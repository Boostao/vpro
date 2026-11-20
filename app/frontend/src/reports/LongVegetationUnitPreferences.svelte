<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
  import { notifications } from '../shell/notificationService.svelte';
  import LongVegetationPreferenceSection from '../shared/LongVegetationPreferenceSection.svelte';
  import { ReadRequests, formatError } from '../shared/readRequests';
  import {
    longVegetationUnitChoices,
    type LongVegetationUnitPreferencesSession,
  } from './longVegetationUnitPreferences';
  import type { LongVegetationStandardPreferenceProps } from './longVegetationPreferenceTypes';

  let {
    contextId,
    preferences,
    operationHeld = false,
    mutationHeld = false,
    onReadBusyChange,
  }: LongVegetationStandardPreferenceProps<LongVegetationUnitPreferencesSession> = $props();
  let view = $state(untrack(() => preferences.view())),
    availability = $state(untrack(() => preferences.availability()));
  let busy = $state(false),
    error = $state(''),
    generation = 0;
  const reads = new ReadRequests();
  const unsubscribe = untrack(() =>
    preferences.subscribe(() => {
      view = preferences.view();
      availability = preferences.availability();
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
      const value = await reads.track(VegetationReportService.GetLongVegetationUnitPreferences(contextId));
      if (request === generation) preferences.applyLoaded(value, token);
    } catch (cause) {
      if (request === generation) {
        error = `Saved Unit Groups unavailable; no defaults applied: ${formatError(cause)}`;
        notifications.error('Long Vegetation Unit Groups load failed', error, {
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
      await preferences.save((value) =>
        VegetationReportService.SaveLongVegetationUnitPreferences(contextId, JSON.stringify(value))
      );
    } catch (cause) {
      if (request === generation) {
        error = formatError(cause);
        notifications.error('Long Vegetation Unit Groups save failed', error, {
          category: 'reports',
          source: 'Long Vegetation',
          contextTag: contextId || undefined,
        });
      }
    }
  }
  function edit(raw: string) {
    if (busy || mutationHeld || view.busy || view.blocked) return;
    cancel();
    error = '';
    preferences.editUnitGroups(raw);
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
  ariaLabel="Saved Long Vegetation Unit Groups"
  sectionAttr="data-long-vegetation-unit-preferences"
  receiptAttr="data-long-vegetation-unit-receipt"
  actionPrefix="data-long-vegetation-unit"
  titleBase="Long Vegetation Unit Groups"
  savedChangedMsg="Saved Unit Groups preference."
  savedNoChangeMsg="No Unit Groups changes."
  unchangedMsg="No Unit Groups changes were needed."
  loadLabel="Load saved Unit Groups"
  saveLabel="Save Unit Groups"
  undoLabel="Undo Unit Groups draft"
  acknowledgeLabel="Acknowledge Unit Groups outcome"
  cancelLabel="Cancel Unit Groups read"
  guidance={'Load saved Unit Groups before editing; no defaults are applied. Drafts do not change report ' +
    'output. Save explicitly, acknowledge and reload report options. Selected fields require a ' +
    'current owned session Build and independently enabled consumers; all-project fallback remains ' +
    'unavailable. None uses Env/current selected-list joins, not None species grouping. Retaining an ' +
    'unchanged unavailable saved choice does not enable its report. Changing Enforce rules resets ' +
    'the saved Unit Groups to Site unit table; retained drafts require owned Load or correction. ' +
    'Receipts remain after acknowledgement; unknown outcomes require explicit owned Load, never ' +
    'blind Save replay. Only LVUnitGroups changes in YAML; no registry, project data, source scratch ' +
    'tables, audits or printing.'}
  onload={load}
  onsave={save}
  oncancel={cancel}
>
  <label for="long-vegetation-unit-groups">
    <span>Unit Groups</span>
    <select
      id="long-vegetation-unit-groups"
      data-source-control="rptLvUnitGroups"
      value={view.draft.unitGroups}
      aria-invalid={!!view.draftError}
      disabled={busy || mutationHeld || view.busy || view.blocked || !view.saved}
      onchange={(event) => {
        const raw = event.currentTarget.value;
        edit(raw);
      }}
    >
      <option value="" disabled>Load saved Unit Groups</option>
      {#each longVegetationUnitChoices as mode}
        <option
          value={String(mode.value)}
          disabled={!availability?.[mode.capability] && view.saved?.unitGroups !== mode.value}
        >
          {mode.label}
        </option>
      {/each}
    </select>
  </label>
</LongVegetationPreferenceSection>

<style>
  label {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 0.35rem;
    min-width: 0;
  }
  span {
    overflow-wrap: anywhere;
  }
  select {
    width: 100%;
    box-sizing: border-box;
    min-width: 0;
    border: 1px solid var(--vpro-border);
    border-radius: 0.4rem;
    padding: 0.5rem;
  }
</style>
