<script lang="ts">
  import type { SummaryEnvQuickDraft } from './compactReportRunners';

  interface Props {
    draft: SummaryEnvQuickDraft;
    su: string;
    disabled?: boolean;
    onChange: (next: SummaryEnvQuickDraft) => void;
  }

  let { draft, su, disabled = false, onChange }: Props = $props();

  function patch(partial: Partial<SummaryEnvQuickDraft>) {
    onChange({ ...draft, ...partial });
  }
</script>

<div class="vpro64-compact-grid" data-summary-env-quick-options>
  <label>
    <span>Summary Statistic</span>
    <select
      data-quick-se-method
      value={draft.method}
      {disabled}
      onchange={(e) => patch({ method: Number(e.currentTarget.value) })}
    >
      <option value={1}>Mean (with Min / Max)</option>
      <option value={2}>Interquartile (Median &amp; IQR)</option>
    </select>
  </label>
  <label>
    <span>Site Unit Scope</span>
    <select
      data-quick-se-sutype
      value={draft.siteUnitType}
      {disabled}
      onchange={(e) => patch({ siteUnitType: Number(e.currentTarget.value) })}
    >
      <option value={1}>
        {su && su !== 'None' ? `Active SU (${su})` : 'Auto (Zone+SubZone / All Plots)'}
      </option>
      <option value={2}>Hierarchy (~) Breakpoints</option>
      <option value={3}>Field-Derived Units</option>
    </select>
  </label>
  <label>
    <span>Vegetation Breakdown</span>
    <select
      data-quick-se-orderby
      value={draft.orderBy}
      {disabled}
      onchange={(e) => patch({ orderBy: Number(e.currentTarget.value) })}
    >
      <option value={1}>By Layer</option>
      <option value={2}>By Lifeform</option>
    </select>
  </label>
  <label class="check-box-col">
    <span>Species List</span>
    <label class="check-item">
      <input
        type="checkbox"
        data-quick-se-species
        checked={Boolean(draft.includeSpecies)}
        {disabled}
        onchange={(e) => patch({ includeSpecies: e.currentTarget.checked ? 1 : 0 })}
      />
      <span>Include Characteristic Species</span>
    </label>
  </label>
  {#if draft.includeSpecies}
    <label>
      <span>Min Presence (%)</span>
      <input
        type="number"
        min="0"
        max="100"
        step="5"
        data-quick-se-presence
        value={draft.presenceGreaterThan}
        {disabled}
        oninput={(e) => patch({ presenceGreaterThan: Number(e.currentTarget.value) || 0 })}
      />
    </label>
    <label>
      <span>Min Cover (%)</span>
      <input
        type="number"
        min="0"
        max="100"
        step="1"
        data-quick-se-cover
        value={draft.coverGreaterThan}
        {disabled}
        oninput={(e) => patch({ coverGreaterThan: Number(e.currentTarget.value) || 0 })}
      />
    </label>
  {/if}
</div>

<style>
  .vpro64-compact-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 190px), 1fr));
    gap: 0.6rem;
    align-items: end;
  }
  .vpro64-compact-grid > label {
    display: grid;
    gap: 0.22rem;
    font-size: 0.8rem;
    font-weight: 600;
    color: var(--vpro-ink);
    min-width: 0;
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
  .check-item {
    display: inline-flex;
    align-items: center;
    gap: 0.4rem;
    font-size: 0.82rem;
    font-weight: 500;
    min-height: 2.1rem;
  }
</style>
