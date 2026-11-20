<script lang="ts">
  import type { FS882Header, ListItem } from '../../bindings/github.com/boostao/vpro/app';
  import HeaderEditor from './HeaderEditor.svelte';
  import OrdinaryFields from './OrdinaryFields.svelte';
  import ParentCodeFields from './ParentCodeFields.svelte';
  import PicturePanel from '../pictures/PicturePanel.svelte';
  import type { PictureMetadataSession } from '../pictures/pictureMetadataSession';
  import type { WorkingUnitSession } from './workingUnitEditor';

  let {
    draft = $bindable(),
    original,
    capabilities,
    headerInputsDisabled,
    parentCodeBusy = $bindable(),
    coordinateBusy = $bindable(),
    workingUnitBusy = $bindable(),
    qualityBusy = $bindable(),
    siteCodeBusy = $bindable(),
    regionCodeBusy = $bindable(),
    pictureBusy = $bindable(),
    openProjectMetadata,
    canOpenProjectMetadata,
    onOpenPictureManager,
    projectIds,
    masterAllowed,
    extendedShrubs,
    snowCoverRegime,
    activeLayerDepth,
    snowCoverRegimeDisabled,
    activeLayerDepthDisabled,
    snowCoverRegimeError,
    activeLayerDepthError,
    onSnowCoverRegimeChange,
    onActiveLayerDepthChange,
    lists,
    workingUnitSession,
    markDirty,
    validateHeader,
    onError,
    twoPageOpen,
    contextId,
    headerRevision = 0,
    activeProject,
    pictureDisabled,
    pictureMetadataDisabled,
    pictureMetadataSession,
  }: {
    draft: FS882Header;
    original: FS882Header | null;
    capabilities: Record<string, boolean | undefined>;
    headerInputsDisabled: boolean;
    parentCodeBusy: boolean;
    coordinateBusy: boolean;
    workingUnitBusy: boolean;
    qualityBusy: boolean;
    siteCodeBusy: boolean;
    regionCodeBusy: boolean;
    pictureBusy: boolean;
    openProjectMetadata: () => void;
    canOpenProjectMetadata: () => boolean;
    onOpenPictureManager?: (plotNumber: string) => void;
    projectIds: string[];
    masterAllowed: boolean;
    extendedShrubs: boolean;
    snowCoverRegime: string;
    activeLayerDepth: string;
    snowCoverRegimeDisabled: boolean;
    activeLayerDepthDisabled: boolean;
    snowCoverRegimeError: string | null;
    activeLayerDepthError: string | null;
    onSnowCoverRegimeChange: (raw: string) => void;
    onActiveLayerDepthChange: (raw: string) => void;
    lists: {
      moistureRegime: ListItem[];
      nutrientRegime: ListItem[];
      mesoSlopePos: ListItem[];
      surfaceShape: ListItem[];
    };
    workingUnitSession: WorkingUnitSession & { plot: string };
    markDirty: () => void;
    validateHeader: (key: string, message: string | null) => void;
    onError: (message: string) => void;
    twoPageOpen: boolean;
    contextId: string;
    headerRevision?: number;
    activeProject: string | null;
    pictureDisabled: boolean;
    pictureMetadataDisabled: boolean;
    pictureMetadataSession: PictureMetadataSession | undefined;
  } = $props();
</script>

<ParentCodeFields
  bind:draft
  {original}
  {capabilities}
  scope="site"
  disabled={headerInputsDisabled}
  onchange={markDirty}
  onvalidation={validateHeader}
  onbusy={(pending) => {
    parentCodeBusy = pending;
  }}
>
  {#snippet children(editor)}
    <OrdinaryFields
      bind:draft
      {original}
      {capabilities}
      scope="site"
      disabled={headerInputsDisabled}
      onchange={markDirty}
      onvalidation={validateHeader}
    >
      {#snippet children(ordinaryEditor)}
        <HeaderEditor
          bind:draft
          {original}
          {capabilities}
          disabled={headerInputsDisabled}
          onMetadata={openProjectMetadata}
          metadataDisabled={!canOpenProjectMetadata()}
          {onOpenPictureManager}
          {projectIds}
          {editor}
          additionalEditor={ordinaryEditor}
          {masterAllowed}
          {extendedShrubs}
          {snowCoverRegime}
          {activeLayerDepth}
          {snowCoverRegimeDisabled}
          {activeLayerDepthDisabled}
          {snowCoverRegimeError}
          {activeLayerDepthError}
          {onSnowCoverRegimeChange}
          {onActiveLayerDepthChange}
          existing={original !== null}
          {lists}
          onchange={markDirty}
          onerror={onError}
          onvalidation={validateHeader}
          onCoordinateBusyChange={(pending) => {
            coordinateBusy = pending;
          }}
          onWorkingUnitBusyChange={(pending) => {
            workingUnitBusy = pending;
          }}
          onQualityBusyChange={(pending) => {
            qualityBusy = pending;
          }}
          onSiteCodeBusyChange={(pending) => {
            siteCodeBusy = pending;
          }}
          onRegionCodeBusyChange={(pending) => {
            regionCodeBusy = pending;
          }}
          {workingUnitSession}
          {contextId}
          {headerRevision}
          pictureEditor={!twoPageOpen ? linkedPictures : undefined}
        />
      {/snippet}
    </OrdinaryFields>
    {#snippet linkedPictures()}
      {#if activeProject && original}
        <PicturePanel
          {contextId}
          project={activeProject}
          plotNumber={original.plotNumber}
          disabled={pictureDisabled}
          metadataDisabled={pictureMetadataDisabled}
          onBusyChange={(pending) => {
            pictureBusy = pending;
          }}
          metadataSession={pictureMetadataSession}
        />
      {:else}
        <p role="status">Save and reload an owned plot before reading linked pictures.</p>
      {/if}
    {/snippet}
  {/snippet}
</ParentCodeFields>
