<script lang="ts">
  import { onDestroy } from 'svelte';
  import {
    defaultProjectAdminPort, validateNewProjectDraft, validateProjectNameInput, validateSplinterDraft,
    parseLiteralTokenList, buildInitialMergeFieldResolutions, buildInitialMergePlotResolutions, formatCompareDiffsDelimited,
    notifications,
    type ProjectAdminPort, type ProjectMetadataPreset, type NewProjectResult, type SaveProjectAsResult,
    type ExportSplinterResult, type CompareProjectsResult, type ComplianceValidationReport,
    type QuarantineOrphanResult, type OptimizeVegPreview, type OptimizeVegResult,
    type ThreeWayMergePreview, type ThreeWayMergeResult, type MergeResolutionChoice,
  } from './projectAdminWorkbench';

  type WorkbenchTab = 'lifecycle' | 'compliance' | 'optimizeveg' | 'merge' | 'cloudsync';

  let {
    contextId, activeProject, activeSu = 'None', initialTab = 'lifecycle', initialTabNonce = 0,
    operationHeld = false, port = defaultProjectAdminPort, onBusyChange, oncontextswitched,
  }: {
    contextId: string; activeProject: string; activeSu?: string; initialTab?: WorkbenchTab;
    initialTabNonce?: number; operationHeld?: boolean; port?: ProjectAdminPort;
    onBusyChange?: (busy: boolean) => void; oncontextswitched?: (state: unknown) => void;
  } = $props();

  let activeTab = $state<WorkbenchTab>('lifecycle');
  let lastAppliedInitialKey = 'lifecycle::0';
  let busy = $state(false);
  let error = $state<string | null>(null);
  let statusMessage = $state<string | null>(null);
  let generation = 0;

  $effect(() => {
    const requested = initialTab;
    const key = `${requested}::${initialTabNonce}`;
    if (requested && key !== lastAppliedInitialKey && !busy) {
      lastAppliedInitialKey = key;
      activeTab = requested;
    }
  });

  function setBusy(next: boolean) {
    busy = next;
    onBusyChange?.(next);
  }

  const FALLBACK_PRESETS: ProjectMetadataPreset[] = [
    { id: 'LMH25_2023_FS882', label: 'LMH25 (2023) Standard FS882', description: 'B.C. Ministry of Forests LMH 25 (2nd Ed., 2023) full ecosystem field form (NAD83).', ecosysCollectionStandard: 'LMH25', vegCoverMethod: 'Percent', plotMethod: '20x20', datum: 'NAD83', coverDescriptions: {} },
    { id: 'LMH25_FS1333_SIVI', label: 'LMH25 FS1333 SIVI Ground', description: 'LMH 25 FS1333 Site Inspection and Vegetation Inventory rapid ground protocol (NAD83).', ecosysCollectionStandard: 'LMH25', vegCoverMethod: 'Percent', plotMethod: '20x20', datum: 'NAD83', coverDescriptions: {} },
    { id: 'DEIF_1980', label: 'DEIF 1980 Historical', description: 'Describing Ecosystems in the Field (1980) historical BEC standard normalized to NAD83.', ecosysCollectionStandard: 'DEIF 1980', vegCoverMethod: 'Percent', plotMethod: '20x20', datum: 'NAD83', coverDescriptions: {} },
    { id: 'CHARS_Arctic', label: 'CHARS Arctic', description: 'CHARS tundra/subarctic standard with extended Arctic shrub covers Cover5a..5c (NAD83).', ecosysCollectionStandard: 'CHAR', vegCoverMethod: 'Percent', plotMethod: '20x20', datum: 'NAD83', coverDescriptions: {} },
  ];
  let availablePresets = $state<ProjectMetadataPreset[]>(FALLBACK_PRESETS);
  let presetsLoadStarted = false;
  let newProjName = $state('');
  let newProjId = $state('');
  let newProjTitle = $state('');
  let newProjPreset = $state('LMH25_2023_FS882');
  let newProjDest = $state('');
  let newProjActivate = $state(false);
  let newProjResult = $state<NewProjectResult | null>(null);

  let saveAsName = $state('');
  let saveAsDest = $state('');
  let saveAsActivate = $state(false);
  let saveAsResult = $state<SaveProjectAsResult | null>(null);

  let splinterName = $state('');
  let splinterDest = $state('');
  let splinterUseSu = $state(true);
  let splinterUnitsRaw = $state('');
  let splinterPlotsRaw = $state('');
  let splinterActivate = $state(false);
  let splinterResult = $state<ExportSplinterResult | null>(null);

  let complianceUseSu = $state(false);
  let complianceReport = $state<ComplianceValidationReport | null>(null);
  let confirmQuarantine = $state(false);
  let quarantineResult = $state<QuarantineOrphanResult | null>(null);

  let optPlotNumbersRaw = $state('');
  let optCustodianAuditOverride = $state(false);
  let optConfirmReviewed = $state(false);
  let optPreview = $state<OptimizeVegPreview | null>(null);
  let optResult = $state<OptimizeVegResult | null>(null);

  let cmpTargetPath = $state('');
  let cmpTargetProject = $state('');
  let cmpSourcePath = $state('');
  let cmpSourceProject = $state('');
  let cmpCaseInsensitive = $state(false);
  let cmpExportPreview = $state<{ format: 'CSV' | 'TSV'; text: string } | null>(null);
  let cmpResult = $state<CompareProjectsResult | null>(null);

  let mergeSourcePath = $state('');
  let mergeSourceProject = $state('');
  let mergeBasePath = $state('');
  let mergeBaseProject = $state('');
  let mergeTargetPath = $state('');
  let mergeTargetProject = $state('');
  let mergeCaseInsensitive = $state(false);
  let mergeDefaultResolution = $state<MergeResolutionChoice>('keep_target');
  let mergePreview = $state<ThreeWayMergePreview | null>(null);
  let mergePlotResolutions = $state<Record<string, MergeResolutionChoice>>({});
  let mergeFieldResolutions = $state<Record<string, MergeResolutionChoice>>({});
  let mergeResult = $state<ThreeWayMergeResult | null>(null);

  const selectedNewProjPreset = $derived(availablePresets.find(p => p.id === newProjPreset) ?? null);
  const newProjIdTruncationWarning = $derived(
    newProjName.trim().length > 20 && newProjId.trim() === ''
      ? `Project name exceeds 20 characters and ProjectID is blank; derived ProjectID will truncate to "${newProjName.trim().slice(0, 20)}".`
      : null
  );
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
    if (typeof optPreview.blockedGroupCount === 'number' && optPreview.blockedGroupCount > 0) {
      return optPreview.blockedGroupCount;
    }
    return optPreview.hasBlockingConflicts ? (optPreview.conflicts?.length || 1) : 0;
  });
  const cmpAllDiffs = $derived(
    cmpResult ? [...(cmpResult.fieldDiffs ?? []), ...(cmpResult.metadataDiffs ?? [])] : []
  );

  $effect(() => {
    if (presetsLoadStarted) return;
    presetsLoadStarted = true;
    const loader = port.listProjectMetadataPresets;
    if (!loader) return;
    void loader()
      .then(loaded => { if (Array.isArray(loaded) && loaded.length > 0) availablePresets = loaded; })
      .catch(() => { /* Retain canonical NAD83 presets if dynamic listing fails. */ });
  });

  const newProjValidationError = $derived(
    newProjName === ''
      ? null
      : validateNewProjectDraft({
          projectName: newProjName,
          projectId: newProjId || undefined,
          projectTitle: newProjTitle || undefined,
          presetId: newProjPreset || undefined,
          destinationPath: newProjDest || undefined,
          activateOnSuccess: newProjActivate,
        })
  );
  const saveAsValidationError = $derived(saveAsName === '' ? null : validateProjectNameInput(saveAsName));
  const splinterValidationError = $derived(
    splinterName === ''
      ? null
      : validateSplinterDraft(
          {
            splinterProject: splinterName,
            destinationPath: splinterDest || undefined,
            useActiveSu: splinterUseSu,
            siteUnits: parseLiteralTokenList(splinterUnitsRaw),
            plotNumbers: parseLiteralTokenList(splinterPlotsRaw),
            activateOnSuccess: splinterActivate,
          },
          activeSu
        )
  );

  onDestroy(() => {
    generation++;
    onBusyChange?.(false);
  });

  function notifyAdmin(
    severity: 'success' | 'info' | 'warning' | 'error',
    title: string,
    message: string,
    toast = true,
  ) {
    if (typeof notifications === 'undefined') return;
    const opts = {
      category: 'admin' as const,
      source: 'Project Admin',
      contextTag: activeProject || undefined,
      toast,
    };
    if (severity === 'success') notifications.success(title, message, opts);
    else if (severity === 'warning') notifications.warning(title, message, opts);
    else if (severity === 'error') notifications.error(title, message, opts);
    else notifications.info(title, message, opts);
  }

  async function runAdminOp(busyLabel: string, errorLabel: string, fn: (isCurrent: () => boolean) => Promise<void>) {
    if (busy || operationHeld) {
      error = `Wait for the current operation or decision before ${busyLabel}.`;
      notifyAdmin('error', 'Project admin action held', error);
      return;
    }
    const gen = ++generation;
    setBusy(true);
    error = null;
    statusMessage = null;
    try {
      await fn(() => gen === generation);
    } catch (cause) {
      if (gen === generation) {
        error = `${errorLabel}: ${String(cause)}`;
        notifyAdmin('error', errorLabel, error);
      }
    } finally {
      if (gen === generation) setBusy(false);
    }
  }

  async function submitCreateNewProject() {
    const req = $state.snapshot({
      projectName: newProjName,
      projectId: newProjId || undefined,
      projectTitle: newProjTitle || undefined,
      presetId: newProjPreset || undefined,
      destinationPath: newProjDest || undefined,
      activateOnSuccess: newProjActivate,
    });
    await runAdminOp('creating a project', 'Create project failed', async isCurrent => {
      const vErr = validateNewProjectDraft(req);
      if (vErr) {
        error = vErr;
        notifyAdmin('error', 'Create project validation failed', vErr);
        return;
      }
      const res = await port.createNewProject(contextId, req);
      if (!isCurrent()) return;
      newProjResult = res;
      statusMessage = `Created VPro project "${res.projectName}" at ${res.destinationPath}.`;
      notifyAdmin('success', `Created project "${res.projectName}"`, statusMessage);
      if (res.activated && res.state && oncontextswitched) oncontextswitched(res.state);
    });
  }

  async function submitSaveProjectAs() {
    const req = $state.snapshot({
      newProjectName: saveAsName,
      destinationPath: saveAsDest || undefined,
      activateOnSuccess: saveAsActivate,
    });
    await runAdminOp('saving project copy', 'Save Project As failed', async isCurrent => {
      const vErr = validateProjectNameInput(req.newProjectName);
      if (vErr) {
        error = vErr;
        notifyAdmin('error', 'Save Project As validation failed', vErr);
        return;
      }
      const res = await port.saveProjectAs(contextId, req);
      if (!isCurrent()) return;
      saveAsResult = res;
      statusMessage = `Saved project "${res.sourceProject}" as "${res.newProjectName}" (${res.copiedTables.length} tables).`;
      notifyAdmin('success', `Saved project as "${res.newProjectName}"`, statusMessage);
      if (res.activated && res.state && oncontextswitched) oncontextswitched(res.state);
    });
  }

  async function submitExportSplinter() {
    const req = $state.snapshot({
      splinterProject: splinterName,
      destinationPath: splinterDest || undefined,
      useActiveSu: splinterUseSu,
      siteUnits: parseLiteralTokenList(splinterUnitsRaw),
      plotNumbers: parseLiteralTokenList(splinterPlotsRaw),
      activateOnSuccess: splinterActivate,
    });
    await runAdminOp('exporting splinter project', 'Export Splinter Project failed', async isCurrent => {
      const vErr = validateSplinterDraft(req, activeSu);
      if (vErr) {
        error = vErr;
        notifyAdmin('error', 'Export Splinter Project validation failed', vErr);
        return;
      }
      const res = await port.exportSplinterProject(contextId, req);
      if (!isCurrent()) return;
      splinterResult = res;
      statusMessage = `Exported ${res.exportedPlotCount} of ${res.sourcePlotCount} plots to "${res.splinterProject}".`;
      notifyAdmin('success', `Exported splinter "${res.splinterProject}"`, statusMessage);
      if (res.activated && res.state && oncontextswitched) oncontextswitched(res.state);
    });
  }

  async function runCompliance() {
    const opts = $state.snapshot({ useActiveSu: complianceUseSu });
    await runAdminOp('running compliance validation', 'Compliance validation failed', async isCurrent => {
      const report = await port.runComplianceValidation(contextId, opts);
      if (!isCurrent()) return;
      complianceReport = report;
      confirmQuarantine = false;
      statusMessage = report.passed
        ? `Compliance validation passed for project "${report.project}".`
        : `Compliance validation identified issues requiring review in "${report.project}".`;
      notifyAdmin(
        report.passed ? 'success' : 'warning',
        report.passed ? `Compliance passed: ${report.project}` : `Compliance issues found: ${report.project}`,
        statusMessage,
      );
    });
  }

  async function runQuarantine() {
    if (!busy && !operationHeld && !confirmQuarantine) {
      error = 'Confirm orphan quarantine before moving orphan child rows.';
      notifyAdmin('error', 'Orphan quarantine confirmation required', error);
      return;
    }
    const req = $state.snapshot({});
    await runAdminOp('quarantining orphan rows', 'Orphan quarantine failed', async isCurrent => {
      const res = await port.quarantineOrphanRecords(contextId, req);
      if (!isCurrent()) return;
      quarantineResult = res;
      confirmQuarantine = false;
      statusMessage = `Quarantined ${res.totalQuarantined} orphan child row(s) into quarantine tables (batch ${res.batchId}).`;
      notifyAdmin('success', 'Orphan child rows quarantined', statusMessage);
      const refreshed = await port.runComplianceValidation(contextId, $state.snapshot({ useActiveSu: complianceUseSu }));
      if (isCurrent()) complianceReport = refreshed;
    });
  }

  async function runPreviewOptimizeVeg() {
    const plotNumbers = parseLiteralTokenList(optPlotNumbersRaw);
    const opts = $state.snapshot({
      plotNumbers: plotNumbers.length > 0 ? plotNumbers : undefined,
      custodianAuditOverride: optCustodianAuditOverride || undefined,
    });
    await runAdminOp('previewing OptimizeVeg', 'Preview OptimizeVeg failed', async isCurrent => {
      const preview = await port.previewOptimizeVeg(contextId, opts);
      if (!isCurrent()) return;
      optPreview = preview;
      optConfirmReviewed = false;
      optResult = null;
      const blockedCount =
        typeof preview.blockedGroupCount === 'number' && preview.blockedGroupCount > 0
          ? preview.blockedGroupCount
          : preview.hasBlockingConflicts
            ? preview.conflicts?.length || 1
            : 0;
      statusMessage =
        blockedCount > 0
          ? `OptimizeVeg preview found ${blockedCount} blocked group(s) with unresolved conflicts.`
          : `OptimizeVeg preview: ${preview.duplicateSpeciesCount} multi-row species group(s) (${preview.beforeRowCount} -> ${preview.afterRowCount} rows).`;
      notifyAdmin(
        blockedCount > 0 ? 'warning' : 'info',
        blockedCount > 0 ? 'OptimizeVeg preview blocked by conflicts' : 'OptimizeVeg preview ready',
        statusMessage,
      );
    });
  }

  async function runApplyOptimizeVeg() {
    if (!busy && !operationHeld) {
      if (!optPreview) {
        error = 'Run Preview OptimizeVeg before applying consolidation.';
        notifyAdmin('error', 'OptimizeVeg preview required', error);
        return;
      }
      if (optUnresolvedConflictCount > 0) {
        error = `Resolve ${optUnresolvedConflictCount} OptimizeVeg blocking conflict(s) (or re-run preview with Custodian Audit Override if only _Audit references remain) before committing.`;
        notifyAdmin('error', 'OptimizeVeg conflicts unresolved', error);
        return;
      }
      if (!optConfirmReviewed) {
        error = 'Check "I have reviewed conflicts and want to commit OptimizeVeg" before committing.';
        notifyAdmin('error', 'OptimizeVeg confirmation required', error);
        return;
      }
    }
    const plotNumbers = parseLiteralTokenList(optPlotNumbersRaw);
    const req = $state.snapshot({
      plotNumbers: plotNumbers.length > 0 ? plotNumbers : undefined,
      expectedDigest: optPreview?.previewDigest ?? '',
      custodianAuditOverride: optCustodianAuditOverride || undefined,
    });
    await runAdminOp('applying OptimizeVeg', 'Apply OptimizeVeg failed', async isCurrent => {
      const res = await port.applyOptimizeVeg(contextId, req);
      if (!isCurrent()) return;
      optResult = res;
      optPreview = null;
      optConfirmReviewed = false;
      statusMessage = `OptimizeVeg consolidated ${res.consolidatedGroups} group(s), removed ${res.deletedRows} duplicate row(s), and wrote ${res.auditRowsWritten} audit row(s).`;
      notifyAdmin('success', 'OptimizeVeg consolidation complete', statusMessage);
    });
  }

  async function runCompareProjects() {
    if (!busy && !operationHeld && !cmpTargetPath.trim()) {
      error = 'Target .db file path is required to compare projects.';
      notifyAdmin('error', 'Compare target path required', error);
      return;
    }
    const req = $state.snapshot({
      sourcePath: cmpSourcePath.trim() || undefined,
      sourceProject: cmpSourceProject.trim() || undefined,
      targetPath: cmpTargetPath.trim(),
      targetProject: cmpTargetProject.trim() || undefined,
      caseInsensitiveText: cmpCaseInsensitive || undefined,
    });
    await runAdminOp('comparing projects', 'Compare Projects failed', async isCurrent => {
      cmpExportPreview = null;
      const res = await port.compareProjects(contextId, req);
      if (!isCurrent()) return;
      cmpResult = res;
      statusMessage = `Compared ${res.sourceProject} vs ${res.targetProject}: ${res.addedCount} Added, ${res.removedCount} Removed, ${res.modifiedCount} Modified, ${res.identicalCount} Identical.`;
      notifyAdmin('info', 'Project comparison complete', statusMessage);
    });
  }

  function exportCompareDiffs(format: 'CSV' | 'TSV') {
    if (!cmpResult) return;
    const text = formatCompareDiffsDelimited(cmpResult, format === 'TSV' ? '\t' : ',');
    cmpExportPreview = { format, text };
    if (typeof document !== 'undefined' && typeof Blob !== 'undefined' && typeof URL !== 'undefined' && typeof URL.createObjectURL === 'function') {
      const url = URL.createObjectURL(new Blob([text], { type: format === 'TSV' ? 'text/tab-separated-values;charset=utf-8' : 'text/csv;charset=utf-8' }));
      const a = document.createElement('a');
      a.href = url;
      a.download = `compare_${cmpResult.sourceProject}_vs_${cmpResult.targetProject}.${format.toLowerCase()}`;
      a.click();
      URL.revokeObjectURL(url);
    }
    statusMessage = `Prepared ${format} export with ${cmpAllDiffs.length} project diff row(s).`;
    notifyAdmin('success', `Prepared ${format} comparison export`, statusMessage);
  }

  function mergeEndpoints(preview?: ThreeWayMergePreview | null) {
    return {
      sourcePath: preview ? preview.sourcePath : mergeSourcePath.trim(),
      sourceProject: (preview?.sourceProject || mergeSourceProject.trim()) || undefined,
      targetPath: (preview ? preview.targetPath : mergeTargetPath.trim()) || undefined,
      targetProject: (preview?.targetProject || mergeTargetProject.trim()) || undefined,
      basePath: (preview?.basePath || mergeBasePath.trim()) || undefined,
      baseProject: (preview?.baseProject || mergeBaseProject.trim()) || undefined,
      caseInsensitiveText: mergeCaseInsensitive || undefined,
    };
  }

  async function runPreviewMerge() {
    if (!busy && !operationHeld && !mergeSourcePath.trim()) {
      error = 'Staging source .db path is required for 3-way merge preview.';
      notifyAdmin('error', '3-Way merge source required', error);
      return;
    }
    const req = $state.snapshot(mergeEndpoints());
    await runAdminOp('previewing merge', 'Preview 3-Way Merge failed', async isCurrent => {
      const preview = await port.previewThreeWayMerge(contextId, req);
      if (!isCurrent()) return;
      mergePreview = preview;
      mergeResult = null;
      mergePlotResolutions = buildInitialMergePlotResolutions(preview);
      mergeFieldResolutions = buildInitialMergeFieldResolutions(preview);
      statusMessage = `Merge preview ready: ${preview.addedCount} Added, ${preview.fastForwardCount} Fast-Forward, ${preview.sourceDeleteCount ?? 0} Source Delete, ${preview.conflictCount} Conflict plot(s).`;
      notifyAdmin('info', '3-Way merge preview ready', statusMessage);
    });
  }

  async function runExecuteMerge() {
    if (!busy && !operationHeld && !mergePreview) {
      error = 'Run Preview 3-Way Merge before executing merge.';
      notifyAdmin('error', '3-Way merge preview required', error);
      return;
    }
    if (!mergePreview) return;
    const req = $state.snapshot({
      ...mergeEndpoints(mergePreview),
      expectedPreviewDigest: mergePreview.previewDigest,
      defaultConflictResolution: mergeDefaultResolution,
      plotResolutions: mergePlotResolutions,
      fieldResolutions: mergeFieldResolutions,
    });
    await runAdminOp('executing merge', 'Execute 3-Way Merge failed', async isCurrent => {
      const res = await port.executeThreeWayMerge(contextId, req);
      if (!isCurrent()) return;
      mergeResult = res;
      mergePreview = null;
      statusMessage = `3-Way Merge complete: ${res.addedPlots} plot(s) added, ${res.updatedPlots} plot(s) updated, ${res.auditRowsWritten} audit row(s) recorded.`;
      notifyAdmin('success', '3-Way merge committed', statusMessage);
    });
  }

  function setPlotResolution(plotNumber: string, choice: MergeResolutionChoice) {
    mergePlotResolutions = { ...mergePlotResolutions, [plotNumber]: choice };
  }

  function setFieldResolution(conflictId: string, choice: MergeResolutionChoice) {
    mergeFieldResolutions = { ...mergeFieldResolutions, [conflictId]: choice };
  }
</script>

<section data-tour="project-admin-root" class="vpro-project-admin min-w-0 space-y-4 rounded border border-[#D8D8D8] bg-white text-[#313132] shadow-sm" aria-label="Project Lifecycle and Pre-Flight Workbench">
  <header class="border-b-[3px] border-b-[#FCBA19] bg-[#003366] px-4 py-3.5 sm:px-5 text-white">
    <div class="flex flex-wrap items-center justify-between gap-2">
      <div class="min-w-0">
        <p class="text-xs font-semibold uppercase tracking-wider text-[#FCBA19]">VPro Project Governance</p>
        <h2 class="m-0 text-base sm:text-lg font-semibold text-white">Project Lifecycle, Compliance Pre-Flight &amp; 3-Way Merge</h2>
      </div>
      <div class="text-xs text-slate-200 tabular-nums">
        Active Project: <span class="font-mono font-semibold text-white">{activeProject}</span>
        {#if activeSu !== 'None'}
          | Active SU: <span class="font-mono font-semibold text-[#FCBA19]">{activeSu}</span>
        {/if}
      </div>
    </div>
  </header>

  <nav data-workbench-sticky-bar class="sticky top-0 z-20 flex flex-wrap gap-1 border-b border-stone-200 bg-white/95 px-5 py-2 backdrop-blur-xs" aria-label="Project workbench sections">
    {#each [
      ['lifecycle', 'Project Lifecycle (New / Save As / Splinter)'],
      ['compliance', 'Compliance Validator & Quarantine'],
      ['optimizeveg', 'Safe OptimizeVeg'],
      ['merge', 'Compare & 3-Way Merge'],
      ['cloudsync', 'Cloud BECMaster Sync'],
    ] as [id, label]}
      <button
        type="button"
        data-workbench-tab={id}
        disabled={busy}
        class={`rounded-t px-4 py-2 text-sm font-medium transition-colors ${activeTab === id ? 'border-b-[3px] border-b-[#FCBA19] bg-[#003366] text-white' : 'bg-slate-100 text-slate-800 hover:bg-slate-200'}`}
        onclick={() => { activeTab = id as WorkbenchTab; error = null; }}
      >
        {label}
      </button>
    {/each}
  </nav>

  <div class="space-y-4 px-5 pb-5">
    {#if error}
      <p role="alert" class="rounded border-l-4 border-red-700 bg-red-50 p-3 text-sm text-red-900">{error}</p>
    {/if}

    {#if activeTab === 'lifecycle'}
      <div class="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <fieldset class="space-y-3 rounded border border-slate-300 border-t-[3px] border-t-[#FCBA19] p-4">
          <legend class="px-1 text-sm font-semibold text-[#003366]">Create New VPro Project</legend>
          <div class="space-y-1"><label class="block text-xs font-semibold text-slate-700" for="new-project-name">Project Name (A-Z, 0-9, _, max 31)</label><input id="new-project-name" type="text" class="w-full rounded border border-slate-300 p-2 text-sm" bind:value={newProjName} disabled={busy} aria-invalid={!!newProjValidationError} /></div>
          <div class="space-y-1"><label class="block text-xs font-semibold text-slate-700" for="new-project-id">Metadata ProjectID (optional, max 20)</label><input id="new-project-id" type="text" class="w-full rounded border border-slate-300 p-2 text-sm" bind:value={newProjId} disabled={busy} /></div>
          <div class="space-y-1"><label class="block text-xs font-semibold text-slate-700" for="new-project-title">Project Title (optional)</label><input id="new-project-title" type="text" class="w-full rounded border border-slate-300 p-2 text-sm" bind:value={newProjTitle} disabled={busy} /></div>
          <div class="space-y-1">
            <label class="block text-xs font-semibold text-[#313132]" for="new-project-preset">Standards Preset</label>
            <select id="new-project-preset" class="w-full rounded border border-[#9F9F9F] p-2 text-sm" bind:value={newProjPreset} disabled={busy}>
              {#each availablePresets as preset (preset.id)}<option value={preset.id}>{preset.label}</option>{/each}
              <option value="">None (Blank Metadata)</option>
            </select>
            {#if selectedNewProjPreset}<p class="text-[11px] text-[#474543]">Standard: <span class="font-mono font-semibold">{selectedNewProjPreset.ecosysCollectionStandard}</span> &middot; Datum: <span class="font-mono font-semibold">{selectedNewProjPreset.datum}</span> ({selectedNewProjPreset.plotMethod})</p>{/if}
          </div>
          {#if newProjIdTruncationWarning}<p role="status" data-projectid-truncation-warning class="rounded border-l-4 border-[#FCBA19] bg-[#FEF6E0] p-2 text-xs text-[#313132]">{newProjIdTruncationWarning}</p>{/if}
          <div class="space-y-1"><label class="block text-xs font-semibold text-slate-700" for="new-project-dest">Destination .db Path (optional)</label><input id="new-project-dest" type="text" class="w-full rounded border border-slate-300 p-2 text-sm font-mono" bind:value={newProjDest} disabled={busy} placeholder="Defaults to projects/<Name>.db" /></div>
          <label class="flex items-center gap-2 text-xs text-slate-800"><input type="checkbox" bind:checked={newProjActivate} disabled={busy} />Switch active context to new project immediately</label>
          {#if newProjValidationError}<p role="alert" class="text-xs text-[#D8292F]">{newProjValidationError}</p>{/if}
          <button type="button" disabled={busy || !newProjName || !!newProjValidationError} class="w-full rounded bg-[#003366] px-3 py-2 text-sm font-semibold text-white hover:bg-[#002244] disabled:opacity-50" onclick={submitCreateNewProject}>Create VPro Project</button>
          {#if newProjResult}<p class="break-all text-xs text-[#474543]">ProjectID: <span class="font-mono font-semibold text-[#003366]">{newProjResult.projectId}</span> &middot; SHA-256: <span class="font-mono">{newProjResult.destinationSha256.slice(0, 16)}</span></p>{/if}
        </fieldset>

        <fieldset class="space-y-3 rounded border border-slate-300 border-t-[3px] border-t-[#FCBA19] p-4">
          <legend class="px-1 text-sm font-semibold text-[#003366]">Save Active Project As</legend>
          <p class="text-xs text-slate-600">Lossless copy of <span class="font-mono font-semibold">{activeProject}</span> renaming prefix across core and companion (_SU, _Hierarchy, _Lump, _Profile) tables.</p>
          <div class="space-y-1"><label class="block text-xs font-semibold text-slate-700" for="saveas-name">New Project Prefix</label><input id="saveas-name" type="text" class="w-full rounded border border-slate-300 p-2 text-sm" bind:value={saveAsName} disabled={busy} aria-invalid={!!saveAsValidationError} /></div>
          <div class="space-y-1"><label class="block text-xs font-semibold text-slate-700" for="saveas-dest">Destination .db Path (optional)</label><input id="saveas-dest" type="text" class="w-full rounded border border-slate-300 p-2 text-sm font-mono" bind:value={saveAsDest} disabled={busy} placeholder="Defaults to projects/<NewPrefix>.db" /></div>
          <label class="flex items-center gap-2 text-xs text-slate-800"><input type="checkbox" bind:checked={saveAsActivate} disabled={busy} />Switch active context to saved copy</label>
          {#if saveAsValidationError}<p role="alert" class="text-xs text-red-700">{saveAsValidationError}</p>{/if}
          <button type="button" disabled={busy || !saveAsName || !!saveAsValidationError} class="w-full rounded bg-[#003366] px-3 py-2 text-sm font-semibold text-white hover:bg-[#002244] disabled:opacity-50" onclick={submitSaveProjectAs}>Save Project As</button>
          {#if saveAsResult && saveAsResult.companionTables.length > 0}<p class="text-xs text-slate-600">Preserved companions: <span class="font-mono">{saveAsResult.companionTables.join(', ')}</span></p>{/if}
        </fieldset>

        <fieldset class="space-y-3 rounded border border-slate-300 border-t-[3px] border-t-[#FCBA19] p-4">
          <legend class="px-1 text-sm font-semibold text-[#003366]">Export Splinter Project</legend>
          <div class="space-y-1"><label class="block text-xs font-semibold text-slate-700" for="splinter-name">Splinter Project Name</label><input id="splinter-name" type="text" class="w-full rounded border border-slate-300 p-2 text-sm" bind:value={splinterName} disabled={busy} aria-invalid={!!splinterValidationError} /></div>
          <label class="flex items-center gap-2 text-xs text-slate-800"><input type="checkbox" bind:checked={splinterUseSu} disabled={busy} />Filter by active Site Unit table ({activeSu})</label>
          <div class="space-y-1"><label class="block text-xs font-semibold text-slate-700" for="splinter-units">Site Unit Filter (comma-separated, optional)</label><input id="splinter-units" type="text" class="w-full rounded border border-slate-300 p-2 text-sm font-mono" bind:value={splinterUnitsRaw} disabled={busy} placeholder="e.g. CWHvm1/01, CWHvm1/05" /></div>
          <div class="space-y-1"><label class="block text-xs font-semibold text-slate-700" for="splinter-plots">Explicit Plot Subset (comma-separated, optional)</label><input id="splinter-plots" type="text" class="w-full rounded border border-slate-300 p-2 text-sm font-mono" bind:value={splinterPlotsRaw} disabled={busy} placeholder="e.g. 00337, 108050" /></div>
          <div class="space-y-1"><label class="block text-xs font-semibold text-slate-700" for="splinter-dest">Destination .db Path (optional)</label><input id="splinter-dest" type="text" class="w-full rounded border border-slate-300 p-2 text-sm font-mono" bind:value={splinterDest} disabled={busy} /></div>
          <label class="flex items-center gap-2 text-xs text-slate-800"><input type="checkbox" bind:checked={splinterActivate} disabled={busy} />Switch active context to splinter project</label>
          {#if splinterValidationError}<p role="alert" class="text-xs text-red-700">{splinterValidationError}</p>{/if}
          <button type="button" disabled={busy || !splinterName || !!splinterValidationError} class="w-full rounded bg-[#003366] px-3 py-2 text-sm font-semibold text-white hover:bg-[#002244] disabled:opacity-50" onclick={submitExportSplinter}>Export Splinter Project</button>
          {#if splinterResult}<p class="text-xs text-slate-600">Exported {splinterResult.exportedPlotCount} / {splinterResult.sourcePlotCount} plots.</p>{/if}
        </fieldset>
      </div>
    {:else if activeTab === 'compliance'}
      {#await import('./ProjectAdminComplianceTab.svelte')}
        <p role="status" class="p-4 text-sm text-slate-700">Loading Compliance Validator...</p>
      {:then { default: ProjectAdminComplianceTab }}
        <ProjectAdminComplianceTab {busy} {activeSu} bind:complianceUseSu bind:confirmQuarantine
          {complianceReport} {quarantineResult} findingCounts={complianceFindingCounts}
          onRunCompliance={runCompliance} onRunQuarantine={runQuarantine} onOpenOptimizeVeg={() => { activeTab = 'optimizeveg'; }} />
      {:catch loadError}
        <p role="alert" class="rounded border-l-4 border-red-700 bg-red-50 p-3 text-sm text-red-900">Compliance Validator could not load: {String(loadError)}</p>
      {/await}
    {:else if activeTab === 'optimizeveg'}
      {#await import('./ProjectAdminOptimizeVegTab.svelte')}
        <p role="status" class="p-4 text-sm text-slate-700">Loading Safe OptimizeVeg...</p>
      {:then { default: ProjectAdminOptimizeVegTab }}
        <ProjectAdminOptimizeVegTab {busy} bind:optPlotNumbersRaw bind:optCustodianAuditOverride bind:optConfirmReviewed
          {optPreview} {optResult} {optUnresolvedConflictCount}
          onOverrideChange={() => { optPreview = null; optConfirmReviewed = false; }}
          onPreviewOptimizeVeg={runPreviewOptimizeVeg} onApplyOptimizeVeg={runApplyOptimizeVeg} />
      {:catch loadError}
        <p role="alert" class="rounded border-l-4 border-red-700 bg-red-50 p-3 text-sm text-red-900">Safe OptimizeVeg could not load: {String(loadError)}</p>
      {/await}
    {:else if activeTab === 'merge'}
      {#await import('./ProjectAdminMergeTab.svelte')}
        <p role="status" class="p-4 text-sm text-slate-700">Loading Compare &amp; 3-Way Merge...</p>
      {:then { default: ProjectAdminMergeTab }}
        <ProjectAdminMergeTab {busy} bind:cmpTargetPath bind:cmpTargetProject bind:cmpSourceProject
          bind:cmpSourcePath bind:cmpCaseInsensitive {cmpResult} {cmpAllDiffs} {cmpExportPreview}
          bind:mergeSourcePath bind:mergeSourceProject bind:mergeBasePath bind:mergeBaseProject
          bind:mergeTargetPath bind:mergeTargetProject bind:mergeCaseInsensitive bind:mergeDefaultResolution
          {mergePreview} {mergePlotResolutions} {mergeFieldResolutions} {mergeResult}
          onRunCompare={runCompareProjects} onExportCompareDiffs={exportCompareDiffs}
          onPreviewMerge={runPreviewMerge} onExecuteMerge={runExecuteMerge}
          onSetPlotResolution={setPlotResolution} onSetFieldResolution={setFieldResolution} />
      {:catch loadError}
        <p role="alert" class="rounded border-l-4 border-red-700 bg-red-50 p-3 text-sm text-red-900">Compare &amp; 3-Way Merge could not load: {String(loadError)}</p>
      {/await}
    {:else if activeTab === 'cloudsync'}
      {#await import('./CloudSyncWorkbench.svelte')}
        <p role="status" class="p-4 text-sm text-slate-700">Loading Cloud BECMaster Sync Workbench...</p>
      {:then { default: CloudSyncWorkbench }}
        <CloudSyncWorkbench {contextId} {activeProject} {activeSu} {operationHeld} onBusyChange={setBusy} {oncontextswitched} />
      {:catch loadError}
        <p role="alert" class="rounded border-l-4 border-red-700 bg-red-50 p-3 text-sm text-red-900">Cloud BECMaster Sync Workbench could not load: {String(loadError)}</p>
      {/await}
    {/if}
  </div>
</section>
