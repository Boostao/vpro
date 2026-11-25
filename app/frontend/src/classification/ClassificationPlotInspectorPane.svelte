<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { ReadRequests, formatError } from '../shared/readRequests';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import ClassificationUserSUPanel from './ClassificationUserSUPanel.svelte';
  import {
    isValidBECUnitMask,
    type BECUnitPickerChoice,
    type BECZoneSummary,
    type ClassificationBackendPort,
    type PlotInspectorSummary,
    type UserSiteUnitEntry,
  } from './classificationExplorer';

  interface Props {
    effectiveContextId: string;
    project: string;
    port: ClassificationBackendPort;
    inspectedPlot: PlotInspectorSummary | null;
    selectedPlots: string[];
    mutating: boolean;
    onRequestSUSync?: (direction: 'su_to_env' | 'env_to_su') => void;
    onAssignPlots: (plots: string[], targetUnit: string) => void;
    onMutatingChange: (v: boolean) => void;
    onError: (msg: string) => void;
    onStatus: (msg: string) => void;
  }

  let {
    effectiveContextId,
    project,
    port,
    inspectedPlot,
    selectedPlots,
    mutating,
    onRequestSUSync,
    onAssignPlots,
    onMutatingChange,
    onError,
    onStatus,
  }: Props = $props();

  const reads = new ReadRequests();

  let rightPaneTab = $state<'bec_picker' | 'user_su_list'>('bec_picker');
  let customTargetUnit = $state('');
  let becSearchMode = $state<'combined' | 'becdb_v13'>('combined');
  let becZones = $state.raw<BECZoneSummary[]>([]);
  let becQuery = $state('');
  let becZone = $state('');
  let becSubZone = $state('');
  let becChoices = $state.raw<BECUnitPickerChoice[]>([]);
  let userSiteUnits = $state.raw<UserSiteUnitEntry[]>([]);

  $effect(() => {
    if (inspectedPlot?.zone && !becZone) {
      becZone = inspectedPlot.zone;
    }
  });

  $effect(() => {
    if (effectiveContextId) {
      void refreshBECPicker();
      void loadUserSiteUnitList();
    }
  });

  async function queryBECChoices(): Promise<BECUnitPickerChoice[]> {
    const zoneArg = becZone.trim() || null;
    const subZoneArg = becSubZone.trim() || null;
    const queryArg = becQuery.trim();
    if (becSearchMode === 'becdb_v13' && port.searchBECSiteSeries) {
      const series = await reads.track(port.searchBECSiteSeries(zoneArg, subZoneArg, queryArg, 120));
      return series ?? [];
    }
    const picker = await reads.track(
      port.searchBECUnitPicker(effectiveContextId, {
        query: queryArg,
        zone: becZone,
        subZone: becSubZone,
        limit: 80,
      })
    );
    const baseChoices = picker ?? [];
    if (port.searchBECSiteSeries && (zoneArg || subZoneArg || queryArg)) {
      try {
        const series = await reads.track(port.searchBECSiteSeries(zoneArg, subZoneArg, queryArg, 120));
        const seen = new Set(baseChoices.map((c) => c.siteSeries));
        const merged = [...baseChoices];
        for (const item of series ?? []) {
          if (item.siteSeries && !seen.has(item.siteSeries)) {
            seen.add(item.siteSeries);
            merged.push(item);
          }
        }
        return merged;
      } catch {
        return baseChoices;
      }
    }
    return baseChoices;
  }

  async function loadBECZonesCatalog() {
    if (!port.listBECZones) return;
    try {
      const zones = await reads.track(port.listBECZones());
      becZones = zones ?? [];
    } catch {
      // Optional zone datalist; keep typing functional even when catalogue offline.
    }
  }

  async function refreshBECPicker() {
    if (!effectiveContextId) return;
    try {
      becChoices = await queryBECChoices();
    } catch (err) {
      onError(formatError(err));
    }
  }

  async function loadUserSiteUnitList() {
    if (!effectiveContextId || !port.listUserSiteUnitList) return;
    try {
      const entries = await reads.track(port.listUserSiteUnitList(effectiveContextId));
      userSiteUnits = entries ?? [];
    } catch (err) {
      onError(`Could not load personal site unit list: ${formatError(err)}`);
    }
  }

  onMount(() => {
    void loadBECZonesCatalog();
  });

  onDestroy(() => {
    reads.cancelAll();
  });
</script>

<section class="vpro-cls-card">
  <div class="vpro-cls-card-head">
    <h3>Plot Environment &amp; Veg Inspector</h3>
    {#if !IS_WEB_READONLY && onRequestSUSync}
      <div class="vpro-cls-sync-btns">
        <button type="button" class="vpro-btn-mini" onclick={() => onRequestSUSync('su_to_env')}>SU -&gt; Env</button>
        <button type="button" class="vpro-btn-mini" onclick={() => onRequestSUSync('env_to_su')}>Env -&gt; SU</button>
      </div>
    {/if}
  </div>

  {#if inspectedPlot}
    <dl class="vpro-cls-kv">
      <div>
        <dt>Plot</dt>
        <dd class="mono">{inspectedPlot.plotNumber}</dd>
      </div>
      <div>
        <dt>Field BGC / Series</dt>
        <dd class="mono">
          {inspectedPlot.zone}{inspectedPlot.subZone || ''}{inspectedPlot.siteSeries
            ? `/${inspectedPlot.siteSeries}`
            : '—'}
        </dd>
      </div>
      <div>
        <dt>Active SU Unit</dt>
        <dd class="mono">{inspectedPlot.currentSuUnit || '(Unassigned)'}</dd>
      </div>
      <div>
        <dt>UserSiteUnit</dt>
        <dd class="mono">{inspectedPlot.userSiteUnit || '—'}</dd>
      </div>
      <div>
        <dt>rSMR / rSNR</dt>
        <dd class="mono">{inspectedPlot.moistureRegime || '—'} / {inspectedPlot.nutrientRegime || '—'}</dd>
      </div>
      <div>
        <dt>Elev / Slope / Aspect</dt>
        <dd class="mono">
          {inspectedPlot.elevation ?? '—'} m · {inspectedPlot.slope || '—'}% · {inspectedPlot.aspect ?? '—'} deg
        </dd>
      </div>
    </dl>

    {#if inspectedPlot.topSpecies.length > 0}
      <div class="table-scroll">
        <table class="vpro-cls-spp-table">
          <thead><tr><th>Species</th><th>A</th><th>B</th><th>C</th><th>D</th><th>Total</th></tr></thead>
          <tbody>
            {#each inspectedPlot.topSpecies.slice(0, 8) as sp (sp.species)}
              <tr>
                <td title={sp.scientificName}><strong class="mono">{sp.species}</strong></td>
                <td class="mono">{sp.coverA}</td>
                <td class="mono">{sp.coverB}</td>
                <td class="mono">{sp.coverC}</td>
                <td class="mono">{sp.coverD}</td>
                <td class="mono"><strong>{sp.totalFormatted}</strong></td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
  {:else}
    <p class="vpro-cls-muted">
      Click any plot leaf in the SU tree to inspect its field BEC, edatopic regime, topography, and dominant species.
    </p>
  {/if}
</section>

<section class="vpro-cls-card">
  <div class="vpro-cls-card-head">
    <h3>BECdb v13 Unit Picker (ZZZZsssvp/##)</h3>
    <div class="vpro-cls-actions">
      <button
        type="button"
        class="vpro-btn-mini"
        class:active-pill={rightPaneTab === 'bec_picker'}
        onclick={() => (rightPaneTab = 'bec_picker')}
      >
        BEC Picker
      </button>
      <button
        type="button"
        class="vpro-btn-mini"
        class:active-pill={rightPaneTab === 'user_su_list'}
        onclick={() => {
          rightPaneTab = 'user_su_list';
          void loadUserSiteUnitList();
        }}
      >
        UserSiteUnitList ({userSiteUnits.length})
      </button>
    </div>
  </div>

  {#if rightPaneTab === 'bec_picker'}
    <datalist id="vpro-cls-bec-zone-options">
      {#each becZones as bz (bz.zone)}
        <option value={bz.zone}>{bz.zone} — {bz.description}</option>
      {/each}
    </datalist>

    <div class="vpro-cls-picker-filters">
      <input
        type="text"
        aria-label="Filter BEC units by zone"
        class="vpro-cls-zone-input"
        list="vpro-cls-bec-zone-options"
        placeholder="Zone (e.g. CWH)"
        bind:value={becZone}
        onkeydown={(e) => {
          if (e.key === 'Enter') void refreshBECPicker();
        }}
      />
      <input
        type="text"
        aria-label="Filter BEC units by subzone"
        class="vpro-cls-zone-input"
        placeholder="SubZone"
        bind:value={becSubZone}
        onkeydown={(e) => {
          if (e.key === 'Enter') void refreshBECPicker();
        }}
      />
      <select
        aria-label="BEC lookup catalogue source"
        bind:value={becSearchMode}
        onchange={() => void refreshBECPicker()}
      >
        <option value="combined">All Sources</option>
        <option value="becdb_v13">BECdb v13 (Zone / Series)</option>
      </select>
      <input
        type="search"
        aria-label="Search BEC site series code or name"
        class="vpro-cls-query-input"
        placeholder="Search code or name..."
        bind:value={becQuery}
        onkeydown={(e) => {
          if (e.key === 'Enter') void refreshBECPicker();
        }}
      />
      <button type="button" class="vpro-btn-secondary" onclick={() => void refreshBECPicker()}>Search</button>
    </div>

    {#if !IS_WEB_READONLY}
      <div class="vpro-cls-custom-assign">
        <input
          type="text"
          aria-label="Custom or BEC target site unit"
          class="mono"
          placeholder="Custom or ZZZZsssvp/## unit..."
          bind:value={customTargetUnit}
        />
        {#if customTargetUnit.trim()}
          <span class="vpro-mask-badge" class:valid={isValidBECUnitMask(customTargetUnit)}>
            {isValidBECUnitMask(customTargetUnit) ? 'BEC Mask OK' : 'Working Unit'}
          </span>
        {/if}
        <button
          type="button"
          class="vpro-btn-primary vpro-cls-assign-btn"
          disabled={selectedPlots.length === 0 || !customTargetUnit.trim() || mutating}
          onclick={() => onAssignPlots(selectedPlots, customTargetUnit.trim())}
        >
          Assign ({selectedPlots.length})
        </button>
      </div>
    {/if}

    <div class="vpro-cls-bec-list">
      {#each becChoices as choice (`${choice.source}::${choice.siteSeries}`)}
        <div class="vpro-cls-bec-row">
          <div class="vpro-cls-bec-info">
            <strong class="mono">{choice.siteSeries}</strong>
            <span class="vpro-cls-sub">{choice.longName}</span>
          </div>
          {#if !IS_WEB_READONLY}
            <button
              type="button"
              class="vpro-btn-mini vpro-cls-assign-btn"
              disabled={selectedPlots.length === 0 || mutating}
              onclick={() => onAssignPlots(selectedPlots, choice.siteSeries)}
            >
              Assign ({selectedPlots.length})
            </button>
          {/if}
        </div>
      {/each}
      {#if becChoices.length === 0}
        <p class="vpro-cls-empty">No BEC site series matched the active zone/filter.</p>
      {/if}
    </div>
  {:else}
    <ClassificationUserSUPanel
      {effectiveContextId}
      {project}
      {port}
      {userSiteUnits}
      {selectedPlots}
      {mutating}
      onLoadUserSiteUnitList={loadUserSiteUnitList}
      {onAssignPlots}
      {onMutatingChange}
      {onError}
      {onStatus}
    />
  {/if}
</section>

<style>
  .vpro-cls-custom-assign {
    min-width: 0;
    flex-wrap: wrap;
  }

  .vpro-cls-custom-assign input {
    min-width: 0;
    flex: 1 1 130px;
  }

  .vpro-cls-bec-row {
    min-width: 0;
    align-items: flex-start;
  }

  .vpro-cls-bec-info {
    min-width: 0;
    flex: 1 1 0%;
    display: flex;
    flex-direction: column;
    gap: 1px;
    overflow-wrap: anywhere;
  }

  .vpro-cls-bec-info .vpro-cls-sub {
    white-space: normal;
    overflow: visible;
    text-overflow: clip;
    overflow-wrap: anywhere;
  }

  .vpro-cls-assign-btn {
    flex-shrink: 0;
    white-space: nowrap;
  }
</style>
