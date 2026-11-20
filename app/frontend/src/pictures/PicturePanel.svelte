<script lang="ts">
  import { onDestroy } from 'svelte';
  import { PictureService } from '../../bindings/github.com/boostao/vpro/app';
  import { equalCell } from '../admin/projectMetadataEditor';
  import { observeSession, observeSessionView } from '../shared/reactiveSession.svelte';
  import { ReadRequests, formatError } from '../shared/readRequests';
  import { notifications } from '../shell/notificationService.svelte';
  import type { PictureCreationReceipt } from './pictureCreationEditor';
  import { pictureCreationSession } from './pictureCreationSessions';
  import { pictureLifecycleOriginalMatches } from './pictureLifecycleEditor';
  import type { PictureLifecycleCommit, PictureLifecycleSession } from './pictureLifecycleSession';
  import { pictureLifecycleSession } from './pictureLifecycleSessions';
  import PictureMetadataEditor from './PictureMetadataEditor.svelte';
  import type { PictureMetadataSession } from './pictureMetadataSession';
  import PicturePanelLinkedList from './PicturePanelLinkedList.svelte';
  import {
    pictureCellLabel,
    pictureImageFromWire,
    pictureMetadataFromWire,
    type PicturePreview,
    type PictureReview,
  } from './pictureRead';

  let {
    contextId,
    project,
    plotNumber,
    view = 'child',
    disabled = false,
    metadataDisabled,
    onBusyChange,
    metadataSession,
    observeMutationReceipts = true,
  }: {
    contextId: string;
    project: string;
    plotNumber: string;
    disabled?: boolean;
    metadataDisabled?: boolean;
    view?: 'child' | 'manager';
    onBusyChange: (busy: boolean) => void;
    metadataSession?: PictureMetadataSession;
    observeMutationReceipts?: boolean;
  } = $props();

  const reads = new ReadRequests();
  let generation = 0;
  let busy = $state(false);
  let error = $state('');
  let review = $state<PictureReview | null>(null);
  let image = $state<PicturePreview | null>(null);
  let selected = $state('');
  let viewerOpen = $state(false);
  let viewer = $state<HTMLDialogElement>();
  const ownerKey = $derived(JSON.stringify([contextId, project, plotNumber, view]));
  let reviewKey = $state('');
  const currentReview = $derived(reviewKey === ownerKey ? review : null);
  const currentImage = $derived(reviewKey === ownerKey ? image : null);
  const row = $derived(currentReview?.records.rows.find((item) => item.rowId === selected));

  const creationSession = $derived(
    observeMutationReceipts && contextId && project && plotNumber
      ? pictureCreationSession({ contextId, project, plotNumber })
      : undefined
  );
  const observedCreation = observeSessionView(() => creationSession);
  const creationView = $derived(observedCreation.current);
  let appliedCreationRequest = '';

  const lifecycleSession = $derived(
    observeMutationReceipts && contextId && project && plotNumber
      ? pictureLifecycleSession({ contextId, project, plotNumber })
      : undefined
  );
  const observedLifecycle = observeSessionView(() => lifecycleSession);
  const lifecycleView = $derived(observedLifecycle.current);
  const observedLifecycleClose = observeSession(
    () => lifecycleSession,
    (s) => s.closeState()
  );
  const lifecyclePending = $derived(
    !!observedLifecycleClose.current &&
      (observedLifecycleClose.current.unsaved ||
        observedLifecycleClose.current.busy ||
        observedLifecycleClose.current.blocked)
  );
  let appliedLifecycleSession: PictureLifecycleSession | undefined;
  let appliedLifecycleRevision = 0;

  const observedMetadata = observeSession(
    () => metadataSession,
    (s) => ({ view: s.view(), close: s.closeState() })
  );
  const metadataClose = $derived(observedMetadata.current?.close);
  const metadataView = $derived(observedMetadata.current?.view);
  const metadataPending = $derived(!!metadataClose && (metadataClose.unsaved || metadataClose.busy));
  let appliedMetadataSession: PictureMetadataSession | undefined;
  let appliedMetadataRevision = 0;

  function synchronizeMetadataOriginal() {
    if (metadataSession !== appliedMetadataSession)
      [appliedMetadataSession, appliedMetadataRevision] = [metadataSession, 0];
    const update = metadataView?.originalUpdate;
    if (!update || update.revision === appliedMetadataRevision) return;
    appliedMetadataRevision = update.revision;
    if (
      !review ||
      reviewKey !== ownerKey ||
      update.contextId !== contextId ||
      update.project !== project ||
      update.plotNumber !== plotNumber
    )
      return;
    review = {
      ...review,
      records: {
        ...review.records,
        rows: review.records.rows.map((item) => (item.rowId === update.original.rowId ? update.original : item)),
      },
    };
    [image, viewerOpen] = [null, false];
  }
  $effect(synchronizeMetadataOriginal);

  async function refreshCreated(receipt: PictureCreationReceipt) {
    cancel();
    const [request, key, owner] = [generation, ownerKey, { contextId, project, plotNumber }];
    [busy, error, image, viewerOpen] = [true, '', null, false];
    onBusyChange(true);
    try {
      const value = await reads.track(PictureService.GetMetadata(contextId, plotNumber));
      if (request !== generation || key !== ownerKey) return;
      const refreshed = pictureMetadataFromWire(value, owner);
      const committed = refreshed.records.rows.find((item) => item.rowId === receipt.rowId);
      if (!committed || committed.cells.some((cell, index) => !equalCell(cell, receipt.committed.cells[index]))) {
        throw new Error('The complete committed physical row differs from the refreshed owned picture list.');
      }
      [review, reviewKey, selected] = [refreshed, key, receipt.rowId];
    } catch (cause) {
      if (request === generation && key === ownerKey) {
        const contextTag = plotNumber ? `Plot ${plotNumber}` : project || undefined;
        error = `Picture creation committed; linked-list refresh failed and receipt is retained: ${formatError(cause)}`;
        notifications.error('Picture list refresh failed', error, {
          category: 'entry',
          source: 'Plot Pictures',
          contextTag,
        });
      }
    } finally {
      if (request === generation) {
        busy = false;
        onBusyChange(false);
      }
    }
  }
  $effect(() => {
    const receipt = creationView?.receipts.at(-1);
    if (
      !receipt ||
      metadataPending ||
      receipt.requestId === appliedCreationRequest ||
      receipt.contextId !== contextId ||
      receipt.project !== project ||
      receipt.plotNumber !== plotNumber
    )
      return;
    appliedCreationRequest = receipt.requestId;
    void refreshCreated(receipt);
  });

  async function refreshLifecycle(commit: PictureLifecycleCommit) {
    cancel();
    const [request, key, owner] = [generation, ownerKey, { contextId, project, plotNumber }];
    [busy, error, review, reviewKey, selected, image, viewerOpen] = [true, '', null, '', '', null, false];
    onBusyChange(true);
    try {
      const value = await reads.track(PictureService.GetMetadata(contextId, plotNumber));
      if (request !== generation || key !== ownerKey) return;
      const refreshed = pictureMetadataFromWire(value, owner);
      const original =
        commit.kind === 'delete' ? commit.receipt.request.original : commit.receipt.request.deletion.original;
      if (commit.kind === 'delete') {
        if (
          refreshed.records.rows.some(
            (r) =>
              r.rowId === original.rowId ||
              (r.cells[0].storage === 'integer' && r.cells[0].integer === original.cells[0].integer)
          )
        ) {
          throw new Error('The deleted physical row/identity reappeared; no replacement is inferred.');
        }
      } else {
        const expected = [...commit.receipt.request.peers, original].sort((l, r) =>
          BigInt(l.rowId) < BigInt(r.rowId) ? -1 : BigInt(l.rowId) > BigInt(r.rowId) ? 1 : 0
        );
        if (
          refreshed.records.rows.length !== expected.length ||
          refreshed.records.rows.some((r, index) => !pictureLifecycleOriginalMatches(r, expected[index]))
        ) {
          throw new Error('The complete restored physical row/peers differ from the retained committed plan.');
        }
        selected = original.rowId;
      }
      [review, reviewKey] = [refreshed, key];
    } catch (cause) {
      if (request === generation && key === ownerKey) {
        const contextTag = plotNumber ? `Plot ${plotNumber}` : project || undefined;
        error = `Picture lifecycle committed; linked-list refresh failed and irreversible receipt is retained: ${formatError(cause)}`;
        notifications.error('Picture list refresh failed', error, {
          category: 'entry',
          source: 'Plot Pictures',
          contextTag,
        });
      }
    } finally {
      if (request === generation) {
        busy = false;
        onBusyChange(false);
      }
    }
  }
  $effect(() => {
    if (appliedLifecycleSession !== lifecycleSession)
      [appliedLifecycleSession, appliedLifecycleRevision] = [lifecycleSession, 0];
    const state = lifecycleView;
    const commit = state?.receipts.at(-1);
    if (!state || !commit || metadataPending || state.revision === appliedLifecycleRevision) return;
    appliedLifecycleRevision = state.revision;
    void refreshLifecycle(commit);
  });

  async function reviewDeletion() {
    if (!lifecycleSession || !row || view !== 'manager' || disabled || busy || metadataPending || lifecyclePending)
      return;
    try {
      await lifecycleSession.reviewDeletion(row.rowId);
      error = '';
    } catch (cause) {
      const contextTag = plotNumber ? `Plot ${plotNumber}` : project || undefined;
      error = `Picture deletion review unavailable: ${formatError(cause)}`;
      notifications.error('Picture deletion review unavailable', error, {
        category: 'entry',
        source: 'Plot Pictures',
        contextTag,
      });
    }
  }

  function editMetadata() {
    if (!metadataSession || !currentReview || !row || disabled || busy || metadataPending || lifecyclePending) return;
    try {
      metadataSession.select(currentReview, row.rowId);
      error = '';
    } catch (cause) {
      const contextTag = plotNumber ? `Plot ${plotNumber}` : project || undefined;
      error = `Picture metadata editing unavailable: ${formatError(cause)}`;
      notifications.error('Picture metadata editing unavailable', error, {
        category: 'entry',
        source: 'Plot Pictures',
        contextTag,
      });
    }
  }

  function cancel() {
    generation++;
    reads.cancelAll();
    busy = false;
    onBusyChange(false);
  }

  async function load() {
    if (disabled || busy || metadataPending || lifecyclePending) return;
    cancel();
    const [request, key, owner] = [generation, ownerKey, { contextId, project, plotNumber }];
    [busy, error, review, image, selected, viewerOpen] = [true, '', null, null, '', false];
    onBusyChange(true);
    try {
      const value = await reads.track(PictureService.GetMetadata(contextId, plotNumber));
      if (request !== generation || key !== ownerKey) return;
      [review, reviewKey, selected] = [pictureMetadataFromWire(value, owner), key, ''];
      selected = review.records.rows[0]?.rowId ?? '';
    } catch (cause) {
      if (request === generation && key === ownerKey) {
        const contextTag = plotNumber ? `Plot ${plotNumber}` : project || undefined;
        error = `Linked pictures unavailable; no files or data changed: ${formatError(cause)}`;
        notifications.error('Linked pictures unavailable', error, {
          category: 'entry',
          source: 'Plot Pictures',
          contextTag,
        });
      }
    } finally {
      if (request === generation) {
        busy = false;
        onBusyChange(false);
      }
    }
  }

  function select(value: string) {
    const contextTag = plotNumber ? `Plot ${plotNumber}` : project || undefined;
    if (metadataPending) {
      error = 'Finish or discard the retained picture metadata draft before changing selection.';
      notifications.error('Picture selection blocked', error, {
        category: 'entry',
        source: 'Plot Pictures',
        contextTag,
      });
      return;
    }
    if (lifecyclePending) {
      error =
        'Finish the retained picture lifecycle review or resolve/acknowledge its receipt before changing selection.';
      notifications.error('Picture selection blocked', error, {
        category: 'entry',
        source: 'Plot Pictures',
        contextTag,
      });
      return;
    }
    cancel();
    [selected, image, error, viewerOpen] = [value, null, '', false];
  }

  async function preview() {
    if (disabled || busy || !row || lifecyclePending) return;
    cancel();
    const [request, key, owner] = [generation, ownerKey, { contextId, project, plotNumber }];
    [busy, error, image, viewerOpen] = [true, '', null, false];
    onBusyChange(true);
    try {
      const original = $state.snapshot(row);
      const value = await reads.track(
        PictureService.GetImage(contextId, plotNumber, JSON.stringify({ view, original }))
      );
      if (request !== generation || key !== ownerKey || selected !== original.rowId) return;
      image = pictureImageFromWire(value, owner, original.rowId);
    } catch (cause) {
      if (request === generation && key === ownerKey) {
        const contextTag = plotNumber ? `Plot ${plotNumber}` : project || undefined;
        error = `Picture preview unavailable; metadata and original files retained: ${formatError(cause)}`;
        notifications.error('Picture preview unavailable', error, {
          category: 'entry',
          source: 'Plot Pictures',
          contextTag,
        });
      }
    } finally {
      if (request === generation) {
        busy = false;
        onBusyChange(false);
      }
    }
  }

  function failPreview(title: string, message: string) {
    [error, image, viewerOpen] = [message, null, false];
    notifications.error(title, message, {
      category: 'entry',
      source: 'Plot Pictures',
      contextTag: plotNumber ? `Plot ${plotNumber}` : project || undefined,
    });
  }

  function measured(event: Event) {
    if (!(event.currentTarget instanceof HTMLImageElement) || !currentImage) return;
    if (
      event.currentTarget.naturalWidth !== currentImage.width ||
      event.currentTarget.naturalHeight !== currentImage.height
    ) {
      failPreview(
        'Picture preview mismatch',
        'Displayed picture dimensions disagree with the owned decoded image; reload before viewing.'
      );
    }
  }

  function displayError() {
    failPreview(
      'Picture preview unavailable',
      'The owned picture bytes could not be displayed; metadata and files are unchanged.'
    );
  }

  $effect(() => {
    if (viewerOpen && currentImage && viewer && !viewer.open) viewer.showModal();
    else if (!viewerOpen && viewer?.open) viewer.close();
  });
  onDestroy(cancel);
</script>

<section class="pictures" data-picture-panel aria-label="Linked plot pictures">
  <h3>Pictures</h3>
  <div class="actions">
    <button onclick={load} disabled={disabled || busy || metadataPending || lifecyclePending}
      >Load linked pictures</button
    >
    {#if busy}<button onclick={cancel}>Cancel picture read</button>{/if}
  </div>

  <PicturePanelLinkedList
    review={currentReview}
    {selected}
    {row}
    {view}
    {disabled}
    {busy}
    {metadataPending}
    {lifecyclePending}
    hasMetadataSession={Boolean(metadataSession)}
    cellLabel={pictureCellLabel}
    onSelect={select}
    onPreview={preview}
    onEditMetadata={editMetadata}
    onReviewDeletion={reviewDeletion}
  >
    {#if metadataSession}
      <PictureMetadataEditor
        session={metadataSession}
        disabled={(metadataDisabled ?? disabled) || busy || lifecyclePending}
      />
    {/if}
    {#if currentImage}
      <button
        class="preview"
        aria-label="Open full-size picture"
        ondblclick={() => (viewerOpen = true)}
        onclick={() => (viewerOpen = true)}
      >
        <img
          src={currentImage.dataUrl}
          alt={row ? pictureCellLabel(row.cells[2]) : 'Selected plot picture'}
          onload={measured}
          onerror={displayError}
        />
      </button>
      <p>
        {currentImage.width} × {currentImage.height}; verified {currentImage.mime}. Click or double-click to open the
        viewer.
      </p>
    {/if}
  </PicturePanelLinkedList>
</section>
{#if viewerOpen && currentImage}
  <dialog
    bind:this={viewer}
    class="viewer"
    aria-label="Pictures viewer"
    oncancel={() => (viewerOpen = false)}
    onclose={() => (viewerOpen = false)}
  >
    <button onclick={() => (viewerOpen = false)}>Close picture viewer</button>
    <img
      src={currentImage.dataUrl}
      alt={row ? pictureCellLabel(row.cells[2]) : 'Selected plot picture'}
      onload={measured}
      onerror={displayError}
    />
  </dialog>
{/if}

<style>
  .pictures {
    display: grid;
    gap: 0.65rem;
    min-width: 0;
    padding: 0.75rem;
  }
  .pictures h3 {
    font-weight: 600;
    color: var(--vpro-navy);
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    align-items: center;
  }
  button {
    border: 1px solid var(--vpro-border-strong);
    border-radius: 0.25rem;
    padding: 0.35rem 0.5rem;
    color: var(--vpro-ink);
    background: var(--vpro-surface);
    min-width: 0;
  }
  button:disabled {
    opacity: 0.5;
  }
  .preview {
    width: fit-content;
    max-width: 100%;
  }
  img {
    max-width: 100%;
    height: auto;
  }
  .viewer::backdrop {
    background: rgba(0, 34, 68, 0.55);
  }
  .viewer {
    background: var(--vpro-surface);
    padding: 1rem;
    max-width: calc(100% - 2rem);
    max-height: calc(100% - 2rem);
    overflow: auto;
    border: 1px solid var(--vpro-border);
    border-radius: 0.25rem;
  }
  .viewer[open] {
    display: grid;
    gap: 0.75rem;
  }
</style>
