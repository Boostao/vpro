<script lang="ts">
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import type { SiteUnitActionBarHandlers, SiteUnitActionBarModel } from './siteUnitSummaryOps';

  let { model, handlers }: { model: SiteUnitActionBarModel; handlers: SiteUnitActionBarHandlers } = $props();
</script>

<p>
  Active unit scope:
  {model.siteUnitType === 1
    ? 'Selected Site Unit Table'
    : model.siteUnitType === 2
      ? 'Hierarchy (~) Breakpoints'
      : model.siteUnitType === 3
        ? 'Field-Derived Units'
        : 'not loaded'}.
</p>
{#if model.hasPreferences && !IS_WEB_READONLY}
  <div class="actions">
    <button
      data-summary-preferences-save
      disabled={model.busy ||
        model.workbookBusy ||
        model.speciesBarrier ||
        !!model.preferenceView?.busy ||
        !!model.preferenceView?.blocked ||
        !!model.preferenceView?.draftError ||
        !model.preferenceView?.saved ||
        !model.ready ||
        model.siteUnitType !== 1}
      onclick={handlers.onSavePreferences}
    >
      Save site-unit options
    </button>
    <button
      data-summary-preferences-undo
      disabled={model.workbookBusy ||
        !!model.preferenceView?.busy ||
        !!model.preferenceView?.blocked ||
        !model.preferenceView?.saved}
      onclick={handlers.onUndoPreferences}>Undo summary options</button
    >
    {#if model.siteUnitType !== 1}
      <button
        data-summary-preferences-normal
        disabled={model.workbookBusy ||
          !!model.preferenceView?.busy ||
          !!model.preferenceView?.blocked ||
          !model.preferenceView?.draft ||
          model.su === 'None'}
        onclick={handlers.onSelectNormalSU}>Select Site Unit Table</button
      >
    {/if}
    {#if model.preferenceView?.blocked}
      <button
        data-summary-preferences-acknowledge
        disabled={model.workbookBusy || !!model.preferenceView.busy}
        onclick={handlers.onAcknowledgePreferences}>Acknowledge summary preference outcome</button
      >
    {/if}
    {#if model.hasFullPreferences}
      <button
        data-summary-full-preferences-load
        disabled={model.workbookBusy || !!model.fullPreferenceView?.busy || !!model.fullPreferenceView?.blocked}
        onclick={handlers.onLoadFullPreferences}>Load all saved options</button
      >
      <button
        data-summary-full-preferences-save
        disabled={model.busy ||
          model.workbookBusy ||
          model.speciesBarrier ||
          !!model.fullPreferenceView?.busy ||
          !!model.fullPreferenceView?.blocked ||
          !!model.fullPreferenceView?.draftError ||
          !model.fullPreferenceView?.saved}
        onclick={handlers.onSaveFullPreferences}>Save all options</button
      >
      {#if model.fullPreferenceView?.blocked}
        <button
          data-summary-full-preferences-acknowledge
          disabled={model.workbookBusy || !!model.fullPreferenceView.busy}
          onclick={handlers.onAcknowledgeFullPreferences}>Acknowledge full preference outcome</button
        >
      {/if}
    {/if}
  </div>
{/if}
{#each model.preferenceView?.receipts ?? [] as receipt}
  {#if receipt.kind !== 'known'}
    <p data-summary-preferences-receipt data-summary-preferences-unknown-receipt role="alert">
      Preference save status is unknown; reload saved options before saving again. {receipt.errorMessage}
    </p>
  {/if}
{/each}
<p class="guidance">
  Summarizes site, vegetation, and soil attributes by Site Unit without changing plot records. Use Load and Save to
  manage your default calculation method, unit scope, and species list thresholds in VPro settings.
</p>

<style>
  .guidance {
    font-size: 0.9rem;
    margin: 0.4rem 0;
    color: var(--vpro-ink-secondary);
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 1rem;
    margin: 0.5rem 0;
    padding: 0.75rem;
    background: var(--vpro-surface);
    border: 1px solid var(--vpro-border);
    border-radius: 0.5rem;
    min-width: 0;
  }
  button {
    min-height: 2.5rem;
    border: 1px solid var(--vpro-navy);
    border-radius: 0.25rem;
    padding: 0.5rem 0.85rem;
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
    opacity: 0.5;
    cursor: not-allowed;
  }
</style>
