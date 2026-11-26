<script lang="ts">
  import type { SummaryVegQuickDraft } from './compactReportRunners';

  interface Props {
    draft: SummaryVegQuickDraft;
    lumpTables: string[];
    disabled?: boolean;
    onChange: (next: SummaryVegQuickDraft) => void;
  }

  let { draft, lumpTables, disabled = false, onChange }: Props = $props();

  function patch(partial: Partial<SummaryVegQuickDraft>) {
    onChange({ ...draft, ...partial });
  }
</script>

<div class="vpro64-compact-grid" data-summary-veg-quick-options>
  <label class="field-wide">
    <span>Report Title</span>
    <input
      type="text"
      data-quick-sv-title
      value={draft.title}
      placeholder="Summary Vegetation Report"
      {disabled}
      oninput={(e) => patch({ title: e.currentTarget.value })}
    />
  </label>
  <label>
    <span>Units Scope</span>
    <select
      data-quick-sv-scope
      value={draft.unitScope}
      {disabled}
      onchange={(e) => patch({ unitScope: e.currentTarget.value as SummaryVegQuickDraft['unitScope'] })}
    >
      <option value="auto">Auto (Active SU or All Plots)</option>
      <option value="su">Active Site Unit Table</option>
      <option value="none">Whole Project (All Plots)</option>
      <option value="field">Field-Derived Units</option>
      <option value="hierarchy">Hierarchy Breakpoints (~)</option>
    </select>
  </label>
  {#if draft.unitScope === 'field'}
    <label>
      <span>Unit Field</span>
      <input
        type="text"
        data-quick-sv-unit-field
        value={draft.unitField}
        placeholder="e.g. SubZone or SiteUnit"
        {disabled}
        oninput={(e) => patch({ unitField: e.currentTarget.value })}
      />
    </label>
  {/if}
  <label>
    <span>Group By</span>
    <select
      data-quick-sv-group
      value={`g${draft.groupBy}`}
      {disabled}
      onchange={(e) => patch({ groupBy: Number(e.currentTarget.value.slice(1)) || 1 })}
    >
      <option value="g1">Layer</option>
      <option value="g2">Strata</option>
      <option value="g3">Lifeform</option>
      <option value="g4">None</option>
    </select>
  </label>
  <label>
    <span>Display Values</span>
    <select
      data-quick-sv-display
      value={`d${draft.display}`}
      {disabled}
      onchange={(e) => patch({ display: Number(e.currentTarget.value.slice(1)) || 1 })}
    >
      <option value="d1">% Presence &amp; % Cover</option>
      <option value="d2">Presence &amp; Significance Class</option>
      <option value="d3">Presence Class &amp; % Cover</option>
      <option value="d6">% Cover Only</option>
      <option value="d4">Prominence Class</option>
      <option value="d5">Goldstream Class</option>
    </select>
  </label>
  <label>
    <span>Average</span>
    <select
      data-quick-sv-average
      value={`a${draft.average}`}
      {disabled}
      onchange={(e) => patch({ average: Number(e.currentTarget.value.slice(1)) || 1 })}
    >
      <option value="a1">By n Plots</option>
      <option value="a2">Characteristic (Present Plots)</option>
    </select>
  </label>
  <label>
    <span>Species Lumping</span>
    <select
      data-quick-sv-lump
      value={draft.lumpTable}
      {disabled}
      onchange={(e) => patch({ lumpTable: e.currentTarget.value })}
    >
      <option value="">None (Raw Species)</option>
      {#each lumpTables as tableName (tableName)}
        <option value={tableName}>{tableName}</option>
      {/each}
    </select>
  </label>
</div>

<div class="vpro64-compact-checks">
  <label class="check-item">
    <input
      type="checkbox"
      data-quick-sv-common
      checked={draft.showCommon}
      {disabled}
      onchange={(e) => patch({ showCommon: e.currentTarget.checked })}
    />
    <span>Show Common Names</span>
  </label>
  <label class="check-item">
    <input
      type="checkbox"
      data-quick-sv-combine
      checked={draft.combineVariants}
      {disabled}
      onchange={(e) => patch({ combineVariants: e.currentTarget.checked })}
    />
    <span>Roll Up Subspecies / Varieties</span>
  </label>
  <label class="check-item">
    <input
      type="checkbox"
      data-quick-sv-env
      checked={draft.includeEnv}
      {disabled}
      onchange={(e) => patch({ includeEnv: e.currentTarget.checked })}
    />
    <span>Include Environment Summary</span>
  </label>
</div>

<style>
  .vpro64-compact-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 190px), 1fr));
    gap: 0.6rem;
  }
  .vpro64-compact-grid label {
    display: grid;
    gap: 0.22rem;
    font-size: 0.8rem;
    font-weight: 600;
    color: var(--vpro-ink);
    min-width: 0;
  }
  .field-wide {
    grid-column: span 2;
  }
  @media (max-width: 720px) {
    .field-wide {
      grid-column: span 1;
    }
  }
  input:not([type='checkbox']),
  select {
    box-sizing: border-box;
    width: 100%;
    min-width: 0;
    padding: 0.4rem 0.5rem;
    border: 1px solid var(--vpro-border-strong);
    border-radius: 0.25rem;
    background: var(--vpro-surface);
    color: var(--vpro-ink);
    font-size: 0.83rem;
  }
  .vpro64-compact-checks {
    display: flex;
    flex-wrap: wrap;
    gap: 0.85rem;
    padding-top: 0.2rem;
  }
  .check-item {
    display: inline-flex;
    align-items: center;
    gap: 0.4rem;
    font-size: 0.82rem;
    color: var(--vpro-ink);
  }
</style>
