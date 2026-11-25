<script lang="ts">
  import { Plus, Trash2 } from '@lucide/svelte';
  import type { VegRecord } from '../../bindings/github.com/boostao/vpro/app';
  import { IS_WEB_READONLY } from '../web/runtimeMode';

  let {
    vegList,
    totalTreeCover,
    totalShrubCover,
    totalHerbCover,
    totalMossCover,
    onopenspeciesmodal,
    ondeleteveg,
  }: {
    vegList: VegRecord[];
    totalTreeCover: number | null;
    totalShrubCover: number | null;
    totalHerbCover: number | null;
    totalMossCover: number | null;
    onopenspeciesmodal: () => void;
    ondeleteveg: (id: number) => Promise<void>;
  } = $props();

  function rowTreeCover(row: VegRecord): number | null {
    if (row.totalA != null) return row.totalA;
    if (row.cover1 != null || row.cover2 != null || row.cover3 != null) {
      return Math.min(99, (row.cover1 ?? 0) + (row.cover2 ?? 0) + (row.cover3 ?? 0));
    }
    return null;
  }

  function rowShrubCover(row: VegRecord): number | null {
    if (row.totalB != null) return row.totalB;
    if (row.cover4 != null || row.cover5 != null || row.cover5a != null || row.cover5b != null || row.cover5c != null) {
      return Math.min(
        99,
        (row.cover4 ?? 0) + (row.cover5 ?? 0) + (row.cover5a ?? 0) + (row.cover5b ?? 0) + (row.cover5c ?? 0)
      );
    }
    return null;
  }

  const effectiveTreeCover = $derived(
    totalTreeCover === null
      ? null
      : vegList.length > 0
        ? Math.min(
            99,
            vegList.reduce((sum, r) => sum + Math.min(99, rowTreeCover(r) ?? 0), 0)
          )
        : Math.min(99, totalTreeCover)
  );
  const effectiveShrubCover = $derived(
    totalShrubCover === null
      ? null
      : vegList.length > 0
        ? Math.min(
            99,
            vegList.reduce((sum, r) => sum + Math.min(99, rowShrubCover(r) ?? 0), 0)
          )
        : Math.min(99, totalShrubCover)
  );
  const effectiveHerbCover = $derived(
    totalHerbCover === null
      ? null
      : vegList.length > 0
        ? Math.min(
            99,
            vegList.reduce((sum, r) => sum + Math.min(99, r.cover6 ?? 0), 0)
          )
        : Math.min(99, totalHerbCover)
  );
  const effectiveMossCover = $derived(
    totalMossCover === null
      ? null
      : vegList.length > 0
        ? Math.min(
            99,
            vegList.reduce((sum, r) => sum + Math.min(99, r.cover7 ?? 0), 0)
          )
        : Math.min(99, totalMossCover)
  );
</script>

<details class="mt-4 border border-vpro-border rounded p-3">
  <summary class="text-xs font-semibold cursor-pointer">Vegetation record preview (read-only)</summary>
  <div class="space-y-4">
    <!-- Live Stratum Cover Summaries -->
    <div
      class="grid grid-cols-4 gap-3 bg-vpro-surface-subtle border border-vpro-border rounded p-3 text-xs"
      data-stratum-cover-summaries
    >
      <div class="flex flex-col">
        <span class="text-vpro-ink-muted font-medium">Tree Layer (A)</span>
        <span class="font-bold text-vpro-ink text-sm" data-stratum-total="A"
          >{effectiveTreeCover === null ? 'unavailable' : `${effectiveTreeCover.toFixed(1)}%`}</span
        >
      </div>
      <div class="flex flex-col">
        <span class="text-vpro-ink-muted font-medium">Shrub Layer (B)</span>
        <span class="font-bold text-vpro-ink text-sm" data-stratum-total="B"
          >{effectiveShrubCover === null ? 'unavailable' : `${effectiveShrubCover.toFixed(1)}%`}</span
        >
      </div>
      <div class="flex flex-col">
        <span class="text-vpro-ink-muted font-medium">Herb Layer (C)</span>
        <span class="font-bold text-vpro-ink text-sm" data-stratum-total="C"
          >{effectiveHerbCover === null ? 'unavailable' : `${effectiveHerbCover.toFixed(1)}%`}</span
        >
      </div>
      <div class="flex flex-col">
        <span class="text-vpro-ink-muted font-medium">Moss/Lichen (D)</span>
        <span class="font-bold text-vpro-ink text-sm" data-stratum-total="D"
          >{effectiveMossCover === null ? 'unavailable' : `${effectiveMossCover.toFixed(1)}%`}</span
        >
      </div>
    </div>

    <div class="flex flex-wrap justify-between items-center gap-2">
      <h3 class="font-bold text-xs uppercase tracking-wider text-vpro-navy">Vegetation Entries ({vegList.length})</h3>
      {#if !IS_WEB_READONLY}
        <button
          type="button"
          onclick={onopenspeciesmodal}
          disabled
          class="px-2.5 py-1 bg-vpro-navy hover:bg-vpro-navy-dark text-white rounded text-xs flex items-center gap-1"
        >
          <Plus size={14} /> Add Species (BC Catalog)
        </button>
      {/if}
    </div>

    <div class="table-scroll border border-vpro-border rounded overflow-x-auto bg-white">
      <table class="w-full text-left text-xs">
        <thead class="bg-vpro-canvas border-b border-vpro-border text-vpro-navy font-semibold">
          <tr>
            <th class="p-2">Species</th>
            <th class="p-2">Layer</th>
            <th class="p-2">Cover 1</th>
            <th class="p-2">Cover 2</th>
            <th class="p-2">Total A</th>
            <th class="p-2">Cover 4</th>
            <th class="p-2">Cover 5</th>
            <th class="p-2">Total B</th>
            <th class="p-2">Cover 6</th>
            <th class="p-2">Cover 7</th>
            <th class="p-2">Action</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-vpro-canvas">
          {#each vegList as row (row.id)}
            {@const dispTotalA = rowTreeCover(row)}
            {@const dispTotalB = rowShrubCover(row)}
            <tr class="hover:bg-vpro-canvas">
              <td class="p-2 font-mono font-bold text-vpro-navy">{row.species}</td>
              <td class="p-2"
                ><input
                  type="text"
                  aria-label={`Layer for ${row.species}`}
                  value={row.layer ?? ''}
                  disabled
                  class="w-10 border border-vpro-border rounded px-1 py-0.5 text-xs text-center"
                /></td
              >
              <td class="p-2"
                ><input
                  type="number"
                  step="0.1"
                  aria-label={`Cover 1 for ${row.species}`}
                  value={row.cover1 ?? ''}
                  disabled
                  class="w-14 border border-vpro-border rounded px-1 py-0.5 text-xs text-right"
                /></td
              >
              <td class="p-2"
                ><input
                  type="number"
                  step="0.1"
                  aria-label={`Cover 2 for ${row.species}`}
                  value={row.cover2 ?? ''}
                  disabled
                  class="w-14 border border-vpro-border rounded px-1 py-0.5 text-xs text-right"
                /></td
              >
              <td class="p-2 font-bold text-vpro-ink text-right">{dispTotalA !== null ? dispTotalA.toFixed(1) : '—'}</td
              >
              <td class="p-2"
                ><input
                  type="number"
                  step="0.1"
                  aria-label={`Cover 4 for ${row.species}`}
                  value={row.cover4 ?? ''}
                  disabled
                  class="w-14 border border-vpro-border rounded px-1 py-0.5 text-xs text-right"
                /></td
              >
              <td class="p-2"
                ><input
                  type="number"
                  step="0.1"
                  aria-label={`Cover 5 for ${row.species}`}
                  value={row.cover5 ?? ''}
                  disabled
                  class="w-14 border border-vpro-border rounded px-1 py-0.5 text-xs text-right"
                /></td
              >
              <td class="p-2 font-bold text-vpro-ink text-right">{dispTotalB !== null ? dispTotalB.toFixed(1) : '—'}</td
              >
              <td class="p-2"
                ><input
                  type="number"
                  step="0.1"
                  aria-label={`Cover 6 for ${row.species}`}
                  value={row.cover6 ?? ''}
                  disabled
                  class="w-14 border border-vpro-border rounded px-1 py-0.5 text-xs text-right"
                /></td
              >
              <td class="p-2"
                ><input
                  type="number"
                  step="0.1"
                  aria-label={`Cover 7 for ${row.species}`}
                  value={row.cover7 ?? ''}
                  disabled
                  class="w-14 border border-vpro-border rounded px-1 py-0.5 text-xs text-right"
                /></td
              >
              <td class="p-2">
                <button
                  type="button"
                  onclick={() => void ondeleteveg(row.id)}
                  disabled
                  class="text-red-600 hover:text-red-800 p-1"
                  title="Delete entry"
                >
                  <Trash2 size={14} />
                </button>
              </td>
            </tr>
          {:else}
            <tr>
              <td colspan="11" class="p-4 text-center text-vpro-ink-muted">No vegetation records for this plot.</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  </div>
</details>
