const assert = require('node:assert/strict');
const { webcrypto } = require('node:crypto');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { compile } = require('svelte/compiler');
const { render } = require('svelte/server');
const { loadTypeScript, serverComponent, srcPath } = require('./svelteTestHelpers.cjs');

test('UX-SPATIAL-008: GoogleEarthReview uses single-line text inputs and plain-language export guidance', () => {
  const source = readFileSync(srcPath('spatial/GoogleEarthReview.svelte'), 'utf8');
  const compiled = compile(source, { filename: 'GoogleEarthReview.svelte', generate: 'client', dev: true });
  assert.equal(compiled.warnings.length, 0);

  const quality = loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });
  const cells = loadTypeScript('projectMetadataRestore.ts', { './qualityEditor': quality, './projectMetadataEditor': {} });
  const locations = loadTypeScript('plotLocationReview.ts', { './projectMetadataRestore': cells });
  const earth = loadTypeScript('googleEarthReview.ts', {
    './projectMetadataRestore': cells,
    './qualityEditor': quality,
    './plotLocationReview': locations,
  });

  const EarthSSR = serverComponent(source, 'GoogleEarthReview.svelte', {
    '../../bindings/github.com/boostao/vpro/app': { SpatialService: {} },
    './googleEarthReview': earth,
    './googleEarthKMLReview': loadTypeScript('googleEarthKMLReview.ts', {
      './qualityEditor': quality,
      './googleEarthReview': earth,
    }),
    './googleEarthKMLExport': loadTypeScript(
      'googleEarthKMLExport.ts',
      {
        './publicationSession': loadTypeScript('publicationSession.ts'),
        './qualityEditor': quality,
        './googleEarthReview': earth,
        './googleEarthKMLReview': {},
      },
      { crypto: webcrypto, TextEncoder, Uint8Array },
    ),
    './googleEarthPreferences': loadTypeScript('googleEarthPreferences.ts', {
      './qualityEditor': quality,
      './googleEarthReview': earth,
      './googleEarthKMLReview': { googleEarthXMLText: () => true },
    }),
    '../reports/longEnvironmentReport': { reportCellText: String },
    '../entry/qualityEditor': quality,
  });

  const html = render(EarthSSR, {
    props: {
      contextId: 'ctx-ux-spatial-008',
      project: 'Sample',
      projectPath: '/data/projects/Sample.db',
      su: 'None',
      suPath: '',
      onBusyChange() {},
    },
  }).body;

  // Single-line fields must be <input type="text">, never <textarea>
  assert.match(html, /<input[^>]*id="google-earth-kml-destination"[^>]*type="text"[^>]*>/);
  assert.match(html, /<input[^>]*id="google-earth-place-name"[^>]*type="text"[^>]*>/);
  assert.doesNotMatch(html, /<textarea[^>]*id="google-earth-kml-destination"/);
  assert.doesNotMatch(html, /<textarea[^>]*id="google-earth-place-name"/);

  // Plain-language guidance replaces developer/XML/SQLite legalistic prose
  assert.match(html, /Load description fields, choose a text field for placemark descriptions/);
  for (const banned of [
    /Physical membership alone/i,
    /XML shape is not schema/i,
    /Review binds original raw cells/i,
    /ReportOptions preferences only/i,
    /Live description literal/i,
    /Direct Env scope/i,
    /Choose a literal Env field/i,
  ]) {
    assert.doesNotMatch(source, banned);
    assert.doesNotMatch(html, banned);
  }
});

test('UX-SPATIAL-008: Plot Pictures removes contradictory deletion copy, fixes 255 typo, and replaces internal jargon', () => {
  const creationSrc = readFileSync(srcPath('pictures/PictureCreationPanel.svelte'), 'utf8');
  const metadataSrc = readFileSync(srcPath('pictures/PictureMetadataEditor.svelte'), 'utf8');
  const managerSrc = readFileSync(srcPath('pictures/PictureManager.svelte'), 'utf8');
  const lifecycleSrc = readFileSync(srcPath('pictures/PictureLifecyclePanel.svelte'), 'utf8');

  for (const [name, src] of [
    ['PictureCreationPanel.svelte', creationSrc],
    ['PictureMetadataEditor.svelte', metadataSrc],
    ['PictureManager.svelte', managerSrc],
    ['PictureLifecyclePanel.svelte', lifecycleSrc],
  ]) {
    assert.equal(compile(src, { filename: name, generate: 'client', dev: true }).warnings.length, 0, name);
  }

  // Contradictory deletion claim and creation jargon removed
  assert.doesNotMatch(creationSrc, /Deletion and restoration remain unavailable/i);
  assert.doesNotMatch(creationSrc, /Source-bound, independently gated creation/i);
  assert.match(creationSrc, /Choose a JPEG or PNG image file to link to this plot/);

  // Missing space ("at most255") and UTF-16 jargon replaced with plain "at most 255 characters"
  assert.doesNotMatch(metadataSrc, /at most255/i);
  assert.doesNotMatch(metadataSrc, /UTF-16 units/i);
  assert.match(metadataSrc, /at most 255 characters/);

  // Internal Access/five-cell/literal-parent jargon replaced across Manager and Lifecycle panels
  for (const banned of [
    /Selected literal parent/i,
    /Independently gated desktop safety adaptation/i,
    /Access GUI confirmation/i,
    /five-cell physical reference/i,
    /source GUI confirmation remains unverified/i,
    /Adaptation of frmPlotPictureMaster/i,
  ]) {
    assert.doesNotMatch(managerSrc, banned);
    assert.doesNotMatch(lifecycleSrc, banned);
  }

  const quality = loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });
  const lookup = loadTypeScript('scopedPlotLookup.ts', { './qualityEditor': quality });
  const ManagerSSR = serverComponent(managerSrc, 'PictureManager.svelte', {
    './PicturePanel.svelte': { default: () => {} },
    './scopedPlotLookup': lookup,
    './pictureMetadataSessions': { pictureMetadataSession: () => undefined },
    './pictureCreationSessions': { pictureCreationSession: () => undefined },
    './PictureCreationPanel.svelte': { default: () => {} },
    './pictureLifecycleSessions': { pictureLifecycleSession: () => undefined },
    './PictureLifecyclePanel.svelte': { default: () => {} },
  });
  const managerHtml = render(ManagerSSR, {
    props: { contextId: 'ctx-pic-008', project: 'Sample', initialPlot: '108050', onBusyChange() {} },
  }).body;
  assert.match(managerHtml, /Selected plot: (?:"|&quot;)108050(?:"|&quot;)/);
  assert.doesNotMatch(managerHtml, /Selected literal parent/);
});

test('UX-SPATIAL-008: SpatialAuto1QATab uses plain BEC/spatial labels and adds bottom toast scroll clearance', () => {
  const qaSrc = readFileSync(srcPath('spatial/SpatialAuto1QATab.svelte'), 'utf8');
  const compiled = compile(qaSrc, { filename: 'SpatialAuto1QATab.svelte', generate: 'client', dev: true });
  assert.equal(compiled.warnings.length, 0);
  assert.match(compiled.css.code, /padding-bottom:\s*12rem/);
  assert.match(compiled.css.code, /scroll-padding-bottom:\s*12rem/);

  const wb = loadTypeScript('geospatialWorkbench.ts');
  const QASSR = serverComponent(qaSrc, 'SpatialAuto1QATab.svelte', {
    './geospatialWorkbench': wb,
  });
  const html = render(QASSR, {
    props: {
      qaReport: {
        unsignedLonCount: 39,
        utmDivergenceCount: 8,
        bgcMismatchCount: 33,
        missingGisBgcCount: 37,
        rows: [
          {
            plotNumber: '00337',
            fieldBgc: 'ICHvk2',
            suggestedGisBgc: 'BWBSlk',
            storedGisBgc: '',
            bgcMismatch: true,
            divergenceFlagged: false,
            longitudeSignFlipped: true,
            divergenceMeters: null,
          },
        ],
      },
      qaSelectedPlots: { '00337': true },
      loading: false,
      mutating: false,
      onReaudit() {},
      onApplyStamp() {},
    },
  }).body;

  assert.match(html, /class="wb-panel-body wb-qa-panel-body[^"]*"/);
  assert.match(html, /Stamp mapped BGC unit &amp; version \(BECdb v13\)/);
  assert.match(html, /Stamp Ecosection, Forest Region\/District, NTS Map Sheet &amp; Province/);
  assert.match(html, /Add negative sign to Western Hemisphere longitudes \(125\.4 to -125\.4\)/);
  assert.match(html, /Calculate NAD83 UTM Zone, Easting &amp; Northing from Latitude\/Longitude/);
  assert.match(html, /Show only plots with coordinate discrepancies or missing mapped BGC/);

  for (const rawSchemaJargon of [
    /_Admin\.GIS_BGC/,
    /GIS_BGC_VER/,
    /FSRegionDistrict/,
    /NtsMapSheet/,
    /UTMZone/,
    /Normalize unsigned positive West longitudes/,
  ]) {
    assert.doesNotMatch(html, rawSchemaJargon);
  }
});
