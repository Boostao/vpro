<script lang="ts">
  let { activeProject, activeSu }: { activeProject: string; activeSu: string } = $props();
</script>

<header class="border-b-[3px] border-b-vpro-gold bg-vpro-navy px-4 py-3.5 text-white sm:px-5">
  <div class="flex flex-wrap items-center justify-between gap-2">
    <div class="min-w-0">
      <p class="text-xs font-semibold uppercase tracking-wider text-vpro-gold">VPro Project Governance</p>
      <h2 class="m-0 text-base font-semibold text-white sm:text-lg">
        Project Lifecycle, Compliance Pre-Flight &amp; 3-Way Merge
      </h2>
    </div>
    <div class="text-xs text-vpro-ink-muted tabular-nums">
      Active Project: <span class="font-mono font-semibold text-white">{activeProject}</span>
      {#if activeSu !== 'None'}
        | Active SU: <span class="font-mono font-semibold text-vpro-gold">{activeSu}</span>
      {/if}
    </div>
  </div>
</header>
