<script lang="ts">
  import type { FS882Header, ListItem } from '../../bindings/github.com/boostao/vpro/app';
  import type { PaperControl } from './paperLayout';
  import { controlLabel } from './formPresentation';
  import type { HeaderValidationContext } from './HeaderGroupGrid.svelte';

  type TextKey = { [K in keyof FS882Header]: FS882Header[K] extends string | null ? K : never }[keyof FS882Header];
  type NullableTextKey = Exclude<TextKey, 'plotNumber'>;
  type NumberKey = { [K in keyof FS882Header]: FS882Header[K] extends number | null ? K : never }[keyof FS882Header];
  export type HeaderFieldDef =
    | { key: NullableTextKey; label: string; kind: 'text' | 'notes'; list?: boolean }
    | { key: NumberKey; label: string; kind: 'number'; step?: string };

  export interface HeaderStandardFieldOptions {
    existing: boolean;
    unavailable: boolean;
    capabilities: Record<string, boolean | undefined>;
    lists: Partial<Record<NullableTextKey, ListItem[]>>;
    stored: unknown;
    hasProjectIds: boolean;
    controlInputId: string;
  }

  const STRUCTURAL_STAGE_OPTIONS = [
    ['1', 'Non-vegetated / Sparse'],
    ['1a', 'Sparse'],
    ['1b', 'Bryoid'],
    ['1c', 'Lichen'],
    ['2', 'Herb'],
    ['2a', 'Forb-dominated'],
    ['2b', 'Graminoid-dominated'],
    ['2c', 'Aquatic'],
    ['2d', 'Dwarf shrub-dominated'],
    ['3', 'Shrub / Stunted trees'],
    ['3a', 'Low shrub (< 2 m)'],
    ['3b', 'Tall shrub (2–10 m)'],
    ['3c', 'Short stunted trees'],
    ['3d', 'Tall stunted trees'],
    ['4', 'Pole / Sapling'],
    ['5', 'Young Forest'],
    ['6', 'Mature Forest'],
    ['7', 'Old Forest'],
    ['7a', 'Old Forest (even/multi-aged)'],
    ['7b', 'Very Old Forest'],
  ] as const;

  const SUCCESSIONAL_STATUS_OPTIONS = [
    ['NV', 'Non-vegetated'],
    ['PS', 'Pioneer seral'],
    ['YS', 'Young seral'],
    ['MS', 'Maturing seral'],
    ['OS', 'Overmature seral'],
    ['YC', 'Young climax'],
    ['MC', 'Maturing climax'],
    ['OC', 'Old climax'],
    ['DC', 'Disclimax'],
  ] as const;

  let {
    control,
    field,
    draft = $bindable(),
    vCtx,
    opts,
    onchange,
  }: {
    control: PaperControl;
    field: HeaderFieldDef | undefined;
    draft: FS882Header;
    vCtx: HeaderValidationContext;
    opts: HeaderStandardFieldOptions;
    onchange: () => void;
  } = $props();

  const helpId = $derived(vCtx.headerHelpId(control.column, control.controlName));
  const fieldError = $derived(field ? vCtx.fieldErrorMessage(field.key) : null);
</script>

{#if control.column === 'PlotNumber'}
  <input
    class="paper-control plot-number-control"
    id="header-plotNumber"
    data-column={control.column}
    data-source-control={control.controlName}
    aria-label="Plot number"
    title={opts.existing ? 'Existing plot identities cannot be renamed here' : 'Plot number'}
    value={draft.plotNumber}
    readonly={opts.existing}
    disabled={opts.unavailable || opts.capabilities.plotNumber !== true}
    aria-invalid={vCtx.plotNumberError ? 'true' : undefined}
    data-help-id="site.plot_number"
    oninput={(event) => {
      draft.plotNumber = event.currentTarget.value;
      onchange();
    }}
  />
  {#if vCtx.plotNumberError}<p role="alert" class="field-validation-alert">{vCtx.plotNumberError}</p>{/if}
{:else if field}
  {#if field.kind === 'number'}
    <input
      class="paper-control numeric-control"
      id={`header-${field.key}`}
      data-column={control.column}
      data-source-control={control.controlName}
      aria-label={field.label}
      type="number"
      step={field.step ?? '1'}
      value={draft[field.key] ?? ''}
      disabled={opts.unavailable || opts.capabilities[field.key] !== true}
      aria-invalid={fieldError ? 'true' : undefined}
      data-help-id={helpId}
      oninput={(event) => vCtx.setNumber(field.key, event.currentTarget)}
    />
    {#if fieldError}<p role="alert" class="field-validation-alert">{fieldError}</p>{/if}
  {:else if field.kind === 'notes'}
    <textarea
      class="paper-control"
      id={`header-${field.key}`}
      data-column={control.column}
      data-source-control={control.controlName}
      aria-label={field.label}
      value={draft[field.key] ?? ''}
      disabled={opts.unavailable || opts.capabilities[field.key] !== true}
      data-help-id={helpId}
      oninput={(event) => vCtx.setText(field.key, event.currentTarget.value)}></textarea>
  {:else if field.list}
    <select
      class="paper-control"
      id={`header-${field.key}`}
      data-column={control.column}
      data-source-control={control.controlName}
      aria-label={field.label}
      value={draft[field.key] ?? ''}
      disabled={opts.unavailable || opts.capabilities[field.key] !== true || !opts.lists[field.key]?.length}
      data-help-id={helpId}
      onchange={(event) => vCtx.setText(field.key, event.currentTarget.value)}
    >
      <option value="">-</option>
      {#if draft[field.key] && !opts.lists[field.key]?.some((item) => item.item === draft[field.key])}
        <option value={draft[field.key] ?? ''}>{draft[field.key]}</option>
      {/if}
      {#each opts.lists[field.key] ?? [] as item (item.item)}
        <option value={item.item}>{item.item} - {item.itemDescription}</option>
      {/each}
    </select>
  {:else}
    <input
      class="paper-control"
      id={`header-${field.key}`}
      data-column={control.column}
      data-source-control={control.controlName}
      aria-label={field.label}
      list={field.key === 'projectId' && opts.hasProjectIds
        ? 'header-projectId-options'
        : field.key === 'structuralStage'
          ? 'header-structuralStage-options'
          : field.key === 'successional'
            ? 'header-successional-options'
            : undefined}
      value={draft[field.key] ?? ''}
      disabled={opts.unavailable || opts.capabilities[field.key] !== true}
      aria-invalid={fieldError ? 'true' : undefined}
      data-help-id={helpId}
      oninput={(event) => vCtx.setText(field.key, event.currentTarget.value)}
    />
    {#if fieldError}<p role="alert" class="field-validation-alert">{fieldError}</p>{/if}
    {#if field.key === 'structuralStage'}
      <datalist id="header-structuralStage-options">
        {#each STRUCTURAL_STAGE_OPTIONS as [code, label] (code)}<option value={code}>{code} - {label}</option>{/each}
      </datalist>
    {:else if field.key === 'successional'}
      <datalist id="header-successional-options">
        {#each SUCCESSIONAL_STATUS_OPTIONS as [code, label] (code)}<option value={code}>{code} - {label}</option>{/each}
      </datalist>
    {/if}
  {/if}
{:else if control.type === 'CheckBox' || control.type === 'OptionButton'}
  <input
    class="paper-control pending"
    id={opts.controlInputId}
    data-column={control.column}
    data-source-control={control.controlName}
    type={control.type === 'OptionButton' ? 'radio' : 'checkbox'}
    checked={opts.stored === true}
    disabled
    aria-label={controlLabel(control)}
  />
{:else if control.type === 'TextBox' || control.type === 'ComboBox'}
  <input
    class="paper-control pending"
    id={opts.controlInputId}
    data-column={control.column}
    data-source-control={control.controlName}
    disabled
    value={typeof opts.stored === 'string' || typeof opts.stored === 'number' ? opts.stored : ''}
    placeholder={opts.stored !== undefined ? '' : 'Legacy field'}
    title={`${controlLabel(control)}: read-only legacy Access field`}
    aria-label={controlLabel(control)}
  />
{/if}

<style>
  .field-validation-alert {
    margin: 0.2rem 0 0;
    font-size: 0.72rem;
    color: var(--vpro-error-ink);
  }
  .paper-control[aria-invalid='true'] {
    border-color: var(--vpro-error);
  }
  .paper-control {
    box-sizing: border-box;
    width: 100%;
    min-width: 0;
    min-height: 40px;
    border: 1px solid var(--vpro-forest-border);
    border-radius: 4px;
    padding: 0.5rem 0.65rem;
    background: var(--vpro-surface, white);
    color: var(--vpro-ink);
    font: inherit;
    line-height: 1.4;
  }
  .plot-number-control {
    font-family: var(--vpro-font-mono, monospace);
    font-variant-numeric: tabular-nums;
    font-weight: 600;
  }
  .numeric-control {
    font-family: var(--vpro-font-mono, monospace);
    font-variant-numeric: tabular-nums;
  }
  .paper-control:focus {
    outline: 2px solid var(--vpro-focus-ring);
    outline-offset: 1px;
  }
  .paper-control:disabled {
    color: var(--vpro-ink-muted);
    background: var(--vpro-surface-subtle);
  }
  .pending {
    opacity: 0.65;
  }
</style>
