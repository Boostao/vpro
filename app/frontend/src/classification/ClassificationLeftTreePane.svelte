<script lang="ts">
  import {
    resolveAriaTreeKeyAction,
    type ExplorerMode,
    type FlattenedHierarchyTreeItem,
    type FlattenedSUTreeItem,
    type HierarchyExplorerView,
    type SUPlotTree,
  } from './classificationExplorer';

  interface VirtualSlice {
    startIndex: number;
    endIndex: number;
    topSpacerPx: number;
    bottomSpacerPx: number;
  }

  interface Props {
    mode: ExplorerMode;
    treeRowHeight: number;
    suFilterText: string;
    suTree: SUPlotTree | null;
    flatSUItems: FlattenedSUTreeItem[];
    suVirtualSlice: VirtualSlice;
    visibleSUItems: FlattenedSUTreeItem[];
    selectedPlots: string[];
    lastHistoryId: number;
    hierarchyView: HierarchyExplorerView | null;
    flatHierarchyItems: FlattenedHierarchyTreeItem[];
    hierVirtualSlice: VirtualSlice;
    visibleHierarchyItems: FlattenedHierarchyTreeItem[];
    selectedHierarchyNodeId: number | null;
    expandedHierarchyIds: number[];
    treeScrollTop: number;
    treeViewportHeight: number;
    mutating: boolean;
    onLoadSUTree: () => void;
    onOpenDialog: (dialog: 'new_su' | 'save_su_as' | 'su_from_env' | 'new_hierarchy' | 'save_hierarchy_as') => void;
    onUndoLast: () => void;
    onToggleSUExpand: (folderId: string) => void;
    onPlotClick: (plotNumber: string, event: MouseEvent | KeyboardEvent) => void;
    onPlotDragStart: (event: DragEvent, plotNumber: string) => void;
    onBucketDrop: (event: DragEvent, targetUnit: string | null) => void;
    onAssignPlots: (plots: string[], targetUnit: string | null) => void;
    onOpenPlot?: (plotNumber: string) => void;
    onToggleHierarchyExpand: (nodeId: number) => void;
    onSelectHierarchyNode: (nodeId: number, name: string, parentNodeId: number | null) => void;
    onToggleBreak: (nodeId: number) => void;
  }

  let {
    mode,
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
    selectedHierarchyNodeId,
    expandedHierarchyIds = $bindable(),
    treeScrollTop = $bindable(),
    treeViewportHeight = $bindable(),
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
    onSelectHierarchyNode,
    onToggleBreak,
  }: Props = $props();

  let focusedTreeItemId = $state('');
  let dragOverBucket = $state<string | null>(null);
  let treeViewportEl = $state<HTMLDivElement | null>(null);

  function handleSUTreeKeyDown(event: KeyboardEvent) {
    const action = resolveAriaTreeKeyAction(flatSUItems, focusedTreeItemId, event.key);
    if (!action) return;
    event.preventDefault();
    if (action.type === 'focus') {
      focusedTreeItemId = action.targetId;
      queueMicrotask(() => {
        treeViewportEl
          ?.querySelector<HTMLElement>(`[data-tree-item-id="${CSS.escape(action.targetId)}"]`)
          ?.focus();
      });
    } else if (action.type === 'expand' || action.type === 'collapse') {
      onToggleSUExpand(action.targetId);
    } else if (action.type === 'select') {
      const item = flatSUItems.find(i => i.id === action.targetId);
      if (!item) return;
      if (item.kind === 'plot_leaf' && item.plot) {
        onPlotClick(item.plot.plotNumber, event);
      } else {
        onToggleSUExpand(item.id);
      }
    }
  }

  function handleHierarchyTreeKeyDown(event: KeyboardEvent) {
    const mapped = flatHierarchyItems.map(i => ({
      id: i.id,
      parentId: i.parentItemId,
      expandable: i.expandable,
      expanded: i.expanded,
    }));
    const action = resolveAriaTreeKeyAction(mapped, focusedTreeItemId, event.key);
    if (!action) return;
    event.preventDefault();
    const targetItem = flatHierarchyItems.find(i => i.id === action.targetId);
    if (!targetItem) return;
    if (action.type === 'focus') {
      focusedTreeItemId = action.targetId;
      onSelectHierarchyNode(targetItem.nodeId, targetItem.name, targetItem.parentNodeId);
      queueMicrotask(() => {
        treeViewportEl
          ?.querySelector<HTMLElement>(`[data-tree-item-id="${CSS.escape(action.targetId)}"]`)
          ?.focus();
      });
    } else if (action.type === 'expand' || action.type === 'collapse') {
      onToggleHierarchyExpand(targetItem.nodeId);
    } else if (action.type === 'select') {
      onSelectHierarchyNode(targetItem.nodeId, targetItem.name, targetItem.parentNodeId);
    }
  }
</script>

<section class="vpro-cls-left-pane" aria-label="Classification Tree">
  {#if mode === 'su_tree'}
    <div class="vpro-cls-subtoolbar">
      <input
        type="search"
        class="vpro-cls-filter"
        placeholder="Filter units or plots..."
        bind:value={suFilterText}
        onkeydown={e => {
          if (e.key === 'Enter') onLoadSUTree();
        }}
      />
      <button type="button" class="vpro-btn-secondary" onclick={onLoadSUTree}>Filter</button>
      <button type="button" class="vpro-btn-secondary" onclick={() => onOpenDialog('new_su')}>New SU</button>
      <button type="button" class="vpro-btn-secondary" onclick={() => onOpenDialog('save_su_as')}>Save As</button>
      <button type="button" class="vpro-btn-secondary" onclick={() => onOpenDialog('su_from_env')}>SU from Env</button>
      {#if lastHistoryId > 0}
        <button type="button" class="vpro-btn-secondary" disabled={mutating} onclick={onUndoLast}>Undo</button>
      {/if}
    </div>

    {#if suTree}
      <p class="vpro-cls-counts">
        <strong>{suTree.units.length}</strong> Site Units ·
        <strong>{suTree.totalAssigned}</strong> Assigned ·
        <strong>{suTree.totalUnassigned}</strong> Unassigned ·
        <strong>{selectedPlots.length}</strong> Selected
      </p>
    {/if}

    <div
      class="vpro-cls-tree-viewport"
      bind:this={treeViewportEl}
      bind:clientHeight={treeViewportHeight}
      onscroll={e => {
        treeScrollTop = e.currentTarget.scrollTop;
      }}
    >
      <div role="tree" aria-label="Site Unit to Plots Assignment Tree" aria-multiselectable="true" tabindex="-1" onkeydown={handleSUTreeKeyDown}>
        {#if suVirtualSlice.topSpacerPx > 0}
          <div style={`height:${suVirtualSlice.topSpacerPx}px;`} aria-hidden="true"></div>
        {/if}

        {#each visibleSUItems as item (item.id)}
          {#if item.kind === 'unit_folder' || item.kind === 'unassigned_folder'}
            <div
              role="treeitem"
              tabindex={focusedTreeItemId === item.id || !focusedTreeItemId ? 0 : -1}
              data-tree-item-id={item.id}
              aria-level={1}
              aria-expanded={item.expandable ? item.expanded : undefined}
              aria-selected={false}
              class="vpro-tree-folder"
              class:drop-target={dragOverBucket === item.id}
              class:unassigned={item.kind === 'unassigned_folder'}
              style={`height:${treeRowHeight}px;`}
              onfocus={() => (focusedTreeItemId = item.id)}
              onclick={() => onToggleSUExpand(item.id)}
              onkeydown={e => {
                if (e.key === 'Enter' || e.key === ' ') {
                  e.preventDefault();
                  onToggleSUExpand(item.id);
                }
              }}
              ondragover={e => {
                e.preventDefault();
                dragOverBucket = item.id;
              }}
              ondragleave={() => {
                if (dragOverBucket === item.id) dragOverBucket = null;
              }}
              ondrop={e => {
                dragOverBucket = null;
                onBucketDrop(e, item.unitCode);
              }}
            >
              <span class="vpro-tree-caret">{item.expandable ? (item.expanded ? '[-]' : '[+]') : '[ ]'}</span>
              <span class="vpro-tree-unit-badge">{item.kind === 'unit_folder' ? 'U' : '0'}</span>
              <strong class="mono">{item.label}</strong>
              {#if item.subtitle}<span class="vpro-tree-sub">{item.subtitle}</span>{/if}
              <span class="vpro-tree-count">{item.count ?? 0}</span>
              {#if selectedPlots.length > 0}
                <button
                  type="button"
                  class="vpro-btn-mini"
                  onclick={e => {
                    e.stopPropagation();
                    onAssignPlots(selectedPlots, item.unitCode);
                  }}
                >
                  Move ({selectedPlots.length}) Here
                </button>
              {/if}
            </div>
          {:else if item.plot}
            {@const isSelected = selectedPlots.includes(item.plot.plotNumber)}
            <div
              role="treeitem"
              tabindex={focusedTreeItemId === item.id ? 0 : -1}
              data-tree-item-id={item.id}
              aria-level={2}
              aria-selected={isSelected}
              draggable="true"
              class="vpro-tree-leaf"
              class:selected={isSelected}
              style={`height:${treeRowHeight}px;`}
              onfocus={() => (focusedTreeItemId = item.id)}
              onclick={e => onPlotClick(item.plot!.plotNumber, e)}
              onkeydown={e => {
                if (e.key === 'Enter' || e.key === ' ') {
                  e.preventDefault();
                  onPlotClick(item.plot!.plotNumber, e);
                }
              }}
              ondragstart={e => onPlotDragStart(e, item.plot!.plotNumber)}
            >
              <span class="vpro-tree-leaf-tag">P</span>
              <span class="mono">{item.label}</span>
              <span class="vpro-tree-sub">{item.subtitle}</span>
              {#if onOpenPlot}
                <button
                  type="button"
                  class="vpro-btn-mini"
                  onclick={e => {
                    e.stopPropagation();
                    onOpenPlot(item.plot!.plotNumber);
                  }}
                >
                  Open
                </button>
              {/if}
            </div>
          {/if}
        {/each}

        {#if suVirtualSlice.bottomSpacerPx > 0}
          <div style={`height:${suVirtualSlice.bottomSpacerPx}px;`} aria-hidden="true"></div>
        {/if}
      </div>
    </div>
  {:else}
    <div class="vpro-cls-subtoolbar">
      <button type="button" class="vpro-btn-secondary" onclick={() => onOpenDialog('new_hierarchy')}>New Hierarchy</button>
      <button type="button" class="vpro-btn-secondary" onclick={() => onOpenDialog('save_hierarchy_as')}>Save Hierarchy As</button>
      <button type="button" class="vpro-btn-secondary" onclick={() => { expandedHierarchyIds = (hierarchyView?.flatNodes ?? []).map(n => n.id); }}>Expand All</button>
      <button type="button" class="vpro-btn-secondary" onclick={() => { expandedHierarchyIds = []; }}>Collapse All</button>
    </div>

    {#if hierarchyView}
      <p class="vpro-cls-counts">
        <strong>{hierarchyView.diagnostics.totalNodes}</strong> Nodes ·
        <strong>{hierarchyView.diagnostics.breakpointNodes}</strong> Breakpoints (~) ·
        <strong>{hierarchyView.diagnostics.cycleNodeIds.length}</strong> Cycles
      </p>
    {/if}

    <div
      class="vpro-cls-tree-viewport"
      bind:this={treeViewportEl}
      bind:clientHeight={treeViewportHeight}
      onscroll={e => {
        treeScrollTop = e.currentTarget.scrollTop;
      }}
    >
      <div role="tree" aria-label="Phytosociological Classification Hierarchy Tree" tabindex="-1" onkeydown={handleHierarchyTreeKeyDown}>
        {#if hierVirtualSlice.topSpacerPx > 0}
          <div style={`height:${hierVirtualSlice.topSpacerPx}px;`} aria-hidden="true"></div>
        {/if}

        {#each visibleHierarchyItems as item (item.id)}
          <div
            role="treeitem"
            tabindex={focusedTreeItemId === item.id || !focusedTreeItemId ? 0 : -1}
            data-tree-item-id={item.id}
            aria-level={item.depth}
            aria-expanded={item.expandable ? item.expanded : undefined}
            aria-selected={selectedHierarchyNodeId === item.nodeId}
            class="vpro-tree-hnode"
            class:selected={selectedHierarchyNodeId === item.nodeId}
            class:breakpoint={item.isBreakpoint}
            style={`height:${treeRowHeight}px;padding-left:${(item.depth - 1) * 18 + 8}px;`}
            onfocus={() => (focusedTreeItemId = item.id)}
            onclick={() => onSelectHierarchyNode(item.nodeId, item.name, item.parentNodeId)}
            onkeydown={e => {
              if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                onSelectHierarchyNode(item.nodeId, item.name, item.parentNodeId);
              }
            }}
          >
            {#if item.expandable}
              <button
                type="button"
                class="vpro-tree-caret-btn"
                aria-label={item.expanded ? 'Collapse branch' : 'Expand branch'}
                onclick={e => {
                  e.stopPropagation();
                  onToggleHierarchyExpand(item.nodeId);
                }}
              >
                {item.expanded ? '[-]' : '[+]'}
              </button>
            {:else}
              <span class="vpro-tree-caret">[ ]</span>
            {/if}
            <span class="vpro-rank-badge">{item.rankName}</span>
            <span class="mono">{item.name}</span>
            <button
              type="button"
              class="vpro-tilde-btn"
              class:active={item.isBreakpoint}
              title="Toggle '~' Report Breakpoint"
              disabled={mutating}
              onclick={e => {
                e.stopPropagation();
                onToggleBreak(item.nodeId);
              }}
            >
              ~ Break
            </button>
          </div>
        {/each}

        {#if hierVirtualSlice.bottomSpacerPx > 0}
          <div style={`height:${hierVirtualSlice.bottomSpacerPx}px;`} aria-hidden="true"></div>
        {/if}
      </div>
    </div>
  {/if}
</section>
