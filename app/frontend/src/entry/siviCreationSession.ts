import type { EditorCloseState } from '../shell/closeLifecycle';
import { ReadRequests, type CancellableRead } from '../shared/readRequests';
import { beginSIVICreation, siviCreationErrors, siviCreationRequest,
  type SIVICreationDraft, type SIVICreationForm, type SIVICreationRequest } from './siviCreationEditor';
import { validateSIVISpeciesReferences, type SIVISpeciesOwner, type SIVISpeciesReferences } from './siviSpeciesEditor';
import { siviCreationReceiptFromWire, type SIVICreationReceipt } from './siviCreationReceipt';

export interface SIVICreationPort {
  references(): CancellableRead<unknown>;
  create(requestJSON: string): CancellableRead<unknown>;
  receipt(requestJSON: string): CancellableRead<unknown>;
}
export interface SIVICreationView {
  draft: SIVICreationDraft | null;
  references: SIVISpeciesReferences | null;
  busy: boolean;
  blocked: boolean;
  error: string | null;
  receipt: SIVICreationReceipt | null;
  requestId: string | null;
  revision: number;
}

function isPreCommitBackendRejection(cause: unknown): boolean {
  if (cause === null || typeof cause !== 'object') return false;
  const { name, message } = cause as { name?: unknown; message?: unknown };
  if (name !== 'RuntimeError' || typeof message !== 'string') return false;
  return !/\bcommitted but\b/i.test(message) && !/\bcontext (?:canceled|deadline exceeded)\b/i.test(message);
}

export class SIVICreationSession {
  private readonly owner: SIVISpeciesOwner;
  private state: SIVICreationView = { draft: null, references: null, busy: false, blocked: false,
    error: null, receipt: null, requestId: null, revision: 0 };
  private pending: SIVICreationRequest | null = null;
  private attempted = false;
  private generation = 0;
  private readonly requests = new ReadRequests();
  private readonly listeners = new Set<() => void>();

  constructor(owner: SIVISpeciesOwner, private readonly port: SIVICreationPort) {
    beginSIVICreation('SubVegA-SIVI', owner);
    this.owner = { contextId: owner.contextId, project: owner.project, plot: owner.plot };
  }
  subscribe(notify: () => void) {
    this.listeners.add(notify);
    notify();
    return () => { this.listeners.delete(notify); };
  }
  private changed() { for (const notify of this.listeners) notify(); }
  view(): SIVICreationView { return structuredClone(this.state); }
  closeState(): EditorCloseState {
    const errors = this.state.draft && this.state.references
      ? siviCreationErrors(this.state.draft, this.state.references, this.owner) : [];
    const reason = this.state.busy ? 'Wait for or cancel the SIVI creation operation.'
      : this.state.blocked ? 'Resolve the retained SIVI creation request using read-only history; do not repeat Create.'
      : !this.state.draft ? 'Start an explicit source-form creation draft.'
      : !this.state.references ? 'Load the owned SIVI Species definitions before creating.'
      : errors[0] ?? '';
    return { unsaved: this.state.draft !== null || this.state.blocked, busy: this.state.busy,
      blocked: this.state.blocked || errors.length > 0, canSave: reason === '', saveReason: reason, error: this.state.error };
  }
  private requireIdle() {
    if (this.state.busy) throw new Error('Wait for or cancel the SIVI creation operation.');
  }
  private requireKnown() {
    this.requireIdle();
    if (this.state.blocked) throw new Error('The retained SIVI creation outcome is unknown; resolve history without replacing its request.');
  }
  async loadReferences(): Promise<boolean> {
    this.requireKnown();
    const generation = ++this.generation;
    this.state.busy = true;
    this.changed();
    try {
      const wire = await this.requests.track(this.port.references());
      if (generation !== this.generation) return false;
      this.state.references = validateSIVISpeciesReferences(wire, this.owner);
      this.state.error = this.state.draft ? siviCreationErrors(this.state.draft, this.state.references, this.owner)[0] ?? null : null;
      return true;
    } catch (cause) {
      if (generation === this.generation) this.state.error = `SIVI creation definitions failed; retained draft was not replaced: ${String(cause)}`;
      return false;
    } finally {
      if (generation === this.generation) { this.state.busy = false; this.changed(); }
    }
  }
  start(form: SIVICreationForm) {
    this.requireKnown();
    if (this.state.draft) throw new Error('Save or explicitly discard the current creation draft before choosing another source form.');
    if (!this.state.references) throw new Error('Load the owned SIVI Species definitions before starting a creation draft.');
    this.state.draft = beginSIVICreation(form, this.owner);
    this.state.receipt = null;
    this.state.error = siviCreationErrors(this.state.draft, this.state.references, this.owner)[0] ?? null;
    this.changed();
  }
  updateDraft(draft: SIVICreationDraft) {
    this.requireKnown();
    if (!this.state.draft || !this.state.references || draft.form !== this.state.draft.form) {
      throw new Error('Creation correction requires the retained source-form draft and owned definitions.');
    }
    const errors = siviCreationErrors(draft, this.state.references, this.owner);
    this.state.draft = structuredClone(draft);
    this.state.error = errors[0] ?? null;
    this.changed();
  }
  discard() {
    this.requireKnown();
    this.state.draft = null;
    this.state.error = null;
    this.changed();
  }
  cancel() {
    if (!this.state.busy) return;
    this.generation++;
    this.requests.cancelAll();
    this.state.busy = false;
    if (this.pending && this.attempted) {
      this.state.blocked = true;
      this.state.error = 'SIVI creation acknowledgement was cancelled; the exact draft/request remain unknown. Resolve read-only history, not matching values.';
    } else if (this.pending) {
      this.pending = null;
      this.state.requestId = null;
      this.attempted = false;
      this.state.error = 'SIVI creation cancelled before dispatch; retained draft is unchanged.';
    } else this.state.error = 'SIVI creation definition read cancelled; retained draft and definitions are unchanged.';
    this.changed();
  }
  async save(requestId: string): Promise<boolean> {
    this.requireKnown();
    const close = this.closeState();
    if (!close.canSave || !this.state.draft || !this.state.references) throw new Error(close.saveReason);
    this.pending = siviCreationRequest(this.state.draft, this.state.references, this.owner, requestId);
    this.state.requestId = requestId;
    this.attempted = false;
    return this.acceptReceipt('create');
  }
  async resolve(): Promise<boolean> {
    this.requireIdle();
    if (!this.pending || !this.state.blocked) throw new Error('No unknown SIVI creation request is retained to resolve.');
    return this.acceptReceipt('lookup');
  }
  private async acceptReceipt(operation: 'create' | 'lookup'): Promise<boolean> {
    const request = this.pending;
    if (!request) throw new Error('The stable SIVI creation request is unavailable.');
    const generation = ++this.generation;
    this.state.busy = true;
    this.state.error = null;
    this.changed();
    let preCommitRejected = false;
    try {
      if (generation !== this.generation) return false;
      if (operation === 'create') this.attempted = true;
      const json = JSON.stringify(request);
      let wire: unknown;
      try {
        wire = await this.requests.track(operation === 'create' ? this.port.create(json) : this.port.receipt(json));
      } catch (rpcCause) {
        preCommitRejected = operation === 'create' && isPreCommitBackendRejection(rpcCause);
        throw rpcCause;
      }
      if (generation !== this.generation) return false;
      if (wire === null && operation === 'lookup') {
        throw new Error('No committed history is visible for this request. This is unresolved, not proof that creation failed.');
      }
      this.state.receipt = siviCreationReceiptFromWire(wire, request, this.owner, operation);
      this.state.draft = null;
      this.state.blocked = false;
      this.state.requestId = null;
      this.state.revision++;
      this.pending = null;
      this.attempted = false;
      return true;
    } catch (cause) {
      if (generation === this.generation) {
        if (preCommitRejected) {
          this.pending = null;
          this.state.requestId = null;
          this.attempted = false;
          this.state.blocked = false;
          this.state.error = `SIVI creation rejected before commit; retained draft requires correction or Undo: ${String(cause)}`;
        } else if (this.attempted) {
          this.state.blocked = true;
          this.state.error = `SIVI creation outcome remains unknown; exact draft/request retained, no automatic replay: ${String(cause)}`;
        } else {
          this.pending = null;
          this.state.requestId = null;
          this.attempted = false;
          this.state.error = `SIVI creation failed before dispatch; retained draft requires correction: ${String(cause)}`;
        }
      }
      return false;
    } finally {
      if (generation === this.generation) { this.state.busy = false; this.changed(); }
    }
  }
}
