<script lang="ts">
  import { formatError } from '../shared/readRequests';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import {
    wouldIntroduceHierarchyCycle,
    type ClassificationBackendPort,
    type HierarchyExplorerNode,
    type HierarchyExplorerView,
  } from './classificationExplorer';

  interface Props {
    effectiveContextId: string;
    port: ClassificationBackendPort;
    hierarchyView: HierarchyExplorerView | null;
    selectedHierarchyNodeId: number | null;
    selectedHierarchyNode: HierarchyExplorerNode | null;
    expandedHierarchyIds: number[];
    renameDraft: string;
    reparentTargetId: string;
    mutating: boolean;
    onMutatingChange: (v: boolean) => void;
    onError: (msg: string) => void;
    onStatus: (msg: string) => void;
    onClearSelection: () => void;
    onReloadHierarchy: () => Promise<void>;
  }

  let {
    effectiveContextId,
    port,
    hierarchyView,
    selectedHierarchyNodeId,
    selectedHierarchyNode,
    expandedHierarchyIds = $bindable(),
    renameDraft = $bindable(),
    reparentTargetId = $bindable(),
    mutating,
    onMutatingChange,
    onError,
    onStatus,
    onClearSelection,
    onReloadHierarchy,
  }: Props = $props();

  let addNodeName = $state('');
  let addNodeLevel = $state(11);
  let addNodeBreak = $state(false);
  let addAsRoot = $state(false);

  async function submitAddHierarchyNode() {
    if (typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY) return;
    if (!addNodeName.trim() || mutating) return;
    onMutatingChange(true);
    onError('');
    try {
      const parentId = addAsRoot ? null : selectedHierarchyNodeId;
      const res = await port.addHierarchyNode(effectiveContextId, {
        name: addNodeName.trim(),
        parentId,
        level: addNodeLevel,
        isBreakpoint: addNodeBreak,
      });
      addNodeName = '';
      if (parentId !== null && !expandedHierarchyIds.includes(parentId)) {
        expandedHierarchyIds = [...expandedHierarchyIds, parentId];
      }
      onStatus(`Added hierarchy node "${res.nodeName}".`);
      await onReloadHierarchy();
    } catch (err) {
      onError(`Add node failed: ${formatError(err)}`);
    } finally {
      onMutatingChange(false);
    }
  }

  async function submitRenameNode() {
    if (typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY) return;
    if (selectedHierarchyNodeId === null || !renameDraft.trim() || mutating) return;
    onMutatingChange(true);
    onError('');
    try {
      const res = await port.renameHierarchyNode(effectiveContextId, {
        nodeId: selectedHierarchyNodeId,
        newName: renameDraft.trim(),
      });
      onStatus(`Renamed node to "${res.nodeName}".`);
      await onReloadHierarchy();
    } catch (err) {
      onError(`Rename failed: ${formatError(err)}`);
    } finally {
      onMutatingChange(false);
    }
  }

  async function submitReparentNode() {
    if (typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY) return;
    if (selectedHierarchyNodeId === null || mutating || !hierarchyView) return;
    const candidateParent = reparentTargetId === '' ? null : Number(reparentTargetId);
    if (wouldIntroduceHierarchyCycle(hierarchyView.flatNodes, selectedHierarchyNodeId, candidateParent)) {
      onError('Cannot reparent a node onto itself or one of its own descendants (cycle).');
      return;
    }
    onMutatingChange(true);
    onError('');
    try {
      await port.reparentHierarchyNode(effectiveContextId, {
        nodeId: selectedHierarchyNodeId,
        newParentId: candidateParent,
      });
      onStatus('Reparented hierarchy node.');
      await onReloadHierarchy();
    } catch (err) {
      onError(`Reparent failed: ${formatError(err)}`);
    } finally {
      onMutatingChange(false);
    }
  }

  async function submitDeleteNode(cascade: boolean) {
    if (typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY) return;
    if (selectedHierarchyNodeId === null || mutating) return;
    onMutatingChange(true);
    onError('');
    try {
      const res = await port.deleteHierarchyNode(effectiveContextId, {
        nodeId: selectedHierarchyNodeId,
        cascadeChildren: cascade,
      });
      onClearSelection();
      onStatus(`Deleted ${res.affectedRows} hierarchy node(s).`);
      await onReloadHierarchy();
    } catch (err) {
      onError(`Delete node failed: ${formatError(err)}`);
    } finally {
      onMutatingChange(false);
    }
  }
</script>

{#if !IS_WEB_READONLY}
  <section class="vpro-cls-card">
    <h3>Add Classification Node</h3>
    <div class="vpro-cls-stack">
      <label
        ><span>Node Name</span><input
          type="text"
          bind:value={addNodeName}
          placeholder="e.g. Tsugion or CWHvm1/01"
        /></label
      >
      <label>
        <span>Phytosociological Level (1..11)</span>
        <select bind:value={addNodeLevel}>
          <option value={1}>1 — Superclass</option>
          <option value={2}>2 — Class</option>
          <option value={3}>3 — Subclass</option>
          <option value={4}>4 — Order</option>
          <option value={5}>5 — SubOrder</option>
          <option value={6}>6 — Alliance</option>
          <option value={7}>7 — SubAlliance</option>
          <option value={8}>8 — Association</option>
          <option value={9}>9 — SubAssociation</option>
          <option value={10}>10 — Facies / WorkingUnit</option>
          <option value={11}>11 — SiteSeries</option>
        </select>
      </label>
      <label class="vpro-cls-check"
        ><input type="checkbox" bind:checked={addNodeBreak} /><span>Mark as '~' Report Breakpoint</span></label
      >
      <label class="vpro-cls-check"
        ><input type="checkbox" bind:checked={addAsRoot} /><span>Insert at Root (otherwise child of selected node)</span
        ></label
      >
      <button
        type="button"
        class="vpro-btn-primary"
        disabled={!addNodeName.trim() || mutating}
        onclick={submitAddHierarchyNode}>Add Node</button
      >
    </div>
  </section>
{/if}

{#if selectedHierarchyNode}
  <section class="vpro-cls-card">
    <h3>Selected Node #{selectedHierarchyNode.id} ({selectedHierarchyNode.rankName})</h3>
    {#if IS_WEB_READONLY}
      <dl class="vpro-cls-kv">
        <div>
          <dt>Name</dt>
          <dd class="mono">{selectedHierarchyNode.name}</dd>
        </div>
        <div>
          <dt>Rank</dt>
          <dd>{selectedHierarchyNode.rankName} (Level {selectedHierarchyNode.level})</dd>
        </div>
        <div>
          <dt>Parent Node</dt>
          <dd class="mono">{selectedHierarchyNode.parent ?? '(Root)'}</dd>
        </div>
        <div>
          <dt>Breakpoint</dt>
          <dd>{selectedHierarchyNode.isBreakpoint ? 'Yes (~ breakpoint)' : 'No'}</dd>
        </div>
      </dl>
    {:else}
      <div class="vpro-cls-stack">
        <label><span>Rename Node</span><input type="text" bind:value={renameDraft} /></label>
        <button
          type="button"
          class="vpro-btn-secondary"
          disabled={mutating || !renameDraft.trim()}
          onclick={submitRenameNode}>Apply Rename</button
        >

        <label>
          <span>Reparent Under (Cycle-Checked)</span>
          <select bind:value={reparentTargetId}>
            <option value="">(Root — No Parent)</option>
            {#each (hierarchyView?.flatNodes ?? []).filter((n) => !wouldIntroduceHierarchyCycle(hierarchyView!.flatNodes, selectedHierarchyNode!.id, n.id)) as candidate (candidate.id)}
              <option value={String(candidate.id)}>{candidate.name} ({candidate.rankName})</option>
            {/each}
          </select>
        </label>
        <button type="button" class="vpro-btn-secondary" disabled={mutating} onclick={submitReparentNode}
          >Move Branch</button
        >

        <div class="vpro-cls-dialog-row">
          <button type="button" class="vpro-btn-secondary" disabled={mutating} onclick={() => submitDeleteNode(false)}
            >Delete &amp; Promote Kids</button
          >
          <button type="button" class="vpro-btn-danger" disabled={mutating} onclick={() => submitDeleteNode(true)}
            >Delete Subtree</button
          >
        </div>
      </div>
    {/if}
  </section>
{:else if IS_WEB_READONLY}
  <section class="vpro-cls-card">
    <h3>Hierarchy Node Inspector</h3>
    <p class="vpro-cls-muted">Select any node in the hierarchy tree to inspect its rank, parent, and breakpoint status.</p>
  </section>
{/if}
