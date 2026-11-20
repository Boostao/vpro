<script lang="ts">
  import { ChevronLeft, ChevronRight, RefreshCw, X } from '@lucide/svelte';
  import type { HierarchyNode, PlotPage } from '../../bindings/github.com/boostao/vpro/app';
  import type { PlotSummary } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
  import { formatError } from '../shared/readRequests';
  import { projectState } from '../shared/state';

  let {
    region = 'main',
    view = 'plots',
    busy = false,
    error = '',
    page = null,
    allPlots = [],
    offset = 0,
    pageSize = 25,
    hierarchyNodes = [],
    selected = $bindable(null),
    siviAvailable = true,
    canUndoSelectedPlot = false,
    editorBusy = false,
    transitionWorking = false,
    pendingTransition = null,
    onrefresh = () => {},
    onloadpage = () => {},
    onopenfs882 = () => {},
    onopentwopage = () => {},
    onopensivi = () => {},
    onopenexplorer = () => {},
    onopenprofiling,
    oncollapseinspector = () => {},
    onselectplot = () => {},
    oncopyplot,
    onremoveplot,
  }: {
    region?: 'main' | 'detail';
    view?: string;
    busy?: boolean;
    error?: string;
    page?: PlotPage | null;
    allPlots?: PlotSummary[];
    offset?: number;
    pageSize?: number;
    hierarchyNodes?: HierarchyNode[];
    selected?: PlotSummary | null;
    siviAvailable?: boolean;
    canUndoSelectedPlot?: boolean;
    editorBusy?: boolean;
    transitionWorking?: boolean;
    pendingTransition?: unknown;
    onrefresh?: () => void;
    onloadpage?: (nextOffset: number) => void;
    onopenfs882?: () => void;
    onopentwopage?: () => void;
    onopensivi?: () => void;
    onopenexplorer?: () => void;
    onopenprofiling?: () => void;
    oncollapseinspector?: () => void;
    onselectplot?: (plot: PlotSummary) => void;
    oncopyplot?: (sourcePlot: string, targetPlot: string) => Promise<void>;
    onremoveplot?: (sourcePlot: string, cleanProjectName: string) => Promise<void>;
  } = $props();

  let plotFilter = $state('');
  let filterInputEl: HTMLInputElement | undefined = $state();
  let targetPlotDraft = $state('');
  let cleanProjectDraft = $state('');
  let actionBusy = $state(false);
  let actionError = $state('');
  let lastSelectedPlotForDraft = '';

  $effect(() => {
    const selPlot = selected?.plotNumber ?? '';
    if (selPlot !== lastSelectedPlotForDraft) {
      lastSelectedPlotForDraft = selPlot;
      targetPlotDraft = selPlot.trim().slice(0, 7);
      const baseProj = ($projectState?.activeProject ?? 'Project').replace(/[^A-Za-z0-9_]/g, '');
      cleanProjectDraft = `${(baseProj || 'Project').slice(0, 22)}_Clean`;
      actionError = '';
    }
  });

  const trimmedFilter = $derived(plotFilter.trim().toLowerCase());
  const displayedPlots = $derived.by(() => {
    if (!trimmedFilter) return page?.plots ?? [];
    const pool = allPlots.length > 0 ? allPlots : (page?.plots ?? []);
    return pool.filter((p) => {
      const hay =
        `${p.plotNumber ?? ''} ${p.fieldNumber ?? ''} ${p.plotRepresenting ?? ''} ${p.zone ?? ''} ${p.subZone ?? ''} ${p.siteSeries ?? ''}`.toLowerCase();
      return hay.includes(trimmedFilter);
    });
  });

  function handleWindowKeydown(event: KeyboardEvent) {
    if (region !== 'main' || view !== 'plots') return;
    if ((event.ctrlKey || event.metaKey) && !event.altKey && !event.shiftKey && event.key.toLowerCase() === 'f') {
      if (filterInputEl) {
        event.preventDefault();
        filterInputEl.focus();
        filterInputEl.select?.();
      }
    }
  }

  async function submitCopyPlot() {
    if (!selected || !oncopyplot || actionBusy) return;
    actionBusy = true;
    actionError = '';
    try {
      await oncopyplot(selected.plotNumber, targetPlotDraft);
    } catch (cause) {
      actionError = formatError(cause);
    } finally {
      actionBusy = false;
    }
  }

  async function submitRemovePlot() {
    if (!selected || !onremoveplot || actionBusy) return;
    actionBusy = true;
    actionError = '';
    try {
      await onremoveplot(selected.plotNumber, canUndoSelectedPlot ? '' : cleanProjectDraft);
    } catch (cause) {
      actionError = formatError(cause);
    } finally {
      actionBusy = false;
    }
  }
</script>

<svelte:window onkeydown={handleWindowKeydown} />

{#if region === 'detail'}
  {#if selected && view === 'plots'}
    <aside class="detail" aria-label="Selected plot">
      <div class="detail-header-row">
        <div class="eyebrow">SELECTED PLOT</div>
        <button
          type="button"
          class="icon-button"
          title="Collapse inspector"
          aria-label="Collapse inspector"
          onclick={oncollapseinspector}
        >
          <X size={15} />
        </button>
      </div>
      <h2 class="tabular-nums">{selected.plotNumber}</h2>
      <dl>
        <dt>Field number</dt>
        <dd class="tabular-nums">{selected.fieldNumber ?? '—'}</dd>
        <dt>Representing</dt>
        <dd>{selected.plotRepresenting ?? '—'}</dd>
        <dt>Zone</dt>
        <dd>{selected.zone ?? '—'}</dd>
        <dt>Subzone</dt>
        <dd>{selected.subZone ?? '—'}</dd>
        <dt>Site series</dt>
        <dd class="tabular-nums">{selected.siteSeries ?? '—'}</dd>
      </dl>
      <div class="mt-4 pt-3 border-t border-vpro-border">
        <button
          type="button"
          class="w-full py-2 px-3 bg-vpro-forest hover:bg-vpro-forest-dark text-white rounded text-xs font-semibold"
          onclick={onopenfs882}
        >
          Open in FS882 Editor
        </button>
        <button
          type="button"
          data-twopage-open
          class="mt-2 w-full py-2 px-3 border border-vpro-navy bg-white hover:bg-vpro-navy-tint text-vpro-navy rounded text-xs font-semibold"
          disabled={busy || editorBusy || transitionWorking || pendingTransition !== null}
          onclick={onopentwopage}
        >
          Open Two-Page (FS882-8x6XL)
        </button>
        {#if siviAvailable}
          <button
            type="button"
            data-sivi-standalone-open
            class="mt-2 w-full py-2 px-3 border border-vpro-navy text-vpro-navy hover:bg-vpro-navy-tint rounded text-xs font-semibold"
            disabled={busy || editorBusy || transitionWorking || pendingTransition !== null}
            onclick={onopensivi}>Open SIVI / FS1333</button
          >
        {/if}

        {#if oncopyplot || onremoveplot}
          <details
            class="mt-3 rounded border border-vpro-border bg-vpro-surface-subtle p-2.5 text-xs"
            data-plot-identity-actions
          >
            <summary class="cursor-pointer font-semibold text-vpro-navy">Rename or Remove Plot</summary>
            <div class="mt-2 space-y-2.5 text-vpro-ink-secondary">
              {#if actionError}
                <p
                  role="alert"
                  class="rounded border border-vpro-error bg-vpro-error-bg p-1.5 text-[11px] text-vpro-error-ink"
                >
                  {actionError}
                </p>
              {/if}

              {#if oncopyplot}
                <div class="space-y-1">
                  <label
                    for="inspector-copy-plot-input"
                    class="block text-[11px] font-semibold text-vpro-ink-secondary"
                  >
                    Copy to corrected Plot Number (up to 7 characters)
                  </label>
                  <div class="flex gap-1.5">
                    <input
                      id="inspector-copy-plot-input"
                      type="text"
                      maxlength="7"
                      data-copy-plot-input
                      class="min-w-0 flex-1 rounded border border-vpro-border bg-white px-2 py-1 font-mono text-xs"
                      placeholder="New plot #"
                      bind:value={targetPlotDraft}
                      disabled={busy || editorBusy || actionBusy}
                    />
                    <button
                      type="button"
                      data-copy-plot-btn
                      class="rounded bg-vpro-navy px-2.5 py-1 text-xs font-semibold text-white hover:bg-vpro-navy-dark disabled:opacity-50"
                      disabled={busy || editorBusy || actionBusy || !targetPlotDraft.trim()}
                      onclick={() => void submitCopyPlot()}
                    >
                      Copy
                    </button>
                  </div>
                </div>
              {/if}

              {#if onremoveplot}
                <div class="space-y-1 border-t border-vpro-border pt-2">
                  {#if canUndoSelectedPlot}
                    <p class="text-[11px] text-vpro-ink-secondary">
                      This newly created SIVI plot has no child rows and can be deleted directly.
                    </p>
                    <button
                      type="button"
                      data-undo-sivi-plot-btn
                      class="w-full rounded border border-vpro-error bg-white px-2.5 py-1.5 text-xs font-semibold text-vpro-error hover:bg-vpro-error-bg disabled:opacity-50"
                      disabled={busy || editorBusy || actionBusy}
                      onclick={() => void submitRemovePlot()}
                    >
                      Delete Newly Created Plot
                    </button>
                  {:else}
                    <label
                      for="inspector-clean-project-input"
                      class="block text-[11px] font-semibold text-vpro-ink-secondary"
                    >
                      Remove plot into clean project copy (keeps original .db backup)
                    </label>
                    <input
                      id="inspector-clean-project-input"
                      type="text"
                      maxlength="30"
                      data-exclude-plot-project-input
                      class="w-full rounded border border-vpro-border bg-white px-2 py-1 font-mono text-xs"
                      placeholder="Clean project name"
                      bind:value={cleanProjectDraft}
                      disabled={busy || editorBusy || actionBusy}
                    />
                    <button
                      type="button"
                      data-exclude-plot-splinter-btn
                      class="w-full rounded border border-vpro-error bg-white px-2.5 py-1.5 text-xs font-semibold text-vpro-error hover:bg-vpro-error-bg disabled:opacity-50"
                      disabled={busy || editorBusy || actionBusy || !cleanProjectDraft.trim()}
                      onclick={() => void submitRemovePlot()}
                    >
                      Save &amp; Switch Without Plot {selected.plotNumber}
                    </button>
                  {/if}
                </div>
              {/if}
            </div>
          </details>
        {/if}
      </div>
    </aside>
  {:else if view === 'home' || view === 'plots'}
    <aside class="detail" aria-label="Workspace inspector">
      <div class="detail-header-row">
        <div class="eyebrow">WORKSPACE INSPECTOR</div>
        <button
          type="button"
          class="icon-button"
          title="Collapse inspector"
          aria-label="Collapse inspector"
          onclick={oncollapseinspector}
        >
          <X size={15} />
        </button>
      </div>
      <h2>{$projectState?.activeProject ?? 'No project'}</h2>
      <dl>
        <dt>Active Site Unit</dt>
        <dd>{$projectState?.activeSU ?? 'None'}</dd>
        <dt>Active Hierarchy</dt>
        <dd>{$projectState?.activeHierarchy ?? 'None'}</dd>
        <dt>Plot Profile</dt>
        <dd>{$projectState?.plotProfile?.source?.name ?? 'None'}</dd>
        <dt>Plots in Scope</dt>
        <dd class="tabular-nums">{page?.total ?? 0}</dd>
      </dl>
      {#if onopenprofiling && $projectState?.contextId}
        <div class="mt-3 pt-3 border-t border-vpro-border">
          <button
            type="button"
            data-inspector-open-profiling
            class="w-full py-2 px-3 border border-vpro-navy bg-white hover:bg-vpro-navy-tint text-vpro-navy rounded text-xs font-semibold disabled:opacity-50"
            disabled={busy || editorBusy || transitionWorking || pendingTransition !== null}
            onclick={onopenprofiling}
          >
            Open Plot Profiling
          </button>
        </div>
      {/if}
      <p class="mt-4 text-xs text-vpro-ink-secondary leading-relaxed">
        Select a plot row to inspect BEC attributes, or press <kbd
          class="px-1 py-0.5 rounded border border-vpro-border bg-vpro-surface-subtle font-mono text-[11px]">Ctrl+K</kbd
        > to jump directly to any plot, report, or LMH25 topic.
      </p>
    </aside>
  {/if}
{:else if view === 'hierarchy'}
  <div class="content-heading">
    <div>
      <div class="eyebrow">{$projectState?.hierarchyFile ?? 'HIERARCHY'}</div>
      <h1>Hierarchy</h1>
    </div>
    <div class="flex flex-wrap items-center gap-2">
      <button
        type="button"
        data-open-classification-explorer
        class="rounded border border-vpro-navy bg-white px-3 py-1.5 text-xs font-semibold text-vpro-navy hover:bg-vpro-navy-tint"
        onclick={onopenexplorer}
      >
        Open SU &amp; Hierarchy Explorer
      </button>
      <button
        class="icon-button"
        title="Refresh hierarchy"
        aria-label="Refresh hierarchy"
        disabled={busy}
        onclick={onrefresh}><RefreshCw size={18} strokeWidth={1.8} /></button
      >
    </div>
  </div>
  <div class="table-bar">
    <span>{hierarchyNodes.length} units</span><span>{$projectState?.activeHierarchy ?? 'None'}</span>
  </div>
  <div class="table-scroll">
    <table>
      <thead><tr><th>Unit</th><th>ID</th><th>Parent ID</th><th>Level</th></tr></thead>
      <tbody>
        {#each hierarchyNodes as node (node.id)}
          <tr
            ><td>{node.name ?? 'Unnamed'}</td><td>{node.id}</td><td>{node.parent ?? '—'}</td><td>{node.level ?? '—'}</td
            ></tr
          >
        {:else}
          <tr><td colspan="4" class="empty-row">No hierarchy selected.</td></tr>
        {/each}
      </tbody>
    </table>
  </div>
{:else}
  <div class="content-heading">
    <div>
      <div class="eyebrow">{$projectState?.activeProject ?? 'PROJECT'}</div>
      <h1>Plots</h1>
    </div>
    <div class="flex flex-wrap items-center gap-2">
      {#if onopenprofiling && $projectState?.contextId}
        <button
          type="button"
          data-plots-open-profiling
          class="rounded border border-vpro-navy bg-white px-3 py-1.5 text-xs font-semibold text-vpro-navy hover:bg-vpro-navy-tint disabled:opacity-50"
          disabled={busy || editorBusy || transitionWorking || pendingTransition !== null}
          onclick={onopenprofiling}
        >
          Plot Profiling
        </button>
      {/if}
      <button
        class="icon-button"
        title="Refresh projects and plots"
        aria-label="Refresh projects and plots"
        disabled={busy}
        onclick={onrefresh}><RefreshCw size={18} strokeWidth={1.8} /></button
      >
    </div>
  </div>
  <div class="table-bar">
    <span
      >{trimmedFilter
        ? `${displayedPlots.length} matching of ${page?.total ?? allPlots.length} plots`
        : `${page?.total ?? 0} plots`}</span
    >
    <div class="flex flex-wrap items-center gap-2">
      <input
        bind:this={filterInputEl}
        type="search"
        class="plots-filter-input"
        data-plots-filter-input
        aria-label="Filter plots by number, BGC unit, or location"
        placeholder="Filter plots by number, BGC unit, or location (Ctrl+F)..."
        bind:value={plotFilter}
      />
      <span>{busy ? 'Loading...' : 'Project data'}</span>
    </div>
  </div>
  <div class="table-scroll">
    <table>
      <thead
        ><tr
          ><th>Plot number</th><th>Field number</th><th>Representing</th><th>Zone</th><th>Subzone</th><th
            >Site series</th
          ></tr
        ></thead
      >
      <tbody>
        {#each displayedPlots as plot (plot.plotNumber)}
          <tr class:selected={selected?.plotNumber === plot.plotNumber}>
            <td
              ><button
                class="plot-link tabular-nums"
                onclick={() => {
                  selected = plot;
                  onselectplot(plot);
                }}>{plot.plotNumber}</button
              ></td
            >
            <td class="tabular-nums">{plot.fieldNumber ?? '—'}</td><td>{plot.plotRepresenting ?? '—'}</td>
            <td>{plot.zone ?? '—'}</td><td>{plot.subZone ?? '—'}</td><td class="tabular-nums"
              >{plot.siteSeries ?? '—'}</td
            >
          </tr>
        {:else}
          <tr
            ><td colspan="6" class="empty-row"
              >{busy
                ? 'Loading plots...'
                : trimmedFilter
                  ? `No plots matched "${plotFilter.trim()}".`
                  : 'No plots in this project.'}</td
            ></tr
          >
        {/each}
      </tbody>
    </table>
  </div>
  {#if !trimmedFilter}
    <div class="table-footer">
      <span class="tabular-nums"
        >{page?.total ? `${offset + 1}–${Math.min(offset + pageSize, page.total)} of ${page.total}` : '0 of 0'}</span
      >
      <div class="page-controls">
        <button
          class="icon-button"
          title="Previous page"
          aria-label="Previous page"
          disabled={busy || offset === 0}
          onclick={() => onloadpage(Math.max(0, offset - pageSize))}><ChevronLeft size={18} /></button
        >
        <button
          class="icon-button"
          title="Next page"
          aria-label="Next page"
          disabled={busy || offset + pageSize >= (page?.total ?? 0)}
          onclick={() => onloadpage(offset + pageSize)}><ChevronRight size={18} /></button
        >
      </div>
    </div>
  {/if}
{/if}
