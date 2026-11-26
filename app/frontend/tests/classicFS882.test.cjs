const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { compile } = require('svelte/compiler');
const { render } = require('svelte/server');
const {
  createFS882TestController,
  loadReactiveRuneModule,
  loadTypeScript,
  serverComponent,
  srcPath,
} = require('./svelteTestHelpers.cjs');

const read = (name) => readFileSync(srcPath(name), 'utf8');
const plain = (value) => JSON.parse(JSON.stringify(value));
const lucideStub = new Proxy({}, { get: () => () => '' });

async function flushMicrotasks(ms = 25) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

test('Classic FS882 4-card components compile with zero Svelte warnings and obey theme invariants', () => {
  const legacyGreenHex = /#(173f38|2c5b4a|d7ad51|b7cfc0|365c48|d1dcd4|176149|174f38|268453|e9efeb|e6f0e8|d2e4d7|dbe8dd|eaf0e9|f0f6ee|e4eee9|526e62|456050|20322d|bd9b48|b7493c|0f766e|ccfbf1|065f46|047857|ecfdf5|d1fae5|a7f3d0|6ee7b7|34d399|10b981|059669|064e3b)\b/i;
  const legacyGreenUtil = /\b(?:bg|text|border|ring|outline)-(?:emerald|teal|green)-\d{2,3}\b/i;
  const emojiRe = /\p{Extended_Pictographic}/u;

  const files = [
    'FS882Form.svelte',
    'FS882Toolbar.svelte',
    'FS882WorkspaceBody.svelte',
    'FS882AccessRecordBar.svelte',
    'FS882CardSite.svelte',
    'FS882CardSoil.svelte',
    'FS882CardVeg.svelte',
    'FS882CardMensuration.svelte',
  ];

  for (const file of files) {
    const src = read(file);
    assert.equal(legacyGreenHex.test(src), false, `${file} must not contain legacy green hex`);
    assert.equal(legacyGreenUtil.test(src), false, `${file} must not contain emerald/teal/green utility class`);
    assert.equal(emojiRe.test(src), false, `${file} must not contain raw emoji`);
    const clientRes = compile(src, { filename: srcPath(file), generate: 'client' });
    assert.deepEqual(clientRes.warnings, [], `${file} emitted client Svelte warnings`);
    const serverRes = compile(src, { filename: srcPath(file), generate: 'server' });
    assert.deepEqual(serverRes.warnings, [], `${file} emitted server Svelte warnings`);
  }
});

test('mensurationDraft.ts validates TreePlotRecord and TreeRowRecord bounds and computes sequential IDs', () => {
  const m = loadTypeScript('entry/mensurationDraft.ts');

  const header = m.newEmptyTreePlotRecord('00337', {
    zone: 'CWH',
    subZone: 'vm1',
    siteSeries: '01',
    surveyor: 'A. Botanist',
    date: '2026-08-12',
    becSiteUnit: 'CWHvm1/01',
  });
  assert.equal(header.plotNumber, '00337');
  assert.equal(header.subPlot, 'A');
  assert.equal(header.measurementId, 1);
  assert.equal(header.zone, 'CWH');
  assert.deepEqual(plain(m.validateTreePlotDraft(header)), []);

  assert.equal(m.nextMeasurementId([header], 'A'), 2);
  assert.equal(m.nextMeasurementId([header], 'B'), 1);

  // Invalid TreePlot bounds
  const badPlot = { ...header, plotNumber: '12345678', subPlot: '', fiz: 'ABC' };
  const badPlotErrors = m.validateTreePlotDraft(badPlot);
  assert.ok(badPlotErrors.some((e) => /PlotNumber.*7/.test(e)));
  assert.ok(badPlotErrors.some((e) => /SubPlot is required/.test(e)));
  assert.ok(badPlotErrors.some((e) => /FIZ.*2/.test(e)));

  // Tree rows & sequential TreeNum
  const t1 = m.newEmptyTreeRowRecord('00337', 'A', 1, 1);
  t1.treeSpp = 'Fd';
  t1.dbh = 42.5;
  t1.totalHtCalc = 31.2;
  t1.conks = 1;
  t1.wildLifeUse = 'CAV';
  assert.deepEqual(plain(m.validateTreeRowDraft(t1)), []);
  assert.equal(m.nextTreeNumber([t1], 'A', 1), 2);
  assert.equal(m.formatPathologySummary(t1), 'Ck:1 WL:CAV');

  const emptyTree = m.newEmptyTreeRowRecord('00337', 'A', 1, 2);
  assert.equal(m.formatPathologySummary(emptyTree), 'None');

  // Byte out-of-range and text length enforcement
  const badTree = { ...t1, treeSpp: 'LONG', treeOrigin: 'AB', crownClass: 'XX', treeHealth: 300, conks: -1 };
  const badTreeErrors = m.validateTreeRowDraft(badTree);
  assert.ok(badTreeErrors.some((e) => /TreeSpp.*3/.test(e)));
  assert.ok(badTreeErrors.some((e) => /TreeOrigin.*1/.test(e)));
  assert.ok(badTreeErrors.some((e) => /CrownClass.*1/.test(e)));
  assert.ok(badTreeErrors.some((e) => /treeHealth.*0 to 255/.test(e)));
  assert.ok(badTreeErrors.some((e) => /conks.*0 to 255/.test(e)));
});

test('classicFS882Helpers enforces LMH25 horizon ordering, 4 layout modes, substrate sum, and record jump parsing', () => {
  const h = loadTypeScript('entry/classicFS882Helpers.ts');

  // Upland L/F/H measured upward (UpperDepth DESC) + Wetland Of/Om/Oh measured downward (UpperDepth ASC)
  const humusSorted = h.sortHumusHorizonsLMH25([
    { id: 1, plotNumber: '00337', horizon: 'H', upperDepth: 2, lowerDepth: 0 },
    { id: 2, plotNumber: '00337', horizon: 'L', upperDepth: 10, lowerDepth: 7 },
    { id: 3, plotNumber: '00337', horizon: 'F', upperDepth: 7, lowerDepth: 2 },
    { id: 4, plotNumber: '00337', horizon: 'Om', upperDepth: 20, lowerDepth: 55 },
    { id: 5, plotNumber: '00337', horizon: 'Of', upperDepth: 0, lowerDepth: 20 },
    { id: 6, plotNumber: '00337', horizon: 'X', upperDepth: null, lowerDepth: null },
  ]);
  assert.deepEqual(
    humusSorted.map((r) => r.horizon),
    ['L', 'F', 'H', 'Of', 'Om', 'X']
  );

  // Mineral horizons measured downward (UpperDepth ASC)
  const mineralSorted = h.sortMineralHorizonsLMH25([
    { id: 1, plotNumber: '00337', horizon: 'C', upperDepth: 55, lowerDepth: 90 },
    { id: 2, plotNumber: '00337', horizon: 'Ah', upperDepth: 0, lowerDepth: 12 },
    { id: 3, plotNumber: '00337', horizon: 'Bf', upperDepth: 12, lowerDepth: 55 },
    { id: 4, plotNumber: '00337', horizon: 'R', upperDepth: null, lowerDepth: null },
  ]);
  assert.deepEqual(
    mineralSorted.map((r) => r.horizon),
    ['Ah', 'Bf', 'C', 'R']
  );

  // 4 display modes
  assert.deepEqual([...h.resolveVisibleCards('single', 'soils', 'site', 'veg')], ['soils']);
  assert.deepEqual([...h.resolveVisibleCards('side-by-side', 'site', 'soils', 'veg')], ['soils', 'veg']);
  assert.deepEqual(
    [...h.resolveVisibleCards('top-down', 'site', 'site', 'soils')],
    ['site', 'soils', 'veg', 'mensuration']
  );
  assert.deepEqual(
    [...h.resolveVisibleCards('grid', 'site', 'site', 'soils')],
    ['site', 'soils', 'veg', 'mensuration']
  );

  // Substrate total & record jump parsing
  assert.equal(h.computeSubstrateTotal({ substrateOrganicMatter: 65, substrateDecWood: 25, substrateRocks: 10 }), 100);
  assert.equal(h.computeSubstrateTotal({}), null);
  assert.deepEqual(plain(h.formatRecordJumpInput('1,250', 5000)), { index: 1250, error: null });
  assert.ok(h.formatRecordJumpInput('0', 5000).error);
  assert.ok(h.formatRecordJumpInput('5001', 5000).error);
  assert.ok(h.formatRecordJumpInput('abc', 5000).error);
});

test('FS882AccessRecordBar SSR renders classic navigation controls, leading-zero search, lock gating, and 4 layout modes', () => {
  const helpers = loadTypeScript('entry/classicFS882Helpers.ts');
  const Bar = serverComponent(read('FS882AccessRecordBar.svelte'), 'FS882AccessRecordBar.svelte', {
    '@lucide/svelte': lucideStub,
    '../web/runtimeMode': { IS_WEB_READONLY: false },
    './classicFS882Helpers': helpers,
  });

  const unlockedHtml = render(Bar, {
    props: {
      currentIndex: 100,
      totalCount: 5000,
      locked: false,
      layoutMode: 'side-by-side',
      leftCard: 'site',
      rightCard: 'soils',
      onFirst() {},
      onPrev() {},
      onNext() {},
      onLast() {},
      onJumpToRecord() {},
      onNewPlot() {},
      onSearchPlot() {},
    },
  }).body;

  assert.match(unlockedHtml, /data-record-nav="first"/);
  assert.match(unlockedHtml, /data-record-nav="prev"/);
  assert.match(unlockedHtml, /data-record-index-input/);
  assert.match(unlockedHtml, /of 5,000/);
  assert.match(unlockedHtml, /data-record-nav="next"/);
  assert.match(unlockedHtml, /data-record-nav="last"/);
  assert.match(unlockedHtml, /data-record-nav="new"/);
  assert.match(unlockedHtml, /data-record-search-input[^>]*type="text"|type="text"[^>]*data-record-search-input/);
  assert.match(unlockedHtml, /data-layout-mode="single"/);
  assert.match(unlockedHtml, /data-layout-mode="side-by-side"/);
  assert.match(unlockedHtml, /data-layout-mode="top-down"/);
  assert.match(unlockedHtml, /data-layout-mode="grid"/);
  assert.match(unlockedHtml, /data-side-by-side-pickers/);

  const lockedHtml = render(Bar, {
    props: {
      currentIndex: 1,
      totalCount: 10,
      locked: true,
      layoutMode: 'grid',
      onFirst() {},
      onPrev() {},
      onNext() {},
      onLast() {},
      onJumpToRecord() {},
      onNewPlot() {},
      onSearchPlot() {},
    },
  }).body;
  assert.match(lockedHtml, /data-record-nav="new"[^>]*disabled/);
});

test('FS882CardMensuration SSR shows Initialize button when unlocked and read-only notice when locked', () => {
  const mDraft = loadTypeScript('entry/mensurationDraft.ts');
  const Card4 = serverComponent(read('FS882CardMensuration.svelte'), 'FS882CardMensuration.svelte', {
    '@lucide/svelte': lucideStub,
    '../../bindings/github.com/boostao/vpro/app': { PlotEntryService: {} },
    '../shared/readRequests': { formatError: (e) => String(e) },
    '../shell/notificationService.svelte': { notifications: { success() {}, error() {} } },
    '../web/runtimeMode': { IS_WEB_READONLY: false },
    './mensurationDraft': mDraft,
  });

  const unlockedNoTables = render(Card4, {
    props: { contextId: 'ctx-1', plotNumber: '00337', locked: false },
  }).body;
  assert.match(unlockedNoTables, /CARD 4 — MENSURATION \(FS882\)/);
  assert.match(unlockedNoTables, /data-mensuration-init-btn/);
  assert.match(unlockedNoTables, /Initialize Mensuration Tables/);

  const lockedNoTables = render(Card4, {
    props: { contextId: 'ctx-1', plotNumber: '00337', locked: true },
  }).body;
  assert.match(lockedNoTables, /data-mensuration-no-tables/);
  assert.match(lockedNoTables, /No mensuration tables in this project/);
  assert.doesNotMatch(lockedNoTables, /data-mensuration-init-btn/);
});

test('Default data edit lock queries ContextService.GetEditLockStatus, blocks edits when locked, reacts to vpro:auth-changed, and dispatches vpro:open-signin', async () => {
  const lockCalls = [];
  const updateCalls = [];
  const listeners = new Map();
  const dispatched = [];

  const mockWindow = {
    addEventListener(type, fn) {
      if (!listeners.has(type)) listeners.set(type, new Set());
      listeners.get(type).add(fn);
    },
    removeEventListener(type, fn) {
      listeners.get(type)?.delete(fn);
    },
    dispatchEvent(evt) {
      dispatched.push(evt.type);
      for (const fn of listeners.get(evt.type) ?? []) fn(evt);
      return true;
    },
  };
  const MockCustomEvent = class {
    constructor(type, init = {}) {
      this.type = type;
      this.detail = init.detail;
    }
  };

  let lockResponse = {
    locked: true,
    reason: 'Sign in with your BC Government IDIR or BCeID account to unlock data editing.',
    signedIn: false,
    userId: '',
    displayName: '',
    role: '',
    identityProvider: '',
    canEditCurrentProject: false,
    isBecMasterProject: false,
    oidcConfigured: true,
    devFallbackAvailable: false,
  };

  const prevWindow = globalThis.window;
  const prevCustomEvent = globalThis.CustomEvent;
  globalThis.window = mockWindow;
  globalThis.CustomEvent = MockCustomEvent;

  const runtime = require('svelte/internal/client');
  const mod = loadReactiveRuneModule(
    'entry/fs882FormController.svelte.ts',
    {
      './paperLayout': {
        paperPage: () => ({ sections: [], controls: [] }),
        paperChild: () => ({ sections: [], controls: [] }),
        accessCaption: (s) => s ?? '',
      },
      './twoPageEntrySession': {
        TwoPageEntrySession: class {},
        twoPageEntryForms: ['FS882-8x6XL', 'FS882-8x6XL-CHARS'],
      },
      '../../bindings/github.com/boostao/vpro/app': {
        ContextService: {
          GetEditLockStatus: async (ctxId) => {
            lockCalls.push(ctxId);
            return structuredClone(lockResponse);
          },
          GetPlotBundle: async () => ({
            header: { plotNumber: '00337', generalLocation: 'Coast', locked: false },
            headerCapabilities: { plotNumber: true, generalLocation: true, locked: true },
            canEditMasterBEC: false,
            childCapabilities: { Veg: {}, Humus: {}, Mineral: {}, Other: {} },
            vegetation: { available: true, reason: '', records: [] },
            humus: [],
            mineral: [],
            other: [],
          }),
          UpdatePlot: async (_ctx, header) => {
            updateCalls.push(header);
          },
        },
        PlotEntryService: {
          GetListItems: async () => [],
        },
      },
    },
    {
      window: mockWindow,
      CustomEvent: MockCustomEvent,
    }
  );

  let ctrl;
  const projectStateBox = runtime.state({
    contextId: 'ctx-lock-1',
    activeProject: 'Sample',
    projectPath: 'Sample.db',
    activeSU: 'None',
    suPath: '',
  });
  const dispose = runtime.effect_root(() => {
    ctrl = mod.createFS882Controller({
      contextId: 'ctx-lock-1',
      getEntryForm: () => 'fs882',
      getPlotNumber: () => '00337',
      getNeighborPlots: () => [],
      getProjectState: () => runtime.get(projectStateBox),
      setSuccess: () => {},
    });
  });

  try {
    runtime.flush();
    await flushMicrotasks();
    runtime.flush();

    assert.ok(lockCalls.includes('ctx-lock-1'), 'must query GetEditLockStatus on mount');
    assert.equal(ctrl.authEditLocked, true);
    assert.equal(ctrl.headerInputsDisabled, true);
    assert.equal(ctrl.arcticInputsDisabled, true);
    assert.equal(ctrl.childParentDisabled, true);

    // Attempting to save or toggleLock while auth-locked must be blocked
    ctrl.draft.generalLocation = 'Attempted Edit';
    ctrl.markDirty();
    await ctrl.save();
    assert.equal(updateCalls.length, 0);
    assert.match(ctrl.error ?? '', /Sign in/i);

    await ctrl.toggleLock();
    assert.equal(ctrl.draft.locked, false, 'toggleLock must not mutate plot lock while auth-locked');

    // Request Sign In dispatches vpro:open-signin
    ctrl.requestSignIn();
    assert.ok(dispatched.includes('vpro:open-signin'));

    // Simulate signing in -> vpro:auth-changed re-queries GetEditLockStatus and unlocks
    lockResponse = {
      ...lockResponse,
      locked: false,
      reason: '',
      signedIn: true,
      userId: 'idir-jdoe',
      displayName: 'Jane Doe',
      role: 'contributor',
      canEditCurrentProject: true,
    };
    mockWindow.dispatchEvent(new MockCustomEvent('vpro:auth-changed'));
    await flushMicrotasks();
    runtime.flush();

    assert.equal(ctrl.authEditLocked, false);
    assert.equal(ctrl.headerInputsDisabled, false);

    // Simulate switching to BECMaster as contributor -> locked again!
    lockResponse = {
      ...lockResponse,
      locked: true,
      isBecMasterProject: true,
      canEditCurrentProject: false,
      reason: 'BECMaster is read-only for your role.',
    };
    mockWindow.dispatchEvent(new MockCustomEvent('vpro:auth-changed'));
    await flushMicrotasks();
    runtime.flush();

    assert.equal(ctrl.authEditLocked, true);
    assert.equal(ctrl.headerInputsDisabled, true);
  } finally {
    dispose();
    if (prevWindow === undefined) delete globalThis.window;
    else globalThis.window = prevWindow;
    if (prevCustomEvent === undefined) delete globalThis.CustomEvent;
    else globalThis.CustomEvent = prevCustomEvent;
  }
});

test('FS882Form preserves FS882EditorHandle exports and FieldCardPreviewModal / buildFieldCardViewModel exports remain intact', () => {
  const formSrc = read('FS882Form.svelte');
  for (const fn of [
    'export function getCloseState',
    'export function saveForClose',
    'export function canOpenProjectMetadata',
    'export function openProjectMetadata',
    'export function canOpenMetadataInPlace',
    'export function applyDiagnosticHumusThickness',
    'export function applyDiagnosticSMR',
    'export function applyDiagnosticSNR',
  ]) {
    assert.ok(formSrc.includes(fn), `FS882Form.svelte must preserve ${fn}`);
  }
  assert.match(formSrc, /data-edit-lock-banner/);
  assert.match(formSrc, /data-open-signin-btn/);
  assert.match(formSrc, /<FS882AccessRecordBar/);

  const previewMod = loadTypeScript('entry/fieldCardPreview.ts');
  assert.equal(typeof previewMod.buildFieldCardViewModel, 'function');
  assert.equal(
    compile(read('FieldCardPreviewModal.svelte'), { filename: srcPath('FieldCardPreviewModal.svelte'), generate: 'client' }).warnings.length,
    0
  );
});

test('FS882CardMensuration avoids DataCloneError on Svelte 5 $state proxies and wires dirty/busy guards through FS882Controller, FS882WorkspaceBody, and ShellEntryHost', async () => {
  const mensSrc = read('FS882CardMensuration.svelte');
  const bodySrc = read('FS882WorkspaceBody.svelte');
  const formSrc = read('FS882Form.svelte');
  const hostSrc = readFileSync(srcPath('shell/ShellEntryHost.svelte'), 'utf8');

  // 1. P1 #4: $state.raw for data + $state.snapshot before every structuredClone
  assert.match(mensSrc, /let data = \$state\.raw<PlotMensurationData \| null>\(null\)/);
  const bareCloneMatches = mensSrc.match(/structuredClone\((?!\$state\.snapshot\()/g);
  assert.equal(bareCloneMatches, null, 'FS882CardMensuration must wrap $state.snapshot(...) before every structuredClone');

  // Exercise hydrateFromPayload and selectHeaderByKey against non-cloneable Proxy objects
  const mDraft = loadTypeScript('entry/mensurationDraft.ts');
  const { componentFunctions } = require('./svelteTestHelpers.cjs');
  const unwrapTag = Symbol('unwrap');
  const wrapProxy = (obj) =>
    new Proxy(obj, {
      get(target, prop, receiver) {
        if (prop === unwrapTag) return target;
        return Reflect.get(target, prop, receiver);
      },
    });
  const headerA = wrapProxy({ plotNumber: '00337', subPlot: 'A', measurementId: 1, cruisePlot: true, cwdPlot: false, wildlifePlot: false, informalPlot: false, siteIndexPlot: false });
  const headerB = wrapProxy({ plotNumber: '00337', subPlot: 'B', measurementId: 1, cruisePlot: false, cwdPlot: true, wildlifePlot: false, informalPlot: false, siteIndexPlot: false });
  const tree1 = wrapProxy({ rowId: 10, plotNumber: '00337', subPlot: 'A', measurementId: 1, treeNum: 1, treeSpp: 'Fd' });

  const mensCtx = componentFunctions('FS882CardMensuration.svelte', ['hydrateFromPayload', 'selectHeaderByKey'], {
    structuredClone,
    $state: {
      snapshot: (v) => (v && typeof v === 'object' && v[unwrapTag] ? v[unwrapTag] : v),
    },
    plotNumber: '00337',
    headerDraft: null,
    data: null,
    selectedHeaderKey: '',
    headerEdit: null,
    headerDirty: false,
    treeDrafts: [],
    dirtyTreeKeys: {},
    expandedPathology: {},
    errorMsg: null,
    sortedHeaders: [headerA, headerB],
    sortTreePlots: mDraft.sortTreePlots,
    sortTreeRows: mDraft.sortTreeRows,
    treePlotKey: mDraft.treePlotKey,
    newEmptyTreePlotRecord: mDraft.newEmptyTreePlotRecord,
  });

  // Direct structuredClone(headerA) throws DataCloneError in Node; hydrateFromPayload and selectHeaderByKey must succeed
  assert.throws(() => structuredClone(headerA));
  mensCtx.actions.hydrateFromPayload({ plotNumber: '00337', hasTables: true, hasTreePlot: true, hasTrees: true, treePlots: [headerA, headerB], trees: [tree1], readOnly: false });
  assert.equal(mensCtx.headerEdit.subPlot, 'A');
  assert.equal(mensCtx.treeDrafts.length, 1);
  mensCtx.actions.selectHeaderByKey('B::1');
  assert.equal(mensCtx.headerEdit.subPlot, 'B');

  // 2. P1 #5: ShellEntryHost wires onSelectPlot and onNewPlot into FS882Form updating editorPlotNumber & selected via requestTransition
  assert.match(hostSrc, /<FS882Form[\s\S]*onSelectPlot=\{\(p\)\s*=>/);
  assert.match(hostSrc, /<FS882Form[\s\S]*onNewPlot=\{\(\)\s*=>/);
  assert.match(hostSrc, /onSelectPlot=\{\(p\)\s*=>[\s\S]*requestTransition[\s\S]*editorPlotNumber = p/);
  assert.match(hostSrc, /onNewPlot=\{\(\)\s*=>[\s\S]*requestTransition[\s\S]*editorPlotNumber = undefined/);

  // 3. P1 #6: FS882CardMensuration exposes onDirtyChange/onBusyChange, FS882WorkspaceBody wires them to ctrl,
  //    FS882Form blocks tab/layout switch when Card 4 is dirty, and controller propagates mensurationDirty/Busy to effectiveFormDirty/busy/getCloseState
  assert.match(mensSrc, /onDirtyChange\?:\s*\(dirty:\s*boolean\)\s*=>\s*void/);
  assert.match(mensSrc, /onBusyChange\?:\s*\(busy:\s*boolean\)\s*=>\s*void/);
  assert.match(bodySrc, /onDirtyChange=\{\(dirty\)\s*=>\s*\{\s*ctrl\.mensurationDirty = dirty;\s*\}\}/);
  assert.match(bodySrc, /onBusyChange=\{\(busy\)\s*=>\s*\{\s*ctrl\.mensurationBusy = busy;\s*\}\}/);
  assert.match(formSrc, /guardMensurationUnmount/);

  const runtime = require('svelte/internal/client');
  const busyEvents = [];
  const mod = loadReactiveRuneModule('entry/fs882FormController.svelte.ts', {
    './paperLayout': {
      paperPage: () => ({ sections: [], controls: [] }),
      paperChild: () => ({ sections: [], controls: [] }),
      accessCaption: (s) => s ?? '',
    },
    './twoPageEntrySession': {
      TwoPageEntrySession: class {},
      twoPageEntryForms: ['FS882-8x6XL', 'FS882-8x6XL-CHARS'],
    },
    '../../bindings/github.com/boostao/vpro/app': {
      ContextService: {
        GetEditLockStatus: async () => ({
          locked: false,
          reason: '',
          signedIn: true,
          userId: 'u1',
          displayName: 'User',
          role: 'contributor',
          identityProvider: 'dev',
          canEditCurrentProject: true,
          isBecMasterProject: false,
          oidcConfigured: false,
          devFallbackAvailable: true,
        }),
        GetPlotBundle: async () => ({
          header: { plotNumber: '00337', generalLocation: 'Coast', locked: false },
          headerCapabilities: { plotNumber: true, generalLocation: true, locked: true },
          canEditMasterBEC: false,
          childCapabilities: { Veg: {}, Humus: {}, Mineral: {}, Other: {} },
          vegetation: { available: true, reason: '', records: [] },
          humus: [],
          mineral: [],
          other: [],
        }),
      },
      PlotEntryService: { GetListItems: async () => [] },
    },
  });

  let ctrl;
  const projectStateBox = runtime.state({
    contextId: 'ctx-mens-1',
    activeProject: 'Sample',
    projectPath: 'Sample.db',
    activeSU: 'None',
    suPath: '',
  });
  const dispose = runtime.effect_root(() => {
    ctrl = mod.createFS882Controller({
      contextId: 'ctx-mens-1',
      getEntryForm: () => 'fs882',
      getPlotNumber: () => '00337',
      getNeighborPlots: () => [],
      getProjectState: () => runtime.get(projectStateBox),
      setSuccess: () => {},
      onBusyChange: (b) => busyEvents.push(b),
    });
  });

  try {
    runtime.flush();
    await flushMicrotasks();
    runtime.flush();

    assert.equal(ctrl.effectiveFormDirty, false);
    assert.equal(ctrl.getCloseState().unsaved, false);
    assert.equal(ctrl.busy, false);

    // Unsaved Card 4 edit marks effectiveFormDirty & getCloseState().unsaved, disables auto-save-on-close, and blocks toggleLock
    ctrl.mensurationDirty = true;
    runtime.flush();
    assert.equal(ctrl.effectiveFormDirty, true);
    const dirtyClose = ctrl.getCloseState();
    assert.equal(dirtyClose.unsaved, true);
    assert.equal(dirtyClose.canSave, false);
    assert.match(dirtyClose.saveReason, /mensuration/i);

    await ctrl.toggleLock();
    assert.equal(ctrl.draft.locked, false, 'toggleLock must be blocked while Card 4 mensuration is dirty');
    assert.match(ctrl.error ?? '', /mensuration/i);

    // Card 4 saving/loading marks ctrl.busy, headerWorkflowBusy, tabWorkflowBusy, getCloseState().busy, and onBusyChange(true)
    ctrl.mensurationBusy = true;
    runtime.flush();
    assert.equal(ctrl.busy, true);
    assert.equal(ctrl.headerWorkflowBusy, true);
    assert.equal(ctrl.tabWorkflowBusy, true);
    assert.equal(ctrl.getCloseState().busy, true);
    assert.equal(busyEvents.at(-1), true);

    // Clearing both restores clean/idle state
    ctrl.mensurationDirty = false;
    ctrl.mensurationBusy = false;
    runtime.flush();
    assert.equal(ctrl.effectiveFormDirty, false);
    assert.equal(ctrl.busy, false);
    assert.equal(ctrl.getCloseState().unsaved, false);
    assert.equal(ctrl.getCloseState().busy, false);
  } finally {
    dispose();
  }
});
