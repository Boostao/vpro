<script lang="ts">
  import { ShieldCheck } from '@lucide/svelte';
  import { webMeta } from '../shared/state';
  import { formatSnapshotProvenance } from './webReadOnlyShell';

  let {
    variant,
    activeProject = '',
    plotCount = 0,
  }: {
    variant: 'header' | 'sidebar' | 'home';
    activeProject?: string;
    plotCount?: number;
  } = $props();

  const snapshotProvenance = $derived(formatSnapshotProvenance($webMeta, activeProject, plotCount));
</script>

{#if variant === 'header'}
  <span
    class="ctx-chip"
    data-snapshot-provenance-badge
    title={snapshotProvenance.notice || `${snapshotProvenance.snapshotId} (${snapshotProvenance.standardsLabel})`}
  >
    <span class="ctx-chip-label">Snapshot</span>
    <span class="ctx-chip-value tabular-nums">
      {snapshotProvenance.snapshotId}{snapshotProvenance.publishedDate
        ? ` · ${snapshotProvenance.publishedDate}`
        : ''}{snapshotProvenance.plotCount > 0 ? ` · ${snapshotProvenance.plotCount.toLocaleString()} plots` : ''}
    </span>
  </span>
  {#if snapshotProvenance.redacted}
    <span
      class="ctx-status-pill ctx-status-dirty"
      data-redaction-provenance-badge
      title={snapshotProvenance.notice}
    >
      10 km Rare-Plant Protection
    </span>
  {/if}
{:else if variant === 'sidebar'}
  <section
    class="mx-2 mb-2 rounded border border-vpro-border border-l-[3px] border-l-vpro-gold bg-vpro-canvas p-2 text-[11px] text-vpro-ink"
    data-sidebar-snapshot-provenance
    aria-label="BECMaster snapshot provenance"
  >
    <div class="font-mono text-[10px] font-bold uppercase tracking-wide text-vpro-navy">Read-Only Snapshot</div>
    <div class="mt-0.5 font-semibold text-vpro-ink break-words">{snapshotProvenance.snapshotId}</div>
    <div class="mt-0.5 text-vpro-ink-secondary tabular-nums">
      {#if snapshotProvenance.publishedDate}{snapshotProvenance.publishedDate}{/if}{#if snapshotProvenance.publishedDate && snapshotProvenance.plotCount > 0}{' · '}{/if}{#if snapshotProvenance.plotCount > 0}{snapshotProvenance.plotCount.toLocaleString()} plots{/if}
    </div>
    {#if snapshotProvenance.redacted}
      <p
        class="mt-1 rounded bg-vpro-warning-bg px-1.5 py-1 text-[10px] leading-snug text-vpro-ink"
        data-sidebar-redaction-notice
      >
        {snapshotProvenance.notice}
      </p>
    {/if}
  </section>
{:else if variant === 'home'}
  <section
    data-home-web-snapshot-banner
    aria-label="Read-Only BECMaster Snapshot Notice"
    class="rounded border border-vpro-navy border-l-[4px] border-l-vpro-gold bg-vpro-surface-subtle p-3.5 text-xs text-vpro-ink"
  >
    <div class="flex flex-wrap items-center justify-between gap-2">
      <div class="flex items-center gap-2 font-bold text-vpro-navy">
        <ShieldCheck size={16} class="text-vpro-navy" aria-hidden="true" />
        <span>
          VPro Web Read-Only Portal · {snapshotProvenance.snapshotId}{snapshotProvenance.publishedDate
            ? ` (${snapshotProvenance.publishedDate})`
            : ''}
        </span>
      </div>
      <span class="rounded bg-vpro-navy px-2 py-0.5 font-mono text-[11px] font-semibold text-white">
        {snapshotProvenance.plotCount.toLocaleString()} plots · Read-Only
      </span>
    </div>
    {#if snapshotProvenance.redacted}
      <p class="mt-1.5 leading-relaxed text-vpro-ink" data-home-redaction-notice>
        {snapshotProvenance.notice}
      </p>
    {/if}
  </section>
{/if}
