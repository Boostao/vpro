import {
  ContextService,
  PlotEntryService,
  type FS882Header,
  type ProjectPlotProfileFilterRequest,
} from '../../bindings/github.com/boostao/vpro/app';
import type { EditLockState, PlotBundle } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
import type { projectState } from '../shared/state';
import {
  resolveVisibleCards,
  type ClassicCardId,
  type ClassicLayoutMode,
} from './classicFS882Helpers';

type ProjectStateValue = Parameters<Parameters<typeof projectState.subscribe>[0]>[0];
import { onDestroy, tick, untrack } from 'svelte';
import {
  externalSUEnvironmentSession,
  subscribeExternalSUEnvironmentActivity,
} from '../classification/externalSUEnvironment';
import { bindContextPlots } from '../shared/contextPlots';
import { formatError, ReadRequests } from '../shared/readRequests';
import { notifications } from '../shell/notificationService.svelte';
import { IS_WEB_READONLY } from '../web/runtimeMode';
import type { AvailablePlotOption } from './FS882TwoPagePlotPrompt.svelte';
import { navigateSourceEnter } from './enterNavigation';
import {
  getCachedContextCapabilities,
  getCachedContextValue,
  getCachedPlotBundle,
  invalidatePlotBundle,
  invalidateProjectIdChoices,
  invalidateSpeciesLists,
  invalidateWorkingUnitChoices,
  peekPlotBundle,
  prefetchPlotBundle,
  setCachedContextCapabilities,
  type CachedContextCapabilities,
} from './entryReferenceCache';
import { buildFieldCardViewModel } from './fieldCardPreview';
import { buildFormValidationItems, focusValidationTarget, type FormValidationItem } from './formValidationSummary';
import { mergeSoilDraftRows } from './fs882FormChildren';
import { firstMatch, newEmptyFS882Draft, toRecord } from './fs882FormHelpers';
import {
  applyDiagnosticHumusThicknessImpl,
  computeFS882SubEditorCloseOverride,
  computeHeaderValidationError,
  computeSaveReason,
  isNonArcticHeaderDirty,
  resolveRetainedExternalSU,
} from './fs882FormLoadSave';
import {
  disposeTwoPageSessionCaches,
  observeProjectIdDatalist,
  refreshTwoPagePeersImpl,
  type EditorCloseState,
  type TwoPageEntrySessionCache,
  type TwoPageParentCommonSessionCache,
  type TwoPageParentForm,
  type TwoPageParentSessionCache,
} from './fs882FormSivi';
import { ordinaryNumberValue, ordinaryTextError } from './ordinaryEditor';
import type { VegetationMode } from './paperLayout';
import { subscribeTwoPageSoilActivity } from './twoPageSoilActivity';
import { subscribeTwoPageVegetationActivity, twoPageVegetationActivity } from './twoPageVegetationActivity';
import type { TwoPageVegetationForm } from './twoPageVegetationWire';
import { createFS882ChildWorkflows } from './useFS882ChildWorkflows.svelte';
import { createSiviSessions } from './useSiviSessions.svelte';
import type { WorkingUnitSession } from './workingUnitEditor';

export type FS882TabId = 'site' | 'soils' | 'veg' | 'mensuration' | 'vegOther' | 'other' | 'audit' | 'siviParent';

export interface FS882DiagnosticsState {
  plotNumber: string;
  header: Record<string, unknown> | null;
  humus: Record<string, unknown>[];
  mineral: Record<string, unknown>[];
}

export interface FS882FormBaseProps {
  plotNumber?: string;
  neighborPlots?: string[];
  contextId: string;
  onSaved?: (p: string) => void | Promise<void>;
  onClosed?: () => void;
  onBusyChange?: (busy: boolean) => void;
  onFindPlot?: () => void;
  onSelectPlot?: (plotNumber: string) => void;
  onNewPlot?: () => void;
  onProfileNavigation?: (proposal: ProjectPlotProfileFilterRequest, contextId: string) => Promise<void>;
  onProfileSUReview?: (proposal: ProjectPlotProfileFilterRequest, contextId: string) => Promise<void>;
  availablePlots?: AvailablePlotOption[];
  onSelectPlotForTwoPage?: (plotNumber: string) => void;
  onSwitchTo6x4NewPlot?: () => void;
  canUndoPlotDelete?: boolean;
  onCopyPlotToNumber?: (sourcePlot: string, targetPlot: string) => Promise<void>;
  onRemovePlotAction?: (sourcePlot: string, cleanProjectName: string) => Promise<void>;
}

export interface FS882ControllerDeps {
  contextId: string;
  getEntryForm: () => 'fs882' | 'sivi' | 'fs882-twopage';
  getPlotNumber: () => string | undefined;
  getNeighborPlots?: () => string[];
  getProjectState: () => ProjectStateValue;
  setSuccess: (msg: string | null, markNotified?: boolean) => void;
  onSaved?: (p: string) => void | Promise<void>;
  onBusyChange?: (busy: boolean) => void;
  onDiagnosticsContextChange?: (state: FS882DiagnosticsState) => void;
}

const FS882_TABS: readonly { id: FS882TabId; label: string; helpId?: string; sivi?: boolean; card?: boolean }[] = [
  { id: 'site', label: 'Card 1: Site', helpId: 'site.moisture_regime', card: true },
  { id: 'soils', label: 'Card 2: Soil', helpId: 'humus.upper_lower_depth', card: true },
  { id: 'veg', label: 'Card 3: Vegetation', helpId: 'veg.covers', card: true },
  { id: 'mensuration', label: 'Card 4: Mensuration', card: true },
  { id: 'vegOther', label: 'Veg Other', helpId: 'veg.species' },
  { id: 'other', label: 'Other Data' },
  { id: 'audit', label: 'Audit Trail' },
];

const SIVI_TABS: readonly { id: FS882TabId; label: string; helpId?: string; sivi?: boolean }[] = [
  { id: 'siviParent', label: 'Plot & Site Description', helpId: 'sivi.plot_type', sivi: true },
  { id: 'veg', label: 'Vegetation', helpId: 'veg.covers' },
];

export function createFS882Controller(deps: FS882ControllerDeps) {
  const siviContextId = untrack(() => deps.contextId);
  const PlotService = { ...PlotEntryService, ...bindContextPlots(siviContextId) };
  const siviStandalone = untrack(() => deps.getEntryForm() === 'sivi');
  const standaloneTwoPage = $derived(deps.getEntryForm() === 'fs882-twopage');
  const reads = new ReadRequests();
  const workingUnitSession: WorkingUnitSession & { plot: string } = { mode: null, plot: '' };

  let activeTab = $state<FS882TabId>('site');
  let layoutMode = $state<ClassicLayoutMode>('single');
  let splitLeftCard = $state<ClassicCardId>('site');
  let splitRightCard = $state<ClassicCardId>('soils');
  let editLock = $state<EditLockState | null>(
    IS_WEB_READONLY
      ? {
          locked: true,
          reason: 'Web viewer is read-only.',
          signedIn: false,
          userId: '',
          displayName: '',
          role: '',
          identityProvider: '',
          canEditCurrentProject: false,
          isBecMasterProject: false,
          oidcConfigured: false,
          devFallbackAvailable: false,
        }
      : null
  );
  let editLockRequest = 0;
  let fieldCardModalOpen = $state(false),
    fieldCardSplitOpen = $state(false);
  let vegetationMode = $state<VegetationMode>('initial');
  let extendedShrubs = $state(false),
    managePlotOpen = $state(false);
  let busy = $state(false),
    coordinateBusy = $state(false),
    workingUnitBusy = $state(false),
    qualityBusy = $state(false);
  let siteCodeBusy = $state(false),
    regionCodeBusy = $state(false),
    soilCodeBusy = $state(false),
    geologyCodeBusy = $state(false);
  let parentCodeBusy = $state(false),
    drainageBusy = $state(false);
  let codeCheckOpen = $state(false),
    codeCheckBusy = $state(false);
  let codeCheckEditor = $state<{ getCloseState(): EditorCloseState; undo(): void }>();
  let metadataOpen = $state(false),
    metadataBusy = $state(false),
    pictureBusy = $state(false);
  let twoPageOpen = $state(false),
    twoPageScope = $state<'extra' | 'common' | 'entry'>('extra');
  let twoPageEntryInitialForm = $state<TwoPageParentForm>('FS882-8x6XL'),
    twoPageBusy = $state(false);
  let twoPageProject = $state<string | null>(null),
    twoPageRevision = $state(0);
  const twoPageSessions: TwoPageParentSessionCache = new Map();
  const twoPageCommonSessions: TwoPageParentCommonSessionCache = new Map();
  const twoPageEntrySessions: TwoPageEntrySessionCache = new Map();
  let twoPageEditor = $state<{
    getCloseState(): EditorCloseState;
    getDraftState?(): EditorCloseState;
    undo(): void;
    saveForClose?(): Promise<boolean>;
    canOpenMetadataEditor?(): boolean;
    openMetadataEditor?(): void;
  }>();
  let twoPageSoilBusy = $state(false),
    twoPageSoilBlocked = $state(false);
  let twoPageVegetationBusy = $state(false),
    twoPageVegetationBlocked = $state(false);
  let twoPageVegetationActivityRevision = $state(0);
  let environmentSUOpen = $state(false),
    environmentSUDirection = $state<'forward' | 'reverse' | 'external-reverse'>('forward');
  let environmentSUEditor = $state<{ getCloseState(): EditorCloseState; undo(): void }>();
  let externalSUEnvironmentBusy = $state(false),
    externalSUEnvironmentBlocked = $state(false);
  let profileReviewOpen = $state(false),
    profileReviewBusy = $state(false),
    profileReviewBlocked = $state(false);
  let profileEditor = $state<{ getCloseState(): EditorCloseState; undo(): void }>();
  let metadataEditor = $state<{ getCloseState(): EditorCloseState; undo(): void }>();
  let error = $state<string | null>(null),
    dirty = $state(false),
    mensurationDirty = $state(false),
    mensurationBusy = $state(false),
    headerValidation = $state<Record<string, string>>({});
  let capabilities = $state<Record<string, boolean | undefined>>({}),
    capabilitiesReady = $state(false),
    masterAllowed = $state(false);
  let loadRequest = 0,
    container = $state<HTMLDivElement>(),
    subEditorGeneration = 0,
    headerRevision = $state(0);
  let prefetchGeneration = 0;
  let prefetchTimer: ReturnType<typeof setTimeout> | null = null;
  let lastSiviProjectSource: string | null = null;
  let draft = $state<FS882Header>(newEmptyFS882Draft()),
    original = $state<FS882Header | null>(null);
  let activeLayerDepthRaw = $state<string | null>(null),
    projectIdDatalist = $state<string[]>([]);

  function cancelNeighborPrefetch() {
    prefetchGeneration += 1;
    if (prefetchTimer !== null) {
      clearTimeout(prefetchTimer);
      prefetchTimer = null;
    }
  }

  function scheduleNeighborPrefetch(currentPlot: string) {
    const getPlotBundle = PlotService.GetPlotBundle;
    if (typeof getPlotBundle !== 'function' || !siviContextId) return;
    cancelNeighborPrefetch();
    const gen = prefetchGeneration;
    const neighbors = (deps.getNeighborPlots?.() ?? []).filter((n) => Boolean(n && n !== currentPlot));
    if (neighbors.length === 0) return;
    prefetchTimer = setTimeout(() => {
      prefetchTimer = null;
      if (gen !== prefetchGeneration) return;
      for (const neighbor of neighbors) {
        if (gen !== prefetchGeneration) return;
        void prefetchPlotBundle<PlotBundle>(siviContextId, neighbor, async () => {
          const res = await getPlotBundle(neighbor, false);
          if (!res || !res.header) throw new Error(`Plot ${neighbor} could not be prefetched.`);
          return res;
        });
      }
    }, 0);
  }

  const children = createFS882ChildWorkflows({
    contextId: siviContextId,
    plotService: PlotService,
    reads,
    getLoadRequest: () => loadRequest,
    getDraft: () => draft,
    getOriginal: () => original,
    getBusy: () => busy,
    setBusy: (b) => {
      busy = b;
    },
    getDirty: () => dirty,
    getCapabilitiesReady: () => capabilitiesReady,
    invalidateCapabilities: () => {
      capabilitiesReady = false;
    },
    getHeaderWorkflowBusy: () => headerWorkflowBusy,
    getChildParentDisabled: () => childParentDisabled,
    getSiviChildUnsaved: () => sivi.anyChildUnsaved,
    getChildUnsaved: () => childUnsaved,
    getCurrentError: () => error,
    setError: (e) => {
      error = e;
    },
    appendError: (s) => {
      error = (error ?? '') + s;
    },
    setSuccess: (s) => deps.setSuccess(s, false),
    isAuditTabActive: () => activeTab === 'audit',
    onChildWrite: () => cancelNeighborPrefetch(),
  });

  const sivi = createSiviSessions({
    contextId: siviContextId,
    reads,
    getActiveContextId: () => deps.getProjectState()?.contextId,
    getActiveProject: () => deps.getProjectState()?.activeProject,
    getOriginal: () => original,
    getDraftLocked: () => draft.locked,
    getBusy: () => busy,
    getDirty: () => dirty,
    getNonArcticHeaderDirty: () => nonArcticHeaderDirty,
    getCapabilitiesReady: () => capabilitiesReady,
    getHeaderValidationCount: () => Object.keys(headerValidation).length,
    getOtherHeaderWorkflowBusy: () => otherHeaderWorkflowBusy,
    getHeaderWorkflowBusy: () => headerWorkflowBusy,
    getPictureBusy: () => pictureBusy,
    getChildParentDisabled: () => childParentDisabled,
    getOrdinaryChildPeerUnsaved: () => children.anyOrdinaryUnsaved,
    getHasPersonalDraft: () => children.personalDraft !== null,
    getSiviCreationPeerUnsaved: () => siviCreationPeerUnsaved,
    getNonParentChildUnsaved: () => nonParentChildUnsaved,
    getChildUnsaved: () => childUnsaved,
    getCurrentError: () => error,
    setError: (e) => {
      error = e;
    },
    setSuccess: (s) => deps.setSuccess(s, false),
    invalidateCapabilities: () => {
      capabilitiesReady = false;
    },
    onShowParentTab: () => {
      activeTab = 'siviParent';
    },
    loadChildData: (p) => {
      cancelNeighborPrefetch();
      invalidatePlotBundle(siviContextId, p);
      return children.loadChildData(p);
    },
    applyRefreshedHeader: (header) => {
      cancelNeighborPrefetch();
      invalidatePlotBundle(siviContextId, header.plotNumber);
      if ((original?.userSiteUnit ?? null) !== (header.userSiteUnit ?? null)) {
        invalidateWorkingUnitChoices(siviContextId, 'env');
      }
      if ((original?.projectId ?? null) !== (header.projectId ?? null)) {
        invalidateProjectIdChoices(siviContextId);
      }
      draft = { ...header };
      original = structuredClone(header);
      activeLayerDepthRaw = null;
      dirty = false;
      headerValidation = {};
    },
  });

  function setExtendedShrubs(next: boolean) {
    extendedShrubs = next;
    sivi.setPresentation(next);
    if (next) vegetationMode = 'cover';
  }

  const pState = $derived(deps.getProjectState());
  const visibleTabs = $derived(
    (siviStandalone ? SIVI_TABS : FS882_TABS).filter((tab) => !IS_WEB_READONLY || tab.id !== 'audit')
  );
  const separateSUSelected = $derived(
    Boolean(pState?.activeSU && pState.activeSU !== 'None' && pState.suPath && pState.suPath !== pState.projectPath)
  );
  const independentHeaderWorkflowBusy = $derived(
    coordinateBusy ||
      workingUnitBusy ||
      qualityBusy ||
      siteCodeBusy ||
      regionCodeBusy ||
      soilCodeBusy ||
      geologyCodeBusy ||
      parentCodeBusy ||
      drainageBusy ||
      children.anyBusy ||
      codeCheckBusy ||
      metadataBusy ||
      profileReviewBusy ||
      environmentSUOpen ||
      externalSUEnvironmentBusy ||
      externalSUEnvironmentBlocked ||
      sivi.anyBusy ||
      mensurationBusy
  );
  const otherHeaderWorkflowBusy = $derived(independentHeaderWorkflowBusy || twoPageOpen || twoPageBusy);
  const headerWorkflowBusy = $derived(
    otherHeaderWorkflowBusy ||
      pictureBusy ||
      sivi.pictureMetadataPending ||
      twoPageSoilBusy ||
      twoPageSoilBlocked ||
      twoPageVegetationBusy ||
      twoPageVegetationBlocked
  );
  const hostEditorBusy = $derived(
    busy ||
      sivi.sourceAuthorityUnknown ||
      independentHeaderWorkflowBusy ||
      twoPageBusy ||
      pictureBusy ||
      (sivi.pictureMetadataClose?.busy ?? false) ||
      (sivi.pictureMetadataClose?.blocked ?? false) ||
      twoPageSoilBusy ||
      twoPageSoilBlocked ||
      twoPageVegetationBusy ||
      twoPageVegetationBlocked ||
      (twoPageOpen && !twoPageEditor) ||
      (environmentSUOpen && (!environmentSUEditor || environmentSUEditor.getCloseState().busy)) ||
      (metadataOpen && !metadataEditor) ||
      (codeCheckOpen && !codeCheckEditor)
  );
  const tabWorkflowBusy = $derived(
    otherHeaderWorkflowBusy || pictureBusy || (sivi.pictureMetadataClose?.busy ?? false)
  );
  const siviCreationPeerUnsaved = $derived(
    sivi.anyChildUnsaved ||
      children.anyDraftOrReviewUnsaved ||
      codeCheckOpen ||
      metadataOpen ||
      profileReviewBlocked ||
      environmentSUOpen
  );
  const nonParentChildUnsaved = $derived(siviCreationPeerUnsaved || sivi.anyLifecyclePending);
  const childUnsaved = $derived(
    nonParentChildUnsaved ||
      sivi.anyParentUnsaved ||
      twoPageOpen ||
      twoPageSoilBusy ||
      twoPageSoilBlocked ||
      twoPageVegetationBusy ||
      twoPageVegetationBlocked ||
      mensurationDirty
  );
  const sourceHeaderValues = $derived(new Map(Object.entries(draft).map(([key, value]) => [key.toLowerCase(), value])));
  const snowCoverRegimeInput = $derived(draft.snowCoverRegime ?? '');
  const activeLayerDepthInput = $derived(
    activeLayerDepthRaw ?? (draft.activeLayerDepth == null ? '' : String(draft.activeLayerDepth))
  );
  const authEditLocked = $derived(IS_WEB_READONLY || Boolean(editLock?.locked));
  const visibleCards = $derived(resolveVisibleCards(layoutMode, activeTab, splitLeftCard, splitRightCard));
  const arcticInputsDisabled = $derived(
    IS_WEB_READONLY ||
      authEditLocked ||
      draft.locked ||
      busy ||
      sivi.sourceBarrier ||
      !capabilitiesReady ||
      nonParentChildUnsaved ||
      sivi.parentWriteUnsaved ||
      sivi.parentActionUnsaved ||
      sivi.projectAssignmentUnsaved ||
      twoPageOpen ||
      twoPageSoilBusy ||
      twoPageSoilBlocked ||
      twoPageVegetationBusy ||
      twoPageVegetationBlocked ||
      pictureBusy ||
      sivi.pictureMetadataPending
  );
  const headerInputsDisabled = $derived(
    IS_WEB_READONLY ||
      authEditLocked ||
      draft.locked ||
      busy ||
      sivi.sourceBarrier ||
      !capabilitiesReady ||
      childUnsaved ||
      pictureBusy ||
      sivi.pictureMetadataPending
  );
  const nonArcticHeaderDirty = $derived(isNonArcticHeaderDirty(dirty, draft, original));
  const twoPageLinkedParentBlocked = $derived.by(() => {
    void twoPageRevision;
    const parent = twoPageEditor?.getDraftState?.();
    return (
      !twoPageOpen ||
      twoPageScope !== 'entry' ||
      !parent ||
      parent.unsaved ||
      parent.busy ||
      Boolean(parent.blocked) ||
      authEditLocked ||
      draft.locked ||
      busy ||
      dirty ||
      !capabilitiesReady ||
      !original ||
      sivi.sourceBarrier ||
      independentHeaderWorkflowBusy ||
      pictureBusy ||
      sivi.pictureMetadataPending ||
      nonParentChildUnsaved ||
      sivi.anyParentUnsaved ||
      children.personalDraft !== null
    );
  });
  const twoPageSoilParentBlocked = $derived(
    twoPageLinkedParentBlocked || twoPageVegetationBusy || twoPageVegetationBlocked
  );
  const twoPageVegetationParentBlocked = $derived(twoPageLinkedParentBlocked || twoPageSoilBusy || twoPageSoilBlocked);
  const childParentDisabled = $derived(
    !capabilitiesReady ||
      authEditLocked ||
      draft.locked ||
      busy ||
      headerWorkflowBusy ||
      sivi.sourceBarrier ||
      dirty ||
      sivi.anyParentUnsaved ||
      original === null ||
      children.deletionReview !== null ||
      children.creationDraft !== null ||
      children.personalDraft !== null ||
      codeCheckOpen ||
      metadataOpen ||
      profileReviewBlocked ||
      sivi.anyLifecyclePending
  );
  const auditGateReason = $derived(
    busy || headerWorkflowBusy || !capabilitiesReady
      ? 'Wait for the plot to finish loading or header workflow.'
      : authEditLocked
        ? (editLock?.reason || 'Data is locked (read-only). Sign in from Work Space to edit.')
        : draft.locked
          ? 'Unlock the plot before restoring fields.'
        : dirty || Object.keys(headerValidation).length > 0
          ? 'Save valid header changes or Undo before restoring fields.'
          : 'Save the plot before restoring fields.'
  );
  const validationSummaryItems = $derived(
    buildFormValidationItems({
      siviStandalone,
      headerValidation,
      soilInvalid: children.soilInvalid,
      speciesInvalid: children.speciesInvalid,
      heightInvalid: children.heightInvalid,
      creationInvalid: children.creationInvalid,
      personalInvalid: children.personalInvalid,
      attributeInvalid: children.attributeInvalid,
      otherInvalid: children.otherInvalid,
    })
  );
  const fieldCardViewModel = $derived.by(() => {
    if (!fieldCardModalOpen && !fieldCardSplitOpen) return null;
    return buildFieldCardViewModel({
      formKind: siviStandalone ? 'sivi' : 'fs882',
      committedHeader: original ? toRecord(original) : null,
      draftHeader: toRecord(draft),
      siviParentOriginal:
        sivi.parentSharedView?.original ??
        sivi.parentWriteView?.original ??
        sivi.parentActionView?.original ??
        sivi.parentView?.original ??
        null,
      siviSharedDrafts: sivi.parentSharedView?.drafts,
      siviDirectDrafts: sivi.parentWriteView?.drafts,
      siviActionDrafts: sivi.parentActionView?.drafts,
      humusRows: children.humusList.map(toRecord),
      mineralRows: children.mineralList.map(toRecord),
      soilDrafts: children.soilDrafts,
      vegRows: children.vegList.map(toRecord),
      heightDrafts: children.heightDrafts,
      speciesDrafts: children.speciesDrafts,
      collectedDrafts: children.collectedDrafts,
      creationDraft: children.creationDraft,
      extendedShrubs,
      snowCoverRegimeRaw: snowCoverRegimeInput,
      activeLayerDepthRaw: activeLayerDepthInput,
      isDirty: dirty || childUnsaved || Object.keys(headerValidation).length > 0,
    });
  });
  const effectiveFormDirty = $derived.by(() => {
    void twoPageRevision;
    return twoPageOpen
      ? Boolean(
          twoPageEditor?.getDraftState?.().unsaved ||
          twoPageSoilBlocked ||
          twoPageVegetationBlocked ||
          sivi.pictureMetadataPending ||
          mensurationDirty
        )
      : dirty || childUnsaved || mensurationDirty;
  });
  const isHeaderConflict = $derived(
    Boolean(
      error &&
      original &&
      (error.includes('plot changed since it was loaded') || error.includes('no longer exists; reload before saving'))
    )
  );

  $effect(() =>
    subscribeTwoPageSoilActivity((a) => {
      twoPageSoilBusy = a.busy;
      twoPageSoilBlocked = a.blocked;
    })
  );
  $effect(() =>
    subscribeTwoPageVegetationActivity((a) => {
      twoPageVegetationBusy = a.busy;
      twoPageVegetationBlocked = a.blocked;
      untrack(() => {
        twoPageVegetationActivityRevision += 1;
      });
    })
  );
  $effect(() => {
    if (siviStandalone) return;
    const state = pState;
    const unsubscribe = subscribeExternalSUEnvironmentActivity((a) => {
      externalSUEnvironmentBusy = a.busy;
      externalSUEnvironmentBlocked = a.blocked;
    });
    if (state?.projectPath && state.suPath && separateSUSelected) {
      const { activeProject, projectPath, activeSU, suPath } = state;
      const next = untrack(() =>
        resolveRetainedExternalSU(
          externalSUEnvironmentSession({
            contextId: deps.contextId,
            project: activeProject,
            projectPath,
            su: activeSU,
            suPath,
          }),
          true
        )
      );
      if (next?.mode === 'twoPage') {
        twoPageEntryInitialForm = next.sourceForm;
        twoPageScope = 'entry';
        twoPageProject = state.activeProject;
        twoPageOpen = true;
      } else if (next?.mode === 'external-reverse') {
        environmentSUDirection = 'external-reverse';
        environmentSUOpen = true;
      }
    }
    return unsubscribe;
  });
  $effect(() => {
    deps.onBusyChange?.(hostEditorBusy);
  });
  $effect(() => {
    const source = sivi.parentSourceView?.choices?.Source ?? null;
    if (source !== null && lastSiviProjectSource !== null && source !== lastSiviProjectSource) {
      invalidateProjectIdChoices(siviContextId);
    }
    if (source !== null) lastSiviProjectSource = source;
  });
  $effect(() => {
    if (standaloneTwoPage) return;
    return observeProjectIdDatalist({
      sourceChoices: sivi.parentSourceView?.choices,
      assignmentChoices: sivi.projectAssignmentView?.choices,
      contextId: siviContextId,
      fetchChoices:
        typeof ContextService?.GetSIVIProjectIDChoices === 'function'
          ? (cid) =>
              getCachedContextValue(cid, 'projectIdChoices', () => ContextService.GetSIVIProjectIDChoices(cid))
          : undefined,
      onChoices: (next) => {
        projectIdDatalist = next;
      },
    });
  });
  $effect(() => {
    const loadedPlot = original?.plotNumber ?? '';
    const expected = deps.getPlotNumber() ?? '';
    const matches = Boolean(loadedPlot && (!expected || loadedPlot === expected));
    deps.onDiagnosticsContextChange?.({
      plotNumber: matches ? loadedPlot : '',
      header: matches ? toRecord($state.snapshot(draft)) : null,
      humus: matches
        ? mergeSoilDraftRows('Humus', children.humusList, children.soilDrafts, (r) => toRecord($state.snapshot(r)))
        : [],
      mineral: matches
        ? mergeSoilDraftRows('Mineral', children.mineralList, children.soilDrafts, (r) => toRecord($state.snapshot(r)))
        : [],
    });
  });
  async function refreshEditLock(ctxId = siviContextId): Promise<void> {
    if (IS_WEB_READONLY) {
      editLock = {
        locked: true,
        reason: 'Web viewer is read-only.',
        signedIn: false,
        userId: '',
        displayName: '',
        role: '',
        identityProvider: '',
        canEditCurrentProject: false,
        isBecMasterProject: false,
        oidcConfigured: false,
        devFallbackAvailable: false,
      };
      return;
    }
    if (typeof ContextService?.GetEditLockStatus !== 'function') return;
    const req = ++editLockRequest;
    try {
      const status = await ContextService.GetEditLockStatus(ctxId);
      if (req !== editLockRequest) return;
      if (status && typeof status === 'object' && typeof status.locked === 'boolean') {
        editLock = status;
      }
    } catch {
      if (req !== editLockRequest) return;
      editLock = {
        locked: true,
        reason: 'Data is locked (read-only). Sign in from Work Space to edit.',
        signedIn: false,
        userId: '',
        displayName: '',
        role: '',
        identityProvider: '',
        canEditCurrentProject: false,
        isBecMasterProject: false,
        oidcConfigured: false,
        devFallbackAvailable: false,
      };
    }
  }

  function requestSignIn() {
    if (typeof window !== 'undefined' && typeof window.dispatchEvent === 'function' && typeof CustomEvent === 'function') {
      window.dispatchEvent(new CustomEvent('vpro:open-signin'));
    }
  }

  $effect(() => {
    const activeCtx = pState?.contextId ?? siviContextId;
    untrack(() => void refreshEditLock(activeCtx));
    if (IS_WEB_READONLY || typeof window === 'undefined' || typeof window.addEventListener !== 'function') {
      return;
    }
    const handleAuthChanged = () => {
      void refreshEditLock(pState?.contextId ?? siviContextId);
    };
    window.addEventListener('vpro:auth-changed', handleAuthChanged);
    return () => {
      window.removeEventListener('vpro:auth-changed', handleAuthChanged);
    };
  });
  $effect(() => {
    const plot = deps.getPlotNumber();
    untrack(() => void load(plot));
  });
  $effect(() => {
    if (siviStandalone || standaloneTwoPage) return;
    untrack(() => void children.loadReferenceLists());
  });
  $effect(() => {
    const tab = activeTab;
    const cards = visibleCards;
    const loadedPlot = original?.plotNumber ?? null;
    const isBusy = busy;
    if (standaloneTwoPage) return;
    untrack(() => {
      if (tab === 'veg' || cards.has('veg')) {
        void children.ensureSpeciesReferencesLoaded();
        void children.ensureAttributeSuggestionsLoaded();
      }
      if (tab === 'vegOther') {
        void children.ensureAttributeSuggestionsLoaded();
      }
      if (tab === 'soils' || cards.has('soils')) {
        void children.ensureSoilSuggestionsLoaded();
      }
      if (tab === 'audit' && loadedPlot && !isBusy) {
        void children.loadAuditEntries(loadedPlot);
      }
    });
  });
  $effect(() => {
    const neighbors = deps.getNeighborPlots?.() ?? [];
    const loadedPlot = original?.plotNumber ?? '';
    if (!loadedPlot || busy || !capabilitiesReady || neighbors.length === 0) return;
    untrack(() => scheduleNeighborPrefetch(loadedPlot));
  });
  onDestroy(() => {
    cancelNeighborPrefetch();
    invalidatePlotBundle(siviContextId);
    invalidateWorkingUnitChoices(siviContextId);
    invalidateProjectIdChoices(siviContextId);
    disposeTwoPageSessionCaches([twoPageSessions, twoPageCommonSessions, twoPageEntrySessions]);
    sivi.disposeAll();
    children.disposeAll();
    loadRequest += 1;
    subEditorGeneration += 1;
    reads.cancelAll();
  });

  async function loadSubEditor<T>(loader: () => Promise<T>, label: string, onFailed: () => void): Promise<T> {
    const request = subEditorGeneration;
    try {
      return await loader();
    } catch (cause) {
      if (request === subEditorGeneration) {
        onFailed();
        error = `${label} could not load: ${formatError(cause)}`;
      }
      throw cause;
    }
  }
  async function vegetationNotesTab() {
    activeTab = 'soils';
    await tick();
    document.querySelector<HTMLInputElement>('#header-soilSurveyor')?.focus();
  }
  function sourceEnter(event: KeyboardEvent) {
    if ((event.ctrlKey || event.metaKey) && !event.altKey && !event.shiftKey && event.key.toLowerCase() === 's') {
      if (metadataOpen) return;
      event.preventDefault();
      if (!authEditLocked && !draft.locked && !busy && !headerWorkflowBusy && capabilitiesReady && (dirty || childUnsaved)) void save();
      return;
    }
    if (event.altKey && !event.ctrlKey && !event.metaKey && !event.shiftKey && event.key.toLowerCase() === 'p') {
      if (twoPageOpen && twoPageScope === 'entry') return;
      event.preventDefault();
      fieldCardModalOpen = !fieldCardModalOpen;
      if (fieldCardModalOpen) fieldCardSplitOpen = false;
      return;
    }
    if (!container) return;
    try {
      navigateSourceEnter(event, container);
    } catch (cause) {
      error = `Source Enter navigation failed; drafts retained: ${formatError(cause)}`;
    }
  }
  function markDirty() {
    dirty = true;
    deps.setSuccess(null);
  }
  const invalidHeaderMessage = 'Correct the invalid header input before saving.';
  function headerValidationError(message: string) {
    return computeHeaderValidationError(message, headerValidation);
  }
  function validateHeader(key: string, message: string | null) {
    const next = { ...headerValidation },
      previous = next[key];
    if (
      previous !== undefined &&
      (error === previous || error === headerValidationError(previous) || error === invalidHeaderMessage)
    )
      error = null;
    if (message === null) delete next[key];
    else next[key] = message;
    headerValidation = next;
  }
  function stageSnowCoverRegime(raw: string) {
    if (arcticInputsDisabled || capabilities.snowCoverRegime !== true) return;
    const value = raw === '' ? null : raw;
    draft.snowCoverRegime = value;
    validateHeader(
      'snowCoverRegime',
      ordinaryTextError(
        { label: 'Snow cover regime', kind: 'text', maximum: 1 },
        value,
        original?.snowCoverRegime ?? null
      )
    );
    markDirty();
  }
  function stageActiveLayerDepth(raw: string) {
    if (arcticInputsDisabled || capabilities.activeLayerDepth !== true) return;
    activeLayerDepthRaw = raw;
    const cell = ordinaryNumberValue(
      { label: 'Active layer depth', kind: 'single' },
      raw,
      original?.activeLayerDepth ?? null
    );
    if (cell.error === null) draft.activeLayerDepth = cell.value;
    validateHeader('activeLayerDepth', cell.error);
    markDirty();
  }
  function linkedVegetationParentBlocked(form: TwoPageVegetationForm): boolean {
    void twoPageVegetationActivityRevision;
    if (twoPageVegetationParentBlocked || twoPageProject === null) return true;
    const others = twoPageVegetationActivity({
      contextId: deps.contextId,
      project: twoPageProject,
      plot: draft.plotNumber,
      form,
    });
    return others.busy || others.blocked;
  }
  async function handleValidationJump(item: FormValidationItem) {
    activeTab = item.tab;
    if (item.tab === 'siviParent') sivi.parentOpen = true;
    await tick();
    focusValidationTarget(container, item);
  }
  function openSpeciesCodeCheck() {
    if (childParentDisabled || childUnsaved || Object.keys(headerValidation).length > 0) {
      error = 'Finish or Undo existing drafts and unlock the available plot before reviewing species codes.';
      return;
    }
    codeCheckOpen = true;
    codeCheckBusy = true;
    error = null;
    deps.setSuccess(null);
  }
  function canOpenProjectMetadata() {
    return twoPageOpen
      ? twoPageScope === 'entry' &&
          Object.keys(headerValidation).length === 0 &&
          typeof twoPageEditor?.openMetadataEditor === 'function' &&
          Boolean(twoPageEditor.canOpenMetadataEditor?.())
      : !childParentDisabled && !childUnsaved && Object.keys(headerValidation).length === 0;
  }
  function openProjectMetadata() {
    if (!canOpenProjectMetadata()) {
      error = 'Finish or Undo existing drafts and unlock the available plot before reviewing project metadata.';
      return;
    }
    if (twoPageOpen) twoPageEditor?.openMetadataEditor?.();
    else {
      metadataOpen = true;
      metadataBusy = true;
    }
    error = null;
    deps.setSuccess(null);
  }
  function canOpenMetadataInPlace() {
    return twoPageOpen && canOpenProjectMetadata();
  }
  function openTwoPageReview(scope: 'extra' | 'common' | 'entry' = 'extra') {
    if (twoPageOpen) {
      error =
        scope === 'entry'
          ? 'Complete-entry review is disabled or another two-page owner is still open.'
          : 'Finish and close the current two-page field review before changing its scope.';
      return;
    }
    const project = pState?.activeProject;
    if (
      !project ||
      pState?.contextId !== siviContextId ||
      siviStandalone ||
      childParentDisabled ||
      childUnsaved ||
      Object.keys(headerValidation).length > 0
    ) {
      error =
        'Finish or Undo existing drafts and unlock the available plot before reviewing two-page additional fields.';
      return;
    }
    twoPageEntryInitialForm = extendedShrubs ? 'FS882-8x6XL-CHARS' : 'FS882-8x6XL';
    twoPageScope = scope;
    twoPageProject = project;
    twoPageOpen = true;
    error = null;
    deps.setSuccess(null);
  }
  function openProfileSUFromTwoPage() {
    if (twoPageBusy || twoPageSoilBusy || twoPageSoilBlocked || twoPageVegetationBusy || twoPageVegetationBlocked) {
      error = 'Finish active two-page operations before opening Plot Profiling / Create SU.';
      return;
    }
    if (sivi.sourceBarrier) {
      error = 'Observe the ProjectID source preference outcome before opening profile rules.';
      return;
    }
    twoPageOpen = false;
    twoPageBusy = false;
    twoPageProject = null;
    profileReviewOpen = true;
    profileReviewBusy = true;
  }
  function openProfileReviewFromToolbar() {
    if (sivi.sourceBarrier) {
      error = 'Observe the ProjectID source preference outcome before opening profile rules.';
      return;
    }
    profileReviewOpen = true;
    profileReviewBusy = true;
  }
  function applyDiagnosticHumusThickness(v: number) {
    applyDiagnosticHumusThicknessImpl({
      disabled: headerInputsDisabled,
      supported: capabilities.humusThickness === true,
      value: v,
      draft,
      original,
      setError: (e) => {
        error = e;
      },
      validateHeader,
      markDirty,
      bumpRevision: () => {
        headerRevision += 1;
      },
    });
  }
  function applyDiagnosticSMR(smr: string) {
    if (headerInputsDisabled || capabilities.moistureRegime !== true) return;
    draft.moistureRegime = smr === '' ? null : smr;
    validateHeader('moistureRegime', null);
    markDirty();
    headerRevision += 1;
  }
  function applyDiagnosticSNR(snr: string) {
    if (headerInputsDisabled || capabilities.nutrientRegime !== true) return;
    draft.nutrientRegime = snr === '' ? null : snr;
    validateHeader('nutrientRegime', null);
    markDirty();
    headerRevision += 1;
  }
  function refreshTwoPagePeers(scope: 'extra' | 'common' | 'entry') {
    cancelNeighborPrefetch();
    invalidatePlotBundle(siviContextId, draft.plotNumber);
    invalidateWorkingUnitChoices(siviContextId, 'env');
    invalidateProjectIdChoices(siviContextId);
    return refreshTwoPagePeersImpl({
      scope,
      contextId: deps.contextId,
      twoPageProject,
      plotNumber: draft.plotNumber,
      twoPageSessions,
      twoPageCommonSessions,
      twoPageEntrySessions,
      refreshParent: () => sivi.refreshAllParentPeers(draft.plotNumber),
    });
  }
  function invalidateAfterSUTransfer(bulkPlots: boolean) {
    cancelNeighborPrefetch();
    invalidateWorkingUnitChoices(siviContextId);
    if (bulkPlots) invalidatePlotBundle(siviContextId);
  }
  function invalidateAfterSpeciesCodeCheck() {
    cancelNeighborPrefetch();
    invalidatePlotBundle(siviContextId);
    invalidateSpeciesLists(siviContextId);
  }
  function invalidateAfterProjectMetadata() {
    invalidateProjectIdChoices(siviContextId);
  }
  function openEnvironmentSU(direction: 'forward' | 'reverse' = 'forward') {
    if (
      childParentDisabled ||
      childUnsaved ||
      Object.keys(headerValidation).length > 0 ||
      !pState?.activeSU ||
      pState.activeSU === 'None' ||
      !original
    ) {
      error =
        'Select an owned-project SU, finish or Undo all drafts and unlock the available plot before reviewing Env Into SU.';
      return;
    }
    environmentSUDirection = direction;
    environmentSUOpen = true;
    error = null;
    deps.setSuccess(null);
  }
  function openExternalSUEnvironment() {
    if (
      siviStandalone ||
      !separateSUSelected ||
      childParentDisabled ||
      childUnsaved ||
      Object.keys(headerValidation).length > 0 ||
      !original
    ) {
      error = 'Select a separate SU file and finish or Undo all drafts before reviewing SU Into Env.';
      return;
    }
    const state = pState;
    if (!state?.projectPath || !state.suPath) {
      error = 'Selected project and SU paths are unavailable; no transfer review was opened.';
      return;
    }
    externalSUEnvironmentSession({
      contextId: deps.contextId,
      project: state.activeProject,
      projectPath: state.projectPath,
      su: state.activeSU,
      suPath: state.suPath,
    }).reviewSourceForm(null);
    environmentSUDirection = 'external-reverse';
    environmentSUOpen = true;
    error = null;
    deps.setSuccess(null);
  }
  async function refreshAfterRestore(plot: string, request: number) {
    cancelNeighborPrefetch();
    invalidatePlotBundle(siviContextId, plot);
    invalidateWorkingUnitChoices(siviContextId, 'env');
    invalidateProjectIdChoices(siviContextId);
    const header = await reads.track(PlotService.GetPlot(plot));
    if (!header) throw new Error('Restored plot could not be reloaded.');
    await children.loadChildData(plot, { includeAudit: true });
    if (request !== loadRequest) return;
    draft = { ...header, locked: draft.locked };
    original = structuredClone(header);
    activeLayerDepthRaw = null;
    dirty = false;
    headerValidation = {};
    headerRevision += 1;
  }

  function resetTransientUiForPlot(p?: string) {
    const hadInvalidHeader =
      Object.keys(headerValidation).length > 0 || Boolean(container?.querySelector('.header-editor input:invalid'));
    managePlotOpen = false;
    codeCheckOpen = false;
    codeCheckBusy = false;
    metadataOpen = false;
    metadataBusy = false;
    profileReviewOpen = false;
    profileReviewBusy = false;
    profileReviewBlocked = false;
    environmentSUOpen = false;
    fieldCardModalOpen = false;
    error = null;
    deps.setSuccess(null);
    activeLayerDepthRaw = null;
    dirty = false;
    mensurationDirty = false;
    mensurationBusy = false;
    headerValidation = {};
    if (!standaloneTwoPage || !p) {
      twoPageOpen = false;
      twoPageBusy = false;
      twoPageProject = null;
    } else {
      twoPageBusy = false;
    }
    if (!siviStandalone && activeTab === 'siviParent') {
      activeTab = 'site';
    }
    if (workingUnitSession.plot !== (p ?? '')) workingUnitSession.mode = null;
    workingUnitSession.plot = p ?? '';
    sivi.resetForPlot();
    children.resetForPlot();
    if (hadInvalidHeader) headerRevision += 1;
  }

  function applyLoadedBundle(
    bundle: PlotBundle,
    cachedCaps?: CachedContextCapabilities,
    skipSiviInit = false
  ): CachedContextCapabilities {
    if (!bundle.header) throw new Error('Plot could not be loaded.');
    const resolvedHeaderCaps = bundle.headerCapabilities ?? cachedCaps?.headerCapabilities ?? null;
    if (resolvedHeaderCaps === null) throw new Error('Header capabilities were not returned.');
    const resolvedMaster =
      typeof bundle.canEditMasterBEC === 'boolean'
        ? bundle.canEditMasterBEC
        : (cachedCaps?.masterAllowed ?? false);
    const resolvedChildCaps = children.applyBundleChildren(bundle, cachedCaps?.childCapabilities);
    const nextCaps: CachedContextCapabilities = {
      headerCapabilities: resolvedHeaderCaps,
      childCapabilities: resolvedChildCaps,
      masterAllowed: resolvedMaster,
    };
    setCachedContextCapabilities(siviContextId, nextCaps);
    capabilities = resolvedHeaderCaps;
    masterAllowed = resolvedMaster;
    draft = structuredClone(bundle.header);
    original = structuredClone(bundle.header);
    activeLayerDepthRaw = null;
    dirty = false;
    headerValidation = {};
    if (!skipSiviInit) {
      sivi.initForLoadedPlot(bundle.header.plotNumber, extendedShrubs);
    }
    capabilitiesReady = true;
    return nextCaps;
  }

  async function load(p?: string, options?: { force?: boolean }) {
    const blockedReason = sivi.blockedLoadReason();
    if (blockedReason) {
      error = blockedReason;
      return;
    }
    const force = Boolean(options?.force);
    loadRequest += 1;
    const request = loadRequest;
    reads.cancelAll();
    resetTransientUiForPlot(p);

    const getPlotBundle = PlotService.GetPlotBundle;
    const cachedCaps = !force ? getCachedContextCapabilities(siviContextId) : undefined;

    // Synchronous prefetch hit: apply atomically with ZERO busy=true transition and ZERO RPCs
    if (p && !force && cachedCaps && typeof getPlotBundle === 'function') {
      const cachedBundle = peekPlotBundle<PlotBundle>(siviContextId, p);
      if (cachedBundle && cachedBundle.header) {
        try {
          applyLoadedBundle(cachedBundle, cachedCaps);
          if (siviStandalone && sivi.parentSession) {
            if (activeTab !== 'veg') activeTab = 'siviParent';
            sivi.parentOpen = true;
            busy = true;
            try {
              await sivi.loadParentOriginals();
            } finally {
              if (request === loadRequest) busy = false;
            }
          }
          if (request === loadRequest) scheduleNeighborPrefetch(p);
          return;
        } catch (e) {
          if (request === loadRequest) {
            error = formatError(e);
            capabilitiesReady = false;
            if (standaloneTwoPage) {
              twoPageOpen = false;
              twoPageBusy = false;
              twoPageProject = null;
            }
          }
          return;
        }
      }
    }

    busy = true;
    capabilitiesReady = false;
    masterAllowed = false;
    try {
      if (p && typeof getPlotBundle === 'function') {
        if (force) invalidatePlotBundle(siviContextId, p);
        const includeCaps = !cachedCaps;
        let siviPreInitialized = false;
        let siviOriginalsPromise: Promise<void> | null = null;
        if (siviStandalone) {
          sivi.initForLoadedPlot(p, extendedShrubs);
          if (sivi.parentSession) {
            siviPreInitialized = true;
            if (activeTab !== 'veg') activeTab = 'siviParent';
            sivi.parentOpen = true;
            siviOriginalsPromise = sivi.loadParentOriginals();
          }
        }
        const bundlePromise = getCachedPlotBundle<PlotBundle>(siviContextId, p, async () => {
          const res = await getPlotBundle(p, includeCaps);
          if (!res || !res.header) throw new Error(`Plot ${p} could not be loaded.`);
          return res;
        });
        let bundle: PlotBundle;
        if (siviOriginalsPromise) {
          const [resolvedBundle] = await Promise.all([bundlePromise, siviOriginalsPromise]);
          bundle = resolvedBundle;
        } else {
          bundle = await bundlePromise;
        }
        if (request !== loadRequest) return;
        if (!cachedCaps && (!bundle.headerCapabilities || !bundle.childCapabilities)) {
          invalidatePlotBundle(siviContextId, p);
          bundle = await getCachedPlotBundle<PlotBundle>(siviContextId, p, async () => {
            const res = await getPlotBundle(p, true);
            if (!res || !res.header) throw new Error(`Plot ${p} could not be loaded.`);
            return res;
          });
          if (request !== loadRequest) return;
        }
        const skipInit = siviPreInitialized && bundle.header?.plotNumber === p;
        applyLoadedBundle(bundle, cachedCaps, skipInit);
        if (siviStandalone && sivi.parentSession && !skipInit) {
          if (activeTab !== 'veg') activeTab = 'siviParent';
          sivi.parentOpen = true;
          await sivi.loadParentOriginals();
        }
        if (request === loadRequest) scheduleNeighborPrefetch(p);
        return;
      }

      // Fallback path: brand-new plot (p === undefined) OR minimal mock PlotService without GetPlotBundle
      const [fields, res, masterPolicy] = await Promise.all([
        cachedCaps?.headerCapabilities
          ? Promise.resolve(cachedCaps.headerCapabilities)
          : reads.track(PlotService.GetHeaderCapabilities()),
        p ? reads.track(PlotService.GetPlot(p)) : Promise.resolve(null),
        cachedCaps !== undefined
          ? Promise.resolve(cachedCaps.masterAllowed)
          : reads.track(PlotService.CanEditMasterBEC()),
      ]);
      if (request !== loadRequest) return;
      if (fields === null) throw new Error('Header capabilities were not returned.');
      capabilities = fields;
      masterAllowed = masterPolicy;
      if (p && !res) throw new Error(`Plot ${p} could not be loaded.`);
      if (p && !standaloneTwoPage) await children.loadChildData(p);
      if (request !== loadRequest) return;
      if (res !== null) {
        draft = { ...res };
        original = structuredClone(res);
        activeLayerDepthRaw = null;
        dirty = false;
        headerValidation = {};
        sivi.initForLoadedPlot(res.plotNumber, extendedShrubs);
        if (!cachedCaps && !standaloneTwoPage) {
          setCachedContextCapabilities(siviContextId, {
            headerCapabilities: fields,
            childCapabilities: children.childCapabilities,
            masterAllowed: masterPolicy,
          });
        }
      } else {
        draft = newEmptyFS882Draft();
        original = null;
        activeLayerDepthRaw = null;
        dirty = false;
        headerValidation = {};
      }
      capabilitiesReady = true;
      if (siviStandalone && sivi.parentSession) {
        if (activeTab !== 'veg') activeTab = 'siviParent';
        sivi.parentOpen = true;
        await sivi.loadParentOriginals();
      }
    } catch (e) {
      if (request === loadRequest) {
        error = formatError(e);
        if (standaloneTwoPage) {
          twoPageOpen = false;
          twoPageBusy = false;
          twoPageProject = null;
        }
      }
    } finally {
      if (request === loadRequest) busy = false;
    }
  }

  async function save() {
    if (authEditLocked) {
      error = editLock?.reason || 'Data is locked (read-only). Sign in from Work Space to edit.';
      return;
    }
    const blocked = firstMatch<string>([
      [
        () => sivi.sourceAuthorityUnknown,
        'Read owned ProjectID choices to observe the source preference outcome before saving.',
      ],
      [() => busy || headerWorkflowBusy, 'Wait for the current operation to finish before saving.'],
      [
        () => sivi.deletionPending || sivi.restorationPending || sivi.creationUndoPending,
        'Confirm deletion/restoration/creation Undo explicitly in its reviewed panel or discard the unsubmitted review; ordinary Save never performs it.',
      ],
      [
        () => codeCheckOpen,
        'Save replacements or personal metadata explicitly, then close species-code review; ordinary plot Save never applies them.',
      ],
      [
        () => metadataOpen,
        'Save or Undo metadata explicitly, then close metadata review; ordinary plot Save never applies it.',
      ],
      [
        () => profileReviewBlocked,
        'Save or Undo profile drafts explicitly; ordinary plot Save never writes profile rules.',
      ],
      [
        () => children.personalDraft !== null,
        'Save the personal definition explicitly or Cancel its entry; ordinary plot Save never writes the user database.',
      ],
      [
        () => children.deletionReview !== null,
        'Confirm reviewed vegetation deletion explicitly or Cancel deletion review; ordinary Save never deletes rows.',
      ],
    ]);
    if (blocked) {
      error = blocked;
      return;
    }
    const draftHandler =
      children.creationDraft !== null
        ? () => children.saveVegetationCreation()
        : (sivi.saveDraftHandler() ?? children.saveDraftHandler());
    if (draftHandler) {
      await draftHandler();
      return;
    }
    const invalid = container?.querySelector<HTMLInputElement>('.header-editor input:invalid');
    if (invalid) {
      invalid.reportValidity();
      error = invalidHeaderMessage;
      return;
    }
    const validation = Object.values(headerValidation)[0];
    if (validation) {
      error = headerValidationError(validation);
      return;
    }
    if (!capabilitiesReady || draft.locked) {
      error = 'The header is not available for saving.';
      return;
    }
    if (!draft.plotNumber.trim()) {
      error = 'Plot Number is required.';
      return;
    }
    busy = true;
    error = null;
    deps.setSuccess(null);
    const prevUserSiteUnit = original?.userSiteUnit ?? null;
    const prevProjectId = original?.projectId ?? null;
    try {
      const payload = $state.snapshot({ ...draft, locked: capabilities.locked === true && draft.locked });
      if (original) await PlotService.UpdatePlot({ ...payload, original: $state.snapshot(original) } as FS882Header);
      else await PlotService.CreatePlot(payload);
      cancelNeighborPrefetch();
      invalidatePlotBundle(siviContextId, draft.plotNumber);
      if (prevUserSiteUnit !== (draft.userSiteUnit ?? null)) {
        invalidateWorkingUnitChoices(siviContextId, 'env');
      }
      if (prevProjectId !== (draft.projectId ?? null)) {
        invalidateProjectIdChoices(siviContextId);
      }
      children.invalidateAuditForPlot();
      original = structuredClone($state.snapshot(draft));
      activeLayerDepthRaw = null;
      workingUnitSession.plot = draft.plotNumber;
      dirty = false;
      headerValidation = {};
      deps.setSuccess(`Plot ${draft.plotNumber} saved successfully.`, true);
      notifications.success(`Plot ${draft.plotNumber} saved`, 'Saved to project file.', {
        category: 'entry',
        source: 'FS882 Form',
        contextTag: draft.plotNumber ? `Plot ${draft.plotNumber}` : undefined,
      });
      await children.loadChildData(draft.plotNumber, { includeAudit: activeTab === 'audit' });
      if (sivi.parentSession?.view().original || sivi.parentSession?.view().error)
        await sivi.refreshAllParentPeers(draft.plotNumber);
      if (deps.onSaved) await deps.onSaved(draft.plotNumber);
    } catch (e) {
      const rawMsg = formatError(e);
      const conflict =
        rawMsg.includes('plot changed since it was loaded') ||
        rawMsg.includes('no longer exists; reload before saving');
      error = rawMsg;
      if (conflict)
        notifications.error(`Plot ${draft.plotNumber} save conflict`, error, {
          category: 'entry',
          source: 'FS882 Form',
          contextTag: draft.plotNumber ? `Plot ${draft.plotNumber}` : undefined,
        });
    } finally {
      busy = false;
    }
  }

  function getCloseState(): EditorCloseState {
    void twoPageRevision;
    const override = computeFS882SubEditorCloseOverride({
      twoPageVegetationBusy,
      twoPageVegetationBlocked,
      twoPageSoilBusy,
      twoPageSoilBlocked,
      lifecycleOverride: sivi.lifecycleCloseOverride(busy, headerWorkflowBusy),
      twoPageOpen,
      twoPageClose: twoPageEditor ? () => twoPageEditor!.getCloseState() : undefined,
      environmentSUOpen,
      environmentSUClose: environmentSUEditor ? () => environmentSUEditor!.getCloseState() : undefined,
      profileReviewBlocked,
      profileClose: profileEditor ? () => profileEditor!.getCloseState() : undefined,
      metadataOpen,
      metadataClose: metadataEditor ? () => metadataEditor!.getCloseState() : undefined,
      codeCheckOpen,
      codeCheckClose: codeCheckEditor ? () => codeCheckEditor!.getCloseState() : undefined,
      creationOverride: sivi.creationCloseOverride(busy, headerWorkflowBusy, error),
      error,
    });
    if (override) return override;
    const invalid = Object.keys(headerValidation).length > 0 || children.hasInvalidDrafts();
    const invalidChild = Boolean(container?.querySelector('.source-child input:invalid'));
    const baseSaveReason = computeSaveReason({
      busy: busy || mensurationBusy,
      headerWorkflowBusy,
      capabilitiesReady,
      locked: authEditLocked || draft.locked,
      ...sivi.saveReasonFields(),
      ...children.saveReasonFields(),
      invalidChild,
      invalid,
      plotNumber: draft.plotNumber,
    });
    const saveReason =
      baseSaveReason ||
      (mensurationDirty ? 'Save or discard unsaved Card 4 mensuration edits before closing.' : '');
    return {
      unsaved: dirty || childUnsaved || invalid || children.newChild !== null || invalidChild,
      busy: busy || headerWorkflowBusy,
      blocked: sivi.anySessionBlocked(),
      canSave: saveReason === '',
      saveReason,
      error,
    };
  }

  async function saveForClose(): Promise<boolean> {
    if (twoPageOpen && typeof twoPageEditor?.saveForClose === 'function') return await twoPageEditor.saveForClose();
    const state = getCloseState();
    if (!state.canSave) {
      error = state.saveReason;
      return false;
    }
    await save();
    return !dirty && !childUnsaved && Object.keys(headerValidation).length === 0 && error === null;
  }

  function undo() {
    if (twoPageOpen) {
      twoPageEditor?.undo();
      return;
    }
    if (environmentSUOpen) {
      environmentSUEditor?.undo();
      return;
    }
    if (busy || headerWorkflowBusy) {
      error = 'Wait for the current operation to finish before undoing changes.';
      return;
    }
    const modalUndo = firstMatch<() => void>([
      [() => codeCheckOpen, () => codeCheckEditor?.undo()],
      [() => metadataOpen, () => metadataEditor?.undo()],
      [() => profileReviewBlocked, () => profileEditor?.undo()],
    ]);
    const handler = modalUndo ?? children.undoDraftHandler() ?? sivi.undoDraftHandler();
    if (handler) {
      handler();
      return;
    }
    draft = original ? structuredClone($state.snapshot(original)) : newEmptyFS882Draft();
    activeLayerDepthRaw = null;
    dirty = false;
    headerValidation = {};
    error = null;
    headerRevision += 1;
    deps.setSuccess('Changes undone.', true);
    notifications.success(
      'Draft changes undone',
      draft.plotNumber ? `Plot ${draft.plotNumber} restored to last saved state.` : 'Draft reset.',
      { category: 'entry', source: 'FS882 Form', contextTag: draft.plotNumber ? `Plot ${draft.plotNumber}` : undefined }
    );
  }

  async function toggleLock() {
    if (authEditLocked) {
      error = editLock?.reason || 'Data is locked (read-only). Sign in from Work Space to edit.';
      return;
    }
    const blocked =
      firstMatch<string>([
        [() => busy || headerWorkflowBusy, 'Wait for the current operation to finish before changing the plot lock.'],
        [() => codeCheckOpen, 'Finish or close species-code review before changing the plot lock.'],
        [() => metadataOpen, 'Finish or close metadata review before changing the plot lock.'],
        [() => profileReviewBlocked, 'Finish profile drafts before changing the plot lock.'],
        [() => mensurationDirty, 'Save or discard unsaved Card 4 mensuration edits before changing the plot lock.'],
      ]) ??
      sivi.lockBlockedReason() ??
      children.lockBlockedReason();
    if (blocked) {
      error = blocked;
      return;
    }
    if (!draft.locked && dirty) {
      await save();
      if (dirty) return;
    }
    draft.locked = !draft.locked;
    notifications.success(
      draft.locked ? `Plot ${draft.plotNumber || ''} locked`.trim() : `Plot ${draft.plotNumber || ''} unlocked`.trim(),
      draft.locked ? 'Form is now protected in read-only mode.' : 'Form is now unlocked for editing.',
      { category: 'entry', source: 'FS882 Form', contextTag: draft.plotNumber ? `Plot ${draft.plotNumber}` : undefined }
    );
  }

  return {
    contextId: deps.contextId,
    siviContextId,
    siviStandalone,
    PlotService,
    workingUnitSession,
    children,
    sivi,
    twoPageSessions,
    twoPageCommonSessions,
    twoPageEntrySessions,
    get standaloneTwoPage() {
      return standaloneTwoPage;
    },
    get pState() {
      return pState;
    },
    get visibleTabs() {
      return visibleTabs;
    },
    get activeTab() {
      return activeTab;
    },
    set activeTab(v: FS882TabId) {
      activeTab = v;
    },
    get container() {
      return container;
    },
    set container(v: HTMLDivElement | undefined) {
      container = v;
    },
    get fieldCardModalOpen() {
      return fieldCardModalOpen;
    },
    set fieldCardModalOpen(v: boolean) {
      fieldCardModalOpen = v;
    },
    get fieldCardSplitOpen() {
      return fieldCardSplitOpen;
    },
    set fieldCardSplitOpen(v: boolean) {
      fieldCardSplitOpen = v;
    },
    get vegetationMode() {
      return vegetationMode;
    },
    set vegetationMode(v: VegetationMode) {
      vegetationMode = v;
    },
    get extendedShrubs() {
      return extendedShrubs;
    },
    get managePlotOpen() {
      return managePlotOpen;
    },
    set managePlotOpen(v: boolean) {
      managePlotOpen = v;
    },
    get busy() {
      return busy || mensurationBusy;
    },
    set busy(v: boolean) {
      busy = v;
    },
    get mensurationDirty() {
      return mensurationDirty;
    },
    set mensurationDirty(v: boolean) {
      mensurationDirty = v;
    },
    get mensurationBusy() {
      return mensurationBusy;
    },
    set mensurationBusy(v: boolean) {
      mensurationBusy = v;
    },
    get coordinateBusy() {
      return coordinateBusy;
    },
    set coordinateBusy(v: boolean) {
      coordinateBusy = v;
    },
    get workingUnitBusy() {
      return workingUnitBusy;
    },
    set workingUnitBusy(v: boolean) {
      workingUnitBusy = v;
    },
    get qualityBusy() {
      return qualityBusy;
    },
    set qualityBusy(v: boolean) {
      qualityBusy = v;
    },
    get siteCodeBusy() {
      return siteCodeBusy;
    },
    set siteCodeBusy(v: boolean) {
      siteCodeBusy = v;
    },
    get regionCodeBusy() {
      return regionCodeBusy;
    },
    set regionCodeBusy(v: boolean) {
      regionCodeBusy = v;
    },
    get soilCodeBusy() {
      return soilCodeBusy;
    },
    set soilCodeBusy(v: boolean) {
      soilCodeBusy = v;
    },
    get geologyCodeBusy() {
      return geologyCodeBusy;
    },
    set geologyCodeBusy(v: boolean) {
      geologyCodeBusy = v;
    },
    get parentCodeBusy() {
      return parentCodeBusy;
    },
    set parentCodeBusy(v: boolean) {
      parentCodeBusy = v;
    },
    get drainageBusy() {
      return drainageBusy;
    },
    set drainageBusy(v: boolean) {
      drainageBusy = v;
    },
    get codeCheckOpen() {
      return codeCheckOpen;
    },
    set codeCheckOpen(v: boolean) {
      codeCheckOpen = v;
    },
    get codeCheckBusy() {
      return codeCheckBusy;
    },
    set codeCheckBusy(v: boolean) {
      codeCheckBusy = v;
    },
    get codeCheckEditor() {
      return codeCheckEditor;
    },
    set codeCheckEditor(v) {
      codeCheckEditor = v;
    },
    get metadataOpen() {
      return metadataOpen;
    },
    set metadataOpen(v: boolean) {
      metadataOpen = v;
    },
    get metadataBusy() {
      return metadataBusy;
    },
    set metadataBusy(v: boolean) {
      metadataBusy = v;
    },
    get metadataEditor() {
      return metadataEditor;
    },
    set metadataEditor(v) {
      metadataEditor = v;
    },
    get pictureBusy() {
      return pictureBusy;
    },
    set pictureBusy(v: boolean) {
      pictureBusy = v;
    },
    get twoPageOpen() {
      return twoPageOpen;
    },
    set twoPageOpen(v: boolean) {
      twoPageOpen = v;
    },
    get twoPageScope() {
      return twoPageScope;
    },
    set twoPageScope(v: 'extra' | 'common' | 'entry') {
      twoPageScope = v;
    },
    get twoPageEntryInitialForm() {
      return twoPageEntryInitialForm;
    },
    get twoPageBusy() {
      return twoPageBusy;
    },
    set twoPageBusy(v: boolean) {
      twoPageBusy = v;
    },
    get twoPageProject() {
      return twoPageProject;
    },
    set twoPageProject(v: string | null) {
      twoPageProject = v;
    },
    get twoPageRevision() {
      return twoPageRevision;
    },
    set twoPageRevision(v: number) {
      twoPageRevision = v;
    },
    get twoPageEditor() {
      return twoPageEditor;
    },
    set twoPageEditor(v) {
      twoPageEditor = v;
    },
    get twoPageSoilBusy() {
      return twoPageSoilBusy;
    },
    get twoPageSoilBlocked() {
      return twoPageSoilBlocked;
    },
    get twoPageVegetationBusy() {
      return twoPageVegetationBusy;
    },
    get twoPageVegetationBlocked() {
      return twoPageVegetationBlocked;
    },
    get environmentSUOpen() {
      return environmentSUOpen;
    },
    set environmentSUOpen(v: boolean) {
      environmentSUOpen = v;
    },
    get environmentSUDirection() {
      return environmentSUDirection;
    },
    get environmentSUEditor() {
      return environmentSUEditor;
    },
    set environmentSUEditor(v) {
      environmentSUEditor = v;
    },
    get profileReviewOpen() {
      return profileReviewOpen;
    },
    set profileReviewOpen(v: boolean) {
      profileReviewOpen = v;
    },
    get profileReviewBusy() {
      return profileReviewBusy;
    },
    set profileReviewBusy(v: boolean) {
      profileReviewBusy = v;
    },
    get profileReviewBlocked() {
      return profileReviewBlocked;
    },
    set profileReviewBlocked(v: boolean) {
      profileReviewBlocked = v;
    },
    get profileEditor() {
      return profileEditor;
    },
    set profileEditor(v) {
      profileEditor = v;
    },
    get error() {
      return error;
    },
    set error(v: string | null) {
      error = v;
    },
    get dirty() {
      return dirty;
    },
    get headerValidation() {
      return headerValidation;
    },
    set headerValidation(v: Record<string, string>) {
      headerValidation = v;
    },
    get capabilities() {
      return capabilities;
    },
    set capabilitiesReady(v: boolean) {
      capabilitiesReady = v;
    },
    get capabilitiesReady() {
      return capabilitiesReady;
    },
    get masterAllowed() {
      return masterAllowed;
    },
    get headerRevision() {
      return headerRevision;
    },
    get loadRequest() {
      return loadRequest;
    },
    get draft() {
      return draft;
    },
    set draft(v: FS882Header) {
      draft = v;
    },
    get original() {
      return original;
    },
    set original(v: FS882Header | null) {
      original = v;
    },
    get projectIdDatalist() {
      return projectIdDatalist;
    },
    get separateSUSelected() {
      return separateSUSelected;
    },
    get otherHeaderWorkflowBusy() {
      return otherHeaderWorkflowBusy;
    },
    get headerWorkflowBusy() {
      return headerWorkflowBusy;
    },
    get tabWorkflowBusy() {
      return tabWorkflowBusy;
    },
    get siviCreationPeerUnsaved() {
      return siviCreationPeerUnsaved;
    },
    get nonParentChildUnsaved() {
      return nonParentChildUnsaved;
    },
    get childUnsaved() {
      return childUnsaved;
    },
    get sourceHeaderValues() {
      return sourceHeaderValues;
    },
    get snowCoverRegimeInput() {
      return snowCoverRegimeInput;
    },
    get activeLayerDepthInput() {
      return activeLayerDepthInput;
    },
    get arcticInputsDisabled() {
      return arcticInputsDisabled;
    },
    get headerInputsDisabled() {
      return headerInputsDisabled;
    },
    get nonArcticHeaderDirty() {
      return nonArcticHeaderDirty;
    },
    get twoPageLinkedParentBlocked() {
      return twoPageLinkedParentBlocked;
    },
    get twoPageSoilParentBlocked() {
      return twoPageSoilParentBlocked;
    },
    get childParentDisabled() {
      return childParentDisabled;
    },
    get auditGateReason() {
      return auditGateReason;
    },
    get validationSummaryItems() {
      return validationSummaryItems;
    },
    get fieldCardViewModel() {
      return fieldCardViewModel;
    },
    get effectiveFormDirty() {
      return effectiveFormDirty;
    },
    get isHeaderConflict() {
      return isHeaderConflict;
    },
    get editLock() {
      return editLock;
    },
    get authEditLocked() {
      return authEditLocked;
    },
    get layoutMode() {
      return layoutMode;
    },
    set layoutMode(v: ClassicLayoutMode) {
      layoutMode = v;
    },
    get splitLeftCard() {
      return splitLeftCard;
    },
    set splitLeftCard(v: ClassicCardId) {
      splitLeftCard = v;
    },
    get splitRightCard() {
      return splitRightCard;
    },
    set splitRightCard(v: ClassicCardId) {
      splitRightCard = v;
    },
    get visibleCards() {
      return visibleCards;
    },
    refreshEditLock,
    requestSignIn,
    setExtendedShrubs,
    loadSubEditor,
    vegetationNotesTab,
    sourceEnter,
    markDirty,
    validateHeader,
    stageSnowCoverRegime,
    stageActiveLayerDepth,
    linkedVegetationParentBlocked,
    handleValidationJump,
    openSpeciesCodeCheck,
    canOpenProjectMetadata,
    openProjectMetadata,
    canOpenMetadataInPlace,
    openTwoPageReview,
    openProfileSUFromTwoPage,
    openProfileReviewFromToolbar,
    applyDiagnosticHumusThickness,
    applyDiagnosticSMR,
    applyDiagnosticSNR,
    refreshTwoPagePeers,
    invalidateAfterSUTransfer,
    invalidateAfterSpeciesCodeCheck,
    invalidateAfterProjectMetadata,
    openEnvironmentSU,
    openExternalSUEnvironment,
    refreshAfterRestore,
    load,
    save,
    getCloseState,
    saveForClose,
    undo,
    toggleLock,
  };
}

export type FS882Controller = ReturnType<typeof createFS882Controller>;
