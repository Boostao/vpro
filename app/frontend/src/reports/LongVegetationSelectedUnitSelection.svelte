<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
  import { notifications } from '../shell/notificationService.svelte';
  import { ReadRequests } from '../shared/readRequests';
  import type { SelectedUnitSelectionSession } from './longVegetationSelectedUnitSelection';

  let {
    contextId,
    selection,
    operationHeld = false,
    mutationHeld = false,
    onChange,
  }: {
    contextId: string;
    selection: SelectedUnitSelectionSession;
    operationHeld?: boolean;
    mutationHeld?: boolean;
    onChange: () => void;
  } = $props();
  let view = $state.raw(untrack(() => selection.view()));
  const reads = new ReadRequests();
  let lastViewError = '';
  function syncSelectedUnitNotifications() {
    const viewErr = view.error ?? '';
    if (viewErr && viewErr !== lastViewError) {
      notifications.error('Long Vegetation selected unit fields failed', viewErr, {
        category: 'reports',
        source: 'Long Vegetation',
        contextTag: typeof contextId === 'string' && contextId ? contextId : undefined,
      });
    }
    lastViewError = viewErr;
  }
  const unsubscribe = untrack(() =>
    selection.subscribe(() => {
      view = selection.view();
      syncSelectedUnitNotifications();
      onChange();
    })
  );
  syncSelectedUnitNotifications();
  function cancel() {
    reads.cancelAll();
    selection.cancel();
  }
  async function load() {
    if (operationHeld || view.busy) return;
    await selection.load(() => reads.track(VegetationReportService.GetLongVegetationSelectedUnitSelection(contextId)));
    if (typeof syncSelectedUnitNotifications === 'function') syncSelectedUnitNotifications();
  }
  async function build() {
    if (operationHeld || view.busy || view.authorityUnknown || view.draftError || !view.review) return;
    await selection.build(
      (request) =>
        reads.track(VegetationReportService.SetLongVegetationSelectedUnitFields(contextId, JSON.stringify(request))),
      (revision) => reads.track(VegetationReportService.BuildLongVegetationSelectedUnitSelection(contextId, revision))
    );
    if (typeof syncSelectedUnitNotifications === 'function') syncSelectedUnitNotifications();
  }
  function edit(fields: string[]) {
    if (mutationHeld || view.busy || !view.review) return;
    selection.edit(fields);
  }
  function move(index: number, offset: number) {
    const fields = [...view.fields],
      other = index + offset;
    if (other < 0 || other >= fields.length) return;
    [fields[index], fields[other]] = [fields[other], fields[index]];
    edit(fields);
  }
  onDestroy(() => {
    unsubscribe();
    cancel();
  });
</script>

<section class="selection" aria-label="Selected report unit fields" data-long-vegetation-selected-unit-selection>
  {#if view.draftError}<p role="alert" class="error">{view.draftError}</p>{/if}
  {#if view.authorityUnknown}<p role="alert">
      Field selection status is uncertain after an interrupted update; reload the Field List before building or viewing
      the report.
    </p>{/if}
  <div class="lists">
    <div>
      <h4>Field List</h4>
      {#if view.review}
        <ul>
          {#each view.review.definitions as field, index}
            <li>
              <span>{field.table}.{field.name} ({field.declaredType || 'untyped'})</span>
              <button
                data-selected-unit-add={index}
                disabled={mutationHeld ||
                  view.busy ||
                  !field.available ||
                  view.fields.some((name) => name.toLowerCase() === field.name.toLowerCase())}
                onclick={() => edit([...view.fields, field.name])}
                aria-label={`Add ${field.table}.${field.name}`}>Add</button
              >
              {#if !field.available}<small>{field.reason}</small>{/if}
            </li>
          {/each}
        </ul>
      {:else}<p>Load the Site and Admin Field List to choose grouping fields; no defaults are assumed.</p>{/if}
    </div>
    <div>
      <h4>Selected List</h4>
      <ol>
        {#each view.fields as name, index}
          <li>
            <span>{name}</span>
            <div class="actions">
              <button
                data-selected-unit-up={index}
                disabled={mutationHeld || view.busy || index === 0}
                aria-label={`Move ${name} up`}
                onclick={() => move(index, -1)}>Up</button
              >
              <button
                data-selected-unit-down={index}
                disabled={mutationHeld || view.busy || index === view.fields.length - 1}
                aria-label={`Move ${name} down`}
                onclick={() => move(index, 1)}>Down</button
              >
              <button
                data-selected-unit-remove={index}
                disabled={mutationHeld || view.busy}
                aria-label={`Remove ${name}`}
                onclick={() => edit(view.fields.filter((_, i) => i !== index))}>Remove</button
              >
            </div>
          </li>
        {/each}
      </ol>
    </div>
  </div>
  <div class="actions">
    <button data-selected-unit-load disabled={operationHeld || view.busy} onclick={load}>Load owned Field List</button>
    <button
      data-selected-unit-build
      disabled={operationHeld || view.busy || view.authorityUnknown || !!view.draftError || !view.review}
      onclick={build}>Build SU List</button
    >
    <button
      data-selected-unit-undo
      disabled={mutationHeld || view.busy || !view.review}
      onclick={() => selection.undo()}>Undo field draft</button
    >
    {#if view.busy}<button data-selected-unit-cancel onclick={cancel}>Cancel field read/Build</button>{/if}
  </div>
  {#if view.review?.build}
    <div class="receipt" data-selected-unit-build-receipt>
      <p role="status">
        Read-only Build receipt: {view.review.build.occurrences.length} original derived rows.
        {view.review.buildCurrent && !view.dirty
          ? 'Source is current.'
          : 'Approval is not current for this draft/source; Build explicitly before output.'}
      </p>
      <p>Approval: <code>{view.review.build.approvalHash}</code></p>
    </div>
  {/if}
  <p class="guidance">
    Selected fields combine in Selected List order without a separator. Building the SU List is read-only and never
    modifies project records, temporary tables, or audit history. After building, load saved Unit Groups and save
    Selected fields to apply. Unsupported or ambiguous fields stay disabled, and blank or overlength unit labels are
    rejected rather than truncated.
  </p>
</section>

<style>
  .selection {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 0.75rem;
    min-width: 0;
  }
  .lists {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 1rem;
  }
  .lists > div,
  .receipt {
    min-width: 0;
  }
  ul,
  ol {
    padding-left: 1.25rem;
    margin: 0.5rem 0;
  }
  li {
    margin-bottom: 0.65rem;
    overflow-wrap: anywhere;
  }
  li > span,
  small {
    display: block;
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    align-items: center;
  }
  button {
    border: 1px solid var(--vpro-border);
    border-radius: 0.4rem;
    padding: 0.5rem 0.75rem;
    background: var(--vpro-surface);
  }
  button:disabled {
    opacity: 0.5;
  }
  .receipt code,
  .receipt p {
    overflow-wrap: anywhere;
  }
  .error {
    color: var(--vpro-error);
  }
  .guidance,
  small {
    color: var(--vpro-ink-secondary);
    font-size: 0.875rem;
  }
  @media (max-width: 640px) {
    .lists {
      grid-template-columns: minmax(0, 1fr);
    }
  }
</style>
