<script lang="ts">
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import type {
    MatrixDisplayMode,
    MatrixGroupingMode,
    SynthesisLumpTableOption,
    SynthesisOptions,
    SynthesisSnapshot,
  } from './classificationSynthesis';

  interface Props {
    options: SynthesisOptions;
    lumpOptions: SynthesisLumpTableOption[];
    su: string;
    snapshot: SynthesisSnapshot | null;
    loading: boolean;
    mutating: boolean;
    matrixDisplay: MatrixDisplayMode;
    matrixGrouping: MatrixGroupingMode;
    diagnosticOnly: boolean;
    useBreakpointGrouping: boolean;
    breakpointPolicy: 'lowest' | 'highest';
    excludePatternsText: string;
    externalLumpDbPath: string;
    externalSuPath: string;
    externalSuNames: string[];
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
  }

  let {
    options,
    lumpOptions,
    su,
    snapshot,
    loading,
    mutating,
    matrixDisplay,
    matrixGrouping,
    diagnosticOnly,
    useBreakpointGrouping,
    breakpointPolicy,
    excludePatternsText,
    externalLumpDbPath,
    externalSuPath,
    externalSuNames,
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
  }: Props = $props();
</script>

<div class="syn-toolbar" role="region" aria-label="Synthesis Options">
  <label class="syn-control">
    <span>Unit Classification Source</span>
    <select
      data-synthesis-unit-source
      value={options.unitSource ?? 'auto'}
      disabled={loading || mutating}
      onchange={(e) =>
        onUpdateOptions(
          { unitSource: (e.currentTarget as HTMLSelectElement).value as 'auto' | 'su' | 'user_site_unit' },
          true
        )}
    >
      <option value="auto">Auto (SU -> UserSiteUnitList)</option>
      <option value="su">Active SU Table ({snapshot?.su || su || 'None'})</option>
      <option value="user_site_unit">UserSiteUnitList Working Units</option>
    </select>
  </label>

  <label class="syn-control">
    <span>Species Lumping (99% Cap)</span>
    <select
      data-synthesis-lump-select
      value={`${options.lumpDbPath ?? ''}::${options.lumpTable ?? ''}`}
      disabled={loading || mutating}
      onchange={(e) => {
        const val = (e.currentTarget as HTMLSelectElement).value;
        const sep = val.indexOf('::');
        onUpdateOptions(
          {
            lumpDbPath: sep >= 0 ? val.slice(0, sep) : '',
            lumpTable: sep >= 0 ? val.slice(sep + 2) : '',
          },
          true
        );
      }}
    >
      <option value="::">None (Raw Species)</option>
      {#each lumpOptions as opt (`${opt.dbPath}::${opt.tableName}`)}
        <option value={`${opt.dbPath}::${opt.name}`}>
          {opt.tableName} ({opt.activeCount} active){opt.dbPath ? ` — ${opt.dbPath.split(/[\\/]/).pop()}` : ''}
        </option>
      {/each}
    </select>
  </label>

  {#if !IS_WEB_READONLY}
    <div class="syn-control-buttons">
      <button
        type="button"
        class="syn-btn syn-btn-ghost-dark"
        data-synthesis-browse-lump
        onclick={onBrowseExternalLump}
        disabled={loading || mutating}
      >
        External Lump .db...
      </button>
      <button
        type="button"
        class="syn-btn syn-btn-ghost-dark"
        data-synthesis-browse-su
        onclick={onBrowseExternalSU}
        disabled={loading || mutating}
      >
        Inspect External SU .db...
      </button>
    </div>
  {/if}

  <label class="syn-control">
    <span>Significance Basis</span>
    <select
      value={options.significanceBasis ?? 'all_plots'}
      disabled={loading || mutating}
      onchange={(e) =>
        onUpdateOptions(
          { significanceBasis: (e.currentTarget as HTMLSelectElement).value as 'all_plots' | 'present_plots' },
          true
        )}
    >
      <option value="all_plots">Mean Cover (All Unit Plots)</option>
      <option value="present_plots">Characteristic Cover (Present Plots)</option>
    </select>
  </label>

  <label class="syn-control">
    <span>Cell Notation</span>
    <select
      value={matrixDisplay}
      onchange={(e) => onMatrixDisplayChange((e.currentTarget as HTMLSelectElement).value as MatrixDisplayMode)}
    >
      <option value="roman_signif">BEC Class (I..V - +..9)</option>
      <option value="pct_cover">Constancy % / Mean Cover</option>
      <option value="crosstab">Diagnostic Code (1..5 - +..9)</option>
    </select>
  </label>

  <label class="syn-control">
    <span>Row Grouping</span>
    <select
      value={matrixGrouping}
      onchange={(e) => onMatrixGroupingChange((e.currentTarget as HTMLSelectElement).value as MatrixGroupingMode)}
    >
      <option value="diagnostic_unit">Diagnostic Unit (~Unit + Companions)</option>
      <option value="stratum">Stratum (Tree / Shrub / Herb / Moss)</option>
      <option value="lifeform">Lifeform (1..13)</option>
      <option value="flat">Flat Taxonomic List</option>
    </select>
  </label>

  <label class="syn-checkbox-control">
    <input
      type="checkbox"
      checked={options.excludeStandardModifiers}
      disabled={loading || mutating}
      onchange={(e) =>
        onUpdateOptions({ excludeStandardModifiers: (e.currentTarget as HTMLInputElement).checked }, true)}
    />
    <span>
      Exclude <code>.support</code> / <code>.poor</code> / <code>.nudum</code>
      {#if snapshot && snapshot.excludedPlotCount > 0}
        ({snapshot.excludedPlotCount} excluded)
      {/if}
    </span>
  </label>

  <label class="syn-control">
    <span>Min Max Presence (%)</span>
    <input
      type="number"
      min="0"
      max="100"
      step="1"
      data-synthesis-min-max-presence
      value={options.minMaxPresencePct ?? 0}
      oninput={(e) => {
        const val = Number((e.currentTarget as HTMLInputElement).value);
        onUpdateOptions({ minMaxPresencePct: Number.isFinite(val) ? Math.max(0, Math.min(100, val)) : 0 }, false);
      }}
      onchange={onRecompute}
    />
  </label>

  <label class="syn-checkbox-control">
    <input
      type="checkbox"
      data-synthesis-use-breakpoints
      checked={useBreakpointGrouping}
      onchange={(e) => onToggleBreakpoints((e.currentTarget as HTMLInputElement).checked)}
    />
    <span>Group by '~' Breakpoints</span>
  </label>

  {#if useBreakpointGrouping}
    <label class="syn-control">
      <span>Breakpoint Policy</span>
      <select
        data-synthesis-breakpoint-policy
        value={breakpointPolicy}
        onchange={(e) =>
          onToggleBreakpoints(true, (e.currentTarget as HTMLSelectElement).value as 'lowest' | 'highest')}
      >
        <option value="lowest">Lowest ('~' Closest Parent)</option>
        <option value="highest">Highest ('~' Broadest Parent)</option>
      </select>
    </label>
  {/if}

  <label class="syn-checkbox-control">
    <input
      type="checkbox"
      checked={diagnosticOnly}
      onchange={(e) => onDiagnosticOnlyChange((e.currentTarget as HTMLInputElement).checked)}
    />
    <span>Diagnostic Taxa Only</span>
  </label>
</div>

<details class="syn-advanced-panel" data-synthesis-advanced-params>
  <summary>
    Advanced BEC Synthesis &amp; Pairwise Thresholds (Defaults: MinPlots=2, Constancy=60%, Noise=10%, MinDiff=0.5,
    MinDd=0.5)
  </summary>
  <div class="syn-advanced-body">
    <div class="syn-params-grid">
      <label class="syn-control">
        <span>Exclude Species Patterns (comma-separated)</span>
        <input
          type="text"
          placeholder="e.g. sp., x, cf."
          data-synthesis-exclude-patterns
          value={excludePatternsText}
          oninput={(e) => onExcludePatternsInput((e.currentTarget as HTMLInputElement).value)}
          onchange={onRecompute}
        />
      </label>

      <label class="syn-control">
        <span>Min Plots / Unit</span>
        <input
          type="number"
          min="1"
          step="1"
          data-synthesis-pairwise-min-plots
          value={options.pairwise?.minPlots ?? 2}
          oninput={(e) => onUpdatePairwiseParam('minPlots', (e.currentTarget as HTMLInputElement).value)}
        />
      </label>

      <label class="syn-control">
        <span>Min Constancy (%)</span>
        <input
          type="number"
          min="0"
          max="100"
          step="1"
          data-synthesis-pairwise-min-constancy
          value={options.pairwise?.minConstancy ?? 60}
          oninput={(e) => onUpdatePairwiseParam('minConstancy', (e.currentTarget as HTMLInputElement).value)}
        />
      </label>

      <label class="syn-control">
        <span>Noise Constancy (%)</span>
        <input
          type="number"
          min="0"
          max="100"
          step="1"
          data-synthesis-pairwise-noise-constancy
          value={options.pairwise?.noiseConstancy ?? 10}
          oninput={(e) => onUpdatePairwiseParam('noiseConstancy', (e.currentTarget as HTMLInputElement).value)}
        />
      </label>

      <label class="syn-control">
        <span>Min Diff Score</span>
        <input
          type="number"
          min="0"
          step="0.1"
          data-synthesis-pairwise-min-diff
          value={options.pairwise?.minDiff ?? 0.5}
          oninput={(e) => onUpdatePairwiseParam('minDiff', (e.currentTarget as HTMLInputElement).value)}
        />
      </label>

      <label class="syn-control">
        <span>Min dd Score</span>
        <input
          type="number"
          min="0"
          step="0.1"
          data-synthesis-pairwise-min-dd
          value={options.pairwise?.minDd ?? 0.5}
          oninput={(e) => onUpdatePairwiseParam('minDd', (e.currentTarget as HTMLInputElement).value)}
        />
      </label>
    </div>

    <div class="syn-advanced-actions">
      <button type="button" class="syn-btn syn-btn-ghost-dark" data-synthesis-reset-pairwise onclick={onResetPairwise}>
        Reset Pairwise Defaults (2, 60, 10, 0.5, 0.5)
      </button>
      <button
        type="button"
        class="syn-btn syn-btn-navy"
        data-synthesis-apply-params
        disabled={loading || mutating}
        onclick={onRecompute}
      >
        Apply Parameters &amp; Recompute
      </button>
    </div>

    {#if externalLumpDbPath || externalSuPath}
      <div class="syn-external-summary" data-synthesis-external-paths>
        {#if externalLumpDbPath}
          <div><strong>External Lump DB:</strong> <code>{externalLumpDbPath}</code></div>
        {/if}
        {#if externalSuPath}
          <div>
            <strong>Inspected External SU DB:</strong> <code>{externalSuPath}</code>
            {#if externalSuNames.length > 0}
              <span> ({externalSuNames.join(', ')})</span>
            {/if}
          </div>
        {/if}
      </div>
    {/if}
  </div>
</details>
