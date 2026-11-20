<script lang="ts">
  import { CheckCircle2, ChevronLeft, ChevronRight } from '@lucide/svelte';
  import type { HelpTour } from './helpSystem';

  let {
    activeTour,
    activeStep,
    stepIndex,
    viewLabel,
    showWaiting,
    onreturntocatalog,
    onpreviousstep,
    onnextstep,
  }: {
    activeTour: HelpTour;
    activeStep: HelpTour['steps'][number];
    stepIndex: number;
    viewLabel: string;
    showWaiting: boolean;
    onreturntocatalog: () => void;
    onpreviousstep: () => void;
    onnextstep: () => void;
  } = $props();
</script>

<div class="h-1.5 w-full bg-vpro-canvas">
  <div
    class="h-full bg-vpro-gold transition-all"
    style={`width:${Math.round(((stepIndex + 1) / activeTour.steps.length) * 100)}%`}
  ></div>
</div>

<div class="space-y-3 p-4 text-xs">
  <div class="flex flex-wrap items-center justify-between gap-2">
    <h3 id="onboarding-tour-step-title" class="text-sm font-bold text-vpro-navy">{activeStep.title}</h3>
    <span class="rounded bg-vpro-canvas px-2 py-0.5 text-[11px] font-medium text-vpro-ink-secondary">
      {viewLabel}
    </span>
  </div>

  <p class="leading-relaxed text-vpro-ink">{activeStep.body}</p>

  {#if showWaiting}
    <p role="status" data-tour-target-waiting class="font-mono text-[11px] text-vpro-info">
      Scrolling to highlighted panel…
    </p>
  {/if}

  <div class="flex flex-wrap items-center justify-between gap-2 border-t border-vpro-border pt-3">
    <button
      type="button"
      class="rounded border border-vpro-border bg-white px-2.5 py-1.5 text-xs font-medium text-vpro-navy hover:bg-vpro-canvas"
      onclick={onreturntocatalog}
    >
      All 4 Tours
    </button>

    <div class="flex items-center gap-2">
      <button
        type="button"
        data-tour-back
        disabled={stepIndex === 0}
        class="inline-flex items-center gap-1 rounded border border-vpro-border bg-white px-2.5 py-1.5 text-xs font-semibold text-vpro-ink hover:bg-vpro-canvas disabled:opacity-45"
        onclick={onpreviousstep}
      >
        <ChevronLeft size={14} /> Back
      </button>
      <button
        type="button"
        data-tour-next
        class="inline-flex items-center gap-1 rounded bg-vpro-navy px-3 py-1.5 text-xs font-semibold text-white hover:bg-vpro-navy-dark"
        onclick={onnextstep}
      >
        {#if stepIndex + 1 < activeTour.steps.length}
          Next <ChevronRight size={14} />
        {:else}
          Finish Tour <CheckCircle2 size={14} />
        {/if}
      </button>
    </div>
  </div>
</div>
