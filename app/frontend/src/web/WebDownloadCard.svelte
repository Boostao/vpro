<script lang="ts">
  import { Check, Download, ExternalLink } from '@lucide/svelte';
  import {
    BECMASTER_DOWNLOAD_FORMATS,
    BECMasterHttpError,
    downloadBECMasterSubset,
    formatByteSize,
    type BECMasterDownloadFormat,
    type BECMasterDownloadResponse,
  } from './webBECMasterFilter';
  import {
    DEFAULT_BECMASTER_CITATION,
    DEFAULT_LICENCE_NAME,
    DEFAULT_LICENCE_URL,
    formatWebDownloadFeedback,
    type WebMetaResponse,
  } from './webMeta';

  let {
    contextId,
    matchedCount,
    totalPlots,
    plotNumbers,
    meta,
  }: {
    contextId: string;
    matchedCount: number;
    totalPlots: number;
    plotNumbers: readonly string[];
    meta: WebMetaResponse | null;
  } = $props();

  let selectedFormat = $state<BECMasterDownloadFormat>('vpro64');
  let downloading = $state(false);
  let errorMsg = $state('');
  let busyNotice = $state('');
  let lastDownload = $state<BECMasterDownloadResponse | null>(null);
  let citationCopied = $state(false);

  const selectedFormatInfo = $derived(
    BECMASTER_DOWNLOAD_FORMATS.find((f) => f.id === selectedFormat) ?? BECMASTER_DOWNLOAD_FORMATS[0]
  );

  const licenceName = $derived(meta?.licenceName || DEFAULT_LICENCE_NAME);
  const licenceUrl = $derived(meta?.licenceUrl || DEFAULT_LICENCE_URL);
  const citation = $derived(meta?.citation || DEFAULT_BECMASTER_CITATION);

  async function handleDownload() {
    if (downloading || matchedCount <= 0 || plotNumbers.length === 0) return;
    downloading = true;
    errorMsg = '';
    busyNotice = '';
    lastDownload = null;
    try {
      const resp = await downloadBECMasterSubset({
        contextId,
        format: selectedFormat,
        plotNumbers: [...plotNumbers],
      });
      lastDownload = resp;
    } catch (cause) {
      const fallback =
        cause instanceof Error && cause.message
          ? `Could not prepare download: ${cause.message}`
          : 'Could not prepare download. Please try again.';
      const msg = formatWebDownloadFeedback(cause, fallback);
      if (cause instanceof BECMasterHttpError && cause.isBusy) {
        busyNotice = msg;
      } else {
        errorMsg = msg;
      }
    } finally {
      downloading = false;
    }
  }

  async function copyCitation() {
    if (typeof navigator === 'undefined' || !navigator.clipboard?.writeText) return;
    try {
      await navigator.clipboard.writeText(citation);
      citationCopied = true;
      setTimeout(() => {
        citationCopied = false;
      }, 2000);
    } catch {
      // Clipboard API unavailable in restricted context
    }
  }
</script>

<section class="web-download-card" aria-label="Download Selected Data" data-web-download-card>
  <div class="web-dl-top">
    <div class="web-dl-summary">
      <div class="web-dl-count tabular-nums" data-web-selected-count>
        Number of plots selected: <strong>{matchedCount.toLocaleString()}</strong> of {totalPlots.toLocaleString()}
      </div>
      <div class="web-dl-desc">{selectedFormatInfo.description}</div>
    </div>

    <div class="web-dl-controls">
      <label class="web-dl-format-field">
        <span class="web-dl-format-label">Format</span>
        <select
          class="web-dl-select"
          bind:value={selectedFormat}
          disabled={downloading}
          data-web-download-format
        >
          {#each BECMASTER_DOWNLOAD_FORMATS as fmt (fmt.id)}
            <option value={fmt.id}>{fmt.label}</option>
          {/each}
        </select>
      </label>

      <button
        type="button"
        class="web-dl-btn"
        disabled={downloading || matchedCount === 0 || plotNumbers.length === 0}
        onclick={handleDownload}
        data-web-download-btn
      >
        <Download size={15} aria-hidden="true" />
        <span>{downloading ? 'Preparing Download...' : 'Download'}</span>
      </button>
    </div>
  </div>

  {#if busyNotice}
    <div class="web-dl-banner web-dl-busy" role="status" data-web-download-busy>
      {busyNotice}
    </div>
  {:else if errorMsg}
    <div class="web-dl-banner web-dl-error" role="alert" data-web-download-error>
      {errorMsg}
    </div>
  {:else if lastDownload}
    <div class="web-dl-banner web-dl-success" role="status" data-web-download-success>
      Ready: <strong class="font-mono">{lastDownload.filename}</strong> ({lastDownload.plotCount.toLocaleString()} plots,
      {formatByteSize(lastDownload.bytes)}).
    </div>
  {/if}

  <div class="web-dl-licence" data-web-licence-block>
    <div class="web-dl-licence-row">
      <div class="web-dl-licence-title">
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <path d="M12 3v18" />
          <path d="M5 7h14" />
          <path d="M3 14h4l-2-7-2 7z" />
          <path d="M17 14h4l-2-7-2 7z" />
          <path d="M8 21h8" />
        </svg>
        <span>Data Licence:</span>
        <a
          href={licenceUrl}
          target="_blank"
          rel="noopener noreferrer"
          class="web-dl-licence-link"
          data-web-licence-link
        >
          <span>{licenceName}</span>
          <ExternalLink size={11} aria-hidden="true" />
        </a>
      </div>

      <button
        type="button"
        class="web-dl-copy-btn"
        onclick={copyCitation}
        title="Copy formal BECMaster citation"
        data-copy-citation-btn
      >
        {#if citationCopied}
          <Check size={12} aria-hidden="true" />
          <span>Copied</span>
        {:else}
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <rect x="9" y="9" width="13" height="13" rx="2" ry="2" />
            <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
          </svg>
          <span>Copy Citation</span>
        {/if}
      </button>
    </div>

    <p class="web-dl-citation" data-web-citation-text>
      <strong>Suggested Citation:</strong>
      {citation}
    </p>
  </div>
</section>

<style>
  .web-download-card {
    background: var(--vpro-surface, #ffffff);
    border: 1px solid var(--vpro-border, #d1d5db);
    border-left: 4px solid var(--vpro-gold, #fcba19);
    border-radius: 6px;
    padding: 12px 14px;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .web-dl-top {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
  }

  .web-dl-summary {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 220px;
  }

  .web-dl-count {
    font-size: 14px;
    color: var(--vpro-navy, #003366);
  }

  .web-dl-desc {
    font-size: 12px;
    color: var(--vpro-ink-secondary, #4b5563);
  }

  .web-dl-controls {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 8px;
  }

  .web-dl-format-field {
    display: inline-flex;
    align-items: center;
    gap: 6px;
  }

  .web-dl-format-label {
    font-size: 12px;
    font-weight: 700;
    color: var(--vpro-ink, #313132);
  }

  .web-dl-select {
    padding: 6px 10px;
    border-radius: 4px;
    border: 1px solid var(--vpro-border-strong, #9ca3af);
    background: #ffffff;
    font-size: 12.5px;
    font-weight: 600;
    color: var(--vpro-ink, #313132);
  }

  .web-dl-btn {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 7px 14px;
    border-radius: 4px;
    border: 1px solid var(--vpro-navy, #003366);
    background: var(--vpro-navy, #003366);
    color: #ffffff;
    font-size: 13px;
    font-weight: 700;
    cursor: pointer;
  }

  .web-dl-btn:hover:not(:disabled) {
    background: var(--vpro-navy-hover, #0a4480);
  }

  .web-dl-btn:disabled {
    opacity: 0.55;
    cursor: not-allowed;
  }

  .web-dl-banner {
    padding: 7px 10px;
    border-radius: 4px;
    font-size: 12px;
  }

  .web-dl-busy {
    background: var(--vpro-warning-bg, #fef6e0);
    border: 1px solid var(--vpro-warning-border, #d99b26);
    color: var(--vpro-warning-ink, #704b00);
  }

  .web-dl-error {
    background: var(--vpro-error-bg, #fbeaea);
    border: 1px solid var(--vpro-error-border, #e59ba0);
    color: var(--vpro-error-ink, #a61b20);
  }

  .web-dl-success {
    background: var(--vpro-success-bg, #ebf5ed);
    border: 1px solid var(--vpro-success-border, #96cfa2);
    color: var(--vpro-success-ink, #1b5e29);
  }

  .web-dl-licence {
    padding-top: 8px;
    border-top: 1px solid var(--vpro-border, #d1d5db);
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .web-dl-licence-row {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }

  .web-dl-licence-title {
    display: inline-flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 5px;
    font-size: 12px;
    font-weight: 600;
    color: var(--vpro-ink, #313132);
  }

  .web-dl-licence-link {
    display: inline-flex;
    align-items: center;
    gap: 3px;
    color: var(--vpro-navy, #003366);
    text-decoration: underline;
    font-weight: 700;
  }

  .web-dl-licence-link:hover {
    color: var(--vpro-navy-hover, #0a4480);
  }

  .web-dl-copy-btn {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 3px 8px;
    border-radius: 4px;
    border: 1px solid var(--vpro-border, #d1d5db);
    background: var(--vpro-surface-subtle, #f8fafb);
    color: var(--vpro-navy, #003366);
    font-size: 11px;
    font-weight: 600;
    cursor: pointer;
  }

  .web-dl-copy-btn:hover {
    background: var(--vpro-navy-tint, #ebf1f8);
  }

  .web-dl-citation {
    margin: 0;
    font-size: 11.5px;
    line-height: 1.45;
    color: var(--vpro-ink-secondary, #4b5563);
  }
</style>
