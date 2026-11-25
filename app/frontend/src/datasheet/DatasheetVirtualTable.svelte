<script lang="ts">
  import {
    computeNextGridCell,
    computeVirtualWindow,
    formatCellForEditor,
    formatTSVRange,
    isCellInRange,
    isColumnEditable,
    normalizeGridRange,
    parseTSVClipboard,
    shouldNavigateOnArrowKey,
    type DatasheetColumnMeta,
    type DatasheetPage,
    type DatasheetSortSpec,
    type GridSelectionRange,
  } from './universalDatasheetGrid';
  import { IS_WEB_READONLY } from '../web/runtimeMode';

  interface CellDraftView {
    rawText: string;
    error: string;
  }

  const ROW_HEIGHT = 34;

  let {
    page,
    orderedColumns,
    sortSpecs = [],
    columnFilters = $bindable<Record<string, string>>({}),
    drafts = {},
    activeCell = $bindable<{ row: number; col: number } | null>(null),
    pageSize = $bindable(250),
    offset = 0,
    busy = false,
    draftCount = 0,
    invalidDraftCount = 0,
    onOpenPlot,
    onHeaderSort,
    onLoadPage,
    onSetCellDraft,
    onClearCellDraft,
    onBannerInfo,
  }: {
    page: DatasheetPage;
    orderedColumns: Array<{ meta: DatasheetColumnMeta; originalIndex: number }>;
    sortSpecs?: DatasheetSortSpec[];
    columnFilters?: Record<string, string>;
    drafts?: Record<string, CellDraftView>;
    activeCell?: { row: number; col: number } | null;
    pageSize?: number;
    offset?: number;
    busy?: boolean;
    draftCount?: number;
    invalidDraftCount?: number;
    onOpenPlot?: (plotNumber: string) => void;
    onHeaderSort: (colName: string, event: MouseEvent) => void;
    onLoadPage: (nextOffset: number) => void;
    onSetCellDraft: (rowIndex: number, displayColIndex: number, rawValue: string) => void;
    onClearCellDraft: (rowId: string, colName: string) => void;
    onBannerInfo: (title: string, message: string) => void;
  } = $props();

  let selectionAnchor = $state<{ row: number; col: number } | null>(null);
  let selectionRange = $state<GridSelectionRange | null>(null);
  let isMouseSelecting = $state(false);
  let scrollTop = $state(0);
  let viewportHeight = $state(520);
  let viewportEl = $state<HTMLDivElement | null>(null);

  $effect(() => {
    void page.tableKey;
    selectionAnchor = null;
    selectionRange = null;
    isMouseSelecting = false;
    scrollTop = 0;
  });

  const virtualSlice = $derived(computeVirtualWindow(scrollTop, viewportHeight, ROW_HEIGHT, page.rows.length, 8));
  const visibleRows = $derived(page.rows.slice(virtualSlice.startIndex, virtualSlice.endIndex));

  function focusGridInput(rowIdx: number, colIdx: number, extendSelection = false) {
    activeCell = { row: rowIdx, col: colIdx };
    selectionAnchor = extendSelection && selectionAnchor ? selectionAnchor : { row: rowIdx, col: colIdx };
    selectionRange = { startRow: selectionAnchor.row, endRow: rowIdx, startCol: selectionAnchor.col, endCol: colIdx };
    if (viewportEl) {
      const topTarget = rowIdx * ROW_HEIGHT;
      if (topTarget < viewportEl.scrollTop) viewportEl.scrollTop = topTarget;
      else if (topTarget + ROW_HEIGHT > viewportEl.scrollTop + viewportEl.clientHeight - 40) {
        viewportEl.scrollTop = topTarget + ROW_HEIGHT - viewportEl.clientHeight + 48;
      }
    }
    queueMicrotask(() => {
      const el = viewportEl?.querySelector<HTMLInputElement>(
        `input[data-grid-row="${rowIdx}"][data-grid-col="${colIdx}"]`
      );
      el?.focus();
      if (!extendSelection) el?.select();
    });
  }

  function handleCellKeyDown(event: KeyboardEvent, rowIdx: number, colIdx: number) {
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
      const el = event.currentTarget as HTMLInputElement | null;
      if (
        !shouldNavigateOnArrowKey(
          event.key,
          el?.selectionStart ?? null,
          el?.selectionEnd ?? null,
          el?.value.length ?? 0
        )
      )
        return;
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
    const row = event.key === 'Escape' ? page.rows[rowIdx] : undefined;
    const col = event.key === 'Escape' ? orderedColumns[colIdx] : undefined;
    if (row && col && `${row.rowId}::${col.meta.name}` in drafts) {
      event.preventDefault();
      onClearCellDraft(row.rowId, col.meta.name);
    }
  }

  function handleCopySelection(event: ClipboardEvent) {
    if (!selectionRange || !event.clipboardData) return;
    const norm = normalizeGridRange(selectionRange);
    if (norm.startRow === norm.endRow && norm.startCol === norm.endCol) return;
    const projectedRows = page.rows.map((r) => ({
      rowId: r.rowId,
      cells: orderedColumns.map((c) => r.cells[c.originalIndex]),
    }));
    const tsv = formatTSVRange(
      projectedRows,
      orderedColumns.map((c) => c.meta),
      norm,
      (rowId, colName) => drafts[`${rowId}::${colName}`]?.rawText
    );
    event.preventDefault();
    event.clipboardData.setData('text/plain', tsv);
    onBannerInfo(
      'Copied datasheet range',
      `Copied ${norm.endRow - norm.startRow + 1}x${norm.endCol - norm.startCol + 1} spreadsheet (tab-separated) block to clipboard.`
    );
  }

  function handlePasteIntoCell(event: ClipboardEvent, anchorRow: number, anchorCol: number) {
    if (typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY) return;
    if (!event.clipboardData) return;
    const text = event.clipboardData.getData('text/plain');
    if (!text.includes('\t') && !text.includes('\n')) return;
    const matrix = parseTSVClipboard(text);
    if (matrix.length === 0) return;
    event.preventDefault();
    let applied = 0;
    for (let rOff = 0; rOff < matrix.length && anchorRow + rOff < page.rows.length; rOff++) {
      for (let cOff = 0; cOff < matrix[rOff].length && anchorCol + cOff < orderedColumns.length; cOff++) {
        if (!isColumnEditable(page.tableKey, orderedColumns[anchorCol + cOff].meta, page.canEditMaster)) continue;
        onSetCellDraft(anchorRow + rOff, anchorCol + cOff, matrix[rOff][cOff]);
        applied++;
      }
    }
    selectionRange = {
      startRow: anchorRow,
      endRow: Math.min(page.rows.length - 1, anchorRow + matrix.length - 1),
      startCol: anchorCol,
      endCol: Math.min(orderedColumns.length - 1, anchorCol + (matrix[0]?.length ?? 1) - 1),
    };
    onBannerInfo(
      'Pasted datasheet cells',
      `Pasted ${applied} cell(s) from spreadsheet (tab-separated) clipboard. Review and click Save Edits to apply.`
    );
  }
</script>

<svelte:window onmouseup={() => (isMouseSelecting = false)} />

<div
  class="vpro-ds-viewport"
  bind:this={viewportEl}
  bind:clientHeight={viewportHeight}
  oncopy={handleCopySelection}
  onscroll={(e) => {
    scrollTop = e.currentTarget.scrollTop;
  }}
>
  <table class="vpro-ds-grid" role="grid" aria-rowcount={page.totalRows} data-datasheet-table={page.tableKey}>
    <thead>
      <tr class="vpro-ds-header-row">
        {#each orderedColumns as colEntry (colEntry.meta.name)}
          {@const sortIdx = sortSpecs.findIndex((s) => s.column.toLowerCase() === colEntry.meta.name.toLowerCase())}
          <th class:pinned={colEntry.meta.pinned} class:protected={colEntry.meta.protected} scope="col">
            <button
              type="button"
              class="vpro-ds-sort-btn"
              title="Click to sort; Shift+Click for multi-column sort"
              onclick={(e) => onHeaderSort(colEntry.meta.name, e)}
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
              data-column={colEntry.meta.name}
              aria-label={`Filter ${colEntry.meta.name}`}
              placeholder={colEntry.meta.pinned ? '=00337 or text' : 'Filter...'}
              bind:value={columnFilters[colEntry.meta.name]}
              onkeydown={(e) => {
                if (e.key === 'Enter') onLoadPage(0);
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
            {@const draft = drafts[`${row.rowId}::${colMeta.name}`]}
            {@const cellEditable = !IS_WEB_READONLY && isColumnEditable(page.tableKey, colMeta, page.canEditMaster)}
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
                  data-column={colMeta.name}
                  data-grid-row={rowIdx}
                  data-grid-col={colIdx}
                  value={displayVal}
                  readonly={!cellEditable}
                  aria-invalid={draft?.error ? 'true' : undefined}
                  title={draft?.error ||
                    `${colMeta.name} (${colMeta.declaredType || colMeta.kind})${colMeta.protected ? ' [Protected]' : ''}`}
                  onfocus={() => {
                    activeCell = { row: rowIdx, col: colIdx };
                    if (!selectionAnchor) selectionAnchor = { row: rowIdx, col: colIdx };
                    if (!selectionRange)
                      selectionRange = { startRow: rowIdx, endRow: rowIdx, startCol: colIdx, endCol: colIdx };
                  }}
                  onmousedown={(e) => {
                    isMouseSelecting = true;
                    activeCell = { row: rowIdx, col: colIdx };
                    if (!e.shiftKey || !selectionAnchor) selectionAnchor = { row: rowIdx, col: colIdx };
                    selectionRange = {
                      startRow: selectionAnchor.row,
                      endRow: rowIdx,
                      startCol: selectionAnchor.col,
                      endCol: colIdx,
                    };
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
                  oninput={(e) => onSetCellDraft(rowIdx, colIdx, e.currentTarget.value)}
                  onkeydown={(e) => handleCellKeyDown(e, rowIdx, colIdx)}
                  onpaste={(e) => handlePasteIntoCell(e, rowIdx, colIdx)}
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
          <td colspan={orderedColumns.length} class="vpro-ds-empty"> No rows matched the current filter criteria. </td>
        </tr>
      {/if}
    </tbody>
  </table>
</div>

<footer class="vpro-ds-footer">
  <div>
    Showing
    <strong>{page.rows.length ? page.offset + 1 : 0}</strong>–<strong>{page.offset + page.rows.length}</strong>
    of <strong>{page.totalRows.toLocaleString()}</strong> rows in
    <code>{page.tableName}</code>
    {#if invalidDraftCount > 0}
      <span class="vpro-ds-err-pill">{invalidDraftCount} invalid cell(s)</span>
    {/if}
  </div>

  <div class="vpro-ds-pager">
    <label>
      <span>Window</span>
      <select bind:value={pageSize} disabled={busy || draftCount > 0} onchange={() => onLoadPage(0)}>
        <option value={100}>100 rows</option>
        <option value={250}>250 rows</option>
        <option value={500}>500 rows</option>
        <option value={1000}>1,000 rows</option>
      </select>
    </label>
    <button
      type="button"
      class="vpro-btn-secondary"
      disabled={busy || offset === 0 || draftCount > 0}
      onclick={() => onLoadPage(Math.max(0, offset - pageSize))}
    >
      Previous
    </button>
    <button
      type="button"
      class="vpro-btn-secondary"
      disabled={busy || offset + page.rows.length >= page.totalRows || draftCount > 0}
      onclick={() => onLoadPage(offset + pageSize)}
    >
      Next
    </button>
  </div>
</footer>
