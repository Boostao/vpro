<script lang="ts">
  import type { SummaryVegOptionsHandlers, SummaryVegOptionsModel } from './summaryVegetationReportOps';

  let { model, handlers }: { model: SummaryVegOptionsModel; handlers: SummaryVegOptionsHandlers } = $props();
</script>

<p class="owner">
  Project: {model.project}<br />{model.projectPath}<br />Current Site Unit Table: {model.su}<br />{model.suPath}
</p>
{#if model.unavailableScope}
  <p class="scope-guidance" role="status">
    {model.unitScope === 'field'
      ? 'Enter an environment field name (such as SiteUnit or SubZone) to group plots.'
      : 'Select a Site Unit table in the sidebar, or choose Whole Project or Hierarchy Breakpoints (~).'}
  </p>
{/if}
<div class="options">
  <label
    >Summary Report Units
    <select
      aria-label="Summary Report Units"
      value={model.unitScope}
      onchange={(event) => {
        handlers.onUnitScopeChange(
          (event.currentTarget as HTMLSelectElement).value as 'su' | 'hierarchy' | 'none' | 'field'
        );
      }}
      disabled={model.editHeld}
      data-summary-unit-scope
      data-source-control="optUnitScope"
    >
      <option value="su">Current Site Unit Table</option>
      <option value="hierarchy">Hierarchy Breakpoints (~)</option>
      <option value="none">Whole Project (None)</option>
      <option value="field">Field-Derived Units</option>
    </select>
  </label>
  {#if model.unitScope === 'hierarchy'}
    <label
      >Hierarchy Breakpoint Policy
      <select
        value={model.breakpointPolicy}
        onchange={(event) => {
          handlers.onBreakpointPolicyChange((event.currentTarget as HTMLSelectElement).value as 'lowest' | 'highest');
        }}
        disabled={model.editHeld}
        data-summary-breakpoint-policy
      >
        <option value="lowest">Lowest (~) Breakpoint</option><option value="highest">Highest (~) Breakpoint</option>
      </select>
    </label>
  {:else if model.unitScope === 'field'}
    <label
      >Environment Unit Field
      <input
        type="text"
        value={model.unitField}
        oninput={(event) => handlers.onUnitFieldInput(event.currentTarget.value)}
        placeholder="e.g. SiteUnit or SubZone"
        disabled={model.editHeld}
        data-summary-unit-field
      />
    </label>
  {/if}
  <label
    >Species Lumping Table
    <div class="lump-picker">
      <select
        value={model.lumpTable}
        onchange={(event) => handlers.onLumpTableChange((event.currentTarget as HTMLSelectElement).value)}
        disabled={model.editHeld}
        data-summary-lump-table
      >
        <option value="">None (unlumped species)</option>
        {#each model.lumpTables as tableName}<option value={tableName}>{tableName}</option>{/each}
      </select>
      <button
        type="button"
        onclick={handlers.onRefreshLumpTables}
        disabled={model.editHeld || !model.contextId}
        data-summary-lump-refresh>Discover</button
      >
    </div>
  </label>
  <label
    >Group by
    <select
      value={model.groupAndOrder}
      onchange={handlers.onGroupChange}
      disabled={model.editHeld}
      data-summary-group
      data-source-control="rptSvGroupBy"
    >
      <option value={11}>Layer</option><option value={12} disabled={model.display === 2}>Strata</option>
      <option value={13} disabled={model.display === 2}>Lifeform</option><option value={14}>None</option>
    </select>
  </label>
  <label
    >Display Values
    <select
      value={model.display}
      onchange={handlers.onDisplayChange}
      disabled={model.editHeld}
      data-summary-display
      data-source-control="rptSvValueEq"
    >
      <option value={1}>% Presence and % Cover</option>
      <option value={2} disabled={model.groupAndOrder === 12 || model.groupAndOrder === 13}
        >Presence Class and Significance Class</option
      >
      <option value={3}>Presence Class and % Cover</option>
      <option value={6}>% Cover</option><option value={4}>Prominence Class</option><option value={5}
        >Goldstream Class</option
      >
    </select>
  </label>
  <label
    >Show
    <select
      value={model.showClass}
      onchange={handlers.onShowClassChange}
      disabled={model.editHeld || model.display <= 3}
      data-summary-show
      data-source-control="OptShowClassValue"
    >
      <option value={1}>Class (historical default 1)</option><option value={10}>Class</option><option value={20}
        >Value</option
      >
    </select>
  </label>
  <label
    >Calculate
    <select
      value={model.average}
      onchange={handlers.onAverageChange}
      disabled={model.editHeld}
      data-summary-average
      data-source-control="rptSvAvgType"
    >
      <option value={1}>By n Plots</option><option value={2}>Characteristic</option>
    </select>
  </label>
</div>
<div class="scope-toggles">
  <label class="checkbox-inline">
    <input
      type="checkbox"
      checked={model.combineVariants}
      onchange={(event) => handlers.onCombineVariantsChange(event.currentTarget.checked)}
      disabled={model.editHeld}
      data-summary-combine-variants
      data-source-control="SVSubSppAsSpp"
    />
    Roll up subspecies and varieties into parent species
  </label>
  <label class="checkbox-inline">
    <input
      type="checkbox"
      checked={model.includeGoldstreamMetadata}
      onchange={(event) => handlers.onIncludeGoldstreamChange(event.currentTarget.checked)}
      disabled={model.editHeld}
      data-summary-goldstream-metadata
    />
    Include Goldstream cover-class metadata
  </label>
</div>

<style>
  .owner {
    overflow-wrap: anywhere;
    color: var(--vpro-ink-secondary);
    margin: 0;
  }
  .scope-guidance {
    margin: 0;
    padding: 0.6rem 0.85rem;
    border-left: 4px solid var(--vpro-navy);
    background: var(--vpro-surface);
    color: var(--vpro-ink);
    border-radius: 0.25rem;
  }
  .options {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 280px), 1fr));
    gap: 1rem;
    background: var(--vpro-surface);
    padding: 0.9rem;
    border: 1px solid var(--vpro-border);
    border-radius: 0.5rem;
  }
  .scope-toggles {
    display: flex;
    flex-wrap: wrap;
    gap: 1rem;
    padding: 0.65rem 0.9rem;
    background: var(--vpro-surface);
    border: 1px solid var(--vpro-border);
    border-radius: 0.5rem;
  }
  .checkbox-inline {
    display: flex;
    flex-direction: row;
    align-items: center;
    gap: 0.5rem;
    font-weight: 500;
  }
  .lump-picker {
    display: flex;
    gap: 0.5rem;
    align-items: stretch;
    min-width: 0;
  }
  .lump-picker select {
    flex: 1;
    min-width: 0;
  }
  label {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
    min-width: 0;
    color: var(--vpro-ink);
    font-weight: 500;
  }
  select,
  input:not([type='checkbox']) {
    box-sizing: border-box;
    width: 100%;
    min-width: 0;
    padding: 0.5rem;
    border: 1px solid var(--vpro-border);
    border-radius: 0.25rem;
    background: var(--vpro-surface);
    color: var(--vpro-ink);
  }
  button {
    min-height: 2.5rem;
    padding: 0.5rem 0.85rem;
    border: 1px solid var(--vpro-navy);
    border-radius: 0.25rem;
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
    opacity: 0.6;
    cursor: not-allowed;
  }
  @media (max-width: 960px) {
    .lump-picker {
      flex-direction: column;
    }
  }
</style>
