<script lang="ts">
  import { formatError } from '../shared/readRequests';
  import type { SiviSessionsController } from './useSiviSessions.svelte';

  let {
    sivi,
    activeTab,
    metadataOpen,
    busy,
    dirty,
    childUnsaved,
    extendedShrubs,
    setExtendedShrubs,
    snowCoverRegimeInput,
    activeLayerDepthInput,
    arcticInputsDisabled,
    snowCoverRegimeSupported,
    activeLayerDepthSupported,
    headerValidation,
    stageSnowCoverRegime,
    stageActiveLayerDepth,
    openProjectMetadata,
    canOpenProjectMetadata,
  }: {
    sivi: SiviSessionsController;
    activeTab: string;
    metadataOpen: boolean;
    busy: boolean;
    dirty: boolean;
    childUnsaved: boolean;
    extendedShrubs: boolean;
    setExtendedShrubs: (v: boolean) => void;
    snowCoverRegimeInput: string;
    activeLayerDepthInput: string;
    arcticInputsDisabled: boolean;
    snowCoverRegimeSupported: boolean;
    activeLayerDepthSupported: boolean;
    headerValidation: Record<string, string>;
    stageSnowCoverRegime: (raw: string) => void;
    stageActiveLayerDepth: (raw: string) => void;
    openProjectMetadata: () => void;
    canOpenProjectMetadata: () => boolean;
  } = $props();
</script>

{#snippet sharedSIVIFields()}
  {#if sivi.parentSharedView}
    {#await import('./SIVIParentSharedFields.svelte')}
      <p role="status" class="p-2 text-xs">Loading shared SIVI fields...</p>
    {:then { default: SIVIParentSharedFields }}
      <SIVIParentSharedFields
        view={sivi.parentSharedView}
        disabled={sivi.parentSharedEditingDisabled}
        canSave={sivi.parentSharedClose?.canSave ?? false}
        onstage={sivi.stageParentShared}
        onoperation={(operation) => {
          void sivi.parentSharedOperation(operation);
        }}
        onreferences={() => {
          void sivi.parentSharedSession?.refreshReferences();
        }}
        oncancel={() => sivi.parentSharedSession?.cancel()}
        {extendedShrubs}
        onExtendedShrubsChange={setExtendedShrubs}
        snowCoverRegime={snowCoverRegimeInput}
        activeLayerDepth={activeLayerDepthInput}
        snowCoverRegimeDisabled={arcticInputsDisabled || !snowCoverRegimeSupported}
        activeLayerDepthDisabled={arcticInputsDisabled || !activeLayerDepthSupported}
        snowCoverRegimeError={headerValidation.snowCoverRegime ?? null}
        activeLayerDepthError={headerValidation.activeLayerDepth ?? null}
        onSnowCoverRegimeChange={stageSnowCoverRegime}
        onActiveLayerDepthChange={stageActiveLayerDepth}
      />
    {:catch loadError}
      <p role="alert" class="p-2 text-xs text-red-700">Shared SIVI fields could not load: {formatError(loadError)}</p>
    {/await}
  {/if}
{/snippet}

{#if activeTab === 'siviParent' && sivi.parentOpen && sivi.parentView && !metadataOpen}
  {#await import('./SIVIParentReadPanel.svelte')}
    <p role="status" class="p-3 text-xs">Loading SIVI parent panel...</p>
  {:then { default: SIVIParentReadPanel }}
    <SIVIParentReadPanel
      view={sivi.parentView}
      sourceView={sivi.parentSourceView}
      sharedEditor={sivi.parentSharedView
        ? {
            liveColumns: sivi.parentSharedView.original ? sivi.sharedColumns : [],
            content: sharedSIVIFields,
            busy: sivi.parentSharedView.busy,
            unsaved: sivi.parentSharedUnsaved || (sivi.parentSharedClose?.blocked ?? false),
          }
        : null}
      onMetadata={openProjectMetadata}
      metadataDisabled={!canOpenProjectMetadata()}
      writeView={sivi.parentWriteView}
      writeDisabled={sivi.parentWriteEditingDisabled}
      writeCanSave={sivi.parentWriteClose?.canSave ?? false}
      onWriteOperation={(operation) => {
        void sivi.parentWriteOperation(operation);
      }}
      onWriteStage={sivi.stageParentCell}
      onWriteCancel={() => sivi.parentWriteSession?.cancel()}
      actionView={sivi.parentActionView}
      actionDisabled={sivi.parentActionEditingDisabled}
      actionCanSave={sivi.parentActionClose?.canSave ?? false}
      onActionOperation={(operation) => {
        void sivi.parentActionOperation(operation);
      }}
      onActionStage={sivi.stageParentAction}
      onActionCancel={() => sivi.parentActionSession?.cancel()}
      assignmentView={sivi.projectAssignmentView}
      assignmentDisabled={sivi.projectAssignmentEditingDisabled}
      assignmentCanSave={sivi.projectAssignmentClose?.canSave ?? false}
      onAssignmentOperation={(operation) => {
        void sivi.projectAssignmentOperation(operation);
      }}
      onAssignmentStage={sivi.stageProjectAssignment}
      onAssignmentCancel={() => sivi.projectAssignmentSession?.cancel()}
      reloadDisabled={busy || dirty || childUnsaved || sivi.parentBusy}
      onreload={() => {
        if (sivi.parentSession) void sivi.parentSession.load();
      }}
      onSourceReload={() => {
        void sivi.reloadProjectSource();
      }}
      onSourceCancel={() => sivi.parentSourceSession?.cancel()}
      onSourceChange={(source) => {
        void sivi.changeProjectSource(source);
      }}
      oncancel={() => sivi.parentSession?.cancel()}
    />
  {:catch loadError}
    <p role="alert" class="p-3 text-xs text-red-700">SIVI parent panel could not load: {formatError(loadError)}</p>
  {/await}
{/if}
