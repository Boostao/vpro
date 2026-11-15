<script lang="ts">
  import { onDestroy } from 'svelte';
  import {
    defaultRSidecarPort,
    isVegclustMethod,
    usesDissimilarity,
    usesHierarchicalLinkage,
    usesBetaParameter,
    validateClusteringDraft,
    validatePromoteCandidateDraft,
    validateQuartoGuideDraft,
    computeDendrogramSVGLayout,
    type RSidecarBackendPort,
    type RRuntimeStatus,
    type ClimateRefPeriod,
    type ClimateGroupBy,
    type ClimateEdatopicResult,
    type PlotClimateRow,
    type EdatopicGridCell,
    type ClusteringMethod,
    type EcologicalDistance,
    type HierarchicalLinkage,
    type AbundanceTransform,
    type ClusteringResult,
    type PromoteCandidateSUResult,
    type QuartoGuideType,
    type QuartoGuideResult,
  } from './rSidecarWorkbench';
  import RSidecarClusteringTab from './RSidecarClusteringTab.svelte';
  import RSidecarEdatopicTab from './RSidecarEdatopicTab.svelte';
  import RSidecarQuartoTab from './RSidecarQuartoTab.svelte';
  import RSidecarRuntimeTab from './RSidecarRuntimeTab.svelte';

  let {
    contextId,
    activeProject,
    activeSu = 'None',
    operationHeld = false,
    port = defaultRSidecarPort,
    onBusyChange,
    oncontextswitched,
  }: {
    contextId: string;
    activeProject: string;
    activeSu?: string;
    operationHeld?: boolean;
    port?: RSidecarBackendPort;
    onBusyChange?: (busy: boolean) => void;
    oncontextswitched?: (state: unknown) => void;
  } = $props();

  type SidecarTab = 'runtime' | 'edatopic' | 'clustering' | 'quarto';
  let activeTab = $state<SidecarTab>('runtime');
  let busy = $state(false);
  let error = $state<string | null>(null);
  let statusMessage = $state<string | null>(null);
  let generation = 0;
  let trackedContextId = '';

  function setBusy(next: boolean) {
    busy = next;
    onBusyChange?.(next);
  }

  let runtimeStatus = $state<RRuntimeStatus | null>(null);
  let refPeriod = $state<ClimateRefPeriod>('1961_1990');
  let climateGroupBy = $state<ClimateGroupBy>('bgc');
  let climateBgcFilter = $state('');
  let climateUseSu = $state(false);
  let climateForceRefresh = $state(false);
  let climateResult = $state<ClimateEdatopicResult | null>(null);
  let cachedRows = $state<PlotClimateRow[]>([]);

  let selectedUnitGroup = $state<string>('__overall__');
  let selectedCellDetail = $state<{ gridKind: string; cell: EdatopicGridCell } | null>(null);

  let clusterMethod = $state<ClusteringMethod>('NC');
  let clusterDistance = $state<EcologicalDistance>('bray');
  let clusterLinkage = $state<HierarchicalLinkage>('ward.D2');
  let clusterTransform = $state<AbundanceTransform>('sqrt');
  let clusterK = $state(3);
  let clusterFuzziness = $state(1.25);
  let clusterDnoise = $state(0.75);
  let clusterBeta = $state(-0.25);
  let clusterCutHeight = $state<number>(0);
  let clusterApplyLump = $state(true);
  let clusterLumpName = $state('');
  let clusterUseSu = $state(false);
  let clusterBgcFilter = $state('');
  let clusterUnitPrefix = $state('BEC');
  let clusterCandidatePrefix = $state('');
  let clusterMaterializeCandidate = $state(true);
  let clusterResult = $state<ClusteringResult | null>(null);
  let selectedDendroPlot = $state<string | null>(null);

  let promoteTargetSuName = $state('');
  let promoteExcludeNoise = $state(true);
  let promoteConfirmOverwrite = $state(false);
  let promoteActivate = $state(false);
  let promoteResult = $state<PromoteCandidateSUResult | null>(null);

  let quartoGuideType = $state<QuartoGuideType>('single_unit');
  let quartoTitle = $state('');
  let quartoTargetUnit = $state('');
  let quartoBgcFilter = $state('');
  let quartoConceptNotes = $state('');
  let quartoMinConstancy = $state(20);
  let quartoUseSu = $state(false);
  let quartoApplyLump = $state(true);
  let quartoIncludePdf = $state(false);
  let quartoDestinationPath = $state('');
  let quartoResult = $state<QuartoGuideResult | null>(null);

  $effect(() => {
    if (trackedContextId !== '' && trackedContextId !== contextId) {
      generation++;
      setBusy(false);
      selectedCellDetail = null;
    }
    trackedContextId = contextId;
  });

  onDestroy(() => {
    generation++;
    onBusyChange?.(false);
  });

  const displayedClimateRows = $derived(climateResult ? climateResult.plots : cachedRows);
  const climateEngineLabel = $derived(
    !runtimeStatus
      ? ''
      : !runtimeStatus.available
        ? 'Rscript Required (Unavailable)'
        : runtimeStatus.climrRastersCached
          ? 'Local climr Rasters'
          : 'Offline Ministry BGC Lapse Model'
  );

  const activeEdatopicView = $derived.by(() => {
    if (!climateResult) return null;
    if (selectedUnitGroup === '__overall__') {
      return {
        label: `All Scoped Plots (${climateResult.project})`,
        plotCount: climateResult.coordinatizedPlots,
        meanShift: null as number | null,
        meanCmd: null as number | null,
        relativeGrid: climateResult.overallRelative,
        actualGrid: climateResult.overallActual,
      };
    }
    const found = climateResult.unitSummaries.find(u => u.groupKey === selectedUnitGroup);
    if (!found) {
      return {
        label: `All Scoped Plots (${climateResult.project})`,
        plotCount: climateResult.coordinatizedPlots,
        meanShift: null as number | null,
        meanCmd: null as number | null,
        relativeGrid: climateResult.overallRelative,
        actualGrid: climateResult.overallActual,
      };
    }
    return {
      label: found.groupKey,
      plotCount: found.plotCount,
      meanShift: found.meanShift ?? null,
      meanCmd: found.meanCmd,
      relativeGrid: found.relativeGrid,
      actualGrid: found.actualGrid,
    };
  });

  const vegclustMode = $derived(isVegclustMethod(clusterMethod));
  const dissimilarityActive = $derived(usesDissimilarity(clusterMethod));
  const linkageActive = $derived(usesHierarchicalLinkage(clusterMethod));
  const betaActive = $derived(usesBetaParameter(clusterMethod));

  const dendrogramLayout = $derived(
    computeDendrogramSVGLayout(
      clusterResult?.dendrogram,
      clusterCutHeight > 0 ? clusterCutHeight : undefined
    )
  );

  const clusteringValidationError = $derived(
    validateClusteringDraft({
      method: clusterMethod,
      distance: clusterDistance,
      linkage: clusterLinkage,
      transform: clusterTransform,
      k: Number(clusterK),
      fuzziness: Number(clusterFuzziness),
      dnoise: Number(clusterDnoise),
      beta: betaActive ? Number(clusterBeta) : undefined,
      cutHeight: clusterCutHeight > 0 ? Number(clusterCutHeight) : undefined,
      applyLump: clusterApplyLump,
      lumpName: clusterLumpName || undefined,
      useActiveSu: clusterUseSu,
      bgcFilter: clusterBgcFilter || undefined,
      unitPrefix: clusterUnitPrefix || undefined,
      candidatePrefix: clusterCandidatePrefix || undefined,
      materializeCandidate: clusterMaterializeCandidate,
    })
  );

  const promoteValidationError = $derived(
    promoteTargetSuName === ''
      ? null
      : validatePromoteCandidateDraft(
          {
            candidateSuName: clusterResult?.candidateSuName || `${activeProject}_ClusterCandidate`,
            targetSuName: promoteTargetSuName,
            excludeNoise: promoteExcludeNoise,
            confirmOverwrite: promoteConfirmOverwrite,
            activate: promoteActivate,
          },
          activeSu
        )
  );

  const quartoValidationError = $derived(
    validateQuartoGuideDraft({
      guideType: quartoGuideType,
      title: quartoTitle || undefined,
      targetUnit: quartoTargetUnit || undefined,
      bgcFilter: quartoBgcFilter || undefined,
      conceptNotes: quartoConceptNotes || undefined,
      refPeriod,
      minConstancyPct: Number(quartoMinConstancy),
      useActiveSu: quartoUseSu,
      applyLump: quartoApplyLump,
      includePdf: quartoIncludePdf,
      destinationPath: quartoDestinationPath || undefined,
    })
  );

  async function refreshRRuntime() {
    if (operationHeld) return;
    const gen = ++generation;
    setBusy(true);
    error = null;
    statusMessage = null;
    try {
      const status = await port.detectRRuntime();
      if (gen !== generation) return;
      runtimeStatus = status;
      statusMessage = status.available
        ? `Detected R ${status.rVersion} (${status.rscriptPath})${status.quartoAvailable ? ` and Quarto ${status.quartoVersion}` : ''}.`
        : 'R runtime was not detected on this workstation. Review setup instructions below.';
    } catch (cause) {
      if (gen === generation) error = `Runtime probe failed: ${String(cause)}`;
    } finally {
      if (gen === generation) setBusy(false);
    }
  }

  async function loadCachedPlotClimate() {
    if (operationHeld) return;
    const periodSnap = $state.snapshot(refPeriod);
    const gen = ++generation;
    setBusy(true);
    error = null;
    statusMessage = null;
    try {
      const rows = await port.getCachedPlotClimate(contextId, periodSnap);
      if (gen !== generation) return;
      cachedRows = rows || [];
      statusMessage = `Loaded ${cachedRows.length} cached __VPRO_PlotClimate records (${periodSnap}).`;
    } catch (cause) {
      if (gen === generation) error = `Load cached plot climate failed: ${String(cause)}`;
    } finally {
      if (gen === generation) setBusy(false);
    }
  }

  async function runClimateAndDualEdatopic() {
    if (operationHeld) {
      error = 'Wait for the current operation or decision before computing climate normals.';
      return;
    }
    const req = $state.snapshot({
      refPeriod,
      groupBy: climateGroupBy,
      bgcFilter: climateBgcFilter.trim() || undefined,
      useActiveSu: climateUseSu,
      forceRefresh: climateForceRefresh,
    });
    const gen = ++generation;
    setBusy(true);
    error = null;
    statusMessage = null;
    try {
      const res = await port.computePlotClimateAndDualEdatopic(contextId, req);
      if (gen !== generation) return;
      climateResult = res;
      cachedRows = res.plots;
      selectedUnitGroup = '__overall__';
      selectedCellDetail = null;
      statusMessage = `Evaluated ${res.coordinatizedPlots} plots (${res.cacheHits} cache hits, ${res.cacheMisses} computed) for ${res.refPeriod}.`;
    } catch (cause) {
      if (gen === generation) error = `Climate & aSMR computation failed: ${String(cause)}`;
    } finally {
      if (gen === generation) setBusy(false);
    }
  }

  async function submitClustering() {
    if (busy || operationHeld) {
      error = 'Wait for the current operation or decision before running BEC_R clustering.';
      return;
    }
    const req = $state.snapshot({
      method: clusterMethod,
      distance: clusterDistance,
      linkage: clusterLinkage,
      transform: clusterTransform,
      k: Number(clusterK),
      fuzziness: Number(clusterFuzziness),
      dnoise: Number(clusterDnoise),
      beta: betaActive ? Number(clusterBeta) : undefined,
      cutHeight: clusterCutHeight > 0 ? Number(clusterCutHeight) : undefined,
      applyLump: clusterApplyLump,
      lumpName: clusterLumpName.trim() || undefined,
      useActiveSu: clusterUseSu,
      bgcFilter: clusterBgcFilter.trim() || undefined,
      unitPrefix: clusterUnitPrefix.trim() || undefined,
      candidatePrefix: clusterCandidatePrefix.trim() || undefined,
      materializeCandidate: clusterMaterializeCandidate,
    });
    const vErr = validateClusteringDraft(req);
    if (vErr) {
      error = vErr;
      return;
    }
    const gen = ++generation;
    setBusy(true);
    error = null;
    statusMessage = null;
    try {
      const res = await port.runMultivariateClustering(contextId, req);
      if (gen !== generation) return;
      clusterResult = res;
      promoteResult = null;
      clusterCutHeight = res.dendrogram.cutHeight;
      statusMessage = res.candidateTableName
        ? `Clustered ${res.plotCount} plots into ${res.clusters.length} groups and staged ${res.candidateTableName} (active SU preserved).`
        : `Clustered ${res.plotCount} plots into ${res.clusters.length} groups.`;
    } catch (cause) {
      if (gen === generation) error = `BEC_R clustering failed: ${String(cause)}`;
    } finally {
      if (gen === generation) setBusy(false);
    }
  }

  async function submitPromoteCandidate() {
    if (busy || operationHeld) {
      error = 'Wait for the current operation or decision before promoting candidate SU.';
      return;
    }
    const candName = clusterResult?.candidateSuName || `${activeProject}_ClusterCandidate`;
    const req = $state.snapshot({
      candidateSuName: candName,
      targetSuName: promoteTargetSuName.trim(),
      excludeNoise: promoteExcludeNoise,
      confirmOverwrite: promoteConfirmOverwrite,
      activate: promoteActivate,
    });
    const vErr = validatePromoteCandidateDraft(req, activeSu);
    if (vErr) {
      error = vErr;
      return;
    }
    const gen = ++generation;
    setBusy(true);
    error = null;
    statusMessage = null;
    try {
      const res = await port.promoteClusterCandidateToSU(contextId, req);
      if (gen !== generation) return;
      promoteResult = res;
      statusMessage = `Promoted ${res.promotedRows} plots from ${res.candidateTableName} into ${res.targetTableName}.`;
      if (res.activated && res.newState && oncontextswitched) {
        oncontextswitched(res.newState);
      }
    } catch (cause) {
      if (gen === generation) error = `Promote candidate SU failed: ${String(cause)}`;
    } finally {
      if (gen === generation) setBusy(false);
    }
  }

  async function submitRenderQuartoGuide() {
    if (busy || operationHeld) {
      error = 'Wait for the current operation or decision before rendering Quarto guide.';
      return;
    }
    const req = $state.snapshot({
      guideType: quartoGuideType,
      title: quartoTitle.trim() || undefined,
      targetUnit: quartoTargetUnit.trim() || undefined,
      bgcFilter: quartoBgcFilter.trim() || undefined,
      conceptNotes: quartoConceptNotes || undefined,
      refPeriod,
      minConstancyPct: Number(quartoMinConstancy),
      useActiveSu: quartoUseSu,
      applyLump: quartoApplyLump,
      includePdf: quartoIncludePdf,
      destinationPath: quartoDestinationPath.trim() || undefined,
    });
    const vErr = validateQuartoGuideDraft(req);
    if (vErr) {
      error = vErr;
      return;
    }
    const gen = ++generation;
    setBusy(true);
    error = null;
    statusMessage = null;
    try {
      const res = await port.renderQuartoGuide(contextId, req);
      if (gen !== generation) return;
      quartoResult = res;
      statusMessage = `Published ${res.guideType} HTML guide via ${res.rendererUsed} to ${res.htmlPath}.`;
    } catch (cause) {
      if (gen === generation) error = `Quarto guide publication failed: ${String(cause)}`;
    } finally {
      if (gen === generation) setBusy(false);
    }
  }
</script>

<section class="rsidecar-workbench" data-tour="r-sidecar-root" aria-label="BEC R Sidecar Climate Clustering and Quarto Workbench">
  <header class="bcgov-header" style="background:#003366;border-bottom:4px solid #FCBA19;color:#FFFFFF">
    <div>
      <h2>BEC_R Sidecar, Climate Normals &amp; Quarto Publication Workbench</h2>
      <p class="subtitle">
        Active Project: <strong>{activeProject}</strong> | Active SU: <strong>{activeSu}</strong> | Out-of-Process R / climr / vegclust / Quarto (Auto-7)
      </p>
    </div>
    <div class="header-actions">
      <button type="button" class="btn-gold" disabled={busy} onclick={refreshRRuntime}>
        Probe R &amp; Quarto Runtime
      </button>
    </div>
  </header>

  <div class="tab-bar" role="tablist" aria-label="R Sidecar Sections">
    <button
      type="button" role="tab" aria-selected={activeTab === 'runtime'}
      class:active={activeTab === 'runtime'} onclick={() => (activeTab = 'runtime')}
    >
      1. Runtime &amp; climr Climate Normals
    </button>
    <button
      type="button" role="tab" aria-selected={activeTab === 'edatopic'}
      class:active={activeTab === 'edatopic'} onclick={() => (activeTab = 'edatopic')}
    >
      2. Dual rSMR vs aSMR Edatopic Grids
    </button>
    <button
      type="button" role="tab" aria-selected={activeTab === 'clustering'}
      class:active={activeTab === 'clustering'} onclick={() => (activeTab = 'clustering')}
    >
      3. BEC_R Clustering &amp; Dendrogram
    </button>
    <button
      type="button" role="tab" aria-selected={activeTab === 'quarto'}
      class:active={activeTab === 'quarto'} onclick={() => (activeTab = 'quarto')}
    >
      4. Quarto Unit &amp; BGC Guide Publisher
    </button>
  </div>

  {#if error}<div class="banner-error" role="alert">{error}</div>{/if}
  {#if statusMessage}<div class="banner-status" role="status">{statusMessage}</div>{/if}

  {#if activeTab === 'runtime'}
    <RSidecarRuntimeTab
      {activeSu} {busy} {runtimeStatus} {climateEngineLabel}
      bind:refPeriod bind:climateGroupBy bind:climateBgcFilter bind:climateUseSu bind:climateForceRefresh
      {climateResult} {displayedClimateRows}
      onRunClimate={runClimateAndDualEdatopic} onLoadCached={loadCachedPlotClimate}
    />
  {:else if activeTab === 'edatopic'}
    <RSidecarEdatopicTab
      {climateResult} {activeEdatopicView} bind:selectedUnitGroup bind:selectedCellDetail
    />
  {:else if activeTab === 'clustering'}
    <RSidecarClusteringTab
      {activeProject} {activeSu} {busy}
      bind:clusterMethod bind:clusterDistance bind:clusterLinkage bind:clusterTransform
      bind:clusterK bind:clusterFuzziness bind:clusterDnoise bind:clusterBeta bind:clusterCutHeight
      bind:clusterApplyLump bind:clusterLumpName bind:clusterUseSu bind:clusterBgcFilter
      bind:clusterUnitPrefix bind:clusterCandidatePrefix bind:clusterMaterializeCandidate
      {vegclustMode} {dissimilarityActive} {linkageActive} {betaActive}
      {clusteringValidationError} {clusterResult} {dendrogramLayout} bind:selectedDendroPlot
      bind:promoteTargetSuName bind:promoteExcludeNoise bind:promoteConfirmOverwrite bind:promoteActivate
      {promoteValidationError} {promoteResult}
      onSubmitClustering={submitClustering} onSubmitPromote={submitPromoteCandidate}
    />
  {:else if activeTab === 'quarto'}
    <RSidecarQuartoTab
      {activeSu} {busy}
      bind:quartoGuideType bind:quartoTitle bind:quartoTargetUnit bind:quartoBgcFilter
      bind:quartoConceptNotes bind:quartoMinConstancy bind:quartoUseSu bind:quartoApplyLump
      bind:quartoIncludePdf bind:quartoDestinationPath
      {quartoValidationError} {quartoResult}
      onRenderQuarto={submitRenderQuartoGuide}
    />
  {/if}
</section>

<style>
  .rsidecar-workbench :global(.table-scroll) {
    overflow-x: auto;
  }
  @media (max-width: 960px) {
    .rsidecar-workbench :global(.bcgov-header) {
      flex-direction: column;
      align-items: flex-start;
    }
  }
</style>
