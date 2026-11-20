<script lang="ts">
  import { onDestroy, tick, untrack } from 'svelte';
  import { Columns2, Maximize2, Printer, X } from '@lucide/svelte';
  import FieldCardVegSoilTables from './FieldCardVegSoilTables.svelte';
  import './fieldCardPreviewModal.css';
  import type { FieldCardCell, FieldCardSide, FieldCardTheme, FieldCardViewModel } from './fieldCardPreview';

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
          'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
        )
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

{#snippet sheetMasthead(suffix: string)}
  <header class="fc-sheet-masthead">
    <div>
      <div class="fc-ministry-line">{viewModel.ministryHeader}</div>
      <div class="fc-card-title">{viewModel.cardTitle} — {suffix}</div>
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
        <g transform="translate(2.5 0.5) scale(0.0263)">
          <path
            d="M512 162L216 286V512C216 681 342 827 512 864C682 827 808 681 808 512V286Z"
            fill="#1E5128"
            stroke="#FCBA19"
            stroke-width="48"
            stroke-linejoin="round"
          />
          <path d="M488 614H536L542 754Q512 764 482 754Z" fill="#FCBA19" />
          <path d="M512 454L698 654Q512 618 326 654Z" fill="#FFFFFF" />
          <path d="M512 344L656 518Q512 488 368 518Z" fill="#FFFFFF" />
          <path d="M512 244L614 396Q512 372 410 396Z" fill="#FFFFFF" />
        </g>
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
          onclick={() => (side = 'front')}>Front (Site &amp; Soil)</button
        >
        <button
          type="button"
          data-field-card-side="back"
          aria-pressed={side === 'back'}
          class:active={side === 'back'}
          onclick={() => (side = 'back')}>Back (Veg &amp; Notes)</button
        >
        <button
          type="button"
          data-field-card-side="both"
          aria-pressed={side === 'both'}
          class:active={side === 'both'}
          onclick={() => (side = 'both')}>Both Sides</button
        >
      </div>

      <div class="fc-segmented" role="group" aria-label="Paper appearance">
        <button
          type="button"
          data-field-card-theme="bw"
          aria-pressed={theme === 'bw'}
          class:active={theme === 'bw'}
          onclick={() => (theme = 'bw')}>Crisp B&amp;W Print</button
        >
        <button
          type="button"
          data-field-card-theme="classic"
          aria-pressed={theme === 'classic'}
          class:active={theme === 'classic'}
          onclick={() => (theme = 'classic')}>LMH25 Field Card Classic</button
        >
      </div>

      {#if onmodechange}
        <button
          type="button"
          class="fc-action-btn fc-dock-switch"
          data-field-card-mode-switch
          onclick={() => onmodechange(mode === 'modal' ? 'docked' : 'modal')}
          title={mode === 'modal' ? 'Dock as live split-pane preview' : 'Expand to fullscreen modal'}
        >
          {#if mode === 'modal'}<Columns2 size={14} /> Dock Split{:else}<Maximize2 size={14} /> Full Modal{/if}
        </button>
      {/if}

      <button type="button" class="fc-action-btn fc-print-btn" data-field-card-print onclick={printCard}>
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
        {@render sheetMasthead('FRONT (SITE & SOIL)')}

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

        <FieldCardVegSoilTables section="soil" {viewModel} />

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
      <article class="fc-sheet" data-field-card-sheet="back" aria-label="Field Card Back — Vegetation and Notes">
        {@render sheetMasthead('BACK (VEGETATION)')}

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

        <FieldCardVegSoilTables section="veg" {viewModel} />

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
