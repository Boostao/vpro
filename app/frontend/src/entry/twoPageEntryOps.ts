import { AuditRestoreAction, PlotEntryService } from '../../bindings/github.com/boostao/vpro/app';
import type { EditorCloseState } from '../shell/closeLifecycle';
import { notifications } from '../shell/notificationService.svelte';
import { formatError, ReadRequests } from '../shared/readRequests';
import type { TwoPageParentForm } from './twoPageParentSession';
import { TwoPageEntrySession } from './twoPageEntrySession';
import type { TwoPageEntryReadersController } from './useTwoPageEntryReaders.svelte';

export interface TwoPageReaderFlags {
  anyOpen: boolean;
  anyBusy: boolean;
  metaOpen: string | null;
  metaBusy: boolean;
  profBusy: boolean;
  metadataEditor?: { getCloseState(): EditorCloseState; undo(): void };
}

export function resolveTwoPageReaderFlags(readers?: TwoPageEntryReadersController): TwoPageReaderFlags {
  if (readers) {
    return {
      anyOpen: readers.anyOpen,
      anyBusy: readers.anyBusy,
      metaOpen: readers.projectMetadataOpen,
      metaBusy: readers.projectMetadataBusy,
      profBusy: readers.profilingBusy,
      metadataEditor: readers.metadataEditor,
    };
  }
  const g = globalThis as Record<string, unknown>;
  const metaOpen = (g.projectMetadataOpen as string | null) ?? null;
  return {
    anyOpen: Boolean(
      g.externalOpen ||
      g.auditOpen ||
      g.googleEarthOpen ||
      g.vegetationTableOpen ||
      g.environmentTableOpen ||
      metaOpen ||
      g.profilingOpen
    ),
    anyBusy: Boolean(
      g.sourceRefreshing ||
      g.auditBusy ||
      g.googleEarthBusy ||
      g.vegetationTableBusy ||
      g.environmentTableBusy ||
      g.projectMetadataBusy ||
      g.profilingBusy
    ),
    metaOpen,
    metaBusy: Boolean(g.projectMetadataBusy),
    profBusy: Boolean(g.profilingBusy),
    metadataEditor: g.metadataEditor as { getCloseState(): EditorCloseState; undo(): void } | undefined,
  };
}

export function createOrReuseTwoPageSession(opts: {
  owner: { contextId: string; project: string; plot: string };
  sessions: Map<TwoPageParentForm, TwoPageEntrySession>;
  sourceForm: TwoPageParentForm;
  oncommitted: () => Promise<void>;
  onchange: () => void;
  PlotEntrySvc?: typeof PlotEntryService;
  ReadsCls?: typeof ReadRequests;
  SessionCls?: typeof TwoPageEntrySession;
}): TwoPageEntrySession {
  const { owner, sessions, sourceForm, oncommitted, onchange } = opts;
  const existing = sessions.get(sourceForm);
  if (existing) return existing;
  const Svc = opts.PlotEntrySvc ?? PlotEntryService;
  const RCls = opts.ReadsCls ?? ReadRequests;
  const SCls = opts.SessionCls ?? TwoPageEntrySession;
  const requests = new RCls();
  const created = new SCls(
    owner,
    sourceForm,
    {
      read: () => requests.track(Svc.GetTwoPageParentEntryOriginal(owner.contextId, owner.plot, sourceForm)),
      readReferences: (filters) =>
        requests.track(Svc.GetTwoPageParentEntryReferences(owner.contextId, owner.plot, sourceForm, filters)),
      cancelRead: () => requests.cancelAll(),
      save: (request) => Svc.SaveTwoPageParentEntry(owner.contextId, owner.plot, sourceForm, request),
      restore: (history, action) =>
        Svc.RestoreTwoPageParentEntry(owner.contextId, owner.plot, sourceForm, history, action),
      refreshParent: async () => {
        await oncommitted();
        for (const [variant, peer] of sessions) {
          if (variant === sourceForm || !peer.view().original) continue;
          if (peer.closeState().unsaved || peer.closeState().busy || !(await peer.load())) {
            throw new Error(
              peer.view().error ?? 'Another complete-entry variant could not refresh; no write was replayed.'
            );
          }
        }
      },
    },
    onchange
  );
  sessions.set(sourceForm, created);
  return created;
}

export function computeTwoPageCloseState(opts: {
  flags: TwoPageReaderFlags;
  standalone: boolean;
  childBlocked: boolean;
  close: EditorCloseState;
  error: string | null;
  getDraftState: () => EditorCloseState;
}): EditorCloseState {
  const { flags, standalone, childBlocked, close, error, getDraftState } = opts;
  if (flags.metaOpen === 'edit') {
    return (
      flags.metadataEditor?.getCloseState() ?? {
        unsaved: true,
        busy: flags.metaBusy,
        canSave: false,
        blocked: true,
        error,
        saveReason: 'Finish the owned metadata editor before closing the complete-entry source.',
      }
    );
  }
  if (standalone) {
    const draftState = getDraftState();
    if (flags.anyOpen || childBlocked) {
      return {
        ...close,
        unsaved: true,
        busy: draftState.busy,
        blocked: draftState.blocked || childBlocked,
        canSave: false,
        error: error ?? close.error,
        saveReason: 'Finish or return from the active sub-panel before saving or leaving this plot.',
      };
    }
    if (!draftState.unsaved)
      return {
        ...close,
        unsaved: false,
        busy: draftState.busy,
        blocked: close.blocked,
        canSave: true,
        error: error ?? close.error,
        saveReason: '',
      };
    return {
      ...close,
      unsaved: true,
      busy: draftState.busy,
      blocked: close.blocked,
      canSave: close.canSave && !childBlocked,
      error: error ?? close.error,
      saveReason: close.saveReason || '',
    };
  }
  return {
    ...close,
    unsaved: true,
    busy: close.busy || flags.metaBusy || flags.profBusy,
    canSave: false,
    error: error ?? close.error,
    saveReason:
      'Save or Undo complete-entry drafts explicitly, then close their review before saving or closing the plot.',
  };
}

export function computeTwoPageDraftState(opts: {
  flags: TwoPageReaderFlags;
  sessions: Map<unknown, { closeState(): EditorCloseState }>;
  view: { original?: unknown; referenceError?: string | null };
  close: EditorCloseState;
  error: string | null;
  getCloseState: () => EditorCloseState;
}): EditorCloseState {
  const { flags, sessions, view, close, error, getCloseState } = opts;
  const states = [...sessions.values()].map((owned) => owned.closeState());
  const metadataClose = flags.metaOpen === 'edit' ? getCloseState() : null;
  return {
    ...close,
    unsaved: flags.anyOpen || states.some((s) => s.unsaved),
    busy: flags.anyBusy || Boolean(metadataClose?.busy) || states.some((s) => s.busy),
    error: error ?? metadataClose?.error ?? close.error,
    blocked: flags.anyOpen || !view.original || Boolean(view.referenceError) || states.some((s) => s.blocked),
  };
}

export async function executeTwoPageParentOperation(opts: {
  action: 'load' | 'save' | 'undo' | 'retain' | 'prune' | 'references';
  plotName: string;
  formLabel: string;
  childBlocked: boolean;
  session: TwoPageEntrySession;
  close?: EditorCloseState;
  readers?: TwoPageEntryReadersController;
  flags: TwoPageReaderFlags;
  setError: (msg: string | null) => void;
  notify?: typeof notifications;
}): Promise<void> {
  const { action, plotName, formLabel, childBlocked, session, close, readers, flags, setError } = opts;
  const notify = opts.notify ?? notifications;
  const notifOpts = {
    category: 'entry' as const,
    source: 'Two-Page Form',
    contextTag: plotName ? `Plot ${plotName}` : undefined,
  };
  try {
    if (readers) readers.assertParentFree('operation');
    else if (flags.anyOpen) throw new Error('Finish the owned review before parent operations.');
    if (childBlocked && action !== 'undo' && action !== 'references') {
      throw new Error('Resolve retained linked-child drafts, reads and receipts before changing the parent.');
    }
    setError(null);
    const hadUnsaved =
      action === 'undo' &&
      ((typeof session?.closeState === 'function' ? Boolean(session.closeState()?.unsaved) : false) ||
        Boolean(close?.unsaved));
    const ok =
      action === 'load'
        ? await session.load()
        : action === 'save'
          ? await session.save()
          : action === 'undo'
            ? await session.undo()
            : action === 'references'
              ? await session.loadReferences()
              : await session.restore(
                  action === 'retain' ? AuditRestoreAction.AuditRestoreRetain : AuditRestoreAction.AuditRestorePrune
                );
    if (!ok) {
      const msg = session.view().error ?? session.view().referenceError;
      setError(msg);
      if (msg && (action === 'save' || action === 'retain' || action === 'prune' || action === 'load')) {
        notify.error(
          `Two-page ${action === 'load' ? 'reload' : action === 'save' ? 'save' : 'restore'} failed`,
          msg,
          notifOpts
        );
      }
    } else if (action === 'save') {
      notify.success(
        plotName ? `Two-page plot ${plotName} saved` : 'Two-page plot saved',
        `${formLabel} complete-entry changes committed atomically.`,
        notifOpts
      );
    } else if (action === 'undo' && hadUnsaved) {
      notify.info(
        'Two-page changes undone',
        plotName ? `Plot ${plotName} restored to last saved state.` : 'Draft changes discarded.',
        notifOpts
      );
    } else if (action === 'retain' || action === 'prune') {
      notify.success(
        plotName ? `Two-page plot ${plotName} restored` : 'Two-page plot restored',
        action === 'retain' ? 'Restored with audit history retained.' : 'Restored with audit history pruned.',
        notifOpts
      );
    }
  } catch (cause) {
    const msg = `Complete-entry operation refused; owned state retained: ${formatError(cause)}`;
    setError(msg);
    if (action === 'save' || action === 'retain' || action === 'prune' || action === 'load') {
      notify.error(
        `Two-page ${action === 'load' ? 'reload' : action === 'save' ? 'save' : 'restore'} refused`,
        msg,
        notifOpts
      );
    }
  }
}
