<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
  import { notifications } from '../shell/notificationService.svelte';
  import { ReadRequests } from '../shared/readRequests';
  import { longVegetationSelectedFieldSuggestions, type LongVegetationSelectedFieldPreferencesSession } from './longVegetationSelectedFieldPreferences';

  let { contextId, preferences, operationHeld = false, mutationHeld = false, onReadBusyChange }: {
    contextId: string;
    preferences: LongVegetationSelectedFieldPreferencesSession;
    operationHeld?: boolean;
    mutationHeld?: boolean;
    onReadBusyChange: (busy: boolean) => void;
  } = $props();
  let view = $state(untrack(() => preferences.view()));
  let definitions = $state(untrack(() => preferences.definitions()));
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
          notifications.success('Long Vegetation selected field saved', receipt.outcome.changed ? 'Saved selected field preference.' : 'No selected field changes.', {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
        } else if (receipt.outcome.committed) {
          notifications.warning('Long Vegetation selected field saved with warning', receipt.outcome.errorMessage, {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
          lastViewError = receipt.outcome.errorMessage;
        } else if (receipt.outcome.errorMessage) {
          notifications.error('Long Vegetation selected field save failed', receipt.outcome.errorMessage, {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
          lastViewError = receipt.outcome.errorMessage;
        } else {
          notifications.info('Long Vegetation selected field unchanged', 'No selected field changes were needed.', {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
        }
      }
    }
    notifiedReceipts = receipts.length;
    const viewErr = view.error ?? '';
    if (viewErr && viewErr !== lastViewError) {
      notifications.error('Long Vegetation selected field preference failed', viewErr, {
        category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
      });
    }
    lastViewError = viewErr;
  }
  const unsubscribe = untrack(() => preferences.subscribe(() => {
    view = preferences.view(); definitions = preferences.definitions();
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
      const value = await reads.track(VegetationReportService.GetLongVegetationSelectedFieldPreferences(contextId));
      if (request !== generation) return;
      preferences.applyLoaded(value, token);
      if (typeof syncPreferenceNotifications === 'function') syncPreferenceNotifications();
    } catch (cause) {
      if (request === generation) {
        error = `Saved selected field unavailable; no defaults applied: ${String(cause)}`;
        if (typeof notifications !== 'undefined') {
          notifications.error('Long Vegetation selected field load failed', error, {
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
      await preferences.save(value => VegetationReportService.SaveLongVegetationSelectedFieldPreferences(contextId, JSON.stringify(value)));
      if (typeof syncPreferenceNotifications === 'function') syncPreferenceNotifications();
      else if (typeof notifications !== 'undefined') {
        const settled = preferences.view();
        const latest = settled.receipts?.[settled.receipts.length - 1];
        if (latest?.kind === 'known') {
          if (latest.outcome.committed && !latest.outcome.errorMessage) {
            notifications.success('Long Vegetation selected field saved', latest.outcome.changed ? 'Saved selected field preference.' : 'No selected field changes.', {
              category: 'reports', source: 'Long Vegetation',
              contextTag: typeof contextId === 'string' && contextId ? contextId : undefined,
            });
          } else if (latest.outcome.errorMessage) {
            notifications.error('Long Vegetation selected field save failed', latest.outcome.errorMessage, {
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
          notifications.error('Long Vegetation selected field save failed', error, {
            category: 'reports', source: 'Long Vegetation',
            contextTag: typeof contextId === 'string' && contextId ? contextId : undefined,
          });
        }
      }
    }
  }
  function edit(raw: string) {
    if (busy || mutationHeld || view.busy || view.blocked) return;
    cancel(); error = ''; preferences.editField(raw);
  }
  onDestroy(() => { unsubscribe(); cancel(); });
</script>

<section class="selected-field" aria-label="Saved Long Vegetation selected field preferences" data-long-vegetation-selected-field>
  {#if view.draftError}<p class="error" role="alert">{view.draftError}</p>{/if}
  {#each view.receipts as receipt}
    {#if receipt.kind !== 'known'}
      <p data-long-vegetation-selected-field-receipt role="alert">
        Preference receipt: outcome unknown; changed unknown; committed unknown. {receipt.errorMessage}
      </p>
    {/if}
  {/each}
  <label for="long-vegetation-selected-field">
    <span>Show selected field</span>
    <input id="long-vegetation-selected-field" data-source-control="cmbShowField" type="text"
      list="long-vegetation-selected-field-suggestions" value={view.draft.selectedField}
      aria-invalid={!!view.draftError}
      disabled={busy || mutationHeld || view.busy || view.blocked || !view.saved}
      oninput={event => { const raw = event.currentTarget.value; edit(raw); }} />
  </label>
  <datalist id="long-vegetation-selected-field-suggestions">
    {#each longVegetationSelectedFieldSuggestions as suggestion}<option value={suggestion}></option>{/each}
  </datalist>
  {#if view.saved}
    <dl>
      <div><dt>Saved selected field</dt><dd>{JSON.stringify(view.saved.selectedField)}</dd></div>
      <div><dt>Saved Show mode</dt><dd>{view.saved.mode}</dd></div>
      <div><dt>Staged Show mode</dt><dd>{view.draft.mode}</dd></div>
    </dl>
    {#if view.draft.mode === '4'}
      <p role="status">Selected-field mode is staged. Clearing the field retains that mode; it does not select another name.</p>
    {/if}
  {/if}
  {#if definitions}
    <details data-long-vegetation-selected-field-definitions>
      <summary>Owned physical fields ({definitions.length})</summary>
      <ul>{#each definitions as column}<li><code>{JSON.stringify(column.name)}</code> - {JSON.stringify(column.declaredType)}</li>{/each}</ul>
    </details>
  {/if}
  <div class="actions">
    <button data-long-vegetation-selected-field-load disabled={busy || operationHeld || view.busy || view.blocked}
      onclick={load}>Load saved selected field</button>
    <button data-long-vegetation-selected-field-save
      disabled={busy || operationHeld || view.busy || view.blocked || view.authorityUnknown || !!view.draftError || !view.saved}
      onclick={save}>Save selected field preferences</button>
    <button data-long-vegetation-selected-field-undo disabled={busy || mutationHeld || view.busy || view.blocked || !view.saved}
      onclick={() => { cancel(); preferences.undo(); }}>Undo selected field draft</button>
    {#if view.blocked && !view.busy}
      <button data-long-vegetation-selected-field-acknowledge disabled={busy || mutationHeld}
        onclick={() => preferences.acknowledge()}>Acknowledge selected field outcome</button>
    {/if}
    {#if busy}<button onclick={cancel}>Cancel selected field read</button>{/if}
  </div>
  <p class="guidance">The source suggestions are not mandatory membership or proof that a physical field exists.
    Preserve the literal field spelling; no trimming, case change or column creation occurs. A nonempty edit sets
    Show mode 4, and a later empty edit retains it. Undo restores the saved pair. Drafts do not change report output.
    Save explicitly, acknowledge and reload report options. Missing or unsupported report fields remain unavailable;
    saving preferences does not enable them. Receipts survive acknowledgement, and unknown outcomes require an
    owned Load before further Save. Only LVShowField and its source-coupled mode change in YAML; no registry,
    project data, source audits or printing.</p>
</section>

<style>
  .selected-field { display: grid; grid-template-columns: minmax(0, 1fr); gap: .75rem; min-width: 0; }
  label { display: grid; gap: .35rem; min-width: 0; }
  span, dd, li { overflow-wrap: anywhere; } dd { margin: .25rem 0 0; }
  input { width: 100%; box-sizing: border-box; min-width: 0; border: 1px solid #D8D8D8; border-radius: .4rem; padding: .5rem; }
  .actions { display: flex; flex-wrap: wrap; gap: .5rem; align-items: center; }
  button { border: 1px solid #D8D8D8; border-radius: .4rem; padding: .5rem .75rem; background: #FFFFFF; }
  button:disabled { opacity: .5; }
  .error { color: #D8292F; } .guidance { color: #474543; font-size: .875rem; }
</style>
