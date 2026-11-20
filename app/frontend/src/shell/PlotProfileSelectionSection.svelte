<script lang="ts">
  import type { PlotProfileSource, PlotProfileSourceInfo } from '../../bindings/github.com/boostao/vpro/app';
  import type { ReviewedProfileFile } from '../classification/profileFile';
  import type { ReviewedProfileTable } from '../classification/profileTable';
  import type { ValidatedProjectPlotProfileReview } from '../classification/projectPlotProfileReview';
  import { projectState } from '../shared/state';
  import PlotProfileBlankReviews from './PlotProfileBlankReviews.svelte';

  let {
    profilePath = $bindable(''),
    profileSources,
    profileSourceContext,
    profileSourceError,
    profileWriteReview,
    profileWriteContext,
    profileWriteError,
    profileFileReview,
    profileFileContext,
    profileFileName = $bindable(''),
    profileFilePath = $bindable(''),
    profileFileError,
    profileFileSuccess,
    profileFileCommitted,
    profileTableReview,
    profileTableContext,
    profileTableName = $bindable(''),
    profileTableError,
    profileTableSuccess,
    profileTableCommitted,
    busy,
    editorBusy,
    transitionWorking,
    pendingTransition,
    onInspectSources,
    onChooseProfile,
    onReviewWriteOwnership,
    onPublishWriteOwnership,
    onDismissWriteOwnership,
    onReviewBlankFile,
    onCreateBlankFile,
    onDismissBlankFile,
    onReviewBlankTable,
    onCreateBlankTable,
    onDismissBlankTable,
  }: {
    profilePath: string;
    profileSources: PlotProfileSourceInfo[];
    profileSourceContext: string;
    profileSourceError: string;
    profileWriteReview: ValidatedProjectPlotProfileReview | null;
    profileWriteContext: string;
    profileWriteError: string;
    profileFileReview: ReviewedProfileFile | null;
    profileFileContext: string;
    profileFileName: string;
    profileFilePath: string;
    profileFileError: string;
    profileFileSuccess: string;
    profileFileCommitted: boolean;
    profileTableReview: ReviewedProfileTable | null;
    profileTableContext: string;
    profileTableName: string;
    profileTableError: string;
    profileTableSuccess: string;
    profileTableCommitted: boolean;
    busy: boolean;
    editorBusy: boolean;
    transitionWorking: boolean;
    pendingTransition: unknown;
    onInspectSources: () => void;
    onChooseProfile: (source: PlotProfileSource, origin: string) => void;
    onReviewWriteOwnership: () => void;
    onPublishWriteOwnership: () => void;
    onDismissWriteOwnership: () => void;
    onReviewBlankFile: () => void;
    onCreateBlankFile: () => void;
    onDismissBlankFile: () => void;
    onReviewBlankTable: () => void;
    onCreateBlankTable: () => void;
    onDismissBlankTable: () => void;
  } = $props();

  const inputDisabled = $derived(busy || transitionWorking || pendingTransition !== null);
  const actionDisabled = $derived(inputDisabled || editorBusy);
</script>

{#if $projectState?.contextId}
  <details class="m-2 p-3 border rounded" aria-label="Stored plot profile selection">
    <summary class="font-semibold cursor-pointer">Plot profile: {$projectState.plotProfile.source.name}</summary>
    <p class="mt-2 text-sm">Select an optional VPro file (.db) containing saved plot profile tables.</p>
    <div class="mt-2 flex flex-wrap items-end gap-2">
      <label for="plot-profile-path" class="flex flex-col gap-1 flex-1 min-w-0">
        Profile database path (.db; blank inspects project and core)
        <input
          id="plot-profile-path"
          class="px-2 py-1 border rounded min-w-0"
          bind:value={profilePath}
          disabled={inputDisabled}
        />
      </label>
      <button
        type="button"
        class="px-3 py-1 border rounded disabled:opacity-50"
        disabled={actionDisabled}
        onclick={onInspectSources}
      >
        Inspect stored profiles
      </button>
      <button
        type="button"
        class="px-3 py-1 border rounded disabled:opacity-50"
        disabled={actionDisabled}
        onclick={() => onChooseProfile({ name: 'None', path: '' }, $projectState?.contextId ?? '')}
      >
        Select no profile
      </button>
    </div>
    {#if profileSourceError}<p role="alert" class="mt-2 text-vpro-error">{profileSourceError}</p>{/if}
    <ul class="mt-2 space-y-2">
      {#each profileSources as info}
        <li class="flex flex-wrap items-center gap-2">
          <span>{info.table} - {info.source.path} ({info.writable ? 'project-owned editing' : 'read-only'})</span>
          <button
            type="button"
            class="px-3 py-1 border rounded disabled:opacity-50"
            disabled={!info.available || profileSourceContext !== $projectState.contextId || actionDisabled}
            onclick={() => onChooseProfile(info.source, profileSourceContext)}
          >
            Select {info.table}
          </button>
          {#if !info.available}<span role="alert">{info.reason}</span>{/if}
        </li>
      {/each}
    </ul>
    {#if $projectState.plotProfile.available && ($projectState.plotProfile.source.name !== $projectState.activeProject || $projectState.plotProfile.source.path !== $projectState.projectPath)}
      <button
        type="button"
        class="mt-3 px-3 py-2 border rounded disabled:opacity-50"
        disabled={actionDisabled}
        onclick={onReviewWriteOwnership}
      >
        Review profile write ownership
      </button>
      {#if profileWriteReview}
        <section class="mt-3 p-3 border rounded" aria-label="Reviewed profile write ownership">
          <p>{profileWriteReview.table} in {profileWriteReview.source.source.path}</p>
          <p>
            {profileWriteReview.rules.rows.length} physical rules and {profileWriteReview.descriptions.rows.length} table
            descriptions reviewed.
          </p>
          {#if profileWriteReview.descriptions.columns.length === 0}<p>
              Description metadata is absent; no descriptions are inferred or created.
            </p>{/if}
          <p>
            Authorization applies only to this selected profile file/table for the current session. Context changes or
            restart clear it. Parent/child writes remain project-owned; support database writes are unavailable.
          </p>
          <button
            type="button"
            class="mt-2 px-3 py-2 border rounded disabled:opacity-50"
            disabled={actionDisabled || profileWriteContext !== $projectState.contextId}
            onclick={onPublishWriteOwnership}
          >
            {profileWriteReview.source.writable
              ? 'Stop selected profile editing'
              : 'Authorize selected profile editing'}
          </button>
          <button
            type="button"
            class="mt-2 ml-2 px-3 py-2 border rounded"
            disabled={inputDisabled}
            onclick={onDismissWriteOwnership}
          >
            Dismiss ownership review
          </button>
        </section>
      {/if}
      {#if profileWriteError}<p role="alert" class="mt-2 text-vpro-error">{profileWriteError}</p>{/if}
    {/if}
    <p class="mt-2 text-sm">
      Profile rules are independent of project/SU selection. External and other-table profiles are read-only unless
      explicitly authorized for this session.
    </p>
    <PlotProfileBlankReviews
      {profileFileReview}
      {profileFileContext}
      bind:profileFileName
      bind:profileFilePath
      {profileFileError}
      {profileFileSuccess}
      {profileFileCommitted}
      {profileTableReview}
      {profileTableContext}
      bind:profileTableName
      {profileTableError}
      {profileTableSuccess}
      {profileTableCommitted}
      profileWritable={Boolean($projectState.plotProfile.writable)}
      {busy}
      {editorBusy}
      {transitionWorking}
      {pendingTransition}
      {onReviewBlankFile}
      {onCreateBlankFile}
      {onDismissBlankFile}
      {onReviewBlankTable}
      {onCreateBlankTable}
      {onDismissBlankTable}
    />
  </details>
{/if}
