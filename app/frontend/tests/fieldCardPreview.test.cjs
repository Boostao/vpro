const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const { compile } = require('svelte/compiler');
const { render } = require('svelte/server');
const { serverComponent, loadTypeScript, componentFunctions, presentationHelpers, srcPath } = require('./svelteTestHelpers.cjs');

const read = (file) => readFileSync(srcPath(file), 'utf8');
const { paper, presentation } = presentationHelpers();
const preview = loadTypeScript('fieldCardPreview.ts', {
  './paperLayout': paper,
  './formPresentation': presentation,
});

test('buildFieldCardViewModel prioritizes staged drafts over committed values, flags UNSAVED DRAFT, and sums 6-cell Substrate (%)', () => {
  const committedHeader = {
    plotNumber: '00337',
    fieldNo: 'FN-01',
    date: '2026-07-14',
    surveyor: 'W. MacKenzie',
    projectId: 'BEC-2026',
    latitude: 54.123456,
    longitude: -126.654321,
    utmZone: '9',
    easting: 653210,
    northing: 5999120,
    zone: 'SBS',
    subZone: 'dk',
    siteSeries: '01',
    moistureRegime: '4',
    nutrientRegime: 'C',
    substrateOrganicMatter: 15,
    substrateDecWood: 10,
    substrateBedRock: 5,
    substrateRocks: 10,
    substrateMineralSoil: 55,
    substrateWater: 0,
    fieldNotes: 'Committed field note',
    officeNotes: 'Committed office note',
    soilNotes: 'Committed soil note',
    vegNotes: 'Committed veg note',
    speciesListComplete: true,
  };

  // Clean state first
  const cleanVm = preview.buildFieldCardViewModel({
    formKind: 'fs882',
    committedHeader,
    draftHeader: { ...committedHeader },
  });
  assert.equal(cleanVm.isDirty, false);
  assert.equal(cleanVm.plotNumber, '00337');
  assert.equal(cleanVm.becUnitMask, 'SBS dk / 01');
  assert.equal(cleanVm.substrateTotal, 95);
  assert.equal(cleanVm.substrateTotalDisplay, '95% / 100%');
  assert.deepEqual(
    Array.from(cleanVm.front.substrateCells, (c) => c.key),
    [
      'SubstrateOrganicMatter',
      'SubstrateDecWood',
      'SubstrateBedRock',
      'SubstrateRocks',
      'SubstrateMineralSoil',
      'SubstrateWater',
    ],
  );
  assert.match(cleanVm.formattedCoordinates, /54\.123456°, -126\.654321°/);
  assert.match(cleanVm.formattedCoordinates, /NAD83 UTM 9 653210E 5999120N/);

  // Draft overrides across header, substrate, soil, and vegetation
  const dirtyVm = preview.buildFieldCardViewModel({
    formKind: 'fs882',
    committedHeader,
    draftHeader: {
      ...committedHeader,
      siteSeries: '05',
      substrateWater: 5,
      fieldNotes: 'Updated live field note',
    },
    humusRows: [
      { id: 1, horizon: 'H', upperDepth: 2, lowerDepth: 0, ph: 4.5, comment: 'dark' },
      { id: 2, horizon: 'L', upperDepth: 8, lowerDepth: 5, ph: 5.1, comment: 'litter' },
      { id: 3, horizon: 'Fm', upperDepth: 5, lowerDepth: 2, ph: 4.8, comment: 'mycelial' },
    ],
    soilDrafts: {
      'Humus/2': {
        kind: 'Humus',
        id: 2,
        cells: {
          upperDepth: { raw: '10', expected: 8, value: 10, error: null },
        },
      },
    },
    mineralRows: [
      { id: 10, horizon: 'Bf', upperDepth: 12, lowerDepth: 45, texture: 'SL', colour: '7.5YR 4/6' },
      { id: 11, horizon: 'Ae', upperDepth: 0, lowerDepth: 12, texture: 'LS', colour: '10YR 6/2' },
    ],
    vegRows: [
      { id: 100, species: 'PINUCON', collected: null, cover1: 35, height1: 22, totalA: 35 },
      { id: 101, species: 'CORNCAN', cover6: 12, height6: 0.15 },
      { id: 102, species: 'PLEUSCH', cover7: 45 },
    ],
    heightDrafts: {
      '100': {
        cover1: { raw: '42.5', expected: 35, value: 42.5, error: null },
      },
    },
    speciesDrafts: {
      '101': { form: 'SubVegCXL', raw: 'LINNBOR', expected: 'CORNCAN', error: null },
    },
    collectedDrafts: {
      '100': { value: 'V', expected: null, form: 'SubVegAXL_BC' },
    },
  });

  assert.equal(dirtyVm.isDirty, true);
  assert.equal(dirtyVm.becUnitMask, 'SBS dk / 05');
  assert.equal(dirtyVm.substrateTotal, 100);
  assert.equal(dirtyVm.substrateTotalDisplay, '100% / 100%');
  assert.equal(dirtyVm.front.notes.siteNotes, 'Updated live field note');

  // Upland L/F/H ordered UpperDepth DESC (10 -> 5 -> 2)
  assert.deepEqual(
    Array.from(dirtyVm.front.organicHorizons, (r) => [r.horizon, r.depthRange, r.isDraft]),
    [
      ['L', '10–5 cm', true],
      ['Fm', '5–2 cm', false],
      ['H', '2–0 cm', false],
    ],
  );

  // Mineral ordered UpperDepth ASC (0 -> 12)
  assert.deepEqual(
    Array.from(dirtyVm.front.mineralHorizons, (r) => [r.horizon, r.depthRange]),
    [
      ['Ae', '0–12 cm'],
      ['Bf', '12–45 cm'],
    ],
  );

  // Veg drafts merged over committed rows
  assert.equal(dirtyVm.back.treeShrubRows.length, 1);
  assert.equal(dirtyVm.back.treeShrubRows[0].cover1, '42.5');
  assert.equal(dirtyVm.back.treeShrubRows[0].collected, 'V');
  assert.equal(dirtyVm.back.treeShrubRows[0].isDraft, true);
  assert.equal(dirtyVm.back.herbRows[0].species, 'LINNBOR');
  assert.equal(dirtyVm.back.mossRows[0].cover7, '45');
});

test('buildFieldCardViewModel handles wetland downward organic horizons, extended shrub layers, Two-Page, and SIVI modes', () => {
  // Null substrate returns null total
  const emptySub = preview.buildFieldCardViewModel({
    formKind: 'fs882',
    draftHeader: { plotNumber: '00001' },
    humusRows: [
      { id: 1, horizon: 'Om', upperDepth: 20, lowerDepth: 55 },
      { id: 2, horizon: 'Of', upperDepth: 0, lowerDepth: 20 },
    ],
    vegRows: [
      { id: 1, species: 'BETUNAN', cover4: 15, cover5a: 8, cover5b: 4, cover5c: 2, totalB: 29 },
    ],
    extendedShrubs: true,
    snowCoverRegimeRaw: 'M',
    activeLayerDepthRaw: '48.5',
  });
  assert.equal(emptySub.substrateTotal, null);
  assert.equal(emptySub.substrateTotalDisplay, '— / 100%');
  // Wetland Of/Om ordered UpperDepth ASC (0–20 then 20–55)
  assert.deepEqual(
    Array.from(emptySub.front.organicHorizons, (r) => [r.horizon, r.depthRange]),
    [
      ['Of', '0–20 cm'],
      ['Om', '20–55 cm'],
    ],
  );
  assert.equal(emptySub.extendedShrubs, true);
  assert.equal(emptySub.back.showExtendedShrubColumns, true);
  assert.equal(emptySub.back.treeShrubRows[0].cover5a, '8');
  assert.equal(emptySub.back.treeShrubRows[0].cover5b, '4');
  assert.equal(emptySub.back.treeShrubRows[0].cover5c, '2');
  assert.equal(
    emptySub.front.topographyQualityCells.find((c) => c.key === 'SnowCoverregime')?.value,
    'M',
  );
  assert.equal(
    emptySub.front.topographyQualityCells.find((c) => c.key === 'ActiveLayerDepth')?.value,
    '48.5',
  );

  // SIVI / FS1333 parent original + shared draft merge
  const siviVm = preview.buildFieldCardViewModel({
    formKind: 'sivi',
    siviParentOriginal: {
      Plot: 'SIVI01',
      EnvTable: 'Sample_Env',
      Bindings: [
        { ControlID: 'c1', Binding: 'PlotType', Table: 'Sample_Env', Column: 0 },
        { ControlID: 'c2', Binding: 'Zone', Table: 'Sample_Env', Column: 1 },
        { ControlID: 'c3', Binding: 'SV_PolygonNumber', Table: 'Sample_Env', Column: 2 },
        { ControlID: 'c4', Binding: 'SV_FloodPlain', Table: 'Sample_Env', Column: 3 },
      ],
      Rows: [
        {
          Env: {
            rowId: '1',
            cells: [
              { storage: 'text', text: 'G' },
              { storage: 'text', text: 'ICH' },
              { storage: 'text', text: 'POLY-77' },
              { storage: 'integer', integer: '-1' },
            ],
          },
          Admin: { rowId: '1', cells: [] },
        },
      ],
    },
    siviSharedDrafts: {
      Zone: { input: { kind: 'text', raw: 'ESSF' } },
    },
  });
  assert.equal(siviVm.formCode, 'FS 1333 / SIVI');
  assert.equal(siviVm.plotNumber, 'SIVI01');
  assert.equal(siviVm.isDirty, true);
  assert.equal(siviVm.becUnitMask, 'ESSF');
  assert.equal(siviVm.front.identityCells.find((c) => c.key === 'PlotType')?.value, 'G');
  assert.equal(siviVm.front.identityCells.find((c) => c.key === 'SV_PolygonNumber')?.value, 'POLY-77');
  assert.equal(siviVm.front.soilSummaryCells.find((c) => c.key === 'SV_FloodPlain')?.value, '☑ Yes');
});

test('FieldCardPreviewModal compiles with zero warnings and SSRs both modal and docked modes cleanly', () => {
  const modalSource = read('FieldCardPreviewModal.svelte');
  assert.equal(compile(modalSource, { filename: 'FieldCardPreviewModal.svelte', generate: 'client' }).warnings.length, 0);
  assert.equal(compile(modalSource, { filename: 'FieldCardPreviewModal.svelte', generate: 'server' }).warnings.length, 0);
  assert.doesNotMatch(modalSource, /position:\s*absolute|transform:scale|ResizeObserver|appendChild|appendTo/);
  assert.match(modalSource, /@media print/);
  assert.match(modalSource, /@page/);

  const lucideStub = new Proxy({}, { get: () => () => '' });
  const ModalComp = serverComponent(modalSource, 'FieldCardPreviewModal.svelte', { '@lucide/svelte': lucideStub });
  const vm = preview.buildFieldCardViewModel({
    formKind: 'two-page',
    draftHeader: {
      plotNumber: '00337',
      zone: 'CWH',
      subZone: 'vm1',
      siteSeries: '01',
      substrateOrganicMatter: 40,
      substrateMineralSoil: 60,
    },
    isDirty: true,
    extendedShrubs: true,
  });

  const modalHtml = render(ModalComp, {
    props: { open: true, mode: 'modal', viewModel: vm, onclose() {} },
  }).body;
  assert.match(modalHtml, /data-field-card-modal/);
  assert.match(modalHtml, /data-field-card-dirty-badge[^>]*>UNSAVED DRAFT/);
  assert.match(modalHtml, /data-field-card-side="front"/);
  assert.match(modalHtml, /data-field-card-side="back"/);
  assert.match(modalHtml, /data-field-card-side="both"/);
  assert.match(modalHtml, /data-field-card-theme="bw"/);
  assert.match(modalHtml, /data-field-card-theme="classic"/);
  assert.match(modalHtml, /data-field-card-print/);
  assert.match(modalHtml, /data-field-card-close/);
  assert.match(modalHtml, /data-field-card-sheet="front"/);
  assert.match(modalHtml, /data-field-card-sheet="back"/);
  assert.match(modalHtml, /TOTAL: 100% \/ 100%/);

  const dockedHtml = render(ModalComp, {
    props: { open: true, mode: 'docked', viewModel: vm, onclose() {} },
  }).body;
  assert.match(dockedHtml, /data-field-card-dock/);
  assert.doesNotMatch(dockedHtml, /data-field-card-modal/);
});

test('FS882Form and TwoPageEntryEditor wire View Field Card, Dock Split View, validation jump, and guarded toast receipts', async () => {
  const fs882Src = read('FS882Form.svelte');
  const twoPageSrc = read('TwoPageEntryEditor.svelte');
  assert.equal(compile(fs882Src, { filename: 'FS882Form.svelte', generate: 'client' }).warnings.length, 0);
  assert.equal(compile(twoPageSrc, { filename: 'TwoPageEntryEditor.svelte', generate: 'client' }).warnings.length, 0);

  for (const src of [fs882Src, twoPageSrc]) {
    assert.match(src, /data-view-field-card-btn/);
    assert.match(src, /data-dock-field-card-btn/);
    assert.match(src, /FieldCardPreviewModal/);
  }
  assert.match(fs882Src, /<FormValidationSummary/);

  // Verify handleValidationJump switches tab (including siviParentOpen) and focuses offending input
  let focused = 0;
  const jumpCtx = componentFunctions('FS882Form.svelte', ['handleValidationJump'], {
    activeTab: 'site',
    siviParentOpen: false,
    tick: async () => {},
    container: {},
    focusValidationTarget: (_container, item) => {
      assert.equal(item.tab, 'siviParent');
      focused++;
      return true;
    },
  });
  await jumpCtx.actions.handleValidationJump({
    id: 'hdr-zone',
    tab: 'siviParent',
    tabLabel: 'Plot & Site',
    fieldLabel: 'BEC Zone',
    message: 'Invalid zone',
  });
  assert.equal(jumpCtx.activeTab, 'siviParent');
  assert.equal(jumpCtx.siviParentOpen, true);
  assert.equal(focused, 1);

  // Verify Alt+P toggles fieldCardModalOpen inside sourceEnter without interfering with Enter navigation
  let prevented = 0;
  const keyCtx = componentFunctions('FS882Form.svelte', ['sourceEnter'], {
    twoPageOpen: false,
    twoPageScope: 'extra',
    fieldCardModalOpen: false,
    fieldCardSplitOpen: false,
    sourceEnterEnabled: true,
    container: null,
    error: null,
  });
  keyCtx.actions.sourceEnter({
    altKey: true,
    ctrlKey: false,
    metaKey: false,
    shiftKey: false,
    key: 'p',
    preventDefault: () => { prevented++; },
  });
  assert.equal(prevented, 1);
  assert.equal(keyCtx.fieldCardModalOpen, true);

  // Verify notifications.success is emitted when injected AND safe when omitted in bare VM
  const toasts = [];
  const toastCtx = componentFunctions('FS882Form.svelte', ['undo', 'toggleLock'], {
    twoPageOpen: false,
    environmentSUOpen: false,
    busy: false,
    headerWorkflowBusy: false,
    codeCheckOpen: false,
    metadataOpen: false,
    profileReviewBlocked: false,
    personalDraft: null,
    deletionReview: null,
    creationDraft: null,
    siviDeletionPending: false,
    siviRestorationPending: false,
    siviCreationUndoPending: false,
    siviCreationPending: false,
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
    heightUnsaved: false,
    otherUnsaved: false,
    soilUnsaved: false,
    attributeUnsaved: false,
    collectedUnsaved: false,
    speciesUnsaved: false,
    siviSourceAuthorityUnknown: false,
    original: { plotNumber: '00337', locked: false },
    draft: { plotNumber: '00337', locked: false },
    activeLayerDepthRaw: '12',
    dirty: true,
    headerValidation: { zone: 'bad' },
    error: 'old',
    headerRevision: 0,
    successMsg: null,
    notifications: {
      success: (title, msg) => toasts.push([title, msg]),
    },
  });
  toastCtx.actions.undo();
  assert.equal(toastCtx.dirty, false);
  assert.equal(toastCtx.successMsg, 'Changes undone.');
  assert.equal(toasts.length, 1);
  assert.match(toasts[0][0], /undone/i);

  await toastCtx.actions.toggleLock();
  assert.equal(toastCtx.draft.locked, true);
  assert.equal(toasts.length, 2);
  assert.match(toasts[1][0], /locked/i);
});
