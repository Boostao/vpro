import { registerContextDisposer } from '../shared/contextSessionRegistry';
import { formatError } from '../shared/readRequests';
import type {
  SiteUnitSummaryFullPreferences,
  SiteUnitSummaryOptions,
  SiteUnitSummaryPreferencesOutcome,
} from '../../bindings/github.com/boostao/vpro/app';
import type { SiteUnitSummaryFullPreferenceValues } from '../../bindings/github.com/boostao/vpro/app/internal/envreport/models';
import { ownedScope, type ProjectSUScope as GoogleEarthScope } from '../shared/scope';
import { wellFormedUTF16 } from '../entry/qualityEditor';
import { validateSiteUnitSummaryOptions } from './siteUnitSummary';

interface SummaryPreferenceValues {
  method: number;
  siteUnitType: number;
}
interface SummaryPreferenceRequest {
  expected: SummaryPreferenceValues;
  proposed: SummaryPreferenceValues;
}
type Receipt =
  | { kind: 'known'; request: SummaryPreferenceRequest; outcome: SiteUnitSummaryPreferencesOutcome }
  | { kind: 'unknown'; request: SummaryPreferenceRequest; errorMessage: string };
interface View {
  draft: SummaryPreferenceValues | null;
  saved: SummaryPreferenceValues | null;
  busy: boolean;
  blocked: boolean;
  authorityUnknown: boolean;
  error: string;
  draftError: string;
  receipts: Receipt[];
}
const equal = (a: SummaryPreferenceValues, b: SummaryPreferenceValues) =>
  a.method === b.method && a.siteUnitType === b.siteUnitType;
const supported = (value: SummaryPreferenceValues) => [1, 2].includes(value.method) && value.siteUnitType === 1;
export class SiteUnitSummaryPreferencesSession {
  private state: View = {
    draft: null,
    saved: null,
    busy: false,
    blocked: false,
    authorityUnknown: false,
    error: '',
    draftError: '',
    receipts: [],
  };
  private listeners = new Set<() => void>();
  private generation = 0;
  constructor(private readonly scope: GoogleEarthScope) {
    this.scope = structuredClone(scope);
  }
  view(): View {
    return structuredClone(this.state);
  }
  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    listener();
    return () => this.listeners.delete(listener);
  }
  private notify() {
    for (const listener of this.listeners) listener();
  }
  private unlocked() {
    if (this.state.busy || this.state.blocked)
      throw new Error('Wait for and acknowledge the summary preference outcome first.');
  }
  cancelLoad() {
    this.generation++;
  }
  beginLoad(): number {
    this.unlocked();
    return ++this.generation;
  }
  applyLoaded(value: SiteUnitSummaryOptions | null, generation: number): boolean {
    if (generation !== this.generation) return false;
    this.unlocked();
    const source = validateSiteUnitSummaryOptions(
      value,
      this.scope.contextId,
      this.scope.project,
      this.scope.projectPath,
      this.scope.su,
      this.scope.suPath
    );
    this.cancelLoad();
    this.state.saved = { method: source.method, siteUnitType: source.siteUnitType };
    this.state.draft = structuredClone(this.state.saved);
    this.state.authorityUnknown = false;
    this.state.error = '';
    this.state.draftError = '';
    this.notify();
    return true;
  }
  editMethod(method: number) {
    this.unlocked();
    if (!this.state.draft) throw new Error('Load saved summary options before editing.');
    this.cancelLoad();
    this.state.draft.method = method;
    this.state.draftError = [1, 2].includes(method) ? '' : 'Correct the summary method or Undo the preference draft.';
    this.notify();
  }
  selectNormalSU() {
    this.unlocked();
    if (!this.state.draft) throw new Error('Load saved summary options before selecting normal SU.');
    this.cancelLoad();
    this.state.draft.siteUnitType = 1;
    this.notify();
  }
  undo() {
    this.unlocked();
    if (!this.state.saved) throw new Error('Undo requires known owned saved options; explicitly Load first.');
    this.cancelLoad();
    this.state.draft = structuredClone(this.state.saved);
    this.state.draftError = '';
    this.notify();
  }
  async save(
    port: (request: SummaryPreferenceRequest) => PromiseLike<SiteUnitSummaryPreferencesOutcome | null>
  ): Promise<void> {
    this.unlocked();
    if (!this.state.saved || !this.state.draft) throw new Error('Explicitly Load saved summary options before saving.');
    if (!supported(this.state.draft) || this.state.draftError)
      throw new Error('Only a valid normal-SU method can be saved; correct the draft first.');
    const request = structuredClone({ expected: this.state.saved, proposed: this.state.draft });
    this.cancelLoad();
    this.state.busy = true;
    this.state.blocked = true;
    this.state.error = '';
    this.notify();
    try {
      const outcome = await port(structuredClone(request));
      const changed = !equal(request.expected, request.proposed);
      if (
        !outcome ||
        outcome.contextId !== this.scope.contextId ||
        typeof outcome.changed !== 'boolean' ||
        typeof outcome.committed !== 'boolean' ||
        outcome.changed !== outcome.committed ||
        typeof outcome.errorMessage !== 'string' ||
        !wellFormedUTF16(outcome.errorMessage) ||
        outcome.errorMessage.includes('\0') ||
        (outcome.committed && !changed) ||
        (!outcome.errorMessage && outcome.committed !== changed)
      ) {
        throw new Error('Incomplete or contradictory summary preference acknowledgement.');
      }
      this.state.receipts.push({ kind: 'known', request: structuredClone(request), outcome: structuredClone(outcome) });
      this.state.error = outcome.errorMessage;
      if (outcome.committed || !outcome.errorMessage) this.state.saved = structuredClone(request.proposed);
    } catch (cause) {
      this.state.error = `Summary preference outcome unknown. Do not replay; acknowledge and explicitly Load before another Save: ${formatError(cause)}`;
      this.state.saved = null;
      this.state.authorityUnknown = true;
      this.state.receipts.push({ kind: 'unknown', request: structuredClone(request), errorMessage: this.state.error });
    } finally {
      this.state.busy = false;
      this.notify();
    }
  }
  acknowledge() {
    if (this.state.busy) throw new Error('Summary preference Save cannot be cancelled; wait for its outcome.');
    this.state.blocked = false;
    this.notify();
  }
}
const sessions = new Map<string, { scope: GoogleEarthScope; session: SiteUnitSummaryPreferencesSession }>();
export function siteUnitSummaryPreferencesSession(scope: GoogleEarthScope): SiteUnitSummaryPreferencesSession {
  const previous = sessions.get(scope.contextId);
  if (previous) {
    if (!ownedScope(previous.scope, scope))
      throw new Error('Summary preference drafts/receipts belong to different owned paths.');
    return previous.session;
  }
  const owner = structuredClone(scope),
    session = new SiteUnitSummaryPreferencesSession(owner);
  sessions.set(owner.contextId, { scope: owner, session });
  return session;
}

export type SummaryFullPreferenceValues = SiteUnitSummaryFullPreferenceValues;
interface SummaryFullPreferenceRequest {
  expected: SummaryFullPreferenceValues;
  proposed: SummaryFullPreferenceValues;
}
type FullReceipt =
  | { kind: 'known'; request: SummaryFullPreferenceRequest; outcome: SiteUnitSummaryPreferencesOutcome }
  | { kind: 'unknown'; request: SummaryFullPreferenceRequest; errorMessage: string };
interface FullView {
  draft: SummaryFullPreferenceValues | null;
  saved: SummaryFullPreferenceValues | null;
  busy: boolean;
  blocked: boolean;
  authorityUnknown: boolean;
  error: string;
  draftError: string;
  receipts: FullReceipt[];
}
const fullKeys: (keyof SummaryFullPreferenceValues)[] = [
  'method',
  'siteUnitType',
  'includeSpecies',
  'orderBy',
  'coverCalculation',
  'andOr',
  'presenceGreaterThan',
  'coverGreaterThan',
];
const fullEqual = (a: SummaryFullPreferenceValues, b: SummaryFullPreferenceValues) =>
  fullKeys.every((key) => a[key] === b[key]);

function validateSummaryFullPreferenceValues(value: unknown, su: string): string {
  if (!value || typeof value !== 'object') return 'Full summary preferences are missing.';
  const v = value as Record<string, unknown>;
  if (![1, 2].includes(v.method as number)) return 'Summary method must be Mean (1) or Interquartile (2).';
  if (![1, 2, 3].includes(v.siteUnitType as number))
    return 'Site-unit type must be Normal SU (1), Hierarchy (~) (2), or Field-Derived (3).';
  if (v.siteUnitType === 1 && su === 'None')
    return 'Normal SU (1) requires an active selected SU; choose Hierarchy (~) or Field-Derived instead.';
  if (![0, 1].includes(v.includeSpecies as number)) return 'Include species must be 0 or 1.';
  if (![1, 2, 3].includes(v.orderBy as number)) return 'OrderBy must be Layer (1), Lifeform (2), or Strata A-D (3).';
  if (![1, 2].includes(v.coverCalculation as number))
    return 'Cover calculation must be All plots (1) or Present values (2).';
  if (![1, 2].includes(v.andOr as number)) return 'Criteria combination must be AND (1) or OR (2).';
  for (const [field, label] of [
    ['presenceGreaterThan', 'Presence threshold'],
    ['coverGreaterThan', 'Cover threshold'],
  ] as const) {
    const num = v[field];
    if (!Number.isSafeInteger(num) || (num as number) < 0 || (num as number) > 32767) {
      return `${label} must be an integer between 0 and 32767.`;
    }
  }
  return '';
}

class SiteUnitSummaryFullPreferencesSession {
  private state: FullView = {
    draft: null,
    saved: null,
    busy: false,
    blocked: false,
    authorityUnknown: false,
    error: '',
    draftError: '',
    receipts: [],
  };
  private listeners = new Set<() => void>();
  private generation = 0;
  constructor(private readonly scope: GoogleEarthScope) {
    this.scope = structuredClone(scope);
  }
  view(): FullView {
    return structuredClone(this.state);
  }
  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    listener();
    return () => this.listeners.delete(listener);
  }
  private notify() {
    for (const listener of this.listeners) listener();
  }
  private unlocked() {
    if (this.state.busy || this.state.blocked)
      throw new Error('Wait for and acknowledge the full summary preference outcome first.');
  }
  cancelLoad() {
    this.generation++;
  }
  beginLoad(): number {
    this.unlocked();
    return ++this.generation;
  }
  applyLoaded(value: SiteUnitSummaryFullPreferences | null, generation: number): boolean {
    if (generation !== this.generation) return false;
    this.unlocked();
    if (
      !value ||
      value.contextId !== this.scope.contextId ||
      value.project !== this.scope.project ||
      value.projectPath !== this.scope.projectPath ||
      value.su !== this.scope.su ||
      value.suPath !== this.scope.suPath ||
      !value.values
    ) {
      throw new Error('Saved full summary preferences belong to another owned context; no defaults applied.');
    }
    const err = validateSummaryFullPreferenceValues(value.values, this.scope.su);
    if (err && value.values.siteUnitType !== 1) throw new Error(err);
    this.cancelLoad();
    this.state.saved = structuredClone(value.values);
    this.state.draft = structuredClone(value.values);
    this.state.authorityUnknown = false;
    this.state.error = '';
    this.state.draftError = err;
    this.notify();
    return true;
  }
  edit(patch: Partial<SummaryFullPreferenceValues>) {
    this.unlocked();
    if (!this.state.draft) throw new Error('Load full summary preferences before editing.');
    this.cancelLoad();
    this.state.draft = { ...this.state.draft, ...patch };
    this.state.draftError = validateSummaryFullPreferenceValues(this.state.draft, this.scope.su);
    this.notify();
  }
  undo() {
    this.unlocked();
    if (!this.state.saved) throw new Error('Undo requires known owned full saved preferences; explicitly Load first.');
    this.cancelLoad();
    this.state.draft = structuredClone(this.state.saved);
    this.state.draftError = validateSummaryFullPreferenceValues(this.state.draft, this.scope.su);
    this.notify();
  }
  async save(
    port: (request: SummaryFullPreferenceRequest) => PromiseLike<SiteUnitSummaryPreferencesOutcome | null>
  ): Promise<void> {
    this.unlocked();
    if (!this.state.saved || !this.state.draft)
      throw new Error('Explicitly Load full summary preferences before saving.');
    const draftErr = validateSummaryFullPreferenceValues(this.state.draft, this.scope.su);
    if (draftErr || this.state.draftError) throw new Error(draftErr || this.state.draftError);
    const request = structuredClone({ expected: this.state.saved, proposed: this.state.draft });
    this.cancelLoad();
    this.state.busy = true;
    this.state.blocked = true;
    this.state.error = '';
    this.notify();
    try {
      const outcome = await port(structuredClone(request));
      const changed = !fullEqual(request.expected, request.proposed);
      if (
        !outcome ||
        outcome.contextId !== this.scope.contextId ||
        typeof outcome.changed !== 'boolean' ||
        typeof outcome.committed !== 'boolean' ||
        outcome.changed !== outcome.committed ||
        typeof outcome.errorMessage !== 'string' ||
        !wellFormedUTF16(outcome.errorMessage) ||
        outcome.errorMessage.includes('\0') ||
        (outcome.committed && !changed) ||
        (!outcome.errorMessage && outcome.committed !== changed)
      ) {
        throw new Error('Incomplete or contradictory full summary preference acknowledgement.');
      }
      this.state.receipts.push({ kind: 'known', request: structuredClone(request), outcome: structuredClone(outcome) });
      this.state.error = outcome.errorMessage;
      if (outcome.committed || !outcome.errorMessage) this.state.saved = structuredClone(request.proposed);
    } catch (cause) {
      this.state.error = `Full summary preference outcome unknown. Do not replay; acknowledge and explicitly Load before another Save: ${formatError(cause)}`;
      this.state.saved = null;
      this.state.authorityUnknown = true;
      this.state.receipts.push({ kind: 'unknown', request: structuredClone(request), errorMessage: this.state.error });
    } finally {
      this.state.busy = false;
      this.notify();
    }
  }
  acknowledge() {
    if (this.state.busy) throw new Error('Full summary preference Save cannot be cancelled; wait for its outcome.');
    this.state.blocked = false;
    this.notify();
  }
}
const fullSessions = new Map<string, { scope: GoogleEarthScope; session: SiteUnitSummaryFullPreferencesSession }>();
export function siteUnitSummaryFullPreferencesSession(scope: GoogleEarthScope): SiteUnitSummaryFullPreferencesSession {
  const previous = fullSessions.get(scope.contextId);
  if (previous) {
    if (!ownedScope(previous.scope, scope))
      throw new Error('Full summary preference drafts/receipts belong to different owned paths.');
    return previous.session;
  }
  const owner = structuredClone(scope),
    session = new SiteUnitSummaryFullPreferencesSession(owner);
  fullSessions.set(owner.contextId, { scope: owner, session });
  return session;
}
registerContextDisposer((id) => {
  sessions.delete(id);
  fullSessions.delete(id);
});
