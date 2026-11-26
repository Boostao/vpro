import { Events } from '@wailsio/runtime';
import { VproCloseRequest } from '../../bindings/events';
import {
  ContextService,
  LifecycleService,
  type HierarchyNode,
  type PlotPage,
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
import { classifyGlobalHelpShortcut } from '../help/helpSystem';
import { onContextDisposed } from '../shared/contextSessionRegistry';
import { formatError, type ReadRequests } from '../shared/readRequests';
import { get } from 'svelte/store';
import { projectState, webMeta, webShellRuntime } from '../shared/state';
import { IS_WEB_READONLY } from '../web/runtimeMode';
import { closeDisposition, type CloseDecision, type EditorCloseState } from './closeLifecycle';
import { notifications } from './notificationService.svelte';
import {
  CLOSE_HOLD_NOTICE,
  PAGING_HOLD_NOTICE,
  TRANSITION_HOLD_NOTICE,
  type ShellOperationGuard,
} from './operationGuard.svelte';
import type { FS882EditorHandle, ShellViewId } from './shellPlotOps';
import { lookupScopedPlotOp, type ShellStatePatch, type ShellUiController } from './shellUiController.svelte';

export interface ShellRuntimeSnap {
  state: ProjectState | null;
  view: ShellViewId;
  busy: boolean;
  editorEntryForm: 'fs882' | 'sivi' | 'fs882-twopage';
  editorPlotNumber: string | undefined;
  editor: FS882EditorHandle | undefined;
  selected: PlotSummary | null;
  profileNavigation: ProfileNavigation | null;
  standaloneMetadataPlot: string;
  startupFailure: StartupState | null;
  closeRequest: string;
  closeWorking: boolean;
  pendingTransition: { contextId: string; run: (contextId: string) => Promise<void> } | null;
  transitionWorking: boolean;
  plotFindQuery: string;
  allAvailablePlots: PlotSummary[];
  pageSize: number;
  operationGuard: ShellOperationGuard;
  ui: ShellUiController | undefined;
  plotReads: ReadRequests;
  hierarchyReads: ReadRequests;
  stateReads: ReadRequests;
  lifecycleService: typeof LifecycleService;
  contextService: typeof ContextService;
  notify: typeof notifications;
  tick: () => Promise<void>;
  closeDispositionFn?: typeof closeDisposition;
  nextPlotRequest: () => number;
  isCurrentPlotRequest: (id: number) => boolean;
  nextHierarchyRequest: () => number;
  isCurrentHierarchyRequest: (id: number) => boolean;
  nextStateRequest: () => number;
  isCurrentStateRequest: (id: number) => boolean;
  cancelAllReads: () => void;
  resetMainCaches: () => void;
  loadPlots: (offset: number) => Promise<void>;
  loadHierarchy: () => Promise<void>;
  requestTransition: (run: (contextId: string) => Promise<void>, ownedAction?: () => boolean) => Promise<void>;
  patch: (next: ShellStatePatch) => void;
}

function blurActiveDocumentElement(): void {
  if (
    typeof document !== 'undefined' &&
    typeof HTMLElement !== 'undefined' &&
    document.activeElement instanceof HTMLElement
  ) {
    document.activeElement.blur();
  }
}

export function registerCoreOperationGuards(
  guard: ShellOperationGuard,
  readers: {
    shellBusy: () => boolean;
    localEditor: () => { busy: boolean; dirty: boolean };
    companionPanel: () => { busy: boolean; dirty: boolean };
    editorInit: () => boolean;
    transitionDialog: () => boolean;
    closeDialog: () => boolean;
  }
): void {
  guard.register('shell-busy', () => ({ busy: readers.shellBusy() }), { shellBusy: true });
  guard.register('local-editor', readers.localEditor, { ownedEditor: true });
  guard.register('companion-panel', readers.companionPanel, { ownedEditor: true, companionPanel: true });
  guard.register('editor-init', () => ({ busy: readers.editorInit() }));
  guard.register('transition-dialog', () => ({ busy: readers.transitionDialog() }), { transitionDialog: true });
  guard.register('close-dialog', () => ({ busy: readers.closeDialog() }), { closeDialog: true });
}

export function pushShellErrorNotification(currentError: string, notify = notifications): void {
  const isPause = currentError.startsWith('Wait for ') || currentError.startsWith('Save or discard ');
  notify.push({
    severity: isPause ? 'warning' : 'error',
    category: 'general',
    source: 'Workspace',
    title: currentError.startsWith('Wait for ') ? 'Navigation paused' : 'Workspace alert',
    message: currentError,
    toast: true,
  });
}

export function mountShellWindowLifecycle(
  ui: ShellUiController,
  lifecycleService: Pick<typeof LifecycleService, 'GetPendingCloseRequest'>,
  onCloseReq: (id: string) => void,
  onRefresh: () => void,
  onError: (msg: string) => void,
  onCleanup: () => void,
  webReadOnly: boolean = IS_WEB_READONLY
): () => void {
  void import('../shared/dialogA11y').then(({ installGlobalAriaModalTabTrap }) => installGlobalAriaModalTabTrap());
  const stopViewport = ui.installViewportAndWhatsNew();
  let stopCloseEvents = () => {};
  if (webReadOnly) {
    void import('../web/webMeta').then((mod) => {
      void mod.loadWebMeta();
      void mod.bootstrapWebShellRuntime();
    });
  } else {
    stopCloseEvents = Events.On(VproCloseRequest, (event) => {
      const requestId: unknown = event.data;
      if (typeof requestId !== 'string' || !requestId) {
        onError('Could not complete window close request; VPRO remains open.');
        return;
      }
      onCloseReq(requestId);
    });
    void lifecycleService
      .GetPendingCloseRequest()
      .then((requestId) => {
        if (requestId) onCloseReq(requestId);
      })
      .catch((cause) => onError(`Window close handler could not initialise: ${formatError(cause)}`));
  }
  onRefresh();
  return () => {
    onCleanup();
    stopCloseEvents();
    stopViewport();
  };
}

function evalDisposition(s: ShellRuntimeSnap, closeState: EditorCloseState | null, busy: boolean) {
  return (s.closeDispositionFn ?? closeDisposition)(closeState, busy);
}

export async function runHandleCloseRequestOp(getRt: () => ShellRuntimeSnap, requestId: string): Promise<void> {
  const s0 = getRt();
  if (s0.closeWorking || s0.closeRequest === requestId) return;
  try {
    if ((await s0.lifecycleService.GetPendingCloseRequest()) !== requestId) return;
    blurActiveDocumentElement();
    await s0.tick();
    const s = getRt();
    const dirty = s.operationGuard.hasDirtyWorkbench();
    const closeState = s.view === 'fs882' ? (s.editor?.getCloseState() ?? null) : null;
    const disposition = evalDisposition(s, closeState, s.operationGuard.isBusy({ ignoreCloseDialog: true }));
    if (disposition === 'busy') {
      await s.lifecycleService.CancelClose(requestId);
      s.patch({
        pausedByGuard: true,
        error: dirty ? 'Save or discard unsaved workbench edits before closing VPro.' : CLOSE_HOLD_NOTICE,
      });
    } else if (dirty) {
      await s.lifecycleService.CancelClose(requestId);
      s.patch({ error: 'Save or discard unsaved workbench edits before closing VPro.' });
    } else if (disposition === 'clean') {
      await s.lifecycleService.ConfirmClose(requestId);
    } else {
      s.patch({ closeError: '', closeRequest: requestId });
    }
  } catch (cause) {
    getRt().patch({ error: `Window close request failed: ${formatError(cause)}` });
  }
}

export async function runRespondToCloseOp(getRt: () => ShellRuntimeSnap, decision: CloseDecision): Promise<void> {
  const s0 = getRt();
  if (!s0.closeRequest || s0.closeWorking) return;
  const requestId = s0.closeRequest;
  s0.patch({ closeWorking: true, closeError: '' });
  try {
    if (decision === 'cancel') {
      await s0.lifecycleService.CancelClose(requestId);
      getRt().patch({ closeRequest: '' });
      return;
    }
    const s = getRt();
    const closeState = s.view === 'fs882' ? (s.editor?.getCloseState() ?? null) : null;
    if (evalDisposition(s, closeState, s.operationGuard.isBusy({ ignoreCloseDialog: true })) === 'busy') {
      s.patch({ closeError: CLOSE_HOLD_NOTICE });
      return;
    }
    const editor = s.editor;
    if (decision === 'save' && (!editor || !(await editor.saveForClose()))) {
      getRt().patch({
        closeError: editor?.getCloseState().error ?? 'The draft could not be saved. VPRO remains open.',
      });
      return;
    }
    await s.lifecycleService.ConfirmClose(requestId);
  } catch (cause) {
    getRt().patch({ closeError: `VPRO remains open: ${formatError(cause)}` });
  } finally {
    getRt().patch({ closeWorking: false });
  }
}

export async function runRequestTransitionOp(
  getRt: () => ShellRuntimeSnap,
  run: (contextId: string) => Promise<void>,
  ownedAction?: () => boolean
): Promise<void> {
  blurActiveDocumentElement();
  await getRt().tick();
  const s = getRt();
  if (ownedAction && !ownedAction()) {
    s.patch({ error: 'Owned action or editor availability changed; no editor replaced.' });
    return;
  }
  if (!ownedAction && s.operationGuard.hasDirtyWorkbench()) {
    s.patch({ error: 'Save or discard unsaved workbench edits before changing context or view.' });
    return;
  }
  const state = s.view === 'fs882' ? (s.editor?.getCloseState() ?? null) : null;
  if (
    evalDisposition(
      s,
      ownedAction ? null : state,
      s.operationGuard.isBusy({ ignoreOwnedEditor: Boolean(ownedAction) })
    ) === 'busy'
  ) {
    s.patch({ pausedByGuard: true, error: TRANSITION_HOLD_NOTICE, lastPushedError: TRANSITION_HOLD_NOTICE });
    s.notify.warning?.('Navigation paused', TRANSITION_HOLD_NOTICE, { toast: true, source: 'Workspace' });
    return;
  }
  const contextId = s.state?.contextId;
  if (!contextId) {
    s.patch({ error: 'A project context must finish loading before navigation.' });
    return;
  }
  s.patch({ transitionError: '' });
  if (state?.unsaved && !ownedAction) {
    s.patch({ pendingTransition: { contextId, run } });
    return;
  }
  try {
    await run(contextId);
  } catch (cause) {
    getRt().patch({ error: formatError(cause) });
  }
}

export async function runRespondToTransitionOp(getRt: () => ShellRuntimeSnap, decision: CloseDecision): Promise<void> {
  const s0 = getRt();
  if (!s0.pendingTransition || s0.transitionWorking) return;
  if (decision === 'cancel') {
    s0.patch({ pendingTransition: null, transitionError: '' });
    return;
  }
  const pending = s0.pendingTransition;
  s0.patch({ transitionWorking: true, transitionError: '' });
  try {
    const s = getRt();
    const editor = s.editor;
    const state = editor?.getCloseState();
    if (!state || evalDisposition(s, state, s.operationGuard.isBusy({ ignoreTransitionDialog: true })) === 'busy') {
      s.patch({ transitionError: 'Wait for the current editor operation to finish.' });
      return;
    }
    if (decision === 'save' && state.unsaved && !(await editor?.saveForClose())) {
      getRt().patch({
        transitionError:
          editor?.getCloseState().error ?? 'The draft could not be saved; context and draft remain open.',
      });
      return;
    }
    await pending.run(pending.contextId);
    getRt().patch({ pendingTransition: null });
  } catch (cause) {
    getRt().patch({ transitionError: `Context remains unchanged: ${formatError(cause)}` });
  } finally {
    getRt().patch({ transitionWorking: false });
  }
}

export function runNavigateOp(
  getRt: () => ShellRuntimeSnap,
  next: ShellViewId | 'fs882-twopage'
): Promise<void> | void {
  if (
    IS_WEB_READONLY &&
    (next === 'project-admin' || next === 'user-log' || (next === 'picture-manager' && get(webMeta)?.picturesAvailable === false))
  ) {
    return;
  }
  const s0 = getRt();
  if (!s0.standaloneMetadataPlot) {
    if (next === 'fs882-twopage' && s0.view === 'fs882' && s0.editorEntryForm === 'fs882-twopage') return;
    if (next === 'fs882' && s0.view === 'fs882' && s0.editorEntryForm === 'fs882') return;
    if (next === s0.view && next !== 'project-admin' && next !== 'fs882') return;
  }
  return s0.requestTransition(async () => {
    const s = getRt();
    const selPlot = s.selected?.plotNumber;
    if (next === 'project-admin' && s.ui) {
      s.ui.projectAdminTab = 'lifecycle';
      s.ui.projectAdminTabNonce++;
    }
    if (next === 'fs882-twopage' || next === 'fs882') {
      if (s.ui) s.ui.diagnosticsDraft = null;
      s.patch({
        error: '',
        standaloneMetadataPlot: '',
        view: 'fs882',
        editorPlotNumber: (s.view === 'fs882' ? s.editorPlotNumber : undefined) ?? selPlot,
        hasEditorPlotNumber: true,
        editorEntryForm: next === 'fs882-twopage' ? 'fs882-twopage' : 'fs882',
      });
      return;
    }
    if (next === 'picture-manager' && s.ui) s.ui.pictureManagerPlot = selPlot ?? '';
    if (next === 'plot-label-preview' && s.ui) {
      s.ui.plotLabelNumber = (s.view === 'fs882' ? s.editorPlotNumber : selPlot) ?? '';
    }
    s.patch({ error: '', standaloneMetadataPlot: '', view: next });
  });
}

export async function runOpenSIVIOp(getRt: () => ShellRuntimeSnap): Promise<void> {
  const s0 = getRt();
  if (!s0.selected || !s0.state?.contextId) {
    s0.patch({ error: 'Select a plot in the active project before opening SIVI / FS1333.' });
    return;
  }
  const plot = s0.selected.plotNumber;
  await s0.requestTransition(async () => {
    const s = getRt();
    if (s.selected?.plotNumber !== plot) {
      throw new Error('Selected plot changed before opening SIVI; no owner replaced.');
    }
    if (s.ui) s.ui.diagnosticsDraft = null;
    s.patch({
      editorPlotNumber: plot,
      hasEditorPlotNumber: true,
      editorEntryForm: 'sivi',
      view: 'fs882',
      error: '',
    });
  });
}

export async function runOpenProjectMetadataOp(getRt: () => ShellRuntimeSnap): Promise<void> {
  const s0 = getRt();
  const inPlotEditor = s0.view === 'fs882' && !(s0.editorEntryForm === 'fs882-twopage' && !s0.editorPlotNumber);
  if (inPlotEditor) {
    const owner = s0.editor;
    const contextId = s0.state?.contextId;
    if (!owner || !contextId || !owner.canOpenProjectMetadata()) {
      s0.patch({ error: 'Project metadata requires a clean, unlocked open plot; finish or Undo drafts first.' });
      return;
    }
    const ownedAction = owner.canOpenMetadataInPlace?.()
      ? () => {
          const s = getRt();
          return (
            s.view === 'fs882' &&
            s.editor === owner &&
            s.state?.contextId === contextId &&
            owner.canOpenMetadataInPlace?.() === true
          );
        }
      : undefined;
    await s0.requestTransition(async (currentContext) => {
      const s = getRt();
      if (
        s.view !== 'fs882' ||
        s.editor !== owner ||
        currentContext !== contextId ||
        s.state?.contextId !== contextId ||
        !owner.canOpenProjectMetadata()
      ) {
        throw new Error('Project metadata owner or availability changed; no editor replaced.');
      }
      owner.openProjectMetadata();
    }, ownedAction);
    return;
  }
  const contextId = s0.state?.contextId;
  if (!contextId) {
    s0.patch({ error: 'Open a project before reviewing project metadata.' });
    return;
  }
  await s0.requestTransition(async (currentContext) => {
    const s = getRt();
    if (currentContext !== contextId || s.state?.contextId !== contextId) {
      throw new Error('Project metadata owner or availability changed; no editor replaced.');
    }
    let targetPlot = s.selected?.plotNumber || (s.allAvailablePlots ?? [])[0]?.plotNumber || '';
    if (!targetPlot && typeof s.contextService?.ListPlots === 'function') {
      const call = s.contextService.ListPlots(0, 1);
      const firstPage = s.plotReads ? await s.plotReads.track(call) : await call;
      if (getRt().state?.contextId !== contextId) return;
      targetPlot = firstPage?.plots?.[0]?.plotNumber ?? '';
    }
    if (!targetPlot) {
      const latest = getRt();
      if (IS_WEB_READONLY) {
        latest.patch({
          standaloneMetadataPlot: '',
          error: 'No plots were found in the active dataset to inspect project metadata.',
        });
        return;
      }
      if (latest.ui) {
        latest.ui.projectAdminTab = 'lifecycle';
        latest.ui.projectAdminTabNonce++;
      }
      latest.patch({ standaloneMetadataPlot: '', view: 'project-admin', error: '' });
      return;
    }
    getRt().patch({ standaloneMetadataPlot: targetPlot, error: '' });
  });
}

export async function runFindScopedPlotOp(getRt: () => ShellRuntimeSnap): Promise<void> {
  const s0 = getRt();
  const contextId = s0.state?.contextId;
  if (!contextId || s0.operationGuard.isBusy()) {
    if (contextId) s0.patch({ pausedByGuard: true, error: PAGING_HOLD_NOTICE });
    return;
  }
  s0.patch({ busy: true, plotFindError: '', plotFindResult: null });
  try {
    await s0.tick();
    const s = getRt();
    const result = await lookupScopedPlotOp({
      number: s.plotFindQuery,
      contextId,
      profileNavigation: s.profileNavigation,
      plotReads: s.plotReads,
      stateReads: s.stateReads,
      getCurrentContextId: () => getRt().state?.contextId,
      contextService: s.contextService,
    });
    getRt().patch({ plotFindResult: result });
  } catch (cause) {
    getRt().patch({ plotFindError: `Could not find plot: ${formatError(cause)}` });
  } finally {
    getRt().patch({ busy: false });
  }
}

export async function runLoadPlotsPageOp(getRt: () => ShellRuntimeSnap, nextOffset: number): Promise<void> {
  const s0 = getRt();
  if (s0.operationGuard.isBusy({ ignoreShellBusy: true })) {
    s0.patch({ pausedByGuard: true, error: PAGING_HOLD_NOTICE });
    return;
  }
  const current = s0.nextPlotRequest();
  s0.plotReads.cancelAll();
  s0.patch({ busy: true, error: '' });
  try {
    let next: ProfileNavigation | null = null;
    if (s0.profileNavigation) {
      if (s0.ui?.resolveNavigation) {
        next = await s0.ui.resolveNavigation(s0.profileNavigation.proposal, s0.profileNavigation.contextId);
      } else {
        const raw = await s0.plotReads.track(
          s0.contextService.ResolveProjectPlotProfileNavigation(
            s0.profileNavigation.contextId,
            s0.profileNavigation.proposal
          )
        );
        next = validateProfileNavigation(raw, s0.profileNavigation.proposal, s0.profileNavigation.contextId);
      }
    }
    const result: PlotPage = next
      ? profileNavigationPage(next, next.contextId, nextOffset, s0.pageSize)
      : await s0.plotReads.track(s0.contextService.ListPlots(nextOffset, s0.pageSize));
    if (!getRt().isCurrentPlotRequest(current)) return;
    getRt().patch({ ...(next ? { profileNavigation: next } : {}), page: result, offset: nextOffset, selected: null });
  } catch (cause) {
    if (getRt().isCurrentPlotRequest(current)) getRt().patch({ error: formatError(cause) });
  } finally {
    if (getRt().isCurrentPlotRequest(current)) getRt().patch({ busy: false });
  }
}

export async function runRefreshWorkspaceOp(getRt: () => ShellRuntimeSnap): Promise<void> {
  const s0 = getRt();
  if (s0.operationGuard.isBusy({ ignoreShellBusy: true })) {
    s0.patch({ pausedByGuard: true, error: PAGING_HOLD_NOTICE });
    return;
  }
  const current = s0.nextStateRequest();
  s0.stateReads.cancelAll();
  s0.patch({ busy: true, error: '' });
  try {
    const startup = await s0.stateReads.track(s0.lifecycleService.GetStartupState());
    if (!getRt().isCurrentStateRequest(current)) return;
    if (getRt().ui) getRt().ui!.startupInfo = startup;
    if (!startup.ready) {
      getRt().patch({ startupFailure: startup, busy: false });
      return;
    }
    const state = await s0.stateReads.track(s0.contextService.GetState());
    if (!getRt().isCurrentStateRequest(current)) return;
    const latest = getRt();
    latest.patch({
      startupFailure: null,
      ...(latest.profileNavigation && latest.profileNavigation.contextId !== state.contextId
        ? { profileNavigation: null }
        : {}),
    });
    projectState.set(state);
    if (IS_WEB_READONLY) {
      await applyInitialWebUrlStateOp(getRt, state, current);
      if (!getRt().isCurrentStateRequest(current)) return;
    }
    await getRt().loadPlots(0);
    if (getRt().isCurrentStateRequest(current)) await getRt().loadHierarchy();
  } catch (cause) {
    if (getRt().isCurrentStateRequest(current)) getRt().patch({ error: formatError(cause), busy: false });
  }
}

export async function runLoadHierarchyOp(getRt: () => ShellRuntimeSnap): Promise<void> {
  const s0 = getRt();
  if (s0.operationGuard.isBusy({ ignoreShellBusy: true })) {
    s0.patch({ pausedByGuard: true, error: PAGING_HOLD_NOTICE });
    return;
  }
  const current = s0.nextHierarchyRequest();
  s0.hierarchyReads.cancelAll();
  const nodes = await s0.hierarchyReads.track(s0.contextService.GetHierarchyNodes());
  if (getRt().isCurrentHierarchyRequest(current)) getRt().patch({ hierarchyNodes: nodes ?? [] });
}

export async function runSwitchContextOp(
  getRt: () => ShellRuntimeSnap,
  contextId: string,
  selection: ContextSelection,
  next: 'plots' | 'hierarchy'
): Promise<void> {
  const s0 = getRt();
  s0.cancelAllReads();
  s0.patch({ busy: true, error: '' });
  try {
    const state = await s0.contextService.SwitchContext(contextId, selection);
    if (state.contextId !== contextId) onContextDisposed(contextId);
    projectState.set(state);
    const s = getRt();
    s.nextPlotRequest();
    s.resetMainCaches();
    s.patch({ view: next });
    await s.loadPlots(0);
    if (next === 'hierarchy') {
      try {
        await s.loadHierarchy();
      } catch (cause) {
        getRt().patch({ error: `Context changed, but hierarchy refresh failed: ${formatError(cause)}` });
      }
    }
    if (typeof window !== 'undefined' && window.innerWidth < 1200 && s.ui) s.ui.contextExpanded = false;
  } catch (cause) {
    const msg = formatError(cause);
    getRt().patch({ lastPushedError: msg, error: msg });
    s0.notify.push({
      severity: 'error',
      category: 'general',
      source: 'Context Switch',
      title: 'Could not switch project context',
      message: msg,
      toast: true,
    });
    throw new Error(msg);
  } finally {
    getRt().patch({ busy: false });
  }
}

export function runGlobalHelpKeydownOp(getRt: () => ShellRuntimeSnap, event: KeyboardEvent): void {
  const s = getRt();
  if (s.startupFailure !== null || !s.ui) return;
  if ((event.ctrlKey || event.metaKey) && typeof event.key === 'string' && event.key.toLowerCase() === 'k') {
    event.preventDefault();
    s.ui.commandPaletteOpen = !s.ui.commandPaletteOpen;
    return;
  }
  const activeEl = typeof document !== 'undefined' ? (document.activeElement as HTMLElement | null) : null;
  const action = classifyGlobalHelpShortcut(event, activeEl);
  if (action === 'f1') {
    event.preventDefault();
    s.ui.openContextualHelp();
    return;
  }
  if (action === 'shortcuts') {
    event.preventDefault();
    s.ui.shortcutsModalOpen = !s.ui.shortcutsModalOpen;
    return;
  }
  if (event.key === 'Escape' && !s.ui.hasBlockingModalOpen() && !s.closeRequest && !s.pendingTransition) {
    if (s.ui.helpDrawerOpen) {
      event.preventDefault();
      s.ui.helpDrawerOpen = false;
      return;
    }
    if (s.ui.isNarrowViewport && s.ui.contextExpanded) {
      event.preventDefault();
      s.ui.contextExpanded = false;
    }
  }
}

let initialWebUrlApplied = false;

export function resetInitialWebUrlAppliedForTest(): void {
  initialWebUrlApplied = false;
}

export async function applyInitialWebUrlStateOp(
  getRt: () => ShellRuntimeSnap,
  state: ProjectState,
  stateReqId: number
): Promise<void> {
  if (initialWebUrlApplied || typeof window === 'undefined' || !window.location?.search) return;
  initialWebUrlApplied = true;
  const runtime = get(webShellRuntime) ?? (await (await import('../web/webMeta')).bootstrapWebShellRuntime());
  const picturesAvailable = get(webMeta)?.picturesAvailable ?? true;
  const plan = runtime.planInitialUrl(window.location.search, state, picturesAvailable);
  if (plan.switchSelection && state.contextId) {
    try {
      const switched = await getRt().stateReads.track(
        getRt().contextService.SwitchContext(state.contextId, plan.switchSelection)
      );
      if (!getRt().isCurrentStateRequest(stateReqId)) return;
      projectState.set(switched);
    } catch {
      // Keep default server context when URL parameters refer to an unknown dataset/SU/hierarchy.
    }
  }
  const patch: ShellStatePatch = {};
  if (plan.plotNumber) {
    patch.editorPlotNumber = plan.plotNumber;
    patch.hasEditorPlotNumber = true;
  }
  if (plan.view) patch.view = plan.view as ShellViewId;
  if (plan.editorEntryForm) patch.editorEntryForm = plan.editorEntryForm;
  if (Object.keys(patch).length > 0) getRt().patch(patch);
}

export function syncShellWebUrlOp(params: {
  state: ProjectState | null;
  view: ShellViewId;
  editorEntryForm: 'fs882' | 'sivi' | 'fs882-twopage';
  plotNumber?: string;
}): void {
  if (!IS_WEB_READONLY || !params.state?.activeProject) return;
  const urlView =
    params.view === 'fs882' && params.editorEntryForm === 'fs882-twopage' ? 'fs882-twopage' : params.view;
  get(webShellRuntime)?.syncUrl({
    dataset: params.state.activeProject,
    su: params.state.activeSU,
    hierarchy: params.state.activeHierarchy,
    view: urlView,
    plot: params.plotNumber,
  });
}

export type { HierarchyNode };
