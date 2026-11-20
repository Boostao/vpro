<script lang="ts">
  import { twoPageSoilKind, type TwoPageSoilForm, type TwoPageSoilOriginal } from './twoPageSoilEditor';
  import { twoPageSoilStoredText } from './twoPageSoilPresentation';
  import type { SoilReferenceView } from './twoPageSoilReferences';
  import type { TwoPageSoilView } from './twoPageSoilSession';

  export interface DeletedSoilHorizonEntry {
    deleteRequestId: string;
    plotNumber: string;
    form: string;
    kind: string;
    deletedId: number;
    horizon: string;
    upperDepth?: number;
    lowerDepth?: number;
    deletedBy: string;
    deletedAt: string;
    restored: boolean;
  }

  let {
    state: s,
    handlers: h,
  }: {
    state: {
      project: string;
      plot: string;
      form: TwoPageSoilForm;
      parentBlocked: boolean;
      error: string | null;
      view: TwoPageSoilView;
      referenceView: SoilReferenceView;
      unsaved: boolean;
      closeBlocked: boolean;
      deleteRestoreBusy: boolean;
      showDeletedHistory: boolean;
      deleteConfirmRowId: string | null;
      currentRowId: string | undefined;
      original: TwoPageSoilOriginal | null;
      deletedHorizons: DeletedSoilHorizonEntry[];
    };
    handlers: {
      onconfirmdelete: () => void;
      oncanceldelete: () => void;
      onrestore: (deleteRequestId: string) => void;
      onstagecreation: (raw: string) => void;
      oncreate: () => void;
    };
  } = $props();
</script>

{#if s.parentBlocked}<p role="status">
    Finish actual parent drafts/operations and unlock the plot before new soil staging.
  </p>{/if}
{#if s.error}<p role="alert" class="break-words text-sm text-red-700">{s.error}</p>{/if}
{#if s.view.error && s.view.error !== s.error}<p role="alert" class="break-words text-sm text-red-700">
    {s.view.error}
  </p>{/if}
{#if s.referenceView.error}<p role="alert" class="break-words text-sm text-red-700">{s.referenceView.error}</p>{/if}
{#if s.referenceView.busy}<p role="status">Reading current source soil definitions...</p>{/if}
{#if s.view.blocked}<p role="alert">
    Save outcome unresolved. Recover the exact retained request; do not repeat Save.
  </p>{/if}
{#if s.view.noCommitCertificate}
  <p role="status">
    Server certified no commit for {s.view.noCommitCertificate.requestId}. Drafts remain for correction or Undo; another
    Save needs a new request.
  </p>
{/if}
{#if Object.keys(s.view.drafts).length}
  <p role="status">
    {Object.keys(s.view.drafts).length} retained field draft(s). Save applies all retained edits together, including other
    physical rows.
  </p>
{/if}

{#if s.deleteConfirmRowId && s.currentRowId && s.deleteConfirmRowId === s.currentRowId && s.original}
  <fieldset
    class="min-w-0 space-y-2 rounded border border-red-300 border-t-[3px] border-t-vpro-gold bg-red-50/40 p-3"
    data-soil-delete-confirm
  >
    <legend class="text-sm font-semibold text-vpro-navy"
      >Confirm guarded {twoPageSoilKind(s.form)} horizon deletion</legend
    >
    <p class="text-xs text-vpro-ink">
      Delete Horizon <span class="font-mono font-semibold"
        >{twoPageSoilStoredText(s.original, s.currentRowId, 'Horizon')}</span
      >
      (ID <span class="font-mono font-semibold">{twoPageSoilStoredText(s.original, s.currentRowId, 'ID')}</span>) from
      plot <span class="font-mono">{s.plot}</span>? Its child ID remains permanently reserved and full history is
      recorded in <span class="font-mono">{s.project}_Audit</span>.
    </p>
    <div class="flex flex-wrap gap-2">
      <button
        type="button"
        data-soil-confirm-delete-btn
        disabled={s.deleteRestoreBusy || s.view.busy}
        class="rounded bg-vpro-navy px-3 py-1.5 text-xs font-semibold text-white hover:bg-vpro-navy-dark"
        onclick={h.onconfirmdelete}>Confirm delete horizon</button
      >
      <button
        type="button"
        disabled={s.deleteRestoreBusy}
        class="rounded border border-vpro-border bg-white px-3 py-1.5 text-xs"
        onclick={h.oncanceldelete}>Cancel</button
      >
    </div>
  </fieldset>
{/if}

{#if s.showDeletedHistory}
  <fieldset
    class="min-w-0 space-y-2 rounded border border-vpro-border border-t-[3px] border-t-vpro-gold p-3"
    data-soil-deleted-history
  >
    <legend class="text-sm font-semibold text-vpro-navy">Deleted {twoPageSoilKind(s.form)} horizons ({s.plot})</legend>
    {#if s.deletedHorizons.length === 0}
      <p class="text-xs text-vpro-ink-secondary">
        No deleted {twoPageSoilKind(s.form)} horizons recorded for {s.plot}.
      </p>
    {:else}
      <div class="space-y-1">
        {#each s.deletedHorizons as entry (entry.deleteRequestId)}
          <div class="flex flex-wrap items-center justify-between gap-2 rounded border border-vpro-border p-2 text-xs">
            <span
              >Horizon <span class="font-mono font-semibold">{entry.horizon || '(NULL)'}</span> | ID
              <span class="font-mono">{entry.deletedId}</span>
              | {entry.deletedAt} by {entry.deletedBy}</span
            >
            {#if entry.restored}
              <span class="text-vpro-ink-muted">Restored</span>
            {:else}
              <button
                type="button"
                data-soil-restore-btn={entry.deleteRequestId}
                disabled={s.parentBlocked || s.view.busy || s.deleteRestoreBusy || s.unsaved || s.closeBlocked}
                class="rounded border border-vpro-navy bg-white px-2.5 py-1 font-semibold text-vpro-navy hover:bg-vpro-surface-subtle"
                onclick={() => h.onrestore(entry.deleteRequestId)}>Restore horizon</button
              >
            {/if}
          </div>
        {/each}
      </div>
    {/if}
  </fieldset>
{/if}

{#if s.view.creation}
  <fieldset class="min-w-0 space-y-2 rounded border p-3">
    <legend class="font-semibold">New {twoPageSoilKind(s.form)} horizon for {s.plot}</legend>
    <label class="block text-sm font-medium" for={`${s.form}-new-horizon`}>New Horizon</label>
    <input
      id={`${s.form}-new-horizon`}
      data-soil-new-horizon
      data-help-id={s.form === 'SoilHumusXL' ? 'humus.horizon' : 'mineral.horizon'}
      type="text"
      class="w-full min-w-0 rounded border p-2"
      value={s.view.creation.raw}
      aria-invalid={!!s.view.creation.error}
      disabled={s.parentBlocked ||
        s.referenceView.busy ||
        s.view.busy ||
        s.view.blocked ||
        s.view.acknowledgementRequired}
      oninput={(event) => h.onstagecreation(event.currentTarget.value)}
    />
    {#if s.view.creation.error}<p role="alert" class="break-words text-red-700">{s.view.creation.error}</p>{/if}
    <button
      type="button"
      disabled={s.parentBlocked ||
        s.referenceView.busy ||
        s.view.busy ||
        s.view.blocked ||
        s.view.acknowledgementRequired ||
        !!s.view.creation.error}
      onclick={h.oncreate}>Create {twoPageSoilKind(s.form)} horizon</button
    >
    <p class="break-words text-sm">
      Explicit creation only: the server allocates a reserved ID, Flag starts False, and other fields start NULL.
      Ordinary Save and Enter do not create a record. After creation, acknowledge its retained receipt before editing
      the new row.
    </p>
  </fieldset>
{/if}
