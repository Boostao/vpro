const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const { webcrypto, createHash } = require('node:crypto');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const { render } = require('svelte/server');
const { loadTypeScript, componentFunctions, serverComponent, srcPath } = require('./svelteTestHelpers.cjs');

const quality = loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });
const lookup = loadTypeScript('scopedPlotLookup.ts', { './qualityEditor': quality });
const labels = loadTypeScript('plotLabelPreview.ts', { './qualityEditor': quality, './scopedPlotLookup': lookup });
const regional = loadTypeScript('plotLabelRegional.ts', { './qualityEditor': quality, './plotLabelPreview': labels });
const cells = loadTypeScript('projectMetadataRestore.ts', { './qualityEditor': quality, './projectMetadataEditor': {} });
const locations = loadTypeScript('plotLocationReview.ts', { './projectMetadataRestore': cells });
const earth = loadTypeScript('googleEarthReview.ts', {
  './projectMetadataRestore': cells, './qualityEditor': quality, './plotLocationReview': locations,
});
const pdf = loadTypeScript('plotLabelPDFExport.ts', {
  './qualityEditor': quality, './googleEarthReview': earth, './plotLabelRegional': regional,
  './publicationSession': loadTypeScript('publicationSession.ts'),
}, { crypto: webcrypto });

const SAMPLE_DB_PATH = path.resolve(__dirname, '../../resources/Sample.db');
const SAMPLE_SQL = `SELECT e.PlotNumber AS plotNumber, e.Zone AS zone, e.SubZone AS subZone,
  e.SiteSeries AS siteSeries, e.PlotRepresenting AS plotRepresenting, e.ProjectID AS projectId
  FROM Sample_Env e INNER JOIN Sample_Admin a
  ON typeof(a.Plot)='text' AND CAST(a.Plot AS BLOB)=CAST(e.PlotNumber AS BLOB)
  WHERE typeof(e.PlotNumber)='text'
  ORDER BY e.PlotNumber COLLATE BINARY`;

function readSampleDbHeaders() {
  try {
    const out = execFileSync('sqlite3', ['-json', SAMPLE_DB_PATH, SAMPLE_SQL], { encoding: 'utf8' });
    return JSON.parse(out);
  } catch {
    const { DatabaseSync } = require('node:sqlite');
    const db = new DatabaseSync(SAMPLE_DB_PATH, { open: true, readOnly: true });
    try {
      return db.prepare(SAMPLE_SQL).all().map(row => ({
        plotNumber: row.plotNumber,
        zone: row.zone,
        subZone: row.subZone,
        siteSeries: row.siteSeries,
        plotRepresenting: row.plotRepresenting,
        projectId: row.projectId,
      }));
    } finally {
      db.close();
    }
  }
}

const hexHash = seed => createHash('sha256').update(seed, 'utf8').digest('hex');

const SCOPE = {
  contextId: 'sample-label-ctx',
  project: 'Sample',
  projectPath: '/workspace/projects/Sample.db',
  su: 'Sample',
  suPath: '/workspace/projects/Sample.db',
};

function makeReview(header) {
  const approvalHash = hexHash(`approval:${JSON.stringify(header)}`);
  const pdfSHA256 = hexHash(`pdf:${JSON.stringify(header)}`);
  return {
    preview: {
      contextId: SCOPE.contextId,
      plotNumber: header.plotNumber,
      header: {
        plotNumber: header.plotNumber,
        zone: header.zone,
        subZone: header.subZone,
        siteSeries: header.siteSeries,
        plotRepresenting: header.plotRepresenting,
        projectId: header.projectId,
      },
      labelDate: 'Monday, October 12, 2026',
      isoDate: '2026-10-12',
      locale: 'en-US',
      pattern: 'dddd, MMMM d, yyyy',
      source: 'windows-user-long-date',
    },
    project: SCOPE.project,
    projectPath: SCOPE.projectPath,
    su: SCOPE.su,
    suPath: SCOPE.suPath,
    approvalHash,
    pdfSHA256,
    layout: 'portable-letter-single-fixed-ascii-v1',
    sessionId: 'SAMPLE_PDF_SESSION',
  };
}

function createHost(headersByPlot, extraService = {}, extraValues = {}) {
  const target = new pdf.PlotLabelPDFPublicationSession(SCOPE);
  const exported = [];
  const context = componentFunctions('PlotLabelPreview.svelte',
    ['cancel', 'load', 'updateBusy', 'publishPDF', 'recoverPDF', 'acknowledgePDF'], {
      ...SCOPE,
      plot: '',
      ownerKey: 'sample-owner',
      pdfEnabled: true,
      regionalDateEnabled: true,
      pdfSession: target,
      pdfReview: null,
      preview: null,
      regionalEvidence: null,
      labelDate: '',
      busy: false,
      generation: 0,
      error: '',
      destination: '/tmp/out.pdf',
      publication: target.view(),
      validatePlotLabelPDFReview: pdf.validatePlotLabelPDFReview,
      validatePlotLabelRegionalPreview: regional.validatePlotLabelRegionalPreview,
      plotLookupInputError: lookup.plotLookupInputError,
      onBusyChange() {},
      reads: { track(v) { return v; }, cancelAll() {} },
      ImportExportService: {
        GetPlotLabelPDFReview(_ctxId, rawJson) {
          const { plotNumber } = JSON.parse(rawJson);
          const h = headersByPlot.get(plotNumber);
          if (!h) return Promise.reject(new Error(`missing plot ${plotNumber}`));
          return Promise.resolve(makeReview(h));
        },
        ExportReviewedPlotLabelPDF(_ctxId, rawJson) {
          const req = JSON.parse(rawJson);
          const h = headersByPlot.get(req.plotNumber);
          const rev = makeReview(h);
          exported.push(req);
          return Promise.resolve({
            status: 'published',
            requestedDestination: req.destination,
            path: req.destination,
            sha256: rev.pdfSHA256,
            errorMessage: '',
          });
        },
        RecoverPlotLabelPDFOutcome() {
          throw new Error('unexpected recover');
        },
        GetPlotLabelRegionalPreview(_ctxId, plotNumber) {
          const h = headersByPlot.get(plotNumber);
          if (!h) return Promise.reject(new Error(`missing plot ${plotNumber}`));
          return Promise.resolve(makeReview(h).preview);
        },
        ...extraService,
      },
      ContextService: { GetPlot() { throw new Error('unexpected legacy GetPlot'); } },
      ...extraValues,
    });
  target.subscribe(() => { context.publication = target.view(); context.actions.updateBusy(); });
  return { context, target, exported };
}

test('UX-REPORTS-006: all Sample.db plots (including 232-char 8529676) succeed in PlotLabelPreview load and PDF export', async () => {
  const rows = readSampleDbHeaders();
  assert.ok(rows.length >= 51, `expected >= 51 Sample.db plots, got ${rows.length}`);
  const headersByPlot = new Map(rows.map(r => [r.plotNumber, r]));
  assert.equal(headersByPlot.get('8529676')?.plotRepresenting?.length, 232);

  const { context, exported } = createHost(headersByPlot);
  let over80 = 0;

  for (const row of rows) {
    if ((row.plotRepresenting ?? '').length > 80) over80++;
    context.plot = row.plotNumber;
    context.destination = `/tmp/sample-${row.plotNumber.trim()}.pdf`;
    await context.actions.load();

    assert.equal(context.error, '', `plot ${row.plotNumber} errored: ${context.error}`);
    assert.ok(context.preview, `plot ${row.plotNumber} missing preview`);
    assert.ok(context.pdfReview, `plot ${row.plotNumber} missing pdfReview`);
    assert.equal(context.preview.plotNumber1, row.plotNumber);
    assert.equal(context.preview.representing1, row.plotRepresenting);

    await context.actions.publishPDF();
    assert.equal(context.publication.outcome?.status, 'published', `plot ${row.plotNumber} failed publishPDF`);
    context.actions.acknowledgePDF();
    assert.equal(context.publication.blocked, false);
  }

  assert.ok(over80 >= 5, `expected >= 5 Sample.db plots over 80 chars, saw ${over80}`);
  assert.equal(exported.length, rows.length);
});

test('UX-REPORTS-006: 255-char PlotRepresenting and full Unicode (accents, em-dash, degree, plus-minus, CJK, emoji) preserve exact UTF-8 in HTML preview and export cleanly', async () => {
  const rep255 = ('Picea engelmannii x glauca - Populus balsamifera - Alnus incana - Equisetum arvense - ' +
    'Linnaea borealis - Mertensia paniculata - Epilobium angustifolium - Leymus innovatus - ' +
    'Platanthera obtusata - Orthilia secunda - Pyrola chlorantha - Hylocomium splendens').slice(0, 255);
  assert.equal(rep255.length, 255);

  const unicodeCases = [
    {
      plotNumber: 'U255CH',
      zone: 'BWBS',
      subZone: 'wk2',
      siteSeries: '06',
      projectId: 'PRJ-'.repeat(12) + 'XY',
      plotRepresenting: rep255,
    },
    {
      plotNumber: 'U255WW',
      zone: 'CWH',
      subZone: 'vm1',
      siteSeries: 'W'.repeat(40),
      projectId: 'W'.repeat(50),
      plotRepresenting: 'W'.repeat(255),
    },
    {
      plotNumber: 'UUNICO',
      zone: 'ICH',
      subZone: 'mw2',
      siteSeries: '01',
      projectId: 'Québec — 12° ± 1° 🌲',
      plotRepresenting: 'Forêt boréale — Slope 18° ± 2° · Betula platyphylla (白樺 / 森林) · Tsuga 🌲 test\nSecond line',
    },
    {
      plotNumber: 'UEMOJI',
      zone: 'ESSF',
      subZone: 'wc4',
      siteSeries: '01',
      projectId: '🌲😀🌲',
      plotRepresenting: '🌲'.repeat(127) + 'x', // 255 UTF-16 code units
    },
  ];

  const headersByPlot = new Map(unicodeCases.map(c => [c.plotNumber, c]));
  const { context, exported } = createHost(headersByPlot);

  for (const tc of unicodeCases) {
    context.plot = tc.plotNumber;
    context.destination = `/tmp/${tc.plotNumber}.pdf`;
    await context.actions.load();

    assert.equal(context.error, '');
    assert.ok(context.preview);
    assert.ok(context.pdfReview);
    // Exact full UTF-8 preserved for on-screen HTML card
    assert.equal(context.preview.representing1, tc.plotRepresenting);
    assert.equal(context.preview.displayRepresenting, tc.plotRepresenting.trim());
    assert.equal(context.preview.projectId1, tc.projectId);

    await context.actions.publishPDF();
    assert.equal(context.publication.outcome?.status, 'published');
    context.actions.acknowledgePDF();
  }
  assert.equal(exported.length, unicodeCases.length);

  // Verify PlotLabelPreview.svelte wrapping CSS and guidance
  const svelteSource = readFileSync(srcPath('PlotLabelPreview.svelte'), 'utf8');
  assert.match(svelteSource, /data-plot-label-representing/);
  assert.match(svelteSource, /wrapped UTF-8 plot labels up to full 255-character descriptions/);
  assert.match(svelteSource, /overflow-wrap:\s*break-word/);

  const component = serverComponent(svelteSource, 'PlotLabelPreview.svelte', {
    '../bindings/github.com/boostao/vpro/app': {},
    './scopedPlotLookup': lookup,
    './plotLabelPreview': labels,
    './plotLabelRegional': regional,
    './plotLabelPDFExport': pdf,
  });
  const html = render(component, { props: { ...SCOPE, initialPlot: '8529676', onBusyChange() {} } }).body;
  assert.match(html, /value="8529676"/);
  assert.match(html, /wrapped UTF-8 plot labels up to full 255-character descriptions/);
});

test('UX-REPORTS-006: host PDF font/encoding failure falls back to regional on-screen preview without blocking HTML card', async () => {
  const { createNotificationController } = loadTypeScript('shell/notificationService.svelte.ts', {
    'svelte/store': require('svelte/store'),
  });
  const notifications = createNotificationController({ schedule: () => 0, cancelSchedule: () => {} });
  const headersByPlot = new Map([
    ['8529676', {
      plotNumber: '8529676',
      zone: 'BWBS',
      subZone: 'wk2',
      siteSeries: '06',
      projectId: 'BEC',
      plotRepresenting: 'Picea engelmannii x glauca — Tsuga 🌲 test',
    }],
  ]);

  const { context } = createHost(headersByPlot, {
    GetPlotLabelPDFReview() {
      return Promise.reject(new Error('runtime label font ArialMT open: file does not exist'));
    },
  }, { notifications });

  context.plot = '8529676';
  await context.actions.load();

  // On-screen HTML preview succeeds with full UTF-8 while pdfReview stays null
  assert.ok(context.preview);
  assert.equal(context.preview.displayRepresenting, 'Picea engelmannii x glauca — Tsuga 🌲 test');
  assert.equal(context.labelDate, 'Monday, October 12, 2026');
  assert.equal(context.pdfReview, null);
  assert.match(context.error, /On-screen plot label preview is ready, but portable PDF export is unavailable/);

  const entries = notifications.getSnapshot().entries;
  assert.equal(entries.length, 1);
  assert.equal(entries[0].severity, 'warning');
  assert.equal(entries[0].category, 'reports');
  assert.equal(entries[0].source, 'Plot Labels');
});
