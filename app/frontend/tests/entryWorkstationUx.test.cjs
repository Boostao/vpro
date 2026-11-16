const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const ts = require('typescript');
const { compile } = require('svelte/compiler');
const { render } = require('svelte/server');
const { componentFunctions, serverComponent, srcPath } = require('./svelteTestHelpers.cjs');

const read = name => readFileSync(srcPath(name), 'utf8');

function splitSvelte(source) {
  const scriptMatch = source.match(/<script\b[^>]*>([\s\S]*?)<\/script>/);
  const template = source
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/g, '')
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/g, '');
  return { script: scriptMatch ? scriptMatch[1] : '', template };
}

test('vpro.css defines .vpro-sticky-bar and .vpro-sticky-subbar and all Stage 2A entry components compile cleanly with theme invariants', () => {
  const css = read('vpro.css');
  assert.match(css, /\.vpro-sticky-bar\s*\{[^}]*position:\s*sticky;[^}]*top:\s*0;[^}]*z-index:\s*20;/s);
  assert.match(css, /\.vpro-sticky-bar\s*\{[^}]*backdrop-filter:\s*blur\(4px\)/s);
  assert.match(css, /\.vpro-sticky-subbar\s*\{[^}]*position:\s*sticky;[^}]*top:\s*0;[^}]*z-index:\s*15;/s);
  assert.match(css, /\.vpro-sticky-subbar\s*\{[^}]*backdrop-filter:\s*blur\(4px\)/s);

  const legacyGreenHex = /#(173f38|2c5b4a|d7ad51|b7cfc0|365c48|d1dcd4|176149|174f38|268453|e9efeb|e6f0e8|d2e4d7|dbe8dd|eaf0e9|f0f6ee|e4eee9|526e62|456050|20322d|bd9b48|b7493c|0f766e|ccfbf1|065f46|047857|ecfdf5|d1fae5|a7f3d0|6ee7b7|34d399|10b981|059669|064e3b)\b/i;
  const legacyGreenUtil = /\b(?:bg|text|border|ring|outline)-(?:emerald|teal|green)-\d{2,3}\b/i;
  const emojiRe = /\p{Extended_Pictographic}/u;

  for (const file of [
    'FS882Form.svelte',
    'FS882ChildCreateModal.svelte',
    'TwoPageEntryEditor.svelte',
    'TwoPageSoilPanel.svelte',
    'TwoPageVegetationPanel.svelte',
  ]) {
    const src = read(file);
    assert.equal(legacyGreenHex.test(src), false, `${file} must not contain legacy green hex`);
    assert.equal(legacyGreenUtil.test(src), false, `${file} must not contain emerald/teal/green utility class`);
    assert.equal(emojiRe.test(src), false, `${file} must not contain raw emoji`);
    const compiled = compile(src, { filename: srcPath(file), generate: 'client' });
    assert.equal(compiled.warnings.length, 0, `${file} emitted Svelte warnings: ${JSON.stringify(compiled.warnings)}`);
  }
});

test('sticky toolbars, prop signatures, and parity guards are intact across entry components', () => {
  const twoPage = read('TwoPageEntryEditor.svelte');
  assert.ok(twoPage.includes('projectMetadataClient, metadataRestorationAvailable'), 'TwoPageEntryEditor must preserve $props() substring');
  assert.match(twoPage, /class="[^"]*\bvpro-sticky-bar\b[^"]*"[^>]*data-two-page-sticky-bar[\s\S]*?two-page-entry-header[\s\S]*?Reload Plot/);

  const soil = read('TwoPageSoilPanel.svelte');
  assert.ok(soil.includes('form, parentBlocked }'), 'TwoPageSoilPanel must preserve $props() substring');
  assert.match(soil, /class="[^"]*\bvpro-sticky-subbar\b[^"]*"[^>]*data-soil-sticky-bar[\s\S]*?Save \{twoPageSoilKind\(form\)\}/);

  const veg = read('TwoPageVegetationPanel.svelte');
  assert.ok(veg.includes('form, parentBlocked }'), 'TwoPageVegetationPanel must preserve $props() substring');
  assert.match(veg, /class="[^"]*\bvpro-sticky-subbar\b[^"]*"[^>]*data-veg-sticky-bar[\s\S]*?Save vegetation[\s\S]*?Add species row/);

  const fs882 = read('FS882Form.svelte');
  for (const guard of [
    'otherHeaderWorkflowBusy',
    'headerWorkflowBusy',
    'tabWorkflowBusy',
    'siviCreationPeerUnsaved',
    'nonParentChildUnsaved',
    'childUnsaved',
  ]) {
    assert.ok(fs882.includes(guard), `FS882Form must preserve ${guard}`);
  }
  assert.match(fs882, /<nav aria-label=\{siviStandalone \? 'SIVI sections' : 'FS882 sections'\}/);
});

test('FS882ChildCreateModal wraps active toolbars in data-sticky-child-draft-bar and omits wrapper when idle', () => {
  const modalComp = serverComponent(read('FS882ChildCreateModal.svelte'), 'FS882ChildCreateModal.svelte', {
    '@lucide/svelte': { X: () => '' },
    './NewChild.svelte': { default: () => '' },
    './PersonalSpeciesFields.svelte': { default: () => '' },
    './formPresentation': { controlLabel: c => c?.column ?? '' },
    './paperLayout': { paperChild: () => ({ controls: [] }) },
    './vegetationSpeciesEditor': { speciesEventError: () => null },
  });

  const idleHtml = render(modalComp, { props: { region: 'toolbars' } }).body;
  assert.doesNotMatch(idleHtml, /data-sticky-child-draft-bar/);

  const dirtyHtml = render(modalComp, { props: { region: 'toolbars', heightUnsaved: true } }).body;
  assert.match(dirtyHtml, /data-sticky-child-draft-bar/);
  assert.match(dirtyHtml, /class="[^"]*sticky top-0 z-20[^"]*"[^>]*data-sticky-child-draft-bar/);
  assert.match(dirtyHtml, /Save height\/cover drafts/);
});

test('inline successMsg and statusMsg banners are removed from templates while preserving script state and deduped notifications', async () => {
  const fs882 = read('FS882Form.svelte');
  const fs882Parts = splitSvelte(fs882);
  assert.doesNotMatch(fs882Parts.template, /\{#if successMsg\}/);
  assert.match(fs882Parts.script, /\bsuccessMsg = \$state<string \| null>\(null\)/);
  assert.match(fs882Parts.script, /successMsg = 'Changes undone\.'/);

  const veg = read('TwoPageVegetationPanel.svelte');
  const vegParts = splitSvelte(veg);
  assert.doesNotMatch(vegParts.template, /\{#if statusMsg\}/);
  assert.match(vegParts.script, /let statusMsg = \$state<string \| null>\(null\)/);
  assert.match(vegParts.script, /statusMsg = `Created vegetation row for \$\{created\.species\}\.`/);

  // Test actual $effect snippet from FS882Form.svelte deduplicating direct save/undo toasts while forwarding child/SIVI successMsg
  const client = await import('svelte/internal/client');
  const effectMatch = fs882Parts.script.match(/let lastNotifiedSuccessMsg: string \| null = null;\s*\$effect\(\(\) => \{[\s\S]*?\n  \}\);/);
  assert.ok(effectMatch, 'FS882Form must define lastNotifiedSuccessMsg $effect');

  const probeSrc = `<script lang="ts">
    let { inspect, notifications } = $props();
    let successMsg = $state<string | null>(null);
    let draft = $state({ plotNumber: '00337' });
    ${effectMatch[0]}
    $effect(() => inspect({
      setSuccess(msg: string | null) { successMsg = msg; },
      simulateDirectSave() {
        successMsg = 'Plot 00337 saved successfully.';
        lastNotifiedSuccessMsg = successMsg;
        notifications.success('Plot 00337 saved', 'Saved to project file.', { category: 'entry', source: 'FS882 Form', contextTag: 'Plot 00337' });
      },
    }));
  </script>`;
  const compiled = compile(probeSrc, { generate: 'client' });
  assert.equal(compiled.warnings.length, 0);
  const ast = ts.createSourceFile('probe.js', compiled.js.code, ts.ScriptTarget.Latest, true);
  const code = ast.statements.filter(n => !ts.isImportDeclaration(n)).map(n => n.getText(ast)).join('\n')
    .replace('export default function', 'function');
  const mount = new Function('$', 'untrack', code + '\nreturn _unknown_;')(client, client.untrack);

  const pushed = [];
  let api;
  const dispose = client.effect_root(() => mount(null, {
    inspect: v => { api = v; },
    notifications: { success: (title, msg, opts) => pushed.push({ title, msg, opts }) },
  }));
  try {
    client.flush();
    assert.equal(pushed.length, 0);

    // Direct save sets lastNotifiedSuccessMsg so $effect must NOT duplicate the toast
    api.simulateDirectSave();
    client.flush();
    assert.equal(pushed.length, 1);
    assert.equal(pushed[0].title, 'Plot 00337 saved');

    // Child/SIVI completion clears then sets successMsg -> $effect emits entry notification with Plot contextTag
    api.setSuccess(null);
    client.flush();
    api.setSuccess('Saved 2 height/cover row drafts.');
    client.flush();
    assert.equal(pushed.length, 2);
    assert.equal(pushed[1].title, 'Saved 2 height/cover row drafts.');
    assert.deepEqual(pushed[1].opts, { category: 'entry', source: 'FS882 Form', contextTag: 'Plot 00337' });
  } finally {
    dispose();
  }
});

test('FS882Form sourceEnter handles Ctrl+S / Cmd+S and tags save/undo/toggleLock notifications with category entry and contextTag', async () => {
  let saves = 0;
  const makeKeyCtx = (overrides = {}) => componentFunctions('FS882Form.svelte', ['sourceEnter'], {
    twoPageOpen: false,
    twoPageScope: 'extra',
    fieldCardModalOpen: false,
    fieldCardSplitOpen: false,
    sourceEnterEnabled: true,
    container: null,
    error: null,
    draft: { locked: false },
    busy: false,
    headerWorkflowBusy: false,
    capabilitiesReady: true,
    dirty: true,
    childUnsaved: false,
    save: async () => { saves++; },
    ...overrides,
  });

  let prevented = 0;
  makeKeyCtx().actions.sourceEnter({
    ctrlKey: true, metaKey: false, altKey: false, shiftKey: false, key: 's',
    preventDefault: () => { prevented++; },
  });
  makeKeyCtx().actions.sourceEnter({
    ctrlKey: false, metaKey: true, altKey: false, shiftKey: false, key: 'S',
    preventDefault: () => { prevented++; },
  });
  assert.equal(prevented, 2);
  assert.equal(saves, 2);

  // Guarded states call preventDefault() but do not save
  for (const guard of [
    { draft: { locked: true } },
    { busy: true },
    { headerWorkflowBusy: true },
    { capabilitiesReady: false },
    { dirty: false, childUnsaved: false },
  ]) {
    makeKeyCtx(guard).actions.sourceEnter({
      ctrlKey: true, metaKey: false, altKey: false, shiftKey: false, key: 's',
      preventDefault: () => { prevented++; },
    });
  }
  assert.equal(prevented, 7);
  assert.equal(saves, 2);

  // Shift+Ctrl+S does not trigger save
  makeKeyCtx().actions.sourceEnter({
    ctrlKey: true, metaKey: false, altKey: false, shiftKey: true, key: 's',
    preventDefault: () => { prevented++; },
  });
  assert.equal(saves, 2);

  // save(), undo(), toggleLock() tag notifications with category: 'entry', source: 'FS882 Form', contextTag: 'Plot 00337'
  const toasts = [];
  const ctx = componentFunctions('FS882Form.svelte', ['save', 'undo', 'toggleLock'], {
    $state: { snapshot: v => structuredClone(v) },
    siviSourceAuthorityUnknown: false,
    busy: false,
    headerWorkflowBusy: false,
    siviDeletionPending: false,
    siviRestorationPending: false,
    siviCreationUndoPending: false,
    codeCheckOpen: false,
    metadataOpen: false,
    profileReviewBlocked: false,
    personalDraft: null,
    deletionReview: null,
    creationDraft: null,
    siviParentActionUnsaved: false,
    siviProjectAssignmentUnsaved: false,
    siviParentWriteUnsaved: false,
    siviParentSharedUnsaved: false,
    siviUnsaved: false,
    siviCoverUnsaved: false,
    siviCombinedUnsaved: false,
    siviCollectedUnsaved: false,
    siviSpeciesUnsaved: false,
    siviIdentityUnsaved: false,
    siviCreationPending: false,
    heightUnsaved: false,
    otherUnsaved: false,
    soilUnsaved: false,
    attributeUnsaved: false,
    collectedUnsaved: false,
    speciesUnsaved: false,
    twoPageOpen: false,
    environmentSUOpen: false,
    capabilitiesReady: true,
    capabilities: { locked: true },
    headerValidation: {},
    dirty: true,
    draft: { plotNumber: '00337', locked: false },
    original: { plotNumber: '00337', locked: false },
    activeLayerDepthRaw: null,
    workingUnitSession: { plot: '' },
    headerRevision: 0,
    error: null,
    successMsg: null,
    container: { querySelector: () => null },
    PlotService: { UpdatePlot: async () => {}, CreatePlot: async () => {} },
    loadChildData: async () => {},
    siviParentSession: null,
    onSaved: async () => {},
    notifications: {
      success: (title, msg, opts) => toasts.push({ kind: 'success', title, msg, opts }),
    },
  });

  await ctx.actions.save();
  assert.equal(ctx.error, null);
  ctx.dirty = true;
  ctx.actions.undo();
  await ctx.actions.toggleLock();

  assert.equal(toasts.length, 3);
  for (const t of toasts) {
    assert.deepEqual({ ...t.opts }, { category: 'entry', source: 'FS882 Form', contextTag: 'Plot 00337' });
  }
});

test('TwoPageEntryEditor handles Ctrl+S / Cmd+S and emits entry notifications with Plot contextTag on save, undo, restore, and failure', async () => {
  let ops = [];
  const makeKeyCtx = (overrides = {}) => componentFunctions('TwoPageEntryEditor.svelte', ['handleTwoPageKeydown'], {
    fieldCardModalOpen: false,
    fieldCardSplitOpen: false,
    externalOpen: false,
    auditOpen: false,
    googleEarthOpen: false,
    childBlocked: false,
    editingEnabled: true,
    close: { canSave: true, busy: false, blocked: false },
    operation: async op => { ops.push(op); },
    ...overrides,
  });

  let prevented = 0;
  makeKeyCtx().actions.handleTwoPageKeydown({
    ctrlKey: true, metaKey: false, altKey: false, shiftKey: false, key: 's',
    preventDefault: () => { prevented++; },
  });
  makeKeyCtx().actions.handleTwoPageKeydown({
    ctrlKey: false, metaKey: true, altKey: false, shiftKey: false, key: 'S',
    preventDefault: () => { prevented++; },
  });
  assert.equal(prevented, 2);
  assert.deepEqual(ops, ['save', 'save']);

  for (const guard of [
    { childBlocked: true },
    { editingEnabled: false },
    { close: { canSave: false, busy: false, blocked: false } },
    { close: { canSave: true, busy: true, blocked: false } },
    { close: { canSave: true, busy: false, blocked: true } },
    { auditOpen: true },
  ]) {
    makeKeyCtx(guard).actions.handleTwoPageKeydown({
      ctrlKey: true, metaKey: false, altKey: false, shiftKey: false, key: 's',
      preventDefault: () => { prevented++; },
    });
  }
  assert.equal(prevented, 8);
  assert.deepEqual(ops, ['save', 'save']);

  const events = [];
  let saveOk = true;
  let unsaved = true;
  const opCtx = componentFunctions('TwoPageEntryEditor.svelte', ['operation'], {
    owner: { contextId: 'ctx-1', project: 'Sample', plot: '00337' },
    form: 'FS882-8x6XL',
    externalOpen: false,
    auditOpen: false,
    googleEarthOpen: false,
    reviewEnabled: true,
    editingEnabled: true,
    childBlocked: false,
    error: null,
    AuditRestoreAction: { AuditRestoreRetain: 'retain', AuditRestorePrune: 'prune' },
    close: { unsaved: true, busy: false, blocked: false, canSave: true },
    session: {
      closeState: () => ({ unsaved }),
      view: () => ({ error: saveOk ? null : 'Save conflict on plot 00337', referenceError: null }),
      save: async () => saveOk,
      undo: async () => { unsaved = false; return true; },
      restore: async () => true,
      load: async () => true,
      loadReferences: async () => true,
    },
    notifications: {
      success: (title, msg, opts) => events.push({ level: 'success', title, msg, opts }),
      info: (title, msg, opts) => events.push({ level: 'info', title, msg, opts }),
      error: (title, msg, opts) => events.push({ level: 'error', title, msg, opts }),
    },
  });

  await opCtx.actions.operation('save');
  await opCtx.actions.operation('undo');
  // Undo when already clean should not emit info toast
  opCtx.close.unsaved = false;
  await opCtx.actions.operation('undo');
  await opCtx.actions.operation('retain');
  saveOk = false;
  await opCtx.actions.operation('save');

  assert.equal(events.length, 4);
  assert.equal(events[0].level, 'success');
  assert.equal(events[1].level, 'info');
  assert.equal(events[2].level, 'success');
  assert.equal(events[3].level, 'error');
  assert.equal(opCtx.error, 'Save conflict on plot 00337');
  for (const ev of events) {
    assert.deepEqual({ ...ev.opts }, { category: 'entry', source: 'Two-Page Form', contextTag: 'Plot 00337' });
  }
});

test('TwoPageSoilPanel and TwoPageVegetationPanel push entry notifications with Plot contextTag on save, create, delete, and restore', async () => {
  const soilEvents = [];
  const soilCtx = componentFunctions('TwoPageSoilPanel.svelte',
    ['operation', 'createHorizon', 'confirmDeleteHorizon', 'restoreDeletedHorizon'], {
      $state: { snapshot: v => structuredClone(v) },
      contextId: 'ctx-1',
      project: 'Sample',
      plot: '00337',
      form: 'SoilHumusXL',
      parentBlocked: false,
      referenceView: { busy: false },
      view: { busy: false, original: { records: {} }, creation: { raw: 'LF' }, receipts: [{ history: { CreatedRowID: '9' } }] },
      close: { unsaved: false, blocked: false, canSave: true },
      row: { rowId: '1' },
      depthOrder: { rows: [{ rowId: '2' }] },
      deleteConfirmRowId: '1',
      deleteRestoreBusy: false,
      deletedHistoryOpen: true,
      deletedHorizons: [],
      deleteRestoreGeneration: 0,
      selected: '1',
      error: null,
      crypto: { randomUUID: () => 'uuid-1' },
      twoPageSoilKind: () => 'Humus',
      twoPageSoilStoredText: () => '1',
      focusHorizon: async () => true,
      panel: {
        dataset: { twoPageSoilPanel: 'SoilHumusXL' },
        querySelector: () => ({ disabled: false, checkVisibility: () => true, value: 'LF' }),
      },
      session: {
        save: async () => true,
        create: async () => true,
        load: async () => true,
        view: () => ({ error: null, receipts: [{ history: { CreatedRowID: '9' } }] }),
      },
      resolveSoilDeleteRestorePort: async () => ({
        deleteHorizon: async () => ({ requestId: 'uuid-1', deletedId: 1, horizon: 'LF' }),
        restoreHorizon: async () => ({ requestId: 'uuid-1', restoredId: 1, restoredRowId: '1', horizon: 'LF' }),
        listDeletedHorizons: async () => [],
      }),
      notifications: {
        success: (title, msg, opts) => soilEvents.push({ title, msg, opts }),
      },
    });

  await soilCtx.actions.operation('save');
  await soilCtx.actions.createHorizon();
  await soilCtx.actions.confirmDeleteHorizon();
  await soilCtx.actions.restoreDeletedHorizon('del-1');

  assert.equal(soilEvents.length, 4);
  for (const ev of soilEvents) {
    assert.deepEqual({ ...ev.opts }, { category: 'entry', source: 'Two-Page Soil', contextTag: 'Plot 00337' });
  }

  const vegEvents = [];
  const vegCtx = componentFunctions('TwoPageVegetationPanel.svelte',
    ['operation', 'submitCreateRow', 'confirmDeleteRow', 'restoreDeletedRow'], {
      contextId: 'ctx-1',
      project: 'Sample',
      plot: '00337',
      form: 'SubVegAXL_BC',
      parentBlocked: false,
      fieldsDisabled: false,
      crudBusy: false,
      crudGeneration: 0,
      createOpen: true,
      createSpecies: 'ABIEALB',
      createLayer: 'A1',
      createCollected: 'C',
      deleteConfirmRowId: '3',
      deletedRows: [],
      error: null,
      statusMsg: null,
      row: { rowId: '3' },
      view: { original: { records: {} } },
      close: { unsaved: false, blocked: false, canSave: true },
      crypto: { randomUUID: () => 'uuid-2' },
      twoPageVegetationStoredText: () => '3',
      session: {
        save: async () => true,
        load: async () => true,
        select: () => {},
        view: () => ({ error: null, referenceError: null }),
      },
      resolveCrudPort: async () => ({
        createRow: async () => ({ requestId: 'uuid-2', rowId: '4', id: 4, species: 'ABIEALB' }),
        deleteRow: async () => ({ requestId: 'uuid-2', deletedId: 3, species: 'TSUGHET' }),
        restoreRow: async () => ({ requestId: 'uuid-2', restoredId: 3, restoredRowId: '3', species: 'TSUGHET' }),
        listDeletedRows: async () => [],
      }),
      notifications: {
        success: (title, msg, opts) => vegEvents.push({ title, msg, opts }),
      },
    });

  await vegCtx.actions.operation('save');
  await vegCtx.actions.submitCreateRow();
  assert.match(vegCtx.statusMsg, /Created vegetation row for ABIEALB/);
  await vegCtx.actions.confirmDeleteRow();
  assert.match(vegCtx.statusMsg, /Deleted vegetation row 3/);
  await vegCtx.actions.restoreDeletedRow('del-3');
  assert.match(vegCtx.statusMsg, /Restored vegetation row 3/);

  assert.equal(vegEvents.length, 4);
  for (const ev of vegEvents) {
    assert.deepEqual({ ...ev.opts }, { category: 'entry', source: 'Two-Page Vegetation', contextTag: 'Plot 00337' });
  }
});
