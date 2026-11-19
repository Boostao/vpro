const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { render } = require('svelte/server');
const { loadTypeScript, serverComponent, srcPath } = require('./svelteTestHelpers.cjs');

const wb = loadTypeScript('geospatialWorkbench.ts');
const quality = loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });
const cells = loadTypeScript('projectMetadataRestore.ts', { './qualityEditor': quality, './projectMetadataEditor': {} });
const plotLoc = loadTypeScript('plotLocationReview.ts', { './projectMetadataRestore': cells });

test('UX-SPATIAL-001: corrupt PMTiles manifest warnings, error classification, and graticule fallback', () => {
  const manifest = {
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
        warning: 'Local map archive bc-bgc-v13.pmtiles is unreadable or incomplete; using the built-in BC overview map (z3..6) instead.',
      },
    },
    ordered: [],
  };

  const warn = wb.summarizePMTilesManifestWarnings(manifest);
  assert.match(warn, /bc-bgc-v13\.pmtiles is unreadable/);
  assert.match(wb.summarizeArchiveResolution({ manifest }), /z3\.\.6, local archive unreadable/);

  const fallbackStyle = wb.buildMapLibreGeospatialStyle(
    manifest,
    {
      bgcFill: true,
      bgcLabels: true,
      ecosections: true,
      nrDistricts: true,
      hillshade3D: false,
      bcOpenMapsWMS: false,
      discrepancyVectors: true,
    },
    { forceGraticuleFallback: true }
  );
  assert.ok(fallbackStyle.sources.vpro_offline_graticule, 'built-in offline graticule source must remain active');
  assert.equal(fallbackStyle.sources.bc_bgc_pmtiles, undefined, 'corrupt PMTiles vector source omitted in graticule fallback');
  assert.equal(fallbackStyle.sources.bc_admin_pmtiles, undefined);

  assert.match(
    wb.classifyPMTilesMapError({ sourceId: 'bc_bgc_pmtiles', error: new Error('PMTiles bad header magic') }),
    /built-in offline map fallback/
  );
  assert.equal(wb.classifyPMTilesMapError({ sourceId: 'bc_openmaps_wms', error: new Error('Failed to fetch') }), null);
});

test('UX-SPATIAL-002: GeoPackage export path defaults to <dataDir>/exports/<Project>_plots.gpkg and never CWD', () => {
  assert.equal(
    wb.buildDefaultGeoPackageExportPath('Sample', '/home/bruno/Work/vpro-qa/runs/UX-SPATIAL/data/projects/Sample.db'),
    '/home/bruno/Work/vpro-qa/runs/UX-SPATIAL/data/exports/Sample_plots.gpkg'
  );
  assert.equal(
    wb.buildDefaultGeoPackageExportPath('Haida Gwaii', 'C:\\Users\\ecologist\\AppData\\Local\\vpro\\projects\\Haida.db'),
    'C:\\Users\\ecologist\\AppData\\Local\\vpro\\exports\\Haida_Gwaii_plots.gpkg'
  );
  assert.equal(
    wb.buildDefaultGeoPackageExportPath('CustomProj', '/mnt/fieldwork/CustomProj.db'),
    '/mnt/fieldwork/exports/CustomProj_plots.gpkg'
  );
  assert.equal(wb.buildDefaultGeoPackageExportPath('Sample', ''), '');

  // Relative filenames resolve into <dataDir>/exports when projectPath is known, or reject (null) when unknown
  assert.equal(
    wb.resolveGeoPackageDestinationPath('Sample_plots.gpkg', 'Sample', '/var/lib/vpro/projects/Sample.db'),
    '/var/lib/vpro/exports/Sample_plots.gpkg'
  );
  assert.equal(wb.resolveGeoPackageDestinationPath('Sample_plots.gpkg', 'Sample', ''), null);
  assert.equal(wb.resolveGeoPackageDestinationPath('../escape.gpkg', 'Sample', '/var/lib/vpro/projects/Sample.db'), null);
  assert.equal(wb.resolveGeoPackageDestinationPath('/tmp/explicit_out', 'Sample', ''), '/tmp/explicit_out.gpkg');
});

test('UX-SPATIAL-003: signed longitude labels, antimeridian preservation, and fitMapToPayloadBounds', () => {
  const inspectorSrc = readFileSync(srcPath('spatial/SpatialPlotInspectorTab.svelte'), 'utf8');
  assert.doesNotMatch(inspectorSrc, /Western Lon/i);
  assert.match(inspectorSrc, /NAD83 Lat, Lon/);

  const plotLocSrc = readFileSync(srcPath('spatial/PlotLocationReview.svelte'), 'utf8');
  assert.doesNotMatch(plotLocSrc, /latitude then western-hemisphere longitude/i);
  assert.match(plotLocSrc, /latitude then signed decimal longitude/);

  assert.equal(
    plotLoc.exactLongitudeNegation(
      { storage: 'real', real: 179.9, text: null, integer: null, blobHex: null },
      { storage: 'real', real: 179.9, text: null, integer: null, blobHex: null }
    ),
    true
  );
  assert.equal(
    plotLoc.exactLongitudeNegation(
      { storage: 'real', real: -179.9, text: null, integer: null, blobHex: null },
      { storage: 'real', real: -179.9, text: null, integer: null, blobHex: null }
    ),
    true
  );

  // BC plots + QAANT1 (+179.9) + QAANT2 (-179.9): initial fit stays focused on BC plots
  const mixedPayload = {
    plottableCount: 4,
    boundingBox: [-179.9, 49.2, 179.9, 58.1],
    geoArrow: {
      count: 4,
      lon: [-123.62903, -127.1743, 179.9, -179.9],
      lat: [58.12346, 54.7804, 52.5, 52.5],
    },
  };
  let fittedBounds = null;
  wb.fitMapToPayloadBounds(
    {
      fitBounds(b) {
        fittedBounds = b;
      },
      jumpTo() {},
    },
    mixedPayload
  );
  assert.deepEqual(JSON.parse(JSON.stringify(fittedBounds)), [
    [-127.1743, 54.7804],
    [-123.62903, 58.12346],
  ]);

  // Pure antimeridian survey (+179.9 and -179.9 only): wraps shortest 0.2 deg arc across 180 meridian
  const antimeridianOnly = {
    plottableCount: 2,
    boundingBox: [-179.9, 52.0, 179.9, 53.0],
    geoArrow: {
      count: 2,
      lon: [179.9, -179.9],
      lat: [52.0, 53.0],
    },
  };
  const arcTarget = wb.computeMapFitBounds(antimeridianOnly);
  assert.equal(arcTarget.kind, 'bounds');
  assert.ok(Math.abs(arcTarget.bounds[0][0] - 179.9) < 1e-6);
  assert.ok(Math.abs(arcTarget.bounds[1][0] - 180.1) < 1e-6);
});

test('UX-SPATIAL-004: Zone 12 inspector rendering, Zone 0 suppression, and QA filter invalid/zero coordinates', () => {
  const InspectorComp = serverComponent(
    readFileSync(srcPath('spatial/SpatialPlotInspectorTab.svelte'), 'utf8'),
    'spatial/SpatialPlotInspectorTab.svelte',
    {}
  );

  // Zone 12 plot renders real Zone 12 Easting/Northing and UTM delta
  const htmlZ12 = render(InspectorComp, {
    props: {
      selectedPlot: {
        index: 0,
        plotNumber: 'QAZ12',
        lat: 50.0,
        lon: -113.5,
        hasUtm: true,
        utmDerivedLon: -113.5,
        utmDerivedLat: 50.0,
        divergenceMeters: 0.4,
        divergenceFlagged: false,
        longitudeFlipped: false,
        elevation: 1400,
        slope: 12,
        aspect: 180,
        zone: 'IDF',
        subZone: 'dk5',
        fieldBgc: 'IDFdk5',
        gisBgc: '',
        bgcMismatch: false,
        siteUnit: '',
        ecosection: '',
        fsRegionDistrict: '',
      },
      selectedSuggestion: {
        utmZone: 12,
        utmEasting: 320973.1,
        utmNorthing: 5541502.4,
        gisBgc: 'IDFdk5',
        zoneName: 'Interior Douglas-fir',
        bgcSource: 'bc-overview.pmtiles',
        bgcZoom: 6,
        ntsMapSheet: '082G058',
        fsRegionDistrict: 'RKB.DRM',
        terrainSanityNote: '',
      },
      filteredPoints: [],
      onInspectPlot() {},
    },
  }).body;
  assert.match(htmlZ12, /NAD83 UTM Zone 12: 320973\.1 E, 5541502\.4 N/);
  assert.match(htmlZ12, /0\.4 m/);
  assert.doesNotMatch(htmlZ12, /No UTM entered/);

  // Out-of-zone plot with utmZone=0 omits bogus "Zone 0: 0.0 E, 0.0 N"
  const htmlZ0 = render(InspectorComp, {
    props: {
      selectedPlot: {
        index: 0,
        plotNumber: 'QAANT1',
        lat: 52.5,
        lon: 179.9,
        hasUtm: false,
        utmDerivedLon: null,
        utmDerivedLat: null,
        divergenceMeters: 0,
        divergenceFlagged: false,
        longitudeFlipped: false,
        elevation: null,
        slope: null,
        aspect: null,
        zone: 'CWH',
        subZone: 'vh1',
        fieldBgc: 'CWHvh1',
        gisBgc: '',
        bgcMismatch: false,
        siteUnit: '',
        ecosection: '',
        fsRegionDistrict: '',
      },
      selectedSuggestion: {
        utmZone: 0,
        utmEasting: 0,
        utmNorthing: 0,
        gisBgc: '',
        zoneName: '',
        bgcSource: 'overview',
        bgcZoom: 6,
        ntsMapSheet: '',
        fsRegionDistrict: '',
        terrainSanityNote: '',
      },
      filteredPoints: [],
      onInspectPlot() {},
    },
  }).body;
  assert.doesNotMatch(htmlZ0, /Zone 0: 0\.0 E, 0\.0 N/);
  assert.match(htmlZ0, /Outside supported Canadian \/ BC UTM zones/);

  // QA filter includes QA0000 (0, 0) and QA9999 (95, 200) while excluding clean plots
  const qaRows = [
    { plotNumber: 'CLEAN1', latitude: 53.9, longitude: -122.7, storedGisBgc: 'SBSmk1', suggestedGisBgc: 'SBSmk1', diagnostics: [] },
    { plotNumber: 'QA0000', latitude: 0, longitude: 0, diagnostics: ['Zero placeholder coordinates (0, 0) require valid field Latitude/Longitude'] },
    { plotNumber: 'QA9999', latitude: 95, longitude: 200, diagnostics: ['Latitude/Longitude (95.00000, 200.00000) exceeds valid geographic bounds [-90..90, -180..180]'] },
  ];
  const filtered = wb.filterSpatialQARows(qaRows, true);
  assert.deepEqual(
    filtered.map((r) => r.plotNumber),
    ['QA0000', 'QA9999']
  );
});
