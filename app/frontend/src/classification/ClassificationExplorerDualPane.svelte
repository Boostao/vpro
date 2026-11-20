<script lang="ts">
  import ClassificationFlatRankTab from './ClassificationFlatRankTab.svelte';
  import ClassificationHierarchyNodePanel from './ClassificationHierarchyNodePanel.svelte';
  import ClassificationLeftTreePane from './ClassificationLeftTreePane.svelte';
  import ClassificationPlotInspectorPane from './ClassificationPlotInspectorPane.svelte';
  import type {
    ClassificationBackendPort,
    ExplorerMode,
    FlattenedHierarchyTreeItem,
    FlatHierarchyRow,
    FlattenedSUTreeItem,
    HierarchyExplorerNode,
    HierarchyExplorerView,
    PlotInspectorSummary,
    SUPlotTree,
  } from './classificationExplorer';

  interface VirtualWindowSlice {
    startIndex: number;
    endIndex: number;
    topSpacerPx: number;
    bottomSpacerPx: number;
  }

  let {
    mode,
    flatDraftRows = $bindable(),
    flatDirty = $bindable(),
    flatValidationError,
    onSaveFlatRows,
    treeRowHeight,
    suFilterText = $bindable(),
    suTree,
    flatSUItems,
    suVirtualSlice,
    visibleSUItems,
    selectedPlots,
    lastHistoryId,
    hierarchyView,
    flatHierarchyItems,
    hierVirtualSlice,
    visibleHierarchyItems,
    selectedHierarchyNodeId = $bindable(),
    selectedHierarchyNode,
    expandedHierarchyIds = $bindable(),
    renameDraft = $bindable(),
    reparentTargetId = $bindable(),
    treeScrollTop = $bindable(),
    treeViewportHeight = $bindable(),
    effectiveContextId,
    project,
    port,
    inspectedPlot,
    mutating,
    onLoadSUTree,
    onOpenDialog,
    onUndoLast,
    onToggleSUExpand,
    onPlotClick,
    onPlotDragStart,
    onBucketDrop,
    onAssignPlots,
    onOpenPlot,
    onToggleHierarchyExpand,
    onToggleBreak,
    onRequestSUSync,
    onMutatingChange,
    onError,
    onStatus,
    onReloadHierarchy,
  }: {
    mode: ExplorerMode;
    flatDraftRows: FlatHierarchyRow[];
    flatDirty: boolean;
    flatValidationError: string;
    onSaveFlatRows: () => Promise<void>;
    treeRowHeight: number;
    suFilterText: string;
    suTree: SUPlotTree | null;
    flatSUItems: FlattenedSUTreeItem[];
    suVirtualSlice: VirtualWindowSlice;
    visibleSUItems: FlattenedSUTreeItem[];
    selectedPlots: string[];
    lastHistoryId: number;
    hierarchyView: HierarchyExplorerView | null;
    flatHierarchyItems: FlattenedHierarchyTreeItem[];
    hierVirtualSlice: VirtualWindowSlice;
    visibleHierarchyItems: FlattenedHierarchyTreeItem[];
    selectedHierarchyNodeId: number | null;
    selectedHierarchyNode: HierarchyExplorerNode | null;
    expandedHierarchyIds: number[];
    renameDraft: string;
    reparentTargetId: string;
    treeScrollTop: number;
    treeViewportHeight: number;
    effectiveContextId: string;
    project: string;
    port: ClassificationBackendPort;
    inspectedPlot: PlotInspectorSummary | null;
    mutating: boolean;
    onLoadSUTree: () => Promise<void>;
    onOpenDialog: (d: 'new_su' | 'save_su_as' | 'su_from_env' | 'new_hierarchy' | 'save_hierarchy_as') => void;
    onUndoLast: () => Promise<void>;
    onToggleSUExpand: (folderId: string) => void;
    onPlotClick: (plotNumber: string, event: MouseEvent | KeyboardEvent) => void;
    onPlotDragStart: (event: DragEvent, plotNumber: string) => void;
    onBucketDrop: (event: DragEvent, targetUnit: string | null) => void;
    onAssignPlots: (plots: string[], targetUnit: string | null) => Promise<void>;
    onOpenPlot?: (plotNumber: string) => void;
    onToggleHierarchyExpand: (nodeId: number) => void;
    onToggleBreak: (nodeId: number) => Promise<void>;
    onRequestSUSync?: (direction: 'su_to_env' | 'env_to_su') => void;
    onMutatingChange: (v: boolean) => void;
    onError: (msg: string) => void;
    onStatus: (msg: string) => void;
    onReloadHierarchy: () => Promise<void>;
  } = $props();
</script>

{#if mode === 'hierarchy_flat'}
  <ClassificationFlatRankTab
    bind:flatDraftRows
    bind:flatDirty
    {flatValidationError}
    {mutating}
    {onOpenDialog}
    {onSaveFlatRows}
  />
{:else}
  <div class="vpro-cls-dual-grid">
    <ClassificationLeftTreePane
      {mode}
      {treeRowHeight}
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
      {onLoadSUTree}
      {onOpenDialog}
      {onUndoLast}
      {onToggleSUExpand}
      {onPlotClick}
      {onPlotDragStart}
      {onBucketDrop}
      {onAssignPlots}
      {onOpenPlot}
      {onToggleHierarchyExpand}
      onSelectHierarchyNode={(id, name, pid) => {
        selectedHierarchyNodeId = id;
        renameDraft = name;
        reparentTargetId = pid === null ? '' : String(pid);
      }}
      {onToggleBreak}
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
          onAssignPlots={(plots, unit) => void onAssignPlots(plots, unit)}
          {onMutatingChange}
          {onError}
          {onStatus}
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
          {onMutatingChange}
          {onError}
          {onStatus}
          onClearSelection={() => (selectedHierarchyNodeId = null)}
          {onReloadHierarchy}
        />
      {/if}
    </section>
  </div>
{/if}
