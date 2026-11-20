<script lang="ts">
  import type {
    ProjectMetadataCell,
    ProjectMetadataCreate,
    ProjectMetadataEditorField,
    ProjectMetadataRow,
  } from '../../bindings/github.com/boostao/vpro/app';
  import type { ProjectMetadataReview } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
  import type { MetadataTemplateDraft } from './projectMetadataEditor';

  export interface MetadataCreationCatalog {
    templateFieldNames: readonly string[];
    templateLegendPrefix: string;
    blankNoticeText: string;
    cellText: (cell: ProjectMetadataCell) => string;
    labelFor: (name: string) => string;
    summaryFor: (review: ProjectMetadataReview | null, row: ProjectMetadataRow, master?: boolean) => string;
  }

  let {
    ready,
    busy,
    dirty,
    committedFailure,
    errorsCount,
    allowCreation,
    allowTemplateCreation,
    hasExistingRows,
    review,
    blank,
    template,
    available,
    catalog,
    onreviewblank,
    oncreateblank,
    onreviewtemplate,
    onstagetemplate,
    oncreatetemplate,
  }: {
    ready: boolean;
    busy: boolean;
    dirty: boolean;
    committedFailure: boolean;
    errorsCount: number;
    allowCreation: boolean;
    allowTemplateCreation: boolean;
    hasExistingRows: boolean;
    review: ProjectMetadataReview | null;
    blank: ProjectMetadataCreate | null;
    template: MetadataTemplateDraft | null;
    available: ProjectMetadataEditorField[];
    catalog: MetadataCreationCatalog;
    onreviewblank: () => void;
    oncreateblank: () => void;
    onreviewtemplate: (rowId: string) => void;
    onstagetemplate: (field: ProjectMetadataEditorField, raw: string, nullValue: boolean) => void;
    oncreatetemplate: () => void;
  } = $props();
</script>

{#if allowCreation && !hasExistingRows && !blank && !template}
  <button type="button" disabled={!ready || busy || dirty || committedFailure} onclick={onreviewblank}>
    Review blank metadata creation
  </button>
{/if}

{#if allowTemplateCreation && !hasExistingRows && !blank && !template}
  <fieldset disabled={!ready || busy || dirty || committedFailure}>
    <legend>Select one physical master template explicitly</legend>
    {#each review?.masterTemplates.rows ?? [] as row (row.rowId)}
      <button type="button" data-metadata-template={row.rowId} onclick={() => onreviewtemplate(row.rowId)}>
        Review master template {row.rowId}: {catalog.summaryFor(review, row, true)}
      </button>
    {:else}
      <p>No matching master templates. No first-row choice, identity assignment or template is inferred.</p>
    {/each}
  </fieldset>
{/if}

{#if template}
  <fieldset data-metadata-template-proposal>
    <legend>{catalog.templateLegendPrefix} {template.original.rowId}</legend>
    <p>
      Existing Project ID {JSON.stringify(template.review.projectId)} remains unchanged. Source timestamps require an explicit
      signed16 year or NULL; incompatible codes require literal text or NULL. No source value is silently converted. Unmapped
      fields and version/date stamps remain NULL. Only one record is created; all other master candidates remain untouched.
    </p>
    <div class="metadata-grid">
      {#each catalog.templateFieldNames as name (name)}
        {@const field = available.find((f) => f.name === name)}
        {@const cell = template.cells[name]}
        {@const index = template.review.masterTemplates.columns?.findIndex((column) => column.name === name) ?? -1}
        {@const source = template.original.cells?.[index]}
        {#if field && cell}
          <div
            class="metadata-field"
            class:wide={name === 'Notes' || name === 'FieldDataCollectionTeam' || name === 'ProjectPurpose'}
          >
            <label for={'metadata-template-' + name}>{catalog.labelFor(name)}</label>
            <p>
              Master source: {source?.storage === 'null'
                ? 'NULL'
                : source
                  ? `${source.storage}: ${JSON.stringify(catalog.cellText(source))}`
                  : 'Unavailable'}
            </p>
            {#if name === 'Notes'}
              <textarea
                id={'metadata-template-' + name}
                rows="4"
                value={cell.raw}
                disabled={!ready || busy || committedFailure || cell.nullValue}
                aria-invalid={cell.error !== null}
                oninput={(event) => onstagetemplate(field, event.currentTarget.value, false)}></textarea>
            {:else if field.collection}
              <select
                id={'metadata-template-' + name}
                value={cell.raw}
                disabled={!ready || busy || committedFailure || cell.nullValue}
                aria-invalid={cell.error !== null}
                onchange={(event) => onstagetemplate(field, event.currentTarget.value, false)}
              >
                {#if !['1', '2', '3'].includes(cell.raw)}
                  <option value={cell.raw}>Unresolved source {cell.raw || 'NULL'}</option>
                {/if}
                <option value="1">Complete</option>
                <option value="2">Partial</option>
                <option value="3">None</option>
              </select>
            {:else}
              <input
                id={'metadata-template-' + name}
                type="text"
                inputmode={field.kind === 'integer' ? 'numeric' : 'text'}
                list={field.referenceList ? 'metadata-template-options-' + name : undefined}
                value={cell.raw}
                disabled={!ready || busy || committedFailure || cell.nullValue}
                aria-invalid={cell.error !== null}
                oninput={(event) => onstagetemplate(field, event.currentTarget.value, false)}
              />
              {#if field.referenceList}
                <datalist id={'metadata-template-options-' + name}>
                  {#each field.options ?? [] as option, i (i)}
                    {#if option.value !== null}<option value={option.value}>{option.description ?? ''}</option>{/if}
                  {/each}
                </datalist>
              {/if}
            {/if}
            <label class="null-option" for={'metadata-template-null-' + name}>
              <input
                id={'metadata-template-null-' + name}
                type="checkbox"
                checked={cell.nullValue}
                disabled={!ready || busy || committedFailure}
                onchange={(event) => onstagetemplate(field, cell.raw, event.currentTarget.checked)}
              />
              Store NULL
            </label>
            {#if cell.error}<p class="failure">{cell.error}</p>{/if}
          </div>
        {/if}
      {/each}
    </div>
    <button type="button" disabled={!ready || busy || committedFailure || errorsCount > 0} onclick={oncreatetemplate}>
      Create reviewed template metadata record
    </button>
  </fieldset>
{/if}

{#if blank}
  <fieldset data-metadata-blank-proposal>
    <legend>Confirm one blank record for the existing parent identity</legend>
    <p>
      Project ID {JSON.stringify(blank.projectId)} is copied literally from the selected plot, never assigned to it.
      {catalog.blankNoticeText}
    </p>
    <button type="button" disabled={!ready || busy || committedFailure} onclick={oncreateblank}>
      Create reviewed blank metadata record
    </button>
  </fieldset>
{/if}

<style>
  fieldset {
    border: 1px solid var(--vpro-border);
    border-radius: 0.5rem;
    margin: 1rem 0;
    padding: 1rem;
    min-width: 0;
  }
  legend {
    font-weight: 600;
    padding: 0 0.4rem;
    color: var(--vpro-navy);
  }
  .metadata-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 18rem), 1fr));
    gap: 1rem;
  }
  .metadata-field {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
    min-width: 0;
  }
  .wide {
    grid-column: 1 / -1;
  }
  input:not([type='checkbox']),
  select,
  textarea {
    width: 100%;
    box-sizing: border-box;
    min-width: 0;
    min-height: 2.5rem;
    padding: 0.5rem;
    border: 1px solid var(--vpro-border-strong);
    border-radius: 0.35rem;
    font: inherit;
    color: var(--vpro-ink);
    background: var(--vpro-surface);
  }
  input:focus,
  select:focus,
  textarea:focus {
    outline: 2px solid var(--vpro-navy);
    outline-offset: 2px;
  }
  .null-option {
    font-size: 0.8rem;
  }
  button {
    padding: 0.5rem 0.75rem;
    border: 1px solid var(--vpro-border-strong);
    border-radius: 0.35rem;
    margin: 0.2rem;
    color: var(--vpro-navy);
    background: var(--vpro-surface);
    font-weight: 600;
  }
  button:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
  .failure {
    color: var(--vpro-error);
  }
</style>
