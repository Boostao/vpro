<script lang="ts">
  import type { ProjectPlotProfileFilterRequest } from '../../bindings/github.com/boostao/vpro/app';
  import PicturePanel from '../pictures/PicturePanel.svelte';
  import { formatError } from '../shared/readRequests';
  import type { PlotProfileSelectionController } from '../shell/plotProfileOps';
  import FS882SiviParentModalHost from './FS882SiviParentModalHost.svelte';
  import SourceChild from './SourceChild.svelte';
  import type { FS882Controller } from './fs882FormController.svelte';
  import type { PaperControl } from './paperLayout';
  import type { TwoPageEntryChild } from './twoPageEntryProjection';

  export interface FS882SubEditorLoaders {
    environmentSU: () => Promise<{ default: typeof import('../classification/EnvironmentSUTransfer.svelte').default }>;
    externalSU: () => Promise<{
      default: typeof import('../classification/ExternalSUEnvironmentTransfer.svelte').default;
    }>;
    profileReview: () => Promise<{
      default: typeof import('../classification/ProjectPlotProfileReview.svelte').default;
    }>;
    twoPageEntry: () => Promise<{ default: typeof import('./TwoPageEntryEditor.svelte').default }>;
    twoPageCommon: () => Promise<{ default: typeof import('./TwoPageParentCommonEditor.svelte').default }>;
    twoPageExtra: () => Promise<{ default: typeof import('./TwoPageParentEditor.svelte').default }>;
    twoPageSoil: () => Promise<{ default: typeof import('./TwoPageSoilPanel.svelte').default }>;
    twoPageVegetation: () => Promise<{ default: typeof import('./TwoPageVegetationPanel.svelte').default }>;
    projectMetadata: () => Promise<{ default: typeof import('../admin/ProjectMetadataEditor.svelte').default }>;
    speciesCodeCheck: () => Promise<{ default: typeof import('./SpeciesCodeCheck.svelte').default }>;
  }

  let {
    ctrl,
    loaders,
    loadSubEditor,
    onCloseStandalone,
    onProfileSUReview,
    onProfileNavigation,
    profileSelection,
  }: {
    ctrl: FS882Controller;
    loaders: FS882SubEditorLoaders;
    loadSubEditor: <T>(loader: () => Promise<T>, label: string, onFailed: () => void) => Promise<T>;
    onCloseStandalone?: () => void;
    onProfileSUReview?: (proposal: ProjectPlotProfileFilterRequest, contextId: string) => Promise<void>;
    onProfileNavigation?: (proposal: ProjectPlotProfileFilterRequest, contextId: string) => Promise<void>;
    profileSelection?: PlotProfileSelectionController;
  } = $props();

  const contextId = $derived(ctrl.contextId);
  const activeProject = $derived(ctrl.pState?.activeProject ?? '');
  const activeSU = $derived(ctrl.pState?.activeSU ?? '');
  const projectPath = $derived(ctrl.pState?.projectPath ?? '');
  const suPath = $derived(ctrl.pState?.suPath ?? '');
  const plotNumber = $derived(ctrl.draft.plotNumber);
  const originalPlotNumber = $derived(ctrl.original?.plotNumber);
  const linkedChildBlocked = $derived(
    ctrl.twoPageSoilBusy || ctrl.twoPageSoilBlocked || ctrl.twoPageVegetationBusy || ctrl.twoPageVegetationBlocked
  );
</script>

<FS882SiviParentModalHost
  sivi={ctrl.sivi}
  activeTab={ctrl.activeTab}
  metadataOpen={ctrl.metadataOpen}
  busy={ctrl.busy}
  dirty={ctrl.dirty}
  childUnsaved={ctrl.childUnsaved}
  extendedShrubs={ctrl.extendedShrubs}
  setExtendedShrubs={ctrl.setExtendedShrubs}
  snowCoverRegimeInput={ctrl.snowCoverRegimeInput}
  activeLayerDepthInput={ctrl.activeLayerDepthInput}
  arcticInputsDisabled={ctrl.arcticInputsDisabled}
  snowCoverRegimeSupported={ctrl.capabilities.snowCoverRegime === true}
  activeLayerDepthSupported={ctrl.capabilities.activeLayerDepth === true}
  headerValidation={ctrl.headerValidation}
  stageSnowCoverRegime={ctrl.stageSnowCoverRegime}
  stageActiveLayerDepth={ctrl.stageActiveLayerDepth}
  openProjectMetadata={ctrl.openProjectMetadata}
  canOpenProjectMetadata={ctrl.canOpenProjectMetadata}
/>

{#if ctrl.environmentSUOpen && ctrl.environmentSUDirection !== 'external-reverse' && projectPath}
  {#await loadSubEditor(loaders.environmentSU, 'SU transfer review', () => {
    ctrl.environmentSUOpen = false;
  })}
    <p role="status" class="p-3 text-xs">Loading SU transfer review...</p>
  {:then { default: EnvironmentSUTransfer }}
    <EnvironmentSUTransfer
      bind:this={ctrl.environmentSUEditor}
      client={ctrl.PlotService}
      {contextId}
      project={activeProject}
      su={activeSU}
      path={projectPath}
      direction={ctrl.environmentSUDirection === 'reverse' ? 'reverse' : 'forward'}
      onclosed={() => {
        ctrl.environmentSUOpen = false;
        ctrl.error = null;
        if (ctrl.environmentSUDirection === 'reverse') void ctrl.load(originalPlotNumber);
      }}
    />
  {:catch loadError}
    <p role="alert" class="p-3 text-xs text-red-700">SU transfer review could not load: {formatError(loadError)}</p>
  {/await}
{/if}

{#if ctrl.environmentSUOpen && ctrl.environmentSUDirection === 'external-reverse' && projectPath && suPath}
  {#await loadSubEditor(loaders.externalSU, 'External SU transfer review', () => {
    ctrl.environmentSUOpen = false;
  })}
    <p role="status" class="p-3 text-xs">Loading external SU transfer review...</p>
  {:then { default: ExternalSUEnvironmentTransfer }}
    <ExternalSUEnvironmentTransfer
      bind:this={ctrl.environmentSUEditor}
      {contextId}
      project={activeProject}
      {projectPath}
      su={activeSU}
      {suPath}
      onclosed={() => {
        ctrl.environmentSUOpen = false;
        ctrl.error = null;
        void ctrl.load(originalPlotNumber);
      }}
    />
  {:catch loadError}
    <p role="alert" class="p-3 text-xs text-red-700">
      External SU transfer review could not load: {formatError(loadError)}
    </p>
  {/await}
{/if}

{#if ctrl.profileReviewOpen}
  {#await loadSubEditor(loaders.profileReview, 'Project plot profile review', () => {
    ctrl.profileReviewOpen = false;
    ctrl.profileReviewBusy = false;
    ctrl.profileReviewBlocked = false;
  })}
    <p role="status" class="p-3 text-xs">Loading project plot profile review...</p>
  {:then { default: ProjectPlotProfileReview }}
    {#if ctrl.profileReviewOpen}
      <ProjectPlotProfileReview
        bind:this={ctrl.profileEditor}
        client={ctrl.PlotService}
        {profileSelection}
        allowRun={true}
        allowPresence={Boolean(activeProject)}
        {contextId}
        {activeSU}
        authorityBlocked={ctrl.sivi.sourceBarrier}
        allowEditing={ctrl.pState?.plotProfile?.writable === true}
        allowCreation={true}
        allowDeletion={true}
        allowSaveSU={true}
        onsureview={async (proposal) => {
          if (!onProfileSUReview) throw new Error('Save as SU review is unavailable.');
          await onProfileSUReview(proposal, contextId);
        }}
        allowFiltering={true}
        onapply={async (proposal) => {
          if (!onProfileNavigation) throw new Error('Profile navigation publication is unavailable.');
          await onProfileNavigation(proposal, contextId);
        }}
        onblocked={(value) => {
          ctrl.profileReviewBlocked = value;
        }}
        onbusy={(value) => {
          ctrl.profileReviewBusy = value;
        }}
        onclosed={() => {
          ctrl.profileReviewOpen = false;
        }}
      />
    {/if}
  {:catch loadError}
    <p role="alert" class="p-3 text-xs text-red-700">
      Project plot profile review could not load: {formatError(loadError)}
    </p>
  {/await}
{/if}

{#snippet twoPageLinkedChild(child: TwoPageEntryChild, control: PaperControl)}
  {#if ctrl.twoPageScope === 'entry' && ctrl.twoPageProject !== null && (child.form === 'SoilHumusXL' || child.form === 'SoilMineralXL')}
    {#await loaders.twoPageSoil()}
      <p role="status" class="p-2 text-xs">Loading linked soil panel...</p>
    {:then { default: TwoPageSoilPanel }}
      <TwoPageSoilPanel
        {contextId}
        project={ctrl.twoPageProject}
        plot={plotNumber}
        form={child.form}
        parentBlocked={ctrl.twoPageSoilParentBlocked}
      />
    {:catch loadError}
      <p role="alert" class="p-2 text-xs text-red-700">Linked soil panel could not load: {formatError(loadError)}</p>
    {/await}
  {:else if ctrl.twoPageScope === 'entry' && ctrl.twoPageProject !== null && (child.form === 'SubVegAXL_BC' || child.form === 'SubVegAXL' || child.form === 'SubVegCXL' || child.form === 'SubVegDXL')}
    {#await loaders.twoPageVegetation()}
      <p role="status" class="p-2 text-xs">Loading linked vegetation panel...</p>
    {:then { default: TwoPageVegetationPanel }}
      {#key JSON.stringify([contextId, ctrl.twoPageProject, plotNumber, child.form])}
        <TwoPageVegetationPanel
          {contextId}
          project={ctrl.twoPageProject}
          plot={plotNumber}
          form={child.form}
          parentBlocked={ctrl.linkedVegetationParentBlocked(child.form)}
        />
      {/key}
    {:catch loadError}
      <p role="alert" class="p-2 text-xs text-red-700">
        Linked vegetation panel could not load: {formatError(loadError)}
      </p>
    {/await}
  {:else if ctrl.twoPageScope === 'entry' && ctrl.twoPageProject !== null && child.form === 'frmVPicsXL'}
    <div
      data-two-page-picture-child={child.form}
      data-source-control={control.controlId}
      data-source-image-control="form:frmVPicsXL/imgCtl"
    >
      <PicturePanel
        {contextId}
        project={ctrl.twoPageProject}
        {plotNumber}
        view="child"
        observeMutationReceipts={false}
        disabled={ctrl.twoPageLinkedParentBlocked || linkedChildBlocked}
        onBusyChange={(pending) => {
          ctrl.pictureBusy = pending;
        }}
      />
    </div>
  {:else if ctrl.children.ordinaryVegetationUnavailable && child.form.startsWith('SubVeg')}
    <p role="status" data-vegetation-ordinary-unavailable={child.form}>{ctrl.children.ordinaryVegetationUnavailable}</p>
  {:else if ctrl.children.ordinarySoilUnavailable && (child.form === 'SoilHumusXL' || child.form === 'SoilMineralXL')}
    <p role="status" data-soil-ordinary-unavailable={child.form}>{ctrl.children.ordinarySoilUnavailable}</p>
  {:else}
    <SourceChild
      name={child.form}
      rows={ctrl.children.sourceRows(child.form)}
      revision={ctrl.children.childRevision}
      disabled={true}
    />
  {/if}
{/snippet}

{#if ctrl.twoPageOpen && ctrl.twoPageProject !== null}
  {#if ctrl.twoPageScope === 'entry'}
    {#await loadSubEditor(loaders.twoPageEntry, 'Two-page complete entry', () => {
      ctrl.twoPageOpen = false;
      ctrl.twoPageBusy = false;
      ctrl.twoPageProject = null;
    })}
      <p role="status" data-two-page-loading="entry" class="p-3 text-xs">Loading two-page complete entry...</p>
    {:then { default: TwoPageEntryEditor }}
      <TwoPageEntryEditor
        bind:this={ctrl.twoPageEditor}
        {contextId}
        project={ctrl.twoPageProject}
        plot={plotNumber}
        initialForm={ctrl.twoPageEntryInitialForm}
        standalone={ctrl.standaloneTwoPage}
        onExtendedShrubsChange={ctrl.setExtendedShrubs}
        pictureReaderAvailable={true}
        auditReaderAvailable={true}
        googleEarthReaderAvailable={true}
        vegetationTableReaderAvailable={true}
        environmentTableReaderAvailable={true}
        projectMetadataReaderAvailable={true}
        projectMetadataClient={ctrl.PlotService}
        metadataRestorationAvailable={true}
        profilingReaderAvailable={true}
        profilingSource={ctrl.pState?.plotProfile?.source ?? null}
        vegetationTableSU={activeSU}
        vegetationTableSUPath={suPath}
        sourceProjectPath={projectPath}
        externalScope={ctrl.separateSUSelected && !ctrl.siviStandalone && projectPath && suPath
          ? { contextId, project: activeProject, projectPath, su: activeSU, suPath }
          : null}
        sourceBlocked={ctrl.twoPageLinkedParentBlocked ||
          Object.keys(ctrl.headerValidation).length > 0 ||
          linkedChildBlocked}
        cache={ctrl.twoPageEntrySessions}
        revision={ctrl.twoPageRevision}
        onchange={() => {
          ctrl.twoPageRevision += 1;
        }}
        childBlocked={linkedChildBlocked || ctrl.pictureBusy || ctrl.sivi.pictureMetadataPending}
        onbusy={(value) => {
          ctrl.twoPageBusy = value;
        }}
        onclosed={() => {
          ctrl.twoPageOpen = false;
          ctrl.twoPageBusy = false;
          ctrl.twoPageProject = null;
          ctrl.error = null;
          if (ctrl.standaloneTwoPage) onCloseStandalone?.();
        }}
        onOpenProfileSU={!ctrl.siviStandalone ? ctrl.openProfileSUFromTwoPage : undefined}
        oncommitted={() => ctrl.refreshTwoPagePeers('entry')}
        embedded={twoPageLinkedChild}
      />
    {:catch loadError}
      <p role="alert" data-two-page-load-error="entry" class="p-3 text-xs text-red-700">
        Two-page complete entry could not load: {formatError(loadError)}
      </p>
    {/await}
  {:else if ctrl.twoPageScope === 'common'}
    {#await loadSubEditor(loaders.twoPageCommon, 'Two-page common fields', () => {
      ctrl.twoPageOpen = false;
      ctrl.twoPageBusy = false;
      ctrl.twoPageProject = null;
    })}
      <p role="status" data-two-page-loading="common" class="p-3 text-xs">Loading two-page common fields...</p>
    {:then { default: TwoPageParentCommonEditor }}
      <TwoPageParentCommonEditor
        bind:this={ctrl.twoPageEditor}
        {contextId}
        project={ctrl.twoPageProject}
        plot={plotNumber}
        initialForm={ctrl.twoPageEntryInitialForm}
        onExtendedShrubsChange={ctrl.setExtendedShrubs}
        cache={ctrl.twoPageCommonSessions}
        revision={ctrl.twoPageRevision}
        onchange={() => {
          ctrl.twoPageRevision += 1;
        }}
        onbusy={(value) => {
          ctrl.twoPageBusy = value;
        }}
        onclosed={() => {
          ctrl.twoPageOpen = false;
          ctrl.twoPageBusy = false;
          ctrl.twoPageProject = null;
          ctrl.error = null;
        }}
        oncommitted={() => ctrl.refreshTwoPagePeers('common')}
        embedded={twoPageLinkedChild}
      />
    {:catch loadError}
      <p role="alert" data-two-page-load-error="common" class="p-3 text-xs text-red-700">
        Two-page common fields could not load: {formatError(loadError)}
      </p>
    {/await}
  {:else}
    {#await loadSubEditor(loaders.twoPageExtra, 'Two-page additional fields', () => {
      ctrl.twoPageOpen = false;
      ctrl.twoPageBusy = false;
      ctrl.twoPageProject = null;
    })}
      <p role="status" data-two-page-loading="extra" class="p-3 text-xs">Loading two-page additional fields...</p>
    {:then { default: TwoPageParentEditor }}
      <TwoPageParentEditor
        bind:this={ctrl.twoPageEditor}
        {contextId}
        project={ctrl.twoPageProject}
        plot={plotNumber}
        initialForm={ctrl.twoPageEntryInitialForm}
        onExtendedShrubsChange={ctrl.setExtendedShrubs}
        cache={ctrl.twoPageSessions}
        revision={ctrl.twoPageRevision}
        onchange={() => {
          ctrl.twoPageRevision += 1;
        }}
        onbusy={(value) => {
          ctrl.twoPageBusy = value;
        }}
        onclosed={() => {
          ctrl.twoPageOpen = false;
          ctrl.twoPageBusy = false;
          ctrl.twoPageProject = null;
          ctrl.error = null;
        }}
        oncommitted={() => ctrl.refreshTwoPagePeers('extra')}
        embedded={twoPageLinkedChild}
      />
    {:catch loadError}
      <p role="alert" data-two-page-load-error="extra" class="p-3 text-xs text-red-700">
        Two-page additional fields could not load: {formatError(loadError)}
      </p>
    {/await}
  {/if}
{/if}

{#if ctrl.metadataOpen}
  {#await loadSubEditor(loaders.projectMetadata, 'Project metadata editor', () => {
    ctrl.metadataOpen = false;
    ctrl.metadataBusy = false;
  })}
    <p role="status" class="p-3 text-xs">Loading project metadata editor...</p>
  {:then { default: ProjectMetadataEditor }}
    <ProjectMetadataEditor
      bind:this={ctrl.metadataEditor}
      client={ctrl.PlotService}
      {contextId}
      plot={plotNumber}
      allowCreation={true}
      allowTemplateCreation={true}
      allowRestoration={true}
      onbusy={(value) => {
        ctrl.metadataBusy = value;
      }}
      onclosed={() => {
        ctrl.metadataOpen = false;
        ctrl.error = null;
      }}
      oncommitted={() => ctrl.sivi.refreshProjectMetadata(plotNumber)}
    />
  {:catch loadError}
    <p role="alert" class="p-3 text-xs text-red-700">
      Project metadata editor could not load: {formatError(loadError)}
    </p>
  {/await}
{/if}

{#if ctrl.codeCheckOpen}
  {#await loadSubEditor(loaders.speciesCodeCheck, 'Species code check', () => {
    ctrl.codeCheckOpen = false;
    ctrl.codeCheckBusy = false;
  })}
    <p role="status" class="p-3 text-xs">Loading species code check...</p>
  {:then { default: SpeciesCodeCheck }}
    <SpeciesCodeCheck
      bind:this={ctrl.codeCheckEditor}
      client={ctrl.PlotService}
      onbusy={(value) => {
        ctrl.codeCheckBusy = value;
      }}
      onclosed={() => {
        ctrl.codeCheckOpen = false;
        ctrl.error = null;
      }}
      oncommitted={() => ctrl.children.loadChildData(plotNumber)}
    />
  {:catch loadError}
    <p role="alert" class="p-3 text-xs text-red-700">Species code check could not load: {formatError(loadError)}</p>
  {/await}
{/if}
