<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import {
    BarChart3,
    ExternalLink,
    FileSpreadsheet,
    FileText,
    Map as MapIcon,
    Table2,
  } from '@lucide/svelte';
  import {
    ContextService,
    SpatialService,
    type PMTilesManifest,
    type ProjectState,
  } from '../../bindings/github.com/boostao/vpro/app';
  import type { ContextSelection } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
  import { formatError } from '../shared/readRequests';
  import { projectState, webMeta } from '../shared/state';
  import WebDownloadCard from './WebDownloadCard.svelte';
  import WebFilterSidebar from './WebFilterSidebar.svelte';
  import WebMapCanvas from './WebMapCanvas.svelte';
  import WebPlotCardDrawer from './WebPlotCardDrawer.svelte';
  import {
    buildFilterRequestFromState,
    createEmptyBECMasterFilterState,
    fetchBECMasterFilterOptions,
    filterBECMasterPlots,
    hasActiveFilterSelections,
    parseBoundingBoxFromState,
    parseExplorerUrlState,
    syncExplorerUrlState,
    type BECMasterBoundingBox,
    type BECMasterFilterOptions,
    type BECMasterFilterState,
    type BECMasterMapPoint,
    type WebExplorerTabId,
  } from './webBECMasterFilter';
  import {
    DEFAULT_EXTERNAL_LINKS,
    loadWebMeta,
    resolveWebPMTilesBaseUrl,
    type WebMetaResponse,
  } from './webMeta';

  type ReportSubTab =
    | 'summary-veg'
    | 'long-veg'
    | 'lifeform-summary'
    | 'summary-env'
    | 'long-env'
    | 'subzone-matrix'
    | 'quarto-unit';
  type AnalysisSubTab = 'synthesis' | 'r-analytics';

  let activeTab = $state<WebExplorerTabId>('map');
  let reportTab = $state<ReportSubTab>('summary-veg');
  let analysisTab = $state<AnalysisSubTab>('synthesis');

  let ctxState = $state<ProjectState | null>(null);
  let meta = $state<WebMetaResponse | null>(null);
  let manifest = $state<PMTilesManifest | null>(null);

  let filterOptions = $state<BECMasterFilterOptions | null>(null);
  let filter = $state<BECMasterFilterState>(createEmptyBECMasterFilterState());
  let appliedFilter = $state<BECMasterFilterState>(createEmptyBECMasterFilterState());
  let sidebarCollapsed = $state(false);
  let drawBBoxMode = $state(false);

  let allPoints = $state.raw<BECMasterMapPoint[]>([]);
  let matchedPoints = $state.raw<BECMasterMapPoint[]>([]);
  let matchedPlotNumbers = $state.raw<string[]>([]);
  let totalPlots = $state(0);
  let matchedCount = $state(0);

  let activePlotNumber = $state<string | null>(null);
  let bootstrapping = $state(true);
  let switchingContext = $state(false);
  let loadingOptions = $state(false);
  let applyingFilter = $state(false);
  let pageError = $state('');

  let mapCanvasRef = $state<{ fitToPoints?: (pts?: readonly BECMasterMapPoint[]) => void } | undefined>(undefined);
  let initDone = false;
  let loadSeq = 0;
  let filterAbort: AbortController | null = null;

  const noopBusy = (_busy: boolean) => {};

  const isFiltered = $derived(hasActiveFilterSelections(appliedFilter));
  const activeBBox = $derived(filter.mode === 'bbox' ? parseBoundingBoxFromState(filter) : null);
  const pmtilesBaseUrl = $derived(resolveWebPMTilesBaseUrl(meta));
  const externalLinks = $derived(meta?.externalLinks ?? [...DEFAULT_EXTERNAL_LINKS]);
  const rAvailable = $derived(meta?.rAvailable !== false);

  const snapshotId = $derived(meta?.snapshotId || 'BECMaster Snapshot');
  const snapshotDate = $derived(meta?.publishedAt ? meta.publishedAt.slice(0, 10) : '');
  const activeMetaDataset = $derived(
    meta?.datasets.find((d) => d.project === ctxState?.activeProject || d.id === ctxState?.activeProject) ??
      meta?.datasets[0] ??
      null
  );
  const snapshotTotalPlots = $derived(
    totalPlots || activeMetaDataset?.plotCount || meta?.totalPlotCount || 0
  );
  const redacted = $derived(Boolean(meta?.redacted));
  const redactionNotice = $derived(
    meta?.redactionNotice ||
      'Coordinates for plots with conservation-listed species are generalized to 10 km for rare-plant protection.'
  );

  const availableProjects = $derived(ctxState?.projects ?? []);
  const availableSUs = $derived(ctxState?.sus ?? []);
  const availableHierarchies = $derived(ctxState?.hierarchies ?? []);
  const showContextSelectors = $derived(
    availableProjects.length > 1 || availableSUs.length > 0 || availableHierarchies.length > 0
  );

  function syncUrlNow() {
    if (!initDone || typeof window === 'undefined') return;
    syncExplorerUrlState({
      tab: activeTab,
      dataset: ctxState?.activeProject || undefined,
      su: ctxState?.activeSU && ctxState.activeSU !== 'None' ? ctxState.activeSU : undefined,
      hierarchy:
        ctxState?.activeHierarchy && ctxState.activeHierarchy !== 'None' ? ctxState.activeHierarchy : undefined,
      plot: activePlotNumber || undefined,
      filter: appliedFilter,
    });
  }

  $effect(() => {
    void activeTab;
    void ctxState?.activeProject;
    void ctxState?.activeSU;
    void ctxState?.activeHierarchy;
    void activePlotNumber;
    void appliedFilter;
    syncUrlNow();
  });

  async function loadDatasetFilterData(
    ctxId: string,
    initialFilter: BECMasterFilterState,
    seq: number
  ) {
    filterAbort?.abort();
    const controller = new AbortController();
    filterAbort = controller;

    loadingOptions = true;
    applyingFilter = true;
    pageError = '';
    try {
      const [opts, allRes, manifestRes] = await Promise.all([
        fetchBECMasterFilterOptions(ctxId, { signal: controller.signal }),
        filterBECMasterPlots(ctxId, { mode: 'all' }, { signal: controller.signal }),
        SpatialService.GetPMTilesManifest().catch(() => null),
      ]);
      if (seq !== loadSeq) return;

      filterOptions = opts;
      manifest = manifestRes;
      allPoints = allRes.points ?? [];
      totalPlots = allRes.totalPlots ?? opts.totalPlots ?? allPoints.length;

      if (hasActiveFilterSelections(initialFilter)) {
        const filteredRes = await filterBECMasterPlots(ctxId, buildFilterRequestFromState(initialFilter), {
          signal: controller.signal,
        });
        if (seq !== loadSeq) return;
        matchedPoints = filteredRes.points ?? [];
        matchedPlotNumbers = filteredRes.plotNumbers ?? [];
        matchedCount = filteredRes.matchedCount ?? matchedPlotNumbers.length;
        appliedFilter = structuredClone($state.snapshot(initialFilter));
      } else {
        matchedPoints = allRes.points ?? [];
        matchedPlotNumbers = allRes.plotNumbers ?? [];
        matchedCount = allRes.matchedCount ?? matchedPlotNumbers.length;
        appliedFilter = createEmptyBECMasterFilterState();
      }
    } catch (cause) {
      if (controller.signal.aborted || seq !== loadSeq) return;
      pageError = `Could not load BECMaster plots: ${formatError(cause)}`;
    } finally {
      if (seq === loadSeq) {
        loadingOptions = false;
        applyingFilter = false;
      }
    }
  }

  async function applyCurrentFilter() {
    const ctxId = ctxState?.contextId?.trim() ?? '';
    if (!ctxId) return;
    filterAbort?.abort();
    const controller = new AbortController();
    filterAbort = controller;

    applyingFilter = true;
    pageError = '';
    drawBBoxMode = false;
    const snapshotFilter = structuredClone($state.snapshot(filter));
    try {
      const req = buildFilterRequestFromState(snapshotFilter);
      const res = await filterBECMasterPlots(ctxId, req, { signal: controller.signal });
      if (controller.signal.aborted) return;
      totalPlots = res.totalPlots ?? totalPlots;
      matchedCount = res.matchedCount ?? (res.plotNumbers?.length ?? 0);
      matchedPlotNumbers = res.plotNumbers ?? [];
      matchedPoints = res.points ?? [];
      appliedFilter = snapshotFilter;
      if (matchedPoints.length > 0) {
        mapCanvasRef?.fitToPoints?.(matchedPoints);
      }
    } catch (cause) {
      if (controller.signal.aborted) return;
      pageError = `Could not apply plot filter: ${formatError(cause)}`;
    } finally {
      if (!controller.signal.aborted) {
        applyingFilter = false;
      }
    }
  }

  async function clearAllFilters() {
    drawBBoxMode = false;
    filter = createEmptyBECMasterFilterState();
    appliedFilter = createEmptyBECMasterFilterState();
    const ctxId = ctxState?.contextId?.trim() ?? '';
    if (!ctxId) return;
    await applyCurrentFilter();
  }

  function handleBBoxChange(nextBox: BECMasterBoundingBox) {
    filter = {
      ...filter,
      mode: 'bbox',
      nwLat: String(nextBox.nwLat),
      nwLon: String(nextBox.nwLon),
      seLat: String(nextBox.seLat),
      seLon: String(nextBox.seLon),
    };
  }

  function handleStartDrawBBoxFromMap() {
    if (filter.mode !== 'bbox') {
      filter = { ...filter, mode: 'bbox' };
    }
  }

  async function switchContextSelection(partial: { project?: string; su?: string; hierarchy?: string }) {
    if (!ctxState?.contextId || switchingContext) return;
    const targetProjectName = partial.project ?? ctxState.activeProject;
    const projEntry = availableProjects.find(
      (p) => p.name === targetProjectName || p.file === targetProjectName
    );
    const targetSUName = partial.su ?? ctxState.activeSU ?? 'None';
    const suEntry = availableSUs.find((s) => s.name === targetSUName);
    const targetHierName = partial.hierarchy ?? ctxState.activeHierarchy ?? 'None';
    const hierEntry = availableHierarchies.find((h) => h.name === targetHierName);

    const selection: ContextSelection = {
      project: projEntry?.name ?? targetProjectName,
      projectPath: projEntry?.path ?? ctxState.projectPath ?? '',
      su: targetSUName === 'None' ? 'None' : (suEntry?.name ?? targetSUName),
      suPath: targetSUName === 'None' ? '' : (suEntry?.path ?? ctxState.suPath ?? ''),
      hierarchy: targetHierName === 'None' ? 'None' : (hierEntry?.name ?? targetHierName),
      hierarchyPath: targetHierName === 'None' ? '' : (hierEntry?.path ?? ctxState.hierarchyPath ?? ''),
    };

    switchingContext = true;
    pageError = '';
    activePlotNumber = null;
    const seq = ++loadSeq;
    try {
      const nextState = await ContextService.SwitchContext(ctxState.contextId, selection);
      if (seq !== loadSeq) return;
      ctxState = nextState;
      projectState.set(nextState);
      filter = createEmptyBECMasterFilterState();
      appliedFilter = createEmptyBECMasterFilterState();
      if (nextState.contextId) {
        await loadDatasetFilterData(nextState.contextId, filter, seq);
      }
    } catch (cause) {
      if (seq !== loadSeq) return;
      pageError = `Could not switch dataset context: ${formatError(cause)}`;
    } finally {
      if (seq === loadSeq) {
        switchingContext = false;
      }
    }
  }

  function handleOpenPlot(plotNumber: string) {
    const cleaned = String(plotNumber ?? '').trim();
    if (!cleaned) return;
    activePlotNumber = cleaned;
  }

  onMount(() => {
    const seq = ++loadSeq;
    void (async () => {
      bootstrapping = true;
      pageError = '';
      try {
        const urlState =
          typeof window !== 'undefined' ? parseExplorerUrlState(window.location.search) : {};
        if (urlState.tab) activeTab = urlState.tab;
        if (urlState.filter) {
          filter = { ...createEmptyBECMasterFilterState(), ...urlState.filter };
        }

        const [loadedMeta, initialState] = await Promise.all([
          loadWebMeta({ ignoreMode: true }),
          ContextService.GetState(),
        ]);
        if (seq !== loadSeq) return;

        meta = loadedMeta;
        if (loadedMeta) webMeta.set(loadedMeta);

        let activeState = initialState;
        const wantsSwitch = Boolean(
          initialState?.contextId &&
            ((urlState.dataset && urlState.dataset !== initialState.activeProject) ||
              (urlState.su && urlState.su !== initialState.activeSU) ||
              (urlState.hierarchy && urlState.hierarchy !== initialState.activeHierarchy))
        );

        if (wantsSwitch && initialState?.contextId) {
          const targetProj = urlState.dataset
            ? initialState.projects?.find((p) => p.name === urlState.dataset || p.file === urlState.dataset)
            : initialState.projects?.find((p) => p.name === initialState.activeProject);
          const targetSU = urlState.su ? initialState.sus?.find((s) => s.name === urlState.su) : undefined;
          const targetHier = urlState.hierarchy
            ? initialState.hierarchies?.find((h) => h.name === urlState.hierarchy)
            : undefined;
          try {
            activeState = await ContextService.SwitchContext(initialState.contextId, {
              project: targetProj?.name ?? initialState.activeProject,
              projectPath: targetProj?.path ?? initialState.projectPath ?? '',
              su: urlState.su ? (targetSU?.name ?? urlState.su) : initialState.activeSU,
              suPath: urlState.su ? (targetSU?.path ?? '') : (initialState.suPath ?? ''),
              hierarchy: urlState.hierarchy ? (targetHier?.name ?? urlState.hierarchy) : initialState.activeHierarchy,
              hierarchyPath: urlState.hierarchy ? (targetHier?.path ?? '') : (initialState.hierarchyPath ?? ''),
            });
          } catch {
            activeState = initialState;
          }
        }

        if (seq !== loadSeq) return;
        ctxState = activeState;
        projectState.set(activeState);

        if (urlState.plot) {
          activePlotNumber = urlState.plot;
        }

        if (activeState?.contextId) {
          await loadDatasetFilterData(activeState.contextId, filter, seq);
        }
        initDone = true;
        syncUrlNow();
      } catch (cause) {
        if (seq !== loadSeq) return;
        pageError = `Could not start BECMaster Explorer: ${formatError(cause)}`;
      } finally {
        if (seq === loadSeq) {
          bootstrapping = false;
        }
      }
    })();
  });

  onDestroy(() => {
    loadSeq++;
    filterAbort?.abort();
  });
</script>

<div class="web-explorer-root" data-web-becmaster-explorer>
  <!-- BC Gov Top Navigation Bar -->
  <header class="web-topbar" data-web-topbar>
    <div class="web-topbar-row">
      <div class="web-brand">
        <svg
          width="30"
          height="30"
          viewBox="0 0 32 32"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
          aria-hidden="true"
          focusable="false"
        >
          <rect width="32" height="32" rx="6" fill="#002244" />
          <rect y="28" width="32" height="4" fill="#FCBA19" />
          <g transform="translate(2.5 0.5) scale(0.0263)">
            <path
              d="M512 162L216 286V512C216 681 342 827 512 864C682 827 808 681 808 512V286Z"
              fill="#1E5128"
              stroke="#FCBA19"
              stroke-width="48"
              stroke-linejoin="round"
            />
            <path d="M488 614H536L542 754Q512 764 482 754Z" fill="#FCBA19" />
            <path d="M512 454L698 654Q512 618 326 654Z" fill="#FFFFFF" />
            <path d="M512 344L656 518Q512 488 368 518Z" fill="#FFFFFF" />
            <path d="M512 244L614 396Q512 372 410 396Z" fill="#FFFFFF" />
          </g>
        </svg>
        <div class="web-brand-text">
          <h1 class="web-brand-title">VPro — BECMaster Explorer</h1>
          <div class="web-provenance-row">
            <span class="web-provenance-chip tabular-nums" data-web-snapshot-badge>
              {snapshotId}{#if snapshotDate} · {snapshotDate}{/if}{#if snapshotTotalPlots > 0} · {snapshotTotalPlots.toLocaleString()} plots{/if}
            </span>
            {#if redacted}
              <span
                class="web-redaction-pill"
                title={redactionNotice}
                data-web-redaction-badge
              >
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" aria-hidden="true">
                  <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
                  <line x1="12" y1="8" x2="12" y2="12" />
                  <line x1="12" y1="16" x2="12.01" y2="16" />
                </svg>
                <span>10 km Rare-Plant Protection</span>
              </span>
            {/if}
          </div>
        </div>
      </div>

      <!-- View Tabs -->
      <nav class="web-view-tabs" aria-label="Explorer views" data-web-view-tabs>
        <button
          type="button"
          class="web-tab-btn"
          class:active={activeTab === 'map'}
          aria-current={activeTab === 'map' ? 'page' : undefined}
          onclick={() => (activeTab = 'map')}
          data-web-tab="map"
        >
          <MapIcon size={14} aria-hidden="true" />
          <span>Map &amp; Filter</span>
        </button>
        <button
          type="button"
          class="web-tab-btn"
          class:active={activeTab === 'datasheet'}
          aria-current={activeTab === 'datasheet' ? 'page' : undefined}
          onclick={() => (activeTab = 'datasheet')}
          data-web-tab="datasheet"
        >
          <Table2 size={14} aria-hidden="true" />
          <span>Datasheet</span>
        </button>
        <button
          type="button"
          class="web-tab-btn"
          class:active={activeTab === 'reports'}
          aria-current={activeTab === 'reports' ? 'page' : undefined}
          onclick={() => (activeTab = 'reports')}
          data-web-tab="reports"
        >
          <FileText size={14} aria-hidden="true" />
          <span>Reports</span>
        </button>
        <button
          type="button"
          class="web-tab-btn"
          class:active={activeTab === 'analysis'}
          aria-current={activeTab === 'analysis' ? 'page' : undefined}
          onclick={() => (activeTab = 'analysis')}
          data-web-tab="analysis"
        >
          <BarChart3 size={14} aria-hidden="true" />
          <span>Analysis</span>
        </button>
      </nav>

      <!-- External BEC Links -->
      {#if externalLinks.length > 0}
        <nav class="web-ext-links" aria-label="External BEC resources" data-web-external-links>
          {#each externalLinks as link (link.url)}
            <a
              href={link.url}
              target="_blank"
              rel="noopener noreferrer"
              class="web-ext-link"
              title={link.description || link.label}
              data-web-external-link={link.label}
            >
              <span>{link.label}</span>
              <ExternalLink size={11} aria-hidden="true" />
            </a>
          {/each}
        </nav>
      {/if}
    </div>

    <!-- Optional Compact Dataset / SU / Hierarchy Context Selector -->
    {#if showContextSelectors && ctxState}
      <div class="web-context-bar" data-web-context-bar>
        {#if availableProjects.length > 1}
          <label class="web-ctx-field">
            <span>Dataset</span>
            <select
              value={ctxState.activeProject}
              disabled={switchingContext}
              onchange={(e) => void switchContextSelection({ project: e.currentTarget.value })}
              data-web-dataset-select
            >
              {#each availableProjects as proj (proj.name)}
                <option value={proj.name}>{proj.name}</option>
              {/each}
            </select>
          </label>
        {/if}
        {#if availableSUs.length > 0}
          <label class="web-ctx-field">
            <span>Site Unit (SU)</span>
            <select
              value={ctxState.activeSU || 'None'}
              disabled={switchingContext}
              onchange={(e) => void switchContextSelection({ su: e.currentTarget.value })}
              data-web-su-select
            >
              <option value="None">All Plots (No SU filter)</option>
              {#each availableSUs as su (su.name)}
                <option value={su.name}>{su.name}</option>
              {/each}
            </select>
          </label>
        {/if}
        {#if availableHierarchies.length > 0}
          <label class="web-ctx-field">
            <span>Hierarchy</span>
            <select
              value={ctxState.activeHierarchy || 'None'}
              disabled={switchingContext}
              onchange={(e) => void switchContextSelection({ hierarchy: e.currentTarget.value })}
              data-web-hierarchy-select
            >
              <option value="None">None</option>
              {#each availableHierarchies as h (h.name)}
                <option value={h.name}>{h.name}</option>
              {/each}
            </select>
          </label>
        {/if}
      </div>
    {/if}
  </header>

  {#if pageError}
    <div class="web-error-strip" role="alert" data-web-error-banner>
      <span>{pageError}</span>
    </div>
  {/if}

  <!-- Main Workspace -->
  <main class="web-main">
    {#if activeTab === 'map'}
      <div class="web-map-workspace" data-web-map-workspace>
        <WebFilterSidebar
          options={filterOptions}
          bind:filter
          bind:collapsed={sidebarCollapsed}
          bind:drawBBoxMode
          {loadingOptions}
          applying={applyingFilter || switchingContext}
          onApply={() => void applyCurrentFilter()}
          onClear={() => void clearAllFilters()}
        />

        <div class="web-map-right-col">
          <WebMapCanvas
            bind:this={mapCanvasRef}
            {allPoints}
            {matchedPoints}
            {isFiltered}
            activePlotNumber={activePlotNumber ?? ''}
            bbox={activeBBox}
            bind:drawBBoxMode
            {pmtilesBaseUrl}
            {manifest}
            onSelectPlot={handleOpenPlot}
            onBBoxChange={handleBBoxChange}
            onStartDrawBBox={handleStartDrawBBoxFromMap}
          />

          <WebDownloadCard
            contextId={ctxState?.contextId ?? ''}
            {matchedCount}
            {totalPlots}
            plotNumbers={matchedPlotNumbers}
            {meta}
          />
        </div>
      </div>
    {:else if activeTab === 'datasheet'}
      <div class="web-deferred-pane" data-web-datasheet-view>
        {#if bootstrapping || !ctxState}
          <p role="status" class="web-deferred-status">Loading workspace...</p>
        {:else}
          {#key ctxState.contextId}
            {#await import('../datasheet/UniversalDatasheetGrid.svelte')}
              <p role="status" class="web-deferred-status">Loading Datasheet...</p>
            {:then { default: UniversalDatasheetGrid }}
              <UniversalDatasheetGrid
                contextId={ctxState.contextId ?? ''}
                project={ctxState.activeProject}
                su={ctxState.activeSU}
                hierarchy={ctxState.activeHierarchy}
                onOpenPlot={handleOpenPlot}
              />
            {:catch loadError}
              <p role="alert" class="web-deferred-error">
                Datasheet could not load: {formatError(loadError)}
              </p>
            {/await}
          {/key}
        {/if}
      </div>
    {:else if activeTab === 'reports'}
      <div class="web-deferred-pane" data-web-reports-view>
        <div class="web-subtab-bar" role="tablist" aria-label="Read-only BEC reports">
          {#each [
            { id: 'summary-veg', label: 'Summary Vegetation' },
            { id: 'long-veg', label: 'Long Vegetation' },
            { id: 'lifeform-summary', label: 'Lifeform & Species Attributes' },
            { id: 'summary-env', label: 'Site Unit Summary (Env)' },
            { id: 'long-env', label: 'Long Environment' },
            { id: 'subzone-matrix', label: 'Subzone Matrix' },
            { id: 'quarto-unit', label: 'Quarto Unit Report' },
          ] as sub (sub.id)}
            <button
              type="button"
              role="tab"
              aria-selected={reportTab === sub.id}
              class="web-subtab-btn"
              class:active={reportTab === sub.id}
              onclick={() => (reportTab = sub.id as ReportSubTab)}
              data-web-report-tab={sub.id}
            >
              <FileSpreadsheet size={13} aria-hidden="true" />
              <span>{sub.label}</span>
            </button>
          {/each}
        </div>

        <div class="web-subtab-content">
          {#if bootstrapping || !ctxState}
            <p role="status" class="web-deferred-status">Loading workspace...</p>
          {:else}
            {#key ctxState.contextId}
              {#if reportTab === 'summary-veg'}
                {#await import('../reports/SummaryVegetationReport.svelte')}
                  <p role="status" class="web-deferred-status">Loading Summary Vegetation Report...</p>
                {:then { default: SummaryVegetationReport }}
                  <SummaryVegetationReport
                    contextId={ctxState.contextId ?? ''}
                    project={ctxState.activeProject}
                    projectPath={ctxState.projectPath ?? ''}
                    su={ctxState.activeSU}
                    suPath={ctxState.suPath ?? ''}
                    hierarchy={ctxState.activeHierarchy ?? 'None'}
                    onBusyChange={noopBusy}
                  />
                {:catch loadError}
                  <p role="alert" class="web-deferred-error">
                    Summary Vegetation Report could not load: {formatError(loadError)}
                  </p>
                {/await}
              {:else if reportTab === 'long-veg'}
                {#await import('../reports/LongVegetationReport.svelte')}
                  <p role="status" class="web-deferred-status">Loading Long Vegetation Report...</p>
                {:then { default: LongVegetationReport }}
                  <LongVegetationReport
                    contextId={ctxState.contextId ?? ''}
                    project={ctxState.activeProject}
                    projectPath={ctxState.projectPath ?? ''}
                    su={ctxState.activeSU}
                    suPath={ctxState.suPath ?? ''}
                    hierarchy={ctxState.activeHierarchy ?? 'None'}
                    onBusyChange={noopBusy}
                  />
                {:catch loadError}
                  <p role="alert" class="web-deferred-error">
                    Long Vegetation Report could not load: {formatError(loadError)}
                  </p>
                {/await}
              {:else if reportTab === 'lifeform-summary'}
                {#await import('../reports/LifeformSummary.svelte')}
                  <p role="status" class="web-deferred-status">Loading Lifeform &amp; Species Attributes...</p>
                {:then { default: LifeformSummary }}
                  <LifeformSummary
                    contextId={ctxState.contextId ?? ''}
                    project={ctxState.activeProject}
                    projectPath={ctxState.projectPath ?? ''}
                    su={ctxState.activeSU}
                    suPath={ctxState.suPath ?? ''}
                    onBusyChange={noopBusy}
                  />
                {:catch loadError}
                  <p role="alert" class="web-deferred-error">
                    Lifeform &amp; Species Attributes could not load: {formatError(loadError)}
                  </p>
                {/await}
              {:else if reportTab === 'summary-env'}
                {#await import('../reports/SiteUnitSummary.svelte')}
                  <p role="status" class="web-deferred-status">Loading Site Unit Summary...</p>
                {:then { default: SiteUnitSummary }}
                  <SiteUnitSummary
                    contextId={ctxState.contextId ?? ''}
                    project={ctxState.activeProject}
                    projectPath={ctxState.projectPath ?? ''}
                    su={ctxState.activeSU}
                    suPath={ctxState.suPath ?? ''}
                    onBusyChange={noopBusy}
                  />
                {:catch loadError}
                  <p role="alert" class="web-deferred-error">
                    Site Unit Summary could not load: {formatError(loadError)}
                  </p>
                {/await}
              {:else if reportTab === 'long-env'}
                {#await import('../reports/LongEnvironmentReport.svelte')}
                  <p role="status" class="web-deferred-status">Loading Long Environment Report...</p>
                {:then { default: LongEnvironmentReport }}
                  <LongEnvironmentReport
                    contextId={ctxState.contextId ?? ''}
                    project={ctxState.activeProject}
                    projectPath={ctxState.projectPath ?? ''}
                    su={ctxState.activeSU}
                    suPath={ctxState.suPath ?? ''}
                    onBusyChange={noopBusy}
                  />
                {:catch loadError}
                  <p role="alert" class="web-deferred-error">
                    Long Environment Report could not load: {formatError(loadError)}
                  </p>
                {/await}
              {:else if reportTab === 'subzone-matrix'}
                {#await import('../reports/SubzoneMatrixReport.svelte')}
                  <p role="status" class="web-deferred-status">Loading Subzone Matrix Report...</p>
                {:then { default: SubzoneMatrixReport }}
                  <SubzoneMatrixReport
                    contextId={ctxState.contextId ?? ''}
                    hierarchy={ctxState.activeHierarchy}
                    hierarchyPath={ctxState.hierarchyPath ?? ''}
                    onBusyChange={noopBusy}
                  />
                {:catch loadError}
                  <p role="alert" class="web-deferred-error">
                    Subzone Matrix Report could not load: {formatError(loadError)}
                  </p>
                {/await}
              {:else if reportTab === 'quarto-unit'}
                {#if !rAvailable}
                  <p role="status" class="web-deferred-status">
                    Quarto Unit Reports are currently unavailable on this server because the R analytical environment is not active.
                  </p>
                {:else}
                  {#await import('../rsidecar/RSidecarWorkbench.svelte')}
                    <p role="status" class="web-deferred-status">Loading Quarto Unit Report generator...</p>
                  {:then { default: RSidecarWorkbench }}
                    <RSidecarWorkbench
                      contextId={ctxState.contextId ?? ''}
                      activeProject={ctxState.activeProject}
                      activeSu={ctxState.activeSU}
                      initialTab="quarto"
                      standaloneQuartoMode={true}
                    />
                  {:catch loadError}
                    <p role="alert" class="web-deferred-error">
                      Quarto Unit Report could not load: {formatError(loadError)}
                    </p>
                  {/await}
                {/if}
              {/if}
            {/key}
          {/if}
        </div>
      </div>
    {:else if activeTab === 'analysis'}
      <div class="web-deferred-pane" data-web-analysis-view>
        <div class="web-subtab-bar" role="tablist" aria-label="Read-only BEC analysis">
          <button
            type="button"
            role="tab"
            aria-selected={analysisTab === 'synthesis'}
            class="web-subtab-btn"
            class:active={analysisTab === 'synthesis'}
            onclick={() => (analysisTab = 'synthesis')}
            data-web-analysis-tab="synthesis"
          >
            <span>BEC Diagnostic Synthesis</span>
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={analysisTab === 'r-analytics'}
            class="web-subtab-btn"
            class:active={analysisTab === 'r-analytics'}
            onclick={() => (analysisTab = 'r-analytics')}
            data-web-analysis-tab="r-analytics"
          >
            <span>R Climate (climr / aSMR) &amp; Clustering</span>
          </button>
        </div>

        <div class="web-subtab-content">
          {#if bootstrapping || !ctxState}
            <p role="status" class="web-deferred-status">Loading workspace...</p>
          {:else}
            {#key ctxState.contextId}
              {#if analysisTab === 'synthesis'}
                {#await import('../diagnostics/ClassificationSynthesisView.svelte')}
                  <p role="status" class="web-deferred-status">Loading BEC Diagnostic Synthesis...</p>
                {:then { default: ClassificationSynthesisView }}
                  <ClassificationSynthesisView
                    contextId={ctxState.contextId ?? ''}
                    project={ctxState.activeProject}
                    su={ctxState.activeSU}
                    onOpenPlot={handleOpenPlot}
                  />
                {:catch loadError}
                  <p role="alert" class="web-deferred-error">
                    BEC Diagnostic Synthesis could not load: {formatError(loadError)}
                  </p>
                {/await}
              {:else}
                {#if !rAvailable}
                  <p role="status" class="web-deferred-status">
                    R climate (climr / aSMR) and clustering tools are currently unavailable on this server.
                  </p>
                {:else}
                  {#await import('../rsidecar/RSidecarWorkbench.svelte')}
                    <p role="status" class="web-deferred-status">Loading R Analysis &amp; Guides...</p>
                  {:then { default: RSidecarWorkbench }}
                    <RSidecarWorkbench
                      contextId={ctxState.contextId ?? ''}
                      activeProject={ctxState.activeProject}
                      activeSu={ctxState.activeSU}
                    />
                  {:catch loadError}
                    <p role="alert" class="web-deferred-error">
                      R Analysis &amp; Guides could not load: {formatError(loadError)}
                    </p>
                  {/await}
                {/if}
              {/if}
            {/key}
          {/if}
        </div>
      </div>
    {/if}
  </main>

  <WebPlotCardDrawer
    contextId={ctxState?.contextId ?? ''}
    plotNumber={activePlotNumber}
    onclose={() => {
      activePlotNumber = null;
    }}
  />
</div>

<style>
  .web-explorer-root {
    min-height: 100vh;
    height: 100vh;
    display: flex;
    flex-direction: column;
    background: var(--vpro-canvas, #f2f4f6);
    color: var(--vpro-ink, #313132);
    font-family: var(--vpro-font-sans, sans-serif);
    overflow: hidden;
  }

  .web-topbar {
    background: var(--vpro-navy, #003366);
    color: #ffffff;
    border-bottom: 3px solid var(--vpro-gold, #fcba19);
    flex-shrink: 0;
  }

  .web-topbar-row {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 8px 16px;
  }

  .web-brand {
    display: flex;
    align-items: center;
    gap: 10px;
    min-width: 0;
  }

  .web-brand-text {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }

  .web-brand-title {
    margin: 0;
    font-size: 16px;
    font-weight: 700;
    letter-spacing: -0.01em;
    color: #ffffff;
    line-height: 1.2;
  }

  .web-provenance-row {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 6px;
  }

  .web-provenance-chip {
    font-size: 11px;
    color: rgba(255, 255, 255, 0.88);
  }

  .web-redaction-pill {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 1px 6px;
    border-radius: 3px;
    background: var(--vpro-gold, #fcba19);
    color: #002244;
    font-size: 10.5px;
    font-weight: 700;
  }

  .web-view-tabs {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 4px;
  }

  .web-tab-btn {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 6px 12px;
    border-radius: 4px;
    border: 1px solid rgba(255, 255, 255, 0.22);
    background: rgba(255, 255, 255, 0.08);
    color: #ffffff;
    font-size: 12.5px;
    font-weight: 600;
    cursor: pointer;
  }

  .web-tab-btn:hover {
    background: rgba(255, 255, 255, 0.16);
  }

  .web-tab-btn.active {
    background: var(--vpro-gold, #fcba19);
    border-color: var(--vpro-gold, #fcba19);
    color: #002244;
    font-weight: 700;
  }

  .web-ext-links {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 6px;
  }

  .web-ext-link {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 5px 9px;
    border-radius: 4px;
    border: 1px solid rgba(252, 186, 25, 0.45);
    color: #ffffff;
    text-decoration: none;
    font-size: 12px;
    font-weight: 600;
  }

  .web-ext-link:hover {
    background: rgba(252, 186, 25, 0.18);
  }

  .web-context-bar {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 12px;
    padding: 6px 16px;
    background: var(--vpro-navy-dark, #002244);
    border-top: 1px solid rgba(255, 255, 255, 0.12);
  }

  .web-ctx-field {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 11.5px;
    font-weight: 600;
    color: rgba(255, 255, 255, 0.88);
  }

  .web-ctx-field select {
    padding: 3px 8px;
    border-radius: 4px;
    border: 1px solid rgba(255, 255, 255, 0.25);
    background: #ffffff;
    color: var(--vpro-ink, #313132);
    font-size: 12px;
  }

  .web-error-strip {
    padding: 8px 16px;
    background: var(--vpro-error-bg, #fbeaea);
    border-bottom: 1px solid var(--vpro-error-border, #e59ba0);
    color: var(--vpro-error-ink, #a61b20);
    font-size: 12.5px;
    font-weight: 600;
  }

  .web-main {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  .web-map-workspace {
    flex: 1;
    min-height: 0;
    display: flex;
    overflow: hidden;
  }

  .web-map-right-col {
    flex: 1;
    min-width: 0;
    min-height: 0;
    padding: 12px;
    display: flex;
    flex-direction: column;
    gap: 10px;
    overflow-y: auto;
  }

  .web-deferred-pane {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
    overflow: hidden;
    background: var(--vpro-surface, #ffffff);
  }

  .web-subtab-bar {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    padding: 8px 14px;
    background: var(--vpro-surface-subtle, #f8fafb);
    border-bottom: 1px solid var(--vpro-border, #d1d5db);
    flex-shrink: 0;
  }

  .web-subtab-btn {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    padding: 5px 10px;
    border-radius: 4px;
    border: 1px solid var(--vpro-border, #d1d5db);
    background: #ffffff;
    color: var(--vpro-ink, #313132);
    font-size: 12px;
    font-weight: 600;
    cursor: pointer;
  }

  .web-subtab-btn:hover {
    border-color: var(--vpro-navy, #003366);
  }

  .web-subtab-btn.active {
    background: var(--vpro-navy, #003366);
    border-color: var(--vpro-navy, #003366);
    color: #ffffff;
  }

  .web-subtab-content {
    flex: 1;
    min-height: 0;
    overflow: auto;
  }

  .web-deferred-status {
    margin: 0;
    padding: 18px 16px;
    font-size: 13px;
    color: var(--vpro-ink-secondary, #4b5563);
  }

  .web-deferred-error {
    margin: 14px 16px;
    padding: 10px 12px;
    border-radius: 4px;
    background: var(--vpro-error-bg, #fbeaea);
    border: 1px solid var(--vpro-error-border, #e59ba0);
    color: var(--vpro-error-ink, #a61b20);
    font-size: 13px;
  }

  @media (max-width: 960px) {
    .web-explorer-root {
      height: auto;
      overflow: auto;
    }

    .web-main,
    .web-map-workspace {
      overflow: visible;
    }

    .web-map-workspace {
      flex-direction: column;
    }
  }
</style>
