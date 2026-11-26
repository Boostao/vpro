<script lang="ts">
  import { onMount, onDestroy, untrack } from 'svelte';
  import { ImportExportService, VegetationReportService, type HTMLReportResult } from '../../bindings/github.com/boostao/vpro/app';
  import { ReadRequests, formatError } from '../shared/readRequests';
  import { projectState } from '../shared/state';
  import { notifications } from '../shell/notificationService.svelte';
  import SiteUnitExclusionFilter from '../classification/SiteUnitExclusionFilter.svelte';
  import { summaryVegetationSession, type SummaryVegetationPort } from './summaryVegetation';
  import { summaryVegetationPreferenceSession } from './summaryVegetationPreferences';
  import { summaryVegetationQualityPreferenceSession } from './summaryVegetationQualityPreferences';
  import { summaryVegetationPresentationPreferenceSession } from './summaryVegetationPresentationPreferences';
  import CompactReportShell from './CompactReportShell.svelte';
  import SummaryVegetationQuickOptions from './SummaryVegetationQuickOptions.svelte';
  import SummaryVegetationOptionsBar from './SummaryVegetationOptionsBar.svelte';
  import SummaryVegetationPeerPanels from './SummaryVegetationPeerPanels.svelte';
  import SummaryVegetationResultPanel from './SummaryVegetationResultPanel.svelte';
  import { summaryVegetationFieldListDesktop } from './summaryVegetationFieldListDesktop';
  import * as envDesk from './summaryVegetationEnvironmentalDesktop';
  import * as ops from './summaryVegetationReportOps';
  import type { QuickExportSummary } from './compactReport';
  import * as quick from './compactReportRunners';

  interface Props {
    contextId: string;
    project: string;
    projectPath: string;
    su: string;
    suPath: string;
    hierarchy?: string;
    operationHeld?: boolean;
    onBusyChange: (busy: boolean) => void;
    onExclusionBusyChange?: (value: boolean) => void;
  }
  let {
    contextId,
    project,
    projectPath,
    su,
    suPath,
    hierarchy = '',
    operationHeld: operationHeldProp = false,
    onBusyChange,
    onExclusionBusyChange,
  }: Props = $props();

  const effectiveHierarchy = $derived(ops.resolveEffectiveHierarchy(hierarchy, $projectState?.activeHierarchy));
  const reads = new ReadRequests();
  const ownedContext = () => ({ contextId, project, projectPath, su, suPath });
  const session = summaryVegetationSession(ownedContext());
  let environmentalHeld = $state(false);
  let workbookHeld = $state(false);
  const operationHeld = $derived(operationHeldProp || environmentalHeld || workbookHeld);
  const envInit = untrack(() =>
    ops.initSummaryVegEnvironmentalSession(ownedContext(), () => effectiveHierarchy, envDesk, notifications)
  );
  const canInspectEnvironmental = envInit.canInspect;
  let environmentalSession = $state.raw(envInit.session);

  const preferences = summaryVegetationPreferenceSession?.(ownedContext()) ?? null;
  const quality = summaryVegetationQualityPreferenceSession?.(ownedContext()) ?? null;
  const presentation = summaryVegetationPresentationPreferenceSession?.(ownedContext()) ?? null;
  const fieldList = summaryVegetationFieldListDesktop;
  const fieldListScopeAvailable = Boolean(
    fieldList?.enabled && typeof fieldList.contextAvailable === 'function' && fieldList.contextAvailable(ownedContext())
  );
  let fieldListState = $state.raw(fieldListScopeAvailable ? fieldList.state(ownedContext()) : null);
  let fieldListHeld = $state(false);
  let fieldListBusy = $state(false);
  let fieldListError = $state('');
  let presentationView = $state.raw(presentation?.view() ?? null);
  let presentationReadBusy = $state(false);
  let qualityView = $state.raw(quality?.view() ?? null);
  let qualityReadBusy = $state(false);
  let preferenceView = $state.raw(preferences?.view() ?? null);
  let preferenceReadBusy = $state(false);
  let preferenceReadError = $state('');
  let preferenceGeneration = 0;
  const preferenceReads = new ReadRequests();
  const port: SummaryVegetationPort = ops.createSummaryVegServicePort(() => contextId, reads, VegetationReportService);

  let unitScope = $state<'su' | 'hierarchy' | 'none' | 'field'>('su');
  let unitField = $state('');
  let breakpointPolicy = $state<'lowest' | 'highest'>('lowest');
  let combineVariants = $state(false);
  let lumpTable = $state('');
  let lumpTables = $state<string[]>([]);
  let lumpDiscoveryError = $state('');
  let includeGoldstreamMetadata = $state(false);
  let exclusionSummaryText = $state('');
  let viewState = $state.raw(session.view());
  let quickDraft = $state<quick.SummaryVegQuickDraft>(quick.loadInitialQuickDraft('summary_veg', quick.DEFAULT_SUMMARY_VEG_QUICK));
  let quickExporting = $state(false);
  let quickRendering = $state(false);
  let quickError = $state('');
  let quickExportResult = $state.raw<QuickExportSummary | null>(null);
  let quickHtmlReport = $state.raw<HTMLReportResult | null>(null);
  const toastTracker = ops.createSummaryVegNotificationTracker();

  const reportContextTag = () => ops.resolveSummaryVegContextTag(project, () => effectiveHierarchy);
  const reportToastOpts = () => ({
    category: 'reports' as const,
    source: 'Summary Vegetation',
    contextTag: reportContextTag(),
  });
  const syncReportNotifications = () =>
    ops.syncSummaryVegToastState(notifications, toastTracker, {
      viewError: viewState?.error ?? '',
      prefView: preferences?.view(),
      fieldListReadError: fieldListState?.readError ?? '',
      contextTag: reportContextTag(),
    });
  function reportBusy() {
    const peerBusy = ops.anySummaryVegPeerBusy(
      preferenceView,
      qualityReadBusy,
      qualityView,
      presentationReadBusy,
      presentationView,
      fieldListHeld,
      environmentalHeld,
      workbookHeld
    );
    onBusyChange(viewState.busy || (!preferences && !!viewState.draftError) || preferenceReadBusy || peerBusy);
  }

  const unsubscribe = session.subscribe(
    () => (([viewState] = [session.view()]), syncReportNotifications(), reportBusy())
  );
  const unsubscribeEnvironment = canInspectEnvironmental
    ? envDesk.summaryEnvironmentalDesktop.subscribe(
        () => (([environmentalHeld] = [envDesk.summaryEnvironmentalDesktop.activity().busy]), reportBusy())
      )
    : undefined;
  const unsubscribePreferences = preferences?.subscribe(() => {
    preferenceView = preferences.view();
    ops.syncSummaryVegPrefDraft(preferenceView, viewState, session);
    syncReportNotifications();
    reportBusy();
  });
  const unsubscribeQuality = quality?.subscribe(() => (([qualityView] = [quality.view()]), reportBusy()));
  const unsubscribePresentation = presentation?.subscribe(
    () => (([presentationView] = [presentation.view()]), reportBusy())
  );
  const unsubscribeFieldList = fieldListScopeAvailable
    ? fieldList.subscribe(() => {
        fieldListState = fieldList.state(ownedContext());
        const activity = fieldList.activity();
        [fieldListBusy, fieldListHeld] = [activity.busy, activity.busy || activity.blocked];
        syncReportNotifications();
        reportBusy();
      })
    : undefined;
  syncReportNotifications();

  async function loadFieldList() {
    if (!fieldListScopeAvailable || fieldListPeerDisabled || fieldListPeerValidation || fieldListState?.readBusy)
      return;
    fieldListError = '';
    try {
      await fieldList.load(ownedContext());
    } catch (cause) {
      fieldListError = formatError(cause);
      notifications.error('Summary Vegetation field list failed', fieldListError, reportToastOpts());
    }
  }
  function dismissInitialFieldListReadError() {
    if (!fieldListScopeAvailable || !fieldListState?.canDismissInitialReadError) return;
    fieldListError = '';
    try {
      fieldList.dismissInitialReadError(ownedContext());
    } catch (cause) {
      fieldListError = formatError(cause);
      notifications.error('Summary Vegetation field list acknowledgement failed', fieldListError, reportToastOpts());
    }
  }

  const presentationMutationHeld = $derived(ops.isPeerMutationHeld(presentationReadBusy, presentationView));
  const presentationInvalid = $derived(ops.isPeerInvalid(presentationView));
  const qualityMutationHeld = $derived(ops.isPeerMutationHeld(qualityReadBusy, qualityView));
  const qualityInvalid = $derived(ops.isPeerInvalid(qualityView));
  const preferenceHeld = $derived(ops.isPeerMutationHeld(preferenceReadBusy, preferenceView));
  const preferenceInvalid = $derived(ops.isPeerInvalid(preferenceView));
  const fieldListPeerDisabled = $derived(
    operationHeld || viewState.busy || preferenceHeld || qualityMutationHeld || presentationMutationHeld
  );
  const fieldListPeerValidation = $derived(
    ops.computeFieldListPeerValidation(preferenceInvalid, qualityInvalid, presentationInvalid)
  );
  const fieldListEnabledFromPresentation = $derived(
    !!presentationView?.saved && !presentationInvalid && presentationView.draft?.includeEnv === true
  );
  const editHeld = $derived(
    viewState.busy ||
      operationHeld ||
      fieldListBusy ||
      preferenceHeld ||
      qualityMutationHeld ||
      presentationMutationHeld ||
      (!!preferences && !preferenceView?.saved)
  );
  const vm = $derived(
    ops.deriveSummaryVegVm({
      owner: ownedContext(), editHeld, unitScope, unitField, breakpointPolicy, combineVariants, lumpTable, lumpTables,
      includeGoldstreamMetadata, viewState, operationHeldProp, operationHeld, workbookHeld, environmentalHeld,
      fieldListHeld, fieldListBusy, preferences, preferenceView, preferenceReadBusy, preferenceHeld, preferenceInvalid,
      quality, qualityView, qualityMutationHeld, qualityInvalid, presentation, presentationView,
      presentationMutationHeld, presentationInvalid, fieldListEnabled: Boolean(fieldList?.enabled),
      fieldListScopeAvailable, fieldListState, fieldListPeerDisabled, fieldListPeerValidation,
      fieldListEnabledFromPresentation, environmentalSession, envDesk,
    })
  );
  function cancelPreferenceRead() {
    preferenceGeneration++;
    preferenceReads.cancelAll();
    preferences?.cancelLoad();
    preferenceReadBusy = false;
    reportBusy();
  }
  async function loadPreferences() {
    if (
      ops.isSummaryVegPrefBlocked(
        preferences,
        viewState.busy,
        operationHeld,
        fieldListHeld,
        preferenceHeld,
        qualityMutationHeld,
        qualityInvalid,
        presentationMutationHeld,
        presentationInvalid
      )
    )
      return;
    cancelPreferenceRead();
    const [request, token] = [preferenceGeneration, preferences!.beginLoad()];
    [preferenceReadError, preferenceReadBusy] = ['', true];
    reportBusy();
    await ops.runSummaryVegPrefLoad({
      reads: preferenceReads,
      fetchPrefs: () => VegetationReportService.GetSummaryVegetationPreferences(contextId),
      isCurrent: () => request === preferenceGeneration,
      applyLoaded: (val) => preferences!.applyLoaded(val, token),
      rejectRead: (cause) => preferences!.rejectRead(cause),
      onSyncNotifications: () => typeof syncReportNotifications === 'function' && syncReportNotifications(),
      onDone: () => {
        preferenceReadBusy = false;
        reportBusy();
      },
    });
  }
  async function savePreferences() {
    if (
      preferenceInvalid ||
      ops.isSummaryVegPrefBlocked(
        preferences,
        viewState.busy,
        operationHeld,
        fieldListHeld,
        preferenceHeld,
        qualityMutationHeld,
        qualityInvalid,
        presentationMutationHeld,
        presentationInvalid
      )
    )
      return;
    cancelPreferenceRead();
    preferenceReadError = '';
    try {
      await preferences!.save((value) =>
        VegetationReportService.SaveSummaryVegetationPreferences(contextId, JSON.stringify(value))
      );
      if (typeof syncReportNotifications === 'function') syncReportNotifications();
    } catch (cause) {
      preferenceReadError = formatError(cause);
      notifications.error('Summary Vegetation preferences save failed', preferenceReadError, reportToastOpts());
    }
  }
  function editPreference(field: 'groupBy' | 'average' | 'display' | 'showClass', raw: string) {
    if (!preferences || editHeld) return;
    cancelPreferenceRead();
    preferenceReadError = '';
    preferences.editOption(field, raw);
  }
  function changeAverage(event: Event) {
    const raw = (event.currentTarget as HTMLSelectElement).value;
    if (preferences) return editPreference('average', raw);
    const current = Number(raw);
    session.edit(current, viewState.display, viewState.showClass || 1, viewState.groupAndOrder);
  }
  function changeDisplay(event: Event) {
    const raw = (event.currentTarget as HTMLSelectElement).value;
    if (preferences) return editPreference('display', raw);
    const current = Number(raw);
    session.edit(viewState.average, current, viewState.showClass || 1, viewState.groupAndOrder);
  }
  function changeShowClass(event: Event) {
    const raw = (event.currentTarget as HTMLSelectElement).value;
    if (preferences) return editPreference('showClass', raw);
    const current = Number(raw);
    session.edit(viewState.average, viewState.display, current, viewState.groupAndOrder);
  }
  function changeGroup(event: Event) {
    const raw = (event.currentTarget as HTMLSelectElement).value;
    if (preferences) return editPreference('groupBy', String(Number(raw) - 10));
    const current = Number(raw);
    session.edit(viewState.average, viewState.display, viewState.showClass || 1, current);
  }
  async function refreshLumpTables() {
    if (!contextId || !ImportExportService?.DiscoverLumpTables) return;
    lumpDiscoveryError = '';
    await ops.discoverSummaryVegLumpNames(
      reads,
      () => ImportExportService.DiscoverLumpTables(contextId, []),
      (names) => (lumpTables = names),
      (msg) => {
        lumpDiscoveryError = msg;
        notifications.error('Summary Vegetation lump table discovery failed', msg, reportToastOpts());
      }
    );
  }
  async function previewReport() {
    exclusionSummaryText = '';
    const ctxTag =
      typeof reportContextTag === 'function'
        ? reportContextTag()
        : (typeof project === 'string' && project) || undefined;
    await ops.dispatchSummaryVegPreview({
      sink: notifications,
      contextTag: ctxTag,
      session,
      port,
      unitScope: typeof unitScope === 'string' ? unitScope : 'su',
      unitField: typeof unitField === 'string' ? unitField : '',
      breakpointPolicy: typeof breakpointPolicy === 'string' ? breakpointPolicy : 'lowest',
      combineVariants: typeof combineVariants === 'boolean' ? combineVariants : false,
      lumpTable: typeof lumpTable === 'string' ? lumpTable : '',
      includeGoldstreamMetadata: typeof includeGoldstreamMetadata === 'boolean' ? includeGoldstreamMetadata : false,
      viewState:
        typeof viewState !== 'undefined' ? viewState : { average: 1, display: 1, showClass: 1, groupAndOrder: 11 },
      presentationDraft: typeof presentationView !== 'undefined' ? presentationView?.draft : null,
      presentationInitialized: typeof presentationView !== 'undefined' && !!presentationView?.initialized,
      qualityEnforce: typeof qualityView !== 'undefined' && !!qualityView?.saved?.enforce,
    });
  }
  function normalizeExclusionSummaryPreview(raw: unknown): unknown {
    return ops.normalizeExclusionSummaryPreviewData(raw);
  }
  async function previewWithPreferences() {
    exclusionSummaryText = '';
    await ops.runSummaryVegPreviewAction(
      notifications,
      reportContextTag(),
      () => session.showWithPreferences(port),
      () => session.view().error
    );
  }
  function applyWorkbookLoadedScope(opts: ops.LoadedWorkbookScopeOptions) {
    if (opts.unitScope) unitScope = opts.unitScope;
    if (opts.unitField !== undefined) unitField = opts.unitField;
    if (opts.breakpointPolicy) breakpointPolicy = opts.breakpointPolicy;
    if (opts.combineVariants !== undefined) combineVariants = opts.combineVariants;
    if (opts.lumpTable !== undefined) lumpTable = opts.lumpTable;
    if (opts.includeGoldstreamMetadata !== undefined) includeGoldstreamMetadata = opts.includeGoldstreamMetadata;
  }

  const optionsHandlers: ops.SummaryVegOptionsHandlers = {
    onUnitScopeChange: (n) => (unitScope = n), onUnitFieldInput: (n) => (unitField = n),
    onBreakpointPolicyChange: (n) => (breakpointPolicy = n), onLumpTableChange: (n) => (lumpTable = n),
    onRefreshLumpTables: refreshLumpTables, onGroupChange: changeGroup, onDisplayChange: changeDisplay,
    onShowClassChange: changeShowClass, onAverageChange: changeAverage,
    onCombineVariantsChange: (c) => (combineVariants = c), onIncludeGoldstreamChange: (c) => (includeGoldstreamMetadata = c),
  };
  const setQualBusy = (v: boolean) => (([qualityReadBusy] = [v]), reportBusy());
  const setPresBusy = (v: boolean) => (([presentationReadBusy] = [v]), reportBusy());
  const setEnvBusy = () => (([environmentalHeld] = [envDesk.summaryEnvironmentalDesktop.activity().busy]), reportBusy());
  const setWbBusy = (h: boolean) => (([workbookHeld] = [h]), reportBusy());
  const undoSummaryPref = () => (cancelPreferenceRead(), preferences?.undo());
  const peerHandlers: ops.SummaryVegPeerHandlers = {
    onLoadPreferences: loadPreferences, onSavePreferences: savePreferences, onUndoPreferences: undoSummaryPref,
    onAcknowledgePreferences: () => preferences?.acknowledge(), onCancelPreferenceRead: cancelPreferenceRead,
    onQualityReadBusyChange: setQualBusy, onPresentationReadBusyChange: setPresBusy,
    onDismissInitialFieldListReadError: dismissInitialFieldListReadError, onLoadFieldList: loadFieldList,
    onCancelFieldListRead: () => fieldList.cancel(ownedContext()), onFieldListStateChange: reportBusy,
    onEnvironmentalBusyChange: setEnvBusy, onWorkbookPreferencesLoaded: applyWorkbookLoadedScope, onWorkbookBusyChange: setWbBusy,
  };

  async function quickExportSpreadsheet() {
    if (!contextId || quickExporting || quickRendering) return;
    [quickExporting, quickError] = [true, ''];
    const snap = $state.snapshot(quickDraft);
    quick.persistQuickDraft('summary_veg', snap);
    const out = await quick.exportSummaryVegSpreadsheet(contextId, snap, project, su);
    [quickExportResult, quickError, quickExporting] = [out.summary, out.error, false];
  }
  async function quickDisplayReport() {
    if (!contextId || quickExporting || quickRendering) return;
    [quickRendering, quickError] = [true, ''];
    const snap = $state.snapshot(quickDraft);
    quick.persistQuickDraft('summary_veg', snap);
    const req = quick.buildSummaryVegQuickRequest(snap, project, false);
    const out = await quick.runQuickHTMLDisplay({
      source: 'Summary Vegetation', project,
      invoke: () => VegetationReportService.RenderSummaryVegetationHTMLReport(contextId, req),
    });
    [quickHtmlReport, quickError, quickRendering] = [out.report, out.error, false];
  }

  onMount(() => {
    void refreshLumpTables();
    void quick.hydrateSummaryVegQuickDraft(contextId, $state.snapshot(quickDraft)).then((next) => (quickDraft = next));
  });

  onDestroy(() => {
    session.cancel(port);
    unsubscribe();
    unsubscribePreferences?.();
    unsubscribeQuality?.();
    unsubscribePresentation?.();
    unsubscribeFieldList?.();
    unsubscribeEnvironment?.();
    if (fieldListScopeAvailable) fieldList.detach(ownedContext());
    cancelPreferenceRead();
    onBusyChange(false);
  });
</script>

<section data-summary-vegetation aria-label="Summary Vegetation" class="summary-vegetation">
  <CompactReportShell
    title="Summary Vegetation"
    subtitle="Compact VPro64 summary of species presence and mean cover by unit."
    {contextId}
    {project}
    {su}
    hierarchy={effectiveHierarchy}
    busy={viewState.busy || operationHeld}
    exporting={quickExporting}
    rendering={quickRendering}
    exportResult={quickExportResult}
    htmlReport={quickHtmlReport}
    errorMessage={quickError || viewState.draftError || preferenceView?.draftError || ''}
    onExportSpreadsheet={quickExportSpreadsheet}
    onDisplayReport={quickDisplayReport}
    onCloseHtmlReport={() => (quickHtmlReport = null)}
  >
    {#snippet headerExtra()}
      <button type="button" class="btn-secondary" onclick={previewReport} disabled={vm.previewDisabled} data-summary-preview>
        Inline Preview
      </button>
      {#if viewState.busy}<button type="button" class="btn-secondary" onclick={() => session.cancel(port)} data-summary-cancel>Cancel</button>{/if}
    {/snippet}
    {#snippet quickOptions()}
      <SummaryVegetationQuickOptions
        draft={quickDraft}
        {lumpTables}
        disabled={quickExporting || quickRendering}
        onChange={(next) => (quickDraft = next)}
      />
    {/snippet}
    {#snippet advanced()}
      <div class="actions">
        <button
          type="button"
          onclick={previewWithPreferences}
          disabled={vm.savedPreviewDisabled}
          data-summary-preview-preferences>Preview with Saved Preferences</button
        >
      </div>
      <SummaryVegetationOptionsBar model={vm.optionsModel} handlers={optionsHandlers} />
      <SummaryVegetationPeerPanels model={vm.peerModel} handlers={peerHandlers} />
      <div class="exclusion-section table-scroll">
        <SiteUnitExclusionFilter
          {contextId}
          {su}
          hierarchy={effectiveHierarchy}
          reportMode="summary"
          average={viewState.average}
          display={viewState.display}
          showClass={viewState.display === 4 || viewState.display === 5 ? viewState.showClass || 1 : 0}
          groupAndOrder={viewState.groupAndOrder}
          onBusyChange={onExclusionBusyChange}
          onSummaryPreview={(result) => {
            exclusionSummaryText = `${result.exclusions.retainedUnits?.length ?? 0} units retained (${result.exclusions.excludedUnits?.length ?? 0} excluded; ${result.exclusions.retainedPlots}/${result.exclusions.totalPlotsBefore} plots)`;
            void session.applyExternalPreview(normalizeExclusionSummaryPreview(result.preview), port);
          }}
        />
        {#if exclusionSummaryText}<p role="status" data-summary-exclusion-status>{exclusionSummaryText}</p>{/if}
      </div>
    {/snippet}
    {#snippet results()}
      {#if viewState.preview && !qualityInvalid}
        <SummaryVegetationResultPanel {project} {su} preview={viewState.preview} />
      {/if}
    {/snippet}
  </CompactReportShell>
</section>

<style>
  .summary-vegetation {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 1rem;
    padding: 1rem;
    background: var(--vpro-canvas);
    color: var(--vpro-ink);
    min-width: 0;
  }
  .exclusion-section {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 0.75rem;
    min-width: 0;
    overflow-wrap: anywhere;
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.75rem;
    align-items: center;
  }
  .btn-secondary,
  .actions button {
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
  .btn-secondary:disabled,
  .actions button:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }
  .table-scroll {
    overflow-x: auto;
    max-width: 100%;
  }
  @media (max-width: 960px) {
    .summary-vegetation {
      padding: 0.75rem;
    }
  }
</style>
