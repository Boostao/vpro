<script lang="ts">
  import type { SpatialWorkbenchPayload } from '../../bindings/github.com/boostao/vpro/app';
  import {
    buildDefaultGeoPackageExportPath,
    summarizeArchiveResolution,
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
    zoneFilter = $bindable(''),
    plotSearch = $bindable(''),
    loading = false,
    mutating = false,
    gpkgExporting = false,
    onApplyLayers,
    onRefreshDeck,
    onFitBounds,
    onRefreshStream,
    onToggleGpkgPanel,
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
    zoneFilter?: string;
    plotSearch?: string;
    loading?: boolean;
    mutating?: boolean;
    gpkgExporting?: boolean;
    onApplyLayers: () => void;
    onRefreshDeck: () => void;
    onFitBounds: () => void;
    onRefreshStream: () => void;
    onToggleGpkgPanel: (defaultPath: string) => void;
  } = $props();
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
    <label class="wb-toggle">
      <input type="checkbox" bind:checked={visibility.bgcFill} onchange={onApplyLayers} />
      <span>BGC v13 Polygons</span>
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
      Export .gpkg...
    </button>
  </div>
</div>
