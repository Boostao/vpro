<script lang="ts">
  import type {
    ClimateEdatopicResult,
    ClimateGroupBy,
    ClimateRefPeriod,
    PlotClimateRow,
    RRuntimeStatus,
  } from './rSidecarWorkbench';

  let {
    activeSu = 'None',
    busy = false,
    runtimeStatus = null,
    climateEngineLabel = '',
    refPeriod = $bindable<ClimateRefPeriod>('1961_1990'),
    climateGroupBy = $bindable<ClimateGroupBy>('bgc'),
    climateBgcFilter = $bindable(''),
    climateUseSu = $bindable(false),
    climateForceRefresh = $bindable(false),
    climateResult = null,
    displayedClimateRows = [],
    onRunClimate,
    onLoadCached,
  }: {
    activeSu?: string;
    busy?: boolean;
    runtimeStatus?: RRuntimeStatus | null;
    climateEngineLabel?: string;
    refPeriod?: ClimateRefPeriod;
    climateGroupBy?: ClimateGroupBy;
    climateBgcFilter?: string;
    climateUseSu?: boolean;
    climateForceRefresh?: boolean;
    climateResult?: ClimateEdatopicResult | null;
    displayedClimateRows?: PlotClimateRow[];
    onRunClimate: () => Promise<void> | void;
    onLoadCached: () => Promise<void> | void;
  } = $props();
</script>

<div class="panel">
  <div class="card">
    <h3>R &amp; Quarto Setup Status</h3>
    {#if runtimeStatus}
      <div class="badge-strip">
        <span class="badge" class:ok={runtimeStatus.available} class:warn={!runtimeStatus.available}>
          Rscript: {runtimeStatus.available ? `Ready (${runtimeStatus.rVersion})` : 'Not Detected'}
        </span>
        <span class="badge" class:ok={runtimeStatus.quartoAvailable} class:warn={!runtimeStatus.quartoAvailable}>
          Quarto CLI: {runtimeStatus.quartoAvailable ? `Ready (${runtimeStatus.quartoVersion})` : 'Fallback RMarkdown'}
        </span>
        <span
          class="badge"
          class:warn={!runtimeStatus.available}
          class:ok={runtimeStatus.available && runtimeStatus.climrRastersCached}
          class:neutral={runtimeStatus.available && !runtimeStatus.climrRastersCached}
        >
          Climate Engine: {climateEngineLabel}
        </span>
        <span class="badge" class:ok={runtimeStatus.readyForClustering} class:warn={!runtimeStatus.readyForClustering}>
          R Clustering: {runtimeStatus.readyForClustering ? 'Ready' : 'Missing Packages'}
        </span>
      </div>

      {#if runtimeStatus.packages.length > 0}
        <div class="table-scroll">
          <table class="data-table compact">
            <thead>
              <tr>
                <th>R Package</th>
                <th>Status</th>
                <th>Version</th>
                <th>Role</th>
              </tr>
            </thead>
            <tbody>
              {#each runtimeStatus.packages as pkg}
                <tr>
                  <td><code>{pkg.name}</code></td>
                  <td>{pkg.installed ? 'Installed' : 'Missing'}</td>
                  <td>{pkg.version || '—'}</td>
                  <td>{pkg.required ? 'Required' : 'Optional'}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {/if}

      {#if runtimeStatus.setupInstructions.length > 0}
        <div class="setup-box">
          <strong>Workstation Setup Guidance:</strong>
          <ul>
            {#each runtimeStatus.setupInstructions as step}
              <li>{step}</li>
            {/each}
          </ul>
        </div>
      {/if}
    {:else}
      <p class="muted">Click "Check R &amp; Quarto Setup" to inspect installed Rscript, Quarto CLI, and R package versions.</p>
    {/if}
  </div>

  <div class="card">
    <h3>Cached Plot Climate Normals</h3>
    <div class="form-row">
      <label>
        Reference Period
        <select bind:value={refPeriod}>
          <option value="1961_1990">1961-1990 Historical Baseline</option>
          <option value="1991_2020">1991-2020 Modern Normal</option>
        </select>
      </label>
      <label>
        Group Grids By
        <select bind:value={climateGroupBy}>
          <option value="bgc">BGC Subzone / Variant</option>
          <option value="site_unit">Assigned Site Unit (*_SU)</option>
        </select>
      </label>
      <label>
        BGC Prefix Filter
        <input type="text" bind:value={climateBgcFilter} placeholder="e.g. SBS, BWBS, MH" />
      </label>
      <label class="checkbox-label">
        <input type="checkbox" bind:checked={climateUseSu} />
        Scope to Active SU ({activeSu})
      </label>
      <label class="checkbox-label">
        <input type="checkbox" bind:checked={climateForceRefresh} />
        Force Re-compute Cache
      </label>
    </div>

    <div class="button-row">
      <button type="button" class="btn-primary" disabled={busy} onclick={onRunClimate}>
        Compute Climate &amp; CMD to aSMR
      </button>
      <button type="button" class="btn-secondary" disabled={busy} onclick={onLoadCached}>
        Load Cached Plot Climate
      </button>
    </div>

    {#if climateResult}
      <div class="kpi-row">
        <div class="kpi"><span>Scoped Plots</span><strong>{climateResult.totalScopedPlots}</strong></div>
        <div class="kpi"><span>Coordinatized</span><strong>{climateResult.coordinatizedPlots}</strong></div>
        <div class="kpi"><span>Cache Hits</span><strong>{climateResult.cacheHits}</strong></div>
        <div class="kpi"><span>Cache Misses</span><strong>{climateResult.cacheMisses}</strong></div>
      </div>
    {/if}

    {#if displayedClimateRows.length > 0}
      <div class="table-scroll">
        <table class="data-table">
          <thead>
            <tr>
              <th>Plot</th>
              <th>BGC</th>
              <th>Lat / Lon</th>
              <th>Elev (m)</th>
              <th>MAT (C)</th>
              <th>MAP (mm)</th>
              <th>MSP (mm)</th>
              <th>PAS (mm)</th>
              <th>CMD</th>
              <th>CMD.site</th>
              <th>rSMR</th>
              <th>aSMR</th>
              <th>Source</th>
            </tr>
          </thead>
          <tbody>
            {#each displayedClimateRows.slice(0, 100) as row}
              <tr>
                <td><code>{row.plotNumber}</code></td>
                <td>{row.bgc || '—'}</td>
                <td>{row.latitude.toFixed(4)}, {row.longitude.toFixed(4)}</td>
                <td>{row.elevation.toFixed(0)}</td>
                <td>{row.mat.toFixed(1)}</td>
                <td>{row.map.toFixed(0)}</td>
                <td>{row.msp.toFixed(0)}</td>
                <td>{row.pas.toFixed(0)}</td>
                <td>{row.cmd.toFixed(0)}</td>
                <td>{row.cmdSite !== undefined ? row.cmdSite.toFixed(0) : '—'}</td>
                <td>{row.rsmr || '—'}</td>
                <td><strong>{row.asmr !== undefined ? row.asmr : '—'}</strong></td>
                <td><code>{row.source}</code></td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
  </div>
</div>
