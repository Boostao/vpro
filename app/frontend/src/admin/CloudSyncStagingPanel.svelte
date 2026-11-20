<script lang="ts">
  import type {
    CloudRoleMode,
    StagingPreflightPreview,
    StagingSubmissionSummary,
    SubmitStagingResult,
  } from './cloudSyncWorkbench';

  interface Props {
    busy: boolean;
    operationHeld: boolean;
    activeProject: string;
    activeSu: string;
    activeRoleMode: CloudRoleMode;
    stagingUseActiveSu: boolean;
    stagingPreflight: StagingPreflightPreview | null;
    stagingSubmittedBy: string;
    stagingSubmitterNotes: string;
    stagingBaseSnapshotTag: string;
    stagingCustodianOverride: boolean;
    canUploadStaging: boolean;
    submitStagingResult: SubmitStagingResult | null;
    submissions: StagingSubmissionSummary[];
    onRunStagingPreflight: () => void;
    onRunSubmitToStaging: () => void;
    onRefreshSubmissionsList: () => void;
  }

  let {
    busy,
    operationHeld,
    activeProject,
    activeSu,
    activeRoleMode,
    stagingUseActiveSu = $bindable(),
    stagingPreflight,
    stagingSubmittedBy = $bindable(),
    stagingSubmitterNotes = $bindable(),
    stagingBaseSnapshotTag = $bindable(),
    stagingCustodianOverride = $bindable(),
    canUploadStaging,
    submitStagingResult,
    submissions,
    onRunStagingPreflight,
    onRunSubmitToStaging,
    onRefreshSubmissionsList,
  }: Props = $props();
</script>

<fieldset class="space-y-3 rounded border border-vpro-border border-t-[3px] border-t-vpro-gold bg-white p-4 shadow-sm">
  <legend class="px-1 text-sm font-semibold text-vpro-navy">Submit Active Project to BECMaster Staging</legend>
  <p class="text-xs text-vpro-ink-secondary">
    Packages <span class="font-mono font-semibold">{activeProject}</span> with automated compliance validation,
    <span class="font-mono">VUser.USysUserSpp</span>
    personal species manifest, and <span class="font-mono">_Lump</span> / <span class="font-mono">_SU</span> companions
    into <span class="font-mono">staging.submissions</span>.
  </p>

  <div
    class="flex flex-wrap items-center justify-between gap-2 rounded border border-vpro-border bg-vpro-surface-subtle p-2.5"
  >
    <label class="flex items-center gap-2 text-xs text-vpro-ink">
      <input
        type="checkbox"
        bind:checked={stagingUseActiveSu}
        disabled={busy || operationHeld || activeSu === 'None'}
      />
      Scope pre-flight &amp; staging bundle to active SU ({activeSu})
    </label>
    <button
      type="button"
      disabled={busy || operationHeld}
      class="rounded bg-vpro-navy px-3 py-1.5 text-xs font-semibold text-white hover:bg-vpro-navy-dark disabled:opacity-50"
      onclick={onRunStagingPreflight}
    >
      Run Pre-Flight Compliance &amp; Package Preview
    </button>
  </div>

  {#if stagingPreflight}
    <div
      class="space-y-2 rounded border border-vpro-border bg-vpro-surface-subtle p-3 text-xs"
      data-staging-preflight-summary
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <span class="font-semibold text-vpro-navy">
          Project: <span class="font-mono">{stagingPreflight.project}</span> ({stagingPreflight.plotCount} plots, {stagingPreflight.vegRowCount}
          veg rows)
        </span>
        {#if stagingPreflight.compliancePassed}
          <span
            class="rounded bg-vpro-success px-2 py-0.5 text-xs font-semibold text-white"
            data-preflight-badge="passed"
          >
            Compliance Passed (0 Blocking)
          </span>
        {:else}
          <span class="rounded bg-red-700 px-2 py-0.5 text-xs font-semibold text-white" data-preflight-badge="failed">
            Compliance Failed ({stagingPreflight.blockingErrorCount} Blocking)
          </span>
        {/if}
      </div>
      <div class="grid grid-cols-3 gap-2 text-[11px] text-vpro-ink-secondary">
        <div>
          Personal Species (<span class="font-mono">USysUserSpp</span>):
          <span class="font-bold">{stagingPreflight.userSpeciesManifest.rowCount}</span>
        </div>
        <div>Lump Rows: <span class="font-bold">{stagingPreflight.lumpRowCount}</span></div>
        <div>SU Rows: <span class="font-bold">{stagingPreflight.suRowCount}</span></div>
      </div>

      {#if stagingPreflight.userSpeciesManifest.species.length > 0}
        <div class="max-h-32 overflow-auto rounded border border-vpro-border bg-white">
          <table class="w-full text-left text-[11px]">
            <thead class="bg-vpro-canvas text-vpro-ink-secondary">
              <tr><th class="p-1.5">Code</th><th class="p-1.5">Scientific Name</th><th class="p-1.5">LifeForm</th></tr>
            </thead>
            <tbody>
              {#each stagingPreflight.userSpeciesManifest.species as sp (sp.code)}
                <tr class="border-t border-vpro-rail">
                  <td class="p-1.5 font-mono font-semibold">{sp.code}</td>
                  <td class="p-1.5">{sp.scientificName ?? '—'}</td>
                  <td class="p-1.5 font-mono">{sp.lifeForm ?? '—'}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {/if}

      {#if !stagingPreflight.compliancePassed && activeRoleMode === 'custodian'}
        <label
          class="flex items-center gap-2 rounded border border-amber-400 bg-amber-50 p-2 text-xs font-medium text-amber-950"
        >
          <input type="checkbox" bind:checked={stagingCustodianOverride} disabled={busy || operationHeld} />
          Custodian Admin Override: permit staging upload despite blocking compliance findings
        </label>
      {/if}
    </div>
  {/if}

  <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
    <div class="space-y-1">
      <label class="block text-xs font-semibold text-vpro-ink-secondary" for="staging-submitted-by"
        >Submitter Name / ID</label
      >
      <input
        id="staging-submitted-by"
        type="text"
        class="w-full rounded border border-vpro-border p-2 text-xs"
        bind:value={stagingSubmittedBy}
        disabled={busy || operationHeld}
        placeholder="e.g. Regional Ecologist"
      />
    </div>
    <div class="space-y-1">
      <label class="block text-xs font-semibold text-vpro-ink-secondary" for="staging-base-tag"
        >Base Snapshot Tag (optional)</label
      >
      <input
        id="staging-base-tag"
        type="text"
        class="w-full rounded border border-vpro-border p-2 font-mono text-xs"
        bind:value={stagingBaseSnapshotTag}
        disabled={busy || operationHeld}
        placeholder="e.g. v13_2026_05"
      />
    </div>
  </div>

  <div class="space-y-1">
    <label class="block text-xs font-semibold text-vpro-ink-secondary" for="staging-notes">Submitter Notes</label>
    <textarea
      id="staging-notes"
      rows="2"
      class="w-full rounded border border-vpro-border p-2 text-xs"
      bind:value={stagingSubmitterNotes}
      disabled={busy || operationHeld}
      placeholder="Field season summary, plot range, or provisional taxonomy notes"></textarea>
  </div>

  <div class="flex flex-wrap items-center gap-2">
    <button
      type="button"
      disabled={busy || operationHeld || !canUploadStaging}
      class="rounded border-2 border-vpro-gold bg-vpro-navy px-3 py-2 text-xs font-semibold text-white hover:bg-vpro-navy-dark disabled:opacity-50"
      onclick={onRunSubmitToStaging}
    >
      Upload Staging Bundle
    </button>
    <button
      type="button"
      disabled={busy || operationHeld}
      class="rounded border border-vpro-border bg-white px-3 py-2 text-xs font-semibold text-vpro-navy hover:bg-vpro-canvas disabled:opacity-50"
      onclick={onRefreshSubmissionsList}
    >
      Refresh Submissions
    </button>
  </div>

  {#if submitStagingResult}
    <p class="text-xs font-medium text-vpro-success">
      Submission <span class="font-mono font-semibold">{submitStagingResult.submissionId}</span> recorded ({submitStagingResult.status}
      at {submitStagingResult.submittedAt}).
    </p>
  {/if}

  {#if submissions.length > 0 && activeRoleMode !== 'custodian'}
    <div class="max-h-48 overflow-auto rounded border border-vpro-border">
      <table class="w-full text-left text-xs">
        <thead class="bg-vpro-canvas text-vpro-ink-secondary">
          <tr>
            <th class="p-2">Submission</th>
            <th class="p-2">Project</th>
            <th class="p-2">Plots</th>
            <th class="p-2">Status</th>
            <th class="p-2">Reviewer Notes</th>
          </tr>
        </thead>
        <tbody>
          {#each submissions as sub (sub.submissionId)}
            <tr class="border-t border-vpro-rail">
              <td class="p-2 font-mono">{sub.submissionId.slice(0, 12)}</td>
              <td class="p-2 font-mono">{sub.projectName}</td>
              <td class="p-2 font-mono">{sub.plotCount}</td>
              <td class="p-2 font-semibold">{sub.status}</td>
              <td class="p-2 text-vpro-ink-secondary">{sub.reviewerNotes ?? '—'}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {/if}
</fieldset>
