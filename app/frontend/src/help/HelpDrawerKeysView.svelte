<script lang="ts">
  import { CheckCircle2, RotateCcw } from '@lucide/svelte';
  import type { COVER_COMPARISON_BLOCKS, DecisionKeyEvalState, HelpDecisionKey } from './helpSystem';

  let {
    decisionKeys,
    selectedKeyId,
    activeDecisionKey,
    isDichotomous,
    keyEval,
    currentKeyStepObj,
    coverComparisonBlocks,
    onselectkey,
    onanswerkey,
    onresetkey,
  }: {
    decisionKeys: HelpDecisionKey[];
    selectedKeyId: string;
    activeDecisionKey: HelpDecisionKey | null;
    isDichotomous: boolean;
    keyEval: DecisionKeyEvalState | null;
    currentKeyStepObj: HelpDecisionKey['steps'][number] | null;
    coverComparisonBlocks: typeof COVER_COMPARISON_BLOCKS;
    onselectkey: (id: string) => void;
    onanswerkey: (choice: 'yes' | 'no') => void;
    onresetkey: () => void;
  } = $props();
</script>

<div class="space-y-4" data-help-keys-panel>
  <div class="flex flex-wrap gap-1.5" role="group" aria-label="Select LMH25 Decision Key">
    {#each decisionKeys as dk (dk.id)}
      <button
        type="button"
        data-help-key-pill={dk.id}
        aria-pressed={selectedKeyId === dk.id}
        class="rounded border px-2.5 py-1.5 text-xs font-semibold {selectedKeyId === dk.id
          ? 'border-vpro-navy bg-vpro-navy text-white'
          : 'border-vpro-border bg-white text-vpro-navy hover:bg-vpro-canvas'}"
        onclick={() => onselectkey(dk.id)}
      >
        {dk.code}
      </button>
    {/each}
  </div>

  {#if activeDecisionKey}
    <section class="space-y-3 rounded border border-vpro-border border-t-[3px] border-t-vpro-gold bg-white p-3.5">
      <div class="flex items-start justify-between gap-2">
        <div>
          <div class="font-mono text-[11px] font-semibold text-vpro-navy">{activeDecisionKey.code}</div>
          <h3 class="text-sm font-bold text-vpro-ink">{activeDecisionKey.title}</h3>
        </div>
        <span class="shrink-0 rounded bg-vpro-canvas px-2 py-0.5 font-mono text-[11px] text-vpro-ink-secondary">
          LMH25 p. {activeDecisionKey.lmh25Page}
        </span>
      </div>

      {#if isDichotomous && keyEval}
        <div
          class="space-y-3 rounded border border-vpro-border bg-vpro-canvas p-3"
          data-decision-key-evaluator={activeDecisionKey.id}
        >
          <div class="flex items-center justify-between">
            <span class="font-mono text-[11px] font-bold uppercase text-vpro-navy">
              Interactive Yes / No Key Evaluator
            </span>
            <button
              type="button"
              data-decision-key-reset
              class="inline-flex items-center gap-1 rounded border border-vpro-border bg-white px-2 py-1 text-[11px] font-medium text-vpro-ink hover:bg-vpro-canvas"
              onclick={onresetkey}
            >
              <RotateCcw size={12} /> Reset Key
            </button>
          </div>

          {#if keyEval.completed && keyEval.conclusion}
            <div
              role="status"
              data-decision-key-conclusion
              class="rounded border border-vpro-success bg-vpro-success-bg p-3 text-vpro-forest"
            >
              <div class="flex items-center gap-1.5 text-[11px] font-bold uppercase">
                <CheckCircle2 size={14} /> Key Determination Reached
              </div>
              <div class="mt-1 font-mono text-sm font-bold text-vpro-navy">{keyEval.conclusion}</div>
            </div>
          {:else if currentKeyStepObj}
            <div class="rounded border border-vpro-border bg-white p-3">
              <div class="font-mono text-[11px] font-semibold text-vpro-navy">
                Step {currentKeyStepObj.step} of {activeDecisionKey.steps.length}
              </div>
              <p class="mt-1 text-xs font-medium text-vpro-ink">{currentKeyStepObj.prompt}</p>
              <div class="mt-3 flex flex-wrap gap-2">
                <button
                  type="button"
                  data-decision-key-yes
                  class="rounded bg-vpro-navy px-3.5 py-1.5 text-xs font-semibold text-white hover:bg-vpro-navy-dark"
                  onclick={() => onanswerkey('yes')}
                >
                  Yes ({currentKeyStepObj.yes})
                </button>
                <button
                  type="button"
                  data-decision-key-no
                  class="rounded border border-vpro-navy bg-white px-3.5 py-1.5 text-xs font-semibold text-vpro-navy hover:bg-vpro-surface-subtle"
                  onclick={() => onanswerkey('no')}
                >
                  No ({currentKeyStepObj.no})
                </button>
              </div>
            </div>
          {/if}

          {#if keyEval.history.length > 0}
            <ol class="space-y-1 text-[11px] text-vpro-ink-secondary" aria-label="Key evaluation path">
              {#each keyEval.history as item (item.step)}
                <li class="flex items-baseline justify-between gap-2 rounded bg-white px-2 py-1">
                  <span>Step {item.step}: <strong>{item.choice.toUpperCase()}</strong></span>
                  <span class="font-mono text-vpro-navy">{item.outcome}</span>
                </li>
              {/each}
            </ol>
          {/if}
        </div>
      {/if}

      {#if activeDecisionKey.id === 'key.cover_chart'}
        <div class="space-y-2.5" data-cover-comparison-chart>
          <p class="text-xs text-vpro-ink-secondary">
            Standard <strong>10 m × 10 m (100 m²)</strong> macroplot foliar crown-projection comparison plates
            calibrated to <em>LMH25 (2023)</em> Appendix p. 274:
          </p>
          <div class="grid grid-cols-2 gap-2.5 sm:grid-cols-3">
            {#each coverComparisonBlocks as block (block.percent)}
              <div class="rounded border border-vpro-border bg-vpro-canvas p-2" data-cover-plate={block.label}>
                <div class="mb-1 flex items-baseline justify-between">
                  <span class="font-mono text-xs font-bold text-vpro-navy">{block.label}</span>
                  <span class="font-mono text-[10px] text-vpro-ink-secondary">{block.areaM2}</span>
                </div>
                <svg
                  viewBox="0 0 100 100"
                  class="aspect-square w-full rounded border border-vpro-border-strong bg-white"
                  role="img"
                  aria-label={`${block.label} foliar cover reference square (${block.equivalentSquare})`}
                >
                  <line x1="50" y1="0" x2="50" y2="100" stroke="#cbd5e1" stroke-width="0.7" stroke-dasharray="2,2" />
                  <line x1="0" y1="50" x2="100" y2="50" stroke="#cbd5e1" stroke-width="0.7" stroke-dasharray="2,2" />
                  {#each block.patches as p}
                    <rect x={p.x} y={p.y} width={p.w} height={p.h} rx="1" fill="#003366" />
                  {/each}
                </svg>
                <div class="mt-1 font-mono text-[10px] text-vpro-ink-secondary">{block.equivalentSquare}</div>
              </div>
            {/each}
          </div>
        </div>
      {/if}

      <details class="rounded border border-vpro-border bg-white p-2.5">
        <summary class="cursor-pointer text-xs font-semibold text-vpro-navy">
          Full {activeDecisionKey.code} Step Table ({activeDecisionKey.steps.length} steps)
        </summary>
        <ol class="mt-2 space-y-2 border-t border-vpro-border pt-2">
          {#each activeDecisionKey.steps as step (step.step)}
            <li class="rounded bg-vpro-canvas p-2">
              <div class="font-mono text-[11px] font-bold text-vpro-navy">Step {step.step}</div>
              <div class="mt-0.5 text-vpro-ink">{step.prompt}</div>
              {#if step.yes || step.no}
                <div class="mt-1 flex flex-wrap gap-3 font-mono text-[11px]">
                  {#if step.yes}<span class="text-vpro-success">Yes → {step.yes}</span>{/if}
                  {#if step.no}<span class="text-vpro-ink-secondary">No → {step.no}</span>{/if}
                </div>
              {/if}
            </li>
          {/each}
        </ol>
      </details>
    </section>
  {/if}
</div>
