<script lang="ts">
  import type { PullSubsetResult, SubsetPreview } from './cloudSyncWorkbench';

  interface Props {
    busy: boolean;
    operationHeld: boolean;
    subsetZonesRaw: string;
    subsetSubzonesRaw: string;
    subsetProjectIdsRaw: string;
    subsetPlotNumbersRaw: string;
    subsetBboxRaw: string;
    subsetLimitRaw: string | number | null | undefined;
    subsetAllowFull: boolean;
    subsetPreview: SubsetPreview | null;
    subsetTargetProject: string;
    subsetDestinationPath: string;
    subsetActivateOnSuccess: boolean;
    subsetTargetValidationError: string | null;
    pullSubsetResult: PullSubsetResult | null;
    onPreviewSubset: () => void;
    onPullSubset: () => void;
  }

  let {
    busy,
    operationHeld,
    subsetZonesRaw = $bindable(),
    subsetSubzonesRaw = $bindable(),
    subsetProjectIdsRaw = $bindable(),
    subsetPlotNumbersRaw = $bindable(),
    subsetBboxRaw = $bindable(),
    subsetLimitRaw = $bindable(),
    subsetAllowFull = $bindable(),
    subsetPreview,
    subsetTargetProject = $bindable(),
    subsetDestinationPath = $bindable(),
    subsetActivateOnSuccess = $bindable(),
    subsetTargetValidationError,
    pullSubsetResult,
    onPreviewSubset,
    onPullSubset,
  }: Props = $props();
</script>

<fieldset class="space-y-3 rounded border border-vpro-border border-t-[3px] border-t-vpro-gold bg-white p-4 shadow-sm">
  <legend class="px-1 text-sm font-semibold text-vpro-navy">Checkout Regional Subset from BECMaster</legend>
  <p class="text-xs text-vpro-ink-secondary">
    Filter BECMaster plots by BGC Zone, Subzone, Project ID, literal PlotNumber (preserving leading zeros such as <span class="font-mono">'00337'</span>), or WGS84 bounding box into a local VPro project (<span class="font-mono">.db</span>).
  </p>

  <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
    <div class="space-y-1">
      <label class="block text-xs font-semibold text-vpro-ink-secondary" for="subset-zones">BGC Zones (comma-separated)</label>
      <input
        id="subset-zones"
        type="text"
        class="w-full rounded border border-vpro-border p-2 font-mono text-xs"
        bind:value={subsetZonesRaw}
        disabled={busy || operationHeld}
        placeholder="e.g. CWH, ICH, SBS"
      />
    </div>
    <div class="space-y-1">
      <label class="block text-xs font-semibold text-vpro-ink-secondary" for="subset-subzones">Subzones / Variants (comma-separated)</label>
      <input
        id="subset-subzones"
        type="text"
        class="w-full rounded border border-vpro-border p-2 font-mono text-xs"
        bind:value={subsetSubzonesRaw}
        disabled={busy || operationHeld}
        placeholder="e.g. vm1, mk1"
      />
    </div>
    <div class="space-y-1">
      <label class="block text-xs font-semibold text-vpro-ink-secondary" for="subset-project-ids">Project IDs (comma-separated)</label>
      <input
        id="subset-project-ids"
        type="text"
        class="w-full rounded border border-vpro-border p-2 font-mono text-xs"
        bind:value={subsetProjectIdsRaw}
        disabled={busy || operationHeld}
        placeholder="e.g. HGW2019, MANNING"
      />
    </div>
    <div class="space-y-1">
      <label class="block text-xs font-semibold text-vpro-ink-secondary" for="subset-plot-numbers">Literal Plot Numbers (max 7 characters)</label>
      <input
        id="subset-plot-numbers"
        type="text"
        class="w-full rounded border border-vpro-border p-2 font-mono text-xs"
        bind:value={subsetPlotNumbersRaw}
        disabled={busy || operationHeld}
        placeholder="e.g. 00337, 108050"
      />
    </div>
  </div>

  <div class="grid grid-cols-1 gap-2 sm:grid-cols-3">
    <div class="space-y-1 sm:col-span-2">
      <label class="block text-xs font-semibold text-vpro-ink-secondary" for="subset-bbox">Spatial BBox (minLon, minLat, maxLon, maxLat)</label>
      <input
        id="subset-bbox"
        type="text"
        class="w-full rounded border border-vpro-border p-2 font-mono text-xs"
        bind:value={subsetBboxRaw}
        disabled={busy || operationHeld}
        placeholder="e.g. -133.2, 52.0, -131.0, 54.3"
      />
    </div>
    <div class="space-y-1">
      <label class="block text-xs font-semibold text-vpro-ink-secondary" for="subset-limit">Plot Limit (optional)</label>
      <input
        id="subset-limit"
        type="number"
        min="1"
        aria-describedby="subset-limit-hint"
        class="w-full rounded border border-vpro-border p-2 font-mono text-xs"
        bind:value={subsetLimitRaw}
        disabled={busy || operationHeld}
        placeholder="5000"
      />
      <p id="subset-limit-hint" class="text-[11px] text-vpro-ink-muted">
        Caps returned plots; requires a regional filter or full checkout.
      </p>
    </div>
  </div>

  <div class="flex flex-wrap items-center justify-between gap-2">
    <label class="flex items-center gap-2 text-xs text-vpro-ink">
      <input type="checkbox" bind:checked={subsetAllowFull} disabled={busy || operationHeld} />
      Allow full provincial BECMaster checkout without regional filter
    </label>
    <button
      type="button"
      disabled={busy || operationHeld}
      class="rounded bg-vpro-navy px-3 py-1.5 text-xs font-semibold text-white hover:bg-vpro-navy-dark disabled:opacity-50"
      onclick={onPreviewSubset}
    >
      Preview Matching Plots
    </button>
  </div>

  {#if subsetPreview}
    <div class="space-y-1.5 rounded border border-vpro-border bg-vpro-surface-subtle p-3 text-xs">
      <div class="font-semibold text-vpro-navy">
        Matched {subsetPreview.matchingPlots.toLocaleString()} plot(s) &middot; {subsetPreview.matchingVeg.toLocaleString()} vegetation row(s)
      </div>
      {#if subsetPreview.samplePlots.length > 0}
        <div>Sample Plots: <span class="font-mono">{subsetPreview.samplePlots.join(', ')}</span></div>
      {/if}
      {#if Object.keys(subsetPreview.zoneBreakdown).length > 0}
        <div>
          Zone Breakdown:
          <span class="font-mono">
            {Object.entries(subsetPreview.zoneBreakdown)
              .map(([z, cnt]) => `${z}: ${cnt}`)
              .join(' | ')}
          </span>
        </div>
      {/if}
    </div>
  {/if}

  <div class="space-y-2 border-t border-vpro-border pt-3">
    <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
      <div class="space-y-1">
        <label class="block text-xs font-semibold text-vpro-ink-secondary" for="subset-target-project">Target Project Name</label>
        <input
          id="subset-target-project"
          type="text"
          class="w-full rounded border border-vpro-border p-2 text-xs"
          bind:value={subsetTargetProject}
          disabled={busy || operationHeld}
          aria-invalid={!!subsetTargetValidationError}
          placeholder="e.g. Skeena_Checkout_2026"
        />
      </div>
      <div class="space-y-1">
        <label class="block text-xs font-semibold text-vpro-ink-secondary" for="subset-dest-path">Destination .db Path (optional)</label>
        <input
          id="subset-dest-path"
          type="text"
          class="w-full rounded border border-vpro-border p-2 font-mono text-xs"
          bind:value={subsetDestinationPath}
          disabled={busy || operationHeld}
          placeholder="Defaults to projects/<Target>.db"
        />
      </div>
    </div>
    {#if subsetTargetValidationError}
      <p role="alert" class="text-xs text-red-700">{subsetTargetValidationError}</p>
    {/if}
    <label class="flex items-center gap-2 text-xs text-vpro-ink">
      <input type="checkbox" bind:checked={subsetActivateOnSuccess} disabled={busy || operationHeld} />
      Activate checked-out project on success
    </label>
    <button
      type="button"
      disabled={busy || operationHeld || !subsetTargetProject || !!subsetTargetValidationError}
      class="w-full rounded border-2 border-vpro-gold bg-vpro-navy px-3 py-2 text-xs font-semibold text-white hover:bg-vpro-navy-dark disabled:opacity-50"
      onclick={onPullSubset}
    >
      Download Regional Subset (.db)
    </button>
    {#if pullSubsetResult}
      <p class="break-all text-xs text-vpro-ink-secondary">
        Saved <span class="font-mono">{pullSubsetResult.targetProject}</span> ({pullSubsetResult.plotCount} plots, log #{pullSubsetResult.downloadLogId}, SHA-256 <span class="font-mono">{pullSubsetResult.destinationSha256.slice(0, 16)}</span>).
      </p>
    {/if}
  </div>
</fieldset>
