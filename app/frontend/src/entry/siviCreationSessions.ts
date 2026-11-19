import { PlotEntryService } from '../../bindings/github.com/boostao/vpro/app';
import { SIVICreationSession } from './siviCreationSession';
import type { SIVISpeciesOwner } from './siviSpeciesEditor';

const sessions = new Map<string, SIVICreationSession>();
const host = globalThis as typeof globalThis & { __vproContextDisposers?: Set<(id: string) => void> };
(host.__vproContextDisposers ??= new Set()).add(id => {
  for (const key of sessions.keys()) {
    if (JSON.parse(key)[0] === id) sessions.delete(key);
  }
});

export function siviCreationSession(owner: SIVISpeciesOwner): SIVICreationSession {
  const key = JSON.stringify([owner.contextId, owner.project, owner.plot]);
  let session = sessions.get(key);
  if (!session) {
    const { contextId, project, plot } = owner;
    session = new SIVICreationSession({ contextId, project, plot }, {
      references: () => PlotEntryService.GetSIVICreationReferences(contextId, plot),
      create: request => PlotEntryService.CreateSIVIVegetation(contextId, request),
      receipt: request => PlotEntryService.LookupSIVICreationReceipt(contextId, request),
    });
    sessions.set(key, session);
  }
  return session;
}
