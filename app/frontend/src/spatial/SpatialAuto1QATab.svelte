<script lang="ts">
  import type { SpatialBatchAuditReport } from '../../bindings/github.com/boostao/vpro/app';
  import { filterSpatialQARows, type SpatialStampOptions } from './geospatialWorkbench';

  type SpatialPlotQARow = NonNullable<SpatialBatchAuditReport['rows']>[number];

  let {
    qaReport = null,
    qaSelectedPlots = $bindable<Record<string, boolean>>({}),
    loading = false,
    mutating = false,
    onReaudit,
    onApplyStamp,
    onOpenPlot,
  }: {
    qaReport?: SpatialBatchAuditReport | null;
    qaSelectedPlots?: Record<string, boolean>;
    loading?: boolean;
    mutating?: boolean;
    onReaudit: () => Promise<void> | void;
    onApplyStamp: (opts: SpatialStampOptions) => Promise<void> | void;
    onOpenPlot?: (plotNumber: string) => void;
  } = $props();

  let qaFilterOnlyIssues = $state(true);
  let stampGISBGC = $state(true);
  let stampAdminFields = $state(true);
  let stampOnlyWhenBlank = $state(true);
  let normalizeLonSign = $state(true);
  let syncUTMFromDD = $state(true);
  let syncLatLonFromUTM = $state(false);

  const filteredQARows = $derived<SpatialPlotQARow[]>(filterSpatialQARows(qaReport?.rows ?? [], qaFilterOnlyIssues));

  function buildStampOpts(allScoped: boolean): SpatialStampOptions {
    const plotNumbers = Object.entries(qaSelectedPlots)
      .filter(([, checked]) => checked)
      .map(([plotNum]) => plotNum);
    return {
      allScoped,
      plotNumbers,
      stampGisBgc: stampGISBGC,
      stampAdminFields,
      onlyWhenBlank: stampOnlyWhenBlank,
      normalizeLongitudeSign: normalizeLonSign,
      syncUtmFromLatLon: syncUTMFromDD,
      syncLatLonFromUTM,
    };
  }
</script>

<div class="wb-panel-body wb-qa-panel-body" data-spatial-qa-panel>
  <div class="wb-card">
    <div class="wb-card-head">
      <h2>Batch Coordinate &amp; BGC Stamp</h2>
      <button type="button" class="wb-btn" onclick={() => void onReaudit()} disabled={loading || mutating}>
        Re-Audit
      </button>
    </div>

    {#if qaReport}
      <div class="wb-qa-summary">
        <span>Positive West Lon: <strong>{qaReport.unsignedLonCount}</strong></span>
        <span>UTM &gt;50 m Offset: <strong>{qaReport.utmDivergenceCount}</strong></span>
        <span>BGC Mismatch: <strong>{qaReport.bgcMismatchCount}</strong></span>
        <span>Missing Mapped BGC: <strong>{qaReport.missingGisBgcCount}</strong></span>
      </div>
    {/if}

    <div class="wb-form-stack">
      <label class="wb-check-row">
        <input type="checkbox" bind:checked={stampGISBGC} />
        <span>Stamp mapped BGC unit &amp; version (BECdb v13)</span>
      </label>
      <label class="wb-check-row">
        <input type="checkbox" bind:checked={stampAdminFields} />
        <span>Stamp Ecosection, Forest Region/District, NTS Map Sheet &amp; Province</span>
      </label>
      <label class="wb-check-row">
        <input type="checkbox" bind:checked={stampOnlyWhenBlank} />
        <span>Keep existing field entries (only fill blank values)</span>
      </label>
      <label class="wb-check-row">
        <input type="checkbox" bind:checked={normalizeLonSign} />
        <span>Add negative sign to Western Hemisphere longitudes (125.4 to -125.4)</span>
      </label>
      <label class="wb-check-row">
        <input type="checkbox" bind:checked={syncUTMFromDD} />
        <span>Calculate NAD83 UTM Zone, Easting &amp; Northing from Latitude/Longitude</span>
      </label>
      <label class="wb-check-row">
        <input type="checkbox" data-sync-latlon-from-utm bind:checked={syncLatLonFromUTM} />
        <span>Calculate NAD83 Latitude/Longitude from UTM Zone, Easting &amp; Northing</span>
      </label>
      <label class="wb-check-row">
        <input type="checkbox" bind:checked={qaFilterOnlyIssues} />
        <span>Show only plots with coordinate discrepancies or missing mapped BGC</span>
      </label>
    </div>

    <div class="wb-btn-row">
      <button
        type="button"
        class="wb-btn wb-btn-primary"
        disabled={mutating || loading}
        onclick={() => void onApplyStamp(buildStampOpts(false))}
      >
        Stamp Checked Plots + Audit
      </button>
      <button
        type="button"
        class="wb-btn"
        disabled={mutating || loading}
        onclick={() => void onApplyStamp(buildStampOpts(true))}
      >
        Stamp All Scoped Plots
      </button>
    </div>
  </div>

  <div class="wb-qa-table-wrap">
    <table class="wb-qa-table">
      <thead>
        <tr>
          <th scope="col">Sel</th>
          <th scope="col">Plot</th>
          <th scope="col">Field / Map BGC</th>
          <th scope="col">UTM Delta</th>
        </tr>
      </thead>
      <tbody>
        {#each filteredQARows.slice(0, 150) as row (row.plotNumber)}
          <tr>
            <td>
              <input
                type="checkbox"
                aria-label={`Select plot ${row.plotNumber} for spatial stamp`}
                checked={!!qaSelectedPlots[row.plotNumber]}
                onchange={(e) => {
                  qaSelectedPlots = {
                    ...qaSelectedPlots,
                    [row.plotNumber]: (e.currentTarget as HTMLInputElement).checked,
                  };
                }}
              />
            </td>
            <td>
              <button type="button" class="wb-link-btn mono" onclick={() => onOpenPlot?.(row.plotNumber)}>
                {row.plotNumber}
              </button>
            </td>
            <td class:wb-flag-text={row.bgcMismatch}>
              {row.fieldBgc || '-'} -&gt; {row.suggestedGisBgc || row.storedGisBgc || '-'}
            </td>
            <td class:wb-flag-text={row.divergenceFlagged || row.longitudeSignFlipped}>
              {#if row.longitudeSignFlipped}+W
              {/if}
              {row.divergenceMeters != null ? `${row.divergenceMeters.toFixed(0)}m` : '-'}
            </td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
</div>

<style>
  .wb-qa-panel-body {
    min-height: 0;
    padding-bottom: 12rem;
    scroll-padding-bottom: 12rem;
  }
</style>
