<script lang="ts">
  import { formatError } from '../shared/readRequests';
  import { notifications } from '../shell/notificationService.svelte';
  import { validateLumpBaseName, type LumpEditorPort, type LumpTableSummary } from './lumpEditor';

  let {
    contextId,
    busy,
    operationHeld,
    port,
    externalDbInput = $bindable(),
    tables,
    selectedTable,
    selectedDbPath,
    selectedSummary,
    bumpGeneration,
    isCurrent,
    onSetBusy,
    onError,
    onNotice,
    onSelectTable,
    onTableActivated,
    onTableDeleted,
    onChanged,
    onRefreshTables,
  }: {
    contextId: string;
    busy: boolean;
    operationHeld: boolean;
    port: LumpEditorPort;
    externalDbInput: string;
    tables: LumpTableSummary[];
    selectedTable: string;
    selectedDbPath: string;
    selectedSummary: LumpTableSummary | null;
    bumpGeneration: () => number;
    isCurrent: (reqGen: number, owner: string) => boolean;
    onSetBusy: (next: boolean) => void;
    onError: (msg: string) => void;
    onNotice: (msg: string) => void;
    onSelectTable: (tableName: string, dbPath: string) => void;
    onTableActivated: (tableName: string, dbPath: string) => void;
    onTableDeleted: (tableName: string) => void;
    onChanged: (tableName: string) => void;
    onRefreshTables: () => Promise<void>;
  } = $props();

  let newTableName = $state('');
  let saveAsTargetName = $state('');
  let pendingDeleteTable = $state('');

  async function createNewLump() {
    const check = validateLumpBaseName(newTableName);
    if (!check.valid) {
      onError(check.error);
      return;
    }
    if (busy || operationHeld || !contextId) return;
    const reqGen = bumpGeneration();
    const owner = contextId;
    onError('');
    onNotice('');
    onSetBusy(true);
    try {
      const created = await port.createLumpTable(owner, check.normalized);
      if (!isCurrent(reqGen, owner)) return;
      onTableActivated(created.tableName, created.databasePath);
      newTableName = '';
      onNotice(`Created ${created.tableName}.`);
      notifications.push({
        severity: 'success',
        category: 'general',
        source: 'Combine Species',
        title: `Created ${created.tableName}`,
        message: created.databasePath,
      });
      onChanged(created.tableName);
    } catch (cause) {
      if (isCurrent(reqGen, owner)) onError(formatError(cause));
      onSetBusy(false);
      return;
    }
    onSetBusy(false);
    await onRefreshTables();
  }

  async function saveAsLump() {
    if (!selectedTable) {
      onError('Select a source lump table first.');
      return;
    }
    const check = validateLumpBaseName(saveAsTargetName);
    if (!check.valid) {
      onError(check.error);
      return;
    }
    if (busy || operationHeld || !contextId) return;
    const reqGen = bumpGeneration();
    const owner = contextId;
    onError('');
    onNotice('');
    onSetBusy(true);
    try {
      const copied = await port.saveAsLumpTable(owner, selectedTable, selectedDbPath, check.normalized);
      if (!isCurrent(reqGen, owner)) return;
      onTableActivated(copied.tableName, copied.databasePath);
      saveAsTargetName = '';
      onNotice(`Copied to ${copied.tableName} (${copied.rowCount} rows).`);
      onChanged(copied.tableName);
    } catch (cause) {
      if (isCurrent(reqGen, owner)) onError(formatError(cause));
      onSetBusy(false);
      return;
    }
    onSetBusy(false);
    await onRefreshTables();
  }

  async function confirmDeleteSelectedTable() {
    if (!pendingDeleteTable || !selectedSummary?.isActiveProject || busy || operationHeld || !contextId) {
      return;
    }
    const targetName = pendingDeleteTable;
    const reqGen = bumpGeneration();
    const owner = contextId;
    onError('');
    onNotice('');
    onSetBusy(true);
    try {
      await port.deleteLumpTable(owner, targetName);
      if (!isCurrent(reqGen, owner)) return;
      pendingDeleteTable = '';
      onTableDeleted(targetName);
      onNotice(`Deleted lump table ${targetName}.`);
      onChanged('');
    } catch (cause) {
      if (isCurrent(reqGen, owner)) onError(formatError(cause));
      onSetBusy(false);
      return;
    }
    onSetBusy(false);
    await onRefreshTables();
  }
</script>

<aside class="bcgov-card">
  <h3>Discovered Lumping Tables</h3>
  <label class="field-block">
    <span>External .db paths (optional, comma-separated)</span>
    <input
      type="text"
      bind:value={externalDbInput}
      placeholder="/path/to/ExternalProject.db"
      disabled={busy || operationHeld}
    />
  </label>

  <ul class="lump-table-list">
    {#if tables.length === 0}
      <li class="empty-note">No lumping tables loaded. Click Refresh Catalog or create a new table below.</li>
    {/if}
    {#each tables as item (item.databasePath + '::' + item.tableName)}
      <li>
        <button
          type="button"
          class:selected={item.tableName === selectedTable && item.databasePath === selectedDbPath}
          onclick={() => onSelectTable(item.tableName, item.databasePath)}
        >
          <strong>{item.tableName}</strong>
          <span>{item.activeCount}/{item.rowCount} active | {item.isActiveProject ? 'Project' : 'External'}</span>
        </button>
      </li>
    {/each}
  </ul>

  <div class="stack-actions">
    <label class="field-block">
      <span>Create New Lump Table</span>
      <div class="inline-row">
        <input type="text" bind:value={newTableName} placeholder="e.g. Regional2026" disabled={busy || operationHeld} />
        <button
          type="button"
          class="bcgov-btn-primary"
          disabled={busy || operationHeld || !contextId}
          onclick={createNewLump}
        >
          Create
        </button>
      </div>
    </label>

    <label class="field-block">
      <span>Save Selected As</span>
      <div class="inline-row">
        <input
          type="text"
          bind:value={saveAsTargetName}
          placeholder="CopyName"
          disabled={busy || operationHeld || !selectedTable}
        />
        <button
          type="button"
          class="bcgov-btn-secondary"
          disabled={busy || operationHeld || !selectedTable}
          onclick={saveAsLump}
        >
          Save As
        </button>
      </div>
    </label>

    {#if selectedSummary?.isActiveProject}
      <div class="delete-table-box">
        {#if pendingDeleteTable === selectedSummary.tableName}
          <p class="delete-confirm-note">
            Confirm permanent deletion of <strong>{selectedSummary.tableName}</strong>?
          </p>
          <div class="inline-row">
            <button
              type="button"
              class="bcgov-btn-danger"
              disabled={busy || operationHeld}
              onclick={confirmDeleteSelectedTable}
            >
              Confirm Delete Table
            </button>
            <button type="button" class="bcgov-btn-secondary" onclick={() => (pendingDeleteTable = '')}>
              Cancel
            </button>
          </div>
        {:else}
          <button
            type="button"
            class="bcgov-btn-danger"
            disabled={busy || operationHeld || !selectedTable}
            onclick={() => (pendingDeleteTable = selectedSummary.tableName)}
          >
            Delete {selectedSummary.tableName}
          </button>
        {/if}
      </div>
    {/if}
  </div>
</aside>

<style>
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
  }
  .lump-table-list {
    list-style: none;
    padding: 0;
    margin: 0.75rem 0;
    display: grid;
    gap: 0.35rem;
    max-height: 240px;
    overflow-y: auto;
  }
  .lump-table-list button {
    width: 100%;
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0.5rem 0.65rem;
    border: 1px solid var(--vpro-border);
    border-radius: 4px;
    background: var(--vpro-canvas);
    text-align: left;
    font-size: 0.82rem;
    color: var(--vpro-ink);
  }
  .lump-table-list button.selected {
    background: rgba(26, 90, 150, 0.14);
    border-color: var(--vpro-navy);
    color: var(--vpro-navy);
  }
  .field-block {
    display: grid;
    gap: 0.3rem;
    font-size: 0.82rem;
    margin-bottom: 0.65rem;
  }
  .inline-row {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    align-items: end;
    margin-bottom: 0.75rem;
  }
  .inline-row input {
    flex: 1 1 160px;
    min-width: 0;
  }
  .delete-table-box {
    border-top: 1px solid var(--vpro-border);
    padding-top: 0.6rem;
    display: grid;
    gap: 0.4rem;
  }
  .delete-confirm-note {
    margin: 0;
    font-size: 0.8rem;
    color: var(--vpro-error);
  }
  .empty-note {
    font-size: 0.82rem;
    color: var(--vpro-ink-secondary);
    padding: 0.5rem 0;
  }
  input {
    padding: 0.45rem 0.6rem;
    border: 1px solid var(--vpro-border);
    border-radius: 4px;
    font-size: 0.85rem;
    max-width: 100%;
    background: var(--vpro-surface);
    color: var(--vpro-ink);
  }
  .bcgov-btn-primary {
    background: var(--vpro-navy);
    color: var(--vpro-surface);
    border: 1px solid var(--vpro-navy);
    border-bottom: 2px solid var(--vpro-gold);
    padding: 0.48rem 0.85rem;
    border-radius: 4px;
    font-weight: 600;
    font-size: 0.84rem;
  }
  .bcgov-btn-secondary {
    background: var(--vpro-surface);
    color: var(--vpro-navy);
    border: 1px solid var(--vpro-navy);
    padding: 0.48rem 0.85rem;
    border-radius: 4px;
    font-weight: 600;
    font-size: 0.84rem;
  }
  .bcgov-btn-danger {
    background: var(--vpro-surface);
    color: var(--vpro-error);
    border: 1px solid var(--vpro-error);
    padding: 0.48rem 0.85rem;
    border-radius: 4px;
    font-weight: 600;
    font-size: 0.84rem;
  }
  @media (pointer: coarse) {
    .bcgov-btn-primary,
    .bcgov-btn-secondary,
    .bcgov-btn-danger,
    input {
      min-height: 44px;
    }
  }
</style>
