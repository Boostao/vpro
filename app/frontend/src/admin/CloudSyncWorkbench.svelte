<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import CloudSyncAuthPanel from './CloudSyncAuthPanel.svelte';
  import CloudSyncPullPanel from './CloudSyncPullPanel.svelte';
  import CloudSyncStagingPanel from './CloudSyncStagingPanel.svelte';
  import CloudSyncCustodianStandardsPanel, {
    type PublishStandardsDraft,
    type SeedBaselineExtras,
  } from './CloudSyncCustodianStandardsPanel.svelte';
  import CloudSyncCustodianMergePanel from './CloudSyncCustodianMergePanel.svelte';
  import CloudSyncSnapshotsPanel from './CloudSyncSnapshotsPanel.svelte';
  import {
    defaultCloudSyncPort,
    validateProjectNameInput,
    buildSubsetFilterDraft,
    canUploadStagingSubmission,
    buildInitialCloudMergeFieldResolutions,
    validateSnapshotTagInput,
    type CloudSyncPort,
    type CloudRoleMode,
    type CloudMergeResolution,
    type CloudConfigStatus,
    type CloudConnectionReport,
    type SchemaBootstrapResult,
    type AuditChainVerification,
    type PublishStandardsResult,
    type SeedBaselineResult,
    type PullStandardsResult,
    type SubsetPreview,
    type PullSubsetResult,
    type StagingPreflightPreview,
    type SubmitStagingResult,
    type StagingSubmissionSummary,
    type StagingSubmissionDetail,
    type StagingMergePreview,
    type StagingMergeResult,
    type SnapshotRecord,
    type DownloadLogEntry,
    type CloudMergeConflictItem,
  } from './cloudSyncWorkbench';

  let {
    contextId,
    activeProject,
    activeSu = 'None',
    operationHeld = false,
    port = defaultCloudSyncPort,
    onBusyChange,
    oncontextswitched,
  }: {
    contextId: string;
    activeProject: string;
    activeSu?: string;
    operationHeld?: boolean;
    port?: CloudSyncPort;
    onBusyChange?: (busy: boolean) => void;
    oncontextswitched?: (state: unknown) => void;
  } = $props();

  let busy = $state(false);
  let error = $state<string | null>(null);
  let statusMessage = $state<string | null>(null);
  let generation = 0;
  function setBusy(next: boolean) {
    busy = next;
    onBusyChange?.(next);
  }

  let configStatus = $state.raw<CloudConfigStatus | null>(null);
  let connectionReport = $state.raw<CloudConnectionReport | null>(null);
  let selectedRoleMode = $state<CloudRoleMode>('contributor');
  let overrideHost = $state('');
  let overridePort = $state('5432');
  let overrideDatabase = $state('');
  let overrideSslMode = $state('require');
  let overrideUser = $state('');
  let overridePassword = $state('');
  let overrideAdminUser = $state('');
  let overrideAdminPassword = $state('');
  let pullStandardsResult = $state.raw<PullStandardsResult | null>(null);

  let subsetZonesRaw = $state('');
  let subsetSubzonesRaw = $state('');
  let subsetProjectIdsRaw = $state('');
  let subsetPlotNumbersRaw = $state('');
  let subsetBboxRaw = $state('');
  let subsetLimitRaw = $state('');
  let subsetAllowFull = $state(false);
  let subsetPreview = $state.raw<SubsetPreview | null>(null);
  let subsetTargetProject = $state('');
  let subsetDestinationPath = $state('');
  let subsetActivateOnSuccess = $state(true);
  let pullSubsetResult = $state.raw<PullSubsetResult | null>(null);

  let stagingUseActiveSu = $state(false);
  let stagingPreflight = $state.raw<StagingPreflightPreview | null>(null);
  let stagingSubmittedBy = $state('');
  let stagingSubmitterNotes = $state('');
  let stagingBaseSnapshotTag = $state('');
  let stagingCustodianOverride = $state(false);
  let submitStagingResult = $state.raw<SubmitStagingResult | null>(null);
  let submissions = $state.raw<StagingSubmissionSummary[]>([]);

  let bootstrapResult = $state.raw<SchemaBootstrapResult | null>(null);
  let auditChainLimit = $state(0);
  let auditChainResult = $state.raw<AuditChainVerification | null>(null);
  let publishStandardsResult = $state.raw<PublishStandardsResult | null>(null);
  let seedSourceDbPath = $state('');
  let seedBaselineResult = $state.raw<SeedBaselineResult | null>(null);
  let selectedSubmissionDetail = $state.raw<StagingSubmissionDetail | null>(null);
  let mergePreview = $state.raw<StagingMergePreview | null>(null);
  let mergePlotResolutions = $state<Record<string, CloudMergeResolution>>({});
  let mergeFieldResolutions = $state<Record<string, CloudMergeResolution>>({});
  let mergeReviewerNotes = $state('');
  let mergeExecuteResult = $state.raw<StagingMergeResult | null>(null);
  let snapshotTag = $state('');
  let snapshotExportFormat = $state('');
  let latestSnapshotCreated = $state.raw<SnapshotRecord | null>(null);
  let snapshots = $state.raw<SnapshotRecord[]>([]);
  let downloadLog = $state.raw<DownloadLogEntry[]>([]);

  let observedContextKey = '';
  $effect(() => {
    const key = `${contextId}::${activeProject}`;
    if (observedContextKey !== '' && observedContextKey !== key) {
      stagingPreflight = null;
      stagingCustodianOverride = false;
      submitStagingResult = null;
    }
    observedContextKey = key;
  });

  const activeRoleMode = $derived<CloudRoleMode>(
    connectionReport?.activeRoleMode ?? configStatus?.activeRoleMode ?? selectedRoleMode
  );
  const subsetTargetValidationError = $derived(
    subsetTargetProject === '' ? null : validateProjectNameInput(subsetTargetProject)
  );
  const snapshotTagValidationError = $derived(
    snapshotTag === '' ? null : validateSnapshotTagInput(snapshotTag)
  );
  const canUploadStaging = $derived(
    canUploadStagingSubmission(stagingPreflight, activeRoleMode, stagingCustodianOverride)
  );
  const combinedMergeItems = $derived.by<CloudMergeConflictItem[]>(() => {
    if (!mergePreview) return [];
    const seen = new Set<string>();
    const list: CloudMergeConflictItem[] = [];
    for (const item of [...(mergePreview.custodianProtectedDiffs ?? []), ...(mergePreview.conflicts ?? [])]) {
      if (!seen.has(item.conflictId)) {
        seen.add(item.conflictId);
        list.push(item);
      }
    }
    return list;
  });

  onMount(() => {
    const mountGen = generation;
    void port
      .getCloudSyncConfigStatus()
      .then(status => {
        if (mountGen !== generation || !status) return;
        configStatus = status;
        selectedRoleMode = status.activeRoleMode;
        if (status.port > 0) overridePort = String(status.port);
        if (status.database) overrideDatabase = status.database;
        if (status.sslMode) overrideSslMode = status.sslMode;
      })
      .catch(cause => {
        if (mountGen === generation) error = `Could not read local cloud sync configuration status: ${String(cause)}`;
      });
  });

  onDestroy(() => {
    generation++;
    onBusyChange?.(false);
  });

  async function runCloudOp(label: string, blockedAction: string, work: (isCurrent: () => boolean) => Promise<void>) {
    if (busy || operationHeld) {
      error = `Wait for the current operation or decision before ${blockedAction}.`;
      return;
    }
    const gen = ++generation;
    setBusy(true);
    error = null;
    statusMessage = null;
    try {
      await work(() => gen === generation);
    } catch (cause) {
      if (gen === generation) error = `${label} failed: ${String(cause)}`;
    } finally {
      if (gen === generation) setBusy(false);
    }
  }

  async function applySessionConfig(clearOverrides = false) {
    let parsedPort: number | undefined;
    if (!clearOverrides && overridePort.trim() !== '') {
      const p = Number(overridePort.trim());
      if (!Number.isInteger(p) || p < 1 || p > 65535) {
        error = 'Server port must be an integer between 1 and 65535.';
        return;
      }
      parsedPort = p;
    }
    const req = $state.snapshot(
      clearOverrides
        ? { roleMode: selectedRoleMode, clearOverrides: true }
        : {
            roleMode: selectedRoleMode,
            host: overrideHost.trim() || undefined,
            port: parsedPort,
            database: overrideDatabase.trim() || undefined,
            sslMode: overrideSslMode.trim() || undefined,
            user: overrideUser.trim() || undefined,
            password: overridePassword !== '' ? overridePassword : undefined,
            adminUser: overrideAdminUser.trim() || undefined,
            adminPassword: overrideAdminPassword !== '' ? overrideAdminPassword : undefined,
          }
    );
    await runCloudOp('Configure cloud session', 'changing cloud session settings', async isCurrent => {
      const status = await port.configureCloudSyncSession(req);
      if (!isCurrent()) return;
      overrideHost = '';
      overridePassword = '';
      overrideAdminPassword = '';
      if (clearOverrides) {
        overrideUser = '';
        overrideAdminUser = '';
      }
      configStatus = status;
      selectedRoleMode = status.activeRoleMode;
      if (connectionReport && connectionReport.activeRoleMode !== status.activeRoleMode) connectionReport = null;
      statusMessage = clearOverrides
        ? `Cleared session credential overrides (active role: ${status.activeRoleMode}).`
        : `Updated session cloud settings (${status.activeRoleMode} role; password inputs cleared).`;
    });
  }

  async function switchRoleAndConnect() {
    await runCloudOp('Cloud connection probe', 'probing cloud status', async isCurrent => {
      const currentRole = configStatus?.activeRoleMode ?? connectionReport?.activeRoleMode;
      if (currentRole !== selectedRoleMode) {
        const status = await port.configureCloudSyncSession($state.snapshot({ roleMode: selectedRoleMode }));
        if (!isCurrent()) return;
        configStatus = status;
      }
      const report = await port.testCloudConnection();
      if (!isCurrent()) return;
      connectionReport = report;
      selectedRoleMode = report.activeRoleMode;
      statusMessage = report.connected
        ? `Connected to ${report.database} as ${report.activeRoleMode} (${report.latencyMs} ms, ${report.becmasterPlotCount} BECMaster plots).`
        : 'Cloud connection probe completed: server reported not connected.';
    });
  }

  async function syncProvincialStandards() {
    await runCloudOp('Sync Provincial Standards', 'syncing provincial standards', async isCurrent => {
      const res = await port.pullCloudStandards(contextId);
      if (!isCurrent()) return;
      pullStandardsResult = res;
      statusMessage = res.alreadyCurrent
        ? `Provincial standards already current (Release ${res.releaseId}, BEC v${res.becVersion}, Taxa v${res.taxonomyVersion}).`
        : `Updated local provincial standards to Release ${res.releaseId} (BEC v${res.becVersion}, Taxa v${res.taxonomyVersion}).`;
      if (res.updated && res.state && oncontextswitched) oncontextswitched(res.state);
    });
  }

  function buildSubsetDraftOrError() {
    const built = buildSubsetFilterDraft({
      zonesRaw: subsetZonesRaw,
      subzonesRaw: subsetSubzonesRaw,
      projectIdsRaw: subsetProjectIdsRaw,
      plotNumbersRaw: subsetPlotNumbersRaw,
      bboxRaw: subsetBboxRaw,
      limitRaw: subsetLimitRaw,
      allowFullCheckout: subsetAllowFull,
    });
    if (built.error || !built.filter) {
      error = built.error ?? 'Invalid subset filter.';
      return null;
    }
    return built.filter;
  }

  async function runPreviewSubset() {
    const filter = buildSubsetDraftOrError();
    if (!filter) return;
    const filterPayload = $state.snapshot(filter);
    await runCloudOp('Preview BECMaster Subset', 'previewing BECMaster subset', async isCurrent => {
      const preview = await port.previewBECMasterSubset(filterPayload);
      if (!isCurrent()) return;
      subsetPreview = preview;
      statusMessage = `Subset preview matched ${preview.matchingPlots} plot(s) and ${preview.matchingVeg} vegetation row(s).`;
    });
  }

  async function runPullSubset() {
    const projErr = validateProjectNameInput(subsetTargetProject);
    if (projErr) {
      error = projErr;
      return;
    }
    const filter = buildSubsetDraftOrError();
    if (!filter) return;
    const req = $state.snapshot({
      filter,
      targetProject: subsetTargetProject,
      destinationPath: subsetDestinationPath.trim() || undefined,
      activateOnSuccess: subsetActivateOnSuccess,
    });
    await runCloudOp('Download Regional Subset', 'downloading BECMaster subset', async isCurrent => {
      const res = await port.pullBECMasterSubset(contextId, req);
      if (!isCurrent()) return;
      pullSubsetResult = res;
      statusMessage = `Checked out ${res.plotCount} plot(s) (${res.vegCount} veg rows) into "${res.targetProject}" at ${res.destinationPath}.`;
      if (res.activated && res.state && oncontextswitched) oncontextswitched(res.state);
    });
  }

  async function runStagingPreflight() {
    const useSu = $state.snapshot(stagingUseActiveSu);
    await runCloudOp('Staging pre-flight preview', 'running staging pre-flight', async isCurrent => {
      const preflight = await port.previewStagingSubmission(contextId, useSu);
      if (!isCurrent()) return;
      stagingPreflight = preflight;
      stagingCustodianOverride = false;
      statusMessage = preflight.compliancePassed
        ? `Pre-flight compliance passed for "${preflight.project}" (${preflight.plotCount} plots, ${preflight.userSpeciesManifest.rowCount} personal species).`
        : `Pre-flight detected ${preflight.blockingErrorCount} blocking compliance error(s) in "${preflight.project}".`;
    });
  }

  async function runSubmitToStaging() {
    if (!stagingPreflight) {
      error = 'Run Pre-Flight Compliance & Package Preview before uploading a staging bundle.';
      return;
    }
    if (!canUploadStagingSubmission(stagingPreflight, activeRoleMode, stagingCustodianOverride)) {
      error = 'Upload blocked: resolve pre-flight compliance errors before submitting to BECMaster staging.';
      return;
    }
    const req = $state.snapshot({
      useActiveSu: stagingUseActiveSu,
      submittedBy: stagingSubmittedBy.trim() || undefined,
      submitterNotes: stagingSubmitterNotes.trim() || undefined,
      baseSnapshotTag: stagingBaseSnapshotTag.trim() || undefined,
      custodianOverride: !stagingPreflight.compliancePassed && activeRoleMode === 'custodian' ? stagingCustodianOverride : undefined,
    });
    await runCloudOp('Upload Staging Bundle', 'uploading to staging', async isCurrent => {
      const res = await port.submitProjectToStaging(contextId, req);
      if (!isCurrent()) return;
      submitStagingResult = res;
      statusMessage = `Uploaded staging submission ${res.submissionId} for "${res.projectName}" (${res.plotCount} plots, status: ${res.status}).`;
    });
  }

  async function refreshSubmissionsList(filterOpts: { status?: string; submittedBy?: string } = {}) {
    const filter = $state.snapshot({
      status: filterOpts.status?.trim() || undefined,
      submittedBy: filterOpts.submittedBy?.trim() || undefined,
      limit: 50,
    });
    await runCloudOp('Refresh Submissions', 'refreshing staging submissions', async isCurrent => {
      const rows = await port.listStagingSubmissions(filter);
      if (!isCurrent()) return;
      submissions = rows ?? [];
      statusMessage = `Loaded ${submissions.length} staging submission(s).`;
    });
  }

  async function runBootstrapSchemas() {
    await runCloudOp('Bootstrap Cloud Schemas', 'bootstrapping cloud schemas', async isCurrent => {
      const res = await port.bootstrapCloudSchemas();
      if (!isCurrent()) return;
      bootstrapResult = res;
      statusMessage = `Verified cloud schemas v${res.schemaVersion} (${res.schemasVerified.join(', ')}).`;
    });
  }

  async function runVerifyAuditChain() {
    const parsedLimit = Number.isInteger(Number(auditChainLimit)) && Number(auditChainLimit) > 0 ? Number(auditChainLimit) : 0;
    await runCloudOp('Verify Audit Chain', 'verifying BECMaster audit hash chain', async isCurrent => {
      const res = await port.verifyBECMasterAuditChain(parsedLimit);
      if (!isCurrent()) return;
      auditChainResult = res;
      statusMessage = res.valid
        ? `BECMaster audit chain verified across ${res.verifiedRows} row(s) (tail ${res.tailHash ? res.tailHash.slice(0, 16) : 'empty'}).`
        : `BECMaster audit chain verification FAILED across ${res.verifiedRows} row(s).`;
    });
  }

  async function runPublishStandards(draft: PublishStandardsDraft = {}) {
    const req = $state.snapshot({
      releaseId: draft.releaseId?.trim() || undefined,
      becVersion: draft.becVersion?.trim() || '13',
      taxonomyVersion: draft.taxonomyVersion?.trim() || '19',
      vlistsPath: draft.vlistsPath?.trim() || undefined,
      becDbPath: draft.becDbPath?.trim() || undefined,
      vmetaDataPath: draft.vmetaDataPath?.trim() || undefined,
      notes: draft.notes?.trim() || undefined,
    });
    await runCloudOp('Publish Standards to Cloud', 'publishing provincial standards', async isCurrent => {
      const res = await port.publishStandardsToCloud(contextId, req);
      if (!isCurrent()) return;
      publishStandardsResult = res;
      statusMessage = `Published provincial standards release "${res.releaseId}" (BEC v${res.becVersion}, Taxonomy v${res.taxonomyVersion}) in ${res.elapsedMs} ms.`;
    });
  }

  async function runSeedBaseline(extras: SeedBaselineExtras = {}) {
    if (!seedSourceDbPath.trim()) {
      error = 'Source VPro project (.db) path is required to seed the BECMaster baseline.';
      return;
    }
    const req = $state.snapshot({
      sourceDbPath: seedSourceDbPath.trim(),
      sourceProject: extras.sourceProject?.trim() || undefined,
      snapshotTag: extras.snapshotTag?.trim() || undefined,
      replaceExisting: extras.replaceExisting ?? false,
      skipAudit: extras.skipAudit || undefined,
      notes: extras.notes?.trim() || undefined,
    });
    await runCloudOp('Seed BECMaster Baseline', 'seeding BECMaster baseline', async isCurrent => {
      const res = await port.seedBECMasterBaseline(req);
      if (!isCurrent()) return;
      seedBaselineResult = res;
      statusMessage = `Seeded BECMaster baseline from "${res.sourceProject}" (${res.plotCount} plots, ${res.vegCount} veg rows, snapshot ${res.snapshotTag}).`;
    });
  }

  async function inspectSubmission(submissionId: string) {
    const idSnap = $state.snapshot(submissionId);
    await runCloudOp('Inspect Submission Detail', 'inspecting submission details', async isCurrent => {
      const detail = await port.getStagingSubmissionDetail(idSnap);
      if (!isCurrent()) return;
      selectedSubmissionDetail = detail;
      statusMessage = `Loaded submission ${detail.summary.submissionId} (${detail.provisionalSpeciesDiffs.length} provisional species crosswalk item(s)).`;
    });
  }

  async function runPreviewStagingMerge(submissionId: string, baseDbPath = '') {
    const req = $state.snapshot({ submissionId, baseDbPath: baseDbPath.trim() || undefined });
    await runCloudOp('Preview Staging-to-Master Merge', 'previewing 3-way staging merge', async isCurrent => {
      const preview = await port.previewStagingToMasterMerge(req);
      if (!isCurrent()) return;
      mergePreview = preview;
      mergeExecuteResult = null;
      mergePlotResolutions = {};
      mergeFieldResolutions = buildInitialCloudMergeFieldResolutions(preview);
      statusMessage = `3-Way Merge preview for ${preview.submissionId}: ${preview.addedCount} Added, ${preview.fastForwardCount} Fast-Forward, ${preview.conflictCount} Conflict, ${preview.identicalCount} Identical.`;
    });
  }

  function setMergePlotResolution(plotNumber: string, value: string) {
    const next = { ...mergePlotResolutions };
    if (value === 'keep_target' || value === 'accept_source') next[plotNumber] = value;
    else delete next[plotNumber];
    mergePlotResolutions = next;
  }

  function setMergeFieldResolution(conflictId: string, choice: string) {
    const next = { ...mergeFieldResolutions };
    if (choice === 'keep_target' || choice === 'accept_source') next[conflictId] = choice;
    else delete next[conflictId];
    mergeFieldResolutions = next;
  }

  async function runExecuteStagingMerge(opts: { baseDbPath?: string; defaultConflictResolution?: CloudMergeResolution; actor?: string } = {}) {
    if (!mergePreview) {
      error = 'Run Review & 3-Way Diff vs BECMaster before approving merge.';
      return;
    }
    const req = $state.snapshot({
      submissionId: mergePreview.submissionId,
      baseDbPath: mergePreview.baseDbPath || opts.baseDbPath?.trim() || undefined,
      baseProject: mergePreview.baseProject || undefined,
      expectedPreviewDigest: mergePreview.previewDigest,
      defaultConflictResolution: opts.defaultConflictResolution ?? 'keep_target',
      plotResolutions: mergePlotResolutions,
      fieldResolutions: mergeFieldResolutions,
      reviewerNotes: mergeReviewerNotes.trim() || undefined,
      actor: opts.actor?.trim() || undefined,
    });
    await runCloudOp('Approve & Merge into BECMaster', 'executing BECMaster merge', async isCurrent => {
      const res = await port.executeStagingToMasterMerge(req);
      if (!isCurrent()) return;
      mergeExecuteResult = res;
      mergePreview = null;
      statusMessage = `Merged submission ${res.submissionId} (tx ${res.mergeTxId}): +${res.addedPlots} added, ${res.updatedPlots} updated, ${res.auditRowsWritten} audit row(s).`;
    });
  }

  async function runRejectSubmission(submissionId?: string, actor?: string) {
    const targetId = submissionId ?? mergePreview?.submissionId ?? selectedSubmissionDetail?.summary.submissionId;
    if (!targetId) {
      error = 'Select a staging submission before rejecting.';
      return;
    }
    if (!mergeReviewerNotes.trim()) {
      error = 'Reviewer notes are required when rejecting a staging submission.';
      return;
    }
    const req = $state.snapshot({ submissionId: targetId, reviewerNotes: mergeReviewerNotes.trim(), actor: actor?.trim() || undefined });
    await runCloudOp('Reject Staging Submission', 'rejecting a staging submission', async isCurrent => {
      const summary = await port.rejectStagingSubmission(req);
      if (!isCurrent()) return;
      submissions = submissions.map(s => (s.submissionId === summary.submissionId ? summary : s));
      if (mergePreview?.submissionId === summary.submissionId) mergePreview = null;
      statusMessage = `Rejected submission ${summary.submissionId} (status: ${summary.status}).`;
    });
  }

  async function runCreateSnapshot(extras: { destinationPath?: string; zoneFilter?: string; notes?: string } = {}) {
    const tagErr = validateSnapshotTagInput(snapshotTag);
    if (tagErr) {
      error = tagErr;
      return;
    }
    const req = $state.snapshot({
      snapshotTag,
      notes: extras.notes?.trim() || undefined,
      exportFormat: snapshotExportFormat || undefined,
      destinationPath: extras.destinationPath?.trim() || undefined,
      zoneFilter: extras.zoneFilter?.trim() || undefined,
    });
    await runCloudOp('Create BECMaster Snapshot', 'cutting a BECMaster snapshot', async isCurrent => {
      const rec = await port.createBECMasterSnapshot(contextId, req);
      if (!isCurrent()) return;
      latestSnapshotCreated = rec;
      snapshots = [rec, ...snapshots.filter(s => s.snapshotTag !== rec.snapshotTag)];
      statusMessage = `Created BECMaster snapshot "${rec.snapshotTag}" (${rec.plotCount} plots, ${rec.vegCount} veg rows).`;
    });
  }

  async function refreshSnapshotsAndLedger() {
    await runCloudOp('Load Snapshots & Download Log', 'loading snapshots and download log', async isCurrent => {
      const [snapRows, logRows] = await Promise.all([
        port.listBECMasterSnapshots(),
        port.listBECMasterDownloadLog(50),
      ]);
      if (!isCurrent()) return;
      snapshots = snapRows ?? [];
      downloadLog = logRows ?? [];
      statusMessage = `Loaded ${snapshots.length} snapshot(s) and ${downloadLog.length} download log record(s).`;
    });
  }
</script>

<div class="min-w-0 space-y-5 text-[#313132]" data-cloud-sync-workbench aria-label="Cloud BECMaster Sync Workbench">
  <CloudSyncAuthPanel
    {busy} {operationHeld} {activeRoleMode} {configStatus} {connectionReport} {pullStandardsResult}
    bind:selectedRoleMode bind:overrideHost bind:overridePort bind:overrideDatabase bind:overrideSslMode
    bind:overrideUser bind:overridePassword bind:overrideAdminUser bind:overrideAdminPassword
    onSwitchRoleAndConnect={switchRoleAndConnect} onSyncProvincialStandards={syncProvincialStandards} onApplySessionConfig={applySessionConfig}
  />

  {#if error}
    <p role="alert" class="rounded border-l-4 border-red-700 bg-red-50 p-3 text-sm text-red-900">{error}</p>
  {/if}
  {#if statusMessage}
    <p role="status" class="rounded border-l-4 border-[#003366] bg-slate-50 p-3 text-sm text-slate-900">{statusMessage}</p>
  {/if}

  <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
    <CloudSyncPullPanel
      {busy} {operationHeld}
      bind:subsetZonesRaw bind:subsetSubzonesRaw bind:subsetProjectIdsRaw bind:subsetPlotNumbersRaw
      bind:subsetBboxRaw bind:subsetLimitRaw bind:subsetAllowFull {subsetPreview}
      bind:subsetTargetProject bind:subsetDestinationPath bind:subsetActivateOnSuccess
      {subsetTargetValidationError} {pullSubsetResult} onPreviewSubset={runPreviewSubset} onPullSubset={runPullSubset}
    />
    <CloudSyncStagingPanel
      {busy} {operationHeld} {activeProject} {activeSu} {activeRoleMode}
      bind:stagingUseActiveSu {stagingPreflight} bind:stagingSubmittedBy bind:stagingSubmitterNotes
      bind:stagingBaseSnapshotTag bind:stagingCustodianOverride {canUploadStaging} {submitStagingResult} {submissions}
      onRunStagingPreflight={runStagingPreflight} onRunSubmitToStaging={runSubmitToStaging} onRefreshSubmissionsList={() => refreshSubmissionsList()}
    />
  </div>

  {#if activeRoleMode === 'custodian'}
    <section class="space-y-4 rounded border border-slate-300 bg-white p-4 shadow-sm" data-custodian-panel aria-label="Custodian Inbox, 3-Way Merge, Standards and Snapshots">
      <header class="flex flex-wrap items-center justify-between gap-2 border-b-[3px] border-b-[#FCBA19] bg-[#003366] px-4 py-3 text-white">
        <div>
          <p class="text-xs font-semibold uppercase tracking-wider text-[#FCBA19]">Custodian Governance Console</p>
          <h3 class="m-0 text-base font-semibold text-white">Schema Bootstrap, 2026 Standards Publishing, Staging 3-Way Merge &amp; Dated Snapshots</h3>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <label class="flex items-center gap-1.5 text-[11px] text-white/90" for="cloud-audit-limit">
            Audit Limit (0 = all)
            <input id="cloud-audit-limit" type="number" min="0" class="w-20 rounded border border-white/40 bg-white px-2 py-1 text-xs font-mono text-[#313132]" bind:value={auditChainLimit} disabled={busy || operationHeld} />
          </label>
          <button type="button" data-verify-audit-chain disabled={busy || operationHeld} class="rounded border border-[#FCBA19] bg-[#002244] px-3 py-1.5 text-xs font-semibold text-white hover:bg-[#1A5A96] disabled:opacity-50" onclick={runVerifyAuditChain}>
            Verify Audit Chain
          </button>
          <button type="button" disabled={busy || operationHeld} class="rounded bg-[#FCBA19] px-3 py-1.5 text-xs font-bold text-[#003366] hover:bg-[#FEF6E0] disabled:opacity-50" onclick={runBootstrapSchemas}>
            Bootstrap / Verify Schemas
          </button>
        </div>
      </header>

      <CloudSyncCustodianStandardsPanel
        {busy} {operationHeld} {auditChainResult} {bootstrapResult} {publishStandardsResult}
        bind:seedSourceDbPath {seedBaselineResult} onPublishStandards={runPublishStandards} onSeedBaseline={runSeedBaseline}
      />

      <CloudSyncCustodianMergePanel
        {busy} {operationHeld} {submissions} {selectedSubmissionDetail} {mergePreview} {combinedMergeItems}
        {mergePlotResolutions} {mergeFieldResolutions} bind:mergeReviewerNotes {mergeExecuteResult}
        onRefreshSubmissions={refreshSubmissionsList} onInspectSubmission={inspectSubmission} onPreviewMerge={runPreviewStagingMerge}
        onSetPlotResolution={setMergePlotResolution} onSetFieldResolution={setMergeFieldResolution}
        onExecuteMerge={runExecuteStagingMerge} onRejectSubmission={actor => runRejectSubmission(undefined, actor)}
      />

      <CloudSyncSnapshotsPanel
        {busy} {operationHeld} bind:snapshotTag bind:snapshotExportFormat {snapshotTagValidationError}
        {latestSnapshotCreated} {snapshots} {downloadLog} onCreateSnapshot={runCreateSnapshot} onRefreshSnapshots={refreshSnapshotsAndLedger}
      />
    </section>
  {:else}
    <div class="rounded border border-slate-200 bg-slate-50 px-4 py-3 text-xs text-slate-700">
      Custodian Admin tools (Schema Bootstrap, 2026 Standards Publishing, Staging Inbox 3-Way Merge, and Dated Snapshots) appear when the active session role is switched to <span class="font-semibold text-[#003366]">Custodian Admin</span>.
    </div>
  {/if}
</div>
