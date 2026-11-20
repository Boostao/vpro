<script module lang="ts">
  import { formatError } from '../shared/readRequests';
  import { notifications } from '../shell/notificationService.svelte';
</script>

<script lang="ts">
  import { untrack } from 'svelte';
  import type { PictureMetadataSession } from './pictureMetadataSession';
  import {
    pictureMetadataColumns,
    pictureMetadataFieldValue,
    type PictureMetadataColumn,
  } from './pictureMetadataEditor';

  let { session, disabled = false }: { session: PictureMetadataSession; disabled?: boolean } = $props();
  let revision = $state(0);
  $effect(() => session.subscribe(() => untrack(() => revision++)));
  const view = $derived.by(() => {
    revision;
    return session.view();
  });
  const close = $derived.by(() => {
    revision;
    return session.closeState();
  });
  let error = $state('');
  const initialView = untrack(() => session.view());
  if (initialView.error) {
    const plotTag = initialView.draft?.plotNumber ? `Plot ${initialView.draft.plotNumber}` : undefined;
    notifications.error('Picture metadata error', initialView.error, {
      category: 'entry',
      source: 'Plot Pictures',
      contextTag: plotTag,
    });
  }

  function stage(column: PictureMetadataColumn, raw: string, nullValue: boolean) {
    try {
      session.stage(column, raw, nullValue);
      error = '';
    } catch (cause) {
      error = formatError(cause);
      const plotTag = view.draft?.plotNumber ? `Plot ${view.draft.plotNumber}` : undefined;
      notifications.error('Picture metadata staging failed', error, {
        category: 'entry',
        source: 'Plot Pictures',
        contextTag: plotTag,
      });
    }
  }
  function cancelMetadata() {
    session.cancel();
    const current = session.view();
    if (current.error) {
      const plotTag = current.draft?.plotNumber ? `Plot ${current.draft.plotNumber}` : undefined;
      notifications.error('Picture metadata operation cancelled', current.error, {
        category: 'entry',
        source: 'Plot Pictures',
        contextTag: plotTag,
      });
    }
  }
  async function operation(action: 'save' | 'resolve' | 'discard') {
    const plotTag = view.draft?.plotNumber ? `Plot ${view.draft.plotNumber}` : undefined;
    try {
      error = '';
      if (action === 'save') {
        const ok = await session.save(crypto.randomUUID());
        const current = session.view();
        if (ok && current.receipt) {
          notifications.success(
            'Picture metadata saved',
            `Saved picture metadata (history ${current.receipt.historyId}).`,
            { category: 'entry', source: 'Plot Pictures', contextTag: plotTag }
          );
        } else if (ok) {
          notifications.info('No picture metadata changes', 'No metadata fields differed from the saved picture row.', {
            category: 'entry',
            source: 'Plot Pictures',
            contextTag: plotTag,
          });
        } else if (current.error) {
          notifications.error('Picture metadata save failed', current.error, {
            category: 'entry',
            source: 'Plot Pictures',
            contextTag: plotTag,
          });
        }
      } else if (action === 'resolve') {
        const ok = await session.resolve();
        const current = session.view();
        if (ok && current.receipt) {
          notifications.success(
            'Picture metadata receipt resolved',
            `Resolved picture metadata save (history ${current.receipt.historyId}).`,
            { category: 'entry', source: 'Plot Pictures', contextTag: plotTag }
          );
        } else if (!ok && current.error) {
          notifications.error('Picture metadata recovery failed', current.error, {
            category: 'entry',
            source: 'Plot Pictures',
            contextTag: plotTag,
          });
        }
      } else {
        const ok = await session.discardAndReload();
        const current = session.view();
        if (ok) {
          notifications.info('Picture metadata draft discarded', 'Reloaded current picture metadata.', {
            category: 'entry',
            source: 'Plot Pictures',
            contextTag: plotTag,
          });
        } else if (current.error) {
          notifications.error('Picture metadata reload failed', current.error, {
            category: 'entry',
            source: 'Plot Pictures',
            contextTag: plotTag,
          });
        }
      }
    } catch (cause) {
      error = formatError(cause);
      notifications.error('Picture metadata action failed', error, {
        category: 'entry',
        source: 'Plot Pictures',
        contextTag: plotTag,
      });
    }
  }
</script>

{#if view.draft}
  <section class="editor" data-picture-metadata-editor aria-label="Existing picture metadata">
    <h4>Existing picture metadata</h4>
    <p>
      Plot {JSON.stringify(view.draft.plotNumber)} · Picture ID {view.draft.id} (record {view.draft.original.rowId})
    </p>
    {#if view.blocked}
      <p role="alert">
        The picture Save outcome is unknown. The original and draft remain retained. Matching current values do not
        prove this request committed. Resolve its durable receipt or explicitly discard and reload.
      </p>
    {/if}
    <div class="fields">
      {#each pictureMetadataColumns as column}
        {@const cell = pictureMetadataFieldValue(view.draft, column)}
        <div>
          <label for={`picture-metadata-${column}`}>
            {column === 'PicDir'
              ? 'Picture Directory'
              : column === 'PicName'
                ? 'Picture File Name'
                : 'Picture Comment / Caption'}
          </label>
          <input
            id={`picture-metadata-${column}`}
            value={cell.raw}
            placeholder={column === 'PicComment' ? 'Add a photo caption (leave blank for none)' : undefined}
            disabled={disabled || view.busy || view.blocked || (column !== 'PicComment' && cell.nullValue)}
            aria-invalid={cell.error !== null}
            oninput={(event) =>
              stage(column, event.currentTarget.value, column === 'PicComment' && event.currentTarget.value === '')}
          />
          <label class="null">
            <input
              type="checkbox"
              checked={cell.nullValue}
              disabled={disabled || view.busy || view.blocked}
              onchange={(event) =>
                stage(
                  column,
                  column === 'PicComment' && event.currentTarget.checked ? '' : cell.raw,
                  event.currentTarget.checked
                )}
            />
            NULL {column}
          </label>
          {#if cell.error}<p role="alert" class="error">{cell.error}</p>{/if}
        </div>
      {/each}
    </div>
    <div class="actions">
      <button onclick={() => void operation('save')} disabled={disabled || !close.canSave || !close.unsaved}>
        Save picture metadata only
      </button>
      {#if view.blocked}
        <button onclick={() => void operation('resolve')} disabled={disabled || view.busy}>
          Resolve picture Save receipt
        </button>
      {/if}
      <button onclick={() => void operation('discard')} disabled={disabled || view.busy}>
        Discard draft and reload picture
      </button>
      {#if view.busy}<button onclick={() => cancelMetadata()}>Cancel picture metadata operation</button>{/if}
    </div>
    <p class="guidance">
      Each field accepts at most 255 characters. Picture Directory allows blank text or NULL; Picture File Name cannot
      be saved as empty text; clearing Comment / Caption saves NULL. Saving updates the folder, file name, and caption
      in the picture library without moving or renaming image files on disk.
      {'Discard reloads the saved record; it does not undo a completed Save.'}
    </p>
  </section>
{/if}

<style>
  .editor {
    display: grid;
    gap: 0.65rem;
    border: 1px solid var(--vpro-border);
    background: var(--vpro-surface);
    border-radius: 0.25rem;
    padding: 0.75rem;
    min-width: 0;
  }
  h4 {
    font-weight: 600;
    color: var(--vpro-navy);
  }
  .fields {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(16rem, 100%), 1fr));
    gap: 0.75rem;
  }
  .fields > div {
    display: grid;
    gap: 0.3rem;
    min-width: 0;
  }
  .null {
    display: flex;
    gap: 0.4rem;
    align-items: center;
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
  }
  input,
  button {
    border: 1px solid var(--vpro-border-strong);
    border-radius: 0.25rem;
    padding: 0.35rem 0.5rem;
    min-width: 0;
    color: var(--vpro-ink);
    background: var(--vpro-surface);
  }
  button:disabled,
  input:disabled {
    opacity: 0.5;
  }
  p {
    overflow-wrap: anywhere;
  }
  .error {
    color: var(--vpro-error);
    background: var(--vpro-error-bg);
    border: 1px solid var(--vpro-error);
    padding: 0.5rem;
    border-radius: 0.25rem;
  }
  .guidance {
    font-size: 0.8rem;
    color: var(--vpro-ink-secondary);
  }
</style>
