<script lang="ts">
  import CloudSyncCustodianMergePanel from './CloudSyncCustodianMergePanel.svelte';
  import CloudSyncCustodianStandardsPanel, {
    type PublishStandardsDraft,
    type SeedBaselineExtras,
  } from './CloudSyncCustodianStandardsPanel.svelte';
  import CloudSyncPullPanel from './CloudSyncPullPanel.svelte';
  import CloudSyncSnapshotsPanel from './CloudSyncSnapshotsPanel.svelte';
  import CloudSyncStagingPanel from './CloudSyncStagingPanel.svelte';
  import {
    canUploadStagingSubmission,
    combineCloudMergeItems,
    validateProjectNameInput,
    validateSnapshotTagInput,
    type AuditChainVerification,
    type CloudMergeResolution,
    type CloudRoleMode,
    type DownloadLogEntry,
    type PublishStandardsResult,
    type PullSubsetResult,
    type SchemaBootstrapResult,
    type SeedBaselineResult,
    type SnapshotRecord,
    type StagingMergePreview,
    type StagingMergeResult,
    type StagingPreflightPreview,
    type StagingSubmissionDetail,
    type StagingSubmissionSummary,
    type SubmitStagingResult,
    type SubsetPreview,
  } from './cloudSyncWorkbench';

  export interface CloudCustodianView {
    busy: boolean;
    operationHeld: boolean;
    activeProject: string;
    activeSu: string;
    activeRoleMode: CloudRoleMode;
    subsetPreview: SubsetPreview | null;
    pullSubsetResult: PullSubsetResult | null;
    stagingPreflight: StagingPreflightPreview | null;
    submitStagingResult: SubmitStagingResult | null;
    submissions: StagingSubmissionSummary[];
    auditChainResult: AuditChainVerification | null;
    bootstrapResult: SchemaBootstrapResult | null;
    publishStandardsResult: PublishStandardsResult | null;
    seedBaselineResult: SeedBaselineResult | null;
    selectedSubmissionDetail: StagingSubmissionDetail | null;
    mergePreview: StagingMergePreview | null;
    mergePlotResolutions: Record<string, CloudMergeResolution>;
    mergeFieldResolutions: Record<string, CloudMergeResolution>;
    mergeExecuteResult: StagingMergeResult | null;
    latestSnapshotCreated: SnapshotRecord | null;
    snapshots: SnapshotRecord[];
    downloadLog: DownloadLogEntry[];
  }

  export interface CloudCustodianActions {
    runPreviewSubset: () => void;
    runPullSubset: () => void;
    runStagingPreflight: () => void;
    runSubmitToStaging: () => void;
    refreshSubmissionsList: (filterOpts?: { status?: string; submittedBy?: string }) => void;
    runVerifyAuditChain: () => void;
    runBootstrapSchemas: () => void;
    runPublishStandards: (draft?: PublishStandardsDraft) => void;
    runSeedBaseline: (extras?: SeedBaselineExtras) => void;
    inspectSubmission: (submissionId: string) => void;
    runPreviewStagingMerge: (submissionId: string, baseDbPath?: string) => void;
    setMergePlotResolution: (plotNumber: string, value: string) => void;
    setMergeFieldResolution: (conflictId: string, choice: string) => void;
    runExecuteStagingMerge: (opts?: {
      baseDbPath?: string;
      defaultConflictResolution?: CloudMergeResolution;
      actor?: string;
    }) => void;
    runRejectSubmission: (actor?: string) => void;
    runCreateSnapshot: (extras?: { destinationPath?: string; zoneFilter?: string; notes?: string }) => void;
    refreshSnapshotsAndLedger: () => void;
  }

  let {
    view,
    actions,
    subsetZonesRaw = $bindable(''),
    subsetSubzonesRaw = $bindable(''),
    subsetProjectIdsRaw = $bindable(''),
    subsetPlotNumbersRaw = $bindable(''),
    subsetBboxRaw = $bindable(''),
    subsetLimitRaw = $bindable<string | number | null | undefined>(''),
    subsetAllowFull = $bindable(false),
    subsetTargetProject = $bindable(''),
    subsetDestinationPath = $bindable(''),
    subsetActivateOnSuccess = $bindable(true),
    stagingUseActiveSu = $bindable(false),
    stagingSubmittedBy = $bindable(''),
    stagingSubmitterNotes = $bindable(''),
    stagingBaseSnapshotTag = $bindable(''),
    stagingCustodianOverride = $bindable(false),
    auditChainLimit = $bindable<string | number | null | undefined>(0),
    seedSourceDbPath = $bindable(''),
    mergeReviewerNotes = $bindable(''),
    snapshotTag = $bindable(''),
    snapshotExportFormat = $bindable(''),
  }: {
    view: CloudCustodianView;
    actions: CloudCustodianActions;
    subsetZonesRaw?: string;
    subsetSubzonesRaw?: string;
    subsetProjectIdsRaw?: string;
    subsetPlotNumbersRaw?: string;
    subsetBboxRaw?: string;
    subsetLimitRaw?: string | number | null | undefined;
    subsetAllowFull?: boolean;
    subsetTargetProject?: string;
    subsetDestinationPath?: string;
    subsetActivateOnSuccess?: boolean;
    stagingUseActiveSu?: boolean;
    stagingSubmittedBy?: string;
    stagingSubmitterNotes?: string;
    stagingBaseSnapshotTag?: string;
    stagingCustodianOverride?: boolean;
    auditChainLimit?: string | number | null | undefined;
    seedSourceDbPath?: string;
    mergeReviewerNotes?: string;
    snapshotTag?: string;
    snapshotExportFormat?: string;
  } = $props();

  const subsetTargetValidationError = $derived(
    subsetTargetProject === '' ? null : validateProjectNameInput(subsetTargetProject)
  );
  const snapshotTagValidationError = $derived(snapshotTag === '' ? null : validateSnapshotTagInput(snapshotTag));
  const canUploadStaging = $derived(
    canUploadStagingSubmission(view.stagingPreflight, view.activeRoleMode, stagingCustodianOverride)
  );
  const combinedMergeItems = $derived(combineCloudMergeItems(view.mergePreview));
</script>

<div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
  <CloudSyncPullPanel
    busy={view.busy}
    operationHeld={view.operationHeld}
    bind:subsetZonesRaw
    bind:subsetSubzonesRaw
    bind:subsetProjectIdsRaw
    bind:subsetPlotNumbersRaw
    bind:subsetBboxRaw
    bind:subsetLimitRaw
    bind:subsetAllowFull
    subsetPreview={view.subsetPreview}
    bind:subsetTargetProject
    bind:subsetDestinationPath
    bind:subsetActivateOnSuccess
    {subsetTargetValidationError}
    pullSubsetResult={view.pullSubsetResult}
    onPreviewSubset={actions.runPreviewSubset}
    onPullSubset={actions.runPullSubset}
  />
  <CloudSyncStagingPanel
    busy={view.busy}
    operationHeld={view.operationHeld}
    activeProject={view.activeProject}
    activeSu={view.activeSu}
    activeRoleMode={view.activeRoleMode}
    bind:stagingUseActiveSu
    stagingPreflight={view.stagingPreflight}
    bind:stagingSubmittedBy
    bind:stagingSubmitterNotes
    bind:stagingBaseSnapshotTag
    bind:stagingCustodianOverride
    {canUploadStaging}
    submitStagingResult={view.submitStagingResult}
    submissions={view.submissions}
    onRunStagingPreflight={actions.runStagingPreflight}
    onRunSubmitToStaging={actions.runSubmitToStaging}
    onRefreshSubmissionsList={() => actions.refreshSubmissionsList()}
  />
</div>

{#if view.activeRoleMode === 'custodian'}
  <section
    class="space-y-4 rounded border border-vpro-border bg-white p-4 shadow-sm"
    data-custodian-panel
    aria-label="Custodian Inbox, 3-Way Merge, Standards and Snapshots"
  >
    <header
      class="flex flex-wrap items-center justify-between gap-2 border-b-[3px] border-b-vpro-gold bg-vpro-navy px-4 py-3 text-white"
    >
      <div>
        <p class="text-xs font-semibold uppercase tracking-wider text-vpro-gold">Custodian Governance Console</p>
        <h3 class="m-0 text-base font-semibold text-white">
          Schema Bootstrap, 2026 Standards Publishing, Staging 3-Way Merge &amp; Dated Snapshots
        </h3>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <label class="flex items-center gap-1.5 text-[11px] text-white/90" for="cloud-audit-limit">
          Audit Limit (0 = all)
          <input
            id="cloud-audit-limit"
            type="number"
            min="0"
            class="w-20 rounded border border-white/40 bg-white px-2 py-1 font-mono text-xs text-vpro-ink"
            bind:value={auditChainLimit}
            disabled={view.busy || view.operationHeld}
          />
        </label>
        <button
          type="button"
          data-verify-audit-chain
          disabled={view.busy || view.operationHeld}
          class="rounded border border-vpro-gold bg-vpro-navy-dark px-3 py-1.5 text-xs font-semibold text-white hover:bg-vpro-info disabled:opacity-50"
          onclick={actions.runVerifyAuditChain}
        >
          Verify Audit Chain
        </button>
        <button
          type="button"
          disabled={view.busy || view.operationHeld}
          class="rounded bg-vpro-gold px-3 py-1.5 text-xs font-bold text-vpro-navy hover:bg-vpro-warning-bg disabled:opacity-50"
          onclick={actions.runBootstrapSchemas}
        >
          Bootstrap / Verify Schemas
        </button>
      </div>
    </header>

    <CloudSyncCustodianStandardsPanel
      busy={view.busy}
      operationHeld={view.operationHeld}
      auditChainResult={view.auditChainResult}
      bootstrapResult={view.bootstrapResult}
      publishStandardsResult={view.publishStandardsResult}
      bind:seedSourceDbPath
      seedBaselineResult={view.seedBaselineResult}
      onPublishStandards={actions.runPublishStandards}
      onSeedBaseline={actions.runSeedBaseline}
    />

    <CloudSyncCustodianMergePanel
      busy={view.busy}
      operationHeld={view.operationHeld}
      submissions={view.submissions}
      selectedSubmissionDetail={view.selectedSubmissionDetail}
      mergePreview={view.mergePreview}
      {combinedMergeItems}
      mergePlotResolutions={view.mergePlotResolutions}
      mergeFieldResolutions={view.mergeFieldResolutions}
      bind:mergeReviewerNotes
      mergeExecuteResult={view.mergeExecuteResult}
      onRefreshSubmissions={actions.refreshSubmissionsList}
      onInspectSubmission={actions.inspectSubmission}
      onPreviewMerge={actions.runPreviewStagingMerge}
      onSetPlotResolution={actions.setMergePlotResolution}
      onSetFieldResolution={actions.setMergeFieldResolution}
      onExecuteMerge={actions.runExecuteStagingMerge}
      onRejectSubmission={actions.runRejectSubmission}
    />

    <CloudSyncSnapshotsPanel
      busy={view.busy}
      operationHeld={view.operationHeld}
      bind:snapshotTag
      bind:snapshotExportFormat
      {snapshotTagValidationError}
      latestSnapshotCreated={view.latestSnapshotCreated}
      snapshots={view.snapshots}
      downloadLog={view.downloadLog}
      onCreateSnapshot={actions.runCreateSnapshot}
      onRefreshSnapshots={actions.refreshSnapshotsAndLedger}
    />
  </section>
{:else}
  <div class="rounded border border-vpro-border bg-vpro-surface-subtle px-4 py-3 text-xs text-vpro-ink-secondary">
    Custodian Admin tools (Schema Bootstrap, 2026 Standards Publishing, Staging Inbox 3-Way Merge, and Dated Snapshots)
    appear when the active session role is switched to <span class="font-semibold text-vpro-navy">Custodian Admin</span
    >.
  </div>
{/if}
