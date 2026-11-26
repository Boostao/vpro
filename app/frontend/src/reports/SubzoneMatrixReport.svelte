<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { EnvironmentReportService, type HTMLReportResult } from '../../bindings/github.com/boostao/vpro/app';
  import { ReadRequests, formatError } from '../shared/readRequests';
  import {
    matrixPageFromWire,
    matrixWorkbookFromWire,
    sameMatrixSource,
    matrixCellText,
    matrixPublicationSession,
    type MatrixPage,
    type MatrixWorkbookReview,
  } from './subzoneMatrixReport';
  import CompactReportShell from './CompactReportShell.svelte';
  import { notifications } from '../shell/notificationService.svelte';
  import { defaultWebExportFilename } from '../shell/webReadOnlyShell';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import { formatWebDownloadFeedback } from '../web/webMeta';
  import type { QuickExportSummary } from './compactReport';
  import * as quick from './compactReportRunners';

  let {
    contextId,
    hierarchy,
    hierarchyPath,
    onBusyChange,
  }: {
    contextId: string;
    hierarchy: string;
    hierarchyPath: string;
    onBusyChange: (busy: boolean) => void;
  } = $props();

  const owner = untrack(() => ({ contextId, hierarchy, hierarchyPath }));
  const session = matrixPublicationSession(owner);
  let publication = $state(session.view());
  let preview = $state.raw<MatrixPage | null>(null);
  let workbook = $state.raw<MatrixWorkbookReview | null>(null);
  let busy = $state(false);
  let error = $state('');
  let destination = $state('');
  let quickExporting = $state(false);
  let quickRendering = $state(false);
  let quickError = $state('');
  let quickExportResult = $state.raw<QuickExportSummary | null>(null);
  let quickHtmlReport = $state.raw<HTMLReportResult | null>(null);
  const barrier = $derived(publication.busy || publication.blocked);
  const available = $derived(!!contextId && hierarchy !== 'None' && !!hierarchyPath);
  const reads = new ReadRequests();
  const limit = 25;
  let generation = 0;
  let lastPubKey = '';

  function reportBusy() {
    onBusyChange(busy || barrier);
  }

  function syncPublicationNotifications() {
    const settled = session.view();
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
    const ctxTag = typeof hierarchy === 'string' && hierarchy && hierarchy !== 'None' ? hierarchy : undefined;
    if (settled.outcome?.status === 'published' && !settled.error) {
      const exportedPath = settled.outcome.path || settled.requestedDestination || destination;
      notifications.success('Subzone Matrix workbook exported', exportedPath, {
        category: 'reports',
        source: 'Subzone Matrix',
        contextTag: ctxTag,
      });
    } else if (settled.error || settled.outcome) {
      notifications.error(
        'Subzone Matrix workbook export failed',
        settled.error ||
          `Export ${settled.outcome?.status ?? 'failed'} for ${settled.requestedDestination || destination}`,
        {
          category: 'reports',
          source: 'Subzone Matrix',
          contextTag: ctxTag,
        }
      );
    }
  }

  const unsubscribe = session.subscribe(() => {
    publication = session.view();
    if (publication.busy) workbook = null;
    syncPublicationNotifications();
    reportBusy();
  });
  syncPublicationNotifications();

  function cancel() {
    generation++;
    reads.cancelAll();
    busy = false;
    reportBusy();
  }

  async function show(offset = 0) {
    if (busy || barrier || !available) return;
    const prior = offset === 0 ? null : preview;
    cancel();
    const request = generation;
    error = '';
    busy = true;
    reportBusy();
    try {
      const value = await reads.track(
        EnvironmentReportService.GetSubzoneMatrixPreview(contextId, JSON.stringify({ offset, limit }))
      );
      if (request !== generation) return;
      const validated = matrixPageFromWire(value, owner, offset, limit);
      if (prior && !sameMatrixSource(prior, validated)) {
        throw new Error('Complete source changed between pages. Reload from the first page before continuing.');
      }
      if (request !== generation) return;
      if (workbook && !sameMatrixSource(workbook.preview, validated)) workbook = null;
      preview = validated;
    } catch (cause) {
      if (request === generation) {
        preview = null;
        workbook = null;
        error = `Subzone Matrix unavailable: ${formatError(cause)}`;
        notifications.error('Subzone Matrix load failed', error, {
          category: 'reports',
          source: 'Subzone Matrix',
          contextTag: typeof hierarchy === 'string' && hierarchy && hierarchy !== 'None' ? hierarchy : undefined,
        });
      }
    } finally {
      if (request === generation) {
        busy = false;
        reportBusy();
      }
    }
  }

  async function reviewWorkbook() {
    if (busy || barrier || !available) return;
    cancel();
    const request = generation;
    error = '';
    workbook = null;
    busy = true;
    reportBusy();
    try {
      const value = await reads.track(EnvironmentReportService.GetSubzoneMatrixReview(contextId));
      if (request !== generation) return;
      const validated = matrixWorkbookFromWire(value, owner);
      if (request !== generation) return;
      workbook = validated;
      preview = validated.preview;
    } catch (cause) {
      if (request === generation) {
        error = `Workbook review unavailable: ${formatError(cause)}`;
        notifications.error('Subzone Matrix workbook review failed', error, {
          category: 'reports',
          source: 'Subzone Matrix',
          contextTag: typeof hierarchy === 'string' && hierarchy && hierarchy !== 'None' ? hierarchy : undefined,
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
    if (busy || barrier || !workbook) return;
    const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
    const targetDestination =
      webReadOnly && !destination.trim()
        ? typeof defaultWebExportFilename === 'function'
          ? defaultWebExportFilename(`${hierarchy || 'subzone'}_matrix`, '.xlsx')
          : `${hierarchy || 'subzone'}_matrix.xlsx`
        : destination;
    cancel();
    error = '';
    const ctxTag = typeof hierarchy === 'string' && hierarchy && hierarchy !== 'None' ? hierarchy : undefined;
    try {
      await session.publish(workbook, targetDestination, (request) =>
        EnvironmentReportService.ExportReviewedSubzoneMatrix(contextId, JSON.stringify(request))
      );
      if (typeof syncPublicationNotifications === 'function') {
        syncPublicationNotifications();
      } else {
        const settled = session.view();
        if (settled.outcome?.status === 'published' && !settled.error) {
          const exportedPath = settled.outcome.path || settled.requestedDestination || targetDestination;
          notifications.success(
            webReadOnly ? 'Subzone Matrix workbook downloaded' : 'Subzone Matrix workbook exported',
            webReadOnly ? targetDestination : exportedPath,
            {
              category: 'reports',
              source: 'Subzone Matrix',
              contextTag: ctxTag,
            }
          );
        } else if (settled.error || settled.outcome) {
          notifications.error(
            'Subzone Matrix workbook export failed',
            settled.error ||
              `Export ${settled.outcome?.status ?? 'failed'} for ${settled.requestedDestination || targetDestination}`,
            { category: 'reports', source: 'Subzone Matrix', contextTag: ctxTag }
          );
        }
      }
    } catch (cause) {
      error =
        webReadOnly && typeof formatWebDownloadFeedback === 'function'
          ? formatWebDownloadFeedback(cause, 'Subzone Matrix workbook download')
          : formatError(cause);
      notifications.error('Subzone Matrix workbook export failed', error, {
        category: 'reports',
        source: 'Subzone Matrix',
        contextTag: ctxTag,
      });
    }
  }

  function acknowledge() {
    session.acknowledge();
    workbook = null;
  }

  async function quickExportSpreadsheet() {
    if (!contextId || !available || quickExporting || quickRendering) return;
    [quickExporting, quickError] = [true, ''];
    const req = quick.buildSubzoneMatrixQuickRequest(hierarchy);
    const out = await quick.runQuickSpreadsheetExport({
      source: 'Subzone Matrix', project: hierarchy, kind: 'env',
      invoke: () => EnvironmentReportService.QuickRunSubzoneMatrixWorkbook(contextId, req),
    });
    [quickExportResult, quickError, quickExporting] = [out.summary, out.error, false];
  }

  async function quickDisplayReport() {
    if (!contextId || !available || quickExporting || quickRendering) return;
    [quickRendering, quickError] = [true, ''];
    const out = await quick.runQuickHTMLDisplay({
      source: 'Subzone Matrix', project: hierarchy,
      invoke: () => EnvironmentReportService.RenderSubzoneMatrixHTMLReport(contextId),
    });
    [quickHtmlReport, quickError, quickRendering] = [out.report, out.error, false];
  }

  onDestroy(() => {
    unsubscribe();
    cancel();
  });
</script>

<section class="matrix" data-subzone-matrix-report aria-label="Subzone Matrix of Units">
  <CompactReportShell
    title="Subzone Matrix of Units"
    subtitle="Association-by-subzone matrix generated from the active hierarchy."
    {contextId}
    {hierarchy}
    requiresHierarchy={true}
    busy={busy || barrier}
    actionDisabled={!available}
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
      <button type="button" class="btn-secondary" data-matrix-read disabled={busy || barrier || !available} onclick={() => show()}>
        Review matrix
      </button>
      {#if busy}
        <button type="button" class="btn-secondary" data-matrix-cancel onclick={cancel}>Cancel</button>
      {/if}
    {/snippet}
    {#snippet quickOptions()}
      <dl class="provenance-inline" data-subzone-matrix-quick-options>
        <div><dt>Selected hierarchy</dt><dd>{hierarchy}</dd></div>
        <div><dt>Hierarchy file</dt><dd>{hierarchyPath || 'None'}</dd></div>
        {#if preview}<div><dt>Reference labels file</dt><dd>{preview.labelsPath}</dd></div>{/if}
      </dl>
    {/snippet}
    {#snippet advanced()}
      <div class="actions">
        <button
          type="button"
          data-matrix-workbook-review
          disabled={busy || barrier || !available}
          onclick={reviewWorkbook}
        >
          Review XLSX workbook
        </button>
      </div>
      {#if workbook}
        <section class="workbook" data-matrix-workbook aria-label="Reviewed XLSX publication">
          <h2>Excel workbook preview</h2>
          <p>Estimated size: {workbook.bytes} bytes (1 worksheet).</p>
          <dl>
            <div><dt>Workbook checksum (SHA-256)</dt><dd>{workbook.workbookSHA256}</dd></div>
            <div><dt>Review snapshot ID</dt><dd>{workbook.approvalHash}</dd></div>
          </dl>
          {#if !IS_WEB_READONLY}
            <label for="matrix-destination">
              New XLSX destination
              <input id="matrix-destination" data-matrix-destination bind:value={destination} disabled={busy || barrier} />
            </label>
          {/if}
          <button
            type="button"
            data-matrix-publish
            disabled={busy || barrier || (!IS_WEB_READONLY && !destination)}
            onclick={publishWorkbook}
          >
            {IS_WEB_READONLY ? 'Download reviewed XLSX' : 'Publish reviewed XLSX'}
          </button>
        </section>
      {/if}
      {#if !publication.outcome && publication.blocked && !publication.busy}
        <p data-matrix-unknown role="alert">
          Workbook export status is unknown. Inspect {publication.requestedDestination || 'the destination file'} before
          exporting again.
        </p>
      {/if}
      {#if publication.blocked && !publication.busy}
        <button type="button" data-matrix-acknowledge onclick={acknowledge}>Acknowledge workbook outcome</button>
      {/if}
      <p class="guidance">
        Uses the selected hierarchy and standard BEC unit labels, not the current project or site-unit table. Exported
        Excel workbooks use estimated column widths (not native Excel AutoFit) and never overwrites an existing file.
      </p>
    {/snippet}
    {#snippet results()}
      {#if preview}
        <p data-matrix-count>
          {preview.total} association rows; showing {preview.rows.length ? preview.offset + 1 : 0}
          through {preview.rows.length ? preview.offset + preview.rows.length : 0}.
        </p>
        {#if preview.total === 0}<p role="status">No matrix rows found for the selected hierarchy.</p>{/if}
        <div class="table-scroll">
          <table data-matrix-table>
            <caption>Subzone/Association Matrix: {hierarchy}</caption>
            <thead>
              <tr>
                <th scope="col">Name</th>
                {#each preview.columns as column}<th scope="col">{column}</th>{/each}
              </tr>
            </thead>
            <tbody>
              {#each preview.rows as row, index}
                <tr aria-label={`Association row ${preview.offset + index + 1}`}>
                  <th scope="row">{matrixCellText(row.name)}</th>
                  {#each row.values as value}<td>{matrixCellText(value)}</td>{/each}
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
        <div class="actions">
          <button
            type="button"
            data-matrix-previous
            disabled={busy || barrier || preview.offset === 0}
            onclick={() => show(Math.max(0, preview!.offset - limit))}
          >
            Previous matrix rows
          </button>
          <button
            type="button"
            data-matrix-next
            disabled={busy || barrier || preview.offset + limit >= preview.total}
            onclick={() => show(preview!.offset + limit)}
          >
            Next matrix rows
          </button>
        </div>
      {/if}
    {/snippet}
  </CompactReportShell>
</section>

<style>
  .matrix {
    min-width: 0;
    padding: 1rem;
    background: var(--vpro-canvas);
    color: var(--vpro-ink);
  }
  .provenance-inline {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 220px), 1fr));
    gap: 0.65rem;
    margin: 0;
    font-size: 0.82rem;
  }
  .provenance-inline dt {
    font-weight: 600;
    color: var(--vpro-navy);
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    align-items: end;
    gap: 0.75rem;
    margin-block: 0.5rem;
  }
  .btn-secondary,
  button {
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
  button:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }
  .workbook {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 0.5rem;
    padding: 0.85rem;
    background: var(--vpro-surface);
    border: 1px solid var(--vpro-border);
    border-radius: 0.4rem;
  }
  dd {
    margin: 0;
    overflow-wrap: anywhere;
  }
  label {
    display: grid;
    gap: 0.25rem;
  }
  input {
    box-sizing: border-box;
    width: 100%;
    min-width: 0;
    padding: 0.45rem;
    border: 1px solid var(--vpro-border);
    border-radius: 0.25rem;
    background: var(--vpro-surface);
    color: var(--vpro-ink);
  }
  .table-scroll {
    max-width: 100%;
    overflow-x: auto;
  }
  table {
    border-collapse: collapse;
    min-width: 100%;
    background: var(--vpro-surface);
  }
  th,
  td {
    min-width: 5rem;
    max-width: 24rem;
    padding: 0.5rem;
    text-align: left;
    border-bottom: 1px solid var(--vpro-border);
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  caption {
    text-align: left;
    font-weight: 600;
    color: var(--vpro-navy);
  }
  .workbook button {
    justify-self: start;
  }
</style>
