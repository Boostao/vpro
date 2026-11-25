<script lang="ts">
  import { Columns2, FileText, Lock, RotateCcw, Save, Unlock } from '@lucide/svelte';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import type { FS882Controller } from './fs882FormController.svelte';

  let {
    ctrl,
    canManagePlot,
    onFindPlot,
    onClosed,
    onToggleLock,
    onUndo,
    onSave,
  }: {
    ctrl: FS882Controller;
    canManagePlot: boolean;
    onFindPlot?: () => void;
    onClosed?: () => void;
    onToggleLock: () => void;
    onUndo: () => void;
    onSave: () => void;
  } = $props();

  const hidden = $derived(ctrl.standaloneTwoPage && ctrl.twoPageOpen && ctrl.twoPageScope === 'entry');
  const siviStandalone = $derived(ctrl.siviStandalone);
  const locked = $derived(ctrl.draft.locked);
  const hasValidationErrors = $derived(Object.keys(ctrl.headerValidation).length > 0);
  const reviewDisabled = $derived(ctrl.childParentDisabled || ctrl.childUnsaved || hasValidationErrors);
  const activeSUNone = $derived(ctrl.pState?.activeSU === 'None');
  const plotProfileWritable = $derived(ctrl.pState?.plotProfile?.writable === true);
  const profileEditBlockedByPeer = $derived(
    ctrl.metadataOpen ||
      ctrl.codeCheckOpen ||
      ctrl.children.personalDraft !== null ||
      ctrl.children.deletionReview !== null ||
      ctrl.children.creationDraft !== null
  );
  const siviLockBlocked = $derived(
    siviStandalone &&
      (!ctrl.sivi.parentView?.original ||
        Boolean(ctrl.sivi.parentView?.error) ||
        ctrl.childUnsaved ||
        ctrl.sivi.sourceBarrier)
  );
  const siviSaveBlocked = $derived(siviStandalone && !ctrl.getCloseState().canSave);
</script>

<header
  {hidden}
  class="fs882-toolbar p-3 bg-vpro-canvas border-b border-vpro-border flex flex-wrap justify-between items-center gap-2"
>
  <div class="flex items-center gap-3">
    <h2 data-help-id={siviStandalone ? 'sivi.plot_type' : 'site.plot_number'} class="font-bold text-vpro-ink text-base">
      {siviStandalone
        ? IS_WEB_READONLY
          ? 'SIVI / FS1333: Site Visit Viewer'
          : 'SIVI / FS1333: Site Visit'
        : IS_WEB_READONLY
          ? 'FS882-6x4XL: Ecosystem Plot Viewer'
          : 'FS882-6x4XL: Ecosystem Field Form'}
    </h2>
    {#if IS_WEB_READONLY}
      <span class="px-2 py-0.5 rounded text-xs font-semibold bg-vpro-rail text-vpro-navy" data-fs882-readonly-badge>
        Read-Only
      </span>
    {:else}
      <span
        class="px-2 py-0.5 rounded text-xs font-semibold {ctrl.effectiveFormDirty
          ? 'bg-amber-100 text-amber-800'
          : 'bg-vpro-rail text-vpro-ink-secondary'}"
      >
        {ctrl.effectiveFormDirty ? 'Draft Unsaved' : 'Clean'}
      </span>
      {#if locked}
        <span class="px-2 py-0.5 rounded text-xs font-semibold bg-red-100 text-red-700 flex items-center gap-1">
          <Lock size={12} /> Locked (Read-Only)
        </span>
      {/if}
    {/if}
  </div>
  <div class="fs882-actions flex flex-wrap items-center gap-2">
    {#if !siviStandalone}
      {#if !IS_WEB_READONLY}
        <button
          type="button"
          data-two-page-review
          class="px-3 py-1 rounded text-xs border border-vpro-border bg-white disabled:opacity-50"
          disabled={reviewDisabled}
          onclick={() => ctrl.openTwoPageReview('extra')}>Two-page additional fields</button
        >
        <button
          type="button"
          data-two-page-common-review
          class="px-3 py-1 rounded text-xs border border-vpro-border bg-white disabled:opacity-50"
          disabled={reviewDisabled}
          onclick={() => ctrl.openTwoPageReview('common')}>Two-page common fields</button
        >
      {/if}
      <button
        type="button"
        data-two-page-entry-review
        class="px-3 py-1 rounded text-xs border border-vpro-border bg-white disabled:opacity-50"
        disabled={reviewDisabled}
        onclick={() => ctrl.openTwoPageReview('entry')}
        >{IS_WEB_READONLY ? 'Two-page plot viewer' : 'Complete two-page entry'}</button
      >
      {#if !IS_WEB_READONLY}
        <button
          type="button"
          data-source-control="btnEnvIntoSu"
          class="px-3 py-1 rounded text-xs border border-vpro-border bg-white disabled:opacity-50"
          disabled={reviewDisabled || activeSUNone}
          onclick={() => ctrl.openEnvironmentSU()}>Env Into SU</button
        >
        {#if !ctrl.separateSUSelected}
          <button
            type="button"
            data-source-control="btnSuIntoEnv"
            class="px-3 py-1 rounded text-xs border border-vpro-border bg-white disabled:opacity-50"
            disabled={reviewDisabled || activeSUNone}
            onclick={() => ctrl.openEnvironmentSU('reverse')}>SU Into Env</button
          >
        {:else if !ctrl.twoPageOpen}
          <button
            type="button"
            data-source-control="btnSuIntoEnv"
            data-external-su-environment-open
            class="px-3 py-1 rounded text-xs border border-vpro-border bg-white disabled:opacity-50"
            disabled={reviewDisabled}
            onclick={ctrl.openExternalSUEnvironment}>SU Into Env: separate file</button
          >
        {/if}
      {/if}
    {/if}
    {#if onFindPlot}
      <button
        type="button"
        class="px-3 py-1 rounded text-xs border border-vpro-border bg-white disabled:opacity-50"
        disabled={ctrl.busy || ctrl.headerWorkflowBusy || !ctrl.capabilitiesReady}
        onclick={onFindPlot}>Find Plot</button
      >
    {/if}
    {#if !IS_WEB_READONLY && ctrl.original !== null && !siviStandalone && canManagePlot}
      <button
        type="button"
        data-manage-plot-btn
        aria-expanded={ctrl.managePlotOpen}
        class="px-3 py-1 rounded text-xs border border-vpro-border bg-white hover:bg-vpro-surface-subtle disabled:opacity-50"
        disabled={ctrl.busy ||
          ctrl.headerWorkflowBusy ||
          ctrl.dirty ||
          ctrl.childUnsaved ||
          locked ||
          !ctrl.capabilitiesReady}
        onclick={() => {
          ctrl.managePlotOpen = !ctrl.managePlotOpen;
        }}>Manage Plot #</button
      >
    {/if}
    <button
      type="button"
      data-project-profile-review-open
      class="px-3 py-1 rounded text-xs border border-vpro-border bg-white disabled:opacity-50"
      disabled={ctrl.busy ||
        ctrl.headerWorkflowBusy ||
        ctrl.sivi.sourceBarrier ||
        ctrl.profileReviewOpen ||
        !ctrl.capabilitiesReady ||
        (plotProfileWritable && profileEditBlockedByPeer)}
      onclick={ctrl.openProfileReviewFromToolbar}
    >
      {plotProfileWritable ? 'Review project profile rules' : 'Review project profile (read-only)'}
    </button>
    <button
      type="button"
      data-view-field-card-btn
      title="Preview official printed field card (Alt+P)"
      onclick={() => {
        ctrl.fieldCardModalOpen = true;
        ctrl.fieldCardSplitOpen = false;
      }}
      class="px-3 py-1 rounded text-xs font-semibold border border-vpro-navy bg-vpro-navy-tint text-vpro-navy hover:bg-vpro-navy hover:text-white flex items-center gap-1.5"
    >
      <FileText size={14} /> View Field Card
    </button>
    <button
      type="button"
      data-dock-field-card-btn
      aria-pressed={ctrl.fieldCardSplitOpen}
      title="Toggle live side-by-side split field card preview (>= 1760px)"
      onclick={() => {
        ctrl.fieldCardSplitOpen = !ctrl.fieldCardSplitOpen;
        if (ctrl.fieldCardSplitOpen) ctrl.fieldCardModalOpen = false;
      }}
      class="dock-field-card-btn px-3 py-1 rounded text-xs font-semibold border flex items-center gap-1.5 {ctrl.fieldCardSplitOpen
        ? 'bg-vpro-navy text-white border-vpro-navy'
        : 'border-vpro-border bg-white text-vpro-navy hover:bg-vpro-navy-tint'}"
    >
      <Columns2 size={14} /> Dock Split View
    </button>
    {#if !IS_WEB_READONLY}
      <button
        type="button"
        onclick={onToggleLock}
        disabled={ctrl.busy || ctrl.headerWorkflowBusy || !ctrl.capabilitiesReady || siviLockBlocked}
        class="px-3 py-1 rounded text-xs font-medium border flex items-center gap-1 {locked
          ? 'bg-vpro-rail hover:bg-vpro-border border-vpro-border'
          : 'bg-vpro-canvas hover:bg-vpro-rail border-vpro-border'}"
        title={locked ? 'Unlock Form' : 'Lock Form'}
      >
        {#if locked}<Unlock size={14} /> Unlock{:else}<Lock size={14} /> Lock{/if}
      </button>
      <button
        type="button"
        onclick={onUndo}
        disabled={(!ctrl.dirty && !ctrl.childUnsaved) ||
          locked ||
          ctrl.busy ||
          ctrl.headerWorkflowBusy ||
          !ctrl.capabilitiesReady}
        class="px-3 py-1 rounded text-xs font-medium border border-vpro-border bg-white hover:bg-vpro-surface-subtle disabled:opacity-50 flex items-center gap-1"
      >
        <RotateCcw size={14} /> Undo
      </button>
      <button
        type="button"
        onclick={onSave}
        disabled={(!ctrl.dirty && !ctrl.childUnsaved) ||
          locked ||
          ctrl.busy ||
          ctrl.headerWorkflowBusy ||
          !ctrl.capabilitiesReady ||
          siviSaveBlocked}
        class="px-3 py-1 rounded text-xs font-medium bg-vpro-navy hover:bg-vpro-navy-dark text-white disabled:opacity-50 flex items-center gap-1"
      >
        <Save size={14} /> Save
      </button>
    {/if}
    {#if onClosed}
      <button
        type="button"
        aria-label={siviStandalone ? 'Close SIVI form' : 'Close FS882 form'}
        disabled={ctrl.busy || ctrl.headerWorkflowBusy}
        onclick={onClosed}
        class="px-2 py-1 text-vpro-ink-muted hover:text-vpro-ink font-bold ml-2">✕</button
      >
    {/if}
  </div>
</header>
