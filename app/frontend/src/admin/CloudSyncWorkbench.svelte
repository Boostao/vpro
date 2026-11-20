<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import CloudSyncCustodianSection from './CloudSyncCustodianSection.svelte';
  import type { PublishStandardsDraft, SeedBaselineExtras } from './CloudSyncCustodianStandardsPanel.svelte';
  import CloudSyncSessionBar from './CloudSyncSessionBar.svelte';
  import * as cloudLib from './cloudSyncWorkbench';

  let {
    contextId,
    activeProject,
    activeSu = 'None',
    operationHeld = false,
    port = cloudLib.defaultCloudSyncPort,
    onBusyChange,
    oncontextswitched,
  }: {
    contextId: string;
    activeProject: string;
    activeSu?: string;
    operationHeld?: boolean;
    port?: cloudLib.CloudSyncPort;
    onBusyChange?: (busy: boolean) => void;
    oncontextswitched?: (state: unknown) => void;
  } = $props();

  let busy = $state(false);
  let error = $state<string | null>(null);
  let statusMessage = $state<string | null>(null);
  let generation = 0;
  let configStatus = $state.raw<cloudLib.CloudConfigStatus | null>(null);
  let connectionReport = $state.raw<cloudLib.CloudConnectionReport | null>(null);
  let selectedRoleMode = $state<cloudLib.CloudRoleMode>('contributor');
  let overrideHost = $state('');
  let overridePort = $state<string | number | null | undefined>('5432');
  let overrideDatabase = $state('');
  let overrideSslMode = $state('require');
  let overrideUser = $state('');
  let overridePassword = $state('');
  let overrideAdminUser = $state('');
  let overrideAdminPassword = $state('');
  let pullStandardsResult = $state.raw<cloudLib.PullStandardsResult | null>(null);
  let subsetZonesRaw = $state('');
  let subsetSubzonesRaw = $state('');
  let subsetProjectIdsRaw = $state('');
  let subsetPlotNumbersRaw = $state('');
  let subsetBboxRaw = $state('');
  let subsetLimitRaw = $state<string | number | null | undefined>('');
  let subsetAllowFull = $state(false);
  let subsetPreview = $state.raw<cloudLib.SubsetPreview | null>(null);
  let subsetTargetProject = $state('');
  let subsetDestinationPath = $state('');
  let subsetActivateOnSuccess = $state(true);
  let pullSubsetResult = $state.raw<cloudLib.PullSubsetResult | null>(null);
  let stagingUseActiveSu = $state(false);
  let stagingPreflight = $state.raw<cloudLib.StagingPreflightPreview | null>(null);
  let stagingSubmittedBy = $state('');
  let stagingSubmitterNotes = $state('');
  let stagingBaseSnapshotTag = $state('');
  let stagingCustodianOverride = $state(false);
  let submitStagingResult = $state.raw<cloudLib.SubmitStagingResult | null>(null);
  let submissions = $state.raw<cloudLib.StagingSubmissionSummary[]>([]);
  let bootstrapResult = $state.raw<cloudLib.SchemaBootstrapResult | null>(null);
  let auditChainLimit = $state<string | number | null | undefined>(0);
  let auditChainResult = $state.raw<cloudLib.AuditChainVerification | null>(null);
  let publishStandardsResult = $state.raw<cloudLib.PublishStandardsResult | null>(null);
  let seedSourceDbPath = $state('');
  let seedBaselineResult = $state.raw<cloudLib.SeedBaselineResult | null>(null);
  let selectedSubmissionDetail = $state.raw<cloudLib.StagingSubmissionDetail | null>(null);
  let mergePreview = $state.raw<cloudLib.StagingMergePreview | null>(null);
  let mergePlotResolutions = $state<Record<string, cloudLib.CloudMergeResolution>>({});
  let mergeFieldResolutions = $state<Record<string, cloudLib.CloudMergeResolution>>({});
  let mergeReviewerNotes = $state('');
  let mergeExecuteResult = $state.raw<cloudLib.StagingMergeResult | null>(null);
  let snapshotTag = $state('');
  let snapshotExportFormat = $state('');
  let latestSnapshotCreated = $state.raw<cloudLib.SnapshotRecord | null>(null);
  let snapshots = $state.raw<cloudLib.SnapshotRecord[]>([]);
  let downloadLog = $state.raw<cloudLib.DownloadLogEntry[]>([]);
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

  const activeRoleMode = $derived<cloudLib.CloudRoleMode>(
    connectionReport?.activeRoleMode ?? configStatus?.activeRoleMode ?? selectedRoleMode
  );
  const setBusy = (next: boolean) => {
    busy = next;
    onBusyChange?.(next);
  };
  const currentSessionFields = (): cloudLib.SessionOverrideFields => ({
    host: overrideHost,
    port: String(overridePort ?? '5432'),
    database: overrideDatabase,
    sslMode: overrideSslMode,
    user: overrideUser,
    adminUser: overrideAdminUser,
  });
  function applySessionFields(next: cloudLib.SessionOverrideFields) {
    overrideHost = next.host;
    overridePort = next.port;
    overrideDatabase = next.database;
    overrideSslMode = next.sslMode;
    overrideUser = next.user;
    overrideAdminUser = next.adminUser;
  }
  function failCloud(title: string, message: string, extraSecrets: readonly string[] = []) {
    const secrets = [overridePassword, overrideAdminPassword, ...extraSecrets];
    error = cloudLib.redactCloudSecrets(message, secrets);
    cloudLib.pushCloudSyncNotification('error', title, error, activeProject, secrets);
  }

  onMount(() => {
    const mountGen = generation;
    void port
      .getCloudSyncConfigStatus()
      .then((status) => {
        if (mountGen !== generation || !status) return;
        configStatus = status;
        selectedRoleMode = status.activeRoleMode;
        applySessionFields(cloudLib.resolveInitialSessionFields(status, currentSessionFields()));
      })
      .catch((cause) => {
        if (mountGen !== generation) return;
        const detail = cloudLib.formatCloudSyncError(cause, [overridePassword, overrideAdminPassword]);
        failCloud('Cloud config status unavailable', `Could not read local cloud sync configuration status: ${detail}`);
      });
  });

  onDestroy(() => {
    generation++;
    onBusyChange?.(false);
  });

  async function runCloudOp(
    label: string,
    blockedAction: string,
    work: (isCurrent: () => boolean) => Promise<cloudLib.CloudOpOutcome | void>
  ) {
    const capturedSecrets = [overridePassword, overrideAdminPassword];
    if (busy || operationHeld) {
      return failCloud(
        'Cloud sync action held',
        `Wait for the current operation or decision before ${blockedAction}.`,
        capturedSecrets
      );
    }
    const gen = ++generation;
    setBusy(true);
    error = null;
    statusMessage = null;
    try {
      const outcome = await work(() => gen === generation);
      if (gen === generation && outcome) {
        statusMessage = cloudLib.redactCloudSecrets(outcome.message, capturedSecrets);
        cloudLib.pushCloudSyncNotification(
          outcome.severity,
          outcome.title,
          statusMessage,
          activeProject,
          capturedSecrets
        );
        if (outcome.switchState && oncontextswitched) oncontextswitched(outcome.switchState);
      }
    } catch (cause) {
      if (gen === generation) {
        failCloud(
          `${label} failed`,
          `${label} failed: ${cloudLib.formatCloudSyncError(cause, capturedSecrets)}`,
          capturedSecrets
        );
      }
    } finally {
      if (gen === generation) setBusy(false);
    }
  }

  async function applySessionConfig(clearOverrides = false) {
    let parsedPort: number | undefined;
    if (!clearOverrides) {
      const portParsed = cloudLib.parseSessionPortInput(overridePort);
      if (portParsed.error) return failCloud('Invalid cloud server port', portParsed.error);
      parsedPort = portParsed.port;
    }
    const req = $state.snapshot(
      cloudLib.buildSessionConfigPayload(clearOverrides, selectedRoleMode, {
        ...currentSessionFields(),
        port: parsedPort,
        password: overridePassword,
        adminPassword: overrideAdminPassword,
      })
    );
    await runCloudOp('Configure cloud session', 'changing cloud session settings', async (isCurrent) => {
      const applied = await cloudLib.executeSessionConfigApply(
        port,
        req,
        clearOverrides,
        currentSessionFields(),
        parsedPort,
        isCurrent
      );
      if (!applied) return;
      overridePassword = '';
      overrideAdminPassword = '';
      applySessionFields(applied.fields);
      configStatus = applied.status;
      selectedRoleMode = applied.status.activeRoleMode;
      connectionReport = null;
      return applied.outcome;
    });
  }
  async function switchRoleAndConnect() {
    const roleReq = $state.snapshot({ roleMode: selectedRoleMode });
    await runCloudOp('Cloud connection probe', 'probing cloud status', (isCurrent) =>
      cloudLib.executeConnectionProbe(
        port,
        configStatus?.activeRoleMode ?? connectionReport?.activeRoleMode,
        roleReq,
        isCurrent,
        {
          onRoleConfigured: (status) => {
            configStatus = status;
            connectionReport = null;
          },
          onReport: (report) => {
            connectionReport = report?.connected ? report : null;
            if (report?.activeRoleMode) selectedRoleMode = report.activeRoleMode;
          },
        }
      )
    );
  }
  async function syncProvincialStandards() {
    await runCloudOp('Sync Provincial Standards', 'syncing provincial standards', async (isCurrent) => {
      const res = await port.pullCloudStandards(contextId);
      if (!isCurrent()) return;
      pullStandardsResult = res;
      return cloudLib.describePullStandardsOutcome(res);
    });
  }
  function buildSubsetDraftOrError() {
    const built = cloudLib.buildSubsetFilterFromInputs(
      subsetZonesRaw,
      subsetSubzonesRaw,
      subsetProjectIdsRaw,
      subsetPlotNumbersRaw,
      subsetBboxRaw,
      subsetLimitRaw,
      subsetAllowFull
    );
    if (built.error || !built.filter) {
      failCloud('Invalid subset filter', built.error ?? 'Invalid subset filter.');
      return null;
    }
    return built.filter;
  }

  async function runPreviewSubset() {
    const filter = buildSubsetDraftOrError();
    if (!filter) return;
    const filterPayload = $state.snapshot(filter);
    await runCloudOp('Preview BECMaster Subset', 'previewing BECMaster subset', async (isCurrent) => {
      const preview = await port.previewBECMasterSubset(filterPayload);
      if (!isCurrent()) return;
      subsetPreview = preview;
      return cloudLib.describePreviewSubsetOutcome(preview);
    });
  }
  async function runPullSubset() {
    const projErr = cloudLib.validateProjectNameInput(subsetTargetProject);
    if (projErr) return failCloud('Invalid subset target project', projErr);
    const filter = buildSubsetDraftOrError();
    if (!filter) return;
    const req = $state.snapshot(
      cloudLib.buildPullSubsetPayload(filter, subsetTargetProject, subsetDestinationPath, subsetActivateOnSuccess)
    );
    await runCloudOp('Download Regional Subset', 'downloading BECMaster subset', async (isCurrent) => {
      const res = await port.pullBECMasterSubset(contextId, req);
      if (!isCurrent()) return;
      pullSubsetResult = res;
      return cloudLib.describePullSubsetOutcome(res);
    });
  }
  async function runStagingPreflight() {
    const useSu = $state.snapshot(stagingUseActiveSu);
    await runCloudOp('Staging pre-flight preview', 'running staging pre-flight', async (isCurrent) => {
      const preflight = await port.previewStagingSubmission(contextId, useSu);
      if (!isCurrent()) return;
      stagingPreflight = preflight;
      stagingCustodianOverride = false;
      return cloudLib.describeStagingPreflightOutcome(preflight);
    });
  }
  async function runSubmitToStaging() {
    const gateErr = cloudLib.checkStagingSubmitGate(stagingPreflight, activeRoleMode, stagingCustodianOverride);
    if (gateErr || !stagingPreflight) return gateErr ? failCloud(gateErr.title, gateErr.message) : undefined;
    const req = $state.snapshot(
      cloudLib.buildStagingSubmitRequest(
        stagingUseActiveSu,
        stagingSubmittedBy,
        stagingSubmitterNotes,
        stagingBaseSnapshotTag,
        stagingPreflight.compliancePassed,
        activeRoleMode,
        stagingCustodianOverride
      )
    );
    await runCloudOp('Upload Staging Bundle', 'uploading to staging', async (isCurrent) => {
      const res = await port.submitProjectToStaging(contextId, req);
      if (!isCurrent()) return;
      submitStagingResult = res;
      return cloudLib.describeSubmitStagingOutcome(res);
    });
  }
  async function refreshSubmissionsList(filterOpts: { status?: string; submittedBy?: string } = {}) {
    const filter = $state.snapshot(cloudLib.buildSubmissionsFilter(filterOpts));
    await runCloudOp('Refresh Submissions', 'refreshing staging submissions', async (isCurrent) => {
      const rows = await port.listStagingSubmissions(filter);
      if (!isCurrent()) return;
      submissions = rows ?? [];
      return cloudLib.describeSubmissionsListOutcome(submissions.length);
    });
  }
  async function runBootstrapSchemas() {
    await runCloudOp('Bootstrap Cloud Schemas', 'bootstrapping cloud schemas', async (isCurrent) => {
      const res = await port.bootstrapCloudSchemas();
      if (!isCurrent()) return;
      bootstrapResult = res;
      return cloudLib.describeBootstrapSchemasOutcome(res);
    });
  }
  async function runVerifyAuditChain() {
    const limitParsed = cloudLib.parseAuditChainLimitInput(auditChainLimit);
    if (limitParsed.error) return failCloud('Invalid audit limit', limitParsed.error);
    await runCloudOp('Verify Audit Chain', 'verifying BECMaster audit hash chain', (isCurrent) =>
      cloudLib.executeVerifyAuditChain(port, limitParsed.limit, isCurrent, (next) => (auditChainResult = next))
    );
  }
  async function runPublishStandards(draft: PublishStandardsDraft = {}) {
    const req = $state.snapshot(cloudLib.buildPublishStandardsPayload(draft));
    await runCloudOp('Publish Standards to Cloud', 'publishing provincial standards', async (isCurrent) => {
      const res = await port.publishStandardsToCloud(contextId, req);
      if (!isCurrent()) return;
      publishStandardsResult = res;
      return cloudLib.describePublishStandardsOutcome(res);
    });
  }
  async function runSeedBaseline(extras: SeedBaselineExtras = {}) {
    const pathErr = cloudLib.checkSeedBaselinePath(seedSourceDbPath);
    if (pathErr) return failCloud(pathErr.title, pathErr.message);
    const req = $state.snapshot(cloudLib.buildSeedBaselinePayload(seedSourceDbPath, extras));
    await runCloudOp('Seed BECMaster Baseline', 'seeding BECMaster baseline', async (isCurrent) => {
      const res = await port.seedBECMasterBaseline(req);
      if (!isCurrent()) return;
      seedBaselineResult = res;
      return cloudLib.describeSeedBaselineOutcome(res);
    });
  }
  async function inspectSubmission(submissionId: string) {
    const idSnap = $state.snapshot(submissionId);
    await runCloudOp('Inspect Submission Detail', 'inspecting submission details', async (isCurrent) => {
      const detail = await port.getStagingSubmissionDetail(idSnap);
      if (!isCurrent()) return;
      selectedSubmissionDetail = detail;
      return cloudLib.describeInspectSubmissionOutcome(detail);
    });
  }
  async function runPreviewStagingMerge(submissionId: string, baseDbPath = '') {
    const req = $state.snapshot({ submissionId, baseDbPath: baseDbPath.trim() || undefined });
    await runCloudOp('Preview Staging-to-Master Merge', 'previewing 3-way staging merge', async (isCurrent) => {
      const preview = await port.previewStagingToMasterMerge(req);
      if (!isCurrent()) return;
      mergePreview = preview;
      mergeExecuteResult = null;
      mergePlotResolutions = {};
      mergeFieldResolutions = cloudLib.buildInitialCloudMergeFieldResolutions(preview);
      return cloudLib.describePreviewStagingMergeOutcome(preview);
    });
  }
  function setMergePlotResolution(plotNumber: string, value: string) {
    mergePlotResolutions = cloudLib.updateCloudMergeResolutionMap(mergePlotResolutions, plotNumber, value);
  }
  function setMergeFieldResolution(conflictId: string, choice: string) {
    mergeFieldResolutions = cloudLib.updateCloudMergeResolutionMap(mergeFieldResolutions, conflictId, choice);
  }
  async function runExecuteStagingMerge(opts: cloudLib.ExecuteStagingMergeOpts = {}) {
    if (!mergePreview)
      return failCloud('Merge preview required', 'Run Review & 3-Way Diff vs BECMaster before approving merge.');
    const req = $state.snapshot(
      cloudLib.buildStagingMergeExecPayload(
        mergePreview,
        mergePlotResolutions,
        mergeFieldResolutions,
        mergeReviewerNotes,
        opts
      )
    );
    await runCloudOp('Approve & Merge into BECMaster', 'executing BECMaster merge', async (isCurrent) => {
      const res = await port.executeStagingToMasterMerge(req);
      if (!isCurrent()) return;
      mergeExecuteResult = res;
      mergePreview = null;
      return cloudLib.describeExecuteStagingMergeOutcome(res);
    });
  }
  async function runRejectSubmission(submissionId?: string, actor?: string) {
    const checked = cloudLib.checkRejectSubmissionDraft(
      submissionId,
      mergePreview,
      selectedSubmissionDetail,
      mergeReviewerNotes,
      actor
    );
    if (checked.error || !checked.req)
      return checked.error ? failCloud(checked.error.title, checked.error.message) : undefined;
    const req = $state.snapshot(checked.req);
    await runCloudOp('Reject Staging Submission', 'rejecting a staging submission', async (isCurrent) => {
      const summary = await port.rejectStagingSubmission(req);
      if (!isCurrent()) return;
      submissions = submissions.map((s) => (s.submissionId === summary.submissionId ? summary : s));
      if (mergePreview?.submissionId === summary.submissionId) mergePreview = null;
      return cloudLib.describeRejectSubmissionOutcome(summary);
    });
  }
  async function runCreateSnapshot(extras: cloudLib.CreateSnapshotExtras = {}) {
    const tagErr = cloudLib.validateSnapshotTagInput(snapshotTag);
    if (tagErr) return failCloud('Invalid snapshot tag', tagErr);
    const req = $state.snapshot(cloudLib.buildCreateSnapshotPayload(snapshotTag, snapshotExportFormat, extras));
    await runCloudOp('Create BECMaster Snapshot', 'cutting a BECMaster snapshot', async (isCurrent) => {
      const rec = await port.createBECMasterSnapshot(contextId, req);
      if (!isCurrent()) return;
      latestSnapshotCreated = rec;
      snapshots = [rec, ...snapshots.filter((s) => s.snapshotTag !== rec.snapshotTag)];
      return cloudLib.describeCreateSnapshotOutcome(rec);
    });
  }
  async function refreshSnapshotsAndLedger() {
    await runCloudOp('Load Snapshots & Download Log', 'loading snapshots and download log', async (isCurrent) => {
      const [snapRows, logRows] = await Promise.all([port.listBECMasterSnapshots(), port.listBECMasterDownloadLog(50)]);
      if (!isCurrent()) return;
      snapshots = snapRows ?? [];
      downloadLog = logRows ?? [];
      return cloudLib.describeSnapshotsLedgerOutcome(snapshots.length, downloadLog.length);
    });
  }

  const custodianView = $derived({
    busy,
    operationHeld,
    activeProject,
    activeSu,
    activeRoleMode,
    subsetPreview,
    pullSubsetResult,
    stagingPreflight,
    submitStagingResult,
    submissions,
    auditChainResult,
    bootstrapResult,
    publishStandardsResult,
    seedBaselineResult,
    selectedSubmissionDetail,
    mergePreview,
    mergePlotResolutions,
    mergeFieldResolutions,
    mergeExecuteResult,
    latestSnapshotCreated,
    snapshots,
    downloadLog,
  });
  const custodianActions = {
    runPreviewSubset,
    runPullSubset,
    runStagingPreflight,
    runSubmitToStaging,
    refreshSubmissionsList,
    runVerifyAuditChain,
    runBootstrapSchemas,
    runPublishStandards,
    runSeedBaseline,
    inspectSubmission,
    runPreviewStagingMerge,
    setMergePlotResolution,
    setMergeFieldResolution,
    runExecuteStagingMerge,
    runRejectSubmission: (actor?: string) => void runRejectSubmission(undefined, actor),
    runCreateSnapshot,
    refreshSnapshotsAndLedger,
  };
</script>

<div class="min-w-0 space-y-5 text-vpro-ink" data-cloud-sync-workbench aria-label="Cloud BECMaster Sync Workbench">
  <CloudSyncSessionBar
    {busy}
    {operationHeld}
    {activeProject}
    {activeRoleMode}
    {configStatus}
    {connectionReport}
    {pullStandardsResult}
    {error}
    bind:selectedRoleMode
    bind:overrideHost
    bind:overridePort
    bind:overrideDatabase
    bind:overrideSslMode
    bind:overrideUser
    bind:overridePassword
    bind:overrideAdminUser
    bind:overrideAdminPassword
    onswitchroleandconnect={switchRoleAndConnect}
    onsyncstandards={syncProvincialStandards}
    onapplysessionconfig={applySessionConfig}
  />

  <CloudSyncCustodianSection
    view={custodianView}
    actions={custodianActions}
    bind:subsetZonesRaw
    bind:subsetSubzonesRaw
    bind:subsetProjectIdsRaw
    bind:subsetPlotNumbersRaw
    bind:subsetBboxRaw
    bind:subsetLimitRaw
    bind:subsetAllowFull
    bind:subsetTargetProject
    bind:subsetDestinationPath
    bind:subsetActivateOnSuccess
    bind:stagingUseActiveSu
    bind:stagingSubmittedBy
    bind:stagingSubmitterNotes
    bind:stagingBaseSnapshotTag
    bind:stagingCustodianOverride
    bind:auditChainLimit
    bind:seedSourceDbPath
    bind:mergeReviewerNotes
    bind:snapshotTag
    bind:snapshotExportFormat
  />
</div>
