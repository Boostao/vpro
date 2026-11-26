<script lang="ts">
  import type { SpatialWorkbenchPayload } from '../../bindings/github.com/boostao/vpro/app';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import {
    BC_OPENMAPS_WMS_OPTIONS,
    DEFAULT_BC_WMS_LAYER,
    DEFAULT_MAP_BASEMAP,
    INITIAL_LAYER_OPACITY,
    MAP_BASEMAP_OPTIONS,
    QUICK_BASEMAP_IDS,
    buildDefaultGeoPackageExportPath,
    getMapBasemapOption,
    resolveGoogleHybridBasemap,
    summarizeArchiveResolution,
    type BCOpenMapsWMSLayerId,
    type GoogleHybridConfig,
    type MapBasemapId,
    type MapLayerOpacity,
    type MapLayerVisibility,
    type SpatialComputeBackendInfo,
  } from './geospatialWorkbench';

  let {
    contextId,
    project,
    computeInfo,
    payload = null,
    flatGeobufCount = 0,
    discrepancyCount = 0,
    plotCount = 0,
    distinctZones = [],
    visibility = $bindable(),
    basemap = $bindable<MapBasemapId>(DEFAULT_MAP_BASEMAP),
    wmsLayer = $bindable<BCOpenMapsWMSLayerId>(DEFAULT_BC_WMS_LAYER),
    layerOpacity = $bindable<MapLayerOpacity>({ ...INITIAL_LAYER_OPACITY }),
    googleHybridConfig = { tileUrlTemplate: '', apiKey: '' },
    zoneFilter = $bindable(''),
    plotSearch = $bindable(''),
    loading = false,
    mutating = false,
    gpkgExporting = false,
    onApplyLayers,
    onApplyOpacity,
    onRefreshDeck,
    onFitBounds,
    onRefreshStream,
    onToggleGpkgPanel,
    onOpenLayersSyncTab,
  }: {
    contextId: string;
    project: string;
    computeInfo: SpatialComputeBackendInfo;
    payload?: SpatialWorkbenchPayload | null;
    flatGeobufCount?: number;
    discrepancyCount?: number;
    plotCount?: number;
    distinctZones?: string[];
    visibility: MapLayerVisibility;
    basemap?: MapBasemapId;
    wmsLayer?: BCOpenMapsWMSLayerId;
    layerOpacity?: MapLayerOpacity;
    googleHybridConfig?: GoogleHybridConfig;
    zoneFilter?: string;
    plotSearch?: string;
    loading?: boolean;
    mutating?: boolean;
    gpkgExporting?: boolean;
    onApplyLayers: () => void;
    onApplyOpacity: () => void;
    onRefreshDeck: () => void;
    onFitBounds: () => void;
    onRefreshStream: () => void;
    onToggleGpkgPanel: (defaultPath: string) => void;
    onOpenLayersSyncTab?: () => void;
  } = $props();

  const bgcPct = $derived(Math.round((layerOpacity?.bgc ?? INITIAL_LAYER_OPACITY.bgc) * 100));
  const adminPct = $derived(Math.round((layerOpacity?.admin ?? INITIAL_LAYER_OPACITY.admin) * 100));
  const wmsPct = $derived(Math.round((layerOpacity?.wms ?? INITIAL_LAYER_OPACITY.wms) * 100));
  const quickBasemaps = $derived(QUICK_BASEMAP_IDS.map((id) => getMapBasemapOption(id)));
  const googleHybridFallback = $derived(
    basemap === 'google-hybrid' && resolveGoogleHybridBasemap(googleHybridConfig).fallbackActive
  );

  function selectQuickBasemap(id: MapBasemapId) {
    if (basemap === id) return;
    basemap = id;
    onApplyLayers();
  }

  function updateOpacity(key: keyof MapLayerOpacity, rawPct: string) {
    const pct = Math.max(0, Math.min(100, Number(rawPct)));
    if (!Number.isFinite(pct)) return;
    layerOpacity = { ...layerOpacity, [key]: pct / 100 };
    onApplyOpacity();
  }
</script>

<header class="wb-banner">
  <div class="wb-title-block">
    <span class="wb-eyebrow">BC MINISTRY OF FORESTS - BEC 3D MAP</span>
    <h1>3D BGC v13 Map, Coordinate Check &amp; Site Units</h1>
  </div>
  <div class="wb-badges">
    <span
      class="wb-badge wb-badge-gold"
      data-compute-backend={computeInfo.backend}
      title={computeInfo.fallbackReason ?? computeInfo.adapterLabel}
    >
      {computeInfo.backend === 'webgpu' ? 'Hardware Accelerated' : 'Standard Graphics'}
    </span>
    <span class="wb-badge">{summarizeArchiveResolution(payload)}</span>
    <span class="wb-badge">
      Plots: {payload?.plottableCount ?? 0} / {payload?.totalPlots ?? 0}
    </span>
    <span
      class="wb-badge"
      class:wb-badge-alert={(payload?.bgcMismatchCount ?? 0) > 0 || (payload?.utmDivergenceCount ?? 0) > 0}
    >
      BGC Mismatch: {payload?.bgcMismatchCount ?? 0} | UTM Div: {payload?.utmDivergenceCount ?? 0}
    </span>
  </div>
</header>

<div class="wb-toolbar" role="toolbar" aria-label="Map layers and spatial tools">
  <div class="wb-layer-toggles">
    <div class="wb-basemap-control">
      <label for="wb-basemap-select" class="wb-control-label">Basemap</label>
      <select
        id="wb-basemap-select"
        class="wb-input"
        aria-label="Map basemap"
        bind:value={basemap}
        onchange={onApplyLayers}
      >
        {#each MAP_BASEMAP_OPTIONS as opt (opt.id)}
          <option value={opt.id}>{opt.label}</option>
        {/each}
      </select>
    </div>

    <div class="wb-quick-basemaps" role="group" aria-label="Quick basemap switcher" data-quick-basemap-bar>
      {#each quickBasemaps as opt (opt.id)}
        <button
          type="button"
          class="wb-pill-btn"
          class:active={basemap === opt.id}
          aria-pressed={basemap === opt.id}
          data-quick-basemap={opt.id}
          onclick={() => selectQuickBasemap(opt.id)}
        >
          {opt.shortLabel ?? opt.label}
        </button>
      {/each}
    </div>

    <label class="wb-toggle">
      <input type="checkbox" bind:checked={visibility.bgcFill} onchange={onApplyLayers} />
      <span>BGC v13 Polygons</span>
    </label>
    <label class="wb-toggle">
      <input
        type="checkbox"
        bind:checked={visibility.forestRegions}
        onchange={onApplyLayers}
        data-toolbar-forest-regions
      />
      <span>BC Forest Regions</span>
    </label>
    <label class="wb-toggle">
      <input type="checkbox" bind:checked={visibility.ecosections} onchange={onApplyLayers} />
      <span>Ecosections</span>
    </label>
    <label class="wb-toggle">
      <input type="checkbox" bind:checked={visibility.nrDistricts} onchange={onApplyLayers} />
      <span>NR Districts</span>
    </label>
    <label class="wb-toggle">
      <input type="checkbox" bind:checked={visibility.discrepancyVectors} onchange={onRefreshDeck} />
      <span>Dual-Pin UTM Vectors ({discrepancyCount})</span>
    </label>
    <label class="wb-toggle">
      <input type="checkbox" bind:checked={visibility.hillshade3D} onchange={onApplyLayers} />
      <span>3D Reconnaissance Tilt</span>
    </label>
    <label class="wb-toggle">
      <input type="checkbox" bind:checked={visibility.bcOpenMapsWMS} onchange={onApplyLayers} />
      <span>Online BC OpenMaps WMS</span>
    </label>
    {#if visibility.bcOpenMapsWMS}
      <div class="wb-basemap-control">
        <label for="wb-wms-layer-select" class="sr-only">BC OpenMaps WMS overlay</label>
        <select
          id="wb-wms-layer-select"
          class="wb-input"
          aria-label="BC OpenMaps WMS overlay"
          bind:value={wmsLayer}
          onchange={onApplyLayers}
        >
          {#each BC_OPENMAPS_WMS_OPTIONS as opt (opt.id)}
            <option value={opt.id}>{opt.label}</option>
          {/each}
        </select>
      </div>
    {/if}
  </div>

  <div class="wb-filter-controls">
    <label for="wb-zone-filter" class="sr-only">Filter by BEC Zone</label>
    <select id="wb-zone-filter" bind:value={zoneFilter} class="wb-input">
      <option value="">All BEC Zones</option>
      {#each distinctZones as z (z)}
        <option value={z}>{z}</option>
      {/each}
    </select>

    <label for="wb-plot-search" class="sr-only">Filter plots by PlotNumber or SiteUnit</label>
    <input
      id="wb-plot-search"
      type="search"
      placeholder="Find plot or unit..."
      bind:value={plotSearch}
      class="wb-input"
    />

    <button type="button" class="wb-btn" onclick={onFitBounds} disabled={loading || plotCount === 0}>
      Fit Project Extent
    </button>
    <button type="button" class="wb-btn" onclick={onRefreshStream} disabled={loading || mutating}> Refresh Map </button>
    <button
      type="button"
      class="wb-btn wb-btn-gold"
      data-gpkg-export-shortcut
      disabled={loading || mutating || gpkgExporting || !contextId}
      onclick={() => {
        onToggleGpkgPanel(buildDefaultGeoPackageExportPath(project, payload?.projectPath));
      }}
    >
      {IS_WEB_READONLY ? 'Download .gpkg' : 'Export .gpkg...'}
    </button>
  </div>
</div>

<div class="wb-opacity-bar" role="group" aria-label="Layer opacity controls">
  <span class="wb-opacity-title">Layer Opacity</span>

  <div class="wb-opacity-item" class:wb-opacity-muted={!visibility.bgcFill}>
    <label for="wb-opacity-bgc">BGC v13 Polygons</label>
    <input
      id="wb-opacity-bgc"
      class="wb-opacity-slider"
      type="range"
      min="0"
      max="100"
      step="1"
      value={bgcPct}
      aria-label="BGC v13 Polygons opacity"
      aria-valuetext={`${bgcPct}%`}
      oninput={(e) => updateOpacity('bgc', e.currentTarget.value)}
    />
    <span class="wb-opacity-value">{bgcPct}%</span>
  </div>

  <div
    class="wb-opacity-item"
    class:wb-opacity-muted={!visibility.ecosections && !visibility.nrDistricts && !visibility.forestRegions}
  >
    <label for="wb-opacity-admin" title="Opacity for Ecosections, BC Forest Regions, and NR Districts boundaries"
      >Boundaries</label
    >
    <input
      id="wb-opacity-admin"
      class="wb-opacity-slider"
      type="range"
      min="0"
      max="100"
      step="1"
      value={adminPct}
      aria-label="Administrative boundaries opacity"
      aria-valuetext={`${adminPct}%`}
      oninput={(e) => updateOpacity('admin', e.currentTarget.value)}
    />
    <span class="wb-opacity-value">{adminPct}%</span>
  </div>

  <div class="wb-opacity-item" class:wb-opacity-muted={!visibility.bcOpenMapsWMS}>
    <label for="wb-opacity-wms">BC OpenMaps WMS</label>
    <input
      id="wb-opacity-wms"
      class="wb-opacity-slider"
      type="range"
      min="0"
      max="100"
      step="1"
      value={wmsPct}
      aria-label="Online BC OpenMaps WMS opacity"
      aria-valuetext={`${wmsPct}%`}
      oninput={(e) => updateOpacity('wms', e.currentTarget.value)}
    />
    <span class="wb-opacity-value">{wmsPct}%</span>
  </div>

  {#if googleHybridFallback}
    <div class="wb-google-fallback-note" role="status" data-toolbar-google-fallback>
      <span>Google Hybrid: showing Satellite Hybrid until a Google Maps tile URL is configured.</span>
      {#if !IS_WEB_READONLY && onOpenLayersSyncTab}
        <button type="button" class="wb-inline-link" onclick={onOpenLayersSyncTab}>Configure in Map &amp; Sync</button>
      {/if}
    </div>
  {/if}
</div>

<style>
  .wb-quick-basemaps {
    display: inline-flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.25rem;
  }
  .wb-pill-btn {
    border: 1px solid var(--vpro-border);
    border-radius: 999px;
    padding: 0.2rem 0.55rem;
    font-size: 0.72rem;
    font-weight: 600;
    background: var(--vpro-canvas);
    color: var(--vpro-navy);
    cursor: pointer;
    white-space: nowrap;
  }
  .wb-pill-btn:hover {
    border-color: var(--vpro-navy);
  }
  .wb-pill-btn.active {
    background: var(--vpro-navy);
    border-color: var(--vpro-navy);
    color: var(--vpro-gold);
  }
  .wb-google-fallback-note {
    display: inline-flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.4rem;
    margin-left: auto;
    font-size: 0.72rem;
    color: var(--vpro-navy);
  }
  .wb-inline-link {
    border: none;
    background: transparent;
    padding: 0;
    color: var(--vpro-navy);
    font-size: 0.72rem;
    font-weight: 700;
    text-decoration: underline;
    cursor: pointer;
  }
</style>
