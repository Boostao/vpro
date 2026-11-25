<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import type { ProjectMetadataCreate, ProjectMetadataEditorField } from '../../bindings/github.com/boostao/vpro/app';
  import type { ProjectMetadataReview } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
  import type { bindContextPlots } from '../shared/contextPlots';
  import type { EditorCloseState } from '../shell/closeLifecycle';
  import { ReadRequests, formatError } from '../shared/readRequests';
  import * as metaEd from './projectMetadataEditor';
  import {
    beginMetadataDraft,
    beginMetadataTemplate,
    metadataBlankRequest,
    metadataTemplateRequest,
    type MetadataDraft,
    type MetadataTemplateDraft,
  } from './projectMetadataEditor';
  import { metadataGroups, metadataLabel } from './projectMetadataPresentation';
  import ProjectMetadataCreationPanel from './ProjectMetadataCreationPanel.svelte';
  import ProjectMetadataFieldsPanel from './ProjectMetadataFieldsPanel.svelte';
  import ProjectMetadataRestore from './ProjectMetadataRestore.svelte';
  import { notifications } from '../shell/notificationService.svelte';

  const IS_WEB_READONLY = typeof __VPRO_WEB_READONLY__ !== 'undefined' && __VPRO_WEB_READONLY__ === true;

  let {
    client,
    contextId,
    plot,
    onclosed,
    onbusy,
    oncommitted,
    allowCreation = false,
    allowTemplateCreation = false,
    allowRestoration = false,
  }: {
    client: ReturnType<typeof bindContextPlots>;
    contextId: string;
    plot: string;
    onclosed: () => void;
    onbusy: (busy: boolean) => void;
    oncommitted: () => Promise<void>;
    allowCreation?: boolean;
    allowTemplateCreation?: boolean;
    allowRestoration?: boolean;
  } = $props();

  const BTN_CLS =
    'm-0.5 rounded border border-vpro-border-strong bg-white px-3 py-2 font-semibold text-vpro-navy aria-pressed:border-vpro-navy aria-pressed:bg-vpro-navy-tint disabled:cursor-not-allowed disabled:opacity-50';
  const creationCatalog = metaEd.makeCreationCatalog(
    metadataLabel,
    'Review 32 assignments from master record',
    'All 73 other source fields, including version/date stamps, remain NULL. No master template is copied. A reserved signed32 ID is allocated only by the creation transaction.'
  );
  const fieldsCatalog = metaEd.makeFieldsCatalog(metadataGroups, metadataLabel);

  let review = $state<ProjectMetadataReview | null>(null);
  let fields = $state<ProjectMetadataEditorField[]>([]);
  let draft = $state<MetadataDraft | null>(null);
  let blank = $state<ProjectMetadataCreate | null>(null);
  let template = $state<MetadataTemplateDraft | null>(null);
  let reading = $state(false);
  let ready = $state(false);
  let standardPreview = $state(false);
  let saving = $state(false);
  let committedFailure = $state(false);
  let error = $state<string | null>(null);
  let success = $state<string | null>(null);
  let restorationOpen = $state(false);
  let restorationBusy = $state(false);
  let restorationEditor: ProjectMetadataRestore | undefined = $state();
  let generation = 0;

  const reads = new ReadRequests();
  const busy = $derived(reading || saving || restorationBusy);
  const errors = $derived(draft ? metaEd.metadataErrors(draft) : template ? metaEd.metadataErrors(template) : []);
  const dirty = $derived(blank !== null || template !== null || (draft ? metaEd.metadataDirty(draft) : false));
  const standardDecision = $derived(draft ? metaEd.metadataStandardDecisionRequired(draft) : false);
  const saveBlocked = $derived(
    errors.length > 0 || committedFailure || standardPreview || (standardDecision && !draft?.standardPopulation)
  );
  const rows = $derived(review?.projectRecords.rows ?? []);
  const available = $derived.by(() => {
    const columns = new Set(review?.projectRecords.columns?.map((column) => column.name));
    return fields.filter((field) => columns.has(field.name));
  });

  $effect(() => onbusy(busy));
  onMount(() => void reload());
  onDestroy(() => {
    generation++;
    reads.cancelAll();
    onbusy(false);
  });

  function notifyMetadata(severity: 'success' | 'error', title: string, message: string) {
    notifications[severity](title, message, {
      category: 'admin',
      source: 'Project Metadata',
      contextTag: review?.project || (plot ? `Plot ${plot}` : undefined),
    });
  }

  export function hasUnsavedChanges(): boolean {
    return dirty || errors.length > 0 || committedFailure || restorationOpen;
  }

  export function getCloseState(): EditorCloseState {
    const restFallback = metaEd.buildMetadataCloseState(true, undefined, busy, error, false);
    if (restorationOpen) return restorationEditor?.getCloseState() ?? restFallback;
    return metaEd.buildMetadataCloseState(false, undefined, busy, error, committedFailure || errors.length > 0);
  }

  export function undo() {
    if (restorationOpen) return restorationEditor?.undo();
    if (busy) {
      error = 'Wait for the current metadata operation before Undo.';
      return;
    }
    if (committedFailure) {
      error = 'Reload the committed metadata refresh before Undo or close; completed writes must not be replayed.';
      return;
    }
    if (template) {
      template = null;
      error = null;
      success = 'Template creation proposal undone; no record, identity or history was allocated.';
    } else if (blank) {
      blank = null;
      error = null;
      success = 'Blank creation proposal undone; no record, identity or history was allocated.';
    } else if (draft && !committedFailure) {
      draft = beginMetadataDraft(draft.review, draft.original.rowId);
      standardPreview = false;
      error = null;
      success = 'Metadata drafts undone; no data or history changed.';
    } else onclosed();
  }

  function reviewBlank() {
    if (!allowCreation || !ready || !review || busy || dirty || committedFailure) {
      error = 'Reload an available empty metadata review before proposing blank creation.';
      return;
    }
    try {
      blank = metadataBlankRequest(review);
      error = null;
      success = null;
    } catch (cause) {
      error = `Blank creation proposal unavailable; no data changed: ${formatError(cause)}`;
    }
  }

  async function createBlank() {
    if (!allowCreation || !ready || !blank || busy || committedFailure) {
      error = 'Explicitly review the empty metadata proposal before creation.';
      notifyMetadata('error', 'Blank metadata creation blocked', error);
      return;
    }
    let committed = false;
    saving = true;
    error = null;
    success = null;
    try {
      const created = await client.CreateBlankProjectMetadata(blank);
      committed = true;
      blank = null;
      await oncommitted();
      const next = await client.ReviewProjectMetadata(plot);
      review = next;
      draft = beginMetadataDraft(next, created.rowId);
      success =
        'Blank metadata record and full creation audit committed atomically. All 73 ordinary/stamp fields remain NULL; edit and Save separately.';
      notifyMetadata('success', 'Blank metadata record created', success);
    } catch (cause) {
      const detail = formatError(cause);
      if (committed || detail.includes('metadata edit committed, but')) {
        committedFailure = true;
        blank = null;
        draft = null;
        error = `Metadata creation committed, but refresh/cleanup failed. Reload before another edit; completed writes must not be replayed: ${detail}`;
      } else error = `Blank metadata creation failed; reviewed proposal retained for retry: ${detail}`;
      notifyMetadata('error', committed ? 'Blank metadata refresh failed' : 'Blank metadata creation failed', error);
    } finally {
      saving = false;
    }
  }

  function reviewTemplate(rowId: string) {
    if (!allowTemplateCreation || !ready || !review || busy || dirty || committedFailure) {
      error = 'Reload an available empty metadata review before selecting a master template.';
      return;
    }
    try {
      template = beginMetadataTemplate(review, rowId, available);
      error = null;
      success = null;
    } catch (cause) {
      error = `Template proposal unavailable; no data changed: ${formatError(cause)}`;
    }
  }

  function stageTemplate(field: ProjectMetadataEditorField, raw: string, nullValue: boolean) {
    if (!ready || !template || busy || committedFailure) {
      error = 'Reload available metadata before reviewing template assignments.';
      return;
    }
    try {
      template = metaEd.stageMetadataTemplate(template, field, raw, nullValue);
      error = null;
      success = null;
    } catch (cause) {
      error = `Template draft failed; proposal retained: ${formatError(cause)}`;
    }
  }

  async function createTemplate() {
    if (!allowTemplateCreation || !ready || !template || busy || committedFailure || errors.length) {
      error = 'Resolve all explicit template assignments before creation; raw errors were retained.';
      notifyMetadata('error', 'Template metadata creation blocked', error);
      return;
    }
    let committed = false;
    saving = true;
    error = null;
    success = null;
    try {
      const created = await client.CreateProjectMetadataFromTemplate(metadataTemplateRequest(template));
      committed = true;
      template = null;
      await oncommitted();
      const next = await client.ReviewProjectMetadata(plot);
      review = next;
      draft = beginMetadataDraft(next, created.rowId);
      success =
        'One reviewed template record and full creation audit committed atomically. Unmapped fields/stamps remain NULL; ordinary editing and Save are separate.';
      notifyMetadata('success', 'Template metadata record created', success);
    } catch (cause) {
      const detail = formatError(cause);
      if (committed || detail.includes('metadata edit committed, but')) {
        committedFailure = true;
        template = null;
        draft = null;
        error = `Template creation committed, but refresh/cleanup failed. Reload before another edit; completed writes must not be replayed: ${detail}`;
      } else error = `Template creation failed; reviewed assignments retained for retry: ${detail}`;
      notifyMetadata(
        'error',
        committed ? 'Template metadata refresh failed' : 'Template metadata creation failed',
        error
      );
    } finally {
      saving = false;
    }
  }

  async function reload() {
    if (saving || dirty) {
      error = 'Save or Undo metadata drafts before reloading; raw errors were retained.';
      return;
    }
    const request = ++generation;
    reads.cancelAll();
    reading = true;
    ready = false;
    error = null;
    try {
      if (committedFailure) await oncommitted();
      if (request !== generation) return;
      const [next, definitions] = await Promise.all([
        reads.track(client.ReviewProjectMetadata(plot)),
        reads.track(client.ListProjectMetadataFields()),
      ]);
      if (request !== generation) return;
      if (!next.projectRecords.columns || !next.projectRecords.rows || !definitions?.length) {
        throw new Error('Complete metadata records and source field definitions are required.');
      }
      review = next;
      fields = definitions;
      draft = null;
      committedFailure = false;
      ready = true;
      standardPreview = false;
    } catch (cause) {
      if (request === generation) {
        error = `Metadata review/references unavailable; no data changed: ${formatError(cause)}`;
        notifyMetadata('error', 'Metadata reload failed', error);
      }
    } finally {
      if (request === generation) reading = false;
    }
  }

  function select(rowId: string) {
    if (!ready || !review || busy || dirty || committedFailure) {
      error =
        'Reload available metadata and references, then Save or Undo the existing draft before selecting another physical record.';
      return;
    }
    try {
      draft = beginMetadataDraft(review, rowId);
      standardPreview = false;
      error = null;
      success = null;
    } catch (cause) {
      error = `Metadata selection failed: ${formatError(cause)}`;
    }
  }

  function stage(field: ProjectMetadataEditorField, raw: string, nullValue: boolean) {
    if (!ready || !draft || busy || committedFailure) {
      error = 'Reload available metadata and references before editing.';
      return;
    }
    try {
      draft = metaEd.stageMetadata(draft, field, raw, nullValue);
      if (field.name === 'EcosysCollectionStandard') standardPreview = false;
      error = null;
      success = null;
    } catch (cause) {
      error = `Metadata draft failed; entry retained: ${formatError(cause)}`;
    }
  }

  function populateStandard() {
    if (!ready || !draft || busy || committedFailure || !standardPreview) {
      error = 'Review the available source defaults before applying them to drafts.';
      return;
    }
    try {
      draft = standardDecision
        ? metaEd.populateMetadataStandard(draft, available)
        : metaEd.applyCanonicalStandardDefaults(draft, available);
      standardPreview = false;
      error = null;
      success =
        '24 canonical LMH25/NAD83 source defaults staged, not saved. Other drafts and raw errors were retained; review before Save.';
    } catch (cause) {
      error = `Source-default proposal failed; drafts retained: ${formatError(cause)}`;
    }
  }

  async function save() {
    if (!ready || !draft || busy || committedFailure) {
      error = 'Reload available metadata and references, then select an existing record before metadata Save.';
      notifyMetadata('error', 'Metadata save blocked', error);
      return;
    }
    if (standardPreview) {
      error = 'Apply or cancel the source-default preview before metadata Save.';
      notifyMetadata('error', 'Metadata save blocked', error);
      return;
    }
    let committed = false;
    saving = true;
    error = null;
    success = null;
    try {
      const request = metaEd.metadataEditRequest(draft);
      await client.SaveProjectMetadata(request);
      committed = true;
      draft = null;
      standardPreview = false;
      await oncommitted();
      const next = await client.ReviewProjectMetadata(plot);
      review = next;
      draft = beginMetadataDraft(next, request.original.rowId);
      success =
        'Metadata fields, version/date stamps and applicable audits saved atomically. Other candidates and master templates were not copied.';
      notifyMetadata('success', 'Project metadata saved', success);
    } catch (cause) {
      const detail = formatError(cause);
      if (committed || detail.includes('metadata edit committed, but')) {
        committedFailure = true;
        draft = null;
        error = `Metadata committed, but refresh/cleanup failed. Reload before another edit; completed writes must not be replayed: ${detail}`;
      } else error = `Metadata Save failed; raw drafts retained for correction or retry: ${detail}`;
      notifyMetadata(
        'error',
        committed ? 'Metadata refresh failed after commit' : 'Project metadata save failed',
        error
      );
    } finally {
      saving = false;
    }
  }

  function handleKeydown(event: KeyboardEvent) {
    if ((event.ctrlKey || event.metaKey) && !event.altKey && !event.shiftKey && event.key.toLowerCase() === 's') {
      event.preventDefault();
      if (!restorationOpen && ready && !busy && draft && dirty && !saveBlocked) void save();
    }
  }

  function close() {
    if (busy || dirty || errors.length || committedFailure) {
      error =
        'Save or Undo metadata drafts, or reload the committed refresh before closing; invalid raw entries and recovery cannot be discarded implicitly.';
      return;
    }
    onclosed();
  }
</script>

<svelte:window onkeydown={handleKeydown} />

<section
  class="my-4 min-w-0 rounded-xl border border-vpro-border bg-white p-4 text-vpro-ink"
  aria-label="Project metadata editor"
  data-metadata-editor
>
  <header>
    <h2 class="text-xl font-semibold text-vpro-navy">Project metadata — {review?.project ?? 'loading'}</h2>
    <p>
      Plot {plot}; Project ID {review?.projectId === null
        ? 'NULL (existing editing unavailable)'
        : JSON.stringify(review?.projectId)}
    </p>
  </header>
  {#if error}<p class="text-vpro-error" role="alert">{error}</p>{/if}
  {#if success}<p class="text-vpro-success" role="status">{success}</p>{/if}
  {#if errors.length}<ul class="text-vpro-error" role="alert">
      {#each errors as message}<li>{message}</li>{/each}
    </ul>{/if}
  {#if busy}<p role="status">
      {saving ? 'Saving metadata transaction…' : 'Loading metadata records and source references…'}
    </p>{/if}
  {#if restorationOpen}
    <ProjectMetadataRestore
      bind:this={restorationEditor}
      {client}
      {contextId}
      {plot}
      onbusy={(value) => (restorationBusy = value)}
      onclosed={() => {
        restorationOpen = false;
        error = null;
      }}
      oncommitted={async (rowId) => {
        await oncommitted();
        const next = await client.ReviewProjectMetadata(plot);
        review = next;
        draft = beginMetadataDraft(next, rowId);
        standardPreview = false;
      }}
    />
  {:else}
    <div
      data-workbench-sticky-bar
      class="my-4 flex flex-wrap gap-2 sticky top-0 z-20 border-b border-vpro-border bg-white/95 py-2 backdrop-blur-xs"
    >
      {#if !IS_WEB_READONLY && allowRestoration}
        <button
          type="button"
          class={BTN_CLS}
          disabled={!ready || busy || dirty || errors.length > 0 || committedFailure || standardPreview}
          onclick={() => {
            restorationOpen = true;
            error = null;
            success = null;
          }}>Review typed metadata restoration</button
        >
      {/if}
      <button type="button" class={BTN_CLS} onclick={reload} disabled={busy || dirty}
        >Reload metadata and references</button
      >
      {#if !IS_WEB_READONLY}
        {#if draft}<button
            type="button"
            class={BTN_CLS}
            data-metadata-populate-standard
            disabled={!ready || busy || committedFailure}
            onclick={() => (standardPreview = true)}>Populate Standard (LMH25 NAD83)</button
          >{/if}
        <button type="button" class={BTN_CLS} onclick={undo} disabled={busy || committedFailure}
          >Undo metadata drafts</button
        >
        <button type="button" class={BTN_CLS} onclick={save} disabled={!ready || busy || !draft || !dirty || saveBlocked}
          >Save metadata</button
        >
      {/if}
      <button
        type="button"
        class={BTN_CLS}
        onclick={close}
        disabled={busy || dirty || errors.length > 0 || committedFailure}>Close metadata review</button
      >
    </div>

    <fieldset
      class="my-4 min-w-0 rounded-lg border border-vpro-border p-4"
      disabled={!ready || busy || dirty || committedFailure}
    >
      <legend class="px-1.5 font-semibold text-vpro-navy">Select an existing physical record explicitly</legend>
      {#each rows as row (row.rowId)}
        <button
          type="button"
          class={BTN_CLS}
          data-metadata-row={row.rowId}
          aria-pressed={draft?.original.rowId === row.rowId}
          onclick={() => select(row.rowId)}>Record {row.rowId}: {metaEd.metadataRowSummary(review, row)}</button
        >
      {:else}
        <p>
          No matching existing metadata records. {allowCreation || allowTemplateCreation
            ? 'Review an explicitly enabled creation proposal below.'
            : 'New/blank/template proposals remain unavailable.'}
        </p>
      {/each}
    </fieldset>

    {#if !IS_WEB_READONLY}
      <ProjectMetadataCreationPanel
        {ready}
        {busy}
        {dirty}
        {committedFailure}
        errorsCount={errors.length}
        {allowCreation}
        {allowTemplateCreation}
        hasExistingRows={rows.length > 0}
        {review}
        {blank}
        {template}
        {available}
        catalog={creationCatalog}
        onreviewblank={reviewBlank}
        oncreateblank={() => void createBlank()}
        onreviewtemplate={reviewTemplate}
        onstagetemplate={stageTemplate}
        oncreatetemplate={() => void createTemplate()}
      />
    {/if}

    <ProjectMetadataFieldsPanel
      {ready}
      {busy}
      {committedFailure}
      {standardDecision}
      bind:standardPreview
      {draft}
      {review}
      {available}
      catalog={fieldsCatalog}
      onstage={stage}
      onpopulatestandard={populateStandard}
      ontogglestandardkeep={(keep) => {
        if (draft) draft = { ...draft, standardPopulation: keep ? 'keep' : '' };
      }}
    />
  {/if}
</section>
