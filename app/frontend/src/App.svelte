<script lang="ts">
  import { onDestroy, onMount, tick } from 'svelte';
  import {
    ContextService,
    LifecycleService,
    type HierarchyNode,
    type PlotPage,
    type StartupState,
  } from '../bindings/github.com/boostao/vpro/app';
  import type { ContextSelection, PlotSummary } from '../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
  import type { ProfileNavigation } from './classification/projectPlotProfileReview';
  import { formatError, ReadRequests } from './shared/readRequests';
  import { projectState, webShellRuntime } from './shared/state';
  import { closeDisposition, type CloseDecision } from './shell/closeLifecycle';
  import { notifications } from './shell/notificationService.svelte';
  import { bindShellActivitySubscriptions, createOperationGuard } from './shell/operationGuard.svelte';
  import ShellFrame from './shell/ShellFrame.svelte';
  import {
    mountShellWindowLifecycle,
    pushShellErrorNotification,
    registerCoreOperationGuards,
    runFindScopedPlotOp,
    runGlobalHelpKeydownOp,
    runHandleCloseRequestOp,
    runLoadHierarchyOp,
    runLoadPlotsPageOp,
    runNavigateOp,
    runOpenProjectMetadataOp,
    runOpenSIVIOp,
    runRefreshWorkspaceOp,
    runRequestTransitionOp,
    runRespondToCloseOp,
    runRespondToTransitionOp,
    runSwitchContextOp,
    syncShellWebUrlOp,
    type ShellRuntimeSnap,
  } from './shell/shellLifecycleOps';
  import { IS_WEB_READONLY } from './web/runtimeMode';
  import type { FS882EditorHandle, ShellViewId } from './shell/shellPlotOps';
  import { createShellUiController, type ShellStatePatch } from './shell/shellUiController.svelte';

  const pageSize = 25;
  let page = $state<PlotPage | null>(null),
    hierarchyNodes = $state<HierarchyNode[]>([]);
  let selected = $state<PlotSummary | null>(null),
    profileNavigation = $state<ProfileNavigation | null>(null);
  let editorPlotNumber = $state<string | undefined>(undefined),
    editorEntryForm = $state<'fs882' | 'sivi' | 'fs882-twopage'>('fs882');
  let offset = $state(0),
    busy = $state(false),
    error = $state(''),
    pausedByGuard = $state(false);
  let request = 0,
    hierarchyRequest = 0,
    stateRequest = 0,
    lastPushedError = '';
  const plotReads = new ReadRequests(),
    hierarchyReads = new ReadRequests(),
    stateReads = new ReadRequests();

  let view = $state<ShellViewId>('home'),
    standaloneMetadataPlot = $state(''),
    workbenchDirtyLabel = $state('');
  let editor = $state<FS882EditorHandle | undefined>(undefined);
  let closeRequest = $state(''),
    closeWorking = $state(false),
    closeError = $state('');
  let pendingTransition = $state<{ contextId: string; run: (contextId: string) => Promise<void> } | null>(null);
  let transitionWorking = $state(false),
    transitionError = $state('');
  let plotFindQuery = $state(''),
    plotFindError = $state('');
  let plotFindResult = $state<Awaited<ReturnType<typeof ContextService.LookupScopedPlot>> | null>(null);
  let startupFailure = $state<StartupState | null>(null);

  export const operationGuard = createOperationGuard();
  const editorBusy = $derived(operationGuard.editorBusy);

  function applyPatch(p: ShellStatePatch) {
    if (p.view !== undefined) view = p.view;
    if (p.busy !== undefined) busy = p.busy;
    if (p.pausedByGuard !== undefined) pausedByGuard = p.pausedByGuard;
    if (p.lastPushedError !== undefined) lastPushedError = p.lastPushedError;
    if (p.error !== undefined) error = p.error;
    if (p.hasEditorPlotNumber) editorPlotNumber = p.editorPlotNumber;
    if (p.editorEntryForm !== undefined) editorEntryForm = p.editorEntryForm;
    if (p.selected !== undefined) selected = p.selected;
    if (p.page !== undefined) page = p.page;
    if (p.offset !== undefined) offset = p.offset;
    if (p.hierarchyNodes !== undefined) hierarchyNodes = p.hierarchyNodes;
    if (p.profileNavigation !== undefined) profileNavigation = p.profileNavigation;
    if (p.standaloneMetadataPlot !== undefined) standaloneMetadataPlot = p.standaloneMetadataPlot;
    if (p.startupFailure !== undefined) startupFailure = p.startupFailure;
    if (p.closeRequest !== undefined) closeRequest = p.closeRequest;
    if (p.closeWorking !== undefined) closeWorking = p.closeWorking;
    if (p.closeError !== undefined) closeError = p.closeError;
    if (p.transitionWorking !== undefined) transitionWorking = p.transitionWorking;
    if (p.transitionError !== undefined) transitionError = p.transitionError;
    if (p.pendingTransition !== undefined) pendingTransition = p.pendingTransition;
    if (p.plotFindError !== undefined) plotFindError = p.plotFindError;
    if (p.plotFindResult !== undefined) plotFindResult = p.plotFindResult;
  }

  const ui = createShellUiController({
    read: () => ({
      state: $projectState,
      startupFailure,
      view,
      editorEntryForm,
      editorPlotNumber,
      editor,
      closeState,
      selected,
      page,
      offset,
      pageSize,
      profileNavigation,
      busy,
      editorBusy,
      companionPanelBusy,
      transitionWorking,
      operationBusy: operationGuard.isBusy(),
      workbenchDirty: operationGuard.hasDirtyWorkbench(),
    }),
    patch: applyPatch,
    plotReads,
    stateReads,
    bumpPlotRequest: () => {
      request++;
    },
    requestTransition,
    navigate,
    openProjectMetadata,
    switchContext,
    reloadPlotsAndHierarchyAfterReset: async (nextState) => {
      cancelAllReads();
      projectState.set(nextState);
      resetMainCaches();
      view = 'plots';
      await loadPlots(0);
      try {
        await loadHierarchy();
      } catch (cause) {
        error = `Sample workspace activated, but hierarchy refresh failed: ${formatError(cause)}`;
      }
    },
    reloadCurrentOffsetPlots: async () => {
      await loadPlots(offset);
    },
  });

  const editorLabel = $derived<'FS882' | 'FS882 (2-Page)' | 'SIVI / FS1333'>(
    editorEntryForm === 'sivi' ? 'SIVI / FS1333' : editorEntryForm === 'fs882-twopage' ? 'FS882 (2-Page)' : 'FS882'
  );
  const companionPanelBusy = $derived(ui.secondaryPanelBusy || ui.siviModalBusy);
  const editorInitializing = $derived(view === 'fs882' && !editor && ui.fs882ModuleLoaded);
  const closeState = $derived(view === 'fs882' ? editor?.getCloseState() : undefined);
  const allAvailablePlots = $derived(ui.allAvailablePlots);

  registerCoreOperationGuards(operationGuard, {
    shellBusy: () => busy,
    localEditor: () => ({ busy: ui.localEditorBusy, dirty: Boolean(workbenchDirtyLabel) }),
    companionPanel: () => ({
      busy: companionPanelBusy,
      dirty: Boolean(standaloneMetadataPlot && ui.standaloneMetadataEditor?.hasUnsavedChanges?.()),
    }),
    editorInit: () => editorInitializing,
    transitionDialog: () => transitionWorking || pendingTransition !== null,
    closeDialog: () => Boolean(closeRequest),
  });
  bindShellActivitySubscriptions(
    operationGuard,
    () => $projectState,
    (t) => {
      if (view === 'home') {
        if (t.view === 'picture-manager') ui.pictureManagerPlot = t.plotNumber;
        view = t.view;
      }
    }
  );

  $effect(() => {
    if (pausedByGuard && !operationGuard.isBusy()) {
      pausedByGuard = false;
      error = '';
    }
  });
  $effect(() => {
    if (!error) lastPushedError = '';
    else if (error !== lastPushedError) {
      lastPushedError = error;
      pushShellErrorNotification(error);
    }
  });
  $effect(() => {
    if (!IS_WEB_READONLY || !$webShellRuntime) return;
    const activePlot = view === 'fs882' ? editorPlotNumber : selected?.plotNumber;
    syncShellWebUrlOp({
      state: $projectState,
      view,
      editorEntryForm,
      plotNumber: activePlot,
    });
  });

  function cancelAllReads() {
    request++;
    hierarchyRequest++;
    stateRequest++;
    plotReads.cancelAll();
    hierarchyReads.cancelAll();
    stateReads.cancelAll();
    ui?.cancelCatalogReads();
  }
  function resetMainCaches() {
    ui?.clearCatalogCaches();
    standaloneMetadataPlot = '';
    profileNavigation = null;
    selected = null;
    page = null;
    hierarchyNodes = [];
    editorPlotNumber = undefined;
  }
  function shellRt(): ShellRuntimeSnap {
    return {
      state: $projectState,
      view,
      busy,
      editorEntryForm,
      editorPlotNumber,
      editor,
      selected,
      profileNavigation,
      standaloneMetadataPlot,
      startupFailure,
      closeRequest,
      closeWorking,
      pendingTransition,
      transitionWorking,
      plotFindQuery,
      allAvailablePlots: allAvailablePlots ?? [],
      pageSize,
      operationGuard,
      ui,
      plotReads,
      hierarchyReads,
      stateReads,
      lifecycleService: LifecycleService,
      contextService: ContextService,
      notify: notifications,
      tick,
      closeDispositionFn: closeDisposition,
      nextPlotRequest: () => ++request,
      isCurrentPlotRequest: (id) => id === request,
      nextHierarchyRequest: () => ++hierarchyRequest,
      isCurrentHierarchyRequest: (id) => id === hierarchyRequest,
      nextStateRequest: () => ++stateRequest,
      isCurrentStateRequest: (id) => id === stateRequest,
      cancelAllReads,
      resetMainCaches,
      loadPlots,
      loadHierarchy,
      requestTransition,
      patch: applyPatch,
    };
  }

  onDestroy(() => {
    cancelAllReads();
    ui.secondaryPanelBusy = false;
    ui.siviModalBusy = false;
    workbenchDirtyLabel = '';
  });

  async function handleCloseRequest(requestId: string) {
    await runHandleCloseRequestOp(shellRt, requestId);
  }
  async function respondToClose(decision: CloseDecision) {
    await runRespondToCloseOp(shellRt, decision);
  }
  async function requestTransition(run: (contextId: string) => Promise<void>, ownedAction?: () => boolean) {
    await runRequestTransitionOp(shellRt, run, ownedAction);
  }
  async function respondToTransition(decision: CloseDecision) {
    await runRespondToTransitionOp(shellRt, decision);
  }
  function navigate(next: ShellViewId | 'fs882-twopage') {
    return runNavigateOp(shellRt, next);
  }
  async function openSIVI() {
    await runOpenSIVIOp(shellRt);
  }
  async function openProjectMetadata() {
    await runOpenProjectMetadataOp(shellRt);
  }
  async function findScopedPlot() {
    await runFindScopedPlotOp(shellRt);
  }
  async function loadPlots(nextOffset: number) {
    await runLoadPlotsPageOp(shellRt, nextOffset);
  }
  async function refresh() {
    await runRefreshWorkspaceOp(shellRt);
  }
  async function loadHierarchy() {
    await runLoadHierarchyOp(shellRt);
  }
  async function switchContext(contextId: string, selection: ContextSelection, next: 'plots' | 'hierarchy') {
    await runSwitchContextOp(shellRt, contextId, selection, next);
  }
  function handleGlobalHelpKeydown(event: KeyboardEvent) {
    runGlobalHelpKeydownOp(shellRt, event);
  }

  onMount(() =>
    mountShellWindowLifecycle(
      ui,
      LifecycleService,
      (id) => void handleCloseRequest(id),
      () => void refresh(),
      (msg) => {
        error = msg;
      },
      () => {
        request++;
      }
    )
  );
</script>

<svelte:window onkeydown={handleGlobalHelpKeydown} />
<ShellFrame
  {ui}
  bind:view
  bind:busy
  bind:error
  bind:editorPlotNumber
  bind:editorEntryForm
  bind:profileNavigation
  bind:selected
  bind:page
  bind:standaloneMetadataPlot
  bind:workbenchDirtyLabel
  bind:editor
  bind:plotFindQuery
  bind:plotFindError
  bind:plotFindResult
  bind:startupFailure
  {editorLabel}
  {editorBusy}
  {companionPanelBusy}
  {transitionWorking}
  {pendingTransition}
  {closeRequest}
  {closeWorking}
  {closeError}
  {transitionError}
  {closeState}
  {offset}
  {pageSize}
  {hierarchyNodes}
  workbenchDirty={operationGuard.hasDirtyWorkbench()}
  {stateReads}
  {requestTransition}
  {respondToClose}
  {respondToTransition}
  {navigate}
  {openSIVI}
  {openProjectMetadata}
  {findScopedPlot}
  {loadPlots}
  {refresh}
  {switchContext}
  onAccessActivated={async () => {
    resetMainCaches();
    await loadPlots(0);
    try {
      await loadHierarchy();
    } catch {
      // Non-fatal if newly attached project has no active hierarchy yet.
    }
  }}
/>
