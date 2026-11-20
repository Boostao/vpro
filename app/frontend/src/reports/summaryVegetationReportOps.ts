import type {
  SummaryVegetationPreferencesReview,
  VegetationReportService,
} from '../../bindings/github.com/boostao/vpro/app';
import type { CancellableRead, ReadRequests } from '../shared/readRequests';
import type { SummaryVegetationPort } from './summaryVegetation';
import type { SummaryWorkbookCalculation } from './summaryVegetationWorkbook';
import type { FieldListDesktopState } from './summaryVegetationFieldListDesktop';
import type { SummaryVegetationPreferencesSession } from './summaryVegetationPreferences';
import type { SummaryVegetationQualityPreferencesSession } from './summaryVegetationQualityPreferences';
import type { SummaryVegetationPresentationPreferencesSession } from './summaryVegetationPresentationPreferences';
import type {
  SummaryEnvironmentalLifeformSession,
  SummaryEnvironmentalNumericSession,
  SummaryEnvironmentalPort,
  SummaryEnvironmentalSession,
} from './summaryVegetationEnvironmental';

export interface SummaryVegToastSink {
  success: (title: string, message: string, opts?: Record<string, unknown>) => void;
  warning: (title: string, message: string, opts?: Record<string, unknown>) => void;
  error: (title: string, message: string, opts?: Record<string, unknown>) => void;
  info: (title: string, message: string, opts?: Record<string, unknown>) => void;
}

export interface SummaryVegNotificationTracker {
  lastViewError: string;
  lastPrefReadError: string;
  lastPrefError: string;
  notifiedPrefReceipts: number;
  lastFieldListReadError: string;
}

export interface SavedPresentationDraft {
  title: string;
  includeEnv: boolean;
  createSummary: boolean;
  showCommon: boolean;
  showGuide: boolean;
  constancy: boolean;
}

export interface LoadedWorkbookScopeOptions {
  unitScope?: 'su' | 'hierarchy' | 'none' | 'field';
  unitField?: string;
  breakpointPolicy?: 'lowest' | 'highest';
  combineVariants?: boolean;
  lumpTable?: string;
  includeGoldstreamMetadata?: boolean;
}

export interface SummaryVegOptionsModel {
  project: string;
  projectPath: string;
  su: string;
  suPath: string;
  unavailableScope: boolean;
  contextId: string;
  editHeld: boolean;
  unitScope: 'su' | 'hierarchy' | 'none' | 'field';
  unitField: string;
  breakpointPolicy: 'lowest' | 'highest';
  lumpTable: string;
  lumpTables: string[];
  groupAndOrder: number;
  display: number;
  showClass: number;
  average: number;
  combineVariants: boolean;
  includeGoldstreamMetadata: boolean;
}

export interface SummaryVegOptionsHandlers {
  onUnitScopeChange: (next: 'su' | 'hierarchy' | 'none' | 'field') => void;
  onUnitFieldInput: (next: string) => void;
  onBreakpointPolicyChange: (next: 'lowest' | 'highest') => void;
  onLumpTableChange: (next: string) => void;
  onRefreshLumpTables: () => void;
  onGroupChange: (event: Event) => void;
  onDisplayChange: (event: Event) => void;
  onShowClassChange: (event: Event) => void;
  onAverageChange: (event: Event) => void;
  onCombineVariantsChange: (checked: boolean) => void;
  onIncludeGoldstreamChange: (checked: boolean) => void;
}

export interface SummaryVegPeerModel {
  owner: { contextId: string; project: string; projectPath: string; su: string; suPath: string };
  preferences: SummaryVegetationPreferencesSession | null;
  preferenceView: ReturnType<SummaryVegetationPreferencesSession['view']> | null;
  preferenceReadBusy: boolean;
  preferenceHeld: boolean;
  preferenceInvalid: boolean;
  quality: SummaryVegetationQualityPreferencesSession | null;
  qualityView: ReturnType<SummaryVegetationQualityPreferencesSession['view']> | null;
  qualityMutationHeld: boolean;
  qualityInvalid: boolean;
  qualityUnavailable: boolean;
  presentation: SummaryVegetationPresentationPreferencesSession | null;
  presentationView: ReturnType<SummaryVegetationPresentationPreferencesSession['view']> | null;
  presentationMutationHeld: boolean;
  presentationInvalid: boolean;
  fieldListEnabled: boolean;
  fieldListScopeAvailable: boolean;
  fieldListState: FieldListDesktopState | null;
  fieldListHeld: boolean;
  fieldListBusy: boolean;
  fieldListPeerDisabled: boolean;
  fieldListPeerValidation: string;
  fieldListEnabledFromPresentation: boolean;
  environmentalSession:
    SummaryEnvironmentalSession | SummaryEnvironmentalNumericSession | SummaryEnvironmentalLifeformSession | null;
  environmentalPort: SummaryEnvironmentalPort;
  environmentalNumericEnabled: boolean;
  environmentalLifeformEnabled: boolean;
  environmentalHeld: boolean;
  operationHeldProp: boolean;
  operationHeld: boolean;
  workbookHeld: boolean;
  unavailableScope: boolean;
  viewBusy: boolean;
  viewDraftError: string;
  calculation: SummaryWorkbookCalculation;
  savedPresentation: SavedPresentationDraft | null;
}

export interface SummaryVegPeerHandlers {
  onLoadPreferences: () => void;
  onSavePreferences: () => void;
  onUndoPreferences: () => void;
  onAcknowledgePreferences: () => void;
  onCancelPreferenceRead: () => void;
  onQualityReadBusyChange: (busy: boolean) => void;
  onPresentationReadBusyChange: (busy: boolean) => void;
  onDismissInitialFieldListReadError: () => void;
  onLoadFieldList: () => void;
  onCancelFieldListRead: () => void;
  onFieldListStateChange: () => void;
  onEnvironmentalBusyChange: () => void;
  onWorkbookPreferencesLoaded: (opts: LoadedWorkbookScopeOptions) => void;
  onWorkbookBusyChange: (held: boolean) => void;
}

export function createSummaryVegNotificationTracker(): SummaryVegNotificationTracker {
  return {
    lastViewError: '',
    lastPrefReadError: '',
    lastPrefError: '',
    notifiedPrefReceipts: 0,
    lastFieldListReadError: '',
  };
}

export function resolveEffectiveHierarchy(propHierarchy: string, stateHierarchy: string | undefined): string {
  return (
    (propHierarchy && propHierarchy !== 'None' ? propHierarchy : '') ||
    (stateHierarchy && stateHierarchy !== 'None' ? stateHierarchy : '') ||
    'None'
  );
}

export function resolveSummaryVegContextTag(project: string, getEffectiveHierarchy: () => string): string | undefined {
  if (typeof project === 'string' && project) return project;
  const h = getEffectiveHierarchy();
  return typeof h === 'string' && h !== 'None' ? h : undefined;
}

export function initSummaryVegEnvironmentalSession(
  owner: { contextId: string; project: string; projectPath: string; su: string; suPath: string },
  getEffectiveHierarchy: () => string,
  envDesk: {
    summaryEnvironmentalEnabled?: boolean;
    summaryEnvironmentalDesktop?: {
      session?: (owner: {
        contextId: string;
        project: string;
        projectPath: string;
        su: string;
        suPath: string;
      }) => SummaryEnvironmentalSession | SummaryEnvironmentalNumericSession | SummaryEnvironmentalLifeformSession;
    } | null;
  },
  sink: SummaryVegToastSink
): {
  canInspect: boolean;
  session:
    SummaryEnvironmentalSession | SummaryEnvironmentalNumericSession | SummaryEnvironmentalLifeformSession | null;
  error: string;
} {
  const envDesktop = envDesk?.summaryEnvironmentalDesktop ?? null;
  const canInspect = Boolean(
    envDesk?.summaryEnvironmentalEnabled &&
    envDesktop &&
    typeof envDesktop.session === 'function' &&
    owner.contextId &&
    owner.project &&
    owner.projectPath &&
    owner.su &&
    owner.su !== 'None' &&
    owner.su !== 'USysSuTableDynamic' &&
    owner.suPath
  );
  if (!canInspect || !envDesktop?.session) return { canInspect: false, session: null, error: '' };
  try {
    return { canInspect: true, session: envDesktop.session(owner), error: '' };
  } catch (cause) {
    const envErr = `Combined environmental inspection unavailable: ${String(cause)}`;
    sink.error('Summary Vegetation environmental inspection unavailable', envErr, {
      category: 'reports',
      source: 'Summary Vegetation',
      contextTag: resolveSummaryVegContextTag(owner.project, getEffectiveHierarchy),
    });
    return { canInspect: true, session: null, error: envErr };
  }
}

export function anySummaryVegPeerBusy(
  prefView: { busy?: boolean; blocked?: boolean; draftError?: string } | null | undefined,
  qualReadBusy: boolean,
  qualView: { busy?: boolean; blocked?: boolean; draftError?: string } | null | undefined,
  presReadBusy: boolean,
  presView: { busy?: boolean; blocked?: boolean; draftError?: string } | null | undefined,
  fieldListHeld: boolean,
  environmentalHeld: boolean,
  workbookHeld: boolean
): boolean {
  return (
    isPeerMutationHeld(false, prefView) ||
    Boolean(prefView?.draftError) ||
    isPeerMutationHeld(qualReadBusy, qualView) ||
    Boolean(qualView?.draftError) ||
    isPeerMutationHeld(presReadBusy, presView) ||
    Boolean(presView?.draftError) ||
    fieldListHeld ||
    environmentalHeld ||
    workbookHeld
  );
}

export function isPeerMutationHeld(
  readBusy: boolean,
  view: { busy?: boolean; blocked?: boolean } | null | undefined
): boolean {
  return readBusy || Boolean(view && (view.busy || view.blocked));
}

export function isPeerInvalid(
  view: { draftError?: string; authorityUnknown?: boolean; readError?: string } | null | undefined
): boolean {
  return Boolean(view?.draftError || view?.authorityUnknown || view?.readError);
}

function isSummaryVegScopeUnavailable(
  contextId: string,
  unitScope: 'su' | 'hierarchy' | 'none' | 'field',
  su: string,
  unitField: string
): boolean {
  return (
    !contextId ||
    (unitScope === 'su' && (su === 'None' || su === 'USysSuTableDynamic')) ||
    (unitScope === 'field' && !unitField.trim())
  );
}

function extractSavedPresentation(
  view: { initialized?: boolean; draft?: SavedPresentationDraft | null } | null | undefined
): SavedPresentationDraft | null {
  const d = view?.initialized ? view.draft : null;
  if (!d) return null;
  return {
    title: d.title,
    includeEnv: d.includeEnv,
    createSummary: d.createSummary,
    showCommon: d.showCommon,
    showGuide: d.showGuide,
    constancy: d.constancy,
  };
}

export function computeFieldListPeerValidation(
  preferenceInvalid: boolean,
  qualityInvalid: boolean,
  presentationInvalid: boolean
): string {
  if (preferenceInvalid) return 'Resolve Summary options validation.';
  if (qualityInvalid) return 'Resolve Summary quality validation.';
  if (presentationInvalid) return 'Resolve Summary presentation validation.';
  return '';
}

function isSummaryVegPreviewDisabled(input: {
  unavailableScope: boolean;
  viewBusy: boolean;
  operationHeld: boolean;
  fieldListHeld: boolean;
  preferenceHeld: boolean;
  preferenceInvalid: boolean;
  qualityMutationHeld: boolean;
  qualityUnavailable: boolean;
  presentationMutationHeld: boolean;
  presentationInvalid: boolean;
  viewDraftError: string;
  hasPreferences: boolean;
  prefInitialized: boolean;
}): boolean {
  return (
    input.unavailableScope ||
    input.viewBusy ||
    input.operationHeld ||
    input.fieldListHeld ||
    input.preferenceHeld ||
    input.preferenceInvalid ||
    input.qualityMutationHeld ||
    input.qualityUnavailable ||
    input.presentationMutationHeld ||
    input.presentationInvalid ||
    Boolean(input.viewDraftError) ||
    (input.hasPreferences && !input.prefInitialized)
  );
}

function isSummaryVegSavedPreviewDisabled(input: {
  contextId: string;
  su: string;
  suPath: string;
  viewBusy: boolean;
  operationHeld: boolean;
  fieldListHeld: boolean;
  preferenceHeld: boolean;
  qualityMutationHeld: boolean;
  presentationMutationHeld: boolean;
}): boolean {
  return (
    !input.contextId ||
    !input.su ||
    input.su === 'None' ||
    !input.suPath ||
    input.viewBusy ||
    input.operationHeld ||
    input.fieldListHeld ||
    input.preferenceHeld ||
    input.qualityMutationHeld ||
    input.presentationMutationHeld
  );
}

export function createSummaryVegServicePort(
  getContextId: () => string,
  reads: ReadRequests,
  vegSvc: Pick<
    typeof VegetationReportService,
    | 'PreviewSummaryVegetation'
    | 'PreviewSummaryVegetationClass'
    | 'PreviewSummaryVegetationGrouped'
    | 'PreviewSummaryVegetationGroupedDisplay'
    | 'PreviewSummaryVegetationConfigured'
    | 'PreviewSummaryVegetationWithPreferences'
  >
): SummaryVegetationPort {
  return {
    preview: (avg, disp) => reads.track(vegSvc.PreviewSummaryVegetation(getContextId(), avg, disp)),
    previewClass: (avg, disp, cls) => reads.track(vegSvc.PreviewSummaryVegetationClass(getContextId(), avg, disp, cls)),
    previewGrouped: (avg, grp) => reads.track(vegSvc.PreviewSummaryVegetationGrouped(getContextId(), avg, grp)),
    previewGroupedDisplay: (avg, grp, disp, cls) =>
      reads.track(vegSvc.PreviewSummaryVegetationGroupedDisplay(getContextId(), avg, grp, disp, cls)),
    previewConfigured: (reqJSON) => reads.track(vegSvc.PreviewSummaryVegetationConfigured(getContextId(), reqJSON)),
    previewWithPreferences: () => reads.track(vegSvc.PreviewSummaryVegetationWithPreferences(getContextId())),
    cancel: () => reads.cancelAll(),
    validationYield: () => new Promise((resolve) => setTimeout(resolve, 0)),
  };
}

export function syncSummaryVegToastState(
  sink: SummaryVegToastSink,
  tracker: SummaryVegNotificationTracker,
  input: {
    viewError: string;
    prefView:
      | {
          receipts?: Array<
            | { kind: 'known'; outcome: { committed: boolean; changed: boolean; errorMessage: string } }
            | { kind: 'unknown'; errorMessage: string }
          >;
          readError?: string;
          error?: string;
        }
      | null
      | undefined;
    fieldListReadError: string;
    contextTag: string | undefined;
  }
): void {
  const opts = { category: 'reports' as const, source: 'Summary Vegetation', contextTag: input.contextTag };
  if (input.viewError && input.viewError !== tracker.lastViewError) {
    sink.error('Summary Vegetation preview failed', input.viewError, opts);
  }
  tracker.lastViewError = input.viewError;

  const pv = input.prefView;
  if (pv) {
    const receipts = pv.receipts ?? [];
    if (receipts.length < tracker.notifiedPrefReceipts) tracker.notifiedPrefReceipts = 0;
    for (let i = tracker.notifiedPrefReceipts; i < receipts.length; i++) {
      const r = receipts[i];
      if (r.kind === 'known') {
        if (r.outcome.committed && !r.outcome.errorMessage) {
          sink.success(
            'Summary Vegetation options saved',
            r.outcome.changed ? 'Saved summary options.' : 'No option changes.',
            opts
          );
        } else if (r.outcome.committed) {
          sink.warning('Summary Vegetation options saved with warning', r.outcome.errorMessage, opts);
          tracker.lastPrefError = r.outcome.errorMessage;
        } else if (r.outcome.errorMessage) {
          sink.error('Summary Vegetation options save failed', r.outcome.errorMessage, opts);
          tracker.lastPrefError = r.outcome.errorMessage;
        } else {
          sink.info('Summary Vegetation options unchanged', 'No option changes were needed.', opts);
        }
      }
    }
    tracker.notifiedPrefReceipts = receipts.length;
    const pvReadErr = pv.readError ?? '';
    if (pvReadErr && pvReadErr !== tracker.lastPrefReadError) {
      sink.error('Summary Vegetation options load failed', pvReadErr, opts);
    }
    tracker.lastPrefReadError = pvReadErr;
    const pvErr = pv.error ?? '';
    if (pvErr && pvErr !== tracker.lastPrefError) {
      sink.error('Summary Vegetation options failed', pvErr, opts);
    }
    tracker.lastPrefError = pvErr;
  }

  if (input.fieldListReadError && input.fieldListReadError !== tracker.lastFieldListReadError) {
    sink.error('Summary Vegetation field list failed', input.fieldListReadError, opts);
  }
  tracker.lastFieldListReadError = input.fieldListReadError;
}

function buildSummaryVegWorkbookCalculation(input: {
  average: number;
  display: number;
  showClass: number;
  groupAndOrder: number;
  workbookConstancy: boolean;
  unitScope: 'su' | 'hierarchy' | 'none' | 'field';
  unitField: string;
  breakpointPolicy: 'lowest' | 'highest';
  hierarchyHeaderEnabled: boolean;
  effectiveCombineVariants: boolean;
  lumpTable: string;
  includeGoldstreamMetadata: boolean;
}): SummaryWorkbookCalculation {
  const {
    average,
    display,
    showClass,
    groupAndOrder,
    workbookConstancy,
    unitScope,
    unitField,
    breakpointPolicy,
    hierarchyHeaderEnabled,
    effectiveCombineVariants,
    lumpTable,
    includeGoldstreamMetadata,
  } = input;
  return {
    average,
    display: workbookConstancy ? 1 : display,
    showClass,
    ...(workbookConstancy
      ? { groupAndOrder: 13, constancy: true as const }
      : groupAndOrder !== 11
        ? { groupAndOrder }
        : {}),
    ...(unitScope !== 'su' ? { unitScope } : {}),
    ...(unitScope === 'field' && unitField.trim() ? { unitField: unitField.trim() } : {}),
    ...(unitScope === 'hierarchy' ? { breakpointPolicy } : {}),
    ...(hierarchyHeaderEnabled ? { hierarchyHeader: true } : {}),
    ...(effectiveCombineVariants ? { combineVariants: true } : {}),
    ...(lumpTable ? { lumpTable } : {}),
    ...(includeGoldstreamMetadata ? { includeGoldstreamMetadata: true } : {}),
  };
}

function buildSummaryVegConfiguredPayload(input: {
  unitScope: 'su' | 'hierarchy' | 'none' | 'field';
  unitField: string;
  hierarchyHeaderEnabled: boolean;
  breakpointPolicy: 'lowest' | 'highest';
  effectiveCombineVariants: boolean;
  lumpTable: string;
  average: number;
  display: number;
  showClass: number;
  groupAndOrder: number;
  showCommon: boolean;
  showGuide: boolean;
  workbookConstancy: boolean;
  includeGoldstreamMetadata: boolean;
}): string {
  const effectiveShowClass = input.display === 4 || input.display === 5 ? input.showClass || 1 : 0;
  const references =
    input.showCommon || input.showGuide ? { showCommon: input.showCommon, useGuideNames: input.showGuide } : undefined;
  return JSON.stringify({
    useSavedPreferences: false,
    unitScope: input.unitScope,
    ...(input.unitScope === 'field' ? { unitField: input.unitField.trim() } : {}),
    hierarchyHeader: input.hierarchyHeaderEnabled,
    ...(input.unitScope === 'hierarchy' ? { breakpointPolicy: input.breakpointPolicy } : {}),
    combineVariants: input.effectiveCombineVariants,
    ...(input.lumpTable ? { lumpTable: input.lumpTable } : {}),
    average: input.average,
    display: input.display,
    showClass: effectiveShowClass,
    ...(input.groupAndOrder !== 11 ? { groupAndOrder: input.groupAndOrder } : {}),
    ...(references ? { references } : {}),
    ...(input.workbookConstancy ? { constancy: true } : {}),
    includeGoldstreamMetadata: input.includeGoldstreamMetadata,
  });
}

export function normalizeExclusionSummaryPreviewData(raw: unknown): unknown {
  if (!raw || typeof raw !== 'object') return raw;
  const candidate = { ...(raw as Record<string, unknown>) };
  const hasRefs = !!candidate.references && typeof candidate.references === 'object';
  const refShowCommon = hasRefs && Boolean((candidate.references as Record<string, unknown>).showCommon);
  const grouped = typeof candidate.groupAndOrder === 'number' && candidate.groupAndOrder !== 11;
  if (hasRefs) {
    candidate.source = 'literal-normal-su-effective-references';
    candidate.ordering = refShowCommon
      ? 'literal-null-first-layer-species-common'
      : grouped
        ? 'literal-null-first-group-species'
        : 'literal-null-first-layer-species';
  } else {
    candidate.source = grouped ? 'literal-normal-su-grouped' : 'literal-normal-su-layer';
    candidate.ordering = grouped ? 'literal-null-first-group-species' : 'literal-null-first-layer-species';
  }
  return candidate;
}

export async function dispatchSummaryVegPreview(input: {
  sink: SummaryVegToastSink;
  contextTag: string | undefined;
  session: {
    show: (port: SummaryVegetationPort) => Promise<void>;
    showConfigured: (port: SummaryVegetationPort, req: string) => Promise<void>;
    view: () => { error: string };
  };
  port: SummaryVegetationPort;
  unitScope: 'su' | 'hierarchy' | 'none' | 'field';
  unitField: string;
  breakpointPolicy: 'lowest' | 'highest';
  combineVariants: boolean;
  lumpTable: string;
  includeGoldstreamMetadata: boolean;
  viewState: { average: number; display: number; showClass: number; groupAndOrder: number };
  presentationDraft:
    | {
        hierarchyHeader?: boolean;
        combineVariants?: boolean;
        showCommon?: boolean;
        showGuide?: boolean;
        constancy?: boolean;
      }
    | null
    | undefined;
  presentationInitialized: boolean;
  qualityEnforce: boolean;
}): Promise<void> {
  const hierarchyHeaderEnabled = !!input.presentationDraft?.hierarchyHeader;
  const effectiveCombineVariants = input.combineVariants || !!input.presentationDraft?.combineVariants;
  const workbookConstancy = input.presentationInitialized && input.presentationDraft?.constancy === true;
  const useConfigured =
    input.unitScope !== 'su' ||
    hierarchyHeaderEnabled ||
    effectiveCombineVariants ||
    input.lumpTable !== '' ||
    input.includeGoldstreamMetadata ||
    input.qualityEnforce;
  const payload = useConfigured
    ? buildSummaryVegConfiguredPayload({
        unitScope: input.unitScope,
        unitField: input.unitField,
        hierarchyHeaderEnabled,
        breakpointPolicy: input.breakpointPolicy,
        effectiveCombineVariants,
        lumpTable: input.lumpTable,
        average: input.viewState.average,
        display: input.viewState.display,
        showClass: input.viewState.showClass,
        groupAndOrder: input.viewState.groupAndOrder,
        showCommon: !!input.presentationDraft?.showCommon,
        showGuide: !!input.presentationDraft?.showGuide,
        workbookConstancy,
        includeGoldstreamMetadata: input.includeGoldstreamMetadata,
      })
    : '';
  await runSummaryVegPreviewAction(
    input.sink,
    input.contextTag,
    () => (!useConfigured ? input.session.show(input.port) : input.session.showConfigured(input.port, payload)),
    () => input.session.view().error
  );
}

export function isSummaryVegPrefBlocked(
  preferences: unknown,
  viewBusy: boolean,
  operationHeld: boolean,
  fieldListHeld: boolean,
  preferenceHeld: boolean,
  qualityMutationHeld: boolean,
  qualityInvalid: boolean,
  presentationMutationHeld: boolean,
  presentationInvalid: boolean
): boolean {
  return (
    !preferences ||
    viewBusy ||
    operationHeld ||
    fieldListHeld ||
    preferenceHeld ||
    qualityMutationHeld ||
    qualityInvalid ||
    presentationMutationHeld ||
    presentationInvalid
  );
}

export function syncSummaryVegPrefDraft(
  preferenceView:
    | { initialized?: boolean; draft: { groupBy: string; average: string; display: string; showClass: string } }
    | null
    | undefined,
  viewState: { busy: boolean; groupAndOrder: number; average: number; display: number; showClass: number },
  session: { edit: (avg: number, disp: number, show: number, group: number) => void }
): void {
  if (!preferenceView?.initialized || viewState.busy) return;
  const d = preferenceView.draft;
  const [group, average, display, show] = [
    Number(d.groupBy) + 10,
    Number(d.average),
    Number(d.display),
    Number(d.showClass),
  ];
  if (
    viewState.groupAndOrder !== group ||
    viewState.average !== average ||
    viewState.display !== display ||
    viewState.showClass !== show
  ) {
    session.edit(average, display, show, group);
  }
}

function packSummaryVegOptionsModel(
  owner: { contextId: string; project: string; projectPath: string; su: string; suPath: string },
  unavailableScope: boolean,
  editHeld: boolean,
  unitScope: 'su' | 'hierarchy' | 'none' | 'field',
  unitField: string,
  breakpointPolicy: 'lowest' | 'highest',
  lumpTable: string,
  lumpTables: string[],
  viewState: { groupAndOrder: number; display: number; showClass: number; average: number },
  combineVariants: boolean,
  includeGoldstreamMetadata: boolean
): SummaryVegOptionsModel {
  return {
    project: owner.project,
    projectPath: owner.projectPath,
    su: owner.su,
    suPath: owner.suPath,
    unavailableScope,
    contextId: owner.contextId,
    editHeld,
    unitScope,
    unitField,
    breakpointPolicy,
    lumpTable,
    lumpTables,
    groupAndOrder: viewState.groupAndOrder,
    display: viewState.display,
    showClass: viewState.showClass,
    average: viewState.average,
    combineVariants,
    includeGoldstreamMetadata,
  };
}

export async function runSummaryVegPrefLoad(input: {
  reads: ReadRequests;
  fetchPrefs: () => CancellableRead<SummaryVegetationPreferencesReview | null>;
  isCurrent: () => boolean;
  applyLoaded: (value: SummaryVegetationPreferencesReview | null) => void;
  rejectRead: (cause: unknown) => void;
  onSyncNotifications: () => void;
  onDone: () => void;
}): Promise<void> {
  try {
    const value = await input.reads.track(input.fetchPrefs());
    if (!input.isCurrent()) return;
    input.applyLoaded(value);
  } catch (cause) {
    if (input.isCurrent()) {
      input.rejectRead(cause);
      input.onSyncNotifications();
    }
  } finally {
    if (input.isCurrent()) input.onDone();
  }
}

function packSummaryVegPeerModel(
  owner: SummaryVegPeerModel['owner'],
  pref: readonly [SummaryVegPeerModel['preferences'], SummaryVegPeerModel['preferenceView'], boolean, boolean, boolean],
  qual: readonly [SummaryVegPeerModel['quality'], SummaryVegPeerModel['qualityView'], boolean, boolean, boolean],
  pres: readonly [
    SummaryVegPeerModel['presentation'],
    SummaryVegPeerModel['presentationView'],
    boolean,
    boolean,
    SummaryVegPeerModel['savedPresentation'],
  ],
  fl: readonly [boolean, boolean, SummaryVegPeerModel['fieldListState'], boolean, boolean, boolean, string, boolean],
  env: readonly [
    SummaryVegPeerModel['environmentalSession'],
    SummaryVegPeerModel['environmentalPort'],
    boolean,
    boolean,
    boolean,
  ],
  opsState: readonly [boolean, boolean, boolean, boolean, boolean, string, SummaryWorkbookCalculation]
): SummaryVegPeerModel {
  return {
    owner,
    preferences: pref[0],
    preferenceView: pref[1],
    preferenceReadBusy: pref[2],
    preferenceHeld: pref[3],
    preferenceInvalid: pref[4],
    quality: qual[0],
    qualityView: qual[1],
    qualityMutationHeld: qual[2],
    qualityInvalid: qual[3],
    qualityUnavailable: qual[4],
    presentation: pres[0],
    presentationView: pres[1],
    presentationMutationHeld: pres[2],
    presentationInvalid: pres[3],
    savedPresentation: pres[4],
    fieldListEnabled: fl[0],
    fieldListScopeAvailable: fl[1],
    fieldListState: fl[2],
    fieldListHeld: fl[3],
    fieldListBusy: fl[4],
    fieldListPeerDisabled: fl[5],
    fieldListPeerValidation: fl[6],
    fieldListEnabledFromPresentation: fl[7],
    environmentalSession: env[0],
    environmentalPort: env[1],
    environmentalNumericEnabled: env[2],
    environmentalLifeformEnabled: env[3],
    environmentalHeld: env[4],
    operationHeldProp: opsState[0],
    operationHeld: opsState[1],
    workbookHeld: opsState[2],
    unavailableScope: opsState[3],
    viewBusy: opsState[4],
    viewDraftError: opsState[5],
    calculation: opsState[6],
  };
}

export function deriveSummaryVegVm(input: {
  owner: SummaryVegPeerModel['owner'];
  editHeld: boolean;
  unitScope: 'su' | 'hierarchy' | 'none' | 'field';
  unitField: string;
  breakpointPolicy: 'lowest' | 'highest';
  combineVariants: boolean;
  lumpTable: string;
  lumpTables: string[];
  includeGoldstreamMetadata: boolean;
  viewState: {
    average: number;
    display: number;
    showClass: number;
    groupAndOrder: number;
    busy: boolean;
    draftError: string;
  };
  operationHeldProp: boolean;
  operationHeld: boolean;
  workbookHeld: boolean;
  environmentalHeld: boolean;
  fieldListHeld: boolean;
  fieldListBusy: boolean;
  preferences: SummaryVegPeerModel['preferences'];
  preferenceView: SummaryVegPeerModel['preferenceView'];
  preferenceReadBusy: boolean;
  preferenceHeld: boolean;
  preferenceInvalid: boolean;
  quality: SummaryVegPeerModel['quality'];
  qualityView: SummaryVegPeerModel['qualityView'];
  qualityMutationHeld: boolean;
  qualityInvalid: boolean;
  presentation: SummaryVegPeerModel['presentation'];
  presentationView: SummaryVegPeerModel['presentationView'];
  presentationMutationHeld: boolean;
  presentationInvalid: boolean;
  fieldListEnabled: boolean;
  fieldListScopeAvailable: boolean;
  fieldListState: SummaryVegPeerModel['fieldListState'];
  fieldListPeerDisabled: boolean;
  fieldListPeerValidation: string;
  fieldListEnabledFromPresentation: boolean;
  environmentalSession: SummaryVegPeerModel['environmentalSession'];
  envDesk: {
    summaryEnvironmentalPort?: SummaryEnvironmentalPort;
    summaryEnvironmentalNumericEnabled?: boolean;
    summaryEnvironmentalLifeformEnabled?: boolean;
  };
}) {
  const unavailableScope = isSummaryVegScopeUnavailable(
    input.owner.contextId,
    input.unitScope,
    input.owner.su,
    input.unitField
  );
  const workbookConstancy = !!input.presentationView?.initialized && input.presentationView.draft?.constancy === true;
  const hierarchyHeaderEnabled = !!input.presentationView?.draft?.hierarchyHeader;
  const effectiveCombineVariants = input.combineVariants || !!input.presentationView?.draft?.combineVariants;
  const qualityUnavailable = !!input.quality && (!input.qualityView?.saved || input.qualityInvalid);
  const savedPresentation = extractSavedPresentation(input.presentationView);
  const calcArgs = {
    average: input.viewState.average,
    display: input.viewState.display,
    showClass: input.viewState.showClass,
    groupAndOrder: input.viewState.groupAndOrder,
    workbookConstancy,
    unitScope: input.unitScope,
    unitField: input.unitField,
    breakpointPolicy: input.breakpointPolicy,
    hierarchyHeaderEnabled,
    effectiveCombineVariants,
    lumpTable: input.lumpTable,
    includeGoldstreamMetadata: input.includeGoldstreamMetadata,
  };
  const useConfigured =
    input.unitScope !== 'su' ||
    hierarchyHeaderEnabled ||
    effectiveCombineVariants ||
    input.lumpTable !== '' ||
    input.includeGoldstreamMetadata ||
    !!input.qualityView?.saved?.enforce;
  const calculation = buildSummaryVegWorkbookCalculation(calcArgs);
  const previewDisabled = isSummaryVegPreviewDisabled({
    unavailableScope,
    viewBusy: input.viewState.busy,
    operationHeld: input.operationHeld,
    fieldListHeld: input.fieldListHeld,
    preferenceHeld: input.preferenceHeld,
    preferenceInvalid: input.preferenceInvalid,
    qualityMutationHeld: input.qualityMutationHeld,
    qualityUnavailable,
    presentationMutationHeld: input.presentationMutationHeld,
    presentationInvalid: input.presentationInvalid,
    viewDraftError: input.viewState.draftError,
    hasPreferences: !!input.preferences,
    prefInitialized: !!input.preferenceView?.initialized,
  });
  const savedPreviewDisabled = isSummaryVegSavedPreviewDisabled({
    contextId: input.owner.contextId,
    su: input.owner.su,
    suPath: input.owner.suPath,
    viewBusy: input.viewState.busy,
    operationHeld: input.operationHeld,
    fieldListHeld: input.fieldListHeld,
    preferenceHeld: input.preferenceHeld,
    qualityMutationHeld: input.qualityMutationHeld,
    presentationMutationHeld: input.presentationMutationHeld,
  });
  const optionsModel = packSummaryVegOptionsModel(
    input.owner,
    unavailableScope,
    input.editHeld,
    input.unitScope,
    input.unitField,
    input.breakpointPolicy,
    input.lumpTable,
    input.lumpTables,
    input.viewState,
    input.combineVariants,
    input.includeGoldstreamMetadata
  );
  const peerModel = packSummaryVegPeerModel(
    input.owner,
    [input.preferences, input.preferenceView, input.preferenceReadBusy, input.preferenceHeld, input.preferenceInvalid],
    [input.quality, input.qualityView, input.qualityMutationHeld, input.qualityInvalid, qualityUnavailable],
    [
      input.presentation,
      input.presentationView,
      input.presentationMutationHeld,
      input.presentationInvalid,
      savedPresentation,
    ],
    [
      input.fieldListEnabled,
      input.fieldListScopeAvailable,
      input.fieldListState,
      input.fieldListHeld,
      input.fieldListBusy,
      input.fieldListPeerDisabled,
      input.fieldListPeerValidation,
      input.fieldListEnabledFromPresentation,
    ],
    [
      input.environmentalSession,
      input.envDesk.summaryEnvironmentalPort as SummaryEnvironmentalPort,
      Boolean(input.envDesk.summaryEnvironmentalNumericEnabled),
      Boolean(input.envDesk.summaryEnvironmentalLifeformEnabled),
      input.environmentalHeld,
    ],
    [
      input.operationHeldProp,
      input.operationHeld,
      input.workbookHeld,
      unavailableScope,
      input.viewState.busy,
      input.viewState.draftError,
      calculation,
    ]
  );
  return { calcArgs, useConfigured, previewDisabled, savedPreviewDisabled, optionsModel, peerModel };
}

export async function discoverSummaryVegLumpNames(
  reads: ReadRequests,
  discover: () => CancellableRead<Array<{ name?: string }> | null | undefined>,
  onNames: (names: string[]) => void,
  onError: (msg: string) => void
): Promise<void> {
  try {
    const discovered = await reads.track(discover());
    onNames(
      Array.from(
        new Set(
          (discovered ?? []).map((item: { name?: string }) => (item?.name ?? '').trim()).filter((n: string) => !!n)
        )
      )
    );
  } catch (cause) {
    onError(String(cause));
  }
}

export async function runSummaryVegPreviewAction(
  sink: SummaryVegToastSink,
  contextTag: string | undefined,
  run: () => Promise<void>,
  readError: () => string
): Promise<void> {
  const opts = { category: 'reports' as const, source: 'Summary Vegetation', contextTag };
  try {
    await run();
    const err = readError();
    if (err) sink.error('Summary Vegetation preview failed', err, opts);
  } catch (cause) {
    sink.error('Summary Vegetation preview failed', String(cause), opts);
  }
}
