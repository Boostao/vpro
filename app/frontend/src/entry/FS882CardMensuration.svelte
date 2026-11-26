<script lang="ts">
  import { onDestroy } from 'svelte';
  import { ChevronDown, ChevronRight, Database, Plus, Save, Trash2 } from '@lucide/svelte';
  import { PlotEntryService } from '../../bindings/github.com/boostao/vpro/app';
  import type {
    FS882Header,
    PlotMensurationData,
    TreePlotRecord,
    TreeRowRecord,
  } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
  import { formatError } from '../shared/readRequests';
  import { notifications } from '../shell/notificationService.svelte';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import {
    formatPathologySummary,
    newEmptyTreePlotRecord,
    newEmptyTreeRowRecord,
    nextTreeNumber,
    parseOptionalFloat,
    parseOptionalInt,
    sortTreePlots,
    sortTreeRows,
    treePlotKey,
    treeRowKey,
    validateTreePlotDraft,
    validateTreeRowDraft,
  } from './mensurationDraft';

  let {
    contextId,
    plotNumber,
    headerDraft = null,
    locked = false,
    onDirtyChange,
    onBusyChange,
  }: {
    contextId: string;
    plotNumber: string;
    headerDraft?: Partial<FS882Header> | null;
    locked?: boolean;
    onDirtyChange?: (dirty: boolean) => void;
    onBusyChange?: (busy: boolean) => void;
  } = $props();

  let loading = $state(false);
  let saving = $state(false);
  let errorMsg = $state<string | null>(null);
  let data = $state.raw<PlotMensurationData | null>(null);
  let selectedHeaderKey = $state<string>('');
  let headerEdit = $state<TreePlotRecord | null>(null);
  let headerDirty = $state(false);
  let treeDrafts = $state<TreeRowRecord[]>([]);
  let dirtyTreeKeys = $state<Record<string, boolean>>({});
  let expandedPathology = $state<Record<string, boolean>>({});
  let loadGeneration = 0;

  const isReadOnly = $derived(IS_WEB_READONLY || locked || Boolean(data?.readOnly));
  const hasUnsavedChanges = $derived(
    !isReadOnly && (headerDirty || Object.values(dirtyTreeKeys).some(Boolean))
  );
  const isBusy = $derived(loading || saving);
  const sortedHeaders = $derived(sortTreePlots(data?.treePlots ?? []));
  const activeSubPlot = $derived(headerEdit?.subPlot ?? sortedHeaders[0]?.subPlot ?? 'A');
  const activeMeasurementId = $derived(headerEdit?.measurementId ?? sortedHeaders[0]?.measurementId ?? 1);

  $effect(() => {
    onDirtyChange?.(hasUnsavedChanges);
  });

  $effect(() => {
    onBusyChange?.(isBusy);
  });

  onDestroy(() => {
    onDirtyChange?.(false);
    onBusyChange?.(false);
  });

  const visibleTrees = $derived.by(() => {
    if (!headerEdit) return treeDrafts;
    return treeDrafts.filter((row) => {
      const sameSub = row.subPlot == null || row.subPlot === '' || row.subPlot === headerEdit!.subPlot;
      const sameMeas = row.measurementId == null || row.measurementId === headerEdit!.measurementId;
      return sameSub && sameMeas;
    });
  });

  function hydrateFromPayload(payload: PlotMensurationData | null) {
    data = payload;
    const headers = sortTreePlots(payload?.treePlots ?? []);
    const existingSelection = headers.find((h) => treePlotKey(h) === selectedHeaderKey);
    const chosen = existingSelection ?? headers[0] ?? null;
    if (chosen) {
      selectedHeaderKey = treePlotKey(chosen);
      headerEdit = structuredClone($state.snapshot(chosen));
    } else if (payload?.hasTables && plotNumber.trim()) {
      const fresh = newEmptyTreePlotRecord(plotNumber.trim(), headerDraft, []);
      selectedHeaderKey = treePlotKey(fresh);
      headerEdit = fresh;
    } else {
      selectedHeaderKey = '';
      headerEdit = null;
    }
    headerDirty = false;
    treeDrafts = sortTreeRows(payload?.trees ?? []).map((r) => structuredClone($state.snapshot(r)));
    dirtyTreeKeys = {};
    expandedPathology = {};
  }

  async function loadMensuration(ctxId: string, plot: string) {
    const gen = ++loadGeneration;
    if (!ctxId || !plot.trim()) {
      loading = false;
      errorMsg = null;
      hydrateFromPayload(null);
      return;
    }
    if (typeof PlotEntryService?.GetPlotMensuration !== 'function') {
      loading = false;
      hydrateFromPayload({
        plotNumber: plot,
        hasTables: false,
        hasTreePlot: false,
        hasTrees: false,
        treePlots: [],
        trees: [],
        readOnly: isReadOnly,
      });
      return;
    }
    loading = true;
    errorMsg = null;
    try {
      const res = await PlotEntryService.GetPlotMensuration(ctxId, plot);
      if (gen !== loadGeneration) return;
      hydrateFromPayload(res);
    } catch (cause) {
      if (gen !== loadGeneration) return;
      errorMsg = `Could not load mensuration data: ${formatError(cause)}`;
    } finally {
      if (gen === loadGeneration) loading = false;
    }
  }

  $effect(() => {
    const ctx = contextId;
    const plot = plotNumber;
    void loadMensuration(ctx, plot);
  });

  async function initializeTables() {
    if (isReadOnly || saving || !contextId) return;
    saving = true;
    errorMsg = null;
    try {
      await PlotEntryService.EnsureMensurationTables(contextId);
      notifications.success('Mensuration tables initialized', 'Added Card 4 mensuration tables to this project.', {
        category: 'entry',
        source: 'FS882 Mensuration',
        contextTag: plotNumber ? `Plot ${plotNumber}` : undefined,
      });
      await loadMensuration(contextId, plotNumber);
    } catch (cause) {
      errorMsg = `Could not initialize mensuration tables: ${formatError(cause)}`;
    } finally {
      saving = false;
    }
  }

  function selectHeaderByKey(key: string) {
    const found = sortedHeaders.find((h) => treePlotKey(h) === key);
    if (!found) return;
    selectedHeaderKey = key;
    headerEdit = structuredClone($state.snapshot(found));
    headerDirty = false;
    errorMsg = null;
  }

  function startNewHeader() {
    if (isReadOnly || !plotNumber.trim()) return;
    const fresh = newEmptyTreePlotRecord(plotNumber.trim(), headerDraft, sortedHeaders);
    selectedHeaderKey = treePlotKey(fresh);
    headerEdit = fresh;
    headerDirty = true;
    errorMsg = null;
  }

  async function saveHeader() {
    if (isReadOnly || saving || !headerEdit || !contextId) return;
    const snapshot = $state.snapshot(headerEdit);
    const errors = validateTreePlotDraft(snapshot);
    if (errors.length > 0) {
      errorMsg = errors[0];
      return;
    }
    saving = true;
    errorMsg = null;
    try {
      const saved = await PlotEntryService.SaveTreePlot(contextId, snapshot);
      if (saved) {
        selectedHeaderKey = treePlotKey(saved);
      }
      notifications.success('Mensuration header saved', `Saved SubPlot ${snapshot.subPlot} (#${snapshot.measurementId}).`, {
        category: 'entry',
        source: 'FS882 Mensuration',
        contextTag: plotNumber ? `Plot ${plotNumber}` : undefined,
      });
      await loadMensuration(contextId, plotNumber);
    } catch (cause) {
      errorMsg = `Could not save mensuration header: ${formatError(cause)}`;
    } finally {
      saving = false;
    }
  }

  async function deleteHeader() {
    if (isReadOnly || saving || !headerEdit || !contextId) return;
    const existsInDb = sortedHeaders.some(
      (h) => h.subPlot === headerEdit!.subPlot && h.measurementId === headerEdit!.measurementId
    );
    if (!existsInDb) {
      hydrateFromPayload(data);
      return;
    }
    saving = true;
    errorMsg = null;
    try {
      await PlotEntryService.DeleteTreePlot(contextId, plotNumber, headerEdit.subPlot, headerEdit.measurementId);
      notifications.success('Mensuration header deleted', `Removed SubPlot ${headerEdit.subPlot} (#${headerEdit.measurementId}).`, {
        category: 'entry',
        source: 'FS882 Mensuration',
        contextTag: plotNumber ? `Plot ${plotNumber}` : undefined,
      });
      selectedHeaderKey = '';
      await loadMensuration(contextId, plotNumber);
    } catch (cause) {
      errorMsg = `Could not delete mensuration header: ${formatError(cause)}`;
    } finally {
      saving = false;
    }
  }

  function addTreeRow() {
    if (isReadOnly || !plotNumber.trim()) return;
    const nextNum = nextTreeNumber(treeDrafts, activeSubPlot, activeMeasurementId);
    const fresh = newEmptyTreeRowRecord(plotNumber.trim(), activeSubPlot, activeMeasurementId, nextNum);
    const key = treeRowKey(fresh, treeDrafts.length);
    treeDrafts = [...treeDrafts, fresh];
    dirtyTreeKeys = { ...dirtyTreeKeys, [key]: true };
    errorMsg = null;
  }

  function updateTreeRow(indexInDrafts: number, patch: Partial<TreeRowRecord>) {
    const current = treeDrafts[indexInDrafts];
    if (!current) return;
    const updated = { ...current, ...patch };
    const nextList = treeDrafts.slice();
    nextList[indexInDrafts] = updated;
    treeDrafts = nextList;
    const key = treeRowKey(updated, indexInDrafts);
    dirtyTreeKeys = { ...dirtyTreeKeys, [key]: true };
  }

  async function saveTreeRow(indexInDrafts: number) {
    if (isReadOnly || saving || !contextId) return;
    const row = treeDrafts[indexInDrafts];
    if (!row) return;
    const snapshot = $state.snapshot(row);
    const errors = validateTreeRowDraft(snapshot);
    if (errors.length > 0) {
      errorMsg = errors[0];
      return;
    }
    saving = true;
    errorMsg = null;
    try {
      await PlotEntryService.SaveTreeRow(contextId, snapshot);
      notifications.success('Tree row saved', `Saved tree #${snapshot.treeNum ?? '—'} (${snapshot.treeSpp ?? '—'}).`, {
        category: 'entry',
        source: 'FS882 Mensuration',
        contextTag: plotNumber ? `Plot ${plotNumber}` : undefined,
      });
      await loadMensuration(contextId, plotNumber);
    } catch (cause) {
      errorMsg = `Could not save tree row: ${formatError(cause)}`;
    } finally {
      saving = false;
    }
  }

  async function deleteTreeRow(indexInDrafts: number) {
    if (isReadOnly || saving || !contextId) return;
    const row = treeDrafts[indexInDrafts];
    if (!row) return;
    if (!row.rowId) {
      const nextDrafts = treeDrafts.filter((_, i) => i !== indexInDrafts);
      const nextDirty: Record<string, boolean> = {};
      for (let i = 0; i < nextDrafts.length; i++) {
        const candidate = nextDrafts[i];
        const nextKey = treeRowKey(candidate, i);
        if (!candidate.rowId || dirtyTreeKeys[nextKey]) {
          nextDirty[nextKey] = true;
        }
      }
      treeDrafts = nextDrafts;
      dirtyTreeKeys = nextDirty;
      return;
    }
    saving = true;
    errorMsg = null;
    try {
      await PlotEntryService.DeleteTreeRow(
        contextId,
        plotNumber,
        row.subPlot ?? '',
        row.measurementId ?? 0,
        row.treeNum ?? 0
      );
      notifications.success('Tree row deleted', `Removed tree #${row.treeNum ?? '—'}.`, {
        category: 'entry',
        source: 'FS882 Mensuration',
        contextTag: plotNumber ? `Plot ${plotNumber}` : undefined,
      });
      await loadMensuration(contextId, plotNumber);
    } catch (cause) {
      errorMsg = `Could not delete tree row: ${formatError(cause)}`;
    } finally {
      saving = false;
    }
  }

  function updateHeaderNumber(key: 'baf' | 'dbhLimit' | 'plotSize', raw: string, label: string) {
    if (!headerEdit) return;
    const parsed = parseOptionalFloat(raw, label, true);
    if (parsed.error) {
      errorMsg = parsed.error;
      return;
    }
    errorMsg = null;
    headerEdit = { ...headerEdit, [key]: parsed.value };
    headerDirty = true;
  }

  function updateHeaderInt(key: 'measurementId' | 'standAge', raw: string, label: string) {
    if (!headerEdit) return;
    const parsed = parseOptionalInt(raw, label);
    if (parsed.error) {
      errorMsg = parsed.error;
      return;
    }
    if (key === 'measurementId' && parsed.value === null) {
      errorMsg = 'MeasurementID is required.';
      return;
    }
    errorMsg = null;
    headerEdit = {
      ...headerEdit,
      [key]: key === 'measurementId' ? (parsed.value ?? 1) : parsed.value,
    };
    headerDirty = true;
  }

  function setTreeNumeric(
    draftIdx: number,
    key: 'treeNum' | 'countAge' | 'totalAge' | 'treeHealth' | 'conks' | 'blindConks' | 'scars' | 'forkOrCrook' | 'frostCrack' | 'mistletoe' | 'rottenBranch' | 'deadOrBrokenTop' | 'appearance' | 'crownCondition' | 'barkRetention' | 'woodCondition' | 'lichenLoading' | 'mossLoading',
    raw: string,
    label: string,
    byteField = false
  ) {
    const parsed = parseOptionalInt(raw, label, byteField ? { min: 0, max: 255 } : {});
    if (parsed.error) {
      errorMsg = parsed.error;
      return;
    }
    errorMsg = null;
    updateTreeRow(draftIdx, { [key]: parsed.value });
  }

  function setTreeFloat(
    draftIdx: number,
    key: 'dbh' | 'totalHtCalc' | 'countHt' | 'ht2LiveCrown' | 'si50',
    raw: string,
    label: string,
    single = true
  ) {
    const parsed = parseOptionalFloat(raw, label, single);
    if (parsed.error) {
      errorMsg = parsed.error;
      return;
    }
    errorMsg = null;
    updateTreeRow(draftIdx, { [key]: parsed.value });
  }
</script>

<article class="classic-card" data-classic-card="mensuration" aria-label="FS882 Card 4 — Mensuration">
  <header class="classic-card-masthead">
    <div>
      <div class="classic-card-kicker">B.C. Ministry of Forests · LMH25 Field Card</div>
      <div class="classic-card-title">CARD 4 — MENSURATION (FS882)</div>
    </div>
    <div class="classic-card-badges">
      {#if data?.hasTables}
        <span class="classic-card-stamp">{sortedHeaders.length} SUBPLOT(S) · {treeDrafts.length} TREE(S)</span>
      {/if}
      <span class="classic-card-stamp">PLOT: {plotNumber || '(New)'}</span>
    </div>
  </header>

  {#if errorMsg}
    <div role="alert" class="mb-2 px-2.5 py-1.5 rounded bg-red-50 border border-red-200 text-red-800 text-xs flex items-center justify-between gap-2">
      <span>{errorMsg}</span>
      <button type="button" class="classic-mini-btn" onclick={() => (errorMsg = null)}>Dismiss</button>
    </div>
  {/if}

  {#if !plotNumber.trim()}
    <div class="p-4 text-center text-xs text-vpro-ink-secondary border border-dashed border-vpro-border rounded bg-white/60">
      Save the new plot on Card 1 before recording Card 4 mensuration measurements.
    </div>
  {:else if loading && !data}
    <p role="status" class="p-3 text-xs text-vpro-ink-secondary" data-mensuration-loading>
      Loading mensuration records for plot {plotNumber}...
    </p>
  {:else if !data?.hasTables}
    <div
      class="p-4 text-center border border-vpro-border rounded bg-white/75 space-y-2"
      data-mensuration-empty-tables
    >
      {#if isReadOnly}
        <p class="text-xs font-medium text-vpro-ink-secondary" data-mensuration-no-tables>
          No mensuration tables in this project.
        </p>
      {:else}
        <p class="text-xs text-vpro-ink-secondary">
          This project does not yet include Card 4 mensuration tables for tree plot headers and tree measurements.
        </p>
        <button
          type="button"
          class="classic-mini-btn classic-mini-btn-primary"
          data-mensuration-init-btn
          disabled={saving}
          onclick={() => void initializeTables()}
        >
          <Database size={12} aria-hidden="true" />
          {saving ? 'Initializing...' : 'Initialize Mensuration Tables'}
        </button>
      {/if}
    </div>
  {:else}
    <!-- SubPlot / Measurement Selector -->
    <section class="classic-block">
      <div class="classic-block-header">
        <span>1. Tree Plot Header (SubPlot &amp; Measurement)</span>
        <div class="flex flex-wrap items-center gap-1">
          {#if sortedHeaders.length > 0}
            <select
              aria-label="Select mensuration subplot and measurement"
              data-mensuration-header-select
              class="classic-select classic-mono"
              style="width: auto; min-width: 140px;"
              value={selectedHeaderKey}
              onchange={(e) => selectHeaderByKey(e.currentTarget.value)}
            >
              {#each sortedHeaders as h (treePlotKey(h))}
                <option value={treePlotKey(h)}>
                  SubPlot {h.subPlot} · Meas #{h.measurementId}{h.date ? ` (${h.date})` : ''}
                </option>
              {/each}
            </select>
          {/if}
          {#if !isReadOnly}
            <button
              type="button"
              class="classic-mini-btn"
              data-mensuration-new-header
              disabled={saving}
              onclick={startNewHeader}
            >
              <Plus size={11} aria-hidden="true" /> New SubPlot
            </button>
            <button
              type="button"
              class="classic-mini-btn classic-mini-btn-primary"
              data-mensuration-save-header
              disabled={saving || !headerEdit}
              onclick={() => void saveHeader()}
            >
              <Save size={11} aria-hidden="true" /> Save Header
            </button>
            <button
              type="button"
              class="classic-mini-btn classic-mini-btn-danger"
              data-mensuration-delete-header
              disabled={saving || !headerEdit || sortedHeaders.length === 0}
              onclick={() => void deleteHeader()}
            >
              <Trash2 size={11} aria-hidden="true" /> Delete Header
            </button>
          {/if}
        </div>
      </div>

      {#if headerEdit}
        <div class="classic-grid" class:is-draft={headerDirty}>
          <div class="classic-cell" style="grid-column: span 2;">
            <label class="classic-label" for="mens-subPlot">SubPlot</label>
            <input
              id="mens-subPlot"
              data-mens-field="SubPlot"
              type="text"
              class="classic-input classic-mono font-semibold"
              value={headerEdit.subPlot}
              disabled={isReadOnly}
              oninput={(e) => {
                headerEdit = { ...headerEdit!, subPlot: e.currentTarget.value };
                headerDirty = true;
              }}
            />
          </div>
          <div class="classic-cell" style="grid-column: span 2;">
            <label class="classic-label" for="mens-measurementId">Measurement ID</label>
            <input
              id="mens-measurementId"
              data-mens-field="MeasurementID"
              type="text"
              inputmode="numeric"
              class="classic-input classic-mono classic-num"
              value={String(headerEdit.measurementId)}
              disabled={isReadOnly}
              oninput={(e) => updateHeaderInt('measurementId', e.currentTarget.value, 'MeasurementID')}
            />
          </div>
          <div class="classic-cell" style="grid-column: span 3;">
            <label class="classic-label" for="mens-mensurationId">Mensuration ID</label>
            <input
              id="mens-mensurationId"
              data-mens-field="MensurationID"
              type="text"
              class="classic-input classic-mono"
              value={headerEdit.mensurationId ?? ''}
              disabled={isReadOnly}
              oninput={(e) => {
                headerEdit = { ...headerEdit!, mensurationId: e.currentTarget.value || null };
                headerDirty = true;
              }}
            />
          </div>
          <div class="classic-cell" style="grid-column: span 3;">
            <label class="classic-label" for="mens-treeSurveyor">Tree Surveyor</label>
            <input
              id="mens-treeSurveyor"
              data-mens-field="TreeSurveyor"
              type="text"
              class="classic-input"
              value={headerEdit.treeSurveyor ?? ''}
              disabled={isReadOnly}
              oninput={(e) => {
                headerEdit = { ...headerEdit!, treeSurveyor: e.currentTarget.value || null };
                headerDirty = true;
              }}
            />
          </div>
          <div class="classic-cell" style="grid-column: span 2;">
            <label class="classic-label" for="mens-date">Date</label>
            <input
              id="mens-date"
              data-mens-field="Date"
              type="text"
              placeholder="YYYY-MM-DD"
              class="classic-input classic-mono"
              value={headerEdit.date ?? ''}
              disabled={isReadOnly}
              oninput={(e) => {
                headerEdit = { ...headerEdit!, date: e.currentTarget.value || null };
                headerDirty = true;
              }}
            />
          </div>
        </div>

        <!-- 5 Plot-Type Checkboxes -->
        <div class="classic-check-row" data-mens-plot-types>
          {#each [
            ['cruisePlot', 'Cruise Plot'],
            ['cwdPlot', 'CWD Plot'],
            ['wildlifePlot', 'Wildlife Plot'],
            ['informalPlot', 'Informal Plot'],
            ['siteIndexPlot', 'Site Index Plot'],
          ] as const as [key, label] (key)}
            <label class="classic-check-label">
              <input
                type="checkbox"
                data-mens-field={key}
                checked={headerEdit[key]}
                disabled={isReadOnly}
                onchange={(e) => {
                  headerEdit = { ...headerEdit!, [key]: e.currentTarget.checked };
                  headerDirty = true;
                }}
              />
              {label}
            </label>
          {/each}
        </div>

        <div class="classic-grid">
          <div class="classic-cell" style="grid-column: span 2;">
            <label class="classic-label" for="mens-baf">BAF</label>
            <input
              id="mens-baf"
              data-mens-field="BAF"
              type="text"
              inputmode="decimal"
              class="classic-input classic-mono classic-num"
              value={headerEdit.baf == null ? '' : String(headerEdit.baf)}
              disabled={isReadOnly}
              oninput={(e) => updateHeaderNumber('baf', e.currentTarget.value, 'BAF')}
            />
          </div>
          <div class="classic-cell" style="grid-column: span 2;">
            <label class="classic-label" for="mens-dbhLimit">DBH Limit (cm)</label>
            <input
              id="mens-dbhLimit"
              data-mens-field="DBHLimit"
              type="text"
              inputmode="decimal"
              class="classic-input classic-mono classic-num"
              value={headerEdit.dbhLimit == null ? '' : String(headerEdit.dbhLimit)}
              disabled={isReadOnly}
              oninput={(e) => updateHeaderNumber('dbhLimit', e.currentTarget.value, 'DBHLimit')}
            />
          </div>
          <div class="classic-cell" style="grid-column: span 2;">
            <label class="classic-label" for="mens-standAge">Stand Age</label>
            <input
              id="mens-standAge"
              data-mens-field="StandAge"
              type="text"
              inputmode="numeric"
              class="classic-input classic-mono classic-num"
              value={headerEdit.standAge == null ? '' : String(headerEdit.standAge)}
              disabled={isReadOnly}
              oninput={(e) => updateHeaderInt('standAge', e.currentTarget.value, 'StandAge')}
            />
          </div>
          <div class="classic-cell" style="grid-column: span 2;">
            <label class="classic-label" for="mens-plotSize">Plot Size</label>
            <input
              id="mens-plotSize"
              data-mens-field="PlotSize"
              type="text"
              inputmode="decimal"
              class="classic-input classic-mono classic-num"
              value={headerEdit.plotSize == null ? '' : String(headerEdit.plotSize)}
              disabled={isReadOnly}
              oninput={(e) => updateHeaderNumber('plotSize', e.currentTarget.value, 'PlotSize')}
            />
          </div>
          <div class="classic-cell" style="grid-column: span 2;">
            <label class="classic-label" for="mens-seralStage">Seral Stage</label>
            <input
              id="mens-seralStage"
              data-mens-field="SeralStage"
              type="text"
              class="classic-input classic-mono"
              value={headerEdit.seralStage ?? ''}
              disabled={isReadOnly}
              oninput={(e) => {
                headerEdit = { ...headerEdit!, seralStage: e.currentTarget.value || null };
                headerDirty = true;
              }}
            />
          </div>
          <div class="classic-cell" style="grid-column: span 2;">
            <label class="classic-label" for="mens-becSiteUnit">BEC Site Unit</label>
            <input
              id="mens-becSiteUnit"
              data-mens-field="BECSiteUnit"
              type="text"
              class="classic-input classic-mono"
              value={headerEdit.becSiteUnit ?? ''}
              disabled={isReadOnly}
              oninput={(e) => {
                headerEdit = { ...headerEdit!, becSiteUnit: e.currentTarget.value || null };
                headerDirty = true;
              }}
            />
          </div>
          <div class="classic-cell" style="grid-column: span 12;" data-full-row>
            <label class="classic-label" for="mens-comment">Mensuration Comment</label>
            <textarea
              id="mens-comment"
              data-mens-field="Comment"
              rows={2}
              class="classic-textarea"
              value={headerEdit.comment ?? ''}
              disabled={isReadOnly}
              oninput={(e) => {
                headerEdit = { ...headerEdit!, comment: e.currentTarget.value || null };
                headerDirty = true;
              }}
            ></textarea>
          </div>
        </div>
      {/if}
    </section>

    <!-- Section 2: Compact Ruled Tree Table -->
    <section class="classic-block" data-mensuration-trees-section>
      <div class="classic-block-header">
        <span>2. Measured Trees ({visibleTrees.length})</span>
        {#if !isReadOnly}
          <button
            type="button"
            class="classic-mini-btn classic-mini-btn-primary"
            data-mensuration-add-tree
            disabled={saving}
            onclick={addTreeRow}
          >
            <Plus size={11} aria-hidden="true" /> Add Tree Row
          </button>
        {/if}
      </div>
      <div class="classic-table-wrap">
        <table class="classic-table">
          <thead>
            <tr>
              <th>#</th>
              <th>Spp</th>
              <th>DBH</th>
              <th>Tot Ht</th>
              <th>Cnt Age</th>
              <th>Cnt Ht</th>
              <th>Tot Age</th>
              <th>Hlth</th>
              <th>Orig</th>
              <th>Crwn</th>
              <th>Ht2LC</th>
              <th>L/D</th>
              <th>Path / Wildlife</th>
              <th>SI50</th>
              <th>Tree Notes</th>
              {#if !isReadOnly}<th style="width: 66px;">Actions</th>{/if}
            </tr>
          </thead>
          <tbody>
            {#each visibleTrees as row, vIdx (treeRowKey(row, vIdx))}
              {@const draftIdx = treeDrafts.indexOf(row)}
              {@const rKey = treeRowKey(row, draftIdx)}
              {@const isExpanded = Boolean(expandedPathology[rKey])}
              <tr class:is-draft={Boolean(dirtyTreeKeys[rKey])} data-mens-tree-row={row.treeNum ?? vIdx}>
                <td style="width: 44px;">
                  <input
                    type="text"
                    inputmode="numeric"
                    class="classic-input classic-mono classic-num font-semibold"
                    aria-label={`Tree number row ${vIdx + 1}`}
                    value={row.treeNum == null ? '' : String(row.treeNum)}
                    disabled={isReadOnly}
                    oninput={(e) => setTreeNumeric(draftIdx, 'treeNum', e.currentTarget.value, 'TreeNum')}
                  />
                </td>
                <td style="width: 48px;">
                  <input
                    type="text"
                    maxlength={3}
                    class="classic-input classic-mono uppercase font-semibold"
                    aria-label={`Tree species row ${vIdx + 1}`}
                    value={row.treeSpp ?? ''}
                    disabled={isReadOnly}
                    oninput={(e) => updateTreeRow(draftIdx, { treeSpp: e.currentTarget.value || null })}
                  />
                </td>
                <td style="width: 52px;">
                  <input
                    type="text"
                    inputmode="decimal"
                    class="classic-input classic-mono classic-num"
                    aria-label={`DBH row ${vIdx + 1}`}
                    value={row.dbh == null ? '' : String(row.dbh)}
                    disabled={isReadOnly}
                    oninput={(e) => setTreeFloat(draftIdx, 'dbh', e.currentTarget.value, 'DBH')}
                  />
                </td>
                <td style="width: 52px;">
                  <input
                    type="text"
                    inputmode="decimal"
                    class="classic-input classic-mono classic-num"
                    aria-label={`Total height row ${vIdx + 1}`}
                    value={row.totalHtCalc == null ? '' : String(row.totalHtCalc)}
                    disabled={isReadOnly}
                    oninput={(e) => setTreeFloat(draftIdx, 'totalHtCalc', e.currentTarget.value, 'TotalHtCalc')}
                  />
                </td>
                <td style="width: 48px;">
                  <input
                    type="text"
                    inputmode="numeric"
                    class="classic-input classic-mono classic-num"
                    aria-label={`Count age row ${vIdx + 1}`}
                    value={row.countAge == null ? '' : String(row.countAge)}
                    disabled={isReadOnly}
                    oninput={(e) => setTreeNumeric(draftIdx, 'countAge', e.currentTarget.value, 'CountAge')}
                  />
                </td>
                <td style="width: 48px;">
                  <input
                    type="text"
                    inputmode="decimal"
                    class="classic-input classic-mono classic-num"
                    aria-label={`Count height row ${vIdx + 1}`}
                    value={row.countHt == null ? '' : String(row.countHt)}
                    disabled={isReadOnly}
                    oninput={(e) => setTreeFloat(draftIdx, 'countHt', e.currentTarget.value, 'CountHT')}
                  />
                </td>
                <td style="width: 48px;">
                  <input
                    type="text"
                    inputmode="numeric"
                    class="classic-input classic-mono classic-num"
                    aria-label={`Total age row ${vIdx + 1}`}
                    value={row.totalAge == null ? '' : String(row.totalAge)}
                    disabled={isReadOnly}
                    oninput={(e) => setTreeNumeric(draftIdx, 'totalAge', e.currentTarget.value, 'TotalAge')}
                  />
                </td>
                <td style="width: 42px;">
                  <input
                    type="text"
                    inputmode="numeric"
                    class="classic-input classic-mono classic-num"
                    aria-label={`Tree health row ${vIdx + 1}`}
                    value={row.treeHealth == null ? '' : String(row.treeHealth)}
                    disabled={isReadOnly}
                    oninput={(e) => setTreeNumeric(draftIdx, 'treeHealth', e.currentTarget.value, 'TreeHealth', true)}
                  />
                </td>
                <td style="width: 38px;">
                  <input
                    type="text"
                    maxlength={1}
                    class="classic-input classic-mono"
                    aria-label={`Tree origin row ${vIdx + 1}`}
                    value={row.treeOrigin ?? ''}
                    disabled={isReadOnly}
                    oninput={(e) => updateTreeRow(draftIdx, { treeOrigin: e.currentTarget.value || null })}
                  />
                </td>
                <td style="width: 38px;">
                  <input
                    type="text"
                    maxlength={1}
                    class="classic-input classic-mono"
                    aria-label={`Crown class row ${vIdx + 1}`}
                    value={row.crownClass ?? ''}
                    disabled={isReadOnly}
                    oninput={(e) => updateTreeRow(draftIdx, { crownClass: e.currentTarget.value || null })}
                  />
                </td>
                <td style="width: 48px;">
                  <input
                    type="text"
                    inputmode="decimal"
                    class="classic-input classic-mono classic-num"
                    aria-label={`Height to live crown row ${vIdx + 1}`}
                    value={row.ht2LiveCrown == null ? '' : String(row.ht2LiveCrown)}
                    disabled={isReadOnly}
                    oninput={(e) => setTreeFloat(draftIdx, 'ht2LiveCrown', e.currentTarget.value, 'Ht2LiveCrown')}
                  />
                </td>
                <td style="width: 46px;">
                  <input
                    type="text"
                    class="classic-input classic-mono"
                    aria-label={`Live or dead row ${vIdx + 1}`}
                    value={row.liveDead ?? ''}
                    disabled={isReadOnly}
                    oninput={(e) => updateTreeRow(draftIdx, { liveDead: e.currentTarget.value || null })}
                  />
                </td>
                <td style="min-width: 96px;">
                  <button
                    type="button"
                    class="classic-mini-btn w-full justify-between"
                    data-mens-pathology-toggle={rKey}
                    aria-expanded={isExpanded}
                    onclick={() => {
                      expandedPathology = { ...expandedPathology, [rKey]: !isExpanded };
                    }}
                  >
                    <span class="truncate max-w-[82px]">{formatPathologySummary(row)}</span>
                    {#if isExpanded}<ChevronDown size={11} aria-hidden="true" />{:else}<ChevronRight size={11} aria-hidden="true" />{/if}
                  </button>
                </td>
                <td style="width: 50px;">
                  <input
                    type="text"
                    inputmode="decimal"
                    class="classic-input classic-mono classic-num"
                    aria-label={`SI50 row ${vIdx + 1}`}
                    value={row.si50 == null ? '' : String(row.si50)}
                    disabled={isReadOnly}
                    oninput={(e) => setTreeFloat(draftIdx, 'si50', e.currentTarget.value, 'SI50', false)}
                  />
                </td>
                <td style="min-width: 90px;">
                  <input
                    type="text"
                    class="classic-input"
                    aria-label={`Tree notes row ${vIdx + 1}`}
                    value={row.treeNotes ?? ''}
                    disabled={isReadOnly}
                    oninput={(e) => updateTreeRow(draftIdx, { treeNotes: e.currentTarget.value || null })}
                  />
                </td>
                {#if !isReadOnly}
                  <td>
                    <div class="flex items-center gap-0.5">
                      <button
                        type="button"
                        class="classic-mini-btn classic-mini-btn-primary"
                        data-mens-save-tree={row.treeNum ?? vIdx}
                        title="Save tree row"
                        aria-label={`Save tree row ${vIdx + 1}`}
                        disabled={saving}
                        onclick={() => void saveTreeRow(draftIdx)}
                      >
                        <Save size={11} aria-hidden="true" />
                      </button>
                      <button
                        type="button"
                        class="classic-mini-btn classic-mini-btn-danger"
                        data-mens-delete-tree={row.treeNum ?? vIdx}
                        title="Delete tree row"
                        aria-label={`Delete tree row ${vIdx + 1}`}
                        disabled={saving}
                        onclick={() => void deleteTreeRow(draftIdx)}
                      >
                        <Trash2 size={11} aria-hidden="true" />
                      </button>
                    </div>
                  </td>
                {/if}
              </tr>

              {#if isExpanded}
                <tr data-mens-pathology-drawer={rKey}>
                  <td colspan={isReadOnly ? 15 : 16} class="bg-white/90 p-2">
                    <div class="text-[10px] font-bold uppercase tracking-wider text-vpro-navy mb-1">
                      Tree #{row.treeNum ?? '—'} — Pathology, Damage &amp; Wildlife Attributes
                    </div>
                    <div class="classic-grid border border-vpro-border">
                      {#each [
                        ['conks', 'Conks'],
                        ['blindConks', 'Blind Conks'],
                        ['scars', 'Scars'],
                        ['forkOrCrook', 'Fork / Crook'],
                        ['frostCrack', 'Frost Crack'],
                        ['mistletoe', 'Mistletoe'],
                        ['rottenBranch', 'Rotten Br.'],
                        ['deadOrBrokenTop', 'Dead/Brk Top'],
                        ['appearance', 'Appearance'],
                        ['crownCondition', 'Crown Cond.'],
                        ['barkRetention', 'Bark Ret.'],
                        ['woodCondition', 'Wood Cond.'],
                        ['lichenLoading', 'Lichen Load'],
                        ['mossLoading', 'Moss Load'],
                      ] as const as [bKey, bLabel] (bKey)}
                        <div class="classic-cell" style="grid-column: span 2;">
                          <label class="classic-label" for={`mens-${rKey}-${bKey}`}>{bLabel}</label>
                          <input
                            id={`mens-${rKey}-${bKey}`}
                            type="text"
                            inputmode="numeric"
                            class="classic-input classic-mono classic-num"
                            value={row[bKey] == null ? '' : String(row[bKey])}
                            disabled={isReadOnly}
                            oninput={(e) => setTreeNumeric(draftIdx, bKey, e.currentTarget.value, bLabel, true)}
                          />
                        </div>
                      {/each}
                      <div class="classic-cell" style="grid-column: span 2;">
                        <label class="classic-label" for={`mens-${rKey}-dmgType`}>Damage Type</label>
                        <input
                          id={`mens-${rKey}-dmgType`}
                          type="text"
                          maxlength={3}
                          class="classic-input classic-mono"
                          value={row.damageType ?? ''}
                          disabled={isReadOnly}
                          oninput={(e) => updateTreeRow(draftIdx, { damageType: e.currentTarget.value || null })}
                        />
                      </div>
                      <div class="classic-cell" style="grid-column: span 2;">
                        <label class="classic-label" for={`mens-${rKey}-dmgSev`}>Damage Sev.</label>
                        <input
                          id={`mens-${rKey}-dmgSev`}
                          type="text"
                          maxlength={1}
                          class="classic-input classic-mono"
                          value={row.damageSeverity ?? ''}
                          disabled={isReadOnly}
                          oninput={(e) => updateTreeRow(draftIdx, { damageSeverity: e.currentTarget.value || null })}
                        />
                      </div>
                      <div class="classic-cell" style="grid-column: span 4;">
                        <label class="classic-label" for={`mens-${rKey}-wlUse`}>Wildlife Use</label>
                        <input
                          id={`mens-${rKey}-wlUse`}
                          type="text"
                          maxlength={17}
                          class="classic-input classic-mono"
                          value={row.wildLifeUse ?? ''}
                          disabled={isReadOnly}
                          oninput={(e) => updateTreeRow(draftIdx, { wildLifeUse: e.currentTarget.value || null })}
                        />
                      </div>
                    </div>
                  </td>
                </tr>
              {/if}
            {:else}
              <tr>
                <td colspan={isReadOnly ? 15 : 16} class="text-center italic py-2 text-vpro-ink-muted">
                  No measured trees recorded for this subplot.
                </td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    </section>
  {/if}
</article>
