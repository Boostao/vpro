<script lang="ts">
  import {
    CUSTODIAN_PROTECTED_FIELDS,
    isCustodianProtectedConflict,
    type CloudMergeConflictItem,
    type CloudMergeResolution,
    type StagingMergePreview,
    type StagingMergeResult,
    type StagingSubmissionDetail,
    type StagingSubmissionSummary,
  } from './cloudSyncWorkbench';

  interface Props {
    busy: boolean;
    operationHeld: boolean;
    submissions: StagingSubmissionSummary[];
    selectedSubmissionDetail: StagingSubmissionDetail | null;
    mergePreview: StagingMergePreview | null;
    combinedMergeItems: CloudMergeConflictItem[];
    mergePlotResolutions: Record<string, CloudMergeResolution>;
    mergeFieldResolutions: Record<string, CloudMergeResolution>;
    mergeReviewerNotes: string;
    mergeExecuteResult: StagingMergeResult | null;
    onRefreshSubmissions: (filter?: { status?: string; submittedBy?: string }) => void;
    onInspectSubmission: (id: string) => void;
    onPreviewMerge: (id: string, baseDbPath?: string) => void;
    onSetPlotResolution: (plotNumber: string, value: string) => void;
    onSetFieldResolution: (conflictId: string, choice: string) => void;
    onExecuteMerge: (opts?: { baseDbPath?: string; defaultConflictResolution?: CloudMergeResolution; actor?: string }) => void;
    onRejectSubmission: (actor?: string) => void;
  }

  let {
    busy,
    operationHeld,
    submissions,
    selectedSubmissionDetail,
    mergePreview,
    combinedMergeItems,
    mergePlotResolutions,
    mergeFieldResolutions,
    mergeReviewerNotes = $bindable(),
    mergeExecuteResult,
    onRefreshSubmissions,
    onInspectSubmission,
    onPreviewMerge,
    onSetPlotResolution,
    onSetFieldResolution,
    onExecuteMerge,
    onRejectSubmission,
  }: Props = $props();

  let submissionsStatusFilter = $state('');
  let submissionsSubmittedByFilter = $state('');
  let mergeBaseDbPath = $state('');
  let mergeDefaultResolution = $state<CloudMergeResolution>('keep_target');
  let mergeActor = $state('');
</script>

<!-- Staging Submissions Queue -->
<fieldset class="space-y-3 rounded border border-slate-300 border-t-[3px] border-t-[#FCBA19] p-4">
  <legend class="px-1 text-sm font-semibold text-[#003366]">Staging Submissions Queue (staging.submissions)</legend>
  <div class="flex flex-wrap items-end gap-2">
    <div class="space-y-1">
      <label class="block text-[11px] font-semibold text-slate-700" for="inbox-status-filter">Status</label>
      <select id="inbox-status-filter" class="rounded border border-slate-300 p-1.5 text-xs" bind:value={submissionsStatusFilter} disabled={busy || operationHeld}>
        <option value="">All Statuses</option>
        <option value="pending">pending</option>
        <option value="merged">merged</option>
        <option value="rejected">rejected</option>
      </select>
    </div>
    <div class="space-y-1">
      <label class="block text-[11px] font-semibold text-slate-700" for="inbox-submitter-filter">Submitted By</label>
      <input id="inbox-submitter-filter" type="text" class="rounded border border-slate-300 p-1.5 text-xs" bind:value={submissionsSubmittedByFilter} disabled={busy || operationHeld} placeholder="Any contributor" />
    </div>
    <div class="space-y-1">
      <label class="block text-[11px] font-semibold text-slate-700" for="merge-base-db-path">Optional Base .db Path</label>
      <input id="merge-base-db-path" type="text" class="rounded border border-slate-300 p-1.5 font-mono text-xs" bind:value={mergeBaseDbPath} disabled={busy || operationHeld} placeholder="Auto-resolve from snapshot" />
    </div>
    <button
      type="button"
      disabled={busy || operationHeld}
      class="rounded bg-[#003366] px-3 py-1.5 text-xs font-semibold text-white hover:bg-[#002244] disabled:opacity-50"
      onclick={() => onRefreshSubmissions({ status: submissionsStatusFilter, submittedBy: submissionsSubmittedByFilter })}
    >
      Refresh Staging Queue
    </button>
  </div>

  {#if submissions.length === 0}
    <p class="text-xs text-slate-600">No staging submissions loaded. Click Refresh Staging Queue to query <span class="font-mono">staging.submissions</span>.</p>
  {:else}
    <div class="overflow-x-auto rounded border border-slate-200">
      <table class="w-full text-left text-xs">
        <thead class="bg-slate-100 text-slate-700">
          <tr>
            <th class="p-2">Submission ID</th>
            <th class="p-2">Project</th>
            <th class="p-2">Submitter</th>
            <th class="p-2">Plots / Veg</th>
            <th class="p-2">Compliance</th>
            <th class="p-2">Provisional Spp</th>
            <th class="p-2">Status</th>
            <th class="p-2">Actions</th>
          </tr>
        </thead>
        <tbody>
          {#each submissions as sub (sub.submissionId)}
            <tr class="border-t border-slate-100">
              <td class="p-2 font-mono">{sub.submissionId}</td>
              <td class="p-2 font-mono font-semibold">{sub.projectName}</td>
              <td class="p-2">{sub.submittedBy}</td>
              <td class="p-2 font-mono">{sub.plotCount} / {sub.vegRowCount}</td>
              <td class="p-2">
                {#if sub.compliancePassed}
                  <span class="rounded bg-[#EBF5ED] px-1.5 py-0.5 font-semibold text-[#2E8540]">Passed</span>
                {:else}
                  <span class="rounded bg-red-100 px-1.5 py-0.5 font-semibold text-red-900">Failed</span>
                {/if}
              </td>
              <td class="p-2">
                {#if sub.userSpeciesCount > 0}
                  <span class="rounded bg-amber-100 px-1.5 py-0.5 font-mono font-semibold text-amber-950">{sub.userSpeciesCount} USysUserSpp</span>
                {:else}
                  <span class="text-slate-500">0</span>
                {/if}
              </td>
              <td class="p-2 font-semibold">{sub.status}</td>
              <td class="p-2">
                <div class="flex flex-wrap gap-1.5">
                  <button
                    type="button"
                    disabled={busy || operationHeld}
                    class="rounded border border-slate-300 bg-white px-2 py-1 text-[11px] font-semibold text-[#003366] hover:bg-slate-100 disabled:opacity-50"
                    onclick={() => onInspectSubmission(sub.submissionId)}
                  >
                    Inspect Details
                  </button>
                  <button
                    type="button"
                    disabled={busy || operationHeld}
                    class="rounded bg-[#003366] px-2 py-1 text-[11px] font-semibold text-white hover:bg-[#002244] disabled:opacity-50"
                    onclick={() => onPreviewMerge(sub.submissionId, mergeBaseDbPath)}
                  >
                    Review &amp; 3-Way Diff vs BECMaster
                  </button>
                </div>
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {/if}

  {#if selectedSubmissionDetail}
    <div class="space-y-2 rounded border border-slate-300 bg-slate-50 p-3 text-xs" data-submission-detail>
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h4 class="m-0 text-xs font-bold text-[#003366]">
          Submission Detail: <span class="font-mono">{selectedSubmissionDetail.summary.submissionId}</span> ({selectedSubmissionDetail.summary.projectName})
        </h4>
        <span class="font-mono text-[11px] text-slate-600">
          Lump Rows: {selectedSubmissionDetail.lumpRows.length} | SU Assignments: {selectedSubmissionDetail.suRows.length}
        </span>
      </div>
      {#if selectedSubmissionDetail.summary.submitterNotes}
        <p class="m-0 text-xs text-slate-700">Submitter Notes: {selectedSubmissionDetail.summary.submitterNotes}</p>
      {/if}
      {#if selectedSubmissionDetail.provisionalSpeciesDiffs.length > 0}
        <div class="overflow-x-auto rounded border border-slate-200 bg-white">
          <table class="w-full text-left text-[11px]">
            <thead class="bg-slate-100 text-slate-700">
              <tr>
                <th class="p-1.5">Submitted Code</th>
                <th class="p-1.5">Submitted Scientific</th>
                <th class="p-1.5">LifeForm</th>
                <th class="p-1.5">USysAllSpecs Status</th>
                <th class="p-1.5">Official Match</th>
              </tr>
            </thead>
            <tbody>
              {#each selectedSubmissionDetail.provisionalSpeciesDiffs as diff (diff.code)}
                <tr class="border-t border-slate-100">
                  <td class="p-1.5 font-mono font-semibold">{diff.code}</td>
                  <td class="p-1.5">{diff.scientificName ?? '—'}</td>
                  <td class="p-1.5 font-mono">{diff.lifeForm ?? '—'}</td>
                  <td class="p-1.5 font-semibold">{diff.status}</td>
                  <td class="p-1.5 font-mono">{diff.officialCode ? `${diff.officialCode} (${diff.officialScientific ?? ''})` : '—'}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {/if}
    </div>
  {/if}
</fieldset>

{#if mergePreview || mergeExecuteResult || selectedSubmissionDetail}
  <fieldset class="space-y-3 rounded border border-slate-300 border-t-[3px] border-t-[#FCBA19] p-4" data-cloud-merge-panel>
    <legend class="px-1 text-sm font-semibold text-[#003366]">Interactive 3-Way Merge Resolution vs BECMaster</legend>

    {#if mergePreview}
      <div class="grid grid-cols-2 gap-2 sm:grid-cols-5">
        <div class="rounded border border-slate-300 p-2.5">
          <div class="text-[11px] text-slate-600">Added Plots</div>
          <div class="font-mono text-lg font-bold text-[#003366]">{mergePreview.addedCount}</div>
        </div>
        <div class="rounded border border-slate-300 p-2.5">
          <div class="text-[11px] text-slate-600">Identical Plots</div>
          <div class="font-mono text-lg font-bold text-[#003366]">{mergePreview.identicalCount}</div>
        </div>
        <div class="rounded border border-slate-300 p-2.5">
          <div class="text-[11px] text-slate-600">Fast-Forward</div>
          <div class="font-mono text-lg font-bold text-[#003366]">{mergePreview.fastForwardCount}</div>
        </div>
        <div class="rounded border border-slate-300 p-2.5">
          <div class="text-[11px] text-slate-600">Conflicts</div>
          <div class="font-mono text-lg font-bold text-red-800">{mergePreview.conflictCount}</div>
        </div>
        <div class="rounded border border-amber-400 bg-amber-50 p-2.5">
          <div class="text-[11px] font-semibold text-amber-950">Custodian-Protected</div>
          <div class="font-mono text-lg font-bold text-amber-950">{mergePreview.custodianProtectedDiffs.length}</div>
        </div>
      </div>

      <p class="text-xs text-slate-600">
        Digest: <span class="font-mono">{mergePreview.previewDigest}</span> &middot; Protected BEC fields (<span class="font-mono">{CUSTODIAN_PROTECTED_FIELDS.join(', ')}</span>) default to keeping canonical BECMaster values unless explicitly overridden below.
      </p>

      {#if mergePreview.plots.length > 0}
        <div class="max-h-40 overflow-auto rounded border border-slate-200">
          <table class="w-full text-left text-xs">
            <thead class="bg-slate-100 text-slate-700">
              <tr>
                <th class="p-2">Plot</th>
                <th class="p-2">Category</th>
                <th class="p-2">Diff Items</th>
                <th class="p-2">Plot-Level Resolution Override</th>
              </tr>
            </thead>
            <tbody>
              {#each mergePreview.plots as plot (plot.plotNumber)}
                <tr class="border-t border-slate-100">
                  <td class="p-2 font-mono font-semibold">{plot.plotNumber}</td>
                  <td class="p-2">{plot.category}</td>
                  <td class="p-2 font-mono">{plot.items.length}</td>
                  <td class="p-2">
                    <select
                      aria-label={`Plot resolution for ${plot.plotNumber}`}
                      class="rounded border border-slate-300 p-1 text-xs"
                      value={mergePlotResolutions[plot.plotNumber] ?? ''}
                      disabled={busy || operationHeld}
                      onchange={e => onSetPlotResolution(plot.plotNumber, e.currentTarget.value)}
                    >
                      <option value="">Use Field / Default Resolution</option>
                      <option value="keep_target">Keep BECMaster</option>
                      <option value="accept_source">Accept Staging</option>
                    </select>
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {/if}

      {#if combinedMergeItems.length > 0}
        <div class="max-h-72 overflow-auto rounded border border-slate-200">
          <table class="w-full text-left text-xs">
            <thead class="bg-slate-100 text-slate-700">
              <tr>
                <th class="p-2">Plot / Table.Field</th>
                <th class="p-2">Base</th>
                <th class="p-2">Staging (Source)</th>
                <th class="p-2">BECMaster (Target)</th>
                <th class="p-2">Governance</th>
                <th class="p-2">Resolution</th>
              </tr>
            </thead>
            <tbody>
              {#each combinedMergeItems as item (item.conflictId)}
                {@const protectedField = isCustodianProtectedConflict(item)}
                <tr class={`border-t border-slate-100 ${protectedField ? 'bg-amber-50' : ''}`}>
                  <td class="p-2 font-mono">
                    {item.plotNumber} {item.table}.{item.field}
                    {#if item.key && item.key !== item.field}
                      <span class="text-slate-500">[{item.key}]</span>
                    {/if}
                  </td>
                  <td class="p-2 font-mono text-slate-600">{item.baseVal ?? 'NULL'}</td>
                  <td class="p-2 font-mono">{item.sourceVal ?? 'NULL'}</td>
                  <td class="p-2 font-mono">{item.targetVal ?? 'NULL'}</td>
                  <td class="p-2">
                    {#if protectedField}
                      <span class="rounded border border-amber-500 bg-[#FCBA19]/30 px-1.5 py-0.5 text-[11px] font-bold text-[#003366]" data-custodian-protected-badge>
                        Custodian Protected
                      </span>
                    {:else}
                      <span class="text-slate-600">{item.kind}</span>
                    {/if}
                  </td>
                  <td class="p-2">
                    <select
                      aria-label={`Field resolution for ${item.conflictId}`}
                      class="rounded border border-slate-300 bg-white p-1 text-xs"
                      value={mergeFieldResolutions[item.conflictId] ?? ''}
                      disabled={busy || operationHeld}
                      onchange={e => onSetFieldResolution(item.conflictId, e.currentTarget.value)}
                    >
                      {#if !protectedField}
                        <option value="">Follow Plot / Default ({mergePlotResolutions[item.plotNumber] ?? mergeDefaultResolution})</option>
                      {/if}
                      <option value="keep_target">Keep BECMaster</option>
                      <option value="accept_source">Accept Staging</option>
                    </select>
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {/if}
    {/if}

    <div class="grid grid-cols-1 gap-2 sm:grid-cols-3">
      <div class="space-y-1">
        <label class="block text-xs font-semibold text-slate-700" for="merge-default-res">Default Conflict Policy</label>
        <select id="merge-default-res" class="w-full rounded border border-slate-300 p-2 text-xs" bind:value={mergeDefaultResolution} disabled={busy || operationHeld}>
          <option value="keep_target">Keep BECMaster (keep_target)</option>
          <option value="accept_source">Accept Staging (accept_source)</option>
        </select>
      </div>
      <div class="space-y-1">
        <label class="block text-xs font-semibold text-slate-700" for="merge-actor">Custodian Reviewer ID (opt)</label>
        <input id="merge-actor" type="text" class="w-full rounded border border-slate-300 p-2 text-xs" bind:value={mergeActor} disabled={busy || operationHeld} placeholder="Provincial Correlation Lead" />
      </div>
      <div class="space-y-1">
        <label class="block text-xs font-semibold text-slate-700" for="merge-reviewer-notes">Reviewer Notes (required to reject)</label>
        <input id="merge-reviewer-notes" type="text" class="w-full rounded border border-slate-300 p-2 text-xs" bind:value={mergeReviewerNotes} disabled={busy || operationHeld} placeholder="Audit / rejection rationale" />
      </div>
    </div>

    <div class="flex flex-wrap gap-2">
      <button
        type="button"
        disabled={busy || operationHeld || !mergePreview}
        class="rounded border-2 border-[#FCBA19] bg-[#003366] px-4 py-2 text-xs font-semibold text-white hover:bg-[#002244] disabled:opacity-50"
        onclick={() => onExecuteMerge({ baseDbPath: mergeBaseDbPath, defaultConflictResolution: mergeDefaultResolution, actor: mergeActor })}
      >
        Approve &amp; Merge into BECMaster
      </button>
      <button
        type="button"
        disabled={busy || operationHeld || (!mergePreview && !selectedSubmissionDetail)}
        class="rounded border border-red-700 bg-red-700 px-4 py-2 text-xs font-semibold text-white hover:bg-red-800 disabled:opacity-50"
        onclick={() => onRejectSubmission(mergeActor)}
      >
        Reject with Notes
      </button>
    </div>

    {#if mergeExecuteResult}
      <p class="text-xs font-medium text-[#2E8540]">
        Committed Merge <span class="font-mono font-bold">{mergeExecuteResult.mergeTxId}</span>: +{mergeExecuteResult.addedPlots} added, {mergeExecuteResult.updatedPlots} updated, {mergeExecuteResult.auditRowsWritten} audit rows (tail hash <span class="font-mono">{mergeExecuteResult.tailAuditHash.slice(0, 16)}</span>).
      </p>
    {/if}
  </fieldset>
{/if}
