<script lang="ts">
  import { formatError } from '../shared/readRequests';
  import { notifications } from '../shell/notificationService.svelte';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import {
    SpatialService,
    type AssignSpatialAOIToSURequest,
    type SpatialAOISelectionResult,
    type SpatialAttributeSuggestion,
    type SpatialBatchAuditReport,
  } from '../../bindings/github.com/boostao/vpro/app';
  import {
    computeViewportAOIRectangle,
    fetchAOIPolygonPreview,
    type SpatialAOICommitInput,
    type SpatialStampOptions,
    type WorkbenchPlotPoint,
  } from './geospatialWorkbench';
  import SpatialAOILassoTab from './SpatialAOILassoTab.svelte';
  import SpatialAuto1QATab from './SpatialAuto1QATab.svelte';
  import SpatialPlotInspectorTab from './SpatialPlotInspectorTab.svelte';

  type SpatialDiagRow = NonNullable<SpatialBatchAuditReport['rows']>[number];

  let {
    contextId,
    project,
    su,
    zoneFilter = '',
    boundingBox = null,
    plotPoints = [],
    activePanel = $bindable<'inspector' | 'aoi' | 'qa'>('inspector'),
    aoiDrawMode = $bindable(false),
    aoiTargetMode = $bindable<'update_active' | 'create_project_su' | 'create_su_file'>('create_project_su'),
    aoiSUName = $bindable(''),
    aoiSiteUnit = $bindable(''),
    aoiVertices = $bindable<Array<[number, number]>>([]),
    aoiPreview = $bindable<SpatialAOISelectionResult | null>(null),
    selectedPlot = null,
    selectedSuggestion = null,
    suggestionBusy = false,
    filteredPoints = [],
    qaReport = null,
    qaSelectedPlots = $bindable<Record<string, boolean>>({}),
    qaCoordinateDiagnosticRows = [],
    loading = false,
    mutating = false,
    onOpenPlot,
    onInspectPlot,
    getViewportBounds,
    onSyncAOIOverlay,
    onRunMutation,
    onPushError,
    onCommittedAOI,
    onLoadBatchAuditQA,
    onApplyStamp,
    aoiFilterActive = false,
    onToggleAoiFilter,
  }: {
    contextId: string;
    project: string;
    su: string;
    zoneFilter?: string;
    boundingBox?: readonly number[] | null;
    plotPoints?: WorkbenchPlotPoint[];
    activePanel?: 'inspector' | 'aoi' | 'qa';
    aoiDrawMode?: boolean;
    aoiTargetMode?: 'update_active' | 'create_project_su' | 'create_su_file';
    aoiSUName?: string;
    aoiSiteUnit?: string;
    aoiVertices?: Array<[number, number]>;
    aoiPreview?: SpatialAOISelectionResult | null;
    selectedPlot?: WorkbenchPlotPoint | null;
    selectedSuggestion?: SpatialAttributeSuggestion | null;
    suggestionBusy?: boolean;
    filteredPoints?: WorkbenchPlotPoint[];
    qaReport?: SpatialBatchAuditReport | null;
    qaSelectedPlots?: Record<string, boolean>;
    qaCoordinateDiagnosticRows?: SpatialDiagRow[];
    loading?: boolean;
    mutating?: boolean;
    onOpenPlot?: (plotNumber: string) => void;
    onInspectPlot: (pt: WorkbenchPlotPoint) => Promise<void> | void;
    getViewportBounds: () => { getWest(): number; getSouth(): number; getEast(): number; getNorth(): number } | null;
    onSyncAOIOverlay: () => void;
    onRunMutation: (action: () => Promise<void>, label: string) => Promise<void>;
    onPushError: (title: string, msg: string) => void;
    onCommittedAOI: (statusMsg: string, activated: boolean) => Promise<void>;
    onLoadBatchAuditQA: () => Promise<void> | void;
    onApplyStamp: (opts: SpatialStampOptions) => Promise<void> | void;
    aoiFilterActive?: boolean;
    onToggleAoiFilter?: (active: boolean) => void;
  } = $props();

  let aoiPreviewBusy = $state(false);
  let aoiGen = 0;
  let lastPreviewedKey = '';

  async function previewPolygon() {
    aoiPreview = null;
    if (!contextId || aoiVertices.length < 3) {
      aoiPreviewBusy = false;
      onSyncAOIOverlay();
      return;
    }
    const gen = ++aoiGen;
    aoiPreviewBusy = true;
    const out = await fetchAOIPolygonPreview(
      contextId,
      $state.snapshot(aoiVertices),
      plotPoints,
      zoneFilter,
      (cid, req) => SpatialService.SelectPlotsInPolygonAOI(cid, req)
    );
    if (gen !== aoiGen) return;
    aoiPreviewBusy = false;
    if (out.cause) {
      onPushError('AOI preview failed', `AOI polygon preview failed: ${formatError(out.cause)}`);
    } else if (out.res) {
      aoiPreview = out.res;
      if (!aoiSiteUnit && out.suggested) aoiSiteUnit = out.suggested;
      onSyncAOIOverlay();
    }
  }

  $effect(() => {
    const key = aoiVertices.length >= 3 ? JSON.stringify(aoiVertices) : '';
    if (key && key !== lastPreviewedKey) {
      lastPreviewedKey = key;
      void previewPolygon();
    } else if (!key) {
      lastPreviewedKey = '';
    }
  });

  function seedAOIFromCurrentViewport() {
    aoiVertices = computeViewportAOIRectangle(getViewportBounds(), boundingBox ?? undefined);
    onSyncAOIOverlay();
    void previewPolygon();
  }

  function clearAOIPolygon() {
    aoiGen++;
    aoiVertices = [];
    aoiPreview = null;
    lastPreviewedKey = '';
    onToggleAoiFilter?.(false);
    onSyncAOIOverlay();
  }

  async function commitAOIToSU(opts: SpatialAOICommitInput) {
    if (typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY) return;
    if (!contextId || mutating || loading || aoiPreviewBusy || !aoiPreview || aoiPreview.matchedCount === 0) return;
    if (!opts.siteUnit) {
      onPushError(
        'AOI SiteUnit required',
        'Enter a target SiteUnit code (for example SBSmk1/01) before saving the AOI selection.'
      );
      return;
    }
    const req: AssignSpatialAOIToSURequest = $state.snapshot({
      ...opts,
      plotNumbers: aoiPreview.plotNumbers ?? [],
      polygon: aoiVertices,
      rings: [],
    });
    await onRunMutation(async () => {
      const res = await SpatialService.AssignSpatialAOIToSU(contextId, req);
      if (!res) return;
      const msg = `Committed ${res.matchedPlots} AOI plots to ${res.tableName} as ${res.siteUnit} (${res.changedRows} row writes).`;
      notifications.success('AOI plots assigned to SU', msg, {
        category: 'entry',
        source: '3D Map',
        contextTag: project || undefined,
      });
      await onCommittedAOI(msg, res.activated);
    }, 'AOI SU assignment failed');
  }
</script>

<aside class="wb-drawer" aria-label="Spatial Inspector, AOI and QA Tools">
  <div class="wb-tabs" role="tablist">
    <button
      type="button"
      role="tab"
      aria-selected={activePanel === 'inspector'}
      class:active={activePanel === 'inspector'}
      onclick={() => {
        aoiDrawMode = false;
        activePanel = 'inspector';
      }}
    >
      Plot Inspector
    </button>
    <button
      type="button"
      role="tab"
      aria-selected={activePanel === 'aoi'}
      class:active={activePanel === 'aoi'}
      onclick={() => {
        activePanel = 'aoi';
      }}
    >
      {IS_WEB_READONLY ? 'Filter by Polygon' : 'Lasso / AOI -> SU'}
    </button>
    <button
      type="button"
      role="tab"
      aria-selected={activePanel === 'qa'}
      class:active={activePanel === 'qa'}
      onclick={() => {
        aoiDrawMode = false;
        activePanel = 'qa';
        if (!qaReport) void onLoadBatchAuditQA();
      }}
    >
      {IS_WEB_READONLY ? 'Geodetic QA Audit' : 'Coordinate & BGC Stamp'}
    </button>
  </div>

  {#if activePanel === 'inspector'}
    <SpatialPlotInspectorTab
      {selectedPlot}
      {selectedSuggestion}
      {suggestionBusy}
      {filteredPoints}
      {onOpenPlot}
      {onInspectPlot}
    />
  {:else if activePanel === 'aoi'}
    <SpatialAOILassoTab
      {project}
      {su}
      bind:aoiDrawMode
      bind:aoiTargetMode
      bind:aoiSUName
      bind:aoiSiteUnit
      aoiVerticesCount={aoiVertices.length}
      {aoiPreview}
      {aoiFilterActive}
      {loading}
      {mutating}
      onSeedViewport={seedAOIFromCurrentViewport}
      onClear={clearAOIPolygon}
      onCommit={commitAOIToSU}
      {onToggleAoiFilter}
      {onOpenPlot}
    />
  {:else if activePanel === 'qa'}
    <SpatialAuto1QATab
      {qaReport}
      bind:qaSelectedPlots
      {loading}
      {mutating}
      onReaudit={onLoadBatchAuditQA}
      {onApplyStamp}
      {onOpenPlot}
    />
    {#if qaCoordinateDiagnosticRows.length > 0}
      <div class="wb-panel-body wb-coord-diag-wrap" data-qa-coordinate-diagnostics>
        <div class="wb-card">
          <h3>Coordinate Diagnostics ({qaCoordinateDiagnosticRows.length})</h3>
          <ul class="wb-diag-list">
            {#each qaCoordinateDiagnosticRows.slice(0, 60) as row (row.plotNumber)}
              <li>
                <button type="button" class="wb-link-btn mono" onclick={() => onOpenPlot?.(row.plotNumber)}>
                  {row.plotNumber}
                </button>:
                {(row.diagnostics ?? []).join('; ') || 'Invalid or incomplete plot coordinates'}
              </li>
            {/each}
          </ul>
        </div>
      </div>
    {/if}
  {/if}
</aside>

<style>
  .wb-coord-diag-wrap {
    padding-top: 0;
  }
  .wb-coord-diag-wrap h3 {
    font-size: 0.875rem;
    font-weight: 700;
    color: var(--vpro-navy);
    margin: 0 0 0.4rem 0;
  }
  .wb-diag-list {
    margin: 0;
    padding-left: 1rem;
    font-size: 0.8125rem;
    color: var(--vpro-ink);
  }
  .wb-diag-list li {
    margin-bottom: 0.25rem;
  }
</style>
