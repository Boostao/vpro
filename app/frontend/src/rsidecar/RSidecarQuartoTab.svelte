<script lang="ts">
  import type { QuartoGuideResult, QuartoGuideType, RRuntimeStatus } from './rSidecarWorkbench';
  import { IS_WEB_READONLY } from '../web/runtimeMode';

  let {
    activeSu = 'None',
    busy = false,
    runtimeStatus = null,
    standaloneQuartoMode = false,
    quartoGuideType = $bindable<QuartoGuideType>('single_unit'),
    quartoTitle = $bindable(''),
    quartoTargetUnit = $bindable(''),
    quartoBgcFilter = $bindable(''),
    quartoConceptNotes = $bindable(''),
    quartoMinConstancy = $bindable(20),
    quartoUseSu = $bindable(false),
    quartoApplyLump = $bindable(true),
    quartoIncludePdf = $bindable(false),
    quartoDestinationPath = $bindable(''),
    quartoValidationError = null,
    quartoResult = null,
    onRenderQuarto,
    onRefreshRuntime,
    onInstantHTMLReport,
  }: {
    activeSu?: string;
    busy?: boolean;
    runtimeStatus?: RRuntimeStatus | null;
    standaloneQuartoMode?: boolean;
    quartoGuideType?: QuartoGuideType;
    quartoTitle?: string;
    quartoTargetUnit?: string;
    quartoBgcFilter?: string;
    quartoConceptNotes?: string;
    quartoMinConstancy?: number;
    quartoUseSu?: boolean;
    quartoApplyLump?: boolean;
    quartoIncludePdf?: boolean;
    quartoDestinationPath?: string;
    quartoValidationError?: string | null;
    quartoResult?: QuartoGuideResult | null;
    onRenderQuarto: () => Promise<void> | void;
    onRefreshRuntime?: () => Promise<void> | void;
    onInstantHTMLReport?: () => Promise<void> | void;
  } = $props();

  const hasActiveSu = $derived(Boolean(activeSu && activeSu !== 'None'));
</script>

<div class="panel" data-quarto-unit-report-panel>
  <div class="card">
    <h3>{standaloneQuartoMode ? 'Quarto Unit & BGC Ecosystem Report' : 'Automated Quarto Single-Unit & BGC Guide Publisher'}</h3>

    <div class="readiness-strip" data-quarto-readiness-strip>
      {#if runtimeStatus}
        <span class="badge" class:ok={runtimeStatus.available} class:warn={!runtimeStatus.available}>
          R: {runtimeStatus.available ? `Ready (${runtimeStatus.rVersion})` : 'Not Installed'}
        </span>
        <span class="badge" class:ok={runtimeStatus.quartoAvailable} class:warn={!runtimeStatus.quartoAvailable}>
          Quarto: {runtimeStatus.quartoAvailable ? `Ready (${runtimeStatus.quartoVersion})` : 'Not Installed'}
        </span>
        {#if !runtimeStatus.available || !runtimeStatus.quartoAvailable}
          <span class="readiness-note">
            Quarto or R is not detected on this workstation. You can still generate an instant Quarto-style HTML report
            directly in VPro below.
          </span>
        {/if}
      {:else}
        <span class="readiness-note">
          Use Quarto / R for full ecosystem guides, or open an instant Quarto-style HTML report right away without R.
        </span>
        {#if onRefreshRuntime}
          <button type="button" class="btn-secondary" disabled={busy} onclick={onRefreshRuntime}>
            Check R &amp; Quarto Status
          </button>
        {/if}
      {/if}
    </div>

    <div class="form-row">
      <label>
        Guide Template
        <select bind:value={quartoGuideType}>
          <option value="single_unit">Single Site Unit Ecosystem Guide</option>
          <option value="bgc_unit">Full BGC Subzone / Variant Synthesis Guide</option>
        </select>
      </label>
      <label>
        Guide Title (Optional)
        <input type="text" bind:value={quartoTitle} placeholder="Auto-titled from unit or BGC" />
      </label>
      <label>
        Target Site Unit Filter
        <input type="text" bind:value={quartoTargetUnit} placeholder="e.g. BWBSmw 2 /05" />
      </label>
      <label>
        BGC Filter
        <input type="text" bind:value={quartoBgcFilter} placeholder="e.g. BWBS, MH, SBSdk" />
      </label>
      <label>
        Min Constancy (%)
        <input type="number" min="0" max="100" step="5" bind:value={quartoMinConstancy} />
      </label>
      {#if !IS_WEB_READONLY}
        <label>
          Destination .html Path (Optional)
          <input type="text" bind:value={quartoDestinationPath} placeholder="Defaults to <ProjectDir>/exports/" />
        </label>
      {/if}
    </div>

    <div class="form-row">
      <label class="full-width">
        Authored Ecological Concept &amp; Diagnostic Narrative
        <textarea
          rows="3"
          bind:value={quartoConceptNotes}
          placeholder="Enter ecosystem concept statement, characteristic physiography, soils, and seral dynamics..."
        ></textarea>
      </label>
    </div>

    <div class="form-row">
      <label class="checkbox-label">
        <input type="checkbox" bind:checked={quartoUseSu} disabled={!hasActiveSu} />
        {hasActiveSu ? `Scope to Active SU (${activeSu})` : 'Scope to Active SU (None attached — using all project plots)'}
      </label>
      <label class="checkbox-label">
        <input type="checkbox" bind:checked={quartoApplyLump} />
        Fold Taxonomic Lump Table (*_Lump)
      </label>
      <label class="checkbox-label">
        <input type="checkbox" bind:checked={quartoIncludePdf} />
        Attempt Companion PDF Export (Print-Ready HTML Always Embedded)
      </label>
    </div>

    {#if quartoValidationError}
      <div class="inline-error">{quartoValidationError}</div>
    {/if}

    <div class="button-row">
      <button
        type="button"
        class="btn-primary"
        data-quarto-render-guide
        disabled={busy || Boolean(quartoValidationError)}
        onclick={onRenderQuarto}
      >
        {IS_WEB_READONLY
          ? busy
            ? 'Preparing Guide Download...'
            : 'Render & Download Guide'
          : 'Render & Publish Guide'}
      </button>
      {#if onInstantHTMLReport}
        <button
          type="button"
          class="btn-secondary"
          data-quarto-instant-html-fallback
          disabled={busy}
          onclick={onInstantHTMLReport}
        >
          Display Instant HTML Report (No R Required)
        </button>
      {/if}
    </div>

    {#if quartoResult}
      <div class="kpi-row">
        <div class="kpi"><span>Renderer</span><strong>{quartoResult.rendererUsed}</strong></div>
        <div class="kpi"><span>Plots Summarized</span><strong>{quartoResult.plotCount}</strong></div>
        <div class="kpi"><span>Characteristic Taxa</span><strong>{quartoResult.speciesRowCount}</strong></div>
        <div class="kpi">
          <span>HTML Size</span><strong>{(quartoResult.htmlSizeBytes / 1024).toFixed(1)} KB</strong>
        </div>
        {#if quartoResult.pdfStatus}
          <div class="kpi"><span>PDF Status</span><strong>{quartoResult.pdfStatus}</strong></div>
        {/if}
      </div>
      <p class="receipt-line">
        Published Path: <code>{quartoResult.htmlPath}</code> | SHA-256:
        <code>{quartoResult.htmlSha256.slice(0, 16)}...</code>
      </p>

      <h4>Standalone HTML Guide Preview</h4>
      <iframe
        class="quarto-preview-frame"
        title="Published BEC Quarto Guide Preview"
        sandbox=""
        srcdoc={quartoResult.htmlPreview}
      ></iframe>
    {/if}
  </div>
</div>

<style>
  .readiness-strip {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.5rem;
    padding: 0.55rem 0.75rem;
    margin-bottom: 0.75rem;
    background: var(--vpro-canvas);
    border: 1px solid var(--vpro-border);
    border-left: 4px solid var(--vpro-gold);
    border-radius: 4px;
    font-size: 0.82rem;
  }
  .readiness-note {
    color: var(--vpro-ink-secondary);
  }
</style>
