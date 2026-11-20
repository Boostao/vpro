<script lang="ts">
  import {
    vegetationColumnIndex,
    type TwoPageVegetationForm,
    type TwoPageVegetationOriginal,
  } from './twoPageVegetationWire';
  import type { TwoPageVegetationDrafts } from './twoPageVegetationEditor';
  import type { VegetationReferences } from './twoPageVegetationReferences';
  import type { vegetationSpeciesListOptions } from './twoPageVegetationSpeciesList';
  import { metadataCellText } from '../admin/projectMetadataEditor';
  import {
    twoPageVegetationGroups,
    twoPageVegetationStoredText,
    twoPageVegetationHasColumn,
  } from './twoPageVegetationPresentation';
  import VegetationSpeciesReferences from './VegetationSpeciesReferences.svelte';

  let {
    state: s,
    handlers: h,
  }: {
    state: {
      plot: string;
      form: TwoPageVegetationForm;
      original: TwoPageVegetationOriginal | null;
      selected: string | null;
      row: TwoPageVegetationOriginal['records']['rows'][number] | undefined;
      diagnostic: string | null;
      busy: boolean;
      fieldsDisabled: boolean;
      drafts: TwoPageVegetationDrafts;
      receiptCount: number;
      references: VegetationReferences | null;
      speciesListAvailable: boolean;
      speciesOptions: ReturnType<typeof vegetationSpeciesListOptions>;
      speciesWarningUnavailable: boolean;
    };
    handlers: {
      onselectrow: (rowId: string) => void;
      onpickspecies: (plannedRow: string, event: Event) => void;
      onenterrecord: (event: KeyboardEvent, column: string) => void;
      onstage: (column: string, raw: string, nullValue: boolean) => void;
      oncyclecollected: (plannedRow: string, event: MouseEvent) => void;
    };
  } = $props();
</script>

{#if s.original}
  {@const original = s.original}
  <div class="flex flex-wrap gap-2" aria-label={`${s.form} complete physical rows`}>
    {#each original.records.rows as physical (physical.rowId)}
      <button
        type="button"
        class="min-w-0 break-words rounded border p-2 text-left"
        aria-pressed={s.row?.rowId === physical.rowId}
        disabled={s.busy}
        onclick={() => h.onselectrow(physical.rowId)}
      >
        Species {twoPageVegetationHasColumn(original, 'Species')
          ? twoPageVegetationStoredText(original, physical.rowId, 'Species')
          : '(source column unavailable)'}; ID {twoPageVegetationStoredText(original, physical.rowId, 'ID')}; physical
        row {physical.rowId};
        {original.sourceRowIds.includes(physical.rowId) ? 'in source query' : 'physical only, read only'}
      </button>
    {:else}<p role="status">No physical vegetation records for this exact parent. Creation is unavailable.</p>{/each}
  </div>
  {#if s.selected !== null && !s.row}<p role="alert">
      Selected physical row {s.selected} is no longer observed. Choose an existing physical row explicitly.
    </p>{/if}
  {#if s.row}
    {@const row = s.row}
    <p class="break-words text-sm">
      Application ID {twoPageVegetationStoredText(original, row.rowId, 'ID')}; physical row {row.rowId}; parent {s.plot}
    </p>
    {#if s.diagnostic}<p role="alert">{s.diagnostic}</p>{/if}
    <p class="break-words text-sm">
      Species (read only): {twoPageVegetationHasColumn(original, 'Species')
        ? twoPageVegetationStoredText(original, row.rowId, 'Species')
        : '(source column unavailable)'}
    </p>
    {#if s.speciesListAvailable && twoPageVegetationHasColumn(original, 'Species')}
      {@const speciesDraft = s.drafts[JSON.stringify([row.rowId, 'Species'])]}
      {@const speciesId = `${s.form}-${row.rowId}-Species-list`}
      {@const plannedRow = row.rowId}
      <div class="min-w-0 space-y-1" data-vegetation-column="Species">
        <label class="block text-sm font-medium" for={speciesId}>Species: existing list selection</label>
        <select
          id={speciesId}
          class="w-full min-w-0 rounded border p-2"
          value={speciesDraft?.raw ?? ''}
          disabled={s.fieldsDisabled || s.speciesWarningUnavailable || !s.references || !s.speciesOptions.length}
          aria-invalid={!!speciesDraft?.error}
          aria-describedby={speciesDraft?.error ? `${speciesId}-error` : undefined}
          onchange={(event) => h.onpickspecies(plannedRow, event)}
        >
          <option value="">Select an exact existing list code</option>
          {#each s.speciesOptions as option (`${option.role}:${option.rowId}`)}
            <option value={option.code}
              >{option.code} | {option.cells[1].storage === 'null' ? 'NULL' : JSON.stringify(option.cells[1].text)} | {option
                .cells[4].text} | {option.cells[2].integer} | {option.cells[3].storage === 'null'
                ? 'NULL'
                : JSON.stringify(option.cells[3].text)} | {option.role} row {option.rowId}</option
            >
          {/each}
        </select>
        {#if speciesDraft?.error}<p id={`${speciesId}-error`} role="alert" class="text-sm text-red-700">
            {speciesDraft.error}
          </p>{/if}
        {#if s.speciesWarningUnavailable}<p role="status" class="text-sm">
            Species selection is unavailable: all seven original common covers are NULL; the source warning/advance
            route is not qualified.
          </p>{/if}
        {#if !s.references}<p role="status" class="text-sm">
            Review physical Species definitions before selecting a list code.
          </p>
        {:else if !s.speciesOptions.length}<p role="status" class="text-sm">
            No qualified exact A/CHARS list codes are available.
          </p>{/if}
      </div>
    {/if}
    {#each twoPageVegetationGroups(s.form) as group}
      <fieldset class="min-w-0 rounded border p-3">
        <legend class="text-sm font-semibold">{group.label}</legend>
        <div class="grid min-w-0 grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3">
          {#each group.fields as [column, label]}
            {#if twoPageVegetationHasColumn(original, column)}
              {@const source = row.cells[vegetationColumnIndex(original, column)]}
              {@const draft = s.drafts[JSON.stringify([row.rowId, column])]}
              {@const raw = draft?.raw ?? (source.storage === 'null' ? '' : metadataCellText(source))}
              {@const nullValue = draft?.nullValue ?? source.storage === 'null'}
              {@const id = `${s.form}-${row.rowId}-${column}`}
              {@const plannedRow = row.rowId}
              <div class="min-w-0 space-y-1 focus-within:bg-vpro-gold-surface" data-vegetation-column={column}>
                <label class="block text-sm font-medium" for={id}>{label}</label>
                <input
                  {id}
                  class="w-full min-w-0 rounded border border-vpro-border p-2"
                  type="text"
                  value={nullValue ? '' : raw}
                  disabled={s.fieldsDisabled}
                  placeholder={nullValue ? 'NULL' : undefined}
                  aria-invalid={!!draft?.error}
                  aria-describedby={draft?.error ? `${id}-error` : undefined}
                  onkeydown={(event) => h.onenterrecord(event, column)}
                  oninput={(event) => h.onstage(column, event.currentTarget.value, false)}
                />
                <label class="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    checked={nullValue}
                    disabled={s.fieldsDisabled}
                    onchange={(event) => h.onstage(column, raw, event.currentTarget.checked)}
                  />
                  {label}: NULL (not empty text)
                </label>
                {#if draft?.error}<p id={`${id}-error`} role="alert" class="text-sm text-vpro-error">
                    {draft.error}
                  </p>{/if}
                {#if !draft}<p class="text-xs text-vpro-ink-muted">Stored {source.storage}</p>{/if}
                {#if column === 'Collected'}
                  <button
                    type="button"
                    disabled={s.fieldsDisabled ||
                      !!draft?.error ||
                      ((draft?.value ?? source).storage !== 'null' && (draft?.value ?? source).storage !== 'text')}
                    onclick={(event) => h.oncyclecollected(plannedRow, event)}>Cycle Collected: NULL / C / V</button
                  >
                  <p class="text-xs text-vpro-ink-muted">C = Collected; V = Verified. Manual values remain distinct.</p>
                {/if}
              </div>
            {:else}<p role="alert">Source field {column} unavailable; row is read only.</p>{/if}
          {/each}
        </div>
      </fieldset>
    {/each}
  {/if}
{/if}
{#each Object.values(s.drafts).filter((draft) => draft.error && draft.rowId !== s.row?.rowId) as draft}
  <p role="alert">Physical row {draft.rowId}, {draft.column}: {draft.error}. Select that row to correct it or Undo.</p>
{/each}
{#if s.receiptCount}<p role="status">
    {s.receiptCount} immutable committed vegetation receipt(s) retained across remounts.
  </p>{/if}
{#if s.references}<VegetationSpeciesReferences references={s.references} />{/if}
<p class="text-xs text-vpro-ink-muted">
  LMH25 2-Page vegetation strata &amp; species editor: cover values validate against calibrated single-precision (&lt;
  100%) bounds while leaving untouched historical values intact. Save commits species, cover, and voucher changes
  atomically.
</p>
