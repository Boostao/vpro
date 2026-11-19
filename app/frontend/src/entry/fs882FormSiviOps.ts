import type { SIVICreationForm } from './siviCreationEditor';
import type { SIVICreationSession } from './siviCreationSession';
import type { SIVICreationUndoSession } from './siviCreationUndoSession';
import type { SIVIDeletionRestorationSession } from './siviDeletionRestorationSession';
import type { SIVIDeletionSession } from './siviDeletionSession';

interface SiviOpCallbacks {
  enabled: boolean;
  recoveryDisabled: boolean;
  editingDisabled: boolean;
  setHostBusy: (busy: boolean) => void;
  invalidateCapabilities: () => void;
  setError: (msg: string | null) => void;
  setSuccess: (msg: string | null) => void;
  randomUUID: () => string;
}

interface SiviVersionedSession {
  cancel(): void;
  view(): { revision: number; error: string | null };
}

async function runSiviSessionBody<TSession extends SiviVersionedSession>(
  session: TSession | undefined,
  callbacks: SiviOpCallbacks,
  unavailableMsg: string,
  isCancel: boolean,
  blockedByDrafts: boolean,
  blockedMsg: string,
  verifiedFailurePrefix: string,
  unverifiedFailurePrefix: string,
  body: (active: TSession) => Promise<boolean>,
): Promise<boolean> {
  if (!session || !callbacks.enabled) {
    callbacks.setError(unavailableMsg);
    return false;
  }
  if (isCancel) {
    session.cancel();
    return true;
  }
  if (callbacks.recoveryDisabled || blockedByDrafts) {
    callbacks.setError(blockedMsg);
    return false;
  }
  const revision = session.view().revision;
  callbacks.setError(null);
  callbacks.setSuccess(null);
  try {
    return await body(session);
  } catch (cause) {
    if (session.view().revision > revision) {
      callbacks.invalidateCapabilities();
      callbacks.setError(`${verifiedFailurePrefix}: ${String(cause)}`);
    } else {
      callbacks.setError(`${unverifiedFailurePrefix}: ${String(cause)}`);
    }
    return false;
  } finally {
    callbacks.setHostBusy(false);
  }
}

/** Execute SIVI creation session commands (`load`, `start`, `save`, `undo`, `resolve`, `cancel`). */
export async function executeSiviCreationOpImpl(params: SiviOpCallbacks & {
  session: SIVICreationSession | undefined;
  operation: 'load' | 'start' | 'save' | 'undo' | 'resolve' | 'cancel';
  form?: SIVICreationForm;
  getCurrentSession: () => SIVICreationSession | undefined;
  refreshPeers: (plot: string) => Promise<void>;
}): Promise<boolean> {
  const needsEdit = params.operation === 'load' || params.operation === 'start' || params.operation === 'save';
  return runSiviSessionBody(
    params.session,
    params,
    'SIVI creation is unavailable for this owned parent.',
    params.operation === 'cancel',
    needsEdit && params.editingDisabled,
    'SIVI creation requires its available owner and no conflicting drafts or operation.',
    'SIVI creation is already verified; peer refresh failed. Reload originals without repeating Create',
    'SIVI creation operation failed; retained owner state unchanged',
    async (session) => {
      if (params.operation === 'start') {
        if (!params.form) throw new Error('Choose one explicit SIVI source form before starting creation.');
        session.start(params.form);
        return true;
      }
      if (params.operation === 'undo') {
        session.discard();
        return true;
      }
      if (params.operation === 'load') {
        if (!(await session.loadReferences())) {
          params.setError(session.view().error);
          return false;
        }
        return true;
      }
      const ok = params.operation === 'save' ? await session.save(params.randomUUID()) : await session.resolve();
      if (!ok) {
        params.setError(session.view().error);
        return false;
      }
      const receipt = session.view().receipt;
      if (!receipt || session !== params.getCurrentSession()) {
        throw new Error('The verified creation owner changed before peer refresh.');
      }
      params.setHostBusy(true);
      await params.refreshPeers(receipt.plot);
      params.setSuccess(`SIVI creation ${receipt.id} verified; ${receipt.replayed ? 'read-only resolution, no mutation repeated' : 'one row committed'}.`);
      return true;
    },
  );
}

/** Execute SIVI deletion or restoration lifecycle operations. */
export async function executeSiviLifecycleOpImpl(params: SiviOpCallbacks & {
  kind: 'deletion' | 'restoration';
  operation: 'load' | 'history' | 'review' | 'save' | 'undo' | 'resolve' | 'cancel';
  identity?: string;
  form?: SIVICreationForm;
  deletionSession: SIVIDeletionSession | undefined;
  restorationSession: SIVIDeletionRestorationSession | undefined;
  getCurrentSession: () => SIVIDeletionSession | SIVIDeletionRestorationSession | undefined;
  refreshPeers: (plot: string, kind: 'deletion' | 'restoration') => Promise<void>;
}): Promise<boolean> {
  const target = params.kind === 'deletion' ? params.deletionSession : params.restorationSession;
  const needsEdit = params.operation !== 'undo' && params.operation !== 'resolve';
  return runSiviSessionBody(
    target,
    params,
    `SIVI ${params.kind} is unavailable for this owned parent.`,
    params.operation === 'cancel',
    needsEdit && params.editingDisabled,
    `SIVI ${params.kind} requires its clean available owner and no conflicting drafts or operation.`,
    `SIVI ${params.kind} is already verified; source refresh failed. Reload the owned plot without repeating the mutation`,
    `SIVI ${params.kind} failed; retained owner state unchanged`,
    async (session) => {
      if (params.operation === 'undo') {
        session.discard();
        return true;
      }
      if (params.operation === 'load' && params.kind === 'deletion') {
        if (!params.deletionSession || !(await params.deletionSession.loadTargets())) {
          params.setError(session.view().error);
          return false;
        }
        return true;
      }
      if (params.operation === 'history' && params.kind === 'restoration') {
        if (!params.restorationSession || !(await params.restorationSession.loadHistory())) {
          params.setError(session.view().error);
          return false;
        }
        return true;
      }
      if (params.operation === 'review') {
        if (!params.identity) throw new Error('Select one explicit loaded source row or owned historical event.');
        const ok = params.kind === 'deletion'
          ? params.form && params.deletionSession && (await params.deletionSession.review(params.form, params.identity))
          : params.restorationSession && (await params.restorationSession.review(params.identity));
        if (!ok) {
          params.setError(session.view().error ?? 'Choose an exact source form before reviewing deletion.');
          return false;
        }
        return true;
      }
      if (params.operation !== 'save' && params.operation !== 'resolve') {
        throw new Error('Unsupported source lifecycle operation; no action was inferred.');
      }
      if (!(await (params.operation === 'save' ? session.save(params.randomUUID()) : session.resolve()))) {
        params.setError(session.view().error);
        return false;
      }
      const receipt = session.view().receipt;
      if (!receipt || session !== params.getCurrentSession()) {
        throw new Error('The verified lifecycle owner changed before peer refresh.');
      }
      params.setHostBusy(true);
      await params.refreshPeers(receipt.plot, params.kind);
      params.setSuccess(`SIVI ${params.kind} ${receipt.id} verified; ${receipt.replayed ? 'read-only resolution, no mutation repeated' : 'one exact physical row committed'}.`);
      return true;
    },
  );
}

/** Execute SIVI creation-undo session operations (`history`, `review`, `undo`, `discard`, `resolve`, `cancel`). */
export async function executeSiviCreationUndoOpImpl(params: SiviOpCallbacks & {
  session: SIVICreationUndoSession | undefined;
  operation: 'history' | 'review' | 'undo' | 'discard' | 'resolve' | 'cancel';
  historyId?: string;
  getCurrentSession: () => SIVICreationUndoSession | undefined;
  refreshPeers: (plot: string) => Promise<void>;
}): Promise<boolean> {
  const needsEdit = params.operation !== 'discard' && params.operation !== 'resolve';
  return runSiviSessionBody(
    params.session,
    params,
    'SIVI creation Undo is unavailable for this owned parent.',
    params.operation === 'cancel',
    needsEdit && params.editingDisabled,
    'SIVI creation Undo requires its clean available owner and no conflicting drafts or operation.',
    'SIVI creation Undo is already verified; source refresh failed. Reload the owned plot without repeating Undo',
    'SIVI creation Undo failed; retained owner state unchanged',
    async (session) => {
      if (params.operation === 'discard') {
        session.discard();
        return true;
      }
      if (params.operation === 'history') {
        if (!(await session.loadHistory())) {
          params.setError(session.view().error);
          return false;
        }
        return true;
      }
      if (params.operation === 'review') {
        if (!params.historyId) throw new Error('Choose an explicit available owned historical creation.');
        if (!(await session.review(params.historyId))) {
          params.setError(session.view().error);
          return false;
        }
        return true;
      }
      if (!(await (params.operation === 'undo' ? session.undo(params.randomUUID()) : session.resolve()))) {
        params.setError(session.view().error);
        return false;
      }
      const receipt = session.view().receipt;
      if (!receipt || session !== params.getCurrentSession()) {
        throw new Error('The verified creation Undo owner changed before peer refresh.');
      }
      params.setHostBusy(true);
      await params.refreshPeers(receipt.plot);
      params.setSuccess(`SIVI creation Undo ${receipt.id} verified; ${receipt.replayed ? 'read-only resolution, no mutation repeated' : 'one exact created row removed'}.`);
      return true;
    },
  );
}
