<script lang="ts">
  import type { SynthesisSnapshot } from './classificationSynthesis';

  interface Props {
    snapshot: SynthesisSnapshot | null;
    project: string;
    su: string;
    lastLatencyMs: number | null;
    loading: boolean;
    mutating: boolean;
    onRefresh: () => void;
    onUndo: () => void;
    onOpenExport: () => void;
  }

  let { snapshot, project, su, lastLatencyMs, loading, mutating, onRefresh, onUndo, onOpenExport }: Props = $props();
</script>

<header class="syn-header">
  <div class="syn-header-brand">
    <div class="syn-eyebrow">B.C. MINISTRY OF FORESTS · BEC CLASSIFICATION SYNTHESIS</div>
    <div class="syn-title-row">
      <h2>BEC Differential &amp; Pairwise Synthesis</h2>
      <span class="syn-chip syn-chip-gold">
        {snapshot?.project || project || 'Active Project'} · SU: {snapshot?.su || su || 'None'}
      </span>
      {#if snapshot}
        <span class="syn-chip">
          {snapshot.classifiedPlotCount} Classified Plots · {snapshot.units.length} Units
        </span>
        {#if lastLatencyMs !== null}
          <span class="syn-chip syn-latency-badge" data-testid="synthesis-latency-badge">
            {lastLatencyMs.toFixed(1)} ms
          </span>
        {/if}
      {/if}
    </div>
  </div>

  <div class="syn-header-actions">
    <button type="button" class="syn-btn syn-btn-ghost" disabled={loading || mutating} onclick={onRefresh}>
      Refresh
    </button>
    <button
      type="button"
      class="syn-btn syn-btn-ghost"
      disabled={!snapshot?.canUndo || mutating || loading}
      title={snapshot?.latestUndo
        ? `Undo move of plot ${snapshot.latestUndo.plotNumber} (${snapshot.latestUndo.afterSiteUnit} -> ${snapshot.latestUndo.beforeSiteUnit || 'Unassigned'})`
        : 'No synthesis SU reassignment to undo'}
      onclick={onUndo}
    >
      Undo Move{snapshot?.undoDepth ? ` (${snapshot.undoDepth})` : ''}
    </button>
    <button type="button" class="syn-btn syn-btn-gold" disabled={!snapshot || loading} onclick={onOpenExport}>
      Publish Diagnostic .xlsx
    </button>
  </div>
</header>
