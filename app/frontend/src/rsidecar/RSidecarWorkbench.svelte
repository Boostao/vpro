<script lang="ts">
  import { onDestroy } from 'svelte';
  import {
    computeDendrogramSVGLayout,
    defaultRSidecarPort,
    formatError,
    isVegclustMethod,
    notifications,
    resolveActiveEdatopicView,
    usesBetaParameter,
    usesDissimilarity,
    usesHierarchicalLinkage,
    validateClusteringDraft,
    validatePromoteCandidateDraft,
    validateQuartoGuideDraft,
    type AbundanceTransform,
    type ClimateEdatopicResult,
    type ClimateGroupBy,
    type ClimateRefPeriod,
    type ClusteringMethod,
    type ClusteringResult,
    type EcologicalDistance,
    type EdatopicGridCell,
    type HierarchicalLinkage,
    type PlotClimateRow,
    type PromoteCandidateSUResult,
    type QuartoGuideResult,
    type QuartoGuideType,
    type RRuntimeStatus,
    type RSidecarBackendPort,
  } from './rSidecarWorkbench';
  import RSidecarClusteringTab from './RSidecarClusteringTab.svelte';
  import RSidecarEdatopicTab from './RSidecarEdatopicTab.svelte';
  import RSidecarQuartoTab from './RSidecarQuartoTab.svelte';
  import RSidecarRuntimeTab from './RSidecarRuntimeTab.svelte';
  import RSidecarWorkbenchHeader from './RSidecarWorkbenchHeader.svelte';

  const IS_WEB_READONLY = typeof __VPRO_WEB_READONLY__ !== 'undefined' && __VPRO_WEB_READONLY__ === true;

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
  let clusterMaterializeCandidate = $state(!IS_WEB_READONLY);
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
  const activeEdatopicView = $derived(resolveActiveEdatopicView(climateResult, selectedUnitGroup));
  const vegclustMode = $derived(isVegclustMethod(clusterMethod));
  const dissimilarityActive = $derived(usesDissimilarity(clusterMethod));
  const linkageActive = $derived(usesHierarchicalLinkage(clusterMethod));
  const betaActive = $derived(usesBetaParameter(clusterMethod));
  const dendrogramLayout = $derived(
    computeDendrogramSVGLayout(clusterResult?.dendrogram, clusterCutHeight > 0 ? clusterCutHeight : undefined)
  );

  function buildClusteringDraft(trimText: boolean) {
    const clean = (v: string) => (trimText ? v.trim() : v) || undefined;
    return {
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
      lumpName: clean(clusterLumpName),
      useActiveSu: clusterUseSu,
      bgcFilter: clean(clusterBgcFilter),
      unitPrefix: clean(clusterUnitPrefix),
      candidatePrefix: clean(clusterCandidatePrefix),
      materializeCandidate: typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY ? false : clusterMaterializeCandidate,
    };
  }

  function buildQuartoDraft(trimText: boolean) {
    const clean = (v: string) => (trimText ? v.trim() : v) || undefined;
    return {
      guideType: quartoGuideType,
      title: clean(quartoTitle),
      targetUnit: clean(quartoTargetUnit),
      bgcFilter: clean(quartoBgcFilter),
      conceptNotes: quartoConceptNotes || undefined,
      refPeriod,
      minConstancyPct: Number(quartoMinConstancy),
      useActiveSu: quartoUseSu,
      applyLump: quartoApplyLump,
      includePdf: quartoIncludePdf,
      destinationPath: typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY ? undefined : clean(quartoDestinationPath),
    };
  }

  const clusteringValidationError = $derived(validateClusteringDraft(buildClusteringDraft(false)));
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
  const quartoValidationError = $derived(validateQuartoGuideDraft(buildQuartoDraft(false)));

  function notifySidecar(
    severity: 'success' | 'info' | 'warning' | 'error',
    title: string,
    message: string,
    toast = true
  ) {
    const opts = {
      category: 'background' as const,
      source: 'R Companion',
      contextTag: activeProject || undefined,
      toast,
    };
    if (severity === 'success') notifications.success(title, message, opts);
    else if (severity === 'warning') notifications.warning(title, message, opts);
    else if (severity === 'error') notifications.error(title, message, opts);
    else notifications.info(title, message, opts);
  }

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
      notifySidecar(
        status.available ? 'success' : 'warning',
        status.available ? `R ${status.rVersion} detected` : 'R runtime not detected',
        statusMessage
      );
    } catch (cause) {
      if (gen === generation) {
        error = `Runtime probe failed: ${formatError(cause)}`;
        notifySidecar('error', 'R runtime check failed', error);
      }
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
      statusMessage = `Loaded ${cachedRows.length} cached plot climate records (${periodSnap}).`;
      notifySidecar('info', 'Loaded cached plot climate', statusMessage);
    } catch (cause) {
      if (gen === generation) {
        error = `Load cached plot climate failed: ${formatError(cause)}`;
        notifySidecar('error', 'Load cached plot climate failed', error);
      }
    } finally {
      if (gen === generation) setBusy(false);
    }
  }

  async function runClimateAndDualEdatopic() {
    if (operationHeld) {
      error = 'Wait for the current operation or decision before computing climate normals.';
      notifySidecar('error', 'Climate computation held', error);
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
      notifySidecar('success', 'Climate & aSMR computation complete', statusMessage);
    } catch (cause) {
      if (gen === generation) {
        error = `Climate & aSMR computation failed: ${formatError(cause)}`;
        notifySidecar('error', 'Climate & aSMR computation failed', error);
      }
    } finally {
      if (gen === generation) setBusy(false);
    }
  }

  async function submitClustering() {
    if (busy || operationHeld) {
      error = 'Wait for the current operation or decision before running R clustering.';
      notifySidecar('error', 'R clustering held', error);
      return;
    }
    const req = $state.snapshot(buildClusteringDraft(true));
    const vErr = validateClusteringDraft(req);
    if (vErr) {
      error = vErr;
      notifySidecar('error', 'Clustering configuration invalid', vErr);
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
      notifySidecar('success', `Clustered ${res.plotCount} plots`, statusMessage);
    } catch (cause) {
      if (gen === generation) {
        error = `R clustering failed: ${formatError(cause)}`;
        notifySidecar('error', 'R clustering failed', error);
      }
    } finally {
      if (gen === generation) setBusy(false);
    }
  }

  async function submitPromoteCandidate() {
    if (typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY) {
      error = 'Promoting cluster candidates to a Site Unit table is unavailable in web read-only mode.';
      return;
    }
    if (busy || operationHeld) {
      error = 'Wait for the current operation or decision before promoting candidate SU.';
      notifySidecar('error', 'Candidate SU promotion held', error);
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
      notifySidecar('error', 'Candidate SU promotion blocked', vErr);
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
      notifySidecar('success', `Promoted candidate to ${res.targetTableName}`, statusMessage);
      if (res.activated && res.newState && oncontextswitched) oncontextswitched(res.newState);
    } catch (cause) {
      if (gen === generation) {
        error = `Promote candidate SU failed: ${formatError(cause)}`;
        notifySidecar('error', 'Promote candidate SU failed', error);
      }
    } finally {
      if (gen === generation) setBusy(false);
    }
  }

  async function submitRenderQuartoGuide() {
    if (busy || operationHeld) {
      error = 'Wait for the current operation or decision before rendering Quarto guide.';
      notifySidecar('error', 'Quarto guide render held', error);
      return;
    }
    const req = $state.snapshot(buildQuartoDraft(true));
    const vErr = validateQuartoGuideDraft(req);
    if (vErr) {
      error = vErr;
      notifySidecar('error', 'Quarto guide configuration invalid', vErr);
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
      statusMessage =
        typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY
          ? `Prepared ${res.guideType} HTML guide via ${res.rendererUsed} for download.`
          : `Published ${res.guideType} HTML guide via ${res.rendererUsed} to ${res.htmlPath}.`;
      notifySidecar('success', 'Quarto guide published', statusMessage);
    } catch (cause) {
      if (gen === generation) {
        const rawErr = formatError(cause);
        const baseMsg = `Quarto guide publication failed: ${rawErr}`;
        error =
          typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY && /429|503|busy|semaphore|queue/i.test(rawErr)
            ? 'Another download is currently being prepared on the server. Please wait a few seconds and try again.'
            : baseMsg;
        notifySidecar('error', 'Quarto guide publication failed', error);
      }
    } finally {
      if (gen === generation) setBusy(false);
    }
  }
</script>

<section class="rsidecar-workbench" data-tour="r-sidecar-root" aria-label="R Companion Climate Clustering and Guides">
  <RSidecarWorkbenchHeader
    {activeProject}
    {activeSu}
    {busy}
    bind:activeTab
    {error}
    onRefreshRuntime={() => void refreshRRuntime()}
  />

  {#if activeTab === 'runtime'}
    <RSidecarRuntimeTab
      {activeSu}
      {busy}
      {runtimeStatus}
      {climateEngineLabel}
      bind:refPeriod
      bind:climateGroupBy
      bind:climateBgcFilter
      bind:climateUseSu
      bind:climateForceRefresh
      {climateResult}
      {displayedClimateRows}
      onRunClimate={runClimateAndDualEdatopic}
      onLoadCached={loadCachedPlotClimate}
    />
  {:else if activeTab === 'edatopic'}
    <RSidecarEdatopicTab {climateResult} {activeEdatopicView} bind:selectedUnitGroup bind:selectedCellDetail />
  {:else if activeTab === 'clustering'}
    <RSidecarClusteringTab
      {activeProject}
      {activeSu}
      {busy}
      bind:clusterMethod
      bind:clusterDistance
      bind:clusterLinkage
      bind:clusterTransform
      bind:clusterK
      bind:clusterFuzziness
      bind:clusterDnoise
      bind:clusterBeta
      bind:clusterCutHeight
      bind:clusterApplyLump
      bind:clusterLumpName
      bind:clusterUseSu
      bind:clusterBgcFilter
      bind:clusterUnitPrefix
      bind:clusterCandidatePrefix
      bind:clusterMaterializeCandidate
      {vegclustMode}
      {dissimilarityActive}
      {linkageActive}
      {betaActive}
      {clusteringValidationError}
      {clusterResult}
      {dendrogramLayout}
      bind:selectedDendroPlot
      bind:promoteTargetSuName
      bind:promoteExcludeNoise
      bind:promoteConfirmOverwrite
      bind:promoteActivate
      {promoteValidationError}
      {promoteResult}
      onSubmitClustering={submitClustering}
      onSubmitPromote={submitPromoteCandidate}
    />
  {:else if activeTab === 'quarto'}
    <RSidecarQuartoTab
      {activeSu}
      {busy}
      bind:quartoGuideType
      bind:quartoTitle
      bind:quartoTargetUnit
      bind:quartoBgcFilter
      bind:quartoConceptNotes
      bind:quartoMinConstancy
      bind:quartoUseSu
      bind:quartoApplyLump
      bind:quartoIncludePdf
      bind:quartoDestinationPath
      {quartoValidationError}
      {quartoResult}
      onRenderQuarto={submitRenderQuartoGuide}
    />
  {/if}
</section>

<style>
  .rsidecar-workbench {
    overflow: clip;
  }
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
