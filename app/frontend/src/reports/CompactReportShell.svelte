<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { HTMLReportResult, SpreadsheetAppPreference } from '../../bindings/github.com/boostao/vpro/app';
  import { notifications } from '../shell/notificationService.svelte';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import {
    SPREADSHEET_APP_PRESETS,
    defaultSpreadsheetAppPort,
    describeCompactScope,
    formatBytesCompact,
    formatCompactReportError,
    formatSpreadsheetAppLabel,
    type QuickExportSummary,
    type SpreadsheetAppPort,
  } from './compactReport';
  import HTMLReportPreviewModal from './HTMLReportPreviewModal.svelte';

  interface Props {
    title: string;
    subtitle?: string;
    contextId: string;
    project?: string;
    su?: string;
    hierarchy?: string;
    requiresHierarchy?: boolean;
    busy?: boolean;
    actionDisabled?: boolean;
    exporting?: boolean;
    rendering?: boolean;
    exportResult?: QuickExportSummary | null;
    htmlReport?: HTMLReportResult | null;
    errorMessage?: string;
    advancedLabel?: string;
    defaultAdvancedOpen?: boolean;
    spreadsheetPort?: SpreadsheetAppPort;
    onExportSpreadsheet: () => void | Promise<void>;
    onDisplayReport: () => void | Promise<void>;
    onCloseHtmlReport: () => void;
    headerExtra?: Snippet;
    quickOptions?: Snippet;
    advanced?: Snippet;
    results?: Snippet;
  }

  let {
    title,
    subtitle = '',
    contextId,
    project = '',
    su = 'None',
    hierarchy = 'None',
    requiresHierarchy = false,
    busy = false,
    actionDisabled = false,
    exporting = false,
    rendering = false,
    exportResult = null,
    htmlReport = null,
    errorMessage = '',
    advancedLabel = 'Advanced Options',
    defaultAdvancedOpen = false,
    spreadsheetPort = defaultSpreadsheetAppPort,
    onExportSpreadsheet,
    onDisplayReport,
    onCloseHtmlReport,
    headerExtra,
    quickOptions,
    advanced,
    results,
  }: Props = $props();

  let appPopoverOpen = $state(false);
  let appPref = $state<SpreadsheetAppPreference>({ programPath: '', autoOpenExports: true });
  let appPrefLoaded = $state(false);
  let appPrefBusy = $state(false);
  let appPrefError = $state('');
  let openingExport = $state(false);

  const scopeInfo = $derived(describeCompactScope({ project, su, hierarchy, requiresHierarchy }));
  const actionsLocked = $derived(busy || exporting || rendering || actionDisabled || !scopeInfo.ready || !contextId);
  const appBadgeLabel = $derived(formatSpreadsheetAppLabel(appPref));

  async function loadSpreadsheetPref() {
    if (IS_WEB_READONLY || !contextId || appPrefBusy) return;
    appPrefBusy = true;
    appPrefError = '';
    try {
      const loaded = await spreadsheetPort.getPreference(contextId);
      if (loaded) {
        appPref = {
          programPath: loaded.programPath ?? '',
          autoOpenExports: Boolean(loaded.autoOpenExports),
        };
        appPrefLoaded = true;
      }
    } catch (cause) {
      appPrefError = formatCompactReportError(cause, 'Load spreadsheet preference');
    } finally {
      appPrefBusy = false;
    }
  }

  function toggleAppPopover() {
    appPopoverOpen = !appPopoverOpen;
    if (appPopoverOpen && !appPrefLoaded) {
      void loadSpreadsheetPref();
    }
  }

  async function saveSpreadsheetPref() {
    if (IS_WEB_READONLY || !contextId || appPrefBusy) return;
    appPrefBusy = true;
    appPrefError = '';
    try {
      const saved = await spreadsheetPort.setPreference(contextId, {
        programPath: appPref.programPath.trim(),
        autoOpenExports: appPref.autoOpenExports,
      });
      if (saved) {
        appPref = {
          programPath: saved.programPath ?? '',
          autoOpenExports: Boolean(saved.autoOpenExports),
        };
      }
      appPrefLoaded = true;
      appPopoverOpen = false;
      notifications.success('Spreadsheet app saved', `Exported reports will use ${formatSpreadsheetAppLabel(appPref)}.`, {
        category: 'reports',
        source: title,
        contextTag: project || undefined,
      });
    } catch (cause) {
      appPrefError = formatCompactReportError(cause, 'Save spreadsheet preference');
    } finally {
      appPrefBusy = false;
    }
  }

  async function openExportedSpreadsheet() {
    if (IS_WEB_READONLY || !contextId || !exportResult?.path || openingExport) return;
    openingExport = true;
    try {
      await spreadsheetPort.openFile(contextId, exportResult.path);
    } catch (cause) {
      const msg = formatCompactReportError(cause, 'Open spreadsheet');
      notifications.error('Could not open spreadsheet', msg, {
        category: 'reports',
        source: title,
        contextTag: project || undefined,
      });
    } finally {
      openingExport = false;
    }
  }
</script>

<div class="compact-report-shell" data-compact-report-shell>
  <header
    class="sticky top-0 z-20 bg-white/95 backdrop-blur-xs py-2 border-b border-vpro-border report-sticky-bar"
    data-report-sticky-bar
  >
    <div class="header-title-group">
      <h1>{title}</h1>
      {#if subtitle}
        <p class="header-subtitle">{subtitle}</p>
      {/if}
    </div>
    <div class="header-actions">
      <button
        type="button"
        class="btn-primary"
        data-compact-export-spreadsheet
        disabled={actionsLocked}
        onclick={() => void onExportSpreadsheet()}
      >
        {exporting
          ? IS_WEB_READONLY
            ? 'Preparing Spreadsheet...'
            : 'Exporting Spreadsheet...'
          : 'Export to Spreadsheet'}
      </button>
      <button
        type="button"
        class="btn-display"
        data-compact-display-report
        disabled={actionsLocked}
        onclick={() => void onDisplayReport()}
      >
        {rendering ? 'Rendering Report...' : 'Display Report'}
      </button>
      {#if !IS_WEB_READONLY}
        <button
          type="button"
          class="btn-app-settings"
          data-spreadsheet-app-toggle
          aria-expanded={appPopoverOpen}
          disabled={!contextId}
          onclick={toggleAppPopover}
        >
          Spreadsheet App: {appBadgeLabel}
        </button>
      {/if}
      {#if headerExtra}
        {@render headerExtra()}
      {/if}
    </div>
  </header>

  {#if !IS_WEB_READONLY && appPopoverOpen}
    <section
      class="spreadsheet-popover"
      data-spreadsheet-app-popover
      aria-label="Spreadsheet Application Settings"
    >
      <div class="popover-head">
        <strong>Designated Spreadsheet Program</strong>
        <button type="button" class="btn-link" onclick={() => (appPopoverOpen = false)}>Close</button>
      </div>
      <div class="preset-row">
        {#each SPREADSHEET_APP_PRESETS as preset (preset.id)}
          <button
            type="button"
            class="preset-chip"
            class:selected={appPref.programPath.trim().toLowerCase() === preset.programPath.toLowerCase()}
            disabled={appPrefBusy}
            onclick={() => {
              appPref = { ...appPref, programPath: preset.programPath };
            }}
          >
            {preset.label}
          </button>
        {/each}
      </div>
      <div class="popover-fields">
        <label class="popover-path">
          <span>Executable Path (blank = OS Default)</span>
          <input
            type="text"
            data-spreadsheet-app-path
            placeholder="Leave blank for OS default, or enter excel / soffice / full path"
            value={appPref.programPath}
            disabled={appPrefBusy}
            oninput={(e) => {
              appPref = { ...appPref, programPath: e.currentTarget.value };
            }}
          />
        </label>
        <label class="popover-check">
          <input
            type="checkbox"
            data-spreadsheet-auto-open
            checked={appPref.autoOpenExports}
            disabled={appPrefBusy}
            onchange={(e) => {
              appPref = { ...appPref, autoOpenExports: e.currentTarget.checked };
            }}
          />
          <span>Open exported workbooks automatically</span>
        </label>
      </div>
      {#if appPrefError}
        <p class="compact-error" role="alert">{appPrefError}</p>
      {/if}
      <div class="popover-actions">
        <button
          type="button"
          class="btn-primary"
          data-spreadsheet-app-save
          disabled={appPrefBusy}
          onclick={() => void saveSpreadsheetPref()}
        >
          {appPrefBusy ? 'Saving...' : 'Save Spreadsheet Preference'}
        </button>
      </div>
    </section>
  {/if}

  <div class="scope-strip" class:fallback={scopeInfo.mode === 'fallback'} class:warn={scopeInfo.mode === 'missing-hierarchy'} data-compact-scope-badge>
    <span class="scope-pill">{scopeInfo.badge}</span>
    <span class="scope-detail">{scopeInfo.detail}</span>
  </div>

  {#if quickOptions}
    <div class="quick-options-card" data-compact-quick-options>
      {@render quickOptions()}
    </div>
  {/if}

  {#if errorMessage}
    <p class="compact-error" role="alert" data-compact-error>{errorMessage}</p>
  {/if}

  {#if exportResult}
    <div class="export-receipt" role="status" data-compact-export-receipt>
      <div class="receipt-main">
        <strong>
          {IS_WEB_READONLY ? 'Spreadsheet ready for download:' : 'Spreadsheet exported:'}
          {exportResult.title || title}
        </strong>
        <span>
          {exportResult.unitCount} unit{exportResult.unitCount === 1 ? '' : 's'} ·
          {exportResult.plotCount} plot{exportResult.plotCount === 1 ? '' : 's'} ·
          {formatBytesCompact(exportResult.bytes)}
          {#if exportResult.preferencesSaved} · Settings saved{/if}
        </span>
        {#if !IS_WEB_READONLY && exportResult.path}
          <span class="receipt-path">File: <code>{exportResult.path}</code></span>
        {/if}
        {#if exportResult.fallbackNotice}
          <span class="receipt-note">{exportResult.fallbackNotice}</span>
        {/if}
        {#if exportResult.spreadsheetNotice}
          <span class="receipt-note">{exportResult.spreadsheetNotice}</span>
        {/if}
      </div>
      {#if !IS_WEB_READONLY && exportResult.path}
        <button
          type="button"
          class="btn-app-settings"
          data-compact-open-exported
          disabled={openingExport}
          onclick={() => void openExportedSpreadsheet()}
        >
          {openingExport ? 'Opening...' : 'Open in Spreadsheet'}
        </button>
      {/if}
    </div>
  {/if}

  {#if advanced}
    <details class="advanced-drawer" data-compact-advanced-drawer open={defaultAdvancedOpen}>
      <summary>{advancedLabel}</summary>
      <div class="advanced-body">
        {@render advanced()}
      </div>
    </details>
  {/if}

  {#if results}
    {@render results()}
  {/if}

  <HTMLReportPreviewModal
    open={Boolean(htmlReport)}
    report={htmlReport}
    onClose={onCloseHtmlReport}
  />
</div>

<style>
  .compact-report-shell {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 0.75rem;
    min-width: 0;
  }
  .report-sticky-bar {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 0.65rem;
    padding-inline: 0.75rem;
    border-radius: 0.35rem;
  }
  .header-title-group {
    display: grid;
    gap: 0.1rem;
    min-width: 0;
  }
  .header-title-group h1 {
    margin: 0;
    font-size: 1.4rem;
    color: var(--vpro-navy);
  }
  .header-subtitle {
    margin: 0;
    font-size: 0.82rem;
    color: var(--vpro-ink-secondary);
  }
  .header-actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    align-items: center;
  }
  .btn-primary {
    min-height: 2.35rem;
    padding: 0.45rem 0.9rem;
    border: 1px solid var(--vpro-navy);
    border-radius: 0.3rem;
    background: var(--vpro-navy);
    color: var(--vpro-surface);
    font-weight: 600;
    font-size: 0.85rem;
    cursor: pointer;
  }
  .btn-primary:hover:not(:disabled) {
    background: var(--vpro-navy-dark);
  }
  .btn-display {
    min-height: 2.35rem;
    padding: 0.45rem 0.9rem;
    border: 1px solid var(--vpro-gold);
    border-radius: 0.3rem;
    background: var(--vpro-gold);
    color: var(--vpro-navy);
    font-weight: 700;
    font-size: 0.85rem;
    cursor: pointer;
  }
  .btn-display:hover:not(:disabled) {
    filter: brightness(0.95);
  }
  .btn-app-settings {
    min-height: 2.35rem;
    padding: 0.42rem 0.75rem;
    border: 1px solid var(--vpro-border-strong);
    border-radius: 0.3rem;
    background: var(--vpro-surface);
    color: var(--vpro-navy);
    font-weight: 600;
    font-size: 0.8rem;
    cursor: pointer;
  }
  .btn-app-settings:hover:not(:disabled) {
    background: var(--vpro-canvas);
  }
  button:disabled {
    opacity: 0.55;
    cursor: not-allowed;
  }
  .btn-link {
    border: 0;
    background: transparent;
    color: var(--vpro-navy);
    font-weight: 600;
    font-size: 0.8rem;
    cursor: pointer;
    text-decoration: underline;
  }
  .spreadsheet-popover {
    background: var(--vpro-surface);
    border: 1px solid var(--vpro-navy);
    border-top: 3px solid var(--vpro-gold);
    border-radius: 0.4rem;
    padding: 0.8rem 0.95rem;
    display: grid;
    gap: 0.6rem;
  }
  .popover-head {
    display: flex;
    justify-content: space-between;
    align-items: center;
    color: var(--vpro-navy);
    font-size: 0.88rem;
  }
  .preset-row {
    display: flex;
    flex-wrap: wrap;
    gap: 0.4rem;
  }
  .preset-chip {
    padding: 0.32rem 0.7rem;
    border: 1px solid var(--vpro-border-strong);
    border-radius: 999px;
    background: var(--vpro-canvas);
    color: var(--vpro-ink);
    font-size: 0.78rem;
    font-weight: 600;
    cursor: pointer;
  }
  .preset-chip.selected {
    background: var(--vpro-navy);
    color: var(--vpro-surface);
    border-color: var(--vpro-navy);
  }
  .popover-fields {
    display: grid;
    gap: 0.5rem;
  }
  .popover-path {
    display: grid;
    gap: 0.2rem;
    font-size: 0.8rem;
    color: var(--vpro-ink);
  }
  .popover-path input {
    padding: 0.42rem 0.55rem;
    border: 1px solid var(--vpro-border-strong);
    border-radius: 0.25rem;
    background: var(--vpro-surface);
    color: var(--vpro-ink);
    font-size: 0.82rem;
  }
  .popover-check {
    display: inline-flex;
    align-items: center;
    gap: 0.45rem;
    font-size: 0.82rem;
    color: var(--vpro-ink);
  }
  .popover-actions {
    display: flex;
    justify-content: flex-end;
  }
  .scope-strip {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.55rem;
    padding: 0.5rem 0.75rem;
    background: var(--vpro-surface);
    border: 1px solid var(--vpro-border);
    border-left: 4px solid var(--vpro-navy);
    border-radius: 0.3rem;
    font-size: 0.82rem;
  }
  .scope-strip.fallback {
    border-left-color: var(--vpro-gold);
  }
  .scope-strip.warn {
    border-left-color: var(--vpro-error);
  }
  .scope-pill {
    font-weight: 700;
    color: var(--vpro-navy);
    background: var(--vpro-canvas);
    padding: 0.15rem 0.5rem;
    border-radius: 999px;
    border: 1px solid var(--vpro-border);
  }
  .scope-detail {
    color: var(--vpro-ink-secondary);
  }
  .quick-options-card {
    background: var(--vpro-surface);
    border: 1px solid var(--vpro-border);
    border-radius: 0.4rem;
    padding: 0.75rem 0.9rem;
    display: grid;
    gap: 0.65rem;
  }
  .compact-error {
    margin: 0;
    padding: 0.55rem 0.8rem;
    background: var(--vpro-error-bg);
    border-left: 4px solid var(--vpro-error);
    border-radius: 0.3rem;
    color: var(--vpro-error);
    font-size: 0.84rem;
    font-weight: 600;
  }
  .export-receipt {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 0.65rem;
    padding: 0.65rem 0.85rem;
    background: var(--vpro-success-bg);
    border: 1px solid var(--vpro-border);
    border-left: 4px solid var(--vpro-success);
    border-radius: 0.35rem;
    font-size: 0.82rem;
  }
  .receipt-main {
    display: grid;
    gap: 0.2rem;
    min-width: 0;
    overflow-wrap: anywhere;
  }
  .receipt-path {
    color: var(--vpro-ink);
  }
  .receipt-note {
    color: var(--vpro-ink-secondary);
  }
  .advanced-drawer {
    background: var(--vpro-surface);
    border: 1px solid var(--vpro-border);
    border-radius: 0.4rem;
    padding: 0.5rem 0.85rem;
  }
  .advanced-drawer > summary {
    cursor: pointer;
    font-weight: 600;
    font-size: 0.86rem;
    color: var(--vpro-navy);
    padding-block: 0.2rem;
  }
  .advanced-body {
    margin-top: 0.75rem;
    display: grid;
    gap: 0.75rem;
    min-width: 0;
  }
</style>
