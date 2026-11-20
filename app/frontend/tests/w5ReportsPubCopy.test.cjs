const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const { compile } = require('svelte/compiler');
const { render } = require('svelte/server');
const {
  componentFunctions,
  loadTypeScript,
  serverComponent,
  srcPath,
} = require('./svelteTestHelpers.cjs');
const { readJsonFixture } = require('./fixtureLoader.cjs');

const REPO_ROOT = path.resolve(__dirname, '..', '..', '..');
const { PublicationSession } = loadTypeScript('shared/publicationSession.ts');
const lifeform = loadTypeScript('lifeformSummary.ts');
const attributes = loadTypeScript('speciesAttributeSummary.ts', { './lifeformSummary': lifeform });
const quality = loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });
const environmentWorkbook = loadTypeScript('environmentWorkbook.ts', {
  './lifeformSummary': lifeform,
  './longEnvironmentReport': {},
  './publicationSession': { PublicationSession },
});
const matrixMod = loadTypeScript('subzoneMatrixReport.ts', {
  './lifeformSummary': lifeform,
  './qualityEditor': quality,
  './environmentWorkbook': environmentWorkbook,
  './publicationSession': { PublicationSession },
});
const lifeformWorkbookMod = loadTypeScript('lifeformWorkbook.ts', {
  './lifeformSummary': lifeform,
  './speciesAttributeSummary': attributes,
  './environmentWorkbook': environmentWorkbook,
  './publicationSession': { PublicationSession },
});

const OWNED_SVELTE_FILES = [
  'interchange/PlotLabelPreview.svelte',
  'interchange/PlotLabelFieldDetails.svelte',
  'reports/LifeformSummary.svelte',
  'reports/LifeformWorkbookPanel.svelte',
  'reports/SiteUnitSummary.svelte',
  'reports/SiteUnitSummaryFieldsets.svelte',
  'reports/SiteUnitSummaryActionBar.svelte',
  'reports/SiteUnitSummaryResults.svelte',
  'reports/SubzoneMatrixReport.svelte',
  'reports/SummaryVegetationReport.svelte',
  'reports/SummaryVegetationOptionsBar.svelte',
  'reports/SummaryVegetationPeerPanels.svelte',
  'reports/SummaryVegetationFieldListSection.svelte',
  'reports/SummaryVegetationResultPanel.svelte',
];

test('UX-REPORTS-008: PublicationSession unblocks immediately on clean published outcome and retains barrier on errors/unknowns', async () => {
  const validate = value => {
    if (!value || typeof value.status !== 'string' || typeof value.errorMessage !== 'string') {
      throw new Error('invalid outcome');
    }
    return value;
  };

  // 1. Clean 'published' -> busy transitions true -> false, blocked clears to false immediately
  const cleanSession = new PublicationSession('Test workbook');
  const states = [];
  cleanSession.subscribe(() => states.push(cleanSession.view()));
  let resolveClean;
  const inflight = cleanSession.publish(
    { id: 1 },
    '/tmp/out-1.xlsx',
    () => new Promise(done => { resolveClean = done; }),
    validate,
  );
  assert.equal(cleanSession.view().busy, true);
  assert.equal(cleanSession.view().blocked, true);
  resolveClean({ status: 'published', path: '/tmp/out-1.xlsx', errorMessage: '' });
  await inflight;

  const afterClean = cleanSession.view();
  assert.equal(afterClean.busy, false);
  assert.equal(afterClean.blocked, false, 'clean published export must clear blocked immediately');
  assert.equal(afterClean.outcome.status, 'published');
  assert.equal(afterClean.error, '');
  assert.ok(states.some(s => s.busy === true && s.blocked === true));
  assert.equal(states.at(-1).blocked, false);

  // Can immediately publish a second workbook without clicking Acknowledge
  await cleanSession.publish(
    { id: 2 },
    '/tmp/out-2.xlsx',
    async () => ({ status: 'published', path: '/tmp/out-2.xlsx', errorMessage: '' }),
    validate,
  );
  assert.equal(cleanSession.view().blocked, false);
  assert.equal(cleanSession.view().outcome.path, '/tmp/out-2.xlsx');

  // 2. Unknown transport exception -> stays blocked until acknowledged
  const unknownSession = new PublicationSession('Test workbook');
  await unknownSession.publish(
    { id: 3 },
    '/tmp/unknown.xlsx',
    async () => { throw new Error('IPC socket closed'); },
    validate,
  );
  assert.equal(unknownSession.view().busy, false);
  assert.equal(unknownSession.view().blocked, true, 'unknown transport exception must keep blocked=true');
  assert.equal(unknownSession.view().outcome, null);
  assert.match(unknownSession.view().error, /outcome unknown.*IPC socket closed/);
  await assert.rejects(
    unknownSession.publish({ id: 4 }, '/tmp/retry.xlsx', async () => null, validate),
    /Acknowledge/,
  );
  unknownSession.acknowledge();
  assert.equal(unknownSession.view().blocked, false);

  // 3. Explicit non-published or published-with-errors -> stays blocked until acknowledged
  for (const status of ['not-published', 'published-with-errors']) {
    const failedSession = new PublicationSession('Test workbook');
    await failedSession.publish(
      { id: 5 },
      '/tmp/fail.xlsx',
      async () => ({ status, path: '', errorMessage: `${status} error` }),
      validate,
    );
    assert.equal(failedSession.view().blocked, true, `${status} must keep blocked=true until acknowledged`);
    failedSession.acknowledge();
    assert.equal(failedSession.view().blocked, false);
  }
});

test('UX-REPORTS-008: SubzoneMatrixReport and LifeformWorkbookPanel release onBusyChange(false) after clean XLSX export', async () => {
  const matrixWire = readJsonFixture('subzoneMatrixWire.json');
  const matrixOwner = {
    contextId: 'matrix-context',
    hierarchy: 'Sample',
    hierarchyPath: 'C:\\fixture\\hierarchy.db',
  };
  const matrixDest = 'C:\\fixture\\matrix.xlsx';
  const matrixSession = new matrixMod.MatrixPublicationSession(matrixOwner);
  const busyChanges = [];

  const ctx = componentFunctions(
    'SubzoneMatrixReport.svelte',
    ['reportBusy', 'cancel', 'reviewWorkbook', 'publishWorkbook', 'acknowledge'],
    {
      ...matrixOwner,
      owner: matrixOwner,
      session: matrixSession,
      publication: matrixSession.view(),
      preview: null,
      workbook: null,
      busy: false,
      barrier: false,
      available: true,
      error: '',
      destination: matrixDest,
      generation: 0,
      limit: 25,
      reads: { track: v => v, cancelAll() {} },
      matrixWorkbookFromWire: matrixMod.matrixWorkbookFromWire,
      sameMatrixSource: matrixMod.sameMatrixSource,
      onBusyChange: held => busyChanges.push(held),
      EnvironmentReportService: {
        GetSubzoneMatrixReview: async () => structuredClone(matrixWire.review),
        ExportReviewedSubzoneMatrix: async () => structuredClone(matrixWire.published),
      },
    },
  );
  matrixSession.subscribe(() => {
    ctx.publication = matrixSession.view();
    ctx.barrier = ctx.publication.busy || ctx.publication.blocked;
    if (ctx.publication.busy) ctx.workbook = null;
    ctx.actions.reportBusy();
  });

  await ctx.actions.reviewWorkbook();
  assert.ok(ctx.workbook);
  assert.equal(busyChanges.at(-1), false);

  await ctx.actions.publishWorkbook();
  assert.equal(ctx.publication.outcome.status, 'published');
  assert.equal(ctx.publication.blocked, false);
  assert.equal(ctx.workbook, null, 'consumed workbook review clears on publish');
  assert.equal(busyChanges.at(-1), false, 'onBusyChange(false) must fire immediately after clean export');

  // SSR after clean 'published' must NOT render [data-matrix-acknowledge], whereas unknown transport MUST render it
  const matrixSource = readFileSync(srcPath('SubzoneMatrixReport.svelte'), 'utf8');
  const CleanMatrix = serverComponent(matrixSource, 'SubzoneMatrixReport.svelte', {
    '../bindings/github.com/boostao/vpro/app': { EnvironmentReportService: {} },
    './subzoneMatrixReport': { ...matrixMod, matrixPublicationSession: () => matrixSession },
  });
  const cleanHtml = render(CleanMatrix, { props: { ...matrixOwner, onBusyChange() {} } }).body;
  assert.doesNotMatch(cleanHtml, /data-matrix-acknowledge/);

  const unknownMatrixSession = new matrixMod.MatrixPublicationSession(matrixOwner);
  await unknownMatrixSession.publish(matrixWire.review, matrixDest, async () => {
    throw new Error('disk RPC timeout');
  });
  assert.equal(unknownMatrixSession.view().blocked, true);
  const UnknownMatrix = serverComponent(matrixSource, 'SubzoneMatrixReport.svelte', {
    '../bindings/github.com/boostao/vpro/app': { EnvironmentReportService: {} },
    './subzoneMatrixReport': { ...matrixMod, matrixPublicationSession: () => unknownMatrixSession },
  });
  const unknownHtml = render(UnknownMatrix, { props: { ...matrixOwner, onBusyChange() {} } }).body;
  assert.match(unknownHtml, /data-matrix-acknowledge/);
  assert.match(unknownHtml, /data-matrix-unknown/);

  // LifeformWorkbookPanel SSR after clean 'published' also renders unblocked with zero acknowledge button
  const lfSession = {
    view: () => ({
      busy: false,
      blocked: false,
      requestedDestination: 'C:\\fixture\\lifeform.xlsx',
      outcome: {
        status: 'published',
        requestedDestination: 'C:\\fixture\\lifeform.xlsx',
        path: 'C:\\fixture\\lifeform.xlsx',
        sha256: 'b'.repeat(64),
        errorMessage: '',
      },
      error: '',
    }),
    subscribe(fn) { fn(); return () => {}; },
  };
  let lfHeld = true;
  const LfPanel = serverComponent(
    readFileSync(srcPath('LifeformWorkbookPanel.svelte'), 'utf8').replace('structuredClone(owner)', '({ ...owner })'),
    'LifeformWorkbookPanel.svelte',
    {
      '../bindings/github.com/boostao/vpro/app': { VegetationReportService: {} },
      './lifeformSummary': lifeform,
      './speciesAttributeSummary': attributes,
      './lifeformWorkbook': { ...lifeformWorkbookMod, lifeformWorkbookPublicationSession: () => lfSession },
    },
  );
  const lfHtml = render(LfPanel, {
    props: {
      owner: { contextId: 'lf', project: 'Sample', projectPath: 'C:\\p.db', su: 'Sample', suPath: 'C:\\p.db' },
      disabled: false,
      onBusyChange: held => { lfHeld = held; },
    },
  }).body;
  assert.equal(lfHeld, false);
  assert.doesNotMatch(lfHtml, /data-lifeform-workbook-acknowledge/);
});

test('UX-REPORTS-009: config.init.yml spells Long Environment Report and removes unused rExportUnits/rVegBy', () => {
  for (const rel of ['app/resources/config.init.yml', 'r/inst/config.init.yml']) {
    const content = readFileSync(path.join(REPO_ROOT, rel), 'utf8');
    assert.match(content, /LEReportTitle:\s*"Long Environment Report"/, `${rel} must spell Long Environment Report`);
    assert.doesNotMatch(content, /Long Evironment Report/, `${rel} must not contain Evironment typo`);
    assert.doesNotMatch(content, /\brExportUnits\b/, `${rel} must not contain unused rExportUnits`);
    assert.doesNotMatch(content, /\brVegBy\b/, `${rel} must not contain unused rVegBy`);
  }
});

test('UX-REPORTS-009 + W5 hygiene: report and label components use plain CBC copy and pass all W5 structural/lint gates', () => {
  const bannedJargon = [
    /five reviewed YAML preferences/i,
    /exact owned VPro64 source path/i,
    /Original Access Load\/View Report setters/i,
    /criteria type mismatch/i,
    /explicitly Load valid reviewed presentation authority/i,
    /SiteDisturbance2 binding/i,
    /Technical ASCII-key ordering/i,
    /BecLabels rows/i,
    /Owned VPro64 labels database/i,
  ];

  for (const rel of OWNED_SVELTE_FILES) {
    const source = readFileSync(srcPath(rel), 'utf8');
    const lines = source.split('\n');
    assert.ok(lines.length <= 560, `${rel} has ${lines.length} lines (expected <= 560)`);
    for (let i = 0; i < lines.length; i++) {
      assert.ok(lines[i].length <= 280, `${rel}:${i + 1} length ${lines[i].length} exceeds 280 chars`);
    }
    assert.doesNotMatch(source, /[A-Za-z]+Enabled(?:\s*:\s*boolean)?\s*=\s*true/, `${rel} has *Enabled = true`);
    assert.doesNotMatch(source, /typeof notifications/, `${rel} has typeof notifications guard`);
    assert.doesNotMatch(source, /: any\b|as any\b|<any>|as unknown as/, `${rel} has type escape`);
    assert.equal(/\p{Extended_Pictographic}/u.test(source), false, `${rel} contains emoji`);
    for (const pattern of bannedJargon) {
      assert.doesNotMatch(source, pattern, `${rel} contains developer jargon ${pattern}`);
    }
    assert.equal(compile(source, { filename: srcPath(rel), generate: 'client' }).warnings.length, 0);
    assert.equal(compile(source, { filename: srcPath(rel), generate: 'server' }).warnings.length, 0);
  }
});
