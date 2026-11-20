<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { ProjectPlotProfileFilterRequest } from '../../bindings/github.com/boostao/vpro/app';
  import FS882ChildCreateModal from './FS882ChildCreateModal.svelte';
  import FS882Modals, { type FS882SubEditorLoaders } from './FS882Modals.svelte';
  import FS882SiteTab from './FS882SiteTab.svelte';
  import FS882SoilTab from './FS882SoilTab.svelte';
  import FS882VegTab from './FS882VegTab.svelte';
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
    onClearSuccess: () => void;
    onAuditSuccess: (msg: string | null) => void;
    ordinaryHost: Snippet<[Snippet]>;
  } = $props();
</script>

{#snippet tabPanels()}
  {#if ctrl.activeTab === 'site' && !ctrl.siviStandalone}
    {#key ctrl.headerRevision}
      <FS882SiteTab
        bind:draft={ctrl.draft}
        original={ctrl.original}
        capabilities={ctrl.capabilities}
        headerInputsDisabled={ctrl.headerInputsDisabled}
        bind:parentCodeBusy={ctrl.parentCodeBusy}
        bind:coordinateBusy={ctrl.coordinateBusy}
        bind:workingUnitBusy={ctrl.workingUnitBusy}
        bind:qualityBusy={ctrl.qualityBusy}
        bind:siteCodeBusy={ctrl.siteCodeBusy}
        bind:regionCodeBusy={ctrl.regionCodeBusy}
        bind:pictureBusy={ctrl.pictureBusy}
        openProjectMetadata={ctrl.openProjectMetadata}
        canOpenProjectMetadata={ctrl.canOpenProjectMetadata}
        {onOpenPictureManager}
        projectIds={ctrl.projectIdDatalist}
        masterAllowed={ctrl.masterAllowed}
        extendedShrubs={ctrl.extendedShrubs}
        snowCoverRegime={ctrl.snowCoverRegimeInput}
        activeLayerDepth={ctrl.activeLayerDepthInput}
        snowCoverRegimeDisabled={ctrl.arcticInputsDisabled}
        activeLayerDepthDisabled={ctrl.arcticInputsDisabled}
        snowCoverRegimeError={ctrl.headerValidation.snowCoverRegime ?? null}
        activeLayerDepthError={ctrl.headerValidation.activeLayerDepth ?? null}
        onSnowCoverRegimeChange={ctrl.stageSnowCoverRegime}
        onActiveLayerDepthChange={ctrl.stageActiveLayerDepth}
        lists={ctrl.children.lists}
        workingUnitSession={ctrl.workingUnitSession}
        markDirty={ctrl.markDirty}
        validateHeader={ctrl.validateHeader}
        onError={(message) => {
          ctrl.error = message;
        }}
        twoPageOpen={ctrl.twoPageOpen}
        contextId={ctrl.siviContextId}
        activeProject={ctrl.pState?.activeProject ?? null}
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
    {/key}
  {:else if ctrl.activeTab === 'veg'}
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
  {:else if ctrl.activeTab === 'soils' || ctrl.activeTab === 'vegOther' || ctrl.activeTab === 'other' || ctrl.activeTab === 'audit'}
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
  {/if}
{/snippet}

{#if !ctrl.twoPageOpen || (!ctrl.siviStandalone && !(ctrl.standaloneTwoPage && ctrl.twoPageOpen && ctrl.twoPageScope === 'entry'))}
  <div class="border-b border-vpro-border px-4 py-2 flex flex-wrap items-center gap-4">
    {#if !ctrl.twoPageOpen}
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
    {/if}
    {#if !ctrl.siviStandalone}
      <button
        type="button"
        data-sivi-parent-open
        aria-pressed={ctrl.activeTab === 'siviParent'}
        class="rounded border px-3 py-1 text-sm disabled:opacity-50"
        disabled={ctrl.busy ||
          ctrl.headerWorkflowBusy ||
          ctrl.dirty ||
          ctrl.nonParentChildUnsaved ||
          !ctrl.sivi.parentSession}
        onclick={() => void ctrl.sivi.showParentPanel()}>SIVI parent (read-only)</button
      >
    {/if}
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
