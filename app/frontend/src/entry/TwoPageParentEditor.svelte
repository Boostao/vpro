<script lang="ts">
  import { onDestroy, untrack, type Snippet } from 'svelte';
  import { PlotEntryService, AuditRestoreAction } from '../../bindings/github.com/boostao/vpro/app';
  import { ReadRequests, formatError } from '../shared/readRequests';
  import type { EditorCloseState } from '../shell/closeLifecycle';
  import TwoPageParentFields from './TwoPageParentFields.svelte';
  import TwoPageParentReviewSection from './TwoPageParentReviewSection.svelte';
  import TwoPageParentSourceLayout from './TwoPageParentSourceLayout.svelte';
  import { twoPageEntryValues, type TwoPageEntryChild } from './twoPageEntryProjection';
  import type { PaperControl } from './paperLayout';
  import {
    TwoPageParentSession,
    type TwoPageParentForm,
    type TwoPageParentColumn,
    type TwoPageParentInput,
    type TwoPageParentSessionCache,
  } from './twoPageParentSession';

  let {
    contextId,
    project,
    plot,
    cache,
    revision,
    onchange,
    onbusy,
    onclosed,
    oncommitted,
    embedded: childContent,
    initialForm = 'FS882-8x6XL',
    onExtendedShrubsChange,
  }: {
    contextId: string;
    project: string;
    plot: string;
    cache: TwoPageParentSessionCache;
    revision: number;
    onchange: () => void;
    onbusy: (value: boolean) => void;
    onclosed: () => void;
    oncommitted: () => Promise<void>;
    embedded?: Snippet<[TwoPageEntryChild, PaperControl]>;
    initialForm?: TwoPageParentForm;
    onExtendedShrubsChange?: (enabled: boolean) => void;
  } = $props();
  const owner = untrack(() => ({ contextId, project, plot }));
  const reads = new ReadRequests();
  const sessions = untrack(() => {
    const cacheKey = JSON.stringify(owner);
    const owned = cache.get(cacheKey) ?? new Map<TwoPageParentForm, TwoPageParentSession>();
    cache.set(cacheKey, owned);
    return owned;
  });
  let form = $state<TwoPageParentForm>(untrack(() => initialForm));
  let error = $state<string | null>(null);
  let session = $state(makeSession(untrack(() => initialForm)));
  const view = $derived.by(() => {
    revision;
    return session.view();
  });
  const close = $derived.by(() => {
    revision;
    return session.closeState();
  });

  function makeSession(sourceForm: TwoPageParentForm) {
    const existing = sessions.get(sourceForm);
    if (existing) return existing;
    const next = new TwoPageParentSession(
      owner,
      sourceForm,
      {
        read: () =>
          reads.track(PlotEntryService.GetTwoPageParentExtraOriginal(owner.contextId, owner.plot, sourceForm)),
        cancelRead: () => reads.cancelAll(),
        save: (request) => PlotEntryService.SaveTwoPageParentExtra(owner.contextId, owner.plot, sourceForm, request),
        restore: (history, action) =>
          PlotEntryService.RestoreTwoPageParentExtra(owner.contextId, owner.plot, sourceForm, history, action),
        refreshParent: async () => {
          await oncommitted();
          for (const [variant, peer] of sessions) {
            if (variant === sourceForm || !peer.view().original) continue;
            if (peer.closeState().unsaved || peer.closeState().busy || !(await peer.load())) {
              throw new Error(
                peer.view().error ?? 'Another two-page source owner could not be refreshed; no write was replayed.'
              );
            }
          }
        },
      },
      onchange
    );
    sessions.set(sourceForm, next);
    return next;
  }
  $effect(() => {
    onbusy(view.busy);
  });
  onDestroy(() => {
    reads.cancelAll();
  });

  export function getCloseState(): EditorCloseState {
    return {
      ...close,
      unsaved: true,
      canSave: false,
      error: error ?? view.error,
      saveReason:
        'Save or Undo additional fields explicitly, then close their review before saving or closing the plot.',
    };
  }
  export function undo() {
    void operation('undo');
  }

  async function chooseForm(next: TwoPageParentForm) {
    if (close.unsaved || close.busy || close.blocked) {
      error = 'Finish or Undo the current source variant before changing its owner.';
      return;
    }
    form = next;
    session = makeSession(next);
    onExtendedShrubsChange?.(next === 'FS882-8x6XL-CHARS');
    onchange();
    error = null;
    await operation('load');
  }
  function stage(column: TwoPageParentColumn, input: TwoPageParentInput) {
    try {
      session.stage(column, input);
      error = session.view().error;
    } catch (cause) {
      error = `Additional-field draft failed; owned state retained: ${formatError(cause)}`;
    }
  }
  async function operation(action: 'load' | 'save' | 'undo' | 'retain' | 'prune') {
    try {
      error = null;
      const ok =
        action === 'load'
          ? await session.load()
          : action === 'save'
            ? await session.save()
            : action === 'undo'
              ? await session.undo()
              : await session.restore(
                  action === 'retain' ? AuditRestoreAction.AuditRestoreRetain : AuditRestoreAction.AuditRestorePrune
                );
      if (!ok) error = session.view().error;
    } catch (cause) {
      error = `Additional-field operation failed; owned state retained: ${formatError(cause)}`;
    }
  }
  function cancel() {
    try {
      session.cancel();
      error = session.view().error;
    } catch (cause) {
      error = `Additional-field cancellation refused: ${formatError(cause)}`;
    }
  }
  function closeReview() {
    if (close.unsaved || close.busy || close.blocked) {
      error = close.saveReason || 'Save or Undo additional fields before closing their review.';
      return;
    }
    onclosed();
  }
</script>

<TwoPageParentReviewSection
  ariaLabel="Two-page source review"
  {error}
  {form}
  locked={close.unsaved || close.busy || close.blocked}
  closeLabel="Close additional-field review"
  onchooseform={(next) => void chooseForm(next)}
  onclose={closeReview}
>
  <TwoPageParentFields
    {form}
    {view}
    disabled={false}
    readDisabled={false}
    canSave={close.canSave}
    onstage={stage}
    onoperation={(action) => void operation(action)}
    oncancel={cancel}
    children={completeLayout}
  />
</TwoPageParentReviewSection>

{#snippet completeLayout(editor: {
  columns: readonly string[];
  input: Snippet<[PaperControl, string]>;
  labelled: true;
})}
  {#if view.original}
    <TwoPageParentSourceLayout
      {form}
      plot={owner.plot}
      scope="extra"
      scopeLabel="Additional"
      values={twoPageEntryValues(view.original, form)}
      {editor}
      {childContent}
    />
  {/if}
{/snippet}
