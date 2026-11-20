<script lang="ts">
  let {
    activeTab = $bindable(),
    busy,
    operationHeld,
    contextId,
    notice,
    onRefreshTables,
  }: {
    activeTab: 'tables' | 'recipes';
    busy: boolean;
    operationHeld: boolean;
    contextId: string;
    notice: string;
    onRefreshTables: () => void;
  } = $props();
</script>

<header class="bcgov-header">
  <div>
    <p class="bcgov-eyebrow">BEC TAXONOMIC CORRELATION</p>
    <h2>Combine Species &amp; Lumping Presets</h2>
  </div>
  <div class="bcgov-tab-strip" role="tablist">
    <button
      type="button"
      role="tab"
      aria-selected={activeTab === 'tables'}
      class:active={activeTab === 'tables'}
      onclick={() => (activeTab = 'tables')}
    >
      Lumping Tables
    </button>
    <button
      type="button"
      role="tab"
      aria-selected={activeTab === 'recipes'}
      class:active={activeTab === 'recipes'}
      onclick={() => (activeTab = 'recipes')}
    >
      Lumping Presets &amp; Rules
    </button>
    <button
      type="button"
      class="bcgov-btn-secondary"
      disabled={busy || operationHeld || !contextId}
      onclick={onRefreshTables}
    >
      Refresh Catalog
    </button>
  </div>
</header>

{#if notice}<p class="bcgov-notice" role="status">{notice}</p>{/if}

<style>
  .bcgov-header {
    background: var(--vpro-navy);
    color: var(--vpro-surface);
    border-bottom: 4px solid var(--vpro-gold);
    padding: 1rem 1.25rem;
    border-radius: 4px;
    display: flex;
    flex-wrap: wrap;
    justify-content: space-between;
    align-items: center;
    gap: 1rem;
  }
  .bcgov-header h2 {
    margin: 0.2rem 0 0;
    font-size: 1.2rem;
    color: var(--vpro-surface);
  }
  .bcgov-eyebrow {
    margin: 0;
    font-size: 0.72rem;
    letter-spacing: 0.08em;
    color: var(--vpro-gold);
    font-weight: 700;
  }
  .bcgov-tab-strip {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
  }
  .bcgov-tab-strip button[role='tab'] {
    background: rgba(255, 255, 255, 0.12);
    color: var(--vpro-surface);
    border: 1px solid rgba(255, 255, 255, 0.28);
    padding: 0.45rem 0.85rem;
    border-radius: 4px;
    font-size: 0.85rem;
  }
  .bcgov-tab-strip button[role='tab'].active {
    background: var(--vpro-gold);
    color: var(--vpro-navy);
    border-color: var(--vpro-gold);
    font-weight: 700;
  }
  .bcgov-btn-secondary {
    background: var(--vpro-surface);
    color: var(--vpro-navy);
    border: 1px solid var(--vpro-navy);
    padding: 0.48rem 0.85rem;
    border-radius: 4px;
    font-weight: 600;
    font-size: 0.84rem;
  }
  .bcgov-notice {
    padding: 0.65rem 0.9rem;
    background: var(--vpro-canvas);
    border-left: 4px solid var(--vpro-gold);
    color: var(--vpro-navy);
    margin: 0;
    font-size: 0.85rem;
  }
  @media (pointer: coarse) {
    .bcgov-tab-strip button,
    .bcgov-btn-secondary {
      min-height: 44px;
    }
  }
</style>
