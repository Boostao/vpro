<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { ContextService, ImportExportService } from '../../bindings/github.com/boostao/vpro/app';
  import type {
    PlotLabelPDFExportReview,
    PlotLabelPDFExportOutcome,
  } from '../../bindings/github.com/boostao/vpro/app';
  import { ReadRequests } from '../shared/readRequests';
  import { plotLookupInputError } from '../shared/scopedPlotLookup';
  import { plotLabelFromHeader, type PlotLabelPreview } from './plotLabelPreview';
  import {
    validatePlotLabelRegionalPreview,
    type PlotLabelRegionalEvidence,
  } from './plotLabelRegional';
  import {
    validatePlotLabelPDFReview,
    plotLabelPDFPublicationSession,
  } from './plotLabelPDFExport';
  import type { PublicationView } from '../shared/publicationSession';
  import { notifications } from '../shell/notificationService.svelte';

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
      : null,
  );
  let publication = $state.raw<PublicationView<PlotLabelPDFExportOutcome>>(
    pdfSession?.view() ?? {
      busy: false,
      blocked: false,
      outcome: null,
      error: '',
      requestedDestination: '',
    },
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
      const key = publication.outcome
        ? `outcome:${publication.requestedDestination}:${publication.outcome.status}:${publication.outcome.path}:${publication.outcome.errorMessage}`
        : publication.error
          ? `error:${publication.requestedDestination}:${publication.error}`
          : '';
      if (key && key !== lastNotifiedPdfKey) {
        lastNotifiedPdfKey = key;
        if (publication.outcome?.status === 'published') {
          const plotLabel = pdfReview?.preview.plotNumber
            ? `plot ${pdfReview.preview.plotNumber} `
            : '';
          notifications.success(
            'Label PDF exported',
            `Exported ${plotLabel}label PDF to ${publication.outcome.path || publication.requestedDestination}.`,
            { category: 'reports', source: 'Plot Labels', contextTag: project || undefined },
          );
        } else {
          notifications.error(
            'Label PDF export failed',
            publication.error ||
              publication.outcome?.errorMessage ||
              'Label PDF export did not complete.',
            { category: 'reports', source: 'Plot Labels', contextTag: project || undefined },
          );
        }
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
    if (busy || publication.busy || publication.blocked) {
      error = 'Finish or acknowledge the current plot label operation before loading another plot.';
      notifications.error('Plot label preview blocked', error, {
        category: 'reports',
        source: 'Plot Labels',
        contextTag: project || undefined,
      });
      return;
    }
    const invalid = plotLookupInputError(plot);
    if (invalid) {
      error = invalid;
      notifications.error('Invalid plot number', error, {
        category: 'reports',
        source: 'Plot Labels',
        contextTag: project || undefined,
      });
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
      const hasPdfReview =
        typeof ImportExportService !== 'undefined' &&
        typeof ImportExportService?.GetPlotLabelPDFReview === 'function';
      const hasRegionalPreview =
        typeof ImportExportService !== 'undefined' &&
        typeof ImportExportService?.GetPlotLabelRegionalPreview === 'function';
      if (hasPdfReview) {
        let value: PlotLabelPDFExportReview | null = null;
        let pdfPrepCause: unknown = null;
        try {
          value = await reads.track(
            ImportExportService.GetPlotLabelPDFReview(
              contextId,
              JSON.stringify({ plotNumber: requestedPlot }),
            ),
          );
        } catch (pdfCause) {
          const canFallbackRegional =
            hasRegionalPreview &&
            /label PDF font|runtime label font|label PDF encoding|clipping\/wrapping/i.test(
              String(pdfCause),
            );
          if (!canFallbackRegional) throw pdfCause;
          pdfPrepCause = pdfCause;
        }
        if (request !== generation || key !== ownerKey) return;
        if (pdfPrepCause !== null) {
          let fallbackValue: unknown;
          try {
            fallbackValue = await reads.track(
              ImportExportService.GetPlotLabelRegionalPreview(contextId, requestedPlot),
            );
          } catch {
            throw pdfPrepCause;
          }
          if (request !== generation || key !== ownerKey) return;
          const native = validatePlotLabelRegionalPreview(fallbackValue, contextId, requestedPlot);
          if (request !== generation || key !== ownerKey) return;
          pdfReview = null;
          preview = native.label;
          labelDate = native.labelDate;
          regionalEvidence = native.evidence;
          const warnMsg = `On-screen plot label preview is ready, but portable PDF export is unavailable: ${String(pdfPrepCause)}`;
          error = warnMsg;
          notifications.warning('Label PDF unavailable; preview shown', warnMsg, {
            category: 'reports',
            source: 'Plot Labels',
            contextTag: project || undefined,
          });
        } else {
          const candidate = validatePlotLabelPDFReview(
            value,
            { contextId, project, projectPath, su, suPath },
            requestedPlot,
          );
          const native = validatePlotLabelRegionalPreview(
            candidate.preview,
            contextId,
            requestedPlot,
          );
          if (request !== generation || key !== ownerKey) return;
          pdfReview = candidate;
          preview = native.label;
          labelDate = native.labelDate;
          regionalEvidence = native.evidence;
        }
      } else if (hasRegionalPreview) {
        const value = await reads.track(
          ImportExportService.GetPlotLabelRegionalPreview(contextId, requestedPlot),
        );
        if (request !== generation || key !== ownerKey) return;
        const candidate = validatePlotLabelRegionalPreview(value, contextId, requestedPlot);
        if (request !== generation || key !== ownerKey) return;
        preview = candidate.label;
        labelDate = candidate.labelDate;
        regionalEvidence = candidate.evidence;
      } else {
        const value = await reads.track(ContextService.GetPlot(contextId, requestedPlot));
        if (request !== generation || key !== ownerKey) return;
        const candidate = plotLabelFromHeader(value, requestedPlot);
        const date = new Date().toLocaleDateString(undefined, {
          weekday: 'long',
          year: 'numeric',
          month: 'long',
          day: 'numeric',
        });
        preview = candidate;
        labelDate = date;
      }
    } catch (cause) {
      if (request === generation && key === ownerKey) {
        error = `Plot label preview unavailable: ${String(cause)}`;
        notifications.error('Plot label preview unavailable', error, {
          category: 'reports',
          source: 'Plot Labels',
          contextTag: project || undefined,
        });
      }
    } finally {
      if (request === generation) {
        busy = false;
        updateBusy();
      }
    }
  }

  async function publishPDF() {
    if (!pdfSession || !pdfReview || busy || publication.busy || publication.blocked) {
      error = 'Review a saved plot label and finish any active export first.';
      notifications.error('Label PDF export blocked', error, {
        category: 'reports',
        source: 'Plot Labels',
        contextTag: project || undefined,
      });
      return;
    }
    error = '';
    try {
      await pdfSession.publish(pdfReview, destination, request =>
        ImportExportService.ExportReviewedPlotLabelPDF(contextId, JSON.stringify(request)),
      );
      const latest = pdfSession.view();
      const key = latest.outcome
        ? `outcome:${latest.requestedDestination}:${latest.outcome.status}:${latest.outcome.path}:${latest.outcome.errorMessage}`
        : latest.error
          ? `error:${latest.requestedDestination}:${latest.error}`
          : '';
      if (typeof lastNotifiedPdfKey === 'undefined' || (key && lastNotifiedPdfKey !== key)) {
        if (typeof lastNotifiedPdfKey !== 'undefined' && key) lastNotifiedPdfKey = key;
        if (latest.outcome?.status === 'published') {
          notifications.success(
            'Label PDF exported',
            `Exported plot ${pdfReview.preview.plotNumber} label PDF to ${latest.outcome.path || destination}.`,
            { category: 'reports', source: 'Plot Labels', contextTag: project || undefined },
          );
        } else {
          notifications.error(
            'Label PDF export failed',
            latest.error || latest.outcome?.errorMessage || 'Label PDF export did not complete.',
            { category: 'reports', source: 'Plot Labels', contextTag: project || undefined },
          );
        }
      }
    } catch (cause) {
      error = `Label PDF export unavailable: ${String(cause)}`;
      notifications.error('Label PDF export failed', error, {
        category: 'reports',
        source: 'Plot Labels',
        contextTag: project || undefined,
      });
    }
  }

  async function recoverPDF() {
    if (!pdfSession) return;
    error = '';
    try {
      await pdfSession.recover(request =>
        ImportExportService.RecoverPlotLabelPDFOutcome(contextId, JSON.stringify(request)),
      );
      const latest = pdfSession.view();
      const key = latest.outcome
        ? `outcome:${latest.requestedDestination}:${latest.outcome.status}:${latest.outcome.path}:${latest.outcome.errorMessage}`
        : latest.error
          ? `error:${latest.requestedDestination}:${latest.error}`
          : '';
      if (typeof lastNotifiedPdfKey === 'undefined' || (key && lastNotifiedPdfKey !== key)) {
        if (typeof lastNotifiedPdfKey !== 'undefined' && key) lastNotifiedPdfKey = key;
        if (latest.outcome?.status === 'published') {
          notifications.success(
            'Label PDF receipt recovered',
            `Verified exported PDF at ${latest.outcome.path}.`,
            { category: 'reports', source: 'Plot Labels', contextTag: project || undefined },
          );
        } else if (latest.error) {
          notifications.error('Label PDF recovery notice', latest.error, {
            category: 'reports',
            source: 'Plot Labels',
            contextTag: project || undefined,
          });
        }
      }
    } catch (cause) {
      error = `PDF status check unavailable: ${String(cause)}`;
      notifications.error('Label PDF recovery failed', error, {
        category: 'reports',
        source: 'Plot Labels',
        contextTag: project || undefined,
      });
    }
  }

  function acknowledgePDF() {
    if (!pdfSession) return;
    try {
      pdfSession.acknowledge();
    } catch (cause) {
      error = String(cause);
      notifications.error('Label PDF acknowledgement failed', error, {
        category: 'reports',
        source: 'Plot Labels',
        contextTag: project || undefined,
      });
    }
  }

  onDestroy(() => { unsubscribe?.(); cancel(); });
</script>

<section class="labels" data-plot-label-preview aria-label="VPro Plot Labels">
  <header
    class="sticky top-0 z-20 bg-white/95 backdrop-blur-xs py-2 border-b border-vpro-border"
    data-workbench-sticky-bar
  >
    <h1>VPro Plot Labels</h1>
    <p>Project {project}. Preview a saved plot label and export a single-page Letter PDF.</p>
    <form
      onsubmit={event => {
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
    <details>
      <summary>Label field values</summary>
      <dl>
        <div><dt>PlotNumber1</dt><dd>{preview.plotNumber1}</dd></div>
        <div><dt>Zone1</dt><dd>{preview.zone1}</dd></div>
        <div>
          <dt>Representing1</dt>
          <dd>
            {preview.representing1 === null
              ? '(NULL)'
              : preview.representing1 === ''
                ? '(empty text)'
                : preview.representing1}
          </dd>
        </div>
        <div>
          <dt>ProjectID1</dt>
          <dd>
            {preview.projectId1 === null
              ? '(NULL)'
              : preview.projectId1 === ''
                ? '(empty text)'
                : preview.projectId1}
          </dd>
        </div>
      </dl>
      <p>
        Leading and trailing spaces are trimmed on the card for Plot Number and Representing, while
        exact stored text and blank values are listed above.
      </p>
      {#if regionalEvidence}
        <p data-plot-label-regional-date>
          Formatted date ({regionalEvidence.locale}, {regionalEvidence.pattern}): {regionalEvidence.isoDate}.
        </p>
      {/if}
    </details>
  {/if}
  <section class="pdf" data-plot-label-pdf-export aria-label="Portable saved label PDF">
    <h2>Portable saved label PDF</h2>
    {#if pdfReview}
      <dl>
        <div><dt>Review snapshot ID</dt><dd>{pdfReview.approvalHash}</dd></div>
        <div><dt>PDF checksum (SHA-256)</dt><dd>{pdfReview.pdfSHA256}</dd></div>
      </dl>
      <label for="plot-label-pdf-destination">
        New PDF destination
        <input id="plot-label-pdf-destination" bind:value={destination} disabled={locked} />
      </label>
      <button
        type="button"
        class="btn-primary"
        disabled={locked || !destination}
        onclick={() => void publishPDF()}
      >
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
      Creates a single-page Letter PDF with wrapped UTF-8 plot labels up to full 255-character descriptions
      and locale-formatted dates (including en-CA, fr-CA, and en-US). Export creates a new file without
      overwriting existing files or changing saved plot data. Print All and physical printing remain unavailable.
    </p>
  </section>
  <p class="guidance">
    Previewing a plot label leaves saved plot records and settings unchanged, and looks up the plot directly
    regardless of active Site Unit filters; six-position printing and Print All Plots remain unavailable.
  </p>
</section>

<style>
  .labels { padding: clamp(0.9rem, 2vw, 1.4rem); min-width: 0; max-width: 58rem; color: var(--vpro-ink); }
  h1 { margin: 0 0 0.5rem; font-size: 1.5rem; font-weight: 700; color: var(--vpro-navy); border-bottom: 3px solid var(--vpro-gold); display: inline-block; padding-bottom: 0.2rem; }
  h2 { margin: 0; font-size: 1.2rem; font-weight: 700; color: var(--vpro-navy); }
  form {
    display: flex; flex-wrap: wrap; align-items: end; gap: 0.75rem; margin: 1rem 0;
    padding: 0.9rem 1rem; background: var(--vpro-surface); border: 1px solid var(--vpro-border);
    border-top: 3px solid var(--vpro-navy); border-radius: var(--vpro-radius-md, 6px);
  }
  label { display: grid; gap: 0.35rem; min-width: 0; flex: 1 1 13rem; font-size: 0.875rem; font-weight: 600; color: var(--vpro-navy); }
  input, button { min-width: 0; min-height: 40px; border: 1px solid var(--vpro-border-strong); border-radius: var(--vpro-radius-sm, 4px); padding: 0.45rem 0.75rem; font: inherit; font-size: 0.9rem; }
  input { background: var(--vpro-surface); color: var(--vpro-ink); font-family: var(--vpro-font-mono, ui-monospace, monospace); font-variant-numeric: tabular-nums; }
  button { background: var(--vpro-surface); border-color: var(--vpro-navy); color: var(--vpro-navy); font-weight: 600; cursor: pointer; }
  button:hover:not(:disabled) { background: var(--vpro-navy-tint); }
  button[type="submit"], .btn-primary { background: var(--vpro-navy); border-color: var(--vpro-navy); color: var(--vpro-surface); font-weight: 700; }
  button[type="submit"]:hover:not(:disabled), .btn-primary:hover:not(:disabled) { background: var(--vpro-navy-dark); border-color: var(--vpro-navy-dark); }
  input:focus-visible, button:focus-visible, summary:focus-visible { outline: 2px solid var(--vpro-gold); outline-offset: 2px; }
  input:disabled, button:disabled { opacity: 0.55; }
  .label {
    background: var(--vpro-surface); border: 1px solid var(--vpro-border-strong);
    border-top: 4px solid var(--vpro-navy); border-radius: var(--vpro-radius-sm, 4px);
    padding: 1.05rem 1.2rem; margin: 1rem 0; max-width: 34rem; display: grid; gap: 0.45rem; min-width: 0;
  }
  .label h2 { font-family: var(--vpro-font-mono, ui-monospace, monospace); font-variant-numeric: tabular-nums; font-size: 1.35rem; letter-spacing: 0.01em; min-width: 0; overflow-wrap: break-word; }
  .label p { margin: 0; min-width: 0; max-width: 100%; overflow-wrap: break-word; word-break: break-word; }
  .representing { line-height: 1.45; }
  .zone {
    display: inline-block; justify-self: start; max-width: 100%; box-sizing: border-box;
    font-family: var(--vpro-font-mono, ui-monospace, monospace); font-variant-numeric: tabular-nums;
    font-size: 0.85rem; font-weight: 700; color: var(--vpro-forest); background: var(--vpro-forest-surface);
    border: 1px solid var(--vpro-forest-border); border-radius: var(--vpro-radius-xs, 3px); padding: 0.12rem 0.5rem;
  }
  footer {
    display: flex; justify-content: space-between; flex-wrap: wrap; gap: 0.5rem;
    margin-top: 0.3rem; padding-top: 0.55rem; border-top: 1px dashed var(--vpro-border);
    font-family: var(--vpro-font-mono, ui-monospace, monospace); font-variant-numeric: tabular-nums;
    font-size: 0.82rem; color: var(--vpro-ink-secondary);
  }
  footer span { min-width: 0; overflow-wrap: anywhere; white-space: pre-wrap; }
  details { margin: 0.85rem 0; padding: 0.75rem 1rem; background: var(--vpro-surface-subtle); border: 1px solid var(--vpro-border); border-radius: var(--vpro-radius-sm, 4px); }
  summary { cursor: pointer; font-weight: 600; color: var(--vpro-navy); }
  .pdf {
    display: grid; grid-template-columns: minmax(0, 1fr); gap: 0.65rem; min-width: 0;
    margin-top: 1rem; padding: 1rem 1.15rem; background: var(--vpro-surface);
    border: 1px solid var(--vpro-border); border-left: 4px solid var(--vpro-forest); border-radius: var(--vpro-radius-sm, 4px);
  }
  .pdf input { width: 100%; box-sizing: border-box; }
  p, dd { white-space: pre-wrap; overflow-wrap: anywhere; }
  dl { margin: 0.4rem 0; display: grid; gap: 0.35rem; }
  dl > div { margin: 0; padding: 0.3rem 0.5rem; background: var(--vpro-surface); border: 1px solid var(--vpro-border); border-radius: var(--vpro-radius-xs, 3px); }
  dt { font-size: 0.76rem; font-weight: 700; color: var(--vpro-ink-secondary); }
  dd { margin: 0.1rem 0 0; font-family: var(--vpro-font-mono, ui-monospace, monospace); font-variant-numeric: tabular-nums; font-size: 0.84rem; color: var(--vpro-ink); }
  .guidance { margin-top: 0.85rem; font-size: 0.8rem; color: var(--vpro-ink-secondary); }
</style>
