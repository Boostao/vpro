<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { SpatialWorkbenchPayload } from '../../bindings/github.com/boostao/vpro/app';
  import type { GeoPackageExportOutcome } from '../../bindings/github.com/boostao/vpro/app/internal/interchange/models';
  import {
    DEFAULT_BC_WMS_LAYER,
    DEFAULT_MAP_BASEMAP,
    INITIAL_LAYER_OPACITY,
    isAbsoluteFilesystemPath,
    type BCOpenMapsWMSLayerId,
    type MapBasemapId,
    type MapLayerOpacity,
    type MapLayerVisibility,
    type SpatialComputeBackendInfo,
    type SpatialGpkgExportInput,
  } from './geospatialWorkbench';
  import SpatialGpkgExportPanel from './SpatialGpkgExportPanel.svelte';
  import SpatialMapLegend from './SpatialMapLegend.svelte';
  import SpatialWorkbenchHeader from './SpatialWorkbenchHeader.svelte';

  let {
    contextId,
    project,
    computeInfo,
    payload = null,
    flatGeobufCount = 0,
    discrepancyCount = 0,
    plotCount = 0,
    distinctZones = [],
    visibility = $bindable<MapLayerVisibility>(),
    basemap = $bindable<MapBasemapId>(DEFAULT_MAP_BASEMAP),
    wmsLayer = $bindable<BCOpenMapsWMSLayerId>(DEFAULT_BC_WMS_LAYER),
    layerOpacity = $bindable<MapLayerOpacity>({ ...INITIAL_LAYER_OPACITY }),
    zoneFilter = $bindable(''),
    plotSearch = $bindable(''),
    pmtilesArchiveWarning = '',
    gpkgPanelOpen = $bindable(false),
    gpkgDestPath = $bindable(''),
    gpkgExporting = false,
    gpkgOutcome = null,
    loading = false,
    mutating = false,
    aoiDrawMode = false,
    aoiMatchedCount = 0,
    viewportMatchedCount = 0,
    mapContainer = $bindable<HTMLDivElement | undefined>(),
    onApplyLayers,
    onApplyOpacity,
    onRefreshDeck,
    onFitBounds,
    onRefreshStream,
    onExportGpkg,
    children,
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
    zoneFilter?: string;
    plotSearch?: string;
    pmtilesArchiveWarning?: string;
    gpkgPanelOpen?: boolean;
    gpkgDestPath?: string;
    gpkgExporting?: boolean;
    gpkgOutcome?: GeoPackageExportOutcome | null;
    loading?: boolean;
    mutating?: boolean;
    aoiDrawMode?: boolean;
    aoiMatchedCount?: number;
    viewportMatchedCount?: number;
    mapContainer?: HTMLDivElement | undefined;
    onApplyLayers: () => void;
    onApplyOpacity: () => void;
    onRefreshDeck: () => void;
    onFitBounds: () => void;
    onRefreshStream: () => void;
    onExportGpkg: (opts: SpatialGpkgExportInput) => Promise<void> | void;
    children: Snippet;
  } = $props();
</script>

<SpatialWorkbenchHeader
  {contextId}
  {project}
  {computeInfo}
  {payload}
  {flatGeobufCount}
  {discrepancyCount}
  {plotCount}
  {distinctZones}
  bind:visibility
  bind:basemap
  bind:wmsLayer
  bind:layerOpacity
  bind:zoneFilter
  bind:plotSearch
  {loading}
  {mutating}
  {gpkgExporting}
  {onApplyLayers}
  {onApplyOpacity}
  {onRefreshDeck}
  {onFitBounds}
  {onRefreshStream}
  onToggleGpkgPanel={(defaultPath) => {
    if (defaultPath && (!gpkgDestPath.trim() || !isAbsoluteFilesystemPath(gpkgDestPath))) {
      gpkgDestPath = defaultPath;
    }
    gpkgPanelOpen = !gpkgPanelOpen;
  }}
/>

{#if pmtilesArchiveWarning}
  <div class="wb-alert wb-alert-warn" role="alert" data-pmtiles-fallback-warning>
    {pmtilesArchiveWarning}
  </div>
{/if}

{#if gpkgPanelOpen}
  <SpatialGpkgExportPanel
    bind:gpkgDestPath
    {gpkgExporting}
    {gpkgOutcome}
    {loading}
    {mutating}
    onExport={onExportGpkg}
    onClose={() => {
      gpkgPanelOpen = false;
    }}
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
    <SpatialMapLegend
      {aoiMatchedCount}
      {viewportMatchedCount}
      {basemap}
      bcOpenMapsWMS={visibility.bcOpenMapsWMS}
      {wmsLayer}
    />
  </div>
  {@render children()}
</div>

<style>
  .wb-alert-warn {
    background: var(--vpro-canvas);
    border: 1px solid var(--vpro-border);
    border-left: 4px solid var(--vpro-gold);
    color: var(--vpro-navy);
    padding: 0.5rem 0.75rem;
    border-radius: 0.25rem;
    font-size: 0.875rem;
    margin: 0.35rem 0;
  }
</style>
