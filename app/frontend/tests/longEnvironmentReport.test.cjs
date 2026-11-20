const assert = require('node:assert/strict');
const {test} = require('node:test');
const {readFileSync} = require('node:fs');
const path = require('node:path');
const {compile} = require('svelte/compiler');
const { loadTypeScript, srcPath } = require('./svelteTestHelpers.cjs');
const quality = loadTypeScript('qualityEditor.ts', {'./becEditor':loadTypeScript('becEditor.ts')});
const editor = loadTypeScript('projectMetadataEditor.ts', {
  './qualityEditor':quality,
  '../../resources/project-metadata-standard.json':JSON.parse(readFileSync(path.join(__dirname,'..','..','resources','project-metadata-standard.json'))),
  '../../resources/project-metadata-template.json':JSON.parse(readFileSync(path.join(__dirname,'..','..','resources','project-metadata-template.json')))
});
const restoration = loadTypeScript('projectMetadataRestore.ts', {'./qualityEditor':quality,'./projectMetadataEditor':editor});
const names = loadTypeScript('reportUnitNames.ts', {'./projectMetadataRestore':restoration});
const report = loadTypeScript('longEnvironmentReport.ts', {'./projectMetadataRestore':restoration,'./reportUnitNames':names});
const cell = text => ({storage:text===null?'null':'text',text,integer:null,real:null,blobHex:null});
function fixture() {
  const fields = readFileSync(path.join(__dirname,'..','..','testdata','long-environment-fields.txt'),'utf8').trimEnd().split(/\r?\n/).map(line=>{
    if(line.startsWith('# ')) return {source:'',key:'',label:line.slice(2),heading:true};
    const [identity,label]=line.split('='), [source,key]=identity.split('.');
    return {source,key,label,heading:false};
  });
  const values=fields.map(()=>cell(null)); values[0]=cell('P1');
  return {contextId:'owned',projectPath:'C:\\project.db',suPath:'C:\\external.db',report:{
    project:'Sample',su:'Selected',title:'  Title  ',fields,diagnostics:[],units:[
      {code:"  U 'quoted'  ",longName:null,nameStatus:'missing',nameCandidates:[],plots:[{plotNumber:'P1',status:'complete',values}]}
    ]}};
}
const validate=value=>report.validateLongEnvironmentPreview(value,'owned','Sample','C:\\project.db','Selected','C:\\external.db','  Title  ');
test('report preserves exact typed zero, NULL, empty text, blobs and signed64 rendering',()=>{
  assert.equal(report.reportCellText(cell(null)),'NULL');
  assert.equal(report.reportCellText(cell('')),'"" (empty text)');
  assert.equal(report.reportCellText({...cell(null),storage:'integer',integer:'-9223372036854775808'}),'-9223372036854775808');
  assert.equal(report.reportCellText({...cell(null),storage:'real',real:0}),'0');
  assert.equal(report.reportCellText({...cell(null),storage:'blob',blobHex:'00ff'}),'BLOB 00ff');
  assert.equal(report.reportTitleError('  Title  '),null);
  assert.equal(report.reportTitleError(''),null);
  assert.ok(report.reportTitleError('\ud800'));
  assert.ok(report.reportTitleError('a\0b'));
  assert.doesNotThrow(()=>validate(fixture()));
});
test('report rejects stale contexts, incomplete scopes and invented observations',()=>{
  for(const mutate of [
    x=>x.contextId='stale',x=>x.suPath='C:\\other.db',x=>x.report.title='Title',
    x=>x.report.fields.pop(),x=>x.report.fields[4].source='Env',
    x=>x.report.units.push(x.report.units[0]),x=>x.report.units[0].plots.push(x.report.units[0].plots[0]),
    x=>x.report.units[0].plots[0].values[0]=cell('Other'),
    x=>x.report.units[0].plots[0].values[4]=cell('Heading data'),
    x=>x.report.units[0].plots[0].values[1]=cell('\ud800'),
    x=>x.report.units[0].plots[0].status='missing_admin',
    x=>x.report.units[0].longName='Invented',
    x=>x.report.units[0].nameCandidates=[{rowId:'01',value:cell(null)}],
    x=>x.report.diagnostics=[{code:'missing_env',unit:'Other',plotNumber:'P1',count:1}],
    x=>x.report.diagnostics=[{code:'missing_env',unit:null,plotNumber:null,count:-1}]
  ]) { const value=fixture(); mutate(value); assert.throws(()=>validate(value)); }
});
test('report view is independently gated, scoped, cancellable and participates in draft-safe navigation',async ()=>{
  const { readReportComposite, renderShellDeferredViews, componentFunctions } = require('./svelteTestHelpers.cjs');
  const read=file=>readFileSync(srcPath(file),'utf8');
  for(const file of ['LongEnvironmentReport.svelte','Navigation.svelte','App.svelte']) {
    assert.equal(compile(read(file),{filename:file,generate:'client'}).warnings.length,0);
  }
  const panel=readReportComposite('long-environment');
  assert.match(read('Navigation.svelte'),/view: 'long-environment'/);
  assert.match(panel,/onDestroy\(\(\) => \{\s*unsubscribe\?\.\(\);\s*unsubscribeWorkbook\(\);\s*cancel\(\);\s*\}\)/);
  assert.match(panel,/request !== generation/);
  assert.match(panel,/EnvironmentReportService\.PreviewLongEnvironment\(\s*contextId/);
  assert.match(panel,/data-source-control="rptSvTitle"/);
  assert.match(panel,/data-source-control="btnViewReport"/);
  assert.match(panel,/Input and report preparation never save preferences/);
  assert.equal(renderShellDeferredViews('long-environment', null), '');
  assert.match(renderShellDeferredViews('long-environment', { contextId: 'c1', activeProject: 'Sample', activeSU: 'S1' }), /Loading Long Environment Report/);
  const appCtx = componentFunctions('App.svelte', ['requestTransition'], { editorBusy: true, error: '' });
  await appCtx.actions.requestTransition(async () => assert.fail('must block while editorBusy'));
  assert.match(appCtx.error, /Wait for the current operation/);
});
