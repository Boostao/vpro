<script lang="ts">
  import { onDestroy, untrack, type Snippet } from 'svelte';
  import type { LongVegetationSettings } from '../../../bindings/github.com/boostao/vpro/app/internal/vegreport/models';
  import type { ReadRequests } from '../../shared/readRequests';
  import { longVegetationPreferencesSession } from '../longVegetationPreferences';
  import { longVegetationStatisticsPreferencesSession } from '../longVegetationStatisticsPreferences';
  import { longVegetationSwitchPreferencesSession } from '../longVegetationSwitchPreferences';
  import { longVegetationThresholdPreferencesSession } from '../longVegetationThresholdPreferences';
  import { longVegetationQualityNullPreferencesSession } from '../longVegetationQualityNullPreferences';
  import { longVegetationQualityMinimumPreferencesSession } from '../longVegetationQualityMinimumPreferences';
  import type { LongVegetationGroupPreferencesSession } from '../longVegetationGroupPreferences';
  import type { LongVegetationNamingPreferencesSession } from '../longVegetationNamingPreferences';
  import type { LongVegetationSelectedFieldPreferencesSession } from '../longVegetationSelectedFieldPreferences';
  import type { LongVegetationEnforcementPreferencesSession } from '../longVegetationEnforcementPreferences';
  import type { LongVegetationUnitPreferencesSession } from '../longVegetationUnitPreferences';
  import type { SelectedUnitSelectionSession } from '../longVegetationSelectedUnitSelection';
  import type { ProjectScopeSelectionSession } from '../longVegetationProjectScopeSession';
  import type { projectReportWorkspace } from '../longVegetationProjectWorkspaces';
  import type { VegetationWorkbookPublicationSession } from '../vegetationWorkbook';
  import LongVegetationHeaderAndScope, { type LongVegHeaderActions } from './LongVegetationHeaderAndScope.svelte';
  import LongVegetationTitleStatsPreferences from './LongVegetationTitleStatsPreferences.svelte';
  import LongVegetationSecondaryPreferences, {
    type SecondaryBusyKind,
  } from './LongVegetationSecondaryPreferences.svelte';
  import LongVegetationToastBridge from './LongVegetationToastBridge.svelte';

  type Workspace = NonNullable<ReturnType<typeof projectReportWorkspace>>;
  type Owner = { contextId: string; project: string; projectPath: string; su: string; suPath: string };

  export interface LongVegHostContext {
    projectActive: boolean;
    workbookBarrier: boolean;
    preferenceBarrier: boolean;
    sharedPreferenceBarrier: boolean;
    cancelLoads: () => void;
    syncWorkbook: () => void;
    syncProject: () => void;
  }

  let {
    workbookOwner,
    registries,
    projectWorkspace,
    projectView,
    publication,
    settings,
    busy,
    operationHeld,
    selectedWorkbookScope,
    destination,
    reads,
    resolveContextTag,
    headerActions,
    onBusyChange,
    onInvalidate,
    onSelectedUnitReset,
    onBridgeReady,
    onBeginTitleStatsRead,
    onEndTitleStatsRead,
    onCancelTitleStatsParent,
    onTitleStatsError,
    children,
  }: {
    workbookOwner: Owner;
    registries: {
      groupingSession: ((o: Owner) => LongVegetationGroupPreferencesSession) | null;
      namingSession: ((o: Owner) => LongVegetationNamingPreferencesSession) | null;
      selectedFieldSession: ((o: Owner) => LongVegetationSelectedFieldPreferencesSession) | null;
      enforcementSession: ((o: Owner) => LongVegetationEnforcementPreferencesSession) | null;
      unitSession: ((o: Owner) => LongVegetationUnitPreferencesSession) | null;
      selectedUnitSession: ((o: Owner) => SelectedUnitSelectionSession) | null;
    };
    projectWorkspace: Workspace | null;
    projectView: ReturnType<Workspace['view']> | null;
    publication: ReturnType<VegetationWorkbookPublicationSession['view']>;
    settings: LongVegetationSettings | null;
    busy: boolean;
    operationHeld: boolean;
    selectedWorkbookScope: string;
    destination: string;
    reads: ReadRequests;
    resolveContextTag: () => string | undefined;
    headerActions: LongVegHeaderActions;
    onBusyChange: (busy: boolean) => void;
    onInvalidate: (invalidatesSettings?: (s: LongVegetationSettings) => boolean) => void;
    onSelectedUnitReset: () => void;
    onBridgeReady: (ctx: LongVegHostContext) => void;
    onBeginTitleStatsRead: () => number;
    onEndTitleStatsRead: (req: number) => void;
    onCancelTitleStatsParent: () => number;
    onTitleStatsError: (title: string, msg: string) => void;
    children: Snippet<[LongVegHostContext]>;
  } = $props();

  const prefFlag = (
    rb: boolean,
    v: { busy?: boolean; blocked?: boolean; authorityUnknown?: boolean; draftError?: string } | null | undefined
  ) => rb || (!!v && Boolean(v.busy || v.blocked || v.authorityUnknown || v.draftError));
  const mutFlag = (rb: boolean, v: { busy?: boolean; blocked?: boolean } | null | undefined) =>
    rb || (!!v && Boolean(v.busy || v.blocked));

  const projectScopeSelection = untrack(() =>
    projectWorkspace
      ? ({
          view: () => {
            const raw = projectWorkspace.selection.view();
            return raw &&
              !raw.dirty &&
              (!raw.fields || raw.fields.length === 0) &&
              raw.scope?.sourceKind !== 'project-selected-fields'
              ? { ...raw, draftError: '' }
              : raw;
          },
          subscribe: (fn) => projectWorkspace.selection.subscribe(fn),
          cancel: () => projectWorkspace.selection.cancel(),
          load: () => projectWorkspace.selection.load(),
          switchTo: (k) => projectWorkspace.selection.switchTo(k),
          build: () => projectWorkspace.selection.build(),
          edit: (f) => projectWorkspace.selection.edit(f),
          undo: () => projectWorkspace.selection.undo(),
        } as ProjectScopeSelectionSession)
      : null
  );

  const projectActive = $derived(!!projectView?.projectActive);
  const projectScopeKnown = $derived(
    !projectWorkspace || (!!projectView?.scope.scope && !projectView.scope.authorityUnknown)
  );
  const projectBarrier = $derived(
    !!projectWorkspace &&
      (!projectScopeKnown ||
        Boolean(
          projectView &&
          (projectView.readBusy ||
            projectView.scope.busy ||
            (projectView.scope.scope?.sourceKind === 'project-selected-fields' && projectView.scope.dirty) ||
            projectView.units.closeBlocked)
        ))
  );
  const projectMutationHeld = $derived(
    Boolean(
      projectView &&
      (projectView.readBusy ||
        projectView.scope.busy ||
        projectView.units.readBusy ||
        projectView.units.busy ||
        projectView.units.blocked)
    )
  );

  const owner = untrack(() => workbookOwner);
  const reg = untrack(() => registries);
  const preferences = longVegetationPreferencesSession?.(owner) ?? null;
  let preferenceView = $state(preferences?.view() ?? null);
  const statistics = longVegetationStatisticsPreferencesSession?.(owner) ?? null;
  let statisticsView = $state(statistics?.view() ?? null);
  const sessions = {
    switches: longVegetationSwitchPreferencesSession?.(owner) ?? null,
    thresholds: longVegetationThresholdPreferencesSession?.(owner) ?? null,
    groups: reg.groupingSession ? reg.groupingSession(owner) : null,
    qualityNulls: longVegetationQualityNullPreferencesSession?.(owner) ?? null,
    qualityMinima: longVegetationQualityMinimumPreferencesSession?.(owner) ?? null,
    naming: reg.namingSession ? reg.namingSession(owner) : null,
    selectedField: reg.selectedFieldSession ? reg.selectedFieldSession(owner) : null,
    enforcement: reg.enforcementSession ? reg.enforcementSession(owner) : null,
    units: reg.unitSession ? reg.unitSession(owner) : null,
    selectedUnitSelection: reg.selectedUnitSession ? reg.selectedUnitSession(owner) : null,
  };
  let switchView = $state(sessions.switches?.view() ?? null);
  let thresholdView = $state(sessions.thresholds?.view() ?? null);
  let groupView = $state(sessions.groups?.view() ?? null);
  let qualityNullView = $state(sessions.qualityNulls?.view() ?? null);
  let qualityMinimumView = $state(sessions.qualityMinima?.view() ?? null);
  let namingView = $state(sessions.naming?.view() ?? null);
  let selectedFieldView = $state(sessions.selectedField?.view() ?? null);
  let enforcementView = $state(sessions.enforcement?.view() ?? null);
  let unitView = $state(sessions.units?.view() ?? null);
  let selectedUnitView = $state.raw(sessions.selectedUnitSelection?.view() ?? null);
  let rb = $state<Record<SecondaryBusyKind, boolean>>({
    switch: false,
    threshold: false,
    group: false,
    qualityNull: false,
    qualityMinimum: false,
    naming: false,
    selectedField: false,
    enforcement: false,
    unit: false,
  });

  const titleBarrier = $derived(prefFlag(false, preferenceView));
  const statisticsBarrier = $derived(prefFlag(false, statisticsView));
  const titleStatsMutationHeld = $derived(
    Boolean(preferenceView?.busy || preferenceView?.blocked || statisticsView?.busy || statisticsView?.blocked)
  );
  const secState = $derived.by(() => {
    const switchBarrier = prefFlag(rb.switch, switchView),
      switchMutationHeld = mutFlag(rb.switch, switchView);
    const thresholdBarrier = prefFlag(rb.threshold, thresholdView),
      thresholdMutationHeld = mutFlag(rb.threshold, thresholdView);
    const groupBarrier = prefFlag(rb.group, groupView),
      groupMutationHeld = mutFlag(rb.group, groupView);
    const qualityNullBarrier = prefFlag(rb.qualityNull, qualityNullView),
      qualityNullMutationHeld = mutFlag(rb.qualityNull, qualityNullView);
    const qualityMinimumBarrier = prefFlag(rb.qualityMinimum, qualityMinimumView),
      qualityMinimumMutationHeld = mutFlag(rb.qualityMinimum, qualityMinimumView);
    const namingBarrier = prefFlag(rb.naming, namingView),
      namingMutationHeld = mutFlag(rb.naming, namingView);
    const selectedFieldBarrier = prefFlag(rb.selectedField, selectedFieldView),
      selectedFieldMutationHeld = mutFlag(rb.selectedField, selectedFieldView);
    const enforcementBarrier = prefFlag(rb.enforcement, enforcementView),
      enforcementMutationHeld = mutFlag(rb.enforcement, enforcementView);
    const selectedUnitBarrier =
      !!selectedUnitView &&
      Boolean(selectedUnitView.busy || selectedUnitView.dirty || selectedUnitView.authorityUnknown);
    const selectedUnitMutationHeld = !!selectedUnitView?.busy;
    const peerPreferenceBarriers =
      switchBarrier ||
      thresholdBarrier ||
      groupBarrier ||
      qualityNullBarrier ||
      qualityMinimumBarrier ||
      namingBarrier ||
      selectedFieldBarrier ||
      enforcementBarrier;
    const acknowledgePeerHeld =
      thresholdMutationHeld ||
      groupMutationHeld ||
      qualityNullMutationHeld ||
      qualityMinimumMutationHeld ||
      namingMutationHeld ||
      selectedFieldMutationHeld ||
      enforcementMutationHeld;
    const peerMutationHeld = switchMutationHeld || acknowledgePeerHeld;
    return {
      unitView,
      unitReadBusy: rb.unit,
      switchBarrier,
      switchMutationHeld,
      thresholdBarrier,
      thresholdMutationHeld,
      groupBarrier,
      groupMutationHeld,
      qualityNullBarrier,
      qualityNullMutationHeld,
      qualityMinimumBarrier,
      qualityMinimumMutationHeld,
      namingBarrier,
      namingMutationHeld,
      selectedFieldBarrier,
      selectedFieldMutationHeld,
      enforcementBarrier,
      enforcementMutationHeld,
      selectedUnitBarrier,
      selectedUnitMutationHeld,
      ordinaryUnitBarrier: selectedUnitBarrier || prefFlag(rb.unit, unitView),
      ordinaryUnitMutationHeld: selectedUnitMutationHeld || mutFlag(rb.unit, unitView),
      peerPreferenceBarriers,
      acknowledgePeerHeld,
      peerMutationHeld,
    };
  });
  const unitBarrier = $derived(secState.ordinaryUnitBarrier || projectBarrier);
  const unitMutationHeld = $derived(secState.ordinaryUnitMutationHeld || projectMutationHeld);
  const sharedPreferenceBarrier = $derived(
    titleBarrier || statisticsBarrier || secState.peerPreferenceBarriers || secState.ordinaryUnitBarrier
  );
  const sharedMutationHeld = $derived(
    secState.ordinaryUnitMutationHeld || titleStatsMutationHeld || secState.peerMutationHeld
  );
  const preferenceBarrier = $derived(sharedPreferenceBarrier || projectBarrier);
  const workbookBarrier = $derived(
    publication.busy ||
      publication.blocked ||
      Boolean(projectView?.publication && (projectView.publication.busy || projectView.publication.blocked))
  );

  let syncApi = { syncWorkbook: () => {}, syncProject: () => {}, syncPreference: () => {}, syncStatistics: () => {} };
  const reportBusy = () =>
    onBusyChange(busy || workbookBarrier || sharedPreferenceBarrier || !!projectView?.closeBlocked);
  const unsubs: Array<(() => void) | undefined> = [
    preferences?.subscribe(() => {
      preferenceView = preferences.view();
      onInvalidate((s) =>
        Boolean(preferenceView?.authorityUnknown || (preferenceView?.saved && s.title !== preferenceView.saved.title))
      );
      syncApi.syncPreference();
      reportBusy();
    }),
    statistics?.subscribe(() => {
      statisticsView = statistics.view();
      onInvalidate((s) =>
        Boolean(
          statisticsView?.authorityUnknown ||
          (statisticsView?.saved &&
            (s.average !== (statisticsView.saved.avgType === 10 ? 'all-plots' : 'observations') ||
              s.order !== (statisticsView.saved.orderBy === 10 ? 'species' : 'presence')))
        )
      );
      syncApi.syncStatistics();
      reportBusy();
    }),
    sessions.switches?.subscribe(() => {
      switchView = sessions.switches!.view();
      onInvalidate((s) =>
        Boolean(
          switchView?.authorityUnknown ||
          (switchView?.saved && s.constantSpeciesList !== switchView.saved.constantSpeciesList)
        )
      );
      reportBusy();
    }),
    sessions.thresholds?.subscribe(() => {
      thresholdView = sessions.thresholds!.view();
      onInvalidate((s) =>
        Boolean(
          thresholdView?.authorityUnknown ||
          (thresholdView?.saved &&
            (s.presenceGreaterThan !== thresholdView.saved.presenceGreaterThan ||
              s.meanCoverGreaterThan !== thresholdView.saved.meanCoverGreaterThan))
        )
      );
      reportBusy();
    }),
    sessions.groups?.subscribe(() => {
      groupView = sessions.groups!.view();
      const g = groupView?.saved?.groupBy;
      onInvalidate((s) =>
        Boolean(
          groupView?.authorityUnknown ||
          (groupView?.saved && s.grouping !== (g === 1 ? 'layer' : g === 2 ? 'strata' : g === 3 ? 'lifeform' : 'none'))
        )
      );
      reportBusy();
    }),
    sessions.qualityNulls?.subscribe(() => {
      qualityNullView = sessions.qualityNulls!.view();
      onInvalidate((s) =>
        Boolean(
          qualityNullView?.authorityUnknown ||
          (s.quality &&
            qualityNullView?.saved &&
            (s.quality.site.includeNull !== qualityNullView.saved.siteIncludeNulls ||
              s.quality.veg.includeNull !== qualityNullView.saved.vegIncludeNulls ||
              s.quality.soil.includeNull !== qualityNullView.saved.soilIncludeNulls))
        )
      );
      reportBusy();
    }),
    sessions.qualityMinima?.subscribe(() => {
      qualityMinimumView = sessions.qualityMinima!.view();
      onInvalidate((s) =>
        Boolean(
          qualityMinimumView?.authorityUnknown ||
          (s.quality &&
            qualityMinimumView?.saved &&
            (s.quality.site.minimum !== qualityMinimumView.saved.siteMinimum ||
              s.quality.veg.minimum !== qualityMinimumView.saved.vegMinimum ||
              s.quality.soil.minimum !== qualityMinimumView.saved.soilMinimum))
        )
      );
      reportBusy();
    }),
    sessions.naming?.subscribe(() => {
      namingView = sessions.naming!.view();
      onInvalidate((s) =>
        Boolean(
          namingView?.authorityUnknown ||
          (namingView?.saved &&
            (s.showEnglishName !== (namingView.saved.mode === 1) ||
              s.showSpeciesCode !== (namingView.saved.mode === 2) ||
              s.selectedField !== (namingView.saved.mode === 4 ? namingView.saved.selectedField : undefined)))
        )
      );
      reportBusy();
    }),
    sessions.selectedField?.subscribe(() => {
      selectedFieldView = sessions.selectedField!.view();
      onInvalidate((s) =>
        Boolean(
          selectedFieldView?.authorityUnknown ||
          (selectedFieldView?.saved &&
            (s.showEnglishName !== (selectedFieldView.saved.mode === 1) ||
              s.showSpeciesCode !== (selectedFieldView.saved.mode === 2) ||
              s.selectedField !==
                (selectedFieldView.saved.mode === 4 ? selectedFieldView.saved.selectedField : undefined)))
        )
      );
      reportBusy();
    }),
    sessions.enforcement?.subscribe(() => {
      enforcementView = sessions.enforcement!.view();
      onInvalidate((s) => {
        const ug = s.unitGrouping === 'all-plots' ? 3 : s.unitGrouping === 'selected-fields' ? 2 : 1;
        return Boolean(
          enforcementView?.authorityUnknown ||
          (enforcementView?.saved &&
            (!!s.quality !== enforcementView.saved.enforce || ug !== enforcementView.saved.unitGroups))
        );
      });
      reportBusy();
    }),
    sessions.units?.subscribe(() => {
      unitView = sessions.units!.view();
      onInvalidate((s) => {
        const ug = s.unitGrouping === 'all-plots' ? 3 : s.unitGrouping === 'selected-fields' ? 2 : 1;
        return Boolean(unitView?.authorityUnknown || (unitView?.saved && ug !== unitView.saved.unitGroups));
      });
      reportBusy();
    }),
  ];
  reportBusy();

  const hostCtx = $derived<LongVegHostContext>({
    projectActive,
    workbookBarrier,
    preferenceBarrier,
    sharedPreferenceBarrier,
    cancelLoads: () => {
      preferences?.cancelLoad();
      statistics?.cancelLoad();
    },
    syncWorkbook: () => syncApi.syncWorkbook(),
    syncProject: () => syncApi.syncProject(),
  });
  $effect(() => {
    onBridgeReady(hostCtx);
    reportBusy();
  });

  const holds = $derived({
    busy,
    operationHeld,
    workbookBarrier,
    preferenceBarrier,
    unitBarrier,
    unitMutationHeld,
    sharedPreferenceBarrier,
    sharedMutationHeld,
    titleBarrier,
    statisticsBarrier,
    titleStatsMutationHeld,
    peerPreferenceBarriers: secState.peerPreferenceBarriers,
    peerMutationHeld: secState.peerMutationHeld,
    acknowledgePeerHeld: secState.acknowledgePeerHeld,
    projectActive,
    projectScopeKnown,
    projectBarrier,
    projectMutationHeld,
    su: workbookOwner.su,
    settingsReady: !!settings,
    selectedWorkbookScope,
    projectWorkspace,
    projectView,
    projectScopeSelection,
    publication,
    preferenceDraftError: preferenceView?.draftError ?? '',
    statisticsDraftError: statisticsView?.draftError ?? '',
  });
  const titleStatsCallbacks = $derived({
    reads,
    onBeginRead: onBeginTitleStatsRead,
    onEndRead: onEndTitleStatsRead,
    onCancelParent: onCancelTitleStatsParent,
    onSyncPreferenceToast: () => syncApi.syncPreference(),
    onSyncStatisticsToast: () => syncApi.syncStatistics(),
    onError: onTitleStatsError,
  });

  onDestroy(() => {
    for (const u of unsubs) u?.();
  });
</script>

<LongVegetationToastBridge
  {publication}
  {projectView}
  {preferenceView}
  {statisticsView}
  {destination}
  {resolveContextTag}
  onSyncApi={(api) => {
    syncApi = api;
  }}
/>
<LongVegetationHeaderAndScope state={holds} actions={headerActions} />
<LongVegetationTitleStatsPreferences
  contextId={workbookOwner.contextId}
  {preferences}
  {preferenceView}
  {statistics}
  {statisticsView}
  {holds}
  callbacks={titleStatsCallbacks}
/>
<LongVegetationSecondaryPreferences
  contextId={workbookOwner.contextId}
  {sessions}
  {secState}
  {holds}
  onReadBusy={(k, v) => {
    rb[k] = v;
    reportBusy();
  }}
  onSelectedUnitChanged={() => {
    selectedUnitView = sessions.selectedUnitSelection?.view() ?? null;
    onSelectedUnitReset();
    reportBusy();
  }}
/>
{@render children(hostCtx)}
