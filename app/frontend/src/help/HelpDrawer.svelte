<script lang="ts">
  import { untrack } from 'svelte';
  import { BookOpen, Compass, Scale, Search, SlidersHorizontal, X } from '@lucide/svelte';
  import { formatError } from '../shared/readRequests';
  import HelpDrawerKeysView from './HelpDrawerKeysView.svelte';
  import HelpDrawerSearchResults from './HelpDrawerSearchResults.svelte';
  import HelpDrawerTopicView from './HelpDrawerTopicView.svelte';
  import {
    COVER_COMPARISON_BLOCKS,
    answerDecisionKeyStep,
    createDecisionKeyState,
    defaultHelpPort,
    isDichotomousDecisionKey,
    type DecisionKeyEvalState,
    type HelpBackendPort,
    type HelpBundle,
    type HelpDecisionKey,
    type HelpDrawerTab,
    type HelpGuide,
    type HelpLookupResult,
    type HelpSearchHit,
  } from './helpSystem';

  let {
    open = false,
    topicId = 'site.plot_number',
    initialTab = 'inspector',
    helpPort = defaultHelpPort,
    onclose,
    onstarttour,
  }: {
    open?: boolean;
    topicId?: string;
    initialTab?: HelpDrawerTab;
    helpPort?: HelpBackendPort;
    onclose: () => void;
    onstarttour?: (tourId?: string) => void;
  } = $props();

  let activeTab = $state<HelpDrawerTab>(untrack(() => initialTab));
  let bundle = $state.raw<HelpBundle | null>(null);
  let lookup = $state.raw<HelpLookupResult | null>(null);
  let selectedFieldId = $state(untrack(() => topicId));
  let selectedKeyId = $state('key.rsmr_9_4');
  let selectedGuideId = $state('migrating-from-vpro64');
  let keyEval = $state.raw<DecisionKeyEvalState | null>(null);

  let searchQuery = $state('');
  let searchHits = $state.raw<HelpSearchHit[]>([]);
  let searchBusy = $state(false);
  let loading = $state(false);
  let error = $state('');

  let loadGeneration = 0;
  let lookupGeneration = 0;
  let searchGeneration = 0;

  $effect(() => {
    const incomingTab = initialTab;
    untrack(() => {
      activeTab = incomingTab;
    });
  });

  $effect(() => {
    if (!open) return;
    const requestedTopic = topicId;
    untrack(() => {
      void ensureBundleAndLookup(requestedTopic);
    });
  });

  async function ensureBundleAndLookup(targetTopic: string) {
    const gen = ++loadGeneration;
    loading = true;
    error = '';
    try {
      let currentBundle = bundle;
      if (!currentBundle) {
        currentBundle = await helpPort.getHelpBundle();
        if (gen !== loadGeneration) return;
        bundle = currentBundle;
        if (currentBundle.guides.length > 0 && !currentBundle.guides.some((g) => g.id === selectedGuideId)) {
          selectedGuideId = currentBundle.guides[0].id;
        }
      }
      await loadTopic(targetTopic || 'site.plot_number');
    } catch (cause) {
      if (gen === loadGeneration) {
        error = `Offline LMH25 help failed to load: ${formatError(cause)}`;
      }
    } finally {
      if (gen === loadGeneration) {
        loading = false;
      }
    }
  }

  async function loadTopic(helpId: string) {
    const gen = ++lookupGeneration;
    error = '';
    try {
      const resolved = await helpPort.lookupHelpTopic(helpId);
      if (gen !== lookupGeneration) return;
      lookup = resolved;
      if (resolved.field) {
        selectedFieldId = resolved.field.id;
      }
      if (resolved.decisionKey) {
        selectedKeyId = resolved.decisionKey.id;
        initKeyEvaluator(resolved.decisionKey);
      } else if (bundle && !keyEval) {
        const defaultKey = bundle.decisionKeys.find((k) => k.id === selectedKeyId) ?? bundle.decisionKeys[0];
        if (defaultKey) initKeyEvaluator(defaultKey);
      }
    } catch (cause) {
      if (gen === lookupGeneration) {
        error = `Help topic lookup failed: ${formatError(cause)}`;
      }
    }
  }

  function initKeyEvaluator(key: HelpDecisionKey) {
    keyEval = isDichotomousDecisionKey(key) ? createDecisionKeyState(key) : null;
  }

  function selectDecisionKey(id: string) {
    selectedKeyId = id;
    const found = bundle?.decisionKeys.find((k) => k.id === id);
    if (found) {
      initKeyEvaluator(found);
    }
  }

  function answerKey(choice: 'yes' | 'no') {
    const activeKey = bundle?.decisionKeys.find((k) => k.id === selectedKeyId);
    if (!activeKey || !keyEval) return;
    keyEval = answerDecisionKeyStep(activeKey, keyEval, choice);
  }

  function resetKey() {
    const activeKey = bundle?.decisionKeys.find((k) => k.id === selectedKeyId);
    if (!activeKey) return;
    initKeyEvaluator(activeKey);
  }

  async function runSearch(query: string) {
    searchQuery = query;
    const trimmed = query.trim();
    const gen = ++searchGeneration;
    if (!trimmed) {
      searchHits = [];
      searchBusy = false;
      return;
    }
    searchBusy = true;
    try {
      const hits = await helpPort.searchHelp(trimmed);
      if (gen !== searchGeneration) return;
      searchHits = hits ?? [];
    } catch (cause) {
      if (gen === searchGeneration) {
        error = `Offline search failed: ${formatError(cause)}`;
      }
    } finally {
      if (gen === searchGeneration) {
        searchBusy = false;
      }
    }
  }

  function openSearchHit(hit: HelpSearchHit) {
    searchQuery = '';
    searchHits = [];
    if (hit.kind === 'field') {
      activeTab = 'inspector';
      void loadTopic(hit.id);
    } else if (hit.kind === 'key') {
      activeTab = 'keys';
      selectDecisionKey(hit.id);
    } else if (hit.kind === 'guide') {
      activeTab = 'guides';
      selectedGuideId = hit.id;
    } else if (hit.kind === 'tour') {
      onstarttour?.(hit.id);
    }
  }

  function openGuide(guide: HelpGuide) {
    selectedGuideId = guide.id;
    activeTab = 'guides';
  }

  const activeDecisionKey = $derived(
    bundle?.decisionKeys.find((k) => k.id === selectedKeyId) ?? lookup?.decisionKey ?? null
  );
  const currentKeyStepObj = $derived.by(() => {
    const activeKey = activeDecisionKey;
    const evalState = keyEval;
    if (!activeKey || !evalState) return null;
    return activeKey.steps.find((s) => s.step === evalState.currentStep) ?? null;
  });
  const activeGuide = $derived(bundle?.guides.find((g) => g.id === selectedGuideId) ?? bundle?.guides[0] ?? null);
  const groupedFields = $derived.by(() => {
    const groups = new Map<string, HelpBundle['fields']>();
    for (const field of bundle?.fields ?? []) {
      const list = groups.get(field.section) ?? [];
      list.push(field);
      groups.set(field.section, list);
    }
    return [...groups.entries()];
  });
</script>

{#if open}
  <div
    class="fixed top-0 right-0 bottom-0 z-50 flex w-full max-w-[min(32rem,100%)] flex-col border-l border-vpro-border bg-white text-vpro-ink shadow-2xl max-sm:left-0"
    role="complementary"
    aria-label="VPro Help and LMH25 Reference"
    data-help-drawer
  >
    <header class="border-b-[3px] border-b-vpro-gold bg-vpro-navy px-4 py-3 text-white">
      <div class="flex items-center justify-between gap-2">
        <div class="min-w-0">
          <div class="font-mono text-[11px] uppercase tracking-wider text-vpro-gold">
            100% Offline Reference · LMH25 (2023)
          </div>
          <h2 class="truncate text-base font-semibold text-white">VPro Field Inspector &amp; BEC User Guide</h2>
        </div>
        <button
          type="button"
          class="rounded border border-white/30 bg-white/10 p-1.5 text-white hover:bg-white/20"
          aria-label="Close Help Drawer"
          data-help-drawer-close
          onclick={onclose}
        >
          <X size={16} />
        </button>
      </div>

      <div class="mt-3">
        <label for="help-drawer-search" class="sr-only">Search LMH25 fields, codes, keys and guides</label>
        <div class="relative flex items-center">
          <Search size={15} class="pointer-events-none absolute left-2.5 text-vpro-ink-muted" />
          <input
            id="help-drawer-search"
            type="search"
            data-help-search-input
            value={searchQuery}
            placeholder="Search codes (SITE 20, SOIL 5, Of, Mor, rSMR), keys or guides..."
            class="w-full rounded border border-vpro-border bg-white py-1.5 pr-3 pl-8 text-xs text-vpro-ink placeholder:text-vpro-ink-muted focus:outline-2 focus:outline-vpro-gold"
            oninput={(e) => void runSearch(e.currentTarget.value)}
          />
        </div>
      </div>
    </header>

    {#if searchQuery.trim()}
      <HelpDrawerSearchResults
        {searchQuery}
        {searchBusy}
        {searchHits}
        onclear={() => {
          searchQuery = '';
          searchHits = [];
        }}
        onopenhit={openSearchHit}
      />
    {/if}

    <nav
      class="flex border-b border-vpro-border bg-vpro-canvas px-3 pt-2 text-xs font-semibold"
      aria-label="Help Drawer tabs"
    >
      <button
        type="button"
        data-help-tab="inspector"
        aria-current={activeTab === 'inspector' ? 'page' : undefined}
        class="flex items-center gap-1.5 rounded-t border border-b-0 px-3 py-2 {activeTab === 'inspector'
          ? 'border-vpro-border bg-white text-vpro-navy'
          : 'border-transparent text-vpro-ink-secondary hover:text-vpro-navy'}"
        onclick={() => {
          activeTab = 'inspector';
        }}
      >
        <SlidersHorizontal size={14} /> Field Inspector
      </button>
      <button
        type="button"
        data-help-tab="keys"
        aria-current={activeTab === 'keys' ? 'page' : undefined}
        class="flex items-center gap-1.5 rounded-t border border-b-0 px-3 py-2 {activeTab === 'keys'
          ? 'border-vpro-border bg-white text-vpro-navy'
          : 'border-transparent text-vpro-ink-secondary hover:text-vpro-navy'}"
        onclick={() => {
          activeTab = 'keys';
        }}
      >
        <Scale size={14} /> Decision Keys
      </button>
      <button
        type="button"
        data-help-tab="guides"
        aria-current={activeTab === 'guides' ? 'page' : undefined}
        class="flex items-center gap-1.5 rounded-t border border-b-0 px-3 py-2 {activeTab === 'guides'
          ? 'border-vpro-border bg-white text-vpro-navy'
          : 'border-transparent text-vpro-ink-secondary hover:text-vpro-navy'}"
        onclick={() => {
          activeTab = 'guides';
        }}
      >
        <BookOpen size={14} /> User Guides
      </button>
    </nav>

    <div class="flex-1 space-y-4 overflow-y-auto p-4 text-xs leading-relaxed">
      {#if error}
        <p role="alert" class="rounded border border-vpro-error bg-red-50 p-2.5 text-vpro-error">{error}</p>
      {/if}
      {#if loading && !bundle}
        <p role="status" class="text-vpro-ink-secondary">Loading embedded LMH25 (2023) reference bundle...</p>
      {/if}

      {#if activeTab === 'inspector'}
        <HelpDrawerTopicView
          {groupedFields}
          {selectedFieldId}
          {lookup}
          onloadtopic={(id) => void loadTopic(id)}
          onopenkey={(id) => {
            selectDecisionKey(id);
            activeTab = 'keys';
          }}
          onopenguide={openGuide}
        />
      {:else if activeTab === 'keys'}
        <HelpDrawerKeysView
          decisionKeys={bundle?.decisionKeys ?? []}
          {selectedKeyId}
          {activeDecisionKey}
          isDichotomous={activeDecisionKey ? isDichotomousDecisionKey(activeDecisionKey) : false}
          {keyEval}
          {currentKeyStepObj}
          coverComparisonBlocks={COVER_COMPARISON_BLOCKS}
          onselectkey={selectDecisionKey}
          onanswerkey={answerKey}
          onresetkey={resetKey}
        />
      {:else if activeTab === 'guides'}
        <div class="space-y-3" data-help-guides-panel>
          {#if onstarttour}
            <div class="flex items-center justify-between gap-2 rounded border border-vpro-gold bg-amber-50/50 p-3">
              <div>
                <div class="text-xs font-bold text-vpro-navy">Coming from Microsoft Access VPro 64?</div>
                <div class="text-[11px] text-vpro-ink-secondary">
                  Launch the 4 interactive spotlight walkthroughs on the Sample project.
                </div>
              </div>
              <button
                type="button"
                class="inline-flex shrink-0 items-center gap-1 rounded bg-vpro-navy px-2.5 py-1.5 text-xs font-semibold text-white hover:bg-vpro-navy-dark"
                onclick={() => onstarttour()}
              >
                <Compass size={13} /> 4 Tours
              </button>
            </div>
          {/if}

          <div>
            <label
              for="help-guide-selector"
              class="block text-[11px] font-semibold uppercase tracking-wide text-vpro-ink-secondary"
            >
              Workflow &amp; User Guides
            </label>
            <select
              id="help-guide-selector"
              class="mt-1 w-full rounded border border-vpro-border bg-white px-2.5 py-1.5 text-xs text-vpro-ink"
              value={selectedGuideId}
              onchange={(e) => {
                selectedGuideId = e.currentTarget.value;
              }}
            >
              {#each bundle?.guides ?? [] as g (g.id)}
                <option value={g.id}>{g.category} — {g.title}</option>
              {/each}
            </select>
          </div>

          {#if activeGuide}
            <article
              class="space-y-3 rounded border border-vpro-border border-t-[3px] border-t-vpro-navy bg-white p-3.5"
              data-help-active-guide={activeGuide.id}
            >
              <div class="font-mono text-[11px] font-semibold uppercase text-vpro-navy">{activeGuide.category}</div>
              <h3 class="text-sm font-bold text-vpro-ink">{activeGuide.title}</h3>
              <p class="rounded bg-vpro-canvas p-2.5 text-xs text-vpro-ink-secondary">{activeGuide.summary}</p>
              <div class="space-y-3">
                {#each activeGuide.sections as sec (sec.heading)}
                  <section class="space-y-1 border-l-2 border-vpro-gold pl-3">
                    <h4 class="text-xs font-bold text-vpro-navy">{sec.heading}</h4>
                    <p class="text-xs text-vpro-ink">{sec.body}</p>
                  </section>
                {/each}
              </div>
            </article>
          {/if}
        </div>
      {/if}
    </div>
  </div>
{/if}
