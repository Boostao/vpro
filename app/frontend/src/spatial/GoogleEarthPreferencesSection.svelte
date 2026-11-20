<script lang="ts">
  import type { GoogleEarthPreferencesView } from './googleEarthPreferences';

  let {
    preferences,
    locked = false,
    onLoadPreferences,
    onSavePreferences,
    onUndoPreferences,
    onAcknowledgePreferences,
  }: {
    preferences: GoogleEarthPreferencesView | null;
    locked?: boolean;
    onLoadPreferences: () => void;
    onSavePreferences: () => void;
    onUndoPreferences: () => void;
    onAcknowledgePreferences: () => void;
  } = $props();
</script>

{#if preferences?.draftError}
  <p class="error" role="alert" data-google-earth-preferences-draft-error>{preferences.draftError}</p>
{/if}
{#if preferences}
  <section data-google-earth-preferences aria-label="Reviewed Google Earth preferences">
    <div class="actions">
      <button type="button" data-google-earth-preferences-load disabled={locked} onclick={onLoadPreferences}>
        Load saved preferences (apply to live fields)
      </button>
      <button
        type="button"
        data-google-earth-preferences-save
        disabled={locked || !preferences.saved || !!preferences.draftError}
        onclick={onSavePreferences}
      >
        Save reviewed preferences
      </button>
      <button
        type="button"
        data-google-earth-preferences-undo
        disabled={locked || !preferences.saved}
        onclick={onUndoPreferences}
      >
        Undo preference draft
      </button>
    </div>
    {#if preferences.blocked && !preferences.busy}
      <div data-google-earth-preferences-outcome>
        {#if !preferences.outcome}
          <p role="alert">
            Preference save outcome is unknown. Do not replay; acknowledge and explicitly reload saved preferences
            before another save.
          </p>
        {:else}
          <p role="status">Preference save attempt requires acknowledgement before continuing.</p>
        {/if}
        <button
          type="button"
          data-google-earth-preferences-acknowledge
          disabled={preferences.busy || !preferences.blocked}
          onclick={onAcknowledgePreferences}
        >
          Acknowledge preference outcome
        </button>
      </div>
    {/if}
  </section>
{/if}

<style>
  .actions {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.75rem;
    margin: 0.75rem 0;
  }
  button {
    border: 1px solid var(--vpro-navy);
    border-radius: 0.25rem;
    padding: 0.4rem 0.6rem;
    min-width: 0;
    background: var(--vpro-surface);
    color: var(--vpro-navy);
    font-weight: 600;
  }
  button:disabled {
    opacity: 0.5;
  }
  p {
    overflow-wrap: anywhere;
  }
  .error {
    color: var(--vpro-error);
  }
</style>
