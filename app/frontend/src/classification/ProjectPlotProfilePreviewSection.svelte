<script lang="ts">
  import type {
    ProjectPlotProfileFilterRequest,
    ProjectPlotProfileRunRequest,
  } from '../../bindings/github.com/boostao/vpro/app';
  import { formatError } from '../shared/readRequests';
  import type { SpeciesPresencePreview } from './projectProfileSpeciesPresence';
  import {
    profileCellLabel,
    profileFilterUnavailable,
    type ProfileReviewTable,
    type ProfileRunResult,
    type ValidatedProjectPlotProfileReview,
  } from './projectPlotProfileReview';

  let {
    allowRun,
    allowEditing,
    allowPresence,
    allowSaveSU,
    allowFiltering,
    busy,
    blocked,
    review,
    lump,
    result,
    runInput,
    presenceResult,
    error = $bindable(),
    onapply,
    onsureview,
  }: {
    allowRun: boolean;
    allowEditing: boolean;
    allowPresence: boolean;
    allowSaveSU: boolean;
    allowFiltering: boolean;
    busy: boolean;
    blocked: boolean;
    review: ValidatedProjectPlotProfileReview | null;
    lump: ProfileReviewTable | null;
    result: ProfileRunResult | null;
    runInput: ProjectPlotProfileRunRequest | null;
    presenceResult: SpeciesPresencePreview | null;
    error: string | null;
    onapply?: (proposal: ProjectPlotProfileFilterRequest) => Promise<void>;
    onsureview?: (proposal: ProjectPlotProfileFilterRequest) => Promise<void>;
  } = $props();

  const reviewedTables = $derived(
    !review
      ? []
      : [
          { title: 'Original profile rules', table: review.rules },
          ...(review.descriptions.columns.length > 0
            ? [{ title: 'Original table-object descriptions', table: review.descriptions }]
            : []),
          ...((allowRun || allowEditing || allowPresence) && lump
            ? [{ title: 'Explicitly selected project-local lump definitions', table: lump }]
            : []),
        ]
  );

  async function applyNavigation() {
    if (!allowFiltering || !allowRun || busy || blocked || !result || !runInput || !onapply) {
      error = 'Run available stored inputs and finish profile drafts before applying navigation.';
      return;
    }
    const unavailable = profileFilterUnavailable(result);
    if (unavailable) {
      error = unavailable;
      return;
    }
    try {
      await onapply(structuredClone($state.snapshot({ input: runInput, preview: result })));
    } catch (cause) {
      error = `Profile navigation was not applied; preview and current filter retained: ${formatError(cause)}`;
    }
  }

  async function reviewSaveSU() {
    if (!allowSaveSU || !allowRun || busy || blocked || !result || !runInput || !onsureview) {
      error = 'Run stored inputs and finish profile drafts before reviewing Save as SU.';
      return;
    }
    try {
      await onsureview(structuredClone($state.snapshot({ input: runInput, preview: result })));
    } catch (cause) {
      error = `Save as SU review failed; preview and drafts retained: ${formatError(cause)}`;
    }
  }
</script>

{#if presenceResult}
  <section aria-label="Readonly species-only matches" class="mt-3 min-w-0">
    <h3 class="font-semibold">
      Saved species-only matches: {presenceResult.plotNumbers.length} of {presenceResult.totalPlots} scope plots
    </h3>
    <p class="text-sm">{presenceResult.project} / {presenceResult.table} / {presenceResult.su}</p>
    <p class="mt-2 whitespace-pre-wrap">
      {presenceResult.plotNumbers.length ? presenceResult.plotNumbers.join(', ') : 'No matching plots.'}
    </p>
    <p class="vpro-prof-muted mt-2 text-sm">
      Readonly Table/Species intersection using the nine source presence columns. Species equality ignores ASCII case
      and terminal ASCII spaces; * and ? remain literal. Order, field, numeric criteria, layer, operation and historical
      counts are ignored. No navigation, Save-as-SU, count or audit action is available for this result; the original
      Access callback remains unavailable.
    </p>
  </section>
{/if}

{#if allowSaveSU && result}
  <button
    type="button"
    class="vpro-prof-btn mt-3 px-3 py-2 rounded disabled:opacity-50"
    disabled={busy || blocked}
    onclick={() => void reviewSaveSU()}
  >
    Review Save as SU
  </button>
{/if}

{#if allowFiltering && result}
  <div class="mt-3">
    <button
      type="button"
      class="vpro-prof-btn px-3 py-2 rounded disabled:opacity-50"
      disabled={busy || blocked || profileFilterUnavailable(result) !== null}
      onclick={() => void applyNavigation()}
    >
      Apply reviewed profile navigation
    </button>
    {#if profileFilterUnavailable(result)}
      <p role="alert" class="vpro-prof-alert mt-2">{profileFilterUnavailable(result)}</p>
    {/if}
    <p class="mt-2 text-sm">
      Explicit navigation only; current stored inputs are independently rechecked after Save/Discard/Cancel. No count,
      SU or configuration write.
    </p>
  </div>
{/if}

{#if result}
  <section class="vpro-prof-result-card mt-3 p-3 rounded" aria-label="Stored profile preview results">
    <h3 class="font-semibold">
      Preview only: {result.plotNumbers.length} matching plots / {result.totalPlots} stored scope plots
    </h3>
    <p>Scope: {result.project}; Working Unit list: {result.su}. No form filter or SU table has been changed.</p>
    <div class="overflow-x-auto">
      <table class="w-full text-xs border-collapse">
        <caption class="text-left py-2">Run-only counts, not stored PlotCount</caption>
        <thead>
          <tr>
            {#each ['Physical rule', 'Order', 'Operation', 'Step count', 'Remaining'] as label}
              <th scope="col" class="border p-2 text-left">{label}</th>
            {/each}
          </tr>
        </thead>
        <tbody>
          {#each result.steps as step (step.rowId)}
            <tr>
              <th scope="row" class="border p-2">{step.rowId}</th>
              <td class="border p-2">{step.order}</td>
              <td class="border p-2">{step.operation}</td>
              <td class="border p-2" aria-label={`Step count, rule ${step.rowId}`}>{step.plotCount}</td>
              <td class="border p-2" aria-label={`Remaining, rule ${step.rowId}`}>{step.remaining}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
    <p class="mt-2 whitespace-pre-wrap break-words" data-profile-plots>
      {result.plotNumbers.join(', ') || 'No matching plots.'}
    </p>
  </section>
{/if}

{#if review}
  <p class="my-3">
    Source: {review.project} / {review.table}. Rules follow stored Order; duplicate Orders retain distinct physical
    records. PlotCount is historical storage, not a recalculated result.
  </p>
  {#if review.descriptions.columns.length === 0}
    <p class="my-3">Original description metadata table is absent; no descriptions are inferred or created.</p>
  {/if}
  {#each reviewedTables as item}
    <div class="overflow-x-auto mt-3">
      <table class="w-full border-collapse text-xs">
        <caption class="text-left font-semibold py-2">{item.title}</caption>
        <thead>
          <tr>
            <th scope="col" class="border p-2 text-left">Physical row</th>
            {#each item.table.columns as column}
              <th scope="col" class="border p-2 text-left">
                {column.name}<span class="vpro-prof-muted block font-normal">{column.declaredType}</span>
              </th>
            {/each}
          </tr>
        </thead>
        <tbody>
          {#each item.table.rows as row (row.rowId)}
            <tr>
              <th scope="row" class="border p-2 text-left">{row.rowId}</th>
              {#each row.cells as cell, index}
                <td
                  class="border p-2 whitespace-pre-wrap min-w-24"
                  aria-label={`${item.table.columns[index].name}, record ${row.rowId}`}>{profileCellLabel(cell)}</td
                >
              {/each}
            </tr>
          {/each}
        </tbody>
      </table>
      {#if item.table.rows.length === 0}<p class="py-2">No physical records in this source table.</p>{/if}
    </div>
  {/each}
{/if}

<p class="vpro-prof-muted mt-3 text-sm">
  This uses only explicitly selected stored rules and project data, never unsaved plot drafts. Ordered preview runs use
  isolated temporary workspace results and source-scoped Env/Veg/Lump operations (including Lump/Any/=/Add fixed
  equality semantics and Start with all plots); their text matching supports ASCII literals and simple * / ? patterns
  only. Unsupported rules fail explicitly. Other-table/external writes require separate current-session authorization;
  restoration remains unavailable. Save as SU creates only a new VPro project file (.db) after its separate opt-in and
  explicit review. Profile selection, rule creation/deletion and navigation filtering require their separate opt-ins. No
  stored PlotCount or shipped scratch table is changed.
</p>

<style>
  .vpro-prof-btn {
    background: var(--vpro-surface);
    color: var(--vpro-navy);
    border: 1px solid var(--vpro-navy);
  }
  .vpro-prof-result-card {
    background: var(--vpro-surface);
    border: 1px solid var(--vpro-success);
    border-left: 4px solid var(--vpro-success);
  }
  .vpro-prof-alert {
    color: var(--vpro-error);
    font-weight: 600;
  }
  .vpro-prof-muted {
    color: var(--vpro-ink-secondary);
  }
</style>
