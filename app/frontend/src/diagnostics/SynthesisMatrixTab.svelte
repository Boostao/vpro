<script lang="ts">
  import {
    DIAGNOSTIC_CODE_META,
    formatSynthesisMatrixCell,
    resolveDiagnosticCellClass,
    type BreakpointUnitRollup,
    type MatrixDisplayMode,
    type SpeciesMatrixSection,
    type SynthesisSnapshot,
  } from './classificationSynthesis';

  interface Props {
    snapshot: SynthesisSnapshot | null;
    matrixSections: SpeciesMatrixSection[];
    matrixDisplay: MatrixDisplayMode;
    useBreakpointGrouping: boolean;
    breakpointPolicy: 'lowest' | 'highest';
    breakpointRollups: BreakpointUnitRollup[];
    loading: boolean;
    dragOverUnit: string | null;
    onUnitDragOver: (ev: DragEvent, unitCode: string) => void;
    onUnitDragLeave: (unitCode: string) => void;
    onUnitDrop: (ev: DragEvent, unitCode: string) => void;
  }

  let {
    snapshot,
    matrixSections,
    matrixDisplay,
    useBreakpointGrouping,
    breakpointPolicy,
    breakpointRollups,
    loading,
    dragOverUnit,
    onUnitDragOver,
    onUnitDragLeave,
    onUnitDrop,
  }: Props = $props();
</script>

<div class="syn-legend-bar">
  <span class="syn-legend-title">BEC Diagnostic Classes:</span>
  {#each Object.entries(DIAGNOSTIC_CODE_META) as [code, meta] (code)}
    <span class="diag-badge {meta.badgeClass}" title={meta.label}>
      {meta.shortLabel}
    </span>
  {/each}
  {#if snapshot?.lumpTableUsed}
    <span class="syn-lump-pill">
      Lumped via {snapshot.lumpTableUsed} ({snapshot.lumpFoldedTaxa} folded, {snapshot.lumpCappedCells} capped at 99%)
    </span>
  {/if}
  {#if snapshot?.suWritable}
    <span class="syn-drop-hint">
      Tip: Drag any outlier plot card onto a Site Unit column header to reassign live.
    </span>
  {/if}
</div>

{#if useBreakpointGrouping && breakpointRollups.length > 0}
  <div class="syn-breakpoint-rollups" data-synthesis-breakpoint-rollups>
    <span class="syn-legend-title">'~' Hierarchy Breakpoint Rollup ({breakpointPolicy}):</span>
    {#each breakpointRollups as rollup (rollup.breakpointUnit)}
      <span class="syn-breakpoint-chip">
        <strong>~{rollup.breakpointUnit}</strong>
        <span>n={rollup.plotCount}, {rollup.speciesCount} taxa</span>
        <span class="syn-muted">[{rollup.descendantUnits.join(', ')}]</span>
      </span>
    {/each}
  </div>
{/if}

<div class="syn-table-container">
  {#if !snapshot || snapshot.units.length === 0}
    <div class="syn-empty">
      {loading
        ? 'Computing BEC synthesis snapshot...'
        : 'No classified Site Units available in the current scope.'}
    </div>
  {:else}
    <table class="syn-matrix-table">
      <thead>
        <tr>
          <th class="sticky-col col-code">Code</th>
          <th class="sticky-col col-sci">Scientific Name</th>
          <th class="col-lf">Stratum</th>
          <th class="col-diag">Diagnosis</th>
          {#each snapshot.units as unit (unit.siteUnit)}
            <th
              class="col-unit"
              class:drop-active={dragOverUnit === unit.siteUnit}
              ondragover={ev => onUnitDragOver(ev, unit.siteUnit)}
              ondragleave={() => onUnitDragLeave(unit.siteUnit)}
              ondrop={ev => onUnitDrop(ev, unit.siteUnit)}
              title={unit.longName
                ? `${unit.siteUnit} — ${unit.longName} (n=${unit.plotCount} plots, ${unit.diagnosticCount} diagnostic taxa)`
                : `${unit.siteUnit} (n=${unit.plotCount} plots)`}
            >
              <div class="unit-th-code">{unit.siteUnit}</div>
              <div class="unit-th-sub">n={unit.plotCount} · diag={unit.diagnosticCount}</div>
            </th>
          {/each}
        </tr>
      </thead>
      <tbody>
        {#each matrixSections as section (section.key)}
          <tr class="syn-section-row">
            <td colspan={4 + snapshot.units.length}>
              <strong>{section.title}</strong>
              {#if section.subtitle}
                <span class="syn-section-sub">{section.subtitle}</span>
              {/if}
            </td>
          </tr>
          {#each section.rows as sp (sp.species)}
            <tr>
              <td class="sticky-col col-code mono-cell">
                {sp.species}
                {#if sp.sourceSpecies && sp.sourceSpecies.length > 0}
                  <span
                    class="lump-origin-tag"
                    title={`Includes lumped: ${sp.sourceSpecies.join(', ')}`}
                  >
                    +{sp.sourceSpecies.length}
                  </span>
                {/if}
              </td>
              <td class="sticky-col col-sci" title={sp.englishName}>
                <em>{sp.scientificName}</em>
              </td>
              <td class="col-lf">{sp.stratumGroup}</td>
              <td class="col-diag">
                {#if sp.diagnosticCodes.length > 0}
                  <div class="diag-cell-badges">
                    {#each sp.diagnosticCodes as dc (dc)}
                      <span
                        class="diag-badge {DIAGNOSTIC_CODE_META[dc]?.badgeClass ?? ''}"
                        title={`${sp.diagnosticUnit}: ${DIAGNOSTIC_CODE_META[dc]?.label ?? dc}`}
                      >
                        {dc}
                      </span>
                    {/each}
                    <span class="diag-unit-ref">{sp.diagnosticUnit}</span>
                  </div>
                {/if}
              </td>
              {#each sp.cells as cell (cell.siteUnit)}
                <td
                  class="col-unit-val {resolveDiagnosticCellClass(cell.cellDiagnosticCodes)}"
                  title={cell.presentPlots > 0
                    ? `${sp.species} in ${cell.siteUnit}: ${cell.presentPlots}/${cell.plotCount} plots (${cell.presencePctText}%, Class ${cell.presenceRoman}), Mean All=${cell.meanCoverAllText}%, Mean Present=${cell.meanCoverPresentText}%, Signif=${cell.signifClass}`
                    : ''}
                >
                  {#if cell.presentPlots > 0}
                    <span>
                      {formatSynthesisMatrixCell(
                        cell,
                        matrixDisplay,
                        snapshot.significanceBasis
                      )}
                    </span>
                    {#if cell.isPrimaryDiagnosticUnit && cell.cellDiagnosticCodes.length > 0}
                      <sup class="cell-diag-sup">{cell.cellDiagnosticCodes.join(',')}</sup>
                    {/if}
                  {/if}
                </td>
              {/each}
            </tr>
          {/each}
        {/each}
      </tbody>
    </table>
  {/if}
</div>
