<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
  import { notifications } from '../shell/notificationService.svelte';
  import { ReadRequests } from '../shared/readRequests';
  import type { LongVegetationEnforcementPreferencesSession } from './longVegetationEnforcementPreferences';

  let { contextId, preferences, operationHeld = false, mutationHeld = false, onReadBusyChange }: {
    contextId: string;
    preferences: LongVegetationEnforcementPreferencesSession;
    operationHeld?: boolean;
    mutationHeld?: boolean;
    onReadBusyChange: (busy: boolean) => void;
  } = $props();
  let view = $state(untrack(() => preferences.view()));
  let printers = $state(untrack(() => preferences.printerView()));
  let busy = $state(false);
  let error = $state('');
  const reads = new ReadRequests();
  let generation = 0;
  let notifiedReceipts = 0;
  let lastViewError = '';
  let lastPrintersError = '';
  function syncPreferenceNotifications() {
    if (typeof notifications === 'undefined') return;
    const receipts = view.receipts ?? [];
    if (receipts.length < notifiedReceipts) notifiedReceipts = 0;
    const ctxTag = typeof contextId === 'string' && contextId ? contextId : undefined;
    for (let i = notifiedReceipts; i < receipts.length; i++) {
      const receipt = receipts[i];
      if (receipt.kind === 'known') {
        if (receipt.outcome.committed && !receipt.outcome.errorMessage) {
          notifications.success('Long Vegetation enforcement preferences saved', receipt.outcome.changed ? 'Saved enforcement preferences.' : 'No enforcement changes.', {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
        } else if (receipt.outcome.committed) {
          notifications.warning('Long Vegetation enforcement preferences saved with warning', receipt.outcome.errorMessage, {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
          lastViewError = receipt.outcome.errorMessage;
        } else if (receipt.outcome.errorMessage) {
          notifications.error('Long Vegetation enforcement save failed', receipt.outcome.errorMessage, {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
          lastViewError = receipt.outcome.errorMessage;
        } else {
          notifications.info('Long Vegetation enforcement preferences unchanged', 'No enforcement preference changes were needed.', {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
        }
      }
    }
    notifiedReceipts = receipts.length;
    const viewErr = view.error ?? '';
    if (viewErr && viewErr !== lastViewError) {
      notifications.error('Long Vegetation enforcement preference failed', viewErr, {
        category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
      });
    }
    lastViewError = viewErr;
    const printersErr = printers.error ?? '';
    if (printersErr && printersErr !== lastPrintersError) {
      notifications.error('Long Vegetation printer observation failed', printersErr, {
        category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
      });
    }
    lastPrintersError = printersErr;
  }
  const unsubscribe = untrack(() => preferences.subscribe(() => {
    view = preferences.view(); printers = preferences.printerView();
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
      const value = await reads.track(VegetationReportService.GetLongVegetationEnforcementPreferences(contextId));
      if (request !== generation) return;
      preferences.applyLoaded(value, token);
      if (typeof syncPreferenceNotifications === 'function') syncPreferenceNotifications();
    } catch (cause) {
      if (request === generation) {
        error = `Saved enforcement preferences unavailable; no defaults applied: ${String(cause)}`;
        if (typeof notifications !== 'undefined') {
          notifications.error('Long Vegetation enforcement load failed', error, {
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
      await preferences.saveWithPrinters(value => VegetationReportService.SaveLongVegetationEnforcementPreferences(contextId, JSON.stringify(value)));
      if (typeof syncPreferenceNotifications === 'function') syncPreferenceNotifications();
      else if (typeof notifications !== 'undefined') {
        const settled = preferences.view();
        const latest = settled.receipts?.[settled.receipts.length - 1];
        if (latest?.kind === 'known') {
          if (latest.outcome.committed && !latest.outcome.errorMessage) {
            notifications.success('Long Vegetation enforcement preferences saved', latest.outcome.changed ? 'Saved enforcement preferences.' : 'No enforcement changes.', {
              category: 'reports', source: 'Long Vegetation',
              contextTag: typeof contextId === 'string' && contextId ? contextId : undefined,
            });
          } else if (latest.outcome.errorMessage) {
            notifications.error('Long Vegetation enforcement save failed', latest.outcome.errorMessage, {
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
          notifications.error('Long Vegetation enforcement save failed', error, {
            category: 'reports', source: 'Long Vegetation',
            contextTag: typeof contextId === 'string' && contextId ? contextId : undefined,
          });
        }
      }
    }
  }
  function edit(raw: boolean) {
    if (busy || mutationHeld || view.busy || view.blocked) return;
    cancel(); error = ''; preferences.editEnforce(raw);
  }
  onDestroy(() => { unsubscribe(); cancel(); });
</script>

<section class="enforcement" aria-label="Saved Long Vegetation enforcement preferences" data-long-vegetation-enforcement>
  {#if view.draftError}<p class="error" role="alert">{view.draftError}</p>{/if}
  {#each view.receipts as receipt}
    {#if receipt.kind !== 'known'}
      <p data-long-vegetation-enforcement-receipt role="alert">
        Preference receipt: outcome unknown; changed unknown; committed unknown. {receipt.errorMessage}
      </p>
    {/if}
  {/each}
  <label for="long-vegetation-enforcement">
    <input id="long-vegetation-enforcement" data-source-control="optEnforceQC" type="checkbox"
      checked={view.draft.enforce === true} aria-invalid={!!view.draftError}
      disabled={busy || mutationHeld || view.busy || view.blocked || !view.saved}
      onchange={event => { const raw = event.currentTarget.checked; edit(raw); }} />
    <span>Enforce rules</span>
  </label>
  {#if view.saved}
    <dl>
      <div><dt>Saved enforcement</dt><dd>{String(view.saved.enforce)}</dd></div>
      <div><dt>Saved unit group</dt><dd>{view.saved.unitGroups === 1 ? 'Site unit table' : view.saved.unitGroups === 2 ? 'Selected fields (report unavailable)' : 'None (report unavailable)'}</dd></div>
      <div><dt>Staged unit group</dt><dd>{view.draft.unitGroups === 1 ? 'Site unit table' : view.draft.unitGroups}</dd></div>
    </dl>
  {/if}
  {#if printers.value}
    <details data-long-vegetation-enforcement-printers>
      <summary>Read-only printer observation ({printers.value.names?.length})</summary>
      <p>Current default: {printers.value.default === null ? 'No default printer installed' : JSON.stringify(printers.value.default)}.</p>
      <ul>{#each printers.value.names ?? [] as name}<li>{JSON.stringify(name)}</li>{/each}</ul>
      <p>Separate host reads can disagree or change later. No printer selection, default change or printing occurs.</p>
    </details>
  {/if}
  <div class="actions">
    <button data-long-vegetation-enforcement-load disabled={busy || operationHeld || view.busy || view.blocked}
      onclick={load}>Load saved enforcement preferences</button>
    <button data-long-vegetation-enforcement-save
      disabled={busy || operationHeld || view.busy || view.blocked || view.authorityUnknown || !!view.draftError || !view.saved}
      onclick={save}>Save enforcement preferences</button>
    <button data-long-vegetation-enforcement-undo disabled={busy || mutationHeld || view.busy || view.blocked || !view.saved}
      onclick={() => { cancel(); preferences.undo(); }}>Undo enforcement draft</button>
    {#if view.blocked && !view.busy}
      <button data-long-vegetation-enforcement-acknowledge disabled={busy || mutationHeld}
        onclick={() => preferences.acknowledge()}>Acknowledge enforcement outcome</button>
    {/if}
    {#if busy}<button onclick={cancel}>Cancel enforcement read</button>{/if}
  </div>
  <p class="guidance">An enforcement edit resets the unit group to Site unit table, including a toggle away and back.
    Undo restores the saved pair; remounting does not reset it. Save explicitly, acknowledge and reload report options.
    Quality minima and NULL choices remain editable with enforcement off; other retained drafts are not reloaded.
    Printer refresh is read-only and separate from YAML persistence. A committed receipt survives a failed refresh:
    do not replay; acknowledge and Load. Only enforcement and its source-coupled unit group change. No source data,
    audits, printer default or physical printing is changed. Selected-fields/None unit-group reports remain unavailable.</p>
</section>

<style>
  .enforcement { display: grid; grid-template-columns: minmax(0, 1fr); gap: .75rem; min-width: 0; }
  label { display: flex; gap: .5rem; align-items: center; min-width: 0; }
  input { width: 1.25rem; height: 1.25rem; flex-shrink: 0; }
  span, dd, li { overflow-wrap: anywhere; } dd { margin: .25rem 0 0; }
  .actions { display: flex; flex-wrap: wrap; gap: .5rem; align-items: center; }
  button { border: 1px solid #D8D8D8; border-radius: .4rem; padding: .5rem .75rem; background: #FFFFFF; }
  button:disabled { opacity: .5; }
  .error { color: #D8292F; } .guidance { color: #474543; font-size: .875rem; }
</style>
