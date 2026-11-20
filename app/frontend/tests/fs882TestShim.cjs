const vm = require('node:vm');
const crypto = require('node:crypto');
const ts = require('typescript');

const FS882_VM_TS = "  function setExtendedShrubs(next: boolean) {\n    extendedShrubs = next;\n    for (const s of [siviSession, siviCoverSession, siviCombinedSession, siviCollectedSession, siviSpeciesSession, siviIdentitySession]) s?.presentation(next);\n    if (next) vegetationMode = 'cover';\n  }\n\n  async function loadSubEditor<T>(loader: () => Promise<T>, label: string, onFailed: () => void): Promise<T> {\n    const request = subEditorGeneration;\n    try { return await loader(); } catch (cause) { if (request === subEditorGeneration) { onFailed(); error = `${label} could not load: ${formatError(cause)}`; } throw cause; }\n  }\n\n  async function vegetationNotesTab() { activeTab = 'soils'; await tick(); document.querySelector<HTMLInputElement>('#header-soilSurveyor')?.focus(); }\n\n  function sourceEnter(event: KeyboardEvent) {\n    if ((event.ctrlKey || event.metaKey) && !event.altKey && !event.shiftKey && event.key.toLowerCase() === 's') {\n      if (typeof metadataOpen !== 'undefined' && metadataOpen) return;\n      event.preventDefault();\n      if (!draft.locked && !busy && !headerWorkflowBusy && capabilitiesReady && (dirty || childUnsaved)) {\n        void save();\n      }\n      return;\n    }\n    if (event.altKey && !event.ctrlKey && !event.metaKey && !event.shiftKey && event.key.toLowerCase() === 'p') {\n      if (twoPageOpen && twoPageScope === 'entry') return;\n      event.preventDefault(); fieldCardModalOpen = !fieldCardModalOpen; if (fieldCardModalOpen) fieldCardSplitOpen = false; return;\n    }\n    if (!sourceEnterEnabled || !container) return;\n    try { navigateSourceEnter(event, container); } catch (cause) { error = `Source Enter navigation failed; drafts retained: ${formatError(cause)}`; }\n  }\n\n  function openNewChild(kind: 'humus' | 'mineral' | 'other') {\n    if (kind === 'other' ? otherEditingDisabled || otherUnsaved : soilEditingDisabled || soilUnsaved) { error = 'Save or cancel drafts and wait for an unlocked, available child workflow before adding a row.'; return; }\n    error = null; newChild = kind;\n  }\n\n  async function deleteSourceChild(name: string, id: number) {\n    if (childEditingDisabled || (name.startsWith('Soil') && soilEditingDisabled)) { error = 'Save or cancel drafts and wait for an unlocked, available child workflow before deleting a row.'; return; }\n    if (!window.confirm(`Delete this ${name} record?`)) return;\n    if (name.startsWith('SubVeg')) await childOperation(() => PlotService.DeleteVegRecord(draft.plotNumber, id));\n    else if (name === 'SoilHumusXL') await childOperation(() => PlotService.DeleteHumusRecord(draft.plotNumber, id));\n    else if (name === 'SoilMineralXL') await childOperation(() => PlotService.DeleteMineralRecord(draft.plotNumber, id));\n    else if (name === 'SubOtherXL') await childOperation(() => PlotService.DeleteOtherRecord(draft.plotNumber, id));\n    else error = `Deletion is not migrated for ${name}.`;\n  }\n\n  async function createChild(first: string, second: string) {\n    const soilUnavailable = ordinarySoilUnavailable ?? (typeof historicalSoilUnavailable !== 'undefined' ? historicalSoilUnavailable : null);\n    await createChildImpl({ kind: newChild, first, second, plotNumber: typeof draft !== 'undefined' ? draft.plotNumber : '', soilUnavailable, setError: e => { error = e; }, clearNewChild: () => { newChild = null; }, childOperation: op => childOperation(op), SaveHumusRecord: r => PlotService.SaveHumusRecord(r), SaveMineralRecord: r => PlotService.SaveMineralRecord(r), SaveOtherRecord: r => PlotService.SaveOtherRecord(r) });\n  }\n\n  function sourceRows(name: string) { return projectSourceRows(name, { vegList, humusList, mineralList, otherList, childCapabilities }); }\n\n  function newDraft(): FS882Header { return newEmptyFS882Draft(); }\n\n  function stageSnowCoverRegime(raw: string) {\n    if ((typeof arcticInputsDisabled !== 'undefined' ? arcticInputsDisabled : headerInputsDisabled) || capabilities.snowCoverRegime !== true) return;\n    const value = raw === '' ? null : raw; draft.snowCoverRegime = value;\n    validateHeader('snowCoverRegime', ordinaryTextError({ label: 'Snow cover regime', kind: 'text', maximum: 1 }, value, original?.snowCoverRegime ?? null)); markDirty();\n  }\n\n  function stageActiveLayerDepth(raw: string) {\n    if ((typeof arcticInputsDisabled !== 'undefined' ? arcticInputsDisabled : headerInputsDisabled) || capabilities.activeLayerDepth !== true) return;\n    activeLayerDepthRaw = raw;\n    const cell = ordinaryNumberValue({ label: 'Active layer depth', kind: 'single' }, raw, original?.activeLayerDepth ?? null);\n    if (cell.error === null) draft.activeLayerDepth = cell.value;\n    validateHeader('activeLayerDepth', cell.error); markDirty();\n  }\n\n  function linkedVegetationParentBlocked(form: TwoPageVegetationForm): boolean {\n    twoPageVegetationActivityRevision;\n    if (twoPageVegetationParentBlocked || twoPageProject === null) return true;\n    const others = twoPageVegetationActivity({ contextId, project: twoPageProject, plot: draft.plotNumber, form });\n    return others.busy || others.blocked;\n  }\n\n  async function handleValidationJump(item: FormValidationItem) { activeTab = item.tab; if (item.tab === 'siviParent') siviParentOpen = true; await tick(); focusValidationTarget(container, item); }\n\n  function siviParentWriteOperation(op: ReviewedSiviOperation) { return runReviewedSiviOp({ kind: 'parentWrite', operation: op, allowed: !(busy || headerWorkflowBusy || siviParentActionUnsaved || siviProjectAssignmentUnsaved || siviParentSharedUnsaved || (op !== 'undo' && siviParentWriteEditingDisabled)), getOwner: () => siviParentWriteSession, retainAction: AuditRestoreAction.AuditRestoreRetain, pruneAction: AuditRestoreAction.AuditRestorePrune, setError: e => { error = e; }, setSuccess: s => { successMsg = s; } }); }\n\n  function siviParentActionOperation(op: ReviewedSiviOperation) { return runReviewedSiviOp({ kind: 'parentAction', operation: op, allowed: !(busy || headerWorkflowBusy || siviParentWriteUnsaved || siviProjectAssignmentUnsaved || siviParentSharedUnsaved || (op !== 'undo' && siviParentActionEditingDisabled)), getOwner: () => siviParentActionSession, retainAction: AuditRestoreAction.AuditRestoreRetain, pruneAction: AuditRestoreAction.AuditRestorePrune, setError: e => { error = e; }, setSuccess: s => { successMsg = s; } }); }\n\n  function stageSIVIParentAction(col: string, input: SIVIParentInput) { runStageSivi({ allowed: Boolean(siviParentActionSession && !siviParentActionEditingDisabled && isSIVIParentActionColumn(col)), guardMessage: 'Only independently available SIVI source actions can be drafted.', errorPrefix: '', failPrefix: 'SIVI source-action draft failed; existing state retained', action: () => siviParentActionSession!.stage(col as SIVIParentActionColumn, input), readError: () => siviParentActionSession!.view().error, currentError: error, setError: e => { error = e; }, setSuccess: s => { successMsg = s; } }); }\n\n  function siviProjectAssignmentOperation(op: ReviewedSiviOperation) { return runReviewedSiviOp({ kind: 'projectAssignment', operation: op, allowed: !(busy || headerWorkflowBusy || siviParentWriteUnsaved || siviParentActionUnsaved || siviParentSharedUnsaved || (op !== 'undo' && siviProjectAssignmentEditingDisabled)), getOwner: () => siviProjectAssignmentSession, retainAction: AuditRestoreAction.AuditRestoreRetain, pruneAction: AuditRestoreAction.AuditRestorePrune, setError: e => { error = e; }, setSuccess: s => { successMsg = s; } }); }\n\n  function stageSIVIProjectAssignment(input: SIVIProjectAssignmentInput) { runStageSivi({ allowed: Boolean(siviProjectAssignmentSession && !siviProjectAssignmentEditingDisabled), guardMessage: 'Only independently available existing ProjectID definitions can be selected.', errorPrefix: '', failPrefix: 'ProjectID selection failed; existing state retained', action: () => siviProjectAssignmentSession!.stage('ProjectID', input), readError: () => siviProjectAssignmentSession!.view().error, currentError: error, setError: e => { error = e; }, setSuccess: s => { successMsg = s; } }); }\n\n  function refreshSIVIParent(plot: string, peers: (SIVIParentWriteSession | SIVIParentActionWriteSession | SIVIProjectAssignmentSession | SIVIParentSharedSession | null)[]) {\n    return refreshSiviParentImpl({ plot, siviContextId, activeContextId: $projectState?.contextId, peers, siviParentSession, getPlot: (cid, p) => reads.track(ContextService.GetPlot(cid, p)), applyRefreshedHeader: header => { draft = { ...header }; original = structuredClone(header); activeLayerDepthRaw = null; dirty = false; headerValidation = {}; }, loadChildData });\n  }\n\n  function stageSIVIParentShared(col: SIVIParentSharedColumn, input: SIVIParentSharedInput) { runStageSivi({ allowed: Boolean(siviParentSharedSession && !siviParentSharedEditingDisabled), guardMessage: 'Shared SIVI fields require their clean owned parent.', errorPrefix: '', failPrefix: 'Shared SIVI draft failed; owned state retained', action: () => siviParentSharedSession!.stage(col, input), readError: () => siviParentSharedSession!.view().error, currentError: error, setError: e => { error = e; }, setSuccess: s => { successMsg = s; } }); }\n\n  function siviParentSharedOperation(op: ReviewedSiviOperation) { return runReviewedSiviOp({ kind: 'parentShared', operation: op, allowed: !(busy || headerWorkflowBusy || siviParentWriteUnsaved || siviParentActionUnsaved || siviProjectAssignmentUnsaved || (op !== 'undo' && siviParentSharedEditingDisabled)), getOwner: () => siviParentSharedSession, retainAction: AuditRestoreAction.AuditRestoreRetain, pruneAction: AuditRestoreAction.AuditRestorePrune, setError: e => { error = e; }, setSuccess: s => { successMsg = s; } }); }\n\n  async function changeSIVIProjectSource(source: number) { if (!siviParentSourceSession || busy || headerWorkflowBusy || dirty || childUnsaved) { error = 'Finish or Undo owned plot/selection drafts before changing ProjectID source.'; return; } error = null; try { if (!await siviParentSourceSession.setSource(source)) { error = siviParentSourceSession.view().error; return; } if (siviProjectAssignmentSession?.view().original && !await siviProjectAssignmentSession.load()) error = siviProjectAssignmentSession.view().error; } catch (cause) { error = `ProjectID source change failed; owned state retained: ${formatError(cause)}`; } }\n\n  async function reloadSIVIProjectSource() { if (!siviParentSourceSession || busy || headerWorkflowBusy || dirty || childUnsaved) { error = 'Finish or Undo owned plot/selection drafts before reloading ProjectID source.'; return; } error = null; try { if (!await siviParentSourceSession.load()) { error = siviParentSourceSession.view().error; return; } if (siviProjectAssignmentSession?.view().original && !await siviProjectAssignmentSession.load()) error = siviProjectAssignmentSession.view().error; } catch (cause) { error = `ProjectID source reload failed; owned state retained: ${formatError(cause)}`; } }\n\n  async function showSIVIParentPanel() { if (!siviParentReviewEnabled || busy || headerWorkflowBusy || dirty || nonParentChildUnsaved || !siviParentSession) { error = 'SIVI parent requires a clean available owned plot and its parent-review gate.'; return; } activeTab = 'siviParent'; siviParentOpen = true; await loadSIVIParentOriginals(); }\n\n  async function loadSIVIParentOriginals() { const parent = siviParentSession; if (!parent) throw new Error('SIVI parent originals have no current owned session.'); if (!parent.view().original && !await parent.load()) return; if (siviParentSession !== parent) return; if (!siviParentWriteUnsaved && !siviParentActionUnsaved && !siviProjectAssignmentUnsaved && !siviParentSharedUnsaved && siviParentSourceSession && !siviParentSourceView?.choices && !siviParentSourceView?.error && !siviParentSourceView?.authorityUnknown) await siviParentSourceSession.load(); }\n\n  function stageSIVIParentCell(col: string, input: SIVIParentInput) { runStageSivi({ allowed: Boolean(siviParentWriteSession && !siviParentWriteEditingDisabled && isSIVIParentDirectColumn(col)), guardMessage: 'Only available directly bound SIVI parent fields can be drafted.', errorPrefix: '', failPrefix: 'SIVI parent draft failed; existing state retained', action: () => siviParentWriteSession!.stage(col as SIVIParentDirectColumn, input), readError: () => siviParentWriteSession!.view().error, currentError: error, setError: e => { error = e; }, setSuccess: s => { successMsg = s; } }); }\n\n  function siviOperation(op: ReviewedSiviOperation) { return runReviewedSiviOp({ kind: 'height', operation: op, allowed: !(siviHeightEnabled === false || busy || headerWorkflowBusy || siviCoverUnsaved || siviCombinedUnsaved || siviCollectedUnsaved || siviSpeciesUnsaved || siviIdentityUnsaved || (op !== 'undo' && siviEditingDisabled)), getOwner: () => siviSession, retainAction: AuditRestoreAction.AuditRestoreRetain, pruneAction: AuditRestoreAction.AuditRestorePrune, setError: e => { error = e; }, setSuccess: s => { successMsg = s; } }); }\n\n  function stageSIVICell(rowId: string, col: SIVIHeightColumn, raw: string, nullValue: boolean) { runStageSivi({ allowed: Boolean(siviSession && !siviEditingDisabled), guardMessage: 'Unlock the clean available parent before editing SIVI heights.', errorPrefix: 'SIVI ', failPrefix: 'SIVI draft failed; original/raw state retained', action: () => siviSession!.stage(rowId, col, raw, nullValue), readError: () => siviSession!.view().error, currentError: error, setError: e => { error = e; }, setSuccess: s => { successMsg = s; } }); }\n\n  async function showSIVIPanel() { if (siviPanelOpen) { siviPanelOpen = false; return; } if (siviEditingDisabled && !siviUnsaved) { error = 'SIVI requires a clean, unlocked available parent.'; return; } siviPanelOpen = true; siviCoverPanelOpen = false; siviCombinedPanelOpen = false; siviCollectedPanelOpen = false; siviSpeciesPanelOpen = false; siviIdentityPanelOpen = false; if (!siviView?.review && !siviUnsaved) await siviOperation('load'); }\n\n  function siviCoverOperation(op: ReviewedSiviOperation) { return runReviewedSiviOp({ kind: 'cover', operation: op, allowed: !(siviCoverEnabled === false || busy || headerWorkflowBusy || siviUnsaved || siviCombinedUnsaved || siviCollectedUnsaved || siviSpeciesUnsaved || siviIdentityUnsaved || heightUnsaved || otherUnsaved || soilUnsaved || attributeUnsaved || collectedUnsaved || speciesUnsaved || siviParentWriteUnsaved || siviParentActionUnsaved || siviProjectAssignmentUnsaved || siviParentSharedUnsaved || (op !== 'undo' && siviCoverEditingDisabled)), getOwner: () => siviCoverSession, retainAction: AuditRestoreAction.AuditRestoreRetain, pruneAction: AuditRestoreAction.AuditRestorePrune, onReading: r => { siviCoverReading = r; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; } }); }\n\n  function stageSIVICoverCell(rowId: string, col: SIVICoverColumn, raw: string, nullValue: boolean) { runStageSivi({ allowed: Boolean(siviCoverSession && !siviCoverEditingDisabled), guardMessage: 'Unlock the clean available parent before editing SIVI covers.', errorPrefix: 'SIVI cover ', failPrefix: 'SIVI cover draft failed; original/raw state retained', action: () => siviCoverSession!.stage(rowId, col, raw, nullValue), readError: () => siviCoverSession!.view().error, currentError: error, setError: e => { error = e; }, setSuccess: s => { successMsg = s; } }); }\n\n  async function showSIVICoverPanel() { if (siviCoverPanelOpen) { siviCoverPanelOpen = false; return; } if (siviCoverEditingDisabled && !siviCoverUnsaved) { error = 'SIVI covers require a clean, unlocked available parent.'; return; } siviPanelOpen = false; siviCoverPanelOpen = true; siviCombinedPanelOpen = false; siviCollectedPanelOpen = false; siviSpeciesPanelOpen = false; siviIdentityPanelOpen = false; if (!siviCoverView?.review && !siviCoverUnsaved) await siviCoverOperation('load'); }\n\n  function refreshSIVIChildEditors(plot: string, owner: 'height' | 'cover' | 'combined' | 'collected' | 'species' | 'identity' | 'creation' | 'deletion' | 'restoration' | 'creationUndo') { return refreshSiviChildEditorsImpl({ plot, owner, siviCreationPending, siviDeletionPending, siviRestorationPending, siviCreationUndoPending, sessions: { height: siviSession, cover: siviCoverSession, combined: siviCombinedSession, collected: siviCollectedSession, species: siviSpeciesSession, identity: siviIdentitySession }, loadChildData }); }\n\n  function refreshSIVILifecycleLists(owner: 'creation' | 'deletion' | 'restoration' | 'creationUndo') { return refreshSiviLifecycleListsImpl({ owner, deletionSession: siviDeletionSession, restorationSession: siviRestorationSession, creationUndoSession: siviCreationUndoSession }); }\n\n  function siviCreationOperation(operation: 'load' | 'start' | 'save' | 'undo' | 'resolve' | 'cancel', form?: SIVICreationForm) { return executeSiviCreationOpImpl({ session: siviCreationSession, enabled: siviCreationEnabled, recoveryDisabled: siviCreationRecoveryDisabled, editingDisabled: siviCreationEditingDisabled, operation, form, getCurrentSession: () => siviCreationSession, setHostBusy: b => { siviCreationHostBusy = b; }, invalidateCapabilities: () => { capabilitiesReady = false; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; }, randomUUID: () => crypto.randomUUID(), refreshPeers: async plot => { await refreshSIVIChildEditors(plot, 'creation'); await refreshSIVILifecycleLists('creation'); } }); }\n\n  function stageSIVICreation(d: SIVICreationDraft) { try { if (!siviCreationSession || siviCreationEditingDisabled) throw new Error('Unlock the clean owned parent before correcting SIVI creation.'); siviCreationSession.updateDraft(d); error = siviCreationSession.view().error; successMsg = null; } catch (cause) { error = `SIVI creation correction failed; retained draft unchanged: ${formatError(cause)}`; } }\n\n  function siviLifecycleOperation(kind: 'deletion' | 'restoration', operation: 'load' | 'history' | 'review' | 'save' | 'undo' | 'resolve' | 'cancel', identity?: string, form?: SIVICreationForm) { return executeSiviLifecycleOpImpl({ kind, operation, identity, form, deletionSession: siviDeletionSession, restorationSession: siviRestorationSession, enabled: kind === 'deletion' ? siviDeletionEnabled : siviRestorationEnabled, recoveryDisabled: kind === 'deletion' ? siviDeletionRecoveryDisabled : siviRestorationRecoveryDisabled, editingDisabled: kind === 'deletion' ? siviDeletionEditingDisabled : siviRestorationEditingDisabled, getCurrentSession: () => (kind === 'deletion' ? siviDeletionSession : siviRestorationSession), setHostBusy: b => { siviLifecycleHostBusy = b; }, invalidateCapabilities: () => { capabilitiesReady = false; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; }, randomUUID: () => crypto.randomUUID(), refreshPeers: async (plot, k) => { await refreshSIVIChildEditors(plot, k); await refreshSIVILifecycleLists(k); } }); }\n\n  function stageSIVILifecycle(kind: 'deletion' | 'restoration', confirmed: boolean, action?: 'retain' | 'prune') { try { if (kind === 'deletion') { if (!siviDeletionSession || siviDeletionEditingDisabled) throw new Error('Unlock the clean owned parent before confirming deletion.'); siviDeletionSession.confirm(confirmed); error = siviDeletionSession.view().error; } else { if (!siviRestorationSession || siviRestorationEditingDisabled) throw new Error('Unlock the clean owned parent before confirming restoration.'); if (action) siviRestorationSession.choose(action); else siviRestorationSession.confirm(confirmed); error = siviRestorationSession.view().error; } successMsg = null; } catch (cause) { error = `SIVI ${kind} confirmation failed; retained review unchanged: ${formatError(cause)}`; } }\n\n  function siviCreationUndoOperation(operation: 'history' | 'review' | 'undo' | 'discard' | 'resolve' | 'cancel', historyId?: string) { return executeSiviCreationUndoOpImpl({ session: siviCreationUndoSession, enabled: siviCreationUndoEnabled, recoveryDisabled: siviCreationUndoRecoveryDisabled, editingDisabled: siviCreationUndoEditingDisabled, operation, historyId, getCurrentSession: () => siviCreationUndoSession, setHostBusy: b => { siviLifecycleHostBusy = b; }, invalidateCapabilities: () => { capabilitiesReady = false; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; }, randomUUID: () => crypto.randomUUID(), refreshPeers: async plot => { await refreshSIVIChildEditors(plot, 'creationUndo'); await refreshSIVILifecycleLists('creationUndo'); } }); }\n\n  function stageSIVICreationUndo(confirmed: boolean, action?: 'retain' | 'prune') { try { if (!siviCreationUndoSession || siviCreationUndoEditingDisabled) throw new Error('Unlock the clean owned parent before confirming creation Undo.'); if (action) siviCreationUndoSession.choose(action); else siviCreationUndoSession.confirm(confirmed); error = siviCreationUndoSession.view().error; successMsg = null; } catch (cause) { error = `SIVI creation Undo confirmation failed; retained review unchanged: ${formatError(cause)}`; } }\n\n  function siviCombinedOperation(op: ReviewedSiviOperation) { return runReviewedSiviOp({ kind: 'combined', operation: op, allowed: !(siviCombinedEnabled === false || busy || headerWorkflowBusy || siviUnsaved || siviCoverUnsaved || siviCollectedUnsaved || siviSpeciesUnsaved || siviIdentityUnsaved || heightUnsaved || otherUnsaved || soilUnsaved || attributeUnsaved || collectedUnsaved || speciesUnsaved || siviParentWriteUnsaved || siviParentActionUnsaved || siviProjectAssignmentUnsaved || siviParentSharedUnsaved || (op !== 'undo' && siviCombinedEditingDisabled)), getOwner: () => siviCombinedSession, retainAction: AuditRestoreAction.AuditRestoreRetain, pruneAction: AuditRestoreAction.AuditRestorePrune, trackOwner: true, onReading: r => { siviCombinedReading = r; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; } }); }\n\n  function stageSIVICombinedCell(rowId: string, col: SIVICombinedColumn, raw: string, nullValue: boolean) { runStageSivi({ allowed: Boolean(siviCombinedSession && !siviCombinedEditingDisabled), guardMessage: 'Unlock the clean available parent before editing combined SIVI rows.', errorPrefix: 'SIVI combined ', failPrefix: 'SIVI combined draft failed; original/raw state retained', action: () => siviCombinedSession!.stage(rowId, col, raw, nullValue), readError: () => siviCombinedSession!.view().error, currentError: error, setError: e => { error = e; }, setSuccess: s => { successMsg = s; } }); }\n\n  async function showSIVICombinedPanel() { if (siviCombinedPanelOpen) { siviCombinedPanelOpen = false; return; } if (siviCombinedEditingDisabled && !siviCombinedUnsaved) { error = 'Combined SIVI rows require a clean, unlocked available parent.'; return; } siviPanelOpen = false; siviCoverPanelOpen = false; siviCombinedPanelOpen = true; siviCollectedPanelOpen = false; siviSpeciesPanelOpen = false; siviIdentityPanelOpen = false; if (!siviCombinedView?.review && !siviCombinedUnsaved) await siviCombinedOperation('load'); }\n\n  function siviCollectedOperation(op: ReviewedSiviOperation) { return runReviewedSiviOp({ kind: 'collected', operation: op, allowed: !(siviCollectedEnabled === false || busy || headerWorkflowBusy || siviUnsaved || siviCoverUnsaved || siviCombinedUnsaved || siviSpeciesUnsaved || siviIdentityUnsaved || heightUnsaved || otherUnsaved || soilUnsaved || attributeUnsaved || collectedUnsaved || speciesUnsaved || siviParentWriteUnsaved || siviParentActionUnsaved || siviProjectAssignmentUnsaved || siviParentSharedUnsaved || (op !== 'undo' && siviCollectedEditingDisabled)), getOwner: () => siviCollectedSession, retainAction: AuditRestoreAction.AuditRestoreRetain, pruneAction: AuditRestoreAction.AuditRestorePrune, trackOwner: true, onReading: r => { siviCollectedReading = r; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; } }); }\n\n  function cycleSIVICollected(rowId: string) { runStageSivi({ allowed: Boolean(siviCollectedSession && !siviCollectedEditingDisabled), guardMessage: 'Unlock the clean available parent before cycling SIVI Collected.', errorPrefix: 'SIVI Collected ', failPrefix: 'SIVI Collected cycle failed; original state retained', action: () => siviCollectedSession!.cycle(rowId), readError: () => siviCollectedSession!.view().error, currentError: error, setError: e => { error = e; }, setSuccess: s => { successMsg = s; } }); }\n\n  async function showSIVICollectedPanel() { if (siviCollectedPanelOpen) { siviCollectedPanelOpen = false; return; } if (siviCollectedEditingDisabled && !siviCollectedUnsaved) { error = 'SIVI Collected requires a clean, unlocked available parent.'; return; } siviPanelOpen = false; siviCoverPanelOpen = false; siviCombinedPanelOpen = false; siviCollectedPanelOpen = true; siviSpeciesPanelOpen = false; siviIdentityPanelOpen = false; if (!siviCollectedView?.review && !siviCollectedUnsaved) await siviCollectedOperation('load'); }\n\n  function siviSpeciesOperation(op: ReviewedSiviOperation) { return runReviewedSiviOp({ kind: 'species', operation: op, allowed: !(siviSpeciesEnabled === false || busy || headerWorkflowBusy || siviUnsaved || siviCoverUnsaved || siviCombinedUnsaved || siviCollectedUnsaved || siviIdentityUnsaved || heightUnsaved || otherUnsaved || soilUnsaved || attributeUnsaved || collectedUnsaved || speciesUnsaved || siviParentWriteUnsaved || siviParentActionUnsaved || siviProjectAssignmentUnsaved || siviParentSharedUnsaved || (op !== 'undo' && siviSpeciesEditingDisabled)), getOwner: () => siviSpeciesSession, retainAction: AuditRestoreAction.AuditRestoreRetain, pruneAction: AuditRestoreAction.AuditRestorePrune, trackOwner: true, onReading: r => { siviSpeciesReading = r; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; } }); }\n\n  function stageSIVISpecies(rowId: string, command: 'Species' | 'context' | SpeciesDecisionKind, raw: string) { runStageSivi({ allowed: Boolean(siviSpeciesSession && !siviSpeciesEditingDisabled), guardMessage: 'Unlock the clean available parent before editing SIVI Species.', errorPrefix: 'SIVI Species ', failPrefix: 'SIVI Species draft failed; original/raw state retained', action: () => siviSpeciesSession!.stage(rowId, command, raw, false), readError: () => siviSpeciesSession!.view().error, currentError: error, setError: e => { error = e; }, setSuccess: s => { successMsg = s; } }); }\n\n  async function showSIVISpeciesPanel() { if (siviSpeciesPanelOpen) { siviSpeciesPanelOpen = false; return; } if (siviSpeciesEditingDisabled && !siviSpeciesUnsaved) { error = 'SIVI Species requires a clean, unlocked available parent.'; return; } siviPanelOpen = false; siviCoverPanelOpen = false; siviCombinedPanelOpen = false; siviCollectedPanelOpen = false; siviSpeciesPanelOpen = true; siviIdentityPanelOpen = false; if (!siviSpeciesView?.review && !siviSpeciesUnsaved) await siviSpeciesOperation('load'); }\n\n  function siviIdentityOperation(op: ReviewedSiviOperation) { return runReviewedSiviOp({ kind: 'identity', operation: op, allowed: !(siviIdentityEnabled === false || busy || headerWorkflowBusy || siviUnsaved || siviCoverUnsaved || siviCombinedUnsaved || siviCollectedUnsaved || siviSpeciesUnsaved || heightUnsaved || otherUnsaved || soilUnsaved || attributeUnsaved || collectedUnsaved || speciesUnsaved || siviParentWriteUnsaved || siviParentActionUnsaved || siviProjectAssignmentUnsaved || siviParentSharedUnsaved || (op !== 'undo' && siviIdentityEditingDisabled)), getOwner: () => siviIdentitySession, retainAction: AuditRestoreAction.AuditRestoreRetain, pruneAction: AuditRestoreAction.AuditRestorePrune, trackOwner: true, onReading: r => { siviIdentityReading = r; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; } }); }\n\n  function stageSIVIIdentity(rowId: string, raw: string, nullValue: boolean) { runStageSivi({ allowed: Boolean(siviIdentitySession && !siviIdentityEditingDisabled), guardMessage: 'Unlock the clean available parent before editing SIVI IDs.', errorPrefix: 'SIVI ID ', failPrefix: 'SIVI ID draft failed; original/raw state retained', action: () => siviIdentitySession!.stage(rowId, 'ID', raw, nullValue), readError: () => siviIdentitySession!.view().error, currentError: error, setError: e => { error = e; }, setSuccess: s => { successMsg = s; } }); }\n\n  async function showSIVIIdentityPanel() { if (siviIdentityPanelOpen) { siviIdentityPanelOpen = false; return; } if (siviIdentityEditingDisabled && !siviIdentityUnsaved) { error = 'SIVI IDs require a clean, unlocked available parent.'; return; } siviPanelOpen = false; siviCoverPanelOpen = false; siviCombinedPanelOpen = false; siviCollectedPanelOpen = false; siviSpeciesPanelOpen = false; siviIdentityPanelOpen = true; if (!siviIdentityView?.review && !siviIdentityUnsaved) await siviIdentityOperation('load'); }\n\n  function openSpeciesCodeCheck() { if (!codeCheckEnabled || childParentDisabled || childUnsaved || Object.keys(headerValidation).length > 0) { error = 'Finish or Undo existing drafts and unlock the available plot before reviewing species codes.'; return; } codeCheckOpen = true; if (typeof codeCheckBusy !== 'undefined') codeCheckBusy = true; error = null; successMsg = null; }\n\n  function canOpenProjectMetadata() { return twoPageOpen ? metadataEnabled && twoPageScope === 'entry' && Object.keys(headerValidation).length === 0 && typeof twoPageEditor?.openMetadataEditor === 'function' && Boolean(twoPageEditor.canOpenMetadataEditor?.()) : metadataEnabled && !childParentDisabled && !childUnsaved && Object.keys(headerValidation).length === 0; }\n\n  function openProjectMetadata() { if (!canOpenProjectMetadata()) { error = 'Finish or Undo existing drafts and unlock the available plot before reviewing project metadata.'; return; } if (twoPageOpen) twoPageEditor?.openMetadataEditor?.(); else { metadataOpen = true; if (typeof metadataBusy !== 'undefined') metadataBusy = true; } error = null; successMsg = null; }\n\n  function canOpenMetadataInPlace() { return twoPageOpen && canOpenProjectMetadata(); }\n\n  function openTwoPageReview() { const project = $projectState?.activeProject; if (!project || $projectState?.contextId !== siviContextId || !twoPageReviewEnabled || siviStandalone || childParentDisabled || childUnsaved || Object.keys(headerValidation).length > 0) { error = 'Finish or Undo existing drafts and unlock the available plot before reviewing two-page additional fields.'; return; } twoPageEntryInitialForm = extendedShrubs ? 'FS882-8x6XL-CHARS' : 'FS882-8x6XL'; twoPageScope = 'extra'; twoPageProject = project; twoPageOpen = true; error = null; successMsg = null; }\n\n  function openTwoPageCommonReview() { if (twoPageOpen) { error = 'Finish and close the current two-page field review before changing its scope.'; return; } if (!twoPageCommonReviewEnabled) { error = 'Two-page common-field review is independently disabled.'; return; } openTwoPageReview(); if (twoPageOpen) twoPageScope = 'common'; }\n\n  function openTwoPageEntryReview() { if (twoPageOpen || !twoPageEntryReviewEnabled) { error = 'Complete-entry review is disabled or another two-page owner is still open.'; return; } openTwoPageReview(); if (twoPageOpen) twoPageScope = 'entry'; }\n\n  function openProfileSUFromTwoPage() { if (twoPageBusy || twoPageSoilBusy || twoPageSoilBlocked || twoPageVegetationBusy || twoPageVegetationBlocked) { error = 'Finish active two-page operations before opening Plot Profiling / Create SU.'; return; } if (siviSourceBarrier) { error = 'Observe the ProjectID source preference outcome before opening profile rules.'; return; } twoPageOpen = false; twoPageBusy = false; twoPageProject = null; profileReviewOpen = true; profileReviewBusy = true; }\n\n  function applyDiagnosticHumusThickness(v: number) { applyDiagnosticHumusThicknessImpl({ disabled: headerInputsDisabled, supported: capabilities.humusThickness === true, value: v, draft, original, setError: e => { error = e; }, validateHeader, markDirty, bumpRevision: () => { headerRevision++; } }); }\n\n  function applyDiagnosticSMR(smr: string) { if (headerInputsDisabled || capabilities.moistureRegime !== true) return; draft.moistureRegime = smr === '' ? null : smr; validateHeader('moistureRegime', null); markDirty(); headerRevision++; }\n\n  function applyDiagnosticSNR(snr: string) { if (headerInputsDisabled || capabilities.nutrientRegime !== true) return; draft.nutrientRegime = snr === '' ? null : snr; validateHeader('nutrientRegime', null); markDirty(); headerRevision++; }\n\n  function refreshTwoPagePeers(scope: 'extra' | 'common' | 'entry') { return refreshTwoPagePeersImpl({ scope, contextId, twoPageProject, plotNumber: draft.plotNumber, twoPageSessions, twoPageCommonSessions, twoPageEntrySessions, refreshParent: () => refreshSIVIParent(draft.plotNumber, [siviParentWriteSession, siviParentActionSession, siviProjectAssignmentSession, siviParentSharedSession]) }); }\n\n  async function refreshProjectMetadata() { if (!siviParentSession?.view().original && !siviParentSession?.view().error) { await loadChildData(draft.plotNumber); return; } await refreshSIVIParent(draft.plotNumber, [siviParentWriteSession, siviParentActionSession, siviProjectAssignmentSession, siviParentSharedSession]); if (siviParentSourceSession && (siviParentSourceSession.view().choices || siviParentSourceSession.view().error) && !await siviParentSourceSession.load()) throw new Error(siviParentSourceSession.view().error ?? 'ProjectID choices did not refresh after the metadata commit.'); }\n\n  function openEnvironmentSU(direction: 'forward' | 'reverse' = 'forward') { if (!(direction === 'reverse' ? siteUnitEnvironmentEnabled : environmentSUEnabled) || childParentDisabled || childUnsaved || Object.keys(headerValidation).length > 0 || !$projectState?.activeSU || $projectState.activeSU === 'None' || !original) { error = 'Select an owned-project SU, finish or Undo all drafts and unlock the available plot before reviewing Env Into SU.'; return; } environmentSUDirection = direction; environmentSUOpen = true; error = null; successMsg = null; }\n\n  function openExternalSUEnvironment() { if (!externalSUEnvironmentEnabled || siviStandalone || !separateSUSelected || childParentDisabled || childUnsaved || Object.keys(headerValidation).length > 0 || !original) { error = 'Select a separate SU file and finish or Undo all drafts before reviewing SU Into Env.'; return; } const state = $projectState; if (!state?.projectPath || !state.suPath) { error = 'Selected project and SU paths are unavailable; no transfer review was opened.'; return; } externalSUEnvironmentSession({ contextId, project: state.activeProject, projectPath: state.projectPath, su: state.activeSU, suPath: state.suPath }).reviewSourceForm(null); environmentSUDirection = 'external-reverse'; environmentSUOpen = true; error = null; successMsg = null; }\n\n  async function refreshAfterRestore(plot: string, request: number) { const header = await reads.track(PlotService.GetPlot(plot)); if (!header) throw new Error('Restored plot could not be reloaded.'); await loadChildData(plot); if (request !== loadRequest) return; const locked = draft.locked; draft = { ...header, locked }; original = JSON.parse(JSON.stringify(header)); activeLayerDepthRaw = null; dirty = false; headerValidation = {}; }\n\n  async function load(p?: string) {\n    const blockedReason = firstMatch<string>([\n      [() => siviDeletionPending || siviRestorationPending || siviCreationUndoPending, 'Finish the source deletion/restoration/creation Undo review or resolve its exact retained request before replacing the plot owner.'],\n      [() => siviCreationPending, 'Finish SIVI creation or resolve its exact retained request before replacing the plot owner.'],\n      [() => pictureMetadataPending, 'Finish or explicitly discard picture metadata drafts/recovery before replacing their plot owner.'],\n      [() => Boolean(siviParentSharedSession && (siviParentSharedSession.closeState().unsaved || siviParentSharedSession.closeState().busy)), 'Finish or explicitly Undo shared SIVI drafts/recovery before replacing their plot owner.'],\n      [() => Boolean(siviProjectAssignmentSession && (siviProjectAssignmentSession.closeState().unsaved || siviProjectAssignmentSession.closeState().busy)), 'Finish or explicitly Undo ProjectID selection/recovery before replacing its plot owner.'],\n      [() => Boolean(siviParentActionSession && (siviParentActionSession.closeState().unsaved || siviParentActionSession.closeState().busy)), 'Finish or explicitly Undo SIVI source-action drafts/recovery before replacing their plot owner.'],\n      [() => Boolean(siviParentWriteSession && (siviParentWriteSession.closeState().unsaved || siviParentWriteSession.closeState().busy)), 'Finish or explicitly Undo SIVI parent drafts/recovery before replacing their plot owner.'],\n      [() => Boolean(siviParentSourceView?.busy), 'Wait for the current SIVI source operation before replacing its plot owner.'],\n      [() => Boolean(siviSession && (siviSession.closeState().unsaved || siviSession.closeState().busy)), 'SIVI drafts or operations must finish or be explicitly undone before replacing their plot owner.'],\n      [() => Boolean(siviCoverSession && (siviCoverSession.closeState().unsaved || siviCoverSession.closeState().busy)), 'SIVI cover drafts or operations must finish or be explicitly undone before replacing their plot owner.'],\n      [() => Boolean(siviCombinedSession && (siviCombinedSession.closeState().unsaved || siviCombinedSession.closeState().busy)), 'Combined SIVI drafts or operations must finish or be explicitly undone before replacing their plot owner.'],\n      [() => Boolean(siviCollectedSession && (siviCollectedSession.closeState().unsaved || siviCollectedSession.closeState().busy)), 'SIVI Collected drafts or operations must finish or be explicitly undone before replacing their plot owner.'],\n      [() => Boolean(siviSpeciesSession && (siviSpeciesSession.closeState().unsaved || siviSpeciesSession.closeState().busy)), 'SIVI Species drafts or operations must finish or be explicitly undone before replacing their plot owner.'],\n      [() => Boolean(siviIdentitySession && (siviIdentitySession.closeState().unsaved || siviIdentitySession.closeState().busy)), 'SIVI ID drafts or operations must finish or be explicitly undone before replacing their plot owner.'],\n    ]);\n    if (blockedReason) { error = blockedReason; return; }\n    for (const s of [siviParentSession, siviParentSourceSession, siviParentWriteSession, siviParentActionSession, siviProjectAssignmentSession, siviParentSharedSession, siviSession, siviCoverSession, siviCombinedSession, siviCollectedSession, siviSpeciesSession, siviIdentitySession]) s?.dispose();\n    siviParentSession = null; siviParentSourceSession = null; siviParentWriteSession = null; siviParentActionSession = null; siviProjectAssignmentSession = null; siviParentSharedSession = null;\n    siviParentSharedRevision++; siviProjectAssignmentRevision++; siviParentActionRevision++; siviParentWriteRevision++; siviParentSourceRevision++; siviParentRevision++; siviParentOpen = false;\n    if (activeTab === 'siviParent') activeTab = 'site';\n    siviSession = null; siviCoverSession = null; siviCombinedSession = null; siviCollectedSession = null; siviSpeciesSession = null; siviIdentitySession = null;\n    for (const r of [siviReads, siviCoverReads, siviCombinedReads, siviCollectedReads, siviSpeciesReads, siviIdentityReads]) r.cancelAll();\n    siviRevision++; siviCoverRevision++; siviCombinedRevision++; siviCollectedRevision++; siviSpeciesRevision++; siviIdentityRevision++;\n    siviPanelOpen = false; siviCoverPanelOpen = false; siviCombinedPanelOpen = false; siviCollectedPanelOpen = false; siviSpeciesPanelOpen = false; siviIdentityPanelOpen = false;\n    const request = ++loadRequest;\n    reads.cancelAll();\n    if (workingUnitSession.plot !== (p ?? '')) workingUnitSession.mode = null;\n    workingUnitSession.plot = p ?? '';\n    busy = true; error = null; capabilitiesReady = false; masterAllowed = false;\n    heightDrafts = {}; otherDrafts = {}; soilDrafts = {}; attributeDrafts = {}; collectedDrafts = {}; speciesDrafts = {}; speciesChoices = {}; deletionReview = null; creationDraft = null; creationChoices = null; personalDraft = null; savedPersonalCodes = []; vegList = []; vegetationReadUnavailable = null; historicalSoilUnavailable = null; humusList = []; mineralList = []; otherList = []; auditList = []; childCapabilities = { Veg: {}, Humus: {}, Mineral: {}, Other: {} };\n    try {\n      const [fields, res, masterPolicy] = await Promise.all([reads.track(PlotService.GetHeaderCapabilities()), p ? reads.track(PlotService.GetPlot(p)) : Promise.resolve(null), reads.track(PlotService.CanEditMasterBEC())]);\n      if (request !== loadRequest) return;\n      if (fields === null) throw new Error('Header capabilities were not returned.');\n      capabilities = fields; masterAllowed = masterPolicy;\n      if (p && !res) throw new Error(`Plot ${p} could not be loaded.`);\n      if (p) await loadChildData(p);\n      if (request !== loadRequest) return;\n      if (res !== null) {\n        draft = { ...res }; original = JSON.parse(JSON.stringify(res)); activeLayerDepthRaw = null; dirty = false; headerValidation = {}; headerRevision++;\n        const plot = res.plotNumber;\n        if (siviParentReviewEnabled && $projectState?.contextId === siviContextId) {\n          const project = $projectState.activeProject;\n          siviParentSession = new SIVIParentReadSession({ contextId: siviContextId, project, plot }, () => siviParentReads.track(ContextService.GetSIVIParentOriginal(siviContextId, plot)), () => siviParentReads.cancelAll(), () => siviParentRevision++);\n          siviParentSourceSession = new SIVIParentSourceSession({ contextId: siviContextId, project, plot }, { join: () => siviParentSourceReads.track(ContextService.GetSIVIParentJoinReview(siviContextId, plot)), choices: () => siviParentSourceReads.track(ContextService.GetSIVIProjectIDChoices(siviContextId)), setSource: (expected, source) => ContextService.SetSIVIProjectIDSource(siviContextId, expected, source), cancel: () => siviParentSourceReads.cancelAll() }, () => siviParentSourceRevision++);\n          if (siviParentEditingEnabled) { siviParentWriteSession = new SIVIParentWriteSession({ contextId: siviContextId, project, plot }, { read: () => siviParentWriteReads.track(ContextService.GetSIVIParentDirectOriginal(siviContextId, plot)), cancelRead: () => siviParentWriteReads.cancelAll(), save: req => ContextService.SaveSIVIParentDirect(siviContextId, plot, req), restore: (hId, act) => ContextService.RestoreSIVIParentDirect(siviContextId, plot, hId, act), refreshParent: () => refreshSIVIParent(plot, [siviParentActionSession, siviProjectAssignmentSession, siviParentSharedSession]) }, () => siviParentWriteRevision++); siviParentWriteRevision++; }\n          if (siviParentActionEditingEnabled) { siviParentActionSession = new SIVIParentActionWriteSession({ contextId: siviContextId, project, plot }, { read: () => siviParentActionReads.track(ContextService.GetSIVIParentActionOriginal(siviContextId, plot)), cancelRead: () => siviParentActionReads.cancelAll(), save: req => ContextService.SaveSIVIParentActions(siviContextId, plot, req), restore: (hId, act) => ContextService.RestoreSIVIParentActions(siviContextId, plot, hId, act), refreshParent: () => refreshSIVIParent(plot, [siviParentWriteSession, siviProjectAssignmentSession, siviParentSharedSession]) }, () => siviParentActionRevision++); siviParentActionRevision++; }\n          if (siviProjectAssignmentEnabled) { siviProjectAssignmentSession = new SIVIProjectAssignmentSession({ contextId: siviContextId, project, plot }, { read: () => siviProjectAssignmentReads.track(ContextService.GetSIVIProjectAssignmentOriginal(siviContextId, plot)), cancelRead: () => siviProjectAssignmentReads.cancelAll(), save: req => ContextService.SaveSIVIProjectAssignment(siviContextId, plot, req), restore: (hId, act) => ContextService.RestoreSIVIProjectAssignment(siviContextId, plot, hId, act), refreshParent: () => refreshSIVIParent(plot, [siviParentWriteSession, siviParentActionSession, siviParentSharedSession]) }, () => siviProjectAssignmentRevision++); siviProjectAssignmentRevision++; }\n          if (siviParentSharedEnabled) { siviParentSharedSession = new SIVIParentSharedSession({ contextId: siviContextId, project, plot }, { read: () => siviParentSharedReads.track(PlotEntryService.GetSIVIParentSharedOriginal(siviContextId, plot)), readReferences: zone => siviParentSharedReads.track(PlotEntryService.GetSIVIParentSharedReferences(siviContextId, plot, zone)), cancelRead: () => siviParentSharedReads.cancelAll(), save: req => PlotEntryService.SaveSIVIParentShared(siviContextId, plot, req), restore: (hId, act) => PlotEntryService.RestoreSIVIParentShared(siviContextId, plot, hId, act), refreshParent: () => refreshSIVIParent(plot, [siviParentWriteSession, siviParentActionSession, siviProjectAssignmentSession]) }, () => siviParentSharedRevision++, siviParentReferenceEnabled); siviParentSharedRevision++; }\n          siviParentSourceRevision++; siviParentRevision++;\n        }\n        if (siviHeightEnabled) {\n          siviSession = new SIVIHeightSession(plot, { read: ext => siviReads.track(ContextService.GetSIVIVegetation(siviContextId, plot, ext)), save: (ext, rev, ed) => ContextService.SaveSIVIHeights(siviContextId, plot, ext, rev, ed), restore: (hId, act) => ContextService.RestoreSIVIHeights(siviContextId, plot, hId, act), refreshParent: () => refreshSIVIChildEditors(plot, 'height') }, () => siviRevision++, extendedShrubs, siviChildSourceNoticesEnabled); siviRevision++; }\n        if (siviCoverEnabled) {\n          siviCoverSession = new SIVICoverSession(plot, { read: extended => siviCoverReads.track(PlotEntryService.GetSIVICoverOriginal(siviContextId, plot, extended)), save: (ext, req) => PlotEntryService.SaveSIVICoverReviewed(siviContextId, plot, ext, req), restore: (hId, act) => PlotEntryService.RestoreSIVICoverReviewed(siviContextId, plot, hId, act), refreshParent: () => refreshSIVIChildEditors(plot, 'cover') }, () => siviCoverRevision++, extendedShrubs, siviChildSourceNoticesEnabled); siviCoverRevision++; }\n        if (siviCombinedEnabled) {\n          siviCombinedSession = new SIVICombinedSession(plot, { read: ext => siviCombinedReads.track(PlotEntryService.GetSIVICombinedOriginal(siviContextId, plot, ext)), save: (ext, req) => PlotEntryService.SaveSIVICombinedReviewed(siviContextId, plot, ext, req), restore: (hId, act) => PlotEntryService.RestoreSIVICombinedReviewed(siviContextId, plot, hId, act), refreshParent: () => refreshSIVIChildEditors(plot, 'combined') }, () => siviCombinedRevision++, extendedShrubs, siviChildSourceNoticesEnabled); siviCombinedRevision++; }\n        if (siviCollectedEnabled) {\n          siviCollectedSession = new SIVICollectedSession(plot, { read: extended => siviCollectedReads.track(PlotEntryService.GetSIVICollectedOriginal(siviContextId, plot, extended)), save: (ext, req) => PlotEntryService.SaveSIVICollectedReviewed(siviContextId, plot, ext, req), restore: (hId, act) => PlotEntryService.RestoreSIVICollectedReviewed(siviContextId, plot, hId, act), refreshParent: () => refreshSIVIChildEditors(plot, 'collected') }, () => siviCollectedRevision++, extendedShrubs, siviChildSourceNoticesEnabled); siviCollectedRevision++; }\n        if (siviSpeciesEnabled) { const project = $projectState?.activeProject; if (!project) throw new Error('SIVI Species requires the active owned project before creating its editor.'); siviSpeciesSession = new SIVISpeciesSession({ contextId: siviContextId, project, plot }, { read: async ext => { const [original, references] = await Promise.all([siviSpeciesReads.track(PlotEntryService.GetSIVISpeciesOriginal(siviContextId, plot, ext)), siviSpeciesReads.track(PlotEntryService.GetSIVISpeciesReferences(siviContextId, plot))]); return { original, references }; }, save: (ext, req) => PlotEntryService.SaveSIVISpeciesReviewed(siviContextId, plot, ext, req), restore: (hId, act) => PlotEntryService.RestoreSIVISpeciesReviewed(siviContextId, plot, hId, act), refreshParent: () => refreshSIVIChildEditors(plot, 'species') }, () => siviSpeciesRevision++, extendedShrubs, siviChildSourceNoticesEnabled); siviSpeciesRevision++; }\n        if (siviIdentityEnabled) { siviIdentitySession = new SIVIIdentitySession(plot, { read: ext => siviIdentityReads.track(PlotEntryService.GetSIVIIdentityOriginal(siviContextId, plot, ext)), save: (ext, req) => PlotEntryService.SaveSIVIIdentityReviewed(siviContextId, plot, ext, req), restore: (hId, act) => PlotEntryService.RestoreSIVIIdentityReviewed(siviContextId, plot, hId, act), refreshParent: () => refreshSIVIChildEditors(plot, 'identity') }, () => siviIdentityRevision++, extendedShrubs, siviChildSourceNoticesEnabled); siviIdentityRevision++; }\n      } else { draft = newDraft(); original = null; activeLayerDepthRaw = null; dirty = false; headerValidation = {}; }\n      capabilitiesReady = true;\n      if (siviStandalone && siviStandaloneEnabled && siviParentSession) { activeTab = 'siviParent'; siviParentOpen = true; await loadSIVIParentOriginals(); if (request !== loadRequest) return; }\n    } catch (e) { if (request === loadRequest) error = formatError(e); } finally { if (request === loadRequest) busy = false; }\n  }\n\n  async function loadChildData(p: string) {\n    const request = loadRequest;\n    const outcome = await executeChildDataLoad({ ordinaryVegetationUnavailable, ordinarySoilUnavailable, siviIdentityEnabled, readVegetationAvailability: () => reads.track(ContextService.GetVegetationReadAvailability(siviContextId, p)), listVegRecords: () => reads.track(PlotService.ListVegRecords(p)), listHumusRecords: () => reads.track(PlotService.ListHumusRecords(p)), listMineralRecords: () => reads.track(PlotService.ListMineralRecords(p)), listOtherRecords: () => reads.track(PlotService.ListOtherRecords(p)), listAuditReadEntries: () => reads.track(PlotService.ListAuditReadEntries(p)), getVegCaps: () => reads.track(PlotService.GetChildCapabilities('Veg')), getHumusCaps: () => reads.track(PlotService.GetChildCapabilities('Humus')), getMineralCaps: () => reads.track(PlotService.GetChildCapabilities('Mineral')), getOtherCaps: () => reads.track(PlotService.GetChildCapabilities('Other')) });\n    if (request !== loadRequest) return;\n    childCapabilities = outcome.childCapabilities; vegList = outcome.vegList; vegetationReadUnavailable = outcome.vegetationReadUnavailable; historicalSoilUnavailable = outcome.historicalSoilUnavailable; humusList = outcome.humusList; mineralList = outcome.mineralList; otherList = outcome.otherList; auditList = outcome.auditList; childRevision++;\n  }\n\n  async function loadReferenceLists() {\n    const request = ++referenceRequest; referenceReads.cancelAll();\n    try { const [m, n, ms, ss] = await Promise.all([referenceReads.track(PlotEntryService.GetListItems('MoistureRegime')), referenceReads.track(PlotEntryService.GetListItems('NutrientRegime')), referenceReads.track(PlotEntryService.GetListItems('MesoSlopePosition')), referenceReads.track(PlotEntryService.GetListItems('SurfaceShape'))]); if (request !== referenceRequest) return; moistureList = m ?? []; nutrientList = n ?? []; mesoSlopeList = ms ?? []; surfaceShapeList = ss ?? []; } catch (e) { if (request === referenceRequest) error = `Reference lists could not be loaded: ${String(e)}`; }\n  }\n\n  async function searchSpecies() {\n    const request = ++speciesRequest; speciesReads.cancelAll();\n    if (!speciesSearchQuery.trim()) { speciesSearchResults = []; searchingSpecies = false; return; }\n    searchingSpecies = true;\n    try { const res = await speciesReads.track(PlotEntryService.SearchSpecies(speciesSearchQuery, 15)); if (request !== speciesRequest) return; speciesSearchResults = res ?? []; } catch (e) { if (request === speciesRequest) error = `Species search failed: ${String(e)}`; } finally { if (request === speciesRequest) searchingSpecies = false; }\n  }\n\n  async function selectSpeciesToAdd(sp: SpeciesItem) {\n    if (await childOperation(() => PlotService.SaveVegRecord({ ...newVegetationFields, id: 0, plotNumber: draft.plotNumber, species: sp.code, layer: 'A', cover1: 0, totalA: 0 }))) { showSpeciesModal = false; speciesSearchQuery = ''; speciesSearchResults = []; }\n  }\n\n  function stageSpeciesCell(form: string, id: number, raw: string) { const res = stageSpeciesCellImpl({ disabled: speciesEditingDisabled, childCapabilities, vegList, humusList, mineralList, otherList, plotNumber: draft.plotNumber, speciesDrafts, speciesChoices, speciesLists, form, id, raw }); speciesDrafts = res.speciesDrafts; speciesChoices = res.speciesChoices; if (res.error) error = res.error; else { successMsg = null; if (res.clearSpeciesError && error?.startsWith('Species ')) error = null; } if (res.bumpRevision) childRevision++; }\n\n  function reviewSpeciesChoices(id: number) { return reviewSpeciesChoicesImpl({ id, speciesEditingDisabled, getSpeciesDrafts: () => speciesDrafts, getSpeciesChoices: () => speciesChoices, bumpRequest: () => ++speciesChoiceRequest, currentRequest: () => speciesChoiceRequest, port: { speciesChoiceReads, ListVegetationSpeciesAliases: req => PlotService.ListVegetationSpeciesAliases(req), ListVegetationSpeciesUsers: req => PlotService.ListVegetationSpeciesUsers(req) }, setDecisionBusy: b => { speciesDecisionBusy = b; }, setSpeciesChoices: c => { speciesChoices = c; }, setError: e => { error = e; } }); }\n\n  function chooseSpeciesCode(id: number, kind: SpeciesDecisionKind, selected?: string) { try { if (speciesEditingDisabled) throw new Error('Wait for available, unlocked species editing before selecting a decision.'); const choices = speciesChoices[String(id)]; if (!choices) throw new Error('Review the current species entry before selecting a decision.'); speciesDrafts = chooseSpecies(speciesDrafts, id, choices, kind, selected); const next = { ...speciesChoices }; delete next[String(id)]; speciesChoices = next; error = null; successMsg = null; childRevision++; } catch (cause) { error = `Species decision failed; draft retained: ${formatError(cause)}`; } }\n\n  function cancelSpeciesDrafts() { return cancelChildDraftsImpl({ guardBlocked: personalDraft !== null || busy || headerWorkflowBusy, guardMessage: personalDraft !== null ? 'Cancel personal definition entry before cancelling plot species drafts.' : 'Wait for the current operation before cancelling species drafts.', clearDrafts: () => { speciesDrafts = {}; speciesChoices = {}; }, bumpRevision: () => { childRevision++; }, plotNumber: draft.plotNumber, loadChildData, successMessage: savedPersonalCodes.length ? 'Plot species drafts cancelled. No plot data or project history changed; explicitly saved personal definitions remain available.' : 'Species drafts cancelled. Stored data and history were unchanged; current rows reloaded.', reloadErrorMessage: 'Species drafts cancelled, but rows could not be reloaded. Reopen the plot', setBusy: b => { busy = b; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; }, invalidateCapabilities: () => { capabilitiesReady = false; } }); }\n\n  function startPersonalSpecies(id: number) { try { if (!personalSpeciesEnabled || speciesEditingDisabled) throw new Error('Personal definition creation is unavailable while loading, locked or another workflow is active.'); const cell = speciesDrafts[String(id)], choices = speciesChoices[String(id)]; if (!cell || !choices) throw new Error('Review the current unknown code before creating its personal definition.'); personalDraft = beginPersonalSpecies(id, cell, choices); error = null; successMsg = null; } catch (cause) { error = `Personal definition could not start: ${formatError(cause)}`; } }\n\n  function cancelPersonalSpecies() { if (busy || headerWorkflowBusy) { error = 'Wait for the personal definition operation before cancelling entry.'; return; } personalDraft = null; error = null; successMsg = 'Personal definition entry cancelled without writes. The original plot species draft or new-row proposal is retained.'; }\n\n  function personalSourceMatches(proposed: PersonalSpeciesDraft): boolean { return proposed.source.kind === 'existing' ? matchesPersonalSpeciesSource(proposed, speciesDrafts[String(proposed.source.id)]) : proposed.source.kind === 'creation' && creationEnabled && matchesCreationPersonalSpeciesSource(proposed, creationDraft); }\n\n  function savePersonalSpecies() { return savePersonalSpeciesImpl({ proposed: personalDraft, enabled: personalSpeciesEnabled, busy, headerWorkflowBusy, dirty, locked: draft.locked, capabilitiesReady, personalSourceMatches, speciesChoiceReads, CreatePersonalSpeciesDefinition: req => PlotService.CreatePersonalSpeciesDefinition(req), ListVegetationSpeciesUsers: req => PlotService.ListVegetationSpeciesUsers(req), ListVegetationSpeciesAliases: req => PlotService.ListVegetationSpeciesAliases(req), getSpeciesDrafts: () => speciesDrafts, getSpeciesChoices: () => speciesChoices, getCreationDraft: () => creationDraft, getSavedPersonalCodes: () => savedPersonalCodes, setBusy: b => { busy = b; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; }, setPersonalDraft: d => { personalDraft = d; }, setSavedPersonalCodes: c => { savedPersonalCodes = c; }, setSpeciesDrafts: d => { speciesDrafts = d; }, setSpeciesChoices: c => { speciesChoices = c; }, setCreationDraft: d => { creationDraft = d; }, setCreationChoices: c => { creationChoices = c; }, bumpChildRevision: () => { childRevision++; }, invalidateCapabilities: () => { capabilitiesReady = false; } }); }\n\n  function saveSpeciesDrafts() { const updates = speciesUpdates(speciesDrafts); return saveChildDraftsImpl({ disabled: speciesEditingDisabled, guardMessage: 'Save a clean, unlocked header with available species references before saving.', hasUpdates: updates.length > 0, noChangeMessage: 'No species values changed.', clearEmpty: () => { speciesDrafts = {}; }, commit: () => PlotService.UpdateVegetationSpecies(draft.plotNumber, updates), clearOnCommit: () => { speciesDrafts = {}; speciesChoices = {}; }, plotNumber: draft.plotNumber, loadChildData, buildSuccessMessage: () => [`Saved ${updates.length} species row drafts.`, ...aCoverSourceNotices(updates, vegList)].join(' '), committedRefreshPrefix: 'Species changes committed, but refresh failed. Reopen the plot before editing', failedPrefix: 'Species save failed; drafts retained', setBusy: b => { busy = b; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; }, invalidateCapabilities: () => { capabilitiesReady = false; } }); }\n\n  function stageCollectedCell(id: number, form: string) { const res = stageCollectedCellImpl({ disabled: collectedEditingDisabled, childCapabilities, vegList, humusList, mineralList, otherList, plotNumber: draft.plotNumber, collectedDrafts, id, form }); collectedDrafts = res.collectedDrafts; if (res.error) error = res.error; else { successMsg = null; if (res.clearCollectedError && error?.startsWith('Collected ')) error = null; } if (res.bumpRevision) childRevision++; }\n\n  function cancelCollectedDrafts() { return cancelChildDraftsImpl({ guardBlocked: busy || headerWorkflowBusy, guardMessage: 'Wait for the current operation before cancelling Collected drafts.', clearDrafts: () => { collectedDrafts = {}; }, bumpRevision: () => { childRevision++; }, plotNumber: draft.plotNumber, loadChildData, successMessage: 'Collected drafts cancelled. Stored data and history were unchanged; current rows reloaded.', reloadErrorMessage: 'Collected drafts cancelled, but current rows could not be reloaded. Reopen the plot', setBusy: b => { busy = b; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; }, invalidateCapabilities: () => { capabilitiesReady = false; } }); }\n\n  function saveCollectedDrafts() { const updates = collectedUpdates(collectedDrafts), sources = updates.map(({ id }) => ({ id, form: collectedDrafts[String(id)].form ?? '' })); return saveChildDraftsImpl({ disabled: collectedEditingDisabled, guardMessage: 'Save a clean, unlocked header before saving Collected drafts.', hasUpdates: updates.length > 0, noChangeMessage: 'No Collected values changed.', clearEmpty: () => { collectedDrafts = {}; }, commit: () => PlotService.UpdateCollectedRecords(draft.plotNumber, updates), clearOnCommit: () => { collectedDrafts = {}; }, plotNumber: draft.plotNumber, loadChildData, buildSuccessMessage: () => [`Saved ${updates.length} Collected row drafts.`, ...aCoverSourceNotices(sources, vegList)].join(' '), committedRefreshPrefix: 'Collected changes committed, but refresh failed. Reopen the plot before editing', failedPrefix: 'Collected save failed; drafts retained', setBusy: b => { busy = b; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; }, invalidateCapabilities: () => { capabilitiesReady = false; } }); }\n\n  function startVegetationCreation(form: string) { startVegetationCreationImpl({ allowed: Boolean(creationEnabled && !childParentDisabled && !childUnsaved && speciesReferenceReady && !speciesReferenceBusy), form, setCreationDraft: d => { creationDraft = d; }, setCreationChoices: c => { creationChoices = c; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; } }); }\n\n  function stageCreationCell(column: string, raw: string) { if (!creationDraft || personalDraft !== null || busy || headerWorkflowBusy) { error = 'An available creation draft without personal metadata entry is required before editing.'; return; } try { creationDraft = stageVegetationCreation(creationDraft, column, raw); error = null; successMsg = null; } catch (cause) { error = `Vegetation creation input rejected: ${formatError(cause)}`; } }\n\n  function stageCreationSpecies(raw: string) { if (!creationDraft || personalDraft !== null || busy || headerWorkflowBusy) { error = 'An available creation draft without personal metadata entry is required before editing species.'; return; } creationDraft = stageVegetationCreationSpecies(creationDraft, raw); creationChoices = null; error = null; successMsg = null; }\n\n  function reviewCreationSpeciesChoices() { return reviewCreationSpeciesChoicesImpl({ enabled: creationEnabled, proposed: creationDraft, canReview: Boolean(creationDraft && !creationDraft.decision && personalDraft === null && !busy && !headerWorkflowBusy && !draft.locked && capabilitiesReady && speciesReferenceReady && !speciesReferenceBusy && creationSpeciesInvalid), bumpRequest: () => ++speciesChoiceRequest, currentRequest: () => speciesChoiceRequest, getCreationDraft: () => creationDraft, port: { speciesChoiceReads, ListVegetationSpeciesAliases: req => PlotService.ListVegetationSpeciesAliases(req), ListVegetationSpeciesUsers: req => PlotService.ListVegetationSpeciesUsers(req) }, setDecisionBusy: b => { speciesDecisionBusy = b; }, setCreationChoices: c => { creationChoices = c; }, setError: e => { error = e; } }); }\n\n  function chooseCreationSpecies(kind: SpeciesDecisionKind, selected?: string) { try { if (!creationEnabled || !creationDraft || !creationChoices || personalDraft !== null || busy || headerWorkflowBusy || draft.locked || !capabilitiesReady) throw new Error('Review the available unlocked creation entry before selecting a decision.'); creationDraft = chooseVegetationCreationSpecies(creationDraft, creationChoices, kind, selected); creationChoices = null; error = null; successMsg = null; } catch (cause) { error = `Creation species decision failed; draft retained: ${formatError(cause)}`; } }\n\n  function startCreationPersonalSpecies() { try { if (!creationEnabled || !personalSpeciesEnabled || !creationDraft || !creationChoices || !creationSpeciesInvalid || personalDraft !== null || busy || headerWorkflowBusy || draft.locked || !capabilitiesReady || !speciesReferenceReady || speciesReferenceBusy) throw new Error('Review the available unlocked unknown creation code before creating its personal definition.'); personalDraft = beginCreationPersonalSpecies(creationDraft, creationChoices); error = null; successMsg = null; } catch (cause) { error = `Creation personal definition could not start: ${formatError(cause)}`; } }\n\n  function cancelVegetationCreation() { return cancelChildDraftsImpl({ guardBlocked: personalDraft !== null || busy || headerWorkflowBusy, guardMessage: personalDraft !== null ? 'Cancel personal definition entry before cancelling the new-row proposal.' : 'Wait for the current operation before cancelling creation.', clearDrafts: () => { creationDraft = null; creationChoices = null; }, plotNumber: draft.plotNumber, loadChildData, successMessage: savedPersonalCodes.length ? 'Vegetation creation cancelled. No project data or history changed; explicitly saved personal definitions remain available.' : 'Vegetation creation cancelled. No stored data or history changed; current rows reloaded.', reloadErrorMessage: 'Creation cancelled, but rows could not be reloaded. Reopen the plot', setBusy: b => { busy = b; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; }, invalidateCapabilities: () => { capabilitiesReady = false; } }); }\n\n  function saveVegetationCreation() { return saveVegetationCreationImpl({ allowed: Boolean(creationEnabled && creationDraft && personalDraft === null && !busy && !headerWorkflowBusy && !dirty && !draft.locked && capabilitiesReady && original !== null && speciesReferenceReady && !speciesReferenceBusy), proposed: creationDraft, plotNumber: draft.plotNumber, speciesLists, CreateSourceVegetation: (p, r) => PlotService.CreateSourceVegetation(p, r), loadChildData, getVegList: () => vegList, setBusy: b => { busy = b; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; }, clearCreation: () => { creationDraft = null; creationChoices = null; }, invalidateCapabilities: () => { capabilitiesReady = false; } }); }\n\n  function reviewVegetationDeletion(form: string, id: number) { return reviewVegetationDeletionImpl({ enabled: deletionEnabled, blocked: childParentDisabled || childUnsaved, form, id, plotNumber: draft.plotNumber, vegList, sourceRows, deletionReads, bumpRequest: () => ++deletionRequest, currentRequest: () => deletionRequest, getPlotNumber: () => draft.plotNumber, ReviewVegetationDeletion: (p, f, rowId) => PlotService.ReviewVegetationDeletion(p, f, rowId), setDeletionBusy: b => { deletionBusy = b; }, setDeletionReview: r => { deletionReview = r; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; } }); }\n\n  function cancelVegetationDeletion() { return cancelChildDraftsImpl({ guardBlocked: busy || headerWorkflowBusy, guardMessage: 'Wait for the current operation before cancelling deletion review.', clearDrafts: () => { deletionReview = null; }, plotNumber: draft.plotNumber, loadChildData, successMessage: 'Vegetation deletion cancelled. No stored data or history changed; current rows reloaded.', reloadErrorMessage: 'Deletion review cancelled, but rows could not be reloaded. Reopen the plot', setBusy: b => { busy = b; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; }, invalidateCapabilities: () => { capabilitiesReady = false; } }); }\n\n  function confirmVegetationDeletion() { return confirmVegetationDeletionImpl({ allowed: Boolean(deletionEnabled && deletionReview && !busy && !headerWorkflowBusy && !dirty && !draft.locked && capabilitiesReady && original !== null), reviewed: deletionReview, plotNumber: draft.plotNumber, DeleteReviewedVegetation: (p, r) => PlotService.DeleteReviewedVegetation(p, r), loadChildData, setBusy: b => { busy = b; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; }, clearReview: () => { deletionReview = null; }, invalidateCapabilities: () => { capabilitiesReady = false; } }); }\n\n  function stageHeightCell(id: number, col: string, raw: string, form: string) { const res = stageHeightCellImpl({ enabled: heightEditingEnabled, disabled: heightEditingDisabled, childCapabilities, vegList, humusList, mineralList, otherList, plotNumber: draft.plotNumber, heightDrafts, id, column: col, raw, form }); heightDrafts = res.heightDrafts; if (res.error) error = res.error; else successMsg = null; if (res.bumpRevision) childRevision++; }\n\n  function cancelHeightDrafts() { return cancelChildDraftsImpl({ guardBlocked: busy || headerWorkflowBusy, guardMessage: 'Wait for the current operation before cancelling height drafts.', clearDrafts: () => { heightDrafts = {}; }, bumpRevision: () => { childRevision++; }, plotNumber: draft.plotNumber, loadChildData, successMessage: 'Height drafts cancelled. Stored data and history were unchanged; current rows reloaded.', reloadErrorMessage: 'Height drafts cancelled, but current rows could not be reloaded. Reopen the plot', setBusy: b => { busy = b; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; }, invalidateCapabilities: () => { capabilitiesReady = false; } }); }\n\n  function saveHeightDrafts() { const updates = heightUpdates(heightDrafts), notices = heightSourceNotices(heightDrafts, vegList); return saveChildDraftsImpl({ disabled: !heightEditingEnabled || heightEditingDisabled, guardMessage: 'Save a clean, unlocked header before saving height drafts.', hasUpdates: updates.length > 0, noChangeMessage: 'No height values changed.', clearEmpty: () => { heightDrafts = {}; }, commit: () => PlotService.UpdateVegetationNumbers(draft.plotNumber, vegetationNumberUpdates(heightDrafts)), clearOnCommit: () => { heightDrafts = {}; }, plotNumber: draft.plotNumber, loadChildData, buildSuccessMessage: () => `Saved ${updates.length} height/cover row drafts.${notices.length ? ' ' + notices.join(' ') : ''}`, committedRefreshPrefix: 'Height changes committed, but refresh failed. Reopen the plot before editing', failedPrefix: 'Height save failed; drafts retained', setBusy: b => { busy = b; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; }, invalidateCapabilities: () => { capabilitiesReady = false; } }); }\n\n  function stageOtherCell(id: number, col: string, raw: OtherValue) { const res = stageOtherCellImpl({ disabled: otherEditingDisabled, childCapabilities, otherList, plotNumber: draft.plotNumber, otherDrafts, id, column: col, raw }); otherDrafts = res.otherDrafts; if (res.error) error = res.error; else { successMsg = null; if (res.clearOtherError && error?.startsWith('Other ')) error = null; } if (res.bumpRevision) childRevision++; }\n\n  function cancelOtherDrafts() { return cancelChildDraftsImpl({ guardBlocked: busy || headerWorkflowBusy, guardMessage: 'Wait for the current operation before cancelling Other drafts.', clearDrafts: () => { otherDrafts = {}; }, bumpRevision: () => { childRevision++; }, plotNumber: draft.plotNumber, loadChildData, successMessage: 'Other drafts cancelled. Stored data and history were unchanged; current rows reloaded.', reloadErrorMessage: 'Other drafts cancelled, but current rows could not be reloaded. Reopen the plot', setBusy: b => { busy = b; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; }, invalidateCapabilities: () => { capabilitiesReady = false; } }); }\n\n  function saveOtherDrafts() { const updates = otherUpdates(otherDrafts); return saveChildDraftsImpl({ disabled: otherEditingDisabled, guardMessage: 'Save a clean, unlocked header before saving Other drafts.', hasUpdates: updates.length > 0, noChangeMessage: 'No Other values changed.', clearEmpty: () => { otherDrafts = {}; }, commit: () => PlotService.UpdateOtherRecords(draft.plotNumber, updates), clearOnCommit: () => { otherDrafts = {}; }, plotNumber: draft.plotNumber, loadChildData, buildSuccessMessage: () => `Saved ${updates.length} Other row drafts.`, committedRefreshPrefix: 'Other changes committed, but refresh failed. Reopen the plot before editing', failedPrefix: 'Other save failed; drafts retained', setBusy: b => { busy = b; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; }, invalidateCapabilities: () => { capabilitiesReady = false; } }); }\n\n  async function loadSoilSuggestions() { if (ordinarySoilUnavailable || !soilEditingEnabled || soilReferenceBusy) return; return executeSuggestionLoad({ enabled: !ordinarySoilUnavailable && soilEditingEnabled, busy: soilReferenceBusy, missingMessage: 'Soil reference metadata was not returned.', unavailablePrefix: 'Soil reference suggestions unavailable', currentRequest: () => referenceRequest, fetchRows: () => referenceReads.track(PlotService.ListSoilSuggestions()), setBusy: b => { soilReferenceBusy = b; }, setReady: r => { soilReferenceReady = r; }, setError: e => { soilReferenceError = e; }, setSuggestions: r => { soilSuggestions = r; } }); }\n\n  function stageSoilCell(kind: SoilKind, id: number, col: string, raw: string) { if (soilEditingDisabled) { error = 'Soil draft failed: Error: Soil editing is unavailable while loading, locked, busy or another draft is unsaved.'; childRevision++; return; } const res = stageSoilCellImpl({ disabled: soilEditingDisabled, childCapabilities, humusList, mineralList, plotNumber: draft.plotNumber, soilDrafts, kind, id, column: col, raw }); soilDrafts = res.soilDrafts; if (res.error) error = res.error; else { successMsg = null; if (res.clearSoilError && error?.startsWith('Soil ')) error = null; } if (res.bumpRevision) childRevision++; }\n\n  function cancelSoilDrafts() { return cancelChildDraftsImpl({ guardBlocked: busy || headerWorkflowBusy, guardMessage: 'Wait for the current operation before cancelling soil drafts.', clearDrafts: () => { soilDrafts = {}; }, bumpRevision: () => { childRevision++; }, plotNumber: draft.plotNumber, loadChildData, successMessage: 'Soil drafts cancelled. Stored data and history were unchanged; current rows reloaded.', reloadErrorMessage: 'Soil drafts cancelled, but current rows could not be reloaded. Reopen the plot', setBusy: b => { busy = b; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; }, invalidateCapabilities: () => { capabilitiesReady = false; } }); }\n\n  function saveSoilDrafts() { if (soilEditingDisabled) { error = 'Save a clean, unlocked header with available references before saving soil drafts.'; return Promise.resolve(); } const updates = soilUpdates(soilDrafts, mineralList); return saveChildDraftsImpl({ disabled: soilEditingDisabled, guardMessage: 'Save a clean, unlocked header with available references before saving soil drafts.', hasUpdates: updates.length > 0, noChangeMessage: 'No soil values changed.', clearEmpty: () => { soilDrafts = {}; }, commit: () => PlotService.UpdateSoilRecords(draft.plotNumber, updates), clearOnCommit: () => { soilDrafts = {}; }, plotNumber: draft.plotNumber, loadChildData, buildSuccessMessage: () => `Saved ${updates.length} Humus/Mineral row drafts.`, committedRefreshPrefix: 'Soil changes committed, but refresh failed. Reopen the plot before editing', failedPrefix: 'Soil save failed; drafts retained', setBusy: b => { busy = b; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; }, invalidateCapabilities: () => { capabilitiesReady = false; } }); }\n\n  async function loadAttributeSuggestions() { return executeSuggestionLoad({ enabled: attributeEditingEnabled, busy: attributeReferenceBusy, missingMessage: 'Vegetation attribute reference metadata was not returned.', unavailablePrefix: 'Vegetation attribute references unavailable', currentRequest: () => referenceRequest, fetchRows: () => referenceReads.track(PlotService.ListVegetationAttributeSuggestions()), setBusy: b => { attributeReferenceBusy = b; }, setReady: r => { attributeReferenceReady = r; }, setError: e => { attributeReferenceError = e; }, setSuggestions: r => { attributeSuggestions = r; } }); }\n\n  function stageAttributeCell(id: number, col: string, raw: string) { const res = stageAttributeCellImpl({ disabled: attributeEditingDisabled, childCapabilities, vegList, plotNumber: draft.plotNumber, attributeDrafts, id, column: col, raw }); attributeDrafts = res.attributeDrafts; if (res.error) error = res.error; else { successMsg = null; if (res.clearAttrError && error?.startsWith('Vegetation attribute ')) error = null; } if (res.bumpRevision) childRevision++; }\n\n  function cancelAttributeDrafts() { return cancelChildDraftsImpl({ guardBlocked: busy || headerWorkflowBusy, guardMessage: 'Wait for the current operation before cancelling attribute drafts.', clearDrafts: () => { attributeDrafts = {}; }, bumpRevision: () => { childRevision++; }, plotNumber: draft.plotNumber, loadChildData, successMessage: 'Vegetation attribute drafts cancelled. Stored data and history were unchanged; current rows reloaded.', reloadErrorMessage: 'Vegetation attribute drafts cancelled, but rows could not be reloaded. Reopen the plot', setBusy: b => { busy = b; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; }, invalidateCapabilities: () => { capabilitiesReady = false; } }); }\n\n  function saveAttributeDrafts() { const updates = vegetationAttributeUpdates(attributeDrafts); return saveChildDraftsImpl({ disabled: attributeEditingDisabled, guardMessage: 'Save a clean, unlocked header with available references before saving attribute drafts.', hasUpdates: updates.length > 0, noChangeMessage: 'No vegetation attribute values changed.', clearEmpty: () => { attributeDrafts = {}; }, commit: () => PlotService.UpdateVegetationAttributes(draft.plotNumber, updates), clearOnCommit: () => { attributeDrafts = {}; }, plotNumber: draft.plotNumber, loadChildData, buildSuccessMessage: () => `Saved ${updates.length} vegetation attribute row drafts.`, committedRefreshPrefix: 'Vegetation attributes committed, but refresh failed. Reopen the plot before editing', failedPrefix: 'Vegetation attribute save failed; drafts retained', setBusy: b => { busy = b; }, setError: e => { error = e; }, setSuccess: s => { successMsg = s; }, invalidateCapabilities: () => { capabilitiesReady = false; } }); }\n\n  async function editSourceChild(name: string, id: number, column: string, raw: string) {\n    if (ordinaryVegetationUnavailable && name.startsWith('SubVeg')) { error = ordinaryVegetationUnavailable; return; }\n    const soilUnavailable = ordinarySoilUnavailable ?? (typeof historicalSoilUnavailable !== 'undefined' ? historicalSoilUnavailable : null);\n    if (soilUnavailable && (name === 'SoilHumusXL' || name === 'SoilMineralXL')) { error = soilUnavailable; return; }\n    try { if (name.startsWith('SubVeg') && column.toLowerCase() === 'species') throw new Error('Species requires the source-list draft workflow; unrestricted source-grid edits are unavailable.'); await childOperation(buildDirectSourceChildWrite(name, id, column, raw, { vegList, humusList, mineralList, otherList }, PlotService)); } catch (cause) { error = `Child input failed: ${formatError(cause)}`; }\n  }\n\n  function markDirty() { dirty = true; successMsg = null; }\n\n  function headerValidationError(message: string) { return computeHeaderValidationError(message, headerValidation); }\n\n  function validateHeader(key: string, message: string | null) { const next = { ...headerValidation }, previous = next[key]; if (previous !== undefined && (error === previous || error === headerValidationError(previous) || error === invalidHeaderMessage)) error = null; if (message === null) delete next[key]; else next[key] = message; headerValidation = next; }\n\n  async function save() {\n    const blocked = firstMatch<string>([[() => siviSourceAuthorityUnknown, 'Read owned ProjectID choices to observe the source preference outcome before saving.'], [() => busy || headerWorkflowBusy, 'Wait for the current operation to finish before saving.'], [() => siviDeletionPending || siviRestorationPending || siviCreationUndoPending, 'Confirm deletion/restoration/creation Undo explicitly in its reviewed panel or discard the unsubmitted review; ordinary Save never performs it.'], [() => codeCheckOpen, 'Save replacements or personal metadata explicitly, then close species-code review; ordinary plot Save never applies them.'], [() => metadataOpen, 'Save or Undo metadata explicitly, then close metadata review; ordinary plot Save never applies it.'], [() => profileReviewBlocked, 'Save or Undo profile drafts explicitly; ordinary plot Save never writes profile rules.'], [() => personalDraft !== null, 'Save the personal definition explicitly or Cancel its entry; ordinary plot Save never writes the user database.'], [() => deletionReview !== null, 'Confirm reviewed vegetation deletion explicitly or Cancel deletion review; ordinary Save never deletes rows.']]);\n    if (blocked) { error = blocked; return; }\n    const draftHandler = firstMatch<() => Promise<void | boolean>>([[() => creationDraft !== null, () => saveVegetationCreation()], [() => siviCreationPending, () => siviCreationOperation('save')], [() => siviParentActionUnsaved, () => siviParentActionOperation('save')], [() => siviProjectAssignmentUnsaved, () => siviProjectAssignmentOperation('save')], [() => siviParentWriteUnsaved, () => siviParentWriteOperation('save')], [() => siviParentSharedUnsaved, () => siviParentSharedOperation('save')], [() => siviUnsaved, () => siviOperation('save')], [() => siviCoverUnsaved, () => siviCoverOperation('save')], [() => siviCombinedUnsaved, () => siviCombinedOperation('save')], [() => siviCollectedUnsaved, () => siviCollectedOperation('save')], [() => siviSpeciesUnsaved, () => siviSpeciesOperation('save')], [() => siviIdentityUnsaved, () => siviIdentityOperation('save')], [() => heightUnsaved, () => saveHeightDrafts()], [() => otherUnsaved, () => saveOtherDrafts()], [() => soilUnsaved, () => saveSoilDrafts()], [() => attributeUnsaved, () => saveAttributeDrafts()], [() => collectedUnsaved, () => saveCollectedDrafts()], [() => speciesUnsaved, () => saveSpeciesDrafts()]]);\n    if (draftHandler) { await draftHandler(); return; }\n    const invalid = container.querySelector<HTMLInputElement>('.header-editor input:invalid');\n    if (invalid) { invalid.reportValidity(); error = invalidHeaderMessage; return; }\n    const validation = Object.values(headerValidation)[0];\n    if (validation) { error = headerValidationError(validation); return; }\n    if (!capabilitiesReady || draft.locked) { error = 'The header is not available for saving.'; return; }\n    if (!draft.plotNumber.trim()) { error = 'Plot Number is required.'; return; }\n    busy = true; error = null; successMsg = null;\n    try {\n      const payload = $state.snapshot({ ...draft, locked: capabilities.locked === true && draft.locked });\n      if (original) {\n        const baseline = $state.snapshot(original);\n        await PlotService.UpdatePlot({ ...payload, original: baseline } as FS882Header);\n      } else {\n        await PlotService.CreatePlot(payload);\n      }\n      original = JSON.parse(JSON.stringify(draft)); activeLayerDepthRaw = null; workingUnitSession.plot = draft.plotNumber; dirty = false; headerValidation = {}; successMsg = `Plot ${draft.plotNumber} saved successfully.`;\n      lastNotifiedSuccessMsg = successMsg;\n      if (typeof notifications !== 'undefined') notifications.success?.(`Plot ${draft.plotNumber} saved`, 'Saved to project file.', { category: 'entry', source: 'FS882 Form', contextTag: draft.plotNumber ? `Plot ${draft.plotNumber}` : undefined });\n      await loadChildData(draft.plotNumber);\n      if (siviParentSession?.view().original || siviParentSession?.view().error) await refreshSIVIParent(draft.plotNumber, [siviParentWriteSession, siviParentActionSession, siviProjectAssignmentSession, siviParentSharedSession]);\n      if (onSaved) await onSaved(draft.plotNumber);\n    } catch (e) {\n      const rawMsg = formatError(e);\n      const conflict = rawMsg.includes('plot changed since it was loaded') || rawMsg.includes('no longer exists; reload before saving');\n      error = conflict ? rawMsg.replace(/^(?:(?:RuntimeError|Error):\\s*)+/, '') : rawMsg;\n      if (conflict && typeof notifications !== 'undefined') {\n        notifications.error?.(`Plot ${draft.plotNumber} save conflict`, error, { category: 'entry', source: 'FS882 Form', contextTag: draft.plotNumber ? `Plot ${draft.plotNumber}` : undefined });\n      }\n    } finally { busy = false; }\n  }\n\n  function getCloseState(): EditorCloseState {\n    if (twoPageVegetationBusy || twoPageVegetationBlocked) return { unsaved: true, busy: twoPageVegetationBusy, blocked: true, canSave: false, error, saveReason: 'Finish retained linked-vegetation drafts/operations, recover unknown outcomes and acknowledge receipts before parent Save, Lock or close.' };\n    if (twoPageSoilBusy || twoPageSoilBlocked) return { unsaved: true, busy: twoPageSoilBusy, blocked: true, canSave: false, error, saveReason: 'Finish retained linked-soil drafts/operations, recover unknown outcomes and acknowledge receipts before parent Save, Lock or close.' };\n    if (pictureMetadataPending && pictureMetadataClose) return { ...pictureMetadataClose, canSave: false, saveReason: pictureMetadataClose.blocked || pictureMetadataClose.busy ? pictureMetadataClose.saveReason : 'Save picture metadata explicitly or discard its draft before parent Save, Lock or close.' };\n    if (siviParentSourceView?.authorityUnknown) return { unsaved: true, busy: siviParentSourceView.busy, blocked: true, canSave: false, saveReason: 'Reload owned ProjectID choices to observe the source preference outcome before saving or closing.', error: siviParentSourceView.error ?? 'ProjectID source preference outcome is unknown.' };\n    const lifecycle = siviCreationUndoPending && siviCreationUndoClose?.blocked ? siviCreationUndoClose : siviDeletionPending ? siviDeletionClose : siviRestorationPending ? siviRestorationClose : siviCreationUndoPending ? siviCreationUndoClose : null;\n    if (lifecycle) return { ...lifecycle, canSave: false, busy: busy || headerWorkflowBusy || lifecycle.busy, saveReason: lifecycle.blocked || lifecycle.busy ? lifecycle.saveReason : 'Finish source deletion/restoration/creation Undo explicitly or discard its unsubmitted review before parent Save, Lock or close.' };\n    if (typeof twoPageRevision !== 'undefined') void twoPageRevision;\n    if (twoPageOpen) return twoPageEditor?.getCloseState() ?? { unsaved: true, busy: true, blocked: true, canSave: false, error, saveReason: 'Wait for two-page field review, then finish and close it explicitly.' };\n    if (environmentSUOpen) return environmentSUEditor?.getCloseState() ?? { unsaved: true, busy: true, canSave: false, error, saveReason: 'Wait for SU transfer review, then finish or dismiss and close it explicitly.' };\n    if (profileReviewBlocked) return profileEditor?.getCloseState() ?? { unsaved: true, busy: true, canSave: false, error, saveReason: 'Finish profile rules explicitly before saving or closing the plot.' };\n    if (metadataOpen) return metadataEditor?.getCloseState() ?? { unsaved: true, busy: true, canSave: false, error, saveReason: 'Wait for metadata review, then finish or close it before saving or closing the plot.' };\n    if (codeCheckOpen) return codeCheckEditor?.getCloseState() ?? { unsaved: true, busy: true, canSave: false, error, saveReason: 'Wait for species-code review to load, then finish or close it before saving or closing the plot.' };\n    if (siviCreationPending && siviCreationClose) return { ...siviCreationClose, busy: busy || headerWorkflowBusy || siviCreationClose.busy, canSave: !siviCreationEditingDisabled && siviCreationClose.canSave, saveReason: siviCreationEditingDisabled ? 'Finish conflicting work before creating the retained SIVI row.' : siviCreationClose.saveReason, error: siviCreationClose.error ?? error };\n    const invalid = Object.keys(headerValidation).length > 0 || heightInvalid.length > 0 || otherInvalid.length > 0 || soilInvalid.length > 0 || attributeInvalid.length > 0 || speciesInvalid.length > 0 || deletionReview !== null || creationInvalid.length > 0;\n    const invalidChild = Boolean(container?.querySelector('.source-child input:invalid'));\n    const saveReason = computeSaveReason({ busy, headerWorkflowBusy, capabilitiesReady, locked: draft.locked, siviParentActionUnsaved, siviParentActionClose, siviParentWriteUnsaved, siviParentWriteClose, siviParentSharedUnsaved, siviParentSharedClose, siviProjectAssignmentUnsaved, siviProjectAssignmentClose, siviUnsaved, siviClose, siviCoverUnsaved, siviCoverClose, siviCombinedUnsaved, siviCombinedClose, siviCollectedUnsaved, siviCollectedClose, siviSpeciesUnsaved, siviSpeciesClose, siviIdentityUnsaved, siviIdentityClose, hasPersonalDraft: personalDraft !== null, hasDeletionReview: deletionReview !== null, creationInvalidCount: creationInvalid.length, hasCreationDraft: creationDraft !== null, speciesReferenceReady, speciesReferenceBusy, hasNewChild: newChild !== null, invalidChild, otherInvalidCount: otherInvalid.length, soilInvalidCount: soilInvalid.length, soilUnsaved, soilReferenceReady, soilReferenceBusy, attributeInvalidCount: attributeInvalid.length, attributeUnsaved, attributeReferenceReady, attributeReferenceBusy, speciesInvalidCount: speciesInvalid.length, speciesUnsaved, invalid, plotNumber: draft.plotNumber });\n    return { unsaved: dirty || childUnsaved || invalid || newChild !== null || invalidChild, busy: busy || headerWorkflowBusy, blocked: [siviClose, siviCoverClose, siviCombinedClose, siviCollectedClose, siviSpeciesClose, siviIdentityClose, siviParentWriteClose, siviParentActionClose, siviProjectAssignmentClose, siviParentSharedClose].some(c => c?.blocked ?? false), canSave: saveReason === '', saveReason, error };\n  }\n\n  async function saveForClose(): Promise<boolean> {\n    if (twoPageOpen && typeof twoPageEditor?.saveForClose === 'function') return await twoPageEditor.saveForClose();\n    const state = getCloseState(); if (!state.canSave) { error = state.saveReason; return false; } await save(); return !dirty && !childUnsaved && Object.keys(headerValidation).length === 0 && error === null;\n  }\n\n  function undo() {\n    if (twoPageOpen) { twoPageEditor?.undo(); return; }\n    if (environmentSUOpen) { environmentSUEditor?.undo(); return; }\n    if (busy || headerWorkflowBusy) { error = 'Wait for the current operation to finish before undoing changes.'; return; }\n    const undoHandler = firstMatch<() => void>([[() => codeCheckOpen, () => codeCheckEditor?.undo()], [() => metadataOpen, () => metadataEditor?.undo()], [() => profileReviewBlocked, () => profileEditor?.undo()], [() => personalDraft !== null, () => cancelPersonalSpecies()], [() => deletionReview !== null, () => void cancelVegetationDeletion()], [() => creationDraft !== null, () => void cancelVegetationCreation()], [() => siviDeletionPending, () => void siviLifecycleOperation('deletion', 'undo')], [() => siviRestorationPending, () => void siviLifecycleOperation('restoration', 'undo')], [() => siviCreationUndoPending, () => void siviCreationUndoOperation('discard')], [() => siviCreationPending, () => void siviCreationOperation('undo')], [() => siviParentActionUnsaved, () => void siviParentActionOperation('undo')], [() => siviProjectAssignmentUnsaved, () => void siviProjectAssignmentOperation('undo')], [() => siviParentWriteUnsaved, () => void siviParentWriteOperation('undo')], [() => siviParentSharedUnsaved, () => void siviParentSharedOperation('undo')], [() => siviUnsaved, () => void siviOperation('undo')], [() => siviCoverUnsaved, () => void siviCoverOperation('undo')], [() => siviCombinedUnsaved, () => void siviCombinedOperation('undo')], [() => siviCollectedUnsaved, () => void siviCollectedOperation('undo')], [() => siviSpeciesUnsaved, () => void siviSpeciesOperation('undo')], [() => siviIdentityUnsaved, () => void siviIdentityOperation('undo')], [() => heightUnsaved, () => void cancelHeightDrafts()], [() => otherUnsaved, () => void cancelOtherDrafts()], [() => soilUnsaved, () => void cancelSoilDrafts()], [() => attributeUnsaved, () => void cancelAttributeDrafts()], [() => collectedUnsaved, () => void cancelCollectedDrafts()], [() => speciesUnsaved, () => void cancelSpeciesDrafts()]]);\n    if (undoHandler) { undoHandler(); return; }\n    draft = original ? JSON.parse(JSON.stringify(original)) : newDraft();\n    activeLayerDepthRaw = null; dirty = false; headerValidation = {}; error = null;\n    headerRevision++;\n    successMsg = 'Changes undone.';\n    lastNotifiedSuccessMsg = successMsg;\n    if (typeof notifications !== 'undefined') notifications.success?.('Draft changes undone', draft.plotNumber ? `Plot ${draft.plotNumber} restored to last saved state.` : 'Draft reset.', { category: 'entry', source: 'FS882 Form', contextTag: draft.plotNumber ? `Plot ${draft.plotNumber}` : undefined });\n  }\n\n  async function toggleLock() {\n    const blocked = firstMatch<string>([[() => siviDeletionPending || siviRestorationPending || siviCreationUndoPending, 'Finish or resolve source deletion/restoration/creation Undo before changing the plot lock.'], [() => siviSourceAuthorityUnknown, 'Read owned ProjectID choices to observe the source preference outcome before changing the plot lock.'], [() => busy || headerWorkflowBusy, 'Wait for the current operation to finish before changing the plot lock.'], [() => codeCheckOpen, 'Finish or close species-code review before changing the plot lock.'], [() => metadataOpen, 'Finish or close metadata review before changing the plot lock.'], [() => profileReviewBlocked, 'Finish profile drafts before changing the plot lock.'], [() => personalDraft !== null, 'Save the personal definition explicitly or Cancel its entry before changing the plot lock.'], [() => creationDraft !== null, 'Save or Cancel vegetation creation before changing the plot lock.'], [() => deletionReview !== null, 'Confirm or Cancel vegetation deletion review before changing the plot lock.'], [() => heightUnsaved, 'Save or Cancel height drafts before changing the plot lock.'], [() => siviParentWriteUnsaved, 'Save or explicitly Undo SIVI parent drafts/recovery before changing the plot lock.'], [() => siviParentSharedUnsaved, 'Save or explicitly Undo shared SIVI drafts/recovery before changing the plot lock.'], [() => siviParentActionUnsaved, 'Save or explicitly Undo SIVI source-action drafts/recovery before changing the plot lock.'], [() => siviProjectAssignmentUnsaved, 'Save or explicitly Undo ProjectID selection/recovery before changing the plot lock.'], [() => siviUnsaved, 'SIVI heights or unresolved acknowledgements must be saved or explicitly undone before changing the plot lock.'], [() => siviCoverUnsaved, 'SIVI covers or unresolved acknowledgements must be saved or explicitly undone before changing the plot lock.'], [() => siviCombinedUnsaved, 'Combined SIVI drafts or unresolved acknowledgements must be saved or explicitly undone before changing the plot lock.'], [() => siviCollectedUnsaved, 'SIVI Collected or unresolved acknowledgements must be saved or explicitly undone before changing the plot lock.'], [() => siviSpeciesUnsaved, 'SIVI Species or unresolved acknowledgements must be saved or explicitly undone before changing the plot lock.'], [() => siviIdentityUnsaved, 'SIVI IDs or unresolved acknowledgements must be saved or explicitly undone before changing the plot lock.'], [() => siviCreationPending, 'SIVI creation drafts or unknown acknowledgements must be resolved before changing the plot lock.'], [() => otherUnsaved, 'Save or Cancel Other drafts before changing the plot lock.'], [() => soilUnsaved, 'Save or Cancel soil drafts before changing the plot lock.'], [() => attributeUnsaved, 'Save or Cancel vegetation attribute drafts before changing the plot lock.'], [() => collectedUnsaved, 'Save or Cancel Collected drafts before changing the plot lock.'], [() => speciesUnsaved, 'Save or Cancel species drafts before changing the plot lock.']]);\n    if (blocked) { error = blocked; return; }\n    if (!draft.locked && dirty) { await save(); if (dirty) return; }\n    draft.locked = !draft.locked;\n    if (typeof notifications !== 'undefined') notifications.success?.(draft.locked ? `Plot ${draft.plotNumber || ''} locked`.trim() : `Plot ${draft.plotNumber || ''} unlocked`.trim(), draft.locked ? 'Form is now protected in read-only mode.' : 'Form is now unlocked for editing.', { category: 'entry', source: 'FS882 Form', contextTag: draft.plotNumber ? `Plot ${draft.plotNumber}` : undefined });\n  }\n\n  function childOperation(operation: () => Promise<void>) { return childOperationImpl({ busy, headerWorkflowBusy, capabilitiesReady, locked: draft.locked, hasOriginal: Boolean(original), plotNumber: draft.plotNumber, dirty, childUnsaved, setBusy: b => { busy = b; }, setError: e => { error = e; }, appendError: s => { error = (error ?? '') + s; }, setSuccess: s => { successMsg = s; }, invalidateCapabilities: () => { capabilitiesReady = false; }, loadChildData }, operation); }\n\n  async function runCopyPlot() {\n    if (!original || !onCopyPlotToNumber || managePlotBusy) return;\n    managePlotBusy = true; error = null;\n    try { await onCopyPlotToNumber(original.plotNumber, copyPlotTarget); managePlotOpen = false; }\n    catch (cause) { error = String(cause instanceof Error ? cause.message : cause); }\n    finally { managePlotBusy = false; }\n  }\n\n  async function runRemovePlot() {\n    if (!original || !onRemovePlotAction || managePlotBusy) return;\n    managePlotBusy = true; error = null;\n    try { await onRemovePlotAction(original.plotNumber, canUndoPlotDelete ? '' : removeCleanProject); managePlotOpen = false; }\n    catch (cause) { error = String(cause instanceof Error ? cause.message : cause); }\n    finally { managePlotBusy = false; }\n  }\n";

let cachedFs882Js = null;
let cachedFs882Deps = null;
let cachedTwoPageDeps = null;

function getTranspiledFs882() {
  if (cachedFs882Js === null) {
    cachedFs882Js = ts.transpileModule(FS882_VM_TS, {
      compilerOptions: {
        module: ts.ModuleKind.CommonJS,
        target: ts.ScriptTarget.ES2022,
        alwaysStrict: false,
      },
    }).outputText;
  }
  return cachedFs882Js;
}

const SESSION_HEAVY_NAMES = new Set(['load', 'openExternalSUEnvironment']);

function getFs882Deps(loadTypeScript, names = []) {
  const needsSessions = names.some((n) => SESSION_HEAVY_NAMES.has(n));
  if (!needsSessions) {
    if (!cachedFs882Deps?.light) {
      const light = {};
      for (const m of ['entry/enterNavigation.ts', 'entry/ordinaryEditor.ts', 'entry/formValidationSummary.ts']) {
        try { Object.assign(light, loadTypeScript(m)); } catch {}
      }
      cachedFs882Deps = { ...(cachedFs882Deps ?? {}), light };
    }
    return cachedFs882Deps.light;
  }
  if (cachedFs882Deps?.full) return cachedFs882Deps.full;
  const mods = [
    'entry/enterNavigation.ts',
    'entry/ordinaryEditor.ts',
    'entry/formValidationSummary.ts',
    'entry/siviParentSharedSession.ts',
    'entry/siviParentReadSession.ts',
    'entry/siviParentSourceSession.ts',
    'entry/siviParentWriteSession.ts',
    'entry/siviParentActionWriteSession.ts',
    'entry/siviProjectAssignmentSession.ts',
    'entry/siviHeightSession.ts',
    'entry/siviCoverSession.ts',
    'entry/siviCombinedSession.ts',
    'entry/siviCollectedSession.ts',
    'entry/siviSpeciesSession.ts',
    'entry/siviIdentitySession.ts',
    'classification/externalSUEnvironment.ts',
  ];
  const merged = {};
  for (const m of mods) {
    try {
      Object.assign(merged, loadTypeScript(m));
    } catch {}
  }
  cachedFs882Deps = { ...(cachedFs882Deps ?? {}), full: merged };
  return merged;
}

function createFs882VmDefaults(loadTypeScript, serverReads, fs882Helpers, names = []) {
  const deps = getFs882Deps(loadTypeScript, names);
  const ReadRequests = serverReads.ReadRequests;
  return {
    ...deps,
    ...fs882Helpers,
    crypto,
    window: { confirm: () => true },
    tick: async () => {},
    container: { querySelector: () => null },
    AuditRestoreAction: { AuditRestoreRetain: 'retain', AuditRestorePrune: 'prune' },
    PlotService: {},
    ContextService: {},
    PlotEntryService: {},
    $projectState: null,
    contextId: '',
    siviContextId: '',
    siviStandalone: false,
    siviStandaloneEnabled: true,
    siviParentReviewEnabled: true,
    siviParentEditingEnabled: true,
    siviParentActionEditingEnabled: true,
    siviProjectAssignmentEnabled: true,
    siviParentSharedEnabled: true,
    siviParentReferenceEnabled: true,
    siviHeightEnabled: true,
    siviCoverEnabled: true,
    siviCombinedEnabled: true,
    siviCollectedEnabled: true,
    siviSpeciesEnabled: true,
    siviIdentityEnabled: true,
    siviChildSourceNoticesEnabled: true,
    siviCreationEnabled: true,
    siviCreationUndoEnabled: true,
    siviDeletionEnabled: true,
    siviRestorationEnabled: true,
    soilEditingEnabled: true,
    attributeEditingEnabled: true,
    speciesEditingEnabled: true,
    vegetationCreationEnabled: true,
    vegetationDeletionEnabled: true,
    collectedEditingEnabled: true,
    heightEditingEnabled: true,
    otherEditingEnabled: true,
    metadataEnabled: true,
    codeCheckEnabled: true,
    twoPageReviewEnabled: true,
    twoPageCommonReviewEnabled: true,
    twoPageEntryReviewEnabled: true,
    environmentSUEnabled: true,
    siteUnitEnvironmentEnabled: true,
    externalSUEnvironmentEnabled: true,
    sourceEnterEnabled: true,
    reads: new ReadRequests(),
    referenceReads: new ReadRequests(),
    speciesReads: new ReadRequests(),
    speciesReferenceReads: new ReadRequests(),
    speciesChoiceReads: new ReadRequests(),
    deletionReads: new ReadRequests(),
    siviReads: new ReadRequests(),
    siviCoverReads: new ReadRequests(),
    siviCombinedReads: new ReadRequests(),
    siviCollectedReads: new ReadRequests(),
    siviSpeciesReads: new ReadRequests(),
    siviIdentityReads: new ReadRequests(),
    siviParentReads: new ReadRequests(),
    siviParentSourceReads: new ReadRequests(),
    siviParentWriteReads: new ReadRequests(),
    siviParentActionReads: new ReadRequests(),
    siviProjectAssignmentReads: new ReadRequests(),
    siviParentSharedReads: new ReadRequests(),
    busy: false,
    headerWorkflowBusy: false,
    otherHeaderWorkflowBusy: false,
    capabilitiesReady: true,
    capabilities: {},
    masterAllowed: false,
    dirty: false,
    headerValidation: {},
    invalidHeaderMessage: 'Correct the invalid header input before saving.',
    error: null,
    successMsg: null,
    lastNotifiedSuccessMsg: null,
    onSaved: undefined,
    draft: fs882Helpers.newEmptyFS882Draft ? fs882Helpers.newEmptyFS882Draft() : { plotNumber: '', locked: false },
    original: null,
    activeLayerDepthRaw: null,
    workingUnitSession: { mode: null, plot: '' },
    loadRequest: 0,
    referenceRequest: 0,
    speciesRequest: 0,
    speciesReferenceRequest: 0,
    speciesChoiceRequest: 0,
    deletionRequest: 0,
    subEditorGeneration: 0,
    headerRevision: 0,
    childRevision: 0,
    activeTab: 'site',
    extendedShrubs: false,
    vegetationMode: 'initial',
    fieldCardModalOpen: false,
    fieldCardSplitOpen: false,
    twoPageOpen: false,
    twoPageScope: 'extra',
    twoPageEntryInitialForm: 'FS882-8x6XL',
    twoPageBusy: false,
    twoPageProject: null,
    twoPageRevision: 0,
    twoPageSessions: new Map(),
    twoPageCommonSessions: new Map(),
    twoPageEntrySessions: new Map(),
    twoPageEditor: undefined,
    environmentSUOpen: false,
    environmentSUDirection: 'forward',
    environmentSUEditor: undefined,
    separateSUSelected: false,
    profileReviewOpen: false,
    profileReviewBusy: false,
    profileReviewBlocked: false,
    profileEditor: undefined,
    metadataOpen: false,
    metadataBusy: false,
    metadataEditor: undefined,
    codeCheckOpen: false,
    codeCheckBusy: false,
    codeCheckEditor: undefined,
    pictureBusy: false,
    pictureMetadataPending: false,
    pictureMetadataClose: null,
    vegList: [],
    humusList: [],
    mineralList: [],
    otherList: [],
    auditList: [],
    childCapabilities: { Veg: {}, Humus: {}, Mineral: {}, Other: {} },
    vegetationReadUnavailable: null,
    historicalSoilUnavailable: null,
    ordinarySoilUnavailable: null,
    ordinaryVegetationUnavailable: null,
    heightDrafts: {},
    otherDrafts: {},
    soilDrafts: {},
    attributeDrafts: {},
    collectedDrafts: {},
    speciesDrafts: {},
    speciesChoices: {},
    speciesLists: {},
    deletionReview: null,
    deletionBusy: false,
    creationDraft: null,
    creationChoices: null,
    personalDraft: null,
    savedPersonalCodes: [],
    speciesDecisionBusy: false,
    newChild: null,
    soilSuggestions: [],
    soilReferenceReady: true,
    soilReferenceBusy: false,
    soilReferenceError: null,
    attributeSuggestions: [],
    attributeReferenceReady: true,
    attributeReferenceBusy: false,
    attributeReferenceError: null,
    speciesReferenceReady: true,
    speciesReferenceBusy: false,
    speciesReferenceError: null,
    moistureList: [],
    nutrientList: [],
    mesoSlopeList: [],
    surfaceShapeList: [],
    showSpeciesModal: false,
    speciesSearchQuery: '',
    speciesSearchResults: [],
    searchingSpecies: false,
    heightUnsaved: false,
    heightInvalid: [],
    otherUnsaved: false,
    otherInvalid: [],
    soilUnsaved: false,
    soilInvalid: [],
    attributeUnsaved: false,
    attributeInvalid: [],
    collectedUnsaved: false,
    speciesUnsaved: false,
    speciesInvalid: [],
    creationInvalid: [],
    childParentDisabled: false,
    childUnsaved: false,
    nonParentChildUnsaved: false,
    childEditingDisabled: false,
    soilEditingDisabled: false,
    otherEditingDisabled: false,
    attributeEditingDisabled: false,
    speciesEditingDisabled: false,
    collectedEditingDisabled: false,
    heightEditingDisabled: false,
    creationEditingDisabled: false,
    deletionEditingDisabled: false,
    headerInputsDisabled: false,
    siviParentSession: null,
    siviParentSourceSession: null,
    siviParentWriteSession: null,
    siviParentActionSession: null,
    siviProjectAssignmentSession: null,
    siviParentSharedSession: null,
    siviParentOpen: false,
    siviSession: null,
    siviCoverSession: null,
    siviCombinedSession: null,
    siviCollectedSession: null,
    siviSpeciesSession: null,
    siviIdentitySession: null,
    siviCreationSession: undefined,
    siviCreationUndoSession: undefined,
    siviDeletionSession: undefined,
    siviRestorationSession: undefined,
    siviPanelOpen: false,
    siviCoverPanelOpen: false,
    siviCombinedPanelOpen: false,
    siviCollectedPanelOpen: false,
    siviSpeciesPanelOpen: false,
    siviIdentityPanelOpen: false,
    siviCoverReading: false,
    siviCombinedReading: false,
    siviCollectedReading: false,
    siviSpeciesReading: false,
    siviIdentityReading: false,
    siviCreationHostBusy: false,
    siviLifecycleHostBusy: false,
    siviParentActionUnsaved: false,
    siviParentActionClose: null,
    siviParentActionEditingDisabled: false,
    siviParentWriteUnsaved: false,
    siviParentWriteClose: null,
    siviParentWriteEditingDisabled: false,
    siviParentSharedUnsaved: false,
    siviParentSharedClose: null,
    siviParentSharedEditingDisabled: false,
    siviProjectAssignmentUnsaved: false,
    siviProjectAssignmentClose: null,
    siviProjectAssignmentEditingDisabled: false,
    siviUnsaved: false,
    siviClose: null,
    siviEditingDisabled: false,
    siviCoverUnsaved: false,
    siviCoverClose: null,
    siviCoverEditingDisabled: false,
    siviCombinedUnsaved: false,
    siviCombinedClose: null,
    siviCombinedEditingDisabled: false,
    siviCollectedUnsaved: false,
    siviCollectedClose: null,
    siviCollectedEditingDisabled: false,
    siviSpeciesUnsaved: false,
    siviSpeciesClose: null,
    siviSpeciesEditingDisabled: false,
    siviIdentityUnsaved: false,
    siviIdentityClose: null,
    siviIdentityEditingDisabled: false,
    siviCreationPending: false,
    siviCreationClose: null,
    siviCreationEditingDisabled: false,
    siviCreationRecoveryDisabled: false,
    siviCreationUndoPending: false,
    siviCreationUndoClose: null,
    siviCreationUndoEditingDisabled: false,
    siviCreationUndoRecoveryDisabled: false,
    siviDeletionPending: false,
    siviDeletionClose: null,
    siviDeletionEditingDisabled: false,
    siviDeletionRecoveryDisabled: false,
    siviRestorationPending: false,
    siviRestorationClose: null,
    siviRestorationEditingDisabled: false,
    siviRestorationRecoveryDisabled: false,
    siviParentSourceView: null,
    siviSourceAuthorityUnknown: false,
    siviSourceBarrier: false,
    siviView: null,
    siviCoverView: null,
    siviCombinedView: null,
    siviCollectedView: null,
    siviSpeciesView: null,
    siviIdentityView: null,
    siviParentSharedRevision: 0,
    siviProjectAssignmentRevision: 0,
    siviParentActionRevision: 0,
    siviParentWriteRevision: 0,
    siviParentSourceRevision: 0,
    siviParentRevision: 0,
    siviRevision: 0,
    siviCoverRevision: 0,
    siviCombinedRevision: 0,
    siviCollectedRevision: 0,
    siviSpeciesRevision: 0,
    siviIdentityRevision: 0,
  };
}

function runFs882TestActions(context, names, values = {}) {
  const base = getTranspiledFs882();
  const overrides = Object.keys(values)
    .filter((k) => typeof values[k] === 'function' && !names.includes(k))
    .map((k) => `${k} = __values[${JSON.stringify(k)}];`)
    .join('\n');
  context.__values = values;
  vm.runInContext(`${base}\n${overrides}\nthis.actions = {${names.join(',')}};`, context);
  delete context.__values;
}

function getTwoPageDeps(loadTypeScript) {
  if (cachedTwoPageDeps) return cachedTwoPageDeps;
  cachedTwoPageDeps = {
    ...loadTypeScript('entry/twoPageEntryOps.ts', {
      './twoPageEntrySession': { TwoPageEntrySession: class {} },
    }),
    twoPageEntryCell: (original, column) => {
      if (!original?.columns || !original?.rows?.[0]?.cells) return original?.[column] ?? { storage: 'null', text: null, integer: null, real: null, blobHex: null };
      const idx = original.columns.findIndex((c) => c.name === column);
      return idx >= 0 ? original.rows[0].cells[idx] : { storage: 'null', text: null, integer: null, real: null, blobHex: null };
    },
  };
  return cachedTwoPageDeps;
}

function attachTwoPageReadersVm(context, values, formatError) {
  if (values && Object.prototype.hasOwnProperty.call(values, 'readers') && values.readers) return;
  const hasPeerError = () =>
    context.sessions ? [...context.sessions.values()].some((p) => Boolean(p?.view?.()?.error || p?.view?.()?.referenceError)) : false;
  const getVegScope = () =>
    context.vegetationScope ?? {
      projectPath: context.sourceProjectPath ?? '',
      su: context.vegetationTableSU ?? '',
      suPath: context.vegetationTableSUPath ?? '',
    };
  const vegScopeInvalid = () => {
    const s = getVegScope();
    return !s.projectPath || !s.su || (s.su !== 'None' && !s.suPath);
  };
  const getDraft = () =>
    typeof context.actions?.getDraftState === 'function'
      ? context.actions.getDraftState()
      : typeof context.getDraftState === 'function'
        ? context.getDraftState()
        : (context.close ?? { unsaved: false, busy: false, blocked: false, error: null });
  const draftOrChildBlocked = () => {
    const d = getDraft();
    return Boolean(
      context.sourceBlocked ||
        context.childBlocked ||
        d.unsaved ||
        d.busy ||
        d.blocked ||
        d.error ||
        hasPeerError()
    );
  };
  const assertParentFree = (mode) => {
    const suffix =
      mode === 'operation'
        ? ''
        : mode === 'field'
          ? ' owns the parent; no field was staged.'
          : mode === 'project'
            ? ' owns the parent; no ProjectID was staged.'
            : ' owns the parent; no literal draft was acknowledged.';
    if (mode === 'operation') {
      if (context.profilingOpen) throw new Error('Finish the owned profile review before parent operations.');
      if (context.projectMetadataOpen) throw new Error('Finish the owned project metadata review before parent operations.');
      if (context.environmentTableOpen) throw new Error('Finish the owned environment table review before parent operations.');
      if (context.vegetationTableOpen) throw new Error('Finish the owned vegetation table review before parent operations.');
      if (context.googleEarthOpen) throw new Error('Finish the owned saved-plot KML review before parent operations.');
      if (context.auditOpen) throw new Error('Finish the owned source audit review before parent operations.');
      if (context.externalOpen) throw new Error('Finish the retained source transfer and explicit refresh before parent operations.');
      return;
    }
    if (context.profilingOpen) throw new Error(`Plot Profiling${suffix}`);
    if (context.projectMetadataOpen) throw new Error(`Project metadata${suffix}`);
    if (context.environmentTableOpen) throw new Error(`Environment table${suffix}`);
    if (context.vegetationTableOpen) throw new Error(`Vegetation table${suffix}`);
    if (context.googleEarthOpen) throw new Error(`Saved-plot KML${suffix}`);
    if (context.auditOpen) throw new Error(`Source audit${suffix}`);
    if (context.externalOpen) throw new Error(`Source transfer${suffix}`);
  };

  const readers = {
    get externalOpen() { return Boolean(context.externalOpen); },
    set externalOpen(v) { context.externalOpen = v; },
    get auditOpen() { return Boolean(context.auditOpen); },
    set auditOpen(v) { context.auditOpen = v; },
    get auditBusy() { return Boolean(context.auditBusy); },
    set auditBusy(v) { context.auditBusy = v; },
    get googleEarthOpen() { return Boolean(context.googleEarthOpen); },
    set googleEarthOpen(v) { context.googleEarthOpen = v; },
    get googleEarthBusy() { return Boolean(context.googleEarthBusy); },
    set googleEarthBusy(v) { context.googleEarthBusy = v; },
    get vegetationTableOpen() { return Boolean(context.vegetationTableOpen); },
    set vegetationTableOpen(v) { context.vegetationTableOpen = v; },
    get vegetationTableBusy() { return Boolean(context.vegetationTableBusy); },
    set vegetationTableBusy(v) { context.vegetationTableBusy = v; },
    get environmentTableOpen() { return Boolean(context.environmentTableOpen); },
    set environmentTableOpen(v) { context.environmentTableOpen = v; },
    get environmentTableBusy() { return Boolean(context.environmentTableBusy); },
    set environmentTableBusy(v) { context.environmentTableBusy = v; },
    get projectMetadataOpen() { return context.projectMetadataOpen ?? null; },
    set projectMetadataOpen(v) { context.projectMetadataOpen = v; },
    get projectMetadataBusy() { return Boolean(context.projectMetadataBusy); },
    set projectMetadataBusy(v) { context.projectMetadataBusy = v; },
    get profilingOpen() { return Boolean(context.profilingOpen); },
    set profilingOpen(v) { context.profilingOpen = v; },
    get profilingBusy() { return Boolean(context.profilingBusy); },
    set profilingBusy(v) { context.profilingBusy = v; },
    get sourceRefreshing() { return Boolean(context.sourceRefreshing); },
    set sourceRefreshing(v) { context.sourceRefreshing = v; },
    get metadataEditor() { return context.metadataEditor; },
    set metadataEditor(v) { context.metadataEditor = v; },
    get externalEditor() { return context.externalEditor; },
    set externalEditor(v) { context.externalEditor = v; },
    get metadataClient() { return context.metadataClient ?? context.projectMetadataClient; },
    get anyOpen() {
      return Boolean(
        context.externalOpen ||
          context.auditOpen ||
          context.googleEarthOpen ||
          context.vegetationTableOpen ||
          context.environmentTableOpen ||
          context.projectMetadataOpen ||
          context.profilingOpen
      );
    },
    get anyBusy() {
      return Boolean(
        context.sourceRefreshing ||
          context.auditBusy ||
          context.googleEarthBusy ||
          context.vegetationTableBusy ||
          context.environmentTableBusy ||
          context.projectMetadataBusy ||
          context.profilingBusy
      );
    },
    assertParentFree,
    openProfiling() {
      const ps = context.profileSource ?? context.profilingSource;
      if (!context.profilingReaderAvailable || !ps?.name || ps.name === 'None' || !ps.path || vegScopeInvalid() || draftOrChildBlocked()) {
        context.error = 'Resolve source-variant and linked-child drafts, references and retained outcomes; select an explicit owned profile before Plot Profiling.';
        return;
      }
      context.error = null; context.profilingOpen = true; context.onchange?.();
    },
    returnFromProfiling() {
      if (context.profilingBusy) { context.error = 'Wait for or cancel the owned profile read before returning to the source form.'; return; }
      context.profilingOpen = false; context.error = null; context.onchange?.();
    },
    openProjectMetadata() {
      if (!context.projectMetadataReaderAvailable || vegScopeInvalid() || draftOrChildBlocked()) {
        context.error = 'Resolve all source-variant and linked-child drafts, references and retained outcomes before project metadata review.';
        return;
      }
      context.error = null; context.projectMetadataOpen = 'read'; context.onchange?.();
    },
    returnFromProjectMetadata() {
      if (context.projectMetadataOpen !== 'read') { context.error = 'Return is limited to saved-data metadata review; finish editing in its owned editor.'; return; }
      if (context.projectMetadataBusy) { context.error = 'Wait for or cancel the owned project metadata read before returning to the source form.'; return; }
      context.projectMetadataOpen = null; context.error = null; context.onchange?.();
    },
    openEnvironmentTable() {
      if (!context.environmentTableReaderAvailable || vegScopeInvalid() || draftOrChildBlocked()) {
        context.error = 'Resolve all source-variant and linked-child drafts, references and retained outcomes before View Env Table.';
        return;
      }
      context.error = null; context.environmentTableOpen = true; context.onchange?.();
    },
    returnFromEnvironmentTable() {
      if (context.environmentTableBusy) { context.error = 'Wait for or cancel the owned environment table read before returning to the source form.'; return; }
      context.environmentTableOpen = false; context.error = null; context.onchange?.();
    },
    openVegetationTable() {
      if (!context.vegetationTableReaderAvailable || vegScopeInvalid() || draftOrChildBlocked()) {
        context.error = 'Resolve all source-variant and linked-child drafts, references and retained outcomes before View Veg Table.';
        return;
      }
      context.error = null; context.vegetationTableOpen = true; context.onchange?.();
    },
    returnFromVegetationTable() {
      if (context.vegetationTableBusy) { context.error = 'Wait for or cancel the owned vegetation table read before returning to the source form.'; return; }
      context.vegetationTableOpen = false; context.error = null; context.onchange?.();
    },
    openGoogleEarth() {
      const gp = context.googleEarthPath ?? context.sourceProjectPath;
      if (!context.googleEarthReaderAvailable || !gp || draftOrChildBlocked()) {
        context.error = 'Resolve all source-variant and linked-child drafts, references and retained outcomes before saved-plot KML.';
        return;
      }
      context.error = null; context.googleEarthOpen = true; context.onchange?.();
    },
    returnFromGoogleEarth() {
      if (context.googleEarthBusy) { context.error = 'Wait for or cancel the owned saved-plot read before returning to the source form.'; return; }
      context.googleEarthOpen = false; context.error = null; context.onchange?.();
    },
    openAudit() {
      if (!context.auditReaderAvailable || draftOrChildBlocked()) {
        context.error = 'Resolve all source-variant and linked-child drafts, references and retained outcomes before Audit.';
        return;
      }
      context.error = null; context.auditOpen = true; context.onchange?.();
    },
    returnFromAudit() {
      if (context.auditBusy) { context.error = 'Wait for or cancel the owned audit read before returning to the source form.'; return; }
      context.auditOpen = false; context.error = null; context.onchange?.();
    },
    openExternalTransfer() {
      const s = context.sourceScope ?? context.externalScope;
      const ext = context.externalSession;
      if (!ext || !s?.projectPath || !s.suPath || s.contextId !== context.owner?.contextId || s.project !== context.owner?.project || draftOrChildBlocked()) {
        context.error = 'Resolve all source-variant and linked-child drafts, references and retained outcomes before SU Into Env.';
        return;
      }
      try {
        ext.reviewSourceForm(context.form);
        context.error = null; context.externalOpen = true; context.onchange?.();
      } catch (cause) {
        context.error = `Source reverse transfer unavailable; owned state retained: ${formatError(cause)}`;
      }
    },
    async returnFromExternalTransfer() {
      if (context.sourceRefreshing || !context.externalEditor || context.externalEditor.getCloseState().unsaved || context.externalEditor.getCloseState().busy) {
        context.error = 'Finish the retained transfer before refreshing the source form; never replay.';
        return;
      }
      context.sourceRefreshing = true; context.error = null; context.onchange?.();
      try {
        await context.oncommitted?.();
        const active = context.session;
        for (const peer of (context.sessions?.values?.() ?? [])) {
          if (peer !== active && !peer.view().original) continue;
          const st = peer.closeState();
          if (st.unsaved || st.busy || st.blocked || !(await peer.load())) {
            throw new Error(peer.view().error ?? peer.view().referenceError ?? 'A complete-entry source variant could not refresh.');
          }
        }
        context.externalOpen = false;
      } catch (cause) {
        context.error = `Source refresh failed; retain the immutable transfer receipt and retry Return, never replay: ${formatError(cause)}`;
      } finally {
        context.sourceRefreshing = false; context.onchange?.();
      }
    },
  };
  context.readers = readers;
}

function attachLongVegTitleStatsVm(context) {
  context.latestReq = context.latestReq ?? 0;
  if (!context.holds) {
    context.holds = {
      get busy() { return Boolean(context.busy); },
      get operationHeld() { return Boolean(context.operationHeld); },
      get workbookBarrier() { return Boolean(context.workbookBarrier); },
      get preferenceBarrier() { return Boolean(context.preferenceBarrier); },
      get unitBarrier() { return Boolean(context.unitBarrier); },
      get unitMutationHeld() { return Boolean(context.unitMutationHeld); },
      get titleBarrier() { return Boolean(context.titleBarrier); },
      get statisticsBarrier() { return Boolean(context.statisticsBarrier); },
      get peerPreferenceBarriers() {
        return Boolean(
          context.peerPreferenceBarriers ||
            context.switchBarrier ||
            context.thresholdBarrier ||
            context.groupBarrier ||
            context.qualityNullBarrier ||
            context.qualityMinimumBarrier ||
            context.namingBarrier ||
            context.selectedFieldBarrier ||
            context.enforcementBarrier
        );
      },
      get peerMutationHeld() { return Boolean(context.peerMutationHeld); },
      get acknowledgePeerHeld() { return Boolean(context.acknowledgePeerHeld); },
    };
  }
  if (!context.cb) {
    context.cb = {
      get reads() { return context.reads; },
      onBeginRead() {
        context.actions?.cancel?.();
        context.busy = true;
        context.reportBusy?.();
        return context.generation;
      },
      onEndRead(req) {
        if (req === context.generation) {
          context.busy = false;
          context.reportBusy?.();
        }
      },
      onCancelParent() {
        context.actions?.cancel?.();
        return context.generation;
      },
      onSyncPreferenceToast() {},
      onSyncStatisticsToast() {},
      onError(title, msg) {
        context.error = msg;
        context.notifications?.error?.(title, msg, { category: 'reports', source: 'Long Vegetation' });
      },
    };
  }
}

module.exports = {
  createFs882VmDefaults,
  runFs882TestActions,
  getTwoPageDeps,
  attachTwoPageReadersVm,
  attachLongVegTitleStatsVm,
};
