const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const vm = require('node:vm');
const ts = require('typescript');
const { compile } = require('svelte/compiler');
const { render } = require('svelte/server');
const { writable, get } = require('svelte/store');

const FE_ROOT = path.resolve(__dirname, '..');
const SRC_ROOT = path.join(FE_ROOT, 'src');

function readSrc(relPath) {
  return readFileSync(path.join(SRC_ROOT, relPath), 'utf8');
}

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

function runTsModule(relPath, deps = {}, globals = {}) {
  const filePath = path.join(SRC_ROOT, relPath);
  const mod = { exports: {} };
  const ctx = {
    URL,
    URLSearchParams,
    Error,
    TypeError,
    Promise,
    Object,
    Array,
    Map,
    Set,
    Symbol,
    JSON,
    Math,
    Date,
    Number,
    String,
    Boolean,
    encodeURIComponent,
    decodeURIComponent,
    console,
    ...globals,
    module: mod,
    exports: mod.exports,
    require(specifier) {
      if (Object.hasOwn(deps, specifier)) {
        return deps[specifier];
      }
      if (specifier === 'svelte/store') {
        return { writable, get };
      }
      throw new Error(`Unexpected require("${specifier}") in ${relPath}`);
    },
  };
  ctx.globalThis = ctx;
  vm.runInNewContext(transpileTs(filePath), ctx, { filename: filePath });
  return mod.exports;
}

function loadWebModules({ webReadOnly = true, fetchImpl } = {}) {
  const projectState = writable(null);
  const webMetaStore = writable(null);
  const webShellRuntimeStore = writable(null);
  const stateMod = {
    projectState,
    webMeta: webMetaStore,
    webShellRuntime: webShellRuntimeStore,
  };
  const runtimeMode = runTsModule(
    'web/runtimeMode.ts',
    {},
    { __VPRO_WEB_READONLY__: webReadOnly }
  );
  const webMetaMod = runTsModule(
    'web/webMeta.ts',
    {
      '../shared/state': stateMod,
      './runtimeMode': runtimeMode,
    },
    {
      __VPRO_WEB_READONLY__: webReadOnly,
      fetch: fetchImpl,
    }
  );
  const webReadOnlyShell = runTsModule(
    'shell/webReadOnlyShell.ts',
    {
      '../web/runtimeMode': runtimeMode,
    },
    { __VPRO_WEB_READONLY__: webReadOnly }
  );
  const commandPalette = runTsModule(
    'shell/commandPalette.ts',
    {
      '../web/runtimeMode': runtimeMode,
      './webReadOnlyShell': webReadOnlyShell,
    },
    { __VPRO_WEB_READONLY__: webReadOnly }
  );
  return {
    projectState,
    webMetaStore,
    webShellRuntimeStore,
    stateMod,
    runtimeMode,
    webMetaMod,
    webReadOnlyShell,
    commandPalette,
  };
}

function compileSvelteServer(relPath, deps = {}, globals = {}) {
  const source = readSrc(relPath);
  const compiled = compile(source, {
    filename: path.join(SRC_ROOT, relPath),
    generate: 'server',
  });
  assert.equal(
    compiled.warnings.length,
    0,
    `${relPath} compiled with unexpected warnings: ${compiled.warnings.map((w) => w.message).join('; ')}`
  );
  const cjs = ts.transpileModule(compiled.js.code, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
      esModuleInterop: true,
    },
  }).outputText;

  const mod = { exports: {} };
  const iconStub = new Proxy(
    {},
    {
      get(_target, prop) {
        if (prop === '__esModule') return true;
        return () => '';
      },
    }
  );
  const ctx = {
    URL,
    URLSearchParams,
    Error,
    TypeError,
    Promise,
    Object,
    Array,
    Map,
    Set,
    Symbol,
    JSON,
    Math,
    Date,
    Number,
    String,
    Boolean,
    console,
    ...globals,
    module: mod,
    exports: mod.exports,
    require(specifier) {
      if (Object.hasOwn(deps, specifier)) {
        return deps[specifier];
      }
      if (specifier === '@lucide/svelte') {
        return iconStub;
      }
      if (specifier.startsWith('svelte')) {
        return require(specifier);
      }
      throw new Error(`Unexpected require("${specifier}") in compiled ${relPath}`);
    },
  };
  ctx.globalThis = ctx;
  vm.runInNewContext(cjs, ctx, { filename: relPath });
  return mod.exports.default;
}

test('webMeta loads /api/meta in web read-only mode, normalizes snake_case/camelCase, and skips fetch on desktop', async () => {
  let fetchCalls = 0;
  const desktop = loadWebModules({
    webReadOnly: false,
    fetchImpl: async () => {
      fetchCalls += 1;
      throw new Error('desktop must not call /api/meta');
    },
  });
  assert.equal(await desktop.webMetaMod.loadWebMeta(), null);
  assert.equal(fetchCalls, 0);

  const web = loadWebModules({
    webReadOnly: true,
    fetchImpl: async (url) => {
      fetchCalls += 1;
      assert.equal(url, '/api/meta');
      return {
        ok: true,
        status: 200,
        json: async () => ({
          snapshot_id: 'becmaster-2026-11',
          published_at: '2026-11-25T18:00:00Z',
          total_plot_count: 71567,
          redacted: true,
          redacted_plot_count: 1420,
          pictures_available: false,
          pmtiles_base_url: 'https://tiles.gov.bc.ca/vpro/',
          standards: {
            bec_version: 'BECdb v13',
            taxonomy_version: 'BCPlantTaxonomy v19',
            lmh25_version: 'LMH25 (2023)',
          },
          datasets: [
            {
              id: 'BECMaster',
              project: 'BECMaster',
              label: 'BECMaster Provincial',
              plot_count: 71567,
              redacted_plot_count: 1420,
              sus: [{ name: 'BECMaster_SU', compatible: true }],
              hierarchies: [{ name: 'BECMaster_Hierarchy', compatible: true }],
            },
          ],
        }),
      };
    },
  });

  const loaded = await web.webMetaMod.loadWebMeta();
  assert.equal(fetchCalls, 1);
  assert.ok(loaded);
  assert.equal(loaded.snapshotId, 'becmaster-2026-11');
  assert.equal(loaded.publishedAt, '2026-11-25T18:00:00Z');
  assert.equal(loaded.totalPlotCount, 71567);
  assert.equal(loaded.redacted, true);
  assert.equal(loaded.redactedPlotCount, 1420);
  assert.match(loaded.redactionNotice, /10 km/i);
  assert.equal(loaded.picturesAvailable, false);
  assert.equal(loaded.pmtilesBaseUrl, 'https://tiles.gov.bc.ca/vpro');
  assert.equal(web.webMetaMod.resolveWebPMTilesBaseUrl(loaded), 'https://tiles.gov.bc.ca/vpro');
  assert.equal(web.webMetaMod.getCachedWebMeta().snapshotId, 'becmaster-2026-11');
  assert.equal(get(web.webMetaStore).snapshotId, 'becmaster-2026-11');
  assert.equal(get(web.webMetaMod.webMetaError), '');

  // Cached second call does not hit fetch unless force: true
  await web.webMetaMod.loadWebMeta();
  assert.equal(fetchCalls, 1);

  // Explicit cache set & reset
  const custom = web.webMetaMod.normalizeWebMeta({
    snapshotId: 'manual-snap',
    picturesAvailable: true,
    datasets: [{ id: 'Haida', project: 'Haida', plotCount: 312 }],
  });
  web.webMetaMod.setWebMetaCache(custom);
  assert.equal(web.webMetaMod.getCachedWebMeta().snapshotId, 'manual-snap');
  assert.equal(web.webMetaMod.resolveWebPMTilesBaseUrl(custom), '/pmtiles');
  web.webMetaMod.resetWebMetaCache();
  assert.equal(web.webMetaMod.getCachedWebMeta(), null);
  assert.equal(get(web.webMetaStore), null);

  // Error handling records plain-language error
  const failed = await web.webMetaMod.loadWebMeta({
    force: true,
    fetchImpl: async () => ({ ok: false, status: 503 }),
  });
  assert.equal(failed, null);
  assert.match(get(web.webMetaMod.webMetaError), /HTTP 503/);

  // Export queue busy feedback (including exact vpro-web 503 unwrapped error strings)
  assert.equal(web.webMetaMod.isExportQueueBusyError(new Error('HTTP 503 export semaphore busy')), true);
  assert.equal(
    web.webMetaMod.isExportQueueBusyError(new Error('export worker pool is busy; please retry shortly')),
    true
  );
  assert.equal(
    web.webMetaMod.isExportQueueBusyError(new Error('R analytical worker pool is busy; please retry shortly')),
    true
  );
  assert.equal(web.webMetaMod.isExportQueueBusyError(new Error('invalid plot number')), false);
  assert.match(
    web.webMetaMod.formatWebDownloadFeedback(
      new Error('export worker pool is busy; please retry shortly'),
      'Download failed.'
    ),
    /wait a few seconds/i
  );
  assert.match(
    web.webMetaMod.formatWebDownloadFeedback(
      new Error('R analytical worker pool is busy; please retry shortly'),
      'Download failed.'
    ),
    /wait a few seconds/i
  );
  assert.match(
    web.webMetaMod.formatWebDownloadFeedback(new Error('429 Too Many Requests'), 'Download failed.'),
    /wait a few seconds/i
  );
  assert.equal(
    web.webMetaMod.formatWebDownloadFeedback(new Error('network reset'), 'Download failed.'),
    'Download failed.'
  );
  assert.ok(web.webMetaMod.VALID_WEB_URL_VIEWS.has('r-sidecar'));
  assert.equal(web.webMetaMod.VALID_WEB_URL_VIEWS.has('project-admin'), false);
  assert.equal(web.webMetaMod.WEB_HUB_WORKFLOW_OVERRIDES.interchange.title, 'Export & Downloads Hub');
});

test('URL state sync preserves literal leading-zero PlotNumber, replaces history idempotently, and blocks admin/log views', () => {
  const { webMetaMod, webReadOnlyShell } = loadWebModules({ webReadOnly: true });

  const parsed = webMetaMod.parseWebUrlState(
    '?dataset=BECMaster&su=BECMaster_SU&hierarchy=Master_Hier&view=fs882&plot=00337'
  );
  assert.deepEqual(
    { ...parsed },
    {
      dataset: 'BECMaster',
      su: 'BECMaster_SU',
      hierarchy: 'Master_Hier',
      view: 'fs882',
      plot: '00337',
    }
  );

  const query = webMetaMod.formatWebUrlQuery({
    dataset: 'BECMaster',
    su: 'None',
    hierarchy: '',
    view: 'fs882',
    plot: '00337',
  });
  assert.equal(query, '?dataset=BECMaster&view=fs882&plot=00337');

  const replaced = [];
  const fakeWin = {
    location: { pathname: '/', search: '', hash: '' },
    history: {
      replaceState(_data, _unused, url) {
        replaced.push(url);
        const qIdx = String(url).indexOf('?');
        fakeWin.location.search = qIdx >= 0 ? String(url).slice(qIdx) : '';
      },
    },
  };
  webMetaMod.syncWebUrlState({ dataset: 'BECMaster', view: 'r-sidecar', plot: '00337' }, fakeWin);
  webMetaMod.syncWebUrlState({ dataset: 'BECMaster', view: 'r-sidecar', plot: '00337' }, fakeWin);
  assert.deepEqual(replaced, ['/?dataset=BECMaster&view=r-sidecar&plot=00337']);

  const baseState = {
    contextId: 'ctx-1',
    activeProject: 'Sample',
    projectPath: '/data/Sample.db',
    activeSU: 'None',
    activeHierarchy: 'None',
    projects: [
      { name: 'Sample', path: '/data/Sample.db' },
      { name: 'BECMaster', path: '/data/BECMaster.db' },
    ],
    sus: [{ name: 'BECMaster_SU', path: '/data/BECMaster.db' }],
    hierarchies: [{ name: 'Master_Hier', path: '/data/BECMaster.db' }],
  };

  const plan = webMetaMod.planInitialWebUrlNavigation(
    '?dataset=BECMaster&su=BECMaster_SU&hierarchy=Master_Hier&view=fs882-twopage&plot=00337',
    baseState,
    true,
    webReadOnlyShell.isViewAllowedInWebReadOnly
  );
  assert.equal(plan.switchSelection?.project, 'BECMaster');
  assert.equal(plan.switchSelection?.su, 'BECMaster_SU');
  assert.equal(plan.switchSelection?.hierarchy, 'Master_Hier');
  assert.equal(plan.view, 'fs882');
  assert.equal(plan.editorEntryForm, 'fs882-twopage');
  assert.equal(plan.plotNumber, '00337');

  // Blocked views are ignored cleanly
  const blockedAdmin = webMetaMod.planInitialWebUrlNavigation(
    '?view=project-admin',
    baseState,
    true,
    webReadOnlyShell.isViewAllowedInWebReadOnly
  );
  assert.equal(blockedAdmin.view, undefined);

  const blockedPictures = webMetaMod.planInitialWebUrlNavigation(
    '?view=picture-manager',
    baseState,
    false,
    webReadOnlyShell.isViewAllowedInWebReadOnly
  );
  assert.equal(blockedPictures.view, undefined);

  const plotFallback = webMetaMod.planInitialWebUrlNavigation(
    '?plot=00337&view=user-log',
    baseState,
    true,
    webReadOnlyShell.isViewAllowedInWebReadOnly
  );
  assert.equal(plotFallback.view, 'fs882');
  assert.equal(plotFallback.plotNumber, '00337');
});

test('web read-only navigation & command palette exclude write/admin/audit/sync, hide pictures when unavailable, keep R sidecar, and use plain CBC labels', () => {
  const { webReadOnlyShell, commandPalette } = loadWebModules({ webReadOnly: true });

  assert.equal(webReadOnlyShell.WEB_READONLY_BLOCKED_VIEWS.has('project-admin'), true);
  assert.equal(webReadOnlyShell.WEB_READONLY_BLOCKED_VIEWS.has('user-log'), true);
  assert.equal(webReadOnlyShell.WEB_READONLY_BLOCKED_ACTIONS.has('new-sivi'), true);
  assert.equal(webReadOnlyShell.WEB_READONLY_BLOCKED_ACTIONS.has('cloud-sync'), true);
  assert.equal(webReadOnlyShell.WEB_READONLY_BLOCKED_ACTIONS.has('user-setup'), true);
  assert.equal(webReadOnlyShell.WEB_READONLY_BLOCKED_HELP_ACTIONS.has('reset-sample'), true);
  assert.equal(webReadOnlyShell.isViewAllowedInWebReadOnly('r-sidecar', false), true);
  assert.equal(webReadOnlyShell.isViewAllowedInWebReadOnly('picture-manager', false), false);
  assert.equal(webReadOnlyShell.isViewAllowedInWebReadOnly('picture-manager', true), true);
  assert.equal(webReadOnlyShell.defaultWebExportFilename('BEC Master/2026', '.xlsx'), 'BEC_Master_2026.xlsx');

  const sampleMenus = [
    {
      label: 'Forms',
      groups: [
        {
          label: 'Data Entry',
          items: [
            { name: 'FS882 Data Forms (6x4)', view: 'fs882' },
            { name: 'Two-Page Entry (FS882-8x6XL)', view: 'fs882-twopage' },
            { name: 'Enter/Edit SIVI Data', action: 'sivi' },
            { name: 'New SIVI / FS1333 Plot', action: 'new-sivi' },
            { name: 'Universal Datasheet Grid', view: 'datasheet' },
          ],
        },
        {
          label: 'Project & Classification',
          items: [
            { name: 'Project Metadata', action: 'metadata' },
            { name: 'Project Admin, QA & Merge', view: 'project-admin' },
            { name: 'Classification Explorer (SU & Hierarchy)', view: 'classification-explorer' },
            { name: 'Combine Species', view: 'lump-editor' },
          ],
        },
      ],
    },
    {
      label: 'Reports',
      groups: [
        {
          label: 'Diagnostics & Analysis',
          items: [
            { name: 'BEC Diagnostic Synthesis', view: 'diagnostic-synthesis' },
            { name: 'R Analytics, climr aSMR & Quarto Guides', view: 'r-sidecar' },
            { name: 'Plot Pictures', view: 'picture-manager' },
          ],
        },
      ],
    },
    {
      label: 'Tools',
      groups: [
        {
          label: 'Audit & Setup',
          items: [
            { name: 'User log', view: 'user-log' },
            { name: 'User setup', action: 'user-setup' },
            { name: 'Plot Labels (PDF)', view: 'plot-label-preview' },
          ],
        },
      ],
    },
    {
      label: 'Interchange',
      groups: [
        {
          label: 'Import & Export',
          items: [
            { name: 'Interchange Hub (VPro64, TurboVeg, RDS, GeoPackage)', view: 'interchange-hub' },
            { name: 'Cloud BECMaster Sync', action: 'cloud-sync' },
            { name: 'Project Table CSV Archive', view: 'table-csv' },
          ],
        },
      ],
    },
    {
      label: 'Help',
      groups: [
        {
          label: 'Release & Workspace',
          items: [
            { name: 'Reset Workspace to Sample', helpAction: 'reset-sample' },
            { name: 'About VPro & Standards Libraries', helpAction: 'about' },
          ],
        },
      ],
    },
  ];

  // Desktop mode leaves menus completely untouched
  const desktopMenus = webReadOnlyShell.filterNavigationMenusForMode(sampleMenus, false, false);
  assert.equal(desktopMenus[0].label, 'Forms');
  assert.ok(desktopMenus[0].groups[0].items.some((i) => i.action === 'new-sivi'));
  assert.ok(desktopMenus[1].groups[0].items.some((i) => i.view === 'picture-manager'));

  // Web read-only mode with picturesAvailable = false
  const webNoPics = webReadOnlyShell.filterNavigationMenusForMode(sampleMenus, true, false);
  const allItemsNoPics = webNoPics.flatMap((m) => m.groups.flatMap((g) => g.items));
  assert.equal(webNoPics[0].label, 'Plot Viewers');
  assert.equal(webNoPics[0].groups[0].label, 'Plot Viewers');
  assert.equal(webNoPics.find((m) => m.label === 'Downloads').groups[0].label, 'Export & Downloads');
  assert.ok(allItemsNoPics.some((i) => i.name === 'View SIVI Data'));
  assert.ok(allItemsNoPics.some((i) => i.view === 'r-sidecar'));
  assert.equal(allItemsNoPics.some((i) => i.action === 'new-sivi'), false);
  assert.equal(allItemsNoPics.some((i) => i.view === 'project-admin'), false);
  assert.equal(allItemsNoPics.some((i) => i.action === 'cloud-sync'), false);
  assert.equal(allItemsNoPics.some((i) => i.view === 'user-log'), false);
  assert.equal(allItemsNoPics.some((i) => i.action === 'user-setup'), false);
  assert.equal(allItemsNoPics.some((i) => i.helpAction === 'reset-sample'), false);
  assert.equal(allItemsNoPics.some((i) => i.view === 'picture-manager'), false);

  // Web read-only mode with picturesAvailable = true restores Plot Pictures
  const webWithPics = webReadOnlyShell.filterNavigationMenusForMode(sampleMenus, true, true);
  assert.ok(webWithPics.flatMap((m) => m.groups.flatMap((g) => g.items)).some((i) => i.view === 'picture-manager'));

  // Command palette filtering in web read-only mode
  const webPalette = commandPalette.buildCommandPaletteCatalog({
    plots: [{ plotNumber: '00337', zone: 'CWH', subzone: 'vm1', siteUnit: '01' }],
    activeProject: 'BECMaster',
    activeSU: 'BECMaster_SU',
    activeHierarchy: 'Master_Hier',
    selectedPlotNumber: '00337',
    metadataAvailable: true,
    newSiviAvailable: true,
    webReadOnly: true,
    picturesAvailable: false,
  });
  const viewsInPalette = new Set(
    webPalette.filter((item) => item.action?.kind === 'navigate-view').map((item) => item.action.view)
  );
  const actionsInPalette = new Set(webPalette.map((item) => item.action?.kind));
  assert.equal(viewsInPalette.has('project-admin'), false);
  assert.equal(viewsInPalette.has('user-log'), false);
  assert.equal(viewsInPalette.has('picture-manager'), false);
  assert.equal(actionsInPalette.has('open-new-sivi'), false);
  assert.equal(actionsInPalette.has('open-cloud-sync'), false);
  assert.equal(actionsInPalette.has('open-user-setup'), false);
  assert.equal(
    webPalette.some((item) => item.action?.kind === 'help-action' && item.action.action === 'reset-sample'),
    false
  );
  assert.equal(viewsInPalette.has('r-sidecar'), true);
  assert.equal(viewsInPalette.has('geospatial-map'), true);
  assert.equal(viewsInPalette.has('diagnostic-synthesis'), true);
  assert.equal(viewsInPalette.has('interchange-hub'), true);

  // Desktop command palette and webReadOnlyShell must use VPro64 instead of legacy VENUS 5 labels
  assert.doesNotMatch(readSrc('shell/commandPalette.ts'), /VENUS 5/i);
  assert.doesNotMatch(readSrc('shell/webReadOnlyShell.ts'), /VENUS 5/i);
  const desktopPalette = commandPalette.buildCommandPaletteCatalog({ webReadOnly: false });
  const interchangeItem = desktopPalette.find((i) => i.id === 'view-interchange');
  assert.ok(interchangeItem);
  assert.match(interchangeItem.title, /VPro64/);
  assert.doesNotMatch(interchangeItem.title, /VENUS 5/i);
});

test('WebSnapshotProvenance compiles and renders snapshot ID, date, plot count, and 10 km rare-plant redaction notice', () => {
  const { webMetaStore, webMetaMod, webReadOnlyShell } = loadWebModules({ webReadOnly: true });
  const meta = webMetaMod.normalizeWebMeta({
    snapshot_id: 'becmaster-2026-11-25',
    published_at: '2026-11-25T14:22:00Z',
    total_plot_count: 71567,
    redacted: true,
    redacted_plot_count: 1420,
    standards: { bec_version: 'BECdb v13', taxonomy_version: 'BCPlantTaxonomy v19' },
    datasets: [{ id: 'BECMaster', project: 'BECMaster', plot_count: 71567, redacted_plot_count: 1420 }],
  });
  webMetaStore.set(meta);

  const summary = webReadOnlyShell.formatSnapshotProvenance(meta, 'BECMaster', 0);
  assert.equal(summary.snapshotId, 'becmaster-2026-11-25');
  assert.equal(summary.publishedDate, '2026-11-25');
  assert.equal(summary.plotCount, 71567);
  assert.equal(summary.redacted, true);
  assert.match(summary.notice, /10 km/i);
  assert.equal(summary.standardsLabel, 'BECdb v13 · BCPlantTaxonomy v19');

  const Provenance = compileSvelteServer('shell/WebSnapshotProvenance.svelte', {
    '../shared/state': { webMeta: webMetaStore },
    './webReadOnlyShell': webReadOnlyShell,
  });

  const headerHtml = render(Provenance, { props: { variant: 'header', activeProject: 'BECMaster' } }).body;
  assert.match(headerHtml, /becmaster-2026-11-25/);
  assert.match(headerHtml, /2026-11-25/);
  assert.match(headerHtml, /10 km Rare-Plant Protection/i);

  const sidebarHtml = render(Provenance, { props: { variant: 'sidebar', activeProject: 'BECMaster' } }).body;
  assert.match(sidebarHtml, /71,567 plots/);
  assert.match(sidebarHtml, /rare-plant protection/i);

  const homeHtml = render(Provenance, { props: { variant: 'home', activeProject: 'BECMaster' } }).body;
  assert.match(homeHtml, /VPro Web Read-Only Portal/);
  assert.match(homeHtml, /71,567 plots/);
  assert.match(homeHtml, /rare-plant protection/i);
});

test('shellLifecycleOps skips CloseService handshake in web mode, blocks admin/log navigation, and restores URL state', async () => {
  const { projectState, webMetaStore, webShellRuntimeStore, stateMod, runtimeMode, webMetaMod, webReadOnlyShell } =
    loadWebModules({ webReadOnly: true });

  let closeEventsRegistered = 0;
  let pendingCloseCalls = 0;
  let refreshCalls = 0;
  const patched = [];
  const switchedCalls = [];
  const replacedUrls = [];

  const fakeWindow = {
    location: {
      pathname: '/',
      search: '?dataset=BECMaster&su=BECMaster_SU&view=r-sidecar&plot=00337',
      hash: '',
    },
    history: {
      replaceState(_d, _u, url) {
        replacedUrls.push(url);
      },
    },
  };

  webShellRuntimeStore.set({
    filterMenus: webReadOnlyShell.filterNavigationMenusForMode,
    isViewAllowed: webReadOnlyShell.isViewAllowedInWebReadOnly,
    hubOverrides: webMetaMod.WEB_HUB_WORKFLOW_OVERRIDES,
    planInitialUrl: (search, state, picturesAvailable) =>
      webMetaMod.planInitialWebUrlNavigation(
        search,
        state,
        picturesAvailable,
        webReadOnlyShell.isViewAllowedInWebReadOnly
      ),
    syncUrl: (urlState) => webMetaMod.syncWebUrlState(urlState, fakeWindow),
    ProvenanceBadge: () => '',
  });

  const lifecycleOps = runTsModule(
    'shell/shellLifecycleOps.ts',
    {
      '@wailsio/runtime': {
        Events: {
          On() {
            closeEventsRegistered += 1;
            return () => {};
          },
        },
      },
      '../../bindings/events': { VproCloseRequest: 'vpro:close-request' },
      '../../bindings/github.com/boostao/vpro/app': {},
      '../classification/projectPlotProfileReview': {
        profileNavigationPage: () => ({}),
        validateProfileNavigation: (x) => x,
      },
      '../help/helpSystem': { classifyGlobalHelpShortcut: () => null },
      '../shared/contextSessionRegistry': { onContextDisposed: () => {} },
      '../shared/dialogA11y': { installGlobalAriaModalTabTrap: () => () => {} },
      '../shared/readRequests': { formatError: (e) => String(e) },
      '../shared/state': stateMod,
      '../web/runtimeMode': runtimeMode,
      '../web/webMeta': {
        loadWebMeta: async () => null,
        bootstrapWebShellRuntime: async () => get(webShellRuntimeStore),
      },
      './closeLifecycle': { closeDisposition: () => 'clean' },
      './notificationService.svelte': { notifications: { push: () => {} } },
      './operationGuard.svelte': {
        CLOSE_HOLD_NOTICE: '',
        PAGING_HOLD_NOTICE: '',
        TRANSITION_HOLD_NOTICE: '',
      },
      './shellUiController.svelte': { lookupScopedPlotOp: async () => ({}) },
    },
    { __VPRO_WEB_READONLY__: true, window: fakeWindow }
  );

  // mountShellWindowLifecycle skips CloseService handshake in web mode
  const unmount = lifecycleOps.mountShellWindowLifecycle(
    { installViewportAndWhatsNew: () => () => {} },
    {
      GetPendingCloseRequest: async () => {
        pendingCloseCalls += 1;
        return 'req-1';
      },
    },
    () => {},
    () => {
      refreshCalls += 1;
    },
    () => {},
    () => {},
    true
  );
  assert.equal(closeEventsRegistered, 0);
  assert.equal(pendingCloseCalls, 0);
  assert.equal(refreshCalls, 1);
  unmount();

  // runNavigateOp blocks project-admin, user-log, and unavailable picture-manager, while allowing r-sidecar
  webMetaStore.set(webMetaMod.normalizeWebMeta({ picturesAvailable: false }));
  const makeSnap = () => ({
    state: { contextId: 'ctx-1', activeProject: 'BECMaster', activeSU: 'BECMaster_SU', activeHierarchy: 'None' },
    view: 'home',
    busy: false,
    editorEntryForm: 'fs882',
    editorPlotNumber: undefined,
    editor: undefined,
    selected: null,
    page: null,
    offset: 0,
    pageSize: 50,
    profileNavigation: null,
    standaloneMetadataPlot: '',
    startupFailure: null,
    closeRequest: '',
    closeWorking: false,
    pendingTransition: null,
    transitionWorking: false,
    ui: undefined,
    operationGuard: { isBusy: () => false, hasDirtyWorkbench: () => false },
    stateReads: { track: (p) => p, cancelAll: () => {} },
    plotReads: { track: (p) => p, cancelAll: () => {} },
    hierarchyReads: { track: (p) => p, cancelAll: () => {} },
    contextService: {
      SwitchContext: async (ctxId, sel) => {
        switchedCalls.push({ ctxId, sel });
        return {
          contextId: 'ctx-2',
          activeProject: sel.project,
          activeSU: sel.su,
          activeHierarchy: sel.hierarchy,
        };
      },
    },
    lifecycleService: {},
    notify: { push: () => {} },
    patch: (p) => patched.push(p),
    requestTransition: async (fn) => fn('ctx-1'),
    loadPlots: async () => {},
    loadHierarchy: async () => {},
    cancelAllReads: () => {},
    resetMainCaches: () => {},
    nextStateRequest: () => 1,
    isCurrentStateRequest: () => true,
    nextPlotRequest: () => 1,
    isCurrentPlotRequest: () => true,
    nextHierarchyRequest: () => 1,
    isCurrentHierarchyRequest: () => true,
    tick: async () => {},
  });

  await lifecycleOps.runNavigateOp(makeSnap, 'project-admin');
  await lifecycleOps.runNavigateOp(makeSnap, 'user-log');
  await lifecycleOps.runNavigateOp(makeSnap, 'picture-manager');
  assert.equal(patched.length, 0);

  await lifecycleOps.runNavigateOp(makeSnap, 'r-sidecar');
  assert.equal(patched.length, 1);
  assert.equal(patched[0].view, 'r-sidecar');

  // applyInitialWebUrlStateOp restores context, view, and plot from URL
  lifecycleOps.resetInitialWebUrlAppliedForTest();
  patched.length = 0;
  await lifecycleOps.applyInitialWebUrlStateOp(
    makeSnap,
    {
      contextId: 'ctx-1',
      activeProject: 'Sample',
      projectPath: '/data/Sample.db',
      activeSU: 'None',
      activeHierarchy: 'None',
      projects: [{ name: 'BECMaster', path: '/data/BECMaster.db' }],
      sus: [{ name: 'BECMaster_SU', path: '/data/BECMaster.db' }],
      hierarchies: [],
    },
    1
  );
  assert.equal(switchedCalls.length, 1);
  assert.equal(switchedCalls[0].sel.project, 'BECMaster');
  assert.equal(get(projectState).activeProject, 'BECMaster');
  assert.equal(patched[0].view, 'r-sidecar');
  assert.equal(patched[0].editorPlotNumber, '00337');

  // syncShellWebUrlOp syncs via webShellRuntime
  lifecycleOps.syncShellWebUrlOp({
    state: { activeProject: 'BECMaster', activeSU: 'BECMaster_SU', activeHierarchy: 'None' },
    view: 'fs882',
    editorEntryForm: 'fs882-twopage',
    plotNumber: '00337',
  });
  assert.equal(replacedUrls.at(-1), '/?dataset=BECMaster&su=BECMaster_SU&view=fs882-twopage&plot=00337');
});

test('geospatialWorkbench resolves /pmtiles and custom pmtilesBaseUrl in web read-only mode without affecting desktop defaults', () => {
  const fgbStub = { decodePlotFeatureCollection: () => ({ type: 'FeatureCollection', features: [] }) };
  const computeStub = {
    computeTerrainStats: () => ({}),
    buildPointFeatureCollection: () => ({ type: 'FeatureCollection', features: [] }),
  };
  const desktopGeo = runTsModule(
    'spatial/geospatialWorkbench.ts',
    {
      './spatialFlatGeobuf': fgbStub,
      './spatialCompute': computeStub,
      '../web/runtimeMode': { IS_WEB_READONLY: false },
    },
    { __VPRO_WEB_READONLY__: false }
  );
  assert.equal(desktopGeo.resolvePMTilesArchiveUrl('bc_bgc_v13.pmtiles'), 'pmtiles:///maps/bc_bgc_v13.pmtiles');

  const webGeo = runTsModule(
    'spatial/geospatialWorkbench.ts',
    {
      './spatialFlatGeobuf': fgbStub,
      './spatialCompute': computeStub,
      '../web/runtimeMode': { IS_WEB_READONLY: true },
    },
    { __VPRO_WEB_READONLY__: true }
  );
  assert.equal(webGeo.resolvePMTilesArchiveUrl('bc_bgc_v13.pmtiles'), 'pmtiles:///pmtiles/bc_bgc_v13.pmtiles');
  assert.equal(
    webGeo.resolvePMTilesArchiveUrl('bc_bgc_v13.pmtiles', 'https://cdn.example.ca/tiles/'),
    'pmtiles://https://cdn.example.ca/tiles/bc_bgc_v13.pmtiles'
  );
  const style = webGeo.buildMapLibreGeospatialStyle(
    {
      bgc: true,
      ecosections: false,
      districts: false,
      plots: true,
      bcOpenMapsWMS: false,
    },
    {
      bgcPmtilesAvailable: true,
      adminPmtilesAvailable: false,
      pmtilesBaseUrl: '/pmtiles',
    }
  );
  assert.equal(style.sources.bc_bgc_pmtiles.url, 'pmtiles:///pmtiles/bc-bgc-v13.pmtiles');
});

test('read-only component guards exclude Audit Trail, Promote-to-SU, GIS stamps, Save AOI to SU, Import tabs, and Picture/Datasheet writes in web mode', () => {
  // 1. FS882: Audit Trail tab & save/lock/undo hidden in web mode
  const fs882CtrlSrc = readSrc('entry/fs882FormController.svelte.ts');
  assert.match(fs882CtrlSrc, /IS_WEB_READONLY/);
  assert.match(fs882CtrlSrc, /audit/);
  const fs882SoilSrc = readSrc('entry/FS882SoilTab.svelte');
  assert.match(fs882SoilSrc, /IS_WEB_READONLY/);
  const fs882ToolbarSrc = readSrc('entry/FS882Toolbar.svelte');
  assert.match(fs882ToolbarSrc, /IS_WEB_READONLY/);
  assert.match(fs882ToolbarSrc, /Ecosystem Plot Viewer/);

  // 2. Universal Datasheet: Edit toggle, Find & Replace, Paste, Insert/Delete hidden in web mode
  const DatasheetHeader = compileSvelteServer(
    'datasheet/DatasheetHeader.svelte',
    {
      './universalDatasheetGrid': {
        ALL_DATASHEET_KEYS: ['env'],
        isReadOnlyDatasheetTable: () => false,
      },
      '../web/runtimeMode': { IS_WEB_READONLY: true },
    },
    { __VPRO_WEB_READONLY__: true }
  );
  const dsHtml = render(DatasheetHeader, {
    props: {
      project: 'BECMaster',
      su: 'BECMaster_SU',
      hierarchy: 'Master_Hier',
      tables: [{ key: 'env', label: 'Environment', rowCount: 120, readOnly: false }],
      activeTableKey: 'env',
      page: { totalRows: 120, rows: [], columns: [] },
      activeTableReadOnly: false,
      activeChildTableEditable: true,
      onApplyFilter: () => {},
      onOpenInsert: () => {},
      onRequestDelete: () => {},
      onDiscard: () => {},
      onSave: () => {},
      onSelectTable: () => {},
    },
  }).body;
  assert.doesNotMatch(dsHtml, /Find &amp; Replace/i);
  assert.doesNotMatch(dsHtml, /Add Row/i);
  assert.doesNotMatch(dsHtml, /Delete Row/i);
  assert.doesNotMatch(dsHtml, /Save All/i);
  assert.match(dsHtml, /data-datasheet-readonly-badge/);
  assert.match(dsHtml, /Apply Filter/);

  // 3. R Sidecar: keeps climr/aSMR, clustering, and Quarto while excluding Promote-to-SU
  const clusterProps = {
    activeProject: 'BECMaster',
    activeSu: 'BECMaster_SU',
    busy: false,
    clusterMethod: 'KM',
    clusterK: 4,
    dendrogramLayout: { maxHeight: 0, width: 600, height: 200, segments: [], leaves: [], cutY: null },
    clusterResult: null,
    onSubmitClustering: () => {},
    onSubmitPromote: () => {},
  };
  const RSidecarClusteringTabWeb = compileSvelteServer(
    'rsidecar/RSidecarClusteringTab.svelte',
    { '../web/runtimeMode': { IS_WEB_READONLY: true } },
    { __VPRO_WEB_READONLY__: true }
  );
  const rClusterHtml = render(RSidecarClusteringTabWeb, { props: clusterProps }).body;
  assert.match(rClusterHtml, /Run R Clustering/i);
  assert.doesNotMatch(rClusterHtml, /data-rsidecar-promote-card/);
  assert.doesNotMatch(rClusterHtml, /Promote Candidate to \*_SU/);
  const RSidecarClusteringTabDesktop = compileSvelteServer(
    'rsidecar/RSidecarClusteringTab.svelte',
    { '../web/runtimeMode': { IS_WEB_READONLY: false } },
    { __VPRO_WEB_READONLY__: false }
  );
  const rClusterDesktopHtml = render(RSidecarClusteringTabDesktop, { props: clusterProps }).body;
  assert.match(rClusterDesktopHtml, /data-rsidecar-promote-card/);
  assert.match(rClusterDesktopHtml, /Promote Candidate to \*_SU/);
  assert.match(
    readSrc('rsidecar/RSidecarWorkbench.svelte'),
    /submitPromoteCandidate\(\)\s*\{\s*if \(typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY\)/
  );

  // 4. Geospatial: Filter Plots by Polygon instead of Save AOI to SU; no Apply GIS_BGC Stamps
  const SpatialAOILassoTab = compileSvelteServer(
    'spatial/SpatialAOILassoTab.svelte',
    { '../web/runtimeMode': { IS_WEB_READONLY: true } },
    { __VPRO_WEB_READONLY__: true }
  );
  const aoiHtml = render(SpatialAOILassoTab, {
    props: {
      aoiDrawMode: false,
      aoiVertices: [
        [-123.1, 49.2],
        [-123.0, 49.2],
        [-123.0, 49.3],
      ],
      aoiMatches: [{ plotNumber: '00337', siteUnit: '01' }],
      aoiSiteUnit: '',
      aoiSaving: false,
      aoiBusy: false,
      aoiFilterActive: false,
      onToggleDraw: () => {},
      onClear: () => {},
      onSaveToSU: () => {},
      onToggleWebFilter: () => {},
    },
  }).body;
  assert.match(aoiHtml, /Filter Plots by Polygon/);
  assert.doesNotMatch(aoiHtml, /Save.*to Site Unit/i);

  const SpatialAuto1QATab = compileSvelteServer(
    'spatial/SpatialAuto1QATab.svelte',
    {
      '../web/runtimeMode': { IS_WEB_READONLY: true },
      './geospatialWorkbench': { filterSpatialQARows: (rows) => rows },
    },
    { __VPRO_WEB_READONLY__: true }
  );
  const qaHtml = render(SpatialAuto1QATab, {
    props: {
      qaReport: {
        totalPlots: 1,
        validCoordinates: 1,
        bgcMismatches: 1,
        rows: [
          {
            plotNumber: '00337',
            existingBGC: 'CWHvm1',
            gisBGC: 'CWHvm2',
            bgcMismatch: true,
            coordinateStatus: 'valid',
          },
        ],
      },
      qaSelectedPlots: {},
      loading: false,
      mutating: false,
      onReaudit: () => {},
      onApplyStamp: () => {},
      onOpenPlot: () => {},
    },
  }).body;
  assert.doesNotMatch(qaHtml, /Apply GIS_BGC Stamps/i);
  assert.match(qaHtml, /00337/);

  // 5. Interchange & Pictures read-only guards
  const interchangeSrc = readSrc('interchange/InterchangeHub.svelte');
  assert.match(interchangeSrc, /IS_WEB_READONLY/);
  const InterchangeHubHeader = compileSvelteServer(
    'interchange/InterchangeHubHeader.svelte',
    { '../web/runtimeMode': { IS_WEB_READONLY: true } },
    { __VPRO_WEB_READONLY__: true }
  );
  const hubHeaderHtml = render(InterchangeHubHeader, {
    props: { section: 'analytics', busy: false, onSelectSection: () => {} },
  }).body;
  assert.match(hubHeaderHtml, /EXPORT &amp; DOWNLOADS/i);
  assert.doesNotMatch(hubHeaderHtml, /VENUS 5/i);
  assert.match(readSrc('interchange/InterchangeTurboVegTab.svelte'), /!IS_WEB_READONLY/);
  assert.match(readSrc('interchange/InterchangeUserSpeciesTab.svelte'), /!IS_WEB_READONLY/);
  assert.match(readSrc('pictures/PictureManager.svelte'), /IS_WEB_READONLY/);
  assert.match(readSrc('pictures/PicturePanel.svelte'), /IS_WEB_READONLY/);
  assert.match(readSrc('admin/ProjectMetadataEditor.svelte'), /IS_WEB_READONLY/);
  assert.match(readSrc('admin/ProjectMetadataFieldsPanel.svelte'), /IS_WEB_READONLY/);

  // 6. Plain CBC-level copy & zero emojis in new web files
  const emojiRe = /[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/u;
  for (const rel of ['web/webMeta.ts', 'shell/webReadOnlyShell.ts', 'shell/WebSnapshotProvenance.svelte']) {
    assert.equal(emojiRe.test(readSrc(rel)), false, `${rel} must contain zero emojis`);
  }
});
