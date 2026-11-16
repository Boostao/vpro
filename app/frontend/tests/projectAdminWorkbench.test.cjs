const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const ts = require('typescript');
const { compile } = require('svelte/compiler');
const { render } = require('svelte/server');
const { loadTypeScript, serverComponent, srcPath } = require('./svelteTestHelpers.cjs');

const quality = loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });
const presetsStub = loadTypeScript('projectMetadataPresets.ts', {
  '../../bindings/github.com/boostao/vpro/app': { ContextService: {} },
  './qualityEditor': quality,
});

const wailsCalls = [];
const makeMockService = (svc) => new Proxy({}, {
  get: (_, method) => (...args) => {
    wailsCalls.push({ methodName: `main.${svc}.${String(method)}`, args });
    return Promise.resolve({ ok: true });
  },
});
const mockBindings = {
  ContextService: makeMockService('ContextService'),
  ValidationService: makeMockService('ValidationService'),
};

const workbench = loadTypeScript('projectAdminWorkbench.ts', {
  '../../bindings/github.com/boostao/vpro/app': mockBindings,
  './projectMetadataPresets': presetsStub,
  './qualityEditor': quality,
});

const read = name => readFileSync(srcPath(name), 'utf8');

test('project naming and splinter draft validators enforce VP08 rules, reserved names, and literal leading-zero plots', () => {
  assert.equal(workbench.validateProjectNameInput('Kootenay_2026'), null);
  assert.match(workbench.validateProjectNameInput(''), /required/);
  assert.match(workbench.validateProjectNameInput(' LeadSpace'), /spaces/);
  assert.match(workbench.validateProjectNameInput('9StartsWithDigit'), /start with a letter/);
  assert.match(workbench.validateProjectNameInput('Sample'), /reserved/);
  assert.match(workbench.validateProjectNameInput('sample'), /reserved/);
  assert.match(workbench.validateProjectNameInput('None'), /reserved/);
  assert.match(workbench.validateProjectNameInput('BECMaster_2026'), /reserved/);
  assert.match(workbench.validateProjectNameInput('A'.repeat(32)), /max 31/);

  assert.match(
    workbench.validateNewProjectDraft({
      projectName: 'ValidProj',
      projectId: 'X'.repeat(21),
      activateOnSuccess: false,
    }),
    /20 UTF-16/
  );

  const tokens = workbench.parseLiteralTokenList(' 00337, 108050 \n 00337 , P001 ');
  assert.deepEqual(structuredClone(tokens), ['00337', '108050', 'P001']);

  assert.match(
    workbench.validateSplinterDraft(
      { splinterProject: 'SubProj', useActiveSu: true, activateOnSuccess: false },
      'None'
    ),
    /Select an active Site Unit/
  );
  assert.equal(
    workbench.validateSplinterDraft(
      { splinterProject: 'SubProj', useActiveSu: false, plotNumbers: ['00337'], activateOnSuccess: false },
      'None'
    ),
    null
  );
  assert.match(
    workbench.validateSplinterDraft(
      { splinterProject: 'SubProj', useActiveSu: false, plotNumbers: ['12345678'], activateOnSuccess: false },
      'None'
    ),
    /7 UTF-16/
  );
});

test('defaultProjectAdminPort dispatches exact Wails Call.ByName endpoints on ContextService and ValidationService', async () => {
  wailsCalls.length = 0;
  await workbench.defaultProjectAdminPort.listProjectMetadataPresets();
  await workbench.defaultProjectAdminPort.createNewProject('ctx-1', { projectName: 'P1', activateOnSuccess: false });
  await workbench.defaultProjectAdminPort.saveProjectAs('ctx-1', { newProjectName: 'P2', activateOnSuccess: false });
  await workbench.defaultProjectAdminPort.exportSplinterProject('ctx-1', { splinterProject: 'P3', useActiveSu: true, activateOnSuccess: false });
  await workbench.defaultProjectAdminPort.compareProjects('ctx-1', { targetPath: '/db/Target.db', caseInsensitiveText: true });
  await workbench.defaultProjectAdminPort.runComplianceValidation('ctx-1', { useActiveSu: false });
  await workbench.defaultProjectAdminPort.quarantineOrphanRecords('ctx-1', {});
  await workbench.defaultProjectAdminPort.previewOptimizeVeg('ctx-1', {});
  await workbench.defaultProjectAdminPort.applyOptimizeVeg('ctx-1', { expectedDigest: 'abc' });
  await workbench.defaultProjectAdminPort.previewThreeWayMerge('ctx-1', { sourcePath: '/db/Stage.db' });
  await workbench.defaultProjectAdminPort.executeThreeWayMerge('ctx-1', { sourcePath: '/db/Stage.db' });

  assert.deepEqual(
    wailsCalls.map(c => c.methodName),
    [
      'main.ContextService.ListProjectMetadataPresets',
      'main.ContextService.CreateNewProject',
      'main.ContextService.SaveProjectAs',
      'main.ContextService.ExportSplinterProject',
      'main.ContextService.CompareProjects',
      'main.ValidationService.RunComplianceValidation',
      'main.ValidationService.QuarantineOrphanRecords',
      'main.ValidationService.PreviewOptimizeVeg',
      'main.ValidationService.ApplyOptimizeVeg',
      'main.ValidationService.PreviewThreeWayMerge',
      'main.ValidationService.ExecuteThreeWayMerge',
    ]
  );
});

test('ProjectAdminWorkbench SSR renders BC Gov header, data-tour root, active context, and Wave 3 admin controls cleanly', () => {
  const Component = serverComponent(read('ProjectAdminWorkbench.svelte'), 'ProjectAdminWorkbench.svelte', {
    './projectAdminWorkbench': workbench,
  });
  const html = render(Component, {
    props: { contextId: 'ctx-ssr', activeProject: 'Sample', activeSu: 'Sample' },
  }).body;
  assert.match(html, /data-tour="project-admin-root"/);
  assert.match(html, /#003366/);
  assert.match(html, /#FCBA19/);
  assert.match(html, /Datum:.*NAD83/);
  assert.match(html, /Create New VPro Project/);
  assert.match(html, /Save Active Project As/);
  assert.match(html, /Export Splinter Project/);
});

test('ProjectAdminWorkbench client actions detach Svelte 5 proxies and cover lifecycle, Save As, Splinter, Compare, Quarantine, OptimizeVeg gate, and 3-way merge resolutions', async () => {
  const client = await import('svelte/internal/client');
  let script = read('ProjectAdminWorkbench.svelte').match(/<script lang="ts">([\s\S]*?)<\/script>/)[1];
  script = script.replace('oncontextswitched,', 'oncontextswitched, inspect,');
  script += `\n$effect(() => inspect({
    setNewProj(name, preset, activate) { newProjName = name; newProjPreset = preset; newProjActivate = activate; },
    setSaveAs(name, dest, activate) { saveAsName = name; saveAsDest = dest; saveAsActivate = activate; },
    submitSaveProjectAs,
    setSplinter(name, unitsRaw, plotsRaw, useSu, activate) { splinterName = name; splinterUnitsRaw = unitsRaw; splinterPlotsRaw = plotsRaw; splinterUseSu = useSu; splinterActivate = activate; },
    submitExportSplinter,
    setCompare(sourceProj, targetPath, targetProj, caseInsensitive) { cmpSourceProject = sourceProj; cmpTargetPath = targetPath; cmpTargetProject = targetProj; cmpCaseInsensitive = caseInsensitive; },
    runCompareProjects,
    exportCompareDiffs,
    submitCreateNewProject,
    runCompliance,
    setConfirmQuarantine(v) { confirmQuarantine = v; },
    runQuarantine,
    setOptimizeVegOverride(v) { optCustodianAuditOverride = v; },
    setConfirmOptimizeVeg(v) { optConfirmReviewed = v; },
    runPreviewOptimizeVeg,
    runApplyOptimizeVeg,
    setMergeConfig(srcPath, srcProj, basePath, baseProj, tgtPath, tgtProj, caseInsensitive) {
      mergeSourcePath = srcPath; mergeSourceProject = srcProj; mergeBasePath = basePath; mergeBaseProject = baseProj;
      mergeTargetPath = tgtPath; mergeTargetProject = tgtProj; mergeCaseInsensitive = caseInsensitive;
    },
    setMergeSource(p) { mergeSourcePath = p; },
    runPreviewMerge,
    setPlotResolution,
    setFieldResolution,
    runExecuteMerge,
    getState: () => ({
      error, statusMessage, availablePresets, newProjIdTruncationWarning,
      saveAsResult, splinterResult, cmpResult, cmpExportPreview,
      complianceReport, optPreview, optResult, optUnresolvedConflictCount,
      mergePreview, mergePlotResolutions, mergeFieldResolutions, mergeResult,
    }),
  }));`;

  const compiled = compile(`<script lang="ts">${script}</script>`, { generate: 'client' });
  assert.equal(compiled.warnings.length, 0);
  const ast = ts.createSourceFile('workbench.js', compiled.js.code, ts.ScriptTarget.Latest, true);
  const code = ast.statements
    .filter(n => !ts.isImportDeclaration(n))
    .map(n => n.getText(ast))
    .join('\n')
    .replace('export default function', 'function');

  const mountFn = new Function(
    '$',
    'onDestroy',
    'defaultProjectAdminPort',
    'validateNewProjectDraft',
    'validateProjectNameInput',
    'validateSplinterDraft',
    'parseLiteralTokenList',
    'buildInitialMergeFieldResolutions',
    'buildInitialMergePlotResolutions',
    'formatCompareDiffsDelimited',
    code + '\nreturn _unknown_;'
  );

  const dispatches = [];
  let switchedState = null;
  let optPreviewBlocked = true;
  const mockPort = {
    async listProjectMetadataPresets() {
      return [
        {
          id: 'LMH25_2023_FS882',
          label: 'LMH25 (2023) Standard FS882 (Live)',
          description: 'Live backend preset.',
          ecosysCollectionStandard: 'LMH25',
          vegCoverMethod: 'Percent',
          plotMethod: '20x20',
          datum: 'NAD83',
          coverDescriptions: {},
        },
      ];
    },
    async createNewProject(cid, req) {
      assert.doesNotThrow(() => structuredClone(req));
      dispatches.push(['createNewProject', cid, req]);
      return {
        projectName: req.projectName,
        projectId: req.projectId ?? req.projectName.slice(0, 20),
        destinationPath: `/projects/${req.projectName}.db`,
        destinationSha256: 'deadbeef12345678',
        activated: req.activateOnSuccess,
        state: { activeProject: req.projectName, contextId: 'ctx-next' },
      };
    },
    async saveProjectAs(cid, req) {
      assert.doesNotThrow(() => structuredClone(req));
      dispatches.push(['saveProjectAs', cid, req]);
      return {
        sourceProject: 'Bulkley2026',
        newProjectName: req.newProjectName,
        destinationPath: req.destinationPath || `/projects/${req.newProjectName}.db`,
        destinationSha256: 'cafe1234567890',
        copiedTables: ['_Env', '_Veg'],
        companionTables: ['Sample_SU'],
        activated: req.activateOnSuccess,
      };
    },
    async exportSplinterProject(cid, req) {
      assert.doesNotThrow(() => structuredClone(req));
      dispatches.push(['exportSplinterProject', cid, req]);
      return {
        sourceProject: 'Bulkley2026',
        splinterProject: req.splinterProject,
        destinationPath: `/projects/${req.splinterProject}.db`,
        destinationSha256: 'babe1234567890',
        sourcePlotCount: 10,
        exportedPlotCount: 2,
        createdSuTable: true,
        activated: req.activateOnSuccess,
      };
    },
    async compareProjects(cid, req) {
      assert.doesNotThrow(() => structuredClone(req));
      dispatches.push(['compareProjects', cid, req]);
      return {
        sourcePath: '/projects/Sample.db',
        sourceProject: req.sourceProject || 'Sample',
        targetPath: req.targetPath,
        targetProject: req.targetProject || 'TargetProj',
        totalPlots: 2,
        addedCount: 0,
        removedCount: 0,
        identicalCount: 1,
        modifiedCount: 1,
        metadataDiffCount: 1,
        plots: [],
        fieldDiffs: [
          { table: 'Env', plotNumber: '00337', key: 'Zone', field: 'Zone', sourceVal: 'CWH', targetVal: 'ICH' },
        ],
        metadataDiffs: [
          { table: '_Metadata', plotNumber: '', key: 'ProjectID', field: 'Datum', sourceVal: 'NAD83', targetVal: 'NAD27' },
        ],
      };
    },
    async runComplianceValidation(cid, opts) {
      assert.doesNotThrow(() => structuredClone(opts));
      dispatches.push(['runComplianceValidation', cid, opts]);
      return {
        project: 'Sample',
        su: 'None',
        useActiveSu: false,
        passed: false,
        summary: {
          envCodeErrors: 1,
          boundsErrors: 0,
          envAdminMismatches: 1,
          orphanChildRows: 2,
          duplicateSpeciesSplits: 1,
          unlistedSpecies: 0,
          synonymSpecies: 1,
          userSpecies: 0,
          plotsWithoutVeg: 1,
        },
        envCodeFindings: [{ listName: 'MoistureRegime', field: 'MoistureRegime', plotNumber: '001', value: 'ZZ' }],
        skippedDefinitions: [{ listName: 'LegacyX', field: 'MissingCol', reason: 'Field does not exist' }],
        boundsFindings: [],
        envAdminFindings: [{ plotNumber: '002', issue: 'Missing _Admin row' }],
        orphanFindings: [{ table: 'SU', plotNumber: 'ORPH1', rowCount: 2 }],
        plotsWithoutVegetation: ['003'],
        duplicateVegFindings: [{ plotNumber: '001', species: 'PSEUMEN', rowCount: 2, overlappingLayers: ['Cover4'] }],
        taxonomyFindings: [{ rowId: 9, id: 9, plotNumber: '001', species: 'OLDPINE', status: 'synonym', suggestedCode: 'PINUCON' }],
      };
    },
    async quarantineOrphanRecords(cid, req) {
      assert.doesNotThrow(() => structuredClone(req));
      dispatches.push(['quarantineOrphanRecords', cid, req]);
      return {
        project: 'Sample',
        batchId: 'b123',
        totalQuarantined: 2,
        reservedDeletedIds: [77, 78],
        tables: [{ table: 'Veg', quarantineTable: '__VPRO_Quarantine_Veg', movedRows: 2, plotNumbers: ['ORPH1'] }],
      };
    },
    async previewOptimizeVeg(cid, opts) {
      assert.doesNotThrow(() => structuredClone(opts));
      dispatches.push(['previewOptimizeVeg', cid, opts]);
      return {
        project: 'Sample',
        beforeRowCount: 10,
        afterRowCount: 8,
        rowsToConsolidate: 2,
        duplicateSpeciesCount: 1,
        overlappingGroupCount: 1,
        cappedCoverCount: 1,
        blockedGroupCount: optPreviewBlocked ? 1 : 0,
        hasBlockingConflicts: optPreviewBlocked,
        conflicts: optPreviewBlocked
          ? [{ plotNumber: '001', species: 'PSEUMEN', field: '_Audit', reason: 'Retired ID referenced in audit', values: [], sourceIds: [11], overrideable: true }]
          : [],
        auditReferences: optPreviewBlocked
          ? [{ plotNumber: '001', species: 'PSEUMEN', retiredId: 11, table: '_Veg', editField: 'Cover4', editWhen: '2026-01-01' }]
          : [],
        previewDigest: 'digest-opt-1',
        groups: [
          {
            plotNumber: '001',
            species: 'PSEUMEN',
            sourceRowCount: 3,
            survivorId: 10,
            retiredIds: [11, 12],
            hasOverlappingLayerCovers: true,
            cappedCoverColumns: ['Cover4'],
            mergedCovers: { Cover4: 99, Cover6: 20 },
            mergedHeights: { Height6: 0.65 },
            blocked: optPreviewBlocked,
            blockedReasons: optPreviewBlocked ? ['_Audit reference'] : [],
          },
        ],
      };
    },
    async applyOptimizeVeg(cid, req) {
      assert.doesNotThrow(() => structuredClone(req));
      assert.equal(req.expectedDigest, 'digest-opt-1');
      dispatches.push(['applyOptimizeVeg', cid, req]);
      return {
        project: 'Sample',
        beforeRowCount: 10,
        afterRowCount: 8,
        consolidatedGroups: 1,
        deletedRows: 2,
        reservedDeletedIds: [11, 12],
        auditRowsWritten: 5,
        groups: [],
      };
    },
    async previewThreeWayMerge(cid, req) {
      assert.doesNotThrow(() => structuredClone(req));
      dispatches.push(['previewThreeWayMerge', cid, req]);
      return {
        sourcePath: req.sourcePath,
        sourceProject: req.sourceProject || 'Stage',
        targetPath: req.targetPath || '/projects/Sample.db',
        targetProject: req.targetProject || 'Sample',
        basePath: req.basePath,
        baseProject: req.baseProject,
        previewDigest: 'merge-digest-99',
        addedCount: 1,
        identicalCount: 4,
        fastForwardCount: 1,
        conflictCount: 1,
        targetOnlyCount: 0,
        sourceDeleteCount: 1,
        metadataConflictCount: 0,
        plots: [
          { plotNumber: 'DEL1', category: 'SourceDelete', items: [] },
          { plotNumber: '0102', category: 'Conflict', items: [] },
        ],
        conflicts: [
          {
            conflictId: '0102::Env::Zone',
            plotNumber: '0102',
            table: 'Env',
            key: 'Zone',
            field: 'Zone',
            sourceVal: 'ICH',
            targetVal: 'IDF',
            kind: 'Conflict',
            defaultResolution: 'keep_target',
          },
        ],
        metadataItems: [],
      };
    },
    async executeThreeWayMerge(cid, req) {
      assert.doesNotThrow(() => structuredClone(req));
      dispatches.push(['executeThreeWayMerge', cid, req]);
      return {
        sourceProject: req.sourceProject || 'Stage',
        targetProject: req.targetProject || 'Sample',
        targetPath: '/projects/Sample.db',
        addedPlots: 1,
        updatedPlots: 2,
        skippedPlots: 4,
        allocatedChildIds: [101],
        reservedDeletedIds: [],
        auditRowsWritten: 9,
      };
    },
  };

  let api;
  const dispose = client.effect_root(() =>
    mountFn(
      client,
      () => {},
      workbench.defaultProjectAdminPort,
      workbench.validateNewProjectDraft,
      workbench.validateProjectNameInput,
      workbench.validateSplinterDraft,
      workbench.parseLiteralTokenList,
      workbench.buildInitialMergeFieldResolutions,
      workbench.buildInitialMergePlotResolutions,
      workbench.formatCompareDiffsDelimited
    )(null, {
      contextId: 'ctx-live',
      activeProject: 'Sample',
      activeSu: 'Sample',
      port: mockPort,
      oncontextswitched: st => {
        switchedState = st;
      },
      inspect: v => {
        api = v;
      },
    })
  );
  client.flush();
  await Promise.resolve();
  await Promise.resolve();

  try {
    // 0. Dynamic presets & >20-char ProjectID truncation warning (S2.11, S2.17)
    assert.equal(api.getState().availablePresets[0].datum, 'NAD83');
    api.setNewProj('LongBoundarySurvey2026_East', 'LMH25_2023_FS882', false);
    client.flush();
    assert.match(api.getState().newProjIdTruncationWarning, /LongBoundarySurvey20/);

    // 1. Create new project + Save As + Export Splinter (S2.18)
    api.setNewProj('Bulkley2026', 'LMH25_2023_FS882', true);
    client.flush();
    await api.submitCreateNewProject();
    client.flush();
    assert.equal(switchedState.activeProject, 'Bulkley2026');

    api.setSaveAs('Bulkley2026_Copy', '', false);
    client.flush();
    await api.submitSaveProjectAs();
    client.flush();
    assert.equal(api.getState().saveAsResult.newProjectName, 'Bulkley2026_Copy');

    api.setSplinter('Bulkley_Subset', '', '00337', false, false);
    client.flush();
    await api.submitExportSplinter();
    client.flush();
    assert.equal(api.getState().splinterResult.exportedPlotCount, 2);

    // 2. Compare Two Projects + caseInsensitiveText + CSV/TSV export (S2.14)
    api.setCompare('SrcProj', '/projects/Target.db', 'TgtProj', true);
    client.flush();
    await api.runCompareProjects();
    client.flush();
    const cmpCall = dispatches.find(d => d[0] === 'compareProjects');
    assert.equal(cmpCall[2].sourceProject, 'SrcProj');
    assert.equal(cmpCall[2].caseInsensitiveText, true);
    api.exportCompareDiffs('CSV');
    client.flush();
    assert.match(api.getState().cmpExportPreview.text, /PlotNumber,Table,Key,Field,SourceValue,TargetValue/);
    assert.match(api.getState().cmpExportPreview.text, /00337,Env,Zone,Zone,CWH,ICH/);
    assert.match(api.getState().cmpExportPreview.text, /_Metadata,ProjectID,Datum,NAD83,NAD27/);

    // 3. Compliance 8 slices + Quarantine gate (S4.1)
    await api.runCompliance();
    client.flush();
    assert.equal(api.getState().complianceReport.taxonomyFindings[0].suggestedCode, 'PINUCON');
    await api.runQuarantine();
    client.flush();
    assert.match(api.getState().error, /Confirm orphan quarantine/);
    api.setConfirmQuarantine(true);
    client.flush();
    await api.runQuarantine();
    client.flush();
    assert.equal(dispatches.some(d => d[0] === 'quarantineOrphanRecords'), true);

    // 4. OptimizeVeg Dry-Run Gate -> blocking conflicts rejected -> resolve & custodian confirm -> commit (S2.6)
    await api.runPreviewOptimizeVeg();
    client.flush();
    assert.equal(api.getState().optUnresolvedConflictCount, 1);
    await api.runApplyOptimizeVeg();
    client.flush();
    assert.match(api.getState().error, /Resolve 1 OptimizeVeg blocking conflict/);

    optPreviewBlocked = false;
    api.setOptimizeVegOverride(true);
    await api.runPreviewOptimizeVeg();
    client.flush();
    assert.equal(api.getState().optUnresolvedConflictCount, 0);
    await api.runApplyOptimizeVeg();
    client.flush();
    assert.match(api.getState().error, /I have reviewed conflicts and want to commit OptimizeVeg/);

    api.setConfirmOptimizeVeg(true);
    client.flush();
    await api.runApplyOptimizeVeg();
    client.flush();
    assert.equal(api.getState().optResult.deletedRows, 2);

    // 5. 3-Way Merge preview with Source/Base/Target project inputs & per-plot mergePlotResolutions (S2.2)
    api.setMergeConfig('/staging/Stage.db', 'StageProj', '/base/Base.db', 'BaseProj', '/tgt/Target.db', 'TargetProj', true);
    client.flush();
    await api.runPreviewMerge();
    client.flush();
    assert.equal(api.getState().mergePlotResolutions['DEL1'], 'accept_source');
    api.setPlotResolution('DEL1', 'keep_target');
    api.setFieldResolution('0102::Env::Zone', 'accept_source');
    client.flush();
    await api.runExecuteMerge();
    client.flush();
    const execCall = dispatches.find(d => d[0] === 'executeThreeWayMerge');
    assert.ok(execCall);
    assert.equal(execCall[2].sourceProject, 'StageProj');
    assert.equal(execCall[2].baseProject, 'BaseProj');
    assert.equal(execCall[2].targetProject, 'TargetProj');
    assert.equal(execCall[2].caseInsensitiveText, true);
    assert.equal(execCall[2].expectedPreviewDigest, 'merge-digest-99');
    assert.equal(execCall[2].plotResolutions['DEL1'], 'keep_target');
    assert.equal(execCall[2].fieldResolutions['0102::Env::Zone'], 'accept_source');
  } finally {
    dispose();
  }
});

test('App.svelte keeps ProjectAdminWorkbench mounted across context activation so lifecycle receipts remain visible', () => {
  const appSrc = read('App.svelte');
  const sectionStart = appSrc.indexOf("{:else if view === 'project-admin'");
  const sectionEnd = appSrc.indexOf("{:else if view === 'lump-editor'");
  assert.ok(sectionStart > 0 && sectionEnd > sectionStart);
  const block = appSrc.slice(sectionStart, sectionEnd);
  assert.doesNotMatch(block, /\{#key \$projectState\.contextId\}/, 'project-admin must update in place without #key remount');
  assert.match(block, /projectId=""/, 'ProjectMetadataPresets must receive empty projectId to auto-detect existing _Metadata row');
});
