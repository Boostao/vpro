<script lang="ts">
  import { AlertTriangle } from '@lucide/svelte';
  import { untrack, type Snippet } from 'svelte';
  import { projectState } from '../shared/state';
  import { notifications } from '../shell/notificationService.svelte';
  import FormValidationSummary from './FormValidationSummary.svelte';
  import FS882ManagePlotBar from './FS882ManagePlotBar.svelte';
  import type { FS882SubEditorLoaders } from './FS882Modals.svelte';
  import FS882Toolbar from './FS882Toolbar.svelte';
  import FS882TwoPagePlotPrompt from './FS882TwoPagePlotPrompt.svelte';
  import FS882WorkspaceBody from './FS882WorkspaceBody.svelte';
  import type { FormValidationItem } from './formValidationSummary';
  import {
    createFS882Controller,
    type FS882DiagnosticsState,
    type FS882FormBaseProps,
  } from './fs882FormController.svelte';
  import type { EditorCloseState } from './fs882FormSivi';

  let {
    plotNumber,
    contextId,
    onSaved,
    onClosed,
    onBusyChange,
    onProfileNavigation,
    onProfileSUReview,
    onFindPlot,
    onOpenPictureManager,
    onDiagnosticsContextChange,
    entryForm = 'fs882',
    availablePlots = [],
    onSelectPlotForTwoPage,
    onSwitchTo6x4NewPlot,
    canUndoPlotDelete = false,
    onCopyPlotToNumber,
    onRemovePlotAction,
  }: FS882FormBaseProps & {
    entryForm?: 'fs882' | 'sivi' | 'fs882-twopage';
    onOpenPictureManager?: (plotNumber: string) => void;
    onDiagnosticsContextChange?: (state: FS882DiagnosticsState) => void;
  } = $props();

  const EXTENDED_SHRUB_NOTICE =
    'Extended shrubs use cover mode (Cover5a–Cover5c only; Height5a–Height5c height fields are disabled). Turn this option off to use height mode; hidden values, drafts and errors are retained.';

  const subEditorLoaders: FS882SubEditorLoaders = {
    environmentSU: () => import('../classification/EnvironmentSUTransfer.svelte'),
    externalSU: () => import('../classification/ExternalSUEnvironmentTransfer.svelte'),
    profileReview: () => import('../classification/ProjectPlotProfileReview.svelte'),
    twoPageEntry: () => import('./TwoPageEntryEditor.svelte'),
    twoPageCommon: () => import('./TwoPageParentCommonEditor.svelte'),
    twoPageExtra: () => import('./TwoPageParentEditor.svelte'),
    twoPageSoil: () => import('./TwoPageSoilPanel.svelte'),
    twoPageVegetation: () => import('./TwoPageVegetationPanel.svelte'),
    projectMetadata: () => import('../admin/ProjectMetadataEditor.svelte'),
    speciesCodeCheck: () => import('./SpeciesCodeCheck.svelte'),
  };

  let successMsg = $state<string | null>(null);
  let autoOpenedTwoPageKey = $state<string | null>(null);

  const ctrl = createFS882Controller({
    contextId: untrack(() => contextId),
    getEntryForm: () => entryForm,
    getPlotNumber: () => plotNumber,
    getProjectState: () => $projectState,
    setSuccess: (msg, markNotified = false) => {
      successMsg = msg;
      if (markNotified && msg) lastNotifiedSuccessMsg = msg;
    },
    onSaved: (p) => onSaved?.(p),
    onBusyChange: (b) => onBusyChange?.(b),
    onDiagnosticsContextChange: (s) => onDiagnosticsContextChange?.(s),
  });

  const draft = $derived(ctrl.draft);
  const siviStandalone = $derived(ctrl.siviStandalone);
  const twoPageOpen = $derived(ctrl.twoPageOpen);
  const twoPageScope = $derived(ctrl.twoPageScope);
  const otherHeaderWorkflowBusy = $derived(ctrl.otherHeaderWorkflowBusy);
  const headerWorkflowBusy = $derived(ctrl.headerWorkflowBusy);
  const tabWorkflowBusy = $derived(ctrl.tabWorkflowBusy);
  const siviCreationPeerUnsaved = $derived(ctrl.siviCreationPeerUnsaved);
  const nonParentChildUnsaved = $derived(ctrl.nonParentChildUnsaved);
  const childUnsaved = $derived(ctrl.childUnsaved);
  const nonArcticHeaderDirty = $derived(ctrl.nonArcticHeaderDirty);

  $effect(() => {
    if (entryForm !== 'fs882-twopage') {
      autoOpenedTwoPageKey = null;
      return;
    }
    const loadedPlot = ctrl.original?.plotNumber ?? null;
    const activeProject = $projectState?.activeProject ?? null;
    if (
      !loadedPlot ||
      !activeProject ||
      $projectState?.contextId !== ctrl.siviContextId ||
      siviStandalone ||
      ctrl.childParentDisabled ||
      twoPageOpen ||
      childUnsaved ||
      ctrl.dirty ||
      Object.keys(ctrl.headerValidation).length > 0
    ) {
      if (!loadedPlot) autoOpenedTwoPageKey = null;
      return;
    }
    const key = `${ctrl.siviContextId}:${activeProject}:${loadedPlot}`;
    if (autoOpenedTwoPageKey === key) return;
    autoOpenedTwoPageKey = key;
    ctrl.openTwoPageReview('entry');
  });

  let lastNotifiedSuccessMsg: string | null = null;
  $effect(() => {
    const msg = successMsg;
    if (!msg) {
      lastNotifiedSuccessMsg = null;
      return;
    }
    if (msg === lastNotifiedSuccessMsg) return;
    lastNotifiedSuccessMsg = msg;
    const plot = untrack(() => draft.plotNumber);
    notifications.success(msg, '', {
      category: 'entry',
      source: 'FS882 Form',
      contextTag: plot ? `Plot ${plot}` : undefined,
    });
  });

  function loadSubEditor<T>(loader: () => Promise<T>, label: string, onFailed: () => void): Promise<T> {
    return ctrl.loadSubEditor(loader, label, onFailed);
  }
  function sourceEnter(event: KeyboardEvent) {
    ctrl.sourceEnter(event);
  }
  function handleValidationJump(item: FormValidationItem) {
    return ctrl.handleValidationJump(item);
  }
  function save() {
    return ctrl.save();
  }
  function toggleLock() {
    return ctrl.toggleLock();
  }
  function undo() {
    const willResetHeader =
      !twoPageOpen &&
      !ctrl.environmentSUOpen &&
      !ctrl.busy &&
      !headerWorkflowBusy &&
      !ctrl.codeCheckOpen &&
      !ctrl.metadataOpen &&
      !ctrl.profileReviewBlocked &&
      !ctrl.children.undoDraftHandler() &&
      !ctrl.sivi.undoDraftHandler();
    ctrl.undo();
    if (willResetHeader) {
      successMsg = 'Changes undone.';
      lastNotifiedSuccessMsg = successMsg;
    }
  }

  export function getCloseState(): EditorCloseState {
    return ctrl.getCloseState();
  }
  export function saveForClose(): Promise<boolean> {
    return ctrl.saveForClose();
  }
  export function canOpenProjectMetadata(): boolean {
    return ctrl.canOpenProjectMetadata();
  }
  export function openProjectMetadata(): void {
    ctrl.openProjectMetadata();
  }
  export function canOpenMetadataInPlace(): boolean {
    return ctrl.canOpenMetadataInPlace();
  }
  export function applyDiagnosticHumusThickness(v: number): void {
    ctrl.applyDiagnosticHumusThickness(v);
  }
  export function applyDiagnosticSMR(smr: string): void {
    ctrl.applyDiagnosticSMR(smr);
  }
  export function applyDiagnosticSNR(snr: string): void {
    ctrl.applyDiagnosticSNR(snr);
  }
</script>

<svelte:window onkeydown={sourceEnter} />

<div
  bind:this={ctrl.container}
  data-tour="fs882-form-root"
  class="fs882-container bg-white rounded-lg shadow border border-vpro-border flex flex-col h-full text-vpro-ink text-sm"
>
  {#if ctrl.standaloneTwoPage && !plotNumber && ctrl.original === null}
    <FS882TwoPagePlotPrompt {availablePlots} {onClosed} {onSwitchTo6x4NewPlot} {onSelectPlotForTwoPage} />
  {:else}
    <FS882Toolbar
      {ctrl}
      canManagePlot={Boolean(onCopyPlotToNumber || onRemovePlotAction)}
      {onFindPlot}
      {onClosed}
      onToggleLock={() => void toggleLock()}
      onUndo={undo}
      onSave={() => void save()}
    />
    <FS882ManagePlotBar
      bind:open={ctrl.managePlotOpen}
      originalPlotNumber={ctrl.original?.plotNumber}
      activeProject={$projectState?.activeProject}
      busy={ctrl.busy}
      {canUndoPlotDelete}
      {onCopyPlotToNumber}
      {onRemovePlotAction}
      onError={(msg) => {
        ctrl.error = msg;
      }}
    />
    {#if ctrl.error}
      <div
        role="alert"
        class="p-2 bg-red-50 border-b border-red-200 text-red-800 text-xs flex flex-wrap items-center gap-2"
      >
        <AlertTriangle size={14} class="text-red-600 shrink-0" /><span>{ctrl.error}</span>
        {#if ctrl.isHeaderConflict && ctrl.original}
          <div class="ml-auto flex items-center gap-1.5">
            <button
              type="button"
              data-fs882-conflict-reload
              class="rounded bg-vpro-navy px-2.5 py-0.5 text-[11px] font-semibold text-white hover:bg-vpro-navy-dark disabled:opacity-50"
              disabled={ctrl.busy || headerWorkflowBusy}
              onclick={() => {
                if (ctrl.original) void ctrl.load(ctrl.original.plotNumber);
              }}>Reload Latest Plot</button
            >
            <button
              type="button"
              data-fs882-conflict-review
              class="rounded border border-red-300 bg-white px-2 py-0.5 text-[11px] font-medium text-red-800 hover:bg-red-100"
              onclick={() => {
                ctrl.error = null;
              }}>Keep Draft to Review</button
            >
          </div>
        {:else}
          <button
            type="button"
            class="ml-auto rounded border border-red-300 bg-white px-2 py-0.5 text-[11px] font-medium text-red-800 hover:bg-red-100"
            onclick={() => {
              ctrl.error = null;
            }}>Dismiss</button
          >
        {/if}
      </div>
    {/if}
    {#if ctrl.children.vegetationReadUnavailable}
      <p role="alert" class="p-2 bg-amber-50 text-amber-900 text-sm" data-vegetation-unavailable>
        Ordinary ID-keyed vegetation is unavailable: {ctrl.children.vegetationReadUnavailable} Use independently enabled physical-row
        source views. Ordinary vegetation rows, totals and actions are not presented as an empty result.
      </p>
    {/if}
    <nav
      aria-label={siviStandalone ? 'SIVI sections' : 'FS882 sections'}
      hidden={ctrl.standaloneTwoPage && twoPageOpen && twoPageScope === 'entry'}
      class="fs882-tabs flex flex-wrap border-b border-vpro-border bg-vpro-surface-subtle px-3 text-xs font-medium"
    >
      {#each ctrl.visibleTabs as tab (tab.id)}
        <button
          type="button"
          data-sivi-site-tab={tab.sivi ? '' : undefined}
          data-help-id={tab.helpId}
          aria-current={ctrl.activeTab === tab.id ? 'page' : undefined}
          disabled={tabWorkflowBusy}
          class="px-4 py-2 border-b-2 {ctrl.activeTab === tab.id
            ? 'border-vpro-navy text-vpro-navy font-bold bg-white'
            : 'border-transparent text-vpro-ink-secondary hover:text-vpro-ink'}"
          onclick={() => {
            ctrl.activeTab = tab.id;
            if (tab.sivi) ctrl.sivi.parentOpen = true;
          }}>{tab.label}</button
        >
      {/each}
    </nav>
    <FormValidationSummary items={ctrl.validationSummaryItems} onjump={(item) => void handleValidationJump(item)} />
    {#snippet ordinaryHost(tabPanels: Snippet)}
      <div hidden={twoPageOpen} data-two-page-ordinary-host>{@render tabPanels()}</div>
    {/snippet}
    <FS882WorkspaceBody
      {ctrl}
      loaders={subEditorLoaders}
      {loadSubEditor}
      extendedShrubsNotice={EXTENDED_SHRUB_NOTICE}
      expectedPlotNumber={plotNumber}
      {onFindPlot}
      {onClosed}
      {onOpenPictureManager}
      {onProfileSUReview}
      {onProfileNavigation}
      onClearSuccess={() => {
        successMsg = null;
      }}
      onAuditSuccess={(msg) => {
        successMsg = msg;
      }}
      {ordinaryHost}
    />
  {/if}
</div>
