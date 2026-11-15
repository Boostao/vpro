<script lang="ts">
  import type { PlotProfileSource, ProjectPlotProfileFilterRequest } from '../../bindings/github.com/boostao/vpro/app';
  import PicturePanel from '../pictures/PicturePanel.svelte';
  import SourceChild from './SourceChild.svelte';
  import type { EditorCloseState } from '../shell/closeLifecycle';
  import type { PaperControl } from './paperLayout';
  import type { SIVIParentActionWriteSession } from './siviParentActionWriteSession';
  import type { SIVIParentInput } from './siviParentEditor';
  import type { SIVIParentReadSession, SIVIParentReadView } from './siviParentReadSession';
  import type { SIVIParentSharedColumn, SIVIParentSharedInput, SIVIParentSharedSession, SIVIParentSharedView } from './siviParentSharedSession';
  import type { SIVIParentSourceSession, SIVIParentSourceView } from './siviParentSourceSession';
  import type { SIVIParentWriteSession, SIVIParentWriteView } from './siviParentWriteSession';
  import type { SIVIProjectAssignmentInput, SIVIProjectAssignmentSession, SIVIProjectAssignmentView } from './siviProjectAssignmentSession';
  import type { TwoPageEntryChild } from './twoPageEntryProjection';
  import type { TwoPageEntrySessionCache } from './twoPageEntrySession';
  import type { TwoPageParentCommonSessionCache } from './twoPageParentCommonSession';
  import type { TwoPageParentForm, TwoPageParentSessionCache } from './twoPageParentSession';
  import type { TwoPageVegetationForm } from './twoPageVegetationWire';

  export interface FS882SubEditorLoaders {
    environmentSU: () => Promise<{ default: typeof import('../classification/EnvironmentSUTransfer.svelte').default }>;
    externalSU: () => Promise<{ default: typeof import('../classification/ExternalSUEnvironmentTransfer.svelte').default }>;
    profileReview: () => Promise<{ default: typeof import('../classification/ProjectPlotProfileReview.svelte').default }>;
    twoPageEntry: () => Promise<{ default: typeof import('./TwoPageEntryEditor.svelte').default }>;
    twoPageCommon: () => Promise<{ default: typeof import('./TwoPageParentCommonEditor.svelte').default }>;
    twoPageExtra: () => Promise<{ default: typeof import('./TwoPageParentEditor.svelte').default }>;
    twoPageSoil: () => Promise<{ default: typeof import('./TwoPageSoilPanel.svelte').default }>;
    twoPageVegetation: () => Promise<{ default: typeof import('./TwoPageVegetationPanel.svelte').default }>;
    projectMetadata: () => Promise<{ default: typeof import('../admin/ProjectMetadataEditor.svelte').default }>;
    speciesCodeCheck: () => Promise<{ default: typeof import('./SpeciesCodeCheck.svelte').default }>;
  }

  let {
    loaders,
    loadSubEditor,
    environmentSUEditor = $bindable(),
    profileEditor = $bindable(),
    twoPageEditor = $bindable(),
    metadataEditor = $bindable(),
    codeCheckEditor = $bindable(),
    twoPageOpen = $bindable(),
    twoPageBusy = $bindable(),
    twoPageProject = $bindable(),
    twoPageRevision = $bindable(),
    profileReviewOpen = $bindable(),
    profileReviewBusy = $bindable(),
    profileReviewBlocked = $bindable(),
    environmentSUOpen = $bindable(),
    metadataOpen = $bindable(),
    metadataBusy = $bindable(),
    codeCheckOpen = $bindable(),
    codeCheckBusy = $bindable(),
    pictureBusy = $bindable(),
    contextId,
    draft,
    plotNumber,
    originalPlotNumber,
    activeProject,
    activeSU,
    projectPath,
    suPath,
    plotProfileWritable,
    plotProfileSource,
    busy,
    dirty,
    childUnsaved,
    headerValidation,
    activeTab,
    siviStandalone,
    siviStandaloneEnabled,
    siviParentOpen,
    siviParentSession, siviParentView, siviParentSourceSession, siviParentSourceView, siviParentBusy, siviSourceBarrier,
    siviParentSharedColumns, siviParentSharedSession, siviParentSharedView, siviParentSharedClose, siviParentSharedUnsaved, siviParentSharedEditingDisabled,
    siviParentWriteSession, siviParentWriteView, siviParentWriteClose, siviParentWriteEditingDisabled,
    siviParentActionSession, siviParentActionView, siviParentActionClose, siviParentActionEditingDisabled,
    siviProjectAssignmentSession, siviProjectAssignmentView, siviProjectAssignmentClose, siviProjectAssignmentEditingDisabled,
    extendedShrubs, extendedShrubsEnabled, setExtendedShrubs,
    snowCoverRegimeInput, activeLayerDepthInput, arcticInputsDisabled, snowCoverRegimeSupported, activeLayerDepthSupported,
    stageSnowCoverRegime, stageActiveLayerDepth,
    metadataEnabled, metadataCreationEnabled, metadataTemplateCreationEnabled, metadataRestorationEnabled,
    openProjectMetadata, canOpenProjectMetadata,
    stageSIVIParentShared, siviParentSharedOperation, stageSIVIParentCell, siviParentWriteOperation,
    stageSIVIParentAction, siviParentActionOperation, stageSIVIProjectAssignment, siviProjectAssignmentOperation,
    reloadSIVIProjectSource, changeSIVIProjectSource,
    PlotService, environmentSUDirection,
    profileReviewEnabled, profileRunEnabled, profileSpeciesPresenceEnabled, profileEditingEnabled,
    profileCreationEnabled, profileDeletionEnabled, profileFilteringEnabled, profileSaveSUEnabled,
    onProfileSUReview, onProfileNavigation,
    twoPageScope, twoPageEntryInitialForm,
    twoPageSessions, twoPageCommonSessions, twoPageEntrySessions,
    twoPageSoilReviewEnabled, twoPageVegetationReviewEnabled, pictureReadingEnabled,
    ordinaryVegetationUnavailable, ordinarySoilUnavailable,
    twoPageLinkedParentBlocked, twoPageSoilParentBlocked, linkedVegetationParentBlocked,
    twoPageSoilBusy, twoPageSoilBlocked, twoPageVegetationBusy, twoPageVegetationBlocked, pictureMetadataPending,
    externalSUEnvironmentEnabled, separateSUSelected,
    childRevision, sourceRows,
    openProfileSUFromTwoPage, refreshTwoPagePeers, refreshProjectMetadata, loadPlot, loadChildData, onClearError,
  }: {
    loaders: FS882SubEditorLoaders;
    loadSubEditor: <T>(loader: () => Promise<T>, label: string, onFailed: () => void) => Promise<T>;
    environmentSUEditor: { getCloseState(): EditorCloseState; undo(): void } | undefined;
    profileEditor: { getCloseState(): EditorCloseState; undo(): void } | undefined;
    twoPageEditor: { getCloseState(): EditorCloseState; getDraftState?(): EditorCloseState; undo(): void; canOpenMetadataEditor?(): boolean; openMetadataEditor?(): void } | undefined;
    metadataEditor: { getCloseState(): EditorCloseState; undo(): void } | undefined;
    codeCheckEditor: { getCloseState(): EditorCloseState; undo(): void } | undefined;
    twoPageOpen: boolean; twoPageBusy: boolean; twoPageProject: string | null; twoPageRevision: number;
    profileReviewOpen: boolean; profileReviewBusy: boolean; profileReviewBlocked: boolean;
    environmentSUOpen: boolean;
    metadataOpen: boolean; metadataBusy: boolean;
    codeCheckOpen: boolean; codeCheckBusy: boolean;
    pictureBusy: boolean;
    contextId: string; draft: { plotNumber: string }; plotNumber: string; originalPlotNumber: string | undefined;
    activeProject: string; activeSU: string; projectPath: string; suPath: string;
    plotProfileWritable: boolean; plotProfileSource: PlotProfileSource | null;
    busy: boolean; dirty: boolean; childUnsaved: boolean; headerValidation: Record<string, string>;
    activeTab: string; siviStandalone: boolean; siviStandaloneEnabled: boolean; siviParentOpen: boolean;
    siviParentSession: SIVIParentReadSession | null; siviParentView: SIVIParentReadView | null;
    siviParentSourceSession: SIVIParentSourceSession | null; siviParentSourceView: SIVIParentSourceView | null;
    siviParentBusy: boolean; siviSourceBarrier: boolean;
    siviParentSharedColumns: readonly SIVIParentSharedColumn[];
    siviParentSharedSession: SIVIParentSharedSession | null; siviParentSharedView: SIVIParentSharedView | null;
    siviParentSharedClose: EditorCloseState | null; siviParentSharedUnsaved: boolean; siviParentSharedEditingDisabled: boolean;
    siviParentWriteSession: SIVIParentWriteSession | null; siviParentWriteView: SIVIParentWriteView | null;
    siviParentWriteClose: EditorCloseState | null; siviParentWriteEditingDisabled: boolean;
    siviParentActionSession: SIVIParentActionWriteSession | null; siviParentActionView: SIVIParentWriteView | null;
    siviParentActionClose: EditorCloseState | null; siviParentActionEditingDisabled: boolean;
    siviProjectAssignmentSession: SIVIProjectAssignmentSession | null; siviProjectAssignmentView: SIVIProjectAssignmentView | null;
    siviProjectAssignmentClose: EditorCloseState | null; siviProjectAssignmentEditingDisabled: boolean;
    extendedShrubs: boolean; extendedShrubsEnabled: boolean; setExtendedShrubs: (v: boolean) => void;
    snowCoverRegimeInput: string; activeLayerDepthInput: string; arcticInputsDisabled: boolean;
    snowCoverRegimeSupported: boolean; activeLayerDepthSupported: boolean;
    stageSnowCoverRegime: (raw: string) => void; stageActiveLayerDepth: (raw: string) => void;
    metadataEnabled: boolean; metadataCreationEnabled: boolean; metadataTemplateCreationEnabled: boolean; metadataRestorationEnabled: boolean;
    openProjectMetadata: () => void; canOpenProjectMetadata: () => boolean;
    stageSIVIParentShared: (col: SIVIParentSharedColumn, input: SIVIParentSharedInput) => void;
    siviParentSharedOperation: (op: 'load' | 'save' | 'undo' | 'retain' | 'prune') => Promise<boolean>;
    stageSIVIParentCell: (col: string, input: SIVIParentInput) => void;
    siviParentWriteOperation: (op: 'load' | 'save' | 'undo' | 'retain' | 'prune') => Promise<boolean>;
    stageSIVIParentAction: (col: string, input: SIVIParentInput) => void;
    siviParentActionOperation: (op: 'load' | 'save' | 'undo' | 'retain' | 'prune') => Promise<boolean>;
    stageSIVIProjectAssignment: (input: SIVIProjectAssignmentInput) => void;
    siviProjectAssignmentOperation: (op: 'load' | 'save' | 'undo' | 'retain' | 'prune') => Promise<boolean>;
    reloadSIVIProjectSource: () => Promise<void>;
    changeSIVIProjectSource: (source: number) => Promise<void>;
    PlotService: typeof import('../../bindings/github.com/boostao/vpro/app').PlotEntryService & ReturnType<typeof import('../shared/contextPlots').bindContextPlots>;
    environmentSUDirection: 'forward' | 'reverse' | 'external-reverse';
    profileReviewEnabled: boolean; profileRunEnabled: boolean; profileSpeciesPresenceEnabled: boolean; profileEditingEnabled: boolean;
    profileCreationEnabled: boolean; profileDeletionEnabled: boolean; profileFilteringEnabled: boolean; profileSaveSUEnabled: boolean;
    onProfileSUReview?: (proposal: ProjectPlotProfileFilterRequest, contextId: string) => Promise<void>;
    onProfileNavigation?: (proposal: ProjectPlotProfileFilterRequest, contextId: string) => Promise<void>;
    twoPageScope: 'extra' | 'common' | 'entry'; twoPageEntryInitialForm: TwoPageParentForm;
    twoPageSessions: TwoPageParentSessionCache; twoPageCommonSessions: TwoPageParentCommonSessionCache; twoPageEntrySessions: TwoPageEntrySessionCache;
    twoPageSoilReviewEnabled: boolean; twoPageVegetationReviewEnabled: boolean; pictureReadingEnabled: boolean;
    ordinaryVegetationUnavailable: string | null; ordinarySoilUnavailable: string | null;
    twoPageLinkedParentBlocked: boolean; twoPageSoilParentBlocked: boolean;
    linkedVegetationParentBlocked: (form: TwoPageVegetationForm) => boolean;
    twoPageSoilBusy: boolean; twoPageSoilBlocked: boolean; twoPageVegetationBusy: boolean; twoPageVegetationBlocked: boolean; pictureMetadataPending: boolean;
    externalSUEnvironmentEnabled: boolean; separateSUSelected: boolean;
    childRevision: number;
    sourceRows: (name: string) => Array<{ id: number; values: Record<string, string | number | boolean | null | undefined> }>;
    openProfileSUFromTwoPage: () => void;
    refreshTwoPagePeers: (scope: 'extra' | 'common' | 'entry') => Promise<void>;
    refreshProjectMetadata: () => Promise<void>;
    loadPlot: (p?: string) => Promise<void>;
    loadChildData: (p: string) => Promise<void>;
    onClearError: () => void;
  } = $props();
</script>

{#snippet sharedSIVIFields()}
  {#if siviParentSharedView}
    {#await import('./SIVIParentSharedFields.svelte')}
      <p role="status" class="p-2 text-xs">Loading shared SIVI fields...</p>
    {:then { default: SIVIParentSharedFields }}
      <SIVIParentSharedFields view={siviParentSharedView} disabled={siviParentSharedEditingDisabled}
        canSave={siviParentSharedClose?.canSave ?? false} onstage={stageSIVIParentShared}
        onoperation={operation => { void siviParentSharedOperation(operation); }}
        onreferences={() => { void siviParentSharedSession?.refreshReferences(); }}
        oncancel={() => siviParentSharedSession?.cancel()}
        {extendedShrubs}
        onExtendedShrubsChange={extendedShrubsEnabled ? setExtendedShrubs : undefined}
        snowCoverRegime={snowCoverRegimeInput}
        activeLayerDepth={activeLayerDepthInput}
        snowCoverRegimeDisabled={arcticInputsDisabled || !snowCoverRegimeSupported}
        activeLayerDepthDisabled={arcticInputsDisabled || !activeLayerDepthSupported}
        snowCoverRegimeError={headerValidation.snowCoverRegime ?? null}
        activeLayerDepthError={headerValidation.activeLayerDepth ?? null}
        onSnowCoverRegimeChange={stageSnowCoverRegime}
        onActiveLayerDepthChange={stageActiveLayerDepth} />
    {:catch loadError}
      <p role="alert" class="p-2 text-xs text-red-700">Shared SIVI fields could not load: {String(loadError)}</p>
    {/await}
  {/if}
{/snippet}
{#if activeTab === 'siviParent' && siviParentOpen && siviParentView && !metadataOpen && (!siviStandalone || siviStandaloneEnabled)}
  {#await import('./SIVIParentReadPanel.svelte')}
    <p role="status" class="p-3 text-xs">Loading SIVI parent panel...</p>
  {:then { default: SIVIParentReadPanel }}
    <SIVIParentReadPanel view={siviParentView} sourceView={siviParentSourceView}
      sharedEditor={siviParentSharedView ? {
        liveColumns: siviParentSharedView.original ? siviParentSharedColumns : [],
        content: sharedSIVIFields, busy: siviParentSharedView.busy,
        unsaved: siviParentSharedUnsaved || (siviParentSharedClose?.blocked ?? false),
      } : null}
      onMetadata={metadataEnabled ? openProjectMetadata : undefined}
      metadataDisabled={!canOpenProjectMetadata()}
      writeView={siviParentWriteView} writeDisabled={siviParentWriteEditingDisabled}
      writeCanSave={siviParentWriteClose?.canSave ?? false}
      onWriteOperation={operation => { void siviParentWriteOperation(operation); }}
      onWriteStage={stageSIVIParentCell}
      onWriteCancel={() => siviParentWriteSession?.cancel()}
      actionView={siviParentActionView} actionDisabled={siviParentActionEditingDisabled}
      actionCanSave={siviParentActionClose?.canSave ?? false}
      onActionOperation={operation => { void siviParentActionOperation(operation); }}
      onActionStage={stageSIVIParentAction}
      onActionCancel={() => siviParentActionSession?.cancel()}
      assignmentView={siviProjectAssignmentView} assignmentDisabled={siviProjectAssignmentEditingDisabled}
      assignmentCanSave={siviProjectAssignmentClose?.canSave ?? false}
      onAssignmentOperation={operation => { void siviProjectAssignmentOperation(operation); }}
      onAssignmentStage={stageSIVIProjectAssignment}
      onAssignmentCancel={() => siviProjectAssignmentSession?.cancel()}
      reloadDisabled={busy || dirty || childUnsaved || siviParentBusy}
      onreload={() => { if (siviParentSession) void siviParentSession.load(); }}
      onSourceReload={() => { void reloadSIVIProjectSource(); }}
      onSourceCancel={() => siviParentSourceSession?.cancel()}
      onSourceChange={source => { void changeSIVIProjectSource(source); }}
      oncancel={() => siviParentSession?.cancel()} />
  {:catch loadError}
    <p role="alert" class="p-3 text-xs text-red-700">SIVI parent panel could not load: {String(loadError)}</p>
  {/await}
{/if}
{#if environmentSUOpen && environmentSUDirection !== 'external-reverse' && projectPath}
  {#await loadSubEditor(loaders.environmentSU, 'SU transfer review', () => { environmentSUOpen = false; })}
    <p role="status" class="p-3 text-xs">Loading SU transfer review...</p>
  {:then { default: EnvironmentSUTransfer }}
    <EnvironmentSUTransfer bind:this={environmentSUEditor} client={PlotService} {contextId}
      project={activeProject} su={activeSU} path={projectPath}
      direction={environmentSUDirection === 'reverse' ? 'reverse' : 'forward'}
      onclosed={() => { environmentSUOpen = false; onClearError(); if (environmentSUDirection === 'reverse') void loadPlot(originalPlotNumber); }} />
  {:catch loadError}
    <p role="alert" class="p-3 text-xs text-red-700">SU transfer review could not load: {String(loadError)}</p>
  {/await}
{/if}
{#if environmentSUOpen && environmentSUDirection === 'external-reverse' && projectPath && suPath}
  {#await loadSubEditor(loaders.externalSU, 'External SU transfer review', () => { environmentSUOpen = false; })}
    <p role="status" class="p-3 text-xs">Loading external SU transfer review...</p>
  {:then { default: ExternalSUEnvironmentTransfer }}
    <ExternalSUEnvironmentTransfer bind:this={environmentSUEditor} {contextId}
      project={activeProject} {projectPath}
      su={activeSU} {suPath}
      onclosed={() => { environmentSUOpen = false; onClearError(); void loadPlot(originalPlotNumber); }} />
  {:catch loadError}
    <p role="alert" class="p-3 text-xs text-red-700">External SU transfer review could not load: {String(loadError)}</p>
  {/await}
{/if}
{#if profileReviewOpen}
  {#await loadSubEditor(loaders.profileReview, 'Project plot profile review', () => { profileReviewOpen = false; profileReviewBusy = false; profileReviewBlocked = false; })}
    <p role="status" class="p-3 text-xs">Loading project plot profile review...</p>
  {:then { default: ProjectPlotProfileReview }}
    {#if profileReviewOpen}
      <ProjectPlotProfileReview bind:this={profileEditor} client={PlotService} allowRun={profileRunEnabled}
        allowPresence={profileSpeciesPresenceEnabled && Boolean(activeProject)} {contextId} {activeSU}
        authorityBlocked={siviSourceBarrier}
        allowEditing={profileEditingEnabled && plotProfileWritable} allowCreation={profileCreationEnabled} allowDeletion={profileDeletionEnabled}
        allowSaveSU={profileSaveSUEnabled} onsureview={async proposal => {
          if (!onProfileSUReview) throw new Error('Save as SU review is unavailable.');
          await onProfileSUReview(proposal, contextId);
        }} allowFiltering={profileFilteringEnabled} onapply={async proposal => {
          if (!onProfileNavigation) throw new Error('Profile navigation publication is unavailable.');
          await onProfileNavigation(proposal, contextId);
        }}
        onblocked={value => profileReviewBlocked = value} onbusy={value => profileReviewBusy = value}
        onclosed={() => { profileReviewOpen = false; }} />
    {/if}
  {:catch loadError}
    <p role="alert" class="p-3 text-xs text-red-700">Project plot profile review could not load: {String(loadError)}</p>
  {/await}
{/if}
{#snippet twoPageLinkedChild(child: TwoPageEntryChild, _control: PaperControl)}
  {#if twoPageSoilReviewEnabled && twoPageScope === 'entry' && twoPageProject !== null &&
    (child.form === 'SoilHumusXL' || child.form === 'SoilMineralXL')}
    {#await loaders.twoPageSoil()}
      <p role="status" class="p-2 text-xs">Loading linked soil panel...</p>
    {:then { default: TwoPageSoilPanel }}
      <TwoPageSoilPanel {contextId} project={twoPageProject} plot={draft.plotNumber} form={child.form}
        parentBlocked={twoPageSoilParentBlocked} />
    {:catch loadError}
      <p role="alert" class="p-2 text-xs text-red-700">Linked soil panel could not load: {String(loadError)}</p>
    {/await}
  {:else if twoPageVegetationReviewEnabled && twoPageScope === 'entry' && twoPageProject !== null &&
    (child.form === 'SubVegAXL_BC' || child.form === 'SubVegAXL' || child.form === 'SubVegCXL' || child.form === 'SubVegDXL')}
    {#await loaders.twoPageVegetation()}
      <p role="status" class="p-2 text-xs">Loading linked vegetation panel...</p>
    {:then { default: TwoPageVegetationPanel }}
      {#key JSON.stringify([contextId, twoPageProject, draft.plotNumber, child.form])}
        <TwoPageVegetationPanel {contextId} project={twoPageProject} plot={draft.plotNumber} form={child.form}
          parentBlocked={linkedVegetationParentBlocked(child.form)} />
      {/key}
    {:catch loadError}
      <p role="alert" class="p-2 text-xs text-red-700">Linked vegetation panel could not load: {String(loadError)}</p>
    {/await}
  {:else if pictureReadingEnabled && twoPageScope === 'entry' && twoPageProject !== null && child.form === 'frmVPicsXL'}
    <div data-two-page-picture-child={child.form} data-source-control={_control.controlId}
      data-source-image-control="form:frmVPicsXL/imgCtl">
      <PicturePanel {contextId} project={twoPageProject} plotNumber={draft.plotNumber} view="child"
        observeMutationReceipts={false}
        disabled={twoPageLinkedParentBlocked || twoPageSoilBusy || twoPageSoilBlocked || twoPageVegetationBusy || twoPageVegetationBlocked}
        onBusyChange={(pending) => pictureBusy = pending} />
    </div>
  {:else if ordinaryVegetationUnavailable && child.form.startsWith('SubVeg')}
    <p role="status" data-vegetation-ordinary-unavailable={child.form}>{ordinaryVegetationUnavailable}</p>
  {:else if ordinarySoilUnavailable && (child.form === 'SoilHumusXL' || child.form === 'SoilMineralXL')}
    <p role="status" data-soil-ordinary-unavailable={child.form}>{ordinarySoilUnavailable}</p>
  {:else}
    <SourceChild name={child.form} rows={sourceRows(child.form)} revision={childRevision} disabled={true} />
  {/if}
{/snippet}
{#if twoPageOpen && twoPageProject !== null}
  {#if twoPageScope === 'entry'}
    {#await loadSubEditor(loaders.twoPageEntry, 'Two-page complete entry', () => { twoPageOpen = false; twoPageBusy = false; twoPageProject = null; })}
      <p role="status" data-two-page-loading="entry" class="p-3 text-xs">Loading two-page complete entry...</p>
    {:then { default: TwoPageEntryEditor }}
      <TwoPageEntryEditor bind:this={twoPageEditor} {contextId} project={twoPageProject} plot={plotNumber}
        initialForm={twoPageEntryInitialForm}
        onExtendedShrubsChange={extendedShrubsEnabled ? setExtendedShrubs : undefined}
        pictureReaderAvailable={pictureReadingEnabled}
        auditReaderAvailable={true}
        googleEarthReaderAvailable={true}
        vegetationTableReaderAvailable={true}
        environmentTableReaderAvailable={true}
        projectMetadataReaderAvailable={true}
        projectMetadataClient={PlotService} metadataRestorationAvailable={metadataRestorationEnabled}
        profilingReaderAvailable={true}
        profilingSource={plotProfileSource}
        vegetationTableSU={activeSU}
        vegetationTableSUPath={suPath}
        sourceProjectPath={projectPath}
        externalScope={externalSUEnvironmentEnabled && separateSUSelected && !siviStandalone && projectPath && suPath
          ? { contextId, project: activeProject, projectPath, su: activeSU, suPath } : null}
        sourceBlocked={twoPageLinkedParentBlocked || Object.keys(headerValidation).length > 0 || twoPageSoilBusy || twoPageSoilBlocked || twoPageVegetationBusy || twoPageVegetationBlocked}
        cache={twoPageEntrySessions} revision={twoPageRevision} onchange={() => twoPageRevision++}
        childBlocked={twoPageSoilBusy || twoPageSoilBlocked || twoPageVegetationBusy || twoPageVegetationBlocked || pictureBusy || pictureMetadataPending}
        onbusy={value => twoPageBusy = value}
        onclosed={() => { twoPageOpen = false; twoPageBusy = false; twoPageProject = null; onClearError(); }}
        onOpenProfileSU={profileReviewEnabled && !siviStandalone ? openProfileSUFromTwoPage : undefined}
        oncommitted={() => refreshTwoPagePeers('entry')} embedded={twoPageLinkedChild} />
    {:catch loadError}
      <p role="alert" data-two-page-load-error="entry" class="p-3 text-xs text-red-700">Two-page complete entry could not load: {String(loadError)}</p>
    {/await}
  {:else if twoPageScope === 'common'}
    {#await loadSubEditor(loaders.twoPageCommon, 'Two-page common fields', () => { twoPageOpen = false; twoPageBusy = false; twoPageProject = null; })}
      <p role="status" data-two-page-loading="common" class="p-3 text-xs">Loading two-page common fields...</p>
    {:then { default: TwoPageParentCommonEditor }}
      <TwoPageParentCommonEditor bind:this={twoPageEditor} {contextId} project={twoPageProject} plot={plotNumber}
        initialForm={twoPageEntryInitialForm}
        onExtendedShrubsChange={extendedShrubsEnabled ? setExtendedShrubs : undefined}
        cache={twoPageCommonSessions} revision={twoPageRevision} onchange={() => twoPageRevision++}
        onbusy={value => twoPageBusy = value}
        onclosed={() => { twoPageOpen = false; twoPageBusy = false; twoPageProject = null; onClearError(); }}
        oncommitted={() => refreshTwoPagePeers('common')} embedded={twoPageLinkedChild} />
    {:catch loadError}
      <p role="alert" data-two-page-load-error="common" class="p-3 text-xs text-red-700">Two-page common fields could not load: {String(loadError)}</p>
    {/await}
  {:else}
    {#await loadSubEditor(loaders.twoPageExtra, 'Two-page additional fields', () => { twoPageOpen = false; twoPageBusy = false; twoPageProject = null; })}
      <p role="status" data-two-page-loading="extra" class="p-3 text-xs">Loading two-page additional fields...</p>
    {:then { default: TwoPageParentEditor }}
      <TwoPageParentEditor bind:this={twoPageEditor} {contextId} project={twoPageProject} plot={plotNumber}
        initialForm={twoPageEntryInitialForm}
        onExtendedShrubsChange={extendedShrubsEnabled ? setExtendedShrubs : undefined}
        cache={twoPageSessions} revision={twoPageRevision} onchange={() => twoPageRevision++}
        onbusy={value => twoPageBusy = value}
        onclosed={() => { twoPageOpen = false; twoPageBusy = false; twoPageProject = null; onClearError(); }}
        oncommitted={() => refreshTwoPagePeers('extra')} embedded={twoPageLinkedChild} />
    {:catch loadError}
      <p role="alert" data-two-page-load-error="extra" class="p-3 text-xs text-red-700">Two-page additional fields could not load: {String(loadError)}</p>
    {/await}
  {/if}
{/if}
{#if metadataOpen}
  {#await loadSubEditor(loaders.projectMetadata, 'Project metadata editor', () => { metadataOpen = false; metadataBusy = false; })}
    <p role="status" class="p-3 text-xs">Loading project metadata editor...</p>
  {:then { default: ProjectMetadataEditor }}
    <ProjectMetadataEditor bind:this={metadataEditor} client={PlotService} {contextId} plot={plotNumber}
      allowCreation={metadataCreationEnabled} allowTemplateCreation={metadataTemplateCreationEnabled}
      allowRestoration={metadataRestorationEnabled}
      onbusy={value => metadataBusy = value}
      onclosed={() => { metadataOpen = false; onClearError(); }}
      oncommitted={refreshProjectMetadata} />
  {:catch loadError}
    <p role="alert" class="p-3 text-xs text-red-700">Project metadata editor could not load: {String(loadError)}</p>
  {/await}
{/if}
{#if codeCheckOpen}
  {#await loadSubEditor(loaders.speciesCodeCheck, 'Species code check', () => { codeCheckOpen = false; codeCheckBusy = false; })}
    <p role="status" class="p-3 text-xs">Loading species code check...</p>
  {:then { default: SpeciesCodeCheck }}
    <SpeciesCodeCheck bind:this={codeCheckEditor} client={PlotService}
      onbusy={value => codeCheckBusy = value}
      onclosed={() => { codeCheckOpen = false; onClearError(); }}
      oncommitted={() => loadChildData(plotNumber)} />
  {:catch loadError}
    <p role="alert" class="p-3 text-xs text-red-700">Species code check could not load: {String(loadError)}</p>
  {/await}
{/if}
