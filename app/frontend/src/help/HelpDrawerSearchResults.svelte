<script lang="ts">
  import type { HelpSearchHit } from './helpSystem';

  let {
    searchQuery,
    searchBusy,
    searchHits,
    onclear,
    onopenhit,
  }: {
    searchQuery: string;
    searchBusy: boolean;
    searchHits: HelpSearchHit[];
    onclear: () => void;
    onopenhit: (hit: HelpSearchHit) => void;
  } = $props();
</script>

<div class="max-h-64 overflow-y-auto border-b border-vpro-border bg-vpro-canvas p-3" data-help-search-results>
  <div class="mb-2 flex items-center justify-between text-xs text-vpro-ink-secondary">
    <span>{searchBusy ? 'Searching offline index...' : `${searchHits.length} matching reference topic(s)`}</span>
    <button type="button" class="text-xs font-medium text-vpro-navy underline" onclick={onclear}> Clear search </button>
  </div>
  {#if searchHits.length === 0 && !searchBusy}
    <p class="rounded border border-vpro-border bg-white p-2.5 text-xs text-vpro-ink-secondary">
      No offline topics matched "{searchQuery}". Try an LMH25 code (SITE 20, SOIL 5, VEG 2) or symbol (Of, Mor, rSMR).
    </p>
  {:else}
    <div class="space-y-1.5">
      {#each searchHits as hit (`${hit.kind}:${hit.id}`)}
        <button
          type="button"
          data-help-search-hit={hit.id}
          class="w-full rounded border border-vpro-border bg-white p-2 text-left hover:border-vpro-navy"
          onclick={() => onopenhit(hit)}
        >
          <div class="flex items-center justify-between gap-2">
            <span class="font-mono text-[11px] font-semibold uppercase text-vpro-navy">
              {hit.code ? `${hit.code} · ` : ''}{hit.kind}
            </span>
            {#if hit.lmh25Page}
              <span class="font-mono text-[11px] text-vpro-ink-muted">LMH25 p. {hit.lmh25Page}</span>
            {/if}
          </div>
          <div class="mt-0.5 text-xs font-semibold text-vpro-ink">{hit.title}</div>
          <p class="mt-0.5 line-clamp-2 text-[11px] text-vpro-ink-secondary">{hit.snippet}</p>
        </button>
      {/each}
    </div>
  {/if}
</div>
