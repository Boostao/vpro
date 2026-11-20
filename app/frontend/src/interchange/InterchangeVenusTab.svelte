<script lang="ts">
  import type { FileDialogFilter, VenusImportResult, VenusSourceInspection } from './interchangeHub';

  let {
    contextId,
    busy,
    operationHeld,
    venusSourcePath = $bindable(''),
    venusInspection,
    venusSelectedProject = $bindable(''),
    venusTargetProject = $bindable(''),
    venusDestinationPath = $bindable(''),
    venusActivate = $bindable(false),
    venusResult,
    onPickFilePath,
    onInspectVenus,
    onRunVenusImport,
  }: {
    contextId: string;
    busy: boolean;
    operationHeld: boolean;
    venusSourcePath?: string;
    venusInspection: VenusSourceInspection | null;
    venusSelectedProject?: string;
    venusTargetProject?: string;
    venusDestinationPath?: string;
    venusActivate?: boolean;
    venusResult: VenusImportResult | null;
    onPickFilePath: (
      mode: 'open' | 'save',
      title: string,
      defaultFilename: string,
      filters: FileDialogFilter[],
      assign: (chosen: string) => void | Promise<void>
    ) => Promise<void>;
    onInspectVenus: () => Promise<void>;
    onRunVenusImport: () => Promise<void>;
  } = $props();
</script>

<div class="hub-card">
  <h3>VENUS 5.0 (.mdb &amp; .xml) Project Importer</h3>
  <p class="desc">
    Pivots normalized VENUS 5.0 vegetation layers, site/soil attributes, and organic/mineral horizons into a verified
    VPro project (.db).
  </p>
  <div class="form-row">
    <label class="grow">
      <span>VENUS Source File (.mdb, .accdb, or .xml)</span>
      <div class="input-with-browse">
        <input
          type="text"
          class="grow"
          bind:value={venusSourcePath}
          placeholder="/path/to/VenusProject.mdb or .xml"
          disabled={busy || operationHeld}
        />
        <button
          type="button"
          class="btn-secondary"
          data-browse-venus-source
          disabled={busy || operationHeld}
          onclick={() =>
            onPickFilePath(
              'open',
              'Choose VENUS Source File',
              '',
              [{ DisplayName: 'VENUS Files (*.mdb, *.accdb, *.xml)', Pattern: '*.mdb;*.accdb;*.xml' }],
              (p) => {
                venusSourcePath = p;
              }
            )}
        >
          Browse...
        </button>
      </div>
    </label>
    <button type="button" class="btn-secondary" disabled={busy || operationHeld || !contextId} onclick={onInspectVenus}>
      Inspect Source
    </button>
  </div>

  {#if venusInspection}
    <div class="receipt-box">
      <p>
        <strong>Detected:</strong> VENUS {venusInspection.venusVersion} ({venusInspection.sourceFormat.toUpperCase()}) |
        <strong>SHA-256:</strong> <code>{venusInspection.sourceSha256.slice(0, 16)}...</code>
      </p>
      <div class="form-row">
        <label>
          <span>Source VENUS Project</span>
          <select bind:value={venusSelectedProject} disabled={busy || operationHeld}>
            {#each venusInspection.projects as cand (cand.projectName)}
              <option value={cand.projectName}>{cand.projectName} ({cand.plotCount} plots)</option>
            {/each}
          </select>
        </label>
        <label>
          <span>Target VPro Project Name</span>
          <input type="text" bind:value={venusTargetProject} disabled={busy || operationHeld} />
        </label>
        <label class="grow">
          <span>Destination .db Path</span>
          <input type="text" bind:value={venusDestinationPath} disabled={busy || operationHeld} />
        </label>
        <label class="check-inline">
          <input type="checkbox" bind:checked={venusActivate} disabled={busy || operationHeld} />
          <span>Open after import</span>
        </label>
        <button type="button" class="btn-primary" disabled={busy || operationHeld} onclick={onRunVenusImport}>
          Import into VPro
        </button>
      </div>
    </div>
  {/if}

  {#if venusResult}
    <div class="receipt-box success">
      <strong>Imported {venusResult.plotCount} plots into {venusResult.targetProject}</strong>
      <span>
        Veg rows: {venusResult.vegRowCount} | Humus: {venusResult.humusRowCount} | Mineral:
        {venusResult.mineralRowCount}
      </span>
      <span>Saved to: <code>{venusResult.destinationPath}</code></span>
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
