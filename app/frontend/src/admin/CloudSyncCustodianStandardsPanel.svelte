<script lang="ts">
  import {
    formatAuditChainBannerSummary,
    type AuditChainVerification,
    type PublishStandardsResult,
    type SchemaBootstrapResult,
    type SeedBaselineResult,
  } from './cloudSyncWorkbench';

  export interface PublishStandardsDraft {
    releaseId?: string;
    becVersion?: string;
    taxonomyVersion?: string;
    vlistsPath?: string;
    becDbPath?: string;
    vmetaDataPath?: string;
    notes?: string;
  }

  export interface SeedBaselineExtras {
    sourceProject?: string;
    snapshotTag?: string;
    replaceExisting?: boolean;
    skipAudit?: boolean;
    notes?: string;
  }

  interface Props {
    busy: boolean;
    operationHeld: boolean;
    auditChainResult: AuditChainVerification | null;
    bootstrapResult: SchemaBootstrapResult | null;
    publishStandardsResult: PublishStandardsResult | null;
    seedSourceDbPath: string;
    seedBaselineResult: SeedBaselineResult | null;
    onPublishStandards: (draft?: PublishStandardsDraft) => void;
    onSeedBaseline: (extras?: SeedBaselineExtras) => void;
  }

  let {
    busy,
    operationHeld,
    auditChainResult,
    bootstrapResult,
    publishStandardsResult,
    seedSourceDbPath = $bindable(),
    seedBaselineResult,
    onPublishStandards,
    onSeedBaseline,
  }: Props = $props();

  let pubReleaseId = $state('');
  let pubBecVersion = $state('13');
  let pubTaxonomyVersion = $state('19');
  let pubVlistsPath = $state('');
  let pubBecDbPath = $state('');
  let pubVmetaDataPath = $state('');
  let pubNotes = $state('');

  let seedSourceProject = $state('');
  let seedSnapshotTag = $state('');
  let seedReplaceExisting = $state(false);
  let seedSkipAudit = $state(false);
  let seedNotes = $state('');
</script>

{#if auditChainResult}
  <div
    role="status"
    data-audit-chain-banner
    class={`rounded border-l-4 p-2.5 text-xs ${auditChainResult.valid ? 'border-vpro-success bg-vpro-success-bg text-vpro-ink' : 'border-vpro-error bg-vpro-error-bg text-vpro-error'}`}
  >
    <strong>Audit Hash Chain {auditChainResult.valid ? 'VALID' : 'INVALID'}</strong>:
    <span class="font-mono font-semibold">{formatAuditChainBannerSummary(auditChainResult)}</span>
    &middot; Tail hash: <span class="font-mono">{auditChainResult.tailHash || 'none'}</span>
  </div>
{/if}

{#if bootstrapResult}
  <div class="rounded border border-vpro-border bg-vpro-surface-subtle p-2.5 text-xs">
    Schema v<span class="font-mono font-bold">{bootstrapResult.schemaVersion}</span> verified ({bootstrapResult.schemasVerified.join(', ')}) &middot; Role Grants: {bootstrapResult.roleGrantsApplied ? 'Applied' : 'Skipped'}
  </div>
{/if}

<div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
  <fieldset class="space-y-2.5 rounded border border-vpro-border border-t-[3px] border-t-vpro-gold p-3">
    <legend class="px-1 text-xs font-semibold text-vpro-navy">Publish 2026 Standards to Cloud</legend>
    <div class="grid grid-cols-3 gap-2">
      <div class="space-y-1">
        <label class="block text-[11px] font-semibold text-vpro-ink-secondary" for="pub-release-id">Release ID</label>
        <input id="pub-release-id" type="text" class="w-full rounded border border-vpro-border p-1.5 font-mono text-xs" bind:value={pubReleaseId} disabled={busy || operationHeld} placeholder="BECv13_Taxa19_2026" />
      </div>
      <div class="space-y-1">
        <label class="block text-[11px] font-semibold text-vpro-ink-secondary" for="pub-bec-ver">BEC Version</label>
        <input id="pub-bec-ver" type="text" class="w-full rounded border border-vpro-border p-1.5 font-mono text-xs" bind:value={pubBecVersion} disabled={busy || operationHeld} />
      </div>
      <div class="space-y-1">
        <label class="block text-[11px] font-semibold text-vpro-ink-secondary" for="pub-taxa-ver">Taxonomy Version</label>
        <input id="pub-taxa-ver" type="text" class="w-full rounded border border-vpro-border p-1.5 font-mono text-xs" bind:value={pubTaxonomyVersion} disabled={busy || operationHeld} />
      </div>
    </div>
    <div class="grid grid-cols-1 gap-2 sm:grid-cols-3">
      <div class="space-y-1">
        <label class="block text-[11px] font-semibold text-vpro-ink-secondary" for="pub-vlists-path">VLists.db Path (opt)</label>
        <input id="pub-vlists-path" type="text" class="w-full rounded border border-vpro-border p-1.5 font-mono text-xs" bind:value={pubVlistsPath} disabled={busy || operationHeld} />
      </div>
      <div class="space-y-1">
        <label class="block text-[11px] font-semibold text-vpro-ink-secondary" for="pub-becdb-path">BECdb Path (opt)</label>
        <input id="pub-becdb-path" type="text" class="w-full rounded border border-vpro-border p-1.5 font-mono text-xs" bind:value={pubBecDbPath} disabled={busy || operationHeld} />
      </div>
      <div class="space-y-1">
        <label class="block text-[11px] font-semibold text-vpro-ink-secondary" for="pub-vmeta-path">VMetaData.db Path (opt)</label>
        <input id="pub-vmeta-path" type="text" class="w-full rounded border border-vpro-border p-1.5 font-mono text-xs" bind:value={pubVmetaDataPath} disabled={busy || operationHeld} />
      </div>
    </div>
    <div class="flex items-center justify-between gap-2">
      <input
        aria-label="Standards release notes"
        type="text"
        class="flex-1 rounded border border-vpro-border p-1.5 text-xs"
        bind:value={pubNotes}
        disabled={busy || operationHeld}
        placeholder="Release notes (optional)"
      />
      <button
        type="button"
        disabled={busy || operationHeld}
        class="rounded bg-vpro-navy px-3 py-1.5 text-xs font-semibold text-white hover:bg-vpro-navy-dark disabled:opacity-50"
        onclick={() =>
          onPublishStandards({
            releaseId: pubReleaseId,
            becVersion: pubBecVersion,
            taxonomyVersion: pubTaxonomyVersion,
            vlistsPath: pubVlistsPath,
            becDbPath: pubBecDbPath,
            vmetaDataPath: pubVmetaDataPath,
            notes: pubNotes,
          })}
      >
        Publish 2026 Standards to Cloud
      </button>
    </div>
    {#if publishStandardsResult}
      <p class="text-[11px] text-vpro-ink-secondary">
        Published <span class="font-mono">{publishStandardsResult.releaseId}</span> (VLists SHA <span class="font-mono">{publishStandardsResult.vlistsSha256.slice(0, 12)}</span>).
      </p>
    {/if}
  </fieldset>

  <details class="rounded border border-vpro-border border-t-[3px] border-t-vpro-gold p-3 text-xs">
    <summary class="cursor-pointer font-semibold text-vpro-navy select-none">
      Seed Baseline VPro Project (.db) into BECMaster
    </summary>
    <div class="mt-3 space-y-2">
      <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <div class="space-y-1">
          <label class="block text-[11px] font-semibold text-vpro-ink-secondary" for="seed-db-path">Source VPro Project (.db) Path (required)</label>
          <input id="seed-db-path" type="text" class="w-full rounded border border-vpro-border p-1.5 font-mono text-xs" bind:value={seedSourceDbPath} disabled={busy || operationHeld} />
        </div>
        <div class="space-y-1">
          <label class="block text-[11px] font-semibold text-vpro-ink-secondary" for="seed-source-proj">Source Project Prefix (opt)</label>
          <input id="seed-source-proj" type="text" class="w-full rounded border border-vpro-border p-1.5 font-mono text-xs" bind:value={seedSourceProject} disabled={busy || operationHeld} />
        </div>
      </div>
      <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <div class="space-y-1">
          <label class="block text-[11px] font-semibold text-vpro-ink-secondary" for="seed-snap-tag">Initial Snapshot Tag (opt)</label>
          <input id="seed-snap-tag" type="text" class="w-full rounded border border-vpro-border p-1.5 font-mono text-xs" bind:value={seedSnapshotTag} disabled={busy || operationHeld} placeholder="baseline_2026" />
        </div>
        <div class="space-y-1">
          <label class="block text-[11px] font-semibold text-vpro-ink-secondary" for="seed-notes">Notes (opt)</label>
          <input id="seed-notes" type="text" class="w-full rounded border border-vpro-border p-1.5 text-xs" bind:value={seedNotes} disabled={busy || operationHeld} />
        </div>
      </div>
      <div class="flex flex-wrap items-center gap-4">
        <label class="flex items-center gap-1.5 text-xs text-vpro-ink">
          <input type="checkbox" bind:checked={seedReplaceExisting} disabled={busy || operationHeld} />
          Replace existing becmaster tables
        </label>
        <label class="flex items-center gap-1.5 text-xs text-vpro-ink">
          <input type="checkbox" bind:checked={seedSkipAudit} disabled={busy || operationHeld} />
          Skip historical audit rows
        </label>
      </div>
      <button
        type="button"
        disabled={busy || operationHeld || !seedSourceDbPath.trim()}
        class="rounded bg-vpro-navy px-3 py-1.5 text-xs font-semibold text-white hover:bg-vpro-navy-dark disabled:opacity-50"
        onclick={() =>
          onSeedBaseline({
            sourceProject: seedSourceProject,
            snapshotTag: seedSnapshotTag,
            replaceExisting: seedReplaceExisting,
            skipAudit: seedSkipAudit,
            notes: seedNotes,
          })}
      >
        Seed Baseline VPro Project (.db)
      </button>
      {#if seedBaselineResult}
        <p class="text-[11px] text-vpro-ink-secondary">
          Seeded {seedBaselineResult.plotCount.toLocaleString()} plots / {seedBaselineResult.vegCount.toLocaleString()} veg rows (snapshot <span class="font-mono">{seedBaselineResult.snapshotTag}</span>).
        </p>
      {/if}
    </div>
  </details>
</div>
