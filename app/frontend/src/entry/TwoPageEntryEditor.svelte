<script lang="ts">
  import { onDestroy, untrack, type Snippet } from 'svelte';
  import { AuditRestoreAction, PlotEntryService } from '../../bindings/github.com/boostao/vpro/app';
import type { SIVIParentSharedReference } from '../../bindings/github.com/boostao/vpro/app/internal/sourceform/models';
  import { ReadRequests } from '../shared/readRequests';
  import type { EditorCloseState } from '../shell/closeLifecycle';
  import type { TwoPageParentForm } from './twoPageParentSession';
  import { twoPageParentCommonFields } from './twoPageParentCommonSession';
  import type { TwoPageEntryInput } from './twoPageEntryDraft';
  import { TwoPageEntrySession, twoPageEntryCell, type TwoPageEntrySessionCache } from './twoPageEntrySession';
  import TwoPageEntryLayout from './TwoPageEntryLayout.svelte';
  import { twoPageEntryProjection, twoPageEntryValues, type TwoPageEntryChild, type TwoPageEntryField } from './twoPageEntryProjection';
  import { metadataCellText } from '../admin/projectMetadataEditor';
  import { controlLabel, wideControl } from './formPresentation';
  import type { PaperControl } from './paperLayout';
  import type { GoogleEarthScope } from '../spatial/googleEarthReview';
  import { externalSUEnvironmentSession } from '../classification/externalSUEnvironment';
  import ExternalSUEnvironmentTransfer from '../classification/ExternalSUEnvironmentTransfer.svelte';
  import TwoPageAuditPanel from './TwoPageAuditPanel.svelte';
  import TwoPageGoogleEarthPanel from './TwoPageGoogleEarthPanel.svelte';
  import TwoPageVegetationTablePanel from './TwoPageVegetationTablePanel.svelte';
  import TwoPageEnvironmentTablePanel from './TwoPageEnvironmentTablePanel.svelte';
  import TwoPageProjectMetadataPanel from './TwoPageProjectMetadataPanel.svelte';
  import ProjectMetadataEditor from '../admin/ProjectMetadataEditor.svelte';
  import type { bindContextPlots } from '../shared/contextPlots';
  import TwoPageProfilingPanel from './TwoPageProfilingPanel.svelte';
  import { Columns2, FileText } from '@lucide/svelte';
  import FieldCardPreviewModal from './FieldCardPreviewModal.svelte';
  import CoordinateHelper from './CoordinateHelper.svelte';
  import { buildFieldCardViewModel } from './fieldCardPreview';
  import { notifications } from '../shell/notificationService.svelte';

  let { contextId, project, plot, cache, revision, onchange, onbusy, onclosed, oncommitted, embedded: childContent, childBlocked = false, pictureReaderAvailable = false, auditReaderAvailable = false, googleEarthReaderAvailable = false, vegetationTableReaderAvailable = false, environmentTableReaderAvailable = false, projectMetadataReaderAvailable = false, vegetationTableSU = '', vegetationTableSUPath = '', sourceProjectPath = '',
    projectMetadataClient, metadataRestorationAvailable = false,
    profilingReaderAvailable = false, profilingSource = null, externalScope = null, sourceBlocked = true, initialForm = 'FS882-8x6XL', standalone = false,
    onExtendedShrubsChange, onOpenProfileSU }: {
    contextId: string; project: string; plot: string; cache: TwoPageEntrySessionCache; revision: number;
    onchange: () => void; onbusy: (busy: boolean) => void; onclosed: () => void; oncommitted: () => Promise<void>;
    embedded: Snippet<[TwoPageEntryChild, PaperControl]>;
    childBlocked?: boolean; pictureReaderAvailable?: boolean; auditReaderAvailable?: boolean;
    googleEarthReaderAvailable?: boolean; sourceProjectPath?: string;
    vegetationTableReaderAvailable?: boolean; environmentTableReaderAvailable?: boolean; projectMetadataReaderAvailable?: boolean; vegetationTableSU?: string; vegetationTableSUPath?: string;
    projectMetadataClient?: ReturnType<typeof bindContextPlots>; metadataRestorationAvailable?: boolean;
    profilingReaderAvailable?: boolean; profilingSource?: { name: string; path: string } | null;
    externalScope?: GoogleEarthScope | null; sourceBlocked?: boolean; initialForm?: TwoPageParentForm; standalone?: boolean;
    onExtendedShrubsChange?: (enabled: boolean) => void;
    onOpenProfileSU?: () => void;
  } = $props();
  const owner = untrack(() => ({ contextId, project, plot }));
  const reviewEnabled = true;
  const editingEnabled = true;
  const metadataEditingEnabled = true;
  const metadataClient = untrack(() => projectMetadataClient);
  const metadataRestore = untrack(() => metadataRestorationAvailable);
  const sessions = untrack(() => {
    const key = JSON.stringify(owner);
    const existing = cache.get(key) ?? new Map<TwoPageParentForm, TwoPageEntrySession>();
    cache.set(key, existing); return existing;
  });
  const sourceScope = untrack(() => externalScope);
  const externalSession = sourceScope ? externalSUEnvironmentSession(sourceScope) : null;
  let externalOpen = $state(untrack(() => Boolean(externalSession?.view().blocked)));
  let auditOpen = $state(false);
  let auditBusy = $state(false);
  let googleEarthOpen = $state(false);
  let googleEarthBusy = $state(false);
  const googleEarthPath = untrack(() => sourceProjectPath);
  let vegetationTableOpen = $state(false);
  let vegetationTableBusy = $state(false);
  let environmentTableOpen = $state(false);
  let environmentTableBusy = $state(false);
  let projectMetadataOpen = $state<'read' | 'edit' | null>(null);
  let projectMetadataBusy = $state(false);
  let metadataEditor = $state<{ getCloseState(): EditorCloseState; undo(): void }>();
  let profilingOpen = $state(false);
  let profilingBusy = $state(false);
  const profileSource = untrack(() => profilingSource ? { ...profilingSource } : null);
  const vegetationScope = untrack(() => ({ projectPath: sourceProjectPath, su: vegetationTableSU, suPath: vegetationTableSUPath }));
  let sourceRefreshing = $state(false);
  let externalEditor = $state<{ getCloseState(): EditorCloseState; undo(): void }>();
  let form = $state<TwoPageParentForm>(untrack(() => initialForm));
  let session = $state(makeSession(untrack(() => initialForm)));
  let error = $state<string | null>(null);
  let fieldCardModalOpen = $state(false);
  let fieldCardSplitOpen = $state(false);
  const view = $derived.by(() => { revision; return session.view(); });
  const close = $derived.by(() => { revision; return session.closeState(); });
  const projection = $derived(twoPageEntryProjection(form));
  const twoPageFieldCardViewModel = $derived.by(() => {
    if (!fieldCardModalOpen && !fieldCardSplitOpen) return null;
    let projectChoiceText: string | null = null;
    if (view.projectRowId && view.snapshot?.ProjectChoices?.Choices?.rows) {
      const matched = view.snapshot.ProjectChoices.Choices.rows.find(r => r.rowId === view.projectRowId);
      const codeCell = matched?.cells?.[0];
      if (codeCell && codeCell.storage !== 'null') {
        projectChoiceText = metadataCellText(codeCell);
      }
    }
    return buildFieldCardViewModel({
      formKind: 'two-page',
      draftHeader: { plotNumber: owner.plot },
      twoPageOriginal: view.original ?? null,
      twoPageDrafts: view.drafts,
      twoPageProjectText: projectChoiceText,
      extendedShrubs: form === 'FS882-8x6XL-CHARS',
      isDirty: close.unsaved || childBlocked,
    });
  });

  function handleTwoPageKeydown(event: KeyboardEvent) {
    if (event.altKey && !event.ctrlKey && !event.metaKey && !event.shiftKey && event.key.toLowerCase() === 'p') {
      event.preventDefault();
      fieldCardModalOpen = !fieldCardModalOpen;
      if (fieldCardModalOpen) fieldCardSplitOpen = false;
      return;
    }
    if ((event.ctrlKey || event.metaKey) && !event.altKey && !event.shiftKey && event.key.toLowerCase() === 's') {
      event.preventDefault();
      const subPanelActive =
        (typeof profilingOpen !== 'undefined' && Boolean(profilingOpen)) ||
        (typeof projectMetadataOpen !== 'undefined' && Boolean(projectMetadataOpen)) ||
        (typeof environmentTableOpen !== 'undefined' && Boolean(environmentTableOpen)) ||
        (typeof vegetationTableOpen !== 'undefined' && Boolean(vegetationTableOpen)) ||
        (typeof googleEarthOpen !== 'undefined' && Boolean(googleEarthOpen)) ||
        (typeof auditOpen !== 'undefined' && Boolean(auditOpen)) ||
        (typeof externalOpen !== 'undefined' && Boolean(externalOpen));
      if (!subPanelActive && !childBlocked && editingEnabled && close.canSave && !close.busy && !close.blocked) {
        void operation('save');
      }
    }
  }

  function makeSession(sourceForm: TwoPageParentForm) {
    const existing = sessions.get(sourceForm);
    if (existing) return existing;
    const requests = new ReadRequests();
    const created = new TwoPageEntrySession(owner, sourceForm, {
      read: () => requests.track(PlotEntryService.GetTwoPageParentEntryOriginal(owner.contextId, owner.plot, sourceForm)),
      readReferences: filters => requests.track(PlotEntryService.GetTwoPageParentEntryReferences(owner.contextId, owner.plot, sourceForm, filters)),
      cancelRead: () => requests.cancelAll(),
      save: request => PlotEntryService.SaveTwoPageParentEntry(owner.contextId, owner.plot, sourceForm, request),
      restore: (history, action) => PlotEntryService.RestoreTwoPageParentEntry(owner.contextId, owner.plot, sourceForm, history, action),
      refreshParent: async () => {
        await oncommitted();
        for (const [variant, peer] of sessions) {
          if (variant === sourceForm || !peer.view().original) continue;
          if (peer.closeState().unsaved || peer.closeState().busy || !await peer.load()) {
            throw new Error(peer.view().error ?? 'Another complete-entry variant could not refresh; no write was replayed.');
          }
        }
      },
    }, onchange);
    sessions.set(sourceForm, created); return created;
  }
  $effect(() => { onbusy(view.busy || view.referencesBusy || externalOpen || sourceRefreshing || auditOpen || auditBusy || googleEarthOpen || googleEarthBusy || vegetationTableOpen || vegetationTableBusy || environmentTableOpen || environmentTableBusy || Boolean(projectMetadataOpen) || projectMetadataBusy || profilingOpen || profilingBusy); });
  let autoLoadedKey = '';
  $effect(() => {
    if (!standalone || !owner.plot) return;
    const key = `${owner.contextId}:${owner.project}:${owner.plot}:${form}`;
    if (autoLoadedKey === key || view.original || view.busy || view.referencesBusy || view.error || view.referenceError || view.blocked) return;
    autoLoadedKey = key;
    void operation('load');
  });
  onDestroy(() => {
    const active = session.view();
    if (active.operation === 'read' || active.referencesBusy) session.cancel();
  });
  export function getCloseState(): EditorCloseState {
    if (projectMetadataOpen === 'edit') return metadataEditor?.getCloseState() ?? {
      unsaved: true, busy: projectMetadataBusy, canSave: false, blocked: true, error,
      saveReason: 'Finish the owned metadata editor before closing the complete-entry source.',
    };
    if (typeof standalone !== 'undefined' && standalone) {
      const draftState = getDraftState();
      const subPanelOpen = externalOpen || auditOpen || googleEarthOpen || vegetationTableOpen || environmentTableOpen || Boolean(projectMetadataOpen) || profilingOpen;
      if (subPanelOpen || childBlocked) {
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
      if (!draftState.unsaved) {
        return {
          ...close,
          unsaved: false,
          busy: draftState.busy,
          blocked: close.blocked,
          canSave: true,
          error: error ?? close.error,
          saveReason: '',
        };
      }
      return {
        ...close,
        unsaved: true,
        busy: draftState.busy,
        blocked: close.blocked,
        canSave: editingEnabled && close.canSave && !childBlocked,
        error: error ?? close.error,
        saveReason: close.saveReason || (!editingEnabled ? 'Editing is disabled.' : ''),
      };
    }
    return { ...close, unsaved: true, busy: close.busy || projectMetadataBusy || profilingBusy, canSave: false, error: error ?? close.error,
      saveReason: 'Save or Undo complete-entry drafts explicitly, then close their review before saving or closing the plot.' };
  }
  export async function saveForClose(): Promise<boolean> {
    const state = getCloseState();
    if (!(typeof standalone !== 'undefined' && standalone) || !state.canSave) { error = state.saveReason; return false; }
    await operation('save');
    return !getDraftState().unsaved && !close.blocked && error === null;
  }
  export function getDraftState(): EditorCloseState {
    const states = [...sessions.values()].map(owned => owned.closeState());
    const metadataClose = projectMetadataOpen === 'edit' ? getCloseState() : null;
    return { ...close, unsaved: externalOpen || auditOpen || googleEarthOpen || vegetationTableOpen || environmentTableOpen || Boolean(projectMetadataOpen) || profilingOpen || states.some(state => state.unsaved), busy: sourceRefreshing || auditBusy || googleEarthBusy || vegetationTableBusy || environmentTableBusy || projectMetadataBusy || profilingBusy || Boolean(metadataClose?.busy) || states.some(state => state.busy),
      error: error ?? metadataClose?.error ?? close.error, blocked: externalOpen || auditOpen || googleEarthOpen || vegetationTableOpen || environmentTableOpen || Boolean(projectMetadataOpen) || profilingOpen || !view.original || !!view.referenceError || states.some(state => state.blocked) };
  }
  export function canOpenMetadataEditor() {
    const state = getDraftState();
    if (!metadataEditingEnabled || !metadataClient || sourceBlocked || childBlocked || !view.original ||
        state.unsaved || state.busy || state.blocked || state.error ||
        [...sessions.values()].some(peer => Boolean(peer.view().error || peer.view().referenceError))) return false;
    const projectId = twoPageEntryCell(view.original, 'ProjectID');
    return projectId.storage === 'text' && projectId.text !== null && projectId.text.length > 0;
  }
  export function openMetadataEditor() {
    if (!canOpenMetadataEditor()) {
      error = 'Resolve source-variant and linked-child drafts, references and retained outcomes before editing owned project metadata.';
      return;
    }
    error = null; projectMetadataOpen = 'edit'; onchange();
  }
  async function refreshMetadataPeers() {
    await oncommitted();
    for (const peer of sessions.values()) {
      if (!peer.view().original && !peer.view().error && !peer.view().referenceError) continue;
      const state = peer.closeState();
      if (state.unsaved || state.busy || state.blocked || !await peer.load()) {
        throw new Error(peer.view().error ?? peer.view().referenceError ??
          'A complete-entry metadata peer could not refresh; no write was replayed.');
      }
    }
  }
  function openProfiling() {
    const draftState = getDraftState();
    const peerError = [...sessions.values()].some(peer => Boolean(peer.view().error || peer.view().referenceError));
    if (!profilingReaderAvailable || !profileSource?.name || profileSource.name === 'None' || !profileSource.path ||
        !vegetationScope.projectPath || !vegetationScope.su || vegetationScope.su !== 'None' && !vegetationScope.suPath ||
        sourceBlocked || childBlocked || draftState.unsaved || draftState.busy || draftState.blocked || draftState.error || peerError) {
      error = 'Resolve source-variant and linked-child drafts, references and retained outcomes; select an explicit owned profile before Plot Profiling.';
      return;
    }
    error = null; profilingOpen = true; onchange();
  }
  function returnFromProfiling() {
    if (profilingBusy) { error = 'Wait for or cancel the owned profile read before returning to the source form.'; return; }
    profilingOpen = false; error = null; onchange();
  }
  function openProjectMetadata() {
    const draftState = getDraftState();
    const peerError = [...sessions.values()].some(peer => Boolean(peer.view().error || peer.view().referenceError));
    if (!projectMetadataReaderAvailable || !vegetationScope.projectPath || !vegetationScope.su ||
        vegetationScope.su !== 'None' && !vegetationScope.suPath || sourceBlocked || childBlocked ||
        draftState.unsaved || draftState.busy || draftState.blocked || draftState.error || peerError) {
      error = 'Resolve all source-variant and linked-child drafts, references and retained outcomes before project metadata review.';
      return;
    }
    error = null; projectMetadataOpen = 'read'; onchange();
  }
  function returnFromProjectMetadata() {
    if (projectMetadataOpen !== 'read') {
      error = 'Return is limited to saved-data metadata review; finish editing in its owned editor.';
      return;
    }
    if (projectMetadataBusy) { error = 'Wait for or cancel the owned project metadata read before returning to the source form.'; return; }
    projectMetadataOpen = null; error = null; onchange();
  }
  function canSwitchToMetadataEdit() {
    const states = [...sessions.values()].map(owned => owned.closeState());
    if (!metadataEditingEnabled || !metadataClient || sourceBlocked || childBlocked || !view.original ||
        projectMetadataBusy || externalOpen || auditOpen || googleEarthOpen || vegetationTableOpen || environmentTableOpen || profilingOpen ||
        states.some(state => state.unsaved || state.busy || state.blocked) ||
        [...sessions.values()].some(peer => Boolean(peer.view().error || peer.view().referenceError))) return false;
    const projectId = twoPageEntryCell(view.original, 'ProjectID');
    return projectId.storage === 'text' && projectId.text !== null && projectId.text.length > 0;
  }
  function switchReadMetadataToEdit() {
    if (projectMetadataBusy) {
      error = 'Wait for or cancel the owned project metadata read before switching to edit.';
      return;
    }
    projectMetadataOpen = null;
    openMetadataEditor();
  }
  function openEnvironmentTable() {
    const draftState = getDraftState();
    const peerError = [...sessions.values()].some(peer => Boolean(peer.view().error || peer.view().referenceError));
    if (!environmentTableReaderAvailable || !vegetationScope.projectPath || !vegetationScope.su ||
        vegetationScope.su !== 'None' && !vegetationScope.suPath || sourceBlocked || childBlocked ||
        draftState.unsaved || draftState.busy || draftState.blocked || draftState.error || peerError) {
      error = 'Resolve all source-variant and linked-child drafts, references and retained outcomes before View Env Table.';
      return;
    }
    error = null; environmentTableOpen = true; onchange();
  }
  function returnFromEnvironmentTable() {
    if (environmentTableBusy) { error = 'Wait for or cancel the owned environment table read before returning to the source form.'; return; }
    environmentTableOpen = false; error = null; onchange();
  }
  function openVegetationTable() {
    const draftState = getDraftState();
    const peerError = [...sessions.values()].some(peer => Boolean(peer.view().error || peer.view().referenceError));
    if (!vegetationTableReaderAvailable || !vegetationScope.projectPath || !vegetationScope.su ||
        vegetationScope.su !== 'None' && !vegetationScope.suPath || sourceBlocked || childBlocked ||
        draftState.unsaved || draftState.busy || draftState.blocked || draftState.error || peerError) {
      error = 'Resolve all source-variant and linked-child drafts, references and retained outcomes before View Veg Table.';
      return;
    }
    error = null; vegetationTableOpen = true; onchange();
  }
  function returnFromVegetationTable() {
    if (vegetationTableBusy) { error = 'Wait for or cancel the owned vegetation table read before returning to the source form.'; return; }
    vegetationTableOpen = false; error = null; onchange();
  }
  function openGoogleEarth() {
    const draftState = getDraftState();
    const peerError = [...sessions.values()].some(peer => Boolean(peer.view().error || peer.view().referenceError));
    if (!googleEarthReaderAvailable || !googleEarthPath || sourceBlocked || childBlocked ||
        draftState.unsaved || draftState.busy || draftState.blocked || draftState.error || peerError) {
      error = 'Resolve all source-variant and linked-child drafts, references and retained outcomes before saved-plot KML.';
      return;
    }
    error = null; googleEarthOpen = true; onchange();
  }
  function returnFromGoogleEarth() {
    if (googleEarthBusy) { error = 'Wait for or cancel the owned saved-plot read before returning to the source form.'; return; }
    googleEarthOpen = false; error = null; onchange();
  }
  function openAudit() {
    const draftState = getDraftState();
    const peerError = [...sessions.values()].some(peer => Boolean(peer.view().error || peer.view().referenceError));
    if (!auditReaderAvailable || sourceBlocked || childBlocked || draftState.unsaved || draftState.busy ||
        draftState.blocked || draftState.error || peerError) {
      error = 'Resolve all source-variant and linked-child drafts, references and retained outcomes before Audit.';
      return;
    }
    error = null; auditOpen = true; onchange();
  }
  function returnFromAudit() {
    if (auditBusy) { error = 'Wait for or cancel the owned audit read before returning to the source form.'; return; }
    auditOpen = false; error = null; onchange();
  }
  function openExternalTransfer() {
    const draftState = getDraftState();
    const peerError = [...sessions.values()].find(peer => peer.view().error || peer.view().referenceError);
    if (!externalSession || !sourceScope?.projectPath || !sourceScope.suPath ||
        sourceScope.contextId !== owner.contextId || sourceScope.project !== owner.project || sourceBlocked || childBlocked ||
        draftState.unsaved || draftState.busy || draftState.blocked || draftState.error || peerError) {
      error = 'Resolve all source-variant and linked-child drafts, references and retained outcomes before SU Into Env.';
      return;
    }
    try {
      externalSession.reviewSourceForm(form);
      error = null; externalOpen = true; onchange();
    } catch (cause) { error = `Source reverse transfer unavailable; owned state retained: ${String(cause)}`; }
  }
  async function returnFromExternalTransfer() {
    if (sourceRefreshing || !externalEditor || externalEditor.getCloseState().unsaved || externalEditor.getCloseState().busy) {
      error = 'Finish the retained transfer before refreshing the source form; never replay.';
      return;
    }
    sourceRefreshing = true; error = null; onchange();
    try {
      await oncommitted();
      for (const peer of sessions.values()) {
        if (peer !== session && !peer.view().original) continue;
        const state = peer.closeState();
        if (state.unsaved || state.busy || state.blocked || !await peer.load()) {
          throw new Error(peer.view().error ?? peer.view().referenceError ?? 'A complete-entry source variant could not refresh.');
        }
      }
      externalOpen = false;
    } catch (cause) {
      error = `Source refresh failed; retain the immutable transfer receipt and retry Return, never replay: ${String(cause)}`;
    } finally { sourceRefreshing = false; onchange(); }
  }
  export function undo() {
    if (projectMetadataOpen === 'edit') { metadataEditor?.undo(); return; }
    void operation('undo');
  }
  async function chooseForm(next: TwoPageParentForm) {
    if (externalOpen || auditOpen || googleEarthOpen || vegetationTableOpen || environmentTableOpen || projectMetadataOpen || profilingOpen || childBlocked || close.unsaved || close.busy || close.blocked) {
      error = 'Save or Undo the owned complete-entry draft before changing source variant.'; return;
    }
    form = next; session = makeSession(next); onExtendedShrubsChange?.(next === 'FS882-8x6XL-CHARS'); onchange();
    await operation('load');
  }
  async function operation(action: 'load' | 'save' | 'undo' | 'retain' | 'prune' | 'references') {
    const plotName = typeof owner !== 'undefined' && owner?.plot ? owner.plot : '';
    const notifOpts = {
      category: 'entry' as const,
      source: 'Two-Page Form',
      contextTag: plotName ? `Plot ${plotName}` : undefined,
    };
    try {
      if (profilingOpen) throw new Error('Finish the owned profile review before parent operations.');
      if (projectMetadataOpen) throw new Error('Finish the owned project metadata review before parent operations.');
      if (environmentTableOpen) throw new Error('Finish the owned environment table review before parent operations.');
      if (vegetationTableOpen) throw new Error('Finish the owned vegetation table review before parent operations.');
      if (googleEarthOpen) throw new Error('Finish the owned saved-plot KML review before parent operations.');
      if (auditOpen) throw new Error('Finish the owned source audit review before parent operations.');
      if (externalOpen) throw new Error('Finish the retained source transfer and explicit refresh before parent operations.');
      if (!reviewEnabled || !editingEnabled && action !== 'load' && action !== 'undo' && action !== 'references') {
        throw new Error('Complete-entry review/editing is independently disabled.');
      }
      if (childBlocked && action !== 'undo' && action !== 'references') {
        throw new Error('Resolve retained linked-child drafts, reads and receipts before changing the parent.');
      }
      error = null;
      const hadUnsaved = action === 'undo' && (
        (typeof session?.closeState === 'function' ? Boolean(session.closeState()?.unsaved) : false) ||
        (typeof close !== 'undefined' ? Boolean(close?.unsaved) : false)
      );
      const ok = action === 'load' ? await session.load() : action === 'save' ? await session.save()
        : action === 'undo' ? await session.undo() : action === 'references' ? await session.loadReferences()
        : await session.restore(action === 'retain' ? AuditRestoreAction.AuditRestoreRetain : AuditRestoreAction.AuditRestorePrune);
      if (!ok) {
        error = session.view().error ?? session.view().referenceError;
        if (error && (action === 'save' || action === 'retain' || action === 'prune' || action === 'load') &&
            typeof notifications !== 'undefined' && typeof notifications?.error === 'function') {
          notifications.error(
            `Two-page ${action === 'load' ? 'reload' : action === 'save' ? 'save' : 'restore'} failed`,
            error,
            notifOpts,
          );
        }
      } else if (typeof notifications !== 'undefined') {
        if (action === 'save' && typeof notifications?.success === 'function') {
          notifications.success(
            plotName ? `Two-page plot ${plotName} saved` : 'Two-page plot saved',
            `${typeof form !== 'undefined' ? form : 'Two-page'} complete-entry changes committed atomically.`,
            notifOpts,
          );
        } else if (action === 'undo' && hadUnsaved && typeof notifications?.info === 'function') {
          notifications.info(
            'Two-page changes undone',
            plotName ? `Plot ${plotName} restored to last saved state.` : 'Draft changes discarded.',
            notifOpts,
          );
        } else if ((action === 'retain' || action === 'prune') && typeof notifications?.success === 'function') {
          notifications.success(
            plotName ? `Two-page plot ${plotName} restored` : 'Two-page plot restored',
            action === 'retain' ? 'Restored with audit history retained.' : 'Restored with audit history pruned.',
            notifOpts,
          );
        }
      }
    } catch (cause) {
      error = `Complete-entry operation refused; owned state retained: ${String(cause)}`;
      if ((action === 'save' || action === 'retain' || action === 'prune' || action === 'load') &&
          typeof notifications !== 'undefined' && typeof notifications?.error === 'function') {
        notifications.error(
          `Two-page ${action === 'load' ? 'reload' : action === 'save' ? 'save' : 'restore'} refused`,
          error,
          notifOpts,
        );
      }
    }
  }
  function stage(column: string, input: TwoPageEntryInput) {
    try {
      if (profilingOpen) throw new Error('Plot Profiling owns the parent; no field was staged.');
      if (projectMetadataOpen) throw new Error('Project metadata owns the parent; no field was staged.');
      if (environmentTableOpen) throw new Error('Environment table owns the parent; no field was staged.');
      if (vegetationTableOpen) throw new Error('Vegetation table owns the parent; no field was staged.');
      if (googleEarthOpen) throw new Error('Saved-plot KML owns the parent; no field was staged.');
      if (auditOpen) throw new Error('Source audit owns the parent; no field was staged.');
      if (externalOpen) throw new Error('Source transfer owns the parent; no field was staged.');
      if (!editingEnabled) throw new Error('Complete-entry editing is independently disabled.');
      if (childBlocked && !view.drafts[column]) throw new Error('Resolve linked-child ownership before new parent staging.');
      session.stage(column, input); error = session.view().error;
    } catch (cause) { error = `Complete-entry draft refused; owned state retained: ${String(cause)}`; }
  }
  function selectProject(rowId: string | null) {
    try {
      if (profilingOpen) throw new Error('Plot Profiling owns the parent; no ProjectID was staged.');
      if (projectMetadataOpen) throw new Error('Project metadata owns the parent; no ProjectID was staged.');
      if (environmentTableOpen) throw new Error('Environment table owns the parent; no ProjectID was staged.');
      if (vegetationTableOpen) throw new Error('Vegetation table owns the parent; no ProjectID was staged.');
      if (googleEarthOpen) throw new Error('Saved-plot KML owns the parent; no ProjectID was staged.');
      if (auditOpen) throw new Error('Source audit owns the parent; no ProjectID was staged.');
      if (externalOpen) throw new Error('Source transfer owns the parent; no ProjectID was staged.');
      if (!editingEnabled) throw new Error('Complete-entry editing is independently disabled.');
      if (childBlocked && !view.drafts.ProjectID) throw new Error('Resolve linked-child ownership before new parent staging.');
      session.selectProject(rowId); error = session.view().error;
    } catch (cause) { error = `Physical ProjectID selection refused: ${String(cause)}`; }
  }
  function acknowledge(column: string) {
    try {
      if (profilingOpen) throw new Error('Plot Profiling owns the parent; no literal draft was acknowledged.');
      if (projectMetadataOpen) throw new Error('Project metadata owns the parent; no literal draft was acknowledged.');
      if (environmentTableOpen) throw new Error('Environment table owns the parent; no literal draft was acknowledged.');
      if (vegetationTableOpen) throw new Error('Vegetation table owns the parent; no literal draft was acknowledged.');
      if (googleEarthOpen) throw new Error('Saved-plot KML owns the parent; no literal draft was acknowledged.');
      if (auditOpen) throw new Error('Source audit owns the parent; no literal draft was acknowledged.');
      if (externalOpen) throw new Error('Source transfer owns the parent; no literal draft was acknowledged.');
      if (!editingEnabled) throw new Error('Complete-entry editing is independently disabled.');
      session.acknowledge(column); error = session.view().error;
    } catch (cause) { error = `Literal acknowledgement refused: ${String(cause)}`; }
  }
  function cancel() {
    try {
      if (projectMetadataOpen) throw new Error('Project metadata owns the source; cancel its own read explicitly.');
      session.cancel(); error = session.view().error;
    }
    catch (cause) { error = `Complete-entry cancellation refused: ${String(cause)}`; }
  }
  function closeReview() {
    if (externalOpen || auditOpen || googleEarthOpen || vegetationTableOpen || environmentTableOpen || projectMetadataOpen || profilingOpen || childBlocked || close.unsaved || close.busy || close.blocked) {
      error = close.saveReason || 'Save or Undo complete-entry drafts before closing their review.'; return;
    }
    onclosed();
  }
  function referenceChoices(reference: SIVIParentSharedReference) {
    if (reference.choices === null) throw new Error(`${reference.column} reference lost its complete choice receipt.`);
    return reference.choices;
  }

  let coordHelperOpen = $state(false);
</script>

<svelte:window onkeydown={handleTwoPageKeydown} />

<section class="two-page-entry-shell space-y-4 rounded border border-[#D8D8D8] bg-white p-4 text-[#313132]" aria-label="Complete two-page entry review" data-two-page-entry-panel={form}>
  <div class="vpro-sticky-bar sticky top-0 z-20 bg-white/95 pb-2 space-y-2" data-two-page-sticky-bar>
  <div class="two-page-entry-header flex flex-wrap items-center justify-between gap-3 border-b border-[#D1D5DB] pb-3">
    <div class="flex flex-wrap items-center gap-2.5">
      <h3 class="font-bold text-[#003366]">{form === 'FS882-8x6XL-CHARS' ? 'FS882 (2-Page, Extended Shrubs): Ecosystem Field Form' : 'FS882 (2-Page): Ecosystem Field Form'}</h3>
      {#if view.original || close.unsaved}
        <span class="px-2 py-0.5 rounded text-xs font-semibold {close.unsaved ? 'bg-amber-100 text-amber-800' : 'bg-stone-200 text-stone-600'}">{close.unsaved ? 'Draft Unsaved' : 'Clean'}</span>
      {/if}
    </div>
    <div class="flex flex-wrap items-center gap-2">
      <button
        type="button"
        data-view-field-card-btn
        title="Preview official printed field card (Alt+P)"
        onclick={() => { fieldCardModalOpen = true; fieldCardSplitOpen = false; }}
        class="px-3 py-1 rounded text-xs font-semibold border border-[#003366] bg-[#EBF1F8] text-[#003366] hover:bg-[#003366] hover:text-white flex items-center gap-1.5"
      >
        <FileText size={14} /> View Field Card
      </button>
      <button
        type="button"
        data-dock-field-card-btn
        aria-pressed={fieldCardSplitOpen}
        title="Toggle live side-by-side split field card preview (>= 1760px)"
        onclick={() => { fieldCardSplitOpen = !fieldCardSplitOpen; if (fieldCardSplitOpen) fieldCardModalOpen = false; }}
        class="two-page-dock-btn px-3 py-1 rounded text-xs font-semibold border flex items-center gap-1.5 {fieldCardSplitOpen ? 'bg-[#003366] text-white border-[#003366]' : 'border-[#D1D5DB] bg-white text-[#003366] hover:bg-[#EBF1F8]'}"
      >
        <Columns2 size={14} /> Dock Split View
      </button>
    </div>
  </div>
  {#if !(profilingOpen && profileSource) && projectMetadataOpen !== 'edit' && projectMetadataOpen !== 'read' && !environmentTableOpen && !vegetationTableOpen && !googleEarthOpen && !auditOpen && !(externalOpen && sourceScope?.projectPath && sourceScope.suPath)}
  <div class="flex flex-wrap items-center justify-between gap-2 rounded border border-stone-200 bg-stone-50 p-2">
    <div class="flex flex-wrap items-center gap-1.5">
      <button type="button" class="rounded bg-[#003366] hover:bg-[#002244] px-3 py-1 text-xs font-medium text-white disabled:opacity-50" disabled={childBlocked || !editingEnabled || !close.canSave || close.busy || close.blocked}
        onclick={() => operation('save')}>Save</button>
      <button type="button" class="rounded border border-stone-300 bg-white px-2.5 py-1 text-xs font-medium text-stone-800 hover:bg-stone-50 disabled:opacity-50" disabled={close.busy} onclick={() => operation('undo')}>Undo</button>
      <button type="button" class="rounded border border-stone-300 bg-white px-2.5 py-1 text-xs font-medium text-stone-800 hover:bg-stone-50 disabled:opacity-50" disabled={childBlocked || !reviewEnabled || close.unsaved || close.busy || close.blocked}
        onclick={() => operation('load')}>Reload Plot</button>
      <button type="button" class="rounded border border-stone-300 bg-white px-2.5 py-1 text-xs font-medium text-stone-800 hover:bg-stone-50 disabled:opacity-50" disabled={!reviewEnabled || close.busy || !view.original || view.blocked}
        onclick={() => operation('references')}>Refresh Lists</button>
      <label class="inline-flex items-center gap-1.5 rounded border border-stone-300 bg-white px-2.5 py-1 text-xs font-medium text-stone-800">
        <input type="checkbox" data-extended-shrubs checked={form === 'FS882-8x6XL-CHARS'}
          disabled={childBlocked || close.unsaved || close.busy || close.blocked}
          onchange={event => chooseForm(event.currentTarget.checked ? 'FS882-8x6XL-CHARS' : 'FS882-8x6XL')} />
        Show extended shrub layers
      </label>
      <button type="button" class="rounded border border-stone-300 bg-white px-2.5 py-1 text-xs font-medium text-stone-800 hover:bg-stone-50 disabled:opacity-50" disabled={childBlocked || close.unsaved || close.busy || close.blocked} onclick={closeReview}>{standalone ? 'Close Form' : 'Return to 6x4 Form'}</button>
      {#if view.busy && view.operation === 'read' || view.referencesBusy}
        <button type="button" class="rounded border border-stone-300 bg-white px-2.5 py-1 text-xs font-medium text-stone-800 hover:bg-stone-50" onclick={cancel}>Cancel Read</button>
      {/if}
      {#if view.historyId}
        <button type="button" class="rounded border border-stone-300 bg-white px-2.5 py-1 text-xs font-medium text-stone-800 hover:bg-stone-50 disabled:opacity-50" disabled={childBlocked || !editingEnabled || close.unsaved || close.busy || close.blocked}
          onclick={() => operation('retain')}>Restore (retain audits)</button>
        <button type="button" class="rounded border border-stone-300 bg-white px-2.5 py-1 text-xs font-medium text-stone-800 hover:bg-stone-50 disabled:opacity-50" disabled={childBlocked || !editingEnabled || close.unsaved || close.busy || close.blocked}
          onclick={() => operation('prune')}>Restore (prune audits)</button>
      {/if}
    </div>
    <div class="flex flex-wrap items-center gap-1.5">
      {#if metadataEditingEnabled}
        <button type="button" class="rounded border border-stone-300 bg-white px-2.5 py-1 text-xs font-medium text-stone-800 hover:bg-stone-50 disabled:opacity-50" data-two-page-project-metadata-edit-open data-source-control={projection.metadataAction.controlId}
          disabled={!canOpenMetadataEditor()} onclick={openMetadataEditor}>{projection.metadataAction.caption}</button>
      {/if}
      {#if profilingReaderAvailable}
        <button type="button" class="rounded border border-stone-300 bg-white px-2.5 py-1 text-xs font-medium text-stone-800 hover:bg-stone-50 disabled:opacity-50" data-two-page-profiling-open data-source-control={projection.profilingAction.controlId}
          disabled={!profileSource?.name || profileSource.name === 'None' || !profileSource.path ||
            !vegetationScope.projectPath || !vegetationScope.su || vegetationScope.su !== 'None' && !vegetationScope.suPath ||
            sourceBlocked || childBlocked || getDraftState().unsaved || getDraftState().busy || getDraftState().blocked ||
            Boolean(getDraftState().error) || [...sessions.values()].some(peer => Boolean(peer.view().error || peer.view().referenceError))}
          onclick={openProfiling}>{projection.profilingAction.caption}</button>
      {/if}
      {#if projectMetadataReaderAvailable}
        <button type="button" class="rounded border border-stone-300 bg-white px-2.5 py-1 text-xs font-medium text-stone-800 hover:bg-stone-50 disabled:opacity-50" data-two-page-project-metadata-open data-source-control={metadataEditingEnabled ? undefined : projection.metadataAction.controlId}
          disabled={!vegetationScope.projectPath || !vegetationScope.su || vegetationScope.su !== 'None' && !vegetationScope.suPath ||
            sourceBlocked || childBlocked || getDraftState().unsaved || getDraftState().busy || getDraftState().blocked ||
            Boolean(getDraftState().error) || [...sessions.values()].some(peer => Boolean(peer.view().error || peer.view().referenceError))}
          onclick={openProjectMetadata}>{metadataEditingEnabled ? 'View Project Metadata' : projection.metadataAction.caption}</button>
      {/if}
      {#if environmentTableReaderAvailable}
        <button type="button" class="rounded border border-stone-300 bg-white px-2.5 py-1 text-xs font-medium text-stone-800 hover:bg-stone-50 disabled:opacity-50" data-two-page-environment-table-open data-source-control={projection.environmentTableAction.controlId}
          disabled={!vegetationScope.projectPath || !vegetationScope.su || vegetationScope.su !== 'None' && !vegetationScope.suPath ||
            sourceBlocked || childBlocked || getDraftState().unsaved || getDraftState().busy || getDraftState().blocked ||
            Boolean(getDraftState().error) || [...sessions.values()].some(peer => Boolean(peer.view().error || peer.view().referenceError))}
          onclick={openEnvironmentTable}>{projection.environmentTableAction.caption}</button>
      {/if}
      {#if vegetationTableReaderAvailable}
        <button type="button" class="rounded border border-stone-300 bg-white px-2.5 py-1 text-xs font-medium text-stone-800 hover:bg-stone-50 disabled:opacity-50" data-two-page-vegetation-table-open data-source-control={projection.vegetationTableAction.controlId}
          disabled={!vegetationScope.projectPath || !vegetationScope.su || vegetationScope.su !== 'None' && !vegetationScope.suPath ||
            sourceBlocked || childBlocked || getDraftState().unsaved || getDraftState().busy || getDraftState().blocked ||
            Boolean(getDraftState().error) || [...sessions.values()].some(peer => Boolean(peer.view().error || peer.view().referenceError))}
          onclick={openVegetationTable}>{projection.vegetationTableAction.caption}</button>
      {/if}
      {#if googleEarthReaderAvailable}
        <button type="button" class="rounded border border-stone-300 bg-white px-2.5 py-1 text-xs font-medium text-stone-800 hover:bg-stone-50 disabled:opacity-50" data-two-page-google-earth-open data-source-control={projection.googleEarthAction.controlId}
          disabled={!googleEarthPath || sourceBlocked || childBlocked || getDraftState().unsaved || getDraftState().busy || getDraftState().blocked ||
            Boolean(getDraftState().error) || [...sessions.values()].some(peer => Boolean(peer.view().error || peer.view().referenceError))}
          onclick={openGoogleEarth}>{projection.googleEarthAction.caption} (KML)</button>
      {/if}
      {#if auditReaderAvailable}
        <button type="button" class="rounded border border-stone-300 bg-white px-2.5 py-1 text-xs font-medium text-stone-800 hover:bg-stone-50 disabled:opacity-50" data-two-page-audit-open data-source-control={projection.auditAction.controlId}
          disabled={sourceBlocked || childBlocked || getDraftState().unsaved || getDraftState().busy || getDraftState().blocked ||
            Boolean(getDraftState().error) || [...sessions.values()].some(peer => Boolean(peer.view().error || peer.view().referenceError))}
          onclick={openAudit}>{projection.auditAction.caption}</button>
      {/if}
      {#if sourceScope}
        <button type="button" class="rounded border border-stone-300 bg-white px-2.5 py-1 text-xs font-medium text-stone-800 hover:bg-stone-50 disabled:opacity-50" data-source-control={projection.reverseAction.controlId} data-two-page-su-environment-open
          disabled={sourceBlocked || childBlocked || getDraftState().unsaved || getDraftState().busy || getDraftState().blocked || Boolean(getDraftState().error)
            || [...sessions.values()].some(peer => Boolean(peer.view().error || peer.view().referenceError))}
          onclick={openExternalTransfer}>{projection.reverseAction.caption} (External SU)</button>
      {/if}
    </div>
  </div>
  {/if}
  </div>
  {#if error}<div role="alert" class="rounded border border-[#e59ba0] bg-[#fbeaea] px-3 py-2 text-xs text-[#a61b20] flex items-center justify-between gap-2"><span>{error}</span><button type="button" class="rounded border border-[#e59ba0] bg-white px-2 py-0.5 text-[11px] font-medium text-[#a61b20] hover:bg-[#f8d7da]" onclick={() => { error = null; }}>Dismiss</button></div>{/if}
  {#if view.error && view.error !== error}<p role="alert" class="text-sm text-[#D8292F]">{view.error}</p>{/if}
  {#if view.referenceError}<p role="alert" class="text-sm text-[#D8292F]">{view.referenceError}</p>{/if}
  {#if view.blocked}<p role="alert" class="rounded border border-[#e59ba0] bg-[#fbeaea] px-3 py-2 text-xs text-[#a61b20]">Write outcome or refresh is unresolved. Undo / reload explicitly; never replay Save.</p>{/if}
  {#if view.busy || view.referencesBusy}<p role="status" class="text-xs font-medium text-[#003366]">{view.operation === 'save' ? 'Saving plot changes...' : 'Loading two-page plot data...'}</p>{/if}
  {#if profilingOpen && profileSource}
    <p role="status" class="text-xs font-semibold text-[#003366]">Plot {owner.plot} — Plot Profiling</p>
    <TwoPageProfilingPanel contextId={owner.contextId} project={owner.project} plot={owner.plot} {form}
      projectPath={vegetationScope.projectPath} su={vegetationScope.su} suPath={vegetationScope.suPath}
      profileSource={profileSource} onBusyChange={value => profilingBusy = value} />
    <div class="flex flex-wrap gap-2">
      <button type="button" class="rounded border border-[#D8D8D8] bg-white px-3 py-1.5 text-xs text-[#313132]" disabled={profilingBusy} onclick={returnFromProfiling}>Back to Two-Page Form</button>
      {#if onOpenProfileSU}
        <button type="button" data-two-page-create-su-link
          class="rounded bg-[#003366] px-3 py-1.5 text-xs font-medium text-white disabled:opacity-50"
          disabled={profilingBusy || childBlocked || close.unsaved || close.busy || close.blocked}
          onclick={onOpenProfileSU}>
          Open Plot Profiling / Create SU from Filter
        </button>
      {/if}
    </div>
  {:else if projectMetadataOpen === 'edit'}
    <p role="status" class="text-xs font-semibold text-[#003366]">Plot {owner.plot} — Project Metadata</p>
    {#if metadataClient}
      <ProjectMetadataEditor bind:this={metadataEditor} client={metadataClient} contextId={owner.contextId} plot={owner.plot}
        allowRestoration={metadataRestore} onbusy={value => projectMetadataBusy = value}
        onclosed={() => { projectMetadataOpen = null; error = null; onchange(); }}
        oncommitted={refreshMetadataPeers} />
    {:else}
      <p role="alert">The owned context-bound metadata client is unavailable. No metadata operation can run.</p>
    {/if}
  {:else if projectMetadataOpen === 'read'}
    <p role="status" class="text-xs font-semibold text-[#003366]">Plot {owner.plot} — Project Metadata</p>
    <TwoPageProjectMetadataPanel contextId={owner.contextId} project={owner.project} plot={owner.plot} {form}
      projectPath={vegetationScope.projectPath} su={vegetationScope.su} suPath={vegetationScope.suPath}
      onEditMetadata={metadataEditingEnabled ? switchReadMetadataToEdit : undefined}
      editDisabled={!canSwitchToMetadataEdit()}
      onBusyChange={value => projectMetadataBusy = value} />
    <button type="button" class="rounded border border-stone-300 bg-white px-3 py-1 text-xs font-medium text-stone-800 hover:bg-stone-50 disabled:opacity-50" disabled={projectMetadataBusy} onclick={returnFromProjectMetadata}>Back to Two-Page Form</button>
  {:else if environmentTableOpen}
    <p role="status" class="text-xs font-semibold text-[#003366]">Plot {owner.plot} — Environment Table</p>
    <TwoPageEnvironmentTablePanel contextId={owner.contextId} project={owner.project} plot={owner.plot} {form}
      projectPath={vegetationScope.projectPath} su={vegetationScope.su} suPath={vegetationScope.suPath}
      onBusyChange={value => environmentTableBusy = value} />
    <button type="button" class="rounded border border-stone-300 bg-white px-3 py-1 text-xs font-medium text-stone-800 hover:bg-stone-50 disabled:opacity-50" disabled={environmentTableBusy} onclick={returnFromEnvironmentTable}>Back to Two-Page Form</button>
  {:else if vegetationTableOpen}
    <p role="status" class="text-xs font-semibold text-[#003366]">Plot {owner.plot} — Vegetation Table</p>
    <TwoPageVegetationTablePanel contextId={owner.contextId} project={owner.project} plot={owner.plot} {form}
      projectPath={vegetationScope.projectPath} su={vegetationScope.su} suPath={vegetationScope.suPath}
      onBusyChange={value => vegetationTableBusy = value} />
    <button type="button" class="rounded border border-stone-300 bg-white px-3 py-1 text-xs font-medium text-stone-800 hover:bg-stone-50 disabled:opacity-50" disabled={vegetationTableBusy} onclick={returnFromVegetationTable}>Back to Two-Page Form</button>
  {:else if googleEarthOpen}
    <p role="status" class="text-xs font-semibold text-[#003366]">Plot {owner.plot} — Google Earth KML</p>
    <TwoPageGoogleEarthPanel contextId={owner.contextId} project={owner.project} projectPath={googleEarthPath} plot={owner.plot} {form}
      onBusyChange={value => googleEarthBusy = value} />
    <button type="button" class="rounded border border-stone-300 bg-white px-3 py-1 text-xs font-medium text-stone-800 hover:bg-stone-50 disabled:opacity-50" disabled={googleEarthBusy} onclick={returnFromGoogleEarth}>Back to Two-Page Form</button>
  {:else if auditOpen}
    <p role="status" class="text-xs font-semibold text-[#003366]">Plot {owner.plot} — Audit Trail</p>
    <TwoPageAuditPanel contextId={owner.contextId} project={owner.project} plot={owner.plot} {form}
      onRestored={async () => { await session.load(); await refreshMetadataPeers(); }}
      onBusyChange={value => auditBusy = value} />
    <button type="button" class="rounded border border-stone-300 bg-white px-3 py-1 text-xs font-medium text-stone-800 hover:bg-stone-50 disabled:opacity-50" disabled={auditBusy} onclick={returnFromAudit}>Back to Two-Page Form</button>
  {:else if externalOpen && sourceScope?.projectPath && sourceScope.suPath}
    <p role="status" class="text-xs font-semibold text-[#003366]">Site Unit Transfer ({owner.plot})</p>
    <ExternalSUEnvironmentTransfer bind:this={externalEditor} contextId={sourceScope.contextId}
      project={sourceScope.project} projectPath={sourceScope.projectPath} su={sourceScope.su} suPath={sourceScope.suPath}
      onclosed={() => { void returnFromExternalTransfer(); }} />
    {#if sourceRefreshing}<p role="status">Refreshing plot fields after transfer...</p>{/if}
  {:else}
  <div class="two-page-split-wrap" class:split-open={fieldCardSplitOpen && twoPageFieldCardViewModel !== null}>
    <div class="two-page-form-col min-w-0 flex-1" data-field-card-form-pane>
      {#if view.original && view.snapshot}
        <TwoPageEntryLayout {form} {pictureReaderAvailable} values={twoPageEntryValues(view.original, form)}
          editors={(['xl', 'common', 'extra'] as const).map(scope => ({
            scope, columns: projection.fields.filter(field => field.scope === scope && field.page !== null).map(field => field.column),
            input: fieldInput, labelled: true,
          }))} identity={identityField} embedded={childContent} />
      {/if}
      <p class="mt-3 text-xs text-stone-600">Saves all Site, Location, and Soil summary fields on this two-page card together. Soil horizons and Vegetation layers save in their own sections below.</p>
    </div>
    {#if fieldCardSplitOpen && twoPageFieldCardViewModel}
      <div class="two-page-dock-col">
        <FieldCardPreviewModal
          open={true}
          mode="docked"
          viewModel={twoPageFieldCardViewModel}
          onclose={() => { fieldCardSplitOpen = false; }}
          onmodechange={(nextMode) => {
            if (nextMode === 'modal') {
              fieldCardSplitOpen = false;
              fieldCardModalOpen = true;
            }
          }}
        />
      </div>
    {/if}
  </div>
  {/if}
  {#if fieldCardModalOpen && twoPageFieldCardViewModel}
    <FieldCardPreviewModal
      open={true}
      mode="modal"
      viewModel={twoPageFieldCardViewModel}
      onclose={() => { fieldCardModalOpen = false; }}
      onmodechange={(nextMode) => {
        if (nextMode === 'docked') {
          fieldCardModalOpen = false;
          fieldCardSplitOpen = true;
        }
      }}
    />
  {/if}
</section>

{#snippet identityField(field: TwoPageEntryField)}
  <label class="block text-sm font-medium text-[#003366]" for="complete-entry-identity">Plot number</label>
  <input id="complete-entry-identity" class="two-page-plot-id w-full rounded border p-2" disabled
    data-column={field.column} data-help-id="site.plot_number" value={owner.plot} />
{/snippet}

{#snippet fieldInput(control: PaperControl, _position: string)}
  {#if view.original && view.snapshot && control.column}
    {@const column = control.column}
    {@const colLower = column.toLowerCase()}
    {@const helpId = colLower === 'moistureregime' ? 'site.moisture_regime'
      : colLower === 'nutrientregime' ? 'site.nutrient_regime'
      : colLower === 'zone' || colLower === 'subzone' || colLower === 'siteseries' || colLower === 'becsiteunit' || colLower === 'usersiteunit' ? 'site.bgc_zone'
      : colLower === 'ecosection' || colLower === 'fsregiondistrict' ? 'site.ecosection'
      : colLower === 'latitude' || colLower === 'longitude' || colLower === 'utmzone' || colLower === 'utmeasting' || colLower === 'utmnorthing' ? 'site.coordinates'
      : colLower === 'elevation' || colLower === 'slopegradient' || colLower === 'aspect' ? 'site.elevation'
      : colLower === 'mesoslopeposition' || colLower === 'surfaceshape' ? 'site.meso_slope'
      : colLower.startsWith('substrate') ? 'site.substrate_cover'
      : colLower === 'structuralstage' || colLower === 'successionalstatus' ? 'site.successional_structural'
      : colLower === 'realmclass' || colLower === 'snowcoverregime' || colLower === 'activelayerdepth' ? 'site.realm_class'
      : colLower === 'humusform' ? 'humus.humus_form'
      : colLower === 'rootingdepth' || colLower === 'rootrestrictingtype' || colLower === 'rootrestrictingdepth' || colLower === 'seepagedepth' || colLower === 'soildrainage' ? 'soil.rooting_seepage'
      : 'site.plot_number'}
    {@const policy = view.snapshot.Policies.find(field => field.column === column)}
    {@const draft = view.drafts[column]}
    {@const originalCell = twoPageEntryCell(view.original, column)}
    {@const nullBlocked = (column === 'SV_FloodPlain' || column === 'SpeciesListComplete') && originalCell.storage !== 'null'}
    {@const value = draft?.value ?? originalCell}
    {@const raw = draft?.input.kind === 'text' ? draft.input.raw : value.storage === 'null' ? '' : metadataCellText(value)}
    {@const reference = view.snapshot.Fields.find(field => field.column === column)}
    {@const id = `complete-entry-${column}`}
    {@const unavailable = !editingEnabled || close.busy || view.blocked || childBlocked && !draft || column === 'BECSiteUnit' && !view.snapshot.MasterEditingAvailable}
    <div class="min-w-0 space-y-1" data-two-page-entry-field={column} data-source-control={control.controlId} data-help-id={helpId}>
      <label class="block text-sm font-medium" for={id}>{controlLabel(control, true)}</label>
      {#if column === 'ProjectID'}
        <select {id} class="w-full rounded border p-2" value={view.projectRowId ?? ''}
          disabled={unavailable || !view.snapshot.ProjectAssignmentAvailable}
          onchange={event => selectProject(event.currentTarget.value || null)}>
          <option value="">Keep original ({value.storage === 'null' ? 'NULL' : raw})</option>
          {#each view.snapshot.ProjectChoices.Choices.rows as row (row.rowId)}
            {@const code = row.cells[0]}
            {@const title = row.cells[1]}
            <option value={row.rowId} disabled={code.storage !== 'text' || !code.text || code.text.length > 30}>
              {metadataCellText(code)} — {title.storage === 'null' ? '(NULL title)' : title.text === '' ? '(empty title)' : metadataCellText(title)} [row {row.rowId}]
            </option>
          {/each}
        </select>
        {#if !view.snapshot.ProjectAssignmentAvailable}<p role="status" class="text-xs">{view.snapshot.ProjectAssignmentDiagnostic}</p>{/if}
      {:else if policy?.kind === 'boolean'}
        {@const selected = value.storage === 'null' ? '' : value.integer === '-1' ? 'true' : value.integer === '0' ? 'false' : 'historical'}
        <select {id} class="w-full rounded border p-2" value={selected} disabled={unavailable}
          onchange={event => stage(column, event.currentTarget.value === '' ? { kind: 'clear' }
            : { kind: 'boolean', value: event.currentTarget.value === 'true' })}>
          <option value="" disabled={nullBlocked}>{column === 'SV_FloodPlain' || column === 'SpeciesListComplete' ? 'Retain historical NULL' : 'NULL'}</option><option value="true">Yes</option><option value="false">No</option>
          {#if selected === 'historical'}<option value="historical" disabled>Historical {raw}</option>{/if}
        </select>
      {:else if policy?.kind === 'option'}
        {@const selected = value.storage === 'null' ? '' : value.text === '1' || value.text === '2' ? value.text : 'historical'}
        {@const options = twoPageParentCommonFields(form).find(field => field.column === column)?.options ?? []}
        <select {id} class="w-full rounded border p-2" value={selected} disabled={unavailable}
          onchange={event => stage(column, { kind: 'option', option: event.currentTarget.value === '' ? null : Number(event.currentTarget.value) })}>
          <option value="">NULL</option>
          {#each options as option}<option value={String(option.value)}>{option.label}</option>{/each}
          {#if selected === 'historical'}<option value="historical" disabled>Historical {raw}</option>{/if}
        </select>
      {:else if wideControl(control)}
        <textarea {id} class="w-full rounded border p-2" rows="3" value={raw} disabled={unavailable}
          aria-invalid={Boolean(draft?.error)} aria-describedby={draft?.error ? `${id}-error` : undefined}
          oninput={event => stage(column, { kind: 'text', raw: event.currentTarget.value })}></textarea>
      {:else}
        <input {id} class="w-full rounded border p-2" type="text" value={raw} disabled={unavailable}
          list={reference?.available ? `${id}-choices` : undefined}
          aria-invalid={Boolean(draft?.error)} aria-describedby={draft?.error ? `${id}-error` : undefined}
          oninput={event => stage(column, { kind: 'text', raw: event.currentTarget.value })} />
        {#if reference?.available}
          <datalist id={`${id}-choices`}>
            {#each referenceChoices(reference).filter(choice => choice.selectable && choice.code !== null) as choice (JSON.stringify([choice.rowId, choice.code, choice.description]))}
              <option value={choice.code ?? ''}>{choice.description === null ? '(NULL description)' : choice.description}</option>
            {/each}
          </datalist>
        {/if}
      {/if}
      {#if column !== 'ProjectID'}
        <div class="flex flex-wrap gap-2 text-xs">
          <button type="button" disabled={unavailable || nullBlocked} onclick={() => stage(column, { kind: 'clear' })}>Clear to NULL</button>
          <button type="button" disabled={unavailable} onclick={() => stage(column, { kind: 'original' })}>Keep original</button>
          {#if column === 'Latitude'}
            <button type="button" data-two-page-coord-toggle
              onclick={() => { coordHelperOpen = !coordHelperOpen; }}>
              {coordHelperOpen ? 'Close DD/DM/DMS/UTM' : 'Coordinate Modes (DM/DMS/UTM)'}
            </button>
          {/if}
        </div>
      {/if}
      {#if column === 'Latitude' && coordHelperOpen}
        <CoordinateHelper
          idPrefix="two-page"
          variant="two-page"
          disabled={unavailable}
          onApplyUTM={(projected) => {
            stage('Latitude', { kind: 'text', raw: String(projected.latitude) });
            stage('Longitude', { kind: 'text', raw: String(projected.longitude) });
            const snap = view.snapshot;
            if (snap?.Fields.some(f => f.column === 'UTMZone')) stage('UTMZone', { kind: 'text', raw: String(projected.zone) });
            if (snap?.Fields.some(f => f.column === 'UTMEasting')) stage('UTMEasting', { kind: 'text', raw: String(projected.easting) });
            if (snap?.Fields.some(f => f.column === 'UTMNorthing')) stage('UTMNorthing', { kind: 'text', raw: String(projected.northing) });
          }}
          onApplyAxis={(axis, dd) => {
            stage(axis === 'latitude' ? 'Latitude' : 'Longitude', { kind: 'text', raw: String(dd) });
          }}
        />
      {/if}
      {#if column === 'SV_FloodPlain' || column === 'SpeciesListComplete'}<p class="text-xs">Source Yes/No converts NULL to No; choose No explicitly. Unchanged historical NULL is retained.</p>{/if}
      {#if draft?.error}<p id={`${id}-error`} role="alert" class="text-xs text-red-700">{draft.error}</p>{/if}
      {#if reference && !reference.available}<p role="status" class="text-xs">{reference.diagnostic}</p>{/if}
      {#if column === 'BECSiteUnit' && !view.snapshot.MasterEditingAvailable}
        <p role="status" class="text-xs">The owned current user is not authorized to change Master site units.</p>
      {/if}
      {#if view.advisories[column]}
        <p class="text-xs">{view.advisories[column]}</p>
        <button type="button" disabled={unavailable} onclick={() => acknowledge(column)}>Acknowledge literal {column}</button>
      {/if}
    </div>
  {/if}
{/snippet}

<style>
  .two-page-entry-shell { border-color: var(--vpro-border, #d1d5db); border-top: 3px solid var(--vpro-gold, #fcba19); }
  .two-page-plot-id { font-family: var(--vpro-font-mono, monospace); font-variant-numeric: tabular-nums; font-weight: 600; border-color: var(--vpro-forest-border, #D8D8D8); }
  .two-page-split-wrap { display: flex; gap: 1rem; align-items: flex-start; min-width: 0; }
  .two-page-dock-col { width: min(46%, 700px); min-width: 500px; max-height: 85vh; flex: none; position: sticky; top: .5rem; }
  @media (max-width: 1759px) {
    .two-page-dock-btn { display: none; }
    .two-page-dock-col { display: none; }
  }
</style>
