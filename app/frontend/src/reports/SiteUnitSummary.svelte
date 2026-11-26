<script lang="ts">
  import { onMount, onDestroy, untrack } from 'svelte';
  import { EnvironmentReportService, type HTMLReportResult } from '../../bindings/github.com/boostao/vpro/app';
  import { ReadRequests } from '../shared/readRequests';
  import {
    validateSiteUnitSummary,
    validateSiteUnitSummaryOptions,
    type ValidatedSiteUnitSummary,
    type SiteUnitSummaryMode,
  } from './siteUnitSummary';
  import {
    siteUnitSummaryPreferencesSession,
    siteUnitSummaryFullPreferencesSession,
    type SummaryFullPreferenceValues,
  } from './siteUnitSummaryPreferences';
  import CompactReportShell from './CompactReportShell.svelte';
  import SiteUnitSummaryQuickOptions from './SiteUnitSummaryQuickOptions.svelte';
  import SiteUnitSummaryFieldsets from './SiteUnitSummaryFieldsets.svelte';
  import SiteUnitSummaryWorkbookPanel from './SiteUnitSummaryWorkbookPanel.svelte';
  import SiteUnitSummaryActionBar from './SiteUnitSummaryActionBar.svelte';
  import SiteUnitSummaryResults from './SiteUnitSummaryResults.svelte';
  import { summarySpeciesCriteria, validateSummarySpecies, type ValidatedSummarySpecies } from './siteUnitSummarySpecies';
  import { extendedSummaryWorkbookPublicationSession, type ExtendedSummaryWorkbookOptions } from './siteUnitSummaryExtendedWorkbook';
  import { notifications } from '../shell/notificationService.svelte';
  import * as ops from './siteUnitSummaryOps';
  import type { QuickExportSummary } from './compactReport';
  import * as quick from './compactReportRunners';

  interface Props {
    contextId: string;
    project: string;
    projectPath: string;
    su: string;
    suPath: string;
    onBusyChange: (busy: boolean) => void;
  }
  let { contextId, project, projectPath, su, suPath, onBusyChange }: Props = $props();

  let method = $state<number | null>(null);
  let siteUnitType = $state<number | null>(null);
  let ready = $state(false);
  let busy = $state(false);
  let workbookBusy = $state(false);
  let error = $state('');
  let preview = $state<ValidatedSiteUnitSummary | null>(null);
  let quickDraft = $state<quick.SummaryEnvQuickDraft>(
    quick.loadInitialQuickDraft('summary_env', quick.DEFAULT_SUMMARY_ENV_QUICK)
  );
  let quickExporting = $state(false);
  let quickRendering = $state(false);
  let quickError = $state('');
  let quickExportResult = $state.raw<QuickExportSummary | null>(null);
  let quickHtmlReport = $state.raw<HTMLReportResult | null>(null);
  const ownerScope = () => ({ contextId, project, projectPath, su, suPath });
  const extendedAuthority = untrack(() =>
    typeof extendedSummaryWorkbookPublicationSession === 'function'
      ? extendedSummaryWorkbookPublicationSession(ownerScope())
      : null
  );
  const retainedOptions = extendedAuthority?.view().blocked ? extendedAuthority.requestedOptions() : null;
  let mode = $state<SiteUnitSummaryMode>(
    retainedOptions?.orderBy === 2 ? 'lifeform' : retainedOptions?.orderBy === 3 ? 'strata' : 'layer'
  );
  const criteria = untrack(() =>
    typeof summarySpeciesCriteria === 'function' ? summarySpeciesCriteria(ownerScope()) : null
  );
  let speciesView = $state(criteria?.view() ?? null);
  let speciesPreview = $state<ValidatedSummarySpecies | null>(null);
  const speciesBarrier = $derived(!!speciesView?.error);
  const buildReq = criteria ? (m: number, md: SiteUnitSummaryMode) => criteria.request(m, md) : undefined;
  const extendedOptions = $derived<ExtendedSummaryWorkbookOptions | null>(
    ops.buildExtendedSummaryOptions({
      method,
      speciesBarrier,
      speciesEnabled: !!speciesView?.enabled,
      mode,
      buildSpeciesRequest: buildReq,
    })
  );

  const reads = new ReadRequests();
  let generation = 0;
  const preferences = untrack(() =>
    typeof siteUnitSummaryPreferencesSession === 'function' ? siteUnitSummaryPreferencesSession(ownerScope()) : null
  );
  const fullPreferences =
    typeof siteUnitSummaryFullPreferencesSession === 'function'
      ? untrack(() => siteUnitSummaryFullPreferencesSession(ownerScope()))
      : null;
  let preferenceView = $state(preferences?.view() ?? null);
  let fullPreferenceView = $state(fullPreferences?.view() ?? null);
  const preferenceBarrier = $derived(ops.isSiteUnitPreferenceHeld(preferenceView, fullPreferenceView));
  const scopeAllowed = $derived(ops.isSiteUnitScopeTypeAllowed(siteUnitType ?? 0, su));
  const toastTracker = ops.createSiteUnitNotificationTracker();

  const syncSpeciesNotifications = () =>
    ops.syncSiteUnitSpeciesToast(notifications, toastTracker, criteria?.view()?.error ?? '', project);
  const syncPreferenceNotifications = () =>
    ops.syncSiteUnitPreferenceToasts(notifications, toastTracker, preferences?.view(), project, 'short');
  const syncFullPreferenceNotifications = () =>
    ops.syncSiteUnitPreferenceToasts(notifications, toastTracker, fullPreferences?.view(), project, 'full');
  function reportBusy() {
    onBusyChange(busy || preferenceBarrier || workbookBusy || speciesBarrier);
  }

  const unsubscribeSpecies = criteria?.subscribe(() => {
    speciesView = criteria.view();
    preview = null;
    speciesPreview = null;
    syncFullDraftFromUI();
    syncSpeciesNotifications();
    reportBusy();
  });
  const unsubscribe = preferences?.subscribe(() => {
    preferenceView = preferences.view();
    if (!fullPreferenceView?.draft) {
      method = preferenceView.draft?.method ?? null;
      siteUnitType = preferenceView.draft?.siteUnitType ?? null;
    }
    ready = ops.isSiteUnitSummaryReady(
      method,
      siteUnitType ?? preferenceView.draft?.siteUnitType ?? 0,
      su,
      preferenceView.authorityUnknown
    );
    preview = null;
    speciesPreview = null;
    syncPreferenceNotifications();
    reportBusy();
  });
  const unsubscribeFull = fullPreferences?.subscribe(() => {
    fullPreferenceView = fullPreferences.view();
    if (fullPreferenceView.draft) {
      method = fullPreferenceView.draft.method;
      siteUnitType = fullPreferenceView.draft.siteUnitType;
    }
    ready = ops.isSiteUnitSummaryReady(method, siteUnitType ?? 0, su, fullPreferenceView.authorityUnknown);
    syncFullPreferenceNotifications();
    reportBusy();
  });
  syncSpeciesNotifications();
  syncPreferenceNotifications();
  syncFullPreferenceNotifications();

  function syncFullDraftFromUI() {
    if (!fullPreferences || !fullPreferenceView?.draft || fullPreferenceView.busy || fullPreferenceView.blocked) return;
    const patch = ops.buildSiteUnitFullDraftPatch({
      method,
      siteUnitType,
      fallbackSiteUnitType: fullPreferenceView.draft.siteUnitType,
      mode,
      speciesView,
    });
    if (patch) fullPreferences.edit(patch);
  }
  function applyFullPreferencesToUI(values: SummaryFullPreferenceValues) {
    method = values.method;
    siteUnitType = values.siteUnitType;
    mode = ops.applySiteUnitFullValuesToCriteria(values, criteria);
  }
  function cancel() {
    generation++;
    reads.cancelAll();
    preferences?.cancelLoad();
    if (typeof fullPreferences !== 'undefined') fullPreferences?.cancelLoad();
    busy = false;
    reportBusy();
  }
  async function options() {
    if (workbookBusy) return;
    cancel();
    const request = generation;
    [ready, error, preview, speciesPreview, busy] = [false, '', null, null, true];
    reportBusy();
    await ops.runSiteUnitOptionsLoad({
      reads,
      fetchOptions: () => EnvironmentReportService.GetSiteUnitSummaryOptions(contextId),
      isCurrent: () => !(request !== generation),
      validate: (val) => validateSiteUnitSummaryOptions(val, contextId, project, projectPath, su, suPath, true),
      su,
      onConfigured: (m, st, r) => ([method, siteUnitType, ready] = [m, st, r]),
      onIneligible: (msg) =>
        (error = ops.emitSiteUnitToastError(notifications, project, 'Summary Environment options ineligible', msg)),
      onError: (msg) =>
        (error = ops.emitSiteUnitToastError(notifications, project, 'Summary Environment options failed', msg)),
      onDone: () => (([busy] = [false]), reportBusy()),
    });
  }
  async function show() {
    if (busy || workbookBusy || preferenceBarrier || speciesBarrier || !ready || (method !== 1 && method !== 2)) return;
    const activeType = typeof siteUnitType === 'number' ? siteUnitType : 1;
    if (!ops.isSiteUnitScopeTypeAllowed(activeType, su)) return;
    cancel();
    const [request, requestedMethod, requestedMode] = [generation, method, mode];
    const allowConfigured = activeType !== 1 || requestedMode === 'strata';
    const speciesRequest = speciesView?.enabled ? (criteria?.request(requestedMethod, requestedMode) ?? null) : null;
    [error, preview, speciesPreview, busy] = ['', null, null, true];
    reportBusy();
    await ops.runSiteUnitShowReport({
      reads,
      fetchPreview: () =>
        speciesRequest
          ? EnvironmentReportService.PreviewSiteUnitSummarySpecies(contextId, speciesRequest)
          : requestedMode === 'lifeform'
            ? EnvironmentReportService.PreviewSiteUnitSummaryLifeforms(contextId, { method: requestedMethod })
            : EnvironmentReportService.PreviewSiteUnitSummary(contextId, { method: requestedMethod }),
      isCurrent: () => !(request !== generation),
      validate: (value) =>
        ops.validateSiteUnitPreviewResponse({
          value,
          owner: {
            contextId,
            project,
            projectPath: typeof projectPath === 'string' ? projectPath : '',
            su,
            suPath: typeof suPath === 'string' ? suPath : '',
          },
          requestedMethod,
          requestedMode,
          allowConfigured,
          speciesRequest,
          validators: {
            validateSiteUnitSummary,
            validateSummarySpecies: typeof validateSummarySpecies === 'function' ? validateSummarySpecies : undefined,
          },
        }),
      onSuccess: (res) => ([preview, speciesPreview] = [res.preview, res.speciesPreview]),
      onError: (msg) =>
        (error = ops.emitSiteUnitToastError(notifications, project, 'Summary Environment report failed', msg)),
      onDone: () => (([busy] = [false]), reportBusy()),
    });
  }
  async function loadPreferences() {
    if (workbookBusy || !preferences || preferenceView?.busy || preferenceView?.blocked) return;
    cancel();
    const [request, token] = [generation, preferences.beginLoad()];
    const canFull =
      typeof fullPreferences !== 'undefined' &&
      !!fullPreferences &&
      typeof fullPreferenceView !== 'undefined' &&
      !fullPreferenceView?.busy &&
      !fullPreferenceView?.blocked;
    const fullToken = canFull ? fullPreferences!.beginLoad() : null;
    [error, busy] = ['', true];
    reportBusy();
    const hasFullRpc =
      typeof EnvironmentReportService.GetFullSiteUnitSummaryPreferences === 'function' &&
      !!fullPreferences &&
      fullToken !== null;
    await ops.runSiteUnitCombinedPrefLoad({
      reads,
      su,
      fetchFull: hasFullRpc ? () => EnvironmentReportService.GetFullSiteUnitSummaryPreferences(contextId) : null,
      applyFull: (fv) => fullPreferences?.applyLoaded(fv, fullToken as number) && applyFullPreferencesToUI(fv.values),
      fetchShort: () => EnvironmentReportService.GetSiteUnitSummaryPreferences(contextId),
      applyShort: (val) => preferences.applyLoaded(val, token),
      applyFallbackDraft: () =>
        fullPreferenceView?.draft &&
        ([method, siteUnitType, ready] = [
          fullPreferenceView.draft.method,
          fullPreferenceView.draft.siteUnitType,
          fullPreferenceView.draft.siteUnitType === 3,
        ]),
      isCurrent: () => !(request !== generation),
      onError: (msg) =>
        (error = ops.emitSiteUnitToastError(notifications, project, 'Summary Environment options load failed', msg)),
      onDone: () => (([busy] = [false]), reportBusy()),
    });
  }
  async function loadFullPreferences() {
    if (workbookBusy || !fullPreferences || fullPreferenceView?.busy || fullPreferenceView?.blocked) return;
    cancel();
    const [request, token] = [generation, fullPreferences.beginLoad()];
    [error, busy] = ['', true];
    reportBusy();
    await ops.runSiteUnitFullPreferencesLoad({
      reads,
      fetchFull: () => EnvironmentReportService.GetFullSiteUnitSummaryPreferences(contextId),
      isCurrent: () => !(request !== generation),
      applyLoaded: (v) => fullPreferences.applyLoaded(v, token),
      onApplied: applyFullPreferencesToUI,
      onError: (msg) =>
        (error = ops.emitSiteUnitToastError(
          notifications,
          project,
          'Summary Environment full preferences load failed',
          msg
        )),
      onDone: () => (([busy] = [false]), reportBusy()),
    });
  }
  async function savePreferences() {
    if (workbookBusy || !preferences || busy || speciesBarrier || preferenceView?.busy || preferenceView?.blocked)
      return;
    cancel();
    error = '';
    await ops.runSiteUnitPrefSave(
      () =>
        preferences.save((req) =>
          EnvironmentReportService.SaveSiteUnitSummaryPreferences(contextId, JSON.stringify(req))
        ),
      () => typeof syncPreferenceNotifications === 'function' && syncPreferenceNotifications(),
      (msg) =>
        (error = ops.emitSiteUnitToastError(notifications, project, 'Summary Environment options save failed', msg))
    );
  }
  async function saveFullPreferences() {
    if (
      workbookBusy ||
      !fullPreferences ||
      busy ||
      speciesBarrier ||
      fullPreferenceView?.busy ||
      fullPreferenceView?.blocked
    )
      return;
    cancel();
    error = '';
    syncFullDraftFromUI();
    await ops.runSiteUnitPrefSave(
      () =>
        fullPreferences.save((req) =>
          EnvironmentReportService.SaveFullSiteUnitSummaryPreferences(contextId, JSON.stringify(req))
        ),
      () => typeof syncFullPreferenceNotifications === 'function' && syncFullPreferenceNotifications(),
      (msg) =>
        (error = ops.emitSiteUnitToastError(
          notifications,
          project,
          'Summary Environment full preferences save failed',
          msg
        ))
    );
  }
  function editMethod(value: number) {
    if (workbookBusy || speciesBarrier) return;
    cancel();
    [error, preview, speciesPreview] = ['', null, null];
    if (
      typeof fullPreferences !== 'undefined' &&
      fullPreferences &&
      typeof fullPreferenceView !== 'undefined' &&
      fullPreferenceView?.draft
    ) {
      fullPreferences.edit({ method: value });
    }
    if (preferences) preferences.editMethod(value);
    else method = value;
  }
  function editSiteUnitType(value: number) {
    if (busy || workbookBusy || preferenceBarrier || speciesBarrier) return;
    cancel();
    [error, preview, speciesPreview, siteUnitType] = ['', null, null, value];
    if (fullPreferences && fullPreferenceView?.draft) fullPreferences.edit({ siteUnitType: value });
    if (value === 1 && preferences && preferenceView?.draft) preferences.selectNormalSU();
    ready = ops.isSiteUnitSummaryReady(method, value, su, preferenceView?.authorityUnknown);
  }
  function editMode(value: SiteUnitSummaryMode) {
    if (busy || workbookBusy || preferenceBarrier || speciesBarrier) return;
    cancel();
    [error, preview, speciesPreview, mode] = ['', null, null, value];
    if (typeof syncFullDraftFromUI === 'function') syncFullDraftFromUI();
  }
  function editSpeciesEnabled(enabled: boolean) {
    if (busy || workbookBusy || preferenceBarrier || speciesBarrier || !ready || !criteria) return;
    cancel();
    error = '';
    criteria.setEnabled(enabled);
  }
  function editSpeciesText(field: 'presenceGreaterThan' | 'coverGreaterThan', value: string) {
    if (busy || workbookBusy || preferenceBarrier || !criteria) return;
    cancel();
    error = '';
    criteria.editText(field, value);
  }
  function editSpeciesChoice(field: 'coverCalculation' | 'andOr', value: number) {
    if (busy || workbookBusy || preferenceBarrier || !criteria) return;
    cancel();
    error = '';
    criteria.editChoice(field, value);
  }
  function resetSpeciesCriteria() {
    if (busy || workbookBusy || preferenceBarrier || !criteria) return;
    cancel();
    error = '';
    criteria.reset();
  }

  const barFlags = $derived([busy, workbookBusy, preferenceBarrier, speciesBarrier, ready] as const);
  const fieldsetsModel = $derived(
    ops.packFieldsetsModel(su, mode, siteUnitType, method, barFlags, preferenceView, speciesView)
  );
  const fieldsetsHandlers = {
    editMode, editSiteUnitType, editMethod, editSpeciesEnabled, editSpeciesChoice, editSpeciesText, resetSpeciesCriteria,
  };
  const prefsPair = $derived([preferences, fullPreferences, preferenceView, fullPreferenceView] as const);
  const actionBarModel = $derived(ops.packActionBarModel(su, siteUnitType, barFlags, prefsPair));
  const undoShortPrefs = () => !workbookBusy && (cancel(), preferences?.undo());
  const selectNormalShortPrefs = () => !workbookBusy && (cancel(), preferences?.selectNormalSU(), editSiteUnitType(1));
  const actionBarHandlers = {
    onSavePreferences: savePreferences, onUndoPreferences: undoShortPrefs, onSelectNormalSU: selectNormalShortPrefs,
    onAcknowledgePreferences: () => !workbookBusy && preferences?.acknowledge(),
    onLoadFullPreferences: loadFullPreferences, onSaveFullPreferences: saveFullPreferences,
    onAcknowledgeFullPreferences: () => !workbookBusy && fullPreferences?.acknowledge(),
  };

  async function quickExportSpreadsheet() {
    if (!contextId || quickExporting || quickRendering) return;
    [quickExporting, quickError] = [true, ''];
    const snap = $state.snapshot(quickDraft);
    quick.persistQuickDraft('summary_env', snap);
    const out = await quick.exportSummaryEnvSpreadsheet(contextId, snap, project, su);
    [quickExportResult, quickError, quickExporting] = [out.summary, out.error, false];
  }
  async function quickDisplayReport() {
    if (!contextId || quickExporting || quickRendering) return;
    [quickRendering, quickError] = [true, ''];
    const snap = $state.snapshot(quickDraft);
    quick.persistQuickDraft('summary_env', snap);
    const req = quick.buildSummaryEnvQuickRequest(snap, project, false);
    const out = await quick.runQuickHTMLDisplay({
      source: 'Summary Environment', project,
      invoke: () => EnvironmentReportService.RenderSummaryEnvironmentHTMLReport(contextId, req),
    });
    [quickHtmlReport, quickError, quickRendering] = [out.report, out.error, false];
  }

  onMount(() => {
    if (!preferences) void options();
    else if (!preferenceView?.draft && !preferenceBarrier) void loadPreferences();
    void quick.hydrateSummaryEnvQuickDraft(contextId, $state.snapshot(quickDraft)).then((next) => (quickDraft = next));
  });
  onDestroy(() => {
    unsubscribe?.();
    unsubscribeFull?.();
    unsubscribeSpecies?.();
    cancel();
  });
</script>

<section class="summary" data-site-unit-summary aria-label="Summary Environment">
  <CompactReportShell
    title="Summary Environment"
    subtitle="Site, soil, and vegetation cover summary statistics by unit."
    {contextId}
    {project}
    {su}
    busy={busy || workbookBusy}
    exporting={quickExporting}
    rendering={quickRendering}
    exportResult={quickExportResult}
    htmlReport={quickHtmlReport}
    errorMessage={quickError || preferenceView?.draftError || fullPreferenceView?.draftError || error}
    onExportSpreadsheet={quickExportSpreadsheet}
    onDisplayReport={quickDisplayReport}
    onCloseHtmlReport={() => (quickHtmlReport = null)}
  >
    {#snippet headerExtra()}
      <button
        type="button"
        class="btn-secondary"
        data-source-control="btnCreateReport"
        disabled={busy || workbookBusy || preferenceBarrier || speciesBarrier || !ready || !scopeAllowed}
        onclick={show}>Inline Preview</button
      >
      {#if busy}<button type="button" class="btn-secondary" data-summary-cancel onclick={cancel}>Cancel</button>{/if}
    {/snippet}
    {#snippet quickOptions()}
      <SiteUnitSummaryQuickOptions
        draft={quickDraft}
        {su}
        disabled={quickExporting || quickRendering}
        onChange={(next) => (quickDraft = next)}
      />
    {/snippet}
    {#snippet advanced()}
      <div class="sticky-actions">
        {#if preferences}
          <button
            data-summary-preferences-load
            disabled={workbookBusy || !!preferenceView?.busy || !!preferenceView?.blocked}
            onclick={loadPreferences}>Load saved summary options</button
          >
        {:else}
          <button data-summary-options-reload disabled={busy || workbookBusy} onclick={options}
            >Reload summary options</button
          >
        {/if}
      </div>
      <SiteUnitSummaryFieldsets model={fieldsetsModel} handlers={fieldsetsHandlers} />
      <SiteUnitSummaryActionBar model={actionBarModel} handlers={actionBarHandlers} />
      {#if mode === 'layer' && !speciesView?.enabled}
        <SiteUnitSummaryWorkbookPanel
          owner={{ contextId, project, projectPath, su, suPath }} {method} {siteUnitType} allowConfiguredScope={true}
          disabled={busy || preferenceBarrier || speciesBarrier || !ready || !scopeAllowed}
          onBusyChange={(held) => { workbookBusy = held; reportBusy(); }}
        />
      {:else if mode === 'lifeform' || mode === 'strata' || speciesView?.enabled}
        <SiteUnitSummaryWorkbookPanel
          owner={{ contextId, project, projectPath, su, suPath }} {method} {siteUnitType} allowConfiguredScope={true}
          {extendedOptions} disabled={busy || preferenceBarrier || speciesBarrier || !ready || !scopeAllowed}
          onBusyChange={(held) => { workbookBusy = held; reportBusy(); }}
        />
      {/if}
    {/snippet}
    {#snippet results()}
      {#if preview}<SiteUnitSummaryResults {preview} {speciesPreview} />{/if}
    {/snippet}
  </CompactReportShell>
</section>

<style>
  .summary {
    display: grid;
    grid-template-columns: minmax(min(100%, 140px), 1fr);
    gap: 1rem;
    padding: 1rem;
    max-width: 90rem;
    margin: auto;
    background: var(--vpro-canvas);
    color: var(--vpro-ink);
    min-width: 0;
  }
  .sticky-actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    align-items: center;
  }
  .btn-secondary,
  .sticky-actions button {
    min-height: 2.35rem;
    border: 1px solid var(--vpro-navy);
    border-radius: 0.25rem;
    padding: 0.42rem 0.75rem;
    background: var(--vpro-surface);
    color: var(--vpro-navy);
    font-weight: 600;
    font-size: 0.82rem;
    cursor: pointer;
  }
  .btn-secondary:disabled,
  .sticky-actions button:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
  @media (max-width: 640px) {
    .summary {
      padding: 0.75rem;
    }
  }
</style>
