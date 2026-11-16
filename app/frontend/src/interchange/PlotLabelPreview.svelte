<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { ContextService, ImportExportService } from '../../bindings/github.com/boostao/vpro/app';
  import type { PlotLabelPDFExportReview, PlotLabelPDFExportOutcome } from '../../bindings/github.com/boostao/vpro/app';
  import { ReadRequests } from '../shared/readRequests';
  import { plotLookupInputError } from '../shared/scopedPlotLookup';
  import { plotLabelFromHeader, type PlotLabelPreview } from './plotLabelPreview';
  import { validatePlotLabelRegionalPreview, type PlotLabelRegionalEvidence } from './plotLabelRegional';
  import { validatePlotLabelPDFReview, plotLabelPDFPublicationSession } from './plotLabelPDFExport';
  import type { PublicationView } from '../shared/publicationSession';
  import { notifications } from '../shell/notificationService.svelte';

  let { contextId, project, projectPath = '', su = '', suPath = '', initialPlot = '', onBusyChange }: {
    contextId: string; project: string; projectPath?: string; su?: string; suPath?: string; initialPlot?: string; onBusyChange: (busy: boolean) => void;
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
  const regionalDateEnabled = true;
  const pdfEnabled = true;
  const pdfSession = untrack(() => pdfEnabled ? plotLabelPDFPublicationSession({ contextId, project, projectPath, su, suPath }) : null);
  let publication = $state.raw<PublicationView<PlotLabelPDFExportOutcome>>(pdfSession?.view() ??
    { busy: false, blocked: false, outcome: null, error: '', requestedDestination: '' });
  const locked = $derived(busy || publication.busy || publication.blocked);
  const ownerKey = $derived(JSON.stringify([contextId, project, projectPath, su, suPath]));
  let generation = 0;
  function updateBusy() { onBusyChange(busy || publication.busy || publication.blocked); }
  const unsubscribe = pdfSession?.subscribe(() => { publication = pdfSession.view(); updateBusy(); });

  function cancel() {
    generation++;
    reads.cancelAll();
    busy = false;
    updateBusy();
  }
  async function load() {
    if (busy || publication.busy || publication.blocked) {
      error = 'Resolve the current saved-label read or retained PDF outcome before another preview.';
      notifications.error('Plot label preview blocked', error, { category: 'reports', source: 'Plot Labels', contextTag: project || undefined });
      return;
    }
    const invalid = plotLookupInputError(plot);
    if (invalid) {
      error = invalid;
      notifications.error('Invalid plot number', error, { category: 'reports', source: 'Plot Labels', contextTag: project || undefined });
      return;
    }
    cancel();
    const request = generation, key = ownerKey, requestedPlot = plot;
    preview = null; error = ''; labelDate = ''; regionalEvidence = null; pdfReview = null; busy = true; updateBusy();
    try {
      if (pdfEnabled) {
        const value = await reads.track(ImportExportService.GetPlotLabelPDFReview(contextId, JSON.stringify({ plotNumber: requestedPlot })));
        if (request !== generation || key !== ownerKey) return;
        const candidate = validatePlotLabelPDFReview(value, { contextId, project, projectPath, su, suPath }, requestedPlot);
        const native = validatePlotLabelRegionalPreview(candidate.preview, contextId, requestedPlot);
        if (request !== generation || key !== ownerKey) return;
        pdfReview = candidate; preview = native.label; labelDate = native.labelDate; regionalEvidence = native.evidence;
      } else if (regionalDateEnabled) {
        const value = await reads.track(ImportExportService.GetPlotLabelRegionalPreview(contextId, requestedPlot));
        if (request !== generation || key !== ownerKey) return;
        const candidate = validatePlotLabelRegionalPreview(value, contextId, requestedPlot);
        if (request !== generation || key !== ownerKey) return;
        preview = candidate.label; labelDate = candidate.labelDate; regionalEvidence = candidate.evidence;
      } else {
        const value = await reads.track(ContextService.GetPlot(contextId, requestedPlot));
        if (request !== generation || key !== ownerKey) return;
        const candidate = plotLabelFromHeader(value, requestedPlot);
        const date = new Date().toLocaleDateString(undefined, { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' });
        preview = candidate; labelDate = date;
      }
    } catch (cause) {
      if (request === generation && key === ownerKey) {
        error = `Plot label preview unavailable; saved data and printing are unchanged: ${String(cause)}`;
        notifications.error('Plot label preview unavailable', error, { category: 'reports', source: 'Plot Labels', contextTag: project || undefined });
      }
    } finally {
      if (request === generation) { busy = false; updateBusy(); }
    }
  }
  async function publishPDF() {
    if (!pdfSession || !pdfReview || busy || publication.busy || publication.blocked) {
      error = 'Prepare an owned PDF review and resolve the prior operation first.';
      notifications.error('Label PDF export blocked', error, { category: 'reports', source: 'Plot Labels', contextTag: project || undefined });
      return;
    }
    error = '';
    try {
      await pdfSession.publish(pdfReview, destination, request => ImportExportService.ExportReviewedPlotLabelPDF(contextId, JSON.stringify(request)));
      const latest = pdfSession.view();
      if (latest.outcome?.status === 'published') {
        notifications.success(
          'Label PDF exported',
          `Exported plot ${pdfReview.preview.plotNumber} label PDF to ${latest.outcome.path || destination}.`,
          { category: 'reports', source: 'Plot Labels', contextTag: project || undefined },
        );
      } else {
        notifications.error(
          'Label PDF export failed',
          latest.error || latest.outcome?.errorMessage || 'Label PDF publication did not complete.',
          { category: 'reports', source: 'Plot Labels', contextTag: project || undefined },
        );
      }
    } catch (cause) {
      error = `Label PDF publication unavailable: ${String(cause)}`;
      notifications.error('Label PDF export failed', error, { category: 'reports', source: 'Plot Labels', contextTag: project || undefined });
    }
  }
  async function recoverPDF() {
    if (!pdfSession) return;
    error = '';
    try {
      await pdfSession.recover(request => ImportExportService.RecoverPlotLabelPDFOutcome(contextId, JSON.stringify(request)));
      const latest = pdfSession.view();
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
    } catch (cause) {
      error = `Readonly PDF recovery unavailable: ${String(cause)}`;
      notifications.error('Label PDF recovery failed', error, { category: 'reports', source: 'Plot Labels', contextTag: project || undefined });
    }
  }
  function acknowledgePDF() {
    if (!pdfSession) return;
    try { pdfSession.acknowledge(); } catch (cause) { error = String(cause); }
  }
  onDestroy(() => { unsubscribe?.(); cancel(); });
</script>

<section class="labels" data-plot-label-preview aria-label="VPro Plot Labels">
  <header class="sticky top-0 z-20 bg-white/95 backdrop-blur-xs py-2 border-b border-stone-200" data-workbench-sticky-bar>
    <h1>VPro Plot Labels</h1>
    <p>Owned project {project}. Preview an exact saved plot, not unsaved form controls.</p>
    <form onsubmit={event => { event.preventDefault(); void load(); }}>
      <label for="plot-label-number">Plot number
        <input id="plot-label-number" bind:value={plot} disabled={locked} />
      </label>
      <button type="submit" disabled={locked}>{pdfEnabled ? 'Review saved plot label PDF' : 'Preview saved plot label'}</button>
      {#if busy}<button type="button" onclick={cancel}>Cancel label read</button><span role="status">Reading saved label fields...</span>{/if}
    </form>
  </header>
  {#if error}<p role="alert" class="error">{error}</p>{/if}
  {#if preview}
    <section class="label" data-plot-label-card aria-label={`Label for saved plot ${preview.plotNumber1}`}>
      <h2>{preview.displayPlotNumber}</h2>
      <p class="zone">{preview.zone1}</p>
      <p>{preview.projectId1 ?? ''}</p>
      <p>{preview.displayRepresenting ?? ''}</p>
      <footer><span>Label Date: {labelDate}</span><span>(VPro)</span></footer>
    </section>
    <details>
      <summary>Original label assignments and display rules</summary>
      <dl>
        <div><dt>PlotNumber1</dt><dd>{preview.plotNumber1}</dd></div>
        <div><dt>Zone1</dt><dd>{preview.zone1}</dd></div>
        <div><dt>Representing1</dt><dd>{preview.representing1 === null ? '(NULL)' : preview.representing1 === '' ? '(empty text)' : preview.representing1}</dd></div>
        <div><dt>ProjectID1</dt><dd>{preview.projectId1 === null ? '(NULL)' : preview.projectId1 === '' ? '(empty text)' : preview.projectId1}</dd></div>
      </dl>
      <p>Only the source display expressions remove leading/trailing ASCII spaces from PlotNumber and Representing.
        Assignments retain exact text/NULL. Label date uses the desktop locale and current clock.</p>
      {#if regionalEvidence}
        <p data-plot-label-regional-date>Native Windows Long Date: {regionalEvidence.isoDate}, locale {regionalEvidence.locale},
          pattern {regionalEvidence.pattern}. No browser-locale fallback.</p>
      {/if}
    </details>
  {/if}
      {#if pdfEnabled}
        <section class="pdf" data-plot-label-pdf-export aria-label="Portable saved label PDF">
          <h2>Portable saved label PDF</h2>
          {#if publication.error}<p role="alert" class="error">{publication.error}</p>{/if}
          {#if pdfReview}
            <dl>
              <div><dt>Source approval</dt><dd>{pdfReview.approvalHash}</dd></div>
              <div><dt>PDF SHA256</dt><dd>{pdfReview.pdfSHA256}</dd></div>
            </dl>
            <label for="plot-label-pdf-destination">New PDF destination
              <input id="plot-label-pdf-destination" bind:value={destination} disabled={locked} />
            </label>
            <button type="button" class="btn-primary" disabled={locked || !destination} onclick={() => void publishPDF()}>Export reviewed label PDF</button>
          {/if}
          {#if publication.busy}<p role="status">Retaining the exact PDF attempt; publication is not replayed or cancelled.</p>{/if}
          {#if publication.requestedDestination}
            <p data-plot-label-pdf-destination>Requested destination: {publication.requestedDestination}</p>
          {/if}
          {#if publication.outcome}
            <dl data-plot-label-pdf-receipt>
              <div><dt>Publication outcome</dt><dd>{publication.outcome.status}</dd></div>
              <div><dt>Published path</dt><dd>{publication.outcome.path || '(no published path)'}</dd></div>
              <div><dt>Artifact SHA256</dt><dd>{publication.outcome.sha256 || '(no artifact hash)'}</dd></div>
            </dl>
          {/if}
          {#if publication.blocked && !publication.outcome}
            <button type="button" disabled={publication.busy} onclick={() => void recoverPDF()}>Recover PDF outcome readonly</button>
          {/if}
          {#if publication.blocked && publication.outcome}
            <button type="button" disabled={publication.busy} onclick={acknowledgePDF}>Acknowledge retained PDF outcome</button>
          {/if}
          <p class="guidance">One portable Letter page, real runtime Arial and fixed source-relative fields, not Access printer/stock alignment.
            Supports calibrated Windows Long Date locales (including en-US, en-CA, fr-CA) and printable UTF-8 single-line labels. Export never overwrites a file or changes saved data.
            Retained receipts survive remount; unknown attempts are recovered readonly, never replayed. Print All and physical printing remain unavailable.</p>
        </section>
      {/if}
  <p class="guidance">Read-only adaptation of the single-plot label preview. No BecLabels rows, database, audits,
    configuration or printer jobs are changed by preview. {pdfEnabled ? 'The separate reviewed PDF action creates one new file only.' : 'No files are created.'} Source report designs are mapped; physical printer output is not verified;
    six-position printing and Print All Plots remain unavailable. SU/profile filters are not applied to this exact lookup.</p>
</section>

<style>
  .labels {
    padding: clamp(0.9rem, 2vw, 1.4rem);
    min-width: 0;
    max-width: 58rem;
    font-family: var(--vpro-font-sans, "BC Sans", "IBM Plex Sans", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif);
    color: var(--vpro-ink, #313132);
  }

  h1 {
    margin: 0 0 0.5rem;
    font-size: 1.5rem;
    font-weight: 700;
    color: var(--vpro-navy, #003366);
    border-bottom: 3px solid var(--vpro-gold, #FCBA19);
    display: inline-block;
    padding-bottom: 0.2rem;
  }

  h2 {
    margin: 0;
    font-size: 1.2rem;
    font-weight: 700;
    color: var(--vpro-navy, #003366);
  }

  form {
    display: flex;
    flex-wrap: wrap;
    align-items: end;
    gap: 0.75rem;
    margin: 1rem 0;
    padding: 0.9rem 1rem;
    background: var(--vpro-surface, #FFFFFF);
    border: 1px solid var(--vpro-border, #D1D5DB);
    border-top: 3px solid var(--vpro-navy, #003366);
    border-radius: var(--vpro-radius-md, 6px);
    box-shadow: var(--vpro-shadow-sm, 0 1px 2px rgba(0, 34, 68, 0.06));
  }

  label {
    display: grid;
    gap: 0.35rem;
    min-width: 0;
    flex: 1 1 13rem;
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--vpro-navy, #003366);
  }

  input,
  button {
    min-width: 0;
    min-height: 40px;
    border: 1px solid var(--vpro-border-strong, #9CA3AF);
    border-radius: var(--vpro-radius-sm, 4px);
    padding: 0.45rem 0.75rem;
    font: inherit;
    font-size: 0.9rem;
  }

  input {
    background: var(--vpro-surface, #FFFFFF);
    color: var(--vpro-ink, #313132);
    font-family: var(--vpro-font-mono, "IBM Plex Mono", ui-monospace, monospace);
    font-variant-numeric: tabular-nums;
  }

  button {
    background: var(--vpro-surface, #FFFFFF);
    border-color: var(--vpro-navy, #003366);
    color: var(--vpro-navy, #003366);
    font-weight: 600;
  }

  button:hover:not(:disabled) {
    background: var(--vpro-navy-tint, #EBF1F8);
  }

  button[type="submit"],
  .btn-primary {
    background: var(--vpro-navy, #003366);
    border-color: var(--vpro-navy, #003366);
    color: var(--vpro-surface, #FFFFFF);
    font-weight: 700;
  }

  button[type="submit"]:hover:not(:disabled),
  .btn-primary:hover:not(:disabled) {
    background: var(--vpro-navy-dark, #002244);
    border-color: var(--vpro-navy-dark, #002244);
  }

  input:focus-visible,
  button:focus-visible,
  summary:focus-visible {
    outline: 2px solid var(--vpro-gold, #FCBA19);
    outline-offset: 2px;
  }

  input:disabled,
  button:disabled {
    opacity: 0.55;
  }

  .label {
    background: var(--vpro-surface, #FFFFFF);
    border: 1px solid var(--vpro-border-strong, #9CA3AF);
    border-top: 4px solid var(--vpro-navy, #003366);
    border-radius: var(--vpro-radius-sm, 4px);
    padding: 1.05rem 1.2rem;
    margin: 1rem 0;
    max-width: 34rem;
    display: grid;
    gap: 0.45rem;
    min-width: 0;
    box-shadow: var(--vpro-shadow-sm, 0 1px 3px rgba(0, 34, 68, 0.08));
  }

  .label h2 {
    font-family: var(--vpro-font-mono, "IBM Plex Mono", ui-monospace, monospace);
    font-variant-numeric: tabular-nums;
    font-size: 1.35rem;
    letter-spacing: 0.01em;
  }

  .label p {
    margin: 0;
  }

  .zone {
    display: inline-block;
    justify-self: start;
    font-family: var(--vpro-font-mono, "IBM Plex Mono", ui-monospace, monospace);
    font-variant-numeric: tabular-nums;
    font-size: 0.85rem;
    font-weight: 700;
    color: var(--vpro-forest, #1E5128);
    background: var(--vpro-forest-surface, #E9F1EB);
    border: 1px solid var(--vpro-forest-border, #D8D8D8);
    border-radius: var(--vpro-radius-xs, 3px);
    padding: 0.12rem 0.5rem;
  }

  footer {
    display: flex;
    justify-content: space-between;
    flex-wrap: wrap;
    gap: 0.5rem;
    margin-top: 0.3rem;
    padding-top: 0.55rem;
    border-top: 1px dashed var(--vpro-border, #D1D5DB);
    font-family: var(--vpro-font-mono, "IBM Plex Mono", ui-monospace, monospace);
    font-variant-numeric: tabular-nums;
    font-size: 0.82rem;
    color: var(--vpro-ink-secondary, #4B5563);
  }

  footer span {
    min-width: 0;
    overflow-wrap: anywhere;
    white-space: pre-wrap;
  }

  details {
    margin: 0.85rem 0;
    padding: 0.75rem 1rem;
    background: var(--vpro-surface-subtle, #F8FAFB);
    border: 1px solid var(--vpro-border, #D1D5DB);
    border-radius: var(--vpro-radius-sm, 4px);
  }

  summary {
    cursor: pointer;
    font-weight: 600;
    color: var(--vpro-navy, #003366);
  }

  .pdf {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 0.65rem;
    min-width: 0;
    margin-top: 1rem;
    padding: 1rem 1.15rem;
    background: var(--vpro-surface, #FFFFFF);
    border: 1px solid var(--vpro-border, #D1D5DB);
    border-left: 4px solid var(--vpro-forest, #1E5128);
    border-radius: var(--vpro-radius-sm, 4px);
  }

  .pdf input {
    width: 100%;
    box-sizing: border-box;
  }

  p,
  dd {
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }

  dl {
    margin: 0.4rem 0;
    display: grid;
    gap: 0.35rem;
  }

  dl > div {
    margin: 0;
    padding: 0.3rem 0.5rem;
    background: var(--vpro-surface, #FFFFFF);
    border: 1px solid var(--vpro-border, #D1D5DB);
    border-radius: var(--vpro-radius-xs, 3px);
  }

  dt {
    font-size: 0.76rem;
    font-weight: 700;
    color: var(--vpro-ink-secondary, #4B5563);
  }

  dd {
    margin: 0.1rem 0 0;
    font-family: var(--vpro-font-mono, "IBM Plex Mono", ui-monospace, monospace);
    font-variant-numeric: tabular-nums;
    font-size: 0.84rem;
    color: var(--vpro-ink, #313132);
  }

  .error {
    color: var(--vpro-error-ink, #A61B20);
    background: var(--vpro-error-bg, #FBEAEA);
    border-left: 4px solid var(--vpro-error, #D8292F);
    border-radius: var(--vpro-radius-xs, 3px);
    padding: 0.6rem 0.8rem;
    font-weight: 600;
  }

  .guidance {
    margin-top: 0.85rem;
    font-size: 0.8rem;
    color: var(--vpro-ink-secondary, #4B5563);
  }
</style>
