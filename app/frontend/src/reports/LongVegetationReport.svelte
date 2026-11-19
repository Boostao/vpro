<script module lang="ts">
  import { createLongVegetationGroupPreferencesRegistry } from './longVegetationGroupPreferences';
  import { createLongVegetationNamingPreferencesRegistry } from './longVegetationNamingPreferences';
  import { createLongVegetationSelectedFieldPreferencesRegistry } from './longVegetationSelectedFieldPreferences';
  import { createLongVegetationEnforcementPreferencesRegistry } from './longVegetationEnforcementPreferences';
  import { createLongVegetationUnitPreferencesRegistry } from './longVegetationUnitPreferences';
  import { createSelectedUnitSelectionRegistry } from './longVegetationSelectedUnitSelection';
  const selectedUnitSession = createSelectedUnitSelectionRegistry();
  const groupingSession = createLongVegetationGroupPreferencesRegistry({
    strata: true,
    lifeform: true,
  });
  const namingSession = createLongVegetationNamingPreferencesRegistry({ code: true });
  const selectedFieldSession = createLongVegetationSelectedFieldPreferencesRegistry();
  const enforcementSession = createLongVegetationEnforcementPreferencesRegistry();
  const unitSession = createLongVegetationUnitPreferencesRegistry(true, true);
</script>

<script lang="ts">
  import { onMount, onDestroy, untrack } from 'svelte';
  import { ImportExportService, VegetationReportService, type ProjectMetadataCell } from '../../bindings/github.com/boostao/vpro/app';
import type { LongVegetationSettings } from '../../bindings/github.com/boostao/vpro/app/internal/vegreport/models';
  import { projectState } from '../shared/state';
  import { ReadRequests } from '../shared/readRequests';
  import SiteUnitExclusionFilter from '../classification/SiteUnitExclusionFilter.svelte';
  import { createDefaultBreakpointOptions, type HierarchyBreakpointOptions, type SiteUnitExclusionRule, type SiteUnitExclusionSummary } from '../classification/siteUnitExclusionFilter';
  import { reportCellText } from './longEnvironmentReport';
  import { requireLongVegetationGrouping, validateLongVegetationOptions, validateLongVegetationPreview, type ValidatedLongVegetationPreview } from './longVegetationReport';
  import { vegetationWorkbookPublicationSession, VegetationWorkbookPublicationSession, type ValidatedVegetationWorkbookReview } from './vegetationWorkbook';
  import { longVegetationPreferencesSession } from './longVegetationPreferences';
  import { longVegetationStatisticsPreferencesSession } from './longVegetationStatisticsPreferences';
  import { longVegetationSwitchPreferencesSession } from './longVegetationSwitchPreferences';
  import LongVegetationSwitchPreferences from './LongVegetationSwitchPreferences.svelte';
  import { longVegetationThresholdPreferencesSession } from './longVegetationThresholdPreferences';
  import LongVegetationThresholdPreferences from './LongVegetationThresholdPreferences.svelte';
  import LongVegetationGroupPreferences from './LongVegetationGroupPreferences.svelte';
  import { longVegetationQualityNullPreferencesSession } from './longVegetationQualityNullPreferences';
  import LongVegetationQualityNullPreferences from './LongVegetationQualityNullPreferences.svelte';
  import { longVegetationQualityMinimumPreferencesSession } from './longVegetationQualityMinimumPreferences';
  import LongVegetationQualityMinimumPreferences from './LongVegetationQualityMinimumPreferences.svelte';
  import LongVegetationNamingPreferences from './LongVegetationNamingPreferences.svelte';
  import LongVegetationSelectedFieldPreferences from './LongVegetationSelectedFieldPreferences.svelte';
  import LongVegetationEnforcementPreferences from './LongVegetationEnforcementPreferences.svelte';
  import LongVegetationUnitPreferences from './LongVegetationUnitPreferences.svelte';
  import LongVegetationSelectedUnitSelection from './LongVegetationSelectedUnitSelection.svelte';
  import LongVegetationProjectScopeSelection from './LongVegetationProjectScopeSelection.svelte';
  import LongVegetationProjectUnitPreferences from './LongVegetationProjectUnitPreferences.svelte';
  import type { ProjectScopeSelectionSession } from './longVegetationProjectScopeSession';
  import { projectReportWorkspace } from './longVegetationProjectWorkspaces';
  import { notifications } from '../shell/notificationService.svelte';

  let { contextId, project, projectPath, su, suPath, hierarchy = '', operationHeld = false, onBusyChange }: {
    contextId: string; project: string; projectPath: string; su: string; suPath: string;
    hierarchy?: string;
    operationHeld?: boolean;
    onBusyChange: (busy: boolean) => void;
  } = $props();

  const effectiveHierarchy = $derived(
    (hierarchy && hierarchy !== 'None' ? hierarchy : '') ||
    ($projectState?.activeHierarchy && $projectState.activeHierarchy !== 'None' ? $projectState.activeHierarchy : '') ||
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
  const reads = new ReadRequests();
  let generation = 0;
  let disposed = false;
  const lifeformEnabled = true;
  const strataEnabled = true;
  const codeEnabled = true;
  const selectedFieldEnabled = true;
  const noneUnitsEnabled = true;
  const selectedUnitsEnabled = true;
  const workbookEnabled = true;
  const preferencesEnabled = true;
  const statisticsEnabled = true;
  const switchesEnabled = true;
  const thresholdsEnabled = true;
  const qualityNullsEnabled = true;
  const qualityMinimaEnabled = true;
  const workbookOwner = untrack(() => ({ contextId, project, projectPath, su, suPath }));
  const projectWorkspace = untrack(() => projectReportWorkspace?.(workbookOwner) ?? null);
  const projectScopeSelection = projectWorkspace ? ({
    view: () => {
      const raw = projectWorkspace.selection.view();
      if (raw && !raw.dirty && (!raw.fields || raw.fields.length === 0) && raw.scope?.sourceKind !== 'project-selected-fields') {
        return { ...raw, draftError: '' };
      }
      return raw;
    },
    subscribe: (listener: () => void) => projectWorkspace.selection.subscribe(listener),
    cancel: () => projectWorkspace.selection.cancel(),
    load: () => projectWorkspace.selection.load(),
    switchTo: (sourceKind: 'selected-list' | 'project-selected-fields' | 'project-all-plots') => projectWorkspace.selection.switchTo(sourceKind),
    build: () => projectWorkspace.selection.build(),
    edit: (fields: string[]) => projectWorkspace.selection.edit(fields),
    undo: () => projectWorkspace.selection.undo(),
  } as ProjectScopeSelectionSession) : null;
  let projectView = $state.raw(untrack(() => projectWorkspace?.view() ?? null));
  const projectActive = $derived(!!projectView?.projectActive);
  const projectScopeKnown = $derived(!projectWorkspace || !!projectView?.scope.scope && !projectView.scope.authorityUnknown);
  const projectBarrier = $derived(!!projectWorkspace && (!projectScopeKnown || !!projectView &&
    (projectView.readBusy || projectView.scope.busy ||
      projectView.scope.scope?.sourceKind === 'project-selected-fields' && projectView.scope.dirty ||
      projectView.units.closeBlocked)));
  const projectMutationHeld = $derived(!!projectView && (projectView.readBusy || projectView.scope.busy ||
    projectView.units.readBusy || projectView.units.busy || projectView.units.blocked));
  const preferences = preferencesEnabled ? longVegetationPreferencesSession(workbookOwner) : null;
  let preferenceView = $state(preferences?.view() ?? null);
  const statistics = statisticsEnabled ? longVegetationStatisticsPreferencesSession(workbookOwner) : null;
  let statisticsView = $state(statistics?.view() ?? null);
  const titleBarrier = $derived(!!preferenceView && (preferenceView.busy || preferenceView.blocked ||
    preferenceView.authorityUnknown || !!preferenceView.draftError));
  const statisticsBarrier = $derived(!!statisticsView && (statisticsView.busy || statisticsView.blocked ||
    statisticsView.authorityUnknown || !!statisticsView.draftError));
  const switches = switchesEnabled ? longVegetationSwitchPreferencesSession(workbookOwner) : null;
  let switchView = $state(switches?.view() ?? null);
  let switchReadBusy = $state(false);
  const switchBarrier = $derived(switchReadBusy || !!switchView && (switchView.busy || switchView.blocked ||
    switchView.authorityUnknown || !!switchView.draftError));
  const switchMutationHeld = $derived(switchReadBusy || !!switchView && (switchView.busy || switchView.blocked));
  const thresholds = thresholdsEnabled ? longVegetationThresholdPreferencesSession(workbookOwner) : null;
  let thresholdView = $state(thresholds?.view() ?? null);
  let thresholdReadBusy = $state(false);
  const thresholdBarrier = $derived(thresholdReadBusy || !!thresholdView && (thresholdView.busy || thresholdView.blocked ||
    thresholdView.authorityUnknown || !!thresholdView.draftError));
  const thresholdMutationHeld = $derived(thresholdReadBusy || !!thresholdView && (thresholdView.busy || thresholdView.blocked));
  const groups = groupingSession ? groupingSession(workbookOwner) : null;
  let groupView = $state(groups?.view() ?? null);
  let groupReadBusy = $state(false);
  const groupBarrier = $derived(groupReadBusy || !!groupView && (groupView.busy || groupView.blocked ||
    groupView.authorityUnknown || !!groupView.draftError));
  const groupMutationHeld = $derived(groupReadBusy || !!groupView && (groupView.busy || groupView.blocked));
  const qualityNulls = qualityNullsEnabled ? longVegetationQualityNullPreferencesSession(workbookOwner) : null;
  let qualityNullView = $state(qualityNulls?.view() ?? null);
  let qualityNullReadBusy = $state(false);
  const qualityNullBarrier = $derived(qualityNullReadBusy || !!qualityNullView && (qualityNullView.busy || qualityNullView.blocked ||
    qualityNullView.authorityUnknown || !!qualityNullView.draftError));
  const qualityNullMutationHeld = $derived(qualityNullReadBusy || !!qualityNullView && (qualityNullView.busy || qualityNullView.blocked));
  const qualityMinima = qualityMinimaEnabled ? longVegetationQualityMinimumPreferencesSession(workbookOwner) : null;
  let qualityMinimumView = $state(qualityMinima?.view() ?? null);
  let qualityMinimumReadBusy = $state(false);
  const qualityMinimumBarrier = $derived(qualityMinimumReadBusy || !!qualityMinimumView && (qualityMinimumView.busy || qualityMinimumView.blocked ||
    qualityMinimumView.authorityUnknown || !!qualityMinimumView.draftError));
  const qualityMinimumMutationHeld = $derived(qualityMinimumReadBusy || !!qualityMinimumView && (qualityMinimumView.busy || qualityMinimumView.blocked));
  const naming = namingSession ? namingSession(workbookOwner) : null;
  let namingView = $state(naming?.view() ?? null);
  let namingReadBusy = $state(false);
  const namingBarrier = $derived(namingReadBusy || !!namingView && (namingView.busy || namingView.blocked ||
    namingView.authorityUnknown || !!namingView.draftError));
  const namingMutationHeld = $derived(namingReadBusy || !!namingView && (namingView.busy || namingView.blocked));
  const selectedField = selectedFieldSession ? selectedFieldSession(workbookOwner) : null;
  let selectedFieldView = $state(selectedField?.view() ?? null);
  let selectedFieldReadBusy = $state(false);
  const selectedFieldBarrier = $derived(selectedFieldReadBusy || !!selectedFieldView && (selectedFieldView.busy || selectedFieldView.blocked ||
    selectedFieldView.authorityUnknown || !!selectedFieldView.draftError));
  const selectedFieldMutationHeld = $derived(selectedFieldReadBusy || !!selectedFieldView && (selectedFieldView.busy || selectedFieldView.blocked));
  const enforcement = enforcementSession ? enforcementSession(workbookOwner) : null;
  let enforcementView = $state(enforcement?.view() ?? null);
  let enforcementReadBusy = $state(false);
  const enforcementBarrier = $derived(enforcementReadBusy || !!enforcementView && (enforcementView.busy || enforcementView.blocked ||
    enforcementView.authorityUnknown || !!enforcementView.draftError));
  const enforcementMutationHeld = $derived(enforcementReadBusy || !!enforcementView && (enforcementView.busy || enforcementView.blocked));
  const units = unitSession ? unitSession(workbookOwner) : null;
  let unitView = $state(units?.view() ?? null);
  let unitReadBusy = $state(false);
  const selectedUnitSelection = selectedUnitSession ? selectedUnitSession(workbookOwner) : null;
  let selectedUnitView = $state.raw(selectedUnitSelection?.view() ?? null);
  const selectedUnitBarrier = $derived(!!selectedUnitView && (selectedUnitView.busy ||
    selectedUnitView.dirty || selectedUnitView.authorityUnknown));
  const selectedUnitMutationHeld = $derived(!!selectedUnitView?.busy);
  const ordinaryUnitBarrier = $derived(selectedUnitBarrier || unitReadBusy || !!unitView && (unitView.busy || unitView.blocked ||
    unitView.authorityUnknown || !!unitView.draftError));
  const unitBarrier = $derived(ordinaryUnitBarrier || projectBarrier);
  const ordinaryUnitMutationHeld = $derived(selectedUnitMutationHeld || unitReadBusy || !!unitView && (unitView.busy || unitView.blocked));
  const unitMutationHeld = $derived(ordinaryUnitMutationHeld || projectMutationHeld);
  const sharedPreferenceBarrier = $derived(titleBarrier || statisticsBarrier || switchBarrier || thresholdBarrier || groupBarrier || qualityNullBarrier || qualityMinimumBarrier || namingBarrier || selectedFieldBarrier || enforcementBarrier || ordinaryUnitBarrier);
  const sharedMutationHeld = $derived(ordinaryUnitMutationHeld || !!preferenceView?.busy || !!preferenceView?.blocked ||
    !!statisticsView?.busy || !!statisticsView?.blocked || switchMutationHeld || thresholdMutationHeld ||
    groupMutationHeld || qualityNullMutationHeld || qualityMinimumMutationHeld || namingMutationHeld ||
    selectedFieldMutationHeld || enforcementMutationHeld);
  const preferenceBarrier = $derived(sharedPreferenceBarrier || projectBarrier);
  const workbookSession = workbookEnabled ? vegetationWorkbookPublicationSession(workbookOwner, selectedUnitsEnabled) :
    new VegetationWorkbookPublicationSession(workbookOwner, selectedUnitsEnabled);
  let publication = $state(workbookSession.view());
  const workbookBarrier = $derived(publication.busy || publication.blocked ||
    !!projectView?.publication && (projectView.publication.busy || projectView.publication.blocked));
  const activeWorkbookReview = $derived(projectActive ? projectView?.workbookReview ?? null : workbookReview);
  const groupLabel = $derived(settings?.grouping === 'lifeform' ? 'Lifeform' : settings?.grouping === 'strata' ? 'Strata' : 'Layer');
  let notifiedPrefReceipts = 0;
  let lastPrefError = '';
  let notifiedStatReceipts = 0;
  let lastStatError = '';
  let lastPubNotificationKey = '';
  let lastProjError = '';
  let lastProjPubNotificationKey = '';
  function resolveContextTag() {
    return (typeof project === 'string' && project) ||
      (typeof effectiveHierarchy === 'string' && effectiveHierarchy !== 'None' ? effectiveHierarchy : undefined) ||
      (typeof hierarchy === 'string' && hierarchy && hierarchy !== 'None' ? hierarchy : undefined);
  }
  function emitLongVegWorkbookToast(
    pub: { outcome?: { status: string; path: string; sha256: string } | null; error?: string; requestedDestination: string } | null | undefined,
    destFallback: string,
    ctxTag: string | undefined,
  ) {
    if (!pub || typeof notifications === 'undefined') return;
    const opts = { category: 'reports' as const, source: 'Long Vegetation', contextTag: ctxTag };
    if (pub.outcome?.status === 'published' && !pub.error) {
      notifications.success('Long Vegetation workbook exported', pub.outcome.path || pub.requestedDestination || destFallback, opts);
    } else if (pub.error || pub.outcome) {
      notifications.error('Long Vegetation workbook export failed', pub.error || `Publication ${pub.outcome?.status ?? 'failed'} for ${pub.requestedDestination || destFallback}`, opts);
    }
  }
  function syncWorkbookNotifications() {
    const pub = publication;
    if (!pub || typeof notifications === 'undefined') { lastPubNotificationKey = ''; return; }
    const key = pub.outcome
      ? `outcome:${pub.outcome.status}:${pub.requestedDestination}:${pub.outcome.path}:${pub.outcome.sha256}:${pub.error ?? ''}`
      : pub.error ? `error:${pub.error}:${pub.requestedDestination}` : '';
    if (!key) { lastPubNotificationKey = ''; return; }
    if (key === lastPubNotificationKey) return;
    lastPubNotificationKey = key;
    emitLongVegWorkbookToast(pub, destination, resolveContextTag());
  }
  function syncProjectNotifications() {
    const pv = projectView;
    if (!pv || typeof notifications === 'undefined') {
      lastProjError = '';
      lastProjPubNotificationKey = '';
      return;
    }
    const ctxTag = resolveContextTag();
    const projErr = pv.error ?? '';
    if (projErr && projErr !== lastProjError) {
      notifications.error('Long Vegetation project report failed', projErr, {
        category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
      });
    }
    lastProjError = projErr;
    const pub = pv.publication;
    if (!pub) { lastProjPubNotificationKey = ''; return; }
    const key = pub.outcome
      ? `outcome:${pub.outcome.status}:${pub.requestedDestination}:${pub.outcome.path}:${pub.outcome.sha256}:${pub.error ?? ''}`
      : pub.error ? `error:${pub.error}:${pub.requestedDestination}` : '';
    if (!key) { lastProjPubNotificationKey = ''; return; }
    if (key === lastProjPubNotificationKey) return;
    lastProjPubNotificationKey = key;
    emitLongVegWorkbookToast(pub, destination, ctxTag);
  }
  function syncPreferenceNotifications() {
    const v = preferenceView;
    if (!v || typeof notifications === 'undefined') return;
    const receipts = v.receipts ?? [];
    if (receipts.length < notifiedPrefReceipts) notifiedPrefReceipts = 0;
    const ctxTag = resolveContextTag();
    for (let i = notifiedPrefReceipts; i < receipts.length; i++) {
      const receipt = receipts[i];
      if (receipt.kind === 'known') {
        if (receipt.outcome.committed && !receipt.outcome.errorMessage) {
          notifications.success('Long Vegetation title saved', receipt.outcome.changed ? 'Saved report title preference.' : 'No title changes.', {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
        } else if (receipt.outcome.committed) {
          notifications.warning('Long Vegetation title saved with warning', receipt.outcome.errorMessage, {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
          lastPrefError = receipt.outcome.errorMessage;
        } else if (receipt.outcome.errorMessage) {
          notifications.error('Long Vegetation title save failed', receipt.outcome.errorMessage, {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
          lastPrefError = receipt.outcome.errorMessage;
        } else {
          notifications.info('Long Vegetation title unchanged', 'No title preference changes were needed.', {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
        }
      }
    }
    notifiedPrefReceipts = receipts.length;
    const prefErr = v.error ?? '';
    if (prefErr && prefErr !== lastPrefError) {
      notifications.error('Long Vegetation title preference failed', prefErr, {
        category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
      });
    }
    lastPrefError = prefErr;
  }
  function syncStatisticsNotifications() {
    const v = statisticsView;
    if (!v || typeof notifications === 'undefined') return;
    const receipts = v.receipts ?? [];
    if (receipts.length < notifiedStatReceipts) notifiedStatReceipts = 0;
    const ctxTag = resolveContextTag();
    for (let i = notifiedStatReceipts; i < receipts.length; i++) {
      const receipt = receipts[i];
      if (receipt.kind === 'known') {
        if (receipt.outcome.committed && !receipt.outcome.errorMessage) {
          notifications.success('Long Vegetation Average/Order saved', receipt.outcome.changed ? 'Saved Average/Order preferences.' : 'No Average/Order changes.', {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
        } else if (receipt.outcome.committed) {
          notifications.warning('Long Vegetation Average/Order saved with warning', receipt.outcome.errorMessage, {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
          lastStatError = receipt.outcome.errorMessage;
        } else if (receipt.outcome.errorMessage) {
          notifications.error('Long Vegetation Average/Order save failed', receipt.outcome.errorMessage, {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
          lastStatError = receipt.outcome.errorMessage;
        } else {
          notifications.info('Long Vegetation Average/Order unchanged', 'No Average/Order changes were needed.', {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
        }
      }
    }
    notifiedStatReceipts = receipts.length;
    const statErr = v.error ?? '';
    if (statErr && statErr !== lastStatError) {
      notifications.error('Long Vegetation Average/Order preference failed', statErr, {
        category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
      });
    }
    lastStatError = statErr;
  }
  function reportBusy() { onBusyChange(busy || workbookBarrier || sharedPreferenceBarrier || !!projectView?.closeBlocked); }
  function invalidateReports() {
    preview = null; workbookReview = null;
    projectWorkspace?.invalidate();
  }
  const unsubscribeWorkbook = workbookSession.subscribe(() => {
    publication = workbookSession.view();
    if (publication.blocked) workbookReview = null;
    syncWorkbookNotifications();
    reportBusy();
  });
  const unsubscribePreferences = preferences?.subscribe(() => {
    preferenceView = preferences.view(); invalidateReports();
    if (preferenceView.authorityUnknown || settings && preferenceView.saved && settings.title !== preferenceView.saved.title) settings = null;
    syncPreferenceNotifications();
    reportBusy();
  });
  const unsubscribeStatistics = statistics?.subscribe(() => {
    statisticsView = statistics.view(); invalidateReports();
    if (statisticsView.authorityUnknown || settings && statisticsView.saved &&
        (settings.average !== (statisticsView.saved.avgType === 10 ? 'all-plots' : 'observations') ||
         settings.order !== (statisticsView.saved.orderBy === 10 ? 'species' : 'presence'))) settings = null;
    syncStatisticsNotifications();
    reportBusy();
  });
  const unsubscribeSwitches = switches?.subscribe(() => {
    switchView = switches.view(); invalidateReports();
    if (switchView.authorityUnknown || settings && switchView.saved &&
        settings.constantSpeciesList !== switchView.saved.constantSpeciesList) settings = null;
    reportBusy();
  });
  const unsubscribeThresholds = thresholds?.subscribe(() => {
    thresholdView = thresholds.view(); invalidateReports();
    if (thresholdView.authorityUnknown || settings && thresholdView.saved &&
        (settings.presenceGreaterThan !== thresholdView.saved.presenceGreaterThan ||
         settings.meanCoverGreaterThan !== thresholdView.saved.meanCoverGreaterThan)) settings = null;
    reportBusy();
  });
  const unsubscribeGroups = groups?.subscribe(() => {
    groupView = groups.view(); invalidateReports();
    if (groupView.authorityUnknown || settings && groupView.saved &&
        settings.grouping !== (groupView.saved.groupBy === 1 ? 'layer' : groupView.saved.groupBy === 2 ? 'strata' :
          groupView.saved.groupBy === 3 ? 'lifeform' : 'none')) settings = null;
    reportBusy();
  });
  const unsubscribeQualityNulls = qualityNulls?.subscribe(() => {
    qualityNullView = qualityNulls.view(); invalidateReports();
    if (qualityNullView.authorityUnknown || settings?.quality && qualityNullView.saved &&
        (settings.quality.site.includeNull !== qualityNullView.saved.siteIncludeNulls ||
         settings.quality.veg.includeNull !== qualityNullView.saved.vegIncludeNulls ||
         settings.quality.soil.includeNull !== qualityNullView.saved.soilIncludeNulls)) settings = null;
    reportBusy();
  });
  const unsubscribeQualityMinima = qualityMinima?.subscribe(() => {
    qualityMinimumView = qualityMinima.view(); invalidateReports();
    if (qualityMinimumView.authorityUnknown || settings?.quality && qualityMinimumView.saved &&
        (settings.quality.site.minimum !== qualityMinimumView.saved.siteMinimum ||
         settings.quality.veg.minimum !== qualityMinimumView.saved.vegMinimum ||
         settings.quality.soil.minimum !== qualityMinimumView.saved.soilMinimum)) settings = null;
    reportBusy();
  });
  const unsubscribeNaming = naming?.subscribe(() => {
    namingView = naming.view(); invalidateReports();
    if (namingView.authorityUnknown || settings && namingView.saved &&
        (settings.showEnglishName !== (namingView.saved.mode === 1) ||
         settings.showSpeciesCode !== (namingView.saved.mode === 2) ||
         settings.selectedField !== (namingView.saved.mode === 4 ? namingView.saved.selectedField : undefined))) settings = null;
    reportBusy();
  });
  const unsubscribeSelectedField = selectedField?.subscribe(() => {
    selectedFieldView = selectedField.view(); invalidateReports();
    if (selectedFieldView.authorityUnknown || settings && selectedFieldView.saved &&
        (settings.showEnglishName !== (selectedFieldView.saved.mode === 1) ||
         settings.showSpeciesCode !== (selectedFieldView.saved.mode === 2) ||
         settings.selectedField !== (selectedFieldView.saved.mode === 4 ? selectedFieldView.saved.selectedField : undefined))) settings = null;
    reportBusy();
  });
  const unsubscribeEnforcement = enforcement?.subscribe(() => {
    enforcementView = enforcement.view(); invalidateReports();
    if (enforcementView.authorityUnknown || settings && enforcementView.saved &&
        (!!settings.quality !== enforcementView.saved.enforce ||
         (settings.unitGrouping === 'all-plots' ? 3 : settings.unitGrouping === 'selected-fields' ? 2 : 1) !== enforcementView.saved.unitGroups)) settings = null;
    reportBusy();
  });
  const unsubscribeUnits = units?.subscribe(() => {
    unitView = units.view(); invalidateReports();
    if (unitView.authorityUnknown || settings && unitView.saved &&
        (settings.unitGrouping === 'all-plots' ? 3 : settings.unitGrouping === 'selected-fields' ? 2 : 1) !== unitView.saved.unitGroups) settings = null;
    reportBusy();
  });
  let wasProjectActive = untrack(() => !!projectView?.projectActive);
  function projectChanged() {
    const nextView = projectWorkspace?.view() ?? null;
    const nextActive = !!nextView?.projectActive;
    if (wasProjectActive || nextActive) {
      generation++; reads.cancelAll(); busy = false;
      workbookReview = null;
      settings = nextActive ? nextView?.settings ?? null : null;
      preview = nextActive ? nextView?.preview ?? null : null;
    }
    wasProjectActive = nextActive;
    projectView = nextView;
    syncProjectNotifications();
    reportBusy();
  }
  const unsubscribeProject = projectWorkspace?.subscribe(projectChanged);
  syncWorkbookNotifications();
  syncPreferenceNotifications();
  syncStatisticsNotifications();
  syncProjectNotifications();

  function selectedUnitChanged() {
    generation++; reads.cancelAll(); busy = false;
    selectedUnitView = selectedUnitSelection?.view() ?? null;
    preview = null; workbookReview = null; settings = null;
    reportBusy();
  }

  function cancel() {
    generation++; reads.cancelAll(); projectWorkspace?.cancelReportRead(); preferences?.cancelLoad(); statistics?.cancelLoad(); busy = false; reportBusy();
  }
  async function readProject(operation: () => Promise<void>) {
    if (busy || operationHeld || workbookBarrier || sharedPreferenceBarrier || !projectView?.outputReady) return;
    error = '';
    try {
      await operation();
      const pv = projectWorkspace?.view?.();
      if (pv?.error && typeof notifications !== 'undefined') {
        const ctxTag = (typeof project === 'string' && project) || (typeof effectiveHierarchy === 'string' && effectiveHierarchy !== 'None' ? effectiveHierarchy : undefined) || (typeof hierarchy === 'string' && hierarchy && hierarchy !== 'None' ? hierarchy : undefined);
        notifications.error('Long Vegetation project report failed', pv.error, {
          category: 'reports',
          source: 'Long Vegetation',
          contextTag: ctxTag,
        });
      }
    } catch (cause) {
      error = `Original project report unavailable: ${String(cause)}`;
      if (typeof notifications !== 'undefined') {
        const ctxTag = (typeof project === 'string' && project) || (typeof effectiveHierarchy === 'string' && effectiveHierarchy !== 'None' ? effectiveHierarchy : undefined) || (typeof hierarchy === 'string' && hierarchy && hierarchy !== 'None' ? hierarchy : undefined);
        notifications.error('Long Vegetation project report failed', error, {
          category: 'reports',
          source: 'Long Vegetation',
          contextTag: ctxTag,
        });
      }
    }
  }
  async function loadLumpTables() {
    if (typeof ImportExportService?.DiscoverLumpTables !== 'function') return;
    try {
      const discovered = await reads.track(ImportExportService.DiscoverLumpTables(contextId, []));
      if (disposed || !Array.isArray(discovered)) return;
      lumpTables = discovered
        .map(item => (typeof item === 'string' ? item : String((item as { tableName?: string })?.tableName ?? '')))
        .filter(name => !!name && !/^none(?:_lump)?$/i.test(name) && !/^combinedspp_lump$/i.test(name));
    } catch {
      // Optional lump discovery leaves 'unlumped' default intact if service is unattached.
    }
  }
  function syncScopeAndVariantOptions(candidate: LongVegetationSettings | null | undefined) {
    if (!candidate) return;
    if (typeof useSppCodesOnlyOverridden === 'boolean' && !useSppCodesOnlyOverridden) useSppCodesOnly = !!candidate.combineVariants;
    if (typeof selectedScopeOverridden === 'boolean' && !selectedScopeOverridden && candidate.lumpTable &&
        !/^none(?:_lump)?$/i.test(candidate.lumpTable) && !/^combinedspp_lump$/i.test(candidate.lumpTable)) {
      selectedWorkbookScope = `lump:${candidate.lumpTable}`;
    }
  }
  function acceptValidatedPreview(raw: unknown) {
    const candidate = validateLongVegetationPreview(raw as never, contextId, project, projectPath, su, suPath, selectedUnitsEnabled);
    requireLongVegetationGrouping(candidate.settings, lifeformEnabled, strataEnabled, codeEnabled, selectedFieldEnabled, noneUnitsEnabled, selectedUnitsEnabled);
    preview = candidate;
    settings = candidate.settings;
  }
  function baseVariantCode(code: string): string {
    if (code.length <= 1) return code;
    const last = code.charAt(code.length - 1);
    return last >= '0' && last < '9' ? code.slice(0, -1) : code;
  }
  function rollupUnitRows(unit: ValidatedLongVegetationPreview['report']['units'][number], activeSettings: LongVegetationSettings) {
    if (!useSppCodesOnly || activeSettings.combineVariants) return unit.rows;
    const merged = new Map<string, typeof unit.rows[number]>();
    for (const row of unit.rows) {
      const rawSpecies = row.species.storage === 'text' ? (row.species.text ?? '') : '';
      const rolledSpecies = rawSpecies ? baseVariantCode(rawSpecies) : rawSpecies;
      const layerKey = `${row.layer.storage}:${row.layer.text ?? row.layer.integer ?? ''}`;
      const key = `${layerKey}|${rolledSpecies.toUpperCase()}`;
      const existing = merged.get(key);
      if (!existing) {
        merged.set(key, {
          ...row,
          species: row.species.storage === 'text' ? { ...row.species, text: rolledSpecies } : row.species,
          plots: row.plots.map(plot => ({ ...plot })),
        });
      } else {
        let nonNullPlots = 0;
        let coverSum = 0;
        const combinedPlots = existing.plots.map((plot, index) => {
          const incoming = row.plots[index]?.cover ?? null;
          let nextCover = plot.cover;
          if (incoming !== null) {
            nextCover = nextCover === null ? incoming : Math.min(99, nextCover + incoming);
          }
          if (nextCover !== null) {
            nonNullPlots += 1;
            coverSum += nextCover;
          }
          return { ...plot, cover: nextCover };
        });
        const denom = activeSettings.average === 'observations' ? nonNullPlots : unit.numPlots;
        existing.plots = combinedPlots;
        existing.presence = unit.numPlots > 0 ? nonNullPlots / unit.numPlots : null;
        existing.meanCover = denom > 0 ? coverSum / denom : null;
      }
    }
    return [...merged.values()];
  }
  async function options() {
    if (projectActive && projectWorkspace) { await readProject(() => projectWorkspace.loadOptions()); return; }
    if (busy || operationHeld || workbookBarrier || preferenceBarrier || !su || su === 'None') return;
    cancel(); const request = generation; settings = null; error = ''; preview = null; workbookReview = null;
    busy = true; reportBusy();
    try {
      const value = await reads.track(VegetationReportService.GetLongVegetationOptions(contextId));
      if (request !== generation) return;
      const candidate = validateLongVegetationOptions(value, contextId, project, projectPath, su, suPath, selectedUnitsEnabled).settings;
      requireLongVegetationGrouping(candidate, lifeformEnabled, strataEnabled, codeEnabled, selectedFieldEnabled, noneUnitsEnabled, selectedUnitsEnabled);
      settings = candidate;
      if (typeof syncScopeAndVariantOptions === 'function') syncScopeAndVariantOptions(candidate);
    } catch (cause) {
      if (request === generation) {
        error = `Report options unavailable: ${String(cause)}`;
        if (typeof notifications !== 'undefined') {
          const ctxTag = (typeof project === 'string' && project) || (typeof effectiveHierarchy === 'string' && effectiveHierarchy !== 'None' ? effectiveHierarchy : undefined) || (typeof hierarchy === 'string' && hierarchy && hierarchy !== 'None' ? hierarchy : undefined);
          notifications.error('Long Vegetation options failed', error, {
            category: 'reports',
            source: 'Long Vegetation',
            contextTag: ctxTag,
          });
        }
      }
    } finally {
      if (request === generation) { busy = false; reportBusy(); }
    }
  }
  async function show() {
    if (projectActive && projectWorkspace) { await readProject(() => projectWorkspace.showPreview()); return; }
    if (busy || operationHeld || workbookBarrier || preferenceBarrier || !settings || su === 'None') return;
    cancel(); const request = generation; error = ''; preview = null; workbookReview = null;
    busy = true; reportBusy();
    try {
      const targetScope = typeof selectedWorkbookScope === 'string' && selectedWorkbookScope.trim()
        ? selectedWorkbookScope.trim() : 'unlumped';
      const activeExclusions = typeof applyExclusionsToReport === 'boolean' && applyExclusionsToReport;
      const activeBP = typeof useHierarchyBreakpoints === 'boolean' && useHierarchyBreakpoints;
      const activeRules = typeof exclusionRules !== 'undefined' && Array.isArray(exclusionRules) ? exclusionRules : [];
      const useExclusions = (activeExclusions || activeBP) && activeRules.some(rule => rule.enabled);
      if (useExclusions && typeof VegetationReportService?.PreviewLongVegetationWithExclusions === 'function') {
        const res = await reads.track(VegetationReportService.PreviewLongVegetationWithExclusions(contextId, {
          rules: activeRules.map(rule => ({ ...rule })),
          useDefaultPresets: false,
          useHierarchyBreakpoints: activeBP,
          breakpointOptions: typeof breakpointOptions === 'object' && breakpointOptions ? { ...breakpointOptions } : createDefaultBreakpointOptions(),
        }));
        if (request !== generation) return;
        acceptValidatedPreview(res?.preview);
        exclusionSummary = (res?.exclusions as SiteUnitExclusionSummary | undefined) ?? null;
      } else if (targetScope !== 'unlumped' && su !== 'USysSuTableDynamic') {
        const reviewed = await reads.track(VegetationReportService.GetVegetationWorkbookReview(contextId, JSON.stringify({ scope: targetScope })));
        if (request !== generation) return;
        if (!reviewed?.preview) throw new Error('No lumped report preview returned.');
        acceptValidatedPreview(reviewed.preview);
      } else {
        const value = await reads.track(VegetationReportService.PreviewLongVegetation(contextId));
        if (request !== generation) return;
        acceptValidatedPreview(value);
      }
    } catch (cause) {
      if (request === generation) {
        error = `Report unavailable; no data or configuration written: ${String(cause)}`;
        if (typeof notifications !== 'undefined') {
          const ctxTag = (typeof project === 'string' && project) || (typeof effectiveHierarchy === 'string' && effectiveHierarchy !== 'None' ? effectiveHierarchy : undefined) || (typeof hierarchy === 'string' && hierarchy && hierarchy !== 'None' ? hierarchy : undefined);
          notifications.error('Long Vegetation report failed', error, {
            category: 'reports',
            source: 'Long Vegetation',
            contextTag: ctxTag,
          });
        }
      }
    } finally {
      if (request === generation) { busy = false; reportBusy(); }
    }
  }
  async function reviewWorkbook() {
    if (projectActive && projectWorkspace) {
      if (workbookEnabled) await readProject(() => projectWorkspace.reviewWorkbook());
      return;
    }
    if (!workbookEnabled || busy || operationHeld || workbookBarrier || preferenceBarrier || !settings || su === 'None' || su === 'USysSuTableDynamic') return;
    cancel(); const request = generation;
    error = ''; preview = null; workbookReview = null; busy = true; reportBusy();
    try {
      const targetScope = typeof selectedWorkbookScope === 'string' && selectedWorkbookScope.trim()
        ? selectedWorkbookScope.trim() : 'unlumped';
      const value = await reads.track(VegetationReportService.GetVegetationWorkbookReview(contextId, JSON.stringify({ scope: targetScope })));
      if (request !== generation) return;
      if (!value) throw new Error('No owned workbook review returned.');
      const reviewed = workbookSession.prepare(value);
      requireLongVegetationGrouping(reviewed.preview.settings, lifeformEnabled, strataEnabled, codeEnabled, selectedFieldEnabled, noneUnitsEnabled, selectedUnitsEnabled);
      workbookReview = reviewed;
      preview = reviewed.preview;
      settings = reviewed.preview.settings;
    } catch (cause) {
      if (request === generation) {
        error = `Workbook review unavailable; no file published: ${String(cause)}`;
        if (typeof notifications !== 'undefined') {
          const ctxTag = (typeof project === 'string' && project) || (typeof effectiveHierarchy === 'string' && effectiveHierarchy !== 'None' ? effectiveHierarchy : undefined) || (typeof hierarchy === 'string' && hierarchy && hierarchy !== 'None' ? hierarchy : undefined);
          notifications.error('Long Vegetation workbook review failed', error, {
            category: 'reports',
            source: 'Long Vegetation',
            contextTag: ctxTag,
          });
        }
      }
    } finally {
      if (request === generation) { busy = false; reportBusy(); }
    }
  }
  async function publishWorkbook() {
    const ctxTag = (typeof project === 'string' && project) || (typeof effectiveHierarchy === 'string' && effectiveHierarchy !== 'None' ? effectiveHierarchy : undefined) || (typeof hierarchy === 'string' && hierarchy && hierarchy !== 'None' ? hierarchy : undefined);
    if (projectActive && projectWorkspace) {
      if (!workbookEnabled || busy || operationHeld || workbookBarrier || sharedPreferenceBarrier || !projectView?.workbookReview) return;
      error = '';
      try {
        await projectWorkspace.publishWorkbook(destination);
        if (typeof syncProjectNotifications === 'function') syncProjectNotifications();
        else if (typeof notifications !== 'undefined') {
          const settled = projectWorkspace.view?.().publication;
          const opts = { category: 'reports' as const, source: 'Long Vegetation', contextTag: ctxTag };
          if (settled?.outcome?.status === 'published' && !settled.error) notifications.success('Long Vegetation workbook exported', settled.outcome.path || settled.requestedDestination || destination, opts);
          else if (settled?.error || settled?.outcome) notifications.error('Long Vegetation workbook export failed', settled.error || `Publication ${settled.outcome?.status ?? 'failed'} for ${settled.requestedDestination || destination}`, opts);
        }
      } catch (cause) {
        error = String(cause);
        if (typeof notifications !== 'undefined') notifications.error('Long Vegetation workbook export failed', error, { category: 'reports', source: 'Long Vegetation', contextTag: ctxTag });
      }
      return;
    }
    if (!workbookEnabled || busy || operationHeld || workbookBarrier || preferenceBarrier || !workbookReview) return;
    const reviewed = workbookReview;
    cancel(); error = '';
    try {
      await workbookSession.publish(reviewed, destination, request =>
        VegetationReportService.ExportReviewedVegetationWorkbook(contextId, JSON.stringify(request)));
      if (typeof syncWorkbookNotifications === 'function') syncWorkbookNotifications();
      else if (typeof notifications !== 'undefined') {
        const s = workbookSession.view();
        const o = { category: 'reports' as const, source: 'Long Vegetation', contextTag: ctxTag };
        if (s.outcome?.status === 'published' && !s.error) notifications.success('Long Vegetation workbook exported', s.outcome.path || s.requestedDestination || destination, o);
        else if (s.error || s.outcome) notifications.error('Long Vegetation workbook export failed', s.error || `Publication ${s.outcome?.status ?? 'failed'} for ${s.requestedDestination || destination}`, o);
      }
    } catch (cause) {
      error = String(cause);
      if (typeof notifications !== 'undefined') notifications.error('Long Vegetation workbook export failed', error, { category: 'reports', source: 'Long Vegetation', contextTag: ctxTag });
    }
  }
  function acknowledgeWorkbook() {
    workbookSession.acknowledge();
    workbookReview = null;
  }
  async function loadSavedTitle() {
    if (!preferences || unitBarrier || busy || operationHeld || workbookBarrier || statisticsBarrier || switchBarrier || thresholdBarrier || groupBarrier || qualityNullBarrier || qualityMinimumBarrier || namingBarrier || selectedFieldBarrier || enforcementBarrier || preferenceView?.busy || preferenceView?.blocked) return;
    cancel(); const request = generation, token = preferences.beginLoad();
    error = ''; busy = true; reportBusy();
    try {
      const value = await reads.track(VegetationReportService.GetLongVegetationPreferences(contextId));
      if (request !== generation) return;
      preferences.applyLoaded(value, token);
    } catch (cause) {
      if (request === generation) {
        error = `Saved title unavailable; no defaults applied: ${String(cause)}`;
        if (typeof notifications !== 'undefined') {
          const ctxTag = (typeof project === 'string' && project) || (typeof effectiveHierarchy === 'string' && effectiveHierarchy !== 'None' ? effectiveHierarchy : undefined) || (typeof hierarchy === 'string' && hierarchy && hierarchy !== 'None' ? hierarchy : undefined);
          notifications.error('Long Vegetation title load failed', error, {
            category: 'reports',
            source: 'Long Vegetation',
            contextTag: ctxTag,
          });
        }
      }
    } finally {
      if (request === generation) { busy = false; reportBusy(); }
    }
  }
  async function saveTitle() {
    if (!preferences || busy || operationHeld || workbookBarrier || preferenceBarrier) return;
    cancel(); const request = generation; error = '';
    try {
      await preferences.save(value => VegetationReportService.SaveLongVegetationPreferences(contextId, JSON.stringify(value)));
      if (typeof syncPreferenceNotifications === 'function') {
        syncPreferenceNotifications();
      } else if (typeof notifications !== 'undefined') {
        const settled = preferences.view?.();
        const receipts = settled?.receipts ?? [];
        const latest = receipts[receipts.length - 1];
        const ctxTag = (typeof project === 'string' && project) || (typeof effectiveHierarchy === 'string' && effectiveHierarchy !== 'None' ? effectiveHierarchy : undefined) || (typeof hierarchy === 'string' && hierarchy && hierarchy !== 'None' ? hierarchy : undefined);
        if (latest?.kind === 'known') {
          if (latest.outcome.committed && !latest.outcome.errorMessage) {
            notifications.success('Long Vegetation title saved', latest.outcome.changed ? 'Saved report title preference.' : 'No title changes.', {
              category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
            });
          } else if (latest.outcome.committed) {
            notifications.warning('Long Vegetation title saved with warning', latest.outcome.errorMessage, {
              category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
            });
          } else if (latest.outcome.errorMessage) {
            notifications.error('Long Vegetation title save failed', latest.outcome.errorMessage, {
              category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
            });
          }
        } else if (settled?.error) {
          notifications.error('Long Vegetation title preference failed', settled.error, {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
        }
      }
    } catch (cause) {
      if (request === generation) {
        error = String(cause);
        if (typeof notifications !== 'undefined') {
          const ctxTag = (typeof project === 'string' && project) || (typeof effectiveHierarchy === 'string' && effectiveHierarchy !== 'None' ? effectiveHierarchy : undefined) || (typeof hierarchy === 'string' && hierarchy && hierarchy !== 'None' ? hierarchy : undefined);
          notifications.error('Long Vegetation title save failed', error, {
            category: 'reports',
            source: 'Long Vegetation',
            contextTag: ctxTag,
          });
        }
      }
    }
  }
  function editTitle(value: string) {
    if (!preferences || unitMutationHeld) return;
    cancel(); error = ''; preferences.edit(value);
  }
  async function loadSavedStatistics() {
    if (!statistics || unitBarrier || busy || operationHeld || workbookBarrier || titleBarrier || switchBarrier || thresholdBarrier || groupBarrier || qualityNullBarrier || qualityMinimumBarrier || namingBarrier || selectedFieldBarrier || enforcementBarrier || statisticsView?.busy || statisticsView?.blocked) return;
    cancel(); const request = generation, token = statistics.beginLoad();
    error = ''; busy = true; reportBusy();
    try {
      const value = await reads.track(VegetationReportService.GetLongVegetationStatisticsPreferences(contextId));
      if (request !== generation) return;
      statistics.applyLoaded(value, token);
    } catch (cause) {
      if (request === generation) {
        error = `Saved Average/Order choices unavailable; no defaults applied: ${String(cause)}`;
        if (typeof notifications !== 'undefined') {
          const ctxTag = (typeof project === 'string' && project) || (typeof effectiveHierarchy === 'string' && effectiveHierarchy !== 'None' ? effectiveHierarchy : undefined) || (typeof hierarchy === 'string' && hierarchy && hierarchy !== 'None' ? hierarchy : undefined);
          notifications.error('Long Vegetation statistics load failed', error, {
            category: 'reports',
            source: 'Long Vegetation',
            contextTag: ctxTag,
          });
        }
      }
    } finally {
      if (request === generation) { busy = false; reportBusy(); }
    }
  }
  async function saveStatistics() {
    if (!statistics || busy || operationHeld || workbookBarrier || preferenceBarrier) return;
    cancel(); const request = generation; error = '';
    try {
      await statistics.save(value => VegetationReportService.SaveLongVegetationStatisticsPreferences(contextId, JSON.stringify(value)));
      if (typeof syncStatisticsNotifications === 'function') {
        syncStatisticsNotifications();
      } else if (typeof notifications !== 'undefined') {
        const settled = statistics.view?.();
        const receipts = settled?.receipts ?? [];
        const latest = receipts[receipts.length - 1];
        const ctxTag = (typeof project === 'string' && project) || (typeof effectiveHierarchy === 'string' && effectiveHierarchy !== 'None' ? effectiveHierarchy : undefined) || (typeof hierarchy === 'string' && hierarchy && hierarchy !== 'None' ? hierarchy : undefined);
        if (latest?.kind === 'known') {
          if (latest.outcome.committed && !latest.outcome.errorMessage) {
            notifications.success('Long Vegetation Average/Order saved', latest.outcome.changed ? 'Saved Average/Order preferences.' : 'No Average/Order changes.', {
              category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
            });
          } else if (latest.outcome.committed) {
            notifications.warning('Long Vegetation Average/Order saved with warning', latest.outcome.errorMessage, {
              category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
            });
          } else if (latest.outcome.errorMessage) {
            notifications.error('Long Vegetation Average/Order save failed', latest.outcome.errorMessage, {
              category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
            });
          }
        } else if (settled?.error) {
          notifications.error('Long Vegetation Average/Order preference failed', settled.error, {
            category: 'reports', source: 'Long Vegetation', contextTag: ctxTag,
          });
        }
      }
    } catch (cause) {
      if (request === generation) {
        error = String(cause);
        if (typeof notifications !== 'undefined') {
          const ctxTag = (typeof project === 'string' && project) || (typeof effectiveHierarchy === 'string' && effectiveHierarchy !== 'None' ? effectiveHierarchy : undefined) || (typeof hierarchy === 'string' && hierarchy && hierarchy !== 'None' ? hierarchy : undefined);
          notifications.error('Long Vegetation statistics save failed', error, {
            category: 'reports',
            source: 'Long Vegetation',
            contextTag: ctxTag,
          });
        }
      }
    }
  }
  function editAverage(value: string) {
    if (!statistics || unitMutationHeld) return;
    cancel(); error = ''; statistics.editAverage(value);
  }
  function editOrder(value: string) {
    if (!statistics || unitMutationHeld) return;
    cancel(); error = ''; statistics.editOrder(value);
  }
  const numberText = (value: number | null) => value === null ? 'NULL' : String(value);
  const presenceText = (value: number | null) => value === null ? 'NULL' : `${value * 100}%`;
  const supplementaryText = (cell: ProjectMetadataCell) => preview?.report.selectedFieldType === 'boolean' && cell.storage !== 'null'
    ? cell.integer === '-1' ? 'TRUE' : 'FALSE' : reportCellText(cell);
  onMount(() => {
    void loadLumpTables();
    if (projectWorkspace) void projectWorkspace.selection.load().then(() => {
      if (disposed) return;
      if (projectWorkspace.view().scope.scope?.sourceKind === 'selected-list' && su && su !== 'None') void options();
    }).catch(cause => {
      if (disposed) return;
      error = `Owned report scope unavailable: ${String(cause)}`;
      if (typeof notifications !== 'undefined') {
        const ctxTag = (typeof project === 'string' && project) || (typeof effectiveHierarchy === 'string' && effectiveHierarchy !== 'None' ? effectiveHierarchy : undefined) || (typeof hierarchy === 'string' && hierarchy && hierarchy !== 'None' ? hierarchy : undefined);
        notifications.error('Long Vegetation scope load failed', error, {
          category: 'reports',
          source: 'Long Vegetation',
          contextTag: ctxTag,
        });
      }
    });
    else if (su && su !== 'None') void options();
  });
  onDestroy(() => {
    disposed = true;
    unsubscribeWorkbook(); unsubscribePreferences?.(); unsubscribeStatistics?.(); unsubscribeSwitches?.();
    unsubscribeThresholds?.(); unsubscribeGroups?.(); unsubscribeQualityNulls?.(); unsubscribeQualityMinima?.();
    unsubscribeNaming?.(); unsubscribeSelectedField?.(); unsubscribeEnforcement?.(); unsubscribeUnits?.(); unsubscribeProject?.();
    projectWorkspace?.cancelScopeReads(); projectWorkspace?.selection.cancel();
    projectWorkspace?.cancelUnitReads(); projectWorkspace?.units.cancelRead(); cancel();
  });
</script>

<section class="report" data-long-vegetation-report aria-label="Long Vegetation report">
  <header class="sticky top-0 z-20 bg-white/95 backdrop-blur-xs py-2 border-b border-vpro-border report-sticky-bar" data-report-sticky-bar>
    <h1>Long Vegetation</h1>
    <div class="actions">
      <button data-source-control="btnViewReport" disabled={busy || operationHeld || workbookBarrier || preferenceBarrier || (projectActive ? !projectView?.outputReady : !settings || su === 'None')} onclick={show}>View Report</button>
      <button disabled={busy || operationHeld || workbookBarrier || preferenceBarrier || (projectActive ? !projectView?.outputReady : !su || su === 'None')} onclick={options}>Reload report options</button>
      {#if workbookEnabled}
        <button disabled={busy || operationHeld || workbookBarrier || preferenceBarrier || (projectActive ? !projectView?.outputReady : !settings || su === 'None' || su === 'USysSuTableDynamic')} onclick={reviewWorkbook}>
          {selectedWorkbookScope === 'unlumped' ? 'Review unlumped XLSX workbook (no file yet)' : `Review ${selectedWorkbookScope.replace(/^lump:/, '')} XLSX workbook (no file yet)`}
        </button>
      {/if}
      {#if busy || projectView?.readBusy}<button onclick={cancel}>Cancel report read</button>{/if}
      {#if projectView?.readBusy}<button data-project-report-cancel onclick={() => projectWorkspace?.cancelReportRead()}>Cancel original project report read</button>{/if}
    </div>
  </header>
  {#if su === 'None' && !projectActive}
    <p class="scope-guidance" role="status">{projectWorkspace ? 'Select an SU in Projects & context, or choose an explicit available whole-project scope before viewing the report.' :
      'Select an SU in Projects & context before viewing the report.'}</p>
  {/if}
  {#if preferenceView?.draftError}<p class="error" role="alert">{preferenceView.draftError}</p>{/if}
  {#if statisticsView?.draftError}<p class="error" role="alert">{statisticsView.draftError}</p>{/if}
  {#if !publication.outcome && publication.requestedDestination && !publication.busy}
    <p data-vegetation-workbook-unknown role="alert">Workbook outcome unknown. Retain and inspect {publication.requestedDestination}; never replay blindly.</p>
  {/if}
  {#if publication.blocked && !publication.busy}
    <button onclick={acknowledgeWorkbook}>Acknowledge workbook outcome</button>
  {/if}
  {#if projectWorkspace && projectView && projectScopeSelection}
    {#if !projectView.publication?.outcome && projectView.publication?.requestedDestination && !projectView.publication.busy}
      <p data-project-workbook-unknown role="alert">Original project workbook outcome unknown.
        Retain and inspect {projectView.publication.requestedDestination}; never replay blindly.</p>
    {/if}
    {#if projectView.publication?.blocked && !projectView.publication.busy}
      <button data-project-workbook-acknowledge disabled={busy || operationHeld || sharedMutationHeld || publication.busy || publication.blocked}
        onclick={() => projectWorkspace.workbook?.acknowledge()}>Acknowledge original project workbook outcome</button>
    {/if}
    <LongVegetationProjectScopeSelection selection={projectScopeSelection} allPlotsAvailable={su === 'None'}
      cancelReads={() => projectWorkspace.cancelScopeReads()} onChange={projectChanged}
      operationHeld={busy || operationHeld || workbookBarrier || sharedPreferenceBarrier || projectView.scopeOperationHeld}
      mutationHeld={busy || operationHeld || workbookBarrier || sharedMutationHeld || projectView.scopeMutationHeld} />
    {#if projectActive}
      <LongVegetationProjectUnitPreferences preferences={projectWorkspace.units}
        fetchPreferences={projectWorkspace.fetchUnitPreferences} savePreferences={projectWorkspace.saveUnitPreferences}
        cancelReads={() => projectWorkspace.cancelUnitReads()} onChange={projectChanged}
        operationHeld={busy || operationHeld || workbookBarrier || sharedPreferenceBarrier || projectView.unitOperationHeld}
        mutationHeld={busy || operationHeld || workbookBarrier || sharedMutationHeld || projectView.unitMutationHeld} />
    {/if}
  {/if}
  {#if preferences && preferenceView}
    <section class="preferences" aria-label="Saved Long Vegetation title">
      <label for="long-vegetation-title">Report Title</label>
      <textarea id="long-vegetation-title" data-source-control="rptLvTitle" rows="2"
        value={preferenceView.draft.title} aria-invalid={!!preferenceView.draftError}
        disabled={unitMutationHeld || busy || operationHeld || workbookBarrier || switchMutationHeld || thresholdMutationHeld || groupMutationHeld || qualityNullMutationHeld || qualityMinimumMutationHeld || namingMutationHeld || selectedFieldMutationHeld || enforcementMutationHeld || statisticsView?.busy || statisticsView?.blocked || preferenceView.busy || preferenceView.blocked || !preferenceView.initialized}
        oninput={event => { const value = event.currentTarget.value; editTitle(value); }}></textarea>
      <div class="actions">
        <button data-long-vegetation-preferences-load
          disabled={unitBarrier || busy || operationHeld || workbookBarrier || statisticsBarrier || switchBarrier || thresholdBarrier || groupBarrier || qualityNullBarrier || qualityMinimumBarrier || namingBarrier || selectedFieldBarrier || enforcementBarrier || preferenceView.busy || preferenceView.blocked}
          onclick={loadSavedTitle}>Load saved title</button>
        <button data-long-vegetation-preferences-save
          disabled={busy || operationHeld || workbookBarrier || preferenceBarrier || !preferenceView.saved}
          onclick={saveTitle}>Save title preferences</button>
        <button data-long-vegetation-preferences-undo
          disabled={unitMutationHeld || busy || operationHeld || workbookBarrier || switchMutationHeld || thresholdMutationHeld || groupMutationHeld || qualityNullMutationHeld || qualityMinimumMutationHeld || namingMutationHeld || selectedFieldMutationHeld || enforcementMutationHeld || statisticsView?.busy || statisticsView?.blocked || preferenceView.busy || preferenceView.blocked || !preferenceView.saved}
          onclick={() => { cancel(); preferences.undo(); }}>Undo title draft</button>
        {#if preferenceView.blocked && !preferenceView.busy}
          <button data-long-vegetation-preferences-acknowledge disabled={unitMutationHeld || busy || operationHeld || workbookBarrier || thresholdMutationHeld || groupMutationHeld || qualityNullMutationHeld || qualityMinimumMutationHeld || namingMutationHeld || selectedFieldMutationHeld || enforcementMutationHeld}
            onclick={() => preferences.acknowledge()}>Acknowledge title preference outcome</button>
        {/if}
      </div>
      {#each preferenceView.receipts as receipt}
        {#if receipt.kind !== 'known'}
          <p data-long-vegetation-preferences-receipt role="alert">Preference receipt: outcome unknown; changed unknown; committed unknown.
            {receipt.errorMessage}</p>
        {/if}
      {/each}
      <p class="guidance">Drafts do not change report output. Save explicitly, acknowledge the outcome, then reload report options.
        Acknowledgement retains receipts; an unknown outcome requires an explicit owned Load, never blind Save replay.
        No registry, project data or source audits are written.</p>
    </section>
  {/if}
  {#if statistics && statisticsView}
    <section class="preferences" aria-label="Saved Long Vegetation Average and Order">
      <label for="long-vegetation-average">Calculate</label>
      <select id="long-vegetation-average" data-source-control="rptLvAvgType" value={statisticsView.draft.avgType}
        aria-invalid={!!statisticsView.draftError}
        disabled={unitMutationHeld || busy || operationHeld || workbookBarrier || switchMutationHeld || thresholdMutationHeld || groupMutationHeld || qualityNullMutationHeld || qualityMinimumMutationHeld || namingMutationHeld || selectedFieldMutationHeld || enforcementMutationHeld || preferenceView?.busy || preferenceView?.blocked || statisticsView.busy || statisticsView.blocked || !statisticsView.initialized}
        onchange={event => { const value = event.currentTarget.value; editAverage(value); }}>
        <option value="" disabled>Load saved Average</option>
        <option value="10">By n Plots</option><option value="20">Characteristic</option>
      </select>
      <label for="long-vegetation-order">Order by</label>
      <select id="long-vegetation-order" data-source-control="rptLvOrderBy" value={statisticsView.draft.orderBy}
        aria-invalid={!!statisticsView.draftError}
        disabled={unitMutationHeld || busy || operationHeld || workbookBarrier || switchMutationHeld || thresholdMutationHeld || groupMutationHeld || qualityNullMutationHeld || qualityMinimumMutationHeld || namingMutationHeld || selectedFieldMutationHeld || enforcementMutationHeld || preferenceView?.busy || preferenceView?.blocked || statisticsView.busy || statisticsView.blocked || !statisticsView.initialized}
        onchange={event => { const value = event.currentTarget.value; editOrder(value); }}>
        <option value="" disabled>Load saved Order by</option>
        <option value="10">Species</option><option value="20">Presence</option>
      </select>
      <div class="actions">
        <button data-long-vegetation-statistics-load
          disabled={unitBarrier || busy || operationHeld || workbookBarrier || titleBarrier || switchBarrier || thresholdBarrier || groupBarrier || qualityNullBarrier || qualityMinimumBarrier || namingBarrier || selectedFieldBarrier || enforcementBarrier || statisticsView.busy || statisticsView.blocked}
          onclick={loadSavedStatistics}>Load saved Average/Order</button>
        <button data-long-vegetation-statistics-save
          disabled={busy || operationHeld || workbookBarrier || preferenceBarrier || !statisticsView.saved}
          onclick={saveStatistics}>Save Average/Order preferences</button>
        <button data-long-vegetation-statistics-undo
          disabled={unitMutationHeld || busy || operationHeld || workbookBarrier || switchMutationHeld || thresholdMutationHeld || groupMutationHeld || qualityNullMutationHeld || qualityMinimumMutationHeld || namingMutationHeld || selectedFieldMutationHeld || enforcementMutationHeld || preferenceView?.busy || preferenceView?.blocked || statisticsView.busy || statisticsView.blocked || !statisticsView.saved}
          onclick={() => { cancel(); statistics.undo(); }}>Undo Average/Order draft</button>
        {#if statisticsView.blocked && !statisticsView.busy}
          <button data-long-vegetation-statistics-acknowledge disabled={unitMutationHeld || busy || operationHeld || workbookBarrier || thresholdMutationHeld || groupMutationHeld || qualityNullMutationHeld || qualityMinimumMutationHeld || namingMutationHeld || selectedFieldMutationHeld || enforcementMutationHeld}
            onclick={() => statistics.acknowledge()}>Acknowledge Average/Order outcome</button>
        {/if}
      </div>
      {#each statisticsView.receipts as receipt}
        {#if receipt.kind !== 'known'}
          <p data-long-vegetation-statistics-receipt role="alert">
            Preference receipt: outcome unknown; changed unknown; committed unknown. {receipt.errorMessage}
          </p>
        {/if}
      {/each}
      <p class="guidance">Drafts do not change report output. Save explicitly, acknowledge the outcome, then reload report options.
        Only the two saved source choices are changed; no registry, project data or source audits are written.</p>
    </section>
  {/if}
  {#if switches}
    <LongVegetationSwitchPreferences contextId={contextId} preferences={switches}
      operationHeld={unitBarrier || busy || operationHeld || workbookBarrier || titleBarrier || statisticsBarrier || thresholdBarrier || groupBarrier || qualityNullBarrier || qualityMinimumBarrier || namingBarrier || selectedFieldBarrier || enforcementBarrier}
      mutationHeld={unitMutationHeld || busy || operationHeld || workbookBarrier || !!preferenceView?.busy || !!preferenceView?.blocked ||
        !!statisticsView?.busy || !!statisticsView?.blocked || thresholdMutationHeld || groupMutationHeld || qualityNullMutationHeld || qualityMinimumMutationHeld || namingMutationHeld || selectedFieldMutationHeld || enforcementMutationHeld}
      onReadBusyChange={value => { switchReadBusy = value; reportBusy(); }} />
  {/if}
  {#if thresholds}
    <LongVegetationThresholdPreferences contextId={contextId} preferences={thresholds}
      operationHeld={unitBarrier || busy || operationHeld || workbookBarrier || titleBarrier || statisticsBarrier || switchBarrier || groupBarrier || qualityNullBarrier || qualityMinimumBarrier || namingBarrier || selectedFieldBarrier || enforcementBarrier}
      mutationHeld={unitMutationHeld || busy || operationHeld || workbookBarrier || !!preferenceView?.busy || !!preferenceView?.blocked ||
        !!statisticsView?.busy || !!statisticsView?.blocked || switchMutationHeld || groupMutationHeld || qualityNullMutationHeld || qualityMinimumMutationHeld || namingMutationHeld || selectedFieldMutationHeld || enforcementMutationHeld}
      onReadBusyChange={value => { thresholdReadBusy = value; reportBusy(); }} />
  {/if}
  {#if groups}
    <LongVegetationGroupPreferences contextId={contextId} preferences={groups}
      operationHeld={unitBarrier || busy || operationHeld || workbookBarrier || titleBarrier || statisticsBarrier || switchBarrier || thresholdBarrier || qualityNullBarrier || qualityMinimumBarrier || namingBarrier || selectedFieldBarrier || enforcementBarrier}
      mutationHeld={unitMutationHeld || busy || operationHeld || workbookBarrier || !!preferenceView?.busy || !!preferenceView?.blocked ||
        !!statisticsView?.busy || !!statisticsView?.blocked || switchMutationHeld || thresholdMutationHeld || qualityNullMutationHeld || qualityMinimumMutationHeld || namingMutationHeld || selectedFieldMutationHeld || enforcementMutationHeld}
      onReadBusyChange={value => { groupReadBusy = value; reportBusy(); }} />
  {/if}
  {#if qualityNulls}
    <LongVegetationQualityNullPreferences contextId={contextId} preferences={qualityNulls}
      operationHeld={unitBarrier || busy || operationHeld || workbookBarrier || titleBarrier || statisticsBarrier || switchBarrier || thresholdBarrier || groupBarrier || qualityMinimumBarrier || namingBarrier || selectedFieldBarrier || enforcementBarrier}
      mutationHeld={unitMutationHeld || busy || operationHeld || workbookBarrier || !!preferenceView?.busy || !!preferenceView?.blocked ||
        !!statisticsView?.busy || !!statisticsView?.blocked || switchMutationHeld || thresholdMutationHeld || groupMutationHeld || qualityMinimumMutationHeld || namingMutationHeld || selectedFieldMutationHeld || enforcementMutationHeld}
      onReadBusyChange={value => { qualityNullReadBusy = value; reportBusy(); }} />
  {/if}
  {#if qualityMinima}
    <LongVegetationQualityMinimumPreferences contextId={contextId} preferences={qualityMinima}
      operationHeld={unitBarrier || busy || operationHeld || workbookBarrier || titleBarrier || statisticsBarrier || switchBarrier || thresholdBarrier || groupBarrier || qualityNullBarrier || namingBarrier || selectedFieldBarrier || enforcementBarrier}
      mutationHeld={unitMutationHeld || busy || operationHeld || workbookBarrier || !!preferenceView?.busy || !!preferenceView?.blocked ||
        !!statisticsView?.busy || !!statisticsView?.blocked || switchMutationHeld || thresholdMutationHeld || groupMutationHeld || qualityNullMutationHeld || namingMutationHeld || selectedFieldMutationHeld || enforcementMutationHeld}
      onReadBusyChange={value => { qualityMinimumReadBusy = value; reportBusy(); }} />
  {/if}
  {#if naming}
    <LongVegetationNamingPreferences contextId={contextId} preferences={naming} selectedFieldEnabled={selectedFieldEnabled}
      operationHeld={unitBarrier || busy || operationHeld || workbookBarrier || titleBarrier || statisticsBarrier || switchBarrier || thresholdBarrier || groupBarrier || qualityNullBarrier || qualityMinimumBarrier || selectedFieldBarrier || enforcementBarrier}
      mutationHeld={unitMutationHeld || busy || operationHeld || workbookBarrier || !!preferenceView?.busy || !!preferenceView?.blocked ||
        !!statisticsView?.busy || !!statisticsView?.blocked || switchMutationHeld || thresholdMutationHeld || groupMutationHeld || qualityNullMutationHeld || qualityMinimumMutationHeld || selectedFieldMutationHeld || enforcementMutationHeld}
      onReadBusyChange={value => { namingReadBusy = value; reportBusy(); }} />
  {/if}
  {#if selectedField}
    <LongVegetationSelectedFieldPreferences contextId={contextId} preferences={selectedField}
      operationHeld={unitBarrier || busy || operationHeld || workbookBarrier || titleBarrier || statisticsBarrier || switchBarrier || thresholdBarrier || groupBarrier || qualityNullBarrier || qualityMinimumBarrier || namingBarrier || enforcementBarrier}
      mutationHeld={unitMutationHeld || busy || operationHeld || workbookBarrier || !!preferenceView?.busy || !!preferenceView?.blocked ||
        !!statisticsView?.busy || !!statisticsView?.blocked || switchMutationHeld || thresholdMutationHeld || groupMutationHeld || qualityNullMutationHeld || qualityMinimumMutationHeld || namingMutationHeld || enforcementMutationHeld}
      onReadBusyChange={value => { selectedFieldReadBusy = value; reportBusy(); }} />
  {/if}
  {#if enforcement}
    <LongVegetationEnforcementPreferences contextId={contextId} preferences={enforcement}
      operationHeld={unitBarrier || busy || operationHeld || workbookBarrier || titleBarrier || statisticsBarrier || switchBarrier || thresholdBarrier || groupBarrier || qualityNullBarrier || qualityMinimumBarrier || namingBarrier || selectedFieldBarrier}
      mutationHeld={unitMutationHeld || busy || operationHeld || workbookBarrier || !!preferenceView?.busy || !!preferenceView?.blocked ||
        !!statisticsView?.busy || !!statisticsView?.blocked || switchMutationHeld || thresholdMutationHeld || groupMutationHeld || qualityNullMutationHeld || qualityMinimumMutationHeld || namingMutationHeld || selectedFieldMutationHeld}
      onReadBusyChange={value => { enforcementReadBusy = value; reportBusy(); }} />
  {/if}
  {#if units && (!projectActive && projectScopeKnown || unitReadBusy || unitView?.busy || unitView?.blocked || unitView?.authorityUnknown)}
    <LongVegetationUnitPreferences contextId={contextId} preferences={units}
      operationHeld={projectBarrier || selectedUnitBarrier || busy || operationHeld || workbookBarrier || titleBarrier || statisticsBarrier || switchBarrier || thresholdBarrier || groupBarrier || qualityNullBarrier || qualityMinimumBarrier || namingBarrier || selectedFieldBarrier || enforcementBarrier}
      mutationHeld={projectMutationHeld || selectedUnitMutationHeld || busy || operationHeld || workbookBarrier || !!preferenceView?.busy || !!preferenceView?.blocked ||
        !!statisticsView?.busy || !!statisticsView?.blocked || switchMutationHeld || thresholdMutationHeld || groupMutationHeld || qualityNullMutationHeld || qualityMinimumMutationHeld || namingMutationHeld || selectedFieldMutationHeld || enforcementMutationHeld}
      onReadBusyChange={value => { unitReadBusy = value; reportBusy(); }} />
  {/if}
  {#if selectedUnitSelection && (!projectActive && projectScopeKnown || selectedUnitBarrier)}
    <LongVegetationSelectedUnitSelection contextId={contextId} selection={selectedUnitSelection}
      operationHeld={projectBarrier || unitReadBusy || !!unitView && (unitView.busy || unitView.blocked || !!unitView.draftError) ||
        busy || operationHeld || workbookBarrier || titleBarrier || statisticsBarrier || switchBarrier || thresholdBarrier ||
        groupBarrier || qualityNullBarrier || qualityMinimumBarrier || namingBarrier || selectedFieldBarrier || enforcementBarrier}
      mutationHeld={projectMutationHeld || unitReadBusy || !!unitView && (unitView.busy || unitView.blocked) ||
        busy || operationHeld || workbookBarrier || !!preferenceView?.busy || !!preferenceView?.blocked ||
        !!statisticsView?.busy || !!statisticsView?.blocked || switchMutationHeld || thresholdMutationHeld ||
        groupMutationHeld || qualityNullMutationHeld || qualityMinimumMutationHeld || namingMutationHeld ||
        selectedFieldMutationHeld || enforcementMutationHeld}
      onChange={selectedUnitChanged} />
  {/if}
  <p>Project {project}; selected SU {su}.
    {projectActive ? 'Explicit original whole-project scope; current SU is retained only for original quality authority when requested.' :
      'Whole selected-SU scope; the current plot and profile navigation do not filter this report.'}</p>
  <dl class="scope">
    <div><dt>Project database</dt><dd>{projectPath}</dd></div>
    <div><dt>Selected SU database</dt><dd>{suPath || 'No selected SU'}</dd></div>
  </dl>
  {#if settings}
    <dl class="settings" aria-label="Read-only report options">
      <div><dt>Report Title</dt><dd data-source-control="rptLvTitle">{settings.title === '' ? '"" (empty title)' : settings.title}</dd></div>
      <div><dt>Group by</dt><dd>{settings.grouping === 'none' ? 'None (source layer observations retained)' : groupLabel}</dd></div>
      <div><dt>Average</dt><dd>{settings.average === 'all-plots' ? (projectActive ? 'By n Plots — original project tuple denominator; quality filters by plot existence' : settings.unitGrouping === 'all-plots' ? 'By n Plots — joined sum / derived Env/current-list denominator' : settings.unitGrouping === 'selected-fields' ? 'By n Plots — joined sum / derived selected-field denominator' : settings.quality ? 'By n Plots — joined sum / qualified SU denominator' : 'By n Plots — joined sum / physical SU denominator') : 'Characteristic — mean of joined non-NULL observations'}</dd></div>
      <div><dt>Report units</dt><dd data-source-control="rptLvUnitGroups">{settings.unitGrouping === 'all-plots' ? (projectActive ? 'None — All plots from original Env rows' : 'None — All plots from Env/current selected list joins') : settings.unitGrouping === 'selected-fields' ? `Selected fields — ${settings.unitFields!.join(' & ')} (no separator)` : 'Site unit table — selected SU'}</dd></div>
      <div><dt>Constant species list</dt><dd>{settings.constantSpeciesList ? (projectActive ? 'On — same original project list; thresholds bypassed' : 'On — same selected-SU list; thresholds bypassed') : 'Off — strict presence and mean-cover thresholds apply'}</dd></div>
      <div><dt>Show species with presence &gt; than</dt><dd>{settings.presenceGreaterThan}%{settings.constantSpeciesList ? ' (not applied)' : ''}</dd></div>
      <div><dt>Show species with mean cover &gt; than</dt><dd>{settings.meanCoverGreaterThan}%{settings.constantSpeciesList ? ' (not applied)' : ''}</dd></div>
      <div><dt>Order by</dt><dd>{settings.constantSpeciesList ? `${groupLabel}, then species (constant-list source order)` :
        settings.grouping === 'none' ? (settings.order === 'presence' ? 'Descending presence, then species' : 'Species') :
        settings.order === 'presence' ? `${groupLabel}, then descending presence` : `${groupLabel}, then species`}</dd></div>
      <div><dt>{settings.selectedField !== undefined ? 'Show selected field' : settings.showSpeciesCode ? 'Show 8 char. code' : 'English names'}</dt><dd>{settings.selectedField !== undefined ?
        `${JSON.stringify(settings.selectedField)} — typed list and matched report scalars shown separately` : settings.showSpeciesCode ?
        'List and matched master codes shown separately; literal values are not truncated' :
        settings.showEnglishName ? 'List and matched report names shown separately' : 'Not shown'}</dd></div>
      <div><dt>Plot-quality filter</dt><dd data-source-control="optEnforceQC">{settings.quality ? (projectActive ? 'On — original-SU qualification; original project tuples retained by plot existence' : 'On — selected-SU qualification') : projectActive ? 'Off — original project tuples' : 'Off — all physical selected-SU memberships'}</dd></div>
      {#if settings.quality}
        {#each [{label:'Site',field:'SitePlotQuality',value:settings.quality.site},
          {label:'Vegetation',field:'VegPlotQuality',value:settings.quality.veg},
          {label:'Soil',field:'SoilPlotQuality',value:settings.quality.soil}] as criterion}
          <div><dt>{criterion.label} quality minimum</dt><dd data-source-control={criterion.field}>{JSON.stringify(criterion.value.minimum)}; include NULL/missing rank: {criterion.value.includeNull ? 'Yes' : 'No'}</dd></div>
        {/each}
      {/if}
    </dl>
  {/if}
  <div class="lump-and-variant-controls" aria-label="Lump table and species variant controls">
    <div class="control-field">
      <label for="long-vegetation-lump-scope">Species Lump Table (<code>LVLumpTable</code> / workbook scope)</label>
      <div class="lump-picker-row">
        <select
          id="long-vegetation-lump-scope"
          data-source-control="rptLvLumpTable"
          disabled={busy || operationHeld || workbookBarrier || preferenceBarrier || projectActive}
          value={selectedWorkbookScope}
          onchange={(e) => {
            selectedScopeOverridden = true;
            selectedWorkbookScope = (e.currentTarget as HTMLSelectElement).value;
            invalidateReports();
          }}
        >
          <option value="unlumped">None (unlumped)</option>
          {#each lumpTables as table}
            <option value={`lump:${table}`}>{table}</option>
          {/each}
        </select>
        <button
          type="button"
          disabled={busy || operationHeld || projectActive}
          onclick={loadLumpTables}
        >Refresh Lump Tables</button>
      </div>
    </div>
    <label class="toggle-field">
      <input
        id="long-vegetation-combine-variants"
        data-source-control="LVUseSppCodesOnly"
        type="checkbox"
        checked={useSppCodesOnly}
        disabled={busy || operationHeld || workbookBarrier || preferenceBarrier}
        onchange={(e) => {
          useSppCodesOnlyOverridden = true;
          useSppCodesOnly = (e.currentTarget as HTMLInputElement).checked;
        }}
      />
      <span>Combine species variants / subspecies (<code>LVUseSppCodesOnly</code>){settings?.combineVariants ? ' — active in backend options' : ''}</span>
    </label>
    <label class="toggle-field">
      <input
        id="long-vegetation-apply-exclusions"
        type="checkbox"
        checked={applyExclusionsToReport}
        disabled={busy || operationHeld || workbookBarrier || preferenceBarrier || projectActive}
        onchange={(e) => {
          applyExclusionsToReport = (e.currentTarget as HTMLInputElement).checked;
          invalidateReports();
        }}
      />
      <span>Apply active unit exclusions / hierarchy breakpoints (<code>~</code>) on View Report</span>
    </label>
  </div>
  <details class="exclusion-panel">
    <summary>Site Unit Exclusions &amp; Hierarchy Breakpoints (~)</summary>
    <SiteUnitExclusionFilter
      {contextId}
      {su}
      hierarchy={effectiveHierarchy}
      reportMode="long"
      onRulesChange={(nextRules, nextUseBP, nextBPOpts) => {
        exclusionRules = nextRules.map(rule => ({ ...rule }));
        useHierarchyBreakpoints = nextUseBP;
        breakpointOptions = { ...nextBPOpts };
        if (nextUseBP || applyExclusionsToReport) invalidateReports();
      }}
      onLongPreview={(res) => {
        if (!res?.preview) return;
        try {
          acceptValidatedPreview(res.preview);
          exclusionSummary = res.exclusions ?? null;
          error = '';
        } catch (cause) {
          error = `Exclusion preview unavailable: ${String(cause)}`;
          if (typeof notifications !== 'undefined') {
            notifications.error('Long Vegetation exclusion preview failed', error, {
              category: 'reports',
              source: 'Long Vegetation',
              contextTag: resolveContextTag(),
            });
          }
        }
      }}
    />
  </details>
  {#if exclusionSummary && exclusionSummary.excludedUnits?.length}
    <p class="notice" role="status">
      Exclusion filter active: {exclusionSummary.excludedUnits.length} site units excluded ({exclusionSummary.excludedPlots} plots), {exclusionSummary.retainedPlots} plots retained.
    </p>
  {/if}
  {#if activeWorkbookReview}
    {@const reviewed = activeWorkbookReview}
    <section class="workbook" aria-label="Reviewed workbook">
      <h2>Reviewed workbook — explicit {reviewed.scope ?? 'unlumped'} scope</h2>
      <dl class="settings">
        <div><dt>Reviewed creation date</dt><dd>{reviewed.createdDate} (reused at publication)</dd></div>
        <div><dt>Quick report</dt><dd>{reviewed.options.quickReport ? 'On' : 'Off — source print layout retained'}</dd></div>
        <div><dt>Space between groups</dt><dd>{reviewed.options.spaceBetweenGroups ? 'On' : 'Off'}</dd></div>
        <div><dt>Report summary</dt><dd>{reviewed.options.reportSummary ? 'On' : 'Off'}</dd></div>
        <div><dt>Reviewed bytes</dt><dd>{reviewed.bytes}; SHA256 {reviewed.workbookSHA256}</dd></div>
        <div><dt>Source approval</dt><dd>{reviewed.approvalHash}</dd></div>
      </dl>
      <ul>{#each reviewed.sheets as sheet}<li>Unit {reportCellText(sheet.unit)} → worksheet “{sheet.name}”</li>{/each}</ul>
      {#each reviewed.skippedUnits as skipped}<p>Skipped unit {reportCellText(skipped.unit)}: {skipped.reason}.</p>{/each}
      {#if reviewed.summary}
        <p>ReportSummary: original Env rows {reviewed.summary.environmentRows};
          {#if 'sourcePlotRows' in reviewed.summary}
            original project non-NULL plot tuples {reviewed.summary.sourcePlotRows}.
            D:E original project tuples are an explicit desktop adaptation of the source's separate current-SU summary.
          {:else}
            {reviewed.preview.settings.unitGrouping === 'selected-fields' ? 'derived selected-field join rows (quality filters by plot existence)' :
              reviewed.preview.settings.unitGrouping === 'all-plots' ? 'derived Env/current-list join rows' :
              reviewed.preview.report.quality ? 'qualified weighted join occurrences' : 'non-NULL selected-SU PlotNumber rows'} {reviewed.summary.selectedPlotRows}.
          {/if}
          AllSpecs version {reportCellText(reviewed.summary.speciesVersion)}; metadata status {reviewed.summary.versionStatus}.</p>
        <details><summary>Original AllSpecs Description definitions</summary>
          {#each reviewed.summary.versionDefinitions.rows ?? [] as row}
            <p>Physical row {row.rowId}: {row.cells?.map(reportCellText).join('; ')}</p>
          {:else}<p>No Description definitions; absence remains distinct from NULL or empty text.</p>{/each}
        </details>
      {/if}
      <label for="vegetation-workbook-destination">New XLSX output file (existing files are never replaced)</label>
      <textarea id="vegetation-workbook-destination" rows="2" disabled={busy || operationHeld || workbookBarrier || preferenceBarrier} bind:value={destination}></textarea>
      <button disabled={busy || operationHeld || workbookBarrier || preferenceBarrier || !destination || !/\.xlsx$/i.test(destination)} onclick={publishWorkbook}>{typeof reviewed.scope === 'string' && reviewed.scope !== 'unlumped' ? `Publish reviewed ${reviewed.scope.replace(/^lump:/, '')} XLSX workbook` : 'Publish reviewed unlumped XLSX workbook'}</button>
      <p class="guidance">Source settings/layout are read-only. Hidden lossless source metadata retains typed identities, reference candidates and diagnostics.
        Publication never replaces an existing file. Every returned or unknown outcome clears preparation; acknowledge it and explicitly obtain a new review before retrying.</p>
    </section>
  {/if}
  {#if settings?.constantSpeciesList}<p class="notice">Constant species list is enabled in retained YAML. Presence and mean-cover thresholds are bypassed, as in the source report; missing combinations have NULL statistics, not zero.</p>{/if}
  {#if settings?.grouping === 'none'}<p class="notice">The source's None mode changes row ordering, not cover aggregation.
    Layer observations remain separate and labelled; equal source sort keys use a deterministic layer/name tie-break.
    A constant species list retains its source layer-first order.</p>{/if}
  {#if settings?.grouping === 'lifeform'}<p class="notice">Lifeform conversion uses the original master/personal UNION,
    extended covers and the source's 99.9 cap before grouped insertion. Cover10 is not part of this conversion.
    Later master definitions and physical memberships retain their separate join weights; this is not the standalone Lifeform Summary.</p>{/if}
  {#if settings?.grouping === 'strata'}<p class="notice">Strata A/B use retained TotalA/TotalB when present;
    otherwise source cover sums are capped at 99. Extended B covers participate.
    Only positive A/B results are inserted; C/D retain every non-NULL cover, including zero or negative values.
    Physical Strata definitions retain their original join weights; Cover8/9/10 do not enter this conversion.</p>{/if}
  {#if preview}
    <h2>{preview.report.title === '' ? '"" (empty title)' : preview.report.title}</h2>
    <p role="status">{preview.report.units.length} units. No data, audits or configuration written.</p>
    {#if preview.report.quality}
      <p class="notice">Quality ranks use original DataQuality definitions, not the editor dropdown ordering.
        NULL flags apply to missing/NULL joined ranks; matches only in another list are excluded.
        {preview.report.sourceKind ?
          'Original project tuples are retained by qualified plot existence; reference fanout does not multiply their denominator or cover.' :
          preview.settings.unitGrouping === 'selected-fields' ?
          'For selected-field units, quality keeps derived rows by qualified plot existence; reference fanout does not multiply their denominator or cover.' :
          'Reference fanout weights the denominator and joined cover without inventing physical SU row IDs.'}</p>
      <details class="quality-provenance"><summary>Quality qualification provenance ({preview.report.quality.occurrences.length} occurrences)</summary>
        <p>Threshold reference row IDs — Site: {preview.report.quality.thresholdRowIds[0].join(', ')};
          Vegetation: {preview.report.quality.thresholdRowIds[1].join(', ')};
          Soil: {preview.report.quality.thresholdRowIds[2].join(', ')}.</p>
        <p>Excluded physical membership IDs: {preview.report.quality.excludedMembershipIds.length ? preview.report.quality.excludedMembershipIds.join(', ') : 'None'}.</p>
        {#each preview.report.quality.references as reference}
          <p class="quality-occurrence">Reference row {reference.rowId}: item {reportCellText(reference.item)};
            list {reportCellText(reference.listName)}; rank {reportCellText(reference.itemOrder)}.</p>
        {/each}
        {#each preview.report.quality.occurrences as occurrence}
          <p class="quality-occurrence">SU row {occurrence.membershipId}; plot {JSON.stringify(occurrence.plotNumber.text)};
            unit {reportCellText(occurrence.siteUnit)}; ENV row {occurrence.envRowId}; Admin row {occurrence.adminRowId};
            quality values (Site, Vegetation, Soil): {occurrence.values.map(reportCellText).join(', ')};
            reference rows (Site, Vegetation, Soil): {occurrence.listRowIds.map(id => id === null ? 'NULL join' : id).join(', ')}.</p>
        {/each}
      </details>
    {/if}
    {#if preview.report.sourceKind && preview.report.projectUnits}
      <p class="notice">Original project scope: {preview.report.sourceKind}. Complete original Build remains separate from emitted tuples.
        No synthetic SU row IDs or memberships are created.</p>
      <details class="quality-provenance"><summary>Original project tuple provenance ({preview.report.projectUnits.length} tuples)</summary>
        {#each preview.report.projectUnits as tuple}
          <p class="quality-occurrence">Original ENV row {tuple.envRowId}; Admin row {tuple.adminRowId ?? 'not used by All plots'};
            plot {reportCellText(tuple.plotNumber)}; derived unit {reportCellText(tuple.siteUnit)}.</p>
        {/each}
      </details>
    {/if}
    {#if preview.settings.unitGrouping === 'all-plots' && preview.report.noneUnits}
      <p class="notice">None report units join physical Env rows to the current selected list.
        Quality qualification runs first when enabled. The derived All plots unit does not replace original SU identities
        or expand to all-project scope.</p>
      <details class="quality-provenance"><summary>None unit join provenance ({preview.report.noneUnits.length} occurrences)</summary>
        {#each preview.report.noneUnits as occurrence}
          <p class="quality-occurrence">Outer ENV row {occurrence.envRowId}; original SU row {occurrence.membershipId};
            plot {JSON.stringify(occurrence.plotNumber.text)}; derived unit {reportCellText(occurrence.siteUnit)};
            {occurrence.qualityOccurrence === null ? 'unfiltered current list' : `quality occurrence index ${occurrence.qualityOccurrence}`}.</p>
        {/each}
      </details>
    {/if}
    {#if preview.settings.unitGrouping === 'selected-fields' && preview.report.selectedUnits}
      <p class="notice">Selected report units concatenate the ordered fields with no separator.
        Original selected-SU/Env/Admin joins define the derived denominator and cover weights.
        Quality, when enabled, filters by qualified plot existence rather than multiplying those joins.
        This is not all-project scope and original physical identities remain unchanged.</p>
      <details class="quality-provenance"><summary>Selected field unit join provenance ({preview.report.selectedUnits.length} occurrences)</summary>
        {#each preview.report.selectedUnits as occurrence}
          <p class="quality-occurrence">Original SU row {occurrence.membershipId};
            ENV row {occurrence.envRowId === null ? 'NULL join' : occurrence.envRowId};
            Admin row {occurrence.adminRowId === null ? 'NULL join' : occurrence.adminRowId};
            plot {reportCellText(occurrence.plotNumber)}; derived unit {reportCellText(occurrence.siteUnit)}.</p>
        {/each}
      </details>
    {/if}
    {#each preview.report.diagnostics as diagnostic}
      <p class="diagnostic">{diagnostic.code}: {JSON.stringify(diagnostic.identity)}; count {diagnostic.count}.</p>
    {/each}
    {#each preview.report.units as unit}
      {@const renderedRows = rollupUnitRows(unit, preview.settings)}
      <section class="unit">
        <h3>Site Unit — {unit.code.storage === 'null' ? 'Unassigned (NULL)' : reportCellText(unit.code)}</h3>
        <p class="unit-name">Long name: {unit.longName === null ? unit.nameStatus : unit.longName === '' ? '"" (empty name)' : unit.longName};
          reference status: {unit.nameStatus}.</p>
        <details><summary>Reference name candidates ({unit.nameCandidates.length})</summary>
          {#each unit.nameCandidates as candidate}<p class="name-candidate">Reference row {candidate.rowId}: {reportCellText(candidate.value)}</p>{/each}
        </details>
        {#if preview.report.sourceKind}
          <p>Original project tuple denominator: {unit.numPlots}; emitted tuple indexes: {unit.projectUnitIndexes?.length ?? 0}.</p>
          <details><summary>Original project tuple indexes</summary><p>{unit.projectUnitIndexes?.join(', ')}</p></details>
        {:else}
          <p>{preview.settings.unitGrouping === 'all-plots' ? 'Derived Env/current-list denominator' : preview.settings.unitGrouping === 'selected-fields' ? 'Derived selected-field denominator' : preview.settings.quality ? 'Qualified denominator' : 'Physical denominator'}: {unit.numPlots}; retained physical membership rows: {unit.membershipIds.length}.</p>
          <details><summary>Physical membership row IDs ({unit.membershipIds.length})</summary><p>{unit.membershipIds.join(', ')}</p></details>
        {/if}
        {#if renderedRows.length === 0}
          <p>No {groupLabel.toLowerCase()}/species rows satisfy the current report settings.</p>
        {:else}
          <div class="table-scroll" role="region" aria-label={`Vegetation table for unit ${reportCellText(unit.code)}`}>
            <table>
              <caption>Vegetation Table — Site Unit {reportCellText(unit.code)}</caption>
              <thead><tr>
                <th scope="col">{groupLabel}</th><th scope="col">Species</th>
                {#if preview.settings.showSpeciesCode}<th scope="col">List Code</th><th scope="col">Matched report Code</th>
                {:else if preview.settings.showEnglishName}<th scope="col">List English name</th><th scope="col">Matched report English name</th>
                {:else if preview.settings.selectedField !== undefined}<th scope="col">List {preview.settings.selectedField}</th><th scope="col">Matched report {preview.settings.selectedField}</th>{/if}
                <th scope="col">Presence (%)</th><th scope="col">Mean cover (%)</th>
                {#each renderedRows[0].plots as plot}<th scope="col">Plot {JSON.stringify(plot.plotNumber)}</th>{/each}
              </tr></thead>
              <tbody>{#each renderedRows as row}
                <tr>
                  <td>{reportCellText(row.layer)}</td><th scope="row">{reportCellText(row.species)}</th>
                  {#if preview.settings.showEnglishName || preview.settings.showSpeciesCode || preview.settings.selectedField !== undefined}<td>{supplementaryText(row.englishName)}</td><td>{supplementaryText(row.matchedName)}</td>{/if}
                  <td>{presenceText(row.presence)}</td><td>{numberText(row.meanCover)}</td>
                  {#each row.plots as plot}<td>{numberText(plot.cover)}</td>{/each}
                </tr>
              {/each}</tbody>
            </table>
          </div>
        {/if}
      </section>
    {/each}
  {/if}
  <p class="guidance">Long Vegetation report preview. Report options load from saved configuration; NULL, empty text, zero, and absent statistics remain distinct.
    Unit-name candidates preserve original reference rows, and workbook export writes to a new .xlsx file without overwriting existing destinations.</p>
</section>

<style>
  .report { display: grid; grid-template-columns: minmax(0, 1fr); gap: .75rem; min-width: 0; overflow-wrap: anywhere; color: var(--vpro-ink); }
  .report-sticky-bar { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: .75rem; }
  .report-sticky-bar h1 { margin: 0; }
  .workbook, .preferences, .lump-and-variant-controls, .exclusion-panel { display: grid; grid-template-columns: minmax(0, 1fr); gap: .75rem; min-width: 0; }
  .lump-and-variant-controls, .exclusion-panel { background: var(--vpro-canvas); border: 1px solid var(--vpro-border); border-radius: .4rem; padding: .75rem; }
  .control-field { display: grid; gap: .35rem; min-width: 0; }
  .lump-picker-row { display: flex; flex-wrap: wrap; gap: .5rem; align-items: center; }
  .lump-picker-row select { flex: 1 1 16rem; }
  .toggle-field { display: flex; align-items: center; gap: .5rem; font-weight: 500; cursor: pointer; }
  .exclusion-panel summary { cursor: pointer; font-weight: 600; color: var(--vpro-navy); }
  textarea, select { box-sizing: border-box; min-width: 0; border: 1px solid var(--vpro-border); border-radius: .4rem; padding: .6rem; width: 100%; background: var(--vpro-surface); color: var(--vpro-ink); }
  h1, h2 { color: var(--vpro-navy); }
  h1 { font-size: 1.5rem; } h2 { font-size: 1.25rem; } h3, dt { font-weight: 600; color: var(--vpro-navy); }
  .scope, .settings { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 19rem), 1fr)); gap: .75rem 1.5rem; }
  .scope > div, .settings > div { min-width: 0; display: grid; gap: .25rem; align-content: start; }
  dd { white-space: pre-wrap; overflow-wrap: anywhere; }
  .actions { display: flex; flex-wrap: wrap; gap: .5rem; align-items: center; }
  button { border: 1px solid var(--vpro-navy); border-radius: .4rem; padding: .5rem .75rem; background: var(--vpro-surface); color: var(--vpro-navy); font-weight: 600; cursor: pointer; }
  button:hover:not(:disabled) { background: var(--vpro-canvas); }
  button:disabled { opacity: .5; cursor: not-allowed; }
  .unit { min-width: 0; display: grid; gap: .5rem; }
  .unit-name, .name-candidate, .quality-occurrence { white-space: pre-wrap; overflow-wrap: anywhere; }
  .table-scroll { overflow-x: auto; max-width: 100%; border: 1px solid var(--vpro-border); background: var(--vpro-surface); }
  table { border-collapse: collapse; width: 100%; }
  th, td { border: 1px solid var(--vpro-border); padding: .5rem; text-align: left; min-width: 8rem; white-space: pre-wrap; overflow-wrap: anywhere; }
  thead th { background: var(--vpro-navy); color: var(--vpro-surface); }
  .error { color: var(--vpro-error); font-weight: 600; } .diagnostic, .notice { color: var(--vpro-info); }
  .scope-guidance { margin: 0; padding: .6rem .85rem; border-left: 4px solid var(--vpro-navy); background: var(--vpro-canvas); color: var(--vpro-ink); border-radius: .3rem; }
  .guidance { color: var(--vpro-ink-secondary); font-size: .875rem; }
</style>
