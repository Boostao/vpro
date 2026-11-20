const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const ts = require('typescript');
const { compile } = require('svelte/compiler');
const {
  createFS882TestController,
  loadTypeScript,
  noopNotificationsStub,
  srcPath,
} = require('./svelteTestHelpers.cjs');

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
}

function makeHeader(plotNumber, overrides = {}) {
  return {
    plotNumber,
    fieldNo: `F-${plotNumber}`,
    projectId: 'PRJ1',
    date: '2026-07-01',
    surveyor: 'Tester',
    generalLocation: `Loc ${plotNumber}`,
    zone: 'CWH',
    subZone: 'vm1',
    siteSeries: '01',
    userSiteUnit: 'SU1',
    becSiteUnit: 'CWHvm1/01',
    locked: false,
    snowCoverRegime: null,
    activeLayerDepth: null,
    ...overrides,
  };
}

function makeBundle(plotNumber, includeCaps = true, overrides = {}) {
  const headerCaps = {
    plotNumber: true,
    generalLocation: true,
    projectId: true,
    userSiteUnit: true,
    moistureRegime: true,
    nutrientRegime: true,
    humusThickness: true,
    locked: true,
  };
  const childCaps = {
    Veg: { species: true, cover1: true, height1: true },
    Humus: { horizon: true, upperDepth: true, lowerDepth: true },
    Mineral: { horizon: true, upperDepth: true, lowerDepth: true },
    Other: { dataName: true, dataItem: true },
  };
  return {
    header: makeHeader(plotNumber, overrides.header),
    ...(includeCaps ? { headerCapabilities: headerCaps, childCapabilities: childCaps } : {}),
    canEditMasterBEC: true,
    vegetation: {
      available: true,
      reason: '',
      records: overrides.veg ?? [{ id: Number(plotNumber) || 1, plotNumber, species: 'TSUGHET', layer: 'A', cover1: 40 }],
    },
    humus: overrides.humus ?? [{ id: 10, plotNumber, horizon: 'L', upperDepth: 5, lowerDepth: 3 }],
    mineral: overrides.mineral ?? [{ id: 20, plotNumber, horizon: 'Ah', upperDepth: 0, lowerDepth: 10 }],
    other: overrides.other ?? [{ id: 30, plotNumber, dataName: `Tag-${plotNumber}`, dataItem: 'Val' }],
  };
}

function makeControllerHarness(options = {}) {
  const calls = {
    getPlotBundle: [],
    getPlot: [],
    listAudit: [],
    listSpecies: [],
    listSoilSuggestions: 0,
    listAttributeSuggestions: 0,
    listItems: [],
    updatePlot: [],
  };
  const bundles = options.bundles ?? {
    '001': makeBundle('001', true),
    '002': makeBundle('002', true),
    '003': makeBundle('003', true),
  };
  const evalCache = new Map();
  const entryCache = loadTypeScript('entry/entryReferenceCache.ts', {}, {}, evalCache);
  entryCache.resetEntryReferenceCachesForTest();

  const ContextService = {
    GetPlotBundle: async (contextId, plot, includeCaps) => {
      calls.getPlotBundle.push([contextId, plot, includeCaps]);
      if (options.onGetPlotBundle) return options.onGetPlotBundle(contextId, plot, includeCaps);
      const raw = bundles[plot];
      if (!raw) throw new Error(`plot "${plot}" not found`);
      const clone = structuredClone(raw);
      if (!includeCaps) {
        delete clone.headerCapabilities;
        delete clone.childCapabilities;
      }
      return clone;
    },
    GetPlot: async (contextId, plot) => {
      calls.getPlot.push([contextId, plot]);
      return structuredClone(bundles[plot]?.header ?? null);
    },
    GetHeaderCapabilities: async () => ({ plotNumber: true, generalLocation: true, locked: true }),
    CanEditMasterBEC: async () => true,
    GetChildCapabilities: async () => ({ species: true, horizon: true }),
    GetVegetationReadAvailability: async (_ctx, plot) => structuredClone(bundles[plot]?.vegetation ?? { available: true, reason: '', records: [] }),
    ListVegRecords: async (_ctx, plot) => structuredClone(bundles[plot]?.vegetation?.records ?? []),
    ListHumusRecords: async (_ctx, plot) => structuredClone(bundles[plot]?.humus ?? []),
    ListMineralRecords: async (_ctx, plot) => structuredClone(bundles[plot]?.mineral ?? []),
    ListOtherRecords: async (_ctx, plot) => structuredClone(bundles[plot]?.other ?? []),
    ListAuditReadEntries: async (_ctx, plot) => {
      calls.listAudit.push(plot);
      return [{ rowId: `audit-${plot}`, plotNumber: plot, table: 'Env', editField: 'Location', before: 'old', after: 'new', user: 'u', editWhen: '2026-07-01' }];
    },
    ListVegetationSpecies: async (_ctx, form) => {
      calls.listSpecies.push(form);
      return [{ code: `SPP_${form}`, scientificName: `Species ${form}`, lifeform: 1 }];
    },
    ListSoilSuggestions: async () => {
      calls.listSoilSuggestions += 1;
      return [{ column: 'Horizon', value: 'Ah' }];
    },
    ListVegetationAttributeSuggestions: async () => {
      calls.listAttributeSuggestions += 1;
      return [{ column: 'Attr', value: 'V1' }];
    },
    GetSIVIProjectIDChoices: async () => ({ Source: 'Env', Choices: { columns: [{ name: 'ProjectID' }], rows: [] } }),
    UpdatePlot: async (_ctx, header) => {
      calls.updatePlot.push(header);
      if (bundles[header.plotNumber]) {
        bundles[header.plotNumber].header = structuredClone(header);
      }
      return header;
    },
  };

  const PlotEntryService = {
    GetListItems: async (name) => {
      calls.listItems.push(name);
      return [{ item: '1', itemDescription: `${name}-1` }];
    },
  };

  const busyTransitions = [];
  const diagnosticsEvents = [];
  const harness = createFS882TestController({
    contextId: options.contextId ?? 'ctx-perf-1',
    plotNumber: options.plotNumber ?? '001',
    neighborPlots: options.neighborPlots ?? [],
    entryForm: options.entryForm ?? 'fs882',
    keepInitialLoadBusy: true,
    onBusyChange: (b) => busyTransitions.push(b),
    onDiagnosticsContextChange: (ctx) => diagnosticsEvents.push(ctx),
    dependencies: {
      './entryReferenceCache': entryCache,
      '../../bindings/github.com/boostao/vpro/app': {
        ContextService,
        PlotEntryService,
        ClassificationService: {},
        ValidationService: {},
        AuditRestoreAction: { AuditRestoreRetain: 'retain', AuditRestorePrune: 'prune', AuditRestoreCancel: 'cancel' },
      },
    },
  });

  return { harness, calls, entryCache, busyTransitions, diagnosticsEvents, bundles };
}

async function flushMicrotasks(ms = 20) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

test('in-place plot switching A -> B -> C has zero cross-plot leakage, preserves activeTab, and does not bump headerRevision', async () => {
  const { harness, calls } = makeControllerHarness({ plotNumber: '001' });
  const { ctrl } = harness;
  try {
    await flushMicrotasks();
    harness.flush();

    assert.equal(ctrl.original?.plotNumber, '001');
    assert.equal(ctrl.draft.generalLocation, 'Loc 001');
    assert.equal(ctrl.headerRevision, 0);
    assert.equal(calls.getPlotBundle.length, 1);
    assert.equal(calls.getPlotBundle[0][2], true, 'initial load requests capabilities');

    // Dirty draft, set validation, open transient modals, switch to Soils tab
    ctrl.draft.generalLocation = 'Dirty A';
    ctrl.markDirty();
    ctrl.validateHeader('elevation', 'Elevation invalid');
    ctrl.error = 'Stale error from Plot 001';
    ctrl.managePlotOpen = true;
    ctrl.fieldCardModalOpen = true;
    ctrl.activeTab = 'soils';
    harness.flush();
    assert.equal(ctrl.dirty, true);

    // Switch to Plot 002
    harness.setPlotNumber('002');
    await flushMicrotasks();
    harness.flush();

    assert.equal(ctrl.original?.plotNumber, '002');
    assert.equal(ctrl.draft.plotNumber, '002');
    assert.equal(ctrl.draft.generalLocation, 'Loc 002');
    assert.equal(ctrl.dirty, false);
    assert.deepEqual(Object.keys(ctrl.headerValidation), []);
    assert.equal(ctrl.error, null);
    assert.equal(ctrl.managePlotOpen, false);
    assert.equal(ctrl.fieldCardModalOpen, false);
    assert.equal(ctrl.activeTab, 'soils', 'activeTab must be preserved across plot switches');
    assert.equal(ctrl.children.otherList[0].dataName, 'Tag-002');
    assert.equal(calls.getPlotBundle.at(-1)[2], false, 'subsequent loads reuse cached capabilities');
    const revAfterInvalidDiscard = ctrl.headerRevision;

    // Clean switch Plot 002 -> Plot 003 must NOT bump headerRevision
    harness.setPlotNumber('003');
    await flushMicrotasks();
    harness.flush();

    assert.equal(ctrl.original?.plotNumber, '003');
    assert.equal(ctrl.draft.generalLocation, 'Loc 003');
    assert.equal(ctrl.activeTab, 'soils');
    assert.equal(ctrl.headerRevision, revAfterInvalidDiscard, 'clean plot switch must not increment headerRevision');

    // Explicit Undo DOES bump headerRevision
    ctrl.draft.generalLocation = 'Temp edit';
    ctrl.markDirty();
    ctrl.undo();
    harness.flush();
    assert.equal(ctrl.headerRevision, revAfterInvalidDiscard + 1, 'undo() must increment headerRevision');
    assert.equal(ctrl.draft.generalLocation, 'Loc 003');
  } finally {
    harness.dispose();
  }
});

test('synchronous neighbor prefetch hit switches plots with 0 additional RPCs and 0 busy=true transitions, and save invalidates cache', async () => {
  const { harness, calls, busyTransitions } = makeControllerHarness({
    plotNumber: '001',
    neighborPlots: ['002'],
  });
  const { ctrl } = harness;
  try {
    await flushMicrotasks(30);
    harness.flush();

    assert.equal(ctrl.original?.plotNumber, '001');
    assert.equal(ctrl.busy, false);
    // Neighbor 002 was prefetched in background
    assert.ok(
      calls.getPlotBundle.some(([, plot, includeCaps]) => plot === '002' && includeCaps === false),
      'neighbor plot 002 must be prefetched in background without capabilities'
    );

    const bundleCallsBeforeSwitch = calls.getPlotBundle.length;
    busyTransitions.length = 0;

    // Switch to prefetched Plot 002 (updating neighborPlots to ['003', '001'])
    harness.setNeighborPlots(['003', '001']);
    harness.setPlotNumber('002');

    // Synchronous hit: state swapped immediately without awaiting IPC, and zero busy=true
    assert.equal(ctrl.original?.plotNumber, '002');
    assert.equal(ctrl.draft.generalLocation, 'Loc 002');
    assert.equal(ctrl.busy, false);
    assert.equal(busyTransitions.includes(true), false, 'sync prefetch hit must never flip busy=true');
    assert.equal(calls.getPlotBundle.length, bundleCallsBeforeSwitch, 'sync prefetch hit must execute 0 immediate RPCs');

    // Mutating Plot 002 via save() invalidates Plot 002 in bundle cache
    ctrl.draft.generalLocation = 'Updated 002';
    ctrl.markDirty();
    await ctrl.save();
    harness.flush();
    assert.equal(calls.updatePlot.length, 1);

    // Reloading Plot 002 now misses cache and hits GetPlotBundle fresh
    const callsBeforeReload = calls.getPlotBundle.length;
    await ctrl.load('002');
    harness.flush();
    assert.equal(calls.getPlotBundle.length, callsBeforeReload + 1);
    assert.equal(ctrl.draft.generalLocation, 'Updated 002');
  } finally {
    harness.dispose();
  }
});

test('rapid A -> B -> C plot switches ignore late Plot B response and settle cleanly on Plot C', async () => {
  const gateB = deferred();
  const gateC = deferred();
  const { harness } = makeControllerHarness({
    plotNumber: '001',
    onGetPlotBundle: (_ctx, plot, includeCaps) => {
      if (plot === '001') return Promise.resolve(makeBundle('001', includeCaps));
      if (plot === '002') return gateB.promise;
      if (plot === '003') return gateC.promise;
      return Promise.reject(new Error(`unexpected plot ${plot}`));
    },
  });
  const { ctrl } = harness;
  try {
    await flushMicrotasks();
    harness.flush();
    assert.equal(ctrl.original?.plotNumber, '001');

    // Rapidly request 002 then 003 before 002 resolves
    harness.setPlotNumber('002');
    harness.setPlotNumber('003');

    // Resolve 003 first, then resolve stale 002 late
    gateC.resolve(makeBundle('003', false));
    await flushMicrotasks();
    harness.flush();
    assert.equal(ctrl.original?.plotNumber, '003');

    gateB.resolve(makeBundle('002', false));
    await flushMicrotasks();
    harness.flush();

    // Must remain on Plot 003 with zero overwrite from late Plot 002
    assert.equal(ctrl.original?.plotNumber, '003');
    assert.equal(ctrl.draft.plotNumber, '003');
    assert.equal(ctrl.draft.generalLocation, 'Loc 003');
    assert.equal(ctrl.children.otherList[0].dataName, 'Tag-003');
    assert.equal(ctrl.busy, false);
  } finally {
    harness.dispose();
  }
});

test('Audit Trail is lazy-loaded only when activeTab === audit and species lists deduplicate 6 forms to 3 canonical RPCs', async () => {
  const { harness, calls } = makeControllerHarness({ plotNumber: '001' });
  const { ctrl } = harness;
  try {
    await flushMicrotasks();
    harness.flush();

    // On Site tab: zero Audit, zero Species, zero Soil suggestions, zero Attribute suggestions
    assert.deepEqual(calls.listAudit, []);
    assert.deepEqual(calls.listSpecies, []);
    assert.equal(calls.listSoilSuggestions, 0);
    assert.equal(calls.listAttributeSuggestions, 0);

    // Step to Plot 002 on Site tab -> still zero Audit & zero Species
    harness.setPlotNumber('002');
    await flushMicrotasks();
    harness.flush();
    assert.deepEqual(calls.listAudit, []);
    assert.deepEqual(calls.listSpecies, []);

    // Visit Veg tab -> triggers 3 canonical species RPCs populating all 6 form keys
    ctrl.activeTab = 'veg';
    harness.flush();
    await flushMicrotasks();
    harness.flush();

    assert.deepEqual(calls.listSpecies, ['SubVegAXL_BC', 'SubVegCXL', 'SubVegDXL']);
    assert.equal(ctrl.children.speciesReferenceReady, true);
    for (const formName of ['SubVegAXL_BC', 'SubVegAXL', 'SubVegAhtXL', 'SubVegCXL', 'SubVegChtXL', 'SubVegDXL']) {
      assert.ok(Array.isArray(ctrl.children.speciesLists[formName]), `expected species list for ${formName}`);
      assert.equal(Object.isFrozen(ctrl.children.speciesLists[formName]), true);
    }
    assert.equal(ctrl.children.speciesLists.SubVegAXL_BC, ctrl.children.speciesLists.SubVegAXL);
    assert.equal(ctrl.children.speciesLists.SubVegAXL_BC, ctrl.children.speciesLists.SubVegAhtXL);
    assert.equal(ctrl.children.speciesLists.SubVegCXL, ctrl.children.speciesLists.SubVegChtXL);
    assert.equal(calls.listAttributeSuggestions, 1);

    // Step to Plot 003 while on Veg tab -> 0 extra species RPCs, still 0 Audit RPCs
    harness.setPlotNumber('003');
    await flushMicrotasks();
    harness.flush();
    assert.equal(calls.listSpecies.length, 3);
    assert.deepEqual(calls.listAudit, []);

    // Visit Soils tab -> 1 soil suggestions RPC, still 0 Audit RPCs
    ctrl.activeTab = 'soils';
    harness.flush();
    await flushMicrotasks();
    harness.flush();
    assert.equal(calls.listSoilSuggestions, 1);
    assert.deepEqual(calls.listAudit, []);

    // Visit Audit tab on Plot 003 -> triggers Audit load for 003
    ctrl.activeTab = 'audit';
    harness.flush();
    await flushMicrotasks();
    harness.flush();
    assert.deepEqual(calls.listAudit, ['003']);
    assert.equal(ctrl.children.auditList.length, 1);
    assert.equal(ctrl.children.auditList[0].rowId, 'audit-003');

    // Step to Plot 002 while on Audit tab -> triggers Audit load for 002
    harness.setPlotNumber('002');
    await flushMicrotasks();
    harness.flush();
    assert.deepEqual(calls.listAudit, ['003', '002']);
    assert.equal(ctrl.children.auditList[0].rowId, 'audit-002');
  } finally {
    harness.dispose();
  }
});

test('LMH25DiagnosticsBar with waitForDraft=true fires once per matching draft and never falls back to stored evaluation; waitForDraft=false preserves fallback', async () => {
  const client = await import('svelte/internal/client');
  const diagMod = loadTypeScript('diagnostics/lmh25Diagnostics.ts');
  const source = readFileSync(srcPath('diagnostics/LMH25DiagnosticsBar.svelte'), 'utf8');
  const script = source.match(/<script lang="ts">([\s\S]*?)<\/script>/)[1];
  const compiled = compile(`<script lang="ts">${script}</script>`, { generate: 'client' });
  assert.deepEqual(compiled.warnings, []);

  const destroyFns = [];
  const mod = { exports: {} };
  vm.runInNewContext(
    ts.transpileModule(compiled.js.code, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    }).outputText,
    {
      module: mod,
      exports: mod.exports,
      structuredClone,
      setTimeout,
      clearTimeout,
      queueMicrotask,
      require(name) {
        if (name === 'svelte') {
          return {
            onDestroy: (fn) => destroyFns.push(fn),
            untrack: client.untrack,
          };
        }
        if (name === 'svelte/internal/client') return client;
        if (name.startsWith('svelte/')) return require(name);
        if (name.endsWith('/readRequests')) return { formatError: (e) => String(e) };
        if (name.endsWith('/notificationService.svelte')) return noopNotificationsStub;
        if (name.endsWith('/lmh25Diagnostics')) return diagMod;
        throw new Error(`Unexpected LMH25DiagnosticsBar dep ${name}`);
      },
    }
  );

  const wireFor = (plotNumber) => ({
    plotNumber,
    derivedHumusThickness: 5,
    headerHumusThickness: 5,
    humusThicknessDiff: 0,
    substratePopulated: 0,
    substrateSum: null,
    substrateValid: true,
    isOrganicSoilOrder: false,
    keyedSmr: '4',
    keyedSmrClass: 4,
    fieldSmr: '4',
    fieldSmrClass: 4,
    smrDivergence: 0,
    smrDivergent: false,
    smrTrace: [],
    keyedSnr: 'C',
    keyedSnrClass: 2,
    fieldSnr: 'C',
    fieldSnrClass: 2,
    snrDivergence: 0,
    snrDivergent: false,
    snrTrace: [],
    issues: [],
  });

  // Case 1: waitForDraft = true
  const draftCalls = [];
  const storedCalls = [];
  const port = {
    evaluatePlotDiagnostics: async (hdr) => {
      draftCalls.push(hdr.plotNumber);
      return wireFor(hdr.plotNumber);
    },
    evaluateStoredPlotDiagnostics: async (_ctx, plot) => {
      storedCalls.push(plot);
      return wireFor(plot);
    },
  };

  const plotBox = client.state('001');
  const headerBox = client.state(null);
  const dispose1 = client.effect_root(() => {
    mod.exports.default(null, {
      contextId: 'ctx-diag',
      get plotNumber() { return client.get(plotBox); },
      get header() { return client.get(headerBox); },
      humus: [],
      mineral: [],
      waitForDraft: true,
      port,
    });
  });
  client.flush();
  // While header is null, must NOT fall back to evaluateStoredPlotDiagnostics
  await flushMicrotasks(150);
  assert.deepEqual(storedCalls, []);
  assert.deepEqual(draftCalls, []);

  // Deliver matching Plot 001 header -> fires ONCE after 120ms debounce
  client.set(headerBox, { plotNumber: '001', moistureRegime: '4' });
  client.flush();
  await flushMicrotasks(160);
  assert.deepEqual(storedCalls, []);
  assert.deepEqual(draftCalls, ['001']);

  // Switch plotNumber to 002 while header still has 001 (stale), then deliver 002
  client.set(plotBox, '002');
  client.flush();
  await flushMicrotasks(40);
  assert.deepEqual(storedCalls, []);
  assert.deepEqual(draftCalls, ['001'], 'stale previous-plot header must not trigger evaluation for plot 002');

  client.set(headerBox, { plotNumber: '002', moistureRegime: '5' });
  client.flush();
  await flushMicrotasks(160);
  assert.deepEqual(storedCalls, []);
  assert.deepEqual(draftCalls, ['001', '002'], 'exact single draft evaluation for plot 002');

  for (const fn of destroyFns.splice(0)) fn();
  dispose1();

  // Case 2: waitForDraft = false (standalone fallback preserved)
  const dispose2 = client.effect_root(() => {
    mod.exports.default(null, {
      contextId: 'ctx-diag',
      plotNumber: '009',
      header: null,
      humus: [],
      mineral: [],
      waitForDraft: false,
      port,
    });
  });
  client.flush();
  await flushMicrotasks(40);
  assert.deepEqual(storedCalls, ['009'], 'waitForDraft=false must preserve evaluateStoredPlotDiagnostics fallback');
  for (const fn of destroyFns.splice(0)) fn();
  dispose2();
});

test('keyed boundaries, contextId wiring, and PicturePanel ownerKey reset compile warning-free', () => {
  for (const file of [
    'shell/ShellEntryHost.svelte',
    'entry/FS882Form.svelte',
    'entry/FS882WorkspaceBody.svelte',
    'entry/FS882SiteTab.svelte',
    'entry/HeaderEditor.svelte',
    'entry/FS882SoilTab.svelte',
    'entry/FS882SoilHorizonSection.svelte',
    'entry/FS882Modals.svelte',
    'pictures/PicturePanel.svelte',
    'diagnostics/LMH25DiagnosticsBar.svelte',
  ]) {
    const compiled = compile(readFileSync(srcPath(file), 'utf8'), { filename: srcPath(file), generate: 'client' });
    assert.deepEqual(compiled.warnings, [], `${file} emitted Svelte compiler warnings`);
  }

  const modals = readFileSync(srcPath('entry/FS882Modals.svelte'), 'utf8');
  assert.match(modals, /\{#if ctrl\.twoPageOpen && ctrl\.twoPageProject !== null && plotNumber\}/);
  assert.match(modals, /\{#key plotNumber\}[\s\S]*?<TwoPageEntryEditor/);
  assert.match(modals, /<SpeciesCodeCheck[\s\S]*?\{contextId\}/);
  assert.match(modals, /ctrl\.invalidateAfterProjectMetadata\(\)/);

  const entryHost = readFileSync(srcPath('shell/ShellEntryHost.svelte'), 'utf8');
  assert.match(entryHost, /invalidateProjectIdChoices\(/);

  const headerEditor = readFileSync(srcPath('entry/HeaderEditor.svelte'), 'utf8');
  assert.match(headerEditor, /<WorkingUnitFields[\s\S]*?\{contextId\}/);
  assert.match(headerEditor, /\{#key headerRevision\}[\s\S]*?<HeaderGroupGrid/);

  const picturePanel = readFileSync(srcPath('pictures/PicturePanel.svelte'), 'utf8');
  assert.match(picturePanel, /lastOwnerKey && lastOwnerKey !== key[\s\S]*?cancel\(\)/);
});

test('leaving FS882 (onDestroy) evicts context plot bundles, workingUnitChoices, and projectIdChoices so non-FS882 edits are never stale on return', async () => {
  const ctxId = 'ctx-non-fs882-edit';
  const { harness, entryCache } = makeControllerHarness({
    contextId: ctxId,
    plotNumber: '001',
    neighborPlots: ['002'],
  });
  try {
    await flushMicrotasks(30);
    harness.flush();

    // Populate workingUnitChoices and projectIdChoices for this context
    await entryCache.getCachedWorkingUnitChoices(ctxId, 'env', async () => [{ code: 'SU1', description: 'Unit 1' }]);
    await entryCache.getCachedContextValue(ctxId, 'projectIdChoices', async () => ({
      Source: 'Env',
      Choices: { columns: [{ name: 'ProjectID' }], rows: [] },
    }));

    assert.ok(entryCache.peekPlotBundle(ctxId, '001'), 'plot 001 cached while in FS882');
    assert.ok(entryCache.peekPlotBundle(ctxId, '002'), 'neighbor 002 cached while in FS882');
    assert.ok(entryCache.peekWorkingUnitChoices(ctxId, 'env'), 'workingUnitChoices cached while in FS882');
    assert.ok(entryCache.peekContextValue(ctxId, 'projectIdChoices'), 'projectIdChoices cached while in FS882');

    // ProjectMetadataEditor commit invalidates projectIdChoices in-place
    harness.ctrl.invalidateAfterProjectMetadata();
    assert.equal(entryCache.peekContextValue(ctxId, 'projectIdChoices'), undefined);
    await entryCache.getCachedContextValue(ctxId, 'projectIdChoices', async () => ({
      Source: 'Env',
      Choices: { columns: [{ name: 'ProjectID' }], rows: [] },
    }));
    assert.ok(entryCache.peekContextValue(ctxId, 'projectIdChoices'));
  } finally {
    // Unmounting FS882 (e.g. navigating to Datasheet / Project Admin) triggers onDestroy
    harness.dispose();
  }

  assert.equal(entryCache.peekPlotBundle(ctxId, '001'), undefined, 'plot 001 bundle evicted on FS882 destroy');
  assert.equal(entryCache.peekPlotBundle(ctxId, '002'), undefined, 'neighbor 002 bundle evicted on FS882 destroy');
  assert.equal(entryCache.peekWorkingUnitChoices(ctxId, 'env'), undefined, 'workingUnitChoices evicted on FS882 destroy');
  assert.equal(entryCache.peekContextValue(ctxId, 'projectIdChoices'), undefined, 'projectIdChoices evicted on FS882 destroy');
  // Context capabilities remain warm for fast re-entry in same context
  assert.ok(entryCache.getCachedContextCapabilities(ctxId), 'context capabilities remain cached across view switch');
});

test('standalone Two-Page clears twoPageOpen/twoPageProject on plotNumber -> undefined and on load error', async () => {
  const { harness } = makeControllerHarness({
    contextId: 'ctx-twopage-reset',
    entryForm: 'fs882-twopage',
    plotNumber: '001',
  });
  const { ctrl } = harness;
  try {
    await flushMicrotasks();
    harness.flush();
    assert.equal(ctrl.original?.plotNumber, '001');

    // Open two-page review as FS882Form auto-open effect does
    ctrl.openTwoPageReview('entry');
    harness.flush();
    assert.equal(ctrl.twoPageOpen, true);
    assert.equal(ctrl.twoPageProject, 'Sample');

    // Transition 001 -> undefined (plot prompt) must close twoPageOpen & clear twoPageProject
    harness.setPlotNumber(undefined);
    await flushMicrotasks();
    harness.flush();
    assert.equal(ctrl.twoPageOpen, false, 'twoPageOpen must reset when plotNumber becomes undefined');
    assert.equal(ctrl.twoPageProject, null, 'twoPageProject must reset when plotNumber becomes undefined');
    assert.equal(ctrl.draft.plotNumber, '');

    // Transition undefined -> 002 -> reopen two-page -> then transition to missing plot '999' (load error)
    harness.setPlotNumber('002');
    await flushMicrotasks();
    harness.flush();
    assert.equal(ctrl.original?.plotNumber, '002');
    ctrl.openTwoPageReview('entry');
    harness.flush();
    assert.equal(ctrl.twoPageOpen, true);

    harness.setPlotNumber('999');
    await flushMicrotasks();
    harness.flush();
    assert.ok(ctrl.error, 'missing plot 999 must surface load error');
    assert.equal(ctrl.twoPageOpen, false, 'standalone Two-Page load error must close stale twoPageOpen');
    assert.equal(ctrl.twoPageProject, null, 'standalone Two-Page load error must clear stale twoPageProject');
  } finally {
    harness.dispose();
  }
});
