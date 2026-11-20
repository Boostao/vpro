const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const { compile } = require('svelte/compiler');
const { render } = require('svelte/server');
const { serverComponent, loadTypeScript, presentationHelpers, srcPath } = require('./svelteTestHelpers.cjs');
const { paper, presentation } = presentationHelpers();
const read = file => readFileSync(srcPath(file), 'utf8');
const bec = loadTypeScript('becEditor.ts');
const quality = loadTypeScript('qualityEditor.ts', { './becEditor': bec });
const reference = loadTypeScript('referenceCodeEditor.ts', { './becEditor': bec, './qualityEditor': quality });
const modules = {
  './becEditor': bec,
  './qualityEditor': quality,
  './coordinateEditor': loadTypeScript('coordinateEditor.ts'),
  './workingUnitEditor': loadTypeScript('workingUnitEditor.ts', { './becEditor': bec }),
  './substrateEditor': loadTypeScript('substrateEditor.ts', { './numericEditor': loadTypeScript('numericEditor.ts') }),
  './siteCodeEditor': loadTypeScript('siteCodeEditor.ts', { './referenceCodeEditor': reference }),
  './regionCodeEditor': loadTypeScript('regionCodeEditor.ts', { './referenceCodeEditor': reference }),
  './paperLayout': paper,
  './formPresentation': presentation
};
modules['./masterBECEditor'] = loadTypeScript('masterBECEditor.ts', {
  './workingUnitEditor': modules['./workingUnitEditor'], './referenceCodeEditor': reference
});
const noNative = new Proxy({}, { get() { return () => { throw new Error('SSR must not call native services'); }; } });
const native = {
  BECService: noNative, CoordinateService: noNative, WorkingUnitService: noNative,
  QualityService: noNative, SiteCodeService: noNative, RegionCodeService: noNative,
  CoordinateMode: { CoordinateModeDD: 'dd', CoordinateModeDM: 'dm', CoordinateModeDMS: 'dms' }
};
const dependencies = { ...modules, '../bindings/github.com/boostao/vpro/app': native };
for (const name of ['BECFields', 'CoordinateFields', 'WorkingUnitFields', 'QualityFields', 'SubstrateFields', 'SiteCodeFields', 'RegionCodeFields']) {
  dependencies[`./${name}.svelte`] = { default: serverComponent(
    read(`${name}.svelte`), `${name}.svelte`, dependencies) };
}
const HeaderEditor = serverComponent(read('HeaderEditor.svelte'), 'HeaderEditor.svelte', dependencies);
test('Exact source captions and binding aliases take precedence only for explicitly supplied source pages', () => {
  const control = { controlName: 'SoilClassGroup', column: 'SoilClassSubGroup', caption: 'S. &Group' };
  assert.equal(presentation.controlLabel(control), 'Soil great group');
  assert.equal(presentation.controlLabel(control, true), 'S. Group');
  assert.equal(presentation.controlLabel({ ...control, caption: '' }, true), 'Soil subgroup');
});
function headerProps(overrides = {}) {
  const draft = {
    plotNumber: 'RESPONSIVE', locked: false, latitude: null, longitude: null,
    zone: null, subZone: null, siteSeries: null, becSiteUnit: null, userSiteUnit: null,
    sitePlotQuality: null, vegPlotQuality: null, soilPlotQuality: null,
    substrateOrganicMatter: null, substrateRocks: null, substrateDecWood: null, substrateMineralSoil: null, substrateBedRock: null, substrateWater: null,
    siteDisturbance1: null, siteDisturbance2: null, siteDisturbance3: null, exposure1: null, exposure2: null,
    fsRegionDistrict: null, ecosection: null,
    fieldNotes: "Unchanged q'X4", officeNotes: null, generalLocation: 'Test location',
    airPhotoNum: 'HISTORICAL', photo: 'PHOTO', updatedFromCards: true
  };
  const capabilities = Object.fromEntries([...Object.keys(draft),
    'fieldNo', 'surveyor', 'projectId', 'date', 'startDate', 'accuracy', 'mapSheet', 'easting', 'northing', 'utmZone',
    'plotRepresenting', 'transition', 'mapUnit', 'moistureRegime', 'nutrientRegime', 'successional', 'structuralStage', 'standAge',
    'elevation', 'slope', 'aspect', 'mesoSlopePos', 'surfaceShape', 'microtopType', 'microtopSize'].map(key => [key, true]));
  return { draft, original: null, capabilities, disabled: false, existing: true, lists: {},
    onchange() {}, onerror() {}, onvalidation() {}, workingUnitSession: { mode: null }, ...overrides };
}
test('Every source page and coordinate/vegetation mode has complete, unique semantic group coverage', () => {
  for (const [name, mode, coordinate] of [
    ['Site', 'initial', 'dd'], ['Site', 'initial', 'dm'], ['Site', 'initial', 'dms'],
    ['Soil/Terrain'], ['Vegetation', 'initial'], ['Vegetation', 'cover'], ['Vegetation', 'height'], ['Veg Other'], ['Other']
  ]) {
    const controls = paper.paperPage(name, mode, coordinate).controls;
    const before = JSON.stringify(controls);
    const groups = presentation.presentationGroups(name, controls);
    const members = groups.flatMap(group => Array.from(group.controls));
    const expected = controls.filter(control => !['Label', 'Rectangle', 'OptionGroup'].includes(control.type));
    assert.deepEqual(Array.from(members, control => control.controlId).sort(), Array.from(expected, control => control.controlId).sort());
    assert.equal(new Set(members.map(control => control.controlId)).size, members.length);
    assert.equal(groups.some(group => group.title === 'Additional source fields and actions'), false);
    assert.equal(JSON.stringify(controls), before);
    assert.ok(members.every(control => presentation.controlLabel(control).length > 0));
  }
});
test('Site SSR renders one live instance per source control with explicit labels and no presentation coordinates', () => {
  const html = render(HeaderEditor, { props: headerProps() }).body;
  assert.doesNotMatch(html, /position:absolute|left:|top:|transform:scale|paper-canvas|height:18px/);
  assert.match(html, /<legend>BEC Master and Working Unit<\/legend>/);
  assert.match(html, /<legend>Location<\/legend>/);
  assert.match(html, /<legend>Data quality<\/legend>/);
  assert.match(html, /<legend>Field and office notes<\/legend>/);
  const inputs = html.match(/<(?:input|select|textarea)\b[^>]*id="header-[^"]*"[^>]*>/g);
  const ids = inputs.map(input => input.match(/id="([^"]*)"/)[1]);
  assert.equal(new Set(ids).size, ids.length);
  for (const id of ids) assert.ok(html.includes(`for="${id}"`), `Missing visible label for ${id}`);
  for (const column of ['Zone', 'SubZone', 'SiteSeries', 'FSRegionDistrict', 'Ecosection', 'SiteDisturbance1', 'SitePlotQuality', 'SubstrateWater', 'Latitude', 'Longitude']) {
    assert.equal(inputs.filter(input => input.includes(`data-column="${column}"`)).length, 1, column);
  }
  assert.match(html, /id="header-plotNumber"[^>]*readonly/);
  assert.match(html, /Unchanged q'X4/);
  assert.match(html, /data-column="AirPhotoNum"[^>]*disabled[^>]*value="HISTORICAL"/);
  assert.match(html, /data-column="Photo"[^>]*disabled[^>]*value="PHOTO"/);
  assert.match(html, /data-column="UpdatedFromCards"[^>]*checked[^>]*disabled/);
});
test('Responsive presentation never enables unsupported or locked header workflows', () => {
  for (const props of [headerProps({ capabilities: {} }), headerProps({ disabled: true })]) {
    const html = render(HeaderEditor, { props }).body;
    const inputs = html.match(/<(?:input|select|textarea)\b[^>]*id="header-[^"]*"[^>]*>/g);
    assert.ok(inputs.filter(input => props.disabled || /\bdata-column=/.test(input)).every(input => /\bdisabled\b/.test(input)));
  }
});
test('Routine guidance starts collapsed without hiding validation, loading, warnings or review controls', () => {
  const html = render(HeaderEditor, { props: headerProps() }).body;
  const guides = html.match(/<details class="field-guidance"[^>]*>/g);
  assert.equal(guides.length, 5);
  assert.ok(guides.every(tag => !/\bopen\b/.test(tag)));
  assert.ok(html.indexOf('id="header-fieldNo"') < html.indexOf('<details class="field-guidance"'));
  for (const file of ['WorkingUnitFields', 'QualityFields', 'SiteCodeFields', 'RegionCodeFields',
    'SubstrateFields', 'SoilCodeFields', 'GeologyCodeFields']) {
    const source = read(`${file}.svelte`);
    const guidance = source.match(/<FieldGuidance\b[^>]*>([\s\S]*?)<\/FieldGuidance>/);
    assert.ok(guidance, file);
    assert.doesNotMatch(guidance[1], /role="alert"|role="status"|acknowledg|warnings|errors|validation|copy-confirmation/);
    assert.equal(compile(source, { filename: `${file}.svelte`, generate: 'client' }).warnings.length, 0);
  }
});
test('All other pages SSR retain labels, child links, stored values and readonly controls', () => {
  const SourcePage = serverComponent(read('SourcePage.svelte'), 'SourcePage.svelte', dependencies);
  const Fixture = serverComponent(`
    <script>import SourcePage from './SourcePage.svelte'; let { name, vegetationMode } = $props();</script>
    <SourcePage {name} {vegetationMode} values={new Map([['plotnumber', 'RESPONSIVE'], ['soilnotes', 'Raw note']])}>
      {#snippet embedded(control)}<div data-child-link={control.controlId}>Child</div>{/snippet}
    </SourcePage>`, 'ResponsivePagesFixture.svelte', { './SourcePage.svelte': { default: SourcePage } });
  for (const [name, vegetationMode] of [['Soil/Terrain'], ['Vegetation', 'initial'], ['Vegetation', 'height'], ['Veg Other'], ['Other']]) {
    const html = render(Fixture, { props: { name, vegetationMode } }).body;
    const controls = paper.paperPage(name, vegetationMode).controls.filter(control => !['Label', 'Rectangle', 'OptionGroup'].includes(control.type));
    for (const control of controls) assert.equal(html.split(`data-source-control="${control.controlName}"`).length - 1, 1);
    assert.ok((html.match(/<(?:input|textarea)\b[^>]*>/g) ?? []).every(input => /\bdisabled\b/.test(input)));
    assert.match(html, /<label class="form-field/);
    assert.match(html, /data-child-link=/);
    assert.doesNotMatch(html, /position:absolute|left:|top:|transform:scale/);
    if (name === 'Soil/Terrain') {
      assert.match(html, /<legend>Surface terrain<\/legend>/);
      assert.match(html, /<legend>Subsurface terrain<\/legend>/);
      assert.match(html, /<legend>Organic horizons \/ layers<\/legend>/);
      assert.match(html, /Raw note/);
    }
    if (name === 'Veg Other') {
      assert.match(html, /Column legend/);
      assert.match(html, /LL = Arboreal Lichen loading code/);
      assert.match(html, /FFA = Fruit\/Flower abundance code/);
    }
  }
});
test('Child SSR uses readable table headings, local scrolling, lexical drafts and unchanged action gates', () => {
  const child = serverComponent(read('SourceChild.svelte'), 'SourceChild.svelte', {
    ...dependencies, './heightEditor': loadTypeScript('heightEditor.ts', { './numericEditor': loadTypeScript('numericEditor.ts') })
  });
  const html = render(child, { props: {
    name: 'SubVegAhtXL', disabled: true, rows: [{ id: 1, values: { species: 'Abies', cover1: 5, height1: 12 } }],
    onstage() {}, ondelete() {}, drafts: { '1': { height1: { raw: '12x', value: null, expected: 12, error: 'Invalid height' } } }
  } }).body;
  assert.match(html, /<table/);
  assert.match(html, /<th scope="col"/);
  assert.ok(html.indexOf('Species</th>') < html.indexOf('A1 cover (%)</th>'));
  assert.match(html, /data-column="Height1"/);
  assert.match(html, /value="12x"/);
  assert.match(html, /aria-invalid="true"/);
  assert.match(html, /Delete SubVegAhtXL row 1/);
  assert.ok(html.match(/<input\b[^>]*>/g).every(input => /\bdisabled\b/.test(input)));
  assert.doesNotMatch(html, /position:absolute|left:|top:|height:\d+px/);
  assert.match(read('SourceChild.svelte'), /overflow-x: auto/);
});
test('Responsive CSS defines readable controls and container-aware wide-to-single-column reflow without duplicated UI', () => {
  const css = read('vpro.css');
  assert.match(css, /grid-template-columns: repeat\(12, minmax\(0, 1fr\)\)/);
  for (const width of [900, 620, 420]) assert.match(css, new RegExp(`@container fs882-fields \\(max-width: ${width}px\\)`));
  assert.match(css, /min-height: 40px/);
  assert.match(css, /BC Sans|IBM Plex Sans/);
  assert.match(css, /border-top:\s*3px solid (?:#bd9b48|#003366|#FCBA19|var\(--bcgov-gold\)|var\(--vpro-)/i);
  assert.match(read('ShellChromeHeader.svelte'), /aria-expanded=\{ui\.contextExpanded\}\s+aria-controls="project-context"/);
  for (const file of ['HeaderEditor', 'SourcePage', 'SourceChild', 'BECFields', 'CoordinateFields', 'WorkingUnitFields',
    'QualityFields', 'SubstrateFields', 'RegionCodeFields', 'SiteCodeFields', 'SoilCodeFields', 'GeologyCodeFields']) {
    const source = read(`${file}.svelte`);
    assert.equal(compile(source, { filename: `${file}.svelte`, generate: 'client' }).warnings.length, 0);
    assert.doesNotMatch(source, /position:\s*absolute|transform:scale|ResizeObserver|appendChild|appendTo/);
  }
});

test('Proportional 12-column card zones, 6-cell Substrate strip and Surface/Subsurface terrain spans align with printed forms', () => {
  assert.equal(presentation.groupCardZone('Site', 'Identity and survey'), 'top-band');
  assert.equal(presentation.groupCardZone('Site', 'Project'), 'top-band');
  assert.equal(presentation.groupCardZone('Site', 'Location'), 'quad-left');
  assert.equal(presentation.groupCardZone('Site', 'Coordinate display'), 'quad-left');
  assert.equal(presentation.groupCardZone('Site', 'BEC Master and Working Unit'), 'quad-right');
  assert.equal(presentation.groupCardZone('Site', 'Site classification'), 'quad-right');
  assert.equal(presentation.groupCardZone('Site', 'Site conditions and stand'), 'quad-right');
  assert.equal(presentation.groupCardZone('Site', 'Substrate (%)'), 'full');
  assert.equal(presentation.groupCardZone('Site', 'Field and office notes'), 'full');

  assert.equal(presentation.groupCardZone('Soil/Terrain', 'Survey'), 'top-band');
  assert.equal(presentation.groupCardZone('Soil/Terrain', 'Geology'), 'top-band');
  assert.equal(presentation.groupCardZone('Soil/Terrain', 'Surface terrain'), 'full');
  assert.equal(presentation.groupCardZone('Soil/Terrain', 'Subsurface terrain'), 'full');
  assert.equal(presentation.groupCardZone('Soil/Terrain', 'Soil classification'), 'quad-left');
  assert.equal(presentation.groupCardZone('Soil/Terrain', 'Humus form'), 'quad-left');
  assert.equal(presentation.groupCardZone('Soil/Terrain', 'Hydrogeology'), 'quad-right');
  assert.equal(presentation.groupCardZone('Soil/Terrain', 'Rooting and restricting layer'), 'quad-right');
  assert.equal(presentation.groupCardZone('Soil/Terrain', 'Water and drainage'), 'quad-right');

  assert.equal(presentation.groupCardZone('Vegetation', 'Vegetation survey'), 'quad-left');
  assert.equal(presentation.groupCardZone('Vegetation', 'Stratum cover (%)'), 'quad-right');
  assert.equal(presentation.groupCardZone('Vegetation', 'Tree and shrub strata (A / B)'), 'full');

  const siteControls = paper.paperPage('Site').controls;
  const siteGroups = presentation.presentationGroups('Site', siteControls);
  const substrateGroup = siteGroups.find(g => g.title === 'Substrate (%)');
  assert.ok(substrateGroup);
  assert.deepEqual(
    Array.from(substrateGroup.controls, c => c.column),
    ['SubstrateOrganicMatter', 'SubstrateDecWood', 'SubstrateBedRock', 'SubstrateRocks', 'SubstrateMineralSoil', 'SubstrateWater']
  );
  for (const ctrl of substrateGroup.controls) {
    assert.equal(presentation.controlColumnSpan('Site', 'Substrate (%)', ctrl), 2);
  }

  const notesGroup = siteGroups.find(g => g.title === 'Field and office notes');
  assert.ok(notesGroup);
  for (const ctrl of notesGroup.controls) {
    assert.equal(presentation.controlColumnSpan('Site', 'Field and office notes', ctrl), 6);
  }

  const soilControls = paper.paperPage('Soil/Terrain').controls;
  const soilGroups = presentation.presentationGroups('Soil/Terrain', soilControls);
  const surfIdx = soilGroups.findIndex(g => g.title === 'Surface terrain');
  const subSurfIdx = soilGroups.findIndex(g => g.title === 'Subsurface terrain');
  assert.equal(subSurfIdx, surfIdx + 1, 'Subsurface terrain must sit directly below Surface terrain');
  assert.equal(soilGroups[surfIdx].controls.length, 4);
  assert.equal(soilGroups[subSurfIdx].controls.length, 4);
  for (const ctrl of soilGroups[surfIdx].controls) {
    assert.equal(presentation.controlColumnSpan('Soil/Terrain', 'Surface terrain', ctrl), 3);
  }
  for (const ctrl of soilGroups[subSurfIdx].controls) {
    assert.equal(presentation.controlColumnSpan('Soil/Terrain', 'Subsurface terrain', ctrl), 3);
  }

  assert.equal(presentation.isUnmigratedStubControl({ controlName: 'Option477', type: 'OptionButton' }), true);
  assert.equal(presentation.isUnmigratedStubControl({ controlName: 'Toggle408', type: 'ToggleButton' }), true);
  assert.equal(presentation.isUnmigratedStubControl({ controlName: 'btnCoverAndHeight', type: 'ToggleButton' }), false);
  assert.equal(presentation.isUnmigratedStubControl({ controlName: 'btnLoadMetadata', type: 'CommandButton' }), false);

  const siteHtml = render(HeaderEditor, { props: headerProps() }).body;
  assert.match(siteHtml, /data-card-zone="top-band"/);
  assert.match(siteHtml, /data-card-zone="quad-left"/);
  assert.match(siteHtml, /data-card-zone="quad-right"/);
  assert.match(siteHtml, /data-col-span="2"/);
  assert.match(siteHtml, /data-substrate-total/);
  assert.doesNotMatch(siteHtml, /class="form-status"/);
});

module.exports.renderResponsiveFixture = (name = 'Site', vegetationMode = 'initial') => {
  if (name === 'Site') return render(HeaderEditor, { props: headerProps() }).body;
  const SourcePage = serverComponent(read('SourcePage.svelte'), 'SourcePage.svelte', dependencies);
  const SourceChild = serverComponent(read('SourceChild.svelte'), 'SourceChild.svelte', {
    ...dependencies, './heightEditor': loadTypeScript('heightEditor.ts', { './numericEditor': loadTypeScript('numericEditor.ts') })
  });
  const Fixture = serverComponent(`
    <script>
      import SourcePage from './SourcePage.svelte';
      import SourceChild from './SourceChild.svelte';
      import { embeddedForm } from './paperLayout';
      let { name, vegetationMode } = $props();
      const rows = [{ id: 1, values: { species: 'Abies', cover1: 5, height1: 12, horizon: 'LF',
        upperdepth: 0, lowerdepth: 10, comment: 'Readonly preview', dataname: 'Example', dataitem: 'Raw value' } }];
    </script>
    <SourcePage {name} {vegetationMode} values={new Map([['plotnumber', 'RESPONSIVE']])}>
      {#snippet embedded(control)}
        {@const child = embeddedForm(control.controlId)}
        <SourceChild name={child.form} {rows} disabled={true} />
      {/snippet}
    </SourcePage>`, 'ResponsiveValidationFixture.svelte', {
    './SourcePage.svelte': { default: SourcePage }, './SourceChild.svelte': { default: SourceChild }, './paperLayout': paper
  });
  return render(Fixture, { props: { name, vegetationMode } }).body;
};
