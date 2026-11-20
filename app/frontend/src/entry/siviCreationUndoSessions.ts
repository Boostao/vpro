import { PlotEntryService, type SIVICreationUndoRequest } from '../../bindings/github.com/boostao/vpro/app';
import { SIVICreationUndoSession } from './siviCreationUndoSession';
import type { SIVISpeciesOwner } from './siviSpeciesEditor';

const sessions = new Map<string, SIVICreationUndoSession>();
const host = globalThis as typeof globalThis & { __vproContextDisposers?: Set<(id: string) => void> };
(host.__vproContextDisposers ??= new Set()).add((id) => {
  for (const key of sessions.keys()) {
    if (JSON.parse(key)[0] === id) sessions.delete(key);
  }
});

function parseUndoRequest(requestJSON: string): SIVICreationUndoRequest {
  return JSON.parse(requestJSON) as SIVICreationUndoRequest;
}

export function siviCreationUndoSession(owner: SIVISpeciesOwner): SIVICreationUndoSession {
  const identity = JSON.stringify([owner.contextId, owner.project, owner.plot]);
  let session = sessions.get(identity);
  if (!session) {
    const { contextId, project, plot } = owner;
    session = new SIVICreationUndoSession(
      { contextId, project, plot },
      {
        history: () => PlotEntryService.GetSIVICreationUndoHistory(contextId, plot),
        review: (historyId) => PlotEntryService.ReviewSIVICreationUndo(contextId, plot, historyId),
        undo: (request) => PlotEntryService.UndoSIVICreation(contextId, parseUndoRequest(request)),
        receipt: (request) => PlotEntryService.LookupSIVICreationUndoReceipt(contextId, parseUndoRequest(request)),
      }
    );
    sessions.set(identity, session);
  }
  return session;
}
