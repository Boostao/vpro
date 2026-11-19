import { PictureService, type PictureMetadataEdit } from '../../bindings/github.com/boostao/vpro/app';
import { PictureMetadataSession } from './pictureMetadataSession';
import type { PictureOwner } from './pictureRead';

const sessions = new Map<string, PictureMetadataSession>();
const host = globalThis as typeof globalThis & { __vproContextDisposers?: Set<(id: string) => void> };
(host.__vproContextDisposers ??= new Set()).add(id => {
  for (const key of sessions.keys()) {
    if (JSON.parse(key)[0] === id) sessions.delete(key);
  }
});

function parseMetadataEdit(requestJSON: string): PictureMetadataEdit {
  return JSON.parse(requestJSON) as PictureMetadataEdit;
}

export function pictureMetadataSession(owner: PictureOwner): PictureMetadataSession {
  const key = JSON.stringify([owner.contextId, owner.project, owner.plotNumber]);
  let session = sessions.get(key);
  if (!session) {
    const { contextId, project, plotNumber } = owner;
    session = new PictureMetadataSession({ contextId, project, plotNumber }, {
      read: () => PictureService.GetMetadata(contextId, plotNumber),
      save: request => PictureService.SaveMetadata(contextId, plotNumber, parseMetadataEdit(request)),
      receipt: request => PictureService.LookupMetadataReceipt(contextId, plotNumber, parseMetadataEdit(request)),
    });
    sessions.set(key, session);
  }
  return session;
}
