<script lang="ts">
  import type { AccessProjectImportResult } from '../../bindings/github.com/boostao/vpro/app';

  let {
    accessWorking,
    accessOperation,
    accessElapsedSeconds,
    accessProgressPercent,
    accessProgressMessage,
    accessProgressRows,
    accessProgressExpectedRows,
    accessStatusNotice,
    accessError,
    accessResult,
    onCancel,
  }: {
    accessWorking: boolean;
    accessOperation: 'inspect' | 'import' | '';
    accessElapsedSeconds: number;
    accessProgressPercent: number | null;
    accessProgressMessage: string;
    accessProgressRows: number;
    accessProgressExpectedRows: number;
    accessStatusNotice: string;
    accessError: string;
    accessResult: AccessProjectImportResult | null;
    onCancel: () => void;
  } = $props();
</script>

{#if accessWorking}
  <div
    class="grid gap-1.5 rounded border border-vpro-navy/25 bg-vpro-navy-tint p-2 text-xs text-vpro-ink"
    data-access-import-progress
    aria-live="polite"
  >
    <div class="flex items-center justify-between gap-2">
      <strong class="truncate text-vpro-navy">
        {accessOperation === 'inspect' ? 'Inspecting Access file…' : 'Importing Access project…'}
      </strong>
      <span class="shrink-0 tabular-nums text-[11px] text-vpro-ink-secondary" data-access-elapsed>
        {accessElapsedSeconds}s
      </span>
    </div>
    <progress
      class="h-2 w-full"
      max={100}
      value={accessProgressPercent ?? undefined}
      aria-label={accessOperation === 'inspect' ? 'Access file inspection progress' : 'Access project import progress'}
    ></progress>
    <p class="m-0 break-words text-[11px] text-vpro-ink-secondary" data-access-progress-detail>
      {accessProgressMessage ||
        (accessOperation === 'inspect'
          ? 'Scanning tables…'
          : 'Preparing destination project file…')}{#if accessProgressRows > 0}
        ({accessProgressRows.toLocaleString()}{accessProgressExpectedRows > 0
          ? ` / ${accessProgressExpectedRows.toLocaleString()}`
          : ''} rows{accessProgressPercent !== null ? ` · ${accessProgressPercent}%` : ''})
      {/if}
    </p>
    <button
      type="button"
      id="cancel-access-import-btn"
      class="rounded border border-vpro-error bg-white px-2 py-1 text-xs font-semibold text-vpro-error"
      onclick={onCancel}
    >
      {accessOperation === 'inspect' ? 'Cancel inspection' : 'Cancel import'}
    </button>
  </div>
{/if}
{#if accessStatusNotice && !accessWorking}
  <p role="status" class="m-0 text-xs text-vpro-ink-secondary break-words">{accessStatusNotice}</p>
{/if}
{#if accessError}<p role="alert" class="text-vpro-error break-words">{accessError}</p>{/if}
{#if accessResult}
  {@const overflowQuarantined = (accessResult as { quarantinedOverflowRows?: number }).quarantinedOverflowRows ?? 0}
  <div role="status" class="grid gap-1 text-xs text-vpro-forest break-words">
    <p class="m-0">
      Imported {accessResult.targetProject} ({accessResult.plotCount} plots, {accessResult.conversionMode}) into {accessResult.destinationPath}.
    </p>
    {#if (accessResult.quarantinedMalformedRows ?? 0) > 0 || (accessResult.quarantinedOrphanRows ?? 0) > 0 || overflowQuarantined > 0}
      <p
        role="alert"
        data-access-quarantine-summary
        class="m-0 rounded border border-vpro-gold bg-vpro-warning-bg px-2 py-1 text-[11px] font-medium text-vpro-ink"
      >
        Access import quarantined rows for review: {accessResult.quarantinedMalformedRows ?? 0} malformed,
        {accessResult.quarantinedOrphanRows ?? 0} orphan{overflowQuarantined > 0
          ? `, ${overflowQuarantined} overflow`
          : ''}.
      </p>
    {/if}
  </div>
{/if}
