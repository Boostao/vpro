const assert = require('node:assert/strict');
const { test } = require('node:test');
const { loadTypeScript } = require('./svelteTestHelpers.cjs');
const { editor: twoPageSoil, fixture: twoPageFixture, original: twoPageOriginal, cell } = require('./twoPageSoilTestHelpers.cjs');
const { editor: siviEditor, original: siviOriginal, setCell } = require('./siviParentTestHelpers.cjs');

const numeric = loadTypeScript('numericEditor.ts');
const quality = loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });
const soil = loadTypeScript('soilChildEditor.ts', { './numericEditor': numeric, './qualityEditor': quality });
const ordinary = loadTypeScript('ordinaryEditor.ts', { './qualityEditor': quality, './numericEditor': numeric });

test('UX-SOIL-005 FS882 soil child editor rejects out-of-domain values and cross-column coarse-frag overflow', () => {
  // Humus: vonPost=15, HumusFormpH=20, negative depths
  let humusDrafts = {};
  humusDrafts = soil.stageSoil(humusDrafts, 'Humus', 1, soil.soilField('Humus', 'vonPost'), '15', null);
  humusDrafts = soil.stageSoil(humusDrafts, 'Humus', 1, soil.soilField('Humus', 'HumusFormpH'), '20', null);
  humusDrafts = soil.stageSoil(humusDrafts, 'Humus', 1, soil.soilField('Humus', 'UpperDepth'), '-5', null);
  const hErrs = soil.soilErrors(humusDrafts);
  assert.equal(hErrs.length, 3);
  assert.match(hErrs[0], /1 to 10/);
  assert.match(hErrs[1], /0 and 14/);
  assert.match(hErrs[2], />= 0 cm/);
  assert.throws(() => soil.soilUpdates(humusDrafts));

  // Mineral: ASP=99, Total=150, MineralFormpH=20
  let minDrafts = {};
  minDrafts = soil.stageSoil(minDrafts, 'Mineral', 1, soil.soilField('Mineral', 'ASP'), '99', null);
  minDrafts = soil.stageSoil(minDrafts, 'Mineral', 1, soil.soilField('Mineral', 'PercentCoarseFragsTotal'), '150', null);
  minDrafts = soil.stageSoil(minDrafts, 'Mineral', 1, soil.soilField('Mineral', 'MineralFormpH'), '20', null);
  const mErrs = soil.soilErrors(minDrafts);
  assert.equal(mErrs.length, 3);
  assert.match(mErrs[0], /1 to 8/);
  assert.match(mErrs[1], /0% and 100%/);
  assert.match(mErrs[2], /0 and 14/);

  // Mineral cross-column: Gravel=60, Cobbles=60, Stones=60 -> sum 180% > 100%
  let sumDrafts = {};
  sumDrafts = soil.stageSoil(sumDrafts, 'Mineral', 2, soil.soilField('Mineral', 'PercentCoarseFragsGravel'), '60', null);
  sumDrafts = soil.stageSoil(sumDrafts, 'Mineral', 2, soil.soilField('Mineral', 'PercentCoarseFragsCobbles'), '60', null);
  sumDrafts = soil.stageSoil(sumDrafts, 'Mineral', 2, soil.soilField('Mineral', 'PercentCoarseFragsStones'), '60', null);
  assert.match(soil.soilErrors(sumDrafts)[0], /180%.*cannot exceed 100%/);
  assert.throws(() => soil.soilUpdates(sumDrafts), /cannot exceed 100%/);

  // Mineral cross-column: Gravel=30, Cobbles=30, Total=50 -> sum 60% > Total 50%
  let totDrafts = {};
  totDrafts = soil.stageSoil(totDrafts, 'Mineral', 3, soil.soilField('Mineral', 'PercentCoarseFragsGravel'), '30', null);
  totDrafts = soil.stageSoil(totDrafts, 'Mineral', 3, soil.soilField('Mineral', 'PercentCoarseFragsCobbles'), '30', null);
  totDrafts = soil.stageSoil(totDrafts, 'Mineral', 3, soil.soilField('Mineral', 'PercentCoarseFragsTotal'), '50', null);
  assert.match(soil.soilErrors(totDrafts)[0], /cannot exceed PercentCoarseFragsTotal \(50%\)/);

  // Stored row merge: existing Gravel=60 + newly staged Cobbles=50 -> 110% > 100%
  let partialDrafts = {};
  partialDrafts = soil.stageSoil(partialDrafts, 'Mineral', 4, soil.soilField('Mineral', 'PercentCoarseFragsCobbles'), '50', null);
  assert.match(
    soil.soilErrors(partialDrafts, [{ id: 4, percentCoarseFragsGravel: 60 }])[0],
    /110%.*cannot exceed 100%/,
  );

  // Legacy plot 202050: PercentCoarseFragsTotal=100 with NULL components + unrelated Texture edit succeeds
  let legacyDrafts = {};
  legacyDrafts = soil.stageSoil(legacyDrafts, 'Mineral', 5, soil.soilField('Mineral', 'PercentCoarseFragsTotal'), '100', 100);
  legacyDrafts = soil.stageSoil(legacyDrafts, 'Mineral', 5, soil.soilField('Mineral', 'Texture'), 'SL', null);
  assert.equal(soil.soilErrors(legacyDrafts, [{ id: 5, percentCoarseFragsTotal: 100 }]).length, 0);
  assert.equal(soil.soilUpdates(legacyDrafts, [{ id: 5, percentCoarseFragsTotal: 100 }]).length, 1);

  // Unchanged legacy out-of-domain ASP=12 / MineralFormpH=16 allows unrelated Texture edit
  let legacyOutDrafts = {};
  legacyOutDrafts = soil.stageSoil(legacyOutDrafts, 'Mineral', 6, soil.soilField('Mineral', 'ASP'), '12', 12);
  legacyOutDrafts = soil.stageSoil(legacyOutDrafts, 'Mineral', 6, soil.soilField('Mineral', 'MineralFormpH'), '16', 16);
  legacyOutDrafts = soil.stageSoil(legacyOutDrafts, 'Mineral', 6, soil.soilField('Mineral', 'Texture'), 'L', null);
  assert.equal(soil.soilErrors(legacyOutDrafts).length, 0);
  assert.equal(soil.soilUpdates(legacyOutDrafts).length, 1);
});

test('UX-SOIL-005 Two-Page SoilMineralXL enforces cross-column coarse fragments and tolerates unchanged legacy rows', () => {
  const source = twoPageOriginal();
  source.form = 'SoilMineralXL';
  source.recordSource = 'UsysMineral';
  source.table = 'Sample_Mineral';
  source.records.columns = [
    { name: 'ID', declaredType: 'INTEGER' },
    { name: 'PlotNumber', declaredType: 'TEXT' },
    { name: 'Texture', declaredType: 'TEXT' },
    { name: 'PercentCoarseFragsGravel', declaredType: 'INTEGER' },
    { name: 'PercentCoarseFragsCobbles', declaredType: 'INTEGER' },
    { name: 'PercentCoarseFragsStones', declaredType: 'INTEGER' },
    { name: 'PercentCoarseFragsTotal', declaredType: 'INTEGER' },
  ];
  source.records.rows = [
    {
      rowId: '-7',
      cells: [
        cell('integer', '1'),
        cell('text', twoPageFixture.owner.plot),
        cell('text', 'SL'),
        cell('integer', '60'),
        cell(),
        cell(),
        cell('integer', '70'),
      ],
    },
  ];
  const mineralOwner = { ...twoPageFixture.owner, form: 'SoilMineralXL' };

  // Staging Cobbles=60 alongside stored Gravel=60 exceeds 100% and Total=70%
  const badCobbles = twoPageSoil.stageTwoPageSoil(source, '-7', 'PercentCoarseFragsCobbles', '60', false);
  assert.equal(badCobbles.error, null);
  assert.throws(
    () => twoPageSoil.twoPageSoilRequest(source, mineralOwner, { badCobbles }, twoPageFixture.request.requestId),
    /cannot exceed 100%/,
  );

  // Staging Cobbles=20 alongside stored Gravel=60 exceeds Total=70%
  const overTotal = twoPageSoil.stageTwoPageSoil(source, '-7', 'PercentCoarseFragsCobbles', '20', false);
  assert.throws(
    () => twoPageSoil.twoPageSoilRequest(source, mineralOwner, { overTotal }, twoPageFixture.request.requestId),
    /cannot exceed PercentCoarseFragsTotal \(70%\)/,
  );

  // Historical out-of-range row (Gravel=60, Cobbles=60, Total=150) allows unrelated Texture edit when coarse frags are untouched
  source.records.rows[0].cells[4] = cell('integer', '60');
  source.records.rows[0].cells[6] = cell('integer', '150');
  const texEdit = twoPageSoil.stageTwoPageSoil(source, '-7', 'Texture', 'LS', false);
  const req = twoPageSoil.twoPageSoilRequest(source, mineralOwner, { texEdit }, twoPageFixture.request.requestId);
  assert.equal(req.edits.length, 1);
  assert.equal(req.edits[0].column, 'Texture');
});

test('UX-SOIL-005 FS882 ordinary soil header and SIVI parent enforce pit depth and coarse-frag bounds with legacy tolerance', () => {
  // Reject negative HumusThickness=-12, RootingDepth=-5, SeepageDepth=-3, RootRestrictingDepth=-2
  for (const [col, raw] of [
    ['HumusThickness', '-12'],
    ['RootingDepth', '-5'],
    ['SeepageDepth', '-3'],
    ['RootRestrictingDepth', '-2'],
  ]) {
    const field = ordinary.ordinaryField(col);
    const parsed = ordinary.ordinaryNumberValue(field, raw, null);
    assert.match(parsed.error, />= 0 cm/, col);
  }

  // Legacy plot 8229723: unchanged SeepageDepth = -60 allows saving unrelated RootingDepth = 45
  const base = Object.fromEntries(ordinary.ordinaryFields.map(f => [f.key, null]));
  const orig = { ...base, seepageDepth: -60, rootingDepth: 30 };
  const next = { ...orig, rootingDepth: 45 };
  assert.equal(ordinary.ordinaryValidation('soils', next, orig, {}), null);

  // Changing SeepageDepth from -60 to -3 is rejected
  const mutatedLegacy = { ...orig, seepageDepth: -3 };
  assert.match(ordinary.ordinaryValidation('soils', mutatedLegacy, orig, {}), />= 0 cm/);

  // SIVI: SV_PercentCoarseFrags=150 and SV_SoilDepth=-5 rejected on edit, tolerated when unchanged
  const rev = siviOriginal();
  assert.match(
    siviEditor.stageSIVIParent(rev, {}, 'SV_PercentCoarseFrags', { kind: 'text', raw: '150' }).SV_PercentCoarseFrags.error,
    /0% and 100%/,
  );
  assert.match(
    siviEditor.stageSIVIParent(rev, {}, 'SV_SoilDepth', { kind: 'text', raw: '-5' }).SV_SoilDepth.error,
    />= 0 cm/,
  );

  const legacyRev = siviOriginal();
  setCell(legacyRev, 'SV_SoilDepth', { storage: 'real', text: null, integer: null, real: -5, blobHex: null });
  let siviDrafts = siviEditor.stageSIVIParent(legacyRev, {}, 'SV_SoilDepth', { kind: 'original' });
  siviDrafts = siviEditor.stageSIVIParent(legacyRev, siviDrafts, 'SV_PolygonNumber', { kind: 'text', raw: 'POLY-1' });
  const siviProp = siviEditor.siviParentProposal(legacyRev, siviDrafts);
  assert.equal(siviProp.scalars.length, 0);
  assert.equal(siviProp.text.length, 1);

  // FS882Form.svelte wires mineralList into both soilErrors(soilDrafts, mineralList) and soilUpdates(soilDrafts, mineralList)
  const fs = require('node:fs');
  const path = require('node:path');
  const fs882Src = fs.readFileSync(path.join(__dirname, '..', 'src', 'entry', 'FS882Form.svelte'), 'utf8');
  assert.match(fs882Src, /soilErrors\(soilDrafts,\s*mineralList\)/);
  assert.match(fs882Src, /soilUpdates\(soilDrafts,\s*mineralList\)/);
  let partialDraft = {};
  partialDraft = soil.stageSoil(partialDraft, 'Mineral', 42, soil.soilField('Mineral', 'PercentCoarseFragsCobbles'), '60', null);
  assert.throws(
    () => soil.soilUpdates(partialDraft, [{ id: 42, percentCoarseFragsGravel: 60 }]),
    /120%.*cannot exceed 100%/,
  );
});
