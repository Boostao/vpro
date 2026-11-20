<script lang="ts">
  import type { ProjectMetadataCell } from '../../bindings/github.com/boostao/vpro/app';
  import SoilReferenceChoices from './SoilReferenceChoices.svelte';
  import type { SoilReferenceView } from './twoPageSoilReferences';
  import { twoPageSoilCreationEnabled } from './twoPageSoilSessions';
  import {
    twoPageSoilKind,
    type TwoPageSoilForm,
    type TwoPageSoilOriginal,
    type TwoPageSoilDrafts,
  } from './twoPageSoilEditor';
  import { metadataCellText } from '../admin/projectMetadataEditor';
  import { soilFields } from './soilChildEditor';
  import {
    twoPageSoilGroups,
    twoPageSoilCell,
    twoPageSoilStoredText,
    type twoPageSoilDepthOrder,
  } from './twoPageSoilPresentation';

  let {
    state: s,
    handlers: h,
  }: {
    state: {
      plot: string;
      form: TwoPageSoilForm;
      original: TwoPageSoilOriginal | null;
      depthOrder: ReturnType<typeof twoPageSoilDepthOrder> | null;
      row: { rowId: string } | undefined;
      diagnostic: string | null;
      drafts: TwoPageSoilDrafts;
      receiptCount: number;
      fieldsDisabled: boolean;
      referenceView: SoilReferenceView;
    };
    handlers: {
      onselectrow: (rowId: string) => void;
      onenterrecord: (event: KeyboardEvent, column: string) => void;
      onstage: (column: string, raw: string, nullValue: boolean) => void;
      onchoosereference: (column: string, plannedRow: string, definitionId: string, value: ProjectMetadataCell) => void;
    };
  } = $props();

  function soilHelpId(soilForm: TwoPageSoilForm, column: string): string {
    const lower = column.toLowerCase();
    if (soilForm === 'SoilHumusXL') {
      if (lower === 'horizon') return 'humus.horizon';
      if (lower === 'upperdepth' || lower === 'lowerdepth') return 'humus.upper_lower_depth';
      if (lower === 'vonpost') return 'humus.von_post';
      return 'humus.humus_form';
    }
    if (lower === 'horizon' || lower === 'upperdepth' || lower === 'lowerdepth') return 'mineral.horizon';
    return 'mineral.texture_cf';
  }
</script>

{#if s.original}
  {@const original = s.original}
  {#if s.depthOrder?.diagnostic}<p role="alert">{s.depthOrder.diagnostic}</p>
  {:else}<p role="status">{s.depthOrder?.status}</p>{/if}
  <div class="flex flex-wrap gap-2" aria-label={`${s.form} physical rows`}>
    {#each s.depthOrder?.rows ?? [] as physical (physical.rowId)}
      <button
        type="button"
        class="min-w-0 break-words rounded border p-2 text-left"
        aria-pressed={s.row?.rowId === physical.rowId}
        onclick={() => h.onselectrow(physical.rowId)}
      >
        Horizon {original.records.columns.some((column) => column.name === 'Horizon')
          ? twoPageSoilStoredText(original, physical.rowId, 'Horizon')
          : '(source column unavailable)'}; Depth Up {original.records.columns.some(
          (column) => column.name === 'UpperDepth'
        )
          ? twoPageSoilStoredText(original, physical.rowId, 'UpperDepth')
          : '(source column unavailable)'}; ID {twoPageSoilStoredText(original, physical.rowId, 'ID')}; physical row {physical.rowId}
      </button>
    {:else}<p role="status">
        No physical soil records for this exact parent.{twoPageSoilCreationEnabled
          ? ' Use the explicit New horizon action.'
          : ' Creation is unavailable.'}
      </p>{/each}
  </div>
  {#if s.row}
    {@const row = s.row}
    <p class="break-words text-sm">
      Application ID {twoPageSoilStoredText(original, row.rowId, 'ID')}; physical row {row.rowId}; parent {s.plot}
    </p>
    {#if s.diagnostic}<p role="alert">{s.diagnostic}</p>{/if}
    {#each twoPageSoilGroups[twoPageSoilKind(s.form)] as group}
      <fieldset class="min-w-0 rounded border p-3">
        <legend class="text-sm font-semibold">{group.label}</legend>
        <div class="grid min-w-0 grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3">
          {#each group.fields as [column, label]}
            {@const index = original.records.columns.findIndex((field) => field.name === column)}
            {#if index >= 0}
              {@const source = twoPageSoilCell(original, row.rowId, column)}
              {@const draft = s.drafts[JSON.stringify([row.rowId, column])]}
              {@const raw = draft?.raw ?? (source.storage === 'null' ? '' : metadataCellText(source))}
              {@const nullValue = draft?.nullValue ?? source.storage === 'null'}
              {@const id = `${s.form}-${row.rowId}-${column}`}
              {@const memo =
                soilFields[twoPageSoilKind(s.form)].find((field) => field.column === column)?.kind === 'memo'}
              {@const reference = s.referenceView.data?.fields.find((field) => field.column === column)}
              {@const plannedRow = row.rowId}
              <div
                class={`min-w-0 space-y-1 ${memo ? 'sm:col-span-2' : ''}`}
                data-soil-column={column}
                data-help-id={soilHelpId(s.form, column)}
              >
                <label class="block text-sm font-medium" for={id}>{label}</label>
                {#if memo}
                  <textarea
                    {id}
                    class="w-full min-w-0 rounded border p-2"
                    rows="3"
                    value={nullValue ? '' : raw}
                    disabled={s.fieldsDisabled}
                    placeholder={nullValue ? 'NULL' : undefined}
                    aria-invalid={!!draft?.error}
                    aria-describedby={draft?.error ? `${id}-error` : undefined}
                    onkeydown={(event) => h.onenterrecord(event, column)}
                    oninput={(event) => h.onstage(column, event.currentTarget.value, false)}></textarea>
                {:else}
                  <input
                    {id}
                    class="w-full min-w-0 rounded border p-2"
                    type="text"
                    value={nullValue ? '' : raw}
                    disabled={s.fieldsDisabled}
                    placeholder={nullValue ? 'NULL' : undefined}
                    aria-invalid={!!draft?.error}
                    aria-describedby={draft?.error ? `${id}-error` : undefined}
                    onkeydown={(event) => h.onenterrecord(event, column)}
                    oninput={(event) => h.onstage(column, event.currentTarget.value, false)}
                  />
                {/if}
                <label class="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    checked={nullValue}
                    disabled={s.fieldsDisabled}
                    onchange={(event) => h.onstage(column, raw, event.currentTarget.checked)}
                  />
                  {label}: NULL (not empty text)
                </label>
                {#if draft?.error}<p id={`${id}-error`} role="alert" class="text-sm text-red-700">{draft.error}</p>{/if}
                {#if !draft}<p class="text-xs text-vpro-ink-secondary">Stored {source.storage}</p>{/if}
                {#if reference}<SoilReferenceChoices
                    field={reference}
                    {label}
                    disabled={s.fieldsDisabled}
                    onchoose={(definitionId, value) => h.onchoosereference(column, plannedRow, definitionId, value)}
                  />{/if}
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
    {s.receiptCount} immutable committed soil receipt(s) retained across remounts.
  </p>{/if}
<p class="text-xs text-vpro-ink-secondary">
  LMH25 pedon horizon editor: upland L/F/H depths measure upward from 0 cm; wetland Of/Om/Oh and mineral A/B/C/R/W
  measure downward. Press Enter to move to the next horizon without auto-saving; use Save to commit changes, or New
  horizon / Delete to manage child rows while preserving permanent IDs.
</p>
