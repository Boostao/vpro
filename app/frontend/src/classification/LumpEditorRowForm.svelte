<script lang="ts">
  import { formatError } from '../shared/readRequests';
  import { validateLumpRowDraft, type LumpEditorPort, type SpeciesItem } from './lumpEditor';

  let {
    contextId,
    busy,
    operationHeld,
    port,
    selectedTable,
    selectedDbPath,
    isActiveProject,
    filterQuery = $bindable(),
    draftLumpCode = $bindable(),
    draftSppCode = $bindable(),
    draftUse = $bindable(),
    draftAllowUnlisted = $bindable(),
    editingSppCode = $bindable(),
    rowCount,
    bumpGeneration,
    isCurrent,
    onSetBusy,
    onError,
    onChanged,
    onSelectTable,
    onSetAllUse,
  }: {
    contextId: string;
    busy: boolean;
    operationHeld: boolean;
    port: LumpEditorPort;
    selectedTable: string;
    selectedDbPath: string;
    isActiveProject: boolean;
    filterQuery: string;
    draftLumpCode: string;
    draftSppCode: string;
    draftUse: boolean;
    draftAllowUnlisted: boolean;
    editingSppCode: string;
    rowCount: number;
    bumpGeneration: () => number;
    isCurrent: (reqGen: number, owner: string) => boolean;
    onSetBusy: (next: boolean) => void;
    onError: (msg: string) => void;
    onChanged: (tableName: string) => void;
    onSelectTable: (tableName: string, dbPath: string) => Promise<void>;
    onSetAllUse: (nextUse: boolean) => void;
  } = $props();

  let speciesSearchQuery = $state('');
  let speciesSearchResults = $state.raw<SpeciesItem[]>([]);
  let speciesSearching = $state(false);

  async function submitRow() {
    if (!isActiveProject) {
      onError('Select a local active-project lumping table (or Save As into the active project) before editing rows.');
      return;
    }
    const check = validateLumpRowDraft(draftLumpCode, draftSppCode);
    if (!check.valid) {
      onError(check.error);
      return;
    }
    if (busy || operationHeld || !contextId) return;
    const reqGen = bumpGeneration();
    const owner = contextId;
    const payload = $state.snapshot({
      lumpCode: check.lumpCode,
      sppCode: check.sppCode,
      use: draftUse,
      allowUnlisted: draftAllowUnlisted,
    });
    onError('');
    onSetBusy(true);
    try {
      if (editingSppCode) {
        await port.updateLumpRow(owner, selectedTable, editingSppCode, payload);
      } else {
        await port.upsertLumpRow(owner, selectedTable, payload);
      }
      if (!isCurrent(reqGen, owner)) return;
      draftSppCode = '';
      editingSppCode = '';
      onChanged(selectedTable);
    } catch (cause) {
      if (isCurrent(reqGen, owner)) onError(formatError(cause));
      onSetBusy(false);
      return;
    }
    onSetBusy(false);
    await onSelectTable(selectedTable, selectedDbPath);
  }

  async function lookupSpeciesCatalogue() {
    if (!port.searchSpecies || !speciesSearchQuery.trim() || speciesSearching) return;
    speciesSearching = true;
    onError('');
    try {
      const found = await port.searchSpecies(speciesSearchQuery.trim(), 25);
      speciesSearchResults = found ?? [];
    } catch (cause) {
      onError(`Species search failed: ${formatError(cause)}`);
    } finally {
      speciesSearching = false;
    }
  }
</script>

<div class="row-editor" aria-label="Add or update species lump mapping">
  <label>
    <span>Target LumpCode (&lt;=50)</span>
    <input type="text" bind:value={draftLumpCode} placeholder="CAREX" disabled={busy || operationHeld} />
  </label>
  <label>
    <span>Source SppCode (&lt;=8)</span>
    <input type="text" bind:value={draftSppCode} placeholder="CARESIT" disabled={busy || operationHeld} />
  </label>
  <label class="checkbox-label">
    <input type="checkbox" bind:checked={draftUse} disabled={busy || operationHeld} />
    <span>Active</span>
  </label>
  <label class="checkbox-label">
    <input type="checkbox" bind:checked={draftAllowUnlisted} disabled={busy || operationHeld} />
    <span>Allow unlisted code</span>
  </label>
  <button type="button" class="bcgov-btn-primary" disabled={busy || operationHeld} onclick={submitRow}>
    {editingSppCode ? `Update ${editingSppCode}` : 'Add / Upsert'}
  </button>
  {#if editingSppCode}
    <button
      type="button"
      class="bcgov-btn-secondary"
      onclick={() => {
        editingSppCode = '';
        draftSppCode = '';
      }}
    >
      Cancel Edit
    </button>
  {/if}
</div>

{#if port.searchSpecies}
  <div class="species-picker-panel" aria-label="Species Catalogue Picker">
    <div class="inline-row">
      <input
        type="search"
        aria-label="Search species catalogue by code or scientific name"
        bind:value={speciesSearchQuery}
        placeholder="Search Species Catalogue code or scientific name..."
        disabled={busy || operationHeld}
        onkeydown={(e) => {
          if (e.key === 'Enter') void lookupSpeciesCatalogue();
        }}
      />
      <button
        type="button"
        class="bcgov-btn-secondary"
        disabled={busy || operationHeld || speciesSearching || !speciesSearchQuery.trim()}
        onclick={lookupSpeciesCatalogue}
      >
        {speciesSearching ? 'Searching...' : 'Browse Species Catalogue'}
      </button>
    </div>
    {#if speciesSearchResults.length > 0}
      <div class="species-chip-list">
        {#each speciesSearchResults as item (item.code)}
          <button
            type="button"
            class="species-pick-btn"
            onclick={() => {
              draftSppCode = item.code;
              if (!draftLumpCode.trim()) draftLumpCode = item.code.slice(0, 7);
            }}
          >
            <strong class="mono">{item.code}</strong>
            <span>{item.scientificName || item.englishName}</span>
          </button>
        {/each}
      </div>
    {/if}
  </div>
{/if}

<div class="toolbar-row">
  <input
    type="search"
    aria-label="Filter species lump mappings by code or scientific name"
    bind:value={filterQuery}
    placeholder="Filter by code or scientific name..."
  />
  <button
    type="button"
    class="bcgov-btn-secondary"
    disabled={busy || operationHeld || rowCount === 0}
    onclick={() => onSetAllUse(true)}
  >
    Enable All
  </button>
  <button
    type="button"
    class="bcgov-btn-secondary"
    disabled={busy || operationHeld || rowCount === 0}
    onclick={() => onSetAllUse(false)}
  >
    Disable All
  </button>
</div>

<style>
  .inline-row,
  .toolbar-row,
  .row-editor {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    align-items: end;
    margin-bottom: 0.75rem;
  }
  .inline-row input,
  .toolbar-row input {
    flex: 1 1 160px;
    min-width: 0;
  }
  .row-editor label {
    display: grid;
    gap: 0.25rem;
    font-size: 0.8rem;
  }
  .species-picker-panel {
    border: 1px solid var(--vpro-border);
    background: var(--vpro-canvas);
    border-radius: 4px;
    padding: 0.55rem 0.7rem;
    margin-bottom: 0.75rem;
  }
  .species-chip-list {
    display: flex;
    flex-wrap: wrap;
    gap: 0.35rem;
    max-height: 140px;
    overflow-y: auto;
  }
  .species-pick-btn {
    display: inline-flex;
    gap: 0.35rem;
    align-items: center;
    padding: 0.25rem 0.5rem;
    border: 1px solid var(--vpro-border);
    background: var(--vpro-surface);
    border-radius: 3px;
    font-size: 0.76rem;
    color: var(--vpro-navy);
  }
  .checkbox-label {
    display: inline-flex;
    align-items: center;
    gap: 0.4rem;
    font-size: 0.83rem;
  }
  input:not([type='checkbox']) {
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
  .mono {
    font-family: var(--vpro-font-mono, var(--font-mono, monospace));
    font-variant-numeric: tabular-nums;
  }
  @media (pointer: coarse) {
    .bcgov-btn-primary,
    .bcgov-btn-secondary,
    input:not([type='checkbox']) {
      min-height: 44px;
    }
  }
</style>
