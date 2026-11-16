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

  const filteredQARows = $derived<SpatialPlotQARow[]>(
    filterSpatialQARows(qaReport?.rows ?? [], qaFilterOnlyIssues)
  );

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

<div class="wb-panel-body">
  <div class="wb-card">
    <div class="wb-card-head">
      <h2>Batch Coordinate &amp; BGC Stamp</h2>
      <button type="button" class="wb-btn" onclick={() => void onReaudit()} disabled={loading || mutating}>
        Re-Audit
      </button>
    </div>

    {#if qaReport}
      <div class="wb-qa-summary">
        <span>Unsigned West Lon: <strong>{qaReport.unsignedLonCount}</strong></span>
        <span>UTM &gt;50m Div: <strong>{qaReport.utmDivergenceCount}</strong></span>
        <span>BGC Mismatch: <strong>{qaReport.bgcMismatchCount}</strong></span>
        <span>Missing GIS_BGC: <strong>{qaReport.missingGisBgcCount}</strong></span>
      </div>
    {/if}

    <div class="wb-form-stack">
      <label class="wb-check-row">
        <input type="checkbox" bind:checked={stampGISBGC} />
        <span>Stamp &lt;Project&gt;_Admin.GIS_BGC &amp; GIS_BGC_VER = 13</span>
      </label>
      <label class="wb-check-row">
        <input type="checkbox" bind:checked={stampAdminFields} />
        <span>Stamp Ecosection, FSRegionDistrict, NtsMapSheet &amp; Province</span>
      </label>
      <label class="wb-check-row">
        <input type="checkbox" bind:checked={stampOnlyWhenBlank} />
        <span>Preserve existing non-blank field entries (only fill blanks)</span>
      </label>
      <label class="wb-check-row">
        <input type="checkbox" bind:checked={normalizeLonSign} />
        <span>Normalize unsigned positive West longitudes (125.4 -&gt; -125.4)</span>
      </label>
      <label class="wb-check-row">
        <input type="checkbox" bind:checked={syncUTMFromDD} />
        <span>Project NAD83 Lat/Lon -&gt; UTMZone / Easting / Northing</span>
      </label>
      <label class="wb-check-row">
        <input type="checkbox" data-sync-latlon-from-utm bind:checked={syncLatLonFromUTM} />
        <span>Derive NAD83 Lat/Lon &lt;- UTMZone / Easting / Northing</span>
      </label>
      <label class="wb-check-row">
        <input type="checkbox" bind:checked={qaFilterOnlyIssues} />
        <span>Show only plots with QA discrepancies or missing GIS_BGC</span>
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
          <th scope="col">Field-&gt;GIS</th>
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
              <button
                type="button"
                class="wb-link-btn mono"
                onclick={() => onOpenPlot?.(row.plotNumber)}
              >
                {row.plotNumber}
              </button>
            </td>
            <td class:wb-flag-text={row.bgcMismatch}>
              {row.fieldBgc || '-'} -&gt; {row.suggestedGisBgc || row.storedGisBgc || '-'}
            </td>
            <td class:wb-flag-text={row.divergenceFlagged || row.longitudeSignFlipped}>
              {#if row.longitudeSignFlipped}+W {/if}
              {row.divergenceMeters != null ? `${row.divergenceMeters.toFixed(0)}m` : '-'}
            </td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
</div>
