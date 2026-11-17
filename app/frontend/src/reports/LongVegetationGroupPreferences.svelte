<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
  import { notifications } from '../shell/notificationService.svelte';
  import { ReadRequests } from '../shared/readRequests';
  import { longVegetationGroupChoices, type LongVegetationGroupPreferencesSession } from './longVegetationGroupPreferences';

  let { contextId, preferences, operationHeld = false, mutationHeld = false, onReadBusyChange }: {
    contextId: string;
    preferences: LongVegetationGroupPreferencesSession;
    operationHeld?: boolean;
    mutationHeld?: boolean;
    onReadBusyChange: (busy: boolean) => void;
  } = $props();
  let view = $state(untrack(() => preferences.view()));
  let availability = $state(untrack(() => preferences.availability()));
  let busy = $state(false);
  let error = $state('');
  const reads = new ReadRequests();
  let generation = 0;
  let notifiedReceipts = 0;
  let lastViewError = '';
  function syncPreferenceNotifications() {
    if (typeof notifications === 'undefined') return;
    const receipts = view.receipts ?? [];
    if (receipts.length < notifiedReceipts) notifiedReceipts = 0;
    const ctxTag = typeof contextId === 'string' && contextId ? contextId : undefined;
    for (let i = notifiedReceipts; i < receipts.length; i++) {
      const receipt = receipts[i];
      if (receipt.kind === 'known') {
        if (receipt.outcome.committed && !receipt.outcome.errorMessage) {
          notifications.success('Long Vegetation report grouping saved', receipt.outcome.changed ? 'Saved report grouping preference.' : 'No report grouping changes.', {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
        } else if (receipt.outcome.committed) {
          notifications.warning('Long Vegetation report grouping saved with warning', receipt.outcome.errorMessage, {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
          lastViewError = receipt.outcome.errorMessage;
        } else if (receipt.outcome.errorMessage) {
          notifications.error('Long Vegetation report grouping save failed', receipt.outcome.errorMessage, {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
          lastViewError = receipt.outcome.errorMessage;
        } else {
          notifications.info('Long Vegetation report grouping unchanged', 'No report grouping changes were needed.', {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
        }
      }
    }
    notifiedReceipts = receipts.length;
    const viewErr = view.error ?? '';
    if (viewErr && viewErr !== lastViewError) {
      notifications.error('Long Vegetation report grouping preference failed', viewErr, {
        category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
      });
    }
    lastViewError = viewErr;
  }
  const unsubscribe = untrack(() => preferences.subscribe(() => {
    view = preferences.view(); availability = preferences.availability();
    syncPreferenceNotifications();
  }));
  syncPreferenceNotifications();
  function cancel() {
    generation++; reads.cancelAll(); preferences.cancelLoad(); busy = false; onReadBusyChange(false);
  }
  async function load() {
    if (busy || operationHeld || view.busy || view.blocked) return;
    cancel(); const request = generation, token = preferences.beginLoad();
    error = ''; busy = true; onReadBusyChange(true);
    try {
      const value = await reads.track(VegetationReportService.GetLongVegetationGroupPreferences(contextId));
      if (request !== generation) return;
      preferences.applyLoaded(value, token);
      if (typeof syncPreferenceNotifications === 'function') syncPreferenceNotifications();
    } catch (cause) {
      if (request === generation) {
        error = `Saved report grouping unavailable; no defaults applied: ${String(cause)}`;
        if (typeof notifications !== 'undefined') {
          notifications.error('Long Vegetation report grouping load failed', error, {
            category: 'reports', source: 'Long Vegetation',
            contextTag: typeof contextId === 'string' && contextId ? contextId : undefined,
          });
        }
      }
    } finally {
      if (request === generation) { busy = false; onReadBusyChange(false); }
    }
  }
  async function save() {
    if (busy || operationHeld || view.busy || view.blocked || view.authorityUnknown || view.draftError) return;
    cancel(); const request = generation; error = '';
    try {
      await preferences.save(value => VegetationReportService.SaveLongVegetationGroupPreferences(contextId, JSON.stringify(value)));
      if (typeof syncPreferenceNotifications === 'function') syncPreferenceNotifications();
      else if (typeof notifications !== 'undefined') {
        const settled = preferences.view();
        const latest = settled.receipts?.[settled.receipts.length - 1];
        if (latest?.kind === 'known') {
          if (latest.outcome.committed && !latest.outcome.errorMessage) {
            notifications.success('Long Vegetation report grouping saved', latest.outcome.changed ? 'Saved report grouping preference.' : 'No report grouping changes.', {
              category: 'reports', source: 'Long Vegetation',
              contextTag: typeof contextId === 'string' && contextId ? contextId : undefined,
            });
          } else if (latest.outcome.errorMessage) {
            notifications.error('Long Vegetation report grouping save failed', latest.outcome.errorMessage, {
              category: 'reports', source: 'Long Vegetation',
              contextTag: typeof contextId === 'string' && contextId ? contextId : undefined,
            });
          }
        }
      }
    } catch (cause) {
      if (request === generation) {
        error = String(cause);
        if (typeof notifications !== 'undefined') {
          notifications.error('Long Vegetation report grouping save failed', error, {
            category: 'reports', source: 'Long Vegetation',
            contextTag: typeof contextId === 'string' && contextId ? contextId : undefined,
          });
        }
      }
    }
  }
  function edit(raw: string) {
    if (busy || mutationHeld || view.busy || view.blocked) return;
    cancel(); error = ''; preferences.editGroup(raw);
  }
  onDestroy(() => { unsubscribe(); cancel(); });
</script>

<section class="grouping" aria-label="Saved Long Vegetation report grouping" data-long-vegetation-grouping>
  {#if view.draftError}<p class="error" role="alert">{view.draftError}</p>{/if}
  {#each view.receipts as receipt}
    {#if receipt.kind !== 'known'}
      <p data-long-vegetation-group-receipt role="alert">
        Preference receipt: outcome unknown; changed unknown; committed unknown. {receipt.errorMessage}
      </p>
    {/if}
  {/each}
  <label for="long-vegetation-group">
    <span>Group by</span>
    <select id="long-vegetation-group" data-source-control="rptLvGroupBy" value={view.draft.groupBy}
      aria-invalid={!!view.draftError}
      disabled={busy || mutationHeld || view.busy || view.blocked || !view.saved}
      onchange={event => { const raw = event.currentTarget.value; edit(raw); }}>
      <option value="" disabled>Load saved Group by</option>
      {#each longVegetationGroupChoices as mode}
        <option value={String(mode.value)} disabled={!availability?.[mode.capability] && view.saved?.groupBy !== mode.value}>
          {mode.label}
        </option>
      {/each}
    </select>
  </label>
  <div class="actions">
    <button data-long-vegetation-group-load disabled={busy || operationHeld || view.busy || view.blocked}
      onclick={load}>Load saved report grouping</button>
    <button data-long-vegetation-group-save
      disabled={busy || operationHeld || view.busy || view.blocked || view.authorityUnknown || !!view.draftError || !view.saved}
      onclick={save}>Save report grouping</button>
    <button data-long-vegetation-group-undo disabled={busy || mutationHeld || view.busy || view.blocked || !view.saved}
      onclick={() => { cancel(); preferences.undo(); }}>Undo report grouping draft</button>
    {#if view.blocked && !view.busy}
      <button data-long-vegetation-group-acknowledge disabled={busy || mutationHeld}
        onclick={() => preferences.acknowledge()}>Acknowledge report grouping outcome</button>
    {/if}
    {#if busy}<button onclick={cancel}>Cancel report grouping read</button>{/if}
  </div>
  <p class="guidance">Load saved grouping before editing; no defaults are applied. Drafts do not change report output.
    Save explicitly, acknowledge and reload report options. Unavailable modes cannot be newly selected;
    retaining an unchanged saved mode does not enable its report.
    Receipts remain after acknowledgement; unknown outcomes require explicit owned Load, never blind Save replay.
    Only LVGroupBy changes in YAML; no registry, project data, source audits, new calculations or printing.</p>
</section>

<style>
  .grouping { display: grid; grid-template-columns: minmax(0, 1fr); gap: .75rem; min-width: 0; }
  label { display: grid; gap: .35rem; min-width: 0; }
  span { overflow-wrap: anywhere; }
  select { width: 100%; box-sizing: border-box; min-width: 0; border: 1px solid #D8D8D8; border-radius: .4rem; padding: .5rem; }
  .actions { display: flex; flex-wrap: wrap; gap: .5rem; align-items: center; }
  button { border: 1px solid #D8D8D8; border-radius: .4rem; padding: .5rem .75rem; background: #FFFFFF; }
  button:disabled { opacity: .5; }
  .error { color: #D8292F; } .guidance { color: #474543; font-size: .875rem; }
</style>
