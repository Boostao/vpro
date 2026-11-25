<script lang="ts">
  import { onDestroy, onMount, untrack } from 'svelte';
  import { ReadRequests, formatError } from '../shared/readRequests';
  import * as gridLib from './universalDatasheetGrid';
  import type {
    DatasheetBackendPort,
    DatasheetCellEdit,
    DatasheetColumnMeta,
    DatasheetFilterSpec,
    DatasheetFindReplacePreview,
    DatasheetPage,
    DatasheetSortSpec,
    DatasheetTableInfo,
    DatasheetTableKey,
  } from './universalDatasheetGrid';
  import DatasheetHeader from './DatasheetHeader.svelte';
  import DatasheetVirtualTable from './DatasheetVirtualTable.svelte';
  import UniversalDatasheetDeleteModal from './UniversalDatasheetDeleteModal.svelte';

  let {
    contextId,
    project = '',
    su = 'None',
    hierarchy = 'None',
    initialTableKey = 'Env',
    port = gridLib.defaultDatasheetBackendPort,
    onBusyChange,
    onDirtyChange,
    onOpenPlot,
  }: {
    contextId: string;
    project?: string;
    su?: string;
    hierarchy?: string;
    initialTableKey?: DatasheetTableKey;
    port?: DatasheetBackendPort;
    onBusyChange?: (busy: boolean) => void;
    onDirtyChange?: (dirty: boolean) => void;
    onOpenPlot?: (plotNumber: string) => void;
  } = $props();

  type CellDraft = {
    rowId: string;
    column: string;
    rawText: string;
    before: DatasheetCellEdit['before'];
    after: DatasheetCellEdit['after'] | null;
    error: string;
  };

  const IS_WEB_READONLY = typeof __VPRO_WEB_READONLY__ !== 'undefined' && __VPRO_WEB_READONLY__ === true;
  const reads = new ReadRequests();
  const draftKey = (rowId: string, column: string) => `${rowId}::${column}`;

  let tables = $state.raw<DatasheetTableInfo[]>([]);
  let activeTableKey = $state<DatasheetTableKey>(untrack(() => initialTableKey));
  let page = $state.raw<DatasheetPage | null>(null);
  let pageSize = $state(250);
  let offset = $state(0);
  let sortSpecs = $state<DatasheetSortSpec[]>([]);
  let columnFilters = $state<Record<string, string>>({});
  let globalSearch = $state('');
  let scopeToActiveSU = $state(false);
  let drafts = $state<Record<string, CellDraft>>({});
  let activeCell = $state<{ row: number; col: number } | null>(null);
  let insertDrawerOpen = $state(false);
  let insertSeedPlot = $state('');
  let insertBusy = $state(false);
  let pendingDeleteRow = $state<{ rowId: string; plotNumber: string; id: number | null } | null>(null);
  let deleteBusy = $state(false);
  let workbenchEl = $state<HTMLElement | null>(null);
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
    page.columns.forEach((meta, originalIndex) => (meta.pinned ? pinned : rest).push({ meta, originalIndex }));
    return [...pinned, ...rest];
  });
  const draftEntries = $derived(Object.values(drafts));
  const invalidDraftCount = $derived(draftEntries.filter((d) => d.error !== '').length);
  const validEditCount = $derived(draftEntries.filter((d) => d.error === '' && d.after !== null).length);
  const activeTableReadOnly = $derived(
    IS_WEB_READONLY ||
      (page
        ? gridLib.isReadOnlyDatasheetTable(page.tableKey, page.readOnly)
        : gridLib.isReadOnlyDatasheetTable(activeTableKey))
  );
  const activeChildTableEditable = $derived(
    !!page && !activeTableReadOnly && gridLib.isEditableChildTable(page.tableKey)
  );
  const editableColumns = $derived(
    page ? page.columns.filter((c) => gridLib.isColumnEditable(page!.tableKey, c, page!.canEditMaster)) : []
  );

  $effect(() => {
    const anyBusy = busy || saving || findBusy || insertBusy || deleteBusy;
    onBusyChange?.(anyBusy || draftEntries.length > 0);
    onDirtyChange?.(!anyBusy && draftEntries.length > 0);
  });

  function notifyGrid(severity: 'success' | 'info' | 'error', title: string, message: string) {
    gridLib.notifications[severity](title, message, {
      category: 'entry',
      source: 'Datasheet Grid',
      contextTag: project || undefined,
    });
  }

  function handleWindowKeydown(event: KeyboardEvent) {
    if ((event.ctrlKey || event.metaKey) && !event.altKey && !event.shiftKey && event.key.toLowerCase() === 'f') {
      const searchBox = workbenchEl?.querySelector<HTMLInputElement>('input.vpro-ds-search, input.vpro-ds-col-filter');
      if (searchBox) {
        event.preventDefault();
        searchBox.focus();
        searchBox.select?.();
      }
      return;
    }
    if ((event.ctrlKey || event.metaKey) && !event.altKey && !event.shiftKey && event.key.toLowerCase() === 's') {
      event.preventDefault();
      if (page && !saving && !activeTableReadOnly && validEditCount > 0 && invalidDraftCount === 0) void saveDrafts();
    }
  }

  function buildActiveFilterSpecs(): DatasheetFilterSpec[] {
    const out: DatasheetFilterSpec[] = [];
    for (const [column, val] of Object.entries(columnFilters)) {
      const trimmed = val.trim();
      if (!trimmed) continue;
      if (trimmed === '=NULL') out.push({ column, op: 'is_null', value: '' });
      else if (trimmed === '!=NULL') out.push({ column, op: 'not_null', value: '' });
      else if (trimmed.startsWith('=')) out.push({ column, op: 'eq', value: trimmed.slice(1) });
      else out.push({ column, op: 'contains', value: trimmed });
    }
    return out;
  }

  const makePageReq = (tableKey: DatasheetTableKey, nextOffset: number) => ({
    tableKey,
    offset: Math.max(0, nextOffset),
    limit: pageSize,
    sort: $state.snapshot(sortSpecs),
    filters: buildActiveFilterSpecs(),
    globalSearch,
    scopeToActiveSU,
  });

  async function refreshTablesAndLoad(
    targetKey: DatasheetTableKey = activeTableKey,
    nextOffset = 0,
    options?: { preserveStatus?: boolean }
  ) {
    if (!contextId) return;
    const reqGen = ++generation;
    reads.cancelAll();
    busy = true;
    errorMessage = '';
    try {
      const listed = await reads.track((port.listAllTables ?? port.listTables)(contextId));
      if (reqGen !== generation) return;
      tables = listed ?? [];
      const chosen = tables.find((t) => t.key === targetKey);
      if (chosen && !chosen.available) {
        page = null;
        statusBanner = chosen.unavailableReason ?? `${chosen.key} is not available in this context.`;
        return;
      }
      const loaded = await reads.track(port.getPage(contextId, makePageReq(targetKey, nextOffset)));
      if (reqGen !== generation) return;
      page = loaded;
      offset = loaded.offset;
      if (!findColumn && loaded.columns.length > 0) {
        const firstEditable =
          loaded.columns.find((c) => !c.pinned && gridLib.isColumnEditable(loaded.tableKey, c, loaded.canEditMaster)) ??
          loaded.columns[0];
        findColumn = firstEditable.name;
      }
      if (!options?.preserveStatus) statusBanner = '';
    } catch (err) {
      if (reqGen === generation) {
        errorMessage = formatError(err);
        notifyGrid('error', 'Datasheet load failed', errorMessage);
      }
    } finally {
      if (reqGen === generation) busy = false;
    }
  }

  async function loadPageOnly(nextOffset = offset) {
    if (!contextId) return;
    const reqGen = ++generation;
    reads.cancelAll();
    busy = true;
    errorMessage = '';
    try {
      const loaded = await reads.track(port.getPage(contextId, makePageReq(activeTableKey, nextOffset)));
      if (reqGen !== generation) return;
      page = loaded;
      offset = loaded.offset;
    } catch (err) {
      if (reqGen === generation) {
        errorMessage = formatError(err);
        notifyGrid('error', 'Datasheet page load failed', errorMessage);
      }
    } finally {
      if (reqGen === generation) busy = false;
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
    insertDrawerOpen = false;
    pendingDeleteRow = null;
    findPreview = null;
    findColumn = '';
    void refreshTablesAndLoad(key, 0);
  }

  function setCellDraft(rowIndex: number, displayColIndex: number, rawValue: string) {
    if (typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY) return;
    const row = page?.rows[rowIndex];
    const colEntry = orderedColumns[displayColIndex];
    if (!page || !row || !colEntry) return;
    const colMeta = colEntry.meta;
    const originalCell = row.cells[colEntry.originalIndex];
    const key = draftKey(row.rowId, colMeta.name);
    const parsed = gridLib.parseAndValidateCellInput(page.tableKey, colMeta, rawValue, page.canEditMaster);
    if (!parsed.error && parsed.cell && gridLib.cellsSemanticallyEqual(originalCell, parsed.cell, colMeta)) {
      const { [key]: _removed, ...rest } = drafts;
      drafts = rest;
      return;
    }
    const before = structuredClone($state.snapshot(originalCell));
    drafts = {
      ...drafts,
      [key]: {
        rowId: row.rowId,
        column: colMeta.name,
        rawText: rawValue,
        before,
        after: parsed.cell,
        error: parsed.error,
      },
    };
  }

  function clearCellDraft(rowId: string, colName: string) {
    const key = draftKey(rowId, colName);
    if (key in drafts) {
      const { [key]: _removed, ...rest } = drafts;
      drafts = rest;
    }
  }

  function discardDrafts() {
    drafts = {};
    errorMessage = '';
    statusBanner = 'Discarded unsaved datasheet edits.';
    notifyGrid('info', 'Datasheet edits discarded', statusBanner);
  }

  async function saveDrafts() {
    if (typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY) return;
    if (!page || saving || validEditCount === 0) return;
    if (invalidDraftCount > 0) {
      errorMessage = `Resolve ${invalidDraftCount} invalid cell(s) before saving.`;
      notifyGrid('error', 'Datasheet save blocked by invalid cells', errorMessage);
      return;
    }
    saving = true;
    errorMessage = '';
    try {
      const edits: DatasheetCellEdit[] = draftEntries
        .filter((d) => d.after !== null)
        .map((d) => ({
          rowId: d.rowId,
          column: d.column,
          before: $state.snapshot(d.before),
          after: $state.snapshot(d.after!),
        }));
      const res = await port.applyEdits(contextId, { tableKey: page.tableKey, edits });
      drafts = {};
      statusBanner = `Saved ${res.updatedCells} cell(s) across ${res.updatedRows} row(s) (${res.auditRows} audit record(s)).`;
      notifyGrid('success', `Saved ${page.tableName} edits`, statusBanner);
      await refreshTablesAndLoad(activeTableKey, offset, { preserveStatus: true });
    } catch (err) {
      errorMessage = `Save failed (no changes were saved): ${formatError(err)}`;
      notifyGrid('error', 'Datasheet save failed', errorMessage);
    } finally {
      saving = false;
    }
  }

  function handleHeaderSort(colName: string, event: MouseEvent) {
    sortSpecs = gridLib.toggleMultiColumnSort(sortSpecs, colName, event.shiftKey);
    offset = 0;
    void loadPageOnly(0);
  }

  async function runFindPreview() {
    if (!page || !findColumn) return;
    findBusy = true;
    errorMessage = '';
    try {
      const filters = buildActiveFilterSpecs();
      findPreview = await reads.track(
        port.previewFindReplace(contextId, {
          tableKey: page.tableKey,
          column: findColumn,
          findText,
          replaceText,
          matchCase: findMatchCase,
          exactCell: findExactCell,
          filters,
          globalSearch,
          scopeToActiveSU,
          maxPreview: 500,
        })
      );
    } catch (err) {
      errorMessage = `Find/Replace preview failed: ${formatError(err)}`;
      notifyGrid('error', 'Find/Replace preview failed', errorMessage);
    } finally {
      findBusy = false;
    }
  }

  async function applyFindReplaceValid() {
    if (typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY) return;
    if (!page || !findPreview || findPreview.validCount === 0) return;
    const validEdits = findPreview.items.filter((i) => !i.validationError).map((i) => $state.snapshot(i.edit));
    if (validEdits.length === 0) return;
    saving = true;
    errorMessage = '';
    try {
      const res = await port.applyEdits(contextId, { tableKey: page.tableKey, edits: validEdits });
      findPreview = null;
      statusBanner = `Applied ${res.updatedCells} replacement(s) on ${page.tableName} (${res.auditRows} audit record(s)).`;
      notifyGrid('success', `Find/Replace applied on ${page.tableName}`, statusBanner);
      await refreshTablesAndLoad(activeTableKey, offset, { preserveStatus: true });
    } catch (err) {
      errorMessage = `Find/Replace failed (no changes were saved): ${formatError(err)}`;
      notifyGrid('error', 'Find/Replace failed', errorMessage);
    } finally {
      saving = false;
    }
  }

  function readSelectedColText(rowIdx: number, colName: string): string {
    const row = page?.rows[rowIdx];
    const col = orderedColumns.find((c) => c.meta.name === colName);
    return row && col && page ? gridLib.formatCellForEditor(row.cells[col.originalIndex], col.meta) : '';
  }

  function openInsertChildDrawer() {
    if (!page || !activeChildTableEditable) return;
    insertSeedPlot = activeCell ? readSelectedColText(activeCell.row, 'PlotNumber') : '';
    pendingDeleteRow = null;
    insertDrawerOpen = true;
    errorMessage = '';
  }

  function requestDeleteSelectedRow() {
    if (!page || !activeChildTableEditable || !activeCell || !page.rows[activeCell.row]) return;
    const row = page.rows[activeCell.row];
    const idStr = readSelectedColText(activeCell.row, 'ID').trim();
    insertDrawerOpen = false;
    pendingDeleteRow = {
      rowId: row.rowId,
      plotNumber: readSelectedColText(activeCell.row, 'PlotNumber'),
      id: /^-?\d+$/.test(idStr) ? Number(idStr) : null,
    };
  }

  async function confirmDeleteSelectedRow() {
    if (!page || !activeChildTableEditable || !pendingDeleteRow || deleteBusy) return;
    const fn = port.deleteChildRow ?? gridLib.defaultDatasheetBackendPort.deleteChildRow;
    if (!fn) {
      errorMessage = 'Child row delete port is unavailable.';
      notifyGrid('error', 'Delete child row failed', errorMessage);
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
      statusBanner = `Deleted row ID ${res.deletedId} (plot ${res.plotNumber}) from ${res.tableName} (${res.auditRows} audit record(s)).`;
      notifyGrid('success', `Deleted row from ${res.tableName}`, statusBanner);
      await refreshTablesAndLoad(activeTableKey, offset, { preserveStatus: true });
    } catch (err) {
      errorMessage = `Delete child row failed: ${formatError(err)}`;
      notifyGrid('error', 'Delete child row failed', errorMessage);
    } finally {
      deleteBusy = false;
    }
  }

  onMount(() => {
    if (contextId) void refreshTablesAndLoad(activeTableKey, 0);
  });
  onDestroy(() => {
    generation++;
    reads.cancelAll();
    onDirtyChange?.(false);
    onBusyChange?.(false);
  });
</script>

<svelte:window onkeydown={handleWindowKeydown} />

<section
  bind:this={workbenchEl}
  class="vpro-datasheet-workbench"
  data-tour="datasheet-grid-root"
  aria-label="Universal Project Datasheet Grid"
>
  <div
    data-workbench-sticky-bar
    class="sticky top-0 z-20 space-y-2 border-b border-vpro-border bg-white/95 py-2 backdrop-blur-xs"
  >
    <DatasheetHeader
      {project}
      {su}
      {hierarchy}
      {tables}
      {activeTableKey}
      {page}
      {activeTableReadOnly}
      {activeChildTableEditable}
      bind:scopeToActiveSU
      bind:globalSearch
      bind:findDrawerOpen
      {insertDrawerOpen}
      {busy}
      {saving}
      {insertBusy}
      {deleteBusy}
      hasActiveCell={!!(activeCell && page?.rows[activeCell.row])}
      draftCount={draftEntries.length}
      {validEditCount}
      {invalidDraftCount}
      onApplyFilter={() => void loadPageOnly(0)}
      onOpenInsert={openInsertChildDrawer}
      onRequestDelete={requestDeleteSelectedRow}
      onDiscard={discardDrafts}
      onSave={() => void saveDrafts()}
      onSelectTable={selectTable}
    />
  </div>

  <UniversalDatasheetDeleteModal
    {contextId}
    {page}
    {orderedColumns}
    {editableColumns}
    {port}
    {activeTableReadOnly}
    {activeChildTableEditable}
    {errorMessage}
    {pendingDeleteRow}
    {deleteBusy}
    {insertSeedPlot}
    bind:insertDrawerOpen
    bind:insertBusy
    {findDrawerOpen}
    bind:findColumn
    bind:findText
    bind:replaceText
    bind:findMatchCase
    bind:findExactCell
    {findPreview}
    {findBusy}
    {saving}
    onconfirmdelete={() => void confirmDeleteSelectedRow()}
    oncanceldelete={() => (pendingDeleteRow = null)}
    oninserterror={(msg) => {
      errorMessage = msg;
      if (msg) notifyGrid('error', 'Insert child row failed', msg);
    }}
    oninserted={async (banner) => {
      statusBanner = banner;
      notifyGrid('success', `Inserted row into ${page?.tableName ?? activeTableKey}`, banner);
      await refreshTablesAndLoad(activeTableKey, offset, { preserveStatus: true });
    }}
    onrunfindpreview={runFindPreview}
    onapplyfindreplace={applyFindReplaceValid}
  />

  {#if page}
    <DatasheetVirtualTable
      {page}
      {orderedColumns}
      {sortSpecs}
      bind:columnFilters
      {drafts}
      bind:activeCell
      bind:pageSize
      {offset}
      {busy}
      draftCount={draftEntries.length}
      {invalidDraftCount}
      {onOpenPlot}
      onHeaderSort={handleHeaderSort}
      onLoadPage={(next) => void loadPageOnly(next)}
      onSetCellDraft={setCellDraft}
      onClearCellDraft={clearCellDraft}
      onBannerInfo={(title, banner) => {
        statusBanner = banner;
        notifyGrid('info', title, banner);
      }}
    />
  {/if}
</section>
