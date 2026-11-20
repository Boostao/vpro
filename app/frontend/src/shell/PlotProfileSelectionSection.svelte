<script lang="ts">
  import { untrack } from 'svelte';
  import { projectState } from '../shared/state';
  import PlotProfileBlankReviews from './PlotProfileBlankReviews.svelte';
  import type { PlotProfileSelectionController } from './plotProfileOps';

  let {
    selection,
    openByDefault = false,
  }: {
    selection: PlotProfileSelectionController;
    openByDefault?: boolean;
  } = $props();

  const inputDisabled = $derived(
    selection.busy || selection.transitionWorking || selection.pendingTransition !== null
  );
  const actionDisabled = $derived(inputDisabled || selection.editorBusy);
  const hasActiveDetails = $derived(
    selection.profileSources.length > 0 ||
      Boolean(
        selection.profileWriteReview ||
          selection.profileFileReview ||
          selection.profileTableReview ||
          selection.profileSourceError ||
          selection.profileWriteError ||
          selection.profileFileError ||
          selection.profileTableError ||
          selection.profileFileSuccess ||
          selection.profileTableSuccess
      )
  );
  let expanded = $state(untrack(() => openByDefault));
  $effect(() => {
    if (openByDefault || hasActiveDetails) {
      expanded = true;
    }
  });
</script>

{#if $projectState?.contextId}
  <details
    class="mt-3 p-3 border border-vpro-border rounded bg-white"
    aria-label="Stored plot profile selection"
    data-plot-profile-selection
    open={expanded}
    ontoggle={(event) => {
      expanded = event.currentTarget.open;
    }}
  >
    <summary class="font-semibold cursor-pointer">
      Plot profile: {$projectState.plotProfile.source.name}
      <span class="ml-1 text-xs font-normal text-vpro-ink-secondary">(Select, create, or authorize)</span>
    </summary>
    <p class="mt-2 text-sm">
      Choose a VPro file (.db) containing saved plot profile tables, or leave the path blank to inspect the current
      project and VPro workspace.
    </p>
    <div class="mt-2 flex flex-wrap items-end gap-2">
      <label for="plot-profile-path" class="flex flex-col gap-1 flex-1 min-w-0">
        Profile file path (.db; blank inspects project and workspace)
        <input
          id="plot-profile-path"
          class="px-2 py-1 border rounded min-w-0"
          value={selection.profilePath}
          oninput={(event) => selection.setProfilePath(event.currentTarget.value)}
          disabled={inputDisabled}
        />
      </label>
      <button
        type="button"
        class="px-3 py-1 border rounded disabled:opacity-50"
        disabled={actionDisabled}
        onclick={selection.inspectSources}
      >
        Inspect stored profiles
      </button>
      <button
        type="button"
        class="px-3 py-1 border rounded disabled:opacity-50"
        disabled={actionDisabled}
        onclick={() => selection.chooseProfile({ name: 'None', path: '' }, $projectState?.contextId ?? '')}
      >
        Select no profile
      </button>
    </div>
    {#if selection.profileSourceError}<p role="alert" class="mt-2 text-vpro-error">
        {selection.profileSourceError}
      </p>{/if}
    <ul class="mt-2 space-y-2">
      {#each selection.profileSources as info}
        <li class="flex flex-wrap items-center gap-2">
          <span>{info.table} - {info.source.path} ({info.writable ? 'project-owned editing' : 'read-only'})</span>
          <button
            type="button"
            class="px-3 py-1 border rounded disabled:opacity-50"
            disabled={!info.available || selection.profileSourceContext !== $projectState.contextId || actionDisabled}
            onclick={() => selection.chooseProfile(info.source, selection.profileSourceContext)}
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
        onclick={selection.reviewWriteOwnership}
      >
        Review profile write ownership
      </button>
      {#if selection.profileWriteReview}
        <section class="mt-3 p-3 border rounded" aria-label="Reviewed profile write ownership">
          <p>{selection.profileWriteReview.table} in {selection.profileWriteReview.source.source.path}</p>
          <p>
            {selection.profileWriteReview.rules.rows.length} saved rules and
            {selection.profileWriteReview.descriptions.rows.length} table descriptions reviewed.
          </p>
          {#if selection.profileWriteReview.descriptions.columns.length === 0}<p>
              Description metadata is absent; no descriptions are inferred or created.
            </p>{/if}
          <p>
            Authorization applies only to this selected profile file/table for the current session. Context changes or
            restart clear it. Plot data edits remain in the active project file; shared reference files stay read-only.
          </p>
          <button
            type="button"
            class="mt-2 px-3 py-2 border rounded disabled:opacity-50"
            disabled={actionDisabled || selection.profileWriteContext !== $projectState.contextId}
            onclick={selection.publishWriteOwnership}
          >
            {selection.profileWriteReview.source.writable
              ? 'Stop selected profile editing'
              : 'Authorize selected profile editing'}
          </button>
          <button
            type="button"
            class="mt-2 ml-2 px-3 py-2 border rounded"
            disabled={inputDisabled}
            onclick={selection.dismissWriteOwnership}
          >
            Dismiss ownership review
          </button>
        </section>
      {/if}
      {#if selection.profileWriteError}<p role="alert" class="mt-2 text-vpro-error">{selection.profileWriteError}</p>{/if}
    {/if}
    <p class="mt-2 text-sm">
      Plot profile rules are independent of your project and Site Unit selection. External and other-table profiles
      stay read-only unless you explicitly authorize editing for this session.
    </p>
    <PlotProfileBlankReviews
      profileFileReview={selection.profileFileReview}
      profileFileContext={selection.profileFileContext}
      bind:profileFileName={() => selection.profileFileName, (value) => selection.setProfileFileName(value)}
      bind:profileFilePath={() => selection.profileFilePath, (value) => selection.setProfileFilePath(value)}
      profileFileError={selection.profileFileError}
      profileFileSuccess={selection.profileFileSuccess}
      profileFileCommitted={selection.profileFileCommitted}
      profileTableReview={selection.profileTableReview}
      profileTableContext={selection.profileTableContext}
      bind:profileTableName={() => selection.profileTableName, (value) => selection.setProfileTableName(value)}
      profileTableError={selection.profileTableError}
      profileTableSuccess={selection.profileTableSuccess}
      profileTableCommitted={selection.profileTableCommitted}
      profileWritable={Boolean($projectState.plotProfile.writable)}
      busy={selection.busy}
      editorBusy={selection.editorBusy}
      transitionWorking={selection.transitionWorking}
      pendingTransition={selection.pendingTransition}
      onReviewBlankFile={selection.reviewBlankFile}
      onCreateBlankFile={selection.createBlankFile}
      onDismissBlankFile={selection.dismissBlankFile}
      onReviewBlankTable={selection.reviewBlankTable}
      onCreateBlankTable={selection.createBlankTable}
      onDismissBlankTable={selection.dismissBlankTable}
    />
  </details>
{/if}
