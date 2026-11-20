<script lang="ts">
  import { onDestroy, onMount, untrack } from 'svelte';
  import { ReadRequests, formatError } from '../shared/readRequests';
  import SiteUnitExclusionUnitList from './SiteUnitExclusionUnitList.svelte';
  import {
    createDefaultBreakpointOptions,
    createDefaultSiteUnitExclusionRules,
    defaultSiteUnitExclusionPort,
    type ExclusionMatchMode,
    type HierarchyBreakpointOptions,
    type LongVegetationExclusionPreview,
    type SiteUnitExclusionBackendPort,
    type SiteUnitExclusionPreview,
    type SiteUnitExclusionRule,
    type SummaryVegetationExclusionPreview,
  } from './siteUnitExclusionFilter';

  interface Props {
    contextId: string;
    su?: string;
    hierarchy?: string;
    reportMode?: 'summary' | 'long';
    average?: number;
    display?: number;
    showClass?: number;
    groupAndOrder?: number;
    initialRules?: SiteUnitExclusionRule[];
    initialUseBreakpoints?: boolean;
    port?: SiteUnitExclusionBackendPort;
    onBusyChange?: (busy: boolean) => void;
    onRulesChange?: (
      rules: SiteUnitExclusionRule[],
      useHierarchyBreakpoints: boolean,
      breakpointOptions: HierarchyBreakpointOptions
    ) => void;
    onSummaryPreview?: (result: SummaryVegetationExclusionPreview) => void;
    onLongPreview?: (result: LongVegetationExclusionPreview) => void;
  }

  let {
    contextId,
    su = 'None',
    hierarchy = 'None',
    reportMode = 'summary',
    average = 1,
    display = 6,
    showClass = 0,
    groupAndOrder = 11,
    initialRules,
    initialUseBreakpoints = false,
    port = defaultSiteUnitExclusionPort,
    onBusyChange,
    onRulesChange,
    onSummaryPreview,
    onLongPreview,
  }: Props = $props();

  const reads = new ReadRequests();

  let rules = $state<SiteUnitExclusionRule[]>(
    untrack(() =>
      initialRules && initialRules.length > 0
        ? initialRules.map((r) => ({ ...r }))
        : createDefaultSiteUnitExclusionRules()
    )
  );
  let useHierarchyBreakpoints = $state<boolean>(untrack(() => initialUseBreakpoints));
  let breakpointOptions = $state<HierarchyBreakpointOptions>(createDefaultBreakpointOptions());

  let newPattern = $state('');
  let newMatchMode = $state<ExclusionMatchMode>('auto');

  let preview = $state.raw<SiteUnitExclusionPreview | null>(null);
  let busy = $state(false);
  let errorMessage = $state('');
  let generation = 0;

  $effect(() => {
    onBusyChange?.(busy);
  });

  function dispatchExclusionEvent(
    extra: {
      summaryPreview?: SummaryVegetationExclusionPreview;
      longPreview?: LongVegetationExclusionPreview;
    } = {}
  ) {
    if (typeof window === 'undefined' || typeof CustomEvent === 'undefined') return;
    window.dispatchEvent(
      new CustomEvent('vpro:site-unit-exclusion-update', {
        detail: {
          reportMode,
          rules: $state.snapshot(rules),
          useHierarchyBreakpoints,
          breakpointOptions: $state.snapshot(breakpointOptions),
          ...extra,
        },
      })
    );
  }

  function emitChange() {
    onRulesChange?.($state.snapshot(rules), useHierarchyBreakpoints, $state.snapshot(breakpointOptions));
    dispatchExclusionEvent();
  }

  async function refreshExclusionPreview() {
    if (!contextId || !su || su === 'None') {
      preview = null;
      return;
    }
    generation++;
    const reqGen = generation;
    reads.cancelAll();
    busy = true;
    errorMessage = '';
    try {
      const effectiveBreak = useHierarchyBreakpoints && hierarchy !== 'None' && hierarchy !== '';
      const res = await reads.track(
        port.previewExclusions(contextId, {
          rules: $state.snapshot(rules),
          useDefaultPresets: false,
          useHierarchyBreakpoints: effectiveBreak,
          breakpointOptions: $state.snapshot(breakpointOptions),
        })
      );
      if (reqGen !== generation) return;
      preview = res;
    } catch (err) {
      if (reqGen === generation) errorMessage = formatError(err);
    } finally {
      if (reqGen === generation) busy = false;
    }
  }

  async function runFilteredReportPreview() {
    if (!contextId || !su || su === 'None' || busy) return;
    generation++;
    const reqGen = generation;
    reads.cancelAll();
    busy = true;
    errorMessage = '';
    try {
      const effectiveBreak = useHierarchyBreakpoints && hierarchy !== 'None' && hierarchy !== '';
      if (reportMode === 'summary') {
        const res = await reads.track(
          port.previewSummaryWithExclusions(contextId, {
            average,
            display,
            showClass,
            groupAndOrder,
            rules: $state.snapshot(rules),
            useDefaultPresets: false,
            useHierarchyBreakpoints: effectiveBreak,
            breakpointOptions: $state.snapshot(breakpointOptions),
          })
        );
        if (reqGen !== generation) return;
        preview = {
          contextId,
          project: '',
          su,
          hierarchy,
          exclusions: res.exclusions,
          breakpoints: res.breakpoints,
        };
        onSummaryPreview?.(res);
        dispatchExclusionEvent({ summaryPreview: res });
      } else {
        const res = await reads.track(
          port.previewLongWithExclusions(contextId, {
            rules: $state.snapshot(rules),
            useDefaultPresets: false,
            useHierarchyBreakpoints: effectiveBreak,
            breakpointOptions: $state.snapshot(breakpointOptions),
          })
        );
        if (reqGen !== generation) return;
        preview = {
          contextId,
          project: '',
          su,
          hierarchy,
          exclusions: res.exclusions,
          breakpoints: res.breakpoints,
        };
        onLongPreview?.(res);
        dispatchExclusionEvent({ longPreview: res });
      }
    } catch (err) {
      if (reqGen === generation) errorMessage = formatError(err);
    } finally {
      if (reqGen === generation) busy = false;
    }
  }

  function addRule() {
    const trimmed = newPattern.trim();
    if (!trimmed) return;
    if (rules.some((r) => r.pattern.toLowerCase() === trimmed.toLowerCase() && r.matchMode === newMatchMode)) {
      newPattern = '';
      return;
    }
    rules = [...rules, { pattern: trimmed, matchMode: newMatchMode, enabled: true }];
    newPattern = '';
    emitChange();
    void refreshExclusionPreview();
  }

  function removeRule(idx: number) {
    rules = rules.filter((_, i) => i !== idx);
    emitChange();
    void refreshExclusionPreview();
  }

  function toggleRule(idx: number) {
    rules = rules.map((r, i) => (i === idx ? { ...r, enabled: !r.enabled } : r));
    emitChange();
    void refreshExclusionPreview();
  }

  function resetPresets() {
    rules = createDefaultSiteUnitExclusionRules();
    emitChange();
    void refreshExclusionPreview();
  }

  onMount(() => {
    if (contextId && su && su !== 'None') {
      void refreshExclusionPreview();
    }
  });

  onDestroy(() => {
    generation++;
    reads.cancelAll();
    onBusyChange?.(false);
  });
</script>

<section class="vpro-su-exclusions" aria-label="SiteUnit Exclusion Filters and Hierarchy Breakpoints">
  <header class="vpro-sux-header">
    <div>
      <p class="vpro-sux-eyebrow">SITE UNIT FILTERING &amp; DYNAMIC BREAKPOINTS</p>
      <h3 class="vpro-sux-title">
        SiteUnit Exclusions (.support / .poor / .nudum)
        {#if reportMode === 'summary'}&amp; '~' Hierarchy Rollup{/if}
      </h3>
    </div>

    <div class="vpro-sux-actions">
      <button type="button" class="vpro-btn-secondary" disabled={busy} onclick={resetPresets}>
        Reset BEC Defaults
      </button>
      <button
        type="button"
        class="vpro-btn-secondary"
        disabled={busy || !su || su === 'None'}
        onclick={refreshExclusionPreview}
      >
        Check Units
      </button>
      <button
        type="button"
        class="vpro-btn-primary"
        disabled={busy || !su || su === 'None'}
        onclick={runFilteredReportPreview}
      >
        {busy ? 'Computing...' : reportMode === 'summary' ? 'Preview Summary Vegetation' : 'Preview Long Vegetation'}
      </button>
    </div>
  </header>

  {#if errorMessage}
    <p role="alert" class="vpro-sux-alert">{errorMessage}</p>
  {/if}

  <SiteUnitExclusionUnitList
    {rules}
    bind:newPattern
    bind:newMatchMode
    {preview}
    onToggleRule={toggleRule}
    onRemoveRule={removeRule}
    onAddRule={addRule}
  >
    <div class="vpro-sux-breakpoints">
      <label class="vpro-sux-check">
        <input
          type="checkbox"
          bind:checked={useHierarchyBreakpoints}
          disabled={!hierarchy || hierarchy === 'None'}
          onchange={() => {
            emitChange();
            void refreshExclusionPreview();
          }}
        />
        <span>
          Roll up descendant Site Units under <code>~Branch</code> Hierarchy Breakpoints
          {#if !hierarchy || hierarchy === 'None'}
            <em>(Select an active Hierarchy in the sidebar to enable)</em>
          {:else}
            (Active Hierarchy: <strong>{hierarchy}</strong>)
          {/if}
        </span>
      </label>

      {#if useHierarchyBreakpoints && hierarchy && hierarchy !== 'None'}
        <div class="vpro-sux-bp-opts">
          <label>
            <span>Nested '~' Breakpoint Policy</span>
            <select
              bind:value={breakpointOptions.breakpointPolicy}
              onchange={() => {
                emitChange();
                void refreshExclusionPreview();
              }}
            >
              <option value="lowest">Lowest '~' Ancestor (Nearest Branch)</option>
              <option value="highest">Highest '~' Ancestor (Top Branch)</option>
            </select>
          </label>
          <label>
            <span>Units Without '~' Ancestor</span>
            <select
              bind:value={breakpointOptions.unbrokenUnitPolicy}
              onchange={() => {
                emitChange();
                void refreshExclusionPreview();
              }}
            >
              <option value="keep_original">Keep Original SiteUnit</option>
              <option value="exclude_unbroken">Exclude Unbroken Units</option>
            </select>
          </label>
          <label class="vpro-sux-check">
            <input
              type="checkbox"
              bind:checked={breakpointOptions.stripTildePrefix}
              onchange={() => {
                emitChange();
                void refreshExclusionPreview();
              }}
            />
            <span>Strip '~' prefix in column header</span>
          </label>
        </div>
      {/if}
    </div>
  </SiteUnitExclusionUnitList>
</section>

<style>
  .vpro-su-exclusions {
    display: flex;
    flex-direction: column;
    gap: 0.65rem;
    background: var(--vpro-canvas);
    border: 1px solid var(--vpro-border);
    border-left: 4px solid var(--vpro-navy);
    border-radius: 4px;
    padding: 0.85rem 1rem;
    min-width: 0;
    color: var(--vpro-ink);
  }
  .vpro-sux-header {
    display: flex;
    flex-wrap: wrap;
    justify-content: space-between;
    align-items: center;
    gap: 0.5rem;
  }
  .vpro-sux-eyebrow {
    margin: 0;
    font-size: 0.68rem;
    font-weight: 700;
    letter-spacing: 0.08em;
    color: var(--vpro-navy);
  }
  .vpro-sux-title {
    margin: 0.1rem 0 0;
    font-size: 0.96rem;
    font-weight: 700;
    color: var(--vpro-navy);
  }
  .vpro-sux-actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.4rem;
  }
  .vpro-sux-bp-opts {
    display: flex;
    flex-wrap: wrap;
    align-items: flex-end;
    gap: 0.5rem;
  }
  .vpro-sux-bp-opts label {
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
    font-size: 0.76rem;
    font-weight: 600;
    color: var(--vpro-navy);
  }
  .vpro-sux-bp-opts select {
    min-height: 30px;
    padding: 0.2rem 0.45rem;
    border: 1px solid var(--vpro-border);
    border-radius: 3px;
    font-size: 0.8rem;
    background: var(--vpro-surface);
    color: var(--vpro-ink);
  }
  .vpro-sux-breakpoints {
    border-top: 1px solid var(--vpro-border);
    padding-top: 0.5rem;
    display: grid;
    gap: 0.45rem;
  }
  .vpro-sux-check {
    display: inline-flex !important;
    flex-direction: row !important;
    align-items: center;
    gap: 0.4rem !important;
    font-size: 0.8rem;
    color: var(--vpro-ink);
  }
  .vpro-sux-alert {
    margin: 0;
    padding: 0.45rem 0.7rem;
    background: rgba(216, 41, 47, 0.08);
    border-left: 4px solid var(--vpro-error);
    color: var(--vpro-error);
    font-size: 0.8rem;
  }
  .vpro-btn-primary {
    min-height: 32px;
    padding: 0.3rem 0.75rem;
    background: var(--vpro-navy);
    color: var(--vpro-surface);
    border: 1px solid var(--vpro-navy);
    border-bottom: 2px solid var(--vpro-gold);
    border-radius: 4px;
    font-size: 0.8rem;
    font-weight: 600;
  }
  .vpro-btn-secondary {
    min-height: 32px;
    padding: 0.3rem 0.65rem;
    background: var(--vpro-surface);
    color: var(--vpro-navy);
    border: 1px solid var(--vpro-navy);
    border-radius: 4px;
    font-size: 0.8rem;
  }
</style>
