<script lang="ts">
  import type {
    ComplianceValidationReport,
    QuarantineOrphanResult,
  } from './projectAdminWorkbench';

  let {
    busy,
    activeSu,
    complianceUseSu = $bindable(false),
    confirmQuarantine = $bindable(false),
    complianceReport,
    quarantineResult,
    findingCounts = null,
    onRunCompliance,
    onRunQuarantine,
    onOpenOptimizeVeg,
  }: {
    busy: boolean;
    activeSu: string;
    complianceUseSu?: boolean;
    confirmQuarantine?: boolean;
    complianceReport: ComplianceValidationReport | null;
    quarantineResult: QuarantineOrphanResult | null;
    findingCounts?: { envAdmin: number; orphan: number; taxonomy: number } | null;
    onRunCompliance: () => void;
    onRunQuarantine: () => void;
    onOpenOptimizeVeg: () => void;
  } = $props();
</script>

<div class="space-y-4">
  <div class="flex flex-wrap items-center justify-between gap-3 rounded border border-vpro-border bg-vpro-surface-subtle p-3">
    <label class="flex items-center gap-2 text-sm text-vpro-ink">
      <input type="checkbox" bind:checked={complianceUseSu} disabled={busy || activeSu === 'None'} />
      Restrict code &amp; bounds checks to active SU ({activeSu})
    </label>
    <button
      type="button"
      disabled={busy}
      class="rounded bg-vpro-navy px-4 py-2 text-sm font-semibold text-white hover:bg-vpro-navy-dark disabled:opacity-50"
      onclick={onRunCompliance}
    >
      Run Batch Compliance Check
    </button>
  </div>

  {#if complianceReport}
    <div class="flex flex-wrap items-center justify-between gap-2 rounded border border-vpro-border bg-vpro-canvas px-3 py-2 text-xs text-vpro-ink">
      <span>
        Scope: <strong>{complianceReport.project}</strong>
        ({complianceReport.useActiveSu ? `Active SU: ${complianceReport.su}` : `Whole Project; SU context: ${complianceReport.su}`})
        &middot; SU&harr;Env orphan integrity &amp; 8 compliance slices evaluated
        {#if findingCounts}
          &middot; Mismatches/Orphans/Taxonomy: {findingCounts.envAdmin}/{findingCounts.orphan}/{findingCounts.taxonomy}
        {/if}
      </span>
      <span class={`rounded px-2 py-0.5 font-semibold ${complianceReport.passed ? 'bg-vpro-success-bg text-vpro-success' : 'bg-vpro-error-bg text-vpro-error'}`}>
        {complianceReport.passed ? 'PASSED' : 'ISSUES FOUND'}
      </span>
    </div>

    <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
      <div class="rounded border border-vpro-border p-3">
        <div class="text-xs text-vpro-ink-secondary">USysTableOfLists Errors</div>
        <div class="text-xl font-bold text-vpro-navy">{complianceReport.summary.envCodeErrors}</div>
      </div>
      <div class="rounded border border-vpro-border p-3">
        <div class="text-xs text-vpro-ink-secondary">Numeric / Text / Cover Bounds</div>
        <div class="text-xl font-bold text-vpro-navy">{complianceReport.summary.boundsErrors}</div>
      </div>
      <div class="rounded border border-vpro-border p-3">
        <div class="text-xs text-vpro-ink-secondary">1:1 Env/Admin &amp; 1:N Orphans</div>
        <div class="text-xl font-bold text-vpro-navy">{complianceReport.summary.envAdminMismatches + complianceReport.summary.orphanChildRows}</div>
      </div>
      <div class="rounded border border-vpro-border p-3">
        <div class="text-xs text-vpro-ink-secondary">Veg Splits / Synonyms / Unlisted</div>
        <div class="text-xl font-bold text-vpro-navy">{complianceReport.summary.duplicateSpeciesSplits + complianceReport.summary.synonymSpecies + complianceReport.summary.unlistedSpecies}</div>
      </div>
      <div class="rounded border border-vpro-border p-3">
        <div class="text-xs text-vpro-ink-secondary">Plots Without Veg / User Spp</div>
        <div class="text-xl font-bold text-vpro-navy">{complianceReport.summary.plotsWithoutVeg} / {complianceReport.summary.userSpecies}</div>
      </div>
    </div>

    {#if complianceReport.summary.orphanChildRows > 0}
      <div class="space-y-2 rounded border border-vpro-gold bg-vpro-warning-bg p-4">
        <h3 class="m-0 text-sm font-semibold text-vpro-ink">Orphan Child Records Detected ({complianceReport.summary.orphanChildRows} rows)</h3>
        <p class="text-xs text-vpro-ink">Quarantining moves orphan child rows (_Veg, _Humus, _Mineral, _Other, _Audit, and active *_SU rows missing from _Env) into quarantine tables, permanently reserves their child IDs so they are never reused, and writes an audit record so no data is silently lost.</p>
        <label class="flex items-center gap-2 text-xs font-medium text-vpro-ink">
          <input type="checkbox" bind:checked={confirmQuarantine} disabled={busy} />
          Confirm move to quarantine tables
        </label>
        <button
          type="button"
          disabled={busy || !confirmQuarantine}
          class="rounded bg-vpro-navy px-3 py-2 text-xs font-semibold text-white hover:bg-vpro-navy-dark disabled:opacity-50"
          onclick={onRunQuarantine}
        >
          Quarantine Orphan Child Rows
        </button>
      </div>
    {/if}

    {#if quarantineResult}
      <p class="text-xs text-vpro-ink">Last quarantine batch <span class="font-mono">{quarantineResult.batchId}</span> moved {quarantineResult.totalQuarantined} row(s).</p>
    {/if}

    {#if (complianceReport.envCodeFindings?.length ?? 0) > 0}
      <div class="space-y-1">
        <h4 class="m-0 text-xs font-semibold text-vpro-navy">1. Code Validation (USysTableOfLists) — {complianceReport.envCodeFindings.length} finding(s)</h4>
        <div class="overflow-x-auto rounded border border-vpro-border">
          <table class="w-full text-left text-xs">
            <thead class="bg-vpro-canvas text-vpro-ink">
              <tr><th class="p-2">Plot</th><th class="p-2">Field</th><th class="p-2">ListName</th><th class="p-2">Invalid Value</th></tr>
            </thead>
            <tbody>
              {#each complianceReport.envCodeFindings as item}
                <tr class="border-t border-vpro-border">
                  <td class="p-2 font-mono">{item.plotNumber}</td>
                  <td class="p-2">{item.field}</td>
                  <td class="p-2">{item.listName}</td>
                  <td class="p-2 font-mono text-vpro-error">{item.value}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      </div>
    {/if}

    {#if (complianceReport.skippedDefinitions?.length ?? 0) > 0}
      <div class="space-y-1">
        <h4 class="m-0 text-xs font-semibold text-vpro-navy">2. Skipped List Definitions — {complianceReport.skippedDefinitions?.length} item(s)</h4>
        <div class="overflow-x-auto rounded border border-vpro-border">
          <table class="w-full text-left text-xs">
            <thead class="bg-vpro-canvas text-vpro-ink">
              <tr><th class="p-2">ListName</th><th class="p-2">Field</th><th class="p-2">Reason</th></tr>
            </thead>
            <tbody>
              {#each complianceReport.skippedDefinitions ?? [] as skipped}
                <tr class="border-t border-vpro-border">
                  <td class="p-2 font-mono">{skipped.listName}</td>
                  <td class="p-2">{skipped.field}</td>
                  <td class="p-2 text-vpro-ink-secondary">{skipped.reason}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      </div>
    {/if}

    {#if (complianceReport.boundsFindings?.length ?? 0) > 0}
      <div class="space-y-1">
        <h4 class="m-0 text-xs font-semibold text-vpro-navy">3. Numeric, Text &amp; LMH25 Horizon Bounds — {complianceReport.boundsFindings.length} finding(s)</h4>
        <div class="overflow-x-auto rounded border border-vpro-border">
          <table class="w-full text-left text-xs">
            <thead class="bg-vpro-canvas text-vpro-ink">
              <tr><th class="p-2">Table</th><th class="p-2">Plot</th><th class="p-2">Field</th><th class="p-2">Value</th><th class="p-2">Rule</th></tr>
            </thead>
            <tbody>
              {#each complianceReport.boundsFindings as b}
                <tr class="border-t border-vpro-border">
                  <td class="p-2">{b.table}</td>
                  <td class="p-2 font-mono">{b.plotNumber}</td>
                  <td class="p-2">{b.field}</td>
                  <td class="p-2 font-mono text-vpro-error">{b.value}</td>
                  <td class="p-2">{b.rule}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      </div>
    {/if}

    {#if (complianceReport.envAdminFindings?.length ?? 0) > 0}
      <div class="space-y-1">
        <h4 class="m-0 text-xs font-semibold text-vpro-navy">4. 1:1 Env &harr; Admin Completeness — {complianceReport.envAdminFindings.length} mismatch(es)</h4>
        <div class="overflow-x-auto rounded border border-vpro-border">
          <table class="w-full text-left text-xs">
            <thead class="bg-vpro-canvas text-vpro-ink">
              <tr><th class="p-2">Plot</th><th class="p-2">Issue</th></tr>
            </thead>
            <tbody>
              {#each complianceReport.envAdminFindings as ea}
                <tr class="border-t border-vpro-border">
                  <td class="p-2 font-mono">{ea.plotNumber}</td>
                  <td class="p-2 text-vpro-error">{ea.issue}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      </div>
    {/if}

    {#if (complianceReport.orphanFindings?.length ?? 0) > 0}
      <div class="space-y-1">
        <h4 class="m-0 text-xs font-semibold text-vpro-navy">5. 1:N Orphan Child &amp; SU Rows — {complianceReport.orphanFindings.length} group(s)</h4>
        <div class="overflow-x-auto rounded border border-vpro-border">
          <table class="w-full text-left text-xs">
            <thead class="bg-vpro-canvas text-vpro-ink">
              <tr><th class="p-2">Table</th><th class="p-2">Plot</th><th class="p-2">Orphan Row Count</th></tr>
            </thead>
            <tbody>
              {#each complianceReport.orphanFindings as o}
                <tr class="border-t border-vpro-border">
                  <td class="p-2 font-mono font-semibold">{o.table}</td>
                  <td class="p-2 font-mono">{o.plotNumber}</td>
                  <td class="p-2 font-mono text-vpro-error">{o.rowCount}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      </div>
    {/if}

    {#if (complianceReport.plotsWithoutVegetation?.length ?? 0) > 0}
      <div class="space-y-1">
        <h4 class="m-0 text-xs font-semibold text-vpro-navy">6. Plots Without Vegetation Records — {complianceReport.plotsWithoutVegetation.length} plot(s)</h4>
        <div class="flex flex-wrap gap-1.5 rounded border border-vpro-border bg-vpro-canvas p-2.5 text-xs font-mono">
          {#each complianceReport.plotsWithoutVegetation as plotNo}
            <span class="rounded border border-vpro-border bg-white px-2 py-0.5 text-vpro-ink">{plotNo}</span>
          {/each}
        </div>
      </div>
    {/if}

    {#if (complianceReport.duplicateVegFindings?.length ?? 0) > 0}
      <div class="space-y-1">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <h4 class="m-0 text-xs font-semibold text-vpro-navy">7. Duplicate Multi-Row Vegetation Species Splits — {complianceReport.duplicateVegFindings.length} group(s)</h4>
          <button
            type="button"
            class="rounded border border-vpro-navy bg-white px-2.5 py-1 text-xs font-semibold text-vpro-navy hover:bg-vpro-canvas"
            onclick={onOpenOptimizeVeg}
          >
            Open Safe OptimizeVeg Preview
          </button>
        </div>
        <div class="overflow-x-auto rounded border border-vpro-border">
          <table class="w-full text-left text-xs">
            <thead class="bg-vpro-canvas text-vpro-ink">
              <tr><th class="p-2">Plot</th><th class="p-2">Species</th><th class="p-2">Row Count</th><th class="p-2">Overlapping Layers</th></tr>
            </thead>
            <tbody>
              {#each complianceReport.duplicateVegFindings as dup}
                <tr class="border-t border-vpro-border">
                  <td class="p-2 font-mono">{dup.plotNumber}</td>
                  <td class="p-2 font-mono font-semibold">{dup.species}</td>
                  <td class="p-2 font-mono">{dup.rowCount}</td>
                  <td class="p-2 font-mono text-vpro-error">{dup.overlappingLayers?.join(', ') || 'None'}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      </div>
    {/if}

    {#if (complianceReport.taxonomyFindings?.length ?? 0) > 0}
      <div class="space-y-1">
        <h4 class="m-0 text-xs font-semibold text-vpro-navy">8. Taxonomy &amp; Synonym Compliance — {complianceReport.taxonomyFindings.length} finding(s)</h4>
        <div class="overflow-x-auto rounded border border-vpro-border">
          <table class="w-full text-left text-xs">
            <thead class="bg-vpro-canvas text-vpro-ink">
              <tr><th class="p-2">Plot</th><th class="p-2">Veg ID</th><th class="p-2">Species</th><th class="p-2">Status</th><th class="p-2">Suggested Code</th></tr>
            </thead>
            <tbody>
              {#each complianceReport.taxonomyFindings as tax}
                <tr class="border-t border-vpro-border">
                  <td class="p-2 font-mono">{tax.plotNumber}</td>
                  <td class="p-2 font-mono">{tax.id}</td>
                  <td class="p-2 font-mono font-semibold">{tax.species}</td>
                  <td class="p-2">{tax.status}</td>
                  <td class="p-2 font-mono font-semibold text-vpro-info">{tax.suggestedCode ?? '—'}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      </div>
    {/if}
  {/if}
</div>
