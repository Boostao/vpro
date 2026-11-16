<script lang="ts">
  import { ChevronLeft, ChevronRight, RefreshCw, X } from '@lucide/svelte';
  import type { HierarchyNode, PlotPage } from '../../bindings/github.com/boostao/vpro/app';
import type { PlotSummary } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
  import { projectState } from '../shared/state';

  let {
    region = 'main',
    view = 'plots',
    busy = false,
    error = '',
    page = null,
    offset = 0,
    pageSize = 25,
    hierarchyNodes = [],
    selected = $bindable(null),
    siviStandaloneEnabled = true,
    editorBusy = false,
    transitionWorking = false,
    pendingTransition = null,
    onrefresh = () => {},
    onloadpage = () => {},
    onopenfs882 = () => {},
    onopentwopage = () => {},
    onopensivi = () => {},
    onopenexplorer = () => {},
    oncollapseinspector = () => {},
    onselectplot = () => {},
    ondismisserror,
  }: {
    region?: 'main' | 'detail';
    view?: string;
    busy?: boolean;
    error?: string;
    page?: PlotPage | null;
    offset?: number;
    pageSize?: number;
    hierarchyNodes?: HierarchyNode[];
    selected?: PlotSummary | null;
    siviStandaloneEnabled?: boolean;
    editorBusy?: boolean;
    transitionWorking?: boolean;
    pendingTransition?: unknown;
    onrefresh?: () => void;
    onloadpage?: (nextOffset: number) => void;
    onopenfs882?: () => void;
    onopentwopage?: () => void;
    onopensivi?: () => void;
    onopenexplorer?: () => void;
    oncollapseinspector?: () => void;
    onselectplot?: (plot: PlotSummary) => void;
    ondismisserror?: () => void;
  } = $props();
</script>

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
        <dt>Field number</dt><dd class="tabular-nums">{selected.fieldNumber ?? '—'}</dd>
        <dt>Representing</dt><dd>{selected.plotRepresenting ?? '—'}</dd>
        <dt>Zone</dt><dd>{selected.zone ?? '—'}</dd>
        <dt>Subzone</dt><dd>{selected.subZone ?? '—'}</dd>
        <dt>Site series</dt><dd class="tabular-nums">{selected.siteSeries ?? '—'}</dd>
      </dl>
      <div class="mt-4 pt-3 border-t border-slate-200">
        <button
          type="button"
          class="w-full py-2 px-3 bg-[#1E5128] hover:bg-[#153B1D] text-white rounded text-xs font-semibold"
          onclick={onopenfs882}
        >
          Open in FS882 Editor
        </button>
        <button
          type="button"
          data-twopage-open
          class="mt-2 w-full py-2 px-3 border border-[#003366] bg-white hover:bg-[#EBF1F8] text-[#003366] rounded text-xs font-semibold"
          disabled={busy || editorBusy || transitionWorking || pendingTransition !== null}
          onclick={onopentwopage}
        >
          Open Two-Page (FS882-8x6XL)
        </button>
        {#if siviStandaloneEnabled}
          <button
            type="button"
            data-sivi-standalone-open
            class="mt-2 w-full py-2 px-3 border border-[#003366] text-[#003366] hover:bg-[#EBF1F8] rounded text-xs font-semibold"
            disabled={busy || editorBusy || transitionWorking || pendingTransition !== null}
            onclick={onopensivi}
          >Open SIVI / FS1333</button>
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
        <dt>Active Site Unit</dt><dd>{$projectState?.activeSU ?? 'None'}</dd>
        <dt>Active Hierarchy</dt><dd>{$projectState?.activeHierarchy ?? 'None'}</dd>
        <dt>Plot Profile</dt><dd>{$projectState?.plotProfile?.source?.name ?? 'None'}</dd>
        <dt>Plots in Scope</dt><dd class="tabular-nums">{page?.total ?? 0}</dd>
      </dl>
      <p class="mt-4 text-xs text-slate-600 leading-relaxed">
        Select a plot row to inspect BEC attributes, or press <kbd class="px-1 py-0.5 rounded border border-slate-300 bg-slate-50 font-mono text-[11px]">Ctrl+K</kbd> to jump directly to any plot, report, or LMH25 topic.
      </p>
    </aside>
  {/if}
{:else if view === 'hierarchy'}
  <div class="content-heading">
    <div><div class="eyebrow">{$projectState?.hierarchyFile ?? 'HIERARCHY'}</div><h1>Hierarchy</h1></div>
    <div class="flex flex-wrap items-center gap-2">
      <button
        type="button"
        data-open-classification-explorer
        class="rounded border border-[#003366] bg-white px-3 py-1.5 text-xs font-semibold text-[#003366] hover:bg-[#EBF1F6]"
        onclick={onopenexplorer}
      >
        Open SU &amp; Hierarchy Explorer
      </button>
      <button class="icon-button" title="Refresh hierarchy" aria-label="Refresh hierarchy" disabled={busy} onclick={onrefresh}><RefreshCw size={18} strokeWidth={1.8} /></button>
    </div>
  </div>
  {#if error}<p class="error" role="alert">{error}{#if ondismisserror}<button type="button" class="error-dismiss" onclick={ondismisserror}>Dismiss</button>{/if}</p>{/if}
  <div class="table-bar"><span>{hierarchyNodes.length} units</span><span>{$projectState?.activeHierarchy ?? 'None'}</span></div>
  <div class="table-scroll">
    <table>
      <thead><tr><th>Unit</th><th>ID</th><th>Parent ID</th><th>Level</th></tr></thead>
      <tbody>
        {#each hierarchyNodes as node (node.id)}
          <tr><td>{node.name ?? 'Unnamed'}</td><td>{node.id}</td><td>{node.parent ?? '—'}</td><td>{node.level ?? '—'}</td></tr>
        {:else}
          <tr><td colspan="4" class="empty-row">No hierarchy selected.</td></tr>
        {/each}
      </tbody>
    </table>
  </div>
{:else}
  <div class="content-heading">
    <div><div class="eyebrow">{$projectState?.activeProject ?? 'PROJECT'}</div><h1>Plots</h1></div>
    <button class="icon-button" title="Refresh projects and plots" aria-label="Refresh projects and plots" disabled={busy} onclick={onrefresh}><RefreshCw size={18} strokeWidth={1.8} /></button>
  </div>
  {#if error}<p class="error" role="alert">{error}{#if ondismisserror}<button type="button" class="error-dismiss" onclick={ondismisserror}>Dismiss</button>{/if}</p>{/if}
  <div class="table-bar"><span>{page?.total ?? 0} plots</span><span>{busy ? 'Loading...' : 'Project data'}</span></div>
  <div class="table-scroll">
    <table>
      <thead><tr><th>Plot number</th><th>Field number</th><th>Representing</th><th>Zone</th><th>Subzone</th><th>Site series</th></tr></thead>
      <tbody>
        {#each page?.plots ?? [] as plot (plot.plotNumber)}
          <tr class:selected={selected?.plotNumber === plot.plotNumber}>
            <td><button class="plot-link tabular-nums" onclick={() => { selected = plot; onselectplot(plot); }}>{plot.plotNumber}</button></td>
            <td class="tabular-nums">{plot.fieldNumber ?? '—'}</td><td>{plot.plotRepresenting ?? '—'}</td>
            <td>{plot.zone ?? '—'}</td><td>{plot.subZone ?? '—'}</td><td class="tabular-nums">{plot.siteSeries ?? '—'}</td>
          </tr>
        {:else}
          <tr><td colspan="6" class="empty-row">{busy ? 'Loading plots...' : 'No plots in this project.'}</td></tr>
        {/each}
      </tbody>
    </table>
  </div>
  <div class="table-footer">
    <span class="tabular-nums">{page?.total ? `${offset + 1}–${Math.min(offset + pageSize, page.total)} of ${page.total}` : '0 of 0'}</span>
    <div class="page-controls">
      <button class="icon-button" title="Previous page" aria-label="Previous page" disabled={busy || offset === 0} onclick={() => onloadpage(Math.max(0, offset - pageSize))}><ChevronLeft size={18} /></button>
      <button class="icon-button" title="Next page" aria-label="Next page" disabled={busy || offset + pageSize >= (page?.total ?? 0)} onclick={() => onloadpage(offset + pageSize)}><ChevronRight size={18} /></button>
    </div>
  </div>
{/if}
