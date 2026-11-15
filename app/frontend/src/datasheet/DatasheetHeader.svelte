<script lang="ts">
  import {
    ALL_DATASHEET_KEYS,
    isReadOnlyDatasheetTable,
    type DatasheetPage,
    type DatasheetTableInfo,
    type DatasheetTableKey,
  } from './universalDatasheetGrid';

  let {
    project = '',
    su = 'None',
    hierarchy = 'None',
    tables = [],
    activeTableKey,
    page = null,
    activeTableReadOnly = false,
    activeChildTableEditable = false,
    scopeToActiveSU = $bindable(false),
    globalSearch = $bindable(''),
    findDrawerOpen = $bindable(false),
    insertDrawerOpen = false,
    busy = false,
    saving = false,
    insertBusy = false,
    deleteBusy = false,
    hasActiveCell = false,
    draftCount = 0,
    validEditCount = 0,
    invalidDraftCount = 0,
    onApplyFilter,
    onOpenInsert,
    onRequestDelete,
    onDiscard,
    onSave,
    onSelectTable,
  }: {
    project?: string;
    su?: string;
    hierarchy?: string;
    tables?: DatasheetTableInfo[];
    activeTableKey: DatasheetTableKey;
    page?: DatasheetPage | null;
    activeTableReadOnly?: boolean;
    activeChildTableEditable?: boolean;
    scopeToActiveSU?: boolean;
    globalSearch?: string;
    findDrawerOpen?: boolean;
    insertDrawerOpen?: boolean;
    busy?: boolean;
    saving?: boolean;
    insertBusy?: boolean;
    deleteBusy?: boolean;
    hasActiveCell?: boolean;
    draftCount?: number;
    validEditCount?: number;
    invalidDraftCount?: number;
    onApplyFilter: () => void;
    onOpenInsert: () => void;
    onRequestDelete: () => void;
    onDiscard: () => void;
    onSave: () => void;
    onSelectTable: (key: DatasheetTableKey) => void;
  } = $props();
</script>

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
        onchange={onApplyFilter}
      />
      <span>Scope to Active SU</span>
    </label>

    <input
      type="search"
      class="vpro-ds-search"
      placeholder="Search all columns..."
      bind:value={globalSearch}
      onkeydown={e => {
        if (e.key === 'Enter') onApplyFilter();
      }}
    />
    <button type="button" class="vpro-btn-secondary" disabled={busy} onclick={onApplyFilter}>
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
        onclick={onOpenInsert}
      >
        {insertDrawerOpen ? 'Close Add Row' : '+ Add Row'}
      </button>
      <button
        type="button"
        class="vpro-btn-danger-outline"
        data-delete-child-row
        disabled={busy || saving || insertBusy || deleteBusy || !hasActiveCell}
        onclick={onRequestDelete}
      >
        Delete Selected Row
      </button>
    {/if}
    <button
      type="button"
      class="vpro-btn-secondary"
      disabled={draftCount === 0 || saving}
      onclick={onDiscard}
    >
      Discard ({draftCount})
    </button>
    <button
      type="button"
      class="vpro-btn-primary"
      disabled={validEditCount === 0 || invalidDraftCount > 0 || saving || activeTableReadOnly}
      onclick={onSave}
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
      onclick={() => onSelectTable(key)}
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
