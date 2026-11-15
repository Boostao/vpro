<script lang="ts">
  import {
    EDATOPIC_SMR_ROWS,
    EDATOPIC_SNR_COLS,
    edatopicHeatLevel,
    SMR_DESCRIPTIONS,
    SNR_DESCRIPTIONS,
    type EdatopicCell,
    type EdatopicUnitGrid,
    type SynthesisSnapshot,
  } from './classificationSynthesis';

  interface Props {
    snapshot: SynthesisSnapshot | null;
    selectedEdatopicScope: string;
    inspectedEdatopicCell: EdatopicCell | null;
    activeEdatopicGrid: EdatopicUnitGrid | null;
    edatopicRows: EdatopicCell[][];
    dragOverUnit: string | null;
    onSelectScope: (scope: string) => void;
    onSelectCell: (cell: EdatopicCell) => void;
    onUnitDragOver: (ev: DragEvent, unitCode: string) => void;
    onUnitDrop: (ev: DragEvent, unitCode: string) => void;
    onOpenPlot?: (plotNumber: string) => void;
  }

  let {
    snapshot,
    selectedEdatopicScope,
    inspectedEdatopicCell,
    activeEdatopicGrid,
    edatopicRows,
    dragOverUnit,
    onSelectScope,
    onSelectCell,
    onUnitDragOver,
    onUnitDrop,
    onOpenPlot,
  }: Props = $props();
</script>

<div class="syn-edatopic-pane">
  {#if !snapshot}
    <div class="syn-empty">No edatopic data loaded.</div>
  {:else}
    <div class="syn-subbar">
      <span class="syn-subbar-label">Unit Scope:</span>
      <button
        type="button"
        class="syn-pill-btn"
        class:active={selectedEdatopicScope === '__OVERALL__'}
        onclick={() => onSelectScope('__OVERALL__')}
      >
        All Classified ({snapshot.overallEdatopicGrid.plottedEdatopicCount}/{snapshot.overallEdatopicGrid.totalPlots})
      </button>
      {#each snapshot.unitEdatopicGrids as ug (ug.siteUnit)}
        <button
          type="button"
          class="syn-pill-btn"
          class:active={selectedEdatopicScope === ug.siteUnit}
          class:drop-active={dragOverUnit === ug.siteUnit}
          ondragover={ev => onUnitDragOver(ev, ug.siteUnit)}
          ondrop={ev => onUnitDrop(ev, ug.siteUnit)}
          onclick={() => onSelectScope(ug.siteUnit)}
        >
          {ug.siteUnit} ({ug.plottedEdatopicCount}/{ug.totalPlots})
        </button>
      {/each}
    </div>

    {#if activeEdatopicGrid}
      <div class="edatopic-layout">
        <div class="edatopic-grid-card">
          <div class="edatopic-card-hdr">
            <strong>{activeEdatopicGrid.label} — Relative Edatopic Grid (9 x 6)</strong>
            <span>
              Plotted: {activeEdatopicGrid.plottedEdatopicCount} · Missing SMR/SNR:{' '}
              {activeEdatopicGrid.missingEdatopicCount}
            </span>
          </div>
          <table class="edatopic-table" aria-label="Relative Edatopic Grid">
            <thead>
              <tr>
                <th class="eda-corner">rSMR \ rSNR</th>
                {#each EDATOPIC_SNR_COLS as snr (snr)}
                  <th title={SNR_DESCRIPTIONS[snr]}>
                    <div>{snr}</div>
                    <div class="eda-axis-sub">{SNR_DESCRIPTIONS[snr]}</div>
                  </th>
                {/each}
              </tr>
            </thead>
            <tbody>
              {#each edatopicRows as rowCells, rIdx (EDATOPIC_SMR_ROWS[rIdx])}
                {@const smrCode = EDATOPIC_SMR_ROWS[rIdx]}
                <tr>
                  <th class="eda-row-hdr" title={SMR_DESCRIPTIONS[smrCode]}>
                    <span class="mono-cell">{smrCode}</span>
                    <span class="eda-axis-sub">{SMR_DESCRIPTIONS[smrCode]}</span>
                  </th>
                  {#each rowCells as cell (cell.snr)}
                    {@const heat = edatopicHeatLevel(cell.prominence, cell.plotCount)}
                    <td
                      class="eda-cell eda-heat-{heat}"
                      class:eda-selected={
                        inspectedEdatopicCell?.smr === cell.smr &&
                        inspectedEdatopicCell?.snr === cell.snr
                      }
                      onclick={() => onSelectCell(cell)}
                      title={`rSMR ${cell.smr} / rSNR ${cell.snr}: ${cell.plotCount} plots (${cell.prominence.toFixed(1)}% prominence)`}
                    >
                      {#if cell.plotCount > 0}
                        <div class="eda-count">{cell.plotCount}</div>
                        <div class="eda-prom">{cell.prominence.toFixed(0)}%</div>
                      {/if}
                    </td>
                  {/each}
                </tr>
              {/each}
            </tbody>
          </table>
        </div>

        <div class="edatopic-inspector">
          <h3>Cell Plot Membership</h3>
          {#if !inspectedEdatopicCell}
            <p class="syn-muted">
              Select any cell in the 9x6 (rSMR 0..8 x rSNR A..F) grid to inspect contributing plots.
            </p>
          {:else}
            <p class="eda-inspected-title">
              <strong>rSMR {inspectedEdatopicCell.smr}{inspectedEdatopicCell.snr}</strong>
              ({SMR_DESCRIPTIONS[inspectedEdatopicCell.smr]} / {SNR_DESCRIPTIONS[inspectedEdatopicCell.snr]})
              — {inspectedEdatopicCell.plotCount} plots ({inspectedEdatopicCell.prominence.toFixed(1)}% prominence)
            </p>
            {#if inspectedEdatopicCell.plotNumbers.length === 0}
              <p class="syn-muted">No plots occupy this edatopic position.</p>
            {:else}
              <div class="eda-plot-chips">
                {#each inspectedEdatopicCell.plotNumbers as pNum (pNum)}
                  <button
                    type="button"
                    class="plot-jump-chip"
                    onclick={() => onOpenPlot?.(pNum)}
                  >
                    {pNum}
                  </button>
                {/each}
              </div>
            {/if}
          {/if}
        </div>
      </div>
    {/if}
  {/if}
</div>
