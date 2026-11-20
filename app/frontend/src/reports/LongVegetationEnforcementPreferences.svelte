<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
  import { notifications } from '../shell/notificationService.svelte';
  import LongVegetationPreferenceSection from '../shared/LongVegetationPreferenceSection.svelte';
  import { ReadRequests, formatError } from '../shared/readRequests';
  import type { LongVegetationEnforcementPreferencesSession } from './longVegetationEnforcementPreferences';
  import type { LongVegetationStandardPreferenceProps } from './longVegetationPreferenceTypes';

  let {
    contextId,
    preferences,
    operationHeld = false,
    mutationHeld = false,
    onReadBusyChange,
  }: LongVegetationStandardPreferenceProps<LongVegetationEnforcementPreferencesSession> = $props();
  let view = $state(untrack(() => preferences.view())),
    printers = $state(untrack(() => preferences.printerView()));
  let busy = $state(false),
    error = $state(''),
    generation = 0;
  const reads = new ReadRequests();
  const unsubscribe = untrack(() =>
    preferences.subscribe(() => {
      view = preferences.view();
      printers = preferences.printerView();
    })
  );
  function cancel() {
    generation++;
    reads.cancelAll();
    preferences.cancelLoad();
    busy = false;
    onReadBusyChange(false);
  }
  async function load() {
    if (busy || operationHeld || view.busy || view.blocked) return;
    cancel();
    const request = generation,
      token = preferences.beginLoad();
    error = '';
    busy = true;
    onReadBusyChange(true);
    try {
      const value = await reads.track(VegetationReportService.GetLongVegetationEnforcementPreferences(contextId));
      if (request === generation) preferences.applyLoaded(value, token);
    } catch (cause) {
      if (request === generation) {
        error = `Saved enforcement preferences unavailable; no defaults applied: ${formatError(cause)}`;
        notifications.error('Long Vegetation enforcement load failed', error, {
          category: 'reports',
          source: 'Long Vegetation',
          contextTag: contextId || undefined,
        });
      }
    } finally {
      if (request === generation) {
        busy = false;
        onReadBusyChange(false);
      }
    }
  }
  async function save() {
    if (busy || operationHeld || view.busy || view.blocked || view.authorityUnknown || view.draftError) return;
    cancel();
    const request = generation;
    error = '';
    try {
      await preferences.saveWithPrinters((value) =>
        VegetationReportService.SaveLongVegetationEnforcementPreferences(contextId, JSON.stringify(value))
      );
    } catch (cause) {
      if (request === generation) {
        error = formatError(cause);
        notifications.error('Long Vegetation enforcement save failed', error, {
          category: 'reports',
          source: 'Long Vegetation',
          contextTag: contextId || undefined,
        });
      }
    }
  }
  function edit(raw: boolean) {
    if (busy || mutationHeld || view.busy || view.blocked) return;
    cancel();
    error = '';
    preferences.editEnforce(raw);
  }
  onDestroy(() => {
    unsubscribe();
    cancel();
  });
</script>

<LongVegetationPreferenceSection
  {view}
  {preferences}
  {busy}
  {operationHeld}
  {mutationHeld}
  contextTag={contextId || undefined}
  extraError={printers.error ?? ''}
  extraErrorTitle="Long Vegetation printer observation failed"
  ariaLabel="Saved Long Vegetation enforcement preferences"
  sectionAttr="data-long-vegetation-enforcement"
  receiptAttr="data-long-vegetation-enforcement-receipt"
  actionPrefix="data-long-vegetation-enforcement"
  titleBase="Long Vegetation enforcement preferences"
  savedChangedMsg="Saved enforcement preferences."
  savedNoChangeMsg="No enforcement changes."
  unchangedMsg="No enforcement preference changes were needed."
  loadLabel="Load saved enforcement preferences"
  saveLabel="Save enforcement preferences"
  undoLabel="Undo enforcement draft"
  acknowledgeLabel="Acknowledge enforcement outcome"
  cancelLabel="Cancel enforcement read"
  guidance={'An enforcement edit resets the unit group to Site unit table, including a toggle away and back. ' +
    'Undo restores the saved pair; remounting does not reset it. Save explicitly, acknowledge and ' +
    'reload report options. Quality minima and NULL choices remain editable with enforcement off; ' +
    'other retained drafts are not reloaded. Printer refresh is read-only and separate from YAML ' +
    'persistence. A committed receipt survives a failed refresh: do not replay; acknowledge and ' +
    'Load. Only enforcement and its source-coupled unit group change. No source data, audits, ' +
    'printer default or physical printing is changed. Selected-fields/None unit-group reports remain ' +
    'unavailable.'}
  onload={load}
  onsave={save}
  oncancel={cancel}
>
  <label for="long-vegetation-enforcement">
    <input
      id="long-vegetation-enforcement"
      data-source-control="optEnforceQC"
      type="checkbox"
      checked={view.draft.enforce === true}
      aria-invalid={!!view.draftError}
      disabled={busy || mutationHeld || view.busy || view.blocked || !view.saved}
      onchange={(event) => {
        const raw = event.currentTarget.checked;
        edit(raw);
      }}
    />
    <span>Enforce rules</span>
  </label>
  {#if view.saved}
    <dl>
      <div>
        <dt>Saved enforcement</dt>
        <dd>{String(view.saved.enforce)}</dd>
      </div>
      <div>
        <dt>Saved unit group</dt>
        <dd>
          {view.saved.unitGroups === 1
            ? 'Site unit table'
            : view.saved.unitGroups === 2
              ? 'Selected fields (report unavailable)'
              : 'None (report unavailable)'}
        </dd>
      </div>
      <div>
        <dt>Staged unit group</dt>
        <dd>{view.draft.unitGroups === 1 ? 'Site unit table' : view.draft.unitGroups}</dd>
      </div>
    </dl>
  {/if}
  {#if printers.value}
    <details data-long-vegetation-enforcement-printers>
      <summary>Read-only printer observation ({printers.value.names?.length})</summary>
      <p>
        Current default: {printers.value.default === null
          ? 'No default printer installed'
          : JSON.stringify(printers.value.default)}.
      </p>
      <ul>
        {#each printers.value.names ?? [] as name}<li>{JSON.stringify(name)}</li>{/each}
      </ul>
      <p>Separate host reads can disagree or change later. No printer selection, default change or printing occurs.</p>
    </details>
  {/if}
</LongVegetationPreferenceSection>

<style>
  label {
    display: flex;
    gap: 0.5rem;
    align-items: center;
    min-width: 0;
  }
  input {
    width: 1.25rem;
    height: 1.25rem;
    flex-shrink: 0;
  }
  span,
  dd,
  li {
    overflow-wrap: anywhere;
  }
  dd {
    margin: 0.25rem 0 0;
  }
</style>
