<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
  import { notifications } from '../shell/notificationService.svelte';
  import LongVegetationPreferenceSection from '../shared/LongVegetationPreferenceSection.svelte';
  import { ReadRequests, formatError } from '../shared/readRequests';
  import {
    longVegetationNamingChoices,
    type LongVegetationNamingPreferencesSession,
  } from './longVegetationNamingPreferences';
  import type { LongVegetationStandardPreferenceProps } from './longVegetationPreferenceTypes';

  let {
    contextId,
    preferences,
    operationHeld = false,
    mutationHeld = false,
    selectedFieldEnabled = false,
    onReadBusyChange,
  }: LongVegetationStandardPreferenceProps<LongVegetationNamingPreferencesSession> & {
    selectedFieldEnabled?: boolean;
  } = $props();
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
      const value = await reads.track(VegetationReportService.GetLongVegetationNamingPreferences(contextId));
      if (request === generation) preferences.applyLoaded(value, token);
    } catch (cause) {
      if (request === generation) {
        error = `Saved Show values unavailable; no defaults applied: ${formatError(cause)}`;
        notifications.error('Long Vegetation Show load failed', error, {
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
        VegetationReportService.SaveLongVegetationNamingPreferences(contextId, JSON.stringify(value))
      );
    } catch (cause) {
      if (request === generation) {
        error = formatError(cause);
        notifications.error('Long Vegetation Show save failed', error, {
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
    preferences.editMode(raw);
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
  ariaLabel="Saved Long Vegetation Show preferences"
  sectionAttr="data-long-vegetation-naming"
  receiptAttr="data-long-vegetation-naming-receipt"
  actionPrefix="data-long-vegetation-naming"
  titleBase="Long Vegetation Show preferences"
  savedChangedMsg="Saved Show preference."
  savedNoChangeMsg="No Show preference changes."
  unchangedMsg="No Show preference changes were needed."
  loadLabel="Load saved Show"
  saveLabel="Save Show preferences"
  undoLabel="Undo Show draft"
  acknowledgeLabel="Acknowledge Show outcome"
  cancelLabel="Cancel Show read"
  guidance={'Load saved Show settings before editing; no defaults are applied. Choosing a Show option clears ' +
    'any paired custom field selection until you Undo back to your saved pair. Unsaved edits do not change ' +
    'report output until you save and reload report options. If a save is interrupted, reload saved Show ' +
    'settings before saving again. Saving updates only your default Show species-label preference; project ' +
    'data, audit history, and printing settings are untouched.'}
  onload={load}
  onsave={save}
  oncancel={cancel}
>
  <label for="long-vegetation-naming">
    <span>Show</span>
    <select
      id="long-vegetation-naming"
      data-source-control="rptLvShowCommon"
      value={view.draft.mode}
      aria-invalid={!!view.draftError}
      disabled={busy || mutationHeld || view.busy || view.blocked || !view.saved}
      onchange={(event) => {
        const raw = event.currentTarget.value;
        edit(raw);
      }}
    >
      <option value="" disabled>Load saved Show</option>
      {#each longVegetationNamingChoices as choice}
        <option
          value={String(choice.value)}
          disabled={!availability?.[choice.capability] && view.saved?.mode !== choice.value}
        >
          {choice.label}
        </option>
      {/each}
      {#if view.saved?.mode === 4}
        <option value="4" disabled
          >Saved selected-field mode ({selectedFieldEnabled ? 'read-only here' : 'unavailable'})</option
        >
      {/if}
    </select>
  </label>
  {#if view.saved}
    <dl>
      <div>
        <dt>Saved selected field (read-only)</dt>
        <dd data-source-control="cmbShowField">{JSON.stringify(view.saved.selectedField)}</dd>
      </div>
    </dl>
    {#if view.draft.selectedField !== view.saved.selectedField}
      <p role="status">The staged Show selection clears the selected field on Save.</p>
    {/if}
  {/if}
</LongVegetationPreferenceSection>

<style>
  label {
    display: grid;
    gap: 0.35rem;
    min-width: 0;
  }
  span,
  dd {
    overflow-wrap: anywhere;
  }
  dd {
    margin: 0.25rem 0 0;
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
