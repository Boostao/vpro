<script lang="ts">
  import { AuditRestoreAction, type FS882Header } from '../../bindings/github.com/boostao/vpro/app';
  import { formatError } from '../shared/readRequests';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import type { SiviSessionsController } from './useSiviSessions.svelte';

  let {
    sivi,
    original,
    siviContextId,
    activeProject,
    busy,
    headerWorkflowBusy,
    siviStandalone,
    extendedShrubs,
    extendedShrubsNotice,
  }: {
    sivi: SiviSessionsController;
    original: FS882Header | null;
    siviContextId: string;
    activeProject: string;
    busy: boolean;
    headerWorkflowBusy: boolean;
    siviStandalone: boolean;
    extendedShrubs: boolean;
    extendedShrubsNotice: string;
  } = $props();

  const anySiviVegPanelOpen = $derived(
    sivi.heightPanelOpen ||
      sivi.coverPanelOpen ||
      sivi.combinedPanelOpen ||
      sivi.collectedPanelOpen ||
      sivi.speciesPanelOpen ||
      sivi.identityPanelOpen
  );
</script>

{#if !IS_WEB_READONLY && sivi.deletionView && sivi.deletionClose}
  {#await import('./SIVIDeletionPanel.svelte')}
    <p role="status" class="p-2 text-xs">Loading SIVI deletion panel...</p>
  {:then { default: SIVIDeletionPanel }}
    <SIVIDeletionPanel
      view={sivi.deletionView}
      close={sivi.deletionClose}
      targets={sivi.deletionView.targets ?? []}
      disabled={sivi.deletionEditingDisabled}
      recoveryDisabled={sivi.deletionRecoveryDisabled}
      onreview={(form, rowId) => void sivi.lifecycleOperation('deletion', 'review', rowId, form)}
      onconfirm={(confirmed) => sivi.stageLifecycle('deletion', confirmed)}
      onoperation={(operation) => void sivi.lifecycleOperation('deletion', operation)}
    />
  {:catch loadError}
    <p role="alert" class="p-2 text-xs text-red-700">SIVI deletion panel could not load: {formatError(loadError)}</p>
  {/await}
{/if}

{#if !IS_WEB_READONLY && sivi.restorationView && sivi.restorationClose}
  {#await import('./SIVIDeletionRestorationPanel.svelte')}
    <p role="status" class="p-2 text-xs">Loading SIVI restoration panel...</p>
  {:then { default: SIVIDeletionRestorationPanel }}
    <SIVIDeletionRestorationPanel
      view={sivi.restorationView}
      close={sivi.restorationClose}
      targets={sivi.restorationTargets}
      disabled={sivi.restorationEditingDisabled}
      recoveryDisabled={sivi.restorationRecoveryDisabled}
      onreview={(historyId) => void sivi.lifecycleOperation('restoration', 'review', historyId)}
      onchoose={(action) => sivi.stageLifecycle('restoration', false, action)}
      onconfirm={(confirmed) => sivi.stageLifecycle('restoration', confirmed)}
      onoperation={(operation) => void sivi.lifecycleOperation('restoration', operation)}
    />
  {:catch loadError}
    <p role="alert" class="p-2 text-xs text-red-700">SIVI restoration panel could not load: {formatError(loadError)}</p>
  {/await}
{/if}

{#if !IS_WEB_READONLY && sivi.creationUndoView && sivi.creationUndoClose}
  {#await import('./SIVICreationUndoPanel.svelte')}
    <p role="status" class="p-2 text-xs">Loading SIVI creation undo panel...</p>
  {:then { default: SIVICreationUndoPanel }}
    <SIVICreationUndoPanel
      view={sivi.creationUndoView}
      close={sivi.creationUndoClose}
      disabled={sivi.creationUndoEditingDisabled}
      recoveryDisabled={sivi.creationUndoRecoveryDisabled}
      onreview={(historyId) => void sivi.creationUndoOperation('review', historyId)}
      onchoose={(action) => sivi.stageCreationUndo(false, action)}
      onconfirm={(confirmed) => sivi.stageCreationUndo(confirmed)}
      onoperation={(operation) => void sivi.creationUndoOperation(operation)}
    />
  {:catch loadError}
    <p role="alert" class="p-2 text-xs text-red-700">
      SIVI creation undo panel could not load: {formatError(loadError)}
    </p>
  {/await}
{/if}

{#if !IS_WEB_READONLY && sivi.creationSession && sivi.creationView && sivi.creationClose}
  {#await import('./SIVICreationPanel.svelte')}
    <p role="status" class="p-2 text-xs">Loading SIVI creation panel...</p>
  {:then { default: SIVICreationPanel }}
    <SIVICreationPanel
      view={sivi.creationView}
      close={sivi.creationClose}
      owner={{
        contextId: siviContextId,
        project: sivi.creationView.references?.project ?? activeProject,
        plot: original?.plotNumber ?? '',
      }}
      disabled={sivi.creationEditingDisabled}
      recoveryDisabled={sivi.creationRecoveryDisabled}
      onoperation={(operation, form) => void sivi.creationOperation(operation, form)}
      onchange={sivi.stageCreation}
    />
  {:catch loadError}
    <p role="alert" class="p-2 text-xs text-red-700">SIVI creation panel could not load: {formatError(loadError)}</p>
  {/await}
{/if}

<button
  type="button"
  class="mb-3 rounded border px-3 py-1 disabled:opacity-50"
  data-sivi-open
  disabled={busy || headerWorkflowBusy || (!sivi.heightPanelOpen && sivi.heightEditingDisabled && !sivi.heightUnsaved)}
  onclick={() => void sivi.showHeightPanel()}
>
  {sivi.heightPanelOpen
    ? siviStandalone
      ? 'Close height view'
      : 'Return to FS882 vegetation'
    : 'Show SIVI aggregate heights (height-only)'}
</button>
<button
  type="button"
  class="mb-3 rounded border px-3 py-1 disabled:opacity-50"
  data-sivi-cover-open
  disabled={busy || headerWorkflowBusy || (!sivi.coverPanelOpen && sivi.coverEditingDisabled && !sivi.coverUnsaved)}
  onclick={() => void sivi.showCoverPanel()}
>
  {sivi.coverPanelOpen
    ? siviStandalone
      ? 'Close cover view'
      : 'Return to FS882 vegetation'
    : 'Show SIVI source covers'}
</button>
<button
  type="button"
  class="mb-3 rounded border px-3 py-1 disabled:opacity-50"
  data-sivi-combined-open
  disabled={busy ||
    headerWorkflowBusy ||
    (!sivi.combinedPanelOpen && sivi.combinedEditingDisabled && !sivi.combinedUnsaved)}
  onclick={() => void sivi.showCombinedPanel()}
>
  {sivi.combinedPanelOpen ? 'Close combined view' : 'Show combined SIVI covers and heights'}
</button>
<button
  type="button"
  class="mb-3 rounded border px-3 py-1 disabled:opacity-50"
  data-sivi-collected-open
  disabled={busy ||
    headerWorkflowBusy ||
    (!sivi.collectedPanelOpen && sivi.collectedEditingDisabled && !sivi.collectedUnsaved)}
  onclick={() => void sivi.showCollectedPanel()}
>
  {sivi.collectedPanelOpen ? 'Close Collected view' : 'Show SIVI Collected cycles'}
</button>
<button
  type="button"
  class="rounded border px-3 py-1 disabled:opacity-50"
  data-sivi-species-open
  disabled={busy ||
    headerWorkflowBusy ||
    (!sivi.speciesPanelOpen && sivi.speciesEditingDisabled && !sivi.speciesUnsaved)}
  onclick={() => void sivi.showSpeciesPanel()}
>
  {sivi.speciesPanelOpen ? 'Close Species view' : 'Show SIVI Species'}
</button>
<button
  type="button"
  class="rounded border px-3 py-1 disabled:opacity-50"
  data-sivi-identity-open
  disabled={busy ||
    headerWorkflowBusy ||
    (!sivi.identityPanelOpen && sivi.identityEditingDisabled && !sivi.identityUnsaved)}
  onclick={() => void sivi.showIdentityPanel()}
>
  {sivi.identityPanelOpen ? 'Close ID view' : 'Show SIVI IDs'}
</button>

{#if extendedShrubs && !anySiviVegPanelOpen}
  <p class="mb-3 text-sm" role="status">{extendedShrubsNotice}</p>
{/if}

{#if sivi.identityPanelOpen && sivi.identityView}
  {#if sivi.identityReading && sivi.identityBusy}
    <button
      type="button"
      class="rounded border px-3 py-1"
      data-sivi-identity-cancel-read
      onclick={sivi.cancelIdentityRead}>Cancel ID source read</button
    >
  {/if}
  {#await import('./SIVIIdentityPanel.svelte')}
    <p role="status" class="p-2 text-xs">Loading SIVI ID panel...</p>
  {:then { default: SIVIIdentityPanel }}
    <SIVIIdentityPanel
      view={sivi.identityView}
      disabled={sivi.identityEditingDisabled}
      canSave={sivi.identityClose?.canSave ?? false}
      onstage={sivi.stageIdentity}
      onsave={() => void sivi.identityOperation('save')}
      onundo={() => void sivi.identityOperation('undo')}
      onreload={() => void sivi.identityOperation('load')}
      onrestore={(action) =>
        void sivi.identityOperation(action === AuditRestoreAction.AuditRestoreRetain ? 'retain' : 'prune')}
    />
  {:catch loadError}
    <p role="alert" class="p-2 text-xs text-red-700">SIVI ID panel could not load: {formatError(loadError)}</p>
  {/await}
{:else if sivi.speciesPanelOpen && sivi.speciesView}
  {#if sivi.speciesReading && sivi.speciesBusy}
    <button
      type="button"
      class="rounded border px-3 py-1"
      data-sivi-species-cancel-read
      onclick={sivi.cancelSpeciesRead}>Cancel Species source/reference read</button
    >
  {/if}
  {#await import('./SIVISpeciesPanel.svelte')}
    <p role="status" class="p-2 text-xs">Loading SIVI Species panel...</p>
  {:then { default: SIVISpeciesPanel }}
    <SIVISpeciesPanel
      view={sivi.speciesView}
      disabled={sivi.speciesEditingDisabled}
      canSave={sivi.speciesClose?.canSave ?? false}
      onstage={(rowId, raw) => sivi.stageSpecies(rowId, 'Species', raw)}
      oncontext={(rowId, group) => sivi.stageSpecies(rowId, 'context', String(group))}
      onchoose={(rowId, kind, selected) => sivi.stageSpecies(rowId, kind, selected ?? '')}
      onsave={() => void sivi.speciesOperation('save')}
      onundo={() => void sivi.speciesOperation('undo')}
      onreload={() => void sivi.speciesOperation('load')}
      onrestore={(action) =>
        void sivi.speciesOperation(action === AuditRestoreAction.AuditRestoreRetain ? 'retain' : 'prune')}
    />
  {:catch loadError}
    <p role="alert" class="p-2 text-xs text-red-700">SIVI Species panel could not load: {formatError(loadError)}</p>
  {/await}
{:else if sivi.collectedPanelOpen && sivi.collectedView}
  {#if sivi.collectedReading && sivi.collectedBusy}
    <button
      type="button"
      class="mb-3 rounded border px-3 py-1"
      data-sivi-collected-cancel-read
      onclick={sivi.cancelCollectedRead}>Cancel Collected source read</button
    >
  {/if}
  {#await import('./SIVICollectedPanel.svelte')}
    <p role="status" class="p-2 text-xs">Loading SIVI Collected panel...</p>
  {:then { default: SIVICollectedPanel }}
    <SIVICollectedPanel
      view={sivi.collectedView}
      disabled={sivi.collectedEditingDisabled}
      canSave={sivi.collectedClose?.canSave ?? false}
      oncycle={sivi.cycleCollected}
      onsave={() => void sivi.collectedOperation('save')}
      onundo={() => void sivi.collectedOperation('undo')}
      onreload={() => void sivi.collectedOperation('load')}
      onrestore={(action) =>
        void sivi.collectedOperation(action === AuditRestoreAction.AuditRestoreRetain ? 'retain' : 'prune')}
    />
  {:catch loadError}
    <p role="alert" class="p-2 text-xs text-red-700">SIVI Collected panel could not load: {formatError(loadError)}</p>
  {/await}
{:else if sivi.combinedPanelOpen && sivi.combinedView}
  {#if sivi.combinedReading && sivi.combinedBusy}
    <button
      type="button"
      class="mb-3 rounded border px-3 py-1"
      data-sivi-combined-cancel-read
      onclick={sivi.cancelCombinedRead}>Cancel combined source read</button
    >
  {/if}
  {#await import('./SIVICombinedPanel.svelte')}
    <p role="status" class="p-2 text-xs">Loading SIVI combined panel...</p>
  {:then { default: SIVICombinedPanel }}
    <SIVICombinedPanel
      view={sivi.combinedView}
      disabled={sivi.combinedEditingDisabled}
      canSave={sivi.combinedClose?.canSave ?? false}
      onstage={sivi.stageCombinedCell}
      onsave={() => void sivi.combinedOperation('save')}
      onundo={() => void sivi.combinedOperation('undo')}
      onreload={() => void sivi.combinedOperation('load')}
      onrestore={(action) =>
        void sivi.combinedOperation(action === AuditRestoreAction.AuditRestoreRetain ? 'retain' : 'prune')}
    />
  {:catch loadError}
    <p role="alert" class="p-2 text-xs text-red-700">SIVI combined panel could not load: {formatError(loadError)}</p>
  {/await}
{:else if sivi.heightPanelOpen && sivi.heightView}
  {#await import('./SIVIHeightPanel.svelte')}
    <p role="status" class="p-2 text-xs">Loading SIVI height panel...</p>
  {:then { default: SIVIHeightPanel }}
    <SIVIHeightPanel
      view={sivi.heightView}
      disabled={sivi.heightEditingDisabled}
      canSave={sivi.heightClose?.canSave ?? false}
      onstage={sivi.stageHeightCell}
      onsave={() => void sivi.heightOperation('save')}
      onundo={() => void sivi.heightOperation('undo')}
      onreload={() => void sivi.heightOperation('load')}
      onrestore={(action) =>
        void sivi.heightOperation(action === AuditRestoreAction.AuditRestoreRetain ? 'retain' : 'prune')}
    />
  {:catch loadError}
    <p role="alert" class="p-2 text-xs text-red-700">SIVI height panel could not load: {formatError(loadError)}</p>
  {/await}
{:else if sivi.coverPanelOpen && sivi.coverView}
  {#if sivi.coverReading && sivi.coverBusy}
    <button
      type="button"
      class="mb-3 rounded border px-3 py-1"
      data-sivi-cover-cancel-read
      onclick={sivi.cancelCoverRead}>Cancel source cover read</button
    >
  {/if}
  {#await import('./SIVICoverPanel.svelte')}
    <p role="status" class="p-2 text-xs">Loading SIVI cover panel...</p>
  {:then { default: SIVICoverPanel }}
    <SIVICoverPanel
      view={sivi.coverView}
      disabled={sivi.coverEditingDisabled}
      canSave={sivi.coverClose?.canSave ?? false}
      onstage={sivi.stageCoverCell}
      onsave={() => void sivi.coverOperation('save')}
      onundo={() => void sivi.coverOperation('undo')}
      onreload={() => void sivi.coverOperation('load')}
      onrestore={(action) =>
        void sivi.coverOperation(action === AuditRestoreAction.AuditRestoreRetain ? 'retain' : 'prune')}
    />
  {:catch loadError}
    <p role="alert" class="p-2 text-xs text-red-700">SIVI cover panel could not load: {formatError(loadError)}</p>
  {/await}
{/if}
