<script lang="ts">
  import { onDestroy, tick, untrack } from 'svelte';
  import { Columns2, Maximize2, Printer, X } from '@lucide/svelte';
  import type {
    FieldCardCell,
    FieldCardSide,
    FieldCardTheme,
    FieldCardViewModel,
  } from './fieldCardPreview';

  let {
    open = true,
    mode = 'modal',
    viewModel,
    initialSide = 'both',
    initialTheme = 'classic',
    onclose,
    onmodechange,
  }: {
    open?: boolean;
    mode?: 'modal' | 'docked';
    viewModel: FieldCardViewModel;
    initialSide?: FieldCardSide;
    initialTheme?: FieldCardTheme;
    onclose: () => void;
    onmodechange?: (nextMode: 'modal' | 'docked') => void;
  } = $props();

  let side = $state<FieldCardSide>(untrack(() => initialSide));
  let theme = $state<FieldCardTheme>(untrack(() => initialTheme));
  let dialogRef = $state<HTMLElement | null>(null);
  let closeButtonRef = $state<HTMLButtonElement | null>(null);
  let previousFocus: HTMLElement | null = null;

  function restorePreviousFocus() {
    const target = previousFocus;
    previousFocus = null;
    if (target && typeof target.focus === 'function') {
      try {
        target.focus();
      } catch {
        // Ignore detached focus target
      }
    }
  }

  function closeCard() {
    onclose();
    if (mode === 'modal') {
      restorePreviousFocus();
    }
  }

  $effect(() => {
    if (open && mode === 'modal' && typeof document !== 'undefined') {
      if (!previousFocus && document.activeElement instanceof HTMLElement) {
        previousFocus = document.activeElement;
      }
      void tick().then(() => {
        closeButtonRef?.focus();
      });
    } else if (!open && previousFocus) {
      restorePreviousFocus();
    }
  });

  onDestroy(() => {
    if (previousFocus) {
      restorePreviousFocus();
    }
  });

  function handleModalKeydownCapture(event: KeyboardEvent) {
    if (!open || mode !== 'modal') return;
    if (event.key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation?.();
      closeCard();
      return;
    }
    if (event.key === 'Tab' && dialogRef) {
      const focusables = Array.from(
        dialogRef.querySelectorAll<HTMLElement>(
          'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
        ),
      );
      if (focusables.length === 0) {
        event.preventDefault();
        return;
      }
      const first = focusables[0];
      const last = focusables[focusables.length - 1];
      const active = typeof document !== 'undefined' ? document.activeElement : null;
      if (event.shiftKey && (active === first || !dialogRef.contains(active))) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && active === last) {
        event.preventDefault();
        first.focus();
      }
    }
  }

  function printCard() {
    if (typeof window !== 'undefined' && typeof window.print === 'function') {
      window.print();
    }
  }
</script>

<svelte:window onkeydowncapture={handleModalKeydownCapture} />

{#snippet ruledCells(cells: readonly FieldCardCell[])}
  <div class="fc-cell-grid">
    {#each cells as item (item.key)}
      <div
        class="fc-cell"
        class:fc-cell-draft={item.isDraft}
        style={`grid-column: span ${item.span ?? 3};`}
        data-fc-field={item.key}
      >
        <span class="fc-cell-label">{item.label}</span>
        <span class="fc-cell-value" class:fc-mono={item.mono}>{item.value}</span>
      </div>
    {/each}
  </div>
{/snippet}

{#snippet cardToolbar()}
  <header class="field-card-toolbar">
    <div class="fc-toolbar-title">
      <svg
        width={24}
        height={24}
        viewBox="0 0 32 32"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        aria-hidden="true"
        focusable="false"
        data-vpro-crest="badge"
      >
        <rect width="32" height="32" rx="6" fill="#003366" />
        <rect y="28" width="32" height="4" fill="#FCBA19" />
        <path
          d="M16 4.2L7.2 8v6.6c0 5.9 3.75 11.05 8.8 12.35 5.05-1.3 8.8-6.45 8.8-12.35V8L16 4.2z"
          fill="#002244"
          stroke="#FCBA19"
          stroke-width="1.65"
          stroke-linejoin="round"
        />
        <path
          d="M16 9.2v11.3M12.2 14l3.8-4.1 3.8 4.1M11 17.8l5-4.5 5 4.5"
          stroke="#FFFFFF"
          stroke-width="1.85"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
      </svg>
      <div>
        <h2 id="field-card-modal-title" class="fc-toolbar-heading">
          {viewModel.formCode} — Plot <span class="fc-mono">{viewModel.plotNumber}</span>
        </h2>
        <span class="fc-toolbar-sub">{viewModel.becUnitMask} · {viewModel.formattedCoordinates}</span>
      </div>
      {#if viewModel.isDirty}
        <span class="fc-dirty-badge" data-field-card-dirty-badge role="status">UNSAVED DRAFT</span>
      {/if}
    </div>

    <div class="fc-toolbar-controls">
      <div class="fc-segmented" role="group" aria-label="Field card side">
        <button
          type="button"
          data-field-card-side="front"
          aria-pressed={side === 'front'}
          class:active={side === 'front'}
          onclick={() => (side = 'front')}
        >
          Front (Site &amp; Soil)
        </button>
        <button
          type="button"
          data-field-card-side="back"
          aria-pressed={side === 'back'}
          class:active={side === 'back'}
          onclick={() => (side = 'back')}
        >
          Back (Veg &amp; Notes)
        </button>
        <button
          type="button"
          data-field-card-side="both"
          aria-pressed={side === 'both'}
          class:active={side === 'both'}
          onclick={() => (side = 'both')}
        >
          Both Sides
        </button>
      </div>

      <div class="fc-segmented" role="group" aria-label="Paper appearance">
        <button
          type="button"
          data-field-card-theme="bw"
          aria-pressed={theme === 'bw'}
          class:active={theme === 'bw'}
          onclick={() => (theme = 'bw')}
        >
          Crisp B&amp;W Print
        </button>
        <button
          type="button"
          data-field-card-theme="classic"
          aria-pressed={theme === 'classic'}
          class:active={theme === 'classic'}
          onclick={() => (theme = 'classic')}
        >
          LMH25 Field Card Classic
        </button>
      </div>

      {#if onmodechange}
        <button
          type="button"
          class="fc-action-btn fc-dock-switch"
          data-field-card-mode-switch
          onclick={() => onmodechange(mode === 'modal' ? 'docked' : 'modal')}
          title={mode === 'modal' ? 'Dock as live split-pane preview' : 'Expand to fullscreen modal'}
        >
          {#if mode === 'modal'}
            <Columns2 size={14} /> Dock Split
          {:else}
            <Maximize2 size={14} /> Full Modal
          {/if}
        </button>
      {/if}

      <button
        type="button"
        class="fc-action-btn fc-print-btn"
        data-field-card-print
        onclick={printCard}
      >
        <Printer size={14} /> Print / Save PDF
      </button>

      <button
        bind:this={closeButtonRef}
        type="button"
        class="fc-close-btn"
        data-field-card-close
        aria-label="Close field card preview"
        onclick={closeCard}
      >
        <X size={16} />
      </button>
    </div>
  </header>
{/snippet}

{#snippet cardSheets()}
  <div class="field-card-sheets" data-paper-theme={theme}>
    {#if side === 'front' || side === 'both'}
      <article
        class="fc-sheet"
        class:fc-page-break-after={side === 'both'}
        data-field-card-sheet="front"
        aria-label="Field Card Front — Site and Soil"
      >
        <header class="fc-sheet-masthead">
          <div>
            <div class="fc-ministry-line">{viewModel.ministryHeader}</div>
            <div class="fc-card-title">{viewModel.cardTitle} — FRONT (SITE &amp; SOIL)</div>
          </div>
          <div class="fc-masthead-right">
            {#if viewModel.isDirty}
              <span class="fc-sheet-stamp">UNSAVED DRAFT</span>
            {/if}
            <div class="fc-plot-box">
              <span class="fc-cell-label">PLOT NO.</span>
              <strong class="fc-mono fc-plot-id">{viewModel.plotNumber}</strong>
            </div>
          </div>
        </header>

        <section class="fc-block">
          <div class="fc-block-header">1. PLOT IDENTITY &amp; SURVEY</div>
          {@render ruledCells(viewModel.front.identityCells)}
        </section>

        <div class="fc-two-col">
          <section class="fc-block">
            <div class="fc-block-header">2. LOCATION &amp; COORDINATES</div>
            {@render ruledCells(viewModel.front.locationCells)}
          </section>

          <section class="fc-block">
            <div class="fc-block-header">
              <span>3. BEC &amp; EDATOPIC CLASSIFICATION</span>
              <span class="fc-mono">{viewModel.becUnitMask}</span>
            </div>
            {@render ruledCells(viewModel.front.becEdatopicCells)}
          </section>
        </div>

        <section class="fc-block">
          <div class="fc-block-header">4. TOPOGRAPHY, EXPOSURE, DISTURBANCE &amp; QUALITY</div>
          {@render ruledCells(viewModel.front.topographyQualityCells)}
        </section>

        <section class="fc-block" data-fc-substrate-strip>
          <div class="fc-block-header">
            <span>5. SUBSTRATE COVER (%)</span>
            <span class="fc-mono">TOTAL: {viewModel.substrateTotalDisplay}</span>
          </div>
          {@render ruledCells(viewModel.front.substrateCells)}
        </section>

        <section class="fc-block">
          <div class="fc-block-header">6. TERRAIN &amp; GEOLOGY (SURFACE / SUBSURFACE)</div>
          {@render ruledCells(viewModel.front.surfaceTerrainCells)}
          {@render ruledCells(viewModel.front.subsurfaceTerrainCells)}
          {@render ruledCells(viewModel.front.geologyCells)}
        </section>

        <section class="fc-block">
          <div class="fc-block-header">7. SOIL CLASSIFICATION, HUMUS FORM, HYDROGEOLOGY &amp; DRAINAGE</div>
          {@render ruledCells(viewModel.front.soilSummaryCells)}
        </section>

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

        <section class="fc-block">
          <div class="fc-block-header">10. SITE, OFFICE &amp; SOIL NOTES</div>
          <div class="fc-notes-grid">
            <div class="fc-note-box">
              <span class="fc-cell-label">FIELD / SITE NOTES</span>
              <p>{viewModel.front.notes.siteNotes}</p>
            </div>
            <div class="fc-note-box">
              <span class="fc-cell-label">OFFICE NOTES</span>
              <p>{viewModel.front.notes.officeNotes}</p>
            </div>
            <div class="fc-note-box">
              <span class="fc-cell-label">SOIL NOTES</span>
              <p>{viewModel.front.notes.soilNotes}</p>
            </div>
          </div>
        </section>
      </article>
    {/if}

    {#if side === 'back' || side === 'both'}
      <article
        class="fc-sheet"
        data-field-card-sheet="back"
        aria-label="Field Card Back — Vegetation and Notes"
      >
        <header class="fc-sheet-masthead">
          <div>
            <div class="fc-ministry-line">{viewModel.ministryHeader}</div>
            <div class="fc-card-title">{viewModel.cardTitle} — BACK (VEGETATION)</div>
          </div>
          <div class="fc-masthead-right">
            {#if viewModel.isDirty}
              <span class="fc-sheet-stamp">UNSAVED DRAFT</span>
            {/if}
            <div class="fc-plot-box">
              <span class="fc-cell-label">PLOT NO.</span>
              <strong class="fc-mono fc-plot-id">{viewModel.plotNumber}</strong>
            </div>
          </div>
        </header>

        <div class="fc-two-col">
          <section class="fc-block">
            <div class="fc-block-header">11. VEGETATION SURVEY</div>
            {@render ruledCells(viewModel.back.vegSurveyCells)}
          </section>

          <section class="fc-block">
            <div class="fc-block-header">12. STRATUM COVER (%)</div>
            {@render ruledCells(viewModel.back.strataCoverCells)}
          </section>
        </div>

        <section class="fc-block">
          <div class="fc-block-header">
            <span>13. TREE &amp; SHRUB STRATA (LAYERS A &amp; B{viewModel.back.showExtendedShrubColumns ? ' + EXTENDED B3–B5' : ''})</span>
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

        <section class="fc-block">
          <div class="fc-block-header">16. VEGETATION NOTES</div>
          <div class="fc-note-box">
            <span class="fc-cell-label">VEGETATION &amp; FLORISTIC NOTES</span>
            <p>{viewModel.back.vegNotes}</p>
          </div>
        </section>
      </article>
    {/if}
  </div>
{/snippet}

{#if open}
  {#if mode === 'modal'}
    <div
      class="field-card-backdrop"
      data-field-card-active
      data-field-card-modal
      role="dialog"
      aria-modal="true"
      aria-labelledby="field-card-modal-title"
      tabindex="-1"
      bind:this={dialogRef}
      onkeydowncapture={handleModalKeydownCapture}
      onkeydown={handleModalKeydownCapture}
      onclick={(event) => {
        if (event.target === event.currentTarget) closeCard();
      }}
    >
      <div class="field-card-modal-panel">
        {@render cardToolbar()}
        <div class="field-card-scroll">
          {@render cardSheets()}
        </div>
      </div>
    </div>
  {:else}
    <aside
      class="field-card-dock"
      data-field-card-active
      data-field-card-dock
      aria-label="Docked Field Card Live Preview"
    >
      {@render cardToolbar()}
      <div class="field-card-scroll">
        {@render cardSheets()}
      </div>
    </aside>
  {/if}
{/if}

<style>
  .field-card-backdrop {
    position: fixed;
    inset: 0;
    z-index: 60;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 1.25rem;
    background: rgba(0, 22, 44, 0.62);
    backdrop-filter: blur(2px);
  }

  .field-card-modal-panel {
    display: flex;
    flex-direction: column;
    width: min(1240px, 96vw);
    height: min(92vh, 1080px);
    background: var(--vpro-canvas, #f2f4f6);
    border: 1px solid var(--vpro-navy, #003366);
    border-top: 4px solid var(--vpro-gold, #fcba19);
    border-radius: 6px;
    box-shadow: var(--vpro-shadow-lg, 0 14px 34px rgba(0, 34, 68, 0.28));
    overflow: hidden;
  }

  .field-card-dock {
    display: flex;
    flex-direction: column;
    min-width: 0;
    width: 100%;
    height: 100%;
    max-height: 100%;
    background: var(--vpro-canvas, #f2f4f6);
    border-left: 2px solid var(--vpro-navy, #003366);
    overflow: hidden;
  }

  .field-card-toolbar {
    flex: none;
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 0.6rem;
    padding: 0.6rem 0.9rem;
    background: var(--vpro-navy, #003366);
    color: #ffffff;
    border-bottom: 2px solid var(--vpro-gold, #fcba19);
  }

  .fc-toolbar-title {
    display: flex;
    align-items: center;
    gap: 0.6rem;
    min-width: 0;
  }

  .fc-toolbar-heading {
    margin: 0;
    font-size: 0.92rem;
    font-weight: 700;
    color: #ffffff;
    line-height: 1.25;
  }

  .fc-toolbar-sub {
    display: block;
    font-size: 0.72rem;
    color: #dbe7f3;
    font-variant-numeric: tabular-nums;
  }

  .fc-dirty-badge {
    display: inline-flex;
    align-items: center;
    padding: 0.15rem 0.5rem;
    border-radius: 3px;
    background: var(--vpro-gold, #fcba19);
    color: #111827;
    font-family: var(--vpro-font-mono, monospace);
    font-size: 0.68rem;
    font-weight: 700;
    letter-spacing: 0.04em;
    white-space: nowrap;
  }

  .fc-toolbar-controls {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.45rem;
  }

  .fc-segmented {
    display: inline-flex;
    border: 1px solid rgba(255, 255, 255, 0.35);
    border-radius: 4px;
    overflow: hidden;
  }

  .fc-segmented button {
    padding: 0.3rem 0.55rem;
    border: 0;
    border-right: 1px solid rgba(255, 255, 255, 0.22);
    background: rgba(255, 255, 255, 0.08);
    color: #e6eef7;
    font-size: 0.72rem;
    font-weight: 600;
    white-space: nowrap;
  }

  .fc-segmented button:last-child {
    border-right: 0;
  }

  .fc-segmented button.active {
    background: #ffffff;
    color: var(--vpro-navy, #003366);
  }

  .fc-action-btn {
    display: inline-flex;
    align-items: center;
    gap: 0.3rem;
    padding: 0.32rem 0.65rem;
    border-radius: 4px;
    border: 1px solid rgba(255, 255, 255, 0.4);
    background: rgba(255, 255, 255, 0.12);
    color: #ffffff;
    font-size: 0.73rem;
    font-weight: 600;
    white-space: nowrap;
  }

  .fc-print-btn {
    background: var(--vpro-forest, #1e5128);
    border-color: #65a373;
  }

  .fc-action-btn:hover {
    background: rgba(255, 255, 255, 0.24);
  }

  .fc-print-btn:hover {
    background: var(--vpro-forest-dark, #153b1d);
  }

  .fc-close-btn {
    display: inline-grid;
    place-items: center;
    width: 32px;
    height: 32px;
    border-radius: 4px;
    border: 1px solid rgba(255, 255, 255, 0.35);
    background: rgba(255, 255, 255, 0.1);
    color: #ffffff;
  }

  .fc-close-btn:hover {
    background: var(--vpro-error, #d8292f);
    border-color: #ffffff;
  }

  .field-card-scroll {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    padding: 1rem;
  }

  .field-card-sheets {
    display: flex;
    flex-direction: column;
    gap: 1.25rem;
    max-width: 1080px;
    margin: 0 auto;
    --fc-paper: #faf8f0;
    --fc-ink: #1b2a22;
    --fc-rule: #2c4235;
    --fc-rule-hair: #7a9182;
    --fc-band: #dce6de;
    --fc-band-ink: #102a1d;
    --fc-draft-bg: #fef3c7;
  }

  .field-card-sheets[data-paper-theme='bw'] {
    --fc-paper: #ffffff;
    --fc-ink: #000000;
    --fc-rule: #000000;
    --fc-rule-hair: #222222;
    --fc-band: #eeeeee;
    --fc-band-ink: #000000;
    --fc-draft-bg: #f3f4f6;
  }

  .fc-sheet {
    container-type: inline-size;
    background: var(--fc-paper);
    color: var(--fc-ink);
    border: 2px solid var(--fc-rule);
    padding: 0.75rem;
    box-shadow: 0 3px 10px rgba(0, 0, 0, 0.12);
    font-size: 0.75rem;
    line-height: 1.3;
  }

  .fc-sheet-masthead {
    display: flex;
    align-items: stretch;
    justify-content: space-between;
    gap: 0.75rem;
    border-bottom: 2px solid var(--fc-rule);
    padding-bottom: 0.45rem;
    margin-bottom: 0.55rem;
  }

  .fc-ministry-line {
    font-size: 0.65rem;
    font-weight: 700;
    letter-spacing: 0.06em;
    text-transform: uppercase;
  }

  .fc-card-title {
    font-size: 0.92rem;
    font-weight: 700;
    letter-spacing: 0.02em;
    margin-top: 0.1rem;
  }

  .fc-masthead-right {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .fc-sheet-stamp {
    padding: 0.15rem 0.45rem;
    border: 1.5px solid var(--fc-rule);
    font-family: var(--vpro-font-mono, monospace);
    font-size: 0.65rem;
    font-weight: 700;
    background: var(--fc-draft-bg);
  }

  .fc-plot-box {
    border: 1.5px solid var(--fc-rule);
    padding: 0.2rem 0.55rem;
    min-width: 7rem;
    background: rgba(255, 255, 255, 0.55);
  }

  .fc-plot-id {
    display: block;
    font-size: 0.95rem;
  }

  .fc-two-col {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 0.5rem;
  }

  @media (max-width: 820px) {
    .fc-two-col {
      grid-template-columns: minmax(0, 1fr);
    }
  }

  @container (max-width: 720px) {
    .fc-two-col {
      grid-template-columns: minmax(0, 1fr);
    }
  }

  .fc-block {
    border: 1px solid var(--fc-rule);
    margin-bottom: 0.5rem;
    min-width: 0;
  }

  .fc-block-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.5rem;
    padding: 0.2rem 0.45rem;
    background: var(--fc-band);
    color: var(--fc-band-ink);
    border-bottom: 1px solid var(--fc-rule);
    font-size: 0.64rem;
    font-weight: 700;
    letter-spacing: 0.05em;
    text-transform: uppercase;
  }

  .fc-cell-grid {
    display: grid;
    grid-template-columns: repeat(12, minmax(0, 1fr));
  }

  .fc-cell {
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    min-width: 0;
    padding: 0.22rem 0.38rem;
    border-right: 1px solid var(--fc-rule-hair);
    border-bottom: 1px solid var(--fc-rule-hair);
  }

  .fc-cell-draft,
  .fc-row-draft {
    background: var(--fc-draft-bg);
  }

  .fc-cell-label {
    display: block;
    font-size: 0.58rem;
    font-weight: 700;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    opacity: 0.85;
    line-height: 1.15;
  }

  .fc-cell-value {
    display: block;
    margin-top: 0.12rem;
    font-size: 0.76rem;
    min-height: 1rem;
    overflow-wrap: anywhere;
  }

  .fc-mono {
    font-family: var(--vpro-font-mono, monospace);
    font-variant-numeric: tabular-nums;
  }

  .fc-bold {
    font-weight: 700;
  }

  .fc-num {
    text-align: right;
  }

  .fc-ruled-table {
    width: 100%;
    min-width: 0;
    border-collapse: collapse;
    font-size: 0.7rem;
    font-variant-numeric: tabular-nums;
  }

  .fc-ruled-table th {
    background: var(--fc-band);
    color: var(--fc-band-ink);
    font-size: 0.58rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.03em;
    padding: 0.2rem 0.3rem;
    border-bottom: 1px solid var(--fc-rule);
    border-right: 1px solid var(--fc-rule-hair);
    white-space: nowrap;
  }

  .fc-ruled-table td {
    padding: 0.2rem 0.3rem;
    border-bottom: 1px solid var(--fc-rule-hair);
    border-right: 1px solid var(--fc-rule-hair);
    white-space: normal;
    max-width: none;
    color: var(--fc-ink);
  }

  .fc-empty-cell {
    text-align: center;
    font-style: italic;
    opacity: 0.72;
    padding: 0.35rem;
  }

  .fc-notes-grid {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }

  @media (max-width: 720px) {
    .fc-notes-grid {
      grid-template-columns: minmax(0, 1fr);
    }
  }

  .fc-note-box {
    padding: 0.3rem 0.45rem;
    border-right: 1px solid var(--fc-rule-hair);
    min-height: 3.2rem;
  }

  .fc-note-box:last-child {
    border-right: 0;
  }

  .fc-note-box p {
    margin: 0.2rem 0 0;
    white-space: pre-wrap;
    font-size: 0.73rem;
  }

  @media (max-width: 1759px) {
    .fc-dock-switch {
      display: none;
    }
  }

  @page {
    size: letter portrait;
    margin: 10mm;
  }

  @media print {
    :global(body:has([data-field-card-active]) .topbar),
    :global(body:has([data-field-card-active]) .sidebar),
    :global(body:has([data-field-card-active]) .detail),
    :global(body:has([data-field-card-active]) .fs882-toolbar),
    :global(body:has([data-field-card-active]) .fs882-tabs),
    :global(body:has([data-field-card-active]) [data-field-card-form-pane]) {
      display: none !important;
    }

    .field-card-toolbar {
      display: none !important;
    }

    .field-card-backdrop,
    .field-card-modal-panel,
    .field-card-dock,
    .field-card-scroll {
      position: static !important;
      width: 100% !important;
      height: auto !important;
      max-height: none !important;
      padding: 0 !important;
      border: 0 !important;
      background: transparent !important;
      box-shadow: none !important;
      overflow: visible !important;
    }

    .fc-sheet {
      box-shadow: none !important;
      margin: 0 !important;
      break-inside: avoid-page;
    }

    .fc-page-break-after {
      break-after: page;
      page-break-after: always;
    }
  }
</style>
