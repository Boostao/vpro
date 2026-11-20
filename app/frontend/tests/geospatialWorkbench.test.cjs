const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const { compile } = require('svelte/compiler');
const { render } = require('svelte/server');
const { componentFunctions, loadTypeScript, serverComponent, srcPath } = require('./svelteTestHelpers.cjs');

const wb = loadTypeScript('geospatialWorkbench.ts');
const plain = (value) => JSON.parse(JSON.stringify(value));

test('detectSpatialComputeBackend handles missing navigator.gpu, null adapter, device errors, and real WebGPU adapter', async () => {
  const missing = await wb.detectSpatialComputeBackend({});
  assert.equal(missing.backend, 'webgl2-cpu');
  assert.equal(missing.available, false);
  assert.match(missing.fallbackReason, /unavailable/);

  const nullAdapter = await wb.detectSpatialComputeBackend({
    gpu: { requestAdapter: async () => null },
  });
  assert.equal(nullAdapter.backend, 'webgl2-cpu');
  assert.equal(nullAdapter.available, false);

  const thrownDevice = await wb.detectSpatialComputeBackend({
    gpu: {
      requestAdapter: async () => ({
        requestDevice: async () => {
          throw new Error('Vulkan ICD missing');
        },
      }),
    },
  });
  assert.equal(thrownDevice.backend, 'webgl2-cpu');
  assert.match(thrownDevice.fallbackReason, /Vulkan ICD missing/);

  let compiledShaderCode = '';
  let destroyed = false;
  const activeGPU = await wb.detectSpatialComputeBackend({
    gpu: {
      requestAdapter: async () => ({
        info: { vendor: 'AMD', description: 'Radeon Pro' },
        limits: { maxComputeWorkgroupSizeX: 512 },
        requestDevice: async () => ({
          limits: { maxComputeWorkgroupSizeX: 512 },
          createShaderModule: ({ code }) => {
            compiledShaderCode = code;
            return {};
          },
          destroy: () => {
            destroyed = true;
          },
        }),
      }),
    },
  });
  assert.equal(activeGPU.backend, 'webgpu');
  assert.equal(activeGPU.available, true);
  assert.equal(activeGPU.adapterLabel, 'AMD - Radeon Pro');
  assert.equal(activeGPU.maxComputeWorkgroupSizeX, 512);
  assert.equal(destroyed, true);
  assert.match(compiledShaderCode, /@compute @workgroup_size\(64\)/);
  assert.match(compiledShaderCode, /atomicAdd\(&densityBins\[binIdx\], 1u\)/);
});

test('executeSpatialFilterKernel produces deterministic BBOX indices and density bins on CPU fallback and simulated WebGPU', async () => {
  const coords = new Float32Array([
    -122.7497, 53.9171, // 0: Prince George (inside)
    -123.3656, 48.4284, // 1: Victoria (outside lat)
    -127.1743, 54.7804, // 2: Smithers (inside)
    -115.7666, 49.5097, // 3: Cranbrook (outside lon/lat)
  ]);
  const bounds = [-128.0, 53.0, -121.0, 55.5];

  const cpuRes = await wb.executeSpatialFilterKernel(coords, bounds, {
    nav: {},
    gridSize: 8,
  });
  assert.equal(cpuRes.backend, 'webgl2-cpu');
  assert.deepEqual(plain(cpuRes.matchedIndices), [0, 2]);
  assert.equal(cpuRes.matchedCount, 2);
  const totalBins = Array.from(cpuRes.densityGrid).reduce((a, b) => a + b, 0);
  assert.equal(totalBins, 2);
});

test('decodeFlatGeobufPoints decodes Go-generated OGC FlatGeobuf v3 wire fixture and rejects malformed magic', () => {
  const b64Fixture = readFileSync(
    path.join(__dirname, '..', '..', 'testdata', 'wave3-plots-flatgeobuf.b64'),
    'utf8'
  ).trim();

  const plots = wb.decodeFlatGeobufPoints(b64Fixture);
  assert.equal(plots.length, 2);

  assert.equal(plots[0].plotNumber, '00337');
  assert.ok(Math.abs(plots[0].lat - 53.9171) < 1e-6);
  assert.ok(Math.abs(plots[0].lon - -122.7497) < 1e-6);
  assert.ok(Math.abs(plots[0].utmDerivedLat - 53.9182) < 1e-6);
  assert.ok(Math.abs(plots[0].divergenceMeters - 146.4) < 1e-6);
  assert.equal(plots[0].elevation, 615);
  assert.equal(plots[0].fieldBgc, 'ICHvk2');
  assert.equal(plots[0].gisBgc, 'SBSmk1');
  assert.equal(plots[0].bgcMismatch, true);
  assert.equal(plots[0].siteUnit, 'SBSmk1/01');

  assert.equal(plots[1].plotNumber, '108050');
  assert.equal(plots[1].bgcMismatch, false);
  assert.equal(plots[1].siteUnit, 'CDFmm/01');

  assert.throws(
    () => wb.decodeFlatGeobufPoints(new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])),
    /Invalid OGC FlatGeobuf v3 magic/
  );
});

test('pointInPolygonRing, materializeWorkbenchPlots, and buildMapLibreGeospatialStyle preserve offline PMTiles contracts', () => {
  const ring = [
    [-124.0, 53.0],
    [-121.0, 53.0],
    [-121.0, 55.0],
    [-124.0, 55.0],
  ];
  assert.equal(wb.pointInPolygonRing(-122.7497, 53.9171, ring), true);
  assert.equal(wb.pointInPolygonRing(-123.3656, 48.4284, ring), false);
  assert.equal(wb.pointInPolygonRing(-122.7497, 53.9171, [...ring, ring[0]]), true);

  const mat = wb.materializeWorkbenchPlots({
    count: 2,
    plotNumber: ['00337', '108050'],
    lon: [-122.7497, -123.3656],
    lat: [53.9171, 48.4284],
    hasUtm: [true, false],
    utmDerivedLon: [-122.752, 0],
    utmDerivedLat: [53.919, 0],
    divergenceMeters: [185.2, 0],
    divergenceFlagged: [true, false],
    longitudeFlipped: [true, false],
    hasElevation: [true, false],
    elevation: [620, 0],
    hasSlope: [false, false],
    slope: [0, 0],
    hasAspect: [false, false],
    aspect: [0, 0],
    zone: ['SBS', 'CDF'],
    subZone: ['mk1', 'mm'],
    fieldBgc: ['ICHvk2', 'CDFmm'],
    gisBgc: ['SBSmk1', 'CDFmm'],
    bgcMismatch: [true, false],
    siteUnit: ['SBSmk1/01', 'CDFmm/01'],
    ecosection: ['NAB', 'SGI'],
    fsRegionDistrict: ['RNO.DPG', 'RSC.DSI'],
  });
  assert.equal(mat.points.length, 2);
  assert.equal(mat.discrepancyVectors.length, 1);
  assert.equal(mat.discrepancyVectors[0].plotNumber, '00337');

  const styleOffline = wb.buildMapLibreGeospatialStyle(
    {
      schemaVersion: 1,
      archives: {
        'bc-bgc-v13.pmtiles': {
          name: 'bc-bgc-v13.pmtiles',
          url: '/maps/bc-bgc-v13.pmtiles',
          source: 'extraDir',
          available: true,
          fullResolution: true,
          fallbackOverview: false,
          minZoom: 3,
          maxZoom: 10,
          sizeBytes: 55000000,
        },
      },
      ordered: [],
    },
    {
      bgcFill: true,
      bgcLabels: true,
      ecosections: true,
      nrDistricts: false,
      hillshade3D: false,
      bcOpenMapsWMS: false,
      discrepancyVectors: true,
    }
  );
  assert.equal(styleOffline.sources.bc_bgc_pmtiles.url, 'pmtiles:///maps/bc-bgc-v13.pmtiles');
  assert.equal(styleOffline.sources.bc_bgc_pmtiles.maxzoom, 10);
  assert.equal(styleOffline.sources.bc_openmaps_wms, undefined);

  const styleWMS = wb.buildMapLibreGeospatialStyle(null, {
    bgcFill: true,
    bgcLabels: true,
    ecosections: false,
    nrDistricts: true,
    hillshade3D: true,
    bcOpenMapsWMS: true,
    discrepancyVectors: true,
  });
  assert.ok(styleWMS.sources.bc_openmaps_wms);
});

test('GeospatialWorkbench, Navigation, App, and CoordinateFields compile cleanly with BC Gov styling and zero emojis', () => {
  const wbSource = readFileSync(srcPath('GeospatialWorkbench.svelte'), 'utf8');
  const navSource = readFileSync(srcPath('Navigation.svelte'), 'utf8');
  const appSource = readFileSync(srcPath('App.svelte'), 'utf8');
  const coordSource = readFileSync(srcPath('CoordinateFields.svelte'), 'utf8');

  for (const [name, src] of [
    ['GeospatialWorkbench.svelte', wbSource],
    ['Navigation.svelte', navSource],
    ['App.svelte', appSource],
    ['CoordinateFields.svelte', coordSource],
  ]) {
    const compiled = compile(src, { filename: name, generate: 'client' });
    assert.equal(compiled.warnings.length, 0, `${name} emitted compiler warnings`);
  }

  // Zero emojis in new/modified Wave 3 files
  const emojiRegex = /[\p{Extended_Pictographic}]/u;
  assert.equal(emojiRegex.test(wbSource), false, 'GeospatialWorkbench.svelte must contain zero emojis');
  assert.equal(
    emojiRegex.test(readFileSync(srcPath('geospatialWorkbench.ts'), 'utf8')),
    false,
    'geospatialWorkbench.ts must contain zero emojis'
  );

  // Zero new VITE_* or VPRO_* env flags in GeospatialWorkbench
  assert.doesNotMatch(wbSource, /VITE_|VPRO_/);

  // BC Gov Design System palette (#003366 / #FCBA19 via semantic vpro-* tokens)
  assert.match(wbSource, /#003366|vpro-navy/i);
  assert.match(wbSource, /#fcba19|vpro-gold/i);

  // Explicit bundled MapLibre worker URL configured for WebView2 http://wails.localhost/
  assert.match(wbSource, /maplibre-gl\/dist\/maplibre-gl-worker\.mjs\?worker&url/);
  assert.match(wbSource, /setWorkerUrl\(/);

  // Lazy route in ShellDeferredViews.svelte, Spatial entry in Navigation.svelte, Auto-1 button in CoordinateFields.svelte
  const { readShellComposite } = require('./svelteTestHelpers.cjs');
  assert.match(readShellComposite(), /import\('\.\.?\/spatial\/GeospatialWorkbench\.svelte'\)/);
  assert.match(navSource, /3D Map \(BGC, Coordinate Check & Site Units\)/);
  assert.match(navSource, /3D Map/);
  assert.match(coordSource, /data-auto1-spatial-stamp/);

  // SSR render smoke check of GeospatialWorkbench.svelte
  const SSRWorkbench = serverComponent(wbSource, 'GeospatialWorkbench.svelte', {
    'maplibre-gl': {
      default: { setWorkerUrl() {} },
      Map: class {},
      NavigationControl: class {},
      ScaleControl: class {},
      addProtocol() {},
      setWorkerUrl() {},
    },
    'maplibre-gl/dist/maplibre-gl.css': {},
    'maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url': { default: '/assets/maplibre-gl-worker.js' },
    pmtiles: { Protocol: class { tile = () => {}; } },
    '@deck.gl/mapbox': { MapboxOverlay: class {} },
    '@deck.gl/layers': { LineLayer: class {}, ScatterplotLayer: class {} },
    '../bindings/github.com/boostao/vpro/app': { SpatialService: {}, ImportExportService: {} },
    './geospatialWorkbench': wb,
  });
  const html = render(SSRWorkbench, {
    props: { contextId: 'ctx-wave3', project: 'Sample', su: 'None' },
  }).body;
  assert.match(html, /3D BGC v13 Map, Coordinate Check/);
  assert.match(html, /Plot Inspector/);
  assert.match(html, /Lasso \/ AOI/);
  assert.match(html, /Coordinate &amp; BGC Stamp/);
});

test('GeospatialWorkbench imports bundled maplibre-gl-worker.mjs?worker&url and configures worker URL before instantiating Map', async () => {
  const vm = require('node:vm');
  const ts = require('typescript');
  const client = await import('svelte/internal/client');
  const wbSource = readFileSync(srcPath('GeospatialWorkbench.svelte'), 'utf8');

  assert.match(
    wbSource,
    /import maplibreWorkerUrl from ['"]maplibre-gl\/dist\/maplibre-gl-worker\.mjs\?worker&url['"];/
  );
  assert.match(wbSource, /setWorkerUrl\(maplibreWorkerUrl\)/);

  let script = wbSource.match(/<script lang="ts">([\s\S]*?)<\/script>/)[1];
  script = script.replace('onOpenPlot?: (plotNumber: string) => void;', 'onOpenPlot?: (plotNumber: string) => void; inspect?: (v: any) => void;');
  script = script.replace('onOpenPlot,', 'onOpenPlot, inspect,');
  script += `\n$effect(() => inspect?.({
    mountCanvas(el) { mapContainer = el; initializeMapCanvas(); },
  }));`;

  const compiled = compile(`<script lang="ts">${script}</script>`, {
    filename: 'GeospatialWorkbench.svelte',
    generate: 'client',
  });
  assert.equal(compiled.warnings.length, 0);

  const callOrder = [];
  const modObj = { exports: {} };
  const transpiled = ts.transpileModule(compiled.js.code, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, esModuleInterop: true },
  }).outputText;

  const maplibreMock = {
    setWorkerUrl(url) {
      callOrder.push(`setWorkerUrl:${url}`);
    },
    addProtocol() {
      callOrder.push('addProtocol');
    },
    Map: class {
      constructor() {
        callOrder.push('new Map');
      }
      addControl() {}
      on() {}
      remove() {}
    },
    NavigationControl: class {},
    ScaleControl: class {},
  };
  maplibreMock.default = maplibreMock;

  vm.runInNewContext(transpiled, {
    module: modObj,
    exports: modObj.exports,
    structuredClone,
    require(name) {
      if (name === 'svelte') {
        return {
          onMount: () => {},
          onDestroy: () => {},
        };
      }
      if (name === 'svelte/internal/client') return client;
      if (name.startsWith('svelte/')) return require(name);
      if (name === 'maplibre-gl') return maplibreMock;
      if (name === 'maplibre-gl/dist/maplibre-gl.css') return {};
      if (name === 'maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url') {
        return { __esModule: true, default: '/assets/maplibre-gl-worker-bundled.mjs' };
      }
      if (name === 'pmtiles') return { Protocol: class { tile = () => {}; } };
      if (name === '@deck.gl/mapbox') return { MapboxOverlay: class { setProps() {} } };
      if (name === '@deck.gl/layers') return { LineLayer: class {}, ScatterplotLayer: class {} };
      if (name.includes('bindings/github.com/boostao/vpro/app')) return { SpatialService: {}, ImportExportService: {} };
      if (name === './geospatialWorkbench') return wb;
      throw new Error(`Unexpected module ${name}`);
    },
  });

  let api;
  const dispose = client.effect_root(() => {
    modObj.exports.default(null, {
      contextId: 'ctx-worker',
      project: 'Sample',
      su: 'None',
      inspect: v => { api = v; },
    });
  });
  try {
    client.flush();
    api.mountCanvas({});
    const workerIdx = callOrder.indexOf('setWorkerUrl:/assets/maplibre-gl-worker-bundled.mjs');
    const mapIdx = callOrder.indexOf('new Map');
    assert.ok(workerIdx >= 0, 'setWorkerUrl must be called with bundled worker URL');
    assert.ok(mapIdx > workerIdx, 'setWorkerUrl must execute before new Map(...)');
  } finally {
    dispose();
  }
});

test('classifyWMSMapError surfaces offline WMS warnings without blocking offline PMTiles', () => {
  assert.equal(wb.classifyWMSMapError({ sourceId: 'bc_openmaps_wms' }, false, false), null);
  assert.match(wb.classifyWMSMapError({}, true, false), /offline.*Offline BGC v13/i);
  assert.match(
    wb.classifyWMSMapError({ sourceId: 'bc_openmaps_wms', error: new Error('Failed to fetch') }, true, true),
    /WMS tile request failed.*Offline map/i
  );
  assert.match(
    wb.classifyWMSMapError(
      { error: { url: 'https://openmaps.gov.bc.ca/geo/pub/ows?service=WMS', message: 'NetworkError' } },
      true,
      true
    ),
    /WMS tile request failed/i
  );
  assert.equal(wb.classifyWMSMapError({ sourceId: 'bc_bgc_pmtiles', error: new Error(' unrelated ') }, true, true), null);
});

test('GeospatialWorkbench removes inline error/warning banners while routing wmsOfflineWarning and mapRenderWarning to background notifications', () => {
  const wbSource = readFileSync(srcPath('GeospatialWorkbench.svelte'), 'utf8');
  const lassoSource = readFileSync(srcPath('SpatialAOILassoTab.svelte'), 'utf8');
  assert.doesNotMatch(wbSource, /\{#if errorMsg\}<div/);
  assert.doesNotMatch(wbSource, /\{#if mapRenderWarning\}<div/);
  assert.doesNotMatch(wbSource, /\{#if wmsOfflineWarning\}<div/);
  assert.match(wbSource, /let errorMsg = \$state\(''\);/);
  assert.match(wbSource, /let mapRenderWarning = \$state\(''\);/);
  assert.match(wbSource, /let wmsOfflineWarning = \$state\(''\);/);
  assert.match(lassoSource, /class="wb-suggestion-box" role="status"/);

  const { createNotificationController } = loadTypeScript('shell/notificationService.svelte.ts', {
    'svelte/store': require('svelte/store'),
  });
  const notifications = createNotificationController({ schedule: () => 0, cancelSchedule: () => {} });
  const host = componentFunctions('GeospatialWorkbench.svelte', ['applyLayerVisibilities', 'initializeMapCanvas'], {
    project: 'Sample',
    alive: true,
    visibility: { bcOpenMapsWMS: true },
    wmsOfflineWarning: '',
    mapRenderWarning: '',
    mapInstance: null,
    mapContainer: {},
    payload: null,
    navigator: { onLine: false },
    classifyWMSMapError: wb.classifyWMSMapError,
    ensurePMTilesProtocol() {},
    setWorkerUrl() {},
    maplibreWorkerUrl: '/worker.js',
    $state: { snapshot: v => v },
    buildMapLibreGeospatialStyle() { throw new Error('WebGL unavailable'); },
    notifications,
  });

  host.actions.applyLayerVisibilities();
  host.actions.initializeMapCanvas();

  const entries = notifications.getSnapshot().entries;
  assert.equal(entries.length, 2);
  assert.ok(entries.every(item => item.severity === 'warning' && item.category === 'background' && item.source === '3D Map' && item.contextTag === 'Sample'));
  assert.match(entries[0].message, /WebGL unavailable/);
  assert.match(entries[1].message, /offline/i);
  assert.match(wbSource, /const handleBrowserOffline = \(\) => \{[\s\S]*?notifications\.warning\(/);
});

test('buildMapLibreGeospatialStyle generates verified basemaps, proxied BC Gov WMS overlays, and persisted opacities', () => {
  const baseVis = {
    bgcFill: true,
    bgcLabels: true,
    ecosections: true,
    nrDistricts: true,
    hillshade3D: false,
    bcOpenMapsWMS: false,
    discrepancyVectors: true,
  };

  // 1. Offline Neutral makes zero external tile requests
  const offlineStyle = wb.buildMapLibreGeospatialStyle(null, baseVis, { basemap: 'offline-neutral' });
  assert.equal(offlineStyle.sources.vpro_basemap_base, undefined);
  assert.equal(offlineStyle.sources.vpro_basemap_reference, undefined);
  assert.ok(offlineStyle.sources.vpro_offline_graticule);
  const bgLayer = offlineStyle.layers.find((l) => l.id === 'vpro-ocean-background');
  assert.equal(bgLayer.paint['background-color'], '#F2F2F2');

  // 2. Positron Light uses Esri World Light Gray Base + Reference labels on top
  const lightStyle = wb.buildMapLibreGeospatialStyle(null, baseVis, { basemap: 'positron-light' });
  assert.deepEqual(plain(lightStyle.sources.vpro_basemap_base.tiles), [
    'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}',
  ]);
  assert.deepEqual(plain(lightStyle.sources.vpro_basemap_reference.tiles), [
    'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Reference/MapServer/tile/{z}/{y}/{x}',
  ]);
  assert.match(lightStyle.sources.vpro_basemap_base.attribution, /OpenStreetMap contributors/);
  const baseLayerIdx = lightStyle.layers.findIndex((l) => l.id === 'vpro-basemap-base-layer');
  const bgcFillIdx = lightStyle.layers.findIndex((l) => l.id === 'bgc-zones-fill');
  const refLayerIdx = lightStyle.layers.findIndex((l) => l.id === 'vpro-basemap-reference-layer');
  assert.ok(baseLayerIdx > 0 && baseLayerIdx < bgcFillIdx && bgcFillIdx < refLayerIdx);

  // 3. Positron Dark uses Esri World Dark Gray Base + Reference labels with high-contrast dark outlines
  const darkStyle = wb.buildMapLibreGeospatialStyle(null, baseVis, { basemap: 'positron-dark' });
  assert.deepEqual(plain(darkStyle.sources.vpro_basemap_base.tiles), [
    'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}',
  ]);
  assert.equal(darkStyle.layers.find((l) => l.id === 'vpro-ocean-background').paint['background-color'], '#002244');
  assert.equal(darkStyle.layers.find((l) => l.id === 'bgc-subzone-outline').paint['line-color'], '#D8D8D8');
  assert.equal(darkStyle.layers.find((l) => l.id === 'ecosections-outline').paint['line-color'], '#FFFFFF');

  // 4. BC Gov Topographic routes through same-origin Go proxy /maps/bc-proxy/basemap/{z}/{y}/{x}
  const bcTopoStyle = wb.buildMapLibreGeospatialStyle(null, baseVis, { basemap: 'bc-gov-topo' });
  assert.deepEqual(plain(bcTopoStyle.sources.vpro_basemap_base.tiles), ['/maps/bc-proxy/basemap/{z}/{y}/{x}']);
  assert.match(bcTopoStyle.sources.vpro_basemap_base.attribution, /Government of British Columbia/);
  assert.equal(bcTopoStyle.sources.vpro_basemap_reference, undefined);

  // 5. Satellite Imagery uses Esri World Imagery
  const satStyle = wb.buildMapLibreGeospatialStyle(null, baseVis, { basemap: 'satellite' });
  assert.deepEqual(plain(satStyle.sources.vpro_basemap_base.tiles), [
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
  ]);

  // 6. Proxied BC OpenMaps WMS overlays replace broken DRA layer and respect custom opacity
  const wmsParks = wb.buildMapLibreGeospatialStyle(
    null,
    { ...baseVis, bcOpenMapsWMS: true },
    { wmsLayer: 'bc-parks', opacity: { bgc: 0.35, admin: 0.6, wms: 0.88 } }
  );
  assert.equal(
    wmsParks.sources.bc_openmaps_wms.tiles[0],
    '/maps/bc-proxy/wms/ows?layers=pub%3AWHSE_TANTALIS.TA_PARK_ECORES_PA_SVW&bbox={bbox-epsg-3857}&width=256&height=256'
  );
  assert.doesNotMatch(wmsParks.sources.bc_openmaps_wms.tiles[0], /DRA_DGTL_ROAD_ATLAS_MPAR_SP/);
  assert.equal(wmsParks.layers.find((l) => l.id === 'bgc-zones-fill').paint['fill-opacity'], 0.35);
  assert.equal(wmsParks.layers.find((l) => l.id === 'ecosections-outline').paint['line-opacity'], 0.6);
  assert.equal(wmsParks.layers.find((l) => l.id === 'nr-districts-outline').paint['line-opacity'], 0.6);
  assert.equal(wmsParks.layers.find((l) => l.id === 'bc-openmaps-wms-layer').paint['raster-opacity'], 0.88);

  const wmsRelief = wb.buildMapLibreGeospatialStyle(
    null,
    { ...baseVis, bcOpenMapsWMS: true },
    { wmsLayer: 'bc-painted-relief' }
  );
  assert.equal(
    wmsRelief.sources.bc_openmaps_wms.tiles[0],
    '/maps/bc-proxy/wms/imagex?layers=hillshade_bc_bc_xc50m_bcalb_painted_relief&bbox={bbox-epsg-3857}&width=256&height=256'
  );
});

test('applyMapLayerOpacity updates existing layer paint properties smoothly without setStyle', () => {
  const calls = [];
  const presentLayers = new Set(['bgc-zones-fill', 'bgc-subzone-outline', 'ecosections-outline', 'bc-openmaps-wms-layer']);
  let setStyleCalls = 0;
  const mockMap = {
    getLayer: (id) => (presentLayers.has(id) ? { id } : undefined),
    setPaintProperty: (id, prop, val) => calls.push([id, prop, val]),
    setStyle: () => {
      setStyleCalls++;
    },
  };

  const applied = wb.applyMapLayerOpacity(mockMap, { bgc: 0.25, admin: 1.4, wms: -0.2 });
  assert.equal(setStyleCalls, 0);
  assert.deepEqual(plain(applied), ['bgc-zones-fill', 'bgc-subzone-outline', 'ecosections-outline', 'bc-openmaps-wms-layer']);
  assert.deepEqual(calls, [
    ['bgc-zones-fill', 'fill-opacity', 0.25],
    ['bgc-subzone-outline', 'line-opacity', 0.29],
    ['ecosections-outline', 'line-opacity', 1],
    ['bc-openmaps-wms-layer', 'raster-opacity', 0],
  ]);

  // Zero BGC opacity also fades subzone outline to 0
  calls.length = 0;
  wb.applyMapLayerOpacity(mockMap, { bgc: 0, admin: 0.5, wms: 0.5 });
  assert.deepEqual(calls.slice(0, 2), [
    ['bgc-zones-fill', 'fill-opacity', 0],
    ['bgc-subzone-outline', 'line-opacity', 0],
  ]);
});

test('GeospatialWorkbench applyLayerOpacity never calls setStyle and online basemaps warn gracefully when offline', () => {
  const { createNotificationController } = loadTypeScript('shell/notificationService.svelte.ts', {
    'svelte/store': require('svelte/store'),
  });
  const notifications = createNotificationController({ schedule: () => 0, cancelSchedule: () => {} });

  const paintCalls = [];
  let setStyleCalls = 0;
  const mockMap = {
    getLayer: (id) => ({ id }),
    setPaintProperty: (id, prop, val) => paintCalls.push([id, prop, val]),
    setStyle: () => {
      setStyleCalls++;
    },
    easeTo() {},
    once() {},
  };

  const host = componentFunctions('GeospatialWorkbench.svelte', ['applyLayerOpacity', 'applyLayerVisibilities'], {
    project: 'Sample',
    alive: true,
    visibility: { ...wb.INITIAL_LAYER_VISIBILITY, bcOpenMapsWMS: false },
    basemap: 'positron-light',
    wmsLayer: 'bc-parks',
    layerOpacity: { bgc: 0.4, admin: 0.7, wms: 0.8 },
    wmsOfflineWarning: '',
    basemapOfflineWarning: '',
    pmtilesGraticuleFallback: false,
    mapInstance: mockMap,
    payload: null,
    navigator: { onLine: false },
    classifyWMSMapError: wb.classifyWMSMapError,
    buildMapLibreGeospatialStyle: wb.buildMapLibreGeospatialStyle,
    syncAOIOverlay() {},
    geoOps: wb,
    $state: { snapshot: (v) => v },
    notifications,
  });

  // Slider drag only calls setPaintProperty, never setStyle
  host.actions.applyLayerOpacity();
  assert.equal(setStyleCalls, 0);
  assert.equal(paintCalls.length, 5);
  assert.deepEqual(paintCalls[0], ['bgc-zones-fill', 'fill-opacity', 0.4]);

  // Switching to online basemap while offline triggers a non-blocking warning and still rebuilds style cleanly
  host.actions.applyLayerVisibilities();
  assert.equal(setStyleCalls, 1);
  assert.match(host.basemapOfflineWarning, /Light Gray \(Positron-style\).*offline/i);
  assert.equal(notifications.getSnapshot().entries.length, 1);
  assert.equal(notifications.getSnapshot().entries[0].title, 'Online basemap offline');
});

test('classifyBasemapError and classifyWMSMapError handle offline and proxied tile failures independently', () => {
  assert.equal(wb.classifyBasemapError({ sourceId: 'vpro_basemap_base' }, 'offline-neutral', false), null);
  assert.match(wb.classifyBasemapError({}, 'bc-gov-topo', false), /BC Gov Topographic.*unavailable while offline/i);
  assert.match(
    wb.classifyBasemapError({ sourceId: 'vpro_basemap_base', error: new Error('Failed to fetch') }, 'positron-light', true),
    /Light Gray \(Positron-style\) basemap tiles could not be loaded/i
  );
  assert.match(
    wb.classifyBasemapError({ error: { url: '/maps/bc-proxy/basemap/6/21/10' } }, 'bc-gov-topo', true),
    /BC Gov Topographic basemap tiles could not be loaded/i
  );
  assert.equal(
    wb.classifyWMSMapError({ sourceId: 'vpro_basemap_base', error: new Error('Failed to fetch') }, true, true),
    null
  );
  assert.match(
    wb.classifyWMSMapError({ error: { url: '/maps/bc-proxy/wms/ows?layers=pub:WHSE_TANTALIS.TA_PARK_ECORES_PA_SVW' } }, true, true),
    /WMS tile request failed/i
  );
});

test('SpatialWorkbenchHeader and SpatialMapLegend render accessible basemap, WMS overlay, opacity sliders, and attribution', () => {
  const headerSrc = readFileSync(srcPath('spatial/SpatialWorkbenchHeader.svelte'), 'utf8');
  const legendSrc = readFileSync(srcPath('spatial/SpatialMapLegend.svelte'), 'utf8');
  const stageSrc = readFileSync(srcPath('spatial/GeospatialMapStage.svelte'), 'utf8');

  for (const [name, src] of [
    ['SpatialWorkbenchHeader.svelte', headerSrc],
    ['SpatialMapLegend.svelte', legendSrc],
    ['GeospatialMapStage.svelte', stageSrc],
  ]) {
    const compiled = compile(src, { filename: name, generate: 'client' });
    assert.equal(compiled.warnings.length, 0, `${name} emitted compiler warnings`);
    assert.equal(/[\p{Extended_Pictographic}]/u.test(src), false, `${name} must contain zero emojis`);
  }

  const HeaderSSR = serverComponent(headerSrc, 'SpatialWorkbenchHeader.svelte', {
    './geospatialWorkbench': wb,
  });
  const headerHtml = render(HeaderSSR, {
    props: {
      contextId: 'ctx-map-ui',
      project: 'Sample',
      computeInfo: wb.INITIAL_COMPUTE_INFO,
      visibility: { ...wb.INITIAL_LAYER_VISIBILITY, bcOpenMapsWMS: true },
      basemap: 'positron-dark',
      wmsLayer: 'bc-painted-relief',
      layerOpacity: { bgc: 0.45, admin: 0.8, wms: 0.65 },
      onApplyLayers() {},
      onApplyOpacity() {},
      onRefreshDeck() {},
      onFitBounds() {},
      onRefreshStream() {},
      onToggleGpkgPanel() {},
    },
  }).body;

  assert.match(headerHtml, /id="wb-basemap-select"/);
  assert.match(headerHtml, /Offline Neutral/);
  assert.match(headerHtml, /Light Gray \(Positron-style\)/);
  assert.match(headerHtml, /Dark Gray \(Positron Dark-style\)/);
  assert.match(headerHtml, /BC Gov Topographic/);
  assert.match(headerHtml, /Satellite Imagery/);
  assert.match(headerHtml, /id="wb-wms-layer-select"/);
  assert.match(headerHtml, /BC Parks &amp; Protected Areas/);
  assert.match(headerHtml, /BC 50m Painted Relief/);
  assert.match(headerHtml, /id="wb-opacity-bgc"[^>]*type="range"[^>]*aria-valuetext="45%"/);
  assert.match(headerHtml, /id="wb-opacity-admin"[^>]*type="range"[^>]*aria-valuetext="80%"/);
  assert.match(headerHtml, /id="wb-opacity-wms"[^>]*type="range"[^>]*aria-valuetext="65%"/);
  assert.match(headerHtml, /45%/);
  assert.match(headerHtml, /80%/);
  assert.match(headerHtml, /65%/);

  const LegendSSR = serverComponent(legendSrc, 'SpatialMapLegend.svelte', {
    './geospatialWorkbench': wb,
  });
  const legendHtml = render(LegendSSR, {
    props: {
      aoiMatchedCount: 3,
      viewportMatchedCount: 12,
      basemap: 'bc-gov-topo',
      bcOpenMapsWMS: true,
      wmsLayer: 'bc-parks',
    },
  }).body;
  assert.match(legendHtml, /Government of British Columbia, DataBC/);
  assert.match(legendHtml, /BC Parks &amp; Protected Areas/);
});
