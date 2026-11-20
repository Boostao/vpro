const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync } = require('node:fs');
const { compile } = require('svelte/compiler');
const ts = require('typescript');
const { render } = require('svelte/server');
const { componentFunctions, loadTypeScript, serverComponent, srcPath } = require('./svelteTestHelpers.cjs');

test('UX-ADMIN-004: FS882Form passes loaded original baseline to UpdatePlot, strips RuntimeError on conflict, and offers Reload / Review actions', async () => {
  const { readFS882Composite } = require('./svelteTestHelpers.cjs');
  const rawFs882 = readFileSync(srcPath('FS882Form.svelte'), 'utf8');
  const fs882Src = readFS882Composite();
  assert.equal(compile(rawFs882, { filename: 'FS882Form.svelte', generate: 'client' }).warnings.length, 0);
  assert.match(fs882Src, /data-fs882-conflict-reload/);
  assert.match(fs882Src, /data-fs882-conflict-review/);
  assert.match(fs882Src, /Reload Latest Plot/);
  assert.match(fs882Src, /Keep Draft to Review/);
  assert.match(fs882Src, /aria-label="Clean project copy name"[\s\S]*?data-fs882-clean-project-input/);

  const updateCalls = [];
  const errorToasts = [];
  let failConflict = true;
  const baseline = { plotNumber: '00337', soilNotes: 'Initial note', locked: false };
  const ctx = componentFunctions('FS882Form.svelte', ['save'], {
    $state: { snapshot: v => structuredClone(v) },
    siviSourceAuthorityUnknown: false,
    busy: false,
    headerWorkflowBusy: false,
    siviDeletionPending: false,
    siviRestorationPending: false,
    siviCreationUndoPending: false,
    codeCheckOpen: false,
    metadataOpen: false,
    profileReviewBlocked: false,
    personalDraft: null,
    deletionReview: null,
    creationDraft: null,
    siviParentActionUnsaved: false,
    siviProjectAssignmentUnsaved: false,
    siviParentWriteUnsaved: false,
    siviParentSharedUnsaved: false,
    siviUnsaved: false,
    siviCoverUnsaved: false,
    siviCombinedUnsaved: false,
    siviCollectedUnsaved: false,
    siviSpeciesUnsaved: false,
    siviIdentityUnsaved: false,
    siviCreationPending: false,
    heightUnsaved: false,
    otherUnsaved: false,
    soilUnsaved: false,
    attributeUnsaved: false,
    collectedUnsaved: false,
    speciesUnsaved: false,
    capabilitiesReady: true,
    capabilities: { locked: true, soilNotes: true },
    headerValidation: {},
    dirty: true,
    draft: { plotNumber: '00337', soilNotes: 'Instance B stale overwrite', locked: false },
    original: structuredClone(baseline),
    activeLayerDepthRaw: null,
    workingUnitSession: { plot: '00337' },
    error: null,
    successMsg: null,
    container: { querySelector: () => null },
    PlotService: {
      UpdatePlot: async (payload) => {
        updateCalls.push(structuredClone(payload));
        if (failConflict) {
          throw new Error('RuntimeError: plot "00337" (SoilNotes): plot changed since it was loaded; reload before saving');
        }
      },
      CreatePlot: async () => {
        assert.fail('CreatePlot must not be called when original exists');
      },
    },
    loadChildData: async () => {},
    siviParentSession: null,
    onSaved: async () => {},
    notifications: {
      success: () => {},
      error: (title, msg, opts) => errorToasts.push({ title, msg, opts }),
    },
  });

  await ctx.actions.save();
  assert.equal(updateCalls.length, 1);
  assert.deepEqual(updateCalls[0].original, baseline);
  assert.equal(updateCalls[0].soilNotes, 'Instance B stale overwrite');
  assert.equal(ctx.dirty, true, 'draft must remain dirty for user review on conflict');
  assert.equal(
    ctx.error,
    'plot "00337" (SoilNotes): plot changed since it was loaded; reload before saving',
  );
  assert.equal(errorToasts.length, 1);
  assert.match(errorToasts[0].title, /00337 save conflict/);

  // Simulate reload updating original + draft, then saving cleanly
  failConflict = false;
  ctx.original = { plotNumber: '00337', soilNotes: 'Instance A committed value', locked: false };
  ctx.draft = { plotNumber: '00337', soilNotes: 'Instance B merged value', locked: false };
  await ctx.actions.save();
  assert.equal(updateCalls.length, 2);
  assert.equal(updateCalls[1].original.soilNotes, 'Instance A committed value');
  assert.equal(ctx.error, null);
  assert.equal(ctx.dirty, false);
  assert.equal(ctx.original.soilNotes, 'Instance B merged value');
});

test('UX-ADMIN-006: ProjectAdminWorkbench refreshes project list when creating, copying, or splintering without activating', async () => {
  const { readShellComposite, serverReads, noopNotificationsStub } = require('./svelteTestHelpers.cjs');
  const appSrc = readShellComposite();
  assert.match(appSrc, /<ProjectAdminWorkbench[\s\S]*?onprojectlistchanged=\{async \(\) => \{[\s\S]*?ContextService\.GetState\(\)[\s\S]*?projectState\.set\(nextState\)/);

  const client = await import('svelte/internal/client');
  const workbench = loadTypeScript('projectAdminWorkbench.ts');
  let script = readFileSync(srcPath('ProjectAdminWorkbench.svelte'), 'utf8').match(/<script lang="ts">([\s\S]*?)<\/script>/)[1];
  script = script.replace('oncontextswitched,', 'oncontextswitched, inspect,');
  script += `\n$effect(() => inspect({
    setNewProj(name, activate) { newProjName = name; newProjActivate = activate; },
    submitCreateNewProject,
    setSaveAs(name, activate) { saveAsName = name; saveAsActivate = activate; },
    submitSaveProjectAs,
    setSplinter(name, plotsRaw, activate) { splinterName = name; splinterPlotsRaw = plotsRaw; splinterUseSu = false; splinterActivate = activate; },
    submitExportSplinter,
  }));`;

  const compiled = compile(`<script lang="ts">${script}</script>`, { generate: 'client' });
  assert.equal(compiled.warnings.length, 0);
  const ast = ts.createSourceFile('workbench-ux006.js', compiled.js.code, ts.ScriptTarget.Latest, true);
  const code = ast.statements
    .filter(n => !ts.isImportDeclaration(n))
    .map(n => n.getText(ast))
    .join('\n')
    .replace('export default function', 'function');

  const mountFn = new Function(
    '$',
    'onDestroy',
    'adminLib',
    code + '\nreturn _unknown_;',
  );

  const listRefreshes = [];
  const contextSwitches = [];
  const mockPort = {
    listProjectMetadataPresets: async () => [],
    createNewProject: async (_cid, req) => ({
      projectName: req.projectName,
      projectId: req.projectName,
      destinationPath: `/data/projects/${req.projectName}.db`,
      destinationSha256: 'abc',
      activated: Boolean(req.activateOnSuccess),
      state: req.activateOnSuccess ? { activeProject: req.projectName } : null,
    }),
    saveProjectAs: async (_cid, req) => ({
      sourceProject: 'Sample',
      newProjectName: req.newProjectName,
      destinationPath: `/data/projects/${req.newProjectName}.db`,
      destinationSha256: 'def',
      copiedTables: ['_Env', '_Admin'],
      companionTables: [],
      activated: Boolean(req.activateOnSuccess),
      state: req.activateOnSuccess ? { activeProject: req.newProjectName } : null,
    }),
    exportSplinterProject: async (_cid, req) => ({
      sourceProject: 'Sample',
      splinterProject: req.splinterProject,
      destinationPath: `/data/projects/${req.splinterProject}.db`,
      destinationSha256: 'ghi',
      sourcePlotCount: 51,
      exportedPlotCount: 1,
      createdSuTable: true,
      activated: Boolean(req.activateOnSuccess),
      state: req.activateOnSuccess ? { activeProject: req.splinterProject } : null,
    }),
  };

  let api;
  const dispose = client.effect_root(() =>
    mountFn(
      client,
      () => {},
      { ...workbench, formatError: serverReads.formatError, notifications: noopNotificationsStub.notifications },
    )(null, {
      contextId: 'ctx-1',
      activeProject: 'Sample',
      activeSu: 'Sample',
      port: mockPort,
      onprojectlistchanged: async () => { listRefreshes.push('refreshed'); },
      oncontextswitched: (st) => { contextSwitches.push(st); },
      inspect: v => { api = v; },
    }),
  );
  client.flush();

  try {
    api.setNewProj('QA_NoActivate_Repro', false);
    client.flush();
    await api.submitCreateNewProject();
    assert.equal(listRefreshes.length, 1);
    assert.equal(contextSwitches.length, 0);

    api.setSaveAs('QA_Copy_NoActivate', false);
    client.flush();
    await api.submitSaveProjectAs();
    assert.equal(listRefreshes.length, 2);
    assert.equal(contextSwitches.length, 0);

    api.setSplinter('QA_Splinter_NoActivate', '00337', false);
    client.flush();
    await api.submitExportSplinter();
    assert.equal(listRefreshes.length, 3);
    assert.equal(contextSwitches.length, 0);
  } finally {
    dispose();
  }
});

test('UX-ADMIN-007: Forms -> Metadata is enabled outside FS882 for active projects and ProjectMetadataEditor fixes All 73 / Review 32 spacing', async () => {
  const metaSrc = readFileSync(srcPath('ProjectMetadataEditor.svelte'), 'utf8');
  assert.doesNotMatch(metaSrc, /All73|Review32/);
  assert.match(metaSrc, /All 73 ordinary\/stamp fields/);
  assert.match(metaSrc, /All 73 other source fields/);
  assert.match(metaSrc, /Review 32 assignments/);

  for (const route of ['home', 'plots', 'project-admin', 'user-log']) {
    const host = componentFunctions('App.svelte', ['openProjectMetadata'], {
      view: route,
      editor: undefined,
      selected: null,
      allAvailablePlots: [{ plotNumber: '00337' }],
      standaloneMetadataPlot: '',
      $projectState: { contextId: 'ctx-active', activeProject: 'Sample' },
      error: '',
      requestTransition: async run => { await run('ctx-active'); },
    });
    await host.actions.openProjectMetadata();
    assert.equal(host.standaloneMetadataPlot, '00337', `Metadata should open standalone from ${route}`);
    assert.equal(host.error, '');
  }

  // Two-Page Entry plot picker (view === 'fs882', editorEntryForm === 'fs882-twopage', no plot open yet)
  const pickerHost = componentFunctions('App.svelte', ['openProjectMetadata'], {
    view: 'fs882',
    editorEntryForm: 'fs882-twopage',
    editorPlotNumber: undefined,
    editor: { canOpenProjectMetadata: () => false },
    selected: null,
    allAvailablePlots: [{ plotNumber: '00337' }],
    standaloneMetadataPlot: '',
    $projectState: { contextId: 'ctx-active', activeProject: 'Sample' },
    error: '',
    requestTransition: async run => { await run('ctx-active'); },
  });
  await pickerHost.actions.openProjectMetadata();
  assert.equal(pickerHost.standaloneMetadataPlot, '00337');
});

test('UX-VEG-006: Two-Page Vegetation validation and table messages include proper word/number spacing', () => {
  const { editor: vegEditor, original: buildOriginal } = require('./twoPageVegetationTestHelpers.cjs');
  const source = buildOriginal();
  const collectedDraft = vegEditor.stageTwoPageVegetation(source, '-7', 'Collected', 'XY', false);
  assert.equal(collectedDraft.error, 'Collected exceeds 1 UTF-16 unit.');

  const coverDraft = vegEditor.stageTwoPageVegetation(source, '-7', 'Cover1', '100', false);
  assert.equal(coverDraft.error, 'Cover1 requires a value >= 0 and below 100 or NULL (<100 Or Is Null).');

  const panelSrc = readFileSync(srcPath('TwoPageVegetationTablePanel.svelte'), 'utf8');
  assert.doesNotMatch(panelSrc, /to100000|to50/);
  const panelComp = serverComponent(panelSrc, 'TwoPageVegetationTablePanel.svelte', {
    '../../bindings/github.com/boostao/vpro/app': { DatasheetService: {} },
    './twoPageVegetationTable': {
      twoPageVegetationTableFromWire: () => null,
      twoPageVegetationTableCellLabel: () => '',
    },
  });
  const html = render(panelComp, {
    props: {
      contextId: 'ctx',
      project: 'Sample',
      projectPath: '/data/projects/Sample.db',
      su: 'None',
      suPath: '',
      plot: '00337',
      form: 'SubVegAXL_BC',
      onBusyChange() {},
    },
  }).body;
  assert.match(html, /limited to 100000 rows;\s+pages\s+contain up to 50 joined rows/);
});
