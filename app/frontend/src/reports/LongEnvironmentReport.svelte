<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { EnvironmentReportService, type LongEnvironmentPreview } from '../../bindings/github.com/boostao/vpro/app';
  import { ReadRequests, formatError } from '../shared/readRequests';
  import { reportTitleError, validateLongEnvironmentPreview } from './longEnvironmentReport';
  import { longEnvironmentPreferencesSession } from './longEnvironmentPreferences';
  import {
    environmentWorkbookPublicationSession,
    validateEnvironmentWorkbookReview,
    type ValidatedEnvironmentWorkbookReview,
  } from './environmentWorkbook';
  import { notifications } from '../shell/notificationService.svelte';
  import LongEnvironmentPreviewBody from './parts/LongEnvironmentPreviewBody.svelte';

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
    const key = JSON.stringify([
      settled.outcome?.status ?? '',
      settled.outcome?.path ?? '',
      settled.outcome?.sha256 ?? '',
      settled.error ?? '',
      settled.requestedDestination ?? '',
    ]);
    if (key === lastPubKey) return;
    lastPubKey = key;
    const ctxTag = (typeof project === 'string' && project) || undefined;
    if (settled.outcome?.status === 'published' && !settled.error) {
      const exportedPath = settled.outcome.path || settled.requestedDestination || destination;
      notifications.success('Long Environment workbook exported', exportedPath, {
        category: 'reports',
        source: 'Long Environment',
        contextTag: ctxTag,
      });
    } else if (settled.error || settled.outcome) {
      notifications.error(
        'Long Environment workbook export failed',
        settled.error ||
          `Publication ${settled.outcome?.status ?? 'failed'} for ${settled.requestedDestination || destination}`,
        {
          category: 'reports',
          source: 'Long Environment',
          contextTag: ctxTag,
        }
      );
    }
  }

  function syncPreferenceNotifications() {
    const view = preferences?.view();
    if (!view) return;
    const ctxTag = (typeof project === 'string' && project) || undefined;
    const receipts = view.receipts ?? [];
    if (receipts.length < notifiedPrefReceipts) notifiedPrefReceipts = 0;
    for (let i = notifiedPrefReceipts; i < receipts.length; i++) {
      const receipt = receipts[i];
      if (receipt.kind === 'known') {
        if (receipt.outcome.committed && !receipt.outcome.errorMessage) {
          notifications.success(
            'Long Environment title saved',
            receipt.outcome.changed ? 'Saved report title preference.' : 'No title changes.',
            { category: 'reports', source: 'Long Environment', contextTag: ctxTag }
          );
        } else if (receipt.outcome.committed) {
          notifications.warning('Long Environment title saved with warning', receipt.outcome.errorMessage, {
            category: 'reports',
            source: 'Long Environment',
            contextTag: ctxTag,
          });
          lastPrefError = receipt.outcome.errorMessage;
        } else if (receipt.outcome.errorMessage) {
          notifications.error('Long Environment title save failed', receipt.outcome.errorMessage, {
            category: 'reports',
            source: 'Long Environment',
            contextTag: ctxTag,
          });
          lastPrefError = receipt.outcome.errorMessage;
        } else {
          notifications.info('Long Environment title unchanged', 'No title preference changes were needed.', {
            category: 'reports',
            source: 'Long Environment',
            contextTag: ctxTag,
          });
        }
      }
    }
    notifiedPrefReceipts = receipts.length;
    const prefErr = view.error ?? '';
    if (prefErr && prefErr !== lastPrefError) {
      notifications.error('Long Environment title preference failed', prefErr, {
        category: 'reports',
        source: 'Long Environment',
        contextTag: ctxTag,
      });
    }
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
    if (
      busy ||
      preferenceBarrier ||
      workbookBarrier ||
      !ready ||
      titleError ||
      su === 'None' ||
      su === 'USysSuTableDynamic'
    ) {
      return;
    }
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
        EnvironmentReportService.GetEnvironmentWorkbookReview(contextId, JSON.stringify({ title: requestedTitle }))
      );
      if (request !== generation) return;
      workbookReview = validateEnvironmentWorkbookReview(value, workbookOwner, requestedTitle);
      preview = workbookReview.preview;
    } catch (cause) {
      if (request === generation) {
        error = `Workbook review unavailable; no file published: ${formatError(cause)}`;
        notifications.error('Long Environment workbook review failed', error, {
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
  async function publishWorkbook() {
    if (busy || preferenceBarrier || workbookBarrier || !workbookReview) return;
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
            'Long Environment workbook exported',
            s.outcome.path || s.requestedDestination || destination,
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
      error = formatError(cause);
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
  onDestroy(() => {
    unsubscribe?.();
    unsubscribeWorkbook();
    cancel();
  });
</script>

<section class="report" data-long-environment-report aria-label="Long Environment report">
  <header
    class="sticky top-0 z-20 bg-white/95 backdrop-blur-xs py-2 border-b border-vpro-border report-sticky-bar"
    data-report-sticky-bar
  >
    <h1>Long Environment</h1>
    <div class="actions">
      <button
        data-source-control="btnViewReport"
        disabled={busy || preferenceBarrier || workbookBarrier || !ready || !!titleError || su === 'None'}
        onclick={show}
      >
        View Report
      </button>
      <button
        disabled={busy ||
          preferenceBarrier ||
          workbookBarrier ||
          !ready ||
          !!titleError ||
          su === 'None' ||
          su === 'USysSuTableDynamic'}
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
      {#if busy}<button onclick={cancel}>Cancel report read</button>{/if}
    </div>
  </header>
  {#if titleError}<p class="error" role="alert">{titleError}</p>{/if}
  {#if preferenceView?.draftError}<p class="error" role="alert">{preferenceView.draftError}</p>{/if}
  {#if !publication.outcome && publication.blocked && !publication.busy}
    <p data-environment-workbook-unknown role="alert">
      Workbook outcome unknown. Retain and inspect {publication.requestedDestination}; never replay blindly.
    </p>
  {/if}
  {#if publication.blocked && !publication.busy}
    <button onclick={acknowledgeWorkbook}>Acknowledge workbook outcome</button>
  {/if}
  <p>Project {project}; selected SU {su}. Whole selected-SU scope; profile navigation does not filter this report.</p>
  <label for="long-environment-title">Title</label>
  <textarea
    id="long-environment-title"
    data-source-control="rptSvTitle"
    rows="2"
    value={title}
    disabled={!!preferenceView?.busy || !!preferenceView?.blocked || workbookBarrier}
    oninput={(event) => editTitle(event.currentTarget.value)}></textarea>
  <div class="actions">
    <button
      data-long-environment-preferences-save
      disabled={busy ||
        !!preferenceView?.busy ||
        !!preferenceView?.blocked ||
        !!preferenceView?.draftError ||
        !preferenceView?.saved ||
        workbookBarrier}
      onclick={saveTitle}
    >
      Save reviewed title
    </button>
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
      {workbookReview.workbookSHA256}. Hidden lossless source metadata preserves typed NULL/empty values and
      diagnostics.
    </p>
    <ul>
      {#each workbookReview.sheets as sheet}
        <li>Unit “{sheet.unit}” → worksheet “{sheet.name}”</li>
      {/each}
    </ul>
    <label for="environment-workbook-destination">New XLSX output file (existing files are never replaced)</label>
    <textarea
      id="environment-workbook-destination"
      rows="2"
      disabled={busy || preferenceBarrier || workbookBarrier}
      bind:value={destination}></textarea>
    <button
      disabled={busy || preferenceBarrier || workbookBarrier || !destination || !/\.xlsx$/i.test(destination)}
      onclick={publishWorkbook}
    >
      Publish reviewed XLSX workbook
    </button>
  {/if}
  {#each preferenceView?.receipts ?? [] as receipt}
    {#if receipt.kind !== 'known'}
      <p data-long-environment-preferences-receipt data-long-environment-preferences-unknown-receipt role="alert">
        Preference receipt: outcome unknown; changed unknown; committed unknown. {receipt.errorMessage}
      </p>
    {/if}
  {/each}
  <p class="guidance">
    Load saved title explicitly, review the literal draft, then Save or Undo. Save changes only
    ReportOptions.LEReportTitle in YAML. Input and report preparation never save preferences.
  </p>
  {#if su === 'None'}<p>Select an SU in Projects &amp; context before viewing the report.</p>{/if}
  {#if preview}
    <LongEnvironmentPreviewBody {preview} />
  {/if}
  <p class="guidance">
    Long Environment report preview. NULL, empty text, and historical storage remain distinct; missing rows and
    conflicting unit names are surfaced without silent modification. Workbook export writes to a new .xlsx destination
    without overwriting existing files.
  </p>
</section>

<style>
  .report {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    min-width: 0;
    overflow-wrap: anywhere;
    gap: 0.75rem;
  }
  .report-sticky-bar {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 0.75rem;
  }
  .report-sticky-bar h1 {
    margin: 0;
    font-size: 1.5rem;
  }
  textarea {
    box-sizing: border-box;
    min-width: 0;
    border: 1px solid var(--vpro-border);
    border-radius: 0.4rem;
    padding: 0.6rem;
    width: 100%;
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    align-items: center;
  }
  button {
    border: 1px solid var(--vpro-border);
    border-radius: 0.4rem;
    padding: 0.5rem 0.75rem;
    background: var(--vpro-surface);
  }
  button:disabled {
    opacity: 0.5;
  }
  .error {
    color: var(--vpro-error);
  }
  .guidance {
    color: var(--vpro-ink-secondary);
    font-size: 0.875rem;
  }
</style>
