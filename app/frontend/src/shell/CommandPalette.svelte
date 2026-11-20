<script lang="ts">
  import { CornerDownLeft, Search, X } from '@lucide/svelte';
  import ModalDialogTrap from '../shared/ModalDialogTrap.svelte';
  import {
    buildCommandPaletteCatalog,
    searchCommandPalette,
    type BuildCommandPaletteInput,
    type CommandPaletteAction,
    type CommandPaletteItem,
  } from './commandPalette';

  let {
    open = false,
    catalogInput,
    onselect,
    onclose,
  }: {
    open?: boolean;
    catalogInput: BuildCommandPaletteInput;
    onselect: (action: CommandPaletteAction) => void;
    onclose: () => void;
  } = $props();

  let query = $state('');
  let activeIndex = $state(0);
  let searchInput: HTMLInputElement | undefined = $state();
  let previousFocus: HTMLElement | null = null;

  const catalog = $derived(buildCommandPaletteCatalog(catalogInput));
  const results = $derived(searchCommandPalette(catalog, query, 30));

  const groupedResults = $derived.by(() => {
    const groups: Array<{ label: string; entries: Array<{ item: CommandPaletteItem; flatIndex: number }> }> = [];
    const byLabel = new Map<string, Array<{ item: CommandPaletteItem; flatIndex: number }>>();
    results.forEach((item, flatIndex) => {
      let bucket = byLabel.get(item.categoryLabel);
      if (!bucket) {
        bucket = [];
        byLabel.set(item.categoryLabel, bucket);
        groups.push({ label: item.categoryLabel, entries: bucket });
      }
      bucket.push({ item, flatIndex });
    });
    return groups;
  });

  $effect(() => {
    if (open) {
      if (typeof document !== 'undefined' && document.activeElement instanceof HTMLElement) {
        previousFocus = document.activeElement;
      }
      query = '';
      activeIndex = 0;
      queueMicrotask(() => {
        searchInput?.focus();
      });
    } else if (previousFocus) {
      const target = previousFocus;
      previousFocus = null;
      queueMicrotask(() => {
        if (target.isConnected) target.focus();
      });
    }
  });

  function clampIndex(idx: number) {
    if (results.length === 0) return 0;
    return ((idx % results.length) + results.length) % results.length;
  }

  function triggerItem(item: CommandPaletteItem | undefined) {
    if (!item || item.disabled) return;
    onclose();
    onselect(item.action);
  }

  function handleWindowKeydown(event: KeyboardEvent) {
    if (!open) return;
    if (event.key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      onclose();
      return;
    }
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      activeIndex = clampIndex(activeIndex + 1);
      return;
    }
    if (event.key === 'ArrowUp') {
      event.preventDefault();
      activeIndex = clampIndex(activeIndex - 1);
      return;
    }
    if (event.key === 'Enter') {
      const candidate = results[activeIndex];
      if (candidate && !candidate.disabled) {
        event.preventDefault();
        event.stopPropagation();
        triggerItem(candidate);
      }
    }
  }
</script>

<svelte:window onkeydowncapture={handleWindowKeydown} />

{#if open}
  <div
    class="vpro-cmd-backdrop"
    role="presentation"
    data-command-palette-backdrop
    onclick={(e) => {
      if (e.target === e.currentTarget) onclose();
    }}
  >
    <div
      class="vpro-cmd-dialog"
      role="dialog"
      aria-modal="true"
      aria-label="VPro Quick-Jump Command Palette"
      data-command-palette
    >
      <ModalDialogTrap trapFocus={true} initialFocusSelector="[data-command-palette-input]" />
      <div class="vpro-cmd-search-row">
        <Search size={17} class="shrink-0 text-vpro-navy" />
        <input
          bind:this={searchInput}
          type="search"
          class="vpro-cmd-input"
          placeholder="Jump to plot (e.g. 00337), project, Site Unit, form, report, or LMH25 topic..."
          aria-label="Search plots, projects, tools, and LMH25 help"
          data-command-palette-input
          value={query}
          oninput={(e) => {
            query = e.currentTarget.value;
            activeIndex = 0;
          }}
        />
        <kbd class="vpro-cmd-esc-hint">Esc</kbd>
        <button
          type="button"
          class="vpro-cmd-close"
          aria-label="Close Command Palette"
          data-command-palette-close
          onclick={onclose}
        >
          <X size={15} />
        </button>
      </div>

      <div class="vpro-cmd-results" role="listbox" aria-label="Matching commands and records">
        {#if results.length === 0}
          <div class="vpro-cmd-empty">
            No matching plots, views, projects, or LMH25 topics for <strong>"{query}"</strong>.
          </div>
        {:else}
          {#each groupedResults as group (group.label)}
            <div class="vpro-cmd-group">
              <div class="vpro-cmd-group-title">{group.label}</div>
              {#each group.entries as entry (entry.item.id)}
                <button
                  type="button"
                  role="option"
                  aria-selected={activeIndex === entry.flatIndex}
                  disabled={entry.item.disabled}
                  class="vpro-cmd-item"
                  class:selected={activeIndex === entry.flatIndex}
                  data-command-item={entry.item.id}
                  onmouseenter={() => (activeIndex = entry.flatIndex)}
                  onclick={() => triggerItem(entry.item)}
                >
                  <div class="vpro-cmd-item-main">
                    <div class="vpro-cmd-item-title-row">
                      <span class="vpro-cmd-item-title">{entry.item.title}</span>
                      {#if entry.item.badge}
                        <span class="vpro-cmd-badge">{entry.item.badge}</span>
                      {/if}
                    </div>
                    <div class="vpro-cmd-item-sub">
                      {entry.item.disabled && entry.item.disabledReason
                        ? entry.item.disabledReason
                        : entry.item.subtitle}
                    </div>
                  </div>
                  <div class="vpro-cmd-item-right">
                    {#if entry.item.shortcut}
                      <kbd>{entry.item.shortcut}</kbd>
                    {:else if activeIndex === entry.flatIndex && !entry.item.disabled}
                      <CornerDownLeft size={13} class="text-vpro-navy" />
                    {/if}
                  </div>
                </button>
              {/each}
            </div>
          {/each}
        {/if}
      </div>

      <footer class="vpro-cmd-footer">
        <span><kbd>↑</kbd><kbd>↓</kbd> Navigate</span>
        <span><kbd>Enter</kbd> Open</span>
        <span><kbd>Esc</kbd> Dismiss</span>
      </footer>
    </div>
  </div>
{/if}

<style>
  .vpro-cmd-backdrop {
    position: fixed;
    inset: 0;
    z-index: 80;
    background: rgba(0, 22, 46, 0.45);
    display: flex;
    align-items: flex-start;
    justify-content: center;
    padding: clamp(0.75rem, 7vh, 4.5rem) 0.75rem 1rem;
  }
  .vpro-cmd-dialog {
    width: min(40rem, 100%);
    max-height: min(34rem, calc(100dvh - 2rem));
    background: var(--vpro-surface);
    border: 1px solid var(--vpro-border-strong);
    border-top: 4px solid var(--vpro-navy);
    border-radius: var(--vpro-radius-lg, 8px);
    box-shadow: var(--vpro-shadow-lg, 0 18px 42px rgba(0, 34, 68, 0.28));
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }
  .vpro-cmd-search-row {
    display: flex;
    align-items: center;
    gap: 0.6rem;
    padding: 0.7rem 0.85rem;
    border-bottom: 1px solid var(--vpro-border);
    background: var(--vpro-surface-subtle);
  }
  .vpro-cmd-input {
    flex: 1;
    min-width: 0;
    border: 0;
    background: transparent;
    color: var(--vpro-ink);
    font: inherit;
    font-size: 0.9rem;
    outline: none;
  }
  .vpro-cmd-esc-hint {
    font-family: var(--vpro-font-mono, monospace);
    font-size: 0.68rem;
    padding: 0.12rem 0.38rem;
    border-radius: 4px;
    border: 1px solid var(--vpro-border);
    background: var(--vpro-surface);
    color: var(--vpro-ink-muted);
  }
  .vpro-cmd-close {
    display: inline-grid;
    place-items: center;
    width: 1.85rem;
    height: 1.85rem;
    border-radius: 4px;
    border: 1px solid transparent;
    background: transparent;
    color: var(--vpro-ink-secondary);
  }
  .vpro-cmd-close:hover {
    background: rgba(0, 51, 102, 0.08);
  }
  .vpro-cmd-results {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    padding: 0.45rem;
  }
  .vpro-cmd-empty {
    padding: 2rem 1rem;
    text-align: center;
    color: var(--vpro-ink-secondary);
    font-size: 0.82rem;
  }
  .vpro-cmd-group + .vpro-cmd-group {
    margin-top: 0.4rem;
    padding-top: 0.35rem;
    border-top: 1px solid var(--vpro-rail);
  }
  .vpro-cmd-group-title {
    padding: 0.2rem 0.55rem;
    font-size: 0.68rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--vpro-navy);
  }
  .vpro-cmd-item {
    width: 100%;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.65rem;
    padding: 0.48rem 0.6rem;
    border: 0;
    border-radius: 5px;
    background: transparent;
    text-align: left;
    color: var(--vpro-ink);
  }
  .vpro-cmd-item.selected,
  .vpro-cmd-item:hover:not(:disabled) {
    background: var(--vpro-navy-tint);
  }
  .vpro-cmd-item:disabled {
    opacity: 0.52;
  }
  .vpro-cmd-item-main {
    min-width: 0;
    flex: 1;
  }
  .vpro-cmd-item-title-row {
    display: flex;
    align-items: center;
    gap: 0.45rem;
    flex-wrap: wrap;
  }
  .vpro-cmd-item-title {
    font-size: 0.82rem;
    font-weight: 600;
    color: var(--vpro-ink);
  }
  .vpro-cmd-badge {
    font-family: var(--vpro-font-mono, monospace);
    font-size: 0.65rem;
    font-weight: 600;
    padding: 0.05rem 0.35rem;
    border-radius: 3px;
    background: var(--vpro-forest-surface);
    color: var(--vpro-forest);
  }
  .vpro-cmd-item-sub {
    font-size: 0.72rem;
    color: var(--vpro-ink-secondary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .vpro-cmd-item-right kbd {
    font-family: var(--vpro-font-mono, monospace);
    font-size: 0.68rem;
    padding: 0.1rem 0.35rem;
    border-radius: 3px;
    border: 1px solid var(--vpro-border);
    background: var(--vpro-surface);
  }
  .vpro-cmd-footer {
    display: flex;
    flex-wrap: wrap;
    gap: 0.85rem;
    padding: 0.45rem 0.85rem;
    border-top: 1px solid var(--vpro-border);
    background: var(--vpro-surface-subtle);
    font-size: 0.7rem;
    color: var(--vpro-ink-secondary);
  }
  .vpro-cmd-footer kbd {
    font-family: var(--vpro-font-mono, monospace);
    font-size: 0.65rem;
    padding: 0.05rem 0.3rem;
    margin-right: 0.2rem;
    border-radius: 3px;
    border: 1px solid var(--vpro-border);
    background: var(--vpro-surface);
  }
  @media (pointer: coarse) {
    .vpro-cmd-item {
      min-height: 44px;
    }
    .vpro-cmd-close {
      min-width: 44px;
      min-height: 44px;
    }
  }
  @media print {
    .vpro-cmd-backdrop {
      display: none !important;
    }
  }
</style>
