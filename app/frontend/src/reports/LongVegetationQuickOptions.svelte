<script lang="ts">
  import type { LongVegQuickDraft } from './compactReportRunners';

  interface Props {
    draft: LongVegQuickDraft;
    lumpTables: string[];
    disabled?: boolean;
    onChange: (next: LongVegQuickDraft) => void;
  }

  let { draft, lumpTables, disabled = false, onChange }: Props = $props();

  function patch(partial: Partial<LongVegQuickDraft>) {
    onChange({ ...draft, ...partial });
  }
</script>

<div class="vpro64-compact-grid" data-long-veg-quick-options>
  <label class="field-wide">
    <span>Report Title</span>
    <input
      type="text"
      data-quick-lv-title
      value={draft.title}
      placeholder="Long Vegetation Report"
      {disabled}
      oninput={(e) => patch({ title: e.currentTarget.value })}
    />
  </label>
  <label>
    <span>Scope</span>
    <select
      data-quick-lv-scope
      value={draft.scopeMode}
      {disabled}
      onchange={(e) => patch({ scopeMode: e.currentTarget.value as LongVegQuickDraft['scopeMode'] })}
    >
      <option value="auto">Auto (Active SU or Zone+SubZone)</option>
      <option value="su">Active Site Unit Table</option>
      <option value="zone-subzone">Zone + SubZone / SiteSeries</option>
      <option value="all-plots">All Project Plots</option>
    </select>
  </label>
  <label>
    <span>Group By</span>
    <select
      data-quick-lv-grouping
      value={draft.grouping}
      {disabled}
      onchange={(e) => patch({ grouping: e.currentTarget.value as LongVegQuickDraft['grouping'] })}
    >
      <option value="layer">Layer</option>
      <option value="strata">Strata</option>
      <option value="lifeform">Lifeform</option>
      <option value="none">None</option>
    </select>
  </label>
  <label>
    <span>Sort Order</span>
    <select
      data-quick-lv-order
      value={draft.order}
      {disabled}
      onchange={(e) => patch({ order: e.currentTarget.value as LongVegQuickDraft['order'] })}
    >
      <option value="presence">Presence</option>
      <option value="mean-cover">Mean Cover</option>
      <option value="species">Species Name</option>
    </select>
  </label>
  <label>
    <span>Average</span>
    <select
      data-quick-lv-average
      value={draft.average}
      {disabled}
      onchange={(e) => patch({ average: e.currentTarget.value as LongVegQuickDraft['average'] })}
    >
      <option value="all-plots">All Plots</option>
      <option value="non-zero">Non-Zero (Present Plots)</option>
    </select>
  </label>
  <label>
    <span>Species Lumping</span>
    <select
      data-quick-lv-lump
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
      data-quick-lv-code
      checked={draft.showSpeciesCode}
      {disabled}
      onchange={(e) => patch({ showSpeciesCode: e.currentTarget.checked })}
    />
    <span>Show Species Codes</span>
  </label>
  <label class="check-item">
    <input
      type="checkbox"
      data-quick-lv-english
      checked={draft.showEnglishName}
      {disabled}
      onchange={(e) => patch({ showEnglishName: e.currentTarget.checked })}
    />
    <span>Show Common Names</span>
  </label>
  <label class="check-item">
    <input
      type="checkbox"
      data-quick-lv-constant
      checked={draft.constantSpeciesList}
      {disabled}
      onchange={(e) => patch({ constantSpeciesList: e.currentTarget.checked })}
    />
    <span>Constant Species List</span>
  </label>
  <label class="check-item">
    <input
      type="checkbox"
      data-quick-lv-combine
      checked={draft.combineVariants}
      {disabled}
      onchange={(e) => patch({ combineVariants: e.currentTarget.checked })}
    />
    <span>Roll Up Subspecies / Varieties</span>
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
