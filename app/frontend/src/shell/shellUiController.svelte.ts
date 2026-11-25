import { tick } from 'svelte';
import {
  ContextService,
  DatasheetService,
  type HierarchyNode,
  type PlotPage,
  type ProjectPlotProfileFilterRequest,
  type ProjectState,
  type StartupState,
} from '../../bindings/github.com/boostao/vpro/app';
import type {
  ContextSelection,
  PlotSummary,
} from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
import {
  profileNavigationPage,
  validateProfileNavigation,
  type ProfileNavigation,
} from '../classification/projectPlotProfileReview';
import {
  defaultHelpPort,
  resolveContextualHelpTarget,
  type HelpDrawerTab,
  type HelpMenuAction,
  type WhatsNewStatus,
} from '../help/helpSystem';
import { invalidatePlotBundle, peekPlotBundle } from '../entry/entryReferenceCache';
import { onContextDisposed } from '../shared/contextSessionRegistry';
import { formatError, ReadRequests } from '../shared/readRequests';
import { plotLookupInputError, validateScopedPlotLookup } from '../shared/scopedPlotLookup';
import { projectState, webMeta } from '../shared/state';
import { IS_WEB_READONLY } from '../web/runtimeMode';
import type { EditorCloseState } from './closeLifecycle';
import type { CommandPaletteAction } from './commandPalette';
import { notifications, type NotificationStateSnapshot } from './notificationService.svelte';
import {
  buildShellCommandCatalogInput,
  extractDatasheetPlotSummaries,
  mergeAvailablePlots,
  runCopyPlotToNewNumber,
  runRemovePlotFromProject,
  runScopedPlotCatalogRefresh,
  type CreatedSiviPlotEntry,
  type DiagnosticsDraftContext,
  type FS882EditorHandle,
  type ShellViewId,
} from './shellPlotOps';

const CONTEXT_EXPANDED_STORAGE_KEY = 'vpro.shell.contextExpanded';

export async function lookupScopedPlotOp(params: {
  number: string;
  contextId: string;
  profileNavigation: ProfileNavigation | null;
  plotReads: ReadRequests;
  stateReads: ReadRequests;
  getCurrentContextId: () => string | undefined;
  contextService?: Pick<typeof ContextService, 'ResolveProjectPlotProfileNavigation' | 'LookupScopedPlot'>;
}) {
  const {
    number,
    contextId,
    profileNavigation,
    plotReads,
    stateReads,
    getCurrentContextId,
    contextService = ContextService,
  } = params;
  const invalid = plotLookupInputError(number);
  if (invalid) throw new Error(invalid);
  if (profileNavigation) {
    if (profileNavigation.contextId !== contextId) {
      throw new Error('Reviewed profile navigation belongs to an old context.');
    }
    const rawNav = await plotReads.track(
      contextService.ResolveProjectPlotProfileNavigation(contextId, profileNavigation.proposal)
    );
    if (getCurrentContextId() !== contextId) {
      throw new Error('Project/SU context changed; navigation was not published.');
    }
    const next = validateProfileNavigation(rawNav, profileNavigation.proposal, contextId);
    if (!next.plots.some((plot) => plot.plotNumber === number)) {
      throw new Error('Plot is outside the reviewed profile filter; current filter is unchanged.');
    }
  }
  const result = await stateReads.track(contextService.LookupScopedPlot(contextId, { plotNumber: number }));
  if (getCurrentContextId() !== contextId) {
    throw new Error('Find belongs to an old context; current editor is unchanged.');
  }
  return validateScopedPlotLookup(result, number, contextId);
}

export interface ShellReactiveSnapshot {
  state: ProjectState | null;
  startupFailure: StartupState | null;
  view: ShellViewId;
  editorEntryForm: 'fs882' | 'sivi' | 'fs882-twopage';
  editorPlotNumber: string | undefined;
  editor: FS882EditorHandle | undefined;
  closeState: EditorCloseState | undefined;
  selected: PlotSummary | null;
  page: PlotPage | null;
  offset: number;
  pageSize: number;
  profileNavigation: ProfileNavigation | null;
  busy: boolean;
  editorBusy: boolean;
  companionPanelBusy: boolean;
  transitionWorking: boolean;
  operationBusy: boolean;
  workbenchDirty: boolean;
}

export interface ShellStatePatch {
  view?: ShellViewId;
  busy?: boolean;
  error?: string;
  pausedByGuard?: boolean;
  lastPushedError?: string;
  editorPlotNumber?: string | undefined;
  hasEditorPlotNumber?: boolean;
  editorEntryForm?: 'fs882' | 'sivi' | 'fs882-twopage';
  selected?: PlotSummary | null;
  page?: PlotPage | null;
  offset?: number;
  hierarchyNodes?: HierarchyNode[];
  profileNavigation?: ProfileNavigation | null;
  standaloneMetadataPlot?: string;
  startupFailure?: StartupState | null;
  closeRequest?: string;
  closeWorking?: boolean;
  closeError?: string;
  transitionWorking?: boolean;
  transitionError?: string;
  pendingTransition?: { contextId: string; run: (contextId: string) => Promise<void> } | null;
  plotFindError?: string;
  plotFindResult?: Awaited<ReturnType<typeof ContextService.LookupScopedPlot>> | null;
}

export interface ShellControllerBridge {
  read: () => ShellReactiveSnapshot;
  patch: (next: ShellStatePatch) => void;
  plotReads: ReadRequests;
  stateReads: ReadRequests;
  bumpPlotRequest: () => void;
  requestTransition: (run: (contextId: string) => Promise<void>, ownedAction?: () => boolean) => Promise<void>;
  navigate: (next: ShellViewId | 'fs882-twopage') => void;
  openProjectMetadata: () => Promise<void>;
  switchContext: (contextId: string, selection: ContextSelection, next: 'plots' | 'hierarchy') => Promise<void>;
  reloadPlotsAndHierarchyAfterReset: (nextState: ProjectState) => Promise<void>;
  reloadCurrentOffsetPlots: () => Promise<void>;
}

export function createShellUiController(bridge: ShellControllerBridge) {
  let helpDrawerOpen = $state(false);
  let helpDrawerTopicId = $state('site.plot_number');
  let helpDrawerTab = $state<HelpDrawerTab>('inspector');
  let tourOpen = $state(false);
  let tourInitialId = $state<string | null>(null);
  let shortcutsModalOpen = $state(false);
  let whatsNewModalOpen = $state(false);
  let aboutModalOpen = $state(false);
  let userSetupOpen = $state(false);
  let resetSampleConfirmOpen = $state(false);
  let whatsNewStatus = $state.raw<WhatsNewStatus | null>(null);
  let whatsNewPromptDismissed = $state(false);
  let contextExpanded = $state(false);
  let inspectorExpanded = $state(false);
  let isNarrowViewport = $state(false);
  let commandPaletteOpen = $state(false);
  let notificationDrawerOpen = $state(false);
  let newSiviModalOpen = $state(false);
  let notifSnapshot = $state<NotificationStateSnapshot>(notifications.getSnapshot());
  let webMetaPicturesAvailable = $state<boolean>(true);
  let startupInfo = $state<StartupState | null>(null);
  let projectAdminTab = $state<'lifecycle' | 'compliance' | 'optimizeveg' | 'merge' | 'cloudsync'>('lifecycle');
  let projectAdminTabNonce = $state(0);
  let pictureManagerPlot = $state('');
  let plotLabelNumber = $state('');
  let diagnosticsDraft = $state.raw<DiagnosticsDraftContext | null>(null);
  let standaloneMetadataEditor = $state<
    { hasUnsavedChanges?: () => boolean; getCloseState: () => EditorCloseState; undo: () => void } | undefined
  >(undefined);
  let localEditorBusy = $state(false);
  let secondaryPanelBusy = $state(false);
  let siviModalBusy = $state(false);
  let fs882ModuleLoaded = $state(false);
  let plotProfilePanel = $state<
    | {
        reviewProfileSU: (proposal: ProjectPlotProfileFilterRequest, origin: string) => Promise<void>;
        clearCachedSources: () => void;
        resetAllReviews: () => void;
      }
    | undefined
  >(undefined);
  let plotFindOpen = $state(false);

  let catalogPlotRequest = 0;
  let paletteSearchRequest = 0;
  let scopedCatalogKey = '';
  let scopedPlotCatalogRows = $state<PlotSummary[]>([]);
  let dynamicPalettePlotRows = $state<PlotSummary[]>([]);
  let createdSiviPlots = $state<CreatedSiviPlotEntry[]>([]);
  const catalogPlotReads = new ReadRequests();
  const paletteSearchReads = new ReadRequests();

  const loadedPlotRows = $derived.by<PlotSummary[]>(() => {
    const pg = bridge.read().page;
    return (
      (pg as (PlotPage & { rows?: PlotSummary[] }) | null)?.plots ?? (pg as { rows?: PlotSummary[] } | null)?.rows ?? []
    );
  });
  const allAvailablePlots = $derived(
    mergeAvailablePlots(bridge.read().profileNavigation, scopedPlotCatalogRows, loadedPlotRows, dynamicPalettePlotRows)
  );
  const canUndoSelectedPlot = $derived.by(() => {
    const sel = bridge.read().selected?.plotNumber;
    return Boolean(sel && createdSiviPlots.some((e) => e.plotNumber === sel && e.canUndo));
  });
  const canUndoEditorPlot = $derived.by(() => {
    const ed = bridge.read().editorPlotNumber;
    return Boolean(ed && createdSiviPlots.some((e) => e.plotNumber === ed && e.canUndo));
  });
  const profileIndex = $derived.by(() => {
    const snap = bridge.read();
    return snap.profileNavigation?.plots.findIndex((plot) => plot.plotNumber === snap.editorPlotNumber) ?? -1;
  });
  const buildMode = $derived(startupInfo?.buildMode ?? '');
  const appVersion = $derived(startupInfo?.appVersion ?? '');
  const shortBuildCommit = $derived.by(() => {
    const raw = (startupInfo?.gitCommit ?? '').trim();
    return /^[0-9a-f]{8,40}$/i.test(raw) ? raw.slice(0, 7) : raw;
  });
  const releaseChannel = $derived(startupInfo?.releaseChannel ?? 'stable');
  const currentContextPlotNumber = $derived.by(() => {
    const snap = bridge.read();
    return (
      (snap.view === 'fs882' ? snap.editorPlotNumber : snap.selected?.plotNumber) ?? snap.selected?.plotNumber ?? ''
    );
  });
  const currentContextPlotIndex = $derived(
    currentContextPlotNumber ? allAvailablePlots.findIndex((p) => p.plotNumber === currentContextPlotNumber) : -1
  );
  const canStepPrevPlot = $derived(
    allAvailablePlots.length > 0 && !bridge.read().operationBusy && currentContextPlotIndex > 0
  );
  const canStepNextPlot = $derived(
    allAvailablePlots.length > 0 &&
      !bridge.read().operationBusy &&
      (currentContextPlotIndex === -1
        ? allAvailablePlots.length > 0
        : currentContextPlotIndex < allAvailablePlots.length - 1)
  );
  const sessionStatusKind = $derived.by<'busy' | 'dirty' | 'ready'>(() => {
    const snap = bridge.read();
    if (snap.busy || snap.editorBusy || snap.companionPanelBusy || snap.transitionWorking) return 'busy';
    if ((snap.closeState?.unsaved ?? false) || snap.workbenchDirty) return 'dirty';
    return 'ready';
  });
  const sessionStatusLabel = $derived(
    sessionStatusKind === 'busy' ? 'Busy' : sessionStatusKind === 'dirty' ? 'Unsaved Draft' : 'Ready'
  );
  const showInspectorToggle = $derived(bridge.read().view === 'home' || bridge.read().view === 'plots');
  const showInspectorRail = $derived(!bridge.read().startupFailure && showInspectorToggle && inspectorExpanded);
  const metadataAvailable = $derived.by(() => {
    const snap = bridge.read();
    if (!snap.state?.contextId) return false;
    if (snap.view !== 'fs882') return true;
    return Boolean(
      snap.editor?.canOpenProjectMetadata() || (!snap.editorPlotNumber && snap.editorEntryForm === 'fs882-twopage')
    );
  });
  const newSiviAvailable = $derived.by(() => {
    const snap = bridge.read();
    return Boolean(
      snap.state?.contextId && !snap.busy && !snap.editorBusy && !snap.companionPanelBusy && !snap.transitionWorking
    );
  });
  const commandCatalogInput = $derived({
    ...buildShellCommandCatalogInput({
      allAvailablePlots,
      state: bridge.read().state,
      selectedPlotNumber: currentContextPlotNumber || null,
      metadataAvailable,
      newSiviAvailable: IS_WEB_READONLY ? false : newSiviAvailable,
    }),
    webReadOnly: IS_WEB_READONLY,
    picturesAvailable: !IS_WEB_READONLY || webMetaPicturesAvailable,
  });

  $effect(() =>
    notifications.subscribe((next) => {
      notifSnapshot = next;
    })
  );

  $effect(() => {
    if (!IS_WEB_READONLY) return;
    return webMeta.subscribe((next) => {
      webMetaPicturesAvailable = next?.picturesAvailable ?? true;
    });
  });

  async function refreshScopedPlotCatalog(expectedContextId: string, currentPage: PlotPage | null, force = false) {
    const snap = bridge.read();
    await runScopedPlotCatalogRefresh({
      expectedContextId,
      currentPage,
      offset: snap.offset,
      force,
      scopedCatalogKey,
      hasCatalogRows: scopedPlotCatalogRows.length > 0,
      profileNavigation: snap.profileNavigation,
      getState: () => bridge.read().state,
      nextRequestId: () => ++catalogPlotRequest,
      isCurrentRequest: (reqId) => reqId === catalogPlotRequest,
      catalogPlotReads,
      contextService: ContextService,
      onCreatedSiviPlots: (rows) => {
        createdSiviPlots = rows;
      },
      onCatalogResolved: (rows, key) => {
        scopedPlotCatalogRows = rows;
        scopedCatalogKey = key;
      },
    });
  }

  $effect(() => {
    const snap = bridge.read();
    const ctxId = snap.state?.contextId ?? '';
    void snap.profileNavigation;
    if (!ctxId || !snap.page || snap.operationBusy) return;
    void refreshScopedPlotCatalog(ctxId, snap.page);
  });

  $effect(() => {
    if (!commandPaletteOpen || typeof document === 'undefined') {
      paletteSearchRequest++;
      paletteSearchReads.cancelAll();
      dynamicPalettePlotRows = [];
      return;
    }
    const snap = bridge.read();
    const ctxId = snap.state?.contextId ?? '';
    if (!ctxId || snap.profileNavigation || (snap.page?.total ?? 0) <= scopedPlotCatalogRows.length) return;
    let debounceTimer: ReturnType<typeof setTimeout> | null = null;
    const handleInput = (ev: Event) => {
      const target = ev.target as HTMLInputElement | null;
      if (!target?.matches?.('[data-command-palette-input]')) return;
      if (debounceTimer) clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => {
        const cleaned = target.value
          .trim()
          .replace(/^plot\s+/i, '')
          .trim();
        const reqId = ++paletteSearchRequest;
        paletteSearchReads.cancelAll();
        if (!cleaned) {
          dynamicPalettePlotRows = [];
          return;
        }
        void paletteSearchReads
          .track(
            DatasheetService.GetDatasheetPage(ctxId, {
              tableKey: 'Env',
              offset: 0,
              limit: 50,
              sort: null,
              filters: null,
              globalSearch: cleaned,
              scopeToActiveSU: (bridge.read().state?.activeSU ?? 'None') !== 'None',
            })
          )
          .then((dsPage) => {
            if (reqId === paletteSearchRequest && bridge.read().state?.contextId === ctxId) {
              dynamicPalettePlotRows = extractDatasheetPlotSummaries(dsPage);
            }
          })
          .catch(() => {});
      }, 120);
    };
    document.addEventListener('input', handleInput, true);
    return () => {
      if (debounceTimer) clearTimeout(debounceTimer);
      document.removeEventListener('input', handleInput, true);
    };
  });

  function cancelCatalogReads() {
    catalogPlotRequest++;
    paletteSearchRequest++;
    catalogPlotReads.cancelAll();
    paletteSearchReads.cancelAll();
  }
  function clearCatalogCaches() {
    scopedCatalogKey = '';
    scopedPlotCatalogRows = [];
    dynamicPalettePlotRows = [];
    createdSiviPlots = [];
    diagnosticsDraft = null;
  }

  async function refreshCatalogAfterWrite() {
    scopedCatalogKey = '';
    await bridge.reloadCurrentOffsetPlots();
    const snap = bridge.read();
    if (snap.state?.contextId) await refreshScopedPlotCatalog(snap.state.contextId, snap.page, true);
  }

  async function resolveNavigation(proposal: ProjectPlotProfileFilterRequest, contextId: string) {
    const response = await bridge.plotReads.track(
      ContextService.ResolveProjectPlotProfileNavigation(contextId, proposal)
    );
    if (bridge.read().state?.contextId !== contextId) {
      throw new Error('Project/SU context changed; navigation was not published.');
    }
    return validateProfileNavigation(response, proposal, contextId);
  }

  async function applyProfileNavigation(proposal: ProjectPlotProfileFilterRequest, origin: string) {
    await bridge.requestTransition(async (contextId) => {
      if (contextId !== origin) throw new Error('Profile proposal belongs to an old context.');
      bridge.patch({ busy: true });
      try {
        await tick();
        const next = await resolveNavigation(proposal, contextId);
        const nextPage = profileNavigationPage(next, contextId, 0, bridge.read().pageSize);
        bridge.bumpPlotRequest();
        bridge.plotReads.cancelAll();
        bridge.patch({
          profileNavigation: next,
          page: nextPage,
          offset: 0,
          selected: null,
          editorPlotNumber: undefined,
          hasEditorPlotNumber: true,
          view: 'plots',
          error: '',
        });
      } finally {
        bridge.patch({ busy: false });
      }
    });
  }

  async function clearProfileNavigation() {
    await bridge.requestTransition(async (contextId) => {
      bridge.patch({ busy: true });
      try {
        await tick();
        const next = await bridge.plotReads.track(ContextService.ListPlots(0, bridge.read().pageSize));
        const state = await bridge.stateReads.track(ContextService.GetState());
        if (state.contextId !== contextId || bridge.read().state?.contextId !== contextId) {
          throw new Error('Context changed before clearing navigation.');
        }
        bridge.bumpPlotRequest();
        bridge.plotReads.cancelAll();
        bridge.patch({
          profileNavigation: null,
          page: next,
          offset: 0,
          selected: null,
          editorPlotNumber: undefined,
          hasEditorPlotNumber: true,
          view: 'plots',
          error: '',
        });
      } finally {
        bridge.patch({ busy: false });
      }
    });
  }

  async function navigateProfilePlot(delta: number) {
    const source = bridge.read().profileNavigation;
    const target = source?.plots[profileIndex + delta]?.plotNumber;
    if (!source || !target) {
      bridge.patch({ error: 'Select an available plot in the reviewed navigation recordset.' });
      return;
    }
    await bridge.requestTransition(async (contextId) => {
      if (contextId !== source.contextId) throw new Error('Profile navigation belongs to an old context.');
      bridge.patch({ busy: true });
      try {
        await tick();
        const next = await resolveNavigation(source.proposal, contextId);
        if (!next.plots.some((plot) => plot.plotNumber === target)) {
          throw new Error('Reviewed navigation target is no longer available.');
        }
        if (!peekPlotBundle(contextId, target)) diagnosticsDraft = null;
        bridge.patch({
          profileNavigation: next,
          editorPlotNumber: target,
          hasEditorPlotNumber: true,
          view: 'fs882',
          error: '',
        });
      } finally {
        bridge.patch({ busy: false });
      }
    });
  }

  async function openFoundPlot(params: {
    plotFindResult: Awaited<ReturnType<typeof ContextService.LookupScopedPlot>> | null;
    setPlotFindError: (msg: string) => void;
    clearPlotFind: () => void;
  }) {
    const { plotFindResult, setPlotFindError, clearPlotFind } = params;
    const snap = bridge.read();
    if (!plotFindResult || plotFindResult.contextId !== snap.state?.contextId) {
      setPlotFindError('Find an available plot in the current scope before opening it.');
      return;
    }
    const proposal = $state.snapshot(plotFindResult);
    if (proposal.plot.plotNumber === snap.editorPlotNumber) {
      setPlotFindError('Found plot is already open; no draft or navigation change.');
      return;
    }
    await bridge.requestTransition(async (contextId) => {
      if (contextId !== proposal.contextId) throw new Error('Found plot belongs to an old context; find again.');
      bridge.patch({ busy: true });
      setPlotFindError('');
      try {
        await tick();
        const current = await lookupScopedPlotOp({
          number: proposal.plot.plotNumber,
          contextId,
          profileNavigation: bridge.read().profileNavigation,
          plotReads: bridge.plotReads,
          stateReads: bridge.stateReads,
          getCurrentContextId: () => bridge.read().state?.contextId,
        });
        if (JSON.stringify(current) !== JSON.stringify(proposal)) {
          throw new Error('Found plot summary changed since review; find again before opening.');
        }
        if (!peekPlotBundle(contextId, current.plot.plotNumber)) diagnosticsDraft = null;
        clearPlotFind();
        bridge.patch({
          editorPlotNumber: current.plot.plotNumber,
          hasEditorPlotNumber: true,
          view: 'fs882',
          selected: null,
          error: '',
        });
      } catch (cause) {
        setPlotFindError(`Could not open found plot: ${formatError(cause)}`);
        throw cause;
      } finally {
        bridge.patch({ busy: false });
      }
    });
  }

  function toggleContextSidebar() {
    contextExpanded = !contextExpanded;
    try {
      if (typeof sessionStorage !== 'undefined')
        sessionStorage.setItem(CONTEXT_EXPANDED_STORAGE_KEY, String(contextExpanded));
    } catch {
      // Ignore storage failures in restricted contexts
    }
  }

  function openContextualHelp(topicOverride?: string, tabOverride: HelpDrawerTab = 'inspector') {
    const activeEl = typeof document !== 'undefined' ? document.activeElement : null;
    const snap = bridge.read();
    helpDrawerTopicId = topicOverride ?? resolveContextualHelpTarget(activeEl, snap.view, snap.editorEntryForm);
    helpDrawerTab = tabOverride;
    helpDrawerOpen = true;
  }

  function handleHelpMenuAction(action: HelpMenuAction) {
    if (action === 'guide') openContextualHelp(undefined, 'inspector');
    else if (action === 'tours') {
      tourInitialId = null;
      tourOpen = true;
    } else if (action === 'shortcuts') shortcutsModalOpen = true;
    else if (action === 'whats-new') whatsNewModalOpen = true;
    else if (action === 'reset-sample') {
      if (!IS_WEB_READONLY) resetSampleConfirmOpen = true;
    } else if (action === 'about') aboutModalOpen = true;
  }

  async function acknowledgeUnreadWhatsNew() {
    if (!whatsNewStatus?.latestVersion) return;
    try {
      whatsNewStatus = await defaultHelpPort.acknowledgeWhatsNew(whatsNewStatus.latestVersion);
    } catch (cause) {
      bridge.patch({ error: `Could not acknowledge What's New: ${formatError(cause)}` });
    }
  }

  async function confirmResetWorkspaceToSample() {
    resetSampleConfirmOpen = false;
    const ownedDiscardOnSample =
      bridge.read().state?.activeProject === 'Sample'
        ? () => !bridge.read().editorBusy && !bridge.read().companionPanelBusy
        : undefined;
    await bridge.requestTransition(async (contextId) => {
      const nextState = await defaultHelpPort.resetWorkspaceToSample(contextId);
      if (nextState.contextId !== contextId) onContextDisposed(contextId);
      resetSampleConfirmOpen = false;
      notifications.push({
        severity: 'success',
        category: 'general',
        source: 'Workspace',
        title: 'Workspace reset to Sample project',
        message: 'User project .db files were preserved.',
      });
      await bridge.reloadPlotsAndHierarchyAfterReset(nextState);
    }, ownedDiscardOnSample);
  }

  async function copyPlotToNewNumber(sourcePlot: string, rawTargetPlot: string) {
    const snap = bridge.read();
    await runCopyPlotToNewNumber({
      sourcePlot,
      rawTargetPlot,
      isBusy: snap.operationBusy,
      hasUnsavedEdits: Boolean((snap.closeState?.unsaved ?? false) || snap.workbenchDirty),
      contextId: snap.state?.contextId,
      allAvailablePlots,
      contextService: ContextService,
      reloadAndSelect: async (targetPlot, fallbackSummary) => {
        if (snap.state?.contextId) invalidatePlotBundle(snap.state.contextId);
        await refreshCatalogAfterWrite();
        const selected = allAvailablePlots.find((p) => p.plotNumber === targetPlot) ?? fallbackSummary;
        bridge.patch(
          bridge.read().view === 'fs882'
            ? { selected, editorPlotNumber: targetPlot, hasEditorPlotNumber: true }
            : { selected }
        );
      },
    });
  }

  async function removePlotFromProject(sourcePlot: string, rawCleanProjectName: string) {
    const snap = bridge.read();
    await runRemovePlotFromProject({
      sourcePlot,
      rawCleanProjectName,
      isBusy: snap.operationBusy,
      hasUnsavedEdits: Boolean((snap.closeState?.unsaved ?? false) || snap.workbenchDirty),
      contextId: snap.state?.contextId,
      createdSiviPlots,
      allAvailablePlots,
      contextService: ContextService,
      datasheetService: DatasheetService,
      onUndoneSivi: async (removed) => {
        if (snap.state?.contextId) invalidatePlotBundle(snap.state.contextId);
        const cur = bridge.read();
        const patch: ShellStatePatch = {};
        if (cur.selected?.plotNumber === removed) patch.selected = null;
        if (cur.editorPlotNumber === removed) {
          patch.editorPlotNumber = undefined;
          patch.hasEditorPlotNumber = true;
          if (cur.view === 'fs882') patch.view = 'plots';
        }
        bridge.patch(patch);
        await refreshCatalogAfterWrite();
      },
      onSplinterSwitched: async (result) => {
        const prevCtx = bridge.read().state?.contextId;
        if (prevCtx) invalidatePlotBundle(prevCtx);
        if (result?.state && prevCtx && result.state.contextId !== prevCtx) onContextDisposed(prevCtx);
        clearCatalogCaches();
        if (result?.state) projectState.set(result.state);
        bridge.patch({ selected: null, editorPlotNumber: undefined, hasEditorPlotNumber: true, view: 'plots' });
        await bridge.reloadCurrentOffsetPlots();
      },
    });
  }

  function stepContextPlot(delta: -1 | 1) {
    const targetIdx = currentContextPlotIndex === -1 ? (delta > 0 ? 0 : -1) : currentContextPlotIndex + delta;
    const target = allAvailablePlots[targetIdx];
    if (!target) return;
    if (bridge.read().view === 'fs882') {
      void bridge.requestTransition(async () => {
        bridge.patch({ selected: target, editorPlotNumber: target.plotNumber, hasEditorPlotNumber: true, error: '' });
      });
      return;
    }
    bridge.patch({ selected: target });
    if (!isNarrowViewport && bridge.read().view === 'plots') inspectorExpanded = true;
  }

  function handleCommandPaletteSelect(action: CommandPaletteAction) {
    if (action.kind === 'open-plot-fs882' || action.kind === 'open-plot-twopage' || action.kind === 'open-plot-sivi') {
      void bridge.requestTransition(async () => {
        const found = allAvailablePlots.find((p) => p.plotNumber === action.plotNumber) ?? null;
        const patch: ShellStatePatch = {
          editorPlotNumber: action.plotNumber,
          hasEditorPlotNumber: true,
          editorEntryForm:
            action.kind === 'open-plot-twopage' ? 'fs882-twopage' : action.kind === 'open-plot-sivi' ? 'sivi' : 'fs882',
          view: 'fs882',
          error: '',
        };
        if (found) patch.selected = found;
        bridge.patch(patch);
      });
    } else if (action.kind === 'switch-project') {
      const targetProj = bridge.read().state?.projects?.[action.projectIndex];
      if (targetProj) {
        void bridge.requestTransition(async (contextId) => {
          const current = bridge.read().state;
          if (current)
            await bridge.switchContext(
              contextId,
              {
                project: targetProj.name,
                projectPath: targetProj.path ?? '',
                su: 'None',
                suPath: '',
                hierarchy: current.activeHierarchy ?? 'None',
                hierarchyPath: current.hierarchyPath ?? '',
              },
              'plots'
            );
        });
      }
    } else if (action.kind === 'switch-su') {
      void bridge.requestTransition(async (contextId) => {
        const current = bridge.read().state;
        const chosen = action.suIndex >= 0 ? current?.sus?.[action.suIndex] : undefined;
        if (current)
          await bridge.switchContext(
            contextId,
            {
              project: current.activeProject,
              projectPath: current.projectPath ?? '',
              su: chosen?.name ?? 'None',
              suPath: chosen?.path ?? '',
              hierarchy: current.activeHierarchy ?? 'None',
              hierarchyPath: current.hierarchyPath ?? '',
            },
            'plots'
          );
      });
    } else if (action.kind === 'navigate-view') bridge.navigate(action.view as ShellViewId | 'fs882-twopage');
    else if (action.kind === 'new-sivi' && newSiviAvailable) newSiviModalOpen = true;
    else if (action.kind === 'open-metadata') void bridge.openProjectMetadata();
    else if (action.kind === 'help-topic') openContextualHelp(action.topicId, action.tab ?? 'inspector');
    else if (action.kind === 'help-action') handleHelpMenuAction(action.action);
  }

  function installViewportAndWhatsNew(): () => void {
    const readSaved = (fallback: boolean) => {
      try {
        const saved =
          typeof sessionStorage !== 'undefined' ? sessionStorage.getItem(CONTEXT_EXPANDED_STORAGE_KEY) : null;
        return saved === null ? fallback : saved === 'true';
      } catch {
        return fallback;
      }
    };
    const syncViewport = () => {
      if (typeof window === 'undefined') return;
      const narrow = window.innerWidth < 1200;
      if (narrow && !isNarrowViewport) {
        contextExpanded = false;
        inspectorExpanded = false;
      } else if (!narrow && isNarrowViewport) contextExpanded = readSaved(true);
      isNarrowViewport = narrow;
    };
    if (typeof window !== 'undefined') {
      isNarrowViewport = window.innerWidth < 1200;
      contextExpanded = isNarrowViewport ? false : readSaved(true);
      inspectorExpanded = !isNarrowViewport;
      window.addEventListener('resize', syncViewport);
    }
    void defaultHelpPort
      .getWhatsNewStatus()
      .then((st) => {
        whatsNewStatus = st;
      })
      .catch(() => {});
    return () => {
      if (typeof window !== 'undefined') window.removeEventListener('resize', syncViewport);
    };
  }

  function hasBlockingModalOpen(): boolean {
    return (
      commandPaletteOpen ||
      notificationDrawerOpen ||
      shortcutsModalOpen ||
      whatsNewModalOpen ||
      aboutModalOpen ||
      tourOpen ||
      resetSampleConfirmOpen ||
      userSetupOpen
    );
  }

  return {
    get helpDrawerOpen() {
      return helpDrawerOpen;
    },
    set helpDrawerOpen(v: boolean) {
      helpDrawerOpen = v;
    },
    get helpDrawerTopicId() {
      return helpDrawerTopicId;
    },
    get helpDrawerTab() {
      return helpDrawerTab;
    },
    get tourOpen() {
      return tourOpen;
    },
    set tourOpen(v: boolean) {
      tourOpen = v;
    },
    get tourInitialId() {
      return tourInitialId;
    },
    set tourInitialId(v: string | null) {
      tourInitialId = v;
    },
    get shortcutsModalOpen() {
      return shortcutsModalOpen;
    },
    set shortcutsModalOpen(v: boolean) {
      shortcutsModalOpen = v;
    },
    get whatsNewModalOpen() {
      return whatsNewModalOpen;
    },
    set whatsNewModalOpen(v: boolean) {
      whatsNewModalOpen = v;
    },
    get aboutModalOpen() {
      return aboutModalOpen;
    },
    set aboutModalOpen(v: boolean) {
      aboutModalOpen = v;
    },
    get userSetupOpen() {
      return userSetupOpen;
    },
    set userSetupOpen(v: boolean) {
      userSetupOpen = v;
    },
    get resetSampleConfirmOpen() {
      return resetSampleConfirmOpen;
    },
    set resetSampleConfirmOpen(v: boolean) {
      resetSampleConfirmOpen = v;
    },
    get whatsNewStatus() {
      return whatsNewStatus;
    },
    set whatsNewStatus(v: WhatsNewStatus | null) {
      whatsNewStatus = v;
    },
    get whatsNewPromptDismissed() {
      return whatsNewPromptDismissed;
    },
    set whatsNewPromptDismissed(v: boolean) {
      whatsNewPromptDismissed = v;
    },
    get contextExpanded() {
      return contextExpanded;
    },
    set contextExpanded(v: boolean) {
      contextExpanded = v;
    },
    get inspectorExpanded() {
      return inspectorExpanded;
    },
    set inspectorExpanded(v: boolean) {
      inspectorExpanded = v;
    },
    get isNarrowViewport() {
      return isNarrowViewport;
    },
    get commandPaletteOpen() {
      return commandPaletteOpen;
    },
    set commandPaletteOpen(v: boolean) {
      commandPaletteOpen = v;
    },
    get notificationDrawerOpen() {
      return notificationDrawerOpen;
    },
    set notificationDrawerOpen(v: boolean) {
      notificationDrawerOpen = v;
    },
    get newSiviModalOpen() {
      return newSiviModalOpen;
    },
    set newSiviModalOpen(v: boolean) {
      newSiviModalOpen = v;
    },
    get notifSnapshot() {
      return notifSnapshot;
    },
    get startupInfo() {
      return startupInfo;
    },
    set startupInfo(v: StartupState | null) {
      startupInfo = v;
    },
    get projectAdminTab() {
      return projectAdminTab;
    },
    set projectAdminTab(v: 'lifecycle' | 'compliance' | 'optimizeveg' | 'merge' | 'cloudsync') {
      projectAdminTab = v;
    },
    get projectAdminTabNonce() {
      return projectAdminTabNonce;
    },
    set projectAdminTabNonce(v: number) {
      projectAdminTabNonce = v;
    },
    get pictureManagerPlot() {
      return pictureManagerPlot;
    },
    set pictureManagerPlot(v: string) {
      pictureManagerPlot = v;
    },
    get plotLabelNumber() {
      return plotLabelNumber;
    },
    set plotLabelNumber(v: string) {
      plotLabelNumber = v;
    },
    get diagnosticsDraft() {
      return diagnosticsDraft;
    },
    set diagnosticsDraft(v: DiagnosticsDraftContext | null) {
      diagnosticsDraft = v;
    },
    get standaloneMetadataEditor() {
      return standaloneMetadataEditor;
    },
    set standaloneMetadataEditor(v) {
      standaloneMetadataEditor = v;
    },
    get localEditorBusy() {
      return localEditorBusy;
    },
    set localEditorBusy(v: boolean) {
      localEditorBusy = v;
    },
    get secondaryPanelBusy() {
      return secondaryPanelBusy;
    },
    set secondaryPanelBusy(v: boolean) {
      secondaryPanelBusy = v;
    },
    get siviModalBusy() {
      return siviModalBusy;
    },
    set siviModalBusy(v: boolean) {
      siviModalBusy = v;
    },
    get fs882ModuleLoaded() {
      return fs882ModuleLoaded;
    },
    set fs882ModuleLoaded(v: boolean) {
      fs882ModuleLoaded = v;
    },
    get plotProfilePanel() {
      return plotProfilePanel;
    },
    set plotProfilePanel(v) {
      plotProfilePanel = v;
    },
    get plotFindOpen() {
      return plotFindOpen;
    },
    set plotFindOpen(v: boolean) {
      plotFindOpen = v;
    },
    get allAvailablePlots() {
      return allAvailablePlots;
    },
    get canUndoSelectedPlot() {
      return canUndoSelectedPlot;
    },
    get canUndoEditorPlot() {
      return canUndoEditorPlot;
    },
    get profileIndex() {
      return profileIndex;
    },
    get buildMode() {
      return buildMode;
    },
    get appVersion() {
      return appVersion;
    },
    get shortBuildCommit() {
      return shortBuildCommit;
    },
    get releaseChannel() {
      return releaseChannel;
    },
    get currentContextPlotNumber() {
      return currentContextPlotNumber;
    },
    get currentContextPlotIndex() {
      return currentContextPlotIndex;
    },
    get canStepPrevPlot() {
      return canStepPrevPlot;
    },
    get canStepNextPlot() {
      return canStepNextPlot;
    },
    get sessionStatusKind() {
      return sessionStatusKind;
    },
    get sessionStatusLabel() {
      return sessionStatusLabel;
    },
    get showInspectorToggle() {
      return showInspectorToggle;
    },
    get showInspectorRail() {
      return showInspectorRail;
    },
    get metadataAvailable() {
      return metadataAvailable;
    },
    get newSiviAvailable() {
      return newSiviAvailable;
    },
    get commandCatalogInput() {
      return commandCatalogInput;
    },
    cancelCatalogReads,
    clearCatalogCaches,
    refreshCatalogAfterWrite,
    resolveNavigation,
    applyProfileNavigation,
    clearProfileNavigation,
    navigateProfilePlot,
    openFoundPlot,
    toggleContextSidebar,
    openContextualHelp,
    handleHelpMenuAction,
    acknowledgeUnreadWhatsNew,
    confirmResetWorkspaceToSample,
    copyPlotToNewNumber,
    removePlotFromProject,
    stepContextPlot,
    handleCommandPaletteSelect,
    installViewportAndWhatsNew,
    hasBlockingModalOpen,
  };
}

export type ShellUiController = ReturnType<typeof createShellUiController>;
