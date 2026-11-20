<script lang="ts">
  import type { Snippet } from 'svelte';
  import { Columns2, FileText } from '@lucide/svelte';
  import type { EditorCloseState } from '../shell/closeLifecycle';
  import type { TwoPageParentForm } from './twoPageParentSession';
  import type { TwoPageEntryView } from './twoPageEntrySession';
  import type { twoPageEntryProjection } from './twoPageEntryProjection';
  import type { TwoPageEntryReadersController } from './useTwoPageEntryReaders.svelte';

  let {
    readers,
    state: s,
    shrubToggle,
    handlers: h,
  }: {
    readers: TwoPageEntryReadersController;
    state: {
      form: TwoPageParentForm;
      standalone: boolean;
      view: TwoPageEntryView;
      close: EditorCloseState;
      projection: ReturnType<typeof twoPageEntryProjection>;
      childBlocked: boolean;
      fieldCardSplitOpen: boolean;
      canOpenMetadataEditor: boolean;
      availabilities: {
        profiling: boolean;
        projectMetadata: boolean;
        environmentTable: boolean;
        vegetationTable: boolean;
        googleEarth: boolean;
        audit: boolean;
      };
    };
    shrubToggle: Snippet;
    handlers: {
      onopenfieldcardmodal: () => void;
      ontoggledocksplit: () => void;
      onoperation: (action: 'load' | 'save' | 'undo' | 'retain' | 'prune' | 'references') => void;
      onclosereview: () => void;
      oncancel: () => void;
      onopenmetadataeditor: () => void;
      onopenprofilesu?: () => void;
    };
  } = $props();

  const readerBlocked = $derived(readers.draftOrChildBlocked());
  const scopeBad = $derived(readers.vegScopeInvalid());
</script>

<div class="vpro-sticky-bar sticky top-0 z-20 bg-white/95 pb-2 space-y-2" data-two-page-sticky-bar>
  <div class="two-page-entry-header flex flex-wrap items-center justify-between gap-3 border-b border-vpro-border pb-3">
    <div class="flex flex-wrap items-center gap-2.5">
      <h3 class="font-bold text-vpro-navy">
        {s.form === 'FS882-8x6XL-CHARS'
          ? 'FS882 (2-Page, Extended Shrubs): Ecosystem Field Form'
          : 'FS882 (2-Page): Ecosystem Field Form'}
      </h3>
      {#if s.view.original || s.close.unsaved}
        <span
          class="px-2 py-0.5 rounded text-xs font-semibold {s.close.unsaved
            ? 'bg-amber-100 text-amber-800'
            : 'bg-vpro-rail text-vpro-ink-secondary'}"
        >
          {s.close.unsaved ? 'Draft Unsaved' : 'Clean'}
        </span>
      {/if}
    </div>
    <div class="flex flex-wrap items-center gap-2">
      <button
        type="button"
        data-view-field-card-btn
        title="Preview official printed field card (Alt+P)"
        onclick={h.onopenfieldcardmodal}
        class="px-3 py-1 rounded text-xs font-semibold border border-vpro-navy bg-vpro-navy-tint text-vpro-navy hover:bg-vpro-navy hover:text-white flex items-center gap-1.5"
      >
        <FileText size={14} /> View Field Card
      </button>
      <button
        type="button"
        data-dock-field-card-btn
        aria-pressed={s.fieldCardSplitOpen}
        title="Toggle live side-by-side split field card preview (>= 1760px)"
        onclick={h.ontoggledocksplit}
        class="two-page-dock-btn px-3 py-1 rounded text-xs font-semibold border flex items-center gap-1.5 {s.fieldCardSplitOpen
          ? 'bg-vpro-navy text-white border-vpro-navy'
          : 'border-vpro-border bg-white text-vpro-navy hover:bg-vpro-navy-tint'}"
      >
        <Columns2 size={14} /> Dock Split View
      </button>
    </div>
  </div>
  {#if !readers.visible}
    <div
      class="flex flex-wrap items-center justify-between gap-2 rounded border border-vpro-border bg-vpro-surface-subtle p-2"
    >
      <div class="flex flex-wrap items-center gap-1.5">
        <button
          type="button"
          class="rounded bg-vpro-navy hover:bg-vpro-navy-dark px-3 py-1 text-xs font-medium text-white disabled:opacity-50"
          disabled={s.childBlocked || !s.close.canSave || s.close.busy || s.close.blocked}
          onclick={() => h.onoperation('save')}>Save</button
        >
        <button
          type="button"
          class="rounded border border-vpro-border bg-white px-2.5 py-1 text-xs font-medium text-vpro-ink hover:bg-vpro-surface-subtle disabled:opacity-50"
          disabled={s.close.busy}
          onclick={() => h.onoperation('undo')}>Undo</button
        >
        <button
          type="button"
          class="rounded border border-vpro-border bg-white px-2.5 py-1 text-xs font-medium text-vpro-ink hover:bg-vpro-surface-subtle disabled:opacity-50"
          disabled={s.childBlocked || s.close.unsaved || s.close.busy || s.close.blocked}
          onclick={() => h.onoperation('load')}>Reload Plot</button
        >
        <button
          type="button"
          class="rounded border border-vpro-border bg-white px-2.5 py-1 text-xs font-medium text-vpro-ink hover:bg-vpro-surface-subtle disabled:opacity-50"
          disabled={s.close.busy || !s.view.original || s.view.blocked}
          onclick={() => h.onoperation('references')}>Refresh Lists</button
        >
        {@render shrubToggle()}
        <button
          type="button"
          class="rounded border border-vpro-border bg-white px-2.5 py-1 text-xs font-medium text-vpro-ink hover:bg-vpro-surface-subtle disabled:opacity-50"
          disabled={s.childBlocked || s.close.unsaved || s.close.busy || s.close.blocked}
          onclick={h.onclosereview}
        >
          {s.standalone ? 'Close Form' : 'Return to 6x4 Form'}
        </button>
        {#if (s.view.busy && s.view.operation === 'read') || s.view.referencesBusy}
          <button
            type="button"
            class="rounded border border-vpro-border bg-white px-2.5 py-1 text-xs font-medium text-vpro-ink hover:bg-vpro-surface-subtle"
            onclick={h.oncancel}>Cancel Read</button
          >
        {/if}
        {#if s.view.historyId}
          <button
            type="button"
            class="rounded border border-vpro-border bg-white px-2.5 py-1 text-xs font-medium text-vpro-ink hover:bg-vpro-surface-subtle disabled:opacity-50"
            disabled={s.childBlocked || s.close.unsaved || s.close.busy || s.close.blocked}
            onclick={() => h.onoperation('retain')}>Restore (retain audits)</button
          >
          <button
            type="button"
            class="rounded border border-vpro-border bg-white px-2.5 py-1 text-xs font-medium text-vpro-ink hover:bg-vpro-surface-subtle disabled:opacity-50"
            disabled={s.childBlocked || s.close.unsaved || s.close.busy || s.close.blocked}
            onclick={() => h.onoperation('prune')}>Restore (prune audits)</button
          >
        {/if}
      </div>
      <div class="flex flex-wrap items-center gap-1.5">
        <button
          type="button"
          class="rounded border border-vpro-border bg-white px-2.5 py-1 text-xs font-medium text-vpro-ink hover:bg-vpro-surface-subtle disabled:opacity-50"
          data-two-page-project-metadata-edit-open
          data-source-control={s.projection.metadataAction.controlId}
          disabled={!s.canOpenMetadataEditor}
          onclick={h.onopenmetadataeditor}>{s.projection.metadataAction.caption}</button
        >
        {#if s.availabilities.profiling}
          <button
            type="button"
            class="rounded border border-vpro-border bg-white px-2.5 py-1 text-xs font-medium text-vpro-ink hover:bg-vpro-surface-subtle disabled:opacity-50"
            data-two-page-profiling-open
            data-source-control={s.projection.profilingAction.controlId}
            disabled={!readers.profileSource?.name ||
              readers.profileSource.name === 'None' ||
              !readers.profileSource.path ||
              scopeBad ||
              readerBlocked}
            onclick={readers.openProfiling}>{s.projection.profilingAction.caption}</button
          >
        {/if}
        {#if h.onopenprofilesu}
          <button
            type="button"
            class="rounded border border-vpro-border bg-white px-2.5 py-1 text-xs font-medium text-vpro-ink hover:bg-vpro-surface-subtle disabled:opacity-50"
            data-two-page-profile-manage-open
            disabled={readerBlocked}
            onclick={h.onopenprofilesu}
          >
            {!readers.profileSource?.name || readers.profileSource.name === 'None' || !readers.profileSource.path
              ? 'Select Plot Profile'
              : 'Manage Plot Profile'}
          </button>
        {/if}
        {#if s.availabilities.projectMetadata}
          <button
            type="button"
            class="rounded border border-vpro-border bg-white px-2.5 py-1 text-xs font-medium text-vpro-ink hover:bg-vpro-surface-subtle disabled:opacity-50"
            data-two-page-project-metadata-open
            disabled={scopeBad || readerBlocked}
            onclick={readers.openProjectMetadata}>View Project Metadata</button
          >
        {/if}
        {#if s.availabilities.environmentTable}
          <button
            type="button"
            class="rounded border border-vpro-border bg-white px-2.5 py-1 text-xs font-medium text-vpro-ink hover:bg-vpro-surface-subtle disabled:opacity-50"
            data-two-page-environment-table-open
            data-source-control={s.projection.environmentTableAction.controlId}
            disabled={scopeBad || readerBlocked}
            onclick={readers.openEnvironmentTable}>{s.projection.environmentTableAction.caption}</button
          >
        {/if}
        {#if s.availabilities.vegetationTable}
          <button
            type="button"
            class="rounded border border-vpro-border bg-white px-2.5 py-1 text-xs font-medium text-vpro-ink hover:bg-vpro-surface-subtle disabled:opacity-50"
            data-two-page-vegetation-table-open
            data-source-control={s.projection.vegetationTableAction.controlId}
            disabled={scopeBad || readerBlocked}
            onclick={readers.openVegetationTable}>{s.projection.vegetationTableAction.caption}</button
          >
        {/if}
        {#if s.availabilities.googleEarth}
          <button
            type="button"
            class="rounded border border-vpro-border bg-white px-2.5 py-1 text-xs font-medium text-vpro-ink hover:bg-vpro-surface-subtle disabled:opacity-50"
            data-two-page-google-earth-open
            data-source-control={s.projection.googleEarthAction.controlId}
            disabled={!readers.googleEarthPath || readerBlocked}
            onclick={readers.openGoogleEarth}>{s.projection.googleEarthAction.caption} (KML)</button
          >
        {/if}
        {#if s.availabilities.audit}
          <button
            type="button"
            class="rounded border border-vpro-border bg-white px-2.5 py-1 text-xs font-medium text-vpro-ink hover:bg-vpro-surface-subtle disabled:opacity-50"
            data-two-page-audit-open
            data-source-control={s.projection.auditAction.controlId}
            disabled={readerBlocked}
            onclick={readers.openAudit}>{s.projection.auditAction.caption}</button
          >
        {/if}
        {#if readers.sourceScope}
          <button
            type="button"
            class="rounded border border-vpro-border bg-white px-2.5 py-1 text-xs font-medium text-vpro-ink hover:bg-vpro-surface-subtle disabled:opacity-50"
            data-source-control={s.projection.reverseAction.controlId}
            data-two-page-su-environment-open
            disabled={readerBlocked}
            onclick={readers.openExternalTransfer}>{s.projection.reverseAction.caption} (External SU)</button
          >
        {/if}
      </div>
    </div>
  {/if}
</div>

<style>
  @media (max-width: 1759px) {
    .two-page-dock-btn {
      display: none;
    }
  }
</style>
