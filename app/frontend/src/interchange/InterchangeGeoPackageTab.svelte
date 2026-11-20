<script lang="ts">
  import type { FileDialogFilter, GeoPackageExportOutcome, LumpTableSummary } from './interchangeHub';

  let {
    contextId,
    busy,
    operationHeld,
    discoveredLumpTables,
    lumpOptionValue,
    formatLumpOptionLabel,
    gpkgLumpKey,
    gpkgDestPath = $bindable(''),
    gpkgCrs = $bindable<'EPSG:3005' | 'EPSG:4326'>('EPSG:3005'),
    gpkgIncludeAttributes = $bindable(true),
    gpkgIncludeUnlocated = $bindable(false),
    gpkgOutcome,
    onApplyLumpOption,
    onBrowseExternalLumpDb,
    onPickFilePath,
    onRunGeoPackageExport,
  }: {
    contextId: string;
    busy: boolean;
    operationHeld: boolean;
    discoveredLumpTables: LumpTableSummary[];
    lumpOptionValue: (item: LumpTableSummary, list?: readonly LumpTableSummary[]) => string;
    formatLumpOptionLabel: (item: LumpTableSummary) => string;
    gpkgLumpKey: string;
    gpkgDestPath?: string;
    gpkgCrs?: 'EPSG:3005' | 'EPSG:4326';
    gpkgIncludeAttributes?: boolean;
    gpkgIncludeUnlocated?: boolean;
    gpkgOutcome: GeoPackageExportOutcome | null;
    onApplyLumpOption: (optionValue: string) => void;
    onBrowseExternalLumpDb: () => void;
    onPickFilePath: (
      mode: 'open' | 'save',
      title: string,
      defaultFilename: string,
      filters: FileDialogFilter[],
      assign: (chosen: string) => void | Promise<void>
    ) => Promise<void>;
    onRunGeoPackageExport: () => Promise<void>;
  } = $props();
</script>

<div class="hub-card">
  <h3>OGC GeoPackage 1.3 (.gpkg) Spatial &amp; Relational Exporter</h3>
  <p class="desc">
    Writes native SQLite GeoPackage Point features with full untruncated Env + Admin + SiteUnit columns, automatic
    Western Hemisphere longitude sign normalization, and optional non-spatial relational tables for QGIS and ArcGIS Pro.
    Coordinate bounds enforced: BC / Western North America [45..85 N, -170..-100 W] (positive Western longitudes
    [100..170] are normalized automatically).
  </p>
  <div class="form-row">
    <label class="grow">
      <span>Destination .gpkg File Path</span>
      <div class="input-with-browse">
        <input
          type="text"
          class="grow"
          bind:value={gpkgDestPath}
          placeholder="/path/to/bec_plots.gpkg"
          disabled={busy || operationHeld}
        />
        <button
          type="button"
          class="btn-secondary"
          data-save-gpkg
          disabled={busy || operationHeld}
          onclick={() =>
            onPickFilePath(
              'save',
              'Save GeoPackage (.gpkg)',
              'bec_plots.gpkg',
              [{ DisplayName: 'GeoPackage (*.gpkg)', Pattern: '*.gpkg' }],
              (p) => {
                gpkgDestPath = p;
              }
            )}
        >
          Save As...
        </button>
      </div>
    </label>
    <label>
      <span>Coordinate Reference System</span>
      <select bind:value={gpkgCrs} disabled={busy || operationHeld}>
        <option value="EPSG:3005">EPSG:3005 — NAD83 / BC Albers (Ministry Standard)</option>
        <option value="EPSG:4326">EPSG:4326 — NAD83 Geographic (Lon/Lat)</option>
      </select>
    </label>
  </div>
  <div class="form-row">
    <label class="check-inline">
      <input type="checkbox" bind:checked={gpkgIncludeAttributes} disabled={busy || operationHeld} />
      <span>Include veg, humus, mineral attribute tables</span>
    </label>
    <label class="check-inline">
      <input type="checkbox" bind:checked={gpkgIncludeUnlocated} disabled={busy || operationHeld} />
      <span>Include unlocated plots (NULL geometry)</span>
    </label>
    <label class="grow">
      <span>Optional *_Lump Table</span>
      <div class="input-with-browse">
        <select
          class="grow"
          data-lump-select="geopackage"
          value={gpkgLumpKey}
          onchange={(e) => onApplyLumpOption((e.currentTarget as HTMLSelectElement).value)}
          disabled={busy || operationHeld}
        >
          <option value="">None (raw unlumped species)</option>
          {#each discoveredLumpTables as item (item.tableName + '::' + item.databasePath)}
            <option value={lumpOptionValue(item, discoveredLumpTables)}>{formatLumpOptionLabel(item)}</option>
          {/each}
        </select>
        <button
          type="button"
          class="btn-secondary"
          data-browse-lump-db="geopackage"
          disabled={busy || operationHeld}
          onclick={onBrowseExternalLumpDb}
        >
          From .db…
        </button>
      </div>
    </label>
    <button
      type="button"
      class="btn-primary"
      disabled={busy || operationHeld || !contextId}
      onclick={onRunGeoPackageExport}
    >
      Export GeoPackage (.gpkg)
    </button>
  </div>

  {#if gpkgOutcome}
    <div class="receipt-box success">
      <strong>Exported {gpkgOutcome.featureCount} plot features ({gpkgOutcome.crs}, SRS {gpkgOutcome.srsId})</strong>
      <span>
        Located: {gpkgOutcome.locatedPlotCount} | Skipped unlocated: {gpkgOutcome.skippedUnlocatedCount} | Flipped positive
        West longitudes: {gpkgOutcome.normalizedWestLongitudes}
      </span>
      <span>
        Attribute tables: {gpkgOutcome.attributeTables.join(', ') || 'none'} | Path: <code>{gpkgOutcome.path}</code>
      </span>
    </div>
  {/if}
</div>

<style>
  .hub-card {
    background: var(--vpro-surface);
    border: 1px solid var(--vpro-border);
    border-top: 3px solid var(--vpro-navy);
    border-radius: 4px;
    padding: 1rem;
    display: grid;
    gap: 0.75rem;
    align-content: start;
    min-width: 0;
  }
  .hub-card h3 {
    margin: 0;
    color: var(--vpro-navy);
    font-size: 1rem;
  }
  .desc {
    margin: 0;
    color: var(--vpro-ink-secondary);
    font-size: 0.83rem;
    line-height: 1.45;
  }
  .form-row {
    display: flex;
    flex-wrap: wrap;
    gap: 0.6rem;
    align-items: end;
    min-width: 0;
  }
  .form-row label {
    display: grid;
    gap: 0.25rem;
    font-size: 0.8rem;
    color: var(--vpro-ink);
    min-width: 0;
  }
  .input-with-browse {
    display: flex;
    flex-wrap: wrap;
    gap: 0.4rem;
    align-items: center;
    min-width: 0;
  }
  .grow {
    flex: 1 1 200px;
    min-width: 0;
  }
  .check-inline {
    display: inline-flex !important;
    flex-direction: row;
    align-items: center;
    gap: 0.4rem;
    padding-bottom: 0.35rem;
  }
  input:not([type='checkbox']),
  select {
    padding: 0.45rem 0.6rem;
    border: 1px solid var(--vpro-border-strong);
    border-radius: 4px;
    font-size: 0.84rem;
    font-family: inherit;
    color: var(--vpro-ink);
    background: var(--vpro-surface);
    min-width: 0;
    max-width: 100%;
    box-sizing: border-box;
  }
  .btn-primary {
    background: var(--vpro-navy);
    color: var(--vpro-surface);
    border: 1px solid var(--vpro-navy);
    border-radius: 4px;
    padding: 0.48rem 0.9rem;
    font-weight: 600;
    font-size: 0.83rem;
  }
  .btn-secondary {
    background: var(--vpro-surface);
    color: var(--vpro-navy);
    border: 1px solid var(--vpro-navy);
    border-radius: 4px;
    padding: 0.48rem 0.9rem;
    font-weight: 600;
    font-size: 0.83rem;
  }
  .receipt-box {
    background: var(--vpro-canvas);
    border: 1px solid var(--vpro-border);
    border-left: 4px solid var(--vpro-navy);
    padding: 0.65rem 0.8rem;
    border-radius: 4px;
    display: grid;
    gap: 0.35rem;
    font-size: 0.82rem;
    min-width: 0;
    overflow-wrap: anywhere;
  }
  .receipt-box.success {
    background: var(--vpro-success-bg);
    border-left-color: var(--vpro-success);
  }
  @media (pointer: coarse) {
    .btn-primary,
    .btn-secondary,
    input:not([type='checkbox']),
    select {
      min-height: 44px;
    }
  }
</style>
