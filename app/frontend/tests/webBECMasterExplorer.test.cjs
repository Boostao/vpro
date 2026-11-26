const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const vm = require('node:vm');
const ts = require('typescript');
const { compile } = require('svelte/compiler');
const { render } = require('svelte/server');
const { writable } = require('svelte/store');

const FE_ROOT = path.resolve(__dirname, '..');
const SRC_ROOT = path.join(FE_ROOT, 'src');

function readSrc(relPath) {
  return readFileSync(path.join(SRC_ROOT, relPath), 'utf8');
}

function transpileTs(filePath) {
  const source = readFileSync(filePath, 'utf8');
  return ts.transpileModule(source, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
      esModuleInterop: true,
    },
  }).outputText;
}

function runTsModule(relPath, deps = {}, globals = {}) {
  const filePath = path.join(SRC_ROOT, relPath);
  const mod = { exports: {} };
  const ctx = {
    URL,
    URLSearchParams,
    Error,
    TypeError,
    Promise,
    Object,
    Array,
    Map,
    Set,
    Symbol,
    JSON,
    Math,
    Date,
    Number,
    String,
    Boolean,
    encodeURIComponent,
    decodeURIComponent,
    console,
    ...globals,
    module: mod,
    exports: mod.exports,
    require(specifier) {
      if (Object.hasOwn(deps, specifier)) {
        return deps[specifier];
      }
      if (specifier === 'svelte/store') {
        return { writable };
      }
      throw new Error(`Unexpected require("${specifier}") in ${relPath}`);
    },
  };
  ctx.globalThis = ctx;
  vm.runInNewContext(transpileTs(filePath), ctx, { filename: filePath });
  return mod.exports;
}

function compileSvelte(relPath, generate = 'client') {
  const source = readSrc(relPath);
  const compiled = compile(source, {
    filename: path.join(SRC_ROOT, relPath),
    generate,
    dev: false,
  });
  assert.equal(
    compiled.warnings.length,
    0,
    `${relPath} (${generate}) compiled with warnings: ${compiled.warnings.map((w) => w.message).join('; ')}`
  );
  return compiled;
}

function loadServerComponent(relPath, deps = {}, globals = {}) {
  const compiled = compileSvelte(relPath, 'server');
  const cjs = ts.transpileModule(compiled.js.code, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
      esModuleInterop: true,
    },
  }).outputText;

  const iconStub = new Proxy(
    {},
    {
      get(_target, prop) {
        if (prop === '__esModule') return true;
        return () => '';
      },
    }
  );

  const mod = { exports: {} };
  const ctx = {
    URL,
    URLSearchParams,
    Error,
    TypeError,
    Promise,
    Object,
    Array,
    Map,
    Set,
    Symbol,
    JSON,
    Math,
    Date,
    Number,
    String,
    Boolean,
    console,
    ...globals,
    module: mod,
    exports: mod.exports,
    require(specifier) {
      if (Object.hasOwn(deps, specifier)) {
        return deps[specifier];
      }
      if (specifier === '@lucide/svelte') {
        return iconStub;
      }
      if (specifier.startsWith('svelte')) {
        return require(specifier);
      }
      throw new Error(`Unexpected require("${specifier}") in ${relPath}`);
    },
  };
  ctx.globalThis = ctx;
  vm.runInNewContext(cjs, ctx, { filename: relPath });
  return mod.exports.default;
}

function loadExplorerModules(globals = {}) {
  const stateMod = {
    projectState: writable(null),
    webMeta: writable(null),
    webShellRuntime: writable(null),
  };
  const runtimeMode = runTsModule('web/runtimeMode.ts', {}, { __VPRO_WEB_READONLY__: true, ...globals });
  const webMetaMod = runTsModule(
    'web/webMeta.ts',
    {
      '../shared/state': stateMod,
      './runtimeMode': runtimeMode,
    },
    { __VPRO_WEB_READONLY__: true, ...globals }
  );
  const downloaded = [];
  const wailsWebRuntimeStub = {
    triggerBrowserDownload(url, filename) {
      downloaded.push({ url, filename });
      return true;
    },
  };
  const filterMod = runTsModule(
    'web/webBECMasterFilter.ts',
    {
      './wailsWebRuntime': wailsWebRuntimeStub,
      './webMeta': webMetaMod,
    },
    { __VPRO_WEB_READONLY__: true, ...globals }
  );
  return { stateMod, runtimeMode, webMetaMod, filterMod, downloaded };
}

test('webMeta exposes externalLinks, licenceName, licenceUrl, citation, and rAvailable with safe defaults and sanitization', () => {
  const { webMetaMod } = loadExplorerModules();

  const defaults = webMetaMod.normalizeWebMeta({ snapshotId: 'snap-1' });
  assert.equal(defaults.externalLinks.length, 2);
  assert.equal(defaults.externalLinks[0].label, 'BECweb');
  assert.equal(defaults.externalLinks[0].url, 'https://www.for.gov.bc.ca/hre/becweb/');
  assert.equal(defaults.externalLinks[1].label, 'byBEC');
  assert.equal(defaults.externalLinks[1].url, 'https://thebeczone.ca/shiny/bybecmap/');
  assert.equal(defaults.licenceName, 'Open Government Licence – British Columbia');
  assert.match(defaults.licenceUrl, /open-government-licence-bc/);
  assert.match(defaults.citation, /BECMaster/);
  assert.equal(defaults.rAvailable, true);

  const custom = webMetaMod.normalizeWebMeta({
    rAvailable: false,
    external_links: [
      { label: 'BC Data Catalogue', url: 'https://catalogue.data.gov.bc.ca/', description: 'Open data' },
      { label: 'Unsafe', url: 'javascript:alert(1)' },
    ],
    licence_name: 'Custom Licence',
    licence_url: 'https://example.gov.bc.ca/licence',
    citation: 'Ministry of Forests BECMaster 2026.',
  });
  assert.equal(custom.rAvailable, false);
  assert.equal(custom.externalLinks.length, 1);
  assert.equal(custom.externalLinks[0].label, 'BC Data Catalogue');
  assert.equal(custom.licenceName, 'Custom Licence');
  assert.equal(custom.licenceUrl, 'https://example.gov.bc.ca/licence');
  assert.equal(custom.citation, 'Ministry of Forests BECMaster 2026.');

  const emptyLinks = webMetaMod.normalizeWebMeta({ externalLinks: [] });
  assert.deepEqual([...emptyLinks.externalLinks], []);
});

test('webBECMasterFilter HTTP client calls filter-options, filter, and download endpoints with session headers and 503 busy detection', async () => {
  const { filterMod, downloaded } = loadExplorerModules();
  const calls = [];

  const mockFetch = async (url, init) => {
    calls.push({ url, method: init.method, headers: init.headers, body: init.body });
    if (url.startsWith('/api/becmaster/filter-options')) {
      return {
        ok: true,
        status: 200,
        statusText: 'OK',
        text: async () =>
          JSON.stringify({
            contextId: 'ctx-1',
            project: 'BECMaster',
            totalPlots: 71567,
            regions: [{ code: 'RSK', label: 'Skeena' }],
            projects: [{ projectId: 'PRJ1', plotCount: 42 }],
            projectIds: ['PRJ1'],
            publications: [],
            hasPublicationLinks: false,
            zones: ['CWH', 'ICH'],
            subzonesByZone: { CWH: ['CWHvm1', 'CWHvh2'], ICH: ['ICHmc1'] },
            minYear: 1965,
            maxYear: 2026,
            successionalStatuses: [{ code: 'OC', label: 'Old Climax' }],
            structuralStages: [{ code: '7', label: 'Old Forest' }],
            sitePlotQualities: [{ code: 'Excellent', label: 'Excellent' }],
            vegPlotQualities: [{ code: 'Excellent', label: 'Excellent' }],
            soilPlotQualities: [{ code: 'Good', label: 'Good' }],
            locationAccuracies: [{ code: '<=10', label: '<10m' }],
          }),
      };
    }
    if (url === '/api/becmaster/filter') {
      return {
        ok: true,
        status: 200,
        statusText: 'OK',
        text: async () =>
          JSON.stringify({
            contextId: 'ctx-1',
            project: 'BECMaster',
            totalPlots: 71567,
            matchedCount: 2,
            plotNumbers: ['00337', '00412'],
            points: [
              { plotNumber: '00337', lat: 54.5, lon: -128.6, zone: 'CWH', subZone: 'ws1', siteSeries: '01', projectId: 'PRJ1', region: 'RSK' },
              { plotNumber: '00412', lat: 54.6, lon: -128.4, zone: 'ICH', subZone: 'mc1', siteSeries: '01', projectId: 'PRJ1', region: 'RSK' },
            ],
          }),
      };
    }
    if (url === '/api/becmaster/download') {
      const parsed = JSON.parse(init.body);
      if (parsed.format === 'rds') {
        return {
          ok: false,
          status: 503,
          statusText: 'Service Unavailable',
          text: async () => JSON.stringify({ error: 'export worker pool is busy; please retry shortly' }),
        };
      }
      return {
        ok: true,
        status: 200,
        statusText: 'OK',
        text: async () =>
          JSON.stringify({
            downloadUrl: '/api/downloads/tok-abc',
            filename: 'BECMaster-subset.db',
            format: 'vpro64',
            plotCount: 2,
            bytes: 131072,
          }),
      };
    }
    throw new Error(`Unexpected URL ${url}`);
  };

  const opts = await filterMod.fetchBECMasterFilterOptions('ctx-1', { fetchImpl: mockFetch });
  assert.equal(opts.totalPlots, 71567);
  assert.equal(calls[0].url, '/api/becmaster/filter-options?contextId=ctx-1');
  assert.ok(calls[0].headers['X-VPro-Session']);

  const filtered = await filterMod.filterBECMasterPlots(
    'ctx-1',
    { mode: 'region', regions: ['RSK'], zones: ['CWH'] },
    { fetchImpl: mockFetch }
  );
  assert.equal(filtered.matchedCount, 2);
  assert.deepEqual([...filtered.plotNumbers], ['00337', '00412']);
  assert.equal(JSON.parse(calls[1].body).filter.mode, 'region');

  const dl = await filterMod.downloadBECMasterSubset(
    { contextId: 'ctx-1', format: 'vpro64', plotNumbers: ['00337', '00412'] },
    { fetchImpl: mockFetch }
  );
  assert.equal(dl.filename, 'BECMaster-subset.db');
  assert.equal(downloaded.length, 1);
  assert.deepEqual(downloaded[0], { url: '/api/downloads/tok-abc', filename: 'BECMaster-subset.db' });

  await assert.rejects(
    filterMod.downloadBECMasterSubset(
      { contextId: 'ctx-1', format: 'rds', plotNumbers: ['00337'] },
      { fetchImpl: mockFetch }
    ),
    (err) => err instanceof filterMod.BECMasterHttpError && err.status === 503 && err.isBusy === true
  );
});

test('filter state composition, dynamic zone->subzone narrowing, bbox normalization, URL sync, and map style helpers work accurately', () => {
  const { filterMod } = loadExplorerModules();

  // Bounding box normalization handles inverted drags & positive West longitudes
  const norm = filterMod.normalizeBoundingBox([122.25, 51.1], [128.5, 55.4]);
  assert.deepEqual({ ...norm }, { nwLat: 55.4, nwLon: -128.5, seLat: 51.1, seLon: -122.25 });

  // Dynamic zone -> subzone narrowing
  const mapByZone = { CWH: ['CWHvh2', 'CWHvm1'], ICH: ['ICHmc1'], IDF: ['IDFdk3'] };
  assert.deepEqual([...filterMod.computeAvailableSubzones(mapByZone, ['CWH'])], ['CWHvh2', 'CWHvm1']);
  assert.deepEqual([...filterMod.computeAvailableSubzones(mapByZone, [])], ['CWHvh2', 'CWHvm1', 'ICHmc1', 'IDFdk3']);
  assert.deepEqual([...filterMod.pruneSelectedSubzones(['CWHvm1', 'ICHmc1'], ['CWHvh2', 'CWHvm1'])], ['CWHvm1']);

  // Composed filter request
  const state = {
    ...filterMod.createEmptyBECMasterFilterState(),
    mode: 'bbox',
    nwLat: '55.2',
    nwLon: '-128.9',
    seLat: '53.1',
    seLon: '-125.0',
    zones: ['CWH'],
    subzones: ['CWHvm1'],
    minYear: '1990',
    maxYear: '2024',
    successionalStatuses: ['OC'],
    structuralStages: ['7'],
    inPublicationsOnly: true,
    sitePlotQualities: ['Excellent'],
    vegPlotQualities: ['Good'],
    soilPlotQualities: ['Fair'],
    locationAccuracy: '<=10',
  };
  const req = filterMod.buildFilterRequestFromState(state);
  assert.equal(req.mode, 'bbox');
  assert.equal(req.nwLat, 55.2);
  assert.equal(req.nwLon, -128.9);
  assert.equal(req.seLat, 53.1);
  assert.equal(req.seLon, -125);
  assert.equal(req.minYear, 1990);
  assert.equal(req.maxYear, 2024);
  assert.equal(req.inPublicationsOnly, true);
  assert.equal(req.locationAccuracy, '<=10');
  assert.equal(filterMod.hasActiveFilterSelections(state), true);

  // URL round-trip preserves literal leading-zero PlotNumber and filter state
  const query = filterMod.formatExplorerUrlQuery({
    dataset: 'BECMaster',
    su: 'Master_SU',
    tab: 'datasheet',
    plot: '00337',
    filter: state,
  });
  const parsed = filterMod.parseExplorerUrlState(query);
  assert.equal(parsed.dataset, 'BECMaster');
  assert.equal(parsed.su, 'Master_SU');
  assert.equal(parsed.tab, 'datasheet');
  assert.equal(parsed.plot, '00337');
  assert.equal(parsed.filter.mode, 'bbox');
  assert.deepEqual([...parsed.filter.zones], ['CWH']);
  assert.equal(parsed.filter.inPublicationsOnly, true);
  assert.equal(parsed.filter.locationAccuracy, '<=10');

  // Idempotent replaceState
  const replaced = [];
  const fakeWin = {
    location: { pathname: '/', search: '', hash: '' },
    history: {
      replaceState(_d, _u, url) {
        replaced.push(url);
        const q = String(url).indexOf('?');
        fakeWin.location.search = q >= 0 ? String(url).slice(q) : '';
      },
    },
  };
  filterMod.syncExplorerUrlState({ plot: '00337', tab: 'map' }, fakeWin);
  filterMod.syncExplorerUrlState({ plot: '00337', tab: 'map' }, fakeWin);
  assert.deepEqual(replaced, ['/?plot=00337']);

  // All 5 basemaps + BGC v13 PMTiles style generation
  for (const bm of ['esri-hybrid', 'satellite', 'bc-gov-topo', 'osm', 'offline-neutral']) {
    const style = filterMod.buildWebExplorerMapStyle({
      basemap: bm,
      showBgcOverlay: true,
      pmtilesBaseUrl: '/pmtiles',
    });
    assert.equal(style.version, 8);
    assert.equal(style.sources.bc_bgc_pmtiles.url, 'pmtiles:///pmtiles/bc-bgc-v13.pmtiles');
  }
  const geo = filterMod.buildPlotsGeoJSON([
    { plotNumber: '00337', lat: 54.5, lon: -128.6, zone: 'CWH', subZone: 'ws1', siteSeries: '01', projectId: 'P1', region: 'RSK' },
  ]);
  assert.equal(geo.features.length, 1);
  assert.equal(geo.features[0].properties.plotNumber, '00337');
  const boxGeo = filterMod.buildBBoxGeoJSON(norm);
  assert.equal(boxGeo.features.length, 1);
});

test('all Track 2E Svelte components compile cleanly with zero warnings and render BEC_plots_Shiny parity controls', () => {
  for (const rel of [
    'web/WebFilterSidebar.svelte',
    'web/WebMapCanvas.svelte',
    'web/WebDownloadCard.svelte',
    'web/WebPlotCardDrawer.svelte',
    'web/WebBECMasterExplorer.svelte',
  ]) {
    compileSvelte(rel, 'client');
    compileSvelte(rel, 'server');
  }

  const { stateMod, webMetaMod, filterMod } = loadExplorerModules();
  const sampleOptions = {
    contextId: 'ctx-1',
    project: 'BECMaster',
    totalPlots: 71567,
    regions: [
      { code: 'RCB', label: 'Cariboo-Chilcotin' },
      { code: 'RSK', label: 'Skeena' },
      { code: 'RWC', label: 'West Coast' },
    ],
    projects: [{ projectId: 'Skeena_2024', title: 'Skeena BEC', plotCount: 310 }],
    projectIds: ['Skeena_2024'],
    publications: [{ id: 'LMH25', title: 'Field Manual for Describing Terrestrial Ecosystems' }],
    hasPublicationLinks: true,
    zones: ['CWH', 'ICH'],
    subzonesByZone: { CWH: ['CWHvm1', 'CWHvh2'], ICH: ['ICHmc1'] },
    minYear: 1965,
    maxYear: 2026,
    successionalStatuses: [{ code: 'OC', label: 'Old Climax' }],
    structuralStages: [{ code: '7', label: 'Old Forest' }],
    sitePlotQualities: [{ code: 'Excellent', label: 'Excellent' }],
    vegPlotQualities: [{ code: 'Good', label: 'Good' }],
    soilPlotQualities: [{ code: 'Fair', label: 'Fair' }],
    locationAccuracies: [
      { code: '<=1', label: '<1m' },
      { code: '>1000', label: '>1000m' },
    ],
  };

  // 1. WebFilterSidebar renders Region, Project+Publications, Bounding Box, Attributes, Quality, Apply & Clear
  const FilterSidebar = loadServerComponent('web/WebFilterSidebar.svelte', {
    './webBECMasterFilter': filterMod,
  });
  const bboxHtml = render(FilterSidebar, {
    props: {
      options: sampleOptions,
      filter: { ...filterMod.createEmptyBECMasterFilterState(), mode: 'bbox' },
      onApply: () => {},
      onClear: () => {},
    },
  }).body;
  assert.match(bboxHtml, /Select &amp; Filter Plots/);
  assert.match(bboxHtml, /Draw Bounding Box on Map/);
  assert.match(bboxHtml, /Northwest Corner/);
  assert.match(bboxHtml, /Southeast Corner/);
  assert.match(bboxHtml, /Plots used in published classification only/);
  assert.match(bboxHtml, /Site Plot Quality/);
  assert.match(bboxHtml, /Veg Plot Quality/);
  assert.match(bboxHtml, /Soil Plot Quality/);
  assert.match(bboxHtml, /Location Accuracy/);
  assert.match(bboxHtml, /Apply/);
  assert.match(bboxHtml, /Clear Selections/);

  const projectHtmlWithPubs = render(FilterSidebar, {
    props: {
      options: sampleOptions,
      filter: { ...filterMod.createEmptyBECMasterFilterState(), mode: 'project' },
      onApply: () => {},
      onClear: () => {},
    },
  }).body;
  assert.match(projectHtmlWithPubs, /Skeena_2024/);
  assert.match(projectHtmlWithPubs, /data-publications-filter/);

  const projectHtmlNoPubs = render(FilterSidebar, {
    props: {
      options: { ...sampleOptions, hasPublicationLinks: false },
      filter: { ...filterMod.createEmptyBECMasterFilterState(), mode: 'project' },
      onApply: () => {},
      onClear: () => {},
    },
  }).body;
  assert.doesNotMatch(projectHtmlNoPubs, /data-publications-filter/);

  // 2. WebDownloadCard renders live count, all 6 formats, OGL-BC link, and citation
  const DownloadCard = loadServerComponent('web/WebDownloadCard.svelte', {
    './webBECMasterFilter': filterMod,
    './webMeta': webMetaMod,
  });
  const sampleMeta = webMetaMod.normalizeWebMeta({
    snapshotId: 'becmaster-2026-11',
    publishedAt: '2026-11-25T00:00:00Z',
    redacted: true,
    totalPlotCount: 71567,
  });
  const dlHtml = render(DownloadCard, {
    props: {
      contextId: 'ctx-1',
      matchedCount: 120,
      totalPlots: 71567,
      plotNumbers: ['00337'],
      meta: sampleMeta,
    },
  }).body;
  assert.match(dlHtml, /Number of plots selected:\s*<strong>120<\/strong>\s*of 71,567/);
  for (const label of [
    'VPro64 SQLite (.db)',
    'CSVs (.zip)',
    'GeoPackage (.gpkg)',
    'R Bundle (.rds)',
    'TurboVeg 3 (.zip)',
    'Google Earth (.kml)',
  ]) {
    assert.ok(dlHtml.includes(label), `Download card missing format: ${label}`);
  }
  assert.match(dlHtml, /Open Government Licence – British Columbia/);
  assert.match(dlHtml, /target="_blank"/);
  assert.match(dlHtml, /rel="noopener noreferrer"/);
  assert.match(dlHtml, /BECMaster Biogeoclimatic Ecosystem Classification Plot Database/);

  // 3. WebBECMasterExplorer renders topbar, tabs, external BEC links, and lazy-loads secondary views
  const Explorer = loadServerComponent('web/WebBECMasterExplorer.svelte', {
    '../../bindings/github.com/boostao/vpro/app': { ContextService: {}, SpatialService: {} },
    '../shared/readRequests': { formatError: (e) => String(e) },
    '../shared/state': stateMod,
    './WebDownloadCard.svelte': DownloadCard,
    './WebFilterSidebar.svelte': FilterSidebar,
    './WebMapCanvas.svelte': () => '',
    './WebPlotCardDrawer.svelte': () => '',
    './webBECMasterFilter': filterMod,
    './webMeta': webMetaMod,
  });
  const explorerHtml = render(Explorer, { props: {} }).body;
  assert.match(explorerHtml, /VPro — BECMaster Explorer/);
  assert.match(explorerHtml, /Map &amp; Filter/);
  assert.match(explorerHtml, /Datasheet/);
  assert.match(explorerHtml, /Reports/);
  assert.match(explorerHtml, /Analysis/);
  assert.match(explorerHtml, /BECweb/);
  assert.match(explorerHtml, /https:\/\/www\.for\.gov\.bc\.ca\/hre\/becweb\//);
  assert.match(explorerHtml, /byBEC/);
  assert.match(explorerHtml, /https:\/\/thebeczone\.ca\/shiny\/bybecmap\//);

  // Verify lazy dynamic imports in WebBECMasterExplorer and zero Audit/edit tabs in WebPlotCardDrawer
  const explorerSrc = readSrc('web/WebBECMasterExplorer.svelte');
  for (const lazyComp of [
    '../datasheet/UniversalDatasheetGrid.svelte',
    '../reports/SummaryVegetationReport.svelte',
    '../reports/LongVegetationReport.svelte',
    '../reports/SiteUnitSummary.svelte',
    '../reports/LongEnvironmentReport.svelte',
    '../reports/SubzoneMatrixReport.svelte',
    '../diagnostics/ClassificationSynthesisView.svelte',
    '../rsidecar/RSidecarWorkbench.svelte',
  ]) {
    assert.ok(explorerSrc.includes(`import('${lazyComp}')`), `Expected lazy import of ${lazyComp}`);
  }
  const drawerSrc = readSrc('web/WebPlotCardDrawer.svelte');
  assert.match(drawerSrc, /GetPlotBundle\(ctxId,\s*plot,\s*false\)/);
  assert.match(drawerSrc, /FieldCardPreviewModal/);
  assert.match(drawerSrc, /buildFieldCardViewModel/);
  assert.doesNotMatch(drawerSrc, /ListAuditEntries|ListAuditReadEntries|UpdatePlot|SaveVegRecord/);
});

test('main.ts isolates WebBECMasterExplorer behind IS_WEB_READONLY dynamic import and all Track 2E files contain zero emojis or VITE_* flags', () => {
  const mainSrc = readSrc('main.ts');
  const webMetaSrc = readSrc('web/webMeta.ts');
  assert.match(mainSrc, /if\s*\(IS_WEB_READONLY\)/);
  assert.match(mainSrc, /mountWeb\(/);
  assert.match(webMetaSrc, /import\('\.\/WebBECMasterExplorer\.svelte'\)/);
  assert.match(mainSrc, /mount\(App,\s*\{\s*target:/);
  assert.doesNotMatch(mainSrc, /import\s+WebBECMasterExplorer\s+from/);

  const emojiRe = /\p{Extended_Pictographic}/u;
  for (const rel of [
    'main.ts',
    'web/webMeta.ts',
    'web/webBECMasterFilter.ts',
    'web/WebFilterSidebar.svelte',
    'web/WebMapCanvas.svelte',
    'web/WebDownloadCard.svelte',
    'web/WebPlotCardDrawer.svelte',
    'web/WebBECMasterExplorer.svelte',
  ]) {
    const src = readSrc(rel);
    assert.equal(emojiRe.test(src), false, `${rel} must contain zero emojis`);
    assert.doesNotMatch(src, /VITE_|import\.meta\.env/, `${rel} must not contain legacy VITE_* env flags`);
  }
});
