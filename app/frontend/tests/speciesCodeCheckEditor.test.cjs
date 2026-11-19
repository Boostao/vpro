const assert=require('node:assert/strict');
const {test}=require('node:test');
const {readFileSync}=require('node:fs');
const path=require('node:path');
const {render}=require('svelte/server');
const {compile}=require('svelte/compiler');
const { loadTypeScript, serverComponent, componentFunctions, srcPath } = require('./svelteTestHelpers.cjs');
const quality=loadTypeScript('qualityEditor.ts',{'./becEditor':loadTypeScript('becEditor.ts')});
const editor=loadTypeScript('speciesCodeCheckEditor.ts',{'./qualityEditor':quality});
const json=value=>JSON.parse(JSON.stringify(value));
const review={project:'Sample',su:'Scoped unit',rows:[
  {id:0,plotNumber:'P1',code:'OLD',status:'unlisted'},
  {id:-9,plotNumber:'P2',code:'OLD',status:'unlisted'},
  {id:3,plotNumber:'P3',code:null,status:'missing'},
  {id:4,plotNumber:'P4',code:'',status:'unlisted'},
]};
const options=[{code:'NEW',source:'master',scientificName:null,englishName:'',lifeform:null,codeType:null}];
test('Species check names its scope and keeps original NULL/empty/literal identities through remount',()=>{
  let draft=editor.stageCodeCheck(editor.beginCodeCheck(review),0,'NEW');
  assert.throws(()=>editor.codeCheckUpdates(draft),/Review this literal replacement/);
  draft=editor.acceptCodeCheckTarget(json(draft),0,'NEW',options,true);
  assert.deepEqual(json(editor.codeCheckUpdates(json(draft))),[
    {id:0,plotNumber:'P1',expected:'OLD',value:'NEW'},
    {id:-9,plotNumber:'P2',expected:'OLD',value:'NEW'},
  ]);
  assert.equal(draft.review.rows[2].code,null);
  assert.equal(draft.review.rows[3].code,'');
  draft=editor.stageCodeCheck(draft,0,'new');
  assert.throws(()=>editor.acceptCodeCheckTarget(draft,0,'new',options,false),/no longer matches/);
});
test('Ignore and Ignore All are runtime-only and never manufacture user definitions or assignments',()=>{
  let draft=editor.stageCodeCheck(editor.beginCodeCheck(review),3,'bad');
  draft=editor.ignoreCodeCheck(json(draft),3,true);
  assert.deepEqual(json(draft.ignored),[3]);
  assert.deepEqual(json(editor.codeCheckUpdates(draft)),[]);
  draft=editor.ignoreCodeCheck(draft,0,true);
  assert.deepEqual(json(draft.ignored),[3,0,-9]);
  assert.equal(draft.review.rows.length,4);
  draft=editor.stageCodeCheck(draft,0,'NEW');
  assert.equal(draft.ignored.includes(0),false);
  assert.equal(draft.ignored.includes(-9),true);
});
test('Raw errors and stale replacement reviews block transport without trimming, case repair or truncation',()=>{
  let draft=editor.beginCodeCheck(review);
  for(const raw of ['', 'OVERLONG1', '\ud800']){
    draft=editor.stageCodeCheck(draft,0,raw);
    assert.equal(draft.cells['0'].raw,raw);
    assert.throws(()=>editor.codeCheckUpdates(json(draft)));
  }
  draft=editor.stageCodeCheck(draft,0,'NEW');
  assert.throws(()=>editor.acceptCodeCheckTarget(draft,0,'OTHER',options,false));
  draft=editor.acceptCodeCheckTarget(draft,0,'NEW',options,false);
  draft.cells['0'].reviewed='STALE';
  assert.throws(()=>editor.codeCheckUpdates(draft),/original explicit replacement/);
  assert.throws(()=>editor.beginCodeCheck({...review,rows:[review.rows[0],review.rows[0]]}),/ambiguous/);
  assert.throws(()=>editor.beginCodeCheck({...review,su:''}),/explicit.*scope/);
});
test('Code-check personal metadata retains independent physical source and original literal names',()=>{
  const species=loadTypeScript('vegetationSpeciesEditor.ts',{'./qualityEditor':quality});
  const personal=loadTypeScript('personalSpeciesEditor.ts',{'./qualityEditor':quality,'./vegetationSpeciesEditor':species});
  let metadata=personal.beginCodeCheckPersonalSpecies(review.rows[0],{form:'USysCodeCheck',entered:'OLD',aliases:[],users:[]});
  assert.deepEqual(json(metadata.source),{kind:'codecheck',id:0,plotNumber:'P1',expected:'OLD'});
  assert.equal(personal.matchesCodeCheckPersonalSpeciesSource(metadata,review.rows[0]),true);
  assert.equal(personal.matchesCodeCheckPersonalSpeciesSource(metadata,{...review.rows[0],plotNumber:'FOREIGN'}),false);
  assert.equal(personal.matchesCodeCheckPersonalSpeciesSource(metadata,{...review.rows[0],code:'CHANGED'}),false);
  metadata=personal.stagePersonalText(metadata,'scientificName','  Literal é  ',false);
  metadata=personal.stagePersonalText(metadata,'englishName','',false);
  assert.deepEqual(json(personal.personalSpeciesRequest(metadata)),{entered:'OLD',scientificName:'  Literal é  ',englishName:'',lifeform:null});
  assert.throws(()=>personal.beginCodeCheckPersonalSpecies(review.rows[2],{form:'USysCodeCheck',entered:'',aliases:[],users:[]}));
});
test('Shared personal fields keep visible source labels, original IDs and distinct NULL/empty controls',()=>{
  const species=loadTypeScript('vegetationSpeciesEditor.ts',{'./qualityEditor':quality});
  const personal=loadTypeScript('personalSpeciesEditor.ts',{'./qualityEditor':quality,'./vegetationSpeciesEditor':species});
  const fields=serverComponent(readFileSync(srcPath('PersonalSpeciesFields.svelte'),'utf8'),'PersonalSpeciesFields.svelte',{'./personalSpeciesEditor':personal});
  const draft=personal.beginCodeCheckPersonalSpecies(review.rows[0],{form:'USysCodeCheck',entered:'OLD',aliases:[],users:[]});
  const html=render(fields,{props:{draft,disabled:false,onchange(){}}}).body;
  for(const id of ['personal-code','personal-lifeform','personal-scientificName','personal-englishName','personal-null-scientificName','personal-null-englishName']){
    assert.match(html,new RegExp(`for="${id}"`));
    assert.equal((html.match(new RegExp(`id="${id}"`,'g'))||[]).length,1);
  }
  assert.match(html,/store NULL, not an empty string/);
});
test('Code-check scope and raw errors remain outside remounted tabs and explicitly gate Save/Lock/close/Undo',()=>{
  const form=readFileSync(srcPath('FS882Form.svelte'),'utf8');
  const component=readFileSync(srcPath('SpeciesCodeCheck.svelte'),'utf8');
  const page=readFileSync(srcPath('SourcePage.svelte'),'utf8');
  assert.match(form,/siviCreationPeerUnsaved = \$derived\([^;]*codeCheckOpen/);
  assert.match(form,/childParentDisabled = \$derived\([^;]*codeCheckOpen/);
  assert.match(form,/if \(codeCheckOpen\) return codeCheckEditor\?\.getCloseState/);
  assert.match(form,/\[\(\) => codeCheckOpen, \(\) => codeCheckEditor\?\.undo\(\)\]/);
  assert.match(form,/ordinary plot Save never applies them/);
  assert.match(form,/Finish or close species-code review before changing the plot lock/);
  assert.match(page,/btnCheckSppCodes' && onSpeciesCheck/);
  assert.match(component,/await client\.SaveSpeciesCodeCheck\(updates\)/);
  assert.match(component,/await client\.CreatePersonalSpeciesDefinition\(request\)/);
  assert.match(component,/matchesCodeCheckPersonalSpeciesSource\(proposed, rows\[0\]\)/);
  assert.match(component,/matchesCodeCheckPersonalSpeciesSource\(proposed, sources\[0\]\)/);
  assert.match(component,/Ignore never creates or deletes temporary LifeForm999/);
  assert.match(component,/applySuggested/);
  assert.match(component,/row\.suggestedCode/);
  assert.match(component,/capped at 99%/);
  assert.doesNotMatch(component,/(emerald-|#b7cfc0)/i);
  assert.equal(compile(component,{filename:'SpeciesCodeCheck.svelte',generate:'client'}).warnings.length,0);
});
test('Species check supports synonym status, <=8 UTF-16 suggestedCode guards, and scope-wide replacement updates',()=>{
  const sampleSynonymReview={project:'Sample',su:'None',rows:[
    {id:101,plotNumber:'00337',code:'ABIEBALD',status:'master'},
    {id:102,plotNumber:'00337',code:'MYUSER1',status:'user'},
    {id:103,plotNumber:'8529675',code:'AMBLSER1',status:'synonym',suggestedCode:'AMBLSER'},
    {id:104,plotNumber:'8529676',code:'ARTEMIS',status:'synonym',suggestedCode:'ARTEMISI'},
    {id:105,plotNumber:'9003002',code:'ARTEMIS',status:'synonym',suggestedCode:'ARTEMISI'},
    {id:106,plotNumber:'8529670',code:'ASTRAGA',status:'synonym',suggestedCode:'ASTRAGAL'},
    {id:107,plotNumber:'00337',code:'myherb',status:'unlisted'},
    {id:108,plotNumber:'00337',code:null,status:'missing'},
  ]};
  let draft=editor.beginCodeCheck(sampleSynonymReview);
  assert.deepEqual(editor.unresolvedCodeCheckRows(draft).map(r=>r.id),[103,104,105,106,107,108]);
  assert.equal(editor.suggestedCodeForRow(sampleSynonymReview.rows[2]),'AMBLSER');
  assert.equal(editor.suggestedCodeForRow(sampleSynonymReview.rows[3]),'ARTEMISI');
  assert.equal(editor.suggestedCodeForRow(sampleSynonymReview.rows[6]),null);

  draft=editor.stageSuggestedCodeCheck(draft,104);
  assert.equal(draft.cells['104'].raw,'ARTEMISI');
  assert.throws(()=>editor.codeCheckUpdates(draft),/Review this literal replacement/);

  const artemisiOptions=[{code:'ARTEMISI',source:'master',scientificName:'Artemisia spp.',englishName:'sagebrush',lifeform:7,codeType:'U'}];
  draft=editor.acceptCodeCheckTarget(json(draft),104,'ARTEMISI',artemisiOptions,true);
  assert.deepEqual(json(editor.codeCheckUpdates(json(draft))),[
    {id:104,plotNumber:'8529676',expected:'ARTEMIS',value:'ARTEMISI'},
    {id:105,plotNumber:'9003002',expected:'ARTEMIS',value:'ARTEMISI'},
  ]);

  draft=editor.ignoreCodeCheck(draft,106,true);
  assert.deepEqual(editor.unresolvedCodeCheckRows(draft).map(r=>r.id),[103,104,105,107,108]);

  // Malformed lone surrogate in suggestedCode is rejected on load; over-8 UTF-16 suggestion is suppressed without crashing
  assert.throws(()=>editor.beginCodeCheck({project:'Sample',su:'None',rows:[
    {id:201,plotNumber:'P1',code:'ARTEMIS',status:'synonym',suggestedCode:'\ud800'},
  ]}),/malformed/);
  const overlongDraft=editor.beginCodeCheck({project:'Sample',su:'None',rows:[
    {id:202,plotNumber:'P1',code:'AMMOARE1',status:'synonym',suggestedCode:'CALAAREARE1'},
    {id:203,plotNumber:'P1',code:'SYNEMPTY',status:'synonym',suggestedCode:''},
    {id:204,plotNumber:'P1',code:'SAMECODE',status:'synonym',suggestedCode:'SAMECODE'},
  ]});
  assert.equal(editor.suggestedCodeForRow(overlongDraft.review.rows[0]),null);
  assert.equal(editor.suggestedCodeForRow(overlongDraft.review.rows[1]),null);
  assert.equal(editor.suggestedCodeForRow(overlongDraft.review.rows[2]),null);
  assert.throws(()=>editor.stageSuggestedCodeCheck(overlongDraft,202),/<= 8 UTF-16/);
});
test('SpeciesCodeCheck.svelte opens Sample synonym rows, applies suggested code, reviews target, and commits updates',async()=>{
  const species=loadTypeScript('vegetationSpeciesEditor.ts',{'./qualityEditor':quality});
  const personal=loadTypeScript('personalSpeciesEditor.ts',{'./qualityEditor':quality,'./vegetationSpeciesEditor':species});
  let currentRows=[
    {id:1,plotNumber:'00337',code:'ABIEBALD',status:'master'},
    {id:2,plotNumber:'8529676',code:'ARTEMIS',status:'synonym',suggestedCode:'ARTEMISI'},
    {id:3,plotNumber:'9003002',code:'ARTEMIS',status:'synonym',suggestedCode:'ARTEMISI'},
    {id:4,plotNumber:'8529670',code:'ASTRAGA',status:'synonym',suggestedCode:'ASTRAGAL'},
  ];
  const savedPayloads=[];
  let committedCalls=0;
  const client={
    ReviewSpeciesCodes:async()=>({project:'Sample',su:'None',rows:structuredClone(currentRows)}),
    LookupSpeciesCodeCheckTarget:async({code})=>code==='ARTEMISI'
      ?[{code:'ARTEMISI',source:'master',scientificName:'Artemisia spp.',englishName:'sagebrush',lifeform:7,codeType:'U'}]
      :[],
    SaveSpeciesCodeCheck:async(updates)=>{
      savedPayloads.push(structuredClone(updates));
      for(const u of updates){
        currentRows=currentRows.map(r=>r.id===u.id?{id:r.id,plotNumber:r.plotNumber,code:u.value,status:'master'}:r);
      }
    },
  };
  const ctx=componentFunctions('SpeciesCodeCheck.svelte',['reload','stage','reviewTarget','applySuggested','accept','ignore','save'],{
    client,
    reads:{track:p=>p,cancelAll(){}},
    beginCodeCheck:editor.beginCodeCheck,
    unresolvedCodeCheckRows:editor.unresolvedCodeCheckRows,
    suggestedCodeForRow:editor.suggestedCodeForRow,
    stageSuggestedCodeCheck:editor.stageSuggestedCodeCheck,
    stageCodeCheck:editor.stageCodeCheck,
    acceptCodeCheckTarget:editor.acceptCodeCheckTarget,
    ignoreCodeCheck:editor.ignoreCodeCheck,
    codeCheckErrors:editor.codeCheckErrors,
    codeCheckUpdates:editor.codeCheckUpdates,
    personalSpeciesErrors:personal.personalSpeciesErrors,
    session:null,choices:{},metadata:null,reading:false,saving:false,committedFailure:false,
    error:null,success:null,offset:0,generation:0,busy:false,pending:0,
    oncommitted:async()=>{committedCalls++;},onclosed(){},
  });
  await ctx.actions.reload();
  assert.equal(ctx.error,null);
  assert.equal(editor.unresolvedCodeCheckRows(ctx.session).length,3);

  await ctx.actions.applySuggested(ctx.session.review.rows[1]);
  assert.equal(ctx.error,null);
  assert.equal(ctx.session.cells['2'].raw,'ARTEMISI');
  assert.equal(ctx.choices['2'].entered,'ARTEMISI');
  assert.equal(ctx.choices['2'].options[0].code,'ARTEMISI');

  ctx.actions.accept(2,true);
  assert.equal(ctx.error,null);
  assert.equal(ctx.session.cells['2'].reviewed,'ARTEMISI');
  assert.equal(ctx.session.cells['3'].reviewed,'ARTEMISI');

  await ctx.actions.save();
  assert.equal(ctx.error,null);
  assert.equal(committedCalls,1);
  assert.deepEqual(savedPayloads,[[
    {id:2,plotNumber:'8529676',expected:'ARTEMIS',value:'ARTEMISI'},
    {id:3,plotNumber:'9003002',expected:'ARTEMIS',value:'ARTEMISI'},
  ]]);
  assert.deepEqual(editor.unresolvedCodeCheckRows(ctx.session).map(r=>r.code),['ASTRAGA']);
});
