<script lang="ts">
  import type { ReviewedProfileFile } from '../classification/profileFile';
  import type { ReviewedProfileTable } from '../classification/profileTable';
  import { projectState } from '../shared/state';

  let {
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
    profileWritable,
    busy,
    editorBusy,
    transitionWorking,
    pendingTransition,
    onReviewBlankFile,
    onCreateBlankFile,
    onDismissBlankFile,
    onReviewBlankTable,
    onCreateBlankTable,
    onDismissBlankTable,
  }: {
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
    profileWritable: boolean;
    busy: boolean;
    editorBusy: boolean;
    transitionWorking: boolean;
    pendingTransition: unknown;
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

<button
  type="button"
  class="mt-3 px-3 py-2 border rounded disabled:opacity-50"
  disabled={actionDisabled}
  onclick={onReviewBlankFile}
>
  Review new blank profile file
</button>
{#if profileFileReview}
  <section class="mt-3 p-3 border rounded" aria-label="Reviewed blank profile file creation">
    <h2 class="font-semibold">Create one new empty profile file</h2>
    <p>
      Original nine nullable fields, zero rules, no template indexes/triggers and absent description metadata. No
      descriptions or legacy population values are invented.
    </p>
    <div class="mt-3 grid grid-cols-1 sm:grid-cols-2 gap-3">
      <label for="profile-file-name" class="flex flex-col gap-1"
        >New profile name
        <input
          id="profile-file-name"
          class="px-2 py-1 border rounded min-w-0"
          bind:value={profileFileName}
          disabled={inputDisabled || profileFileCommitted}
        />
      </label>
      <label for="profile-file-path" class="flex flex-col gap-1"
        >New VPro file (absolute .db path)
        <input
          id="profile-file-path"
          class="px-2 py-1 border rounded min-w-0"
          bind:value={profileFilePath}
          disabled={inputDisabled || profileFileCommitted}
        />
      </label>
    </div>
    {#if profileFileSuccess}<p role="status" class="mt-2 text-vpro-forest break-words">{profileFileSuccess}</p>{/if}
    <div class="mt-3 flex flex-wrap gap-2">
      <button
        type="button"
        class="px-3 py-2 border rounded disabled:opacity-50"
        disabled={actionDisabled ||
          profileFileCommitted ||
          !profileFileName ||
          !profileFilePath ||
          profileFileContext !== $projectState?.contextId}
        onclick={onCreateBlankFile}
      >
        Create reviewed blank profile file
      </button>
      <button type="button" class="px-3 py-2 border rounded" disabled={inputDisabled} onclick={onDismissBlankFile}>
        Dismiss blank profile review
      </button>
    </div>
    <p class="mt-3 text-sm">
      Creates a new VPro profile file (.db) without overwriting existing files or altering active session selections.
      Profile names follow the 31-character ASCII VPro identifier rule (None, Sample, and master names are reserved).
    </p>
  </section>
{/if}
{#if profileFileError}<p role="alert" class="mt-2 text-vpro-error">{profileFileError}</p>{/if}

{#if profileWritable}
  <button
    type="button"
    class="mt-3 px-3 py-2 border rounded disabled:opacity-50"
    disabled={actionDisabled}
    onclick={onReviewBlankTable}
  >
    Review blank profile in selected file
  </button>
  {#if profileTableReview}
    <section class="mt-3 p-3 border rounded" aria-label="Reviewed existing-file profile creation">
      <h2 class="font-semibold">Create one empty profile in the owned selected file</h2>
      <p class="break-words">Destination: {profileTableReview.profile.source.source.path}</p>
      <p>
        Current ownership, selected rules/descriptions and the original empty nine-field template are reviewed
        independently.
      </p>
      <label for="profile-table-name" class="mt-3 flex flex-col gap-1"
        >New profile table name
        <input
          id="profile-table-name"
          class="px-2 py-1 border rounded min-w-0"
          bind:value={profileTableName}
          disabled={inputDisabled || profileTableCommitted}
        />
      </label>
      {#if profileTableSuccess}<p role="status" class="mt-2 text-vpro-forest break-words">{profileTableSuccess}</p>{/if}
      <div class="mt-3 flex flex-wrap gap-2">
        <button
          type="button"
          class="px-3 py-2 border rounded disabled:opacity-50"
          disabled={actionDisabled ||
            profileTableCommitted ||
            !profileTableName ||
            profileTableContext !== $projectState?.contextId}
          onclick={onCreateBlankTable}
        >
          Create reviewed profile in selected file
        </button>
        <button type="button" class="px-3 py-2 border rounded" disabled={inputDisabled} onclick={onDismissBlankTable}>
          Dismiss existing-file profile review
        </button>
      </div>
      <p class="mt-3 text-sm">
        Adds one table and transactional creation provenance; never replaces existing objects or creates descriptions.
        No automatic selection/attachment or new write grant.
      </p>
    </section>
  {/if}
  {#if profileTableError}<p role="alert" class="mt-2 text-vpro-error">{profileTableError}</p>{/if}
{/if}
