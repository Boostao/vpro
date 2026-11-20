<script lang="ts">
  import type { SpatialAOISelectionResult } from '../../bindings/github.com/boostao/vpro/app';
  import type { SpatialAOICommitInput } from './geospatialWorkbench';

  let {
    project,
    su,
    aoiDrawMode = $bindable(false),
    aoiTargetMode = $bindable<'update_active' | 'create_project_su' | 'create_su_file'>('create_project_su'),
    aoiSUName = $bindable(''),
    aoiSiteUnit = $bindable(''),
    aoiVerticesCount = 0,
    aoiPreview = null,
    loading = false,
    mutating = false,
    onSeedViewport,
    onClear,
    onCommit,
  }: {
    project: string;
    su: string;
    aoiDrawMode?: boolean;
    aoiTargetMode?: 'update_active' | 'create_project_su' | 'create_su_file';
    aoiSUName?: string;
    aoiSiteUnit?: string;
    aoiVerticesCount?: number;
    aoiPreview?: SpatialAOISelectionResult | null;
    loading?: boolean;
    mutating?: boolean;
    onSeedViewport: () => void;
    onClear: () => void;
    onCommit: (opts: SpatialAOICommitInput) => Promise<void> | void;
  } = $props();

  let aoiFilePath = $state('');
  let aoiIncludeUnassigned = $state(false);
  let aoiActivate = $state(true);
</script>

<div class="wb-panel-body">
  <div class="wb-card">
    <h2>Polygon / Lasso AOI -&gt; Site Unit (*_SU)</h2>
    <p class="wb-muted">
      Click vertices directly on the map or capture the current map view extent to select plots spatially.
    </p>
    <div class="wb-btn-row">
      <button
        type="button"
        class="wb-btn"
        class:wb-btn-gold={aoiDrawMode}
        onclick={() => {
          aoiDrawMode = !aoiDrawMode;
        }}
      >
        {aoiDrawMode ? 'Finish Drawing AOI' : 'Draw Polygon on Map'}
      </button>
      <button type="button" class="wb-btn" onclick={onSeedViewport}> Use Current Map View </button>
      <button type="button" class="wb-btn" onclick={onClear} disabled={aoiVerticesCount === 0}>
        Clear ({aoiVerticesCount} pts)
      </button>
    </div>

    {#if aoiPreview}
      {@const previewNums = aoiPreview.plotNumbers ?? []}
      <div class="wb-suggestion-box" role="status">
        <strong>AOI Selection: {aoiPreview.matchedCount} of {aoiPreview.totalEvaluated} plots</strong>
        <div>Approx. Area: {aoiPreview.approxAreaKm2.toFixed(1)} km^2</div>
        <div class="wb-chip-wrap">
          {#each previewNums.slice(0, 20) as pNum (pNum)}
            <span class="wb-chip">{pNum}</span>
          {/each}
          {#if previewNums.length > 20}
            <span class="wb-muted">+{previewNums.length - 20} more</span>
          {/if}
        </div>
      </div>
    {/if}

    <div class="wb-form-stack">
      <label for="aoi-target-mode">Target *_SU Destination</label>
      <select id="aoi-target-mode" bind:value={aoiTargetMode} class="wb-input">
        <option value="update_active" disabled={!su || su === 'None'}>
          Update Active SU ({su && su !== 'None' ? `${su}_SU` : 'None selected'})
        </option>
        <option value="create_project_su">Create New *_SU Table in Project ({project}.db)</option>
        <option value="create_su_file">Create New Site Unit File (.db)</option>
      </select>

      {#if aoiTargetMode !== 'update_active'}
        <label for="aoi-su-name">New SU Table Prefix</label>
        <input id="aoi-su-name" class="wb-input" bind:value={aoiSUName} placeholder="e.g. SBS_NorthAOI" />
      {/if}

      {#if aoiTargetMode === 'create_su_file'}
        <label for="aoi-su-filepath">New Site Unit File Path (.db)</label>
        <input id="aoi-su-filepath" class="wb-input" bind:value={aoiFilePath} placeholder="/path/to/NewAOI_SU.db" />
      {/if}

      <label for="aoi-site-unit">Assigned SiteUnit Code</label>
      <input id="aoi-site-unit" class="wb-input" bind:value={aoiSiteUnit} placeholder="e.g. SBSmk1/01" />

      {#if aoiTargetMode !== 'update_active'}
        <label class="wb-check-row">
          <input type="checkbox" bind:checked={aoiIncludeUnassigned} />
          <span>Include non-AOI project plots as unassigned (NULL)</span>
        </label>
        <label class="wb-check-row">
          <input type="checkbox" bind:checked={aoiActivate} />
          <span>Switch active context to new *_SU immediately</span>
        </label>
      {/if}

      <button
        type="button"
        class="wb-btn wb-btn-primary"
        disabled={mutating || loading || !aoiPreview || aoiPreview.matchedCount === 0 || !aoiSiteUnit.trim()}
        onclick={() =>
          void onCommit({
            mode: aoiTargetMode,
            suName: aoiSUName.trim(),
            filePath: aoiFilePath.trim(),
            siteUnit: aoiSiteUnit.trim(),
            includeNonAoiPlotsAsUnassigned: aoiIncludeUnassigned,
            activate: aoiActivate,
          })}
      >
        {mutating ? 'Saving *_SU...' : `Assign ${aoiPreview?.matchedCount ?? 0} AOI Plots to *_SU`}
      </button>
    </div>
  </div>
</div>
