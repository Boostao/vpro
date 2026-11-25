<script module lang="ts">
  import { formatError } from '../shared/readRequests';
  import { notifications } from '../shell/notificationService.svelte';
  import { defaultWebExportFilename } from '../shell/webReadOnlyShell';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import { formatWebDownloadFeedback, getCachedWebMeta, resolveWebPMTilesBaseUrl } from '../web/webMeta';
</script>

<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { Map as MapLibreMap, NavigationControl, ScaleControl, addProtocol, setWorkerUrl } from 'maplibre-gl';
  import maplibreWorkerUrl from 'maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url';
  import 'maplibre-gl/dist/maplibre-gl.css';
  import { Protocol } from 'pmtiles';
  import { MapboxOverlay } from '@deck.gl/mapbox';
  import { LineLayer, ScatterplotLayer } from '@deck.gl/layers';
  import { ImportExportService, SpatialService } from '../../bindings/github.com/boostao/vpro/app';
  import type { GeoPackageExportOutcome } from '../../bindings/github.com/boostao/vpro/app/internal/interchange/models';
  import * as geoOps from './geospatialWorkbench';
  import {
    buildDefaultGeoPackageExportPath,
    buildMapLibreGeospatialStyle,
    classifyWMSMapError,
    fitMapToPayloadBounds,
    initQASelectedPlots,
    isAbsoluteFilesystemPath,
    materializeWorkbenchPlots,
    resolveGeoPackageDestinationPath,
    summarizePMTilesManifestWarnings,
  } from './geospatialWorkbench';
  import GeospatialMapStage from './GeospatialMapStage.svelte';
  import GeospatialSidebarDrawer from './GeospatialSidebarDrawer.svelte';

  let {
    contextId,
    project,
    su,
    onBusyChange,
    onContextChanged,
    onOpenPlot,
  }: {
    contextId: string;
    project: string;
    su: string;
    onBusyChange?: (busy: boolean) => void;
    onContextChanged?: () => Promise<void> | void;
    onOpenPlot?: (plotNumber: string) => void;
  } = $props();

  let mapContainer: HTMLDivElement | undefined = $state();
  let [mapInstance, deckOverlay]: [MapLibreMap | null, MapboxOverlay | null] = [null, null];
  let alive = true;
  let [loadGeneration, qaGeneration, inspectorGeneration] = [0, 0, 0];
  let removeWindowListeners: (() => void) | null = null;

  let loading = $state(false);
  let mutating = $state(false);
  let errorMsg = $state('');
  let statusMsg = $state('');
  let mapRenderWarning = $state('');
  let wmsOfflineWarning = $state('');
  let basemapOfflineWarning = $state('');
  let pmtilesArchiveWarning = $state('');
  let pmtilesGraticuleFallback = $state(false);
  let computeInfo = $state<geoOps.SpatialComputeBackendInfo>({ ...geoOps.INITIAL_COMPUTE_INFO });

  let payload = $state<Parameters<typeof fitMapToPayloadBounds>[1]>(null);
  let plotPoints = $state.raw<geoOps.WorkbenchPlotPoint[]>([]);
  let plotCoordsF32 = $state.raw<Float32Array>(new Float32Array(0));
  let discrepancySegments = $state.raw<geoOps.DiscrepancyVectorSegment[]>([]);
  let flatGeobufCount = $state(0);
  let viewportMatchedCount = $state(0);
  let visibility = $state<geoOps.MapLayerVisibility>({ ...geoOps.INITIAL_LAYER_VISIBILITY });
  let basemap = $state<geoOps.MapBasemapId>(geoOps.DEFAULT_MAP_BASEMAP);
  let wmsLayer = $state<geoOps.BCOpenMapsWMSLayerId>(geoOps.DEFAULT_BC_WMS_LAYER);
  let layerOpacity = $state<geoOps.MapLayerOpacity>({ ...geoOps.INITIAL_LAYER_OPACITY });
  let zoneFilter = $state('');
  let plotSearch = $state('');
  let activePanel = $state<'inspector' | 'aoi' | 'qa'>('inspector');

  let selectedPlot = $state<geoOps.WorkbenchPlotPoint | null>(null);
  let selectedSuggestion = $state<Awaited<ReturnType<typeof SpatialService.SuggestSpatialAttributes>> | null>(null);
  let suggestionBusy = $state(false);

  let aoiDrawMode = $state(false);
  let aoiVertices = $state<Array<[number, number]>>([]);
  let aoiPreview = $state<Awaited<ReturnType<typeof SpatialService.SelectPlotsInPolygonAOI>> | null>(null);
  let aoiFilterActive = $state(false);
  let aoiTargetMode = $state<'update_active' | 'create_project_su' | 'create_su_file'>('create_project_su');
  let aoiSUName = $state('');
  let aoiSiteUnit = $state('');

  let qaReport = $state<Awaited<ReturnType<typeof SpatialService.BatchAuditSpatialQA>> | null>(null);
  let qaSelectedPlots = $state<Record<string, boolean>>({});

  let gpkgPanelOpen = $state(false);
  let gpkgExporting = $state(false);
  let gpkgDestPath = $state('');
  let gpkgOutcome = $state.raw<GeoPackageExportOutcome | null>(null);

  const aoiMatchedSet = $derived(new Set(aoiPreview?.plotNumbers ?? []));
  const filteredPoints = $derived.by(() => {
    const base = geoOps.filterWorkbenchPlots(plotPoints, zoneFilter, plotSearch);
    if (IS_WEB_READONLY && aoiFilterActive && aoiMatchedSet.size > 0) {
      return base.filter((pt) => aoiMatchedSet.has(pt.plotNumber));
    }
    return base;
  });
  const distinctZones = $derived(geoOps.extractDistinctZones(plotPoints));
  const qaCoordinateDiagnosticRows = $derived(geoOps.filterCoordinateDiagnosticRows(qaReport?.rows));
  const setBusyState = (nextBusy: boolean) => onBusyChange?.(nextBusy);

  function pushGeoError(title: string, msg: string) {
    errorMsg = msg;
    notifications.error(title, msg, { category: 'entry', source: '3D Map', contextTag: project || undefined });
  }

  function ensurePMTilesProtocol() {
    geoOps.ensureMapLibrePMTilesProtocol(setWorkerUrl, maplibreWorkerUrl, addProtocol, Protocol);
  }

  function refreshDeckOverlay() {
    if (!deckOverlay) return;
    const onPin = (pt: geoOps.WorkbenchPlotPoint) => {
      if (!aoiDrawMode) void inspectPlotPin(pt);
    };
    const selNum = selectedPlot?.plotNumber ?? '';
    const layers = geoOps.makeWorkbenchDeckLayers(
      LineLayer,
      ScatterplotLayer,
      filteredPoints,
      aoiMatchedSet,
      selNum,
      visibility.discrepancyVectors,
      discrepancySegments,
      aoiPreview,
      onPin
    );
    deckOverlay.setProps({ layers });
  }

  function syncAOIOverlay() {
    geoOps.syncMapAOIOverlay(mapInstance, aoiVertices);
    refreshDeckOverlay();
  }

  function applyLayerOpacity() {
    if (!mapInstance) return;
    geoOps.applyMapLayerOpacity(mapInstance, $state.snapshot(layerOpacity));
  }

  function applyLayerVisibilities() {
    const bgOpt = { category: 'background' as const, source: '3D Map', contextTag: project || undefined, toast: true };
    const isOffline = typeof navigator !== 'undefined' && navigator.onLine === false;
    const curBasemap = typeof basemap !== 'undefined' ? basemap : 'offline-neutral';
    const curWmsLayer = typeof wmsLayer !== 'undefined' ? wmsLayer : 'bc-parks';
    const curOpacity = typeof layerOpacity !== 'undefined' ? $state.snapshot(layerOpacity) : undefined;
    if (!visibility.bcOpenMapsWMS) wmsOfflineWarning = '';
    else if (isOffline) {
      const nextWarn =
        classifyWMSMapError({}, true, false) ??
        'BC OpenMaps WMS imagery is unreachable while offline. Offline map layers remain active.';
      if (nextWarn !== wmsOfflineWarning) notifications.warning('BC OpenMaps WMS offline', nextWarn, bgOpt);
      wmsOfflineWarning = nextWarn;
    } else wmsOfflineWarning = '';
    if (typeof geoOps !== 'undefined' && typeof basemapOfflineWarning !== 'undefined') {
      const baseOpt = geoOps.getMapBasemapOption(curBasemap);
      if (!baseOpt.online) basemapOfflineWarning = '';
      else if (isOffline) {
        const nextBaseWarn = geoOps.classifyBasemapError({}, curBasemap, false) ?? '';
        if (nextBaseWarn && nextBaseWarn !== basemapOfflineWarning) {
          notifications.warning('Online basemap offline', nextBaseWarn, bgOpt);
        }
        basemapOfflineWarning = nextBaseWarn;
      } else basemapOfflineWarning = '';
    }
    if (!mapInstance) return;
    const snap = $state.snapshot(visibility);
    const force = typeof pmtilesGraticuleFallback !== 'undefined' && pmtilesGraticuleFallback;
    const webPmtilesBase =
      typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY && typeof resolveWebPMTilesBaseUrl === 'function'
        ? resolveWebPMTilesBaseUrl(typeof getCachedWebMeta === 'function' ? getCachedWebMeta() : null)
        : undefined;
    mapInstance.setStyle(
      buildMapLibreGeospatialStyle(payload?.manifest, snap, {
        ...(force ? { forceGraticuleFallback: true } : {}),
        basemap: curBasemap,
        wmsLayer: curWmsLayer,
        opacity: curOpacity,
        ...(webPmtilesBase ? { pmtilesBaseUrl: webPmtilesBase } : {}),
      })
    );
    mapInstance.easeTo({
      pitch: visibility.hillshade3D ? 52 : 0,
      bearing: visibility.hillshade3D ? -14 : 0,
      duration: 450,
    });
    mapInstance.once('styledata', syncAOIOverlay);
  }

  async function runViewportKernel() {
    if (plotCoordsF32.length === 0) {
      viewportMatchedCount = 0;
      return;
    }
    const bounds = geoOps.computeViewportFilterBounds(mapInstance, payload?.boundingBox);
    const res = await geoOps.executeSpatialFilterKernel(plotCoordsF32, bounds, { gridSize: 16 });
    if (alive) viewportMatchedCount = res.matchedCount;
  }

  function onMapError(m: { setStyle(s: ReturnType<typeof buildMapLibreGeospatialStyle>): unknown }, evt: unknown) {
    const bgOpt = { category: 'background' as const, source: '3D Map', contextTag: project || undefined, toast: true };
    const st: [
      boolean,
      string,
      string,
      boolean,
      geoOps.MapBasemapId,
      geoOps.BCOpenMapsWMSLayerId,
      geoOps.MapLayerOpacity,
      string,
    ] = [
      visibility.bcOpenMapsWMS,
      wmsOfflineWarning,
      pmtilesArchiveWarning,
      pmtilesGraticuleFallback,
      basemap,
      wmsLayer,
      $state.snapshot(layerOpacity),
      basemapOfflineWarning,
    ];
    geoOps.routeGeospatialMapError(
      evt,
      st,
      payload?.manifest,
      $state.snapshot(visibility),
      (w, pm, s, bw) => {
        if (w !== null) wmsOfflineWarning = w;
        if (bw !== undefined && bw !== null) basemapOfflineWarning = bw;
        if (pm !== null) pmtilesArchiveWarning = pm;
        if (s !== null) {
          pmtilesGraticuleFallback = true;
          m.setStyle(s);
        }
      },
      (t, msg) => notifications.warning(t, msg, bgOpt)
    );
  }

  function onMapClick(pt: [number, number]) {
    if (!aoiDrawMode) return;
    aoiVertices = [...aoiVertices, pt];
    syncAOIOverlay();
  }

  function initializeMapCanvas() {
    if (!mapContainer || mapInstance) return;
    ensurePMTilesProtocol();
    const bgOpt = { category: 'background' as const, source: '3D Map', contextTag: project || undefined, toast: true };
    try {
      setWorkerUrl(maplibreWorkerUrl);
      const curBasemap = typeof basemap !== 'undefined' ? basemap : 'offline-neutral';
      const curWmsLayer = typeof wmsLayer !== 'undefined' ? wmsLayer : 'bc-parks';
      const curOpacity = typeof layerOpacity !== 'undefined' ? $state.snapshot(layerOpacity) : undefined;
      const webPmtilesBase =
        typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY && typeof resolveWebPMTilesBaseUrl === 'function'
          ? resolveWebPMTilesBaseUrl(typeof getCachedWebMeta === 'function' ? getCachedWebMeta() : null)
          : undefined;
      const style = buildMapLibreGeospatialStyle(payload?.manifest, $state.snapshot(visibility), {
        basemap: curBasemap,
        wmsLayer: curWmsLayer,
        opacity: curOpacity,
        ...(webPmtilesBase ? { pmtilesBaseUrl: webPmtilesBase } : {}),
      });
      const onLoad = () => {
        syncAOIOverlay();
        fitMapToPayloadBounds(mapInstance, payload);
        void runViewportKernel();
      };
      const hooks = {
        isAlive: () => alive,
        onLoad,
        onMoveEnd: () => void runViewportKernel(),
        onError: onMapError,
        onClick: onMapClick,
      };
      const created = geoOps.createGeospatialMapInstance<MapLibreMap, MapboxOverlay>(
        [MapLibreMap as never, NavigationControl, ScaleControl, MapboxOverlay],
        [mapContainer, style],
        hooks
      );
      [mapInstance, deckOverlay] = [created.map, created.overlay];
    } catch (cause) {
      mapRenderWarning = `Hardware 3D map rendering is unavailable in this environment (${formatError(cause)}). Table-based Coordinate Check, BGC Stamp, and Site Unit selection remain active.`;
      notifications.warning('3D map rendering fallback', mapRenderWarning, bgOpt);
    }
  }

  async function loadWorkbenchData() {
    if (!contextId) return;
    const gen = ++loadGeneration;
    const bgOpt = { category: 'background' as const, source: '3D Map', contextTag: project || undefined, toast: true };
    [loading, errorMsg] = [true, ''];
    setBusyState(true);
    try {
      const wb = await SpatialService.GetSpatialWorkbenchPayload(contextId);
      if (!alive || gen !== loadGeneration) return;
      [payload, pmtilesGraticuleFallback] = [wb, false];
      const manifestWarn = summarizePMTilesManifestWarnings(wb?.manifest) ?? '';
      if (manifestWarn && manifestWarn !== pmtilesArchiveWarning)
        notifications.warning('Local map archive unreadable', manifestWarn, bgOpt);
      pmtilesArchiveWarning = manifestWarn;
      if (wb?.projectPath && (!gpkgDestPath.trim() || !isAbsoluteFilesystemPath(gpkgDestPath))) {
        gpkgDestPath = buildDefaultGeoPackageExportPath(wb.project || project, wb.projectPath);
      }
      const mat = materializeWorkbenchPlots(wb?.geoArrow);
      [plotPoints, plotCoordsF32, discrepancySegments, flatGeobufCount] = [
        mat.points,
        mat.coordsFloat32,
        mat.discrepancyVectors,
        wb?.plottableCount ?? mat.points.length,
      ];
      if (su && su !== 'None') aoiTargetMode = 'update_active';
      else {
        aoiTargetMode = 'create_project_su';
        if (!aoiSUName) aoiSUName = `${project}_AOI`;
      }
      if (mapInstance) {
        applyLayerVisibilities();
        fitMapToPayloadBounds(mapInstance, payload);
      } else initializeMapCanvas();
      refreshDeckOverlay();
      await runViewportKernel();
      if (plotPoints.length > 0 && !selectedPlot) void inspectPlotPin(plotPoints[0], false);
    } catch (cause) {
      if (alive && gen === loadGeneration) {
        errorMsg = `Failed to load spatial workbench: ${formatError(cause)}`;
        notifications.error('3D Map load failed', errorMsg, {
          category: 'entry',
          source: '3D Map',
          contextTag: project || undefined,
        });
      }
    } finally {
      if (alive && gen === loadGeneration) {
        loading = false;
        setBusyState(mutating);
      }
    }
  }

  async function inspectPlotPin(pt: geoOps.WorkbenchPlotPoint, fly = true) {
    [selectedPlot, selectedSuggestion, activePanel] = [pt, null, 'inspector'];
    refreshDeckOverlay();
    if (fly && mapInstance)
      mapInstance.easeTo({ center: [pt.lon, pt.lat], zoom: Math.max(mapInstance.getZoom(), 8.5), duration: 400 });
    const gen = ++inspectorGeneration;
    suggestionBusy = true;
    try {
      const sug = await SpatialService.SuggestSpatialAttributes(pt.lat, pt.lon);
      if (alive && gen === inspectorGeneration) {
        selectedSuggestion = sug;
        if (fly) {
          const desc = sug?.gisBgc
            ? `Overlay BGC: ${sug.gisBgc}; field: ${pt.fieldBgc || 'blank'}.`
            : `Lat ${pt.lat.toFixed(5)}, Lon ${pt.lon.toFixed(5)}.`;
          notifications.info(`Inspected plot ${pt.plotNumber}`, desc, {
            category: 'entry',
            source: '3D Map',
            contextTag: project || undefined,
          });
        }
      }
    } catch {
      if (alive && gen === inspectorGeneration) selectedSuggestion = null;
    } finally {
      if (alive && gen === inspectorGeneration) suggestionBusy = false;
    }
  }

  async function runMutation(action: () => Promise<void>, label: string, keepBusyGpkg = false) {
    [mutating, errorMsg, statusMsg] = [true, '', ''];
    setBusyState(true);
    try {
      await action();
    } catch (cause) {
      if (alive) {
        errorMsg = `${label}: ${formatError(cause)}`;
        notifications.error(label, errorMsg, { category: 'entry', source: '3D Map', contextTag: project || undefined });
      }
    } finally {
      if (alive) {
        mutating = false;
        setBusyState(loading || (keepBusyGpkg && gpkgExporting));
      }
    }
  }

  async function loadBatchAuditQA(announce = true) {
    if (!contextId) return;
    const gen = ++qaGeneration;
    const meta = { category: 'entry' as const, source: '3D Map', contextTag: project || undefined };
    [loading, errorMsg] = [true, ''];
    setBusyState(true);
    try {
      const report = await SpatialService.BatchAuditSpatialQA(contextId);
      if (!alive || gen !== qaGeneration) return;
      [qaReport, qaSelectedPlots] = [report, initQASelectedPlots(report?.rows ?? [])];
      if (announce) {
        notifications.info(
          'Spatial QA audit ready',
          `Audited ${report?.rows?.length ?? 0} plot(s) (${report?.bgcMismatchCount ?? 0} BGC mismatch, ${report?.utmDivergenceCount ?? 0} UTM divergence).`,
          meta
        );
      }
    } catch (cause) {
      if (alive && gen === qaGeneration) {
        errorMsg = `Spatial QA batch audit failed: ${formatError(cause)}`;
        notifications.error('Spatial QA audit failed', errorMsg, meta);
      }
    } finally {
      if (alive && gen === qaGeneration) {
        loading = false;
        setBusyState(mutating);
      }
    }
  }

  async function applyAuto1SpatialStamp(opts: geoOps.SpatialStampOptions) {
    if (typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY) return;
    if (!contextId || mutating || loading) return;
    const meta = { category: 'entry' as const, source: '3D Map', contextTag: project || undefined };
    if (!opts.allScoped && opts.plotNumbers.length === 0) {
      errorMsg = 'Select at least one plot in the Spatial QA table or run across all scoped plots.';
      notifications.error('Coordinate & BGC stamp blocked', errorMsg, meta);
      return;
    }
    const p1 = {
      plotNumbers: opts.allScoped ? [] : opts.plotNumbers,
      allScopedPlots: opts.allScoped,
      onlyWhenBlank: opts.onlyWhenBlank,
    };
    const p2 = {
      stampGisBgc: opts.stampGisBgc,
      stampAdminFields: opts.stampAdminFields,
      normalizeLongitudeSign: opts.normalizeLongitudeSign,
    };
    const req = $state.snapshot({
      ...p1,
      ...p2,
      syncUtmFromLatLon: opts.syncUtmFromLatLon,
      syncLatLonFromUtm: opts.syncLatLonFromUTM,
    });
    await runMutation(
      async () => {
        const res = await SpatialService.ApplySpatialAttributes(contextId, req);
        if (!alive || !res) return;
        statusMsg = `Stamped ${res.updatedPlots} plot(s) (${res.updatedCells} cell updates, ${res.auditRows} <Project>_Audit entries).`;
        notifications.success('Coordinate & BGC stamp applied', statusMsg, meta);
        await loadWorkbenchData();
        await loadBatchAuditQA(false);
      },
      'Coordinate & BGC stamp failed',
      true
    );
  }

  async function exportGeoPackageShortcut(opts: geoOps.SpatialGpkgExportInput) {
    if (!contextId || gpkgExporting || mutating || loading) return;
    const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
    const meta = { category: 'entry' as const, source: '3D Map', contextTag: project || undefined };
    let resolvedDest: string | null = null;
    if (webReadOnly) {
      resolvedDest =
        typeof defaultWebExportFilename === 'function'
          ? defaultWebExportFilename(`${project || 'vpro'}_plots`, '.gpkg')
          : `${project || 'vpro'}_plots.gpkg`;
    } else {
      const rawDest = opts.destinationPath.trim();
      if (!rawDest) {
        errorMsg = 'Enter a destination .gpkg file path before exporting.';
        notifications.error('GeoPackage destination required', errorMsg, meta);
        return;
      }
      const isAbs = rawDest.startsWith('/') || /^[A-Za-z]:[\\/]/.test(rawDest) || rawDest.startsWith('\\\\');
      const fallbackDest = isAbs ? (rawDest.toLowerCase().endsWith('.gpkg') ? rawDest : `${rawDest}.gpkg`) : null;
      resolvedDest =
        typeof resolveGeoPackageDestinationPath === 'function'
          ? resolveGeoPackageDestinationPath(rawDest, project, payload?.projectPath)
          : fallbackDest;
      if (!resolvedDest) {
        errorMsg =
          'Enter an absolute destination folder path (not a bare relative filename) before exporting GeoPackage.';
        notifications.error('GeoPackage destination required', errorMsg, meta);
        return;
      }
    }
    [gpkgExporting, errorMsg, statusMsg] = [true, '', ''];
    setBusyState(true);
    try {
      const outcome = await ImportExportService.ExportGeoPackage(contextId, { ...opts, destinationPath: resolvedDest });
      if (!alive || !outcome) return;
      gpkgOutcome = outcome;
      statusMsg = webReadOnly
        ? `Downloaded ${outcome.featureCount} GeoPackage plot features (${outcome.crs}, SRS ${outcome.srsId}).`
        : `Exported ${outcome.featureCount} GeoPackage plot features (${outcome.crs}, SRS ${outcome.srsId}) to ${outcome.path}.`;
      notifications.success(webReadOnly ? 'GeoPackage downloaded' : 'GeoPackage exported', statusMsg, meta);
    } catch (cause) {
      if (alive) {
        errorMsg =
          webReadOnly && typeof formatWebDownloadFeedback === 'function'
            ? formatWebDownloadFeedback(cause, 'GeoPackage (.gpkg) download')
            : `GeoPackage (.gpkg) export failed: ${formatError(cause)}`;
        notifications.error('GeoPackage export failed', errorMsg, meta);
      }
    } finally {
      if (alive) {
        gpkgExporting = false;
        setBusyState(loading || mutating);
      }
    }
  }

  $effect(() => {
    void zoneFilter;
    void plotSearch;
    void aoiFilterActive;
    refreshDeckOverlay();
  });

  const handleBrowserOffline = () => {
    if (!alive) return;
    const bgOpt = { category: 'background' as const, source: '3D Map', contextTag: project || undefined, toast: true };
    if (visibility.bcOpenMapsWMS) {
      const msg = classifyWMSMapError({}, true, false);
      if (msg) {
        if (msg !== wmsOfflineWarning) notifications.warning('BC OpenMaps WMS offline', msg, bgOpt);
        wmsOfflineWarning = msg;
      }
    }
    const baseMsg = geoOps.classifyBasemapError({}, basemap, false);
    if (baseMsg) {
      if (baseMsg !== basemapOfflineWarning) notifications.warning('Online basemap offline', baseMsg, bgOpt);
      basemapOfflineWarning = baseMsg;
    }
  };
  const handleBrowserOnline = () => {
    if (alive) {
      wmsOfflineWarning = '';
      basemapOfflineWarning = '';
    }
  };

  onMount(() => {
    void geoOps.detectSpatialComputeBackend().then((info) => {
      if (alive) computeInfo = info;
    });
    removeWindowListeners = geoOps.bindWindowConnectivityListeners(handleBrowserOffline, handleBrowserOnline);
    initializeMapCanvas();
    void loadWorkbenchData();
  });

  onDestroy(() => {
    alive = false;
    removeWindowListeners?.();
    [loadGeneration, qaGeneration, inspectorGeneration] = [
      loadGeneration + 1,
      qaGeneration + 1,
      inspectorGeneration + 1,
    ];
    setBusyState(false);
    geoOps.disposeGeospatialMap(mapInstance, deckOverlay);
    [deckOverlay, mapInstance] = [null, null];
  });

  async function handleCommittedAOI(msg: string, activated: boolean) {
    statusMsg = msg;
    if (activated) await onContextChanged?.();
    else await loadWorkbenchData();
  }

  const fitBounds = () => fitMapToPayloadBounds(mapInstance, payload);
  const refreshStream = () => void loadWorkbenchData();
  const getBounds = () => (mapInstance ? mapInstance.getBounds() : null);
  const stgA = $derived({ contextId, project, computeInfo, payload, flatGeobufCount, plotCount: plotPoints.length });
  const stgB = $derived({ distinctZones, discrepancyCount: discrepancySegments.length, pmtilesArchiveWarning });
  const stgC = $derived({ gpkgExporting, gpkgOutcome, loading, mutating, aoiDrawMode, viewportMatchedCount });
  const stgD = $derived({
    aoiMatchedCount: aoiPreview?.matchedCount ?? 0,
    onFitBounds: fitBounds,
    onRefreshStream: refreshStream,
  });
  const stgE = {
    onApplyLayers: applyLayerVisibilities,
    onApplyOpacity: applyLayerOpacity,
    onRefreshDeck: refreshDeckOverlay,
  };
  const stgAll = $derived({ ...stgA, ...stgB, ...stgC, ...stgD, ...stgE, onExportGpkg: exportGeoPackageShortcut });
  const drwA = $derived({ contextId, project, su, zoneFilter, boundingBox: payload?.boundingBox, plotPoints });
  const drwB = $derived({ selectedPlot, selectedSuggestion, suggestionBusy, filteredPoints, qaReport });
  const drwC = $derived({ qaCoordinateDiagnosticRows, loading, mutating, onOpenPlot, onInspectPlot: inspectPlotPin });
  const drwD = { getViewportBounds: getBounds, onSyncAOIOverlay: syncAOIOverlay, onRunMutation: runMutation };
  const drwE = { onPushError: pushGeoError, onCommittedAOI: handleCommittedAOI, onLoadBatchAuditQA: loadBatchAuditQA };
  const drwAll = $derived({
    ...drwA,
    ...drwB,
    ...drwC,
    ...drwD,
    ...drwE,
    onApplyStamp: applyAuto1SpatialStamp,
    aoiFilterActive,
    onToggleAoiFilter: (active: boolean) => {
      aoiFilterActive = active;
      refreshDeckOverlay();
    },
  });
</script>

<section class="geospatial-workbench" data-tour="geospatial-workbench-root" aria-label="3D Map">
  <GeospatialMapStage
    {...stgAll}
    bind:visibility
    bind:basemap
    bind:wmsLayer
    bind:layerOpacity
    bind:zoneFilter
    bind:plotSearch
    bind:gpkgPanelOpen
    bind:gpkgDestPath
    bind:mapContainer
  >
    <GeospatialSidebarDrawer
      {...drwAll}
      bind:activePanel
      bind:aoiDrawMode
      bind:aoiTargetMode
      bind:aoiSUName
      bind:aoiSiteUnit
      bind:aoiVertices
      bind:aoiPreview
      bind:qaSelectedPlots
    />
  </GeospatialMapStage>
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
    background: var(--vpro-gold);
    color: var(--vpro-navy);
  }
</style>
