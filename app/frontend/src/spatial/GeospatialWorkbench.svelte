<script module lang="ts">
  import { notifications } from '../shell/notificationService.svelte';
</script>

<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { Map as MapLibreMap, NavigationControl, ScaleControl, addProtocol, setWorkerUrl, type IControl } from 'maplibre-gl';
  import maplibreWorkerUrl from 'maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url';
  import 'maplibre-gl/dist/maplibre-gl.css';
  import { Protocol } from 'pmtiles';
  import { MapboxOverlay } from '@deck.gl/mapbox';
  import { LineLayer, ScatterplotLayer } from '@deck.gl/layers';
  import {
    ImportExportService,
    SpatialService,
    type ApplySpatialAttributesRequest,
    type AssignSpatialAOIToSURequest,
    type SpatialAOISelectionResult,
    type SpatialAttributeSuggestion,
    type SpatialBatchAuditReport,
    type SpatialWorkbenchPayload,
  } from '../../bindings/github.com/boostao/vpro/app';
  import type { GeoPackageExportOutcome } from '../../bindings/github.com/boostao/vpro/app/internal/interchange/models';
  import {
    DEFAULT_BC_VIEW_STATE, buildMapLibreGeospatialStyle, buildSpatialDeckLayers, classifyWMSMapError,
    computeViewportAOIRectangle, decodeFlatGeobufPoints, detectSpatialComputeBackend, executeSpatialFilterKernel,
    extractDistinctZones, filterWorkbenchPlots, fitMapToPayloadBounds, initQASelectedPlots,
    materializeWorkbenchPlots, pointInPolygonRing, syncMapAOIOverlay,
    type DiscrepancyVectorSegment, type MapLayerVisibility, type SpatialAOICommitInput,
    type SpatialComputeBackendInfo, type SpatialGpkgExportInput, type SpatialStampOptions, type WorkbenchPlotPoint,
  } from './geospatialWorkbench';
  import SpatialAOILassoTab from './SpatialAOILassoTab.svelte';
  import SpatialAuto1QATab from './SpatialAuto1QATab.svelte';
  import SpatialGpkgExportPanel from './SpatialGpkgExportPanel.svelte';
  import SpatialMapLegend from './SpatialMapLegend.svelte';
  import SpatialPlotInspectorTab from './SpatialPlotInspectorTab.svelte';
  import SpatialWorkbenchHeader from './SpatialWorkbenchHeader.svelte';

  let {
    contextId, project, su, onBusyChange, onContextChanged, onOpenPlot,
  }: {
    contextId: string; project: string; su: string;
    onBusyChange?: (busy: boolean) => void;
    onContextChanged?: () => Promise<void> | void;
    onOpenPlot?: (plotNumber: string) => void;
  } = $props();

  let mapContainer: HTMLDivElement | undefined = $state();
  let mapInstance: MapLibreMap | null = null;
  let deckOverlay: MapboxOverlay | null = null;
  let alive = true;
  let loadGeneration = 0, qaGeneration = 0, aoiGeneration = 0, inspectorGeneration = 0;

  let loading = $state(false);
  let mutating = $state(false);
  let errorMsg = $state('');
  let statusMsg = $state('');
  let mapRenderWarning = $state('');
  let wmsOfflineWarning = $state('');
  let computeInfo = $state<SpatialComputeBackendInfo>({
    backend: 'webgl2-cpu', available: false, adapterLabel: 'Probing GPU compute...', maxComputeWorkgroupSizeX: 0, fallbackReason: null,
  });

  let payload = $state<SpatialWorkbenchPayload | null>(null);
  let plotPoints = $state.raw<WorkbenchPlotPoint[]>([]);
  let plotCoordsF32 = $state.raw<Float32Array>(new Float32Array(0));
  let discrepancySegments = $state.raw<DiscrepancyVectorSegment[]>([]);
  let flatGeobufCount = $state(0);
  let viewportMatchedCount = $state(0);
  let visibility = $state<MapLayerVisibility>({
    bgcFill: true, bgcLabels: true, ecosections: false, nrDistricts: false, hillshade3D: false, bcOpenMapsWMS: false, discrepancyVectors: true,
  });
  let zoneFilter = $state(''), plotSearch = $state('');
  let activePanel = $state<'inspector' | 'aoi' | 'qa'>('inspector');

  let selectedPlot = $state<WorkbenchPlotPoint | null>(null);
  let selectedSuggestion = $state<SpatialAttributeSuggestion | null>(null);
  let suggestionBusy = $state(false);

  let aoiDrawMode = $state(false), aoiPreviewBusy = $state(false);
  let aoiVertices = $state<Array<[number, number]>>([]);
  let aoiPreview = $state<SpatialAOISelectionResult | null>(null);
  let aoiTargetMode = $state<'update_active' | 'create_project_su' | 'create_su_file'>('create_project_su');
  let aoiSUName = $state(''), aoiSiteUnit = $state('');

  let qaReport = $state<SpatialBatchAuditReport | null>(null);
  let qaSelectedPlots = $state<Record<string, boolean>>({});

  let gpkgPanelOpen = $state(false), gpkgExporting = $state(false);
  let gpkgDestPath = $state('');
  let gpkgOutcome = $state.raw<GeoPackageExportOutcome | null>(null);

  const aoiMatchedSet = $derived(new Set(aoiPreview?.plotNumbers ?? []));
  const filteredPoints = $derived(filterWorkbenchPlots(plotPoints, zoneFilter, plotSearch));
  const distinctZones = $derived(extractDistinctZones(plotPoints));

  const setBusyState = (nextBusy: boolean) => onBusyChange?.(nextBusy);

  let maplibreWorkerConfigured = false, pmtilesProtocolAdded = false;
  function ensurePMTilesProtocol() {
    if (!maplibreWorkerConfigured) {
      if (typeof setWorkerUrl === 'function' && maplibreWorkerUrl) setWorkerUrl(maplibreWorkerUrl);
      maplibreWorkerConfigured = true;
    }
    if (pmtilesProtocolAdded) return;
    try {
      const protocol = new Protocol();
      addProtocol('pmtiles', protocol.tile);
    } catch {
      // Ignore duplicate registration
    }
    pmtilesProtocolAdded = true;
  }

  function refreshDeckOverlay() {
    if (!deckOverlay) return;
    const layers = buildSpatialDeckLayers({
      LineLayerCtor: LineLayer, ScatterplotLayerCtor: ScatterplotLayer, pts: filteredPoints,
      matched: aoiMatchedSet, selPlotNum: selectedPlot?.plotNumber ?? '', showVectors: visibility.discrepancyVectors,
      discrepancySegments, aoiPreviewTrigger: aoiPreview,
      onPinClick: (pt) => { if (!aoiDrawMode) void inspectPlotPin(pt); },
    });
    deckOverlay.setProps({ layers });
  }

  function applyLayerVisibilities() {
    if (!visibility.bcOpenMapsWMS) wmsOfflineWarning = '';
    else if (typeof navigator !== 'undefined' && navigator.onLine === false) {
      const nextWarn = classifyWMSMapError({}, true, false) ?? 'BC OpenMaps WMS imagery is unreachable while offline. Offline map layers remain active.';
      if (nextWarn !== wmsOfflineWarning && typeof notifications !== 'undefined') {
        notifications.warning('BC OpenMaps WMS offline', nextWarn, {
          category: 'background',
          source: '3D Map',
          contextTag: project || undefined,
          toast: true,
        });
      }
      wmsOfflineWarning = nextWarn;
    } else wmsOfflineWarning = '';
    if (!mapInstance) return;
    const style = buildMapLibreGeospatialStyle(payload?.manifest, $state.snapshot(visibility));
    mapInstance.setStyle(style as any);
    mapInstance.easeTo({ pitch: visibility.hillshade3D ? 52 : 0, bearing: visibility.hillshade3D ? -14 : 0, duration: 450 });
    mapInstance.once('styledata', () => { syncMapAOIOverlay(mapInstance, aoiVertices); refreshDeckOverlay(); });
  }

  async function runViewportKernel() {
    if (plotCoordsF32.length === 0) { viewportMatchedCount = 0; return; }
    let bounds: [number, number, number, number] = [-140, 47, -113, 61];
    if (mapInstance) {
      const b = mapInstance.getBounds();
      bounds = [b.getWest(), b.getSouth(), b.getEast(), b.getNorth()];
    } else if (payload?.boundingBox) {
      bounds = [payload.boundingBox[0], payload.boundingBox[1], payload.boundingBox[2], payload.boundingBox[3]];
    }
    const res = await executeSpatialFilterKernel(plotCoordsF32, bounds, { gridSize: 16 });
    if (alive) viewportMatchedCount = res.matchedCount;
  }

  function initializeMapCanvas() {
    if (!mapContainer || mapInstance) return;
    ensurePMTilesProtocol();
    try {
      setWorkerUrl(maplibreWorkerUrl);
      const style = buildMapLibreGeospatialStyle(payload?.manifest, $state.snapshot(visibility));
      const map = new MapLibreMap({
        container: mapContainer, style: style as any,
        center: [DEFAULT_BC_VIEW_STATE.longitude, DEFAULT_BC_VIEW_STATE.latitude],
        zoom: DEFAULT_BC_VIEW_STATE.zoom, pitch: 0, bearing: 0,
      });
      map.addControl(new NavigationControl({ visualizePitch: true }), 'top-right');
      map.addControl(new ScaleControl({ maxWidth: 140, unit: 'metric' }), 'bottom-left');
      deckOverlay = new MapboxOverlay({ interleaved: false, layers: [] });
      map.addControl(deckOverlay as unknown as IControl);
      map.on('load', () => {
        if (!alive) return;
        syncMapAOIOverlay(mapInstance, aoiVertices);
        refreshDeckOverlay();
        fitMapToPayloadBounds(mapInstance, payload);
        void runViewportKernel();
      });
      map.on('moveend', () => { if (alive) void runViewportKernel(); });
      map.on('error', (evt) => {
        if (!alive) return;
        const online = typeof navigator !== 'undefined' ? navigator.onLine : undefined;
        const wmsWarn = classifyWMSMapError(evt, visibility.bcOpenMapsWMS, online);
        if (wmsWarn) {
          if (wmsWarn !== wmsOfflineWarning && typeof notifications !== 'undefined') {
            notifications.warning('BC OpenMaps WMS unavailable', wmsWarn, {
              category: 'background',
              source: '3D Map',
              contextTag: project || undefined,
              toast: true,
            });
          }
          wmsOfflineWarning = wmsWarn;
        }
      });
      map.on('click', (evt) => {
        if (!alive || !aoiDrawMode) return;
        const nextPt: [number, number] = [Math.round(evt.lngLat.lng * 1e6) / 1e6, Math.round(evt.lngLat.lat * 1e6) / 1e6];
        aoiVertices = [...aoiVertices, nextPt];
        syncMapAOIOverlay(mapInstance, aoiVertices);
        if (aoiVertices.length >= 3) void previewAOIPolygon();
      });
      mapInstance = map;
    } catch (cause) {
      mapRenderWarning = `Hardware 3D map rendering is unavailable in this environment (${cause instanceof Error ? cause.message : String(cause)}). Table-based Coordinate Check, BGC Stamp, and Site Unit selection remain active.`;
      if (typeof notifications !== 'undefined') {
        notifications.warning('3D map rendering fallback', mapRenderWarning, {
          category: 'background',
          source: '3D Map',
          contextTag: project || undefined,
          toast: true,
        });
      }
    }
  }

  async function loadWorkbenchData() {
    if (!contextId) return;
    const gen = ++loadGeneration;
    loading = true; errorMsg = ''; setBusyState(true);
    try {
      const [wb, fgbRaw] = await Promise.all([
        SpatialService.GetSpatialWorkbenchPayload(contextId),
        SpatialService.GetSpatialPlotsFlatGeobuf(contextId),
      ]);
      if (!alive || gen !== loadGeneration) return;
      payload = wb;
      const mat = materializeWorkbenchPlots(wb?.geoArrow);
      plotPoints = mat.points; plotCoordsF32 = mat.coordsFloat32; discrepancySegments = mat.discrepancyVectors;
      flatGeobufCount = decodeFlatGeobufPoints(fgbRaw).length;
      if (su && su !== 'None') aoiTargetMode = 'update_active';
      else { aoiTargetMode = 'create_project_su'; if (!aoiSUName) aoiSUName = `${project}_AOI`; }
      if (mapInstance) { applyLayerVisibilities(); fitMapToPayloadBounds(mapInstance, payload); }
      else initializeMapCanvas();
      refreshDeckOverlay();
      await runViewportKernel();
      if (plotPoints.length > 0 && !selectedPlot) void inspectPlotPin(plotPoints[0], false);
    } catch (cause) {
      if (alive && gen === loadGeneration) {
        errorMsg = `Failed to load spatial workbench: ${cause instanceof Error ? cause.message : String(cause)}`;
        if (typeof notifications !== 'undefined') {
          notifications.error('3D Map load failed', errorMsg, { category: 'entry', source: '3D Map', contextTag: project || undefined });
        }
      }
    } finally {
      if (alive && gen === loadGeneration) { loading = false; setBusyState(mutating); }
    }
  }

  async function inspectPlotPin(pt: WorkbenchPlotPoint, fly = true) {
    selectedPlot = pt; selectedSuggestion = null; activePanel = 'inspector';
    refreshDeckOverlay();
    if (fly && mapInstance) mapInstance.easeTo({ center: [pt.lon, pt.lat], zoom: Math.max(mapInstance.getZoom(), 8.5), duration: 400 });
    const gen = ++inspectorGeneration;
    suggestionBusy = true;
    try {
      const sug = await SpatialService.SuggestSpatialAttributes(pt.lat, pt.lon);
      if (alive && gen === inspectorGeneration) {
        selectedSuggestion = sug;
        if (fly && typeof notifications !== 'undefined') {
          notifications.info(
            `Inspected plot ${pt.plotNumber}`,
            sug?.gisBgc ? `Overlay BGC: ${sug.gisBgc}; field: ${pt.fieldBgc || 'blank'}.` : `Lat ${pt.lat.toFixed(5)}, Lon ${pt.lon.toFixed(5)}.`,
            { category: 'entry', source: '3D Map', contextTag: project || undefined },
          );
        }
      }
    } catch {
      if (alive && gen === inspectorGeneration) selectedSuggestion = null;
    } finally {
      if (alive && gen === inspectorGeneration) suggestionBusy = false;
    }
  }

  async function previewAOIPolygon() {
    aoiPreview = null;
    if (!contextId || aoiVertices.length < 3) { aoiPreviewBusy = false; refreshDeckOverlay(); return; }
    const gen = ++aoiGeneration;
    aoiPreviewBusy = true;
    const ringSnapshot = $state.snapshot(aoiVertices);
    const localMatches = plotPoints.filter((p) => pointInPolygonRing(p.lon, p.lat, ringSnapshot));
    try {
      const res = await SpatialService.SelectPlotsInPolygonAOI(contextId, { polygon: ringSnapshot, rings: [] as number[][][], zone: zoneFilter.trim() });
      if (!alive || gen !== aoiGeneration) return;
      aoiPreview = res;
      if (!aoiSiteUnit && localMatches[0]?.gisBgc) aoiSiteUnit = `${localMatches[0].gisBgc}/01`;
      refreshDeckOverlay();
    } catch (cause) {
      if (alive && gen === aoiGeneration) {
        errorMsg = `AOI polygon preview failed: ${cause instanceof Error ? cause.message : String(cause)}`;
        if (typeof notifications !== 'undefined') {
          notifications.error('AOI preview failed', errorMsg, { category: 'entry', source: '3D Map', contextTag: project || undefined });
        }
      }
    } finally {
      if (alive && gen === aoiGeneration) aoiPreviewBusy = false;
    }
  }

  function seedAOIFromCurrentViewport() {
    aoiVertices = computeViewportAOIRectangle(mapInstance ? mapInstance.getBounds() : null, payload?.boundingBox);
    syncMapAOIOverlay(mapInstance, aoiVertices);
    void previewAOIPolygon();
  }

  function clearAOIPolygon() {
    aoiGeneration++; aoiVertices = []; aoiPreview = null;
    syncMapAOIOverlay(mapInstance, aoiVertices);
    refreshDeckOverlay();
  }

  async function runMutation(action: () => Promise<void>, label: string, keepBusyGpkg = false) {
    mutating = true; errorMsg = ''; statusMsg = ''; setBusyState(true);
    try { await action(); }
    catch (cause) {
      if (alive) {
        errorMsg = `${label}: ${cause instanceof Error ? cause.message : String(cause)}`;
        if (typeof notifications !== 'undefined') {
          notifications.error(label, errorMsg, { category: 'entry', source: '3D Map', contextTag: project || undefined });
        }
      }
    }
    finally { if (alive) { mutating = false; setBusyState(loading || (keepBusyGpkg && gpkgExporting)); } }
  }

  async function commitAOIToSU(opts: SpatialAOICommitInput) {
    if (!contextId || mutating || loading || aoiPreviewBusy || !aoiPreview || aoiPreview.matchedCount === 0) return;
    if (!opts.siteUnit) {
      errorMsg = 'Enter a target SiteUnit code (for example SBSmk1/01) before saving the AOI selection.';
      if (typeof notifications !== 'undefined') {
        notifications.error('AOI SiteUnit required', errorMsg, { category: 'entry', source: '3D Map', contextTag: project || undefined });
      }
      return;
    }
    await runMutation(async () => {
      const req: AssignSpatialAOIToSURequest = $state.snapshot({ ...opts, plotNumbers: aoiPreview?.plotNumbers ?? [], polygon: aoiVertices, rings: [] });
      const res = await SpatialService.AssignSpatialAOIToSU(contextId, req);
      if (!alive || !res) return;
      statusMsg = `Committed ${res.matchedPlots} AOI plots to ${res.tableName} as ${res.siteUnit} (${res.changedRows} row writes).`;
      if (typeof notifications !== 'undefined') {
        notifications.success('AOI plots assigned to SU', statusMsg, { category: 'entry', source: '3D Map', contextTag: project || undefined });
      }
      if (res.activated) await onContextChanged?.(); else await loadWorkbenchData();
    }, 'AOI SU assignment failed');
  }

  async function loadBatchAuditQA(announce = true) {
    if (!contextId) return;
    const gen = ++qaGeneration;
    loading = true; errorMsg = ''; setBusyState(true);
    try {
      const report = await SpatialService.BatchAuditSpatialQA(contextId);
      if (!alive || gen !== qaGeneration) return;
      qaReport = report;
      qaSelectedPlots = initQASelectedPlots(report?.rows ?? []);
      if (announce && typeof notifications !== 'undefined') {
        notifications.info(
          'Spatial QA audit ready',
          `Audited ${report?.rows?.length ?? 0} plot(s) (${report?.bgcMismatchCount ?? 0} BGC mismatch, ${report?.utmDivergenceCount ?? 0} UTM divergence).`,
          { category: 'entry', source: '3D Map', contextTag: project || undefined },
        );
      }
    } catch (cause) {
      if (alive && gen === qaGeneration) {
        errorMsg = `Spatial QA batch audit failed: ${cause instanceof Error ? cause.message : String(cause)}`;
        if (typeof notifications !== 'undefined') {
          notifications.error('Spatial QA audit failed', errorMsg, { category: 'entry', source: '3D Map', contextTag: project || undefined });
        }
      }
    } finally {
      if (alive && gen === qaGeneration) { loading = false; setBusyState(mutating); }
    }
  }

  async function applyAuto1SpatialStamp(opts: SpatialStampOptions) {
    if (!contextId || mutating || loading) return;
    if (!opts.allScoped && opts.plotNumbers.length === 0) {
      errorMsg = 'Select at least one plot in the Spatial QA table or run across all scoped plots.';
      if (typeof notifications !== 'undefined') {
        notifications.error('Coordinate & BGC stamp blocked', errorMsg, { category: 'entry', source: '3D Map', contextTag: project || undefined });
      }
      return;
    }
    await runMutation(async () => {
      const req: ApplySpatialAttributesRequest = $state.snapshot({
        plotNumbers: opts.allScoped ? [] : opts.plotNumbers,
        allScopedPlots: opts.allScoped,
        stampGisBgc: opts.stampGisBgc,
        stampAdminFields: opts.stampAdminFields,
        onlyWhenBlank: opts.onlyWhenBlank,
        normalizeLongitudeSign: opts.normalizeLongitudeSign,
        syncUtmFromLatLon: opts.syncUtmFromLatLon,
        syncLatLonFromUtm: opts.syncLatLonFromUTM,
      });
      const res = await SpatialService.ApplySpatialAttributes(contextId, req);
      if (!alive || !res) return;
      statusMsg = `Stamped ${res.updatedPlots} plot(s) (${res.updatedCells} cell updates, ${res.auditRows} <Project>_Audit entries).`;
      if (typeof notifications !== 'undefined') {
        notifications.success('Coordinate & BGC stamp applied', statusMsg, { category: 'entry', source: '3D Map', contextTag: project || undefined });
      }
      await loadWorkbenchData();
      await loadBatchAuditQA(false);
    }, 'Coordinate & BGC stamp failed', true);
  }

  async function exportGeoPackageShortcut(opts: SpatialGpkgExportInput) {
    if (!contextId || gpkgExporting || mutating || loading) return;
    const rawDest = opts.destinationPath.trim();
    if (!rawDest) {
      errorMsg = 'Enter a destination .gpkg file path before exporting.';
      if (typeof notifications !== 'undefined') {
        notifications.error('GeoPackage destination required', errorMsg, { category: 'entry', source: '3D Map', contextTag: project || undefined });
      }
      return;
    }
    const destinationPath = rawDest.toLowerCase().endsWith('.gpkg') ? rawDest : `${rawDest}.gpkg`;
    gpkgExporting = true; errorMsg = ''; statusMsg = ''; setBusyState(true);
    try {
      const outcome = await ImportExportService.ExportGeoPackage(contextId, { ...opts, destinationPath });
      if (!alive || !outcome) return;
      gpkgOutcome = outcome;
      statusMsg = `Exported ${outcome.featureCount} GeoPackage plot features (${outcome.crs}, SRS ${outcome.srsId}) to ${outcome.path}.`;
      if (typeof notifications !== 'undefined') {
        notifications.success('GeoPackage exported', statusMsg, { category: 'entry', source: '3D Map', contextTag: project || undefined });
      }
    } catch (cause) {
      if (alive) {
        errorMsg = `GeoPackage (.gpkg) export failed: ${cause instanceof Error ? cause.message : String(cause)}`;
        if (typeof notifications !== 'undefined') {
          notifications.error('GeoPackage export failed', errorMsg, { category: 'entry', source: '3D Map', contextTag: project || undefined });
        }
      }
    } finally {
      if (alive) { gpkgExporting = false; setBusyState(loading || mutating); }
    }
  }

  $effect(() => { void zoneFilter; void plotSearch; refreshDeckOverlay(); });

  const handleBrowserOffline = () => {
    if (!alive || !visibility.bcOpenMapsWMS) return;
    const msg = classifyWMSMapError({}, true, false);
    if (msg) {
      if (msg !== wmsOfflineWarning && typeof notifications !== 'undefined') {
        notifications.warning('BC OpenMaps WMS offline', msg, {
          category: 'background',
          source: '3D Map',
          contextTag: project || undefined,
          toast: true,
        });
      }
      wmsOfflineWarning = msg;
    }
  };
  const handleBrowserOnline = () => { if (alive) wmsOfflineWarning = ''; };

  onMount(() => {
    void detectSpatialComputeBackend().then((info) => { if (alive) computeInfo = info; });
    if (typeof window !== 'undefined') {
      window.addEventListener('offline', handleBrowserOffline);
      window.addEventListener('online', handleBrowserOnline);
    }
    initializeMapCanvas();
    void loadWorkbenchData();
  });

  onDestroy(() => {
    alive = false;
    if (typeof window !== 'undefined') {
      window.removeEventListener('offline', handleBrowserOffline);
      window.removeEventListener('online', handleBrowserOnline);
    }
    loadGeneration++; qaGeneration++; aoiGeneration++; inspectorGeneration++;
    setBusyState(false);
    if (deckOverlay && mapInstance) {
      try { mapInstance.removeControl(deckOverlay as unknown as IControl); } catch { /* ignore */ }
    }
    deckOverlay = null;
    if (mapInstance) { mapInstance.remove(); mapInstance = null; }
  });
</script>

<section class="geospatial-workbench" data-tour="geospatial-workbench-root" aria-label="3D Map">
  <SpatialWorkbenchHeader
    {contextId} {project} {computeInfo} {payload} {flatGeobufCount} discrepancyCount={discrepancySegments.length}
    plotCount={plotPoints.length} {distinctZones} bind:visibility bind:zoneFilter bind:plotSearch
    {loading} {mutating} {gpkgExporting}
    onApplyLayers={applyLayerVisibilities}
    onRefreshDeck={refreshDeckOverlay}
    onFitBounds={() => fitMapToPayloadBounds(mapInstance, payload)}
    onRefreshStream={() => void loadWorkbenchData()}
    onToggleGpkgPanel={(defaultPath) => { if (!gpkgDestPath.trim()) gpkgDestPath = defaultPath; gpkgPanelOpen = !gpkgPanelOpen; }}
  />

  {#if gpkgPanelOpen}
    <SpatialGpkgExportPanel
      bind:gpkgDestPath {gpkgExporting} {gpkgOutcome} {loading} {mutating}
      onExport={exportGeoPackageShortcut} onClose={() => { gpkgPanelOpen = false; }}
    />
  {/if}

  <div class="wb-main-split">
    <div class="wb-map-stage">
      <div
        bind:this={mapContainer}
        class="wb-map-canvas"
        class:wb-crosshair={aoiDrawMode}
        data-testid="maplibre-geospatial-canvas"
      ></div>
      <SpatialMapLegend aoiMatchedCount={aoiPreview?.matchedCount ?? 0} {viewportMatchedCount} />
    </div>

    <aside class="wb-drawer" aria-label="Spatial Inspector, AOI and QA Tools">
      <div class="wb-tabs" role="tablist">
        <button
          type="button" role="tab" aria-selected={activePanel === 'inspector'} class:active={activePanel === 'inspector'}
          onclick={() => { aoiDrawMode = false; activePanel = 'inspector'; }}
        >
          Plot Inspector
        </button>
        <button
          type="button" role="tab" aria-selected={activePanel === 'aoi'} class:active={activePanel === 'aoi'}
          onclick={() => { activePanel = 'aoi'; }}
        >
          Lasso / AOI -&gt; SU
        </button>
        <button
          type="button" role="tab" aria-selected={activePanel === 'qa'} class:active={activePanel === 'qa'}
          onclick={() => { aoiDrawMode = false; activePanel = 'qa'; if (!qaReport) void loadBatchAuditQA(); }}
        >
          Coordinate &amp; BGC Stamp
        </button>
      </div>

      {#if activePanel === 'inspector'}
        <SpatialPlotInspectorTab
          {selectedPlot} {selectedSuggestion} {suggestionBusy} {filteredPoints} {onOpenPlot} onInspectPlot={inspectPlotPin}
        />
      {:else if activePanel === 'aoi'}
        <SpatialAOILassoTab
          {project} {su} bind:aoiDrawMode bind:aoiTargetMode bind:aoiSUName bind:aoiSiteUnit
          aoiVerticesCount={aoiVertices.length} {aoiPreview} {loading} {mutating}
          onSeedViewport={seedAOIFromCurrentViewport} onClear={clearAOIPolygon} onCommit={commitAOIToSU}
        />
      {:else if activePanel === 'qa'}
        <SpatialAuto1QATab
          {qaReport} bind:qaSelectedPlots {loading} {mutating}
          onReaudit={loadBatchAuditQA} onApplyStamp={applyAuto1SpatialStamp} {onOpenPlot}
        />
      {/if}
    </aside>
  </div>
</section>

<style>
  @media (max-width: 960px) {
    .geospatial-workbench :global(.wb-main-split) {
      grid-template-columns: minmax(0, 1fr);
    }
  }
  .geospatial-workbench :global(.wb-gpkg-grid) {
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 220px), 1fr));
  }
  .geospatial-workbench :global(.wb-badge-gold) {
    background: #FCBA19;
    color: #003366;
  }
</style>
