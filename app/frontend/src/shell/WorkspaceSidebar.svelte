<script lang="ts">
  import { onDestroy } from 'svelte';
  import { FolderOpen } from '@lucide/svelte';
  import { ContextService, ImportExportService, type AccessDatabaseInspection, type AccessProjectImportResult } from '../../bindings/github.com/boostao/vpro/app';
  import type { AccessProjectCandidate } from '../../bindings/github.com/boostao/vpro/app/internal/interchange/models';
  import type { ContextSelection, ProjectInfo } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
  import { ReadRequests, type CancellableRead } from '../shared/readRequests';
  import { projectState } from '../shared/state';
  import { notifications } from './notificationService.svelte';

  import type { AccessImportProgressPayload } from '../interchange/interchangeHub';

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
    subscribeAccessProgress?: (handler: (progress: AccessImportProgressPayload) => void) => Promise<() => void> | (() => void);
  } = $props();

  const externalProjectsEnabled = true;

  let externalProject = $state('');
  let externalPath = $state('');
  let externalDiscoveredProjects = $state<ProjectInfo[]>([]);
  let accessSourcePath = $state('');
  let accessInspection = $state<AccessDatabaseInspection | null>(null);
  let accessSelectedSourceProject = $state('');
  let accessTargetProject = $state('');
  let accessDestinationPath = $state('');
  let accessActivateOnSuccess = $state(true);
  let accessWorking = $state(false);
  let accessOperation = $state<'inspect' | 'import' | ''>('');
  let accessProgressPhase = $state('');
  let accessProgressMessage = $state('');
  let accessProgressRows = $state(0);
  let accessProgressExpectedRows = $state(0);
  let accessElapsedSeconds = $state(0);
  let accessStatusNotice = $state('');
  let accessError = $state('');
  let accessResult = $state<AccessProjectImportResult | null>(null);

  let accessGeneration = 0;
  let activeAccessRpc: { cancel: () => unknown } | null = null;
  const accessRequests = new ReadRequests();
  let stopAccessProgressEvents: (() => void) | null = null;
  let accessElapsedTimer: ReturnType<typeof setInterval> | null = null;

  const accessSelectedCandidate = $derived(
    accessInspection?.projects?.find(p => p.sourceProject === accessSelectedSourceProject) ?? null
  );
  const accessProgressPercent = $derived.by(() => {
    if (!accessWorking) return null;
    if (accessProgressPhase === 'finalizing') return 98;
    if (accessProgressExpectedRows > 0 && accessProgressRows > 0) {
      return Math.min(96, Math.max(1, Math.round((accessProgressRows / accessProgressExpectedRows) * 95)));
    }
    return null;
  });
  const activeHierarchyIndex = $derived(
    $projectState?.hierarchies?.findIndex(
      hierarchy => hierarchy.name === $projectState?.activeHierarchy && hierarchy.path === $projectState?.hierarchyPath
    ) ?? -1
  );
  const activeSUIndex = $derived(
    $projectState?.sus?.findIndex(
      su => su.name === $projectState?.activeSU && su.path === $projectState?.suPath
    ) ?? -1
  );

  async function formatSidebarError(cause: unknown): Promise<string> {
    try {
      const mod = await import('../interchange/interchangeHub');
      if (typeof mod?.formatInterchangeError === 'function') {
        return mod.formatInterchangeError(cause);
      }
    } catch {
      // Fallback in isolated VM tests where dynamic import is unavailable.
    }
    const msg = String(cause ?? '').replace(/^(?:\s*(?:RuntimeError|Error|CallError):\s*)+/i, '').trim();
    if (/picture selection|file dialogs not available/i.test(msg)) {
      return 'File selection requires an active desktop window; enter a file path directly when running in a browser.';
    }
    if (/Access source read error|cannot read Access catalog/i.test(msg)) {
      return 'The selected Access file could not be read. It may be incomplete, damaged, or in an unsupported format.';
    }
    if (/\b(?:lstat|stat|open)\b[^:]*:\s*no such file/i.test(msg)) {
      return 'The selected file or folder was not found. Check the path and try again.';
    }
    return msg.replace(/:\s*sql:\s*no rows in result set/gi, '').trim() || 'An unexpected error occurred.';
  }

  function isCancelledAccessError(cause: unknown): boolean {
    if (!cause) return false;
    if (cause instanceof Error && cause.name === 'CancelError') return true;
    const text = String(cause).toLowerCase();
    return text.includes('context canceled') || text.includes('operation cancelled');
  }

  function clearAccessRuntimeTimersAndListeners() {
    if (typeof stopAccessProgressEvents === 'function') {
      const stop = stopAccessProgressEvents;
      stopAccessProgressEvents = null;
      stop();
    }
    if (typeof accessElapsedTimer !== 'undefined' && accessElapsedTimer !== null) {
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

  async function attachAccessProgressListener(contextId: string, expectedOperation: 'inspect' | 'import', reqGen: number) {
    const handler = (raw: AccessImportProgressPayload) => {
      if (!raw || reqGen !== accessGeneration) return;
      if (raw.contextId && raw.contextId !== contextId) return;
      if (raw.operation && raw.operation !== expectedOperation) return;
      if (typeof raw.phase === 'string') accessProgressPhase = raw.phase;
      if (typeof raw.message === 'string' && raw.message.trim()) {
        accessProgressMessage = raw.message.trim();
      }
      const rows = Number(raw.totalRowsProcessed ?? raw.tableRowsProcessed ?? 0);
      if (Number.isFinite(rows) && rows >= 0) {
        accessProgressRows = rows;
      }
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
      if (reqGen !== accessGeneration) return;
      if (typeof mod?.subscribeWailsAccessImportProgress === 'function') {
        stopAccessProgressEvents = mod.subscribeWailsAccessImportProgress(handler);
      }
    } catch {
      // Progress events degrade gracefully if runtime events are unavailable in headless test harnesses.
    }
  }

  function cancelAccessOperation(silent = false) {
    const wasWorking = accessWorking;
    const prevOp = accessOperation;
    accessGeneration++;
    const current = typeof activeAccessRpc !== 'undefined' ? activeAccessRpc : null;
    activeAccessRpc = null;
    clearAccessRuntimeTimersAndListeners();
    accessWorking = false;
    accessOperation = '';
    accessProgressPhase = '';
    accessProgressMessage = '';
    accessProgressRows = 0;
    accessProgressExpectedRows = 0;
    if (typeof accessRequests !== 'undefined') {
      accessRequests.cancelAll();
    }
    if (current) {
      current.cancel();
    }
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
    await requestTransition(async contextId => {
      if (!project.path) throw new Error('Choose a project with an explicit file identity.');
      const selection = selectedContext();
      selection.project = project.name;
      selection.projectPath = project.path;
      selection.su = 'None';
      selection.suPath = '';
      await switchContext(contextId, selection, 'plots');
    });
  }

  async function chooseSU(event: Event) {
    const select = event.currentTarget as HTMLSelectElement;
    const chosen = $projectState?.sus?.[Number(select.value)];
    select.value = String(activeSUIndex);
    await requestTransition(async contextId => {
      const selection = selectedContext();
      selection.su = chosen?.name ?? 'None';
      selection.suPath = chosen?.path ?? '';
      await switchContext(contextId, selection, 'plots');
    });
  }

  async function chooseHierarchy(event: Event) {
    const select = event.currentTarget as HTMLSelectElement;
    const chosen = $projectState?.hierarchies?.[Number(select.value)];
    select.value = String(activeHierarchyIndex);
    await requestTransition(async contextId => {
      const selection = selectedContext();
      selection.hierarchy = chosen?.name ?? 'None';
      selection.hierarchyPath = chosen?.path ?? '';
      await switchContext(contextId, selection, 'hierarchy');
    });
  }

  async function attachExternalProject(event: SubmitEvent) {
    event.preventDefault();
    const name = externalProject;
    const filePath = externalPath;
    await requestTransition(async contextId => {
      const selection = selectedContext();
      selection.project = name;
      selection.projectPath = filePath;
      selection.su = 'None';
      selection.suPath = '';
      await switchContext(contextId, selection, 'plots');
    });
  }

  async function browseExternalSQLiteProject() {
    const contextId = $projectState?.contextId;
    if (!contextId) return;
    try {
      const inspection = await ContextService.ChooseExternalSQLiteFile(contextId);
      if (!inspection.selectedPath) return;
      externalPath = inspection.selectedPath;
      externalDiscoveredProjects = inspection.projects ?? [];
      const firstCompatible = externalDiscoveredProjects.find(p => p.compatible) ?? externalDiscoveredProjects[0];
      if (firstCompatible) {
        externalProject = firstCompatible.name;
        notifications.push({
          severity: 'info',
          category: 'general',
          source: 'Attach Project',
          title: `Found ${externalDiscoveredProjects.length} project(s)`,
          message: firstCompatible.file,
          toast: true,
        });
      } else {
        notifications.push({
          severity: 'warning',
          category: 'general',
          source: 'Attach Project',
          title: 'No project table found',
          message: 'Selected SQLite file contains no *_Env project table.',
          toast: true,
        });
      }
    } catch (cause) {
      const msg = await formatSidebarError(cause);
      notifications.push({
        severity: 'error',
        category: 'general',
        source: 'Attach Project',
        title: 'Could not inspect SQLite file',
        message: msg,
        toast: true,
      });
    }
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
      const msg =
        typeof formatSidebarError === 'function'
          ? await formatSidebarError(cause)
          : String(cause ?? '').replace(/^(?:RuntimeError|Error|CallError):\s*/i, '').trim();
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
    if (!contextId || !pathToInspect || accessWorking) return;
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
    try {
      await attachAccessProgressListener(contextId, 'inspect', reqGen);
      if (reqGen !== accessGeneration) return;
      const rawRpc = ImportExportService.InspectAccessDatabase(contextId, pathToInspect);
      const isCancellable =
        rawRpc !== null &&
        typeof rawRpc === 'object' &&
        typeof (rawRpc as { cancel?: unknown }).cancel === 'function';
      const trackedRpc =
        isCancellable && typeof accessRequests !== 'undefined'
          ? accessRequests.track(rawRpc as unknown as CancellableRead<AccessDatabaseInspection>)
          : rawRpc;
      activeAccessRpc = trackedRpc === rawRpc && isCancellable ? (rawRpc as { cancel: () => unknown }) : null;
      const inspection = await trackedRpc;
      if (reqGen !== accessGeneration) return;
      accessInspection = inspection;
      accessSourcePath = inspection.sourcePath;
      const projects = inspection.projects ?? [];
      const first = projects.find(p => p.compatible) ?? projects[0] ?? null;
      applyAccessCandidate(first);
      if (!first) {
        accessError = 'No VPro project tables (*_Env) were found in the selected Access database.';
      }
    } catch (cause) {
      if (reqGen !== accessGeneration || isCancelledAccessError(cause)) return;
      const msg = await formatSidebarError(cause);
      if (reqGen !== accessGeneration) return;
      accessInspection = null;
      accessError = `Access inspection failed: ${msg}`;
      notifications.push({
        severity: 'error',
        category: 'background',
        source: 'Access Import',
        title: 'Access inspection failed',
        message: msg,
      });
    } finally {
      if (reqGen === accessGeneration) {
        activeAccessRpc = null;
        clearAccessRuntimeTimersAndListeners();
        accessWorking = false;
        accessOperation = '';
        accessProgressPhase = '';
      }
    }
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
    if (!accessInspection || !accessSelectedSourceProject || !accessTargetProject || !accessDestinationPath || accessWorking) return;
    const sourcePath = accessInspection.sourcePath;
    const sourceProject = accessSelectedSourceProject;
    const targetProject = accessTargetProject;
    const destinationPath = accessDestinationPath;
    const activateOnSuccess = accessActivateOnSuccess;
    const expectedRows = (accessSelectedCandidate?.tables ?? []).reduce(
      (sum, tbl) => sum + (tbl.present ? (tbl.rowCount ?? 0) : 0),
      0
    );
    await requestTransition(async contextId => {
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
      try {
        await attachAccessProgressListener(contextId, 'import', reqGen);
        if (reqGen !== accessGeneration) return;
        const rawRpc = ImportExportService.ImportAccessProject(contextId, {
          sourcePath,
          sourceProject,
          targetProject,
          destinationPath,
          activateOnSuccess,
        });
        const isCancellable =
          rawRpc !== null &&
          typeof rawRpc === 'object' &&
          typeof (rawRpc as { cancel?: unknown }).cancel === 'function';
        const trackedRpc =
          isCancellable && typeof accessRequests !== 'undefined'
            ? accessRequests.track(rawRpc as unknown as CancellableRead<AccessProjectImportResult>)
            : rawRpc;
        activeAccessRpc = trackedRpc === rawRpc && isCancellable ? (rawRpc as { cancel: () => unknown }) : null;
        const result = await trackedRpc;
        if (reqGen !== accessGeneration) return;
        accessResult = result;
        notifications.push({
          severity: 'success',
          category: 'background',
          source: 'Access Import',
          title: `Imported ${result.targetProject} (${result.plotCount} plots)`,
          message: `Saved to ${result.destinationPath}`,
        });
        if (result.state) {
          projectState.set(result.state);
        }
        if (result.activated) {
          await onAccessActivated();
        }
      } catch (cause) {
        if (reqGen !== accessGeneration || isCancelledAccessError(cause)) return;
        const msg = await formatSidebarError(cause);
        if (reqGen !== accessGeneration) return;
        accessError = `Import failed: ${msg}`;
        notifications.push({
          severity: 'error',
          category: 'background',
          source: 'Access Import',
          title: 'Access project import failed',
          message: msg,
        });
      } finally {
        if (reqGen === accessGeneration) {
          activeAccessRpc = null;
          clearAccessRuntimeTimersAndListeners();
          accessWorking = false;
          accessOperation = '';
          accessProgressPhase = '';
        }
      }
    });
  }

  onDestroy(() => cancelAccessOperation(true));
</script>

<aside id="project-context" class="sidebar" aria-label="Projects">
  <div class="sidebar-heading">
    <span>PROJECTS</span>
    <button type="button" class="icon-button" title="Reveal VPRO database folder in File Explorer" aria-label="Reveal in File Explorer" disabled={busy || transitionWorking || !$projectState?.contextId} onclick={() => void revealInExplorer('projects')}>
      <FolderOpen size={16} strokeWidth={1.8} />
    </button>
  </div>
  <nav aria-label="Project list">
    {#each $projectState?.projects ?? [] as project ((project.path ?? project.file) + project.name)}
      <button class:active={project.name === $projectState?.activeProject && project.path === $projectState?.projectPath} disabled={!project.compatible || busy || editorBusy || companionPanelBusy || transitionWorking || accessWorking} title={project.compatible ? project.path : `${project.version} is not a complete VPro project`} onclick={() => chooseProject(project)}>
        <span class="project-name">{project.name}
          <span class="project-location">{$projectState?.projects?.filter(item => item.name === project.name).length === 1 ? project.file : project.path}</span>
        </span>
        <span class="project-version">{project.version}</span>
      </button>
    {/each}
  </nav>
  <div class="su-picker">
    <label for="active-su">SITE UNIT</label>
    <select id="active-su" value={String(activeSUIndex)} onchange={chooseSU} disabled={busy || editorBusy || companionPanelBusy || transitionWorking || accessWorking || !$projectState}>
      <option value="-1">None</option>
      {#each $projectState?.sus ?? [] as su, index ((su.path ?? '') + su.name)}
        <option value={String(index)} disabled={!su.compatible} title={su.path}>{su.name}{su.kind === 'master' ? ' (master)' : ''}</option>
      {/each}
    </select>
  </div>
  <div class="su-picker">
    <label for="active-hierarchy">HIERARCHY</label>
    <select id="active-hierarchy" value={String(activeHierarchyIndex)} onchange={chooseHierarchy} disabled={busy || editorBusy || companionPanelBusy || transitionWorking || accessWorking || !$projectState}>
      <option value="-1">None</option>
      {#each $projectState?.hierarchies ?? [] as hierarchy, index ((hierarchy.path ?? hierarchy.file) + hierarchy.name)}
        <option value={String(index)} disabled={!hierarchy.compatible} title={hierarchy.path}>{hierarchy.name} ({hierarchy.file})</option>
      {/each}
    </select>
  </div>
  {#if externalProjectsEnabled}
    <details class="su-picker">
      <summary>Attach external SQLite project</summary>
      <form onsubmit={attachExternalProject}>
        <button type="button" id="browse-external-sqlite" disabled={busy || editorBusy || companionPanelBusy || transitionWorking || !$projectState?.contextId} onclick={() => void browseExternalSQLiteProject()}>Browse SQLite .db file…</button>
        {#if externalDiscoveredProjects.length > 1}
          <label for="external-project-select">DISCOVERED PROJECTS IN FILE</label>
          <select id="external-project-select" value={externalProject} onchange={(e) => { externalProject = (e.currentTarget as HTMLSelectElement).value; }} disabled={busy || editorBusy || companionPanelBusy || transitionWorking}>
            {#each externalDiscoveredProjects as p (p.name)}
              <option value={p.name} disabled={!p.compatible}>{p.name} ({p.version})</option>
            {/each}
          </select>
        {/if}
        <label for="external-project">PROJECT PREFIX</label>
        <input id="external-project" bind:value={externalProject} required disabled={busy || editorBusy || companionPanelBusy || transitionWorking} />
        <label for="external-path">FULL SQLITE FILE PATH</label>
        <input id="external-path" bind:value={externalPath} required disabled={busy || editorBusy || companionPanelBusy || transitionWorking} />
        <p>Attaching opens the SQLite database in place without copying it; edits write directly to the attached file.</p>
        <button type="submit" disabled={busy || editorBusy || companionPanelBusy || transitionWorking}>Attach project</button>
      </form>
    </details>
    <details class="su-picker" id="access-import-wizard">
      <summary>Import Access (.mdb / .accdb) wizard</summary>
      <form onsubmit={runAccessProjectImport}>
        <button type="button" id="browse-access-db" disabled={busy || transitionWorking || accessWorking || !$projectState?.contextId} onclick={() => void browseAccessDatabase()}>Browse Access (.mdb / .accdb)…</button>
        <label for="access-source-path">ACCESS SOURCE FILE (.mdb / .accdb)</label>
        <input id="access-source-path" bind:value={accessSourcePath} placeholder="C:\path\to\project.accdb" disabled={busy || transitionWorking || accessWorking} />
        <button type="button" id="inspect-access-db" disabled={busy || transitionWorking || accessWorking || !accessSourcePath || !$projectState?.contextId} onclick={() => void inspectAccessSource()}>
          {accessWorking && accessOperation === 'inspect' ? 'Inspecting Access file…' : 'Inspect Access file'}
        </button>
        {#if accessInspection && (accessInspection.projects?.length ?? 0) > 0}
          <label for="access-source-project">SOURCE PROJECT IN ACCESS DB</label>
          <select id="access-source-project" value={accessSelectedSourceProject} onchange={(e) => {
            const chosen = (accessInspection?.projects ?? []).find(p => p.sourceProject === (e.currentTarget as HTMLSelectElement).value) ?? null;
            applyAccessCandidate(chosen);
          }} disabled={busy || transitionWorking || accessWorking}>
            {#each accessInspection.projects ?? [] as cand (cand.sourceProject)}
              <option value={cand.sourceProject}>{cand.sourceProject} ({cand.sourceVersion} · {cand.plotCount} plots)</option>
            {/each}
          </select>
          {#if accessSelectedCandidate}
            <p class="text-xs break-words"><strong>Autoconversion:</strong> {accessSelectedCandidate.conversionMode}</p>
            <p class="text-xs break-words">{accessSelectedCandidate.statusMessage}</p>
            {#if (accessSelectedCandidate.optionalSUs?.length ?? 0) > 0}
              <p class="text-xs break-words">SU tables included: {(accessSelectedCandidate.optionalSUs ?? []).join(', ')}</p>
            {/if}
          {/if}
          <label for="access-target-project">NEW VPRO PROJECT PREFIX</label>
          <input id="access-target-project" bind:value={accessTargetProject} required disabled={busy || transitionWorking || accessWorking} />
          <label for="access-dest-path">NEW SQLITE DESTINATION (.db)</label>
          <input id="access-dest-path" bind:value={accessDestinationPath} required disabled={busy || transitionWorking || accessWorking} />
          <button type="button" id="browse-access-dest" disabled={busy || transitionWorking || accessWorking || !$projectState?.contextId} onclick={() => void browseAccessDestinationPath()}>Browse destination .db…</button>
          <label class="flex items-center gap-2 text-xs">
            <input type="checkbox" style="width:auto;min-height:auto;" bind:checked={accessActivateOnSuccess} disabled={busy || transitionWorking || accessWorking} />
            Switch to imported project on completion
          </label>
          <button type="submit" id="convert-import-access-btn" disabled={busy || transitionWorking || accessWorking || !accessSelectedCandidate?.compatible || !accessTargetProject || !accessDestinationPath}>
            {accessWorking && accessOperation === 'import' ? 'Converting & importing…' : 'Convert & import to VPRO DB'}
          </button>
        {/if}
        {#if accessWorking}
          <div class="grid gap-1.5 rounded border border-vpro-navy/25 bg-vpro-navy-tint p-2 text-xs text-vpro-ink" data-access-import-progress aria-live="polite">
            <div class="flex items-center justify-between gap-2">
              <strong class="truncate text-vpro-navy">
                {accessOperation === 'inspect' ? 'Inspecting Access file…' : 'Importing Access project…'}
              </strong>
              <span class="shrink-0 tabular-nums text-[11px] text-vpro-ink-secondary" data-access-elapsed>{accessElapsedSeconds}s</span>
            </div>
            <progress
              class="h-2 w-full"
              max={100}
              value={accessProgressPercent ?? undefined}
              aria-label={accessOperation === 'inspect' ? 'Access file inspection progress' : 'Access project import progress'}
            ></progress>
            <p class="m-0 break-words text-[11px] text-vpro-ink-secondary" data-access-progress-detail>
              {accessProgressMessage || (accessOperation === 'inspect' ? 'Scanning tables…' : 'Preparing destination project file…')}{#if accessProgressRows > 0} ({accessProgressRows.toLocaleString()}{accessProgressExpectedRows > 0 ? ` / ${accessProgressExpectedRows.toLocaleString()}` : ''} rows{accessProgressPercent !== null ? ` · ${accessProgressPercent}%` : ''}){/if}
            </p>
            <button
              type="button"
              id="cancel-access-import-btn"
              class="rounded border border-vpro-error bg-white px-2 py-1 text-xs font-semibold text-vpro-error"
              onclick={() => cancelAccessOperation(false)}
            >
              {accessOperation === 'inspect' ? 'Cancel inspection' : 'Cancel import'}
            </button>
          </div>
        {/if}
        {#if accessStatusNotice && !accessWorking}
          <p role="status" class="m-0 text-xs text-vpro-ink-secondary break-words">{accessStatusNotice}</p>
        {/if}
        {#if accessError}<p role="alert" class="text-vpro-error break-words">{accessError}</p>{/if}
        {#if accessResult}
          {@const overflowQuarantined = (accessResult as { quarantinedOverflowRows?: number }).quarantinedOverflowRows ?? 0}
          <div role="status" class="grid gap-1 text-xs text-vpro-forest break-words">
            <p class="m-0">
              Imported {accessResult.targetProject} ({accessResult.plotCount} plots, {accessResult.conversionMode}) into {accessResult.destinationPath}.
            </p>
            {#if (accessResult.quarantinedMalformedRows ?? 0) > 0 || (accessResult.quarantinedOrphanRows ?? 0) > 0 || overflowQuarantined > 0}
              <p
                role="alert"
                data-access-quarantine-summary
                class="m-0 rounded border border-vpro-gold bg-vpro-warning-bg px-2 py-1 text-[11px] font-medium text-vpro-ink"
              >
                Access import quarantined rows for review:
                {accessResult.quarantinedMalformedRows ?? 0} malformed,
                {accessResult.quarantinedOrphanRows ?? 0} orphan{overflowQuarantined > 0 ? `, ${overflowQuarantined} overflow` : ''}.
              </p>
            {/if}
          </div>
        {/if}
      </form>
    </details>
  {/if}
  <div class="su-picker">
    <label for="reveal-explorer-btn">DATA ON DISK</label>
    <div class="grid gap-1.5">
      <button type="button" id="reveal-explorer-btn" class="px-2 py-1.5 border rounded bg-white text-xs text-left" disabled={busy || transitionWorking || !$projectState?.contextId} onclick={() => void revealInExplorer('project')}>
        Reveal active project .db in File Explorer
      </button>
      <button type="button" id="reveal-root-explorer-btn" class="px-2 py-1.5 border rounded bg-white text-xs text-left" disabled={busy || transitionWorking || !$projectState?.contextId} onclick={() => void revealInExplorer('root')}>
        Open VPRO DBs root folder in File Explorer
      </button>
    </div>
  </div>
  <div class="sidebar-footer">{$projectState?.projects?.length ?? 0} project{($projectState?.projects?.length ?? 0) === 1 ? '' : 's'}</div>
</aside>
