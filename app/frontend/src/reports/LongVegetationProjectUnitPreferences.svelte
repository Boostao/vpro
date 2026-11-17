<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { notifications } from '../shell/notificationService.svelte';
  import type { LongVegetationProjectUnitOutcome, LongVegetationProjectUnitPreferences } from '../../bindings/github.com/boostao/vpro/app';
  import type { ProjectUnitPreferencesSession, ProjectUnitSaveRequest } from './longVegetationProjectUnitSession';

  let { preferences, fetchPreferences, savePreferences, cancelReads, onChange, operationHeld = false, mutationHeld = false }: {
    preferences: ProjectUnitPreferencesSession;
    fetchPreferences: (request: { revision: string; approvalHash: string }) => PromiseLike<LongVegetationProjectUnitPreferences>;
    savePreferences: (request: ProjectUnitSaveRequest) => PromiseLike<LongVegetationProjectUnitOutcome>;
    cancelReads: () => void;
    onChange: () => void;
    operationHeld?: boolean;
    mutationHeld?: boolean;
  } = $props();
  let view = $state.raw(untrack(() => preferences.projectView()));
  let error = $state('');
  let generation = 0;
  let notifiedReceipts = 0;
  let lastReadError = '';
  let lastViewError = '';
  function syncUnitNotifications() {
    if (typeof notifications === 'undefined') return;
    const ctxTag = view.scope?.project || undefined;
    const receipts = view.projectReceipts ?? [];
    if (receipts.length < notifiedReceipts) notifiedReceipts = 0;
    for (let i = notifiedReceipts; i < receipts.length; i++) {
      const receipt = receipts[i];
      if (receipt.kind === 'known') {
        const outcome = receipt.outcome.outcome;
        if (outcome.committed && !outcome.errorMessage) {
          notifications.success(
            'Long Vegetation project Unit Groups saved',
            outcome.changed
              ? `Revision ${receipt.request.revision}: Unit Groups set to ${receipt.request.proposed.unitGroups}.`
              : `Revision ${receipt.request.revision}: No Unit Groups changes.`,
            { category: 'reports', source: 'Long Vegetation', contextTag: ctxTag },
          );
        } else if (outcome.committed) {
          notifications.warning('Long Vegetation project Unit Groups saved with warning', outcome.errorMessage, {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
          lastViewError = outcome.errorMessage;
        } else if (outcome.errorMessage) {
          notifications.error('Long Vegetation project Unit Groups save failed', outcome.errorMessage, {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
          lastViewError = outcome.errorMessage;
        } else {
          notifications.info('Long Vegetation project Unit Groups unchanged', 'No Unit Groups changes were needed.', {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
        }
      }
    }
    notifiedReceipts = receipts.length;
    const readErr = view.readError ?? '';
    if (readErr && readErr !== lastReadError) {
      notifications.error('Long Vegetation project Unit Groups load failed', readErr, {
        category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
      });
    }
    lastReadError = readErr;
    const viewErr = view.error ?? '';
    if (viewErr && viewErr !== lastViewError) {
      notifications.error('Long Vegetation project Unit Groups preference failed', viewErr, {
        category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
      });
    }
    lastViewError = viewErr;
  }
  const unsubscribe = untrack(() => preferences.subscribe(() => {
    view = preferences.projectView();
    syncUnitNotifications();
    onChange();
  }));
  syncUnitNotifications();
  function cancel() {
    generation++;
    cancelReads();
    preferences.cancelRead();
  }
  async function load() {
    if (operationHeld || view.readBusy || view.busy || view.blocked || !view.scope) return;
    const request = ++generation;
    error = '';
    try {
      await preferences.load(fetchPreferences);
      if (typeof syncUnitNotifications === 'function') syncUnitNotifications();
    } catch (cause) {
      if (request === generation) {
        error = String(cause);
        if (typeof notifications !== 'undefined') {
          notifications.error('Long Vegetation project Unit Groups load failed', error, {
            category: 'reports', source: 'Long Vegetation', contextTag: view.scope?.project || undefined,
          });
        }
      }
    }
  }
  async function save() {
    if (operationHeld || mutationHeld || !view.saveReady) return;
    const request = ++generation;
    error = '';
    try {
      await preferences.saveProject(savePreferences);
      if (typeof syncUnitNotifications === 'function') syncUnitNotifications();
      else if (typeof notifications !== 'undefined') {
        const settled = preferences.projectView();
        const latest = settled.projectReceipts?.[settled.projectReceipts.length - 1];
        if (latest?.kind === 'known') {
          const outcome = latest.outcome.outcome;
          if (outcome.committed && !outcome.errorMessage) {
            notifications.success(
              'Long Vegetation project Unit Groups saved',
              outcome.changed
                ? `Revision ${latest.request.revision}: Unit Groups set to ${latest.request.proposed.unitGroups}.`
                : `Revision ${latest.request.revision}: No Unit Groups changes.`,
              { category: 'reports', source: 'Long Vegetation', contextTag: settled.scope?.project || undefined },
            );
          } else if (outcome.errorMessage) {
            notifications.error('Long Vegetation project Unit Groups save failed', outcome.errorMessage, {
              category: 'reports', source: 'Long Vegetation', contextTag: settled.scope?.project || undefined,
            });
          }
        }
      }
    } catch (cause) {
      if (request === generation) {
        error = String(cause);
        if (typeof notifications !== 'undefined') {
          notifications.error('Long Vegetation project Unit Groups save failed', error, {
            category: 'reports', source: 'Long Vegetation', contextTag: view.scope?.project || undefined,
          });
        }
      }
    }
  }
  function edit(raw: string) {
    if (mutationHeld || view.readBusy || view.busy || view.blocked || !view.saved) return;
    error = '';
    try { preferences.editUnitGroups(raw); }
    catch (cause) {
      error = String(cause);
      if (typeof notifications !== 'undefined') {
        notifications.error('Long Vegetation project Unit Groups edit failed', error, {
          category: 'reports', source: 'Long Vegetation', contextTag: view.scope?.project || undefined,
        });
      }
    }
  }
  function undo() {
    if (mutationHeld || view.readBusy || view.busy || view.blocked || !view.saved) return;
    error = '';
    try { preferences.undo(); }
    catch (cause) {
      error = String(cause);
      if (typeof notifications !== 'undefined') {
        notifications.error('Long Vegetation project Unit Groups undo failed', error, {
          category: 'reports', source: 'Long Vegetation', contextTag: view.scope?.project || undefined,
        });
      }
    }
  }
  onDestroy(() => { unsubscribe(); cancel(); });
</script>

<section class="unit-preferences" aria-label="Actual saved project Unit Groups" data-project-unit-preferences>
  {#if view.draftError}<p role="alert" class="error">{view.draftError}</p>{/if}
  {#if view.authorityUnknown}
    <p role="alert">Unit Groups outcome is unknown. Acknowledge the receipt, then Load actual saved values.
      The retained draft is not replayed automatically.</p>
  {/if}
  {#each view.projectReceipts as receipt}
    {#if receipt.kind !== 'known'}
      <div class="receipt" data-project-unit-receipt role="alert">
        <p>Preference receipt for revision {receipt.request.revision}:
          expected {receipt.request.expected.unitGroups}; proposed {receipt.request.proposed.unitGroups}.
          Changed unknown; committed unknown. {receipt.errorMessage}
        </p>
        <p>Approval: <code>{receipt.request.approvalHash}</code></p>
      </div>
    {/if}
  {/each}
  <label for="project-unit-groups">
    <span>Unit Groups</span>
    <select id="project-unit-groups" data-source-control="rptLvUnitGroups" value={view.draft.unitGroups}
      aria-invalid={!!view.draftError} disabled={mutationHeld || view.readBusy || view.busy || view.blocked || !view.saved}
      onchange={event => { const raw = event.currentTarget.value; edit(raw); }}>
      <option value="" disabled>Load actual saved Unit Groups</option>
      <option value="1" disabled={view.saved?.unitGroups !== 1}>Site unit table (saved value only)</option>
      <option value="2" disabled={view.scope?.sourceKind !== 'project-selected-fields' && view.saved?.unitGroups !== 2}>Selected fields</option>
      <option value="3" disabled={view.scope?.sourceKind !== 'project-all-plots' && view.saved?.unitGroups !== 3}>None (All plots)</option>
    </select>
  </label>
  {#if view.saved}<p data-project-unit-actual>Actual saved Unit Groups: {view.saved.unitGroups}. Draft: {view.draft.unitGroups}.</p>{/if}
  <div class="actions">
    <button data-project-unit-load disabled={operationHeld || view.readBusy || view.busy || view.blocked || !view.scope}
      onclick={load}>Load actual saved Unit Groups</button>
    <button data-project-unit-save disabled={operationHeld || mutationHeld || !view.saveReady} onclick={save}>Save Unit Groups</button>
    <button data-project-unit-undo disabled={mutationHeld || view.readBusy || view.busy || view.blocked || !view.saved}
      onclick={undo}>Undo Unit Groups draft</button>
    {#if view.blocked && !view.busy}
      <button data-project-unit-acknowledge disabled={mutationHeld || view.readBusy}
        onclick={() => preferences.acknowledge()}>Acknowledge Unit Groups outcome</button>
    {/if}
    {#if view.readBusy}
      <button data-project-unit-cancel onclick={cancel}>Cancel Unit Groups read</button>
    {/if}
  </div>
  <p class="guidance">Build the explicit project source before Load. Actual saved values are never normalized into the planned source choice.
    Save only the choice matching that source; changing source requires an explicit scope switch.
    Drafts do not change report output. Receipts remain after acknowledgement and tab remounts.
    Only LVUnitGroups changes in YAML; no project data, audits, registry or printing.</p>
</section>

<style>
  .unit-preferences { display: grid; grid-template-columns: minmax(0, 1fr); gap: .75rem; min-width: 0; }
  label { display: grid; gap: .35rem; min-width: 0; }
  select { width: 100%; box-sizing: border-box; min-width: 0; border: 1px solid #D8D8D8; border-radius: .4rem; padding: .5rem; }
  .actions { display: flex; flex-wrap: wrap; gap: .5rem; align-items: center; }
  button { border: 1px solid #D8D8D8; border-radius: .4rem; padding: .5rem .75rem; background: #FFFFFF; }
  button:disabled { opacity: .5; }
  .receipt, label { min-width: 0; }
  p, span, code { overflow-wrap: anywhere; }
  .error { color: #D8292F; }
  .guidance { color: #474543; font-size: .875rem; }
</style>
