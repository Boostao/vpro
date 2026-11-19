<script lang="ts">
  import { onDestroy } from 'svelte';
  import { notifications } from '../shell/notificationService.svelte';
  import {
    countDiagnosticsBySeverity,
    defaultLMH25DiagnosticsPort,
    formatHumusComparison,
    normalizeDiagnosticsWire,
    substrateProgressPercent,
    substrateStatusLabel,
    type LMH25DiagnosticsPort,
    type PlotDiagnosticsResult,
  } from './lmh25Diagnostics';

  let {
    contextId = '',
    plotNumber = '',
    header = null,
    humus = [],
    mineral = [],
    port = defaultLMH25DiagnosticsPort,
    onApplyHumusThickness,
    onApplyKeyedSMR,
    onApplyKeyedSNR,
  }: {
    contextId?: string;
    plotNumber?: string;
    header?: Record<string, unknown> | null;
    humus?: Record<string, unknown>[];
    mineral?: Record<string, unknown>[];
    port?: LMH25DiagnosticsPort;
    onApplyHumusThickness?: (value: number) => void;
    onApplyKeyedSMR?: (smrCode: string) => void;
    onApplyKeyedSNR?: (snrCode: string) => void;
  } = $props();

  let busy = $state(false);
  let error = $state('');
  let diagnostics = $state.raw<PlotDiagnosticsResult | null>(null);
  let detailsOpen = $state(false);
  let generation = 0;
  let lastNotifiedSignature = '';

  function cancel() {
    generation++;
    busy = false;
  }

  const counts = $derived.by(() => countDiagnosticsBySeverity(diagnostics?.issues));
  const substratePct = $derived.by(() => substrateProgressPercent(diagnostics?.substrateSum ?? null));
  const substrateLabel = $derived.by(() => substrateStatusLabel(diagnostics));
  const humusSummary = $derived.by(() => formatHumusComparison(diagnostics));
  const allVerified = $derived.by(() =>
    !!diagnostics &&
    counts.errors === 0 &&
    counts.warnings === 0 &&
    !diagnostics.smrDivergent &&
    !diagnostics.snrDivergent &&
    (diagnostics.substratePopulated === 0 || diagnostics.substrateValid)
  );
  const inputSignature = $derived.by(() => {
    const hdr = header ? JSON.stringify($state.snapshot(header)) : '';
    const hum = JSON.stringify($state.snapshot(humus));
    const min = JSON.stringify($state.snapshot(mineral));
    return `${contextId}|${plotNumber}|${hdr}|${hum}|${min}`;
  });

  $effect(() => {
    const sig = inputSignature;
    const hasHeader = !!header;
    const hasStored = !!(contextId && plotNumber);
    if (!sig || (!hasHeader && !hasStored)) {
      diagnostics = null;
      return;
    }
    const timer = setTimeout(() => {
      void evaluateCurrent();
    }, hasHeader ? 120 : 0);
    return () => clearTimeout(timer);
  });

  async function evaluateCurrent() {
    const reqGen = ++generation;
    const owner = contextId;
    error = '';
    busy = true;
    try {
      let raw: PlotDiagnosticsResult;
      if (header) {
        const headerSnap = $state.snapshot(header);
        const humusSnap = $state.snapshot(humus);
        const mineralSnap = $state.snapshot(mineral);
        raw = await port.evaluatePlotDiagnostics(headerSnap, humusSnap, mineralSnap);
      } else if (owner && plotNumber) {
        raw = await port.evaluateStoredPlotDiagnostics(owner, plotNumber);
      } else {
        busy = false;
        return;
      }
      if (reqGen !== generation || owner !== contextId) return;
      const validated = normalizeDiagnosticsWire(raw);
      if (reqGen !== generation || owner !== contextId) return;
      diagnostics = validated;
      if (validated.smrDivergent || validated.snrDivergent || validated.issues.some((i) => i.severity === 'error' || i.severity === 'warning')) {
        const sig = [
          validated.plotNumber,
          validated.smrDivergent ? `${validated.keyedSmr}:${validated.fieldSmr}` : '',
          validated.snrDivergent ? `${validated.keyedSnr}:${validated.fieldSnr}` : '',
          validated.issues.map((i) => i.code).join(','),
        ].join('|');
        if (sig !== lastNotifiedSignature) {
          lastNotifiedSignature = sig;
          const parts: string[] = [];
          if (validated.smrDivergent) {
            parts.push(`Keyed rSMR ${validated.keyedSmr} vs Field ${validated.fieldSmr || 'blank'}`);
          }
          if (validated.snrDivergent) {
            parts.push(`Keyed rSNR ${validated.keyedSnr} vs Field ${validated.fieldSnr || 'blank'}`);
          }
          if (validated.issues.length > 0) {
            parts.push(`${validated.issues.length} pedon/substrate finding(s)`);
          }
          if (typeof notifications !== 'undefined' && typeof notifications?.push === 'function') {
            notifications.push({
              severity: validated.issues.some((i) => i.severity === 'error') ? 'error' : 'warning',
              category: 'lmh25',
              source: `LMH25 · Plot ${validated.plotNumber}`,
              title: `LMH25 edatopic/pedon advisory for Plot ${validated.plotNumber}`,
              message: parts.join(' · '),
              toast: false,
            });
          }
        }
      }
    } catch (cause) {
      if (reqGen === generation) error = String(cause);
    } finally {
      if (reqGen === generation) busy = false;
    }
  }

  onDestroy(cancel);
</script>

<aside class="lmh25-bar" data-lmh25-diagnostics aria-label="LMH25 (2023) Edatopic and Pedon Rule Diagnostics">
  <div class="lmh25-summary-row">
    <div class="lmh25-brand">
      <span class="lmh25-tag">LMH25 (2023)</span>
      <strong>Pedon &amp; Edatopic Co-Pilot</strong>
    </div>

    {#if diagnostics}
      <div class="lmh25-chips">
        <span class="chip" class:verified={allVerified} class:divergent={!allVerified && (counts.errors > 0 || counts.warnings > 0)} data-lmh25-status-badge>
          {#if allVerified}
            <strong class="verified-flag" data-lmh25-verified-badge>LMH25 Verified</strong>
          {:else}
            <strong class="error-flag" data-lmh25-alert-badge>{counts.errors} Errors / {counts.warnings} Warnings</strong>
          {/if}
        </span>

        <span class="chip" class:divergent={diagnostics.smrDivergent} data-smr-badge>
          Keyed rSMR: <strong>{diagnostics.keyedSmr || 'N/A'}</strong>
          {#if diagnostics.fieldSmr}
            (Field: {diagnostics.fieldSmr})
          {/if}
          {#if diagnostics.smrDivergent}
            <strong class="alert-flag">Diverges &gt;=2</strong>
          {/if}
          {#if onApplyKeyedSMR && diagnostics.keyedSmrClass !== null}
            <button type="button" class="chip-action" onclick={() => onApplyKeyedSMR!(String(diagnostics!.keyedSmrClass))}>
              Apply {diagnostics.keyedSmrClass}
            </button>
          {/if}
        </span>

        <span class="chip" class:divergent={diagnostics.snrDivergent} data-snr-badge>
          Keyed rSNR: <strong>{diagnostics.keyedSnr || 'N/A'}</strong>
          {#if diagnostics.fieldSnr}
            (Field: {diagnostics.fieldSnr})
          {/if}
          {#if diagnostics.snrDivergent}
            <strong class="alert-flag">Diverges &gt;=2</strong>
          {/if}
          {#if onApplyKeyedSNR && diagnostics.keyedSnr}
            <button type="button" class="chip-action" onclick={() => onApplyKeyedSNR!(diagnostics!.keyedSnr.slice(0, 1))}>
              Apply {diagnostics.keyedSnr.slice(0, 1)}
            </button>
          {/if}
        </span>

        <span class="chip" data-humus-badge>
          Humus: <strong>{humusSummary}</strong>
          {#if onApplyHumusThickness && diagnostics.derivedHumusThickness !== null && (diagnostics.headerHumusThickness === null || (diagnostics.humusThicknessDiff !== null && Math.abs(diagnostics.humusThicknessDiff) > 0.05))}
            <button type="button" class="chip-action" onclick={() => onApplyHumusThickness!(diagnostics!.derivedHumusThickness!)}>
              Use {diagnostics.derivedHumusThickness} cm
            </button>
          {/if}
        </span>

        <span class="chip" class:divergent={!diagnostics.substrateValid && diagnostics.substratePopulated > 0} data-substrate-badge>
          Substrates: <strong>{substrateLabel}</strong>
          <span class="substrate-meter" role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={substratePct}>
            <span class="substrate-fill" class:invalid={!diagnostics.substrateValid} style={`width: ${substratePct}%`}></span>
          </span>
        </span>
      </div>
    {/if}

    <div class="lmh25-controls">
      <button type="button" class="bcgov-btn" disabled={busy || (!header && (!contextId || !plotNumber))} onclick={evaluateCurrent}>
        {busy ? 'Checking...' : 'Evaluate LMH25 Rules'}
      </button>
      {#if diagnostics}
        <button type="button" class="bcgov-btn-outline" onclick={() => (detailsOpen = !detailsOpen)}>
          {detailsOpen ? 'Hide Trace' : `Issues (${counts.errors + counts.warnings}) & Key Trace`}
        </button>
      {/if}
    </div>
  </div>

  {#if error}
    <p class="error" role="alert">{error}</p>
  {/if}

  {#if diagnostics && detailsOpen}
    <div class="lmh25-drawer">
      <div class="drawer-col">
        <h4>Pedon, Horizon &amp; Substrate Findings ({diagnostics.issues.length})</h4>
        {#if diagnostics.issues.length === 0}
          <p class="ok-note">All upland/wetland horizon depth signs, contiguity, von Post Table 2.23 bounds, and substrates pass LMH25 checks.</p>
        {:else}
          <ul class="issue-list">
            {#each diagnostics.issues as iss, idx (iss.code + ':' + idx)}
              <li class={`sev-${iss.severity}`}>
                <strong>[{iss.severity.toUpperCase()}] {iss.code}</strong>: {iss.message}
                <span class="ref-cite">({iss.lmh25Ref})</span>
              </li>
            {/each}
          </ul>
        {/if}
      </div>

      <div class="drawer-col">
        <h4>Keys 9.3, 9.4 (rSMR) &amp; 9.6 (rSNR) Decision Trace</h4>
        <ul class="trace-list">
          {#each [...diagnostics.smrTrace, ...diagnostics.snrTrace] as step, idx (step.key + ':' + idx)}
            <li>
              <span class="trace-key">Key {step.key}</span>
              <strong>{step.step}:</strong> {step.condition} -&gt; <strong>{step.outcome}</strong>
            </li>
          {/each}
        </ul>
      </div>
    </div>
  {/if}
</aside>

<style>
  .lmh25-bar { background: var(--vpro-surface-subtle); border: 1px solid var(--vpro-border); border-left: 5px solid var(--vpro-navy); border-radius: 4px; padding: 0.65rem 0.9rem; margin-bottom: 0.85rem; color: var(--vpro-ink); min-width: 0; }
  .lmh25-summary-row { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 0.65rem; }
  .lmh25-brand { display: inline-flex; align-items: center; flex-wrap: wrap; gap: 0.5rem; color: var(--vpro-navy); font-size: 0.88rem; }
  .lmh25-tag { background: var(--vpro-navy); color: var(--vpro-gold); padding: 0.15rem 0.45rem; border-radius: 3px; font-size: 0.72rem; font-weight: 700; letter-spacing: 0.04em; }
  .lmh25-chips { display: flex; flex-wrap: wrap; gap: 0.45rem; align-items: center; min-width: 0; font-variant-numeric: tabular-nums; }
  .chip { display: inline-flex; flex-wrap: wrap; align-items: center; gap: 0.35rem; background: var(--vpro-surface); border: 1px solid var(--vpro-border); border-radius: 4px; padding: 0.25rem 0.55rem; font-size: 0.8rem; color: var(--vpro-ink); max-width: 100%; }
  .chip.verified { border-color: var(--vpro-success); background: var(--vpro-surface); color: var(--vpro-forest); }
  .chip.divergent { background: var(--vpro-warning-bg); border-color: var(--vpro-warning-border); color: var(--vpro-warning-ink); border-left: 3px solid var(--vpro-error); }
  .alert-flag { background: var(--vpro-gold); color: var(--vpro-navy); padding: 0.05rem 0.35rem; border-radius: 3px; font-size: 0.72rem; }
  .error-flag { background: var(--vpro-error); color: var(--vpro-surface); padding: 0.05rem 0.35rem; border-radius: 3px; font-size: 0.72rem; }
  .verified-flag { background: var(--vpro-success); color: var(--vpro-surface); padding: 0.05rem 0.35rem; border-radius: 3px; font-size: 0.72rem; }
  .chip-action { background: var(--vpro-navy); color: var(--vpro-surface); border: 0; border-radius: 3px; padding: 0.15rem 0.45rem; font-size: 0.73rem; font-weight: 600; cursor: pointer; }
  .chip-action:hover { background: var(--vpro-navy-dark); }
  .substrate-meter { width: 56px; height: 8px; background: var(--vpro-border); border-radius: 4px; overflow: hidden; display: inline-block; }
  .substrate-fill { display: block; height: 100%; background: var(--vpro-forest); }
  .substrate-fill.invalid { background: var(--vpro-error); }
  .lmh25-controls { display: flex; flex-wrap: wrap; gap: 0.4rem; }
  .bcgov-btn { min-height: 2.25rem; background: var(--vpro-navy); color: var(--vpro-surface); border: 1px solid var(--vpro-navy); border-radius: 4px; padding: 0.35rem 0.7rem; font-size: 0.8rem; font-weight: 600; cursor: pointer; }
  .bcgov-btn:hover:not(:disabled) { background: var(--vpro-navy-dark); border-color: var(--vpro-navy-dark); }
  .bcgov-btn:disabled { opacity: 0.5; cursor: not-allowed; }
  .bcgov-btn-outline { min-height: 2.25rem; background: var(--vpro-surface); color: var(--vpro-navy); border: 1px solid var(--vpro-navy); border-radius: 4px; padding: 0.35rem 0.7rem; font-size: 0.8rem; font-weight: 600; cursor: pointer; }
  .bcgov-btn-outline:hover:not(:disabled) { background: var(--vpro-canvas); }
  .lmh25-drawer { margin-top: 0.75rem; padding-top: 0.75rem; border-top: 1px solid var(--vpro-border); display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 280px), 1fr)); gap: 1rem; font-size: 0.82rem; min-width: 0; }
  .lmh25-drawer h4 { margin: 0 0 0.45rem; color: var(--vpro-navy); font-size: 0.86rem; }
  .issue-list, .trace-list { margin: 0; padding-left: 1.1rem; display: grid; gap: 0.3rem; }
  .sev-error, .error { color: var(--vpro-error-ink); font-weight: 600; }
  .sev-warning { color: var(--vpro-warning-ink); }
  .sev-info { color: var(--vpro-info); }
  .ref-cite { color: var(--vpro-ink-muted); font-size: 0.76rem; }
  .trace-key { background: var(--vpro-navy-tint); border: 1px solid var(--vpro-info); color: var(--vpro-navy); padding: 0.05rem 0.35rem; border-radius: 3px; font-weight: 600; margin-right: 0.25rem; }
  .ok-note { color: var(--vpro-success-ink); margin: 0; font-weight: 600; }
  @media (pointer: coarse) {
    .bcgov-btn,
    .bcgov-btn-outline,
    .chip-action {
      min-height: 44px;
    }
  }
</style>
