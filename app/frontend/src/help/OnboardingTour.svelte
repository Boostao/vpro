<script lang="ts">
  import { onDestroy, tick, untrack } from 'svelte';
  import { CheckCircle2, ChevronLeft, ChevronRight, Compass, RotateCcw, ShieldCheck, X } from '@lucide/svelte';
  import { defaultHelpPort, type HelpBackendPort, type HelpTour } from './helpSystem';

  let {
    open = false,
    initialTourId = null,
    initialTours = [],
    activeProject = 'Sample',
    helpPort = defaultHelpPort,
    onnavigateview,
    onensurecontextopen,
    onresetsample,
    onclose,
  }: {
    open?: boolean;
    initialTourId?: string | null;
    initialTours?: HelpTour[];
    activeProject?: string;
    helpPort?: HelpBackendPort;
    onnavigateview: (viewName: string) => void;
    onensurecontextopen?: () => void;
    onresetsample?: () => Promise<void> | void;
    onclose: () => void;
  } = $props();

  let tours = $state.raw<HelpTour[]>(untrack(() => initialTours));
  let activeTourId = $state<string | null>(untrack(() => initialTourId));
  let stepIndex = $state(0);
  let targetRect = $state<{ top: number; left: number; width: number; height: number } | null>(null);
  let targetWaiting = $state(false);
  let viewportWidth = $state(typeof window !== 'undefined' ? window.innerWidth : 1280);
  let viewportHeight = $state(typeof window !== 'undefined' ? window.innerHeight : 800);
  let loading = $state(false);
  let error = $state('');
  let completedTourTitle = $state('');

  let loadGen = 0;
  let trackGen = 0;
  let observedEl: Element | null = null;
  let mutationObserver: MutationObserver | null = null;
  let resizeObserver: ResizeObserver | null = null;
  let retryTimer: ReturnType<typeof setTimeout> | null = null;
  let rafId = 0;
  let trackingActive = false;

  $effect(() => {
    const requestedTour = initialTourId;
    untrack(() => {
      if (requestedTour) {
        activeTourId = requestedTour;
        stepIndex = 0;
        completedTourTitle = '';
      }
    });
  });

  $effect(() => {
    if (!open) {
      untrack(() => stopTargetTracking());
      return;
    }
    untrack(() => {
      syncViewport();
      void loadTours();
    });
  });

  function syncViewport() {
    if (typeof window === 'undefined') return;
    viewportWidth = window.innerWidth;
    viewportHeight = window.innerHeight;
  }

  function stopTargetTracking() {
    trackingActive = false;
    observedEl = null;
    if (mutationObserver) {
      mutationObserver.disconnect();
      mutationObserver = null;
    }
    if (resizeObserver) {
      resizeObserver.disconnect();
      resizeObserver = null;
    }
    if (retryTimer !== null) {
      clearTimeout(retryTimer);
      retryTimer = null;
    }
    if (rafId && typeof cancelAnimationFrame === 'function') {
      cancelAnimationFrame(rafId);
      rafId = 0;
    }
    if (typeof window !== 'undefined') {
      window.removeEventListener('scroll', handleViewportMutation, true);
      window.removeEventListener('resize', handleViewportMutation);
    }
  }

  function handleViewportMutation() {
    syncViewport();
    const step = activeTour?.steps[stepIndex];
    if (!open || !step) return;
    if (rafId && typeof cancelAnimationFrame === 'function') return;
    const schedule = typeof requestAnimationFrame === 'function'
      ? requestAnimationFrame
      : (cb: () => void) => setTimeout(cb, 16) as unknown as number;
    rafId = schedule(() => {
      rafId = 0;
      const current = activeTour?.steps[stepIndex];
      if (!open || !current) return;
      measureResolvedElement(current.target, false);
    });
  }

  function openAncestorDetails(el: Element): boolean {
    let changed = false;
    let node: Element | null = el;
    while (node) {
      if (node.tagName === 'DETAILS' && !(node as HTMLDetailsElement).open) {
        (node as HTMLDetailsElement).open = true;
        changed = true;
      }
      node = node.parentElement;
    }
    return changed;
  }

  function rectsAlmostEqual(
    a: { top: number; left: number; width: number; height: number } | null,
    b: { top: number; left: number; width: number; height: number }
  ): boolean {
    if (!a) return false;
    return (
      Math.abs(a.top - b.top) < 0.5 &&
      Math.abs(a.left - b.left) < 0.5 &&
      Math.abs(a.width - b.width) < 0.5 &&
      Math.abs(a.height - b.height) < 0.5
    );
  }

  function isSelfTourMutation(records?: MutationRecord[]): boolean {
    if (!records || records.length === 0) return false;
    return records.every((rec) => {
      const target = rec.target as Element | null;
      const el = target && target.nodeType === 1 ? target : target?.parentElement;
      return !!el?.closest?.('[data-tour-overlay], [data-tour-spotlight-ring], [data-onboarding-tour-active], [data-onboarding-tour-catalog]');
    });
  }

  function measureResolvedElement(selector: string, allowScroll: boolean): boolean {
    if (typeof document === 'undefined' || !selector) {
      if (targetRect !== null) targetRect = null;
      return false;
    }
    try {
      const el = document.querySelector(selector);
      if (!el || typeof el.getBoundingClientRect !== 'function') {
        if (targetRect !== null) targetRect = null;
        return false;
      }
      const openedDetails = openAncestorDetails(el);
      if (el.closest?.('#project-context')) {
        onensurecontextopen?.();
      }
      if (observedEl !== el) {
        observedEl = el;
        if (resizeObserver) {
          resizeObserver.disconnect();
        } else if (typeof ResizeObserver === 'function') {
          resizeObserver = new ResizeObserver(() => handleViewportMutation());
        }
        resizeObserver?.observe(el);
      }
      if (allowScroll && typeof el.scrollIntoView === 'function') {
        el.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'nearest' });
      }
      const rect = el.getBoundingClientRect();
      if (rect.width <= 0 || rect.height <= 0 || openedDetails) {
        if (rect.width <= 0 || rect.height <= 0) {
          if (targetRect !== null) targetRect = null;
          return false;
        }
      }
      const vw = typeof window !== 'undefined' ? window.innerWidth : viewportWidth;
      const vh = typeof window !== 'undefined' ? window.innerHeight : viewportHeight;
      const left = Math.max(4, rect.left - 4);
      const right = Math.min(vw - 4, rect.right + 4);
      const top = Math.max(4, rect.top - 4);
      const maxH = Math.max(24, vh - top - 4);
      const nextRect = {
        top,
        left,
        width: Math.max(24, right - left),
        height: Math.min(rect.height + 8, maxH),
      };
      if (!rectsAlmostEqual(targetRect, nextRect)) {
        targetRect = nextRect;
      }
      if (targetWaiting) {
        targetWaiting = false;
      }
      return true;
    } catch {
      if (targetRect !== null) targetRect = null;
      return false;
    }
  }

  function disconnectMutationObserver() {
    if (mutationObserver) {
      mutationObserver.disconnect();
      mutationObserver = null;
    }
  }

  function beginTargetObservation(selector: string, expectedGen: number) {
    stopTargetTracking();
    if (typeof document === 'undefined' || !selector) return;

    trackingActive = true;
    let scrolledOnce = false;
    let attempts = 0;
    const maxAttempts = 50; // ~4s bounded retry loop for lazy {@await import} views

    if (typeof window !== 'undefined') {
      window.addEventListener('scroll', handleViewportMutation, { capture: true, passive: true });
      window.addEventListener('resize', handleViewportMutation, { passive: true });
    }

    const probe = () => {
      if (!trackingActive || expectedGen !== trackGen || !open) return;
      const resolved = measureResolvedElement(selector, !scrolledOnce);
      if (resolved) {
        scrolledOnce = true;
        targetWaiting = false;
        disconnectMutationObserver();
        // Re-sample once on the next animation frame after smooth scroll / details open settles
        if (attempts < 2 && typeof requestAnimationFrame === 'function') {
          attempts++;
          requestAnimationFrame(() => {
            if (trackingActive && expectedGen === trackGen && open) {
              measureResolvedElement(selector, false);
            }
          });
        }
        return;
      }
      attempts++;
      if (attempts >= maxAttempts) {
        targetWaiting = false;
        disconnectMutationObserver();
        return;
      }
      targetWaiting = true;
      retryTimer = setTimeout(() => {
        retryTimer = null;
        if (typeof requestAnimationFrame === 'function') {
          requestAnimationFrame(probe);
        } else {
          probe();
        }
      }, 80);
    };

    // Watch DOM only until lazy view/target resolves; resize/scroll listeners maintain position afterward.
    if (typeof MutationObserver === 'function' && document.body && !measureResolvedElement(selector, false)) {
      mutationObserver = new MutationObserver((records) => {
        if (!trackingActive || expectedGen !== trackGen || !open) return;
        if (isSelfTourMutation(records)) return;
        const hit = measureResolvedElement(selector, !scrolledOnce);
        if (hit) {
          scrolledOnce = true;
          targetWaiting = false;
          disconnectMutationObserver();
          if (retryTimer !== null) {
            clearTimeout(retryTimer);
            retryTimer = null;
          }
        }
      });
      mutationObserver.observe(document.body, { childList: true, subtree: true, attributes: true });
    }

    probe();
  }

  async function loadTours() {
    if (tours.length > 0) {
      if (activeTourId) await syncActiveStepSideEffects();
      return;
    }
    const gen = ++loadGen;
    loading = true;
    error = '';
    try {
      const bundle = await helpPort.getHelpBundle();
      if (gen !== loadGen) return;
      tours = bundle.tours ?? [];
      if (activeTourId) {
        await syncActiveStepSideEffects();
      }
    } catch (cause) {
      if (gen === loadGen) {
        error = `Guided tours could not load: ${String(cause)}`;
      }
    } finally {
      if (gen === loadGen) {
        loading = false;
      }
    }
  }

  const activeTour = $derived(tours.find((t) => t.id === activeTourId) ?? null);
  const activeStep = $derived(activeTour ? activeTour.steps[stepIndex] ?? null : null);

  function boxesOverlap(
    a: { top: number; left: number; width: number; height: number },
    b: { top: number; left: number; width: number; height: number },
    pad = 8
  ): boolean {
    return !(
      a.left + a.width + pad <= b.left ||
      b.left + b.width + pad <= a.left ||
      a.top + a.height + pad <= b.top ||
      b.top + b.height + pad <= a.top
    );
  }

  const dialogLayout = $derived.by(() => {
    const margin = viewportWidth < 640 ? 12 : 20;
    const cardHeightEst = 270;
    if (viewportWidth < 640) {
      const targetBottom = targetRect ? targetRect.top + targetRect.height : 0;
      const topFlip = !!targetRect && targetRect.top > viewportHeight * 0.45 && targetBottom > viewportHeight - cardHeightEst;
      return {
        placement: topFlip ? 'mobile-top' : 'mobile-bottom',
        style: topFlip
          ? `top:${margin}px;bottom:auto;left:${margin}px;right:${margin}px;width:auto;max-width:calc(100vw - ${margin * 2}px);`
          : `bottom:${margin}px;top:auto;left:${margin}px;right:${margin}px;width:auto;max-width:calc(100vw - ${margin * 2}px);`,
      };
    }

    const cardW = Math.min(448, Math.max(280, viewportWidth - margin * 2));
    const candidates: Array<{
      name: string;
      box: { top: number; left: number; width: number; height: number };
      style: string;
    }> = [
      {
        name: 'bottom-right',
        box: { top: viewportHeight - margin - cardHeightEst, left: viewportWidth - margin - cardW, width: cardW, height: cardHeightEst },
        style: `right:${margin}px;bottom:${margin}px;left:auto;top:auto;width:${cardW}px;max-width:calc(100vw - ${margin * 2}px);`,
      },
      {
        name: 'top-right',
        box: { top: margin + 56, left: viewportWidth - margin - cardW, width: cardW, height: cardHeightEst },
        style: `right:${margin}px;top:${margin + 56}px;left:auto;bottom:auto;width:${cardW}px;max-width:calc(100vw - ${margin * 2}px);`,
      },
      {
        name: 'bottom-left',
        box: { top: viewportHeight - margin - cardHeightEst, left: margin, width: cardW, height: cardHeightEst },
        style: `left:${margin}px;bottom:${margin}px;right:auto;top:auto;width:${cardW}px;max-width:calc(100vw - ${margin * 2}px);`,
      },
      {
        name: 'top-left',
        box: { top: margin + 56, left: margin, width: cardW, height: cardHeightEst },
        style: `left:${margin}px;top:${margin + 56}px;right:auto;bottom:auto;width:${cardW}px;max-width:calc(100vw - ${margin * 2}px);`,
      },
    ];

    if (targetRect) {
      const clear = candidates.find((c) => !boxesOverlap(c.box, targetRect!));
      if (clear) {
        return { placement: clear.name, style: clear.style };
      }
    }
    return { placement: candidates[0].name, style: candidates[0].style };
  });

  async function syncActiveStepSideEffects() {
    const stepGen = ++trackGen;
    const step = activeTour?.steps[stepIndex];
    if (!step) {
      stopTargetTracking();
      targetRect = null;
      targetWaiting = false;
      return;
    }
    syncViewport();
    targetRect = null;
    targetWaiting = true;
    if (step.target === '#project-context' || step.target.includes('project-context')) {
      onensurecontextopen?.();
    }
    if (step.view) {
      onnavigateview(step.view);
    }
    await tick();
    if (stepGen !== trackGen || !open) return;
    beginTargetObservation(step.target, stepGen);
  }

  async function startTour(tourId: string) {
    completedTourTitle = '';
    activeTourId = tourId;
    stepIndex = 0;
    await syncActiveStepSideEffects();
  }

  async function previousStep() {
    if (!activeTour || stepIndex <= 0) return;
    stepIndex -= 1;
    await syncActiveStepSideEffects();
  }

  async function nextStep() {
    if (!activeTour) return;
    if (stepIndex + 1 < activeTour.steps.length) {
      stepIndex += 1;
      await syncActiveStepSideEffects();
    } else {
      stopTargetTracking();
      completedTourTitle = activeTour.title;
      activeTourId = null;
      stepIndex = 0;
      targetRect = null;
      targetWaiting = false;
    }
  }

  function returnToCatalog() {
    stopTargetTracking();
    activeTourId = null;
    stepIndex = 0;
    targetRect = null;
    targetWaiting = false;
  }

  function handleKeydown(event: KeyboardEvent) {
    if (!open) return;
    if (event.key === 'Escape') {
      event.preventDefault();
      onclose();
    }
  }

  onDestroy(() => {
    loadGen++;
    trackGen++;
    stopTargetTracking();
  });
</script>

<svelte:window onkeydown={handleKeydown} />

{#if open}
  {#if activeTour && activeStep}
    <div data-tour-overlay class="contents">
      {#if targetRect}
        <div
          aria-hidden="true"
          data-tour-spotlight-ring
          class="pointer-events-none fixed z-40 rounded border-[3px] border-[#FCBA19] shadow-[0_0_0_9999px_rgba(0,25,51,0.38)] transition-all duration-150"
          style={`top:${targetRect.top}px;left:${targetRect.left}px;width:${targetRect.width}px;height:${targetRect.height}px;`}
        ></div>
      {/if}

      <div
        role="dialog"
      aria-modal="false"
      aria-labelledby="onboarding-tour-step-title"
      data-onboarding-tour-active={activeTour.id}
      data-tour-placement={dialogLayout.placement}
      class="fixed z-50 max-sm:inset-x-3 max-sm:bottom-3 rounded border border-[#D8D8D8] border-t-[4px] border-t-[#FCBA19] bg-white text-[#313132] shadow-2xl"
      style={dialogLayout.style}
    >
      <header class="flex items-center justify-between gap-2 bg-[#003366] px-4 py-2.5 text-white">
        <div class="min-w-0">
          <div class="truncate font-mono text-[11px] text-[#FCBA19]">
            {activeTour.title} · Step {stepIndex + 1} of {activeTour.steps.length}
          </div>
        </div>
        <button
          type="button"
          aria-label="Dismiss Guided Tour"
          data-tour-dismiss
          class="rounded p-1 text-white/90 hover:bg-white/15 focus-visible:outline-2 focus-visible:outline-[#FCBA19]"
          onclick={onclose}
        >
          <X size={15} />
        </button>
      </header>

      <div class="h-1.5 w-full bg-[#F2F2F2]">
        <div
          class="h-full bg-[#FCBA19] transition-all"
          style={`width:${Math.round(((stepIndex + 1) / activeTour.steps.length) * 100)}%`}
        ></div>
      </div>

      <div class="space-y-3 p-4 text-xs">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <h3 id="onboarding-tour-step-title" class="text-sm font-bold text-[#003366]">{activeStep.title}</h3>
          <span class="rounded bg-[#F2F2F2] px-2 py-0.5 font-mono text-[10px] text-[#474543]">
            View: {activeStep.view}
          </span>
        </div>

        <p class="leading-relaxed text-[#313132]">{activeStep.body}</p>

        {#if targetWaiting && !targetRect}
          <p role="status" data-tour-target-waiting class="font-mono text-[11px] text-[#1A5A96]">
            Synchronizing highlight target in view…
          </p>
        {/if}

        <div class="flex flex-wrap items-center justify-between gap-2 border-t border-[#D8D8D8] pt-3">
          <button
            type="button"
            class="rounded border border-[#D8D8D8] bg-white px-2.5 py-1.5 text-xs font-medium text-[#003366] hover:bg-[#F2F2F2]"
            onclick={returnToCatalog}
          >
            All 4 Tours
          </button>

          <div class="flex items-center gap-2">
            <button
              type="button"
              data-tour-back
              disabled={stepIndex === 0}
              class="inline-flex items-center gap-1 rounded border border-[#D8D8D8] bg-white px-2.5 py-1.5 text-xs font-semibold text-[#313132] hover:bg-[#F2F2F2] disabled:opacity-45"
              onclick={() => void previousStep()}
            >
              <ChevronLeft size={14} /> Back
            </button>
            <button
              type="button"
              data-tour-next
              class="inline-flex items-center gap-1 rounded bg-[#003366] px-3 py-1.5 text-xs font-semibold text-white hover:bg-[#002244]"
              onclick={() => void nextStep()}
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
    </div>
    </div>

  {:else}
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/50 p-3 sm:p-4" data-onboarding-tour-catalog>
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="onboarding-catalog-title"
        class="flex max-h-[88vh] w-full max-w-2xl flex-col overflow-hidden rounded border border-[#D8D8D8] bg-white text-[#313132] shadow-2xl"
      >
        <header class="flex items-center justify-between gap-3 border-b-[3px] border-b-[#FCBA19] bg-[#003366] px-5 py-3.5 text-white">
          <div class="flex items-center gap-2.5">
            <Compass size={18} class="shrink-0 text-[#FCBA19]" />
            <div>
              <div class="font-mono text-[11px] uppercase tracking-wider text-[#FCBA19]">
                Coming from VPro 64 · Non-Destructive Walkthroughs
              </div>
              <h2 id="onboarding-catalog-title" class="text-base font-semibold text-white">
                Interactive VPro 2.0 Guided Tours (4 Modules)
              </h2>
            </div>
          </div>
          <button
            type="button"
            aria-label="Close Guided Tours"
            class="rounded border border-white/30 bg-white/10 p-1.5 text-white hover:bg-white/20"
            onclick={onclose}
          >
            <X size={16} />
          </button>
        </header>

        <div class="space-y-4 overflow-y-auto p-5 text-xs">
          {#if error}
            <p role="alert" class="rounded border border-[#D8292F] bg-[#FBEAEA] p-2.5 text-[#D8292F]">{error}</p>
          {/if}
          {#if completedTourTitle}
            <div role="status" class="flex items-center gap-2 rounded border border-[#2E8540] bg-[#EBF5ED] p-3 text-[#1E5128]">
              <CheckCircle2 size={16} />
              <span>Completed <strong>{completedTourTitle}</strong>. Choose another walkthrough below or close to continue working.</span>
            </div>
          {/if}

          <div class="flex flex-wrap items-center justify-between gap-2 rounded border border-[#D8D8D8] bg-[#F2F2F2] p-3">
            <div class="flex items-center gap-2">
              <ShieldCheck size={16} class="shrink-0 text-[#2E8540]" />
              <span>
                Active project: <strong class="font-mono text-[#003366]">{activeProject}</strong>.
                Walkthroughs navigate read-only views safely without mutating user databases.
              </span>
            </div>
            {#if activeProject !== 'Sample' && onresetsample}
              <button
                type="button"
                data-tour-switch-sample
                class="inline-flex items-center gap-1 rounded border border-[#003366] bg-white px-2.5 py-1.5 text-xs font-semibold text-[#003366] hover:bg-[#EBF1F6]"
                onclick={() => void onresetsample()}
              >
                <RotateCcw size={12} /> Switch to Sample.db
              </button>
            {/if}
          </div>

          {#if loading}
            <p role="status" class="text-[#474543]">Loading guided tour definitions...</p>
          {:else}
            <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
              {#each tours as tour (tour.id)}
                <article
                  data-tour-card={tour.id}
                  class="flex flex-col justify-between rounded border border-[#D8D8D8] border-t-[3px] border-t-[#003366] bg-white p-3.5"
                >
                  <div class="space-y-1.5">
                    <div class="flex items-center justify-between gap-2">
                      <span class="rounded bg-[#F2F2F2] px-2 py-0.5 font-mono text-[11px] font-semibold text-[#003366]">
                        {tour.duration}
                      </span>
                      <span class="font-mono text-[11px] text-[#474543]">{tour.steps.length} steps</span>
                    </div>
                    <h3 class="text-sm font-bold text-[#003366]">{tour.title}</h3>
                    <p class="text-xs leading-relaxed text-[#474543]">{tour.description}</p>
                  </div>

                  <button
                    type="button"
                    data-start-tour={tour.id}
                    class="mt-3 inline-flex w-full items-center justify-center gap-1.5 rounded bg-[#003366] px-3 py-2 text-xs font-semibold text-white hover:bg-[#002244]"
                    onclick={() => void startTour(tour.id)}
                  >
                    Start Walkthrough <ChevronRight size={14} />
                  </button>
                </article>
              {/each}
            </div>
          {/if}
        </div>
      </div>
    </div>
  {/if}
{/if}
