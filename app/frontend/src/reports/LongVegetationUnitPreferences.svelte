<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
  import { notifications } from '../shell/notificationService.svelte';
  import { ReadRequests } from '../shared/readRequests';
  import { longVegetationUnitChoices, type LongVegetationUnitPreferencesSession } from './longVegetationUnitPreferences';

  let { contextId, preferences, operationHeld = false, mutationHeld = false, onReadBusyChange }: {
    contextId: string;
    preferences: LongVegetationUnitPreferencesSession;
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
          notifications.success('Long Vegetation Unit Groups saved', receipt.outcome.changed ? 'Saved Unit Groups preference.' : 'No Unit Groups changes.', {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
        } else if (receipt.outcome.committed) {
          notifications.warning('Long Vegetation Unit Groups saved with warning', receipt.outcome.errorMessage, {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
          lastViewError = receipt.outcome.errorMessage;
        } else if (receipt.outcome.errorMessage) {
          notifications.error('Long Vegetation Unit Groups save failed', receipt.outcome.errorMessage, {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
          lastViewError = receipt.outcome.errorMessage;
        } else {
          notifications.info('Long Vegetation Unit Groups unchanged', 'No Unit Groups changes were needed.', {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
        }
      }
    }
    notifiedReceipts = receipts.length;
    const viewErr = view.error ?? '';
    if (viewErr && viewErr !== lastViewError) {
      notifications.error('Long Vegetation Unit Groups preference failed', viewErr, {
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
      const value = await reads.track(VegetationReportService.GetLongVegetationUnitPreferences(contextId));
      if (request !== generation) return;
      preferences.applyLoaded(value, token);
      if (typeof syncPreferenceNotifications === 'function') syncPreferenceNotifications();
    } catch (cause) {
      if (request === generation) {
        error = `Saved Unit Groups unavailable; no defaults applied: ${String(cause)}`;
        if (typeof notifications !== 'undefined') {
          notifications.error('Long Vegetation Unit Groups load failed', error, {
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
      await preferences.save(value => VegetationReportService.SaveLongVegetationUnitPreferences(contextId, JSON.stringify(value)));
      if (typeof syncPreferenceNotifications === 'function') syncPreferenceNotifications();
      else if (typeof notifications !== 'undefined') {
        const settled = preferences.view();
        const latest = settled.receipts?.[settled.receipts.length - 1];
        if (latest?.kind === 'known') {
          if (latest.outcome.committed && !latest.outcome.errorMessage) {
            notifications.success('Long Vegetation Unit Groups saved', latest.outcome.changed ? 'Saved Unit Groups preference.' : 'No Unit Groups changes.', {
              category: 'reports', source: 'Long Vegetation',
              contextTag: typeof contextId === 'string' && contextId ? contextId : undefined,
            });
          } else if (latest.outcome.errorMessage) {
            notifications.error('Long Vegetation Unit Groups save failed', latest.outcome.errorMessage, {
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
          notifications.error('Long Vegetation Unit Groups save failed', error, {
            category: 'reports', source: 'Long Vegetation',
            contextTag: typeof contextId === 'string' && contextId ? contextId : undefined,
          });
        }
      }
    }
  }
  function edit(raw: string) {
    if (busy || mutationHeld || view.busy || view.blocked) return;
    cancel(); error = ''; preferences.editUnitGroups(raw);
  }
  onDestroy(() => { unsubscribe(); cancel(); });
</script>

<section class="unit-preferences" aria-label="Saved Long Vegetation Unit Groups" data-long-vegetation-unit-preferences>
  {#if view.draftError}<p class="error" role="alert">{view.draftError}</p>{/if}
  {#each view.receipts as receipt}
    {#if receipt.kind !== 'known'}
      <p data-long-vegetation-unit-receipt role="alert">
        Preference receipt: outcome unknown; changed unknown; committed unknown. {receipt.errorMessage}
      </p>
    {/if}
  {/each}
  <label for="long-vegetation-unit-groups">
    <span>Unit Groups</span>
    <select id="long-vegetation-unit-groups" data-source-control="rptLvUnitGroups" value={view.draft.unitGroups}
      aria-invalid={!!view.draftError}
      disabled={busy || mutationHeld || view.busy || view.blocked || !view.saved}
      onchange={event => { const raw = event.currentTarget.value; edit(raw); }}>
      <option value="" disabled>Load saved Unit Groups</option>
      {#each longVegetationUnitChoices as mode}
        <option value={String(mode.value)} disabled={!availability?.[mode.capability] && view.saved?.unitGroups !== mode.value}>
          {mode.label}
        </option>
      {/each}
    </select>
  </label>
  <div class="actions">
    <button data-long-vegetation-unit-load disabled={busy || operationHeld || view.busy || view.blocked}
      onclick={load}>Load saved Unit Groups</button>
    <button data-long-vegetation-unit-save
      disabled={busy || operationHeld || view.busy || view.blocked || view.authorityUnknown || !!view.draftError || !view.saved}
      onclick={save}>Save Unit Groups</button>
    <button data-long-vegetation-unit-undo disabled={busy || mutationHeld || view.busy || view.blocked || !view.saved}
      onclick={() => { cancel(); preferences.undo(); }}>Undo Unit Groups draft</button>
    {#if view.blocked && !view.busy}
      <button data-long-vegetation-unit-acknowledge disabled={busy || mutationHeld}
        onclick={() => preferences.acknowledge()}>Acknowledge Unit Groups outcome</button>
    {/if}
    {#if busy}<button onclick={cancel}>Cancel Unit Groups read</button>{/if}
  </div>
  <p class="guidance">Load saved Unit Groups before editing; no defaults are applied. Drafts do not change report output.
    Save explicitly, acknowledge and reload report options. Selected fields require a current owned session Build
    and independently enabled consumers; all-project fallback remains unavailable.
    None uses Env/current selected-list joins, not None species grouping.
    Retaining an unchanged unavailable saved choice does not enable its report.
    Changing Enforce rules resets the saved Unit Groups to Site unit table; retained drafts require owned Load or correction.
    Receipts remain after acknowledgement; unknown outcomes require explicit owned Load, never blind Save replay.
    Only LVUnitGroups changes in YAML; no registry, project data, source scratch tables, audits or printing.</p>
</section>

<style>
  .unit-preferences { display: grid; grid-template-columns: minmax(0, 1fr); gap: .75rem; min-width: 0; }
  label { display: grid; gap: .35rem; min-width: 0; }
  span { overflow-wrap: anywhere; }
  select { width: 100%; box-sizing: border-box; min-width: 0; border: 1px solid #D8D8D8; border-radius: .4rem; padding: .5rem; }
  .actions { display: flex; flex-wrap: wrap; gap: .5rem; align-items: center; }
  button { border: 1px solid #D8D8D8; border-radius: .4rem; padding: .5rem .75rem; background: #FFFFFF; }
  button:disabled { opacity: .5; }
  .error { color: #D8292F; } .guidance { color: #474543; font-size: .875rem; }
</style>
