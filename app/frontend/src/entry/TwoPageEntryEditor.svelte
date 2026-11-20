<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { PlotEntryService } from '../../bindings/github.com/boostao/vpro/app';
  import { formatError, ReadRequests } from '../shared/readRequests';
  import type { EditorCloseState } from '../shell/closeLifecycle';
  import type { TwoPageParentForm } from './twoPageParentSession';
  import type { TwoPageEntryInput } from './twoPageEntryDraft';
  import { TwoPageEntrySession, twoPageEntryCell } from './twoPageEntrySession';
  import TwoPageEntryLayout from './TwoPageEntryLayout.svelte';
  import { twoPageEntryProjection, twoPageEntryValues, type TwoPageEntryField } from './twoPageEntryProjection';
  import type { PaperControl } from './paperLayout';
  import { notifications } from '../shell/notificationService.svelte';
  import {
    computeTwoPageCloseState,
    computeTwoPageDraftState,
    createOrReuseTwoPageSession,
    executeTwoPageParentOperation,
    resolveTwoPageReaderFlags,
  } from './twoPageEntryOps';
  import {
    buildTwoPageFieldCard,
    createTwoPageEntryReaders,
    type TwoPageEntryProps,
  } from './useTwoPageEntryReaders.svelte';
  import TwoPageEntryToolbar from './TwoPageEntryToolbar.svelte';
  import TwoPageEntryReadersHost from './TwoPageEntryReadersHost.svelte';
  import TwoPageEntryFieldInput from './TwoPageEntryFieldInput.svelte';

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
    childBlocked = false,
    pictureReaderAvailable = false,
    auditReaderAvailable = false,
    googleEarthReaderAvailable = false,
    vegetationTableReaderAvailable = false,
    environmentTableReaderAvailable = false,
    projectMetadataReaderAvailable = false,
    vegetationTableSU = '',
    vegetationTableSUPath = '',
    sourceProjectPath = '',
    projectMetadataClient,
    metadataRestorationAvailable = false,
    profilingReaderAvailable = false,
    profilingSource = null,
    externalScope = null,
    sourceBlocked = true,
    initialForm = 'FS882-8x6XL',
    standalone = false,
    onExtendedShrubsChange,
    onOpenProfileSU,
  }: TwoPageEntryProps = $props();

  const owner = untrack(() => ({ contextId, project, plot }));
  const sessions = untrack(() => {
    const key = JSON.stringify(owner);
    const existing = cache.get(key) ?? new Map<TwoPageParentForm, TwoPageEntrySession>();
    cache.set(key, existing);
    return existing;
  });
  let form = $state<TwoPageParentForm>(untrack(() => initialForm));
  let session = $state(makeSession(untrack(() => initialForm)));
  let error = $state<string | null>(null);
  let fieldCardModalOpen = $state(false),
    fieldCardSplitOpen = $state(false);
  const view = $derived.by(() => {
    revision;
    return session.view();
  });
  const close = $derived.by(() => {
    revision;
    return session.closeState();
  });
  const projection = $derived(twoPageEntryProjection(form));
  const availabilities = $derived({
    profiling: profilingReaderAvailable,
    projectMetadata: projectMetadataReaderAvailable,
    environmentTable: environmentTableReaderAvailable,
    vegetationTable: vegetationTableReaderAvailable,
    googleEarth: googleEarthReaderAvailable,
    audit: auditReaderAvailable,
  });

  const readers = createTwoPageEntryReaders(
    untrack(() => ({
      owner,
      sessions,
      metadataClient: projectMetadataClient,
      metadataRestore: metadataRestorationAvailable,
      sourceScope: externalScope,
      profileSource: profilingSource ? { ...profilingSource } : null,
      vegetationScope: { projectPath: sourceProjectPath, su: vegetationTableSU, suPath: vegetationTableSUPath },
      googleEarthPath: sourceProjectPath,
      getForm: () => form,
      getSession: () => session,
      getView: () => view,
      getDraftState: () => getDraftState(),
      getSourceBlocked: () => sourceBlocked,
      getChildBlocked: () => childBlocked,
      getAvailabilities: () => availabilities,
      setError: (msg) => {
        error = msg;
      },
      onchange: () => onchange(),
      oncommitted: () => oncommitted(),
      openMetadataEditor: () => openMetadataEditor(),
    }))
  );

  const twoPageFieldCardViewModel = $derived(
    buildTwoPageFieldCard(
      fieldCardModalOpen || fieldCardSplitOpen,
      owner.plot,
      form,
      view,
      close.unsaved || childBlocked
    )
  );

  function handleTwoPageKeydown(event: KeyboardEvent) {
    if (event.altKey && !event.ctrlKey && !event.metaKey && !event.shiftKey && event.key.toLowerCase() === 'p') {
      event.preventDefault();
      fieldCardModalOpen = !fieldCardModalOpen;
      if (fieldCardModalOpen) fieldCardSplitOpen = false;
      return;
    }
    if ((event.ctrlKey || event.metaKey) && !event.altKey && !event.shiftKey && event.key.toLowerCase() === 's') {
      event.preventDefault();
      const flags = resolveTwoPageReaderFlags(typeof readers !== 'undefined' ? readers : undefined);
      if (!flags.anyOpen && !childBlocked && close.canSave && !close.busy && !close.blocked) void operation('save');
    }
  }

  function makeSession(sourceForm: TwoPageParentForm) {
    return createOrReuseTwoPageSession({
      owner,
      sessions,
      sourceForm,
      oncommitted,
      onchange,
      PlotEntrySvc: PlotEntryService,
      ReadsCls: ReadRequests,
      SessionCls: TwoPageEntrySession,
    });
  }

  $effect(() => {
    onbusy(view.busy || view.referencesBusy || readers.anyOpen || readers.anyBusy);
  });
  let autoLoadedKey = '';
  $effect(() => {
    if (!standalone || !owner.plot) return;
    const key = `${owner.contextId}:${owner.project}:${owner.plot}:${form}`;
    if (
      autoLoadedKey === key ||
      view.original ||
      view.busy ||
      view.referencesBusy ||
      view.error ||
      view.referenceError ||
      view.blocked
    )
      return;
    autoLoadedKey = key;
    void operation('load');
  });
  onDestroy(() => {
    const active = session.view();
    if (active.operation === 'read' || active.referencesBusy) session.cancel();
  });

  export function getCloseState(): EditorCloseState {
    const flags = resolveTwoPageReaderFlags(typeof readers !== 'undefined' ? readers : undefined);
    return computeTwoPageCloseState({
      flags,
      standalone: typeof standalone !== 'undefined' && standalone,
      childBlocked,
      close,
      error,
      getDraftState,
    });
  }

  export async function saveForClose(): Promise<boolean> {
    const state = getCloseState();
    if (!(typeof standalone !== 'undefined' && standalone) || !state.canSave) {
      error = state.saveReason;
      return false;
    }
    await operation('save');
    return !getDraftState().unsaved && !close.blocked && error === null;
  }

  export function getDraftState(): EditorCloseState {
    const flags = resolveTwoPageReaderFlags(typeof readers !== 'undefined' ? readers : undefined);
    return computeTwoPageDraftState({ flags, sessions, view, close, error, getCloseState });
  }

  export function canOpenMetadataEditor() {
    const state = getDraftState();
    if (
      !readers.metadataClient ||
      sourceBlocked ||
      childBlocked ||
      !view.original ||
      state.unsaved ||
      state.busy ||
      state.blocked ||
      state.error ||
      [...sessions.values()].some((peer) => Boolean(peer.view().error || peer.view().referenceError))
    )
      return false;
    const projectId = twoPageEntryCell(view.original, 'ProjectID');
    return projectId.storage === 'text' && projectId.text !== null && projectId.text.length > 0;
  }

  export function openMetadataEditor() {
    if (!canOpenMetadataEditor()) {
      error =
        'Resolve source-variant and linked-child drafts, references and retained outcomes before editing owned project metadata.';
      return;
    }
    error = null;
    readers.projectMetadataOpen = 'edit';
    onchange();
  }

  export function undo() {
    if (readers.projectMetadataOpen === 'edit') {
      readers.metadataEditor?.undo();
      return;
    }
    void operation('undo');
  }

  async function chooseForm(next: TwoPageParentForm) {
    if (readers.anyOpen || childBlocked || close.unsaved || close.busy || close.blocked) {
      error = 'Save or Undo the owned complete-entry draft before changing source variant.';
      return;
    }
    form = next;
    session = makeSession(next);
    onExtendedShrubsChange?.(next === 'FS882-8x6XL-CHARS');
    onchange();
    await operation('load');
  }

  async function operation(action: 'load' | 'save' | 'undo' | 'retain' | 'prune' | 'references') {
    const r = typeof readers !== 'undefined' ? readers : undefined;
    await executeTwoPageParentOperation({
      action,
      plotName: typeof owner !== 'undefined' && owner?.plot ? owner.plot : '',
      formLabel: typeof form !== 'undefined' ? form : 'Two-page',
      childBlocked,
      session,
      close: typeof close !== 'undefined' ? close : undefined,
      readers: r,
      flags: resolveTwoPageReaderFlags(r),
      setError: (msg) => {
        error = msg;
      },
      notify: notifications,
    });
  }

  function stage(column: string, input: TwoPageEntryInput) {
    try {
      readers.assertParentFree('field');
      if (childBlocked && !view.drafts[column])
        throw new Error('Resolve linked-child ownership before new parent staging.');
      session.stage(column, input);
      error = session.view().error;
    } catch (cause) {
      error = `Complete-entry draft refused; owned state retained: ${formatError(cause)}`;
    }
  }
  function selectProject(rowId: string | null) {
    try {
      readers.assertParentFree('project');
      if (childBlocked && !view.drafts.ProjectID)
        throw new Error('Resolve linked-child ownership before new parent staging.');
      session.selectProject(rowId);
      error = session.view().error;
    } catch (cause) {
      error = `Physical ProjectID selection refused: ${formatError(cause)}`;
    }
  }
  function acknowledge(column: string) {
    try {
      readers.assertParentFree('literal');
      session.acknowledge(column);
      error = session.view().error;
    } catch (cause) {
      error = `Literal acknowledgement refused: ${formatError(cause)}`;
    }
  }
  function cancel() {
    try {
      if (readers.projectMetadataOpen)
        throw new Error('Project metadata owns the source; cancel its own read explicitly.');
      session.cancel();
      error = session.view().error;
    } catch (cause) {
      error = `Complete-entry cancellation refused: ${formatError(cause)}`;
    }
  }
  function closeReview() {
    const flags = resolveTwoPageReaderFlags(typeof readers !== 'undefined' ? readers : undefined);
    if (flags.anyOpen || childBlocked || close.unsaved || close.busy || close.blocked) {
      error = close.saveReason || 'Save or Undo complete-entry drafts before closing their review.';
      return;
    }
    onclosed();
  }
</script>

<svelte:window onkeydown={handleTwoPageKeydown} />

{#snippet shrubToggle()}
  <label
    class="inline-flex items-center gap-1.5 rounded border border-vpro-border bg-white px-2.5 py-1 text-xs font-medium text-vpro-ink"
  >
    <input
      type="checkbox"
      data-extended-shrubs
      checked={form === 'FS882-8x6XL-CHARS'}
      disabled={childBlocked || close.unsaved || close.busy || close.blocked}
      onchange={(event) => chooseForm(event.currentTarget.checked ? 'FS882-8x6XL-CHARS' : 'FS882-8x6XL')}
    />
    Show extended shrub layers
  </label>
{/snippet}
{#snippet identityField(field: TwoPageEntryField)}
  <label class="block text-sm font-medium text-vpro-navy" for="complete-entry-identity">Plot number</label>
  <input
    id="complete-entry-identity"
    class="two-page-plot-id w-full rounded border p-2"
    disabled
    data-column={field.column}
    data-help-id="site.plot_number"
    value={owner.plot}
  />
{/snippet}
{#snippet fieldInput(control: PaperControl, _position: string)}
  <TwoPageEntryFieldInput
    {form}
    {control}
    {view}
    {close}
    {childBlocked}
    onstage={stage}
    onselectproject={selectProject}
    onacknowledge={acknowledge}
  />
{/snippet}
{#snippet formPane()}
  {#if view.original && view.snapshot}
    <TwoPageEntryLayout
      {form}
      {pictureReaderAvailable}
      values={twoPageEntryValues(view.original, form)}
      editors={(['xl', 'common', 'extra'] as const).map((scope) => ({
        scope,
        columns: projection.fields
          .filter((field) => field.scope === scope && field.page !== null)
          .map((field) => field.column),
        input: fieldInput,
        labelled: true,
      }))}
      identity={identityField}
      embedded={childContent}
    />
  {/if}
{/snippet}

<section
  class="two-page-entry-shell space-y-4 rounded border border-vpro-border bg-white p-4 text-vpro-ink"
  aria-label="Complete two-page entry review"
  data-two-page-entry-panel={form}
>
  <TwoPageEntryToolbar
    {readers}
    {shrubToggle}
    state={{
      form,
      standalone,
      view,
      close,
      projection,
      childBlocked,
      fieldCardSplitOpen,
      canOpenMetadataEditor: canOpenMetadataEditor(),
      availabilities,
    }}
    handlers={{
      onopenfieldcardmodal: () => {
        fieldCardModalOpen = true;
        fieldCardSplitOpen = false;
      },
      ontoggledocksplit: () => {
        fieldCardSplitOpen = !fieldCardSplitOpen;
        if (fieldCardSplitOpen) fieldCardModalOpen = false;
      },
      onoperation: (action) => void operation(action),
      onclosereview: closeReview,
      oncancel: cancel,
      onopenmetadataeditor: openMetadataEditor,
    }}
  />
  <TwoPageEntryReadersHost
    {readers}
    {owner}
    {form}
    {view}
    {close}
    bind:error
    {childBlocked}
    bind:fieldCardModalOpen
    bind:fieldCardSplitOpen
    fieldCardViewModel={twoPageFieldCardViewModel}
    {onOpenProfileSU}
    onclosemetadataeditor={() => {
      readers.projectMetadataOpen = null;
      error = null;
      onchange();
    }}
    onrestoredaudit={async () => {
      await session.load();
      await readers.refreshMetadataPeers();
    }}
    {formPane}
  />
</section>

<style>
  .two-page-entry-shell {
    border-color: var(--vpro-border);
    border-top: 3px solid var(--vpro-gold);
  }
  .two-page-plot-id {
    font-family: var(--vpro-font-mono, monospace);
    font-variant-numeric: tabular-nums;
    font-weight: 600;
    border-color: var(--vpro-forest-border);
  }
</style>
