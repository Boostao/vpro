<script lang="ts">
  import type {
    OrdinaryAuditReadEntry,
    OtherRecord,
    SoilSuggestion,
  } from '../../bindings/github.com/boostao/vpro/app';
  import FS882AuditTrailSection from './FS882AuditTrailSection.svelte';
  import FS882OtherRecordsSection from './FS882OtherRecordsSection.svelte';
  import FS882SoilHorizonSection from './FS882SoilHorizonSection.svelte';
  import type { FS882ChildCapabilities } from './fs882FormHelpers';
  import type { FS882SoilHorizonSectionProps } from './fs882SoilTypes';
  import type { OtherDrafts, OtherValue } from './otherEditor';
  import type { VegetationAttributeDrafts } from './vegetationAttributeEditor';

  interface Props extends FS882SoilHorizonSectionProps {
    activeTab: 'soils' | 'vegOther' | 'other' | 'audit';
    headerRevision: number;
    vegetationReadUnavailable: string | null;
    attributeEditingEnabled: boolean;
    attributeReferenceBusy: boolean;
    attributeReferenceError: string | null;
    attributeEditingDisabled: boolean;
    attributeDrafts: VegetationAttributeDrafts;
    attributeSuggestions: SoilSuggestion[];
    otherEditingEnabled: boolean;
    otherEditingDisabled: boolean;
    otherUnsaved: boolean;
    otherDrafts: OtherDrafts;
    otherList: OtherRecord[];
    auditList: OrdinaryAuditReadEntry[];
    auditProject: string;
    expectedPlotNumber?: string;
    childCapabilities: FS882ChildCapabilities;
    auditRestoreEnabled: boolean;
    auditBlocked: boolean;
    auditGateReason: string;
    getLoadRequest: () => number;
    PlotService: typeof import('../../bindings/github.com/boostao/vpro/app').PlotEntryService & ReturnType<typeof import('../shared/contextPlots').bindContextPlots>;
    loadAttributeSuggestions: () => Promise<void>;
    stageAttributeCell: (id: number, column: string, raw: string) => void;
    stageOtherCell: (id: number, column: string, raw: OtherValue) => void;
    onAuditBusyChange: (val: boolean) => void;
    onAuditFeedback: (err: string | null, msg: string | null) => void;
    onRefreshAfterRestore: (plot: string, request: number) => Promise<void>;
    onRefreshFailure: (msg: string) => void;
  }

  let {
    activeTab,
    draft = $bindable(),
    soilCodeBusy = $bindable(),
    geologyCodeBusy = $bindable(),
    parentCodeBusy = $bindable(),
    drainageBusy = $bindable(),
    headerRevision,
    childRevision,
    original,
    capabilities,
    sourceHeaderValues,
    busy,
    headerWorkflowBusy,
    sourceRows,
    openNewChild,
    deleteSourceChild,
    vegetationReadUnavailable,
    attributeEditingEnabled,
    attributeReferenceBusy,
    attributeReferenceError,
    attributeEditingDisabled,
    attributeDrafts,
    attributeSuggestions,
    otherEditingEnabled,
    otherEditingDisabled,
    otherUnsaved,
    otherDrafts,
    otherList,
    auditList,
    auditProject,
    expectedPlotNumber,
    childCapabilities,
    auditRestoreEnabled,
    auditBlocked,
    auditGateReason,
    getLoadRequest,
    PlotService,
    loadAttributeSuggestions,
    stageAttributeCell,
    stageOtherCell,
    onAuditBusyChange,
    onAuditFeedback,
    onRefreshAfterRestore,
    onRefreshFailure,
    ...soilHorizonRest
  }: Props = $props();
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
      {childRevision}
      {busy}
      {headerWorkflowBusy}
      {sourceRows}
      {openNewChild}
      {deleteSourceChild}
      {...soilHorizonRest}
    />
  {/key}
{:else if activeTab === 'vegOther'}
  <FS882OtherRecordsSection mode="vegOther" {sourceHeaderValues} {childRevision} {busy} {headerWorkflowBusy}
    {sourceRows} {vegetationReadUnavailable} {attributeEditingEnabled} {attributeReferenceBusy}
    {attributeReferenceError} {attributeEditingDisabled} {attributeDrafts} {attributeSuggestions}
    {loadAttributeSuggestions} {stageAttributeCell} />
{:else if activeTab === 'other'}
  <FS882OtherRecordsSection mode="other" {sourceHeaderValues} {childRevision} {busy} {headerWorkflowBusy}
    {sourceRows} {otherEditingEnabled} {otherEditingDisabled} {otherUnsaved} {otherDrafts} {otherList}
    {openNewChild} {stageOtherCell} {deleteSourceChild} />
{:else if activeTab === 'audit'}
  <FS882AuditTrailSection entries={auditList} project={auditProject} plot={original?.plotNumber ?? ''}
    {expectedPlotNumber} {capabilities} {childCapabilities} enabled={auditRestoreEnabled}
    disabled={auditBlocked} gateReason={auditGateReason} revision={childRevision}
    {getLoadRequest} {PlotService}
    onBusyChange={onAuditBusyChange}
    onFeedback={onAuditFeedback}
    {onRefreshAfterRestore}
    {onRefreshFailure} />
{/if}
