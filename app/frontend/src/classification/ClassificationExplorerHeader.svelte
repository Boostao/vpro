<script lang="ts">
  import ClassificationDialogs from './ClassificationDialogs.svelte';
  import type { ClassificationBackendPort, ExplorerMode } from './classificationExplorer';

  let {
    project,
    activeSuLabel,
    activeHierarchyLabel,
    activeHierarchy,
    mode,
    operationHeld,
    errorMessage,
    statusBanner,
    activeDialog,
    effectiveContextId,
    port,
    mutating,
    newSUName = $bindable(),
    newSUDestination = $bindable(),
    newSUFilePath = $bindable(),
    populateAllPlots = $bindable(),
    seedFromUserSU = $bindable(),
    onSwitchMode,
    onCloseDialog,
    onSubmitCreateSU,
    onMutatingChange,
    onError,
    onStatus,
    onActivated,
    onReloadSU,
    onReloadHierarchy,
  }: {
    project: string;
    activeSuLabel: string;
    activeHierarchyLabel: string;
    activeHierarchy: string;
    mode: ExplorerMode;
    operationHeld: boolean;
    errorMessage: string;
    statusBanner: string;
    activeDialog: 'none' | 'new_su' | 'save_su_as' | 'su_from_env' | 'new_hierarchy' | 'save_hierarchy_as';
    effectiveContextId: string;
    port: ClassificationBackendPort;
    mutating: boolean;
    newSUName: string;
    newSUDestination: 'project' | 'new_file';
    newSUFilePath: string;
    populateAllPlots: boolean;
    seedFromUserSU: boolean;
    onSwitchMode: (nextMode: ExplorerMode) => void;
    onCloseDialog: () => void;
    onSubmitCreateSU: () => Promise<void>;
    onMutatingChange: (v: boolean) => void;
    onError: (msg: string) => void;
    onStatus: (msg: string) => void;
    onActivated: (cid: string, st: unknown) => void;
    onReloadSU: () => Promise<void>;
    onReloadHierarchy: () => Promise<void>;
  } = $props();
</script>

<header class="vpro-cls-header">
  <div>
    <p class="vpro-cls-eyebrow">BEC CLASSIFICATION WORKBENCH</p>
    <h2 class="vpro-cls-title">
      Classification Explorer
      {#if project}<span class="vpro-cls-pill">Project: {project}</span>{/if}
      <span class="vpro-cls-pill">SU: {activeSuLabel}</span>
      <span class="vpro-cls-pill">Hierarchy: {activeHierarchyLabel}</span>
    </h2>
  </div>

  <div class="vpro-cls-mode-bar" role="tablist" aria-label="Classification Explorer Views">
    <button
      type="button"
      role="tab"
      aria-selected={mode === 'su_tree'}
      class="vpro-cls-mode-btn"
      class:active={mode === 'su_tree'}
      onclick={() => onSwitchMode('su_tree')}
    >
      SU -&gt; Plots Tree
    </button>
    <button
      type="button"
      role="tab"
      aria-selected={mode === 'hierarchy_tree'}
      class="vpro-cls-mode-btn"
      class:active={mode === 'hierarchy_tree'}
      onclick={() => onSwitchMode('hierarchy_tree')}
    >
      Hierarchy Tree (~)
    </button>
    <button
      type="button"
      role="tab"
      aria-selected={mode === 'hierarchy_flat'}
      class="vpro-cls-mode-btn"
      class:active={mode === 'hierarchy_flat'}
      onclick={() => onSwitchMode('hierarchy_flat')}
    >
      Flat Rank Table
    </button>
  </div>
</header>

{#if operationHeld}
  <p role="status" class="vpro-cls-status">Sync/operation in progress — some edits are queued.</p>
{/if}
{#if errorMessage}
  <p role="alert" class="vpro-cls-alert">{errorMessage}</p>
{/if}
{#if statusBanner}
  <p role="status" class="vpro-cls-status">{statusBanner}</p>
{/if}

<ClassificationDialogs
  {activeDialog}
  {effectiveContextId}
  {activeHierarchy}
  {port}
  {mutating}
  bind:newSUName
  bind:newSUDestination
  bind:newSUFilePath
  bind:populateAllPlots
  bind:seedFromUserSU
  onClose={onCloseDialog}
  {onSubmitCreateSU}
  {onMutatingChange}
  {onError}
  {onStatus}
  {onActivated}
  {onReloadSU}
  {onReloadHierarchy}
/>
