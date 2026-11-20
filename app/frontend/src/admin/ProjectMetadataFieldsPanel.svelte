<script lang="ts">
  import type {
    ProjectMetadataCell,
    ProjectMetadataEditorField,
    ProjectMetadataRow,
  } from '../../bindings/github.com/boostao/vpro/app';
  import type { ProjectMetadataReview } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
  import type { MetadataDraft } from './projectMetadataEditor';
  import type { MetadataGroup } from './projectMetadataPresentation';

  export interface MetadataFieldsCatalog {
    groups: readonly MetadataGroup[];
    standardDefaults: Readonly<Record<string, string>>;
    fieldValue: (
      draft: MetadataDraft,
      field: ProjectMetadataEditorField
    ) => { raw: string; nullValue: boolean; error: string | null };
    cellText: (cell: ProjectMetadataCell) => string;
    labelFor: (name: string) => string;
  }

  let {
    ready,
    busy,
    committedFailure,
    standardDecision,
    standardPreview = $bindable(false),
    draft,
    review,
    available,
    catalog,
    onstage,
    onpopulatestandard,
    ontogglestandardkeep,
  }: {
    ready: boolean;
    busy: boolean;
    committedFailure: boolean;
    standardDecision: boolean;
    standardPreview?: boolean;
    draft: MetadataDraft | null;
    review: ProjectMetadataReview | null;
    available: ProjectMetadataEditorField[];
    catalog: MetadataFieldsCatalog;
    onstage: (field: ProjectMetadataEditorField, raw: string, nullValue: boolean) => void;
    onpopulatestandard: () => void;
    ontogglestandardkeep: (keep: boolean) => void;
  } = $props();
</script>

{#if draft}
  <p>
    Physical ID {draft.id}; immutable Project ID {JSON.stringify(draft.review.projectId)}. Unchanged historical values
    are omitted from Save.
  </p>
  {#if standardDecision}
    <label class="decision">
      <input
        type="checkbox"
        data-metadata-standard-keep
        disabled={!ready || busy || committedFailure}
        checked={draft.standardPopulation === 'keep'}
        onchange={(event) => ontogglestandardkeep(event.currentTarget.checked)}
      />
      Use current field drafts without further source population.
    </label>
    <button type="button" disabled={!ready || busy || committedFailure} onclick={() => (standardPreview = true)}>
      Review 24 source defaults
    </button>
    {#if draft.standardPopulation === 'populate'}
      <p>Source defaults were explicitly staged; they remain editable drafts until Save.</p>
    {/if}
  {/if}
  {#if standardPreview}
    <fieldset data-metadata-standard-preview>
      <legend>Confirm replacement of these 24 canonical LMH25 (NAD83) field drafts</legend>
      <p>
        No data has been saved. Apply replaces the listed current drafts, including their raw errors; all other drafts
        remain unchanged.
      </p>
      <dl>
        {#each Object.entries(catalog.standardDefaults) as [name, value] (name)}
          {@const field = available.find((f) => f.name === name)}
          <dt>{catalog.labelFor(name)}</dt>
          <dd>
            Current: {field
              ? catalog.fieldValue(draft, field).nullValue
                ? 'NULL'
                : JSON.stringify(catalog.fieldValue(draft, field).raw)
              : 'Unavailable'}; proposed: {JSON.stringify(value)}
          </dd>
        {/each}
      </dl>
      <button type="button" disabled={!ready || busy || committedFailure} onclick={onpopulatestandard}>
        Apply 24 source defaults to drafts
      </button>
      <button type="button" disabled={busy} onclick={() => (standardPreview = false)}>
        Cancel source-default preview
      </button>
    </fieldset>
  {/if}
  {#each catalog.groups as group (group.title)}
    <fieldset>
      <legend>{group.title}</legend>
      <div class="metadata-grid">
        {#each group.names as name (name)}
          {@const field = available.find((f) => f.name === name)}
          {#if field}
            {@const cell = catalog.fieldValue(draft, field)}
            <div
              class="metadata-field"
              class:wide={name === 'Notes' || name === 'FieldDataCollectionTeam' || name === 'ProjectPurpose'}
            >
              <label for={'metadata-' + name}>{catalog.labelFor(name)}</label>
              {#if name === 'Notes'}
                <textarea
                  id={'metadata-' + name}
                  data-metadata-column={name}
                  rows="4"
                  value={cell.raw}
                  disabled={!ready || busy || committedFailure || cell.nullValue}
                  aria-invalid={cell.error !== null}
                  oninput={(event) => onstage(field, event.currentTarget.value, false)}></textarea>
              {:else if field.collection}
                <select
                  id={'metadata-' + name}
                  data-metadata-column={name}
                  value={cell.raw}
                  disabled={!ready || busy || committedFailure || cell.nullValue}
                  aria-invalid={cell.error !== null}
                  onchange={(event) => onstage(field, event.currentTarget.value, false)}
                >
                  {#if !['1', '2', '3'].includes(cell.raw)}
                    <option value={cell.raw}>Historical {cell.raw || 'NULL'} (unchanged only)</option>
                  {/if}
                  <option value="1">Complete</option>
                  <option value="2">Partial</option>
                  <option value="3">None</option>
                </select>
              {:else}
                <input
                  id={'metadata-' + name}
                  data-metadata-column={name}
                  type="text"
                  inputmode={field.kind === 'integer' ? 'numeric' : 'text'}
                  list={field.referenceList ? 'metadata-options-' + name : undefined}
                  value={cell.raw}
                  disabled={!ready || busy || committedFailure || cell.nullValue}
                  aria-invalid={cell.error !== null}
                  oninput={(event) => onstage(field, event.currentTarget.value, false)}
                />
                {#if field.referenceList}
                  <datalist id={'metadata-options-' + name}>
                    {#each field.options ?? [] as option (option.rowId)}
                      {#if option.value !== null}
                        <option value={option.value} label={option.description ?? option.value}></option>
                      {/if}
                    {/each}
                  </datalist>
                {/if}
              {/if}
              <label class="null-control" for={'metadata-null-' + name}>
                <input
                  id={'metadata-null-' + name}
                  type="checkbox"
                  checked={cell.nullValue}
                  disabled={!ready || busy || committedFailure}
                  onchange={(event) => onstage(field, cell.raw, event.currentTarget.checked)}
                />
                Store NULL, not an empty value
              </label>
              {#if cell.error}<p class="failure">{cell.error}</p>{/if}
            </div>
          {/if}
        {/each}
      </div>
    </fieldset>
  {/each}
  <fieldset>
    <legend>Immutable identity and source-managed stamps</legend>
    <dl>
      {#each ['ID', 'ProjectID', 'AllSpecs', 'TableOfLists', 'DateLastEdited'] as name}
        {@const index = draft.review.projectRecords.columns?.findIndex((column) => column.name === name) ?? -1}
        <dt>{name}</dt>
        <dd>
          {draft.original.cells?.[index]?.storage === 'null'
            ? 'NULL'
            : draft.original.cells?.[index]
              ? catalog.cellText(draft.original.cells[index])
              : 'Unavailable'}
        </dd>
      {/each}
    </dl>
  </fieldset>
{/if}

<details>
  <summary>Original master templates (read-only; no automatic conversion)</summary>
  {#each review?.masterTemplates.rows ?? [] as row (row.rowId)}
    <h3>Master physical row {row.rowId}</h3>
    <dl>
      {#each review?.masterTemplates.columns ?? [] as column, index}
        <dt>{column.name}</dt>
        <dd>
          {row.cells?.[index]?.storage}: {row.cells?.[index]
            ? catalog.cellText(row.cells[index]) || (row.cells[index].storage === 'null' ? 'NULL' : 'Empty text')
            : 'Unavailable'}
        </dd>
      {/each}
    </dl>
  {:else}
    <p>No matching master templates.</p>
  {/each}
</details>

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
  .null-control {
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
  .decision {
    display: block;
    background: var(--vpro-warning-bg);
    border-left: 4px solid var(--vpro-gold);
    padding: 0.75rem;
    color: var(--vpro-ink);
  }
  dl {
    display: grid;
    grid-template-columns: minmax(8rem, 1fr) 2fr;
    gap: 0.5rem;
    overflow-wrap: anywhere;
  }
  dt {
    font-weight: 600;
  }
  @media (max-width: 600px) {
    dl {
      grid-template-columns: 1fr;
    }
  }
</style>
