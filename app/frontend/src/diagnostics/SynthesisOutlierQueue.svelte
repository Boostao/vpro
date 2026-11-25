<script lang="ts">
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import type { OutlierFilterMode, OutlierPlotCandidate, SynthesisSnapshot } from './classificationSynthesis';

  interface Props {
    snapshot: SynthesisSnapshot | null;
    visibleOutliers: OutlierPlotCandidate[];
    misplacedCount: number;
    outlierFilter: OutlierFilterMode;
    outlierSearch: string;
    manualTargetByPlot: Record<string, string>;
    mutating: boolean;
    onFilterChange: (mode: OutlierFilterMode) => void;
    onSearchChange: (value: string) => void;
    onManualTargetChange: (plotNumber: string, targetUnit: string) => void;
    onReassignPlot: (plotNumber: string, targetUnit: string) => void;
    onPlotDragStart: (ev: DragEvent, plotNumber: string) => void;
    onPlotDragEnd: () => void;
    onOpenPlot?: (plotNumber: string) => void;
  }

  let {
    snapshot,
    visibleOutliers,
    misplacedCount,
    outlierFilter,
    outlierSearch,
    manualTargetByPlot,
    mutating,
    onFilterChange,
    onSearchChange,
    onManualTargetChange,
    onReassignPlot,
    onPlotDragStart,
    onPlotDragEnd,
    onOpenPlot,
  }: Props = $props();
</script>

<aside class="syn-outlier-pane" aria-label="Candidate Misplaced Plots Queue">
  <div class="outlier-pane-hdr">
    <div>
      <h3>Candidate Misplaced Plots</h3>
      <p>
        Leave-One-Out centroid similarity · {misplacedCount} misplaced of{' '}
        {snapshot?.outlierQueue.length ?? 0}
      </p>
    </div>
  </div>

  <div class="outlier-filter-bar">
    <div class="outlier-pills">
      <button
        type="button"
        class="syn-pill-btn"
        class:active={outlierFilter === 'all'}
        onclick={() => onFilterChange('all')}
      >
        All ({snapshot?.outlierQueue.length ?? 0})
      </button>
      <button
        type="button"
        class="syn-pill-btn"
        class:active={outlierFilter === 'misplaced'}
        onclick={() => onFilterChange('misplaced')}
      >
        Misplaced ({misplacedCount})
      </button>
      <button
        type="button"
        class="syn-pill-btn"
        class:active={outlierFilter === 'top5'}
        onclick={() => onFilterChange('top5')}
      >
        Top 5%
      </button>
    </div>
    <input
      type="search"
      aria-label="Search candidate outlier plots or units"
      class="outlier-search"
      placeholder="Search plot or unit..."
      value={outlierSearch}
      oninput={(e) => onSearchChange((e.currentTarget as HTMLInputElement).value)}
    />
  </div>

  <div class="outlier-list">
    {#if visibleOutliers.length === 0}
      <div class="syn-empty-small">No plots match the selected outlier filter.</div>
    {:else}
      {#each visibleOutliers as cand (cand.plotNumber)}
        {@const chosenUnit = manualTargetByPlot[cand.plotNumber] || cand.nearestRivalUnit || ''}
        <article
          class="outlier-card"
          class:is-misplaced={cand.misplaced}
          class:is-top5={cand.top5PercentAnomaly}
          draggable={!IS_WEB_READONLY && Boolean(snapshot?.suWritable)}
          ondragstart={(ev) => onPlotDragStart(ev, cand.plotNumber)}
          ondragend={onPlotDragEnd}
        >
          <div class="outlier-card-top">
            <div class="outlier-id-group">
              <span class="outlier-rank">#{cand.rank}</span>
              <button
                type="button"
                class="outlier-plot-link"
                title={`Open plot ${cand.plotNumber}`}
                onclick={() => onOpenPlot?.(cand.plotNumber)}
              >
                {cand.plotNumber}
              </button>
              {#if cand.moistureRegime || cand.nutrientRegime}
                <span class="outlier-eda-tag">
                  {cand.moistureRegime || '?'}{cand.nutrientRegime || '?'}
                </span>
              {/if}
            </div>

            {#if cand.misplaced}
              <span class="outlier-flag flag-misplaced">Rival Closer (+{cand.deltaSimilarityPct.toFixed(1)}%)</span>
            {:else if cand.singletonUnit}
              <span class="outlier-flag flag-singleton">Singleton Unit</span>
            {:else if cand.top5PercentAnomaly}
              <span class="outlier-flag flag-top5">Top 5%</span>
            {/if}
          </div>

          <div class="outlier-metrics">
            <div>
              <span class="metric-lbl">Assigned:</span>
              <strong>{cand.assignedUnit}</strong>
              <span>({cand.ownSimilarityPct.toFixed(1)}% LOO)</span>
            </div>
            {#if cand.nearestRivalUnit}
              <div>
                <span class="metric-lbl">Nearest Rival:</span>
                <strong>{cand.nearestRivalUnit}</strong>
                <span>({cand.rivalSimilarityPct.toFixed(1)}%)</span>
              </div>
            {/if}
          </div>

          {#if !IS_WEB_READONLY && snapshot && snapshot.units.length > 1}
            <div class="outlier-actions">
              {#if cand.nearestRivalUnit}
                <button
                  type="button"
                  class="syn-btn-reassign"
                  disabled={!snapshot.suWritable || mutating}
                  onclick={() => onReassignPlot(cand.plotNumber, cand.nearestRivalUnit)}
                >
                  Move to {cand.nearestRivalUnit}
                </button>
              {/if}

              <select
                aria-label={`Select target unit for plot ${cand.plotNumber}`}
                value={chosenUnit}
                disabled={!snapshot.suWritable || mutating}
                onchange={(e) => {
                  const val = (e.currentTarget as HTMLSelectElement).value;
                  onManualTargetChange(cand.plotNumber, val);
                  if (val && val !== cand.assignedUnit) {
                    onReassignPlot(cand.plotNumber, val);
                  }
                }}
              >
                <option value="">Assign unit...</option>
                {#each snapshot.units as u (u.siteUnit)}
                  {#if u.siteUnit !== cand.assignedUnit}
                    <option value={u.siteUnit}>{u.siteUnit}</option>
                  {/if}
                {/each}
              </select>
            </div>
          {/if}
        </article>
      {/each}
    {/if}
  </div>
</aside>
