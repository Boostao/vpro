<script lang="ts">
  import type {
    FileDialogFilter,
    LumpTableSummary,
    TurboVegExportOutcome,
    TurboVegImportOutcome,
  } from './interchangeHub';

  let {
    contextId,
    busy,
    operationHeld,
    tvExportFormat = $bindable<'xml' | 'sqlite'>('sqlite'),
    tvExportPath = $bindable(''),
    selectedLumpKey,
    discoveredLumpTables,
    lumpOptionValue,
    formatLumpOptionLabel,
    tvExportOutcome,
    layerCrosswalk,
    tvImportPath = $bindable(''),
    tvImportFormat = $bindable<'xml' | 'sqlite' | ''>(''),
    tvImportTarget = $bindable(''),
    tvImportDestPath = $bindable(''),
    tvImportActivate = $bindable(false),
    tvResolveSynonyms = $bindable(false),
    tvImportOutcome,
    onApplyLumpOption,
    onBrowseExternalLumpDb,
    onPickFilePath,
    onRunTurboVegExport,
    onValidateXmlSnippet,
    onRunTurboVegImport,
  }: {
    contextId: string;
    busy: boolean;
    operationHeld: boolean;
    tvExportFormat?: 'xml' | 'sqlite';
    tvExportPath?: string;
    selectedLumpKey: string;
    discoveredLumpTables: LumpTableSummary[];
    lumpOptionValue: (item: LumpTableSummary, list?: readonly LumpTableSummary[]) => string;
    formatLumpOptionLabel: (item: LumpTableSummary) => string;
    tvExportOutcome: TurboVegExportOutcome | null;
    layerCrosswalk: ReadonlyArray<{ vproLayers: string; tvGroup: string; description: string }>;
    tvImportPath?: string;
    tvImportFormat?: 'xml' | 'sqlite' | '';
    tvImportTarget?: string;
    tvImportDestPath?: string;
    tvImportActivate?: boolean;
    tvResolveSynonyms?: boolean;
    tvImportOutcome: TurboVegImportOutcome | null;
    onApplyLumpOption: (optionValue: string) => void;
    onBrowseExternalLumpDb: () => void;
    onPickFilePath: (
      mode: 'open' | 'save',
      title: string,
      defaultFilename: string,
      filters: FileDialogFilter[],
      assign: (chosen: string) => void | Promise<void>
    ) => Promise<void>;
    onRunTurboVegExport: () => Promise<void>;
    onValidateXmlSnippet: (xmlText: string) => Promise<number | null>;
    onRunTurboVegImport: () => Promise<void>;
  } = $props();

  let tvXmlSnippet = $state('');
  let tvXmlSnippetCount = $state<number | null>(null);

  async function handleCheckXml() {
    tvXmlSnippetCount = await onValidateXmlSnippet(tvXmlSnippet);
  }
</script>

<div class="two-col">
  <div class="hub-card">
    <h3>Export TurboVeg 3 (31-Table .sqlite) or Standard XML (&lt;Plot_package&gt;)</h3>
    <div class="form-stack">
      <label>
        <span>Target Format</span>
        <select bind:value={tvExportFormat} disabled={busy || operationHeld}>
          <option value="sqlite">TurboVeg 3 Official 31-Table SQLite (.sqlite)</option>
          <option value="xml">TurboVeg Standard XML (&lt;Plot_package&gt; for TV2 / TV3 / JUICE / vegdata)</option>
        </select>
      </label>
      <label>
        <span>Destination File Path</span>
        <div class="input-with-browse">
          <input
            type="text"
            class="grow"
            bind:value={tvExportPath}
            placeholder="/path/to/export.sqlite or .xml"
            disabled={busy || operationHeld}
          />
          <button
            type="button"
            class="btn-secondary"
            data-save-tv-export
            disabled={busy || operationHeld}
            onclick={() =>
              onPickFilePath(
                'save',
                'Save TurboVeg Export',
                tvExportFormat === 'xml' ? 'turboveg_export.xml' : 'turboveg_export.sqlite',
                [{ DisplayName: 'TurboVeg (*.sqlite, *.xml)', Pattern: '*.sqlite;*.xml' }],
                (p) => {
                  tvExportPath = p;
                }
              )}
          >
            Save As...
          </button>
        </div>
      </label>
      <label>
        <span>Optional *_Lump Table</span>
        <div class="input-with-browse">
          <select
            class="grow"
            data-lump-select="turboveg"
            value={selectedLumpKey}
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
            data-browse-lump-db="turboveg"
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
        onclick={onRunTurboVegExport}
      >
        Export TurboVeg
      </button>
    </div>

    {#if tvExportOutcome}
      <div class="receipt-box success">
        <strong>
          Exported {tvExportOutcome.plotCount} plots ({tvExportOutcome.observationCount} abundances,
          {tvExportOutcome.speciesCount} taxa)
        </strong>
        <span>File: <code>{tvExportOutcome.path}</code></span>
      </div>
    {/if}

    <h4>Canonical VPro &lt;-&gt; TurboVeg Layer Crosswalk (0..10 + UDF Sublayer Tags)</h4>
    <div class="table-scroll">
      <table class="compact-table">
        <thead>
          <tr><th>VPro Columns</th><th>TurboVeg Layer</th><th>Crosswalk &amp; UDF Provenance</th></tr>
        </thead>
        <tbody>
          {#each layerCrosswalk as cw (cw.tvGroup)}
            <tr>
              <td class="mono">{cw.vproLayers}</td>
              <td><strong>{cw.tvGroup}</strong></td>
              <td>{cw.description}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  </div>

  <div class="hub-card">
    <h3>Import TurboVeg (.sqlite or &lt;Plot_package&gt; .xml) into VPro</h3>
    <div class="form-stack">
      <label>
        <span>Source TurboVeg File (.sqlite or .xml)</span>
        <div class="input-with-browse">
          <input
            type="text"
            class="grow"
            bind:value={tvImportPath}
            placeholder="/path/to/turboveg.sqlite or .xml"
            disabled={busy || operationHeld}
          />
          <button
            type="button"
            class="btn-secondary"
            data-browse-tv-import
            disabled={busy || operationHeld}
            onclick={() =>
              onPickFilePath(
                'open',
                'Choose TurboVeg File',
                '',
                [{ DisplayName: 'TurboVeg (*.sqlite, *.xml)', Pattern: '*.sqlite;*.xml' }],
                (p) => {
                  tvImportPath = p;
                }
              )}
          >
            Browse...
          </button>
        </div>
      </label>
      <label>
        <span>Format Override</span>
        <select bind:value={tvImportFormat} disabled={busy || operationHeld}>
          <option value="">Auto-detect from extension</option>
          <option value="sqlite">TurboVeg 3 31-Table SQLite (.sqlite)</option>
          <option value="xml">TurboVeg Standard XML (&lt;Plot_package&gt; .xml)</option>
        </select>
      </label>
      <label>
        <span>Target VPro Project Name</span>
        <input
          type="text"
          bind:value={tvImportTarget}
          placeholder="e.g. Phytosoc2026"
          disabled={busy || operationHeld}
        />
      </label>
      <label>
        <span>Destination .db Path (optional)</span>
        <div class="input-with-browse">
          <input
            type="text"
            class="grow"
            bind:value={tvImportDestPath}
            placeholder="Defaults to projects/<Target>.db"
            disabled={busy || operationHeld}
          />
          <button
            type="button"
            class="btn-secondary"
            data-save-tv-dest
            disabled={busy || operationHeld}
            onclick={() =>
              onPickFilePath(
                'save',
                'Choose VPro Project Destination',
                `${tvImportTarget.trim() || 'project'}.db`,
                [{ DisplayName: 'VPro Project (*.db)', Pattern: '*.db' }],
                (p) => {
                  tvImportDestPath = p;
                }
              )}
          >
            Save As...
          </button>
        </div>
      </label>
      <label class="check-inline">
        <input type="checkbox" bind:checked={tvResolveSynonyms} disabled={busy || operationHeld} />
        <span>Resolve VPro OldCode synonyms (USysAllSpecs Codetype='S')</span>
      </label>
      <label class="check-inline">
        <input type="checkbox" bind:checked={tvImportActivate} disabled={busy || operationHeld} />
        <span>Activate imported project</span>
      </label>
      <button
        type="button"
        class="btn-primary"
        disabled={busy || operationHeld || !contextId}
        onclick={onRunTurboVegImport}
      >
        Import TurboVeg Project
      </button>
    </div>

    <details class="xml-check-box">
      <summary>Pre-validate pasted XML snippet</summary>
      <textarea
        aria-label="TurboVeg XML snippet to validate"
        bind:value={tvXmlSnippet}
        rows={3}
        placeholder="<Plot_package><Plots><Plot releve_nr=&quot;1&quot;>..."
        disabled={busy || operationHeld}></textarea>
      <button type="button" class="btn-secondary" disabled={busy || operationHeld} onclick={handleCheckXml}>
        Validate XML Snippet
      </button>
      {#if tvXmlSnippetCount !== null}
        <p class="ok-text">Valid UTF-8 XML ({tvXmlSnippetCount} plot element(s) detected).</p>
      {/if}
    </details>

    {#if tvImportOutcome}
      <div class="receipt-box success">
        <strong>
          Imported {tvImportOutcome.plotCount} plots ({tvImportOutcome.observationCount} observations) into
          {tvImportOutcome.targetProject}
        </strong>
        <span>Destination: <code>{tvImportOutcome.destinationPath}</code></span>
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
  .form-stack {
    display: grid;
    gap: 0.6rem;
    min-width: 0;
  }
  .form-stack label {
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
  .xml-check-box {
    font-size: 0.8rem;
    border-top: 1px solid var(--vpro-border);
    padding-top: 0.5rem;
  }
  .ok-text {
    color: var(--vpro-success);
    margin: 0.3rem 0 0;
    font-weight: 600;
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
