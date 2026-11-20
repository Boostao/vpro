<script lang="ts">
  import type { SiteUnitSummaryMode } from './siteUnitSummary';

  export interface SiteUnitFieldsetsModel {
    su: string;
    mode: SiteUnitSummaryMode;
    siteUnitType: number | null;
    method: number | null;
    busy: boolean;
    workbookBusy: boolean;
    preferenceBarrier: boolean;
    speciesBarrier: boolean;
    ready: boolean;
    preferenceView: { busy?: boolean; blocked?: boolean } | null;
    speciesView: {
      enabled: boolean;
      error: string;
      coverCalculation: number;
      andOr: number;
      presenceGreaterThan: string;
      coverGreaterThan: string;
    } | null;
  }

  export interface SiteUnitFieldsetsHandlers {
    editMode: (mode: SiteUnitSummaryMode) => void;
    editSiteUnitType: (value: number) => void;
    editMethod: (value: number) => void;
    editSpeciesEnabled: (enabled: boolean) => void;
    editSpeciesChoice: (field: 'coverCalculation' | 'andOr', value: number) => void;
    editSpeciesText: (field: 'presenceGreaterThan' | 'coverGreaterThan', value: string) => void;
    resetSpeciesCriteria: () => void;
  }

  let { model, handlers }: { model: SiteUnitFieldsetsModel; handlers: SiteUnitFieldsetsHandlers } = $props();
</script>

<fieldset
  disabled={model.busy || model.workbookBusy || model.preferenceBarrier || model.speciesBarrier || !model.ready}
>
  <legend>Vegetation summary preview</legend>
  <label>
    <input
      type="radio"
      name="summary-vegetation"
      checked={model.mode === 'layer'}
      onchange={() => handlers.editMode('layer')}
    />Layer covers
  </label>
  <label>
    <input
      type="radio"
      name="summary-vegetation"
      checked={model.mode === 'lifeform'}
      onchange={() => handlers.editMode('lifeform')}
    />Lifeform cover values
  </label>
  <label>
    <input
      type="radio"
      name="summary-vegetation"
      data-summary-orderby-strata
      checked={model.mode === 'strata'}
      onchange={() => handlers.editMode('strata')}
    />Strata A–D
  </label>
</fieldset>
{#if model.mode === 'lifeform'}
  <p class="guidance">
    Summarizes cover across standard BEC lifeforms (minimum, mean, and maximum) alongside site and soil fields.
  </p>
{:else if model.mode === 'strata'}
  <p class="guidance">
    Sums layer covers per plot and species across strata A–D (Tree, Shrub, Herb, Moss), capped at 99%.
  </p>
{/if}
<fieldset
  disabled={model.busy || model.workbookBusy || model.preferenceBarrier || model.speciesBarrier}
  data-source-control="optSiteUnitType"
  data-config-key="SESuType"
>
  <legend>Site Unit Scope</legend>
  <label>
    <input
      type="radio"
      name="summary-su-type"
      value={1}
      checked={model.siteUnitType === 1}
      disabled={model.su === 'None' || model.su === 'USysSuTableDynamic'}
      onchange={() => handlers.editSiteUnitType(1)}
    />Selected Site Unit Table
  </label>
  <label>
    <input
      type="radio"
      name="summary-su-type"
      value={2}
      checked={model.siteUnitType === 2}
      disabled={model.su === 'None'}
      data-summary-sutype-hierarchy
      onchange={() => handlers.editSiteUnitType(2)}
    />Hierarchy (~) Breakpoints
  </label>
  <label>
    <input
      type="radio"
      name="summary-su-type"
      value={3}
      checked={model.siteUnitType === 3}
      data-summary-sutype-field
      onchange={() => handlers.editSiteUnitType(3)}
    />Field-Derived Units
  </label>
</fieldset>
<fieldset
  disabled={model.busy ||
    model.workbookBusy ||
    model.speciesBarrier ||
    model.preferenceView?.busy ||
    model.preferenceView?.blocked ||
    !model.ready}
  data-source-control="optValueMethod"
>
  <legend>Quantitative Values</legend>
  <label>
    <input
      type="radio"
      name="summary-method"
      value={1}
      checked={model.method === 1}
      onchange={() => handlers.editMethod(1)}
    />Mean
  </label>
  <label>
    <input
      type="radio"
      name="summary-method"
      value={2}
      checked={model.method === 2}
      onchange={() => handlers.editMethod(2)}
    />Interquartile (25% - 50% - 75%)
  </label>
</fieldset>
{#if model.speciesView}
  <fieldset disabled={model.busy || model.workbookBusy || model.preferenceBarrier}>
    <legend>Species preview criteria</legend>
    <label>
      <input
        type="checkbox"
        data-summary-species-enabled
        checked={model.speciesView.enabled}
        disabled={model.speciesBarrier || !model.ready}
        onchange={(e) => handlers.editSpeciesEnabled(e.currentTarget.checked)}
      />Include species list in preview
    </label>
    {#if model.speciesView.enabled}
      <label>
        Cover calculation
        <select
          data-summary-species-average
          value={model.speciesView.coverCalculation}
          onchange={(e) => handlers.editSpeciesChoice('coverCalculation', Number(e.currentTarget.value))}
        >
          <option value={1}>All plots in unit</option>
          <option value={2}>Plots where present</option>
        </select>
      </label>
      <label>
        Criteria combination
        <select
          data-summary-species-combination
          value={model.speciesView.andOr}
          onchange={(e) => handlers.editSpeciesChoice('andOr', Number(e.currentTarget.value))}
        >
          <option value={1}>AND</option>
          <option value={2}>OR</option>
        </select>
      </label>
      <label>
        Presence greater than (%)
        <input
          data-summary-species-presence
          inputmode="numeric"
          value={model.speciesView.presenceGreaterThan}
          aria-invalid={!!model.speciesView.error}
          oninput={(e) => handlers.editSpeciesText('presenceGreaterThan', e.currentTarget.value)}
        />
      </label>
      <label>
        Cover greater than (%)
        <input
          data-summary-species-cover
          inputmode="numeric"
          value={model.speciesView.coverGreaterThan}
          aria-invalid={!!model.speciesView.error}
          oninput={(e) => handlers.editSpeciesText('coverGreaterThan', e.currentTarget.value)}
        />
      </label>
      <button data-summary-species-reset onclick={handlers.resetSpeciesCriteria}>Reset preview criteria</button>
    {/if}
  </fieldset>
  <p class="guidance">
    Filters the vegetation species list by minimum presence and cover across layer, lifeform, and Strata A–D views.
  </p>
{/if}

<style>
  fieldset {
    display: flex;
    flex-wrap: wrap;
    gap: 1rem;
    margin: 0.5rem 0;
    padding: 0.75rem;
    background: var(--vpro-surface);
    border: 1px solid var(--vpro-border);
    border-radius: 0.5rem;
    min-width: 0;
  }
  fieldset legend {
    font-weight: 600;
    color: var(--vpro-navy);
    padding: 0 0.35rem;
  }
  label {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    color: var(--vpro-ink);
    min-width: minmax(min(100%, 140px), auto);
  }
  button {
    min-height: 2.5rem;
    border: 1px solid var(--vpro-navy);
    border-radius: 0.25rem;
    padding: 0.5rem 0.85rem;
    background: var(--vpro-navy);
    color: var(--vpro-surface);
    font-weight: 600;
    cursor: pointer;
  }
  button:hover:not(:disabled) {
    background: var(--vpro-navy-dark);
    border-color: var(--vpro-navy-dark);
  }
  button:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
  .guidance {
    font-size: 0.9rem;
    margin: 0.4rem 0;
    color: var(--vpro-ink-secondary);
  }
  select,
  input:not([type='radio']):not([type='checkbox']) {
    max-width: 100%;
    min-width: 0;
    border: 1px solid var(--vpro-border);
    border-radius: 0.25rem;
    padding: 0.4rem;
    background: var(--vpro-surface);
    color: var(--vpro-ink);
  }
</style>
