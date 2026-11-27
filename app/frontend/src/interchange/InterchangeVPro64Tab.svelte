<script lang="ts">
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import type { VPro64ExportOutcome } from './interchangeHub';

  let {
    contextId,
    busy,
    operationHeld,
    vpro64DestPath = $bindable(''),
    vpro64TargetProject = $bindable(''),
    vpro64IncludeActiveSU = $bindable(true),
    vpro64IncludeHierarchy = $bindable(true),
    vpro64IncludeMensuration = $bindable(true),
    vpro64IncludeCompanions = $bindable(true),
    vpro64IncludeVBABridge = $bindable(true),
    vpro64Outcome,
    onChooseVPro64Dest,
    onRunVPro64Export,
  }: {
    contextId: string;
    busy: boolean;
    operationHeld: boolean;
    vpro64DestPath?: string;
    vpro64TargetProject?: string;
    vpro64IncludeActiveSU?: boolean;
    vpro64IncludeHierarchy?: boolean;
    vpro64IncludeMensuration?: boolean;
    vpro64IncludeCompanions?: boolean;
    vpro64IncludeVBABridge?: boolean;
    vpro64Outcome: VPro64ExportOutcome | null;
    onChooseVPro64Dest: () => Promise<void>;
    onRunVPro64Export: () => Promise<void>;
  } = $props();
</script>

<div class="hub-card" data-interchange-vpro64-tab>
  <h3>VPro64 Database Export (.db)</h3>
  <p class="desc">
    Export the active project into a clean, self-contained database package ready for direct import into VPro64
    Microsoft Access via the SQLite ODBC module.
  </p>

  <div class="form-row">
    <label>
      <span>Target Project Name (Optional)</span>
      <input
        type="text"
        data-vpro64-target-project
        bind:value={vpro64TargetProject}
        placeholder="Defaults to active project name"
        disabled={busy || operationHeld}
      />
    </label>

    {#if !IS_WEB_READONLY}
      <label class="grow">
        <span>Destination .db File</span>
        <div class="input-with-browse">
          <input
            type="text"
            class="grow"
            data-vpro64-dest-path
            bind:value={vpro64DestPath}
            placeholder="/path/to/Project_VPro64.db"
            disabled={busy || operationHeld}
          />
          <button
            type="button"
            class="btn-secondary"
            data-browse-vpro64-dest
            disabled={busy || operationHeld}
            onclick={() => void onChooseVPro64Dest()}
          >
            Browse...
          </button>
        </div>
      </label>
    {/if}
  </div>

  <div class="checks-row" data-vpro64-options>
    <label class="check-inline">
      <input
        type="checkbox"
        data-vpro64-include-su
        bind:checked={vpro64IncludeActiveSU}
        disabled={busy || operationHeld}
      />
      <span>Include Active SU</span>
    </label>
    <label class="check-inline">
      <input
        type="checkbox"
        data-vpro64-include-hierarchy
        bind:checked={vpro64IncludeHierarchy}
        disabled={busy || operationHeld}
      />
      <span>Include Hierarchy</span>
    </label>
    <label class="check-inline">
      <input
        type="checkbox"
        data-vpro64-include-mensuration
        bind:checked={vpro64IncludeMensuration}
        disabled={busy || operationHeld}
      />
      <span>Include Mensuration (<code>_TreePlot</code> / <code>_Trees</code>)</span>
    </label>
    <label class="check-inline">
      <input
        type="checkbox"
        data-vpro64-include-companions
        bind:checked={vpro64IncludeCompanions}
        disabled={busy || operationHeld}
      />
      <span>Include Companions</span>
    </label>
    {#if !IS_WEB_READONLY}
      <label class="check-inline">
        <input
          type="checkbox"
          data-vpro64-include-bridge
          bind:checked={vpro64IncludeVBABridge}
          disabled={busy || operationHeld}
        />
        <span>Include VPro64 VBA importer (<code>V7mdlImportSQLite.bas</code>) &amp; setup guide</span>
      </label>
    {/if}
  </div>

  <div class="action-row">
    <button
      type="button"
      class="btn-primary"
      data-run-vpro64-export
      disabled={busy || operationHeld || !contextId}
      onclick={() => void onRunVPro64Export()}
    >
      {#if busy}
        {IS_WEB_READONLY ? 'Preparing VPro64 Download...' : 'Exporting VPro64 Database...'}
      {:else}
        {IS_WEB_READONLY ? 'Download VPro64 Database (.db)' : 'Export VPro64 Database (.db)'}
      {/if}
    </button>
  </div>

  <p class="odbc-note" data-vpro64-odbc-note>
    {#if IS_WEB_READONLY}
      The downloaded <code>.db</code> file uses standard single-file formatting with Access-compatible checkboxes and
      exact plot numbers. To import it into legacy VPro64 Microsoft Access, download
      <code>vpro64-sqlite-bridge.zip</code> from the VPro downloads page and install the 64-bit SQLite3 ODBC Driver.
    {:else}
      The exported <code>.db</code> file uses standard single-file formatting with Access-compatible checkboxes and
      exact plot numbers. When the VBA importer option is checked, VPro also saves <code>V7mdlImportSQLite.bas</code>
      and <code>VPro64-Import-README.txt</code> beside your export so you can import directly into VPro64 Microsoft
      Access offline.
    {/if}
  </p>

  {#if vpro64Outcome}
    <div class="receipt-box success" data-vpro64-export-receipt>
      <strong>
        {IS_WEB_READONLY ? 'Downloaded' : 'Exported'} {vpro64Outcome.plotCount} plots for {vpro64Outcome.targetProject}
      </strong>
      <span>
        {#if vpro64Outcome.includedSU}Active SU: <code>{vpro64Outcome.includedSU}</code> | {/if}
        {#if vpro64Outcome.includedHierarchy}Hierarchy: <code>{vpro64Outcome.includedHierarchy}</code> | {/if}
        Mensuration: {vpro64Outcome.includedMensuration ? 'Included' : 'Not included'} | Size:
        {(vpro64Outcome.bytes / 1024).toFixed(1)} KB
      </span>
      {#if !IS_WEB_READONLY}
        <span>
          Saved to: <code>{vpro64Outcome.destinationPath}</code> | SHA-256:
          <code>{vpro64Outcome.sha256.slice(0, 16)}...</code>
        </span>
        {#if vpro64Outcome.bridgeModulePath}
          <span data-vpro64-bridge-receipt>
            VPro64 VBA bridge saved: <code>{vpro64Outcome.bridgeModulePath}</code>
            {#if vpro64Outcome.bridgeReadmePath}
              &amp; <code>{vpro64Outcome.bridgeReadmePath}</code>
            {/if}
          </span>
        {/if}
      {/if}
      {#if vpro64Outcome.tables && vpro64Outcome.tables.length > 0}
        <div class="table-summary">
          {#each vpro64Outcome.tables as tbl (tbl.targetTable)}
            <span class="table-chip"><code>{tbl.targetTable}</code> ({tbl.rowCount})</span>
          {/each}
        </div>
      {/if}
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
  .odbc-note {
    margin: 0;
    padding: 0.55rem 0.75rem;
    background: var(--vpro-canvas);
    border-left: 3px solid var(--vpro-gold);
    border-radius: 3px;
    font-size: 0.8rem;
    color: var(--vpro-ink-secondary);
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
    flex: 1 1 220px;
    min-width: 0;
  }
  .checks-row {
    display: flex;
    flex-wrap: wrap;
    gap: 0.85rem;
    padding: 0.5rem 0.7rem;
    background: var(--vpro-canvas);
    border: 1px solid var(--vpro-border);
    border-radius: 4px;
  }
  .check-inline {
    display: inline-flex;
    flex-direction: row;
    align-items: center;
    gap: 0.4rem;
    font-size: 0.82rem;
    color: var(--vpro-ink);
  }
  .action-row {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
  }
  input:not([type='checkbox']) {
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
    cursor: pointer;
  }
  .btn-secondary {
    background: var(--vpro-surface);
    color: var(--vpro-navy);
    border: 1px solid var(--vpro-navy);
    border-radius: 4px;
    padding: 0.48rem 0.9rem;
    font-weight: 600;
    font-size: 0.83rem;
    cursor: pointer;
  }
  button:disabled {
    opacity: 0.55;
    cursor: not-allowed;
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
  .table-summary {
    display: flex;
    flex-wrap: wrap;
    gap: 0.35rem;
    margin-top: 0.2rem;
  }
  .table-chip {
    background: var(--vpro-surface);
    border: 1px solid var(--vpro-border);
    border-radius: 3px;
    padding: 0.12rem 0.4rem;
    font-size: 0.76rem;
  }
  @media (pointer: coarse) {
    .btn-primary,
    .btn-secondary,
    input:not([type='checkbox']) {
      min-height: 44px;
    }
  }
</style>
