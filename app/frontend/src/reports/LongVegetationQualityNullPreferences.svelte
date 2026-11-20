<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
  import { notifications } from '../shell/notificationService.svelte';
  import LongVegetationPreferenceSection from '../shared/LongVegetationPreferenceSection.svelte';
  import { ReadRequests, formatError } from '../shared/readRequests';
  import type { LongVegetationStandardPreferenceProps } from './longVegetationPreferenceTypes';
  import {
    longVegetationQualityNullFields,
    type LongVegetationQualityNullPreferencesSession,
    type LongVegetationQualityNullPreferenceValues,
  } from './longVegetationQualityNullPreferences';

  let {
    contextId,
    preferences,
    operationHeld = false,
    mutationHeld = false,
    onReadBusyChange,
  }: LongVegetationStandardPreferenceProps<LongVegetationQualityNullPreferencesSession> = $props();
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
      const value = await reads.track(VegetationReportService.GetLongVegetationQualityNullPreferences(contextId));
      if (request === generation) preferences.applyLoaded(value, token);
    } catch (cause) {
      if (request === generation) {
        error = `Saved quality Include Nulls flags unavailable; no defaults applied: ${formatError(cause)}`;
        notifications.error('Long Vegetation quality Include Nulls load failed', error, {
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
        VegetationReportService.SaveLongVegetationQualityNullPreferences(contextId, JSON.stringify(value))
      );
    } catch (cause) {
      if (request === generation) {
        error = formatError(cause);
        notifications.error('Long Vegetation quality Include Nulls save failed', error, {
          category: 'reports',
          source: 'Long Vegetation',
          contextTag: contextId || undefined,
        });
      }
    }
  }
  function edit(key: keyof LongVegetationQualityNullPreferenceValues, checked: boolean) {
    if (busy || mutationHeld || view.busy || view.blocked) return;
    cancel();
    error = '';
    preferences.editNullFlag(key, checked);
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
  ariaLabel="Saved Long Vegetation Data Quality Include Nulls"
  sectionAttr="data-long-vegetation-quality-nulls"
  receiptAttr="data-long-vegetation-quality-null-receipt"
  actionPrefix="data-long-vegetation-quality-null"
  titleBase="Long Vegetation quality Include Nulls"
  savedChangedMsg="Saved quality Include Nulls flags."
  savedNoChangeMsg="No quality Include Nulls changes."
  unchangedMsg="No quality Include Nulls changes were needed."
  loadLabel="Load saved quality Include Nulls"
  saveLabel="Save quality Include Nulls"
  undoLabel="Undo quality Include Nulls draft"
  acknowledgeLabel="Acknowledge quality Include Nulls outcome"
  cancelLabel="Cancel quality Include Nulls read"
  guidance={'Load saved flags before editing; unloaded checkboxes do not show saved values. Unsaved edits do ' +
    'not change report output until you save and reload report options. These Include Nulls flags apply only ' +
    'when Enforce rules is enabled and do not alter minimum thresholds. If a save is interrupted, reload saved ' +
    'flags before saving again. Saving updates only these three Include Nulls preferences; project data and ' +
    'audit history are untouched.'}
  onload={load}
  onsave={save}
  oncancel={cancel}
>
  <fieldset>
    <legend>Data Quality - Include Nulls</legend>
    <div class="fields">
      {#each longVegetationQualityNullFields as field}
        <label for={'long-vegetation-quality-null-' + field.key}>
          <input
            id={'long-vegetation-quality-null-' + field.key}
            type="checkbox"
            data-source-control={field.control}
            checked={view.draft ? view.draft[field.key] : false}
            aria-invalid={!!view.draftError}
            disabled={busy || mutationHeld || view.busy || view.blocked || !view.draft}
            onchange={(event) => {
              const checked = event.currentTarget.checked;
              edit(field.key, checked);
            }}
          />
          <span>{field.label} - Include Nulls</span>
        </label>
      {/each}
    </div>
  </fieldset>
</LongVegetationPreferenceSection>

<style>
  fieldset {
    min-width: 0;
    border: 1px solid var(--vpro-border);
    border-radius: 0.4rem;
    padding: 0.75rem;
  }
  legend {
    padding: 0 0.35rem;
  }
  .fields {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 12rem), 1fr));
    gap: 0.75rem;
  }
  label {
    display: flex;
    align-items: flex-start;
    gap: 0.5rem;
    min-width: 0;
  }
  span {
    overflow-wrap: anywhere;
  }
  input {
    flex: none;
    margin-top: 0.2rem;
  }
</style>
