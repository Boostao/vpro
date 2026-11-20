<script lang="ts">
  import type {
    ContextService,
    HierarchyNode,
    PlotPage,
    ProjectPlotProfileFilterRequest,
    StartupState,
  } from '../../bindings/github.com/boostao/vpro/app';
  import type { PlotSummary } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
  import type { ProfileNavigation } from '../classification/projectPlotProfileReview';
  import type { ReadRequests } from '../shared/readRequests';
  import { projectState } from '../shared/state';
  import type { CloseDecision, EditorCloseState } from './closeLifecycle';
  import HomeWorkspaceHub from './HomeWorkspaceHub.svelte';
  import { notifications } from './notificationService.svelte';
  import type { PlotProfileSelectionController } from './plotProfileOps';
  import PlotProfilePanel from './PlotProfilePanel.svelte';
  import ShellDeferredViews from './ShellDeferredViews.svelte';
  import ShellEntryHost from './ShellEntryHost.svelte';
  import type { FS882EditorHandle, ShellViewId } from './shellPlotOps';
  import type { ShellUiController } from './shellUiController.svelte';
  import WorkspaceStatusBanners from './WorkspaceStatusBanners.svelte';

  const DEFERRED_VIEW_SET = new Set<ShellViewId>([
    'datasheet',
    'classification-explorer',
    'project-admin',
    'lump-editor',
    'diagnostic-synthesis',
    'r-sidecar',
    'geospatial-map',
    'interchange-hub',
    'summary-environment',
    'long-environment',
    'long-vegetation',
    'summary-vegetation',
    'lifeform-summary',
    'table-csv',
    'user-log',
    'plot-label-preview',
    'picture-manager',
    'plot-locations',
    'google-earth-review',
    'subzone-matrix',
  ]);

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
    standaloneMetadataEditor = $bindable<
      { hasUnsavedChanges?: () => boolean; getCloseState: () => EditorCloseState; undo: () => void } | undefined
    >(undefined),
    localEditorBusy = $bindable(false),
    secondaryPanelBusy = $bindable(false),
    siviModalBusy = $bindable(false),
    workbenchDirtyLabel = $bindable(''),
    editor = $bindable<FS882EditorHandle | undefined>(undefined),
    fs882ModuleLoaded = $bindable(false),
    plotProfilePanel = $bindable<
      | {
          reviewProfileSU: (proposal: ProjectPlotProfileFilterRequest, origin: string) => Promise<void>;
          clearCachedSources: () => void;
          resetAllReviews: () => void;
        }
      | undefined
    >(undefined),
    plotFindOpen = $bindable(false),
    plotFindQuery = $bindable(''),
    plotFindError = $bindable(''),
    plotFindResult = $bindable<Awaited<ReturnType<typeof ContextService.LookupScopedPlot>> | null>(null),
    startupFailure = $bindable<StartupState | null>(null),
    editorLabel,
    editorBusy,
    companionPanelBusy,
    operationHeld,
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
    stateReads,
    requestTransition,
    respondToClose,
    respondToTransition,
    navigate,
    openSIVI,
    findScopedPlot,
    loadPlots,
    refresh,
    cancelAllReads,
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
    standaloneMetadataEditor:
      { hasUnsavedChanges?: () => boolean; getCloseState: () => EditorCloseState; undo: () => void } | undefined;
    localEditorBusy: boolean;
    secondaryPanelBusy: boolean;
    siviModalBusy: boolean;
    workbenchDirtyLabel: string;
    editor: FS882EditorHandle | undefined;
    fs882ModuleLoaded: boolean;
    plotProfilePanel:
      | {
          reviewProfileSU: (proposal: ProjectPlotProfileFilterRequest, origin: string) => Promise<void>;
          clearCachedSources: () => void;
          resetAllReviews: () => void;
        }
      | undefined;
    plotFindOpen: boolean;
    plotFindQuery: string;
    plotFindError: string;
    plotFindResult: Awaited<ReturnType<typeof ContextService.LookupScopedPlot>> | null;
    startupFailure: StartupState | null;
    editorLabel: 'FS882' | 'FS882 (2-Page)' | 'SIVI / FS1333';
    editorBusy: boolean;
    companionPanelBusy: boolean;
    operationHeld: boolean;
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
    stateReads: ReadRequests;
    requestTransition: (run: (contextId: string) => Promise<void>, ownedAction?: () => boolean) => Promise<void>;
    respondToClose: (decision: CloseDecision) => Promise<void>;
    respondToTransition: (decision: CloseDecision) => Promise<void>;
    navigate: (next: ShellViewId | 'fs882-twopage') => void;
    openSIVI: () => Promise<void>;
    findScopedPlot: () => Promise<void>;
    loadPlots: (nextOffset: number) => Promise<void>;
    refresh: () => Promise<void>;
    cancelAllReads: () => void;
  } = $props();

  const panelHold = $derived(busy || transitionWorking || pendingTransition !== null || !!closeRequest);
  let profileSelection = $state<PlotProfileSelectionController | undefined>(undefined);
  let reopenProfileReview = $state(false);
  let pictureManagerPlotProxy = $state('');
  let diagnosticsDraftProxy = $state<typeof ui.diagnosticsDraft>(null);
  $effect(() => {
    pictureManagerPlotProxy = ui.pictureManagerPlot;
  });
  $effect(() => {
    diagnosticsDraftProxy = ui.diagnosticsDraft;
  });
  $effect(() => {
    if (view !== 'fs882' && reopenProfileReview) {
      reopenProfileReview = false;
    }
  });

  function openPlotProfiling() {
    void requestTransition(async () => {
      const targetPlot = selected?.plotNumber ?? ui.allAvailablePlots[0]?.plotNumber ?? editorPlotNumber;
      editorPlotNumber = targetPlot;
      editorEntryForm = 'fs882';
      reopenProfileReview = true;
      view = 'fs882';
      error = '';
    });
  }
</script>

<main class="content">
  <WorkspaceStatusBanners
    region="banners"
    startupFailed={startupFailure !== null}
    whatsNewStatus={ui.whatsNewStatus}
    whatsNewPromptDismissed={ui.whatsNewPromptDismissed}
    onopenwhatsnew={() => {
      ui.whatsNewModalOpen = true;
    }}
    onacknowledgewhatsnew={() => void ui.acknowledgeUnreadWhatsNew()}
    ondismisswhatsnew={() => {
      ui.whatsNewPromptDismissed = true;
    }}
  />
  <PlotProfilePanel
    bind:this={plotProfilePanel}
    bind:view
    bind:busy
    bind:error
    bind:editorPlotNumber
    bind:profileNavigation
    bind:selected
    bind:page
    bind:selectionController={profileSelection}
    bind:reopenProfileReview
    {operationHeld}
    {editorBusy}
    {transitionWorking}
    {pendingTransition}
    {closeRequest}
    profileIndex={ui.profileIndex}
    {stateReads}
    {requestTransition}
    {loadPlots}
    navigateProfilePlot={ui.navigateProfilePlot}
    clearProfileNavigation={ui.clearProfileNavigation}
    {cancelAllReads}
  />
  <WorkspaceStatusBanners region="banners" startupFailed={true} diagnostics={$projectState?.diagnostics ?? []} />
  {#if startupFailure}
    {#await import('./StartupRecoveryPanel.svelte') then { default: StartupRecoveryPanel }}
      <StartupRecoveryPanel
        {startupFailure}
        {busy}
        onrecovered={async (notice) => {
          if (notice) notifications.success('Startup recovery complete', notice, { source: 'Startup Recovery' });
          startupFailure = null;
          await refresh();
        }}
      />
    {/await}
  {:else if (standaloneMetadataPlot && $projectState?.contextId) || view === 'fs882'}
    <ShellEntryHost
      mode={standaloneMetadataPlot && $projectState?.contextId ? 'metadata' : 'fs882'}
      {busy}
      bind:error
      bind:view
      bind:editorPlotNumber
      bind:editorEntryForm
      bind:selected
      bind:standaloneMetadataPlot
      bind:standaloneMetadataEditor
      bind:localEditorBusy
      bind:editor
      bind:fs882ModuleLoaded
      bind:plotFindOpen
      bind:plotFindQuery
      bind:plotFindError
      bind:plotFindResult
      bind:pictureManagerPlot={
        () => pictureManagerPlotProxy,
        (next) => {
          pictureManagerPlotProxy = next;
          ui.pictureManagerPlot = next;
        }
      }
      bind:diagnosticsDraft={
        () => diagnosticsDraftProxy,
        (next) => {
          diagnosticsDraftProxy = next;
          ui.diagnosticsDraft = next;
        }
      }
      {editorLabel}
      {editorBusy}
      {transitionWorking}
      {pendingTransition}
      {closeRequest}
      {closeWorking}
      {closeError}
      {transitionError}
      {closeState}
      allAvailablePlots={ui.allAvailablePlots}
      canUndoEditorPlot={ui.canUndoEditorPlot}
      {stateReads}
      {requestTransition}
      {respondToClose}
      {respondToTransition}
      {navigate}
      {findScopedPlot}
      openFoundPlot={() =>
        ui.openFoundPlot({
          plotFindResult,
          setPlotFindError: (msg) => {
            plotFindError = msg;
          },
          clearPlotFind: () => {
            plotFindOpen = false;
            plotFindResult = null;
          },
        })}
      applyProfileNavigation={ui.applyProfileNavigation}
      {profileSelection}
      initialProfileReviewOpen={reopenProfileReview}
      onConsumedInitialProfileReview={() => {
        reopenProfileReview = false;
      }}
      reviewProfileSU={async (proposal, origin) => {
        if (!plotProfilePanel) throw new Error('Plot profile panel is not ready.');
        await plotProfilePanel.reviewProfileSU(proposal, origin);
      }}
      copyPlotToNewNumber={ui.copyPlotToNewNumber}
      removePlotFromProject={ui.removePlotFromProject}
      refreshCatalogAfterWrite={ui.refreshCatalogAfterWrite}
    />
  {:else if view === 'home'}
    <div class="content-heading">
      <div>
        <div class="eyebrow">VPro</div>
        <h1>Home</h1>
      </div>
    </div>
    <HomeWorkspaceHub
      activeProject={$projectState?.activeProject ?? 'No project selected'}
      projectPath={$projectState?.projectPath ?? ''}
      activeSU={$projectState?.activeSU ?? 'None'}
      activeHierarchy={$projectState?.activeHierarchy ?? 'None'}
      plotCount={page?.total ?? 0}
      buildMode={ui.buildMode}
      appVersion={ui.appVersion}
      gitCommit={ui.startupInfo?.gitCommit ?? ''}
      releaseChannel={ui.releaseChannel}
      onnavigate={(nextView) => navigate(nextView)}
      onhelpaction={(action) => ui.handleHelpMenuAction(action)}
    />
  {:else if DEFERRED_VIEW_SET.has(view) && $projectState}
    <ShellDeferredViews
      {view}
      {panelHold}
      {companionPanelBusy}
      bind:localEditorBusy
      bind:secondaryPanelBusy
      bind:workbenchDirtyLabel
      projectAdminTab={ui.projectAdminTab}
      projectAdminTabNonce={ui.projectAdminTabNonce}
      plotLabelNumber={ui.plotLabelNumber}
      pictureManagerPlot={ui.pictureManagerPlot}
      {stateReads}
      {refresh}
      onOpenPlot={(plotNumber) => {
        void requestTransition(async () => {
          editorPlotNumber = plotNumber;
          editorEntryForm = 'fs882';
          view = 'fs882';
          error = '';
        });
      }}
    />
  {:else}
    {#await import('./PlotsBrowserPanel.svelte') then { default: PlotsBrowserPanel }}
      <PlotsBrowserPanel
        region="main"
        {view}
        {busy}
        {error}
        {page}
        allPlots={ui.allAvailablePlots}
        {offset}
        {pageSize}
        {hierarchyNodes}
        bind:selected
        onrefresh={refresh}
        onloadpage={loadPlots}
        onopenexplorer={() => navigate('classification-explorer')}
        onopenprofiling={openPlotProfiling}
        onselectplot={() => {
          ui.inspectorExpanded = true;
        }}
      />
    {/await}
  {/if}
</main>

{#if ui.showInspectorRail}
  {#await import('./PlotsBrowserPanel.svelte') then { default: PlotsBrowserPanel }}
    <PlotsBrowserPanel
      region="detail"
      {view}
      {busy}
      {page}
      allPlots={ui.allAvailablePlots}
      bind:selected
      canUndoSelectedPlot={ui.canUndoSelectedPlot}
      {editorBusy}
      {transitionWorking}
      {pendingTransition}
      onopenfs882={() => navigate('fs882')}
      onopentwopage={() => navigate('fs882-twopage')}
      onopensivi={() => void openSIVI()}
      onopenprofiling={openPlotProfiling}
      oncopyplot={ui.copyPlotToNewNumber}
      onremoveplot={ui.removePlotFromProject}
      oncollapseinspector={() => {
        ui.inspectorExpanded = false;
      }}
    />
  {/await}
{/if}

{#if ui.newSiviModalOpen && $projectState?.contextId}
  {#await import('../entry/SIVIParentCreateModal.svelte') then { default: SIVIParentCreateModal }}
    <SIVIParentCreateModal
      contextId={$projectState.contextId}
      activeProject={$projectState.activeProject}
      activeSu={$projectState.activeSU}
      open={ui.newSiviModalOpen}
      operationHeld={panelHold || editorBusy || secondaryPanelBusy}
      onBusyChange={(value) => {
        siviModalBusy = value;
      }}
      oncreated={async (res) => {
        ui.newSiviModalOpen = false;
        await ui.refreshCatalogAfterWrite();
        editorPlotNumber = res.plotNumber;
        editorEntryForm = 'sivi';
        view = 'fs882';
      }}
      onundone={async () => {
        await ui.refreshCatalogAfterWrite();
      }}
      onclose={() => {
        ui.newSiviModalOpen = false;
      }}
    />
  {/await}
{/if}
