const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync } = require('node:fs');
const { compile } = require('svelte/compiler');
const { componentFunctions, loadTypeScript, srcPath } = require('./svelteTestHelpers.cjs');

test('WorkspaceSidebar Access Import Wizard compiles with zero warnings, zero emojis, progress bar, and Cancel button (UX-IMPORT-002)', () => {
  const { readSidebarComposite } = require('./svelteTestHelpers.cjs');
  const sidebarSrc = readFileSync(srcPath('shell/WorkspaceSidebar.svelte'), 'utf8');
  const compositeSrc = readSidebarComposite();
  assert.equal(/\p{Extended_Pictographic}/u.test(compositeSrc), false);
  assert.deepEqual(compile(sidebarSrc, { filename: 'WorkspaceSidebar.svelte', generate: 'client' }).warnings, []);
  assert.deepEqual(compile(sidebarSrc, { filename: 'WorkspaceSidebar.svelte', generate: 'server' }).warnings, []);
  assert.match(compositeSrc, /data-access-import-progress/);
  assert.match(compositeSrc, /<progress/);
  assert.match(compositeSrc, /id="cancel-access-import-btn"/);
  assert.match(compositeSrc, /Cancel import/);
  assert.match(compositeSrc, /Cancel inspection/);
});

test('Access Import Wizard streams live progress updates and cancels cleanly via Wails $CancellablePromise.cancel() (UX-IMPORT-002)', async () => {
  const { createNotificationController } = loadTypeScript('shell/notificationService.svelte.ts', {
    'svelte/store': require('svelte/store'),
  });
  class MockRuntimeError extends Error {
    constructor(msg) {
      super(msg);
      this.name = 'RuntimeError';
    }
  }
  class MockCancelledRejectionError extends Error {
    constructor(promise, cause) {
      super('Unhandled rejection in cancelled promise.');
      this.name = 'CancelledRejectionError';
      this.promise = promise;
      this.cause = cause;
    }
  }
  const readRequestsMod = loadTypeScript('shared/readRequests.ts', {
    '@wailsio/runtime': {
      Call: { RuntimeError: MockRuntimeError },
      CancelledRejectionError: MockCancelledRejectionError,
    },
  });

  let settleReject;
  let cancelCount = 0;
  const importPromise = new Promise((_, reject) => {
    settleReject = reject;
  });
  importPromise.cancel = () => {
    cancelCount++;
    settleReject(new MockRuntimeError('context canceled'));
  };

  let progressListener = null;
  let listenerUnsubscribed = 0;
  const notifications = createNotificationController({ schedule: () => 0, cancelSchedule: () => {} });
  const accessRequests = new readRequestsMod.ReadRequests();

  const host = componentFunctions(
    'WorkspaceSidebar.svelte',
    [
      'formatSidebarError',
      'isCancelledAccessError',
      'clearAccessRuntimeTimersAndListeners',
      'startAccessElapsedTimer',
      'attachAccessProgressListener',
      'cancelAccessOperation',
      'runAccessProjectImport',
    ],
    {
      $projectState: { contextId: 'ctx-import-1' },
      projectState: { set() {} },
      notifications,
      accessRequests,
      accessGeneration: 0,
      activeAccessRpc: null,
      stopAccessProgressEvents: null,
      accessElapsedTimer: null,
      accessWorking: false,
      accessOperation: '',
      accessProgressPhase: '',
      accessProgressMessage: '',
      accessProgressRows: 0,
      accessProgressExpectedRows: 0,
      accessElapsedSeconds: 0,
      accessStatusNotice: '',
      accessError: '',
      accessResult: null,
      accessInspection: {
        sourcePath: '/legacy/BECMaster_fixing.accdb',
        sourceSha256: 'abc',
        projects: [],
      },
      accessSelectedSourceProject: 'BECMaster_fixing',
      accessTargetProject: 'BECFixingQA',
      accessDestinationPath: '/tmp/BECFixingQA.db',
      accessActivateOnSuccess: true,
      accessSelectedCandidate: {
        sourceProject: 'BECMaster_fixing',
        compatible: true,
        tables: [
          { suffix: 'Env', present: true, rowCount: 71567 },
          { suffix: 'Veg', present: true, rowCount: 1651726 },
        ],
      },
      requestTransition: async (run) => run('ctx-import-1'),
      onAccessActivated: async () => {},
      subscribeAccessProgress: async (handler) => {
        progressListener = handler;
        return () => {
          listenerUnsubscribed++;
        };
      },
      ImportExportService: {
        ImportAccessProject: () => importPromise,
      },
    }
  );

  const running = host.actions.runAccessProjectImport({ preventDefault() {} });
  // Flush microtasks so attachAccessProgressListener resolves and ImportAccessProject starts.
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(host.accessWorking, true);
  assert.equal(host.accessOperation, 'import');
  assert.equal(host.accessProgressExpectedRows, 71567 + 1651726);
  assert.equal(typeof progressListener, 'function');

  progressListener({
    contextId: 'ctx-import-1',
    operation: 'import',
    phase: 'streaming',
    sourceTable: 'BECMaster_fixing_Veg',
    targetTable: 'BECFixingQA_Veg',
    tableRowsProcessed: 500000,
    totalRowsProcessed: 571567,
    message: 'Importing BECMaster_fixing_Veg…',
  });
  assert.equal(host.accessProgressMessage, 'Importing BECMaster_fixing_Veg…');
  assert.equal(host.accessProgressRows, 571567);

  // User clicks Cancel mid-import:
  host.actions.cancelAccessOperation(false);
  assert.equal(host.accessWorking, false);
  assert.equal(cancelCount, 1);
  assert.equal(listenerUnsubscribed, 1);
  assert.equal(
    readRequestsMod.expectedReadCancellation(
      new MockCancelledRejectionError(importPromise, new MockRuntimeError('context canceled'))
    ),
    true
  );

  await running;
  assert.equal(host.accessError, '');
  assert.match(host.accessStatusNotice, /Import cancelled/);
  assert.equal(notifications.getSnapshot().entries.length, 0);
});

test('Access Import Wizard sanitizes RuntimeError, picture selection, lstat, and C bridge errors into plain language (UX-IMPORT-003)', async () => {
  const { createNotificationController } = loadTypeScript('shell/notificationService.svelte.ts', {
    'svelte/store': require('svelte/store'),
  });
  const notifications = createNotificationController({ schedule: () => 0, cancelSchedule: () => {} });

  let inspectErrorToThrow = null;
  const host = componentFunctions(
    'WorkspaceSidebar.svelte',
    [
      'formatSidebarError',
      'isCancelledAccessError',
      'clearAccessRuntimeTimersAndListeners',
      'startAccessElapsedTimer',
      'attachAccessProgressListener',
      'applyAccessCandidate',
      'browseAccessDatabase',
      'inspectAccessSource',
    ],
    {
      $projectState: { contextId: 'ctx-err' },
      notifications,
      accessGeneration: 0,
      activeAccessRpc: null,
      stopAccessProgressEvents: null,
      accessElapsedTimer: null,
      accessWorking: false,
      accessOperation: '',
      accessProgressPhase: '',
      accessProgressMessage: '',
      accessProgressRows: 0,
      accessProgressExpectedRows: 0,
      accessElapsedSeconds: 0,
      accessSourcePath: '/tmp/does_not_exist_qa1117.accdb',
      accessInspection: null,
      accessSelectedSourceProject: '',
      accessTargetProject: '',
      accessDestinationPath: '',
      accessStatusNotice: '',
      accessError: '',
      accessResult: null,
      subscribeAccessProgress: () => () => {},
      ImportExportService: {
        ChooseAccessDatabaseFile: async () => {
          throw new Error('RuntimeError: picture selection requires its live native request window');
        },
        InspectAccessDatabase: async () => {
          throw inspectErrorToThrow;
        },
      },
    }
  );

  await host.actions.browseAccessDatabase();
  assert.doesNotMatch(host.accessError, /RuntimeError|picture selection/);
  assert.match(host.accessError, /File selection requires an active desktop window/);

  inspectErrorToThrow = new Error(
    'RuntimeError: resolve Access database "/tmp/does_not_exist_qa1117.accdb": lstat /tmp/does_not_exist_qa1117.accdb: no such file or directory'
  );
  await host.actions.inspectAccessSource('/tmp/does_not_exist_qa1117.accdb');
  assert.doesNotMatch(host.accessError, /RuntimeError|lstat|no such file or directory/);
  assert.match(host.accessError, /was not found/);

  inspectErrorToThrow = new Error('RuntimeError: Access source read error');
  await host.actions.inspectAccessSource('/tmp/truncated.accdb');
  assert.doesNotMatch(host.accessError, /RuntimeError|Access source read error/);
  assert.match(host.accessError, /could not be read/);

  for (const entry of notifications.getSnapshot().entries) {
    assert.doesNotMatch(entry.message, /RuntimeError|lstat|picture selection|Access source read error/);
  }
});
