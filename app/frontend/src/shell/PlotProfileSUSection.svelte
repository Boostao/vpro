<script lang="ts">
  import type { ReviewedProfileSU } from '../classification/profileSU';
  import type { ReviewedProjectSU } from '../classification/profileSUProject';
  import { projectState } from '../shared/state';

  let {
    suReview,
    suReviewContext,
    suName = $bindable(''),
    suPath = $bindable(''),
    suError,
    suSuccess,
    suCommitted,
    suProjectReview,
    suProjectContext,
    suProjectName = $bindable(''),
    suProjectError,
    suProjectSuccess,
    suProjectCommitted,
    busy,
    editorBusy,
    transitionWorking,
    pendingTransition,
    onSaveSU,
    onDismissSU,
    onReviewSUProject,
    onSaveSUProject,
    onDismissSUProject,
  }: {
    suReview: ReviewedProfileSU;
    suReviewContext: string;
    suName: string;
    suPath: string;
    suError: string;
    suSuccess: string;
    suCommitted: boolean;
    suProjectReview: ReviewedProjectSU | null;
    suProjectContext: string;
    suProjectName: string;
    suProjectError: string;
    suProjectSuccess: string;
    suProjectCommitted: boolean;
    busy: boolean;
    editorBusy: boolean;
    transitionWorking: boolean;
    pendingTransition: unknown;
    onSaveSU: () => void;
    onDismissSU: () => void;
    onReviewSUProject: () => void;
    onSaveSUProject: () => void;
    onDismissSUProject: () => void;
  } = $props();

  const inputDisabled = $derived(busy || transitionWorking || pendingTransition !== null);
  const actionDisabled = $derived(inputDisabled || editorBusy);
</script>

<section class="m-2 p-3 border rounded" aria-label="Reviewed Save as SU">
  <h2 class="font-semibold">Save reviewed profile as a new SU file</h2>
  <p class="mt-2">
    {suReview.plots.length} stored plots; SiteUnit values
    {suReview.sourceSU
      ? 'copied from the independently reviewed selected SU'
      : 'remain NULL because no SU is selected'}.
  </p>
  <div class="mt-3 grid grid-cols-1 sm:grid-cols-2 gap-3">
    <label for="profile-su-name" class="flex flex-col gap-1"
      >New SU name
      <input
        id="profile-su-name"
        class="px-2 py-1 border rounded min-w-0"
        bind:value={suName}
        disabled={inputDisabled || suCommitted}
      />
    </label>
    <label for="profile-su-path" class="flex flex-col gap-1"
      >New VPro SU file (absolute .db path)
      <input
        id="profile-su-path"
        class="px-2 py-1 border rounded min-w-0"
        bind:value={suPath}
        disabled={inputDisabled || suCommitted}
      />
    </label>
  </div>
  {#if suError}<p role="alert" class="mt-2 text-vpro-error">{suError}</p>{/if}
  {#if suSuccess}<p role="status" class="mt-2 text-vpro-forest">{suSuccess}</p>{/if}
  <div class="mt-3 overflow-x-auto">
    <table class="w-full text-sm">
      <thead><tr><th class="text-left">Plot number</th><th class="text-left">SiteUnit</th></tr></thead>
      <tbody>
        {#each suReview.plots.slice(0, 25) as plot}
          <tr>
            <td>{plot.plotNumber}</td>
            <td>{plot.siteUnit === null ? 'NULL (no value)' : plot.siteUnit === '' ? 'Empty text' : plot.siteUnit}</td>
          </tr>
        {/each}
      </tbody>
    </table>
    {#if suReview.plots.length > 25}<p>
        Showing the first 25 of {suReview.plots.length} explicitly reviewed rows.
      </p>{/if}
  </div>
  <div class="mt-3 flex flex-wrap gap-2">
    <button
      type="button"
      class="px-3 py-2 border rounded disabled:opacity-50"
      disabled={actionDisabled || suCommitted || !suName || !suPath || suReviewContext !== $projectState?.contextId}
      onclick={onSaveSU}
    >
      Create reviewed SU file
    </button>
    <button
      type="button"
      class="px-3 py-2 border rounded disabled:opacity-50"
      disabled={inputDisabled}
      onclick={onDismissSU}
    >
      Dismiss SU review
    </button>
  </div>
  <p class="mt-3 text-sm">
    Creates a new VPro SU file (.db) without overwriting existing files or switching the active project/SU context.
    Table names follow the 31-character VPro identifier rule (None, Sample, and master names are reserved).
  </p>
  <button
    type="button"
    class="mt-3 px-3 py-2 border rounded disabled:opacity-50"
    disabled={actionDisabled || suReviewContext !== $projectState?.contextId}
    onclick={onReviewSUProject}
  >
    Review Save as SU in current project file
  </button>
  {#if suProjectReview}
    <section class="mt-3 p-3 border rounded" aria-label="Reviewed project-file SU creation">
      <h3 class="font-semibold">Add one SU table to the current owned project</h3>
      <p class="break-words">Destination: {suProjectReview.path}</p>
      <p>
        {suProjectReview.su.plots.length} stored plots and {suProjectReview.metadata.rows.length} original table descriptions
        reviewed. No descriptions are synthesized or removed.
      </p>
      <label for="profile-su-project-name" class="mt-3 flex flex-col gap-1"
        >New project-file SU name
        <input
          id="profile-su-project-name"
          class="px-2 py-1 border rounded min-w-0"
          bind:value={suProjectName}
          disabled={inputDisabled || suProjectCommitted}
        />
      </label>
      {#if suProjectSuccess}<p role="status" class="mt-2 text-vpro-forest break-words">{suProjectSuccess}</p>{/if}
      <div class="mt-3 flex flex-wrap gap-2">
        <button
          type="button"
          class="px-3 py-2 border rounded disabled:opacity-50"
          disabled={actionDisabled ||
            suProjectCommitted ||
            !suProjectName ||
            suProjectContext !== $projectState?.contextId}
          onclick={onSaveSUProject}
        >
          Create reviewed SU in project file
        </button>
        <button type="button" class="px-3 py-2 border rounded" disabled={inputDisabled} onclick={onDismissSUProject}>
          Dismiss project-file SU review
        </button>
      </div>
      <p class="mt-3 text-sm">
        Adds only the reviewed SU, its original indexes and transactional creation provenance. No implicit
        selection/attachment, Master authorization or settings write.
      </p>
    </section>
  {/if}
  {#if suProjectError}<p role="alert" class="mt-2 text-vpro-error">{suProjectError}</p>{/if}
</section>
