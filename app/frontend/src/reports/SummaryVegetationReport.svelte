<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { ImportExportService, VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
  import { ReadRequests } from '../shared/readRequests';
  import { projectState } from '../shared/state';
  import { notifications } from '../shell/notificationService.svelte';
  import SiteUnitExclusionFilter from '../classification/SiteUnitExclusionFilter.svelte';
  import { summaryVegetationSession, type SummaryVegetationPort } from './summaryVegetation';
  import type { SummaryWorkbookCalculation } from './summaryVegetationWorkbook';
  import { summaryVegetationPreferenceSession } from './summaryVegetationPreferences';
  import { summaryVegetationQualityPreferenceSession } from './summaryVegetationQualityPreferences';
  import { summaryVegetationPresentationPreferenceSession } from './summaryVegetationPresentationPreferences';
  import SummaryVegetationPeerPanels from './SummaryVegetationPeerPanels.svelte';
  import SummaryVegetationResultPanel from './SummaryVegetationResultPanel.svelte';
  import { summaryVegetationFieldListDesktop } from './summaryVegetationFieldListDesktop';
  import {
    summaryEnvironmentalDesktop, summaryEnvironmentalEnabled,
    summaryEnvironmentalNumericEnabled, summaryEnvironmentalLifeformEnabled, summaryEnvironmentalPort,
  } from './summaryVegetationEnvironmentalDesktop';
  import type {
    SummaryEnvironmentalSession, SummaryEnvironmentalNumericSession, SummaryEnvironmentalLifeformSession,
  } from './summaryVegetationEnvironmental';

  let {
    contextId, project, projectPath, su, suPath,
    hierarchy = '', operationHeld: operationHeldProp = false,
    onBusyChange, onExclusionBusyChange,
  }: {
    contextId: string; project: string; projectPath: string; su: string; suPath: string;
    hierarchy?: string; operationHeld?: boolean;
    onBusyChange: (busy: boolean) => void;
    onExclusionBusyChange?: (value: boolean) => void;
  } = $props();

  const effectiveHierarchy = $derived(
    (hierarchy && hierarchy !== 'None' ? hierarchy : '') ||
      ($projectState?.activeHierarchy && $projectState.activeHierarchy !== 'None' ? $projectState.activeHierarchy : '') ||
      'None',
  );
  const enabled = true;
  const reads = new ReadRequests();
  function ownedContext() { return { contextId, project, projectPath, su, suPath }; }
  const session = summaryVegetationSession(ownedContext());
  let environmentalHeld = $state(false);
  let workbookHeld = $state(false);
  const operationHeld = $derived(operationHeldProp || environmentalHeld || workbookHeld);
  let environmentalSession = $state.raw<
    SummaryEnvironmentalSession | SummaryEnvironmentalNumericSession | SummaryEnvironmentalLifeformSession | null
  >(null);
  let environmentalError = $state('');
  const canInspectEnvironmental = untrack(() => {
    const o = ownedContext();
    return Boolean(
      summaryEnvironmentalEnabled && o.contextId && o.project && o.projectPath &&
        o.su && o.su !== 'None' && o.su !== 'USysSuTableDynamic' && o.suPath,
    );
  });
  if (canInspectEnvironmental) {
    try {
      environmentalSession = summaryEnvironmentalDesktop.session(ownedContext());
    } catch (cause) {
      const envErr = `Combined environmental inspection unavailable: ${String(cause)}`;
      environmentalError = envErr;
      notifications.error('Summary Vegetation environmental inspection unavailable', envErr, {
        category: 'reports',
        source: 'Summary Vegetation',
        contextTag: untrack(() => (typeof project === 'string' && project) || (effectiveHierarchy !== 'None' ? effectiveHierarchy : undefined)),
      });
    }
  }
  const preferences = summaryVegetationPreferenceSession?.(ownedContext()) ?? null;
  const quality = summaryVegetationQualityPreferenceSession?.(ownedContext()) ?? null;
  const presentation = summaryVegetationPresentationPreferenceSession?.(ownedContext()) ?? null;
  const fieldList = summaryVegetationFieldListDesktop;
  const fieldListScopeAvailable = fieldList.contextAvailable(ownedContext());
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
  const port: SummaryVegetationPort = {
    preview: (avg, disp) => reads.track(VegetationReportService.PreviewSummaryVegetation(contextId, avg, disp)),
    previewClass: (avg, disp, cls) => reads.track(VegetationReportService.PreviewSummaryVegetationClass(contextId, avg, disp, cls)),
    previewGrouped: (avg, grp) => reads.track(VegetationReportService.PreviewSummaryVegetationGrouped(contextId, avg, grp)),
    previewGroupedDisplay: (avg, grp, disp, cls) => reads.track(VegetationReportService.PreviewSummaryVegetationGroupedDisplay(contextId, avg, grp, disp, cls)),
    previewConfigured: reqJSON => reads.track(VegetationReportService.PreviewSummaryVegetationConfigured(contextId, reqJSON)),
    previewWithPreferences: () => reads.track(VegetationReportService.PreviewSummaryVegetationWithPreferences(contextId)),
    cancel: () => reads.cancelAll(),
    validationYield: () => new Promise(resolve => setTimeout(resolve, 0)),
  };
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
  let lastViewError = '';
  let lastPrefReadError = '';
  let lastPrefError = '';
  let notifiedPrefReceipts = 0;
  let lastFieldListReadError = '';

  function reportContextTag() {
    return (typeof project === 'string' && project) || (typeof effectiveHierarchy === 'string' && effectiveHierarchy !== 'None' ? effectiveHierarchy : undefined);
  }

  function syncReportNotifications() {
    const opts = { category: 'reports' as const, source: 'Summary Vegetation', contextTag: reportContextTag() };
    const vsErr = viewState?.error ?? '';
    if (vsErr && vsErr !== lastViewError) notifications.error('Summary Vegetation preview failed', vsErr, opts);
    lastViewError = vsErr;
    const pv = preferences?.view();
    if (pv) {
      const receipts = pv.receipts ?? [];
      if (receipts.length < notifiedPrefReceipts) notifiedPrefReceipts = 0;
      for (let i = notifiedPrefReceipts; i < receipts.length; i++) {
        const r = receipts[i];
        if (r.kind === 'known') {
          if (r.outcome.committed && !r.outcome.errorMessage) {
            notifications.success('Summary Vegetation options saved', r.outcome.changed ? 'Saved summary options.' : 'No option changes.', opts);
          } else if (r.outcome.committed) {
            notifications.warning('Summary Vegetation options saved with warning', r.outcome.errorMessage, opts);
            lastPrefError = r.outcome.errorMessage;
          } else if (r.outcome.errorMessage) {
            notifications.error('Summary Vegetation options save failed', r.outcome.errorMessage, opts);
            lastPrefError = r.outcome.errorMessage;
          } else {
            notifications.info('Summary Vegetation options unchanged', 'No option changes were needed.', opts);
          }
        }
      }
      notifiedPrefReceipts = receipts.length;
      const pvReadErr = pv.readError ?? '';
      if (pvReadErr && pvReadErr !== lastPrefReadError) notifications.error('Summary Vegetation options load failed', pvReadErr, opts);
      lastPrefReadError = pvReadErr;
      const pvErr = pv.error ?? '';
      if (pvErr && pvErr !== lastPrefError) notifications.error('Summary Vegetation options failed', pvErr, opts);
      lastPrefError = pvErr;
    }
    const flErr = fieldListState?.readError ?? '';
    if (flErr && flErr !== lastFieldListReadError) notifications.error('Summary Vegetation field list failed', flErr, opts);
    lastFieldListReadError = flErr;
  }

  function reportBusy() {
    onBusyChange(viewState.busy || (!preferences && !!viewState.draftError) || preferenceReadBusy ||
      (!!preferenceView && (preferenceView.busy || preferenceView.blocked || !!preferenceView.draftError)) ||
      qualityReadBusy || (!!qualityView && (qualityView.busy || qualityView.blocked || !!qualityView.draftError)) ||
      presentationReadBusy || (!!presentationView && (presentationView.busy || presentationView.blocked || !!presentationView.draftError)) ||
      fieldListHeld || environmentalHeld || workbookHeld);
  }
  const unsubscribe = session.subscribe(() => { viewState = session.view(); syncReportNotifications(); reportBusy(); });
  const unsubscribeEnvironment = canInspectEnvironmental ? summaryEnvironmentalDesktop.subscribe(() => {
    environmentalHeld = summaryEnvironmentalDesktop.activity().busy;
    reportBusy();
  }) : undefined;
  function syncPreferenceDraft() {
    if (!preferenceView?.initialized || viewState.busy) return;
    const d = preferenceView.draft;
    const group = Number(d.groupBy) + 10;
    const average = Number(d.average);
    const display = Number(d.display);
    const show = Number(d.showClass);
    if (viewState.groupAndOrder !== group || viewState.average !== average || viewState.display !== display || viewState.showClass !== show) {
      session.edit(average, display, show, group);
    }
  }
  const unsubscribePreferences = preferences?.subscribe(() => {
    preferenceView = preferences.view(); syncPreferenceDraft(); syncReportNotifications(); reportBusy();
  });
  const unsubscribeQuality = quality?.subscribe(() => { qualityView = quality.view(); reportBusy(); });
  const unsubscribePresentation = presentation?.subscribe(() => { presentationView = presentation.view(); reportBusy(); });
  const unsubscribeFieldList = fieldListScopeAvailable ? fieldList.subscribe(() => {
    fieldListState = fieldList.state(ownedContext());
    const activity = fieldList.activity();
    fieldListBusy = activity.busy;
    fieldListHeld = activity.busy || activity.blocked;
    syncReportNotifications();
    reportBusy();
  }) : undefined;
  syncReportNotifications();

  async function loadFieldList() {
    if (!fieldListScopeAvailable || fieldListPeerDisabled || fieldListPeerValidation || fieldListState?.readBusy) return;
    fieldListError = '';
    try { await fieldList.load(ownedContext()); } catch (cause) {
      fieldListError = String(cause);
      notifications.error('Summary Vegetation field list failed', fieldListError, { category: 'reports', source: 'Summary Vegetation', contextTag: reportContextTag() });
    }
  }
  function dismissInitialFieldListReadError() {
    if (!fieldListScopeAvailable || !fieldListState?.canDismissInitialReadError) return;
    fieldListError = '';
    try { fieldList.dismissInitialReadError(ownedContext()); } catch (cause) {
      fieldListError = String(cause);
      notifications.error('Summary Vegetation field list acknowledgement failed', fieldListError, { category: 'reports', source: 'Summary Vegetation', contextTag: reportContextTag() });
    }
  }
  const presentationMutationHeld = $derived(presentationReadBusy || (!!presentationView && (presentationView.busy || presentationView.blocked)));
  const presentationInvalid = $derived(!!presentationView?.draftError || !!presentationView?.authorityUnknown || !!presentationView?.readError);
  const workbookConstancy = $derived(!!presentationView?.initialized && presentationView.draft?.constancy === true);
  const qualityMutationHeld = $derived(qualityReadBusy || (!!qualityView && (qualityView.busy || qualityView.blocked)));
  const qualityInvalid = $derived(!!qualityView?.draftError || !!qualityView?.authorityUnknown || !!qualityView?.readError);
  const qualityUnavailable = $derived(!!quality && (!qualityView?.saved || qualityInvalid));
  const unavailableScope = $derived(!contextId || (unitScope === 'su' && (su === 'None' || su === 'USysSuTableDynamic')) || (unitScope === 'field' && !unitField.trim()));
  const hierarchyHeaderEnabled = $derived(!!presentationView?.draft?.hierarchyHeader);
  const effectiveCombineVariants = $derived(combineVariants || !!presentationView?.draft?.combineVariants);
  const savedPresentation = $derived.by(() => {
    const d = presentationView?.initialized ? presentationView.draft : null;
    return d ? { title: d.title, includeEnv: d.includeEnv, createSummary: d.createSummary, showCommon: d.showCommon, showGuide: d.showGuide, constancy: d.constancy } : null;
  });
  const preferenceHeld = $derived(preferenceReadBusy || (!!preferenceView && (preferenceView.busy || preferenceView.blocked)));
  const preferenceInvalid = $derived(!!preferenceView?.draftError || !!preferenceView?.authorityUnknown || !!preferenceView?.readError);
  const fieldListPeerDisabled = $derived(operationHeld || viewState.busy || preferenceHeld || qualityMutationHeld || presentationMutationHeld);
  const fieldListPeerValidation = $derived(preferenceInvalid ? 'Resolve Summary options validation.' : qualityInvalid ? 'Resolve Summary quality validation.' : presentationInvalid ? 'Resolve Summary presentation validation.' : '');
  const fieldListEnabledFromPresentation = $derived(!!presentationView?.saved && !presentationInvalid && presentationView.draft?.includeEnv === true);
  const editHeld = $derived(!enabled || viewState.busy || operationHeld || fieldListBusy || preferenceHeld || qualityMutationHeld || presentationMutationHeld || (!!preferences && !preferenceView?.saved));
  const workbookCalculation = $derived<SummaryWorkbookCalculation>({
    average: viewState.average, display: workbookConstancy ? 1 : viewState.display, showClass: viewState.showClass,
    ...(workbookConstancy ? { groupAndOrder: 13, constancy: true as const } : viewState.groupAndOrder !== 11 ? { groupAndOrder: viewState.groupAndOrder } : {}),
    ...(unitScope !== 'su' ? { unitScope } : {}), ...(unitScope === 'field' && unitField.trim() ? { unitField: unitField.trim() } : {}),
    ...(unitScope === 'hierarchy' ? { breakpointPolicy } : {}), ...(hierarchyHeaderEnabled ? { hierarchyHeader: true } : {}),
    ...(effectiveCombineVariants ? { combineVariants: true } : {}), ...(lumpTable ? { lumpTable } : {}),
    ...(includeGoldstreamMetadata ? { includeGoldstreamMetadata: true } : {}),
  });

  function cancelPreferenceRead() {
    preferenceGeneration++; preferenceReads.cancelAll(); preferences?.cancelLoad();
    preferenceReadBusy = false; reportBusy();
  }
  async function loadPreferences() {
    if (!preferences || viewState.busy || operationHeld || fieldListHeld || preferenceHeld || qualityMutationHeld || qualityInvalid || presentationMutationHeld || presentationInvalid) return;
    cancelPreferenceRead();
    const request = preferenceGeneration;
    const token = preferences.beginLoad();
    preferenceReadError = ''; preferenceReadBusy = true; reportBusy();
    try {
      const value = await preferenceReads.track(VegetationReportService.GetSummaryVegetationPreferences(contextId));
      if (request !== preferenceGeneration) return;
      preferences.applyLoaded(value, token);
    } catch (cause) {
      if (request === preferenceGeneration) {
        preferences.rejectRead(cause);
        if (typeof syncReportNotifications === 'function') syncReportNotifications();
      }
    } finally {
      if (request === preferenceGeneration) { preferenceReadBusy = false; reportBusy(); }
    }
  }
  async function savePreferences() {
    if (!preferences || viewState.busy || operationHeld || fieldListHeld || preferenceHeld || preferenceInvalid || qualityMutationHeld || qualityInvalid || presentationMutationHeld || presentationInvalid) return;
    cancelPreferenceRead(); preferenceReadError = '';
    try {
      await preferences.save(value => VegetationReportService.SaveSummaryVegetationPreferences(contextId, JSON.stringify(value)));
      if (typeof syncReportNotifications === 'function') syncReportNotifications();
    } catch (cause) {
      preferenceReadError = String(cause);
      notifications.error('Summary Vegetation preferences save failed', preferenceReadError, {
        category: 'reports', source: 'Summary Vegetation',
        contextTag: (typeof project === 'string' && project) || (typeof effectiveHierarchy === 'string' && effectiveHierarchy !== 'None' ? effectiveHierarchy : undefined),
      });
    }
  }
  function editPreference(field: 'groupBy' | 'average' | 'display' | 'showClass', raw: string) {
    if (!preferences || editHeld) return;
    cancelPreferenceRead(); preferenceReadError = ''; preferences.editOption(field, raw);
  }
  function changeAverage(event: Event) {
    const raw = (event.currentTarget as HTMLSelectElement).value;
    if (preferences) { editPreference('average', raw); return; }
    const current = Number(raw);
    session.edit(current, viewState.display, viewState.showClass || 1, viewState.groupAndOrder);
  }
  function changeDisplay(event: Event) {
    const raw = (event.currentTarget as HTMLSelectElement).value;
    if (preferences) { editPreference('display', raw); return; }
    const current = Number(raw);
    session.edit(viewState.average, current, viewState.showClass || 1, viewState.groupAndOrder);
  }
  function changeShowClass(event: Event) {
    const raw = (event.currentTarget as HTMLSelectElement).value;
    if (preferences) { editPreference('showClass', raw); return; }
    const current = Number(raw);
    session.edit(viewState.average, viewState.display, current, viewState.groupAndOrder);
  }
  function changeGroup(event: Event) {
    const raw = (event.currentTarget as HTMLSelectElement).value;
    if (preferences) { editPreference('groupBy', String(Number(raw) - 10)); return; }
    const current = Number(raw);
    session.edit(viewState.average, viewState.display, viewState.showClass || 1, current);
  }
  async function refreshLumpTables() {
    if (!contextId || !ImportExportService?.DiscoverLumpTables) return;
    lumpDiscoveryError = '';
    try {
      const discovered = await reads.track(ImportExportService.DiscoverLumpTables(contextId, []));
      lumpTables = Array.from(new Set((discovered ?? []).map(item => (item?.name ?? '').trim()).filter((n): n is string => !!n)));
    } catch (cause) {
      lumpDiscoveryError = String(cause);
      notifications.error('Summary Vegetation lump table discovery failed', lumpDiscoveryError, { category: 'reports', source: 'Summary Vegetation', contextTag: reportContextTag() });
    }
  }
  function buildConfiguredRequestJSON(): string {
    const groupAndOrder = viewState.groupAndOrder;
    const showClass = viewState.display === 4 || viewState.display === 5 ? (viewState.showClass || 1) : 0;
    const showCommon = !!presentationView?.draft?.showCommon;
    const showGuide = !!presentationView?.draft?.showGuide;
    const references = showCommon || showGuide ? { showCommon, useGuideNames: showGuide } : undefined;
    return JSON.stringify({
      useSavedPreferences: false, unitScope,
      ...(unitScope === 'field' ? { unitField: unitField.trim() } : {}),
      hierarchyHeader: hierarchyHeaderEnabled,
      ...(unitScope === 'hierarchy' ? { breakpointPolicy } : {}),
      combineVariants: effectiveCombineVariants,
      ...(lumpTable ? { lumpTable } : {}),
      average: viewState.average, display: viewState.display, showClass,
      ...(groupAndOrder !== 11 ? { groupAndOrder } : {}),
      ...(references ? { references } : {}),
      ...(workbookConstancy ? { constancy: true } : {}),
      includeGoldstreamMetadata,
    });
  }
  async function previewReport() {
    exclusionSummaryText = '';
    const useConfigured = unitScope !== 'su' || hierarchyHeaderEnabled || effectiveCombineVariants || lumpTable !== '' || includeGoldstreamMetadata || !!qualityView?.saved?.enforce;
    const ctxTag = (typeof project === 'string' && project) || (typeof effectiveHierarchy === 'string' && effectiveHierarchy !== 'None' ? effectiveHierarchy : undefined);
    try {
      if (!useConfigured) await session.show(port);
      else await session.showConfigured(port, buildConfiguredRequestJSON());
      const next = session.view();
      if (next.error) notifications.error('Summary Vegetation preview failed', next.error, { category: 'reports', source: 'Summary Vegetation', contextTag: ctxTag });
    } catch (cause) {
      notifications.error('Summary Vegetation preview failed', String(cause), { category: 'reports', source: 'Summary Vegetation', contextTag: ctxTag });
    }
  }
  function normalizeExclusionSummaryPreview(raw: unknown): unknown {
    if (!raw || typeof raw !== 'object') return raw;
    const candidate = { ...(raw as Record<string, unknown>) };
    const hasRefs = !!candidate.references && typeof candidate.references === 'object';
    const refShowCommon = hasRefs && Boolean((candidate.references as Record<string, unknown>).showCommon);
    const grouped = typeof candidate.groupAndOrder === 'number' && candidate.groupAndOrder !== 11;
    if (hasRefs) {
      candidate.source = 'literal-normal-su-effective-references';
      candidate.ordering = refShowCommon ? 'literal-null-first-layer-species-common' : grouped ? 'literal-null-first-group-species' : 'literal-null-first-layer-species';
    } else {
      candidate.source = grouped ? 'literal-normal-su-grouped' : 'literal-normal-su-layer';
      candidate.ordering = grouped ? 'literal-null-first-group-species' : 'literal-null-first-layer-species';
    }
    return candidate;
  }
  async function previewWithPreferences() {
    exclusionSummaryText = '';
    const ctxTag = (typeof project === 'string' && project) || (typeof effectiveHierarchy === 'string' && effectiveHierarchy !== 'None' ? effectiveHierarchy : undefined);
    try {
      await session.showWithPreferences(port);
      const next = session.view();
      if (next.error) notifications.error('Summary Vegetation preview failed', next.error, { category: 'reports', source: 'Summary Vegetation', contextTag: ctxTag });
    } catch (cause) {
      notifications.error('Summary Vegetation preview failed', String(cause), { category: 'reports', source: 'Summary Vegetation', contextTag: ctxTag });
    }
  }
  onDestroy(() => {
    session.cancel(port); unsubscribe(); unsubscribePreferences?.(); unsubscribeQuality?.(); unsubscribePresentation?.();
    unsubscribeFieldList?.(); unsubscribeEnvironment?.(); if (fieldListScopeAvailable) fieldList.detach(ownedContext());
    cancelPreferenceRead(); onBusyChange(false);
  });
</script>

<section data-summary-vegetation aria-label="Summary Vegetation" class="summary-vegetation">
  <header class="sticky top-0 z-20 bg-white/95 backdrop-blur-xs py-2 border-b border-vpro-border report-sticky-bar" data-report-sticky-bar>
    <h1>Summary Vegetation</h1>
    <div class="actions">
      <button
        onclick={previewReport}
        disabled={!enabled || unavailableScope || viewState.busy || operationHeld || fieldListHeld ||
          preferenceHeld || preferenceInvalid || qualityMutationHeld || qualityUnavailable ||
          presentationMutationHeld || presentationInvalid || !!viewState.draftError ||
          (!!preferences && !preferenceView?.initialized)}
        data-summary-preview>Preview Summary Vegetation</button>
      <button
        type="button"
        onclick={previewWithPreferences}
        disabled={!enabled || !contextId || !su || su === 'None' || !suPath || viewState.busy ||
          operationHeld || fieldListHeld || preferenceHeld || qualityMutationHeld || presentationMutationHeld}
        data-summary-preview-preferences>Preview with Saved Preferences</button>
      {#if viewState.busy}<button onclick={() => session.cancel(port)} data-summary-cancel>Cancel preview</button>{/if}
    </div>
  </header>
  {#if viewState.draftError}<p role="alert" class="error">{viewState.draftError}</p>{/if}
  {#if preferenceView?.draftError}<p role="alert" class="error">{preferenceView.draftError}</p>{/if}
  <p class="owner">Project: {project}<br />{projectPath}<br />Current Site Unit Table: {su}<br />{suPath}</p>
  {#if unavailableScope}
    <p class="scope-guidance" role="status">
      {unitScope === 'field'
        ? 'Enter an environment field name (such as SiteUnit or SubZone) to group plots.'
        : 'Select a Site Unit table in the sidebar, or choose Whole Project or Hierarchy Breakpoints (~).'}
    </p>
  {/if}
  <div class="options">
    <label>Summary Report Units
      <select aria-label="Summary Report Units" value={unitScope}
        onchange={event => { unitScope = (event.currentTarget as HTMLSelectElement).value as 'su' | 'hierarchy' | 'none' | 'field'; }}
        disabled={editHeld} data-summary-unit-scope data-source-control="optUnitScope">
        <option value="su">Current Site Unit Table</option>
        <option value="hierarchy">Hierarchy Breakpoints (~)</option>
        <option value="none">Whole Project (None)</option>
        <option value="field">Field-Derived Units</option>
      </select>
    </label>
    {#if unitScope === 'hierarchy'}
      <label>Hierarchy Breakpoint Policy
        <select value={breakpointPolicy} onchange={event => { breakpointPolicy = (event.currentTarget as HTMLSelectElement).value as 'lowest' | 'highest'; }} disabled={editHeld} data-summary-breakpoint-policy>
          <option value="lowest">Lowest (~) Breakpoint</option><option value="highest">Highest (~) Breakpoint</option>
        </select>
      </label>
    {:else if unitScope === 'field'}
      <label>Environment Unit Field
        <input type="text" value={unitField} oninput={event => { unitField = event.currentTarget.value; }} placeholder="e.g. SiteUnit or SubZone" disabled={editHeld} data-summary-unit-field />
      </label>
    {/if}
    <label>Species Lumping Table
      <div class="lump-picker">
        <select value={lumpTable} onchange={event => { lumpTable = (event.currentTarget as HTMLSelectElement).value; }} disabled={editHeld} data-summary-lump-table>
          <option value="">None (unlumped species)</option>
          {#each lumpTables as tableName}<option value={tableName}>{tableName}</option>{/each}
        </select>
        <button type="button" onclick={refreshLumpTables} disabled={editHeld || !contextId} data-summary-lump-refresh>Discover</button>
      </div>
    </label>
    <label>Group by
      <select value={viewState.groupAndOrder} onchange={changeGroup} disabled={editHeld} data-summary-group data-source-control="rptSvGroupBy">
        <option value={11}>Layer</option><option value={12} disabled={viewState.display === 2}>Strata</option>
        <option value={13} disabled={viewState.display === 2}>Lifeform</option><option value={14}>None</option>
      </select>
    </label>
    <label>Display Values
      <select value={viewState.display} onchange={changeDisplay} disabled={editHeld} data-summary-display data-source-control="rptSvValueEq">
        <option value={1}>% Presence and % Cover</option>
        <option value={2} disabled={viewState.groupAndOrder === 12 || viewState.groupAndOrder === 13}>Presence Class and Significance Class</option>
        <option value={3}>Presence Class and % Cover</option>
        <option value={6}>% Cover</option><option value={4}>Prominence Class</option><option value={5}>Goldstream Class</option>
      </select>
    </label>
    <label>Show
      <select value={viewState.showClass} onchange={changeShowClass} disabled={editHeld || viewState.display <= 3} data-summary-show data-source-control="OptShowClassValue">
        <option value={1}>Class (historical default 1)</option><option value={10}>Class</option><option value={20}>Value</option>
      </select>
    </label>
    <label>Calculate
      <select value={viewState.average} onchange={changeAverage} disabled={editHeld} data-summary-average data-source-control="rptSvAvgType">
        <option value={1}>By n Plots</option><option value={2}>Characteristic</option>
      </select>
    </label>
  </div>
  <div class="scope-toggles">
    <label class="checkbox-inline">
      <input type="checkbox" checked={combineVariants} onchange={event => { combineVariants = event.currentTarget.checked; }} disabled={editHeld} data-summary-combine-variants data-source-control="SVSubSppAsSpp" />
      Roll up subspecies and varieties into parent species
    </label>
    <label class="checkbox-inline">
      <input type="checkbox" checked={includeGoldstreamMetadata} onchange={event => { includeGoldstreamMetadata = event.currentTarget.checked; }} disabled={editHeld} data-summary-goldstream-metadata />
      Include Goldstream cover-class metadata
    </label>
  </div>
  <SummaryVegetationPeerPanels
    owner={{ contextId, project, projectPath, su, suPath }}
    {preferences} {preferenceView} {preferenceReadBusy} {preferenceHeld} {preferenceInvalid}
    {quality} {qualityView} {qualityMutationHeld} {qualityInvalid} {qualityUnavailable}
    {presentation} {presentationView} {presentationMutationHeld} {presentationInvalid}
    fieldListEnabled={fieldList.enabled} {fieldListScopeAvailable} {fieldListState} {fieldListHeld} {fieldListBusy}
    {fieldListPeerDisabled} {fieldListPeerValidation} {fieldListEnabledFromPresentation}
    {environmentalSession}
    environmentalPort={summaryEnvironmentalPort}
    environmentalNumericEnabled={summaryEnvironmentalNumericEnabled}
    environmentalLifeformEnabled={summaryEnvironmentalLifeformEnabled}
    {environmentalHeld} {operationHeldProp} {operationHeld} {workbookHeld} {unavailableScope}
    viewBusy={viewState.busy} viewDraftError={viewState.draftError}
    calculation={workbookCalculation} {savedPresentation}
    onLoadPreferences={loadPreferences}
    onSavePreferences={savePreferences}
    onUndoPreferences={() => { cancelPreferenceRead(); preferences?.undo(); }}
    onAcknowledgePreferences={() => preferences?.acknowledge()}
    onCancelPreferenceRead={cancelPreferenceRead}
    onQualityReadBusyChange={value => { qualityReadBusy = value; reportBusy(); }}
    onPresentationReadBusyChange={value => { presentationReadBusy = value; reportBusy(); }}
    onDismissInitialFieldListReadError={dismissInitialFieldListReadError}
    onLoadFieldList={loadFieldList}
    onCancelFieldListRead={() => fieldList.cancel(ownedContext())}
    onFieldListStateChange={() => reportBusy()}
    onEnvironmentalBusyChange={() => { environmentalHeld = summaryEnvironmentalDesktop.activity().busy; reportBusy(); }}
    onWorkbookPreferencesLoaded={opts => {
      if (opts.unitScope) unitScope = opts.unitScope;
      if (opts.unitField !== undefined) unitField = opts.unitField;
      if (opts.breakpointPolicy) breakpointPolicy = opts.breakpointPolicy;
      if (opts.combineVariants !== undefined) combineVariants = opts.combineVariants;
      if (opts.lumpTable !== undefined) lumpTable = opts.lumpTable;
      if (opts.includeGoldstreamMetadata !== undefined) includeGoldstreamMetadata = opts.includeGoldstreamMetadata;
    }}
    onWorkbookBusyChange={held => { workbookHeld = held; reportBusy(); }}
  />
  <div class="exclusion-section table-scroll">
    <SiteUnitExclusionFilter {contextId} {su} hierarchy={effectiveHierarchy} reportMode="summary"
      average={viewState.average} display={viewState.display}
      showClass={viewState.display === 4 || viewState.display === 5 ? (viewState.showClass || 1) : 0}
      groupAndOrder={viewState.groupAndOrder}
      onBusyChange={onExclusionBusyChange}
      onSummaryPreview={result => {
        exclusionSummaryText = `${result.exclusions.retainedUnits?.length ?? 0} units retained (${result.exclusions.excludedUnits?.length ?? 0} excluded; ${result.exclusions.retainedPlots}/${result.exclusions.totalPlotsBefore} plots)`;
        void session.applyExternalPreview(normalizeExclusionSummaryPreview(result.preview), port);
      }} />
    {#if exclusionSummaryText}<p role="status" data-summary-exclusion-status>{exclusionSummaryText}</p>{/if}
  </div>
  <p class="guidance">
    Preview reflects the options selected above, and your saved defaults only change when you click Save.
    Title and layout settings in Presentation Options apply to exported workbooks and “Preview with Saved Preferences” rather than the standard crosstab preview.
    Presence Class and Significance Class are available when grouped by Layer or None (not Strata or Lifeform).
  </p>
  <p class="guidance">Presence values are shown as proportions from 0 to 1 (for example, 0.75 for 75% of plots in a unit).</p>
  {#if viewState.preview && !qualityInvalid}
    <SummaryVegetationResultPanel {project} {su} preview={viewState.preview} />
  {/if}
</section>

<style>
  .summary-vegetation { display: grid; grid-template-columns: minmax(0, 1fr); gap: 1rem; padding: 1rem; background: var(--vpro-canvas); color: var(--vpro-ink); min-width: 0; }
  .report-sticky-bar { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: .75rem; padding-inline: .75rem; border-radius: .35rem; }
  .summary-vegetation h1 { margin: 0; color: var(--vpro-navy); }
  .options { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 280px), 1fr)); gap: 1rem; background: var(--vpro-surface); padding: .9rem; border: 1px solid var(--vpro-border); border-radius: .5rem; }
  .scope-toggles { display: flex; flex-wrap: wrap; gap: 1rem; padding: .65rem .9rem; background: var(--vpro-surface); border: 1px solid var(--vpro-border); border-radius: .5rem; }
  .checkbox-inline { display: flex; flex-direction: row; align-items: center; gap: .5rem; font-weight: 500; }
  .lump-picker { display: flex; gap: .5rem; align-items: stretch; min-width: 0; }
  .lump-picker select { flex: 1; min-width: 0; }
  label { display: flex; flex-direction: column; gap: .35rem; min-width: 0; color: var(--vpro-ink); font-weight: 500; }
  select, input:not([type="checkbox"]) { box-sizing: border-box; width: 100%; min-width: 0; padding: .5rem; border: 1px solid var(--vpro-border); border-radius: .25rem; background: var(--vpro-surface); color: var(--vpro-ink); }
  .owner { overflow-wrap: anywhere; color: var(--vpro-ink-secondary); }
  .scope-guidance { margin: 0; padding: .6rem .85rem; border-left: 4px solid var(--vpro-navy); background: var(--vpro-surface); color: var(--vpro-ink); border-radius: .25rem; }
  .exclusion-section { display: grid; grid-template-columns: minmax(0, 1fr); gap: .75rem; min-width: 0; overflow-wrap: anywhere; }
  .actions { display: flex; flex-wrap: wrap; gap: .75rem; align-items: center; }
  button { min-height: 2.5rem; padding: .5rem .85rem; border: 1px solid var(--vpro-navy); border-radius: .25rem; background: var(--vpro-navy); color: var(--vpro-surface); font-weight: 600; cursor: pointer; }
  button:hover:not(:disabled) { background: var(--vpro-navy-dark); border-color: var(--vpro-navy-dark); }
  button:disabled { opacity: .6; cursor: not-allowed; }
  .error { color: var(--vpro-error); font-weight: 600; }
  .guidance { margin: 0; font-size: .9rem; color: var(--vpro-ink-secondary); }
  .table-scroll { overflow-x: auto; max-width: 100%; }
  @media (max-width: 960px) { .summary-vegetation { padding: .75rem; } .lump-picker { flex-direction: column; } }
</style>
