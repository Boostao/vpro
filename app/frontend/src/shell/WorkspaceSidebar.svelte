<script lang="ts">
  import { onDestroy } from 'svelte';
  import { FolderOpen } from '@lucide/svelte';
  import {
    ContextService,
    ImportExportService,
    type AccessDatabaseInspection,
    type AccessProjectImportResult,
  } from '../../bindings/github.com/boostao/vpro/app';
  import type { AccessProjectCandidate } from '../../bindings/github.com/boostao/vpro/app/internal/interchange/models';
  import type {
    ContextSelection,
    ProjectInfo,
  } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
  import type { AccessImportProgressPayload } from '../interchange/interchangeHub';
  import { formatError, ReadRequests } from '../shared/readRequests';
  import { projectState, webShellRuntime } from '../shared/state';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import { notifications } from './notificationService.svelte';
  import WorkspaceAccessCandidateFields from './WorkspaceAccessCandidateFields.svelte';
  import WorkspaceAccessProgressStatus from './WorkspaceAccessProgressStatus.svelte';
  import WorkspaceExternalAttachSection from './WorkspaceExternalAttachSection.svelte';
  import {
    browseExternalProjectFileOp,
    computeAccessProgressPercent,
    formatSidebarErrorOp,
    isCancelledAccessErrorOp,
    runImportAccessProjectOp,
    runInspectAccessSourceOp,
  } from './workspaceSidebarOps';

  let {
    busy,
    editorBusy,
    companionPanelBusy,
    transitionWorking,
    requestTransition,
    switchContext,
    onAccessActivated,
    subscribeAccessProgress,
  }: {
    busy: boolean;
    editorBusy: boolean;
    companionPanelBusy: boolean;
    transitionWorking: boolean;
    requestTransition: (run: (contextId: string) => Promise<void>) => Promise<void>;
    switchContext: (contextId: string, selection: ContextSelection, next: 'plots' | 'hierarchy') => Promise<void>;
    onAccessActivated: () => Promise<void>;
    subscribeAccessProgress?: (
      handler: (progress: AccessImportProgressPayload) => void
    ) => Promise<() => void> | (() => void);
  } = $props();

  let externalProject = $state(''),
    externalPath = $state(''),
    externalDiscoveredProjects = $state<ProjectInfo[]>([]);
  let accessSourcePath = $state(''),
    accessInspection = $state<AccessDatabaseInspection | null>(null);
  let accessSelectedSourceProject = $state(''),
    accessTargetProject = $state(''),
    accessDestinationPath = $state('');
  let accessActivateOnSuccess = $state(true),
    accessWorking = $state(false);
  let accessOperation = $state<'inspect' | 'import' | ''>(''),
    accessProgressPhase = $state(''),
    accessProgressMessage = $state('');
  let accessProgressRows = $state(0),
    accessProgressExpectedRows = $state(0),
    accessElapsedSeconds = $state(0);
  let accessStatusNotice = $state(''),
    accessError = $state(''),
    accessResult = $state<AccessProjectImportResult | null>(null);

  let accessGeneration = 0;
  let activeAccessRpc: { cancel: () => unknown } | null = null;
  const accessRequests = new ReadRequests();
  let stopAccessProgressEvents: (() => void) | null = null;
  let accessElapsedTimer: ReturnType<typeof setInterval> | null = null;

  const accessSelectedCandidate = $derived(
    accessInspection?.projects?.find((p) => p.sourceProject === accessSelectedSourceProject) ?? null
  );
  const accessProgressPercent = $derived(
    computeAccessProgressPercent(accessWorking, accessProgressPhase, accessProgressRows, accessProgressExpectedRows)
  );
  const activeHierarchyIndex = $derived(
    $projectState?.hierarchies?.findIndex(
      (h) => h.name === $projectState?.activeHierarchy && h.path === $projectState?.hierarchyPath
    ) ?? -1
  );
  const activeSUIndex = $derived(
    $projectState?.sus?.findIndex((su) => su.name === $projectState?.activeSU && su.path === $projectState?.suPath) ??
      -1
  );

  async function formatSidebarError(cause: unknown): Promise<string> {
    return formatSidebarErrorOp(cause);
  }
  function isCancelledAccessError(cause: unknown): boolean {
    return isCancelledAccessErrorOp(cause);
  }

  function clearAccessRuntimeTimersAndListeners() {
    if (typeof stopAccessProgressEvents === 'function') {
      const stop = stopAccessProgressEvents;
      stopAccessProgressEvents = null;
      stop();
    }
    if (accessElapsedTimer !== null) {
      clearInterval(accessElapsedTimer);
      accessElapsedTimer = null;
    }
  }

  function startAccessElapsedTimer() {
    clearAccessRuntimeTimersAndListeners();
    accessElapsedSeconds = 0;
    if (typeof globalThis.setInterval === 'function') {
      const startedAt = Date.now();
      accessElapsedTimer = globalThis.setInterval(() => {
        accessElapsedSeconds = Math.max(1, Math.floor((Date.now() - startedAt) / 1000));
      }, 1000);
    }
  }

  async function attachAccessProgressListener(
    contextId: string,
    expectedOperation: 'inspect' | 'import',
    reqGen: number
  ) {
    const handler = (raw: AccessImportProgressPayload) => {
      if (!raw || reqGen !== accessGeneration) return;
      if (raw.contextId && raw.contextId !== contextId) return;
      if (raw.operation && raw.operation !== expectedOperation) return;
      if (typeof raw.phase === 'string') accessProgressPhase = raw.phase;
      if (typeof raw.message === 'string' && raw.message.trim()) accessProgressMessage = raw.message.trim();
      const rows = Number(raw.totalRowsProcessed ?? raw.tableRowsProcessed ?? 0);
      if (Number.isFinite(rows) && rows >= 0) accessProgressRows = rows;
    };
    try {
      if (typeof subscribeAccessProgress === 'function') {
        const off = await subscribeAccessProgress(handler);
        if (reqGen !== accessGeneration) {
          off?.();
          return;
        }
        stopAccessProgressEvents = off;
        return;
      }
      const mod = await import('../interchange/interchangeHub');
      if (reqGen === accessGeneration && typeof mod?.subscribeWailsAccessImportProgress === 'function') {
        stopAccessProgressEvents = mod.subscribeWailsAccessImportProgress(handler);
      }
    } catch {
      // Progress events degrade gracefully if runtime events are unavailable in headless test harnesses.
    }
  }

  function cancelAccessOperation(silent = false) {
    const wasWorking = accessWorking,
      prevOp = accessOperation;
    accessGeneration++;
    const current = activeAccessRpc;
    activeAccessRpc = null;
    clearAccessRuntimeTimersAndListeners();
    accessWorking = false;
    accessOperation = '';
    accessProgressPhase = '';
    accessProgressMessage = '';
    accessProgressRows = 0;
    accessProgressExpectedRows = 0;
    accessRequests.cancelAll();
    if (current) current.cancel();
    if (!silent && wasWorking) {
      accessError = '';
      accessStatusNotice =
        prevOp === 'inspect'
          ? 'Access file inspection cancelled.'
          : 'Import cancelled. No VPro project file (.db) was created.';
    }
  }

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

  async function chooseProject(project: ProjectInfo) {
    await requestTransition(async (contextId) => {
      if (!project.path) throw new Error('Choose a project with an explicit file identity.');
      await switchContext(
        contextId,
        { ...selectedContext(), project: project.name, projectPath: project.path, su: 'None', suPath: '' },
        'plots'
      );
    });
  }

  async function chooseSU(event: Event) {
    const select = event.currentTarget as HTMLSelectElement,
      chosen = $projectState?.sus?.[Number(select.value)];
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
    const select = event.currentTarget as HTMLSelectElement,
      chosen = $projectState?.hierarchies?.[Number(select.value)];
    select.value = String(activeHierarchyIndex);
    await requestTransition(async (contextId) => {
      await switchContext(
        contextId,
        { ...selectedContext(), hierarchy: chosen?.name ?? 'None', hierarchyPath: chosen?.path ?? '' },
        'hierarchy'
      );
    });
  }

  async function attachExternalProject(event: SubmitEvent) {
    event.preventDefault();
    const name = externalProject,
      filePath = externalPath;
    await requestTransition(async (contextId) => {
      await switchContext(
        contextId,
        { ...selectedContext(), project: name, projectPath: filePath, su: 'None', suPath: '' },
        'plots'
      );
    });
  }

  async function browseExternalProjectFile() {
    await browseExternalProjectFileOp({
      contextId: $projectState?.contextId,
      contextService: ContextService,
      onDiscovered: (path, discovered, first) => {
        externalPath = path;
        externalDiscoveredProjects = discovered;
        if (first) externalProject = first;
      },
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
      const msg = await formatSidebarError(cause);
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

  function applyAccessCandidate(candidate: AccessProjectCandidate | null) {
    if (!candidate) return;
    accessSelectedSourceProject = candidate.sourceProject;
    accessTargetProject = candidate.suggestedTarget;
    accessDestinationPath = candidate.suggestedDestPath;
  }

  async function browseAccessDatabase() {
    const contextId = $projectState?.contextId;
    if (!contextId) return;
    accessError = '';
    accessStatusNotice = '';
    accessResult = null;
    try {
      const chosen = await ImportExportService.ChooseAccessDatabaseFile(contextId);
      if (!chosen) return;
      accessSourcePath = chosen;
      await inspectAccessSource(chosen);
    } catch (cause) {
      accessError = `Could not select Access file: ${await formatSidebarError(cause)}`;
    }
  }

  async function inspectAccessSource(pathToInspect = accessSourcePath) {
    const contextId = $projectState?.contextId;
    if (!contextId || !pathToInspect || (accessWorking && accessOperation === 'import')) return;
    if (accessWorking) cancelAccessOperation(true);
    const reqGen = ++accessGeneration;
    accessWorking = true;
    accessOperation = 'inspect';
    accessProgressPhase = 'starting';
    accessProgressMessage = 'Verifying Access file…';
    accessProgressRows = 0;
    accessProgressExpectedRows = 0;
    accessError = '';
    accessStatusNotice = '';
    accessResult = null;
    startAccessElapsedTimer();
    await runInspectAccessSourceOp({
      contextId,
      pathToInspect,
      reqGen,
      isCurrentGen: () => reqGen === accessGeneration,
      attachProgress: () => attachAccessProgressListener(contextId, 'inspect', reqGen),
      importExportService: ImportExportService,
      accessRequests,
      setActiveRpc: (rpc) => {
        activeAccessRpc = rpc;
      },
      onResolved: (inspection, first) => {
        accessInspection = inspection;
        accessSourcePath = inspection.sourcePath;
        applyAccessCandidate(first);
        if (!first) accessError = 'No VPro project tables were found in the selected Access database.';
      },
      onFailed: (msg) => {
        accessInspection = null;
        accessError = `Access inspection failed: ${msg}`;
      },
      onSettledCurrent: () => {
        activeAccessRpc = null;
        clearAccessRuntimeTimersAndListeners();
        accessWorking = false;
        accessOperation = '';
        accessProgressPhase = '';
      },
      notify: notifications,
    });
  }

  async function browseAccessDestinationPath() {
    const contextId = $projectState?.contextId;
    if (!contextId) return;
    accessError = '';
    accessStatusNotice = '';
    try {
      const chosen = await ContextService.ChooseNewSQLiteProjectFile(contextId, accessTargetProject);
      if (chosen) accessDestinationPath = chosen;
    } catch (cause) {
      accessError = `Could not choose destination .db file: ${await formatSidebarError(cause)}`;
    }
  }

  async function runAccessProjectImport(event: SubmitEvent) {
    event.preventDefault();
    if (
      !accessInspection ||
      !accessSelectedSourceProject ||
      !accessTargetProject ||
      !accessDestinationPath ||
      accessWorking
    )
      return;
    const payload = {
      sourcePath: accessInspection.sourcePath,
      sourceProject: accessSelectedSourceProject,
      targetProject: accessTargetProject,
      destinationPath: accessDestinationPath,
      activateOnSuccess: accessActivateOnSuccess,
    };
    const expectedRows = (accessSelectedCandidate?.tables ?? []).reduce(
      (sum, tbl) => sum + (tbl.present ? (tbl.rowCount ?? 0) : 0),
      0
    );
    await requestTransition(async (contextId) => {
      const reqGen = ++accessGeneration;
      accessWorking = true;
      accessOperation = 'import';
      accessProgressPhase = 'starting';
      accessProgressMessage = 'Preparing destination file and verifying Access database…';
      accessProgressRows = 0;
      accessProgressExpectedRows = expectedRows;
      accessError = '';
      accessStatusNotice = '';
      accessResult = null;
      startAccessElapsedTimer();
      await runImportAccessProjectOp({
        contextId,
        payload,
        isCurrentGen: () => reqGen === accessGeneration,
        attachProgress: () => attachAccessProgressListener(contextId, 'import', reqGen),
        importExportService: ImportExportService,
        accessRequests: typeof accessRequests !== 'undefined' ? accessRequests : undefined,
        setActiveRpc: (rpc) => {
          activeAccessRpc = rpc;
        },
        onSucceeded: async (result) => {
          accessResult = result;
          if (result.state) projectState.set(result.state);
          if (result.activated) await onAccessActivated();
        },
        onFailed: (msg) => {
          accessError = `Import failed: ${msg}`;
        },
        onSettledCurrent: () => {
          activeAccessRpc = null;
          clearAccessRuntimeTimersAndListeners();
          accessWorking = false;
          accessOperation = '';
          accessProgressPhase = '';
        },
        notify: notifications,
      });
    });
  }

  onDestroy(() => cancelAccessOperation(true));
</script>

<aside id="project-context" class="sidebar" aria-label={IS_WEB_READONLY ? 'Datasets' : 'Projects'}>
  <div class="sidebar-heading">
    <span>{IS_WEB_READONLY ? 'DATASETS' : 'PROJECTS'}</span>
    {#if !IS_WEB_READONLY}
      <button
        type="button"
        class="icon-button"
        title="Reveal VPro project folder in File Explorer"
        aria-label="Reveal in File Explorer"
        disabled={busy || transitionWorking || !$projectState?.contextId}
        onclick={() => void revealInExplorer('projects')}
      >
        <FolderOpen size={16} strokeWidth={1.8} />
      </button>
    {/if}
  </div>
  {#if IS_WEB_READONLY && $webShellRuntime?.ProvenanceBadge}
    {@const WebSnapshotProvenance = $webShellRuntime.ProvenanceBadge}
    <WebSnapshotProvenance variant="sidebar" activeProject={$projectState?.activeProject ?? ''} />
  {/if}
  <nav aria-label="Project list">
    {#each $projectState?.projects ?? [] as project ((project.path ?? project.file) + project.name)}
      <button
        class:active={project.name === $projectState?.activeProject && project.path === $projectState?.projectPath}
        disabled={!project.compatible || busy || editorBusy || companionPanelBusy || transitionWorking || accessWorking}
        title={project.compatible ? project.path : `${project.version} is not a complete VPro project`}
        onclick={() => chooseProject(project)}
      >
        <span class="project-name"
          >{project.name}
          <span class="project-location"
            >{$projectState?.projects?.filter((item) => item.name === project.name).length === 1
              ? project.file
              : project.path}</span
          >
        </span>
        {#if !project.compatible}<span class="project-version">{project.version}</span>{/if}
      </button>
    {/each}
  </nav>
  <div class="su-picker">
    <label for="active-su">SITE UNIT</label>
    <select
      id="active-su"
      value={String(activeSUIndex)}
      onchange={chooseSU}
      disabled={busy || editorBusy || companionPanelBusy || transitionWorking || accessWorking || !$projectState}
    >
      <option value="-1">None</option>
      {#each $projectState?.sus ?? [] as su, index ((su.path ?? '') + su.name)}
        <option value={String(index)} disabled={!su.compatible} title={su.path}
          >{su.name}{su.kind === 'master' ? ' (master)' : ''}</option
        >
      {/each}
    </select>
  </div>
  <div class="su-picker">
    <label for="active-hierarchy">HIERARCHY</label>
    <select
      id="active-hierarchy"
      value={String(activeHierarchyIndex)}
      onchange={chooseHierarchy}
      disabled={busy || editorBusy || companionPanelBusy || transitionWorking || accessWorking || !$projectState}
    >
      <option value="-1">None</option>
      {#each $projectState?.hierarchies ?? [] as hierarchy, index ((hierarchy.path ?? hierarchy.file) + hierarchy.name)}
        <option value={String(index)} disabled={!hierarchy.compatible} title={hierarchy.path}
          >{hierarchy.name} ({hierarchy.file})</option
        >
      {/each}
    </select>
  </div>

  {#if !IS_WEB_READONLY}
    <WorkspaceExternalAttachSection
      bind:externalProject
      bind:externalPath
      {externalDiscoveredProjects}
      {busy}
      {editorBusy}
      {companionPanelBusy}
      {transitionWorking}
      contextReady={Boolean($projectState?.contextId)}
      onBrowseExternal={() => void browseExternalProjectFile()}
      onAttachSubmit={attachExternalProject}
      onReveal={(t) => void revealInExplorer(t)}
    />

    <details class="su-picker" id="access-import-wizard">
      <summary>Import Access (.mdb / .accdb) wizard</summary>
      <form onsubmit={runAccessProjectImport}>
        <button
          type="button"
          id="browse-access-db"
          disabled={busy || transitionWorking || accessWorking || !$projectState?.contextId}
          onclick={() => void browseAccessDatabase()}>Browse Access (.mdb / .accdb)…</button
        >
        <label for="access-source-path">ACCESS SOURCE FILE (.mdb / .accdb)</label>
        <input
          id="access-source-path"
          bind:value={accessSourcePath}
          placeholder="C:\path\to\project.accdb"
          disabled={busy || transitionWorking || accessWorking}
        />
        <button
          type="button"
          id="inspect-access-db"
          disabled={busy ||
            transitionWorking ||
            (accessWorking && accessOperation === 'import') ||
            !accessSourcePath ||
            !$projectState?.contextId}
          onclick={() => void inspectAccessSource()}
        >
          {accessWorking && accessOperation === 'inspect' ? 'Inspecting Access file…' : 'Inspect Access file'}
        </button>
        {#if accessInspection && (accessInspection.projects?.length ?? 0) > 0}
          <WorkspaceAccessCandidateFields
            {accessInspection}
            {accessSelectedSourceProject}
            {accessSelectedCandidate}
            bind:accessTargetProject
            bind:accessDestinationPath
            bind:accessActivateOnSuccess
            {busy}
            {transitionWorking}
            {accessWorking}
            contextReady={Boolean($projectState?.contextId)}
            onSelectCandidate={applyAccessCandidate}
            onBrowseDestination={() => void browseAccessDestinationPath()}
          />
        {/if}
        <WorkspaceAccessProgressStatus
          {accessWorking}
          {accessOperation}
          {accessElapsedSeconds}
          {accessProgressPercent}
          {accessProgressMessage}
          {accessProgressRows}
          {accessProgressExpectedRows}
          {accessStatusNotice}
          {accessError}
          {accessResult}
          onCancel={() => cancelAccessOperation(false)}
        />
      </form>
    </details>
  {/if}
  <div class="sidebar-footer">
    {$projectState?.projects?.length ?? 0} {IS_WEB_READONLY ? 'dataset' : 'project'}{($projectState?.projects?.length ?? 0) === 1 ? '' : 's'}
  </div>
</aside>
