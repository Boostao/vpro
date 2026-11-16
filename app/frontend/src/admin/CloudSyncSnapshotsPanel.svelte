<script lang="ts">
  import type { DownloadLogEntry, SnapshotRecord } from './cloudSyncWorkbench';

  interface Props {
    busy: boolean;
    operationHeld: boolean;
    snapshotTag: string;
    snapshotExportFormat: string;
    snapshotTagValidationError: string | null;
    latestSnapshotCreated: SnapshotRecord | null;
    snapshots: SnapshotRecord[];
    downloadLog: DownloadLogEntry[];
    onCreateSnapshot: (extras?: { destinationPath?: string; zoneFilter?: string; notes?: string }) => void;
    onRefreshSnapshots: () => void;
  }

  let {
    busy,
    operationHeld,
    snapshotTag = $bindable(),
    snapshotExportFormat = $bindable(),
    snapshotTagValidationError,
    latestSnapshotCreated,
    snapshots,
    downloadLog,
    onCreateSnapshot,
    onRefreshSnapshots,
  }: Props = $props();

  let snapshotDestinationPath = $state('');
  let snapshotZoneFilter = $state('');
  let snapshotNotes = $state('');
</script>

<div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
  <fieldset class="space-y-2.5 rounded border border-slate-300 border-t-[3px] border-t-[#FCBA19] p-4">
    <legend class="px-1 text-sm font-semibold text-[#003366]">Cut Dated BECMaster Snapshot</legend>
    <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
      <div class="space-y-1">
        <label class="block text-xs font-semibold text-slate-700" for="snapshot-tag-input">Snapshot Tag</label>
        <input
          id="snapshot-tag-input"
          type="text"
          class="w-full rounded border border-slate-300 p-2 font-mono text-xs"
          bind:value={snapshotTag}
          disabled={busy || operationHeld}
          aria-invalid={!!snapshotTagValidationError}
          placeholder="e.g. BECMaster_2026_11"
        />
      </div>
      <div class="space-y-1">
        <label class="block text-xs font-semibold text-slate-700" for="snapshot-export-format">Optional Archive Export</label>
        <select id="snapshot-export-format" class="w-full rounded border border-slate-300 p-2 text-xs" bind:value={snapshotExportFormat} disabled={busy || operationHeld}>
          <option value="">Cloud Snapshot Only</option>
          <option value="sqlite">VPro Project (.db)</option>
          <option value="rds">R Serialized Dataset (.rds)</option>
          <option value="gpkg">OGC GeoPackage (.gpkg)</option>
        </select>
      </div>
    </div>
    {#if snapshotTagValidationError}
      <p role="alert" class="text-xs text-red-700">{snapshotTagValidationError}</p>
    {/if}
    <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
      <div class="space-y-1">
        <label class="block text-xs font-semibold text-slate-700" for="snapshot-dest-path">Export Destination Path (opt)</label>
        <input id="snapshot-dest-path" type="text" class="w-full rounded border border-slate-300 p-2 font-mono text-xs" bind:value={snapshotDestinationPath} disabled={busy || operationHeld} />
      </div>
      <div class="space-y-1">
        <label class="block text-xs font-semibold text-slate-700" for="snapshot-zone-filter">Zone Filter (opt)</label>
        <input id="snapshot-zone-filter" type="text" class="w-full rounded border border-slate-300 p-2 font-mono text-xs" bind:value={snapshotZoneFilter} disabled={busy || operationHeld} placeholder="All zones" />
      </div>
    </div>
    <div class="space-y-1">
      <label class="block text-xs font-semibold text-slate-700" for="snapshot-notes-input">Release Notes</label>
      <input id="snapshot-notes-input" type="text" class="w-full rounded border border-slate-300 p-2 text-xs" bind:value={snapshotNotes} disabled={busy || operationHeld} />
    </div>
    <div class="flex flex-wrap gap-2">
      <button
        type="button"
        disabled={busy || operationHeld || !snapshotTag || !!snapshotTagValidationError}
        class="rounded bg-[#003366] px-3 py-1.5 text-xs font-semibold text-white hover:bg-[#002244] disabled:opacity-50"
        onclick={() =>
          onCreateSnapshot({
            destinationPath: snapshotDestinationPath,
            zoneFilter: snapshotZoneFilter,
            notes: snapshotNotes,
          })}
      >
        Cut Dated Snapshot
      </button>
      <button
        type="button"
        disabled={busy || operationHeld}
        class="rounded border border-slate-300 bg-white px-3 py-1.5 text-xs font-semibold text-[#003366] hover:bg-slate-100 disabled:opacity-50"
        onclick={onRefreshSnapshots}
      >
        Refresh Snapshots &amp; Download Log
      </button>
    </div>
    {#if latestSnapshotCreated}
      <p class="text-xs text-slate-700">
        Snapshot <span class="font-mono font-semibold">{latestSnapshotCreated.snapshotTag}</span> manifest SHA-256: <span class="font-mono">{latestSnapshotCreated.manifestSha256.slice(0, 16)}</span>
      </p>
    {/if}
  </fieldset>

  <fieldset class="space-y-2.5 rounded border border-slate-300 border-t-[3px] border-t-[#FCBA19] p-4">
    <legend class="px-1 text-sm font-semibold text-[#003366]">Snapshots &amp; Download Activity Ledger</legend>
    {#if snapshots.length > 0}
      <div class="max-h-36 overflow-auto rounded border border-slate-200">
        <table class="w-full text-left text-[11px]">
          <thead class="bg-slate-100 text-slate-700">
            <tr><th class="p-1.5">Tag</th><th class="p-1.5">Plots</th><th class="p-1.5">Standards</th><th class="p-1.5">Created</th></tr>
          </thead>
          <tbody>
            {#each snapshots as snap (snap.snapshotTag)}
              <tr class="border-t border-slate-100">
                <td class="p-1.5 font-mono font-semibold">{snap.snapshotTag}</td>
                <td class="p-1.5 font-mono">{snap.plotCount.toLocaleString()}</td>
                <td class="p-1.5 font-mono">BEC v{snap.becVersion} / Taxa v{snap.taxonomyVersion}</td>
                <td class="p-1.5">{snap.createdAt}</td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}

    {#if downloadLog.length > 0}
      <div class="max-h-36 overflow-auto rounded border border-slate-200">
        <table class="w-full text-left text-[11px]">
          <thead class="bg-slate-100 text-slate-700">
            <tr><th class="p-1.5">#</th><th class="p-1.5">Actor</th><th class="p-1.5">Role</th><th class="p-1.5">Format</th><th class="p-1.5">Plots</th><th class="p-1.5">Timestamp</th></tr>
          </thead>
          <tbody>
            {#each downloadLog as entry (entry.id)}
              <tr class="border-t border-slate-100">
                <td class="p-1.5 font-mono">{entry.id}</td>
                <td class="p-1.5">{entry.actor}</td>
                <td class="p-1.5 font-mono">{entry.roleTier}</td>
                <td class="p-1.5 font-mono">{entry.format}</td>
                <td class="p-1.5 font-mono">{entry.plotCount}</td>
                <td class="p-1.5">{entry.downloadedAt}</td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {:else if snapshots.length === 0}
      <p class="text-xs text-slate-600">Click Refresh Snapshots &amp; Download Log to inspect historical provincial releases and subset checkouts.</p>
    {/if}
  </fieldset>
</div>
