<script lang="ts">
  import { AuditRestoreAction, type FS882Header, type SpeciesItem, type VegRecord } from '../../bindings/github.com/boostao/vpro/app';
  import FS882ChildCreateModal from './FS882ChildCreateModal.svelte';
  import FS882StratumSummary from './FS882StratumSummary.svelte';
  import OrdinaryFields from './OrdinaryFields.svelte';
  import SourceChild from './SourceChild.svelte';
  import SourcePage from './SourcePage.svelte';
  import type { CollectedDrafts } from './collectedEditor';
  import type { HeightDrafts } from './heightEditor';
  import { embeddedForm, type VegetationMode } from './paperLayout';
  import type { SIVICollectedView } from './siviCollectedSession';
  import type { SIVICombinedColumn } from './siviCombinedEditor';
  import type { SIVICombinedView } from './siviCombinedSession';
  import type { SIVICoverColumn } from './siviCoverEditor';
  import type { SIVICoverView } from './siviCoverSession';
  import type { SIVICreationDraft, SIVICreationForm } from './siviCreationEditor';
  import type { SIVICreationSession, SIVICreationView } from './siviCreationSession';
  import type { SIVICreationUndoView } from './siviCreationUndoSession';
  import type { SIVIDeletionRestorationView } from './siviDeletionRestorationSession';
  import type { SIVIDeletionView } from './siviDeletionSession';
  import type { SIVIHeightColumn } from './siviHeightEditor';
  import type { SIVIHeightView } from './siviHeightSession';
  import type { SIVIIdentityView } from './siviIdentitySession';
  import type { SIVISpeciesView } from './siviSpeciesSession';
  import type { EditorCloseState } from '../shell/closeLifecycle';
  import type { SpeciesDecisionKind, SpeciesDrafts, SpeciesLists } from './vegetationSpeciesEditor';

  let {
    draft = $bindable(),
    original,
    capabilities,
    vegetationMode = $bindable(),
    showSpeciesModal = $bindable(),
    speciesSearchQuery = $bindable(),
    busy,
    headerWorkflowBusy,
    headerInputsDisabled,
    capabilitiesReady,
    siviStandalone,
    siviStandaloneEnabled,
    extendedShrubs,
    extendedShrubsNotice,
    siviContextId,
    activeProject,
    childRevision,
    sourceHeaderValues,
    headerValidation,
    childParentDisabled,
    childUnsaved,
    childEditingDisabled,
    numberEditingEnabled,
    heightEditingDisabled,
    collectedEditingEnabled,
    collectedEditingDisabled,
    speciesEditingEnabled,
    speciesEditingDisabled,
    creationEnabled,
    deletionEnabled,
    personalSpeciesEnabled,
    vegetationReadUnavailable,
    speciesReferenceReady,
    speciesReferenceBusy,
    speciesReferenceError,
    speciesDrafts,
    speciesLists,
    collectedDrafts,
    heightDrafts,
    vegList,
    totalTreeCover,
    totalShrubCover,
    totalHerbCover,
    totalMossCover,
    speciesSearchResults,
    searchingSpecies,
    siviHeightEnabled, siviCoverEnabled, siviCombinedEnabled, siviCollectedEnabled, siviSpeciesEnabled, siviIdentityEnabled,
    siviCreationEnabled, siviDeletionEnabled, siviRestorationEnabled, siviCreationUndoEnabled,
    siviPanelOpen, siviCoverPanelOpen, siviCombinedPanelOpen, siviCollectedPanelOpen, siviSpeciesPanelOpen, siviIdentityPanelOpen,
    siviView, siviClose, siviUnsaved, siviEditingDisabled,
    siviCoverView, siviCoverClose, siviCoverUnsaved, siviCoverBusy, siviCoverReading, siviCoverEditingDisabled,
    siviCombinedView, siviCombinedClose, siviCombinedUnsaved, siviCombinedBusy, siviCombinedReading, siviCombinedEditingDisabled,
    siviCollectedView, siviCollectedClose, siviCollectedUnsaved, siviCollectedBusy, siviCollectedReading, siviCollectedEditingDisabled,
    siviSpeciesView, siviSpeciesClose, siviSpeciesUnsaved, siviSpeciesBusy, siviSpeciesReading, siviSpeciesEditingDisabled,
    siviIdentityView, siviIdentityClose, siviIdentityUnsaved, siviIdentityBusy, siviIdentityReading, siviIdentityEditingDisabled,
    siviDeletionView, siviDeletionClose, siviDeletionEditingDisabled, siviDeletionRecoveryDisabled,
    siviRestorationView, siviRestorationClose, siviRestorationTargets, siviRestorationEditingDisabled, siviRestorationRecoveryDisabled,
    siviCreationUndoView, siviCreationUndoClose, siviCreationUndoEditingDisabled, siviCreationUndoRecoveryDisabled,
    siviCreationSession, siviCreationView, siviCreationClose, siviCreationEditingDisabled, siviCreationRecoveryDisabled,
    codeCheckEnabled, onFindPlot,
    markDirty, validateHeader, vegetationNotesTab, openSpeciesCodeCheck,
    loadSpeciesReferences, sourceRows, startVegetationCreation, stageHeightCell, stageCollectedCell, stageSpeciesCell, reviewVegetationDeletion,
    searchSpecies, selectSpeciesToAdd, deleteVeg,
    showSIVIPanel, showSIVICoverPanel, showSIVICombinedPanel, showSIVICollectedPanel, showSIVISpeciesPanel, showSIVIIdentityPanel,
    siviOperation, stageSIVICell,
    siviCoverOperation, stageSIVICoverCell, onCancelSiviCoverRead,
    siviCombinedOperation, stageSIVICombinedCell, onCancelSiviCombinedRead,
    siviCollectedOperation, cycleSIVICollected, onCancelSiviCollectedRead,
    siviSpeciesOperation, stageSIVISpecies, onCancelSiviSpeciesRead,
    siviIdentityOperation, stageSIVIIdentity, onCancelSiviIdentityRead,
    siviLifecycleOperation, stageSIVILifecycle, siviCreationUndoOperation, stageSIVICreationUndo,
    siviCreationOperation, stageSIVICreation,
  }: {
    draft: FS882Header;
    original: FS882Header | null;
    capabilities: Record<string, boolean | undefined>;
    vegetationMode: VegetationMode;
    showSpeciesModal: boolean;
    speciesSearchQuery: string;
    busy: boolean;
    headerWorkflowBusy: boolean;
    headerInputsDisabled: boolean;
    capabilitiesReady: boolean;
    siviStandalone: boolean;
    siviStandaloneEnabled: boolean;
    extendedShrubs: boolean;
    extendedShrubsNotice: string;
    siviContextId: string;
    activeProject: string;
    childRevision: number;
    sourceHeaderValues: Map<string, unknown>;
    headerValidation: Record<string, string>;
    childParentDisabled: boolean;
    childUnsaved: boolean;
    childEditingDisabled: boolean;
    numberEditingEnabled: boolean;
    heightEditingDisabled: boolean;
    collectedEditingEnabled: boolean;
    collectedEditingDisabled: boolean;
    speciesEditingEnabled: boolean;
    speciesEditingDisabled: boolean;
    creationEnabled: boolean;
    deletionEnabled: boolean;
    personalSpeciesEnabled: boolean;
    vegetationReadUnavailable: string | null;
    speciesReferenceReady: boolean;
    speciesReferenceBusy: boolean;
    speciesReferenceError: string | null;
    speciesDrafts: SpeciesDrafts;
    speciesLists: SpeciesLists;
    collectedDrafts: CollectedDrafts;
    heightDrafts: HeightDrafts;
    vegList: VegRecord[];
    totalTreeCover: number | null;
    totalShrubCover: number | null;
    totalHerbCover: number | null;
    totalMossCover: number | null;
    speciesSearchResults: SpeciesItem[];
    searchingSpecies: boolean;
    siviHeightEnabled: boolean; siviCoverEnabled: boolean; siviCombinedEnabled: boolean; siviCollectedEnabled: boolean; siviSpeciesEnabled: boolean; siviIdentityEnabled: boolean;
    siviCreationEnabled: boolean; siviDeletionEnabled: boolean; siviRestorationEnabled: boolean; siviCreationUndoEnabled: boolean;
    siviPanelOpen: boolean; siviCoverPanelOpen: boolean; siviCombinedPanelOpen: boolean; siviCollectedPanelOpen: boolean; siviSpeciesPanelOpen: boolean; siviIdentityPanelOpen: boolean;
    siviView: SIVIHeightView | null; siviClose: EditorCloseState | null; siviUnsaved: boolean; siviEditingDisabled: boolean;
    siviCoverView: SIVICoverView | null; siviCoverClose: EditorCloseState | null; siviCoverUnsaved: boolean; siviCoverBusy: boolean; siviCoverReading: boolean; siviCoverEditingDisabled: boolean;
    siviCombinedView: SIVICombinedView | null; siviCombinedClose: EditorCloseState | null; siviCombinedUnsaved: boolean; siviCombinedBusy: boolean; siviCombinedReading: boolean; siviCombinedEditingDisabled: boolean;
    siviCollectedView: SIVICollectedView | null; siviCollectedClose: EditorCloseState | null; siviCollectedUnsaved: boolean; siviCollectedBusy: boolean; siviCollectedReading: boolean; siviCollectedEditingDisabled: boolean;
    siviSpeciesView: SIVISpeciesView | null; siviSpeciesClose: EditorCloseState | null; siviSpeciesUnsaved: boolean; siviSpeciesBusy: boolean; siviSpeciesReading: boolean; siviSpeciesEditingDisabled: boolean;
    siviIdentityView: SIVIIdentityView | null; siviIdentityClose: EditorCloseState | null; siviIdentityUnsaved: boolean; siviIdentityBusy: boolean; siviIdentityReading: boolean; siviIdentityEditingDisabled: boolean;
    siviDeletionView: SIVIDeletionView | undefined; siviDeletionClose: EditorCloseState | undefined; siviDeletionEditingDisabled: boolean; siviDeletionRecoveryDisabled: boolean;
    siviRestorationView: SIVIDeletionRestorationView | undefined; siviRestorationClose: EditorCloseState | undefined;
    siviRestorationTargets: Array<{ historyId: string; restored: boolean; label: string }>;
    siviRestorationEditingDisabled: boolean; siviRestorationRecoveryDisabled: boolean;
    siviCreationUndoView: SIVICreationUndoView | undefined; siviCreationUndoClose: EditorCloseState | undefined; siviCreationUndoEditingDisabled: boolean; siviCreationUndoRecoveryDisabled: boolean;
    siviCreationSession: SIVICreationSession | undefined; siviCreationView: SIVICreationView | undefined; siviCreationClose: EditorCloseState | undefined;
    siviCreationEditingDisabled: boolean; siviCreationRecoveryDisabled: boolean;
    codeCheckEnabled: boolean;
    onFindPlot?: () => void;
    markDirty: () => void;
    validateHeader: (key: string, message: string | null) => void;
    vegetationNotesTab: () => Promise<void>;
    openSpeciesCodeCheck: () => void;
    loadSpeciesReferences: () => Promise<void>;
    sourceRows: (name: string) => Array<{ id: number; values: Record<string, string | number | boolean | null | undefined> }>;
    startVegetationCreation: (form: string) => void;
    stageHeightCell: (id: number, column: string, raw: string, form: string) => void;
    stageCollectedCell: (id: number, form: string) => void;
    stageSpeciesCell: (form: string, id: number, raw: string) => void;
    reviewVegetationDeletion: (form: string, id: number) => Promise<void>;
    searchSpecies: () => Promise<void>;
    selectSpeciesToAdd: (sp: SpeciesItem) => Promise<void>;
    deleteVeg: (id: number) => Promise<void>;
    showSIVIPanel: () => Promise<void>;
    showSIVICoverPanel: () => Promise<void>;
    showSIVICombinedPanel: () => Promise<void>;
    showSIVICollectedPanel: () => Promise<void>;
    showSIVISpeciesPanel: () => Promise<void>;
    showSIVIIdentityPanel: () => Promise<void>;
    siviOperation: (op: 'load' | 'save' | 'undo' | 'retain' | 'prune') => Promise<boolean>;
    stageSIVICell: (rowId: string, column: SIVIHeightColumn, raw: string, nullValue: boolean) => void;
    siviCoverOperation: (op: 'load' | 'save' | 'undo' | 'retain' | 'prune') => Promise<boolean>;
    stageSIVICoverCell: (rowId: string, column: SIVICoverColumn, raw: string, nullValue: boolean) => void;
    onCancelSiviCoverRead: () => void;
    siviCombinedOperation: (op: 'load' | 'save' | 'undo' | 'retain' | 'prune') => Promise<boolean>;
    stageSIVICombinedCell: (rowId: string, column: SIVICombinedColumn, raw: string, nullValue: boolean) => void;
    onCancelSiviCombinedRead: () => void;
    siviCollectedOperation: (op: 'load' | 'save' | 'undo' | 'retain' | 'prune') => Promise<boolean>;
    cycleSIVICollected: (rowId: string) => void;
    onCancelSiviCollectedRead: () => void;
    siviSpeciesOperation: (op: 'load' | 'save' | 'undo' | 'retain' | 'prune') => Promise<boolean>;
    stageSIVISpecies: (rowId: string, command: 'Species' | 'context' | SpeciesDecisionKind, raw: string) => void;
    onCancelSiviSpeciesRead: () => void;
    siviIdentityOperation: (op: 'load' | 'save' | 'undo' | 'retain' | 'prune') => Promise<boolean>;
    stageSIVIIdentity: (rowId: string, raw: string, nullValue: boolean) => void;
    onCancelSiviIdentityRead: () => void;
    siviLifecycleOperation: (kind: 'deletion' | 'restoration', op: 'load' | 'history' | 'review' | 'save' | 'undo' | 'resolve' | 'cancel', identity?: string, form?: SIVICreationForm) => Promise<boolean>;
    stageSIVILifecycle: (kind: 'deletion' | 'restoration', confirmed: boolean, action?: 'retain' | 'prune') => void;
    siviCreationUndoOperation: (op: 'history' | 'review' | 'undo' | 'discard' | 'resolve' | 'cancel', historyId?: string) => Promise<boolean>;
    stageSIVICreationUndo: (confirmed: boolean, action?: 'retain' | 'prune') => void;
    siviCreationOperation: (op: 'load' | 'start' | 'save' | 'undo' | 'resolve' | 'cancel', form?: SIVICreationForm) => Promise<boolean>;
    stageSIVICreation: (draft: SIVICreationDraft) => void;
  } = $props();
</script>

{#if siviDeletionEnabled && siviDeletionView && siviDeletionClose}
  {#await import('./SIVIDeletionPanel.svelte')}
    <p role="status" class="p-2 text-xs">Loading SIVI deletion panel...</p>
  {:then { default: SIVIDeletionPanel }}
    <SIVIDeletionPanel view={siviDeletionView} close={siviDeletionClose} targets={siviDeletionView.targets ?? []}
      disabled={siviDeletionEditingDisabled} recoveryDisabled={siviDeletionRecoveryDisabled}
      onreview={(form, rowId) => void siviLifecycleOperation('deletion', 'review', rowId, form)}
      onconfirm={confirmed => stageSIVILifecycle('deletion', confirmed)}
      onoperation={operation => void siviLifecycleOperation('deletion', operation)} />
  {:catch loadError}
    <p role="alert" class="p-2 text-xs text-red-700">SIVI deletion panel could not load: {String(loadError)}</p>
  {/await}
{/if}
{#if siviRestorationEnabled && siviRestorationView && siviRestorationClose}
  {#await import('./SIVIDeletionRestorationPanel.svelte')}
    <p role="status" class="p-2 text-xs">Loading SIVI restoration panel...</p>
  {:then { default: SIVIDeletionRestorationPanel }}
    <SIVIDeletionRestorationPanel view={siviRestorationView} close={siviRestorationClose} targets={siviRestorationTargets}
      disabled={siviRestorationEditingDisabled} recoveryDisabled={siviRestorationRecoveryDisabled}
      onreview={historyId => void siviLifecycleOperation('restoration', 'review', historyId)}
      onchoose={action => stageSIVILifecycle('restoration', false, action)}
      onconfirm={confirmed => stageSIVILifecycle('restoration', confirmed)}
      onoperation={operation => void siviLifecycleOperation('restoration', operation)} />
  {:catch loadError}
    <p role="alert" class="p-2 text-xs text-red-700">SIVI restoration panel could not load: {String(loadError)}</p>
  {/await}
{/if}
{#if siviCreationUndoEnabled && siviCreationUndoView && siviCreationUndoClose}
  {#await import('./SIVICreationUndoPanel.svelte')}
    <p role="status" class="p-2 text-xs">Loading SIVI creation undo panel...</p>
  {:then { default: SIVICreationUndoPanel }}
    <SIVICreationUndoPanel view={siviCreationUndoView} close={siviCreationUndoClose}
      disabled={siviCreationUndoEditingDisabled} recoveryDisabled={siviCreationUndoRecoveryDisabled}
      onreview={historyId => void siviCreationUndoOperation('review', historyId)}
      onchoose={action => stageSIVICreationUndo(false, action)}
      onconfirm={confirmed => stageSIVICreationUndo(confirmed)}
      onoperation={operation => void siviCreationUndoOperation(operation)} />
  {:catch loadError}
    <p role="alert" class="p-2 text-xs text-red-700">SIVI creation undo panel could not load: {String(loadError)}</p>
  {/await}
{/if}
{#if siviCreationEnabled && siviCreationSession && siviCreationView && siviCreationClose}
  {#await import('./SIVICreationPanel.svelte')}
    <p role="status" class="p-2 text-xs">Loading SIVI creation panel...</p>
  {:then { default: SIVICreationPanel }}
    <SIVICreationPanel view={siviCreationView} close={siviCreationClose}
      owner={{ contextId: siviContextId, project: siviCreationView.references?.project ?? activeProject, plot: original?.plotNumber ?? '' }}
      disabled={siviCreationEditingDisabled} recoveryDisabled={siviCreationRecoveryDisabled}
      onoperation={(operation, form) => void siviCreationOperation(operation, form)} onchange={stageSIVICreation} />
  {:catch loadError}
    <p role="alert" class="p-2 text-xs text-red-700">SIVI creation panel could not load: {String(loadError)}</p>
  {/await}
{/if}
{#if siviHeightEnabled}
  <button type="button" class="mb-3 rounded border px-3 py-1 disabled:opacity-50" data-sivi-open
    disabled={busy || headerWorkflowBusy || !siviPanelOpen && siviEditingDisabled && !siviUnsaved}
    onclick={() => void showSIVIPanel()}>{siviPanelOpen ? (siviStandalone ? 'Close height view' : 'Return to FS882 vegetation') : 'Show SIVI aggregate heights (height-only)'}</button>
{/if}
{#if siviCoverEnabled}
  <button type="button" class="mb-3 rounded border px-3 py-1 disabled:opacity-50" data-sivi-cover-open
    disabled={busy || headerWorkflowBusy || !siviCoverPanelOpen && siviCoverEditingDisabled && !siviCoverUnsaved}
    onclick={() => void showSIVICoverPanel()}>{siviCoverPanelOpen ? (siviStandalone ? 'Close cover view' : 'Return to FS882 vegetation') : 'Show SIVI source covers'}</button>
{/if}
{#if siviCombinedEnabled}
  <button type="button" class="mb-3 rounded border px-3 py-1 disabled:opacity-50" data-sivi-combined-open
    disabled={busy || headerWorkflowBusy || !siviCombinedPanelOpen && siviCombinedEditingDisabled && !siviCombinedUnsaved}
    onclick={() => void showSIVICombinedPanel()}>{siviCombinedPanelOpen ? 'Close combined view' : 'Show combined SIVI covers and heights'}</button>
{/if}
{#if siviCollectedEnabled}
  <button type="button" class="mb-3 rounded border px-3 py-1 disabled:opacity-50" data-sivi-collected-open
    disabled={busy || headerWorkflowBusy || !siviCollectedPanelOpen && siviCollectedEditingDisabled && !siviCollectedUnsaved}
    onclick={() => void showSIVICollectedPanel()}>{siviCollectedPanelOpen ? 'Close Collected view' : 'Show SIVI Collected cycles'}</button>
{/if}
{#if siviSpeciesEnabled}
  <button type="button" class="rounded border px-3 py-1 disabled:opacity-50" data-sivi-species-open
    disabled={busy || headerWorkflowBusy || !siviSpeciesPanelOpen && siviSpeciesEditingDisabled && !siviSpeciesUnsaved}
    onclick={() => void showSIVISpeciesPanel()}>{siviSpeciesPanelOpen ? 'Close Species view' : 'Show SIVI Species'}</button>
{/if}
{#if siviIdentityEnabled}
  <button type="button" class="rounded border px-3 py-1 disabled:opacity-50" data-sivi-identity-open
    disabled={busy || headerWorkflowBusy || !siviIdentityPanelOpen && siviIdentityEditingDisabled && !siviIdentityUnsaved}
    onclick={() => void showSIVIIdentityPanel()}>{siviIdentityPanelOpen ? 'Close ID view' : 'Show SIVI IDs'}</button>
{/if}
{#if extendedShrubs && !siviPanelOpen && !siviCoverPanelOpen && !siviCombinedPanelOpen && !siviCollectedPanelOpen && !siviSpeciesPanelOpen && !siviIdentityPanelOpen}
  <p class="mb-3 text-sm" role="status">{extendedShrubsNotice}</p>
{/if}
{#if siviIdentityPanelOpen && siviIdentityView}
  {#if siviIdentityReading && siviIdentityBusy}
    <button type="button" class="rounded border px-3 py-1" data-sivi-identity-cancel-read onclick={onCancelSiviIdentityRead}>Cancel ID source read</button>
  {/if}
  {#await import('./SIVIIdentityPanel.svelte')}
    <p role="status" class="p-2 text-xs">Loading SIVI ID panel...</p>
  {:then { default: SIVIIdentityPanel }}
    <SIVIIdentityPanel view={siviIdentityView} disabled={siviIdentityEditingDisabled} canSave={siviIdentityClose?.canSave ?? false}
      onstage={stageSIVIIdentity} onsave={() => void siviIdentityOperation('save')} onundo={() => void siviIdentityOperation('undo')}
      onreload={() => void siviIdentityOperation('load')}
      onrestore={(action) => void siviIdentityOperation(action === AuditRestoreAction.AuditRestoreRetain ? 'retain' : 'prune')} />
  {:catch loadError}
    <p role="alert" class="p-2 text-xs text-red-700">SIVI ID panel could not load: {String(loadError)}</p>
  {/await}
{:else if siviSpeciesPanelOpen && siviSpeciesView}
  {#if siviSpeciesReading && siviSpeciesBusy}
    <button type="button" class="rounded border px-3 py-1" data-sivi-species-cancel-read onclick={onCancelSiviSpeciesRead}>Cancel Species source/reference read</button>
  {/if}
  {#await import('./SIVISpeciesPanel.svelte')}
    <p role="status" class="p-2 text-xs">Loading SIVI Species panel...</p>
  {:then { default: SIVISpeciesPanel }}
    <SIVISpeciesPanel view={siviSpeciesView} disabled={siviSpeciesEditingDisabled} canSave={siviSpeciesClose?.canSave ?? false}
      onstage={(rowId, raw) => stageSIVISpecies(rowId, 'Species', raw)}
      oncontext={(rowId, group) => stageSIVISpecies(rowId, 'context', String(group))}
      onchoose={(rowId, kind, selected) => stageSIVISpecies(rowId, kind, selected ?? '')}
      onsave={() => void siviSpeciesOperation('save')} onundo={() => void siviSpeciesOperation('undo')}
      onreload={() => void siviSpeciesOperation('load')} onrestore={(action) => void siviSpeciesOperation(action === AuditRestoreAction.AuditRestoreRetain ? 'retain' : 'prune')} />
  {:catch loadError}
    <p role="alert" class="p-2 text-xs text-red-700">SIVI Species panel could not load: {String(loadError)}</p>
  {/await}
{:else if siviCollectedPanelOpen && siviCollectedView}
  {#if siviCollectedReading && siviCollectedBusy}
    <button type="button" class="mb-3 rounded border px-3 py-1" data-sivi-collected-cancel-read onclick={onCancelSiviCollectedRead}>Cancel Collected source read</button>
  {/if}
  {#await import('./SIVICollectedPanel.svelte')}
    <p role="status" class="p-2 text-xs">Loading SIVI Collected panel...</p>
  {:then { default: SIVICollectedPanel }}
    <SIVICollectedPanel view={siviCollectedView} disabled={siviCollectedEditingDisabled} canSave={siviCollectedClose?.canSave ?? false}
      oncycle={cycleSIVICollected} onsave={() => void siviCollectedOperation('save')} onundo={() => void siviCollectedOperation('undo')}
      onreload={() => void siviCollectedOperation('load')} onrestore={(action) => void siviCollectedOperation(action === AuditRestoreAction.AuditRestoreRetain ? 'retain' : 'prune')} />
  {:catch loadError}
    <p role="alert" class="p-2 text-xs text-red-700">SIVI Collected panel could not load: {String(loadError)}</p>
  {/await}
{:else if siviCombinedPanelOpen && siviCombinedView}
  {#if siviCombinedReading && siviCombinedBusy}
    <button type="button" class="mb-3 rounded border px-3 py-1" data-sivi-combined-cancel-read onclick={onCancelSiviCombinedRead}>Cancel combined source read</button>
  {/if}
  {#await import('./SIVICombinedPanel.svelte')}
    <p role="status" class="p-2 text-xs">Loading SIVI combined panel...</p>
  {:then { default: SIVICombinedPanel }}
    <SIVICombinedPanel view={siviCombinedView} disabled={siviCombinedEditingDisabled} canSave={siviCombinedClose?.canSave ?? false}
      onstage={stageSIVICombinedCell} onsave={() => void siviCombinedOperation('save')} onundo={() => void siviCombinedOperation('undo')}
      onreload={() => void siviCombinedOperation('load')} onrestore={(action) => void siviCombinedOperation(action === AuditRestoreAction.AuditRestoreRetain ? 'retain' : 'prune')} />
  {:catch loadError}
    <p role="alert" class="p-2 text-xs text-red-700">SIVI combined panel could not load: {String(loadError)}</p>
  {/await}
{:else if siviPanelOpen && siviView}
  {#await import('./SIVIHeightPanel.svelte')}
    <p role="status" class="p-2 text-xs">Loading SIVI height panel...</p>
  {:then { default: SIVIHeightPanel }}
    <SIVIHeightPanel view={siviView} disabled={siviEditingDisabled} canSave={siviClose?.canSave ?? false}
      onstage={stageSIVICell} onsave={() => void siviOperation('save')} onundo={() => void siviOperation('undo')}
      onreload={() => void siviOperation('load')} onrestore={(action) => void siviOperation(action === AuditRestoreAction.AuditRestoreRetain ? 'retain' : 'prune')} />
  {:catch loadError}
    <p role="alert" class="p-2 text-xs text-red-700">SIVI height panel could not load: {String(loadError)}</p>
  {/await}
{:else if siviCoverPanelOpen && siviCoverView}
  {#if siviCoverReading && siviCoverBusy}
    <button type="button" class="mb-3 rounded border px-3 py-1" data-sivi-cover-cancel-read onclick={onCancelSiviCoverRead}>Cancel source cover read</button>
  {/if}
  {#await import('./SIVICoverPanel.svelte')}
    <p role="status" class="p-2 text-xs">Loading SIVI cover panel...</p>
  {:then { default: SIVICoverPanel }}
    <SIVICoverPanel view={siviCoverView} disabled={siviCoverEditingDisabled} canSave={siviCoverClose?.canSave ?? false}
      onstage={stageSIVICoverCell} onsave={() => void siviCoverOperation('save')} onundo={() => void siviCoverOperation('undo')}
      onreload={() => void siviCoverOperation('load')} onrestore={(action) => void siviCoverOperation(action === AuditRestoreAction.AuditRestoreRetain ? 'retain' : 'prune')} />
  {:catch loadError}
    <p role="alert" class="p-2 text-xs text-red-700">SIVI cover panel could not load: {String(loadError)}</p>
  {/await}
{:else if vegetationReadUnavailable}
  <p role="alert" class="p-4">Ordinary ID-keyed vegetation is unavailable: {vegetationReadUnavailable}
    Independently enabled physical-row SIVI views remain available; no NULL identity is converted to zero and no row is omitted from an ordinary result.</p>
{:else if siviStandalone}
  <p role="status" class="p-4">SIVI vegetation preserves the three PlotNumber-linked source groups: A (trees/shrubs), C and D.
    Choose an independently enabled source view above. Species creation/deletion and original species-list callbacks remain unavailable.</p>
{:else}
  {#if speciesEditingEnabled || creationEnabled}
    {#if speciesReferenceBusy}<p role="status">Loading source species lists...</p>{/if}
    {#if speciesReferenceError}<p role="alert">{speciesReferenceError}</p>{/if}
    <button type="button" class="mb-2 px-2 py-1 border rounded" disabled={busy || speciesReferenceBusy || headerWorkflowBusy}
      onclick={() => void loadSpeciesReferences()}>{speciesReferenceError ? 'Retry species references' : 'Reload species references'}</button>
  {/if}
  <OrdinaryFields bind:draft {original} {capabilities} scope="veg"
    disabled={headerInputsDisabled}
    onchange={markDirty} onvalidation={validateHeader} onVegNotesTab={vegetationNotesTab}>
    {#snippet children(ordinaryEditor)}
      <SourcePage name="Vegetation" values={sourceHeaderValues} {vegetationMode} editor={ordinaryEditor}
        onHeightToggle={() => vegetationMode = vegetationMode === 'height' ? 'cover' : 'height'}
        heightToggleDisabled={extendedShrubs || busy || headerWorkflowBusy}
        {onFindPlot} findPlotDisabled={busy || headerWorkflowBusy || !capabilitiesReady}
        onSpeciesCheck={codeCheckEnabled ? openSpeciesCodeCheck : undefined}
        speciesCheckDisabled={childParentDisabled || childUnsaved || Object.keys(headerValidation).length > 0}>
        {#snippet embedded(control)}
          {@const originalChild = embeddedForm(control.controlId)}
          {@const child = { ...originalChild, form: extendedShrubs && originalChild.form === 'SubVegAXL_BC' ? 'SubVegAXL' : originalChild.form }}
          {@const heightGrid = child.form === 'SubVegAhtXL' || child.form === 'SubVegChtXL'}
          {#if creationEnabled}
            <button type="button" class="mb-2 rounded border px-2 py-1 text-xs disabled:opacity-50" data-create-source={child.form}
              disabled={childParentDisabled || childUnsaved || !speciesReferenceReady || speciesReferenceBusy}
              onclick={() => startVegetationCreation(child.form)}>New vegetation record - {child.form}</button>
          {/if}
          <SourceChild name={child.form} rows={sourceRows(child.form)} revision={childRevision}
            disabled={heightGrid || numberEditingEnabled ? heightEditingDisabled : childEditingDisabled}
            drafts={heightDrafts} onstage={numberEditingEnabled ? (id, column, raw) => stageHeightCell(id, column, raw, child.form) : undefined}
            {collectedDrafts} collectedDisabled={collectedEditingDisabled}
            oncollectedstage={collectedEditingEnabled ? stageCollectedCell : undefined}
            {speciesDrafts} {speciesLists} speciesDisabled={speciesEditingDisabled}
            onspeciesstage={speciesEditingEnabled ? stageSpeciesCell : undefined}
            onedit={undefined} ondelete={deletionEnabled ? reviewVegetationDeletion : undefined} deleteDisabled={childUnsaved} />
        {/snippet}
      </SourcePage>
    {/snippet}
  </OrdinaryFields>
{/if}
{#if vegetationMode === 'height'}
  <p class="mt-2 text-xs text-vpro-ink-muted">{numberEditingEnabled ? 'Cover and height values validate against LMH25 (< 100%) single-precision bounds; use Save or Cancel to commit or discard drafts.' : 'Cover/height cells are read-only.'} Switching view does not save or alter data.</p>
{/if}
{#if collectedEditingEnabled}
  <p class="mt-2 text-xs text-vpro-ink-muted">Collected buttons cycle NULL -> C -> V -> NULL using persistent drafts. Other historical values remain unchanged, as in the source click event. Use Save or Cancel; {creationEnabled ? 'new rows use a separate explicit source creation draft.' : 'new-row workflows remain unavailable in the source grids.'}</p>
{/if}
{#if numberEditingEnabled}
  <p class="mt-2 text-xs text-vpro-ink-muted">All source cover/total and height fields share persistent drafts. Switching grids retains raw errors and original values; Save checks each field's original source row and commits changes/audits atomically. Clearing cover may remove a row from a source view, never delete the vegetation record.</p>
{/if}
<p class="mt-2 text-xs text-vpro-ink-muted">{speciesEditingEnabled ? `Species selection uses canonical source lists and explicit old-code replace/keep or existing personal-code decisions. Decisions stage the source UCase event; Save remains separate. ${personalSpeciesEnabled ? 'Unknown-code personal definitions use a separate explicit user-database save; plot Save and Undo remain independent.' : 'Personal-list creation remains unavailable.'}` : 'Species editing remains read-only pending native verification.'}</p>
<FS882StratumSummary {vegList} {totalTreeCover} {totalShrubCover} {totalHerbCover} {totalMossCover}
  onopenspeciesmodal={() => { showSpeciesModal = true; }} ondeleteveg={deleteVeg} />
<FS882ChildCreateModal region="speciesModal" bind:showSpeciesModal bind:speciesSearchQuery
  {speciesSearchResults} {searchingSpecies} {searchSpecies} {selectSpeciesToAdd} />
