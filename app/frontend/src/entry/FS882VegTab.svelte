<script lang="ts">
  import type { FS882Header } from '../../bindings/github.com/boostao/vpro/app';
  import FS882ChildCreateModal from './FS882ChildCreateModal.svelte';
  import FS882StratumSummary from './FS882StratumSummary.svelte';
  import OrdinaryFields from './OrdinaryFields.svelte';
  import SourceChild from './SourceChild.svelte';
  import SourcePage from './SourcePage.svelte';
  import { embeddedForm, type VegetationMode } from './paperLayout';
  import type { FS882ChildWorkflowsController } from './useFS882ChildWorkflows.svelte';
  import type { SiviSessionsController } from './useSiviSessions.svelte';

  let {
    sivi,
    children: childCtrl,
    draft = $bindable(),
    original,
    capabilities,
    vegetationMode = $bindable(),
    busy,
    headerWorkflowBusy,
    headerInputsDisabled,
    capabilitiesReady,
    siviStandalone,
    extendedShrubs,
    extendedShrubsNotice,
    siviContextId,
    activeProject,
    sourceHeaderValues,
    headerValidation,
    childParentDisabled,
    childUnsaved,
    onFindPlot,
    markDirty,
    validateHeader,
    vegetationNotesTab,
    openSpeciesCodeCheck,
  }: {
    sivi: SiviSessionsController;
    children: FS882ChildWorkflowsController;
    draft: FS882Header;
    original: FS882Header | null;
    capabilities: Record<string, boolean | undefined>;
    vegetationMode: VegetationMode;
    busy: boolean;
    headerWorkflowBusy: boolean;
    headerInputsDisabled: boolean;
    capabilitiesReady: boolean;
    siviStandalone: boolean;
    extendedShrubs: boolean;
    extendedShrubsNotice: string;
    siviContextId: string;
    activeProject: string;
    sourceHeaderValues: Map<string, unknown>;
    headerValidation: Record<string, string>;
    childParentDisabled: boolean;
    childUnsaved: boolean;
    onFindPlot?: () => void;
    markDirty: () => void;
    validateHeader: (key: string, message: string | null) => void;
    vegetationNotesTab: () => Promise<void>;
    openSpeciesCodeCheck: () => void;
  } = $props();

  const anySiviVegPanelOpen = $derived(
    Boolean(
      (sivi.identityPanelOpen && sivi.identityView) ||
      (sivi.speciesPanelOpen && sivi.speciesView) ||
      (sivi.collectedPanelOpen && sivi.collectedView) ||
      (sivi.combinedPanelOpen && sivi.combinedView) ||
      (sivi.heightPanelOpen && sivi.heightView) ||
      (sivi.coverPanelOpen && sivi.coverView)
    )
  );
</script>

{#await import('./FS882SiviVegSection.svelte') then { default: FS882SiviVegSection }}
  <FS882SiviVegSection
    {sivi}
    {original}
    {siviContextId}
    {activeProject}
    {busy}
    {headerWorkflowBusy}
    {siviStandalone}
    {extendedShrubs}
    {extendedShrubsNotice}
  />
{/await}

{#if !anySiviVegPanelOpen}
  {#if childCtrl.vegetationReadUnavailable}
    <p role="alert" class="p-4">
      Ordinary ID-keyed vegetation is unavailable: {childCtrl.vegetationReadUnavailable}
      Independently enabled physical-row SIVI views remain available; no NULL identity is converted to zero and no row is
      omitted from an ordinary result.
    </p>
  {:else if siviStandalone}
    <p role="status" class="p-4">
      SIVI vegetation preserves the three PlotNumber-linked source groups: A (trees/shrubs), C and D. Choose an
      independently enabled source view above. Species creation/deletion and original species-list callbacks remain
      unavailable.
    </p>
  {:else}
    {#if childCtrl.speciesReferenceBusy}<p role="status">Loading source species lists...</p>{/if}
    {#if childCtrl.speciesReferenceError}<p role="alert">{childCtrl.speciesReferenceError}</p>{/if}
    <button
      type="button"
      class="mb-2 px-2 py-1 border rounded"
      disabled={busy || childCtrl.speciesReferenceBusy || headerWorkflowBusy}
      onclick={() => void childCtrl.loadSpeciesReferences()}
    >
      {childCtrl.speciesReferenceError ? 'Retry species references' : 'Reload species references'}
    </button>
    <OrdinaryFields
      bind:draft
      {original}
      {capabilities}
      scope="veg"
      disabled={headerInputsDisabled}
      onchange={markDirty}
      onvalidation={validateHeader}
      onVegNotesTab={vegetationNotesTab}
    >
      {#snippet children(ordinaryEditor)}
        <SourcePage
          name="Vegetation"
          values={sourceHeaderValues}
          {vegetationMode}
          editor={ordinaryEditor}
          onHeightToggle={() => {
            vegetationMode = vegetationMode === 'height' ? 'cover' : 'height';
          }}
          heightToggleDisabled={extendedShrubs || busy || headerWorkflowBusy}
          {onFindPlot}
          findPlotDisabled={busy || headerWorkflowBusy || !capabilitiesReady}
          onSpeciesCheck={openSpeciesCodeCheck}
          speciesCheckDisabled={childParentDisabled || childUnsaved || Object.keys(headerValidation).length > 0}
        >
          {#snippet embedded(control)}
            {@const originalChild = embeddedForm(control.controlId)}
            {@const child = {
              ...originalChild,
              form: extendedShrubs && originalChild.form === 'SubVegAXL_BC' ? 'SubVegAXL' : originalChild.form,
            }}
            <button
              type="button"
              class="mb-2 rounded border px-2 py-1 text-xs disabled:opacity-50"
              data-create-source={child.form}
              disabled={childParentDisabled ||
                childUnsaved ||
                !childCtrl.speciesReferenceReady ||
                childCtrl.speciesReferenceBusy}
              onclick={() => childCtrl.startVegetationCreation(child.form)}>New vegetation record - {child.form}</button
            >
            <SourceChild
              name={child.form}
              rows={childCtrl.sourceRows(child.form)}
              revision={childCtrl.childRevision}
              disabled={childCtrl.heightEditingDisabled}
              drafts={childCtrl.heightDrafts}
              onstage={(id, column, raw) => childCtrl.stageHeightCell(id, column, raw, child.form)}
              collectedDrafts={childCtrl.collectedDrafts}
              collectedDisabled={childCtrl.collectedEditingDisabled}
              oncollectedstage={childCtrl.stageCollectedCell}
              speciesDrafts={childCtrl.speciesDrafts}
              speciesLists={childCtrl.speciesLists}
              speciesDisabled={childCtrl.speciesEditingDisabled}
              onspeciesstage={childCtrl.stageSpeciesCell}
              onedit={undefined}
              ondelete={childCtrl.reviewVegetationDeletion}
              deleteDisabled={childUnsaved}
            />
          {/snippet}
        </SourcePage>
      {/snippet}
    </OrdinaryFields>
  {/if}
{/if}

{#if vegetationMode === 'height'}
  <p class="mt-2 text-xs text-vpro-ink-muted">
    Cover and height values validate against LMH25 (&lt; 100%) single-precision bounds; use Save or Cancel to commit or
    discard drafts. Switching view does not save or alter data.
  </p>
{/if}
<p class="mt-2 text-xs text-vpro-ink-muted">
  Collected buttons cycle NULL -&gt; C -&gt; V -&gt; NULL using persistent drafts. Other historical values remain
  unchanged, as in the source click event. Use Save or Cancel; new rows use a separate explicit source creation draft.
</p>
<p class="mt-2 text-xs text-vpro-ink-muted">
  All source cover/total and height fields share persistent drafts. Switching grids retains raw errors and original
  values; Save checks each field's original source row and commits changes/audits atomically. Clearing cover may remove
  a row from a source view, never delete the vegetation record.
</p>
<p class="mt-2 text-xs text-vpro-ink-muted">
  Species selection uses canonical source lists and explicit old-code replace/keep or existing personal-code decisions.
  Decisions stage the source UCase event; Save remains separate. Unknown-code personal definitions use a separate
  explicit user-database save; plot Save and Undo remain independent.
</p>

<FS882StratumSummary
  vegList={childCtrl.vegList}
  totalTreeCover={childCtrl.totalTreeCover}
  totalShrubCover={childCtrl.totalShrubCover}
  totalHerbCover={childCtrl.totalHerbCover}
  totalMossCover={childCtrl.totalMossCover}
  onopenspeciesmodal={() => {
    childCtrl.showSpeciesModal = true;
  }}
  ondeleteveg={childCtrl.deleteVeg}
/>
<FS882ChildCreateModal region="speciesModal" children={childCtrl} />
