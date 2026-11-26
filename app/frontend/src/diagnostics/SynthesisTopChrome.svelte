<script lang="ts">
  import SynthesisHeader from './SynthesisHeader.svelte';
  import SynthesisToolbar from './SynthesisToolbar.svelte';
  import type {
    MatrixDisplayMode,
    MatrixGroupingMode,
    SynthesisLumpTableOption,
    SynthesisOptions,
    SynthesisSnapshot,
  } from './classificationSynthesis';

  let {
    snapshot,
    project,
    su,
    lastLatencyMs,
    loading,
    mutating,
    options,
    lumpOptions,
    matrixDisplay,
    matrixGrouping,
    diagnosticOnly,
    useBreakpointGrouping,
    breakpointPolicy,
    excludePatternsText,
    externalLumpDbPath,
    externalSuPath,
    externalSuNames,
    errorMessage,
    statusNotice = $bindable(),
    onRefresh,
    onUndo,
    onOpenExport,
    onUpdateOptions,
    onRecompute,
    onBrowseExternalLump,
    onBrowseExternalSU,
    onMatrixDisplayChange,
    onMatrixGroupingChange,
    onDiagnosticOnlyChange,
    onToggleBreakpoints,
    onExcludePatternsInput,
    onUpdatePairwiseParam,
    onResetPairwise,
  }: {
    snapshot: SynthesisSnapshot | null;
    project: string;
    su: string;
    lastLatencyMs: number | null;
    loading: boolean;
    mutating: boolean;
    options: SynthesisOptions;
    lumpOptions: SynthesisLumpTableOption[];
    matrixDisplay: MatrixDisplayMode;
    matrixGrouping: MatrixGroupingMode;
    diagnosticOnly: boolean;
    useBreakpointGrouping: boolean;
    breakpointPolicy: 'lowest' | 'highest';
    excludePatternsText: string;
    externalLumpDbPath: string;
    externalSuPath: string;
    externalSuNames: string[];
    errorMessage: string;
    statusNotice: string;
    onRefresh: () => void;
    onUndo: () => void;
    onOpenExport: () => void;
    onUpdateOptions: (patch: Partial<SynthesisOptions>, recompute?: boolean) => void;
    onRecompute: () => void;
    onBrowseExternalLump: () => void;
    onBrowseExternalSU: () => void;
    onMatrixDisplayChange: (mode: MatrixDisplayMode) => void;
    onMatrixGroupingChange: (mode: MatrixGroupingMode) => void;
    onDiagnosticOnlyChange: (checked: boolean) => void;
    onToggleBreakpoints: (enabled: boolean, policy?: 'lowest' | 'highest') => void;
    onExcludePatternsInput: (raw: string) => void;
    onUpdatePairwiseParam: (
      key: 'minPlots' | 'minConstancy' | 'noiseConstancy' | 'minDiff' | 'minDd',
      raw: string
    ) => void;
    onResetPairwise: () => void;
  } = $props();
</script>

<SynthesisHeader {snapshot} {project} {su} {lastLatencyMs} {loading} {mutating} {onRefresh} {onUndo} {onOpenExport} />

<SynthesisToolbar
  {options}
  {lumpOptions}
  {su}
  {snapshot}
  {loading}
  {mutating}
  {matrixDisplay}
  {matrixGrouping}
  {diagnosticOnly}
  {useBreakpointGrouping}
  {breakpointPolicy}
  {excludePatternsText}
  {externalLumpDbPath}
  {externalSuPath}
  {externalSuNames}
  {onUpdateOptions}
  {onRecompute}
  {onBrowseExternalLump}
  {onBrowseExternalSU}
  {onMatrixDisplayChange}
  {onMatrixGroupingChange}
  {onDiagnosticOnlyChange}
  {onToggleBreakpoints}
  {onExcludePatternsInput}
  {onUpdatePairwiseParam}
  {onResetPairwise}
/>

{#if errorMessage}
  <div class="syn-alert syn-alert-error" role="alert">
    <span>{errorMessage}</span>
    {#if (!su || su === 'None') && options.unitSource !== 'user_site_unit'}
      <button
        type="button"
        class="syn-btn syn-btn-ghost-dark"
        data-synthesis-try-working-units
        onclick={() => onUpdateOptions({ unitSource: 'user_site_unit' }, true)}
      >
        Try Working Units (UserSiteUnitList)
      </button>
    {/if}
  </div>
{/if}

{#if (!su || su === 'None') && (!snapshot || snapshot.units.length === 0) && !loading}
  <div class="syn-scope-guidance" data-synthesis-scope-guidance role="status">
    <div>
      <strong>No active Site Unit table is attached.</strong>
      <span>
        Analysis checks your active Site Unit table first and falls back to working units (UserSiteUnitList). Attach or
        create a Site Unit table in the sidebar, or inspect an external Site Unit file to run diagnostics.
      </span>
    </div>
    <div class="syn-guidance-actions">
      <button
        type="button"
        class="syn-btn syn-btn-navy"
        data-synthesis-use-working-units
        disabled={loading || mutating}
        onclick={() => onUpdateOptions({ unitSource: 'user_site_unit' }, true)}
      >
        Use Working Units
      </button>
      <button
        type="button"
        class="syn-btn syn-btn-ghost-dark"
        data-synthesis-retry-analysis
        disabled={loading || mutating}
        onclick={onRefresh}
      >
        Refresh Analysis
      </button>
    </div>
  </div>
{/if}

{#if statusNotice}
  <div class="syn-alert syn-alert-info" role="status">
    <span>{statusNotice}</span>
    <button type="button" class="syn-dismiss" onclick={() => (statusNotice = '')}>Dismiss</button>
  </div>
{/if}

{#if snapshot && !snapshot.suWritable && snapshot.suReadOnlyReason}
  <div class="syn-readonly-note">
    Read-only classification view: {snapshot.suReadOnlyReason}
  </div>
{/if}

<style>
  .syn-scope-guidance {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 0.75rem;
    padding: 0.7rem 0.9rem;
    background: var(--vpro-surface);
    border: 1px solid var(--vpro-border);
    border-left: 4px solid var(--vpro-gold);
    border-radius: 4px;
    font-size: 0.84rem;
    color: var(--vpro-ink);
  }
  .syn-scope-guidance strong {
    display: block;
    color: var(--vpro-navy);
    margin-bottom: 0.15rem;
  }
  .syn-guidance-actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    align-items: center;
  }
</style>
