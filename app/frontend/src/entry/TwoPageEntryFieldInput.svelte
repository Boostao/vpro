<script lang="ts">
  import type { SIVIParentSharedReference } from '../../bindings/github.com/boostao/vpro/app/internal/sourceform/models';
  import type { EditorCloseState } from '../shell/closeLifecycle';
  import type { TwoPageParentForm } from './twoPageParentSession';
  import { twoPageParentCommonFields } from './twoPageParentCommonSession';
  import type { TwoPageEntryInput } from './twoPageEntryDraft';
  import { twoPageEntryCell, type TwoPageEntryView } from './twoPageEntrySession';
  import { metadataCellText } from '../admin/projectMetadataEditor';
  import { controlLabel, wideControl } from './formPresentation';
  import type { PaperControl } from './paperLayout';
  import CoordinateHelper from './CoordinateHelper.svelte';
  import { IS_WEB_READONLY } from '../web/runtimeMode';

  let {
    form,
    control,
    view,
    close,
    childBlocked,
    onstage,
    onselectproject,
    onacknowledge,
  }: {
    form: TwoPageParentForm;
    control: PaperControl;
    view: TwoPageEntryView;
    close: EditorCloseState;
    childBlocked: boolean;
    onstage: (column: string, input: TwoPageEntryInput) => void;
    onselectproject: (rowId: string | null) => void;
    onacknowledge: (column: string) => void;
  } = $props();

  let coordHelperOpen = $state(false);

  function referenceChoices(reference: SIVIParentSharedReference) {
    if (reference.choices === null) throw new Error(`${reference.column} reference lost its complete choice receipt.`);
    return reference.choices;
  }

  function twoPageHelpId(colLower: string): string {
    if (colLower === 'moistureregime') return 'site.moisture_regime';
    if (colLower === 'nutrientregime') return 'site.nutrient_regime';
    if (['zone', 'subzone', 'siteseries', 'becsiteunit', 'usersiteunit'].includes(colLower)) return 'site.bgc_zone';
    if (colLower === 'ecosection' || colLower === 'fsregiondistrict') return 'site.ecosection';
    if (['latitude', 'longitude', 'utmzone', 'utmeasting', 'utmnorthing'].includes(colLower)) return 'site.coordinates';
    if (colLower === 'elevation' || colLower === 'slopegradient' || colLower === 'aspect') return 'site.elevation';
    if (colLower === 'mesoslopeposition' || colLower === 'surfaceshape') return 'site.meso_slope';
    if (colLower.startsWith('substrate')) return 'site.substrate_cover';
    if (colLower === 'structuralstage' || colLower === 'successionalstatus') return 'site.successional_structural';
    if (colLower === 'realmclass' || colLower === 'snowcoverregime' || colLower === 'activelayerdepth')
      return 'site.realm_class';
    if (colLower === 'humusform') return 'humus.humus_form';
    if (
      ['rootingdepth', 'rootrestrictingtype', 'rootrestrictingdepth', 'seepagedepth', 'soildrainage'].includes(colLower)
    )
      return 'soil.rooting_seepage';
    return 'site.plot_number';
  }
</script>

{#if view.original && view.snapshot && control.column}
  {@const column = control.column}
  {@const helpId = twoPageHelpId(column.toLowerCase())}
  {@const policy = view.snapshot.Policies.find((field) => field.column === column)}
  {@const draft = view.drafts[column]}
  {@const originalCell = twoPageEntryCell(view.original, column)}
  {@const nullBlocked =
    (column === 'SV_FloodPlain' || column === 'SpeciesListComplete') && originalCell.storage !== 'null'}
  {@const value = draft?.value ?? originalCell}
  {@const raw =
    draft?.input.kind === 'text' ? draft.input.raw : value.storage === 'null' ? '' : metadataCellText(value)}
  {@const reference = view.snapshot.Fields.find((field) => field.column === column)}
  {@const id = `complete-entry-${column}`}
  {@const unavailable =
    IS_WEB_READONLY ||
    close.busy ||
    view.blocked ||
    (childBlocked && !draft) ||
    (column === 'BECSiteUnit' && !view.snapshot.MasterEditingAvailable)}
  <div
    class="min-w-0 space-y-1"
    data-two-page-entry-field={column}
    data-source-control={control.controlId}
    data-help-id={helpId}
  >
    <label class="block text-sm font-medium" for={id}>{controlLabel(control, true)}</label>
    {#if column === 'ProjectID'}
      <select
        {id}
        class="w-full rounded border p-2"
        value={view.projectRowId ?? ''}
        disabled={unavailable || !view.snapshot.ProjectAssignmentAvailable}
        onchange={(event) => onselectproject(event.currentTarget.value || null)}
      >
        <option value="">Keep original ({value.storage === 'null' ? 'NULL' : raw})</option>
        {#each view.snapshot.ProjectChoices.Choices.rows as row (row.rowId)}
          {@const code = row.cells[0]}
          {@const title = row.cells[1]}
          <option value={row.rowId} disabled={code.storage !== 'text' || !code.text || code.text.length > 30}>
            {metadataCellText(code)} — {title.storage === 'null'
              ? '(NULL title)'
              : title.text === ''
                ? '(empty title)'
                : metadataCellText(title)} [row {row.rowId}]
          </option>
        {/each}
      </select>
      {#if !view.snapshot.ProjectAssignmentAvailable}<p role="status" class="text-xs">
          {view.snapshot.ProjectAssignmentDiagnostic}
        </p>{/if}
    {:else if policy?.kind === 'boolean'}
      {@const selected =
        value.storage === 'null'
          ? ''
          : value.integer === '-1'
            ? 'true'
            : value.integer === '0'
              ? 'false'
              : 'historical'}
      <select
        {id}
        class="w-full rounded border p-2"
        value={selected}
        disabled={unavailable}
        onchange={(event) =>
          onstage(
            column,
            event.currentTarget.value === ''
              ? { kind: 'clear' }
              : { kind: 'boolean', value: event.currentTarget.value === 'true' }
          )}
      >
        <option value="" disabled={nullBlocked}
          >{column === 'SV_FloodPlain' || column === 'SpeciesListComplete' ? 'Retain historical NULL' : 'NULL'}</option
        >
        <option value="true">Yes</option>
        <option value="false">No</option>
        {#if selected === 'historical'}<option value="historical" disabled>Historical {raw}</option>{/if}
      </select>
    {:else if policy?.kind === 'option'}
      {@const selected =
        value.storage === 'null' ? '' : value.text === '1' || value.text === '2' ? value.text : 'historical'}
      {@const options = twoPageParentCommonFields(form).find((field) => field.column === column)?.options ?? []}
      <select
        {id}
        class="w-full rounded border p-2"
        value={selected}
        disabled={unavailable}
        onchange={(event) =>
          onstage(column, {
            kind: 'option',
            option: event.currentTarget.value === '' ? null : Number(event.currentTarget.value),
          })}
      >
        <option value="">NULL</option>
        {#each options as option}<option value={String(option.value)}>{option.label}</option>{/each}
        {#if selected === 'historical'}<option value="historical" disabled>Historical {raw}</option>{/if}
      </select>
    {:else if wideControl(control)}
      <textarea
        {id}
        class="w-full rounded border p-2"
        rows="3"
        value={raw}
        disabled={unavailable}
        aria-invalid={Boolean(draft?.error)}
        aria-describedby={draft?.error ? `${id}-error` : undefined}
        oninput={(event) => onstage(column, { kind: 'text', raw: event.currentTarget.value })}></textarea>
    {:else}
      <input
        {id}
        class="w-full rounded border p-2"
        type="text"
        value={raw}
        disabled={unavailable}
        list={reference?.available ? `${id}-choices` : undefined}
        aria-invalid={Boolean(draft?.error)}
        aria-describedby={draft?.error ? `${id}-error` : undefined}
        oninput={(event) => onstage(column, { kind: 'text', raw: event.currentTarget.value })}
      />
      {#if reference?.available}
        <datalist id={`${id}-choices`}>
          {#each referenceChoices(reference).filter((choice) => choice.selectable && choice.code !== null) as choice (JSON.stringify( [choice.rowId, choice.code, choice.description] ))}
            <option value={choice.code ?? ''}
              >{choice.description === null ? '(NULL description)' : choice.description}</option
            >
          {/each}
        </datalist>
      {/if}
    {/if}
    {#if !IS_WEB_READONLY && column !== 'ProjectID'}
      <div class="flex flex-wrap gap-2 text-xs">
        <button type="button" disabled={unavailable || nullBlocked} onclick={() => onstage(column, { kind: 'clear' })}
          >Clear to NULL</button
        >
        <button type="button" disabled={unavailable} onclick={() => onstage(column, { kind: 'original' })}
          >Keep original</button
        >
        {#if column === 'Latitude'}
          <button
            type="button"
            data-two-page-coord-toggle
            onclick={() => {
              coordHelperOpen = !coordHelperOpen;
            }}
          >
            {coordHelperOpen ? 'Close DD/DM/DMS/UTM' : 'Coordinate Modes (DM/DMS/UTM)'}
          </button>
        {/if}
      </div>
    {/if}
    {#if column === 'Latitude' && coordHelperOpen}
      <CoordinateHelper
        idPrefix="two-page"
        variant="two-page"
        disabled={unavailable}
        onApplyUTM={(projected) => {
          onstage('Latitude', { kind: 'text', raw: String(projected.latitude) });
          onstage('Longitude', { kind: 'text', raw: String(projected.longitude) });
          const snap = view.snapshot;
          if (snap?.Fields.some((f) => f.column === 'UTMZone'))
            onstage('UTMZone', { kind: 'text', raw: String(projected.zone) });
          if (snap?.Fields.some((f) => f.column === 'UTMEasting'))
            onstage('UTMEasting', { kind: 'text', raw: String(projected.easting) });
          if (snap?.Fields.some((f) => f.column === 'UTMNorthing'))
            onstage('UTMNorthing', { kind: 'text', raw: String(projected.northing) });
        }}
        onApplyAxis={(axis, dd) => {
          onstage(axis === 'latitude' ? 'Latitude' : 'Longitude', { kind: 'text', raw: String(dd) });
        }}
      />
    {/if}
    {#if column === 'SV_FloodPlain' || column === 'SpeciesListComplete'}
      <p class="text-xs">
        Source Yes/No converts NULL to No; choose No explicitly. Unchanged historical NULL is retained.
      </p>
    {/if}
    {#if draft?.error}<p id={`${id}-error`} role="alert" class="text-xs text-red-700">{draft.error}</p>{/if}
    {#if reference && !reference.available}<p role="status" class="text-xs">{reference.diagnostic}</p>{/if}
    {#if column === 'BECSiteUnit' && !view.snapshot.MasterEditingAvailable}
      <p role="status" class="text-xs">The owned current user is not authorized to change Master site units.</p>
    {/if}
    {#if view.advisories[column]}
      <p class="text-xs">{view.advisories[column]}</p>
      <button type="button" disabled={unavailable} onclick={() => onacknowledge(column)}
        >Acknowledge literal {column}</button
      >
    {/if}
  </div>
{/if}
