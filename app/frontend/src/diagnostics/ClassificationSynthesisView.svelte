<script lang="ts">
  import { onDestroy, onMount, untrack } from 'svelte';
  import { ReadRequests, formatError } from '../shared/readRequests';
  import { notifications } from '../shell/notificationService.svelte';
  import SynthesisExportModal from './SynthesisExportModal.svelte';
  import SynthesisOutlierQueue from './SynthesisOutlierQueue.svelte';
  import SynthesisPrimaryPane from './SynthesisPrimaryPane.svelte';
  import SynthesisTopChrome from './SynthesisTopChrome.svelte';
  import {
    buildDiagnosticWorkbookPayload,
    chooseExternalSQLiteTarget,
    createDefaultPairwiseParams,
    createDefaultSynthesisExportDraft,
    createDefaultSynthesisOptions,
    defaultSynthesisBackendPort,
    discoverExternalSynthesisLumps,
    filterAndGroupSpeciesRows,
    filterOutlierQueue,
    findPairwiseComparison,
    getEdatopicCellMatrix,
    groupUnitsByHierarchyBreakpoints,
    mergeUniqueLumpOptions,
    resolveSynthesisHierarchyBreakpoints,
    validateWorkbookExportDraft,
    type BreakpointUnitRollup,
    type EdatopicCell,
    type ExportDiagnosticWorkbookResult,
    type MatrixDisplayMode,
    type MatrixGroupingMode,
    type OutlierFilterMode,
    type SynthesisBackendPort,
    type SynthesisExportDraft,
    type SynthesisLumpTableOption,
    type SynthesisOptions,
    type SynthesisSnapshot,
    type SynthesisWorkspaceTab,
  } from './classificationSynthesis';

  interface Props {
    contextId: string;
    project?: string;
    su?: string;
    initialSnapshot?: SynthesisSnapshot | null;
    port?: SynthesisBackendPort;
    onBusyChange?: (busy: boolean) => void;
    onOpenPlot?: (plotNumber: string) => void;
  }

  let {
    contextId,
    project = '',
    su = 'None',
    initialSnapshot = null,
    port = defaultSynthesisBackendPort,
    onBusyChange,
    onOpenPlot,
  }: Props = $props();

  const reads = new ReadRequests();

  let effectiveContextId = $state(untrack(() => contextId));
  let snapshot = $state.raw<SynthesisSnapshot | null>(untrack(() => initialSnapshot));
  let lumpOptions = $state.raw<SynthesisLumpTableOption[]>([]);

  let options = $state<SynthesisOptions>(createDefaultSynthesisOptions());
  let excludePatternsText = $state('');
  let externalLumpDbPath = $state('');
  let externalSuPath = $state('');
  let externalSuNames = $state<string[]>([]);
  let useBreakpointGrouping = $state(false);
  let breakpointPolicy = $state<'lowest' | 'highest'>('lowest');
  let breakpointRollups = $state.raw<BreakpointUnitRollup[]>([]);
  let activeTab = $state<SynthesisWorkspaceTab>('matrix');
  let matrixDisplay = $state<MatrixDisplayMode>('roman_signif');
  let matrixGrouping = $state<MatrixGroupingMode>('diagnostic_unit');
  let diagnosticOnly = $state(false);
  let speciesSearch = $state('');

  let outlierFilter = $state<OutlierFilterMode>('all');
  let outlierSearch = $state('');
  let manualTargetByPlot = $state<Record<string, string>>({});

  let selectedPairUnits = $state<[string, string]>(['', '']);
  let similarityMetric = $state<'sorensen' | 'bec_diff'>('sorensen');

  let selectedEdatopicScope = $state<string>('__OVERALL__');
  let inspectedEdatopicCell = $state.raw<EdatopicCell | null>(null);

  let draggingPlotNumber = $state<string | null>(null);
  let dragOverUnit = $state<string | null>(null);

  let exportModalOpen = $state(false);
  let exportDraft = $state<SynthesisExportDraft>(createDefaultSynthesisExportDraft());
  let exportingWorkbook = $state(false);
  let lastExportResult = $state.raw<ExportDiagnosticWorkbookResult | null>(null);

  let loading = $state(false);
  let mutating = $state(false);
  let lastLatencyMs = $state<number | null>(untrack(() => (initialSnapshot ? initialSnapshot.computeMs : null)));
  let statusNotice = $state('');
  let errorMessage = $state('');

  let requestGeneration = 0;

  $effect(() => {
    if (contextId && contextId !== effectiveContextId) {
      effectiveContextId = contextId;
      void refreshAll();
    }
  });

  function pushNotice(
    severity: 'success' | 'info',
    category: 'general' | 'background',
    title: string,
    message: string
  ) {
    notifications.push({ severity, category, source: 'BEC Synthesis', title, message });
  }

  function setBusyState(nextLoading: boolean, nextMutating: boolean) {
    loading = nextLoading;
    mutating = nextMutating;
    onBusyChange?.(nextLoading || nextMutating || exportingWorkbook);
  }

  async function runReadSnapshot(withLumps: boolean): Promise<void> {
    if (!effectiveContextId) return;
    reads.cancelAll();
    const gen = ++requestGeneration;
    setBusyState(true, mutating);
    errorMessage = '';
    try {
      const plainOpts = $state.snapshot(options);
      if (withLumps) {
        const [lumps, snap] = await Promise.all([
          reads.track(port.listSynthesisLumpTables(effectiveContextId)),
          reads.track(port.computeSynthesisSnapshot(effectiveContextId, plainOpts)),
        ]);
        if (gen !== requestGeneration) return;
        lumpOptions = lumps ?? [];
        applyIncomingSnapshot(snap, snap.computeMs);
      } else {
        const snap = await reads.track(port.computeSynthesisSnapshot(effectiveContextId, plainOpts));
        if (gen !== requestGeneration) return;
        applyIncomingSnapshot(snap, snap.computeMs);
        if (useBreakpointGrouping) {
          const res = await reads.track(resolveSynthesisHierarchyBreakpoints(effectiveContextId, breakpointPolicy));
          if (gen !== requestGeneration) return;
          breakpointRollups = groupUnitsByHierarchyBreakpoints(snap, res);
        } else {
          breakpointRollups = [];
        }
      }
    } catch (err) {
      if (gen !== requestGeneration) return;
      errorMessage = formatError(err);
    } finally {
      if (gen === requestGeneration) setBusyState(false, mutating);
    }
  }

  const refreshAll = () => runReadSnapshot(true);
  const recomputeSnapshotOnly = () => runReadSnapshot(false);

  async function browseExternalLumpDatabase() {
    if (!effectiveContextId || loading || mutating) return;
    errorMessage = '';
    try {
      const picked = await chooseExternalSQLiteTarget(effectiveContextId);
      if (!picked?.selectedPath) return;
      externalLumpDbPath = picked.selectedPath;
      const extLumps = await discoverExternalSynthesisLumps(effectiveContextId, picked.selectedPath);
      lumpOptions = mergeUniqueLumpOptions(lumpOptions, extLumps);
      if (extLumps.length > 0) {
        options.lumpTable = extLumps[0].name;
        options.lumpDbPath = extLumps[0].dbPath;
        await recomputeSnapshotOnly();
      } else {
        statusNotice = `No *_Lump tables found in ${picked.selectedPath}.`;
      }
    } catch (err) {
      errorMessage = formatError(err);
    }
  }

  async function browseExternalSUFile() {
    if (!effectiveContextId || loading || mutating) return;
    errorMessage = '';
    try {
      const picked = await chooseExternalSQLiteTarget(effectiveContextId);
      if (!picked?.selectedPath) return;
      externalSuPath = picked.selectedPath;
      externalSuNames = (picked.sus ?? []).map((s) => s.name).filter(Boolean);
      statusNotice =
        externalSuNames.length > 0
          ? `Inspected external SU file (${picked.selectedPath}): ${externalSuNames.join(', ')}. Switch active SU in Classification Explorer or UserSiteUnitList mode.`
          : `Selected ${picked.selectedPath} (no *_SU tables found).`;
    } catch (err) {
      errorMessage = formatError(err);
    }
  }

  function applyExcludePatterns(raw: string) {
    excludePatternsText = raw;
    options.excludePatterns = raw
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean);
  }

  function updateOptions(patch: Partial<SynthesisOptions>, recompute = false) {
    Object.assign(options, patch);
    if (patch.minMaxPresencePct !== undefined) options.minMaxPresencePct = patch.minMaxPresencePct;
    if (recompute) void recomputeSnapshotOnly();
  }

  function updatePairwiseParam(key: 'minPlots' | 'minConstancy' | 'noiseConstancy' | 'minDiff' | 'minDd', raw: string) {
    const parsed = Number(raw);
    if (!Number.isFinite(parsed)) return;
    options.pairwise = { ...(options.pairwise ?? createDefaultPairwiseParams()), [key]: parsed };
  }

  function resetPairwiseDefaults() {
    options.pairwise = createDefaultPairwiseParams();
    void recomputeSnapshotOnly();
  }

  async function toggleBreakpointGrouping(nextEnabled: boolean, nextPolicy = breakpointPolicy) {
    useBreakpointGrouping = nextEnabled;
    breakpointPolicy = nextPolicy;
    if (!nextEnabled) {
      breakpointRollups = [];
      return;
    }
    if (!effectiveContextId || !snapshot) return;
    try {
      const res = await reads.track(resolveSynthesisHierarchyBreakpoints(effectiveContextId, nextPolicy));
      breakpointRollups = groupUnitsByHierarchyBreakpoints(snapshot, res);
    } catch (err) {
      errorMessage = formatError(err);
    }
  }

  function applyIncomingSnapshot(snap: SynthesisSnapshot, latencyMs: number) {
    snapshot = snap;
    lastLatencyMs = latencyMs;
    if (selectedEdatopicScope !== '__OVERALL__' && !snap.units.some((u) => u.siteUnit === selectedEdatopicScope)) {
      selectedEdatopicScope = '__OVERALL__';
    }
    if (
      snap.units.length >= 2 &&
      (!selectedPairUnits[0] ||
        !selectedPairUnits[1] ||
        !snap.units.some((u) => u.siteUnit === selectedPairUnits[0]) ||
        !snap.units.some((u) => u.siteUnit === selectedPairUnits[1]))
    ) {
      selectedPairUnits = [snap.units[0].siteUnit, snap.units[1].siteUnit];
    }
  }

  async function handleReassignPlot(plotNumber: string, targetUnit: string): Promise<void> {
    const cleanTarget = targetUnit.trim();
    if (!effectiveContextId || !plotNumber || !cleanTarget || mutating) return;
    if (!snapshot?.suWritable) {
      errorMessage = snapshot?.suReadOnlyReason || 'Select a writable Site Unit (SU) table before reassigning plots.';
      return;
    }

    const gen = ++requestGeneration;
    setBusyState(loading, true);
    errorMessage = '';
    try {
      const res = await port.reassignSynthesisPlotUnit(effectiveContextId, {
        plotNumber,
        targetSiteUnit: cleanTarget,
        options: $state.snapshot(options),
      });
      if (gen !== requestGeneration) return;
      applyIncomingSnapshot(res.snapshot, res.latencyMs);
      statusNotice = res.changed
        ? `Moved plot ${res.plotNumber} from ${res.beforeSiteUnit || 'Unassigned'} to ${res.afterSiteUnit} in ${res.latencyMs.toFixed(1)} ms.`
        : `Plot ${res.plotNumber} is already assigned to ${res.afterSiteUnit}.`;
      if (res.changed) {
        pushNotice(
          'success',
          'general',
          `Moved plot ${res.plotNumber} -> ${res.afterSiteUnit}`,
          `From ${res.beforeSiteUnit || 'Unassigned'} (${res.latencyMs.toFixed(1)} ms)`
        );
      }
    } catch (err) {
      if (gen !== requestGeneration) return;
      errorMessage = formatError(err);
    } finally {
      if (gen === requestGeneration) setBusyState(loading, false);
    }
  }

  async function handleUndoReassignment(): Promise<void> {
    if (!effectiveContextId || mutating || !snapshot?.canUndo) return;
    const gen = ++requestGeneration;
    setBusyState(loading, true);
    errorMessage = '';
    try {
      const res = await port.undoSynthesisReassignment(effectiveContextId, {
        options: $state.snapshot(options),
      });
      if (gen !== requestGeneration) return;
      applyIncomingSnapshot(res.snapshot, res.latencyMs);
      statusNotice = `Restored plot ${res.plotNumber} to ${res.afterSiteUnit || 'Unassigned'} in ${res.latencyMs.toFixed(1)} ms.`;
      pushNotice(
        'info',
        'general',
        `Restored plot ${res.plotNumber}`,
        `Reverted to ${res.afterSiteUnit || 'Unassigned'} (${res.latencyMs.toFixed(1)} ms)`
      );
    } catch (err) {
      if (gen !== requestGeneration) return;
      errorMessage = formatError(err);
    } finally {
      if (gen === requestGeneration) setBusyState(loading, false);
    }
  }

  async function handlePublishWorkbook(): Promise<void> {
    const validationErr = validateWorkbookExportDraft(exportDraft);
    if (validationErr) {
      errorMessage = validationErr;
      return;
    }
    const gen = ++requestGeneration;
    exportingWorkbook = true;
    onBusyChange?.(true);
    errorMessage = '';
    try {
      const res = await port.exportDiagnosticWorkbook(
        effectiveContextId,
        buildDiagnosticWorkbookPayload(exportDraft, $state.snapshot(options))
      );
      if (gen !== requestGeneration) return;
      lastExportResult = res;
      statusNotice = `Published 4-sheet BEC Diagnostic workbook (${res.path}) in ${res.latencyMs.toFixed(1)} ms.`;
      pushNotice(
        'success',
        'background',
        'Published BEC Diagnostic Workbook (.xlsx)',
        `${res.path} (${res.latencyMs.toFixed(1)} ms)`
      );
    } catch (err) {
      if (gen !== requestGeneration) return;
      errorMessage = formatError(err);
    } finally {
      if (gen === requestGeneration) {
        exportingWorkbook = false;
        onBusyChange?.(loading || mutating);
      }
    }
  }

  function onPlotDragStart(ev: DragEvent, plotNumber: string) {
    if (!snapshot?.suWritable) return;
    draggingPlotNumber = plotNumber;
    if (ev.dataTransfer) {
      ev.dataTransfer.effectAllowed = 'move';
      ev.dataTransfer.setData('text/plain', plotNumber);
    }
  }

  function onPlotDragEnd() {
    draggingPlotNumber = null;
    dragOverUnit = null;
  }

  function onUnitDragOver(ev: DragEvent, unitCode: string) {
    if (!snapshot?.suWritable || !draggingPlotNumber) return;
    ev.preventDefault();
    dragOverUnit = unitCode;
    if (ev.dataTransfer) ev.dataTransfer.dropEffect = 'move';
  }

  function onUnitDrop(ev: DragEvent, unitCode: string) {
    ev.preventDefault();
    const plotNum = draggingPlotNumber || ev.dataTransfer?.getData('text/plain') || '';
    draggingPlotNumber = null;
    dragOverUnit = null;
    if (plotNum && unitCode) void handleReassignPlot(plotNum, unitCode);
  }

  onMount(() => {
    if (!initialSnapshot && effectiveContextId) void refreshAll();
  });

  onDestroy(() => {
    requestGeneration++;
    reads.cancelAll();
    onBusyChange?.(false);
  });

  const matrixSections = $derived(
    filterAndGroupSpeciesRows(snapshot, {
      searchText: speciesSearch,
      diagnosticOnly,
      grouping: matrixGrouping,
    })
  );
  const visibleOutliers = $derived(filterOutlierQueue(snapshot?.outlierQueue ?? [], outlierFilter, outlierSearch));
  const misplacedCount = $derived((snapshot?.outlierQueue ?? []).filter((item) => item.misplaced).length);
  const activePairComparison = $derived(
    findPairwiseComparison(snapshot?.pairwiseComparisons ?? [], selectedPairUnits[0], selectedPairUnits[1])
  );
  const activeEdatopicGrid = $derived.by(() => {
    if (!snapshot) return null;
    if (selectedEdatopicScope === '__OVERALL__') return snapshot.overallEdatopicGrid;
    return snapshot.unitEdatopicGrids.find((g) => g.siteUnit === selectedEdatopicScope) ?? snapshot.overallEdatopicGrid;
  });
  const edatopicRows = $derived(getEdatopicCellMatrix(activeEdatopicGrid));
  const exportValidationMessage = $derived(exportModalOpen ? validateWorkbookExportDraft(exportDraft) : '');
</script>

<section
  class="synthesis-workbench"
  data-tour="diagnostic-synthesis-root"
  aria-label="BEC Differential and Pairwise Synthesis Workbench"
>
  <SynthesisTopChrome
    {snapshot}
    {project}
    {su}
    {lastLatencyMs}
    {loading}
    {mutating}
    {options}
    {lumpOptions}
    {matrixDisplay}
    {matrixGrouping}
    {diagnosticOnly}
    {useBreakpointGrouping}
    {breakpointPolicy}
    {excludePatternsText}
    {externalLumpDbPath}
    {externalSuPath}
    {externalSuNames}
    {errorMessage}
    bind:statusNotice
    onRefresh={() => void refreshAll()}
    onUndo={() => void handleUndoReassignment()}
    onOpenExport={() => {
      lastExportResult = null;
      exportModalOpen = true;
    }}
    onUpdateOptions={updateOptions}
    onRecompute={() => void recomputeSnapshotOnly()}
    onBrowseExternalLump={() => void browseExternalLumpDatabase()}
    onBrowseExternalSU={() => void browseExternalSUFile()}
    onMatrixDisplayChange={(mode) => (matrixDisplay = mode)}
    onMatrixGroupingChange={(mode) => (matrixGrouping = mode)}
    onDiagnosticOnlyChange={(checked) => (diagnosticOnly = checked)}
    onToggleBreakpoints={(enabled, policy) => void toggleBreakpointGrouping(enabled, policy)}
    onExcludePatternsInput={applyExcludePatterns}
    onUpdatePairwiseParam={updatePairwiseParam}
    onResetPairwise={resetPairwiseDefaults}
  />

  <div class="syn-workspace-grid">
    <SynthesisPrimaryPane
      {snapshot}
      bind:activeTab
      bind:speciesSearch
      {matrixSections}
      {matrixDisplay}
      {useBreakpointGrouping}
      {breakpointPolicy}
      {breakpointRollups}
      {loading}
      bind:dragOverUnit
      bind:similarityMetric
      bind:selectedPairUnits
      {activePairComparison}
      bind:selectedEdatopicScope
      bind:inspectedEdatopicCell
      {activeEdatopicGrid}
      {edatopicRows}
      {onUnitDragOver}
      {onUnitDrop}
      {onOpenPlot}
    />

    <SynthesisOutlierQueue
      {snapshot}
      {visibleOutliers}
      {misplacedCount}
      {outlierFilter}
      {outlierSearch}
      {manualTargetByPlot}
      {mutating}
      onFilterChange={(mode) => (outlierFilter = mode)}
      onSearchChange={(val) => (outlierSearch = val)}
      onManualTargetChange={(plotNumber, val) => (manualTargetByPlot[plotNumber] = val)}
      onReassignPlot={(plotNumber, targetUnit) => void handleReassignPlot(plotNumber, targetUnit)}
      {onPlotDragStart}
      {onPlotDragEnd}
      {onOpenPlot}
    />
  </div>

  <SynthesisExportModal
    open={exportModalOpen}
    bind:draft={exportDraft}
    {exportValidationMessage}
    {lastExportResult}
    {exportingWorkbook}
    onClose={() => (exportModalOpen = false)}
    onPublish={() => void handlePublishWorkbook()}
  />
</section>

<style>
  :global(.syn-params-grid) {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 160px), 1fr));
    gap: 0.65rem;
  }

  @media (max-width: 1200px) {
    .syn-workspace-grid {
      grid-template-columns: minmax(0, 1fr);
    }
  }

  @media (max-width: 960px) {
    .syn-workspace-grid {
      grid-template-columns: minmax(0, 1fr);
    }
  }
</style>
