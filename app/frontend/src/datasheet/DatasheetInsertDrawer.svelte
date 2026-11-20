<script lang="ts">
  import { untrack } from 'svelte';
  import { formatError } from '../shared/readRequests';
  import {
    defaultDatasheetBackendPort,
    isColumnEditable,
    parseAndValidateCellInput,
    type DatasheetBackendPort,
    type DatasheetColumnMeta,
    type DatasheetPage,
    type DatasheetStorageCell,
  } from './universalDatasheetGrid';

  let {
    contextId,
    page,
    orderedColumns,
    seedPlotNumber = '',
    port = defaultDatasheetBackendPort,
    activeChildTableEditable = false,
    insertDrawerOpen = $bindable(false),
    insertBusy = $bindable(false),
    onError,
    onInserted,
  }: {
    contextId: string;
    page: DatasheetPage;
    orderedColumns: Array<{ meta: DatasheetColumnMeta; originalIndex: number }>;
    seedPlotNumber?: string;
    port?: DatasheetBackendPort;
    activeChildTableEditable?: boolean;
    insertDrawerOpen?: boolean;
    insertBusy?: boolean;
    onError: (msg: string) => void;
    onInserted: (banner: string) => Promise<void>;
  } = $props();

  let insertPlotNumber = $state(untrack(() => seedPlotNumber));
  let insertFieldDrafts = $state<Record<string, string>>({});

  $effect(() => {
    if (insertDrawerOpen) {
      insertPlotNumber = seedPlotNumber;
      insertFieldDrafts = {};
    }
  });

  const insertableColumns = $derived(
    orderedColumns
      .filter(
        (c) =>
          c.meta.name !== 'ID' &&
          c.meta.name !== 'PlotNumber' &&
          isColumnEditable(page.tableKey, c.meta, page.canEditMaster)
      )
      .slice(0, 6)
  );

  async function commitInsertChildRow() {
    if (!activeChildTableEditable || insertBusy) return;
    const plotNumber = insertPlotNumber.trim();
    if (!plotNumber) {
      onError('PlotNumber is required to insert a child row.');
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
        onError(parsed.error || `Invalid value for ${meta.name}.`);
        return;
      }
      insertCells[meta.name] = parsed.cell;
    }

    const fn = port.insertChildRow ?? defaultDatasheetBackendPort.insertChildRow;
    if (!fn) {
      onError('Child row insert port is unavailable.');
      return;
    }
    insertBusy = true;
    onError('');
    try {
      const res = await fn(contextId, {
        tableKey: page.tableKey,
        plotNumber,
        cells: insertCells,
      });
      insertDrawerOpen = false;
      insertFieldDrafts = {};
      await onInserted(
        `Inserted row ID ${res.id} for plot ${res.plotNumber} in ${res.tableName} (${res.auditRows} audit record(s)).`
      );
    } catch (err) {
      onError(`Insert child row failed: ${formatError(err)}`);
    } finally {
      insertBusy = false;
    }
  }
</script>

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
          oninput={(e) => {
            insertFieldDrafts = { ...insertFieldDrafts, [colEntry.meta.name]: e.currentTarget.value };
          }}
        />
      </label>
    {/each}
    <button
      type="button"
      class="vpro-btn-primary"
      data-commit-insert-row
      disabled={insertBusy}
      onclick={commitInsertChildRow}
    >
      {insertBusy ? 'Inserting...' : 'Commit New Row'}
    </button>
    <button
      type="button"
      class="vpro-btn-secondary"
      disabled={insertBusy}
      onclick={() => {
        insertDrawerOpen = false;
      }}
    >
      Cancel
    </button>
  </div>
</section>
