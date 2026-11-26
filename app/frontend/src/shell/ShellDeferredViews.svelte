<script lang="ts">
  import { ContextService } from '../../bindings/github.com/boostao/vpro/app';
  import { formatError, type ReadRequests } from '../shared/readRequests';
  import { projectState, webMeta } from '../shared/state';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import type { ShellViewId } from './shellPlotOps';

  let {
    view,
    panelHold,
    companionPanelBusy,
    localEditorBusy = $bindable(false),
    secondaryPanelBusy = $bindable(false),
    workbenchDirtyLabel = $bindable(''),
    projectAdminTab,
    projectAdminTabNonce,
    plotLabelNumber,
    pictureManagerPlot,
    stateReads,
    refresh,
    onOpenPlot,
  }: {
    view: ShellViewId;
    panelHold: boolean;
    companionPanelBusy: boolean;
    localEditorBusy: boolean;
    secondaryPanelBusy: boolean;
    workbenchDirtyLabel: string;
    projectAdminTab: 'lifecycle' | 'compliance' | 'optimizeveg' | 'merge' | 'cloudsync';
    projectAdminTabNonce: number;
    plotLabelNumber: string;
    pictureManagerPlot: string;
    stateReads: ReadRequests;
    refresh: () => Promise<void>;
    onOpenPlot: (plotNumber: string) => void;
  } = $props();
</script>

{#if view === 'datasheet' && $projectState}
  {#key $projectState.contextId}
    {#await import('../datasheet/UniversalDatasheetGrid.svelte')}
      <p role="status" class="p-4 text-sm">Loading Universal Datasheet Grid...</p>
    {:then { default: UniversalDatasheetGrid }}
      <UniversalDatasheetGrid
        contextId={$projectState.contextId ?? ''}
        project={$projectState.activeProject}
        su={$projectState.activeSU}
        hierarchy={$projectState.activeHierarchy}
        onBusyChange={(value) => {
          localEditorBusy = value;
        }}
        onDirtyChange={(dirty) => {
          workbenchDirtyLabel = dirty ? 'datasheet' : '';
        }}
        {onOpenPlot}
      />
    {/await}
  {/key}
{:else if view === 'classification-explorer' && $projectState}
  {#await import('../classification/ClassificationExplorer.svelte')}
    <p role="status" class="p-4 text-sm">Loading Classification Explorer...</p>
  {:then { default: ClassificationExplorer }}
    <ClassificationExplorer
      contextId={$projectState.contextId ?? ''}
      project={$projectState.activeProject}
      su={$projectState.activeSU}
      hierarchy={$projectState.activeHierarchy}
      operationHeld={panelHold}
      onBusyChange={(value) => {
        localEditorBusy = value;
      }}
      onDirtyChange={(dirty) => {
        workbenchDirtyLabel = dirty ? 'classification-explorer' : '';
      }}
      onContextChanged={async () => {
        await refresh();
      }}
      {onOpenPlot}
    />
  {/await}
{:else if view === 'project-admin' && $projectState && !IS_WEB_READONLY}
  <div class="p-3 space-y-4">
    {#await import('../admin/ProjectAdminWorkbench.svelte')}
      <p role="status" class="p-4 text-sm">Loading Project Admin Workbench...</p>
    {:then { default: ProjectAdminWorkbench }}
      <ProjectAdminWorkbench
        contextId={$projectState.contextId ?? ''}
        activeProject={$projectState.activeProject}
        activeSu={$projectState.activeSU}
        initialTab={projectAdminTab}
        initialTabNonce={projectAdminTabNonce}
        operationHeld={panelHold || companionPanelBusy}
        onBusyChange={(value) => {
          localEditorBusy = value;
        }}
        onprojectlistchanged={async () => {
          const nextState = await stateReads.track(ContextService.GetState());
          projectState.set(nextState);
        }}
        oncontextswitched={async () => {
          await refresh();
        }}
      />
    {/await}
    {#await import('../admin/ProjectMetadataPresets.svelte') then { default: ProjectMetadataPresets }}
      <ProjectMetadataPresets
        contextId={$projectState.contextId ?? ''}
        projectId=""
        operationHeld={panelHold || localEditorBusy}
        onBusyChange={(value) => {
          secondaryPanelBusy = value;
        }}
      />
    {/await}
  </div>
{:else if view === 'lump-editor' && $projectState}
  {#key $projectState.contextId}
    {#await import('../classification/LumpEditor.svelte')}
      <p role="status" class="p-4 text-sm">Loading Combine Species...</p>
    {:then { default: LumpEditor }}
      <LumpEditor
        contextId={$projectState.contextId ?? ''}
        operationHeld={panelHold}
        onBusyChange={(value) => {
          localEditorBusy = value;
        }}
      />
    {/await}
  {/key}
{:else if view === 'diagnostic-synthesis' && $projectState}
  {#key $projectState.contextId}
    {#await import('../diagnostics/ClassificationSynthesisView.svelte')}
      <p role="status" class="p-4 text-sm">Loading BEC Diagnostic &amp; Pairwise Synthesis...</p>
    {:then { default: ClassificationSynthesisView }}
      <ClassificationSynthesisView
        contextId={$projectState.contextId ?? ''}
        project={$projectState.activeProject}
        su={$projectState.activeSU}
        onBusyChange={(value) => {
          localEditorBusy = value;
        }}
        {onOpenPlot}
      />
    {/await}
  {/key}
{:else if view === 'r-sidecar' && $projectState}
  {#key $projectState.contextId}
    {#await import('../rsidecar/RSidecarWorkbench.svelte')}
      <p role="status" class="p-4 text-sm">Loading R Companion &amp; Guides...</p>
    {:then { default: RSidecarWorkbench }}
      <RSidecarWorkbench
        contextId={$projectState.contextId ?? ''}
        activeProject={$projectState.activeProject}
        activeSu={$projectState.activeSU}
        operationHeld={panelHold}
        onBusyChange={(value) => {
          localEditorBusy = value;
        }}
        oncontextswitched={async () => {
          await refresh();
        }}
      />
    {/await}
  {/key}
{:else if view === 'quarto-unit-report' && $projectState}
  {#key `${$projectState.contextId}:quarto-unit-report`}
    {#await import('../rsidecar/RSidecarWorkbench.svelte')}
      <p role="status" class="p-4 text-sm">Loading Quarto Unit Report...</p>
    {:then { default: RSidecarWorkbenchModule }}
      {@const RSidecarWorkbench = RSidecarWorkbenchModule as unknown as import('svelte').Component<{
        contextId: string;
        activeProject: string;
        activeSu?: string;
        initialTab?: 'runtime' | 'edatopic' | 'clustering' | 'quarto';
        operationHeld?: boolean;
        onBusyChange?: (busy: boolean) => void;
        oncontextswitched?: (state: unknown) => void;
      }>}
      <RSidecarWorkbench
        contextId={$projectState.contextId ?? ''}
        activeProject={$projectState.activeProject}
        activeSu={$projectState.activeSU}
        initialTab="quarto"
        operationHeld={panelHold}
        onBusyChange={(value) => {
          localEditorBusy = value;
        }}
        oncontextswitched={async () => {
          await refresh();
        }}
      />
    {/await}
  {/key}
{:else if view === 'geospatial-map' && $projectState}
  {#key $projectState.contextId}
    {#await import('../spatial/GeospatialWorkbench.svelte')}
      <p role="status" class="p-4 text-sm">Loading Map...</p>
    {:then { default: GeospatialWorkbench }}
      <GeospatialWorkbench
        contextId={$projectState.contextId ?? ''}
        project={$projectState.activeProject}
        su={$projectState.activeSU}
        onBusyChange={(value) => {
          localEditorBusy = value;
        }}
        onContextChanged={async () => {
          await refresh();
        }}
        {onOpenPlot}
      />
    {/await}
  {/key}
{:else if view === 'interchange-hub' && $projectState}
  {#key $projectState.contextId}
    {#await import('../interchange/InterchangeHub.svelte')}
      <p role="status" class="p-4 text-sm">Loading Interchange Hub...</p>
    {:then { default: InterchangeHub }}
      <InterchangeHub
        contextId={$projectState.contextId ?? ''}
        operationHeld={panelHold}
        onBusyChange={(value) => {
          localEditorBusy = value;
        }}
        onProjectActivated={async () => {
          await refresh();
        }}
      />
    {/await}
  {/key}
{:else if view === 'summary-environment' && $projectState}
  {#await import('../reports/SiteUnitSummary.svelte')}
    <p role="status" class="p-4 text-sm">Loading Site Unit Summary...</p>
  {:then { default: SiteUnitSummary }}
    {#key $projectState.contextId}<SiteUnitSummary
        contextId={$projectState.contextId ?? ''}
        project={$projectState.activeProject}
        projectPath={$projectState.projectPath ?? ''}
        su={$projectState.activeSU}
        suPath={$projectState.suPath ?? ''}
        onBusyChange={(value) => {
          localEditorBusy = value;
        }}
      />{/key}
  {:catch loadError}<p class="error" role="alert">Site Unit Summary could not load: {formatError(loadError)}</p>{/await}
{:else if view === 'long-environment' && $projectState}
  {#await import('../reports/LongEnvironmentReport.svelte')}
    <p role="status" class="p-4 text-sm">Loading Long Environment Report...</p>
  {:then { default: LongEnvironmentReport }}
    {#key $projectState.contextId}<LongEnvironmentReport
        contextId={$projectState.contextId ?? ''}
        project={$projectState.activeProject}
        projectPath={$projectState.projectPath ?? ''}
        su={$projectState.activeSU}
        suPath={$projectState.suPath ?? ''}
        onBusyChange={(value) => {
          localEditorBusy = value;
        }}
      />{/key}
  {:catch loadError}<p class="error" role="alert">
      Long Environment Report could not load: {formatError(loadError)}
    </p>{/await}
{:else if view === 'long-vegetation' && $projectState}
  {#await import('../reports/LongVegetationReport.svelte')}
    <p role="status" class="p-4 text-sm">Loading Long Vegetation Report...</p>
  {:then { default: LongVegetationReport }}
    {#key $projectState.contextId}<LongVegetationReport
        contextId={$projectState.contextId ?? ''}
        project={$projectState.activeProject}
        projectPath={$projectState.projectPath ?? ''}
        su={$projectState.activeSU}
        suPath={$projectState.suPath ?? ''}
        hierarchy={$projectState.activeHierarchy ?? 'None'}
        operationHeld={panelHold}
        onBusyChange={(value) => {
          localEditorBusy = value;
        }}
      />{/key}
  {:catch loadError}<p class="error" role="alert">
      Long Vegetation Report could not load: {formatError(loadError)}
    </p>{/await}
{:else if view === 'summary-vegetation' && $projectState}
  {#await import('../reports/SummaryVegetationReport.svelte')}
    <p role="status" class="p-4 text-sm">Loading Summary Vegetation Report...</p>
  {:then { default: SummaryVegetationReport }}
    {#key $projectState.contextId}<SummaryVegetationReport
        contextId={$projectState.contextId ?? ''}
        project={$projectState.activeProject}
        projectPath={$projectState.projectPath ?? ''}
        su={$projectState.activeSU}
        suPath={$projectState.suPath ?? ''}
        hierarchy={$projectState.activeHierarchy ?? 'None'}
        operationHeld={panelHold}
        onBusyChange={(value) => {
          localEditorBusy = value;
        }}
        onExclusionBusyChange={(value) => {
          secondaryPanelBusy = value;
        }}
      />{/key}
  {:catch loadError}<p class="error" role="alert">
      Summary Vegetation Report could not load: {formatError(loadError)}
    </p>{/await}
{:else if view === 'lifeform-summary' && $projectState}
  {#await import('../reports/LifeformSummary.svelte')}
    <p role="status" class="p-4 text-sm">Loading Lifeform Summary...</p>
  {:then { default: LifeformSummary }}
    {#key $projectState.contextId}<LifeformSummary
        contextId={$projectState.contextId ?? ''}
        project={$projectState.activeProject}
        projectPath={$projectState.projectPath ?? ''}
        su={$projectState.activeSU}
        suPath={$projectState.suPath ?? ''}
        onBusyChange={(value) => {
          localEditorBusy = value;
        }}
      />{/key}
  {:catch loadError}<p class="error" role="alert">Lifeform Summary could not load: {formatError(loadError)}</p>{/await}
{:else if view === 'table-csv' && $projectState}
  {#await import('../interchange/ProjectTableCSVReview.svelte')}
    <p role="status" class="p-4 text-sm">Loading Table CSV Review...</p>
  {:then { default: ProjectTableCSVReview }}
    {#key $projectState.contextId}<ProjectTableCSVReview
        contextId={$projectState.contextId ?? ''}
        project={$projectState.activeProject}
        projectPath={$projectState.projectPath ?? ''}
        onBusyChange={(value) => {
          localEditorBusy = value;
        }}
      />{/key}
  {:catch loadError}<p class="error" role="alert">Table CSV Review could not load: {formatError(loadError)}</p>{/await}
{:else if view === 'user-log' && $projectState && !IS_WEB_READONLY}
  {#await import('../admin/UserLogReview.svelte')}
    <p role="status" class="p-4 text-sm">Loading User Log Review...</p>
  {:then { default: UserLogReview }}
    {#key $projectState.contextId}<UserLogReview
        contextId={$projectState.contextId ?? ''}
        operationHeld={panelHold}
        onBusyChange={(value) => {
          localEditorBusy = value;
        }}
      />{/key}
  {:catch loadError}<p class="error" role="alert">User Log Review could not load: {formatError(loadError)}</p>{/await}
{:else if view === 'plot-label-preview' && $projectState}
  {#await import('../interchange/PlotLabelPreview.svelte')}
    <p role="status" class="p-4 text-sm">Loading Plot Label Preview...</p>
  {:then { default: PlotLabelPreview }}
    {#key $projectState.contextId}<PlotLabelPreview
        contextId={$projectState.contextId ?? ''}
        project={$projectState.activeProject}
        projectPath={$projectState.projectPath ?? ''}
        su={$projectState.activeSU}
        suPath={$projectState.suPath ?? ''}
        initialPlot={plotLabelNumber}
        onBusyChange={(value) => {
          localEditorBusy = value;
        }}
      />{/key}
  {:catch loadError}<p class="error" role="alert">
      Plot Label Preview could not load: {formatError(loadError)}
    </p>{/await}
{:else if view === 'picture-manager' && $projectState && (!IS_WEB_READONLY || $webMeta?.picturesAvailable !== false)}
  {#await import('../pictures/PictureManager.svelte')}
    <p role="status" class="p-4 text-sm">Loading Picture Manager...</p>
  {:then { default: PictureManager }}
    {#key $projectState.contextId}<PictureManager
        contextId={$projectState.contextId ?? ''}
        project={$projectState.activeProject}
        initialPlot={pictureManagerPlot}
        onBusyChange={(value) => {
          localEditorBusy = value;
        }}
      />{/key}
  {:catch loadError}<p class="error" role="alert">Picture Manager could not load: {formatError(loadError)}</p>{/await}
{:else if view === 'plot-locations' && $projectState}
  {#await import('../spatial/PlotLocationReview.svelte')}
    <p role="status" class="p-4 text-sm">Loading Plot Location Review...</p>
  {:then { default: PlotLocationReview }}
    {#key $projectState.contextId}<PlotLocationReview
        contextId={$projectState.contextId ?? ''}
        project={$projectState.activeProject}
        projectPath={$projectState.projectPath ?? ''}
        su={$projectState.activeSU}
        suPath={$projectState.suPath ?? ''}
        onBusyChange={(value) => {
          localEditorBusy = value;
        }}
      />{/key}
  {:catch loadError}<p class="error" role="alert">
      Plot Location Review could not load: {formatError(loadError)}
    </p>{/await}
{:else if view === 'google-earth-review' && $projectState}
  {#await import('../spatial/GoogleEarthReview.svelte')}
    <p role="status" class="p-4 text-sm">Loading Google Earth Review...</p>
  {:then { default: GoogleEarthReview }}
    {#key $projectState.contextId}<GoogleEarthReview
        contextId={$projectState.contextId ?? ''}
        project={$projectState.activeProject}
        projectPath={$projectState.projectPath ?? ''}
        su={$projectState.activeSU}
        suPath={$projectState.suPath ?? ''}
        onBusyChange={(value) => {
          localEditorBusy = value;
        }}
      />{/key}
  {:catch loadError}<p class="error" role="alert">
      Google Earth Review could not load: {formatError(loadError)}
    </p>{/await}
{:else if view === 'subzone-matrix' && $projectState}
  {#await import('../reports/SubzoneMatrixReport.svelte')}
    <p role="status" class="p-4 text-sm">Loading Subzone Matrix Report...</p>
  {:then { default: SubzoneMatrixReport }}
    {#key $projectState.contextId}<SubzoneMatrixReport
        contextId={$projectState.contextId ?? ''}
        hierarchy={$projectState.activeHierarchy}
        hierarchyPath={$projectState.hierarchyPath ?? ''}
        onBusyChange={(value) => {
          localEditorBusy = value;
        }}
      />{/key}
  {:catch loadError}<p class="error" role="alert">
      Subzone Matrix Report could not load: {formatError(loadError)}
    </p>{/await}
{/if}
