<script lang="ts">
  import { onDestroy, onMount, tick, untrack } from 'svelte';
  import { ReadRequests } from '../shared/readRequests';
  import { computeVirtualWindow } from '../datasheet/universalDatasheetGrid';
  import SiteUnitExclusionFilter from './SiteUnitExclusionFilter.svelte';
  import ClassificationDialogs from './ClassificationDialogs.svelte';
  import ClassificationLeftTreePane from './ClassificationLeftTreePane.svelte';
  import ClassificationPlotInspectorPane from './ClassificationPlotInspectorPane.svelte';
  import ClassificationHierarchyNodePanel from './ClassificationHierarchyNodePanel.svelte';
  import ClassificationFlatRankTab from './ClassificationFlatRankTab.svelte';
  import {
    defaultClassificationBackendPort,
    flattenVisibleHierarchyTree,
    flattenVisibleSUTree,
    UNASSIGNED_BUCKET_ID,
    validateFlatHierarchyRows,
    type ClassificationBackendPort,
    type ExplorerMode,
    type FlatHierarchyRow,
    type HierarchyExplorerView,
    type PlotInspectorSummary,
    type SUPlotTree,
  } from './classificationExplorer';

  interface Props {
    contextId: string;
    project?: string;
    su?: string;
    hierarchy?: string;
    initialMode?: ExplorerMode;
    operationHeld?: boolean;
    port?: ClassificationBackendPort;
    onBusyChange?: (busy: boolean) => void;
    onDirtyChange?: (dirty: boolean) => void;
    onContextChanged?: (nextContextId: string, newState: unknown) => void;
    onOpenPlot?: (plotNumber: string) => void;
    onRequestSUSync?: (direction: 'su_to_env' | 'env_to_su') => void;
  }

  let {
    contextId,
    project = '',
    su = 'None',
    hierarchy = 'None',
    initialMode = 'su_tree',
    operationHeld = false,
    port = defaultClassificationBackendPort,
    onBusyChange,
    onDirtyChange,
    onContextChanged,
    onOpenPlot,
    onRequestSUSync,
  }: Props = $props();

  const reads = new ReadRequests();
  const TREE_ROW_HEIGHT = 34;

  let mode = $state<ExplorerMode>(untrack(() => initialMode));
  let effectiveContextId = $state(untrack(() => contextId));
  let prevPropContextId = untrack(() => contextId);

  $effect(() => {
    if (contextId && contextId !== prevPropContextId) {
      prevPropContextId = contextId;
      if (contextId !== effectiveContextId) {
        effectiveContextId = contextId;
        void reloadActivePane();
      }
    }
  });

  // Left pane SU Tree state
  let suTree = $state.raw<SUPlotTree | null>(null);
  let suFilterText = $state('');
  let expandedSUIds = $state<string[]>([UNASSIGNED_BUCKET_ID]);
  let selectedPlots = $state<string[]>([]);
  let lastClickedPlot = $state('');
  let lastHistoryId = $state(0);

  // Virtualized scroll state for tree pane
  let treeScrollTop = $state(0);
  let treeViewportHeight = $state(480);
  let explorerEl = $state<HTMLElement | null>(null);

  // Right pane Plot Inspector & Exclusion filter state
  let inspectedPlot = $state.raw<PlotInspectorSummary | null>(null);
  let exclusionBusy = $state(false);

  // Create SU & modal dialogs
  let activeDialog = $state<
    'none' | 'new_su' | 'save_su_as' | 'su_from_env' | 'new_hierarchy' | 'save_hierarchy_as'
  >('none');
  let newSUName = $state('');
  let newSUDestination = $state<'project' | 'new_file'>('project');
  let newSUFilePath = $state('');
  let populateAllPlots = $state(true);
  let seedFromUserSU = $state(false);

  // Hierarchy explorer & inspector state
  let hierarchyView = $state.raw<HierarchyExplorerView | null>(null);
  let expandedHierarchyIds = $state<number[]>([]);
  let selectedHierarchyNodeId = $state<number | null>(null);
  let renameDraft = $state('');
  let reparentTargetId = $state<string>('');

  // Wide Flat Phytosociological Rank Editor state
  let flatDraftRows = $state<FlatHierarchyRow[]>([]);
  let flatDirty = $state(false);

  let busy = $state(false);
  let mutating = $state(false);
  let errorMessage = $state('');
  let statusBanner = $state('');

  let generation = 0;

  const flatSUItems = $derived(flattenVisibleSUTree(suTree, new Set(expandedSUIds)));
  const suVirtualSlice = $derived(
    computeVirtualWindow(treeScrollTop, treeViewportHeight, TREE_ROW_HEIGHT, flatSUItems.length, 8)
  );
  const visibleSUItems = $derived(
    flatSUItems.slice(suVirtualSlice.startIndex, suVirtualSlice.endIndex)
  );

  const flatHierarchyItems = $derived(
    flattenVisibleHierarchyTree(hierarchyView?.roots ?? [], new Set(expandedHierarchyIds))
  );
  const hierVirtualSlice = $derived(
    computeVirtualWindow(
      treeScrollTop,
      treeViewportHeight,
      TREE_ROW_HEIGHT,
      flatHierarchyItems.length,
      8
    )
  );
  const visibleHierarchyItems = $derived(
    flatHierarchyItems.slice(hierVirtualSlice.startIndex, hierVirtualSlice.endIndex)
  );

  const flatValidationError = $derived(flatDirty ? validateFlatHierarchyRows(flatDraftRows) : '');
  const selectedHierarchyNode = $derived(
    hierarchyView?.flatNodes.find(n => n.id === selectedHierarchyNodeId) ?? null
  );

  $effect(() => {
    onBusyChange?.(busy || mutating || flatDirty || !!flatValidationError || exclusionBusy);
    onDirtyChange?.(!busy && !mutating && flatDirty);
  });

  function formatExplorerError(cause: unknown): string {
    return String(cause ?? '').replace(/(?:RuntimeError|Error):\s*/gi, '').trim();
  }

  async function reloadActivePane() {
    if (!effectiveContextId) return;
    if (mode === 'su_tree') {
      await loadSUTreeAndPicker();
    } else {
      await loadHierarchy();
    }
  }

  async function loadSUTreeAndPicker() {
    if (!effectiveContextId) return;
    generation++;
    const reqGen = generation;
    reads.cancelAll();
    busy = true;
    errorMessage = '';
    try {
      const tree = await reads.track(port.getSUPlotTree(effectiveContextId, suFilterText));
      if (reqGen !== generation) return;
      suTree = tree;
      if (expandedSUIds.length <= 1 && tree.units.length > 0) {
        expandedSUIds = [
          UNASSIGNED_BUCKET_ID,
          ...tree.units.slice(0, 5).map(u => `unit::${u.siteUnit}`),
        ];
      }
    } catch (err) {
      if (reqGen === generation) errorMessage = formatExplorerError(err);
    } finally {
      if (reqGen === generation) busy = false;
    }
  }

  async function inspectPlot(plotNumber: string) {
    if (!effectiveContextId || !plotNumber) return;
    try {
      inspectedPlot = await reads.track(
        port.getPlotInspectorSummary(effectiveContextId, plotNumber)
      );
    } catch (err) {
      errorMessage = `Plot inspector failed: ${formatExplorerError(err)}`;
    }
  }

  async function loadHierarchy() {
    if (!effectiveContextId) return;
    generation++;
    const reqGen = generation;
    reads.cancelAll();
    busy = true;
    errorMessage = '';
    try {
      const view = await reads.track(port.getHierarchyExplorer(effectiveContextId));
      if (reqGen !== generation) return;
      hierarchyView = view;
      if (expandedHierarchyIds.length === 0 && view.flatNodes.length > 0) {
        expandedHierarchyIds = view.flatNodes.filter(n => n.depth <= 2).map(n => n.id);
      }
      flatDraftRows = (view.flatRankRows ?? []).map(r => ({ ...r }));
      flatDirty = false;
    } catch (err) {
      if (reqGen === generation) errorMessage = formatExplorerError(err);
    } finally {
      if (reqGen === generation) busy = false;
    }
  }

  function toggleSUExpand(folderId: string) {
    expandedSUIds = expandedSUIds.includes(folderId)
      ? expandedSUIds.filter(id => id !== folderId)
      : [...expandedSUIds, folderId];
  }

  function handlePlotClick(plotNumber: string, event: MouseEvent | KeyboardEvent) {
    if (event.ctrlKey || event.metaKey) {
      selectedPlots = selectedPlots.includes(plotNumber)
        ? selectedPlots.filter(p => p !== plotNumber)
        : [...selectedPlots, plotNumber];
    } else if (event.shiftKey && lastClickedPlot) {
      const leafPlots = flatSUItems
        .filter(i => i.kind === 'plot_leaf' && i.plot)
        .map(i => i.plot!.plotNumber);
      const a = leafPlots.indexOf(lastClickedPlot);
      const b = leafPlots.indexOf(plotNumber);
      if (a >= 0 && b >= 0) {
        const [lo, hi] = a < b ? [a, b] : [b, a];
        selectedPlots = Array.from(new Set([...selectedPlots, ...leafPlots.slice(lo, hi + 1)]));
      } else {
        selectedPlots = [plotNumber];
      }
    } else {
      selectedPlots = [plotNumber];
    }
    lastClickedPlot = plotNumber;
    void inspectPlot(plotNumber);
  }

  async function assignPlots(plotsToMove: string[], targetUnit: string | null) {
    if (plotsToMove.length === 0 || mutating) return;
    mutating = true;
    errorMessage = '';
    try {
      const res = await port.assignPlotsToSiteUnit(effectiveContextId, {
        plotNumbers: $state.snapshot(plotsToMove),
        targetSiteUnit: targetUnit,
        removeFromSuWhenUnassigned: false,
      });
      lastHistoryId = res.historyId;
      if (res.changedPlots === 0) {
        statusBanner = targetUnit
          ? `0 plot(s) changed in ${res.tableName} (plots are already assigned to ${targetUnit}, or the active Site Unit table is read-only/master).`
          : `0 plot(s) changed in ${res.tableName} (plots are already unassigned, or the active Site Unit table is read-only/master).`;
      } else {
        statusBanner = targetUnit
          ? `Assigned ${res.changedPlots} plot(s) to ${targetUnit}.`
          : `Moved ${res.changedPlots} plot(s) to Unassigned.`;
      }
      await loadSUTreeAndPicker();
      if (inspectedPlot && plotsToMove.includes(inspectedPlot.plotNumber)) {
        await inspectPlot(inspectedPlot.plotNumber);
      }
    } catch (err) {
      errorMessage = `Plot assignment failed: ${formatExplorerError(err)}`;
    } finally {
      mutating = false;
    }
  }

  async function undoLastAssignment() {
    if (mutating) return;
    mutating = true;
    errorMessage = '';
    try {
      const res = await port.undoSUAssignment(effectiveContextId, lastHistoryId);
      lastHistoryId = 0;
      statusBanner = `Reverted ${res.changedPlots} plot assignment(s).`;
      await loadSUTreeAndPicker();
    } catch (err) {
      errorMessage = `Undo failed: ${formatExplorerError(err)}`;
    } finally {
      mutating = false;
    }
  }

  function handlePlotDragStart(event: DragEvent, plotNumber: string) {
    const batch = selectedPlots.includes(plotNumber) ? selectedPlots : [plotNumber];
    selectedPlots = batch;
    event.dataTransfer?.setData('application/x-vpro-plots', JSON.stringify(batch));
    event.dataTransfer?.setData('text/plain', batch.join(','));
  }

  function handleBucketDrop(event: DragEvent, targetUnit: string | null) {
    event.preventDefault();
    const raw = event.dataTransfer?.getData('application/x-vpro-plots');
    let batch: string[] = [];
    if (raw) {
      try {
        batch = JSON.parse(raw);
      } catch {
        batch = [];
      }
    }
    if (batch.length === 0) batch = selectedPlots;
    if (batch.length > 0) void assignPlots(batch, targetUnit);
  }

  function toggleHierarchyExpand(nodeId: number) {
    expandedHierarchyIds = expandedHierarchyIds.includes(nodeId)
      ? expandedHierarchyIds.filter(id => id !== nodeId)
      : [...expandedHierarchyIds, nodeId];
  }

  async function submitCreateSU() {
    if (!newSUName.trim() || mutating) return;
    if (newSUDestination === 'new_file' && !newSUFilePath.trim()) {
      errorMessage = 'Enter or browse an external .db file path for the new SU table.';
      return;
    }
    mutating = true;
    errorMessage = '';
    try {
      const res = await port.createSUTable(effectiveContextId, {
        name: newSUName.trim(),
        destination: newSUDestination,
        filePath: newSUDestination === 'new_file' ? newSUFilePath.trim() : '',
        populateAllProjectPlots: populateAllPlots,
        seedFromUserSiteUnit: seedFromUserSU,
        activate: true,
      });
      if (res.activated) {
        effectiveContextId = res.contextId;
        onContextChanged?.(res.contextId, res.newState);
      }
      activeDialog = 'none';
      newSUName = '';
      newSUFilePath = '';
      newSUDestination = 'project';
      statusBanner = `Created and activated ${res.tableName} (${res.plotCount} plot(s)).`;
      await loadSUTreeAndPicker();
    } catch (err) {
      errorMessage = `Create SU failed: ${formatExplorerError(err)}`;
    } finally {
      mutating = false;
    }
  }

  async function submitToggleBreak(nodeId: number) {
    if (mutating) return;
    mutating = true;
    errorMessage = '';
    try {
      const res = await port.toggleHierarchyBreakpoint(effectiveContextId, nodeId);
      statusBanner = `Updated breakpoint status: ${res.nodeName}.`;
      await loadHierarchy();
    } catch (err) {
      errorMessage = `Breakpoint toggle failed: ${formatExplorerError(err)}`;
    } finally {
      mutating = false;
    }
  }

  async function submitSaveFlatRows() {
    if (mutating || flatValidationError) return;
    mutating = true;
    errorMessage = '';
    try {
      const res = await port.saveFlatHierarchyRows(effectiveContextId, {
        rows: $state.snapshot(flatDraftRows),
      });
      flatDirty = false;
      statusBanner = `Synchronized ${res.affectedRows} hierarchy node(s) from flat phytosociological table.`;
      await loadHierarchy();
    } catch (err) {
      errorMessage = `Save Flat Hierarchy failed: ${formatExplorerError(err)}`;
    } finally {
      mutating = false;
    }
  }

  async function focusExplorerFilter() {
    const existing = explorerEl?.querySelector<HTMLInputElement>('input.vpro-cls-filter');
    if (existing) {
      existing.focus();
      existing.select?.();
      return;
    }
    if (mode !== 'su_tree' && !flatDirty && !mutating) {
      mode = 'su_tree';
      treeScrollTop = 0;
      void loadSUTreeAndPicker();
      await tick();
      const input = explorerEl?.querySelector<HTMLInputElement>('input.vpro-cls-filter');
      input?.focus();
      input?.select?.();
    }
  }

  function handleWindowKeydown(event: KeyboardEvent) {
    if ((event.ctrlKey || event.metaKey) && !event.altKey && !event.shiftKey && event.key.toLowerCase() === 'f') {
      if (activeDialog !== 'none') return;
      event.preventDefault();
      void focusExplorerFilter();
    }
  }

  onMount(() => {
    if (effectiveContextId) void reloadActivePane();
  });

  onDestroy(() => {
    generation++;
    reads.cancelAll();
    onDirtyChange?.(false);
    onBusyChange?.(false);
  });
</script>

<svelte:window onkeydown={handleWindowKeydown} />

<section
  bind:this={explorerEl}
  class="vpro-cls-explorer"
  data-tour="classification-explorer-root"
  aria-label="Dual-Pane Classification Explorer"
>
  <header class="vpro-cls-header">
    <div>
      <p class="vpro-cls-eyebrow">BEC CLASSIFICATION WORKBENCH</p>
      <h2 class="vpro-cls-title">
        Classification Explorer
        {#if project}<span class="vpro-cls-pill">Project: {project}</span>{/if}
        <span class="vpro-cls-pill">SU: {suTree?.su || su}</span>
        <span class="vpro-cls-pill">Hierarchy: {hierarchyView?.hierarchy || hierarchy}</span>
      </h2>
    </div>

    <div class="vpro-cls-mode-bar" role="tablist" aria-label="Classification Explorer Views">
      <button
        type="button"
        role="tab"
        aria-selected={mode === 'su_tree'}
        class="vpro-cls-mode-btn"
        class:active={mode === 'su_tree'}
        onclick={() => {
          mode = 'su_tree';
          treeScrollTop = 0;
          void loadSUTreeAndPicker();
        }}
      >
        SU -&gt; Plots Tree
      </button>
      <button
        type="button"
        role="tab"
        aria-selected={mode === 'hierarchy_tree'}
        class="vpro-cls-mode-btn"
        class:active={mode === 'hierarchy_tree'}
        onclick={() => {
          mode = 'hierarchy_tree';
          treeScrollTop = 0;
          void loadHierarchy();
        }}
      >
        Hierarchy Tree (~)
      </button>
      <button
        type="button"
        role="tab"
        aria-selected={mode === 'hierarchy_flat'}
        class="vpro-cls-mode-btn"
        class:active={mode === 'hierarchy_flat'}
        onclick={() => {
          mode = 'hierarchy_flat';
          void loadHierarchy();
        }}
      >
        Flat Rank Table
      </button>
    </div>
  </header>

  {#if operationHeld}
    <p role="status" class="vpro-cls-status">Sync/operation in progress — some edits are queued.</p>
  {/if}
  {#if errorMessage}
    <p role="alert" class="vpro-cls-alert">{formatExplorerError(errorMessage)}</p>
  {/if}
  {#if statusBanner}
    <p role="status" class="vpro-cls-status">{statusBanner}</p>
  {/if}

  <ClassificationDialogs
    {activeDialog}
    {effectiveContextId}
    activeHierarchy={hierarchyView?.hierarchy ?? ''}
    {port}
    {mutating}
    bind:newSUName
    bind:newSUDestination
    bind:newSUFilePath
    bind:populateAllPlots
    bind:seedFromUserSU
    onClose={() => (activeDialog = 'none')}
    onSubmitCreateSU={submitCreateSU}
    onMutatingChange={v => (mutating = v)}
    onError={msg => (errorMessage = formatExplorerError(msg))}
    onStatus={msg => (statusBanner = msg)}
    onActivated={(cid, st) => {
      effectiveContextId = cid;
      onContextChanged?.(cid, st);
    }}
    onReloadSU={loadSUTreeAndPicker}
    onReloadHierarchy={loadHierarchy}
  />

  {#if mode === 'hierarchy_flat'}
    <ClassificationFlatRankTab
      bind:flatDraftRows
      bind:flatDirty
      {flatValidationError}
      {mutating}
      onOpenDialog={d => (activeDialog = d)}
      onSaveFlatRows={submitSaveFlatRows}
    />
  {:else}
    <div class="vpro-cls-dual-grid">
      <ClassificationLeftTreePane
        {mode}
        treeRowHeight={TREE_ROW_HEIGHT}
        bind:suFilterText
        {suTree}
        {flatSUItems}
        {suVirtualSlice}
        {visibleSUItems}
        {selectedPlots}
        {lastHistoryId}
        {hierarchyView}
        {flatHierarchyItems}
        {hierVirtualSlice}
        {visibleHierarchyItems}
        {selectedHierarchyNodeId}
        bind:expandedHierarchyIds
        bind:treeScrollTop
        bind:treeViewportHeight
        {mutating}
        onLoadSUTree={loadSUTreeAndPicker}
        onOpenDialog={d => (activeDialog = d)}
        onUndoLast={undoLastAssignment}
        onToggleSUExpand={toggleSUExpand}
        onPlotClick={handlePlotClick}
        onPlotDragStart={handlePlotDragStart}
        onBucketDrop={handleBucketDrop}
        onAssignPlots={assignPlots}
        {onOpenPlot}
        onToggleHierarchyExpand={toggleHierarchyExpand}
        onSelectHierarchyNode={(id, name, pid) => {
          selectedHierarchyNodeId = id;
          renameDraft = name;
          reparentTargetId = pid === null ? '' : String(pid);
        }}
        onToggleBreak={submitToggleBreak}
      />

      <section class="vpro-cls-right-pane" aria-label="Inspector and Editors">
        {#if mode === 'su_tree'}
          <ClassificationPlotInspectorPane
            {effectiveContextId}
            {project}
            {port}
            {inspectedPlot}
            {selectedPlots}
            {mutating}
            {onRequestSUSync}
            onAssignPlots={assignPlots}
            onMutatingChange={v => (mutating = v)}
            onError={msg => (errorMessage = formatExplorerError(msg))}
            onStatus={msg => (statusBanner = msg)}
          />
        {:else}
          <ClassificationHierarchyNodePanel
            {effectiveContextId}
            {port}
            {hierarchyView}
            {selectedHierarchyNodeId}
            {selectedHierarchyNode}
            bind:expandedHierarchyIds
            bind:renameDraft
            bind:reparentTargetId
            {mutating}
            onMutatingChange={v => (mutating = v)}
            onError={msg => (errorMessage = formatExplorerError(msg))}
            onStatus={msg => (statusBanner = msg)}
            onClearSelection={() => (selectedHierarchyNodeId = null)}
            onReloadHierarchy={loadHierarchy}
          />
        {/if}
      </section>
    </div>
  {/if}

  {#if effectiveContextId}
    <details class="vpro-cls-exclusion-drawer">
      <summary class="vpro-cls-exclusion-summary">
        Site Unit Exclusion Rules (~ Breakpoints &amp; Report Filters)
      </summary>
      <div class="vpro-cls-exclusion-body">
        <SiteUnitExclusionFilter
          contextId={effectiveContextId}
          su={suTree?.su || su}
          hierarchy={hierarchyView?.hierarchy || (hierarchy && hierarchy !== 'None' ? hierarchy : '') || 'None'}
          reportMode="summary"
          onBusyChange={val => (exclusionBusy = val)}
        />
      </div>
    </details>
  {/if}
</section>

<style>
  :global(.table-scroll) {
    overflow-x: auto;
    max-width: 100%;
  }

  @media (max-width: 960px) {
    :global(.vpro-cls-dual-grid) {
      grid-template-columns: minmax(0, 1fr);
    }
  }
</style>
