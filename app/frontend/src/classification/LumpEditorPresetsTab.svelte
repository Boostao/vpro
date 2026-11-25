<script lang="ts">
  import { formatError } from '../shared/readRequests';
  import { notifications } from '../shell/notificationService.svelte';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import {
    parseGenusRollupTokens,
    validateLumpBaseName,
    type LumpEditorPort,
    type LumpMaterializeResult,
    type LumpPresetInfo,
    type LumpSpec,
    type LumpSpecPreview,
  } from './lumpEditor';

  let {
    contextId,
    busy,
    operationHeld,
    port,
    presets,
    baseLumpTable,
    baseLumpDbPath,
    bumpGeneration,
    isCurrent,
    onSetBusy,
    onError,
    onNotice,
    onTableActivated,
    onChanged,
    onRefreshTables,
  }: {
    contextId: string;
    busy: boolean;
    operationHeld: boolean;
    port: LumpEditorPort;
    presets: LumpPresetInfo[];
    baseLumpTable: string;
    baseLumpDbPath: string;
    bumpGeneration: () => number;
    isCurrent: (reqGen: number, owner: string) => boolean;
    onSetBusy: (next: boolean) => void;
    onError: (msg: string) => void;
    onNotice: (msg: string) => void;
    onTableActivated: (tableName: string, dbPath: string) => void;
    onChanged: (tableName: string) => void;
    onRefreshTables: () => Promise<void>;
  } = $props();

  let specPreset = $state('BEC_Provincial_Correlation_2026');
  let collapseInfraspecific = $state(true);
  let collapseSeedlingAndDead = $state(true);
  let genusRollupsText = $state('CARE*, SALI*, SPHA*, CLAD*');
  let rollupMosses = $state(false);
  let rollupLiverworts = $state(false);
  let rollupLichens = $state(false);
  let scopeToProject = $state(true);
  let materializeName = $state('BEC2026');
  let replaceExisting = $state(true);
  let specPreview = $state.raw<LumpSpecPreview | null>(null);
  let lastMaterialized = $state.raw<LumpMaterializeResult | null>(null);

  function buildCurrentSpec(): LumpSpec {
    const lifeforms: number[] = [];
    if (rollupMosses) lifeforms.push(9);
    if (rollupLiverworts) lifeforms.push(10);
    if (rollupLichens) lifeforms.push(11);
    return {
      preset: specPreset,
      collapseInfraspecific,
      collapseSeedlingAndDeadSuffixes: collapseSeedlingAndDead,
      genusRollups: parseGenusRollupTokens(genusRollupsText),
      nonVascularLifeforms: lifeforms,
      baseLumpTable,
      baseLumpDbPath,
      scopeToProjectSpecies: scopeToProject,
    };
  }

  function applyPresetSelection(presetID: string) {
    specPreset = presetID;
    const found = presets.find((p) => p.id === presetID);
    if (found) {
      collapseInfraspecific = found.spec.collapseInfraspecific;
      collapseSeedlingAndDead = found.spec.collapseSeedlingAndDeadSuffixes;
      genusRollupsText = (found.spec.genusRollups ?? []).join(', ');
    }
  }

  async function runSpecPreview() {
    if (busy || operationHeld || !contextId) return;
    const reqGen = bumpGeneration();
    const owner = contextId;
    const specSnapshot = $state.snapshot(buildCurrentSpec());
    onError('');
    onSetBusy(true);
    try {
      const result = await port.previewLumpSpec(owner, specSnapshot);
      if (!isCurrent(reqGen, owner)) return;
      specPreview = result;
    } catch (cause) {
      if (isCurrent(reqGen, owner)) onError(formatError(cause));
    } finally {
      if (isCurrent(reqGen, owner)) onSetBusy(false);
    }
  }

  async function runMaterializeSpec() {
    if (typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY) return;
    const check = validateLumpBaseName(materializeName);
    if (!check.valid) {
      onError(check.error);
      return;
    }
    if (busy || operationHeld || !contextId) return;
    const reqGen = bumpGeneration();
    const owner = contextId;
    const specSnapshot = $state.snapshot(buildCurrentSpec());
    onError('');
    onNotice('');
    onSetBusy(true);
    try {
      const res = await port.materializeLumpSpec(owner, check.normalized, specSnapshot, replaceExisting);
      if (!isCurrent(reqGen, owner)) return;
      lastMaterialized = res;
      onTableActivated(res.table.tableName, res.table.databasePath);
      onNotice(`Saved ${res.rowsWritten} folding rules into ${res.table.tableName}.`);
      notifications.push({
        severity: 'success',
        category: 'background',
        source: 'Lumping Presets',
        title: `Saved ${res.rowsWritten} rules into ${res.table.tableName}`,
        message: res.table.databasePath,
      });
      onChanged(res.table.tableName);
    } catch (cause) {
      if (isCurrent(reqGen, owner)) onError(formatError(cause));
      onSetBusy(false);
      return;
    }
    onSetBusy(false);
    await onRefreshTables();
  }
</script>

<div class="bcgov-card">
  <h3>Species Lumping Presets &amp; Rollup Rules</h3>
  <div class="recipe-grid">
    <label class="field-block">
      <span>Provincial Preset</span>
      <select
        value={specPreset}
        onchange={(e) => applyPresetSelection(e.currentTarget.value)}
        disabled={busy || operationHeld}
      >
        <option value="BEC_Provincial_Correlation_2026">BEC_Provincial_Correlation_2026</option>
        <option value="">Custom Recipe Only</option>
      </select>
    </label>

    <label class="field-block">
      <span>Wildcard Genus Rollups</span>
      <input
        type="text"
        bind:value={genusRollupsText}
        placeholder="CARE*, SALI*, SPHA*, CLAD*"
        disabled={busy || operationHeld}
      />
    </label>

    <div class="checkbox-group">
      <label class="checkbox-label">
        <input type="checkbox" bind:checked={collapseInfraspecific} disabled={busy || operationHeld} />
        <span>Collapse 8-char infraspecifics (1..8 -&gt; 7-char parent)</span>
      </label>
      <label class="checkbox-label">
        <input type="checkbox" bind:checked={collapseSeedlingAndDead} disabled={busy || operationHeld} />
        <span>Collapse seedling &amp; dead codes (_D / _X)</span>
      </label>
      <label class="checkbox-label">
        <input type="checkbox" bind:checked={rollupMosses} disabled={busy || operationHeld} />
        <span>Rollup Lifeform 9 (Mosses) to genus</span>
      </label>
      <label class="checkbox-label">
        <input type="checkbox" bind:checked={rollupLiverworts} disabled={busy || operationHeld} />
        <span>Rollup Lifeform 10 (Liverworts) to genus</span>
      </label>
      <label class="checkbox-label">
        <input type="checkbox" bind:checked={rollupLichens} disabled={busy || operationHeld} />
        <span>Rollup Lifeform 11 (Lichens) to genus</span>
      </label>
      <label class="checkbox-label">
        <input type="checkbox" bind:checked={scopeToProject} disabled={busy || operationHeld} />
        <span>Scope rules to species present in active project</span>
      </label>
    </div>

    <div class="inline-row">
      <button
        type="button"
        class={IS_WEB_READONLY ? 'bcgov-btn-primary' : 'bcgov-btn-secondary'}
        disabled={busy || operationHeld || !contextId}
        onclick={runSpecPreview}
      >
        Preview Lumping Impact
      </button>
      {#if !IS_WEB_READONLY}
        <input
          type="text"
          aria-label="Target lump table name"
          bind:value={materializeName}
          placeholder="Target name (e.g. BEC2026)"
          disabled={busy || operationHeld}
        />
        <label class="checkbox-label">
          <input type="checkbox" bind:checked={replaceExisting} disabled={busy || operationHeld} />
          <span>Overwrite if exists</span>
        </label>
        <button
          type="button"
          class="bcgov-btn-primary"
          disabled={busy || operationHeld || !contextId}
          onclick={runMaterializeSpec}
        >
          Build Lumping Table
        </button>
      {/if}
    </div>
  </div>

  {#if specPreview}
    <div class="spec-results">
      <p>
        <strong>Compiled Rules:</strong>
        {specPreview.rows.length} mappings |
        <strong>Raw -&gt; Folded Species:</strong>
        {specPreview.impact.distinctRawSpecies} -&gt; {specPreview.impact.distinctFoldedSpecies} |
        <strong>Merged Cells:</strong>
        {specPreview.impact.mergedCells} |
        <strong>99%-Capped Cells:</strong>
        {specPreview.impact.cappedCells}
      </p>
      <div class="table-scroll">
        <table>
          <thead>
            <tr>
              <th>LumpCode</th>
              <th>SppCode</th>
              <th>Scientific Name</th>
              <th>Rule Provenance</th>
            </tr>
          </thead>
          <tbody>
            {#each specPreview.rows.slice(0, 100) as row (row.sppCode)}
              <tr>
                <td class="mono">{row.lumpCode}</td>
                <td class="mono">{row.sppCode}</td>
                <td>{row.scientificName}</td>
                <td>{row.ruleOrigin || 'recipe'}</td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    </div>
  {/if}
  {#if lastMaterialized}
    <p class="bcgov-notice">
      Saved {lastMaterialized.rowsWritten} rows into {lastMaterialized.table.tableName}.
    </p>
  {/if}
</div>

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
  .inline-row input:not([type='checkbox']) {
    flex: 1 1 160px;
    min-width: 0;
  }
  .checkbox-group {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 240px), 1fr));
    gap: 0.45rem;
    margin: 0.65rem 0;
  }
  .checkbox-label {
    display: inline-flex;
    align-items: center;
    gap: 0.4rem;
    font-size: 0.83rem;
  }
  input:not([type='checkbox']),
  select {
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
  .bcgov-notice {
    padding: 0.65rem 0.9rem;
    background: var(--vpro-canvas);
    border-left: 4px solid var(--vpro-gold);
    color: var(--vpro-navy);
    margin: 0.75rem 0 0;
    font-size: 0.85rem;
  }
  .mono {
    font-family: var(--vpro-font-mono, var(--font-mono, monospace));
    font-variant-numeric: tabular-nums;
  }
  @media (pointer: coarse) {
    .bcgov-btn-primary,
    .bcgov-btn-secondary,
    input:not([type='checkbox']),
    select {
      min-height: 44px;
    }
  }
</style>
