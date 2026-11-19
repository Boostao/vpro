<script lang="ts">
  import { untrack } from 'svelte';
  import type { PictureLifecycleSession, PictureLifecycleView } from './pictureLifecycleSession';
  import { pictureCellLabel } from './pictureRead';
  import { notifications } from '../shell/notificationService.svelte';

  let { session, disabled = false }: { session: PictureLifecycleSession; disabled?: boolean } = $props();
  const restoringEnabled = true;
  let view = $state.raw<PictureLifecycleView>(untrack(() => session.view()));
  let localError = $state('');
  $effect(() => session.subscribe(() => { view = session.view(); }));
  const initialView = untrack(() => session.view());
  if (initialView.error) {
    const plotTag = initialView.restoration?.plotNumber ?? initialView.original?.plotNumber;
    notifications.error('Picture lifecycle error', initialView.error, {
      category: 'entry',
      source: 'Plot Pictures',
      contextTag: plotTag ? `Plot ${plotTag}` : undefined,
    });
  }
  function cancelLifecycle() {
    session.cancel();
    const current = session.view();
    if (current.error) {
      const plotTag = current.restoration?.plotNumber ?? current.original?.plotNumber;
      notifications.error('Picture lifecycle cancelled', current.error, {
        category: 'entry',
        source: 'Plot Pictures',
        contextTag: plotTag ? `Plot ${plotTag}` : undefined,
      });
    }
  }
  const close = $derived.by(() => { view; return session.closeState(); });
  const original = $derived(view.restoration?.deletion.request.original ??
    view.original?.records.rows.find(row => row.rowId === view.rowId));
  const columns = $derived(view.restoration?.deletion.request.columns ?? view.original?.records.columns);
  const blocked = $derived(disabled || view.busy || view.blocked || view.acknowledgementRequired);
  async function run(operation: () => unknown | Promise<unknown>) {
    localError = '';
    try {
      const outcome = await operation();
      const current = session.view();
      if (outcome === false && current.error) {
        notifications.error('Picture lifecycle action failed', current.error, {
          category: 'entry',
          source: 'Plot Pictures',
        });
      }
    } catch (cause) {
      localError = `Picture lifecycle action unavailable: ${String(cause)}`;
      notifications.error('Picture lifecycle action failed', localError, {
        category: 'entry',
        source: 'Plot Pictures',
      });
    }
  }
  async function saveLifecycle() {
    localError = '';
    const isRestore = Boolean(view.restoration);
    const plotNumber = view.restoration?.plotNumber ?? view.original?.plotNumber;
    const contextTag = plotNumber ? `Plot ${plotNumber}` : undefined;
    try {
      const ok = await session.save(crypto.randomUUID());
      const current = session.view();
      if (ok) {
        const latest = current.receipts.at(-1);
        const historyId = latest?.kind === 'restore'
          ? latest.receipt.request.historyId
          : latest?.receipt.historyId;
        if (isRestore) {
          notifications.success(
            'Picture reference restored',
            `Restored historical picture reference${historyId ? ` (history ${historyId})` : ''}.`,
            { category: 'entry', source: 'Plot Pictures', contextTag },
          );
        } else {
          notifications.success(
            'Picture reference deleted',
            `Deleted picture reference${historyId ? ` (history ${historyId})` : ''}. Image file was not deleted.`,
            { category: 'entry', source: 'Plot Pictures', contextTag },
          );
        }
      } else if (current.error) {
        notifications.error(
          isRestore ? 'Picture restoration failed' : 'Picture deletion failed',
          current.error,
          { category: 'entry', source: 'Plot Pictures', contextTag },
        );
      }
    } catch (cause) {
      localError = `Picture lifecycle action unavailable: ${String(cause)}`;
      notifications.error(
        isRestore ? 'Picture restoration failed' : 'Picture deletion failed',
        localError,
        { category: 'entry', source: 'Plot Pictures', contextTag },
      );
    }
  }
  async function resolveLifecycle() {
    localError = '';
    try {
      const ok = await session.resolve();
      const current = session.view();
      if (ok) {
        const latest = current.receipts.at(-1);
        if (latest?.kind === 'restore') {
          notifications.success(
            'Picture restoration receipt recovered',
            `Verified restored picture reference (history ${latest.receipt.request.historyId}).`,
            { category: 'entry', source: 'Plot Pictures', contextTag: latest.receipt.request.deletion.plotNumber ? `Plot ${latest.receipt.request.deletion.plotNumber}` : undefined },
          );
        } else if (latest?.kind === 'delete') {
          notifications.success(
            'Picture deletion receipt recovered',
            `Verified deleted picture reference (history ${latest.receipt.historyId}).`,
            { category: 'entry', source: 'Plot Pictures', contextTag: latest.receipt.request.plotNumber ? `Plot ${latest.receipt.request.plotNumber}` : undefined },
          );
        }
      } else if (current.error) {
        notifications.error('Picture lifecycle recovery failed', current.error, {
          category: 'entry',
          source: 'Plot Pictures',
        });
      }
    } catch (cause) {
      localError = `Picture lifecycle action unavailable: ${String(cause)}`;
      notifications.error('Picture lifecycle recovery failed', localError, {
        category: 'entry',
        source: 'Plot Pictures',
      });
    }
  }
</script>

<section class="lifecycle" data-picture-lifecycle aria-label="Picture deletion and historical restoration">
  <h3>Picture reference lifecycle</h3>
  {#if view.busy}
    <button data-picture-lifecycle-cancel onclick={() => cancelLifecycle()}>Cancel acknowledgement or read</button>
  {/if}
  {#if view.blocked}
    <p class="safety">Mutation outcome is unknown. The exact original/request is retained; do not repeat Delete or Restore.</p>
    <button data-picture-lifecycle-recover disabled={view.busy} onclick={() => resolveLifecycle()}>Recover picture receipt read-only</button>
  {/if}
  {#if original && columns}
    <p data-picture-lifecycle-row>Reviewed physical rowid {JSON.stringify(original.rowId)}.
      {view.restoration ? 'Restore the historical reference.' : 'Delete this reference only; its image file is not deleted.'}</p>
    <div class="fields">
      {#each columns as column, index}
        <label>{column.name}<output>{pictureCellLabel(original.cells[index])}</output></label>
      {/each}
    </div>
    <label class="confirmation">
      <input type="checkbox" data-picture-lifecycle-confirm checked={view.confirmed} disabled={blocked}
        onchange={event => { const checked = event.currentTarget.checked; void run(() => session.confirm(checked)); }} />
      {view.restoration ? 'Restore exactly this historical physical row; retain all histories and ID reservations.'
        : 'Delete exactly this reviewed physical reference; permanently reserve its ID and retain technical history.'}
    </label>
    <div class="actions">
      <button data-picture-lifecycle-save disabled={disabled || !close.canSave}
        onclick={() => saveLifecycle()}>
        {view.restoration ? 'Restore historical picture reference' : 'Delete reviewed picture reference'}
      </button>
      <button data-picture-lifecycle-discard disabled={blocked} onclick={() => run(() => session.discard())}>Discard uncommitted review</button>
    </div>
    {#if !close.canSave}<p class="safety">{close.saveReason}</p>{/if}
  {/if}
  {#if view.acknowledgementRequired}
    <p class="safety">The physical operation committed. Acknowledge its receipt before navigating; the receipt remains retained.</p>
    <button data-picture-lifecycle-acknowledge disabled={view.busy || view.blocked} onclick={() => run(() => session.acknowledge())}>
      Acknowledge committed picture receipt
    </button>
  {/if}
  {#if restoringEnabled}
    <details data-picture-lifecycle-history>
      <summary>Historical picture deletions</summary>
      <button data-picture-lifecycle-history-load disabled={blocked || !!original} onclick={() => run(() => session.loadHistory())}>Load deletion history</button>
      {#if view.history}
        {#if view.history.events.length === 0}<p>No owned deletion history was returned.</p>{/if}
        {#each view.history.events as event}
          <div class="history">
            <p>History {event.deletion.historyId}; physical row {JSON.stringify(event.deletion.request.original.rowId)};
              ID {event.deletion.id}; original actor {JSON.stringify(event.deletion.actor)}.
              {event.restoration ? 'Already restored; acknowledgement retained.' : 'Not restored.'}</p>
            <button disabled={blocked || !!original || event.restoration !== null}
              aria-label={`Review picture restoration history ${event.deletion.historyId}`}
              onclick={() => run(() => session.reviewRestoration(event.deletion.historyId))}>Review historical restoration</button>
          </div>
        {/each}
      {/if}
    </details>
  {/if}
  <p class="guidance">Deleting or restoring a picture updates only the plot's photo link in the picture library; image files on disk are never modified or deleted, and change history is preserved.</p>
</section>

<style>
  .lifecycle { display: grid; gap: .65rem; min-width: 0; max-width: 100%; padding: .75rem; border: 1px solid var(--vpro-border); background: var(--vpro-surface); border-radius: .25rem; }
  h3, summary { font-weight: 600; color: var(--vpro-navy); }
  .fields { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 16rem), 1fr)); gap: .65rem; }
  label { display: grid; gap: .25rem; min-width: 0; }
  output { display: block; min-width: 0; padding: .4rem; background: var(--vpro-canvas); overflow-wrap: anywhere; border: 1px solid var(--vpro-border); border-radius: .25rem; }
  .confirmation { display: flex; gap: .5rem; align-items: start; }
  .confirmation input { margin-top: .25rem; flex: none; }
  .actions { display: flex; flex-wrap: wrap; gap: .5rem; }
  button { border: 1px solid var(--vpro-border-strong); border-radius: .25rem; padding: .4rem .6rem; min-width: 0; min-height: 2rem; overflow-wrap: anywhere; color: var(--vpro-ink); background: var(--vpro-surface); }
  button:disabled, input:disabled { opacity: .5; }
  details, .history { min-width: 0; display: block; }
  summary { cursor: pointer; min-height: 2rem; padding: .35rem 0; overflow-wrap: anywhere; }
  .history { padding: .5rem 0; border-bottom: 1px solid var(--vpro-border); }
  p { overflow-wrap: anywhere; }
  .safety { color: var(--vpro-ink); background: var(--vpro-warning-bg); border-left: 3px solid var(--vpro-gold); padding: .5rem; }
  .guidance { color: var(--vpro-ink-secondary); font-size: .8rem; }
</style>
