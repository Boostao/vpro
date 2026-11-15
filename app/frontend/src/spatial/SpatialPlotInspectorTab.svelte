<script lang="ts">
  import type { SpatialAttributeSuggestion } from '../../bindings/github.com/boostao/vpro/app';
  import type { WorkbenchPlotPoint } from './geospatialWorkbench';

  let {
    selectedPlot = null,
    selectedSuggestion = null,
    suggestionBusy = false,
    filteredPoints = [],
    onOpenPlot,
    onInspectPlot,
  }: {
    selectedPlot?: WorkbenchPlotPoint | null;
    selectedSuggestion?: SpatialAttributeSuggestion | null;
    suggestionBusy?: boolean;
    filteredPoints?: WorkbenchPlotPoint[];
    onOpenPlot?: (plotNumber: string) => void;
    onInspectPlot: (pt: WorkbenchPlotPoint) => Promise<void> | void;
  } = $props();
</script>

<div class="wb-panel-body">
  {#if selectedPlot}
    <div class="wb-card">
      <div class="wb-card-head">
        <div>
          <span class="wb-label">PLOT PIN</span>
          <h2>{selectedPlot.plotNumber}</h2>
        </div>
        {#if onOpenPlot}
          <button
            type="button"
            class="wb-btn wb-btn-primary"
            onclick={() => onOpenPlot?.(selectedPlot!.plotNumber)}
          >
            Open in FS882 Editor
          </button>
        {/if}
      </div>

      <dl class="wb-kv-grid">
        <div><dt>NAD83 Lat, Western Lon</dt><dd>{selectedPlot.lat.toFixed(5)}, {selectedPlot.lon.toFixed(5)}</dd></div>
        <div><dt>Active SiteUnit</dt><dd>{selectedPlot.siteUnit || 'Unassigned'}</dd></div>
        <div><dt>Field BGC</dt><dd>{selectedPlot.fieldBgc || 'Blank'}</dd></div>
        <div>
          <dt>GIS_BGC (v13)</dt>
          <dd class:wb-flag-text={selectedPlot.bgcMismatch}>
            {selectedPlot.gisBgc || selectedSuggestion?.gisBgc || 'Pending'}
            {#if selectedPlot.bgcMismatch} (Mismatch){/if}
          </dd>
        </div>
        <div>
          <dt>UTM vs DD Delta</dt>
          <dd class:wb-flag-text={selectedPlot.divergenceFlagged}>
            {selectedPlot.hasUtm ? `${selectedPlot.divergenceMeters.toFixed(1)} m` : 'No UTM entered'}
          </dd>
        </div>
        <div><dt>Elevation / Slope</dt><dd>{selectedPlot.elevation ?? '-'} m / {selectedPlot.slope ?? '-'}%</dd></div>
        <div><dt>Ecosection</dt><dd>{selectedPlot.ecosection || selectedSuggestion?.ecosection || '-'}</dd></div>
        <div><dt>NR District</dt><dd>{selectedPlot.fsRegionDistrict || selectedSuggestion?.fsRegionDistrict || '-'}</dd></div>
      </dl>

      {#if suggestionBusy}
        <p class="wb-muted" role="status">Querying local PMTiles v3 Hilbert MVT index...</p>
      {:else if selectedSuggestion}
        <div class="wb-suggestion-box">
          <strong>Auto-1 PMTiles Attribution ({selectedSuggestion.bgcSource || 'overview'} z{selectedSuggestion.bgcZoom}):</strong>
          <div>BGC: {selectedSuggestion.gisBgc} ({selectedSuggestion.zoneName || 'BC'})</div>
          <div>NAD83 UTM Zone {selectedSuggestion.utmZone}: {selectedSuggestion.utmEasting.toFixed(1)} E, {selectedSuggestion.utmNorthing.toFixed(1)} N</div>
          <div>BCGS 1:20k Sheet: {selectedSuggestion.ntsMapSheet} | District: {selectedSuggestion.fsRegionDistrict}</div>
          {#if selectedSuggestion.terrainSanityNote}
            <div class="wb-muted">{selectedSuggestion.terrainSanityNote}</div>
          {/if}
        </div>
      {/if}
    </div>
  {:else}
    <p class="wb-muted">Click any plot pin on the map or choose from the list below to inspect coordinates and BGC v13 overlay.</p>
  {/if}

  <div class="wb-list-header">Scoped Plots ({filteredPoints.length})</div>
  <div class="wb-plot-list">
    {#each filteredPoints.slice(0, 120) as pt (pt.plotNumber)}
      <button
        type="button"
        class="wb-plot-row"
        class:selected={selectedPlot?.plotNumber === pt.plotNumber}
        onclick={() => void onInspectPlot(pt)}
      >
        <span class="wb-plot-code mono">{pt.plotNumber}</span>
        <span>{pt.fieldBgc || '-'} -&gt; {pt.gisBgc || '-'}</span>
        {#if pt.bgcMismatch || pt.divergenceFlagged}
          <span class="wb-pill-err">QA</span>
        {/if}
      </button>
    {/each}
  </div>
</div>
