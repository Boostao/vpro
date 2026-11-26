<script lang="ts">
  import type { HTMLReportResult } from '../../bindings/github.com/boostao/vpro/app';
  import { triggerBrowserHTMLDownload } from './compactReport';

  interface Props {
    open: boolean;
    report: HTMLReportResult | null;
    onClose: () => void;
  }

  let { open, report, onClose }: Props = $props();
  let frameEl = $state<HTMLIFrameElement | null>(null);
  let saveStatus = $state('');

  function handleKeydown(event: KeyboardEvent) {
    if (open && event.key === 'Escape') {
      event.preventDefault();
      onClose();
    }
  }

  function handlePrint() {
    saveStatus = '';
    try {
      frameEl?.contentWindow?.focus();
      frameEl?.contentWindow?.print();
    } catch {
      saveStatus = 'Use Save HTML to open and print this report in your browser.';
    }
  }

  function handleSaveHtml() {
    if (!report) return;
    const saved = triggerBrowserHTMLDownload(report);
    saveStatus = saved
      ? 'Saved standalone HTML report.'
      : 'Browser download is unavailable in this environment.';
  }
</script>

<svelte:window onkeydown={handleKeydown} />

{#if open && report}
  <div class="html-modal-backdrop" data-html-report-modal>
    <div
      class="html-modal-dialog"
      role="dialog"
      aria-modal="true"
      aria-labelledby="html-report-modal-title"
      tabindex="-1"
    >
      <header class="html-modal-header">
        <div class="html-modal-heading">
          <p class="html-modal-eyebrow">DISPLAY REPORT (QUARTO STYLE)</p>
          <h2 id="html-report-modal-title">{report.title || 'VPro Report'}</h2>
          <div class="html-modal-meta">
            {#if report.project}<span>Project: <strong>{report.project}</strong></span>{/if}
            {#if report.scopeLabel}<span>Scope: <strong>{report.scopeLabel}</strong></span>{/if}
            <span>Units: <strong>{report.unitCount}</strong></span>
            <span>Plots: <strong>{report.plotCount}</strong></span>
            {#if report.tableCount > 0}<span>Tables: <strong>{report.tableCount}</strong></span>{/if}
          </div>
        </div>
        <div class="html-modal-actions">
          <button type="button" class="btn-gold" data-html-report-print onclick={handlePrint}>
            Print
          </button>
          <button type="button" class="btn-outline" data-html-report-save onclick={handleSaveHtml}>
            Save HTML
          </button>
          <button type="button" class="btn-outline" data-html-report-close onclick={onClose}>
            Close
          </button>
        </div>
      </header>

      {#if report.notice}
        <div class="html-modal-notice" role="status">{report.notice}</div>
      {/if}
      {#if saveStatus}
        <div class="html-modal-notice" role="status">{saveStatus}</div>
      {/if}

      <div class="html-modal-body">
        <iframe
          bind:this={frameEl}
          class="html-report-iframe"
          data-html-report-iframe
          title={report.title || 'Displayed VPro Report'}
          sandbox="allow-same-origin allow-modals"
          srcdoc={report.html}
        ></iframe>
      </div>
    </div>
  </div>
{/if}

<style>
  .html-modal-backdrop {
    position: fixed;
    inset: 0;
    z-index: 60;
    background: rgba(15, 23, 42, 0.58);
    display: grid;
    place-items: center;
    padding: 1rem;
  }
  .html-modal-dialog {
    width: min(1240px, 96vw);
    height: min(90vh, 920px);
    background: var(--vpro-surface);
    border: 1px solid var(--vpro-border);
    border-radius: 6px;
    display: flex;
    flex-direction: column;
    overflow: hidden;
    box-shadow: 0 20px 50px rgba(0, 0, 0, 0.28);
  }
  .html-modal-header {
    flex: 0 0 auto;
    background: var(--vpro-navy);
    color: var(--vpro-surface);
    border-bottom: 4px solid var(--vpro-gold);
    padding: 0.85rem 1.15rem;
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 0.75rem;
  }
  .html-modal-heading {
    min-width: 0;
    display: grid;
    gap: 0.2rem;
  }
  .html-modal-eyebrow {
    margin: 0;
    font-size: 0.7rem;
    letter-spacing: 0.08em;
    font-weight: 700;
    color: var(--vpro-gold);
  }
  .html-modal-header h2 {
    margin: 0;
    font-size: 1.15rem;
    color: var(--vpro-surface);
  }
  .html-modal-meta {
    display: flex;
    flex-wrap: wrap;
    gap: 0.75rem;
    font-size: 0.78rem;
    opacity: 0.92;
  }
  .html-modal-actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    align-items: center;
  }
  .btn-gold {
    background: var(--vpro-gold);
    color: var(--vpro-navy);
    border: 1px solid var(--vpro-gold);
    border-radius: 4px;
    padding: 0.45rem 0.85rem;
    font-weight: 700;
    font-size: 0.84rem;
    cursor: pointer;
  }
  .btn-outline {
    background: rgba(255, 255, 255, 0.14);
    color: var(--vpro-surface);
    border: 1px solid rgba(255, 255, 255, 0.35);
    border-radius: 4px;
    padding: 0.45rem 0.85rem;
    font-weight: 600;
    font-size: 0.84rem;
    cursor: pointer;
  }
  .btn-outline:hover {
    background: rgba(255, 255, 255, 0.24);
  }
  .html-modal-notice {
    flex: 0 0 auto;
    padding: 0.5rem 1.15rem;
    background: var(--vpro-canvas);
    border-bottom: 1px solid var(--vpro-border);
    color: var(--vpro-ink);
    font-size: 0.82rem;
  }
  .html-modal-body {
    flex: 1 1 auto;
    min-height: 0;
    display: flex;
    background: var(--vpro-surface);
  }
  .html-report-iframe {
    width: 100%;
    height: 100%;
    flex: 1 1 auto;
    border: 0;
    display: block;
    background: var(--vpro-surface);
  }
</style>
