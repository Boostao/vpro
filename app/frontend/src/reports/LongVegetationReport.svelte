<script module lang="ts">
  import { createLongVegetationGroupPreferencesRegistry } from './longVegetationGroupPreferences';
  import { createLongVegetationNamingPreferencesRegistry } from './longVegetationNamingPreferences';
  import { createLongVegetationSelectedFieldPreferencesRegistry } from './longVegetationSelectedFieldPreferences';
  import { createLongVegetationEnforcementPreferencesRegistry } from './longVegetationEnforcementPreferences';
  import { createLongVegetationUnitPreferencesRegistry } from './longVegetationUnitPreferences';
  import { createSelectedUnitSelectionRegistry } from './longVegetationSelectedUnitSelection';

  const selectedUnitSession = createSelectedUnitSelectionRegistry?.() ?? null;
  const groupingSession = createLongVegetationGroupPreferencesRegistry?.({ strata: true, lifeform: true }) ?? null;
  const namingSession = createLongVegetationNamingPreferencesRegistry?.({ code: true }) ?? null;
  const selectedFieldSession = createLongVegetationSelectedFieldPreferencesRegistry?.() ?? null;
  const enforcementSession = createLongVegetationEnforcementPreferencesRegistry?.() ?? null;
  const unitSession = createLongVegetationUnitPreferencesRegistry?.(true, true) ?? null;
</script>

<script lang="ts">
  import { onMount, onDestroy, untrack } from 'svelte';
  import {
    ImportExportService,
    VegetationReportService,
    type HTMLReportResult,
  } from '../../bindings/github.com/boostao/vpro/app';
  import type { LongVegetationSettings } from '../../bindings/github.com/boostao/vpro/app/internal/vegreport/models';
  import { projectState } from '../shared/state';
  import { ReadRequests, formatError } from '../shared/readRequests';
  import {
    createDefaultBreakpointOptions,
    type HierarchyBreakpointOptions,
    type SiteUnitExclusionRule,
    type SiteUnitExclusionSummary,
  } from '../classification/siteUnitExclusionFilter';
  import {
    requireLongVegetationGrouping,
    validateLongVegetationOptions,
    validateLongVegetationPreview,
    type ValidatedLongVegetationPreview,
  } from './longVegetationReport';
  import { vegetationWorkbookPublicationSession, type ValidatedVegetationWorkbookReview } from './vegetationWorkbook';
  import CompactReportShell from './CompactReportShell.svelte';
  import LongVegetationQuickOptions from './LongVegetationQuickOptions.svelte';
  import LongVegetationStateHost, { type LongVegHostContext } from './parts/LongVegetationStateHost.svelte';
  import LongVegetationOptionsAndControls from './parts/LongVegetationOptionsAndControls.svelte';
  import LongVegetationPreviewBody from './parts/LongVegetationPreviewBody.svelte';
  import { projectReportWorkspace } from './longVegetationProjectWorkspaces';
  import { notifications } from '../shell/notificationService.svelte';
  import { defaultWebExportFilename } from '../shell/webReadOnlyShell';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import { formatWebDownloadFeedback } from '../web/webMeta';
  import type { QuickExportSummary } from './compactReport';
  import * as quick from './compactReportRunners';

  let {
    contextId,
    project,
    projectPath,
    su,
    suPath,
    hierarchy = '',
    operationHeld = false,
    onBusyChange,
  }: {
    contextId: string;
    project: string;
    projectPath: string;
    su: string;
    suPath: string;
    hierarchy?: string;
    operationHeld?: boolean;
    onBusyChange: (busy: boolean) => void;
  } = $props();

  const effectiveHierarchy = $derived(
    (hierarchy && hierarchy !== 'None' ? hierarchy : '') ||
      ($projectState?.activeHierarchy && $projectState.activeHierarchy !== 'None'
        ? $projectState.activeHierarchy
        : '') ||
      'None'
  );
  let settings = $state.raw<LongVegetationSettings | null>(null);
  let busy = $state(false);
  let error = $state('');
  let preview = $state.raw<ValidatedLongVegetationPreview | null>(null);
  let workbookReview = $state.raw<ValidatedVegetationWorkbookReview | null>(null);
  let destination = $state('');
  let selectedWorkbookScope = $state('unlumped');
  let selectedScopeOverridden = $state(false);
  let lumpTables = $state<string[]>([]);
  let useSppCodesOnly = $state(false);
  let useSppCodesOnlyOverridden = $state(false);
  let applyExclusionsToReport = $state(false);
  let exclusionRules = $state<SiteUnitExclusionRule[]>([]);
  let useHierarchyBreakpoints = $state(false);
  let breakpointOptions = $state<HierarchyBreakpointOptions>(createDefaultBreakpointOptions());
  let exclusionSummary = $state.raw<SiteUnitExclusionSummary | null>(null);
  let quickDraft = $state<quick.LongVegQuickDraft>(quick.loadInitialQuickDraft('long_veg', quick.DEFAULT_LONG_VEG_QUICK));
  let quickExporting = $state(false);
  let quickRendering = $state(false);
  let quickError = $state('');
  let quickExportResult = $state.raw<QuickExportSummary | null>(null);
  let quickHtmlReport = $state.raw<HTMLReportResult | null>(null);
  const reads = new ReadRequests();
  let generation = 0;
  let disposed = false;

  const workbookOwner = untrack(() => ({ contextId, project, projectPath, su, suPath }));
  const projectWorkspace = untrack(() => projectReportWorkspace?.(workbookOwner) ?? null);
  let projectView = $state.raw(untrack(() => projectWorkspace?.view() ?? null));
  const workbookSession = vegetationWorkbookPublicationSession(workbookOwner, true);
  let publication = $state(workbookSession.view());
  let bridge = $state<LongVegHostContext>({
    projectActive: !!untrack(() => projectView?.projectActive),
    workbookBarrier: false,
    preferenceBarrier: false,
    sharedPreferenceBarrier: false,
    cancelLoads: () => {},
    syncWorkbook: () => {},
    syncProject: () => {},
  });

  function resolveContextTag() {
    return (
      (typeof project === 'string' && project) ||
      (typeof effectiveHierarchy === 'string' && effectiveHierarchy !== 'None' ? effectiveHierarchy : undefined) ||
      (typeof hierarchy === 'string' && hierarchy && hierarchy !== 'None' ? hierarchy : undefined)
    );
  }
  function toastErr(title: string, msg: string) {
    return notifications.error(title, msg, {
      category: 'reports',
      source: 'Long Vegetation',
      contextTag: resolveContextTag(),
    });
  }
  function filterLumpNames(discovered: unknown) {
    return !Array.isArray(discovered)
      ? []
      : discovered
          .map((item) => (typeof item === 'string' ? item : String((item as { tableName?: string })?.tableName ?? '')))
          .filter((name) => !!name && !/^none(?:_lump)?$/i.test(name) && !/^combinedspp_lump$/i.test(name));
  }

  function invalidateReports() {
    preview = null;
    workbookReview = null;
    projectWorkspace?.invalidate();
  }
  const unsubscribeWorkbook = workbookSession.subscribe(() => {
    publication = workbookSession.view();
    if (publication.blocked) workbookReview = null;
    bridge.syncWorkbook();
  });
  let wasProjectActive = untrack(() => !!projectView?.projectActive);
  function projectChanged() {
    const nextView = projectWorkspace?.view() ?? null;
    const nextActive = !!nextView?.projectActive;
    if (wasProjectActive || nextActive) {
      generation++;
      reads.cancelAll();
      busy = false;
      workbookReview = null;
      settings = nextActive ? (nextView?.settings ?? null) : null;
      preview = nextActive ? (nextView?.preview ?? null) : null;
    }
    wasProjectActive = nextActive;
    projectView = nextView;
    bridge.syncProject();
  }
  const unsubscribeProject = projectWorkspace?.subscribe(projectChanged);

  function cancel() {
    generation++;
    reads.cancelAll();
    projectWorkspace?.cancelReportRead();
    bridge.cancelLoads();
    busy = false;
  }
  async function readProject(operation: () => Promise<void>) {
    if (busy || operationHeld || bridge.workbookBarrier || bridge.sharedPreferenceBarrier || !projectView?.outputReady)
      return;
    error = '';
    try {
      await operation();
      const pv = projectWorkspace?.view?.();
      if (pv?.error) toastErr('Long Vegetation project report failed', pv.error);
    } catch (cause) {
      error = `Original project report unavailable: ${formatError(cause)}`;
      toastErr('Long Vegetation project report failed', error);
    }
  }
  async function runGuardedRead(
    toastTitle: string,
    errPrefix: string,
    clearSettings: boolean,
    fn: (req: number) => Promise<void>
  ) {
    cancel();
    const req = generation;
    if (clearSettings) settings = null;
    error = '';
    preview = null;
    workbookReview = null;
    busy = true;
    try {
      await fn(req);
    } catch (c) {
      if (req === generation) {
        error = `${errPrefix}: ${formatError(c)}`;
        toastErr(toastTitle, error);
      }
    } finally {
      if (req === generation) busy = false;
    }
  }
  async function loadLumpTables() {
    if (typeof ImportExportService?.DiscoverLumpTables !== 'function') return;
    try {
      const discovered = await reads.track(ImportExportService.DiscoverLumpTables(contextId, []));
      if (!disposed) lumpTables = filterLumpNames(discovered);
    } catch {
      /* Optional lump discovery leaves 'unlumped' default intact. */
    }
  }
  function acceptValidatedPreview(raw: unknown) {
    const candidate = validateLongVegetationPreview(raw as never, contextId, project, projectPath, su, suPath, true);
    requireLongVegetationGrouping(candidate.settings, true, true, true, true, true, true);
    preview = candidate;
    settings = candidate.settings;
  }
  async function options() {
    if (bridge.projectActive && projectWorkspace) return readProject(() => projectWorkspace.loadOptions());
    if (busy || operationHeld || bridge.workbookBarrier || bridge.preferenceBarrier || !su || su === 'None') return;
    await runGuardedRead('Long Vegetation options failed', 'Report options unavailable', true, async (req) => {
      const val = await reads.track(VegetationReportService.GetLongVegetationOptions(contextId));
      if (req !== generation) return;
      const cand = validateLongVegetationOptions(val, contextId, project, projectPath, su, suPath, true).settings;
      requireLongVegetationGrouping(cand, true, true, true, true, true, true);
      settings = cand;
      if (!useSppCodesOnlyOverridden) useSppCodesOnly = !!cand.combineVariants;
      if (!selectedScopeOverridden && cand.lumpTable && filterLumpNames([cand.lumpTable]).length)
        selectedWorkbookScope = `lump:${cand.lumpTable}`;
    });
  }
  async function show() {
    if (bridge.projectActive && projectWorkspace) return readProject(() => projectWorkspace.showPreview());
    if (busy || operationHeld || bridge.workbookBarrier || bridge.preferenceBarrier || !settings || su === 'None')
      return;
    await runGuardedRead(
      'Long Vegetation report failed',
      'Report unavailable; no data or configuration written',
      false,
      async (req) => {
        const scope = selectedWorkbookScope.trim() || 'unlumped';
        const useExcl = (applyExclusionsToReport || useHierarchyBreakpoints) && exclusionRules.some((r) => r.enabled);
        if (useExcl && typeof VegetationReportService?.PreviewLongVegetationWithExclusions === 'function') {
          const res = await reads.track(
            VegetationReportService.PreviewLongVegetationWithExclusions(contextId, {
              rules: exclusionRules.map((r) => ({ ...r })),
              useDefaultPresets: false,
              useHierarchyBreakpoints,
              breakpointOptions: breakpointOptions ? { ...breakpointOptions } : createDefaultBreakpointOptions(),
            })
          );
          if (req !== generation) return;
          acceptValidatedPreview(res?.preview);
          exclusionSummary = (res?.exclusions as SiteUnitExclusionSummary | undefined) ?? null;
        } else if (scope !== 'unlumped' && su !== 'USysSuTableDynamic') {
          const rev = await reads.track(
            VegetationReportService.GetVegetationWorkbookReview(contextId, JSON.stringify({ scope }))
          );
          if (req !== generation) return;
          if (!rev?.preview) throw new Error('No lumped report preview returned.');
          acceptValidatedPreview(rev.preview);
        } else {
          const val = await reads.track(VegetationReportService.PreviewLongVegetation(contextId));
          if (req === generation) acceptValidatedPreview(val);
        }
      }
    );
  }
  async function reviewWorkbook() {
    if (bridge.projectActive && projectWorkspace) return readProject(() => projectWorkspace.reviewWorkbook());
    if (
      busy ||
      operationHeld ||
      bridge.workbookBarrier ||
      bridge.preferenceBarrier ||
      !settings ||
      su === 'None' ||
      su === 'USysSuTableDynamic'
    )
      return;
    await runGuardedRead(
      'Long Vegetation workbook review failed',
      'Workbook review unavailable; no file published',
      false,
      async (req) => {
        const scope = selectedWorkbookScope.trim() || 'unlumped';
        const val = await reads.track(
          VegetationReportService.GetVegetationWorkbookReview(contextId, JSON.stringify({ scope }))
        );
        if (req !== generation) return;
        if (!val) throw new Error('No owned workbook review returned.');
        const reviewed = workbookSession.prepare(val);
        requireLongVegetationGrouping(reviewed.preview.settings, true, true, true, true, true, true);
        workbookReview = reviewed;
        preview = reviewed.preview;
        settings = reviewed.preview.settings;
      }
    );
  }
  async function publishWorkbook() {
    const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
    const targetDestination =
      webReadOnly && !destination.trim()
        ? typeof defaultWebExportFilename === 'function'
          ? defaultWebExportFilename(`${project || 'vpro'}_long_vegetation`, '.xlsx')
          : `${project || 'vpro'}_long_vegetation.xlsx`
        : destination;
    if (bridge.projectActive && projectWorkspace) {
      if (
        busy ||
        operationHeld ||
        bridge.workbookBarrier ||
        bridge.sharedPreferenceBarrier ||
        !projectView?.workbookReview
      )
        return;
      error = '';
      try {
        await projectWorkspace.publishWorkbook(targetDestination);
        bridge.syncProject();
      } catch (c) {
        error =
          webReadOnly && typeof formatWebDownloadFeedback === 'function'
            ? formatWebDownloadFeedback(c, 'Long Vegetation workbook download')
            : formatError(c);
        toastErr('Long Vegetation workbook export failed', error);
      }
      return;
    }
    if (busy || operationHeld || bridge.workbookBarrier || bridge.preferenceBarrier || !workbookReview) return;
    const reviewed = workbookReview;
    cancel();
    error = '';
    try {
      await workbookSession.publish(reviewed, targetDestination, (r) =>
        VegetationReportService.ExportReviewedVegetationWorkbook(contextId, JSON.stringify(r))
      );
      bridge.syncWorkbook();
    } catch (c) {
      error =
        webReadOnly && typeof formatWebDownloadFeedback === 'function'
          ? formatWebDownloadFeedback(c, 'Long Vegetation workbook download')
          : formatError(c);
      toastErr('Long Vegetation workbook export failed', error);
    }
  }
  function acknowledgeWorkbook() {
    workbookSession.acknowledge();
    workbookReview = null;
  }

  const groupLabel = $derived(
    settings?.grouping === 'lifeform' ? 'Lifeform' : settings?.grouping === 'strata' ? 'Strata' : 'Layer'
  );
  const registries = {
    groupingSession, namingSession, selectedFieldSession, enforcementSession, unitSession, selectedUnitSession,
  };
  const headerActions = {
    onShow: show, onOptions: options, onReviewWorkbook: reviewWorkbook,
    onCancel: cancel, onAcknowledgeWorkbook: acknowledgeWorkbook, onProjectChanged: projectChanged,
  };
  const controlsOwner = $derived({ contextId, project, projectPath, su, suPath, effectiveHierarchy });
  const controlsActions = {
    onSelectWorkbookScope: (s: string) => {
      [selectedScopeOverridden, selectedWorkbookScope] = [true, s];
      invalidateReports();
    },
    onRefreshLumpTables: loadLumpTables,
    onToggleUseSppCodesOnly: (c: boolean) => ([useSppCodesOnlyOverridden, useSppCodesOnly] = [true, c]),
    onToggleApplyExclusions: (c: boolean) => {
      applyExclusionsToReport = c;
      invalidateReports();
    },
    onRulesChange: (r: SiteUnitExclusionRule[], bp: boolean, o: HierarchyBreakpointOptions) => {
      [exclusionRules, useHierarchyBreakpoints, breakpointOptions] = [r.map((x) => ({ ...x })), bp, { ...o }];
      if (bp || applyExclusionsToReport) invalidateReports();
    },
    onLongPreview: (res: { preview?: unknown; exclusions?: SiteUnitExclusionSummary } | null | undefined) => {
      if (!res?.preview) return;
      try {
        acceptValidatedPreview(res.preview);
        [exclusionSummary, error] = [res.exclusions ?? null, ''];
      } catch (c) {
        error = `Exclusion preview unavailable: ${formatError(c)}`;
        toastErr('Long Vegetation exclusion preview failed', error);
      }
    },
    onPublishWorkbook: publishWorkbook,
  };

  async function quickExportSpreadsheet() {
    if (!contextId || quickExporting || quickRendering) return;
    [quickExporting, quickError] = [true, ''];
    const snap = $state.snapshot(quickDraft);
    quick.persistQuickDraft('long_veg', snap);
    const out = await quick.exportLongVegSpreadsheet(contextId, snap, project, su);
    [quickExportResult, quickError, quickExporting] = [out.summary, out.error, false];
  }
  async function quickDisplayReport() {
    if (!contextId || quickExporting || quickRendering) return;
    [quickRendering, quickError] = [true, ''];
    const snap = $state.snapshot(quickDraft);
    quick.persistQuickDraft('long_veg', snap);
    const req = quick.buildLongVegQuickRequest(snap, project, false);
    const out = await quick.runQuickHTMLDisplay({
      source: 'Long Vegetation', project,
      invoke: () => VegetationReportService.RenderLongVegetationHTMLReport(contextId, req),
    });
    [quickHtmlReport, quickError, quickRendering] = [out.report, out.error, false];
  }

  onMount(() => {
    void loadLumpTables();
    if (projectWorkspace) {
      void projectWorkspace.selection
        .load()
        .then(() => {
          if (disposed) return;
          if (projectWorkspace.view().scope.scope?.sourceKind === 'selected-list' && su && su !== 'None')
            void options();
        })
        .catch((c) => {
          if (disposed) return;
          error = `Owned report scope unavailable: ${formatError(c)}`;
          toastErr('Long Vegetation scope load failed', error);
        });
    } else if (su && su !== 'None') void options();
  });
  onDestroy(() => {
    disposed = true;
    unsubscribeWorkbook();
    unsubscribeProject?.();
    projectWorkspace?.cancelScopeReads();
    projectWorkspace?.selection.cancel();
    projectWorkspace?.cancelUnitReads();
    projectWorkspace?.units.cancelRead();
    cancel();
  });
</script>

<section class="report" data-long-vegetation-report aria-label="Long Vegetation report">
  <CompactReportShell
    title="Long Vegetation"
    subtitle="Plot-by-species vegetation table grouped by layer, strata, or lifeform."
    {contextId}
    {project}
    {su}
    hierarchy={effectiveHierarchy}
    busy={busy || operationHeld}
    exporting={quickExporting}
    rendering={quickRendering}
    exportResult={quickExportResult}
    htmlReport={quickHtmlReport}
    errorMessage={quickError || error}
    onExportSpreadsheet={quickExportSpreadsheet}
    onDisplayReport={quickDisplayReport}
    onCloseHtmlReport={() => (quickHtmlReport = null)}
  >
    {#snippet headerExtra()}
      <button
        type="button"
        class="btn-secondary"
        data-source-control="btnViewReport"
        disabled={busy ||
          operationHeld ||
          bridge.workbookBarrier ||
          bridge.preferenceBarrier ||
          (bridge.projectActive ? !projectView?.outputReady : !settings || su === 'None')}
        onclick={show}
      >View Report</button>
    {/snippet}
    {#snippet quickOptions()}
      <LongVegetationQuickOptions
        draft={quickDraft}
        {lumpTables}
        disabled={quickExporting || quickRendering}
        onChange={(next) => (quickDraft = next)}
      />
    {/snippet}
    {#snippet advanced()}
      <LongVegetationStateHost
        {workbookOwner}
        {registries}
        {projectWorkspace}
        {projectView}
        {publication}
        {settings}
        {busy}
        {operationHeld}
        {selectedWorkbookScope}
        {destination}
        {reads}
        {resolveContextTag}
        {headerActions}
        {onBusyChange}
        onInvalidate={(inv) => {
          invalidateReports();
          if (settings && inv?.(settings)) settings = null;
        }}
        onSelectedUnitReset={() => {
          generation++;
          reads.cancelAll();
          busy = false;
          preview = null;
          workbookReview = null;
          settings = null;
        }}
        onBridgeReady={(ctx) => (bridge = ctx)}
        onBeginTitleStatsRead={() => {
          cancel();
          error = '';
          busy = true;
          return generation;
        }}
        onEndTitleStatsRead={(req) => {
          if (req === generation) busy = false;
        }}
        onCancelTitleStatsParent={() => {
          cancel();
          error = '';
          return generation;
        }}
        onTitleStatsError={(t, msg) => {
          error = msg;
          toastErr(t, msg);
        }}
      >
        {#snippet children(ctx)}
          <LongVegetationOptionsAndControls
            owner={controlsOwner}
            state={{
              projectActive: ctx.projectActive, settings, groupLabel, busy, operationHeld,
              workbookBarrier: ctx.workbookBarrier, preferenceBarrier: ctx.preferenceBarrier,
              selectedWorkbookScope, lumpTables, useSppCodesOnly, applyExclusionsToReport, exclusionSummary,
              activeWorkbookReview: ctx.projectActive ? (projectView?.workbookReview ?? null) : workbookReview,
            }}
            bind:destination
            actions={controlsActions}
          />
        {/snippet}
      </LongVegetationStateHost>
    {/snippet}
    {#snippet results()}
      <LongVegetationPreviewBody {settings} {preview} {groupLabel} {useSppCodesOnly} />
    {/snippet}
  </CompactReportShell>
  <p class="guidance">Report options load from saved configuration; NULL, empty text, zero, and absent statistics remain distinct.</p>
</section>

<style>
  .report {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 0.75rem;
    min-width: 0;
    overflow-wrap: anywhere;
    color: var(--vpro-ink);
  }
  .btn-secondary {
    min-height: 2.35rem;
    padding: 0.42rem 0.75rem;
    border: 1px solid var(--vpro-navy);
    border-radius: 0.25rem;
    background: var(--vpro-surface);
    color: var(--vpro-navy);
    font-weight: 600;
    font-size: 0.82rem;
    cursor: pointer;
  }
  .btn-secondary:disabled {
    opacity: 0.55;
    cursor: not-allowed;
  }
  .report :global(.table-scroll) {
    max-width: 100%;
  }
  .report :global(.scope) {
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 19rem), 1fr));
  }
</style>
