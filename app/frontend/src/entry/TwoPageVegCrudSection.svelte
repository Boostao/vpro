<script lang="ts">
  import type { TwoPageVegetationForm, TwoPageVegetationOriginal } from './twoPageVegetationWire';
  import type { TwoPageVegetationView } from './twoPageVegetationSession';
  import { twoPageVegetationStoredText } from './twoPageVegetationPresentation';

  export interface DeletedVegetationRowEntry {
    deleteRequestId: string;
    plotNumber: string;
    form: string;
    deletedId: number;
    species: string;
    layer: string;
    deletedBy: string;
    deletedAt: string;
    restored: boolean;
  }

  let {
    createSpecies = $bindable(),
    createLayer = $bindable(),
    createCollected = $bindable(),
    state: s,
    handlers: h,
  }: {
    createSpecies: string;
    createLayer: string;
    createCollected: string;
    state: {
      form: TwoPageVegetationForm;
      parentBlocked: boolean;
      error: string | null;
      view: TwoPageVegetationView;
      createOpen: boolean;
      crudBusy: boolean;
      fieldsDisabled: boolean;
      unsaved: boolean;
      closeBlocked: boolean;
      original: TwoPageVegetationOriginal | null;
      currentRowId: string | undefined;
      deleteConfirmRowId: string | null;
      deletedHistoryOpen: boolean;
      deletedRows: DeletedVegetationRowEntry[];
    };
    handlers: {
      onsubmitcreate: () => void;
      oncancelcreate: () => void;
      onconfirmdelete: () => void;
      oncanceldelete: () => void;
      onrestore: (deleteRequestId: string) => void;
    };
  } = $props();
</script>

{#if s.parentBlocked}<p role="status">
    Finish actual parent/other-owner drafts and unlock the plot before new vegetation staging.
  </p>{/if}
{#if s.error}<p role="alert" class="break-words text-sm text-vpro-error">{s.error}</p>{/if}
{#if s.view.error && s.view.error !== s.error}<p role="alert" class="break-words text-sm text-vpro-error">
    {s.view.error}
  </p>{/if}
{#if s.view.referenceError && s.view.referenceError !== s.error}<p
    role="alert"
    class="break-words text-sm text-vpro-error"
  >
    {s.view.referenceError}
  </p>{/if}
{#if s.view.blocked}<p role="alert">
    Save outcome unresolved. Recover the exact retained request; do not repeat Save.
  </p>{/if}
{#if s.view.noCommitCertificate}
  <p role="status" class="break-words">
    Server certified no commit for {s.view.noCommitCertificate.requestId}. Correct or Undo retained drafts; another Save
    needs a new request.
  </p>
{/if}
{#if Object.keys(s.view.drafts).length}
  <p role="status">
    {Object.keys(s.view.drafts).length} retained field draft(s). Save applies all retained edits together, including other
    physical rows.
  </p>
{/if}

{#if s.createOpen}
  <div class="rounded border border-vpro-navy/30 bg-vpro-canvas p-3 space-y-2" data-veg-create-panel>
    <p class="text-xs font-semibold text-vpro-navy">Add Vegetation Row ({s.form})</p>
    <div class="grid grid-cols-1 gap-2 sm:grid-cols-3">
      <div class="min-w-0">
        <label class="block text-xs font-medium text-vpro-ink" for={`${s.form}-create-species`}>Species Code *</label>
        <input
          id={`${s.form}-create-species`}
          type="text"
          class="w-full rounded border border-vpro-border bg-white px-2 py-1.5 text-sm"
          bind:value={createSpecies}
          disabled={s.crudBusy}
          placeholder="e.g. PSEUMEN"
        />
      </div>
      <div class="min-w-0">
        <label class="block text-xs font-medium text-vpro-ink" for={`${s.form}-create-layer`}>Layer (optional)</label>
        <input
          id={`${s.form}-create-layer`}
          type="text"
          class="w-full rounded border border-vpro-border bg-white px-2 py-1.5 text-sm"
          bind:value={createLayer}
          disabled={s.crudBusy}
          placeholder="e.g. A1, B1, C, D"
        />
      </div>
      <div class="min-w-0">
        <label class="block text-xs font-medium text-vpro-ink" for={`${s.form}-create-collected`}
          >Collected (optional)</label
        >
        <input
          id={`${s.form}-create-collected`}
          type="text"
          class="w-full rounded border border-vpro-border bg-white px-2 py-1.5 text-sm"
          bind:value={createCollected}
          disabled={s.crudBusy}
          placeholder="C or V"
        />
      </div>
    </div>
    <div class="flex flex-wrap gap-2">
      <button
        type="button"
        data-veg-create-submit
        class="rounded bg-vpro-navy px-3 py-1 text-xs font-medium text-white disabled:opacity-50"
        disabled={s.crudBusy || !createSpecies.trim()}
        onclick={h.onsubmitcreate}>Create row</button
      >
      <button
        type="button"
        class="rounded border border-vpro-border bg-white px-3 py-1 text-xs text-vpro-ink"
        disabled={s.crudBusy}
        onclick={h.oncancelcreate}>Cancel</button
      >
    </div>
  </div>
{/if}

{#if s.original && s.currentRowId && s.deleteConfirmRowId === s.currentRowId}
  <div
    class="rounded border border-vpro-error bg-vpro-error-bg p-2.5 flex flex-wrap items-center justify-between gap-2 text-xs text-vpro-ink"
    data-veg-delete-confirm
  >
    <span
      >Delete vegetation row {twoPageVegetationStoredText(s.original, s.currentRowId, 'ID')} ({twoPageVegetationStoredText(
        s.original,
        s.currentRowId,
        'Species'
      )})? Can be restored from Deleted rows.</span
    >
    <div class="flex gap-2">
      <button
        type="button"
        data-veg-delete-confirm-btn
        class="rounded bg-vpro-error px-2.5 py-1 text-xs font-medium text-white disabled:opacity-50"
        disabled={s.crudBusy}
        onclick={h.onconfirmdelete}>Confirm delete</button
      >
      <button
        type="button"
        class="rounded border border-vpro-border bg-white px-2.5 py-1 text-xs text-vpro-ink"
        disabled={s.crudBusy}
        onclick={h.oncanceldelete}>Cancel</button
      >
    </div>
  </div>
{/if}

{#if s.deletedHistoryOpen}
  <div class="rounded border border-vpro-border bg-vpro-canvas p-3 space-y-2" data-veg-deleted-panel>
    <p class="text-xs font-semibold text-vpro-navy">Deleted Vegetation Rows ({s.deletedRows.length})</p>
    {#if s.deletedRows.length === 0}
      <p class="text-xs text-vpro-ink-muted">No deleted rows recorded for this form.</p>
    {:else}
      <div class="space-y-1.5">
        {#each s.deletedRows as entry (entry.deleteRequestId)}
          <div
            class="flex flex-wrap items-center justify-between gap-2 rounded border border-vpro-border bg-white p-2 text-xs"
          >
            <span
              >ID {entry.deletedId} · <strong>{entry.species}</strong>
              {entry.layer ? `(${entry.layer})` : ''} · Deleted {entry.deletedAt} by {entry.deletedBy}</span
            >
            {#if entry.restored}
              <span class="rounded bg-vpro-success-bg px-2 py-0.5 text-vpro-forest">Restored</span>
            {:else}
              <button
                type="button"
                data-veg-restore-btn={entry.deleteRequestId}
                class="rounded border border-vpro-navy bg-vpro-navy px-2.5 py-1 text-xs font-medium text-white disabled:opacity-50"
                disabled={s.crudBusy || s.fieldsDisabled || s.unsaved || s.closeBlocked}
                onclick={() => h.onrestore(entry.deleteRequestId)}>Restore row</button
              >
            {/if}
          </div>
        {/each}
      </div>
    {/if}
  </div>
{/if}
