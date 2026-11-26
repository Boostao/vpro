<script lang="ts">
  import type { BGCMapSyncResult, BGCMapSyncStatus } from '../../bindings/github.com/boostao/vpro/app';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import {
    BC_FOREST_REGIONS,
    DEFAULT_MAP_BASEMAP,
    MAP_BASEMAP_OPTIONS,
    describeBGCMapSource,
    formatMapByteSize,
    formatSyncTimestamp,
    resolveGoogleHybridBasemap,
    type GoogleHybridConfig,
    type MapBasemapId,
    type MapLayerVisibility,
  } from './geospatialWorkbench';

  let {
    basemap = $bindable<MapBasemapId>(DEFAULT_MAP_BASEMAP),
    visibility = $bindable<MapLayerVisibility>(),
    googleHybridConfig = { tileUrlTemplate: '', apiKey: '' },
    bgcSyncStatus = null,
    bgcSyncLoading = false,
    bgcSyncBusy = false,
    bgcSyncUrl = $bindable(''),
    bgcSyncSha256 = $bindable(''),
    bgcSyncError = '',
    bgcLastSyncResult = null,
    onApplyLayers,
    onSaveGoogleHybridConfig,
    onRefreshBgcSyncStatus,
    onSyncLatestBgcMap,
  }: {
    basemap?: MapBasemapId;
    visibility: MapLayerVisibility;
    googleHybridConfig?: GoogleHybridConfig;
    bgcSyncStatus?: BGCMapSyncStatus | null;
    bgcSyncLoading?: boolean;
    bgcSyncBusy?: boolean;
    bgcSyncUrl?: string;
    bgcSyncSha256?: string;
    bgcSyncError?: string;
    bgcLastSyncResult?: BGCMapSyncResult | null;
    onApplyLayers: () => void;
    onSaveGoogleHybridConfig: (next: GoogleHybridConfig) => void;
    onRefreshBgcSyncStatus?: () => Promise<void> | void;
    onSyncLatestBgcMap?: (sourceUrl: string, expectedSha256: string) => Promise<void> | void;
  } = $props();

  let draftTileUrl = $state('');
  let draftApiKey = $state('');
  let showGoogleConfig = $state(false);
  let lastSyncedCfgKey = '';
  const googleTilePlaceholder = 'https://tile.googleapis.com/v1/2dtiles/{z}/{x}/{y}?session=...&key={key}';
  const googleKeyPlaceholder = 'Paste API key if your tile URL uses {key}';

  $effect(() => {
    const key = `${googleHybridConfig?.tileUrlTemplate ?? ''}\u0000${googleHybridConfig?.apiKey ?? ''}`;
    if (key !== lastSyncedCfgKey) {
      lastSyncedCfgKey = key;
      draftTileUrl = googleHybridConfig?.tileUrlTemplate ?? '';
      draftApiKey = googleHybridConfig?.apiKey ?? '';
    }
  });

  const googleResolved = $derived(resolveGoogleHybridBasemap(googleHybridConfig));
  const draftValidation = $derived(
    resolveGoogleHybridBasemap({ tileUrlTemplate: draftTileUrl, apiKey: draftApiKey })
  );
  const effectiveSyncUrl = $derived((bgcSyncUrl || bgcSyncStatus?.defaultSourceUrl || '').trim());

  function selectBasemap(id: MapBasemapId) {
    basemap = id;
    if (id === 'google-hybrid' && !googleResolved.configured) {
      showGoogleConfig = true;
    }
    onApplyLayers();
  }

  function applyGoogleConfig() {
    onSaveGoogleHybridConfig({
      tileUrlTemplate: draftTileUrl.trim(),
      apiKey: draftApiKey.trim(),
    });
  }

  function resetGoogleConfig() {
    draftTileUrl = '';
    draftApiKey = '';
    onSaveGoogleHybridConfig({ tileUrlTemplate: '', apiKey: '' });
  }

  function describeChecksumSource(source: string): string {
    switch (source) {
      case 'explicit':
        return 'Verified against your SHA-256 checksum';
      case 'companion':
        return 'Verified automatically via published .sha256 file';
      default:
        return 'Map file integrity checked (no SHA-256 file published)';
    }
  }
</script>

<div class="wb-panel-body wb-layers-sync-body" data-map-layers-sync-panel>
  <section class="wb-card" aria-label="Base map selection">
    <div class="wb-card-head">
      <h2>Base Map</h2>
      <span class="wb-label">1-Click Switch</span>
    </div>
    <p class="wb-help-copy">
      Choose a satellite, topographic, street, or offline background. Your BGC zones, boundaries, and plot pins stay on
      top.
    </p>
    <div class="wb-basemap-grid" role="group" aria-label="Available base maps">
      {#each MAP_BASEMAP_OPTIONS as opt (opt.id)}
        <button
          type="button"
          class="wb-basemap-card"
          class:active={basemap === opt.id}
          aria-pressed={basemap === opt.id}
          data-basemap-option={opt.id}
          onclick={() => selectBasemap(opt.id)}
        >
          <span class="wb-basemap-card-title">{opt.label}</span>
          {#if opt.description}
            <span class="wb-basemap-card-desc">{opt.description}</span>
          {/if}
        </button>
      {/each}
    </div>

    {#if basemap === 'google-hybrid' || showGoogleConfig}
      <div class="wb-google-config-box" data-google-hybrid-config>
        <div class="wb-card-head">
          <h3>Google Hybrid Settings</h3>
          <span class="wb-status-pill" class:wb-status-pill-ok={googleResolved.configured}>
            {googleResolved.configured ? 'Configured' : 'Using Satellite Hybrid'}
          </span>
        </div>
        <p class="wb-help-copy" role="status" data-google-hybrid-note>
          {googleResolved.statusNote}
        </p>

        {#if !IS_WEB_READONLY}
          <label class="wb-sync-field" for="wb-google-tile-url">
            <span>Google / Custom Hybrid Tile URL Template</span>
            <input
              id="wb-google-tile-url"
              type="url"
              class="wb-input"
              bind:value={draftTileUrl}
              placeholder={googleTilePlaceholder}
            />
          </label>
          <label class="wb-sync-field" for="wb-google-api-key">
            <span>Google Maps API Key (optional)</span>
            <input
              id="wb-google-api-key"
              type="password"
              class="wb-input"
              autocomplete="off"
              bind:value={draftApiKey}
              placeholder={googleKeyPlaceholder}
            />
          </label>
          {#if draftValidation.validationError}
            <p class="wb-flag-text wb-small-msg" role="alert">{draftValidation.validationError}</p>
          {/if}
          <div class="wb-sync-actions">
            <button type="button" class="wb-btn wb-btn-primary" onclick={applyGoogleConfig}>
              Apply Tile Settings
            </button>
            <button
              type="button"
              class="wb-btn"
              onclick={resetGoogleConfig}
              disabled={!draftTileUrl && !draftApiKey && !googleResolved.configured}
            >
              Reset
            </button>
          </div>
        {/if}
      </div>
    {:else if !IS_WEB_READONLY}
      <button
        type="button"
        class="wb-link-btn wb-config-toggle"
        onclick={() => {
          showGoogleConfig = true;
        }}
      >
        Configure Google Hybrid tile URL or API key...
      </button>
    {/if}
  </section>

  <section class="wb-card" aria-label="Reference overlays">
    <div class="wb-card-head">
      <h2>Reference Overlays</h2>
      <span class="wb-label">BC Provincial Layers</span>
    </div>
    <div class="wb-overlay-list">
      <label class="wb-toggle">
        <input type="checkbox" bind:checked={visibility.bgcFill} onchange={onApplyLayers} />
        <span>BGC v13 Polygons</span>
      </label>
      <label class="wb-toggle">
        <input
          type="checkbox"
          bind:checked={visibility.forestRegions}
          onchange={onApplyLayers}
          data-overlay-forest-regions
        />
        <span>BC Forest Regions</span>
      </label>
      <label class="wb-toggle">
        <input type="checkbox" bind:checked={visibility.ecosections} onchange={onApplyLayers} />
        <span>Ecosections</span>
      </label>
      <label class="wb-toggle">
        <input type="checkbox" bind:checked={visibility.nrDistricts} onchange={onApplyLayers} />
        <span>NR Districts</span>
      </label>
      <label class="wb-toggle">
        <input type="checkbox" bind:checked={visibility.hillshade3D} onchange={onApplyLayers} />
        <span>3D Reconnaissance Tilt</span>
      </label>
      <label class="wb-toggle">
        <input type="checkbox" bind:checked={visibility.bcOpenMapsWMS} onchange={onApplyLayers} />
        <span>Online BC OpenMaps WMS</span>
      </label>
    </div>

    {#if visibility.forestRegions}
      <div class="wb-region-legend" data-forest-regions-legend>
        {#each BC_FOREST_REGIONS as reg (reg.code)}
          <span class="wb-region-chip">
            <i style={`background:${reg.color}`}></i>
            <strong>{reg.code}</strong>
            <span>{reg.name}</span>
          </span>
        {/each}
      </div>
    {/if}
  </section>

  {#if !IS_WEB_READONLY}
    <section class="wb-card" aria-label="BGC Base Map Sync" data-bgc-sync-section>
      <div class="wb-card-head">
        <h2>BGC Base Map Sync</h2>
        <button
          type="button"
          class="wb-btn"
          onclick={() => onRefreshBgcSyncStatus?.()}
          disabled={bgcSyncLoading || bgcSyncBusy}
        >
          {bgcSyncLoading ? 'Checking...' : 'Check Status'}
        </button>
      </div>
      <p class="wb-help-copy">
        Download the latest provincial BGC v13 offline map directly into VPro. The map refreshes immediately once the
        download is verified.
      </p>

      {#if bgcSyncStatus}
        <dl class="wb-kv-grid" data-bgc-sync-metadata>
          <div>
            <dt>Active Map Source</dt>
            <dd>{describeBGCMapSource(bgcSyncStatus)}</dd>
          </div>
          <div>
            <dt>Detail Level</dt>
            <dd>
              {bgcSyncStatus.fullResolution ? 'Full Resolution' : 'Overview'} (z{bgcSyncStatus.minZoom || 3}..{bgcSyncStatus.maxZoom || 6})
            </dd>
          </div>
          <div>
            <dt>File Size</dt>
            <dd>{formatMapByteSize(bgcSyncStatus.sizeBytes)}</dd>
          </div>
          <div>
            <dt>Last Updated</dt>
            <dd>{formatSyncTimestamp(bgcSyncStatus.modTime)}</dd>
          </div>
          {#if bgcSyncStatus.sha256}
            <div>
              <dt>SHA-256 Digest</dt>
              <dd class="mono" title={bgcSyncStatus.sha256}>{bgcSyncStatus.sha256.slice(0, 12)}...</dd>
            </div>
          {/if}
          {#if bgcSyncStatus.defaultSourceUrl}
            <div>
              <dt>Configured Sync URL</dt>
              <dd class="mono wb-url-preview" title={bgcSyncStatus.defaultSourceUrl}>
                {bgcSyncStatus.defaultSourceUrl}
              </dd>
            </div>
          {/if}
        </dl>

        {#if bgcSyncStatus.warning}
          <p class="wb-flag-text wb-small-msg" role="alert">{bgcSyncStatus.warning}</p>
        {/if}
      {:else if bgcSyncLoading}
        <p class="wb-help-copy">Checking local BGC map status...</p>
      {:else}
        <p class="wb-help-copy">Local BGC map status has not been loaded yet.</p>
      {/if}

      <label class="wb-sync-field" for="wb-bgc-sync-url">
        <span>BGC Map Source URL (HTTPS)</span>
        <input
          id="wb-bgc-sync-url"
          type="url"
          class="wb-input"
          bind:value={bgcSyncUrl}
          disabled={bgcSyncBusy}
          placeholder="https://.../bc-bgc-v13.pmtiles"
        />
      </label>

      <label class="wb-sync-field" for="wb-bgc-sync-sha256">
        <span>Expected SHA-256 Checksum (optional)</span>
        <input
          id="wb-bgc-sync-sha256"
          type="text"
          class="wb-input mono"
          bind:value={bgcSyncSha256}
          disabled={bgcSyncBusy}
          placeholder="Leave blank to verify via companion .sha256 file"
        />
      </label>

      {#if bgcSyncError}
        <p class="wb-flag-text wb-small-msg" role="alert" data-bgc-sync-error>{bgcSyncError}</p>
      {/if}

      <div class="wb-sync-actions">
        <button
          type="button"
          class="wb-btn wb-btn-gold"
          data-bgc-sync-btn
          disabled={bgcSyncBusy || !effectiveSyncUrl}
          onclick={() => onSyncLatestBgcMap?.(effectiveSyncUrl, bgcSyncSha256.trim())}
        >
          {bgcSyncBusy ? 'Syncing Latest BGC Map...' : 'Sync Latest BGC Map'}
        </button>
      </div>

      {#if bgcLastSyncResult}
        <div class="wb-sync-result" role="status" data-bgc-sync-result>
          <strong>Map updated and reloaded live</strong>
          <span>
            {formatMapByteSize(bgcLastSyncResult.sizeBytes)} (z{bgcLastSyncResult.minZoom}..{bgcLastSyncResult.maxZoom})
            - {describeChecksumSource(bgcLastSyncResult.checksumSource)}
          </span>
          <span class="mono">Synced {formatSyncTimestamp(bgcLastSyncResult.syncedAt)}</span>
        </div>
      {/if}
    </section>
  {/if}
</div>

<style>
  .wb-layers-sync-body {
    padding-bottom: 12rem;
    scroll-padding-bottom: 12rem;
  }
  .wb-help-copy {
    margin: 0;
    font-size: 0.76rem;
    line-height: 1.4;
    color: var(--vpro-ink-secondary);
  }
  .wb-basemap-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 145px), 1fr));
    gap: 0.4rem;
  }
  .wb-basemap-card {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 0.2rem;
    text-align: left;
    padding: 0.5rem 0.55rem;
    border: 1px solid var(--vpro-border);
    border-radius: 5px;
    background: var(--vpro-surface);
    color: var(--vpro-ink);
    cursor: pointer;
  }
  .wb-basemap-card:hover {
    border-color: var(--vpro-navy);
  }
  .wb-basemap-card.active {
    border-color: var(--vpro-navy);
    background: var(--vpro-navy);
    color: var(--vpro-surface);
  }
  .wb-basemap-card-title {
    font-size: 0.76rem;
    font-weight: 700;
    line-height: 1.25;
  }
  .wb-basemap-card.active .wb-basemap-card-title {
    color: var(--vpro-gold);
  }
  .wb-basemap-card-desc {
    font-size: 0.69rem;
    line-height: 1.3;
    color: var(--vpro-ink-secondary);
  }
  .wb-basemap-card.active .wb-basemap-card-desc {
    color: var(--vpro-surface);
  }
  .wb-google-config-box {
    display: flex;
    flex-direction: column;
    gap: 0.45rem;
    padding: 0.55rem;
    border: 1px solid var(--vpro-border);
    border-left: 3px solid var(--vpro-gold);
    border-radius: 4px;
    background: var(--vpro-surface);
  }
  .wb-google-config-box h3 {
    margin: 0;
    font-size: 0.8rem;
    font-weight: 700;
    color: var(--vpro-navy);
  }
  .wb-status-pill {
    display: inline-block;
    padding: 0.12rem 0.45rem;
    border-radius: 999px;
    font-size: 0.67rem;
    font-weight: 700;
    background: var(--vpro-canvas);
    color: var(--vpro-navy);
    border: 1px solid var(--vpro-border);
  }
  .wb-status-pill-ok {
    background: var(--vpro-forest);
    color: var(--vpro-surface);
    border-color: var(--vpro-forest);
  }
  .wb-config-toggle {
    align-self: flex-start;
    font-size: 0.75rem;
    font-weight: 600;
    color: var(--vpro-navy);
    background: transparent;
    border: none;
    padding: 0;
    cursor: pointer;
    text-decoration: underline;
  }
  .wb-overlay-list {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 145px), 1fr));
    gap: 0.45rem 0.65rem;
  }
  .wb-region-legend {
    display: flex;
    flex-wrap: wrap;
    gap: 0.3rem;
    padding-top: 0.25rem;
    border-top: 1px solid var(--vpro-border);
  }
  .wb-region-chip {
    display: inline-flex;
    align-items: center;
    gap: 0.25rem;
    font-size: 0.69rem;
    padding: 0.12rem 0.35rem;
    border-radius: 3px;
    background: var(--vpro-surface);
    border: 1px solid var(--vpro-border);
    color: var(--vpro-ink);
  }
  .wb-region-chip i {
    display: inline-block;
    width: 8px;
    height: 8px;
    border-radius: 2px;
  }
  .wb-sync-field {
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
    font-size: 0.74rem;
    font-weight: 600;
    color: var(--vpro-navy);
  }
  .wb-sync-actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.45rem;
    align-items: center;
  }
  .wb-small-msg {
    margin: 0;
    font-size: 0.75rem;
    line-height: 1.35;
  }
  .wb-url-preview {
    font-size: 0.7rem;
    word-break: break-all;
  }
  .wb-sync-result {
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
    padding: 0.5rem 0.6rem;
    border-radius: 4px;
    border: 1px solid var(--vpro-forest);
    background: var(--vpro-surface);
    color: var(--vpro-forest);
    font-size: 0.75rem;
  }
</style>
