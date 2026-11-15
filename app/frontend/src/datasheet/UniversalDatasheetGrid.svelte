<script lang="ts">
  import { onDestroy, onMount, untrack } from 'svelte';
  import { ReadRequests } from '../shared/readRequests';
  import {
    ALL_DATASHEET_KEYS,
    cellsSemanticallyEqual,
    computeNextGridCell,
    computeVirtualWindow,
    defaultDatasheetBackendPort,
    formatCellForEditor,
    formatTSVRange,
    isCellInRange,
    isColumnEditable,
    isEditableChildTable,
    isReadOnlyDatasheetTable,
    normalizeGridRange,
    parseAndValidateCellInput,
    parseTSVClipboard,
    shouldNavigateOnArrowKey,
    toggleMultiColumnSort,
    type DatasheetBackendPort,
    type DatasheetCellEdit,
    type DatasheetColumnMeta,
    type DatasheetFilterSpec,
    type DatasheetFindReplacePreview,
    type DatasheetPage,
    type DatasheetSortSpec,
    type DatasheetStorageCell,
    type DatasheetTableInfo,
    type DatasheetTableKey,
    type GridSelectionRange,
  } from './universalDatasheetGrid';

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
    contextId,
    project = '',
    su = 'None',
    hierarchy = 'None',
    initialTableKey = 'Env',
    port = defaultDatasheetBackendPort,
    onBusyChange,
    onDirtyChange,
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

  // Keyed by `${rowId}::${colName}`
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

  // Child-row insert & delete state
  let insertDrawerOpen = $state(false);
  let insertPlotNumber = $state('');
  let insertFieldDrafts = $state<Record<string, string>>({});
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

  // Find & Replace state
  let findDrawerOpen = $state(false);
  let findColumn = $state('');
  let findText = $state('');
  let replaceText = $state('');
  let findMatchCase = $state(false);
  let findExactCell = $state(false);
  let findPreview = $state.raw<DatasheetFindReplacePreview | null>(null);
  let findBusy = $state(false);

  let generation = 0;

  // Compute display columns with pinned column placed first
  const orderedColumns = $derived.by(() => {
    if (!page) return [] as Array<{ meta: DatasheetColumnMeta; originalIndex: number }>;
    const pinned: Array<{ meta: DatasheetColumnMeta; originalIndex: number }> = [];
    const rest: Array<{ meta: DatasheetColumnMeta; originalIndex: number }> = [];
    page.columns.forEach((meta, idx) => {
      if (meta.pinned) pinned.push({ meta, originalIndex: idx });
      else rest.push({ meta, originalIndex: idx });
    });
    return [...pinned, ...rest];
  });

  const virtualSlice = $derived(
    computeVirtualWindow(scrollTop, viewportHeight, ROW_HEIGHT, page?.rows.length ?? 0, 8)
  );

  const visibleRows = $derived(
    page ? page.rows.slice(virtualSlice.startIndex, virtualSlice.endIndex) : []
  );

  const draftEntries = $derived(Object.values(drafts));
  const invalidDraftCount = $derived(draftEntries.filter(d => d.error !== '').length);
  const validEditCount = $derived(draftEntries.filter(d => d.error === '' && d.after !== null).length);
  const activeTableReadOnly = $derived(
    page ? isReadOnlyDatasheetTable(page.tableKey, page.readOnly) : isReadOnlyDatasheetTable(activeTableKey)
  );
  const activeChildTableEditable = $derived(
    !!page && !activeTableReadOnly && isEditableChildTable(page.tableKey)
  );
  const editableColumns = $derived.by(() => {
    const p = page;
    return p ? p.columns.filter(c => isColumnEditable(p.tableKey, c, p.canEditMaster)) : [];
  });
  const insertableColumns = $derived.by(() => {
    const p = page;
    if (!p) return [] as Array<{ meta: DatasheetColumnMeta; originalIndex: number }>;
    return orderedColumns
      .filter(c => c.meta.name !== 'ID' && c.meta.name !== 'PlotNumber' && isColumnEditable(p.tableKey, c.meta, p.canEditMaster))
      .slice(0, 6);
  });

  function notifyHost() {
    onBusyChange?.(busy || saving || findBusy || insertBusy || deleteBusy || draftEntries.length > 0);
    onDirtyChange?.(!busy && !saving && !findBusy && !insertBusy && !deleteBusy && draftEntries.length > 0);
  }

  $effect(() => {
    void busy;
    void saving;
    void findBusy;
    void insertBusy;
    void deleteBusy;
    void invalidDraftCount;
    void draftEntries.length;
    notifyHost();
  });

  function draftKey(rowId: string, column: string): string {
    return `${rowId}::${column}`;
  }

  function buildActiveFilterSpecs(): DatasheetFilterSpec[] {
    const out: DatasheetFilterSpec[] = [];
    for (const [col, val] of Object.entries(columnFilters)) {
      const trimmed = val.trim();
      if (!trimmed) continue;
      if (trimmed === '=NULL') {
        out.push({ column: col, op: 'is_null', value: '' });
      } else if (trimmed === '!=NULL') {
        out.push({ column: col, op: 'not_null', value: '' });
      } else if (trimmed.startsWith('=')) {
        out.push({ column: col, op: 'eq', value: trimmed.slice(1) });
      } else {
        out.push({ column: col, op: 'contains', value: trimmed });
      }
    }
    return out;
  }

  async function refreshTablesAndLoad(
    targetKey: DatasheetTableKey = activeTableKey,
    nextOffset = 0,
    options?: { preserveStatus?: boolean }
  ) {
    if (!contextId) return;
    generation++;
    const reqGen = generation;
    reads.cancelAll();
    busy = true;
    errorMessage = '';
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

      const reqPayload = {
        tableKey: targetKey,
        offset: nextOffset,
        limit: pageSize,
        sort: $state.snapshot(sortSpecs),
        filters: buildActiveFilterSpecs(),
        globalSearch,
        scopeToActiveSU,
      };
      const loaded = await reads.track(port.getPage(contextId, reqPayload));
      if (reqGen !== generation) return;
      page = loaded;
      offset = loaded.offset;
      if (!findColumn && loaded.columns.length > 0) {
        const firstEditable =
          loaded.columns.find(c => !c.pinned && isColumnEditable(loaded.tableKey, c, loaded.canEditMaster)) ??
          loaded.columns[0];
        findColumn = firstEditable.name;
      }
      if (!options?.preserveStatus) {
        statusBanner = '';
      }
    } catch (err) {
      if (reqGen === generation) {
        errorMessage = String(err);
      }
    } finally {
      if (reqGen === generation) {
        busy = false;
      }
    }
  }

  async function loadPageOnly(nextOffset = offset) {
    if (!contextId) return;
    generation++;
    const reqGen = generation;
    reads.cancelAll();
    busy = true;
    errorMessage = '';
    try {
      const reqPayload = {
        tableKey: activeTableKey,
        offset: Math.max(0, nextOffset),
        limit: pageSize,
        sort: $state.snapshot(sortSpecs),
        filters: buildActiveFilterSpecs(),
        globalSearch,
        scopeToActiveSU,
      };
      const loaded = await reads.track(port.getPage(contextId, reqPayload));
      if (reqGen !== generation) return;
      page = loaded;
      offset = loaded.offset;
    } catch (err) {
      if (reqGen === generation) {
        errorMessage = String(err);
      }
    } finally {
      if (reqGen === generation) {
        busy = false;
      }
    }
  }

  function selectTable(key: DatasheetTableKey) {
    if (draftEntries.length > 0) {
      errorMessage = 'Save or discard unsaved cell edits before switching datasheet tables.';
      return;
    }
    activeTableKey = key;
    offset = 0;
    sortSpecs = [];
    columnFilters = {};
    globalSearch = '';
    activeCell = null;
    selectionAnchor = null;
    selectionRange = null;
    isMouseSelecting = false;
    insertDrawerOpen = false;
    pendingDeleteRow = null;
    findPreview = null;
    findColumn = '';
    scrollTop = 0;
    void refreshTablesAndLoad(key, 0);
  }

  function setCellDraft(rowIndex: number, displayColIndex: number, rawValue: string) {
    if (!page) return;
    const row = page.rows[rowIndex];
    const colEntry = orderedColumns[displayColIndex];
    if (!row || !colEntry) return;
    const colMeta = colEntry.meta;
    const originalCell = row.cells[colEntry.originalIndex];
    const key = draftKey(row.rowId, colMeta.name);

    const parsed = parseAndValidateCellInput(page.tableKey, colMeta, rawValue, page.canEditMaster);
    if (!parsed.error && parsed.cell && cellsSemanticallyEqual(originalCell, parsed.cell, colMeta)) {
      const next = { ...drafts };
      delete next[key];
      drafts = next;
      return;
    }

    drafts = {
      ...drafts,
      [key]: {
        rowId: row.rowId,
        column: colMeta.name,
        rawText: rawValue,
        before: structuredClone($state.snapshot(originalCell)),
        after: parsed.cell,
        error: parsed.error,
      },
    };
  }

  function discardDrafts() {
    drafts = {};
    errorMessage = '';
    statusBanner = 'Discarded unsaved datasheet edits.';
  }

  async function saveDrafts() {
    if (!page || saving || validEditCount === 0) return;
    if (invalidDraftCount > 0) {
      errorMessage = `Resolve ${invalidDraftCount} invalid cell(s) before saving.`;
      return;
    }
    saving = true;
    errorMessage = '';
    try {
      const edits: DatasheetCellEdit[] = [];
      for (const d of draftEntries) {
        if (d.after) {
          edits.push({
            rowId: d.rowId,
            column: d.column,
            before: $state.snapshot(d.before),
            after: $state.snapshot(d.after),
          });
        }
      }
      const res = await port.applyEdits(contextId, {
        tableKey: page.tableKey,
        edits,
      });
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
      selectionRange = {
        startRow: selectionAnchor.row,
        endRow: rowIdx,
        startCol: selectionAnchor.col,
        endCol: colIdx,
      };
    } else {
      selectionAnchor = { row: rowIdx, col: colIdx };
      selectionRange = { startRow: rowIdx, endRow: rowIdx, startCol: colIdx, endCol: colIdx };
    }
    if (viewportEl) {
      const topTarget = rowIdx * ROW_HEIGHT;
      const bottomTarget = topTarget + ROW_HEIGHT;
      if (topTarget < viewportEl.scrollTop) {
        viewportEl.scrollTop = topTarget;
      } else if (bottomTarget > viewportEl.scrollTop + viewportEl.clientHeight - 40) {
        viewportEl.scrollTop = bottomTarget - viewportEl.clientHeight + 48;
      }
    }
    queueMicrotask(() => {
      const el = viewportEl?.querySelector<HTMLInputElement>(
        `input[data-grid-row="${rowIdx}"][data-grid-col="${colIdx}"]`
      );
      el?.focus();
      if (!extendSelection) {
        el?.select();
      }
    });
  }

  function handleCellKeyDown(event: KeyboardEvent, rowIdx: number, colIdx: number) {
    if (!page) return;
    if (event.key === 'Enter' || event.key === 'Tab') {
      const next = computeNextGridCell(
        { row: rowIdx, col: colIdx },
        event.key,
        event.shiftKey,
        page.rows.length,
        orderedColumns.length
      );
      if (next) {
        event.preventDefault();
        focusGridInput(next.row, next.col, false);
      }
      return;
    }
    if (
      event.key === 'ArrowUp' ||
      event.key === 'ArrowDown' ||
      event.key === 'ArrowLeft' ||
      event.key === 'ArrowRight'
    ) {
      const inputEl = event.currentTarget as HTMLInputElement | null;
      if (
        !shouldNavigateOnArrowKey(
          event.key,
          inputEl?.selectionStart ?? null,
          inputEl?.selectionEnd ?? null,
          inputEl?.value.length ?? 0
        )
      ) {
        return;
      }
      const next = computeNextGridCell(
        { row: rowIdx, col: colIdx },
        event.key,
        event.shiftKey,
        page.rows.length,
        orderedColumns.length
      );
      if (next) {
        event.preventDefault();
        focusGridInput(next.row, next.col, event.shiftKey);
      }
      return;
    }
    if (event.key === 'Escape') {
      const row = page.rows[rowIdx];
      const col = orderedColumns[colIdx];
      if (row && col) {
        const key = draftKey(row.rowId, col.meta.name);
        if (key in drafts) {
          event.preventDefault();
          const copy = { ...drafts };
          delete copy[key];
          drafts = copy;
        }
      }
    }
  }

  function handleCopySelection(event: ClipboardEvent) {
    if (!page || !selectionRange) return;
    const norm = normalizeGridRange(selectionRange);
    // Single-cell native input selection copies normally unless multi-cell range is selected
    if (norm.startRow === norm.endRow && norm.startCol === norm.endCol) return;
    const projectedRows = page.rows.map(r => ({
      rowId: r.rowId,
      cells: orderedColumns.map(c => r.cells[c.originalIndex]),
    }));
    const cols = orderedColumns.map(c => c.meta);
    const tsv = formatTSVRange(projectedRows, cols, norm, (rowId, colName) => {
      const d = drafts[draftKey(rowId, colName)];
      return d?.rawText;
    });
    if (event.clipboardData) {
      event.preventDefault();
      event.clipboardData.setData('text/plain', tsv);
      statusBanner = `Copied ${norm.endRow - norm.startRow + 1}x${norm.endCol - norm.startCol + 1} TSV block to clipboard.`;
    }
  }

  function handlePasteIntoCell(event: ClipboardEvent, anchorRow: number, anchorCol: number) {
    if (!page || !event.clipboardData) return;
    const text = event.clipboardData.getData('text/plain');
    if (!text.includes('\t') && !text.includes('\n')) {
      return; // single value paste uses standard input handling
    }
    const matrix = parseTSVClipboard(text);
    if (matrix.length === 0) return;
    event.preventDefault();

    let applied = 0;
    for (let rOff = 0; rOff < matrix.length; rOff++) {
      const targetRow = anchorRow + rOff;
      if (targetRow >= page.rows.length) break;
      const line = matrix[rOff];
      for (let cOff = 0; cOff < line.length; cOff++) {
        const targetCol = anchorCol + cOff;
        if (targetCol >= orderedColumns.length) break;
        if (!isColumnEditable(page.tableKey, orderedColumns[targetCol].meta, page.canEditMaster)) continue;
        setCellDraft(targetRow, targetCol, line[cOff]);
        applied++;
      }
    }
    selectionRange = {
      startRow: anchorRow,
      endRow: Math.min(page.rows.length - 1, anchorRow + matrix.length - 1),
      startCol: anchorCol,
      endCol: Math.min(orderedColumns.length - 1, anchorCol + (matrix[0]?.length ?? 1) - 1),
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
    findBusy = true;
    errorMessage = '';
    try {
      const preview = await reads.track(
        port.previewFindReplace(contextId, {
          tableKey: page.tableKey,
          column: findColumn,
          findText,
          replaceText,
          matchCase: findMatchCase,
          exactCell: findExactCell,
          filters: buildActiveFilterSpecs(),
          globalSearch,
          scopeToActiveSU,
          maxPreview: 500,
        })
      );
      findPreview = preview;
    } catch (err) {
      errorMessage = `Find/Replace preview failed: ${String(err)}`;
    } finally {
      findBusy = false;
    }
  }

  async function applyFindReplaceValid() {
    if (!page || !findPreview || findPreview.validCount === 0) return;
    const validEdits = findPreview.items
      .filter(i => !i.validationError)
      .map(i => $state.snapshot(i.edit));
    if (validEdits.length === 0) return;
    saving = true;
    errorMessage = '';
    try {
      const res = await port.applyEdits(contextId, {
        tableKey: page.tableKey,
        edits: validEdits,
      });
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
      const row = page.rows[activeCell.row];
      const plotCol = orderedColumns.find(c => c.meta.name === 'PlotNumber');
      if (plotCol) {
        seedPlot = formatCellForEditor(row.cells[plotCol.originalIndex], plotCol.meta);
      }
    }
    insertPlotNumber = seedPlot;
    insertFieldDrafts = {};
    pendingDeleteRow = null;
    insertDrawerOpen = true;
    errorMessage = '';
  }

  async function commitInsertChildRow() {
    if (!page || !activeChildTableEditable || insertBusy) return;
    const plotNumber = insertPlotNumber.trim();
    if (!plotNumber) {
      errorMessage = 'PlotNumber is required to insert a child row.';
      return;
    }
    const insertCells: Record<string, DatasheetStorageCell> = {};
    for (const colEntry of orderedColumns) {
      const meta = colEntry.meta;
      if (meta.name === 'ID' || meta.name === 'PlotNumber') continue;
      if (!isColumnEditable(page.tableKey, meta, page.canEditMaster)) continue;
      const raw = insertFieldDrafts[meta.name] ?? '';
      if (raw === '') continue;
      const parsed = parseAndValidateCellInput(page.tableKey, meta, raw, page.canEditMaster);
      if (parsed.error || !parsed.cell) {
        errorMessage = parsed.error || `Invalid value for ${meta.name}.`;
        return;
      }
      insertCells[meta.name] = parsed.cell;
    }

    const fn = port.insertChildRow ?? defaultDatasheetBackendPort.insertChildRow;
    if (!fn) {
      errorMessage = 'Child row insert port is unavailable.';
      return;
    }
    insertBusy = true;
    errorMessage = '';
    try {
      const res = await fn(contextId, {
        tableKey: page.tableKey,
        plotNumber,
        cells: insertCells,
      });
      insertDrawerOpen = false;
      insertFieldDrafts = {};
      statusBanner = `Inserted row ID ${res.id} for plot ${res.plotNumber} in ${res.tableName} (${res.auditRows} audit record(s)).`;
      await refreshTablesAndLoad(activeTableKey, offset, { preserveStatus: true });
    } catch (err) {
      errorMessage = `Insert child row failed: ${String(err)}`;
    } finally {
      insertBusy = false;
    }
  }

  function requestDeleteSelectedRow() {
    if (!page || !activeChildTableEditable || !activeCell) return;
    const row = page.rows[activeCell.row];
    if (!row) return;
    const plotCol = orderedColumns.find(c => c.meta.name === 'PlotNumber');
    const idCol = orderedColumns.find(c => c.meta.name === 'ID');
    const plotNumber = plotCol ? formatCellForEditor(row.cells[plotCol.originalIndex], plotCol.meta) : '';
    const idStr = idCol ? formatCellForEditor(row.cells[idCol.originalIndex], idCol.meta) : '';
    const parsedId = idStr && /^-?\d+$/.test(idStr.trim()) ? Number(idStr.trim()) : null;
    insertDrawerOpen = false;
    pendingDeleteRow = {
      rowId: row.rowId,
      plotNumber,
      id: parsedId,
    };
  }

  async function confirmDeleteSelectedRow() {
    if (!page || !activeChildTableEditable || !pendingDeleteRow || deleteBusy) return;
    const fn = port.deleteChildRow ?? defaultDatasheetBackendPort.deleteChildRow;
    if (!fn) {
      errorMessage = 'Child row delete port is unavailable.';
      return;
    }
    deleteBusy = true;
    errorMessage = '';
    try {
      const target = pendingDeleteRow;
      const res = await fn(contextId, {
        tableKey: page.tableKey,
        rowId: target.rowId,
        expectedPlotNumber: target.plotNumber || undefined,
        expectedId: target.id,
      });
      pendingDeleteRow = null;
      activeCell = null;
      selectionAnchor = null;
      selectionRange = null;
      statusBanner = `Deleted row ID ${res.deletedId} (plot ${res.plotNumber}) from ${res.tableName} (${res.auditRows} audit record(s)).`;
      await refreshTablesAndLoad(activeTableKey, offset, { preserveStatus: true });
    } catch (err) {
      errorMessage = `Delete child row failed: ${String(err)}`;
    } finally {
      deleteBusy = false;
    }
  }

  onMount(() => {
    if (contextId) {
      void refreshTablesAndLoad(activeTableKey, 0);
    }
  });

  onDestroy(() => {
    generation++;
    reads.cancelAll();
    onDirtyChange?.(false);
    onBusyChange?.(false);
  });
</script>

<svelte:window onmouseup={() => { isMouseSelecting = false; }} />

<section
  class="vpro-datasheet-workbench"
  data-tour="datasheet-grid-root"
  aria-label="Universal Project Datasheet Grid"
  oncopy={handleCopySelection}
>
  <header class="vpro-ds-header">
    <div>
      <p class="vpro-ds-eyebrow">DIRECT DATASHEET WORKBENCH</p>
      <h2 class="vpro-ds-title">
        Universal Project Datasheet
        {#if project}<span class="vpro-ds-context-pill">Project: {project}</span>{/if}
        {#if su && su !== 'None'}<span class="vpro-ds-context-pill">SU: {su}</span>{/if}
        {#if hierarchy && hierarchy !== 'None'}<span class="vpro-ds-context-pill">Hierarchy: {hierarchy}</span>{/if}
      </h2>
    </div>

    <div class="vpro-ds-toolbar-actions">
      <label class="vpro-ds-inline-check">
        <input
          type="checkbox"
          bind:checked={scopeToActiveSU}
          disabled={!su || su === 'None' || busy || saving}
          onchange={() => loadPageOnly(0)}
        />
        <span>Scope to Active SU</span>
      </label>

      <input
        type="search"
        class="vpro-ds-search"
        placeholder="Search all columns..."
        bind:value={globalSearch}
        onkeydown={e => {
          if (e.key === 'Enter') void loadPageOnly(0);
        }}
      />
      <button type="button" class="vpro-btn-secondary" disabled={busy} onclick={() => loadPageOnly(0)}>
        Apply Filter
      </button>
      <button
        type="button"
        class="vpro-btn-secondary"
        disabled={!page || activeTableReadOnly}
        onclick={() => {
          findDrawerOpen = !findDrawerOpen;
        }}
      >
        {findDrawerOpen ? 'Hide Find & Replace' : 'Find & Replace'}
      </button>
      {#if activeChildTableEditable}
        <button
          type="button"
          class="vpro-btn-secondary"
          data-add-child-row
          disabled={busy || saving || insertBusy || deleteBusy}
          onclick={openInsertChildDrawer}
        >
          {insertDrawerOpen ? 'Close Add Row' : '+ Add Row'}
        </button>
        <button
          type="button"
          class="vpro-btn-danger-outline"
          data-delete-child-row
          disabled={busy || saving || insertBusy || deleteBusy || !activeCell || !page?.rows[activeCell.row]}
          onclick={requestDeleteSelectedRow}
        >
          Delete Selected Row
        </button>
      {/if}
      <button
        type="button"
        class="vpro-btn-secondary"
        disabled={draftEntries.length === 0 || saving}
        onclick={discardDrafts}
      >
        Discard ({draftEntries.length})
      </button>
      <button
        type="button"
        class="vpro-btn-primary"
        disabled={validEditCount === 0 || invalidDraftCount > 0 || saving || activeTableReadOnly}
        onclick={saveDrafts}
      >
        {saving ? 'Saving...' : `Save Edits (${validEditCount})`}
      </button>
    </div>
  </header>

  <nav class="vpro-ds-tabs" aria-label="Canonical Project Tables">
    {#each ALL_DATASHEET_KEYS as key (key)}
      {@const info = tables.find(t => t.key === key)}
      {@const isReadOnlyTab = isReadOnlyDatasheetTable(key, info?.readOnly)}
      <button
        type="button"
        class="vpro-ds-tab"
        class:active={activeTableKey === key}
        disabled={saving}
        onclick={() => selectTable(key)}
      >
        <span>_{key}</span>
        {#if isReadOnlyTab}
          <span class="vpro-ds-ro-tag">RO</span>
        {/if}
        {#if info}
          <span class="vpro-ds-badge" class:unavailable={!info.available}>
            {info.available ? info.rowCount.toLocaleString() : 'N/A'}
          </span>
        {/if}
      </button>
    {/each}
  </nav>

  {#if activeTableReadOnly && page}
    <p role="status" class="vpro-ds-status" data-readonly-table-banner>
      Read-only system table view (<code>{page.tableName}</code>): inspection, sorting, filtering, and copy are enabled; mutations are locked.
    </p>
  {/if}

  {#if errorMessage}
    <p role="alert" class="vpro-ds-alert">{errorMessage}</p>
  {/if}
  {#if statusBanner}
    <p role="status" class="vpro-ds-status">{statusBanner}</p>
  {/if}

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
        <button type="button" class="vpro-btn-secondary" disabled={deleteBusy} onclick={() => { pendingDeleteRow = null; }}>
          Cancel
        </button>
      </div>
    </div>
  {/if}

  {#if insertDrawerOpen && page && activeChildTableEditable}
    <section class="vpro-ds-find-drawer" aria-label="Insert Child Table Row" data-insert-child-drawer>
      <div class="vpro-ds-find-controls">
        <label>
          <span>PlotNumber (required)</span>
          <input type="text" data-insert-plot bind:value={insertPlotNumber} placeholder="e.g. 00337" maxlength={7} />
        </label>
        {#each insertableColumns as colEntry (colEntry.meta.name)}
          <label>
            <span>{colEntry.meta.name}</span>
            <input
              type="text"
              data-insert-field={colEntry.meta.name}
              value={insertFieldDrafts[colEntry.meta.name] ?? ''}
              oninput={e => {
                insertFieldDrafts = { ...insertFieldDrafts, [colEntry.meta.name]: e.currentTarget.value };
              }}
            />
          </label>
        {/each}
        <button type="button" class="vpro-btn-primary" data-commit-insert-row disabled={insertBusy} onclick={commitInsertChildRow}>
          {insertBusy ? 'Inserting...' : 'Commit New Row'}
        </button>
        <button type="button" class="vpro-btn-secondary" disabled={insertBusy} onclick={() => { insertDrawerOpen = false; }}>
          Cancel
        </button>
      </div>
    </section>
  {/if}

  {#if findDrawerOpen && page}
    <section class="vpro-ds-find-drawer" aria-label="Column Find and Replace">
      <div class="vpro-ds-find-controls">
        <label>
          <span>Column</span>
          <select bind:value={findColumn}>
            {#each editableColumns as col (col.name)}
              <option value={col.name}>{col.name} ({col.kind})</option>
            {/each}
          </select>
        </label>
        <label>
          <span>Find</span>
          <input type="text" bind:value={findText} placeholder="Text to find..." />
        </label>
        <label>
          <span>Replace With</span>
          <input type="text" bind:value={replaceText} placeholder="Replacement (blank = NULL)" />
        </label>
        <label class="vpro-ds-inline-check">
          <input type="checkbox" bind:checked={findMatchCase} />
          <span>Match case</span>
        </label>
        <label class="vpro-ds-inline-check">
          <input type="checkbox" bind:checked={findExactCell} />
          <span>Whole cell</span>
        </label>
        <button type="button" class="vpro-btn-secondary" disabled={findBusy} onclick={runFindPreview}>
          {findBusy ? 'Previewing...' : 'Dry-Run Preview'}
        </button>
        {#if findPreview && findPreview.validCount > 0}
          <button
            type="button"
            class="vpro-btn-primary"
            disabled={saving}
            onclick={applyFindReplaceValid}
          >
            Commit {findPreview.validCount} Valid Replacement(s)
          </button>
        {/if}
      </div>

      {#if findPreview}
        <div class="vpro-ds-find-summary">
          <p>
            Matched <strong>{findPreview.matchedRows}</strong> row(s) in
            <code>{findPreview.tableName}.{findPreview.column}</code> —
            <strong>{findPreview.validCount}</strong> valid,
            <strong>{findPreview.invalidCount}</strong> blocked by validation.
          </p>
          {#if findPreview.items.length > 0}
            <div class="vpro-ds-find-preview-scroll">
              <table>
                <thead>
                  <tr>
                    <th>{page.pinnedColumn}</th>
                    <th>Before</th>
                    <th>After</th>
                    <th>Validation</th>
                  </tr>
                </thead>
                <tbody>
                  {#each findPreview.items.slice(0, 50) as item (item.rowId)}
                    <tr>
                      <td class="mono">{item.pinnedIdentity}</td>
                      <td class="mono">{item.beforeText || '(NULL)'}</td>
                      <td class="mono">{item.afterText || '(NULL)'}</td>
                      <td class:text-err={!!item.validationError}>
                        {item.validationError || 'Ready'}
                      </td>
                    </tr>
                  {/each}
                </tbody>
              </table>
            </div>
          {/if}
        </div>
      {/if}
    </section>
  {/if}

  {#if page}
    <div
      class="vpro-ds-viewport"
      bind:this={viewportEl}
      bind:clientHeight={viewportHeight}
      onscroll={e => {
        scrollTop = e.currentTarget.scrollTop;
      }}
    >
      <table class="vpro-ds-grid" role="grid" aria-rowcount={page.totalRows}>
        <thead>
          <tr class="vpro-ds-header-row">
            {#each orderedColumns as colEntry (colEntry.meta.name)}
              {@const sortIdx = sortSpecs.findIndex(
                s => s.column.toLowerCase() === colEntry.meta.name.toLowerCase()
              )}
              <th
                class:pinned={colEntry.meta.pinned}
                class:protected={colEntry.meta.protected}
                scope="col"
              >
                <button
                  type="button"
                  class="vpro-ds-sort-btn"
                  title="Click to sort; Shift+Click for multi-column sort"
                  onclick={e => handleHeaderSort(colEntry.meta.name, e)}
                >
                  <span>{colEntry.meta.name}</span>
                  {#if sortIdx >= 0}
                    <span class="vpro-ds-sort-indicator">
                      {sortSpecs[sortIdx].direction === 'asc' ? 'ASC' : 'DESC'}{sortSpecs.length > 1
                        ? ` #${sortIdx + 1}`
                        : ''}
                    </span>
                  {/if}
                </button>
              </th>
            {/each}
          </tr>
          <tr class="vpro-ds-filter-row">
            {#each orderedColumns as colEntry (colEntry.meta.name)}
              <th class:pinned={colEntry.meta.pinned}>
                <input
                  type="text"
                  class="vpro-ds-col-filter"
                  aria-label={`Filter ${colEntry.meta.name}`}
                  placeholder={colEntry.meta.pinned ? '=00337 or text' : 'Filter...'}
                  bind:value={columnFilters[colEntry.meta.name]}
                  onkeydown={e => {
                    if (e.key === 'Enter') void loadPageOnly(0);
                  }}
                />
              </th>
            {/each}
          </tr>
        </thead>

        <tbody>
          {#if virtualSlice.topSpacerPx > 0}
            <tr aria-hidden="true" style={`height:${virtualSlice.topSpacerPx}px;`}>
              <td colspan={orderedColumns.length} style="padding:0;border:0;"></td>
            </tr>
          {/if}

          {#each visibleRows as row, localIdx (row.rowId)}
            {@const rowIdx = virtualSlice.startIndex + localIdx}
            <tr class="vpro-ds-row" style={`height:${ROW_HEIGHT}px;`}>
              {#each orderedColumns as colEntry, colIdx (colEntry.meta.name)}
                {@const colMeta = colEntry.meta}
                {@const cell = row.cells[colEntry.originalIndex]}
                {@const key = draftKey(row.rowId, colMeta.name)}
                {@const draft = drafts[key]}
                {@const cellEditable = isColumnEditable(page.tableKey, colMeta, page.canEditMaster)}
                {@const cellSelected = isCellInRange(rowIdx, colIdx, selectionRange)}
                {@const displayVal = draft ? draft.rawText : formatCellForEditor(cell, colMeta)}
                <td
                  class:pinned={colMeta.pinned}
                  class:protected={colMeta.protected}
                  class:selected={cellSelected}
                  class:dirty={!!draft && !draft.error}
                  class:invalid={!!draft?.error}
                  class:readonly={!cellEditable}
                >
                  <div class="vpro-ds-cell-wrap">
                    <input
                      type="text"
                      class="vpro-ds-cell-input"
                      class:mono={colMeta.pinned || colMeta.kind !== 'text'}
                      data-grid-row={rowIdx}
                      data-grid-col={colIdx}
                      value={displayVal}
                      readonly={!cellEditable}
                      aria-invalid={draft?.error ? 'true' : undefined}
                      title={draft?.error || `${colMeta.name} (${colMeta.declaredType || colMeta.kind})${colMeta.protected ? ' [Protected]' : ''}`}
                      onfocus={() => {
                        activeCell = { row: rowIdx, col: colIdx };
                        if (!selectionAnchor) {
                          selectionAnchor = { row: rowIdx, col: colIdx };
                        }
                        if (!selectionRange) {
                          selectionRange = {
                            startRow: rowIdx,
                            endRow: rowIdx,
                            startCol: colIdx,
                            endCol: colIdx,
                          };
                        }
                      }}
                      onmousedown={e => {
                        isMouseSelecting = true;
                        if (e.shiftKey && selectionAnchor) {
                          activeCell = { row: rowIdx, col: colIdx };
                          selectionRange = {
                            startRow: selectionAnchor.row,
                            endRow: rowIdx,
                            startCol: selectionAnchor.col,
                            endCol: colIdx,
                          };
                        } else {
                          activeCell = { row: rowIdx, col: colIdx };
                          selectionAnchor = { row: rowIdx, col: colIdx };
                          selectionRange = {
                            startRow: rowIdx,
                            endRow: rowIdx,
                            startCol: colIdx,
                            endCol: colIdx,
                          };
                        }
                      }}
                      onmouseenter={() => {
                        if (isMouseSelecting && selectionAnchor) {
                          selectionRange = {
                            startRow: selectionAnchor.row,
                            endRow: rowIdx,
                            startCol: selectionAnchor.col,
                            endCol: colIdx,
                          };
                        }
                      }}
                      oninput={e => setCellDraft(rowIdx, colIdx, e.currentTarget.value)}
                      onkeydown={e => handleCellKeyDown(e, rowIdx, colIdx)}
                      onpaste={e => handlePasteIntoCell(e, rowIdx, colIdx)}
                    />
                    {#if colMeta.pinned && onOpenPlot && (page.tableKey === 'Env' || page.tableKey === 'Admin') && displayVal}
                      <button
                        type="button"
                        class="vpro-ds-open-plot"
                        title={`Open Plot ${displayVal} in Form`}
                        onclick={() => onOpenPlot(displayVal)}
                      >
                        Form
                      </button>
                    {/if}
                  </div>
                </td>
              {/each}
            </tr>
          {/each}

          {#if virtualSlice.bottomSpacerPx > 0}
            <tr aria-hidden="true" style={`height:${virtualSlice.bottomSpacerPx}px;`}>
              <td colspan={orderedColumns.length} style="padding:0;border:0;"></td>
            </tr>
          {/if}

          {#if page.rows.length === 0}
            <tr>
              <td colspan={orderedColumns.length} class="vpro-ds-empty">
                No rows matched the current filter criteria.
              </td>
            </tr>
          {/if}
        </tbody>
      </table>
    </div>

    <footer class="vpro-ds-footer">
      <div>
        Showing
        <strong>{page.rows.length ? page.offset + 1 : 0}</strong>–<strong
          >{page.offset + page.rows.length}</strong
        >
        of <strong>{page.totalRows.toLocaleString()}</strong> rows in
        <code>{page.tableName}</code>
        {#if invalidDraftCount > 0}
          <span class="vpro-ds-err-pill">{invalidDraftCount} invalid cell(s)</span>
        {/if}
      </div>

      <div class="vpro-ds-pager">
        <label>
          <span>Window</span>
          <select
            bind:value={pageSize}
            disabled={busy || draftEntries.length > 0}
            onchange={() => loadPageOnly(0)}
          >
            <option value={100}>100 rows</option>
            <option value={250}>250 rows</option>
            <option value={500}>500 rows</option>
            <option value={1000}>1,000 rows</option>
          </select>
        </label>
        <button
          type="button"
          class="vpro-btn-secondary"
          disabled={busy || offset === 0 || draftEntries.length > 0}
          onclick={() => loadPageOnly(Math.max(0, offset - pageSize))}
        >
          Previous
        </button>
        <button
          type="button"
          class="vpro-btn-secondary"
          disabled={busy || offset + page.rows.length >= page.totalRows || draftEntries.length > 0}
          onclick={() => loadPageOnly(offset + pageSize)}
        >
          Next
        </button>
      </div>
    </footer>
  {/if}
</section>

<style>
  .vpro-datasheet-workbench {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
    background: #FFFFFF;
    border: 1px solid #D8D8D8;
    border-top: 4px solid #003366;
    border-radius: 4px;
    padding: 1rem;
    min-width: 0;
  }
  .vpro-ds-header {
    display: flex;
    flex-wrap: wrap;
    justify-content: space-between;
    align-items: flex-end;
    gap: 0.75rem;
    min-width: 0;
  }
  .vpro-ds-eyebrow {
    margin: 0;
    font-size: 0.7rem;
    font-weight: 700;
    letter-spacing: 0.08em;
    color: #003366;
  }
  .vpro-ds-title {
    margin: 0.15rem 0 0;
    font-size: 1.2rem;
    font-weight: 600;
    color: #003366;
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.5rem;
  }
  .vpro-ds-context-pill {
    font-size: 0.75rem;
    font-weight: 500;
    background: #F2F2F2;
    border: 1px solid #D8D8D8;
    color: #003366;
    padding: 0.15rem 0.5rem;
    border-radius: 3px;
  }
  .vpro-ds-toolbar-actions {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.5rem;
    min-width: 0;
  }
  .vpro-ds-inline-check {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
    font-size: 0.82rem;
    color: #313132;
  }
  .vpro-ds-search {
    min-height: 34px;
    padding: 0.3rem 0.6rem;
    border: 1px solid #9F9F9F;
    border-radius: 4px;
    font-size: 0.85rem;
    color: #313132;
    background: #FFFFFF;
    min-width: 0;
  }
  .vpro-btn-primary {
    min-height: 34px;
    padding: 0.35rem 0.8rem;
    background: #003366;
    color: #FFFFFF;
    border: 1px solid #003366;
    border-bottom: 2px solid #FCBA19;
    border-radius: 4px;
    font-size: 0.82rem;
    font-weight: 600;
  }
  .vpro-btn-primary:disabled {
    opacity: 0.5;
  }
  .vpro-btn-secondary {
    min-height: 34px;
    padding: 0.35rem 0.7rem;
    background: #FFFFFF;
    color: #003366;
    border: 1px solid #003366;
    border-radius: 4px;
    font-size: 0.82rem;
    font-weight: 500;
  }
  .vpro-btn-secondary:disabled,
  .vpro-btn-danger-outline:disabled,
  .vpro-btn-danger:disabled {
    opacity: 0.5;
  }
  .vpro-btn-danger-outline {
    min-height: 34px;
    padding: 0.35rem 0.7rem;
    background: #FFFFFF;
    color: #D8292F;
    border: 1px solid #D8292F;
    border-radius: 4px;
    font-size: 0.82rem;
    font-weight: 600;
  }
  .vpro-btn-danger {
    min-height: 34px;
    padding: 0.35rem 0.8rem;
    background: #D8292F;
    color: #FFFFFF;
    border: 1px solid #D8292F;
    border-radius: 4px;
    font-size: 0.82rem;
    font-weight: 600;
  }
  .vpro-ds-tabs {
    display: flex;
    flex-wrap: wrap;
    gap: 0.3rem;
    border-bottom: 2px solid #D8D8D8;
    padding-bottom: 0.35rem;
    min-width: 0;
  }
  .vpro-ds-tab {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
    padding: 0.4rem 0.7rem;
    border: 1px solid #D8D8D8;
    border-radius: 4px 4px 0 0;
    background: #F2F2F2;
    color: #313132;
    font-size: 0.82rem;
    font-weight: 600;
  }
  .vpro-ds-tab.active {
    background: #003366;
    color: #FFFFFF;
    border-color: #003366;
    box-shadow: inset 0 -3px 0 #FCBA19;
  }
  .vpro-ds-badge,
  .vpro-ds-ro-tag {
    font-size: 0.7rem;
    padding: 0.05rem 0.35rem;
    border-radius: 3px;
    background: rgba(255, 255, 255, 0.2);
  }
  .vpro-ds-tab:not(.active) .vpro-ds-badge {
    background: #D8D8D8;
    color: #313132;
  }
  .vpro-ds-tab:not(.active) .vpro-ds-ro-tag {
    background: #FEF6E0;
    color: #313132;
    border: 1px solid #FCBA19;
  }
  .vpro-ds-badge.unavailable {
    opacity: 0.65;
  }
  .vpro-ds-alert {
    margin: 0;
    padding: 0.55rem 0.75rem;
    background: #FBEAEA;
    border-left: 4px solid #D8292F;
    color: #D8292F;
    font-size: 0.85rem;
  }
  .vpro-ds-status {
    margin: 0;
    padding: 0.5rem 0.75rem;
    background: #F2F2F2;
    border-left: 4px solid #FCBA19;
    color: #003366;
    font-size: 0.83rem;
  }
  .vpro-ds-confirm-bar {
    display: flex;
    flex-wrap: wrap;
    justify-content: space-between;
    align-items: center;
    gap: 0.65rem;
    padding: 0.6rem 0.8rem;
    background: #FBEAEA;
    border: 1px solid #D8292F;
    border-radius: 4px;
    color: #313132;
    font-size: 0.84rem;
  }
  .vpro-ds-find-drawer {
    background: #F2F2F2;
    border: 1px solid #D8D8D8;
    border-left: 4px solid #003366;
    padding: 0.75rem;
    border-radius: 4px;
    display: grid;
    gap: 0.6rem;
    min-width: 0;
  }
  .vpro-ds-find-controls {
    display: flex;
    flex-wrap: wrap;
    align-items: flex-end;
    gap: 0.6rem;
  }
  .vpro-ds-find-controls label {
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
    font-size: 0.78rem;
    font-weight: 600;
    color: #003366;
    min-width: 0;
  }
  .vpro-ds-find-controls input[type='text'],
  .vpro-ds-find-controls select {
    min-height: 32px;
    padding: 0.25rem 0.5rem;
    border: 1px solid #9F9F9F;
    border-radius: 3px;
    font-size: 0.82rem;
    background: #FFFFFF;
    color: #313132;
    min-width: 0;
  }
  .vpro-ds-find-preview-scroll {
    max-height: 180px;
    overflow: auto;
    border: 1px solid #D8D8D8;
    background: #FFFFFF;
  }
  .vpro-ds-viewport {
    height: 520px;
    max-width: 100%;
    overflow: auto;
    border: 1px solid #D8D8D8;
    background: #FFFFFF;
    position: relative;
  }
  .vpro-ds-grid {
    border-collapse: separate;
    border-spacing: 0;
    width: max-content;
    min-width: 100%;
    font-size: 0.82rem;
  }
  .vpro-ds-grid thead {
    position: sticky;
    top: 0;
    z-index: 3;
  }
  .vpro-ds-header-row th {
    background: #003366;
    color: #FFFFFF;
    padding: 0;
    border-right: 1px solid #002244;
    border-bottom: 2px solid #FCBA19;
    min-width: 118px;
  }
  .vpro-ds-header-row th.protected {
    background: #002244;
  }
  .vpro-ds-filter-row th {
    background: #F2F2F2;
    padding: 3px 4px;
    border-right: 1px solid #D8D8D8;
    border-bottom: 1px solid #9F9F9F;
  }
  .vpro-ds-grid th.pinned,
  .vpro-ds-grid td.pinned {
    position: sticky;
    left: 0;
    z-index: 2;
    box-shadow: 2px 0 0 #003366;
  }
  .vpro-ds-grid thead th.pinned {
    z-index: 4;
  }
  .vpro-ds-sort-btn {
    width: 100%;
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 0.4rem;
    padding: 0.45rem 0.55rem;
    background: transparent;
    color: inherit;
    border: 0;
    font-size: 0.78rem;
    font-weight: 600;
    text-align: left;
  }
  .vpro-ds-sort-indicator {
    font-size: 0.68rem;
    background: #FCBA19;
    color: #003366;
    padding: 0.05rem 0.3rem;
    border-radius: 2px;
    font-weight: 700;
  }
  .vpro-ds-col-filter {
    width: 100%;
    box-sizing: border-box;
    padding: 0.2rem 0.35rem;
    border: 1px solid #D8D8D8;
    border-radius: 2px;
    font-size: 0.76rem;
    background: #FFFFFF;
    color: #313132;
  }
  .vpro-ds-row td {
    padding: 0;
    border-right: 1px solid #D8D8D8;
    border-bottom: 1px solid #D8D8D8;
    background: #FFFFFF;
  }
  .vpro-ds-row td.pinned {
    background: #F2F2F2;
  }
  .vpro-ds-row td.selected {
    background: rgba(26, 90, 150, 0.12);
    box-shadow: inset 0 0 0 1px #1A5A96;
  }
  .vpro-ds-row td.dirty {
    background: #FEF6E0;
  }
  .vpro-ds-row td.invalid {
    background: #FBEAEA;
  }
  .vpro-ds-row td.readonly {
    background: #F2F2F2;
  }
  .vpro-ds-cell-wrap {
    display: flex;
    align-items: center;
    height: 33px;
  }
  .vpro-ds-cell-input {
    width: 100%;
    height: 100%;
    box-sizing: border-box;
    border: 0;
    padding: 0 0.45rem;
    background: transparent;
    color: #313132;
    font-size: 0.82rem;
  }
  .vpro-ds-cell-input:focus {
    outline: 2px solid #003366;
    outline-offset: -2px;
    background: #FFFFFF;
  }
  .vpro-ds-open-plot {
    flex: none;
    margin-right: 3px;
    padding: 1px 5px;
    font-size: 0.68rem;
    background: #003366;
    color: #FFFFFF;
    border: 0;
    border-radius: 2px;
  }
  .mono {
    font-family: var(--font-mono, monospace);
  }
  .text-err {
    color: #D8292F;
    font-weight: 600;
  }
  .vpro-ds-empty {
    padding: 2rem;
    text-align: center;
    color: #474543;
  }
  .vpro-ds-footer {
    display: flex;
    flex-wrap: wrap;
    justify-content: space-between;
    align-items: center;
    gap: 0.75rem;
    font-size: 0.82rem;
    color: #313132;
  }
  .vpro-ds-pager {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.5rem;
  }
  .vpro-ds-pager label {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
  }
  .vpro-ds-err-pill {
    margin-left: 0.5rem;
    padding: 0.1rem 0.45rem;
    background: #FBEAEA;
    color: #D8292F;
    border-radius: 3px;
    font-weight: 600;
  }
</style>
