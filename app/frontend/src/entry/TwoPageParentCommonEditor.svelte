<script lang="ts">
  import { onDestroy, untrack, type Snippet } from 'svelte';
  import { PlotEntryService, AuditRestoreAction, type ListItem } from '../../bindings/github.com/boostao/vpro/app';
  import { ReadRequests } from '../shared/readRequests';
  import type { EditorCloseState } from '../shell/closeLifecycle';
  import TwoPageParentCommonFields from './TwoPageParentCommonFields.svelte';
  import TwoPageParentReviewSection from './TwoPageParentReviewSection.svelte';
  import TwoPageParentSourceLayout from './TwoPageParentSourceLayout.svelte';
  import { twoPageEntryValues, type TwoPageEntryChild } from './twoPageEntryProjection';
  import type { PaperControl } from './paperLayout';
  import type { TwoPageParentForm } from './twoPageParentSession';
  import { TwoPageParentCommonSession, type TwoPageParentCommonColumn,
    type TwoPageParentCommonInput, type TwoPageParentCommonSessionCache } from './twoPageParentCommonSession';

  let { contextId, project, plot, cache, revision, onchange, onbusy, onclosed, oncommitted, embedded: childContent, initialForm = 'FS882-8x6XL', onExtendedShrubsChange }: {
    contextId: string; project: string; plot: string; cache: TwoPageParentCommonSessionCache;
    revision: number; onchange: () => void; onbusy: (value: boolean) => void;
    onclosed: () => void; oncommitted: () => Promise<void>;
    embedded?: Snippet<[TwoPageEntryChild, PaperControl]>;
    initialForm?: TwoPageParentForm;
    onExtendedShrubsChange?: (enabled: boolean) => void;
  } = $props();
  const owner = untrack(() => ({ contextId, project, plot }));
  const reviewEnabled = true;
  const editingEnabled = true;
  const sourceLayoutEnabled = true;
  const reads = new ReadRequests();
  const key = JSON.stringify(owner);
  const sessions = untrack(() => {
    const owned = cache.get(key) ?? new Map<TwoPageParentForm, TwoPageParentCommonSession>();
    cache.set(key, owned); return owned;
  });
  let form = $state<TwoPageParentForm>(untrack(() => initialForm));
  let error = $state<string | null>(null);
  let choices = $state<ListItem[] | null>(null);
  let choicesBusy = $state(false);
  let choicesError = $state<string | null>(null);
  let choicesRequest = 0;
  let session = $state(makeSession(untrack(() => initialForm)));
  const view = $derived.by(() => { revision; return session.view(); });
  const close = $derived.by(() => { revision; return session.closeState(); });

  function makeSession(sourceForm: TwoPageParentForm) {
    const existing = sessions.get(sourceForm);
    if (existing) return existing;
    const next = new TwoPageParentCommonSession(owner, sourceForm, {
      read: () => reads.track(PlotEntryService.GetTwoPageParentCommonOriginal(owner.contextId, owner.plot, sourceForm)),
      cancelRead: () => reads.cancelAll(),
      save: request => PlotEntryService.SaveTwoPageParentCommon(owner.contextId, owner.plot, sourceForm, request),
      restore: (history, action) => PlotEntryService.RestoreTwoPageParentCommon(owner.contextId, owner.plot, sourceForm, history, action),
      refreshParent: async () => {
        await oncommitted();
        for (const [variant, peer] of sessions) {
          if (variant === sourceForm || !peer.view().original) continue;
          if (peer.closeState().unsaved || peer.closeState().busy || !await peer.load()) {
            throw new Error(peer.view().error ?? 'Another common-field source owner could not be refreshed; no write was replayed.');
          }
        }
      },
    }, onchange);
    sessions.set(sourceForm, next); return next;
  }
  $effect(() => { onbusy(view.busy); });
  onDestroy(() => { choicesRequest++; reads.cancelAll(); });
  export function getCloseState(): EditorCloseState {
    return { ...close, unsaved: true, canSave: false, error: error ?? view.error,
      saveReason: 'Save or Undo common fields explicitly, then close their review before saving or closing the plot.' };
  }
  export function undo() { void operation('undo'); }
  async function chooseForm(next: TwoPageParentForm) {
    if (close.unsaved || close.busy || close.blocked) {
      error = 'Finish or Undo the current source variant before changing its owner.'; return;
    }
    form = next; session = makeSession(next); onExtendedShrubsChange?.(next === 'FS882-8x6XL-CHARS'); onchange(); error = null;
    await operation('load');
  }
  function stage(column: TwoPageParentCommonColumn, input: TwoPageParentCommonInput) {
    try {
      if (!editingEnabled) throw new Error('Common-field editing is independently disabled.');
      session.stage(column, input); error = session.view().error;
    } catch (cause) { error = `Common-field draft failed; owned state retained: ${String(cause)}`; }
  }
  async function loadChoices() {
    const request = ++choicesRequest;
    choicesBusy = true; choicesError = null;
    try {
      if (!reviewEnabled) throw new Error('Two-page common review is independently disabled.');
      const result = await reads.track(PlotEntryService.GetListItems('PlotType'));
      if (request !== choicesRequest) return;
      if (!Array.isArray(result) || result.some(item => !item || item.listName !== 'PlotType'
        || typeof item.item !== 'string' || typeof item.itemDescription !== 'string')) {
        throw new Error('PlotType choices are unavailable or their source identity changed.');
      }
      choices = result;
    } catch (cause) {
      if (request === choicesRequest) {
        choices = null; choicesError = `PlotType choices could not be loaded; retry explicitly: ${String(cause)}`;
      }
    } finally { if (request === choicesRequest) choicesBusy = false; }
  }
  async function operation(action: 'load' | 'save' | 'undo' | 'retain' | 'prune') {
    try {
      if (!reviewEnabled || action !== 'load' && action !== 'undo' && !editingEnabled) {
        throw new Error('Two-page common review/editing is independently disabled.');
      }
      error = null;
      const ok = action === 'load' ? await session.load() : action === 'save' ? await session.save()
        : action === 'undo' ? await session.undo() : await session.restore(
          action === 'retain' ? AuditRestoreAction.AuditRestoreRetain : AuditRestoreAction.AuditRestorePrune);
      if (!ok) error = session.view().error;
      else if (action === 'load' || action === 'undo') await loadChoices();
    } catch (cause) { error = `Common-field operation failed; owned state retained: ${String(cause)}`; }
  }
  function cancel() {
    try { session.cancel(); error = session.view().error; }
    catch (cause) { error = `Common-field cancellation refused: ${String(cause)}`; }
  }
  function closeReview() {
    if (close.unsaved || close.busy || close.blocked) {
      error = close.saveReason || 'Save or Undo common fields before closing their review.'; return;
    }
    onclosed();
  }
</script>

<TwoPageParentReviewSection
  ariaLabel="Two-page common source review"
  {error}
  {form}
  locked={close.unsaved || close.busy || close.blocked}
  closeLabel="Close common-field review"
  onchooseform={next => void chooseForm(next)}
  onclose={closeReview}
>
  <TwoPageParentCommonFields {form} {view} {choices} {choicesBusy} {choicesError} disabled={!editingEnabled}
    readDisabled={!reviewEnabled} canSave={editingEnabled && close.canSave} onstage={stage}
    onoperation={action => void operation(action)} oncancel={cancel} onchoices={() => void loadChoices()}
    children={sourceLayoutEnabled ? completeLayout : undefined} />
</TwoPageParentReviewSection>

{#snippet completeLayout(editor: { columns: readonly string[]; input: Snippet<[PaperControl, string]>; labelled: true })}
  {#if view.original}
    <TwoPageParentSourceLayout
      {form}
      plot={owner.plot}
      scope="common"
      scopeLabel="Common"
      values={twoPageEntryValues(view.original, form)}
      {editor}
      {childContent}
    />
  {/if}
{/snippet}
