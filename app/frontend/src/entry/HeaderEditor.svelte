<script lang="ts">
  import { untrack, type Snippet } from 'svelte';
  import type { FS882Header, ListItem } from '../../bindings/github.com/boostao/vpro/app';
  import { paperPage, type PaperControl } from './paperLayout';
  import { controlColumnSpan, controlLabel, groupCardZone, isUnmigratedStubControl, presentationGroups, wideControl } from './formPresentation';
  import CoordinateFields from './CoordinateFields.svelte';
  import BECFields from './BECFields.svelte';
  import WorkingUnitFields from './WorkingUnitFields.svelte';
  import QualityFields from './QualityFields.svelte';
  import SubstrateFields from './SubstrateFields.svelte';
  import SiteCodeFields from './SiteCodeFields.svelte';
  import { siteCodeKey, type SiteCodes } from './siteCodeEditor';
  import RegionCodeFields from './RegionCodeFields.svelte';
  import { regionCodeKey, type RegionCodes } from './regionCodeEditor';
  import { substrateKey, substrateKeys, substrateLabels, type SubstrateValues } from './substrateEditor';
  import { qualityKey, type QualityCodes } from './qualityEditor';
  import { becKey, type BECCodes } from './becEditor';
  import { isWorkingUnitControl, type WorkingUnitCodes, type WorkingUnitSession } from './workingUnitEditor';
  import { isCoordinateControl, type CoordinateDisplayMode } from './coordinateEditor';
  import { nullableParentField } from './ordinaryEditor';

  type TextKey = { [K in keyof FS882Header]: FS882Header[K] extends string | null ? K : never }[keyof FS882Header];
  type NullableTextKey = Exclude<TextKey, 'plotNumber'>;
  type NumberKey = { [K in keyof FS882Header]: FS882Header[K] extends number | null ? K : never }[keyof FS882Header];
  type ValidationKey = NumberKey | 'plotNumber' | 'date' | 'utmZone' | 'standCodes' | 'substrateBounds' | 'bec' | 'workingUnit' | 'masterBEC' | 'quality' | 'substrate' | 'siteCodes' | 'regionCodes';
  type Field = { key: NullableTextKey; label: string; kind: 'text' | 'notes'; list?: boolean } |
    { key: NumberKey; label: string; kind: 'number'; step?: string };

  type HeaderSlot = { columns: readonly string[]; controls: readonly string[]; input: Snippet<[PaperControl, string]>; labelled: true };
  let { draft = $bindable(), original, capabilities, disabled, existing, lists, onchange, onerror, onvalidation, onCoordinateBusyChange, onWorkingUnitBusyChange, onQualityBusyChange, onSiteCodeBusyChange, onRegionCodeBusyChange, workingUnitSession, masterAllowed = false, extendedShrubs = false, snowCoverRegime = '', activeLayerDepth = '', snowCoverRegimeDisabled, activeLayerDepthDisabled, snowCoverRegimeError = null, activeLayerDepthError = null, onSnowCoverRegimeChange, onActiveLayerDepthChange, editor, additionalEditor, onMetadata, metadataDisabled = true, onOpenPictureManager, projectIds = [], pictureEditor, sourcePage, coordinateMode = $bindable<CoordinateDisplayMode>('dd'), children: layoutContent }: {
    draft: FS882Header;
    original: (BECCodes & WorkingUnitCodes & QualityCodes & SubstrateValues & SiteCodes & RegionCodes & Partial<FS882Header>) | null;
    capabilities: Record<string, boolean | undefined>;
    disabled: boolean;
    existing: boolean;
    lists: Partial<Record<NullableTextKey, ListItem[]>>;
    onchange: () => void;
    onerror: (message: string) => void;
    onvalidation: (key: ValidationKey, message: string | null) => void;
    masterAllowed?: boolean;
    extendedShrubs?: boolean;
    snowCoverRegime?: string;
    activeLayerDepth?: string;
    snowCoverRegimeDisabled?: boolean;
    activeLayerDepthDisabled?: boolean;
    snowCoverRegimeError?: string | null;
    activeLayerDepthError?: string | null;
    onSnowCoverRegimeChange?: (value: string) => void;
    onActiveLayerDepthChange?: (value: string) => void;
    onCoordinateBusyChange?: (busy: boolean) => void;
    onWorkingUnitBusyChange?: (busy: boolean) => void;
    onQualityBusyChange?: (busy: boolean) => void;
    onSiteCodeBusyChange?: (busy: boolean) => void;
    onRegionCodeBusyChange?: (busy: boolean) => void;
    workingUnitSession: WorkingUnitSession;
    editor?: { columns: readonly string[]; input: Snippet<[PaperControl, string]> };
    additionalEditor?: { columns: readonly string[]; input: Snippet<[PaperControl, string]> };
    onMetadata?: () => void;
    metadataDisabled?: boolean;
    onOpenPictureManager?: (plotNumber: string) => void;
    projectIds?: readonly string[];
    pictureEditor?: Snippet;
    sourcePage?: ReturnType<typeof paperPage>;
    coordinateMode?: CoordinateDisplayMode;
    children?: Snippet<[HeaderSlot, CoordinateDisplayMode]>;
  } = $props();

  const STRUCTURAL_STAGE_OPTIONS = [
    { code: '1', label: 'Non-vegetated / Sparse' },
    { code: '1a', label: 'Sparse' },
    { code: '1b', label: 'Bryoid' },
    { code: '1c', label: 'Lichen' },
    { code: '2', label: 'Herb' },
    { code: '2a', label: 'Forb-dominated' },
    { code: '2b', label: 'Graminoid-dominated' },
    { code: '2c', label: 'Aquatic' },
    { code: '2d', label: 'Dwarf shrub-dominated' },
    { code: '3', label: 'Shrub / Stunted trees' },
    { code: '3a', label: 'Low shrub (< 2 m)' },
    { code: '3b', label: 'Tall shrub (2–10 m)' },
    { code: '3c', label: 'Short stunted trees' },
    { code: '3d', label: 'Tall stunted trees' },
    { code: '4', label: 'Pole / Sapling' },
    { code: '5', label: 'Young Forest' },
    { code: '6', label: 'Mature Forest' },
    { code: '7', label: 'Old Forest' },
    { code: '7a', label: 'Old Forest (even/multi-aged)' },
    { code: '7b', label: 'Very Old Forest' },
  ] as const;

  const SUCCESSIONAL_STATUS_OPTIONS = [
    { code: 'NV', label: 'Non-vegetated' },
    { code: 'PS', label: 'Pioneer seral' },
    { code: 'YS', label: 'Young seral' },
    { code: 'MS', label: 'Maturing seral' },
    { code: 'OS', label: 'Overmature seral' },
    { code: 'YC', label: 'Young climax' },
    { code: 'MC', label: 'Maturing climax' },
    { code: 'OC', label: 'Old climax' },
    { code: 'DC', label: 'Disclimax' },
  ] as const;

  const structuralStageSet = new Set(STRUCTURAL_STAGE_OPTIONS.map(o => o.code.toLowerCase()));
  const successionalStatusSet = new Set(SUCCESSIONAL_STATUS_OPTIONS.map(o => o.code.toLowerCase()));

  function isValidSurveyDateText(raw: string): boolean {
    const m = /^(\d{4})-(\d{2})-(\d{2})(?: (\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?)?$/.exec(raw);
    if (!m) return false;
    const year = Number.parseInt(m[1], 10);
    const month = Number.parseInt(m[2], 10);
    const day = Number.parseInt(m[3], 10);
    if (year < 100 || year > 9999 || month < 1 || month > 12 || day < 1 || day > 31) return false;
    const dt = new Date(Date.UTC(year, month - 1, day));
    if (dt.getUTCFullYear() !== year || dt.getUTCMonth() !== month - 1 || dt.getUTCDate() !== day) return false;
    if (m[4] !== undefined) {
      const hh = Number.parseInt(m[4], 10);
      const mm = Number.parseInt(m[5], 10);
      const ss = Number.parseInt(m[6], 10);
      if (hh > 23 || mm > 59 || ss > 59) return false;
    }
    return true;
  }

  function baselineField<K extends keyof FS882Header>(key: K): { known: boolean; value: FS882Header[K] | null } {
    if (!existing || !original) return { known: true, value: null };
    if (!(key in original)) return { known: false, value: null };
    return { known: true, value: (original[key] ?? null) as FS882Header[K] | null };
  }

  function isChangedFromBaseline<K extends keyof FS882Header>(key: K, current: FS882Header[K] | undefined): boolean {
    const base = baselineField(key);
    if (!base.known) return false;
    return (current ?? null) !== base.value;
  }

  function domainNumberError(key: NumberKey, value: number | null | undefined): string | null {
    if (value == null || !isChangedFromBaseline(key, value)) return null;
    if (!Number.isFinite(value)) return `Enter a valid finite number for ${key}.`;
    switch (key) {
      case 'startDate':
        if (!Number.isInteger(value) || value < 1900 || value > 2500) {
          return 'Start year (Yr.) must be an integer between 1900 and 2500.';
        }
        return null;
      case 'elevation':
        if (!Number.isInteger(value) || value < 0 || value > 9000) {
          return 'Elevation must be an integer between 0 and 9000 m above sea level.';
        }
        return null;
      case 'slope':
        if (value < 0 || value > 3.4028234663852886e38) {
          return 'Slope gradient must be 0% or greater.';
        }
        return null;
      case 'aspect':
        if (!Number.isInteger(value) || (value !== 999 && (value < 0 || value > 360))) {
          return 'Aspect must be an integer from 0 to 360 degrees, or 999 for level ground.';
        }
        return null;
      case 'standAge':
        if (!Number.isInteger(value) || value < 0 || value > 32767) {
          return 'Stand age must be an integer from 0 to 32767 years.';
        }
        return null;
      case 'accuracy':
        if (!Number.isInteger(value) || value < 0 || value > 32767) {
          return 'Location accuracy must be an integer from 0 to 32767 m.';
        }
        return null;
      default:
        return null;
    }
  }

  let rawNumberErrors = $state<Partial<Record<NumberKey, string>>>({});
  let standCodesAcknowledged = $state(false);
  let lastDraftRef: object | null = null;
  $effect(() => {
    const currentRef = draft;
    if (currentRef !== lastDraftRef) {
      lastDraftRef = currentRef;
      untrack(() => {
        rawNumberErrors = {};
        standCodesAcknowledged = false;
      });
    }
  });

  const plotNumberError = $derived(
    !existing && typeof draft.plotNumber === 'string' && draft.plotNumber !== '' && draft.plotNumber !== draft.plotNumber.trim()
      ? 'Plot number cannot start or end with spaces.'
      : null
  );

  const dateError = $derived(
    draft.date != null && isChangedFromBaseline('date', draft.date) && !isValidSurveyDateText(draft.date)
      ? 'Survey date must be a valid calendar date in YYYY-MM-DD format (for example 2026-07-15).'
      : null
  );

  const utmZoneError = $derived(
    draft.utmZone != null && isChangedFromBaseline('utmZone', draft.utmZone) &&
      !/^0*([1-9]|[1-5][0-9]|60)[Nn]?$/.test(draft.utmZone.trim())
      ? 'UTM zone must be a Northern Hemisphere zone number (for example 9, 10, or 10N; Southern zones like 9S are invalid).'
      : null
  );

  const standCodeState = $derived.by(() => {
    const lengthErrors: Partial<Record<'structuralStage' | 'successional', string>> = {};
    const warnings: string[] = [];
    if (draft.structuralStage != null && isChangedFromBaseline('structuralStage', draft.structuralStage)) {
      if (draft.structuralStage.length > 6) {
        lengthErrors.structuralStage = 'Structural stage must be at most 6 characters (for example 1–7, 3b, 7a).';
      } else if (!structuralStageSet.has(draft.structuralStage.toLowerCase())) {
        warnings.push(`Structural stage "${draft.structuralStage}" is not a standard LMH25 code (1–7, 1a–3d, 7a–7b).`);
      }
    }
    if (draft.successional != null && isChangedFromBaseline('successional', draft.successional)) {
      if (draft.successional.length > 3) {
        lengthErrors.successional = 'Successional status must be at most 3 characters (for example PS, YS, MS, MC).';
      } else if (!successionalStatusSet.has(draft.successional.toLowerCase())) {
        warnings.push(`Successional status "${draft.successional}" is not a standard LMH25 code (NV, PS, YS, MS, OS, YC, MC, OC, DC).`);
      }
    }
    const firstLengthErr = lengthErrors.structuralStage ?? lengthErrors.successional ?? null;
    const validation = firstLengthErr ?? (warnings.length > 0 && !standCodesAcknowledged
      ? `${warnings[0]} Choose a listed LMH25 code or confirm keeping unlisted stand codes.`
      : null);
    return { lengthErrors, warnings, validation };
  });

  const substrateBoundsError = $derived.by(() => {
    for (const key of substrateKeys) {
      const val = draft[key];
      if (typeof val === 'number' && Number.isFinite(val) && isChangedFromBaseline(key, val) && (val < 0 || val > 100)) {
        return `${substrateLabels[key]} must be between 0% and 100% (got ${val}%).`;
      }
    }
    return null;
  });

  const trackedNumberKeys = ['startDate', 'elevation', 'slope', 'aspect', 'standAge', 'accuracy'] as const;
  function fieldErrorMessage(key: NullableTextKey | NumberKey): string | null {
    if (key === 'date') return dateError;
    if (key === 'utmZone') return utmZoneError;
    if (key === 'structuralStage') return standCodeState.lengthErrors.structuralStage ?? null;
    if (key === 'successional') return standCodeState.lengthErrors.successional ?? null;
    if ((trackedNumberKeys as readonly string[]).includes(key)) {
      const nKey = key as NumberKey;
      return rawNumberErrors[nKey] ?? domainNumberError(nKey, draft[nKey]);
    }
    return null;
  }

  $effect(() => {
    const pErr = plotNumberError;
    const dErr = dateError;
    const zErr = utmZoneError;
    const sErr = standCodeState.validation;
    const subErr = substrateBoundsError;
    const numErrs = trackedNumberKeys.map(k => [k, rawNumberErrors[k] ?? domainNumberError(k, draft[k])] as const);
    untrack(() => {
      onvalidation('plotNumber', pErr);
      onvalidation('date', dErr);
      onvalidation('utmZone', zErr);
      onvalidation('standCodes', sErr);
      onvalidation('substrateBounds', subErr);
      for (const [k, msg] of numErrs) {
        onvalidation(k, msg);
      }
    });
  });

  const pageName = $derived(sourcePage ? 'Site/Veg' : 'Site');
  const page = $derived(sourcePage ?? paperPage('Site', 'initial', coordinateMode));
  const groups = $derived(presentationGroups(pageName, page.controls));
  const headerSubstrateSummary = $derived.by(() => {
    let sum = 0;
    let count = 0;
    for (const key of substrateKeys) {
      const val = draft[key];
      if (typeof val === 'number' && Number.isFinite(val)) {
        sum += val;
        count++;
      }
    }
    if (count === 0) return { totalText: 'Total: — / 100%', sumWarning: null };
    const rounded = Math.round(sum * 100) / 100;
    const sumWarning = Math.abs(sum - 100) > 1.0
      ? `Populated substrates sum to ${rounded}% (LMH25 expects 100% total).`
      : null;
    return { totalText: `Total: ${rounded}% / 100%`, sumWarning };
  });
  const headerSubstrateTotalText = $derived(headerSubstrateSummary.totalText);

  const sections: { title: string; fields: Field[] }[] = [
    { title: 'Identity and survey', fields: [
      { key: 'projectId', label: 'Project ID', kind: 'text' },
      { key: 'fieldNo', label: 'Field number', kind: 'text' },
      { key: 'surveyor', label: 'Site surveyor', kind: 'text' },
      { key: 'date', label: 'Survey date', kind: 'text' },
      { key: 'startDate', label: 'Start year', kind: 'number' }
    ] },
    { title: 'Location and coordinates', fields: [
      { key: 'generalLocation', label: 'Location', kind: 'text' },
      { key: 'mapSheet', label: 'NTS map sheet', kind: 'text' },
      { key: 'utmZone', label: 'UTM zone', kind: 'text' },
      { key: 'easting', label: 'UTM easting', kind: 'number', step: 'any' },
      { key: 'northing', label: 'UTM northing', kind: 'number', step: 'any' },
      { key: 'accuracy', label: 'Location accuracy', kind: 'number' }
    ] },
    { title: 'Classification', fields: [
      { key: 'plotRepresenting', label: 'Plot representing', kind: 'text' },
      { key: 'transition', label: 'Transition distribution', kind: 'text' },
      { key: 'mapUnit', label: 'Map unit', kind: 'text' },
      { key: 'moistureRegime', label: 'Moisture regime', kind: 'text', list: true },
      { key: 'nutrientRegime', label: 'Nutrient regime', kind: 'text', list: true }
    ] },
    { title: 'Stand information', fields: [
      { key: 'successional', label: 'Successional status', kind: 'text' },
      { key: 'structuralStage', label: 'Structural stage', kind: 'text' },
      { key: 'standAge', label: 'Stand age', kind: 'number' }
    ] },
    { title: 'Topography', fields: [
      { key: 'elevation', label: 'Elevation (m)', kind: 'number' },
      { key: 'slope', label: 'Slope gradient (%)', kind: 'number', step: 'any' },
      { key: 'aspect', label: 'Aspect (degrees)', kind: 'number' },
      { key: 'mesoSlopePos', label: 'Meso slope position', kind: 'text', list: true },
      { key: 'surfaceShape', label: 'Surface shape', kind: 'text', list: true },
      { key: 'microtopType', label: 'Surface topography type', kind: 'text' },
      { key: 'microtopSize', label: 'Surface topography size', kind: 'text' }
    ] },
    { title: 'Notes', fields: [
      { key: 'fieldNotes', label: 'Site notes', kind: 'notes' },
      { key: 'officeNotes', label: 'Office notes', kind: 'notes' }
    ] }
  ];

  const columns: Partial<Record<Exclude<keyof FS882Header, 'locked'>, string>> = {
    plotNumber: 'PlotNumber', projectId: 'ProjectID', surveyor: 'SiteSurveyor',
    date: 'Date', fieldNo: 'FieldNumber', generalLocation: 'Location', mapSheet: 'NtsMapSheet',
    utmZone: 'UTMZone', easting: 'UTMEasting', northing: 'UTMNorthing', accuracy: 'LocationAccuracy',
    plotRepresenting: 'PlotRepresenting', siteSeries: 'SiteSeries', transition: 'TransDistrib',
    mapUnit: 'MapUnit', moistureRegime: 'MoistureRegime', nutrientRegime: 'NutrientRegime',
    successional: 'SuccessionalStatus', structuralStage: 'StructuralStage', standAge: 'StandAge',
    elevation: 'Elevation', slope: 'SlopeGradient', aspect: 'Aspect', mesoSlopePos: 'MesoSlopePosition',
    surfaceShape: 'SurfaceShape', microtopType: 'SurfaceTopographyType',
    microtopSize: 'SurfaceTopographySize', fieldNotes: 'SiteNotes', officeNotes: 'OfficeNotes',
    startDate: 'StartDate'
  };
  const byColumn = new Map(sections.flatMap(section => section.fields).map(field => [columns[field.key], field]));
  const storedValues = $derived(new Map(Object.entries(draft).map(([key, value]) => [key.toLowerCase(), value])));
  const ordered = $derived(page.controls);
  const ownedColumns = $derived([...new Set(ordered.flatMap(control => {
    const column = control.column;
    if (!column || column === 'PlotNumber') return [];
    return isCoordinateControl(control.controlName) || isWorkingUnitControl(control.controlName) ||
      becKey(column) || qualityKey(column) || substrateKey(column) || siteCodeKey(column) || regionCodeKey(column) ||
      additionalEditor?.columns.includes(column) || editor?.columns.includes(column) || byColumn.has(column) ? [column] : [];
  }))]);
  const ownedControls = $derived(ordered.filter(control => !control.column &&
    isCoordinateControl(control.controlName) && control.controlName !== 'optCoordMethod2').map(control => control.controlId));
  function inputOwner(control: PaperControl): PaperControl {
    const source = ordered.find(source => source.controlId === control.controlId && source.column === control.column);
    if (!(control.column ? ownedColumns.includes(control.column) : ownedControls.includes(control.controlId)) ||
        !source) {
      throw new Error(`Header input ${control.controlName} has no exact source field owner.`);
    }
    return source;
  }
  function position(control: PaperControl) {
    if (['CheckBox', 'OptionButton'].includes(control.type)) return 'box-sizing:border-box;';
    return 'box-sizing:border-box;width:100%;min-width:0;min-height:40px;font:inherit;';
  }
  function inputId(control: PaperControl): string {
    if (isCoordinateControl(control.controlName)) return `header-coordinate-${control.controlName}`;
    if (isWorkingUnitControl(control.controlName)) {
      if (control.column === 'BECSiteUnit') return 'header-becSiteUnit';
      if (control.column === 'UserSiteUnit') return 'header-userSiteUnit';
      return `header-working-unit-${control.controlName}`;
    }
    const key = becKey(control.column) ?? qualityKey(control.column) ?? substrateKey(control.column) ??
      siteCodeKey(control.column) ?? regionCodeKey(control.column) ??
      (additionalEditor?.columns.includes(control.column ?? '') ? nullableParentField(control.column)?.key : undefined) ??
      byColumn.get(control.column ?? '')?.key;
    return key ? `header-${key}` : control.column === 'RealmClass' && editor?.columns.includes('RealmClass')
      ? 'header-realmClass' : control.column === 'PlotNumber' ? 'header-plotNumber' : `header-source-${control.controlId}`;
  }

  function headerHelpId(column?: string, controlName?: string): string | undefined {
    if (controlName && isCoordinateControl(controlName)) return 'site.coordinates';
    if (controlName && isWorkingUnitControl(controlName)) return 'site.bgc_zone';
    const col = (column ?? '').toLowerCase();
    if (!col) return undefined;
    if (col === 'plotnumber') return 'site.plot_number';
    if (col === 'fieldnumber' || col === 'projectid') return 'site.field_number';
    if (col === 'date' || col === 'sitesurveyor' || col === 'vegsurveyor' || col === 'soilsurveyor' || col === 'startdate') return 'site.date';
    if (col === 'zone' || col === 'subzone' || col === 'siteseries' || col === 'becsiteunit' || col === 'usersiteunit' || col === 'mapunit' || col === 'plotrepresenting' || col === 'transdistrib') return 'site.bgc_zone';
    if (col === 'ecosection' || col === 'fsregiondistrict') return 'site.ecosection';
    if (col === 'latitude' || col === 'longitude' || col === 'utmzone' || col === 'utmeasting' || col === 'utmnorthing' || col === 'locationaccuracy' || col === 'ntsmapsheet' || col === 'location') return 'site.coordinates';
    if (col === 'elevation' || col === 'slopegradient' || col === 'aspect') return 'site.elevation';
    if (col === 'mesoslopeposition' || col === 'surfaceshape' || col === 'surfacetopographytype' || col === 'surfacetopographysize') return 'site.meso_slope';
    if (col === 'moistureregime') return 'site.moisture_regime';
    if (col === 'nutrientregime') return 'site.nutrient_regime';
    if (col.startsWith('substrate')) return 'site.substrate_cover';
    if (col === 'structuralstage' || col === 'successionalstatus' || col === 'standage') return 'site.successional_structural';
    if (col === 'realmclass' || col === 'snowcoverregime' || col === 'activelayerdepth') return 'site.realm_class';
    if (col === 'humusform') return 'humus.humus_form';
    if (col === 'rootingdepth' || col === 'rootrestrictingtype' || col === 'rootrestrictingdepth' || col === 'seepagedepth' || col === 'soildrainage') return 'soil.rooting_seepage';
    return 'site.plot_number';
  }

  function setText(key: NullableTextKey, value: string) {
    draft[key] = value === '' ? null : value;
    if (key === 'structuralStage' || key === 'successional') {
      standCodesAcknowledged = false;
    }
    onchange();
  }

  function setNumber(key: NumberKey, input: HTMLInputElement) {
    if (input.validity.badInput || input.validity.stepMismatch) {
      const message = `Enter a valid ${input.step === 'any' ? 'number' : 'integer'} for ${key}.`;
      rawNumberErrors = { ...rawNumberErrors, [key]: message };
      onvalidation(key, message);
      onchange();
      onerror(message);
      return;
    }
    if (input.value === '') {
      draft[key] = null;
    } else if (Number.isFinite(input.valueAsNumber)) {
      draft[key] = input.valueAsNumber;
    } else {
      const message = `Enter a valid number for ${key}.`;
      rawNumberErrors = { ...rawNumberErrors, [key]: message };
      onvalidation(key, message);
      onchange();
      onerror(message);
      return;
    }
    if (key in rawNumberErrors) {
      const nextRaw = { ...rawNumberErrors };
      delete nextRaw[key];
      rawNumberErrors = nextRaw;
    }
    onvalidation(key, domainNumberError(key, draft[key]));
    onchange();
  }

  function attachSuContextMenu(node: HTMLElement) {
    function onContextMenu(event: MouseEvent) {
      event.preventDefault();
      const copyBtn = node.closest('.responsive-form')?.querySelector<HTMLButtonElement>('[data-source-control="btnCoptToWorkingUnit"]');
      if (copyBtn && !copyBtn.disabled) copyBtn.click();
    }
    node.addEventListener('contextmenu', onContextMenu);
    return { destroy() { node.removeEventListener('contextmenu', onContextMenu); } };
  }
</script>

<WorkingUnitFields bind:draft {original} controls={ordered} {position} {capabilities} {disabled}
  {onchange} {onerror} {onvalidation} {masterAllowed} onbusy={onWorkingUnitBusyChange} session={workingUnitSession}>
{#snippet children(workingUnitInputs)}
<QualityFields bind:draft {original} controls={ordered} {position} {capabilities} {disabled}
  {onchange} {onvalidation} onbusy={onQualityBusyChange}>
{#snippet children(qualityInputs)}
<SiteCodeFields bind:draft {original} controls={ordered} {position} {capabilities} {disabled}
  {onchange} {onvalidation} onbusy={onSiteCodeBusyChange}>
{#snippet children(siteCodeInputs)}
<RegionCodeFields bind:draft {original} controls={ordered} {position} {capabilities} {disabled}
  {onchange} {onvalidation} onbusy={onRegionCodeBusyChange}>
{#snippet children(regionCodeInputs)}
<SubstrateFields bind:draft {original} controls={ordered} {position} {capabilities} {disabled}
  {onchange} {onvalidation}>
{#snippet children(substrateInputs)}
<BECFields bind:draft {original} controls={ordered} {position} {capabilities} {disabled} {onchange}   {onvalidation}>
{#snippet children(becInputs)}
<CoordinateFields bind:draft bind:mode={coordinateMode} controls={ordered} {position} {capabilities} {disabled}
  {onchange} {onerror} {onvalidation} onbusy={onCoordinateBusyChange}>
{#snippet children(coordinateInputs)}
{#snippet fieldInput(control: PaperControl)}
        {@const field = byColumn.get(control.column ?? '')}
        {@const stored = control.column ? storedValues.get(control.column.toLowerCase()) : undefined}
        {@const unavailable = disabled || !control.enabled || control.locked}
        {@const action = control.type === 'CommandButton' || control.type === 'ToggleButton' || control.type === 'Subform'}
        {#if !action}<label class="field-label" for={inputId(control)}>{controlLabel(control, Boolean(sourcePage))}</label>{/if}
        {#if isCoordinateControl(control.controlName)}
          {@render coordinateInputs(control)}
        {:else if isWorkingUnitControl(control.controlName)}
          {#if control.controlName === 'UserSiteUnit' || control.controlName === 'BECSiteUnit'}
            <span class="su-context-wrap" use:attachSuContextMenu title="Right-click to copy BEC Master Site Unit to Working Unit">
              {@render workingUnitInputs(control)}
            </span>
          {:else}
            {@render workingUnitInputs(control)}
          {/if}
        {:else if becKey(control.column)}
          {@render becInputs(control)}
        {:else if qualityKey(control.column)}
          {@render qualityInputs(control)}
        {:else if substrateKey(control.column)}
          {@render substrateInputs(control)}
        {:else if siteCodeKey(control.column)}
          {@render siteCodeInputs(control)}
        {:else if regionCodeKey(control.column)}
          {@render regionCodeInputs(control)}
        {:else if additionalEditor && control.column && additionalEditor.columns.includes(control.column)}
          {@render additionalEditor.input(control, position(control))}
        {:else if editor && control.column && editor.columns.includes(control.column)}
          {@render editor.input(control, position(control))}
        {:else if control.column === 'PlotNumber'}
          <input class="paper-control plot-number-control" id="header-plotNumber" data-column={control.column} data-source-control={control.controlName} aria-label="Plot number"
            title={existing ? 'Existing plot identities cannot be renamed here' : 'Plot number'}
            value={draft.plotNumber} readonly={existing} disabled={unavailable || capabilities.plotNumber !== true}
            aria-invalid={plotNumberError ? 'true' : undefined}
            data-help-id="site.plot_number"
            oninput={(event) => { draft.plotNumber = event.currentTarget.value; onchange(); }} />
          {#if plotNumberError}<p role="alert" class="field-validation-alert">{plotNumberError}</p>{/if}
        {:else if field}
          {@const fErr = fieldErrorMessage(field.key)}
          {#if field.kind === 'number'}
            <input class="paper-control numeric-control" id={`header-${field.key}`} data-column={control.column} data-source-control={control.controlName} aria-label={field.label}
              type="number" step={field.step ?? '1'} value={draft[field.key] ?? ''}
              disabled={unavailable || capabilities[field.key] !== true}
              aria-invalid={fErr ? 'true' : undefined}
              data-help-id={headerHelpId(control.column, control.controlName)}
              oninput={(event) => setNumber(field.key, event.currentTarget)} />
            {#if fErr}<p role="alert" class="field-validation-alert">{fErr}</p>{/if}
          {:else if field.kind === 'notes'}
            <textarea class="paper-control" id={`header-${field.key}`} data-column={control.column} data-source-control={control.controlName} aria-label={field.label}
              value={draft[field.key] ?? ''} disabled={unavailable || capabilities[field.key] !== true}
              data-help-id={headerHelpId(control.column, control.controlName)}
              oninput={(event) => setText(field.key, event.currentTarget.value)}></textarea>
          {:else if field.list}
            <select class="paper-control" id={`header-${field.key}`} data-column={control.column} data-source-control={control.controlName} aria-label={field.label}
              value={draft[field.key] ?? ''} disabled={unavailable || capabilities[field.key] !== true || !lists[field.key]?.length}
              data-help-id={headerHelpId(control.column, control.controlName)}
              onchange={(event) => setText(field.key, event.currentTarget.value)}>
              <option value="">-</option>
              {#if draft[field.key] && !lists[field.key]?.some(item => item.item === draft[field.key])}
                <option value={draft[field.key] ?? ''}>{draft[field.key]}</option>
              {/if}
              {#each lists[field.key] ?? [] as item (item.item)}
                <option value={item.item}>{item.item} - {item.itemDescription}</option>
              {/each}
            </select>
          {:else}
            <input class="paper-control" id={`header-${field.key}`} data-column={control.column} data-source-control={control.controlName} aria-label={field.label}
              list={field.key === 'projectId' && projectIds.length ? 'header-projectId-options' : field.key === 'structuralStage' ? 'header-structuralStage-options' : field.key === 'successional' ? 'header-successional-options' : undefined}
              value={draft[field.key] ?? ''} disabled={unavailable || capabilities[field.key] !== true}
              aria-invalid={fErr ? 'true' : undefined}
              data-help-id={headerHelpId(control.column, control.controlName)}
              oninput={(event) => setText(field.key, event.currentTarget.value)} />
            {#if fErr}<p role="alert" class="field-validation-alert">{fErr}</p>{/if}
            {#if field.key === 'projectId' && projectIds.length}
              <datalist id="header-projectId-options">
                {#each projectIds as pid (pid)}
                  <option value={pid}></option>
                {/each}
              </datalist>
            {:else if field.key === 'structuralStage'}
              <datalist id="header-structuralStage-options">
                {#each STRUCTURAL_STAGE_OPTIONS as opt (opt.code)}
                  <option value={opt.code}>{opt.code} - {opt.label}</option>
                {/each}
              </datalist>
            {:else if field.key === 'successional'}
              <datalist id="header-successional-options">
                {#each SUCCESSIONAL_STATUS_OPTIONS as opt (opt.code)}
                  <option value={opt.code}>{opt.code} - {opt.label}</option>
                {/each}
              </datalist>
            {/if}
          {/if}
        {:else if control.type === 'CommandButton' || control.type === 'ToggleButton'}
          {#if control.controlName === 'btnLoadMetadata' && onMetadata}
            <button type="button" class="paper-control" data-source-control={control.controlName} disabled={metadataDisabled} onclick={onMetadata}>{controlLabel(control)}</button>
          {:else if control.controlName === 'btnManagePictures' && onOpenPictureManager}
            <button type="button" class="paper-control" data-source-control={control.controlName}
              disabled={!draft.plotNumber.trim()}
              title={draft.plotNumber.trim() ? `Manage pictures for plot ${draft.plotNumber.trim()}` : 'Select or enter a Plot Number first'}
              onclick={() => { if (draft.plotNumber.trim()) onOpenPictureManager(draft.plotNumber.trim()); }}>{controlLabel(control)}</button>
          {:else if control.controlName === 'Toggle408' || control.controlName === 'Toggle409'}
            <button type="button" class="paper-control pending" data-source-control={control.controlName} disabled title="Legacy Access paper-form display toggle (not used in VPro 2.0 web layout)">{controlLabel(control)}</button>
          {:else}
            <button type="button" class="paper-control pending" data-source-control={control.controlName} disabled title="Legacy Access paper-form action; use the corresponding VPro 2.0 workflow">{controlLabel(control)}</button>
          {/if}
        {:else if control.type === 'CheckBox' || control.type === 'OptionButton'}
          <input class="paper-control pending" id={inputId(control)} data-column={control.column} data-source-control={control.controlName} type={control.type === 'OptionButton' ? 'radio' : 'checkbox'} checked={stored === true} disabled aria-label={controlLabel(control)} />
        {:else if control.type === 'Subform'}
          {#if pictureEditor && control.controlName === 'frmVPics' && control.properties.SourceObject?.value === 'Form.frmVPicsXL'}
            <div class="embedded" data-source-control={control.controlName}>{@render pictureEditor()}</div>
          {:else}
          <div class="pending embedded" data-source-control={control.controlName} title="Pictures subform is managed via Pictures tab or Picture Manager">Pictures panel</div>
          {/if}
        {:else if control.type === 'TextBox' || control.type === 'ComboBox'}
          <input class="paper-control pending" id={inputId(control)} data-column={control.column} data-source-control={control.controlName} disabled value={typeof stored === 'string' || typeof stored === 'number' ? stored : ''} placeholder={stored !== undefined ? '' : 'Legacy field'} title={`${controlLabel(control)}: read-only legacy Access field`} aria-label={controlLabel(control)} />
        {/if}
{/snippet}
{#snippet input(control: PaperControl, _position: string)}
  {@render fieldInput(inputOwner(control))}
{/snippet}
{#if layoutContent}
  {@render layoutContent({ columns: ownedColumns, controls: ownedControls, input, labelled: true }, coordinateMode)}
{:else}
<div class="responsive-form header-editor" data-source-page={pageName}>
  {#each groups as group (group.title)}
    {@const allStubs = group.controls.length > 0 && group.controls.every(control => isUnmigratedStubControl(control))}
    <fieldset class="form-group" class:unmigrated-group={allStubs} data-card-zone={groupCardZone(pageName, group.title)} data-group-title={group.title}>
      <legend>{group.title}</legend>
      {#if group.title === 'Substrate (%)'}
        <div class="group-meta-bar">
          {#if headerSubstrateSummary.sumWarning}
            <span role="status" class="substrate-sum-warning" data-substrate-sum-warning>{headerSubstrateSummary.sumWarning}</span>
          {/if}
          <span class="group-total-badge tabular-nums" data-substrate-total data-header-substrate-total>{headerSubstrateTotalText}</span>
        </div>
        {#if substrateBoundsError}
          <p role="alert" class="field-validation-alert mb-2">{substrateBoundsError}</p>
        {/if}
      {/if}
      {#if standCodeState.warnings.length > 0 && group.controls.some(c => c.column === 'StructuralStage' || c.column === 'SuccessionalStatus')}
        <div class="stand-code-review" aria-label="Stand code review">
          {#each standCodeState.warnings as warn}<p role="alert" class="field-validation-alert">{warn}</p>{/each}
          <div class="stand-code-ack">
            <input id="stand-code-acknowledgement" type="checkbox" checked={standCodesAcknowledged} disabled={disabled}
              onchange={(event) => { standCodesAcknowledged = event.currentTarget.checked; onchange(); }} />
            <label for="stand-code-acknowledgement">Keep unlisted stand code(s) exactly as entered; I have reviewed these warnings.</label>
          </div>
        </div>
      {/if}
      <div class="field-grid">
      {#each group.controls as control (control.controlId)}
        {@const action = control.type === 'CommandButton' || control.type === 'ToggleButton' || control.type === 'Subform'}
        {@const span = controlColumnSpan(pageName, group.title, control)}
        {@const stub = isUnmigratedStubControl(control)}
        <div class="form-field" class:full-width={wideControl(control)} class:action-field={action} class:unmigrated-source-stub={stub} data-col-span={span} data-help-id={action ? undefined : headerHelpId(control.column, control.controlName)}>
        {@render fieldInput(control)}
        </div>
      {/each}
      </div>
    </fieldset>
  {/each}
  {#if extendedShrubs}
    <fieldset class="form-group" data-card-zone="full" data-extended-arctic-fields data-help-id="site.realm_class">
      <legend>Arctic / extended site fields</legend>
      <div class="field-grid">
        <div class="form-field" data-col-span={6} data-help-id="site.realm_class">
          <label class="field-label" for="header-snowCoverregime">Snow cover regime</label>
          <input class="paper-control" id="header-snowCoverregime" data-column="SnowCoverregime" type="text"
            value={snowCoverRegime} disabled={(snowCoverRegimeDisabled ?? disabled) || capabilities.snowCoverRegime !== true || !onSnowCoverRegimeChange}
            aria-invalid={snowCoverRegimeError ? 'true' : undefined}
            title={onSnowCoverRegimeChange ? 'SnowCoverregime' : 'Use Complete two-page entry or SIVI parent editor to save SnowCoverregime'}
            data-help-id="site.realm_class"
            oninput={(event) => onSnowCoverRegimeChange?.(event.currentTarget.value)} />
          {#if snowCoverRegimeError}<p role="alert" class="text-xs text-red-700 mt-1">{snowCoverRegimeError}</p>{/if}
        </div>
        <div class="form-field" data-col-span={6} data-help-id="site.realm_class">
          <label class="field-label" for="header-activeLayerDepth">Active layer depth (cm)</label>
          <input class="paper-control numeric-control" id="header-activeLayerDepth" data-column="ActiveLayerDepth" type="text" inputmode="decimal"
            value={activeLayerDepth} disabled={(activeLayerDepthDisabled ?? disabled) || capabilities.activeLayerDepth !== true || !onActiveLayerDepthChange}
            aria-invalid={activeLayerDepthError ? 'true' : undefined}
            title={onActiveLayerDepthChange ? 'ActiveLayerDepth' : 'Use Complete two-page entry or Two-page additional fields to save ActiveLayerDepth'}
            data-help-id="site.realm_class"
            oninput={(event) => onActiveLayerDepthChange?.(event.currentTarget.value)} />
          {#if activeLayerDepthError}<p role="alert" class="text-xs text-red-700 mt-1">{activeLayerDepthError}</p>{/if}
        </div>
      </div>
    </fieldset>
  {/if}
</div>
{/if}
{/snippet}
</CoordinateFields>
{/snippet}
</BECFields>
{/snippet}
</SubstrateFields>
{/snippet}
</RegionCodeFields>
{/snippet}
</SiteCodeFields>
{/snippet}
</QualityFields>
{/snippet}
</WorkingUnitFields>

<style>
  .su-context-wrap { display: contents; }
  .responsive-form { display: grid; grid-template-columns: repeat(12, minmax(0, 1fr)); gap: .85rem; align-items: start; grid-auto-flow: row dense; }
  .form-group { grid-column: 1 / -1; margin: 0; border-color: var(--vpro-border, #d1d5db); border-top: 3px solid var(--vpro-gold, #fcba19); background: var(--vpro-surface, #ffffff); }
  .form-group :global(legend) { color: var(--vpro-navy, #003366); }
  .group-meta-bar { display: flex; flex-wrap: wrap; align-items: center; justify-content: flex-end; gap: .5rem; margin: 0 0 .45rem; }
  .group-total-badge { display: inline-flex; align-items: center; padding: .15rem .55rem; border-radius: 999px; border: 1px solid var(--vpro-border, #d1d5db); background: var(--vpro-navy-tint, #ebf1f8); color: var(--vpro-navy, #003366); font-family: var(--vpro-font-mono, monospace); font-size: .72rem; font-weight: 600; font-variant-numeric: tabular-nums; }
  .substrate-sum-warning { display: inline-flex; align-items: center; padding: .15rem .55rem; border-radius: 4px; border: 1px solid #d97706; background: #fffbeb; color: #92400e; font-size: .72rem; font-weight: 600; }
  .field-validation-alert { margin: .2rem 0 0; font-size: .72rem; color: var(--vpro-error-ink, #a61b20); }
  .stand-code-review { display: grid; gap: .3rem; padding: .45rem .6rem; margin: 0 0 .5rem; border: 1px solid #d97706; border-radius: 4px; background: #fffbeb; font-size: .75rem; }
  .stand-code-ack { display: flex; align-items: center; gap: .35rem; color: #313132; }
  .paper-control[aria-invalid="true"] { border-color: var(--vpro-error, #d8292f); }
  .unmigrated-source-stub, .unmigrated-group { display: none; }
  .paper-control { box-sizing: border-box; width: 100%; min-width: 0; min-height: 40px; border: 1px solid var(--vpro-forest-border, #D8D8D8); border-radius: 4px; padding: .5rem .65rem; background: var(--vpro-surface, white); color: var(--vpro-ink, #313132); font: inherit; line-height: 1.4; }
  .plot-number-control { font-family: var(--vpro-font-mono, monospace); font-variant-numeric: tabular-nums; font-weight: 600; }
  .numeric-control { font-family: var(--vpro-font-mono, monospace); font-variant-numeric: tabular-nums; }
  .paper-control:focus { outline: 2px solid var(--vpro-focus-ring, #1a5a96); outline-offset: 1px; }
  .paper-control:disabled { color: var(--vpro-ink-muted, #5f6b7a); background: var(--vpro-surface-subtle, #f8fafb); }
  .pending { opacity: .65; }
  .embedded { display: flex; align-items: center; justify-content: center; }
  @container fs882-fields (min-width: 960px) {
    .form-group[data-card-zone="quad-left"] { grid-column: 1 / 7; }
    .form-group[data-card-zone="quad-right"] { grid-column: 7 / 13; }
    .form-group[data-card-zone="top-band"] { grid-column: span 6; }
    .form-group[data-group-title="Identity and survey"] { grid-column: 1 / 9; }
    .form-group[data-group-title="Project"] { grid-column: 9 / 13; }
    .form-group[data-card-zone="full"] { grid-column: 1 / -1; }
  }
  @container fs882-fields (min-width: 901px) {
    .form-field[data-col-span="2"] { grid-column: span 2; }
    .form-field[data-col-span="3"] { grid-column: span 3; }
    .form-field[data-col-span="4"] { grid-column: span 4; }
    .form-field[data-col-span="6"] { grid-column: span 6; }
    .form-field[data-col-span="12"] { grid-column: 1 / -1; }
  }
</style>
