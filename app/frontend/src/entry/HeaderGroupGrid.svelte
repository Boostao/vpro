<script lang="ts">
  import { untrack, type Snippet } from 'svelte';
  import type { FS882Header } from '../../bindings/github.com/boostao/vpro/app';
  import type { PaperControl } from './paperLayout';
  import {
    controlColumnSpan,
    groupCardZone,
    isUnmigratedStubControl,
    type presentationGroups,
    wideControl,
  } from './formPresentation';
  import { substrateKeys, substrateLabels } from './substrateEditor';
  import { isCoordinateControl } from './coordinateEditor';
  import { isWorkingUnitControl } from './workingUnitEditor';

  type TextKey = { [K in keyof FS882Header]: FS882Header[K] extends string | null ? K : never }[keyof FS882Header];
  type NullableTextKey = Exclude<TextKey, 'plotNumber'>;
  type NumberKey = { [K in keyof FS882Header]: FS882Header[K] extends number | null ? K : never }[keyof FS882Header];
  type BaseValidationKey = NumberKey | 'plotNumber' | 'date' | 'utmZone' | 'standCodes' | 'substrateBounds';

  export interface HeaderValidationContext {
    plotNumberError: string | null;
    fieldErrorMessage: (key: NullableTextKey | NumberKey) => string | null;
    headerHelpId: (column?: string, controlName?: string) => string | undefined;
    setText: (key: NullableTextKey, value: string) => void;
    setNumber: (key: NumberKey, input: HTMLInputElement) => void;
  }

  const STRUCTURAL_CODES = new Set([
    '1',
    '1a',
    '1b',
    '1c',
    '2',
    '2a',
    '2b',
    '2c',
    '2d',
    '3',
    '3a',
    '3b',
    '3c',
    '3d',
    '4',
    '5',
    '6',
    '7',
    '7a',
    '7b',
  ]);
  const SUCCESSIONAL_CODES = new Set(['nv', 'ps', 'ys', 'ms', 'os', 'yc', 'mc', 'oc', 'dc']);
  const TRACKED_NUMBER_KEYS = ['startDate', 'elevation', 'slope', 'aspect', 'standAge', 'accuracy'] as const;

  let {
    draft = $bindable(),
    original,
    existing,
    disabled,
    pageName,
    groups,
    hasCustomLayout,
    onchange,
    onerror,
    onvalidation,
    customLayout,
    renderControl,
    arcticFields,
  }: {
    draft: FS882Header;
    original: Partial<FS882Header> | null;
    existing: boolean;
    disabled: boolean;
    pageName: string;
    groups: ReturnType<typeof presentationGroups>;
    hasCustomLayout: boolean;
    onchange: () => void;
    onerror: (message: string) => void;
    onvalidation: (key: BaseValidationKey, message: string | null) => void;
    customLayout?: Snippet<[HeaderValidationContext]>;
    renderControl: Snippet<[PaperControl, HeaderValidationContext]>;
    arcticFields?: Snippet;
  } = $props();

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

  function isChangedFromBaseline<K extends keyof FS882Header>(key: K, current: FS882Header[K] | undefined): boolean {
    if (!existing || !original) return (current ?? null) !== null;
    if (!(key in original)) return false;
    return (current ?? null) !== ((original[key] ?? null) as FS882Header[K] | null);
  }

  function domainNumberError(key: NumberKey, value: number | null | undefined): string | null {
    if (value == null || !isChangedFromBaseline(key, value)) return null;
    if (!Number.isFinite(value)) return `Enter a valid finite number for ${key}.`;
    if (key === 'startDate' && (!Number.isInteger(value) || value < 1900 || value > 2500)) {
      return 'Start year (Yr.) must be an integer between 1900 and 2500.';
    }
    if (key === 'elevation' && (!Number.isInteger(value) || value < 0 || value > 9000)) {
      return 'Elevation must be an integer between 0 and 9000 m above sea level.';
    }
    if (key === 'slope' && (value < 0 || value > 3.4028234663852886e38)) {
      return 'Slope gradient must be 0% or greater.';
    }
    if (key === 'aspect' && (!Number.isInteger(value) || (value !== 999 && (value < 0 || value > 360)))) {
      return 'Aspect must be an integer from 0 to 360 degrees, or 999 for level ground.';
    }
    if (key === 'standAge' && (!Number.isInteger(value) || value < 0 || value > 32767)) {
      return 'Stand age must be an integer from 0 to 32767 years.';
    }
    if (key === 'accuracy' && (!Number.isInteger(value) || value < 0 || value > 32767)) {
      return 'Location accuracy must be an integer from 0 to 32767 m.';
    }
    return null;
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
    !existing &&
      typeof draft.plotNumber === 'string' &&
      draft.plotNumber !== '' &&
      draft.plotNumber !== draft.plotNumber.trim()
      ? 'Plot number cannot start or end with spaces.'
      : null
  );
  const dateError = $derived(
    draft.date != null && isChangedFromBaseline('date', draft.date) && !isValidSurveyDateText(draft.date)
      ? 'Survey date must be a valid calendar date in YYYY-MM-DD format (for example 2026-07-15).'
      : null
  );
  const utmZoneError = $derived(
    draft.utmZone != null &&
      isChangedFromBaseline('utmZone', draft.utmZone) &&
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
      } else if (!STRUCTURAL_CODES.has(draft.structuralStage.toLowerCase())) {
        warnings.push(`Structural stage "${draft.structuralStage}" is not a standard LMH25 code (1–7, 1a–3d, 7a–7b).`);
      }
    }
    if (draft.successional != null && isChangedFromBaseline('successional', draft.successional)) {
      if (draft.successional.length > 3) {
        lengthErrors.successional = 'Successional status must be at most 3 characters (for example PS, YS, MS, MC).';
      } else if (!SUCCESSIONAL_CODES.has(draft.successional.toLowerCase())) {
        warnings.push(
          `Successional status "${draft.successional}" is not a standard LMH25 code (NV, PS, YS, MS, OS, YC, MC, OC, DC).`
        );
      }
    }
    const firstLengthErr = lengthErrors.structuralStage ?? lengthErrors.successional ?? null;
    const validation =
      firstLengthErr ??
      (warnings.length > 0 && !standCodesAcknowledged
        ? `${warnings[0]} Choose a listed LMH25 code or confirm keeping unlisted stand codes.`
        : null);
    return { lengthErrors, warnings, validation };
  });

  const substrateBoundsError = $derived.by(() => {
    for (const key of substrateKeys) {
      const val = draft[key];
      if (
        typeof val === 'number' &&
        Number.isFinite(val) &&
        isChangedFromBaseline(key, val) &&
        (val < 0 || val > 100)
      ) {
        return `${substrateLabels[key]} must be between 0% and 100% (got ${val}%).`;
      }
    }
    return null;
  });

  function fieldErrorMessage(key: NullableTextKey | NumberKey): string | null {
    if (key === 'date') return dateError;
    if (key === 'utmZone') return utmZoneError;
    if (key === 'structuralStage') return standCodeState.lengthErrors.structuralStage ?? null;
    if (key === 'successional') return standCodeState.lengthErrors.successional ?? null;
    if ((TRACKED_NUMBER_KEYS as readonly string[]).includes(key)) {
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
    const numErrs = TRACKED_NUMBER_KEYS.map((k) => [k, rawNumberErrors[k] ?? domainNumberError(k, draft[k])] as const);
    untrack(() => {
      onvalidation('plotNumber', pErr);
      onvalidation('date', dErr);
      onvalidation('utmZone', zErr);
      onvalidation('standCodes', sErr);
      onvalidation('substrateBounds', subErr);
      for (const [k, msg] of numErrs) onvalidation(k, msg);
    });
  });

  const headerSubstrateSummary = $derived.by(() => {
    let sum = 0;
    let count = 0;
    for (const key of substrateKeys) {
      const val = draft[key];
      if (typeof val === 'number' && Number.isFinite(val)) {
        sum += val;
        count += 1;
      }
    }
    if (count === 0) return { totalText: 'Total: — / 100%', sumWarning: null };
    const rounded = Math.round(sum * 100) / 100;
    const sumWarning =
      Math.abs(sum - 100) > 1.0 ? `Populated substrates sum to ${rounded}% (LMH25 expects 100% total).` : null;
    return { totalText: `Total: ${rounded}% / 100%`, sumWarning };
  });

  function headerHelpId(column?: string, controlName?: string): string | undefined {
    if (controlName && isCoordinateControl(controlName)) return 'site.coordinates';
    if (controlName && isWorkingUnitControl(controlName)) return 'site.bgc_zone';
    const col = (column ?? '').toLowerCase();
    if (!col) return undefined;
    if (col === 'plotnumber') return 'site.plot_number';
    if (col === 'fieldnumber' || col === 'projectid') return 'site.field_number';
    if (
      col === 'date' ||
      col === 'sitesurveyor' ||
      col === 'vegsurveyor' ||
      col === 'soilsurveyor' ||
      col === 'startdate'
    )
      return 'site.date';
    if (
      [
        'zone',
        'subzone',
        'siteseries',
        'becsiteunit',
        'usersiteunit',
        'mapunit',
        'plotrepresenting',
        'transdistrib',
      ].includes(col)
    )
      return 'site.bgc_zone';
    if (col === 'ecosection' || col === 'fsregiondistrict') return 'site.ecosection';
    if (
      [
        'latitude',
        'longitude',
        'utmzone',
        'utmeasting',
        'utmnorthing',
        'locationaccuracy',
        'ntsmapsheet',
        'location',
      ].includes(col)
    )
      return 'site.coordinates';
    if (col === 'elevation' || col === 'slopegradient' || col === 'aspect') return 'site.elevation';
    if (['mesoslopeposition', 'surfaceshape', 'surfacetopographytype', 'surfacetopographysize'].includes(col))
      return 'site.meso_slope';
    if (col === 'moistureregime') return 'site.moisture_regime';
    if (col === 'nutrientregime') return 'site.nutrient_regime';
    if (col.startsWith('substrate')) return 'site.substrate_cover';
    if (col === 'structuralstage' || col === 'successionalstatus' || col === 'standage')
      return 'site.successional_structural';
    if (col === 'realmclass' || col === 'snowcoverregime' || col === 'activelayerdepth') return 'site.realm_class';
    if (col === 'humusform') return 'humus.humus_form';
    if (['rootingdepth', 'rootrestrictingtype', 'rootrestrictingdepth', 'seepagedepth', 'soildrainage'].includes(col))
      return 'soil.rooting_seepage';
    return 'site.plot_number';
  }

  function setText(key: NullableTextKey, value: string) {
    draft[key] = value === '' ? null : value;
    if (key === 'structuralStage' || key === 'successional') standCodesAcknowledged = false;
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
    if (input.value === '') draft[key] = null;
    else if (Number.isFinite(input.valueAsNumber)) draft[key] = input.valueAsNumber;
    else {
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

  const validationCtx = $derived<HeaderValidationContext>({
    plotNumberError,
    fieldErrorMessage,
    headerHelpId,
    setText,
    setNumber,
  });
</script>

{#if hasCustomLayout && customLayout}
  {@render customLayout(validationCtx)}
{:else}
  <div class="responsive-form header-editor" data-source-page={pageName}>
    {#each groups as group (group.title)}
      {@const allStubs =
        group.controls.length > 0 && group.controls.every((control) => isUnmigratedStubControl(control))}
      <fieldset
        class="form-group"
        class:unmigrated-group={allStubs}
        data-card-zone={groupCardZone(pageName, group.title)}
        data-group-title={group.title}
      >
        <legend>{group.title}</legend>
        {#if group.title === 'Substrate (%)'}
          <div class="group-meta-bar">
            {#if headerSubstrateSummary.sumWarning}
              <span role="status" class="substrate-sum-warning" data-substrate-sum-warning
                >{headerSubstrateSummary.sumWarning}</span
              >
            {/if}
            <span class="group-total-badge tabular-nums" data-substrate-total data-header-substrate-total
              >{headerSubstrateSummary.totalText}</span
            >
          </div>
          {#if substrateBoundsError}
            <p role="alert" class="field-validation-alert mb-2">{substrateBoundsError}</p>
          {/if}
        {/if}
        {#if standCodeState.warnings.length > 0 && group.controls.some((c) => c.column === 'StructuralStage' || c.column === 'SuccessionalStatus')}
          <div class="stand-code-review" aria-label="Stand code review">
            {#each standCodeState.warnings as warn}<p role="alert" class="field-validation-alert">{warn}</p>{/each}
            <div class="stand-code-ack">
              <input
                id="stand-code-acknowledgement"
                type="checkbox"
                checked={standCodesAcknowledged}
                {disabled}
                onchange={(event) => {
                  standCodesAcknowledged = event.currentTarget.checked;
                  onchange();
                }}
              />
              <label for="stand-code-acknowledgement"
                >Keep unlisted stand code(s) exactly as entered; I have reviewed these warnings.</label
              >
            </div>
          </div>
        {/if}
        <div class="field-grid">
          {#each group.controls as control (control.controlId)}
            {@const action =
              control.type === 'CommandButton' || control.type === 'ToggleButton' || control.type === 'Subform'}
            {@const span = controlColumnSpan(pageName, group.title, control)}
            {@const stub = isUnmigratedStubControl(control)}
            <div
              class="form-field"
              class:full-width={wideControl(control)}
              class:action-field={action}
              class:unmigrated-source-stub={stub}
              data-col-span={span}
              data-help-id={action ? undefined : headerHelpId(control.column, control.controlName)}
            >
              {@render renderControl(control, validationCtx)}
            </div>
          {/each}
        </div>
      </fieldset>
    {/each}
    {@render arcticFields?.()}
  </div>
{/if}

<style>
  .responsive-form {
    display: grid;
    grid-template-columns: repeat(12, minmax(0, 1fr));
    gap: 0.85rem;
    align-items: start;
    grid-auto-flow: row dense;
  }
  .form-group {
    grid-column: 1 / -1;
    margin: 0;
    border-color: var(--vpro-border);
    border-top: 3px solid var(--vpro-gold);
    background: var(--vpro-surface);
  }
  .form-group :global(legend) {
    color: var(--vpro-navy);
  }
  .group-meta-bar {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: flex-end;
    gap: 0.5rem;
    margin: 0 0 0.45rem;
  }
  .group-total-badge {
    display: inline-flex;
    align-items: center;
    padding: 0.15rem 0.55rem;
    border-radius: 999px;
    border: 1px solid var(--vpro-border);
    background: var(--vpro-navy-tint);
    color: var(--vpro-navy);
    font-family: var(--vpro-font-mono, monospace);
    font-size: 0.72rem;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
  }
  .substrate-sum-warning {
    display: inline-flex;
    align-items: center;
    padding: 0.15rem 0.55rem;
    border-radius: 4px;
    border: 1px solid var(--vpro-warning);
    background: var(--vpro-warning-bg);
    color: var(--vpro-warning-ink);
    font-size: 0.72rem;
    font-weight: 600;
  }
  .field-validation-alert {
    margin: 0.2rem 0 0;
    font-size: 0.72rem;
    color: var(--vpro-error-ink);
  }
  .stand-code-review {
    display: grid;
    gap: 0.3rem;
    padding: 0.45rem 0.6rem;
    margin: 0 0 0.5rem;
    border: 1px solid var(--vpro-warning);
    border-radius: 4px;
    background: var(--vpro-warning-bg);
    font-size: 0.75rem;
  }
  .stand-code-ack {
    display: flex;
    align-items: center;
    gap: 0.35rem;
    color: var(--vpro-ink);
  }
  .unmigrated-source-stub,
  .unmigrated-group {
    display: none;
  }
  @container fs882-fields (min-width: 960px) {
    .form-group[data-card-zone='quad-left'] {
      grid-column: 1 / 7;
    }
    .form-group[data-card-zone='quad-right'] {
      grid-column: 7 / 13;
    }
    .form-group[data-card-zone='top-band'] {
      grid-column: span 6;
    }
    .form-group[data-group-title='Identity and survey'] {
      grid-column: 1 / 9;
    }
    .form-group[data-group-title='Project'] {
      grid-column: 9 / 13;
    }
    .form-group[data-card-zone='full'] {
      grid-column: 1 / -1;
    }
  }
  @container fs882-fields (min-width: 901px) {
    .form-field[data-col-span='2'] {
      grid-column: span 2;
    }
    .form-field[data-col-span='3'] {
      grid-column: span 3;
    }
    .form-field[data-col-span='4'] {
      grid-column: span 4;
    }
    .form-field[data-col-span='6'] {
      grid-column: span 6;
    }
    .form-field[data-col-span='12'] {
      grid-column: 1 / -1;
    }
  }
</style>
