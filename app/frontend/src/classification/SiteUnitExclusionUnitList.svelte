<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { ExclusionMatchMode, SiteUnitExclusionPreview, SiteUnitExclusionRule } from './siteUnitExclusionFilter';

  let {
    rules,
    newPattern = $bindable(),
    newMatchMode = $bindable(),
    preview,
    onToggleRule,
    onRemoveRule,
    onAddRule,
    children,
  }: {
    rules: SiteUnitExclusionRule[];
    newPattern: string;
    newMatchMode: ExclusionMatchMode;
    preview: SiteUnitExclusionPreview | null;
    onToggleRule: (idx: number) => void;
    onRemoveRule: (idx: number) => void;
    onAddRule: () => void;
    children?: Snippet;
  } = $props();
</script>

<div class="vpro-sux-rules" role="list" aria-label="Active SiteUnit Exclusion Rules">
  {#each rules as rule, idx (`${rule.pattern}:${rule.matchMode}:${idx}`)}
    <div role="listitem" class="vpro-sux-chip" class:disabled={!rule.enabled}>
      <input
        type="checkbox"
        checked={rule.enabled}
        aria-label={`Enable exclusion rule ${rule.pattern}`}
        onchange={() => onToggleRule(idx)}
      />
      <code class="mono">{rule.pattern}</code>
      <span class="vpro-sux-mode-tag">{rule.matchMode}</span>
      <button
        type="button"
        class="vpro-sux-remove"
        aria-label={`Remove exclusion rule ${rule.pattern}`}
        onclick={() => onRemoveRule(idx)}
      >
        x
      </button>
    </div>
  {/each}
</div>

<div class="vpro-sux-add-row">
  <label>
    <span>Exclude Suffix / Phrase / Wildcard</span>
    <input
      type="text"
      bind:value={newPattern}
      placeholder="e.g. .transitional or *unassigned*"
      onkeydown={(e) => {
        if (e.key === 'Enter') {
          e.preventDefault();
          onAddRule();
        }
      }}
    />
  </label>
  <label>
    <span>Match Mode</span>
    <select bind:value={newMatchMode}>
      <option value="auto">Auto (Dot-Suffix / Phrase / *?)</option>
      <option value="suffix">Case-Insensitive Suffix</option>
      <option value="contains">Case-Insensitive Substring</option>
      <option value="wildcard">Wildcard (* / ?)</option>
    </select>
  </label>
  <button type="button" class="vpro-btn-secondary" onclick={onAddRule}>+ Add Exclusion</button>
</div>

{@render children?.()}

{#if preview}
  <div class="vpro-sux-summary" role="status">
    <p>
      SU <code>{preview.su}</code>:
      <strong>{preview.exclusions.retainedPlots}</strong> of
      <strong>{preview.exclusions.totalPlotsBefore}</strong> plots retained ·
      <strong>{preview.exclusions.excludedPlots}</strong> plots excluded across
      <strong>{preview.exclusions.excludedUnits.length}</strong> unit(s).
      {#if preview.breakpoints}
        Dynamic <code>~</code> rollup:
        <strong>{preview.breakpoints.totalUnitsBefore}</strong> unit(s) -&gt;
        <strong>{preview.breakpoints.totalUnitsAfter}</strong> report unit(s) ({preview.breakpoints.rolledUpPlotCount} plot(s)
        aggregated).
      {/if}
    </p>

    {#if preview.exclusions.excludedUnits.length > 0}
      <details class="vpro-sux-details">
        <summary>Excluded Site Units ({preview.exclusions.excludedUnits.length})</summary>
        <ul>
          {#each preview.exclusions.excludedUnits as ex (ex.siteUnit)}
            <li>
              <code class="mono">{ex.siteUnit}</code> — {ex.plotCount} plot(s) (matched
              <code>{ex.matchedPattern}</code>)
            </li>
          {/each}
        </ul>
      </details>
    {/if}

    {#if preview.breakpoints && preview.breakpoints.buckets.length > 0}
      <details class="vpro-sux-details" open>
        <summary>Dynamic '~' Breakpoint Rollup Buckets ({preview.breakpoints.buckets.length})</summary>
        <ul>
          {#each preview.breakpoints.buckets as b (b.breakpointUnit)}
            <li>
              <strong class="mono">{b.breakpointUnit}</strong> ({b.plotCount} plot(s)) &lt;=
              {b.sourceUnits.join(', ')}
            </li>
          {/each}
        </ul>
      </details>
    {/if}
  </div>
{/if}

<style>
  .vpro-sux-rules {
    display: flex;
    flex-wrap: wrap;
    gap: 0.4rem;
  }
  .vpro-sux-chip {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
    padding: 0.25rem 0.5rem;
    background: var(--vpro-surface);
    border: 1px solid var(--vpro-navy);
    border-radius: 999px;
    font-size: 0.78rem;
  }
  .vpro-sux-chip.disabled {
    opacity: 0.55;
    border-color: var(--vpro-border);
  }
  .vpro-sux-mode-tag {
    font-size: 0.66rem;
    background: var(--vpro-border);
    color: var(--vpro-ink);
    padding: 0.05rem 0.35rem;
    border-radius: 3px;
  }
  .vpro-sux-remove {
    border: 0;
    background: transparent;
    color: var(--vpro-error);
    font-weight: 700;
    padding: 0 2px;
  }
  .vpro-sux-add-row {
    display: flex;
    flex-wrap: wrap;
    align-items: flex-end;
    gap: 0.5rem;
  }
  .vpro-sux-add-row label {
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
    font-size: 0.76rem;
    font-weight: 600;
    color: var(--vpro-navy);
  }
  .vpro-sux-add-row input,
  .vpro-sux-add-row select {
    min-height: 30px;
    padding: 0.2rem 0.45rem;
    border: 1px solid var(--vpro-border);
    border-radius: 3px;
    font-size: 0.8rem;
    background: var(--vpro-surface);
    color: var(--vpro-ink);
  }
  .vpro-sux-summary {
    background: var(--vpro-surface);
    border: 1px solid var(--vpro-border);
    border-top: 2px solid var(--vpro-gold);
    padding: 0.55rem 0.75rem;
    border-radius: 4px;
    font-size: 0.8rem;
  }
  .vpro-sux-summary p {
    margin: 0;
  }
  .vpro-sux-details {
    margin-top: 0.4rem;
    font-size: 0.76rem;
  }
  .vpro-sux-details ul {
    margin: 0.25rem 0 0;
    padding-left: 1.2rem;
  }
  .vpro-btn-secondary {
    min-height: 32px;
    padding: 0.3rem 0.65rem;
    background: var(--vpro-surface);
    color: var(--vpro-navy);
    border: 1px solid var(--vpro-navy);
    border-radius: 4px;
    font-size: 0.8rem;
  }
  .mono {
    font-family: var(--font-mono, monospace);
  }
</style>
