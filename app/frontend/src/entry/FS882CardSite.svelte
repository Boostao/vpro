<script lang="ts">
  import { Camera, Copy, FileSpreadsheet, Plus, Trash2 } from '@lucide/svelte';
  import type { FS882Header } from '../../bindings/github.com/boostao/vpro/app';
  import type { PictureMetadataSession } from '../pictures/pictureMetadataSession';
  import { webMeta } from '../shared/state';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import { computeSubstrateTotal } from './classicFS882Helpers';
  import type { FS882Controller } from './fs882FormController.svelte';

  type NullableTextKey = {
    [K in keyof FS882Header]: FS882Header[K] extends string | null ? K : never;
  }[keyof FS882Header];
  type NumberKey = {
    [K in keyof FS882Header]: FS882Header[K] extends number | null ? K : never;
  }[keyof FS882Header];

  let {
    ctrl,
    onOpenPictureManager,
    pictureDisabled = false,
    pictureMetadataDisabled = false,
    pictureMetadataSession,
  }: {
    ctrl: FS882Controller;
    onOpenPictureManager?: (plotNumber: string) => void;
    pictureDisabled?: boolean;
    pictureMetadataDisabled?: boolean;
    pictureMetadataSession?: PictureMetadataSession;
  } = $props();

  let picturesExpanded = $state(false);

  const STRUCTURAL_STAGE_OPTIONS = [
    ['1', '1 — Non-vegetated / Sparse'],
    ['1a', '1a — Sparse'],
    ['1b', '1b — Bryoid'],
    ['1c', '1c — Lichen'],
    ['2', '2 — Herb'],
    ['2a', '2a — Forb-dominated'],
    ['2b', '2b — Graminoid-dominated'],
    ['2c', '2c — Aquatic'],
    ['2d', '2d — Dwarf shrub'],
    ['3', '3 — Shrub / Stunted trees'],
    ['3a', '3a — Low shrub (< 2 m)'],
    ['3b', '3b — Tall shrub (2–10 m)'],
    ['3c', '3c — Short stunted trees'],
    ['3d', '3d — Tall stunted trees'],
    ['4', '4 — Pole / Sapling'],
    ['5', '5 — Young Forest'],
    ['6', '6 — Mature Forest'],
    ['7', '7 — Old Forest'],
    ['7a', '7a — Old Forest (even/multi)'],
    ['7b', '7b — Very Old Forest'],
  ] as const;

  const SUCCESSIONAL_STATUS_OPTIONS = [
    ['NV', 'NV — Non-vegetated'],
    ['PS', 'PS — Pioneer seral'],
    ['YS', 'YS — Young seral'],
    ['MS', 'MS — Maturing seral'],
    ['OS', 'OS — Overmature seral'],
    ['YC', 'YC — Young climax'],
    ['MC', 'MC — Maturing climax'],
    ['OC', 'OC — Old climax'],
    ['DC', 'DC — Disclimax'],
  ] as const;

  let rawNumbers = $state<Partial<Record<NumberKey, string>>>({});
  let lastRevisionKey = '';

  $effect(() => {
    const key = `${ctrl.original?.plotNumber ?? '__new__'}:${ctrl.headerRevision}`;
    if (key !== lastRevisionKey) {
      lastRevisionKey = key;
      rawNumbers = {};
    }
  });

  const existing = $derived(ctrl.original !== null);
  const disabled = $derived(ctrl.headerInputsDisabled);
  const substrateTotal = $derived(computeSubstrateTotal(ctrl.draft));
  const bgcMask = $derived.by(() => {
    const z = ctrl.draft.zone?.trim() ?? '';
    const sz = ctrl.draft.subZone?.trim() ?? '';
    const ss = ctrl.draft.siteSeries?.trim() ?? '';
    const prefix = [z, sz].filter(Boolean).join(' ');
    if (prefix && ss) return `${prefix} / ${ss}`;
    if (prefix) return prefix;
    return ctrl.draft.becSiteUnit?.trim() || ctrl.draft.userSiteUnit?.trim() || 'Unclassified';
  });

  function fieldDisabled(key: keyof FS882Header): boolean {
    if (disabled) return true;
    if (Object.keys(ctrl.capabilities).length > 0 && ctrl.capabilities[key] !== true) return true;
    return false;
  }

  function isFieldDraft(key: keyof FS882Header): boolean {
    if (!ctrl.original) return ctrl.draft[key] != null && ctrl.draft[key] !== '' && ctrl.draft[key] !== false;
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

  function setNumber(
    key: NumberKey,
    raw: string,
    label: string,
    opts: { integer?: boolean; min?: number; max?: number } = {}
  ) {
    rawNumbers = { ...rawNumbers, [key]: raw };
    const trimmed = raw.trim();
    if (trimmed === '') {
      ctrl.draft[key] = null;
      ctrl.validateHeader(key, null);
      ctrl.markDirty();
      return;
    }
    const parsed = Number(trimmed);
    if (!Number.isFinite(parsed) || (opts.integer && !Number.isInteger(parsed))) {
      ctrl.validateHeader(key, `${label} must be a valid ${opts.integer ? 'whole ' : ''}number.`);
      ctrl.markDirty();
      return;
    }
    if (opts.min !== undefined && parsed < opts.min) {
      ctrl.validateHeader(key, `${label} must be at least ${opts.min}.`);
      ctrl.markDirty();
      return;
    }
    if (opts.max !== undefined && parsed > opts.max) {
      ctrl.validateHeader(key, `${label} must be at most ${opts.max}.`);
      ctrl.markDirty();
      return;
    }
    ctrl.draft[key] = parsed === 0 ? 0 : parsed;
    ctrl.validateHeader(key, null);
    ctrl.markDirty();
  }

  function setPlotNumber(raw: string) {
    ctrl.draft.plotNumber = raw;
    if (!raw.trim()) {
      ctrl.validateHeader('plotNumber', 'Plot Number is required.');
    } else if (raw !== raw.trim()) {
      ctrl.validateHeader('plotNumber', 'Plot Number cannot start or end with spaces.');
    } else if (raw.length > 7) {
      ctrl.validateHeader('plotNumber', 'Plot Number must be 7 characters or fewer.');
    } else {
      ctrl.validateHeader('plotNumber', null);
    }
    ctrl.markDirty();
  }

  function copyBecToWorkingUnit() {
    if (fieldDisabled('userSiteUnit')) return;
    const bec = ctrl.draft.becSiteUnit?.trim();
    if (!bec) return;
    ctrl.draft.userSiteUnit = bec;
    ctrl.validateHeader('userSiteUnit', null);
    ctrl.markDirty();
  }
</script>

{#if ctrl.projectIdDatalist.length > 0}
  <datalist id="classic-projectId-options">
    {#each ctrl.projectIdDatalist as pid (pid)}
      <option value={pid}></option>
    {/each}
  </datalist>
{/if}

<article class="classic-card" data-classic-card="site" aria-label="FS882 Card 1 — Site and Environment">
  <header class="classic-card-masthead">
    <div>
      <div class="classic-card-kicker">B.C. Ministry of Forests · LMH25 Field Card</div>
      <div class="classic-card-title">CARD 1 — SITE &amp; ENVIRONMENT (FS882)</div>
    </div>
    <div class="classic-card-badges">
      <span class="classic-card-stamp" data-site-bgc-mask>{bgcMask}</span>
      {#if ctrl.dirty}
        <span class="classic-card-stamp classic-card-stamp-draft">UNSAVED</span>
      {/if}
      <span class="classic-card-stamp">PLOT: {ctrl.draft.plotNumber || '(New)'}</span>
    </div>
  </header>

  <!-- Section 1: Plot Identity & Survey -->
  <section class="classic-block">
    <div class="classic-block-header">
      <span>1. Plot Identity &amp; Survey</span>
      <div class="flex items-center gap-1">
        {#if !IS_WEB_READONLY && ctrl.canOpenProjectMetadata()}
          <button
            type="button"
            class="classic-mini-btn"
            data-classic-open-metadata
            onclick={() => ctrl.openProjectMetadata()}
          >
            <FileSpreadsheet size={11} aria-hidden="true" /> Project Metadata
          </button>
        {/if}
        {#if onOpenPictureManager && ctrl.draft.plotNumber.trim()}
          <button
            type="button"
            class="classic-mini-btn"
            data-classic-open-pictures
            onclick={() => onOpenPictureManager(ctrl.draft.plotNumber.trim())}
          >
            <Camera size={11} aria-hidden="true" /> Pictures
          </button>
        {/if}
      </div>
    </div>
    <div class="classic-grid">
      <div class="classic-cell" class:is-draft={isFieldDraft('plotNumber')} class:is-error={Boolean(ctrl.headerValidation.plotNumber)} style="grid-column: span 3;">
        <label class="classic-label" for="classic-plotNumber">Plot No.</label>
        <input
          id="classic-plotNumber"
          data-column="PlotNumber"
          type="text"
          class="classic-input classic-mono font-bold"
          value={ctrl.draft.plotNumber}
          readonly={existing}
          disabled={fieldDisabled('plotNumber')}
          aria-invalid={ctrl.headerValidation.plotNumber ? 'true' : undefined}
          oninput={(e) => setPlotNumber(e.currentTarget.value)}
        />
        {#if ctrl.headerValidation.plotNumber}<p class="classic-field-error" role="alert">{ctrl.headerValidation.plotNumber}</p>{/if}
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('projectId')} style="grid-column: span 3;">
        <label class="classic-label" for="classic-projectId">Project ID</label>
        <input
          id="classic-projectId"
          data-column="ProjectID"
          type="text"
          list={ctrl.projectIdDatalist.length > 0 ? 'classic-projectId-options' : undefined}
          class="classic-input classic-mono"
          value={ctrl.draft.projectId ?? ''}
          disabled={fieldDisabled('projectId')}
          oninput={(e) => setText('projectId', e.currentTarget.value, 50, 'Project ID')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('fieldNo')} style="grid-column: span 2;">
        <label class="classic-label" for="classic-fieldNo">Field No.</label>
        <input
          id="classic-fieldNo"
          data-column="FieldNumber"
          type="text"
          class="classic-input classic-mono"
          value={ctrl.draft.fieldNo ?? ''}
          disabled={fieldDisabled('fieldNo')}
          oninput={(e) => setText('fieldNo', e.currentTarget.value, 20, 'Field Number')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('date')} style="grid-column: span 2;">
        <label class="classic-label" for="classic-date">Date</label>
        <input
          id="classic-date"
          data-column="Date"
          type="text"
          placeholder="YYYY-MM-DD"
          class="classic-input classic-mono"
          value={ctrl.draft.date ?? ''}
          disabled={fieldDisabled('date')}
          oninput={(e) => setText('date', e.currentTarget.value, 25, 'Date')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('surveyor')} style="grid-column: span 2;">
        <label class="classic-label" for="classic-surveyor">Site Surveyor</label>
        <input
          id="classic-surveyor"
          data-column="SiteSurveyor"
          type="text"
          class="classic-input"
          value={ctrl.draft.surveyor ?? ''}
          disabled={fieldDisabled('surveyor')}
          oninput={(e) => setText('surveyor', e.currentTarget.value, 30, 'Site Surveyor')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('enteredBy')} style="grid-column: span 4;">
        <label class="classic-label" for="classic-enteredBy">Entered By</label>
        <input
          id="classic-enteredBy"
          data-column="EnteredBy"
          type="text"
          class="classic-input"
          value={ctrl.draft.enteredBy ?? ''}
          disabled={fieldDisabled('enteredBy')}
          oninput={(e) => setText('enteredBy', e.currentTarget.value, 30, 'Entered By')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('photo')} style="grid-column: span 4;">
        <label class="classic-label" for="classic-photo">Photo Roll / Frame</label>
        <input
          id="classic-photo"
          data-column="Photo"
          type="text"
          class="classic-input classic-mono"
          value={ctrl.draft.photo ?? ''}
          disabled={fieldDisabled('photo')}
          oninput={(e) => setText('photo', e.currentTarget.value, 50, 'Photo')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('updatedFromCards')} style="grid-column: span 4;">
        <span class="classic-label">Admin Check</span>
        <label class="classic-check-label mt-0.5">
          <input
            type="checkbox"
            data-column="UpdatedFromCards"
            checked={Boolean(ctrl.draft.updatedFromCards)}
            disabled={fieldDisabled('updatedFromCards')}
            onchange={(e) => {
              ctrl.draft.updatedFromCards = e.currentTarget.checked;
              ctrl.markDirty();
            }}
          />
          Updated from field cards
        </label>
      </div>
    </div>
  </section>

  <!-- Section 2: Location & Coordinates -->
  <section class="classic-block">
    <div class="classic-block-header">
      <span>2. Location &amp; Coordinates (WGS84 / NAD83 UTM)</span>
    </div>
    <div class="classic-grid">
      <div class="classic-cell" class:is-draft={isFieldDraft('generalLocation')} style="grid-column: span 6;" data-full-row>
        <label class="classic-label" for="classic-generalLocation">Location Description</label>
        <input
          id="classic-generalLocation"
          data-column="Location"
          type="text"
          class="classic-input"
          value={ctrl.draft.generalLocation ?? ''}
          disabled={fieldDisabled('generalLocation')}
          oninput={(e) => setText('generalLocation', e.currentTarget.value, 255, 'Location')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('fsRegionDistrict')} style="grid-column: span 2;">
        <label class="classic-label" for="classic-fsRegionDistrict">Region / Dist.</label>
        <input
          id="classic-fsRegionDistrict"
          data-column="FSRegionDistrict"
          type="text"
          class="classic-input classic-mono"
          value={ctrl.draft.fsRegionDistrict ?? ''}
          disabled={fieldDisabled('fsRegionDistrict')}
          oninput={(e) => setText('fsRegionDistrict', e.currentTarget.value, 7, 'FSRegionDistrict')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('ecosection')} style="grid-column: span 2;">
        <label class="classic-label" for="classic-ecosection">Ecosection</label>
        <input
          id="classic-ecosection"
          data-column="Ecosection"
          type="text"
          class="classic-input classic-mono"
          value={ctrl.draft.ecosection ?? ''}
          disabled={fieldDisabled('ecosection')}
          oninput={(e) => setText('ecosection', e.currentTarget.value, 10, 'Ecosection')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('mapSheet')} style="grid-column: span 2;">
        <label class="classic-label" for="classic-mapSheet">NTS Map Sheet</label>
        <input
          id="classic-mapSheet"
          data-column="NtsMapSheet"
          type="text"
          class="classic-input classic-mono"
          value={ctrl.draft.mapSheet ?? ''}
          disabled={fieldDisabled('mapSheet')}
          oninput={(e) => setText('mapSheet', e.currentTarget.value, 15, 'NTS Map Sheet')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('latitude')} class:is-error={Boolean(ctrl.headerValidation.latitude)} style="grid-column: span 3;">
        <label class="classic-label" for="classic-latitude">Latitude (DD)</label>
        <input
          id="classic-latitude"
          data-column="Latitude"
          type="text"
          inputmode="decimal"
          class="classic-input classic-mono classic-num"
          value={numDisplay('latitude')}
          disabled={fieldDisabled('latitude')}
          aria-invalid={ctrl.headerValidation.latitude ? 'true' : undefined}
          oninput={(e) => setNumber('latitude', e.currentTarget.value, 'Latitude', { min: -90, max: 90 })}
        />
        {#if ctrl.headerValidation.latitude}<p class="classic-field-error" role="alert">{ctrl.headerValidation.latitude}</p>{/if}
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('longitude')} class:is-error={Boolean(ctrl.headerValidation.longitude)} style="grid-column: span 3;">
        <label class="classic-label" for="classic-longitude">Longitude (DD)</label>
        <input
          id="classic-longitude"
          data-column="Longitude"
          type="text"
          inputmode="decimal"
          class="classic-input classic-mono classic-num"
          value={numDisplay('longitude')}
          disabled={fieldDisabled('longitude')}
          aria-invalid={ctrl.headerValidation.longitude ? 'true' : undefined}
          oninput={(e) => setNumber('longitude', e.currentTarget.value, 'Longitude', { min: -180, max: 180 })}
        />
        {#if ctrl.headerValidation.longitude}<p class="classic-field-error" role="alert">{ctrl.headerValidation.longitude}</p>{/if}
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('utmZone')} style="grid-column: span 2;">
        <label class="classic-label" for="classic-utmZone">UTM Zone</label>
        <input
          id="classic-utmZone"
          data-column="UTMZone"
          type="text"
          class="classic-input classic-mono"
          value={ctrl.draft.utmZone ?? ''}
          disabled={fieldDisabled('utmZone')}
          oninput={(e) => setText('utmZone', e.currentTarget.value, 4, 'UTM Zone')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('easting')} class:is-error={Boolean(ctrl.headerValidation.easting)} style="grid-column: span 2;">
        <label class="classic-label" for="classic-easting">UTM Easting</label>
        <input
          id="classic-easting"
          data-column="UTMEasting"
          type="text"
          inputmode="decimal"
          class="classic-input classic-mono classic-num"
          value={numDisplay('easting')}
          disabled={fieldDisabled('easting')}
          oninput={(e) => setNumber('easting', e.currentTarget.value, 'UTM Easting')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('northing')} class:is-error={Boolean(ctrl.headerValidation.northing)} style="grid-column: span 2;">
        <label class="classic-label" for="classic-northing">UTM Northing</label>
        <input
          id="classic-northing"
          data-column="UTMNorthing"
          type="text"
          inputmode="decimal"
          class="classic-input classic-mono classic-num"
          value={numDisplay('northing')}
          disabled={fieldDisabled('northing')}
          oninput={(e) => setNumber('northing', e.currentTarget.value, 'UTM Northing')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('accuracy')} style="grid-column: span 3;">
        <label class="classic-label" for="classic-accuracy">Location Accuracy (m)</label>
        <input
          id="classic-accuracy"
          data-column="LocationAccuracy"
          type="text"
          inputmode="decimal"
          class="classic-input classic-mono classic-num"
          value={numDisplay('accuracy')}
          disabled={fieldDisabled('accuracy')}
          oninput={(e) => setNumber('accuracy', e.currentTarget.value, 'Location Accuracy', { min: 0 })}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('airPhotoNum')} style="grid-column: span 3;">
        <label class="classic-label" for="classic-airPhotoNum">Air Photo No.</label>
        <input
          id="classic-airPhotoNum"
          data-column="AirPhotoNum"
          type="text"
          class="classic-input classic-mono"
          value={ctrl.draft.airPhotoNum ?? ''}
          disabled={fieldDisabled('airPhotoNum')}
          oninput={(e) => setText('airPhotoNum', e.currentTarget.value, 25, 'Air Photo No.')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('xCoord')} style="grid-column: span 3;">
        <label class="classic-label" for="classic-xCoord">X Coord</label>
        <input
          id="classic-xCoord"
          data-column="XCoord"
          type="text"
          inputmode="decimal"
          class="classic-input classic-mono classic-num"
          value={numDisplay('xCoord')}
          disabled={fieldDisabled('xCoord')}
          oninput={(e) => setNumber('xCoord', e.currentTarget.value, 'X Coord')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('yCoord')} style="grid-column: span 3;">
        <label class="classic-label" for="classic-yCoord">Y Coord</label>
        <input
          id="classic-yCoord"
          data-column="YCoord"
          type="text"
          inputmode="decimal"
          class="classic-input classic-mono classic-num"
          value={numDisplay('yCoord')}
          disabled={fieldDisabled('yCoord')}
          oninput={(e) => setNumber('yCoord', e.currentTarget.value, 'Y Coord')}
        />
      </div>
    </div>
  </section>

  <!-- Section 3: BEC & Edatopic Classification -->
  <section class="classic-block">
    <div class="classic-block-header">
      <span>3. BGC &amp; Edatopic Classification</span>
      <span class="classic-mono">{bgcMask}</span>
    </div>
    <div class="classic-grid">
      <div class="classic-cell" class:is-draft={isFieldDraft('zone')} style="grid-column: span 2;">
        <label class="classic-label" for="classic-zone">BGC Zone</label>
        <input
          id="classic-zone"
          data-column="Zone"
          type="text"
          class="classic-input classic-mono"
          value={ctrl.draft.zone ?? ''}
          disabled={fieldDisabled('zone')}
          oninput={(e) => setText('zone', e.currentTarget.value, 10, 'BGC Zone')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('subZone')} style="grid-column: span 2;">
        <label class="classic-label" for="classic-subZone">Subzone / Var.</label>
        <input
          id="classic-subZone"
          data-column="SubZone"
          type="text"
          class="classic-input classic-mono"
          value={ctrl.draft.subZone ?? ''}
          disabled={fieldDisabled('subZone')}
          oninput={(e) => setText('subZone', e.currentTarget.value, 15, 'Subzone')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('siteSeries')} style="grid-column: span 2;">
        <label class="classic-label" for="classic-siteSeries">Site Series</label>
        <input
          id="classic-siteSeries"
          data-column="SiteSeries"
          type="text"
          class="classic-input classic-mono"
          value={ctrl.draft.siteSeries ?? ''}
          disabled={fieldDisabled('siteSeries')}
          oninput={(e) => setText('siteSeries', e.currentTarget.value, 15, 'Site Series')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('transition')} style="grid-column: span 2;">
        <label class="classic-label" for="classic-transition">Transitional</label>
        <input
          id="classic-transition"
          data-column="TransDistrib"
          type="text"
          class="classic-input classic-mono"
          value={ctrl.draft.transition ?? ''}
          disabled={fieldDisabled('transition')}
          oninput={(e) => setText('transition', e.currentTarget.value, 10, 'Transitional')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('moistureRegime')} style="grid-column: span 2;" data-help-id="site.moisture_regime">
        <label class="classic-label" for="classic-moistureRegime">Moisture (rSMR)</label>
        {#if ctrl.children.lists.moistureRegime.length > 0}
          <select
            id="classic-moistureRegime"
            data-column="MoistureRegime"
            class="classic-select classic-mono"
            value={ctrl.draft.moistureRegime ?? ''}
            disabled={fieldDisabled('moistureRegime')}
            onchange={(e) => setText('moistureRegime', e.currentTarget.value, 5, 'Moisture Regime')}
          >
            <option value=""></option>
            {#each ctrl.children.lists.moistureRegime as opt (opt.item)}
              <option value={opt.item}>{opt.item}{opt.itemDescription ? ` — ${opt.itemDescription}` : ''}</option>
            {/each}
          </select>
        {:else}
          <input
            id="classic-moistureRegime"
            data-column="MoistureRegime"
            type="text"
            class="classic-input classic-mono"
            value={ctrl.draft.moistureRegime ?? ''}
            disabled={fieldDisabled('moistureRegime')}
            oninput={(e) => setText('moistureRegime', e.currentTarget.value, 5, 'Moisture Regime')}
          />
        {/if}
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('nutrientRegime')} style="grid-column: span 2;">
        <label class="classic-label" for="classic-nutrientRegime">Nutrient (rSNR)</label>
        {#if ctrl.children.lists.nutrientRegime.length > 0}
          <select
            id="classic-nutrientRegime"
            data-column="NutrientRegime"
            class="classic-select classic-mono"
            value={ctrl.draft.nutrientRegime ?? ''}
            disabled={fieldDisabled('nutrientRegime')}
            onchange={(e) => setText('nutrientRegime', e.currentTarget.value, 5, 'Nutrient Regime')}
          >
            <option value=""></option>
            {#each ctrl.children.lists.nutrientRegime as opt (opt.item)}
              <option value={opt.item}>{opt.item}{opt.itemDescription ? ` — ${opt.itemDescription}` : ''}</option>
            {/each}
          </select>
        {:else}
          <input
            id="classic-nutrientRegime"
            data-column="NutrientRegime"
            type="text"
            class="classic-input classic-mono"
            value={ctrl.draft.nutrientRegime ?? ''}
            disabled={fieldDisabled('nutrientRegime')}
            oninput={(e) => setText('nutrientRegime', e.currentTarget.value, 5, 'Nutrient Regime')}
          />
        {/if}
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('becSiteUnit')} style="grid-column: span 4;">
        <label class="classic-label" for="classic-becSiteUnit">BEC Master Site Unit</label>
        <input
          id="classic-becSiteUnit"
          data-column="BECSiteUnit"
          type="text"
          class="classic-input classic-mono"
          value={ctrl.draft.becSiteUnit ?? ''}
          disabled={fieldDisabled('becSiteUnit') || !ctrl.masterAllowed}
          oninput={(e) => setText('becSiteUnit', e.currentTarget.value, 100, 'BEC Master Site Unit')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('userSiteUnit')} style="grid-column: span 4;">
        <label class="classic-label" for="classic-userSiteUnit">
          <span>Working Site Unit</span>
          {#if !fieldDisabled('userSiteUnit') && ctrl.draft.becSiteUnit}
            <button
              type="button"
              class="classic-mini-btn"
              title="Copy BEC Master Site Unit to Working Site Unit"
              onclick={copyBecToWorkingUnit}
            >
              <Copy size={10} aria-hidden="true" /> From Master
            </button>
          {/if}
        </label>
        <input
          id="classic-userSiteUnit"
          data-column="UserSiteUnit"
          type="text"
          class="classic-input classic-mono"
          value={ctrl.draft.userSiteUnit ?? ''}
          disabled={fieldDisabled('userSiteUnit')}
          oninput={(e) => setText('userSiteUnit', e.currentTarget.value, 100, 'Working Site Unit')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('realmClass')} style="grid-column: span 2;">
        <label class="classic-label" for="classic-realmClass">Realm / Class</label>
        <input
          id="classic-realmClass"
          data-column="RealmClass"
          type="text"
          class="classic-input classic-mono"
          value={ctrl.draft.realmClass ?? ''}
          disabled={fieldDisabled('realmClass')}
          oninput={(e) => setText('realmClass', e.currentTarget.value, 15, 'Realm / Class')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('mapUnit')} style="grid-column: span 2;">
        <label class="classic-label" for="classic-mapUnit">Map Unit</label>
        <input
          id="classic-mapUnit"
          data-column="MapUnit"
          type="text"
          class="classic-input classic-mono"
          value={ctrl.draft.mapUnit ?? ''}
          disabled={fieldDisabled('mapUnit')}
          oninput={(e) => setText('mapUnit', e.currentTarget.value, 50, 'Map Unit')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('plotRepresenting')} style="grid-column: span 12;" data-full-row>
        <label class="classic-label" for="classic-plotRepresenting">Plot Representing</label>
        <input
          id="classic-plotRepresenting"
          data-column="PlotRepresenting"
          type="text"
          class="classic-input"
          value={ctrl.draft.plotRepresenting ?? ''}
          disabled={fieldDisabled('plotRepresenting')}
          oninput={(e) => setText('plotRepresenting', e.currentTarget.value, 255, 'Plot Representing')}
        />
      </div>
    </div>
  </section>

  <!-- Section 4: Topography, Stand, Disturbance & Quality -->
  <section class="classic-block">
    <div class="classic-block-header">
      <span>4. Topography, Stand Structure, Disturbance &amp; Plot Quality</span>
    </div>
    <div class="classic-grid">
      <div class="classic-cell" class:is-draft={isFieldDraft('elevation')} class:is-error={Boolean(ctrl.headerValidation.elevation)} style="grid-column: span 2;">
        <label class="classic-label" for="classic-elevation">Elevation (m)</label>
        <input
          id="classic-elevation"
          data-column="Elevation"
          type="text"
          inputmode="decimal"
          class="classic-input classic-mono classic-num"
          value={numDisplay('elevation')}
          disabled={fieldDisabled('elevation')}
          oninput={(e) => setNumber('elevation', e.currentTarget.value, 'Elevation')}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('slope')} class:is-error={Boolean(ctrl.headerValidation.slope)} style="grid-column: span 2;">
        <label class="classic-label" for="classic-slope">Slope (%)</label>
        <input
          id="classic-slope"
          data-column="SlopeGradient"
          type="text"
          inputmode="decimal"
          class="classic-input classic-mono classic-num"
          value={numDisplay('slope')}
          disabled={fieldDisabled('slope')}
          oninput={(e) => setNumber('slope', e.currentTarget.value, 'Slope', { min: 0 })}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('aspect')} class:is-error={Boolean(ctrl.headerValidation.aspect)} style="grid-column: span 2;">
        <label class="classic-label" for="classic-aspect">Aspect (deg)</label>
        <input
          id="classic-aspect"
          data-column="Aspect"
          type="text"
          inputmode="decimal"
          class="classic-input classic-mono classic-num"
          value={numDisplay('aspect')}
          disabled={fieldDisabled('aspect')}
          oninput={(e) => setNumber('aspect', e.currentTarget.value, 'Aspect', { min: 0, max: 999 })}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('mesoSlopePos')} style="grid-column: span 3;">
        <label class="classic-label" for="classic-mesoSlopePos">Meso Slope Position</label>
        {#if ctrl.children.lists.mesoSlopePos.length > 0}
          <select
            id="classic-mesoSlopePos"
            data-column="MesoSlopePosition"
            class="classic-select classic-mono"
            value={ctrl.draft.mesoSlopePos ?? ''}
            disabled={fieldDisabled('mesoSlopePos')}
            onchange={(e) => setText('mesoSlopePos', e.currentTarget.value, 10, 'Meso Slope Position')}
          >
            <option value=""></option>
            {#each ctrl.children.lists.mesoSlopePos as opt (opt.item)}
              <option value={opt.item}>{opt.item}{opt.itemDescription ? ` — ${opt.itemDescription}` : ''}</option>
            {/each}
          </select>
        {:else}
          <input
            id="classic-mesoSlopePos"
            data-column="MesoSlopePosition"
            type="text"
            class="classic-input classic-mono"
            value={ctrl.draft.mesoSlopePos ?? ''}
            disabled={fieldDisabled('mesoSlopePos')}
            oninput={(e) => setText('mesoSlopePos', e.currentTarget.value, 10, 'Meso Slope Position')}
          />
        {/if}
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('surfaceShape')} style="grid-column: span 3;">
        <label class="classic-label" for="classic-surfaceShape">Surface Shape</label>
        {#if ctrl.children.lists.surfaceShape.length > 0}
          <select
            id="classic-surfaceShape"
            data-column="SurfaceShape"
            class="classic-select classic-mono"
            value={ctrl.draft.surfaceShape ?? ''}
            disabled={fieldDisabled('surfaceShape')}
            onchange={(e) => setText('surfaceShape', e.currentTarget.value, 10, 'Surface Shape')}
          >
            <option value=""></option>
            {#each ctrl.children.lists.surfaceShape as opt (opt.item)}
              <option value={opt.item}>{opt.item}{opt.itemDescription ? ` — ${opt.itemDescription}` : ''}</option>
            {/each}
          </select>
        {:else}
          <input
            id="classic-surfaceShape"
            data-column="SurfaceShape"
            type="text"
            class="classic-input classic-mono"
            value={ctrl.draft.surfaceShape ?? ''}
            disabled={fieldDisabled('surfaceShape')}
            oninput={(e) => setText('surfaceShape', e.currentTarget.value, 10, 'Surface Shape')}
          />
        {/if}
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('structuralStage')} style="grid-column: span 4;">
        <label class="classic-label" for="classic-structuralStage">Structural Stage</label>
        <select
          id="classic-structuralStage"
          data-column="StructuralStage"
          class="classic-select"
          value={ctrl.draft.structuralStage ?? ''}
          disabled={fieldDisabled('structuralStage')}
          onchange={(e) => setText('structuralStage', e.currentTarget.value, 5, 'Structural Stage')}
        >
          <option value=""></option>
          {#each STRUCTURAL_STAGE_OPTIONS as [code, desc] (code)}
            <option value={code}>{desc}</option>
          {/each}
        </select>
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('successional')} style="grid-column: span 4;">
        <label class="classic-label" for="classic-successional">Successional Status</label>
        <select
          id="classic-successional"
          data-column="SuccessionalStatus"
          class="classic-select"
          value={ctrl.draft.successional ?? ''}
          disabled={fieldDisabled('successional')}
          onchange={(e) => setText('successional', e.currentTarget.value, 5, 'Successional Status')}
        >
          <option value=""></option>
          {#each SUCCESSIONAL_STATUS_OPTIONS as [code, desc] (code)}
            <option value={code}>{desc}</option>
          {/each}
        </select>
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('standAge')} style="grid-column: span 2;">
        <label class="classic-label" for="classic-standAge">Stand Age (yr)</label>
        <input
          id="classic-standAge"
          data-column="StandAge"
          type="text"
          inputmode="numeric"
          class="classic-input classic-mono classic-num"
          value={numDisplay('standAge')}
          disabled={fieldDisabled('standAge')}
          oninput={(e) => setNumber('standAge', e.currentTarget.value, 'Stand Age', { integer: true, min: 0 })}
        />
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('microtopType')} style="grid-column: span 2;">
        <label class="classic-label" for="classic-microtopType">Microtop. Type/Size</label>
        <div class="flex gap-1">
          <input
            id="classic-microtopType"
            data-column="SurfaceTopographyType"
            type="text"
            placeholder="Type"
            class="classic-input classic-mono"
            value={ctrl.draft.microtopType ?? ''}
            disabled={fieldDisabled('microtopType')}
            oninput={(e) => setText('microtopType', e.currentTarget.value, 5, 'Microtopography Type')}
          />
          <input
            id="classic-microtopSize"
            data-column="SurfaceTopographySize"
            aria-label="Microtopography size"
            type="text"
            placeholder="Size"
            class="classic-input classic-mono"
            value={ctrl.draft.microtopSize ?? ''}
            disabled={fieldDisabled('microtopSize')}
            oninput={(e) => setText('microtopSize', e.currentTarget.value, 5, 'Microtopography Size')}
          />
        </div>
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('exposure1') || isFieldDraft('exposure2')} style="grid-column: span 3;">
        <label class="classic-label" for="classic-exposure1">Exposure (1 / 2)</label>
        <div class="flex gap-1">
          <input
            id="classic-exposure1"
            data-column="Exposure1"
            type="text"
            class="classic-input classic-mono"
            value={ctrl.draft.exposure1 ?? ''}
            disabled={fieldDisabled('exposure1')}
            oninput={(e) => setText('exposure1', e.currentTarget.value, 5, 'Exposure 1')}
          />
          <input
            id="classic-exposure2"
            data-column="Exposure2"
            aria-label="Exposure 2"
            type="text"
            class="classic-input classic-mono"
            value={ctrl.draft.exposure2 ?? ''}
            disabled={fieldDisabled('exposure2')}
            oninput={(e) => setText('exposure2', e.currentTarget.value, 5, 'Exposure 2')}
          />
        </div>
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('siteDisturbance1') || isFieldDraft('siteDisturbance2') || isFieldDraft('siteDisturbance3')} style="grid-column: span 4;">
        <label class="classic-label" for="classic-siteDisturbance1">Site Disturbance (1 / 2 / 3)</label>
        <div class="flex gap-1">
          <input
            id="classic-siteDisturbance1"
            data-column="SiteDisturbance1"
            type="text"
            class="classic-input classic-mono"
            value={ctrl.draft.siteDisturbance1 ?? ''}
            disabled={fieldDisabled('siteDisturbance1')}
            oninput={(e) => setText('siteDisturbance1', e.currentTarget.value, 10, 'Site Disturbance 1')}
          />
          <input
            id="classic-siteDisturbance2"
            data-column="SiteDisturbance2"
            aria-label="Site Disturbance 2"
            type="text"
            class="classic-input classic-mono"
            value={ctrl.draft.siteDisturbance2 ?? ''}
            disabled={fieldDisabled('siteDisturbance2')}
            oninput={(e) => setText('siteDisturbance2', e.currentTarget.value, 10, 'Site Disturbance 2')}
          />
          <input
            id="classic-siteDisturbance3"
            data-column="SiteDisturbance3"
            aria-label="Site Disturbance 3"
            type="text"
            class="classic-input classic-mono"
            value={ctrl.draft.siteDisturbance3 ?? ''}
            disabled={fieldDisabled('siteDisturbance3')}
            oninput={(e) => setText('siteDisturbance3', e.currentTarget.value, 10, 'Site Disturbance 3')}
          />
        </div>
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('sitePlotQuality') || isFieldDraft('vegPlotQuality') || isFieldDraft('soilPlotQuality')} style="grid-column: span 5;">
        <label class="classic-label" for="classic-sitePlotQuality">Plot Quality (Site / Veg / Soil)</label>
        <div class="flex gap-1">
          <input
            id="classic-sitePlotQuality"
            data-column="SitePlotQuality"
            type="text"
            placeholder="Site"
            class="classic-input classic-mono"
            value={ctrl.draft.sitePlotQuality ?? ''}
            disabled={fieldDisabled('sitePlotQuality')}
            oninput={(e) => setText('sitePlotQuality', e.currentTarget.value, 15, 'Site Plot Quality')}
          />
          <input
            id="classic-vegPlotQuality"
            data-column="VegPlotQuality"
            aria-label="Veg Plot Quality"
            type="text"
            placeholder="Veg"
            class="classic-input classic-mono"
            value={ctrl.draft.vegPlotQuality ?? ''}
            disabled={fieldDisabled('vegPlotQuality')}
            oninput={(e) => setText('vegPlotQuality', e.currentTarget.value, 15, 'Veg Plot Quality')}
          />
          <input
            id="classic-soilPlotQuality"
            data-column="SoilPlotQuality"
            aria-label="Soil Plot Quality"
            type="text"
            placeholder="Soil"
            class="classic-input classic-mono"
            value={ctrl.draft.soilPlotQuality ?? ''}
            disabled={fieldDisabled('soilPlotQuality')}
            oninput={(e) => setText('soilPlotQuality', e.currentTarget.value, 15, 'Soil Plot Quality')}
          />
        </div>
      </div>

      {#if ctrl.extendedShrubs}
        <div class="classic-cell" class:is-error={Boolean(ctrl.headerValidation.snowCoverRegime)} style="grid-column: span 6;" data-extended-arctic-fields>
          <label class="classic-label" for="header-snowCoverregime">Snow Cover Regime (Extended)</label>
          <input
            id="header-snowCoverregime"
            data-column="SnowCoverregime"
            type="text"
            class="classic-input classic-mono"
            value={ctrl.snowCoverRegimeInput}
            disabled={ctrl.arcticInputsDisabled || ctrl.capabilities.snowCoverRegime !== true}
            aria-invalid={ctrl.headerValidation.snowCoverRegime ? 'true' : undefined}
            oninput={(e) => ctrl.stageSnowCoverRegime(e.currentTarget.value)}
          />
          {#if ctrl.headerValidation.snowCoverRegime}<p class="classic-field-error" role="alert">{ctrl.headerValidation.snowCoverRegime}</p>{/if}
        </div>
        <div class="classic-cell" class:is-error={Boolean(ctrl.headerValidation.activeLayerDepth)} style="grid-column: span 6;">
          <label class="classic-label" for="header-activeLayerDepth">Active Layer Depth (cm)</label>
          <input
            id="header-activeLayerDepth"
            data-column="ActiveLayerDepth"
            type="text"
            inputmode="decimal"
            class="classic-input classic-mono classic-num"
            value={ctrl.activeLayerDepthInput}
            disabled={ctrl.arcticInputsDisabled || ctrl.capabilities.activeLayerDepth !== true}
            aria-invalid={ctrl.headerValidation.activeLayerDepth ? 'true' : undefined}
            oninput={(e) => ctrl.stageActiveLayerDepth(e.currentTarget.value)}
          />
          {#if ctrl.headerValidation.activeLayerDepth}<p class="classic-field-error" role="alert">{ctrl.headerValidation.activeLayerDepth}</p>{/if}
        </div>
      {/if}
    </div>
  </section>

  <!-- Section 5: Substrate Cover (%) -->
  <section class="classic-block" data-classic-substrate-strip>
    <div class="classic-block-header">
      <span>5. Substrate Cover (%)</span>
      <span class="classic-mono">TOTAL: {substrateTotal !== null ? `${substrateTotal}%` : '—'} / 100%</span>
    </div>
    <div class="classic-grid">
      {#each [
        ['substrateOrganicMatter', 'SubstrateOrganicMatter', 'Organic Matter'],
        ['substrateDecWood', 'SubstrateDecWood', 'Decaying Wood'],
        ['substrateBedRock', 'SubstrateBedRock', 'Bedrock'],
        ['substrateRocks', 'SubstrateRocks', 'Rocks'],
        ['substrateMineralSoil', 'SubstrateMineralSoil', 'Mineral Soil'],
        ['substrateWater', 'SubstrateWater', 'Water'],
      ] as const as [key, col, label] (key)}
        <div class="classic-cell" class:is-draft={isFieldDraft(key)} class:is-error={Boolean(ctrl.headerValidation[key])} style="grid-column: span 2;">
          <label class="classic-label" for={`classic-${key}`}>{label}</label>
          <input
            id={`classic-${key}`}
            data-column={col}
            type="text"
            inputmode="decimal"
            class="classic-input classic-mono classic-num"
            value={numDisplay(key)}
            disabled={fieldDisabled(key)}
            oninput={(e) => setNumber(key, e.currentTarget.value, label, { min: 0, max: 100 })}
          />
        </div>
      {/each}
    </div>
  </section>

  <!-- Section 6: Site & Office Notes + Other Records -->
  <section class="classic-block">
    <div class="classic-block-header">
      <span>6. Site Notes, Office Notes &amp; Other Data ({ctrl.children.otherList.length})</span>
      {#if !IS_WEB_READONLY}
        <button
          type="button"
          class="classic-mini-btn"
          data-classic-add-other
          disabled={ctrl.children.otherEditingDisabled || ctrl.children.otherUnsaved}
          onclick={() => ctrl.children.openNewChild('other')}
        >
          <Plus size={11} aria-hidden="true" /> Add Other Item
        </button>
      {/if}
    </div>
    <div class="classic-grid">
      <div class="classic-cell" class:is-draft={isFieldDraft('fieldNotes')} style="grid-column: span 6;" data-full-row>
        <label class="classic-label" for="classic-fieldNotes">Site / Field Notes</label>
        <textarea
          id="classic-fieldNotes"
          data-column="SiteNotes"
          rows={2}
          class="classic-textarea"
          value={ctrl.draft.fieldNotes ?? ''}
          disabled={fieldDisabled('fieldNotes')}
          oninput={(e) => setText('fieldNotes', e.currentTarget.value, 0, 'Site Notes')}
        ></textarea>
      </div>
      <div class="classic-cell" class:is-draft={isFieldDraft('officeNotes')} style="grid-column: span 6;" data-full-row>
        <label class="classic-label" for="classic-officeNotes">Office Notes</label>
        <textarea
          id="classic-officeNotes"
          data-column="OfficeNotes"
          rows={2}
          class="classic-textarea"
          value={ctrl.draft.officeNotes ?? ''}
          disabled={fieldDisabled('officeNotes')}
          oninput={(e) => setText('officeNotes', e.currentTarget.value, 0, 'Office Notes')}
        ></textarea>
      </div>
    </div>
    {#if ctrl.children.otherList.length > 0}
      <div class="classic-table-wrap">
        <table class="classic-table">
          <thead>
            <tr>
              <th>Data Name</th>
              <th>Data Item</th>
              <th>User 1</th>
              <th>User 2</th>
              <th>User 3</th>
              {#if !IS_WEB_READONLY}<th style="width: 34px;">Del</th>{/if}
            </tr>
          </thead>
          <tbody>
            {#each ctrl.children.otherList as row (row.id)}
              {@const oDraft = ctrl.children.otherDrafts[String(row.id)]}
              <tr class:is-draft={Boolean(oDraft)}>
                <td>
                  <input
                    type="text"
                    class="classic-input"
                    aria-label={`Other data name row ${row.id}`}
                    value={String(oDraft?.dataName?.raw ?? row.dataName ?? '')}
                    disabled={IS_WEB_READONLY || ctrl.children.otherEditingDisabled}
                    oninput={(e) => ctrl.children.stageOtherCell(row.id, 'DataName', e.currentTarget.value)}
                  />
                </td>
                <td>
                  <input
                    type="text"
                    class="classic-input"
                    aria-label={`Other data item row ${row.id}`}
                    value={String(oDraft?.dataItem?.raw ?? row.dataItem ?? '')}
                    disabled={IS_WEB_READONLY || ctrl.children.otherEditingDisabled}
                    oninput={(e) => ctrl.children.stageOtherCell(row.id, 'DataItem', e.currentTarget.value)}
                  />
                </td>
                <td>
                  <input
                    type="text"
                    class="classic-input"
                    aria-label={`Other user item 1 row ${row.id}`}
                    value={String(oDraft?.userItem1?.raw ?? row.userItem1 ?? '')}
                    disabled={IS_WEB_READONLY || ctrl.children.otherEditingDisabled}
                    oninput={(e) => ctrl.children.stageOtherCell(row.id, 'UserItem1', e.currentTarget.value)}
                  />
                </td>
                <td>
                  <input
                    type="text"
                    class="classic-input"
                    aria-label={`Other user item 2 row ${row.id}`}
                    value={String(oDraft?.userItem2?.raw ?? row.userItem2 ?? '')}
                    disabled={IS_WEB_READONLY || ctrl.children.otherEditingDisabled}
                    oninput={(e) => ctrl.children.stageOtherCell(row.id, 'UserItem2', e.currentTarget.value)}
                  />
                </td>
                <td>
                  <input
                    type="text"
                    class="classic-input"
                    aria-label={`Other user item 3 row ${row.id}`}
                    value={String(oDraft?.userItem3?.raw ?? row.userItem3 ?? '')}
                    disabled={IS_WEB_READONLY || ctrl.children.otherEditingDisabled}
                    oninput={(e) => ctrl.children.stageOtherCell(row.id, 'UserItem3', e.currentTarget.value)}
                  />
                </td>
                {#if !IS_WEB_READONLY}
                  <td>
                    <button
                      type="button"
                      class="classic-mini-btn classic-mini-btn-danger"
                      title="Delete other row"
                      aria-label="Delete other row"
                      disabled={ctrl.children.otherEditingDisabled || ctrl.children.otherUnsaved}
                      onclick={() => void ctrl.children.deleteSourceChild('SubOtherXL', row.id)}
                    >
                      <Trash2 size={11} aria-hidden="true" />
                    </button>
                  </td>
                {/if}
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
  </section>

  {#if !(IS_WEB_READONLY && $webMeta?.picturesAvailable === false) && ctrl.pState?.activeProject && ctrl.original}
    <details
      class="classic-block"
      open={picturesExpanded}
      ontoggle={(e) => {
        picturesExpanded = e.currentTarget.open;
      }}
    >
      <summary class="classic-block-header cursor-pointer">
        <span>7. Linked Plot Pictures</span>
        <span class="text-[10px] font-normal">Expand to review linked photos</span>
      </summary>
      {#if picturesExpanded}
        <div class="p-2">
          {#await import('../pictures/PicturePanel.svelte') then { default: PicturePanel }}
            <PicturePanel
              contextId={ctrl.siviContextId}
              project={ctrl.pState.activeProject}
              plotNumber={ctrl.original.plotNumber}
              disabled={pictureDisabled || ctrl.authEditLocked}
              metadataDisabled={pictureMetadataDisabled || ctrl.authEditLocked}
              onBusyChange={(pending) => {
                ctrl.pictureBusy = pending;
              }}
              metadataSession={pictureMetadataSession}
            />
          {/await}
        </div>
      {/if}
    </details>
  {/if}
</article>
