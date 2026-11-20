<script lang="ts">
  import type { bindContextPlots } from '../shared/contextPlots';
  import { formatError } from '../shared/readRequests';
  import ProfileRuleInputs from './ProfileRuleInputs.svelte';
  import type { SpeciesPresencePreview } from './projectProfileSpeciesPresence';
  import {
    beginProfileRuleCreation,
    profileCreationOptions,
    profileCreationValue,
    profileEditableFields,
    profileRuleCreationRequest,
    profileRuleDeletionRequest,
    profileRuleEditRequest,
    profileRuleOptions,
    profileRuleValue,
    stageProfileRule,
    stageProfileRuleCreation,
    validateCreatedProfileRule,
    validateProfileLifecycleReview,
    type ProfileField,
    type ProfileRuleChoices,
    type ProfileRuleCreationDraft,
    type ProfileRulesDraft,
  } from './projectProfileRuleEditor';
  import {
    profileCellLabel,
    validateProjectPlotProfileReview,
    type ProfileReviewTable,
    type ProfileRunResult,
    type ValidatedProjectPlotProfileReview,
  } from './projectPlotProfileReview';

  let {
    client,
    allowEditing,
    allowCreation,
    allowDeletion,
    authorityBlocked,
    busy,
    blocked,
    dirty,
    errors,
    choices,
    review = $bindable(),
    draft = $bindable(),
    creation = $bindable(),
    deletion = $bindable(),
    lump = $bindable(),
    subvarieties = $bindable(),
    result = $bindable(),
    presenceResult = $bindable(),
    saving = $bindable(),
    committedFailure = $bindable(),
    error = $bindable(),
    success = $bindable(),
    onbusy,
    onundo,
  }: {
    client: ReturnType<typeof bindContextPlots>;
    allowEditing: boolean;
    allowCreation: boolean;
    allowDeletion: boolean;
    authorityBlocked: boolean;
    busy: boolean;
    blocked: boolean;
    dirty: boolean;
    errors: string[];
    choices: ProfileRuleChoices | null;
    review: ValidatedProjectPlotProfileReview | null;
    draft: ProfileRulesDraft | null;
    creation: ProfileRuleCreationDraft | null;
    deletion: string | null;
    lump: ProfileReviewTable | null;
    subvarieties: boolean;
    result: ProfileRunResult | null;
    presenceResult: SpeciesPresencePreview | null;
    saving: boolean;
    committedFailure: boolean;
    error: string | null;
    success: string | null;
    onbusy: (busy: boolean) => void;
    onundo: () => void;
  } = $props();

  function mutationAuthorized(): boolean {
    if (!authorityBlocked) return true;
    error =
      'Observe the ProjectID source preference outcome before changing profile rules; existing drafts are retained.';
    return false;
  }

  function stage(rowId: string, name: ProfileField, raw: string, nullValue: boolean) {
    if (!mutationAuthorized()) return;
    if (!allowEditing || !draft || busy || committedFailure || creation || deletion !== null) {
      error = 'Finish the current profile proposal before editing existing rules.';
      return;
    }
    try {
      draft = stageProfileRule(draft, rowId, name, raw, nullValue);
      error = null;
      success = null;
      result = null;
      presenceResult = null;
    } catch (cause) {
      error = `Profile draft failed; existing drafts retained: ${formatError(cause)}`;
    }
  }

  async function saveRules() {
    if (!mutationAuthorized()) return;
    if (
      !allowEditing ||
      !draft ||
      busy ||
      committedFailure ||
      creation ||
      deletion !== null ||
      !dirty ||
      errors.length
    ) {
      error = 'Correct or Undo profile errors before saving reviewed changes.';
      return;
    }
    let committed = false;
    saving = true;
    onbusy(true);
    error = null;
    success = null;
    presenceResult = null;
    try {
      await client.SaveProjectPlotProfile(profileRuleEditRequest(draft));
      committed = true;
      draft = null;
      result = null;
      lump = null;
      subvarieties = false;
      const next = validateProjectPlotProfileReview(await client.ReviewProjectPlotProfile());
      review = next;
      draft = { review: next, cells: {} };
      success =
        'Profile assignments and typed technical history committed atomically. Historical PlotCount and plot drafts were not changed.';
    } catch (cause) {
      const cleaned = formatError(cause);
      if (committed || cleaned.includes('Profile rule changes committed, but')) {
        committedFailure = true;
        draft = null;
        result = null;
        lump = null;
        subvarieties = false;
        error = `Profile rules committed, but refresh/cleanup failed. Reload before editing; completed writes must not be replayed: ${cleaned}`;
      } else {
        error = `Profile save failed; raw drafts retained for correction or retry: ${cleaned}`;
      }
    } finally {
      saving = false;
      onbusy(false);
    }
  }

  function proposeCreation() {
    if (!mutationAuthorized()) return;
    if (!allowEditing || !allowCreation || busy || blocked || !review) {
      error = 'Finish existing drafts before proposing one new rule.';
      return;
    }
    try {
      creation = beginProfileRuleCreation(review);
      error = null;
      success = null;
      result = null;
      presenceResult = null;
    } catch (cause) {
      error = `New rule proposal unavailable; no identity allocated: ${formatError(cause)}`;
    }
  }

  function stageCreation(name: ProfileField, raw: string, nullValue: boolean) {
    if (!mutationAuthorized()) return;
    if (!creation || busy || committedFailure) {
      error = 'Review an available new-rule proposal before editing.';
      return;
    }
    try {
      creation = stageProfileRuleCreation(creation, name, raw, nullValue);
      error = null;
      success = null;
    } catch (cause) {
      error = `New rule draft failed; proposal retained: ${formatError(cause)}`;
    }
  }

  async function createRule() {
    if (!mutationAuthorized()) return;
    if (!allowEditing || !allowCreation || !creation || busy || committedFailure || errors.length) {
      error = 'Correct or Undo the explicit new-rule proposal before allocating identity.';
      return;
    }
    const source = creation;
    let committed = false;
    saving = true;
    onbusy(true);
    error = null;
    success = null;
    presenceResult = null;
    try {
      const created = await client.CreateProjectPlotProfileRule(profileRuleCreationRequest(source));
      committed = true;
      creation = null;
      result = null;
      lump = null;
      subvarieties = false;
      validateCreatedProfileRule(created, source);
      const next = validateProjectPlotProfileReview(await client.ReviewProjectPlotProfile());
      validateProfileLifecycleReview(source.review, next, { created });
      const observed = next.rules.rows.find((row) => row.rowId === created.rowId);
      if (!observed) throw new Error('Created physical rule is missing from independent review.');
      validateCreatedProfileRule(observed, source);
      review = next;
      draft = { review: next, cells: {} };
      success = `Physical rule ${created.rowId} and typed creation history committed atomically. No Order, criteria, layer or PlotCount was inferred.`;
    } catch (cause) {
      const cleaned = formatError(cause);
      if (committed || cleaned.includes('Profile rule changes committed, but')) {
        committedFailure = true;
        creation = null;
        draft = null;
        result = null;
        lump = null;
        subvarieties = false;
        error = `Profile creation committed, but refresh/cleanup failed. Reload before another proposal; completed writes must not be replayed: ${cleaned}`;
      } else {
        error = `Profile creation failed; nullable/raw proposal retained for retry: ${cleaned}`;
      }
    } finally {
      saving = false;
      onbusy(false);
    }
  }

  function reviewDeletion(rowId: string) {
    if (!mutationAuthorized()) return;
    if (
      !allowEditing ||
      !allowDeletion ||
      busy ||
      blocked ||
      !review ||
      review.rules.rows.filter((row) => row.rowId === rowId).length !== 1
    ) {
      error = 'Finish drafts before reviewing one original physical rule for deletion.';
      return;
    }
    deletion = rowId;
    error = null;
    success = null;
    result = null;
    presenceResult = null;
  }

  async function deleteRule() {
    if (!mutationAuthorized()) return;
    if (!allowEditing || !allowDeletion || deletion === null || !review || busy || committedFailure) {
      error = 'Explicitly review one physical rule before confirming deletion.';
      return;
    }
    const rowId = deletion;
    const source = review;
    let committed = false;
    saving = true;
    onbusy(true);
    error = null;
    success = null;
    presenceResult = null;
    try {
      await client.DeleteProjectPlotProfileRule(profileRuleDeletionRequest(source, rowId, true));
      committed = true;
      deletion = null;
      result = null;
      lump = null;
      subvarieties = false;
      const next = validateProjectPlotProfileReview(await client.ReviewProjectPlotProfile());
      validateProfileLifecycleReview(source, next, { deleted: rowId });
      if (next.rules.rows.some((row) => row.rowId === rowId)) {
        throw new Error('Deleted physical rule remains in independent review.');
      }
      review = next;
      draft = { review: next, cells: {} };
      success = `Physical rule ${rowId} deleted with full typed history; its identity remains reserved. Surviving rules/counts and plot drafts were not changed.`;
    } catch (cause) {
      const cleaned = formatError(cause);
      if (committed || cleaned.includes('Profile rule changes committed, but')) {
        committedFailure = true;
        deletion = null;
        draft = null;
        result = null;
        lump = null;
        subvarieties = false;
        error = `Profile deletion committed, but refresh/cleanup failed. Reload before another review; completed writes must not be replayed: ${cleaned}`;
      } else {
        error = `Profile deletion failed; original confirmation retained for retry: ${cleaned}`;
      }
    } finally {
      saving = false;
      onbusy(false);
    }
  }
</script>

{#if allowEditing && draft}
  <section class="mt-3" aria-label="Stored profile rule editor">
    <div class="flex flex-wrap gap-2">
      <button
        type="button"
        class="vpro-prof-btn-primary px-3 py-2 rounded disabled:opacity-50"
        disabled={authorityBlocked ||
          busy ||
          committedFailure ||
          creation !== null ||
          deletion !== null ||
          !dirty ||
          errors.length > 0}
        onclick={() => void saveRules()}
      >
        Save profile rules
      </button>
      <button
        type="button"
        class="vpro-prof-btn px-3 py-2 rounded disabled:opacity-50"
        disabled={busy || committedFailure || !blocked}
        onclick={onundo}
      >
        Undo profile drafts
      </button>
      {#if allowCreation}
        <button
          type="button"
          class="vpro-prof-btn px-3 py-2 rounded disabled:opacity-50"
          disabled={authorityBlocked || busy || blocked}
          onclick={proposeCreation}
        >
          Review new profile rule
        </button>
      {/if}
    </div>
    {#if creation}
      {@const proposal = creation}
      <fieldset class="vpro-prof-card mt-3 p-3 rounded" disabled={authorityBlocked || busy || committedFailure}>
        <legend class="font-semibold">New rule proposal (no physical identity allocated)</legend>
        <ProfileRuleInputs
          prefix="new-profile-rule"
          identityLabel="new proposal"
          fields={profileEditableFields.map((name) => ({
            name,
            cell: profileCreationValue(proposal, name),
            options: profileCreationOptions(proposal, name, choices, lump),
          }))}
          onstage={stageCreation}
        />
        <p class="mt-3 text-sm">
          Eight explicit nullable assignments; PlotCount remains NULL. Create allocates one unused physical identity and
          complete typed history. Rule completeness for preview is a separate decision.
        </p>
        <button
          type="button"
          class="vpro-prof-btn-primary mt-3 px-3 py-2 rounded disabled:opacity-50"
          disabled={authorityBlocked || errors.length > 0}
          onclick={() => void createRule()}
        >
          Create reviewed profile rule
        </button>
      </fieldset>
    {/if}
    {#if deletion !== null}
      {@const row = review?.rules.rows.find((r) => r.rowId === deletion)}
      <section class="vpro-prof-danger-card mt-3 p-3 rounded" aria-label="Profile rule deletion confirmation">
        <h3 class="font-semibold">Delete reviewed physical rule {deletion}?</h3>
        {#if row && review}
          <dl class="grid grid-cols-1 sm:grid-cols-2 gap-2 mt-2">
            {#each row.cells as cell, index}
              <div>
                <dt class="font-medium">{review.rules.columns[index].name}</dt>
                <dd class="whitespace-pre-wrap break-words">{profileCellLabel(cell)}</dd>
              </div>
            {/each}
          </dl>
        {/if}
        <p class="mt-3">
          One rule only. Surviving rules and historical counts remain unchanged. Full typed deletion history and the
          reserved physical identity commit together; restoration is unavailable.
        </p>
        <button
          type="button"
          class="vpro-prof-btn px-3 py-2 rounded disabled:opacity-50"
          disabled={authorityBlocked || busy || committedFailure}
          onclick={() => void deleteRule()}
        >
          Confirm profile rule deletion
        </button>
        <button
          type="button"
          class="vpro-prof-btn mt-3 ml-2 px-3 py-2 rounded disabled:opacity-50"
          disabled={busy || committedFailure}
          onclick={onundo}
        >
          Cancel profile deletion
        </button>
      </section>
    {/if}
    {#each draft.review.rules.rows as row (row.rowId)}
      {@const sourceDraft = draft}
      <fieldset
        class="vpro-prof-card mt-3 p-3 rounded"
        disabled={authorityBlocked || busy || committedFailure || creation !== null || deletion !== null}
      >
        <legend class="font-semibold">Physical rule {row.rowId}</legend>
        <ProfileRuleInputs
          prefix={`profile-${row.rowId}`}
          identityLabel={`rule ${row.rowId}`}
          fields={profileEditableFields.map((name) => ({
            name,
            cell: profileRuleValue(sourceDraft, row.rowId, name),
            options: profileRuleOptions(sourceDraft, row.rowId, name, choices, lump),
          }))}
          onstage={(name, raw, nullValue) => stage(row.rowId, name, raw, nullValue)}
        />
        {#if allowDeletion}
          <button
            type="button"
            class="vpro-prof-btn mt-3 px-3 py-2 rounded disabled:opacity-50"
            disabled={authorityBlocked || dirty}
            onclick={() => reviewDeletion(row.rowId)}
          >
            Review deletion of rule {row.rowId}
          </button>
        {/if}
      </fieldset>
    {/each}
    <p class="vpro-prof-muted mt-3 text-sm">
      Existing rules only. Table changes to Veg/Lump visibly propose Field=Species/LumpCode; no Layer, Species or
      Criteria is cleared. NULL differs from empty text. Only changed assignments are saved; stored PlotCount is
      read-only. Env field suggestions come from this project; Veg species suggestions use grouped VLists codes, and
      Lump species suggestions require explicit lump review. Suggestions do not restrict those literal fields.
    </p>
    {#if choices}
      <p class="vpro-prof-muted mt-1 text-xs">
        Source species definitions: {choices.species.length} distinct typed codes, including {choices.species.filter(
          (c) => c.storage === 'null'
        ).length} NULL and {choices.species.filter((c) => c.storage === 'text' && c.text === '').length} empty. NULL is set
        explicitly, not by an empty suggestion.
      </p>
    {/if}
  </section>
{/if}

<style>
  .vpro-prof-btn {
    background: var(--vpro-surface);
    color: var(--vpro-navy);
    border: 1px solid var(--vpro-navy);
  }
  .vpro-prof-btn-primary {
    background: var(--vpro-navy);
    color: var(--vpro-surface);
    border: 1px solid var(--vpro-navy);
    border-bottom: 2px solid var(--vpro-gold);
    font-weight: 600;
  }
  .vpro-prof-card {
    background: var(--vpro-surface);
    border: 1px solid var(--vpro-border);
  }
  .vpro-prof-danger-card {
    background: var(--vpro-surface);
    border: 1px solid var(--vpro-error);
    border-left: 4px solid var(--vpro-error);
  }
  .vpro-prof-muted {
    color: var(--vpro-ink-secondary);
  }
</style>
