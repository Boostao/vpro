<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { formatError } from '../shared/readRequests';
  import { notifications } from '../shell/notificationService.svelte';
  import type {
    SummaryEnvironmentalPort,
    SummaryEnvironmentalSession,
    SummaryEnvironmentalNumericSession,
    SummaryEnvironmentalLifeformSession,
  } from './summaryVegetationEnvironmental';
  import type { FieldListCell } from './summaryVegetationFieldList';
  import type { SummaryEnvironmentalValue } from './summaryVegetationEnvironmentalNumeric';
  let {
    session,
    port,
    numeric = false,
    lifeform = false,
    operationHeld = false,
    onBusyChange,
  }: {
    session: SummaryEnvironmentalSession | SummaryEnvironmentalNumericSession | SummaryEnvironmentalLifeformSession;
    port: SummaryEnvironmentalPort;
    numeric?: boolean;
    lifeform?: boolean;
    operationHeld?: boolean;
    onBusyChange: (busy: boolean) => void;
  } = $props();
  const retained = untrack(() => session);
  let view = $state.raw(retained.view());
  let error = $state('');
  let lastViewError = '';
  function syncEnvNotifications() {
    const err = view?.error ?? '';
    if (err && err !== lastViewError) {
      notifications.error('Summary environmental inspection failed', err, {
        category: 'reports',
        source: 'Summary Vegetation',
        contextTag: retained.owner?.project || undefined,
      });
    }
    lastViewError = err;
  }
  const unsubscribe = retained.subscribe(() => {
    view = retained.view();
    syncEnvNotifications();
    onBusyChange(view.busy || view.settling);
  });
  syncEnvNotifications();
  async function preview() {
    if (operationHeld || view.busy || view.settling) return;
    error = '';
    try {
      await retained.show(port);
      syncEnvNotifications();
    } catch (cause) {
      error = formatError(cause);
      notifications.error('Summary environmental inspection failed', error, {
        category: 'reports',
        source: 'Summary Vegetation',
        contextTag: retained.owner?.project || undefined,
      });
    }
  }
  function cancel() {
    retained.cancel();
  }
  function environmentalText(value: FieldListCell | SummaryEnvironmentalValue) {
    if ('kind' in value && value.kind === 'empty') return 'Empty (no numeric value)';
    const cell = 'kind' in value ? value.cell : value;
    return cell.storage === 'integer' ? cell.integer : cell.text === '' ? '""' : cell.text;
  }
  onDestroy(() => {
    if (view.busy) retained.cancel();
    unsubscribe();
    onBusyChange(false);
  });
</script>

<section class="environmental" data-summary-environment aria-label="Combined Summary environmental inspection">
  <h2>Environmental rows — current Site Unit Table</h2>
  <div class="actions">
    <button data-summary-environment-preview disabled={operationHeld || view.busy || view.settling} onclick={preview}
      >Preview environmental rows</button
    >
    {#if view.busy}<button data-summary-environment-cancel onclick={cancel}>Cancel environmental preview</button>{/if}
  </div>
  {#if view.settling && !view.busy}<p role="status">
      Cancelled dispatch or validation is still settling. Navigation, close and another Preview must wait.
    </p>{/if}
  <p>
    This read-only inspection uses Layer, By n Plots and % Cover to establish the unit frame. It does not consume the
    controls or saved Include Env preference above. Every selected physical Report=Yes field is read afresh, including
    hidden and NULL-order rows. Count and nineteen direct category summaries are available, along with Bedrock arguments
    1/2/3 and Disturbance arguments 1/2.
    {#if numeric}The numeric inspection also supports Seepage, Rooting Depth, Stand Age, Elevation, Slope and the six
      substrate/four stratum covers. Empty numeric results are explicitly labelled, not converted to zero or an empty
      string.
    {:else}Numeric functions remain unavailable in this categorical inspection.{/if}
    {#if lifeform}Lifeform cover arguments 1 through 13 use the raw physical vegetation and master species reference
      from the same owned snapshot. A lifeform String empty remains an empty string, not an Empty numeric result.{:else}Lifeform
      environmental rows remain unavailable in this inspection.{/if}
    Unsupported selections refuse the whole result. Grouped environmental reports, formatting, workbooks and printing remain
    unavailable. No data or settings are saved.
  </p>
  {#if view.result && !operationHeld}
    <article data-summary-environment-result>
      <p class="paths">
        Field-list source: {view.result.sourcePath}<br />Environmental source: {view.result.envSourcePath}
      </p>
      {#if lifeform && 'masterSourcePath' in view.result}<p class="paths">
          Lifeform master source: {view.result.masterSourcePath}
        </p>{/if}
      <div class="table-scroll">
        <table>
          <caption>Environmental inspection — {retained.owner.project}, {retained.owner.su}</caption>
          <thead
            ><tr
              ><th scope="col">Source</th><th scope="col">Label</th>
              {#each view.result.vegetation.units as unit}<th scope="col"
                  >{unit.code === '' ? '"" (empty unit)' : unit.code}</th
                >{/each}
            </tr></thead
          >
          <tbody>
            {#each view.result.rows as row}
              <tr data-environment-field-row={row.field.rowId}>
                <td
                  >{row.field.cells[1].text === null
                    ? 'NULL'
                    : row.field.cells[1].text === ''
                      ? '""'
                      : row.field.cells[1].text}</td
                >
                <th scope="row"
                  >{row.field.cells[2].text === null
                    ? 'NULL label'
                    : row.field.cells[2].text === ''
                      ? '""'
                      : row.field.cells[2].text}
                  <small>Physical row {row.field.rowId}</small></th
                >
                {#each row.values as value}<td>{environmentalText(value)}</td>{/each}
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
      {#if view.result.rows.length === 0}<p>
          No fields have Report=Yes. This is an empty selection, not a missing source.
        </p>{/if}
      <p>{view.result.source}</p>
    </article>
  {/if}
</section>

<style>
  .environmental {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 0.75rem;
    min-width: 0;
    overflow-wrap: anywhere;
    color: var(--vpro-ink);
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.75rem;
  }
  button {
    min-height: 2.5rem;
    padding: 0.5rem 0.85rem;
    border: 1px solid var(--vpro-navy);
    border-radius: 0.25rem;
    background: var(--vpro-surface);
    color: var(--vpro-navy);
    font-weight: 600;
    cursor: pointer;
  }
  button:hover:not(:disabled) {
    background: var(--vpro-canvas);
  }
  button:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }
  .paths {
    overflow-wrap: anywhere;
    color: var(--vpro-ink-secondary);
  }
  .table-scroll {
    max-width: 100%;
    overflow-x: auto;
  }
  table {
    width: 100%;
    border-collapse: collapse;
    background: var(--vpro-surface);
  }
  th,
  td {
    padding: 0.5rem;
    border: 1px solid var(--vpro-border);
    text-align: left;
    vertical-align: top;
    white-space: pre-wrap;
  }
  thead th {
    background: var(--vpro-canvas);
    color: var(--vpro-navy);
  }
  small {
    display: block;
    font-weight: normal;
    color: var(--vpro-ink-secondary);
  }
  article {
    min-width: 0;
  }
</style>
