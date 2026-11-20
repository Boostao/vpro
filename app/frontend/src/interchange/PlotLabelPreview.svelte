<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { ContextService, ImportExportService } from '../../bindings/github.com/boostao/vpro/app';
  import type { PlotLabelPDFExportReview, PlotLabelPDFExportOutcome } from '../../bindings/github.com/boostao/vpro/app';
  import { ReadRequests, formatError } from '../shared/readRequests';
  import { plotLookupInputError } from '../shared/scopedPlotLookup';
  import { plotLabelFromHeader, type PlotLabelPreview } from './plotLabelPreview';
  import { validatePlotLabelRegionalPreview, type PlotLabelRegionalEvidence } from './plotLabelRegional';
  import { plotLabelPDFPublicationSession, validatePlotLabelPDFReview } from './plotLabelPDFExport';
  import type { PublicationView } from '../shared/publicationSession';
  import { notifications } from '../shell/notificationService.svelte';
  import PlotLabelFieldDetails from './PlotLabelFieldDetails.svelte';
  import {
    buildPdfNotificationKey,
    emitPlotLabelPdfExportToast,
    emitPlotLabelPdfRecoveryToast,
    fetchPlotLabelPreviewBundle,
  } from './plotLabelPreviewOps';

  let {
    contextId,
    project,
    projectPath = '',
    su = '',
    suPath = '',
    initialPlot = '',
    onBusyChange,
  }: {
    contextId: string;
    project: string;
    projectPath?: string;
    su?: string;
    suPath?: string;
    initialPlot?: string;
    onBusyChange: (busy: boolean) => void;
  } = $props();

  let plot = $state(untrack(() => initialPlot));
  let preview = $state<PlotLabelPreview | null>(null);
  let labelDate = $state('');
  let regionalEvidence = $state.raw<PlotLabelRegionalEvidence | null>(null);
  let error = $state('');
  let busy = $state(false);
  let pdfReview = $state.raw<PlotLabelPDFExportReview | null>(null);
  let destination = $state('');
  const reads = new ReadRequests();
  const pdfSession = untrack(() =>
    typeof plotLabelPDFPublicationSession === 'function'
      ? plotLabelPDFPublicationSession({ contextId, project, projectPath, su, suPath })
      : null
  );
  let publication = $state.raw<PublicationView<PlotLabelPDFExportOutcome>>(
    pdfSession?.view() ?? { busy: false, blocked: false, outcome: null, error: '', requestedDestination: '' }
  );
  const locked = $derived(busy || publication.busy || publication.blocked);
  const ownerKey = $derived(JSON.stringify([contextId, project, projectPath, su, suPath]));
  let generation = 0;
  let lastNotifiedPdfKey = '';

  function updateBusy() {
    onBusyChange(busy || publication.busy || publication.blocked);
  }

  const unsubscribe = pdfSession?.subscribe(() => {
    publication = pdfSession.view();
    updateBusy();
    if (!publication.busy) {
      const key = buildPdfNotificationKey(publication);
      if (key && key !== lastNotifiedPdfKey) {
        lastNotifiedPdfKey = key;
        emitPlotLabelPdfExportToast(
          notifications,
          publication,
          pdfReview?.preview.plotNumber,
          publication.requestedDestination,
          project
        );
      }
    }
  });

  function cancel() {
    generation++;
    reads.cancelAll();
    busy = false;
    updateBusy();
  }

  async function load() {
    const toastOpts = { category: 'reports' as const, source: 'Plot Labels', contextTag: project || undefined };
    if (busy || publication.busy || publication.blocked) {
      error = 'Finish or acknowledge the current plot label operation before loading another plot.';
      notifications.error('Plot label preview blocked', error, toastOpts);
      return;
    }
    const invalid = plotLookupInputError(plot);
    if (invalid) {
      error = invalid;
      notifications.error('Invalid plot number', error, toastOpts);
      return;
    }
    cancel();
    const request = generation;
    const key = ownerKey;
    const requestedPlot = plot;
    preview = null;
    error = '';
    labelDate = '';
    regionalEvidence = null;
    pdfReview = null;
    busy = true;
    updateBusy();
    try {
      const bundle = await fetchPlotLabelPreviewBundle({
        reads,
        owner: {
          contextId,
          project,
          projectPath: typeof projectPath === 'string' ? projectPath : '',
          su: typeof su === 'string' ? su : '',
          suPath: typeof suPath === 'string' ? suPath : '',
        },
        requestedPlot,
        isCurrent: () => request === generation && key === ownerKey,
        importExportSvc: typeof ImportExportService !== 'undefined' ? ImportExportService : undefined,
        contextSvc: ContextService,
        validators: {
          validatePlotLabelPDFReview:
            typeof validatePlotLabelPDFReview === 'function' ? validatePlotLabelPDFReview : undefined,
          validatePlotLabelRegionalPreview:
            typeof validatePlotLabelRegionalPreview === 'function' ? validatePlotLabelRegionalPreview : undefined,
          plotLabelFromHeader: typeof plotLabelFromHeader === 'function' ? plotLabelFromHeader : undefined,
          makeDate: () => new Date(),
        },
      });
      if (bundle.cancelled || request !== generation || key !== ownerKey) return;
      pdfReview = bundle.pdfReview;
      preview = bundle.preview;
      labelDate = bundle.labelDate;
      regionalEvidence = bundle.regionalEvidence;
      if (bundle.warningMessage) {
        error = bundle.warningMessage;
        notifications.warning('Label PDF unavailable; preview shown', bundle.warningMessage, toastOpts);
      }
    } catch (cause) {
      if (request === generation && key === ownerKey) {
        error = `Plot label preview unavailable: ${formatError(cause)}`;
        notifications.error('Plot label preview unavailable', error, toastOpts);
      }
    } finally {
      if (request === generation) {
        busy = false;
        updateBusy();
      }
    }
  }

  async function publishPDF() {
    const toastOpts = { category: 'reports' as const, source: 'Plot Labels', contextTag: project || undefined };
    if (!pdfSession || !pdfReview || busy || publication.busy || publication.blocked) {
      error = 'Review a saved plot label and finish any active export first.';
      notifications.error('Label PDF export blocked', error, toastOpts);
      return;
    }
    error = '';
    try {
      await pdfSession.publish(pdfReview, destination, (request) =>
        ImportExportService.ExportReviewedPlotLabelPDF(contextId, JSON.stringify(request))
      );
      const latest = pdfSession.view();
      const key = buildPdfNotificationKey(latest);
      if (typeof lastNotifiedPdfKey === 'undefined' || (key && lastNotifiedPdfKey !== key)) {
        if (typeof lastNotifiedPdfKey !== 'undefined' && key) lastNotifiedPdfKey = key;
        emitPlotLabelPdfExportToast(notifications, latest, pdfReview.preview.plotNumber, destination, project);
      }
    } catch (cause) {
      error = `Label PDF export unavailable: ${formatError(cause)}`;
      notifications.error('Label PDF export failed', error, toastOpts);
    }
  }

  async function recoverPDF() {
    if (!pdfSession) return;
    const toastOpts = { category: 'reports' as const, source: 'Plot Labels', contextTag: project || undefined };
    error = '';
    try {
      await pdfSession.recover((request) =>
        ImportExportService.RecoverPlotLabelPDFOutcome(contextId, JSON.stringify(request))
      );
      const latest = pdfSession.view();
      const key = buildPdfNotificationKey(latest);
      if (typeof lastNotifiedPdfKey === 'undefined' || (key && lastNotifiedPdfKey !== key)) {
        if (typeof lastNotifiedPdfKey !== 'undefined' && key) lastNotifiedPdfKey = key;
        emitPlotLabelPdfRecoveryToast(notifications, latest, project);
      }
    } catch (cause) {
      error = `PDF status check unavailable: ${formatError(cause)}`;
      notifications.error('Label PDF recovery failed', error, toastOpts);
    }
  }

  function acknowledgePDF() {
    if (!pdfSession) return;
    try {
      pdfSession.acknowledge();
    } catch (cause) {
      error = formatError(cause);
      notifications.error('Label PDF acknowledgement failed', error, {
        category: 'reports',
        source: 'Plot Labels',
        contextTag: project || undefined,
      });
    }
  }

  onDestroy(() => {
    unsubscribe?.();
    cancel();
  });
</script>

<section class="labels" data-plot-label-preview aria-label="VPro Plot Labels">
  <header
    class="sticky top-0 z-20 bg-white/95 backdrop-blur-xs py-2 border-b border-vpro-border"
    data-workbench-sticky-bar
  >
    <h1>VPro Plot Labels</h1>
    <p>Project {project}. Preview a saved plot label and export a single-page Letter PDF.</p>
    <form
      onsubmit={(event) => {
        event.preventDefault();
        void load();
      }}
    >
      <label for="plot-label-number">
        Plot number
        <input id="plot-label-number" bind:value={plot} disabled={locked} />
      </label>
      <button type="submit" disabled={locked}>Review saved plot label PDF</button>
      {#if busy}<button type="button" onclick={cancel}>Cancel label read</button>{/if}
    </form>
  </header>
  {#if preview}
    <section class="label" data-plot-label-card aria-label={`Label for saved plot ${preview.plotNumber1}`}>
      <h2>{preview.displayPlotNumber}</h2>
      <p class="zone">{preview.zone1}</p>
      <p class="project-id">{preview.projectId1 ?? ''}</p>
      <p class="representing" data-plot-label-representing>{preview.displayRepresenting ?? ''}</p>
      <footer><span>Label Date: {labelDate}</span><span>(VPro)</span></footer>
    </section>
    <PlotLabelFieldDetails {preview} {regionalEvidence} />
  {/if}
  <section class="pdf" data-plot-label-pdf-export aria-label="Portable saved label PDF">
    <h2>Portable saved label PDF</h2>
    {#if pdfReview}
      <dl class="pdf-meta">
        <div>
          <dt>Review snapshot ID</dt>
          <dd>{pdfReview.approvalHash}</dd>
        </div>
        <div>
          <dt>PDF checksum (SHA-256)</dt>
          <dd>{pdfReview.pdfSHA256}</dd>
        </div>
      </dl>
      <label for="plot-label-pdf-destination">
        New PDF destination
        <input id="plot-label-pdf-destination" bind:value={destination} disabled={locked} />
      </label>
      <button type="button" class="btn-primary" disabled={locked || !destination} onclick={() => void publishPDF()}>
        Export reviewed label PDF
      </button>
    {/if}
    {#if publication.blocked && !publication.busy}
      {#if publication.requestedDestination}
        <p data-plot-label-pdf-destination>Requested destination: {publication.requestedDestination}</p>
      {/if}
      {#if !publication.outcome}
        <p role="alert">PDF publication outcome is unknown. Check the status below before exporting again.</p>
        <button type="button" disabled={publication.busy} onclick={() => void recoverPDF()}>
          Recover PDF outcome readonly
        </button>
      {:else}
        <button type="button" disabled={publication.busy} onclick={acknowledgePDF}>
          Acknowledge retained PDF outcome
        </button>
      {/if}
    {/if}
    <p class="guidance">
      Creates a single-page Letter PDF with wrapped UTF-8 plot labels up to full 255-character descriptions and
      locale-formatted dates (including en-CA, fr-CA, and en-US). Export creates a new file without overwriting existing
      files or changing saved plot data. Print All and physical printing remain unavailable.
    </p>
  </section>
  <p class="guidance">
    Previewing a plot label leaves saved plot records and settings unchanged, and looks up the plot directly regardless
    of active Site Unit filters; six-position printing and Print All Plots remain unavailable.
  </p>
</section>

<style>
  .labels {
    padding: clamp(0.9rem, 2vw, 1.4rem);
    min-width: 0;
    max-width: 58rem;
    color: var(--vpro-ink);
  }
  h1 {
    margin: 0 0 0.5rem;
    color: var(--vpro-navy);
  }
  form {
    display: flex;
    flex-wrap: wrap;
    gap: 0.75rem;
    align-items: end;
    margin: 1rem 0;
    min-width: 0;
  }
  label {
    display: grid;
    gap: 0.25rem;
    min-width: 0;
    color: var(--vpro-ink);
  }
  input,
  button {
    font: inherit;
    padding: 0.45rem 0.7rem;
    min-height: 2.35rem;
  }
  input {
    border: 1px solid var(--vpro-border);
    border-radius: 4px;
    background: var(--vpro-surface);
    color: var(--vpro-ink);
    min-width: 0;
    max-width: 100%;
  }
  button {
    border: 1px solid var(--vpro-navy);
    border-radius: 4px;
    background: var(--vpro-surface);
    color: var(--vpro-navy);
    font-weight: 600;
    cursor: pointer;
  }
  button[type='submit'],
  .btn-primary {
    background: var(--vpro-navy);
    color: var(--vpro-surface);
  }
  button:disabled {
    opacity: 0.55;
    cursor: not-allowed;
  }
  .label {
    max-width: 34rem;
    min-width: 0;
    border: 1px solid var(--vpro-ink);
    border-top: 4px solid var(--vpro-gold);
    background: var(--vpro-surface);
    color: var(--vpro-ink);
    padding: 1.1rem 1.25rem 0.9rem;
    display: grid;
    gap: 0.35rem;
  }
  .label h2 {
    font-size: 2rem;
    line-height: 1.1;
    margin: 0;
    text-align: center;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  .zone,
  .project-id {
    font-size: 1.1rem;
    font-weight: 600;
    margin: 0;
    text-align: center;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  .representing {
    margin: 0.5rem 0;
    min-height: 3.5rem;
    line-height: 1.45;
    white-space: pre-wrap;
    overflow-wrap: break-word;
    word-break: break-word;
  }
  footer {
    border-top: 1px solid var(--vpro-border);
    display: flex;
    flex-wrap: wrap;
    justify-content: space-between;
    gap: 1rem;
    font-size: 0.85rem;
    padding-top: 0.5rem;
  }
  .pdf-meta {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 10rem), 1fr));
    gap: 0.75rem;
    min-width: 0;
  }
  dt {
    font-weight: 600;
  }
  dd {
    margin: 0.15rem 0 0;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  .pdf {
    margin-top: 1.25rem;
    border-top: 1px solid var(--vpro-border);
    padding-top: 1rem;
    display: grid;
    gap: 0.65rem;
    max-width: 44rem;
    min-width: 0;
  }
  .pdf h2 {
    font-size: 1.15rem;
    margin: 0;
    color: var(--vpro-navy);
  }
  .guidance {
    color: var(--vpro-ink-secondary);
    font-size: 0.9rem;
    margin-top: 1rem;
  }
</style>
