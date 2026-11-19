<script lang="ts">
  import { AlertCircle, ArrowUpRight, ChevronDown, ChevronUp } from '@lucide/svelte';
  import type { FormValidationItem } from './formValidationSummary';

  let {
    items = [],
    onjump,
  }: {
    items?: readonly FormValidationItem[];
    onjump?: (item: FormValidationItem) => void;
  } = $props();

  let expanded = $state(true);
</script>

{#if items.length > 0}
  <section
    class="vpro-validation-bar"
    aria-label="Draft validation issues"
    data-validation-summary
  >
    <div class="vpro-validation-header">
      <div class="vpro-validation-lead">
        <AlertCircle size={15} class="shrink-0 text-vpro-error" />
        <strong class="tabular-nums">
          {items.length} validation {items.length === 1 ? 'issue blocks' : 'issues block'} Save &amp; Lock
        </strong>
        <span class="vpro-validation-hint">Click any field pill to jump directly to the offending input.</span>
      </div>
      <button
        type="button"
        class="vpro-validation-toggle"
        aria-expanded={expanded}
        onclick={() => (expanded = !expanded)}
      >
        {expanded ? 'Hide pills' : `Show ${items.length}`}
        {#if expanded}<ChevronUp size={13} />{:else}<ChevronDown size={13} />{/if}
      </button>
    </div>

    {#if expanded}
      <div class="vpro-validation-pills">
        {#each items as item (item.id)}
          <button
            type="button"
            class="vpro-validation-pill"
            data-validation-jump={item.id}
            data-validation-tab={item.tab}
            title={`${item.tabLabel} — ${item.fieldLabel}: ${item.message}`}
            onclick={() => onjump?.(item)}
          >
            <span class="vpro-validation-tab">{item.tabLabel}</span>
            <span class="vpro-validation-field">{item.fieldLabel}:</span>
            <span class="vpro-validation-msg">{item.message}</span>
            <ArrowUpRight size={12} class="shrink-0 opacity-75" />
          </button>
        {/each}
      </div>
    {/if}
  </section>
{/if}

<style>
  .vpro-validation-bar {
    position: sticky;
    top: 0;
    z-index: 15;
    background: var(--vpro-error-bg);
    border-bottom: 2px solid var(--vpro-error);
    padding: 0.45rem 0.85rem;
    color: var(--vpro-error-ink);
    font-size: 0.75rem;
  }
  .vpro-validation-header {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 0.5rem;
  }
  .vpro-validation-lead {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.45rem;
  }
  .vpro-validation-hint {
    color: var(--vpro-ink-secondary);
    font-size: 0.72rem;
  }
  .vpro-validation-toggle {
    display: inline-flex;
    align-items: center;
    gap: 0.25rem;
    padding: 0.2rem 0.5rem;
    border-radius: 4px;
    border: 1px solid var(--vpro-error-border);
    background: var(--vpro-surface);
    color: var(--vpro-error-ink);
    font-size: 0.7rem;
    font-weight: 600;
  }
  .vpro-validation-pills {
    display: flex;
    flex-wrap: wrap;
    gap: 0.35rem;
    margin-top: 0.45rem;
  }
  .vpro-validation-pill {
    display: inline-flex;
    align-items: center;
    gap: 0.3rem;
    max-width: 100%;
    padding: 0.25rem 0.55rem;
    border-radius: 4px;
    border: 1px solid var(--vpro-error-border);
    background: var(--vpro-surface);
    color: var(--vpro-ink);
    font-size: 0.72rem;
    text-align: left;
  }
  .vpro-validation-pill:hover {
    border-color: var(--vpro-error);
    background: #fff8f8;
  }
  .vpro-validation-tab {
    font-family: var(--vpro-font-mono, monospace);
    font-size: 0.65rem;
    font-weight: 700;
    padding: 0.05rem 0.3rem;
    border-radius: 3px;
    background: var(--vpro-navy);
    color: var(--vpro-surface);
    white-space: nowrap;
  }
  .vpro-validation-field {
    font-weight: 700;
    color: var(--vpro-error-ink);
    white-space: nowrap;
  }
  .vpro-validation-msg {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    max-width: 24rem;
  }
  @media (pointer: coarse) {
    .vpro-validation-pill,
    .vpro-validation-toggle {
      min-height: 44px;
      padding: 0.45rem 0.7rem;
    }
  }
  @media print {
    .vpro-validation-bar {
      display: none !important;
    }
  }
</style>
