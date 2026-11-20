<script lang="ts">
  export interface AvailablePlotOption {
    plotNumber: string;
    fieldNumber?: string | null;
    plotRepresenting?: string | null;
    zone?: string | null;
    subZone?: string | null;
    siteSeries?: string | null;
  }

  let {
    availablePlots,
    onClosed,
    onSwitchTo6x4NewPlot,
    onSelectPlotForTwoPage,
  }: {
    availablePlots: AvailablePlotOption[];
    onClosed?: () => void;
    onSwitchTo6x4NewPlot?: () => void;
    onSelectPlotForTwoPage?: (plotNumber: string) => void;
  } = $props();

  let twoPagePickerFilter = $state('');
  const filteredTwoPagePlots = $derived.by(() => {
    const q = twoPagePickerFilter.trim().toLowerCase();
    if (!q) return availablePlots.slice(0, 50);
    return availablePlots
      .filter((p) =>
        `${p.plotNumber ?? ''} ${p.fieldNumber ?? ''} ${p.plotRepresenting ?? ''} ${p.zone ?? ''} ${p.subZone ?? ''} ${p.siteSeries ?? ''}`
          .toLowerCase()
          .includes(q)
      )
      .slice(0, 50);
  });
</script>

<div class="fs882-body overflow-y-auto flex-1 min-w-0 p-4" data-field-card-form-pane>
  <section
    aria-label="Select plot for Two-Page Entry"
    data-twopage-select-plot-prompt
    class="mx-auto my-6 max-w-2xl rounded border border-vpro-border border-t-[4px] border-t-vpro-navy bg-white p-5 shadow-sm space-y-4"
  >
    <div class="space-y-1">
      <div class="font-mono text-[11px] font-semibold uppercase tracking-wider text-vpro-forest">
        FS882-8x6XL Two-Page Layout
      </div>
      <h2 class="text-base font-bold text-vpro-navy m-0">Two-Page Entry (FS882-8x6XL) — Select a Plot</h2>
      <p class="text-xs leading-relaxed text-vpro-ink-secondary">
        Two-Page Entry edits an existing plot across side-by-side Site, Soil, and Vegetation panels. Choose a plot below
        to open Two-Page Entry immediately, or create a new plot header first.
      </p>
    </div>

    <div class="flex flex-wrap items-center gap-2">
      <input
        type="search"
        data-twopage-plot-picker-filter
        class="flex-1 min-w-48 rounded border border-vpro-border px-3 py-1.5 text-xs"
        placeholder="Filter plots by plot number, BGC unit, or location..."
        aria-label="Filter plots for Two-Page Entry"
        bind:value={twoPagePickerFilter}
      />
      {#if onClosed}
        <button
          type="button"
          class="rounded border border-vpro-navy bg-white px-3 py-1.5 text-xs font-semibold text-vpro-navy hover:bg-vpro-navy-tint"
          onclick={onClosed}
        >
          Browse Plots Table
        </button>
      {/if}
      {#if onSwitchTo6x4NewPlot}
        <button
          type="button"
          data-twopage-switch-new-plot
          class="rounded bg-vpro-forest px-3 py-1.5 text-xs font-semibold text-white hover:bg-vpro-forest-dark"
          onclick={onSwitchTo6x4NewPlot}
        >
          Create New Plot Header (FS882 6x4)
        </button>
      {/if}
    </div>

    <div class="max-h-64 overflow-y-auto rounded border border-vpro-border divide-y divide-vpro-rail">
      {#each filteredTwoPagePlots as p (p.plotNumber)}
        <button
          type="button"
          data-twopage-pick-plot={p.plotNumber}
          class="w-full flex items-center justify-between gap-3 px-3 py-2 text-left text-xs hover:bg-vpro-navy-tint"
          onclick={() => onSelectPlotForTwoPage?.(p.plotNumber)}
        >
          <span class="font-mono font-bold text-vpro-navy tabular-nums">{p.plotNumber}</span>
          <span class="truncate text-vpro-ink-secondary"
            >{[
              p.zone && p.subZone ? `${p.zone}${p.subZone}` : (p.zone ?? p.subZone),
              p.siteSeries ? `/${p.siteSeries}` : '',
              p.plotRepresenting ?? '',
            ]
              .filter(Boolean)
              .join(' ')}</span
          >
          <span class="shrink-0 rounded border border-vpro-navy px-2 py-0.5 font-semibold text-vpro-navy"
            >Open 2-Page</span
          >
        </button>
      {:else}
        <p class="p-4 text-center text-xs text-vpro-ink-muted">
          {availablePlots.length === 0
            ? 'No plots in the active scope yet. Create a new plot header first.'
            : `No plots matched "${twoPagePickerFilter.trim()}".`}
        </p>
      {/each}
    </div>
  </section>
</div>
