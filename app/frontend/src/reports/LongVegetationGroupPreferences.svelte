<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
  import { notifications } from '../shell/notificationService.svelte';
  import LongVegetationPreferenceSection from '../shared/LongVegetationPreferenceSection.svelte';
  import { ReadRequests, formatError } from '../shared/readRequests';
  import {
    longVegetationGroupChoices,
    type LongVegetationGroupPreferencesSession,
  } from './longVegetationGroupPreferences';
  import type { LongVegetationStandardPreferenceProps } from './longVegetationPreferenceTypes';

  let {
    contextId,
    preferences,
    operationHeld = false,
    mutationHeld = false,
    onReadBusyChange,
  }: LongVegetationStandardPreferenceProps<LongVegetationGroupPreferencesSession> = $props();
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
      const value = await reads.track(VegetationReportService.GetLongVegetationGroupPreferences(contextId));
      if (request === generation) preferences.applyLoaded(value, token);
    } catch (cause) {
      if (request === generation) {
        error = `Saved report grouping unavailable; no defaults applied: ${formatError(cause)}`;
        notifications.error('Long Vegetation report grouping load failed', error, {
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
        VegetationReportService.SaveLongVegetationGroupPreferences(contextId, JSON.stringify(value))
      );
    } catch (cause) {
      if (request === generation) {
        error = formatError(cause);
        notifications.error('Long Vegetation report grouping save failed', error, {
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
    preferences.editGroup(raw);
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
  ariaLabel="Saved Long Vegetation report grouping"
  sectionAttr="data-long-vegetation-grouping"
  receiptAttr="data-long-vegetation-group-receipt"
  actionPrefix="data-long-vegetation-group"
  titleBase="Long Vegetation report grouping"
  savedChangedMsg="Saved report grouping preference."
  savedNoChangeMsg="No report grouping changes."
  unchangedMsg="No report grouping changes were needed."
  loadLabel="Load saved report grouping"
  saveLabel="Save report grouping"
  undoLabel="Undo report grouping draft"
  acknowledgeLabel="Acknowledge report grouping outcome"
  cancelLabel="Cancel report grouping read"
  guidance={'Load saved grouping before editing; no defaults are applied. Drafts do not change report ' +
    'output. Save explicitly, acknowledge and reload report options. Unavailable modes cannot be ' +
    'newly selected; retaining an unchanged saved mode does not enable its report. Receipts remain ' +
    'after acknowledgement; unknown outcomes require explicit owned Load, never blind Save replay. ' +
    'Only LVGroupBy changes in YAML; no registry, project data, source audits, new calculations or ' +
    'printing.'}
  onload={load}
  onsave={save}
  oncancel={cancel}
>
  <label for="long-vegetation-group">
    <span>Group by</span>
    <select
      id="long-vegetation-group"
      data-source-control="rptLvGroupBy"
      value={view.draft.groupBy}
      aria-invalid={!!view.draftError}
      disabled={busy || mutationHeld || view.busy || view.blocked || !view.saved}
      onchange={(event) => {
        const raw = event.currentTarget.value;
        edit(raw);
      }}
    >
      <option value="" disabled>Load saved Group by</option>
      {#each longVegetationGroupChoices as mode}
        <option
          value={String(mode.value)}
          disabled={!availability?.[mode.capability] && view.saved?.groupBy !== mode.value}
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
