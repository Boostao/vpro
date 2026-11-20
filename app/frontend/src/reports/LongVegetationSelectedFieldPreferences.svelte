<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
  import { notifications } from '../shell/notificationService.svelte';
  import LongVegetationPreferenceSection from '../shared/LongVegetationPreferenceSection.svelte';
  import { ReadRequests, formatError } from '../shared/readRequests';
  import type { LongVegetationStandardPreferenceProps } from './longVegetationPreferenceTypes';
  import {
    longVegetationSelectedFieldSuggestions,
    type LongVegetationSelectedFieldPreferencesSession,
  } from './longVegetationSelectedFieldPreferences';

  let {
    contextId,
    preferences,
    operationHeld = false,
    mutationHeld = false,
    onReadBusyChange,
  }: LongVegetationStandardPreferenceProps<LongVegetationSelectedFieldPreferencesSession> = $props();
  let view = $state(untrack(() => preferences.view())),
    definitions = $state(untrack(() => preferences.definitions()));
  let busy = $state(false),
    error = $state(''),
    generation = 0;
  const reads = new ReadRequests();
  const unsubscribe = untrack(() =>
    preferences.subscribe(() => {
      view = preferences.view();
      definitions = preferences.definitions();
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
      const value = await reads.track(VegetationReportService.GetLongVegetationSelectedFieldPreferences(contextId));
      if (request === generation) preferences.applyLoaded(value, token);
    } catch (cause) {
      if (request === generation) {
        error = `Saved selected field unavailable; no defaults applied: ${formatError(cause)}`;
        notifications.error('Long Vegetation selected field load failed', error, {
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
        VegetationReportService.SaveLongVegetationSelectedFieldPreferences(contextId, JSON.stringify(value))
      );
    } catch (cause) {
      if (request === generation) {
        error = formatError(cause);
        notifications.error('Long Vegetation selected field save failed', error, {
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
    preferences.editField(raw);
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
  ariaLabel="Saved Long Vegetation selected field preferences"
  sectionAttr="data-long-vegetation-selected-field"
  receiptAttr="data-long-vegetation-selected-field-receipt"
  actionPrefix="data-long-vegetation-selected-field"
  titleBase="Long Vegetation selected field"
  savedChangedMsg="Saved selected field preference."
  savedNoChangeMsg="No selected field changes."
  unchangedMsg="No selected field changes were needed."
  loadLabel="Load saved selected field"
  saveLabel="Save selected field preferences"
  undoLabel="Undo selected field draft"
  acknowledgeLabel="Acknowledge selected field outcome"
  cancelLabel="Cancel selected field read"
  guidance={'The source suggestions are not mandatory membership or proof that a physical field exists. ' +
    'Preserve the literal field spelling; no trimming, case change or column creation occurs. A ' +
    'nonempty edit sets Show mode 4, and a later empty edit retains it. Undo restores the saved ' +
    'pair. Drafts do not change report output. Save explicitly, acknowledge and reload report ' +
    'options. Missing or unsupported report fields remain unavailable; saving preferences does not ' +
    'enable them. Receipts survive acknowledgement, and unknown outcomes require an owned Load ' +
    'before further Save. Only LVShowField and its source-coupled mode change in YAML; no registry, ' +
    'project data, source audits or printing.'}
  onload={load}
  onsave={save}
  oncancel={cancel}
>
  <label for="long-vegetation-selected-field">
    <span>Show selected field</span>
    <input
      id="long-vegetation-selected-field"
      data-source-control="cmbShowField"
      type="text"
      list="long-vegetation-selected-field-suggestions"
      value={view.draft.selectedField}
      aria-invalid={!!view.draftError}
      disabled={busy || mutationHeld || view.busy || view.blocked || !view.saved}
      oninput={(event) => {
        const raw = event.currentTarget.value;
        edit(raw);
      }}
    />
  </label>
  <datalist id="long-vegetation-selected-field-suggestions">
    {#each longVegetationSelectedFieldSuggestions as suggestion}<option value={suggestion}></option>{/each}
  </datalist>
  {#if view.saved}
    <dl>
      <div>
        <dt>Saved selected field</dt>
        <dd>{JSON.stringify(view.saved.selectedField)}</dd>
      </div>
      <div>
        <dt>Saved Show mode</dt>
        <dd>{view.saved.mode}</dd>
      </div>
      <div>
        <dt>Staged Show mode</dt>
        <dd>{view.draft.mode}</dd>
      </div>
    </dl>
    {#if view.draft.mode === '4'}
      <p role="status">
        Selected-field mode is staged. Clearing the field retains that mode; it does not select another name.
      </p>
    {/if}
  {/if}
  {#if definitions}
    <details data-long-vegetation-selected-field-definitions>
      <summary>Owned physical fields ({definitions.length})</summary>
      <ul>
        {#each definitions as column}<li>
            <code>{JSON.stringify(column.name)}</code> - {JSON.stringify(column.declaredType)}
          </li>{/each}
      </ul>
    </details>
  {/if}
</LongVegetationPreferenceSection>

<style>
  label {
    display: grid;
    gap: 0.35rem;
    min-width: 0;
  }
  span,
  dd,
  li {
    overflow-wrap: anywhere;
  }
  dd {
    margin: 0.25rem 0 0;
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
