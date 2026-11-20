const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readdirSync, readFileSync } = require('node:fs');
const path = require('node:path');
const { render } = require('svelte/server');
const { loadTypeScript, serverComponent, srcPath } = require('./svelteTestHelpers.cjs');

const SRC_ROOT = path.resolve(__dirname, '..', 'src');

const CANONICAL_BCGOV_HEXES = new Set([
  '#003366',
  '#002244',
  '#FCBA19',
  '#FFFFFF',
  '#F2F2F2',
  '#D8D8D8',
  '#313132',
  '#474543',
  '#1A5A96',
  '#2E8540',
  '#D8292F',
  '#1E5128',
]);

const OWNED_SUBSYSTEMS = [
  'classification',
  'reports',
  'diagnostics',
  'spatial',
  'rsidecar',
];

const mockBindings = new Proxy({}, {
  get: (_target, service) => new Proxy({}, {
    get: (_svcTarget, method) => () => Promise.resolve(
      String(method).startsWith('List') || String(method).startsWith('Get') ? [] : null
    ),
  }),
});

function walkFiles(dir) {
  const results = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...walkFiles(full));
    } else if (entry.name.endsWith('.svelte') || entry.name.endsWith('.ts')) {
      results.push(full);
    }
  }
  return results;
}

test('all five Wave 3 workbenches render their canonical data-tour root attributes', () => {
  const roots = [
    ['classification/ClassificationExplorer.svelte', 'classification-explorer-root'],
    ['classification/LumpEditor.svelte', 'lump-editor-root'],
    ['spatial/GeospatialWorkbench.svelte', 'geospatial-workbench-root'],
    ['diagnostics/ClassificationSynthesisView.svelte', 'diagnostic-synthesis-root'],
    ['rsidecar/RSidecarWorkbench.svelte', 'r-sidecar-root'],
  ];

  for (const [relPath, tourAttr] of roots) {
    const src = readFileSync(path.join(SRC_ROOT, relPath), 'utf8');
    assert.match(
      src,
      new RegExp(`data-tour="${tourAttr}"`),
      `${relPath} must mount root container with data-tour="${tourAttr}"`
    );
  }
});

test('all five Wave 3 UI directories use strictly canonical BC Gov hexes and zero Tailwind palette utilities', () => {
  const legacyOrAdhocHexViolations = [];
  const tailwindUtilityViolations = [];
  const legacyForestRegex = /#(173f38|2c5b4a|d7ad51|b7cfc0)/i;
  const tailwindPaletteRegex = /\b(?:bg|text|border)-(?:indigo|emerald|amber|slate|teal|sky|rose|green|blue|gray|zinc|stone|red|yellow)-\d+\b/;

  for (const subsystem of OWNED_SUBSYSTEMS) {
    const dir = path.join(SRC_ROOT, subsystem);
    for (const filePath of walkFiles(dir)) {
      const rel = path.relative(SRC_ROOT, filePath);
      const lines = readFileSync(filePath, 'utf8').split('\n');
      let inCartographicZonePalette = false;

      lines.forEach((line, index) => {
        if (rel === 'spatial/geospatialWorkbench.ts') {
          if (line.includes('BEC_ZONE_PALETTE')) inCartographicZonePalette = true;
          else if (inCartographicZonePalette && line.trim() === '};') {
            inCartographicZonePalette = false;
            return;
          }
          if (inCartographicZonePalette) return;
        }

        if (legacyForestRegex.test(line)) {
          legacyOrAdhocHexViolations.push(`${rel}:${index + 1} (legacy Forest Green): ${line.trim()}`);
        }

        const hexMatches = line.match(/#[0-9a-fA-F]{3,8}\b/g);
        if (hexMatches) {
          for (const hex of hexMatches) {
            if (!CANONICAL_BCGOV_HEXES.has(hex.toUpperCase())) {
              legacyOrAdhocHexViolations.push(`${rel}:${index + 1}: ${hex}`);
            }
          }
        }

        if (tailwindPaletteRegex.test(line)) {
          tailwindUtilityViolations.push(`${rel}:${index + 1}: ${line.trim()}`);
        }
      });
    }
  }

  assert.deepEqual(
    legacyOrAdhocHexViolations,
    [],
    `Unexpected non-BC Gov hex values:\n${legacyOrAdhocHexViolations.join('\n')}`
  );
  assert.deepEqual(
    tailwindUtilityViolations,
    [],
    `Unexpected ad-hoc Tailwind color classes:\n${tailwindUtilityViolations.join('\n')}`
  );
});

test('primary Wave 3 workbenches include mobile/tablet responsive layouts and horizontal table-scroll containers', () => {
  const responsiveChecks = [
    ['classification/ClassificationExplorer.svelte', /@media\s*\(max-width:\s*960px\)/, /\.table-scroll/],
    ['classification/LumpEditor.svelte', /@media\s*\(max-width:\s*960px\)/, /minmax\(min\(100%,/],
    ['reports/LongVegetationReport.svelte', /minmax\(min\(100%,/, /\.table-scroll/],
    ['reports/SummaryVegetationReport.svelte', /@media\s*\(max-width:\s*960px\)/, /\.table-scroll/],
    ['reports/LifeformSummary.svelte', /minmax\(min\(100%,/, /\.table-scroll/],
    ['reports/SiteUnitSummary.svelte', /minmax\(min\(100%,/, /@media\s*\(max-width:\s*640px\)/],
    ['diagnostics/LMH25DiagnosticsBar.svelte', /minmax\(min\(100%,/, null],
    ['diagnostics/ClassificationSynthesisView.svelte', /@media\s*\(max-width:\s*960px\)/, /minmax\(min\(100%,/],
    ['spatial/GeospatialWorkbench.svelte', /@media\s*\(max-width:\s*960px\)/, /minmax\(min\(100%,/],
    ['rsidecar/RSidecarWorkbench.svelte', /@media\s*\(max-width:\s*960px\)/, /\.table-scroll/],
  ];

  for (const [relPath, firstRule, secondRule] of responsiveChecks) {
    const src = readFileSync(path.join(SRC_ROOT, relPath), 'utf8');
    assert.match(src, firstRule, `${relPath} missing responsive rule ${firstRule}`);
    if (secondRule) {
      assert.match(src, secondRule, `${relPath} missing overflow/grid guard ${secondRule}`);
    }
  }
});

test('Wave 3 functional wiring spans Classification, Reports, Diagnostics, Spatial, and R Sidecar', () => {
  // 1. Classification contracts
  const classExplorerSrc = readFileSync(srcPath('classification/ClassificationExplorer.svelte'), 'utf8');
  const classExplorerTs = readFileSync(srcPath('classification/classificationExplorer.ts'), 'utf8');
  const lumpEditorTs = readFileSync(srcPath('classification/lumpEditor.ts'), 'utf8');
  const lumpEditorSrc = readFileSync(srcPath('classification/LumpEditor.svelte'), 'utf8');
  const profileReviewSrc = readFileSync(srcPath('classification/ProjectPlotProfileReview.svelte'), 'utf8');
  assert.match(classExplorerTs, /SearchBECSiteSeries/);
  assert.match(classExplorerTs, /ListUserSiteUnitList/);
  assert.match(classExplorerTs, /SaveHierarchyTableAs/);
  assert.match(classExplorerSrc, /<SiteUnitExclusionFilter/);
  assert.match(lumpEditorTs, /DeleteLumpTable/);
  assert.match(lumpEditorSrc, /refreshTables\(/);
  assert.match(profileReviewSrc, /ListProjectPlotProfileLumpTables/);

  // 2. Reports contracts
  const { readReportComposite } = require('./svelteTestHelpers.cjs');
  const longVegSrc = readReportComposite('long-vegetation');
  const sumVegSrc =
    readFileSync(srcPath('reports/SummaryVegetationReport.svelte'), 'utf8') +
    '\n' +
    readFileSync(srcPath('reports/SummaryVegetationOptionsBar.svelte'), 'utf8');
  const sumVegQualSrc = readFileSync(srcPath('reports/SummaryVegetationQualityPreferences.svelte'), 'utf8');
  const lifeformSrc = readFileSync(srcPath('reports/LifeformSummary.svelte'), 'utf8');
  const suSummarySrc =
    readFileSync(srcPath('reports/SiteUnitSummary.svelte'), 'utf8') +
    '\n' +
    readFileSync(srcPath('reports/SiteUnitSummaryFieldsets.svelte'), 'utf8');
  assert.match(longVegSrc, /LVUseSppCodesOnly/);
  assert.match(longVegSrc, /reportMode="long"/);
  assert.doesNotMatch(sumVegQualSrc, /disabled[^>]*optEnforceQC|optEnforceQC[^>]*disabled/);
  assert.match(sumVegSrc, /SVSubSppAsSpp/);
  assert.match(lifeformSrc, /PreviewLifeformSummaryWithHierarchyBreakpoints/);
  assert.match(suSummarySrc, /GetFullSiteUnitSummaryPreferences/);
  assert.match(suSummarySrc, /SESuType/);

  // 3. Diagnostics synthesis defaults + pairwise params
  const syn = loadTypeScript('classificationSynthesis.ts', {
    '../../bindings/github.com/boostao/vpro/app': mockBindings,
  });
  const synSrc = readFileSync(srcPath('diagnostics/ClassificationSynthesisView.svelte'), 'utf8');
  const defaults = syn.createDefaultSynthesisOptions();
  assert.equal(defaults.pairwise.minPlots, 2);
  assert.equal(defaults.pairwise.minConstancy, 60);
  assert.equal(defaults.pairwise.noiseConstancy, 10);
  assert.equal(defaults.pairwise.minDiff, 0.5);
  assert.equal(defaults.pairwise.minDd, 0.5);
  assert.match(synSrc, /minMaxPresencePct/);
  assert.match(synSrc, /excludePatternsText/);

  // 4. Spatial western longitude preservation + SyncLatLonFromUTM + GeoPackage shortcut
  const qualityForSpatial = loadTypeScript('entry/qualityEditor.ts', {
    './becEditor': loadTypeScript('entry/becEditor.ts'),
  });
  const cells = loadTypeScript('admin/projectMetadataRestore.ts', {
    '../entry/qualityEditor': qualityForSpatial,
    './projectMetadataEditor': {},
  });
  const plotLoc = loadTypeScript('spatial/plotLocationReview.ts', {
    '../admin/projectMetadataRestore': cells,
  });
  const geoSrc = readFileSync(srcPath('spatial/GeospatialWorkbench.svelte'), 'utf8');
  assert.equal(
    plotLoc.exactLongitudeNegation(
      { raw: '-125.4', storage: 'real', real: -125.4, text: null },
      { raw: '-125.4', storage: 'real', real: -125.4, text: null }
    ),
    true,
    'Already-negative BC western longitudes must be preserved cleanly'
  );
  assert.equal(
    plotLoc.exactLongitudeNegation(
      { raw: '125.4', storage: 'real', real: 125.4, text: null },
      { raw: '-125.4', storage: 'real', real: -125.4, text: null }
    ),
    true,
    'Positive magnitude longitudes must flip negative'
  );
  assert.match(geoSrc, /syncLatLonFromUTM/);
  assert.match(geoSrc, /ExportGeoPackage/);

  // 5. R Sidecar SSR + vegclust disabled controls + dynamic SVG height
  const rSidecar = loadTypeScript('rsidecar/rSidecarWorkbench.ts', {
    '../../bindings/github.com/boostao/vpro/app': mockBindings,
    '../entry/qualityEditor': qualityForSpatial,
  });
  const RSidecarComp = serverComponent(
    readFileSync(srcPath('rsidecar/RSidecarWorkbench.svelte'), 'utf8'),
    'RSidecarWorkbench.svelte',
    { './rSidecarWorkbench': rSidecar }
  );
  const renderedRSidecar = render(RSidecarComp, {
    props: { contextId: 'ctx-wave3', activeProject: 'Sample', activeSu: 'Working' },
  }).body;
  assert.match(renderedRSidecar, /data-tour="r-sidecar-root"/);
  assert.equal(rSidecar.usesDissimilarity('NC'), false);
  assert.equal(rSidecar.usesDissimilarity('BETA_FLEXIBLE'), true);
  assert.equal(rSidecar.usesHierarchicalLinkage('PAM'), false);
});

test('SummaryVegetationReport and LongVegetationReport forward live active hierarchy and exclusion busy hook to SiteUnitExclusionFilter (#48)', () => {
  const exclLogic = loadTypeScript('classification/siteUnitExclusionFilter.ts', {
    '@wailsio/runtime': { Call: { ByName: () => Promise.resolve(null) } },
  });
  const RealExclusionFilter = serverComponent(
    readFileSync(srcPath('classification/SiteUnitExclusionFilter.svelte'), 'utf8'),
    'SiteUnitExclusionFilter.svelte',
    {
      './siteUnitExclusionFilter': exclLogic,
      '../shared/readRequests': { ReadRequests: class { cancelAll() {} } },
    }
  );

  let activeHierarchyState = { activeHierarchy: 'StoreHier' };
  const storeStub = {
    projectState: {
      subscribe(fn) {
        fn(activeHierarchyState);
        return () => {};
      },
    },
  };

  // 1. SummaryVegetationReport with store activeHierarchy + explicit prop override + onExclusionBusyChange
  const lifeform = loadTypeScript('lifeformSummary.ts');
  const summaryMod = loadTypeScript('summaryVegetation.ts', { './lifeformSummary': lifeform }, { setTimeout });
  const sumOwner = {
    contextId: 'ctx-s59',
    project: 'Sample',
    projectPath: '/tmp/Sample.db',
    su: 'Working',
    suPath: '/tmp/Sample.db',
  };
  const SumComp = serverComponent(
    readFileSync(srcPath('reports/SummaryVegetationReport.svelte'), 'utf8'),
    'SummaryVegetationReport.svelte',
    {
      './summaryVegetation': summaryMod,
      '../bindings/github.com/boostao/vpro/app': mockBindings,
      '../shared/state': storeStub,
      '../classification/SiteUnitExclusionFilter.svelte': { default: RealExclusionFilter },
      '../classification/siteUnitExclusionFilter': exclLogic,
    }
  );

  const sumFromStore = render(SumComp, {
    props: { ...sumOwner, onBusyChange: () => {}, onExclusionBusyChange: () => {} },
  }).body;
  assert.match(sumFromStore, /\(Active Hierarchy:\s*<strong>StoreHier<\/strong>\)/);
  assert.doesNotMatch(sumFromStore, /Select an active Hierarchy in the sidebar to enable/);

  const sumExplicitProp = render(SumComp, {
    props: { ...sumOwner, hierarchy: 'PropHier', onBusyChange: () => {}, onExclusionBusyChange: () => {} },
  }).body;
  assert.match(sumExplicitProp, /\(Active Hierarchy:\s*<strong>PropHier<\/strong>\)/);

  // Verify SummaryVegetationReport source wires onExclusionBusyChange cleanly to SiteUnitExclusionFilter
  const sumSrc = readFileSync(srcPath('reports/SummaryVegetationReport.svelte'), 'utf8');
  assert.match(sumSrc, /onExclusionBusyChange\?\s*:\s*\(value:\s*boolean\)\s*=>\s*void/);
  assert.match(sumSrc, /onBusyChange=\{onExclusionBusyChange\}/);

  // 2. LongVegetationReport forwards $projectState.activeHierarchy and explicit hierarchy prop instead of ""
  class PubStub {
    view() { return { busy: false, blocked: false, error: '', outcome: null, requestedDestination: '' }; }
    subscribe(fn) { fn(); return () => {}; }
  }
  const longWorkspace = {
    view: () => ({
      scope: { scope: sumOwner, definitions: [], fields: [], dirty: false, draftError: '', error: '', busy: false, authorityUnknown: false, outputReady: false, closeBlocked: false },
      units: { saved: { unitGroups: 2 }, draft: { unitGroups: '2' }, initialized: true, busy: false, blocked: false, authorityUnknown: false, error: '', draftError: '', readError: '', readBusy: false, readReady: true, saveReady: true, closeBlocked: false, projectReceipts: [], scope: sumOwner },
      publication: { busy: false, blocked: false, error: '', outcome: null, requestedDestination: '' },
      readBusy: false, error: '', settings: null, preview: null, workbookReview: null,
      projectActive: true, outputReady: false, scopeOperationHeld: false, scopeMutationHeld: false,
      unitOperationHeld: false, unitMutationHeld: false, closeBlocked: false, sourceRevalidationRequired: false,
    }),
    subscribe(fn) { fn(); return () => {}; },
    selection: { view: () => ({ scope: sumOwner, definitions: [], fields: [], dirty: false, draftError: '', error: '', busy: false, authorityUnknown: false, outputReady: false, closeBlocked: false }), subscribe(fn) { fn(); return () => {}; }, cancel() {} },
    units: { projectView: () => ({ saved: { unitGroups: 2 }, draft: { unitGroups: '2' }, initialized: true, busy: false, blocked: false, authorityUnknown: false, error: '', draftError: '', readError: '', readBusy: false, readReady: true, saveReady: true, closeBlocked: false, projectReceipts: [], scope: sumOwner }), subscribe(fn) { fn(); return () => {}; }, cancelRead() {} },
    workbook: { acknowledge() {} },
    cancelScopeReads() {}, cancelUnitReads() {}, cancelReportRead() {}, invalidate() {},
    fetchUnitPreferences() {}, saveUnitPreferences() {},
    loadOptions: async () => {}, showPreview: async () => {}, reviewWorkbook: async () => {}, publishWorkbook: async () => {},
  };
  const LongComp = serverComponent(
    readFileSync(srcPath('reports/LongVegetationReport.svelte'), 'utf8'),
    'LongVegetationReport.svelte',
    {
      '../bindings/github.com/boostao/vpro/app': mockBindings,
      './longVegetationProjectWorkspaces': { projectReportWorkspace: () => longWorkspace },
      './longVegetationSelectedUnitSelection': {}, './LongVegetationSelectedUnitSelection.svelte': { default() {} },
      '../shared/state': storeStub,
      '../classification/SiteUnitExclusionFilter.svelte': { default: RealExclusionFilter },
      '../classification/siteUnitExclusionFilter': exclLogic,
      './longVegetationGroupPreferences': {}, './LongVegetationGroupPreferences.svelte': { default() {} },
      './longVegetationNamingPreferences': {}, './LongVegetationNamingPreferences.svelte': { default() {} },
      './longVegetationSelectedFieldPreferences': {}, './LongVegetationSelectedFieldPreferences.svelte': { default() {} },
      './longVegetationEnforcementPreferences': {}, './LongVegetationEnforcementPreferences.svelte': { default() {} },
      './longVegetationQualityNullPreferences': {}, './LongVegetationQualityNullPreferences.svelte': { default() {} },
      './longVegetationQualityMinimumPreferences': {}, './LongVegetationQualityMinimumPreferences.svelte': { default() {} },
      './longVegetationUnitPreferences': {}, './LongVegetationUnitPreferences.svelte': { default() {} },
      './longVegetationPreferences': {}, './longVegetationStatisticsPreferences': {},
      './longVegetationSwitchPreferences': {}, './LongVegetationSwitchPreferences.svelte': { default() {} },
      './longVegetationThresholdPreferences': {}, './LongVegetationThresholdPreferences.svelte': { default() {} },
      './longVegetationReport': {},
      './longEnvironmentReport': { reportCellText: () => '' },
      './vegetationWorkbook': { VegetationWorkbookPublicationSession: PubStub, vegetationWorkbookPublicationSession: () => new PubStub() },
    }
  );

  const longFromStore = render(LongComp, {
    props: { ...sumOwner, onBusyChange: () => {} },
  }).body;
  assert.match(longFromStore, /\(Active Hierarchy:\s*<strong>StoreHier<\/strong>\)/);
  assert.doesNotMatch(longFromStore, /Select an active Hierarchy in the sidebar to enable/);

  const longExplicitProp = render(LongComp, {
    props: { ...sumOwner, hierarchy: 'LongPropHier', onBusyChange: () => {} },
  }).body;
  assert.match(longExplicitProp, /\(Active Hierarchy:\s*<strong>LongPropHier<\/strong>\)/);

  // 3. Verify ClassificationExplorer keeps ../shared/state free and preserves hierarchy || 'None' fallback
  const ceSrc = readFileSync(srcPath('classification/ClassificationExplorer.svelte'), 'utf8');
  assert.doesNotMatch(ceSrc, /shared\/state/);
  assert.match(ceSrc, /hierarchy=\{hierarchyView\?\.hierarchy\s*\|\|\s*\(hierarchy\s*&&\s*hierarchy\s*!==\s*'None'\s*\?\s*hierarchy\s*:\s*''\)\s*\|\|\s*'None'\}/);
});
