<script lang="ts">
  import type { Snippet } from 'svelte';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import type { PictureReview } from './pictureRead';

  type PictureRow = PictureReview['records']['rows'][number];
  type PictureCell = PictureRow['cells'][number];

  let {
    review,
    selected,
    row,
    view = 'child',
    disabled = false,
    busy = false,
    metadataPending = false,
    lifecyclePending = false,
    hasMetadataSession = false,
    cellLabel,
    onSelect,
    onPreview,
    onEditMetadata,
    onReviewDeletion,
    children,
  }: {
    review: PictureReview | null;
    selected: string;
    row: PictureRow | undefined;
    view?: 'child' | 'manager';
    disabled?: boolean;
    busy?: boolean;
    metadataPending?: boolean;
    lifecyclePending?: boolean;
    hasMetadataSession?: boolean;
    cellLabel: (cell: PictureCell) => string;
    onSelect: (rowId: string) => void;
    onPreview: () => void;
    onEditMetadata: () => void;
    onReviewDeletion: () => void;
    children?: Snippet;
  } = $props();
</script>

{#if review}
  {#if review.records.rows.length === 0}
    <p>No linked picture metadata for this literal plot.</p>
  {:else}
    <label for="picture-record">Linked picture record</label>
    <select
      id="picture-record"
      value={selected}
      disabled={busy || disabled || metadataPending || lifecyclePending}
      onchange={(event) => onSelect(event.currentTarget.value)}
    >
      {#each review.records.rows as item (item.rowId)}
        <option value={item.rowId}>
          {cellLabel(item.cells[2])} — ID {cellLabel(item.cells[0])}; physical row {item.rowId}
        </option>
      {/each}
    </select>
    {#if row}
      <dl class="metadata">
        <div>
          <dt>{view === 'manager' ? 'Picture File Name' : 'PicName'}</dt>
          <dd>{cellLabel(row.cells[2])}</dd>
        </div>
        <div>
          <dt>{view === 'manager' ? 'Picture Directory' : 'PicDir'}</dt>
          <dd>{cellLabel(row.cells[1])}</dd>
        </div>
        <div>
          <dt>PicComment</dt>
          <dd>{cellLabel(row.cells[4])}</dd>
        </div>
      </dl>
      <div class="row-actions">
        <button onclick={onPreview} disabled={disabled || busy || lifecyclePending}>Preview selected picture</button>
        {#if !IS_WEB_READONLY && hasMetadataSession}
          <button onclick={onEditMetadata} disabled={disabled || busy || metadataPending || lifecyclePending}>
            Edit selected picture metadata
          </button>
        {/if}
        {#if !IS_WEB_READONLY && view === 'manager'}
          <button
            data-picture-delete-review
            onclick={onReviewDeletion}
            disabled={disabled || busy || metadataPending || lifecyclePending}
          >
            Review deletion of selected picture reference
          </button>
        {/if}
      </div>
    {/if}
  {/if}
{/if}
{@render children?.()}
<p class="guidance">
  Read-only linked metadata and JPEG/PNG preview. Each selected row uses its own PicDir.
  {view === 'manager'
    ? 'Default uses the explicitly authorized manager directory, not the FS882 child directory.'
    : 'Default uses the explicitly authorized child directory, not the manager PictureDir.'}
  {view === 'manager'
    ? 'Deletion requires the separate lifecycle review and backend permission.'
    : 'Record deletion remains unavailable here.'}
  {hasMetadataSession
    ? 'External directories and adding records remain unavailable here.'
    : 'External directories, adding records and metadata editing remain unavailable here.'}
  Files are never copied or repaired.
</p>

<style>
  .guidance {
    font-size: 0.8rem;
    color: var(--vpro-ink-secondary);
  }
  .row-actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    align-items: center;
  }
  button,
  select {
    border: 1px solid var(--vpro-border-strong);
    border-radius: 0.25rem;
    padding: 0.35rem 0.5rem;
    color: var(--vpro-ink);
    background: var(--vpro-surface);
    min-width: 0;
  }
  button:disabled,
  select:disabled {
    opacity: 0.5;
  }
  select {
    min-width: 0;
    max-width: 100%;
  }
  .metadata {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(15rem, 100%), 1fr));
    gap: 0.5rem;
  }
  dt {
    font-weight: 600;
    color: var(--vpro-ink);
  }
  dd {
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
</style>
