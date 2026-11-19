<script lang="ts">
  import { VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
  import SummaryVegetationQualityPreferences from './SummaryVegetationQualityPreferences.svelte';
  import SummaryVegetationPresentationPreferences from './SummaryVegetationPresentationPreferences.svelte';
  import SummaryVegetationFieldListSection from './SummaryVegetationFieldListSection.svelte';
  import SummaryVegetationEnvironmental from './SummaryVegetationEnvironmental.svelte';
  import SummaryVegetationWorkbookPanel from './SummaryVegetationWorkbookPanel.svelte';
  import type { FieldListDesktopState } from './summaryVegetationFieldListDesktop';
  import type { SummaryVegetationPreferencesSession } from './summaryVegetationPreferences';
  import type { SummaryVegetationQualityPreferencesSession } from './summaryVegetationQualityPreferences';
  import type { SummaryVegetationPresentationPreferencesSession } from './summaryVegetationPresentationPreferences';
  import type {
    SummaryEnvironmentalSession,
    SummaryEnvironmentalNumericSession,
    SummaryEnvironmentalLifeformSession,
    SummaryEnvironmentalPort,
  } from './summaryVegetationEnvironmental';
  import type { SummaryWorkbookCalculation } from './summaryVegetationWorkbook';

  interface SavedPresentationDraft {
    title: string;
    includeEnv: boolean;
    createSummary: boolean;
    showCommon: boolean;
    showGuide: boolean;
    constancy: boolean;
  }

  interface LoadedWorkbookScopeOptions {
    unitScope?: 'su' | 'hierarchy' | 'none' | 'field';
    unitField?: string;
    breakpointPolicy?: 'lowest' | 'highest';
    combineVariants?: boolean;
    lumpTable?: string;
    includeGoldstreamMetadata?: boolean;
  }

  let {
    owner,
    preferences,
    preferenceView,
    preferenceReadBusy,
    preferenceHeld,
    preferenceInvalid,
    quality,
    qualityView,
    qualityMutationHeld,
    qualityInvalid,
    qualityUnavailable,
    presentation,
    presentationView,
    presentationMutationHeld,
    presentationInvalid,
    fieldListEnabled,
    fieldListScopeAvailable,
    fieldListState,
    fieldListHeld,
    fieldListBusy,
    fieldListPeerDisabled,
    fieldListPeerValidation,
    fieldListEnabledFromPresentation,
    environmentalSession,
    environmentalPort,
    environmentalNumericEnabled,
    environmentalLifeformEnabled,
    environmentalHeld,
    operationHeldProp,
    operationHeld,
    workbookHeld,
    unavailableScope,
    viewBusy,
    viewDraftError,
    calculation,
    savedPresentation,
    onLoadPreferences,
    onSavePreferences,
    onUndoPreferences,
    onAcknowledgePreferences,
    onCancelPreferenceRead,
    onQualityReadBusyChange,
    onPresentationReadBusyChange,
    onDismissInitialFieldListReadError,
    onLoadFieldList,
    onCancelFieldListRead,
    onFieldListStateChange,
    onEnvironmentalBusyChange,
    onWorkbookPreferencesLoaded,
    onWorkbookBusyChange,
  }: {
    owner: { contextId: string; project: string; projectPath: string; su: string; suPath: string };
    preferences: SummaryVegetationPreferencesSession | null;
    preferenceView: ReturnType<SummaryVegetationPreferencesSession['view']> | null;
    preferenceReadBusy: boolean;
    preferenceHeld: boolean;
    preferenceInvalid: boolean;
    quality: SummaryVegetationQualityPreferencesSession | null;
    qualityView: ReturnType<SummaryVegetationQualityPreferencesSession['view']> | null;
    qualityMutationHeld: boolean;
    qualityInvalid: boolean;
    qualityUnavailable: boolean;
    presentation: SummaryVegetationPresentationPreferencesSession | null;
    presentationView: ReturnType<SummaryVegetationPresentationPreferencesSession['view']> | null;
    presentationMutationHeld: boolean;
    presentationInvalid: boolean;
    fieldListEnabled: boolean;
    fieldListScopeAvailable: boolean;
    fieldListState: FieldListDesktopState | null;
    fieldListHeld: boolean;
    fieldListBusy: boolean;
    fieldListPeerDisabled: boolean;
    fieldListPeerValidation: string;
    fieldListEnabledFromPresentation: boolean;
    environmentalSession:
      | SummaryEnvironmentalSession
      | SummaryEnvironmentalNumericSession
      | SummaryEnvironmentalLifeformSession
      | null;
    environmentalPort: SummaryEnvironmentalPort;
    environmentalNumericEnabled: boolean;
    environmentalLifeformEnabled: boolean;
    environmentalHeld: boolean;
    operationHeldProp: boolean;
    operationHeld: boolean;
    workbookHeld: boolean;
    unavailableScope: boolean;
    viewBusy: boolean;
    viewDraftError: string;
    calculation: SummaryWorkbookCalculation;
    savedPresentation: SavedPresentationDraft | null;
    onLoadPreferences: () => void;
    onSavePreferences: () => void;
    onUndoPreferences: () => void;
    onAcknowledgePreferences: () => void;
    onCancelPreferenceRead: () => void;
    onQualityReadBusyChange: (busy: boolean) => void;
    onPresentationReadBusyChange: (busy: boolean) => void;
    onDismissInitialFieldListReadError: () => void;
    onLoadFieldList: () => void;
    onCancelFieldListRead: () => void;
    onFieldListStateChange: () => void;
    onEnvironmentalBusyChange: () => void;
    onWorkbookPreferencesLoaded: (opts: LoadedWorkbookScopeOptions) => void;
    onWorkbookBusyChange: (held: boolean) => void;
  } = $props();
</script>

{#if preferences && preferenceView}
  <section data-summary-preferences aria-label="Saved Summary options">
    {#each preferenceView.receipts as receipt}
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
        disabled={viewBusy ||
          operationHeld ||
          fieldListHeld ||
          preferenceHeld ||
          qualityMutationHeld ||
          qualityInvalid ||
          presentationMutationHeld ||
          presentationInvalid}
        onclick={onLoadPreferences}
      >
        Load saved Summary options
      </button>
      <button
        data-summary-preferences-save
        disabled={viewBusy ||
          operationHeld ||
          fieldListHeld ||
          preferenceHeld ||
          preferenceInvalid ||
          qualityMutationHeld ||
          qualityInvalid ||
          presentationMutationHeld ||
          presentationInvalid ||
          !preferenceView.saved}
        onclick={onSavePreferences}
      >
        Save Summary options
      </button>
      <button
        data-summary-preferences-undo
        disabled={viewBusy ||
          operationHeld ||
          fieldListBusy ||
          preferenceHeld ||
          qualityMutationHeld ||
          presentationMutationHeld ||
          !preferenceView.saved}
        onclick={onUndoPreferences}
      >
        Undo Summary option draft
      </button>
      {#if preferenceView.blocked && !preferenceView.busy}
        <button
          data-summary-preferences-acknowledge
          disabled={operationHeld || fieldListBusy}
          onclick={onAcknowledgePreferences}
        >
          Acknowledge Summary preference outcome
        </button>
      {/if}
      {#if preferenceReadBusy}
        <button data-summary-preferences-cancel onclick={onCancelPreferenceRead}>
          Cancel saved options read
        </button>
      {/if}
    </div>
    <p>
      Load applies your saved grouping, display, and calculation defaults to the controls above.
      Save updates only your Summary Vegetation report settings without changing project plot data.
    </p>
  </section>
{/if}
{#if quality}
  <SummaryVegetationQualityPreferences
    contextId={owner.contextId}
    preferences={quality}
    port={{
      read: id => VegetationReportService.GetSummaryVegetationQualityPreferences(id),
      save: (id, request) =>
        VegetationReportService.SaveSummaryVegetationQualityPreferences(id, request),
    }}
    operationHeld={operationHeld ||
      fieldListHeld ||
      viewBusy ||
      preferenceHeld ||
      preferenceInvalid ||
      presentationMutationHeld ||
      presentationInvalid}
    mutationHeld={operationHeld ||
      fieldListBusy ||
      viewBusy ||
      preferenceHeld ||
      presentationMutationHeld}
    onReadBusyChange={onQualityReadBusyChange}
  />
  {#if !qualityView?.saved}<p>Load saved quality filter options before previewing.</p>{/if}
  {#if qualityView?.saved?.enforce}
    <p data-summary-quality-active role="status">
      Saved QC enforcement is active; plots failing minimum quality thresholds are excluded.
    </p>
  {/if}
{/if}
{#if presentation}
  <SummaryVegetationPresentationPreferences
    contextId={owner.contextId}
    preferences={presentation}
    port={{
      read: id => VegetationReportService.GetSummaryVegetationPresentationPreferences(id),
      save: (id, request) =>
        VegetationReportService.SaveSummaryVegetationPresentationPreferences(id, request),
    }}
    operationHeld={operationHeld ||
      fieldListHeld ||
      viewBusy ||
      preferenceHeld ||
      preferenceInvalid ||
      qualityMutationHeld ||
      qualityInvalid}
    mutationHeld={operationHeld ||
      fieldListBusy ||
      viewBusy ||
      preferenceHeld ||
      qualityMutationHeld}
    onReadBusyChange={onPresentationReadBusyChange}
  />
{/if}
{#if fieldListEnabled && !fieldListScopeAvailable}
  <p role="status">
    Select an active project and Site Unit table in the sidebar to configure environmental summary
    fields.
  </p>
{/if}
{#if fieldListEnabled && fieldListState}
  <SummaryVegetationFieldListSection
    {fieldListState}
    presentationReady={!!presentationView?.saved && !presentationInvalid}
    {fieldListEnabledFromPresentation}
    {fieldListPeerDisabled}
    {fieldListPeerValidation}
    onDismissInitialReadError={onDismissInitialFieldListReadError}
    onLoadFieldList={onLoadFieldList}
    onCancelRead={onCancelFieldListRead}
    onStateChange={onFieldListStateChange}
  />
{/if}
{#if environmentalSession}
  <SummaryVegetationEnvironmental
    session={environmentalSession}
    port={environmentalPort}
    numeric={environmentalNumericEnabled}
    lifeform={environmentalLifeformEnabled}
    operationHeld={operationHeldProp ||
      workbookHeld ||
      unavailableScope ||
      viewBusy ||
      fieldListHeld ||
      preferenceHeld ||
      preferenceInvalid ||
      !!viewDraftError ||
      qualityMutationHeld ||
      qualityUnavailable ||
      presentationMutationHeld ||
      presentationInvalid}
    onBusyChange={onEnvironmentalBusyChange}
  />
{/if}
<SummaryVegetationWorkbookPanel
  {owner}
  {calculation}
  {savedPresentation}
  onPreferencesLoaded={onWorkbookPreferencesLoaded}
  disabled={operationHeldProp ||
    environmentalHeld ||
    unavailableScope ||
    viewBusy ||
    fieldListHeld ||
    preferenceHeld ||
    preferenceInvalid ||
    !!viewDraftError ||
    qualityMutationHeld ||
    qualityUnavailable ||
    presentationMutationHeld ||
    presentationInvalid}
  onBusyChange={onWorkbookBusyChange}
/>

<style>
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
