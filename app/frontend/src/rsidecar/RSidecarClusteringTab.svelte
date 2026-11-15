<script lang="ts">
  import type {
    AbundanceTransform,
    ClusteringMethod,
    ClusteringResult,
    EcologicalDistance,
    HierarchicalLinkage,
    PromoteCandidateSUResult,
  } from './rSidecarWorkbench';

  let {
    activeProject,
    activeSu = 'None',
    busy = false,
    clusterMethod = $bindable<ClusteringMethod>('NC'),
    clusterDistance = $bindable<EcologicalDistance>('bray'),
    clusterLinkage = $bindable<HierarchicalLinkage>('ward.D2'),
    clusterTransform = $bindable<AbundanceTransform>('sqrt'),
    clusterK = $bindable(3),
    clusterFuzziness = $bindable(1.25),
    clusterDnoise = $bindable(0.75),
    clusterBeta = $bindable(-0.25),
    clusterCutHeight = $bindable(0),
    clusterApplyLump = $bindable(true),
    clusterLumpName = $bindable(''),
    clusterUseSu = $bindable(false),
    clusterBgcFilter = $bindable(''),
    clusterUnitPrefix = $bindable('BEC'),
    clusterCandidatePrefix = $bindable(''),
    clusterMaterializeCandidate = $bindable(true),
    vegclustMode = false,
    dissimilarityActive = false,
    linkageActive = false,
    betaActive = false,
    clusteringValidationError = null,
    clusterResult = null,
    dendrogramLayout,
    selectedDendroPlot = $bindable<string | null>(null),
    promoteTargetSuName = $bindable(''),
    promoteExcludeNoise = $bindable(true),
    promoteConfirmOverwrite = $bindable(false),
    promoteActivate = $bindable(false),
    promoteValidationError = null,
    promoteResult = null,
    onSubmitClustering,
    onSubmitPromote,
  }: {
    activeProject: string;
    activeSu?: string;
    busy?: boolean;
    clusterMethod?: ClusteringMethod;
    clusterDistance?: EcologicalDistance;
    clusterLinkage?: HierarchicalLinkage;
    clusterTransform?: AbundanceTransform;
    clusterK?: number;
    clusterFuzziness?: number;
    clusterDnoise?: number;
    clusterBeta?: number;
    clusterCutHeight?: number;
    clusterApplyLump?: boolean;
    clusterLumpName?: string;
    clusterUseSu?: boolean;
    clusterBgcFilter?: string;
    clusterUnitPrefix?: string;
    clusterCandidatePrefix?: string;
    clusterMaterializeCandidate?: boolean;
    vegclustMode?: boolean;
    dissimilarityActive?: boolean;
    linkageActive?: boolean;
    betaActive?: boolean;
    clusteringValidationError?: string | null;
    clusterResult?: ClusteringResult | null;
    dendrogramLayout: {
      width: number;
      height: number;
      cutLineY: number;
      segments: Array<{ x1: number; y1: number; x2: number; y2: number }>;
      leaves: Array<{ cx: number; cy: number; plotNumber: string; clusterUnit: string; isNoise: boolean }>;
    };
    selectedDendroPlot?: string | null;
    promoteTargetSuName?: string;
    promoteExcludeNoise?: boolean;
    promoteConfirmOverwrite?: boolean;
    promoteActivate?: boolean;
    promoteValidationError?: string | null;
    promoteResult?: PromoteCandidateSUResult | null;
    onSubmitClustering: () => Promise<void> | void;
    onSubmitPromote: () => Promise<void> | void;
  } = $props();
</script>

<div class="panel">
  <div class="card">
    <h3>BEC_R Multivariate Clustering (vegclust, vegan Hierarchical, Flexible-Beta &amp; PAM)</h3>
    <div class="form-row">
      <label>
        Algorithm
        <select data-cluster-method bind:value={clusterMethod}>
          <option value="NC">vegclust Noise Clustering (NC)</option>
          <option value="KM">vegclust Crisp K-Means (KM)</option>
          <option value="FCM">vegclust Fuzzy C-Means (FCM)</option>
          <option value="HCLUST">vegan Hierarchical Clustering (HCLUST)</option>
          <option value="BETA_FLEXIBLE">Flexible-Beta Hierarchical (BETA_FLEXIBLE)</option>
          <option value="PAM">Partitioning Around Medoids (PAM)</option>
        </select>
      </label>
      <label class:field-muted={!dissimilarityActive}>
        Dissimilarity
        <select
          data-cluster-distance
          bind:value={clusterDistance}
          disabled={!dissimilarityActive}
          aria-disabled={!dissimilarityActive}
        >
          <option value="bray">Bray-Curtis</option>
          <option value="chord">Chord Normalized</option>
          <option value="jaccard">Jaccard</option>
          <option value="kulczynski">Kulczynski</option>
        </select>
        {#if vegclustMode}
          <span class="field-hint">Disabled for vegclust ({clusterMethod})</span>
        {/if}
      </label>
      <label class:field-muted={!linkageActive}>
        Linkage
        <select
          data-cluster-linkage
          bind:value={clusterLinkage}
          disabled={!linkageActive}
          aria-disabled={!linkageActive}
        >
          <option value="ward.D2">Ward.D2</option>
          <option value="average">UPGMA (Average)</option>
          <option value="complete">Complete</option>
        </select>
        {#if !linkageActive}
          <span class="field-hint">
            {vegclustMode ? `Disabled for vegclust (${clusterMethod})` : betaActive ? 'Uses Flexible-Beta parameter' : 'N/A for PAM medoids'}
          </span>
        {/if}
      </label>
      <label>
        Cover Transform
        <select bind:value={clusterTransform}>
          <option value="sqrt">Square Root</option>
          <option value="log1p">Log(1 + Cover)</option>
          <option value="hellinger">Hellinger</option>
          <option value="chord">Chord</option>
          <option value="raw">Raw % Cover</option>
        </select>
      </label>
      <label>
        Clusters (k)
        <input type="number" min="2" max="50" bind:value={clusterK} />
      </label>
      {#if betaActive}
        <label data-cluster-beta-field>
          Flexible Beta (beta)
          <input type="number" step="0.05" min="-0.99" max="0.99" bind:value={clusterBeta} />
        </label>
      {/if}
      <label class:field-muted={!vegclustMode}>
        Fuzziness (m)
        <input type="number" step="0.05" min="1.05" max="5" bind:value={clusterFuzziness} disabled={!vegclustMode} />
      </label>
      <label class:field-muted={clusterMethod !== 'NC'}>
        Noise Distance (dnoise)
        <input type="number" step="0.05" min="0.05" max="5" bind:value={clusterDnoise} disabled={clusterMethod !== 'NC'} />
      </label>
      <label>
        Unit Prefix
        <input type="text" data-cluster-unit-prefix bind:value={clusterUnitPrefix} placeholder="CL or BEC" />
      </label>
      <label>
        BGC Filter
        <input type="text" data-cluster-bgc-filter bind:value={clusterBgcFilter} placeholder="e.g. SBS, BWBS, MH" />
      </label>
      <label class:field-muted={!clusterApplyLump}>
        Lump Table (*_Lump)
        <input
          type="text"
          data-cluster-lump-name
          bind:value={clusterLumpName}
          disabled={!clusterApplyLump}
          placeholder={activeProject}
        />
      </label>
      <label>
        Candidate Prefix
        <input type="text" bind:value={clusterCandidatePrefix} placeholder={activeProject} />
      </label>
    </div>

    <div class="form-row">
      <label class="checkbox-label">
        <input type="checkbox" bind:checked={clusterApplyLump} />
        Fold Taxonomic Lump Table (*_Lump)
      </label>
      <label class="checkbox-label">
        <input type="checkbox" bind:checked={clusterUseSu} />
        Scope to Active SU ({activeSu})
      </label>
      <label class="checkbox-label">
        <input type="checkbox" bind:checked={clusterMaterializeCandidate} />
        Stage &lt;Name&gt;_ClusterCandidate_SU (Never Overwrites Active SU)
      </label>
    </div>

    {#if clusteringValidationError}
      <div class="inline-error">{clusteringValidationError}</div>
    {/if}

    <div class="button-row">
      <button
        type="button"
        class="btn-primary"
        disabled={busy || Boolean(clusteringValidationError)}
        onclick={onSubmitClustering}
      >
        Run BEC_R Clustering
      </button>
    </div>

    {#if clusterResult}
      <div class="kpi-row">
        <div class="kpi"><span>Clustered Plots</span><strong>{clusterResult.plotCount}</strong></div>
        <div class="kpi"><span>Species Taxa</span><strong>{clusterResult.speciesCount}</strong></div>
        <div class="kpi"><span>Cophenetic r</span><strong>{clusterResult.copheneticCorrelation}</strong></div>
        <div class="kpi"><span>Mean Silhouette</span><strong>{clusterResult.meanSilhouette}</strong></div>
        <div class="kpi"><span>Noise Outliers</span><strong>{clusterResult.noiseCount}</strong></div>
        {#if clusterResult.candidateTableName}
          <div class="kpi"><span>Staged Table</span><strong>{clusterResult.candidateTableName}</strong></div>
        {/if}
      </div>

      <h4>Interactive Hierarchical Dendrogram</h4>
      <div class="form-row">
        <label>
          Reference Cut Height ({clusterCutHeight.toFixed(3)} / Max {clusterResult.dendrogram.maxHeight})
          <input
            type="range"
            min="0.01"
            max={clusterResult.dendrogram.maxHeight}
            step="0.01"
            bind:value={clusterCutHeight}
          />
        </label>
        {#if selectedDendroPlot}
          <span>Selected Leaf Plot: <code>{selectedDendroPlot}</code></span>
        {/if}
      </div>

      <div class="dendrogram-scroll">
        <svg
          viewBox="0 0 {dendrogramLayout.width} {dendrogramLayout.height}"
          width={dendrogramLayout.width}
          height={dendrogramLayout.height}
          role="img"
          aria-label="BEC Hierarchical Cluster Dendrogram"
        >
          <rect x="0" y="0" width={dendrogramLayout.width} height={dendrogramLayout.height} fill="#FFFFFF" />
          {#each dendrogramLayout.segments as seg}
            <line x1={seg.x1} y1={seg.y1} x2={seg.x2} y2={seg.y2} stroke="#003366" stroke-width="1.4" />
          {/each}
          <line
            x1="36"
            y1={dendrogramLayout.cutLineY}
            x2={dendrogramLayout.width - 16}
            y2={dendrogramLayout.cutLineY}
            stroke="#FCBA19"
            stroke-width="2"
            stroke-dasharray="6,4"
          />
          {#each dendrogramLayout.leaves as leaf}
            <g
              class="dendro-leaf"
              role="button"
              tabindex="0"
              aria-label="Select plot {leaf.plotNumber}"
              transform="translate({leaf.cx}, {leaf.cy})"
              onclick={() => (selectedDendroPlot = leaf.plotNumber)}
              onkeydown={e => {
                if (e.key === 'Enter' || e.key === ' ') {
                  e.preventDefault();
                  selectedDendroPlot = leaf.plotNumber;
                }
              }}
            >
              <circle
                r="3.4"
                cy="-8"
                fill={leaf.isNoise ? '#D8292F' : selectedDendroPlot === leaf.plotNumber ? '#1A5A96' : '#003366'}
                stroke={selectedDendroPlot === leaf.plotNumber ? '#FCBA19' : 'none'}
                stroke-width="1.5"
              />
              <text
                transform="rotate(65)"
                text-anchor="start"
                font-family="monospace"
                font-size="10"
                font-weight={selectedDendroPlot === leaf.plotNumber ? '700' : '400'}
                fill={selectedDendroPlot === leaf.plotNumber ? '#1A5A96' : '#313132'}
              >
                {leaf.plotNumber} ({leaf.clusterUnit})
              </text>
            </g>
          {/each}
        </svg>
      </div>

      <h4>Cluster Units &amp; Indicator Species Fidelity (IndVal)</h4>
      <div class="table-scroll">
        <table class="data-table">
          <thead>
            <tr>
              <th>Cluster Unit</th>
              <th>Plots</th>
              <th>Mean Richness</th>
              <th>Mean Silhouette</th>
              <th>Top Diagnostic / Indicator Species</th>
            </tr>
          </thead>
          <tbody>
            {#each clusterResult.clusters as cl}
              <tr>
                <td><strong>{cl.clusterUnit}</strong></td>
                <td>{cl.plotCount}</td>
                <td>{cl.meanRichness}</td>
                <td>{cl.meanSilhouette}</td>
                <td>
                  {#each cl.indicators.slice(0, 5) as ind, idx}
                    <span>
                      <code>{ind.species}</code>
                      {#if ind.scientificName}<em>({ind.scientificName})</em>{/if}
                      [{ind.constancyPct}% | IndVal {ind.indVal}]{idx < Math.min(4, cl.indicators.length - 1) ? ', ' : ''}
                    </span>
                  {/each}
                </td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
  </div>

  <div class="card">
    <h3>Promote Staged Cluster Candidate to Site Unit Table (*_SU)</h3>
    <div class="form-row">
      <label>
        Target SU Name
        <input type="text" bind:value={promoteTargetSuName} placeholder="e.g. SubzoneRev2026" />
      </label>
      <label class="checkbox-label">
        <input type="checkbox" bind:checked={promoteExcludeNoise} />
        Exclude *_Noise Outliers
      </label>
      <label class="checkbox-label">
        <input type="checkbox" bind:checked={promoteConfirmOverwrite} />
        Confirm overwrite if target *_SU exists
      </label>
      <label class="checkbox-label">
        <input type="checkbox" bind:checked={promoteActivate} />
        Activate promoted *_SU immediately
      </label>
    </div>

    {#if promoteValidationError}
      <div class="inline-error">{promoteValidationError}</div>
    {/if}

    <div class="button-row">
      <button
        type="button"
        class="btn-primary"
        disabled={busy || !promoteTargetSuName.trim() || Boolean(promoteValidationError)}
        onclick={onSubmitPromote}
      >
        Promote Candidate to *_SU
      </button>
    </div>

    {#if promoteResult}
      <div class="banner-status">
        Promoted {promoteResult.promotedRows} plot assignments into <strong>{promoteResult.targetTableName}</strong>
        (skipped {promoteResult.skippedNoiseRows} noise plots).
      </div>
    {/if}
  </div>
</div>
