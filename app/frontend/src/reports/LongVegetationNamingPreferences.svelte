<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
  import { notifications } from '../shell/notificationService.svelte';
  import { ReadRequests } from '../shared/readRequests';
  import { longVegetationNamingChoices, type LongVegetationNamingPreferencesSession } from './longVegetationNamingPreferences';

  let { contextId, preferences, operationHeld = false, mutationHeld = false, selectedFieldEnabled = false, onReadBusyChange }: {
    contextId: string;
    preferences: LongVegetationNamingPreferencesSession;
    operationHeld?: boolean;
    mutationHeld?: boolean;
    selectedFieldEnabled?: boolean;
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
          notifications.success('Long Vegetation Show preferences saved', receipt.outcome.changed ? 'Saved Show preference.' : 'No Show preference changes.', {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
        } else if (receipt.outcome.committed) {
          notifications.warning('Long Vegetation Show preferences saved with warning', receipt.outcome.errorMessage, {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
          lastViewError = receipt.outcome.errorMessage;
        } else if (receipt.outcome.errorMessage) {
          notifications.error('Long Vegetation Show save failed', receipt.outcome.errorMessage, {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
          lastViewError = receipt.outcome.errorMessage;
        } else {
          notifications.info('Long Vegetation Show preferences unchanged', 'No Show preference changes were needed.', {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
        }
      }
    }
    notifiedReceipts = receipts.length;
    const viewErr = view.error ?? '';
    if (viewErr && viewErr !== lastViewError) {
      notifications.error('Long Vegetation Show preference failed', viewErr, {
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
      const value = await reads.track(VegetationReportService.GetLongVegetationNamingPreferences(contextId));
      if (request !== generation) return;
      preferences.applyLoaded(value, token);
      if (typeof syncPreferenceNotifications === 'function') syncPreferenceNotifications();
    } catch (cause) {
      if (request === generation) {
        error = `Saved Show values unavailable; no defaults applied: ${String(cause)}`;
        if (typeof notifications !== 'undefined') {
          notifications.error('Long Vegetation Show load failed', error, {
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
      await preferences.save(value => VegetationReportService.SaveLongVegetationNamingPreferences(contextId, JSON.stringify(value)));
      if (typeof syncPreferenceNotifications === 'function') syncPreferenceNotifications();
      else if (typeof notifications !== 'undefined') {
        const settled = preferences.view();
        const latest = settled.receipts?.[settled.receipts.length - 1];
        if (latest?.kind === 'known') {
          if (latest.outcome.committed && !latest.outcome.errorMessage) {
            notifications.success('Long Vegetation Show preferences saved', latest.outcome.changed ? 'Saved Show preference.' : 'No Show preference changes.', {
              category: 'reports', source: 'Long Vegetation',
              contextTag: typeof contextId === 'string' && contextId ? contextId : undefined,
            });
          } else if (latest.outcome.errorMessage) {
            notifications.error('Long Vegetation Show save failed', latest.outcome.errorMessage, {
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
          notifications.error('Long Vegetation Show save failed', error, {
            category: 'reports', source: 'Long Vegetation',
            contextTag: typeof contextId === 'string' && contextId ? contextId : undefined,
          });
        }
      }
    }
  }
  function edit(raw: string) {
    if (busy || mutationHeld || view.busy || view.blocked) return;
    cancel(); error = ''; preferences.editMode(raw);
  }
  onDestroy(() => { unsubscribe(); cancel(); });
</script>

<section class="naming" aria-label="Saved Long Vegetation Show preferences" data-long-vegetation-naming>
  {#if view.draftError}<p class="error" role="alert">{view.draftError}</p>{/if}
  {#each view.receipts as receipt}
    {#if receipt.kind !== 'known'}
      <p data-long-vegetation-naming-receipt role="alert">
        Preference receipt: outcome unknown; changed unknown; committed unknown. {receipt.errorMessage}
      </p>
    {/if}
  {/each}
  <label for="long-vegetation-naming">
    <span>Show</span>
    <select id="long-vegetation-naming" data-source-control="rptLvShowCommon" value={view.draft.mode}
      aria-invalid={!!view.draftError}
      disabled={busy || mutationHeld || view.busy || view.blocked || !view.saved}
      onchange={event => { const raw = event.currentTarget.value; edit(raw); }}>
      <option value="" disabled>Load saved Show</option>
      {#each longVegetationNamingChoices as choice}
        <option value={String(choice.value)} disabled={!availability?.[choice.capability] && view.saved?.mode !== choice.value}>
          {choice.label}
        </option>
      {/each}
      {#if view.saved?.mode === 4}
        <option value="4" disabled>Saved selected-field mode ({selectedFieldEnabled ? 'read-only here' : 'unavailable'})</option>
      {/if}
    </select>
  </label>
  {#if view.saved}
    <dl><div><dt>Saved selected field (read-only)</dt>
      <dd data-source-control="cmbShowField">{JSON.stringify(view.saved.selectedField)}</dd></div></dl>
    {#if view.draft.selectedField !== view.saved.selectedField}
      <p role="status">The staged Show selection clears the selected field on Save.</p>
    {/if}
  {/if}
  <div class="actions">
    <button data-long-vegetation-naming-load disabled={busy || operationHeld || view.busy || view.blocked}
      onclick={load}>Load saved Show</button>
    <button data-long-vegetation-naming-save
      disabled={busy || operationHeld || view.busy || view.blocked || view.authorityUnknown || !!view.draftError || !view.saved}
      onclick={save}>Save Show preferences</button>
    <button data-long-vegetation-naming-undo disabled={busy || mutationHeld || view.busy || view.blocked || !view.saved}
      onclick={() => { cancel(); preferences.undo(); }}>Undo Show draft</button>
    {#if view.blocked && !view.busy}
      <button data-long-vegetation-naming-acknowledge disabled={busy || mutationHeld}
        onclick={() => preferences.acknowledge()}>Acknowledge Show outcome</button>
    {/if}
    {#if busy}<button onclick={cancel}>Cancel Show read</button>{/if}
  </div>
  <p class="guidance">Load saved Show values before editing; no defaults are applied. A staged source Show selection
    clears its paired selected field, even after returning to the original choice. Undo restores the saved pair.
    Drafts do not change report output. Save explicitly, acknowledge and reload report options.
    Historical unavailable modes can remain unchanged without enabling their report.
    Receipts remain after acknowledgement; unknown outcomes require explicit owned Load, never blind Save replay.
    Only LVShowEnglishName and the source-required empty LVShowField change in YAML; no registry, project data,
    source audits, custom-field selection, new calculations or printing.</p>
</section>

<style>
  .naming { display: grid; grid-template-columns: minmax(0, 1fr); gap: .75rem; min-width: 0; }
  label { display: grid; gap: .35rem; min-width: 0; }
  span, dd { overflow-wrap: anywhere; } dd { margin: .25rem 0 0; }
  select { width: 100%; box-sizing: border-box; min-width: 0; border: 1px solid #D8D8D8; border-radius: .4rem; padding: .5rem; }
  .actions { display: flex; flex-wrap: wrap; gap: .5rem; align-items: center; }
  button { border: 1px solid #D8D8D8; border-radius: .4rem; padding: .5rem .75rem; background: #FFFFFF; }
  button:disabled { opacity: .5; }
  .error { color: #D8292F; } .guidance { color: #474543; font-size: .875rem; }
</style>
