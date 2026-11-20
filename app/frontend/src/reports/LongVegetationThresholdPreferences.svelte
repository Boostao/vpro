<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
  import { notifications } from '../shell/notificationService.svelte';
  import LongVegetationPreferenceSection from '../shared/LongVegetationPreferenceSection.svelte';
  import { ReadRequests, formatError } from '../shared/readRequests';
  import type { LongVegetationStandardPreferenceProps } from './longVegetationPreferenceTypes';
  import {
    longVegetationThresholdFields,
    type LongVegetationThresholdPreferencesSession,
    type LongVegetationThresholdDraft,
  } from './longVegetationThresholdPreferences';

  let {
    contextId,
    preferences,
    operationHeld = false,
    mutationHeld = false,
    onReadBusyChange,
  }: LongVegetationStandardPreferenceProps<LongVegetationThresholdPreferencesSession> = $props();
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
      const value = await reads.track(VegetationReportService.GetLongVegetationThresholdPreferences(contextId));
      if (request === generation) preferences.applyLoaded(value, token);
    } catch (cause) {
      if (request === generation) {
        error = `Saved report thresholds unavailable; no defaults applied: ${formatError(cause)}`;
        notifications.error('Long Vegetation report thresholds load failed', error, {
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
        VegetationReportService.SaveLongVegetationThresholdPreferences(contextId, JSON.stringify(value))
      );
    } catch (cause) {
      if (request === generation) {
        error = formatError(cause);
        notifications.error('Long Vegetation report thresholds save failed', error, {
          category: 'reports',
          source: 'Long Vegetation',
          contextTag: contextId || undefined,
        });
      }
    }
  }
  function edit(key: keyof LongVegetationThresholdDraft, raw: string) {
    if (busy || mutationHeld || view.busy || view.blocked) return;
    cancel();
    error = '';
    preferences.editThreshold(key, raw);
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
  ariaLabel="Saved Long Vegetation report thresholds"
  sectionAttr="data-long-vegetation-thresholds"
  receiptAttr="data-long-vegetation-threshold-receipt"
  actionPrefix="data-long-vegetation-threshold"
  titleBase="Long Vegetation report thresholds"
  savedChangedMsg="Saved report threshold preferences."
  savedNoChangeMsg="No report threshold changes."
  unchangedMsg="No report threshold changes were needed."
  loadLabel="Load saved report thresholds"
  saveLabel="Save report thresholds"
  undoLabel="Undo report threshold draft"
  acknowledgeLabel="Acknowledge report threshold outcome"
  cancelLabel="Cancel report threshold read"
  guidance={'Load saved thresholds before editing; no defaults are applied. Drafts do not change report ' +
    'output. Save explicitly, acknowledge and reload report options. Source comparisons are strict; ' +
    'constant-list mode bypasses these thresholds. No new range is imposed. Receipts remain after ' +
    'acknowledgement; unknown outcomes require explicit owned Load, never blind Save replay. Only ' +
    'these two YAML preferences change; no registry, project data, source audits or printing.'}
  onload={load}
  onsave={save}
  oncancel={cancel}
>
  <div class="fields">
    {#each longVegetationThresholdFields as field}
      <label for={'long-vegetation-threshold-' + field.key}>
        <span>{field.label}</span>
        <div class="value">
          <input
            id={'long-vegetation-threshold-' + field.key}
            type="text"
            inputmode="decimal"
            data-source-control={field.control}
            value={view.draft[field.key]}
            aria-invalid={!!view.draftError}
            disabled={busy || mutationHeld || view.busy || view.blocked || !view.initialized}
            oninput={(event) => {
              const raw = event.currentTarget.value;
              edit(field.key, raw);
            }}
          />
          <span>%</span>
        </div>
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
    gap: 0.35rem;
    min-width: 0;
  }
  .value {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    gap: 0.5rem;
    align-items: center;
  }
  span {
    overflow-wrap: anywhere;
  }
  input {
    width: 100%;
    box-sizing: border-box;
    min-width: 0;
    border: 1px solid var(--vpro-border);
    border-radius: 0.4rem;
    padding: 0.5rem;
  }
</style>
