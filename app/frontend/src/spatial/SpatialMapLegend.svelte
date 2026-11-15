<script lang="ts">
  import { BEC_ZONE_PALETTE } from './geospatialWorkbench';

  let {
    aoiMatchedCount = 0,
    viewportMatchedCount = 0,
  }: {
    aoiMatchedCount?: number;
    viewportMatchedCount?: number;
  } = $props();
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
</div>
