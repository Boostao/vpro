const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const { pathToFileURL } = require('node:url');
const vm = require('node:vm');
const ts = require('typescript');

const FE_ROOT = path.resolve(__dirname, '..');
const REPO_ROOT = path.resolve(FE_ROOT, '..', '..');
const ALLOWLIST_PATH = path.join(REPO_ROOT, 'app', 'resources', 'web_rpc_allowlist.json');
const EMBED_GO_PATH = path.join(REPO_ROOT, 'app', 'resources', 'embed.go');
const GENERATOR_URL = pathToFileURL(path.join(REPO_ROOT, 'scripts', 'generate-web-rpc-map.mjs')).href;

function transpileTs(filePath) {
  const source = readFileSync(filePath, 'utf8');
  return ts.transpileModule(source, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
      esModuleInterop: true,
    },
  }).outputText;
}

function loadWebStack(options = {}) {
  const {
    webReadOnly = true,
    fetchImpl = async () => {
      throw new Error('unexpected fetch');
    },
    documentImpl = undefined,
    windowImpl = undefined,
    sessionStorageImpl = undefined,
  } = options;

  const sandboxBase = {
    URL,
    AbortController,
    EventTarget,
    CustomEvent,
    Error,
    TypeError,
    Promise,
    Object,
    Array,
    Map,
    Set,
    WeakSet,
    Symbol,
    JSON,
    Math,
    Date,
    Uint8Array,
    Number,
    String,
    Boolean,
    encodeURIComponent,
    crypto: globalThis.crypto,
    fetch: fetchImpl,
    document: documentImpl,
    window: windowImpl,
    sessionStorage: sessionStorageImpl,
    __VPRO_WEB_READONLY__: webReadOnly,
  };
  sandboxBase.globalThis = sandboxBase;

  const runModule = (filePath, deps) => {
    const mod = { exports: {} };
    const ctx = {
      ...sandboxBase,
      module: mod,
      exports: mod.exports,
      require(specifier) {
        if (Object.hasOwn(deps, specifier)) {
          return deps[specifier];
        }
        throw new Error(`Unexpected require("${specifier}") in ${path.basename(filePath)}`);
      },
    };
    vm.runInNewContext(transpileTs(filePath), ctx, { filename: filePath });
    return mod.exports;
  };

  const generatedRpcMap = runModule(path.join(FE_ROOT, 'src', 'web', 'generatedRpcMap.ts'), {});
  const runtimeMode = runModule(path.join(FE_ROOT, 'src', 'web', 'runtimeMode.ts'), {});
  const wailsWebRuntime = runModule(path.join(FE_ROOT, 'src', 'web', 'wailsWebRuntime.ts'), {
    './generatedRpcMap': generatedRpcMap,
    './runtimeMode': runtimeMode,
  });
  const readRequests = runModule(path.join(FE_ROOT, 'src', 'shared', 'readRequests.ts'), {
    '@wailsio/runtime': wailsWebRuntime,
  });

  return { generatedRpcMap, runtimeMode, wailsWebRuntime, readRequests };
}

test('allowlist completeness, embed.go exposure, and generatedRpcMap.ts parity', async () => {
  const gen = await import(GENERATOR_URL);
  const allowlist = JSON.parse(readFileSync(ALLOWLIST_PATH, 'utf8'));
  const bindings = gen.parseBindings();
  const built = gen.buildRpcMap(allowlist, bindings);

  assert.equal(bindings.size, 12, 'Expected all 12 Wails services in bindings');
  assert.equal(Object.keys(allowlist.services).length, 12, 'Allowlist must enumerate all 12 services');
  assert.equal(
    readFileSync(gen.OUTPUT_PATH, 'utf8'),
    built.source,
    'generatedRpcMap.ts must match scripts/generate-web-rpc-map.mjs output'
  );

  const embedGo = readFileSync(EMBED_GO_PATH, 'utf8');
  assert.match(embedGo, /\/\/go:embed web_rpc_allowlist\.json/);
  assert.match(embedGo, /var WebRPCAllowlistJSON \[\]byte/);

  const { generatedRpcMap } = loadWebStack();
  assert.equal(Object.keys(generatedRpcMap.WEB_RPC_BY_ID).length, built.counts.total);
  assert.equal(Object.keys(generatedRpcMap.WEB_RPC_BY_NAME).length, built.counts.total);
  assert.ok(built.counts.rpc >= 200, `Expected >= 200 rpc methods, got ${built.counts.rpc}`);
  assert.ok(built.counts.prefs >= 45, `Expected >= 45 prefs methods, got ${built.counts.prefs}`);
  assert.ok(built.counts.download >= 17, `Expected >= 17 download methods, got ${built.counts.download}`);

  // All 17+ required download endpoints must be mapped as kind === 'download'.
  const requiredDownloads = [
    'VegetationReportService.ExportReviewedSummaryVegetationWorkbook',
    'VegetationReportService.ExportReviewedLongVegetationProjectWorkbook',
    'VegetationReportService.ExportReviewedVegetationWorkbook',
    'VegetationReportService.ExportReviewedLifeformWorkbook',
    'EnvironmentReportService.ExportReviewedEnvironmentWorkbook',
    'EnvironmentReportService.ExportReviewedSiteUnitSummaryWorkbook',
    'EnvironmentReportService.ExportReviewedSiteUnitSummaryExtendedWorkbook',
    'EnvironmentReportService.ExportReviewedSubzoneMatrix',
    'EnvironmentReportService.RenderQuartoGuide',
    'ImportExportService.ExportReviewedTableCSVArchive',
    'ImportExportService.ExportReviewedPlotLabelPDF',
    'ImportExportService.ExportGeoPackage',
    'ImportExportService.ExportProjectRDS',
    'ImportExportService.ExportTurboVeg',
    'SpatialService.ExportReviewedGoogleEarthKML',
    'ClassificationService.ExportDiagnosticWorkbook',
    'ClassificationService.ExportUserSiteUnitListCSV',
  ];
  for (const key of requiredDownloads) {
    assert.equal(
      generatedRpcMap.WEB_RPC_BY_NAME[key]?.kind,
      'download',
      `${key} must be allowlisted as kind "download"`
    );
  }

  // Required read-only R sidecar and Validation endpoints.
  for (const key of [
    'EnvironmentReportService.DetectRRuntime',
    'EnvironmentReportService.GetCachedPlotClimate',
    'EnvironmentReportService.ComputePlotClimateAndDualEdatopic',
    'EnvironmentReportService.RunMultivariateClustering',
    'ValidationService.RunComplianceValidation',
    'ValidationService.PreviewOptimizeVeg',
    'ContextService.SwitchContext',
    'SpatialService.SelectPlotsInPolygonAOI',
    'PictureService.GetPictureOptions',
    'PictureService.GetMetadata',
    'PictureService.GetImage',
  ]) {
    assert.equal(generatedRpcMap.WEB_RPC_BY_NAME[key]?.kind, 'rpc', `${key} must be allowlisted as "rpc"`);
  }

  // Required ephemeral session prefs endpoints.
  for (const key of [
    'SpatialService.GetCoordinateMode',
    'SpatialService.SetCoordinateMode',
    'ClassificationService.GetWorkingUnitMode',
    'ClassificationService.SetWorkingUnitMode',
    'VegetationReportService.SaveLongVegetationPreferences',
    'VegetationReportService.SaveSummaryVegetationPreferences',
    'VegetationReportService.SetLongVegetationReportScope',
    'EnvironmentReportService.SaveLongEnvironmentPreferences',
    'EnvironmentReportService.SaveFullSiteUnitSummaryPreferences',
    'SpatialService.SaveGoogleEarthPreferences',
  ]) {
    assert.equal(generatedRpcMap.WEB_RPC_BY_NAME[key]?.kind, 'prefs', `${key} must be allowlisted as "prefs"`);
  }
});

test('fail-closed denylist rejects all mutating, audit, cloud, import, dialog, and PromoteClusterCandidateToSU RPCs', async () => {
  const gen = await import(GENERATOR_URL);
  const bindings = gen.parseBindings();
  const { generatedRpcMap, wailsWebRuntime } = loadWebStack({
    fetchImpl: async () => {
      throw new Error('fetch MUST NOT be called for denied RPCs');
    },
  });

  const forbiddenSamples = [
    ['EnvironmentReportService', 'PromoteClusterCandidateToSU', 'rpc'],
    ['VegetationReportService', 'SaveSummaryVegetationFieldList', 'prefs'],
    ['HelpService', 'ResetWorkspaceToSample', 'rpc'],
    ['LifecycleService', 'ResetStartupToSample', 'rpc'],
    ['LifecycleService', 'RecoverStartupWithPaths', 'rpc'],
    ['LifecycleService', 'GetUserLogReview', 'rpc'],
    ['LifecycleService', 'ChooseStartupDatabaseFile', 'rpc'],
    ['LifecycleService', 'ConfirmClose', 'rpc'],
    ['LifecycleService', 'CancelClose', 'rpc'],
    ['LifecycleService', 'GetPendingCloseRequest', 'rpc'],
    ['PlotEntryService', 'CreatePlot', 'rpc'],
    ['PlotEntryService', 'UpdatePlot', 'rpc'],
    ['PlotEntryService', 'SavePlot', 'rpc'],
    ['PlotEntryService', 'DeleteVegRecord', 'rpc'],
    ['PlotEntryService', 'ListAuditEntries', 'rpc'],
    ['PlotEntryService', 'ListAuditReadEntries', 'rpc'],
    ['PlotEntryService', 'SetAuditStrength', 'prefs'],
    ['PlotEntryService', 'SetCurrentUser', 'prefs'],
    ['PlotEntryService', 'RestoreAuditRecords', 'rpc'],
    ['PlotEntryService', 'UndoSIVICreation', 'rpc'],
    ['PlotEntryService', 'UserAccreditationStatus', 'rpc'],
    ['ContextService', 'SelectProject', 'rpc'],
    ['ContextService', 'SelectSU', 'rpc'],
    ['ContextService', 'SelectHierarchy', 'rpc'],
    ['ContextService', 'GetUserSetup', 'rpc'],
    ['ContextService', 'SetUserName', 'prefs'],
    ['ContextService', 'SubmitProjectToStaging', 'rpc'],
    ['ContextService', 'PullBECMasterSubset', 'rpc'],
    ['ContextService', 'ExecuteStagingToMasterMerge', 'rpc'],
    ['ContextService', 'BootstrapCloudSchemas', 'rpc'],
    ['ContextService', 'GetCloudSyncConfigStatus', 'rpc'],
    ['ContextService', 'RevealInFileExplorer', 'rpc'],
    ['ContextService', 'ExportSplinterProject', 'download'],
    ['ValidationService', 'ApplyOptimizeVeg', 'rpc'],
    ['ValidationService', 'QuarantineOrphanRecords', 'rpc'],
    ['ValidationService', 'ExecuteThreeWayMerge', 'rpc'],
    ['ValidationService', 'ApplySpeciesCodeCheck', 'rpc'],
    ['ImportExportService', 'ImportAccessProject', 'rpc'],
    ['ImportExportService', 'ImportTurboVeg', 'rpc'],
    ['ImportExportService', 'ImportVenusProject', 'rpc'],
    ['ImportExportService', 'MaterializeLumpSpec', 'rpc'],
    ['ImportExportService', 'CreateLumpTable', 'rpc'],
    ['ImportExportService', 'ToggleLumpRow', 'rpc'],
    ['ImportExportService', 'UpsertLumpRow', 'rpc'],
    ['ImportExportService', 'ChooseAccessDatabaseFile', 'rpc'],
    ['SpatialService', 'ApplySpatialAttributes', 'rpc'],
    ['SpatialService', 'AssignSpatialAOIToSU', 'rpc'],
    ['PictureService', 'CreatePicture', 'rpc'],
    ['PictureService', 'DeletePicture', 'rpc'],
    ['PictureService', 'SaveMetadata', 'rpc'],
    ['PictureService', 'SavePictureOptions', 'prefs'],
    ['PictureService', 'ChooseCreationImage', 'rpc'],
    ['ClassificationService', 'AddHierarchyNode', 'rpc'],
    ['ClassificationService', 'RenameHierarchyNode', 'rpc'],
    ['ClassificationService', 'ReparentHierarchyNode', 'rpc'],
    ['ClassificationService', 'DeleteHierarchyNode', 'rpc'],
    ['ClassificationService', 'AssignPlotsToSiteUnit', 'rpc'],
    ['ClassificationService', 'ToggleHierarchyBreakpoint', 'rpc'],
    ['ClassificationService', 'TransferSiteUnitEnvironment', 'rpc'],
    ['ClassificationService', 'UndoSUAssignment', 'rpc'],
    ['ClassificationService', 'ReassignSynthesisPlotUnit', 'rpc'],
    ['DatasheetService', 'ApplyDatasheetEdits', 'rpc'],
    ['DatasheetService', 'InsertDatasheetChildRow', 'rpc'],
    ['DatasheetService', 'DeleteDatasheetChildRow', 'rpc'],
  ];

  for (const [service, method, kind] of forbiddenSamples) {
    const qualified = `${service}.${method}`;
    const denial = gen.checkDenylist(service, method, kind);
    assert.ok(denial, `checkDenylist MUST reject ${qualified}`);
    assert.equal(generatedRpcMap.WEB_RPC_BY_NAME[qualified], undefined, `${qualified} must not be in WEB_RPC_BY_NAME`);

    const bindingId = bindings.get(service)?.get(method);
    assert.equal(typeof bindingId, 'number', `Expected ${qualified} to exist in bindings for ID rejection check`);
    assert.equal(generatedRpcMap.WEB_RPC_BY_ID[bindingId], undefined, `${qualified} (${bindingId}) must not be in WEB_RPC_BY_ID`);

    await assert.rejects(
      wailsWebRuntime.Call.ByID(bindingId, 'ctx'),
      (err) => err instanceof wailsWebRuntime.Call.RuntimeError && /web read-only mode/i.test(err.message)
    );
    await assert.rejects(
      wailsWebRuntime.Call.ByName(`main.${qualified}`, 'ctx'),
      (err) => err instanceof wailsWebRuntime.Call.RuntimeError && /web read-only mode/i.test(err.message)
    );
  }
});

test('Call.ByID and Call.ByName send POST /api/rpc/{service}/{method} with session header and unwrap results', async () => {
  const requests = [];
  const store = new Map();
  const sessionStorageImpl = {
    getItem: (k) => (store.has(k) ? store.get(k) : null),
    setItem: (k, v) => {
      store.set(k, String(v));
    },
  };

  const { generatedRpcMap, runtimeMode, wailsWebRuntime } = loadWebStack({
    webReadOnly: true,
    sessionStorageImpl,
    fetchImpl: async (url, init) => {
      requests.push({ url, init });
      if (url.endsWith('/ContextService/GetState')) {
        return {
          ok: true,
          status: 200,
          statusText: 'OK',
          text: async () => JSON.stringify({ result: { contextId: 'web-ctx-1', project: 'BECMaster' } }),
        };
      }
      if (url.endsWith('/PictureService/GetPictureOptions')) {
        return {
          ok: true,
          status: 200,
          statusText: 'OK',
          text: async () => JSON.stringify({ effectiveLibraryPath: '/readonly/VPics.db' }),
        };
      }
      if (url.endsWith('/SpatialService/SetCoordinateMode')) {
        return {
          ok: true,
          status: 204,
          statusText: 'No Content',
          text: async () => '',
        };
      }
      return {
        ok: false,
        status: 403,
        statusText: 'Forbidden',
        text: async () => JSON.stringify({ error: 'read-only context violation' }),
      };
    },
  });

  assert.equal(runtimeMode.IS_WEB_READONLY, true);
  assert.equal(runtimeMode.isWebReadOnly(), true);
  assert.equal(runtimeMode.getRuntimeMode(), 'web-readonly');
  const sessionId = runtimeMode.getWebSessionId();
  assert.ok(sessionId.length >= 16);
  assert.equal(runtimeMode.getWebSessionId(), sessionId, 'Session ID must remain stable within sessionStorage');

  const getStateEntry = generatedRpcMap.WEB_RPC_BY_NAME['ContextService.GetState'];
  const state = await wailsWebRuntime.Call.ByID(getStateEntry.id);
  assert.deepEqual(state, { contextId: 'web-ctx-1', project: 'BECMaster' });
  assert.equal(requests[0].url, '/api/rpc/ContextService/GetState');
  assert.equal(requests[0].init.method, 'POST');
  assert.equal(requests[0].init.headers['Content-Type'], 'application/json');
  assert.equal(requests[0].init.headers[runtimeMode.WEB_SESSION_HEADER], sessionId);
  assert.equal(requests[0].init.body, JSON.stringify({ args: [] }));

  // Fully qualified Wails main.* name works via Call.ByName.
  const picOpts = await wailsWebRuntime.Call.ByName('main.PictureService.GetPictureOptions');
  assert.deepEqual(picOpts, { effectiveLibraryPath: '/readonly/VPics.db' });
  assert.equal(requests[1].url, '/api/rpc/PictureService/GetPictureOptions');

  // 204 No Content resolves to undefined.
  const setCoordEntry = generatedRpcMap.WEB_RPC_BY_NAME['SpatialService.SetCoordinateMode'];
  const voidRes = await wailsWebRuntime.Call.Call({ methodID: setCoordEntry.id, args: ['dd'] });
  assert.equal(voidRes, undefined);
  assert.equal(requests[2].init.body, JSON.stringify({ args: ['dd'] }));

  // Non-2xx response rejects as Call.RuntimeError with server error message.
  const listPlotsEntry = generatedRpcMap.WEB_RPC_BY_NAME['ContextService.ListPlots'];
  await assert.rejects(
    wailsWebRuntime.Call.ByID(listPlotsEntry.id, 0, 50),
    (err) => err instanceof wailsWebRuntime.RuntimeError && err.message === 'read-only context violation'
  );

  // Desktop mode check when __VPRO_WEB_READONLY__ is false.
  const desktopStack = loadWebStack({ webReadOnly: false });
  assert.equal(desktopStack.runtimeMode.IS_WEB_READONLY, false);
  assert.equal(desktopStack.runtimeMode.getRuntimeMode(), 'desktop');
});

test('AbortController cancellation matches ReadRequests ownership and expectedReadCancellation parity', async () => {
  const capturedSignals = [];
  const { generatedRpcMap, wailsWebRuntime, readRequests } = loadWebStack({
    fetchImpl: (_url, init) => {
      capturedSignals.push(init.signal);
      return new Promise((_resolve, reject) => {
        init.signal.addEventListener('abort', () => {
          const abortErr = new Error('The operation was aborted.');
          abortErr.name = 'AbortError';
          reject(abortErr);
        });
      });
    },
  });

  const listPlotsId = generatedRpcMap.WEB_RPC_BY_NAME['ContextService.ListPlots'].id;
  const reads = new readRequests.ReadRequests();
  const rpcPromise = wailsWebRuntime.Call.ByID(listPlotsId, 0, 100);
  const tracked = reads.track(rpcPromise);

  assert.equal(capturedSignals.length, 1);
  assert.equal(capturedSignals[0].aborted, false);

  reads.cancelAll();
  reads.cancelAll(); // idempotent second call

  assert.equal(capturedSignals[0].aborted, true, 'cancelAll() must abort underlying fetch AbortController');

  await assert.rejects(tracked, (err) => err instanceof wailsWebRuntime.CancelError && err.name === 'CancelError');

  // Verify expectedReadCancellation contract parity with src/shared/readRequests.ts.
  const expectedErr = new wailsWebRuntime.CancelledRejectionError(
    rpcPromise,
    new wailsWebRuntime.Call.RuntimeError('context canceled')
  );
  assert.equal(readRequests.expectedReadCancellation(expectedErr), true);

  const wrongMsgErr = new wailsWebRuntime.CancelledRejectionError(
    rpcPromise,
    new wailsWebRuntime.Call.RuntimeError('database corrupt')
  );
  assert.equal(readRequests.expectedReadCancellation(wrongMsgErr), false);

  const plainErr = new wailsWebRuntime.CancelledRejectionError(rpcPromise, new Error('context canceled'));
  assert.equal(readRequests.expectedReadCancellation(plainErr), false);

  const unownedPromise = wailsWebRuntime.CancellablePromise.withResolvers().promise;
  const unownedErr = new wailsWebRuntime.CancelledRejectionError(
    unownedPromise,
    new wailsWebRuntime.Call.RuntimeError('context canceled')
  );
  assert.equal(readRequests.expectedReadCancellation(unownedErr), false);
});

test('download RPCs trigger browser download and return outcome cleanly, while blocking unsafe URLs', async () => {
  const createdAnchors = [];
  const appended = [];
  const removed = [];

  const documentImpl = {
    body: {
      appendChild(node) {
        appended.push(node);
      },
      removeChild(node) {
        removed.push(node);
      },
    },
    createElement(tag) {
      assert.equal(tag, 'a');
      const node = {
        href: '',
        download: '',
        rel: '',
        style: {},
        clicked: false,
        removed: false,
        click() {
          this.clicked = true;
        },
        remove() {
          this.removed = true;
          removed.push(this);
        },
      };
      createdAnchors.push(node);
      return node;
    },
  };

  const expectedOutcome = {
    contextId: 'web-ctx-1',
    path: 'BECMaster_SummaryVegetation.xlsx',
    sheetCount: 3,
    written: true,
  };

  const { generatedRpcMap, wailsWebRuntime } = loadWebStack({
    documentImpl,
    windowImpl: { location: { origin: 'https://vpro.gov.bc.ca' }, addEventListener() {} },
    fetchImpl: async () => ({
      ok: true,
      status: 200,
      statusText: 'OK',
      text: async () =>
        JSON.stringify({
          outcome: expectedOutcome,
          downloadUrl: '/api/downloads/dl-abc123',
          filename: 'BECMaster_SummaryVegetation.xlsx',
        }),
    }),
  });

  const exportId = generatedRpcMap.WEB_RPC_BY_NAME['VegetationReportService.ExportReviewedSummaryVegetationWorkbook'].id;
  const result = await wailsWebRuntime.Call.ByID(exportId, 'web-ctx-1', '{}');

  assert.deepEqual(result, expectedOutcome);
  assert.equal(createdAnchors.length, 1);
  assert.equal(createdAnchors[0].href, '/api/downloads/dl-abc123');
  assert.equal(createdAnchors[0].download, 'BECMaster_SummaryVegetation.xlsx');
  assert.equal(createdAnchors[0].rel, 'noopener');
  assert.equal(createdAnchors[0].clicked, true);
  assert.equal(createdAnchors[0].removed, true);
  assert.equal(appended.length, 1);
  assert.equal(removed.length, 1);

  // Unsafe URLs must be rejected without creating an anchor element.
  assert.equal(wailsWebRuntime.triggerBrowserDownload('javascript:alert(1)', 'x.txt'), false);
  assert.equal(wailsWebRuntime.triggerBrowserDownload('data:text/html,<script>1</script>', 'x.html'), false);
  assert.equal(wailsWebRuntime.triggerBrowserDownload('//evil.example/a.xlsx', 'a.xlsx'), false);
  assert.equal(wailsWebRuntime.triggerBrowserDownload('https://evil.example/a.xlsx', 'a.xlsx'), false);
  assert.equal(createdAnchors.length, 1);

  // Same-origin https and blob URLs are permitted.
  assert.equal(wailsWebRuntime.triggerBrowserDownload('https://vpro.gov.bc.ca/api/downloads/ok.pdf', 'ok.pdf'), true);
  assert.equal(wailsWebRuntime.triggerBrowserDownload('blob:https://vpro.gov.bc.ca/123', 'blob.csv'), true);
  assert.equal(createdAnchors.length, 3);
});

test('Events, Dialogs, Create shims and vite.web.config.ts invariants', async () => {
  const { wailsWebRuntime } = loadWebStack();

  // Events in-memory EventTarget behavior.
  const received = [];
  const off = wailsWebRuntime.Events.On('vpro:test', (ev) => {
    assert.ok(ev instanceof wailsWebRuntime.WailsEvent);
    received.push(ev.data);
  });
  let onceCount = 0;
  wailsWebRuntime.Events.Once('vpro:test', () => {
    onceCount += 1;
  });
  await wailsWebRuntime.Events.Emit('vpro:test', { n: 1 });
  await wailsWebRuntime.Events.Emit('vpro:test', { n: 2 });
  off();
  await wailsWebRuntime.Events.Emit('vpro:test', { n: 3 });
  assert.deepEqual(received, [{ n: 1 }, { n: 2 }]);
  assert.equal(onceCount, 1);

  wailsWebRuntime.Events.On('vpro:cleanup', () => {
    received.push('should-not-fire');
  });
  wailsWebRuntime.Events.Off('vpro:cleanup');
  await wailsWebRuntime.Events.Emit('vpro:cleanup', {});
  wailsWebRuntime.Events.OffAll();
  assert.equal(received.length, 2);

  // Dialogs return safe sentinels rather than throwing.
  assert.equal(await wailsWebRuntime.Dialogs.SaveFile({ Filename: 'out.xlsx' }), '');
  assert.equal(await wailsWebRuntime.Dialogs.OpenFile({}), '');
  assert.deepEqual([...(await wailsWebRuntime.Dialogs.OpenFile({ AllowsMultipleSelection: true }))], []);
  assert.equal(await wailsWebRuntime.Dialogs.Info({ Message: 'ok' }), '');
  assert.equal(await wailsWebRuntime.Dialogs.Warning({ Message: 'ok' }), '');
  assert.equal(await wailsWebRuntime.Dialogs.Error({ Message: 'ok' }), '');
  assert.equal(await wailsWebRuntime.Dialogs.Question({ Message: 'ok' }), '');

  // Create helpers match Wails runtime eventcreate expectations.
  assert.equal(wailsWebRuntime.Create.ByteSlice(null), '');
  assert.deepEqual([...wailsWebRuntime.Create.Array(wailsWebRuntime.Create.Any)(null)], []);
  assert.deepEqual({ ...wailsWebRuntime.Create.Map(wailsWebRuntime.Create.Any, wailsWebRuntime.Create.Any)(null) }, {});
  assert.equal(wailsWebRuntime.Create.Nullable(wailsWebRuntime.Create.ByteSlice)(null), null);
  assert.ok(wailsWebRuntime.Create.DateFromTime('2026-01-01T00:00:00Z') instanceof Date);
  assert.deepEqual({ ...wailsWebRuntime.Create.Events }, {});

  // Verify vite.web.config.ts structure.
  const webViteSrc = readFileSync(path.join(FE_ROOT, 'vite.web.config.ts'), 'utf8');
  assert.match(webViteSrc, /__VPRO_WEB_READONLY__:\s*true/);
  assert.match(webViteSrc, /outDir:\s*["']dist-web["']/);
  assert.match(webViteSrc, /wailsWebRuntime\.ts/);
  assert.match(webViteSrc, /wails-typed-events/);
  assert.doesNotMatch(webViteSrc, /@wailsio\/runtime\/plugins\/vite/);
});
