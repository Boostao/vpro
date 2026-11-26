<script lang="ts">
  import { CheckSquare, Plus, Trash2 } from '@lucide/svelte';
  import type { FS882Header, VegRecord } from '../../bindings/github.com/boostao/vpro/app';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import { classifyVegRowsForClassicCard } from './classicFS882Helpers';
  import type { FS882Controller } from './fs882FormController.svelte';
  import type { HeightField } from './heightEditor';

  type StrataNumberKey = 'strataCoverTree' | 'strataCoverShrub' | 'strataCoverHerb' | 'strataCoverMoss';

  let {
    ctrl,
    extendedShrubsNotice,
  }: {
    ctrl: FS882Controller;
    extendedShrubsNotice: string;
  } = $props();

  let rawStrata = $state<Partial<Record<StrataNumberKey, string>>>({});
  let lastRevisionKey = '';

  $effect(() => {
    const key = `${ctrl.original?.plotNumber ?? '__new__'}:${ctrl.headerRevision}`;
    if (key !== lastRevisionKey) {
      lastRevisionKey = key;
      rawStrata = {};
    }
  });

  const disabled = $derived(ctrl.headerInputsDisabled);
  const heightDisabled = $derived(IS_WEB_READONLY || ctrl.children.heightEditingDisabled);
  const speciesDisabled = $derived(IS_WEB_READONLY || ctrl.children.speciesEditingDisabled);
  const collectedDisabled = $derived(IS_WEB_READONLY || ctrl.children.collectedEditingDisabled);
  const createDisabled = $derived(
    IS_WEB_READONLY ||
      ctrl.childParentDisabled ||
      ctrl.childUnsaved ||
      !ctrl.children.speciesReferenceReady ||
      ctrl.children.speciesReferenceBusy
  );
  const showHeights = $derived(ctrl.vegetationMode === 'height' && !ctrl.extendedShrubs);
  const abFormName = $derived(ctrl.extendedShrubs ? 'SubVegAXL' : 'SubVegAXL_BC');
  const classified = $derived(classifyVegRowsForClassicCard(ctrl.children.vegList));

  function fieldDisabled(key: keyof FS882Header): boolean {
    if (disabled) return true;
    if (Object.keys(ctrl.capabilities).length > 0 && ctrl.capabilities[key] !== true) return true;
    return false;
  }

  function isHeaderDraft(key: keyof FS882Header): boolean {
    if (!ctrl.original) return ctrl.draft[key] != null && ctrl.draft[key] !== '' && ctrl.draft[key] !== false;
    return ctrl.draft[key] !== ctrl.original[key];
  }

  function strataDisplay(key: StrataNumberKey): string {
    if (rawStrata[key] !== undefined) return rawStrata[key] ?? '';
    const v = ctrl.draft[key];
    return v == null ? '' : String(v);
  }

  function setStrataNumber(key: StrataNumberKey, raw: string, label: string) {
    rawStrata = { ...rawStrata, [key]: raw };
    const trimmed = raw.trim();
    if (trimmed === '') {
      ctrl.draft[key] = null;
      ctrl.validateHeader(key, null);
      ctrl.markDirty();
      return;
    }
    const parsed = Number(trimmed);
    if (!Number.isFinite(parsed) || parsed < 0 || Math.fround(parsed) >= 100) {
      ctrl.validateHeader(key, `${label} must be a percent cover from 0 to under 100% (e.g. 99.9%).`);
      ctrl.markDirty();
      return;
    }
    ctrl.draft[key] = parsed === 0 ? 0 : parsed;
    ctrl.validateHeader(key, null);
    ctrl.markDirty();
  }

  function vegNumVal(row: VegRecord, field: HeightField): string {
    const staged = ctrl.children.heightDrafts[String(row.id)]?.[field];
    if (staged !== undefined) return staged.raw;
    const val = row[field];
    return val == null ? '' : String(val);
  }

  function vegNumErr(row: VegRecord, field: HeightField): string | null {
    return ctrl.children.heightDrafts[String(row.id)]?.[field]?.error ?? null;
  }

  function vegSpeciesVal(row: VegRecord): string {
    const staged = ctrl.children.speciesDrafts[String(row.id)];
    if (staged !== undefined) return staged.raw;
    return row.species ?? '';
  }

  function vegSpeciesErr(row: VegRecord): string | null {
    return ctrl.children.speciesDrafts[String(row.id)]?.error ?? null;
  }

  function vegCollectedVal(row: VegRecord): string {
    const staged = ctrl.children.collectedDrafts[String(row.id)];
    const val = staged !== undefined ? staged.value : row.collected;
    return val ?? '—';
  }

  function isVegRowDraft(row: VegRecord): boolean {
    const key = String(row.id);
    return Boolean(
      ctrl.children.heightDrafts[key] || ctrl.children.speciesDrafts[key] || ctrl.children.collectedDrafts[key]
    );
  }

  function formatCalcCover(val: number | null): string {
    return val === null ? '—' : `${Math.round(val * 100) / 100}%`;
  }
</script>

<article class="classic-card" data-classic-card="veg" aria-label="FS882 Card 3 — Vegetation">
  <header class="classic-card-masthead">
    <div>
      <div class="classic-card-kicker">B.C. Ministry of Forests · LMH25 Field Card</div>
      <div class="classic-card-title">CARD 3 — VEGETATION (FS882)</div>
    </div>
    <div class="classic-card-badges">
      <label
        class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded border border-vpro-border bg-white text-[11px] font-semibold cursor-pointer"
        data-help-id="veg.covers"
      >
        <input
          type="checkbox"
          data-extended-shrubs
          checked={ctrl.extendedShrubs}
          disabled={ctrl.busy || ctrl.headerWorkflowBusy}
          onchange={(e) => ctrl.setExtendedShrubs(e.currentTarget.checked)}
        />
        Show extended shrub layers (5a–5c)
      </label>
      <button
        type="button"
        class="classic-mini-btn"
        data-classic-height-toggle
        disabled={ctrl.extendedShrubs || ctrl.busy || ctrl.headerWorkflowBusy}
        onclick={() => {
          ctrl.vegetationMode = ctrl.vegetationMode === 'height' ? 'cover' : 'height';
        }}
      >
        {showHeights ? 'Hide Heights' : 'Show Heights'}
      </button>
      {#if !IS_WEB_READONLY}
        <button
          type="button"
          class="classic-mini-btn"
          data-classic-species-check
          disabled={ctrl.childParentDisabled || ctrl.childUnsaved || Object.keys(ctrl.headerValidation).length > 0}
          onclick={() => ctrl.openSpeciesCodeCheck()}
        >
          <CheckSquare size={11} aria-hidden="true" /> Check Species Codes
        </button>
      {/if}
      <span class="classic-card-stamp">PLOT: {ctrl.draft.plotNumber || '(New)'}</span>
    </div>
  </header>

  {#if ctrl.extendedShrubs}
    <p class="mb-2 px-2 py-1 text-[11px] rounded bg-amber-50 border border-amber-200 text-amber-900" data-extended-shrub-notice>
      {extendedShrubsNotice}
    </p>
  {/if}

  <!-- Section 1: Vegetation Survey & Strata Covers -->
  <section class="classic-block">
    <div class="classic-block-header">
      <span>1. Vegetation Survey &amp; Strata Covers (%)</span>
      <span class="classic-mono">
        Calc (99% cap): A {formatCalcCover(ctrl.children.totalTreeCover)} · B {formatCalcCover(ctrl.children.totalShrubCover)} · C {formatCalcCover(ctrl.children.totalHerbCover)} · D {formatCalcCover(ctrl.children.totalMossCover)}
      </span>
    </div>
    <div class="classic-grid">
      <div class="classic-cell" class:is-draft={isHeaderDraft('vegSurveyor')} style="grid-column: span 3;">
        <label class="classic-label" for="classic-vegSurveyor">Veg Surveyor</label>
        <input
          id="classic-vegSurveyor"
          data-column="VegSurveyor"
          type="text"
          class="classic-input"
          value={ctrl.draft.vegSurveyor ?? ''}
          disabled={fieldDisabled('vegSurveyor')}
          oninput={(e) => {
            ctrl.draft.vegSurveyor = e.currentTarget.value === '' ? null : e.currentTarget.value;
            ctrl.markDirty();
          }}
        />
      </div>
      <div class="classic-cell" class:is-draft={isHeaderDraft('speciesListComplete')} style="grid-column: span 3;">
        <span class="classic-label">Completeness</span>
        <label class="classic-check-label mt-0.5">
          <input
            type="checkbox"
            data-column="SpeciesListComplete"
            checked={Boolean(ctrl.draft.speciesListComplete)}
            disabled={fieldDisabled('speciesListComplete')}
            onchange={(e) => {
              ctrl.draft.speciesListComplete = e.currentTarget.checked;
              ctrl.markDirty();
            }}
          />
          Species list complete
        </label>
      </div>
      {#each [
        ['strataCoverTree', 'StrataCoverTree', 'Strata A (Tree %)'],
        ['strataCoverShrub', 'StrataCoverShrub', 'Strata B (Shrub %)'],
        ['strataCoverHerb', 'StrataCoverHerb', 'Strata C (Herb %)'],
        ['strataCoverMoss', 'StrataCoverMoss', 'Strata D (Moss %)'],
      ] as const as [key, col, label] (key)}
        <div
          class="classic-cell"
          class:is-draft={isHeaderDraft(key)}
          class:is-error={Boolean(ctrl.headerValidation[key])}
          style="grid-column: span 3;"
        >
          <label class="classic-label" for={`classic-${key}`}>{label}</label>
          <input
            id={`classic-${key}`}
            data-column={col}
            type="text"
            inputmode="decimal"
            class="classic-input classic-mono classic-num"
            value={strataDisplay(key)}
            disabled={fieldDisabled(key)}
            aria-invalid={ctrl.headerValidation[key] ? 'true' : undefined}
            oninput={(e) => setStrataNumber(key, e.currentTarget.value, label)}
          />
          {#if ctrl.headerValidation[key]}<p class="classic-field-error" role="alert">{ctrl.headerValidation[key]}</p>{/if}
        </div>
      {/each}
    </div>
  </section>

  {#if ctrl.children.vegetationReadUnavailable}
    <p role="alert" class="p-2 mb-2 bg-amber-50 border border-amber-200 text-amber-900 text-xs" data-classic-veg-unavailable>
      Ordinary ID-keyed vegetation is unavailable: {ctrl.children.vegetationReadUnavailable}
    </p>
  {:else}
    <!-- Section 2: Trees & Shrubs (Layers A & B) -->
    <section class="classic-block" data-classic-veg-ab>
      <div class="classic-block-header">
        <span>2. Tree &amp; Shrub Species — Layers A &amp; B ({classified.treeShrub.length})</span>
        {#if !IS_WEB_READONLY}
          <div class="flex items-center gap-1">
            <button
              type="button"
              class="classic-mini-btn classic-mini-btn-primary"
              data-classic-add-veg-ab
              disabled={createDisabled}
              onclick={() => ctrl.children.startVegetationCreation(abFormName)}
            >
              <Plus size={11} aria-hidden="true" /> Add Tree/Shrub Row
            </button>
            <button
              type="button"
              class="classic-mini-btn"
              data-classic-quick-species
              disabled={ctrl.childParentDisabled || ctrl.childUnsaved}
              onclick={() => {
                ctrl.children.showSpeciesModal = true;
              }}
            >
              Quick Lookup
            </button>
          </div>
        {/if}
      </div>
      <div class="classic-table-wrap">
        <table class="classic-table">
          <thead>
            <tr>
              <th>Species</th>
              <th>Coll</th>
              <th>A1</th>
              {#if showHeights}<th>H1</th>{/if}
              <th>A2</th>
              {#if showHeights}<th>H2</th>{/if}
              <th>A3</th>
              {#if showHeights}<th>H3</th>{/if}
              <th>TotA</th>
              <th>B1</th>
              {#if showHeights}<th>H4</th>{/if}
              <th>B2</th>
              {#if showHeights}<th>H5</th>{/if}
              {#if ctrl.extendedShrubs}
                <th>5a</th>
                <th>5b</th>
                <th>5c</th>
              {/if}
              <th>TotB</th>
              {#if !IS_WEB_READONLY}<th style="width: 32px;">Del</th>{/if}
            </tr>
          </thead>
          <tbody>
            {#each classified.treeShrub as row (row.id)}
              <tr class:is-draft={isVegRowDraft(row)} data-classic-veg-row={row.id}>
                <td style="min-width: 78px;">
                  <input
                    type="text"
                    class="classic-input classic-mono font-semibold uppercase"
                    aria-label={`Tree/Shrub species ${row.id}`}
                    value={vegSpeciesVal(row)}
                    disabled={speciesDisabled}
                    aria-invalid={vegSpeciesErr(row) ? 'true' : undefined}
                    oninput={(e) => ctrl.children.stageSpeciesCell(abFormName, row.id, e.currentTarget.value)}
                  />
                </td>
                <td style="width: 36px; text-align: center;">
                  <button
                    type="button"
                    class="classic-mini-btn classic-mono"
                    aria-label={`Toggle collected for row ${row.id}`}
                    disabled={collectedDisabled}
                    onclick={() => ctrl.children.stageCollectedCell(row.id, abFormName)}
                  >
                    {vegCollectedVal(row)}
                  </button>
                </td>
                {#each (
                  [
                    ['cover1', 'Cover1'],
                    ...(showHeights ? ([['height1', 'Height1']] as const) : []),
                    ['cover2', 'Cover2'],
                    ...(showHeights ? ([['height2', 'Height2']] as const) : []),
                    ['cover3', 'Cover3'],
                    ...(showHeights ? ([['height3', 'Height3']] as const) : []),
                    ['totalA', 'TotalA'],
                    ['cover4', 'Cover4'],
                    ...(showHeights ? ([['height4', 'Height4']] as const) : []),
                    ['cover5', 'Cover5'],
                    ...(showHeights ? ([['height5', 'Height5']] as const) : []),
                    ...(ctrl.extendedShrubs
                      ? ([
                          ['cover5a', 'Cover5a'],
                          ['cover5b', 'Cover5b'],
                          ['cover5c', 'Cover5c'],
                        ] as const)
                      : []),
                    ['totalB', 'TotalB'],
                  ] as const
                ) as [field, col] (field)}
                  <td style="width: 48px;">
                    <input
                      type="text"
                      inputmode="decimal"
                      class="classic-input classic-mono classic-num"
                      aria-label={`${col} row ${row.id}`}
                      value={vegNumVal(row, field)}
                      disabled={heightDisabled}
                      aria-invalid={vegNumErr(row, field) ? 'true' : undefined}
                      title={vegNumErr(row, field) ?? col}
                      oninput={(e) => ctrl.children.stageHeightCell(row.id, col, e.currentTarget.value, abFormName)}
                    />
                  </td>
                {/each}
                {#if !IS_WEB_READONLY}
                  <td>
                    <button
                      type="button"
                      class="classic-mini-btn classic-mini-btn-danger"
                      title="Review and delete vegetation row"
                      aria-label={`Delete vegetation row ${row.id}`}
                      disabled={ctrl.childParentDisabled || ctrl.childUnsaved}
                      onclick={() => void ctrl.children.reviewVegetationDeletion(abFormName, row.id)}
                    >
                      <Trash2 size={11} aria-hidden="true" />
                    </button>
                  </td>
                {/if}
              </tr>
            {:else}
              <tr>
                <td colspan={20} class="text-center italic py-2 text-vpro-ink-muted">No tree or shrub species recorded.</td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    </section>

    <!-- Section 3 & 4: Herb (C) and Moss/Lichen (D) side-by-side when wide -->
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-2 mb-2">
      <!-- Herb Layer C -->
      <section class="classic-block mb-0" data-classic-veg-c>
        <div class="classic-block-header">
          <span>3. Herb Layer — C ({classified.herb.length})</span>
          {#if !IS_WEB_READONLY}
            <button
              type="button"
              class="classic-mini-btn classic-mini-btn-primary"
              data-classic-add-veg-c
              disabled={createDisabled}
              onclick={() => ctrl.children.startVegetationCreation('SubVegCXL')}
            >
              <Plus size={11} aria-hidden="true" /> Add Herb
            </button>
          {/if}
        </div>
        <div class="classic-table-wrap">
          <table class="classic-table">
            <thead>
              <tr>
                <th>Species</th>
                <th>Coll</th>
                <th>Cover C</th>
                <th>Height C</th>
                {#if !IS_WEB_READONLY}<th style="width: 32px;">Del</th>{/if}
              </tr>
            </thead>
            <tbody>
              {#each classified.herb as row (row.id)}
                <tr class:is-draft={isVegRowDraft(row)} data-classic-veg-c-row={row.id}>
                  <td>
                    <input
                      type="text"
                      class="classic-input classic-mono font-semibold uppercase"
                      aria-label={`Herb species ${row.id}`}
                      value={vegSpeciesVal(row)}
                      disabled={speciesDisabled}
                      aria-invalid={vegSpeciesErr(row) ? 'true' : undefined}
                      oninput={(e) => ctrl.children.stageSpeciesCell('SubVegCXL', row.id, e.currentTarget.value)}
                    />
                  </td>
                  <td style="width: 36px; text-align: center;">
                    <button
                      type="button"
                      class="classic-mini-btn classic-mono"
                      aria-label={`Toggle collected for herb row ${row.id}`}
                      disabled={collectedDisabled}
                      onclick={() => ctrl.children.stageCollectedCell(row.id, 'SubVegCXL')}
                    >
                      {vegCollectedVal(row)}
                    </button>
                  </td>
                  <td style="width: 56px;">
                    <input
                      type="text"
                      inputmode="decimal"
                      class="classic-input classic-mono classic-num"
                      aria-label={`Cover6 row ${row.id}`}
                      value={vegNumVal(row, 'cover6')}
                      disabled={heightDisabled}
                      aria-invalid={vegNumErr(row, 'cover6') ? 'true' : undefined}
                      title={vegNumErr(row, 'cover6') ?? 'Cover6'}
                      oninput={(e) => ctrl.children.stageHeightCell(row.id, 'Cover6', e.currentTarget.value, 'SubVegCXL')}
                    />
                  </td>
                  <td style="width: 56px;">
                    <input
                      type="text"
                      inputmode="decimal"
                      class="classic-input classic-mono classic-num"
                      aria-label={`Height6 row ${row.id}`}
                      value={vegNumVal(row, 'height6')}
                      disabled={heightDisabled}
                      aria-invalid={vegNumErr(row, 'height6') ? 'true' : undefined}
                      title={vegNumErr(row, 'height6') ?? 'Height6'}
                      oninput={(e) => ctrl.children.stageHeightCell(row.id, 'Height6', e.currentTarget.value, 'SubVegCXL')}
                    />
                  </td>
                  {#if !IS_WEB_READONLY}
                    <td>
                      <button
                        type="button"
                        class="classic-mini-btn classic-mini-btn-danger"
                        title="Review and delete herb row"
                        aria-label={`Delete herb row ${row.id}`}
                        disabled={ctrl.childParentDisabled || ctrl.childUnsaved}
                        onclick={() => void ctrl.children.reviewVegetationDeletion('SubVegCXL', row.id)}
                      >
                        <Trash2 size={11} aria-hidden="true" />
                      </button>
                    </td>
                  {/if}
                </tr>
              {:else}
                <tr>
                  <td colspan={IS_WEB_READONLY ? 4 : 5} class="text-center italic py-2 text-vpro-ink-muted">No herb species recorded.</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      </section>

      <!-- Moss / Lichen Layer D -->
      <section class="classic-block mb-0" data-classic-veg-d>
        <div class="classic-block-header">
          <span>4. Moss, Lichen &amp; Seedlings — D ({classified.moss.length})</span>
          {#if !IS_WEB_READONLY}
            <button
              type="button"
              class="classic-mini-btn classic-mini-btn-primary"
              data-classic-add-veg-d
              disabled={createDisabled}
              onclick={() => ctrl.children.startVegetationCreation('SubVegDXL')}
            >
              <Plus size={11} aria-hidden="true" /> Add Moss/Lichen
            </button>
          {/if}
        </div>
        <div class="classic-table-wrap">
          <table class="classic-table">
            <thead>
              <tr>
                <th>Species</th>
                <th>Coll</th>
                <th>D (7)</th>
                <th>D (8)</th>
                <th>D (9)</th>
                {#if !IS_WEB_READONLY}<th style="width: 32px;">Del</th>{/if}
              </tr>
            </thead>
            <tbody>
              {#each classified.moss as row (row.id)}
                <tr class:is-draft={isVegRowDraft(row)} data-classic-veg-d-row={row.id}>
                  <td>
                    <input
                      type="text"
                      class="classic-input classic-mono font-semibold uppercase"
                      aria-label={`Moss species ${row.id}`}
                      value={vegSpeciesVal(row)}
                      disabled={speciesDisabled}
                      aria-invalid={vegSpeciesErr(row) ? 'true' : undefined}
                      oninput={(e) => ctrl.children.stageSpeciesCell('SubVegDXL', row.id, e.currentTarget.value)}
                    />
                  </td>
                  <td style="width: 36px; text-align: center;">
                    <button
                      type="button"
                      class="classic-mini-btn classic-mono"
                      aria-label={`Toggle collected for moss row ${row.id}`}
                      disabled={collectedDisabled}
                      onclick={() => ctrl.children.stageCollectedCell(row.id, 'SubVegDXL')}
                    >
                      {vegCollectedVal(row)}
                    </button>
                  </td>
                  {#each [
                    ['cover7', 'Cover7'],
                    ['cover8', 'Cover8'],
                    ['cover9', 'Cover9'],
                  ] as const as [field, col] (field)}
                    <td style="width: 50px;">
                      <input
                        type="text"
                        inputmode="decimal"
                        class="classic-input classic-mono classic-num"
                        aria-label={`${col} row ${row.id}`}
                        value={vegNumVal(row, field)}
                        disabled={heightDisabled}
                        aria-invalid={vegNumErr(row, field) ? 'true' : undefined}
                        title={vegNumErr(row, field) ?? col}
                        oninput={(e) => ctrl.children.stageHeightCell(row.id, col, e.currentTarget.value, 'SubVegDXL')}
                      />
                    </td>
                  {/each}
                  {#if !IS_WEB_READONLY}
                    <td>
                      <button
                        type="button"
                        class="classic-mini-btn classic-mini-btn-danger"
                        title="Review and delete moss row"
                        aria-label={`Delete moss row ${row.id}`}
                        disabled={ctrl.childParentDisabled || ctrl.childUnsaved}
                        onclick={() => void ctrl.children.reviewVegetationDeletion('SubVegDXL', row.id)}
                      >
                        <Trash2 size={11} aria-hidden="true" />
                      </button>
                    </td>
                  {/if}
                </tr>
              {:else}
                <tr>
                  <td colspan={IS_WEB_READONLY ? 5 : 6} class="text-center italic py-2 text-vpro-ink-muted">
                    No moss or lichen species recorded.
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  {/if}

  <!-- Section 5: Vegetation Notes -->
  <section class="classic-block">
    <div class="classic-block-header">
      <span>5. Vegetation Notes</span>
    </div>
    <div class="classic-grid">
      <div class="classic-cell" class:is-draft={isHeaderDraft('vegNotes')} style="grid-column: span 12;" data-full-row>
        <label class="classic-label" for="classic-vegNotes">Vegetation &amp; Floristic Notes</label>
        <textarea
          id="classic-vegNotes"
          data-column="VegNotes"
          rows={2}
          class="classic-textarea"
          value={ctrl.draft.vegNotes ?? ''}
          disabled={fieldDisabled('vegNotes')}
          oninput={(e) => {
            ctrl.draft.vegNotes = e.currentTarget.value === '' ? null : e.currentTarget.value;
            ctrl.markDirty();
          }}
        ></textarea>
      </div>
    </div>
  </section>
</article>
