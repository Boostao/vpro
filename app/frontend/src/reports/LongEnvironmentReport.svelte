<script lang="ts">
  import { onMount, onDestroy, untrack } from 'svelte';
  import {
    EnvironmentReportService,
    type HTMLReportResult,
    type LongEnvironmentPreview,
  } from '../../bindings/github.com/boostao/vpro/app';
  import { ReadRequests, formatError } from '../shared/readRequests';
  import { reportTitleError, validateLongEnvironmentPreview } from './longEnvironmentReport';
  import { longEnvironmentPreferencesSession } from './longEnvironmentPreferences';
  import {
    environmentWorkbookPublicationSession,
    validateEnvironmentWorkbookReview,
    type ValidatedEnvironmentWorkbookReview,
  } from './environmentWorkbook';
  import { notifications } from '../shell/notificationService.svelte';
  import { defaultWebExportFilename } from '../shell/webReadOnlyShell';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import { formatWebDownloadFeedback } from '../web/webMeta';
  import CompactReportShell from './CompactReportShell.svelte';
  import LongEnvironmentPreviewBody from './parts/LongEnvironmentPreviewBody.svelte';
  import type { QuickExportSummary } from './compactReport';
  import * as quick from './compactReportRunners';

  let {
    contextId,
    project,
    projectPath,
    su,
    suPath,
    onBusyChange,
  }: {
    contextId: string;
    project: string;
    projectPath: string;
    su: string;
    suPath: string;
    onBusyChange: (busy: boolean) => void;
  } = $props();

  let title = $state('');
  let ready = $state(false);
  let busy = $state(false);
  let error = $state('');
  let preview = $state<LongEnvironmentPreview | null>(null);
  let workbookReview = $state.raw<ValidatedEnvironmentWorkbookReview | null>(null);
  let destination = $state('');
  let quickDraft = $state<quick.LongEnvQuickDraft>(quick.loadInitialQuickDraft('long_env', quick.DEFAULT_LONG_ENV_QUICK));
  let quickExporting = $state(false);
  let quickRendering = $state(false);
  let quickError = $state('');
  let quickExportResult = $state.raw<QuickExportSummary | null>(null);
  let quickHtmlReport = $state.raw<HTMLReportResult | null>(null);
  const titleError = $derived(reportTitleError(title));
  const reads = new ReadRequests();
  let generation = 0;
  const workbookOwner = untrack(() => ({ contextId, project, projectPath, su, suPath }));
  const workbookSession = environmentWorkbookPublicationSession(workbookOwner);
  let publication = $state(workbookSession.view());
  const workbookBarrier = $derived(publication.busy || publication.blocked);
  const preferences = longEnvironmentPreferencesSession?.(workbookOwner) ?? null;
  let preferenceView = $state(preferences?.view() ?? null);
  const preferenceBarrier = $derived(
    !!preferenceView &&
      (preferenceView.busy || preferenceView.blocked || preferenceView.authorityUnknown || !!preferenceView.draftError)
  );
  function reportBusy() {
    onBusyChange(busy || preferenceBarrier || workbookBarrier);
  }
  let lastPubKey = '';
  let lastPrefError = '';
  let notifiedPrefReceipts = 0;

  function syncWorkbookNotifications() {
    const settled = workbookSession.view();
    if (settled.busy) {
      lastPubKey = '';
      return;
    }
    if (!settled.outcome && !settled.error) return;
    const key = JSON.stringify([settled.outcome?.status ?? '', settled.outcome?.path ?? '', settled.outcome?.sha256 ?? '', settled.error ?? '', settled.requestedDestination ?? '']);
    if (key === lastPubKey) return;
    lastPubKey = key;
    const opts = { category: 'reports' as const, source: 'Long Environment', contextTag: (typeof project === 'string' && project) || undefined };
    if (settled.outcome?.status === 'published' && !settled.error) {
      notifications.success('Long Environment workbook exported', settled.outcome.path || settled.requestedDestination || destination, opts);
    } else if (settled.error || settled.outcome) {
      notifications.error('Long Environment workbook export failed', settled.error || `Publication ${settled.outcome?.status ?? 'failed'} for ${settled.requestedDestination || destination}`, opts);
    }
  }

  function syncPreferenceNotifications() {
    const view = preferences?.view();
    if (!view) return;
    const opts = { category: 'reports' as const, source: 'Long Environment', contextTag: (typeof project === 'string' && project) || undefined };
    const receipts = view.receipts ?? [];
    if (receipts.length < notifiedPrefReceipts) notifiedPrefReceipts = 0;
    for (let i = notifiedPrefReceipts; i < receipts.length; i++) {
      const receipt = receipts[i];
      if (receipt.kind === 'known') {
        if (receipt.outcome.committed && !receipt.outcome.errorMessage) {
          notifications.success('Long Environment title saved', receipt.outcome.changed ? 'Saved report title preference.' : 'No title changes.', opts);
        } else if (receipt.outcome.committed) {
          notifications.warning('Long Environment title saved with warning', receipt.outcome.errorMessage, opts);
          lastPrefError = receipt.outcome.errorMessage;
        } else if (receipt.outcome.errorMessage) {
          notifications.error('Long Environment title save failed', receipt.outcome.errorMessage, opts);
          lastPrefError = receipt.outcome.errorMessage;
        } else {
          notifications.info('Long Environment title unchanged', 'No title preference changes were needed.', opts);
        }
      }
    }
    notifiedPrefReceipts = receipts.length;
    const prefErr = view.error ?? '';
    if (prefErr && prefErr !== lastPrefError) notifications.error('Long Environment title preference failed', prefErr, opts);
    lastPrefError = prefErr;
  }

  const unsubscribeWorkbook = workbookSession.subscribe(() => {
    publication = workbookSession.view();
    syncWorkbookNotifications();
    reportBusy();
  });
  const unsubscribe = preferences?.subscribe(() => {
    preferenceView = preferences.view();
    title = preferenceView.draft.title;
    ready = preferenceView.initialized;
    preview = null;
    workbookReview = null;
    syncPreferenceNotifications();
    onBusyChange(
      busy ||
        preferenceView.busy ||
        preferenceView.blocked ||
        preferenceView.authorityUnknown ||
        !!preferenceView.draftError ||
        workbookBarrier
    );
  });
  syncWorkbookNotifications();
  syncPreferenceNotifications();

  function cancel() {
    generation++;
    reads.cancelAll();
    preferences?.cancelLoad();
    busy = false;
    reportBusy();
  }
  async function show() {
    if (busy || preferenceBarrier || workbookBarrier || !ready || titleError || su === 'None') return;
    cancel();
    const request = generation;
    const requestedTitle = title;
    error = '';
    preview = null;
    workbookReview = null;
    busy = true;
    reportBusy();
    try {
      const value = await reads.track(
        EnvironmentReportService.PreviewLongEnvironment(contextId, { title: requestedTitle })
      );
      if (request !== generation) return;
      preview = validateLongEnvironmentPreview(value, contextId, project, projectPath, su, suPath, requestedTitle);
    } catch (cause) {
      if (request === generation) {
        error = `Report unavailable; this report preparation made no data or configuration writes: ${formatError(cause)}`;
        notifications.error('Long Environment report failed', error, {
          category: 'reports',
          source: 'Long Environment',
          contextTag: (typeof project === 'string' && project) || undefined,
        });
      }
    } finally {
      if (request === generation) {
        busy = false;
        reportBusy();
      }
    }
  }
  async function loadSavedTitle() {
    if (!preferences || preferenceView?.busy || preferenceView?.blocked || workbookBarrier) return;
    cancel();
    const request = generation;
    const token = preferences.beginLoad();
    error = '';
    busy = true;
    reportBusy();
    try {
      const value = await reads.track(EnvironmentReportService.GetLongEnvironmentPreferences(contextId));
      if (request !== generation) return;
      preferences.applyLoaded(value, token);
    } catch (cause) {
      if (request === generation) {
        error = `Saved title unavailable; no defaults applied: ${formatError(cause)}`;
        notifications.error('Long Environment title load failed', error, {
          category: 'reports',
          source: 'Long Environment',
          contextTag: (typeof project === 'string' && project) || undefined,
        });
      }
    } finally {
      if (request === generation) {
        busy = false;
        reportBusy();
      }
    }
  }
  async function saveTitle() {
    if (typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY) return;
    if (!preferences || busy || preferenceView?.busy || preferenceView?.blocked || workbookBarrier) return;
    cancel();
    error = '';
    try {
      await preferences.save((request) =>
        EnvironmentReportService.SaveLongEnvironmentPreferences(contextId, JSON.stringify(request))
      );
      if (typeof syncPreferenceNotifications === 'function') syncPreferenceNotifications();
    } catch (cause) {
      error = formatError(cause);
      notifications.error('Long Environment title save failed', error, {
        category: 'reports',
        source: 'Long Environment',
        contextTag: (typeof project === 'string' && project) || undefined,
      });
    }
  }
  function editTitle(value: string) {
    if (preferences) {
      cancel();
      preferences.edit(value);
    } else {
      title = value;
    }
    preview = null;
    workbookReview = null;
    if (!reportTitleError(title)) error = '';
  }
  async function reviewWorkbook() {
    if (busy || preferenceBarrier || workbookBarrier || !ready || titleError || su === 'None' || su === 'USysSuTableDynamic') return;
    cancel();
    const request = generation;
    const requestedTitle = title;
    [error, preview, workbookReview, busy] = ['', null, null, true];
    reportBusy();
    try {
      const value = await reads.track(
        EnvironmentReportService.GetEnvironmentWorkbookReview(contextId, JSON.stringify({ title: requestedTitle }))
      );
      if (request !== generation) return;
      workbookReview = validateEnvironmentWorkbookReview(value, workbookOwner, requestedTitle);
      preview = workbookReview.preview;
    } catch (cause) {
      if (request === generation) {
        error = `Workbook review unavailable; no file published: ${formatError(cause)}`;
        notifications.error('Long Environment workbook review failed', error, {
          category: 'reports', source: 'Long Environment', contextTag: (typeof project === 'string' && project) || undefined,
        });
      }
    } finally {
      if (request === generation) {
        busy = false;
        reportBusy();
      }
    }
  }
  async function publishWorkbook() {
    if (busy || preferenceBarrier || workbookBarrier || !workbookReview) return;
    const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
    if (webReadOnly && !destination.trim()) {
      destination =
        typeof defaultWebExportFilename === 'function'
          ? defaultWebExportFilename(`${project || 'vpro'}_long_environment`, '.xlsx')
          : `${project || 'vpro'}_long_environment.xlsx`;
    }
    cancel();
    error = '';
    const ctxTag = (typeof project === 'string' && project) || undefined;
    try {
      await workbookSession.publish(workbookReview, destination, (request) =>
        EnvironmentReportService.ExportReviewedEnvironmentWorkbook(contextId, JSON.stringify(request))
      );
      if (typeof syncWorkbookNotifications === 'function') {
        syncWorkbookNotifications();
      } else {
        const s = workbookSession.view();
        const opts = { category: 'reports' as const, source: 'Long Environment', contextTag: ctxTag };
        if (s.outcome?.status === 'published' && !s.error) {
          notifications.success(
            webReadOnly ? 'Long Environment workbook downloaded' : 'Long Environment workbook exported',
            webReadOnly ? destination : s.outcome.path || s.requestedDestination || destination,
            opts
          );
        } else if (s.error || s.outcome) {
          notifications.error(
            'Long Environment workbook export failed',
            s.error || `Publication ${s.outcome?.status ?? 'failed'} for ${s.requestedDestination || destination}`,
            opts
          );
        }
      }
    } catch (cause) {
      error =
        webReadOnly && typeof formatWebDownloadFeedback === 'function'
          ? formatWebDownloadFeedback(cause, 'Long Environment workbook download')
          : formatError(cause);
      notifications.error('Long Environment workbook export failed', error, {
        category: 'reports',
        source: 'Long Environment',
        contextTag: ctxTag,
      });
    }
  }
  function acknowledgeWorkbook() {
    workbookSession.acknowledge();
    workbookReview = null;
  }
  async function quickExportSpreadsheet() {
    if (!contextId || quickExporting || quickRendering) return;
    [quickExporting, quickError] = [true, ''];
    const snap = $state.snapshot(quickDraft);
    quick.persistQuickDraft('long_env', snap);
    const out = await quick.exportLongEnvSpreadsheet(contextId, snap, project, su);
    [quickExportResult, quickError, quickExporting] = [out.summary, out.error, false];
  }
  async function quickDisplayReport() {
    if (!contextId || quickExporting || quickRendering) return;
    [quickRendering, quickError] = [true, ''];
    const snap = $state.snapshot(quickDraft);
    quick.persistQuickDraft('long_env', snap);
    const req = quick.buildLongEnvQuickRequest(snap, project, false);
    const out = await quick.runQuickHTMLDisplay({
      source: 'Long Environment', project,
      invoke: () => EnvironmentReportService.RenderLongEnvironmentHTMLReport(contextId, req),
    });
    [quickHtmlReport, quickError, quickRendering] = [out.report, out.error, false];
  }
  onMount(() => {
    void quick.hydrateLongEnvQuickDraft(contextId, $state.snapshot(quickDraft)).then((next) => {
      quickDraft = next;
    });
  });
  onDestroy(() => {
    unsubscribe?.();
    unsubscribeWorkbook();
    cancel();
  });
</script>

<section class="report" data-long-environment-report aria-label="Long Environment report">
  <CompactReportShell
    title="Long Environment"
    subtitle="Plot-by-plot site, soil, and environmental attributes by unit."
    {contextId}
    {project}
    {su}
    busy={busy || preferenceBarrier || workbookBarrier}
    exporting={quickExporting}
    rendering={quickRendering}
    exportResult={quickExportResult}
    htmlReport={quickHtmlReport}
    errorMessage={quickError || titleError || preferenceView?.draftError || error}
    onExportSpreadsheet={quickExportSpreadsheet}
    onDisplayReport={quickDisplayReport}
    onCloseHtmlReport={() => (quickHtmlReport = null)}
  >
    {#snippet headerExtra()}
      <button
        type="button"
        class="btn-secondary"
        data-source-control="btnViewReport"
        disabled={busy || preferenceBarrier || workbookBarrier || !ready || !!titleError || su === 'None'}
        onclick={show}
      >
        View Report
      </button>
      {#if busy}<button type="button" class="btn-secondary" onclick={cancel}>Cancel</button>{/if}
    {/snippet}
    {#snippet quickOptions()}
      <div class="quick-env-grid" data-long-env-quick-options>
        <label class="field-wide">
          <span>Report Title</span>
          <input
            type="text"
            data-quick-le-title
            value={quickDraft.title}
            placeholder="Long Environment Report"
            disabled={quickExporting || quickRendering}
            oninput={(e) => {
              quickDraft = { ...quickDraft, title: e.currentTarget.value };
            }}
          />
        </label>
        <label>
          <span>Scope</span>
          <select
            data-quick-le-scope
            value={quickDraft.scopeMode}
            disabled={quickExporting || quickRendering}
            onchange={(e) => {
              quickDraft = { ...quickDraft, scopeMode: e.currentTarget.value as quick.LongEnvQuickDraft['scopeMode'] };
            }}
          >
            <option value="auto">Auto (Active SU or Zone+SubZone)</option>
            <option value="su">Active Site Unit Table</option>
            <option value="zone-subzone">Zone + SubZone / SiteSeries</option>
            <option value="all-plots">All Project Plots</option>
          </select>
        </label>
      </div>
    {/snippet}
    {#snippet advanced()}
      {#if !publication.outcome && publication.blocked && !publication.busy}
        <p data-environment-workbook-unknown role="alert">
          Workbook outcome unknown. Retain and inspect {publication.requestedDestination}; never replay blindly.
        </p>
      {/if}
      {#if publication.blocked && !publication.busy}
        <button onclick={acknowledgeWorkbook}>Acknowledge workbook outcome</button>
      {/if}
      <div class="actions">
        <button
          disabled={busy || preferenceBarrier || workbookBarrier || !ready || !!titleError || su === 'None' || su === 'USysSuTableDynamic'}
          onclick={reviewWorkbook}
        >
          Review XLSX workbook (no file yet)
        </button>
        <button
          data-long-environment-preferences-load
          disabled={!!preferenceView?.busy || !!preferenceView?.blocked || workbookBarrier}
          onclick={loadSavedTitle}
        >
          Load saved title
        </button>
      </div>
      <label for="long-environment-title">Title</label>
      <textarea
        id="long-environment-title"
        data-source-control="rptSvTitle"
        rows="2"
        value={title}
        disabled={!!preferenceView?.busy || !!preferenceView?.blocked || workbookBarrier}
        oninput={(event) => editTitle(event.currentTarget.value)}
      ></textarea>
      <div class="actions">
        {#if !IS_WEB_READONLY}
          <button
            data-long-environment-preferences-save
            disabled={busy || !!preferenceView?.busy || !!preferenceView?.blocked || !!preferenceView?.draftError || !preferenceView?.saved || workbookBarrier}
            onclick={saveTitle}
          >
            Save reviewed title
          </button>
        {/if}
        <button
          data-long-environment-preferences-undo
          disabled={!!preferenceView?.busy || !!preferenceView?.blocked || !preferenceView?.saved || workbookBarrier}
          onclick={() => {
            cancel();
            preferences?.undo();
          }}
        >
          Undo title
        </button>
        {#if preferenceView?.blocked}
          <button
            data-long-environment-preferences-acknowledge
            disabled={preferenceView.busy}
            onclick={() => preferences?.acknowledge()}
          >
            Acknowledge preference outcome
          </button>
        {/if}
      </div>
      {#if workbookReview}
        <p>
          Reviewed workbook: {workbookReview.sheets.length} source unit sheets; {workbookReview.bytes} bytes; SHA256
          {workbookReview.workbookSHA256}.
        </p>
        <ul>
          {#each workbookReview.sheets as sheet}
            <li>Unit “{sheet.unit}” → worksheet “{sheet.name}”</li>
          {/each}
        </ul>
        {#if !IS_WEB_READONLY}
          <label for="environment-workbook-destination">New XLSX output file (existing files are never replaced)</label>
          <textarea
            id="environment-workbook-destination"
            rows="2"
            disabled={busy || preferenceBarrier || workbookBarrier}
            bind:value={destination}
          ></textarea>
        {/if}
        <button
          disabled={busy || preferenceBarrier || workbookBarrier || (!IS_WEB_READONLY && (!destination || !/\.xlsx$/i.test(destination)))}
          onclick={publishWorkbook}
        >
          {IS_WEB_READONLY ? 'Download reviewed XLSX workbook' : 'Publish reviewed XLSX workbook'}
        </button>
      {/if}
      {#each preferenceView?.receipts ?? [] as receipt}
        {#if receipt.kind !== 'known'}
          <p data-long-environment-preferences-receipt data-long-environment-preferences-unknown-receipt role="alert">
            Preference receipt: outcome unknown; changed unknown; committed unknown. {receipt.errorMessage}
          </p>
        {/if}
      {/each}
    {/snippet}
    {#snippet results()}
      {#if preview}
        <LongEnvironmentPreviewBody {preview} />
      {/if}
    {/snippet}
  </CompactReportShell>
  <p class="guidance">
    Previewing, typing or viewing the report does not alter saved preferences. This report preparation made no data/configuration writes.
  </p>
</section>

<style>
  .report { display: grid; grid-template-columns: minmax(0, 1fr); min-width: 0; overflow-wrap: anywhere; gap: 0.75rem; }
  .quick-env-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 220px), 1fr)); gap: 0.65rem; }
  .quick-env-grid label { display: grid; gap: 0.22rem; font-size: 0.8rem; font-weight: 600; }
  .field-wide { grid-column: span 2; }
  @media (max-width: 720px) { .field-wide { grid-column: span 1; } }
  .quick-env-grid input, .quick-env-grid select {
    box-sizing: border-box; min-width: 0; border: 1px solid var(--vpro-border-strong); border-radius: 0.25rem;
    padding: 0.42rem 0.55rem; width: 100%; background: var(--vpro-surface); color: var(--vpro-ink);
  }
  textarea {
    box-sizing: border-box; min-width: 0; border: 1px solid var(--vpro-border-strong); border-radius: 0.25rem;
    padding: 0.42rem 0.55rem; width: 100%; background: var(--vpro-surface); color: var(--vpro-ink);
  }
  .guidance { color: var(--vpro-ink-secondary); font-size: 0.85rem; margin: 0; }
  .actions { display: flex; flex-wrap: wrap; gap: 0.5rem; align-items: center; }
  .btn-secondary, button {
    border: 1px solid var(--vpro-navy); border-radius: 0.25rem; padding: 0.42rem 0.75rem; min-height: 2.35rem;
    background: var(--vpro-surface); color: var(--vpro-navy); font-weight: 600; font-size: 0.82rem; cursor: pointer;
  }
  button:disabled { opacity: 0.5; cursor: not-allowed; }
</style>
