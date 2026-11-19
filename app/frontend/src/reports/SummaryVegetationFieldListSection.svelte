<script lang="ts">
  import SummaryVegetationFieldList from './SummaryVegetationFieldList.svelte';
  import type { FieldListDesktopState } from './summaryVegetationFieldListDesktop';

  let {
    fieldListState,
    presentationReady,
    fieldListEnabledFromPresentation,
    fieldListPeerDisabled,
    fieldListPeerValidation,
    onDismissInitialReadError,
    onLoadFieldList,
    onCancelRead,
    onStateChange,
  }: {
    fieldListState: FieldListDesktopState;
    presentationReady: boolean;
    fieldListEnabledFromPresentation: boolean;
    fieldListPeerDisabled: boolean;
    fieldListPeerValidation: string;
    onDismissInitialReadError: () => void;
    onLoadFieldList: () => void;
    onCancelRead: () => void;
    onStateChange: () => void;
  } = $props();
</script>

<section
  class="linked-field-list"
  data-summary-field-list-desktop
  aria-label="Linked Summary environmental field list"
>
  {#if fieldListState.readError && !fieldListState.session}
    <p>
      Environmental field list could not be loaded. Acknowledge this error once background
      validation finishes, then click Load environmental fields to try again. Existing drafts and
      saved changes are preserved.
    </p>
    <button
      data-summary-field-list-bootstrap-dismiss
      onclick={onDismissInitialReadError}
      disabled={!fieldListState.canDismissInitialReadError}
    >
      Acknowledge failed initial environmental field read
    </button>
  {/if}
  {#if fieldListState.bootstrapPending && !fieldListState.readBusy}
    <p role="status">
      Environmental field list is still loading. Please wait before retrying.
    </p>
  {/if}
  {#if !presentationReady}
    <p role="status">
      Load saved presentation options above before editing environmental fields.
    </p>
  {/if}
  {#if fieldListState.session && fieldListState.scope}
    {#key fieldListState.session}
      <SummaryVegetationFieldList
        scope={fieldListState.scope}
        session={fieldListState.session}
        enabledFromPresentationDraft={fieldListEnabledFromPresentation}
        peerDisabled={fieldListPeerDisabled}
        peerValidation={fieldListPeerValidation}
        {onStateChange}
      />
    {/key}
  {:else}
    <p>
      Load the environmental field list from your VPro workspace to select which site and soil
      fields appear in the summary.
    </p>
    <button
      data-summary-field-list-bootstrap-load
      onclick={onLoadFieldList}
      disabled={fieldListPeerDisabled ||
        !!fieldListPeerValidation ||
        fieldListState.readBusy ||
        fieldListState.bootstrapPending}
    >
      Load environmental fields
    </button>
  {/if}
  {#if fieldListState.readBusy}
    <button data-summary-field-list-bootstrap-cancel onclick={onCancelRead}>
      Cancel environmental field read
    </button>
  {/if}
</section>

<style>
  .linked-field-list {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 0.75rem;
    min-width: 0;
    overflow-wrap: anywhere;
  }
  button {
    min-height: 2.5rem;
    padding: 0.5rem 0.85rem;
    border: 1px solid var(--vpro-navy);
    border-radius: 0.25rem;
    background: var(--vpro-navy);
    color: var(--vpro-surface);
    font-weight: 600;
    cursor: pointer;
    justify-self: start;
  }
  button:hover:not(:disabled) {
    background: var(--vpro-navy-dark);
    border-color: var(--vpro-navy-dark);
  }
  button:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }
</style>
