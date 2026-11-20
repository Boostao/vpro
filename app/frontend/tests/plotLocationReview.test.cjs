const assert = require('node:assert/strict');
const {test} = require('node:test');
const {readFileSync} = require('node:fs');
const path = require('node:path');
const {compile} = require('svelte/compiler');
const { componentFunctions, loadTypeScript, srcPath } = require('./svelteTestHelpers.cjs');
const quality = loadTypeScript('qualityEditor.ts', {'./becEditor':loadTypeScript('becEditor.ts')});
const cells = loadTypeScript('projectMetadataRestore.ts', {'./qualityEditor':quality,'./projectMetadataEditor':{}});
const locations = loadTypeScript('plotLocationReview.ts', {'./projectMetadataRestore':cells});
const cell = (storage,value) => ({storage,text:null,integer:null,real:null,blobHex:null,...(storage==='null'?{}:{[storage]:value})});
function document(su='Unit') {
  return {contextId:'owner',projectPath:'C:\\fixture\\Sample.db',suPath:su==='None'?'':'C:\\fixture\\Other.db',
    report:{project:'Sample',su,fields:locations.plotLocationFieldDefinitions.map(([key,label])=>({source:'Env',key,label,heading:false})),
      rows:[{envRowId:'-9007199254740993',adminRowId:'9223372036854775807',membershipRowIds:su==='None'?[]:['2','3'],
        storedLongitude:cell('real',123.25),values:[cell('text','001'),cell('text','  \u{1f332} '),cell('null'),
          cell('text','01'),cell('text',''),cell('real',54.75),cell('real',-123.25),cell('integer','200')]}]}};
}
const validate = (value,yieldTask) => locations.validatePlotLocationReview(value,'owner','Sample','C:\\fixture\\Sample.db',
  value?.report?.su || 'Unit',value?.report?.su==='None'?'':'C:\\fixture\\Other.db',yieldTask);

test('location review keeps source order, leading zeros, NULL/empty and duplicate SU membership provenance',async()=>{
  for(const value of [document(),document('None')]) {
    const accepted=await validate(value);
    assert.equal(JSON.stringify(accepted),JSON.stringify(value));
    accepted.report.rows[0].values[0].text='changed';
    accepted.report.rows[0].membershipRowIds.push('4');
    assert.equal(value.report.rows[0].values[0].text,'001');
    assert.equal(value.report.rows[0].membershipRowIds.includes('4'),false);
  }
  const empty=document();empty.report.rows=[];
  assert.equal(JSON.stringify(await validate(empty)),JSON.stringify(empty));
});

test('location longitude normalization preserves already-negative and Eastern longitudes while negating [100, 170] inputs',async()=>{
  for(const [storage,original,converted] of [
    ['real',0,0],['real',-0,-0],['real',-125.4,-125.4],['real',125.4,-125.4],['real',179.9,179.9],['real',-179.9,-179.9],['real',-190,-190],['integer','0','0'],
    ['integer','125','-125'],['integer','9223372036854775807','9223372036854775807'],['integer','-9007199254740993','-9007199254740993']]) {
    const value=document();value.report.rows[0].storedLongitude=cell(storage,original);
    value.report.rows[0].values[6]=cell(storage,converted);
    const result=await validate(value);
    assert.ok(Object.is(result.report.rows[0].values[6][storage],converted));
  }
  for(const [original,converted] of [[0,-0],[-0,0],[-123,123],[-190,190],[123,123],[179.9,-179.9]]) {
    const value=document();value.report.rows[0].storedLongitude=cell('real',original);
    value.report.rows[0].values[6]=cell('real',converted);
    await assert.rejects(validate(value));
  }
});

test('location transport rejects foreign scopes, incomplete cells, inferred coordinates and ambiguous physical provenance',async()=>{
  const mutations=[
    v=>v.contextId='stale',v=>v.projectPath='elsewhere',v=>v.suPath='elsewhere',
    v=>v.report.project='Other',v=>v.report.su='Other',v=>v.report.fields.reverse(),
    v=>v.report.fields[0].source='Admin',v=>v.report.fields[0].label='Changed',v=>v.report.fields[0].heading=true,
    v=>v.report.fields=null,v=>v.report.rows=null,v=>v.report.rows[0].envRowId='+1',
    v=>v.report.rows[0].adminRowId='9223372036854775808',v=>v.report.rows.push(structuredClone(v.report.rows[0])),
    v=>v.report.rows[0].membershipRowIds=[],v=>v.report.rows[0].membershipRowIds=['2','2'],
    v=>v.report.rows[0].membershipRowIds=['01'],v=>v.report.rows[0].values.pop(),
    v=>v.report.rows[0].values[0]=cell('null'),v=>v.report.rows[0].values[1]=cell('text','\ud800'),
    v=>v.report.rows[0].values[5]=cell('null'),v=>v.report.rows[0].values[5]=cell('text','54'),
    v=>v.report.rows[0].values[5]=cell('real',Infinity),v=>v.report.rows[0].storedLongitude=cell('text','123.25'),
    v=>v.report.rows[0].values[6]=cell('real',123.25),
    v=>{v.report.rows[0].storedLongitude=cell('integer','-9223372036854775808');v.report.rows[0].values[6]=cell('integer','9223372036854775807');},
    v=>{const next=structuredClone(v.report.rows[0]);next.envRowId='4';next.adminRowId='5';v.report.rows.push(next);}
  ];
  for(const mutate of mutations) {const value=document();mutate(value);
    await assert.rejects(locations.validatePlotLocationReview(value,'owner','Sample','C:\\fixture\\Sample.db','Unit','C:\\fixture\\Other.db'));}
  const none=document('None');none.report.rows[0].membershipRowIds=['1'];await assert.rejects(validate(none));
  await assert.rejects(validate(null));
});

test('location validation detaches before yielding large snapshots to keep cancellation responsive',async()=>{
  const value=document('None'), first=structuredClone(value.report.rows[0]);
  value.report.rows=Array.from({length:501},(_,i)=>({...structuredClone(first),envRowId:String(i),adminRowId:String(i)}));
  const expected=structuredClone(value);let yields=0;
  const result=await validate(value,async()=>{
    yields++;value.contextId='caller changed';value.report.fields[0].key='changed';
    value.report.rows[500].values[0].text='changed';
  });
  assert.equal(yields,1);assert.equal(JSON.stringify(result),JSON.stringify(expected));
});

test('location UI remains independently gated, cancellable and uses shared draft/context/native-close barriers', async () => {
  const { renderShellDeferredViews, componentFunctions } = require('./svelteTestHelpers.cjs');
  const component=readFileSync(srcPath('PlotLocationReview.svelte'),'utf8');
  const navigation=readFileSync(srcPath('Navigation.svelte'),'utf8');
  assert.equal(compile(component,{filename:'PlotLocationReview.svelte',generate:'client'}).warnings.length,0);
  assert.match(navigation,/name: 'Plot Locations', icon: FileText, view: 'plot-locations'/);
  assert.equal(renderShellDeferredViews('plot-locations', null), '');
  assert.match(renderShellDeferredViews('plot-locations', { contextId: 'c1', activeProject: 'Sample' }), /Loading Plot Location Review/);
  const appCtx = componentFunctions('App.svelte', ['navigate', 'requestTransition'], { editorBusy: true });
  await appCtx.actions.navigate('plot-locations');
  assert.match(appCtx.error, /Wait for the current operation/);
  assert.match(component,/reads\.track\(\s*SpatialService\.GetPlotLocationReview\(contextId\)\s*\)/);
  assert.match(component,/const validated = await validatePlotLocationReview[\s\S]*?if \(request !== generation\) return;[\s\S]*?review = validated/);
  assert.match(component,/onDestroy\(cancel\)/);assert.match(component,/reads\.cancelAll\(\)/);
  assert.match(component,/scope="col"/);assert.match(component,/aria-label=.*Env row/);
  assert.match(component,/slice\(offset, offset \+ pageSize\)/);
  assert.match(component,/western-hemisphere sign convention/);
  assert.doesNotMatch(component,/\{#if error\}<p class="error"/);
  assert.doesNotMatch(component,/Reading and checking the owned location snapshot/);
  assert.match(component,/data-plot-location-cancel/);
  assert.match(component,/data-plot-location-summary/);
  assert.doesNotMatch(component,/download=|SaveProject|CreateBlank|BuildFile/);
});

test('PlotLocationReview routes load summaries and operational errors to reports notifications', async () => {
  const { createNotificationController } = loadTypeScript('shell/notificationService.svelte.ts', {
    'svelte/store': require('svelte/store'),
  });
  const notifications = createNotificationController({ schedule: () => 0, cancelSchedule: () => {} });
  const host = componentFunctions('PlotLocationReview.svelte', ['cancel', 'show'], {
    contextId: 'owner',
    project: 'Sample',
    projectPath: 'C:\\fixture\\Sample.db',
    su: 'Unit',
    suPath: 'C:\\fixture\\Other.db',
    review: null,
    busy: false,
    error: '',
    offset: 0,
    generation: 0,
    reads: { track: v => v, cancelAll() {} },
    validatePlotLocationReview: locations.validatePlotLocationReview,
    onBusyChange() {},
    notifications,
    SpatialService: {
      GetPlotLocationReview: async () => document(),
    },
  });

  await host.actions.show();
  host.busy = true;
  await host.actions.show();
  assert.match(host.error, /Wait for or cancel/);
  host.busy = false;
  host.SpatialService.GetPlotLocationReview = async () => { throw new Error('location query failed'); };
  await host.actions.show();

  const entries = notifications.getSnapshot().entries;
  assert.equal(entries.length, 3);
  assert.equal(entries[0].severity, 'error');
  assert.match(entries[0].message, /location query failed/);
  assert.equal(entries[1].severity, 'error');
  assert.match(entries[1].message, /Wait for or cancel/);
  assert.equal(entries[2].severity, 'info');
  assert.match(entries[2].message, /Loaded 1 plot location/);
  assert.ok(entries.every(item => item.category === 'reports' && item.source === 'Plot Locations' && item.contextTag === 'Sample'));
});
