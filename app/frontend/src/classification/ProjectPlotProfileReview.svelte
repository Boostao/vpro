<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import type { bindContextPlots } from '../shared/contextPlots';
  import { ReadRequests, formatError, trackIfCancellable } from '../shared/readRequests';
  import type { EditorCloseState } from '../shell/closeLifecycle';
  import ProjectPlotProfileHeader from './ProjectPlotProfileHeader.svelte';
  import ProjectPlotProfilePreviewSection from './ProjectPlotProfilePreviewSection.svelte';
  import ProjectPlotProfileRulesSection from './ProjectPlotProfileRulesSection.svelte';
  import { validateSpeciesPresencePreview, type SpeciesPresencePreview } from './projectProfileSpeciesPresence';
  import {
    ClassificationService,
    type ProfileLumpChoice,
    type ProjectMetadataTable,
    type ProjectPlotProfileFilterRequest,
    type ProjectPlotProfileRunRequest,
  } from '../../bindings/github.com/boostao/vpro/app';
  import {
    profileCreationErrors,
    profileRuleErrors,
    profileRulesDirty,
    validateProfileChoices,
    type ProfileRuleChoices,
    type ProfileRuleCreationDraft,
    type ProfileRulesDraft,
  } from './projectProfileRuleEditor';
  import {
    validateProfileRunResult,
    validateProjectPlotProfileReview,
    validateProjectProfileLump,
    type ProfileReviewTable,
    type ProfileRunResult,
    type ValidatedProjectPlotProfileReview,
  } from './projectPlotProfileReview';

  type ProfileClient = ReturnType<typeof bindContextPlots> & {
    ListProjectPlotProfileLumpTables?: () => Promise<ProfileLumpChoice[] | null>;
    ReviewProjectPlotProfileLumpTable?: (location: string) => Promise<ProjectMetadataTable>;
  };

  let {
    client,
    onclosed,
    onbusy,
    onblocked,
    onapply,
    onsureview,
    contextId = '',
    activeSU = '',
    allowPresence = false,
    authorityBlocked = false,
    allowSaveSU = false,
    allowFiltering = false,
    allowRun = false,
    allowEditing = false,
    allowCreation = false,
    allowDeletion = false,
  }: {
    client: ProfileClient;
    onclosed: () => void;
    onbusy: (busy: boolean) => void;
    onblocked: (blocked: boolean) => void;
    allowRun?: boolean;
    allowEditing?: boolean;
    allowCreation?: boolean;
    allowDeletion?: boolean;
    authorityBlocked?: boolean;
    allowFiltering?: boolean;
    onapply?: (proposal: ProjectPlotProfileFilterRequest) => Promise<void>;
    allowSaveSU?: boolean;
    onsureview?: (proposal: ProjectPlotProfileFilterRequest) => Promise<void>;
    contextId?: string;
    activeSU?: string;
    allowPresence?: boolean;
  } = $props();

  let review = $state<ValidatedProjectPlotProfileReview | null>(null);
  let reading = $state(false);
  let running = $state(false);
  let error = $state<string | null>(null);
  let lump = $state<ProfileReviewTable | null>(null);
  let lumpChoices = $state.raw<ProfileLumpChoice[]>([]);
  let selectedLumpLocation = $state('');
  let startWithAllPlots = $state(false);
  let subvarieties = $state(false);
  let result = $state<ProfileRunResult | null>(null);
  let presenceResult = $state.raw<SpeciesPresencePreview | null>(null);
  let runInput = $state<ProjectPlotProfileRunRequest | null>(null);
  let draft = $state<ProfileRulesDraft | null>(null);
  let saving = $state(false);
  let committedFailure = $state(false);
  let success = $state<string | null>(null);
  let choices = $state<ProfileRuleChoices | null>(null);
  let creation = $state<ProfileRuleCreationDraft | null>(null);
  let deletion = $state<string | null>(null);

  const dirty = $derived(draft ? profileRulesDirty(draft) : false);
  const errors = $derived(creation ? profileCreationErrors(creation) : draft ? profileRuleErrors(draft) : []);
  const blocked = $derived(dirty || creation !== null || deletion !== null || committedFailure);
  const busy = $derived(reading || saving);
  let generation = 0;
  const reads = new ReadRequests();

  onMount(() => {
    void reload();
  });
  $effect(() => onblocked(blocked));
  onDestroy(() => {
    generation++;
    reads.cancelAll();
    onbusy(false);
    onblocked(false);
  });

  export function getCloseState(): EditorCloseState {
    return {
      unsaved: blocked,
      busy,
      canSave: false,
      error,
      saveReason:
        'Save or Undo profile rules explicitly before closing or changing context; ordinary plot Save never writes profile rules.',
    };
  }

  export function undo() {
    if (busy || committedFailure) {
      error = 'Wait for the operation or Reload committed rules before Undo.';
      return;
    }
    creation = null;
    deletion = null;
    presenceResult = null;
    if (draft) draft = { review: draft.review, cells: {} };
    error = null;
    success = 'Profile drafts undone; no rules, counts or history changed.';
  }

  function close() {
    if (busy || blocked) {
      error = 'Save or Undo profile drafts, or Reload committed rules, before closing this review.';
      return;
    }
    onclosed();
  }

  async function reload() {
    if (busy || dirty || creation || deletion !== null) {
      error = 'Save or Undo profile drafts before reloading; raw errors were retained.';
      return;
    }
    const request = ++generation;
    draft = null;
    choices = null;
    presenceResult = null;
    review = null;
    error = null;
    lump = null;
    result = null;
    reading = true;
    onbusy(true);
    try {
      const listLumpFn = client.ListProjectPlotProfileLumpTables;
      const [source, suggestions, availableLumps] = await Promise.all([
        reads.track(client.ReviewProjectPlotProfile()),
        allowEditing ? reads.track(client.ListProjectPlotProfileChoices()) : Promise.resolve(null),
        allowRun || allowEditing || allowPresence
          ? trackIfCancellable(
              reads,
              listLumpFn
                ? listLumpFn()
                : contextId
                  ? ClassificationService.ListProjectPlotProfileLumpTables(contextId)
                  : Promise.resolve(null)
            ).catch(() => null)
          : Promise.resolve(null),
      ]);
      const validated = validateProjectPlotProfileReview(source);
      const validatedChoices = suggestions ? validateProfileChoices(suggestions) : null;
      if (request === generation) {
        review = validated;
        choices = validatedChoices;
        draft = allowEditing ? { review: validated, cells: {} } : null;
        if (Array.isArray(availableLumps) && availableLumps.length > 0) {
          lumpChoices = availableLumps;
          if (!selectedLumpLocation || !availableLumps.some((c) => c.location === selectedLumpLocation)) {
            const firstTable = availableLumps.find((c) => c.location !== 'None');
            selectedLumpLocation = firstTable ? firstTable.location : 'None';
          }
        }
        committedFailure = false;
        success = null;
      }
    } catch (cause) {
      if (request === generation) {
        error = `Project-local profile review failed; no rules, counts or filters changed: ${formatError(cause)}`;
      }
    } finally {
      if (request === generation) {
        reading = false;
        onbusy(false);
      }
    }
  }

  async function reviewLump() {
    if ((!allowRun && !allowEditing && !allowPresence) || busy || !review) return;
    if (selectedLumpLocation === 'None') {
      lump = null;
      result = null;
      presenceResult = null;
      error = null;
      return;
    }
    const request = ++generation;
    error = null;
    lump = null;
    result = null;
    presenceResult = null;
    reading = true;
    onbusy(true);
    try {
      const reviewLumpFn = client.ReviewProjectPlotProfileLumpTable;
      const rawLoader: PromiseLike<ProjectMetadataTable> =
        selectedLumpLocation && (reviewLumpFn || contextId)
          ? reviewLumpFn
            ? reviewLumpFn(selectedLumpLocation)
            : ClassificationService.ReviewProjectPlotProfileLumpTable(contextId, selectedLumpLocation)
          : client.ReviewProjectPlotProfileLump();
      const source = validateProjectProfileLump(await trackIfCancellable(reads, rawLoader));
      if (request === generation) lump = source;
    } catch (cause) {
      if (request === generation) {
        error = `Project-local lump review failed; no definitions changed: ${formatError(cause)}`;
      }
    } finally {
      if (request === generation) {
        reading = false;
        onbusy(false);
      }
    }
  }

  async function run() {
    if (!allowRun || busy || blocked || !review) return;
    const source = review;
    const request = ++generation;
    const activeLumpChoice = selectedLumpLocation.trim();
    const effectiveLump = activeLumpChoice === 'None' ? null : lump;
    if (activeLumpChoice === 'None' && lump !== null) lump = null;
    const input: ProjectPlotProfileRunRequest = {
      originalRules: source.rules,
      projectLump: lump,
      subvarieties,
      ...(startWithAllPlots ? { startWithAllPlots: true } : {}),
      ...(activeLumpChoice ? { lumpTable: activeLumpChoice } : {}),
    };
    if (effectiveLump !== lump) input.projectLump = effectiveLump;
    result = null;
    presenceResult = null;
    error = null;
    reading = true;
    running = true;
    onbusy(true);
    try {
      const preview = await reads.track(client.RunProjectPlotProfile(input));
      if (request === generation) {
        result = validateProfileRunResult(preview, source);
        runInput = $state.snapshot(input);
      }
    } catch (cause) {
      if (request === generation) {
        error = `Profile preview failed; no stored rules, counts or filters changed: ${formatError(cause)}`;
      }
    } finally {
      if (request === generation) {
        reading = false;
        running = false;
        onbusy(false);
      }
    }
  }

  function cancelRun() {
    generation++;
    reads.cancelAll();
    running = false;
    reading = false;
    result = null;
    onbusy(false);
    presenceResult = null;
    error = 'Profile preview cancelled; reviewed inputs retained. No stored rules, counts or filters changed.';
  }

  async function runPresence() {
    if (!allowPresence || busy || blocked || !review || subvarieties) return;
    const request = ++generation;
    const expected = { contextId, project: review.project, table: review.table, su: activeSU };
    result = null;
    runInput = null;
    presenceResult = null;
    error = null;
    success = null;
    reading = true;
    running = true;
    onbusy(true);
    try {
      const input = $state.snapshot({ originalRules: review.rules, projectLump: lump, subvarieties: false });
      const wire = await reads.track(client.PreviewProjectProfileSpeciesPresence(input));
      if (request !== generation) return;
      const validated = await validateSpeciesPresencePreview(wire, expected);
      if (request === generation) presenceResult = validated;
    } catch (cause) {
      if (request === generation) {
        error = `Species-only preview failed; no rules, counts, navigation or SU changed: ${formatError(cause)}`;
      }
    } finally {
      if (request === generation) {
        reading = false;
        running = false;
        onbusy(false);
      }
    }
  }
</script>

<section class="vpro-prof-panel m-3 p-3 rounded-lg" aria-label="Project-local plot profile review">
  <ProjectPlotProfileHeader
    {allowEditing}
    {allowRun}
    {allowPresence}
    {busy}
    {blocked}
    {dirty}
    hasCreationOrDeletion={creation !== null || deletion !== null}
    hasReview={review !== null}
    {running}
    {reading}
    {subvarieties}
    {success}
    onreload={() => void reload()}
    onrun={() => void run()}
    oncancelrun={cancelRun}
    onrunpresence={() => void runPresence()}
    onclose={close}
  />

  {#if error}<p role="alert" class="vpro-prof-alert mt-3">{error.replace(/(?:RuntimeError|Error):\s*/gi, '')}</p>{/if}

  {#if (allowRun || allowEditing || allowPresence) && review}
    <div class="flex flex-wrap gap-3 items-center mt-3">
      {#if lumpChoices.length > 0}
        <label class="flex gap-2 items-center text-sm">
          <span>Lump Table</span>
          <select
            class="vpro-prof-select px-2 py-1 rounded"
            disabled={busy || blocked}
            bind:value={selectedLumpLocation}
            onchange={() => {
              lump = null;
              result = null;
              presenceResult = null;
              error = null;
            }}
          >
            {#each lumpChoices as ch (`${ch.role}::${ch.location}`)}
              <option value={ch.location}>
                {ch.location === 'None' ? 'None (no lump table)' : `${ch.role}.${ch.table} (${ch.rowCount})`}
              </option>
            {/each}
          </select>
        </label>
      {/if}
      <button
        type="button"
        class="vpro-prof-btn px-3 py-2 rounded disabled:opacity-50"
        disabled={busy || selectedLumpLocation === 'None'}
        onclick={() => void reviewLump()}
      >
        Review and select project lump table
      </button>
      {#if lump}
        <span>
          {selectedLumpLocation && selectedLumpLocation !== 'None' ? selectedLumpLocation : `${review.project}_Lump`}
          explicitly selected: {lump.rows.length} physical definitions.
        </span>
        <button
          type="button"
          class="vpro-prof-btn px-3 py-2 rounded disabled:opacity-50"
          disabled={busy || blocked}
          onclick={() => {
            lump = null;
            subvarieties = false;
            result = null;
            error = null;
            presenceResult = null;
          }}
        >
          Clear lump selection
        </button>
      {/if}
      {#if allowRun}
        <label class="flex gap-2 items-center">
          <input
            type="checkbox"
            disabled={busy || blocked || (!lump && selectedLumpLocation !== 'None')}
            checked={subvarieties}
            onchange={(event) => {
              subvarieties = event.currentTarget.checked;
              result = null;
              presenceResult = null;
              error = null;
            }}
          />
          Combine source subvarieties
        </label>
        <label class="flex gap-2 items-center">
          <input
            type="checkbox"
            disabled={busy || blocked}
            bind:checked={startWithAllPlots}
            onchange={() => {
              result = null;
              error = null;
            }}
          />
          Start with all plots
        </label>
      {/if}
    </div>
  {/if}

  <ProjectPlotProfileRulesSection
    {client}
    {allowEditing}
    {allowCreation}
    {allowDeletion}
    {authorityBlocked}
    {busy}
    {blocked}
    {dirty}
    {errors}
    {choices}
    bind:review
    bind:draft
    bind:creation
    bind:deletion
    bind:lump
    bind:subvarieties
    bind:result
    bind:presenceResult
    bind:saving
    bind:committedFailure
    bind:error
    bind:success
    {onbusy}
    onundo={undo}
  />

  <ProjectPlotProfilePreviewSection
    {allowRun}
    {allowEditing}
    {allowPresence}
    {allowSaveSU}
    {allowFiltering}
    {busy}
    {blocked}
    {review}
    {lump}
    {result}
    {runInput}
    {presenceResult}
    bind:error
    {onapply}
    {onsureview}
  />
</section>

<style>
  .vpro-prof-panel {
    background: var(--vpro-canvas);
    border: 1px solid var(--vpro-border);
    border-top: 4px solid var(--vpro-navy);
    color: var(--vpro-ink);
  }
  .vpro-prof-btn {
    background: var(--vpro-surface);
    color: var(--vpro-navy);
    border: 1px solid var(--vpro-navy);
  }
  .vpro-prof-select {
    background: var(--vpro-surface);
    color: var(--vpro-ink);
    border: 1px solid var(--vpro-border);
  }
  .vpro-prof-alert {
    color: var(--vpro-error);
    font-weight: 600;
  }
</style>
