<script lang="ts">
  let {
    allowEditing,
    allowRun,
    allowPresence,
    noProfileSelected = false,
    busy,
    blocked,
    dirty,
    hasCreationOrDeletion,
    hasReview,
    running,
    reading,
    subvarieties,
    success,
    onreload,
    onrun,
    oncancelrun,
    onrunpresence,
    onclose,
  }: {
    allowEditing: boolean;
    allowRun: boolean;
    allowPresence: boolean;
    noProfileSelected?: boolean;
    busy: boolean;
    blocked: boolean;
    dirty: boolean;
    hasCreationOrDeletion: boolean;
    hasReview: boolean;
    running: boolean;
    reading: boolean;
    subvarieties: boolean;
    success: string | null;
    onreload: () => void;
    onrun: () => void;
    oncancelrun: () => void;
    onrunpresence: () => void;
    onclose: () => void;
  } = $props();
</script>

<div class="flex flex-wrap gap-2 items-center justify-between">
  <h2 class="vpro-prof-title font-semibold">
    {#if noProfileSelected}
      Plot profiling — no profile selected
    {:else}
      Selected plot profile {allowEditing ? 'rules' : 'review (read-only)'}
    {/if}
  </h2>
  <div class="flex flex-wrap gap-2">
    <button
      type="button"
      class="vpro-prof-btn px-3 py-2 rounded disabled:opacity-50"
      disabled={busy || dirty || hasCreationOrDeletion || noProfileSelected}
      onclick={onreload}
    >
      Reload profile review
    </button>
    {#if allowRun}
      <button
        type="button"
        class="vpro-prof-btn-primary px-3 py-2 rounded disabled:opacity-50"
        disabled={busy || blocked || !hasReview}
        onclick={onrun}
      >
        Run stored profile preview
      </button>
      {#if running}
        <button type="button" class="vpro-prof-btn px-3 py-2 rounded" onclick={oncancelrun}>
          Cancel profile preview
        </button>
      {/if}
    {:else}
      <button
        type="button"
        class="vpro-prof-btn px-3 py-2 rounded disabled:opacity-50"
        disabled
        title="Ordered profile execution is not implemented."
      >
        Run Profile (unavailable)
      </button>
    {/if}
    {#if allowPresence}
      <button
        type="button"
        class="vpro-prof-btn px-3 py-2 rounded disabled:opacity-50"
        disabled={busy || blocked || !hasReview || subvarieties}
        onclick={onrunpresence}
      >
        Preview saved species-only matches
      </button>
      {#if running && !allowRun}
        <button type="button" class="vpro-prof-btn px-3 py-2 rounded" onclick={oncancelrun}>
          Cancel species-only preview
        </button>
      {/if}
    {/if}
    <button
      type="button"
      class="vpro-prof-btn px-3 py-2 rounded disabled:opacity-50"
      disabled={busy || blocked}
      onclick={onclose}
    >
      Close profile review
    </button>
  </div>
</div>

{#if allowPresence && subvarieties}
  <p role="alert" class="vpro-prof-warn mt-3">
    Species-only subvariety preparation is unavailable. Clear the ordered preview's subvariety selection to preview
    literal saved species.
  </p>
{/if}
{#if success}<p role="status" class="vpro-prof-success mt-3">{success}</p>{/if}
{#if reading}<p role="status" class="mt-3">Reading original inputs or evaluating stored profile rules...</p>{/if}

<style>
  .vpro-prof-title {
    color: var(--vpro-navy);
  }
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
  .vpro-prof-warn {
    color: var(--vpro-navy-dark);
    background: rgba(252, 186, 25, 0.22);
    border-left: 3px solid var(--vpro-gold);
    padding: 0.35rem 0.6rem;
  }
  .vpro-prof-success {
    color: var(--vpro-forest);
    font-weight: 600;
  }
</style>
