<script lang="ts">
  import type {
    OptimizeVegPreview,
    OptimizeVegResult,
  } from './projectAdminWorkbench';

  let {
    busy,
    optPlotNumbersRaw = $bindable(''),
    optCustodianAuditOverride = $bindable(false),
    optConfirmReviewed = $bindable(false),
    optPreview,
    optResult,
    optUnresolvedConflictCount,
    onOverrideChange,
    onPreviewOptimizeVeg,
    onApplyOptimizeVeg,
  }: {
    busy: boolean;
    optPlotNumbersRaw?: string;
    optCustodianAuditOverride?: boolean;
    optConfirmReviewed?: boolean;
    optPreview: OptimizeVegPreview | null;
    optResult: OptimizeVegResult | null;
    optUnresolvedConflictCount: number;
    onOverrideChange: () => void;
    onPreviewOptimizeVeg: () => void;
    onApplyOptimizeVeg: () => void;
  } = $props();
</script>

<div class="space-y-4">
  <div class="space-y-3 rounded border border-[#D8D8D8] bg-[#F2F2F2] p-3">
    <div class="text-xs text-[#313132]">
      Mandatory Dry-Run Safety Gate: consolidates split multi-row <span class="font-mono">(PlotNumber, Species)</span> records atomically using <span class="font-semibold">MAX(Height*)</span> and IEEE-754 SINGLE &lt;100 cover capping (99%), retiring deleted child IDs in <span class="font-mono">__VPRO_ChildIdentity</span>.
    </div>
    <div class="flex flex-wrap items-end gap-3">
      <div class="min-w-0 flex-1 space-y-1">
        <label class="block text-xs font-semibold text-[#313132]" for="opt-plot-filter">Plot Subset Filter (comma-separated, blank = all plots)</label>
        <input id="opt-plot-filter" type="text" class="w-full rounded border border-[#9F9F9F] bg-white p-2 text-xs font-mono" bind:value={optPlotNumbersRaw} disabled={busy} placeholder="e.g. 00337, 108050" />
      </div>
      <label class="flex items-center gap-2 text-xs text-[#313132]">
        <input
          type="checkbox"
          bind:checked={optCustodianAuditOverride}
          disabled={busy}
          onchange={onOverrideChange}
        />
        Custodian Audit Override (allow retiring _Audit-referenced IDs)
      </label>
      <button
        type="button"
        disabled={busy}
        class="rounded bg-[#003366] px-4 py-2 text-sm font-semibold text-white hover:bg-[#002244] disabled:opacity-50"
        onclick={onPreviewOptimizeVeg}
      >
        Preview OptimizeVeg
      </button>
    </div>
  </div>

  {#if optPreview}
    <div class="grid grid-cols-2 gap-3 sm:grid-cols-5">
      <div class="rounded border border-[#D8D8D8] p-3">
        <div class="text-xs text-[#474543]">Before Rows</div>
        <div class="text-lg font-bold text-[#003366]">{optPreview.beforeRowCount}</div>
      </div>
      <div class="rounded border border-[#D8D8D8] p-3">
        <div class="text-xs text-[#474543]">After Rows</div>
        <div class="text-lg font-bold text-[#003366]">{optPreview.afterRowCount}</div>
      </div>
      <div class="rounded border border-[#D8D8D8] p-3">
        <div class="text-xs text-[#474543]">Overlapping Layer Groups</div>
        <div class="text-lg font-bold text-[#003366]">{optPreview.overlappingGroupCount}</div>
      </div>
      <div class="rounded border border-[#D8D8D8] p-3">
        <div class="text-xs text-[#474543]">Covers Capped at 99%</div>
        <div class="text-lg font-bold text-[#003366]">{optPreview.cappedCoverCount}</div>
      </div>
      <div class="rounded border border-[#D8D8D8] p-3">
        <div class="text-xs text-[#474543]">Unresolved Conflicts</div>
        <div class={`text-lg font-bold ${optUnresolvedConflictCount > 0 ? 'text-[#D8292F]' : 'text-[#2E8540]'}`}>{optUnresolvedConflictCount}</div>
      </div>
    </div>

    {#if (optPreview.conflicts?.length ?? 0) > 0}
      <div class="space-y-2 rounded border border-[#D8292F] bg-[#FBEAEA] p-3">
        <h3 class="m-0 text-xs font-bold text-[#D8292F]">Blocking Conflicts ({optPreview.conflicts?.length}) — Commit Disabled Until Resolved</h3>
        <div class="overflow-x-auto rounded border border-[#D8D8D8] bg-white">
          <table class="w-full text-left text-xs">
            <thead class="bg-[#F2F2F2] text-[#313132]">
              <tr><th class="p-2">Plot</th><th class="p-2">Species</th><th class="p-2">Field</th><th class="p-2">Reason</th><th class="p-2">Conflicting Values</th><th class="p-2">Overrideable</th></tr>
            </thead>
            <tbody>
              {#each optPreview.conflicts ?? [] as c}
                <tr class="border-t border-[#D8D8D8]">
                  <td class="p-2 font-mono">{c.plotNumber}</td>
                  <td class="p-2 font-mono font-semibold">{c.species}</td>
                  <td class="p-2 font-mono">{c.field}</td>
                  <td class="p-2 text-[#D8292F]">{c.reason}</td>
                  <td class="p-2 font-mono">{c.values?.join(' vs ') || '—'}</td>
                  <td class="p-2">{c.overrideable ? 'Audit Override' : 'Manual Fix Required'}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      </div>
    {/if}

    {#if (optPreview.auditReferences?.length ?? 0) > 0}
      <div class="space-y-2 rounded border border-[#FCBA19] bg-[#FEF6E0] p-3">
        <h3 class="m-0 text-xs font-bold text-[#313132]">Retired IDs Referenced in _Audit ({optPreview.auditReferences?.length})</h3>
        <div class="overflow-x-auto rounded border border-[#D8D8D8] bg-white">
          <table class="w-full text-left text-xs">
            <thead class="bg-[#F2F2F2] text-[#313132]">
              <tr><th class="p-2">Plot</th><th class="p-2">Species</th><th class="p-2">Retired ID</th><th class="p-2">Table.Field</th><th class="p-2">EditWhen</th></tr>
            </thead>
            <tbody>
              {#each optPreview.auditReferences ?? [] as ref}
                <tr class="border-t border-[#D8D8D8]">
                  <td class="p-2 font-mono">{ref.plotNumber}</td>
                  <td class="p-2 font-mono">{ref.species}</td>
                  <td class="p-2 font-mono">{ref.retiredId}</td>
                  <td class="p-2 font-mono">{ref.table}.{ref.editField}</td>
                  <td class="p-2 font-mono">{ref.editWhen}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      </div>
    {/if}

    {#if optPreview.duplicateSpeciesCount > 0}
      <div class="flex flex-wrap items-center justify-between gap-3 rounded border border-[#FCBA19] bg-[#FEF6E0] p-3">
        <label class="flex items-center gap-2 text-xs font-semibold text-[#313132]">
          <input
            type="checkbox"
            data-optimizeveg-confirm
            bind:checked={optConfirmReviewed}
            disabled={busy || optUnresolvedConflictCount > 0}
          />
          I have reviewed conflicts and want to commit OptimizeVeg
        </label>
        <button
          type="button"
          disabled={busy || optUnresolvedConflictCount > 0 || !optConfirmReviewed}
          class="rounded border-2 border-[#FCBA19] bg-[#003366] px-4 py-2 text-sm font-semibold text-white hover:bg-[#002244] disabled:opacity-50"
          onclick={onApplyOptimizeVeg}
        >
          Apply Consolidation ({optPreview.rowsToConsolidate} duplicate rows)
        </button>
      </div>
    {/if}

    {#if optPreview.groups.length > 0}
      <div class="overflow-x-auto rounded border border-[#D8D8D8]">
        <table class="w-full text-left text-xs">
          <thead class="bg-[#F2F2F2] text-[#313132]">
            <tr>
              <th class="p-2">Plot</th>
              <th class="p-2">Species</th>
              <th class="p-2">Rows</th>
              <th class="p-2">Survivor ID</th>
              <th class="p-2">Retired IDs</th>
              <th class="p-2">Merged Covers</th>
              <th class="p-2">MAX Heights</th>
              <th class="p-2">Status</th>
            </tr>
          </thead>
          <tbody>
            {#each optPreview.groups as grp}
              <tr class="border-t border-[#D8D8D8]">
                <td class="p-2 font-mono">{grp.plotNumber}</td>
                <td class="p-2 font-mono font-semibold">{grp.species}</td>
                <td class="p-2">{grp.sourceRowCount}</td>
                <td class="p-2 font-mono">{grp.survivorId}</td>
                <td class="p-2 font-mono">{grp.retiredIds.join(', ')}</td>
                <td class="p-2 font-mono">{Object.entries(grp.mergedCovers).map(([k, v]) => `${k}=${v}`).join(', ')}</td>
                <td class="p-2 font-mono">{Object.entries(grp.mergedHeights).map(([k, v]) => `${k}=${v}`).join(', ')}</td>
                <td class="p-2 font-semibold {grp.blocked ? 'text-[#D8292F]' : 'text-[#2E8540]'}">{grp.blocked ? (grp.blockedReasons?.join('; ') || 'Blocked') : 'Ready'}</td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
  {/if}

  {#if optResult}
    <p class="text-xs text-[#313132]">Committed OptimizeVeg: {optResult.beforeRowCount} -&gt; {optResult.afterRowCount} rows; retired IDs reserved: {optResult.reservedDeletedIds.join(', ') || 'none'}.</p>
  {/if}
</div>
