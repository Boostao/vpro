<script lang="ts">
  import { VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
  import SummaryVegetationQualityPreferences from './SummaryVegetationQualityPreferences.svelte';
  import SummaryVegetationPresentationPreferences from './SummaryVegetationPresentationPreferences.svelte';
  import SummaryVegetationFieldListSection from './SummaryVegetationFieldListSection.svelte';
  import SummaryVegetationEnvironmental from './SummaryVegetationEnvironmental.svelte';
  import SummaryVegetationWorkbookPanel from './SummaryVegetationWorkbookPanel.svelte';
  import type { SummaryVegPeerHandlers, SummaryVegPeerModel } from './summaryVegetationReportOps';

  let { model, handlers }: { model: SummaryVegPeerModel; handlers: SummaryVegPeerHandlers } = $props();
</script>

{#if model.preferences && model.preferenceView}
  <section data-summary-preferences aria-label="Saved Summary options">
    {#each model.preferenceView.receipts as receipt}
      {#if receipt.kind !== 'known'}
        <p data-summary-preference-receipt role="alert">
          Preference save status is unknown; reload saved options before saving again.
          {receipt.errorMessage}
        </p>
      {/if}
    {/each}
    <div class="actions">
      <button
        data-summary-preferences-load
        disabled={model.viewBusy ||
          model.operationHeld ||
          model.fieldListHeld ||
          model.preferenceHeld ||
          model.qualityMutationHeld ||
          model.qualityInvalid ||
          model.presentationMutationHeld ||
          model.presentationInvalid}
        onclick={handlers.onLoadPreferences}
      >
        Load saved Summary options
      </button>
      <button
        data-summary-preferences-save
        disabled={model.viewBusy ||
          model.operationHeld ||
          model.fieldListHeld ||
          model.preferenceHeld ||
          model.preferenceInvalid ||
          model.qualityMutationHeld ||
          model.qualityInvalid ||
          model.presentationMutationHeld ||
          model.presentationInvalid ||
          !model.preferenceView.saved}
        onclick={handlers.onSavePreferences}
      >
        Save Summary options
      </button>
      <button
        data-summary-preferences-undo
        disabled={model.viewBusy ||
          model.operationHeld ||
          model.fieldListBusy ||
          model.preferenceHeld ||
          model.qualityMutationHeld ||
          model.presentationMutationHeld ||
          !model.preferenceView.saved}
        onclick={handlers.onUndoPreferences}
      >
        Undo Summary option draft
      </button>
      {#if model.preferenceView.blocked && !model.preferenceView.busy}
        <button
          data-summary-preferences-acknowledge
          disabled={model.operationHeld || model.fieldListBusy}
          onclick={handlers.onAcknowledgePreferences}
        >
          Acknowledge Summary preference outcome
        </button>
      {/if}
      {#if model.preferenceReadBusy}
        <button data-summary-preferences-cancel onclick={handlers.onCancelPreferenceRead}>
          Cancel saved options read
        </button>
      {/if}
    </div>
    <p>
      Load applies your saved grouping, display, and calculation defaults to the controls above. Save updates only your
      Summary Vegetation report settings without changing project plot data.
    </p>
  </section>
{/if}
{#if model.quality}
  <SummaryVegetationQualityPreferences
    contextId={model.owner.contextId}
    preferences={model.quality}
    port={{
      read: (id) => VegetationReportService.GetSummaryVegetationQualityPreferences(id),
      save: (id, request) => VegetationReportService.SaveSummaryVegetationQualityPreferences(id, request),
    }}
    operationHeld={model.operationHeld ||
      model.fieldListHeld ||
      model.viewBusy ||
      model.preferenceHeld ||
      model.preferenceInvalid ||
      model.presentationMutationHeld ||
      model.presentationInvalid}
    mutationHeld={model.operationHeld ||
      model.fieldListBusy ||
      model.viewBusy ||
      model.preferenceHeld ||
      model.presentationMutationHeld}
    onReadBusyChange={handlers.onQualityReadBusyChange}
  />
  {#if !model.qualityView?.saved}<p>Load saved quality filter options before previewing.</p>{/if}
  {#if model.qualityView?.saved?.enforce}
    <p data-summary-quality-active role="status">
      Saved QC enforcement is active; plots failing minimum quality thresholds are excluded.
    </p>
  {/if}
{/if}
{#if model.presentation}
  <SummaryVegetationPresentationPreferences
    contextId={model.owner.contextId}
    preferences={model.presentation}
    port={{
      read: (id) => VegetationReportService.GetSummaryVegetationPresentationPreferences(id),
      save: (id, request) => VegetationReportService.SaveSummaryVegetationPresentationPreferences(id, request),
    }}
    operationHeld={model.operationHeld ||
      model.fieldListHeld ||
      model.viewBusy ||
      model.preferenceHeld ||
      model.preferenceInvalid ||
      model.qualityMutationHeld ||
      model.qualityInvalid}
    mutationHeld={model.operationHeld ||
      model.fieldListBusy ||
      model.viewBusy ||
      model.preferenceHeld ||
      model.qualityMutationHeld}
    onReadBusyChange={handlers.onPresentationReadBusyChange}
  />
{/if}
{#if model.fieldListEnabled && !model.fieldListScopeAvailable}
  <p role="status">
    Select an active project and Site Unit table in the sidebar to configure environmental summary fields.
  </p>
{/if}
{#if model.fieldListEnabled && model.fieldListState}
  <SummaryVegetationFieldListSection
    fieldListState={model.fieldListState}
    presentationReady={!!model.presentationView?.saved && !model.presentationInvalid}
    fieldListEnabledFromPresentation={model.fieldListEnabledFromPresentation}
    fieldListPeerDisabled={model.fieldListPeerDisabled}
    fieldListPeerValidation={model.fieldListPeerValidation}
    onDismissInitialReadError={handlers.onDismissInitialFieldListReadError}
    onLoadFieldList={handlers.onLoadFieldList}
    onCancelRead={handlers.onCancelFieldListRead}
    onStateChange={handlers.onFieldListStateChange}
  />
{/if}
{#if model.environmentalSession}
  <SummaryVegetationEnvironmental
    session={model.environmentalSession}
    port={model.environmentalPort}
    numeric={model.environmentalNumericEnabled}
    lifeform={model.environmentalLifeformEnabled}
    operationHeld={model.operationHeldProp ||
      model.workbookHeld ||
      model.unavailableScope ||
      model.viewBusy ||
      model.fieldListHeld ||
      model.preferenceHeld ||
      model.preferenceInvalid ||
      !!model.viewDraftError ||
      model.qualityMutationHeld ||
      model.qualityUnavailable ||
      model.presentationMutationHeld ||
      model.presentationInvalid}
    onBusyChange={handlers.onEnvironmentalBusyChange}
  />
{/if}
<SummaryVegetationWorkbookPanel
  owner={model.owner}
  calculation={model.calculation}
  savedPresentation={model.savedPresentation}
  onPreferencesLoaded={handlers.onWorkbookPreferencesLoaded}
  disabled={model.operationHeldProp ||
    model.environmentalHeld ||
    model.unavailableScope ||
    model.viewBusy ||
    model.fieldListHeld ||
    model.preferenceHeld ||
    model.preferenceInvalid ||
    !!model.viewDraftError ||
    model.qualityMutationHeld ||
    model.qualityUnavailable ||
    model.presentationMutationHeld ||
    model.presentationInvalid}
  onBusyChange={handlers.onWorkbookBusyChange}
/>
<p class="guidance">
  Preview reflects the options selected above, and your saved defaults only change when you click Save. Title and layout
  settings in Presentation Options apply to exported workbooks and “Preview with Saved Preferences” rather than the
  standard crosstab preview. Presence Class and Significance Class are available when grouped by Layer or None (not
  Strata or Lifeform).
</p>
<p class="guidance">
  Presence values are shown as proportions from 0 to 1 (for example, 0.75 for 75% of plots in a unit).
</p>

<style>
  .guidance {
    margin: 0;
    font-size: 0.9rem;
    color: var(--vpro-ink-secondary);
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.75rem;
    align-items: center;
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
