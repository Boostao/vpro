import type { Snippet } from 'svelte';
import { metadataCellText } from '../admin/projectMetadataEditor';
import type { EditorCloseState } from '../shell/closeLifecycle';
import { formatError } from '../shared/readRequests';
import type { bindContextPlots } from '../shared/contextPlots';
import type { ProjectSUScope as GoogleEarthScope } from '../shared/scope';
import { externalSUEnvironmentSession } from '../classification/externalSUEnvironment';
import { buildFieldCardViewModel, type FieldCardViewModel } from './fieldCardPreview';
import type { PaperControl } from './paperLayout';
import type { TwoPageParentForm } from './twoPageParentSession';
import type { TwoPageEntryChild } from './twoPageEntryProjection';
import { twoPageEntryCell, type TwoPageEntrySession, type TwoPageEntrySessionCache } from './twoPageEntrySession';

type TwoPageEntryView = ReturnType<TwoPageEntrySession['view']>;

export interface TwoPageEntryProps {
  contextId: string;
  project: string;
  plot: string;
  cache: TwoPageEntrySessionCache;
  revision: number;
  onchange: () => void;
  onbusy: (busy: boolean) => void;
  onclosed: () => void;
  oncommitted: () => Promise<void>;
  embedded: Snippet<[TwoPageEntryChild, PaperControl]>;
  childBlocked?: boolean;
  pictureReaderAvailable?: boolean;
  auditReaderAvailable?: boolean;
  googleEarthReaderAvailable?: boolean;
  sourceProjectPath?: string;
  vegetationTableReaderAvailable?: boolean;
  environmentTableReaderAvailable?: boolean;
  projectMetadataReaderAvailable?: boolean;
  vegetationTableSU?: string;
  vegetationTableSUPath?: string;
  projectMetadataClient?: ReturnType<typeof bindContextPlots>;
  metadataRestorationAvailable?: boolean;
  profilingReaderAvailable?: boolean;
  profilingSource?: { name: string; path: string } | null;
  externalScope?: GoogleEarthScope | null;
  sourceBlocked?: boolean;
  initialForm?: TwoPageParentForm;
  standalone?: boolean;
  onExtendedShrubsChange?: (enabled: boolean) => void;
  onOpenProfileSU?: () => void;
}

export function buildTwoPageFieldCard(
  active: boolean,
  plot: string,
  form: TwoPageParentForm,
  view: TwoPageEntryView,
  isDirty: boolean
): FieldCardViewModel | null {
  if (!active) return null;
  let projectChoiceText: string | null = null;
  if (view.projectRowId && view.snapshot?.ProjectChoices?.Choices?.rows) {
    const codeCell = view.snapshot.ProjectChoices.Choices.rows.find((r) => r.rowId === view.projectRowId)?.cells?.[0];
    if (codeCell && codeCell.storage !== 'null') projectChoiceText = metadataCellText(codeCell);
  }
  return buildFieldCardViewModel({
    formKind: 'two-page',
    draftHeader: { plotNumber: plot },
    twoPageOriginal: view.original ?? null,
    twoPageDrafts: view.drafts,
    twoPageProjectText: projectChoiceText,
    extendedShrubs: form === 'FS882-8x6XL-CHARS',
    isDirty,
  });
}

export interface TwoPageReadersDeps {
  owner: { contextId: string; project: string; plot: string };
  sessions: Map<TwoPageParentForm, TwoPageEntrySession>;
  metadataClient: ReturnType<typeof bindContextPlots> | undefined;
  metadataRestore: boolean;
  sourceScope: GoogleEarthScope | null | undefined;
  profileSource: { name: string; path: string } | null;
  vegetationScope: { projectPath: string; su: string; suPath: string };
  googleEarthPath: string;
  getForm: () => TwoPageParentForm;
  getSession: () => TwoPageEntrySession;
  getView: () => TwoPageEntryView;
  getDraftState: () => EditorCloseState;
  getSourceBlocked: () => boolean;
  getChildBlocked: () => boolean;
  getAvailabilities: () => {
    profiling: boolean;
    projectMetadata: boolean;
    environmentTable: boolean;
    vegetationTable: boolean;
    googleEarth: boolean;
    audit: boolean;
  };
  setError: (msg: string | null) => void;
  onchange: () => void;
  oncommitted: () => Promise<void>;
  openMetadataEditor: () => void;
}

export function createTwoPageEntryReaders(deps: TwoPageReadersDeps) {
  const externalSession = deps.sourceScope ? externalSUEnvironmentSession(deps.sourceScope) : null;
  let externalOpen = $state(Boolean(externalSession?.view().blocked));
  let auditOpen = $state(false);
  let auditBusy = $state(false);
  let googleEarthOpen = $state(false);
  let googleEarthBusy = $state(false);
  let vegetationTableOpen = $state(false);
  let vegetationTableBusy = $state(false);
  let environmentTableOpen = $state(false);
  let environmentTableBusy = $state(false);
  let projectMetadataOpen = $state<'read' | 'edit' | null>(null);
  let projectMetadataBusy = $state(false);
  let metadataEditor = $state<{ getCloseState(): EditorCloseState; undo(): void }>();
  let profilingOpen = $state(false);
  let profilingBusy = $state(false);
  let sourceRefreshing = $state(false);
  let externalEditor = $state<{ getCloseState(): EditorCloseState; undo(): void }>();

  const anyOpen = $derived(
    externalOpen ||
      auditOpen ||
      googleEarthOpen ||
      vegetationTableOpen ||
      environmentTableOpen ||
      Boolean(projectMetadataOpen) ||
      profilingOpen
  );
  const anyBusy = $derived(
    sourceRefreshing ||
      auditBusy ||
      googleEarthBusy ||
      vegetationTableBusy ||
      environmentTableBusy ||
      projectMetadataBusy ||
      profilingBusy
  );
  const visible = $derived(
    (profilingOpen && Boolean(deps.profileSource)) ||
      projectMetadataOpen === 'edit' ||
      projectMetadataOpen === 'read' ||
      environmentTableOpen ||
      vegetationTableOpen ||
      googleEarthOpen ||
      auditOpen ||
      Boolean(externalOpen && deps.sourceScope?.projectPath && deps.sourceScope.suPath)
  );

  function hasPeerError(): boolean {
    return [...deps.sessions.values()].some((peer) => Boolean(peer.view().error || peer.view().referenceError));
  }
  function vegScopeInvalid(): boolean {
    const s = deps.vegetationScope;
    return !s.projectPath || !s.su || (s.su !== 'None' && !s.suPath);
  }
  function draftOrChildBlocked(): boolean {
    const d = deps.getDraftState();
    return (
      deps.getSourceBlocked() ||
      deps.getChildBlocked() ||
      d.unsaved ||
      d.busy ||
      d.blocked ||
      Boolean(d.error) ||
      hasPeerError()
    );
  }

  function assertParentFree(mode: 'operation' | 'field' | 'project' | 'literal') {
    const suffix =
      mode === 'operation'
        ? ''
        : mode === 'field'
          ? ' owns the parent; no field was staged.'
          : mode === 'project'
            ? ' owns the parent; no ProjectID was staged.'
            : ' owns the parent; no literal draft was acknowledged.';
    if (mode === 'operation') {
      if (profilingOpen) throw new Error('Finish the owned profile review before parent operations.');
      if (projectMetadataOpen) throw new Error('Finish the owned project metadata review before parent operations.');
      if (environmentTableOpen) throw new Error('Finish the owned environment table review before parent operations.');
      if (vegetationTableOpen) throw new Error('Finish the owned vegetation table review before parent operations.');
      if (googleEarthOpen) throw new Error('Finish the owned saved-plot KML review before parent operations.');
      if (auditOpen) throw new Error('Finish the owned source audit review before parent operations.');
      if (externalOpen)
        throw new Error('Finish the retained source transfer and explicit refresh before parent operations.');
      return;
    }
    if (profilingOpen) throw new Error(`Plot Profiling${suffix}`);
    if (projectMetadataOpen) throw new Error(`Project metadata${suffix}`);
    if (environmentTableOpen) throw new Error(`Environment table${suffix}`);
    if (vegetationTableOpen) throw new Error(`Vegetation table${suffix}`);
    if (googleEarthOpen) throw new Error(`Saved-plot KML${suffix}`);
    if (auditOpen) throw new Error(`Source audit${suffix}`);
    if (externalOpen) throw new Error(`Source transfer${suffix}`);
  }

  async function refreshMetadataPeers() {
    await deps.oncommitted();
    for (const peer of deps.sessions.values()) {
      if (!peer.view().original && !peer.view().error && !peer.view().referenceError) continue;
      const state = peer.closeState();
      if (state.unsaved || state.busy || state.blocked || !(await peer.load())) {
        throw new Error(
          peer.view().error ??
            peer.view().referenceError ??
            'A complete-entry metadata peer could not refresh; no write was replayed.'
        );
      }
    }
  }

  function openProfiling() {
    if (
      !deps.getAvailabilities().profiling ||
      !deps.profileSource?.name ||
      deps.profileSource.name === 'None' ||
      !deps.profileSource.path ||
      vegScopeInvalid() ||
      draftOrChildBlocked()
    ) {
      deps.setError(
        'Resolve source-variant and linked-child drafts, references and retained outcomes; select an explicit owned profile before Plot Profiling.'
      );
      return;
    }
    deps.setError(null);
    profilingOpen = true;
    deps.onchange();
  }
  function returnFromProfiling() {
    if (profilingBusy) {
      deps.setError('Wait for or cancel the owned profile read before returning to the source form.');
      return;
    }
    profilingOpen = false;
    deps.setError(null);
    deps.onchange();
  }
  function openProjectMetadata() {
    if (!deps.getAvailabilities().projectMetadata || vegScopeInvalid() || draftOrChildBlocked()) {
      deps.setError(
        'Resolve all source-variant and linked-child drafts, references and retained outcomes before project metadata review.'
      );
      return;
    }
    deps.setError(null);
    projectMetadataOpen = 'read';
    deps.onchange();
  }
  function returnFromProjectMetadata() {
    if (projectMetadataOpen !== 'read') {
      deps.setError('Return is limited to saved-data metadata review; finish editing in its owned editor.');
      return;
    }
    if (projectMetadataBusy) {
      deps.setError('Wait for or cancel the owned project metadata read before returning to the source form.');
      return;
    }
    projectMetadataOpen = null;
    deps.setError(null);
    deps.onchange();
  }
  function canSwitchToMetadataEdit(): boolean {
    const view = deps.getView();
    const states = [...deps.sessions.values()].map((owned) => owned.closeState());
    if (
      !deps.metadataClient ||
      deps.getSourceBlocked() ||
      deps.getChildBlocked() ||
      !view.original ||
      projectMetadataBusy ||
      externalOpen ||
      auditOpen ||
      googleEarthOpen ||
      vegetationTableOpen ||
      environmentTableOpen ||
      profilingOpen ||
      states.some((s) => s.unsaved || s.busy || s.blocked) ||
      hasPeerError()
    )
      return false;
    const projectId = twoPageEntryCell(view.original, 'ProjectID');
    return projectId.storage === 'text' && projectId.text !== null && projectId.text.length > 0;
  }
  function switchReadMetadataToEdit() {
    if (projectMetadataBusy) {
      deps.setError('Wait for or cancel the owned project metadata read before switching to edit.');
      return;
    }
    projectMetadataOpen = null;
    deps.openMetadataEditor();
  }
  function openEnvironmentTable() {
    if (!deps.getAvailabilities().environmentTable || vegScopeInvalid() || draftOrChildBlocked()) {
      deps.setError(
        'Resolve all source-variant and linked-child drafts, references and retained outcomes before View Env Table.'
      );
      return;
    }
    deps.setError(null);
    environmentTableOpen = true;
    deps.onchange();
  }
  function returnFromEnvironmentTable() {
    if (environmentTableBusy) {
      deps.setError('Wait for or cancel the owned environment table read before returning to the source form.');
      return;
    }
    environmentTableOpen = false;
    deps.setError(null);
    deps.onchange();
  }
  function openVegetationTable() {
    if (!deps.getAvailabilities().vegetationTable || vegScopeInvalid() || draftOrChildBlocked()) {
      deps.setError(
        'Resolve all source-variant and linked-child drafts, references and retained outcomes before View Veg Table.'
      );
      return;
    }
    deps.setError(null);
    vegetationTableOpen = true;
    deps.onchange();
  }
  function returnFromVegetationTable() {
    if (vegetationTableBusy) {
      deps.setError('Wait for or cancel the owned vegetation table read before returning to the source form.');
      return;
    }
    vegetationTableOpen = false;
    deps.setError(null);
    deps.onchange();
  }
  function openGoogleEarth() {
    if (!deps.getAvailabilities().googleEarth || !deps.googleEarthPath || draftOrChildBlocked()) {
      deps.setError(
        'Resolve all source-variant and linked-child drafts, references and retained outcomes before saved-plot KML.'
      );
      return;
    }
    deps.setError(null);
    googleEarthOpen = true;
    deps.onchange();
  }
  function returnFromGoogleEarth() {
    if (googleEarthBusy) {
      deps.setError('Wait for or cancel the owned saved-plot read before returning to the source form.');
      return;
    }
    googleEarthOpen = false;
    deps.setError(null);
    deps.onchange();
  }
  function openAudit() {
    if (!deps.getAvailabilities().audit || draftOrChildBlocked()) {
      deps.setError(
        'Resolve all source-variant and linked-child drafts, references and retained outcomes before Audit.'
      );
      return;
    }
    deps.setError(null);
    auditOpen = true;
    deps.onchange();
  }
  function returnFromAudit() {
    if (auditBusy) {
      deps.setError('Wait for or cancel the owned audit read before returning to the source form.');
      return;
    }
    auditOpen = false;
    deps.setError(null);
    deps.onchange();
  }
  function openExternalTransfer() {
    const s = deps.sourceScope;
    if (
      !externalSession ||
      !s?.projectPath ||
      !s.suPath ||
      s.contextId !== deps.owner.contextId ||
      s.project !== deps.owner.project ||
      draftOrChildBlocked()
    ) {
      deps.setError(
        'Resolve all source-variant and linked-child drafts, references and retained outcomes before SU Into Env.'
      );
      return;
    }
    try {
      externalSession.reviewSourceForm(deps.getForm());
      deps.setError(null);
      externalOpen = true;
      deps.onchange();
    } catch (cause) {
      deps.setError(`Source reverse transfer unavailable; owned state retained: ${formatError(cause)}`);
    }
  }
  async function returnFromExternalTransfer() {
    if (
      sourceRefreshing ||
      !externalEditor ||
      externalEditor.getCloseState().unsaved ||
      externalEditor.getCloseState().busy
    ) {
      deps.setError('Finish the retained transfer before refreshing the source form; never replay.');
      return;
    }
    sourceRefreshing = true;
    deps.setError(null);
    deps.onchange();
    try {
      await deps.oncommitted();
      const active = deps.getSession();
      for (const peer of deps.sessions.values()) {
        if (peer !== active && !peer.view().original) continue;
        const state = peer.closeState();
        if (state.unsaved || state.busy || state.blocked || !(await peer.load())) {
          throw new Error(
            peer.view().error ?? peer.view().referenceError ?? 'A complete-entry source variant could not refresh.'
          );
        }
      }
      externalOpen = false;
    } catch (cause) {
      deps.setError(
        `Source refresh failed; retain the immutable transfer receipt and retry Return, never replay: ${formatError(cause)}`
      );
    } finally {
      sourceRefreshing = false;
      deps.onchange();
    }
  }

  return {
    get externalOpen() {
      return externalOpen;
    },
    get auditOpen() {
      return auditOpen;
    },
    get auditBusy() {
      return auditBusy;
    },
    set auditBusy(v: boolean) {
      auditBusy = v;
    },
    get googleEarthOpen() {
      return googleEarthOpen;
    },
    get googleEarthBusy() {
      return googleEarthBusy;
    },
    set googleEarthBusy(v: boolean) {
      googleEarthBusy = v;
    },
    get vegetationTableOpen() {
      return vegetationTableOpen;
    },
    get vegetationTableBusy() {
      return vegetationTableBusy;
    },
    set vegetationTableBusy(v: boolean) {
      vegetationTableBusy = v;
    },
    get environmentTableOpen() {
      return environmentTableOpen;
    },
    get environmentTableBusy() {
      return environmentTableBusy;
    },
    set environmentTableBusy(v: boolean) {
      environmentTableBusy = v;
    },
    get projectMetadataOpen() {
      return projectMetadataOpen;
    },
    set projectMetadataOpen(v: 'read' | 'edit' | null) {
      projectMetadataOpen = v;
    },
    get projectMetadataBusy() {
      return projectMetadataBusy;
    },
    set projectMetadataBusy(v: boolean) {
      projectMetadataBusy = v;
    },
    get metadataEditor() {
      return metadataEditor;
    },
    set metadataEditor(v: { getCloseState(): EditorCloseState; undo(): void } | undefined) {
      metadataEditor = v;
    },
    get profilingOpen() {
      return profilingOpen;
    },
    get profilingBusy() {
      return profilingBusy;
    },
    set profilingBusy(v: boolean) {
      profilingBusy = v;
    },
    get sourceRefreshing() {
      return sourceRefreshing;
    },
    get externalEditor() {
      return externalEditor;
    },
    set externalEditor(v: { getCloseState(): EditorCloseState; undo(): void } | undefined) {
      externalEditor = v;
    },
    get anyOpen() {
      return anyOpen;
    },
    get anyBusy() {
      return anyBusy;
    },
    get visible() {
      return visible;
    },
    metadataClient: deps.metadataClient,
    metadataRestore: deps.metadataRestore,
    sourceScope: deps.sourceScope,
    profileSource: deps.profileSource,
    vegetationScope: deps.vegetationScope,
    googleEarthPath: deps.googleEarthPath,
    vegScopeInvalid,
    draftOrChildBlocked,
    assertParentFree,
    refreshMetadataPeers,
    openProfiling,
    returnFromProfiling,
    openProjectMetadata,
    returnFromProjectMetadata,
    canSwitchToMetadataEdit,
    switchReadMetadataToEdit,
    openEnvironmentTable,
    returnFromEnvironmentTable,
    openVegetationTable,
    returnFromVegetationTable,
    openGoogleEarth,
    returnFromGoogleEarth,
    openAudit,
    returnFromAudit,
    openExternalTransfer,
    returnFromExternalTransfer,
  };
}

export type TwoPageEntryReadersController = ReturnType<typeof createTwoPageEntryReaders>;
