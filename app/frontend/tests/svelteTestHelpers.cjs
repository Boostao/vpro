const assert = require('node:assert/strict');
const vm = require('node:vm');
const { existsSync, readdirSync, readFileSync } = require('node:fs');
const path = require('node:path');
const ts = require('typescript');
const { compile } = require('svelte/compiler');
const { readFixtureText, resolveFixturePath } = require('./fixtureLoader.cjs');

const SRC_ROOT = path.resolve(__dirname, '..', 'src');
let cachedByBasename = null;
if (!globalThis.__vproContextDisposers) {
  globalThis.__vproContextDisposers = new Set();
}

function buildSrcIndex(rootDir = SRC_ROOT) {
  const byBase = new Map();
  function walk(dir) {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (byBase.has(entry.name)) {
        throw new Error(`Duplicate src basename "${entry.name}": ${byBase.get(entry.name)} vs ${full}`);
      } else {
        byBase.set(entry.name, full);
      }
    }
  }
  walk(rootDir);
  if (rootDir === SRC_ROOT) cachedByBasename = byBase;
  return byBase;
}

function srcPath(name) {
  const raw = String(name);
  if (path.isAbsolute(raw) && existsSync(raw)) return raw;
  const clean = raw.replaceAll('\\', '/').replace(/^\.\//, '');
  if (clean.startsWith('fixtures/')) {
    try { return resolveFixturePath(clean.slice('fixtures/'.length)).filePath; } catch {}
  }
  const testRelative = path.join(__dirname, clean);
  if (clean.startsWith('fixtures/') && existsSync(testRelative)) return testRelative;
  const direct = path.join(SRC_ROOT, clean);
  if (existsSync(direct)) return direct;
  const base = path.posix.basename(clean);
  const index = cachedByBasename ?? buildSrcIndex();
  if (index.has(base) && existsSync(index.get(base))) return index.get(base);
  const refreshed = buildSrcIndex();
  if (refreshed.has(base) && existsSync(refreshed.get(base))) return refreshed.get(base);
  return direct;
}

function readSrc(name) {
  const clean = String(name).replaceAll('\\', '/').replace(/^\.\//, '');
  if (clean.startsWith('fixtures/')) {
    return readFixtureText(clean.slice('fixtures/'.length));
  }
  return readFileSync(srcPath(name), 'utf8');
}

function srcFiles() {
  const out = [];
  function walk(dir) {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name.endsWith('.svelte') || entry.name.endsWith('.ts')) {
        out.push(path.relative(SRC_ROOT, full).replaceAll('\\', '/'));
      }
    }
  }
  walk(SRC_ROOT);
  return out.sort();
}

function canonicalLocalSpecifier(name) {
  const norm = String(name).replaceAll('\\', '/');
  if ((norm.startsWith('./') || norm.startsWith('../')) && !norm.includes('bindings/') && !norm.includes('resources/')) {
    return './' + path.posix.basename(norm);
  }
  return norm;
}

function resolveDependency(name, dependencies = {}) {
  if (!dependencies || typeof dependencies !== 'object') return { found: false, key: '', value: undefined };
  if (name in dependencies) return { found: true, key: name, value: dependencies[name] };
  const norm = String(name).replaceAll('\\', '/');
  for (const marker of ['bindings/', 'resources/']) {
    const idx = norm.indexOf(marker);
    if (idx !== -1) {
      const suffix = norm.slice(idx);
      for (const key of Object.keys(dependencies)) {
        const kNorm = key.replaceAll('\\', '/');
        const kIdx = kNorm.indexOf(marker);
        if (kIdx !== -1 && kNorm.slice(kIdx) === suffix) {
          return { found: true, key, value: dependencies[key] };
        }
      }
      return { found: false, key: '', value: undefined };
    }
  }
  if (norm.startsWith('./') || norm.startsWith('../')) {
    const base = path.posix.basename(norm);
    const dotBase = './' + base;
    if (dotBase in dependencies) return { found: true, key: dotBase, value: dependencies[dotBase] };
    for (const key of Object.keys(dependencies)) {
      const kNorm = key.replaceAll('\\', '/');
      if ((kNorm.startsWith('./') || kNorm.startsWith('../')) &&
          !kNorm.includes('bindings/') && !kNorm.includes('resources/') &&
          path.posix.basename(kNorm) === base) {
        return { found: true, key, value: dependencies[key] };
      }
    }
  }
  return { found: false, key: '', value: undefined };
}

const wailsRuntimeStub = {
  Events: { On: () => () => {} },
  Call: { RuntimeError: class RuntimeError extends Error {} },
  CancelledRejectionError: class CancelledRejectionError extends Error {},
};

const serverReads = {
  ReadRequests: class {
    track(request) { return request; }
    cancelAll() {}
  },
  trackIfCancellable(reads, request) {
    if (
      request !== null &&
      typeof request === 'object' &&
      typeof request.cancel === 'function' &&
      reads &&
      typeof reads.track === 'function'
    ) {
      return reads.track(request);
    }
    return Promise.resolve(request);
  },
  formatError(cause) {
    return loadTypeScript('shared/readRequests.ts', {
      '@wailsio/runtime': wailsRuntimeStub,
    }).formatError(cause);
  },
  expectedReadCancellation() {
    return false;
  },
};

const ssrReactiveSessionStub = {
  observeSession(getSession, read) {
    return {
      get current() {
        const s = getSession();
        return s ? read(s) : undefined;
      },
    };
  },
  observeSessionView(getSession) {
    return {
      get current() {
        const s = getSession();
        return s ? s.view() : undefined;
      },
    };
  },
};

const noopNotificationsStub = {
  notifications: {
    push: () => ({ id: 'stub' }),
    success: () => ({ id: 'stub' }),
    info: () => ({ id: 'stub' }),
    warning: () => ({ id: 'stub' }),
    error: () => ({ id: 'stub' }),
    triggerAction: () => false,
    markRead() {},
    markAllRead() {},
    clearHistory() {},
    dismissToast() {},
    pauseToast() {},
    resumeToast() {},
    subscribe: (fn) => {
      fn({ entries: [], toasts: [], unreadCount: 0, unreadErrorCount: 0, unreadWarningCount: 0, badgeSeverity: 'none' });
      return () => {};
    },
    getSnapshot: () => ({ entries: [], toasts: [], unreadCount: 0, unreadErrorCount: 0, unreadWarningCount: 0, badgeSeverity: 'none' }),
  },
};

function resolveLocalSourceFile(fromDir, rawSpecifier) {
  const norm = String(rawSpecifier).replaceAll('\\', '/');
  if (!(norm.startsWith('./') || norm.startsWith('../')) || norm.includes('bindings/') || norm.includes('resources/')) {
    return null;
  }
  const candidates = [];
  if (fromDir) {
    const rel = path.resolve(fromDir, norm);
    candidates.push(rel, `${rel}.ts`, `${rel}.svelte.ts`, `${rel}.svelte`);
  }
  const base = path.posix.basename(norm);
  for (const ext of ['', '.ts', '.svelte.ts', '.svelte']) {
    const p = srcPath(base + ext);
    if (existsSync(p)) candidates.push(p);
  }
  for (const candidate of candidates) {
    if (existsSync(candidate)) return candidate;
  }
  return null;
}

const BUILTIN_SSR_MODULE_FACTORIES = {
  './notificationService.svelte': () => noopNotificationsStub,
  './reactiveSession.svelte': () => ssrReactiveSessionStub,
  './readRequests': () => serverReads,
  './ProjectMetadataEditor.svelte': () => ({ default: () => {} }),
  './SummaryVegetationWorkbookPanel.svelte': () => ({ default: () => {} }),
  './summaryVegetationPreferences': () => ({ summaryVegetationPreferenceSession: null }),
  './summaryVegetationQualityPreferences': () => ({
    ...qualityPreferenceHelpers().preferences,
    summaryVegetationQualityPreferenceSession: null,
  }),
  './summaryVegetationPresentationPreferences': () => ({ summaryVegetationPresentationPreferenceSession: null }),
  './summaryVegetationFieldListDesktop': () => ({
    summaryVegetationFieldListDesktop: { enabled: false, contextAvailable: () => false },
  }),
  './summaryVegetationEnvironmentalDesktop': () => ({
    summaryEnvironmentalEnabled: false,
    summaryEnvironmentalDesktop: {},
    summaryEnvironmentalPort: {},
  }),
  './SummaryVegetationQualityPreferences.svelte': (dependencies) => ({
    default: serverComponent(
      readSrc('SummaryVegetationQualityPreferences.svelte'),
      'SummaryVegetationQualityPreferences.svelte',
      { ...dependencies, './summaryVegetationQualityPreferences': qualityPreferenceHelpers().preferences }
    ),
  }),
};

function serverComponent(source, filename, dependencies = {}, _environment = {}) {
  const resolvedFilename = srcPath(filename);
  const fromDir = path.dirname(resolvedFilename);
  const compiled = compile(source, { filename: resolvedFilename, generate: 'server' });
  assert.equal(compiled.warnings.length, 0);
  const module = { exports: {} };
  const code = ts.transpileModule(compiled.js.code, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, esModuleInterop: false }
  }).outputText;
  vm.runInNewContext(code, {
    module, exports: module.exports, structuredClone,
    require(rawName) {
      const canon = canonicalLocalSpecifier(rawName);
      const matched = resolveDependency(rawName, dependencies);
      if (matched.found) {
        if (canon === './readRequests' && matched.value && typeof matched.value === 'object') {
          return { ...serverReads, ...matched.value };
        }
        return matched.value;
      }
      if (rawName === 'svelte' || rawName.startsWith('svelte/')) return require(rawName);
      if (rawName === '@wailsio/runtime') return wailsRuntimeStub;
      if (rawName === '@lucide/svelte') {
        return new Proxy({}, { get: () => () => {} });
      }
      if (canon.endsWith('.css')) return {};
      if (Object.prototype.hasOwnProperty.call(BUILTIN_SSR_MODULE_FACTORIES, canon)) {
        return BUILTIN_SSR_MODULE_FACTORIES[canon](dependencies);
      }
      const qualityDep = resolveDependency('./qualityEditor', dependencies);
      const qualityModule = () =>
        qualityDep.found ? qualityDep.value : loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });
      if (canon === './ordinaryEditor' || canon === './otherEditor' || canon === './soilChildEditor') {
        return loadTypeScript(`${canon.slice(2)}.ts`, {
          './qualityEditor': qualityModule(),
          './numericEditor': loadTypeScript('numericEditor.ts'),
        });
      }
      if (canon === './catalogueLookup' && qualityDep.found) {
        return loadTypeScript('catalogueLookup.ts', {
          './qualityEditor': qualityDep.value,
          './readRequests': serverReads,
        });
      }
      if (canon.endsWith('bindings/github.com/boostao/vpro/app')) {
        return new Proxy({}, { get: () => new Proxy({}, { get: () => async () => null }) });
      }
      if (canon.endsWith('bindings/events')) {
        return { VproCloseRequest: 'vpro:close-request' };
      }
      const localTarget = resolveLocalSourceFile(fromDir, rawName);
      if (localTarget) {
        if (localTarget.endsWith('.svelte')) {
          return { default: serverComponent(readFileSync(localTarget, 'utf8'), localTarget, dependencies) };
        }
        return loadTypeScript(localTarget, dependencies);
      }
      throw new Error(`Unexpected renderer dependency ${rawName}`);
    }
  });
  return module.exports.default;
}

const cachedTranspiledTs = new Map();
const cachedResourceJson = new Map();

function loadTypeScript(filename, dependencies = {}, globals = {}, evalCache = null) {
  const resolvedFilename = srcPath(filename);
  if (evalCache && evalCache.has(resolvedFilename)) return evalCache.get(resolvedFilename);
  const fromDir = path.dirname(resolvedFilename);
  const isRuneModule = resolvedFilename.endsWith('.svelte.ts');
  const runeGlobals = isRuneModule
    ? {
        $state: Object.assign((v) => v, { raw: (v) => v, snapshot: (v) => v }),
        $derived: Object.assign((v) => v, { by: (fn) => fn() }),
        $effect: Object.assign(() => {}, { root: () => () => {} }),
      }
    : {};
  let jsCode = cachedTranspiledTs.get(resolvedFilename);
  if (!jsCode) {
    jsCode = ts.transpileModule(readSrc(filename), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, esModuleInterop: true }
    }).outputText;
    cachedTranspiledTs.set(resolvedFilename, jsCode);
  }
  const module = { exports: {} };
  if (evalCache) evalCache.set(resolvedFilename, module.exports);
  vm.runInNewContext(jsCode, {
    __vproContextDisposers: globalThis.__vproContextDisposers,
    ...runeGlobals,
    ...globals,
    module,
    exports: module.exports,
    structuredClone,
    require(rawName) {
      const canon = canonicalLocalSpecifier(rawName);
      const matched = resolveDependency(rawName, dependencies);
      if (matched.found) {
        if (canon === './readRequests' && matched.value && typeof matched.value === 'object') {
          return { ...serverReads, ...matched.value };
        }
        return matched.value;
      }
      if (rawName === 'svelte' || rawName.startsWith('svelte/')) return require(rawName);
      if (rawName === '@wailsio/runtime') return wailsRuntimeStub;
      if (canon === './notificationService.svelte') return noopNotificationsStub;
      if (canon === './reactiveSession.svelte') return ssrReactiveSessionStub;
      if (canon === './readRequests') return serverReads;
      const qualityDep = resolveDependency('./qualityEditor', dependencies);
      const restoreDep = resolveDependency('./projectMetadataRestore', dependencies);
      const transportDep = resolveDependency('./siviParentTransport', dependencies);
      const metadataDep = resolveDependency('./projectMetadataEditor', dependencies);
      if (canon === './siviMetadataWire') {
        if (transportDep.found) return transportDep.value;
        const quality = qualityDep.found ? qualityDep.value : loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts', {}, {}, evalCache) }, {}, evalCache);
        return loadTypeScript('siviMetadataWire.ts', {
          './projectMetadataRestore': restoreDep.found ? restoreDep.value : loadTypeScript('projectMetadataRestore.ts', {
            './qualityEditor': quality, './projectMetadataEditor': {},
          }, {}, evalCache),
        }, {}, evalCache);
      }
      if (canon === './twoPageSoilActivity' || canon === './twoPageVegetationActivity') {
        const quality = qualityDep.found ? qualityDep.value : loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts', {}, {}, evalCache) }, {}, evalCache);
        return loadTypeScript(`${canon.slice(2)}.ts`, { './qualityEditor': quality }, {}, evalCache);
      }
      if (canon === './qualityMinimumReference') return qualityPreferenceHelpers().reference;
      if (canon === './siviChildSourceNotices') {
        const quality = qualityDep.found ? qualityDep.value : loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts', {}, {}, evalCache) }, {}, evalCache);
        const metadata = metadataDep.found ? metadataDep.value : loadTypeScript('projectMetadataEditor.ts', {
          './qualityEditor': quality, '../../resources/project-metadata-standard.json': [], '../../resources/project-metadata-template.json': [],
        }, {}, evalCache);
        return loadTypeScript('siviChildSourceNotices.ts', {
          './heightEditor': loadTypeScript('heightEditor.ts', { './numericEditor': loadTypeScript('numericEditor.ts', {}, {}, evalCache) }, {}, evalCache),
          './projectMetadataEditor': metadata,
          './projectMetadataRestore': restoreDep.found ? restoreDep.value : loadTypeScript('projectMetadataRestore.ts', {
            './qualityEditor': quality, './projectMetadataEditor': metadata,
          }, {}, evalCache),
        }, {}, evalCache);
      }
      if (rawName.includes('resources/') && rawName.endsWith('.json')) {
        const jsonPath = path.resolve(__dirname, '../../resources', path.basename(rawName));
        if (!cachedResourceJson.has(jsonPath)) {
          cachedResourceJson.set(jsonPath, JSON.parse(readFileSync(jsonPath, 'utf8')));
        }
        return cachedResourceJson.get(jsonPath);
      }
      if (canon.endsWith('bindings/github.com/boostao/vpro/app')) {
        return new Proxy({}, { get: () => new Proxy({}, { get: () => async () => null }) });
      }
      if (canon.endsWith('bindings/events')) {
        return { VproCloseRequest: 'vpro:close-request' };
      }
      const localTarget = resolveLocalSourceFile(fromDir, rawName);
      if (localTarget && !localTarget.endsWith('.svelte')) {
        if (localTarget.endsWith('.json')) return JSON.parse(readFileSync(localTarget, 'utf8'));
        return loadTypeScript(localTarget, dependencies, globals, evalCache);
      }
      throw new Error(`Unexpected TypeScript dependency ${rawName}`);
    }
  });
  return module.exports;
}

const LEGACY_CONTEXT_BUSY_FLAGS = [
  'archivePublicationBusy',
  'vegetationPublicationBusy',
  'lifeformPublicationBusy',
  'summaryPublicationBusy',
  'projectReportBusy',
  'twoPageVegetationBusy',
  'twoPageSoilBusy',
  'pictureCreationBusy',
  'pictureLifecycleBusy',
  'summaryPreferenceBusy',
  'summaryFieldListBusy',
  'summaryEnvironmentalBusy',
  'externalSUEnvironmentBusy',
];

let cachedFs882Helpers = null;
let cachedAppVmModules = null;
let cachedSidebarOps = null;
let cachedProfileOps = null;
let cachedHubOps = null;

function loadFs882HelperExports() {
  if (cachedFs882Helpers) return cachedFs882Helpers;
  const entryDir = path.join(SRC_ROOT, 'entry');
  if (!existsSync(entryDir)) return {};
  const merged = {};
  for (const name of readdirSync(entryDir).sort()) {
    if (name.startsWith('fs882Form') && (name.endsWith('.ts') || name.endsWith('.svelte.ts'))) {
      try {
        Object.assign(merged, loadTypeScript(path.join(entryDir, name)));
      } catch {}
    }
  }
  cachedFs882Helpers = merged;
  return merged;
}

function getAppVmModules() {
  if (cachedAppVmModules) return cachedAppVmModules;
  const noopSub = () => () => {};
  const noopSession = () => ({ view: () => ({ busy: false, blocked: false, closeBlocked: false }), held: () => false, subscribe: noopSub });
  const opGuardMod = loadTypeScript('shell/operationGuard.svelte.ts', {
    './externalSUEnvironment': { subscribeExternalSUEnvironmentActivity: noopSub },
    './twoPageSoilActivity': { subscribeTwoPageSoilActivity: noopSub },
    './twoPageVegetationActivity': { subscribeTwoPageVegetationActivity: noopSub },
    './tableCSVArchiveExport': { tableCSVArchivePublicationSession: noopSession },
    './pictureCreationActivity': { subscribePictureCreationActivity: noopSub },
    './pictureLifecycleActivity': { subscribePictureLifecycleActivity: noopSub },
    './lifeformWorkbook': { lifeformWorkbookPublicationSession: noopSession },
    './longVegetationProjectWorkspaces': { projectReportWorkspace: noopSession },
    './siteUnitSummaryExtendedWorkbook': { extendedSummaryWorkbookPublicationSession: noopSession },
    './siteUnitSummaryWorkbook': { siteUnitSummaryWorkbookPublicationSession: noopSession },
    './subzoneMatrixReport': { matrixPublicationSession: noopSession },
    './summaryVegetationEnvironmentalDesktop': { summaryEnvironmentalEnabled: false, summaryEnvironmentalDesktop: {} },
    './summaryVegetationFieldListDesktop': { summaryVegetationFieldListDesktop: { enabled: false } },
    './summaryVegetationPreferences': { summaryVegetationPreferenceSession: null },
    './summaryVegetationPresentationPreferences': { summaryVegetationPresentationPreferenceSession: null },
    './summaryVegetationQualityPreferences': { summaryVegetationQualityPreferenceSession: null },
    './summaryVegetationWorkbook': { summaryVegetationWorkbookSession: noopSession },
    './vegetationWorkbook': { vegetationWorkbookPublicationSession: noopSession },
  });
  const closeMod = loadTypeScript('shell/closeLifecycle.ts');
  const plotOpsMod = loadTypeScript('shell/shellPlotOps.ts');
  const lifecycleMod = loadTypeScript('shell/shellLifecycleOps.ts', {
    './operationGuard.svelte': opGuardMod,
  });
  cachedAppVmModules = { ...closeMod, ...opGuardMod, ...plotOpsMod, ...lifecycleMod };
  return cachedAppVmModules;
}

function createAppVmDefaults() {
  return {
    ...getAppVmModules(),
    pageSize: 25,
    request: 0,
    hierarchyRequest: 0,
    stateRequest: 0,
    lastPushedError: '',
    pausedByGuard: false,
    busy: false,
    error: '',
    view: 'plots',
    editorEntryForm: 'fs882',
    editorPlotNumber: undefined,
    editor: undefined,
    editorBusy: false,
    localEditorBusy: false,
    companionPanelBusy: false,
    editorInitializing: false,
    workbenchDirtyLabel: '',
    selected: null,
    page: null,
    offset: 0,
    hierarchyNodes: [],
    profileNavigation: null,
    standaloneMetadataPlot: '',
    startupFailure: null,
    closeRequest: '',
    closeWorking: false,
    closeError: '',
    pendingTransition: null,
    transitionWorking: false,
    transitionError: '',
    plotFindQuery: '',
    plotFindError: '',
    plotFindResult: null,
    allAvailablePlots: [],
    $projectState: null,
    tick: async () => {},
    LifecycleService: {},
    ContextService: {},
    plotReads: new serverReads.ReadRequests(),
    hierarchyReads: new serverReads.ReadRequests(),
    stateReads: new serverReads.ReadRequests(),
    ui: undefined,
  };
}

function attachDefaultAppOperationGuard(context, values) {
  if (values && Object.prototype.hasOwnProperty.call(values, 'operationGuard') && values.operationGuard) {
    return;
  }
  const guard = context.createOperationGuard();
  context.registerCoreOperationGuards(guard, {
    shellBusy: () => Boolean(context.busy),
    localEditor: () => ({
      busy: Boolean(context.editorBusy || context.localEditorBusy),
      dirty: Boolean(context.workbenchDirtyLabel),
    }),
    companionPanel: () => ({
      busy: Boolean(context.companionPanelBusy),
      dirty: Boolean(context.standaloneMetadataPlot && context.standaloneMetadataEditor?.hasUnsavedChanges?.()),
    }),
    editorInit: () => Boolean(context.editorInitializing),
    transitionDialog: () => Boolean(context.transitionWorking || context.pendingTransition !== null),
    closeDialog: () => Boolean(context.closeRequest),
  });
  guard.register(
    'legacy-vm-flags',
    () => ({ busy: LEGACY_CONTEXT_BUSY_FLAGS.some((flag) => Boolean(context[flag])) }),
    { publicationOnly: true }
  );
  context.operationGuard = guard;
}

function componentFunctions(filename, names, values = {}) {
  const shim = require('./fs882TestShim.cjs');
  const source = readSrc(filename);
  const baseName = path.basename(String(filename));
  const script = source.match(/<script lang="ts">([\s\S]*?)<\/script>/)[1];
  const ast = ts.createSourceFile(baseName + '.ts', script, ts.ScriptTarget.Latest, true);
  const allDecls = ast.statements.filter((node) => ts.isFunctionDeclaration(node) && node.name);

  let extraAst = null;
  let extraDecls = [];
  if (baseName === 'LongVegetationReport.svelte') {
    const extraSrc = readSrc('reports/parts/LongVegetationTitleStatsPreferences.svelte');
    const extraScript = extraSrc.match(/<script lang="ts">([\s\S]*?)<\/script>/)[1];
    extraAst = ts.createSourceFile('LongVegetationTitleStatsPreferences.svelte.ts', extraScript, ts.ScriptTarget.Latest, true);
    extraDecls = extraAst.statements.filter((node) => ts.isFunctionDeclaration(node) && node.name);
  }

  const TWO_PAGE_READER_NAMES = new Set([
    'openProfiling', 'returnFromProfiling',
    'openProjectMetadata', 'returnFromProjectMetadata',
    'openEnvironmentTable', 'returnFromEnvironmentTable',
    'openVegetationTable', 'returnFromVegetationTable',
    'openGoogleEarth', 'returnFromGoogleEarth',
    'openAudit', 'returnFromAudit',
    'openExternalTransfer', 'returnFromExternalTransfer',
  ]);

  const APP_DELEGATED_NAMES = new Set([
    'copyPlotToNewNumber',
    'removePlotFromProject',
    'collectAllProjectPlotNumbers',
    'extractDatasheetPlotSummaries',
    'refreshScopedPlotCatalog',
  ]);

  const selected = allDecls.filter((node) => names.includes(node.name.text));
  const selectedExtra = extraDecls.filter((node) => names.includes(node.name.text));
  if (baseName !== 'FS882Form.svelte') {
    const readerMatches =
      baseName === 'TwoPageEntryEditor.svelte' ? names.filter((n) => TWO_PAGE_READER_NAMES.has(n)).length : 0;
    const appMatches = baseName === 'App.svelte' ? names.filter((n) => APP_DELEGATED_NAMES.has(n)).length : 0;
    assert.equal(
      selected.length + selectedExtra.length + readerMatches + appMatches,
      names.length,
      `Missing functions in ${baseName}: requested ${names.join(', ')}`
    );
  }

  const helperDecls = [
    'App.svelte',
    'WorkspaceSidebar.svelte',
    'PlotProfilePanel.svelte',
    'LongVegetationReport.svelte',
    'TwoPageEntryEditor.svelte',
    'TwoPageSoilPanel.svelte',
    'TwoPageVegetationPanel.svelte',
  ].includes(baseName)
    ? allDecls.filter(
        (node) => !names.includes(node.name.text) && !Object.prototype.hasOwnProperty.call(values, node.name.text)
      )
    : [];

  const fs882Helpers = baseName === 'FS882Form.svelte' ? loadFs882HelperExports() : {};
  const fs882VmDefaults =
    baseName === 'FS882Form.svelte' ? shim.createFs882VmDefaults(loadTypeScript, serverReads, fs882Helpers, names) : {};
  const defaultSoilReviewProfile =
    baseName === 'App.svelte' || baseName === 'FS882Form.svelte'
      ? {
          ...fs882Helpers,
          ...fs882VmDefaults,
          twoPageSoilBusy: false,
          twoPageSoilBlocked: false,
          ordinarySoilUnavailable: null,
          historicalSoilUnavailable: null,
          twoPageVegetationBusy: false,
          twoPageVegetationBlocked: false,
          ordinaryVegetationUnavailable: null,
        }
      : {};

  const appDefaults = baseName === 'App.svelte' ? createAppVmDefaults() : {};
  const sidebarDefaults =
    baseName === 'WorkspaceSidebar.svelte'
      ? {
          ...(cachedSidebarOps ?? (cachedSidebarOps = loadTypeScript('shell/workspaceSidebarOps.ts'))),
          accessRequests: new serverReads.ReadRequests(),
          accessElapsedTimer: null,
          stopAccessProgressEvents: null,
          accessGeneration: 0,
          activeAccessRpc: null,
          busy: false,
          editorBusy: false,
          companionPanelBusy: false,
          transitionWorking: false,
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
          accessInspection: null,
          accessSelectedSourceProject: '',
          accessTargetProject: '',
          accessDestinationPath: '',
        }
      : {};
  const profileDefaults =
    baseName === 'PlotProfilePanel.svelte'
      ? (cachedProfileOps ?? (cachedProfileOps = loadTypeScript('shell/plotProfileOps.ts')))
      : {};
  const interchangeDefaults =
    baseName === 'InterchangeHub.svelte'
      ? {
          hubOps:
            cachedHubOps ??
            (cachedHubOps = loadTypeScript('interchangeHub.ts', {
              '@wailsio/runtime': { Dialogs: {}, Events: {} },
              '../shared/readRequests': serverReads,
            })),
        }
      : {};

  const context = vm.createContext({
    exports: {},
    $state: Object.assign((v) => v, { raw: (v) => v, snapshot: (v) => v }),
    notifications: noopNotificationsStub.notifications,
    formatError: serverReads.formatError,
    trackIfCancellable: serverReads.trackIfCancellable,
    ...(baseName === 'TwoPageEntryEditor.svelte'
      ? {
          ...shim.getTwoPageDeps(loadTypeScript),
          owner: { contextId: '', project: '', plot: '' },
          form: 'FS882-8x6XL',
          standalone: false,
          childBlocked: false,
          sourceBlocked: false,
          session: undefined,
          sessions: new Map(),
          view: { original: null, drafts: {}, error: null, referenceError: null, busy: false, referencesBusy: false, blocked: false },
          close: { unsaved: false, busy: false, blocked: false, canSave: false, saveReason: '', error: null },
          error: null,
          onchange() {},
          onclosed() {},
          oncommitted: async () => {},
          externalOpen: false,
          auditOpen: false,
          auditBusy: false,
          googleEarthOpen: false,
          googleEarthBusy: false,
          vegetationTableOpen: false,
          vegetationTableBusy: false,
          environmentTableOpen: false,
          environmentTableBusy: false,
          projectMetadataOpen: null,
          projectMetadataBusy: false,
          profilingOpen: false,
          profilingBusy: false,
          sourceRefreshing: false,
        }
      : {}),
    ...(baseName === 'SummaryVegetationReport.svelte'
      ? {
          preferences: null,
          quality: null,
          qualityView: null,
          qualityReadBusy: false,
          qualityMutationHeld: false,
          qualityInvalid: false,
          qualityUnavailable: false,
          presentation: null,
          presentationView: null,
          presentationReadBusy: false,
          presentationMutationHeld: false,
          presentationInvalid: false,
          fieldListHeld: false,
          fieldListBusy: false,
          environmentalHeld: false,
        }
      : {}),
    ...(baseName === 'StartupRecoveryPanel.svelte' ? loadTypeScript('shell/startupRecovery.ts') : {}),
    ...(baseName === 'PlotLabelPreview.svelte' ? loadTypeScript('interchange/plotLabelPreviewOps.ts') : {}),
    ...(baseName === 'SiteUnitSummary.svelte' ? { ops: loadTypeScript('reports/siteUnitSummaryOps.ts') } : {}),
    ...(baseName === 'SummaryVegetationReport.svelte'
      ? { ops: loadTypeScript('reports/summaryVegetationReportOps.ts'), envDesk: {} }
      : {}),
    ...appDefaults,
    ...sidebarDefaults,
    ...profileDefaults,
    ...interchangeDefaults,
    ...defaultSoilReviewProfile,
    ...values,
  });

  if (baseName === 'FS882Form.svelte') {
    shim.runFs882TestActions(context, names, values);
    return context;
  }
  if (baseName === 'TwoPageEntryEditor.svelte') {
    shim.attachTwoPageReadersVm(context, values, serverReads.formatError);
  }
  if (baseName === 'App.svelte') {
    attachDefaultAppOperationGuard(context, values);
    if (!Object.prototype.hasOwnProperty.call(values, 'ui') || !values.ui) {
      context.ui = new Proxy(
        {
          hasBlockingModalOpen() {
            return Boolean(
              context.commandPaletteOpen ||
                context.notificationDrawerOpen ||
                context.shortcutsModalOpen ||
                context.whatsNewModalOpen ||
                context.aboutModalOpen ||
                context.tourOpen ||
                context.resetSampleConfirmOpen ||
                context.userSetupOpen
            );
          },
          cancelCatalogReads() {
            context.catalogPlotRequest = (context.catalogPlotRequest ?? 0) + 1;
            context.catalogPlotReads?.cancelAll?.();
          },
          clearCatalogCaches() {
            context.scopedCatalogKey = '';
            context.scopedPlotCatalogRows = [];
            context.dynamicPalettePlotRows = [];
            context.createdSiviPlots = [];
          },
        },
        {
          get(target, prop) {
            if (prop in context) return context[prop];
            return target[prop];
          },
          set(_target, prop, value) {
            context[prop] = value;
            return true;
          },
        }
      );
    }
  }
  if (baseName === 'LongVegetationReport.svelte') {
    shim.attachLongVegTitleStatsVm(context);
  }
  if (
    baseName === 'LongVegetationReport.svelte' &&
    !Object.prototype.hasOwnProperty.call(values, 'bridge')
  ) {
    let lastPubKey = '';
    context.bridge = {
      get projectActive() { return Boolean(context.projectActive); },
      get workbookBarrier() { return Boolean(context.workbookBarrier); },
      get preferenceBarrier() { return Boolean(context.preferenceBarrier); },
      get sharedPreferenceBarrier() { return Boolean(context.sharedPreferenceBarrier); },
      cancelLoads() {
        context.preferences?.cancelLoad?.();
        context.statistics?.cancelLoad?.();
      },
      syncWorkbook() {
        const p = context.workbookSession?.view?.();
        if (!p) { lastPubKey = ''; return; }
        const key = p.outcome
          ? `outcome:${p.outcome.status}:${p.requestedDestination}:${p.outcome.path}:${p.outcome.sha256}:${p.error ?? ''}`
          : p.error
            ? `error:${p.error}:${p.requestedDestination}`
            : '';
        if (!key || key === lastPubKey) return;
        lastPubKey = key;
        const ctxTag =
          (typeof context.project === 'string' && context.project) ||
          (typeof context.effectiveHierarchy === 'string' && context.effectiveHierarchy !== 'None' ? context.effectiveHierarchy : undefined) ||
          (typeof context.hierarchy === 'string' && context.hierarchy && context.hierarchy !== 'None' ? context.hierarchy : undefined);
        const opts = { category: 'reports', source: 'Long Vegetation', contextTag: ctxTag };
        if (p.outcome?.status === 'published' && !p.error) {
          context.notifications.success('Long Vegetation workbook exported', p.outcome.path || p.requestedDestination || context.destination, opts);
        } else if (p.error || p.outcome) {
          context.notifications.error('Long Vegetation workbook export failed', p.error || `Publication ${p.outcome?.status ?? 'failed'} for ${p.requestedDestination || context.destination}`, opts);
        }
      },
      syncProject() {},
    };
  }
  if (
    baseName === 'PlotProfilePanel.svelte' &&
    !Object.prototype.hasOwnProperty.call(values, 'operationHeld')
  ) {
    Object.defineProperty(context, 'operationHeld', {
      configurable: true,
      enumerable: true,
      get: () => LEGACY_CONTEXT_BUSY_FLAGS.some((flag) => Boolean(context[flag])),
    });
  }

  const orderedNodes = [...helperDecls, ...selected];
  const extraCode = selectedExtra.map((node) => node.getText(extraAst)).join('\n');
  const readerBindings =
    baseName === 'TwoPageEntryEditor.svelte'
      ? names
          .filter((n) => TWO_PAGE_READER_NAMES.has(n))
          .map((n) => `function ${n}(...args) { return readers.${n}(...args); }`)
          .join('\n')
      : '';
  const appDelegatedBindings =
    baseName === 'App.svelte'
      ? names
          .filter((n) => APP_DELEGATED_NAMES.has(n))
          .map((n) => {
            if (n === 'extractDatasheetPlotSummaries') return '';
            if (n === 'collectAllProjectPlotNumbers') {
              return `function collectAllProjectPlotNumbers(cid) { return __collectAllProjectPlotNumbers(cid, typeof DatasheetService !== 'undefined' ? DatasheetService : undefined, allAvailablePlots ?? []); }`;
            }
            if (n === 'refreshScopedPlotCatalog') {
              return `async function refreshScopedPlotCatalog(expectedContextId, currentPage, force = false) {
                await runScopedPlotCatalogRefresh({
                  expectedContextId,
                  currentPage,
                  offset: offset ?? 0,
                  force,
                  scopedCatalogKey: scopedCatalogKey ?? '',
                  hasCatalogRows: (scopedPlotCatalogRows?.length ?? 0) > 0,
                  profileNavigation: profileNavigation ?? null,
                  getState: () => $projectState,
                  nextRequestId: () => ++catalogPlotRequest,
                  isCurrentRequest: (id) => id === catalogPlotRequest,
                  catalogPlotReads: catalogPlotReads ?? { cancelAll() {}, track: (p) => p },
                  contextService: ContextService,
                  onCreatedSiviPlots: (rows) => { createdSiviPlots = rows; },
                  onCatalogResolved: (rows, key) => { scopedPlotCatalogRows = rows; scopedCatalogKey = key; },
                });
              }`;
            }
            if (n === 'copyPlotToNewNumber') {
              return `async function copyPlotToNewNumber(sourcePlot, rawTargetPlot) {
                await runCopyPlotToNewNumber({
                  sourcePlot,
                  rawTargetPlot,
                  isBusy: operationGuard.isBusy(),
                  hasUnsavedEdits: Boolean(editor?.getCloseState?.()?.unsaved || workbenchDirtyLabel),
                  contextId: $projectState?.contextId,
                  allAvailablePlots: allAvailablePlots ?? [],
                  contextService: ContextService,
                  reloadAndSelect: async (targetPlot, fallbackSummary) => {
                    scopedCatalogKey = '';
                    await loadPlots(offset ?? 0);
                    selected = fallbackSummary;
                  },
                  notify: notifications,
                });
              }`;
            }
            if (n === 'removePlotFromProject') {
              return `async function removePlotFromProject(sourcePlot, rawCleanProjectName) {
                await runRemovePlotFromProject({
                  sourcePlot,
                  rawCleanProjectName,
                  isBusy: operationGuard.isBusy(),
                  hasUnsavedEdits: Boolean(editor?.getCloseState?.()?.unsaved || workbenchDirtyLabel),
                  contextId: $projectState?.contextId,
                  createdSiviPlots: createdSiviPlots ?? [],
                  allAvailablePlots: allAvailablePlots ?? [],
                  contextService: ContextService,
                  datasheetService: typeof DatasheetService !== 'undefined' ? DatasheetService : undefined,
                  onUndoneSivi: async (p) => {
                    createdSiviPlots = (createdSiviPlots ?? []).filter((e) => e.plotNumber !== p);
                    scopedCatalogKey = '';
                    await loadPlots(offset ?? 0);
                  },
                  onSplinterSwitched: async (res) => {
                    if (res?.state && typeof projectState?.set === 'function') projectState.set(res.state);
                    await refresh();
                  },
                  notify: notifications,
                });
              }`;
            }
            return '';
          })
          .filter(Boolean)
          .join('\n')
      : '';
  if (baseName === 'App.svelte' && names.includes('collectAllProjectPlotNumbers')) {
    context.__collectAllProjectPlotNumbers = context.collectAllProjectPlotNumbers;
  }
  const code =
    [orderedNodes.map((node) => node.getText(ast)).join('\n'), extraCode, readerBindings, appDelegatedBindings]
      .filter(Boolean)
      .join('\n') + `\nthis.actions = {${names.join(',')}};`;
  vm.runInContext(
    ts.transpileModule(code, {
      compilerOptions: {
        module: ts.ModuleKind.CommonJS,
        target: ts.ScriptTarget.ES2022,
        alwaysStrict: false,
      },
    }).outputText,
    context
  );
  return context;
}

function presentationHelpers() {
  const paper = loadTypeScript('paperLayout.ts', {
    '../../resources/fs882-xl-layout.json': JSON.parse(readFileSync(path.join(__dirname, '..', '..', 'resources', 'fs882-xl-layout.json'), 'utf8')),
    '../../resources/fs882-extended-shrub-layout.json': JSON.parse(readFileSync(path.join(__dirname, '..', '..', 'resources', 'fs882-extended-shrub-layout.json'), 'utf8'))
  });
  return { paper, presentation: loadTypeScript('formPresentation.ts', { './paperLayout': paper }) };
}

function qualityPreferenceHelpers() {
  const quality = loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });
  const cells = loadTypeScript('projectMetadataRestore.ts', { './qualityEditor': quality, './projectMetadataEditor': {} });
  const locations = loadTypeScript('plotLocationReview.ts', { './projectMetadataRestore': cells });
  const earth = loadTypeScript('googleEarthReview.ts', {
    './projectMetadataRestore': cells, './qualityEditor': quality, './plotLocationReview': locations,
  });
  const shared = loadTypeScript('reportTitlePreferences.ts', { './qualityEditor': quality, './googleEarthReview': earth });
  const lifeform = loadTypeScript('lifeformSummary.ts');
  const transport = loadTypeScript('siviParentTransport.ts', {
    './projectMetadataRestore': cells, './siviParentEditor': {}, './siviParentSession': {},
  });
  const reference = loadTypeScript('qualityMinimumReference.ts', {
    './lifeformSummary': lifeform, './projectMetadataRestore': cells, './siviParentTransport': transport,
  });
  return { reference, preferences: loadTypeScript('summaryVegetationQualityPreferences.ts', {
    './googleEarthReview': earth, './lifeformSummary': lifeform, './qualityEditor': quality,
    './qualityMinimumReference': reference, './reportTitlePreferences': shared,
  }) };
}

const cachedReactiveCjs = new Map();
let cachedFs882CtrlMod = null;
let activeReactiveDestroyCollector = null;

function loadReactiveRuneModule(filename, dependencies = {}, globals = {}, evalCache = new Map()) {
  const { compileModule } = require('svelte/compiler');
  const runtime = require('svelte/internal/client');
  const resolved = srcPath(filename);
  if (evalCache && evalCache.has(resolved)) return evalCache.get(resolved);
  const fromDir = path.dirname(resolved);
  let cjs = cachedReactiveCjs.get(resolved);
  if (cjs === undefined) {
    const es = ts.transpileModule(readFileSync(resolved, 'utf8'), {
      compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext },
    }).outputText;
    const compiled = compileModule(es, { filename: resolved + '.js', generate: 'client' });
    cjs = ts.transpileModule(compiled.js.code, {
      compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS, esModuleInterop: true },
    }).outputText;
    cachedReactiveCjs.set(resolved, cjs);
  }
  const mod = { exports: {} };
  if (evalCache) evalCache.set(resolved, mod.exports);
  vm.runInNewContext(cjs, {
    module: mod,
    exports: mod.exports,
    structuredClone,
    setTimeout,
    clearTimeout,
    queueMicrotask,
    crypto: require('node:crypto'),
    document: { activeElement: null, querySelector: () => null, querySelectorAll: () => [] },
    __vproContextDisposers: globalThis.__vproContextDisposers,
    ...globals,
    require(rawName) {
      if (rawName === 'svelte/internal/client') return runtime;
      if (rawName === 'svelte') {
        return {
          ...require('svelte'),
          onDestroy: (fn) => {
            if (activeReactiveDestroyCollector) activeReactiveDestroyCollector.push(fn);
          },
          tick: async () => {},
          untrack: runtime.untrack,
        };
      }
      if (rawName === '@wailsio/runtime') return wailsRuntimeStub;
      const canon = canonicalLocalSpecifier(rawName);
      const m = resolveDependency(rawName, dependencies);
      if (m.found) {
        if (canon === './readRequests' && m.value && typeof m.value === 'object') {
          return { ...serverReads, ...m.value };
        }
        return m.value;
      }
      if (canon === './notificationService.svelte') return noopNotificationsStub;
      if (canon === './readRequests') return serverReads;
      if (canon.endsWith('bindings/github.com/boostao/vpro/app')) {
        return new Proxy({}, { get: () => new Proxy({}, { get: () => async () => null }) });
      }
      if (canon.endsWith('bindings/events')) return { VproCloseRequest: 'vpro:close-request' };
      const localTarget = resolveLocalSourceFile(fromDir, rawName);
      if (localTarget && !localTarget.endsWith('.svelte')) {
        if (localTarget.endsWith('.json')) return JSON.parse(readFileSync(localTarget, 'utf8'));
        return localTarget.endsWith('.svelte.ts')
          ? loadReactiveRuneModule(localTarget, dependencies, globals, evalCache)
          : loadTypeScript(localTarget, dependencies, globals, evalCache);
      }
      throw new Error(`Unexpected reactive module dependency ${rawName}`);
    },
  });
  return mod.exports;
}

function createFS882TestController(overrides = {}) {
  const runtime = require('svelte/internal/client');
  const fastDefaults = {
    './paperLayout': {
      paperPage: () => ({ sections: [], controls: [] }),
      paperChild: () => ({ sections: [], controls: [] }),
      accessCaption: (s) => s ?? '',
    },
    './twoPageEntrySession': {
      TwoPageEntrySession: class {},
      twoPageEntryForms: ['FS882-8x6XL', 'FS882-8x6XL-CHARS'],
    },
  };
  const mod =
    overrides.dependencies
      ? loadReactiveRuneModule('entry/fs882FormController.svelte.ts', { ...fastDefaults, ...overrides.dependencies })
      : (cachedFs882CtrlMod ??
          (cachedFs882CtrlMod = loadReactiveRuneModule('entry/fs882FormController.svelte.ts', fastDefaults)));
  let ctrl;
  const projectStateBox = runtime.state(
    overrides.projectState ?? {
      contextId: overrides.contextId ?? 'ctx-1',
      activeProject: 'Sample',
      projectPath: 'Sample.db',
      activeSU: 'None',
      suPath: '',
    }
  );
  const entryFormBox = runtime.state(overrides.entryForm ?? 'fs882');
  const plotNumberBox = runtime.state(overrides.plotNumber ?? '00337');
  const neighborPlotsBox = runtime.state(overrides.neighborPlots ?? []);
  const destroyCallbacks = [];
  const prevCollector = activeReactiveDestroyCollector;
  activeReactiveDestroyCollector = destroyCallbacks;
  let disposeRoot;
  try {
    disposeRoot = runtime.effect_root(() => {
      ctrl = mod.createFS882Controller({
        contextId: overrides.contextId ?? 'ctx-1',
        getEntryForm: () => runtime.get(entryFormBox),
        getPlotNumber: () => runtime.get(plotNumberBox),
        getNeighborPlots: () => runtime.get(neighborPlotsBox),
        getProjectState: () => runtime.get(projectStateBox),
        setSuccess: overrides.setSuccess ?? (() => {}),
        onSaved: overrides.onSaved,
        onBusyChange: overrides.onBusyChange,
        onDiagnosticsContextChange: overrides.onDiagnosticsContextChange,
      });
    });
  } finally {
    activeReactiveDestroyCollector = prevCollector;
  }
  const dispose = () => {
    for (const fn of destroyCallbacks.splice(0)) fn();
    disposeRoot();
  };
  const cwProxy = new Proxy(ctrl.children, {
    get(target, prop, receiver) {
      if (prop === 'auditBlocked') {
        return ctrl.childParentDisabled || ctrl.childUnsaved || Object.keys(ctrl.headerValidation).length > 0;
      }
      if (prop === 'heightInvalidCount') return target.heightInvalid.length;
      return Reflect.get(target, prop, receiver);
    },
    set(target, prop, value, receiver) {
      return Reflect.set(target, prop, value, receiver);
    },
  });
  Object.defineProperty(ctrl, 'cw', { get: () => cwProxy, enumerable: true, configurable: true });
  runtime.flush();
  if (!overrides.keepInitialLoadBusy) {
    ctrl.busy = false;
    ctrl.children.soilReferenceBusy = false;
    ctrl.children.speciesReferenceBusy = false;
    ctrl.children.attributeReferenceBusy = false;
    runtime.flush();
  }
  return {
    ctrl,
    flush: () => runtime.flush(),
    setProjectState: (s) => {
      runtime.set(projectStateBox, s);
      runtime.flush();
    },
    setEntryForm: (f) => {
      runtime.set(entryFormBox, f);
      runtime.flush();
    },
    setPlotNumber: (p) => {
      runtime.set(plotNumberBox, p);
      runtime.flush();
    },
    setNeighborPlots: (plots) => {
      runtime.set(neighborPlotsBox, plots);
      runtime.flush();
    },
    dispose,
  };
}

function readFS882Composite() {
  return [
    'entry/FS882Form.svelte',
    'entry/FS882Toolbar.svelte',
    'entry/FS882ManagePlotBar.svelte',
    'entry/FS882TwoPagePlotPrompt.svelte',
    'entry/FS882WorkspaceBody.svelte',
    'entry/FS882SiteTab.svelte',
    'entry/FS882SoilTab.svelte',
    'entry/FS882SoilHorizonSection.svelte',
    'entry/FS882OtherRecordsSection.svelte',
    'entry/FS882AuditTrailSection.svelte',
    'entry/FS882SiviVegSection.svelte',
    'entry/FS882VegCreationSection.svelte',
    'entry/FS882VegTab.svelte',
    'entry/FS882StratumSummary.svelte',
    'entry/FS882Modals.svelte',
    'entry/FS882SiviParentModalHost.svelte',
    'entry/FS882ChildCreateModal.svelte',
    'entry/fs882FormController.svelte.ts',
    'entry/useFS882ChildWorkflows.svelte.ts',
    'entry/useSiviSessions.svelte.ts',
    'entry/fs882FormHelpers.ts',
    'entry/fs882FormSivi.ts',
    'entry/fs882FormSiviOps.ts',
    'entry/fs882FormLoadSave.ts',
    'entry/fs882FormVegDrafts.ts',
    'entry/fs882FormChildren.ts',
  ]
    .map((f) => readSrc(f))
    .join('\n');
}

function readSidebarComposite() {
  return [
    'shell/WorkspaceSidebar.svelte',
    'shell/WorkspaceAccessCandidateFields.svelte',
    'shell/WorkspaceAccessProgressStatus.svelte',
    'shell/WorkspaceExternalAttachSection.svelte',
    'shell/workspaceSidebarOps.ts',
  ]
    .map((f) => readSrc(f))
    .join('\n');
}

function readPlotProfileComposite() {
  return [
    'shell/PlotProfilePanel.svelte',
    'shell/PlotProfileSelectionSection.svelte',
    'shell/PlotProfileSUSection.svelte',
    'shell/PlotProfileBlankReviews.svelte',
    'shell/plotProfileOps.ts',
  ]
    .map((f) => readSrc(f))
    .join('\n');
}

function readTwoPageComposite() {
  return [
    'entry/TwoPageEntryEditor.svelte',
    'entry/TwoPageEntryToolbar.svelte',
    'entry/TwoPageEntryReadersHost.svelte',
    'entry/TwoPageEntryLayout.svelte',
    'entry/TwoPageEntryFieldInput.svelte',
    'entry/useTwoPageEntryReaders.svelte.ts',
    'entry/twoPageEntryOps.ts',
  ]
    .map((f) => readSrc(f))
    .join('\n');
}

function readProjectPlotProfileComposite() {
  return [
    'classification/ProjectPlotProfileReview.svelte',
    'classification/ProjectPlotProfileHeader.svelte',
    'classification/ProjectPlotProfilePreviewSection.svelte',
    'classification/ProjectPlotProfileRulesSection.svelte',
  ]
    .map((f) => readSrc(f))
    .join('\n');
}

function readProjectAdminComposite() {
  return [
    'admin/ProjectAdminWorkbench.svelte',
    'admin/ProjectAdminHeader.svelte',
    'admin/ProjectAdminLazyTabs.svelte',
    'admin/ProjectAdminLifecycleTab.svelte',
    'admin/ProjectAdminComplianceTab.svelte',
    'admin/ProjectAdminOptimizeVegTab.svelte',
    'admin/ProjectAdminMergeTab.svelte',
  ]
    .map((f) => readSrc(f))
    .join('\n');
}

function readShellComposite() {
  return [
    'App.svelte',
    'shell/ShellFrame.svelte',
    'shell/ShellChromeHeader.svelte',
    'shell/ShellWorkspaceRouter.svelte',
    'shell/ShellEntryHost.svelte',
    'shell/ShellDeferredViews.svelte',
    'shell/ShellOverlays.svelte',
    'shell/PlotsBrowserPanel.svelte',
    'shell/WorkspaceStatusBanners.svelte',
    'shell/operationGuard.svelte.ts',
    'shell/shellLifecycleOps.ts',
    'shell/shellPlotOps.ts',
    'shell/shellUiController.svelte.ts',
  ]
    .map((f) => readSrc(f))
    .join('\n');
}

function readReportComposite(kind = 'long-vegetation') {
  if (kind === 'long-environment') {
    return (
      readSrc('reports/LongEnvironmentReport.svelte') +
      '\n' +
      readSrc('reports/parts/LongEnvironmentPreviewBody.svelte')
    );
  }
  const partsDir = path.join(SRC_ROOT, 'reports', 'parts');
  const partFiles = existsSync(partsDir)
    ? readdirSync(partsDir)
        .filter((f) => f.startsWith('LongVegetation') && f.endsWith('.svelte'))
        .sort((a, b) => {
          const rank = (f) => (f.includes('PreviewBody') ? 2 : f.includes('WorkbookPanel') ? 1 : 0);
          return rank(a) - rank(b) || a.localeCompare(b);
        })
        .map((f) => readFileSync(path.join(partsDir, f), 'utf8'))
    : [];
  return [
    ...partFiles,
    readSrc('reports/LongVegetationReport.svelte'),
    readSrc('reports/LongVegetationPreferenceSection.svelte'),
  ].join('\n');
}

function renderShellDeferredViews(view, state, extraProps = {}) {
  const { render } = require('svelte/server');
  const comp = serverComponent(readSrc('shell/ShellDeferredViews.svelte'), 'shell/ShellDeferredViews.svelte', {
    '../shared/state': {
      projectState: {
        subscribe(fn) {
          fn(state);
          return () => {};
        },
        set() {},
      },
    },
  });
  return render(comp, {
    props: {
      view,
      panelHold: false,
      companionPanelBusy: false,
      localEditorBusy: false,
      secondaryPanelBusy: false,
      workbenchDirtyLabel: '',
      projectAdminTab: 'lifecycle',
      projectAdminTabNonce: 0,
      plotLabelNumber: '',
      pictureManagerPlot: '',
      stateReads: new serverReads.ReadRequests(),
      refresh: async () => {},
      onOpenPlot: () => {},
      ...extraProps,
    },
  }).body.replace(/<!--[\s\S]*?-->/g, '').trim();
}

function createTestReportOperationGuard(options = {}) {
  const runtime = require('svelte/internal/client');
  const noopSession = () => ({
    view: () => ({ busy: false, blocked: false, closeBlocked: false }),
    held: () => false,
    subscribe: () => () => {},
  });
  const defaultDeps = {
    './externalSUEnvironment': { subscribeExternalSUEnvironmentActivity: () => () => {} },
    './twoPageSoilActivity': { subscribeTwoPageSoilActivity: () => () => {} },
    './twoPageVegetationActivity': { subscribeTwoPageVegetationActivity: () => () => {} },
    './tableCSVArchiveExport': { tableCSVArchivePublicationSession: noopSession },
    './pictureCreationActivity': { subscribePictureCreationActivity: () => () => {} },
    './pictureLifecycleActivity': { subscribePictureLifecycleActivity: () => () => {} },
    './lifeformWorkbook': { lifeformWorkbookPublicationSession: noopSession },
    './longVegetationProjectWorkspaces': { projectReportWorkspace: null },
    './siteUnitSummaryExtendedWorkbook': { extendedSummaryWorkbookPublicationSession: noopSession },
    './siteUnitSummaryWorkbook': { siteUnitSummaryWorkbookPublicationSession: noopSession },
    './subzoneMatrixReport': { matrixPublicationSession: noopSession },
    './summaryVegetationEnvironmentalDesktop': { summaryEnvironmentalEnabled: false, summaryEnvironmentalDesktop: {} },
    './summaryVegetationFieldListDesktop': { summaryVegetationFieldListDesktop: { enabled: false } },
    './summaryVegetationPreferences': { summaryVegetationPreferenceSession: null },
    './summaryVegetationPresentationPreferences': { summaryVegetationPresentationPreferenceSession: null },
    './summaryVegetationQualityPreferences': { summaryVegetationQualityPreferenceSession: null },
    './summaryVegetationWorkbook': { summaryVegetationWorkbookSession: noopSession },
    './vegetationWorkbook': { vegetationWorkbookPublicationSession: noopSession },
    ...(options.dependencies ?? {}),
  };
  const mod = loadReactiveRuneModule('shell/operationGuard.svelte.ts', defaultDeps);
  const stateBox = runtime.state(
    options.initialState ?? {
      contextId: 'ctx-1',
      activeProject: 'Sample',
      projectPath: 'C:\\project.db',
      activeSU: 'Selected',
      suPath: 'C:\\external.db',
      activeHierarchy: 'None',
      hierarchyPath: '',
    }
  );
  let currentView = options.initialView ?? 'home';
  let guard;
  const dispose = runtime.effect_root(() => {
    guard = mod.createOperationGuard();
    mod.bindShellActivitySubscriptions(
      guard,
      () => runtime.get(stateBox),
      ({ view }) => {
        if (currentView === 'home') currentView = view;
      }
    );
  });
  Object.defineProperty(guard, 'publicationBusy', {
    get: () => guard.isBusy(),
    enumerable: true,
    configurable: true,
  });
  runtime.flush();
  return {
    guard,
    get view() {
      return currentView;
    },
    set view(v) {
      currentView = v;
    },
    setState(s) {
      runtime.set(stateBox, s);
      runtime.flush();
    },
    flush: () => runtime.flush(),
    dispose,
  };
}

module.exports = {
  SRC_ROOT,
  buildSrcIndex,
  srcPath,
  readSrc,
  srcFiles,
  canonicalLocalSpecifier,
  resolveDependency,
  serverComponent,
  loadTypeScript,
  loadReactiveRuneModule,
  createFS882TestController,
  readFS882Composite,
  readShellComposite,
  readSidebarComposite,
  readPlotProfileComposite,
  readTwoPageComposite,
  readProjectPlotProfileComposite,
  readProjectAdminComposite,
  readReportComposite,
  renderShellDeferredViews,
  createTestReportOperationGuard,
  componentFunctions,
  presentationHelpers,
  qualityPreferenceHelpers,
  noopNotificationsStub,
  serverReads,
};
