<script lang="ts">
  import {
    BEC_ZONE_PALETTE,
    DEFAULT_BC_WMS_LAYER,
    DEFAULT_MAP_BASEMAP,
    getBCOpenMapsWMSOption,
    getMapBasemapOption,
    type BCOpenMapsWMSLayerId,
    type MapBasemapId,
  } from './geospatialWorkbench';

  let {
    aoiMatchedCount = 0,
    viewportMatchedCount = 0,
    basemap = DEFAULT_MAP_BASEMAP,
    bcOpenMapsWMS = false,
    wmsLayer = DEFAULT_BC_WMS_LAYER,
  }: {
    aoiMatchedCount?: number;
    viewportMatchedCount?: number;
    basemap?: MapBasemapId;
    bcOpenMapsWMS?: boolean;
    wmsLayer?: BCOpenMapsWMSLayerId;
  } = $props();

  const attributionText = $derived.by(() => {
    const parts: string[] = [];
    const baseOpt = getMapBasemapOption(basemap);
    if (baseOpt.online && baseOpt.attribution) {
      parts.push(`Basemap: ${baseOpt.attribution}`);
    }
    if (bcOpenMapsWMS) {
      const wmsOpt = getBCOpenMapsWMSOption(wmsLayer);
      parts.push(`Overlay: ${wmsOpt.label} (${wmsOpt.attribution})`);
    }
    return parts.join(' | ');
  });
</script>

<div class="wb-map-legend" aria-label="BGC Zone and Pin Legend">
  <div class="wb-legend-row">
    <span class="wb-dot wb-dot-ok"></span><span>Verified Plot</span>
    <span class="wb-dot wb-dot-err"></span><span>BGC / UTM Discrepancy</span>
    <span class="wb-dot wb-dot-aoi"></span><span>AOI Selected ({aoiMatchedCount})</span>
    <span class="wb-viewport-stat">In Viewport: {viewportMatchedCount}</span>
  </div>
  <div class="wb-zone-swatches">
    {#each Object.entries(BEC_ZONE_PALETTE).slice(0, 10) as [zCode, zHex] (zCode)}
      <span class="wb-swatch"><i style={`background:${zHex}`}></i>{zCode}</span>
    {/each}
  </div>
  {#if attributionText}
    <div class="wb-legend-attribution">{attributionText}</div>
  {/if}
</div>
