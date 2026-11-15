<script lang="ts">
  import { onDestroy, onMount, untrack } from 'svelte';
  import { ReadRequests } from '../shared/readRequests';
  import {
    cellsSemanticallyEqual, computeNextGridCell, computeVirtualWindow, defaultDatasheetBackendPort,
    formatCellForEditor, formatTSVRange, isColumnEditable, isEditableChildTable,
    isReadOnlyDatasheetTable, normalizeGridRange, parseAndValidateCellInput, parseTSVClipboard,
    shouldNavigateOnArrowKey, toggleMultiColumnSort,
    type DatasheetBackendPort, type DatasheetCellEdit, type DatasheetColumnMeta, type DatasheetFilterSpec,
    type DatasheetFindReplacePreview, type DatasheetPage, type DatasheetSortSpec,
    type DatasheetTableInfo, type DatasheetTableKey, type GridSelectionRange,
  } from './universalDatasheetGrid';
  import DatasheetFindReplaceDrawer from './DatasheetFindReplaceDrawer.svelte';
  import DatasheetHeader from './DatasheetHeader.svelte';
  import DatasheetInsertDrawer from './DatasheetInsertDrawer.svelte';
  import DatasheetVirtualTable from './DatasheetVirtualTable.svelte';

  interface Props {
    contextId: string;
    project?: string;
    su?: string;
    hierarchy?: string;
    initialTableKey?: DatasheetTableKey;
    port?: DatasheetBackendPort;
    onBusyChange?: (busy: boolean) => void;
    onDirtyChange?: (dirty: boolean) => void;
    onOpenPlot?: (plotNumber: string) => void;
  }

  let {
    contextId, project = '', su = 'None', hierarchy = 'None', initialTableKey = 'Env',
    port = defaultDatasheetBackendPort, onBusyChange, onDirtyChange,
    onOpenPlot,
  }: Props = $props();

  const reads = new ReadRequests();
  const ROW_HEIGHT = 34;

  let tables = $state.raw<DatasheetTableInfo[]>([]);
  let activeTableKey = $state<DatasheetTableKey>(untrack(() => initialTableKey));
  let page = $state.raw<DatasheetPage | null>(null);
  let pageSize = $state(250);
  let offset = $state(0);
  let sortSpecs = $state<DatasheetSortSpec[]>([]);
  let columnFilters = $state<Record<string, string>>({});
  let globalSearch = $state('');
  let scopeToActiveSU = $state(false);

  interface CellDraft {
    rowId: string;
    column: string;
    rawText: string;
    before: DatasheetCellEdit['before'];
    after: DatasheetCellEdit['after'] | null;
    error: string;
  }
  let drafts = $state<Record<string, CellDraft>>({});
  let activeCell = $state<{ row: number; col: number } | null>(null);
  let selectionAnchor = $state<{ row: number; col: number } | null>(null);
  let selectionRange = $state<GridSelectionRange | null>(null);
  let isMouseSelecting = $state(false);

  let insertDrawerOpen = $state(false);
  let insertSeedPlot = $state('');
  let insertBusy = $state(false);
  let pendingDeleteRow = $state<{ rowId: string; plotNumber: string; id: number | null } | null>(null);
  let deleteBusy = $state(false);

  let scrollTop = $state(0);
  let viewportHeight = $state(520);
  let viewportEl = $state<HTMLDivElement | null>(null);
  let busy = $state(false);
  let saving = $state(false);
  let errorMessage = $state('');
  let statusBanner = $state('');

  let findDrawerOpen = $state(false);
  let findColumn = $state('');
  let findText = $state('');
  let replaceText = $state('');
  let findMatchCase = $state(false);
  let findExactCell = $state(false);
  let findPreview = $state.raw<DatasheetFindReplacePreview | null>(null);
  let findBusy = $state(false);
  let generation = 0;

  const orderedColumns = $derived.by(() => {
    if (!page) return [] as Array<{ meta: DatasheetColumnMeta; originalIndex: number }>;
    const pinned: Array<{ meta: DatasheetColumnMeta; originalIndex: number }> = [];
    const rest: Array<{ meta: DatasheetColumnMeta; originalIndex: number }> = [];
    page.columns.forEach((meta, idx) => (meta.pinned ? pinned : rest).push({ meta, originalIndex: idx }));
    return [...pinned, ...rest];
  });
  const virtualSlice = $derived(computeVirtualWindow(scrollTop, viewportHeight, ROW_HEIGHT, page?.rows.length ?? 0, 8));
  const visibleRows = $derived(page ? page.rows.slice(virtualSlice.startIndex, virtualSlice.endIndex) : []);
  const draftEntries = $derived(Object.values(drafts));
  const invalidDraftCount = $derived(draftEntries.filter(d => d.error !== '').length);
  const validEditCount = $derived(draftEntries.filter(d => d.error === '' && d.after !== null).length);
  const activeTableReadOnly = $derived(
    page ? isReadOnlyDatasheetTable(page.tableKey, page.readOnly) : isReadOnlyDatasheetTable(activeTableKey)
  );
  const activeChildTableEditable = $derived(!!page && !activeTableReadOnly && isEditableChildTable(page.tableKey));
  const editableColumns = $derived(page ? page.columns.filter(c => isColumnEditable(page!.tableKey, c, page!.canEditMaster)) : []);

  $effect(() => {
    void busy; void saving; void findBusy; void insertBusy; void deleteBusy; void invalidDraftCount; void draftEntries.length;
    onBusyChange?.(busy || saving || findBusy || insertBusy || deleteBusy || draftEntries.length > 0);
    onDirtyChange?.(!busy && !saving && !findBusy && !insertBusy && !deleteBusy && draftEntries.length > 0);
  });

  const draftKey = (rowId: string, column: string) => `${rowId}::${column}`;

  function buildActiveFilterSpecs(): DatasheetFilterSpec[] {
    const out: DatasheetFilterSpec[] = [];
    for (const [col, val] of Object.entries(columnFilters)) {
      const trimmed = val.trim();
      if (!trimmed) continue;
      if (trimmed === '=NULL') out.push({ column: col, op: 'is_null', value: '' });
      else if (trimmed === '!=NULL') out.push({ column: col, op: 'not_null', value: '' });
      else if (trimmed.startsWith('=')) out.push({ column: col, op: 'eq', value: trimmed.slice(1) });
      else out.push({ column: col, op: 'contains', value: trimmed });
    }
    return out;
  }

  function makePageReq(tableKey: DatasheetTableKey, nextOffset: number) {
    return {
      tableKey, offset: Math.max(0, nextOffset), limit: pageSize,
      sort: $state.snapshot(sortSpecs), filters: buildActiveFilterSpecs(), globalSearch, scopeToActiveSU,
    };
  }

  async function refreshTablesAndLoad(targetKey: DatasheetTableKey = activeTableKey, nextOffset = 0, options?: { preserveStatus?: boolean }) {
    if (!contextId) return;
    const reqGen = ++generation;
    reads.cancelAll();
    busy = true; errorMessage = '';
    try {
      const listed = await reads.track((port.listAllTables ?? port.listTables)(contextId));
      if (reqGen !== generation) return;
      tables = listed ?? [];
      const chosen = tables.find(t => t.key === targetKey);
      if (chosen && !chosen.available) {
        page = null;
        statusBanner = chosen.unavailableReason ?? `${chosen.key} is not available in this context.`;
        return;
      }
      const loaded = await reads.track(port.getPage(contextId, makePageReq(targetKey, nextOffset)));
      if (reqGen !== generation) return;
      page = loaded; offset = loaded.offset;
      if (!findColumn && loaded.columns.length > 0) {
        const firstEditable = loaded.columns.find(c => !c.pinned && isColumnEditable(loaded.tableKey, c, loaded.canEditMaster)) ?? loaded.columns[0];
        findColumn = firstEditable.name;
      }
      if (!options?.preserveStatus) statusBanner = '';
    } catch (err) {
      if (reqGen === generation) errorMessage = String(err);
    } finally {
      if (reqGen === generation) busy = false;
    }
  }

  async function loadPageOnly(nextOffset = offset) {
    if (!contextId) return;
    const reqGen = ++generation;
    reads.cancelAll();
    busy = true; errorMessage = '';
    try {
      const loaded = await reads.track(port.getPage(contextId, makePageReq(activeTableKey, nextOffset)));
      if (reqGen !== generation) return;
      page = loaded; offset = loaded.offset;
    } catch (err) {
      if (reqGen === generation) errorMessage = String(err);
    } finally {
      if (reqGen === generation) busy = false;
    }
  }

  function selectTable(key: DatasheetTableKey) {
    if (draftEntries.length > 0) { errorMessage = 'Save or discard unsaved cell edits before switching datasheet tables.'; return; }
    activeTableKey = key; offset = 0; sortSpecs = []; columnFilters = {}; globalSearch = '';
    activeCell = null; selectionAnchor = null; selectionRange = null; isMouseSelecting = false;
    insertDrawerOpen = false; pendingDeleteRow = null; findPreview = null; findColumn = ''; scrollTop = 0;
    void refreshTablesAndLoad(key, 0);
  }

  function setCellDraft(rowIndex: number, displayColIndex: number, rawValue: string) {
    if (!page) return;
    const row = page.rows[rowIndex], colEntry = orderedColumns[displayColIndex];
    if (!row || !colEntry) return;
    const colMeta = colEntry.meta, originalCell = row.cells[colEntry.originalIndex];
    const key = draftKey(row.rowId, colMeta.name);
    const parsed = parseAndValidateCellInput(page.tableKey, colMeta, rawValue, page.canEditMaster);
    if (!parsed.error && parsed.cell && cellsSemanticallyEqual(originalCell, parsed.cell, colMeta)) {
      const next = { ...drafts }; delete next[key]; drafts = next; return;
    }
    drafts = {
      ...drafts,
      [key]: { rowId: row.rowId, column: colMeta.name, rawText: rawValue, before: structuredClone($state.snapshot(originalCell)), after: parsed.cell, error: parsed.error },
    };
  }

  function discardDrafts() {
    drafts = {}; errorMessage = ''; statusBanner = 'Discarded unsaved datasheet edits.';
  }

  async function saveDrafts() {
    if (!page || saving || validEditCount === 0) return;
    if (invalidDraftCount > 0) { errorMessage = `Resolve ${invalidDraftCount} invalid cell(s) before saving.`; return; }
    saving = true; errorMessage = '';
    try {
      const edits: DatasheetCellEdit[] = draftEntries
        .filter(d => d.after !== null)
        .map(d => ({ rowId: d.rowId, column: d.column, before: $state.snapshot(d.before), after: $state.snapshot(d.after!) }));
      const res = await port.applyEdits(contextId, { tableKey: page.tableKey, edits });
      drafts = {};
      statusBanner = `Saved ${res.updatedCells} cell(s) across ${res.updatedRows} row(s) (${res.auditRows} audit record(s)).`;
      await refreshTablesAndLoad(activeTableKey, offset, { preserveStatus: true });
    } catch (err) {
      errorMessage = `Save failed (transaction rolled back): ${String(err)}`;
    } finally {
      saving = false;
    }
  }

  function focusGridInput(rowIdx: number, colIdx: number, extendSelection = false) {
    activeCell = { row: rowIdx, col: colIdx };
    if (extendSelection && selectionAnchor) {
      selectionRange = { startRow: selectionAnchor.row, endRow: rowIdx, startCol: selectionAnchor.col, endCol: colIdx };
    } else {
      selectionAnchor = { row: rowIdx, col: colIdx };
      selectionRange = { startRow: rowIdx, endRow: rowIdx, startCol: colIdx, endCol: colIdx };
    }
    if (viewportEl) {
      const topTarget = rowIdx * ROW_HEIGHT, bottomTarget = topTarget + ROW_HEIGHT;
      if (topTarget < viewportEl.scrollTop) viewportEl.scrollTop = topTarget;
      else if (bottomTarget > viewportEl.scrollTop + viewportEl.clientHeight - 40) viewportEl.scrollTop = bottomTarget - viewportEl.clientHeight + 48;
    }
    queueMicrotask(() => {
      const el = viewportEl?.querySelector<HTMLInputElement>(`input[data-grid-row="${rowIdx}"][data-grid-col="${colIdx}"]`);
      el?.focus();
      if (!extendSelection) el?.select();
    });
  }

  function handleCellKeyDown(event: KeyboardEvent, rowIdx: number, colIdx: number) {
    if (!page) return;
    if (event.key === 'Enter' || event.key === 'Tab') {
      const next = computeNextGridCell({ row: rowIdx, col: colIdx }, event.key, event.shiftKey, page.rows.length, orderedColumns.length);
      if (next) { event.preventDefault(); focusGridInput(next.row, next.col, false); }
      return;
    }
    if (event.key === 'ArrowUp' || event.key === 'ArrowDown' || event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
      const inputEl = event.currentTarget as HTMLInputElement | null;
      if (!shouldNavigateOnArrowKey(event.key, inputEl?.selectionStart ?? null, inputEl?.selectionEnd ?? null, inputEl?.value.length ?? 0)) return;
      const next = computeNextGridCell({ row: rowIdx, col: colIdx }, event.key, event.shiftKey, page.rows.length, orderedColumns.length);
      if (next) { event.preventDefault(); focusGridInput(next.row, next.col, event.shiftKey); }
      return;
    }
    if (event.key === 'Escape') {
      const row = page.rows[rowIdx], col = orderedColumns[colIdx];
      if (row && col) {
        const key = draftKey(row.rowId, col.meta.name);
        if (key in drafts) { event.preventDefault(); const copy = { ...drafts }; delete copy[key]; drafts = copy; }
      }
    }
  }

  function handleCopySelection(event: ClipboardEvent) {
    if (!page || !selectionRange) return;
    const norm = normalizeGridRange(selectionRange);
    if (norm.startRow === norm.endRow && norm.startCol === norm.endCol) return;
    const projectedRows = page.rows.map(r => ({ rowId: r.rowId, cells: orderedColumns.map(c => r.cells[c.originalIndex]) }));
    const tsv = formatTSVRange(projectedRows, orderedColumns.map(c => c.meta), norm, (rowId, colName) => drafts[draftKey(rowId, colName)]?.rawText);
    if (event.clipboardData) {
      event.preventDefault();
      event.clipboardData.setData('text/plain', tsv);
      statusBanner = `Copied ${norm.endRow - norm.startRow + 1}x${norm.endCol - norm.startCol + 1} TSV block to clipboard.`;
    }
  }

  function handlePasteIntoCell(event: ClipboardEvent, anchorRow: number, anchorCol: number) {
    if (!page || !event.clipboardData) return;
    const text = event.clipboardData.getData('text/plain');
    if (!text.includes('\t') && !text.includes('\n')) return;
    const matrix = parseTSVClipboard(text);
    if (matrix.length === 0) return;
    event.preventDefault();
    let applied = 0;
    for (let rOff = 0; rOff < matrix.length && anchorRow + rOff < page.rows.length; rOff++) {
      for (let cOff = 0; cOff < matrix[rOff].length && anchorCol + cOff < orderedColumns.length; cOff++) {
        if (!isColumnEditable(page.tableKey, orderedColumns[anchorCol + cOff].meta, page.canEditMaster)) continue;
        setCellDraft(anchorRow + rOff, anchorCol + cOff, matrix[rOff][cOff]);
        applied++;
      }
    }
    selectionRange = {
      startRow: anchorRow, endRow: Math.min(page.rows.length - 1, anchorRow + matrix.length - 1),
      startCol: anchorCol, endCol: Math.min(orderedColumns.length - 1, anchorCol + (matrix[0]?.length ?? 1) - 1),
    };
    statusBanner = `Pasted ${applied} cell(s) from TSV clipboard. Review and click Save Edits to commit.`;
  }

  function handleHeaderSort(colName: string, event: MouseEvent) {
    sortSpecs = toggleMultiColumnSort(sortSpecs, colName, event.shiftKey);
    offset = 0;
    void loadPageOnly(0);
  }

  async function runFindPreview() {
    if (!page || !findColumn) return;
    findBusy = true; errorMessage = '';
    try {
      findPreview = await reads.track(port.previewFindReplace(contextId, {
        tableKey: page.tableKey, column: findColumn, findText, replaceText,
        matchCase: findMatchCase, exactCell: findExactCell, filters: buildActiveFilterSpecs(),
        globalSearch, scopeToActiveSU, maxPreview: 500,
      }));
    } catch (err) {
      errorMessage = `Find/Replace preview failed: ${String(err)}`;
    } finally {
      findBusy = false;
    }
  }

  async function applyFindReplaceValid() {
    if (!page || !findPreview || findPreview.validCount === 0) return;
    const validEdits = findPreview.items.filter(i => !i.validationError).map(i => $state.snapshot(i.edit));
    if (validEdits.length === 0) return;
    saving = true; errorMessage = '';
    try {
      const res = await port.applyEdits(contextId, { tableKey: page.tableKey, edits: validEdits });
      findPreview = null;
      statusBanner = `Applied ${res.updatedCells} replacement(s) on ${page.tableName} (${res.auditRows} audit record(s)).`;
      await refreshTablesAndLoad(activeTableKey, offset, { preserveStatus: true });
    } catch (err) {
      errorMessage = `Find/Replace commit failed (rolled back): ${String(err)}`;
    } finally {
      saving = false;
    }
  }

  function openInsertChildDrawer() {
    if (!page || !activeChildTableEditable) return;
    let seedPlot = '';
    if (activeCell && page.rows[activeCell.row]) {
      const plotCol = orderedColumns.find(c => c.meta.name === 'PlotNumber');
      if (plotCol) seedPlot = formatCellForEditor(page.rows[activeCell.row].cells[plotCol.originalIndex], plotCol.meta);
    }
    insertSeedPlot = seedPlot;
    pendingDeleteRow = null; insertDrawerOpen = true; errorMessage = '';
  }

  function requestDeleteSelectedRow() {
    if (!page || !activeChildTableEditable || !activeCell) return;
    const row = page.rows[activeCell.row];
    if (!row) return;
    const plotCol = orderedColumns.find(c => c.meta.name === 'PlotNumber');
    const idCol = orderedColumns.find(c => c.meta.name === 'ID');
    const plotNumber = plotCol ? formatCellForEditor(row.cells[plotCol.originalIndex], plotCol.meta) : '';
    const idStr = idCol ? formatCellForEditor(row.cells[idCol.originalIndex], idCol.meta) : '';
    insertDrawerOpen = false;
    pendingDeleteRow = { rowId: row.rowId, plotNumber, id: idStr && /^-?\d+$/.test(idStr.trim()) ? Number(idStr.trim()) : null };
  }

  async function confirmDeleteSelectedRow() {
    if (!page || !activeChildTableEditable || !pendingDeleteRow || deleteBusy) return;
    const fn = port.deleteChildRow ?? defaultDatasheetBackendPort.deleteChildRow;
    if (!fn) { errorMessage = 'Child row delete port is unavailable.'; return; }
    deleteBusy = true; errorMessage = '';
    try {
      const target = pendingDeleteRow;
      const res = await fn(contextId, {
        tableKey: page.tableKey, rowId: target.rowId,
        expectedPlotNumber: target.plotNumber || undefined, expectedId: target.id,
      });
      pendingDeleteRow = null; activeCell = null; selectionAnchor = null; selectionRange = null;
      statusBanner = `Deleted row ID ${res.deletedId} (plot ${res.plotNumber}) from ${res.tableName} (${res.auditRows} audit record(s)).`;
      await refreshTablesAndLoad(activeTableKey, offset, { preserveStatus: true });
    } catch (err) {
      errorMessage = `Delete child row failed: ${String(err)}`;
    } finally {
      deleteBusy = false;
    }
  }

  onMount(() => { if (contextId) void refreshTablesAndLoad(activeTableKey, 0); });
  onDestroy(() => { generation++; reads.cancelAll(); onDirtyChange?.(false); onBusyChange?.(false); });
</script>

<svelte:window onmouseup={() => { isMouseSelecting = false; }} />

<section class="vpro-datasheet-workbench" data-tour="datasheet-grid-root" aria-label="Universal Project Datasheet Grid" oncopy={handleCopySelection}>
  <DatasheetHeader
    {project} {su} {hierarchy} {tables} {activeTableKey} {page}
    {activeTableReadOnly} {activeChildTableEditable}
    bind:scopeToActiveSU bind:globalSearch bind:findDrawerOpen
    {insertDrawerOpen} {busy} {saving} {insertBusy} {deleteBusy}
    hasActiveCell={!!(activeCell && page?.rows[activeCell.row])}
    draftCount={draftEntries.length} {validEditCount} {invalidDraftCount}
    onApplyFilter={() => void loadPageOnly(0)}
    onOpenInsert={openInsertChildDrawer}
    onRequestDelete={requestDeleteSelectedRow}
    onDiscard={discardDrafts}
    onSave={() => void saveDrafts()}
    onSelectTable={selectTable}
  />

  {#if activeTableReadOnly && page}
    <p role="status" class="vpro-ds-status" data-readonly-table-banner>
      Read-only system table view (<code>{page.tableName}</code>): inspection, sorting, filtering, and copy are enabled; mutations are locked.
    </p>
  {/if}
  {#if errorMessage}<p role="alert" class="vpro-ds-alert">{errorMessage}</p>{/if}
  {#if statusBanner}<p role="status" class="vpro-ds-status">{statusBanner}</p>{/if}

  {#if pendingDeleteRow && page}
    <div class="vpro-ds-confirm-bar" role="alertdialog" aria-label="Confirm Child Row Deletion" data-delete-confirm-bar>
      <span>
        Delete row <code>{pendingDeleteRow.rowId}</code>
        {#if pendingDeleteRow.id !== null}(ID {pendingDeleteRow.id}){/if}
        for plot <strong>{pendingDeleteRow.plotNumber || '(unknown)'}</strong> from <code>{page.tableName}</code>?
        This logs a permanent delete audit entry.
      </span>
      <div class="vpro-ds-toolbar-actions">
        <button type="button" class="vpro-btn-danger" data-confirm-delete-row disabled={deleteBusy} onclick={confirmDeleteSelectedRow}>
          {deleteBusy ? 'Deleting...' : 'Confirm Delete Row'}
        </button>
        <button type="button" class="vpro-btn-secondary" disabled={deleteBusy} onclick={() => { pendingDeleteRow = null; }}>Cancel</button>
      </div>
    </div>
  {/if}

  {#if insertDrawerOpen && page && activeChildTableEditable}
    <DatasheetInsertDrawer
      {contextId} {page} {orderedColumns} seedPlotNumber={insertSeedPlot} {port} {activeChildTableEditable}
      bind:insertDrawerOpen bind:insertBusy
      onError={msg => { errorMessage = msg; }}
      onInserted={async banner => { statusBanner = banner; await refreshTablesAndLoad(activeTableKey, offset, { preserveStatus: true }); }}
    />
  {/if}

  {#if findDrawerOpen && page}
    <DatasheetFindReplaceDrawer
      {page} {editableColumns}
      bind:findColumn bind:findText bind:replaceText bind:findMatchCase bind:findExactCell
      {findPreview} {findBusy} {saving}
      onRunPreview={runFindPreview} onApplyValid={applyFindReplaceValid}
    />
  {/if}

  {#if page}
    <DatasheetVirtualTable
      {page} {orderedColumns} {visibleRows} {virtualSlice} rowHeight={ROW_HEIGHT}
      {sortSpecs} bind:columnFilters {drafts}
      bind:activeCell bind:selectionAnchor bind:selectionRange bind:isMouseSelecting
      bind:scrollTop bind:viewportHeight bind:viewportEl bind:pageSize
      {offset} {busy} draftCount={draftEntries.length} {invalidDraftCount}
      {onOpenPlot} onHeaderSort={handleHeaderSort} onLoadPage={next => void loadPageOnly(next)}
      onSetCellDraft={setCellDraft} onCellKeyDown={handleCellKeyDown} onCellPaste={handlePasteIntoCell}
    />
  {/if}
</section>
