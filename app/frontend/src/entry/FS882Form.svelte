<script lang="ts">
  import { AlertTriangle, Lock, LogIn } from '@lucide/svelte';
  import { untrack, type Snippet } from 'svelte';
  import { ContextService } from '../../bindings/github.com/boostao/vpro/app';
  import { projectState } from '../shared/state';
  import { notifications } from '../shell/notificationService.svelte';
  import type { PlotProfileSelectionController } from '../shell/plotProfileOps';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import FS882AccessRecordBar from './FS882AccessRecordBar.svelte';
  import FormValidationSummary from './FormValidationSummary.svelte';
  import FS882ManagePlotBar from './FS882ManagePlotBar.svelte';
  import type { FS882SubEditorLoaders } from './FS882Modals.svelte';
  import FS882Toolbar from './FS882Toolbar.svelte';
  import FS882TwoPagePlotPrompt from './FS882TwoPagePlotPrompt.svelte';
  import FS882WorkspaceBody from './FS882WorkspaceBody.svelte';
  import './classicFS882.css';
  import type { FormValidationItem } from './formValidationSummary';
  import {
    createFS882Controller,
    type FS882DiagnosticsState,
    type FS882FormBaseProps,
  } from './fs882FormController.svelte';
  import type { EditorCloseState } from './fs882FormSivi';

  let {
    plotNumber,
    neighborPlots = [],
    contextId,
    onSaved,
    onClosed,
    onBusyChange,
    onProfileNavigation,
    onProfileSUReview,
    profileSelection,
    initialProfileReviewOpen = false,
    onConsumedInitialProfileReview,
    onFindPlot,
    onSelectPlot,
    onNewPlot,
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
    profileSelection?: PlotProfileSelectionController;
    initialProfileReviewOpen?: boolean;
    onConsumedInitialProfileReview?: () => void;
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
  let navPlotOverride = $state<string | undefined | null>(null);
  let jumpedRecordIndex = $state<number | null>(null);
  let remoteTotalCount = $state<number | null>(null);
  let recordSearchFeedback = $state<string | null>(null);
  let lastPropPlotNumber: string | undefined = untrack(() => plotNumber);

  $effect(() => {
    const incoming = plotNumber;
    if (incoming !== lastPropPlotNumber) {
      lastPropPlotNumber = incoming;
      navPlotOverride = null;
      jumpedRecordIndex = null;
      recordSearchFeedback = null;
    }
  });

  const effectivePlotNumber = $derived(navPlotOverride === null ? plotNumber : navPlotOverride);

  const ctrl = createFS882Controller({
    contextId: untrack(() => contextId),
    getEntryForm: () => entryForm,
    getPlotNumber: () => effectivePlotNumber,
    getNeighborPlots: () => neighborPlots,
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

  const totalRecordCount = $derived(Math.max(availablePlots.length, remoteTotalCount ?? 0));
  const currentRecordIndex = $derived.by(() => {
    if (!effectivePlotNumber) return 0;
    const idx = availablePlots.findIndex((p) => p.plotNumber === effectivePlotNumber);
    if (idx >= 0) return idx + 1;
    if (jumpedRecordIndex !== null) return jumpedRecordIndex;
    return totalRecordCount > 0 ? 1 : 0;
  });

  $effect(() => {
    const ctx = contextId;
    const availLen = availablePlots.length;
    if (!ctx || typeof ContextService?.ListPlots !== 'function') {
      remoteTotalCount = null;
      return;
    }
    if (availLen > 0 && availLen < 2000) {
      remoteTotalCount = availLen;
      return;
    }
    let cancelled = false;
    void ContextService.ListPlots(0, 1)
      .then((page) => {
        if (!cancelled && page && typeof page.total === 'number') {
          remoteTotalCount = page.total;
        }
      })
      .catch(() => {
        // Keep availablePlots.length fallback
      });
    return () => {
      cancelled = true;
    };
  });

  $effect(() => {
    if (entryForm !== 'fs882-twopage') {
      autoOpenedTwoPageKey = null;
      return;
    }
    const loadedPlot = ctrl.original?.plotNumber ?? null;
    const activeProject = $projectState?.activeProject ?? null;
    if (!loadedPlot || !activeProject) {
      autoOpenedTwoPageKey = null;
      return;
    }
    const key = `${ctrl.siviContextId}:${activeProject}:${loadedPlot}`;
    if (twoPageOpen) {
      autoOpenedTwoPageKey = key;
      return;
    }
    if (
      $projectState?.contextId !== ctrl.siviContextId ||
      siviStandalone ||
      ctrl.childParentDisabled ||
      ctrl.profileReviewOpen ||
      initialProfileReviewOpen ||
      childUnsaved ||
      ctrl.dirty ||
      Object.keys(ctrl.headerValidation).length > 0
    ) {
      return;
    }
    if (autoOpenedTwoPageKey === key) return;
    autoOpenedTwoPageKey = key;
    ctrl.openTwoPageReview('entry');
  });

  $effect(() => {
    if (!initialProfileReviewOpen) return;
    if (ctrl.profileReviewOpen) {
      onConsumedInitialProfileReview?.();
      return;
    }
    if (ctrl.busy || ctrl.headerWorkflowBusy || ctrl.sivi.sourceBarrier || !ctrl.capabilitiesReady) return;
    ctrl.openProfileReviewFromToolbar();
    onConsumedInitialProfileReview?.();
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

  function guardRecordSwitch(): boolean {
    if (ctrl.busy || ctrl.headerWorkflowBusy) return false;
    if (ctrl.effectiveFormDirty) {
      ctrl.error = 'Save or Undo unsaved edits before switching records.';
      return false;
    }
    return true;
  }

  function navigateToPlot(targetPlot: string, knownIndex?: number) {
    if (!guardRecordSwitch()) return;
    recordSearchFeedback = null;
    ctrl.error = null;
    if (onSelectPlot) {
      jumpedRecordIndex = knownIndex ?? null;
      onSelectPlot(targetPlot);
    } else {
      jumpedRecordIndex = knownIndex ?? null;
      navPlotOverride = targetPlot;
      if (typeof window !== 'undefined' && typeof window.dispatchEvent === 'function' && typeof CustomEvent === 'function') {
        window.dispatchEvent(new CustomEvent('vpro:select-plot', { detail: { plotNumber: targetPlot } }));
      }
    }
  }

  async function jumpToRecordIndex(oneBasedIndex: number) {
    if (!guardRecordSwitch()) return;
    if (oneBasedIndex < 1 || (totalRecordCount > 0 && oneBasedIndex > totalRecordCount)) {
      recordSearchFeedback = `Record must be between 1 and ${totalRecordCount.toLocaleString()}.`;
      return;
    }
    if (oneBasedIndex <= availablePlots.length) {
      const target = availablePlots[oneBasedIndex - 1];
      if (target?.plotNumber) {
        navigateToPlot(target.plotNumber, oneBasedIndex);
        return;
      }
    }
    if (typeof ContextService?.ListPlots === 'function') {
      try {
        const page = await ContextService.ListPlots(oneBasedIndex - 1, 1);
        const target = page?.plots?.[0]?.plotNumber;
        if (target) {
          navigateToPlot(target, oneBasedIndex);
          return;
        }
      } catch {
        // Handled below
      }
    }
    recordSearchFeedback = `Record #${oneBasedIndex} could not be loaded.`;
  }

  async function searchPlotByNumber(rawQuery: string) {
    if (!guardRecordSwitch()) return;
    const trimmed = rawQuery.trim();
    if (!trimmed) return;
    // Preserve exact literal PlotNumber including leading zeroes (e.g. '00337')
    const exactRaw = availablePlots.find((p) => p.plotNumber === rawQuery);
    if (exactRaw) {
      navigateToPlot(exactRaw.plotNumber);
      return;
    }
    const exactTrim = availablePlots.find((p) => p.plotNumber === trimmed);
    if (exactTrim) {
      navigateToPlot(exactTrim.plotNumber);
      return;
    }
    const lower = trimmed.toLowerCase();
    const ciMatch = availablePlots.find((p) => p.plotNumber.toLowerCase() === lower);
    if (ciMatch) {
      navigateToPlot(ciMatch.plotNumber);
      return;
    }
    const prefixMatch = availablePlots.find((p) => p.plotNumber.startsWith(trimmed));
    if (prefixMatch) {
      navigateToPlot(prefixMatch.plotNumber);
      return;
    }
    if (contextId && typeof ContextService?.LookupScopedPlot === 'function') {
      try {
        const res = await ContextService.LookupScopedPlot(contextId, { plotNumber: rawQuery });
        if (res?.plot?.plotNumber) {
          navigateToPlot(res.plot.plotNumber);
          return;
        }
      } catch {
        // Fall through to not found message
      }
    }
    recordSearchFeedback = `Plot "${rawQuery}" not found.`;
  }

  function handleNewPlotRecord() {
    if (IS_WEB_READONLY || ctrl.authEditLocked) return;
    if (!guardRecordSwitch()) return;
    recordSearchFeedback = null;
    ctrl.error = null;
    if (onNewPlot) {
      onNewPlot();
    } else if (onSwitchTo6x4NewPlot) {
      onSwitchTo6x4NewPlot();
    } else {
      jumpedRecordIndex = null;
      navPlotOverride = undefined;
    }
  }

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
  {#if ctrl.standaloneTwoPage && !effectivePlotNumber && ctrl.original === null}
    <FS882TwoPagePlotPrompt {availablePlots} {onClosed} {onSwitchTo6x4NewPlot} {onSelectPlotForTwoPage} />
  {:else}
    {#if !siviStandalone}
      <FS882AccessRecordBar
        currentIndex={currentRecordIndex}
        totalCount={totalRecordCount}
        isNewPlot={!effectivePlotNumber && ctrl.original === null}
        locked={ctrl.authEditLocked}
        busy={ctrl.busy || headerWorkflowBusy}
        unsaved={ctrl.effectiveFormDirty}
        layoutMode={ctrl.layoutMode}
        leftCard={ctrl.splitLeftCard}
        rightCard={ctrl.splitRightCard}
        showLayoutSwitcher={!ctrl.standaloneTwoPage}
        searchFeedback={recordSearchFeedback}
        onFirst={() => void jumpToRecordIndex(1)}
        onPrev={() => void jumpToRecordIndex(Math.max(1, currentRecordIndex - 1))}
        onNext={() => void jumpToRecordIndex(Math.min(totalRecordCount, currentRecordIndex + 1))}
        onLast={() => void jumpToRecordIndex(totalRecordCount)}
        onJumpToRecord={(idx) => void jumpToRecordIndex(idx)}
        onNewPlot={handleNewPlotRecord}
        onSearchPlot={(q) => void searchPlotByNumber(q)}
        onLayoutModeChange={(mode) => {
          ctrl.layoutMode = mode;
        }}
        onLeftCardChange={(card) => {
          ctrl.splitLeftCard = card;
        }}
        onRightCardChange={(card) => {
          ctrl.splitRightCard = card;
        }}
      />
    {/if}

    <FS882Toolbar
      {ctrl}
      canManagePlot={Boolean(onCopyPlotToNumber || onRemovePlotAction)}
      {onFindPlot}
      {onClosed}
      onToggleLock={() => void toggleLock()}
      onUndo={undo}
      onSave={() => void save()}
    />

    {#if !IS_WEB_READONLY && ctrl.authEditLocked}
      <div
        role="status"
        data-edit-lock-banner
        class="classic-lock-banner px-3 py-1.5 bg-amber-50 border-b border-amber-300 text-amber-950 text-xs flex flex-wrap items-center justify-between gap-2"
      >
        <div class="flex items-center gap-1.5">
          <Lock size={13} class="text-amber-800 shrink-0" aria-hidden="true" />
          <span>
            <strong>Data is locked (read-only).</strong>
            {ctrl.editLock?.reason || 'Sign in from Work Space to edit.'}
          </span>
        </div>
        <button
          type="button"
          data-open-signin-btn
          class="inline-flex items-center gap-1 rounded bg-vpro-navy px-2.5 py-1 text-[11px] font-semibold text-white hover:bg-vpro-navy-dark"
          onclick={() => ctrl.requestSignIn()}
        >
          <LogIn size={12} aria-hidden="true" />
          {ctrl.editLock?.signedIn ? 'Switch Account' : 'Sign In'}
        </button>
      </div>
    {/if}

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
                if (ctrl.original) void ctrl.load(ctrl.original.plotNumber, { force: true });
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
      hidden={(ctrl.standaloneTwoPage && twoPageOpen && twoPageScope === 'entry') ||
        (!siviStandalone && ctrl.layoutMode !== 'single')}
      class="fs882-tabs flex flex-wrap items-center gap-1 border-b border-vpro-border bg-vpro-surface-subtle px-2.5 py-1 text-xs font-medium"
    >
      {#each ctrl.visibleTabs as tab (tab.id)}
        <button
          type="button"
          data-sivi-site-tab={tab.sivi ? '' : undefined}
          data-fs882-card-tab={tab.id}
          data-help-id={tab.helpId}
          aria-current={ctrl.activeTab === tab.id ? 'page' : undefined}
          disabled={tabWorkflowBusy}
          class="px-3 py-1 rounded border text-xs {ctrl.activeTab === tab.id
            ? 'border-vpro-navy bg-vpro-navy text-white font-semibold'
            : 'border-vpro-border bg-white text-vpro-ink-secondary hover:text-vpro-ink hover:bg-vpro-canvas'}"
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
      expectedPlotNumber={effectivePlotNumber}
      {onFindPlot}
      {onClosed}
      {onOpenPictureManager}
      {onProfileSUReview}
      {onProfileNavigation}
      {profileSelection}
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
