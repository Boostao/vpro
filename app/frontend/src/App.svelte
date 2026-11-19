<script lang="ts">
  import { onMount, onDestroy, tick, type Component } from 'svelte';
  import { Events } from '@wailsio/runtime';
  import { VproCloseRequest } from '../bindings/events';
  import { Bell, ChevronLeft, ChevronRight, Database, PanelRight, Search } from '@lucide/svelte';
  import { ContextService, DatasheetService, LifecycleService, type StartupState, type HierarchyNode, type PlotPage, type ProjectPlotProfileFilterRequest } from '../bindings/github.com/boostao/vpro/app';
import type { ContextSelection, PlotSummary } from '../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
  import { projectState } from './shared/state';
  import Navigation from './shell/Navigation.svelte';
  import CommandPalette from './shell/CommandPalette.svelte';
  import NotificationHost from './shell/NotificationHost.svelte';
  import NotificationDrawer from './shell/NotificationDrawer.svelte';
  import { notifications, type NotificationStateSnapshot } from './shell/notificationService.svelte';
  import type { BuildCommandPaletteInput, CommandPaletteAction } from './shell/commandPalette';
  import HomeWorkspaceHub from './shell/HomeWorkspaceHub.svelte';
  import WorkspaceSidebar from './shell/WorkspaceSidebar.svelte';
  import PlotProfilePanel from './shell/PlotProfilePanel.svelte';
  import PlotsBrowserPanel from './shell/PlotsBrowserPanel.svelte';
  import WorkspaceStatusBanners from './shell/WorkspaceStatusBanners.svelte';
  import { summaryVegetationPreferenceSession } from './reports/summaryVegetationPreferences';
  import { summaryVegetationQualityPreferenceSession } from './reports/summaryVegetationQualityPreferences';
  import { summaryVegetationPresentationPreferenceSession } from './reports/summaryVegetationPresentationPreferences';
  import { summaryVegetationFieldListDesktop } from './reports/summaryVegetationFieldListDesktop';
  import { summaryEnvironmentalDesktop, summaryEnvironmentalEnabled } from './reports/summaryVegetationEnvironmentalDesktop';
  import { matrixPublicationSession } from './reports/subzoneMatrixReport';
  import CloseConfirm from './shell/CloseConfirm.svelte';
  import { closeDisposition, type CloseDecision, type EditorCloseState } from './shell/closeLifecycle';
  import { ReadRequests } from './shared/readRequests';
  import { bindContextPlots } from './shared/contextPlots';
  import { validateProfileNavigation, profileNavigationPage, type ProfileNavigation } from './classification/projectPlotProfileReview';
  import { plotLookupInputError, validateScopedPlotLookup } from './shared/scopedPlotLookup';
  import { tableCSVArchivePublicationSession } from './interchange/tableCSVArchiveExport';
  import { vegetationWorkbookPublicationSession } from './reports/vegetationWorkbook';
  import { projectReportWorkspace } from './reports/longVegetationProjectWorkspaces';
  import { lifeformWorkbookPublicationSession } from './reports/lifeformWorkbook';
  import { siteUnitSummaryWorkbookPublicationSession } from './reports/siteUnitSummaryWorkbook';
  import { extendedSummaryWorkbookPublicationSession } from './reports/siteUnitSummaryExtendedWorkbook';
  import { summaryVegetationWorkbookSession } from './reports/summaryVegetationWorkbook';
  import { subscribePictureCreationActivity } from './pictures/pictureCreationActivity';
  import { subscribePictureLifecycleActivity } from './pictures/pictureLifecycleActivity';
  import { subscribeTwoPageSoilActivity } from './entry/twoPageSoilActivity';
  import { subscribeTwoPageVegetationActivity } from './entry/twoPageVegetationActivity';
  import { subscribeExternalSUEnvironmentActivity } from './classification/externalSUEnvironment';
  import { classifyGlobalHelpShortcut, defaultHelpPort, resolveContextualHelpTarget, type HelpDrawerTab, type HelpMenuAction, type WhatsNewStatus } from './help/helpSystem';

  const pageSize = 25;
  let page = $state<PlotPage | null>(null);
  let hierarchyNodes = $state<HierarchyNode[]>([]);
  let selected = $state<PlotSummary | null>(null);
  let profileNavigation = $state<ProfileNavigation | null>(null);
  const profileIndex = $derived(profileNavigation?.plots.findIndex(plot => plot.plotNumber === editorPlotNumber) ?? -1);
  type DiagnosticsDraftContext = {
    header: Record<string, unknown> | null;
    humus: Record<string, unknown>[];
    mineral: Record<string, unknown>[];
  };
  type FS882EditorHandle = {
    getCloseState: () => EditorCloseState;
    saveForClose: () => Promise<boolean>;
    canOpenProjectMetadata: () => boolean;
    openProjectMetadata: () => void;
    canOpenMetadataInPlace?: () => boolean;
    applyDiagnosticHumusThickness?: (value: number) => void;
    applyDiagnosticSMR?: (smrCode: string) => void;
    applyDiagnosticSNR?: (snrCode: string) => void;
  };
  type FS882FormWave3Props = {
    plotNumber?: string;
    contextId?: string;
    entryForm?: 'fs882' | 'sivi' | 'fs882-twopage';
    onSaved?: (plotNumber: string) => Promise<void> | void;
    onClosed?: () => void;
    onBusyChange?: (busy: boolean) => void;
    onProfileNavigation?: (proposal: ProjectPlotProfileFilterRequest, origin: string) => Promise<void> | void;
    onProfileSUReview?: (proposal: ProjectPlotProfileFilterRequest, origin: string) => Promise<void> | void;
    onFindPlot?: () => void;
    onOpenPictureManager?: (plotNumber: string) => void;
    onDiagnosticsContextChange?: (state: DiagnosticsDraftContext) => void;
    availablePlots?: PlotSummary[];
    onSelectPlotForTwoPage?: (plotNumber: string) => void;
    onSwitchTo6x4NewPlot?: () => void;
    canUndoPlotDelete?: boolean;
    onCopyPlotToNumber?: (sourcePlot: string, targetPlot: string) => Promise<void>;
    onRemovePlotAction?: (sourcePlot: string, cleanProjectName: string) => Promise<void>;
  };
  type LongVegetationWave3Props = {
    contextId: string;
    project: string;
    projectPath: string;
    su: string;
    suPath: string;
    hierarchy?: string;
    operationHeld?: boolean;
    onBusyChange: (busy: boolean) => void;
  };
  type SummaryVegetationWave3Props = {
    contextId: string;
    project: string;
    projectPath: string;
    su: string;
    suPath: string;
    hierarchy?: string;
    operationHeld?: boolean;
    onBusyChange: (busy: boolean) => void;
    onExclusionBusyChange?: (busy: boolean) => void;
  };

  let editorPlotNumber = $state<string | undefined>(undefined);
  let editorEntryForm = $state<'fs882' | 'sivi' | 'fs882-twopage'>('fs882');
  const editorLabel = $derived<'FS882' | 'FS882 (2-Page)' | 'SIVI / FS1333'>(
    editorEntryForm === 'sivi' ? 'SIVI / FS1333' : editorEntryForm === 'fs882-twopage' ? 'FS882 (2-Page)' : 'FS882'
  );
  let diagnosticsDraft = $state.raw<DiagnosticsDraftContext | null>(null);
  const siviStandaloneEnabled = true;
  let offset = $state(0), busy = $state(false), error = $state('');
  let request = 0, hierarchyRequest = 0, stateRequest = 0;
  let catalogPlotRequest = 0, paletteSearchRequest = 0;
  let scopedCatalogKey = '';
  let scopedPlotCatalogRows = $state<PlotSummary[]>([]);
  let dynamicPalettePlotRows = $state<PlotSummary[]>([]);
  let createdSiviPlots = $state<Array<{ requestId: string; plotNumber: string; canUndo: boolean }>>([]);
  const plotReads = new ReadRequests(), hierarchyReads = new ReadRequests();
  const stateReads = new ReadRequests();
  const catalogPlotReads = new ReadRequests(), paletteSearchReads = new ReadRequests();
  onDestroy(() => {
    request++; hierarchyRequest++; stateRequest++;
    secondaryPanelBusy = false; siviModalBusy = false; workbenchDirtyLabel = '';
    plotReads.cancelAll(); hierarchyReads.cancelAll(); stateReads.cancelAll();
    catalogPlotRequest++; paletteSearchRequest++;
    catalogPlotReads.cancelAll(); paletteSearchReads.cancelAll();
  });
  let view = $state<'home' | 'plots' | 'geospatial-map' | 'diagnostic-synthesis' | 'r-sidecar' | 'hierarchy' | 'fs882' | 'datasheet' | 'classification-explorer' | 'project-admin' | 'lump-editor' | 'interchange-hub' | 'long-environment' | 'summary-environment' | 'long-vegetation' | 'summary-vegetation' | 'lifeform-summary' | 'subzone-matrix' | 'table-csv' | 'user-log' | 'plot-locations' | 'google-earth-review' | 'picture-manager' | 'plot-label-preview'>('home');
  let projectAdminTab = $state<'lifecycle' | 'compliance' | 'optimizeveg' | 'merge' | 'cloudsync'>('lifecycle');
  let projectAdminTabNonce = $state(0), newSiviModalOpen = $state(false);
  let standaloneMetadataPlot = $state('');
  let standaloneMetadataEditor: { hasUnsavedChanges?: () => boolean; getCloseState: () => EditorCloseState; undo: () => void } | undefined = $state();
  let helpDrawerOpen = $state(false), helpDrawerTopicId = $state('site.plot_number'), helpDrawerTab = $state<HelpDrawerTab>('inspector');
  let tourOpen = $state(false), tourInitialId = $state<string | null>(null), tourAutoOpenedContext = $state(false);
  let shortcutsModalOpen = $state(false), whatsNewModalOpen = $state(false), aboutModalOpen = $state(false);
  let userSetupOpen = $state(false);
  let resetSampleConfirmOpen = $state(false), resetSampleNotice = $state('');
  let whatsNewStatus = $state.raw<WhatsNewStatus | null>(null), whatsNewPromptDismissed = $state(false);
  let pictureManagerPlot = $state(''), plotLabelNumber = $state(''), contextExpanded = $state(false);
  let inspectorExpanded = $state(false);
  let isNarrowViewport = $state(false);
  let commandPaletteOpen = $state(false);
  let notificationDrawerOpen = $state(false);
  let notifSnapshot = $state<NotificationStateSnapshot>(notifications.getSnapshot());
  $effect(() => {
    return notifications.subscribe((next) => {
      notifSnapshot = next;
    });
  });
  const CONTEXT_EXPANDED_STORAGE_KEY = 'vpro.shell.contextExpanded';
  function toggleContextSidebar() {
    const next = !contextExpanded;
    contextExpanded = next;
    try {
      if (typeof sessionStorage !== 'undefined') {
        sessionStorage.setItem(CONTEXT_EXPANDED_STORAGE_KEY, String(next));
      }
    } catch {
      // Ignore storage failures in restricted contexts
    }
  }
  let localEditorBusy = $state(false), matrixPublicationBusy = $state(false), pictureCreationBusy = $state(false);
  let pictureLifecycleBusy = $state(false), twoPageSoilBusy = $state(false), twoPageVegetationBusy = $state(false);
  let externalSUEnvironmentBusy = $state(false), projectReportBusy = $state(false), summaryPreferenceBusy = $state(false);
  let summaryFieldListBusy = $state(false), summaryEnvironmentalBusy = $state(false);
  const editorBusy = $derived(localEditorBusy || matrixPublicationBusy || pictureCreationBusy || pictureLifecycleBusy || twoPageSoilBusy || twoPageVegetationBusy || externalSUEnvironmentBusy || summaryPreferenceBusy || summaryFieldListBusy || summaryEnvironmentalBusy || projectReportBusy);
  let secondaryPanelBusy = $state(false), siviModalBusy = $state(false), workbenchDirtyLabel = $state('');
  const companionPanelBusy = $derived(secondaryPanelBusy || siviModalBusy);
  $effect(() => {
    const state = $projectState;
    if (!state?.contextId || state.activeHierarchy === 'None' || !state.hierarchyPath) { matrixPublicationBusy = false; return; }
    const session = matrixPublicationSession({ contextId: state.contextId, hierarchy: state.activeHierarchy, hierarchyPath: state.hierarchyPath });
    return session.subscribe(() => {
      const publication = session.view();
      matrixPublicationBusy = publication.busy || publication.blocked;
      if (publication.blocked && view === 'home') view = 'subzone-matrix';
    });
  });
  $effect(() => {
    if (!summaryEnvironmentalEnabled) return;
    return summaryEnvironmentalDesktop.subscribe(() => {
      summaryEnvironmentalBusy = summaryEnvironmentalDesktop.activity().busy;
      if (summaryEnvironmentalBusy && view === 'home') view = 'summary-vegetation';
    });
  });
  $effect(() => {
    if (!summaryVegetationFieldListDesktop.enabled) return;
    return summaryVegetationFieldListDesktop.subscribe(() => {
      const activity = summaryVegetationFieldListDesktop.activity();
      summaryFieldListBusy = activity.busy || activity.blocked;
      if (summaryFieldListBusy && view === 'home') view = 'summary-vegetation';
    });
  });
  $effect(() => {
    const state = $projectState;
    if ((!summaryVegetationPreferenceSession && !summaryVegetationQualityPreferenceSession && !summaryVegetationPresentationPreferenceSession) ||
        !state?.contextId || !state.projectPath || !state.suPath) { summaryPreferenceBusy = false; return; }
    const owner = { contextId: state.contextId, project: state.activeProject, projectPath: state.projectPath, su: state.activeSU, suPath: state.suPath };
    const preferences = summaryVegetationPreferenceSession?.(owner), quality = summaryVegetationQualityPreferenceSession?.(owner),
      presentation = summaryVegetationPresentationPreferenceSession?.(owner);
    const changed = () => {
      const views = [preferences?.view(), quality?.view(), presentation?.view()];
      summaryPreferenceBusy = views.some(current => !!current && (current.busy || current.blocked || !!current.draftError));
      if (summaryPreferenceBusy && view === 'home') view = 'summary-vegetation';
    };
    const r1 = preferences?.subscribe(changed), r2 = quality?.subscribe(changed), r3 = presentation?.subscribe(changed);
    return () => { r1?.(); r2?.(); r3?.(); };
  });
  $effect(() => {
    const state = $projectState;
    if (!projectReportWorkspace || !state?.contextId || !state.projectPath || state.activeSU !== 'None' && !state.suPath) { projectReportBusy = false; return; }
    const workspace = projectReportWorkspace({ contextId: state.contextId,
      project: state.activeProject, projectPath: state.projectPath, su: state.activeSU, suPath: state.suPath ?? '' });
    return workspace.subscribe(() => {
      projectReportBusy = workspace.view().closeBlocked;
      if (projectReportBusy && view === 'home') view = 'long-vegetation';
    });
  });
  $effect(() => subscribeTwoPageSoilActivity(activity => { twoPageSoilBusy = activity.busy || activity.blocked; }));
  $effect(() => subscribeTwoPageVegetationActivity(activity => { twoPageVegetationBusy = activity.busy || activity.blocked; }));
  $effect(() => subscribeExternalSUEnvironmentActivity(activity => { externalSUEnvironmentBusy = activity.busy || activity.blocked; }));
  $effect(() => {
    const state = $projectState;
    return subscribePictureLifecycleActivity(activity => {
      pictureLifecycleBusy = activity.busy || activity.blocked;
      if (activity.owner && activity.owner.contextId === state?.contextId && activity.owner.project === state.activeProject && view === 'home') {
        pictureManagerPlot = activity.owner.plotNumber; view = 'picture-manager';
      }
    });
  });
  $effect(() => {
    const state = $projectState;
    return subscribePictureCreationActivity(activity => {
      pictureCreationBusy = activity.busy || activity.blocked;
      if (activity.owner && activity.owner.contextId === state?.contextId && activity.owner.project === state.activeProject && view === 'home') {
        pictureManagerPlot = activity.owner.plotNumber; view = 'picture-manager';
      }
    });
  });
  let archivePublicationBusy = $state(false), vegetationPublicationBusy = $state(false), lifeformPublicationBusy = $state(false);
  let summaryEnvironmentPublicationBusy = $state(false), summaryVegetationPublicationBusy = $state(false);
  const summaryPublicationBusy = $derived(summaryEnvironmentPublicationBusy || summaryVegetationPublicationBusy);
  $effect(() => {
    const state = $projectState;
    if (!state?.contextId || state.activeSU === 'None' || !state.suPath) { vegetationPublicationBusy = false; return; }
    const session = vegetationWorkbookPublicationSession({ contextId: state.contextId,
      project: state.activeProject, projectPath: state.projectPath ?? '', su: state.activeSU, suPath: state.suPath }, true);
    return session.subscribe(() => {
      const publication = session.view();
      vegetationPublicationBusy = publication.busy || publication.blocked;
      if (publication.blocked && view === 'home') view = 'long-vegetation';
    });
  });
  $effect(() => {
    const state = $projectState;
    if (!state?.contextId || state.activeSU === 'None' || !state.suPath) { lifeformPublicationBusy = false; return; }
    const session = lifeformWorkbookPublicationSession({ contextId: state.contextId,
      project: state.activeProject, projectPath: state.projectPath ?? '', su: state.activeSU, suPath: state.suPath });
    return session.subscribe(() => {
      const publication = session.view();
      lifeformPublicationBusy = publication.busy || publication.blocked;
      if (publication.blocked && view === 'home') view = 'lifeform-summary';
    });
  });
  $effect(() => {
    const state = $projectState;
    if (!state?.contextId) { archivePublicationBusy = false; return; }
    const session = tableCSVArchivePublicationSession({ contextId: state.contextId, project: state.activeProject, projectPath: state.projectPath ?? '' });
    return session.subscribe(() => {
      const publication = session.view();
      archivePublicationBusy = publication.busy || publication.blocked;
      if (publication.blocked && view === 'home') view = 'table-csv';
    });
  });
  $effect(() => {
    const state = $projectState;
    if (!state?.contextId || state.activeSU === 'None' || !state.suPath) { summaryEnvironmentPublicationBusy = false; return; }
    const owner = { contextId: state.contextId, project: state.activeProject, projectPath: state.projectPath ?? '', su: state.activeSU, suPath: state.suPath };
    const sessions = [siteUnitSummaryWorkbookPublicationSession(owner), extendedSummaryWorkbookPublicationSession(owner)];
    const update = () => {
      const states = sessions.map(session => session.view());
      const publication = { busy: states.some(state => state.busy), blocked: states.some(state => state.blocked) };
      summaryEnvironmentPublicationBusy = publication.busy || publication.blocked;
      if (publication.blocked && view === 'home') view = 'summary-environment';
    };
    const unsubscribe = sessions.map(session => session.subscribe(update));
    return () => { for (const stop of unsubscribe) stop(); };
  });
  $effect(() => {
    const state = $projectState;
    if (!state?.contextId || state.activeSU === 'None' || !state.suPath) { summaryVegetationPublicationBusy = false; return; }
    const session = summaryVegetationWorkbookSession({ contextId: state.contextId, project: state.activeProject,
      projectPath: state.projectPath ?? '', su: state.activeSU, suPath: state.suPath });
    return session.subscribe(() => {
      summaryVegetationPublicationBusy = session.held();
      if (session.held() && view === 'home') view = 'summary-vegetation';
    });
  });
  let editor: FS882EditorHandle | undefined = $state();
  let fs882ModuleLoaded = $state(false);
  const editorInitializing = $derived(view === 'fs882' && !editor && fs882ModuleLoaded);

  async function loadFS882Editor(): Promise<{ default: Component<FS882FormWave3Props, FS882EditorHandle> }> {
    const module = await import('./entry/FS882Form.svelte');
    fs882ModuleLoaded = true;
    return module as unknown as { default: Component<FS882FormWave3Props, FS882EditorHandle> };
  }

  let closeRequest = $state(''), closeWorking = $state(false), closeError = $state('');
  let pendingTransition = $state<{ contextId: string; run: (contextId: string) => Promise<void> } | null>(null);
  let transitionWorking = $state(false), transitionError = $state('');
  let plotProfilePanel: {
    reviewProfileSU: (proposal: ProjectPlotProfileFilterRequest, origin: string) => Promise<void>;
    clearCachedSources: () => void; resetAllReviews: () => void;
  } | undefined = $state();
  const plotFindEnabled = true;
  let plotFindOpen = $state(false), plotFindQuery = $state(''), plotFindError = $state('');
  let plotFindResult = $state<Awaited<ReturnType<typeof ContextService.LookupScopedPlot>> | null>(null);
  let startupInfo = $state<StartupState | null>(null), startupFailure = $state<StartupState | null>(null);
  const buildMode = $derived(startupInfo?.buildMode ?? ''), appVersion = $derived(startupInfo?.appVersion ?? '');
  const shortBuildCommit = $derived.by(() => {
    const raw = (startupInfo?.gitCommit ?? '').trim();
    return /^[0-9a-f]{8,40}$/i.test(raw) ? raw.slice(0, 7) : raw;
  });
  const releaseChannel = $derived(startupInfo?.releaseChannel ?? 'stable');
  let startupBackupNotice = $state('');
  const closeState = $derived(view === 'fs882' ? editor?.getCloseState() : undefined);
  $effect(() => {
    if (
      (error === 'Wait for the current operation or decision before changing context.' ||
        error === 'Wait for the current operation to finish before closing VPRO.') &&
      !busy && !editorBusy && !companionPanelBusy && !transitionWorking &&
      !archivePublicationBusy && !vegetationPublicationBusy && !lifeformPublicationBusy &&
      !summaryPublicationBusy && pendingTransition === null && !closeRequest && !editorInitializing
    ) {
      error = '';
    }
  });

  let lastPushedError = '';
  $effect(() => {
    const currentError = error;
    if (!currentError) {
      lastPushedError = '';
      return;
    }
    if (currentError === lastPushedError) return;
    lastPushedError = currentError;
    if (typeof notifications !== 'undefined') {
      const isPause = currentError.startsWith('Wait for ') || currentError.startsWith('Save or discard ');
      notifications.push({
        severity: isPause ? 'warning' : 'error',
        category: 'general',
        source: 'Workspace',
        title: currentError.startsWith('Wait for ') ? 'Navigation paused' : 'Workspace alert',
        message: currentError,
        toast: true,
      });
    }
  });

  async function handleCloseRequest(requestId: string) {
    if (closeWorking || closeRequest === requestId) return;
    try {
      if (await LifecycleService.GetPendingCloseRequest() !== requestId) return;
      if (document.activeElement instanceof HTMLElement) document.activeElement.blur();
      await tick();
      const hasStandaloneMetaDirty = typeof standaloneMetadataPlot !== 'undefined' && Boolean(standaloneMetadataPlot && standaloneMetadataEditor?.hasUnsavedChanges?.());
      const hasWorkbenchDirty = (typeof workbenchDirtyLabel !== 'undefined' && Boolean(workbenchDirtyLabel)) || hasStandaloneMetaDirty;
      const state = view === 'fs882' ? editor?.getCloseState() ?? null : null;
      const disposition = closeDisposition(state, busy || editorBusy || transitionWorking || archivePublicationBusy || vegetationPublicationBusy || lifeformPublicationBusy || summaryPublicationBusy || pendingTransition !== null || editorInitializing || (typeof companionPanelBusy !== 'undefined' && companionPanelBusy));
      if (disposition === 'busy') {
        await LifecycleService.CancelClose(requestId);
        error = hasWorkbenchDirty ? 'Save or discard unsaved workbench edits before closing VPro.' : 'Wait for the current operation to finish before closing VPRO.';
      } else if (hasWorkbenchDirty) {
        await LifecycleService.CancelClose(requestId);
        error = 'Save or discard unsaved workbench edits before closing VPro.';
      } else if (disposition === 'clean') {
        await LifecycleService.ConfirmClose(requestId);
      } else { closeError = ''; closeRequest = requestId; }
    } catch (cause) { error = `Window close request failed: ${String(cause)}`; }
  }

  async function respondToClose(decision: CloseDecision) {
    if (!closeRequest || closeWorking) return;
    const requestId = closeRequest;
    closeWorking = true; closeError = '';
    try {
      if (decision === 'cancel') { await LifecycleService.CancelClose(requestId); closeRequest = ''; return; }
      const state = view === 'fs882' ? editor?.getCloseState() ?? null : null;
      if (closeDisposition(state, busy || editorBusy || transitionWorking || archivePublicationBusy || vegetationPublicationBusy || lifeformPublicationBusy || summaryPublicationBusy || pendingTransition !== null || editorInitializing || (typeof companionPanelBusy !== 'undefined' && companionPanelBusy)) === 'busy') {
        closeError = 'Wait for the current operation to finish before closing VPRO.'; return;
      }
      if (decision === 'save') {
        if (!editor || !await editor.saveForClose()) {
          closeError = editor?.getCloseState().error ?? 'The draft could not be saved. VPRO remains open.'; return;
        }
      }
      await LifecycleService.ConfirmClose(requestId);
    } catch (cause) { closeError = `VPRO remains open: ${String(cause)}`; }
    finally { closeWorking = false; }
  }

  async function requestTransition(run: (contextId: string) => Promise<void>, ownedAction?: () => boolean) {
    if (document.activeElement instanceof HTMLElement) document.activeElement.blur();
    await tick();
    if (ownedAction && !ownedAction()) { error = 'Owned action or editor availability changed; no editor replaced.'; return; }
    const hasStandaloneMetaDirty = typeof standaloneMetadataPlot !== 'undefined' && Boolean(standaloneMetadataPlot && standaloneMetadataEditor?.hasUnsavedChanges?.());
    if (!ownedAction && ((typeof workbenchDirtyLabel !== 'undefined' && workbenchDirtyLabel) || hasStandaloneMetaDirty)) {
      error = 'Save or discard unsaved workbench edits before changing context or view.'; return;
    }
    const state = view === 'fs882' ? editor?.getCloseState() ?? null : null;
    if (closeDisposition(ownedAction ? null : state, busy || !ownedAction && editorBusy || transitionWorking || archivePublicationBusy || vegetationPublicationBusy || lifeformPublicationBusy || summaryPublicationBusy || pendingTransition !== null || !!closeRequest || editorInitializing || (!ownedAction && typeof companionPanelBusy !== 'undefined' && companionPanelBusy)) === 'busy') {
      error = 'Wait for the current operation or decision before changing context.';
      if (typeof notifications !== 'undefined') {
        lastPushedError = error;
        notifications.warning?.('Navigation paused', error, { toast: true, source: 'Workspace' });
      }
      return;
    }
    const contextId = $projectState?.contextId;
    if (!contextId) { error = 'A project context must finish loading before navigation.'; return; }
    transitionError = '';
    if (state?.unsaved && !ownedAction) { pendingTransition = { contextId, run }; return; }
    try { await run(contextId); } catch (cause) { error = String(cause); }
  }

  async function respondToTransition(decision: CloseDecision) {
    if (!pendingTransition || transitionWorking) return;
    if (decision === 'cancel') { pendingTransition = null; transitionError = ''; return; }
    const pending = pendingTransition;
    transitionWorking = true; transitionError = '';
    try {
      const state = editor?.getCloseState();
      if (!state || closeDisposition(state, busy || editorBusy || vegetationPublicationBusy || lifeformPublicationBusy || summaryPublicationBusy || (typeof companionPanelBusy !== 'undefined' && companionPanelBusy)) === 'busy') {
        transitionError = 'Wait for the current editor operation to finish.'; return;
      }
      if (decision === 'save' && state.unsaved && !await editor?.saveForClose()) {
        transitionError = editor?.getCloseState().error ?? 'The draft could not be saved; context and draft remain open.'; return;
      }
      await pending.run(pending.contextId);
      pendingTransition = null;
    } catch (cause) { transitionError = `Context remains unchanged: ${String(cause)}`; }
    finally { transitionWorking = false; }
  }

  function navigate(next: typeof view | 'fs882-twopage') {
    const standaloneOpen = typeof standaloneMetadataPlot !== 'undefined' && Boolean(standaloneMetadataPlot);
    if (!standaloneOpen) {
      if (next === 'fs882-twopage' && view === 'fs882' && editorEntryForm === 'fs882-twopage') return;
      if (next === 'fs882' && view === 'fs882' && editorEntryForm === 'fs882') return;
      if (next === view && next !== 'project-admin' && next !== 'fs882') return;
    }
    void requestTransition(async () => {
      error = '';
      if (typeof standaloneMetadataPlot !== 'undefined') standaloneMetadataPlot = '';
      if (next === 'project-admin') { projectAdminTab = 'lifecycle'; projectAdminTabNonce++; }
      if (next === 'fs882-twopage') {
        editorPlotNumber = (view === 'fs882' ? editorPlotNumber : undefined) ?? selected?.plotNumber;
        editorEntryForm = 'fs882-twopage';
        diagnosticsDraft = null;
        view = 'fs882';
        return;
      }
      if (next === 'fs882') {
        editorPlotNumber = (view === 'fs882' ? editorPlotNumber : undefined) ?? selected?.plotNumber;
        editorEntryForm = 'fs882';
        diagnosticsDraft = null;
      }
      if (next === 'picture-manager') pictureManagerPlot = selected?.plotNumber ?? '';
      if (next === 'plot-label-preview') plotLabelNumber = (view === 'fs882' ? editorPlotNumber : selected?.plotNumber) ?? '';
      view = next;
    });
  }

  async function openSIVI() {
    if (!siviStandaloneEnabled || !selected || !$projectState?.contextId) {
      error = 'Standalone SIVI requires its independent entry gate, parent review and a selected owned plot.'; return;
    }
    const plot = selected.plotNumber;
    await requestTransition(async () => {
      if (selected?.plotNumber !== plot) throw new Error('Selected plot changed before opening SIVI; no owner replaced.');
      editorPlotNumber = plot; editorEntryForm = 'sivi'; diagnosticsDraft = null; view = 'fs882'; error = '';
    });
  }

  async function openProjectMetadata() {
    const inPlotEditor = view === 'fs882' && !((typeof editorPlotNumber === 'undefined' || !editorPlotNumber) && typeof editorEntryForm !== 'undefined' && editorEntryForm === 'fs882-twopage');
    if (inPlotEditor) {
      if (!editor || !$projectState?.contextId || !editor.canOpenProjectMetadata()) {
        error = 'Project metadata requires its existing gate and a clean, unlocked open plot; finish or Undo drafts first.'; return;
      }
      const owner = editor, contextId = $projectState.contextId;
      const ownedAction = owner.canOpenMetadataInPlace?.()
        ? () => view === 'fs882' && editor === owner && $projectState?.contextId === contextId && owner.canOpenMetadataInPlace?.() === true
        : undefined;
      await requestTransition(async currentContext => {
        if (view !== 'fs882' || editor !== owner || currentContext !== contextId || $projectState?.contextId !== contextId || !owner.canOpenProjectMetadata()) {
          throw new Error('Project metadata owner or availability changed; no editor replaced.');
        }
        owner.openProjectMetadata();
      }, ownedAction);
      return;
    }
    if (!$projectState?.contextId) {
      error = 'Open a project before reviewing project metadata.'; return;
    }
    const contextId = $projectState.contextId;
    await requestTransition(async currentContext => {
      if (currentContext !== contextId || $projectState?.contextId !== contextId) {
        throw new Error('Project metadata owner or availability changed; no editor replaced.');
      }
      const available = typeof allAvailablePlots !== 'undefined' ? allAvailablePlots : [];
      let targetPlot = (typeof selected !== 'undefined' && selected?.plotNumber) || available[0]?.plotNumber || '';
      if (!targetPlot && typeof ContextService !== 'undefined' && typeof ContextService?.ListPlots === 'function') {
        const firstPage = await plotReads.track(ContextService.ListPlots(0, 1));
        if ($projectState?.contextId !== contextId) return;
        targetPlot = firstPage?.plots?.[0]?.plotNumber ?? '';
      }
      if (!targetPlot) {
        if (typeof standaloneMetadataPlot !== 'undefined') standaloneMetadataPlot = '';
        projectAdminTab = 'lifecycle';
        projectAdminTabNonce++;
        view = 'project-admin';
        error = '';
        return;
      }
      standaloneMetadataPlot = targetPlot;
      error = '';
    });
  }

  async function resolveNavigation(proposal: ProjectPlotProfileFilterRequest, contextId: string): Promise<ProfileNavigation> {
    const response = await plotReads.track(ContextService.ResolveProjectPlotProfileNavigation(contextId, proposal));
    if ($projectState?.contextId !== contextId) throw new Error('Project/SU context changed; navigation was not published.');
    return validateProfileNavigation(response, proposal, contextId);
  }

  async function applyProfileNavigation(proposal: ProjectPlotProfileFilterRequest, origin: string) {
    await requestTransition(async contextId => {
      if (contextId !== origin) throw new Error('Profile proposal belongs to an old context.');
      busy = true;
      try {
        await tick();
        const next = await resolveNavigation(proposal, contextId);
        const nextPage = profileNavigationPage(next, contextId, 0, pageSize);
        request++; plotReads.cancelAll();
        profileNavigation = next; page = nextPage; offset = 0; selected = null;
        editorPlotNumber = undefined; view = 'plots'; error = '';
      } finally { busy = false; }
    });
  }

  async function clearProfileNavigation() {
    await requestTransition(async contextId => {
      busy = true;
      try {
        await tick();
        const next = await plotReads.track(ContextService.ListPlots(0, pageSize));
        const state = await stateReads.track(ContextService.GetState());
        if (state.contextId !== contextId || $projectState?.contextId !== contextId) throw new Error('Context changed before clearing navigation.');
        request++; plotReads.cancelAll();
        profileNavigation = null; page = next; offset = 0; selected = null;
        editorPlotNumber = undefined; view = 'plots'; error = '';
      } finally { busy = false; }
    });
  }

  async function lookupPlot(number: string, contextId: string) {
    const invalid = plotLookupInputError(number);
    if (invalid) throw new Error(invalid);
    const source = profileNavigation;
    if (source) {
      if (source.contextId !== contextId) throw new Error('Reviewed profile navigation belongs to an old context.');
      const next = await resolveNavigation(source.proposal, contextId);
      if (!next.plots.some(plot => plot.plotNumber === number)) throw new Error('Literal plot is outside the reviewed profile navigation; current filter is unchanged.');
    }
    const result = await stateReads.track(ContextService.LookupScopedPlot(contextId, { plotNumber: number }));
    if ($projectState?.contextId !== contextId) throw new Error('Find belongs to an old context; current editor is unchanged.');
    return validateScopedPlotLookup(result, number, contextId);
  }

  async function findScopedPlot() {
    const contextId = $projectState?.contextId;
    if (!plotFindEnabled || !contextId || busy || editorBusy || (typeof companionPanelBusy !== 'undefined' && companionPanelBusy) || vegetationPublicationBusy || lifeformPublicationBusy || summaryPublicationBusy || transitionWorking || pendingTransition !== null || closeRequest) return;
    const number = plotFindQuery;
    busy = true; plotFindError = ''; plotFindResult = null;
    try { await tick(); plotFindResult = await lookupPlot(number, contextId); }
    catch (cause) { plotFindError = `No navigation or data change; find failed: ${String(cause)}`; }
    finally { busy = false; }
  }

  async function openFoundPlot() {
    if (!plotFindEnabled || !plotFindResult || plotFindResult.contextId !== $projectState?.contextId) {
      plotFindError = 'Find an available plot in the current scope before opening it.'; return;
    }
    const proposal = $state.snapshot(plotFindResult);
    if (proposal.plot.plotNumber === editorPlotNumber) { plotFindError = 'Found plot is already open; no draft or navigation change.'; return; }
    await requestTransition(async contextId => {
      if (contextId !== proposal.contextId) throw new Error('Found plot belongs to an old context; find again.');
      busy = true; plotFindError = '';
      try {
        await tick();
        const current = await lookupPlot(proposal.plot.plotNumber, contextId);
        if (JSON.stringify(current) !== JSON.stringify(proposal)) throw new Error('Found plot summary changed since review; find again before opening.');
        editorPlotNumber = current.plot.plotNumber; diagnosticsDraft = null; view = 'fs882'; selected = null;
        plotFindOpen = false; plotFindResult = null; error = '';
      } catch (cause) {
        plotFindError = `Navigation failed; current editor and filters retained: ${String(cause)}`;
        throw cause;
      } finally { busy = false; }
    });
  }

  async function navigateProfilePlot(delta: number) {
    const source = profileNavigation, target = source?.plots[profileIndex + delta]?.plotNumber;
    if (!source || !target) { error = 'Select an available plot in the reviewed navigation recordset.'; return; }
    await requestTransition(async contextId => {
      if (contextId !== source.contextId) throw new Error('Profile navigation belongs to an old context.');
      busy = true;
      try {
        await tick();
        const next = await resolveNavigation(source.proposal, contextId);
        if (!next.plots.some(plot => plot.plotNumber === target)) throw new Error('Reviewed navigation target is no longer available.');
        profileNavigation = next; editorPlotNumber = target; diagnosticsDraft = null; view = 'fs882'; error = '';
      } finally { busy = false; }
    });
  }

  async function loadPlots(nextOffset: number) {
    if (projectReportBusy || twoPageVegetationBusy || twoPageSoilBusy || pictureCreationBusy || pictureLifecycleBusy || vegetationPublicationBusy || lifeformPublicationBusy || summaryPublicationBusy || summaryPreferenceBusy || externalSUEnvironmentBusy || (typeof companionPanelBusy !== 'undefined' && companionPanelBusy) || (view === 'long-vegetation' || view === 'lifeform-summary' || view === 'summary-environment' || view === 'summary-vegetation' || view === 'user-log' || view === 'subzone-matrix') && editorBusy) return;
    const current = ++request;
    plotReads.cancelAll(); busy = true; error = '';
    try {
      const source = profileNavigation;
      const next = source ? await resolveNavigation(source.proposal, source.contextId) : null;
      const result = next ? profileNavigationPage(next, next.contextId, nextOffset, pageSize) :
        await plotReads.track(ContextService.ListPlots(nextOffset, pageSize));
      if (current !== request) return;
      if (next) profileNavigation = next;
      page = result; offset = nextOffset; selected = null;
    } catch (cause) { if (current === request) error = String(cause); }
    finally { if (current === request) busy = false; }
  }

  async function refresh() {
    if (projectReportBusy || twoPageVegetationBusy || twoPageSoilBusy || pictureCreationBusy || pictureLifecycleBusy || vegetationPublicationBusy || lifeformPublicationBusy || summaryPublicationBusy || summaryPreferenceBusy || externalSUEnvironmentBusy || (typeof companionPanelBusy !== 'undefined' && companionPanelBusy) || (view === 'long-vegetation' || view === 'lifeform-summary' || view === 'summary-environment' || view === 'summary-vegetation' || view === 'user-log' || view === 'subzone-matrix') && editorBusy) return;
    const current = ++stateRequest;
    stateReads.cancelAll(); busy = true; error = '';
    try {
      const startup = await stateReads.track(LifecycleService.GetStartupState());
      if (current !== stateRequest) return;
      startupInfo = startup;
      if (!startup.ready) { startupFailure = startup; busy = false; return; }
      startupFailure = null;
      const state = await stateReads.track(ContextService.GetState());
      if (current !== stateRequest) return;
      projectState.set(state);
      if (profileNavigation && profileNavigation.contextId !== state.contextId) profileNavigation = null;
      await loadPlots(0);
      if (current !== stateRequest) return;
      await loadHierarchy();
    } catch (cause) { if (current === stateRequest) { error = String(cause); busy = false; } }
  }

  async function loadHierarchy() {
    if (projectReportBusy || twoPageVegetationBusy || twoPageSoilBusy || pictureCreationBusy || pictureLifecycleBusy || vegetationPublicationBusy || lifeformPublicationBusy || summaryPublicationBusy || summaryPreferenceBusy || externalSUEnvironmentBusy || (typeof companionPanelBusy !== 'undefined' && companionPanelBusy) || (view === 'long-vegetation' || view === 'lifeform-summary' || view === 'summary-environment' || view === 'summary-vegetation' || view === 'user-log' || view === 'subzone-matrix') && editorBusy) return;
    const current = ++hierarchyRequest;
    hierarchyReads.cancelAll();
    try {
      const nodes = await hierarchyReads.track(ContextService.GetHierarchyNodes());
      if (current === hierarchyRequest) hierarchyNodes = nodes ?? [];
    } catch (cause) { if (current === hierarchyRequest) throw cause; }
  }

  function cancelAllReads() {
    request++; hierarchyRequest++; stateRequest++;
    plotReads.cancelAll(); hierarchyReads.cancelAll(); stateReads.cancelAll();
    if (typeof catalogPlotReads !== 'undefined') {
      catalogPlotRequest++; paletteSearchRequest++;
      catalogPlotReads.cancelAll(); paletteSearchReads.cancelAll();
    }
  }

  async function reviewProfileSU(proposal: ProjectPlotProfileFilterRequest, origin: string) {
    if (!plotProfilePanel) throw new Error('Plot profile panel is not ready.');
    await plotProfilePanel.reviewProfileSU(proposal, origin);
  }

  async function switchContext(contextId: string, selection: ContextSelection, next: 'plots' | 'hierarchy') {
    cancelAllReads(); busy = true; error = '';
    try {
      const state = await ContextService.SwitchContext(contextId, selection);
      request++; projectState.set(state); profileNavigation = null; plotProfilePanel?.clearCachedSources();
      scopedCatalogKey = ''; scopedPlotCatalogRows = []; dynamicPalettePlotRows = []; createdSiviPlots = [];
      standaloneMetadataPlot = '';
      page = null; selected = null; hierarchyNodes = []; editorPlotNumber = undefined; diagnosticsDraft = null; view = next;
      await loadPlots(0);
      if (next === 'hierarchy') {
        try { await loadHierarchy(); }
        catch (cause) { error = `Context changed, but hierarchy refresh failed: ${String(cause)}`; }
      }
      if (typeof window !== 'undefined' && window.innerWidth < 1200) {
        contextExpanded = false;
      }
    } catch (cause) {
      notifications.push({
        severity: 'error',
        category: 'general',
        source: 'Context Switch',
        title: 'Context switch failed',
        message: String(cause),
      });
      throw cause;
    } finally { busy = false; }
  }

  async function handleAccessActivated() {
    scopedCatalogKey = ''; scopedPlotCatalogRows = []; dynamicPalettePlotRows = []; createdSiviPlots = [];
    standaloneMetadataPlot = '';
    profileNavigation = null; plotProfilePanel?.resetAllReviews(); editorPlotNumber = undefined; diagnosticsDraft = null; view = 'plots';
    await loadPlots(0);
  }

  function openContextualHelp(topicOverride?: string, tabOverride: HelpDrawerTab = 'inspector') {
    const activeEl = typeof document !== 'undefined' ? document.activeElement : null;
    helpDrawerTopicId = topicOverride ?? resolveContextualHelpTarget(activeEl, view, editorEntryForm);
    helpDrawerTab = tabOverride; helpDrawerOpen = true;
  }

  function handleGlobalHelpKeydown(event: KeyboardEvent) {
    if (startupFailure !== null) return;
    if ((event.ctrlKey || event.metaKey) && typeof event.key === 'string' && event.key.toLowerCase() === 'k') {
      event.preventDefault();
      commandPaletteOpen = !commandPaletteOpen;
      return;
    }
    const activeEl = typeof document !== 'undefined' ? (document.activeElement as HTMLElement | null) : null;
    const action = classifyGlobalHelpShortcut(event, activeEl);
    if (action === 'f1') { event.preventDefault(); openContextualHelp(); return; }
    if (action === 'shortcuts') { event.preventDefault(); shortcutsModalOpen = !shortcutsModalOpen; return; }
    if (event.key === 'Escape' && !commandPaletteOpen && !notificationDrawerOpen && !shortcutsModalOpen && !whatsNewModalOpen && !aboutModalOpen && !tourOpen && !resetSampleConfirmOpen && !userSetupOpen && !closeRequest && !pendingTransition) {
      if (helpDrawerOpen) {
        event.preventDefault();
        helpDrawerOpen = false;
        return;
      }
      if (isNarrowViewport && (contextExpanded || showInspectorRail)) {
        event.preventDefault();
        contextExpanded = false;
        inspectorExpanded = false;
      }
    }
  }

  function handleHelpMenuAction(action: HelpMenuAction) {
    resetSampleNotice = '';
    if (action === 'guide') openContextualHelp(undefined, 'inspector');
    else if (action === 'tours') { tourInitialId = null; tourOpen = true; }
    else if (action === 'shortcuts') shortcutsModalOpen = true;
    else if (action === 'whats-new') whatsNewModalOpen = true;
    else if (action === 'reset-sample') resetSampleConfirmOpen = true;
    else if (action === 'about') aboutModalOpen = true;
  }

  async function acknowledgeUnreadWhatsNew() {
    if (!whatsNewStatus?.latestVersion) return;
    try { whatsNewStatus = await defaultHelpPort.acknowledgeWhatsNew(whatsNewStatus.latestVersion); }
    catch (cause) { error = `Could not acknowledge What's New: ${String(cause)}`; }
  }

  async function confirmResetWorkspaceToSample() {
    resetSampleConfirmOpen = false;
    const ownedDiscardOnSample = $projectState?.activeProject === 'Sample' ? () => !editorBusy && !companionPanelBusy : undefined;
    await requestTransition(async (contextId) => {
      busy = true; error = ''; resetSampleNotice = '';
      try {
        const nextState = await defaultHelpPort.resetWorkspaceToSample(contextId);
        cancelAllReads(); projectState.set(nextState); profileNavigation = null; plotProfilePanel?.clearCachedSources();
        scopedCatalogKey = ''; scopedPlotCatalogRows = []; dynamicPalettePlotRows = []; createdSiviPlots = [];
        standaloneMetadataPlot = '';
        selected = null; page = null; hierarchyNodes = []; editorPlotNumber = undefined; diagnosticsDraft = null; resetSampleConfirmOpen = false; view = 'plots';
        resetSampleNotice = 'Workspace reset to the built-in Sample project (Project: Sample, SU: Sample, Hierarchy: Sample). Your own project files were preserved.';
        notifications.push({
          severity: 'success',
          category: 'general',
          source: 'Workspace',
          title: 'Workspace reset to Sample project',
          message: 'User project .db files were preserved.',
        });
        await loadPlots(0);
        try { await loadHierarchy(); }
        catch (cause) { error = `Sample workspace activated, but hierarchy refresh failed: ${String(cause)}`; }
      } finally { busy = false; }
    }, ownedDiscardOnSample);
  }

  async function refreshScopedPlotCatalog(expectedContextId: string, currentPage: PlotPage | null, force = false) {
    const SCOPED_PLOT_CATALOG_CAP = 2000;
    const SCOPED_PLOT_CHUNK_SIZE = 200;
    if (!expectedContextId || !currentPage || typeof currentPage.total !== 'number' || !Array.isArray(currentPage.plots)) return;
    if (typeof ContextService?.ListPlots !== 'function') return;
    const navKey = profileNavigation ? `profile:${profileNavigation.contextId}:${profileNavigation.plots.length}` : 'default';
    const nextKey = `${expectedContextId}|${$projectState?.activeProject ?? ''}|${$projectState?.activeSU ?? ''}|${currentPage.total}|${navKey}`;
    if (!force && nextKey === scopedCatalogKey && scopedPlotCatalogRows.length > 0) return;
    const current = ++catalogPlotRequest;
    catalogPlotReads.cancelAll();
    try {
      if (typeof ContextService.ListCreatedSIVIPlots === 'function') {
        try {
          const created = await catalogPlotReads.track(ContextService.ListCreatedSIVIPlots(expectedContextId));
          if (current !== catalogPlotRequest || $projectState?.contextId !== expectedContextId) return;
          createdSiviPlots = (created ?? []).map((entry) => ({
            requestId: entry.requestId,
            plotNumber: entry.plotNumber,
            canUndo: Boolean(entry.canUndo && !entry.undone),
          }));
        } catch {
          if (current === catalogPlotRequest) createdSiviPlots = [];
        }
      }
      if (profileNavigation && profileNavigation.contextId === expectedContextId) {
        scopedPlotCatalogRows = profileNavigation.plots;
        scopedCatalogKey = nextKey;
        return;
      }
      const total = currentPage.total;
      if (total <= currentPage.plots.length && offset === 0) {
        scopedPlotCatalogRows = currentPage.plots;
        scopedCatalogKey = nextKey;
        return;
      }
      const targetCount = Math.min(total, SCOPED_PLOT_CATALOG_CAP);
      const collected: PlotSummary[] = [];
      for (let nextOff = 0; nextOff < targetCount; nextOff += SCOPED_PLOT_CHUNK_SIZE) {
        const limit = Math.min(SCOPED_PLOT_CHUNK_SIZE, targetCount - nextOff);
        const chunk = await catalogPlotReads.track(ContextService.ListPlots(nextOff, limit));
        if (current !== catalogPlotRequest || $projectState?.contextId !== expectedContextId) return;
        if (!chunk || !Array.isArray(chunk.plots) || chunk.plots.length === 0) break;
        collected.push(...chunk.plots);
        if (chunk.plots.length < limit) break;
      }
      if (current === catalogPlotRequest && $projectState?.contextId === expectedContextId) {
        scopedPlotCatalogRows = collected;
        scopedCatalogKey = nextKey;
      }
    } catch {
      // Keep current page rows available if background catalog pagination cancels
    }
  }

  $effect(() => {
    const ctxId = $projectState?.contextId ?? '';
    const currentPage = page;
    const _nav = profileNavigation;
    if (!ctxId || !currentPage || typeof currentPage.total !== 'number' || !Array.isArray(currentPage.plots)) return;
    if (busy || projectReportBusy || twoPageVegetationBusy || twoPageSoilBusy || pictureCreationBusy || pictureLifecycleBusy || vegetationPublicationBusy || lifeformPublicationBusy || summaryPublicationBusy || summaryPreferenceBusy || externalSUEnvironmentBusy) return;
    void _nav;
    void refreshScopedPlotCatalog(ctxId, currentPage);
  });

  function extractDatasheetPlotSummaries(dsPage: Awaited<ReturnType<typeof DatasheetService.GetDatasheetPage>>): PlotSummary[] {
    if (!dsPage?.columns || !dsPage?.rows) return [];
    const colIdx = new Map<string, number>();
    dsPage.columns.forEach((col, idx) => colIdx.set(col.name.toLowerCase(), idx));
    const cellStr = (cells: Array<{ text: string | null; integer: string | null; real: number | null }> | null | undefined, name: string): string | null => {
      const idx = colIdx.get(name.toLowerCase());
      if (idx === undefined || !cells || !cells[idx]) return null;
      const c = cells[idx];
      if (c.text !== null && c.text !== undefined) return c.text;
      if (c.integer !== null && c.integer !== undefined) return String(c.integer);
      if (c.real !== null && c.real !== undefined) return String(c.real);
      return null;
    };
    const out: PlotSummary[] = [];
    for (const row of dsPage.rows) {
      const pn = cellStr(row.cells, 'plotnumber');
      if (!pn) continue;
      out.push({
        plotNumber: pn,
        fieldNumber: cellStr(row.cells, 'fieldnumber'),
        plotRepresenting: cellStr(row.cells, 'plotrepresenting'),
        zone: cellStr(row.cells, 'zone'),
        subZone: cellStr(row.cells, 'subzone'),
        siteSeries: cellStr(row.cells, 'siteseries'),
      });
    }
    return out;
  }

  $effect(() => {
    if (!commandPaletteOpen || typeof document === 'undefined') {
      paletteSearchRequest++;
      paletteSearchReads.cancelAll();
      dynamicPalettePlotRows = [];
      return;
    }
    const ctxId = $projectState?.contextId ?? '';
    const totalPlots = page?.total ?? 0;
    if (!ctxId || profileNavigation || totalPlots <= scopedPlotCatalogRows.length) return;
    let debounceTimer: ReturnType<typeof setTimeout> | null = null;
    const runDynamicSearch = (rawQuery: string) => {
      const cleaned = rawQuery.trim().replace(/^plot\s+/i, '').trim();
      if (!cleaned) {
        paletteSearchRequest++;
        paletteSearchReads.cancelAll();
        dynamicPalettePlotRows = [];
        return;
      }
      const reqId = ++paletteSearchRequest;
      paletteSearchReads.cancelAll();
      void (async () => {
        try {
          const scopeToActiveSU = ($projectState?.activeSU ?? 'None') !== 'None';
          const dsPage = await paletteSearchReads.track(
            DatasheetService.GetDatasheetPage(ctxId, {
              tableKey: 'Env',
              offset: 0,
              limit: 50,
              sort: null,
              filters: null,
              globalSearch: cleaned,
              scopeToActiveSU,
            })
          );
          if (reqId !== paletteSearchRequest || $projectState?.contextId !== ctxId) return;
          dynamicPalettePlotRows = extractDatasheetPlotSummaries(dsPage);
        } catch {
          // Ignore transient cancellation during typing
        }
      })();
    };
    const handleInput = (ev: Event) => {
      const target = ev.target as HTMLInputElement | null;
      if (!target || !target.matches?.('[data-command-palette-input]')) return;
      if (debounceTimer) clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => runDynamicSearch(target.value), 120);
    };
    document.addEventListener('input', handleInput, true);
    return () => {
      if (debounceTimer) clearTimeout(debounceTimer);
      document.removeEventListener('input', handleInput, true);
    };
  });

  const loadedPlotRows = $derived<PlotSummary[]>(
    (page as (PlotPage & { rows?: PlotSummary[] }) | null)?.plots ??
      (page as { rows?: PlotSummary[] } | null)?.rows ??
      []
  );
  const allAvailablePlots = $derived.by<PlotSummary[]>(() => {
    if (profileNavigation) return profileNavigation.plots;
    const merged = new Map<string, PlotSummary>();
    for (const row of scopedPlotCatalogRows) {
      if (row?.plotNumber) merged.set(row.plotNumber, row);
    }
    for (const row of loadedPlotRows) {
      if (row?.plotNumber && !merged.has(row.plotNumber)) merged.set(row.plotNumber, row);
    }
    for (const row of dynamicPalettePlotRows) {
      if (row?.plotNumber && !merged.has(row.plotNumber)) merged.set(row.plotNumber, row);
    }
    return merged.size > 0 ? Array.from(merged.values()) : loadedPlotRows;
  });
  const canUndoSelectedPlot = $derived(
    Boolean(selected?.plotNumber && createdSiviPlots.some((entry) => entry.plotNumber === selected?.plotNumber && entry.canUndo))
  );
  const canUndoEditorPlot = $derived(
    Boolean(editorPlotNumber && createdSiviPlots.some((entry) => entry.plotNumber === editorPlotNumber && entry.canUndo))
  );

  async function copyPlotToNewNumber(sourcePlot: string, rawTargetPlot: string) {
    if (busy || editorBusy || companionPanelBusy || transitionWorking || pendingTransition !== null || !!closeRequest) {
      throw new Error('Wait for the current operation to finish first.');
    }
    if ((view === 'fs882' && editor?.getCloseState()?.unsaved) || workbenchDirtyLabel) {
      throw new Error('Save or undo unsaved edits before copying a plot.');
    }
    const contextId = $projectState?.contextId;
    if (!contextId) throw new Error('Open a project before copying a plot.');
    const targetPlot = rawTargetPlot.trim();
    if (!targetPlot || targetPlot.length > 7 || targetPlot.includes('\u0000')) {
      throw new Error('Plot Number must be 1 to 7 characters.');
    }
    if (targetPlot === sourcePlot) {
      throw new Error('Enter a Plot Number different from the current plot.');
    }
    if (allAvailablePlots.some((p) => p.plotNumber === targetPlot)) {
      throw new Error(`Plot ${targetPlot} already exists in this project.`);
    }
    const header = await ContextService.GetPlot(contextId, sourcePlot);
    if (!header) throw new Error(`Plot ${sourcePlot} could not be read.`);
    const [vegRows, humusRows, mineralRows, otherRows] = await Promise.all([
      ContextService.ListVegRecords(contextId, sourcePlot),
      ContextService.ListHumusRecords(contextId, sourcePlot),
      ContextService.ListMineralRecords(contextId, sourcePlot),
      ContextService.ListOtherRecords(contextId, sourcePlot),
    ]);
    await ContextService.CreatePlot(contextId, { ...header, plotNumber: targetPlot, locked: false });
    for (const row of vegRows ?? []) {
      await ContextService.SaveVegRecord(contextId, { ...row, id: 0, plotNumber: targetPlot });
    }
    for (const row of humusRows ?? []) {
      await ContextService.SaveHumusRecord(contextId, { ...row, id: 0, plotNumber: targetPlot });
    }
    for (const row of mineralRows ?? []) {
      await ContextService.SaveMineralRecord(contextId, { ...row, id: 0, plotNumber: targetPlot });
    }
    for (const row of otherRows ?? []) {
      await ContextService.SaveOtherRecord(contextId, { ...row, id: 0, plotNumber: targetPlot });
    }
    scopedCatalogKey = '';
    await loadPlots(offset);
    await refreshScopedPlotCatalog(contextId, page, true);
    const copiedSummary: PlotSummary = {
      plotNumber: targetPlot,
      fieldNumber: header.fieldNo ?? null,
      plotRepresenting: header.plotRepresenting ?? null,
      zone: header.zone ?? null,
      subZone: header.subZone ?? null,
      siteSeries: header.siteSeries ?? null,
    };
    selected = allAvailablePlots.find((p) => p.plotNumber === targetPlot) ?? copiedSummary;
    if (view === 'fs882') {
      editorPlotNumber = targetPlot;
    }
    if (typeof notifications !== 'undefined') {
      notifications.success?.(`Copied plot ${sourcePlot} to ${targetPlot}`, 'Site, vegetation, soil, and auxiliary rows were copied to the new Plot Number.', {
        category: 'entry',
        source: 'Plots',
        contextTag: `Plot ${targetPlot}`,
      });
    }
  }

  async function collectAllProjectPlotNumbers(contextId: string): Promise<string[]> {
    if (typeof DatasheetService?.GetDatasheetPage === 'function') {
      const plotNums: string[] = [];
      for (let nextOff = 0; ; nextOff += 1000) {
        const dsPage = await DatasheetService.GetDatasheetPage(contextId, {
          tableKey: 'Env',
          offset: nextOff,
          limit: 1000,
          sort: null,
          filters: null,
          globalSearch: '',
          scopeToActiveSU: false,
        });
        const summaries = extractDatasheetPlotSummaries(dsPage);
        if (summaries.length === 0) break;
        for (const s of summaries) plotNums.push(s.plotNumber);
        if (summaries.length < 1000 || plotNums.length >= (dsPage?.totalRows ?? 0)) break;
      }
      if (plotNums.length > 0) return plotNums;
    }
    return allAvailablePlots.map((p) => p.plotNumber);
  }

  async function removePlotFromProject(sourcePlot: string, rawCleanProjectName: string) {
    if (busy || editorBusy || companionPanelBusy || transitionWorking || pendingTransition !== null || !!closeRequest) {
      throw new Error('Wait for the current operation to finish first.');
    }
    if ((view === 'fs882' && editor?.getCloseState()?.unsaved) || workbenchDirtyLabel) {
      throw new Error('Save or undo unsaved edits before removing a plot.');
    }
    const contextId = $projectState?.contextId;
    if (!contextId) throw new Error('Open a project before removing a plot.');
    const undoable = createdSiviPlots.find((entry) => entry.plotNumber === sourcePlot && entry.canUndo);
    if (undoable) {
      await ContextService.UndoCreateSIVIPlot(contextId, {
        creationRequestId: undoable.requestId,
        plotNumber: sourcePlot,
      });
      scopedCatalogKey = '';
      if (selected?.plotNumber === sourcePlot) selected = null;
      if (editorPlotNumber === sourcePlot) {
        editorPlotNumber = undefined;
        if (view === 'fs882') view = 'plots';
      }
      await loadPlots(offset);
      await refreshScopedPlotCatalog(contextId, page, true);
      if (typeof notifications !== 'undefined') {
        notifications.success?.(`Deleted plot ${sourcePlot}`, 'Removed the newly created SIVI plot.', {
          category: 'entry',
          source: 'Plots',
        });
      }
      return;
    }
    const cleanProject = rawCleanProjectName.trim();
    if (!cleanProject || !/^[A-Za-z][A-Za-z0-9_]{0,29}$/.test(cleanProject)) {
      throw new Error('Clean project name must start with a letter and use only letters, numbers, or underscores (up to 30 characters).');
    }
    const allPlotNumbers = await collectAllProjectPlotNumbers(contextId);
    const remainingPlots = allPlotNumbers.filter((pn) => pn !== sourcePlot);
    if (remainingPlots.length === 0) {
      throw new Error('Cannot save a clean project copy when this is the only plot in the project. Create a blank project in Project Admin instead.');
    }
    const result = await ContextService.ExportSplinterProject(contextId, {
      splinterProject: cleanProject,
      useActiveSu: false,
      plotNumbers: remainingPlots,
      activateOnSuccess: true,
    });
    scopedCatalogKey = ''; scopedPlotCatalogRows = []; dynamicPalettePlotRows = []; createdSiviPlots = [];
    standaloneMetadataPlot = '';
    profileNavigation = null;
    selected = null;
    editorPlotNumber = undefined;
    diagnosticsDraft = null;
    if (result?.state) projectState.set(result.state);
    view = 'plots';
    await refresh();
    if (typeof notifications !== 'undefined') {
      notifications.success?.(`Switched to ${result.splinterProject}`, `Saved ${result.exportedPlotCount} plots without plot ${sourcePlot}. Original project file was preserved.`, {
        category: 'general',
        source: 'Plots',
      });
    }
  }

  const currentContextPlotNumber = $derived(
    (view === 'fs882' ? editorPlotNumber : selected?.plotNumber) ?? selected?.plotNumber ?? ''
  );
  const currentContextPlotIndex = $derived(
    currentContextPlotNumber
      ? allAvailablePlots.findIndex((p) => p.plotNumber === currentContextPlotNumber)
      : -1
  );
  const canStepPrevPlot = $derived(
    allAvailablePlots.length > 0 &&
      !busy &&
      !editorBusy &&
      !companionPanelBusy &&
      !transitionWorking &&
      currentContextPlotIndex > 0
  );
  const canStepNextPlot = $derived(
    allAvailablePlots.length > 0 &&
      !busy &&
      !editorBusy &&
      !companionPanelBusy &&
      !transitionWorking &&
      (currentContextPlotIndex === -1
        ? allAvailablePlots.length > 0
        : currentContextPlotIndex < allAvailablePlots.length - 1)
  );
  const sessionStatusKind = $derived<'busy' | 'dirty' | 'ready'>(
    busy || editorBusy || companionPanelBusy || transitionWorking
      ? 'busy'
      : (closeState?.unsaved ?? false) || Boolean(workbenchDirtyLabel) || Boolean(standaloneMetadataPlot && standaloneMetadataEditor?.hasUnsavedChanges?.())
        ? 'dirty'
        : 'ready'
  );
  const sessionStatusLabel = $derived(
    sessionStatusKind === 'busy'
      ? 'Busy'
      : sessionStatusKind === 'dirty'
        ? 'Unsaved Draft'
        : 'Ready'
  );
  const showInspectorToggle = $derived(view === 'home' || view === 'plots');
  const showInspectorRail = $derived(
    !startupFailure && showInspectorToggle && inspectorExpanded
  );
  const commandCatalogInput = $derived<BuildCommandPaletteInput>({
    plots: allAvailablePlots.map((p) => ({
      plotNumber: p.plotNumber,
      siteUnit: p.siteSeries,
      zone: p.zone,
      subZone: p.subZone,
      location: p.plotRepresenting,
    })),
    projects: ($projectState?.projects ?? []).map((p) => ({
      name: p.name,
      path: p.path,
      file: p.file,
      version: p.version,
      compatible: p.compatible,
      active: p.name === $projectState?.activeProject && p.path === $projectState?.projectPath,
    })),
    sus: ($projectState?.sus ?? []).map((s, index) => ({
      index,
      name: s.name,
      path: s.path,
      kind: s.kind,
      compatible: s.compatible,
      active: s.name === $projectState?.activeSU && s.path === $projectState?.suPath,
    })),
    selectedPlotNumber: currentContextPlotNumber || null,
    activeSU: $projectState?.activeSU ?? 'None',
    metadataAvailable: !!$projectState?.contextId && (view === 'fs882' ? (!!editor?.canOpenProjectMetadata() || ((typeof editorPlotNumber === 'undefined' || !editorPlotNumber) && typeof editorEntryForm !== 'undefined' && editorEntryForm === 'fs882-twopage')) : true),
    siviAvailable: siviStandaloneEnabled,
    newSiviAvailable: !!$projectState?.contextId && !busy && !editorBusy && !companionPanelBusy && !transitionWorking,
  });

  function stepContextPlot(delta: -1 | 1) {
    if (allAvailablePlots.length === 0) return;
    const targetIdx =
      currentContextPlotIndex === -1
        ? delta > 0
          ? 0
          : -1
        : currentContextPlotIndex + delta;
    const target = allAvailablePlots[targetIdx];
    if (!target) return;
    if (view === 'fs882') {
      void requestTransition(async () => {
        selected = target;
        editorPlotNumber = target.plotNumber;
        error = '';
      });
      return;
    }
    selected = target;
    if (!isNarrowViewport && view === 'plots') {
      inspectorExpanded = true;
    }
  }

  function handleCommandPaletteSelect(action: CommandPaletteAction) {
    if (action.kind === 'open-plot-fs882' || action.kind === 'open-plot-twopage') {
      void requestTransition(async () => {
        const found = allAvailablePlots.find((p) => p.plotNumber === action.plotNumber) ?? null;
        if (found) selected = found;
        editorPlotNumber = action.plotNumber;
        editorEntryForm = action.kind === 'open-plot-twopage' ? 'fs882-twopage' : 'fs882';
        view = 'fs882';
        error = '';
      });
      return;
    }
    if (action.kind === 'open-plot-sivi') {
      if (!siviStandaloneEnabled) {
        error = 'Standalone SIVI requires its independent entry gate, parent review and a selected owned plot.';
        return;
      }
      void requestTransition(async () => {
        const found = allAvailablePlots.find((p) => p.plotNumber === action.plotNumber) ?? null;
        if (found) selected = found;
        editorPlotNumber = action.plotNumber;
        editorEntryForm = 'sivi';
        view = 'fs882';
        error = '';
      });
      return;
    }
    if (action.kind === 'switch-project') {
      const targetProj = $projectState?.projects?.[action.projectIndex];
      if (targetProj) {
        void requestTransition(async (contextId) => {
          const current = $projectState;
          if (!current) return;
          await switchContext(contextId, {
            project: targetProj.name,
            projectPath: targetProj.path ?? '',
            su: 'None',
            suPath: '',
            hierarchy: current.activeHierarchy ?? 'None',
            hierarchyPath: current.hierarchyPath ?? '',
          }, 'plots');
        });
      }
      return;
    }
    if (action.kind === 'switch-su') {
      void requestTransition(async (contextId) => {
        const current = $projectState;
        if (!current) return;
        const chosen = action.suIndex >= 0 ? current.sus?.[action.suIndex] : undefined;
        await switchContext(contextId, {
          project: current.activeProject,
          projectPath: current.projectPath ?? '',
          su: chosen?.name ?? 'None',
          suPath: chosen?.path ?? '',
          hierarchy: current.activeHierarchy ?? 'None',
          hierarchyPath: current.hierarchyPath ?? '',
        }, 'plots');
      });
      return;
    }
    if (action.kind === 'navigate-view') {
      navigate(action.view as typeof view | 'fs882-twopage');
      return;
    }
    if (action.kind === 'new-sivi') {
      if ($projectState?.contextId && !busy && !editorBusy && !companionPanelBusy && !transitionWorking) {
        newSiviModalOpen = true;
      }
      return;
    }
    if (action.kind === 'open-metadata') {
      void openProjectMetadata();
      return;
    }
    if (action.kind === 'help-topic') {
      openContextualHelp(action.topicId, action.tab ?? 'inspector');
      return;
    }
    if (action.kind === 'help-action') {
      handleHelpMenuAction(action.action);
    }
  }

  onMount(() => {
    const syncViewport = () => {
      if (typeof window === 'undefined') return;
      const narrow = window.innerWidth < 1200;
      const wasNarrow = isNarrowViewport;
      isNarrowViewport = narrow;
      if (narrow && !wasNarrow) {
        contextExpanded = false;
        inspectorExpanded = false;
      } else if (!narrow && wasNarrow) {
        try {
          const saved = typeof sessionStorage !== 'undefined' ? sessionStorage.getItem(CONTEXT_EXPANDED_STORAGE_KEY) : null;
          contextExpanded = saved === 'false' ? false : true;
        } catch {
          contextExpanded = true;
        }
      }
    };
    if (typeof window !== 'undefined') {
      const initialNarrow = window.innerWidth < 1200;
      isNarrowViewport = initialNarrow;
      if (initialNarrow) {
        contextExpanded = false;
        inspectorExpanded = false;
      } else {
        try {
          const saved = typeof sessionStorage !== 'undefined' ? sessionStorage.getItem(CONTEXT_EXPANDED_STORAGE_KEY) : null;
          contextExpanded = saved === null ? true : saved === 'true';
        } catch {
          contextExpanded = true;
        }
        inspectorExpanded = true;
      }
      window.addEventListener('resize', syncViewport);
    }
    const stopCloseEvents = Events.On(VproCloseRequest, (event) => {
      const requestId: unknown = event.data;
      if (typeof requestId !== 'string' || !requestId) { error = 'Could not complete window close request; VPRO remains open.'; return; }
      void handleCloseRequest(requestId);
    });
    void LifecycleService.GetPendingCloseRequest().then((requestId) => { if (requestId) void handleCloseRequest(requestId); })
      .catch((cause) => { error = `Window close handler could not initialise: ${String(cause)}`; });
    void defaultHelpPort.getWhatsNewStatus().then((st) => { whatsNewStatus = st; }).catch(() => {});
    void refresh();
    return () => {
      request++;
      stopCloseEvents();
      if (typeof window !== 'undefined') {
        window.removeEventListener('resize', syncViewport);
      }
    };
  });
</script>

<svelte:window onkeydown={handleGlobalHelpKeydown} />

<div class="app-shell">
  <header class="topbar">
    <div class="brand">
      <span class="brand-symbol" aria-hidden="true">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="36 36 952 952" width="28" height="28" focusable="false">
          <defs>
            <linearGradient id="vpro-topbar-navy" x1="16%" y1="6%" x2="84%" y2="96%">
              <stop offset="0%" stop-color="#0B437A"/>
              <stop offset="52%" stop-color="#003366"/>
              <stop offset="100%" stop-color="#001D3A"/>
            </linearGradient>
            <linearGradient id="vpro-topbar-shield" x1="50%" y1="0%" x2="50%" y2="100%">
              <stop offset="0%" stop-color="#2E8540"/>
              <stop offset="56%" stop-color="#1E5128"/>
              <stop offset="100%" stop-color="#13381B"/>
            </linearGradient>
          </defs>
          <rect x="64" y="64" width="896" height="896" rx="196" ry="196" fill="url(#vpro-topbar-navy)" stroke="#38598A" stroke-width="16"/>
          <path d="M512 162L216 286V512C216 681 342 827 512 864C682 827 808 681 808 512V286Z" fill="url(#vpro-topbar-shield)" stroke="#FCBA19" stroke-width="28" stroke-linejoin="round"/>
          <path d="M488 614H536L542 754Q512 764 482 754Z" fill="#FCBA19"/>
          <path d="M512 454L698 654Q512 618 326 654Z" fill="#FFFFFF"/>
          <path d="M512 344L656 518Q512 488 368 518Z" fill="#FFFFFF"/>
          <path d="M512 244L614 396Q512 372 410 396Z" fill="#FFFFFF"/>
        </svg>
      </span>
      <span>VPro</span>
      <WorkspaceStatusBanners region="badge" {buildMode} {appVersion} {shortBuildCommit} {releaseChannel}
        startupFailed={startupFailure !== null} onopenabout={() => { aboutModalOpen = true; }} />
    </div>
    <button class="context-toggle" type="button" disabled={startupFailure !== null} aria-expanded={contextExpanded} aria-controls="project-context" onclick={toggleContextSidebar}>Projects &amp; context</button>
    {#if !startupFailure}<Navigation {view} activeEntryForm={editorEntryForm} onnavigate={navigate}
      siviAvailable={siviStandaloneEnabled && !!selected && !!$projectState?.contextId} onopensivi={() => void openSIVI()}
      newSiviAvailable={!!$projectState?.contextId && !busy && !editorBusy && !companionPanelBusy && !transitionWorking} onopennewsivi={() => { newSiviModalOpen = true; }}
      metadataAvailable={!!$projectState?.contextId && (view === 'fs882' ? (!!editor?.canOpenProjectMetadata() || ((typeof editorPlotNumber === 'undefined' || !editorPlotNumber) && typeof editorEntryForm !== 'undefined' && editorEntryForm === 'fs882-twopage')) : true)} onopenmetadata={() => void openProjectMetadata()}
      onopencloudsync={() => { void requestTransition(async () => { standaloneMetadataPlot = ''; projectAdminTab = 'cloudsync'; projectAdminTabNonce++; view = 'project-admin'; error = ''; }); }}
      onopenusersetup={() => { userSetupOpen = true; }}
      whatsNewUnreadCount={whatsNewStatus?.unreadCount ?? 0} resetSampleAvailable={!!$projectState?.contextId && !busy && !editorBusy && !companionPanelBusy && !transitionWorking}
      {releaseChannel} onhelpaction={handleHelpMenuAction} />{/if}
    <div class="topbar-actions">
      <button
        type="button"
        class="cmd-trigger"
        disabled={startupFailure !== null}
        aria-label="Open Quick-Jump Command Palette (Ctrl+K)"
        title="Quick-Jump Command Palette (Ctrl+K)"
        data-command-palette-trigger
        onclick={() => { commandPaletteOpen = true; }}
      >
        <Search size={14} aria-hidden="true" />
        <span class="cmd-trigger-label">Quick Jump</span>
        <kbd>Ctrl+K</kbd>
      </button>

      <button
        type="button"
        class="notif-bell"
        disabled={startupFailure !== null}
        aria-label={`Notification Center${notifSnapshot.unreadCount > 0 ? ` (${notifSnapshot.unreadCount} unread)` : ''}`}
        title="Open Notification Center"
        data-notification-bell
        onclick={() => { notificationDrawerOpen = !notificationDrawerOpen; }}
      >
        <Bell size={16} aria-hidden="true" />
        {#if notifSnapshot.unreadCount > 0}
          <span
            class="notif-badge tabular-nums notif-badge-{notifSnapshot.badgeSeverity === 'none' ? 'info' : notifSnapshot.badgeSeverity}"
            data-notification-badge={notifSnapshot.badgeSeverity}
          >
            {notifSnapshot.unreadCount > 99 ? '99+' : notifSnapshot.unreadCount}
          </span>
        {/if}
      </button>

      <div class="topbar-context">
        <Database size={15} strokeWidth={1.8} aria-hidden="true" />
        <span>{$projectState?.activeProject ?? 'No project'}</span>
      </div>
    </div>
  </header>

  {#if !startupFailure}
    <div class="context-strip" role="region" aria-label="Active workspace context and quick actions" data-context-strip>
      <div class="context-strip-chips">
        <span class="ctx-chip" data-context-chip="project">
          <span class="ctx-chip-label">Project</span>
          <span class="ctx-chip-value">{$projectState?.activeProject ?? 'None'}</span>
        </span>
        <span class="ctx-chip" data-context-chip="su">
          <span class="ctx-chip-label">SU</span>
          <span class="ctx-chip-value">{$projectState?.activeSU ?? 'None'}</span>
        </span>
        <span class="ctx-chip" data-context-chip="hierarchy">
          <span class="ctx-chip-label">Hierarchy</span>
          <span class="ctx-chip-value">{$projectState?.activeHierarchy ?? 'None'}</span>
        </span>

        <div class="ctx-plot-stepper" role="group" aria-label="Plot navigation">
          <span class="ctx-chip-label">Plot</span>
          <span class="ctx-plot-badge tabular-nums" data-context-plot-badge>
            {currentContextPlotNumber || 'None'}
          </span>
          <button
            type="button"
            class="ctx-step-btn"
            title="Previous plot in loaded page"
            aria-label="Previous plot"
            disabled={!canStepPrevPlot}
            onclick={() => stepContextPlot(-1)}
          >
            <ChevronLeft size={14} aria-hidden="true" />
          </button>
          <button
            type="button"
            class="ctx-step-btn"
            title="Next plot in loaded page"
            aria-label="Next plot"
            disabled={!canStepNextPlot}
            onclick={() => stepContextPlot(1)}
          >
            <ChevronRight size={14} aria-hidden="true" />
          </button>
        </div>
      </div>

      <div class="context-strip-actions">
        <span
          class="ctx-status-pill ctx-status-{sessionStatusKind}"
          role="status"
          data-session-status={sessionStatusKind}
        >
          {sessionStatusLabel}
        </span>

        {#if showInspectorToggle}
          <button
            type="button"
            class="ctx-inspector-toggle"
            aria-expanded={inspectorExpanded}
            data-inspector-toggle
            onclick={() => { inspectorExpanded = !inspectorExpanded; }}
          >
            <PanelRight size={14} aria-hidden="true" />
            <span>Inspector</span>
          </button>
        {/if}
      </div>
    </div>
  {/if}

  <div
    class="workspace"
    class:context-collapsed={!contextExpanded || startupFailure !== null}
    class:inspector-collapsed={!showInspectorRail}
  >
    {#if !startupFailure && isNarrowViewport && (contextExpanded || showInspectorRail)}
      <button
        type="button"
        class="drawer-backdrop"
        aria-label="Close side drawer"
        data-drawer-backdrop
        onclick={() => {
          contextExpanded = false;
          inspectorExpanded = false;
        }}
      ></button>
    {/if}
    <WorkspaceSidebar {busy} {editorBusy} {companionPanelBusy} {transitionWorking} {requestTransition} {switchContext} onAccessActivated={handleAccessActivated} />

    <main class="content">
      <WorkspaceStatusBanners region="banners" startupFailed={startupFailure !== null} {whatsNewStatus} {whatsNewPromptDismissed}
        onopenwhatsnew={() => { whatsNewModalOpen = true; }} onacknowledgewhatsnew={() => void acknowledgeUnreadWhatsNew()}
        ondismisswhatsnew={() => { whatsNewPromptDismissed = true; }} />
      <PlotProfilePanel bind:this={plotProfilePanel} bind:view bind:busy bind:error bind:editorPlotNumber bind:profileNavigation bind:selected bind:page
        {editorBusy} {vegetationPublicationBusy} {lifeformPublicationBusy} {summaryPublicationBusy} {transitionWorking} {pendingTransition} {closeRequest}
        {profileIndex} {stateReads} {requestTransition} {loadPlots} {navigateProfilePlot} {clearProfileNavigation} {cancelAllReads} />
      <WorkspaceStatusBanners region="banners" startupFailed={true} diagnostics={$projectState?.diagnostics ?? []} />
      {#if startupFailure}
        {#await import('./shell/StartupRecoveryPanel.svelte') then { default: StartupRecoveryPanel }}
          <StartupRecoveryPanel {startupFailure} {busy} onrecovered={async (notice) => { startupBackupNotice = notice; if (notice && typeof notifications !== 'undefined') notifications.success('Startup recovery complete', notice, { source: 'Startup Recovery' }); startupFailure = null; await refresh(); }} />
        {/await}
      {:else if standaloneMetadataPlot && $projectState?.contextId}
        <div class="p-3 space-y-3" data-standalone-metadata-host>
          <div class="flex flex-wrap items-center justify-between gap-2 rounded border border-stone-200 bg-stone-50 px-3 py-2 text-xs">
            <div class="flex flex-wrap items-center gap-2">
              <span class="font-semibold text-[#003366]">Project Metadata ({$projectState.activeProject})</span>
              {#if allAvailablePlots.length > 1}
                <label class="inline-flex items-center gap-1.5 text-stone-700" for="standalone-metadata-plot-select">
                  <span>Plot scope:</span>
                  <select
                    id="standalone-metadata-plot-select"
                    class="rounded border border-stone-300 bg-white px-2 py-1 font-mono text-xs"
                    value={standaloneMetadataPlot}
                    disabled={localEditorBusy || Boolean(standaloneMetadataEditor?.hasUnsavedChanges?.())}
                    onchange={(e) => { standaloneMetadataPlot = e.currentTarget.value; }}
                  >
                    {#each allAvailablePlots as p (p.plotNumber)}
                      <option value={p.plotNumber}>{p.plotNumber}</option>
                    {/each}
                  </select>
                </label>
              {/if}
            </div>
            <button
              type="button"
              class="rounded border border-[#003366] bg-white px-2.5 py-1 font-semibold text-[#003366] hover:bg-[#EBF1F8] disabled:opacity-50"
              disabled={localEditorBusy || Boolean(standaloneMetadataEditor?.hasUnsavedChanges?.())}
              onclick={() => { standaloneMetadataPlot = ''; localEditorBusy = false; navigate('project-admin'); }}
            >
              Open Metadata Presets &amp; Project Admin
            </button>
          </div>
          {#key `${$projectState.contextId}:${standaloneMetadataPlot}`}
            {#await import('./admin/ProjectMetadataEditor.svelte')}
              <p role="status" class="p-4 text-sm">Loading Project Metadata Editor...</p>
            {:then { default: ProjectMetadataEditor }}
              <ProjectMetadataEditor
                bind:this={standaloneMetadataEditor}
                client={bindContextPlots($projectState.contextId)}
                contextId={$projectState.contextId}
                plot={standaloneMetadataPlot}
                allowCreation={true}
                allowTemplateCreation={true}
                allowRestoration={true}
                onbusy={(b) => { localEditorBusy = b; }}
                oncommitted={async () => {
                  const nextState = await stateReads.track(ContextService.GetState());
                  projectState.set(nextState);
                }}
                onclosed={() => { standaloneMetadataPlot = ''; localEditorBusy = false; }}
              />
            {:catch loadError}
              <p class="error" role="alert">Project Metadata Editor could not load: {String(loadError)}</p>
            {/await}
          {/key}
        </div>
      {:else if view === 'home'}
        <div class="content-heading"><div><div class="eyebrow">VPro</div><h1>Home</h1></div></div>
        <HomeWorkspaceHub activeProject={$projectState?.activeProject ?? 'No project selected'} projectPath={$projectState?.projectPath ?? ''}
          activeSU={$projectState?.activeSU ?? 'None'} activeHierarchy={$projectState?.activeHierarchy ?? 'None'} plotCount={page?.total ?? 0}
          {buildMode} {appVersion} gitCommit={startupInfo?.gitCommit ?? ''} {releaseChannel}
          onnavigate={(nextView) => navigate(nextView)} onhelpaction={(action) => handleHelpMenuAction(action)} />
      {:else if view === 'fs882'}
        <div class="h-full flex flex-col p-2">
          {#if plotFindEnabled && plotFindOpen}
            <section aria-label="Find scoped plot" class="mb-2 p-3 border rounded">
              <form onsubmit={(event) => { event.preventDefault(); void findScopedPlot(); }} class="flex flex-wrap items-end gap-2">
                <label for="find-scoped-plot" class="flex flex-col gap-1 flex-1 min-w-0">Exact plot number
                  <input id="find-scoped-plot" class="px-2 py-1 border rounded min-w-0" bind:value={plotFindQuery}
                    oninput={() => { plotFindResult = null; plotFindError = ''; }} disabled={busy || editorBusy || transitionWorking || pendingTransition !== null} />
                </label>
                <button type="submit" class="px-3 py-1 border rounded disabled:opacity-50" disabled={busy || editorBusy || transitionWorking || pendingTransition !== null}>Find in current scope</button>
                <button type="button" class="px-3 py-1 border rounded disabled:opacity-50" disabled={busy || transitionWorking || pendingTransition !== null}
                  onclick={() => { plotFindOpen = false; plotFindResult = null; plotFindError = ''; }}>Dismiss find</button>
              </form>
              {#if plotFindError}<p role="alert" class="mt-2 text-[#D8292F]">{plotFindError}</p>{/if}
              {#if plotFindResult}
                <p role="status" class="mt-2">Found plot {JSON.stringify(plotFindResult.plot.plotNumber)} in the current recordset.</p>
                <button type="button" class="mt-2 px-3 py-1 border rounded disabled:opacity-50"
                  disabled={busy || editorBusy || transitionWorking || pendingTransition !== null || plotFindResult.contextId !== $projectState?.contextId || plotFindResult.plot.plotNumber === editorPlotNumber}
                  onclick={() => void openFoundPlot()}>Open found plot</button>
              {/if}
              <p class="mt-2 text-sm">Find is read-only. Exact spaces and case are preserved, including historical long identifiers. Current SU and reviewed profile filters stay in effect. Open rechecks the target after Save/Discard/Cancel; no record is created.</p>
            </section>
          {/if}
          <fieldset disabled={busy} class="contents">
          {#key $projectState?.contextId}
          {#key editorEntryForm}
          {#key editorPlotNumber}
          {#await loadFS882Editor()}
            <p role="status" data-entry-loading="fs882">Loading {editorLabel} editor...</p>
          {:then { default: FS882Form }}
          <FS882Form bind:this={editor} plotNumber={editorPlotNumber} contextId={$projectState?.contextId ?? ''} entryForm={editorEntryForm}
            availablePlots={allAvailablePlots}
            onSelectPlotForTwoPage={(p) => { void requestTransition(async () => { const found = allAvailablePlots.find((item) => item.plotNumber === p) ?? null; if (found) selected = found; editorPlotNumber = p; editorEntryForm = 'fs882-twopage'; view = 'fs882'; error = ''; }); }}
            onSwitchTo6x4NewPlot={() => { void requestTransition(async () => { editorPlotNumber = undefined; editorEntryForm = 'fs882'; view = 'fs882'; error = ''; }); }}
            canUndoPlotDelete={canUndoEditorPlot}
            onCopyPlotToNumber={copyPlotToNewNumber}
            onRemovePlotAction={removePlotFromProject}
            onSaved={async (p) => { editorPlotNumber = p; scopedCatalogKey = ''; await loadPlots(offset); if ($projectState?.contextId) await refreshScopedPlotCatalog($projectState.contextId, page, true); }} onClosed={() => navigate('plots')}
            onBusyChange={(busy) => { localEditorBusy = busy; }} onProfileNavigation={applyProfileNavigation}
            onProfileSUReview={reviewProfileSU} onFindPlot={plotFindEnabled ? () => { plotFindOpen = true; } : undefined}
            onOpenPictureManager={(p) => {
              void requestTransition(async () => {
                pictureManagerPlot = p || editorPlotNumber || '';
                view = 'picture-manager';
                error = '';
              });
            }}
            onDiagnosticsContextChange={(ctx) => { diagnosticsDraft = ctx; }} />
          {:catch error}
            <p class="error" role="alert" data-entry-load-error="fs882">{editorLabel} editor could not load: {String(error)}</p>
          {/await}
          {/key}
          {/key}
          {/key}
          </fieldset>
        </div>
        <CloseConfirm requestId={closeRequest || (pendingTransition ? 'context' : '')} purpose={closeRequest ? 'close' : 'context'} {editorLabel}
          working={closeWorking || transitionWorking} canSave={closeState?.canSave ?? false}
          saveReason={closeState?.saveReason ?? `Return to the ${editorLabel} editor before saving.`}
          error={closeRequest ? closeError : transitionError} onrespond={closeRequest ? respondToClose : respondToTransition} />
        {#if editorPlotNumber && $projectState?.contextId}
          {#await import('./diagnostics/LMH25DiagnosticsBar.svelte') then { default: LMH25DiagnosticsBar }}
            <div class="px-2 pb-2">
              <LMH25DiagnosticsBar
                contextId={$projectState.contextId}
                plotNumber={editorPlotNumber}
                header={diagnosticsDraft?.header ?? null}
                humus={diagnosticsDraft?.humus ?? []}
                mineral={diagnosticsDraft?.mineral ?? []}
                onApplyHumusThickness={(v) => editor?.applyDiagnosticHumusThickness?.(v)}
                onApplyKeyedSMR={(v) => editor?.applyDiagnosticSMR?.(v)}
                onApplyKeyedSNR={(v) => editor?.applyDiagnosticSNR?.(v)}
              />
            </div>
          {/await}
        {/if}
      {:else if view === 'datasheet' && $projectState}
        {#key $projectState.contextId}
          {#await import('./datasheet/UniversalDatasheetGrid.svelte')}
            <p role="status" class="p-4 text-sm">Loading Universal Datasheet Grid...</p>
          {:then { default: UniversalDatasheetGrid }}
            <UniversalDatasheetGrid contextId={$projectState.contextId ?? ''} project={$projectState.activeProject} su={$projectState.activeSU} hierarchy={$projectState.activeHierarchy}
              onBusyChange={(value) => { localEditorBusy = value; }} onDirtyChange={(dirty) => { workbenchDirtyLabel = dirty ? 'datasheet' : ''; }}
              onOpenPlot={(p) => { void requestTransition(async () => { editorPlotNumber = p; editorEntryForm = 'fs882'; view = 'fs882'; error = ''; }); }} />
          {/await}
        {/key}
      {:else if view === 'classification-explorer' && $projectState}
        {#await import('./classification/ClassificationExplorer.svelte')}
          <p role="status" class="p-4 text-sm">Loading Classification Explorer...</p>
        {:then { default: ClassificationExplorer }}
          <ClassificationExplorer contextId={$projectState.contextId ?? ''} project={$projectState.activeProject} su={$projectState.activeSU} hierarchy={$projectState.activeHierarchy}
            operationHeld={busy || transitionWorking || pendingTransition !== null || !!closeRequest}
            onBusyChange={(value) => { localEditorBusy = value; }} onDirtyChange={(dirty) => { workbenchDirtyLabel = dirty ? 'classification-explorer' : ''; }}
            onContextChanged={async () => { await refresh(); }}
            onOpenPlot={(p) => { void requestTransition(async () => { editorPlotNumber = p; editorEntryForm = 'fs882'; view = 'fs882'; error = ''; }); }} />
        {/await}
      {:else if view === 'project-admin' && $projectState}
        <div class="p-3 space-y-4">
          {#await import('./admin/ProjectAdminWorkbench.svelte')}
            <p role="status" class="p-4 text-sm">Loading Project Admin Workbench...</p>
          {:then { default: ProjectAdminWorkbench }}
            <ProjectAdminWorkbench contextId={$projectState.contextId ?? ''} activeProject={$projectState.activeProject} activeSu={$projectState.activeSU}
              initialTab={projectAdminTab} initialTabNonce={projectAdminTabNonce}
              operationHeld={busy || companionPanelBusy || transitionWorking || pendingTransition !== null || !!closeRequest}
              onBusyChange={(value) => { localEditorBusy = value; }}
              onprojectlistchanged={async () => {
                const nextState = await stateReads.track(ContextService.GetState());
                projectState.set(nextState);
              }}
              oncontextswitched={async () => { await refresh(); }} />
          {/await}
          {#await import('./admin/ProjectMetadataPresets.svelte') then { default: ProjectMetadataPresets }}
            <ProjectMetadataPresets contextId={$projectState.contextId ?? ''} projectId=""
              operationHeld={busy || localEditorBusy || transitionWorking || pendingTransition !== null || !!closeRequest}
              onBusyChange={(value) => { secondaryPanelBusy = value; }} />
          {/await}
        </div>
      {:else if view === 'lump-editor' && $projectState}
        {#key $projectState.contextId}
          {#await import('./classification/LumpEditor.svelte')}
            <p role="status" class="p-4 text-sm">Loading Combine Species...</p>
          {:then { default: LumpEditor }}
            <LumpEditor contextId={$projectState.contextId ?? ''} operationHeld={busy || transitionWorking || pendingTransition !== null || !!closeRequest}
              onBusyChange={(value) => { localEditorBusy = value; }} />
          {/await}
        {/key}
      {:else if view === 'diagnostic-synthesis' && $projectState}
        {#key $projectState.contextId}
          {#await import('./diagnostics/ClassificationSynthesisView.svelte')}
            <p role="status" class="p-4 text-sm">Loading BEC Diagnostic &amp; Pairwise Synthesis...</p>
          {:then { default: ClassificationSynthesisView }}
            <ClassificationSynthesisView contextId={$projectState.contextId ?? ''} project={$projectState.activeProject} su={$projectState.activeSU}
              onBusyChange={(value) => { localEditorBusy = value; }}
              onOpenPlot={(p) => { void requestTransition(async () => { editorPlotNumber = p; editorEntryForm = 'fs882'; view = 'fs882'; error = ''; }); }} />
          {/await}
        {/key}
      {:else if view === 'r-sidecar' && $projectState}
        {#key $projectState.contextId}
          {#await import('./rsidecar/RSidecarWorkbench.svelte')}
            <p role="status" class="p-4 text-sm">Loading R Companion &amp; Guides...</p>
          {:then { default: RSidecarWorkbench }}
            <RSidecarWorkbench contextId={$projectState.contextId ?? ''} activeProject={$projectState.activeProject} activeSu={$projectState.activeSU}
              operationHeld={busy || transitionWorking || pendingTransition !== null || !!closeRequest}
              onBusyChange={(value) => { localEditorBusy = value; }} oncontextswitched={async () => { await refresh(); }} />
          {/await}
        {/key}
      {:else if view === 'geospatial-map' && $projectState}
        {#key $projectState.contextId}
          {#await import('./spatial/GeospatialWorkbench.svelte')}
            <p role="status" class="p-4 text-sm">Loading 3D Map...</p>
          {:then { default: GeospatialWorkbench }}
            <GeospatialWorkbench contextId={$projectState.contextId ?? ''} project={$projectState.activeProject} su={$projectState.activeSU}
              onBusyChange={(value) => { localEditorBusy = value; }} onContextChanged={async () => { await refresh(); }}
              onOpenPlot={(p) => { void requestTransition(async () => { editorPlotNumber = p; editorEntryForm = 'fs882'; view = 'fs882'; error = ''; }); }} />
          {/await}
        {/key}
      {:else if view === 'interchange-hub' && $projectState}
        {#key $projectState.contextId}
          {#await import('./interchange/InterchangeHub.svelte')}
            <p role="status" class="p-4 text-sm">Loading Interchange Hub...</p>
          {:then { default: InterchangeHub }}
            <InterchangeHub contextId={$projectState.contextId ?? ''} operationHeld={busy || transitionWorking || pendingTransition !== null || !!closeRequest}
              onBusyChange={(value) => { localEditorBusy = value; }} onProjectActivated={async () => { await refresh(); }} />
          {/await}
        {/key}
      {:else if view === 'summary-environment' && $projectState}
        {#await import('./reports/SiteUnitSummary.svelte')}
          <p role="status" class="p-4 text-sm">Loading Site Unit Summary...</p>
        {:then { default: SiteUnitSummary }}
          {#key $projectState.contextId}<SiteUnitSummary contextId={$projectState.contextId ?? ''} project={$projectState.activeProject}
            projectPath={$projectState.projectPath ?? ''} su={$projectState.activeSU} suPath={$projectState.suPath ?? ''}
            onBusyChange={(value) => { localEditorBusy = value; }} />{/key}
        {:catch loadError}<p class="error" role="alert">Site Unit Summary could not load: {String(loadError)}</p>{/await}
      {:else if view === 'long-environment' && $projectState}
        {#await import('./reports/LongEnvironmentReport.svelte')}
          <p role="status" class="p-4 text-sm">Loading Long Environment Report...</p>
        {:then { default: LongEnvironmentReport }}
          {#key $projectState.contextId}<LongEnvironmentReport contextId={$projectState.contextId ?? ''} project={$projectState.activeProject}
            projectPath={$projectState.projectPath ?? ''} su={$projectState.activeSU} suPath={$projectState.suPath ?? ''}
            onBusyChange={(value) => { localEditorBusy = value; }} />{/key}
        {:catch loadError}<p class="error" role="alert">Long Environment Report could not load: {String(loadError)}</p>{/await}
      {:else if view === 'long-vegetation' && $projectState}
        {#await (import('./reports/LongVegetationReport.svelte') as unknown as Promise<{ default: Component<LongVegetationWave3Props> }>)}
          <p role="status" class="p-4 text-sm">Loading Long Vegetation Report...</p>
        {:then { default: LongVegetationReport }}
          {#key $projectState.contextId}<LongVegetationReport contextId={$projectState.contextId ?? ''} project={$projectState.activeProject}
            projectPath={$projectState.projectPath ?? ''} su={$projectState.activeSU} suPath={$projectState.suPath ?? ''}
            hierarchy={$projectState.activeHierarchy ?? 'None'}
            operationHeld={busy || transitionWorking || pendingTransition !== null || !!closeRequest}
            onBusyChange={(value) => { localEditorBusy = value; }} />{/key}
        {:catch loadError}<p class="error" role="alert">Long Vegetation Report could not load: {String(loadError)}</p>{/await}
      {:else if view === 'summary-vegetation' && $projectState}
        {#await (import('./reports/SummaryVegetationReport.svelte') as unknown as Promise<{ default: Component<SummaryVegetationWave3Props> }>)}
          <p role="status" class="p-4 text-sm">Loading Summary Vegetation Report...</p>
        {:then { default: SummaryVegetationReport }}
          {#key $projectState.contextId}
            <SummaryVegetationReport contextId={$projectState.contextId ?? ''} project={$projectState.activeProject}
              projectPath={$projectState.projectPath ?? ''} su={$projectState.activeSU} suPath={$projectState.suPath ?? ''}
              hierarchy={$projectState.activeHierarchy ?? 'None'}
              operationHeld={busy || transitionWorking || pendingTransition !== null || !!closeRequest}
              onBusyChange={(value) => { localEditorBusy = value; }}
              onExclusionBusyChange={(value) => { secondaryPanelBusy = value; }} />
          {/key}
        {:catch loadError}<p class="error" role="alert">Summary Vegetation Report could not load: {String(loadError)}</p>{/await}
      {:else if view === 'lifeform-summary' && $projectState}
        {#await import('./reports/LifeformSummary.svelte')}
          <p role="status" class="p-4 text-sm">Loading Lifeform Summary...</p>
        {:then { default: LifeformSummary }}
          {#key $projectState.contextId}<LifeformSummary contextId={$projectState.contextId ?? ''} project={$projectState.activeProject}
            projectPath={$projectState.projectPath ?? ''} su={$projectState.activeSU} suPath={$projectState.suPath ?? ''}
            onBusyChange={(value) => { localEditorBusy = value; }} />{/key}
        {:catch loadError}<p class="error" role="alert">Lifeform Summary could not load: {String(loadError)}</p>{/await}
      {:else if view === 'table-csv' && $projectState}
        {#await import('./interchange/ProjectTableCSVReview.svelte')}
          <p role="status" class="p-4 text-sm">Loading Table CSV Review...</p>
        {:then { default: ProjectTableCSVReview }}
          {#key $projectState.contextId}<ProjectTableCSVReview contextId={$projectState.contextId ?? ''} project={$projectState.activeProject}
            projectPath={$projectState.projectPath ?? ''} onBusyChange={(value) => { localEditorBusy = value; }} />{/key}
        {:catch loadError}<p class="error" role="alert">Table CSV Review could not load: {String(loadError)}</p>{/await}
      {:else if view === 'user-log' && $projectState}
        {#await import('./admin/UserLogReview.svelte')}
          <p role="status" class="p-4 text-sm">Loading User Log Review...</p>
        {:then { default: UserLogReview }}
          {#key $projectState.contextId}<UserLogReview contextId={$projectState.contextId ?? ''}
            operationHeld={busy || transitionWorking || pendingTransition !== null || !!closeRequest}
            onBusyChange={(value) => { localEditorBusy = value; }} />{/key}
        {:catch loadError}<p class="error" role="alert">User Log Review could not load: {String(loadError)}</p>{/await}
      {:else if view === 'plot-label-preview' && $projectState}
        {#await import('./interchange/PlotLabelPreview.svelte')}
          <p role="status" class="p-4 text-sm">Loading Plot Label Preview...</p>
        {:then { default: PlotLabelPreview }}
          {#key $projectState.contextId}<PlotLabelPreview contextId={$projectState.contextId ?? ''} project={$projectState.activeProject}
            projectPath={$projectState.projectPath ?? ''} su={$projectState.activeSU} suPath={$projectState.suPath ?? ''}
            initialPlot={plotLabelNumber} onBusyChange={(value) => { localEditorBusy = value; }} />{/key}
        {:catch loadError}<p class="error" role="alert">Plot Label Preview could not load: {String(loadError)}</p>{/await}
      {:else if view === 'picture-manager' && $projectState}
        {#await import('./pictures/PictureManager.svelte')}
          <p role="status" class="p-4 text-sm">Loading Picture Manager...</p>
        {:then { default: PictureManager }}
          {#key $projectState.contextId}<PictureManager contextId={$projectState.contextId ?? ''} project={$projectState.activeProject}
            initialPlot={pictureManagerPlot} onBusyChange={(value) => { localEditorBusy = value; }} />{/key}
        {:catch loadError}<p class="error" role="alert">Picture Manager could not load: {String(loadError)}</p>{/await}
      {:else if view === 'plot-locations' && $projectState}
        {#await import('./spatial/PlotLocationReview.svelte')}
          <p role="status" class="p-4 text-sm">Loading Plot Location Review...</p>
        {:then { default: PlotLocationReview }}
          {#key $projectState.contextId}<PlotLocationReview contextId={$projectState.contextId ?? ''} project={$projectState.activeProject}
            projectPath={$projectState.projectPath ?? ''} su={$projectState.activeSU} suPath={$projectState.suPath ?? ''}
            onBusyChange={(value) => { localEditorBusy = value; }} />{/key}
        {:catch loadError}<p class="error" role="alert">Plot Location Review could not load: {String(loadError)}</p>{/await}
      {:else if view === 'google-earth-review' && $projectState}
        {#await import('./spatial/GoogleEarthReview.svelte')}
          <p role="status" class="p-4 text-sm">Loading Google Earth Review...</p>
        {:then { default: GoogleEarthReview }}
          {#key $projectState.contextId}<GoogleEarthReview contextId={$projectState.contextId ?? ''} project={$projectState.activeProject}
            projectPath={$projectState.projectPath ?? ''} su={$projectState.activeSU} suPath={$projectState.suPath ?? ''}
            onBusyChange={(value) => { localEditorBusy = value; }} />{/key}
        {:catch loadError}<p class="error" role="alert">Google Earth Review could not load: {String(loadError)}</p>{/await}
      {:else if view === 'subzone-matrix' && $projectState}
        {#await import('./reports/SubzoneMatrixReport.svelte')}
          <p role="status" class="p-4 text-sm">Loading Subzone Matrix Report...</p>
        {:then { default: SubzoneMatrixReport }}
          {#key $projectState.contextId}<SubzoneMatrixReport contextId={$projectState.contextId ?? ''} hierarchy={$projectState.activeHierarchy}
            hierarchyPath={$projectState.hierarchyPath ?? ''} onBusyChange={(value) => { localEditorBusy = value; }} />{/key}
        {:catch loadError}<p class="error" role="alert">Subzone Matrix Report could not load: {String(loadError)}</p>{/await}
      {:else}
        <PlotsBrowserPanel region="main" {view} {busy} {error} {page} allPlots={allAvailablePlots} {offset} {pageSize} {hierarchyNodes} bind:selected {siviStandaloneEnabled}
          onrefresh={refresh} onloadpage={loadPlots} onopenexplorer={() => navigate('classification-explorer')}
          onselectplot={() => { inspectorExpanded = true; }} />
      {/if}
    </main>

    {#if showInspectorRail}
      <PlotsBrowserPanel region="detail" {view} {busy} {page} allPlots={allAvailablePlots} bind:selected {siviStandaloneEnabled} {canUndoSelectedPlot} {editorBusy} {transitionWorking} {pendingTransition}
        onopenfs882={() => navigate('fs882')} onopentwopage={() => navigate('fs882-twopage')} onopensivi={() => void openSIVI()}
        oncopyplot={copyPlotToNewNumber} onremoveplot={removePlotFromProject}
        oncollapseinspector={() => { inspectorExpanded = false; }} />
    {/if}
    {#if newSiviModalOpen && $projectState?.contextId}
      {#await import('./entry/SIVIParentCreateModal.svelte') then { default: SIVIParentCreateModal }}
        <SIVIParentCreateModal contextId={$projectState.contextId} activeProject={$projectState.activeProject} activeSu={$projectState.activeSU}
          open={newSiviModalOpen} operationHeld={busy || editorBusy || secondaryPanelBusy || transitionWorking || pendingTransition !== null || !!closeRequest}
          onBusyChange={(value) => { siviModalBusy = value; }}
          oncreated={async (res) => { newSiviModalOpen = false; scopedCatalogKey = ''; await loadPlots(offset); if ($projectState?.contextId) await refreshScopedPlotCatalog($projectState.contextId, page, true); editorPlotNumber = res.plotNumber; editorEntryForm = 'sivi'; view = 'fs882'; }}
          onundone={async () => { scopedCatalogKey = ''; await loadPlots(offset); if ($projectState?.contextId) await refreshScopedPlotCatalog($projectState.contextId, page, true); }} onclose={() => { newSiviModalOpen = false; }} />
      {/await}
    {/if}
  </div>

  {#if resetSampleConfirmOpen && !startupFailure}
    {#await import('./shell/ResetSampleModal.svelte') then { default: ResetSampleModal }}
      <ResetSampleModal open={resetSampleConfirmOpen && !startupFailure} {busy} {editorBusy} {companionPanelBusy} {transitionWorking}
        contextAvailable={!!$projectState?.contextId} onconfirm={() => void confirmResetWorkspaceToSample()} onclose={() => { resetSampleConfirmOpen = false; }} />
    {/await}
  {/if}

  {#if helpDrawerOpen && !startupFailure}
    {#await import('./help/HelpDrawer.svelte') then { default: HelpDrawer }}
      <HelpDrawer open={helpDrawerOpen} topicId={helpDrawerTopicId} initialTab={helpDrawerTab} onclose={() => { helpDrawerOpen = false; }}
        onstarttour={(tid) => { helpDrawerOpen = false; tourInitialId = tid ?? null; tourOpen = true; }} />
    {/await}
  {/if}
  {#if tourOpen && !startupFailure}
    {#await import('./help/OnboardingTour.svelte') then { default: OnboardingTour }}
      <OnboardingTour open={tourOpen} initialTourId={tourInitialId} activeProject={$projectState?.activeProject ?? 'Sample'}
        onensurecontextopen={() => { if (!contextExpanded) tourAutoOpenedContext = true; contextExpanded = true; }}
        onrestorecontext={() => { if (tourAutoOpenedContext || isNarrowViewport) { tourAutoOpenedContext = false; contextExpanded = false; } }}
        onnavigateview={(nextView) => { navigate(nextView as typeof view); }}
        onresetsample={async () => { if (tourAutoOpenedContext || isNarrowViewport) { tourAutoOpenedContext = false; contextExpanded = false; } tourOpen = false; resetSampleConfirmOpen = true; }}
        onclose={() => { if (tourAutoOpenedContext || isNarrowViewport) { tourAutoOpenedContext = false; contextExpanded = false; } tourOpen = false; tourInitialId = null; }} />
    {/await}
  {/if}
  {#if shortcutsModalOpen && !startupFailure}
    {#await import('./help/KeyboardShortcutsModal.svelte') then { default: KeyboardShortcutsModal }}
      <KeyboardShortcutsModal open={shortcutsModalOpen} onclose={() => { shortcutsModalOpen = false; }} />
    {/await}
  {/if}
  {#if whatsNewModalOpen && !startupFailure}
    {#await import('./help/WhatsNewModal.svelte') then { default: WhatsNewModal }}
      <WhatsNewModal open={whatsNewModalOpen} initialStatus={whatsNewStatus} onstatuschange={(updated) => { whatsNewStatus = updated; }} onclose={() => { whatsNewModalOpen = false; }} />
    {/await}
  {/if}
  {#if aboutModalOpen && !startupFailure}
    {#await import('./help/AboutVProModal.svelte') then { default: AboutVProModal }}
      <AboutVProModal open={aboutModalOpen} onclose={() => { aboutModalOpen = false; }} />
    {/await}
  {/if}
  {#if userSetupOpen && !startupFailure}
    {#await import('./shell/UserSetupModal.svelte') then { default: UserSetupModal }}
      <UserSetupModal open={userSetupOpen} contextId={$projectState?.contextId ?? ''}
        activeProject={$projectState?.activeProject ?? 'None'}
        onSaved={async () => {
          if (!editorBusy && !companionPanelBusy && !workbenchDirtyLabel) {
            await refresh();
          } else {
            const nextState = await stateReads.track(ContextService.GetState());
            projectState.set(nextState);
          }
        }}
        onclose={() => { userSetupOpen = false; }} />
    {/await}
  {/if}

  {#if !startupFailure}
    <CommandPalette
      open={commandPaletteOpen}
      catalogInput={commandCatalogInput}
      onselect={handleCommandPaletteSelect}
      onclose={() => { commandPaletteOpen = false; }}
    />
    <NotificationDrawer
      open={notificationDrawerOpen}
      controller={notifications}
      onclose={() => { notificationDrawerOpen = false; }}
    />
  {/if}
  <NotificationHost controller={notifications} />
</div>
