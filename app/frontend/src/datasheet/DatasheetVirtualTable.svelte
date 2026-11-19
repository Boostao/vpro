<script lang="ts">
  import {
    formatCellForEditor,
    isCellInRange,
    isColumnEditable,
    type DatasheetColumnMeta,
    type DatasheetPage,
    type DatasheetRow,
    type DatasheetSortSpec,
    type GridSelectionRange,
  } from './universalDatasheetGrid';

  interface CellDraftView {
    rawText: string;
    error: string;
  }

  let {
    page,
    orderedColumns,
    visibleRows,
    virtualSlice,
    rowHeight = 34,
    sortSpecs = [],
    columnFilters = $bindable<Record<string, string>>({}),
    drafts = {},
    activeCell = $bindable<{ row: number; col: number } | null>(null),
    selectionAnchor = $bindable<{ row: number; col: number } | null>(null),
    selectionRange = $bindable<GridSelectionRange | null>(null),
    isMouseSelecting = $bindable(false),
    scrollTop = $bindable(0),
    viewportHeight = $bindable(520),
    viewportEl = $bindable<HTMLDivElement | null>(null),
    pageSize = $bindable(250),
    offset = 0,
    busy = false,
    draftCount = 0,
    invalidDraftCount = 0,
    onOpenPlot,
    onHeaderSort,
    onLoadPage,
    onSetCellDraft,
    onCellKeyDown,
    onCellPaste,
  }: {
    page: DatasheetPage;
    orderedColumns: Array<{ meta: DatasheetColumnMeta; originalIndex: number }>;
    visibleRows: DatasheetRow[];
    virtualSlice: { startIndex: number; endIndex: number; topSpacerPx: number; bottomSpacerPx: number };
    rowHeight?: number;
    sortSpecs?: DatasheetSortSpec[];
    columnFilters?: Record<string, string>;
    drafts?: Record<string, CellDraftView>;
    activeCell?: { row: number; col: number } | null;
    selectionAnchor?: { row: number; col: number } | null;
    selectionRange?: GridSelectionRange | null;
    isMouseSelecting?: boolean;
    scrollTop?: number;
    viewportHeight?: number;
    viewportEl?: HTMLDivElement | null;
    pageSize?: number;
    offset?: number;
    busy?: boolean;
    draftCount?: number;
    invalidDraftCount?: number;
    onOpenPlot?: (plotNumber: string) => void;
    onHeaderSort: (colName: string, event: MouseEvent) => void;
    onLoadPage: (nextOffset: number) => void;
    onSetCellDraft: (rowIndex: number, displayColIndex: number, rawValue: string) => void;
    onCellKeyDown: (event: KeyboardEvent, rowIdx: number, colIdx: number) => void;
    onCellPaste: (event: ClipboardEvent, rowIdx: number, colIdx: number) => void;
  } = $props();
</script>

<div
  class="vpro-ds-viewport"
  bind:this={viewportEl}
  bind:clientHeight={viewportHeight}
  onscroll={e => {
    scrollTop = e.currentTarget.scrollTop;
  }}
>
  <table class="vpro-ds-grid" role="grid" aria-rowcount={page.totalRows} data-datasheet-table={page.tableKey}>
    <thead>
      <tr class="vpro-ds-header-row">
        {#each orderedColumns as colEntry (colEntry.meta.name)}
          {@const sortIdx = sortSpecs.findIndex(
            s => s.column.toLowerCase() === colEntry.meta.name.toLowerCase()
          )}
          <th class:pinned={colEntry.meta.pinned} class:protected={colEntry.meta.protected} scope="col">
            <button
              type="button"
              class="vpro-ds-sort-btn"
              title="Click to sort; Shift+Click for multi-column sort"
              onclick={e => onHeaderSort(colEntry.meta.name, e)}
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
              onkeydown={e => {
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
        <tr class="vpro-ds-row" style={`height:${rowHeight}px;`}>
          {#each orderedColumns as colEntry, colIdx (colEntry.meta.name)}
            {@const colMeta = colEntry.meta}
            {@const cell = row.cells[colEntry.originalIndex]}
            {@const draft = drafts[`${row.rowId}::${colMeta.name}`]}
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
                  data-column={colMeta.name}
                  data-grid-row={rowIdx}
                  data-grid-col={colIdx}
                  value={displayVal}
                  readonly={!cellEditable}
                  aria-invalid={draft?.error ? 'true' : undefined}
                  title={draft?.error || `${colMeta.name} (${colMeta.declaredType || colMeta.kind})${colMeta.protected ? ' [Protected]' : ''}`}
                  onfocus={() => {
                    activeCell = { row: rowIdx, col: colIdx };
                    if (!selectionAnchor) selectionAnchor = { row: rowIdx, col: colIdx };
                    if (!selectionRange) {
                      selectionRange = { startRow: rowIdx, endRow: rowIdx, startCol: colIdx, endCol: colIdx };
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
                      selectionRange = { startRow: rowIdx, endRow: rowIdx, startCol: colIdx, endCol: colIdx };
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
                  oninput={e => onSetCellDraft(rowIdx, colIdx, e.currentTarget.value)}
                  onkeydown={e => onCellKeyDown(e, rowIdx, colIdx)}
                  onpaste={e => onCellPaste(e, rowIdx, colIdx)}
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
