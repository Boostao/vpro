<script lang="ts">
  import type { VegetationDeletionReview } from '../../bindings/github.com/boostao/vpro/app';
  import PersonalSpeciesFields from './PersonalSpeciesFields.svelte';
  import { controlLabel } from './formPresentation';
  import { paperChild } from './paperLayout';
  import type { PersonalSpeciesDraft } from './personalSpeciesEditor';
  import type { VegetationCreationDraft } from './vegetationCreationEditor';
  import {
    speciesEventError,
    type SpeciesChoices,
    type SpeciesDecisionKind,
    type SpeciesDrafts,
    type SpeciesLists,
  } from './vegetationSpeciesEditor';

  let {
    busy,
    headerWorkflowBusy,
    plotNumber,
    savedPersonalCodes,
    speciesUnsaved,
    speciesEditingDisabled,
    speciesInvalid,
    speciesNotices,
    speciesDecisionBusy,
    speciesDrafts,
    speciesChoices,
    speciesLists,
    speciesReferenceReady,
    speciesReferenceBusy,
    personalDraft,
    personalInvalid,
    creationDraft,
    creationInvalid,
    creationSpeciesInvalid,
    creationNotice,
    creationChoices,
    deletionReview,
    saveSpeciesDrafts,
    cancelSpeciesDrafts,
    reviewSpeciesChoices,
    chooseSpeciesCode,
    startPersonalSpecies,
    onPersonalDraftChange,
    savePersonalSpecies,
    cancelPersonalSpecies,
    stageCreationSpecies,
    reviewCreationSpeciesChoices,
    chooseCreationSpecies,
    startCreationPersonalSpecies,
    stageCreationCell,
    saveVegetationCreation,
    cancelVegetationCreation,
    confirmVegetationDeletion,
    cancelVegetationDeletion,
  }: {
    busy: boolean;
    headerWorkflowBusy: boolean;
    plotNumber: string;
    savedPersonalCodes: string[];
    speciesUnsaved: boolean;
    speciesEditingDisabled: boolean;
    speciesInvalid: string[];
    speciesNotices: string[];
    speciesDecisionBusy: boolean;
    speciesDrafts: SpeciesDrafts;
    speciesChoices: Record<string, SpeciesChoices>;
    speciesLists: SpeciesLists;
    speciesReferenceReady: boolean;
    speciesReferenceBusy: boolean;
    personalDraft: PersonalSpeciesDraft | null;
    personalInvalid: string[];
    creationDraft: VegetationCreationDraft | null;
    creationInvalid: string[];
    creationSpeciesInvalid: string | null;
    creationNotice: string | null;
    creationChoices: SpeciesChoices | null;
    deletionReview: VegetationDeletionReview | null;
    saveSpeciesDrafts: () => Promise<void>;
    cancelSpeciesDrafts: () => Promise<void>;
    reviewSpeciesChoices: (id: number) => Promise<void>;
    chooseSpeciesCode: (id: number, kind: SpeciesDecisionKind, selected?: string) => void;
    startPersonalSpecies: (id: number) => void;
    onPersonalDraftChange: (draft: PersonalSpeciesDraft) => void;
    savePersonalSpecies: () => Promise<void>;
    cancelPersonalSpecies: () => void;
    stageCreationSpecies: (raw: string) => void;
    reviewCreationSpeciesChoices: () => Promise<void>;
    chooseCreationSpecies: (kind: SpeciesDecisionKind, selected?: string) => void;
    startCreationPersonalSpecies: () => void;
    stageCreationCell: (column: string, raw: string) => void;
    saveVegetationCreation: () => Promise<void>;
    cancelVegetationCreation: () => Promise<void>;
    confirmVegetationDeletion: () => Promise<void>;
    cancelVegetationDeletion: () => Promise<void>;
  } = $props();
</script>

{#if speciesUnsaved}
  <div
    class="species-draft-toolbar mb-3 p-2 border border-amber-300 bg-amber-50 text-xs"
    aria-label="Species draft controls"
  >
    {#if savedPersonalCodes.length}
      <p role="status">
        Saved personal definitions: {savedPersonalCodes.join(', ')}. Plot Undo does not remove these user-database
        records.
      </p>
    {/if}
    <span
      >Species drafts are unsubmitted. Switching tabs or cover/height views never saves them; other editing waits.</span
    >
    {#each speciesNotices as message}<p class="mt-2 font-medium" role="status">{message}</p>{/each}
    <div class="flex flex-wrap gap-2 mt-2">
      <button
        type="button"
        class="px-2 py-1 border border-vpro-navy rounded bg-vpro-navy hover:bg-vpro-navy-dark text-white disabled:opacity-50"
        disabled={speciesEditingDisabled || speciesInvalid.length > 0}
        onclick={() => void saveSpeciesDrafts()}>Save species drafts</button
      >
      <button
        type="button"
        class="px-2 py-1 border border-vpro-border rounded bg-white disabled:opacity-50"
        disabled={busy || headerWorkflowBusy || personalDraft !== null}
        onclick={() => void cancelSpeciesDrafts()}>Cancel species drafts</button
      >
    </div>
    {#each speciesInvalid as message}<p role="alert">{message}</p>{/each}
    {#if speciesDecisionBusy}<p role="status">Looking up source species choices...</p>{/if}
    {#each Object.entries(speciesDrafts) as [id, cell] (id)}
      {#if cell.error}
        {@const choices = speciesChoices[id]}
        <section
          class="mt-2 border-t border-amber-300 pt-2"
          aria-label={`Species choices, row ${id}`}
          data-species-choice-row={id}
        >
          <p>Row {id}: entered code "{cell.raw}" ({cell.form}). No assignment is saved by reviewing choices.</p>
          <button
            type="button"
            class="mt-1 px-2 py-1 border rounded bg-white"
            disabled={speciesEditingDisabled}
            onclick={() => void reviewSpeciesChoices(Number(id))}>Review species code, row {id}</button
          >
          {#if choices && choices.entered === cell.raw && choices.form === cell.form}
            {@const hasAlias = choices.aliases.some((option) => option.code !== null)}
            {#each choices.aliases as option, index (index)}
              <div class="mt-1">
                <span
                  >{option.code ?? 'NULL'} | {option.scientificName ?? 'NULL'} | {option.englishName ?? 'NULL'} | Lifeform
                  {option.lifeform ?? 'NULL'} | {option.codeType ?? 'NULL'}</span
                >
                <button
                  type="button"
                  class="ml-2 px-2 py-1 border rounded bg-white"
                  disabled={speciesEditingDisabled ||
                    speciesEventError(cell.raw) !== null ||
                    speciesEventError(option.code) !== null}
                  title={speciesEventError(cell.raw) ??
                    speciesEventError(option.code) ??
                    'Stage the explicit replacement; Save remains separate'}
                  onclick={() => option.code !== null && chooseSpeciesCode(Number(id), 'replace', option.code)}
                  >Use replacement {option.code ?? 'NULL'}, row {id}</button
                >
              </div>
            {/each}
            {#if hasAlias}
              <button
                type="button"
                class="mt-1 px-2 py-1 border rounded bg-white"
                disabled={speciesEditingDisabled || speciesEventError(cell.raw) !== null}
                title={speciesEventError(cell.raw) ?? 'Stage the entered code using the source UCase event'}
                onclick={() => chooseSpeciesCode(Number(id), 'keep')}>Keep entered code, row {id}</button
              >
            {:else}
              {#each choices.users as option, index (index)}
                <div class="mt-1">
                  <span
                    >{option.code ?? 'NULL'} | {option.scientificName ?? 'NULL'} | {option.englishName ?? 'NULL'} | Lifeform
                    {option.lifeform ?? 'NULL'} | {option.codeType ?? 'NULL'}</span
                  >
                  <button
                    type="button"
                    class="ml-2 px-2 py-1 border rounded bg-white"
                    disabled={speciesEditingDisabled ||
                      speciesEventError(cell.raw) !== null ||
                      speciesEventError(option.code) !== null}
                    title={speciesEventError(cell.raw) ??
                      speciesEventError(option.code) ??
                      'Stage the existing personal-list code; no personal-list write'}
                    onclick={() => option.code !== null && chooseSpeciesCode(Number(id), 'user', option.code)}
                    >Use personal code {option.code ?? 'NULL'}, row {id}</button
                  >
                </div>
              {:else}
                <button
                  type="button"
                  class="mt-2 rounded border bg-white px-2 py-1"
                  data-personal-create-row={id}
                  disabled={speciesEditingDisabled || speciesEventError(cell.raw) !== null}
                  onclick={() => startPersonalSpecies(Number(id))}>Create personal definition, row {id}</button
                >
              {/each}
            {/if}
            {#if speciesEventError(cell.raw)}<p role="alert">{speciesEventError(cell.raw)}</p>{/if}
          {/if}
        </section>
      {/if}
    {/each}
  </div>
{/if}

{#if personalDraft}
  <section
    class="personal-species-draft mb-3 rounded border border-amber-300 bg-amber-50 p-3 text-xs"
    aria-label="New personal species definition"
    data-personal-row-id={personalDraft.source.kind === 'existing' ? personalDraft.source.id : undefined}
    data-personal-editor={personalDraft.source.kind}
  >
    <h3 class="mb-2 font-semibold">New personal species definition - not yet saved</h3>
    <p class="mb-2" role="status">
      Saving here creates a reusable user-database definition and audit only. The plot assignment or new-row proposal
      remains unsaved. A later plot Undo does not delete a saved definition.
    </p>
    {#each personalInvalid as message}<p class="mb-2 text-red-700" role="alert">{message}</p>{/each}
    <PersonalSpeciesFields
      draft={personalDraft}
      disabled={busy || headerWorkflowBusy}
      onchange={onPersonalDraftChange}
    />
    <div class="flex gap-2">
      <button
        type="button"
        class="rounded border bg-white px-2 py-1 disabled:opacity-50"
        disabled={busy || headerWorkflowBusy || personalInvalid.length > 0}
        onclick={() => void savePersonalSpecies()}>Save personal definition only</button
      >
      <button
        type="button"
        class="rounded border bg-white px-2 py-1 disabled:opacity-50"
        disabled={busy || headerWorkflowBusy}
        onclick={cancelPersonalSpecies}>Cancel personal definition entry</button
      >
    </div>
    <p class="mt-2">
      Names preserve case and spacing, with a 255-UTF-16-unit bound. NULL and empty text remain distinct. Report,
      SppNumber and Codetype retain their original user-table defaults; no U/X classification is inferred.
    </p>
  </section>
{/if}

{#if creationDraft}
  <section
    class="vegetation-creation-draft mb-3 rounded border border-amber-300 bg-amber-50 p-3 text-xs"
    aria-label="New vegetation record"
  >
    <h3 class="mb-2 font-semibold">New vegetation record - {creationDraft.form} - not yet saved</h3>
    {#if savedPersonalCodes.length}<p class="mb-2" role="status">
        Saved personal definitions: {savedPersonalCodes.join(', ')}. Cancelling this new-row proposal never removes
        these user-database records.
      </p>{/if}
    {#if creationInvalid.length}<p class="mb-2 text-red-700" role="alert">{creationInvalid[0]}</p>{/if}
    {#if creationNotice}<p class="mb-2 font-medium" role="status">{creationNotice}</p>{/if}
    <label class="mb-2 flex flex-col gap-1" for="creation-species"
      >Species code
      <input
        id="creation-species"
        class="rounded border bg-white px-2 py-2"
        type="text"
        value={creationDraft.species}
        list="creation-species-list"
        disabled={busy || headerWorkflowBusy || personalDraft !== null}
        aria-invalid={creationSpeciesInvalid !== null}
        oninput={(event) => stageCreationSpecies(event.currentTarget.value)}
      />
    </label>
    <datalist id="creation-species-list">
      {#each speciesLists[creationDraft.form] ?? [] as option, index (index)}
        {#if option.code !== null}<option value={option.code}
            >{option.scientificName ?? 'NULL'} | {option.englishName ?? 'NULL'} | Lifeform {option.lifeform ??
              'NULL'}</option
          >{/if}
      {/each}
    </datalist>
    {#if creationDraft.decision}
      <p class="mb-2" role="status">
        Explicit {creationDraft.decision.kind} decision for "{creationDraft.decision.entered}" stages "{creationDraft.species}".
        No new row or personal definition is saved yet.
      </p>
    {:else if creationSpeciesInvalid}
      <section class="mb-3 border-t border-amber-300 pt-2" aria-label="New vegetation species choices">
        <button
          type="button"
          class="rounded border bg-white px-2 py-1"
          disabled={busy ||
            headerWorkflowBusy ||
            personalDraft !== null ||
            !speciesReferenceReady ||
            speciesReferenceBusy ||
            speciesEventError(creationDraft.species) !== null}
          title={speciesEventError(creationDraft.species) ?? 'Review source definitions without saving'}
          onclick={() => void reviewCreationSpeciesChoices()}>Review new vegetation species code</button
        >
        {#if speciesDecisionBusy}<p role="status">Looking up source species choices...</p>{/if}
        {#if creationChoices && creationChoices.form === creationDraft.form && creationChoices.entered === creationDraft.species}
          {@const hasAlias = creationChoices.aliases.some((option) => option.code !== null)}
          {#each creationChoices.aliases as option, index (index)}
            <div class="mt-1">
              <span
                >{option.code ?? 'NULL'} | {option.scientificName ?? 'NULL'} | {option.englishName ?? 'NULL'} | Lifeform {option.lifeform ??
                  'NULL'} | {option.codeType ?? 'NULL'}</span
              >
              <button
                type="button"
                class="ml-2 rounded border bg-white px-2 py-1"
                disabled={busy ||
                  headerWorkflowBusy ||
                  personalDraft !== null ||
                  speciesEventError(option.code) !== null}
                title={speciesEventError(option.code) ?? 'Stage explicit replacement; Save remains separate'}
                onclick={() => option.code !== null && chooseCreationSpecies('replace', option.code)}
                >Use replacement {option.code ?? 'NULL'} for new row</button
              >
            </div>
          {/each}
          {#if hasAlias}
            <button
              type="button"
              class="mt-1 rounded border bg-white px-2 py-1"
              disabled={busy || headerWorkflowBusy || personalDraft !== null}
              onclick={() => chooseCreationSpecies('keep')}>Keep entered code for new row</button
            >
          {:else}
            {#each creationChoices.users as option, index (index)}
              <div class="mt-1">
                <span
                  >{option.code ?? 'NULL'} | {option.scientificName ?? 'NULL'} | {option.englishName ?? 'NULL'} | Lifeform
                  {option.lifeform ?? 'NULL'} | {option.codeType ?? 'NULL'}</span
                >
                <button
                  type="button"
                  class="ml-2 rounded border bg-white px-2 py-1"
                  disabled={busy ||
                    headerWorkflowBusy ||
                    personalDraft !== null ||
                    speciesEventError(option.code) !== null}
                  title={speciesEventError(option.code) ?? 'Stage an existing personal code; no user-database write'}
                  onclick={() => option.code !== null && chooseCreationSpecies('user', option.code)}
                  >Use personal code {option.code ?? 'NULL'} for new row</button
                >
              </div>
            {:else}
              <button
                type="button"
                class="mt-2 rounded border bg-white px-2 py-1"
                data-personal-create-source={creationDraft.form}
                disabled={busy ||
                  headerWorkflowBusy ||
                  personalDraft !== null ||
                  speciesEventError(creationDraft.species) !== null}
                onclick={startCreationPersonalSpecies}>Create personal definition for new row</button
              >
            {/each}
          {/if}
        {/if}
      </section>
    {/if}
    <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
      {#each Object.entries(creationDraft.cells) as [column, cell] (column)}
        {@const control = paperChild(creationDraft.form).controls.find(
          (c) => c.column?.toLowerCase() === column.toLowerCase()
        )}
        <label class="flex flex-col gap-1" for={`creation-${column}`}
          >{control ? controlLabel(control) : column}
          <input
            id={`creation-${column}`}
            class="rounded border bg-white px-2 py-2"
            type="text"
            inputmode="decimal"
            value={cell?.raw ?? ''}
            disabled={busy || headerWorkflowBusy || personalDraft !== null}
            aria-invalid={cell?.error != null}
            title={cell?.error ?? 'Blank is NULL; no zero cover is inferred.'}
            oninput={(event) => stageCreationCell(column, event.currentTarget.value)}
          />
        </label>
      {/each}
    </div>
    <div class="mt-3 flex gap-2">
      <button
        type="button"
        class="rounded border bg-white px-2 py-1 disabled:opacity-50"
        disabled={busy ||
          headerWorkflowBusy ||
          personalDraft !== null ||
          creationInvalid.length > 0 ||
          !speciesReferenceReady ||
          speciesReferenceBusy}
        onclick={() => void saveVegetationCreation()}>Save new vegetation record</button
      >
      <button
        type="button"
        class="rounded border bg-white px-2 py-1 disabled:opacity-50"
        disabled={busy || headerWorkflowBusy || personalDraft !== null}
        onclick={() => void cancelVegetationCreation()}>Cancel vegetation creation</button
      >
    </div>
    <p class="mt-2">
      Select an exact canonical code or explicitly review replacement, keep or existing personal-code decisions. Enter
      source numeric values explicitly. Blank fields remain NULL; Layer, covers, totals and personal metadata are not
      inferred. Identity is allocated only by the transactional writer; saving a new row never writes the user database.
    </p>
  </section>
{/if}

{#if deletionReview}
  <section
    class="vegetation-deletion-review mb-3 rounded border border-red-300 bg-red-50 p-3 text-xs"
    aria-label="Vegetation deletion review"
  >
    <p role="alert">
      Delete the entire vegetation record for {deletionReview.species ?? 'NULL'}, row {deletionReview.id}, plot {plotNumber}?
      This removes every stored field from all cover/height/attribute views, not just {deletionReview.form}. The deleted
      identity remains reserved. Ordinary Save never confirms this action.
    </p>
    <details class="mt-2">
      <summary>Stored columns being removed</summary>
      <p>{deletionReview.columns?.join(', ')}</p>
    </details>
    <div class="mt-2 flex gap-2">
      <button
        type="button"
        class="rounded border bg-red-700 px-2 py-1 text-white disabled:opacity-50"
        disabled={busy || headerWorkflowBusy}
        onclick={() => void confirmVegetationDeletion()}>Confirm deletion of row {deletionReview.id}</button
      >
      <button
        type="button"
        class="rounded border bg-white px-2 py-1 disabled:opacity-50"
        disabled={busy || headerWorkflowBusy}
        onclick={() => void cancelVegetationDeletion()}>Cancel deletion review</button
      >
    </div>
  </section>
{/if}
