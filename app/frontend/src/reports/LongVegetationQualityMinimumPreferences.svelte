<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
  import { notifications } from '../shell/notificationService.svelte';
  import LongVegetationPreferenceSection from '../shared/LongVegetationPreferenceSection.svelte';
  import { ReadRequests } from '../shared/readRequests';
  import type { LongVegetationStandardPreferenceProps } from './longVegetationPreferenceTypes';
  import { longVegetationQualityMinimumFields, type LongVegetationQualityMinimumPreferencesSession,
    type LongVegetationQualityMinimumPreferenceValues } from './longVegetationQualityMinimumPreferences';

  let { contextId, preferences, operationHeld = false, mutationHeld = false, onReadBusyChange }: LongVegetationStandardPreferenceProps<LongVegetationQualityMinimumPreferencesSession> = $props();
  let view = $state(untrack(() => preferences.view())), reference = $state.raw(untrack(() => preferences.reference()));
  let busy = $state(false), error = $state(''), generation = 0;
  const reads = new ReadRequests();
  const rows = $derived(reference?.definitions.rows ?? []);
  const unsubscribe = untrack(() => preferences.subscribe(() => { view = preferences.view(); reference = preferences.reference(); }));
  function cancel() { generation++; reads.cancelAll(); preferences.cancelLoad(); busy = false; onReadBusyChange(false); }
  async function load() {
    if (busy || operationHeld || view.busy || view.blocked) return;
    cancel(); const request = generation, token = preferences.beginLoad(); error = ''; busy = true; onReadBusyChange(true);
    try {
      const value = await reads.track(VegetationReportService.GetLongVegetationQualityMinimumPreferences(contextId));
      if (request === generation) preferences.applyLoaded(value, token);
    } catch (cause) {
      if (request === generation) {
        error = `Saved quality minimum strings unavailable; no defaults applied: ${String(cause)}`;
        notifications.error('Long Vegetation quality minima load failed', error, { category: 'reports', source: 'Long Vegetation', contextTag: contextId || undefined });
      }
    } finally { if (request === generation) { busy = false; onReadBusyChange(false); } }
  }
  async function save() {
    if (busy || operationHeld || view.busy || view.blocked || view.authorityUnknown || view.draftError) return;
    cancel(); const request = generation; error = '';
    try { await preferences.save(value => VegetationReportService.SaveLongVegetationQualityMinimumPreferences(contextId, JSON.stringify(value))); }
    catch (cause) { if (request === generation) { error = String(cause); notifications.error('Long Vegetation quality minima save failed', error, { category: 'reports', source: 'Long Vegetation', contextTag: contextId || undefined }); } }
  }
  function edit(key: keyof LongVegetationQualityMinimumPreferenceValues, value: string) {
    if (busy || mutationHeld || view.busy || view.blocked) return;
    cancel(); error = ''; preferences.editMinimum(key, value);
  }
  onDestroy(() => { unsubscribe(); cancel(); });
</script>

<LongVegetationPreferenceSection
  {view} {preferences} {busy} {operationHeld} {mutationHeld}
  contextTag={contextId || undefined}
  ariaLabel="Saved Long Vegetation Data Quality minima"
  sectionAttr="data-long-vegetation-quality-minima"
  receiptAttr="data-long-vegetation-quality-minimum-receipt"
  actionPrefix="data-long-vegetation-quality-minimum"
  titleBase="Long Vegetation quality minima"
  savedChangedMsg="Saved quality minimum preferences."
  savedNoChangeMsg="No quality minimum changes."
  unchangedMsg="No quality minimum changes were needed."
  loadLabel="Load saved quality minima"
  saveLabel="Save quality minima"
  undoLabel="Undo quality minimum draft"
  acknowledgeLabel="Acknowledge quality minimum outcome"
  cancelLabel="Cancel quality minimum read"
  guidance="Load saved strings before editing; unloaded disabled inputs do not represent saved values. All three controls suggest the same owned PlotQualitySite items, not active DataQuality ranks. Suggestions are optional; case, whitespace, empty strings and unchanged historical values are retained. Drafts do not change output. Save explicitly, acknowledge and reload report options. These minima apply only when existing quality enforcement is active; this panel does not enable it. Unknown outcomes require owned Load, never blind Save replay. Only these three YAML strings change; no registry, project data, source audits, new qualification logic, printer reset or printing. Explicit Save is a desktop adaptation, not proof of Access automatic Change typing timing."
  onload={load} onsave={save} oncancel={cancel}
>
  <fieldset>
    <legend>Data Quality - Minimum</legend>
    <div class="fields">
      {#each longVegetationQualityMinimumFields as field}
        <label for={'long-vegetation-quality-minimum-' + field.key}>
          <span>{field.label}</span>
          <input id={'long-vegetation-quality-minimum-' + field.key} type="text"
            list="long-vegetation-quality-minimum-suggestions" data-source-control={field.control}
            value={view.draft ? view.draft[field.key] : ''} aria-invalid={!!view.draftError}
            disabled={busy || mutationHeld || view.busy || view.blocked || !view.draft}
            oninput={event => { const value = event.currentTarget.value; edit(field.key, value); }} />
        </label>
      {/each}
    </div>
    <datalist id="long-vegetation-quality-minimum-suggestions">
      {#each rows as row (row.rowId)}
        {#if row.cells && row.cells[3]?.storage === 'text' && typeof row.cells[3].text === 'string' && !row.cells[3].text.includes('\0')}
          <option value={row.cells[3].text}>{row.cells[4]?.text ?? ''}</option>
        {/if}
      {/each}
    </datalist>
  </fieldset>
  {#snippet afterActions()}
    {#if reference}
      <details data-long-vegetation-quality-minimum-definitions>
        <summary>Owned PlotQualitySite suggestions ({rows.length} physical rows)</summary>
        <p>{reference.source}</p>
        {#if rows.length === 0}<p>No suggestions; literal editing remains available.</p>{/if}
        <ul>
          {#each rows as row (row.rowId)}
            <li>Row {row.rowId}: Item {row.cells?.[3]?.storage} {JSON.stringify(row.cells?.[3]?.text)};
              description {row.cells?.[4]?.storage} {JSON.stringify(row.cells?.[4]?.text)}.</li>
          {/each}
        </ul>
      </details>
    {/if}
  {/snippet}
</LongVegetationPreferenceSection>

<style>
  fieldset { min-width: 0; border: 1px solid var(--vpro-border); border-radius: .4rem; padding: .75rem; }
  legend { padding: 0 .35rem; }
  .fields { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 12rem), 1fr)); gap: .75rem; }
  label { display: grid; grid-template-columns: minmax(0, 1fr); gap: .3rem; min-width: 0; }
  input { box-sizing: border-box; width: 100%; min-width: 0; border: 1px solid var(--vpro-border); border-radius: .3rem; padding: .45rem; }
  input:disabled { opacity: .5; }
  details { min-width: 0; } summary { cursor: pointer; padding: .5rem 0; }
  p, li { overflow-wrap: anywhere; } ul { padding-left: 1.25rem; }
</style>
