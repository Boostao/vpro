<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
  import { notifications } from '../shell/notificationService.svelte';
  import { ReadRequests } from '../shared/readRequests';
  import { longVegetationThresholdFields, type LongVegetationThresholdPreferencesSession, type LongVegetationThresholdDraft } from './longVegetationThresholdPreferences';

  let { contextId, preferences, operationHeld = false, mutationHeld = false, onReadBusyChange }: {
    contextId: string;
    preferences: LongVegetationThresholdPreferencesSession;
    operationHeld?: boolean;
    mutationHeld?: boolean;
    onReadBusyChange: (busy: boolean) => void;
  } = $props();
  let view = $state(untrack(() => preferences.view()));
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
          notifications.success('Long Vegetation report thresholds saved', receipt.outcome.changed ? 'Saved report threshold preferences.' : 'No report threshold changes.', {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
        } else if (receipt.outcome.committed) {
          notifications.warning('Long Vegetation report thresholds saved with warning', receipt.outcome.errorMessage, {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
          lastViewError = receipt.outcome.errorMessage;
        } else if (receipt.outcome.errorMessage) {
          notifications.error('Long Vegetation report thresholds save failed', receipt.outcome.errorMessage, {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
          lastViewError = receipt.outcome.errorMessage;
        } else {
          notifications.info('Long Vegetation report thresholds unchanged', 'No report threshold changes were needed.', {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
        }
      }
    }
    notifiedReceipts = receipts.length;
    const viewErr = view.error ?? '';
    if (viewErr && viewErr !== lastViewError) {
      notifications.error('Long Vegetation report thresholds preference failed', viewErr, {
        category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
      });
    }
    lastViewError = viewErr;
  }
  const unsubscribe = untrack(() => preferences.subscribe(() => {
    view = preferences.view();
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
      const value = await reads.track(VegetationReportService.GetLongVegetationThresholdPreferences(contextId));
      if (request !== generation) return;
      preferences.applyLoaded(value, token);
      if (typeof syncPreferenceNotifications === 'function') syncPreferenceNotifications();
    } catch (cause) {
      if (request === generation) {
        error = `Saved report thresholds unavailable; no defaults applied: ${String(cause)}`;
        if (typeof notifications !== 'undefined') {
          notifications.error('Long Vegetation report thresholds load failed', error, {
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
      await preferences.save(value => VegetationReportService.SaveLongVegetationThresholdPreferences(contextId, JSON.stringify(value)));
      if (typeof syncPreferenceNotifications === 'function') syncPreferenceNotifications();
      else if (typeof notifications !== 'undefined') {
        const settled = preferences.view();
        const latest = settled.receipts?.[settled.receipts.length - 1];
        if (latest?.kind === 'known') {
          if (latest.outcome.committed && !latest.outcome.errorMessage) {
            notifications.success('Long Vegetation report thresholds saved', latest.outcome.changed ? 'Saved report threshold preferences.' : 'No report threshold changes.', {
              category: 'reports', source: 'Long Vegetation',
              contextTag: typeof contextId === 'string' && contextId ? contextId : undefined,
            });
          } else if (latest.outcome.errorMessage) {
            notifications.error('Long Vegetation report thresholds save failed', latest.outcome.errorMessage, {
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
          notifications.error('Long Vegetation report thresholds save failed', error, {
            category: 'reports', source: 'Long Vegetation',
            contextTag: typeof contextId === 'string' && contextId ? contextId : undefined,
          });
        }
      }
    }
  }
  function edit(key: keyof LongVegetationThresholdDraft, raw: string) {
    if (busy || mutationHeld || view.busy || view.blocked) return;
    cancel(); error = ''; preferences.editThreshold(key, raw);
  }
  onDestroy(() => { unsubscribe(); cancel(); });
</script>

<section class="thresholds" aria-label="Saved Long Vegetation report thresholds" data-long-vegetation-thresholds>
  {#if view.draftError}<p class="error" role="alert">{view.draftError}</p>{/if}
  {#each view.receipts as receipt}
    {#if receipt.kind !== 'known'}
      <p data-long-vegetation-threshold-receipt role="alert">
        Preference receipt: outcome unknown; changed unknown; committed unknown. {receipt.errorMessage}
      </p>
    {/if}
  {/each}
  <div class="fields">
    {#each longVegetationThresholdFields as field}
      <label for={'long-vegetation-threshold-' + field.key}>
        <span>{field.label}</span>
        <div class="value">
          <input id={'long-vegetation-threshold-' + field.key} type="text" inputmode="decimal" data-source-control={field.control}
            value={view.draft[field.key]} aria-invalid={!!view.draftError}
            disabled={busy || mutationHeld || view.busy || view.blocked || !view.initialized}
            oninput={event => { const raw = event.currentTarget.value; edit(field.key, raw); }} />
          <span>%</span>
        </div>
      </label>
    {/each}
  </div>
  <div class="actions">
    <button data-long-vegetation-threshold-load disabled={busy || operationHeld || view.busy || view.blocked}
      onclick={load}>Load saved report thresholds</button>
    <button data-long-vegetation-threshold-save
      disabled={busy || operationHeld || view.busy || view.blocked || view.authorityUnknown || !!view.draftError || !view.saved}
      onclick={save}>Save report thresholds</button>
    <button data-long-vegetation-threshold-undo disabled={busy || mutationHeld || view.busy || view.blocked || !view.saved}
      onclick={() => { cancel(); preferences.undo(); }}>Undo report threshold draft</button>
    {#if view.blocked && !view.busy}
      <button data-long-vegetation-threshold-acknowledge disabled={busy || mutationHeld}
        onclick={() => preferences.acknowledge()}>Acknowledge report threshold outcome</button>
    {/if}
    {#if busy}<button onclick={cancel}>Cancel report threshold read</button>{/if}
  </div>
  <p class="guidance">Load saved thresholds before editing; no defaults are applied. Drafts do not change report output.
    Save explicitly, acknowledge and reload report options. Source comparisons are strict; constant-list mode bypasses these thresholds.
    No new range is imposed. Receipts remain after acknowledgement; unknown outcomes require explicit owned Load, never blind Save replay.
    Only these two YAML preferences change; no registry, project data, source audits or printing.</p>
</section>

<style>
  .thresholds { display: grid; grid-template-columns: minmax(0, 1fr); gap: .75rem; min-width: 0; }
  .fields { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 20rem), 1fr)); gap: .75rem; }
  label { display: grid; gap: .35rem; min-width: 0; }
  .value { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: .5rem; align-items: center; }
  span { overflow-wrap: anywhere; }
  input { width: 100%; box-sizing: border-box; min-width: 0; border: 1px solid #D8D8D8; border-radius: .4rem; padding: .5rem; }
  .actions { display: flex; flex-wrap: wrap; gap: .5rem; align-items: center; }
  button { border: 1px solid #D8D8D8; border-radius: .4rem; padding: .5rem .75rem; background: #FFFFFF; }
  button:disabled { opacity: .5; }
  .error { color: #D8292F; } .guidance { color: #474543; font-size: .875rem; }
</style>
