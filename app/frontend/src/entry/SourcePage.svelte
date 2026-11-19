<script lang="ts">
  import type { Snippet } from 'svelte';
  import { accessCaption, paperPage, type PaperControl, type VegetationMode } from './paperLayout';
  import { controlColumnSpan, controlLabel, groupCardZone, isUnmigratedStubControl, presentationGroups, wideControl } from './formPresentation';
  type Editor = { columns: readonly string[]; controls?: readonly string[]; input: Snippet<[PaperControl, string]>; labelled?: boolean };
  let { name, sourcePage, embedded, values = new Map<string, unknown>(), vegetationMode = 'initial', onHeightToggle, heightToggleDisabled = false, onSpeciesCheck, speciesCheckDisabled = true, onFindPlot, findPlotDisabled = true, editor, editors = [] }: {
    name: string; embedded: Snippet<[PaperControl]>; values?: Map<string, unknown>;
    sourcePage?: ReturnType<typeof paperPage>;
    vegetationMode?: VegetationMode; onHeightToggle?: () => void; heightToggleDisabled?: boolean;
    onSpeciesCheck?: () => void; speciesCheckDisabled?: boolean;
    onFindPlot?: () => void; findPlotDisabled?: boolean;
    editor?: Editor; editors?: readonly Editor[];
  } = $props();
  const page = $derived(sourcePage ?? paperPage(name, vegetationMode));
  const activeEditors = $derived.by(() => {
    const slots = editor ? [editor, ...editors] : editors;
    const columns = new Set<string>();
    const controls = new Set<string>();
    for (const slot of slots) {
      for (const column of slot.columns) {
        if (columns.has(column)) throw new Error(`Multiple source editors own ${column}.`);
        columns.add(column);
      }
      for (const control of slot.controls ?? []) {
        if (controls.has(control)) throw new Error(`Multiple source editors own control ${control}.`);
        const source = page.controls.find(member => member.controlId === control);
        if (source?.column) throw new Error(`Bound source control ${control} must be owned by its column.`);
        if (source && ['CommandButton', 'ToggleButton', 'Subform'].includes(source.type)) {
          throw new Error(`Source action ${control} cannot be owned by a field editor.`);
        }
        controls.add(control);
      }
    }
    return slots;
  });
  const sections = $derived(presentationGroups(name, page.controls));
</script>

<div class="responsive-form" data-source-page={name}>
  {#each sections as section (section.title)}
    {@const allStubs = section.controls.length > 0 && section.controls.every(control => isUnmigratedStubControl(control))}
    <fieldset class="form-group" class:unmigrated-group={allStubs} data-card-zone={groupCardZone(name, section.title)} data-group-title={section.title}>
      <legend>{section.title}</legend>
      <div class="field-grid">
        {#each section.controls as control (control.controlId)}
          {@const column = control.column}
          {@const label = controlLabel(control, Boolean(sourcePage))}
          {@const span = controlColumnSpan(name, section.title, control)}
          {@const stub = isUnmigratedStubControl(control)}
          {@const fieldEditor = column ? activeEditors.find(slot => slot.columns.includes(column)) :
            activeEditors.find(slot => slot.controls?.includes(control.controlId))}
          {@const stored = column ? values.get(column.toLowerCase()) : undefined}
          {#if control.type === 'Subform'}
            <div class="form-field full-width embedded" data-col-span={span} data-source-control={control.controlName}>
              {@render embedded(control)}
            </div>
          {:else if control.type === 'CommandButton' || control.type === 'ToggleButton'}
            <div class="form-field action-field" class:unmigrated-source-stub={stub} data-col-span={span}>
              {#if control.controlName === 'btnCoverAndHeight' && onHeightToggle}
                <button type="button" data-source-control={control.controlName} disabled={heightToggleDisabled} aria-pressed={vegetationMode === 'height'} onclick={onHeightToggle}>{accessCaption(control.caption)}</button>
              {:else if control.controlName === 'btnCheckSppCodes' && onSpeciesCheck}
                <button type="button" data-source-control={control.controlName} disabled={speciesCheckDisabled} onclick={onSpeciesCheck}>{label}</button>
              {:else if control.controlName === 'btnFindPlot' && onFindPlot}
                <button type="button" data-source-control={control.controlName} disabled={findPlotDisabled} onclick={onFindPlot}>{label}</button>
              {:else if control.controlName === 'btnAllowSmallEntry'}
                <button type="button" disabled title="Small-entry cover precision (<1%) is always enabled in VPro 2.0" data-source-control={control.controlName}>{label}</button>
              {:else}
                <button type="button" disabled title="Legacy Access paper-form action; use the corresponding VPro 2.0 toolbar workflow" data-source-control={control.controlName}>{label}</button>
              {/if}
            </div>
          {:else if fieldEditor?.labelled}
            <div class="form-field" class:full-width={wideControl(control)} class:unmigrated-source-stub={stub} data-col-span={span}>
              {@render fieldEditor.input(control, 'box-sizing:border-box;width:100%;min-width:0;min-height:40px;font:inherit;')}
            </div>
          {:else}
            <label class={`form-field col-span-${span}${wideControl(control) ? ' full-width' : ''}${stub ? ' unmigrated-source-stub' : ''}`}>
              <span class="field-label">{label}</span>
              {#if fieldEditor}
                {@render fieldEditor.input(control, 'box-sizing:border-box;width:100%;min-width:0;min-height:40px;font:inherit;')}
              {:else if control.type === 'CheckBox' || control.type === 'OptionButton'}
                <input data-column={column} data-source-control={control.controlName} type={control.type === 'OptionButton' ? 'radio' : 'checkbox'}
                  checked={stored === true || Boolean(sourcePage) && control.type === 'CheckBox' && (stored === -1 || stored === '-1')}
                  disabled aria-label={label} />
                {#if sourcePage && control.type === 'CheckBox' && stored != null && stored !== true && stored !== false
                  && stored !== 0 && stored !== '0' && stored !== -1 && stored !== '-1'}
                  <span class="text-xs text-vpro-ink-secondary">Historical {String(stored)}</span>
                {/if}
              {:else if control.type === 'TextBox' || control.type === 'ComboBox' || control.type === 'OptionGroup'}
                {#if wideControl(control)}
                  <textarea data-column={column} data-source-control={control.controlName} disabled value={typeof stored === 'string' ? stored : ''} placeholder={stored !== undefined ? '' : 'Pending'} aria-label={label} rows="3"></textarea>
                {:else}
                  <input data-column={column} data-source-control={control.controlName} disabled value={typeof stored === 'string' || typeof stored === 'number' ? stored : ''} placeholder={stored !==undefined ? '' : 'Pending'} aria-label={label} />
                {/if}
              {/if}
            </label>
          {/if}
        {/each}
        {#if name === 'Veg Other'}
          <details class="form-group veg-other-legend">
            <summary>Column legend</summary>
            <ul>
              {#each page.controls.filter(control => control.type === 'Label') as control (control.controlId)}
                <li>{accessCaption(control.caption)}</li>
              {/each}
            </ul>
          </details>
        {/if}
      </div>
    </fieldset>
  {/each}
</div>

<style>
  .responsive-form { display: grid; grid-template-columns: repeat(12, minmax(0, 1fr)); gap: .85rem; align-items: start; grid-auto-flow: row dense; }
  .form-group { grid-column: 1 / -1; margin: 0; border-color: var(--vpro-border); border-top: 3px solid var(--vpro-gold); background: var(--vpro-surface); }
  .form-group :global(legend) { color: var(--vpro-navy); }
  .veg-other-legend { grid-column: 1 / -1; margin-top: .5rem; }
  .unmigrated-source-stub, .unmigrated-group { display: none; }
  @container fs882-fields (min-width: 960px) {
    .form-group[data-card-zone="quad-left"] { grid-column: 1 / 7; }
    .form-group[data-card-zone="quad-right"] { grid-column: 7 / 13; }
    .form-group[data-card-zone="top-band"] { grid-column: span 6; }
    .form-group[data-group-title="Identity and survey"] { grid-column: 1 / 9; }
    .form-group[data-group-title="Project"] { grid-column: 9 / 13; }
    .form-group[data-group-title="Survey"] { grid-column: 1 / 5; }
    .form-group[data-group-title="Geology"] { grid-column: 5 / 13; }
    .form-group[data-card-zone="full"] { grid-column: 1 / -1; }
    .responsive-form[data-source-page="Vegetation"] .form-group[data-card-zone="quad-left"] { grid-column: 1 / 6; }
    .responsive-form[data-source-page="Vegetation"] .form-group[data-card-zone="quad-right"] { grid-column: 6 / 13; }
  }
  @container fs882-fields (min-width: 901px) {
    .form-field[data-col-span="2"], .form-field:global(.col-span-2) { grid-column: span 2; }
    .form-field[data-col-span="3"], .form-field:global(.col-span-3) { grid-column: span 3; }
    .form-field[data-col-span="4"], .form-field:global(.col-span-4) { grid-column: span 4; }
    .form-field[data-col-span="6"], .form-field:global(.col-span-6) { grid-column: span 6; }
    .form-field[data-col-span="12"], .form-field:global(.col-span-12) { grid-column: 1 / -1; }
  }
</style>
