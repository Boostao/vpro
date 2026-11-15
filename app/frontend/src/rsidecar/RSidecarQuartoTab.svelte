<script lang="ts">
  import type { QuartoGuideResult, QuartoGuideType } from './rSidecarWorkbench';

  let {
    activeSu = 'None',
    busy = false,
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
  }: {
    activeSu?: string;
    busy?: boolean;
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
  } = $props();
</script>

<div class="panel">
  <div class="card">
    <h3>Automated Quarto Single-Unit &amp; BGC Guide Publisher</h3>
    <div class="form-row">
      <label>
        Guide Template
        <select bind:value={quartoGuideType}>
          <option value="single_unit">Single Site Unit Ecosystem Guide (4.d)</option>
          <option value="bgc_unit">Full BGC Subzone / Variant Synthesis Guide (4.e)</option>
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
      <label>
        Destination .html Path (Optional)
        <input type="text" bind:value={quartoDestinationPath} placeholder="Defaults to <ProjectDir>/exports/" />
      </label>
    </div>

    <div class="form-row">
      <label class="full-width">
        Authored Ecological Concept &amp; Diagnostic Narrative
        <textarea
          rows="3"
          bind:value={quartoConceptNotes}
          placeholder="Enter ecosystem concept statement, characteristicphysiography, soils, and seral dynamics..."
        ></textarea>
      </label>
    </div>

    <div class="form-row">
      <label class="checkbox-label">
        <input type="checkbox" bind:checked={quartoUseSu} />
        Scope to Active SU ({activeSu})
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
        disabled={busy || Boolean(quartoValidationError)}
        onclick={onRenderQuarto}
      >
        Render &amp; Publish Guide
      </button>
    </div>

    {#if quartoResult}
      <div class="kpi-row">
        <div class="kpi"><span>Renderer</span><strong>{quartoResult.rendererUsed}</strong></div>
        <div class="kpi"><span>Plots Summarized</span><strong>{quartoResult.plotCount}</strong></div>
        <div class="kpi"><span>Characteristic Taxa</span><strong>{quartoResult.speciesRowCount}</strong></div>
        <div class="kpi"><span>HTML Size</span><strong>{(quartoResult.htmlSizeBytes / 1024).toFixed(1)} KB</strong></div>
        {#if quartoResult.pdfStatus}
          <div class="kpi"><span>PDF Status</span><strong>{quartoResult.pdfStatus}</strong></div>
        {/if}
      </div>
      <p class="receipt-line">
        Published Path: <code>{quartoResult.htmlPath}</code> | SHA-256: <code>{quartoResult.htmlSha256.slice(0, 16)}...</code>
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
