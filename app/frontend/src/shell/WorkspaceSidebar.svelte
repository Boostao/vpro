<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { Download, FolderOpen, KeyRound, Lock, Plus, Trash2, Unlock, Upload } from '@lucide/svelte';
  import {
    ContextService,
    ImportExportService,
    type AttachableFileInspection,
  } from '../../bindings/github.com/boostao/vpro/app';
  import type { SessionSummary } from '../../bindings/github.com/boostao/vpro/app/internal/auth/models';
  import type { VPro64ExportOutcome } from '../../bindings/github.com/boostao/vpro/app/internal/interchange/models';
  import type {
    ContextSelection,
    CreateWorkspaceResourceRequest,
    EditLockState,
  } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
  import type { AccessImportProgressPayload } from '../interchange/interchangeHub';
  import { ReadRequests } from '../shared/readRequests';
  import { projectState, webShellRuntime } from '../shared/state';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import { notifications } from './notificationService.svelte';
  import {
    computeAccessProgressPercent,
    extractAttachCandidates,
    formatSidebarErrorOp,
    isCancelledAccessErrorOp,
    requiresAccessConversion,
    runAttachWorkspaceResourceOp,
    runCreateWorkspaceResourceOp,
    runExportVPro64Op,
    runUnattachWorkspaceResourceOp,
    workspaceKindLabel,
    type AttachCandidateItem,
    type WorkspaceResourceKind,
  } from './workspaceSidebarOps';

  let {
    busy,
    editorBusy,
    companionPanelBusy,
    transitionWorking,
    requestTransition,
    switchContext,
    onAccessActivated,
    onOpenAuthSignIn,
    subscribeAccessProgress,
  }: {
    busy: boolean;
    editorBusy: boolean;
    companionPanelBusy: boolean;
    transitionWorking: boolean;
    requestTransition: (run: (contextId: string) => Promise<void>) => Promise<void>;
    switchContext: (contextId: string, selection: ContextSelection, next: 'plots' | 'hierarchy') => Promise<void>;
    onAccessActivated: () => Promise<void>;
    onOpenAuthSignIn?: () => void;
    subscribeAccessProgress?: (
      handler: (progress: AccessImportProgressPayload) => void
    ) => Promise<() => void> | (() => void);
  } = $props();

  let workspaceWorking = $state(false);
  let sidebarError = $state('');
  let sidebarNotice = $state('');

  // Unified Attach state (handles both .db and .accdb/.mdb auto-convert)
  let pendingAttach = $state<{
    kind: WorkspaceResourceKind;
    inspection: AttachableFileInspection;
    candidates: AttachCandidateItem[];
    selectedName: string;
    requiresConvert: boolean;
  } | null>(null);
  let attachProgressMessage = $state('');
  let attachProgressPhase = $state('');
  let attachProgressRows = $state(0);
  let attachProgressExpectedRows = $state(0);
  let attachElapsedSeconds = $state(0);
  let attachGeneration = 0;
  const attachRequests = new ReadRequests();
  let stopAttachProgress: (() => void) | null = null;
  let attachTimer: ReturnType<typeof setInterval> | null = null;
  const attachProgressPercent = $derived(
    computeAccessProgressPercent(workspaceWorking, attachProgressPhase, attachProgressRows, attachProgressExpectedRows)
  );

  // Remove (Unattach) confirmation state
  let pendingRemove = $state<{
    kind: WorkspaceResourceKind;
    name: string;
    path: string;
  } | null>(null);

  // New resource creation state
  let pendingNew = $state<{
    kind: WorkspaceResourceKind;
    name: string;
    projectTitle: string;
    destinationMode: string;
    filePath: string;
    populatePlots: boolean;
    seedFromUserSu: boolean;
    activate: boolean;
  } | null>(null);

  // VPro64 export state
  let exportingVPro64 = $state(false);
  let lastVPro64Export = $state<VPro64ExportOutcome | null>(null);

  // Auth / Edit-lock summary state
  let authSession = $state<SessionSummary | null>(null);
  let editLockStatus = $state<EditLockState | null>(null);
  let authLoadGen = 0;

  const controlsDisabled = $derived(
    busy || editorBusy || companionPanelBusy || transitionWorking || workspaceWorking || exportingVPro64
  );

  const activeProjectIndex = $derived(
    $projectState?.projects?.findIndex(
      (p) => p.name === $projectState?.activeProject && p.path === $projectState?.projectPath
    ) ?? -1
  );
  const activeSUIndex = $derived(
    $projectState?.sus?.findIndex((su) => su.name === $projectState?.activeSU && su.path === $projectState?.suPath) ??
      -1
  );
  const activeHierarchyIndex = $derived(
    $projectState?.hierarchies?.findIndex(
      (h) => h.name === $projectState?.activeHierarchy && h.path === $projectState?.hierarchyPath
    ) ?? -1
  );

  const activeProjectEntry = $derived(
    activeProjectIndex >= 0 ? ($projectState?.projects?.[activeProjectIndex] ?? null) : null
  );
  const activeSUEntry = $derived(activeSUIndex >= 0 ? ($projectState?.sus?.[activeSUIndex] ?? null) : null);
  const activeHierarchyEntry = $derived(
    activeHierarchyIndex >= 0 ? ($projectState?.hierarchies?.[activeHierarchyIndex] ?? null) : null
  );

  const isSignedIn = $derived(Boolean(authSession?.signedIn || editLockStatus?.signedIn));
  const isDataLocked = $derived(editLockStatus ? editLockStatus.locked : !isSignedIn);
  const authUserLabel = $derived(
    (authSession?.displayName || editLockStatus?.displayName || authSession?.userId || editLockStatus?.userId || '').trim()
  );
  const authRoleLabel = $derived((authSession?.role || editLockStatus?.role || '').trim());

  function clearAttachProgress() {
    if (typeof stopAttachProgress === 'function') {
      const stop = stopAttachProgress;
      stopAttachProgress = null;
      stop();
    }
    if (attachTimer !== null) {
      clearInterval(attachTimer);
      attachTimer = null;
    }
    attachElapsedSeconds = 0;
    attachProgressMessage = '';
    attachProgressPhase = '';
    attachProgressRows = 0;
    attachProgressExpectedRows = 0;
  }

  function cancelAttachOperation(silent = false) {
    const wasWorking = workspaceWorking;
    attachGeneration++;
    attachRequests.cancelAll();
    clearAttachProgress();
    workspaceWorking = false;
    if (!silent && wasWorking) {
      sidebarError = '';
      sidebarNotice = 'File inspection or conversion cancelled.';
    }
  }

  async function startAttachProgress(contextId: string, reqGen: number, expectedRows = 0) {
    clearAttachProgress();
    attachProgressPhase = 'starting';
    attachProgressExpectedRows = expectedRows;
    attachProgressMessage = 'Converting Microsoft Access database to VPro (.db)…';
    if (typeof globalThis.setInterval === 'function') {
      const started = Date.now();
      attachTimer = globalThis.setInterval(() => {
        attachElapsedSeconds = Math.max(1, Math.floor((Date.now() - started) / 1000));
      }, 1000);
    }
    const handler = (raw: AccessImportProgressPayload) => {
      if (!raw || reqGen !== attachGeneration) return;
      if (raw.contextId && raw.contextId !== contextId) return;
      if (typeof raw.phase === 'string') attachProgressPhase = raw.phase;
      if (typeof raw.message === 'string' && raw.message.trim()) {
        attachProgressMessage = raw.message.trim();
      }
      const rows = Number(raw.totalRowsProcessed ?? raw.tableRowsProcessed ?? 0);
      if (Number.isFinite(rows) && rows >= 0) attachProgressRows = rows;
    };
    try {
      if (typeof subscribeAccessProgress === 'function') {
        const off = await subscribeAccessProgress(handler);
        if (reqGen !== attachGeneration) {
          off?.();
          return;
        }
        stopAttachProgress = off;
        return;
      }
      const mod = await import('../interchange/interchangeHub');
      if (reqGen === attachGeneration && typeof mod?.subscribeWailsAccessImportProgress === 'function') {
        stopAttachProgress = mod.subscribeWailsAccessImportProgress(handler);
      }
    } catch {
      // Headless tests may run without runtime event listeners.
    }
  }

  async function refreshAuthStatus() {
    if (IS_WEB_READONLY) return;
    const gen = ++authLoadGen;
    const ctxId = $projectState?.contextId ?? '';
    try {
      const [sess, lock] = await Promise.all([
        typeof ContextService.GetAuthSession === 'function' ? ContextService.GetAuthSession() : Promise.resolve(null),
        ctxId && typeof ContextService.GetEditLockStatus === 'function'
          ? ContextService.GetEditLockStatus(ctxId)
          : Promise.resolve(null),
      ]);
      if (gen !== authLoadGen) return;
      authSession = sess;
      editLockStatus = lock;
    } catch {
      // Non-fatal in minimal test stubs where auth RPCs are not mounted.
    }
  }

  $effect(() => {
    void $projectState?.contextId;
    if (!IS_WEB_READONLY) {
      void refreshAuthStatus();
    }
  });

  onMount(() => {
    if (IS_WEB_READONLY || typeof window === 'undefined') return;
    const onAuthChanged = () => void refreshAuthStatus();
    window.addEventListener('vpro:auth-changed', onAuthChanged);
    return () => {
      window.removeEventListener('vpro:auth-changed', onAuthChanged);
    };
  });

  function selectedContext(): ContextSelection {
    const state = $projectState;
    if (!state?.projectPath) throw new Error('The active project file identity is unavailable.');
    return {
      project: state.activeProject,
      projectPath: state.projectPath,
      su: state.activeSU,
      suPath: state.suPath ?? '',
      hierarchy: state.activeHierarchy,
      hierarchyPath: state.hierarchyPath ?? '',
    };
  }

  async function chooseProject(event: Event) {
    const select = event.currentTarget as HTMLSelectElement;
    const chosen = $projectState?.projects?.[Number(select.value)];
    select.value = String(activeProjectIndex);
    if (!chosen) return;
    await requestTransition(async (contextId) => {
      if (!chosen.path) throw new Error('Choose a project with an explicit file identity.');
      await switchContext(
        contextId,
        { ...selectedContext(), project: chosen.name, projectPath: chosen.path, su: 'None', suPath: '' },
        'plots'
      );
    });
  }

  async function chooseSU(event: Event) {
    const select = event.currentTarget as HTMLSelectElement;
    const chosen = $projectState?.sus?.[Number(select.value)];
    select.value = String(activeSUIndex);
    await requestTransition(async (contextId) => {
      await switchContext(
        contextId,
        { ...selectedContext(), su: chosen?.name ?? 'None', suPath: chosen?.path ?? '' },
        'plots'
      );
    });
  }

  async function chooseHierarchy(event: Event) {
    const select = event.currentTarget as HTMLSelectElement;
    const chosen = $projectState?.hierarchies?.[Number(select.value)];
    select.value = String(activeHierarchyIndex);
    await requestTransition(async (contextId) => {
      await switchContext(
        contextId,
        { ...selectedContext(), hierarchy: chosen?.name ?? 'None', hierarchyPath: chosen?.path ?? '' },
        'hierarchy'
      );
    });
  }

  async function revealInExplorer(target: 'root' | 'projects' | 'project' | 'su' | 'hierarchy') {
    const contextId = $projectState?.contextId;
    if (!contextId) return;
    try {
      const opened = await ContextService.RevealInFileExplorer(contextId, target);
      notifications.push({
        severity: 'info',
        category: 'general',
        source: 'File Explorer',
        title: 'Opened in File Explorer',
        message: opened,
        toast: true,
      });
    } catch (cause) {
      const msg = await formatSidebarErrorOp(cause);
      notifications.push({
        severity: 'error',
        category: 'general',
        source: 'File Explorer',
        title: 'Could not open File Explorer',
        message: msg,
        toast: true,
      });
    }
  }

  async function inspectAttachFile(kind: WorkspaceResourceKind, chosenPath: string) {
    const contextId = $projectState?.contextId;
    if (!contextId || !chosenPath) return;
    attachRequests.cancelAll();
    const reqGen = ++attachGeneration;
    workspaceWorking = true;
    sidebarError = '';
    sidebarNotice = '';
    try {
      const rawRpc = ContextService.InspectAttachableFile(contextId, chosenPath);
      const inspection =
        rawRpc && typeof (rawRpc as { cancel?: unknown }).cancel === 'function'
          ? await attachRequests.track(rawRpc)
          : await rawRpc;
      if (reqGen !== attachGeneration) return;
      const candidates = extractAttachCandidates(kind, inspection);
      const needsConvert = requiresAccessConversion(inspection);
      const compatible = candidates.filter((c) => c.compatible);
      const defaultChoice = compatible[0]?.name ?? candidates[0]?.name ?? '';

      if (!needsConvert && compatible.length === 0) {
        sidebarError = `No compatible ${workspaceKindLabel(kind)} table was found in the selected file.`;
        return;
      }

      if (!needsConvert && compatible.length === 1) {
        workspaceWorking = false;
        await executeAttach(kind, inspection.selectedPath, compatible[0].name, false);
        return;
      }

      // Access conversion ALWAYS asks for confirmation first; multi-table .db files let user pick which table.
      pendingAttach = {
        kind,
        inspection,
        candidates,
        selectedName: defaultChoice,
        requiresConvert: needsConvert,
      };
    } catch (cause) {
      if (reqGen !== attachGeneration || isCancelledAccessErrorOp(cause)) return;
      sidebarError = `Could not inspect file to attach: ${await formatSidebarErrorOp(cause)}`;
    } finally {
      if (reqGen === attachGeneration) workspaceWorking = false;
    }
  }

  async function startAttach(kind: WorkspaceResourceKind) {
    const contextId = $projectState?.contextId;
    if (!contextId || controlsDisabled) return;
    sidebarError = '';
    sidebarNotice = '';
    pendingRemove = null;
    pendingNew = null;
    try {
      const chosenPath = await ContextService.ChooseAttachableFile(contextId, kind);
      if (!chosenPath) return;
      await inspectAttachFile(kind, chosenPath);
    } catch (cause) {
      sidebarError = `Could not select file to attach: ${await formatSidebarErrorOp(cause)}`;
    }
  }

  async function executeAttach(
    kind: WorkspaceResourceKind,
    path: string,
    name: string,
    isAccessConvert: boolean
  ) {
    sidebarError = '';
    sidebarNotice = '';
    const expectedRows = isAccessConvert
      ? (pendingAttach?.inspection.accessInspection?.projects?.find((p) => p.sourceProject === name)?.tables ?? []).reduce(
          (sum, tbl) => sum + (tbl.present ? (tbl.rowCount ?? 0) : 0),
          0
        )
      : 0;
    await requestTransition(async (contextId) => {
      attachRequests.cancelAll();
      const reqGen = ++attachGeneration;
      workspaceWorking = true;
      if (isAccessConvert) {
        await startAttachProgress(contextId, reqGen, expectedRows);
        if (reqGen !== attachGeneration) return;
      }
      try {
        const result = await runAttachWorkspaceResourceOp({
          contextId,
          kind,
          path,
          name,
          activate: true,
          contextService: {
            AttachWorkspaceResource: (ctxId, req) => {
              const rpc = ContextService.AttachWorkspaceResource(ctxId, req);
              if (rpc && typeof (rpc as { cancel?: unknown }).cancel === 'function') {
                return attachRequests.track(rpc) as typeof rpc;
              }
              return rpc;
            },
          },
          notify: notifications,
        });
        if (reqGen !== attachGeneration) return;
        pendingAttach = null;
        if (result.state) projectState.set(result.state);
        if (result.activated) {
          await onAccessActivated();
        }
        sidebarNotice = result.converted
          ? `Converted and attached ${name || workspaceKindLabel(kind)} (.db).`
          : `Attached ${name || workspaceKindLabel(kind)}.`;
      } catch (cause) {
        if (reqGen !== attachGeneration || isCancelledAccessErrorOp(cause)) return;
        sidebarError = `Attach failed: ${await formatSidebarErrorOp(cause)}`;
      } finally {
        if (reqGen === attachGeneration) {
          clearAttachProgress();
          workspaceWorking = false;
        }
      }
    });
  }

  async function confirmPendingAttach() {
    if (!pendingAttach) return;
    const { kind, inspection, selectedName, requiresConvert } = pendingAttach;
    await executeAttach(kind, inspection.selectedPath, selectedName, requiresConvert);
  }

  function promptRemove(kind: WorkspaceResourceKind) {
    sidebarError = '';
    sidebarNotice = '';
    pendingAttach = null;
    pendingNew = null;
    if (kind === 'project' && activeProjectEntry) {
      pendingRemove = { kind, name: activeProjectEntry.name, path: activeProjectEntry.path ?? '' };
    } else if (kind === 'su' && activeSUEntry) {
      pendingRemove = { kind, name: activeSUEntry.name, path: activeSUEntry.path ?? '' };
    } else if (kind === 'hierarchy' && activeHierarchyEntry) {
      pendingRemove = { kind, name: activeHierarchyEntry.name, path: activeHierarchyEntry.path ?? '' };
    }
  }

  async function confirmRemove() {
    if (!pendingRemove) return;
    const target = pendingRemove;
    sidebarError = '';
    sidebarNotice = '';
    await requestTransition(async (contextId) => {
      workspaceWorking = true;
      try {
        const result = await runUnattachWorkspaceResourceOp({
          contextId,
          kind: target.kind,
          name: target.name,
          path: target.path,
          contextService: ContextService,
          notify: notifications,
        });
        pendingRemove = null;
        if (result.state) projectState.set(result.state);
        await onAccessActivated();
        sidebarNotice = `Removed ${target.name} from Work Space (file kept on disk).`;
      } catch (cause) {
        sidebarError = `Could not remove ${workspaceKindLabel(target.kind)}: ${await formatSidebarErrorOp(cause)}`;
      } finally {
        workspaceWorking = false;
      }
    });
  }

  function openNewForm(kind: WorkspaceResourceKind) {
    sidebarError = '';
    sidebarNotice = '';
    pendingAttach = null;
    pendingRemove = null;
    pendingNew = {
      kind,
      name: '',
      projectTitle: '',
      destinationMode: 'managed_new_file',
      filePath: '',
      populatePlots: kind === 'su',
      seedFromUserSu: false,
      activate: true,
    };
  }

  async function browseNewDestination() {
    const contextId = $projectState?.contextId;
    if (!contextId || !pendingNew) return;
    sidebarError = '';
    try {
      let chosen = '';
      if (pendingNew.destinationMode === 'existing_db') {
        chosen = await ContextService.ChooseAttachableFile(contextId, pendingNew.kind);
      } else {
        chosen = await ContextService.ChooseNewSQLiteProjectFile(contextId, pendingNew.name || pendingNew.kind);
      }
      if (chosen && pendingNew) {
        pendingNew = { ...pendingNew, filePath: chosen };
      }
    } catch (cause) {
      sidebarError = `Could not select destination file: ${await formatSidebarErrorOp(cause)}`;
    }
  }

  async function submitNewResource(event: SubmitEvent) {
    event.preventDefault();
    if (!pendingNew) return;
    const draft = pendingNew;
    const cleanName = draft.name.trim();
    if (!cleanName) {
      sidebarError = `Enter a name for the new ${workspaceKindLabel(draft.kind)}.`;
      return;
    }
    const req: CreateWorkspaceResourceRequest = {
      kind: draft.kind,
      name: cleanName,
      destinationMode: draft.destinationMode,
      filePath: draft.filePath.trim() || undefined,
      projectTitle: draft.kind === 'project' ? draft.projectTitle.trim() || undefined : undefined,
      populatePlots: draft.kind === 'su' ? draft.populatePlots : undefined,
      seedFromUserSu: draft.kind === 'su' ? draft.seedFromUserSu : undefined,
      activate: draft.activate,
    };
    sidebarError = '';
    sidebarNotice = '';
    await requestTransition(async (contextId) => {
      workspaceWorking = true;
      try {
        const result = await runCreateWorkspaceResourceOp({
          contextId,
          request: req,
          contextService: ContextService,
          notify: notifications,
        });
        pendingNew = null;
        if (result.state) projectState.set(result.state);
        if (result.activated) {
          await onAccessActivated();
        }
        sidebarNotice = `Created ${workspaceKindLabel(draft.kind)} ${result.name}.`;
      } catch (cause) {
        sidebarError = `Could not create ${workspaceKindLabel(draft.kind)}: ${await formatSidebarErrorOp(cause)}`;
      } finally {
        workspaceWorking = false;
      }
    });
  }

  async function handleExportVPro64() {
    const contextId = $projectState?.contextId;
    if (!contextId || controlsDisabled) return;
    sidebarError = '';
    sidebarNotice = '';
    exportingVPro64 = true;
    try {
      const outcome = await runExportVPro64Op({
        contextId,
        includeActiveSU: Boolean($projectState?.activeSU && $projectState.activeSU !== 'None'),
        includeHierarchy: Boolean($projectState?.activeHierarchy && $projectState.activeHierarchy !== 'None'),
        importExportService: ImportExportService,
        notify: notifications,
      });
      if (outcome) {
        lastVPro64Export = outcome;
        sidebarNotice = `Exported ${outcome.targetProject} (${outcome.plotCount} plots) for VPro64.`;
      }
    } catch (cause) {
      sidebarError = `Export to VPro64 failed: ${await formatSidebarErrorOp(cause)}`;
    } finally {
      exportingVPro64 = false;
    }
  }

  onDestroy(() => {
    cancelAttachOperation(true);
  });
</script>

<aside id="project-context" class="sidebar" aria-label={IS_WEB_READONLY ? 'Datasets' : 'Work Space'}>
  <div class="sidebar-heading">
    <span>{IS_WEB_READONLY ? 'DATASETS' : 'WORK SPACE'}</span>
    {#if !IS_WEB_READONLY}
      <button
        type="button"
        class="icon-button"
        title="Reveal VPro project folder in File Explorer"
        aria-label="Reveal in File Explorer"
        disabled={controlsDisabled || !$projectState?.contextId}
        onclick={() => void revealInExplorer('projects')}
      >
        <FolderOpen size={15} strokeWidth={1.8} />
      </button>
    {/if}
  </div>

  {#if IS_WEB_READONLY && $webShellRuntime?.ProvenanceBadge}
    {@const WebSnapshotProvenance = $webShellRuntime.ProvenanceBadge}
    <WebSnapshotProvenance variant="sidebar" activeProject={$projectState?.activeProject ?? ''} />
  {/if}

  {#if sidebarError}
    <div role="alert" data-workspace-error class="mx-2.5 mb-2 rounded border border-vpro-error bg-red-50 px-2.5 py-2 text-[11px] text-vpro-error">
      {sidebarError}
    </div>
  {/if}

  {#if sidebarNotice}
    <div role="status" data-workspace-notice class="mx-2.5 mb-2 rounded border border-vpro-navy/25 bg-white px-2.5 py-1.5 text-[11px] text-vpro-navy">
      {sidebarNotice}
    </div>
  {/if}

  <!-- 1. PROJECT dropdown box -->
  <section class="ws-box" data-ws-section="project" aria-label="Project selection">
    <div class="ws-box-header">
      <label for="active-project">{IS_WEB_READONLY ? 'DATASET' : 'PROJECT'}</label>
      {#if !IS_WEB_READONLY}
        <div class="ws-btn-row">
          <button
            type="button"
            class="ws-act-btn"
            data-ws-attach="project"
            title="Attach a VPro (.db) or Microsoft Access (.accdb / .mdb) project"
            disabled={controlsDisabled || !$projectState?.contextId}
            onclick={() => void startAttach('project')}
          >
            <Upload size={11} aria-hidden="true" />Attach
          </button>
          <button
            type="button"
            class="ws-act-btn"
            data-ws-remove="project"
            title="Remove active project from Work Space without deleting the file on disk"
            disabled={controlsDisabled || !$projectState?.contextId || !activeProjectEntry}
            onclick={() => promptRemove('project')}
          >
            <Trash2 size={11} aria-hidden="true" />Remove
          </button>
          <button
            type="button"
            class="ws-act-btn"
            data-ws-new="project"
            title="Create a new VPro project database (.db)"
            disabled={controlsDisabled || !$projectState?.contextId}
            onclick={() => openNewForm('project')}
          >
            <Plus size={11} aria-hidden="true" />New
          </button>
        </div>
      {/if}
    </div>
    <select
      id="active-project"
      data-ws-select="project"
      value={String(activeProjectIndex)}
      onchange={chooseProject}
      disabled={controlsDisabled || !$projectState}
    >
      {#if ($projectState?.projects?.length ?? 0) === 0}
        <option value="-1">No projects available</option>
      {/if}
      {#each $projectState?.projects ?? [] as project, index ((project.path ?? project.file) + project.name)}
        <option
          value={String(index)}
          disabled={!project.compatible}
          title={project.compatible ? project.path : `${project.version} is not a complete VPro project`}
        >
          {project.name}{$projectState?.projects?.filter((item) => item.name === project.name).length === 1
            ? ` (${project.file})`
            : ` — ${project.path}`}{!project.compatible ? ` [${project.version}]` : ''}
        </option>
      {/each}
    </select>
    {#if activeProjectEntry?.file}
      <div class="ws-meta-hint" title={activeProjectEntry.path}>{activeProjectEntry.file}</div>
    {/if}
  </section>

  <!-- 2. SITE UNIT dropdown box -->
  <section class="ws-box" data-ws-section="su" aria-label="Site Unit selection">
    <div class="ws-box-header">
      <label for="active-su">SITE UNIT</label>
      {#if !IS_WEB_READONLY}
        <div class="ws-btn-row">
          <button
            type="button"
            class="ws-act-btn"
            data-ws-attach="su"
            title="Attach a Site Unit database (.db) or Access file (.accdb / .mdb)"
            disabled={controlsDisabled || !$projectState?.contextId}
            onclick={() => void startAttach('su')}
          >
            <Upload size={11} aria-hidden="true" />Attach
          </button>
          <button
            type="button"
            class="ws-act-btn"
            data-ws-remove="su"
            title="Remove active Site Unit from Work Space without deleting the file on disk"
            disabled={controlsDisabled || !$projectState?.contextId || !activeSUEntry}
            onclick={() => promptRemove('su')}
          >
            <Trash2 size={11} aria-hidden="true" />Remove
          </button>
          <button
            type="button"
            class="ws-act-btn"
            data-ws-new="su"
            title="Create a new Site Unit table or standalone multi-SU file (.db)"
            disabled={controlsDisabled || !$projectState?.contextId}
            onclick={() => openNewForm('su')}
          >
            <Plus size={11} aria-hidden="true" />New
          </button>
        </div>
      {/if}
    </div>
    <select
      id="active-su"
      data-ws-select="su"
      value={String(activeSUIndex)}
      onchange={chooseSU}
      disabled={controlsDisabled || !$projectState}
    >
      <option value="-1">None</option>
      {#each $projectState?.sus ?? [] as su, index ((su.path ?? '') + su.name)}
        <option value={String(index)} disabled={!su.compatible} title={su.path}>
          {su.name}{su.kind === 'master' ? ' (master)' : ''}
        </option>
      {/each}
    </select>
    {#if activeSUEntry?.path}
      <div class="ws-meta-hint" title={activeSUEntry.path}>{activeSUEntry.path.split(/[\\/]/).pop()}</div>
    {/if}
  </section>

  <!-- 3. HIERARCHY dropdown box -->
  <section class="ws-box" data-ws-section="hierarchy" aria-label="Hierarchy selection">
    <div class="ws-box-header">
      <label for="active-hierarchy">HIERARCHY</label>
      {#if !IS_WEB_READONLY}
        <div class="ws-btn-row">
          <button
            type="button"
            class="ws-act-btn"
            data-ws-attach="hierarchy"
            title="Attach a Hierarchy database (.db) or Access file (.accdb / .mdb)"
            disabled={controlsDisabled || !$projectState?.contextId}
            onclick={() => void startAttach('hierarchy')}
          >
            <Upload size={11} aria-hidden="true" />Attach
          </button>
          <button
            type="button"
            class="ws-act-btn"
            data-ws-remove="hierarchy"
            title="Remove active Hierarchy from Work Space without deleting the file on disk"
            disabled={controlsDisabled || !$projectState?.contextId || !activeHierarchyEntry}
            onclick={() => promptRemove('hierarchy')}
          >
            <Trash2 size={11} aria-hidden="true" />Remove
          </button>
          <button
            type="button"
            class="ws-act-btn"
            data-ws-new="hierarchy"
            title="Create a new Hierarchy table or standalone multi-hierarchy file (.db)"
            disabled={controlsDisabled || !$projectState?.contextId}
            onclick={() => openNewForm('hierarchy')}
          >
            <Plus size={11} aria-hidden="true" />New
          </button>
        </div>
      {/if}
    </div>
    <select
      id="active-hierarchy"
      data-ws-select="hierarchy"
      value={String(activeHierarchyIndex)}
      onchange={chooseHierarchy}
      disabled={controlsDisabled || !$projectState}
    >
      <option value="-1">None</option>
      {#each $projectState?.hierarchies ?? [] as hierarchy, index ((hierarchy.path ?? hierarchy.file) + hierarchy.name)}
        <option value={String(index)} disabled={!hierarchy.compatible} title={hierarchy.path}>
          {hierarchy.name} ({hierarchy.file})
        </option>
      {/each}
    </select>
    {#if activeHierarchyEntry?.file}
      <div class="ws-meta-hint" title={activeHierarchyEntry.path}>{activeHierarchyEntry.file}</div>
    {/if}
  </section>

  <!-- Unified Attach Confirmation (Access auto-convert OR multi-table picker) -->
  {#if !IS_WEB_READONLY && pendingAttach}
    <section
      class="mx-2.5 my-2 space-y-2 rounded border border-vpro-navy border-l-[3px] border-l-vpro-gold bg-white p-2.5 text-[11px]"
      data-ws-attach-confirm
      aria-label="Confirm attach resource"
    >
      {#if pendingAttach.requiresConvert}
        <div class="font-semibold text-vpro-navy">Convert &amp; Attach Access File</div>
        <p class="leading-snug text-vpro-ink" data-ws-access-convert-prompt>
          This Microsoft Access file will be converted to a VPro database (.db) and attached to your Work Space.
        </p>
      {:else}
        <div class="font-semibold text-vpro-navy">Choose {workspaceKindLabel(pendingAttach.kind)} to Attach</div>
      {/if}

      <div class="truncate font-mono text-[10px] text-vpro-ink-secondary" title={pendingAttach.inspection.selectedPath}>
        {pendingAttach.inspection.selectedPath.split(/[\\/]/).pop()}
      </div>

      {#if pendingAttach.candidates.length > 0}
        <label class="flex flex-col gap-1 text-[10px] font-semibold uppercase text-vpro-ink-secondary">
          <span>{workspaceKindLabel(pendingAttach.kind)}</span>
          <select
            class="rounded border border-vpro-border bg-white px-2 py-1 text-[11px] font-normal text-vpro-ink"
            value={pendingAttach.selectedName}
            disabled={workspaceWorking}
            onchange={(e) => {
              if (pendingAttach) pendingAttach = { ...pendingAttach, selectedName: e.currentTarget.value };
            }}
          >
            {#each pendingAttach.candidates as cand (cand.name)}
              <option value={cand.name} disabled={!cand.compatible}>{cand.label}</option>
            {/each}
          </select>
        </label>
      {/if}

      {#if workspaceWorking && attachProgressMessage}
        <div role="status" class="space-y-1 rounded bg-vpro-canvas px-2 py-1.5 text-[10px] text-vpro-navy" data-ws-attach-progress>
          <div>{attachProgressMessage}{attachElapsedSeconds > 0 ? ` (${attachElapsedSeconds}s)` : ''}</div>
          {#if attachProgressPercent !== null}
            <progress max="100" value={attachProgressPercent} class="h-1.5 w-full"></progress>
          {:else}
            <progress class="h-1.5 w-full"></progress>
          {/if}
        </div>
      {/if}

      <div class="flex items-center gap-1.5 pt-1">
        <button
          type="button"
          data-ws-attach-submit
          disabled={workspaceWorking}
          class="flex-1 rounded bg-vpro-navy px-2 py-1 text-[11px] font-semibold text-white hover:bg-vpro-navy-dark disabled:opacity-50"
          onclick={() => void confirmPendingAttach()}
        >
          {workspaceWorking
            ? 'Working…'
            : pendingAttach.requiresConvert
              ? 'Convert & Attach'
              : 'Attach'}
        </button>
        <button
          type="button"
          data-ws-attach-cancel
          class="rounded border border-vpro-border bg-white px-2 py-1 text-[11px] text-vpro-ink hover:bg-vpro-surface-subtle"
          onclick={() => {
            if (workspaceWorking) {
              cancelAttachOperation(false);
            } else {
              pendingAttach = null;
            }
          }}
        >
          Cancel
        </button>
      </div>
    </section>
  {/if}

  <!-- Remove (Unattach) Confirmation -->
  {#if !IS_WEB_READONLY && pendingRemove}
    <section
      class="mx-2.5 my-2 space-y-2 rounded border border-vpro-navy/40 bg-white p-2.5 text-[11px]"
      data-ws-remove-confirm
      aria-label="Confirm remove from Work Space"
    >
      <div class="font-semibold text-vpro-navy">Remove from Work Space</div>
      <p class="leading-snug text-vpro-ink">
        Remove <strong>{pendingRemove.name}</strong> from your Work Space? The database file on disk will not be deleted.
      </p>
      <div class="flex items-center gap-1.5">
        <button
          type="button"
          data-ws-remove-submit
          disabled={workspaceWorking}
          class="flex-1 rounded bg-vpro-navy px-2 py-1 text-[11px] font-semibold text-white hover:bg-vpro-navy-dark disabled:opacity-50"
          onclick={() => void confirmRemove()}
        >
          {workspaceWorking ? 'Removing…' : 'Remove'}
        </button>
        <button
          type="button"
          disabled={workspaceWorking}
          class="rounded border border-vpro-border bg-white px-2 py-1 text-[11px] text-vpro-ink hover:bg-vpro-surface-subtle disabled:opacity-50"
          onclick={() => {
            pendingRemove = null;
          }}
        >
          Cancel
        </button>
      </div>
    </section>
  {/if}

  <!-- New Project / SU / Hierarchy Form -->
  {#if !IS_WEB_READONLY && pendingNew}
    <section
      class="mx-2.5 my-2 space-y-2 rounded border border-vpro-navy/40 bg-white p-2.5 text-[11px]"
      data-ws-new-form={pendingNew.kind}
      aria-label={`Create new ${workspaceKindLabel(pendingNew.kind)}`}
    >
      <div class="font-semibold text-vpro-navy">New {workspaceKindLabel(pendingNew.kind)}</div>
      <form class="space-y-2" onsubmit={(e) => void submitNewResource(e)}>
        <label class="flex flex-col gap-0.5 text-[10px] font-semibold uppercase text-vpro-ink-secondary">
          <span>Name</span>
          <input
            type="text"
            data-ws-new-name
            value={pendingNew.name}
            disabled={workspaceWorking}
            placeholder={pendingNew.kind === 'project'
              ? 'e.g. CoastalStudy'
              : pendingNew.kind === 'su'
                ? 'e.g. WorkingUnits'
                : 'e.g. RegionalHierarchy'}
            oninput={(e) => {
              if (pendingNew) pendingNew = { ...pendingNew, name: e.currentTarget.value };
            }}
            class="rounded border border-vpro-border bg-white px-2 py-1 text-[11px] font-normal text-vpro-ink"
          />
        </label>

        {#if pendingNew.kind === 'project'}
          <label class="flex flex-col gap-0.5 text-[10px] font-semibold uppercase text-vpro-ink-secondary">
            <span>Project Title (optional)</span>
            <input
              type="text"
              value={pendingNew.projectTitle}
              disabled={workspaceWorking}
              placeholder="Study description"
              oninput={(e) => {
                if (pendingNew) pendingNew = { ...pendingNew, projectTitle: e.currentTarget.value };
              }}
              class="rounded border border-vpro-border bg-white px-2 py-1 text-[11px] font-normal text-vpro-ink"
            />
          </label>
        {/if}

        <label class="flex flex-col gap-0.5 text-[10px] font-semibold uppercase text-vpro-ink-secondary">
          <span>Save Location</span>
          <select
            data-ws-new-dest
            value={pendingNew.destinationMode}
            disabled={workspaceWorking}
            onchange={(e) => {
              if (pendingNew) pendingNew = { ...pendingNew, destinationMode: e.currentTarget.value, filePath: '' };
            }}
            class="rounded border border-vpro-border bg-white px-2 py-1 text-[11px] font-normal text-vpro-ink"
          >
            <option value="managed_new_file">
              {pendingNew.kind === 'project' ? 'VPro workspace folder (.db)' : 'New standalone file (.db)'}
            </option>
            {#if pendingNew.kind !== 'project'}
              <option value="existing_db">Add to existing multi-table file (.db)</option>
              <option value="active_project">Inside active project file</option>
            {/if}
            <option value="custom_new_file">Choose custom file location (.db)</option>
          </select>
        </label>

        {#if pendingNew.destinationMode === 'custom_new_file' || pendingNew.destinationMode === 'existing_db'}
          <div class="space-y-1">
            <input
              type="text"
              data-ws-new-path
              value={pendingNew.filePath}
              disabled={workspaceWorking}
              placeholder="Path to .db file"
              oninput={(e) => {
                if (pendingNew) pendingNew = { ...pendingNew, filePath: e.currentTarget.value };
              }}
              class="w-full rounded border border-vpro-border bg-white px-2 py-1 text-[11px] text-vpro-ink"
            />
            <button
              type="button"
              disabled={workspaceWorking}
              class="w-full rounded border border-vpro-border bg-vpro-canvas px-2 py-1 text-[10px] font-semibold text-vpro-navy hover:bg-vpro-navy-tint"
              onclick={() => void browseNewDestination()}
            >
              Browse (.db)…
            </button>
          </div>
        {/if}

        {#if pendingNew.kind === 'su'}
          <label class="flex items-center gap-1.5 text-[11px] text-vpro-ink">
            <input
              type="checkbox"
              checked={pendingNew.populatePlots}
              disabled={workspaceWorking}
              onchange={(e) => {
                if (pendingNew) pendingNew = { ...pendingNew, populatePlots: e.currentTarget.checked };
              }}
            />
            <span>Include active project plots</span>
          </label>
          {#if pendingNew.populatePlots}
            <label class="flex items-center gap-1.5 text-[11px] text-vpro-ink">
              <input
                type="checkbox"
                checked={pendingNew.seedFromUserSu}
                disabled={workspaceWorking}
                onchange={(e) => {
                  if (pendingNew) pendingNew = { ...pendingNew, seedFromUserSu: e.currentTarget.checked };
                }}
              />
              <span>Seed from UserSiteUnit</span>
            </label>
          {/if}
        {/if}

        <div class="flex items-center gap-1.5 pt-1">
          <button
            type="submit"
            data-ws-new-submit
            disabled={workspaceWorking}
            class="flex-1 rounded bg-vpro-navy px-2 py-1 text-[11px] font-semibold text-white hover:bg-vpro-navy-dark disabled:opacity-50"
          >
            {workspaceWorking ? 'Creating…' : 'Create'}
          </button>
          <button
            type="button"
            disabled={workspaceWorking}
            class="rounded border border-vpro-border bg-white px-2 py-1 text-[11px] text-vpro-ink hover:bg-vpro-surface-subtle disabled:opacity-50"
            onclick={() => {
              pendingNew = null;
            }}
          >
            Cancel
          </button>
        </div>
      </form>
    </section>
  {/if}

  <!-- Export to VPro64 action -->
  {#if !IS_WEB_READONLY}
    <div class="ws-action-block">
      <button
        type="button"
        class="ws-export-btn"
        data-ws-export-vpro64
        title="Save a clean VPro64-compatible database (.db) ready to import into legacy Access VPro64"
        disabled={controlsDisabled || !$projectState?.contextId}
        onclick={() => void handleExportVPro64()}
      >
        <Download size={14} aria-hidden="true" />
        <span>{exportingVPro64 ? 'Exporting to VPro64…' : 'Export to VPro64'}</span>
      </button>
      {#if lastVPro64Export}
        <div class="ws-meta-hint mt-1" title={lastVPro64Export.destinationPath}>
          Last export: {lastVPro64Export.targetProject} ({lastVPro64Export.plotCount} plots)
        </div>
      {/if}
    </div>

    <!-- Compact Sign In / Access Status card -->
    <section
      class="ws-auth-card {isDataLocked ? 'ws-auth-locked' : 'ws-auth-unlocked'}"
      data-ws-auth-card
      aria-label="Sign in and edit access status"
    >
      <div class="flex items-start gap-2">
        {#if isDataLocked}
          <Lock size={14} class="mt-0.5 shrink-0 text-vpro-navy" aria-hidden="true" />
        {:else}
          <Unlock size={14} class="mt-0.5 shrink-0 text-vpro-success" aria-hidden="true" />
        {/if}
        <div class="min-w-0 flex-1">
          {#if isSignedIn}
            <div class="truncate text-[11px] font-bold text-vpro-navy" title={authUserLabel}>
              {authUserLabel || 'Signed in'}
            </div>
            <div class="text-[10px] text-vpro-ink-secondary">
              {authRoleLabel || 'user'} · {isDataLocked ? 'Locked' : 'Unlocked'}
            </div>
          {:else}
            <div class="text-[11px] font-bold text-vpro-navy">Data locked</div>
            <div class="text-[10px] text-vpro-ink-secondary">Sign in to edit plots</div>
          {/if}
        </div>
      </div>
      <button
        type="button"
        class="ws-auth-btn"
        data-ws-auth-trigger
        disabled={busy || transitionWorking}
        onclick={() => onOpenAuthSignIn?.()}
      >
        <KeyRound size={12} aria-hidden="true" />
        <span>{isSignedIn ? 'Access & Sign Out' : 'Sign In'}</span>
      </button>
    </section>
  {/if}

  <div class="sidebar-footer">
    {$projectState?.projects?.length ?? 0} {IS_WEB_READONLY ? 'dataset' : 'project'}{($projectState?.projects?.length ?? 0) === 1 ? '' : 's'}
  </div>
</aside>

<style>
  .ws-box {
    padding: 0.65rem 0.75rem;
    border-top: 1px solid rgba(0, 51, 102, 0.08);
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
  }

  .ws-box-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.25rem;
    flex-wrap: wrap;
  }

  .ws-box-header label {
    font-size: 0.68rem;
    font-weight: 700;
    letter-spacing: 0.05em;
    color: var(--vpro-navy, #003366);
    margin: 0;
  }

  .ws-btn-row {
    display: inline-flex;
    align-items: center;
    gap: 0.2rem;
  }

  .ws-act-btn {
    display: inline-flex;
    align-items: center;
    gap: 0.18rem;
    padding: 0.14rem 0.36rem;
    border: 1px solid var(--vpro-border, #cbd5e1);
    border-radius: 3px;
    background: var(--vpro-surface, #ffffff);
    color: var(--vpro-navy, #003366);
    font-size: 0.65rem;
    font-weight: 600;
    line-height: 1.25;
    cursor: pointer;
  }

  .ws-act-btn:hover:not(:disabled) {
    background: var(--vpro-navy-tint, #edf2f7);
    border-color: var(--vpro-navy, #003366);
  }

  .ws-act-btn:disabled {
    opacity: 0.45;
    cursor: not-allowed;
  }

  .ws-box select {
    width: 100%;
    padding: 0.36rem 0.45rem;
    border: 1px solid var(--vpro-border, #cbd5e1);
    border-radius: 4px;
    background: var(--vpro-surface, #ffffff);
    color: var(--vpro-ink, #1e293b);
    font-size: 0.78rem;
    min-width: 0;
  }

  .ws-meta-hint {
    font-size: 0.67rem;
    color: var(--vpro-ink-secondary, #475569);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .ws-action-block {
    padding: 0.65rem 0.75rem;
    border-top: 1px solid rgba(0, 51, 102, 0.08);
  }

  .ws-export-btn {
    width: 100%;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 0.4rem;
    padding: 0.42rem 0.6rem;
    border: 1px solid var(--vpro-navy, #003366);
    border-radius: 4px;
    background: var(--vpro-surface, #ffffff);
    color: var(--vpro-navy, #003366);
    font-size: 0.75rem;
    font-weight: 600;
    cursor: pointer;
  }

  .ws-export-btn:hover:not(:disabled) {
    background: var(--vpro-navy, #003366);
    color: #ffffff;
  }

  .ws-export-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .ws-auth-card {
    margin: 0.5rem 0.75rem 0.65rem;
    padding: 0.55rem 0.65rem;
    border-radius: 4px;
    border: 1px solid var(--vpro-border, #cbd5e1);
    display: flex;
    flex-direction: column;
    gap: 0.45rem;
  }

  .ws-auth-locked {
    background: var(--vpro-warning-bg, #fffbeb);
    border-color: var(--vpro-gold, #fcba19);
  }

  .ws-auth-unlocked {
    background: #f0fdf4;
    border-color: rgba(46, 133, 64, 0.4);
  }

  .ws-auth-btn {
    width: 100%;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 0.35rem;
    padding: 0.32rem 0.5rem;
    border: 1px solid var(--vpro-navy, #003366);
    border-radius: 3px;
    background: var(--vpro-navy, #003366);
    color: #ffffff;
    font-size: 0.72rem;
    font-weight: 600;
    cursor: pointer;
  }

  .ws-auth-btn:hover:not(:disabled) {
    filter: brightness(1.08);
  }

  .ws-auth-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
</style>
