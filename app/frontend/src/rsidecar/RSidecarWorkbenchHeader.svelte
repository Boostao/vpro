<script lang="ts">
  type SidecarTab = 'runtime' | 'edatopic' | 'clustering' | 'quarto';

  let {
    activeProject,
    activeSu,
    busy,
    activeTab = $bindable(),
    standaloneQuartoMode = false,
    error,
    onSelectTab,
    onRefreshRuntime,
  }: {
    activeProject: string;
    activeSu: string;
    busy: boolean;
    activeTab: SidecarTab;
    standaloneQuartoMode?: boolean;
    error: string | null;
    onSelectTab?: (tab: SidecarTab) => void;
    onRefreshRuntime: () => void;
  } = $props();

  function selectTab(next: SidecarTab) {
    activeTab = next;
    onSelectTab?.(next);
  }
</script>

<header class="bcgov-header" style="background:#003366;border-bottom:4px solid #FCBA19;color:#FFFFFF">
  <div>
    {#if standaloneQuartoMode && activeTab === 'quarto'}
      <h2 data-quarto-standalone-heading>Quarto Unit &amp; BGC Ecosystem Report</h2>
      <p class="subtitle">
        Active Project: <strong>{activeProject}</strong> | Active SU: <strong>{activeSu}</strong> | Publish a
        Quarto HTML/PDF unit guide or display an instant built-in HTML report
      </p>
    {:else}
      <h2>R Companion: Climate, Clustering &amp; Ecosystem Guides</h2>
      <p class="subtitle">
        Active Project: <strong>{activeProject}</strong> | Active SU: <strong>{activeSu}</strong> | R / climr /
        vegclust / Quarto
      </p>
    {/if}
  </div>
  <div class="header-actions">
    <button type="button" class="btn-gold" disabled={busy} onclick={onRefreshRuntime}>
      Check R &amp; Quarto Setup
    </button>
  </div>
</header>

<div
  data-workbench-sticky-bar
  class="tab-bar sticky top-0 z-20 bg-white/95 backdrop-blur-xs py-2 border-b border-vpro-border"
  role="tablist"
  aria-label="R Companion Sections"
>
  <button
    type="button"
    role="tab"
    aria-selected={activeTab === 'runtime'}
    class:active={activeTab === 'runtime'}
    onclick={() => selectTab('runtime')}
  >
    1. Runtime &amp; climr Climate Normals
  </button>
  <button
    type="button"
    role="tab"
    aria-selected={activeTab === 'edatopic'}
    class:active={activeTab === 'edatopic'}
    onclick={() => selectTab('edatopic')}
  >
    2. Dual rSMR vs aSMR Edatopic Grids
  </button>
  <button
    type="button"
    role="tab"
    aria-selected={activeTab === 'clustering'}
    class:active={activeTab === 'clustering'}
    onclick={() => selectTab('clustering')}
  >
    3. R Clustering &amp; Dendrogram
  </button>
  <button
    type="button"
    role="tab"
    aria-selected={activeTab === 'quarto'}
    class:active={activeTab === 'quarto'}
    onclick={() => selectTab('quarto')}
  >
    4. Quarto Unit &amp; BGC Guide Publisher
  </button>
</div>

{#if error}<div class="banner-error" role="alert">{error}</div>{/if}

<style>
  .tab-bar[data-workbench-sticky-bar] {
    position: sticky;
    top: 0;
    z-index: 20;
    background: rgba(255, 255, 255, 0.95);
    backdrop-filter: blur(4px);
    padding-top: 0.5rem;
    padding-bottom: 0.5rem;
  }
</style>
