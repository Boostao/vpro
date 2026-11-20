<script lang="ts">
  import { X } from '@lucide/svelte';
  import ModalDialogTrap from '../shared/ModalDialogTrap.svelte';
  import FS882VegCreationSection from './FS882VegCreationSection.svelte';
  import NewChild from './NewChild.svelte';
  import type { PersonalSpeciesDraft } from './personalSpeciesEditor';
  import type { FS882ChildWorkflowsController } from './useFS882ChildWorkflows.svelte';

  let {
    region = 'toolbars',
    children: c,
    busy = false,
    headerWorkflowBusy = false,
    error = null,
    plotNumber = '',
    heightUnsaved: fallbackHeightUnsaved = false,
    onPersonalDraftChange,
  }: {
    region?: 'toolbars' | 'speciesModal' | 'newChild';
    children?: FS882ChildWorkflowsController;
    busy?: boolean;
    headerWorkflowBusy?: boolean;
    error?: string | null;
    plotNumber?: string;
    heightUnsaved?: boolean;
    onPersonalDraftChange?: (draft: PersonalSpeciesDraft) => void;
  } = $props();

  const noopAsync = async () => {};
  const noop = () => {};

  const speciesUnsaved = $derived(c?.speciesUnsaved ?? false);
  const personalDraft = $derived(c?.personalDraft ?? null);
  const collectedUnsaved = $derived(c?.collectedUnsaved ?? false);
  const attributeUnsaved = $derived(c?.attributeUnsaved ?? false);
  const soilUnsaved = $derived(c?.soilUnsaved ?? false);
  const otherUnsaved = $derived(c?.otherUnsaved ?? false);
  const creationDraft = $derived(c?.creationDraft ?? null);
  const deletionReview = $derived(c?.deletionReview ?? null);
  const heightUnsaved = $derived(c?.heightUnsaved ?? fallbackHeightUnsaved);
  const hasActiveToolbar = $derived(
    speciesUnsaved ||
      Boolean(personalDraft) ||
      collectedUnsaved ||
      attributeUnsaved ||
      soilUnsaved ||
      otherUnsaved ||
      Boolean(creationDraft) ||
      Boolean(deletionReview) ||
      heightUnsaved
  );
</script>

{#if region === 'toolbars'}
  {#if hasActiveToolbar}
    <div class="sticky top-0 z-20 bg-white/95 py-1 shadow-xs" data-sticky-child-draft-bar>
      <FS882VegCreationSection
        {busy}
        {headerWorkflowBusy}
        {plotNumber}
        savedPersonalCodes={c?.savedPersonalCodes ?? []}
        {speciesUnsaved}
        speciesEditingDisabled={c?.speciesEditingDisabled ?? false}
        speciesInvalid={c?.speciesInvalid ?? []}
        speciesNotices={c?.speciesNotices ?? []}
        speciesDecisionBusy={c?.speciesDecisionBusy ?? false}
        speciesDrafts={c?.speciesDrafts ?? {}}
        speciesChoices={c?.speciesChoices ?? {}}
        speciesLists={c?.speciesLists ?? {}}
        speciesReferenceReady={c?.speciesReferenceReady ?? false}
        speciesReferenceBusy={c?.speciesReferenceBusy ?? false}
        {personalDraft}
        personalInvalid={c?.personalInvalid ?? []}
        {creationDraft}
        creationInvalid={c?.creationInvalid ?? []}
        creationSpeciesInvalid={c?.creationSpeciesInvalid ?? null}
        creationNotice={c?.creationNotice ?? null}
        creationChoices={c?.creationChoices ?? null}
        {deletionReview}
        saveSpeciesDrafts={c?.saveSpeciesDrafts ?? noopAsync}
        cancelSpeciesDrafts={c?.cancelSpeciesDrafts ?? noopAsync}
        reviewSpeciesChoices={c?.reviewSpeciesChoices ?? noopAsync}
        chooseSpeciesCode={c?.chooseSpeciesCode ?? noop}
        startPersonalSpecies={c?.startPersonalSpecies ?? noop}
        onPersonalDraftChange={onPersonalDraftChange ?? noop}
        savePersonalSpecies={c?.savePersonalSpecies ?? noopAsync}
        cancelPersonalSpecies={c?.cancelPersonalSpecies ?? noop}
        stageCreationSpecies={c?.stageCreationSpecies ?? noop}
        reviewCreationSpeciesChoices={c?.reviewCreationSpeciesChoices ?? noopAsync}
        chooseCreationSpecies={c?.chooseCreationSpecies ?? noop}
        startCreationPersonalSpecies={c?.startCreationPersonalSpecies ?? noop}
        stageCreationCell={c?.stageCreationCell ?? noop}
        saveVegetationCreation={c?.saveVegetationCreation ?? noopAsync}
        cancelVegetationCreation={c?.cancelVegetationCreation ?? noopAsync}
        confirmVegetationDeletion={c?.confirmVegetationDeletion ?? noopAsync}
        cancelVegetationDeletion={c?.cancelVegetationDeletion ?? noopAsync}
      />

      {#if collectedUnsaved}
        <div
          class="collected-draft-toolbar mb-3 p-2 border border-amber-300 bg-amber-50 text-xs"
          aria-label="Collected draft controls"
        >
          <span
            >Collected drafts are unsubmitted. Switching tabs or cover/height views never saves them; other editing
            waits.</span
          >
          {#each c?.collectedNotices ?? [] as message}<p class="mt-2 font-medium" role="status">{message}</p>{/each}
          <div class="flex flex-wrap gap-2 mt-2">
            <button
              type="button"
              class="px-2 py-1 border border-vpro-navy rounded bg-vpro-navy hover:bg-vpro-navy-dark text-white disabled:opacity-50"
              disabled={c?.collectedEditingDisabled ?? false}
              onclick={() => void c?.saveCollectedDrafts()}>Save Collected drafts</button
            >
            <button
              type="button"
              class="px-2 py-1 border border-vpro-border rounded bg-white disabled:opacity-50"
              disabled={busy || headerWorkflowBusy}
              onclick={() => void c?.cancelCollectedDrafts()}>Cancel Collected drafts</button
            >
          </div>
        </div>
      {/if}

      {#if attributeUnsaved}
        <div
          class="attribute-draft-toolbar mb-3 p-2 border border-amber-300 bg-amber-50 text-xs"
          aria-label="Vegetation attribute draft controls"
        >
          <span>Vegetation attribute drafts are unsubmitted. Switching tabs never saves them; other editing waits.</span
          >
          <div class="flex flex-wrap gap-2 mt-2">
            <button
              type="button"
              class="px-2 py-1 border border-vpro-navy rounded bg-vpro-navy hover:bg-vpro-navy-dark text-white disabled:opacity-50"
              disabled={(c?.attributeEditingDisabled ?? false) || (c?.attributeInvalid.length ?? 0) > 0}
              onclick={() => void c?.saveAttributeDrafts()}>Save vegetation attributes</button
            >
            <button
              type="button"
              class="px-2 py-1 border border-vpro-border rounded bg-white disabled:opacity-50"
              disabled={busy || headerWorkflowBusy}
              onclick={() => void c?.cancelAttributeDrafts()}>Cancel vegetation attributes</button
            >
          </div>
          {#each c?.attributeInvalid ?? [] as message}<p role="alert">{message}</p>{/each}
        </div>
      {/if}

      {#if soilUnsaved}
        <div
          class="soil-draft-toolbar mb-3 p-2 border border-amber-300 bg-amber-50 text-xs"
          aria-label="Soil draft controls"
        >
          <span>Humus/Mineral drafts are unsubmitted. Switching tabs never saves them; other editing waits.</span>
          <div class="flex flex-wrap gap-2 mt-2">
            <button
              type="button"
              class="px-2 py-1 border border-vpro-navy rounded bg-vpro-navy hover:bg-vpro-navy-dark text-white disabled:opacity-50"
              disabled={(c?.soilEditingDisabled ?? false) || (c?.soilInvalid.length ?? 0) > 0}
              onclick={() => void c?.saveSoilDrafts()}>Save soil drafts</button
            >
            <button
              type="button"
              class="px-2 py-1 border border-vpro-border rounded bg-white disabled:opacity-50"
              disabled={busy || headerWorkflowBusy}
              onclick={() => void c?.cancelSoilDrafts()}>Cancel soil drafts</button
            >
          </div>
          {#each c?.soilInvalid ?? [] as message}<p role="alert">{message}</p>{/each}
        </div>
      {/if}

      {#if otherUnsaved}
        <div
          class="other-draft-toolbar mb-3 p-2 border border-amber-300 bg-amber-50 text-xs"
          aria-label="Other draft controls"
        >
          <span
            >Other drafts are unsubmitted. Switching tabs never saves them; header and other child editing wait.</span
          >
          <div class="flex flex-wrap gap-2 mt-2">
            <button
              type="button"
              class="px-2 py-1 border border-vpro-navy rounded bg-vpro-navy hover:bg-vpro-navy-dark text-white disabled:opacity-50"
              disabled={(c?.otherEditingDisabled ?? false) || (c?.otherInvalid.length ?? 0) > 0}
              onclick={() => void c?.saveOtherDrafts()}>Save Other drafts</button
            >
            <button
              type="button"
              class="px-2 py-1 border border-vpro-border rounded bg-white disabled:opacity-50"
              disabled={busy || headerWorkflowBusy}
              onclick={() => void c?.cancelOtherDrafts()}>Cancel Other drafts</button
            >
          </div>
          {#each c?.otherInvalid ?? [] as message}<p role="alert">{message}</p>{/each}
        </div>
      {/if}

      {#if heightUnsaved}
        <div
          class="height-draft-toolbar mb-3 p-2 border border-amber-300 bg-amber-50 text-xs"
          aria-label="Height draft controls"
        >
          <span
            >Height/cover drafts are unsubmitted. Switching views never saves them; header and other child editing wait.</span
          >
          {#each c?.heightNotices ?? [] as message}<p class="mt-2 font-medium" role="status">{message}</p>{/each}
          <div class="flex flex-wrap gap-2 mt-2">
            <button
              type="button"
              class="px-2 py-1 border border-vpro-navy rounded bg-vpro-navy hover:bg-vpro-navy-dark text-white disabled:opacity-50"
              disabled={(c?.heightEditingDisabled ?? false) || (c?.heightInvalid.length ?? 0) > 0}
              onclick={() => void c?.saveHeightDrafts()}>Save height/cover drafts</button
            >
            <button
              type="button"
              class="px-2 py-1 border border-vpro-border rounded bg-white disabled:opacity-50"
              disabled={busy || headerWorkflowBusy}
              onclick={() => void c?.cancelHeightDrafts()}>Cancel height/cover drafts</button
            >
          </div>
          {#each c?.heightInvalid ?? [] as message}<p role="alert">{message}</p>{/each}
          {#if Object.values(c?.heightDrafts ?? {}).some((row) => row.cover6?.value === null && row.cover6?.expected !== null)}
            <p>
              Saving NULL Cover6 removes that row from the C-height view after refresh, but does not delete the
              vegetation record.
            </p>
          {/if}
        </div>
      {/if}
    </div>
  {/if}
{:else if region === 'speciesModal' && c?.showSpeciesModal}
  <div class="fixed inset-0 bg-vpro-ink/40 backdrop-blur-xs flex items-center justify-center z-50 p-4">
    <div
      role="dialog"
      aria-modal="true"
      aria-label="BC Master Species Search"
      class="bg-white rounded-lg shadow-xl border border-vpro-border w-full max-w-lg flex flex-col max-h-[80vh]"
    >
      <ModalDialogTrap
        onEscape={() => {
          if (c) c.showSpeciesModal = false;
        }}
      />
      <div class="p-3 border-b border-vpro-border flex justify-between items-center bg-vpro-canvas rounded-t-lg">
        <h4 class="font-bold text-sm text-vpro-navy">BC Master Species Search</h4>
        <button
          type="button"
          aria-label="Close species search"
          onclick={() => {
            if (c) c.showSpeciesModal = false;
          }}
          class="text-vpro-ink-muted hover:text-vpro-ink p-1"><X size={16} /></button
        >
      </div>
      <div class="p-3 border-b border-vpro-border flex flex-wrap gap-2">
        <input
          type="text"
          aria-label="Search BC master species by code or name"
          placeholder="Search code (e.g. ABIE) or name (e.g. fir, spruce)..."
          bind:value={c.speciesSearchQuery}
          oninput={() => void c.searchSpecies()}
          class="min-w-0 flex-1 border border-vpro-border rounded px-3 py-1.5 text-xs bg-white text-vpro-ink"
        />
        <button
          type="button"
          onclick={() => void c.searchSpecies()}
          class="px-3 py-1.5 bg-vpro-navy text-white rounded text-xs font-medium hover:bg-vpro-navy-dark">Search</button
        >
      </div>
      <div class="p-2 overflow-y-auto flex-1 divide-y divide-vpro-canvas">
        {#if c.searchingSpecies}
          <div class="p-4 text-center text-xs text-vpro-ink-muted">Searching catalog...</div>
        {:else if c.speciesSearchResults.length > 0}
          {#each c.speciesSearchResults as sp}
            <button
              type="button"
              class="w-full p-2 hover:bg-vpro-canvas rounded flex justify-between items-center text-left"
              onclick={() => void c.selectSpeciesToAdd(sp)}
            >
              <div>
                <div class="flex items-center gap-2">
                  <span class="font-mono font-bold text-xs text-vpro-navy bg-vpro-info-bg px-1.5 py-0.5 rounded"
                    >{sp.code}</span
                  >
                  <span class="font-medium text-xs text-vpro-ink italic">{sp.scientificName}</span>
                </div>
                {#if sp.englishName}<div class="text-[11px] text-vpro-ink-muted mt-0.5">{sp.englishName}</div>{/if}
              </div>
              <span class="px-2 py-1 bg-vpro-navy hover:bg-vpro-navy-dark text-white text-[11px] rounded font-medium"
                >Select</span
              >
            </button>
          {/each}
        {:else if c.speciesSearchQuery.trim()}
          <div class="p-4 text-center text-xs text-vpro-ink-muted">No matching species found.</div>
        {:else}
          <div class="p-4 text-center text-xs text-vpro-ink-muted">
            Type a code or species name above to search 10,500+ BC flora.
          </div>
        {/if}
      </div>
    </div>
  </div>
{:else if c?.newChild}
  <NewChild
    kind={c.newChild}
    {busy}
    {error}
    oncreate={c.createChild}
    oncancel={() => {
      c.newChild = null;
    }}
  />
{/if}
