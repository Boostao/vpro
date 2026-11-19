<script lang="ts">
  import type {
    CompareProjectsResult,
    FieldDiff,
    MergeResolutionChoice,
    ThreeWayMergePreview,
    ThreeWayMergeResult,
  } from './projectAdminWorkbench';

  let {
    busy,
    cmpTargetPath = $bindable(''),
    cmpTargetProject = $bindable(''),
    cmpSourceProject = $bindable(''),
    cmpSourcePath = $bindable(''),
    cmpCaseInsensitive = $bindable(false),
    cmpResult,
    cmpAllDiffs,
    cmpExportPreview,
    mergeSourcePath = $bindable(''),
    mergeSourceProject = $bindable(''),
    mergeBasePath = $bindable(''),
    mergeBaseProject = $bindable(''),
    mergeTargetPath = $bindable(''),
    mergeTargetProject = $bindable(''),
    mergeCaseInsensitive = $bindable(false),
    mergeDefaultResolution = $bindable<MergeResolutionChoice>('keep_target'),
    mergePreview,
    mergePlotResolutions,
    mergeFieldResolutions,
    mergeResult,
    onRunCompare,
    onExportCompareDiffs,
    onPreviewMerge,
    onExecuteMerge,
    onSetPlotResolution,
    onSetFieldResolution,
  }: {
    busy: boolean;
    cmpTargetPath?: string;
    cmpTargetProject?: string;
    cmpSourceProject?: string;
    cmpSourcePath?: string;
    cmpCaseInsensitive?: boolean;
    cmpResult: CompareProjectsResult | null;
    cmpAllDiffs: FieldDiff[];
    cmpExportPreview: { format: 'CSV' | 'TSV'; text: string } | null;
    mergeSourcePath?: string;
    mergeSourceProject?: string;
    mergeBasePath?: string;
    mergeBaseProject?: string;
    mergeTargetPath?: string;
    mergeTargetProject?: string;
    mergeCaseInsensitive?: boolean;
    mergeDefaultResolution?: MergeResolutionChoice;
    mergePreview: ThreeWayMergePreview | null;
    mergePlotResolutions: Record<string, MergeResolutionChoice>;
    mergeFieldResolutions: Record<string, MergeResolutionChoice>;
    mergeResult: ThreeWayMergeResult | null;
    onRunCompare: () => void;
    onExportCompareDiffs: (format: 'CSV' | 'TSV') => void;
    onPreviewMerge: () => void;
    onExecuteMerge: () => void;
    onSetPlotResolution: (plotNumber: string, choice: MergeResolutionChoice) => void;
    onSetFieldResolution: (conflictId: string, choice: MergeResolutionChoice) => void;
  } = $props();
</script>

<div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
  <!-- Compare Projects -->
  <fieldset class="min-w-0 space-y-3 rounded border border-[#D8D8D8] border-t-[3px] border-t-[#FCBA19] p-4">
    <legend class="px-1 text-sm font-semibold text-[#003366]">Compare Two Projects</legend>
    <div class="space-y-1">
      <label class="block text-xs font-semibold text-[#313132]" for="cmp-target-path">Target .db Path (required)</label>
      <input id="cmp-target-path" type="text" class="w-full rounded border border-[#9F9F9F] p-2 text-sm font-mono" bind:value={cmpTargetPath} disabled={busy} />
    </div>
    <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
      <div class="space-y-1">
        <label class="block text-xs font-semibold text-[#313132]" for="cmp-target-proj">Target Project (optional)</label>
        <input id="cmp-target-proj" type="text" class="w-full rounded border border-[#9F9F9F] p-2 text-sm" bind:value={cmpTargetProject} disabled={busy} />
      </div>
      <div class="space-y-1">
        <label class="block text-xs font-semibold text-[#313132]" for="cmp-source-proj">Source Project (optional)</label>
        <input id="cmp-source-proj" type="text" class="w-full rounded border border-[#9F9F9F] p-2 text-sm" bind:value={cmpSourceProject} disabled={busy} />
      </div>
    </div>
    <div class="space-y-1">
      <label class="block text-xs font-semibold text-[#313132]" for="cmp-source-path">Source .db Path (blank = active)</label>
      <input id="cmp-source-path" type="text" class="w-full rounded border border-[#9F9F9F] p-2 text-sm font-mono" bind:value={cmpSourcePath} disabled={busy} />
    </div>
    <label class="flex items-center gap-2 text-xs text-[#313132]">
      <input id="cmp-case-insensitive" type="checkbox" bind:checked={cmpCaseInsensitive} disabled={busy} />
      Case-insensitive text comparison
    </label>
    <div class="flex flex-wrap items-center gap-2">
      <button
        type="button"
        disabled={busy || !cmpTargetPath.trim()}
        class="rounded bg-[#003366] px-4 py-2 text-sm font-semibold text-white hover:bg-[#002244] disabled:opacity-50"
        onclick={onRunCompare}
      >
        Compare Projects
      </button>
      {#if cmpResult}
        <button
          type="button"
          disabled={busy}
          class="rounded border border-[#003366] bg-white px-3 py-2 text-xs font-semibold text-[#003366] hover:bg-[#F2F2F2] disabled:opacity-50"
          onclick={() => onExportCompareDiffs('CSV')}
        >
          Export Diffs CSV
        </button>
        <button
          type="button"
          disabled={busy}
          class="rounded border border-[#003366] bg-white px-3 py-2 text-xs font-semibold text-[#003366] hover:bg-[#F2F2F2] disabled:opacity-50"
          onclick={() => onExportCompareDiffs('TSV')}
        >
          Export Diffs TSV
        </button>
      {/if}
    </div>

    {#if cmpResult}
      <p class="text-xs text-[#313132]">
        Total Plots: {cmpResult.totalPlots} | Added: {cmpResult.addedCount} | Removed: {cmpResult.removedCount} | Modified: {cmpResult.modifiedCount} | Identical: {cmpResult.identicalCount}
        {#if (cmpResult.metadataDiffCount ?? cmpResult.metadataDiffs?.length ?? 0) > 0}
          | Metadata Diffs: {cmpResult.metadataDiffCount ?? cmpResult.metadataDiffs?.length ?? 0}
        {/if}
      </p>
      {#if cmpAllDiffs.length > 0}
        <div class="max-h-60 overflow-auto rounded border border-[#D8D8D8]">
          <table class="w-full text-left text-xs">
            <thead class="bg-[#F2F2F2] text-[#313132]">
              <tr><th class="p-2">Plot</th><th class="p-2">Table</th><th class="p-2">Key / Field</th><th class="p-2">Source</th><th class="p-2">Target</th></tr>
            </thead>
            <tbody>
              {#each cmpAllDiffs as d}
                <tr class="border-t border-[#D8D8D8]">
                  <td class="p-2 font-mono">{d.plotNumber || '—'}</td>
                  <td class="p-2">{d.table}</td>
                  <td class="p-2 font-mono">{d.key}{d.field && d.field !== d.key ? `.${d.field}` : ''}</td>
                  <td class="p-2 font-mono">{d.sourceVal ?? 'NULL'}</td>
                  <td class="p-2 font-mono">{d.targetVal ?? 'NULL'}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {/if}
      {#if cmpExportPreview}
        <p class="text-[11px] text-[#2E8540]">Exported {cmpExportPreview.format} ({cmpExportPreview.text.split('\n').length - 1} diff rows).</p>
      {/if}
    {/if}
  </fieldset>

  <!-- 3-Way Merge -->
  <fieldset class="min-w-0 space-y-3 rounded border border-[#D8D8D8] border-t-[3px] border-t-[#FCBA19] p-4">
    <legend class="px-1 text-sm font-semibold text-[#003366]">Controlled 3-Way Project Merge</legend>
    <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
      <div class="space-y-1">
        <label class="block text-xs font-semibold text-[#313132]" for="merge-source-path">Staging Source .db Path (required)</label>
        <input id="merge-source-path" type="text" class="w-full rounded border border-[#9F9F9F] p-2 text-sm font-mono" bind:value={mergeSourcePath} disabled={busy} />
      </div>
      <div class="space-y-1">
        <label class="block text-xs font-semibold text-[#313132]" for="merge-source-proj">Source Project (optional)</label>
        <input id="merge-source-proj" type="text" class="w-full rounded border border-[#9F9F9F] p-2 text-sm" bind:value={mergeSourceProject} disabled={busy} />
      </div>
      <div class="space-y-1">
        <label class="block text-xs font-semibold text-[#313132]" for="merge-base-path">Base Ancestor .db Path (optional)</label>
        <input id="merge-base-path" type="text" class="w-full rounded border border-[#9F9F9F] p-2 text-sm font-mono" bind:value={mergeBasePath} disabled={busy} />
      </div>
      <div class="space-y-1">
        <label class="block text-xs font-semibold text-[#313132]" for="merge-base-proj">Base Project (optional)</label>
        <input id="merge-base-proj" type="text" class="w-full rounded border border-[#9F9F9F] p-2 text-sm" bind:value={mergeBaseProject} disabled={busy} />
      </div>
      <div class="space-y-1">
        <label class="block text-xs font-semibold text-[#313132]" for="merge-target-path">Target .db Path (blank = active)</label>
        <input id="merge-target-path" type="text" class="w-full rounded border border-[#9F9F9F] p-2 text-sm font-mono" bind:value={mergeTargetPath} disabled={busy} />
      </div>
      <div class="space-y-1">
        <label class="block text-xs font-semibold text-[#313132]" for="merge-target-proj">Target Project (optional)</label>
        <input id="merge-target-proj" type="text" class="w-full rounded border border-[#9F9F9F] p-2 text-sm" bind:value={mergeTargetProject} disabled={busy} />
      </div>
    </div>
    <label class="flex items-center gap-2 text-xs text-[#313132]">
      <input id="merge-case-insensitive" type="checkbox" bind:checked={mergeCaseInsensitive} disabled={busy} />
      Case-insensitive text matching during 3-way merge
    </label>
    <div class="flex flex-wrap items-center gap-2">
      <button
        type="button"
        disabled={busy || !mergeSourcePath.trim()}
        class="rounded bg-[#003366] px-4 py-2 text-sm font-semibold text-white hover:bg-[#002244] disabled:opacity-50"
        onclick={onPreviewMerge}
      >
        Preview 3-Way Merge
      </button>
      {#if mergePreview}
        <select class="rounded border border-[#9F9F9F] p-2 text-xs" bind:value={mergeDefaultResolution} disabled={busy} aria-label="Default conflict resolution">
          <option value="keep_target">Default: Keep Target</option>
          <option value="accept_source">Default: Accept Source</option>
        </select>
        <button
          type="button"
          disabled={busy}
          class="rounded border-2 border-[#FCBA19] bg-[#003366] px-4 py-2 text-sm font-semibold text-white hover:bg-[#002244] disabled:opacity-50"
          onclick={onExecuteMerge}
        >
          Apply 3-Way Merge
        </button>
      {/if}
    </div>

    {#if mergePreview}
      <p class="text-xs text-[#313132]">
        Added: {mergePreview.addedCount} | Fast-Forward: {mergePreview.fastForwardCount} | Source Deletes: {mergePreview.sourceDeleteCount ?? 0} | Conflicts: {mergePreview.conflictCount} | Target-Only: {mergePreview.targetOnlyCount} | Identical: {mergePreview.identicalCount}
      </p>

      {#if (mergePreview.plots?.length ?? 0) > 0}
        <div class="space-y-1">
          <h4 class="m-0 text-xs font-semibold text-[#003366]">Per-Plot Merge Resolutions ({mergePreview.plots.length} plots)</h4>
          <div class="max-h-56 overflow-auto rounded border border-[#D8D8D8]">
            <table class="w-full text-left text-xs">
              <thead class="bg-[#F2F2F2] text-[#313132]">
                <tr><th class="p-2">Plot</th><th class="p-2">Category</th><th class="p-2">Items</th><th class="p-2">Plot Resolution</th></tr>
              </thead>
              <tbody>
                {#each mergePreview.plots as plot (plot.plotNumber)}
                  <tr class="border-t border-[#D8D8D8]">
                    <td class="p-2 font-mono font-semibold">{plot.plotNumber}</td>
                    <td class="p-2">{plot.category}</td>
                    <td class="p-2 font-mono">{plot.items?.length ?? 0}</td>
                    <td class="p-2">
                      <select
                        aria-label={`Plot merge resolution for ${plot.plotNumber}`}
                        data-merge-plot-resolution={plot.plotNumber}
                        class="rounded border border-[#9F9F9F] p-1 text-xs"
                        disabled={busy || plot.category === 'Identical' || plot.category === 'TargetOnly'}
                        value={mergePlotResolutions[plot.plotNumber] ?? (plot.category === 'Added' || plot.category === 'FastForward' || plot.category === 'SourceDelete' ? 'accept_source' : 'keep_target')}
                        onchange={e => onSetPlotResolution(plot.plotNumber, e.currentTarget.value as MergeResolutionChoice)}
                      >
                        <option value="keep_target">Keep Target</option>
                        <option value="accept_source">{plot.category === 'SourceDelete' ? 'Delete Plot (Accept Source)' : 'Accept Source'}</option>
                      </select>
                    </td>
                  </tr>
                {/each}
              </tbody>
            </table>
          </div>
        </div>
      {/if}

      {#if [...mergePreview.conflicts, ...(mergePreview.metadataItems ?? [])].length > 0}
        <div class="max-h-60 overflow-auto rounded border border-[#D8D8D8]">
          <table class="w-full text-left text-xs">
            <thead class="bg-[#F2F2F2] text-[#313132]">
              <tr>
                <th class="p-2">Plot / Field</th>
                <th class="p-2">Source</th>
                <th class="p-2">Target</th>
                <th class="p-2">Resolution</th>
              </tr>
            </thead>
            <tbody>
              {#each [...mergePreview.conflicts, ...(mergePreview.metadataItems ?? [])] as c}
                <tr class="border-t border-[#D8D8D8]">
                  <td class="p-2 font-mono">{c.plotNumber} {c.table}.{c.key}</td>
                  <td class="p-2 font-mono">{c.sourceVal ?? 'NULL'}</td>
                  <td class="p-2 font-mono">{c.targetVal ?? 'NULL'}</td>
                  <td class="p-2">
                    <select
                      aria-label={`Field conflict resolution for ${c.plotNumber} ${c.table}.${c.key}`}
                      data-merge-field-resolution={c.conflictId}
                      class="rounded border border-[#9F9F9F] p-1 text-xs"
                      value={mergeFieldResolutions[c.conflictId] ?? mergeDefaultResolution}
                      onchange={e => onSetFieldResolution(c.conflictId, e.currentTarget.value as MergeResolutionChoice)}
                    >
                      <option value="keep_target">Keep Target</option>
                      <option value="accept_source">Accept Source</option>
                    </select>
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {/if}
    {/if}

    {#if mergeResult}
      <p class="text-xs text-[#313132]">
        Merged {mergeResult.sourceProject} -&gt; {mergeResult.targetProject}: +{mergeResult.addedPlots} added, {mergeResult.updatedPlots} updated, {mergeResult.auditRowsWritten} audit entries.
      </p>
    {/if}
  </fieldset>
</div>
