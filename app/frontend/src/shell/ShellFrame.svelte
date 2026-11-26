<script lang="ts">
  import type {
    ContextService,
    HierarchyNode,
    PlotPage,
    StartupState,
  } from '../../bindings/github.com/boostao/vpro/app';
  import type {
    ContextSelection,
    PlotSummary,
  } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
  import type { ProfileNavigation } from '../classification/projectPlotProfileReview';
  import type { ReadRequests } from '../shared/readRequests';
  import { projectState } from '../shared/state';
  import type { CloseDecision, EditorCloseState } from './closeLifecycle';
  import ShellChromeHeader from './ShellChromeHeader.svelte';
  import ShellOverlays from './ShellOverlays.svelte';
  import type { FS882EditorHandle, ShellViewId } from './shellPlotOps';
  import type { ShellUiController } from './shellUiController.svelte';
  import ShellWorkspaceRouter from './ShellWorkspaceRouter.svelte';
  import WorkspaceSidebar from './WorkspaceSidebar.svelte';

  let {
    ui,
    view = $bindable<ShellViewId>('home'),
    busy = $bindable(false),
    error = $bindable(''),
    editorPlotNumber = $bindable<string | undefined>(undefined),
    editorEntryForm = $bindable<'fs882' | 'sivi' | 'fs882-twopage'>('fs882'),
    profileNavigation = $bindable<ProfileNavigation | null>(null),
    selected = $bindable<PlotSummary | null>(null),
    page = $bindable<PlotPage | null>(null),
    standaloneMetadataPlot = $bindable(''),
    workbenchDirtyLabel = $bindable(''),
    editor = $bindable<FS882EditorHandle | undefined>(undefined),
    plotFindQuery = $bindable(''),
    plotFindError = $bindable(''),
    plotFindResult = $bindable<Awaited<ReturnType<typeof ContextService.LookupScopedPlot>> | null>(null),
    startupFailure = $bindable<StartupState | null>(null),
    editorLabel,
    editorBusy,
    companionPanelBusy,
    transitionWorking,
    pendingTransition,
    closeRequest,
    closeWorking,
    closeError,
    transitionError,
    closeState,
    offset,
    pageSize,
    hierarchyNodes,
    workbenchDirty,
    stateReads,
    requestTransition,
    respondToClose,
    respondToTransition,
    navigate,
    openSIVI,
    openProjectMetadata,
    findScopedPlot,
    loadPlots,
    refresh,
    switchContext,
    onAccessActivated,
  }: {
    ui: ShellUiController;
    view: ShellViewId;
    busy: boolean;
    error: string;
    editorPlotNumber: string | undefined;
    editorEntryForm: 'fs882' | 'sivi' | 'fs882-twopage';
    profileNavigation: ProfileNavigation | null;
    selected: PlotSummary | null;
    page: PlotPage | null;
    standaloneMetadataPlot: string;
    workbenchDirtyLabel: string;
    editor: FS882EditorHandle | undefined;
    plotFindQuery: string;
    plotFindError: string;
    plotFindResult: Awaited<ReturnType<typeof ContextService.LookupScopedPlot>> | null;
    startupFailure: StartupState | null;
    editorLabel: 'FS882' | 'FS882 (2-Page)' | 'SIVI / FS1333';
    editorBusy: boolean;
    companionPanelBusy: boolean;
    transitionWorking: boolean;
    pendingTransition: unknown;
    closeRequest: string;
    closeWorking: boolean;
    closeError: string;
    transitionError: string;
    closeState: EditorCloseState | undefined;
    offset: number;
    pageSize: number;
    hierarchyNodes: HierarchyNode[];
    workbenchDirty: boolean;
    stateReads: ReadRequests;
    requestTransition: (run: (contextId: string) => Promise<void>, ownedAction?: () => boolean) => Promise<void>;
    respondToClose: (decision: CloseDecision) => Promise<void>;
    respondToTransition: (decision: CloseDecision) => Promise<void>;
    navigate: (next: ShellViewId | 'fs882-twopage') => void;
    openSIVI: () => Promise<void>;
    openProjectMetadata: () => Promise<void>;
    findScopedPlot: () => Promise<void>;
    loadPlots: (nextOffset: number) => Promise<void>;
    refresh: () => Promise<void>;
    switchContext: (contextId: string, selection: ContextSelection, next: 'plots' | 'hierarchy') => Promise<void>;
    onAccessActivated: () => Promise<void>;
  } = $props();
</script>

<div class="app-shell">
  <ShellChromeHeader
    {ui}
    {view}
    {editorEntryForm}
    {startupFailure}
    siviAvailable={Boolean(selected && $projectState?.contextId)}
    onNavigate={navigate}
    onOpenSivi={() => void openSIVI()}
    onOpenMetadata={() => void openProjectMetadata()}
    onOpenCloudSync={() => {
      void requestTransition(async () => {
        standaloneMetadataPlot = '';
        ui.projectAdminTab = 'cloudsync';
        ui.projectAdminTabNonce++;
        view = 'project-admin';
        error = '';
      });
    }}
    onOpenAuthSignIn={() => {
      ui.authSignInOpen = true;
    }}
  />
  <div
    class="workspace inspector-collapsed"
    class:context-collapsed={!ui.contextExpanded || startupFailure !== null}
  >
    {#if !startupFailure && ui.isNarrowViewport && ui.contextExpanded}
      <button
        type="button"
        class="drawer-backdrop"
        aria-label="Close side drawer"
        data-drawer-backdrop
        onclick={() => {
          ui.contextExpanded = false;
        }}
      ></button>
    {/if}
    <WorkspaceSidebar
      {busy}
      {editorBusy}
      {companionPanelBusy}
      {transitionWorking}
      {requestTransition}
      {switchContext}
      {onAccessActivated}
      onOpenAuthSignIn={() => {
        ui.authSignInOpen = true;
      }}
    />
    <ShellWorkspaceRouter
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
      bind:standaloneMetadataEditor={
        () => ui.standaloneMetadataEditor,
        (v) => {
          ui.standaloneMetadataEditor = v;
        }
      }
      bind:localEditorBusy={
        () => ui.localEditorBusy,
        (v) => {
          ui.localEditorBusy = v;
        }
      }
      bind:secondaryPanelBusy={
        () => ui.secondaryPanelBusy,
        (v) => {
          ui.secondaryPanelBusy = v;
        }
      }
      bind:siviModalBusy={
        () => ui.siviModalBusy,
        (v) => {
          ui.siviModalBusy = v;
        }
      }
      bind:workbenchDirtyLabel
      bind:editor
      bind:fs882ModuleLoaded={
        () => ui.fs882ModuleLoaded,
        (v) => {
          ui.fs882ModuleLoaded = v;
        }
      }
      bind:plotFindOpen={
        () => ui.plotFindOpen,
        (v) => {
          ui.plotFindOpen = v;
        }
      }
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
      {stateReads}
      {requestTransition}
      {respondToClose}
      {respondToTransition}
      {navigate}
      {findScopedPlot}
      {loadPlots}
      {refresh}
    />
  </div>
  <ShellOverlays
    {ui}
    {startupFailure}
    {busy}
    {editorBusy}
    {companionPanelBusy}
    {transitionWorking}
    {workbenchDirty}
    plotCount={page?.total ?? 0}
    {stateReads}
    onNavigate={(nextView) => navigate(nextView)}
    onRefresh={refresh}
  />
</div>
