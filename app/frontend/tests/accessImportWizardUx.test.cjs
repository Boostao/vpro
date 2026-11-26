const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync } = require('node:fs');
const { compile } = require('svelte/compiler');
const { componentFunctions, loadTypeScript, srcPath } = require('./svelteTestHelpers.cjs');

test('WorkspaceSidebar unified Attach & Access auto-convert compiles with zero warnings, zero emojis, progress bar, and Cancel button (UX-IMPORT-002)', () => {
  const { readSidebarComposite } = require('./svelteTestHelpers.cjs');
  const sidebarSrc = readFileSync(srcPath('shell/WorkspaceSidebar.svelte'), 'utf8');
  const compositeSrc = readSidebarComposite();
  assert.equal(/\p{Extended_Pictographic}/u.test(compositeSrc), false);
  assert.deepEqual(compile(sidebarSrc, { filename: 'WorkspaceSidebar.svelte', generate: 'client' }).warnings, []);
  assert.deepEqual(compile(sidebarSrc, { filename: 'WorkspaceSidebar.svelte', generate: 'server' }).warnings, []);
  assert.match(sidebarSrc, /data-ws-attach-progress/);
  assert.match(sidebarSrc, /<progress/);
  assert.match(sidebarSrc, /data-ws-attach-cancel/);
  assert.match(
    sidebarSrc,
    /This Microsoft Access file will be converted to a VPro database \(\.db\) and attached to your Work Space\./
  );
  assert.doesNotMatch(sidebarSrc, /id="access-import-wizard"/);
});

test('WorkspaceSidebar unified Access auto-convert streams live progress updates and cancels cleanly via ReadRequests (UX-IMPORT-002)', async () => {
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
  const sidebarOps = loadTypeScript('shell/workspaceSidebarOps.ts', {
    '../shared/readRequests': readRequestsMod,
    './notificationService.svelte': { notifications: createNotificationController({ schedule: () => 0, cancelSchedule: () => {} }) },
  });

  let settleReject;
  let cancelCount = 0;
  const attachPromise = new Promise((_, reject) => {
    settleReject = reject;
  });
  attachPromise.cancel = () => {
    cancelCount++;
    settleReject(new MockRuntimeError('context canceled'));
  };

  let progressListener = null;
  let listenerUnsubscribed = 0;
  const notifications = createNotificationController({ schedule: () => 0, cancelSchedule: () => {} });
  const attachRequests = new readRequestsMod.ReadRequests();

  const host = componentFunctions(
    'WorkspaceSidebar.svelte',
    ['clearAttachProgress', 'cancelAttachOperation', 'startAttachProgress', 'executeAttach'],
    {
      $projectState: { contextId: 'ctx-import-1' },
      projectState: { set() {} },
      notifications,
      attachRequests,
      attachGeneration: 0,
      stopAttachProgress: null,
      attachTimer: null,
      workspaceWorking: false,
      attachProgressPhase: '',
      attachProgressMessage: '',
      attachProgressRows: 0,
      attachProgressExpectedRows: 0,
      attachElapsedSeconds: 0,
      sidebarNotice: '',
      sidebarError: '',
      pendingAttach: {
        kind: 'project',
        requiresConvert: true,
        selectedName: 'BECMaster_fixing',
        candidates: [{ name: 'BECMaster_fixing', label: 'BECMaster_fixing', compatible: true }],
        inspection: {
          selectedPath: '/legacy/BECMaster_fixing.accdb',
          fileKind: 'access',
          requiresConvert: true,
          accessInspection: {
            sourcePath: '/legacy/BECMaster_fixing.accdb',
            projects: [
              {
                sourceProject: 'BECMaster_fixing',
                compatible: true,
                tables: [
                  { suffix: 'Env', present: true, rowCount: 71567 },
                  { suffix: 'Veg', present: true, rowCount: 1651726 },
                ],
              },
            ],
          },
        },
      },
      runAttachWorkspaceResourceOp: sidebarOps.runAttachWorkspaceResourceOp,
      isCancelledAccessErrorOp: sidebarOps.isCancelledAccessErrorOp,
      formatSidebarErrorOp: sidebarOps.formatSidebarErrorOp,
      workspaceKindLabel: sidebarOps.workspaceKindLabel,
      requestTransition: async (run) => run('ctx-import-1'),
      onAccessActivated: async () => {},
      subscribeAccessProgress: async (handler) => {
        progressListener = handler;
        return () => {
          listenerUnsubscribed++;
        };
      },
      ContextService: {
        AttachWorkspaceResource: () => attachPromise,
      },
    }
  );

  const running = host.actions.executeAttach('project', '/legacy/BECMaster_fixing.accdb', 'BECMaster_fixing', true);
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(host.workspaceWorking, true);
  assert.equal(host.attachProgressExpectedRows, 71567 + 1651726);
  assert.equal(typeof progressListener, 'function');

  progressListener({
    contextId: 'ctx-import-1',
    operation: 'import',
    phase: 'streaming',
    tableRowsProcessed: 500000,
    totalRowsProcessed: 571567,
    message: 'Importing BECMaster_fixing_Veg…',
  });
  assert.equal(host.attachProgressMessage, 'Importing BECMaster_fixing_Veg…');
  assert.equal(host.attachProgressRows, 571567);

  host.actions.cancelAttachOperation(false);
  assert.equal(host.workspaceWorking, false);
  assert.equal(cancelCount, 1);
  assert.equal(listenerUnsubscribed, 1);
  assert.equal(
    readRequestsMod.expectedReadCancellation(
      new MockCancelledRejectionError(attachPromise, new MockRuntimeError('context canceled'))
    ),
    true
  );

  await running;
  assert.equal(host.sidebarError, '');
  assert.match(host.sidebarNotice, /cancelled/i);
  assert.equal(notifications.getSnapshot().entries.length, 0);
});

test('WorkspaceSidebar sanitizes RuntimeError, picture selection, lstat, and C bridge errors into plain language (UX-IMPORT-003)', async () => {
  const { createNotificationController } = loadTypeScript('shell/notificationService.svelte.ts', {
    'svelte/store': require('svelte/store'),
  });
  const readRequestsMod = loadTypeScript('shared/readRequests.ts', {
    '@wailsio/runtime': {
      Call: { RuntimeError: class extends Error {} },
      CancelledRejectionError: class extends Error {},
    },
  });
  const notifications = createNotificationController({ schedule: () => 0, cancelSchedule: () => {} });
  const sidebarOps = loadTypeScript('shell/workspaceSidebarOps.ts', {
    '../shared/readRequests': readRequestsMod,
    './notificationService.svelte': { notifications },
  });

  let inspectErrorToThrow = null;
  const host = componentFunctions('WorkspaceSidebar.svelte', ['startAttach', 'inspectAttachFile'], {
    $projectState: { contextId: 'ctx-err' },
    controlsDisabled: false,
    attachGeneration: 0,
    attachRequests: new readRequestsMod.ReadRequests(),
    workspaceWorking: false,
    pendingAttach: null,
    pendingRemove: null,
    pendingNew: null,
    sidebarNotice: '',
    sidebarError: '',
    extractAttachCandidates: sidebarOps.extractAttachCandidates,
    requiresAccessConversion: sidebarOps.requiresAccessConversion,
    isCancelledAccessErrorOp: sidebarOps.isCancelledAccessErrorOp,
    formatSidebarErrorOp: sidebarOps.formatSidebarErrorOp,
    workspaceKindLabel: sidebarOps.workspaceKindLabel,
    ContextService: {
      ChooseAttachableFile: async () => {
        throw new Error('RuntimeError: picture selection requires its live native request window');
      },
      InspectAttachableFile: async () => {
        throw inspectErrorToThrow;
      },
    },
  });

  await host.actions.startAttach('project');
  assert.doesNotMatch(host.sidebarError, /RuntimeError|picture selection/);
  assert.match(host.sidebarError, /File selection requires an active desktop window/);

  inspectErrorToThrow = new Error(
    'RuntimeError: resolve Access database "/tmp/does_not_exist_qa1117.accdb": lstat /tmp/does_not_exist_qa1117.accdb: no such file or directory'
  );
  await host.actions.inspectAttachFile('project', '/tmp/does_not_exist_qa1117.accdb');
  assert.doesNotMatch(host.sidebarError, /RuntimeError|lstat|no such file or directory/);
  assert.match(host.sidebarError, /was not found/);

  inspectErrorToThrow = new Error('RuntimeError: Access source read error');
  await host.actions.inspectAttachFile('project', '/tmp/truncated.accdb');
  assert.doesNotMatch(host.sidebarError, /RuntimeError|Access source read error/);
  assert.match(host.sidebarError, /could not be read/);

  for (const entry of notifications.getSnapshot().entries) {
    assert.doesNotMatch(entry.message, /RuntimeError|lstat|picture selection|Access source read error/);
  }
});
