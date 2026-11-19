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
    parseSessionPortInput,
    parseAuditChainLimitInput,
    formatAuditChainStatusMessage,
    getRememberedSessionOverrides,
    setRememberedSessionOverrides,
    clearRememberedSessionOverrides,
    buildSubsetFilterDraft,
    canUploadStagingSubmission,
    buildInitialCloudMergeFieldResolutions,
    validateSnapshotTagInput,
    redactCloudSecrets,
    formatCloudSyncError,
    notifications,
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
  let overridePort = $state<string | number | null | undefined>('5432');
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
  let subsetLimitRaw = $state<string | number | null | undefined>('');
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
  let auditChainLimit = $state<string | number | null | undefined>(0);
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

  function sanitizeCloudText(raw: string, extraSecrets: readonly string[] = []): string {
    return redactCloudSecrets(raw, [overridePassword, overrideAdminPassword, ...extraSecrets]);
  }

  function notifyCloud(
    severity: 'success' | 'info' | 'warning' | 'error',
    title: string,
    message: string,
    extraSecrets: readonly string[] = [],
    toast = true,
  ) {
    const safeTitle = sanitizeCloudText(title, extraSecrets);
    const safeMessage = sanitizeCloudText(message, extraSecrets);
    if (typeof notifications === 'undefined') return;
    const opts = {
      category: 'background' as const,
      source: 'BECMaster Cloud Sync',
      contextTag: activeProject || undefined,
      toast,
    };
    if (severity === 'success') notifications.success(safeTitle, safeMessage, opts);
    else if (severity === 'warning') notifications.warning(safeTitle, safeMessage, opts);
    else if (severity === 'error') notifications.error(safeTitle, safeMessage, opts);
    else notifications.info(safeTitle, safeMessage, opts);
  }

  onMount(() => {
    const mountGen = generation;
    void port
      .getCloudSyncConfigStatus()
      .then(status => {
        if (mountGen !== generation || !status) return;
        configStatus = status;
        selectedRoleMode = status.activeRoleMode;
        if (status.sessionOverride) {
          const remembered = getRememberedSessionOverrides();
          if (remembered) {
            overrideHost = remembered.host;
            overridePort = remembered.port !== '' ? remembered.port : status.port > 0 ? String(status.port) : '5432';
            overrideDatabase = remembered.database !== '' ? remembered.database : status.database || '';
            overrideSslMode = remembered.sslMode !== '' ? remembered.sslMode : status.sslMode || 'require';
            overrideUser = remembered.user;
            overrideAdminUser = remembered.adminUser;
            return;
          }
        } else {
          clearRememberedSessionOverrides();
        }
        if (status.port > 0) overridePort = String(status.port);
        if (status.database) overrideDatabase = status.database;
        if (status.sslMode) overrideSslMode = status.sslMode;
      })
      .catch(cause => {
        if (mountGen === generation) {
          const detail = formatCloudSyncError(cause, [overridePassword, overrideAdminPassword]);
          error = sanitizeCloudText(`Could not read local cloud sync configuration status: ${detail}`);
          notifyCloud('error', 'Cloud config status unavailable', error);
        }
      });
  });

  onDestroy(() => {
    generation++;
    onBusyChange?.(false);
  });

  async function runCloudOp(label: string, blockedAction: string, work: (isCurrent: () => boolean, capturedSecrets: readonly string[]) => Promise<void>) {
    const capturedSecrets = [overridePassword, overrideAdminPassword];
    if (busy || operationHeld) {
      error = `Wait for the current operation or decision before ${blockedAction}.`;
      notifyCloud('error', 'Cloud sync action held', error, capturedSecrets);
      return;
    }
    const gen = ++generation;
    setBusy(true);
    error = null;
    statusMessage = null;
    try {
      await work(() => gen === generation, capturedSecrets);
    } catch (cause) {
      if (gen === generation) {
        const detail = formatCloudSyncError(cause, capturedSecrets);
        error = sanitizeCloudText(`${label} failed: ${detail}`, capturedSecrets);
        notifyCloud('error', `${label} failed`, error, capturedSecrets);
      }
    } finally {
      if (gen === generation) setBusy(false);
    }
  }

  async function applySessionConfig(clearOverrides = false) {
    let parsedPort: number | undefined;
    if (!clearOverrides) {
      const portParsed = parseSessionPortInput(overridePort);
      if (portParsed.error) {
        error = portParsed.error;
        notifyCloud('error', 'Invalid cloud server port', error);
        return;
      }
      parsedPort = portParsed.port;
    }
    const trimmedHost = overrideHost.trim();
    const trimmedDb = overrideDatabase.trim();
    const trimmedSsl = overrideSslMode.trim();
    const trimmedUser = overrideUser.trim();
    const trimmedAdminUser = overrideAdminUser.trim();
    const req = $state.snapshot(
      clearOverrides
        ? { roleMode: selectedRoleMode, clearOverrides: true }
        : {
            roleMode: selectedRoleMode,
            host: trimmedHost || undefined,
            port: parsedPort,
            database: trimmedDb || undefined,
            sslMode: trimmedSsl || undefined,
            user: trimmedUser || undefined,
            password: overridePassword !== '' ? overridePassword : undefined,
            adminUser: trimmedAdminUser || undefined,
            adminPassword: overrideAdminPassword !== '' ? overrideAdminPassword : undefined,
          }
    );
    await runCloudOp('Configure cloud session', 'changing cloud session settings', async (isCurrent, capturedSecrets) => {
      const prevRemembered = getRememberedSessionOverrides();
      const status = await port.configureCloudSyncSession(req);
      if (!isCurrent()) return;
      overridePassword = '';
      overrideAdminPassword = '';
      if (clearOverrides) {
        clearRememberedSessionOverrides();
        overrideHost = '';
        overrideUser = '';
        overrideAdminUser = '';
        overridePort = status.port > 0 ? String(status.port) : '5432';
        overrideDatabase = status.database || '';
        overrideSslMode = status.sslMode || 'require';
      } else {
        // Preserve non-secret session override inputs (and surface any still-active backend override if left blank).
        overrideHost = trimmedHost || (status.sessionOverride ? prevRemembered?.host ?? '' : '');
        overrideDatabase = trimmedDb || status.database || '';
        overrideSslMode = trimmedSsl || status.sslMode || 'require';
        overrideUser = trimmedUser || (status.sessionOverride ? prevRemembered?.user ?? '' : '');
        overrideAdminUser = trimmedAdminUser || (status.sessionOverride ? prevRemembered?.adminUser ?? '' : '');
        if (status.sessionOverride) {
          setRememberedSessionOverrides({
            host: overrideHost,
            port: parsedPort !== undefined ? String(parsedPort) : prevRemembered?.port ?? '',
            database: overrideDatabase,
            sslMode: overrideSslMode,
            user: overrideUser,
            adminUser: overrideAdminUser,
          });
        } else {
          clearRememberedSessionOverrides();
        }
      }
      configStatus = status;
      selectedRoleMode = status.activeRoleMode;
      connectionReport = null;
      statusMessage = sanitizeCloudText(
        clearOverrides
          ? `Cleared session credential overrides (active role: ${status.activeRoleMode}).`
          : `Updated session cloud settings (${status.activeRoleMode} role; password inputs cleared).`,
        capturedSecrets,
      );
      notifyCloud('success', 'Cloud session configured', statusMessage, capturedSecrets);
    });
  }

  async function switchRoleAndConnect() {
    await runCloudOp('Cloud connection probe', 'probing cloud status', async (isCurrent, capturedSecrets) => {
      try {
        const currentRole = configStatus?.activeRoleMode ?? connectionReport?.activeRoleMode;
        if (currentRole !== selectedRoleMode) {
          const status = await port.configureCloudSyncSession($state.snapshot({ roleMode: selectedRoleMode }));
          if (!isCurrent()) return;
          configStatus = status;
          connectionReport = null;
        }
        const report = await port.testCloudConnection();
        if (!isCurrent()) return;
        if (report.connected) {
          connectionReport = report;
          selectedRoleMode = report.activeRoleMode;
        } else {
          connectionReport = null;
          if (report.activeRoleMode) selectedRoleMode = report.activeRoleMode;
        }
        statusMessage = sanitizeCloudText(
          report.connected
            ? `Connected to ${report.database} as ${report.activeRoleMode} (${report.latencyMs} ms, ${report.becmasterPlotCount} BECMaster plots).`
            : 'Cloud connection probe completed: server reported not connected.',
          capturedSecrets,
        );
        notifyCloud(
          report.connected ? 'success' : 'warning',
          report.connected ? `Connected to ${report.database}` : 'Cloud server not connected',
          statusMessage,
          capturedSecrets,
        );
      } catch (cause) {
        if (isCurrent()) {
          connectionReport = null;
        }
        throw cause;
      }
    });
  }

  async function syncProvincialStandards() {
    await runCloudOp('Sync Provincial Standards', 'syncing provincial standards', async (isCurrent, capturedSecrets) => {
      const res = await port.pullCloudStandards(contextId);
      if (!isCurrent()) return;
      pullStandardsResult = res;
      statusMessage = sanitizeCloudText(
        res.alreadyCurrent
          ? `Provincial standards already current (Release ${res.releaseId}, BEC v${res.becVersion}, Taxa v${res.taxonomyVersion}).`
          : `Updated local provincial standards to Release ${res.releaseId} (BEC v${res.becVersion}, Taxa v${res.taxonomyVersion}).`,
        capturedSecrets,
      );
      notifyCloud(
        res.updated ? 'success' : 'info',
        res.updated ? 'Provincial standards updated' : 'Provincial standards current',
        statusMessage,
        capturedSecrets,
      );
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
      error = sanitizeCloudText(built.error ?? 'Invalid subset filter.');
      notifyCloud('error', 'Invalid subset filter', error);
      return null;
    }
    return built.filter;
  }

  async function runPreviewSubset() {
    const filter = buildSubsetDraftOrError();
    if (!filter) return;
    const filterPayload = $state.snapshot(filter);
    await runCloudOp('Preview BECMaster Subset', 'previewing BECMaster subset', async (isCurrent, capturedSecrets) => {
      const preview = await port.previewBECMasterSubset(filterPayload);
      if (!isCurrent()) return;
      subsetPreview = preview;
      statusMessage = sanitizeCloudText(
        `Subset preview matched ${preview.matchingPlots} plot(s) and ${preview.matchingVeg} vegetation row(s).`,
        capturedSecrets,
      );
      notifyCloud('info', 'BECMaster subset preview ready', statusMessage, capturedSecrets);
    });
  }

  async function runPullSubset() {
    const projErr = validateProjectNameInput(subsetTargetProject);
    if (projErr) {
      error = sanitizeCloudText(projErr);
      notifyCloud('error', 'Invalid subset target project', error);
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
    await runCloudOp('Download Regional Subset', 'downloading BECMaster subset', async (isCurrent, capturedSecrets) => {
      const res = await port.pullBECMasterSubset(contextId, req);
      if (!isCurrent()) return;
      pullSubsetResult = res;
      statusMessage = sanitizeCloudText(
        `Checked out ${res.plotCount} plot(s) (${res.vegCount} veg rows) into "${res.targetProject}" at ${res.destinationPath}.`,
        capturedSecrets,
      );
      notifyCloud('success', `Checked out "${res.targetProject}"`, statusMessage, capturedSecrets);
      if (res.activated && res.state && oncontextswitched) oncontextswitched(res.state);
    });
  }

  async function runStagingPreflight() {
    const useSu = $state.snapshot(stagingUseActiveSu);
    await runCloudOp('Staging pre-flight preview', 'running staging pre-flight', async (isCurrent, capturedSecrets) => {
      const preflight = await port.previewStagingSubmission(contextId, useSu);
      if (!isCurrent()) return;
      stagingPreflight = preflight;
      stagingCustodianOverride = false;
      statusMessage = sanitizeCloudText(
        preflight.compliancePassed
          ? `Pre-flight compliance passed for "${preflight.project}" (${preflight.plotCount} plots, ${preflight.userSpeciesManifest.rowCount} personal species).`
          : `Pre-flight detected ${preflight.blockingErrorCount} blocking compliance error(s) in "${preflight.project}".`,
        capturedSecrets,
      );
      notifyCloud(
        preflight.compliancePassed ? 'success' : 'warning',
        preflight.compliancePassed ? 'Staging pre-flight passed' : 'Staging pre-flight blocked',
        statusMessage,
        capturedSecrets,
      );
    });
  }

  async function runSubmitToStaging() {
    if (!stagingPreflight) {
      error = 'Run Pre-Flight Compliance & Package Preview before uploading a staging bundle.';
      notifyCloud('error', 'Staging pre-flight required', error);
      return;
    }
    if (!canUploadStagingSubmission(stagingPreflight, activeRoleMode, stagingCustodianOverride)) {
      error = 'Upload blocked: resolve pre-flight compliance errors before submitting to BECMaster staging.';
      notifyCloud('error', 'Staging upload blocked', error);
      return;
    }
    const req = $state.snapshot({
      useActiveSu: stagingUseActiveSu,
      submittedBy: stagingSubmittedBy.trim() || undefined,
      submitterNotes: stagingSubmitterNotes.trim() || undefined,
      baseSnapshotTag: stagingBaseSnapshotTag.trim() || undefined,
      custodianOverride: !stagingPreflight.compliancePassed && activeRoleMode === 'custodian' ? stagingCustodianOverride : undefined,
    });
    await runCloudOp('Upload Staging Bundle', 'uploading to staging', async (isCurrent, capturedSecrets) => {
      const res = await port.submitProjectToStaging(contextId, req);
      if (!isCurrent()) return;
      submitStagingResult = res;
      statusMessage = sanitizeCloudText(
        `Uploaded staging submission ${res.submissionId} for "${res.projectName}" (${res.plotCount} plots, status: ${res.status}).`,
        capturedSecrets,
      );
      notifyCloud('success', `Uploaded staging submission ${res.submissionId}`, statusMessage, capturedSecrets);
    });
  }

  async function refreshSubmissionsList(filterOpts: { status?: string; submittedBy?: string } = {}) {
    const filter = $state.snapshot({
      status: filterOpts.status?.trim() || undefined,
      submittedBy: filterOpts.submittedBy?.trim() || undefined,
      limit: 50,
    });
    await runCloudOp('Refresh Submissions', 'refreshing staging submissions', async (isCurrent, capturedSecrets) => {
      const rows = await port.listStagingSubmissions(filter);
      if (!isCurrent()) return;
      submissions = rows ?? [];
      statusMessage = sanitizeCloudText(`Loaded ${submissions.length} staging submission(s).`, capturedSecrets);
      notifyCloud('info', 'Staging submissions refreshed', statusMessage, capturedSecrets);
    });
  }

  async function runBootstrapSchemas() {
    await runCloudOp('Bootstrap Cloud Schemas', 'bootstrapping cloud schemas', async (isCurrent, capturedSecrets) => {
      const res = await port.bootstrapCloudSchemas();
      if (!isCurrent()) return;
      bootstrapResult = res;
      statusMessage = sanitizeCloudText(`Verified cloud schemas v${res.schemaVersion} (${res.schemasVerified.join(', ')}).`, capturedSecrets);
      notifyCloud('success', 'Cloud schemas verified', statusMessage, capturedSecrets);
    });
  }

  async function runVerifyAuditChain() {
    const limitParsed = parseAuditChainLimitInput(auditChainLimit);
    if (limitParsed.error) {
      error = limitParsed.error;
      notifyCloud('error', 'Invalid audit limit', error);
      return;
    }
    const parsedLimit = limitParsed.limit;
    await runCloudOp('Verify Audit Chain', 'verifying BECMaster audit hash chain', async (isCurrent, capturedSecrets) => {
      try {
        const res = await port.verifyBECMasterAuditChain(parsedLimit);
        if (!isCurrent()) return;
        auditChainResult = res;
        statusMessage = sanitizeCloudText(formatAuditChainStatusMessage(res), capturedSecrets);
        notifyCloud(
          res.valid ? 'success' : 'error',
          res.valid ? 'BECMaster audit chain verified' : 'BECMaster audit chain verification failed',
          statusMessage,
          capturedSecrets,
        );
      } catch (cause) {
        if (isCurrent()) {
          auditChainResult = null;
        }
        throw cause;
      }
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
    await runCloudOp('Publish Standards to Cloud', 'publishing provincial standards', async (isCurrent, capturedSecrets) => {
      const res = await port.publishStandardsToCloud(contextId, req);
      if (!isCurrent()) return;
      publishStandardsResult = res;
      statusMessage = sanitizeCloudText(
        `Published provincial standards release "${res.releaseId}" (BEC v${res.becVersion}, Taxonomy v${res.taxonomyVersion}) in ${res.elapsedMs} ms.`,
        capturedSecrets,
      );
      notifyCloud('success', `Published standards ${res.releaseId}`, statusMessage, capturedSecrets);
    });
  }

  async function runSeedBaseline(extras: SeedBaselineExtras = {}) {
    if (!seedSourceDbPath.trim()) {
      error = 'Source VPro project (.db) path is required to seed the BECMaster baseline.';
      notifyCloud('error', 'Baseline source path required', error);
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
    await runCloudOp('Seed BECMaster Baseline', 'seeding BECMaster baseline', async (isCurrent, capturedSecrets) => {
      const res = await port.seedBECMasterBaseline(req);
      if (!isCurrent()) return;
      seedBaselineResult = res;
      statusMessage = sanitizeCloudText(
        `Seeded BECMaster baseline from "${res.sourceProject}" (${res.plotCount} plots, ${res.vegCount} veg rows, snapshot ${res.snapshotTag}).`,
        capturedSecrets,
      );
      notifyCloud('success', 'BECMaster baseline seeded', statusMessage, capturedSecrets);
    });
  }

  async function inspectSubmission(submissionId: string) {
    const idSnap = $state.snapshot(submissionId);
    await runCloudOp('Inspect Submission Detail', 'inspecting submission details', async (isCurrent, capturedSecrets) => {
      const detail = await port.getStagingSubmissionDetail(idSnap);
      if (!isCurrent()) return;
      selectedSubmissionDetail = detail;
      statusMessage = sanitizeCloudText(
        `Loaded submission ${detail.summary.submissionId} (${detail.provisionalSpeciesDiffs.length} provisional species crosswalk item(s)).`,
        capturedSecrets,
      );
      notifyCloud('info', `Loaded submission ${detail.summary.submissionId}`, statusMessage, capturedSecrets);
    });
  }

  async function runPreviewStagingMerge(submissionId: string, baseDbPath = '') {
    const req = $state.snapshot({ submissionId, baseDbPath: baseDbPath.trim() || undefined });
    await runCloudOp('Preview Staging-to-Master Merge', 'previewing 3-way staging merge', async (isCurrent, capturedSecrets) => {
      const preview = await port.previewStagingToMasterMerge(req);
      if (!isCurrent()) return;
      mergePreview = preview;
      mergeExecuteResult = null;
      mergePlotResolutions = {};
      mergeFieldResolutions = buildInitialCloudMergeFieldResolutions(preview);
      statusMessage = sanitizeCloudText(
        `3-Way Merge preview for ${preview.submissionId}: ${preview.addedCount} Added, ${preview.fastForwardCount} Fast-Forward, ${preview.conflictCount} Conflict, ${preview.identicalCount} Identical.`,
        capturedSecrets,
      );
      notifyCloud('info', `Merge preview ready (${preview.submissionId})`, statusMessage, capturedSecrets);
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
      notifyCloud('error', 'Merge preview required', error);
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
    await runCloudOp('Approve & Merge into BECMaster', 'executing BECMaster merge', async (isCurrent, capturedSecrets) => {
      const res = await port.executeStagingToMasterMerge(req);
      if (!isCurrent()) return;
      mergeExecuteResult = res;
      mergePreview = null;
      statusMessage = sanitizeCloudText(
        `Merged submission ${res.submissionId} (tx ${res.mergeTxId}): +${res.addedPlots} added, ${res.updatedPlots} updated, ${res.auditRowsWritten} audit row(s).`,
        capturedSecrets,
      );
      notifyCloud('success', `Merged submission ${res.submissionId}`, statusMessage, capturedSecrets);
    });
  }

  async function runRejectSubmission(submissionId?: string, actor?: string) {
    const targetId = submissionId ?? mergePreview?.submissionId ?? selectedSubmissionDetail?.summary.submissionId;
    if (!targetId) {
      error = 'Select a staging submission before rejecting.';
      notifyCloud('error', 'Submission selection required', error);
      return;
    }
    if (!mergeReviewerNotes.trim()) {
      error = 'Reviewer notes are required when rejecting a staging submission.';
      notifyCloud('error', 'Reviewer notes required', error);
      return;
    }
    const req = $state.snapshot({ submissionId: targetId, reviewerNotes: mergeReviewerNotes.trim(), actor: actor?.trim() || undefined });
    await runCloudOp('Reject Staging Submission', 'rejecting a staging submission', async (isCurrent, capturedSecrets) => {
      const summary = await port.rejectStagingSubmission(req);
      if (!isCurrent()) return;
      submissions = submissions.map(s => (s.submissionId === summary.submissionId ? summary : s));
      if (mergePreview?.submissionId === summary.submissionId) mergePreview = null;
      statusMessage = sanitizeCloudText(`Rejected submission ${summary.submissionId} (status: ${summary.status}).`, capturedSecrets);
      notifyCloud('success', `Rejected submission ${summary.submissionId}`, statusMessage, capturedSecrets);
    });
  }

  async function runCreateSnapshot(extras: { destinationPath?: string; zoneFilter?: string; notes?: string } = {}) {
    const tagErr = validateSnapshotTagInput(snapshotTag);
    if (tagErr) {
      error = sanitizeCloudText(tagErr);
      notifyCloud('error', 'Invalid snapshot tag', error);
      return;
    }
    const req = $state.snapshot({
      snapshotTag,
      notes: extras.notes?.trim() || undefined,
      exportFormat: snapshotExportFormat || undefined,
      destinationPath: extras.destinationPath?.trim() || undefined,
      zoneFilter: extras.zoneFilter?.trim() || undefined,
    });
    await runCloudOp('Create BECMaster Snapshot', 'cutting a BECMaster snapshot', async (isCurrent, capturedSecrets) => {
      const rec = await port.createBECMasterSnapshot(contextId, req);
      if (!isCurrent()) return;
      latestSnapshotCreated = rec;
      snapshots = [rec, ...snapshots.filter(s => s.snapshotTag !== rec.snapshotTag)];
      statusMessage = sanitizeCloudText(
        `Created BECMaster snapshot "${rec.snapshotTag}" (${rec.plotCount} plots, ${rec.vegCount} veg rows).`,
        capturedSecrets,
      );
      notifyCloud('success', `Created snapshot "${rec.snapshotTag}"`, statusMessage, capturedSecrets);
    });
  }

  async function refreshSnapshotsAndLedger() {
    await runCloudOp('Load Snapshots & Download Log', 'loading snapshots and download log', async (isCurrent, capturedSecrets) => {
      const [snapRows, logRows] = await Promise.all([
        port.listBECMasterSnapshots(),
        port.listBECMasterDownloadLog(50),
      ]);
      if (!isCurrent()) return;
      snapshots = snapRows ?? [];
      downloadLog = logRows ?? [];
      statusMessage = sanitizeCloudText(
        `Loaded ${snapshots.length} snapshot(s) and ${downloadLog.length} download log record(s).`,
        capturedSecrets,
      );
      notifyCloud('info', 'Snapshots & download log loaded', statusMessage, capturedSecrets);
    });
  }
</script>

<div class="min-w-0 space-y-5 text-vpro-ink" data-cloud-sync-workbench aria-label="Cloud BECMaster Sync Workbench">
  <div
    data-workbench-sticky-bar
    class="sticky top-0 z-20 flex flex-wrap items-center justify-between gap-2 rounded-t border-b border-vpro-border bg-white/95 px-3 py-2 backdrop-blur-xs"
  >
    <div class="flex flex-wrap items-center gap-2 text-xs text-vpro-ink">
      <span class="font-semibold text-vpro-navy">BECMaster Cloud Sync</span>
      <span class="rounded bg-vpro-canvas px-2 py-0.5 font-mono text-[11px] text-vpro-navy">
        {activeRoleMode === 'custodian' ? 'Custodian Admin' : 'Contributor'}
      </span>
      <span class="text-vpro-ink-secondary">
        {connectionReport?.connected ? `Connected (${connectionReport.database})` : 'Offline / Unprobed'}
      </span>
      {#if activeProject}
        <span class="rounded bg-vpro-canvas px-2 py-0.5 font-mono text-[11px] text-vpro-ink-secondary">Project: {activeProject}</span>
      {/if}
    </div>
    <div class="flex flex-wrap items-center gap-2">
      <button
        type="button"
        disabled={busy || operationHeld}
        class="rounded bg-vpro-navy px-2.5 py-1 text-xs font-semibold text-white hover:bg-vpro-navy-dark disabled:opacity-50"
        onclick={switchRoleAndConnect}
      >
        Test Connection
      </button>
      <button
        type="button"
        disabled={busy || operationHeld}
        class="rounded border border-vpro-navy bg-white px-2.5 py-1 text-xs font-semibold text-vpro-navy hover:bg-vpro-surface-subtle disabled:opacity-50"
        onclick={syncProvincialStandards}
      >
        Sync Standards
      </button>
    </div>
  </div>

  <CloudSyncAuthPanel
    {busy} {operationHeld} {activeRoleMode} {configStatus} {connectionReport} {pullStandardsResult}
    bind:selectedRoleMode bind:overrideHost bind:overridePort bind:overrideDatabase bind:overrideSslMode
    bind:overrideUser bind:overridePassword bind:overrideAdminUser bind:overrideAdminPassword
    onSwitchRoleAndConnect={switchRoleAndConnect} onSyncProvincialStandards={syncProvincialStandards} onApplySessionConfig={applySessionConfig}
  />

  {#if error}
    <p role="alert" class="rounded border-l-4 border-red-700 bg-red-50 p-3 text-sm text-red-900">{error}</p>
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
    <section class="space-y-4 rounded border border-vpro-border bg-white p-4 shadow-sm" data-custodian-panel aria-label="Custodian Inbox, 3-Way Merge, Standards and Snapshots">
      <header class="flex flex-wrap items-center justify-between gap-2 border-b-[3px] border-b-vpro-gold bg-vpro-navy px-4 py-3 text-white">
        <div>
          <p class="text-xs font-semibold uppercase tracking-wider text-vpro-gold">Custodian Governance Console</p>
          <h3 class="m-0 text-base font-semibold text-white">Schema Bootstrap, 2026 Standards Publishing, Staging 3-Way Merge &amp; Dated Snapshots</h3>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <label class="flex items-center gap-1.5 text-[11px] text-white/90" for="cloud-audit-limit">
            Audit Limit (0 = all)
            <input id="cloud-audit-limit" type="number" min="0" class="w-20 rounded border border-white/40 bg-white px-2 py-1 text-xs font-mono text-vpro-ink" bind:value={auditChainLimit} disabled={busy || operationHeld} />
          </label>
          <button type="button" data-verify-audit-chain disabled={busy || operationHeld} class="rounded border border-vpro-gold bg-vpro-navy-dark px-3 py-1.5 text-xs font-semibold text-white hover:bg-vpro-info disabled:opacity-50" onclick={runVerifyAuditChain}>
            Verify Audit Chain
          </button>
          <button type="button" disabled={busy || operationHeld} class="rounded bg-vpro-gold px-3 py-1.5 text-xs font-bold text-vpro-navy hover:bg-vpro-warning-bg disabled:opacity-50" onclick={runBootstrapSchemas}>
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
    <div class="rounded border border-vpro-border bg-vpro-surface-subtle px-4 py-3 text-xs text-vpro-ink-secondary">
      Custodian Admin tools (Schema Bootstrap, 2026 Standards Publishing, Staging Inbox 3-Way Merge, and Dated Snapshots) appear when the active session role is switched to <span class="font-semibold text-vpro-navy">Custodian Admin</span>.
    </div>
  {/if}
</div>
