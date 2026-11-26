<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { ProjectPlotProfileFilterRequest } from '../../bindings/github.com/boostao/vpro/app';
  import type { PlotProfileSelectionController } from '../shell/plotProfileOps';
  import FS882CardSite from './FS882CardSite.svelte';
  import FS882CardSoil from './FS882CardSoil.svelte';
  import FS882CardVeg from './FS882CardVeg.svelte';
  import FS882ChildCreateModal from './FS882ChildCreateModal.svelte';
  import FS882Modals, { type FS882SubEditorLoaders } from './FS882Modals.svelte';
  import type { ClassicCardId } from './classicFS882Helpers';
  import type { FS882Controller } from './fs882FormController.svelte';

  let {
    ctrl,
    loaders,
    loadSubEditor,
    extendedShrubsNotice,
    expectedPlotNumber,
    onFindPlot,
    onClosed,
    onOpenPictureManager,
    onProfileSUReview,
    onProfileNavigation,
    profileSelection,
    onClearSuccess,
    onAuditSuccess,
    ordinaryHost,
  }: {
    ctrl: FS882Controller;
    loaders: FS882SubEditorLoaders;
    loadSubEditor: <T>(loader: () => Promise<T>, label: string, onFailed: () => void) => Promise<T>;
    extendedShrubsNotice: string;
    expectedPlotNumber?: string;
    onFindPlot?: () => void;
    onClosed?: () => void;
    onOpenPictureManager?: (plotNumber: string) => void;
    onProfileSUReview?: (proposal: ProjectPlotProfileFilterRequest, contextId: string) => Promise<void>;
    onProfileNavigation?: (proposal: ProjectPlotProfileFilterRequest, contextId: string) => Promise<void>;
    profileSelection?: PlotProfileSelectionController;
    onClearSuccess: () => void;
    onAuditSuccess: (msg: string | null) => void;
    ordinaryHost: Snippet<[Snippet]>;
  } = $props();

  const effectiveLocked = $derived(ctrl.authEditLocked || ctrl.draft.locked);
  const currentPlotForCard4 = $derived(ctrl.original?.plotNumber ?? expectedPlotNumber ?? '');
</script>

{#snippet renderClassicCard(cardId: ClassicCardId)}
  {#if cardId === 'site'}
    <FS882CardSite
      {ctrl}
      {onOpenPictureManager}
      pictureDisabled={ctrl.busy ||
        ctrl.otherHeaderWorkflowBusy ||
        !ctrl.capabilitiesReady ||
        ctrl.dirty ||
        ctrl.childUnsaved}
      pictureMetadataDisabled={ctrl.busy ||
        ctrl.otherHeaderWorkflowBusy ||
        !ctrl.capabilitiesReady ||
        (!ctrl.sivi.pictureMetadataPending && (ctrl.dirty || ctrl.childUnsaved))}
      pictureMetadataSession={ctrl.sivi.pictureMetadataSession}
    />
  {:else if cardId === 'soils'}
    <FS882CardSoil {ctrl} />
  {:else if cardId === 'veg'}
    <FS882CardVeg {ctrl} {extendedShrubsNotice} />
  {:else if cardId === 'mensuration'}
    {#await import('./FS882CardMensuration.svelte') then { default: FS882CardMensuration }}
      <FS882CardMensuration
        contextId={ctrl.siviContextId}
        plotNumber={currentPlotForCard4}
        headerDraft={ctrl.draft}
        locked={effectiveLocked}
        onDirtyChange={(dirty) => {
          ctrl.mensurationDirty = dirty;
        }}
        onBusyChange={(busy) => {
          ctrl.mensurationBusy = busy;
        }}
      />
    {/await}
  {/if}
{/snippet}

{#snippet tabPanels()}
  {#if ctrl.siviStandalone}
    {#if ctrl.activeTab === 'veg'}
      {#await import('./FS882VegTab.svelte') then { default: FS882VegTab }}
        <FS882VegTab
          sivi={ctrl.sivi}
          children={ctrl.children}
          bind:draft={ctrl.draft}
          original={ctrl.original}
          capabilities={ctrl.capabilities}
          bind:vegetationMode={ctrl.vegetationMode}
          busy={ctrl.busy}
          headerWorkflowBusy={ctrl.headerWorkflowBusy}
          headerInputsDisabled={ctrl.headerInputsDisabled}
          capabilitiesReady={ctrl.capabilitiesReady}
          siviStandalone={ctrl.siviStandalone}
          extendedShrubs={ctrl.extendedShrubs}
          {extendedShrubsNotice}
          siviContextId={ctrl.siviContextId}
          activeProject={ctrl.pState?.activeProject ?? ''}
          sourceHeaderValues={ctrl.sourceHeaderValues}
          headerValidation={ctrl.headerValidation}
          childParentDisabled={ctrl.childParentDisabled}
          childUnsaved={ctrl.childUnsaved}
          {onFindPlot}
          markDirty={ctrl.markDirty}
          validateHeader={ctrl.validateHeader}
          vegetationNotesTab={ctrl.vegetationNotesTab}
          openSpeciesCodeCheck={ctrl.openSpeciesCodeCheck}
        />
      {/await}
    {/if}
  {:else if ctrl.standaloneTwoPage && expectedPlotNumber}
    <p role="status" class="p-4 text-xs text-vpro-ink-secondary" data-entry-loading="twopage-plot">
      Loading plot {expectedPlotNumber}...
    </p>
  {:else if expectedPlotNumber && ctrl.original === null && ctrl.busy}
    <p role="status" class="p-4 text-xs text-vpro-ink-secondary" data-entry-loading="site-plot">
      Loading plot {expectedPlotNumber}...
    </p>
  {:else if ctrl.layoutMode === 'single' && (ctrl.activeTab === 'vegOther' || ctrl.activeTab === 'other' || ctrl.activeTab === 'audit')}
    <div class="p-3">
      {#await import('./FS882SoilTab.svelte') then { default: FS882SoilTab }}
        <FS882SoilTab
          activeTab={ctrl.activeTab}
          children={ctrl.children}
          bind:draft={ctrl.draft}
          original={ctrl.original}
          capabilities={ctrl.capabilities}
          bind:soilCodeBusy={ctrl.soilCodeBusy}
          bind:geologyCodeBusy={ctrl.geologyCodeBusy}
          bind:parentCodeBusy={ctrl.parentCodeBusy}
          bind:drainageBusy={ctrl.drainageBusy}
          headerRevision={ctrl.headerRevision}
          sourceHeaderValues={ctrl.sourceHeaderValues}
          headerInputsDisabled={ctrl.headerInputsDisabled}
          busy={ctrl.busy}
          headerWorkflowBusy={ctrl.headerWorkflowBusy}
          coordinateBusy={ctrl.coordinateBusy}
          workingUnitBusy={ctrl.workingUnitBusy}
          qualityBusy={ctrl.qualityBusy}
          siteCodeBusy={ctrl.siteCodeBusy}
          regionCodeBusy={ctrl.regionCodeBusy}
          auditProject={ctrl.pState?.activeProject ?? ''}
          {expectedPlotNumber}
          auditBlocked={ctrl.childParentDisabled || ctrl.childUnsaved || Object.keys(ctrl.headerValidation).length > 0}
          auditGateReason={ctrl.auditGateReason}
          getLoadRequest={() => ctrl.loadRequest}
          PlotService={ctrl.PlotService}
          markDirty={ctrl.markDirty}
          validateHeader={ctrl.validateHeader}
          onAuditBusyChange={(val) => {
            ctrl.busy = val;
          }}
          onAuditFeedback={(err, msg) => {
            ctrl.error = err;
            if (msg !== null || err === null) onAuditSuccess(msg);
          }}
          onRefreshAfterRestore={ctrl.refreshAfterRestore}
          onRefreshFailure={(msg) => {
            ctrl.capabilitiesReady = false;
            ctrl.children.childRevision += 1;
            ctrl.error = msg;
          }}
        />
      {/await}
    </div>
  {:else}
    <div class="classic-fs882-stage">
      <div class="classic-fs882-layout" data-classic-layout={ctrl.layoutMode}>
        {#if ctrl.layoutMode === 'single'}
          {#if ctrl.activeTab === 'site' && !ctrl.siviStandalone}
            {@render renderClassicCard('site')}
          {:else if ctrl.activeTab === 'soils'}
            {@render renderClassicCard('soils')}
          {:else if ctrl.activeTab === 'veg'}
            {@render renderClassicCard('veg')}
          {:else if ctrl.activeTab === 'mensuration'}
            {@render renderClassicCard('mensuration')}
          {:else if !ctrl.siviStandalone}
            {@render renderClassicCard('site')}
          {/if}
        {:else if ctrl.layoutMode === 'side-by-side'}
          {@render renderClassicCard(ctrl.splitLeftCard)}
          {@render renderClassicCard(ctrl.splitRightCard)}
        {:else}
          <!-- Top-Down and 2x2 Grid show all 4 FS882 Classic cards simultaneously -->
          {@render renderClassicCard('site')}
          {@render renderClassicCard('soils')}
          {@render renderClassicCard('veg')}
          {@render renderClassicCard('mensuration')}
        {/if}
      </div>
    </div>
  {/if}
{/snippet}

{#if ctrl.siviStandalone && !ctrl.twoPageOpen}
  <div class="border-b border-vpro-border px-4 py-1.5 flex flex-wrap items-center gap-4">
    <label class="inline-flex items-center gap-2 text-xs font-medium cursor-pointer" data-help-id="veg.covers">
      <input
        type="checkbox"
        data-extended-shrubs
        checked={ctrl.extendedShrubs}
        disabled={ctrl.busy || ctrl.headerWorkflowBusy}
        onchange={(event) => ctrl.setExtendedShrubs(event.currentTarget.checked)}
      />
      Show extended shrub layers
    </label>
  </div>
{/if}

<div
  class="fs882-workspace-split flex-1 min-h-0 flex"
  class:split-active={ctrl.fieldCardSplitOpen && ctrl.fieldCardViewModel !== null}
>
  <div class="fs882-body overflow-y-auto flex-1 min-w-0" data-field-card-form-pane>
    <FS882Modals
      {ctrl}
      {loaders}
      {loadSubEditor}
      onCloseStandalone={onClosed}
      {onProfileSUReview}
      {onProfileNavigation}
      {profileSelection}
    />
    <FS882ChildCreateModal
      region="toolbars"
      children={ctrl.children}
      busy={ctrl.busy}
      headerWorkflowBusy={ctrl.headerWorkflowBusy}
      plotNumber={ctrl.draft.plotNumber}
      onPersonalDraftChange={(value) => {
        ctrl.children.personalDraft = value;
        ctrl.error = null;
        onClearSuccess();
      }}
    />
    {@render ordinaryHost(tabPanels)}
    <FS882ChildCreateModal region="newChild" children={ctrl.children} busy={ctrl.busy} error={ctrl.error} />
    <FS882ChildCreateModal region="speciesModal" children={ctrl.children} />
  </div>
  {#if ctrl.fieldCardSplitOpen && ctrl.fieldCardViewModel}
    {#await import('./FieldCardPreviewModal.svelte') then { default: FieldCardPreviewModal }}
      <div class="fs882-dock-pane">
        <FieldCardPreviewModal
          open={true}
          mode="docked"
          viewModel={ctrl.fieldCardViewModel}
          onclose={() => {
            ctrl.fieldCardSplitOpen = false;
          }}
          onmodechange={(nextMode) => {
            if (nextMode === 'modal') {
              ctrl.fieldCardSplitOpen = false;
              ctrl.fieldCardModalOpen = true;
            }
          }}
        />
      </div>
    {/await}
  {/if}
</div>

{#if ctrl.fieldCardModalOpen && ctrl.fieldCardViewModel}
  {#await import('./FieldCardPreviewModal.svelte') then { default: FieldCardPreviewModal }}
    <FieldCardPreviewModal
      open={true}
      mode="modal"
      viewModel={ctrl.fieldCardViewModel}
      onclose={() => {
        ctrl.fieldCardModalOpen = false;
      }}
      onmodechange={(nextMode) => {
        if (nextMode === 'docked') {
          ctrl.fieldCardModalOpen = false;
          ctrl.fieldCardSplitOpen = true;
        }
      }}
    />
  {/await}
{/if}
