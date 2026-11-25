<script lang="ts">
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import type { CSVExportOutcome, FileDialogFilter, LumpTableSummary, RDSExportOutcome } from './interchangeHub';

  let {
    contextId,
    busy,
    operationHeld,
    discoveredLumpTables,
    lumpOptionValue,
    formatLumpOptionLabel,
    csvLumpKey,
    longCsvDest = $bindable(''),
    wideCsvDest = $bindable(''),
    wideLayerMode = $bindable<'rollup_all' | 'strata_4' | 'species_layer'>('rollup_all'),
    wideZeroFill = $bindable(true),
    wideIncludeSiteUnit = $bindable(true),
    csvOutcome,
    rdsDestPath = $bindable(''),
    rdsOutcome,
    onApplyLumpOption,
    onBrowseExternalLumpDb,
    onPickFilePath,
    onRunLongCsvExport,
    onRunWideCsvExport,
    onRunRdsExport,
  }: {
    contextId: string;
    busy: boolean;
    operationHeld: boolean;
    discoveredLumpTables: LumpTableSummary[];
    lumpOptionValue: (item: LumpTableSummary, list?: readonly LumpTableSummary[]) => string;
    formatLumpOptionLabel: (item: LumpTableSummary) => string;
    csvLumpKey: string;
    longCsvDest?: string;
    wideCsvDest?: string;
    wideLayerMode?: 'rollup_all' | 'strata_4' | 'species_layer';
    wideZeroFill?: boolean;
    wideIncludeSiteUnit?: boolean;
    csvOutcome: CSVExportOutcome | null;
    rdsDestPath?: string;
    rdsOutcome: RDSExportOutcome | null;
    onApplyLumpOption: (optionValue: string) => void;
    onBrowseExternalLumpDb: () => void;
    onPickFilePath: (
      mode: 'open' | 'save',
      title: string,
      defaultFilename: string,
      filters: FileDialogFilter[],
      assign: (chosen: string) => void | Promise<void>
    ) => Promise<void>;
    onRunLongCsvExport: () => Promise<void>;
    onRunWideCsvExport: () => Promise<void>;
    onRunRdsExport: () => Promise<void>;
  } = $props();
</script>

<div class="two-col">
  <div class="hub-card">
    <h3>Long Tidy CSV &amp; Wide Plot-by-Species Matrix CSV</h3>
    <label class="field-label-block">
      <span>Optional *_Lump Table Applied at Export Time</span>
      <div class="input-with-browse">
        <select
          class="grow"
          data-lump-select="analytics"
          value={csvLumpKey}
          onchange={(e) => onApplyLumpOption((e.currentTarget as HTMLSelectElement).value)}
          disabled={busy || operationHeld}
        >
          <option value="">None (raw unlumped species)</option>
          {#each discoveredLumpTables as item (item.tableName + '::' + item.databasePath)}
            <option value={lumpOptionValue(item, discoveredLumpTables)}>{formatLumpOptionLabel(item)}</option>
          {/each}
        </select>
        {#if !IS_WEB_READONLY}
          <button
            type="button"
            class="btn-secondary"
            data-browse-lump-db="analytics"
            disabled={busy || operationHeld}
            onclick={onBrowseExternalLumpDb}
          >
            From .db…
          </button>
        {/if}
      </div>
    </label>

    <div class="sub-box">
      <h4>Long Tidy CSV (PlotNumber, SiteUnit, Layer, Species, ScientificName, Lifeform, Cover, Height, Collected)</h4>
      <div class="form-row">
        {#if !IS_WEB_READONLY}
          <input
            type="text"
            aria-label="Long tidy CSV destination file path"
            class="grow"
            bind:value={longCsvDest}
            placeholder="/path/to/veg_long.csv (optional for preview)"
            disabled={busy || operationHeld}
          />
          <button
            type="button"
            class="btn-secondary"
            data-save-long-csv
            disabled={busy || operationHeld}
            onclick={() =>
              onPickFilePath(
                'save',
                'Save Long Tidy CSV',
                'veg_long.csv',
                [{ DisplayName: 'CSV (*.csv)', Pattern: '*.csv' }],
                (p) => {
                  longCsvDest = p;
                }
              )}
          >
            Save As...
          </button>
        {/if}
        <button
          type="button"
          class="btn-primary"
          disabled={busy || operationHeld || !contextId}
          onclick={onRunLongCsvExport}
        >
          {IS_WEB_READONLY ? (busy ? 'Preparing download...' : 'Download Long CSV') : 'Export Long CSV'}
        </button>
      </div>
    </div>

    <div class="sub-box">
      <h4>Wide Plot x Species Matrix CSV</h4>
      <div class="form-row">
        <label>
          <span>Column Rollup</span>
          <select bind:value={wideLayerMode} disabled={busy || operationHeld}>
            <option value="rollup_all">Species Rollup (summed across layers, 99% cap)</option>
            <option value="strata_4">4-Strata Columns (Species_A, _B, _C, _D)</option>
            <option value="species_layer">Full Sub-Layer Columns (Species_A1..Ep)</option>
          </select>
        </label>
        <label class="check-inline">
          <input type="checkbox" bind:checked={wideZeroFill} disabled={busy || operationHeld} />
          <span>Zero-fill absences</span>
        </label>
        <label class="check-inline">
          <input type="checkbox" bind:checked={wideIncludeSiteUnit} disabled={busy || operationHeld} />
          <span>Include SiteUnit column</span>
        </label>
      </div>
      <div class="form-row">
        {#if !IS_WEB_READONLY}
          <input
            type="text"
            aria-label="Wide plot by species matrix CSV destination file path"
            class="grow"
            bind:value={wideCsvDest}
            placeholder="/path/to/veg_wide_matrix.csv"
            disabled={busy || operationHeld}
          />
          <button
            type="button"
            class="btn-secondary"
            data-save-wide-csv
            disabled={busy || operationHeld}
            onclick={() =>
              onPickFilePath(
                'save',
                'Save Wide Matrix CSV',
                'veg_wide_matrix.csv',
                [{ DisplayName: 'CSV (*.csv)', Pattern: '*.csv' }],
                (p) => {
                  wideCsvDest = p;
                }
              )}
          >
            Save As...
          </button>
        {/if}
        <button
          type="button"
          class="btn-primary"
          disabled={busy || operationHeld || !contextId}
          onclick={onRunWideCsvExport}
        >
          {IS_WEB_READONLY ? (busy ? 'Preparing download...' : 'Download Wide Matrix CSV') : 'Export Wide Matrix CSV'}
        </button>
      </div>
    </div>

    {#if csvOutcome}
      <div class="receipt-box">
        <strong>
          {csvOutcome.mode}: {csvOutcome.rowCount} rows x {csvOutcome.columnCount} cols ({csvOutcome.speciesCount} taxa)
        </strong>
        <textarea aria-label="Exported CSV preview" readonly rows={6} value={csvOutcome.previewCsv}></textarea>
      </div>
    {/if}
  </div>

  <div class="hub-card">
    <h3>Native R Serialization Format v2 (.rds) Export</h3>
    <p class="desc">
      Exports project tables (<code>env</code>, <code>admin</code>, <code>veg_long</code>, <code>humus</code>,
      <code>mineral</code>, <code>su</code>, <code>metadata</code>) as an .rds file ready for <code>readRDS()</code> in R,
      without requiring R to be installed.
    </p>
    <div class="form-stack">
      <label>
        <span>Optional *_Lump Table Applied to veg_long</span>
        <select
          data-lump-select="rds"
          value={csvLumpKey}
          onchange={(e) => onApplyLumpOption((e.currentTarget as HTMLSelectElement).value)}
          disabled={busy || operationHeld}
        >
          <option value="">None (raw unlumped species)</option>
          {#each discoveredLumpTables as item (item.tableName + '::' + item.databasePath)}
            <option value={lumpOptionValue(item, discoveredLumpTables)}>{formatLumpOptionLabel(item)}</option>
          {/each}
        </select>
      </label>
      {#if !IS_WEB_READONLY}
        <label>
          <span>Destination .rds Path</span>
          <div class="input-with-browse">
            <input
              type="text"
              class="grow"
              bind:value={rdsDestPath}
              placeholder="/path/to/project_snapshot.rds"
              disabled={busy || operationHeld}
            />
            <button
              type="button"
              class="btn-secondary"
              data-save-rds
              disabled={busy || operationHeld}
              onclick={() =>
                onPickFilePath(
                  'save',
                  'Save Native R .rds',
                  'project_snapshot.rds',
                  [{ DisplayName: 'R Data (*.rds)', Pattern: '*.rds' }],
                  (p) => {
                    rdsDestPath = p;
                  }
                )}
            >
              Save As...
            </button>
          </div>
        </label>
      {/if}
      <button type="button" class="btn-primary" disabled={busy || operationHeld || !contextId} onclick={onRunRdsExport}>
        {IS_WEB_READONLY ? (busy ? 'Preparing download...' : 'Download Native R .rds') : 'Export Native R .rds'}
      </button>
    </div>

    {#if rdsOutcome}
      <div class="receipt-box success">
        <strong>
          {IS_WEB_READONLY ? 'Downloaded' : 'Exported'} {rdsOutcome.plotCount} plots ({rdsOutcome.byteSize} bytes){#if !IS_WEB_READONLY}
            to <code>{rdsOutcome.path}</code>
          {/if}
        </strong>
        <div class="table-scroll">
          <table class="compact-table">
            <thead><tr><th>R data.frame</th><th>Rows</th><th>Columns</th></tr></thead>
            <tbody>
              {#each rdsOutcome.tables as tbl (tbl.name)}
                <tr><td class="mono">{tbl.name}</td><td>{tbl.rowCount}</td><td>{tbl.columnCount}</td></tr>
              {/each}
            </tbody>
          </table>
        </div>
      </div>
    {/if}
  </div>
</div>

<style>
  .two-col {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 320px), 1fr));
    gap: 1rem;
    min-width: 0;
  }
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
  .hub-card h4 {
    margin: 0.35rem 0 0.25rem;
    color: var(--vpro-navy);
    font-size: 0.86rem;
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
  .form-stack {
    display: grid;
    gap: 0.6rem;
    min-width: 0;
  }
  .form-row label,
  .form-stack label,
  .field-label-block {
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
  select,
  textarea {
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
  textarea {
    font-family: var(--font-mono, monospace);
    font-size: 0.78rem;
    width: 100%;
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
  .sub-box {
    border: 1px solid var(--vpro-border);
    border-left: 3px solid var(--vpro-gold);
    padding: 0.65rem;
    border-radius: 4px;
    display: grid;
    gap: 0.5rem;
    min-width: 0;
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
  .table-scroll {
    overflow-x: auto;
    max-width: 100%;
  }
  .compact-table {
    width: 100%;
    min-width: 0;
    border-collapse: collapse;
    font-size: 0.78rem;
  }
  .compact-table th,
  .compact-table td {
    padding: 0.35rem 0.5rem;
    border-bottom: 1px solid var(--vpro-border);
    white-space: normal;
    text-align: left;
  }
  .mono {
    font-family: var(--vpro-font-mono, var(--font-mono, monospace));
    font-variant-numeric: tabular-nums;
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
