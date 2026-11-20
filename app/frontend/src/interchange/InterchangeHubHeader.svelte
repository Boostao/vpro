<script lang="ts">
  export type InterchangeSection = 'venus' | 'turboveg' | 'userspecies' | 'analytics' | 'geopackage';

  let {
    section = $bindable<InterchangeSection>('venus'),
    busy = false,
    onCancel,
  }: {
    section?: InterchangeSection;
    busy?: boolean;
    onCancel: () => void;
  } = $props();
</script>

<header class="bcgov-banner">
  <div>
    <p class="eyebrow-gold">STANDARDS, ANALYTICS &amp; GIS INTERCHANGE</p>
    <h2>VENUS 5.0, TurboVeg 3 / XML, User Species, CSV / R (.rds) &amp; OGC GeoPackage (.gpkg)</h2>
  </div>
  <nav class="hub-tabs" aria-label="Interchange formats">
    <button type="button" class:active={section === 'venus'} onclick={() => (section = 'venus')}>VENUS 5.0</button>
    <button type="button" class:active={section === 'turboveg'} onclick={() => (section = 'turboveg')}>
      TurboVeg 3 / XML
    </button>
    <button type="button" class:active={section === 'userspecies'} onclick={() => (section = 'userspecies')}>
      User Species List
    </button>
    <button type="button" class:active={section === 'analytics'} onclick={() => (section = 'analytics')}>
      Long/Wide CSV &amp; R .rds
    </button>
    <button type="button" class:active={section === 'geopackage'} onclick={() => (section = 'geopackage')}>
      GeoPackage (.gpkg)
    </button>
    {#if busy}
      <button type="button" class="cancel-btn" onclick={onCancel}>Cancel</button>
    {/if}
  </nav>
</header>

<style>
  .bcgov-banner {
    background: var(--vpro-navy);
    color: var(--vpro-surface);
    border-bottom: 4px solid var(--vpro-gold);
    border-radius: 4px;
    padding: 1rem 1.25rem;
    display: grid;
    gap: 0.75rem;
    min-width: 0;
  }
  .bcgov-banner h2 {
    margin: 0.15rem 0 0;
    font-size: 1.15rem;
    color: var(--vpro-surface);
  }
  .eyebrow-gold {
    margin: 0;
    font-size: 0.72rem;
    letter-spacing: 0.08em;
    color: var(--vpro-gold);
    font-weight: 700;
  }
  .hub-tabs {
    display: flex;
    flex-wrap: wrap;
    gap: 0.45rem;
  }
  .hub-tabs button {
    background: rgba(255, 255, 255, 0.12);
    color: var(--vpro-surface);
    border: 1px solid rgba(255, 255, 255, 0.3);
    border-radius: 4px;
    padding: 0.42rem 0.8rem;
    font-size: 0.82rem;
  }
  .hub-tabs button.active {
    background: var(--vpro-gold);
    color: var(--vpro-navy);
    border-color: var(--vpro-gold);
    font-weight: 700;
  }
  .hub-tabs button.cancel-btn {
    background: var(--vpro-error);
    border-color: var(--vpro-error-bg);
    margin-left: auto;
  }
  @media (pointer: coarse) {
    .hub-tabs button {
      min-height: 44px;
    }
  }
</style>
