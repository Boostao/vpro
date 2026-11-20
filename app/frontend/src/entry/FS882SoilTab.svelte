<script lang="ts">
  import type { FS882Header } from '../../bindings/github.com/boostao/vpro/app';
  import FS882AuditTrailSection from './FS882AuditTrailSection.svelte';
  import FS882OtherRecordsSection from './FS882OtherRecordsSection.svelte';
  import FS882SoilHorizonSection from './FS882SoilHorizonSection.svelte';
  import type { FS882ChildWorkflowsController } from './useFS882ChildWorkflows.svelte';

  let {
    activeTab,
    children: c,
    draft = $bindable(),
    original,
    capabilities,
    soilCodeBusy = $bindable(),
    geologyCodeBusy = $bindable(),
    parentCodeBusy = $bindable(),
    drainageBusy = $bindable(),
    headerRevision,
    sourceHeaderValues,
    headerInputsDisabled,
    busy,
    headerWorkflowBusy,
    coordinateBusy,
    workingUnitBusy,
    qualityBusy,
    siteCodeBusy,
    regionCodeBusy,
    auditProject,
    expectedPlotNumber,
    auditBlocked,
    auditGateReason,
    getLoadRequest,
    PlotService,
    markDirty,
    validateHeader,
    onAuditBusyChange,
    onAuditFeedback,
    onRefreshAfterRestore,
    onRefreshFailure,
  }: {
    activeTab: 'soils' | 'vegOther' | 'other' | 'audit';
    children: FS882ChildWorkflowsController;
    draft: FS882Header;
    original: FS882Header | null;
    capabilities: Record<string, boolean | undefined>;
    soilCodeBusy: boolean;
    geologyCodeBusy: boolean;
    parentCodeBusy: boolean;
    drainageBusy: boolean;
    headerRevision: number;
    sourceHeaderValues: Map<string, unknown>;
    headerInputsDisabled: boolean;
    busy: boolean;
    headerWorkflowBusy: boolean;
    coordinateBusy: boolean;
    workingUnitBusy: boolean;
    qualityBusy: boolean;
    siteCodeBusy: boolean;
    regionCodeBusy: boolean;
    auditProject: string;
    expectedPlotNumber?: string;
    auditBlocked: boolean;
    auditGateReason: string;
    getLoadRequest: () => number;
    PlotService: typeof import('../../bindings/github.com/boostao/vpro/app').PlotEntryService &
      ReturnType<typeof import('../shared/contextPlots').bindContextPlots>;
    markDirty: () => void;
    validateHeader: (key: string, message: string | null) => void;
    onAuditBusyChange: (val: boolean) => void;
    onAuditFeedback: (err: string | null, msg: string | null) => void;
    onRefreshAfterRestore: (plot: string, request: number) => Promise<void>;
    onRefreshFailure: (msg: string) => void;
  } = $props();
</script>

{#if activeTab === 'soils'}
  {#key headerRevision}
    <FS882SoilHorizonSection
      bind:draft
      bind:soilCodeBusy
      bind:geologyCodeBusy
      bind:parentCodeBusy
      bind:drainageBusy
      {original}
      {capabilities}
      {sourceHeaderValues}
      ordinarySoilUnavailable={c.ordinarySoilUnavailable}
      historicalSoilUnavailable={c.historicalSoilUnavailable}
      soilReferenceBusy={c.soilReferenceBusy}
      soilReferenceError={c.soilReferenceError}
      soilEditingDisabled={c.soilEditingDisabled}
      soilUnsaved={c.soilUnsaved}
      {headerInputsDisabled}
      {busy}
      {headerWorkflowBusy}
      {coordinateBusy}
      {workingUnitBusy}
      {qualityBusy}
      {siteCodeBusy}
      {regionCodeBusy}
      childRevision={c.childRevision}
      soilDrafts={c.soilDrafts}
      soilSuggestions={c.soilSuggestions}
      humusList={c.humusList}
      mineralList={c.mineralList}
      sourceRows={c.sourceRows}
      {markDirty}
      {validateHeader}
      loadSoilSuggestions={c.loadSoilSuggestions}
      openNewChild={c.openNewChild}
      stageSoilCell={c.stageSoilCell}
      deleteSourceChild={c.deleteSourceChild}
      deleteHumus={c.deleteHumus}
    />
  {/key}
{:else if activeTab === 'vegOther'}
  <FS882OtherRecordsSection
    mode="vegOther"
    {sourceHeaderValues}
    childRevision={c.childRevision}
    {busy}
    {headerWorkflowBusy}
    sourceRows={c.sourceRows}
    vegetationReadUnavailable={c.vegetationReadUnavailable}
    attributeReferenceBusy={c.attributeReferenceBusy}
    attributeReferenceError={c.attributeReferenceError}
    attributeEditingDisabled={c.attributeEditingDisabled}
    attributeDrafts={c.attributeDrafts}
    attributeSuggestions={c.attributeSuggestions}
    loadAttributeSuggestions={c.loadAttributeSuggestions}
    stageAttributeCell={c.stageAttributeCell}
  />
{:else if activeTab === 'other'}
  <FS882OtherRecordsSection
    mode="other"
    {sourceHeaderValues}
    childRevision={c.childRevision}
    {busy}
    {headerWorkflowBusy}
    sourceRows={c.sourceRows}
    otherEditingDisabled={c.otherEditingDisabled}
    otherUnsaved={c.otherUnsaved}
    otherDrafts={c.otherDrafts}
    otherList={c.otherList}
    openNewChild={c.openNewChild}
    stageOtherCell={c.stageOtherCell}
    deleteSourceChild={c.deleteSourceChild}
  />
{:else if activeTab === 'audit'}
  <FS882AuditTrailSection
    entries={c.auditList}
    project={auditProject}
    plot={original?.plotNumber ?? ''}
    {expectedPlotNumber}
    {capabilities}
    childCapabilities={c.childCapabilities}
    enabled={true}
    disabled={auditBlocked}
    gateReason={auditGateReason}
    revision={c.childRevision}
    {getLoadRequest}
    {PlotService}
    onBusyChange={onAuditBusyChange}
    onFeedback={onAuditFeedback}
    {onRefreshAfterRestore}
    {onRefreshFailure}
  />
{/if}
