<script lang="ts">
  import DatasheetFindReplaceDrawer from './DatasheetFindReplaceDrawer.svelte';
  import DatasheetInsertDrawer from './DatasheetInsertDrawer.svelte';
  import type {
    DatasheetBackendPort,
    DatasheetColumnMeta,
    DatasheetFindReplacePreview,
    DatasheetPage,
  } from './universalDatasheetGrid';

  let {
    contextId,
    page = null,
    orderedColumns,
    editableColumns,
    port,
    activeTableReadOnly = false,
    activeChildTableEditable = false,
    errorMessage = '',
    pendingDeleteRow = null,
    deleteBusy = false,
    insertSeedPlot = '',
    insertDrawerOpen = $bindable(false),
    insertBusy = $bindable(false),
    findDrawerOpen = false,
    findColumn = $bindable(''),
    findText = $bindable(''),
    replaceText = $bindable(''),
    findMatchCase = $bindable(false),
    findExactCell = $bindable(false),
    findPreview = null,
    findBusy = false,
    saving = false,
    onconfirmdelete,
    oncanceldelete,
    oninserterror,
    oninserted,
    onrunfindpreview,
    onapplyfindreplace,
  }: {
    contextId: string;
    page: DatasheetPage | null;
    orderedColumns: Array<{ meta: DatasheetColumnMeta; originalIndex: number }>;
    editableColumns: DatasheetColumnMeta[];
    port: DatasheetBackendPort;
    activeTableReadOnly?: boolean;
    activeChildTableEditable?: boolean;
    errorMessage?: string;
    pendingDeleteRow?: { rowId: string; plotNumber: string; id: number | null } | null;
    deleteBusy?: boolean;
    insertSeedPlot?: string;
    insertDrawerOpen?: boolean;
    insertBusy?: boolean;
    findDrawerOpen?: boolean;
    findColumn?: string;
    findText?: string;
    replaceText?: string;
    findMatchCase?: boolean;
    findExactCell?: boolean;
    findPreview?: DatasheetFindReplacePreview | null;
    findBusy?: boolean;
    saving?: boolean;
    onconfirmdelete: () => void;
    oncanceldelete: () => void;
    oninserterror: (msg: string) => void;
    oninserted: (banner: string) => Promise<void>;
    onrunfindpreview: () => void;
    onapplyfindreplace: () => void;
  } = $props();
</script>

{#if activeTableReadOnly && page}
  <p role="status" class="vpro-ds-status" data-readonly-table-banner>
    Read-only system table view (<code>{page.tableName}</code>): inspection, sorting, filtering, and copy are enabled;
    edits are disabled.
  </p>
{/if}

{#if errorMessage}
  <p role="alert" class="vpro-ds-alert">{errorMessage}</p>
{/if}

{#if pendingDeleteRow && page}
  <div class="vpro-ds-confirm-bar" role="alertdialog" aria-label="Confirm Child Row Deletion" data-delete-confirm-bar>
    <span>
      Delete row <code>{pendingDeleteRow.rowId}</code>
      {#if pendingDeleteRow.id !== null}(ID {pendingDeleteRow.id}){/if}
      for plot <strong>{pendingDeleteRow.plotNumber || '(unknown)'}</strong> from <code>{page.tableName}</code>? This
      logs a permanent delete audit entry.
    </span>
    <div class="vpro-ds-toolbar-actions">
      <button
        type="button"
        class="vpro-btn-danger"
        data-confirm-delete-row
        disabled={deleteBusy}
        onclick={onconfirmdelete}
      >
        {deleteBusy ? 'Deleting...' : 'Confirm Delete Row'}
      </button>
      <button type="button" class="vpro-btn-secondary" disabled={deleteBusy} onclick={oncanceldelete}> Cancel </button>
    </div>
  </div>
{/if}

{#if insertDrawerOpen && page && activeChildTableEditable}
  <DatasheetInsertDrawer
    {contextId}
    {page}
    {orderedColumns}
    seedPlotNumber={insertSeedPlot}
    {port}
    {activeChildTableEditable}
    bind:insertDrawerOpen
    bind:insertBusy
    onError={oninserterror}
    onInserted={oninserted}
  />
{/if}

{#if findDrawerOpen && page}
  <DatasheetFindReplaceDrawer
    {page}
    {editableColumns}
    bind:findColumn
    bind:findText
    bind:replaceText
    bind:findMatchCase
    bind:findExactCell
    {findPreview}
    {findBusy}
    {saving}
    onRunPreview={onrunfindpreview}
    onApplyValid={onapplyfindreplace}
  />
{/if}
