<script lang="ts">
  import type { PairwiseUnitComparison, SynthesisSnapshot } from './classificationSynthesis';

  interface Props {
    snapshot: SynthesisSnapshot | null;
    similarityMetric: 'sorensen' | 'bec_diff';
    selectedPairUnits: [string, string];
    activePairComparison: PairwiseUnitComparison | null;
    onMetricChange: (metric: 'sorensen' | 'bec_diff') => void;
    onSelectPair: (pair: [string, string]) => void;
  }

  let {
    snapshot,
    similarityMetric,
    selectedPairUnits,
    activePairComparison,
    onMetricChange,
    onSelectPair,
  }: Props = $props();
</script>

<div class="syn-similarity-pane">
  {#if !snapshot || snapshot.similarityMatrix.length === 0}
    <div class="syn-empty">Need at least one classified Site Unit for similarity analysis.</div>
  {:else}
    <div class="syn-subbar">
      <span class="syn-subbar-label">Similarity Metric:</span>
      <button
        type="button"
        class="syn-pill-btn"
        class:active={similarityMetric === 'sorensen'}
        onclick={() => onMetricChange('sorensen')}
      >
        Sorensen / Diagnostic10 (2*min / sum)
      </button>
      <button
        type="button"
        class="syn-pill-btn"
        class:active={similarityMetric === 'bec_diff'}
        onclick={() => onMetricChange('bec_diff')}
      >
        BEC Differential Similarity (BEC.sim.mean)
      </button>
    </div>

    <div class="syn-table-container">
      <table class="syn-sim-table">
        <thead>
          <tr>
            <th>Site Unit</th>
            {#each snapshot.units as u (u.siteUnit)}
              <th>{u.siteUnit}</th>
            {/each}
          </tr>
        </thead>
        <tbody>
          {#each snapshot.similarityMatrix as row, rIdx (row.unit)}
            <tr>
              <th class="sim-row-hdr">{row.unit}</th>
              {#each row.cells as cell, cIdx (cell.unit)}
                {@const pct =
                  similarityMetric === 'sorensen' ? cell.similarityPct : cell.becSimMeanPct}
                <td
                  class="sim-cell"
                  class:sim-diag={rIdx === cIdx}
                  class:sim-high={rIdx !== cIdx && pct >= 70}
                  class:sim-med={rIdx !== cIdx && pct >= 50 && pct < 70}
                  class:sim-selected={
                    (selectedPairUnits[0] === row.unit &&
                      selectedPairUnits[1] === cell.unit) ||
                    (selectedPairUnits[1] === row.unit &&
                      selectedPairUnits[0] === cell.unit)
                  }
                  onclick={() => {
                    if (row.unit !== cell.unit) {
                      onSelectPair([row.unit, cell.unit]);
                    }
                  }}
                >
                  {pct.toFixed(1)}%
                </td>
              {/each}
            </tr>
          {/each}
        </tbody>
      </table>
    </div>

    {#if activePairComparison}
      <div class="syn-pair-detail">
        <div class="syn-pair-detail-hdr">
          <strong>
            Pairwise Differential Breakdown: {activePairComparison.unit1} (n={activePairComparison.plotsUnit1})
            vs {activePairComparison.unit2} (n={activePairComparison.plotsUnit2})
          </strong>
          <span>
            Sorensen: {activePairComparison.sorensenPct.toFixed(1)}% · BEC.sim.mean:{' '}
            {(activePairComparison.becSimMean * 100).toFixed(1)}% · Shared Diag Pot:{' '}
            {activePairComparison.sharedDiagPotential.toFixed(1)}
          </span>
        </div>
        {#if activePairComparison.differentialTaxa.length === 0}
          <p class="syn-muted">No species exceed BEC pairwise differential thresholds between these two units.</p>
        {:else}
          <table class="syn-pair-taxa-table">
            <thead>
              <tr>
                <th>Species</th>
                <th>Scientific Name</th>
                <th>{activePairComparison.unit1} (Const% / Cov%)</th>
                <th>{activePairComparison.unit2} (Const% / Cov%)</th>
                <th>Diff Pts ({activePairComparison.unit1})</th>
                <th>Diff Pts ({activePairComparison.unit2})</th>
                <th>Favours</th>
              </tr>
            </thead>
            <tbody>
              {#each activePairComparison.differentialTaxa.slice(0, 15) as dt (dt.species)}
                <tr>
                  <td class="mono-cell">{dt.species}</td>
                  <td><em>{dt.scientificName}</em></td>
                  <td>{dt.constancyUnit1.toFixed(0)}% / {dt.meanCoverUnit1.toFixed(1)}%</td>
                  <td>{dt.constancyUnit2.toFixed(0)}% / {dt.meanCoverUnit2.toFixed(1)}%</td>
                  <td>{dt.diffPtsUnit1.toFixed(2)}</td>
                  <td>{dt.diffPtsUnit2.toFixed(2)}</td>
                  <td><strong>{dt.favoursUnit}</strong></td>
                </tr>
              {/each}
            </tbody>
          </table>
        {/if}
      </div>
    {/if}
  {/if}
</div>
