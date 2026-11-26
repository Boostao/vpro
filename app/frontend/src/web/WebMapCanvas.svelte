<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { Layers, Maximize2, SquareDashedMousePointer } from '@lucide/svelte';
  import {
    Map as MapLibreMap,
    NavigationControl,
    Popup,
    ScaleControl,
    addProtocol,
    setWorkerUrl,
    type GeoJSONSource,
    type MapLayerMouseEvent,
  } from 'maplibre-gl';
  import maplibreWorkerUrl from 'maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url';
  import 'maplibre-gl/dist/maplibre-gl.css';
  import { Protocol } from 'pmtiles';
  import type { PMTilesManifest } from '../../bindings/github.com/boostao/vpro/app';
  import {
    BC_DEFAULT_BOUNDS,
    DEFAULT_WEB_MAP_BASEMAP,
    WEB_MAP_BASEMAPS,
    buildBBoxGeoJSON,
    buildPlotsGeoJSON,
    buildWebExplorerMapStyle,
    computePointsBounds,
    normalizeBoundingBox,
    type BECMasterBoundingBox,
    type BECMasterMapPoint,
    type WebMapBasemapId,
  } from './webBECMasterFilter';

  let {
    allPoints = [],
    matchedPoints = [],
    isFiltered = false,
    activePlotNumber = '',
    bbox = null,
    drawBBoxMode = $bindable(false),
    pmtilesBaseUrl = '/pmtiles',
    manifest = null,
    onSelectPlot,
    onBBoxChange,
    onStartDrawBBox,
  }: {
    allPoints: readonly BECMasterMapPoint[];
    matchedPoints: readonly BECMasterMapPoint[];
    isFiltered: boolean;
    activePlotNumber?: string;
    bbox?: BECMasterBoundingBox | null;
    drawBBoxMode?: boolean;
    pmtilesBaseUrl?: string;
    manifest?: PMTilesManifest | null;
    onSelectPlot: (plotNumber: string) => void;
    onBBoxChange: (nextBBox: BECMasterBoundingBox) => void;
    onStartDrawBBox?: () => void;
  } = $props();

  const SRC_ALL = 'becmaster-plots-all-src';
  const SRC_SEL = 'becmaster-plots-selected-src';
  const SRC_BBOX = 'becmaster-bbox-src';
  const LYR_ALL = 'becmaster-plots-all';
  const LYR_SEL = 'becmaster-plots-selected';
  const LYR_ACTIVE = 'becmaster-plots-active';
  const LYR_BBOX_FILL = 'becmaster-bbox-fill';
  const LYR_BBOX_LINE = 'becmaster-bbox-line';

  let mapContainer = $state<HTMLDivElement | undefined>(undefined);
  let mapInstance: MapLibreMap | null = null;
  let hoverPopup: Popup | null = null;
  let styleReady = false;
  let alive = true;

  let basemap = $state<WebMapBasemapId>(DEFAULT_WEB_MAP_BASEMAP);
  let showBgcOverlay = $state(true);
  let bgcOpacity = $state(0.35);
  let forceNoPmtiles = $state(false);
  let mapWarning = $state('');

  let dragStartLngLat: [number, number] | null = null;
  let draggingBox = false;
  let hasFittedOnce = false;

  function escapeHtml(raw: unknown): string {
    return String(raw ?? '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  }

  function ensureDynamicLayers() {
    const map = mapInstance;
    if (!map || !map.isStyleLoaded()) return;

    if (!map.getSource(SRC_ALL)) {
      map.addSource(SRC_ALL, {
        type: 'geojson',
        data: buildPlotsGeoJSON(allPoints),
      });
    }
    if (!map.getSource(SRC_SEL)) {
      map.addSource(SRC_SEL, {
        type: 'geojson',
        data: buildPlotsGeoJSON(isFiltered ? matchedPoints : []),
      });
    }
    if (!map.getSource(SRC_BBOX)) {
      map.addSource(SRC_BBOX, {
        type: 'geojson',
        data: buildBBoxGeoJSON(bbox),
      });
    }

    if (!map.getLayer(LYR_BBOX_FILL)) {
      map.addLayer({
        id: LYR_BBOX_FILL,
        type: 'fill',
        source: SRC_BBOX,
        paint: {
          'fill-color': '#fcba19',
          'fill-opacity': 0.16,
        },
      });
    }
    if (!map.getLayer(LYR_BBOX_LINE)) {
      map.addLayer({
        id: LYR_BBOX_LINE,
        type: 'line',
        source: SRC_BBOX,
        paint: {
          'line-color': '#d8292f',
          'line-width': 2.2,
          'line-dasharray': [3, 2],
        },
      });
    }

    if (!map.getLayer(LYR_ALL)) {
      map.addLayer({
        id: LYR_ALL,
        type: 'circle',
        source: SRC_ALL,
        paint: {
          'circle-radius': ['interpolate', ['linear'], ['zoom'], 4, 2.4, 8, 4.2, 12, 6],
          'circle-color': '#1e293b',
          'circle-opacity': isFiltered ? 0.36 : 0.78,
          'circle-stroke-color': '#ffffff',
          'circle-stroke-width': isFiltered ? 0.4 : 0.75,
          'circle-stroke-opacity': isFiltered ? 0.35 : 0.7,
        },
      });
    }

    if (!map.getLayer(LYR_SEL)) {
      map.addLayer({
        id: LYR_SEL,
        type: 'circle',
        source: SRC_SEL,
        paint: {
          'circle-radius': ['interpolate', ['linear'], ['zoom'], 4, 3.6, 8, 5.5, 12, 7.5],
          'circle-color': '#d8292f',
          'circle-opacity': 0.92,
          'circle-stroke-color': '#fcba19',
          'circle-stroke-width': 1.4,
        },
      });
    }

    if (!map.getLayer(LYR_ACTIVE)) {
      map.addLayer({
        id: LYR_ACTIVE,
        type: 'circle',
        source: SRC_ALL,
        filter: ['==', ['get', 'plotNumber'], activePlotNumber || '__none__'],
        paint: {
          'circle-radius': 8.5,
          'circle-color': '#fcba19',
          'circle-stroke-color': '#003366',
          'circle-stroke-width': 2.5,
        },
      });
    }

    styleReady = true;
    syncDataSources();
  }

  function syncDataSources() {
    const map = mapInstance;
    if (!map || !styleReady) return;

    const allSrc = map.getSource(SRC_ALL) as GeoJSONSource | undefined;
    if (allSrc && typeof allSrc.setData === 'function') {
      allSrc.setData(buildPlotsGeoJSON(allPoints));
    }
    const selSrc = map.getSource(SRC_SEL) as GeoJSONSource | undefined;
    if (selSrc && typeof selSrc.setData === 'function') {
      selSrc.setData(buildPlotsGeoJSON(isFiltered ? matchedPoints : []));
    }
    const bboxSrc = map.getSource(SRC_BBOX) as GeoJSONSource | undefined;
    if (bboxSrc && typeof bboxSrc.setData === 'function') {
      bboxSrc.setData(buildBBoxGeoJSON(bbox));
    }

    if (map.getLayer(LYR_ALL)) {
      map.setPaintProperty(LYR_ALL, 'circle-opacity', isFiltered ? 0.36 : 0.78);
      map.setPaintProperty(LYR_ALL, 'circle-stroke-width', isFiltered ? 0.4 : 0.75);
      map.setPaintProperty(LYR_ALL, 'circle-stroke-opacity', isFiltered ? 0.35 : 0.7);
    }
    if (map.getLayer(LYR_ACTIVE)) {
      map.setFilter(LYR_ACTIVE, ['==', ['get', 'plotNumber'], activePlotNumber || '__none__']);
    }
  }

  function updateStyle() {
    const map = mapInstance;
    if (!map) return;
    styleReady = false;
    const style = buildWebExplorerMapStyle({
      basemap,
      showBgcOverlay,
      bgcOpacity,
      pmtilesBaseUrl,
      manifest,
      forceNoPmtiles,
    });
    map.setStyle(style);
    map.once('styledata', () => {
      if (!alive) return;
      ensureDynamicLayers();
    });
  }

  function applyBgcVisibility() {
    const map = mapInstance;
    if (!map || !styleReady) return;
    const vis = showBgcOverlay ? 'visible' : 'none';
    if (map.getLayer('bgc-zones-fill')) {
      map.setLayoutProperty('bgc-zones-fill', 'visibility', vis);
      map.setPaintProperty('bgc-zones-fill', 'fill-opacity', bgcOpacity);
    }
    if (map.getLayer('bgc-subzone-outline')) {
      map.setLayoutProperty('bgc-subzone-outline', 'visibility', vis);
      map.setPaintProperty('bgc-subzone-outline', 'line-opacity', Math.min(0.85, bgcOpacity + 0.25));
    }
  }

  export function fitToPoints(points?: readonly BECMasterMapPoint[]) {
    const map = mapInstance;
    if (!map) return;
    const target = points ?? (isFiltered && matchedPoints.length > 0 ? matchedPoints : allPoints);
    const bounds = computePointsBounds(target) ?? BC_DEFAULT_BOUNDS;
    map.fitBounds(bounds, { padding: 42, maxZoom: 11, duration: 450 });
  }

  function showHoverForEvent(e: MapLayerMouseEvent) {
    const map = mapInstance;
    if (!map || drawBBoxMode) return;
    const feat = e.features?.[0];
    if (!feat || feat.geometry.type !== 'Point') return;
    const props = feat.properties ?? {};
    const plotNum = escapeHtml(props.plotNumber);
    const bgc = escapeHtml(`${props.zone ?? ''}${props.subZone ?? ''}`);
    const siteSeries = escapeHtml(props.siteSeries);
    const proj = escapeHtml(props.projectId);
    const reg = escapeHtml(props.region);
    const coords = feat.geometry.coordinates as [number, number];

    map.getCanvas().style.cursor = 'pointer';
    if (!hoverPopup) {
      hoverPopup = new Popup({ closeButton: false, closeOnClick: false, offset: 10, maxWidth: '240px' });
    }
    hoverPopup
      .setLngLat(coords)
      .setHTML(
        `<div class="web-map-tooltip">` +
          `<div class="web-map-tt-title">Plot ${plotNum}</div>` +
          (bgc ? `<div>BGC: <strong>${bgc}</strong>${siteSeries ? ` / ${siteSeries}` : ''}</div>` : '') +
          (proj ? `<div>Project: ${proj}</div>` : '') +
          (reg ? `<div>Region: ${reg}</div>` : '') +
          `<div class="web-map-tt-hint">Click to open FS882 card</div>` +
          `</div>`
      )
      .addTo(map);
  }

  function clearHover() {
    const map = mapInstance;
    if (map && !drawBBoxMode) {
      map.getCanvas().style.cursor = '';
    }
    hoverPopup?.remove();
  }

  function handlePlotClick(e: MapLayerMouseEvent) {
    if (drawBBoxMode || draggingBox) return;
    const feat = e.features?.[0];
    const plotNum = feat?.properties?.plotNumber;
    if (typeof plotNum === 'string' && plotNum.length > 0) {
      onSelectPlot(plotNum);
    }
  }

  function unprojectClientPoint(clientX: number, clientY: number): [number, number] | null {
    const map = mapInstance;
    if (!map) return null;
    const rect = map.getCanvas().getBoundingClientRect();
    const lngLat = map.unproject([clientX - rect.left, clientY - rect.top]);
    return [lngLat.lng, lngLat.lat];
  }

  function handlePointerDown(e: MouseEvent) {
    if (!drawBBoxMode || e.button !== 0 || !mapInstance) return;
    const pt = unprojectClientPoint(e.clientX, e.clientY);
    if (!pt) return;
    e.preventDefault();
    dragStartLngLat = pt;
    draggingBox = true;
    hoverPopup?.remove();
  }

  function handlePointerMove(e: MouseEvent) {
    if (!draggingBox || !dragStartLngLat || !mapInstance) return;
    const pt = unprojectClientPoint(e.clientX, e.clientY);
    if (!pt) return;
    const nextBox = normalizeBoundingBox(dragStartLngLat, pt);
    const bboxSrc = mapInstance.getSource(SRC_BBOX) as GeoJSONSource | undefined;
    if (bboxSrc && typeof bboxSrc.setData === 'function') {
      bboxSrc.setData(buildBBoxGeoJSON(nextBox));
    }
    onBBoxChange(nextBox);
  }

  function handlePointerUp(e: MouseEvent) {
    if (!draggingBox || !dragStartLngLat || !mapInstance) return;
    const pt = unprojectClientPoint(e.clientX, e.clientY);
    draggingBox = false;
    const start = dragStartLngLat;
    dragStartLngLat = null;
    if (pt && (Math.abs(pt[0] - start[0]) > 0.001 || Math.abs(pt[1] - start[1]) > 0.001)) {
      const nextBox = normalizeBoundingBox(start, pt);
      onBBoxChange(nextBox);
    }
    drawBBoxMode = false;
  }

  function handleWindowKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape' && drawBBoxMode) {
      draggingBox = false;
      dragStartLngLat = null;
      drawBBoxMode = false;
    }
  }

  function triggerQuickDrawBox() {
    onStartDrawBBox?.();
    drawBBoxMode = !drawBBoxMode;
  }

  $effect(() => {
    const map = mapInstance;
    if (!map) return;
    if (drawBBoxMode) {
      map.dragPan.disable();
      map.getCanvas().style.cursor = 'crosshair';
      hoverPopup?.remove();
    } else {
      map.dragPan.enable();
      map.getCanvas().style.cursor = '';
    }
  });

  $effect(() => {
    // Track reactive plot/filter/bbox inputs and update GeoJSON sources cleanly.
    void allPoints;
    void matchedPoints;
    void isFiltered;
    void activePlotNumber;
    void bbox;
    syncDataSources();
    if (!hasFittedOnce && styleReady && allPoints.length > 0) {
      hasFittedOnce = true;
      fitToPoints(isFiltered && matchedPoints.length > 0 ? matchedPoints : allPoints);
    }
  });

  $effect(() => {
    void showBgcOverlay;
    void bgcOpacity;
    applyBgcVisibility();
  });

  onMount(() => {
    if (!mapContainer) return;
    try {
      setWorkerUrl(maplibreWorkerUrl);
      const pmtilesGlobal = globalThis as { __vproPMTilesRegistered?: boolean };
      if (!pmtilesGlobal.__vproPMTilesRegistered) {
        const protocol = new Protocol();
        addProtocol('pmtiles', protocol.tile);
        pmtilesGlobal.__vproPMTilesRegistered = true;
      }
      const style = buildWebExplorerMapStyle({
        basemap,
        showBgcOverlay,
        bgcOpacity,
        pmtilesBaseUrl,
        manifest,
        forceNoPmtiles,
      });
      const map = new MapLibreMap({
        container: mapContainer,
        style,
        bounds: BC_DEFAULT_BOUNDS,
        fitBoundsOptions: { padding: 24 },
        attributionControl: { compact: true },
      });
      map.addControl(new NavigationControl({ visualizePitch: false }), 'top-right');
      map.addControl(new ScaleControl({ unit: 'metric' }), 'bottom-right');

      map.on('load', () => {
        if (!alive) return;
        ensureDynamicLayers();
        if (allPoints.length > 0 && !hasFittedOnce) {
          hasFittedOnce = true;
          fitToPoints(isFiltered && matchedPoints.length > 0 ? matchedPoints : allPoints);
        }
      });

      map.on('click', LYR_SEL, handlePlotClick);
      map.on('click', LYR_ALL, handlePlotClick);
      map.on('mouseenter', LYR_SEL, showHoverForEvent);
      map.on('mouseenter', LYR_ALL, showHoverForEvent);
      map.on('mouseleave', LYR_SEL, clearHover);
      map.on('mouseleave', LYR_ALL, clearHover);

      map.on('error', (evt) => {
        if (!alive) return;
        const errMsg = String((evt as { error?: { message?: string } })?.error?.message ?? '');
        if (!forceNoPmtiles && /pmtiles|bc-bgc-v13/i.test(errMsg)) {
          forceNoPmtiles = true;
          updateStyle();
        }
      });

      mapInstance = map;
    } catch (cause) {
      const msg = cause instanceof Error ? cause.message : String(cause ?? 'Unknown error');
      mapWarning = `Interactive map display is unavailable in this browser (${msg}). You can still filter plots and download datasets below.`;
    }
  });

  onDestroy(() => {
    alive = false;
    hoverPopup?.remove();
    hoverPopup = null;
    if (mapInstance) {
      mapInstance.remove();
      mapInstance = null;
    }
  });
</script>

<svelte:window onkeydown={handleWindowKeydown} onmousemove={handlePointerMove} onmouseup={handlePointerUp} />

<section class="web-map-stage" aria-label="Interactive BECMaster Plot Map" data-web-map-canvas>
  <div class="web-map-toolbar">
    <div class="web-map-toolbar-group">
      <label class="web-map-control">
        <span class="web-map-control-label">Basemap</span>
        <select
          class="web-map-select"
          bind:value={basemap}
          onchange={() => updateStyle()}
          data-web-basemap-select
        >
          {#each WEB_MAP_BASEMAPS as opt (opt.id)}
            <option value={opt.id}>{opt.label}</option>
          {/each}
        </select>
      </label>

      <label class="web-map-bgc-toggle">
        <input type="checkbox" bind:checked={showBgcOverlay} data-web-bgc-toggle />
        <Layers size={13} aria-hidden="true" />
        <span>BGC v13 Overlay</span>
      </label>

      {#if showBgcOverlay}
        <label class="web-map-opacity" title="BGC v13 overlay opacity">
          <span class="sr-only">BGC overlay opacity</span>
          <input
            type="range"
            min="0.1"
            max="0.85"
            step="0.05"
            bind:value={bgcOpacity}
            aria-label="BGC v13 overlay opacity"
          />
        </label>
      {/if}
    </div>

    <div class="web-map-toolbar-group">
      <button
        type="button"
        class="web-map-tool-btn"
        class:active={drawBBoxMode}
        aria-pressed={drawBBoxMode}
        onclick={triggerQuickDrawBox}
        data-map-draw-bbox-btn
      >
        <SquareDashedMousePointer size={13} aria-hidden="true" />
        <span>{drawBBoxMode ? 'Cancel Box Draw' : 'Draw Bounding Box'}</span>
      </button>
      <button
        type="button"
        class="web-map-tool-btn"
        onclick={() => fitToPoints()}
        title="Zoom map to selected plots"
        data-map-fit-btn
      >
        <Maximize2 size={13} aria-hidden="true" />
        <span>Fit Plots</span>
      </button>
    </div>
  </div>

  {#if mapWarning}
    <div class="web-map-fallback" role="status">{mapWarning}</div>
  {/if}

  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class="web-map-container"
    class:drawing={drawBBoxMode}
    bind:this={mapContainer}
    onmousedown={handlePointerDown}
  ></div>

  <div class="web-map-legend" aria-label="Map legend">
    <span class="web-legend-item">
      <span class="web-dot web-dot-all"></span>
      <span>All Plots ({allPoints.length.toLocaleString()})</span>
    </span>
    {#if isFiltered}
      <span class="web-legend-item">
        <span class="web-dot web-dot-selected"></span>
        <span>Selected ({matchedPoints.length.toLocaleString()})</span>
      </span>
    {/if}
    {#if bbox}
      <span class="web-legend-item">
        <span class="web-box-swatch"></span>
        <span>Bounding Box</span>
      </span>
    {/if}
    <span class="web-legend-tip">Click any plot dot to view its FS882 field card</span>
  </div>
</section>

<style>
  .web-map-stage {
    position: relative;
    display: flex;
    flex-direction: column;
    flex: 1;
    min-height: 430px;
    background: #edf1f5;
    border: 1px solid var(--vpro-border, #d1d5db);
    border-radius: 6px;
    overflow: hidden;
  }

  .web-map-toolbar {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    padding: 7px 10px;
    background: var(--vpro-surface, #ffffff);
    border-bottom: 1px solid var(--vpro-border, #d1d5db);
    z-index: 2;
  }

  .web-map-toolbar-group {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 8px;
  }

  .web-map-control {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 12px;
    font-weight: 600;
    color: var(--vpro-navy, #003366);
  }

  .web-map-control-label {
    white-space: nowrap;
  }

  .web-map-select {
    padding: 4px 8px;
    border-radius: 4px;
    border: 1px solid var(--vpro-border, #d1d5db);
    background: #ffffff;
    font-size: 12px;
    color: var(--vpro-ink, #313132);
  }

  .web-map-bgc-toggle {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    font-size: 12px;
    font-weight: 600;
    color: var(--vpro-ink, #313132);
    cursor: pointer;
    user-select: none;
  }

  .web-map-bgc-toggle input {
    accent-color: var(--vpro-navy, #003366);
    margin: 0;
  }

  .web-map-opacity input[type='range'] {
    width: 72px;
    accent-color: var(--vpro-navy, #003366);
    vertical-align: middle;
  }

  .web-map-tool-btn {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    padding: 5px 9px;
    border-radius: 4px;
    border: 1px solid var(--vpro-border-strong, #9ca3af);
    background: #ffffff;
    color: var(--vpro-navy, #003366);
    font-size: 12px;
    font-weight: 600;
    cursor: pointer;
  }

  .web-map-tool-btn:hover {
    background: var(--vpro-navy-tint, #ebf1f8);
    border-color: var(--vpro-navy, #003366);
  }

  .web-map-tool-btn.active {
    background: var(--vpro-gold, #fcba19);
    border-color: #b7791f;
    color: #002244;
  }

  .web-map-container {
    flex: 1;
    min-height: 360px;
    width: 100%;
  }

  .web-map-container.drawing {
    cursor: crosshair;
  }

  .web-map-fallback {
    padding: 10px 12px;
    background: var(--vpro-warning-bg, #fef6e0);
    border-bottom: 1px solid var(--vpro-warning-border, #d99b26);
    color: var(--vpro-warning-ink, #704b00);
    font-size: 12.5px;
  }

  .web-map-legend {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 12px;
    padding: 6px 10px;
    background: rgba(255, 255, 255, 0.96);
    border-top: 1px solid var(--vpro-border, #d1d5db);
    font-size: 11.5px;
    color: var(--vpro-ink-secondary, #4b5563);
  }

  .web-legend-item {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    font-weight: 600;
    color: var(--vpro-ink, #313132);
  }

  .web-dot {
    width: 10px;
    height: 10px;
    border-radius: 999px;
    display: inline-block;
  }

  .web-dot-all {
    background: #1e293b;
    border: 1.5px solid #ffffff;
    box-shadow: 0 0 0 1px #94a3b8;
  }

  .web-dot-selected {
    background: #d8292f;
    border: 1.5px solid #fcba19;
  }

  .web-box-swatch {
    width: 12px;
    height: 10px;
    border: 1.5px dashed #d8292f;
    background: rgba(252, 186, 25, 0.25);
    display: inline-block;
  }

  .web-legend-tip {
    margin-left: auto;
    font-style: italic;
    color: var(--vpro-ink-muted, #5f6b7a);
  }

  :global(.web-map-tooltip) {
    font-family: var(--vpro-font-sans, sans-serif);
    font-size: 11.5px;
    line-height: 1.35;
    color: #313132;
  }

  :global(.web-map-tt-title) {
    font-weight: 700;
    color: #003366;
    margin-bottom: 2px;
  }

  :global(.web-map-tt-hint) {
    margin-top: 3px;
    font-size: 10.5px;
    color: #5f6b7a;
  }
</style>
