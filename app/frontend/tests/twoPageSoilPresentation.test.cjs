const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync } = require('node:fs');
const { render } = require('svelte/server');
const { loadTypeScript, serverComponent, srcPath } = require('./svelteTestHelpers.cjs');
const { editor, TwoPageSoilSession, fixture, original, cell } = require('./twoPageSoilTestHelpers.cjs');
const { metadata, transport, restoration } = require('./siviParentTestHelpers.cjs');

const quality = loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });
const soilReferences = loadTypeScript('twoPageSoilReferences.ts', {
  './siviParentTransport': transport,
  './projectMetadataRestore': restoration,
  './qualityEditor': quality,
  './readRequests': loadTypeScript('readRequests.ts', { '@wailsio/runtime': {} }),
});
const soil = loadTypeScript('soilChildEditor.ts', {
  './qualityEditor': quality,
  './numericEditor': loadTypeScript('numericEditor.ts'),
});
const presentation = loadTypeScript('twoPageSoilPresentation.ts', {
  './projectMetadataEditor': metadata,
  './twoPageSoilEditor': editor,
  './soilChildEditor': soil,
});
const navigation = loadTypeScript('enterNavigation.ts');
const sourceChoices = serverComponent(readFileSync(srcPath('SoilReferenceChoices.svelte'), 'utf8'), 'SoilReferenceChoices.svelte', {
  './projectMetadataEditor': metadata,
});
const panelSource = readFileSync(srcPath('TwoPageSoilPanel.svelte'), 'utf8');

const bindings = {
  Humus: [
    'Horizon', 'UpperDepth', 'LowerDepth', 'HumusStructureDegree', 'HumusStructureKind',
    'MycelAbundance', 'FecalAbundance', 'RootsAbundance', 'RootsSize', 'vonPost', 'HumusFormpH', 'Comment',
  ],
  Mineral: [
    'Horizon', 'UpperDepth', 'LowerDepth', 'PitDepthLimit', 'Texture', 'Colour', 'ASP',
    'PercentCoarseFragsGravel', 'PercentCoarseFragsCobbles', 'PercentCoarseFragsStones', 'PercentCoarseFragsTotal',
    'PercentCoarseFragsShape', 'RootsAbundance', 'RootsSize', 'MineralStructureClass', 'MineralStructureKind',
    'MineralFormpH', 'Comments',
  ],
};

function buildOriginal(kind, rowSpecs) {
  const source = original();
  source.form = `Soil${kind}XL`;
  source.table = `Sample_${kind}`;
  source.recordSource = `Usys${kind}`;
  for (const name of bindings[kind]) {
    if (source.records.columns.some(column => column.name === name)) continue;
    source.records.columns.push({ name, declaredType: '' });
    for (const row of source.records.rows) row.cells.push(cell());
  }
  const idIdx = source.records.columns.findIndex(c => c.name === 'ID');
  const plotIdx = source.records.columns.findIndex(c => c.name === 'PlotNumber');
  const hzIdx = source.records.columns.findIndex(c => c.name === 'Horizon');
  const upIdx = source.records.columns.findIndex(c => c.name === 'UpperDepth');
  const loIdx = source.records.columns.findIndex(c => c.name === 'LowerDepth');
  const template = source.records.rows[0];
  source.records.rows = rowSpecs.map((spec, idx) => {
    const row = structuredClone(template);
    row.rowId = spec.rowId ?? String(idx + 1);
    for (let i = 0; i < row.cells.length; i++) row.cells[i] = cell();
    row.cells[idIdx] = cell('integer', String(spec.id ?? idx + 1));
    row.cells[plotIdx] = cell('text', source.plot);
    row.cells[hzIdx] = spec.horizon === null ? cell() : cell('text', spec.horizon);
    row.cells[upIdx] = spec.upper === null ? cell() : cell('real', spec.upper);
    row.cells[loIdx] = spec.lower === null ? cell() : cell('real', spec.lower);
    return row;
  });
  return source;
}

async function renderPanelHTML(source) {
  const operation = value => Object.assign(Promise.resolve(value), { cancel() {} });
  const session = new TwoPageSoilSession(
    { ...fixture.owner, form: source.form },
    {
      read: () => operation(source),
      save: () => { throw new Error('Unexpected Save'); },
      outcome: () => { throw new Error('Unexpected recovery'); },
    }
  );
  assert.equal(await session.load(), true);
  const component = serverComponent(panelSource, 'TwoPageSoilPanel.svelte', {
    '../bindings/github.com/boostao/vpro/app': {
      PlotEntryService: { GetTwoPageSoilReferences() { throw new Error('Unexpected reference read'); } },
    },
    './twoPageSoilReferences': soilReferences,
    './SoilReferenceChoices.svelte': { default: sourceChoices },
    './twoPageSoilSessions': {
      twoPageSoilSession: () => session,
      twoPageSoilWritingEnabled: true,
      twoPageSoilCreationEnabled: true,
    },
    './twoPageSoilEditor': editor,
    './projectMetadataEditor': metadata,
    './soilChildEditor': soil,
    './twoPageSoilPresentation': presentation,
    './enterNavigation': navigation,
    '../shell/notificationService.svelte': { notifications: { push() {}, success() {}, info() {}, warning() {}, error() {} } },
  });
  return render(component, { props: { ...fixture.owner, form: source.form, parentBlocked: false } }).body;
}

test('twoPageSoilDepthOrder and TwoPageSoilPanel render ascending order and wetland copy for pure wetland profiles (UX-SOIL-001)', async () => {
  const source = buildOriginal('Humus', [
    { rowId: '1', id: 1, horizon: 'Oh', upper: 35, lower: 60 },
    { rowId: '2', id: 2, horizon: 'Hydric', upper: 60, lower: 75 },
    { rowId: '3', id: 3, horizon: 'Of1', upper: 0, lower: 15 },
    { rowId: '4', id: 4, horizon: '2Om', upper: 15, lower: 35 },
    { rowId: '5', id: 5, horizon: 'IIOh', upper: null, lower: null },
    { rowId: '6', id: 6, horizon: 'Limno', upper: 75, lower: 90 },
    { rowId: '7', id: 7, horizon: 'Cumulo', upper: 90, lower: 110 },
  ]);
  const res = presentation.twoPageSoilDepthOrder(source);
  assert.equal(res.diagnostic, null);
  assert.deepEqual(
    res.rows.map(r => r.rowId),
    ['3', '4', '1', '2', '6', '7', '5']
  );
  assert.equal(res.status, 'Depth Down ascending (NULL last). Ties retain physical reader order.');

  const html = await renderPanelHTML(source);
  assert.match(html, /Depth Down ascending \(NULL last\)\. Ties retain physical reader order\./);
  assert.doesNotMatch(html, /Depth Up descending/);
});

test('twoPageSoilDepthOrder and TwoPageSoilPanel render mixed upland-then-wetland order and dynamic status copy (UX-SOIL-001)', async () => {
  const source = buildOriginal('Humus', [
    { rowId: '1', id: 1, horizon: 'Oh', upper: 15, lower: 40 },
    { rowId: '2', id: 2, horizon: 'H', upper: 5, lower: 0 },
    { rowId: '3', id: 3, horizon: 'Of1', upper: 0, lower: 15 },
    { rowId: '4', id: 4, horizon: 'L', upper: 10, lower: 5 },
    { rowId: '5', id: 5, horizon: '2L', upper: null, lower: null },
  ]);
  const res = presentation.twoPageSoilDepthOrder(source);
  assert.equal(res.diagnostic, null);
  // Upland L(10) -> H(5) -> 2L(NULL), then wetland Of1(0) -> Oh(15)
  assert.deepEqual(
    res.rows.map(r => r.rowId),
    ['4', '2', '5', '3', '1']
  );
  assert.equal(res.status, 'Upland descending, then wetland ascending (NULL last). Ties retain physical reader order.');

  const html = await renderPanelHTML(source);
  assert.match(html, /Upland descending, then wetland ascending \(NULL last\)\. Ties retain physical reader order\./);
});

test('twoPageSoilDepthOrder and TwoPageSoilPanel preserve upland descending and mineral ascending copy', async () => {
  const upland = buildOriginal('Humus', [
    { rowId: '1', id: 1, horizon: 'Fm', upper: 2, lower: 0 },
    { rowId: '2', id: 2, horizon: 'Lv', upper: 6, lower: 2 },
  ]);
  const upRes = presentation.twoPageSoilDepthOrder(upland);
  assert.deepEqual(upRes.rows.map(r => r.rowId), ['2', '1']);
  assert.equal(upRes.status, 'Depth Up descending (NULL last). Ties retain physical reader order.');
  const upHtml = await renderPanelHTML(upland);
  assert.match(upHtml, /Depth Up descending \(NULL last\)\. Ties retain physical reader order\./);

  const mineral = buildOriginal('Mineral', [
    { rowId: '1', id: 1, horizon: 'BC', upper: 25, lower: 60 },
    { rowId: '2', id: 2, horizon: 'Ah', upper: 0, lower: 15 },
    { rowId: '3', id: 3, horizon: 'Bm', upper: null, lower: null },
  ]);
  const minRes = presentation.twoPageSoilDepthOrder(mineral);
  assert.deepEqual(minRes.rows.map(r => r.rowId), ['3', '2', '1']);
  assert.equal(minRes.status, 'Depth Up ascending (NULL first). Ties retain physical reader order.');
  const minHtml = await renderPanelHTML(mineral);
  assert.match(minHtml, /Depth Up ascending \(NULL first\)\. Ties retain physical reader order\./);
});
