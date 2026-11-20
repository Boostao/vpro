<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
  import { notifications } from '../shell/notificationService.svelte';
  import LongVegetationPreferenceSection from '../shared/LongVegetationPreferenceSection.svelte';
  import { ReadRequests, formatError } from '../shared/readRequests';
  import type { LongVegetationStandardPreferenceProps } from './longVegetationPreferenceTypes';
  import {
    longVegetationSwitchFields,
    type LongVegetationSwitchPreferencesSession,
    type LongVegetationSwitchPreferenceValues,
  } from './longVegetationSwitchPreferences';

  let {
    contextId,
    preferences,
    operationHeld = false,
    mutationHeld = false,
    onReadBusyChange,
  }: LongVegetationStandardPreferenceProps<LongVegetationSwitchPreferencesSession> = $props();
  let view = $state(untrack(() => preferences.view())),
    busy = $state(false),
    error = $state(''),
    generation = 0;
  const reads = new ReadRequests();
  const unsubscribe = untrack(() =>
    preferences.subscribe(() => {
      view = preferences.view();
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
      const value = await reads.track(VegetationReportService.GetLongVegetationSwitchPreferences(contextId));
      if (request === generation) preferences.applyLoaded(value, token);
    } catch (cause) {
      if (request === generation) {
        error = `Saved report switches unavailable; no defaults applied: ${formatError(cause)}`;
        notifications.error('Long Vegetation report switches load failed', error, {
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
        VegetationReportService.SaveLongVegetationSwitchPreferences(contextId, JSON.stringify(value))
      );
    } catch (cause) {
      if (request === generation) {
        error = formatError(cause);
        notifications.error('Long Vegetation report switches save failed', error, {
          category: 'reports',
          source: 'Long Vegetation',
          contextTag: contextId || undefined,
        });
      }
    }
  }
  function edit(key: keyof LongVegetationSwitchPreferenceValues, value: boolean) {
    if (busy || mutationHeld || view.busy || view.blocked) return;
    cancel();
    error = '';
    preferences.editSwitch(key, value);
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
  ariaLabel="Saved Long Vegetation report switches"
  sectionAttr="data-long-vegetation-switches"
  receiptAttr="data-long-vegetation-switch-receipt"
  actionPrefix="data-long-vegetation-switch"
  titleBase="Long Vegetation report switches"
  savedChangedMsg="Saved report switch preferences."
  savedNoChangeMsg="No report switch changes."
  unchangedMsg="No report switch changes were needed."
  loadLabel="Load saved report switches"
  saveLabel="Save report switches"
  undoLabel="Undo report switch draft"
  acknowledgeLabel="Acknowledge report switch outcome"
  cancelLabel="Cancel report switch read"
  guidance={(!view.initialized ? 'Load saved switches before editing; unloaded boxes do not show saved values. ' : '') +
    'Unsaved edits do not change report output until you save and reload report options. If a save is ' +
    'interrupted, reload saved switches before saving again. Saving updates only these four Long Vegetation ' +
    'display preferences; project data, audit history, and printing settings are untouched.'}
  onload={load}
  onsave={save}
  oncancel={cancel}
>
  <div class="fields">
    {#each longVegetationSwitchFields as field}
      <label for={'long-vegetation-switch-' + field.key}>
        <input
          id={'long-vegetation-switch-' + field.key}
          type="checkbox"
          data-source-control={field.control}
          checked={view.draft?.[field.key] === true}
          aria-invalid={!!view.draftError}
          disabled={busy || mutationHeld || view.busy || view.blocked || !view.initialized}
          onchange={(event) => {
            const value = event.currentTarget.checked;
            edit(field.key, value);
          }}
        />
        <span>{field.label}</span>
      </label>
    {/each}
  </div>
</LongVegetationPreferenceSection>

<style>
  .fields {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 20rem), 1fr));
    gap: 0.75rem;
  }
  label {
    display: grid;
    grid-template-columns: auto minmax(0, 1fr);
    gap: 0.5rem;
    align-items: start;
  }
  span {
    overflow-wrap: anywhere;
  }
  input {
    margin-top: 0.2rem;
    width: 1rem;
    height: 1rem;
  }
</style>
