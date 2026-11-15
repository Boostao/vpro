<script lang="ts">
  import type {
    FS882Header,
    HumusRecord,
    MineralRecord,
    OrdinaryAuditReadEntry,
    OtherRecord,
    SoilSuggestion,
  } from '../../bindings/github.com/boostao/vpro/app';
  import FS882AuditTrailSection from './FS882AuditTrailSection.svelte';
  import FS882OtherRecordsSection from './FS882OtherRecordsSection.svelte';
  import FS882SoilHorizonSection from './FS882SoilHorizonSection.svelte';
  import type { FS882ChildCapabilities } from './fs882FormHelpers';
  import type { OtherDrafts, OtherValue } from './otherEditor';
  import type { SoilDrafts, SoilKind } from './soilChildEditor';
  import type { VegetationAttributeDrafts } from './vegetationAttributeEditor';

  let {
    activeTab,
    draft = $bindable(),
    original,
    capabilities,
    soilCodeBusy = $bindable(),
    geologyCodeBusy = $bindable(),
    parentCodeBusy = $bindable(),
    drainageBusy = $bindable(),
    headerRevision,
    childRevision,
    sourceHeaderValues,
    ordinarySoilUnavailable,
    historicalSoilUnavailable,
    soilEditingEnabled,
    soilCodeEditingEnabled,
    soilReferenceBusy,
    soilReferenceError,
    soilEditingDisabled,
    soilUnsaved,
    headerInputsDisabled,
    busy,
    headerWorkflowBusy,
    coordinateBusy,
    workingUnitBusy,
    qualityBusy,
    siteCodeBusy,
    regionCodeBusy,
    soilDrafts,
    soilSuggestions,
    humusList,
    mineralList,
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
    sourceRows,
    markDirty,
    validateHeader,
    loadSoilSuggestions,
    openNewChild,
    stageSoilCell,
    deleteSourceChild,
    deleteHumus,
    loadAttributeSuggestions,
    stageAttributeCell,
    stageOtherCell,
    onAuditBusyChange,
    onAuditFeedback,
    onRefreshAfterRestore,
    onRefreshFailure,
  }: {
    activeTab: 'soils' | 'vegOther' | 'other' | 'audit';
    draft: FS882Header;
    original: FS882Header | null;
    capabilities: Record<string, boolean | undefined>;
    soilCodeBusy: boolean;
    geologyCodeBusy: boolean;
    parentCodeBusy: boolean;
    drainageBusy: boolean;
    headerRevision: number;
    childRevision: number;
    sourceHeaderValues: Map<string, unknown>;
    ordinarySoilUnavailable: string | null;
    historicalSoilUnavailable: string | null;
    soilEditingEnabled: boolean;
    soilCodeEditingEnabled: boolean;
    soilReferenceBusy: boolean;
    soilReferenceError: string | null;
    soilEditingDisabled: boolean;
    soilUnsaved: boolean;
    headerInputsDisabled: boolean;
    busy: boolean;
    headerWorkflowBusy: boolean;
    coordinateBusy: boolean;
    workingUnitBusy: boolean;
    qualityBusy: boolean;
    siteCodeBusy: boolean;
    regionCodeBusy: boolean;
    soilDrafts: SoilDrafts;
    soilSuggestions: SoilSuggestion[];
    humusList: HumusRecord[];
    mineralList: MineralRecord[];
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
    sourceRows: (name: string) => Array<{ id: number; values: Record<string, string | number | boolean | null | undefined> }>;
    markDirty: () => void;
    validateHeader: (key: string, message: string | null) => void;
    loadSoilSuggestions: () => Promise<void>;
    openNewChild: (kind: 'humus' | 'mineral' | 'other') => void;
    stageSoilCell: (kind: SoilKind, id: number, column: string, raw: string) => void;
    deleteSourceChild: (name: string, id: number) => Promise<void>;
    deleteHumus: (id: number) => Promise<void>;
    loadAttributeSuggestions: () => Promise<void>;
    stageAttributeCell: (id: number, column: string, raw: string) => void;
    stageOtherCell: (id: number, column: string, raw: OtherValue) => void;
    onAuditBusyChange: (val: boolean) => void;
    onAuditFeedback: (err: string | null, msg: string | null) => void;
    onRefreshAfterRestore: (plot: string, request: number) => Promise<void>;
    onRefreshFailure: (msg: string) => void;
  } = $props();
</script>

{#if activeTab === 'soils'}
  {#key headerRevision}
    <FS882SoilHorizonSection bind:draft {original} {capabilities} {sourceHeaderValues} {ordinarySoilUnavailable}
      {historicalSoilUnavailable} {soilEditingEnabled} {soilCodeEditingEnabled} {soilReferenceBusy}
      {soilReferenceError} {soilEditingDisabled} {soilUnsaved} {headerInputsDisabled} {busy} {headerWorkflowBusy}
      {coordinateBusy} {workingUnitBusy} {qualityBusy} {siteCodeBusy} {regionCodeBusy}
      bind:soilCodeBusy bind:geologyCodeBusy bind:parentCodeBusy bind:drainageBusy
      {childRevision} {soilDrafts} {soilSuggestions} {humusList} {mineralList} {sourceRows} {markDirty}
      {validateHeader} {loadSoilSuggestions} {openNewChild} {stageSoilCell} {deleteSourceChild} {deleteHumus} />
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
