<script lang="ts">
  import {
    edatopicCellColor,
    indexEdatopicCells,
    type ClimateEdatopicResult,
    type EdatopicGridCell,
    type EdatopicGridMatrix,
  } from './rSidecarWorkbench';

  interface ActiveEdatopicView {
    label: string;
    plotCount: number;
    meanShift: number | null;
    meanCmd: number | null;
    relativeGrid: EdatopicGridMatrix;
    actualGrid: EdatopicGridMatrix;
  }

  let {
    climateResult = null,
    activeEdatopicView = null,
    busy = false,
    selectedUnitGroup = $bindable('__overall__'),
    selectedCellDetail = $bindable<{ gridKind: string; cell: EdatopicGridCell } | null>(null),
    onRunClimate,
  }: {
    climateResult?: ClimateEdatopicResult | null;
    activeEdatopicView?: ActiveEdatopicView | null;
    busy?: boolean;
    selectedUnitGroup?: string;
    selectedCellDetail?: { gridKind: string; cell: EdatopicGridCell } | null;
    onRunClimate?: () => Promise<void> | void;
  } = $props();

  const relIndexed = $derived(indexEdatopicCells(activeEdatopicView?.relativeGrid));
  const actIndexed = $derived(indexEdatopicCells(activeEdatopicView?.actualGrid));
</script>

<div class="panel">
  <div class="card">
    <h3>Ministry CMD to aSMR Dual Edatopic Grids</h3>
    {#if !climateResult || !activeEdatopicView}
      <p class="muted">
        Compute plot climate normals to populate the Dual Relative (rSMR) and Actual (aSMR) Edatopic Grids.
      </p>
      {#if onRunClimate}
        <div class="button-row">
          <button type="button" class="btn-primary" data-edatopic-compute-now disabled={busy} onclick={onRunClimate}>
            {busy ? 'Computing Climate & aSMR...' : 'Compute Climate & aSMR Now'}
          </button>
        </div>
      {/if}
    {:else}
      <div class="form-row">
        <label>
          BGC / Site Unit Scope
          <select bind:value={selectedUnitGroup}>
            <option value="__overall__">Overall Project Scope ({climateResult.coordinatizedPlots} plots)</option>
            {#each climateResult.unitSummaries as unit}
              <option value={unit.groupKey}>
                {unit.groupKey} ({unit.plotCount} plots{unit.meanAsmr !== undefined
                  ? `, mean aSMR ${unit.meanAsmr}`
                  : ''})
              </option>
            {/each}
          </select>
        </label>
        {#if activeEdatopicView.meanShift !== null}
          <div class="kpi">
            <span>Mean Moisture Shift (aSMR - rSMR)</span>
            <strong
              >{activeEdatopicView.meanShift > 0
                ? `+${activeEdatopicView.meanShift}`
                : activeEdatopicView.meanShift}</strong
            >
          </div>
        {/if}
      </div>

      <div class="dual-grid-wrap">
        <div class="edatopic-panel">
          <h4>Relative Edatopic Grid (rSMR x rSNR) — Modal: {activeEdatopicView.relativeGrid.modalCell || '—'}</h4>
          <div class="table-scroll">
            <table class="edatopic-table">
              <thead>
                <tr>
                  <th>rSMR \ rSNR</th>
                  {#each activeEdatopicView.relativeGrid.nutrientAxis as snr}
                    <th>{snr}</th>
                  {/each}
                </tr>
              </thead>
              <tbody>
                {#each activeEdatopicView.relativeGrid.moistureAxis as smr}
                  <tr>
                    <th>{smr}</th>
                    {#each activeEdatopicView.relativeGrid.nutrientAxis as snr}
                      {@const cell = relIndexed.byKey[`${smr}|${snr}`]}
                      {@const colors = edatopicCellColor(cell?.count || 0, relIndexed.maxCount)}
                      <td style="background:{colors.bg};color:{colors.fg}">
                        {#if cell}
                          <button
                            type="button"
                            class="edatopic-cell-btn"
                            style="color:{colors.fg}"
                            onclick={() => {
                              selectedCellDetail = { gridKind: 'Relative (rSMR)', cell };
                            }}
                          >
                            <strong>{cell.count}</strong>
                            <small>{cell.frequency}%</small>
                          </button>
                        {:else}
                          ·
                        {/if}
                      </td>
                    {/each}
                  </tr>
                {/each}
              </tbody>
            </table>
          </div>
        </div>

        <div class="edatopic-panel">
          <h4>Actual Edatopic Grid (aSMR x rSNR) — Modal: {activeEdatopicView.actualGrid.modalCell || '—'}</h4>
          <div class="table-scroll">
            <table class="edatopic-table compact-edatope">
              <thead>
                <tr>
                  <th>aSMR \ rSNR</th>
                  {#each activeEdatopicView.actualGrid.nutrientAxis as snr}
                    <th>{snr}</th>
                  {/each}
                </tr>
              </thead>
              <tbody>
                {#each activeEdatopicView.actualGrid.moistureAxis as asmr}
                  <tr>
                    <th>{asmr}</th>
                    {#each activeEdatopicView.actualGrid.nutrientAxis as snr}
                      {@const cell = actIndexed.byKey[`${asmr}|${snr}`]}
                      {@const colors = edatopicCellColor(cell?.count || 0, actIndexed.maxCount)}
                      <td style="background:{colors.bg};color:{colors.fg}">
                        {#if cell}
                          <button
                            type="button"
                            class="edatopic-cell-btn"
                            style="color:{colors.fg}"
                            onclick={() => {
                              selectedCellDetail = { gridKind: 'Actual (aSMR)', cell };
                            }}
                          >
                            <strong>{cell.count}</strong>
                          </button>
                        {:else}
                          ·
                        {/if}
                      </td>
                    {/each}
                  </tr>
                {/each}
              </tbody>
            </table>
          </div>
        </div>
      </div>

      {#if selectedCellDetail}
        <div class="cell-detail-box">
          <strong>
            {selectedCellDetail.gridKind} Cell {selectedCellDetail.cell.moisture}/{selectedCellDetail.cell.nutrient}:
          </strong>
          {selectedCellDetail.cell.count} plot(s) ({selectedCellDetail.cell.frequency}%)
          {#if selectedCellDetail.cell.meanCmdSite !== undefined}
            | Mean CMD.site: {selectedCellDetail.cell.meanCmdSite} mm
          {/if}
          <div>Plots: <code>{selectedCellDetail.cell.plotNumbers.join(', ')}</code></div>
        </div>
      {/if}
    {/if}
  </div>
</div>
