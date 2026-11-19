<script lang="ts">
  import { onMount, onDestroy, untrack } from 'svelte';
  import { EnvironmentReportService } from '../../bindings/github.com/boostao/vpro/app';
  import { ReadRequests } from '../shared/readRequests';
  import { validateSiteUnitSummary, validateSiteUnitSummaryOptions, type ValidatedSiteUnitSummary, type SiteUnitSummaryMode } from './siteUnitSummary';
  import { reportCellText } from './longEnvironmentReport';
  import { siteUnitSummaryPreferencesSession, siteUnitSummaryFullPreferencesSession, type SummaryFullPreferenceValues } from './siteUnitSummaryPreferences';
  import SiteUnitSummaryWorkbookPanel from './SiteUnitSummaryWorkbookPanel.svelte';
  import { summarySpeciesCriteria, validateSummarySpecies, type ValidatedSummarySpecies } from './siteUnitSummarySpecies';
  import { extendedSummaryWorkbookPublicationSession, type ExtendedSummaryWorkbookOptions } from './siteUnitSummaryExtendedWorkbook';
  import { notifications } from '../shell/notificationService.svelte';

  let { contextId, project, projectPath, su, suPath, onBusyChange }: {
    contextId: string; project: string; projectPath: string; su: string; suPath: string;
    onBusyChange: (busy: boolean) => void;
  } = $props();
  let method = $state<number | null>(null);
  let siteUnitType = $state<number | null>(null);
  let ready = $state(false);
  let busy = $state(false);
  let workbookBusy = $state(false);
  let error = $state('');
  let preview = $state<ValidatedSiteUnitSummary | null>(null);
  const extendedWorkbookEnabled = true;
  const extendedAuthority = untrack(() => extendedWorkbookEnabled
    ? extendedSummaryWorkbookPublicationSession({ contextId, project, projectPath, su, suPath }) : null);
  const retainedOptions = extendedAuthority?.view().blocked ? extendedAuthority.requestedOptions() : null;
  let mode = $state<SiteUnitSummaryMode>(retainedOptions?.orderBy === 2 ? 'lifeform' : retainedOptions?.orderBy === 3 ? 'strata' : 'layer');
  const lifeformsEnabled = true;
  const speciesEnabled = true;
  const ownedCriteria = () => summarySpeciesCriteria({ contextId, project, projectPath, su, suPath });
  const criteria = speciesEnabled ? ownedCriteria() : null;
  let speciesView = $state(criteria?.view() ?? null);
  let speciesPreview = $state<ValidatedSummarySpecies | null>(null);
  const speciesBarrier = $derived(!!speciesView?.error);
  const extendedOptions = $derived.by((): ExtendedSummaryWorkbookOptions | null => {
    if ((method !== 1 && method !== 2) || speciesBarrier) return null;
    if (speciesView?.enabled && criteria) return { ...criteria.request(method, mode), includeSpecies: 1 };
    if (mode === 'lifeform') return { method, orderBy: 2, includeSpecies: 0, coverCalculation: 1,
      andOr: 1, presenceGreaterThan: 0, coverGreaterThan: 0 };
    if (mode === 'strata') return { method, orderBy: 3, includeSpecies: 1, coverCalculation: 1,
      andOr: 1, presenceGreaterThan: 0, coverGreaterThan: 0 };
    return null;
  });
  const reads = new ReadRequests();
  let generation = 0;
  const preferencesEnabled = true;
  const ownedPreferences = () => siteUnitSummaryPreferencesSession({ contextId, project, projectPath, su, suPath });
  const preferences = preferencesEnabled ? ownedPreferences() : null;
  const fullPreferences = preferencesEnabled && typeof siteUnitSummaryFullPreferencesSession === 'function'
    ? untrack(() => siteUnitSummaryFullPreferencesSession({ contextId, project, projectPath, su, suPath })) : null;
  let preferenceView = $state(preferences?.view() ?? null);
  let fullPreferenceView = $state(fullPreferences?.view() ?? null);
  const preferenceBarrier = $derived((!!preferenceView && (preferenceView.busy || preferenceView.blocked ||
    preferenceView.authorityUnknown || !!preferenceView.draftError)) ||
    (!!fullPreferenceView && (fullPreferenceView.busy || fullPreferenceView.blocked ||
      fullPreferenceView.authorityUnknown || !!fullPreferenceView.draftError)));
  const scopeAllowed = $derived(siteUnitType === 3 || (su !== 'None' && (siteUnitType === 2 || (siteUnitType === 1 && su !== 'USysSuTableDynamic'))));
  let lastPrefError = '';
  let notifiedPrefReceipts = 0;
  let lastFullPrefError = '';
  let notifiedFullPrefReceipts = 0;
  let lastSpeciesError = '';
  function syncSpeciesNotifications() {
    const err = criteria?.view()?.error ?? '';
    if (err && err !== lastSpeciesError && typeof notifications !== 'undefined') {
      notifications.error('Summary Environment species criteria invalid', err, {
        category: 'reports',
        source: 'Summary Environment',
        contextTag: (typeof project === 'string' && project) || undefined,
      });
    }
    lastSpeciesError = err;
  }
  function syncPreferenceNotifications() {
    const view = preferences?.view();
    if (!view) return;
    const ctxTag = (typeof project === 'string' && project) || undefined;
    const receipts = view.receipts ?? [];
    if (receipts.length < notifiedPrefReceipts) notifiedPrefReceipts = 0;
    for (let i = notifiedPrefReceipts; i < receipts.length; i++) {
      const receipt = receipts[i];
      if (receipt.kind === 'known' && typeof notifications !== 'undefined') {
        if (receipt.outcome.committed && !receipt.outcome.errorMessage) {
          notifications.success('Summary Environment options saved', receipt.outcome.changed ? 'Saved summary preferences.' : 'No option changes.', {
            category: 'reports', source: 'Summary Environment', contextTag: ctxTag,
          });
        } else if (receipt.outcome.committed) {
          notifications.warning('Summary Environment options saved with warning', receipt.outcome.errorMessage, {
            category: 'reports', source: 'Summary Environment', contextTag: ctxTag,
          });
          lastPrefError = receipt.outcome.errorMessage;
        } else if (receipt.outcome.errorMessage) {
          notifications.error('Summary Environment options save failed', receipt.outcome.errorMessage, {
            category: 'reports', source: 'Summary Environment', contextTag: ctxTag,
          });
          lastPrefError = receipt.outcome.errorMessage;
        } else {
          notifications.info('Summary Environment options unchanged', 'No option changes were needed.', {
            category: 'reports', source: 'Summary Environment', contextTag: ctxTag,
          });
        }
      }
    }
    notifiedPrefReceipts = receipts.length;
    const err = view.error ?? '';
    if (err && err !== lastPrefError && typeof notifications !== 'undefined') {
      notifications.error('Summary Environment options failed', err, {
        category: 'reports', source: 'Summary Environment', contextTag: ctxTag,
      });
    }
    lastPrefError = err;
  }
  function syncFullPreferenceNotifications() {
    const view = fullPreferences?.view();
    if (!view) return;
    const ctxTag = (typeof project === 'string' && project) || undefined;
    const receipts = view.receipts ?? [];
    if (receipts.length < notifiedFullPrefReceipts) notifiedFullPrefReceipts = 0;
    for (let i = notifiedFullPrefReceipts; i < receipts.length; i++) {
      const receipt = receipts[i];
      if (receipt.kind === 'known' && typeof notifications !== 'undefined') {
        if (receipt.outcome.committed && !receipt.outcome.errorMessage) {
          notifications.success('Summary Environment full preferences saved', receipt.outcome.changed ? 'Saved full SE* preferences.' : 'No preference changes.', {
            category: 'reports', source: 'Summary Environment', contextTag: ctxTag,
          });
        } else if (receipt.outcome.committed) {
          notifications.warning('Summary Environment full preferences saved with warning', receipt.outcome.errorMessage, {
            category: 'reports', source: 'Summary Environment', contextTag: ctxTag,
          });
          lastFullPrefError = receipt.outcome.errorMessage;
        } else if (receipt.outcome.errorMessage) {
          notifications.error('Summary Environment full preferences save failed', receipt.outcome.errorMessage, {
            category: 'reports', source: 'Summary Environment', contextTag: ctxTag,
          });
          lastFullPrefError = receipt.outcome.errorMessage;
        } else {
          notifications.info('Summary Environment full preferences unchanged', 'No preference changes were needed.', {
            category: 'reports', source: 'Summary Environment', contextTag: ctxTag,
          });
        }
      }
    }
    notifiedFullPrefReceipts = receipts.length;
    const err = view.error ?? '';
    if (err && err !== lastFullPrefError && typeof notifications !== 'undefined') {
      notifications.error('Summary Environment full preferences failed', err, {
        category: 'reports', source: 'Summary Environment', contextTag: ctxTag,
      });
    }
    lastFullPrefError = err;
  }
  function reportBusy() { onBusyChange(busy || preferenceBarrier || workbookBusy || speciesBarrier); }
  const unsubscribeSpecies = criteria?.subscribe(() => {
    speciesView = criteria.view(); preview = null; speciesPreview = null; syncFullDraftFromUI(); syncSpeciesNotifications(); reportBusy();
  });
  const unsubscribe = preferences?.subscribe(() => {
    preferenceView = preferences.view();
    if (!fullPreferenceView?.draft) {
      method = preferenceView.draft?.method ?? null;
      siteUnitType = preferenceView.draft?.siteUnitType ?? null;
    }
    const effectiveType = siteUnitType ?? preferenceView.draft?.siteUnitType ?? 0;
    const allowed = effectiveType === 3 || (su !== 'None' && (effectiveType === 2 || (effectiveType === 1 && su !== 'USysSuTableDynamic')));
    ready = (method === 1 || method === 2) && [1, 2, 3].includes(effectiveType) && allowed && !preferenceView.authorityUnknown;
    preview = null; speciesPreview = null;
    syncPreferenceNotifications();
    reportBusy();
  });
  const unsubscribeFull = fullPreferences?.subscribe(() => {
    fullPreferenceView = fullPreferences.view();
    if (fullPreferenceView.draft) {
      method = fullPreferenceView.draft.method;
      siteUnitType = fullPreferenceView.draft.siteUnitType;
    }
    const effectiveType = siteUnitType ?? 0;
    const allowed = effectiveType === 3 || (su !== 'None' && (effectiveType === 2 || (effectiveType === 1 && su !== 'USysSuTableDynamic')));
    ready = (method === 1 || method === 2) && [1, 2, 3].includes(effectiveType) && allowed && !fullPreferenceView.authorityUnknown;
    syncFullPreferenceNotifications();
    reportBusy();
  });
  syncSpeciesNotifications();
  syncPreferenceNotifications();
  syncFullPreferenceNotifications();
  function syncFullDraftFromUI() {
    if (!fullPreferences || !fullPreferenceView?.draft || fullPreferenceView.busy || fullPreferenceView.blocked) return;
    if (method !== 1 && method !== 2) return;
    const orderBy = mode === 'layer' ? 1 : mode === 'lifeform' ? 2 : 3;
    const nextPatch: Partial<SummaryFullPreferenceValues> = {
      method,
      siteUnitType: [1, 2, 3].includes(siteUnitType ?? 0) ? (siteUnitType as number) : fullPreferenceView.draft.siteUnitType,
      includeSpecies: speciesView?.enabled ? 1 : 0,
      orderBy,
    };
    if (speciesView && !speciesView.error) {
      nextPatch.coverCalculation = speciesView.coverCalculation;
      nextPatch.andOr = speciesView.andOr;
      const pNum = Number(speciesView.presenceGreaterThan);
      const cNum = Number(speciesView.coverGreaterThan);
      if (Number.isSafeInteger(pNum) && pNum >= 0 && pNum <= 32767) nextPatch.presenceGreaterThan = pNum;
      if (Number.isSafeInteger(cNum) && cNum >= 0 && cNum <= 32767) nextPatch.coverGreaterThan = cNum;
    }
    fullPreferences.edit(nextPatch);
  }
  function applyFullPreferencesToUI(values: SummaryFullPreferenceValues) {
    method = values.method;
    siteUnitType = values.siteUnitType;
    mode = values.orderBy === 2 ? 'lifeform' : values.orderBy === 3 ? 'strata' : 'layer';
    if (criteria) {
      criteria.editChoice('coverCalculation', values.coverCalculation);
      criteria.editChoice('andOr', values.andOr);
      criteria.editText('presenceGreaterThan', String(values.presenceGreaterThan));
      criteria.editText('coverGreaterThan', String(values.coverGreaterThan));
      if (criteria.view().enabled !== (values.includeSpecies === 1)) {
        criteria.setEnabled(values.includeSpecies === 1);
      }
    }
  }
  function cancel() {
    generation++; reads.cancelAll(); preferences?.cancelLoad();
    if (typeof fullPreferences !== 'undefined') fullPreferences?.cancelLoad();
    busy = false; reportBusy();
  }
  async function options() {
    if (workbookBusy) return;
    cancel(); const request = generation;
    ready = false; error = ''; preview = null; speciesPreview = null; busy = true; reportBusy();
    try {
      const value = await reads.track(EnvironmentReportService.GetSiteUnitSummaryOptions(contextId));
      if (request !== generation) return;
      const configured = validateSiteUnitSummaryOptions(value, contextId, project, projectPath, su, suPath, true);
      method = configured.method; siteUnitType = configured.siteUnitType;
      const allowed = siteUnitType === 3 || (su !== 'None' && (siteUnitType === 2 || (siteUnitType === 1 && su !== 'USysSuTableDynamic')));
      ready = allowed;
      if (!ready) {
        error = `Saved site-unit type ${siteUnitType} requires an eligible active Site Unit table; choose Hierarchy (~) or Field-Derived.`;
        if (typeof notifications !== 'undefined') {
          notifications.error('Summary Environment options ineligible', error, {
            category: 'reports',
            source: 'Summary Environment',
            contextTag: (typeof project === 'string' && project) || undefined,
          });
        }
      }
    } catch (cause) {
      if (request === generation) {
        error = `Summary options unavailable; no defaults or configuration writes: ${String(cause)}`;
        if (typeof notifications !== 'undefined') {
          notifications.error('Summary Environment options failed', error, {
            category: 'reports',
            source: 'Summary Environment',
            contextTag: (typeof project === 'string' && project) || undefined,
          });
        }
      }
    } finally {
      if (request === generation) { busy = false; reportBusy(); }
    }
  }
  async function show() {
    if (busy || workbookBusy || preferenceBarrier || speciesBarrier || !ready || (method !== 1 && method !== 2)) return;
    const activeType = typeof siteUnitType === 'number' ? siteUnitType : 1;
    const typeAllowed = activeType === 3 || (su !== 'None' && (activeType === 2 || (activeType === 1 && su !== 'USysSuTableDynamic')));
    if (!typeAllowed) return;
    cancel(); const request = generation; const requestedMethod = method; const requestedMode = mode;
    const allowConfigured = activeType !== 1 || requestedMode === 'strata';
    const speciesRequest = speciesView?.enabled ? criteria?.request(requestedMethod, requestedMode) : null;
    error = ''; preview = null; speciesPreview = null; busy = true; reportBusy();
    try {
      if (speciesRequest) {
        const value = await reads.track(EnvironmentReportService.PreviewSiteUnitSummarySpecies(contextId, speciesRequest));
        if (request !== generation) return;
        speciesPreview = allowConfigured
          ? validateSummarySpecies(value, { contextId, project, projectPath, su, suPath }, speciesRequest, true)
          : validateSummarySpecies(value, { contextId, project, projectPath, su, suPath }, speciesRequest);
        preview = speciesPreview.environment;
      } else {
        const value = await reads.track(requestedMode === 'lifeform'
          ? EnvironmentReportService.PreviewSiteUnitSummaryLifeforms(contextId, { method: requestedMethod })
          : EnvironmentReportService.PreviewSiteUnitSummary(contextId, { method: requestedMethod }));
        if (request !== generation) return;
        preview = allowConfigured
          ? validateSiteUnitSummary(value, contextId, project, projectPath, su, suPath, requestedMethod, requestedMode, true)
          : validateSiteUnitSummary(value, contextId, project, projectPath, su, suPath, requestedMethod, requestedMode);
      }
    } catch (cause) {
      if (request === generation) {
        error = `Summary unavailable; no data or configuration writes: ${String(cause)}`;
        if (typeof notifications !== 'undefined') {
          notifications.error('Summary Environment report failed', error, {
            category: 'reports',
            source: 'Summary Environment',
            contextTag: (typeof project === 'string' && project) || undefined,
          });
        }
      }
    } finally {
      if (request === generation) { busy = false; reportBusy(); }
    }
  }
  async function loadPreferences() {
    if (workbookBusy || !preferences || preferenceView?.busy || preferenceView?.blocked) return;
    cancel(); const request = generation; const token = preferences.beginLoad();
    const fullToken = typeof fullPreferences !== 'undefined' && fullPreferences && typeof fullPreferenceView !== 'undefined' && !fullPreferenceView?.busy && !fullPreferenceView?.blocked ? fullPreferences.beginLoad() : null;
    error = ''; busy = true; reportBusy();
    try {
      if (typeof EnvironmentReportService.GetFullSiteUnitSummaryPreferences === 'function' && fullPreferences && fullToken !== null) {
        try {
          const fullValue = await reads.track(EnvironmentReportService.GetFullSiteUnitSummaryPreferences(contextId));
          if (request !== generation) return;
          if (fullValue && fullPreferences.applyLoaded(fullValue, fullToken)) {
            applyFullPreferencesToUI(fullValue.values);
          }
        } catch {
          // Legacy fallback below handles mocked contexts or partial fixtures.
        }
      }
      if (su !== 'None') {
        const value = await reads.track(EnvironmentReportService.GetSiteUnitSummaryPreferences(contextId));
        if (request !== generation) return;
        preferences.applyLoaded(value, token);
      } else if (fullPreferenceView?.draft) {
        method = fullPreferenceView.draft.method;
        siteUnitType = fullPreferenceView.draft.siteUnitType;
        ready = siteUnitType === 3;
      }
    } catch (cause) {
      if (request === generation) {
        error = `Saved summary options unavailable; no defaults applied: ${String(cause)}`;
        if (typeof notifications !== 'undefined') {
          notifications.error('Summary Environment options load failed', error, {
            category: 'reports',
            source: 'Summary Environment',
            contextTag: (typeof project === 'string' && project) || undefined,
          });
        }
      }
    } finally {
      if (request === generation) { busy = false; reportBusy(); }
    }
  }
  async function loadFullPreferences() {
    if (workbookBusy || !fullPreferences || fullPreferenceView?.busy || fullPreferenceView?.blocked) return;
    cancel(); const request = generation; const token = fullPreferences.beginLoad();
    error = ''; busy = true; reportBusy();
    try {
      const fullValue = await reads.track(EnvironmentReportService.GetFullSiteUnitSummaryPreferences(contextId));
      if (request !== generation) return;
      if (fullValue && fullPreferences.applyLoaded(fullValue, token)) {
        applyFullPreferencesToUI(fullValue.values);
      }
    } catch (cause) {
      if (request === generation) {
        error = `Full summary preferences unavailable; no defaults applied: ${String(cause)}`;
        if (typeof notifications !== 'undefined') {
          notifications.error('Summary Environment full preferences load failed', error, {
            category: 'reports',
            source: 'Summary Environment',
            contextTag: (typeof project === 'string' && project) || undefined,
          });
        }
      }
    } finally {
      if (request === generation) { busy = false; reportBusy(); }
    }
  }
  async function savePreferences() {
    if (workbookBusy) return;
    if (!preferences || busy || speciesBarrier || preferenceView?.busy || preferenceView?.blocked) return;
    cancel(); error = '';
    try {
      await preferences.save(request => EnvironmentReportService.SaveSiteUnitSummaryPreferences(contextId, JSON.stringify(request)));
      if (typeof syncPreferenceNotifications === 'function') {
        syncPreferenceNotifications();
      } else if (typeof notifications !== 'undefined') {
        const view = preferences.view();
        const latest = view.receipts?.at(-1);
        const ctxTag = (typeof project === 'string' && project) || undefined;
        if (latest?.kind === 'known') {
          if (latest.outcome.committed && !latest.outcome.errorMessage) {
            notifications.success('Summary Environment options saved', latest.outcome.changed ? 'Saved summary preferences.' : 'No option changes.', {
              category: 'reports', source: 'Summary Environment', contextTag: ctxTag,
            });
          } else if (latest.outcome.committed) {
            notifications.warning('Summary Environment options saved with warning', latest.outcome.errorMessage, {
              category: 'reports', source: 'Summary Environment', contextTag: ctxTag,
            });
          } else if (latest.outcome.errorMessage) {
            notifications.error('Summary Environment options save failed', latest.outcome.errorMessage, {
              category: 'reports', source: 'Summary Environment', contextTag: ctxTag,
            });
          } else {
            notifications.info('Summary Environment options unchanged', 'No option changes were needed.', {
              category: 'reports', source: 'Summary Environment', contextTag: ctxTag,
            });
          }
        } else if (view.error) {
          notifications.error('Summary Environment options failed', view.error, {
            category: 'reports', source: 'Summary Environment', contextTag: ctxTag,
          });
        }
      }
    } catch (cause) {
      error = String(cause);
      if (typeof notifications !== 'undefined') {
        notifications.error('Summary Environment options save failed', error, {
          category: 'reports',
          source: 'Summary Environment',
          contextTag: (typeof project === 'string' && project) || undefined,
        });
      }
    }
  }
  async function saveFullPreferences() {
    if (workbookBusy || !fullPreferences || busy || speciesBarrier || fullPreferenceView?.busy || fullPreferenceView?.blocked) return;
    cancel(); error = '';
    try {
      syncFullDraftFromUI();
      await fullPreferences.save(request => EnvironmentReportService.SaveFullSiteUnitSummaryPreferences(contextId, JSON.stringify(request)));
      if (typeof syncFullPreferenceNotifications === 'function') {
        syncFullPreferenceNotifications();
      } else if (typeof notifications !== 'undefined') {
        const view = fullPreferences.view();
        const latest = view.receipts?.at(-1);
        const ctxTag = (typeof project === 'string' && project) || undefined;
        if (latest?.kind === 'known') {
          if (latest.outcome.committed && !latest.outcome.errorMessage) {
            notifications.success('Summary Environment full preferences saved', latest.outcome.changed ? 'Saved full SE* preferences.' : 'No preference changes.', {
              category: 'reports', source: 'Summary Environment', contextTag: ctxTag,
            });
          } else if (latest.outcome.committed) {
            notifications.warning('Summary Environment full preferences saved with warning', latest.outcome.errorMessage, {
              category: 'reports', source: 'Summary Environment', contextTag: ctxTag,
            });
          } else if (latest.outcome.errorMessage) {
            notifications.error('Summary Environment full preferences save failed', latest.outcome.errorMessage, {
              category: 'reports', source: 'Summary Environment', contextTag: ctxTag,
            });
          } else {
            notifications.info('Summary Environment full preferences unchanged', 'No preference changes were needed.', {
              category: 'reports', source: 'Summary Environment', contextTag: ctxTag,
            });
          }
        } else if (view.error) {
          notifications.error('Summary Environment full preferences failed', view.error, {
            category: 'reports', source: 'Summary Environment', contextTag: ctxTag,
          });
        }
      }
    } catch (cause) {
      error = String(cause);
      if (typeof notifications !== 'undefined') {
        notifications.error('Summary Environment full preferences save failed', error, {
          category: 'reports',
          source: 'Summary Environment',
          contextTag: (typeof project === 'string' && project) || undefined,
        });
      }
    }
  }
  function editMethod(value: number) {
    if (workbookBusy || speciesBarrier) return;
    cancel(); error = ''; preview = null; speciesPreview = null;
    if (typeof fullPreferences !== 'undefined' && fullPreferences && typeof fullPreferenceView !== 'undefined' && fullPreferenceView?.draft) {
      fullPreferences.edit({ method: value });
    }
    if (preferences) preferences.editMethod(value);
    else method = value;
  }
  function editSiteUnitType(value: number) {
    if (busy || workbookBusy || preferenceBarrier || speciesBarrier) return;
    cancel(); error = ''; preview = null; speciesPreview = null;
    siteUnitType = value;
    if (fullPreferences && fullPreferenceView?.draft) fullPreferences.edit({ siteUnitType: value });
    if (value === 1 && preferences && preferenceView?.draft) preferences.selectNormalSU();
    const allowed = value === 3 || (su !== 'None' && (value === 2 || (value === 1 && su !== 'USysSuTableDynamic')));
    ready = (method === 1 || method === 2) && [1, 2, 3].includes(value) && allowed && !preferenceView?.authorityUnknown;
  }
  function editMode(value: SiteUnitSummaryMode) {
    if (busy || workbookBusy || preferenceBarrier || speciesBarrier || (value === 'lifeform' && !lifeformsEnabled)) return;
    cancel(); error = ''; preview = null; speciesPreview = null; mode = value;
    if (typeof syncFullDraftFromUI === 'function') syncFullDraftFromUI();
  }
  function editSpeciesEnabled(enabled: boolean) {
    if (busy || workbookBusy || preferenceBarrier || speciesBarrier || !ready || !criteria) return;
    cancel(); error = ''; criteria.setEnabled(enabled);
  }
  function editSpeciesText(field: 'presenceGreaterThan' | 'coverGreaterThan', value: string) {
    if (busy || workbookBusy || preferenceBarrier || !criteria) return;
    cancel(); error = ''; criteria.editText(field, value);
  }
  function editSpeciesChoice(field: 'coverCalculation' | 'andOr', value: number) {
    if (busy || workbookBusy || preferenceBarrier || !criteria) return;
    cancel(); error = ''; criteria.editChoice(field, value);
  }
  function resetSpeciesCriteria() {
    if (busy || workbookBusy || preferenceBarrier || !criteria) return;
    cancel(); error = ''; criteria.reset();
  }
  onMount(() => {
    if (!preferencesEnabled) void options();
    else if (!preferenceView?.draft && !preferenceBarrier) void loadPreferences();
  });
  onDestroy(() => { unsubscribe?.(); unsubscribeFull?.(); unsubscribeSpecies?.(); cancel(); });
</script>

<section class="summary" data-site-unit-summary aria-label="Summary Environment">
  <header class="sticky top-0 z-20 bg-white/95 backdrop-blur-xs py-2 border-b border-vpro-border report-sticky-bar" data-report-sticky-bar>
    <h1>Summary Environment</h1>
    <div class="sticky-actions">
      <button data-source-control="btnCreateReport" disabled={busy || workbookBusy || preferenceBarrier || speciesBarrier || !ready || !scopeAllowed} onclick={show}>Create Report</button>
      {#if preferencesEnabled}
        <button data-summary-preferences-load disabled={workbookBusy || !!preferenceView?.busy || !!preferenceView?.blocked} onclick={loadPreferences}>Load saved summary options</button>
      {:else}
        <button data-summary-options-reload disabled={busy || workbookBusy} onclick={options}>Reload summary options</button>
      {/if}
      {#if busy}<button data-summary-cancel onclick={cancel}>Cancel report read</button>{/if}
    </div>
  </header>
  {#if preferenceView?.draftError}<p role="alert" class="error">{preferenceView.draftError}</p>{/if}
  {#if fullPreferenceView?.draftError}<p role="alert" class="error">{fullPreferenceView.draftError}</p>{/if}
  <p>Project {project}; active SU {su}. Profile navigation does not filter this report.</p>
  {#if lifeformsEnabled}
    <fieldset disabled={busy || workbookBusy || preferenceBarrier || speciesBarrier || !ready}>
      <legend>Vegetation summary preview (OrderBy)</legend>
      <label><input type="radio" name="summary-vegetation" checked={mode === 'layer'} onchange={() => editMode('layer')} />Layer covers (1)</label>
      <label><input type="radio" name="summary-vegetation" checked={mode === 'lifeform'} onchange={() => editMode('lifeform')} />Lifeform cover values (2)</label>
      <label><input type="radio" name="summary-vegetation" data-summary-orderby-strata checked={mode === 'strata'} onchange={() => editMode('strata')} />Strata A-D (3)</label>
    </fieldset>
    {#if mode === 'lifeform'}
      <p>Explicit read-only lifeform preview; saved report grouping and species-list options can be saved via full preferences.
        Lifeform values use source minimum/mean/maximum even when other fields use Interquartile.</p>
    {:else if mode === 'strata'}
      <p>Strata A-D (OrderBy = 3) sums layer covers per plot/species across USysAllSpecs strata A-D (Tree/Shrub/Herb/Moss) capped at 99%.</p>
    {/if}
  {/if}
  <fieldset disabled={busy || workbookBusy || preferenceBarrier || speciesBarrier} data-source-control="optSiteUnitType">
    <legend>Site-Unit Scope (SESuType)</legend>
    <label><input type="radio" name="summary-su-type" value={1} checked={siteUnitType === 1} disabled={su === 'None' || su === 'USysSuTableDynamic'} onchange={() => editSiteUnitType(1)} />Normal SU (1)</label>
    <label><input type="radio" name="summary-su-type" value={2} checked={siteUnitType === 2} disabled={su === 'None'} data-summary-sutype-hierarchy onchange={() => editSiteUnitType(2)} />Hierarchy (~) Breakpoints (2)</label>
    <label><input type="radio" name="summary-su-type" value={3} checked={siteUnitType === 3} data-summary-sutype-field onchange={() => editSiteUnitType(3)} />Field-Derived (3)</label>
  </fieldset>
  <fieldset disabled={busy || workbookBusy || speciesBarrier || preferenceView?.busy || preferenceView?.blocked || !ready} data-source-control="optValueMethod">
    <legend>Quantitative Values</legend>
    <label><input type="radio" name="summary-method" value={1} checked={method === 1} onchange={() => editMethod(1)} />Mean</label>
    <label><input type="radio" name="summary-method" value={2} checked={method === 2} onchange={() => editMethod(2)} />Interquartile (25% - 50% - 75%)</label>
  </fieldset>
  {#if speciesEnabled && speciesView}
    <fieldset disabled={busy || workbookBusy || preferenceBarrier}>
      <legend>Species preview criteria</legend>
      <label><input type="checkbox" data-summary-species-enabled checked={speciesView.enabled} disabled={speciesBarrier || !ready}
        onchange={(event) => editSpeciesEnabled(event.currentTarget.checked)} />Include species list in preview</label>
      {#if speciesView.enabled}
        <label>Cover calculation<select data-summary-species-average value={speciesView.coverCalculation}
          onchange={(event) => editSpeciesChoice('coverCalculation', Number(event.currentTarget.value))}>
          <option value={1}>All plots (physical report count)</option><option value={2}>Present values</option>
        </select></label>
        <label>Criteria combination<select data-summary-species-combination value={speciesView.andOr}
          onchange={(event) => editSpeciesChoice('andOr', Number(event.currentTarget.value))}>
          <option value={1}>AND</option><option value={2}>OR</option>
        </select></label>
        <label>Presence greater than (%)<input data-summary-species-presence inputmode="numeric" value={speciesView.presenceGreaterThan}
          aria-invalid={!!speciesView.error} oninput={(event) => editSpeciesText('presenceGreaterThan', event.currentTarget.value)} /></label>
        <label>Cover greater than (%)<input data-summary-species-cover inputmode="numeric" value={speciesView.coverGreaterThan}
          aria-invalid={!!speciesView.error} oninput={(event) => editSpeciesText('coverGreaterThan', event.currentTarget.value)} /></label>
        <button data-summary-species-reset onclick={resetSpeciesCriteria}>Reset preview criteria</button>
      {/if}
    </fieldset>
    <p class="guidance">Criteria apply to layer, lifeform, and Strata A-D species lists and can be saved across all 8 SE* preferences.
      Strict thresholds compare source-formatted values; physical presence can exceed 100%.</p>
  {/if}
  <p>Active site-unit type:
    {siteUnitType === 1 ? 'Normal SU (1)' : siteUnitType === 2 ? 'Hierarchy (~) Breakpoints (2)' :
      siteUnitType === 3 ? 'Field-Derived (3)' : 'not loaded'}.</p>
  {#if preferencesEnabled}
    <div class="actions">
      <button data-summary-preferences-save disabled={busy || workbookBusy || speciesBarrier || !!preferenceView?.busy || !!preferenceView?.blocked || !!preferenceView?.draftError ||
        !preferenceView?.saved || !ready || siteUnitType !== 1} onclick={savePreferences}>Save normal-SU options</button>
      <button data-summary-preferences-undo disabled={workbookBusy || !!preferenceView?.busy || !!preferenceView?.blocked || !preferenceView?.saved}
        onclick={() => { if (workbookBusy) return; cancel(); preferences?.undo(); }}>Undo summary options</button>
      {#if siteUnitType !== 1}
        <button data-summary-preferences-normal disabled={workbookBusy || !!preferenceView?.busy || !!preferenceView?.blocked || !preferenceView?.draft || su === 'None'}
          onclick={() => { if (workbookBusy) return; cancel(); preferences?.selectNormalSU(); editSiteUnitType(1); }}>Select normal SU</button>
      {/if}
      {#if preferenceView?.blocked}
        <button data-summary-preferences-acknowledge disabled={workbookBusy || preferenceView.busy}
          onclick={() => { if (!workbookBusy) preferences?.acknowledge(); }}>Acknowledge summary preference outcome</button>
      {/if}
      {#if fullPreferences}
        <button data-summary-full-preferences-load disabled={workbookBusy || !!fullPreferenceView?.busy || !!fullPreferenceView?.blocked} onclick={loadFullPreferences}>Load full SE* preferences</button>
        <button data-summary-full-preferences-save disabled={busy || workbookBusy || speciesBarrier || !!fullPreferenceView?.busy || !!fullPreferenceView?.blocked || !!fullPreferenceView?.draftError || !fullPreferenceView?.saved}
          onclick={saveFullPreferences}>Save full SE* preferences</button>
        {#if fullPreferenceView?.blocked}
          <button data-summary-full-preferences-acknowledge disabled={workbookBusy || fullPreferenceView.busy}
            onclick={() => { if (!workbookBusy) fullPreferences?.acknowledge(); }}>Acknowledge full preference outcome</button>
        {/if}
      {/if}
    </div>
  {/if}
  {#if mode === 'layer' && !speciesView?.enabled}
    <SiteUnitSummaryWorkbookPanel owner={{ contextId, project, projectPath, su, suPath }} {method} {siteUnitType} allowConfiguredScope={true}
      disabled={busy || preferenceBarrier || speciesBarrier || !ready || !scopeAllowed}
      onBusyChange={(held) => { workbookBusy = held; reportBusy(); }} />
  {:else if extendedWorkbookEnabled && (mode === 'lifeform' || mode === 'strata' || speciesView?.enabled)}
    <SiteUnitSummaryWorkbookPanel owner={{ contextId, project, projectPath, su, suPath }} {method} {siteUnitType} allowConfiguredScope={true} {extendedOptions}
      disabled={busy || preferenceBarrier || speciesBarrier || !ready || !scopeAllowed}
      onBusyChange={(held) => { workbookBusy = held; reportBusy(); }} />
  {/if}
  {#each preferenceView?.receipts ?? [] as receipt}
    {#if receipt.kind !== 'known'}
      <p data-summary-preferences-receipt data-summary-preferences-unknown-receipt role="alert">
        Preference receipt: outcome unknown; changed unknown; committed unknown. {receipt.errorMessage}</p>
    {/if}
  {/each}
  <p class="guidance">Read-only normal-SU Environment fields. Saved calculation method and site-unit type load from configuration.
    {#if preferencesEnabled}Explicit reviewed Save replaces the source's immediate AfterUpdate preferences. It changes only the two saved summary keys, never plot data or registry.
      Drafts and receipts survive tab remounts. Unknown outcomes require acknowledgement and explicit Load, never replay.
    {:else}Calculation changes are preview-only; Reload restores saved options. No registry or saved-preference changes.{/if}
    Hierarchy/field-derived units {#if !speciesEnabled}and species-list output {/if}remain unavailable.
    Lifeform cover values require their separate preview gate.
    {#if extendedWorkbookEnabled}Extended workbooks additionally require their independent backend gate and the corresponding preview gates.
    {:else}Only layer-cover workbooks without a species list are supported.{/if}</p>
  <p class="guidance">Counts preserve every physical SU/Env/Admin join, including duplicate weights. Text equality/order is literal.
    Numeric formatting uses the measured English locale; unsupported historical text in numeric fields is refused, not repaired.
    Both disturbance labels retain the source's SiteDisturbance2 binding.</p>
  {#if preview}
    <p role="status" data-summary-count>{preview.report.units.length} units; {preview.report.memberships.length} physical memberships.
      {preview.report.method === 1 ? 'Min---Mean---Max' : 'Interquartile 25% - 50% - 75%'}</p>
    {#if preview.report.units.length === 0}<p>No joined plots in the selected units.</p>{/if}
    {#each preview.report.units as unit, unitIndex (unit.code)}
      <article data-summary-unit>
        <h2>{unit.code === '' ? '"" (empty unit)' : unit.code}</h2>
        <p>{unit.longName === '' ? '"" (empty name)' : unit.longName ?? `Name ${unit.nameStatus}`}</p>
        <p>Plots in unit: {unit.plots.length} (physical joined rows)</p>
        {#if speciesPreview}
          {@const speciesUnit = speciesPreview.units[unitIndex]}
          <section data-summary-species-unit aria-label={`Vegetation species for ${unit.code}`}>
            <h3>Vegetation species</h3>
            {#each speciesUnit.groups as group}
              <h4>{group.caption}</h4>
              {#if group.rows.some(row => row.included)}
                <div class="species-table"><table>
                  <thead><tr><th scope="col">Scientific Name</th><th scope="col">Common Name</th><th scope="col">%Cover</th><th scope="col">%Presence</th></tr></thead>
                  <tbody>{#each group.rows.filter(row => row.included) as row}
                    <tr><th scope="row" aria-label={`${reportCellText(row.scientificName)} (${row.species})`}>{reportCellText(row.scientificName)}</th>
                      <td>{reportCellText(row.englishName)}</td><td>{row.cover}</td><td>{row.presence}</td></tr>
                  {/each}</tbody>
                </table></div>
              {:else}<p>No species pass the strict formatted criteria.</p>{/if}
              <details><summary>Physical species values, definitions and excluded rows</summary>
                <ul>{#each group.rows as row}
                  <li>{row.species}: {row.cover} cover; {row.presence} presence; {row.physicalValues} physical values;
                    UNION reference rows {row.referenceRowIds.join(', ')}; {row.included ? 'included' : 'excluded'}.</li>
                {/each}</ul>
              </details>
            {:else}<p>No matched species definitions in the reportable groups.</p>{/each}
          </section>
        {/if}
        {#each ['SITE', 'VEGETATION', 'SOILS'] as section}
          <section aria-labelledby={`summary-${unitIndex}-${section}`}>
            <h3 id={`summary-${unitIndex}-${section}`}>{section}</h3>
            <dl>
              {#each preview.report.fields as field, index}
                {#if field.section === section}
                  <div><dt>{field.label}</dt><dd data-summary-value>{unit.values[index] === '' ? '"" (empty summary)' : unit.values[index]}</dd></div>
                {/if}
              {/each}
            </dl>
          </section>
        {/each}
        <details>
          <summary>Physical plot joins and reference name candidates</summary>
          <ul>{#each unit.plots as plot}<li>{plot.plotNumber}: SU row {plot.suRowId}, Env row {plot.envRowId}, Admin row {plot.adminRowId}</li>{/each}</ul>
          <ul>{#each unit.nameCandidates as candidate}<li>Reference row {candidate.rowId}: {reportCellText(candidate.value)}</li>{/each}</ul>
        </details>
      </article>
    {/each}
    <details>
      <summary>All physical memberships and exclusions</summary>
      <ul>{#each preview.report.memberships as membership}
        <li>SU row {membership.rowId}: plot {reportCellText(membership.plotNumber)}, unit {reportCellText(membership.siteUnit)};
          {membership.status}, {membership.joinedRows} joined rows</li>
      {/each}</ul>
    </details>
  {/if}
</section>

<style>
  .summary { display: grid; gap: 1rem; padding: 1rem; max-width: 90rem; margin: auto; background: var(--vpro-canvas); color: var(--vpro-ink); min-width: 0; }
  .report-sticky-bar { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: .75rem; padding-inline: .75rem; border-radius: .35rem; }
  .report-sticky-bar h1 { margin: 0; }
  .sticky-actions { display: flex; flex-wrap: wrap; gap: .5rem; align-items: center; }
  h1, h2, h3 { font-weight: 600; margin: .8rem 0; color: var(--vpro-navy); }
  h1 { font-size: 1.5rem; } h2 { font-size: 1.2rem; }
  fieldset, .actions { display: flex; flex-wrap: wrap; gap: 1rem; margin: .5rem 0; padding: .75rem; background: var(--vpro-surface); border: 1px solid var(--vpro-border); border-radius: .5rem; }
  fieldset legend { font-weight: 600; color: var(--vpro-navy); padding: 0 .35rem; }
  label { display: flex; align-items: center; gap: .5rem; color: var(--vpro-ink); }
  button, summary { min-height: 2.5rem; border: 1px solid var(--vpro-navy); border-radius: .25rem; padding: .5rem .85rem; background: var(--vpro-navy); color: var(--vpro-surface); font-weight: 600; cursor: pointer; }
  button:hover:not(:disabled), summary:hover { background: var(--vpro-navy-dark); border-color: var(--vpro-navy-dark); }
  button:disabled { opacity: .5; cursor: not-allowed; }
  article { border: 1px solid var(--vpro-border); border-radius: .5rem; padding: 1rem; margin-top: 1rem; background: var(--vpro-surface); min-width: 0; }
  dl { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 280px), 1fr)); gap: .5rem 1rem; }
  dl > div { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: .5rem; padding: .45rem .6rem; background: var(--vpro-canvas); border-radius: .25rem; }
  dt { font-weight: 600; color: var(--vpro-navy); } dd, li, h2 { white-space: pre-wrap; overflow-wrap: anywhere; }
  details { margin-top: .8rem; } .guidance { font-size: .9rem; margin: .4rem 0; color: var(--vpro-ink-secondary); }
  .error { color: var(--vpro-error); white-space: pre-wrap; font-weight: 600; }
  .species-table { overflow-x: auto; max-width: 100%; }
  table { width: 100%; border-collapse: collapse; margin: .5rem 0; background: var(--vpro-surface); }
  th, td { padding: .5rem; border-bottom: 1px solid var(--vpro-border); text-align: left; overflow-wrap: anywhere; }
  thead th { background: var(--vpro-canvas); color: var(--vpro-navy); }
  select, input:not([type="radio"]):not([type="checkbox"]) { max-width: 100%; min-width: 0; border: 1px solid var(--vpro-border); border-radius: .25rem; padding: .4rem; background: var(--vpro-surface); color: var(--vpro-ink); }
  @media (max-width: 640px) { dl > div { grid-template-columns: minmax(0, 1fr); } }
</style>
