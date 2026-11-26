<script lang="ts">
  import { Plus, Trash2 } from '@lucide/svelte';
  import type { FS882Header, HumusRecord, MineralRecord } from '../../bindings/github.com/boostao/vpro/app';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import { sortHumusHorizonsLMH25, sortMineralHorizonsLMH25 } from './classicFS882Helpers';
  import type { FS882Controller } from './fs882FormController.svelte';

  type NullableTextKey = {
    [K in keyof FS882Header]: FS882Header[K] extends string | null ? K : never;
  }[keyof FS882Header];
  type NumberKey = {
    [K in keyof FS882Header]: FS882Header[K] extends number | null ? K : never;
  }[keyof FS882Header];

  let { ctrl }: { ctrl: FS882Controller } = $props();

  let rawNumbers = $state<Partial<Record<NumberKey, string>>>({});
  let lastRevisionKey = '';

  $effect(() => {
    const key = `${ctrl.original?.plotNumber ?? '__new__'}:${ctrl.headerRevision}`;
    if (key !== lastRevisionKey) {
      lastRevisionKey = key;
      rawNumbers = {};
    }
  });

  const disabled = $derived(ctrl.headerInputsDisabled);
  const soilDisabled = $derived(IS_WEB_READONLY || ctrl.children.soilEditingDisabled);
  const sortedHumus = $derived(sortHumusHorizonsLMH25(ctrl.children.humusList, ctrl.children.soilDrafts));
  const sortedMineral = $derived(sortMineralHorizonsLMH25(ctrl.children.mineralList, ctrl.children.soilDrafts));

  function fieldDisabled(key: keyof FS882Header): boolean {
    if (disabled) return true;
    if (Object.keys(ctrl.capabilities).length > 0 && ctrl.capabilities[key] !== true) return true;
    return false;
  }

  function isFieldDraft(key: keyof FS882Header): boolean {
    if (!ctrl.original) return ctrl.draft[key] != null && ctrl.draft[key] !== '';
    return ctrl.draft[key] !== ctrl.original[key];
  }

  function setText(key: Exclude<NullableTextKey, 'plotNumber'>, raw: string, maxLen = 0, label = String(key)) {
    const value = raw === '' ? null : raw;
    ctrl.draft[key] = value;
    if (value !== null && value.includes('\u0000')) {
      ctrl.validateHeader(key, `${label} cannot contain NUL characters.`);
    } else if (value !== null && maxLen > 0 && value.length > maxLen) {
      ctrl.validateHeader(key, `${label} must be at most ${maxLen} characters.`);
    } else {
      ctrl.validateHeader(key, null);
    }
    ctrl.markDirty();
  }

  function numDisplay(key: NumberKey): string {
    if (rawNumbers[key] !== undefined) return rawNumbers[key] ?? '';
    const v = ctrl.draft[key];
    return v == null ? '' : String(v);
  }

  function setNumber(key: NumberKey, raw: string, label: string) {
    rawNumbers = { ...rawNumbers, [key]: raw };
    const trimmed = raw.trim();
    if (trimmed === '') {
      ctrl.draft[key] = null;
      ctrl.validateHeader(key, null);
      ctrl.markDirty();
      return;
    }
    const parsed = Number(trimmed);
    if (!Number.isFinite(parsed)) {
      ctrl.validateHeader(key, `${label} must be a valid number.`);
      ctrl.markDirty();
      return;
    }
    ctrl.draft[key] = parsed === 0 ? 0 : parsed;
    ctrl.validateHeader(key, null);
    ctrl.markDirty();
  }

  function humusCellVal(row: HumusRecord, field: keyof HumusRecord, draftKey: string): string {
    const staged = ctrl.children.soilDrafts[`Humus/${row.id}`]?.cells?.[draftKey];
    if (staged !== undefined) return staged.raw;
    const val = row[field];
    return val == null ? '' : String(val);
  }

  function humusCellErr(row: HumusRecord, draftKey: string): string | null {
    return ctrl.children.soilDrafts[`Humus/${row.id}`]?.cells?.[draftKey]?.error ?? null;
  }

  function humusRowDraft(row: HumusRecord): boolean {
    return Boolean(ctrl.children.soilDrafts[`Humus/${row.id}`]);
  }

  function mineralCellVal(row: MineralRecord, field: keyof MineralRecord, draftKey: string): string {
    const staged = ctrl.children.soilDrafts[`Mineral/${row.id}`]?.cells?.[draftKey];
    if (staged !== undefined) return staged.raw;
    const val = row[field];
    return val == null ? '' : String(val);
  }

  function mineralCellErr(row: MineralRecord, draftKey: string): string | null {
    return ctrl.children.soilDrafts[`Mineral/${row.id}`]?.cells?.[draftKey]?.error ?? null;
  }

  function mineralRowDraft(row: MineralRecord): boolean {
    return Boolean(ctrl.children.soilDrafts[`Mineral/${row.id}`]);
  }
</script>

<article class="classic-card" data-classic-card="soil" aria-label="FS882 Card 2 — Soil and Terrain">
  <header class="classic-card-masthead">
    <div>
      <div class="classic-card-kicker">B.C. Ministry of Forests · LMH25 Field Card</div>
      <div class="classic-card-title">CARD 2 — SOIL &amp; TERRAIN (FS882)</div>
    </div>
    <div class="classic-card-badges">
      {#if ctrl.draft.soilClassSubGroup || ctrl.draft.soilClassGroup}
        <span class="classic-card-stamp">
          {[ctrl.draft.soilClassSubGroup, ctrl.draft.soilClassGroup].filter(Boolean).join('.')}
        </span>
      {/if}
      {#if ctrl.draft.humusForm}
        <span class="classic-card-stamp">HUMUS: {ctrl.draft.humusForm}</span>
      {/if}
      <span class="classic-card-stamp">PLOT: {ctrl.draft.plotNumber || '(New)'}</span>
    </div>
  </header>

  <!-- Section 1: Soil Classification, Humus Form & Drainage -->
  <section class="classic-block">
    <div class="classic-block-header">
      <span>1. Soil Classification, Humus Form, Rooting &amp; Drainage</span>
    </div>
    <div class="classic-grid">
      <div class="classic-cell" class:is-draft={isFieldDraft('soilSurveyor')} style="grid-column: span 3;">
        <label class="classic-label" for="header-soilSurveyor">Soil Surveyor</label>
        <input
          id="header-soilSurveyor"
          data-column="SoilSurveyor"
          type="text"
          class="classic-input"
          value={ctrl.draft.soilSurveyor ?? ''}
          disabled={fieldDisabled('soilSurveyor')}
          oninput={(e) => setText('soilSurveyor', e.currentTarget.value, 30, 'Soil Surveyor')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('soilClassSubGroup')} style="grid-column: span 3;">
        <label class="classic-label" for="classic-soilClassSubGroup">Soil Subgroup</label>
        <input
          id="classic-soilClassSubGroup"
          data-column="SoilClassSubGroup"
          type="text"
          class="classic-input classic-mono"
          value={ctrl.draft.soilClassSubGroup ?? ''}
          disabled={fieldDisabled('soilClassSubGroup')}
          oninput={(e) => setText('soilClassSubGroup', e.currentTarget.value, 10, 'Soil Subgroup')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('soilClassGroup')} style="grid-column: span 3;">
        <label class="classic-label" for="classic-soilClassGroup">Great Group</label>
        <input
          id="classic-soilClassGroup"
          data-column="SoilClassGroup"
          type="text"
          class="classic-input classic-mono"
          value={ctrl.draft.soilClassGroup ?? ''}
          disabled={fieldDisabled('soilClassGroup')}
          oninput={(e) => setText('soilClassGroup', e.currentTarget.value, 10, 'Great Group')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('soilDrainage')} style="grid-column: span 3;">
        <label class="classic-label" for="classic-soilDrainage">Soil Drainage</label>
        <input
          id="classic-soilDrainage"
          data-column="SoilDrainage"
          type="text"
          class="classic-input classic-mono"
          value={ctrl.draft.soilDrainage ?? ''}
          disabled={fieldDisabled('soilDrainage')}
          oninput={(e) => setText('soilDrainage', e.currentTarget.value, 5, 'Soil Drainage')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('humusForm')} style="grid-column: span 3;">
        <label class="classic-label" for="classic-humusForm">Humus Form</label>
        <input
          id="classic-humusForm"
          data-column="HumusForm"
          type="text"
          class="classic-input classic-mono"
          value={ctrl.draft.humusForm ?? ''}
          disabled={fieldDisabled('humusForm')}
          oninput={(e) => setText('humusForm', e.currentTarget.value, 15, 'Humus Form')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('humusFormPhase')} style="grid-column: span 3;">
        <label class="classic-label" for="classic-humusFormPhase">Humus Phase</label>
        <input
          id="classic-humusFormPhase"
          data-column="HumusFormPhase"
          type="text"
          class="classic-input classic-mono"
          value={ctrl.draft.humusFormPhase ?? ''}
          disabled={fieldDisabled('humusFormPhase')}
          oninput={(e) => setText('humusFormPhase', e.currentTarget.value, 15, 'Humus Phase')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('humusThickness')} class:is-error={Boolean(ctrl.headerValidation.humusThickness)} style="grid-column: span 2;">
        <label class="classic-label" for="classic-humusThickness">Humus Thick. (cm)</label>
        <input
          id="classic-humusThickness"
          data-column="HumusThickness"
          type="text"
          inputmode="decimal"
          class="classic-input classic-mono classic-num"
          value={numDisplay('humusThickness')}
          disabled={fieldDisabled('humusThickness')}
          oninput={(e) => setNumber('humusThickness', e.currentTarget.value, 'Humus Thickness')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('rootingDepth')} style="grid-column: span 2;">
        <label class="classic-label" for="classic-rootingDepth">Rooting Depth (cm)</label>
        <input
          id="classic-rootingDepth"
          data-column="RootingDepth"
          type="text"
          inputmode="decimal"
          class="classic-input classic-mono classic-num"
          value={numDisplay('rootingDepth')}
          disabled={fieldDisabled('rootingDepth')}
          oninput={(e) => setNumber('rootingDepth', e.currentTarget.value, 'Rooting Depth')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('seepageDepth')} style="grid-column: span 2;">
        <label class="classic-label" for="classic-seepageDepth">Seepage Depth (cm)</label>
        <input
          id="classic-seepageDepth"
          data-column="SeepageDepth"
          type="text"
          inputmode="decimal"
          class="classic-input classic-mono classic-num"
          value={numDisplay('seepageDepth')}
          disabled={fieldDisabled('seepageDepth')}
          oninput={(e) => setNumber('seepageDepth', e.currentTarget.value, 'Seepage Depth')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('rootRestrictingType')} style="grid-column: span 3;">
        <label class="classic-label" for="classic-rootRestrictingType">Root Restrict. Type</label>
        <input
          id="classic-rootRestrictingType"
          data-column="RootRestrictingType"
          type="text"
          class="classic-input classic-mono"
          value={ctrl.draft.rootRestrictingType ?? ''}
          disabled={fieldDisabled('rootRestrictingType')}
          oninput={(e) => setText('rootRestrictingType', e.currentTarget.value, 10, 'Root Restricting Type')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('rootRestrictingDepth')} style="grid-column: span 2;">
        <label class="classic-label" for="classic-rootRestrictingDepth">Restrict. Depth (cm)</label>
        <input
          id="classic-rootRestrictingDepth"
          data-column="RootRestrictingDepth"
          type="text"
          inputmode="decimal"
          class="classic-input classic-mono classic-num"
          value={numDisplay('rootRestrictingDepth')}
          disabled={fieldDisabled('rootRestrictingDepth')}
          oninput={(e) => setNumber('rootRestrictingDepth', e.currentTarget.value, 'Restricting Depth')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('rootZoneParticleSize')} style="grid-column: span 2;">
        <label class="classic-label" for="classic-rootZoneParticleSize">Root Zone Part. Size</label>
        <input
          id="classic-rootZoneParticleSize"
          data-column="RootZoneParticleSize"
          type="text"
          class="classic-input classic-mono"
          value={ctrl.draft.rootZoneParticleSize ?? ''}
          disabled={fieldDisabled('rootZoneParticleSize')}
          oninput={(e) => setText('rootZoneParticleSize', e.currentTarget.value, 10, 'Root Zone Particle Size')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('waterSource')} style="grid-column: span 2;">
        <label class="classic-label" for="classic-waterSource">Water Source</label>
        <input
          id="classic-waterSource"
          data-column="WaterSource"
          type="text"
          class="classic-input classic-mono"
          value={ctrl.draft.waterSource ?? ''}
          disabled={fieldDisabled('waterSource')}
          oninput={(e) => setText('waterSource', e.currentTarget.value, 10, 'Water Source')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('floodingRegimeFreq') || isFieldDraft('floodingRegimeDur')} style="grid-column: span 3;">
        <label class="classic-label" for="classic-floodingRegimeFreq">Flooding (Freq / Dur)</label>
        <div class="flex gap-1">
          <input
            id="classic-floodingRegimeFreq"
            data-column="FloodingRegimeFreq"
            type="text"
            placeholder="Freq"
            class="classic-input classic-mono"
            value={ctrl.draft.floodingRegimeFreq ?? ''}
            disabled={fieldDisabled('floodingRegimeFreq')}
            oninput={(e) => setText('floodingRegimeFreq', e.currentTarget.value, 5, 'Flooding Freq')}
          />
          <input
            id="classic-floodingRegimeDur"
            data-column="FloodingRegimeDur"
            aria-label="Flooding Duration"
            type="text"
            placeholder="Dur"
            class="classic-input classic-mono"
            value={ctrl.draft.floodingRegimeDur ?? ''}
            disabled={fieldDisabled('floodingRegimeDur')}
            oninput={(e) => setText('floodingRegimeDur', e.currentTarget.value, 5, 'Flooding Dur')}
          />
        </div>
      </div>
    </div>
  </section>

  <!-- Section 2: Bedrock & Parent Material / Terrain -->
  <section class="classic-block">
    <div class="classic-block-header">
      <span>2. Bedrock Geology &amp; Parent Material (Surface / Subsurface)</span>
    </div>
    <div class="classic-grid">
      {#each [
        ['terrainTextureSurf', 'TerrainTextureSurf', 'Surf. Texture'],
        ['surficialMaterialSurf', 'SurficialMaterialSurf', 'Surf. Material'],
        ['surfaceExpSurf', 'SurfaceExpSurf', 'Surf. Expression'],
        ['geoMorProSurf', 'GeoMorProSurf', 'Surf. Geomorph.'],
        ['terrainTextureSubSurf', 'TerrainTextureSubSurf', 'Subsurf. Texture'],
        ['surficialMaterialSubSurf', 'SurficialMaterialSubSurf', 'Subsurf. Material'],
        ['surfaceExpSubSurf', 'SurfaceExpSubSurf', 'Subsurf. Expr.'],
        ['geoMorProSubSurf', 'GeoMorProSubSurf', 'Subsurf. Geomorph.'],
      ] as const as [key, col, label] (key)}
        <div class="classic-cell" class:is-draft={isFieldDraft(key)} style="grid-column: span 3;">
          <label class="classic-label" for={`classic-${key}`}>{label}</label>
          <input
            id={`classic-${key}`}
            data-column={col}
            type="text"
            class="classic-input classic-mono"
            value={ctrl.draft[key] ?? ''}
            disabled={fieldDisabled(key)}
            oninput={(e) => setText(key, e.currentTarget.value, 15, label)}
          />
        </div>
      {/each}
      {#each [
        ['bedrockGeology1', 'BedrockGeology1', 'Bedrock 1'],
        ['bedrockGeology2', 'BedrockGeology2', 'Bedrock 2'],
        ['bedrockGeology3', 'BedrockGeology3', 'Bedrock 3'],
        ['coarseFragLith1', 'CoarseFragLith1', 'CF Lith 1'],
        ['coarseFragLith2', 'CoarseFragLith2', 'CF Lith 2'],
        ['coarseFragLith3', 'CoarseFragLith3', 'CF Lith 3'],
      ] as const as [key, col, label] (key)}
        <div class="classic-cell" class:is-draft={isFieldDraft(key)} style="grid-column: span 2;">
          <label class="classic-label" for={`classic-${key}`}>{label}</label>
          <input
            id={`classic-${key}`}
            data-column={col}
            type="text"
            class="classic-input classic-mono"
            value={ctrl.draft[key] ?? ''}
            disabled={fieldDisabled(key)}
            oninput={(e) => setText(key, e.currentTarget.value, 10, label)}
          />
        </div>
      {/each}
    </div>
  </section>

  <!-- Section 3: Organic Horizons (_Humus) — LMH25 Upward/Downward Ordering -->
  <section class="classic-block" data-classic-organic-horizons data-help-id="humus.upper_lower_depth">
    <div class="classic-block-header">
      <span>3. Organic Horizons ({sortedHumus.length}) — Upland L/F/H Upward (DESC) · Wetland Of/Om/Oh Downward (ASC)</span>
      <div class="flex items-center gap-1">
        {#if !IS_WEB_READONLY}
          <button
            type="button"
            class="classic-mini-btn classic-mini-btn-primary"
            data-classic-add-humus
            disabled={soilDisabled || ctrl.children.soilUnsaved}
            onclick={() => ctrl.children.openNewChild('humus')}
          >
            <Plus size={11} aria-hidden="true" /> Add Organic Horizon
          </button>
        {/if}
      </div>
    </div>
    {#if ctrl.children.historicalSoilUnavailable}
      <p role="status" class="p-2 text-xs text-amber-900 bg-amber-50">{ctrl.children.historicalSoilUnavailable}</p>
    {/if}
    <div class="classic-table-wrap">
      <table class="classic-table">
        <thead>
          <tr>
            <th>Horizon</th>
            <th>Upper (cm)</th>
            <th>Lower (cm)</th>
            <th>Str. Deg</th>
            <th>Str. Kind</th>
            <th>Mycel</th>
            <th>Fecal</th>
            <th>Roots Ab/Sz</th>
            <th>von Post</th>
            <th>pH</th>
            <th>Comment</th>
            {#if !IS_WEB_READONLY}<th style="width: 32px;">Del</th>{/if}
          </tr>
        </thead>
        <tbody>
          {#each sortedHumus as row (row.id)}
            <tr class:is-draft={humusRowDraft(row)} data-classic-humus-row={row.id}>
              <td style="min-width: 58px;">
                <input
                  type="text"
                  class="classic-input classic-mono font-semibold"
                  aria-label={`Organic horizon ${row.id}`}
                  value={humusCellVal(row, 'horizon', 'horizon')}
                  disabled={soilDisabled}
                  aria-invalid={humusCellErr(row, 'horizon') ? 'true' : undefined}
                  oninput={(e) => ctrl.children.stageSoilCell('Humus', row.id, 'Horizon', e.currentTarget.value)}
                />
              </td>
              <td style="width: 56px;">
                <input
                  type="text"
                  inputmode="decimal"
                  class="classic-input classic-mono classic-num"
                  aria-label={`Organic upper depth ${row.id}`}
                  value={humusCellVal(row, 'upperDepth', 'upperDepth')}
                  disabled={soilDisabled}
                  aria-invalid={humusCellErr(row, 'upperDepth') ? 'true' : undefined}
                  oninput={(e) => ctrl.children.stageSoilCell('Humus', row.id, 'UpperDepth', e.currentTarget.value)}
                />
              </td>
              <td style="width: 56px;">
                <input
                  type="text"
                  inputmode="decimal"
                  class="classic-input classic-mono classic-num"
                  aria-label={`Organic lower depth ${row.id}`}
                  value={humusCellVal(row, 'lowerDepth', 'lowerDepth')}
                  disabled={soilDisabled}
                  aria-invalid={humusCellErr(row, 'lowerDepth') ? 'true' : undefined}
                  oninput={(e) => ctrl.children.stageSoilCell('Humus', row.id, 'LowerDepth', e.currentTarget.value)}
                />
              </td>
              <td style="width: 52px;">
                <input
                  type="text"
                  class="classic-input classic-mono"
                  aria-label={`Humus structure degree ${row.id}`}
                  value={humusCellVal(row, 'humusStructureDegree', 'humusStructureDegree')}
                  disabled={soilDisabled}
                  oninput={(e) => ctrl.children.stageSoilCell('Humus', row.id, 'HumusStructureDegree', e.currentTarget.value)}
                />
              </td>
              <td style="width: 52px;">
                <input
                  type="text"
                  class="classic-input classic-mono"
                  aria-label={`Humus structure kind ${row.id}`}
                  value={humusCellVal(row, 'humusStructureKind', 'humusStructureKind')}
                  disabled={soilDisabled}
                  oninput={(e) => ctrl.children.stageSoilCell('Humus', row.id, 'HumusStructureKind', e.currentTarget.value)}
                />
              </td>
              <td style="width: 48px;">
                <input
                  type="text"
                  class="classic-input classic-mono"
                  aria-label={`Mycelium abundance ${row.id}`}
                  value={humusCellVal(row, 'mycelAbundance', 'mycelAbundance')}
                  disabled={soilDisabled}
                  oninput={(e) => ctrl.children.stageSoilCell('Humus', row.id, 'MycelAbundance', e.currentTarget.value)}
                />
              </td>
              <td style="width: 48px;">
                <input
                  type="text"
                  class="classic-input classic-mono"
                  aria-label={`Fecal abundance ${row.id}`}
                  value={humusCellVal(row, 'fecalAbundance', 'fecalAbundance')}
                  disabled={soilDisabled}
                  oninput={(e) => ctrl.children.stageSoilCell('Humus', row.id, 'FecalAbundance', e.currentTarget.value)}
                />
              </td>
              <td style="width: 78px;">
                <div class="flex gap-0.5">
                  <input
                    type="text"
                    class="classic-input classic-mono"
                    aria-label={`Humus roots abundance ${row.id}`}
                    placeholder="Ab"
                    value={humusCellVal(row, 'rootsAbundance', 'rootsAbundance')}
                    disabled={soilDisabled}
                    oninput={(e) => ctrl.children.stageSoilCell('Humus', row.id, 'RootsAbundance', e.currentTarget.value)}
                  />
                  <input
                    type="text"
                    class="classic-input classic-mono"
                    aria-label={`Humus roots size ${row.id}`}
                    placeholder="Sz"
                    value={humusCellVal(row, 'rootsSize', 'rootsSize')}
                    disabled={soilDisabled}
                    oninput={(e) => ctrl.children.stageSoilCell('Humus', row.id, 'RootsSize', e.currentTarget.value)}
                  />
                </div>
              </td>
              <td style="width: 48px;">
                <input
                  type="text"
                  inputmode="numeric"
                  class="classic-input classic-mono classic-num"
                  aria-label={`von Post ${row.id}`}
                  value={humusCellVal(row, 'vonPost', 'vonPost')}
                  disabled={soilDisabled}
                  oninput={(e) => ctrl.children.stageSoilCell('Humus', row.id, 'vonPost', e.currentTarget.value)}
                />
              </td>
              <td style="width: 48px;">
                <input
                  type="text"
                  inputmode="decimal"
                  class="classic-input classic-mono classic-num"
                  aria-label={`Humus pH ${row.id}`}
                  value={humusCellVal(row, 'ph', 'ph')}
                  disabled={soilDisabled}
                  oninput={(e) => ctrl.children.stageSoilCell('Humus', row.id, 'HumusFormpH', e.currentTarget.value)}
                />
              </td>
              <td style="min-width: 100px;">
                <input
                  type="text"
                  class="classic-input"
                  aria-label={`Humus comment ${row.id}`}
                  value={humusCellVal(row, 'comment', 'comment')}
                  disabled={soilDisabled}
                  oninput={(e) => ctrl.children.stageSoilCell('Humus', row.id, 'Comment', e.currentTarget.value)}
                />
              </td>
              {#if !IS_WEB_READONLY}
                <td>
                  <button
                    type="button"
                    class="classic-mini-btn classic-mini-btn-danger"
                    title="Delete organic horizon"
                    aria-label={`Delete organic horizon ${row.id}`}
                    disabled={soilDisabled || ctrl.children.soilUnsaved}
                    onclick={() => void ctrl.children.deleteHumus(row.id)}
                  >
                    <Trash2 size={11} aria-hidden="true" />
                  </button>
                </td>
              {/if}
            </tr>
          {:else}
            <tr>
              <td colspan={IS_WEB_READONLY ? 11 : 12} class="text-center italic py-2 text-vpro-ink-muted">
                No organic horizons recorded.
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  </section>

  <!-- Section 4: Mineral Horizons (_Mineral) — LMH25 Downward Ordering -->
  <section class="classic-block" data-classic-mineral-horizons data-help-id="mineral.texture_cf">
    <div class="classic-block-header">
      <span>4. Mineral Horizons ({sortedMineral.length}) — Downward from 0 cm (UpperDepth ASC)</span>
      {#if !IS_WEB_READONLY}
        <button
          type="button"
          class="classic-mini-btn classic-mini-btn-primary"
          data-classic-add-mineral
          disabled={soilDisabled || ctrl.children.soilUnsaved}
          onclick={() => ctrl.children.openNewChild('mineral')}
        >
          <Plus size={11} aria-hidden="true" /> Add Mineral Horizon
        </button>
      {/if}
    </div>
    <div class="classic-table-wrap">
      <table class="classic-table">
        <thead>
          <tr>
            <th>Horizon</th>
            <th>Upper (cm)</th>
            <th>Lower (cm)</th>
            <th>Texture</th>
            <th>Colour</th>
            <th>CF G/C/S</th>
            <th>CF Tot%</th>
            <th>Roots Ab/Sz</th>
            <th>pH</th>
            <th>Comments</th>
            {#if !IS_WEB_READONLY}<th style="width: 32px;">Del</th>{/if}
          </tr>
        </thead>
        <tbody>
          {#each sortedMineral as row (row.id)}
            <tr class:is-draft={mineralRowDraft(row)} data-classic-mineral-row={row.id}>
              <td style="min-width: 58px;">
                <input
                  type="text"
                  class="classic-input classic-mono font-semibold"
                  aria-label={`Mineral horizon ${row.id}`}
                  value={mineralCellVal(row, 'horizon', 'horizon')}
                  disabled={soilDisabled}
                  aria-invalid={mineralCellErr(row, 'horizon') ? 'true' : undefined}
                  oninput={(e) => ctrl.children.stageSoilCell('Mineral', row.id, 'Horizon', e.currentTarget.value)}
                />
              </td>
              <td style="width: 54px;">
                <input
                  type="text"
                  inputmode="decimal"
                  class="classic-input classic-mono classic-num"
                  aria-label={`Mineral upper depth ${row.id}`}
                  value={mineralCellVal(row, 'upperDepth', 'upperDepth')}
                  disabled={soilDisabled}
                  oninput={(e) => ctrl.children.stageSoilCell('Mineral', row.id, 'UpperDepth', e.currentTarget.value)}
                />
              </td>
              <td style="width: 54px;">
                <input
                  type="text"
                  inputmode="decimal"
                  class="classic-input classic-mono classic-num"
                  aria-label={`Mineral lower depth ${row.id}`}
                  value={mineralCellVal(row, 'lowerDepth', 'lowerDepth')}
                  disabled={soilDisabled}
                  oninput={(e) => ctrl.children.stageSoilCell('Mineral', row.id, 'LowerDepth', e.currentTarget.value)}
                />
              </td>
              <td style="width: 54px;">
                <input
                  type="text"
                  class="classic-input classic-mono"
                  aria-label={`Mineral texture ${row.id}`}
                  value={mineralCellVal(row, 'texture', 'texture')}
                  disabled={soilDisabled}
                  aria-invalid={mineralCellErr(row, 'texture') ? 'true' : undefined}
                  oninput={(e) => ctrl.children.stageSoilCell('Mineral', row.id, 'Texture', e.currentTarget.value)}
                />
              </td>
              <td style="width: 82px;">
                <input
                  type="text"
                  class="classic-input classic-mono"
                  aria-label={`Mineral colour ${row.id}`}
                  value={mineralCellVal(row, 'colour', 'colour')}
                  disabled={soilDisabled}
                  aria-invalid={mineralCellErr(row, 'colour') ? 'true' : undefined}
                  oninput={(e) => ctrl.children.stageSoilCell('Mineral', row.id, 'Colour', e.currentTarget.value)}
                />
              </td>
              <td style="width: 108px;">
                <div class="flex gap-0.5">
                  <input
                    type="text"
                    inputmode="decimal"
                    class="classic-input classic-mono classic-num"
                    aria-label={`Gravel percent ${row.id}`}
                    placeholder="G"
                    value={mineralCellVal(row, 'percentCoarseFragsGravel', 'percentCoarseFragsGravel')}
                    disabled={soilDisabled}
                    oninput={(e) =>
                      ctrl.children.stageSoilCell('Mineral', row.id, 'PercentCoarseFragsGravel', e.currentTarget.value)}
                  />
                  <input
                    type="text"
                    inputmode="decimal"
                    class="classic-input classic-mono classic-num"
                    aria-label={`Cobbles percent ${row.id}`}
                    placeholder="C"
                    value={mineralCellVal(row, 'percentCoarseFragsCobbles', 'percentCoarseFragsCobbles')}
                    disabled={soilDisabled}
                    oninput={(e) =>
                      ctrl.children.stageSoilCell('Mineral', row.id, 'PercentCoarseFragsCobbles', e.currentTarget.value)}
                  />
                  <input
                    type="text"
                    inputmode="decimal"
                    class="classic-input classic-mono classic-num"
                    aria-label={`Stones percent ${row.id}`}
                    placeholder="S"
                    value={mineralCellVal(row, 'percentCoarseFragsStones', 'percentCoarseFragsStones')}
                    disabled={soilDisabled}
                    oninput={(e) =>
                      ctrl.children.stageSoilCell('Mineral', row.id, 'PercentCoarseFragsStones', e.currentTarget.value)}
                  />
                </div>
              </td>
              <td style="width: 52px;">
                <input
                  type="text"
                  inputmode="decimal"
                  class="classic-input classic-mono classic-num"
                  aria-label={`Coarse fragments total ${row.id}`}
                  value={mineralCellVal(row, 'percentCoarseFragsTotal', 'percentCoarseFragsTotal')}
                  disabled={soilDisabled}
                  oninput={(e) =>
                    ctrl.children.stageSoilCell('Mineral', row.id, 'PercentCoarseFragsTotal', e.currentTarget.value)}
                />
              </td>
              <td style="width: 78px;">
                <div class="flex gap-0.5">
                  <input
                    type="text"
                    class="classic-input classic-mono"
                    aria-label={`Mineral roots abundance ${row.id}`}
                    placeholder="Ab"
                    value={mineralCellVal(row, 'rootsAbundance', 'rootsAbundance')}
                    disabled={soilDisabled}
                    oninput={(e) => ctrl.children.stageSoilCell('Mineral', row.id, 'RootsAbundance', e.currentTarget.value)}
                  />
                  <input
                    type="text"
                    class="classic-input classic-mono"
                    aria-label={`Mineral roots size ${row.id}`}
                    placeholder="Sz"
                    value={mineralCellVal(row, 'rootsSize', 'rootsSize')}
                    disabled={soilDisabled}
                    oninput={(e) => ctrl.children.stageSoilCell('Mineral', row.id, 'RootsSize', e.currentTarget.value)}
                  />
                </div>
              </td>
              <td style="width: 48px;">
                <input
                  type="text"
                  inputmode="decimal"
                  class="classic-input classic-mono classic-num"
                  aria-label={`Mineral pH ${row.id}`}
                  value={mineralCellVal(row, 'mineralFormpH', 'mineralFormpH')}
                  disabled={soilDisabled}
                  oninput={(e) => ctrl.children.stageSoilCell('Mineral', row.id, 'MineralFormpH', e.currentTarget.value)}
                />
              </td>
              <td style="min-width: 100px;">
                <input
                  type="text"
                  class="classic-input"
                  aria-label={`Mineral comments ${row.id}`}
                  value={mineralCellVal(row, 'comments', 'comments')}
                  disabled={soilDisabled}
                  oninput={(e) => ctrl.children.stageSoilCell('Mineral', row.id, 'Comments', e.currentTarget.value)}
                />
              </td>
              {#if !IS_WEB_READONLY}
                <td>
                  <button
                    type="button"
                    class="classic-mini-btn classic-mini-btn-danger"
                    title="Delete mineral horizon"
                    aria-label={`Delete mineral horizon ${row.id}`}
                    disabled={soilDisabled || ctrl.children.soilUnsaved}
                    onclick={() => void ctrl.children.deleteSourceChild('SoilMineralXL', row.id)}
                  >
                    <Trash2 size={11} aria-hidden="true" />
                  </button>
                </td>
              {/if}
            </tr>
          {:else}
            <tr>
              <td colspan={IS_WEB_READONLY ? 10 : 11} class="text-center italic py-2 text-vpro-ink-muted">
                No mineral horizons recorded.
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  </section>

  <!-- Section 5: Soil Notes -->
  <section class="classic-block">
    <div class="classic-block-header">
      <span>5. Soil Notes</span>
    </div>
    <div class="classic-grid">
      <div class="classic-cell" class:is-draft={isFieldDraft('soilNotes')} style="grid-column: span 12;" data-full-row>
        <label class="classic-label" for="classic-soilNotes">Soil Profile &amp; Pit Notes</label>
        <textarea
          id="classic-soilNotes"
          data-column="SoilNotes"
          rows={2}
          class="classic-textarea"
          value={ctrl.draft.soilNotes ?? ''}
          disabled={fieldDisabled('soilNotes')}
          oninput={(e) => setText('soilNotes', e.currentTarget.value, 0, 'Soil Notes')}
        ></textarea>
      </div>
    </div>
  </section>
</article>
