<script lang="ts">
  import SynthesisEdatopicTab from './SynthesisEdatopicTab.svelte';
  import SynthesisMatrixTab from './SynthesisMatrixTab.svelte';
  import SynthesisSimilarityTab from './SynthesisSimilarityTab.svelte';
  import type {
    BreakpointUnitRollup,
    EdatopicCell,
    EdatopicUnitGrid,
    MatrixDisplayMode,
    PairwiseUnitComparison,
    SpeciesMatrixSection,
    SynthesisSnapshot,
    SynthesisWorkspaceTab,
  } from './classificationSynthesis';

  let {
    snapshot,
    activeTab = $bindable(),
    speciesSearch = $bindable(),
    matrixSections,
    matrixDisplay,
    useBreakpointGrouping,
    breakpointPolicy,
    breakpointRollups,
    loading,
    dragOverUnit = $bindable(),
    similarityMetric = $bindable(),
    selectedPairUnits = $bindable(),
    activePairComparison,
    selectedEdatopicScope = $bindable(),
    inspectedEdatopicCell = $bindable(),
    activeEdatopicGrid,
    edatopicRows,
    onUnitDragOver,
    onUnitDrop,
    onOpenPlot,
  }: {
    snapshot: SynthesisSnapshot | null;
    activeTab: SynthesisWorkspaceTab;
    speciesSearch: string;
    matrixSections: SpeciesMatrixSection[];
    matrixDisplay: MatrixDisplayMode;
    useBreakpointGrouping: boolean;
    breakpointPolicy: 'lowest' | 'highest';
    breakpointRollups: BreakpointUnitRollup[];
    loading: boolean;
    dragOverUnit: string | null;
    similarityMetric: 'sorensen' | 'bec_diff';
    selectedPairUnits: [string, string];
    activePairComparison: PairwiseUnitComparison | null;
    selectedEdatopicScope: string;
    inspectedEdatopicCell: EdatopicCell | null;
    activeEdatopicGrid: EdatopicUnitGrid | null;
    edatopicRows: EdatopicCell[][];
    onUnitDragOver: (ev: DragEvent, unitCode: string) => void;
    onUnitDrop: (ev: DragEvent, unitCode: string) => void;
    onOpenPlot?: (plotNumber: string) => void;
  } = $props();
</script>

<div class="syn-primary-pane">
  <div class="syn-tabbar" role="tablist" aria-label="Synthesis Views">
    <button
      type="button"
      role="tab"
      aria-selected={activeTab === 'matrix'}
      class="syn-tab"
      class:active={activeTab === 'matrix'}
      onclick={() => (activeTab = 'matrix')}
    >
      Diagnostic Matrix ({snapshot?.species.length ?? 0} Taxa)
    </button>
    <button
      type="button"
      role="tab"
      aria-selected={activeTab === 'similarity'}
      class="syn-tab"
      class:active={activeTab === 'similarity'}
      onclick={() => (activeTab = 'similarity')}
    >
      Pairwise Similarity ({snapshot?.units.length ?? 0}x{snapshot?.units.length ?? 0})
    </button>
    <button
      type="button"
      role="tab"
      aria-selected={activeTab === 'edatopic'}
      class="syn-tab"
      class:active={activeTab === 'edatopic'}
      onclick={() => (activeTab = 'edatopic')}
    >
      Edatopic Grid (rSMR 0..8 x rSNR A..F)
    </button>

    {#if activeTab === 'matrix'}
      <input
        type="search"
        aria-label="Filter synthesis matrix by species, code, lifeform, or unit"
        class="syn-inline-search"
        placeholder="Filter species, code, lifeform, or unit..."
        value={speciesSearch}
        oninput={(e) => (speciesSearch = e.currentTarget.value)}
      />
    {/if}
  </div>

  {#if activeTab === 'matrix'}
    <SynthesisMatrixTab
      {snapshot}
      {matrixSections}
      {matrixDisplay}
      {useBreakpointGrouping}
      {breakpointPolicy}
      {breakpointRollups}
      {loading}
      {dragOverUnit}
      {onUnitDragOver}
      onUnitDragLeave={(unitCode) => {
        if (dragOverUnit === unitCode) dragOverUnit = null;
      }}
      {onUnitDrop}
    />
  {/if}

  {#if activeTab === 'similarity'}
    <SynthesisSimilarityTab
      {snapshot}
      {similarityMetric}
      {selectedPairUnits}
      {activePairComparison}
      onMetricChange={(metric) => (similarityMetric = metric)}
      onSelectPair={(pair) => (selectedPairUnits = pair)}
    />
  {/if}

  {#if activeTab === 'edatopic'}
    <SynthesisEdatopicTab
      {snapshot}
      {selectedEdatopicScope}
      {inspectedEdatopicCell}
      {activeEdatopicGrid}
      {edatopicRows}
      {dragOverUnit}
      onSelectScope={(scope) => {
        selectedEdatopicScope = scope;
        inspectedEdatopicCell = null;
      }}
      onSelectCell={(cell) => (inspectedEdatopicCell = cell)}
      {onUnitDragOver}
      {onUnitDrop}
      {onOpenPlot}
    />
  {/if}
</div>
