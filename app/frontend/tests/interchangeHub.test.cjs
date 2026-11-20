const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { render } = require('svelte/server');
const { componentFunctions, loadTypeScript, serverComponent, srcPath } = require('./svelteTestHelpers.cjs');

const calls = [];
const mockBindings = {
  ImportExportService: new Proxy({}, {
    get: (_, method) => (...args) => {
      calls.push([`main.ImportExportService.${String(method)}`, ...args]);
      return Promise.resolve(null);
    },
  }),
};

const dialogCalls = [];
const mockWailsRuntime = {
  Dialogs: {
    OpenFile(opts) {
      dialogCalls.push(['open', opts]);
      return Promise.resolve('/tmp/picked-source.sqlite');
    },
    SaveFile(opts) {
      dialogCalls.push(['save', opts]);
      return Promise.resolve('/tmp/picked-dest.gpkg');
    },
  },
};

const hub = loadTypeScript('interchangeHub.ts', {
  '../../bindings/github.com/boostao/vpro/app': mockBindings,
  '@wailsio/runtime': mockWailsRuntime,
});

test('validateTargetProjectName rejects None, Sample, master, and non-identifiers', () => {
  assert.deepEqual(JSON.parse(JSON.stringify(hub.validateTargetProjectName('SkeenaImport_2026'))), {
    valid: true,
    normalized: 'SkeenaImport_2026',
    error: '',
  });
  assert.equal(hub.validateTargetProjectName('Sample').valid, false);
  assert.equal(hub.validateTargetProjectName('None').valid, false);
  assert.equal(hub.validateTargetProjectName('BECMasterClone').valid, false);
  assert.equal(hub.validateTargetProjectName('99Invalid').valid, false);
});

test('validateXMLSnippetChunked yields cooperatively across chunks and aborts when cancelled mid-yield', async () => {
  // Single-plot <Plot_package> must count strictly 1 <Plot>, never matching <Plot_package> or <Plots>, even across tiny chunk boundaries
  const singlePkg = '<Plot_package><Plots><Plot releve_nr="1"><header_data><standard_record releve_nr="1"/></header_data></Plot></Plots></Plot_package>';
  const singleRes = await hub.validateXMLSnippetChunked(singlePkg, 7, async () => {});
  assert.equal(singleRes.valid, true);
  assert.equal(singleRes.plotTagCount, 1);

  const nonPkgTags = await hub.validateXMLSnippetChunked('<Plot_package><Releve id="1"/><tblPlotData/></Plot_package>', 16, async () => {});
  assert.equal(nonPkgTags.valid, true);
  assert.equal(nonPkgTags.plotTagCount, 0);

  let yields = 0;
  const bigXml = '<Plot_package><Plots>' + '<Plot releve_nr="1"><header_data/></Plot>'.repeat(120) + '</Plots></Plot_package>';
  const ok = await hub.validateXMLSnippetChunked(
    bigXml,
    512,
    async () => {
      yields++;
    },
    () => false
  );
  assert.equal(ok.valid, true);
  assert.equal(ok.plotTagCount, 120);
  assert.ok(yields >= 8, `expected multiple chunk yields, got ${yields}`);

  // Held yield released after remount/cancel: must reject and never produce stale state
  let releaseGate;
  const gate = new Promise((resolve) => {
    releaseGate = resolve;
  });
  let cancelled = false;
  const pending = hub.validateXMLSnippetChunked(
    bigXml,
    512,
    () => gate,
    () => cancelled
  );
  cancelled = true;
  releaseGate();
  await assert.rejects(pending, /cancelled/);

  // Malformed surrogate in XML is rejected cleanly, whereas a valid astral surrogate pair straddling a chunk boundary succeeds
  const badSurrogate = await hub.validateXMLSnippetChunked('<Plot_package>\uD800</Plot_package>', 512);
  assert.equal(badSurrogate.valid, false);
  assert.match(badSurrogate.error, /surrogate/);

  const straddleAstral = await hub.validateXMLSnippetChunked('<Plot_package>a🌲<Plot releve_nr="1"/></Plot_package>', 16, async () => {});
  assert.equal(straddleAstral.valid, true);
  assert.equal(straddleAstral.plotTagCount, 1);

  // Canonical Alterra Turboveg 3 crosswalk documents 9 = ml (Cryptogam) and 10 = ep (Epiphyte)
  assert.ok(hub.TURBOVEG_LAYER_CROSSWALK.some((cw) => cw.tvGroup.includes('9 = ml')));
  assert.ok(hub.TURBOVEG_LAYER_CROSSWALK.some((cw) => cw.tvGroup.includes('10 = ep')));
});

test('defaultInterchangeHubPort invokes all expected ImportExportService methods via Call.ByName', async () => {
  calls.length = 0;
  await hub.defaultInterchangeHubPort.inspectVenusSource('ctx-1', '/a/venus.mdb');
  await hub.defaultInterchangeHubPort.exportTurboVeg('ctx-1', { format: 'sqlite', destinationPath: '/a/tv.sqlite' });
  await hub.defaultInterchangeHubPort.exportUserSpeciesList('ctx-1', { format: 'json' });
  await hub.defaultInterchangeHubPort.exportLongTidyCSV('ctx-1', {});
  await hub.defaultInterchangeHubPort.exportWideMatrixCSV('ctx-1', { layerMode: 'rollup_all', zeroFill: true, includeSiteUnit: true });
  await hub.defaultInterchangeHubPort.exportProjectRDS('ctx-1', { destinationPath: '/a/out.rds' });
  await hub.defaultInterchangeHubPort.exportGeoPackage('ctx-1', {
    destinationPath: '/a/out.gpkg',
    crs: 'EPSG:3005',
    includeAttributeTables: true,
    includeUnlocatedPlots: false,
  });

  assert.deepEqual(
    calls.map((c) => c[0]),
    [
      'main.ImportExportService.InspectVenusSource',
      'main.ImportExportService.ExportTurboVeg',
      'main.ImportExportService.ExportUserSpeciesList',
      'main.ImportExportService.ExportLongTidyCSV',
      'main.ImportExportService.ExportWideMatrixCSV',
      'main.ImportExportService.ExportProjectRDS',
      'main.ImportExportService.ExportGeoPackage',
    ]
  );
});

test('InterchangeHub.svelte compiles cleanly, contains zero emojis, and renders BC Gov 5-tab workbench', () => {
  const source = readFileSync(srcPath('InterchangeHub.svelte'), 'utf8');
  assert.equal(/\p{Extended_Pictographic}/u.test(source), false);
  assert.doesNotMatch(source, /<p class="error" role="alert">/);
  assert.match(source, /#003366|vpro-navy/);
  assert.match(source, /#fcba19|vpro-gold/i);

  const Component = serverComponent(source, 'InterchangeHub.svelte', {
    './interchangeHub': hub,
    '../shell/notificationService.svelte': { notifications: { push() {}, success() {}, info() {}, warning() {}, error() {} } },
  });
  const rendered = render(Component, { props: { contextId: 'ctx-hub' } });
  assert.match(rendered.body, /data-tour="interchange-hub-root"/);
  assert.match(rendered.body, /VENUS 5\.0/);
  assert.match(rendered.body, /TurboVeg 3 \/ XML/);
  assert.match(rendered.body, /User Species List/);
  assert.match(rendered.body, /GeoPackage \(\.gpkg\)/);
  assert.match(source, /resolveVProCodeSynonyms/);
  assert.match(source, /45\.\.85 N, -170\.\.-100 W/);
});

test('defaultInterchangeHubPort wraps @wailsio/runtime native OS pickers and passes resolveVProCodeSynonyms', async () => {
  dialogCalls.length = 0;
  calls.length = 0;
  const openPicked = await hub.defaultInterchangeHubPort.chooseOpenFile('Choose File', [{ DisplayName: 'All', Pattern: '*.*' }]);
  const savePicked = await hub.defaultInterchangeHubPort.chooseSaveFile('Save File', 'out.gpkg', [{ DisplayName: 'GPKG', Pattern: '*.gpkg' }]);
  assert.equal(openPicked, '/tmp/picked-source.sqlite');
  assert.equal(savePicked, '/tmp/picked-dest.gpkg');
  assert.equal(dialogCalls[0][0], 'open');
  assert.equal(dialogCalls[1][0], 'save');

  await hub.defaultInterchangeHubPort.importTurboVeg('ctx-tv', {
    sourcePath: '/a/tv.xml',
    targetProject: 'TvProj',
    activateOnSuccess: false,
    resolveVProCodeSynonyms: true,
  });
  assert.equal(calls[0][0], 'main.ImportExportService.ImportTurboVeg');
  assert.equal(calls[0][2].resolveVProCodeSynonyms, true);
});

test('InterchangeHub routes all validation and RPC error paths to background notifications while preserving error state', async () => {
  const { createNotificationController } = loadTypeScript('shell/notificationService.svelte.ts', {
    'svelte/store': require('svelte/store'),
  });
  const notifications = createNotificationController({ schedule: () => 0, cancelSchedule: () => {} });
  const host = componentFunctions(
    'InterchangeHub.svelte',
    ['pushHubError', 'setBusy', 'inspectVenus', 'runVenusImport', 'runTurboVegExport', 'runTurboVegImport', 'runRdsExport', 'runGeoPackageExport'],
    {
      contextId: 'ctx-hub',
      busy: false,
      operationHeld: false,
      error: '',
      generation: 0,
      venusSourcePath: '',
      venusInspection: null,
      venusSelectedProject: '',
      venusTargetProject: 'Sample',
      venusDestinationPath: '',
      venusActivate: false,
      tvExportFormat: 'sqlite',
      tvExportPath: '',
      tvExportLump: '',
      tvImportPath: '',
      tvImportFormat: '',
      tvImportTarget: '99Invalid',
      tvImportDestPath: '',
      tvImportActivate: false,
      tvResolveSynonyms: false,
      rdsDestPath: '',
      gpkgDestPath: '',
      validateTargetProjectName: hub.validateTargetProjectName,
      onBusyChange() {},
      notifications,
      port: {
        inspectVenusSource: async () => { throw new Error('bad mdb header'); },
      },
    },
  );

  await host.actions.inspectVenus();
  assert.match(host.error, /Enter a VENUS 5\.0/);
  host.venusSourcePath = '/tmp/broken.mdb';
  await host.actions.inspectVenus();
  assert.match(host.error, /bad mdb header/);
  await host.actions.runVenusImport();
  await host.actions.runTurboVegExport();
  await host.actions.runTurboVegImport();
  await host.actions.runRdsExport();
  await host.actions.runGeoPackageExport();

  const entries = notifications.getSnapshot().entries;
  assert.equal(entries.length, 7);
  assert.ok(entries.every(item => item.severity === 'error' && item.category === 'background' && item.source === 'Interchange Hub'));
});

test('InterchangeHub cancelOperation invokes Wails promise .cancel(), suppresses post-cancel error toasts, and fences subsequent exports', async () => {
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

  function makeCancellableRpc(onCancelRejectError) {
    let settleReject;
    let settleResolve;
    let cancelCalls = 0;
    const p = new Promise((resolve, reject) => {
      settleResolve = resolve;
      settleReject = reject;
    });
    p.cancel = () => {
      cancelCalls++;
      const cancelErr = onCancelRejectError();
      settleReject(cancelErr);
    };
    return {
      promise: p,
      getCancelCalls: () => cancelCalls,
      resolve: (v) => settleResolve(v),
      reject: (e) => settleReject(e),
    };
  }

  const notifications = createNotificationController({ schedule: () => 0, cancelSchedule: () => {} });
  const busyTransitions = [];
  const rpcRequests = new readRequestsMod.ReadRequests();

  let activeMock = null;
  const host = componentFunctions(
    'InterchangeHub.svelte',
    [
      'pushHubError',
      'setBusy',
      'cancelOperation',
      'runLongCsvExport',
      'runWideCsvExport',
      'runRdsExport',
      'runGeoPackageExport',
      'runTurboVegExport',
    ],
    {
      $state: { snapshot: (v) => structuredClone(v) },
      contextId: 'ctx-cancel',
      busy: false,
      operationHeld: false,
      error: '',
      generation: 0,
      activeRpc: null,
      rpcRequests,
      csvLumpTable: '',
      longCsvDest: '/tmp/bec_long.csv',
      wideCsvDest: '/tmp/bec_wide.csv',
      wideLayerMode: 'rollup_all',
      wideZeroFill: true,
      wideIncludeSiteUnit: true,
      csvOutcome: null,
      rdsDestPath: '/tmp/bec.rds',
      rdsOutcome: null,
      gpkgDestPath: '/tmp/bec.gpkg',
      gpkgCrs: 'EPSG:3005',
      gpkgIncludeAttributes: true,
      gpkgIncludeUnlocated: false,
      gpkgLumpTable: '',
      gpkgOutcome: null,
      tvExportFormat: 'sqlite',
      tvExportPath: '/tmp/bec_tv.sqlite',
      tvExportLump: '',
      tvExportOutcome: null,
      notifications,
      onBusyChange(next) {
        busyTransitions.push(next);
      },
      port: {
        exportLongTidyCSV: () => activeMock.promise,
        exportWideMatrixCSV: () => activeMock.promise,
        exportProjectRDS: () => activeMock.promise,
        exportGeoPackage: () => activeMock.promise,
        exportTurboVeg: () => activeMock.promise,
      },
    }
  );

  // 1. Cancel each export format in-flight: must call .cancel() exactly once, clear busy immediately,
  //    register expectedReadCancellation for Wails v3.1.0, and emit 0 error toasts.
  for (const actionName of [
    'runLongCsvExport',
    'runWideCsvExport',
    'runRdsExport',
    'runGeoPackageExport',
    'runTurboVegExport',
  ]) {
    activeMock = makeCancellableRpc(() => new MockRuntimeError('context canceled'));
    const runPromise = host.actions[actionName]();
    assert.equal(host.busy, true, `${actionName} should mark hub busy while in flight`);

    host.actions.cancelOperation();
    assert.equal(host.busy, false, `${actionName} should clear busy immediately on Cancel`);
    assert.equal(activeMock.getCancelCalls(), 1, `${actionName} must invoke .cancel() once on active RPC`);
    assert.equal(
      readRequestsMod.expectedReadCancellation(
        new MockCancelledRejectionError(activeMock.promise, new MockRuntimeError('context canceled'))
      ),
      true,
      `${actionName} cancelled promise should suppress Wails CancelledRejectionError`
    );

    await runPromise;
    assert.equal(host.error, '', `${actionName} cancel must not surface error text`);
    assert.equal(notifications.getSnapshot().entries.length, 0, `${actionName} cancel must not push error toast`);
  }

  // 2. Immediately starting a fresh export after cancelling a stalled one must succeed cleanly
  //    even if the cancelled promise settles after the new export begins.
  let deferredRejectFirst;
  const firstPromise = new Promise((_, reject) => {
    deferredRejectFirst = reject;
  });
  let firstCancelled = 0;
  firstPromise.cancel = () => {
    firstCancelled++;
  };
  activeMock = { promise: firstPromise };
  const firstRun = host.actions.runLongCsvExport();
  assert.equal(host.busy, true);

  host.actions.cancelOperation();
  assert.equal(firstCancelled, 1);
  assert.equal(host.busy, false);

  const secondMock = makeCancellableRpc(() => new Error('unexpected'));
  activeMock = secondMock;
  const secondRun = host.actions.runLongCsvExport();
  assert.equal(host.busy, true);

  // Late rejection from first cancelled RPC arrives while second export is still running:
  deferredRejectFirst(new MockRuntimeError('context canceled'));
  await firstRun;
  assert.equal(host.busy, true, 'late rejection of cancelled RPC must not clear busy of second export');
  assert.equal(host.error, '');

  const expectedCsvOutcome = {
    mode: 'long_tidy',
    rowCount: 42,
    plotCount: 10,
    speciesCount: 6,
    columnCount: 9,
    path: '/tmp/bec_long.csv',
    sha256: 'abc123',
    previewCsv: 'PlotNumber,SiteUnit\n00337,CWHvm1/01\n',
  };
  secondMock.resolve(expectedCsvOutcome);
  await secondRun;

  assert.equal(host.busy, false);
  assert.deepEqual(host.csvOutcome, expectedCsvOutcome);
  assert.equal(notifications.getSnapshot().entries.length, 0);
  assert.equal(busyTransitions.at(-1), false);
});

test('InterchangeHub plain-language error formatting strips RuntimeError, lstat syscalls, SQLite jargon, and picture selection (UX-IMPORT-003)', () => {
  assert.doesNotMatch(
    hub.formatInterchangeError(
      'RuntimeError: resolve Access database "/tmp/does_not_exist.accdb": lstat /tmp/does_not_exist.accdb: no such file or directory'
    ),
    /RuntimeError|lstat|no such file or directory/
  );
  assert.match(
    hub.formatInterchangeError('RuntimeError: picture selection requires its live native request window'),
    /File selection requires an active desktop window/
  );
  assert.match(
    hub.formatInterchangeError('RuntimeError: database disk image is malformed'),
    /damaged, incomplete, or not a valid SQLite file/
  );
  assert.match(
    hub.formatInterchangeError('RuntimeError: decode <Plot> #1: XML syntax error on line 1: unexpected EOF'),
    /invalid XML formatting on line 1/
  );
  assert.doesNotMatch(
    hub.formatInterchangeError('RuntimeError: lump table Missing_Lump not found: sql: no rows in result set'),
    /RuntimeError|sql: no rows in result set/
  );

  const { createNotificationController } = loadTypeScript('shell/notificationService.svelte.ts', {
    'svelte/store': require('svelte/store'),
  });
  const notifications = createNotificationController({ schedule: () => 0, cancelSchedule: () => {} });
  const host = componentFunctions('InterchangeHub.svelte', ['pushHubError'], {
    error: '',
    notifications,
  });
  host.actions.pushHubError(
    'TurboVeg import failed',
    'RuntimeError: decode <Plot> #1: XML syntax error on line 1: unexpected EOF'
  );
  assert.doesNotMatch(host.error, /RuntimeError|unexpected EOF/);
  assert.match(host.error, /invalid XML formatting on line 1/);
  assert.equal(notifications.getSnapshot().entries[0].message, host.error);
});

test('InterchangeHub replaces free-text lump inputs with discovered *_Lump selectors and passes cross-DB lumpDbPath (UX-IMPORT-004)', async () => {
  const source = [
    'InterchangeHub.svelte',
    'InterchangeTurboVegTab.svelte',
    'InterchangeDataExportsTab.svelte',
    'InterchangeGeoPackageTab.svelte',
  ]
    .map(f => readFileSync(srcPath(f), 'utf8'))
    .join('\n');
  assert.doesNotMatch(source, /<input[^>]*bind:value=\{(?:tvExportLump|csvLumpTable|gpkgLumpTable)\}/);
  assert.match(source, /data-lump-select="turboveg"/);
  assert.match(source, /data-lump-select="analytics"/);
  assert.match(source, /data-lump-select="rds"/);
  assert.match(source, /data-lump-select="geopackage"/);
  assert.match(source, /None \(raw unlumped species\)/);

  calls.length = 0;
  await hub.defaultInterchangeHubPort.discoverLumpTables('ctx-lump', ['/tmp/External.db']);
  assert.equal(calls[0][0], 'main.ImportExportService.DiscoverLumpTables');
  assert.equal(calls[0][1], 'ctx-lump');
  assert.deepEqual(calls[0][2], ['/tmp/External.db']);

  const discoveredFixture = [
    {
      name: 'EdgeCaseQA',
      tableName: 'EdgeCaseQA_Lump',
      databasePath: '/data/projects/EdgeCaseQA.db',
      isActiveProject: true,
      metadataVersion: 'VP05',
      rowCount: 18,
      activeCount: 15,
      distinctLumpCodes: 9,
    },
    {
      name: 'Sample',
      tableName: 'Sample_Lump',
      databasePath: '/data/projects/Sample.db',
      isActiveProject: false,
      metadataVersion: 'VP05',
      rowCount: 24,
      activeCount: 20,
      distinctLumpCodes: 11,
    },
  ];

  const exportPayloads = [];
  const host = componentFunctions(
    'InterchangeHub.svelte',
    [
      'lumpDatabaseBaseName',
      'lumpOptionValue',
      'formatLumpOptionLabel',
      'selectedLumpOptionKey',
      'applySelectedLumpOption',
      'refreshDiscoveredLumpTables',
      'browseExternalLumpDatabase',
      'pickFilePath',
      'pushHubError',
      'setBusy',
      'runLongCsvExport',
      'runWideCsvExport',
      'runRdsExport',
      'runTurboVegExport',
      'runGeoPackageExport',
    ],
    {
      $state: { snapshot: (v) => structuredClone(v) },
      defaultInterchangeHubPort: hub.defaultInterchangeHubPort,
      contextId: 'ctx-lump',
      busy: false,
      operationHeld: false,
      error: '',
      generation: 0,
      lumpDiscoveryGen: 0,
      discoveredLumpTables: [],
      externalLumpDbPaths: [],
      tvExportFormat: 'sqlite',
      tvExportPath: '/tmp/out.sqlite',
      tvExportLump: '',
      tvExportLumpDbPath: '',
      tvExportOutcome: null,
      csvLumpTable: '',
      csvLumpDbPath: '',
      longCsvDest: '/tmp/long.csv',
      wideCsvDest: '/tmp/wide.csv',
      wideLayerMode: 'rollup_all',
      wideZeroFill: true,
      wideIncludeSiteUnit: true,
      csvOutcome: null,
      rdsDestPath: '/tmp/out.rds',
      rdsOutcome: null,
      gpkgDestPath: '/tmp/out.gpkg',
      gpkgCrs: 'EPSG:3005',
      gpkgIncludeAttributes: true,
      gpkgIncludeUnlocated: false,
      gpkgLumpTable: '',
      gpkgLumpDbPath: '',
      gpkgOutcome: null,
      onBusyChange() {},
      port: {
        discoverLumpTables: async (_cid, extras) =>
          extras && extras.includes('/ext/Regional.db')
            ? [
                ...discoveredFixture,
                {
                  name: 'Regional2026',
                  tableName: 'Regional2026_Lump',
                  databasePath: '/ext/Regional.db',
                  isActiveProject: false,
                  metadataVersion: 'VP05',
                  rowCount: 8,
                  activeCount: 8,
                  distinctLumpCodes: 4,
                },
              ]
            : discoveredFixture,
        chooseOpenFile: async () => '/ext/Regional.db',
        exportLongTidyCSV: async (_cid, req) => {
          exportPayloads.push(['long', req]);
          return { mode: 'long_tidy', rowCount: 1, plotCount: 1, speciesCount: 1, columnCount: 9, sha256: 'x', previewCsv: '' };
        },
        exportWideMatrixCSV: async (_cid, req) => {
          exportPayloads.push(['wide', req]);
          return { mode: 'wide_matrix', rowCount: 1, plotCount: 1, speciesCount: 1, columnCount: 2, sha256: 'x', previewCsv: '' };
        },
        exportProjectRDS: async (_cid, req) => {
          exportPayloads.push(['rds', req]);
          return { path: '/tmp/out.rds', sha256: 'x', byteSize: 10, plotCount: 1, tables: [] };
        },
        exportTurboVeg: async (_cid, req) => {
          exportPayloads.push(['tv', req]);
          return { format: 'sqlite', path: '/tmp/out.sqlite', sha256: 'x', plotCount: 1, speciesCount: 1, observationCount: 1 };
        },
        exportGeoPackage: async (_cid, req) => {
          exportPayloads.push(['gpkg', req]);
          return {
            path: '/tmp/out.gpkg',
            sha256: 'x',
            crs: 'EPSG:3005',
            srsId: 3005,
            featureCount: 1,
            locatedPlotCount: 1,
            skippedUnlocatedCount: 0,
            normalizedWestLongitudes: 0,
            attributeTables: ['veg'],
          };
        },
      },
    }
  );

  await host.actions.refreshDiscoveredLumpTables();
  assert.equal(host.discoveredLumpTables.length, 2);
  assert.equal(host.actions.formatLumpOptionLabel(host.discoveredLumpTables[0]), 'EdgeCaseQA_Lump (15 active rules)');
  assert.equal(host.actions.formatLumpOptionLabel(host.discoveredLumpTables[1]), 'Sample_Lump (Sample.db · 20 active rules)');

  // Selecting Sample_Lump while EdgeCaseQA is active populates both lumpTable and lumpDbPath across exports!
  host.actions.applySelectedLumpOption('csv', 'Sample_Lump');
  host.actions.applySelectedLumpOption('tv', 'Sample_Lump');
  host.actions.applySelectedLumpOption('gpkg', 'EdgeCaseQA_Lump');
  assert.equal(host.csvLumpTable, 'Sample_Lump');
  assert.equal(host.csvLumpDbPath, '/data/projects/Sample.db');
  assert.equal(host.gpkgLumpTable, 'EdgeCaseQA_Lump');
  assert.equal(host.gpkgLumpDbPath, '');

  await host.actions.runLongCsvExport();
  await host.actions.runWideCsvExport();
  await host.actions.runRdsExport();
  await host.actions.runTurboVegExport();
  await host.actions.runGeoPackageExport();

  assert.equal(exportPayloads[0][1].lumpTable, 'Sample_Lump');
  assert.equal(exportPayloads[0][1].lumpDbPath, '/data/projects/Sample.db');
  assert.equal(exportPayloads[1][1].lumpDbPath, '/data/projects/Sample.db');
  assert.equal(exportPayloads[2][1].lumpDbPath, '/data/projects/Sample.db');
  assert.equal(exportPayloads[3][1].lumpDbPath, '/data/projects/Sample.db');
  assert.equal(exportPayloads[4][1].lumpTable, 'EdgeCaseQA_Lump');
  assert.equal('lumpDbPath' in exportPayloads[4][1], false);

  // Attaching an external .db via From .db... discovers and selects its lump table automatically.
  await host.actions.browseExternalLumpDatabase('gpkg');
  assert.equal(host.gpkgLumpTable, 'Regional2026_Lump');
  assert.equal(host.gpkgLumpDbPath, '/ext/Regional.db');
});
