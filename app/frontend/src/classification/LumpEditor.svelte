<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { formatError } from '../shared/readRequests';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import LumpEditorCreatePanel from './LumpEditorCreatePanel.svelte';
  import LumpEditorHeader from './LumpEditorHeader.svelte';
  import LumpEditorPresetsTab from './LumpEditorPresetsTab.svelte';
  import LumpEditorRowForm from './LumpEditorRowForm.svelte';
  import {
    defaultLumpEditorPort,
    groupLumpRowsByCode,
    type LumpEditorPort,
    type LumpImpactPreview,
    type LumpPresetInfo,
    type LumpRow,
    type LumpTableSummary,
  } from './lumpEditor';

  let {
    contextId,
    operationHeld = false,
    port = defaultLumpEditorPort,
    onBusyChange = () => {},
    onChanged = () => {},
  }: {
    contextId: string;
    operationHeld?: boolean;
    port?: LumpEditorPort;
    onBusyChange?: (busy: boolean) => void;
    onChanged?: (tableName: string) => void;
  } = $props();

  let activeTab = $state<'tables' | 'recipes'>('tables');
  let busy = $state(false);
  let error = $state('');
  let notice = $state('');

  let externalDbInput = $state('');
  let tables = $state.raw<LumpTableSummary[]>([]);
  let presets = $state.raw<LumpPresetInfo[]>([]);
  let selectedTable = $state('');
  let selectedDbPath = $state('');
  let rows = $state.raw<LumpRow[]>([]);
  let impact = $state.raw<LumpImpactPreview | null>(null);
  let filterQuery = $state('');

  let draftLumpCode = $state('');
  let draftSppCode = $state('');
  let draftUse = $state(true);
  let draftAllowUnlisted = $state(false);
  let editingSppCode = $state('');
  let generation = 0;

  function setBusyState(next: boolean) {
    busy = next;
    onBusyChange(next);
  }

  function cancelPending() {
    generation++;
    setBusyState(false);
  }

  const filteredRows = $derived.by(() => {
    const q = filterQuery.trim().toUpperCase();
    if (!q) return rows;
    return rows.filter(
      (r) =>
        r.lumpCode.toUpperCase().includes(q) ||
        r.sppCode.toUpperCase().includes(q) ||
        r.scientificName.toUpperCase().includes(q) ||
        r.englishName.toUpperCase().includes(q)
    );
  });

  const groupedRows = $derived.by(() => groupLumpRowsByCode(filteredRows));
  const selectedSummary = $derived.by(
    () => tables.find((t) => t.tableName === selectedTable && t.databasePath === selectedDbPath) ?? null
  );
  const baseLumpDbPath = $derived(
    IS_WEB_READONLY ? '' : selectedSummary && !selectedSummary.isActiveProject ? selectedSummary.databasePath : ''
  );

  async function refreshTables() {
    if (busy || operationHeld || !contextId) return;
    const reqGen = ++generation;
    const owner = contextId;
    error = '';
    setBusyState(true);
    try {
      const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
      const extPaths = webReadOnly
        ? []
        : externalDbInput
            .split(/[,;\n]+/)
            .map((s) => s.trim())
            .filter(Boolean);
      const [discovered, loadedPresets] = await Promise.all([
        port.discoverLumpTables(owner, $state.snapshot(extPaths)),
        port.listLumpPresets(),
      ]);
      if (reqGen !== generation || owner !== contextId) return;
      tables = discovered ?? [];
      presets = loadedPresets ?? [];
      if (
        tables.length > 0 &&
        !tables.some((t) => t.tableName === selectedTable && t.databasePath === selectedDbPath)
      ) {
        selectedTable = tables[0].tableName;
        selectedDbPath = tables[0].databasePath;
      }
      if (selectedTable) {
        const effectiveDbPath = webReadOnly ? '' : selectedDbPath;
        const [loadedRows, loadedImpact] = await Promise.all([
          port.getLumpTableRows(owner, selectedTable, effectiveDbPath),
          port.previewLumpImpact(owner, selectedTable, effectiveDbPath),
        ]);
        if (reqGen !== generation || owner !== contextId) return;
        rows = loadedRows ?? [];
        impact = loadedImpact;
      } else {
        rows = [];
        impact = null;
      }
    } catch (cause) {
      if (reqGen === generation) error = formatLumpError(cause);
    } finally {
      if (reqGen === generation) setBusyState(false);
    }
  }

  async function selectLumpTable(tableName: string, dbPath: string) {
    if (busy || operationHeld || !contextId) return;
    selectedTable = tableName;
    selectedDbPath = dbPath;
    editingSppCode = '';
    const reqGen = ++generation;
    const owner = contextId;
    error = '';
    setBusyState(true);
    try {
      const effectiveDbPath = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY ? '' : dbPath;
      const [loadedRows, loadedImpact] = await Promise.all([
        port.getLumpTableRows(owner, tableName, effectiveDbPath),
        port.previewLumpImpact(owner, tableName, effectiveDbPath),
      ]);
      if (reqGen !== generation || owner !== contextId) return;
      rows = loadedRows ?? [];
      impact = loadedImpact;
    } catch (cause) {
      if (reqGen === generation) error = formatLumpError(cause);
    } finally {
      if (reqGen === generation) setBusyState(false);
    }
  }

  async function mutateActiveRows(run: (owner: string) => Promise<void>) {
    if (typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY) return;
    if (!selectedSummary?.isActiveProject || busy || operationHeld || !contextId) return;
    const reqGen = ++generation;
    const owner = contextId;
    error = '';
    setBusyState(true);
    try {
      await run(owner);
      if (reqGen !== generation || owner !== contextId) return;
      onChanged(selectedTable);
    } catch (cause) {
      if (reqGen === generation) error = formatLumpError(cause);
      setBusyState(false);
      return;
    }
    setBusyState(false);
    await selectLumpTable(selectedTable, selectedDbPath);
  }

  function startEditRow(row: LumpRow) {
    editingSppCode = row.sppCode;
    draftLumpCode = row.lumpCode;
    draftSppCode = row.sppCode;
    draftUse = row.use;
    draftAllowUnlisted = row.sourceCatalog === 'Unlisted';
  }

  function formatLumpError(cause: unknown): string {
    return formatError(cause)
      .replace(/(?:RuntimeError|Error):\s*/gi, '')
      .trim();
  }

  let lastLoadedContextId = '';

  onMount(() => {
    if (contextId) {
      lastLoadedContextId = contextId;
      void refreshTables();
    }
  });

  $effect(() => {
    const cid = contextId;
    if (cid && cid !== lastLoadedContextId) {
      lastLoadedContextId = cid;
      cancelPending();
      void refreshTables();
    }
  });

  onDestroy(cancelPending);
</script>

<section
  class="bcgov-lump-editor"
  data-lump-editor
  data-tour="lump-editor-root"
  aria-label="Combine Species and Lumping Rules"
>
  <LumpEditorHeader
    bind:activeTab
    {busy}
    {operationHeld}
    {contextId}
    {notice}
    onRefreshTables={() => void refreshTables()}
  />

  {#if error}<p class="error" role="alert">{formatLumpError(error)}</p>{/if}

  {#if activeTab === 'tables'}
    <div class="lump-grid">
      <LumpEditorCreatePanel
        {contextId}
        {busy}
        {operationHeld}
        {port}
        bind:externalDbInput
        {tables}
        {selectedTable}
        {selectedDbPath}
        {selectedSummary}
        bumpGeneration={() => ++generation}
        isCurrent={(reqGen, owner) => reqGen === generation && owner === contextId}
        onSetBusy={setBusyState}
        onError={(msg) => (error = msg)}
        onNotice={(msg) => (notice = msg)}
        onSelectTable={(t, db) => void selectLumpTable(t, db)}
        onTableActivated={(t, db) => {
          selectedTable = t;
          selectedDbPath = db;
        }}
        onTableDeleted={(targetName) => {
          if (selectedTable === targetName) {
            selectedTable = '';
            selectedDbPath = '';
            rows = [];
            impact = null;
          }
        }}
        {onChanged}
        onRefreshTables={refreshTables}
      />

      <div class="bcgov-card">
        <h3>
          {selectedTable || 'No Lump Table Selected'}
          {#if selectedSummary}
            <span class="badge">{selectedSummary.isActiveProject ? 'Project Table' : 'External Table'}</span>
          {/if}
        </h3>

        {#if !IS_WEB_READONLY && selectedSummary?.isActiveProject}
          <LumpEditorRowForm
            {contextId}
            {busy}
            {operationHeld}
            {port}
            {selectedTable}
            {selectedDbPath}
            isActiveProject={selectedSummary.isActiveProject}
            bind:filterQuery
            bind:draftLumpCode
            bind:draftSppCode
            bind:draftUse
            bind:draftAllowUnlisted
            bind:editingSppCode
            rowCount={rows.length}
            bumpGeneration={() => ++generation}
            isCurrent={(reqGen, owner) => reqGen === generation && owner === contextId}
            onSetBusy={setBusyState}
            onError={(msg) => (error = msg)}
            {onChanged}
            onSelectTable={selectLumpTable}
            onSetAllUse={(nextUse) =>
              void mutateActiveRows((o) => port.setAllLumpRowsUse(o, selectedTable, nextUse).then(() => {}))}
          />
        {:else if IS_WEB_READONLY}
          <div class="lump-readonly-filter">
            <input
              type="search"
              aria-label="Filter lump rules"
              bind:value={filterQuery}
              placeholder="Filter LumpCode, SppCode, or scientific name..."
            />
          </div>
        {/if}

        <div class="table-scroll">
          <table>
            <thead>
              <tr>
                <th>LumpCode</th>
                <th>SppCode</th>
                <th>Scientific Name</th>
                <th>Species Catalogue</th>
                <th>Active</th>
                {#if !IS_WEB_READONLY}<th>Actions</th>{/if}
              </tr>
            </thead>
            <tbody>
              {#if groupedRows.length === 0}
                <tr>
                  <td colspan={IS_WEB_READONLY ? 5 : 6} class="empty-row">No species mappings in current selection.</td>
                </tr>
              {/if}
              {#each groupedRows as grp (grp.lumpCode)}
                {@const allGroupActive = grp.rows.length > 0 && grp.activeCount === grp.rows.length}
                <tr class="group-header-row">
                  <td colspan="4">
                    <strong class="mono">{grp.lumpCode}</strong>
                    <span class="group-count">({grp.activeCount}/{grp.rows.length} active)</span>
                  </td>
                  <td colspan={IS_WEB_READONLY ? 1 : 2}>
                    {#if !IS_WEB_READONLY && selectedSummary?.isActiveProject}
                      <button
                        type="button"
                        class="link-btn"
                        disabled={busy || operationHeld}
                        onclick={() =>
                          void mutateActiveRows(async (o) => {
                            for (const r of grp.rows)
                              await port.toggleLumpRow(o, selectedTable, r.sppCode, !allGroupActive);
                          })}
                      >
                        {allGroupActive ? 'Disable Group' : 'Enable Group'}
                      </button>
                    {/if}
                  </td>
                </tr>
                {#each grp.rows as row (row.sppCode)}
                  <tr>
                    <td class="mono">{row.lumpCode}</td>
                    <td class="mono">{row.sppCode}</td>
                    <td>{row.scientificName || 'Unlisted taxon'}</td>
                    <td>{row.sourceCatalog}</td>
                    <td>
                      <input
                        type="checkbox"
                        checked={row.use}
                        disabled={IS_WEB_READONLY || !selectedSummary?.isActiveProject || busy || operationHeld}
                        onchange={() =>
                          void mutateActiveRows((o) =>
                            port.toggleLumpRow(o, selectedTable, row.sppCode, !row.use).then(() => {})
                          )}
                        aria-label={`Toggle ${row.sppCode}`}
                      />
                    </td>
                    {#if !IS_WEB_READONLY}
                      <td>
                        {#if selectedSummary?.isActiveProject}
                          <button type="button" class="link-btn" onclick={() => startEditRow(row)}>Edit</button>
                          <button
                            type="button"
                            class="link-btn danger"
                            onclick={() =>
                              void mutateActiveRows((o) =>
                                port.deleteLumpRow(o, selectedTable, row.sppCode).then(() => {})
                              )}>Delete</button
                          >
                        {:else}
                          <span>Read-only external</span>
                        {/if}
                      </td>
                    {/if}
                  </tr>
                {/each}
              {/each}
            </tbody>
          </table>
        </div>
      </div>
    </div>

    {#if impact}
      <section class="bcgov-card impact-panel" aria-label="Project species folding impact preview">
        <h3>Live Project Folding Impact (Summed Cover Capped at {impact.coverCap}%)</h3>
        <div class="stat-strip">
          <div><span>Scoped Plots</span><strong>{impact.totalPlots}</strong></div>
          <div><span>Raw Species</span><strong>{impact.distinctRawSpecies}</strong></div>
          <div><span>Folded Species</span><strong>{impact.distinctFoldedSpecies}</strong></div>
          <div><span>Merged Plot-Layer Cells</span><strong>{impact.mergedCells}</strong></div>
          <div><span>Cells Capped at 99%</span><strong>{impact.cappedCells}</strong></div>
        </div>
      </section>
    {/if}
  {:else}
    <LumpEditorPresetsTab
      {contextId}
      {busy}
      {operationHeld}
      {port}
      {presets}
      baseLumpTable={selectedSummary?.tableName ?? ''}
      {baseLumpDbPath}
      bumpGeneration={() => ++generation}
      isCurrent={(reqGen, owner) => reqGen === generation && owner === contextId}
      onSetBusy={setBusyState}
      onError={(msg) => (error = msg)}
      onNotice={(msg) => (notice = msg)}
      onTableActivated={(t, db) => {
        selectedTable = t;
        selectedDbPath = db;
      }}
      {onChanged}
      onRefreshTables={refreshTables}
    />
  {/if}
</section>

<style>
  .bcgov-lump-editor {
    display: grid;
    gap: 1rem;
    min-width: 0;
    color: var(--vpro-ink);
  }
  .bcgov-card {
    background: var(--vpro-surface);
    border: 1px solid var(--vpro-border);
    border-top: 3px solid var(--vpro-navy);
    border-radius: 4px;
    padding: 1rem;
    min-width: 0;
  }
  .bcgov-card h3 {
    margin: 0 0 0.75rem;
    font-size: 1rem;
    color: var(--vpro-navy);
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.5rem;
  }
  .badge {
    background: var(--vpro-gold);
    color: var(--vpro-navy);
    padding: 0.1rem 0.45rem;
    border-radius: 3px;
    font-size: 0.75rem;
    font-weight: 700;
  }
  .lump-grid {
    display: grid;
    grid-template-columns: minmax(min(100%, 260px), 320px) minmax(0, 1fr);
    gap: 1rem;
  }
  .group-header-row {
    background: var(--vpro-canvas);
  }
  .group-count {
    font-size: 0.75rem;
    color: var(--vpro-ink-secondary);
    margin-left: 0.35rem;
  }
  .error {
    padding: 0.65rem 0.9rem;
    background: rgba(216, 41, 47, 0.08);
    border-left: 4px solid var(--vpro-error);
    color: var(--vpro-error);
    margin: 0;
    font-size: 0.85rem;
  }
  .stat-strip {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 140px), 1fr));
    gap: 0.75rem;
  }
  .stat-strip div {
    padding: 0.55rem 0.75rem;
    background: var(--vpro-canvas);
    border-left: 3px solid var(--vpro-gold);
    display: grid;
  }
  .stat-strip span {
    font-size: 0.75rem;
    color: var(--vpro-ink-secondary);
  }
  .stat-strip strong {
    font-size: 1.1rem;
    color: var(--vpro-navy);
    font-variant-numeric: tabular-nums;
  }
  .mono {
    font-family: var(--vpro-font-mono, var(--font-mono, monospace));
    font-variant-numeric: tabular-nums;
  }
  .link-btn {
    background: transparent;
    border: 0;
    color: var(--vpro-navy);
    text-decoration: underline;
    padding: 0.15rem 0.35rem;
    font-size: 0.8rem;
  }
  .link-btn.danger {
    color: var(--vpro-error);
  }
  .empty-row {
    font-size: 0.82rem;
    color: var(--vpro-ink-secondary);
    padding: 0.5rem 0;
  }
  .lump-readonly-filter {
    margin-bottom: 0.75rem;
  }
  .lump-readonly-filter input {
    width: 100%;
    padding: 0.45rem 0.6rem;
    border: 1px solid var(--vpro-border);
    border-radius: 4px;
    font-size: 0.85rem;
    background: var(--vpro-surface);
    color: var(--vpro-ink);
  }
  @media (max-width: 960px) {
    .lump-grid {
      grid-template-columns: minmax(0, 1fr);
    }
  }
</style>
