import {
  AuditRestoreAction,
  ContextService,
  PlotEntryService,
  type FS882Header,
} from '../../bindings/github.com/boostao/vpro/app';
import { pictureMetadataSession as ownedPictureMetadataSession } from '../pictures/pictureMetadataSessions';
import { formatError, ReadRequests } from '../shared/readRequests';
import { observeSession } from '../shared/reactiveSession.svelte';
import type { EditorCloseState } from '../shell/closeLifecycle';
import {
  firstMatch,
  refreshSiviChildEditorsImpl,
  runReviewedSiviOp,
  runStageSivi,
  type ReviewedSiviOperation,
} from './fs882FormHelpers';
import { formatSiviRestorationTargets } from './fs882FormLoadSave';
import {
  disposePlotSiviSessions,
  refreshSiviLifecycleListsImpl,
  refreshSiviParentImpl,
  type SIVICombinedColumn,
  type SIVICoverColumn,
  type SIVICreationDraft,
  type SIVICreationForm,
  type SIVIHeightColumn,
  type SIVIParentActionColumn,
  type SIVIParentDirectColumn,
  type SIVIParentInput,
  type SIVIParentSharedColumn,
  type SIVIParentSharedInput,
  type SIVIProjectAssignmentInput,
} from './fs882FormSivi';
import {
  executeSiviCreationOpImpl,
  executeSiviCreationUndoOpImpl,
  executeSiviLifecycleOpImpl,
} from './fs882FormSiviOps';
import { SIVICollectedSession } from './siviCollectedSession';
import { SIVICombinedSession } from './siviCombinedSession';
import { SIVICoverSession } from './siviCoverSession';
import { siviCreationSession as ownedSIVICreationSession } from './siviCreationSessions';
import { siviCreationUndoSession as ownedSIVICreationUndoSession } from './siviCreationUndoSessions';
import {
  siviDeletionRestorationSession as ownedSIVIRestorationSession,
  siviDeletionSession as ownedSIVIDeletionSession,
} from './siviDeletionSessions';
import { SIVIHeightSession } from './siviHeightSession';
import { SIVIIdentitySession } from './siviIdentitySession';
import { SIVIParentActionWriteSession, isSIVIParentActionColumn } from './siviParentActionWriteSession';
import { SIVIParentReadSession } from './siviParentReadSession';
import { SIVIParentSharedSession, siviParentSharedFieldsFor } from './siviParentSharedSession';
import { SIVIParentSourceSession } from './siviParentSourceSession';
import { SIVIParentWriteSession, isSIVIParentDirectColumn } from './siviParentWriteSession';
import { SIVIProjectAssignmentSession } from './siviProjectAssignmentSession';
import { SIVISpeciesSession } from './siviSpeciesSession';
import type { SpeciesDecisionKind } from './vegetationSpeciesEditor';

export interface SiviSessionsDeps {
  contextId: string;
  reads: ReadRequests;
  getActiveContextId: () => string | undefined;
  getActiveProject: () => string | undefined;
  getOriginal: () => FS882Header | null;
  getDraftLocked: () => boolean;
  getBusy: () => boolean;
  getDirty: () => boolean;
  getNonArcticHeaderDirty: () => boolean;
  getCapabilitiesReady: () => boolean;
  getHeaderValidationCount: () => number;
  getOtherHeaderWorkflowBusy: () => boolean;
  getHeaderWorkflowBusy: () => boolean;
  getPictureBusy: () => boolean;
  getChildParentDisabled: () => boolean;
  getOrdinaryChildPeerUnsaved: () => boolean;
  getHasPersonalDraft: () => boolean;
  getSiviCreationPeerUnsaved: () => boolean;
  getNonParentChildUnsaved: () => boolean;
  getChildUnsaved: () => boolean;
  getCurrentError: () => string | null;
  setError: (msg: string | null) => void;
  setSuccess: (msg: string | null) => void;
  invalidateCapabilities: () => void;
  onShowParentTab: () => void;
  loadChildData: (plot: string) => Promise<void>;
  applyRefreshedHeader: (header: FS882Header) => void;
}

export function createSiviSessions(deps: SiviSessionsDeps) {
  const sharedColumns: readonly SIVIParentSharedColumn[] = siviParentSharedFieldsFor(true).map((f) => f.column);
  const parentSharedReads = new ReadRequests();
  const parentWriteReads = new ReadRequests();
  const parentActionReads = new ReadRequests();
  const projectAssignmentReads = new ReadRequests();
  const parentReads = new ReadRequests();
  const parentSourceReads = new ReadRequests();
  const heightReads = new ReadRequests();
  const coverReads = new ReadRequests();
  const combinedReads = new ReadRequests();
  const collectedReads = new ReadRequests();
  const speciesReads = new ReadRequests();
  const identityReads = new ReadRequests();

  let parentSharedSession = $state<SIVIParentSharedSession | null>(null);
  let parentSharedVer = $state(0);
  let parentWriteSession = $state<SIVIParentWriteSession | null>(null);
  let parentWriteVer = $state(0);
  let parentActionSession = $state<SIVIParentActionWriteSession | null>(null);
  let parentActionVer = $state(0);
  let projectAssignmentSession = $state<SIVIProjectAssignmentSession | null>(null);
  let projectAssignmentVer = $state(0);
  let parentSourceSession = $state<SIVIParentSourceSession | null>(null);
  let parentSourceVer = $state(0);
  let parentSession = $state<SIVIParentReadSession | null>(null);
  let parentVer = $state(0);
  let parentOpen = $state(false);

  let heightSession: SIVIHeightSession | null = null;
  let heightVer = $state(0);
  let heightPanelOpen = $state(false);
  let coverSession: SIVICoverSession | null = null;
  let coverVer = $state(0);
  let coverPanelOpen = $state(false);
  let coverReading = $state(false);
  let combinedSession: SIVICombinedSession | null = null;
  let combinedVer = $state(0);
  let combinedPanelOpen = $state(false);
  let combinedReading = $state(false);
  let collectedSession: SIVICollectedSession | null = null;
  let collectedVer = $state(0);
  let collectedPanelOpen = $state(false);
  let collectedReading = $state(false);
  let speciesSession: SIVISpeciesSession | null = null;
  let speciesVer = $state(0);
  let speciesPanelOpen = $state(false);
  let speciesReading = $state(false);
  let identitySession: SIVIIdentitySession | null = null;
  let identityVer = $state(0);
  let identityPanelOpen = $state(false);
  let identityReading = $state(false);

  let creationHostBusy = $state(false);
  let lifecycleHostBusy = $state(false);

  const parentSharedView = $derived.by(() => {
    void parentSharedVer;
    return parentSharedSession?.view() ?? null;
  });
  const parentSharedClose = $derived.by(() => {
    void parentSharedVer;
    return parentSharedSession?.closeState() ?? null;
  });
  const parentSharedUnsaved = $derived(parentSharedClose?.unsaved ?? false);
  const parentWriteView = $derived.by(() => {
    void parentWriteVer;
    return parentWriteSession?.view() ?? null;
  });
  const parentWriteClose = $derived.by(() => {
    void parentWriteVer;
    return parentWriteSession?.closeState() ?? null;
  });
  const parentWriteUnsaved = $derived(parentWriteClose?.unsaved ?? false);
  const parentActionView = $derived.by(() => {
    void parentActionVer;
    return parentActionSession?.view() ?? null;
  });
  const parentActionClose = $derived.by(() => {
    void parentActionVer;
    return parentActionSession?.closeState() ?? null;
  });
  const parentActionUnsaved = $derived(parentActionClose?.unsaved ?? false);
  const projectAssignmentView = $derived.by(() => {
    void projectAssignmentVer;
    return projectAssignmentSession?.view() ?? null;
  });
  const projectAssignmentClose = $derived.by(() => {
    void projectAssignmentVer;
    return projectAssignmentSession?.closeState() ?? null;
  });
  const projectAssignmentUnsaved = $derived(projectAssignmentClose?.unsaved ?? false);
  const parentSourceView = $derived.by(() => {
    void parentSourceVer;
    return parentSourceSession?.view() ?? null;
  });
  const sourceAuthorityUnknown = $derived(parentSourceView?.authorityUnknown ?? false);
  const sourceBarrier = $derived(Boolean(parentSourceView?.saving) || sourceAuthorityUnknown);
  const parentView = $derived.by(() => {
    void parentVer;
    return parentSession?.view() ?? null;
  });
  const parentBusy = $derived(
    (parentView?.busy ?? false) ||
      (parentSourceView?.busy ?? false) ||
      (parentWriteView?.busy ?? false) ||
      (parentActionView?.busy ?? false) ||
      (projectAssignmentView?.busy ?? false) ||
      (parentSharedView?.busy ?? false)
  );

  const heightView = $derived.by(() => {
    void heightVer;
    return heightSession?.view() ?? null;
  });
  const heightClose = $derived.by(() => {
    void heightVer;
    return heightSession?.closeState() ?? null;
  });
  const heightUnsaved = $derived(heightClose?.unsaved ?? false);
  const heightBusy = $derived(heightClose?.busy ?? false);
  const coverView = $derived.by(() => {
    void coverVer;
    return coverSession?.view() ?? null;
  });
  const coverClose = $derived.by(() => {
    void coverVer;
    return coverSession?.closeState() ?? null;
  });
  const coverUnsaved = $derived(coverClose?.unsaved ?? false);
  const coverBusy = $derived(coverClose?.busy ?? false);
  const combinedView = $derived.by(() => {
    void combinedVer;
    return combinedSession?.view() ?? null;
  });
  const combinedClose = $derived.by(() => {
    void combinedVer;
    return combinedSession?.closeState() ?? null;
  });
  const combinedUnsaved = $derived(combinedClose?.unsaved ?? false);
  const combinedBusy = $derived(combinedClose?.busy ?? false);
  const collectedView = $derived.by(() => {
    void collectedVer;
    return collectedSession?.view() ?? null;
  });
  const collectedClose = $derived.by(() => {
    void collectedVer;
    return collectedSession?.closeState() ?? null;
  });
  const collectedUnsaved = $derived(collectedClose?.unsaved ?? false);
  const collectedBusy = $derived(collectedClose?.busy ?? false);
  const speciesView = $derived.by(() => {
    void speciesVer;
    return speciesSession?.view() ?? null;
  });
  const speciesClose = $derived.by(() => {
    void speciesVer;
    return speciesSession?.closeState() ?? null;
  });
  const speciesUnsaved = $derived(speciesClose?.unsaved ?? false);
  const speciesBusy = $derived(speciesClose?.busy ?? false);
  const identityView = $derived.by(() => {
    void identityVer;
    return identitySession?.view() ?? null;
  });
  const identityClose = $derived.by(() => {
    void identityVer;
    return identitySession?.closeState() ?? null;
  });
  const identityUnsaved = $derived(identityClose?.unsaved ?? false);
  const identityBusy = $derived(identityClose?.busy ?? false);

  const ownerScope = $derived.by(() => {
    const project = deps.getActiveProject();
    const plot = deps.getOriginal()?.plotNumber;
    return deps.contextId && project && plot ? { contextId: deps.contextId, project, plot } : undefined;
  });

  const pictureMetadataSession = $derived(
    ownerScope
      ? ownedPictureMetadataSession({
          contextId: ownerScope.contextId,
          project: ownerScope.project,
          plotNumber: ownerScope.plot,
        })
      : undefined
  );
  const pictureMetadataObs = observeSession(
    () => pictureMetadataSession,
    (s) => s.closeState()
  );
  const pictureMetadataClose = $derived(pictureMetadataObs.current);
  const pictureMetadataPending = $derived(
    Boolean(
      pictureMetadataClose &&
      (pictureMetadataClose.unsaved || pictureMetadataClose.blocked || pictureMetadataClose.busy)
    )
  );

  const creationSession = $derived(ownerScope ? ownedSIVICreationSession(ownerScope) : undefined);
  const creationObs = observeSession(
    () => creationSession,
    (s) => ({ view: s.view(), close: s.closeState() })
  );
  const creationView = $derived(creationObs.current?.view);
  const creationClose = $derived(creationObs.current?.close);
  const creationPending = $derived(
    Boolean(creationClose && (creationClose.unsaved || creationClose.blocked || creationClose.busy))
  );
  const creationBusy = $derived(creationHostBusy || (creationClose?.busy ?? false));

  const deletionSession = $derived(ownerScope ? ownedSIVIDeletionSession(ownerScope) : undefined);
  const deletionObs = observeSession(
    () => deletionSession,
    (s) => ({ view: s.view(), close: s.closeState() })
  );
  const deletionView = $derived(deletionObs.current?.view);
  const deletionClose = $derived(deletionObs.current?.close);
  const deletionPending = $derived(
    Boolean(deletionClose && (deletionClose.unsaved || deletionClose.blocked || deletionClose.busy))
  );

  const restorationSession = $derived(ownerScope ? ownedSIVIRestorationSession(ownerScope) : undefined);
  const restorationObs = observeSession(
    () => restorationSession,
    (s) => ({ view: s.view(), close: s.closeState() })
  );
  const restorationView = $derived(restorationObs.current?.view);
  const restorationClose = $derived(restorationObs.current?.close);
  const restorationPending = $derived(
    Boolean(restorationClose && (restorationClose.unsaved || restorationClose.blocked || restorationClose.busy))
  );

  const creationUndoSession = $derived(ownerScope ? ownedSIVICreationUndoSession(ownerScope) : undefined);
  const creationUndoObs = observeSession(
    () => creationUndoSession,
    (s) => ({ view: s.view(), close: s.closeState() })
  );
  const creationUndoView = $derived(creationUndoObs.current?.view);
  const creationUndoClose = $derived(creationUndoObs.current?.close);
  const creationUndoPending = $derived(
    Boolean(creationUndoClose && (creationUndoClose.unsaved || creationUndoClose.blocked || creationUndoClose.busy))
  );

  const lifecycleBusy = $derived(
    lifecycleHostBusy ||
      (deletionClose?.busy ?? false) ||
      (restorationClose?.busy ?? false) ||
      (creationUndoClose?.busy ?? false)
  );
  const restorationTargets = $derived(formatSiviRestorationTargets(restorationView));

  const anyChildUnsaved = $derived(
    heightUnsaved || coverUnsaved || combinedUnsaved || collectedUnsaved || speciesUnsaved || identityUnsaved
  );
  const anyParentUnsaved = $derived(
    parentWriteUnsaved || parentActionUnsaved || projectAssignmentUnsaved || parentSharedUnsaved
  );
  const anyLifecyclePending = $derived(creationPending || deletionPending || restorationPending || creationUndoPending);
  const anyBusy = $derived(
    parentBusy ||
      heightBusy ||
      combinedBusy ||
      coverBusy ||
      collectedBusy ||
      speciesBusy ||
      identityBusy ||
      creationBusy ||
      lifecycleBusy
  );

  function recoveryBaseBlocked(selfBusy: boolean, hostBusy: boolean, otherLifecyclePending: boolean): boolean {
    return (
      deps.getBusy() ||
      hostBusy ||
      (deps.getOtherHeaderWorkflowBusy() && !selfBusy) ||
      deps.getPictureBusy() ||
      pictureMetadataPending ||
      deps.getSiviCreationPeerUnsaved() ||
      otherLifecyclePending ||
      anyParentUnsaved
    );
  }
  function editingGateBlocked(): boolean {
    return (
      !deps.getCapabilitiesReady() ||
      deps.getDraftLocked() ||
      sourceBarrier ||
      deps.getDirty() ||
      deps.getOriginal() === null ||
      deps.getHasPersonalDraft() ||
      deps.getHeaderValidationCount() > 0
    );
  }

  const creationRecoveryDisabled = $derived(
    recoveryBaseBlocked(
      creationClose?.busy ?? false,
      creationHostBusy,
      deletionPending || restorationPending || creationUndoPending
    )
  );
  const deletionRecoveryDisabled = $derived(
    recoveryBaseBlocked(
      deletionClose?.busy ?? false,
      lifecycleHostBusy,
      creationPending || restorationPending || creationUndoPending
    )
  );
  const restorationRecoveryDisabled = $derived(
    recoveryBaseBlocked(
      restorationClose?.busy ?? false,
      lifecycleHostBusy,
      creationPending || deletionPending || creationUndoPending
    )
  );
  const creationUndoRecoveryDisabled = $derived(
    recoveryBaseBlocked(
      creationUndoClose?.busy ?? false,
      lifecycleHostBusy,
      creationPending || deletionPending || restorationPending
    )
  );
  const creationEditingDisabled = $derived(creationRecoveryDisabled || editingGateBlocked());
  const deletionEditingDisabled = $derived(deletionRecoveryDisabled || editingGateBlocked());
  const restorationEditingDisabled = $derived(restorationRecoveryDisabled || editingGateBlocked());
  const creationUndoEditingDisabled = $derived(creationUndoRecoveryDisabled || editingGateBlocked());

  function parentCommonBlocked(otherParentsUnsaved: boolean, dirtyFlag: boolean): boolean {
    return (
      !deps.getCapabilitiesReady() ||
      deps.getDraftLocked() ||
      deps.getBusy() ||
      deps.getHeaderWorkflowBusy() ||
      dirtyFlag ||
      deps.getOriginal() === null ||
      deps.getNonParentChildUnsaved() ||
      otherParentsUnsaved ||
      deps.getHasPersonalDraft() ||
      sourceAuthorityUnknown ||
      deps.getHeaderValidationCount() > 0
    );
  }
  const parentSharedEditingDisabled = $derived(
    parentCommonBlocked(
      parentWriteUnsaved || parentActionUnsaved || projectAssignmentUnsaved,
      deps.getNonArcticHeaderDirty()
    ) ||
      (parentSharedView?.blocked ?? false)
  );
  const parentWriteEditingDisabled = $derived(
    parentCommonBlocked(parentActionUnsaved || projectAssignmentUnsaved || parentSharedUnsaved, deps.getDirty()) ||
      (parentWriteView?.blocked ?? false)
  );
  const parentActionEditingDisabled = $derived(
    parentCommonBlocked(parentWriteUnsaved || projectAssignmentUnsaved || parentSharedUnsaved, deps.getDirty()) ||
      (parentActionView?.blocked ?? false)
  );
  const projectAssignmentEditingDisabled = $derived(
    parentCommonBlocked(parentWriteUnsaved || parentActionUnsaved || parentSharedUnsaved, deps.getDirty()) ||
      Boolean(parentSourceView?.error) ||
      (projectAssignmentView?.blocked ?? false)
  );

  function childPanelDisabled(peerSiviUnsaved: boolean, viewBlocked: boolean): boolean {
    return (
      deps.getChildParentDisabled() ||
      peerSiviUnsaved ||
      deps.getOrdinaryChildPeerUnsaved() ||
      deps.getHeaderValidationCount() > 0 ||
      viewBlocked
    );
  }
  const heightEditingDisabled = $derived(
    childPanelDisabled(
      coverUnsaved || combinedUnsaved || collectedUnsaved || speciesUnsaved || identityUnsaved,
      heightView?.blocked ?? false
    )
  );
  const coverEditingDisabled = $derived(
    childPanelDisabled(
      heightUnsaved || combinedUnsaved || collectedUnsaved || speciesUnsaved || identityUnsaved,
      coverView?.blocked ?? false
    )
  );
  const combinedEditingDisabled = $derived(
    childPanelDisabled(
      heightUnsaved || coverUnsaved || collectedUnsaved || speciesUnsaved || identityUnsaved,
      combinedView?.blocked ?? false
    )
  );
  const collectedEditingDisabled = $derived(
    childPanelDisabled(
      heightUnsaved || coverUnsaved || combinedUnsaved || speciesUnsaved || identityUnsaved,
      collectedView?.blocked ?? false
    )
  );
  const speciesEditingDisabled = $derived(
    childPanelDisabled(
      heightUnsaved || coverUnsaved || combinedUnsaved || collectedUnsaved || identityUnsaved,
      speciesView?.blocked ?? false
    )
  );
  const identityEditingDisabled = $derived(
    childPanelDisabled(
      heightUnsaved || coverUnsaved || combinedUnsaved || collectedUnsaved || speciesUnsaved,
      identityView?.blocked ?? false
    )
  );

  function setPresentation(extended: boolean) {
    for (const s of [heightSession, coverSession, combinedSession, collectedSession, speciesSession, identitySession]) {
      s?.presentation(extended);
    }
  }

  function refreshParent(
    plot: string,
    peers: (
      | SIVIParentWriteSession
      | SIVIParentActionWriteSession
      | SIVIProjectAssignmentSession
      | SIVIParentSharedSession
      | null
    )[]
  ) {
    return refreshSiviParentImpl({
      plot,
      siviContextId: deps.contextId,
      activeContextId: deps.getActiveContextId(),
      peers,
      siviParentSession: parentSession,
      getPlot: (cid, p) => deps.reads.track(ContextService.GetPlot(cid, p)),
      applyRefreshedHeader: deps.applyRefreshedHeader,
      loadChildData: deps.loadChildData,
    });
  }

  function refreshAllParentPeers(plot: string) {
    return refreshParent(plot, [
      parentWriteSession,
      parentActionSession,
      projectAssignmentSession,
      parentSharedSession,
    ]);
  }

  function refreshChildEditors(
    plot: string,
    owner:
      | 'height'
      | 'cover'
      | 'combined'
      | 'collected'
      | 'species'
      | 'identity'
      | 'creation'
      | 'deletion'
      | 'restoration'
      | 'creationUndo'
  ) {
    return refreshSiviChildEditorsImpl({
      plot,
      owner,
      siviCreationPending: creationPending,
      siviDeletionPending: deletionPending,
      siviRestorationPending: restorationPending,
      siviCreationUndoPending: creationUndoPending,
      sessions: {
        height: heightSession,
        cover: coverSession,
        combined: combinedSession,
        collected: collectedSession,
        species: speciesSession,
        identity: identitySession,
      },
      loadChildData: deps.loadChildData,
    });
  }

  function refreshLifecycleLists(owner: 'creation' | 'deletion' | 'restoration' | 'creationUndo') {
    return refreshSiviLifecycleListsImpl({ owner, deletionSession, restorationSession, creationUndoSession });
  }

  function parentWriteOperation(op: ReviewedSiviOperation) {
    return runReviewedSiviOp({
      kind: 'parentWrite',
      operation: op,
      allowed: !(
        deps.getBusy() ||
        deps.getHeaderWorkflowBusy() ||
        parentActionUnsaved ||
        projectAssignmentUnsaved ||
        parentSharedUnsaved ||
        (op !== 'undo' && parentWriteEditingDisabled)
      ),
      getOwner: () => parentWriteSession,
      retainAction: AuditRestoreAction.AuditRestoreRetain,
      pruneAction: AuditRestoreAction.AuditRestorePrune,
      setError: deps.setError,
      setSuccess: deps.setSuccess,
    });
  }
  function parentActionOperation(op: ReviewedSiviOperation) {
    return runReviewedSiviOp({
      kind: 'parentAction',
      operation: op,
      allowed: !(
        deps.getBusy() ||
        deps.getHeaderWorkflowBusy() ||
        parentWriteUnsaved ||
        projectAssignmentUnsaved ||
        parentSharedUnsaved ||
        (op !== 'undo' && parentActionEditingDisabled)
      ),
      getOwner: () => parentActionSession,
      retainAction: AuditRestoreAction.AuditRestoreRetain,
      pruneAction: AuditRestoreAction.AuditRestorePrune,
      setError: deps.setError,
      setSuccess: deps.setSuccess,
    });
  }
  function stageParentAction(col: string, input: SIVIParentInput) {
    runStageSivi({
      allowed: Boolean(parentActionSession && !parentActionEditingDisabled && isSIVIParentActionColumn(col)),
      guardMessage: 'Only independently available SIVI source actions can be drafted.',
      errorPrefix: '',
      failPrefix: 'SIVI source-action draft failed; existing state retained',
      action: () => parentActionSession!.stage(col as SIVIParentActionColumn, input),
      readError: () => parentActionSession!.view().error,
      currentError: deps.getCurrentError(),
      setError: deps.setError,
      setSuccess: deps.setSuccess,
    });
  }
  function projectAssignmentOperation(op: ReviewedSiviOperation) {
    return runReviewedSiviOp({
      kind: 'projectAssignment',
      operation: op,
      allowed: !(
        deps.getBusy() ||
        deps.getHeaderWorkflowBusy() ||
        parentWriteUnsaved ||
        parentActionUnsaved ||
        parentSharedUnsaved ||
        (op !== 'undo' && projectAssignmentEditingDisabled)
      ),
      getOwner: () => projectAssignmentSession,
      retainAction: AuditRestoreAction.AuditRestoreRetain,
      pruneAction: AuditRestoreAction.AuditRestorePrune,
      setError: deps.setError,
      setSuccess: deps.setSuccess,
    });
  }
  function stageProjectAssignment(input: SIVIProjectAssignmentInput) {
    runStageSivi({
      allowed: Boolean(projectAssignmentSession && !projectAssignmentEditingDisabled),
      guardMessage: 'Only independently available existing ProjectID definitions can be selected.',
      errorPrefix: '',
      failPrefix: 'ProjectID selection failed; existing state retained',
      action: () => projectAssignmentSession!.stage('ProjectID', input),
      readError: () => projectAssignmentSession!.view().error,
      currentError: deps.getCurrentError(),
      setError: deps.setError,
      setSuccess: deps.setSuccess,
    });
  }
  function stageParentShared(col: SIVIParentSharedColumn, input: SIVIParentSharedInput) {
    runStageSivi({
      allowed: Boolean(parentSharedSession && !parentSharedEditingDisabled),
      guardMessage: 'Shared SIVI fields require their clean owned parent.',
      errorPrefix: '',
      failPrefix: 'Shared SIVI draft failed; owned state retained',
      action: () => parentSharedSession!.stage(col, input),
      readError: () => parentSharedSession!.view().error,
      currentError: deps.getCurrentError(),
      setError: deps.setError,
      setSuccess: deps.setSuccess,
    });
  }
  function parentSharedOperation(op: ReviewedSiviOperation) {
    return runReviewedSiviOp({
      kind: 'parentShared',
      operation: op,
      allowed: !(
        deps.getBusy() ||
        deps.getHeaderWorkflowBusy() ||
        parentWriteUnsaved ||
        parentActionUnsaved ||
        projectAssignmentUnsaved ||
        (op !== 'undo' && parentSharedEditingDisabled)
      ),
      getOwner: () => parentSharedSession,
      retainAction: AuditRestoreAction.AuditRestoreRetain,
      pruneAction: AuditRestoreAction.AuditRestorePrune,
      setError: deps.setError,
      setSuccess: deps.setSuccess,
    });
  }
  function stageParentCell(col: string, input: SIVIParentInput) {
    runStageSivi({
      allowed: Boolean(parentWriteSession && !parentWriteEditingDisabled && isSIVIParentDirectColumn(col)),
      guardMessage: 'Only available directly bound SIVI parent fields can be drafted.',
      errorPrefix: '',
      failPrefix: 'SIVI parent draft failed; existing state retained',
      action: () => parentWriteSession!.stage(col as SIVIParentDirectColumn, input),
      readError: () => parentWriteSession!.view().error,
      currentError: deps.getCurrentError(),
      setError: deps.setError,
      setSuccess: deps.setSuccess,
    });
  }
  async function changeProjectSource(source: number) {
    if (
      !parentSourceSession ||
      deps.getBusy() ||
      deps.getHeaderWorkflowBusy() ||
      deps.getDirty() ||
      deps.getChildUnsaved()
    ) {
      deps.setError('Finish or Undo owned plot/selection drafts before changing ProjectID source.');
      return;
    }
    deps.setError(null);
    try {
      if (!(await parentSourceSession.setSource(source))) {
        deps.setError(parentSourceSession.view().error);
        return;
      }
      if (projectAssignmentSession?.view().original && !(await projectAssignmentSession.load()))
        deps.setError(projectAssignmentSession.view().error);
    } catch (cause) {
      deps.setError(`ProjectID source change failed; owned state retained: ${formatError(cause)}`);
    }
  }
  async function reloadProjectSource() {
    if (
      !parentSourceSession ||
      deps.getBusy() ||
      deps.getHeaderWorkflowBusy() ||
      deps.getDirty() ||
      deps.getChildUnsaved()
    ) {
      deps.setError('Finish or Undo owned plot/selection drafts before reloading ProjectID source.');
      return;
    }
    deps.setError(null);
    try {
      if (!(await parentSourceSession.load())) {
        deps.setError(parentSourceSession.view().error);
        return;
      }
      if (projectAssignmentSession?.view().original && !(await projectAssignmentSession.load()))
        deps.setError(projectAssignmentSession.view().error);
    } catch (cause) {
      deps.setError(`ProjectID source reload failed; owned state retained: ${formatError(cause)}`);
    }
  }
  async function loadParentOriginals() {
    const parent = parentSession;
    if (!parent) throw new Error('SIVI parent originals have no current owned session.');
    if (!parent.view().original && !(await parent.load())) return;
    if (parentSession !== parent) return;
    if (
      !anyParentUnsaved &&
      parentSourceSession &&
      !parentSourceView?.choices &&
      !parentSourceView?.error &&
      !parentSourceView?.authorityUnknown
    ) {
      await parentSourceSession.load();
    }
  }
  async function showParentPanel() {
    if (
      deps.getBusy() ||
      deps.getHeaderWorkflowBusy() ||
      deps.getDirty() ||
      deps.getNonParentChildUnsaved() ||
      !parentSession
    ) {
      deps.setError('SIVI parent requires a clean available owned plot and its parent-review gate.');
      return;
    }
    deps.onShowParentTab();
    parentOpen = true;
    await loadParentOriginals();
  }

  function closeOtherVegPanels(keep: 'height' | 'cover' | 'combined' | 'collected' | 'species' | 'identity') {
    heightPanelOpen = keep === 'height';
    coverPanelOpen = keep === 'cover';
    combinedPanelOpen = keep === 'combined';
    collectedPanelOpen = keep === 'collected';
    speciesPanelOpen = keep === 'species';
    identityPanelOpen = keep === 'identity';
  }

  function heightOperation(op: ReviewedSiviOperation) {
    return runReviewedSiviOp({
      kind: 'height',
      operation: op,
      allowed: !(
        deps.getBusy() ||
        deps.getHeaderWorkflowBusy() ||
        coverUnsaved ||
        combinedUnsaved ||
        collectedUnsaved ||
        speciesUnsaved ||
        identityUnsaved ||
        (op !== 'undo' && heightEditingDisabled)
      ),
      getOwner: () => heightSession,
      retainAction: AuditRestoreAction.AuditRestoreRetain,
      pruneAction: AuditRestoreAction.AuditRestorePrune,
      setError: deps.setError,
      setSuccess: deps.setSuccess,
    });
  }
  function stageHeightCell(rowId: string, col: SIVIHeightColumn, raw: string, nullValue: boolean) {
    runStageSivi({
      allowed: Boolean(heightSession && !heightEditingDisabled),
      guardMessage: 'Unlock the clean available parent before editing SIVI heights.',
      errorPrefix: 'SIVI ',
      failPrefix: 'SIVI draft failed; original/raw state retained',
      action: () => heightSession!.stage(rowId, col, raw, nullValue),
      readError: () => heightSession!.view().error,
      currentError: deps.getCurrentError(),
      setError: deps.setError,
      setSuccess: deps.setSuccess,
    });
  }
  async function showHeightPanel() {
    if (heightPanelOpen) {
      heightPanelOpen = false;
      return;
    }
    if (heightEditingDisabled && !heightUnsaved) {
      deps.setError('SIVI requires a clean, unlocked available parent.');
      return;
    }
    closeOtherVegPanels('height');
    if (!heightView?.review && !heightUnsaved) await heightOperation('load');
  }

  function coverOperation(op: ReviewedSiviOperation) {
    return runReviewedSiviOp({
      kind: 'cover',
      operation: op,
      allowed: !(
        deps.getBusy() ||
        deps.getHeaderWorkflowBusy() ||
        heightUnsaved ||
        combinedUnsaved ||
        collectedUnsaved ||
        speciesUnsaved ||
        identityUnsaved ||
        deps.getOrdinaryChildPeerUnsaved() ||
        anyParentUnsaved ||
        (op !== 'undo' && coverEditingDisabled)
      ),
      getOwner: () => coverSession,
      retainAction: AuditRestoreAction.AuditRestoreRetain,
      pruneAction: AuditRestoreAction.AuditRestorePrune,
      onReading: (r) => {
        coverReading = r;
      },
      setError: deps.setError,
      setSuccess: deps.setSuccess,
    });
  }
  function stageCoverCell(rowId: string, col: SIVICoverColumn, raw: string, nullValue: boolean) {
    runStageSivi({
      allowed: Boolean(coverSession && !coverEditingDisabled),
      guardMessage: 'Unlock the clean available parent before editing SIVI covers.',
      errorPrefix: 'SIVI cover ',
      failPrefix: 'SIVI cover draft failed; original/raw state retained',
      action: () => coverSession!.stage(rowId, col, raw, nullValue),
      readError: () => coverSession!.view().error,
      currentError: deps.getCurrentError(),
      setError: deps.setError,
      setSuccess: deps.setSuccess,
    });
  }
  async function showCoverPanel() {
    if (coverPanelOpen) {
      coverPanelOpen = false;
      return;
    }
    if (coverEditingDisabled && !coverUnsaved) {
      deps.setError('SIVI covers require a clean, unlocked available parent.');
      return;
    }
    closeOtherVegPanels('cover');
    if (!coverView?.review && !coverUnsaved) await coverOperation('load');
  }

  function combinedOperation(op: ReviewedSiviOperation) {
    return runReviewedSiviOp({
      kind: 'combined',
      operation: op,
      allowed: !(
        deps.getBusy() ||
        deps.getHeaderWorkflowBusy() ||
        heightUnsaved ||
        coverUnsaved ||
        collectedUnsaved ||
        speciesUnsaved ||
        identityUnsaved ||
        deps.getOrdinaryChildPeerUnsaved() ||
        anyParentUnsaved ||
        (op !== 'undo' && combinedEditingDisabled)
      ),
      getOwner: () => combinedSession,
      retainAction: AuditRestoreAction.AuditRestoreRetain,
      pruneAction: AuditRestoreAction.AuditRestorePrune,
      trackOwner: true,
      onReading: (r) => {
        combinedReading = r;
      },
      setError: deps.setError,
      setSuccess: deps.setSuccess,
    });
  }
  function stageCombinedCell(rowId: string, col: SIVICombinedColumn, raw: string, nullValue: boolean) {
    runStageSivi({
      allowed: Boolean(combinedSession && !combinedEditingDisabled),
      guardMessage: 'Unlock the clean available parent before editing combined SIVI rows.',
      errorPrefix: 'SIVI combined ',
      failPrefix: 'SIVI combined draft failed; original/raw state retained',
      action: () => combinedSession!.stage(rowId, col, raw, nullValue),
      readError: () => combinedSession!.view().error,
      currentError: deps.getCurrentError(),
      setError: deps.setError,
      setSuccess: deps.setSuccess,
    });
  }
  async function showCombinedPanel() {
    if (combinedPanelOpen) {
      combinedPanelOpen = false;
      return;
    }
    if (combinedEditingDisabled && !combinedUnsaved) {
      deps.setError('Combined SIVI rows require a clean, unlocked available parent.');
      return;
    }
    closeOtherVegPanels('combined');
    if (!combinedView?.review && !combinedUnsaved) await combinedOperation('load');
  }

  function collectedOperation(op: ReviewedSiviOperation) {
    return runReviewedSiviOp({
      kind: 'collected',
      operation: op,
      allowed: !(
        deps.getBusy() ||
        deps.getHeaderWorkflowBusy() ||
        heightUnsaved ||
        coverUnsaved ||
        combinedUnsaved ||
        speciesUnsaved ||
        identityUnsaved ||
        deps.getOrdinaryChildPeerUnsaved() ||
        anyParentUnsaved ||
        (op !== 'undo' && collectedEditingDisabled)
      ),
      getOwner: () => collectedSession,
      retainAction: AuditRestoreAction.AuditRestoreRetain,
      pruneAction: AuditRestoreAction.AuditRestorePrune,
      trackOwner: true,
      onReading: (r) => {
        collectedReading = r;
      },
      setError: deps.setError,
      setSuccess: deps.setSuccess,
    });
  }
  function cycleCollected(rowId: string) {
    runStageSivi({
      allowed: Boolean(collectedSession && !collectedEditingDisabled),
      guardMessage: 'Unlock the clean available parent before cycling SIVI Collected.',
      errorPrefix: 'SIVI Collected ',
      failPrefix: 'SIVI Collected cycle failed; original state retained',
      action: () => collectedSession!.cycle(rowId),
      readError: () => collectedSession!.view().error,
      currentError: deps.getCurrentError(),
      setError: deps.setError,
      setSuccess: deps.setSuccess,
    });
  }
  async function showCollectedPanel() {
    if (collectedPanelOpen) {
      collectedPanelOpen = false;
      return;
    }
    if (collectedEditingDisabled && !collectedUnsaved) {
      deps.setError('SIVI Collected requires a clean, unlocked available parent.');
      return;
    }
    closeOtherVegPanels('collected');
    if (!collectedView?.review && !collectedUnsaved) await collectedOperation('load');
  }

  function speciesOperation(op: ReviewedSiviOperation) {
    return runReviewedSiviOp({
      kind: 'species',
      operation: op,
      allowed: !(
        deps.getBusy() ||
        deps.getHeaderWorkflowBusy() ||
        heightUnsaved ||
        coverUnsaved ||
        combinedUnsaved ||
        collectedUnsaved ||
        identityUnsaved ||
        deps.getOrdinaryChildPeerUnsaved() ||
        anyParentUnsaved ||
        (op !== 'undo' && speciesEditingDisabled)
      ),
      getOwner: () => speciesSession,
      retainAction: AuditRestoreAction.AuditRestoreRetain,
      pruneAction: AuditRestoreAction.AuditRestorePrune,
      trackOwner: true,
      onReading: (r) => {
        speciesReading = r;
      },
      setError: deps.setError,
      setSuccess: deps.setSuccess,
    });
  }
  function stageSpecies(rowId: string, command: 'Species' | 'context' | SpeciesDecisionKind, raw: string) {
    runStageSivi({
      allowed: Boolean(speciesSession && !speciesEditingDisabled),
      guardMessage: 'Unlock the clean available parent before editing SIVI Species.',
      errorPrefix: 'SIVI Species ',
      failPrefix: 'SIVI Species draft failed; original/raw state retained',
      action: () => speciesSession!.stage(rowId, command, raw, false),
      readError: () => speciesSession!.view().error,
      currentError: deps.getCurrentError(),
      setError: deps.setError,
      setSuccess: deps.setSuccess,
    });
  }
  async function showSpeciesPanel() {
    if (speciesPanelOpen) {
      speciesPanelOpen = false;
      return;
    }
    if (speciesEditingDisabled && !speciesUnsaved) {
      deps.setError('SIVI Species requires a clean, unlocked available parent.');
      return;
    }
    closeOtherVegPanels('species');
    if (!speciesView?.review && !speciesUnsaved) await speciesOperation('load');
  }

  function identityOperation(op: ReviewedSiviOperation) {
    return runReviewedSiviOp({
      kind: 'identity',
      operation: op,
      allowed: !(
        deps.getBusy() ||
        deps.getHeaderWorkflowBusy() ||
        heightUnsaved ||
        coverUnsaved ||
        combinedUnsaved ||
        collectedUnsaved ||
        speciesUnsaved ||
        deps.getOrdinaryChildPeerUnsaved() ||
        anyParentUnsaved ||
        (op !== 'undo' && identityEditingDisabled)
      ),
      getOwner: () => identitySession,
      retainAction: AuditRestoreAction.AuditRestoreRetain,
      pruneAction: AuditRestoreAction.AuditRestorePrune,
      trackOwner: true,
      onReading: (r) => {
        identityReading = r;
      },
      setError: deps.setError,
      setSuccess: deps.setSuccess,
    });
  }
  function stageIdentity(rowId: string, raw: string, nullValue: boolean) {
    runStageSivi({
      allowed: Boolean(identitySession && !identityEditingDisabled),
      guardMessage: 'Unlock the clean available parent before editing SIVI IDs.',
      errorPrefix: 'SIVI ID ',
      failPrefix: 'SIVI ID draft failed; original/raw state retained',
      action: () => identitySession!.stage(rowId, 'ID', raw, nullValue),
      readError: () => identitySession!.view().error,
      currentError: deps.getCurrentError(),
      setError: deps.setError,
      setSuccess: deps.setSuccess,
    });
  }
  async function showIdentityPanel() {
    if (identityPanelOpen) {
      identityPanelOpen = false;
      return;
    }
    if (identityEditingDisabled && !identityUnsaved) {
      deps.setError('SIVI IDs require a clean, unlocked available parent.');
      return;
    }
    closeOtherVegPanels('identity');
    if (!identityView?.review && !identityUnsaved) await identityOperation('load');
  }

  function creationOperation(
    operation: 'load' | 'start' | 'save' | 'undo' | 'resolve' | 'cancel',
    form?: SIVICreationForm
  ) {
    return executeSiviCreationOpImpl({
      session: creationSession,
      enabled: true,
      recoveryDisabled: creationRecoveryDisabled,
      editingDisabled: creationEditingDisabled,
      operation,
      form,
      getCurrentSession: () => creationSession,
      setHostBusy: (b) => {
        creationHostBusy = b;
      },
      invalidateCapabilities: deps.invalidateCapabilities,
      setError: deps.setError,
      setSuccess: deps.setSuccess,
      randomUUID: () => crypto.randomUUID(),
      refreshPeers: async (plot) => {
        await refreshChildEditors(plot, 'creation');
        await refreshLifecycleLists('creation');
      },
    });
  }
  function stageCreation(d: SIVICreationDraft) {
    try {
      if (!creationSession || creationEditingDisabled)
        throw new Error('Unlock the clean owned parent before correcting SIVI creation.');
      creationSession.updateDraft(d);
      deps.setError(creationSession.view().error);
      deps.setSuccess(null);
    } catch (cause) {
      deps.setError(`SIVI creation correction failed; retained draft unchanged: ${formatError(cause)}`);
    }
  }
  function lifecycleOperation(
    kind: 'deletion' | 'restoration',
    operation: 'load' | 'history' | 'review' | 'save' | 'undo' | 'resolve' | 'cancel',
    identity?: string,
    form?: SIVICreationForm
  ) {
    return executeSiviLifecycleOpImpl({
      kind,
      operation,
      identity,
      form,
      deletionSession,
      restorationSession,
      enabled: true,
      recoveryDisabled: kind === 'deletion' ? deletionRecoveryDisabled : restorationRecoveryDisabled,
      editingDisabled: kind === 'deletion' ? deletionEditingDisabled : restorationEditingDisabled,
      getCurrentSession: () => (kind === 'deletion' ? deletionSession : restorationSession),
      setHostBusy: (b) => {
        lifecycleHostBusy = b;
      },
      invalidateCapabilities: deps.invalidateCapabilities,
      setError: deps.setError,
      setSuccess: deps.setSuccess,
      randomUUID: () => crypto.randomUUID(),
      refreshPeers: async (plot, k) => {
        await refreshChildEditors(plot, k);
        await refreshLifecycleLists(k);
      },
    });
  }
  function stageLifecycle(kind: 'deletion' | 'restoration', confirmed: boolean, action?: 'retain' | 'prune') {
    try {
      if (kind === 'deletion') {
        if (!deletionSession || deletionEditingDisabled)
          throw new Error('Unlock the clean owned parent before confirming deletion.');
        deletionSession.confirm(confirmed);
        deps.setError(deletionSession.view().error);
      } else {
        if (!restorationSession || restorationEditingDisabled)
          throw new Error('Unlock the clean owned parent before confirming restoration.');
        if (action) restorationSession.choose(action);
        else restorationSession.confirm(confirmed);
        deps.setError(restorationSession.view().error);
      }
      deps.setSuccess(null);
    } catch (cause) {
      deps.setError(`SIVI ${kind} confirmation failed; retained review unchanged: ${formatError(cause)}`);
    }
  }
  function creationUndoOperation(
    operation: 'history' | 'review' | 'undo' | 'discard' | 'resolve' | 'cancel',
    historyId?: string
  ) {
    return executeSiviCreationUndoOpImpl({
      session: creationUndoSession,
      enabled: true,
      recoveryDisabled: creationUndoRecoveryDisabled,
      editingDisabled: creationUndoEditingDisabled,
      operation,
      historyId,
      getCurrentSession: () => creationUndoSession,
      setHostBusy: (b) => {
        lifecycleHostBusy = b;
      },
      invalidateCapabilities: deps.invalidateCapabilities,
      setError: deps.setError,
      setSuccess: deps.setSuccess,
      randomUUID: () => crypto.randomUUID(),
      refreshPeers: async (plot) => {
        await refreshChildEditors(plot, 'creationUndo');
        await refreshLifecycleLists('creationUndo');
      },
    });
  }
  function stageCreationUndo(confirmed: boolean, action?: 'retain' | 'prune') {
    try {
      if (!creationUndoSession || creationUndoEditingDisabled)
        throw new Error('Unlock the clean owned parent before confirming creation Undo.');
      if (action) creationUndoSession.choose(action);
      else creationUndoSession.confirm(confirmed);
      deps.setError(creationUndoSession.view().error);
      deps.setSuccess(null);
    } catch (cause) {
      deps.setError(`SIVI creation Undo confirmation failed; retained review unchanged: ${formatError(cause)}`);
    }
  }

  function blockedLoadReason(): string | null {
    return firstMatch<string>([
      [
        () => deletionPending || restorationPending || creationUndoPending,
        'Finish the source deletion/restoration/creation Undo review or resolve its exact retained request before replacing the plot owner.',
      ],
      [
        () => creationPending,
        'Finish SIVI creation or resolve its exact retained request before replacing the plot owner.',
      ],
      [
        () => pictureMetadataPending,
        'Finish or explicitly discard picture metadata drafts/recovery before replacing their plot owner.',
      ],
      [
        () =>
          Boolean(
            parentSharedSession && (parentSharedSession.closeState().unsaved || parentSharedSession.closeState().busy)
          ),
        'Finish or explicitly Undo shared SIVI drafts/recovery before replacing their plot owner.',
      ],
      [
        () =>
          Boolean(
            projectAssignmentSession &&
            (projectAssignmentSession.closeState().unsaved || projectAssignmentSession.closeState().busy)
          ),
        'Finish or explicitly Undo ProjectID selection/recovery before replacing its plot owner.',
      ],
      [
        () =>
          Boolean(
            parentActionSession && (parentActionSession.closeState().unsaved || parentActionSession.closeState().busy)
          ),
        'Finish or explicitly Undo SIVI source-action drafts/recovery before replacing their plot owner.',
      ],
      [
        () =>
          Boolean(
            parentWriteSession && (parentWriteSession.closeState().unsaved || parentWriteSession.closeState().busy)
          ),
        'Finish or explicitly Undo SIVI parent drafts/recovery before replacing their plot owner.',
      ],
      [
        () => Boolean(parentSourceView?.busy),
        'Wait for the current SIVI source operation before replacing its plot owner.',
      ],
      [
        () => Boolean(heightSession && (heightSession.closeState().unsaved || heightSession.closeState().busy)),
        'SIVI drafts or operations must finish or be explicitly undone before replacing their plot owner.',
      ],
      [
        () => Boolean(coverSession && (coverSession.closeState().unsaved || coverSession.closeState().busy)),
        'SIVI cover drafts or operations must finish or be explicitly undone before replacing their plot owner.',
      ],
      [
        () => Boolean(combinedSession && (combinedSession.closeState().unsaved || combinedSession.closeState().busy)),
        'Combined SIVI drafts or operations must finish or be explicitly undone before replacing their plot owner.',
      ],
      [
        () =>
          Boolean(collectedSession && (collectedSession.closeState().unsaved || collectedSession.closeState().busy)),
        'SIVI Collected drafts or operations must finish or be explicitly undone before replacing their plot owner.',
      ],
      [
        () => Boolean(speciesSession && (speciesSession.closeState().unsaved || speciesSession.closeState().busy)),
        'SIVI Species drafts or operations must finish or be explicitly undone before replacing their plot owner.',
      ],
      [
        () => Boolean(identitySession && (identitySession.closeState().unsaved || identitySession.closeState().busy)),
        'SIVI ID drafts or operations must finish or be explicitly undone before replacing their plot owner.',
      ],
    ]);
  }

  function resetForPlot() {
    for (const s of [
      parentSession,
      parentSourceSession,
      parentWriteSession,
      parentActionSession,
      projectAssignmentSession,
      parentSharedSession,
      heightSession,
      coverSession,
      combinedSession,
      collectedSession,
      speciesSession,
      identitySession,
    ]) {
      s?.dispose();
    }
    parentSession = null;
    parentSourceSession = null;
    parentWriteSession = null;
    parentActionSession = null;
    projectAssignmentSession = null;
    parentSharedSession = null;
    parentSharedVer += 1;
    projectAssignmentVer += 1;
    parentActionVer += 1;
    parentWriteVer += 1;
    parentSourceVer += 1;
    parentVer += 1;
    parentOpen = false;
    heightSession = null;
    coverSession = null;
    combinedSession = null;
    collectedSession = null;
    speciesSession = null;
    identitySession = null;
    for (const r of [heightReads, coverReads, combinedReads, collectedReads, speciesReads, identityReads])
      r.cancelAll();
    heightVer += 1;
    coverVer += 1;
    combinedVer += 1;
    collectedVer += 1;
    speciesVer += 1;
    identityVer += 1;
    heightPanelOpen = false;
    coverPanelOpen = false;
    combinedPanelOpen = false;
    collectedPanelOpen = false;
    speciesPanelOpen = false;
    identityPanelOpen = false;
  }

  function initForLoadedPlot(plot: string, extendedShrubs: boolean) {
    const cid = deps.contextId;
    if (deps.getActiveContextId() === cid) {
      const project = deps.getActiveProject() ?? '';
      parentSession = new SIVIParentReadSession(
        { contextId: cid, project, plot },
        () => parentReads.track(ContextService.GetSIVIParentOriginal(cid, plot)),
        () => parentReads.cancelAll(),
        () => {
          parentVer += 1;
        }
      );
      parentSourceSession = new SIVIParentSourceSession(
        { contextId: cid, project, plot },
        {
          join: () => parentSourceReads.track(ContextService.GetSIVIParentJoinReview(cid, plot)),
          choices: () => parentSourceReads.track(ContextService.GetSIVIProjectIDChoices(cid)),
          setSource: (expected, source) => ContextService.SetSIVIProjectIDSource(cid, expected, source),
          cancel: () => parentSourceReads.cancelAll(),
        },
        () => {
          parentSourceVer += 1;
        }
      );
      parentWriteSession = new SIVIParentWriteSession(
        { contextId: cid, project, plot },
        {
          read: () => parentWriteReads.track(ContextService.GetSIVIParentDirectOriginal(cid, plot)),
          cancelRead: () => parentWriteReads.cancelAll(),
          save: (req) => ContextService.SaveSIVIParentDirect(cid, plot, req),
          restore: (hId, act) => ContextService.RestoreSIVIParentDirect(cid, plot, hId, act),
          refreshParent: () =>
            refreshParent(plot, [parentActionSession, projectAssignmentSession, parentSharedSession]),
        },
        () => {
          parentWriteVer += 1;
        }
      );
      parentActionSession = new SIVIParentActionWriteSession(
        { contextId: cid, project, plot },
        {
          read: () => parentActionReads.track(ContextService.GetSIVIParentActionOriginal(cid, plot)),
          cancelRead: () => parentActionReads.cancelAll(),
          save: (req) => ContextService.SaveSIVIParentActions(cid, plot, req),
          restore: (hId, act) => ContextService.RestoreSIVIParentActions(cid, plot, hId, act),
          refreshParent: () => refreshParent(plot, [parentWriteSession, projectAssignmentSession, parentSharedSession]),
        },
        () => {
          parentActionVer += 1;
        }
      );
      projectAssignmentSession = new SIVIProjectAssignmentSession(
        { contextId: cid, project, plot },
        {
          read: () => projectAssignmentReads.track(ContextService.GetSIVIProjectAssignmentOriginal(cid, plot)),
          cancelRead: () => projectAssignmentReads.cancelAll(),
          save: (req) => ContextService.SaveSIVIProjectAssignment(cid, plot, req),
          restore: (hId, act) => ContextService.RestoreSIVIProjectAssignment(cid, plot, hId, act),
          refreshParent: () => refreshParent(plot, [parentWriteSession, parentActionSession, parentSharedSession]),
        },
        () => {
          projectAssignmentVer += 1;
        }
      );
      parentSharedSession = new SIVIParentSharedSession(
        { contextId: cid, project, plot },
        {
          read: () => parentSharedReads.track(PlotEntryService.GetSIVIParentSharedOriginal(cid, plot)),
          readReferences: (zone) =>
            parentSharedReads.track(PlotEntryService.GetSIVIParentSharedReferences(cid, plot, zone)),
          cancelRead: () => parentSharedReads.cancelAll(),
          save: (req) => PlotEntryService.SaveSIVIParentShared(cid, plot, req),
          restore: (hId, act) => PlotEntryService.RestoreSIVIParentShared(cid, plot, hId, act),
          refreshParent: () => refreshParent(plot, [parentWriteSession, parentActionSession, projectAssignmentSession]),
        },
        () => {
          parentSharedVer += 1;
        },
        true
      );
      parentWriteVer += 1;
      parentActionVer += 1;
      projectAssignmentVer += 1;
      parentSharedVer += 1;
      parentSourceVer += 1;
      parentVer += 1;
    }
    heightSession = new SIVIHeightSession(
      plot,
      {
        read: (ext) => heightReads.track(ContextService.GetSIVIVegetation(cid, plot, ext)),
        save: (ext, rev, ed) => ContextService.SaveSIVIHeights(cid, plot, ext, rev, ed),
        restore: (hId, act) => ContextService.RestoreSIVIHeights(cid, plot, hId, act),
        refreshParent: () => refreshChildEditors(plot, 'height'),
      },
      () => {
        heightVer += 1;
      },
      extendedShrubs,
      true
    );
    coverSession = new SIVICoverSession(
      plot,
      {
        read: (ext) => coverReads.track(PlotEntryService.GetSIVICoverOriginal(cid, plot, ext)),
        save: (ext, req) => PlotEntryService.SaveSIVICoverReviewed(cid, plot, ext, req),
        restore: (hId, act) => PlotEntryService.RestoreSIVICoverReviewed(cid, plot, hId, act),
        refreshParent: () => refreshChildEditors(plot, 'cover'),
      },
      () => {
        coverVer += 1;
      },
      extendedShrubs,
      true
    );
    combinedSession = new SIVICombinedSession(
      plot,
      {
        read: (ext) => combinedReads.track(PlotEntryService.GetSIVICombinedOriginal(cid, plot, ext)),
        save: (ext, req) => PlotEntryService.SaveSIVICombinedReviewed(cid, plot, ext, req),
        restore: (hId, act) => PlotEntryService.RestoreSIVICombinedReviewed(cid, plot, hId, act),
        refreshParent: () => refreshChildEditors(plot, 'combined'),
      },
      () => {
        combinedVer += 1;
      },
      extendedShrubs,
      true
    );
    collectedSession = new SIVICollectedSession(
      plot,
      {
        read: (ext) => collectedReads.track(PlotEntryService.GetSIVICollectedOriginal(cid, plot, ext)),
        save: (ext, req) => PlotEntryService.SaveSIVICollectedReviewed(cid, plot, ext, req),
        restore: (hId, act) => PlotEntryService.RestoreSIVICollectedReviewed(cid, plot, hId, act),
        refreshParent: () => refreshChildEditors(plot, 'collected'),
      },
      () => {
        collectedVer += 1;
      },
      extendedShrubs,
      true
    );
    const project = deps.getActiveProject();
    if (!project) throw new Error('SIVI Species requires the active owned project before creating its editor.');
    speciesSession = new SIVISpeciesSession(
      { contextId: cid, project, plot },
      {
        read: async (ext) => {
          const [orig, refs] = await Promise.all([
            speciesReads.track(PlotEntryService.GetSIVISpeciesOriginal(cid, plot, ext)),
            speciesReads.track(PlotEntryService.GetSIVISpeciesReferences(cid, plot)),
          ]);
          return { original: orig, references: refs };
        },
        save: (ext, req) => PlotEntryService.SaveSIVISpeciesReviewed(cid, plot, ext, req),
        restore: (hId, act) => PlotEntryService.RestoreSIVISpeciesReviewed(cid, plot, hId, act),
        refreshParent: () => refreshChildEditors(plot, 'species'),
      },
      () => {
        speciesVer += 1;
      },
      extendedShrubs,
      true
    );
    identitySession = new SIVIIdentitySession(
      plot,
      {
        read: (ext) => identityReads.track(PlotEntryService.GetSIVIIdentityOriginal(cid, plot, ext)),
        save: (ext, req) => PlotEntryService.SaveSIVIIdentityReviewed(cid, plot, ext, req),
        restore: (hId, act) => PlotEntryService.RestoreSIVIIdentityReviewed(cid, plot, hId, act),
        refreshParent: () => refreshChildEditors(plot, 'identity'),
      },
      () => {
        identityVer += 1;
      },
      extendedShrubs,
      true
    );
    heightVer += 1;
    coverVer += 1;
    combinedVer += 1;
    collectedVer += 1;
    speciesVer += 1;
    identityVer += 1;
  }

  function disposeAll() {
    disposePlotSiviSessions(
      {
        siviParentSession: parentSession,
        siviParentSourceSession: parentSourceSession,
        siviParentWriteSession: parentWriteSession,
        siviParentActionSession: parentActionSession,
        siviProjectAssignmentSession: projectAssignmentSession,
        siviParentSharedSession: parentSharedSession,
        siviSession: heightSession,
        siviCoverSession: coverSession,
        siviCombinedSession: combinedSession,
        siviCollectedSession: collectedSession,
        siviSpeciesSession: speciesSession,
        siviIdentitySession: identitySession,
      },
      {
        siviParentReads: parentReads,
        siviParentSourceReads: parentSourceReads,
        siviParentWriteReads: parentWriteReads,
        siviParentActionReads: parentActionReads,
        siviProjectAssignmentReads: projectAssignmentReads,
        siviParentSharedReads: parentSharedReads,
        siviReads: heightReads,
        siviCoverReads: coverReads,
        siviCombinedReads: combinedReads,
        siviCollectedReads: collectedReads,
        siviSpeciesReads: speciesReads,
        siviIdentityReads: identityReads,
      }
    );
  }

  function saveDraftHandler(): (() => Promise<void | boolean>) | null {
    return firstMatch<() => Promise<void | boolean>>([
      [() => creationPending, () => creationOperation('save')],
      [() => parentActionUnsaved, () => parentActionOperation('save')],
      [() => projectAssignmentUnsaved, () => projectAssignmentOperation('save')],
      [() => parentWriteUnsaved, () => parentWriteOperation('save')],
      [() => parentSharedUnsaved, () => parentSharedOperation('save')],
      [() => heightUnsaved, () => heightOperation('save')],
      [() => coverUnsaved, () => coverOperation('save')],
      [() => combinedUnsaved, () => combinedOperation('save')],
      [() => collectedUnsaved, () => collectedOperation('save')],
      [() => speciesUnsaved, () => speciesOperation('save')],
      [() => identityUnsaved, () => identityOperation('save')],
    ]);
  }

  function undoDraftHandler(): (() => void) | null {
    return firstMatch<() => void>([
      [() => deletionPending, () => void lifecycleOperation('deletion', 'undo')],
      [() => restorationPending, () => void lifecycleOperation('restoration', 'undo')],
      [() => creationUndoPending, () => void creationUndoOperation('discard')],
      [() => creationPending, () => void creationOperation('undo')],
      [() => parentActionUnsaved, () => void parentActionOperation('undo')],
      [() => projectAssignmentUnsaved, () => void projectAssignmentOperation('undo')],
      [() => parentWriteUnsaved, () => void parentWriteOperation('undo')],
      [() => parentSharedUnsaved, () => void parentSharedOperation('undo')],
      [() => heightUnsaved, () => void heightOperation('undo')],
      [() => coverUnsaved, () => void coverOperation('undo')],
      [() => combinedUnsaved, () => void combinedOperation('undo')],
      [() => collectedUnsaved, () => void collectedOperation('undo')],
      [() => speciesUnsaved, () => void speciesOperation('undo')],
      [() => identityUnsaved, () => void identityOperation('undo')],
    ]);
  }

  function lockBlockedReason(): string | null {
    return firstMatch<string>([
      [
        () => deletionPending || restorationPending || creationUndoPending,
        'Finish or resolve source deletion/restoration/creation Undo before changing the plot lock.',
      ],
      [
        () => sourceAuthorityUnknown,
        'Read owned ProjectID choices to observe the source preference outcome before changing the plot lock.',
      ],
      [() => parentWriteUnsaved, 'Save or explicitly Undo SIVI parent drafts/recovery before changing the plot lock.'],
      [() => parentSharedUnsaved, 'Save or explicitly Undo shared SIVI drafts/recovery before changing the plot lock.'],
      [
        () => parentActionUnsaved,
        'Save or explicitly Undo SIVI source-action drafts/recovery before changing the plot lock.',
      ],
      [
        () => projectAssignmentUnsaved,
        'Save or explicitly Undo ProjectID selection/recovery before changing the plot lock.',
      ],
      [
        () => heightUnsaved,
        'SIVI heights or unresolved acknowledgements must be saved or explicitly undone before changing the plot lock.',
      ],
      [
        () => coverUnsaved,
        'SIVI covers or unresolved acknowledgements must be saved or explicitly undone before changing the plot lock.',
      ],
      [
        () => combinedUnsaved,
        'Combined SIVI drafts or unresolved acknowledgements must be saved or explicitly undone before changing the plot lock.',
      ],
      [
        () => collectedUnsaved,
        'SIVI Collected or unresolved acknowledgements must be saved or explicitly undone before changing the plot lock.',
      ],
      [
        () => speciesUnsaved,
        'SIVI Species or unresolved acknowledgements must be saved or explicitly undone before changing the plot lock.',
      ],
      [
        () => identityUnsaved,
        'SIVI IDs or unresolved acknowledgements must be saved or explicitly undone before changing the plot lock.',
      ],
      [
        () => creationPending,
        'SIVI creation drafts or unknown acknowledgements must be resolved before changing the plot lock.',
      ],
    ]);
  }

  function lifecycleCloseOverride(busy: boolean, headerWorkflowBusy: boolean): EditorCloseState | null {
    if (pictureMetadataPending && pictureMetadataClose) {
      return {
        ...pictureMetadataClose,
        canSave: false,
        saveReason:
          pictureMetadataClose.blocked || pictureMetadataClose.busy
            ? pictureMetadataClose.saveReason
            : 'Save picture metadata explicitly or discard its draft before parent Save, Lock or close.',
      };
    }
    if (parentSourceView?.authorityUnknown) {
      return {
        unsaved: true,
        busy: parentSourceView.busy,
        blocked: true,
        canSave: false,
        saveReason: 'Reload owned ProjectID choices to observe the source preference outcome before saving or closing.',
        error: parentSourceView.error ?? 'ProjectID source preference outcome is unknown.',
      };
    }
    const lc =
      creationUndoPending && creationUndoClose?.blocked
        ? creationUndoClose
        : deletionPending
          ? deletionClose
          : restorationPending
            ? restorationClose
            : creationUndoPending
              ? creationUndoClose
              : null;
    if (!lc) return null;
    return {
      ...lc,
      canSave: false,
      busy: busy || headerWorkflowBusy || lc.busy,
      saveReason:
        lc.blocked || lc.busy
          ? lc.saveReason
          : 'Finish source deletion/restoration/creation Undo explicitly or discard its unsubmitted review before parent Save, Lock or close.',
    };
  }

  function creationCloseOverride(
    busy: boolean,
    headerWorkflowBusy: boolean,
    error: string | null
  ): EditorCloseState | null {
    if (!creationPending || !creationClose) return null;
    return {
      ...creationClose,
      busy: busy || headerWorkflowBusy || creationClose.busy,
      canSave: !creationEditingDisabled && creationClose.canSave,
      saveReason: creationEditingDisabled
        ? 'Finish conflicting work before creating the retained SIVI row.'
        : creationClose.saveReason,
      error: creationClose.error ?? error,
    };
  }

  function anySessionBlocked(): boolean {
    return [
      heightClose,
      coverClose,
      combinedClose,
      collectedClose,
      speciesClose,
      identityClose,
      parentWriteClose,
      parentActionClose,
      projectAssignmentClose,
      parentSharedClose,
    ].some((c) => c?.blocked ?? false);
  }

  function saveReasonFields() {
    return {
      siviParentActionUnsaved: parentActionUnsaved,
      siviParentActionClose: parentActionClose,
      siviParentWriteUnsaved: parentWriteUnsaved,
      siviParentWriteClose: parentWriteClose,
      siviParentSharedUnsaved: parentSharedUnsaved,
      siviParentSharedClose: parentSharedClose,
      siviProjectAssignmentUnsaved: projectAssignmentUnsaved,
      siviProjectAssignmentClose: projectAssignmentClose,
      siviUnsaved: heightUnsaved,
      siviClose: heightClose,
      siviCoverUnsaved: coverUnsaved,
      siviCoverClose: coverClose,
      siviCombinedUnsaved: combinedUnsaved,
      siviCombinedClose: combinedClose,
      siviCollectedUnsaved: collectedUnsaved,
      siviCollectedClose: collectedClose,
      siviSpeciesUnsaved: speciesUnsaved,
      siviSpeciesClose: speciesClose,
      siviIdentityUnsaved: identityUnsaved,
      siviIdentityClose: identityClose,
    };
  }

  async function refreshProjectMetadata(plotNumber: string) {
    if (!parentSession?.view().original && !parentSession?.view().error) {
      await deps.loadChildData(plotNumber);
      return;
    }
    await refreshAllParentPeers(plotNumber);
    if (
      parentSourceSession &&
      (parentSourceSession.view().choices || parentSourceSession.view().error) &&
      !(await parentSourceSession.load())
    ) {
      throw new Error(
        parentSourceSession.view().error ?? 'ProjectID choices did not refresh after the metadata commit.'
      );
    }
  }

  return {
    sharedColumns,
    get parentSession() {
      return parentSession;
    },
    get parentOpen() {
      return parentOpen;
    },
    set parentOpen(v: boolean) {
      parentOpen = v;
    },
    get parentView() {
      return parentView;
    },
    get parentSourceSession() {
      return parentSourceSession;
    },
    get parentSourceView() {
      return parentSourceView;
    },
    get parentBusy() {
      return parentBusy;
    },
    get sourceAuthorityUnknown() {
      return sourceAuthorityUnknown;
    },
    get sourceBarrier() {
      return sourceBarrier;
    },
    get parentSharedSession() {
      return parentSharedSession;
    },
    get parentSharedView() {
      return parentSharedView;
    },
    get parentSharedClose() {
      return parentSharedClose;
    },
    get parentSharedUnsaved() {
      return parentSharedUnsaved;
    },
    get parentSharedEditingDisabled() {
      return parentSharedEditingDisabled;
    },
    get parentWriteSession() {
      return parentWriteSession;
    },
    get parentWriteView() {
      return parentWriteView;
    },
    get parentWriteClose() {
      return parentWriteClose;
    },
    get parentWriteUnsaved() {
      return parentWriteUnsaved;
    },
    get parentWriteEditingDisabled() {
      return parentWriteEditingDisabled;
    },
    get parentActionSession() {
      return parentActionSession;
    },
    get parentActionView() {
      return parentActionView;
    },
    get parentActionClose() {
      return parentActionClose;
    },
    get parentActionUnsaved() {
      return parentActionUnsaved;
    },
    get parentActionEditingDisabled() {
      return parentActionEditingDisabled;
    },
    get projectAssignmentSession() {
      return projectAssignmentSession;
    },
    get projectAssignmentView() {
      return projectAssignmentView;
    },
    get projectAssignmentClose() {
      return projectAssignmentClose;
    },
    get projectAssignmentUnsaved() {
      return projectAssignmentUnsaved;
    },
    get projectAssignmentEditingDisabled() {
      return projectAssignmentEditingDisabled;
    },
    get heightPanelOpen() {
      return heightPanelOpen;
    },
    get heightView() {
      return heightView;
    },
    get heightClose() {
      return heightClose;
    },
    get heightUnsaved() {
      return heightUnsaved;
    },
    get heightEditingDisabled() {
      return heightEditingDisabled;
    },
    get coverPanelOpen() {
      return coverPanelOpen;
    },
    get coverView() {
      return coverView;
    },
    get coverClose() {
      return coverClose;
    },
    get coverUnsaved() {
      return coverUnsaved;
    },
    get coverBusy() {
      return coverBusy;
    },
    get coverReading() {
      return coverReading;
    },
    get coverEditingDisabled() {
      return coverEditingDisabled;
    },
    get combinedPanelOpen() {
      return combinedPanelOpen;
    },
    get combinedView() {
      return combinedView;
    },
    get combinedClose() {
      return combinedClose;
    },
    get combinedUnsaved() {
      return combinedUnsaved;
    },
    get combinedBusy() {
      return combinedBusy;
    },
    get combinedReading() {
      return combinedReading;
    },
    get combinedEditingDisabled() {
      return combinedEditingDisabled;
    },
    get collectedPanelOpen() {
      return collectedPanelOpen;
    },
    get collectedView() {
      return collectedView;
    },
    get collectedClose() {
      return collectedClose;
    },
    get collectedUnsaved() {
      return collectedUnsaved;
    },
    get collectedBusy() {
      return collectedBusy;
    },
    get collectedReading() {
      return collectedReading;
    },
    get collectedEditingDisabled() {
      return collectedEditingDisabled;
    },
    get speciesPanelOpen() {
      return speciesPanelOpen;
    },
    get speciesView() {
      return speciesView;
    },
    get speciesClose() {
      return speciesClose;
    },
    get speciesUnsaved() {
      return speciesUnsaved;
    },
    get speciesBusy() {
      return speciesBusy;
    },
    get speciesReading() {
      return speciesReading;
    },
    get speciesEditingDisabled() {
      return speciesEditingDisabled;
    },
    get identityPanelOpen() {
      return identityPanelOpen;
    },
    get identityView() {
      return identityView;
    },
    get identityClose() {
      return identityClose;
    },
    get identityUnsaved() {
      return identityUnsaved;
    },
    get identityBusy() {
      return identityBusy;
    },
    get identityReading() {
      return identityReading;
    },
    get identityEditingDisabled() {
      return identityEditingDisabled;
    },
    get pictureMetadataSession() {
      return pictureMetadataSession;
    },
    get pictureMetadataClose() {
      return pictureMetadataClose;
    },
    get pictureMetadataPending() {
      return pictureMetadataPending;
    },
    get creationSession() {
      return creationSession;
    },
    get creationView() {
      return creationView;
    },
    get creationClose() {
      return creationClose;
    },
    get creationPending() {
      return creationPending;
    },
    get creationEditingDisabled() {
      return creationEditingDisabled;
    },
    get creationRecoveryDisabled() {
      return creationRecoveryDisabled;
    },
    get deletionView() {
      return deletionView;
    },
    get deletionClose() {
      return deletionClose;
    },
    get deletionPending() {
      return deletionPending;
    },
    get deletionEditingDisabled() {
      return deletionEditingDisabled;
    },
    get deletionRecoveryDisabled() {
      return deletionRecoveryDisabled;
    },
    get restorationView() {
      return restorationView;
    },
    get restorationClose() {
      return restorationClose;
    },
    get restorationPending() {
      return restorationPending;
    },
    get restorationTargets() {
      return restorationTargets;
    },
    get restorationEditingDisabled() {
      return restorationEditingDisabled;
    },
    get restorationRecoveryDisabled() {
      return restorationRecoveryDisabled;
    },
    get creationUndoView() {
      return creationUndoView;
    },
    get creationUndoClose() {
      return creationUndoClose;
    },
    get creationUndoPending() {
      return creationUndoPending;
    },
    get creationUndoEditingDisabled() {
      return creationUndoEditingDisabled;
    },
    get creationUndoRecoveryDisabled() {
      return creationUndoRecoveryDisabled;
    },
    get anyChildUnsaved() {
      return anyChildUnsaved;
    },
    get anyParentUnsaved() {
      return anyParentUnsaved;
    },
    get anyLifecyclePending() {
      return anyLifecyclePending;
    },
    get anyBusy() {
      return anyBusy;
    },
    setPresentation,
    refreshAllParentPeers,
    refreshProjectMetadata,
    parentWriteOperation,
    parentActionOperation,
    stageParentAction,
    projectAssignmentOperation,
    stageProjectAssignment,
    stageParentShared,
    parentSharedOperation,
    stageParentCell,
    changeProjectSource,
    reloadProjectSource,
    loadParentOriginals,
    showParentPanel,
    heightOperation,
    stageHeightCell,
    showHeightPanel,
    coverOperation,
    stageCoverCell,
    showCoverPanel,
    cancelCoverRead: () => coverReads.cancelAll(),
    combinedOperation,
    stageCombinedCell,
    showCombinedPanel,
    cancelCombinedRead: () => combinedReads.cancelAll(),
    collectedOperation,
    cycleCollected,
    showCollectedPanel,
    cancelCollectedRead: () => collectedReads.cancelAll(),
    speciesOperation,
    stageSpecies,
    showSpeciesPanel,
    cancelSpeciesRead: () => speciesReads.cancelAll(),
    identityOperation,
    stageIdentity,
    showIdentityPanel,
    cancelIdentityRead: () => identityReads.cancelAll(),
    creationOperation,
    stageCreation,
    lifecycleOperation,
    stageLifecycle,
    creationUndoOperation,
    stageCreationUndo,
    blockedLoadReason,
    resetForPlot,
    initForLoadedPlot,
    disposeAll,
    saveDraftHandler,
    undoDraftHandler,
    lockBlockedReason,
    lifecycleCloseOverride,
    creationCloseOverride,
    anySessionBlocked,
    saveReasonFields,
  };
}

export type SiviSessionsController = ReturnType<typeof createSiviSessions>;
