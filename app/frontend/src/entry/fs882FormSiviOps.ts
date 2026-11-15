import type { SIVICreationForm } from './siviCreationEditor';
import type { SIVICreationSession } from './siviCreationSession';
import type { SIVICreationUndoSession } from './siviCreationUndoSession';
import type { SIVIDeletionRestorationSession } from './siviDeletionRestorationSession';
import type { SIVIDeletionSession } from './siviDeletionSession';

/** Execute SIVI creation session commands (`load`, `start`, `save`, `undo`, `resolve`, `cancel`). */
export async function executeSiviCreationOpImpl(params: {
  session: SIVICreationSession | undefined;
  enabled: boolean;
  recoveryDisabled: boolean;
  editingDisabled: boolean;
  operation: 'load' | 'start' | 'save' | 'undo' | 'resolve' | 'cancel';
  form?: SIVICreationForm;
  getCurrentSession: () => SIVICreationSession | undefined;
  setHostBusy: (busy: boolean) => void;
  invalidateCapabilities: () => void;
  setError: (msg: string | null) => void;
  setSuccess: (msg: string | null) => void;
  refreshPeers: (plot: string) => Promise<void>;
  randomUUID: () => string;
}): Promise<boolean> {
  const session = params.session;
  if (!session || !params.enabled) {
    params.setError('SIVI creation is unavailable for this owned parent.');
    return false;
  }
  if (params.operation === 'cancel') {
    session.cancel();
    return true;
  }
  if (params.recoveryDisabled || ((params.operation === 'load' || params.operation === 'start' || params.operation === 'save') && params.editingDisabled)) {
    params.setError('SIVI creation requires its available owner and no conflicting drafts or operation.');
    return false;
  }
  const revision = session.view().revision;
  params.setError(null);
  params.setSuccess(null);
  try {
    if (params.operation === 'start') {
      if (!params.form) throw new Error('Choose one explicit SIVI source form before starting creation.');
      session.start(params.form);
    } else if (params.operation === 'undo') {
      session.discard();
    } else if (params.operation === 'load') {
      if (!(await session.loadReferences())) {
        params.setError(session.view().error);
        return false;
      }
    } else {
      const ok = params.operation === 'save' ? await session.save(params.randomUUID()) : await session.resolve();
      if (!ok) {
        params.setError(session.view().error);
        return false;
      }
      const receipt = session.view().receipt;
      if (!receipt || session !== params.getCurrentSession()) throw new Error('The verified creation owner changed before peer refresh.');
      params.setHostBusy(true);
      await params.refreshPeers(receipt.plot);
      params.setSuccess(`SIVI creation ${receipt.id} verified; ${receipt.replayed ? 'read-only resolution, no mutation repeated' : 'one row committed'}.`);
    }
    return true;
  } catch (cause) {
    if (session.view().revision > revision) {
      params.invalidateCapabilities();
      params.setError(`SIVI creation is already verified; peer refresh failed. Reload originals without repeating Create: ${String(cause)}`);
    } else {
      params.setError(`SIVI creation operation failed; retained owner state unchanged: ${String(cause)}`);
    }
    return false;
  } finally {
    params.setHostBusy(false);
  }
}

/** Execute SIVI deletion or restoration lifecycle operations. */
export async function executeSiviLifecycleOpImpl(params: {
  kind: 'deletion' | 'restoration';
  operation: 'load' | 'history' | 'review' | 'save' | 'undo' | 'resolve' | 'cancel';
  identity?: string;
  form?: SIVICreationForm;
  deletionSession: SIVIDeletionSession | undefined;
  restorationSession: SIVIDeletionRestorationSession | undefined;
  enabled: boolean;
  recoveryDisabled: boolean;
  editingDisabled: boolean;
  getCurrentSession: () => SIVIDeletionSession | SIVIDeletionRestorationSession | undefined;
  setHostBusy: (busy: boolean) => void;
  invalidateCapabilities: () => void;
  setError: (msg: string | null) => void;
  setSuccess: (msg: string | null) => void;
  refreshPeers: (plot: string, kind: 'deletion' | 'restoration') => Promise<void>;
  randomUUID: () => string;
}): Promise<boolean> {
  const session = params.kind === 'deletion' ? params.deletionSession : params.restorationSession;
  if (!session || !params.enabled) {
    params.setError(`SIVI ${params.kind} is unavailable for this owned parent.`);
    return false;
  }
  if (params.operation === 'cancel') {
    session.cancel();
    return true;
  }
  if (params.recoveryDisabled || (params.operation !== 'undo' && params.operation !== 'resolve' && params.editingDisabled)) {
    params.setError(`SIVI ${params.kind} requires its clean available owner and no conflicting drafts or operation.`);
    return false;
  }
  const revision = session.view().revision;
  params.setError(null);
  params.setSuccess(null);
  try {
    if (params.operation === 'undo') {
      session.discard();
    } else if (params.operation === 'load' && params.kind === 'deletion') {
      if (!params.deletionSession || !(await params.deletionSession.loadTargets())) {
        params.setError(session.view().error);
        return false;
      }
    } else if (params.operation === 'history' && params.kind === 'restoration') {
      if (!params.restorationSession || !(await params.restorationSession.loadHistory())) {
        params.setError(session.view().error);
        return false;
      }
    } else if (params.operation === 'review') {
      if (!params.identity) throw new Error('Select one explicit loaded source row or owned historical event.');
      const ok = params.kind === 'deletion'
        ? params.form && params.deletionSession && (await params.deletionSession.review(params.form, params.identity))
        : params.restorationSession && (await params.restorationSession.review(params.identity));
      if (!ok) {
        params.setError(session.view().error ?? 'Choose an exact source form before reviewing deletion.');
        return false;
      }
    } else if (params.operation === 'save' || params.operation === 'resolve') {
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
    } else {
      throw new Error('Unsupported source lifecycle operation; no action was inferred.');
    }
    return true;
  } catch (cause) {
    if (session.view().revision > revision) {
      params.invalidateCapabilities();
      params.setError(`SIVI ${params.kind} is already verified; source refresh failed. Reload the owned plot without repeating the mutation: ${String(cause)}`);
    } else {
      params.setError(`SIVI ${params.kind} failed; retained owner state unchanged: ${String(cause)}`);
    }
    return false;
  } finally {
    params.setHostBusy(false);
  }
}

/** Execute SIVI creation-undo session operations (`history`, `review`, `undo`, `discard`, `resolve`, `cancel`). */
export async function executeSiviCreationUndoOpImpl(params: {
  session: SIVICreationUndoSession | undefined;
  enabled: boolean;
  recoveryDisabled: boolean;
  editingDisabled: boolean;
  operation: 'history' | 'review' | 'undo' | 'discard' | 'resolve' | 'cancel';
  historyId?: string;
  getCurrentSession: () => SIVICreationUndoSession | undefined;
  setHostBusy: (busy: boolean) => void;
  invalidateCapabilities: () => void;
  setError: (msg: string | null) => void;
  setSuccess: (msg: string | null) => void;
  refreshPeers: (plot: string) => Promise<void>;
  randomUUID: () => string;
}): Promise<boolean> {
  const session = params.session;
  if (!session || !params.enabled) {
    params.setError('SIVI creation Undo is unavailable for this owned parent.');
    return false;
  }
  if (params.operation === 'cancel') {
    session.cancel();
    return true;
  }
  if (params.recoveryDisabled || (params.operation !== 'discard' && params.operation !== 'resolve' && params.editingDisabled)) {
    params.setError('SIVI creation Undo requires its clean available owner and no conflicting drafts or operation.');
    return false;
  }
  const revision = session.view().revision;
  params.setError(null);
  params.setSuccess(null);
  try {
    if (params.operation === 'discard') {
      session.discard();
    } else if (params.operation === 'history') {
      if (!(await session.loadHistory())) {
        params.setError(session.view().error);
        return false;
      }
    } else if (params.operation === 'review') {
      if (!params.historyId) throw new Error('Choose an explicit available owned historical creation.');
      if (!(await session.review(params.historyId))) {
        params.setError(session.view().error);
        return false;
      }
    } else {
      if (!(await (params.operation === 'undo' ? session.undo(params.randomUUID()) : session.resolve()))) {
        params.setError(session.view().error);
        return false;
      }
      const receipt = session.view().receipt;
      if (!receipt || session !== params.getCurrentSession()) throw new Error('The verified creation Undo owner changed before peer refresh.');
      params.setHostBusy(true);
      await params.refreshPeers(receipt.plot);
      params.setSuccess(`SIVI creation Undo ${receipt.id} verified; ${receipt.replayed ? 'read-only resolution, no mutation repeated' : 'one exact created row removed'}.`);
    }
    return true;
  } catch (cause) {
    if (session.view().revision > revision) {
      params.invalidateCapabilities();
      params.setError(`SIVI creation Undo is already verified; source refresh failed. Reload the owned plot without repeating Undo: ${String(cause)}`);
    } else {
      params.setError(`SIVI creation Undo failed; retained owner state unchanged: ${String(cause)}`);
    }
    return false;
  } finally {
    params.setHostBusy(false);
  }
}
