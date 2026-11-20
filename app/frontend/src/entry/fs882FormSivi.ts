import type { FS882Header, SIVIProjectChoices } from '../../bindings/github.com/boostao/vpro/app';
import type { ReadRequests } from '../shared/readRequests';
import type { SIVIParentReadSession } from './siviParentReadSession';
import type { SIVIParentSourceSession } from './siviParentSourceSession';
import type { SIVIParentWriteSession, SIVIParentDirectColumn } from './siviParentWriteSession';
import type { SIVIParentActionWriteSession, SIVIParentActionColumn } from './siviParentActionWriteSession';
import type { SIVIProjectAssignmentSession, SIVIProjectAssignmentInput } from './siviProjectAssignmentSession';
import type { SIVIParentSharedSession, SIVIParentSharedColumn, SIVIParentSharedInput } from './siviParentSharedSession';
import type { SIVIParentInput } from './siviParentEditor';
import type { SIVIHeightColumn } from './siviHeightEditor';
import type { SIVIHeightSession } from './siviHeightSession';
import type { SIVICoverColumn } from './siviCoverEditor';
import type { SIVICoverSession } from './siviCoverSession';
import type { SIVICombinedColumn } from './siviCombinedEditor';
import type { SIVICombinedSession } from './siviCombinedSession';
import type { SIVICollectedSession } from './siviCollectedSession';
import type { SIVISpeciesSession } from './siviSpeciesSession';
import type { SIVIIdentitySession } from './siviIdentitySession';
import type { SIVIDeletionSession } from './siviDeletionSession';
import type { SIVIDeletionRestorationSession } from './siviDeletionRestorationSession';
import type { SIVICreationUndoSession } from './siviCreationUndoSession';
import type { SIVICreationDraft, SIVICreationForm } from './siviCreationEditor';
import type { TwoPageParentSessionCache, TwoPageParentForm } from './twoPageParentSession';
import type { TwoPageParentCommonSessionCache } from './twoPageParentCommonSession';
import type { TwoPageEntrySessionCache } from './twoPageEntrySession';
import type { EditorCloseState } from '../shell/closeLifecycle';

type SiviLifecycleOwner = 'creation' | 'deletion' | 'restoration' | 'creationUndo';

interface SiviSessionStateBundle {
  siviParentSession: SIVIParentReadSession | null;
  siviParentSourceSession: SIVIParentSourceSession | null;
  siviParentWriteSession: SIVIParentWriteSession | null;
  siviParentActionSession: SIVIParentActionWriteSession | null;
  siviProjectAssignmentSession: SIVIProjectAssignmentSession | null;
  siviParentSharedSession: SIVIParentSharedSession | null;
  siviSession: SIVIHeightSession | null;
  siviCoverSession: SIVICoverSession | null;
  siviCombinedSession: SIVICombinedSession | null;
  siviCollectedSession: SIVICollectedSession | null;
  siviSpeciesSession: SIVISpeciesSession | null;
  siviIdentitySession: SIVIIdentitySession | null;
}

interface SiviReadsBundle {
  siviParentReads: ReadRequests;
  siviParentSourceReads: ReadRequests;
  siviParentWriteReads: ReadRequests;
  siviParentActionReads: ReadRequests;
  siviProjectAssignmentReads: ReadRequests;
  siviParentSharedReads: ReadRequests;
  siviReads: ReadRequests;
  siviCoverReads: ReadRequests;
  siviCombinedReads: ReadRequests;
  siviCollectedReads: ReadRequests;
  siviSpeciesReads: ReadRequests;
  siviIdentityReads: ReadRequests;
}

/** Dispose all plot-owned SIVI sessions and cancel their outstanding child reads. */
export function disposePlotSiviSessions(sessions: SiviSessionStateBundle, reads: SiviReadsBundle): void {
  sessions.siviParentSession?.dispose();
  sessions.siviParentSourceSession?.dispose();
  sessions.siviParentWriteSession?.dispose();
  sessions.siviParentActionSession?.dispose();
  sessions.siviProjectAssignmentSession?.dispose();
  sessions.siviParentSharedSession?.dispose();
  sessions.siviSession?.dispose();
  reads.siviReads.cancelAll();
  sessions.siviCoverSession?.dispose();
  reads.siviCoverReads.cancelAll();
  sessions.siviCombinedSession?.dispose();
  reads.siviCombinedReads.cancelAll();
  sessions.siviCollectedSession?.dispose();
  reads.siviCollectedReads.cancelAll();
  sessions.siviSpeciesSession?.dispose();
  reads.siviSpeciesReads.cancelAll();
  sessions.siviIdentitySession?.dispose();
  reads.siviIdentityReads.cancelAll();
}

/** Dispose all open Two-Page caches on component teardown. */
export function disposeTwoPageSessionCaches(
  caches: Array<TwoPageParentSessionCache | TwoPageParentCommonSessionCache | TwoPageEntrySessionCache>
): void {
  for (const cache of caches) {
    for (const variants of cache.values()) {
      for (const owned of variants.values()) owned.dispose();
    }
  }
}

/** Refresh owned SIVI deletion/restoration/creation-undo target and history lists. */
export async function refreshSiviLifecycleListsImpl(params: {
  owner: SiviLifecycleOwner;
  deletionSession: SIVIDeletionSession | undefined;
  restorationSession: SIVIDeletionRestorationSession | undefined;
  creationUndoSession: SIVICreationUndoSession | undefined;
}): Promise<void> {
  if (
    params.deletionSession &&
    (params.owner === 'deletion' || params.deletionSession.view().targets !== null) &&
    !(await params.deletionSession.loadTargets())
  ) {
    throw new Error('Reload deletion source targets explicitly.');
  }
  if (
    params.restorationSession &&
    (params.owner === 'restoration' || params.restorationSession.view().history !== null) &&
    !(await params.restorationSession.loadHistory())
  ) {
    throw new Error('Reload owned deletion history explicitly.');
  }
  if (
    params.creationUndoSession &&
    (params.owner === 'creationUndo' || params.creationUndoSession.view().history !== null) &&
    !(await params.creationUndoSession.loadHistory())
  ) {
    throw new Error('Reload owned creation Undo history explicitly.');
  }
}

/** Reload SIVI parent header, ordinary child data, and open peer sessions after a parent commit. */
export async function refreshSiviParentImpl(params: {
  plot: string;
  siviContextId: string;
  activeContextId: string | undefined;
  peers: Array<
    | SIVIParentWriteSession
    | SIVIParentActionWriteSession
    | SIVIProjectAssignmentSession
    | SIVIParentSharedSession
    | null
  >;
  siviParentSession: SIVIParentReadSession | null;
  getPlot: (contextId: string, plot: string) => Promise<FS882Header | null>;
  applyRefreshedHeader: (header: FS882Header) => void;
  loadChildData: (plot: string) => Promise<void>;
}): Promise<void> {
  for (const peer of params.peers) {
    if (peer && (peer.closeState().unsaved || peer.closeState().busy)) {
      throw new Error('Another SIVI parent editor has drafts or an operation; no peer state was replaced.');
    }
  }
  const header = await params.getPlot(params.siviContextId, params.plot);
  if (!header || params.activeContextId !== params.siviContextId || header.plotNumber !== params.plot) {
    throw new Error('SIVI parent header refresh changed its context/plot owner.');
  }
  params.applyRefreshedHeader(header);
  await params.loadChildData(params.plot);
  if (params.siviParentSession && !(await params.siviParentSession.load())) {
    throw new Error(params.siviParentSession.view().error ?? 'Owned SIVI parent refresh did not finish.');
  }
  for (const peer of params.peers) {
    if (peer && (peer.view().original || peer.view().error) && !(await peer.load())) {
      throw new Error(peer.view().error ?? 'Peer SIVI parent original refresh did not finish.');
    }
  }
}

/** Refresh peer two-page scopes and parent editors after committing one two-page scope. */
export async function refreshTwoPagePeersImpl(params: {
  scope: 'extra' | 'common' | 'entry';
  contextId: string;
  twoPageProject: string | null;
  plotNumber: string;
  twoPageSessions: TwoPageParentSessionCache;
  twoPageCommonSessions: TwoPageParentCommonSessionCache;
  twoPageEntrySessions: TwoPageEntrySessionCache;
  refreshParent: () => Promise<void>;
}): Promise<void> {
  await params.refreshParent();
  for (const cohort of [
    { scope: 'extra' as const, cache: params.twoPageSessions },
    { scope: 'common' as const, cache: params.twoPageCommonSessions },
    { scope: 'entry' as const, cache: params.twoPageEntrySessions },
  ]) {
    if (cohort.scope === params.scope) continue;
    const variants = cohort.cache.get(
      JSON.stringify({ contextId: params.contextId, project: params.twoPageProject, plot: params.plotNumber })
    );
    if (!variants) continue;
    for (const peer of variants.values()) {
      if (!peer.view().original && !peer.view().error) continue;
      if (peer.closeState().unsaved || peer.closeState().busy || !(await peer.load())) {
        throw new Error(
          peer.view().error ?? 'Another two-page field scope could not be refreshed; no write was replayed.'
        );
      }
    }
  }
}

/** Extract unique trimmed ProjectID options from wire choices. */
function extractProjectIdChoices(choices: SIVIProjectChoices | null | undefined): string[] {
  const rows = choices?.Choices?.rows;
  if (!rows?.length) return [];
  return [
    ...new Set(
      rows.map((r) => (r.cells?.[0]?.storage === 'text' ? (r.cells[0].text ?? '').trim() : '')).filter(Boolean)
    ),
  ];
}

/** Observe ProjectID datalist choices directly or via owned context fetch. */
export function observeProjectIdDatalist(params: {
  sourceChoices: SIVIProjectChoices | null | undefined;
  assignmentChoices: SIVIProjectChoices | null | undefined;
  contextId: string;
  fetchChoices?: (cid: string) => Promise<SIVIProjectChoices | null>;
  onChoices: (choices: string[]) => void;
}): (() => void) | undefined {
  const next = extractProjectIdChoices(params.sourceChoices ?? params.assignmentChoices);
  if (next.length) {
    params.onChoices(next);
    return undefined;
  }
  if (!params.contextId || !params.fetchChoices) return undefined;
  let active = true;
  void params
    .fetchChoices(params.contextId)
    .then((res) => {
      if (!active) return;
      const choices = extractProjectIdChoices(res);
      if (choices.length) params.onChoices(choices);
    })
    .catch(() => {});
  return () => {
    active = false;
  };
}

export type {
  EditorCloseState,
  SIVICollectedSession,
  SIVICombinedColumn,
  SIVICombinedSession,
  SIVICoverColumn,
  SIVICoverSession,
  SIVICreationDraft,
  SIVICreationForm,
  SIVIHeightColumn,
  SIVIHeightSession,
  SIVIIdentitySession,
  SIVIParentActionColumn,
  SIVIParentActionWriteSession,
  SIVIParentDirectColumn,
  SIVIParentInput,
  SIVIParentReadSession,
  SIVIParentSharedColumn,
  SIVIParentSharedInput,
  SIVIParentSharedSession,
  SIVIParentSourceSession,
  SIVIParentWriteSession,
  SIVIProjectAssignmentInput,
  SIVIProjectAssignmentSession,
  SIVISpeciesSession,
  TwoPageEntrySessionCache,
  TwoPageParentCommonSessionCache,
  TwoPageParentForm,
  TwoPageParentSessionCache,
};
