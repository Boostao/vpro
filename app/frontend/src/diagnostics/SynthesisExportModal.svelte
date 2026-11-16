<script lang="ts">
  import type { ExportDiagnosticWorkbookResult, SynthesisExportDraft } from './classificationSynthesis';

  interface Props {
    open: boolean;
    draft: SynthesisExportDraft;
    exportValidationMessage: string;
    lastExportResult: ExportDiagnosticWorkbookResult | null;
    exportingWorkbook: boolean;
    onClose: () => void;
    onPublish: () => void;
  }

  let {
    open,
    draft = $bindable(),
    exportValidationMessage,
    lastExportResult,
    exportingWorkbook,
    onClose,
    onPublish,
  }: Props = $props();
</script>

{#if open}
  <div class="syn-modal-backdrop" role="dialog" aria-modal="true" aria-label="Publish BEC Diagnostic Workbook">
    <div class="syn-modal">
      <div class="syn-modal-hdr">
        <h3>Publish BEC Diagnostic Synthesis Workbook (.xlsx)</h3>
        <button type="button" class="syn-dismiss" onclick={onClose}>
          Close
        </button>
      </div>

      <div class="syn-modal-body">
        <p class="syn-modal-desc">
          Creates a new 4-sheet diagnostic Excel workbook (.xlsx, without overwriting existing files):
          BEC colour-coded Diagnostic Summary, Pairwise Similarity Matrix, Leave-One-Out Outlier Queue, and
          9x6 Edatopic Grids.
        </p>

        <label class="syn-modal-field">
          <span>Output .xlsx File Path (Absolute Path, No Overwrite)</span>
          <input
            type="text"
            placeholder="/path/to/BEC_Diagnostic_Synthesis.xlsx"
            bind:value={draft.outputPath}
          />
        </label>

        <label class="syn-modal-field">
          <span>Report Title (Optional)</span>
          <input
            type="text"
            placeholder="VPro BEC Diagnostic Summary Vegetation Report"
            bind:value={draft.reportTitle}
          />
        </label>

        <div class="syn-sheet-grid">
          <label class="syn-modal-field">
            <span>Sheet 1 (Diagnostic)</span>
            <input type="text" maxlength="31" bind:value={draft.diagnosticSheetName} />
          </label>
          <label class="syn-modal-field">
            <span>Sheet 2 (Similarity)</span>
            <input type="text" maxlength="31" bind:value={draft.similaritySheetName} />
          </label>
          <label class="syn-modal-field">
            <span>Sheet 3 (Outliers)</span>
            <input type="text" maxlength="31" bind:value={draft.outlierSheetName} />
          </label>
          <label class="syn-modal-field">
            <span>Sheet 4 (Edatopic)</span>
            <input type="text" maxlength="31" bind:value={draft.edatopicSheetName} />
          </label>
        </div>

        <div class="syn-modal-checks">
          <label class="syn-checkbox-control">
            <input type="checkbox" bind:checked={draft.includeCommonNames} />
            <span>Include English Common Names Column</span>
          </label>
          <label class="syn-checkbox-control">
            <input type="checkbox" bind:checked={draft.includeUnitEdatopicTabs} />
            <span>Append Individual Unit Edatopic Tabs</span>
          </label>
        </div>

        {#if exportValidationMessage}
          <div class="syn-validation-hint">{exportValidationMessage}</div>
        {/if}

        {#if lastExportResult}
          <div class="syn-export-success">
            <strong>Published:</strong> <code>{lastExportResult.path}</code>
            <div>SHA-256: <code>{lastExportResult.sha256.slice(0, 16)}...</code> · Sheets: {lastExportResult.sheetNames.join(', ')}</div>
          </div>
        {/if}
      </div>

      <div class="syn-modal-ftr">
        <button type="button" class="syn-btn syn-btn-ghost-dark" onclick={onClose}>
          Cancel
        </button>
        <button
          type="button"
          class="syn-btn syn-btn-navy"
          disabled={exportingWorkbook || Boolean(exportValidationMessage)}
          onclick={onPublish}
        >
          {exportingWorkbook ? 'Publishing...' : 'Publish .xlsx Workbook'}
        </button>
      </div>
    </div>
  </div>
{/if}
