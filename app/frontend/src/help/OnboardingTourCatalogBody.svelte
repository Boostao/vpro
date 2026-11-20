<script lang="ts">
  import { CheckCircle2, ChevronRight, RotateCcw, ShieldCheck } from '@lucide/svelte';
  import type { HelpTour } from './helpSystem';

  let {
    tours,
    activeProject,
    loading,
    error,
    completedTourTitle,
    onresetsample,
    onstarttour,
  }: {
    tours: HelpTour[];
    activeProject: string;
    loading: boolean;
    error: string;
    completedTourTitle: string;
    onresetsample?: () => Promise<void> | void;
    onstarttour: (tourId: string) => void;
  } = $props();
</script>

<div class="space-y-4 overflow-y-auto p-5 text-xs">
  {#if error}
    <p role="alert" class="rounded border border-vpro-error bg-vpro-error-bg p-2.5 text-vpro-error">{error}</p>
  {/if}
  {#if completedTourTitle}
    <div
      role="status"
      class="flex items-center gap-2 rounded border border-vpro-success bg-vpro-success-bg p-3 text-vpro-forest"
    >
      <CheckCircle2 size={16} />
      <span>
        Completed <strong>{completedTourTitle}</strong>. Choose another walkthrough below or close to continue working.
      </span>
    </div>
  {/if}

  <div class="flex flex-wrap items-center justify-between gap-2 rounded border border-vpro-border bg-vpro-canvas p-3">
    <div class="flex items-center gap-2">
      <ShieldCheck size={16} class="shrink-0 text-vpro-success" />
      <span>
        Active project: <strong class="font-mono text-vpro-navy">{activeProject}</strong>. Walkthroughs navigate
        read-only views safely without changing user databases.
      </span>
    </div>
    {#if activeProject !== 'Sample' && onresetsample}
      <button
        type="button"
        data-tour-switch-sample
        class="inline-flex items-center gap-1 rounded border border-vpro-navy bg-white px-2.5 py-1.5 text-xs font-semibold text-vpro-navy hover:bg-vpro-navy-tint"
        onclick={() => void onresetsample()}
      >
        <RotateCcw size={12} /> Switch to Sample
      </button>
    {/if}
  </div>

  {#if loading}
    <p role="status" class="text-vpro-ink-secondary">Loading guided tour definitions...</p>
  {:else}
    <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
      {#each tours as tour (tour.id)}
        <article
          data-tour-card={tour.id}
          class="flex flex-col justify-between rounded border border-vpro-border border-t-[3px] border-t-vpro-navy bg-white p-3.5"
        >
          <div class="space-y-1.5">
            <div class="flex items-center justify-between gap-2">
              <span class="rounded bg-vpro-canvas px-2 py-0.5 font-mono text-[11px] font-semibold text-vpro-navy">
                {tour.duration}
              </span>
              <span class="font-mono text-[11px] text-vpro-ink-secondary">{tour.steps.length} steps</span>
            </div>
            <h3 class="text-sm font-bold text-vpro-navy">{tour.title}</h3>
            <p class="text-xs leading-relaxed text-vpro-ink-secondary">{tour.description}</p>
          </div>

          <button
            type="button"
            data-start-tour={tour.id}
            class="mt-3 inline-flex w-full items-center justify-center gap-1.5 rounded bg-vpro-navy px-3 py-2 text-xs font-semibold text-white hover:bg-vpro-navy-dark"
            onclick={() => onstarttour(tour.id)}
          >
            Start Walkthrough <ChevronRight size={14} />
          </button>
        </article>
      {/each}
    </div>
  {/if}
</div>
