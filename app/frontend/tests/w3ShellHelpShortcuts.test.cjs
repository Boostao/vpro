const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const { runInNewContext } = require('node:vm');
const { compile } = require('svelte/compiler');
const { render } = require('svelte/server');
const {
  loadTypeScript,
  serverComponent,
  componentFunctions,
  srcPath,
} = require('./svelteTestHelpers.cjs');

const REPO_ROOT = path.resolve(__dirname, '..', '..', '..');
const readSrc = (file) => readFileSync(srcPath(file), 'utf8');
const iconsProxy = new Proxy({}, { get: () => () => {} });

const bindingsStub = new Proxy(
  {},
  {
    get: (_t, service) =>
      new Proxy(
        {},
        {
          get: (_s, method) => (...args) =>
            Promise.resolve({ methodName: `main.${String(service)}.${String(method)}`, args }),
        }
      ),
  }
);

const help = loadTypeScript('helpSystem.ts', {
  '../../bindings/github.com/boostao/vpro/app': bindingsStub,
});
const enterNav = loadTypeScript('enterNavigation.ts');
const palette = loadTypeScript('commandPalette.ts');

function createDomChain(levels) {
  let parent = null;
  for (const attrs of levels) {
    const node = {
      parentElement: parent,
      getAttribute(name) {
        return Object.prototype.hasOwnProperty.call(attrs, name) ? attrs[name] : null;
      },
      closest(selector) {
        const parts = selector
          .split(',')
          .map((s) => s.trim())
          .map((s) => {
            const m = s.match(/^\[([a-z0-9-]+)\]$/i);
            return m ? m[1] : null;
          })
          .filter(Boolean);
        let cur = node;
        while (cur) {
          if (parts.some((attr) => cur.getAttribute(attr) !== null)) return cur;
          cur = cur.parentElement;
        }
        return null;
      },
    };
    parent = node;
  }
  return parent;
}

test('ENG-XCUT-008 + UX-SHELL-004: nearest-ancestor contextual F1 never lets container data-help-id shadow field/column topics', () => {
  const bundleJson = JSON.parse(readFileSync(path.join(REPO_ROOT, 'app', 'resources', 'help_bundle.json'), 'utf8'));
  const validFieldIds = new Set(bundleJson.fields.map((f) => f.id));

  // 1. FS882 Vegetation cells inside form/tab containers
  const vegSpeciesCell = createDomChain([
    { 'data-help-id': 'site.plot_number' },
    { 'data-source-form': 'SubVegAXL_BC' },
    { 'data-column': 'Species' },
  ]);
  const speciesId = help.resolveContextualHelpTarget(vegSpeciesCell, 'fs882', 'fs882');
  assert.equal(speciesId, 'veg.species');
  assert.ok(validFieldIds.has(speciesId));

  const vegCoverCell = createDomChain([
    { 'data-help-id': 'site.plot_number' },
    { 'data-source-form': 'SubVegCXL' },
    { 'data-column': 'Cover6' },
  ]);
  assert.equal(help.resolveContextualHelpTarget(vegCoverCell, 'fs882', 'fs882'), 'veg.covers');

  const vegAttrCell = createDomChain([
    { 'data-help-id': 'veg.covers' },
    { 'data-column': 'AF' },
  ]);
  assert.equal(help.resolveContextualHelpTarget(vegAttrCell, 'fs882', 'fs882'), 'veg.species');

  // 2. Soil Humus & Mineral cells inside section wrappers carrying container data-help-id
  const humusVonPost = createDomChain([
    { 'data-help-id': 'humus.upper_lower_depth', 'data-source-form': 'SoilHumusXL' },
    { 'data-column': 'VonPost' },
  ]);
  assert.equal(help.resolveContextualHelpTarget(humusVonPost, 'fs882', 'fs882'), 'humus.von_post');

  const humusHorizon = createDomChain([
    { 'data-help-id': 'humus.upper_lower_depth', 'data-two-page-soil-panel': 'SoilHumusXL' },
    { 'data-soil-column': 'Horizon' },
  ]);
  assert.equal(help.resolveContextualHelpTarget(humusHorizon, 'fs882', 'fs882-twopage'), 'humus.horizon');

  const mineralHorizon = createDomChain([
    { 'data-help-id': 'mineral.texture_cf', 'data-source-form': 'SoilMineralXL' },
    { 'data-column': 'Horizon' },
  ]);
  assert.equal(help.resolveContextualHelpTarget(mineralHorizon, 'fs882', 'fs882'), 'mineral.horizon');

  const mineralCoarseFrags = createDomChain([
    { 'data-help-id': 'mineral.horizon', 'data-source-form': 'SoilMineralXL' },
    { 'data-column': 'PercentCoarseFragsTotal' },
  ]);
  assert.equal(help.resolveContextualHelpTarget(mineralCoarseFrags, 'fs882', 'fs882'), 'mineral.texture_cf');

  // 3. SIVI shared site fields inside SIVI form
  const siviMoisture = createDomChain([
    { 'data-help-id': 'sivi.plot_type' },
    { 'data-sivi-shared-field': 'MoistureRegime' },
  ]);
  assert.equal(help.resolveContextualHelpTarget(siviMoisture, 'fs882', 'sivi'), 'site.moisture_regime');

  const siviElevation = createDomChain([
    { 'data-help-id': 'sivi.plot_type' },
    { 'data-sivi-shared-field': 'Elevation' },
  ]);
  assert.equal(help.resolveContextualHelpTarget(siviElevation, 'fs882', 'sivi'), 'site.elevation');

  // 4. Universal Datasheet Grid cells & column filters with data-datasheet-table + data-column
  const datasheetMineralCell = createDomChain([
    { 'data-datasheet-table': 'Mineral' },
    { 'data-column': 'Horizon' },
  ]);
  assert.equal(help.resolveContextualHelpTarget(datasheetMineralCell, 'datasheet'), 'mineral.horizon');

  const datasheetHumusCell = createDomChain([
    { 'data-datasheet-table': 'Humus' },
    { 'data-column': 'Horizon' },
  ]);
  assert.equal(help.resolveContextualHelpTarget(datasheetHumusCell, 'datasheet'), 'humus.horizon');

  const datasheetEnvCell = createDomChain([
    { 'data-datasheet-table': 'Env' },
    { 'data-column': 'FSRegionDistrict' },
  ]);
  assert.equal(help.resolveContextualHelpTarget(datasheetEnvCell, 'datasheet'), 'site.ecosection');

  // 5. Verify FS882Form root container no longer carries outer data-help-id and DatasheetVirtualTable emits data-column
  const fs882Src = readSrc('FS882Form.svelte');
  const rootContainerOpenTag = fs882Src.match(/<div[^>]*class="fs882-container[^"]*"[^>]*>/)?.[0] ?? '';
  assert.ok(rootContainerOpenTag, 'fs882-container tag must exist');
  assert.doesNotMatch(rootContainerOpenTag, /data-help-id=/, 'root fs882-container must not shadow child inputs');

  const virtTableSrc = readSrc('DatasheetVirtualTable.svelte');
  assert.match(virtTableSrc, /data-datasheet-table=\{page\.tableKey\}/);
  assert.match(virtTableSrc, /data-column=\{colMeta\.name\}/);
});

test('ENG-XCUT-008 + UX-SHELL-004: Shift+Enter reverse navigation, Ctrl+F filters, Ctrl+S metadata, and docs-src parity', () => {
  // 1. Shift+Enter reverse navigation in field & record modes
  const pos = (extra = {}) => ({
    form: null,
    record: null,
    column: 'FieldNo',
    enabled: true,
    visible: true,
    invalid: false,
    ...extra,
  });
  const fieldPositions = [
    pos({ column: 'PlotNumber' }),
    pos({ column: 'LockedField', enabled: false }),
    pos({ column: 'HiddenField', visible: false }),
    pos({ column: 'Elevation' }),
  ];
  assert.equal(enterNav.nextEnterPosition(fieldPositions, 3, 'field', true), 0);
  assert.equal(enterNav.nextEnterPosition(fieldPositions, 0, 'field', true), null);

  const recBase = pos({ form: 'SubVegCXL', record: '1', column: 'Cover6' });
  const recPositions = [
    recBase,
    pos({ ...recBase, record: '2', enabled: false }),
    pos({ ...recBase, record: '3', column: 'Species' }),
    pos({ ...recBase, record: '3', column: 'Cover6' }),
  ];
  assert.equal(enterNav.nextEnterPosition(recPositions, 3, 'record', true), 0);
  assert.equal(enterNav.nextEnterPosition(recPositions, 0, 'record', true), null);

  // DOM-level Shift+Enter backward focus check
  const fakeDoc = { activeElement: null };
  class FakeControl {
    constructor(col, rec = null) {
      this.dataset = { column: col };
      this.recordId = rec;
      this.type = 'text';
      this.readOnly = false;
      this.focused = 0;
    }
    matches() { return false; }
    checkVisibility() { return true; }
    getAttribute() { return null; }
    closest(sel) {
      if (sel.includes('dialog')) return null;
      if (sel === '[data-source-form]') return this.sourceArea;
      if (sel === '[data-record-id]') return this.recordId ? { dataset: { recordId: this.recordId } } : null;
      return this.page;
    }
    focus() { fakeDoc.activeElement = this; this.focused++; }
  }
  const domNav = loadTypeScript('enterNavigation.ts', {}, {
    document: fakeDoc,
    HTMLInputElement: FakeControl,
    HTMLSelectElement: class {},
    HTMLTextAreaElement: class {},
  });
  const row1Cover = new FakeControl('Cover6', '101');
  const row2Cover = new FakeControl('Cover6', '102');
  const sourceArea = {
    dataset: { sourceForm: 'SubVegCXL' },
    querySelectorAll: () => [row1Cover, row2Cover],
  };
  const pageEl = {
    dataset: {},
    contains: (el) => el === row1Cover || el === row2Cover,
    querySelectorAll: () => [row1Cover, row2Cover],
  };
  row1Cover.sourceArea = sourceArea;
  row2Cover.sourceArea = sourceArea;
  row1Cover.page = pageEl;
  row2Cover.page = pageEl;
  fakeDoc.activeElement = row2Cover;
  let prevented = false;
  domNav.navigateSourceEnter(
    {
      key: 'Enter',
      defaultPrevented: false,
      isComposing: false,
      repeat: false,
      altKey: false,
      ctrlKey: false,
      metaKey: false,
      shiftKey: true,
      target: row2Cover,
      preventDefault() { prevented = true; },
    },
    pageEl
  );
  assert.equal(prevented, true);
  assert.equal(fakeDoc.activeElement, row1Cover);

  // 2. Ctrl+F handlers in PlotsBrowserPanel, UniversalDatasheetGrid, ClassificationExplorer + Ctrl+S in ProjectMetadataEditor
  for (const file of [
    'PlotsBrowserPanel.svelte',
    'UniversalDatasheetGrid.svelte',
    'ClassificationExplorer.svelte',
  ]) {
    const src = readSrc(file);
    assert.match(src, /key\.toLowerCase\(\)\s*===\s*'f'/, `${file} must handle Ctrl+F / Cmd+F`);
  }
  const metaEditorSrc = readSrc('ProjectMetadataEditor.svelte');
  assert.match(metaEditorSrc, /<svelte:window onkeydown=\{handleKeydown\}/);
  assert.match(metaEditorSrc, /key\.toLowerCase\(\)\s*===\s*'s'/);

  // 3. docs-src/shortcuts.json, docs-src/lmh25_fields.json, and compiled app/resources/help_bundle.json parity
  const shortcutsJson = JSON.parse(readFileSync(path.join(REPO_ROOT, 'docs-src', 'shortcuts.json'), 'utf8'));
  const lmh25Json = JSON.parse(readFileSync(path.join(REPO_ROOT, 'docs-src', 'lmh25_fields.json'), 'utf8'));
  const bundleJson = JSON.parse(readFileSync(path.join(REPO_ROOT, 'app', 'resources', 'help_bundle.json'), 'utf8'));

  assert.equal(shortcutsJson[4].keys, 'Ctrl+S');
  assert.ok(shortcutsJson.some((s) => s.keys === 'Ctrl+K'));
  assert.ok(shortcutsJson.some((s) => s.keys === 'Alt+P'));
  assert.deepEqual(bundleJson.shortcuts, shortcutsJson);

  const ecosection = bundleJson.fields.find((f) => f.id === 'site.ecosection');
  assert.match(ecosection.column, /FSRegionDistrict/);
  assert.doesNotMatch(ecosection.column, /ForestRegionDistrict/);

  const elevation = bundleJson.fields.find((f) => f.id === 'site.elevation');
  assert.match(elevation.unit, /0–359/);
  assert.doesNotMatch(JSON.stringify(elevation), /0–360/);

  const substrate = bundleJson.fields.find((f) => f.id === 'site.substrate_cover');
  assert.match(substrate.rules[0], /0\.01%/);
  assert.deepEqual(bundleJson.fields, lmh25Json.fields);
});

test('UX-ENV-006 + UX-SHELL-007: Two-Page Entry without selected plot renders plot picker prompt and exposes plot copy/remove actions', async () => {
  const { readFS882Composite } = require('./svelteTestHelpers.cjs');
  const fs882Src = readFS882Composite();
  assert.match(fs882Src, /data-twopage-select-plot-prompt/);
  assert.match(fs882Src, /Two-Page Entry \(FS882-8x6XL\) — Select a Plot/);
  assert.match(fs882Src, /data-manage-plot-btn/);
  assert.match(fs882Src, /data-manage-plot-panel/);

  // PlotsBrowserPanel detail rail renders Rename or Remove Plot disclosure when callbacks are provided
  const BrowserPanel = serverComponent(readSrc('PlotsBrowserPanel.svelte'), 'PlotsBrowserPanel.svelte', {
    '@lucide/svelte': iconsProxy,
    '../shared/state': { projectState: { subscribe: (fn) => { fn({ activeProject: 'Sample' }); return () => {}; } } },
  });
  const detailHtml = render(BrowserPanel, {
    props: {
      region: 'detail',
      view: 'plots',
      selected: { plotNumber: '00337', fieldNumber: 'F1', plotRepresenting: 'Subalpine', zone: 'ESSF', subZone: 'mc', siteSeries: '01' },
      oncopyplot: async () => {},
      onremoveplot: async () => {},
    },
  }).body;
  assert.match(detailHtml, /data-plot-identity-actions/);
  assert.match(detailHtml, /Rename or Remove Plot/);
  assert.match(detailHtml, /data-copy-plot-btn/);
  assert.match(detailHtml, /data-exclude-plot-splinter-btn/);

  // Behavioral test of App.svelte copyPlotToNewNumber and removePlotFromProject
  const calls = [];
  const ctx = componentFunctions('App.svelte', ['copyPlotToNewNumber', 'removePlotFromProject', 'collectAllProjectPlotNumbers', 'extractDatasheetPlotSummaries'], {
    busy: false,
    editorBusy: false,
    companionPanelBusy: false,
    transitionWorking: false,
    pendingTransition: null,
    closeRequest: '',
    view: 'plots',
    editor: undefined,
    workbenchDirtyLabel: '',
    offset: 0,
    page: { total: 2, plots: [{ plotNumber: '00337' }, { plotNumber: '8529415' }] },
    allAvailablePlots: [
      { plotNumber: '00337', fieldNumber: null, plotRepresenting: null, zone: 'ESSF', subZone: 'mc', siteSeries: '01' },
      { plotNumber: '8529415', fieldNumber: null, plotRepresenting: null, zone: 'BWBS', subZone: 'wk1', siteSeries: '01' },
    ],
    createdSiviPlots: [{ requestId: 'req-sivi-1', plotNumber: 'SIVI01', canUndo: true }],
    selected: { plotNumber: '00337' },
    editorPlotNumber: undefined,
    scopedCatalogKey: 'old',
    scopedPlotCatalogRows: [],
    dynamicPalettePlotRows: [],
    profileNavigation: null,
    diagnosticsDraft: null,
    $projectState: { contextId: 'ctx-1', activeProject: 'Sample', activeSU: 'None' },
    projectState: { set: (st) => calls.push(['setState', st]) },
    loadPlots: async () => calls.push(['loadPlots']),
    refreshScopedPlotCatalog: async () => calls.push(['refreshCatalog']),
    refresh: async () => calls.push(['refresh']),
    notifications: { success: (title) => calls.push(['notify', title]) },
    DatasheetService: {
      GetDatasheetPage: async () => ({
        totalRows: 2,
        columns: [{ name: 'PlotNumber' }, { name: 'Zone' }],
        rows: [
          { rowId: '1', cells: [{ text: '00337', integer: null, real: null }, { text: 'ESSF', integer: null, real: null }] },
          { rowId: '2', cells: [{ text: '8529415', integer: null, real: null }, { text: 'BWBS', integer: null, real: null }] },
        ],
      }),
    },
    ContextService: {
      GetPlot: async (_ctx, p) => {
        calls.push(['GetPlot', p]);
        return { plotNumber: p, fieldNo: 'FN-1', plotRepresenting: 'Loc', zone: 'ESSF', subZone: 'mc', siteSeries: '01', locked: true };
      },
      ListVegRecords: async () => [{ id: 11, plotNumber: '00337', species: 'ABIELAS', layer: 'A' }],
      ListHumusRecords: async () => [{ id: 21, plotNumber: '00337', horizon: 'L', upperDepth: 4, lowerDepth: 0 }],
      ListMineralRecords: async () => [{ id: 31, plotNumber: '00337', horizon: 'Bf', upperDepth: 0, lowerDepth: 25 }],
      ListOtherRecords: async () => [],
      CreatePlot: async (_ctx, h) => calls.push(['CreatePlot', h.plotNumber, h.locked]),
      SaveVegRecord: async (_ctx, r) => calls.push(['SaveVegRecord', r.plotNumber, r.id, r.species]),
      SaveHumusRecord: async (_ctx, r) => calls.push(['SaveHumusRecord', r.plotNumber, r.id, r.horizon]),
      SaveMineralRecord: async (_ctx, r) => calls.push(['SaveMineralRecord', r.plotNumber, r.id, r.horizon]),
      SaveOtherRecord: async (_ctx, r) => calls.push(['SaveOtherRecord', r.plotNumber, r.id]),
      UndoCreateSIVIPlot: async (_ctx, req) => calls.push(['UndoCreateSIVIPlot', req.creationRequestId, req.plotNumber]),
      ExportSplinterProject: async (_ctx, req) => {
        calls.push(['ExportSplinterProject', req.splinterProject, Array.from(req.plotNumbers)]);
        return { splinterProject: req.splinterProject, exportedPlotCount: req.plotNumbers.length, state: { contextId: 'ctx-2', activeProject: req.splinterProject } };
      },
    },
  });

  await assert.rejects(() => ctx.actions.copyPlotToNewNumber('00337', '00337'), /different/);
  await assert.rejects(() => ctx.actions.copyPlotToNewNumber('00337', '12345678'), /1 to 7 characters/);

  await ctx.actions.copyPlotToNewNumber('00337', '00888');
  assert.deepEqual(calls.slice(0, 5), [
    ['GetPlot', '00337'],
    ['CreatePlot', '00888', false],
    ['SaveVegRecord', '00888', 0, 'ABIELAS'],
    ['SaveHumusRecord', '00888', 0, 'L'],
    ['SaveMineralRecord', '00888', 0, 'Bf'],
  ]);

  calls.length = 0;
  await ctx.actions.removePlotFromProject('SIVI01', '');
  assert.deepEqual(calls[0], ['UndoCreateSIVIPlot', 'req-sivi-1', 'SIVI01']);

  calls.length = 0;
  await ctx.actions.removePlotFromProject('00337', 'Sample_Clean');
  assert.deepEqual(JSON.parse(JSON.stringify(calls[0])), ['ExportSplinterProject', 'Sample_Clean', ['8529415']]);
});

test('UX-ENV-007: Ctrl+K Quick Jump indexes all scoped plots beyond the 25-row first page', async () => {
  const all52 = Array.from({ length: 52 }, (_, i) => ({
    plotNumber: i === 27 ? '8529415' : String(i + 1).padStart(5, '0'),
    fieldNumber: `F-${i + 1}`,
    plotRepresenting: i === 27 ? 'Fort Nelson Lowland' : 'Plot site',
    zone: i === 27 ? 'BWBS' : 'ESSF',
    subZone: i === 27 ? 'wk1' : 'mc',
    siteSeries: '01',
  }));

  const listCalls = [];
  const ctx = componentFunctions('App.svelte', ['refreshScopedPlotCatalog'], {
    offset: 0,
    profileNavigation: null,
    scopedCatalogKey: '',
    scopedPlotCatalogRows: [],
    createdSiviPlots: [],
    catalogPlotRequest: 0,
    catalogPlotReads: { cancelAll() {}, track: (p) => p },
    $projectState: { contextId: 'ctx-sample', activeProject: 'Sample', activeSU: 'Sample' },
    ContextService: {
      ListCreatedSIVIPlots: async () => [],
      ListPlots: async (off, lim) => {
        listCalls.push([off, lim]);
        return { total: 52, plots: all52.slice(off, off + lim) };
      },
    },
  });

  await ctx.actions.refreshScopedPlotCatalog('ctx-sample', { total: 52, plots: all52.slice(0, 25) });
  assert.deepEqual(listCalls, [[0, 52]]);
  assert.equal(ctx.scopedPlotCatalogRows.length, 52);

  const catalog = palette.buildCommandPaletteCatalog({
    plots: ctx.scopedPlotCatalogRows.map((p) => ({
      plotNumber: p.plotNumber,
      siteUnit: p.siteSeries,
      zone: p.zone,
      subZone: p.subZone,
      location: p.plotRepresenting,
    })),
    projects: [],
    sus: [],
    selectedPlotNumber: null,
    activeSU: 'Sample',
    metadataAvailable: false,
    siviAvailable: true,
    newSiviAvailable: true,
  });

  const hits = palette.searchCommandPalette(catalog, '8529415');
  assert.ok(hits.length >= 2, 'Page-2 plot 8529415 must appear in Quick Jump results');
  assert.equal(hits[0].action.kind, 'open-plot-fs882');
  assert.equal(hits[0].action.plotNumber, '8529415');
});

test('UX-SHELL-003 + UX-SHELL-005: responsive topbar wrap, narrow-viewport Esc drawer close, Tour 1 backdrop restore, and Tour 2 scroll containment', async () => {
  const css = readSrc('vpro.css');

  // UX-SHELL-003: .main-nav does not shrink below intrinsic content width and .topbar wraps at <= 1560px
  const mainNavRule = css.match(/\.main-nav\s*\{([^}]*)\}/)?.[1] ?? '';
  assert.match(mainNavRule, /flex-shrink:\s*0/);
  assert.doesNotMatch(mainNavRule, /min-width:\s*0/);
  assert.match(css, /@media\s*\(max-width:\s*1560px\)\s*\{\s*\.topbar\s*\{/);

  // UX-SHELL-005 (3): .app-shell locks viewport height with .content { overflow-y: auto }
  const appShellRule = css.match(/\.app-shell\s*\{([^}]*)\}/)?.[1] ?? '';
  assert.match(appShellRule, /height:\s*100dvh/);
  assert.match(appShellRule, /overflow:\s*hidden/);
  const contentRule = css.match(/\.content\s*\{([^}]*)\}/)?.[1] ?? '';
  assert.match(contentRule, /overflow-y:\s*auto/);

  // UX-SHELL-005 (1): Escape closes narrow-viewport context/inspector drawer
  const appKeyCtx = componentFunctions('App.svelte', ['handleGlobalHelpKeydown'], {
    startupFailure: null,
    commandPaletteOpen: false,
    notificationDrawerOpen: false,
    shortcutsModalOpen: false,
    whatsNewModalOpen: false,
    aboutModalOpen: false,
    tourOpen: false,
    resetSampleConfirmOpen: false,
    userSetupOpen: false,
    closeRequest: '',
    pendingTransition: null,
    helpDrawerOpen: false,
    isNarrowViewport: true,
    contextExpanded: true,
    inspectorExpanded: true,
    showInspectorRail: true,
    classifyGlobalHelpShortcut: () => null,
    openContextualHelp: () => {},
  });
  let escPrevented = false;
  appKeyCtx.actions.handleGlobalHelpKeydown({
    key: 'Escape',
    ctrlKey: false,
    metaKey: false,
    preventDefault() { escPrevented = true; },
  });
  assert.equal(escPrevented, true);
  assert.equal(appKeyCtx.contextExpanded, false);
  assert.equal(appKeyCtx.inspectorExpanded, false);

  // UX-SHELL-005 (2): OnboardingTour calls onrestorecontext on dismiss, finish, and returnToCatalog
  let restored = 0;
  let closed = 0;
  const tourCtx = componentFunctions('OnboardingTour.svelte', ['dismissTour', 'nextStep', 'returnToCatalog'], {
    activeTour: {
      id: 'tour-session-import',
      title: 'Session Context',
      steps: [
        { id: 's1', title: 'Step 1', target: '#project-context', body: 'Body' },
        { id: 's2', title: 'Step 2', target: '[data-command-palette-trigger]', body: 'Body' },
      ],
    },
    stepIndex: 1,
    activeTourId: 'tour-session-import',
    completedTourTitle: '',
    targetRect: null,
    targetWaiting: false,
    stopTargetTracking() {},
    onrestorecontext: () => { restored++; },
    onclose: () => { closed++; },
  });
  await tourCtx.actions.nextStep();
  assert.equal(restored, 1, 'Finishing a tour must restore temporary context drawer state');
  tourCtx.actions.returnToCatalog();
  assert.equal(restored, 2, 'Returning to catalog must restore temporary context drawer state');
  tourCtx.actions.dismissTour();
  assert.equal(restored, 3, 'Dismissing a tour must restore temporary context drawer state');
  assert.equal(closed, 1);
});

test('UX-VEG-005: FS882Form and FS882StratumSummary fall back to sublayer covers when TotalA/TotalB are null and cap stratum totals at 99%', () => {
  const { createFS882TestController } = require('./svelteTestHelpers.cjs');
  const StratumSummary = serverComponent(readSrc('FS882StratumSummary.svelte'), 'FS882StratumSummary.svelte', {
    '@lucide/svelte': iconsProxy,
  });

  const evalTotals = (vegList, vegetationReadUnavailable = null) => {
    const h = createFS882TestController();
    try {
      h.ctrl.cw.vegList = vegList;
      if (vegetationReadUnavailable !== null) {
        h.ctrl.children.vegetationReadUnavailable = vegetationReadUnavailable;
      }
      h.flush();
      return {
        totalTreeCover: vegetationReadUnavailable ? null : h.ctrl.cw.totalTreeCover,
        totalShrubCover: vegetationReadUnavailable ? null : h.ctrl.cw.totalShrubCover,
        totalHerbCover: vegetationReadUnavailable ? null : h.ctrl.cw.totalHerbCover,
        totalMossCover: vegetationReadUnavailable ? null : h.ctrl.cw.totalMossCover,
      };
    } finally {
      h.dispose();
    }
  };

  // 1. Sample plot 00337 exact reproduction: TotalA/TotalB are null, sublayers hold 10+4, 2, and 20
  const plot00337Rows = [
    { id: 1, species: 'ABIELAS', layer: 'A', cover1: 10, cover2: 4, cover3: null, totalA: null, cover4: null, cover5: null, totalB: null, cover6: null, cover7: null },
    { id: 2, species: 'PINUCON', layer: 'A', cover1: null, cover2: 2, cover3: null, totalA: null, cover4: null, cover5: null, totalB: null, cover6: null, cover7: null },
    { id: 3, species: 'ALNUALN1', layer: 'B', cover1: null, cover2: null, cover3: null, totalA: null, cover4: 20, cover5: null, totalB: null, cover6: null, cover7: null },
    { id: 4, species: 'CORNCAN', layer: 'C', cover1: null, cover2: null, cover3: null, totalA: null, cover4: null, cover5: null, totalB: null, cover6: 15, cover7: null },
    { id: 5, species: 'PLEUSCH', layer: 'D', cover1: null, cover2: null, cover3: null, totalA: null, cover4: null, cover5: null, totalB: null, cover6: null, cover7: 35 },
  ];
  const totals00337 = evalTotals(plot00337Rows);
  assert.deepEqual(totals00337, {
    totalTreeCover: 16,
    totalShrubCover: 20,
    totalHerbCover: 15,
    totalMossCover: 35,
  });
  // Raw rows are never mutated
  assert.equal(plot00337Rows[0].totalA, null);
  assert.equal(plot00337Rows[2].totalB, null);

  const summaryHtml = render(StratumSummary, {
    props: { vegList: plot00337Rows },
  }).body;
  assert.match(summaryHtml, /Tree Layer \(A\)[\s\S]*?16\.0%/);
  assert.match(summaryHtml, /Shrub Layer \(B\)[\s\S]*?20\.0%/);
  assert.match(summaryHtml, /Herb Layer \(C\)[\s\S]*?15\.0%/);
  assert.match(summaryHtml, /Moss\/Lichen \(D\)[\s\S]*?35\.0%/);

  // 2. Authoritative explicit 0 is respected, and sums > 99% cap at 99.0% (AGENTS.md §3.3)
  const capAndExplicitZeroRows = [
    { id: 1, species: 'PSEUMEN', layer: 'A', cover1: 25, cover2: 10, cover3: null, totalA: 0, cover4: 60, cover5: 30, cover5a: 25, totalB: null, cover6: 70, cover7: 80 },
    { id: 2, species: 'TSUGHET', layer: 'A', cover1: 65, cover2: 50, cover3: null, totalA: null, cover4: 20, cover5: null, totalB: null, cover6: 45, cover7: 40 },
  ];
  const cappedTotals = evalTotals(capAndExplicitZeroRows);
  assert.deepEqual(cappedTotals, {
    totalTreeCover: 99,
    totalShrubCover: 99,
    totalHerbCover: 99,
    totalMossCover: 99,
  });
  const cappedHtml = render(StratumSummary, {
    props: { vegList: capAndExplicitZeroRows },
  }).body;
  assert.equal((cappedHtml.match(/99\.0%/g) ?? []).length, 4, 'All 4 strata must cap at 99.0%');

  // Verify zero compiler warnings on FS882StratumSummary.svelte
  assert.deepEqual(
    compile(readSrc('FS882StratumSummary.svelte'), { filename: 'FS882StratumSummary.svelte', generate: 'client' }).warnings,
    []
  );
});
