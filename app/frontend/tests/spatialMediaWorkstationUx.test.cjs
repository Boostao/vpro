const assert = require('node:assert/strict');
const { webcrypto } = require('node:crypto');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { compile } = require('svelte/compiler');
const { render } = require('svelte/server');
const { componentFunctions, loadTypeScript, serverComponent, srcPath } = require('./svelteTestHelpers.cjs');
const { readJsonFixture } = require('./fixtureLoader.cjs');

const MODIFIED_COMPONENTS = [
  'spatial/GeospatialWorkbench.svelte',
  'spatial/GoogleEarthReview.svelte',
  'spatial/PlotLocationReview.svelte',
  'pictures/PictureManager.svelte',
  'pictures/PictureCreationPanel.svelte',
  'pictures/PictureLifecyclePanel.svelte',
  'pictures/PictureMetadataEditor.svelte',
  'interchange/ProjectTableCSVReview.svelte',
  'interchange/PlotLabelPreview.svelte',
];

const STICKY_BAR_COMPONENTS = [
  'spatial/GoogleEarthReview.svelte',
  'spatial/PlotLocationReview.svelte',
  'pictures/PictureManager.svelte',
  'interchange/ProjectTableCSVReview.svelte',
  'interchange/PlotLabelPreview.svelte',
];

function makeNotifications() {
  const { createNotificationController } = loadTypeScript('shell/notificationService.svelte.ts', {
    'svelte/store': require('svelte/store'),
  });
  return createNotificationController({ schedule: () => 0, cancelSchedule: () => {} });
}

test('all modified spatial, pictures, and interchange components compile with 0 warnings and zero emojis/green classes', () => {
  const emojiRegex = /\p{Extended_Pictographic}/u;
  const legacyGreenHex = /#(173f38|2c5b4a|d7ad51|b7cfc0|365c48|d1dcd4|176149|174f38|268453|e9efeb|e6f0e8|d2e4d7|dbe8dd|eaf0e9|f0f6ee|e4eee9|526e62|456050|20322d|bd9b48|b7493c|0f766e|ccfbf1|065f46|047857|ecfdf5|d1fae5|a7f3d0|6ee7b7|34d399|10b981|059669|064e3b)\b/i;
  const legacyGreenUtil = /\b(?:bg|text|border|ring|outline)-(?:emerald|teal|green)-\d{2,3}\b/i;

  for (const rel of MODIFIED_COMPONENTS) {
    const source = readFileSync(srcPath(rel), 'utf8');
    const clientCompiled = compile(source, { filename: srcPath(rel), generate: 'client' });
    assert.equal(clientCompiled.warnings.length, 0, `${rel} client warnings: ${JSON.stringify(clientCompiled.warnings)}`);
    const serverCompiled = compile(source, { filename: srcPath(rel), generate: 'server' });
    assert.equal(serverCompiled.warnings.length, 0, `${rel} server warnings: ${JSON.stringify(serverCompiled.warnings)}`);
    assert.equal(emojiRegex.test(source), false, `${rel} must contain zero emojis`);
    assert.equal(legacyGreenHex.test(source), false, `${rel} must contain zero legacy forest-green hexes`);
    assert.equal(legacyGreenUtil.test(source), false, `${rel} must contain zero emerald/teal/green utilities`);
  }
});

test('primary header/action toolbars render data-workbench-sticky-bar and GeospatialWorkbench removes duplicate statusMsg banner', () => {
  const quality = loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });
  const cells = loadTypeScript('projectMetadataRestore.ts', { './qualityEditor': quality, './projectMetadataEditor': {} });
  const locations = loadTypeScript('plotLocationReview.ts', { './projectMetadataRestore': cells });
  const earth = loadTypeScript('googleEarthReview.ts', {
    './projectMetadataRestore': cells, './qualityEditor': quality, './plotLocationReview': locations,
  });
  const lookup = loadTypeScript('scopedPlotLookup.ts', { './qualityEditor': quality });
  const labels = loadTypeScript('plotLabelPreview.ts', { './qualityEditor': quality, './scopedPlotLookup': lookup });
  const regional = loadTypeScript('plotLabelRegional.ts', { './qualityEditor': quality, './plotLabelPreview': labels });
  const pdf = loadTypeScript('plotLabelPDFExport.ts', {
    './qualityEditor': quality, './googleEarthReview': earth, './plotLabelRegional': regional,
    './publicationSession': loadTypeScript('publicationSession.ts'),
  }, { crypto: webcrypto });
  const csv = loadTypeScript('projectTableCSV.ts', { './qualityEditor': quality, './projectMetadataRestore': cells }, {
    crypto: webcrypto, TextEncoder, Uint8Array,
  });
  const archive = loadTypeScript('tableCSVArchiveExport.ts', {
    './qualityEditor': quality, './projectTableCSV': csv,
    '../../bindings/github.com/boostao/vpro/app': { ImportExportService: { ChooseTableCSVArchiveFile: async () => '' } },
  }, { localStorage: undefined });

  const ssrCases = [
    {
      rel: 'spatial/GoogleEarthReview.svelte',
      deps: {
        '../../bindings/github.com/boostao/vpro/app': { SpatialService: {} },
        './googleEarthReview': earth,
        './googleEarthKMLReview': loadTypeScript('googleEarthKMLReview.ts', { './qualityEditor': quality, './googleEarthReview': earth }),
        './googleEarthKMLExport': loadTypeScript('googleEarthKMLExport.ts', {
          './publicationSession': loadTypeScript('publicationSession.ts'),
          './qualityEditor': quality, './googleEarthReview': earth, './googleEarthKMLReview': {},
        }, { crypto: webcrypto, TextEncoder, Uint8Array }),
        './googleEarthPreferences': loadTypeScript('googleEarthPreferences.ts', {
          './qualityEditor': quality, './googleEarthReview': earth, './googleEarthKMLReview': { googleEarthXMLText: () => true },
        }),
        '../reports/longEnvironmentReport': { reportCellText: String },
        '../entry/qualityEditor': quality,
      },
      props: { contextId: 'ctx-earth', project: 'Sample', projectPath: '/tmp/Sample.db', su: 'None', suPath: '', onBusyChange() {} },
    },
    {
      rel: 'spatial/PlotLocationReview.svelte',
      deps: {
        '../../bindings/github.com/boostao/vpro/app': { SpatialService: {} },
        './plotLocationReview': locations,
        '../reports/longEnvironmentReport': { reportCellText: String },
      },
      props: { contextId: 'ctx-loc', project: 'Sample', projectPath: '/tmp/Sample.db', su: 'None', suPath: '', onBusyChange() {} },
    },
    {
      rel: 'pictures/PictureManager.svelte',
      deps: {
        './PicturePanel.svelte': { default: () => {} },
        './scopedPlotLookup': lookup,
        './pictureMetadataSessions': { pictureMetadataSession: () => undefined },
        './pictureCreationSessions': { pictureCreationSession: () => undefined },
        './PictureCreationPanel.svelte': { default: () => {} },
        './pictureLifecycleSessions': { pictureLifecycleSession: () => undefined },
        './PictureLifecyclePanel.svelte': { default: () => {} },
      },
      props: { contextId: 'ctx-pic', project: 'Sample', initialPlot: '00337', onBusyChange() {} },
    },
    {
      rel: 'interchange/ProjectTableCSVReview.svelte',
      deps: {
        '../../bindings/github.com/boostao/vpro/app': {},
        './projectTableCSV': csv,
        '../reports/longEnvironmentReport': { reportCellText: String },
        './tableCSVArchiveExport': archive,
      },
      props: { contextId: 'ctx-csv', project: 'Sample', projectPath: '/tmp/Sample.db', onBusyChange() {} },
    },
    {
      rel: 'interchange/PlotLabelPreview.svelte',
      deps: {
        '../../bindings/github.com/boostao/vpro/app': {},
        './scopedPlotLookup': lookup,
        './plotLabelPreview': labels,
        './plotLabelRegional': regional,
        './plotLabelPDFExport': pdf,
      },
      props: { contextId: 'ctx-lbl', project: 'Sample', projectPath: '/tmp/Sample.db', su: 'None', suPath: '', onBusyChange() {} },
    },
  ];

  for (const item of ssrCases) {
    assert.ok(STICKY_BAR_COMPONENTS.includes(item.rel));
    const source = readFileSync(srcPath(item.rel), 'utf8');
    assert.match(source, /sticky top-0 z-20 bg-white\/95 backdrop-blur-xs py-2 border-b/);
    const comp = serverComponent(source, item.rel, item.deps);
    const html = render(comp, { props: item.props }).body;
    assert.match(html, /data-workbench-sticky-bar/, `${item.rel} must render data-workbench-sticky-bar`);
  }

  const geoSrc = readFileSync(srcPath('spatial/GeospatialWorkbench.svelte'), 'utf8');
  assert.doesNotMatch(geoSrc, /\{#if statusMsg\}/, 'GeospatialWorkbench template must not render duplicate statusMsg banner');
  assert.match(geoSrc, /let statusMsg = \$state\(''\);/, 'GeospatialWorkbench script must keep statusMsg state');
});

test('GeospatialWorkbench routes 3D Map stamp, export, and audit actions to entry notifications', async () => {
  const notifications = makeNotifications();
  const geo = componentFunctions(
    'spatial/GeospatialWorkbench.svelte',
    ['runMutation', 'inspectPlotPin', 'loadBatchAuditQA', 'applyAuto1SpatialStamp', 'exportGeoPackageShortcut'],
    {
      contextId: 'ctx-geo',
      project: 'Sample',
      su: 'None',
      alive: true,
      loading: false,
      mutating: false,
      gpkgExporting: false,
      errorMsg: '',
      statusMsg: '',
      loadGeneration: 0,
      qaGeneration: 0,
      inspectorGeneration: 0,
      activePanel: 'inspector',
      selectedPlot: null,
      selectedSuggestion: null,
      suggestionBusy: false,
      qaReport: null,
      qaSelectedPlots: {},
      gpkgOutcome: null,
      mapInstance: null,
      payload: null,
      notifications,
      setBusyState() {},
      refreshDeckOverlay() {},
      initQASelectedPlots: () => ({}),
      loadWorkbenchData: async () => {},
      SpatialService: {
        SuggestSpatialAttributes: async () => ({ gisBgc: 'SBSmk1' }),
        BatchAuditSpatialQA: async () => ({ rows: [{ plotNumber: '00337' }], bgcMismatchCount: 1, utmDivergenceCount: 0 }),
        ApplySpatialAttributes: async () => ({ updatedPlots: 1, updatedCells: 3, auditRows: 3 }),
      },
      ImportExportService: {
        ExportGeoPackage: async () => ({ featureCount: 12, crs: 'EPSG:3005', srsId: 3005, path: '/tmp/Sample_plots.gpkg' }),
      },
      $state: { snapshot: (v) => structuredClone(v) },
    },
  );

  await geo.actions.inspectPlotPin({ plotNumber: '00337', lat: 53.9, lon: -122.7, fieldBgc: 'ICHvk2' }, true);
  await geo.actions.loadBatchAuditQA();
  await geo.actions.applyAuto1SpatialStamp({
    allScoped: false,
    plotNumbers: ['00337'],
    stampGisBgc: true,
    stampAdminFields: true,
    onlyWhenBlank: true,
    normalizeLongitudeSign: true,
    syncUtmFromLatLon: true,
    syncLatLonFromUTM: false,
  });
  await geo.actions.exportGeoPackageShortcut({
    destinationPath: '/tmp/Sample_plots',
    crs: 'EPSG:3005',
    includeAttributeTables: true,
    includeUnlocatedPlots: false,
  });
  geo.ImportExportService.ExportGeoPackage = async () => { throw new Error('disk full'); };
  await geo.actions.exportGeoPackageShortcut({
    destinationPath: '/tmp/fail.gpkg',
    crs: 'EPSG:3005',
    includeAttributeTables: true,
    includeUnlocatedPlots: false,
  });

  const entries = Array.from(notifications.getSnapshot().entries);
  assert.equal(entries.length, 5);
  assert.ok(entries.every((item) => item.category === 'entry' && item.source === '3D Map' && item.contextTag === 'Sample'));
  assert.deepEqual(
    Array.from(entries, (item) => item.severity),
    ['error', 'success', 'success', 'info', 'info'],
  );
  assert.match(entries[0].message, /disk full/);
  assert.match(entries[1].message, /Sample_plots\.gpkg/);
  assert.match(entries[2].message, /Stamped 1 plot/);
});

test('GoogleEarthReview routes KML export completion and failure to reports notifications', async () => {
  const notifications = makeNotifications();
  const quality = loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });
  const cells = loadTypeScript('projectMetadataRestore.ts', { './qualityEditor': quality, './projectMetadataEditor': {} });
  const locations = loadTypeScript('plotLocationReview.ts', { './projectMetadataRestore': cells });
  const earth = loadTypeScript('googleEarthReview.ts', {
    './projectMetadataRestore': cells, './qualityEditor': quality, './plotLocationReview': locations,
  });
  const { createHash } = require('node:crypto');
  const kmlXml = '<?xml version="1.0" encoding="UTF-8"?>\n<kml xmlns="http://earth.google.com/kml/2.1"><Document><name>Title</name></Document></kml>';
  const sha = createHash('sha256').update(kmlXml).digest('hex');
  const scope = { contextId: 'ctx-kml', project: 'Sample', projectPath: '/tmp/Sample.db', su: 'None', suPath: '' };
  const kmlExport = loadTypeScript('googleEarthKMLExport.ts', {
    './publicationSession': loadTypeScript('publicationSession.ts'),
    './qualityEditor': quality,
    './googleEarthReview': earth,
    './googleEarthKMLReview': { validateGoogleEarthKMLReview: async (v) => structuredClone(v) },
  }, { crypto: webcrypto, TextEncoder, Uint8Array });

  const session = new kmlExport.GoogleEarthKMLPublicationSession(scope);
  const host = componentFunctions('GoogleEarthReview.svelte', ['publishKML'], {
    ...scope,
    locked: false,
    error: '',
    destination: '/tmp/Sample.kml',
    approval: {
      review: { ...scope, descriptionField: 'Zone', title: 'Title', placemarkCount: 0, byteCount: Buffer.byteLength(kmlXml), kml: kmlXml },
      approvalHash: 'a'.repeat(64),
      kmlSHA256: sha,
    },
    publicationSession: session,
    notifications,
    SpatialService: {
      ExportReviewedGoogleEarthKML: async () => ({
        status: 'published',
        requestedDestination: '/tmp/Sample.kml',
        path: '/tmp/Sample.kml',
        sha256: sha,
        errorMessage: '',
      }),
    },
  });

  await host.actions.publishKML();
  session.acknowledge();
  host.SpatialService.ExportReviewedGoogleEarthKML = async () => { throw new Error('permission denied'); };
  await host.actions.publishKML();

  const entries = notifications.getSnapshot().entries;
  assert.equal(entries.length, 2);
  assert.equal(entries[0].severity, 'error');
  assert.equal(entries[1].severity, 'success');
  assert.ok(entries.every((item) => item.category === 'reports' && item.source === 'Google Earth KML' && item.contextTag === 'Sample'));
});

test('Picture panels route attach, delete, restore, and metadata save to entry notifications', async () => {
  const notifications = makeNotifications();
  const reads = loadTypeScript('readRequests.ts', { '@wailsio/runtime': {} });
  const { editor: createEd, picture, owner, selection, receipt, requestId } = require('./pictureCreationTestHelpers.cjs');
  const { editor: lifeEd, fixture: lifeFix, owner: lifeOwner, requestId: lifeReqId, deletion, review: lifeReview, restorationReview, restoration } =
    require('./pictureLifecycleTestHelpers.cjs');
  const { metadata, cell } = require('./siviParentTestHelpers.cjs');
  const metaEd = loadTypeScript('pictureMetadataEditor.ts', {
    '../../resources/picture-metadata-policy.json': require('../../resources/picture-metadata-policy.json'),
    './projectMetadataEditor': metadata,
    './pictureRead': picture,
  });
  const { PictureCreationSession } = loadTypeScript('pictureCreationSession.ts', {
    './readRequests': reads, './pictureRead': picture, './pictureCreationEditor': createEd, './siviRequestId': loadTypeScript('siviRequestId.ts'),
  });
  const { PictureLifecycleSession } = loadTypeScript('pictureLifecycleSession.ts', {
    './pictureLifecycleEditor': lifeEd, './pictureRead': picture, './readRequests': reads,
  });
  const { PictureMetadataSession } = loadTypeScript('pictureMetadataSession.ts', {
    './readRequests': reads, './projectMetadataEditor': metadata, './pictureRead': picture, './pictureMetadataEditor': metaEd,
  });

  const op = (v) => Object.assign(Promise.resolve(v), { cancel() {} });

  // 1. PictureManager plot select
  const mgr = componentFunctions('PictureManager.svelte', ['selectPlot'], {
    busy: false, metadataBlocked: false, creationBlocked: false, lifecycleBlocked: false,
    plot: '00337', selected: '', project: 'Sample', error: '',
    plotLookupInputError: () => null, notifications,
  });
  mgr.actions.selectPlot();

  // 2. PictureCreationPanel attach
  const createSession = new PictureCreationSession(owner, {
    choose: () => op(selection()),
    create: (_t, json) => op(receipt(JSON.parse(json))),
    image: () => op({ ...owner, rowId: '9223372036854775807', mime: 'image/jpeg', width: 100, height: 100, sha256: 'a'.repeat(64), dataUrl: 'data:image/jpeg;base64,YQ==' }),
  });
  const createPanel = componentFunctions('PictureCreationPanel.svelte', ['operate'], {
    session: createSession, disabled: false, error: '', crypto: { randomUUID: () => requestId }, notifications,
  });
  await createPanel.actions.operate('add');

  // 3. PictureLifecyclePanel delete + restore
  let lifeAttempt = 0;
  const lifeSession = new PictureLifecycleSession(lifeOwner, {
    read: () => op(lifeReview()),
    history: () => op({ ...lifeOwner, events: [{ deletion: deletion(), restoration: null }] }),
    review: () => op(restorationReview()),
    delete: (json) => op({ ...deletion(), request: JSON.parse(json) }),
    deletionReceipt: (json) => op({ ...deletion(), request: JSON.parse(json), replayed: true }),
    restore: (json) => op(restoration(JSON.parse(json))),
    restorationReceipt: (json) => op({ ...restoration(JSON.parse(json)), replayed: true }),
  });
  await lifeSession.reviewDeletion('-7');
  lifeSession.confirm(true);
  const lifePanel = componentFunctions('PictureLifecyclePanel.svelte', ['saveLifecycle'], {
    session: lifeSession, view: lifeSession.view(), localError: '',
    crypto: { randomUUID: () => (++lifeAttempt === 1 ? lifeReqId : lifeFix.restorationRequestId) }, notifications,
  });
  await lifePanel.actions.saveLifecycle();
  lifeSession.acknowledge();
  await lifeSession.loadHistory();
  await lifeSession.reviewRestoration('1');
  lifeSession.confirm(true);
  lifePanel.view = lifeSession.view();
  await lifePanel.actions.saveLifecycle();

  // 4. PictureMetadataEditor save
  const metaReview = {
    ...owner,
    records: {
      columns: ['ID', 'PicDir', 'PicName', 'PlotNumber', 'PicComment'].map((name) => ({ name, declaredType: 'TEXT' })),
      rows: [{ rowId: '9223372036854775806', cells: [cell('integer', '1'), cell('text', 'Default'), cell('text', 'Orig.jpg'), cell('text', owner.plotNumber), cell()] }],
    },
  };
  const metaSession = new PictureMetadataSession(owner, {
    read: () => op(metaReview),
    save: (json) => {
      const req = JSON.parse(json);
      const committed = structuredClone(req.original);
      committed.cells[2] = structuredClone(req.changes[0].value);
      return op({
        ...req, ...owner, requestedSource: 'mgr', source: 'mgr',
        ownedFiles: { project: '/tmp/Sample.db' }, actor: 'tester', auditStrength: 3,
        committed, editWhen: '2026-10-12T10:00:00Z', historyId: '55', didCommit: true, replayed: false,
      });
    },
    receipt: () => op(null),
  });
  metaSession.select(metaReview, '9223372036854775806');
  metaSession.stage('PicName', 'Renamed.jpg', false);
  const metaPanel = componentFunctions('PictureMetadataEditor.svelte', ['operation'], {
    session: metaSession, view: metaSession.view(), error: '',
    crypto: { randomUUID: () => requestId }, notifications,
  });
  await metaPanel.actions.operation('save');

  const entries = Array.from(notifications.getSnapshot().entries);
  assert.equal(entries.length, 5);
  assert.ok(entries.every((item) => item.category === 'entry' && item.source === 'Plot Pictures'));
  assert.deepEqual(
    Array.from(entries, (item) => item.title),
    [
      'Picture metadata saved',
      'Picture reference restored',
      'Picture reference deleted',
      'Picture attached',
      'Plot selected for pictures',
    ],
  );
  assert.equal(entries[0].contextTag, `Plot ${owner.plotNumber}`);
  assert.equal(entries[1].contextTag, `Plot ${lifeOwner.plotNumber}`);
  assert.equal(entries[2].contextTag, `Plot ${lifeOwner.plotNumber}`);
  assert.equal(entries[3].contextTag, `Plot ${owner.plotNumber}`);
});

test('ProjectTableCSVReview and PlotLabelPreview route CSV archive and label PDF publications to reports notifications', async () => {
  const notifications = makeNotifications();
  const quality = loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });
  const cells = loadTypeScript('projectMetadataRestore.ts', { './qualityEditor': quality, './projectMetadataEditor': {} });
  const csv = loadTypeScript('projectTableCSV.ts', { './qualityEditor': quality, './projectMetadataRestore': cells }, {
    crypto: webcrypto, TextEncoder, Uint8Array,
  });
  const archiveMod = loadTypeScript('tableCSVArchiveExport.ts', {
    './qualityEditor': quality, './projectTableCSV': csv,
    '../../bindings/github.com/boostao/vpro/app': { ImportExportService: { ChooseTableCSVArchiveFile: async () => '' } },
  }, { localStorage: undefined });

  const { createHash } = require('node:crypto');
  const csvBody = 'Value\n7\n';
  const archiveSha = 'b'.repeat(64);
  const csvOwner = { contextId: 'ctx-csv', project: 'Sample', projectPath: '/tmp/Sample.db' };
  const csvSession = new archiveMod.TableCSVArchivePublicationSession(csvOwner, {
    getItem: () => null,
    setItem() {},
  });
  const csvHost = componentFunctions('ProjectTableCSVReview.svelte', ['publish'], {
    ...csvOwner,
    suffix: 'Env',
    busy: false,
    error: '',
    destination: '/tmp/Sample_Env.zip',
    publicationSession: csvSession,
    publication: csvSession.view(),
    approval: {
      review: {
        ...csvOwner,
        descriptionMetadataPresent: false,
        csv: csvBody,
        manifest: {
          version: 1,
          table: 'Sample_Env',
          columns: [{ name: 'Value', declaredType: 'INTEGER' }],
          rowIds: ['1'],
          storage: [['integer']],
          descriptions: [],
          sha256: createHash('sha256').update(csvBody).digest('hex'),
        },
      },
      approvalHash: 'a'.repeat(64),
      archiveSHA256: archiveSha,
      byteCount: 412,
      format: 'vpro-owned-table-csv',
      version: 1,
    },
    review: null,
    validTableCSVArchiveDestination: archiveMod.validTableCSVArchiveDestination,
    $state: { snapshot: (v) => structuredClone(v) },
    notifications,
    ImportExportService: {
      ExportReviewedTableCSVArchive: async () => ({
        status: 'published',
        requestedDestination: '/tmp/Sample_Env.zip',
        path: '/tmp/Sample_Env.zip',
        sha256: archiveSha,
        errorMessage: '',
      }),
    },
  });
  await csvHost.actions.publish();
  csvSession.acknowledge();
  csvHost.approval = {
    review: csvHost.approval?.review ?? {
      ...csvOwner,
      descriptionMetadataPresent: false,
      csv: csvBody,
      manifest: {
        version: 1,
        table: 'Sample_Env',
        columns: [{ name: 'Value', declaredType: 'INTEGER' }],
        rowIds: ['1'],
        storage: [['integer']],
        descriptions: [],
        sha256: createHash('sha256').update(csvBody).digest('hex'),
      },
    },
    approvalHash: 'a'.repeat(64),
    archiveSHA256: archiveSha,
    byteCount: 412,
    format: 'vpro-owned-table-csv',
    version: 1,
  };
  csvHost.ImportExportService.ExportReviewedTableCSVArchive = async () => { throw new Error('archive disk error'); };
  await csvHost.actions.publish();

  const wire = readJsonFixture('plotLabelPDFWire.json');
  const lookup = loadTypeScript('scopedPlotLookup.ts', { './qualityEditor': quality });
  const labels = loadTypeScript('plotLabelPreview.ts', { './qualityEditor': quality, './scopedPlotLookup': lookup });
  const regional = loadTypeScript('plotLabelRegional.ts', { './qualityEditor': quality, './plotLabelPreview': labels });
  const locations = loadTypeScript('plotLocationReview.ts', { './projectMetadataRestore': cells });
  const earth = loadTypeScript('googleEarthReview.ts', {
    './projectMetadataRestore': cells, './qualityEditor': quality, './plotLocationReview': locations,
  });
  const pdf = loadTypeScript('plotLabelPDFExport.ts', {
    './qualityEditor': quality, './googleEarthReview': earth, './plotLabelRegional': regional,
    './publicationSession': loadTypeScript('publicationSession.ts'),
  }, { crypto: webcrypto });
  const pdfScope = {
    contextId: wire.review.preview.contextId,
    project: wire.review.project,
    projectPath: wire.review.projectPath,
    su: wire.review.su,
    suPath: wire.review.suPath,
  };
  const pdfSession = new pdf.PlotLabelPDFPublicationSession(pdfScope);
  const pdfHost = componentFunctions('PlotLabelPreview.svelte', ['publishPDF'], {
    ...pdfScope,
    busy: false,
    error: '',
    destination: wire.request.destination,
    pdfSession,
    pdfReview: structuredClone(wire.review),
    publication: pdfSession.view(),
    notifications,
    ImportExportService: {
      ExportReviewedPlotLabelPDF: async () => structuredClone(wire.outcome),
    },
  });
  await pdfHost.actions.publishPDF();
  pdfSession.acknowledge();
  pdfHost.ImportExportService.ExportReviewedPlotLabelPDF = async () => ({
    ...structuredClone(wire.outcome),
    status: 'not-published',
    path: '',
    sha256: '',
    errorMessage: 'destination exists',
  });
  await pdfHost.actions.publishPDF();

  const entries = Array.from(notifications.getSnapshot().entries);
  assert.equal(entries.length, 4);
  assert.equal(entries[0].category, 'reports');
  assert.equal(entries[0].source, 'Plot Labels');
  assert.equal(entries[0].severity, 'error');
  assert.match(entries[0].message, /destination exists/);
  assert.equal(entries[1].category, 'reports');
  assert.equal(entries[1].source, 'Plot Labels');
  assert.equal(entries[1].severity, 'success');
  assert.equal(entries[1].contextTag, wire.review.project);
  assert.equal(entries[2].category, 'reports');
  assert.equal(entries[2].source, 'CSV Export');
  assert.equal(entries[2].severity, 'error');
  assert.match(entries[2].message, /archive disk error/);
  assert.equal(entries[3].category, 'reports');
  assert.equal(entries[3].source, 'CSV Export');
  assert.equal(entries[3].severity, 'success');
  assert.equal(entries[3].contextTag, 'Sample');
});
