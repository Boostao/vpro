<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { EnvironmentReportService } from '../../bindings/github.com/boostao/vpro/app';
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
  import { notifications } from '../shell/notificationService.svelte';

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
    cancel();
    error = '';
    const ctxTag = typeof hierarchy === 'string' && hierarchy && hierarchy !== 'None' ? hierarchy : undefined;
    try {
      await session.publish(workbook, destination, (request) =>
        EnvironmentReportService.ExportReviewedSubzoneMatrix(contextId, JSON.stringify(request))
      );
      if (typeof syncPublicationNotifications === 'function') {
        syncPublicationNotifications();
      } else {
        const settled = session.view();
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
            { category: 'reports', source: 'Subzone Matrix', contextTag: ctxTag }
          );
        }
      }
    } catch (cause) {
      error = formatError(cause);
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

  onDestroy(() => {
    unsubscribe();
    cancel();
  });
</script>

<section class="matrix" data-subzone-matrix-report aria-label="Subzone Matrix of Units">
  <header
    class="sticky top-0 z-20 bg-white/95 backdrop-blur-xs py-2 border-b border-vpro-border report-sticky-bar"
    data-report-sticky-bar
  >
    <h1>Subzone Matrix of Units</h1>
    <div class="actions">
      <button type="button" data-matrix-read disabled={busy || barrier || !available} onclick={() => show()}>
        Review matrix
      </button>
      <button
        type="button"
        data-matrix-workbook-review
        disabled={busy || barrier || !available}
        onclick={reviewWorkbook}
      >
        Review XLSX workbook
      </button>
      {#if busy}
        <button type="button" data-matrix-cancel onclick={cancel}>Cancel matrix read</button>
      {/if}
    </div>
  </header>
  {#if !available}<p role="status">Select a hierarchy in the sidebar to view this report.</p>{/if}
  <dl class="provenance">
    <div>
      <dt>Selected hierarchy</dt>
      <dd>{hierarchy}</dd>
    </div>
    <div>
      <dt>Hierarchy file</dt>
      <dd>{hierarchyPath}</dd>
    </div>
    {#if preview}<div>
        <dt>Reference labels file</dt>
        <dd>{preview.labelsPath}</dd>
      </div>{/if}
  </dl>
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
  {#if workbook}
    <section class="workbook" data-matrix-workbook aria-label="Reviewed XLSX publication">
      <h2>Excel workbook preview</h2>
      <p>Estimated size: {workbook.bytes} bytes (1 worksheet).</p>
      <dl>
        <div>
          <dt>Workbook checksum (SHA-256)</dt>
          <dd>{workbook.workbookSHA256}</dd>
        </div>
        <div>
          <dt>Review snapshot ID</dt>
          <dd>{workbook.approvalHash}</dd>
        </div>
      </dl>
      <label for="matrix-destination">
        New XLSX destination
        <input id="matrix-destination" data-matrix-destination bind:value={destination} disabled={busy || barrier} />
      </label>
      <button type="button" data-matrix-publish disabled={busy || barrier || !destination} onclick={publishWorkbook}>
        Publish reviewed XLSX
      </button>
    </section>
  {/if}
  {#if !publication.outcome && publication.blocked && !publication.busy}
    <p data-matrix-unknown role="alert">
      Workbook export status is unknown. Inspect {publication.requestedDestination || 'the destination file'} before exporting
      again.
    </p>
  {/if}
  {#if publication.blocked && !publication.busy}
    <button type="button" data-matrix-acknowledge onclick={acknowledge}>Acknowledge workbook outcome</button>
  {/if}
  <p class="guidance">
    Uses the selected hierarchy and standard BEC unit labels, not the current project or site-unit table. Previewing and
    exporting leave your hierarchy and saved settings unchanged. Exported Excel workbooks use rotated column headings
    and estimated column widths (not native Excel AutoFit), and export never overwrites an existing file.
  </p>
</section>

<style>
  .matrix {
    min-width: 0;
    padding: 1rem;
    background: var(--vpro-canvas);
    color: var(--vpro-ink);
  }
  .report-sticky-bar {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 0.75rem;
    padding-inline: 0.75rem;
    border-radius: 0.35rem;
  }
  .report-sticky-bar h1 {
    margin: 0;
    color: var(--vpro-navy);
  }
  .report-sticky-bar .actions {
    margin-block: 0;
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    align-items: end;
    gap: 0.75rem;
    margin-block: 1rem;
  }
  button {
    min-height: 2.5rem;
    padding: 0.5rem 0.85rem;
    border: 1px solid var(--vpro-navy);
    border-radius: 0.25rem;
    background: var(--vpro-navy);
    color: var(--vpro-surface);
    font-weight: 600;
    cursor: pointer;
  }
  button:hover:not(:disabled) {
    background: var(--vpro-navy-dark);
    border-color: var(--vpro-navy-dark);
  }
  button:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }
  .provenance,
  .workbook {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 0.5rem;
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
  .workbook {
    margin-block: 1rem;
    padding: 1rem;
    background: var(--vpro-surface);
    border: 1px solid var(--vpro-border);
    border-radius: 0.5rem;
  }
  .workbook button {
    justify-self: start;
  }
  .guidance {
    margin-block-start: 1rem;
    font-size: 0.9rem;
    color: var(--vpro-ink-secondary);
  }
</style>
