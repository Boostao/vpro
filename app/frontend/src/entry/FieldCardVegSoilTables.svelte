<script lang="ts">
  import type { FieldCardViewModel } from './fieldCardPreview';

  let {
    section,
    viewModel,
  }: {
    section: 'soil' | 'veg';
    viewModel: FieldCardViewModel;
  } = $props();
</script>

{#if section === 'soil'}
  <div class="fc-two-col">
    <section class="fc-block">
      <div class="fc-block-header">8. ORGANIC HORIZONS / LAYERS</div>
      <table class="fc-ruled-table">
        <thead>
          <tr>
            <th>Horiz</th>
            <th>Depth</th>
            <th>Struct</th>
            <th>M/F</th>
            <th>Roots</th>
            <th>vP</th>
            <th>pH</th>
            <th>Comment</th>
          </tr>
        </thead>
        <tbody>
          {#each viewModel.front.organicHorizons as row (row.id)}
            <tr class:fc-row-draft={row.isDraft}>
              <td class="fc-mono fc-bold">{row.horizon}</td>
              <td class="fc-mono">{row.depthRange}</td>
              <td class="fc-mono">{row.fabricStructure}</td>
              <td class="fc-mono">{row.mycelFecal}</td>
              <td class="fc-mono">{row.roots}</td>
              <td class="fc-mono">{row.vonPost}</td>
              <td class="fc-mono">{row.ph}</td>
              <td>{row.comment}</td>
            </tr>
          {:else}
            <tr><td colspan="8" class="fc-empty-cell">No organic horizons recorded</td></tr>
          {/each}
        </tbody>
      </table>
    </section>

    <section class="fc-block">
      <div class="fc-block-header">9. MINERAL HORIZONS / LAYERS</div>
      <table class="fc-ruled-table">
        <thead>
          <tr>
            <th>Horiz</th>
            <th>Depth</th>
            <th>Tex</th>
            <th>Colour</th>
            <th>Coarse Frags</th>
            <th>Roots</th>
            <th>Struct</th>
            <th>pH</th>
            <th>Comments</th>
          </tr>
        </thead>
        <tbody>
          {#each viewModel.front.mineralHorizons as row (row.id)}
            <tr class:fc-row-draft={row.isDraft}>
              <td class="fc-mono fc-bold">{row.horizon}</td>
              <td class="fc-mono">{row.depthRange}</td>
              <td class="fc-mono">{row.texture}</td>
              <td class="fc-mono">{row.colour}</td>
              <td class="fc-mono">{row.coarseFrags}</td>
              <td class="fc-mono">{row.roots}</td>
              <td class="fc-mono">{row.structure}</td>
              <td class="fc-mono">{row.ph}</td>
              <td>{row.comments}</td>
            </tr>
          {:else}
            <tr><td colspan="9" class="fc-empty-cell">No mineral horizons recorded</td></tr>
          {/each}
        </tbody>
      </table>
    </section>
  </div>
{:else}
  <section class="fc-block">
    <div class="fc-block-header">
      <span
        >13. TREE &amp; SHRUB STRATA (LAYERS A &amp; B{viewModel.back.showExtendedShrubColumns
          ? ' + EXTENDED B3–B5'
          : ''})</span
      >
      <span class="fc-mono">{viewModel.back.treeShrubRows.length} spp.</span>
    </div>
    <table class="fc-ruled-table">
      <thead>
        <tr>
          <th>Species</th>
          <th>Col</th>
          <th>A1 %</th>
          <th>A1 Ht</th>
          <th>A2 %</th>
          <th>A2 Ht</th>
          <th>A3 %</th>
          <th>A3 Ht</th>
          <th>Tot A</th>
          <th>B1 %</th>
          <th>B1 Ht</th>
          <th>B2 %</th>
          <th>B2 Ht</th>
          {#if viewModel.back.showExtendedShrubColumns}
            <th>B3 %</th>
            <th>B4 %</th>
            <th>B5 %</th>
          {/if}
          <th>Tot B</th>
        </tr>
      </thead>
      <tbody>
        {#each viewModel.back.treeShrubRows as row (`ab-${row.id}`)}
          <tr class:fc-row-draft={row.isDraft}>
            <td class="fc-mono fc-bold">{row.species}</td>
            <td class="fc-mono">{row.collected}</td>
            <td class="fc-mono fc-num">{row.cover1}</td>
            <td class="fc-mono fc-num">{row.height1}</td>
            <td class="fc-mono fc-num">{row.cover2}</td>
            <td class="fc-mono fc-num">{row.height2}</td>
            <td class="fc-mono fc-num">{row.cover3}</td>
            <td class="fc-mono fc-num">{row.height3}</td>
            <td class="fc-mono fc-num fc-bold">{row.totalA}</td>
            <td class="fc-mono fc-num">{row.cover4}</td>
            <td class="fc-mono fc-num">{row.height4}</td>
            <td class="fc-mono fc-num">{row.cover5}</td>
            <td class="fc-mono fc-num">{row.height5}</td>
            {#if viewModel.back.showExtendedShrubColumns}
              <td class="fc-mono fc-num">{row.cover5a}</td>
              <td class="fc-mono fc-num">{row.cover5b}</td>
              <td class="fc-mono fc-num">{row.cover5c}</td>
            {/if}
            <td class="fc-mono fc-num fc-bold">{row.totalB}</td>
          </tr>
        {:else}
          <tr>
            <td colspan={viewModel.back.showExtendedShrubColumns ? 17 : 14} class="fc-empty-cell">
              No tree or shrub strata rows recorded
            </td>
          </tr>
        {/each}
      </tbody>
    </table>
  </section>

  <div class="fc-two-col">
    <section class="fc-block">
      <div class="fc-block-header">
        <span>14. HERB STRATUM (LAYER C)</span>
        <span class="fc-mono">{viewModel.back.herbRows.length} spp.</span>
      </div>
      <table class="fc-ruled-table">
        <thead>
          <tr>
            <th>Species</th>
            <th>Col</th>
            <th>C %</th>
            <th>C Ht</th>
          </tr>
        </thead>
        <tbody>
          {#each viewModel.back.herbRows as row (`c-${row.id}`)}
            <tr class:fc-row-draft={row.isDraft}>
              <td class="fc-mono fc-bold">{row.species}</td>
              <td class="fc-mono">{row.collected}</td>
              <td class="fc-mono fc-num">{row.cover6}</td>
              <td class="fc-mono fc-num">{row.height6}</td>
            </tr>
          {:else}
            <tr><td colspan="4" class="fc-empty-cell">No herb stratum rows recorded</td></tr>
          {/each}
        </tbody>
      </table>
    </section>

    <section class="fc-block">
      <div class="fc-block-header">
        <span>15. MOSS, LIVERWORT &amp; LICHEN STRATUM (LAYER D)</span>
        <span class="fc-mono">{viewModel.back.mossRows.length} spp.</span>
      </div>
      <table class="fc-ruled-table">
        <thead>
          <tr>
            <th>Species</th>
            <th>Col</th>
            <th>D (Soil/Humus) %</th>
            <th>Dw (Wood) %</th>
            <th>Dr (Rock) %</th>
          </tr>
        </thead>
        <tbody>
          {#each viewModel.back.mossRows as row (`d-${row.id}`)}
            <tr class:fc-row-draft={row.isDraft}>
              <td class="fc-mono fc-bold">{row.species}</td>
              <td class="fc-mono">{row.collected}</td>
              <td class="fc-mono fc-num">{row.cover7}</td>
              <td class="fc-mono fc-num">{row.cover8}</td>
              <td class="fc-mono fc-num">{row.cover9}</td>
            </tr>
          {:else}
            <tr><td colspan="5" class="fc-empty-cell">No moss / lichen rows recorded</td></tr>
          {/each}
        </tbody>
      </table>
    </section>
  </div>
{/if}
