<script module lang="ts">
  import ProjectAdminHeader from './ProjectAdminHeader.svelte';
  import ProjectAdminLazyTabs from './ProjectAdminLazyTabs.svelte';
</script>

<script lang="ts">
  import { onDestroy } from 'svelte';
  import * as adminLib from './projectAdminWorkbench';

  type WorkbenchTab = 'lifecycle' | 'compliance' | 'optimizeveg' | 'merge' | 'cloudsync';
  let {
    contextId,
    activeProject,
    activeSu = 'None',
    initialTab = 'lifecycle',
    initialTabNonce = 0,
    operationHeld = false,
    port = adminLib.defaultProjectAdminPort,
    onBusyChange,
    onprojectlistchanged,
    oncontextswitched,
  }: {
    contextId: string;
    activeProject: string;
    activeSu?: string;
    initialTab?: WorkbenchTab;
    initialTabNonce?: number;
    operationHeld?: boolean;
    port?: adminLib.ProjectAdminPort;
    onBusyChange?: (busy: boolean) => void;
    onprojectlistchanged?: (state?: unknown) => void | Promise<void>;
    oncontextswitched?: (state: unknown) => void;
  } = $props();

  let activeTab = $state<WorkbenchTab>('lifecycle');
  let lastAppliedInitialKey = 'lifecycle::0';
  let busy = $state(false);
  let error = $state<string | null>(null);
  let statusMessage = $state<string | null>(null);
  let generation = 0;

  let availablePresets = $state<adminLib.ProjectMetadataPreset[]>(adminLib.FALLBACK_PROJECT_METADATA_PRESETS);
  let presetsLoadStarted = false;
  let newProjName = $state('');
  let newProjId = $state('');
  let newProjTitle = $state('');
  let newProjPreset = $state('LMH25_2023_FS882');
  let newProjDest = $state('');
  let newProjActivate = $state(false);
  let newProjResult = $state<adminLib.NewProjectResult | null>(null);
  let saveAsName = $state('');
  let saveAsDest = $state('');
  let saveAsActivate = $state(false);
  let saveAsResult = $state<adminLib.SaveProjectAsResult | null>(null);
  let splinterName = $state('');
  let splinterDest = $state('');
  let splinterUseSu = $state(true);
  let splinterUnitsRaw = $state('');
  let splinterPlotsRaw = $state('');
  let splinterActivate = $state(false);
  let splinterResult = $state<adminLib.ExportSplinterResult | null>(null);
  let complianceUseSu = $state(false);
  let complianceReport = $state<adminLib.ComplianceValidationReport | null>(null);
  let confirmQuarantine = $state(false);
  let quarantineResult = $state<adminLib.QuarantineOrphanResult | null>(null);
  let optPlotNumbersRaw = $state('');
  let optCustodianAuditOverride = $state(false);
  let optConfirmReviewed = $state(false);
  let optPreview = $state<adminLib.OptimizeVegPreview | null>(null);
  let optResult = $state<adminLib.OptimizeVegResult | null>(null);
  let cmpTargetPath = $state('');
  let cmpTargetProject = $state('');
  let cmpSourcePath = $state('');
  let cmpSourceProject = $state('');
  let cmpCaseInsensitive = $state(false);
  let cmpExportPreview = $state<{ format: 'CSV' | 'TSV'; text: string } | null>(null);
  let cmpResult = $state<adminLib.CompareProjectsResult | null>(null);
  let mergeSourcePath = $state('');
  let mergeSourceProject = $state('');
  let mergeBasePath = $state('');
  let mergeBaseProject = $state('');
  let mergeTargetPath = $state('');
  let mergeTargetProject = $state('');
  let mergeCaseInsensitive = $state(false);
  let mergeDefaultResolution = $state<adminLib.MergeResolutionChoice>('keep_target');
  let mergePreview = $state<adminLib.ThreeWayMergePreview | null>(null);
  let mergePlotResolutions = $state<Record<string, adminLib.MergeResolutionChoice>>({});
  let mergeFieldResolutions = $state<Record<string, adminLib.MergeResolutionChoice>>({});
  let mergeResult = $state<adminLib.ThreeWayMergeResult | null>(null);

  $effect(() => {
    const key = `${initialTab}::${initialTabNonce}`;
    if (initialTab && key !== lastAppliedInitialKey && !busy) {
      lastAppliedInitialKey = key;
      activeTab = initialTab;
    }
  });

  $effect(() => {
    if (presetsLoadStarted || !port.listProjectMetadataPresets) return;
    presetsLoadStarted = true;
    void port
      .listProjectMetadataPresets()
      .then((loaded) => {
        if (Array.isArray(loaded) && loaded.length > 0) availablePresets = loaded;
      })
      .catch(() => {});
  });

  const newProjIdTruncationWarning = $derived(adminLib.computeNewProjIdTruncationWarning(newProjName, newProjId));
  const complianceFindingCounts = $derived(
    complianceReport
      ? {
          envAdmin: complianceReport.envAdminFindings?.length ?? 0,
          orphan: complianceReport.orphanFindings?.length ?? 0,
          taxonomy: complianceReport.taxonomyFindings?.length ?? 0,
        }
      : null
  );
  const optUnresolvedConflictCount = $derived.by(() => {
    if (!optPreview) return 0;
    if (typeof optPreview.blockedGroupCount === 'number' && optPreview.blockedGroupCount > 0)
      return optPreview.blockedGroupCount;
    return optPreview.hasBlockingConflicts ? optPreview.conflicts?.length || 1 : 0;
  });
  const cmpAllDiffs = $derived(cmpResult ? [...(cmpResult.fieldDiffs ?? []), ...(cmpResult.metadataDiffs ?? [])] : []);
  const lazyView = $derived({
    activeTab: activeTab as 'lifecycle' | 'compliance' | 'optimizeveg' | 'merge',
    busy,
    activeProject,
    activeSu,
    availablePresets,
    newProjIdTruncationWarning,
    newProjResult,
    saveAsResult,
    splinterResult,
    complianceReport,
    quarantineResult,
    complianceFindingCounts,
    optPreview,
    optResult,
    optUnresolvedConflictCount,
    cmpResult,
    cmpAllDiffs,
    cmpExportPreview,
    mergePreview,
    mergePlotResolutions,
    mergeFieldResolutions,
    mergeResult,
  });

  const setBusy = (next: boolean) => {
    busy = next;
    onBusyChange?.(next);
  };
  onDestroy(() => {
    generation++;
    onBusyChange?.(false);
  });

  const notifyAdmin = (
    severity: 'success' | 'info' | 'warning' | 'error',
    title: string,
    message: string,
    toast = true
  ) => adminLib.pushAdminNotification(severity, title, message, activeProject, toast);

  function failAdmin(title: string, message: string) {
    error = message;
    notifyAdmin('error', title, message);
  }

  async function notifyLifecycleSwitch(res: { activated: boolean; state?: unknown }) {
    if (res.activated && res.state && oncontextswitched) await oncontextswitched(res.state);
    else if (typeof onprojectlistchanged === 'function') await onprojectlistchanged(res.state);
  }

  async function runAdminOp(
    busyLabel: string,
    errorLabel: string,
    fn: (isCurrent: () => boolean) => Promise<adminLib.AdminOpOutcome | void>
  ) {
    if (busy || operationHeld)
      return failAdmin('Project admin action held', `Wait for the current operation or decision before ${busyLabel}.`);
    const gen = ++generation;
    setBusy(true);
    error = null;
    statusMessage = null;
    try {
      const outcome = await fn(() => gen === generation);
      if (gen === generation && outcome) {
        statusMessage = outcome.message;
        notifyAdmin(outcome.severity, outcome.title, outcome.message);
        if (outcome.lifecycle) await notifyLifecycleSwitch(outcome.lifecycle);
      }
    } catch (cause) {
      if (gen === generation) failAdmin(errorLabel, `${errorLabel}: ${adminLib.formatError(cause)}`);
    } finally {
      if (gen === generation) setBusy(false);
    }
  }

  async function submitCreateNewProject() {
    const req = $state.snapshot(
      adminLib.buildNewProjectPayload(newProjName, newProjId, newProjTitle, newProjPreset, newProjDest, newProjActivate)
    );
    await runAdminOp('creating a project', 'Create project failed', async (isCurrent) => {
      const vErr = adminLib.validateNewProjectDraft(req);
      if (vErr) return failAdmin('Create project validation failed', vErr);
      const res = await port.createNewProject(contextId, req);
      if (!isCurrent()) return;
      newProjResult = res;
      return adminLib.describeNewProjectOutcome(res);
    });
  }

  async function submitSaveProjectAs() {
    const req = $state.snapshot(adminLib.buildSaveProjectAsPayload(saveAsName, saveAsDest, saveAsActivate));
    await runAdminOp('saving project copy', 'Save Project As failed', async (isCurrent) => {
      const vErr = adminLib.validateProjectNameInput(req.newProjectName);
      if (vErr) return failAdmin('Save Project As validation failed', vErr);
      const res = await port.saveProjectAs(contextId, req);
      if (!isCurrent()) return;
      saveAsResult = res;
      return adminLib.describeSaveProjectAsOutcome(res);
    });
  }

  async function submitExportSplinter() {
    const req = $state.snapshot(
      adminLib.buildSplinterPayload(
        splinterName,
        splinterDest,
        splinterUseSu,
        splinterUnitsRaw,
        splinterPlotsRaw,
        splinterActivate
      )
    );
    await runAdminOp('exporting splinter project', 'Export Splinter Project failed', async (isCurrent) => {
      const vErr = adminLib.validateSplinterDraft(req, activeSu);
      if (vErr) return failAdmin('Export Splinter Project validation failed', vErr);
      const res = await port.exportSplinterProject(contextId, req);
      if (!isCurrent()) return;
      splinterResult = res;
      return adminLib.describeExportSplinterOutcome(res);
    });
  }

  async function runCompliance() {
    const opts = $state.snapshot({ useActiveSu: complianceUseSu });
    await runAdminOp('running compliance validation', 'Compliance validation failed', async (isCurrent) => {
      const report = await port.runComplianceValidation(contextId, opts);
      if (!isCurrent()) return;
      complianceReport = report;
      confirmQuarantine = false;
      return adminLib.describeComplianceOutcome(report);
    });
  }

  async function runQuarantine() {
    if (!busy && !operationHeld && !confirmQuarantine) {
      return failAdmin(
        'Orphan quarantine confirmation required',
        'Confirm orphan quarantine before moving orphan child rows.'
      );
    }
    const req = $state.snapshot({});
    await runAdminOp('quarantining orphan rows', 'Orphan quarantine failed', async (isCurrent) => {
      const res = await port.quarantineOrphanRecords(contextId, req);
      if (!isCurrent()) return;
      quarantineResult = res;
      confirmQuarantine = false;
      const outcome = adminLib.describeQuarantineOutcome(res);
      statusMessage = outcome.message;
      notifyAdmin(outcome.severity, outcome.title, outcome.message);
      const refreshed = await port.runComplianceValidation(
        contextId,
        $state.snapshot({ useActiveSu: complianceUseSu })
      );
      if (isCurrent()) complianceReport = refreshed;
    });
  }

  async function runPreviewOptimizeVeg() {
    const opts = $state.snapshot(adminLib.buildOptimizeVegOptions(optPlotNumbersRaw, optCustodianAuditOverride));
    await runAdminOp('previewing OptimizeVeg', 'Preview OptimizeVeg failed', async (isCurrent) => {
      const preview = await port.previewOptimizeVeg(contextId, opts);
      if (!isCurrent()) return;
      optPreview = preview;
      optConfirmReviewed = false;
      optResult = null;
      return adminLib.summarizeOptimizeVegPreview(preview);
    });
  }

  async function runApplyOptimizeVeg() {
    if (!busy && !operationHeld) {
      const gateErr = adminLib.checkOptimizeVegApplyGate(optPreview, optUnresolvedConflictCount, optConfirmReviewed);
      if (gateErr) return failAdmin(gateErr.title, gateErr.message);
    }
    const req = $state.snapshot({
      ...adminLib.buildOptimizeVegOptions(optPlotNumbersRaw, optCustodianAuditOverride),
      expectedDigest: optPreview?.previewDigest ?? '',
    });
    await runAdminOp('applying OptimizeVeg', 'Apply OptimizeVeg failed', async (isCurrent) => {
      const res = await port.applyOptimizeVeg(contextId, req);
      if (!isCurrent()) return;
      optResult = res;
      optPreview = null;
      optConfirmReviewed = false;
      return adminLib.describeApplyOptimizeVegOutcome(res);
    });
  }

  async function runCompareProjects() {
    if (!busy && !operationHeld && !cmpTargetPath.trim()) {
      return failAdmin('Compare target path required', 'Target .db file path is required to compare projects.');
    }
    const req = $state.snapshot(
      adminLib.buildCompareProjectsPayload(
        cmpSourcePath,
        cmpSourceProject,
        cmpTargetPath,
        cmpTargetProject,
        cmpCaseInsensitive
      )
    );
    await runAdminOp('comparing projects', 'Compare Projects failed', async (isCurrent) => {
      cmpExportPreview = null;
      const res = await port.compareProjects(contextId, req);
      if (!isCurrent()) return;
      cmpResult = res;
      return adminLib.describeCompareProjectsOutcome(res);
    });
  }

  function exportCompareDiffs(format: 'CSV' | 'TSV') {
    if (!cmpResult) return;
    const text = adminLib.formatCompareDiffsDelimited(cmpResult, format === 'TSV' ? '\t' : ',');
    cmpExportPreview = { format, text };
    adminLib.triggerCompareDiffDownload(cmpResult, format, text);
    statusMessage = `Prepared ${format} export with ${cmpAllDiffs.length} project diff row(s).`;
    notifyAdmin('success', `Prepared ${format} comparison export`, statusMessage);
  }

  const mergeEndpoints = (preview?: adminLib.ThreeWayMergePreview | null) =>
    adminLib.buildThreeWayMergeEndpoints(preview, {
      sourcePath: mergeSourcePath,
      sourceProject: mergeSourceProject,
      targetPath: mergeTargetPath,
      targetProject: mergeTargetProject,
      basePath: mergeBasePath,
      baseProject: mergeBaseProject,
      caseInsensitive: mergeCaseInsensitive,
    });

  async function runPreviewMerge() {
    if (!busy && !operationHeld && !mergeSourcePath.trim()) {
      return failAdmin('3-Way merge source required', 'Staging source .db path is required for 3-way merge preview.');
    }
    const req = $state.snapshot(mergeEndpoints());
    await runAdminOp('previewing merge', 'Preview 3-Way Merge failed', async (isCurrent) => {
      const preview = await port.previewThreeWayMerge(contextId, req);
      if (!isCurrent()) return;
      mergePreview = preview;
      mergeResult = null;
      mergePlotResolutions = adminLib.buildInitialMergePlotResolutions(preview);
      mergeFieldResolutions = adminLib.buildInitialMergeFieldResolutions(preview);
      return adminLib.describePreviewMergeOutcome(preview);
    });
  }

  async function runExecuteMerge() {
    if (!busy && !operationHeld && !mergePreview) {
      return failAdmin('3-Way merge preview required', 'Run Preview 3-Way Merge before executing merge.');
    }
    if (!mergePreview) return;
    const req = {
      ...adminLib.buildExecuteMergePayload(
        mergePreview,
        mergeEndpoints(mergePreview),
        mergeDefaultResolution,
        $state.snapshot(mergePlotResolutions),
        $state.snapshot(mergeFieldResolutions)
      ),
    };
    await runAdminOp('executing merge', 'Execute 3-Way Merge failed', async (isCurrent) => {
      const res = await port.executeThreeWayMerge(contextId, req);
      if (!isCurrent()) return;
      mergeResult = res;
      mergePreview = null;
      return adminLib.describeExecuteMergeOutcome(res);
    });
  }

  function setPlotResolution(plotNumber: string, choice: adminLib.MergeResolutionChoice) {
    mergePlotResolutions = { ...mergePlotResolutions, [plotNumber]: choice };
  }

  function setFieldResolution(conflictId: string, choice: adminLib.MergeResolutionChoice) {
    mergeFieldResolutions = { ...mergeFieldResolutions, [conflictId]: choice };
  }

  function resetOptPreview() {
    optPreview = null;
    optConfirmReviewed = false;
  }
  const openOptimizeVeg = () => (activeTab = 'optimizeveg');
  const lazyActions = {
    submitCreateNewProject,
    submitSaveProjectAs,
    submitExportSplinter,
    runCompliance,
    runQuarantine,
    openOptimizeVeg,
    resetOptPreview,
    previewOptimizeVeg: runPreviewOptimizeVeg,
    applyOptimizeVeg: runApplyOptimizeVeg,
    runCompare: runCompareProjects,
    exportCompareDiffs,
    previewMerge: runPreviewMerge,
    executeMerge: runExecuteMerge,
    setPlotResolution,
    setFieldResolution,
  };
</script>

<section
  data-tour="project-admin-root"
  class="vpro-project-admin min-w-0 space-y-4 rounded border border-vpro-border bg-white text-vpro-ink shadow-sm"
  aria-label="Project Lifecycle and Pre-Flight Workbench"
>
  <ProjectAdminHeader {activeProject} {activeSu} />

  <nav
    data-workbench-sticky-bar
    class="sticky top-0 z-20 flex flex-wrap gap-1 border-b border-vpro-border bg-white/95 px-5 py-2 backdrop-blur-xs"
    aria-label="Project workbench sections"
  >
    {#each [['lifecycle', 'Project Lifecycle (New / Save As / Splinter)'], ['compliance', 'Compliance Validator & Quarantine'], ['optimizeveg', 'Safe OptimizeVeg'], ['merge', 'Compare & 3-Way Merge'], ['cloudsync', 'Cloud BECMaster Sync']] as [id, label]}
      <button
        type="button"
        data-workbench-tab={id}
        disabled={busy}
        class={`rounded-t px-4 py-2 text-sm font-medium transition-colors ${activeTab === id ? 'border-b-[3px] border-b-vpro-gold bg-vpro-navy text-white' : 'bg-vpro-canvas text-vpro-ink hover:bg-vpro-rail'}`}
        onclick={() => {
          activeTab = id as WorkbenchTab;
          error = null;
        }}>{label}</button
      >
    {/each}
  </nav>

  <div class="space-y-4 px-5 pb-5">
    {#if error}<p role="alert" class="rounded border-l-4 border-red-700 bg-red-50 p-3 text-sm text-red-900">
        {error}
      </p>{/if}

    {#if activeTab === 'cloudsync'}
      {#await import('./CloudSyncWorkbench.svelte')}
        <p role="status" class="p-4 text-sm text-vpro-ink-secondary">Loading Cloud BECMaster Sync Workbench...</p>
      {:then { default: CloudSyncWorkbench }}
        <CloudSyncWorkbench
          {contextId}
          {activeProject}
          {activeSu}
          {operationHeld}
          onBusyChange={setBusy}
          {oncontextswitched}
        />
      {:catch loadError}
        <p role="alert" class="rounded border-l-4 border-red-700 bg-red-50 p-3 text-sm text-red-900">
          Cloud BECMaster Sync Workbench could not load: {adminLib.formatError(loadError)}
        </p>
      {/await}
    {:else}
      <ProjectAdminLazyTabs
        view={lazyView}
        actions={lazyActions}
        bind:newProjName
        bind:newProjId
        bind:newProjTitle
        bind:newProjPreset
        bind:newProjDest
        bind:newProjActivate
        bind:saveAsName
        bind:saveAsDest
        bind:saveAsActivate
        bind:splinterName
        bind:splinterDest
        bind:splinterUseSu
        bind:splinterUnitsRaw
        bind:splinterPlotsRaw
        bind:splinterActivate
        bind:complianceUseSu
        bind:confirmQuarantine
        bind:optPlotNumbersRaw
        bind:optCustodianAuditOverride
        bind:optConfirmReviewed
        bind:cmpTargetPath
        bind:cmpTargetProject
        bind:cmpSourceProject
        bind:cmpSourcePath
        bind:cmpCaseInsensitive
        bind:mergeSourcePath
        bind:mergeSourceProject
        bind:mergeBasePath
        bind:mergeBaseProject
        bind:mergeTargetPath
        bind:mergeTargetProject
        bind:mergeCaseInsensitive
        bind:mergeDefaultResolution
      />
    {/if}
  </div>
</section>
