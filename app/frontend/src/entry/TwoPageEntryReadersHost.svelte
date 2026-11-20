<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { EditorCloseState } from '../shell/closeLifecycle';
  import type { FieldCardViewModel } from './fieldCardPreview';
  import FieldCardPreviewModal from './FieldCardPreviewModal.svelte';
  import type { TwoPageParentForm } from './twoPageParentSession';
  import type { TwoPageEntrySession } from './twoPageEntrySession';
  import type { TwoPageEntryReadersController } from './useTwoPageEntryReaders.svelte';
  import ExternalSUEnvironmentTransfer from '../classification/ExternalSUEnvironmentTransfer.svelte';
  import TwoPageAuditPanel from './TwoPageAuditPanel.svelte';
  import TwoPageGoogleEarthPanel from './TwoPageGoogleEarthPanel.svelte';
  import TwoPageVegetationTablePanel from './TwoPageVegetationTablePanel.svelte';
  import TwoPageEnvironmentTablePanel from './TwoPageEnvironmentTablePanel.svelte';
  import TwoPageProjectMetadataPanel from './TwoPageProjectMetadataPanel.svelte';
  import ProjectMetadataEditor from '../admin/ProjectMetadataEditor.svelte';
  import TwoPageProfilingPanel from './TwoPageProfilingPanel.svelte';

  let {
    readers,
    owner,
    form,
    view,
    close,
    error = $bindable(),
    childBlocked,
    fieldCardModalOpen = $bindable(false),
    fieldCardSplitOpen = $bindable(false),
    fieldCardViewModel = null,
    onOpenProfileSU,
    onclosemetadataeditor,
    onrestoredaudit,
    formPane,
  }: {
    readers: TwoPageEntryReadersController;
    owner: { contextId: string; project: string; plot: string };
    form: TwoPageParentForm;
    view: ReturnType<TwoPageEntrySession['view']>;
    close: EditorCloseState;
    error: string | null;
    childBlocked: boolean;
    fieldCardModalOpen?: boolean;
    fieldCardSplitOpen?: boolean;
    fieldCardViewModel?: FieldCardViewModel | null;
    onOpenProfileSU?: () => void;
    onclosemetadataeditor: () => void;
    onrestoredaudit: () => Promise<void>;
    formPane: Snippet;
  } = $props();
</script>

{#if error}
  <div
    role="alert"
    class="rounded border border-vpro-error-border bg-vpro-error-bg px-3 py-2 text-xs text-vpro-error-ink flex items-center justify-between gap-2"
  >
    <span>{error}</span>
    <button
      type="button"
      class="rounded border border-vpro-error-border bg-white px-2 py-0.5 text-[11px] font-medium text-vpro-error-ink hover:bg-vpro-error-bg"
      onclick={() => {
        error = null;
      }}>Dismiss</button
    >
  </div>
{/if}
{#if view.error && view.error !== error}<p role="alert" class="text-sm text-vpro-error">{view.error}</p>{/if}
{#if view.referenceError}<p role="alert" class="text-sm text-vpro-error">{view.referenceError}</p>{/if}
{#if view.blocked}<p
    role="alert"
    class="rounded border border-vpro-error-border bg-vpro-error-bg px-3 py-2 text-xs text-vpro-error-ink"
  >
    Write outcome or refresh is unresolved. Undo / reload explicitly; never replay Save.
  </p>{/if}
{#if view.busy || view.referencesBusy}<p role="status" class="text-xs font-medium text-vpro-navy">
    {view.operation === 'save' ? 'Saving plot changes...' : 'Loading two-page plot data...'}
  </p>{/if}

{#if readers.profilingOpen && readers.profileSource}
  <p role="status" class="text-xs font-semibold text-vpro-navy">Plot {owner.plot} — Plot Profiling</p>
  <TwoPageProfilingPanel
    contextId={owner.contextId}
    project={owner.project}
    plot={owner.plot}
    {form}
    projectPath={readers.vegetationScope.projectPath}
    su={readers.vegetationScope.su}
    suPath={readers.vegetationScope.suPath}
    profileSource={readers.profileSource}
    onBusyChange={(value) => {
      readers.profilingBusy = value;
    }}
  />
  <div class="flex flex-wrap gap-2">
    <button
      type="button"
      class="rounded border border-vpro-border bg-white px-3 py-1.5 text-xs text-vpro-ink"
      disabled={readers.profilingBusy}
      onclick={readers.returnFromProfiling}>Back to Two-Page Form</button
    >
    {#if onOpenProfileSU}
      <button
        type="button"
        data-two-page-create-su-link
        class="rounded bg-vpro-navy px-3 py-1.5 text-xs font-medium text-white disabled:opacity-50"
        disabled={readers.profilingBusy || childBlocked || close.unsaved || close.busy || close.blocked}
        onclick={onOpenProfileSU}>Manage Plot Profile / Save as Site Unit</button
      >
    {/if}
  </div>
{:else if readers.projectMetadataOpen === 'edit'}
  <p role="status" class="text-xs font-semibold text-vpro-navy">Plot {owner.plot} — Project Metadata</p>
  {#if readers.metadataClient}
    <ProjectMetadataEditor
      bind:this={readers.metadataEditor}
      client={readers.metadataClient}
      contextId={owner.contextId}
      plot={owner.plot}
      allowRestoration={readers.metadataRestore}
      onbusy={(value) => {
        readers.projectMetadataBusy = value;
      }}
      onclosed={onclosemetadataeditor}
      oncommitted={readers.refreshMetadataPeers}
    />
  {:else}
    <p role="alert">The owned context-bound metadata client is unavailable. No metadata operation can run.</p>
  {/if}
{:else if readers.projectMetadataOpen === 'read'}
  <p role="status" class="text-xs font-semibold text-vpro-navy">Plot {owner.plot} — Project Metadata</p>
  <TwoPageProjectMetadataPanel
    contextId={owner.contextId}
    project={owner.project}
    plot={owner.plot}
    {form}
    projectPath={readers.vegetationScope.projectPath}
    su={readers.vegetationScope.su}
    suPath={readers.vegetationScope.suPath}
    onEditMetadata={readers.switchReadMetadataToEdit}
    editDisabled={!readers.canSwitchToMetadataEdit()}
    onBusyChange={(value) => {
      readers.projectMetadataBusy = value;
    }}
  />
  <button
    type="button"
    class="rounded border border-vpro-border bg-white px-3 py-1 text-xs font-medium text-vpro-ink hover:bg-vpro-surface-subtle disabled:opacity-50"
    disabled={readers.projectMetadataBusy}
    onclick={readers.returnFromProjectMetadata}>Back to Two-Page Form</button
  >
{:else if readers.environmentTableOpen}
  <p role="status" class="text-xs font-semibold text-vpro-navy">Plot {owner.plot} — Environment Table</p>
  <TwoPageEnvironmentTablePanel
    contextId={owner.contextId}
    project={owner.project}
    plot={owner.plot}
    {form}
    projectPath={readers.vegetationScope.projectPath}
    su={readers.vegetationScope.su}
    suPath={readers.vegetationScope.suPath}
    onBusyChange={(value) => {
      readers.environmentTableBusy = value;
    }}
  />
  <button
    type="button"
    class="rounded border border-vpro-border bg-white px-3 py-1 text-xs font-medium text-vpro-ink hover:bg-vpro-surface-subtle disabled:opacity-50"
    disabled={readers.environmentTableBusy}
    onclick={readers.returnFromEnvironmentTable}>Back to Two-Page Form</button
  >
{:else if readers.vegetationTableOpen}
  <p role="status" class="text-xs font-semibold text-vpro-navy">Plot {owner.plot} — Vegetation Table</p>
  <TwoPageVegetationTablePanel
    contextId={owner.contextId}
    project={owner.project}
    plot={owner.plot}
    {form}
    projectPath={readers.vegetationScope.projectPath}
    su={readers.vegetationScope.su}
    suPath={readers.vegetationScope.suPath}
    onBusyChange={(value) => {
      readers.vegetationTableBusy = value;
    }}
  />
  <button
    type="button"
    class="rounded border border-vpro-border bg-white px-3 py-1 text-xs font-medium text-vpro-ink hover:bg-vpro-surface-subtle disabled:opacity-50"
    disabled={readers.vegetationTableBusy}
    onclick={readers.returnFromVegetationTable}>Back to Two-Page Form</button
  >
{:else if readers.googleEarthOpen}
  <p role="status" class="text-xs font-semibold text-vpro-navy">Plot {owner.plot} — Google Earth KML</p>
  <TwoPageGoogleEarthPanel
    contextId={owner.contextId}
    project={owner.project}
    projectPath={readers.googleEarthPath}
    plot={owner.plot}
    {form}
    onBusyChange={(value) => {
      readers.googleEarthBusy = value;
    }}
  />
  <button
    type="button"
    class="rounded border border-vpro-border bg-white px-3 py-1 text-xs font-medium text-vpro-ink hover:bg-vpro-surface-subtle disabled:opacity-50"
    disabled={readers.googleEarthBusy}
    onclick={readers.returnFromGoogleEarth}>Back to Two-Page Form</button
  >
{:else if readers.auditOpen}
  <p role="status" class="text-xs font-semibold text-vpro-navy">Plot {owner.plot} — Audit Trail</p>
  <TwoPageAuditPanel
    contextId={owner.contextId}
    project={owner.project}
    plot={owner.plot}
    {form}
    onRestored={onrestoredaudit}
    onBusyChange={(value) => {
      readers.auditBusy = value;
    }}
  />
  <button
    type="button"
    class="rounded border border-vpro-border bg-white px-3 py-1 text-xs font-medium text-vpro-ink hover:bg-vpro-surface-subtle disabled:opacity-50"
    disabled={readers.auditBusy}
    onclick={readers.returnFromAudit}>Back to Two-Page Form</button
  >
{:else if readers.externalOpen && readers.sourceScope?.projectPath && readers.sourceScope.suPath}
  <p role="status" class="text-xs font-semibold text-vpro-navy">Site Unit Transfer ({owner.plot})</p>
  <ExternalSUEnvironmentTransfer
    bind:this={readers.externalEditor}
    contextId={readers.sourceScope.contextId}
    project={readers.sourceScope.project}
    projectPath={readers.sourceScope.projectPath}
    su={readers.sourceScope.su}
    suPath={readers.sourceScope.suPath}
    onclosed={() => {
      void readers.returnFromExternalTransfer();
    }}
  />
  {#if readers.sourceRefreshing}<p role="status">Refreshing plot fields after transfer...</p>{/if}
{:else}
  <div class="two-page-split-wrap" class:split-open={fieldCardSplitOpen && fieldCardViewModel !== null}>
    <div class="two-page-form-col min-w-0 flex-1" data-field-card-form-pane>
      {@render formPane()}
      <p class="mt-3 text-xs text-vpro-ink-secondary">
        Saves all Site, Location, and Soil summary fields on this two-page card together. Soil horizons and Vegetation
        layers save in their own sections below.
      </p>
    </div>
    {#if fieldCardSplitOpen && fieldCardViewModel}
      <div class="two-page-dock-col">
        <FieldCardPreviewModal
          open={true}
          mode="docked"
          viewModel={fieldCardViewModel}
          onclose={() => {
            fieldCardSplitOpen = false;
          }}
          onmodechange={(nextMode) => {
            if (nextMode === 'modal') {
              fieldCardSplitOpen = false;
              fieldCardModalOpen = true;
            }
          }}
        />
      </div>
    {/if}
  </div>
{/if}
{#if fieldCardModalOpen && fieldCardViewModel}
  <FieldCardPreviewModal
    open={true}
    mode="modal"
    viewModel={fieldCardViewModel}
    onclose={() => {
      fieldCardModalOpen = false;
    }}
    onmodechange={(nextMode) => {
      if (nextMode === 'docked') {
        fieldCardModalOpen = false;
        fieldCardSplitOpen = true;
      }
    }}
  />
{/if}

<style>
  .two-page-split-wrap {
    display: flex;
    gap: 1rem;
    align-items: flex-start;
    min-width: 0;
  }
  .two-page-dock-col {
    width: min(46%, 700px);
    min-width: 500px;
    max-height: 85vh;
    flex: none;
    position: sticky;
    top: 0.5rem;
  }
  @media (max-width: 1759px) {
    .two-page-dock-col {
      display: none;
    }
  }
</style>
