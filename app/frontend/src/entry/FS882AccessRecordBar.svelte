<script lang="ts">
  import { ChevronLeft, ChevronRight, ChevronsLeft, ChevronsRight, Plus, Search } from '@lucide/svelte';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import {
    CLASSIC_CARD_OPTIONS,
    CLASSIC_LAYOUT_MODES,
    formatRecordJumpInput,
    type ClassicCardId,
    type ClassicLayoutMode,
  } from './classicFS882Helpers';

  let {
    currentIndex,
    totalCount,
    isNewPlot = false,
    locked = false,
    busy = false,
    unsaved = false,
    layoutMode = 'single',
    leftCard = 'site',
    rightCard = 'soils',
    showLayoutSwitcher = true,
    searchFeedback = null,
    onFirst,
    onPrev,
    onNext,
    onLast,
    onJumpToRecord,
    onNewPlot,
    onSearchPlot,
    onLayoutModeChange,
    onLeftCardChange,
    onRightCardChange,
  }: {
    currentIndex: number;
    totalCount: number;
    isNewPlot?: boolean;
    locked?: boolean;
    busy?: boolean;
    unsaved?: boolean;
    layoutMode?: ClassicLayoutMode;
    leftCard?: ClassicCardId;
    rightCard?: ClassicCardId;
    showLayoutSwitcher?: boolean;
    searchFeedback?: string | null;
    onFirst: () => void;
    onPrev: () => void;
    onNext: () => void;
    onLast: () => void;
    onJumpToRecord: (oneBasedIndex: number) => void;
    onNewPlot?: () => void;
    onSearchPlot: (plotQuery: string) => void;
    onLayoutModeChange?: (mode: ClassicLayoutMode) => void;
    onLeftCardChange?: (card: ClassicCardId) => void;
    onRightCardChange?: (card: ClassicCardId) => void;
  } = $props();

  let indexInput = $state('');
  let searchQuery = $state('');
  let localError = $state<string | null>(null);

  $effect(() => {
    indexInput = isNewPlot ? '' : currentIndex > 0 ? String(currentIndex) : '';
    localError = null;
  });

  const navDisabled = $derived(busy || totalCount <= 0);
  const atFirst = $derived(navDisabled || (!isNewPlot && currentIndex <= 1));
  const atLast = $derived(navDisabled || (!isNewPlot && currentIndex >= totalCount));
  const newDisabled = $derived(IS_WEB_READONLY || locked || busy || unsaved || !onNewPlot);

  function commitIndexJump() {
    if (navDisabled) return;
    const parsed = formatRecordJumpInput(indexInput, totalCount);
    if (parsed.error !== null || parsed.index === null) {
      localError = parsed.error;
      return;
    }
    localError = null;
    onJumpToRecord(parsed.index);
  }

  function handleIndexKeydown(event: KeyboardEvent) {
    if (event.key === 'Enter') {
      event.preventDefault();
      commitIndexJump();
    } else if (event.key === 'Escape') {
      localError = null;
      indexInput = isNewPlot ? '' : currentIndex > 0 ? String(currentIndex) : '';
    }
  }

  function submitSearch(event: SubmitEvent) {
    event.preventDefault();
    if (busy) return;
    localError = null;
    onSearchPlot(searchQuery);
  }
</script>

<div
  class="classic-record-bar sticky top-0 z-20 flex flex-wrap items-center justify-between gap-2 px-2.5 py-1.5 bg-vpro-navy text-white border-b-2 border-vpro-gold text-xs"
  data-access-record-bar
  role="region"
  aria-label="Plot record navigator and form layout"
>
  <div class="flex flex-wrap items-center gap-1">
    <span class="font-semibold text-[11px] uppercase tracking-wider text-vpro-gold mr-1">Record</span>
    <div class="inline-flex items-center rounded border border-white/30 bg-white/10 overflow-hidden">
      <button
        type="button"
        data-record-nav="first"
        class="px-1.5 py-1 hover:bg-white/20 disabled:opacity-40"
        disabled={atFirst}
        title="First record"
        aria-label="First record"
        onclick={onFirst}
      >
        <ChevronsLeft size={14} aria-hidden="true" />
      </button>
      <button
        type="button"
        data-record-nav="prev"
        class="px-1.5 py-1 border-l border-white/20 hover:bg-white/20 disabled:opacity-40"
        disabled={atFirst}
        title="Previous record"
        aria-label="Previous record"
        onclick={onPrev}
      >
        <ChevronLeft size={14} aria-hidden="true" />
      </button>
      <label class="inline-flex items-center gap-1 px-1.5 py-0.5 border-l border-white/20 bg-white/10">
        <span class="sr-only">Record number</span>
        <input
          type="text"
          inputmode="numeric"
          data-record-index-input
          class="w-14 px-1 py-0.5 rounded bg-white text-vpro-ink font-mono text-xs text-center font-semibold disabled:opacity-60"
          value={indexInput}
          placeholder={isNewPlot ? 'New' : '—'}
          disabled={navDisabled}
          aria-label="Current record number"
          oninput={(e) => {
            indexInput = e.currentTarget.value;
            localError = null;
          }}
          onkeydown={handleIndexKeydown}
          onblur={() => {
            if (!localError) {
              indexInput = isNewPlot ? '' : currentIndex > 0 ? String(currentIndex) : '';
            }
          }}
        />
        <span class="text-[11px] text-white/90 font-mono whitespace-nowrap" data-record-total>
          of {totalCount.toLocaleString()}
        </span>
      </label>
      <button
        type="button"
        data-record-nav="next"
        class="px-1.5 py-1 border-l border-white/20 hover:bg-white/20 disabled:opacity-40"
        disabled={atLast}
        title="Next record"
        aria-label="Next record"
        onclick={onNext}
      >
        <ChevronRight size={14} aria-hidden="true" />
      </button>
      <button
        type="button"
        data-record-nav="last"
        class="px-1.5 py-1 border-l border-white/20 hover:bg-white/20 disabled:opacity-40"
        disabled={atLast}
        title="Last record"
        aria-label="Last record"
        onclick={onLast}
      >
        <ChevronsRight size={14} aria-hidden="true" />
      </button>
    </div>

    {#if !IS_WEB_READONLY}
      <button
        type="button"
        data-record-nav="new"
        class="inline-flex items-center gap-1 px-2 py-1 rounded border border-vpro-gold bg-vpro-gold text-vpro-ink font-semibold text-[11px] hover:brightness-95 disabled:opacity-45"
        disabled={newDisabled}
        title={locked ? 'Sign in to create a new plot' : 'Create new plot record'}
        onclick={() => onNewPlot?.()}
      >
        <Plus size={13} aria-hidden="true" /> New
      </button>
    {/if}

    <form class="inline-flex items-center gap-1 ml-1" onsubmit={submitSearch} role="search" aria-label="Search PlotNumber">
      <div class="relative inline-flex items-center">
        <Search size={12} class="absolute left-1.5 text-vpro-ink-muted pointer-events-none" aria-hidden="true" />
        <input
          type="text"
          data-record-search-input
          class="pl-6 pr-2 py-0.5 w-36 rounded bg-white text-vpro-ink font-mono text-xs placeholder:text-vpro-ink-muted"
          placeholder="PlotNumber (00337)"
          aria-label="Search PlotNumber"
          value={searchQuery}
          disabled={busy}
          oninput={(e) => {
            searchQuery = e.currentTarget.value;
            localError = null;
          }}
        />
      </div>
      <button
        type="submit"
        data-record-search-submit
        class="px-2 py-0.5 rounded border border-white/35 bg-white/15 hover:bg-white/25 text-white font-semibold text-[11px] disabled:opacity-45"
        disabled={busy || !searchQuery.trim()}
      >
        Go
      </button>
    </form>

    {#if localError || searchFeedback}
      <span class="px-2 py-0.5 rounded bg-red-100 text-red-900 text-[11px] font-medium" role="status" data-record-feedback>
        {localError ?? searchFeedback}
      </span>
    {/if}
  </div>

  {#if showLayoutSwitcher}
    <div class="flex flex-wrap items-center gap-1.5">
      <div
        class="inline-flex rounded border border-white/30 overflow-hidden"
        role="group"
        aria-label="Form display mode"
        data-layout-switcher
      >
        {#each CLASSIC_LAYOUT_MODES as mode (mode.id)}
          <button
            type="button"
            data-layout-mode={mode.id}
            aria-pressed={layoutMode === mode.id}
            title={mode.title}
            class="px-2 py-1 text-[11px] font-semibold border-r border-white/20 last:border-r-0 {layoutMode === mode.id
              ? 'bg-white text-vpro-navy'
              : 'bg-white/10 text-white/90 hover:bg-white/20'}"
            onclick={() => onLayoutModeChange?.(mode.id)}
          >
            {mode.label}
          </button>
        {/each}
      </div>

      {#if layoutMode === 'side-by-side'}
        <div class="inline-flex items-center gap-1 text-[11px]" data-side-by-side-pickers>
          <label class="inline-flex items-center gap-1">
            <span class="text-white/80">L:</span>
            <select
              data-split-left-select
              aria-label="Left card"
              class="rounded bg-white text-vpro-ink px-1.5 py-0.5 text-[11px] font-medium"
              value={leftCard}
              onchange={(e) => onLeftCardChange?.(e.currentTarget.value as ClassicCardId)}
            >
              {#each CLASSIC_CARD_OPTIONS as opt (opt.id)}
                <option value={opt.id}>{opt.shortLabel}</option>
              {/each}
            </select>
          </label>
          <label class="inline-flex items-center gap-1">
            <span class="text-white/80">R:</span>
            <select
              data-split-right-select
              aria-label="Right card"
              class="rounded bg-white text-vpro-ink px-1.5 py-0.5 text-[11px] font-medium"
              value={rightCard}
              onchange={(e) => onRightCardChange?.(e.currentTarget.value as ClassicCardId)}
            >
              {#each CLASSIC_CARD_OPTIONS as opt (opt.id)}
                <option value={opt.id}>{opt.shortLabel}</option>
              {/each}
            </select>
          </label>
        </div>
      {/if}
    </div>
  {/if}
</div>
