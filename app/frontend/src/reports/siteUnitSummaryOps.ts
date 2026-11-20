import type {
  SiteUnitSpeciesListPreview,
  SiteUnitSpeciesListRequest,
  SiteUnitSummaryFullPreferences,
  SiteUnitSummaryOptions,
  SiteUnitSummaryPreview,
} from '../../bindings/github.com/boostao/vpro/app';
import type { CancellableRead, ReadRequests } from '../shared/readRequests';
import type { validateSiteUnitSummary, SiteUnitSummaryMode, ValidatedSiteUnitSummary } from './siteUnitSummary';
import type { SummaryFullPreferenceValues } from './siteUnitSummaryPreferences';
import type { validateSummarySpecies, ValidatedSummarySpecies } from './siteUnitSummarySpecies';
import type { ExtendedSummaryWorkbookOptions } from './siteUnitSummaryExtendedWorkbook';

export interface SiteUnitToastSink {
  success: (title: string, message: string, opts?: Record<string, unknown>) => void;
  warning: (title: string, message: string, opts?: Record<string, unknown>) => void;
  error: (title: string, message: string, opts?: Record<string, unknown>) => void;
  info: (title: string, message: string, opts?: Record<string, unknown>) => void;
}

export interface SiteUnitNotificationTracker {
  lastPrefError: string;
  notifiedPrefReceipts: number;
  lastFullPrefError: string;
  notifiedFullPrefReceipts: number;
  lastSpeciesError: string;
}

export function createSiteUnitNotificationTracker(): SiteUnitNotificationTracker {
  return {
    lastPrefError: '',
    notifiedPrefReceipts: 0,
    lastFullPrefError: '',
    notifiedFullPrefReceipts: 0,
    lastSpeciesError: '',
  };
}

export function isSiteUnitScopeTypeAllowed(effectiveType: number, su: string): boolean {
  return (
    effectiveType === 3 ||
    (su !== 'None' && (effectiveType === 2 || (effectiveType === 1 && su !== 'USysSuTableDynamic')))
  );
}

export function isSiteUnitSummaryReady(
  method: number | null,
  effectiveType: number,
  su: string,
  authorityUnknown: boolean | undefined
): boolean {
  return (
    (method === 1 || method === 2) &&
    [1, 2, 3].includes(effectiveType) &&
    isSiteUnitScopeTypeAllowed(effectiveType, su) &&
    !authorityUnknown
  );
}

export function isSiteUnitPreferenceHeld(
  prefView: { busy?: boolean; blocked?: boolean; authorityUnknown?: boolean; draftError?: string } | null | undefined,
  fullView: { busy?: boolean; blocked?: boolean; authorityUnknown?: boolean; draftError?: string } | null | undefined
): boolean {
  const shortHeld = Boolean(
    prefView && (prefView.busy || prefView.blocked || prefView.authorityUnknown || prefView.draftError)
  );
  const fullHeld = Boolean(
    fullView && (fullView.busy || fullView.blocked || fullView.authorityUnknown || fullView.draftError)
  );
  return shortHeld || fullHeld;
}

export function buildExtendedSummaryOptions(input: {
  method: number | null;
  speciesBarrier: boolean;
  speciesEnabled: boolean;
  mode: SiteUnitSummaryMode;
  buildSpeciesRequest?: (method: number, mode: SiteUnitSummaryMode) => SiteUnitSpeciesListRequest;
}): ExtendedSummaryWorkbookOptions | null {
  const { method, speciesBarrier, speciesEnabled, mode, buildSpeciesRequest } = input;
  if ((method !== 1 && method !== 2) || speciesBarrier) return null;
  if (speciesEnabled && buildSpeciesRequest) {
    return { ...buildSpeciesRequest(method, mode), includeSpecies: 1 };
  }
  if (mode === 'lifeform') {
    return {
      method,
      orderBy: 2,
      includeSpecies: 0,
      coverCalculation: 1,
      andOr: 1,
      presenceGreaterThan: 0,
      coverGreaterThan: 0,
    };
  }
  if (mode === 'strata') {
    return {
      method,
      orderBy: 3,
      includeSpecies: 1,
      coverCalculation: 1,
      andOr: 1,
      presenceGreaterThan: 0,
      coverGreaterThan: 0,
    };
  }
  return null;
}

export function emitSiteUnitToastError(sink: SiteUnitToastSink, project: string, title: string, msg: string): string {
  sink.error(title, msg, {
    category: 'reports',
    source: 'Summary Environment',
    contextTag: (typeof project === 'string' && project) || undefined,
  });
  return msg;
}

export function syncSiteUnitSpeciesToast(
  sink: SiteUnitToastSink,
  tracker: SiteUnitNotificationTracker,
  err: string,
  project: string
): void {
  if (err && err !== tracker.lastSpeciesError) {
    sink.error('Summary Environment species criteria invalid', err, {
      category: 'reports',
      source: 'Summary Environment',
      contextTag: (typeof project === 'string' && project) || undefined,
    });
  }
  tracker.lastSpeciesError = err;
}

function emitReceiptToast(
  sink: SiteUnitToastSink,
  receipt: { kind: string; outcome?: { committed: boolean; changed: boolean; errorMessage: string } },
  label: string,
  changedMsg: string,
  project: string,
  onErr: (msg: string) => void
): void {
  if (receipt.kind !== 'known' || !receipt.outcome) return;
  const opts = {
    category: 'reports' as const,
    source: 'Summary Environment',
    contextTag: (typeof project === 'string' && project) || undefined,
  };
  if (receipt.outcome.committed && !receipt.outcome.errorMessage) {
    sink.success(`${label} saved`, receipt.outcome.changed ? changedMsg : 'No option changes.', opts);
  } else if (receipt.outcome.committed) {
    sink.warning(`${label} saved with warning`, receipt.outcome.errorMessage, opts);
    onErr(receipt.outcome.errorMessage);
  } else if (receipt.outcome.errorMessage) {
    sink.error(`${label} save failed`, receipt.outcome.errorMessage, opts);
    onErr(receipt.outcome.errorMessage);
  } else {
    sink.info(`${label} unchanged`, 'No option changes were needed.', opts);
  }
}

export function syncSiteUnitPreferenceToasts(
  sink: SiteUnitToastSink,
  tracker: SiteUnitNotificationTracker,
  view:
    | {
        receipts?: Array<{ kind: string; outcome?: { committed: boolean; changed: boolean; errorMessage: string } }>;
        error?: string;
      }
    | null
    | undefined,
  project: string,
  kind: 'short' | 'full'
): void {
  if (!view) return;
  const receipts = view.receipts ?? [];
  const isFull = kind === 'full';
  const label = isFull ? 'Summary Environment full preferences' : 'Summary Environment options';
  const changedMsg = isFull ? 'Saved all summary preferences.' : 'Saved summary preferences.';
  let count = isFull ? tracker.notifiedFullPrefReceipts : tracker.notifiedPrefReceipts;
  if (receipts.length < count) count = 0;
  for (let i = count; i < receipts.length; i++) {
    emitReceiptToast(sink, receipts[i], label, changedMsg, project, (m) => {
      if (isFull) tracker.lastFullPrefError = m;
      else tracker.lastPrefError = m;
    });
  }
  if (isFull) tracker.notifiedFullPrefReceipts = receipts.length;
  else tracker.notifiedPrefReceipts = receipts.length;

  const err = view.error ?? '';
  const prevErr = isFull ? tracker.lastFullPrefError : tracker.lastPrefError;
  if (err && err !== prevErr) {
    sink.error(`${label} failed`, err, {
      category: 'reports',
      source: 'Summary Environment',
      contextTag: (typeof project === 'string' && project) || undefined,
    });
  }
  if (isFull) tracker.lastFullPrefError = err;
  else tracker.lastPrefError = err;
}

export function buildSiteUnitFullDraftPatch(input: {
  method: number | null;
  siteUnitType: number | null;
  fallbackSiteUnitType: number;
  mode: SiteUnitSummaryMode;
  speciesView: {
    enabled: boolean;
    error: string;
    coverCalculation: number;
    andOr: number;
    presenceGreaterThan: string;
    coverGreaterThan: string;
  } | null;
}): Partial<SummaryFullPreferenceValues> | null {
  const { method, siteUnitType, fallbackSiteUnitType, mode, speciesView } = input;
  if (method !== 1 && method !== 2) return null;
  const orderBy = mode === 'layer' ? 1 : mode === 'lifeform' ? 2 : 3;
  const nextPatch: Partial<SummaryFullPreferenceValues> = {
    method,
    siteUnitType: [1, 2, 3].includes(siteUnitType ?? 0) ? (siteUnitType as number) : fallbackSiteUnitType,
    includeSpecies: speciesView?.enabled ? 1 : 0,
    orderBy,
  };
  if (speciesView && !speciesView.error) {
    nextPatch.coverCalculation = speciesView.coverCalculation;
    nextPatch.andOr = speciesView.andOr;
    const pNum = Number(speciesView.presenceGreaterThan);
    const cNum = Number(speciesView.coverGreaterThan);
    if (Number.isSafeInteger(pNum) && pNum >= 0 && pNum <= 32767) nextPatch.presenceGreaterThan = pNum;
    if (Number.isSafeInteger(cNum) && cNum >= 0 && cNum <= 32767) nextPatch.coverGreaterThan = cNum;
  }
  return nextPatch;
}

export function applySiteUnitFullValuesToCriteria(
  values: SummaryFullPreferenceValues,
  criteria: {
    editChoice: (field: 'coverCalculation' | 'andOr', value: number) => void;
    editText: (field: 'presenceGreaterThan' | 'coverGreaterThan', value: string) => void;
    view: () => { enabled: boolean };
    setEnabled: (enabled: boolean) => void;
  } | null
): SiteUnitSummaryMode {
  if (criteria) {
    criteria.editChoice('coverCalculation', values.coverCalculation);
    criteria.editChoice('andOr', values.andOr);
    criteria.editText('presenceGreaterThan', String(values.presenceGreaterThan));
    criteria.editText('coverGreaterThan', String(values.coverGreaterThan));
    if (criteria.view().enabled !== (values.includeSpecies === 1)) criteria.setEnabled(values.includeSpecies === 1);
  }
  return values.orderBy === 2 ? 'lifeform' : values.orderBy === 3 ? 'strata' : 'layer';
}

export function validateSiteUnitPreviewResponse(input: {
  value: unknown;
  owner: { contextId: string; project: string; projectPath: string; su: string; suPath: string };
  requestedMethod: number;
  requestedMode: SiteUnitSummaryMode;
  allowConfigured: boolean;
  speciesRequest: SiteUnitSpeciesListRequest | null;
  validators: {
    validateSiteUnitSummary: typeof validateSiteUnitSummary;
    validateSummarySpecies?: typeof validateSummarySpecies;
  };
}): { preview: ValidatedSiteUnitSummary; speciesPreview: ValidatedSummarySpecies | null } {
  const { value, owner, requestedMethod, requestedMode, allowConfigured, speciesRequest, validators } = input;
  if (speciesRequest) {
    const rawSp = value as SiteUnitSpeciesListPreview;
    const sp = allowConfigured
      ? validators.validateSummarySpecies!(rawSp, owner, speciesRequest, true)
      : validators.validateSummarySpecies!(rawSp, owner, speciesRequest);
    return { preview: sp.environment, speciesPreview: sp };
  }
  const rawEnv = value as SiteUnitSummaryPreview;
  const env = allowConfigured
    ? validators.validateSiteUnitSummary(
        rawEnv,
        owner.contextId,
        owner.project,
        owner.projectPath,
        owner.su,
        owner.suPath,
        requestedMethod,
        requestedMode,
        true
      )
    : validators.validateSiteUnitSummary(
        rawEnv,
        owner.contextId,
        owner.project,
        owner.projectPath,
        owner.su,
        owner.suPath,
        requestedMethod,
        requestedMode
      );
  return { preview: env, speciesPreview: null };
}

export interface SiteUnitActionBarModel {
  su: string;
  siteUnitType: number | null;
  busy: boolean;
  workbookBusy: boolean;
  speciesBarrier: boolean;
  ready: boolean;
  hasPreferences: boolean;
  hasFullPreferences: boolean;
  preferenceView: {
    busy?: boolean;
    blocked?: boolean;
    draftError?: string;
    saved?: unknown;
    draft?: unknown;
    receipts?: Array<{ kind: string; errorMessage?: string }>;
  } | null;
  fullPreferenceView: { busy?: boolean; blocked?: boolean; draftError?: string; saved?: unknown } | null;
}

export interface SiteUnitActionBarHandlers {
  onSavePreferences: () => void;
  onUndoPreferences: () => void;
  onSelectNormalSU: () => void;
  onAcknowledgePreferences: () => void;
  onLoadFullPreferences: () => void;
  onSaveFullPreferences: () => void;
  onAcknowledgeFullPreferences: () => void;
}

export type SiteUnitBarFlags = readonly [
  busy: boolean,
  workbookBusy: boolean,
  preferenceBarrier: boolean,
  speciesBarrier: boolean,
  ready: boolean,
];

export function packFieldsetsModel(
  su: string,
  mode: SiteUnitSummaryMode,
  siteUnitType: number | null,
  method: number | null,
  flags: SiteUnitBarFlags,
  preferenceView: { busy?: boolean; blocked?: boolean } | null,
  speciesView: {
    enabled: boolean;
    error: string;
    coverCalculation: number;
    andOr: number;
    presenceGreaterThan: string;
    coverGreaterThan: string;
  } | null
) {
  const [busy, workbookBusy, preferenceBarrier, speciesBarrier, ready] = flags;
  return {
    su,
    mode,
    siteUnitType,
    method,
    busy,
    workbookBusy,
    preferenceBarrier,
    speciesBarrier,
    ready,
    preferenceView,
    speciesView,
  };
}

export function packActionBarModel(
  su: string,
  siteUnitType: number | null,
  flags: SiteUnitBarFlags,
  prefs: readonly [
    unknown,
    unknown,
    SiteUnitActionBarModel['preferenceView'],
    SiteUnitActionBarModel['fullPreferenceView'],
  ]
): SiteUnitActionBarModel {
  const [busy, workbookBusy, , speciesBarrier, ready] = flags;
  return {
    su,
    siteUnitType,
    busy,
    workbookBusy,
    speciesBarrier,
    ready,
    hasPreferences: Boolean(prefs[0]),
    hasFullPreferences: Boolean(prefs[1]),
    preferenceView: prefs[2],
    fullPreferenceView: prefs[3],
  };
}

export async function runSiteUnitPrefSave(
  saveFn: () => Promise<void>,
  onSync: () => void,
  onError: (msg: string) => void
): Promise<void> {
  try {
    await saveFn();
    onSync();
  } catch (cause) {
    onError(String(cause));
  }
}

export async function runSiteUnitShowReport(input: {
  reads: ReadRequests;
  fetchPreview: () => CancellableRead<unknown>;
  isCurrent: () => boolean;
  validate: (value: unknown) => { preview: ValidatedSiteUnitSummary; speciesPreview: ValidatedSummarySpecies | null };
  onSuccess: (res: { preview: ValidatedSiteUnitSummary; speciesPreview: ValidatedSummarySpecies | null }) => void;
  onError: (msg: string) => void;
  onDone: () => void;
}): Promise<void> {
  try {
    const value = await input.reads.track(input.fetchPreview());
    if (!input.isCurrent()) return;
    input.onSuccess(input.validate(value));
  } catch (cause) {
    if (input.isCurrent()) input.onError(`Summary Environment report unavailable: ${String(cause)}`);
  } finally {
    if (input.isCurrent()) input.onDone();
  }
}

export async function runSiteUnitCombinedPrefLoad(input: {
  reads: ReadRequests;
  su: string;
  fetchFull: (() => CancellableRead<SiteUnitSummaryFullPreferences | null>) | null;
  applyFull: (val: SiteUnitSummaryFullPreferences) => void;
  fetchShort: () => CancellableRead<SiteUnitSummaryOptions | null>;
  applyShort: (val: SiteUnitSummaryOptions | null) => void;
  applyFallbackDraft: () => void;
  isCurrent: () => boolean;
  onError: (msg: string) => void;
  onDone: () => void;
}): Promise<void> {
  try {
    if (input.fetchFull) {
      try {
        const fullValue = await input.reads.track(input.fetchFull());
        if (!input.isCurrent()) return;
        if (fullValue) input.applyFull(fullValue);
      } catch {
        // Fallback to two-key summary preferences when mocked or partial.
      }
    }
    if (input.su !== 'None') {
      const value = await input.reads.track(input.fetchShort());
      if (!input.isCurrent()) return;
      input.applyShort(value);
    } else {
      input.applyFallbackDraft();
    }
  } catch (cause) {
    if (input.isCurrent()) input.onError(`Saved summary options unavailable: ${String(cause)}`);
  } finally {
    if (input.isCurrent()) input.onDone();
  }
}

export async function runSiteUnitOptionsLoad(input: {
  reads: ReadRequests;
  fetchOptions: () => CancellableRead<SiteUnitSummaryOptions | null>;
  isCurrent: () => boolean;
  validate: (value: SiteUnitSummaryOptions | null) => { method: number; siteUnitType: number };
  su: string;
  onConfigured: (method: number, siteUnitType: number, ready: boolean) => void;
  onIneligible: (msg: string) => void;
  onError: (msg: string) => void;
  onDone: () => void;
}): Promise<void> {
  try {
    const value = await input.reads.track(input.fetchOptions());
    if (!input.isCurrent()) return;
    const configured = input.validate(value);
    const ready = isSiteUnitScopeTypeAllowed(configured.siteUnitType, input.su);
    input.onConfigured(configured.method, configured.siteUnitType, ready);
    if (!ready) {
      input.onIneligible(
        'Select a Site Unit table in the sidebar, or choose Hierarchy (~) Breakpoints or Field-Derived Units.'
      );
    }
  } catch (cause) {
    if (input.isCurrent()) input.onError(`Summary options unavailable: ${String(cause)}`);
  } finally {
    if (input.isCurrent()) input.onDone();
  }
}

export async function runSiteUnitFullPreferencesLoad(input: {
  reads: ReadRequests;
  fetchFull: () => CancellableRead<SiteUnitSummaryFullPreferences | null>;
  isCurrent: () => boolean;
  applyLoaded: (value: SiteUnitSummaryFullPreferences) => boolean;
  onApplied: (values: SummaryFullPreferenceValues) => void;
  onError: (msg: string) => void;
  onDone: () => void;
}): Promise<void> {
  try {
    const fullValue = await input.reads.track(input.fetchFull());
    if (!input.isCurrent()) return;
    if (fullValue && input.applyLoaded(fullValue)) input.onApplied(fullValue.values);
  } catch (cause) {
    if (input.isCurrent()) input.onError(`Saved summary preferences unavailable: ${String(cause)}`);
  } finally {
    if (input.isCurrent()) input.onDone();
  }
}
