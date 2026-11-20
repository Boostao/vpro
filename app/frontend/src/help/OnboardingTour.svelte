<script lang="ts">
  import { onDestroy, tick, untrack } from 'svelte';
  import { Compass, X } from '@lucide/svelte';
  import ModalDialogTrap from '../shared/ModalDialogTrap.svelte';
  import { formatError } from '../shared/readRequests';
  import OnboardingTourCatalogBody from './OnboardingTourCatalogBody.svelte';
  import OnboardingTourStepBody from './OnboardingTourStepBody.svelte';
  import {
    computeTourDialogLayout,
    defaultHelpPort,
    formatTourViewLabel,
    type HelpBackendPort,
    type HelpTour,
    type TourBoxRect,
  } from './helpSystem';

  let {
    open = false,
    initialTourId = null,
    initialTours = [],
    activeProject = 'Sample',
    helpPort = defaultHelpPort,
    onnavigateview,
    onensurecontextopen,
    onrestorecontext,
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
    onrestorecontext?: () => void;
    onresetsample?: () => Promise<void> | void;
    onclose: () => void;
  } = $props();

  let tours = $state.raw<HelpTour[]>(untrack(() => initialTours));
  let activeTourId = $state<string | null>(untrack(() => initialTourId));
  let stepIndex = $state(0);
  let targetRect = $state<TourBoxRect | null>(null);
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
    const schedule =
      typeof requestAnimationFrame === 'function'
        ? requestAnimationFrame
        : (cb: () => void) => window.setTimeout(cb, 16);
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

  function rectsAlmostEqual(a: TourBoxRect | null, b: TourBoxRect): boolean {
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
      return !!el?.closest?.(
        '[data-tour-overlay], [data-tour-spotlight-ring], [data-onboarding-tour-active], [data-onboarding-tour-catalog]'
      );
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
        if (typeof window !== 'undefined' && typeof window.scrollTo === 'function' && window.scrollY > 0) {
          window.scrollTo(0, 0);
        }
      }
      const rect = el.getBoundingClientRect();
      if ((rect.width <= 0 || rect.height <= 0 || openedDetails) && (rect.width <= 0 || rect.height <= 0)) {
        if (targetRect !== null) targetRect = null;
        return false;
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
    const maxAttempts = 50;

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
        error = `Guided tours could not load: ${formatError(cause)}`;
      }
    } finally {
      if (gen === loadGen) {
        loading = false;
      }
    }
  }

  const activeTour = $derived(tours.find((t) => t.id === activeTourId) ?? null);
  const activeStep = $derived(activeTour ? (activeTour.steps[stepIndex] ?? null) : null);

  function boxesOverlap(a: TourBoxRect, b: TourBoxRect, pad = 8): boolean {
    return !(
      a.left + a.width + pad <= b.left ||
      b.left + b.width + pad <= a.left ||
      a.top + a.height + pad <= b.top ||
      b.top + b.height + pad <= a.top
    );
  }

  const dialogLayout = $derived(computeTourDialogLayout(viewportWidth, viewportHeight, targetRect, boxesOverlap));

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
    } else {
      onrestorecontext?.();
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
      onrestorecontext?.();
      completedTourTitle = activeTour.title;
      activeTourId = null;
      stepIndex = 0;
      targetRect = null;
      targetWaiting = false;
    }
  }

  function returnToCatalog() {
    stopTargetTracking();
    onrestorecontext?.();
    activeTourId = null;
    stepIndex = 0;
    targetRect = null;
    targetWaiting = false;
  }

  function dismissTour() {
    stopTargetTracking();
    onrestorecontext?.();
    onclose();
  }

  onDestroy(() => {
    loadGen++;
    trackGen++;
    stopTargetTracking();
    onrestorecontext?.();
  });
</script>

{#if open}
  {#if activeTour && activeStep}
    <div data-tour-overlay class="contents">
      {#if targetRect}
        <div
          aria-hidden="true"
          data-tour-spotlight-ring
          class="pointer-events-none fixed z-40 rounded border-[3px] border-vpro-gold shadow-[0_0_0_9999px_rgba(0,25,51,0.38)] transition-all duration-150"
          style={`top:${targetRect.top}px;left:${targetRect.left}px;width:${targetRect.width}px;height:${targetRect.height}px;`}
        ></div>
      {/if}

      <div
        role="dialog"
        aria-modal="false"
        aria-labelledby="onboarding-tour-step-title"
        data-onboarding-tour-active={activeTour.id}
        data-tour-placement={dialogLayout.placement}
        class="fixed z-50 rounded border border-vpro-border border-t-[4px] border-t-vpro-gold bg-white text-vpro-ink shadow-2xl max-sm:inset-x-3 max-sm:bottom-3"
        style={dialogLayout.style}
      >
        <ModalDialogTrap onEscape={dismissTour} trapFocus={true} initialFocusSelector="[data-tour-next]" />
        <header class="flex items-center justify-between gap-2 bg-vpro-navy px-4 py-2.5 text-white">
          <div class="min-w-0">
            <div class="truncate font-mono text-[11px] text-vpro-gold">
              {activeTour.title} · Step {stepIndex + 1} of {activeTour.steps.length}
            </div>
          </div>
          <button
            type="button"
            aria-label="Dismiss Guided Tour"
            data-tour-dismiss
            class="rounded p-1 text-white/90 hover:bg-white/15 focus-visible:outline-2 focus-visible:outline-vpro-gold"
            onclick={dismissTour}
          >
            <X size={15} />
          </button>
        </header>

        <OnboardingTourStepBody
          {activeTour}
          {activeStep}
          {stepIndex}
          viewLabel={formatTourViewLabel(activeStep.view)}
          showWaiting={targetWaiting && !targetRect}
          onreturntocatalog={returnToCatalog}
          onpreviousstep={() => void previousStep()}
          onnextstep={() => void nextStep()}
        />
      </div>
    </div>
  {:else}
    <div
      class="fixed inset-0 z-50 flex items-center justify-center bg-vpro-ink/50 p-3 sm:p-4"
      data-onboarding-tour-catalog
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="onboarding-catalog-title"
        class="flex max-h-[88vh] w-full max-w-2xl flex-col overflow-hidden rounded border border-vpro-border bg-white text-vpro-ink shadow-2xl"
      >
        <ModalDialogTrap onEscape={dismissTour} trapFocus={true} />
        <header
          class="flex items-center justify-between gap-3 border-b-[3px] border-b-vpro-gold bg-vpro-navy px-5 py-3.5 text-white"
        >
          <div class="flex items-center gap-2.5">
            <Compass size={18} class="shrink-0 text-vpro-gold" />
            <div>
              <div class="font-mono text-[11px] uppercase tracking-wider text-vpro-gold">
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
            onclick={dismissTour}
          >
            <X size={16} />
          </button>
        </header>

        <OnboardingTourCatalogBody
          {tours}
          {activeProject}
          {loading}
          {error}
          {completedTourTitle}
          {onresetsample}
          onstarttour={(id) => void startTour(id)}
        />
      </div>
    </div>
  {/if}
{/if}
