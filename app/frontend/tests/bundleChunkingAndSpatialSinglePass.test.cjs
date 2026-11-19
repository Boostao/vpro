const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const ts = require('typescript');
const vm = require('node:vm');
const {
  componentFunctions,
  loadTypeScript,
  srcPath,
} = require('./svelteTestHelpers.cjs');

const frontendDir = path.resolve(__dirname, '..');
const resourcesDir = path.resolve(frontendDir, '..', 'resources');

function loadViteCompactHelper() {
  const viteSource = readFileSync(path.join(frontendDir, 'vite.config.ts'), 'utf8');
  const transpiled = ts.transpileModule(viteSource, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
      esModuleInterop: true,
    },
  }).outputText;
  const mod = { exports: {} };
  vm.runInNewContext(transpiled, {
    module: mod,
    exports: mod.exports,
    process,
    require(specifier) {
      if (specifier === 'node:fs' || specifier === 'fs') return require('node:fs');
      if (specifier === 'node:path' || specifier === 'path') return require('node:path');
      if (specifier === 'vite') return { defineConfig: (cfg) => cfg };
      const stub = () => ({});
      return new Proxy(stub, { get: (_target, prop) => (prop === '__esModule' ? true : stub) });
    },
  });
  return mod.exports.compactAccessLayoutJson;
}

test('ENG-FE-008: decoupled fs882FormLayoutBindings and projectMetadataPresentation match packaged Access JSON layouts 100%', () => {
  const bindings = loadTypeScript('entry/fs882FormLayoutBindings.ts');
  const siviRaw = JSON.parse(
    readFileSync(path.join(resourcesDir, 'fs1333-sivi-layout.json'), 'utf8')
  ).forms[0];

  assert.equal(bindings.siviParentLayoutForm.name, siviRaw.name);
  assert.equal(bindings.siviParentLayoutForm.recordSource, siviRaw.recordSource);

  const expectedSiviFields = siviRaw.fields
    .filter(
      (f) =>
        Boolean(f.binding) ||
        f.controlName === 'optPlotType' ||
        f.controlName === 'optSpeciesListComplete' ||
        (f.controlName === 'Label601' && f.type === 'Label')
    )
    .map((f) => {
      const out = { controlId: f.controlId, type: f.type };
      if (f.controlName !== undefined) out.controlName = f.controlName;
      if (f.binding !== undefined) out.binding = f.binding;
      if (f.caption !== undefined) out.caption = f.caption;
      if (f.pageId !== undefined) out.pageId = f.pageId;
      if (f.readOnly !== undefined) out.readOnly = f.readOnly;
      if (f.implementation !== undefined) out.implementation = f.implementation;
      return out;
    });
  assert.deepEqual(
    JSON.parse(JSON.stringify(bindings.siviParentLayoutForm.fields)),
    expectedSiviFields
  );

  const xlRaw = JSON.parse(
    readFileSync(path.join(resourcesDir, 'fs882-xl-layout.json'), 'utf8')
  );
  const xlRoot = xlRaw.forms.find((f) => f.name === xlRaw.root);
  const expectedXlCols = [
    ...new Set(xlRoot.fields.flatMap((f) => (f.binding ? [f.binding] : []))),
  ];
  assert.deepEqual([...bindings.fs882XlBoundColumns], expectedXlCols);

  const metaLayout = JSON.parse(
    readFileSync(path.join(resourcesDir, 'project-metadata-layout.json'), 'utf8')
  );
  const metaForm = metaLayout.forms.find((f) => f.name === 'frmProjectMetaData');
  const presentation = loadTypeScript('admin/projectMetadataPresentation.ts');

  const allGroupNames = [
    'ProjectID',
    'DateLastEdited',
    'AllSpecs',
    'TableOfLists',
    ...presentation.metadataGroups.flatMap((g) => g.names),
  ];
  for (const colName of allGroupNames) {
    const label = presentation.metadataLabel(colName);
    assert.equal(typeof label, 'string');
    assert.ok(label.length > 0, `Empty metadataLabel for ${colName}`);
  }
  for (const field of metaForm.fields) {
    if (!field.column) continue;
    const matches = metaForm.fields.filter(
      (candidate) => candidate.column?.toLowerCase() === field.column.toLowerCase()
    );
    if (matches.length === 1 && matches[0].caption) {
      const label = presentation.metadataLabel(field.column);
      assert.equal(
        label,
        field.column.startsWith('Cover')
          ? `${matches[0].caption} layer description`
          : matches[0].caption
      );
    }
  }
  for (const invalidName of ['UnknownMetadataColumn', 'toString', 'constructor']) {
    assert.throws(
      () => presentation.metadataLabel(invalidName),
      /no unambiguous source\/associated label/
    );
  }
});

test('ENG-FE-008: Vite compactAccessLayoutJson shrinks 3.8 MB layout JSONs by >65% with 100% lossless runtime equivalence', () => {
  const compactAccessLayoutJson = loadViteCompactHelper();
  const extendedShrub = JSON.parse(
    readFileSync(path.join(resourcesDir, 'fs882-extended-shrub-layout.json'), 'utf8')
  );

  const rawByFile = {};
  const compactedByFile = {};
  let rawTotal = 0;
  let compactedTotal = 0;

  for (const fileName of [
    'fs882-xl-layout.json',
    'fs882-two-page-layout.json',
    'fs882-two-page-chars-layout.json',
    'fs1333-sivi-layout.json',
    'project-metadata-layout.json',
  ]) {
    const rawText = readFileSync(path.join(resourcesDir, fileName), 'utf8');
    const compactedText = compactAccessLayoutJson(fileName, rawText);
    rawTotal += Buffer.byteLength(rawText, 'utf8');
    compactedTotal += Buffer.byteLength(compactedText, 'utf8');
    rawByFile[fileName] = JSON.parse(rawText);
    compactedByFile[fileName] = JSON.parse(compactedText);
    assert.ok(
      compactedText.length < rawText.length * 0.5,
      `Expected ${fileName} to shrink by >50%`
    );
  }
  assert.ok(
    compactedTotal < 1_350_000 && compactedTotal < rawTotal * 0.35,
    `Compacted layout JSON total ${compactedTotal} exceeds 1.35 MB / 35% ceiling (raw ${rawTotal})`
  );

  const paperRaw = loadTypeScript('entry/paperLayout.ts', {
    '../../resources/fs882-xl-layout.json': rawByFile['fs882-xl-layout.json'],
    '../../resources/fs882-extended-shrub-layout.json': extendedShrub,
  });
  const paperCompacted = loadTypeScript('entry/paperLayout.ts', {
    '../../resources/fs882-xl-layout.json': compactedByFile['fs882-xl-layout.json'],
    '../../resources/fs882-extended-shrub-layout.json': extendedShrub,
  });

  const plain = (value) => JSON.parse(JSON.stringify(value));
  const normalizePaperControl = (ctrl) => ({
    controlId: ctrl.controlId,
    parentId: ctrl.parentId,
    controlName: ctrl.controlName,
    type: ctrl.type,
    pageId: ctrl.pageId,
    line: ctrl.line,
    column: ctrl.column,
    caption: ctrl.caption,
    x: ctrl.x,
    y: ctrl.y,
    width: ctrl.width,
    height: ctrl.height,
    fontSize: ctrl.fontSize,
    fontName: ctrl.fontName,
    textAlign: ctrl.textAlign,
    bold: ctrl.bold,
    italic: ctrl.italic,
    locked: ctrl.locked,
    enabled: ctrl.enabled,
    tabOrder: ctrl.tabOrder,
    sourceObject: ctrl.properties?.SourceObject?.value ?? null,
  });
  const normalizePage = (page) =>
    plain({
      ...page,
      controls: page.controls.map(normalizePaperControl),
    });
  const normalizeChild = (child) =>
    plain({
      ...child,
      controls: child.controls.map(normalizePaperControl),
      headerControls: child.headerControls.map(normalizePaperControl),
    });

  for (const pageName of ['Site', 'Soil/Terrain', 'Vegetation', 'Veg Other', 'Other']) {
    for (const vegMode of ['initial', 'height', 'cover']) {
      for (const coordMode of ['dd', 'dm', 'dms']) {
        assert.deepEqual(
          normalizePage(paperCompacted.paperPage(pageName, vegMode, coordMode)),
          normalizePage(paperRaw.paperPage(pageName, vegMode, coordMode))
        );
      }
    }
  }
  for (const childForm of [
    'SubVegAXL_BC',
    'SubVegAXL',
    'SubVegAhtXL',
    'SubVegCXL',
    'SubVegChtXL',
    'SubVegDXL',
    'SoilHumusXL',
    'SoilMineralXL',
    'SubOtherXL',
    'USysVegOtherXL',
    'USysAuditXL',
  ]) {
    assert.deepEqual(
      normalizeChild(paperCompacted.paperChild(childForm)),
      normalizeChild(paperRaw.paperChild(childForm))
    );
  }

  const { editor, writeSession, transport, metadata } = require('./siviParentTestHelpers.cjs');
  const quality = loadTypeScript('entry/qualityEditor.ts', {
    './becEditor': loadTypeScript('entry/becEditor.ts'),
  });
  const ordinary = loadTypeScript('entry/ordinaryEditor.ts', {
    './qualityEditor': quality,
    './numericEditor': loadTypeScript('entry/numericEditor.ts'),
  });
  const shared = loadTypeScript('entry/siviParentSharedSession.ts', {
    './ordinaryEditor': ordinary,
    './projectMetadataEditor': metadata,
    './siviParentEditor': editor,
    './siviParentWriteSession': writeSession,
    './siviParentTransport': transport,
    './coordinateEditor': loadTypeScript('entry/coordinateEditor.ts'),
    './siviDateTimestamp': loadTypeScript('entry/siviDateTimestamp.ts'),
    './referenceEditor': loadTypeScript('entry/referenceEditor.ts', {
      './qualityEditor': quality,
      './projectMetadataEditor': metadata,
      './siviParentTransport': transport,
    }),
  });

  const buildProjectionSuite = (twoPageNormal, twoPageChars, paperMod) => {
    const extraMod = loadTypeScript('entry/twoPageParentSession.ts', {
      '../../resources/fs882-two-page-layout.json': twoPageNormal,
      '../../resources/fs882-two-page-chars-layout.json': twoPageChars,
      './siviParentEditor': editor,
      './siviParentTransport': transport,
      './siviParentWriteSession': writeSession,
      './siviParentSharedSession': shared,
      './ordinaryEditor': ordinary,
      './projectMetadataEditor': metadata,
    });
    const commonMod = loadTypeScript('entry/twoPageParentCommonSession.ts', {
      './siviParentEditor': editor,
      './twoPageParentSession': extraMod,
      './siviParentTransport': transport,
      './siviParentWriteSession': writeSession,
      './siviParentSharedSession': shared,
      './ordinaryEditor': ordinary,
      './qualityEditor': quality,
      './projectMetadataEditor': metadata,
    });
    const projMod = loadTypeScript('entry/twoPageEntryProjection.ts', {
      './twoPageParentSession': extraMod,
      './twoPageParentCommonSession': commonMod,
      './paperLayout': paperMod,
      './projectMetadataEditor': metadata,
    });
    return { extraMod, commonMod, projMod };
  };

  const rawSuite = buildProjectionSuite(
    rawByFile['fs882-two-page-layout.json'],
    rawByFile['fs882-two-page-chars-layout.json'],
    paperRaw
  );
  const compactedSuite = buildProjectionSuite(
    compactedByFile['fs882-two-page-layout.json'],
    compactedByFile['fs882-two-page-chars-layout.json'],
    paperCompacted
  );

  for (const form of ['FS882-8x6XL', 'FS882-8x6XL-CHARS']) {
    assert.deepEqual(
      plain(compactedSuite.extraMod.twoPageParentFields(form)),
      plain(rawSuite.extraMod.twoPageParentFields(form))
    );
    assert.deepEqual(
      plain(compactedSuite.commonMod.twoPageParentCommonFields(form)),
      plain(rawSuite.commonMod.twoPageParentCommonFields(form))
    );
    for (const mode of ['dd', 'dm', 'dms']) {
      const compProj = compactedSuite.projMod.twoPageEntryProjection(form, mode);
      const rawProj = rawSuite.projMod.twoPageEntryProjection(form, mode);
      assert.deepEqual(
        plain({ ...compProj, pages: compProj.pages.map(normalizePage) }),
        plain({ ...rawProj, pages: rawProj.pages.map(normalizePage) })
      );
    }
  }
});

test('ENG-FE-008: production Rollup static closures keep UserLogReview < 150 kB, exclude fs1333-sivi-layout from FS882Form, and keep all app/layout chunks < 500 kB', async () => {
  const { build } = await import('vite');
  const result = await build({
    root: frontendDir,
    configFile: path.join(frontendDir, 'vite.config.ts'),
    mode: 'production',
    logLevel: 'warn',
    build: { write: false, emptyOutDir: false, sourcemap: false },
  });
  assert.ok(!Array.isArray(result) && Array.isArray(result.output));

  const chunks = new Map(
    result.output
      .filter((item) => item.type === 'chunk')
      .map((chunk) => [chunk.fileName, chunk])
  );

  const chunkBytes = (name) => Buffer.byteLength(chunks.get(name).code, 'utf8');

  const staticClosureOf = (prefix) => {
    const candidates = [...chunks.values()]
      .filter((c) => c.fileName.startsWith(`assets/${prefix}-`))
      .sort((a, b) => Buffer.byteLength(b.code, 'utf8') - Buffer.byteLength(a.code, 'utf8'));
    assert.ok(candidates.length > 0, `Expected chunk matching assets/${prefix}-*.js`);
    const visited = new Set();
    (function walk(fileName) {
      if (visited.has(fileName)) return;
      const chunk = chunks.get(fileName);
      assert.ok(chunk, `Missing static chunk ${fileName}`);
      visited.add(fileName);
      for (const dep of chunk.imports) walk(dep);
    })(candidates[0].fileName);
    const bytes = [...visited].reduce((sum, name) => sum + chunkBytes(name), 0);
    const moduleIds = [...visited].flatMap((name) =>
      Object.keys(chunks.get(name).modules).map((id) => id.replaceAll('\\', '/'))
    );
    return { root: candidates[0].fileName, chunks: visited, bytes, moduleIds };
  };

  // 1. UserLogReview static closure < 150 kB and zero siviParentTransport / fs1333-sivi-layout.json
  const userLogClosure = staticClosureOf('UserLogReview');
  assert.ok(
    userLogClosure.bytes < 150 * 1024,
    `UserLogReview static closure ${userLogClosure.bytes} B exceeds 150 kB budget`
  );
  assert.equal(
    userLogClosure.moduleIds.some((id) => id.endsWith('/fs1333-sivi-layout.json')),
    false,
    'UserLogReview static closure must not include fs1333-sivi-layout.json'
  );
  assert.equal(
    userLogClosure.moduleIds.some((id) => id.endsWith('/siviParentTransport.ts')),
    false,
    'UserLogReview static closure must not include siviParentTransport.ts'
  );

  // 2. FS882Form in standard 'fs882' mode does not eagerly load fs1333-sivi-layout.json or project-metadata-layout.json
  const fs882Closure = staticClosureOf('FS882Form');
  assert.equal(
    fs882Closure.moduleIds.some((id) => id.endsWith('/fs1333-sivi-layout.json')),
    false,
    'FS882Form static closure must not eagerly include fs1333-sivi-layout.json'
  );
  assert.equal(
    fs882Closure.moduleIds.some((id) => id.endsWith('/project-metadata-layout.json')),
    false,
    'FS882Form static closure must not eagerly include project-metadata-layout.json'
  );

  // 3. Dedicated manualChunks exist for fs1333-sivi-layout.json and project-metadata-layout.json
  for (const layoutPrefix of [
    'assets/layout-fs882-xl-',
    'assets/layout-fs882-two-page-',
    'assets/layout-fs882-two-page-chars-',
    'assets/layout-fs1333-sivi-',
    'assets/layout-project-metadata-',
  ]) {
    const matches = [...chunks.keys()].filter((name) => {
      if (layoutPrefix === 'assets/layout-fs882-two-page-') {
        return (
          name.startsWith(layoutPrefix) &&
          !name.startsWith('assets/layout-fs882-two-page-chars-')
        );
      }
      return name.startsWith(layoutPrefix);
    });
    assert.equal(matches.length, 1, `Expected dedicated layout chunk for ${layoutPrefix}`);
  }

  // 4. ProjectMetadataEditor static closure excludes project-metadata-layout.json and stays < 200 kB
  const metadataEditorClosure = staticClosureOf('ProjectMetadataEditor');
  assert.ok(
    metadataEditorClosure.bytes < 200 * 1024,
    `ProjectMetadataEditor static closure ${metadataEditorClosure.bytes} B exceeds 200 kB`
  );
  assert.equal(
    metadataEditorClosure.moduleIds.some((id) =>
      id.endsWith('/project-metadata-layout.json')
    ),
    false,
    'ProjectMetadataEditor static closure must not include project-metadata-layout.json'
  );

  // 5. TwoPageEntryEditor static closure drops well below 2.4 MB (from 4.8 MB) and excludes fs1333-sivi-layout.json
  const twoPageClosure = staticClosureOf('TwoPageEntryEditor');
  assert.ok(
    twoPageClosure.bytes < 2_400_000,
    `TwoPageEntryEditor static closure ${twoPageClosure.bytes} B exceeds 2.4 MB budget`
  );
  assert.equal(
    twoPageClosure.moduleIds.some((id) => id.endsWith('/fs1333-sivi-layout.json')),
    false,
    'TwoPageEntryEditor static closure must not include fs1333-sivi-layout.json'
  );

  // 6. Every non-vendor application & layout chunk stays below Rollup's 500 kB ceiling
  for (const [name] of chunks) {
    if (
      name.startsWith('assets/vendor-') ||
      name.startsWith('assets/maplibre-gl-worker-')
    ) {
      continue;
    }
    const sz = chunkBytes(name);
    assert.ok(
      sz < 500_000,
      `Application/layout chunk ${name} (${sz} B) exceeds 500 KB ceiling`
    );
  }
});

test('ENG-FE-008: GeospatialWorkbench.loadWorkbenchData fetches and decodes plot geometry once per load while preserving W3 spatial guards', async () => {
  const wbSource = readFileSync(srcPath('spatial/GeospatialWorkbench.svelte'), 'utf8');
  assert.doesNotMatch(
    wbSource,
    /GetSpatialPlotsFlatGeobuf/,
    'GeospatialWorkbench.svelte must not request duplicate FlatGeobuf stream on load'
  );
  assert.doesNotMatch(
    wbSource,
    /decodeFlatGeobufPoints/,
    'GeospatialWorkbench.svelte must not decode FlatGeobuf on load'
  );

  const wbHelpers = loadTypeScript('spatial/geospatialWorkbench.ts');
  const { createNotificationController } = loadTypeScript(
    'shell/notificationService.svelte.ts',
    { 'svelte/store': require('svelte/store') }
  );
  const notifications = createNotificationController({
    schedule: () => 0,
    cancelSchedule: () => {},
  });

  let payloadCalls = 0;
  let materializeCalls = 0;
  let fittedCalls = 0;

  const mockPayload = {
    project: 'Sample',
    projectPath: '/var/lib/vpro/projects/Sample.db',
    totalPlots: 3,
    plottableCount: 2,
    bgcMismatchCount: 1,
    utmDivergenceCount: 0,
    boundingBox: [-179.9, 52.0, 179.9, 53.0],
    manifest: {
      schemaVersion: 1,
      archives: {
        'bc-bgc-v13.pmtiles': {
          name: 'bc-bgc-v13.pmtiles',
          url: '/maps/bc-bgc-v13.pmtiles',
          source: 'embedded-overview',
          available: true,
          fullResolution: false,
          fallbackOverview: true,
          minZoom: 3,
          maxZoom: 6,
          sizeBytes: 180000,
          warning:
            'Local map archive bc-bgc-v13.pmtiles is unreadable; using built-in BC overview map.',
        },
      },
      ordered: [],
    },
    geoArrow: {
      count: 2,
      plotNumber: ['QAANT1', 'QAANT2'],
      lon: [179.9, -179.9],
      lat: [52.0, 53.0],
      hasUtm: [0, 0],
      utmDerivedLon: [0, 0],
      utmDerivedLat: [0, 0],
      divergenceMeters: [0, 0],
      divergenceFlagged: [0, 0],
      longitudeFlipped: [0, 0],
      elevation: [null, null],
      slope: [null, null],
      aspect: [null, null],
      zone: ['CWH', 'CWH'],
      subZone: ['vh1', 'vh1'],
      fieldBgc: ['CWHvh1', 'CWHvh1'],
      gisBgc: ['CWHvh1', 'CWHvh1'],
      bgcMismatch: [0, 0],
      siteUnit: ['01', '01'],
      ecosection: ['', ''],
      fsRegionDistrict: ['', ''],
    },
  };

  const host = componentFunctions(
    'spatial/GeospatialWorkbench.svelte',
    ['loadWorkbenchData'],
    {
      contextId: 'ctx-single-pass',
      project: 'Sample',
      su: 'None',
      alive: true,
      loadGeneration: 0,
      loading: false,
      mutating: false,
      errorMsg: '',
      pmtilesGraticuleFallback: true,
      pmtilesArchiveWarning: '',
      gpkgDestPath: '',
      payload: null,
      plotPoints: [],
      plotCoordsF32: new Float32Array(0),
      discrepancySegments: [],
      flatGeobufCount: 0,
      aoiTargetMode: 'update_active',
      aoiSUName: '',
      selectedPlot: { plotNumber: 'QAANT1' },
      mapInstance: {},
      setBusyState() {},
      applyLayerVisibilities() {},
      initializeMapCanvas() {},
      refreshDeckOverlay() {},
      runViewportKernel: async () => {},
      inspectPlotPin: async () => {},
      summarizePMTilesManifestWarnings: wbHelpers.summarizePMTilesManifestWarnings,
      isAbsoluteFilesystemPath: wbHelpers.isAbsoluteFilesystemPath,
      buildDefaultGeoPackageExportPath: wbHelpers.buildDefaultGeoPackageExportPath,
      materializeWorkbenchPlots(geoArrow) {
        materializeCalls++;
        return wbHelpers.materializeWorkbenchPlots(geoArrow);
      },
      fitMapToPayloadBounds(_map, wb) {
        fittedCalls++;
        const fit = wbHelpers.computeMapFitBounds(wb);
        assert.equal(fit.kind, 'bounds');
        assert.ok(Math.abs(fit.bounds[0][0] - 179.9) < 1e-6);
        assert.ok(Math.abs(fit.bounds[1][0] - 180.1) < 1e-6);
      },
      SpatialService: {
        async GetSpatialWorkbenchPayload(ctxId) {
          assert.equal(ctxId, 'ctx-single-pass');
          payloadCalls++;
          return mockPayload;
        },
        async GetSpatialPlotsFlatGeobuf() {
          throw new Error('GetSpatialPlotsFlatGeobuf must not be called by loadWorkbenchData');
        },
      },
      notifications,
    }
  );

  await host.actions.loadWorkbenchData();

  assert.equal(payloadCalls, 1, 'Expected exactly 1 GetSpatialWorkbenchPayload RPC call');
  assert.equal(materializeCalls, 1, 'Expected plot points to be decoded once per load');
  assert.equal(fittedCalls, 1, 'Expected antimeridian fitMapToPayloadBounds to run');
  assert.equal(host.plotPoints.length, 2);
  assert.equal(host.flatGeobufCount, 2);
  assert.equal(host.gpkgDestPath, '/var/lib/vpro/exports/Sample_plots.gpkg');
  assert.match(host.pmtilesArchiveWarning, /bc-bgc-v13\.pmtiles is unreadable/);
  assert.equal(notifications.getSnapshot().entries.length, 1);
});
