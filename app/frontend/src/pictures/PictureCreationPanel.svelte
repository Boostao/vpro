<script lang="ts">
  import { untrack } from 'svelte';
  import type { PictureCreationSession } from './pictureCreationSession';
  import { notifications } from '../shell/notificationService.svelte';
  let { session, disabled = false }: { session: PictureCreationSession; disabled?: boolean } = $props();
  let revision = $state(0);
  $effect(() => session.subscribe(() => untrack(() => revision++)));
  const view = $derived.by(() => { revision; return session.view(); });
  let error = $state('');
  const initialView = untrack(() => session.view());
  if (initialView.error) {
    const plotTag = initialView.receipt?.plotNumber
      ? `Plot ${initialView.receipt.plotNumber}`
      : initialView.request?.plotNumber
        ? `Plot ${initialView.request.plotNumber}`
        : undefined;
    notifications.error('Picture operation error', initialView.error, {
      category: 'entry',
      source: 'Plot Pictures',
      contextTag: plotTag,
    });
  }
  async function operate(operation: 'add' | 'selection' | 'create' | 'receipt' | 'preview' | 'release' | 'acknowledge' | 'cancel') {
    error = '';
    try {
      if (operation === 'cancel') {
        session.cancel();
        const current = session.view();
        if (current.error) {
          const plotTag = current.request?.plotNumber ? `Plot ${current.request.plotNumber}` : undefined;
          notifications.error('Picture operation cancelled', current.error, {
            category: 'entry',
            source: 'Plot Pictures',
            contextTag: plotTag,
          });
        }
      } else if (operation === 'add' || operation === 'create') {
        if (operation === 'add' && disabled) throw new Error('Finish the current picture read or metadata draft before adding.');
        const ok = operation === 'add' ? await session.add(crypto.randomUUID()) : await session.create();
        const current = session.view();
        const plotTag = current.receipt?.plotNumber
          ? `Plot ${current.receipt.plotNumber}`
          : current.request?.plotNumber
            ? `Plot ${current.request.plotNumber}`
            : undefined;
        if (ok && current.receipt) {
          notifications.success(
            'Picture attached',
            `Attached ${current.receipt.selectedPath} (ID ${current.receipt.id}, physical row ${current.receipt.rowId}, history ${current.receipt.historyId}; PicComment remains NULL).`,
            { category: 'entry', source: 'Plot Pictures', contextTag: plotTag },
          );
          await session.preview();
          const afterPreview = session.view();
          if (afterPreview.error) {
            notifications.error('Picture preview unavailable', afterPreview.error, {
              category: 'entry',
              source: 'Plot Pictures',
              contextTag: plotTag,
            });
          }
        } else if (current.error) {
          notifications.error('Picture attach failed', current.error, {
            category: 'entry',
            source: 'Plot Pictures',
            contextTag: plotTag,
          });
        }
      } else if (operation === 'selection') {
        const ok = await session.recoverSelection();
        const current = session.view();
        if (!ok && current.error) {
          notifications.error('Picture selection recovery failed', current.error, { category: 'entry', source: 'Plot Pictures' });
        }
      } else if (operation === 'receipt') {
        const ok = await session.recoverReceipt();
        const current = session.view();
        const plotTag = current.receipt?.plotNumber ? `Plot ${current.receipt.plotNumber}` : undefined;
        if (ok && current.receipt) {
          notifications.success('Picture receipt recovered', `Recovered attach receipt for ${current.receipt.selectedPath} (ID ${current.receipt.id}, physical row ${current.receipt.rowId}, history ${current.receipt.historyId}; PicComment remains NULL).`, {
            category: 'entry',
            source: 'Plot Pictures',
            contextTag: plotTag,
          });
        } else if (current.error) {
          notifications.error('Picture receipt recovery failed', current.error, {
            category: 'entry',
            source: 'Plot Pictures',
            contextTag: plotTag,
          });
        }
      } else if (operation === 'preview') {
        const ok = await session.preview();
        const current = session.view();
        if (!ok && current.error) {
          notifications.error('Picture preview unavailable', current.error, { category: 'entry', source: 'Plot Pictures' });
        }
      } else if (operation === 'release') {
        const ok = await session.release();
        const current = session.view();
        if (!ok && current.error) {
          notifications.error('Picture selection release failed', current.error, { category: 'entry', source: 'Plot Pictures' });
        }
      } else {
        const ok = await session.acknowledge();
        const current = session.view();
        if (!ok && current.error) {
          notifications.error('Picture acknowledgement failed', current.error, { category: 'entry', source: 'Plot Pictures' });
        }
      }
    } catch (cause) {
      error = `Picture operation unavailable; retained state is unchanged: ${String(cause)}`;
      notifications.error('Picture attach unavailable', error, { category: 'entry', source: 'Plot Pictures' });
    }
  }
</script>

<section class="creation" data-picture-creation aria-label="Add a Picture">
  <h2>Add a Picture</h2>
  <div class="actions">
    <button data-picture-add disabled={disabled || view.busy || view.blocked} onclick={() => operate('add')}>Add a Picture</button>
    {#if view.blocked}
      <button data-picture-recover-selection disabled={view.busy} onclick={() => operate('selection')}>Recover selection (read-only)</button>
      {#if view.request && view.attempted}
        <button data-picture-recover-receipt disabled={view.busy} onclick={() => operate('receipt')}>Resolve creation history (read-only)</button>
      {/if}
      {#if view.selection && view.request && !view.receipt && !view.attempted}
        <button data-picture-create-recovered disabled={view.busy} onclick={() => operate('create')}>Create recovered selection once</button>
      {/if}
      {#if !view.receipt}
        <button data-picture-release disabled={view.busy || (view.attempted && !view.noCommitVerified)} onclick={() => operate('release')}>Release verified uncommitted selection</button>
      {/if}
    {/if}
    {#if view.receipt && !view.acknowledged}
      <button data-picture-selected-preview disabled={view.busy || !view.selection} onclick={() => operate('preview')}>Preview this selected file</button>
      <button data-picture-acknowledge disabled={view.busy} onclick={() => operate('acknowledge')}>Acknowledge retained creation receipt</button>
    {/if}
    {#if view.busy && !['choosing', 'releasing', 'acknowledging'].includes(view.phase)}
      <button data-picture-cancel onclick={() => operate('cancel')}>Cancel operation acknowledgement</button>
    {/if}
  </div>
  {#if view.selection}
    <p data-picture-selected-path>Selected file: {view.selection.selectedPath}</p>
  {/if}
  {#if view.request}<p data-picture-creation-request>Request ID: {view.request.requestId}</p>{/if}
  {#if view.image}
    <img data-picture-selected-image src={view.image.dataUrl} alt="Selected plot attachment preview" />
    <p>{view.image.width} × {view.image.height}; {view.image.mime}; SHA256 {view.image.sha256}</p>
  {/if}
  <p class="guidance">Choose a JPEG or PNG image file to link to this plot. VPro records the file path for this plot without copying or moving image files on disk; cancelling leaves the plot unchanged.</p>
</section>

<style>
  .creation { display: grid; grid-template-columns: minmax(0, 1fr); gap: .65rem; margin: 1rem 0; padding: .75rem; border: 1px solid #D8D8D8; background: #FFFFFF; border-radius: .25rem; min-width: 0; }
  h2 { font-weight: 600; color: #003366; }
  .actions { display: flex; flex-wrap: wrap; gap: .5rem; }
  button { border: 1px solid #9F9F9F; border-radius: .25rem; padding: .5rem .65rem; min-width: 0; overflow-wrap: anywhere; color: #313132; background: #FFFFFF; }
  button:disabled { opacity: .5; }
  p { overflow-wrap: anywhere; }
  img { max-width: 100%; max-height: 28rem; object-fit: contain; }
  .guidance { font-size: .8rem; color: #474543; }
</style>
