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
  <div class="syn-alert syn-alert-error" role="alert">{errorMessage}</div>
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
