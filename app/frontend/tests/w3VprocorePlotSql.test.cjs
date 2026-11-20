const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const ts = require('typescript');
const { compile } = require('svelte/compiler');
const { render } = require('svelte/server');
const { serverComponent, loadTypeScript, presentationHelpers, srcPath } = require('./svelteTestHelpers.cjs');

const { paper, presentation } = presentationHelpers();
const read = file => readFileSync(srcPath(file), 'utf8');

const bec = loadTypeScript('becEditor.ts');
const quality = loadTypeScript('qualityEditor.ts', { './becEditor': bec });
const reference = loadTypeScript('referenceCodeEditor.ts', { './becEditor': bec, './qualityEditor': quality });
const coordMod = loadTypeScript('coordinateEditor.ts');

const siviCreate = loadTypeScript('siviParentCreate.ts', {
  '../../bindings/github.com/boostao/vpro/app': {},
  './qualityEditor': quality,
});

const modules = {
  './becEditor': bec,
  './qualityEditor': quality,
  './coordinateEditor': coordMod,
  './workingUnitEditor': loadTypeScript('workingUnitEditor.ts', { './becEditor': bec }),
  './substrateEditor': loadTypeScript('substrateEditor.ts', { './numericEditor': loadTypeScript('numericEditor.ts') }),
  './siteCodeEditor': loadTypeScript('siteCodeEditor.ts', { './referenceCodeEditor': reference }),
  './regionCodeEditor': loadTypeScript('regionCodeEditor.ts', { './referenceCodeEditor': reference }),
  './paperLayout': paper,
  './formPresentation': presentation,
};
modules['./masterBECEditor'] = loadTypeScript('masterBECEditor.ts', {
  './workingUnitEditor': modules['./workingUnitEditor'],
  './referenceCodeEditor': reference,
});

const noNative = new Proxy({}, { get() { return () => { throw new Error('SSR must not call native services'); }; } });
const native = {
  BECService: noNative,
  CoordinateService: noNative,
  SpatialService: noNative,
  WorkingUnitService: noNative,
  QualityService: noNative,
  SiteCodeService: noNative,
  RegionCodeService: noNative,
  CoordinateMode: { CoordinateModeDD: 'dd', CoordinateModeDM: 'dm', CoordinateModeDMS: 'dms' },
};
const dependencies = { ...modules, '../../bindings/github.com/boostao/vpro/app': native };
for (const name of ['BECFields', 'CoordinateFields', 'WorkingUnitFields', 'QualityFields', 'SubstrateFields', 'SiteCodeFields', 'RegionCodeFields']) {
  dependencies[`./${name}.svelte`] = { default: serverComponent(read(`${name}.svelte`), `${name}.svelte`, dependencies) };
}
const HeaderEditor = serverComponent(read('HeaderEditor.svelte'), 'HeaderEditor.svelte', dependencies);

function baseDraft(overrides = {}) {
  return {
    plotNumber: 'QALMH1',
    locked: false,
    fieldNo: null,
    surveyor: null,
    projectId: null,
    date: null,
    startDate: null,
    generalLocation: null,
    mapSheet: null,
    utmZone: null,
    easting: null,
    northing: null,
    latitude: null,
    longitude: null,
    accuracy: null,
    zone: null,
    subZone: null,
    siteSeries: null,
    becSiteUnit: null,
    userSiteUnit: null,
    plotRepresenting: null,
    transition: null,
    mapUnit: null,
    moistureRegime: null,
    nutrientRegime: null,
    successional: null,
    structuralStage: null,
    standAge: null,
    elevation: null,
    slope: null,
    aspect: null,
    mesoSlopePos: null,
    surfaceShape: null,
    microtopType: null,
    microtopSize: null,
    sitePlotQuality: null,
    vegPlotQuality: null,
    soilPlotQuality: null,
    substrateOrganicMatter: null,
    substrateRocks: null,
    substrateDecWood: null,
    substrateMineralSoil: null,
    substrateBedRock: null,
    substrateWater: null,
    siteDisturbance1: null,
    siteDisturbance2: null,
    siteDisturbance3: null,
    exposure1: null,
    exposure2: null,
    fsRegionDistrict: null,
    ecosection: null,
    fieldNotes: null,
    officeNotes: null,
    ...overrides,
  };
}

function allCapabilities() {
  return Object.fromEntries(Object.keys(baseDraft()).map(k => [k, true]));
}

test('UX-ENV-005 & UX-ENV-004: validateCreateSIVIPlotDraft rejects leading/trailing spaces and impossible calendar dates', () => {
  assert.match(
    siviCreate.validateCreateSIVIPlotDraft({ plotNumber: '00888 ', plotType: 'Ground' }).plotNumber,
    /spaces/i
  );
  assert.match(
    siviCreate.validateCreateSIVIPlotDraft({ plotNumber: ' 00887', plotType: 'Visual' }).plotNumber,
    /spaces/i
  );
  assert.match(
    siviCreate.validateCreateSIVIPlotDraft({ plotNumber: 'SV01', plotType: 'Ground', date: '2026-02-30' }).date,
    /calendar date/i
  );
  assert.match(
    siviCreate.validateCreateSIVIPlotDraft({ plotNumber: 'SV01', plotType: 'Ground', date: 'not-a-date' }).date,
    /YYYY-MM-DD/
  );
  assert.equal(
    siviCreate.validateCreateSIVIPlotDraft({ plotNumber: 'SV01', plotType: 'Ground', date: '2024-02-29' }).date,
    undefined
  );
});

test('UX-ENV-004 & UX-ENV-005: HeaderEditor SSR renders inline validation alerts, substrate sum warning, and preserves legacy plots', () => {
  // 1. New plot with trailing space + invalid LMH25 fields + 60% substrate sum
  const badDraft = baseDraft({
    plotNumber: '00888 ',
    date: 'not-a-date',
    startDate: 99999,
    elevation: -500,
    slope: -15,
    aspect: 500,
    utmZone: '9S',
    structuralStage: '99',
    successional: 'BOGUS',
    substrateOrganicMatter: 50,
    substrateMineralSoil: 10,
  });
  const badHtml = render(HeaderEditor, {
    props: {
      draft: badDraft,
      original: null,
      capabilities: allCapabilities(),
      disabled: false,
      existing: false,
      lists: {},
      onchange() {},
      onerror() {},
      onvalidation() {},
      workingUnitSession: { mode: null },
    },
  }).body;

  assert.match(badHtml, /Plot number cannot start or end with spaces\./);
  assert.match(badHtml, /Survey date must be a valid calendar date in YYYY-MM-DD format/);
  assert.match(badHtml, /Start year \(Yr\.\) must be an integer between 1900 and 2500\./);
  assert.match(badHtml, /Elevation must be an integer between 0 and 9000 m/);
  assert.match(badHtml, /Slope gradient must be 0% or greater\./);
  assert.match(badHtml, /Aspect must be an integer from 0 to 360 degrees, or 999 for level ground\./);
  assert.match(badHtml, /UTM zone must be a Northern Hemisphere zone number/);
  assert.match(badHtml, /Structural stage "99" is not a standard LMH25 code/);
  assert.match(badHtml, /Successional status must be at most 3 characters/);
  assert.match(badHtml, /Total: 60% \/ 100%/);
  assert.match(badHtml, /data-substrate-sum-warning[^>]*>Populated substrates sum to 60% \(LMH25 expects 100% total\)\./);

  // 2. Valid 100% substrate sum + Aspect = 999 level ground + standard codes emit zero alerts or substrate warnings
  const validDraft = baseDraft({
    plotNumber: '00888',
    date: '2026-07-15',
    startDate: 2026,
    elevation: 450,
    slope: 0,
    aspect: 999,
    utmZone: '10N',
    structuralStage: '6',
    successional: 'MC',
    substrateOrganicMatter: 60,
    substrateMineralSoil: 40,
  });
  const validHtml = render(HeaderEditor, {
    props: {
      draft: validDraft,
      original: null,
      capabilities: allCapabilities(),
      disabled: false,
      existing: false,
      lists: {},
      onchange() {},
      onerror() {},
      onvalidation() {},
      workingUnitSession: { mode: null },
    },
  }).body;
  assert.match(validHtml, /Total: 100% \/ 100%/);
  assert.doesNotMatch(validHtml, /data-substrate-sum-warning/);
  assert.doesNotMatch(validHtml, /field-error-msg/);

  // 3. Existing historical plot with leading space & unchanged anomalies renders zero field-error-msg alerts
  const legacyValues = baseDraft({
    plotNumber: ' 00337',
    date: 'not-a-date',
    startDate: 99999,
    elevation: -500,
    slope: -15,
    aspect: 500,
    utmZone: '9S',
    structuralStage: '99',
    successional: 'BOGUS',
    substrateOrganicMatter: 150,
    fieldNotes: 'Edited note on legacy plot',
  });
  const legacyOriginal = structuredClone(legacyValues);
  legacyOriginal.fieldNotes = 'Original note';
  const legacyHtml = render(HeaderEditor, {
    props: {
      draft: legacyValues,
      original: legacyOriginal,
      capabilities: allCapabilities(),
      disabled: false,
      existing: true,
      lists: {},
      onchange() {},
      onerror() {},
      onvalidation() {},
      workingUnitSession: { mode: null },
    },
  }).body;
  assert.doesNotMatch(legacyHtml, /field-error-msg/);
  assert.doesNotMatch(legacyHtml, /stand-code-acknowledgement/);
});

test('UX-ENV-004: CoordinateFields rejects Southern UTM zone 9S and reports out-of-BC status for (0, 0)', async () => {
  const client = await import('svelte/internal/client');
  let script = read('CoordinateFields.svelte').match(/<script lang="ts">([\s\S]*?)<\/script>/)[1];
  script = script.replace(/children,?\s*\}:/, 'children, inspect }:');
  script += `\n$effect(() => inspect({
    runAuto1: runAuto1CoordinateAttribution,
    getState: () => ({ auto1Summary, auto1OutOfBounds, auto1Busy }),
  }));`;

  const compiled = compile(`<script lang="ts">${script}</script>`, { generate: 'client' });
  assert.equal(compiled.warnings.length, 0);
  const ast = ts.createSourceFile('coordFields.js', compiled.js.code, ts.ScriptTarget.Latest, true);
  const code = ast.statements
    .filter(n => !ts.isImportDeclaration(n))
    .map(n => n.getText(ast))
    .join('\n')
    .replace('export default function', 'function');

  const { serverReads } = require('./svelteTestHelpers.cjs');
  const coordConvMod = loadTypeScript('coordinateConversion.ts');
  const mountFn = new Function(
    '$',
    'onMount',
    'onDestroy',
    'untrack',
    'SpatialService',
    'CoordinateMode',
    'ReadRequests',
    'formatError',
    'trackIfCancellable',
    'CoordinateEditor',
    'coordinateSession',
    'rememberCoordinateSession',
    'coordinateBusy',
    'coordinateControls',
    'coordinateOptions',
    'createSpatialCoordinatePort',
    'projectNAD83UTMZoneToLatLon',
    code + '\nreturn _unknown_;'
  );

  let utmCalls = 0;
  const mockSpatial = {
    async GetCoordinateMode() { return 'dd'; },
    async SetCoordinateMode() {},
    async DecomposeCoordinate(val) {
      return { negative: false, degrees: val === null ? null : val, minutes: null, seconds: null };
    },
    async ConvertCoordinate() { return 0; },
    async ProjectNAD83UTMToLatLon() {
      utmCalls++;
      return { latitude: 54.5, longitude: -126.5 };
    },
    async SuggestSpatialAttributes(lat, lon) {
      return {
        latitude: lat,
        longitude: lon,
        normalizedLon: lon,
        longitudeSignFlipped: false,
        utmZone: 0,
        utmEasting: 0,
        utmNorthing: 0,
        ntsMapSheet: '',
        gisBgc: '',
        ecosection: '',
        fsRegionDistrict: '',
        diagnostics: ['Coordinates fall outside British Columbia coverage.'],
      };
    },
  };

  let handle = null;
  const errors = [];
  const draft = baseDraft({
    latitude: null,
    longitude: null,
    utmZone: '9S',
    easting: 500000,
    northing: 6000000,
  });

  const componentFn = mountFn(
    { ...client, props_id: () => 'w3-rg' },
    fn => fn(),
    () => {},
    client.untrack,
    mockSpatial,
    native.CoordinateMode,
    serverReads.ReadRequests,
    serverReads.formatError,
    serverReads.trackIfCancellable,
    coordMod.CoordinateEditor,
    coordMod.coordinateSession,
    coordMod.rememberCoordinateSession,
    coordMod.coordinateBusy,
    coordMod.coordinateControls,
    coordMod.coordinateOptions,
    coordConvMod.createSpatialCoordinatePort,
    coordConvMod.projectNAD83UTMZoneToLatLon
  );

  const dispose = client.effect_root(() =>
    componentFn(
      null,
      {
        get draft() { return draft; },
        set draft(v) { Object.assign(draft, v); },
        mode: 'dd',
        controls: [],
        position: () => '',
        capabilities: allCapabilities(),
        disabled: false,
        onchange() {},
        onerror(msg) { errors.push(msg); },
        onvalidation() {},
        children() {},
        inspect(h) { handle = h; },
      }
    )
  );
  client.flush();
  await new Promise(r => setTimeout(r, 10));
  client.flush();

  try {
    // 1. Southern zone "9S" must be rejected without calling ProjectNAD83UTMToLatLon
    await handle.runAuto1();
    client.flush();
    assert.equal(utmCalls, 0);
    assert.equal(errors.length, 1);
    assert.match(errors[0], /Invalid NAD83 UTM zone "9S"/);

    // 2. Out-of-BC (0, 0) must populate auto1Summary with out-of-BC warning instead of staying blank
    errors.length = 0;
    draft.utmZone = null;
    draft.easting = null;
    draft.northing = null;
    draft.latitude = 0;
    draft.longitude = 0;
    await handle.runAuto1();
    client.flush();
    assert.equal(errors.length, 0);
    const st = handle.getState();
    assert.equal(st.auto1OutOfBounds, true);
    assert.match(st.auto1Summary, /Out of B\.C\. bounds/i);
  } finally {
    dispose();
  }
});
