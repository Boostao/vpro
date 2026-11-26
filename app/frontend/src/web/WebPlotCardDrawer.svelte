<script lang="ts">
  import { Loader2, X } from '@lucide/svelte';
  import { ContextService } from '../../bindings/github.com/boostao/vpro/app';
  import type { PlotBundle } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
  import FieldCardPreviewModal from '../entry/FieldCardPreviewModal.svelte';
  import { buildFieldCardViewModel, type FieldCardViewModel } from '../entry/fieldCardPreview';
  import { formatError } from '../shared/readRequests';

  let {
    contextId,
    plotNumber,
    onclose,
    fetchBundle = (ctxId: string, plot: string) => ContextService.GetPlotBundle(ctxId, plot, false),
  }: {
    contextId: string;
    plotNumber: string | null;
    onclose: () => void;
    fetchBundle?: (ctxId: string, plot: string) => Promise<PlotBundle | null>;
  } = $props();

  let loading = $state(false);
  let errorMsg = $state('');
  let viewModel = $state<FieldCardViewModel | null>(null);
  let loadGeneration = 0;

  function toRecord(value: unknown): Record<string, unknown> {
    return value && typeof value === 'object' ? (value as Record<string, unknown>) : {};
  }

  async function loadPlotCard(ctxId: string, plot: string) {
    const gen = ++loadGeneration;
    loading = true;
    errorMsg = '';
    viewModel = null;
    try {
      const bundle = await fetchBundle(ctxId, plot);
      if (gen !== loadGeneration) return;
      if (!bundle || !bundle.header) {
        errorMsg = `Plot ${plot} could not be found in the active dataset.`;
        return;
      }
      viewModel = buildFieldCardViewModel({
        formKind: 'fs882',
        committedHeader: toRecord(bundle.header),
        humusRows: (bundle.humus ?? []).map(toRecord),
        mineralRows: (bundle.mineral ?? []).map(toRecord),
        vegRows: (bundle.vegetation?.records ?? []).map(toRecord),
        isDirty: false,
      });
    } catch (cause) {
      if (gen !== loadGeneration) return;
      errorMsg = `Could not load FS882 card for plot ${plot}: ${formatError(cause)}`;
    } finally {
      if (gen === loadGeneration) {
        loading = false;
      }
    }
  }

  $effect(() => {
    const plot = plotNumber?.trim() ?? '';
    const ctxId = contextId.trim();
    if (!plot || !ctxId) {
      loadGeneration++;
      loading = false;
      errorMsg = '';
      viewModel = null;
      return;
    }
    void loadPlotCard(ctxId, plot);
  });

  function handleKeydown(event: KeyboardEvent) {
    if (event.key === 'Escape' && plotNumber && !viewModel) {
      event.preventDefault();
      onclose();
    }
  }
</script>

<svelte:window onkeydown={handleKeydown} />

{#if plotNumber}
  {#if viewModel}
    <FieldCardPreviewModal
      open={true}
      mode="modal"
      {viewModel}
      initialSide="both"
      initialTheme="classic"
      {onclose}
    />
  {:else}
    <!-- svelte-ignore a11y_click_events_have_key_events -->
    <div
      class="web-plot-drawer-backdrop"
      role="dialog"
      aria-modal="true"
      aria-label={`FS882 Field Card — Plot ${plotNumber}`}
      tabindex="-1"
      data-web-plot-card-loading={loading ? 'true' : 'false'}
      onclick={(event) => {
        if (event.target === event.currentTarget) onclose();
      }}
    >
      <div class="web-plot-drawer-box">
        <header class="web-plot-drawer-head">
          <div class="web-plot-drawer-title">
            FS882 Field Card — Plot <span class="font-mono">{plotNumber}</span>
          </div>
          <button
            type="button"
            class="web-plot-drawer-close"
            aria-label="Close plot card"
            onclick={onclose}
          >
            <X size={16} aria-hidden="true" />
          </button>
        </header>

        <div class="web-plot-drawer-body">
          {#if loading}
            <div class="web-plot-drawer-status" role="status">
              <Loader2 size={18} class="animate-spin text-vpro-navy" aria-hidden="true" />
              <span>Loading formatted FS882 field card for plot {plotNumber}...</span>
            </div>
          {:else if errorMsg}
            <div class="web-plot-drawer-error" role="alert">
              <p>{errorMsg}</p>
              <div class="web-plot-drawer-actions">
                <button
                  type="button"
                  class="web-retry-btn"
                  onclick={() => plotNumber && void loadPlotCard(contextId, plotNumber)}
                >
                  Retry
                </button>
                <button type="button" class="web-close-text-btn" onclick={onclose}>Close</button>
              </div>
            </div>
          {/if}
        </div>
      </div>
    </div>
  {/if}
{/if}

<style>
  .web-plot-drawer-backdrop {
    position: fixed;
    inset: 0;
    z-index: 120;
    background: rgba(0, 34, 68, 0.56);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 20px;
  }

  .web-plot-drawer-box {
    width: min(480px, 100%);
    background: var(--vpro-surface, #ffffff);
    border: 1px solid var(--vpro-navy, #003366);
    border-top: 4px solid var(--vpro-gold, #fcba19);
    border-radius: 6px;
    box-shadow: var(--vpro-shadow-lg, 0 14px 34px rgba(0, 34, 68, 0.25));
    overflow: hidden;
  }

  .web-plot-drawer-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 10px 14px;
    background: var(--vpro-navy, #003366);
    color: #ffffff;
  }

  .web-plot-drawer-title {
    font-size: 13.5px;
    font-weight: 700;
  }

  .web-plot-drawer-close {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 28px;
    height: 28px;
    border-radius: 4px;
    border: 1px solid rgba(255, 255, 255, 0.25);
    background: transparent;
    color: #ffffff;
    cursor: pointer;
  }

  .web-plot-drawer-close:hover {
    background: rgba(255, 255, 255, 0.14);
  }

  .web-plot-drawer-body {
    padding: 18px 16px;
  }

  .web-plot-drawer-status {
    display: flex;
    align-items: center;
    gap: 10px;
    font-size: 13px;
    color: var(--vpro-ink, #313132);
  }

  .web-plot-drawer-error p {
    margin: 0 0 12px;
    font-size: 13px;
    color: var(--vpro-error-ink, #a61b20);
  }

  .web-plot-drawer-actions {
    display: flex;
    gap: 8px;
  }

  .web-retry-btn {
    padding: 6px 12px;
    border-radius: 4px;
    border: 1px solid var(--vpro-navy, #003366);
    background: var(--vpro-navy, #003366);
    color: #ffffff;
    font-size: 12px;
    font-weight: 700;
    cursor: pointer;
  }

  .web-close-text-btn {
    padding: 6px 12px;
    border-radius: 4px;
    border: 1px solid var(--vpro-border-strong, #9ca3af);
    background: #ffffff;
    color: var(--vpro-ink, #313132);
    font-size: 12px;
    font-weight: 600;
    cursor: pointer;
  }
</style>
