const assert = require('node:assert/strict');
const {test} = require('node:test');
const {readFileSync} = require('node:fs');
const path = require('node:path');
const {compile} = require('svelte/compiler');
const {render} = require('svelte/server');
const { componentFunctions, loadTypeScript, serverComponent, srcPath } = require('./svelteTestHelpers.cjs');
const resource = name => JSON.parse(readFileSync(path.join(__dirname,'..','..','resources',name),'utf8'));
const quality = loadTypeScript('qualityEditor.ts',{'./becEditor':loadTypeScript('becEditor.ts')});
const metadata = loadTypeScript('projectMetadataEditor.ts',{'./qualityEditor':quality,
  '../../resources/project-metadata-standard.json':resource('project-metadata-standard.json'),
  '../../resources/project-metadata-template.json':resource('project-metadata-template.json')});
const profile = loadTypeScript('projectPlotProfileReview.ts',{'./projectMetadataEditor':metadata});
const profileFile = loadTypeScript('profileFile.ts',{'./projectPlotProfileReview':profile});
const profileTable = loadTypeScript('profileTable.ts',{'./profileFile':profileFile,'./projectPlotProfileReview':profile});
const read = name => readFileSync(srcPath(name),'utf8');
const nullCell = () => ({storage:'null',text:null,integer:null,real:null,blobHex:null});
const rules = {columns:Array.from(profile.plotProfileFields,name=>({name,declaredType:'TEXT'})),
  rows:['1','2'].map(rowId=>({rowId,cells:Array.from({length:9},nullCell)}))};
const preview = {project:'Sample',table:'Sample_Profile',su:'None',totalPlots:4,plotNumbers:[" A' # ",'Z'],
  steps:[{rowId:'1',order:1,operation:'Add plots',plotCount:4,remaining:4},
    {rowId:'2',order:2,operation:'Subtract plots',plotCount:2,remaining:2}]};
const proposal = {input:{originalRules:rules,projectLump:null,subvarieties:false},preview};
const summary = plotNumber => ({plotNumber,fieldNumber:null,plotRepresenting:null,zone:null,subZone:null,siteSeries:null});
const navigation = () => ({contextId:'owned',result:structuredClone(preview),plots:preview.plotNumbers.map(summary)});

test('Scoped navigation preserves exact literal membership and paginates one immutable approved recordset',()=>{
  const source=profile.validateProfileNavigation(navigation(),proposal,'owned');
  const first=profile.profileNavigationPage(source,'owned',0,1);
  const second=profile.profileNavigationPage(source,'owned',1,1);
  assert.equal(first.total,2); assert.equal(first.plots[0].plotNumber," A' # ");
  assert.equal(second.total,2); assert.equal(second.plots[0].plotNumber,'Z');
  assert.equal(profile.profileNavigationPage(source,'owned',2,1).plots.length,0);
  for(const [id,offset,limit] of [['stale',0,1],['owned',-1,1],['owned',0,201],['owned',0,0],['owned',.5,1]]) {
    assert.throws(()=>profile.profileNavigationPage(source,id,offset,limit),/stale or out of range/);
  }
});

test('Navigation rejects foreign scopes, inconsistent counts, normalization, duplicate summaries and missing fields',()=>{
  for(const alter of [
    value=>value.contextId='stale',value=>value.result.su='Other',value=>value.result.totalPlots=5,
    value=>value.result.steps[0].plotCount=3,value=>value.result.plotNumbers[0]="A' #",
    value=>value.plots[0].plotNumber="A' #",value=>value.plots.reverse(),
    value=>value.plots[1]=value.plots[0],value=>value.plots=null,
    value=>delete value.plots[0].fieldNumber,value=>value.plots[0].zone=5
  ]) {
    const value=navigation(); alter(value);
    assert.throws(()=>profile.validateProfileNavigation(value,proposal,'owned'));
  }
});

test('Zero and over200 previews stay unavailable without clearing an existing filter; exact200 remains supported',()=>{
  for(const [count,unavailable] of [[0,true],[1,false],[200,false],[201,true]]) {
    const result={...preview,plotNumbers:Array.from({length:count},(_,index)=>String(index))};
    assert.equal(profile.profileFilterUnavailable(result)!==null,unavailable);
  }
});

test('Apply/Clear/Previous/Next reuse transition ownership and revalidation before publishing, with context retirement and a fresh plot mount',()=>{
  const { readShellComposite, readProjectPlotProfileComposite } = require('./svelteTestHelpers.cjs');
  const app=readShellComposite(),panel=readProjectPlotProfileComposite();
  assert.match(panel,/allowFiltering = false/);
  assert.match(panel,/disabled=\{busy \|\| blocked \|\| profileFilterUnavailable\(result\) !== null\}/);
  assert.match(panel,/runInput = \$state\.snapshot\(input\)/);
  assert.match(panel,/structuredClone\(\$state\.snapshot\(\{\s*input:\s*runInput,\s*preview:\s*result\s*\}\)\)/);
  assert.match(app,/onProfileNavigation=/);
  for(const name of ['applyProfileNavigation','clearProfileNavigation','navigateProfilePlot']) {
    const start=app.indexOf(`async function ${name}`);
    assert.ok(start>=0, name);
    assert.match(app.slice(start, start + 900),/requestTransition/);
  }
  assert.match(app,/const next = await resolveNavigation\(proposal, contextId\);[\s\S]*?profileNavigation:\s*next,\s*page:\s*nextPage/);
  assert.match(app,/const next = await resolveNavigation\(source\.proposal, contextId\);[\s\S]*?editorPlotNumber:\s*target/);
  assert.match(app,/resolveNavigation\(\s*(?:source|s0\.profileNavigation)\.proposal,\s*(?:source|s0\.profileNavigation)\.contextId\s*\)/);
  assert.match(app,/(?:latest\.)?profileNavigation && (?:latest\.)?profileNavigation\.contextId !== state\.contextId/);
  assert.match(app,/projectState\.set\(state\)[\s\S]*?profileNavigation = null|profileNavigation:\s*null/);
  assert.match(app,/\{#key \$projectState\?\.contextId\}[\s\S]*?\{#key editorEntryForm\}[\s\S]*?\{#key editorPlotNumber\}/);
  assert.match(app,/<fieldset disabled=\{busy\} class="contents">/);
  assert.match(app,/await tick\(\);\s*const next = await resolveNavigation/);
  assert.doesNotMatch(app,/SetProfileFilter|CreateSU|UpdatePlotCount/);
});

test('Independent profile write authorization is default-off and shared-transition owned, not inferred from selection',()=>{
  const { readShellComposite, readPlotProfileComposite } = require('./svelteTestHelpers.cjs');
  const app=readPlotProfileComposite();
  assert.match(readShellComposite(),/<PlotProfilePanel/);
  assert.match(app,/aria-label="Reviewed profile write ownership"/);
  assert.match(app,/Context changes or\s+restart clear it/);
  assert.match(app,/profileWriteContext !== \$projectState\.contextId|profileWriteContext !== host\.getCurrentContextId\(\)/);
  const start=app.indexOf('export async function publishProfileWriteOwnershipOp');
  const action=app.slice(start, start + 1500);
  assert.match(app,/\$state\.snapshot\(profileWriteReview\)|review:\s*profileWriteReview,\s*enabled:\s*!profileWriteReview\.source\.writable,\s*confirmed:\s*true/);
  assert.match(action,/await host\.requestTransition/);
  assert.match(action,/contextId !== profileWriteContext/);
  assert.match(action,/await tick\(\);\s*const state = await ContextService\.SetPlotProfileEditing/);
  assert.match(app,/projectState\.set\(state\);\s*profileNavigation = null/);
  assert.match(app,/view = 'plots'/);
  assert.match(action,/do not replay/);
  assert.doesNotMatch(action,/SwitchContext|SelectPlotProfile|SaveProjectPlotProfile/);
});

test('Write ownership review preserves exact physical source, typed rules and NULL/empty descriptions',()=>{
  const source={source:{name:" Other' # ",path:"C:\\profile O'Brien #.db"},table:" Other' # _Profile",available:true,writable:false,reason:''};
  const review={project:'Sample',table:source.table,rules:structuredClone(rules),
    descriptions:{columns:[{name:'table_name',declaredType:'TEXT'},{name:'description',declaredType:'TEXT'}],
      rows:[{rowId:'1',cells:[{storage:'text',text:source.table},nullCell()]},
        {rowId:'2',cells:[{storage:'text',text:source.table},{storage:'text',text:''}]}]},source};
  const result=profile.validateProjectPlotProfileReview(review);
  assert.equal(result.source.source.name,source.source.name);
  assert.equal(result.descriptions.rows[0].cells[1].storage,'null');
  assert.equal(result.descriptions.rows[1].cells[1].text,'');
  for(const alter of [value=>value.table='Sample_Profile',value=>value.source.writable='true',
    value=>value.rules.rows[1].rowId=value.rules.rows[0].rowId,value=>delete value.descriptions.columns]){
    const value=structuredClone(review);alter(value);
    assert.throws(()=>profile.validateProjectPlotProfileReview(value));
  }
});

test('Genuine absent description metadata differs from an empty physical metadata table or malformed response',()=>{
  const source={source:{name:'Bare',path:'C:\\bare.db'},table:'Bare_Profile',available:true,writable:false,reason:''};
  const review={project:'Sample',table:source.table,rules:structuredClone(rules),
    descriptions:{columns:[],rows:[]},source};
  assert.deepEqual(JSON.parse(JSON.stringify(profile.validateProjectPlotProfileReview(review).descriptions)),{columns:[],rows:[]});
  review.descriptions={columns:[{name:'table_name',declaredType:'TEXT'},{name:'description',declaredType:'TEXT'}],rows:[]};
  assert.equal(profile.validateProjectPlotProfileReview(review).descriptions.columns.length,2);
  for(const descriptions of [null,{columns:null,rows:[]},{columns:[],rows:null},
    {columns:[],rows:[{rowId:'1',cells:[]}]},{columns:[{name:'table_name',declaredType:'TEXT'}],rows:[]}]){
    assert.throws(()=>profile.validateProjectPlotProfileReview({...review,descriptions}));
  }
});

test('Blank profile-file creation preserves the exact original template and rejects partial or populated proposals',()=>{
  const review={metadataAbsent:true,template:{columns:profile.plotProfileFields.map((name,index)=>({
    name,declaredType:index===0?'SMALLINT':index===8?'INTEGER':'VARCHAR'})),rows:[]}};
  assert.equal(profileFile.validateProfileFileReview(review).template.columns.length,9);
  for(const alter of [value=>delete value.metadataAbsent,value=>value.metadataAbsent=false,
    value=>value.template.rows=[rules.rows[0]],value=>value.template.columns.reverse(),
    value=>value.template.columns[0].declaredType='INTEGER',value=>value.template.columns.pop()]){
    const invalid=structuredClone(review);alter(invalid);
    assert.throws(()=>profileFile.validateProfileFileReview(invalid));
  }
  const result={source:{name:'NewBlank',path:"C:\\new O'Brien #.db"},table:'NewBlank_Profile',ruleCount:0};
  assert.equal(profileFile.validateProfileFileCreated(result,'NewBlank'),result);
  for(const value of [{...result,ruleCount:1},{...result,table:'Other_Profile'},{...result,source:{name:'NewBlank',path:''}}])
    assert.throws(()=>profileFile.validateProfileFileCreated(value,'NewBlank'),/do not replay/);
});

test('New profile-file publication is separately default-off, shared-transition owned and never an implicit attach or grant',()=>{
  const { readPlotProfileComposite } = require('./svelteTestHelpers.cjs');
  const app=readPlotProfileComposite();
  assert.match(app,/aria-label="Reviewed blank profile file creation"/);
  assert.match(app,/<label for="profile-file-name"/);
  assert.match(app,/<label for="profile-file-path"/);
  const start=app.indexOf('export async function createBlankProfileFileOp');
  const action=app.slice(start, start + 3000);
  assert.match(app,/\$state\.snapshot\(profileFileReview\)|review:\s*profileFileReview,\s*name:\s*profileFileName,\s*path:\s*profileFilePath,\s*confirmed:\s*true/);
  assert.match(action,/await host\.requestTransition/);
  assert.match(action,/await tick\(\);\s*const response = await ContextService\.CreatePlotProfileFile/);
  assert.match(action,/setProfileFileCommitted\(true\)/);
  assert.match(action,/do not replay creation/);
  assert.match(app,/view = 'plots';\s*editorPlotNumber = undefined/);
  assert.doesNotMatch(action,/SetPlotProfileEditing|SelectPlotProfile|SwitchContext/);
  assert.match(app,/profileFileCommitted\s*\|\|\s*!profileFileName\s*\|\|\s*!profileFilePath/);
});

test('Existing-file profile creation requires exact original template and current selected-file writer ownership',()=>{
  const source={source:{name:'Owned',path:"C:\\owned O'Brien #.db"},table:'Owned_Profile',available:true,writable:true,reason:''};
  const review={template:{metadataAbsent:true,template:{columns:profile.plotProfileFields.map((name,index)=>({
    name,declaredType:index===0?'SMALLINT':index===8?'INTEGER':'VARCHAR'})),rows:[]}},
    profile:{project:'Sample',table:source.table,rules:structuredClone(rules),descriptions:{columns:[],rows:[]},source}};
  assert.equal(profileTable.validateProfileTableReview(review).profile.source.source.path,source.source.path);
  for(const alter of [value=>value.profile.source.writable=false,value=>value.profile.source.available=false,
    value=>value.profile.table='Foreign_Profile',value=>value.template.metadataAbsent=false,
    value=>value.profile.descriptions=null,value=>value.template.template.columns.pop()]){
    const invalid=structuredClone(review);alter(invalid);
    assert.throws(()=>profileTable.validateProfileTableReview(invalid));
  }
  const result={source:{name:'New',path:source.source.path},table:'New_Profile',ruleCount:0};
  assert.equal(profileTable.validateProfileTableCreated(result,'New',source.source.path),result);
  for(const response of [{...result,ruleCount:1},{...result,table:'Foreign_Profile'},
    {...result,source:{name:'New',path:'C:\\another.db'}}]){
    assert.throws(()=>profileTable.validateProfileTableCreated(response,'New',source.source.path),/do not replay/);
  }
});

test('Existing-file creation is separately gated inside profile selection, shares draft transitions and never switches or grants',()=>{
  const { readPlotProfileComposite } = require('./svelteTestHelpers.cjs');
  const app=readPlotProfileComposite();
  assert.match(app,/\$projectState\.plotProfile\.writable/);
  const panel=app.indexOf('aria-label="Reviewed existing-file profile creation"');
  assert.ok(panel >= 0);
  assert.ok(app.includes('aria-label="Stored plot profile selection"'));
  assert.match(app,/<label for="profile-table-name"/);
  assert.match(app,/profileTableReview\.profile\.source\.source\.path/);
  const start=app.indexOf('export async function createBlankProfileTableOp');
  const action=app.slice(start, start + 3000);
  assert.match(app,/\$state\.snapshot\(profileTableReview\)|review:\s*profileTableReview,\s*name:\s*profileTableName,\s*confirmed:\s*true/);
  assert.match(action,/await host\.requestTransition/);
  assert.match(action,/contextId !== profileTableContext/);
  assert.match(action,/await tick\(\);\s*const response = await ContextService\.CreatePlotProfileTable/);
  assert.match(action,/setProfileTableCommitted\(true\)/);
  assert.match(action,/do not replay creation/);
  assert.match(app,/view = 'plots';\s*editorPlotNumber = undefined/);
  assert.doesNotMatch(action,/SetPlotProfileEditing|SelectPlotProfile|SwitchContext/);
});

function makeWritableStore(initial) {
  let value = initial;
  const subs = new Set();
  return {
    subscribe(fn) {
      fn(value);
      subs.add(fn);
      return () => subs.delete(fn);
    },
    set(next) {
      value = next;
      for (const fn of subs) fn(value);
    },
  };
}

function makeSelectionController(overrides = {}) {
  return {
    profilePath: '',
    setProfilePath() {},
    profileSources: [],
    profileSourceContext: '',
    profileSourceError: '',
    profileWriteReview: null,
    profileWriteContext: '',
    profileWriteError: '',
    profileFileReview: null,
    profileFileContext: '',
    profileFileName: '',
    setProfileFileName() {},
    profileFilePath: '',
    setProfileFilePath() {},
    profileFileError: '',
    profileFileSuccess: '',
    profileFileCommitted: false,
    profileTableReview: null,
    profileTableContext: '',
    profileTableName: '',
    setProfileTableName() {},
    profileTableError: '',
    profileTableSuccess: '',
    profileTableCommitted: false,
    busy: false,
    editorBusy: false,
    transitionWorking: false,
    pendingTransition: null,
    inspectSources() {},
    chooseProfile() {},
    reviewWriteOwnership() {},
    publishWriteOwnership() {},
    dismissWriteOwnership() {},
    reviewBlankFile() {},
    createBlankFile() {},
    dismissBlankFile() {},
    reviewBlankTable() {},
    createBlankTable() {},
    dismissBlankTable() {},
    ...overrides,
  };
}

test('PlotProfilePanel omits global PlotProfileSelectionSection across non-profiling views while preserving slim navigation bar', () => {
  const panelSrc = read('PlotProfilePanel.svelte');
  assert.doesNotMatch(panelSrc, /PlotProfileSelectionSection/);
  assert.doesNotMatch(panelSrc, /Stored plot profile selection/);

  const stateStore = makeWritableStore({
    contextId: 'owned',
    activeProject: 'Sample',
    projectPath: '/data/Sample.db',
    activeSU: 'None',
    plotProfile: {
      source: { name: 'Sample', path: '/data/Sample.db' },
      table: 'Sample_Profile',
      available: true,
      writable: true,
      reason: '',
    },
  });
  const PlotProfilePanel = serverComponent(panelSrc, 'PlotProfilePanel.svelte', {
    '../../bindings/github.com/boostao/vpro/app': { ContextService: {} },
    '../classification/profileFile': profileFile,
    '../classification/profileSU': {},
    '../classification/profileSUProject': {},
    '../classification/profileTable': profileTable,
    '../classification/projectPlotProfileReview': profile,
    '../shared/readRequests': { formatError: (e) => String(e) },
    '../shared/state': { projectState: stateStore },
    './plotProfileOps': {},
    './PlotProfileSUSection.svelte': { default: () => '' },
  });

  const baseProps = {
    busy: false,
    error: '',
    editorPlotNumber: undefined,
    profileNavigation: null,
    selected: null,
    page: null,
    profileIndex: -1,
    stateReads: { track: (p) => p },
    requestTransition: async (fn) => fn('owned'),
    loadPlots: async () => {},
    navigateProfilePlot: async () => {},
    clearProfileNavigation: async () => {},
    cancelAllReads: () => {},
  };

  for (const view of ['home', 'geospatial-map', 'plots', 'classification-explorer', 'project-admin', 'summary-vegetation']) {
    const html = render(PlotProfilePanel, { props: { ...baseProps, view } }).body;
    assert.doesNotMatch(html, /Stored plot profile selection/, `Selector must not render globally on ${view}`);
    assert.doesNotMatch(html, /Plot profile:/, `Global plot profile details must not render on ${view}`);
    assert.doesNotMatch(html, /Active profile navigation/, `Nav bar must stay hidden when inactive on ${view}`);
    assert.doesNotMatch(html, /<details\b/, `No global <details> box on ${view}`);
  }

  const activeNav = profile.validateProfileNavigation(navigation(), proposal, 'owned');
  const fs882Html = render(PlotProfilePanel, {
    props: { ...baseProps, view: 'fs882', profileNavigation: activeNav, profileIndex: 0 },
  }).body;
  assert.match(fs882Html, /aria-label="Active profile navigation"/);
  assert.match(fs882Html, /2 of 4 stored plots in reviewed profile navigation\./);
  assert.match(fs882Html, /Record 1 of 2/);
  assert.match(fs882Html, /Previous profile plot/);
  assert.match(fs882Html, /Next profile plot/);
  assert.match(fs882Html, /Clear profile navigation/);
  assert.doesNotMatch(fs882Html, /Stored plot profile selection/);

  const plotsNavHtml = render(PlotProfilePanel, {
    props: { ...baseProps, view: 'plots', profileNavigation: activeNav, profileIndex: -1 },
  }).body;
  assert.match(plotsNavHtml, /aria-label="Active profile navigation"/);
  assert.match(plotsNavHtml, /Clear profile navigation/);
  assert.doesNotMatch(plotsNavHtml, /Record 1 of 2/);
  assert.doesNotMatch(plotsNavHtml, /Stored plot profile selection/);
});

test('PlotProfileSelectionSection renders inside ProjectPlotProfileReview including None, external write-ownership, and blank creation', () => {
  const noneState = makeWritableStore({
    contextId: 'ctx-none',
    activeProject: 'Sample',
    projectPath: '/data/Sample.db',
    activeSU: 'None',
    plotProfile: {
      source: { name: 'None', path: '' },
      table: '',
      available: false,
      writable: false,
      reason: 'No profile selected',
    },
  });
  const BlankReviews = serverComponent(read('PlotProfileBlankReviews.svelte'), 'PlotProfileBlankReviews.svelte', {
    '../shared/state': { projectState: noneState },
  });
  const SelectionSection = serverComponent(read('PlotProfileSelectionSection.svelte'), 'PlotProfileSelectionSection.svelte', {
    '../shared/state': { projectState: noneState },
    './PlotProfileBlankReviews.svelte': { default: BlankReviews },
  });
  const Header = serverComponent(read('ProjectPlotProfileHeader.svelte'), 'ProjectPlotProfileHeader.svelte', {});
  const Review = serverComponent(read('ProjectPlotProfileReview.svelte'), 'ProjectPlotProfileReview.svelte', {
    '../shared/readRequests': { ReadRequests: class { cancelAll() {} track(p) { return p; } }, formatError: (e) => String(e), trackIfCancellable: (_r, p) => p },
    '../shared/state': { projectState: noneState },
    '../shell/PlotProfileSelectionSection.svelte': { default: SelectionSection },
    './ProjectPlotProfileHeader.svelte': { default: Header },
    './ProjectPlotProfilePreviewSection.svelte': { default: () => '' },
    './ProjectPlotProfileRulesSection.svelte': { default: () => '' },
    './projectProfileSpeciesPresence': { validateSpeciesPresencePreview: (x) => x },
    './projectProfileRuleEditor': {
      profileCreationErrors: () => [],
      profileRuleErrors: () => [],
      profileRulesDirty: () => false,
      validateProfileChoices: (x) => x,
    },
    './projectPlotProfileReview': profile,
    '../../bindings/github.com/boostao/vpro/app': { ClassificationService: {} },
  });

  const noneHtml = render(Review, {
    props: {
      client: {},
      contextId: 'ctx-none',
      profileSelection: makeSelectionController(),
      onclosed() {},
      onbusy() {},
      onblocked() {},
    },
  }).body;
  assert.match(noneHtml, /Plot profiling — no profile selected/);
  assert.match(noneHtml, /data-plot-profile-selection[^>]*open/);
  assert.match(noneHtml, /Plot profile: None/);
  assert.match(noneHtml, /Inspect stored profiles/);
  assert.match(noneHtml, /Select no profile/);
  assert.match(noneHtml, /Review new blank profile file/);
  assert.match(noneHtml, /data-profile-none-notice/);
  assert.doesNotMatch(noneHtml, /Review profile write ownership/);
  assert.doesNotMatch(noneHtml, /Review blank profile in selected file/);

  // External read-only profile with write-ownership review + discovered sources
  const extSource = {
    source: { name: 'External', path: '/data/External.db' },
    table: 'External_Profile',
    available: true,
    writable: false,
    reason: '',
  };
  const extReview = {
    project: 'Sample',
    table: 'External_Profile',
    rules: structuredClone(rules),
    descriptions: { columns: [], rows: [] },
    source: extSource,
  };
  noneState.set({
    contextId: 'ctx-ext',
    activeProject: 'Sample',
    projectPath: '/data/Sample.db',
    activeSU: 'None',
    plotProfile: extSource,
  });
  const extHtml = render(SelectionSection, {
    props: {
      selection: makeSelectionController({
        profileSources: [extSource],
        profileSourceContext: 'ctx-ext',
        profileWriteReview: extReview,
        profileWriteContext: 'ctx-ext',
      }),
    },
  }).body;
  assert.match(extHtml, /Plot profile: External/);
  assert.match(extHtml, /Select External_Profile/);
  assert.match(extHtml, /Review profile write ownership/);
  assert.match(extHtml, /aria-label="Reviewed profile write ownership"/);
  assert.match(extHtml, /Authorize selected profile editing/);

  // Writable profile shows blank profile table creation inside selected file
  const writableSource = {
    source: { name: 'Sample', path: '/data/Sample.db' },
    table: 'Sample_Profile',
    available: true,
    writable: true,
    reason: '',
  };
  noneState.set({
    contextId: 'ctx-write',
    activeProject: 'Sample',
    projectPath: '/data/Sample.db',
    activeSU: 'None',
    plotProfile: writableSource,
  });
  const writableHtml = render(SelectionSection, {
    props: {
      selection: makeSelectionController({
        profileFileReview: { metadataAbsent: true, template: { columns: [], rows: [] } },
        profileFileContext: 'ctx-write',
        profileFileName: 'NewBlank',
        profileFilePath: '/data/NewBlank.db',
        profileTableReview: {
          template: { metadataAbsent: true, template: { columns: [], rows: [] } },
          profile: { project: 'Sample', table: 'Sample_Profile', rules: structuredClone(rules), descriptions: { columns: [], rows: [] }, source: writableSource },
        },
        profileTableContext: 'ctx-write',
        profileTableName: 'ExtraProf',
      }),
    },
  }).body;
  assert.match(writableHtml, /Create reviewed blank profile file/);
  assert.match(writableHtml, /Review blank profile in selected file/);
  assert.match(writableHtml, /Create reviewed profile in selected file/);
});

test('End-to-end profile selection, None, write-ownership, and blank creation keep Plot Profiling open inside FS882', async () => {
  const stateStore = makeWritableStore({
    contextId: 'ctx-1',
    activeProject: 'Sample',
    projectPath: '/data/Sample.db',
    activeSU: 'None',
    plotProfile: {
      source: { name: 'Sample', path: '/data/Sample.db' },
      table: 'Sample_Profile',
      available: true,
      writable: true,
      reason: '',
    },
  });
  let currentContextId = 'ctx-1';
  let currentView = 'fs882';
  let currentPlot = '001';
  let reopenFlag = false;
  let loadPlotsCalls = 0;
  let cancelReadsCalls = 0;
  const serviceCalls = [];

  const ops = loadTypeScript('shell/plotProfileOps.ts', {
    svelte: { tick: async () => {} },
    '../../bindings/github.com/boostao/vpro/app': {
      ContextService: {
        SelectPlotProfile: async (ctx, req) => {
          serviceCalls.push(['SelectPlotProfile', ctx, req]);
          currentContextId = req.name === 'None' ? 'ctx-none' : 'ctx-ext';
          return {
            contextId: currentContextId,
            activeProject: 'Sample',
            projectPath: '/data/Sample.db',
            activeSU: 'None',
            plotProfile: {
              source: req,
              table: req.name === 'None' ? '' : `${req.name}_Profile`,
              available: req.name !== 'None',
              writable: false,
              reason: req.name === 'None' ? 'No profile selected' : '',
            },
          };
        },
        SetPlotProfileEditing: async (ctx, req) => {
          serviceCalls.push(['SetPlotProfileEditing', ctx, req]);
          currentContextId = 'ctx-ext-write';
          return {
            contextId: currentContextId,
            activeProject: 'Sample',
            projectPath: '/data/Sample.db',
            activeSU: 'None',
            plotProfile: { ...req.review.source, writable: req.enabled },
          };
        },
        CreatePlotProfileFile: async (ctx, req) => {
          serviceCalls.push(['CreatePlotProfileFile', ctx, req]);
          return { source: { name: req.name, path: req.path }, table: `${req.name}_Profile`, ruleCount: 0 };
        },
        CreatePlotProfileTable: async (ctx, req) => {
          serviceCalls.push(['CreatePlotProfileTable', ctx, req]);
          return {
            source: { name: req.name, path: req.review.profile.source.source.path },
            table: `${req.name}_Profile`,
            ruleCount: 0,
          };
        },
      },
    },
    '../classification/profileFile': profileFile,
    '../classification/profileSU': {},
    '../classification/profileSUProject': {},
    '../classification/profileTable': profileTable,
    '../shared/readRequests': { formatError: (e) => String(e) },
    '../shared/state': { projectState: stateStore },
  });

  const host = {
    setBusy() {},
    getError: () => '',
    setError() {},
    resetToPlotsView: () => {
      currentView = 'plots';
      currentPlot = undefined;
    },
    afterBlankProfileCreated: () => {
      if (currentView !== 'fs882') {
        currentView = 'plots';
        currentPlot = undefined;
      }
    },
    resetContextAfterProfileSwitch: (state) => {
      const keepProfilingOpen = currentView === 'fs882';
      stateStore.set(state);
      if (keepProfilingOpen) reopenFlag = true;
      else {
        currentPlot = undefined;
        currentView = 'plots';
      }
    },
    loadPlotsZero: async () => {
      loadPlotsCalls++;
    },
    cancelAllReads: () => {
      cancelReadsCalls++;
    },
    stateReads: { track: (p) => p },
    getCurrentContextId: () => currentContextId,
    requestTransition: async (run) => run(currentContextId),
  };

  // 1. Select external profile from inside FS882 profiling dialog
  await ops.choosePlotProfileOp(host, { name: 'External', path: '/data/External.db' }, 'ctx-1');
  assert.equal(currentView, 'fs882');
  assert.equal(currentPlot, '001');
  assert.equal(reopenFlag, true);
  assert.equal(cancelReadsCalls, 1);
  assert.equal(loadPlotsCalls, 1);

  // 2. Authorize write ownership from inside FS882 profiling dialog
  reopenFlag = false;
  let writeCleared = false;
  let writeErr = '';
  const extReview = {
    project: 'Sample',
    table: 'External_Profile',
    rules: structuredClone(rules),
    descriptions: { columns: [], rows: [] },
    source: {
      source: { name: 'External', path: '/data/External.db' },
      table: 'External_Profile',
      available: true,
      writable: false,
      reason: '',
    },
  };
  await ops.publishProfileWriteOwnershipOp(host, {
    profileWriteReview: extReview,
    profileWriteContext: 'ctx-ext',
    clearWriteReview: () => {
      writeCleared = true;
    },
    setProfileWriteError: (m) => {
      writeErr = m;
    },
  });
  assert.equal(writeCleared, true);
  assert.equal(writeErr, '');
  assert.equal(currentView, 'fs882');
  assert.equal(currentPlot, '001');
  assert.equal(reopenFlag, true);

  // 3. Create blank profile file from inside FS882 profiling dialog -> stays in FS882 with confirmation
  let fileCommitted = false;
  let fileSuccess = '';
  let nextPath = '';
  await ops.createBlankProfileFileOp(host, {
    profileFileReview: {
      metadataAbsent: true,
      template: {
        columns: profile.plotProfileFields.map((name, index) => ({
          name,
          declaredType: index === 0 ? 'SMALLINT' : index === 8 ? 'INTEGER' : 'VARCHAR',
        })),
        rows: [],
      },
    },
    profileFileCommitted: false,
    profileFileContext: 'ctx-ext-write',
    profileFileName: 'FieldBlank',
    profileFilePath: '/data/FieldBlank.db',
    setProfileFileCommitted: (v) => {
      fileCommitted = v;
    },
    setProfileFileError: (m) => {
      assert.equal(m, '');
    },
    setProfileFileSuccess: (m) => {
      fileSuccess = m;
    },
    setProfilePath: (p) => {
      nextPath = p;
    },
  });
  assert.equal(fileCommitted, true);
  assert.match(fileSuccess, /Created FieldBlank_Profile with zero rules/);
  assert.equal(nextPath, '/data/FieldBlank.db');
  assert.equal(currentView, 'fs882');
  assert.equal(currentPlot, '001');

  // 4. Create blank profile table in selected file -> stays in FS882 with confirmation
  let tableCommitted = false;
  let tableSuccess = '';
  await ops.createBlankProfileTableOp(host, {
    profileTableReview: {
      template: {
        metadataAbsent: true,
        template: {
          columns: profile.plotProfileFields.map((name, index) => ({
            name,
            declaredType: index === 0 ? 'SMALLINT' : index === 8 ? 'INTEGER' : 'VARCHAR',
          })),
          rows: [],
        },
      },
      profile: {
        ...extReview,
        source: { ...extReview.source, writable: true },
      },
    },
    profileTableCommitted: false,
    profileTableContext: 'ctx-ext-write',
    profileTableName: 'SecondProf',
    setProfileTableCommitted: (v) => {
      tableCommitted = v;
    },
    setProfileTableError: (m) => {
      assert.equal(m, '');
    },
    setProfileTableSuccess: (m) => {
      tableSuccess = m;
    },
    setProfilePath: () => {},
  });
  assert.equal(tableCommitted, true);
  assert.match(tableSuccess, /Created SecondProf_Profile with zero rules/);
  assert.equal(currentView, 'fs882');

  // 5. Select no profile ('None') -> stays in FS882 and reopens profiling dialog
  reopenFlag = false;
  await ops.choosePlotProfileOp(host, { name: 'None', path: '' }, 'ctx-ext-write');
  assert.equal(currentContextId, 'ctx-none');
  assert.equal(currentView, 'fs882');
  assert.equal(reopenFlag, true);
  assert.equal(serviceCalls.length, 5);
});

test('Relocated Plot Profile selector wiring compiles warning-free and is reachable from FS882, Two-Page, and Plots', () => {
  for (const file of [
    'shell/PlotProfilePanel.svelte',
    'shell/PlotProfileSelectionSection.svelte',
    'shell/ShellWorkspaceRouter.svelte',
    'shell/ShellEntryHost.svelte',
    'shell/PlotsBrowserPanel.svelte',
    'classification/ProjectPlotProfileReview.svelte',
    'classification/ProjectPlotProfileHeader.svelte',
    'entry/FS882Form.svelte',
    'entry/FS882WorkspaceBody.svelte',
    'entry/FS882Modals.svelte',
    'entry/TwoPageEntryEditor.svelte',
    'entry/TwoPageEntryToolbar.svelte',
    'entry/TwoPageEntryReadersHost.svelte',
  ]) {
    const compiled = compile(read(file), { filename: srcPath(file), generate: 'client' });
    assert.deepEqual(compiled.warnings, [], `${file} emitted Svelte compiler warnings`);
  }

  const routerSrc = read('shell/ShellWorkspaceRouter.svelte');
  assert.match(routerSrc, /bind:selectionController=\{profileSelection\}/);
  assert.match(routerSrc, /bind:reopenProfileReview/);
  assert.match(routerSrc, /onopenprofiling=\{openPlotProfiling\}/);

  const fs882Src = read('entry/FS882Form.svelte');
  assert.match(fs882Src, /ctrl\.profileReviewOpen \|\|\s*initialProfileReviewOpen/);
  assert.match(fs882Src, /ctrl\.openProfileReviewFromToolbar\(\);\s*onConsumedInitialProfileReview\?\.\(\)/);

  const twoPageToolbarSrc = read('entry/TwoPageEntryToolbar.svelte');
  assert.match(twoPageToolbarSrc, /data-two-page-profile-manage-open/);
  assert.match(twoPageToolbarSrc, /Select Plot Profile/);
  assert.match(twoPageToolbarSrc, /Manage Plot Profile/);

  const plotsBrowserSrc = read('shell/PlotsBrowserPanel.svelte');
  assert.match(plotsBrowserSrc, /data-plots-open-profiling/);
  assert.match(plotsBrowserSrc, /data-inspector-open-profiling/);
});
