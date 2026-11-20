<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { AuditRestoreAction, PlotEntryService } from '../../bindings/github.com/boostao/vpro/app';
  import { ReadRequests, formatError } from '../shared/readRequests';
  import {
    sourceAuditFields,
    twoPageAuditFromWire,
    twoPageAuditLabel,
    type TwoPageAuditOwner,
    type TwoPageAuditReview,
  } from './twoPageAudit';

  let {
    onRestored,
    contextId,
    project,
    plot,
    form,
    onBusyChange,
  }: TwoPageAuditOwner & {
    onRestored?: () => void | Promise<void>;
    onBusyChange: (busy: boolean) => void;
  } = $props();
  const owner = untrack(() => ({ contextId, project, plot, form }));
  let review = $state.raw<TwoPageAuditReview | null>(null);
  let busy = $state(false);
  let restoreBusy = $state(false);
  let error = $state('');
  let statusMsg = $state('');
  let selectedIds = $state<string[]>([]);
  let generation = 0;
  const reads = new ReadRequests();

  function initialRestoreIds(loaded: TwoPageAuditReview): string[] {
    const restoreIdx = loaded.records.columns.findIndex((col) => col.name.toLowerCase() === 'restore');
    if (restoreIdx < 0) return [];
    return loaded.records.rows
      .filter((r) => {
        const cell = r.cells[restoreIdx];
        return cell?.storage === 'integer' && (cell.integer === '-1' || cell.integer === '1');
      })
      .map((r) => r.rowId);
  }

  function cancel() {
    generation++;
    reads.cancelAll();
    busy = false;
    onBusyChange(false);
  }
  async function load() {
    if (busy || restoreBusy) return;
    cancel();
    const request = generation;
    review = null;
    error = '';
    statusMsg = '';
    selectedIds = [];
    busy = true;
    onBusyChange(true);
    try {
      const value = await reads.track(
        PlotEntryService.GetTwoPageSourceAuditOriginal(owner.contextId, owner.plot, owner.form)
      );
      if (request !== generation) return;
      review = twoPageAuditFromWire(value, owner);
      selectedIds = initialRestoreIds(review);
    } catch (cause) {
      if (request === generation) error = `Source audit unavailable; history and data unchanged: ${formatError(cause)}`;
    } finally {
      if (request === generation) {
        busy = false;
        onBusyChange(false);
      }
    }
  }

  async function toggleRestoreRow(rowId: string, checked: boolean) {
    if (!review || busy || restoreBusy) return;
    const prev = [...selectedIds];
    const next = checked ? [...new Set([...prev, rowId])] : prev.filter((id) => id !== rowId);
    selectedIds = next;
    restoreBusy = true;
    error = '';
    statusMsg = '';
    onBusyChange(true);
    try {
      await PlotEntryService.SetTwoPageSourceAuditRestoreSelection(owner.contextId, owner.plot, owner.form, next);
      statusMsg = `Updated restore selection (${next.length} row(s) selected).`;
    } catch (cause) {
      selectedIds = prev;
      error = `Restore selection update failed; selection reverted: ${formatError(cause)}`;
    } finally {
      restoreBusy = false;
      onBusyChange(false);
    }
  }

  async function restoreSelected(action: AuditRestoreAction) {
    if (!review || busy || restoreBusy || selectedIds.length === 0) return;
    restoreBusy = true;
    error = '';
    statusMsg = '';
    onBusyChange(true);
    try {
      const ids = [...selectedIds];
      const result = await PlotEntryService.RestoreSelectedTwoPageSourceAudit(
        owner.contextId,
        owner.plot,
        owner.form,
        ids,
        action
      );
      statusMsg = result
        ? `Restored ${ids.length} selected audit row(s).`
        : `Restore command finished for ${ids.length} selected audit row(s).`;
      restoreBusy = false;
      onBusyChange(false);
      await load();
      await onRestored?.();
    } catch (cause) {
      error = `Restore selected audit rows failed: ${formatError(cause)}`;
      restoreBusy = false;
      onBusyChange(false);
    }
  }
  onDestroy(cancel);
</script>

<section
  class="min-w-0 space-y-3 rounded border border-vpro-border bg-white p-3"
  aria-label="VPro Data History"
  data-two-page-audit-panel
  data-source-form="USysAuditXL"
  data-source-parent-form={owner.form}
>
  <h3 class="font-semibold text-vpro-navy">VPro Data History</h3>
  <p class="break-words text-sm text-vpro-ink">
    Owned project {owner.project}; literal plot {JSON.stringify(owner.plot)}.
  </p>
  {#if error}<p role="alert" class="break-words text-sm text-vpro-error">{error}</p>{/if}
  {#if statusMsg}<p role="status" class="break-words text-sm text-vpro-success">{statusMsg}</p>{/if}
  <div class="flex flex-wrap gap-2">
    <button
      type="button"
      class="rounded border border-vpro-navy bg-vpro-navy px-3 py-1 text-xs font-medium text-white disabled:opacity-50"
      disabled={busy || restoreBusy}
      onclick={load}>Load source audit history</button
    >
    {#if busy}<button
        type="button"
        class="rounded border border-vpro-border bg-white px-3 py-1 text-xs text-vpro-ink"
        onclick={cancel}>Cancel audit read</button
      >
      <p role="status">Reading owned history...</p>{/if}
    {#if review && review.records.rows.length > 0}
      <button
        type="button"
        data-audit-restore-retain
        class="rounded border border-vpro-success bg-vpro-success-bg px-3 py-1 text-xs font-medium text-vpro-forest disabled:opacity-50"
        disabled={busy || restoreBusy || selectedIds.length === 0}
        onclick={() => void restoreSelected(AuditRestoreAction.AuditRestoreRetain)}
      >
        Restore selected (Retain history)
      </button>
      <button
        type="button"
        data-audit-restore-prune
        class="rounded border border-vpro-error bg-vpro-error-bg px-3 py-1 text-xs font-medium text-vpro-error disabled:opacity-50"
        disabled={busy || restoreBusy || selectedIds.length === 0}
        onclick={() => void restoreSelected(AuditRestoreAction.AuditRestorePrune)}
      >
        Restore selected (Prune history)
      </button>
    {/if}
  </div>
  {#if review}
    <p role="status" class="text-xs text-vpro-ink">
      {review.records.rows.length} physical audit rows ({selectedIds.length} marked for restore). Ascending SQLite EditWhen
      storage order; ties retain physical row order.
    </p>
    {#each review.records.rows as row (row.rowId)}
      <article
        class="min-w-0 rounded border border-vpro-border p-3"
        data-source-audit-row={row.rowId}
        aria-label={`Physical audit row ${row.rowId}`}
      >
        <div class="mb-2 flex flex-wrap items-center justify-between gap-2">
          <h4 class="break-words font-medium text-vpro-navy">Physical audit row {row.rowId}</h4>
          <label class="flex items-center gap-1.5 text-xs font-medium text-vpro-ink">
            <input
              type="checkbox"
              checked={selectedIds.includes(row.rowId)}
              disabled={busy || restoreBusy}
              onchange={(event) => void toggleRestoreRow(row.rowId, event.currentTarget.checked)}
            />
            Select for restore
          </label>
        </div>
        <dl class="grid min-w-0 grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3">
          {#each sourceAuditFields as [column, label]}
            <div class="min-w-0" data-source-audit-column={column}>
              <dt class="font-medium">{label}</dt>
              <dd class="whitespace-pre-wrap break-words">{twoPageAuditLabel(review, row, column)}</dd>
            </div>
          {/each}
        </dl>
      </article>
    {:else}<p>No audit history for this literal plot.</p>{/each}
  {/if}
  <p class="text-xs text-vpro-ink-secondary">
    Adaptation of USysAuditXL / UsysAuditTrail. NULL, empty text, child identity and stored BOOLEAN values remain
    distinct. Use the row checkboxes to persist Restore flags and explicitly choose Retain or Prune restoration.
  </p>
</section>
