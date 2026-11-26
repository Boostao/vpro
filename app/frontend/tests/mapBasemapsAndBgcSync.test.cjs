const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { compile } = require('svelte/compiler');
const { render } = require('svelte/server');
const {
  componentFunctions,
  loadTypeScript,
  serverComponent,
  srcPath,
} = require('./svelteTestHelpers.cjs');

const wb = loadTypeScript('spatial/geospatialWorkbench.ts');
const plain = (value) => JSON.parse(JSON.stringify(value));

test('Track 2D: common hybrid basemaps (Esri Hybrid, Google Hybrid, OpenStreetMap, BC Gov Topo, Offline Neutral) build valid styles and safe fallbacks', () => {
  const ids = wb.MAP_BASEMAP_OPTIONS.map((opt) => opt.id);
  for (const requiredId of [
    'offline-neutral',
    'esri-hybrid',
    'google-hybrid',
    'osm-standard',
    'bc-gov-topo',
    'satellite',
    'positron-light',
    'positron-dark',
  ]) {
    assert.ok(ids.includes(requiredId), `Missing basemap option ${requiredId}`);
  }
  assert.equal(wb.getMapBasemapOption('esri-hybrid').label, 'Satellite Hybrid (Imagery + Labels)');
  assert.equal(wb.getMapBasemapOption('google-hybrid').label, 'Google Hybrid');
  assert.equal(wb.getMapBasemapOption('osm-standard').label, 'OpenStreetMap');

  const vis = {
    bgcFill: true,
    bgcLabels: true,
    ecosections: false,
    nrDistricts: false,
    forestRegions: false,
    hillshade3D: false,
    bcOpenMapsWMS: false,
    discrepancyVectors: true,
  };

  // 1. Esri Satellite Hybrid renders World Imagery base + Reference Boundaries & Places overlay above BGC zones
  const esriHybrid = wb.buildMapLibreGeospatialStyle(null, vis, { basemap: 'esri-hybrid' });
  assert.deepEqual(plain(esriHybrid.sources.vpro_basemap_base.tiles), [
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
  ]);
  assert.deepEqual(plain(esriHybrid.sources.vpro_basemap_reference.tiles), [
    'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
  ]);
  const baseIdx = esriHybrid.layers.findIndex((l) => l.id === 'vpro-basemap-base-layer');
  const bgcIdx = esriHybrid.layers.findIndex((l) => l.id === 'bgc-zones-fill');
  const refIdx = esriHybrid.layers.findIndex((l) => l.id === 'vpro-basemap-reference-layer');
  assert.ok(baseIdx > 0 && baseIdx < bgcIdx && bgcIdx < refIdx, 'Hybrid reference labels must render above BGC polygons');

  // 2. OpenStreetMap uses standard OSM raster tiles and light surface
  const osmStyle = wb.buildMapLibreGeospatialStyle(null, vis, { basemap: 'osm-standard' });
  assert.deepEqual(plain(osmStyle.sources.vpro_basemap_base.tiles), [
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  ]);
  assert.equal(osmStyle.sources.vpro_basemap_reference, undefined);
  assert.match(osmStyle.sources.vpro_basemap_base.attribution, /OpenStreetMap contributors/);
  assert.equal(osmStyle.layers.find((l) => l.id === 'vpro-ocean-background').paint['background-color'], '#F2F2F2');

  // 3. Google Hybrid without key/URL falls back seamlessly to Esri Satellite Hybrid with an honest plain-language note
  const unconfiguredGoogle = wb.resolveGoogleHybridBasemap(null);
  assert.equal(unconfiguredGoogle.configured, false);
  assert.equal(unconfiguredGoogle.fallbackActive, true);
  assert.deepEqual(plain(unconfiguredGoogle.baseTiles), [wb.ESRI_IMAGERY_TILE_URL]);
  assert.deepEqual(plain(unconfiguredGoogle.referenceTiles), [wb.ESRI_BOUNDARIES_LABELS_TILE_URL]);
  assert.match(unconfiguredGoogle.statusNote, /Satellite Hybrid \(Imagery \+ Labels\)/);
  assert.match(unconfiguredGoogle.statusNote, /Google Maps tile URL/i);

  const googleFallbackStyle = wb.buildMapLibreGeospatialStyle(null, vis, { basemap: 'google-hybrid' });
  assert.deepEqual(plain(googleFallbackStyle.sources.vpro_basemap_base.tiles), [wb.ESRI_IMAGERY_TILE_URL]);
  assert.deepEqual(plain(googleFallbackStyle.sources.vpro_basemap_reference.tiles), [wb.ESRI_BOUNDARIES_LABELS_TILE_URL]);

  // 4. Google Hybrid with configured HTTPS template + API key uses Google tile URL directly
  const configuredGoogle = wb.resolveGoogleHybridBasemap({
    tileUrlTemplate: 'https://tile.googleapis.com/v1/2dtiles/{z}/{x}/{y}?session=demo-session&key={key}',
    apiKey: 'AIza-demo-key',
  });
  assert.equal(configuredGoogle.configured, true);
  assert.equal(configuredGoogle.fallbackActive, false);
  assert.deepEqual(plain(configuredGoogle.baseTiles), [
    'https://tile.googleapis.com/v1/2dtiles/{z}/{x}/{y}?session=demo-session&key=AIza-demo-key',
  ]);
  assert.equal(configuredGoogle.referenceTiles, undefined);
  assert.equal(configuredGoogle.attribution, 'Google Maps');

  const googleActiveStyle = wb.buildMapLibreGeospatialStyle(null, vis, {
    basemap: 'google-hybrid',
    googleHybrid: {
      tileUrlTemplate: 'https://tile.googleapis.com/v1/2dtiles/{z}/{x}/{y}?session=demo-session&key={key}',
      apiKey: 'AIza-demo-key',
    },
  });
  assert.deepEqual(plain(googleActiveStyle.sources.vpro_basemap_base.tiles), [
    'https://tile.googleapis.com/v1/2dtiles/{z}/{x}/{y}?session=demo-session&key=AIza-demo-key',
  ]);
  assert.equal(googleActiveStyle.sources.vpro_basemap_reference, undefined);
  assert.equal(googleActiveStyle.sources.vpro_basemap_base.attribution, 'Google Maps');

  // 5. Rejects insecure HTTP remote URLs, javascript: URLs, or missing {z}/{x}/{y} placeholders
  assert.equal(wb.validateCustomTileTemplate('http://tiles.example.com/{z}/{x}/{y}.png').valid, false);
  assert.equal(wb.validateCustomTileTemplate('javascript:alert(1)/{z}/{x}/{y}').valid, false);
  assert.equal(wb.validateCustomTileTemplate('https://tile.googleapis.com/v1/2dtiles/missing').valid, false);
  assert.equal(wb.validateCustomTileTemplate('http://127.0.0.1:8080/tiles/{z}/{x}/{y}.png').valid, true);

  // 6. Storage round-trip and error classification for OpenStreetMap & Google Maps hosts
  const mem = new Map();
  const fakeStorage = {
    getItem: (k) => (mem.has(k) ? mem.get(k) : null),
    setItem: (k, v) => mem.set(k, v),
    removeItem: (k) => mem.delete(k),
  };
  wb.saveGoogleHybridConfig(
    { tileUrlTemplate: 'https://tiles.example.ca/{z}/{x}/{y}.png', apiKey: 'secret' },
    fakeStorage
  );
  assert.deepEqual(plain(wb.loadGoogleHybridConfig(fakeStorage)), {
    tileUrlTemplate: 'https://tiles.example.ca/{z}/{x}/{y}.png',
    apiKey: 'secret',
  });
  wb.saveGoogleHybridConfig({ tileUrlTemplate: '', apiKey: '' }, fakeStorage);
  assert.equal(mem.has(wb.GOOGLE_HYBRID_STORAGE_KEY), false);

  assert.match(
    wb.classifyBasemapError({ error: { url: 'https://tile.openstreetmap.org/7/19/41.png' } }, 'osm-standard', true),
    /OpenStreetMap basemap tiles could not be loaded/i
  );
  assert.match(
    wb.classifyBasemapError({ error: { url: 'https://tile.googleapis.com/v1/2dtiles/7/19/41' } }, 'google-hybrid', true),
    /Google Hybrid basemap tiles could not be loaded/i
  );
});

test('Track 2D: BC Forest Regions overlay renders all 8 regions from admin PMTiles and respects admin opacity', () => {
  assert.equal(wb.BC_FOREST_REGIONS.length, 8);
  assert.deepEqual(
    plain(wb.BC_FOREST_REGIONS.map((r) => r.code)),
    ['RCB', 'RKB', 'RNO', 'ROM', 'RSC', 'RSK', 'RTO', 'RWC']
  );

  const styleHidden = wb.buildMapLibreGeospatialStyle(null, {
    ...wb.INITIAL_LAYER_VISIBILITY,
    forestRegions: false,
  });
  const fillHidden = styleHidden.layers.find((l) => l.id === 'forest-regions-fill');
  const lineHidden = styleHidden.layers.find((l) => l.id === 'forest-regions-outline');
  assert.ok(fillHidden && lineHidden);
  assert.equal(fillHidden['source-layer'], 'nr_districts');
  assert.equal(fillHidden.layout.visibility, 'none');
  assert.equal(lineHidden.layout.visibility, 'none');

  const styleVisible = wb.buildMapLibreGeospatialStyle(
    null,
    {
      ...wb.INITIAL_LAYER_VISIBILITY,
      forestRegions: true,
    },
    { opacity: { bgc: 0.5, admin: 0.8, wms: 0.7 } }
  );
  const fillVis = styleVisible.layers.find((l) => l.id === 'forest-regions-fill');
  const lineVis = styleVisible.layers.find((l) => l.id === 'forest-regions-outline');
  assert.equal(fillVis.layout.visibility, 'visible');
  assert.equal(lineVis.layout.visibility, 'visible');
  assert.equal(fillVis.paint['fill-color'][0], 'match');
  assert.deepEqual(plain(fillVis.paint['fill-color'][1]), ['get', 'REGION_ORG_UNIT']);
  assert.equal(lineVis.paint['line-opacity'], 0.8);

  const paintCalls = [];
  const mockMap = {
    getLayer: (id) => (id.startsWith('forest-regions-') ? { id } : undefined),
    setPaintProperty: (id, prop, val) => paintCalls.push([id, prop, val]),
  };
  const applied = wb.applyMapLayerOpacity(mockMap, { admin: 0.5 });
  assert.deepEqual(plain(applied), ['forest-regions-fill', 'forest-regions-outline']);
  assert.deepEqual(paintCalls, [
    ['forest-regions-fill', 'fill-opacity', 0.14],
    ['forest-regions-outline', 'line-opacity', 0.5],
  ]);
});

test('Track 2D: SpatialWorkbenchHeader, SpatialMapLayersSyncTab, and GeospatialSidebarDrawer compile cleanly and enforce desktop vs IS_WEB_READONLY visibility', () => {
  const files = [
    'spatial/SpatialMapLayersSyncTab.svelte',
    'spatial/SpatialWorkbenchHeader.svelte',
    'spatial/GeospatialSidebarDrawer.svelte',
    'spatial/GeospatialMapStage.svelte',
    'spatial/SpatialMapLegend.svelte',
    'spatial/GeospatialWorkbench.svelte',
  ];
  const emojiRegex = /[\p{Extended_Pictographic}]/u;
  for (const rel of files) {
    const src = readFileSync(srcPath(rel), 'utf8');
    const compiled = compile(src, { filename: rel, generate: 'client' });
    assert.equal(compiled.warnings.length, 0, `${rel} emitted compiler warnings`);
    assert.equal(emojiRegex.test(src), false, `${rel} must contain zero emojis`);
    assert.doesNotMatch(src, /VITE_|import\.meta\.env/, `${rel} must not contain legacy VITE_* env flags`);
  }

  // 1. Header renders 1-click quick basemap pills, BC Forest Regions toggle, and Google Hybrid fallback note
  const HeaderSSR = serverComponent(
    readFileSync(srcPath('spatial/SpatialWorkbenchHeader.svelte'), 'utf8'),
    'spatial/SpatialWorkbenchHeader.svelte',
    {
      './geospatialWorkbench': wb,
      '../web/runtimeMode': { IS_WEB_READONLY: false },
    }
  );
  const headerHtml = render(HeaderSSR, {
    props: {
      contextId: 'ctx-2d',
      project: 'Sample',
      computeInfo: wb.INITIAL_COMPUTE_INFO,
      visibility: { ...wb.INITIAL_LAYER_VISIBILITY, forestRegions: true },
      basemap: 'google-hybrid',
      googleHybridConfig: { tileUrlTemplate: '', apiKey: '' },
      onApplyLayers() {},
      onApplyOpacity() {},
      onRefreshDeck() {},
      onFitBounds() {},
      onRefreshStream() {},
      onToggleGpkgPanel() {},
      onOpenLayersSyncTab() {},
    },
  }).body;
  assert.match(headerHtml, /data-quick-basemap-bar/);
  assert.match(headerHtml, /data-quick-basemap="esri-hybrid"/);
  assert.match(headerHtml, /data-quick-basemap="google-hybrid"/);
  assert.match(headerHtml, /data-quick-basemap="osm-standard"/);
  assert.match(headerHtml, /data-quick-basemap="bc-gov-topo"/);
  assert.match(headerHtml, /data-quick-basemap="offline-neutral"/);
  assert.match(headerHtml, /Satellite Hybrid \(Imagery \+ Labels\)/);
  assert.match(headerHtml, /Google Hybrid/);
  assert.match(headerHtml, /OpenStreetMap/);
  assert.match(headerHtml, /BC Forest Regions/);
  assert.match(headerHtml, /data-toolbar-google-fallback/);
  assert.match(headerHtml, /Configure in Map &amp; Sync/);

  // 2. Desktop mode Map & Sync tab shows all 8 basemaps, Forest Regions legend, and BGC Base Map Sync section
  const desktopSyncStatus = {
    archiveName: 'bc-bgc-v13.pmtiles',
    targetPath: '/home/user/.local/share/vpro/maps/bc-bgc-v13.pmtiles',
    activeSource: 'embedded-overview',
    available: true,
    fullResolution: false,
    fallbackOverview: true,
    minZoom: 3,
    maxZoom: 6,
    sizeBytes: 184320,
    modTime: '2026-01-01T00:00:00Z',
    defaultSourceUrl: 'https://maps.example.gov.bc.ca/bc-bgc-v13.pmtiles',
  };
  const DesktopTabSSR = serverComponent(
    readFileSync(srcPath('spatial/SpatialMapLayersSyncTab.svelte'), 'utf8'),
    'spatial/SpatialMapLayersSyncTab.svelte',
    {
      './geospatialWorkbench': wb,
      '../web/runtimeMode': { IS_WEB_READONLY: false },
    }
  );
  const desktopTabHtml = render(DesktopTabSSR, {
    props: {
      basemap: 'google-hybrid',
      visibility: { ...wb.INITIAL_LAYER_VISIBILITY, forestRegions: true },
      googleHybridConfig: { tileUrlTemplate: '', apiKey: '' },
      bgcSyncStatus: desktopSyncStatus,
      bgcSyncUrl: desktopSyncStatus.defaultSourceUrl,
      bgcSyncSha256: '',
      bgcLastSyncResult: {
        archiveName: 'bc-bgc-v13.pmtiles',
        targetPath: desktopSyncStatus.targetPath,
        sourceUrl: desktopSyncStatus.defaultSourceUrl,
        sizeBytes: 54_525_952,
        sha256: 'a1b2c3d4e5f60000000000000000000000000000000000000000000000000000',
        checksumSource: 'companion',
        minZoom: 3,
        maxZoom: 10,
        syncedAt: '2026-11-26T18:30:00Z',
        status: { ...desktopSyncStatus, activeSource: 'dataDir', fullResolution: true, maxZoom: 10, sizeBytes: 54_525_952 },
      },
      onApplyLayers() {},
      onSaveGoogleHybridConfig() {},
      onRefreshBgcSyncStatus() {},
      onSyncLatestBgcMap() {},
    },
  }).body;
  assert.match(desktopTabHtml, /data-basemap-option="esri-hybrid"/);
  assert.match(desktopTabHtml, /data-basemap-option="google-hybrid"/);
  assert.match(desktopTabHtml, /data-basemap-option="osm-standard"/);
  assert.match(desktopTabHtml, /data-google-hybrid-note/);
  assert.match(desktopTabHtml, /id="wb-google-tile-url"/);
  assert.match(desktopTabHtml, /data-forest-regions-legend/);
  assert.match(desktopTabHtml, /Cariboo-Chilcotin/);
  assert.match(desktopTabHtml, /data-bgc-sync-section/);
  assert.match(desktopTabHtml, /BGC Base Map Sync/);
  assert.match(desktopTabHtml, /Built-in BC overview map/);
  assert.match(desktopTabHtml, /180 KB/);
  assert.match(desktopTabHtml, /2026-01-01 00:00 UTC/);
  assert.match(desktopTabHtml, /id="wb-bgc-sync-url"/);
  assert.match(desktopTabHtml, /id="wb-bgc-sync-sha256"/);
  assert.match(desktopTabHtml, /Sync Latest BGC Map/);
  assert.match(desktopTabHtml, /Map updated and reloaded live/);
  assert.match(desktopTabHtml, /52\.00 MB/);

  // 3. Web read-only mode hides BGC Base Map Sync & Google config write inputs while keeping basemaps & overlays
  const WebTabSSR = serverComponent(
    readFileSync(srcPath('spatial/SpatialMapLayersSyncTab.svelte'), 'utf8'),
    'spatial/SpatialMapLayersSyncTab.svelte',
    {
      './geospatialWorkbench': wb,
      '../web/runtimeMode': { IS_WEB_READONLY: true },
    }
  );
  const webTabHtml = render(WebTabSSR, {
    props: {
      basemap: 'google-hybrid',
      visibility: { ...wb.INITIAL_LAYER_VISIBILITY },
      googleHybridConfig: { tileUrlTemplate: '', apiKey: '' },
      bgcSyncStatus: desktopSyncStatus,
      onApplyLayers() {},
      onSaveGoogleHybridConfig() {},
    },
  }).body;
  assert.match(webTabHtml, /data-basemap-option="esri-hybrid"/);
  assert.match(webTabHtml, /data-google-hybrid-note/);
  assert.doesNotMatch(webTabHtml, /data-bgc-sync-section/);
  assert.doesNotMatch(webTabHtml, /Sync Latest BGC Map/);
  assert.doesNotMatch(webTabHtml, /id="wb-google-tile-url"/);

  const WebDrawerSSR = serverComponent(
    readFileSync(srcPath('spatial/GeospatialSidebarDrawer.svelte'), 'utf8'),
    'spatial/GeospatialSidebarDrawer.svelte',
    {
      './geospatialWorkbench': wb,
      '../web/runtimeMode': { IS_WEB_READONLY: true },
      '../../bindings/github.com/boostao/vpro/app': { SpatialService: {} },
    }
  );
  const webDrawerHtml = render(WebDrawerSSR, {
    props: {
      contextId: 'ctx-web',
      project: 'BECMaster',
      su: 'None',
      activePanel: 'layers',
      onInspectPlot() {},
      getViewportBounds: () => null,
      onSyncAOIOverlay() {},
      onRunMutation: async () => {},
      onPushError() {},
      onCommittedAOI: async () => {},
      onLoadBatchAuditQA() {},
      onApplyStamp() {},
    },
  }).body;
  assert.match(webDrawerHtml, />Basemaps</);
  assert.doesNotMatch(webDrawerHtml, /BGC Base Map Sync/);
});

test('Track 2D: GeospatialWorkbench loads BGC sync status and hot-reloads MapLibre BGC PMTiles layer immediately on SyncLatestBGCMap', async () => {
  const { createNotificationController } = loadTypeScript('shell/notificationService.svelte.ts', {
    'svelte/store': require('svelte/store'),
  });
  const notifications = createNotificationController({ schedule: () => 0, cancelSchedule: () => {} });

  // Register a mock PMTiles protocol instance so we can verify cache eviction on sync
  const cachedTiles = new Map([
    ['/maps/bc-bgc-v13.pmtiles', { mock: 'stale-bgc-reader' }],
    ['/maps/bc-admin-ecosections-districts.pmtiles', { mock: 'admin-reader' }],
  ]);
  const freshWb = loadTypeScript('spatial/geospatialWorkbench.ts');
  freshWb.ensureMapLibrePMTilesProtocol(
    () => {},
    '/worker.js',
    () => {},
    class MockProtocol {
      tiles = cachedTiles;
      tile = () => {};
    }
  );

  const appliedStyles = [];
  const mockMap = {
    setStyle(style) {
      appliedStyles.push(style);
    },
    easeTo() {},
    once() {},
  };

  let syncRpcArgs = null;
  const syncedResult = {
    archiveName: 'bc-bgc-v13.pmtiles',
    targetPath: '/data/maps/bc-bgc-v13.pmtiles',
    sourceUrl: 'https://maps.example.gov.bc.ca/bc-bgc-v13.pmtiles',
    sizeBytes: 58_720_256,
    sha256: 'deadbeef1234567890abcdef1234567890abcdef1234567890abcdef12345678',
    checksumSource: 'explicit',
    minZoom: 3,
    maxZoom: 10,
    syncedAt: '2026-11-26T19:00:00Z',
    status: {
      archiveName: 'bc-bgc-v13.pmtiles',
      targetPath: '/data/maps/bc-bgc-v13.pmtiles',
      activeSource: 'dataDir',
      available: true,
      fullResolution: true,
      fallbackOverview: false,
      minZoom: 3,
      maxZoom: 10,
      sizeBytes: 58_720_256,
      modTime: '2026-11-26T19:00:00Z',
      sha256: 'deadbeef1234567890abcdef1234567890abcdef1234567890abcdef12345678',
      defaultSourceUrl: 'https://maps.example.gov.bc.ca/bc-bgc-v13.pmtiles',
    },
  };

  const host = componentFunctions(
    'spatial/GeospatialWorkbench.svelte',
    ['loadBgcMapSyncStatus', 'syncLatestBgcMap', 'applyLayerVisibilities'],
    {
      IS_WEB_READONLY: false,
      project: 'Sample',
      alive: true,
      loading: false,
      mutating: false,
      gpkgExporting: false,
      errorMsg: '',
      statusMsg: '',
      wmsOfflineWarning: '',
      basemapOfflineWarning: '',
      pmtilesArchiveWarning: 'old warning',
      pmtilesGraticuleFallback: true,
      syncStatusGeneration: 0,
      bgcSyncStatus: null,
      bgcSyncLoading: false,
      bgcSyncBusy: false,
      bgcSyncUrl: '',
      bgcSyncSha256: '',
      bgcSyncError: '',
      bgcLastSyncResult: null,
      bgcTileRevision: '',
      visibility: { ...freshWb.INITIAL_LAYER_VISIBILITY },
      basemap: 'esri-hybrid',
      wmsLayer: 'bc-parks',
      layerOpacity: { ...freshWb.INITIAL_LAYER_OPACITY },
      googleHybridConfig: { tileUrlTemplate: '', apiKey: '' },
      mapInstance: mockMap,
      payload: {
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
              sizeBytes: 184320,
            },
          },
          ordered: [],
        },
      },
      navigator: { onLine: true },
      geoOps: freshWb,
      buildMapLibreGeospatialStyle: freshWb.buildMapLibreGeospatialStyle,
      classifyWMSMapError: freshWb.classifyWMSMapError,
      summarizePMTilesManifestWarnings: freshWb.summarizePMTilesManifestWarnings,
      syncAOIOverlay() {},
      setBusyState() {},
      formatError: (e) => (e instanceof Error ? e.message : String(e)),
      $state: { snapshot: (v) => v },
      notifications,
      SpatialService: {
        async GetBGCMapSyncStatus() {
          return {
            archiveName: 'bc-bgc-v13.pmtiles',
            targetPath: '/data/maps/bc-bgc-v13.pmtiles',
            activeSource: 'embedded-overview',
            available: true,
            fullResolution: false,
            fallbackOverview: true,
            minZoom: 3,
            maxZoom: 6,
            sizeBytes: 184320,
            defaultSourceUrl: 'https://maps.example.gov.bc.ca/bc-bgc-v13.pmtiles',
          };
        },
        async SyncLatestBGCMap(url, sha) {
          syncRpcArgs = [url, sha];
          return syncedResult;
        },
        async GetPMTilesManifest() {
          return {
            schemaVersion: 1,
            archives: {
              'bc-bgc-v13.pmtiles': {
                name: 'bc-bgc-v13.pmtiles',
                url: '/maps/bc-bgc-v13.pmtiles',
                source: 'dataDir',
                available: true,
                fullResolution: true,
                fallbackOverview: false,
                minZoom: 3,
                maxZoom: 10,
                sizeBytes: 58_720_256,
              },
            },
            ordered: [],
          };
        },
      },
    }
  );

  // 1. Load status prefills default sync URL
  await host.actions.loadBgcMapSyncStatus();
  assert.equal(host.bgcSyncStatus.activeSource, 'embedded-overview');
  assert.equal(host.bgcSyncUrl, 'https://maps.example.gov.bc.ca/bc-bgc-v13.pmtiles');

  // 2. Sync calls SpatialService.SyncLatestBGCMap, evicts stale PMTiles cache, updates manifest, and hot-reloads MapLibre style
  await host.actions.syncLatestBgcMap(
    'https://maps.example.gov.bc.ca/bc-bgc-v13.pmtiles',
    'deadbeef1234567890abcdef1234567890abcdef1234567890abcdef12345678'
  );
  assert.deepEqual(syncRpcArgs, [
    'https://maps.example.gov.bc.ca/bc-bgc-v13.pmtiles',
    'deadbeef1234567890abcdef1234567890abcdef1234567890abcdef12345678',
  ]);
  assert.equal(cachedTiles.has('/maps/bc-bgc-v13.pmtiles'), false, 'Stale BGC PMTiles cache entry must be evicted');
  assert.equal(cachedTiles.has('/maps/bc-admin-ecosections-districts.pmtiles'), true, 'Admin PMTiles cache stays warm');
  assert.equal(host.bgcSyncStatus.activeSource, 'dataDir');
  assert.equal(host.bgcSyncStatus.fullResolution, true);
  assert.equal(host.pmtilesGraticuleFallback, false);
  assert.equal(host.pmtilesArchiveWarning, '');
  assert.equal(appliedStyles.length, 1, 'MapLibre setStyle must fire immediately to hot-reload synced BGC tiles');
  assert.equal(
    appliedStyles[0].sources.bc_bgc_pmtiles.url,
    'pmtiles:///maps/bc-bgc-v13.pmtiles?v=deadbeef1234'
  );
  assert.equal(appliedStyles[0].sources.bc_bgc_pmtiles.maxzoom, 10);
  assert.match(host.statusMsg, /reloaded the map live/i);
  assert.equal(notifications.getSnapshot().entries[0].severity, 'success');
  assert.equal(notifications.getSnapshot().entries[0].title, 'BGC base map updated');

  // 3. Web read-only mode blocks sync completely
  host.IS_WEB_READONLY = true;
  syncRpcArgs = null;
  await host.actions.syncLatestBgcMap('https://maps.example.gov.bc.ca/bc-bgc-v13.pmtiles', '');
  assert.equal(syncRpcArgs, null, 'SyncLatestBGCMap must never be invoked in IS_WEB_READONLY web mode');
});
