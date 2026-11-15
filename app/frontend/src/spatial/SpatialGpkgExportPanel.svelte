<script lang="ts">
  import type { GeoPackageExportOutcome } from '../../bindings/github.com/boostao/vpro/app/internal/interchange/models';
  import type { SpatialGpkgExportInput } from './geospatialWorkbench';

  let {
    gpkgDestPath = $bindable(''),
    gpkgExporting = false,
    gpkgOutcome = null,
    loading = false,
    mutating = false,
    onExport,
    onClose,
  }: {
    gpkgDestPath?: string;
    gpkgExporting?: boolean;
    gpkgOutcome?: GeoPackageExportOutcome | null;
    loading?: boolean;
    mutating?: boolean;
    onExport: (opts: SpatialGpkgExportInput) => Promise<void> | void;
    onClose: () => void;
  } = $props();

  let gpkgCrs = $state<'EPSG:3005' | 'EPSG:4326'>('EPSG:3005');
  let gpkgIncludeAttributes = $state(true);
  let gpkgIncludeUnlocated = $state(false);
</script>

<div class="wb-gpkg-panel" data-gpkg-export-panel>
  <div class="wb-gpkg-grid">
    <label class="wb-gpkg-field">
      <span>Destination GeoPackage (.gpkg) Path</span>
      <input
        type="text"
        class="wb-input"
        data-gpkg-dest-input
        bind:value={gpkgDestPath}
        placeholder="/path/to/plots.gpkg"
        disabled={gpkgExporting}
      />
    </label>
    <label class="wb-gpkg-field">
      <span>CRS</span>
      <select class="wb-input" data-gpkg-crs-select bind:value={gpkgCrs} disabled={gpkgExporting}>
        <option value="EPSG:3005">EPSG:3005 (BC Albers)</option>
        <option value="EPSG:4326">EPSG:4326 (NAD83 Lon/Lat)</option>
      </select>
    </label>
    <label class="wb-check-row">
      <input type="checkbox" bind:checked={gpkgIncludeAttributes} disabled={gpkgExporting} />
      <span>Include veg/soil attribute tables</span>
    </label>
    <label class="wb-check-row">
      <input type="checkbox" bind:checked={gpkgIncludeUnlocated} disabled={gpkgExporting} />
      <span>Include unlocated plots</span>
    </label>
  </div>
  <div class="wb-btn-row">
    <button
      type="button"
      class="wb-btn wb-btn-primary"
      data-gpkg-export-run
      disabled={gpkgExporting || loading || mutating || !gpkgDestPath.trim()}
      onclick={() =>
        void onExport({
          destinationPath: gpkgDestPath,
          crs: gpkgCrs,
          includeAttributeTables: gpkgIncludeAttributes,
          includeUnlocatedPlots: gpkgIncludeUnlocated,
        })}
    >
      {gpkgExporting ? 'Exporting .gpkg...' : 'Export GeoPackage (.gpkg)'}
    </button>
    <button type="button" class="wb-btn" onclick={onClose}>Close</button>
  </div>
  {#if gpkgOutcome}
    <div class="wb-alert wb-alert-ok">
      Exported {gpkgOutcome.featureCount} features ({gpkgOutcome.crs}) | Flipped West Lons: {gpkgOutcome.normalizedWestLongitudes} | {gpkgOutcome.path}
    </div>
  {/if}
</div>
