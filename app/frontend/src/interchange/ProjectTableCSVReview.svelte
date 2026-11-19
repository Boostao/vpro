<script module lang="ts">
  import { notifications } from '../shell/notificationService.svelte';
</script>

<script lang="ts">
  import { onDestroy } from 'svelte';
  import { ImportExportService } from '../../bindings/github.com/boostao/vpro/app';
  import { ReadRequests } from '../shared/readRequests';
  import { coreTableSuffixes, validateProjectTableCSVReview, type ValidatedProjectTableCSVReview } from './projectTableCSV';
  import { reportCellText } from '../reports/longEnvironmentReport';
  import { chooseTableCSVArchiveFile, tableCSVArchivePublicationSession, validateTableCSVArchiveReview,
    validTableCSVArchiveDestination, type ValidatedTableCSVArchiveReview } from './tableCSVArchiveExport';

  let { contextId, project, projectPath, onBusyChange }: {
    contextId: string; project: string; projectPath: string; onBusyChange: (busy: boolean) => void;
  } = $props();
  let suffix = $state<string>('Env');
  let busy = $state(false);
  let error = $state('');
  let review = $state<ValidatedProjectTableCSVReview | null>(null);
  const archiveEnabled = true;
  const scope = () => ({ contextId, project, projectPath });
  const publicationSession = archiveEnabled ? tableCSVArchivePublicationSession(scope()) : null;
  let publication = $state(publicationSession?.view() ?? null);
  let approval = $state<ValidatedTableCSVArchiveReview | null>(null);
  let destination = $state('');
  let lastNotifiedStorageError = '';
  let lastNotifiedReceiptKey = '';
  const unsubscribe = publicationSession?.subscribe(() => {
    publication = publicationSession.view();
    updateBusy();
    if (typeof notifications !== 'undefined') {
      if (publication.storageError && publication.storageError !== lastNotifiedStorageError) {
        lastNotifiedStorageError = publication.storageError;
        notifications.error('CSV archive storage error', publication.storageError, {
          category: 'reports',
          source: 'CSV Export',
          contextTag: project || undefined,
        });
      }
      const latest = publication.receipts.at(-1);
      if (!publication.busy && latest && latest.phase !== 'pending') {
        const key = `${publication.receipts.length}:${latest.phase}:${latest.outcome?.status ?? ''}:${latest.outcome?.path ?? ''}:${latest.error}`;
        if (key !== lastNotifiedReceiptKey) {
          lastNotifiedReceiptKey = key;
          if (latest.phase === 'known' && latest.outcome?.status === 'published') {
            notifications.success(
              'CSV archive exported',
              `Exported ${latest.table} CSV archive to ${latest.outcome.path || latest.requestedDestination}.`,
              { category: 'reports', source: 'CSV Export', contextTag: project || undefined },
            );
          } else {
            notifications.error(
              'CSV archive export failed',
              latest.error || latest.outcome?.errorMessage || `CSV archive export outcome for ${latest.table}: ${latest.phase}.`,
              { category: 'reports', source: 'CSV Export', contextTag: project || undefined },
            );
          }
        }
      }
    }
  });
  const reads = new ReadRequests();
  let generation = 0;

  function updateBusy() { onBusyChange(busy || !!publication?.busy || !!publication?.blocked); }
  function cancel() {
    generation++; reads.cancelAll(); busy = false; approval = null; updateBusy();
  }
  async function show() {
    if (busy || publication?.busy || publication?.blocked) {
      error = 'Wait for or cancel the current table read and acknowledge any archive attempt before another review.';
      if (typeof notifications !== 'undefined') {
        notifications.error('CSV table review blocked', error, { category: 'reports', source: 'CSV Export', contextTag: project || undefined });
      }
      return;
    }
    cancel(); const request = generation, table = `${project}_${suffix}`;
    review = null; error = ''; busy = true; updateBusy();
    try {
      if (archiveEnabled) {
        const value = await reads.track(ImportExportService.GetTableCSVArchiveReview(contextId, JSON.stringify({ table })));
        if (request !== generation) return;
        const validated = await validateTableCSVArchiveReview(value, { contextId, project, projectPath }, table);
        if (request !== generation) return;
        approval = validated; review = validated.review;
        return;
      }
      const value = await reads.track(ImportExportService.GetProjectTableCSVReview(contextId, table));
      if (request !== generation) return;
      const validated = await validateProjectTableCSVReview(value, contextId, project, projectPath, table);
      if (request !== generation) return;
      review = validated;
    } catch (cause) {
      if (request === generation) {
        error = `Table review unavailable; no data, audits, configuration or export files written: ${String(cause)}`;
        if (typeof notifications !== 'undefined') {
          notifications.error('CSV table review unavailable', error, { category: 'reports', source: 'CSV Export', contextTag: project || undefined });
        }
      }
    } finally {
      if (request === generation) { busy = false; updateBusy(); }
    }
  }
  function changeTable() { cancel(); review = null; error = ''; }
  async function chooseDestination() {
    if (!publicationSession || busy || publication?.busy || publication?.blocked) return;
    error = '';
    try { destination = await publicationSession.chooseDestination(destination, chooseTableCSVArchiveFile); }
    catch (cause) {
      error = `Destination chooser unavailable; destination unchanged, no publication invoked: ${String(cause)}`;
      if (typeof notifications !== 'undefined') {
        notifications.error('CSV destination chooser failed', error, { category: 'reports', source: 'CSV Export', contextTag: project || undefined });
      }
    }
  }
  async function publish() {
    const table = `${project}_${suffix}`;
    if (!publicationSession || !approval || approval.review.manifest.table !== table || busy ||
        publication?.busy || publication?.blocked || !validTableCSVArchiveDestination(destination)) return;
    const approved = $state.snapshot(approval);
    approval = null; review = null; error = '';
    try {
      await publicationSession.publish(approved, table, destination, request =>
        ImportExportService.ExportReviewedTableCSVArchive(contextId, JSON.stringify(request)));
      const view = publicationSession.view();
      const latest = view.receipts.at(-1);
      if (typeof notifications !== 'undefined' && latest) {
        const key = `${view.receipts.length}:${latest.phase}:${latest.outcome?.status ?? ''}:${latest.outcome?.path ?? ''}:${latest.error}`;
        if (typeof lastNotifiedReceiptKey === 'undefined' || lastNotifiedReceiptKey !== key) {
          if (typeof lastNotifiedReceiptKey !== 'undefined') lastNotifiedReceiptKey = key;
          if (latest.phase === 'known' && latest.outcome?.status === 'published') {
            notifications.success(
              'CSV archive exported',
              `Exported ${table} CSV archive to ${latest.outcome.path || destination}.`,
              { category: 'reports', source: 'CSV Export', contextTag: project || undefined },
            );
          } else {
            notifications.error(
              'CSV archive export failed',
              latest.error || latest.outcome?.errorMessage || `CSV archive export outcome for ${table}: ${latest.phase}.`,
              { category: 'reports', source: 'CSV Export', contextTag: project || undefined },
            );
          }
        }
      }
    } catch (cause) {
      error = `Archive export not invoked; review again before proceeding: ${String(cause)}`;
      if (typeof notifications !== 'undefined') {
        notifications.error('CSV archive export failed', error, { category: 'reports', source: 'CSV Export', contextTag: project || undefined });
      }
    }
  }
  function acknowledge() {
    try { publicationSession?.acknowledge(); changeTable(); }
    catch (cause) {
      error = String(cause);
      if (typeof notifications !== 'undefined') {
        notifications.error('CSV archive acknowledgement failed', error, { category: 'reports', source: 'CSV Export', contextTag: project || undefined });
      }
    }
  }
  onDestroy(cancel);
  onDestroy(() => unsubscribe?.());
</script>

<section class="table-review" data-project-table-csv-review aria-label="Project table CSV review">
  <header class="sticky top-0 z-20 bg-white/95 backdrop-blur-xs py-2 border-b border-vpro-border" data-workbench-sticky-bar>
    <h1>Project table CSV review</h1>
    <div class="actions">
      <label for="csv-core-table">Physical core table
        <select id="csv-core-table" bind:value={suffix} disabled={(busy && !archiveEnabled) || !!publication?.busy || !!publication?.blocked} onchange={changeTable}>
          {#each coreTableSuffixes as value}<option value={value}>{project}_{value}</option>{/each}
        </select>
      </label>
      <button type="button" data-table-csv-read disabled={busy || !!publication?.busy || !!publication?.blocked} onclick={show}>Review core table CSV</button>
      {#if archiveEnabled}
        <button type="button" data-table-csv-archive-choose disabled={busy || !!publication?.busy || !!publication?.blocked} onclick={chooseDestination}>Choose ZIP destination...</button>
        <button type="button" data-table-csv-archive-publish data-table-csv-archive-export disabled={busy || !!publication?.busy || !!publication?.blocked ||
          !approval || approval.review.manifest.table !== `${project}_${suffix}` || !validTableCSVArchiveDestination(destination)} onclick={publish}>
          Export reviewed {project}_{suffix} CSV archive
        </button>
      {/if}
      {#if busy}<button type="button" data-table-csv-cancel onclick={cancel}>Cancel table read</button>{/if}
    </div>
  </header>
  {#if publication}
    {#each publication.receipts.filter(receipt => receipt.phase === 'unknown') as receipt, index}
      <section class="receipt" data-table-csv-archive-attempt
        data-table-csv-archive-unknown-receipt=""
        aria-label={`Archive attempt ${index + 1}`}>
        <h2>Archive attempt {index + 1}: outcome unknown</h2>
        <p>{receipt.table}; requested literal destination: {receipt.requestedDestination}</p>
        <p>Expected archive SHA256: {receipt.archiveSHA256}</p>
        <p>{receipt.acknowledged ? 'Acknowledged; historical evidence retained.' : 'Unacknowledged. Close and navigation are blocked. Publication cannot be cancelled or automatically replayed.'}</p>
      </section>
    {/each}
    {#if publication.blocked && !publication.storageError}
      <button type="button" data-table-csv-archive-acknowledge disabled={publication.busy} onclick={acknowledge}>Acknowledge archive outcome; retain all receipts</button>
    {/if}
  {/if}
  <p>Project {project}. Whole physical project table; selected SU and plot/profile filters are not applied.</p>
  <dl><div><dt>Owned project database</dt><dd>{projectPath}</dd></div></dl>
  {#if archiveEnabled}
    {#if destination && !validTableCSVArchiveDestination(destination)}
      <p class="error" role="alert">Destination contains NUL or malformed UTF-16; export is blocked, and no spelling repair is applied.</p>
    {/if}
    <label for="table-csv-archive-destination">Project table CSV archive destination (.zip)</label>
    <textarea id="table-csv-archive-destination" rows="3" bind:value={destination} disabled={busy || !!publication?.busy || !!publication?.blocked}></textarea>
    {#if approval}
      <dl>
        <div><dt>Approved physical table</dt><dd>{approval.review.manifest.table}</dd></div>
        <div><dt>Backend source approval (not independently verified by browser)</dt><dd>{approval.approvalHash}</dd></div>
        <div><dt>Backend archive SHA256 (not independently computed by browser)</dt><dd>{approval.archiveSHA256}</dd></div>
        <div><dt>Backend archive byte count / format / version</dt><dd>{approval.byteCount} / {approval.format} / {approval.version}</dd></div>
      </dl>
    {/if}
    <p class="notice">Exports a verified project table CSV archive (.zip) with JSON-escaped text and typed storage metadata (distinguishing NULL, empty text, and BLOBs).
      Exact destination paths are preserved without overwriting existing files.</p>
  {:else}
    <p class="notice">Project table CSV preview. CSV text fields use JSON string escaping, and storage tags distinguish NULL, empty text, and BLOBs.</p>
  {/if}
  {#if review}
    <p role="status" data-table-csv-summary>{review.manifest.rowIds.length} physical rows;
      {review.manifest.columns.length} columns. No data, audits, configuration or export files written.</p>
    <dl>
      <div><dt>Description metadata</dt><dd>{review.descriptionMetadataPresent ? 'Present physical table' : 'Absent physical table'}</dd></div>
      <div><dt>CSV SHA256</dt><dd data-table-csv-checksum>{review.manifest.sha256}</dd></div>
    </dl>
    <details>
      <summary>Physical Description candidates ({review.manifest.descriptions.length})</summary>
      {#each review.manifest.descriptions as candidate (candidate.rowId)}
        <p>Row {candidate.rowId}: {reportCellText(candidate.value)}</p>
      {:else}<p>No matching candidates. No description was inferred.</p>{/each}
    </details>
    <label for="csv-value-preview">JSON-escaped value CSV (read-only)</label>
    <textarea id="csv-value-preview" readonly rows="12" value={review.csv}></textarea>
    <details>
      <summary>Version1 typed manifest</summary>
      <pre>{JSON.stringify(review.manifest, null, 2)}</pre>
    </details>
  {/if}
</section>

<style>
  .table-review { padding: 1rem; max-width: 100%; min-width: 0; }
  h1 { font-size: 1.5rem; margin-bottom: .75rem; color: var(--vpro-navy); }
  h2 { color: var(--vpro-navy); }
  .actions { display: flex; flex-wrap: wrap; align-items: end; gap: .75rem; margin: 1rem 0; }
  .actions label { display: flex; flex-direction: column; gap: .3rem; min-width: 0; flex: 1 1 12rem; }
  select, button, textarea { border: 1px solid var(--vpro-border-strong); border-radius: .25rem; padding: .4rem .6rem; color: var(--vpro-ink); background: var(--vpro-surface); min-width: 0; }
  button:disabled { opacity: .5; }
  textarea { display: block; width: 100%; box-sizing: border-box; margin-top: .4rem; font-family: monospace; }
  dl > div { margin: .6rem 0; }
  dt { font-weight: 600; color: var(--vpro-ink); }
  dd, p { overflow-wrap: anywhere; }
  details { margin: .75rem 0; }
  pre { overflow: auto; max-height: 24rem; padding: .5rem; background: var(--vpro-canvas); border: 1px solid var(--vpro-border); }
  .notice { color: var(--vpro-ink-secondary); }
  .error { color: var(--vpro-error); background: var(--vpro-error-bg); border: 1px solid var(--vpro-error); padding: .5rem; border-radius: .25rem; }
  .receipt { border: 1px solid var(--vpro-border); background: var(--vpro-surface); padding: .75rem; margin: .75rem 0; border-radius: .25rem; }
  .receipt p { white-space: pre-wrap; }
</style>
