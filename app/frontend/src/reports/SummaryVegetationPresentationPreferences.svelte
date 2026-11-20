<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { ReadRequests, formatError, type CancellableRead } from '../shared/readRequests';
  import type {
    SummaryVegetationPresentationPreferencesReview,
    SummaryVegetationPresentationPreferencesSession,
  } from './summaryVegetationPresentationPreferences';
  import type { ReportTitlePreferencesOutcome } from './reportTitlePreferences';
  import { notifications } from '../shell/notificationService.svelte';

  let {
    contextId,
    preferences,
    port,
    operationHeld = false,
    mutationHeld = false,
    onReadBusyChange,
  }: {
    contextId: string;
    preferences: SummaryVegetationPresentationPreferencesSession;
    port: {
      read: (contextId: string) => CancellableRead<SummaryVegetationPresentationPreferencesReview | null>;
      save: (contextId: string, requestJSON: string) => PromiseLike<ReportTitlePreferencesOutcome | null>;
    };
    operationHeld?: boolean;
    mutationHeld?: boolean;
    onReadBusyChange: (busy: boolean) => void;
  } = $props();
  const flags = [
    { key: 'showCommon', control: 'rptSvShowCommon', label: 'Show english name' },
    { key: 'showGuide', control: 'optUseShortFieldGuideNames', label: 'Use short field guide names' },
    { key: 'includeEnv', control: 'optIncludeEnvFields', label: 'Include Environmental Fields?' },
    { key: 'createSummary', control: 'optCreateSummary', label: 'Create report summary' },
    { key: 'combineVariants', control: 'optCombineVariants', label: 'Treat subspecies/varieties as species?' },
    { key: 'constancy', control: 'optConstancyFormat', label: 'Use Constancy Format' },
  ] as const;
  let view = $state.raw(untrack(() => preferences.view()));
  let busy = $state(false);
  let error = $state('');
  const reads = new ReadRequests();
  let generation = 0;
  let lastReadError = '';
  let lastPrefError = '';
  let notifiedReceipts = 0;
  function syncPresentationNotifications() {
    const receipts = view.receipts ?? [];
    if (receipts.length < notifiedReceipts) notifiedReceipts = 0;
    for (let i = notifiedReceipts; i < receipts.length; i++) {
      const receipt = receipts[i];
      if (receipt.kind === 'known') {
        if (receipt.outcome.committed && !receipt.outcome.errorMessage) {
          notifications.success(
            'Summary presentation saved',
            receipt.outcome.changed ? 'Saved presentation preferences.' : 'No presentation changes.',
            {
              category: 'reports',
              source: 'Summary Vegetation',
            }
          );
        } else if (receipt.outcome.committed) {
          notifications.warning('Summary presentation saved with warning', receipt.outcome.errorMessage, {
            category: 'reports',
            source: 'Summary Vegetation',
          });
          lastPrefError = receipt.outcome.errorMessage;
        } else if (receipt.outcome.errorMessage) {
          notifications.error('Summary presentation save failed', receipt.outcome.errorMessage, {
            category: 'reports',
            source: 'Summary Vegetation',
          });
          lastPrefError = receipt.outcome.errorMessage;
        } else {
          notifications.info('Summary presentation unchanged', 'No presentation changes were needed.', {
            category: 'reports',
            source: 'Summary Vegetation',
          });
        }
      }
    }
    notifiedReceipts = receipts.length;
    const rErr = view.readError ?? '';
    if (rErr && rErr !== lastReadError) {
      notifications.error('Summary presentation load failed', rErr, {
        category: 'reports',
        source: 'Summary Vegetation',
      });
    }
    lastReadError = rErr;
    const vErr = view.error ?? '';
    if (vErr && vErr !== lastPrefError) {
      notifications.error('Summary presentation failed', vErr, {
        category: 'reports',
        source: 'Summary Vegetation',
      });
    }
    lastPrefError = vErr;
  }
  const unsubscribe = untrack(() =>
    preferences.subscribe(() => {
      view = preferences.view();
      syncPresentationNotifications();
    })
  );
  syncPresentationNotifications();
  function cancel() {
    generation++;
    reads.cancelAll();
    preferences.cancelLoad();
    busy = false;
    onReadBusyChange(false);
  }
  async function load() {
    if (busy || operationHeld || view.busy || view.blocked) return;
    cancel();
    const request = generation,
      token = preferences.beginLoad();
    error = '';
    busy = true;
    onReadBusyChange(true);
    try {
      const value = await reads.track(port.read(contextId));
      if (request !== generation) return;
      preferences.applyLoaded(value, token);
    } catch (cause) {
      if (request === generation) preferences.rejectRead(cause);
    } finally {
      if (request === generation) {
        busy = false;
        onReadBusyChange(false);
      }
    }
  }
  async function save() {
    if (
      busy ||
      operationHeld ||
      view.busy ||
      view.blocked ||
      view.authorityUnknown ||
      view.draftError ||
      view.readError
    )
      return;
    cancel();
    const request = generation;
    error = '';
    try {
      await preferences.save((value) => port.save(contextId, JSON.stringify(value)));
      if (typeof syncPresentationNotifications === 'function') {
        syncPresentationNotifications();
      } else {
        const current = preferences.view();
        const latest = current.receipts?.at(-1);
        if (latest?.kind === 'known') {
          if (latest.outcome.committed && !latest.outcome.errorMessage) {
            notifications.success(
              'Summary presentation saved',
              latest.outcome.changed ? 'Saved presentation preferences.' : 'No presentation changes.',
              {
                category: 'reports',
                source: 'Summary Vegetation',
              }
            );
          } else if (latest.outcome.committed) {
            notifications.warning('Summary presentation saved with warning', latest.outcome.errorMessage, {
              category: 'reports',
              source: 'Summary Vegetation',
            });
          } else if (latest.outcome.errorMessage) {
            notifications.error('Summary presentation save failed', latest.outcome.errorMessage, {
              category: 'reports',
              source: 'Summary Vegetation',
            });
          } else {
            notifications.info('Summary presentation unchanged', 'No presentation changes were needed.', {
              category: 'reports',
              source: 'Summary Vegetation',
            });
          }
        } else if (current.error) {
          notifications.error('Summary presentation failed', current.error, {
            category: 'reports',
            source: 'Summary Vegetation',
          });
        }
      }
    } catch (cause) {
      if (request === generation) {
        error = formatError(cause);
        notifications.error('Summary presentation save failed', error, {
          category: 'reports',
          source: 'Summary Vegetation',
        });
      }
    }
  }
  function editTitle(raw: string) {
    if (busy || mutationHeld || view.busy || view.blocked) return;
    cancel();
    error = '';
    preferences.editTitle(raw);
  }
  function editFlag(key: (typeof flags)[number]['key'] | 'hierarchyHeader', raw: boolean) {
    if (busy || mutationHeld || view.busy || view.blocked) return;
    cancel();
    error = '';
    try {
      preferences.editFlag(key, raw);
    } catch (cause) {
      error = formatError(cause);
      notifications.error('Summary presentation edit failed', error, {
        category: 'reports',
        source: 'Summary Vegetation',
      });
    }
  }
  onDestroy(() => {
    unsubscribe();
    cancel();
  });
</script>

<section
  class="summary-presentation"
  data-summary-presentation-preferences
  aria-label="Saved Summary presentation drafts"
>
  {#if view.draftError}<p class="error" role="alert">{view.draftError}</p>{/if}
  {#each view.receipts as receipt}
    {#if receipt.kind !== 'known'}
      <p data-summary-presentation-receipt role="alert">
        Preference receipt: outcome unknown; changed unknown; committed unknown. {receipt.errorMessage}
        Constancy preset applied: {String(receipt.request.constancyApplied)}.
      </p>
    {/if}
  {/each}
  <fieldset>
    <legend>Stored Summary presentation</legend>
    <label class="title" for="summary-presentation-title">
      <span>Report Title</span>
      <input
        id="summary-presentation-title"
        data-source-control="rptSvTitle"
        type="text"
        value={view.draft?.title ?? ''}
        aria-invalid={!!view.draftError}
        disabled={busy || mutationHeld || view.busy || view.blocked || !view.draft}
        oninput={(event) => {
          const raw = event.currentTarget.value;
          editTitle(raw);
        }}
      />
    </label>
    <div class="flags">
      {#each flags as field}
        <label for={'summary-presentation-' + field.key}>
          <input
            id={'summary-presentation-' + field.key}
            data-source-control={field.control}
            type="checkbox"
            checked={view.draft ? view.draft[field.key] : false}
            disabled={busy ||
              mutationHeld ||
              view.busy ||
              view.blocked ||
              !view.draft ||
              (field.key === 'showCommon' && view.draft.constancy)}
            onchange={(event) => {
              const raw = event.currentTarget.checked;
              editFlag(field.key, raw);
            }}
          />
          <span>{field.label}</span>
        </label>
      {/each}
      <label for="summary-presentation-hierarchyHeader">
        <input
          id="summary-presentation-hierarchyHeader"
          data-source-control="optIncludeHierarchyHeader"
          type="checkbox"
          checked={view.draft ? view.draft.hierarchyHeader : false}
          disabled={busy || mutationHeld || view.busy || view.blocked || !view.draft}
          onchange={(event) => {
            const raw = event.currentTarget.checked;
            editFlag('hierarchyHeader', raw);
          }}
        />
        <span>Include hierarchy header</span>
      </label>
    </div>
    {#if view.draft}
      <dl data-summary-presentation-callback>
        <div>
          <dt>Shared Group by</dt>
          <dd>{view.draft.groupBy}</dd>
        </div>
        <div>
          <dt>Shared Display</dt>
          <dd>{view.draft.display}</dd>
        </div>
        <div>
          <dt>Retained value limit</dt>
          <dd>{view.draft.valueLimit}</dd>
        </div>
        <div>
          <dt>Constancy preset staged</dt>
          <dd>{String(view.draft.constancyApplied)}</dd>
        </div>
      </dl>
    {/if}
  </fieldset>
  <div class="actions">
    <button data-summary-presentation-load disabled={busy || operationHeld || view.busy || view.blocked} onclick={load}
      >Load saved presentation</button
    >
    <button
      data-summary-presentation-save
      disabled={busy ||
        operationHeld ||
        view.busy ||
        view.blocked ||
        view.authorityUnknown ||
        !!view.draftError ||
        !!view.readError ||
        !view.saved}
      onclick={save}>Save presentation draft</button
    >
    <button
      data-summary-presentation-undo
      disabled={busy || mutationHeld || view.busy || view.blocked || !view.saved}
      onclick={() => {
        cancel();
        preferences.undo();
      }}>Undo presentation draft</button
    >
    {#if view.blocked && !view.busy}
      <button
        data-summary-presentation-acknowledge
        disabled={busy || mutationHeld}
        onclick={() => preferences.acknowledge()}>Acknowledge presentation outcome</button
      >
    {/if}
    {#if busy}<button data-summary-presentation-cancel onclick={cancel}>Cancel presentation read</button>{/if}
  </div>
  <p class="guidance">
    Load saved presentation settings before editing; unloaded controls do not show saved values. Enabling Use Constancy
    Format sets Group by Lifeform, Display Presence Class and Mean Cover, and turns off common names while keeping your
    value limit; turning Constancy off keeps those selections until you change them. Reload Summary options after saving
    a Constancy preset change. Workbook export below can preview your loaded Constancy selection before saving, while
    title and layout flags apply only where supported.
  </p>
</section>

<style>
  .summary-presentation {
    min-width: 0;
    margin: 0.75rem 0;
    color: var(--vpro-ink);
  }
  fieldset {
    min-width: 0;
    border: 1px solid var(--vpro-border);
    border-radius: 0.5rem;
    padding: 0.75rem;
    background: var(--vpro-surface);
  }
  legend {
    font-weight: 600;
    color: var(--vpro-navy);
  }
  .title {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 0.25rem;
  }
  .title input {
    width: 100%;
    min-width: 0;
    box-sizing: border-box;
    border: 1px solid var(--vpro-border);
    border-radius: 0.25rem;
    padding: 0.5rem;
    background: var(--vpro-surface);
    color: var(--vpro-ink);
  }
  .flags {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 0.5rem 1rem;
    margin-top: 0.75rem;
  }
  .flags label {
    display: flex;
    align-items: flex-start;
    gap: 0.5rem;
    min-width: 0;
    min-height: 2.75rem;
    overflow-wrap: anywhere;
  }
  .flags input {
    flex: none;
    margin-top: 0.25rem;
  }
  dl {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 0.5rem 1rem;
    margin-top: 0.75rem;
  }
  dl div {
    min-width: 0;
    overflow-wrap: anywhere;
  }
  dt {
    font-weight: 600;
    color: var(--vpro-navy);
  }
  dd {
    margin: 0;
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.5rem;
    margin-top: 0.5rem;
  }
  button {
    min-height: 2.75rem;
    max-width: 100%;
    padding: 0.5rem 0.75rem;
    border: 1px solid var(--vpro-navy);
    border-radius: 0.25rem;
    background: var(--vpro-surface);
    color: var(--vpro-navy);
    font-weight: 600;
  }
  button:disabled {
    opacity: 0.55;
  }
  .error {
    color: var(--vpro-error);
    overflow-wrap: anywhere;
    margin-bottom: 0.5rem;
    font-weight: 600;
  }
  .guidance {
    font-size: 0.875rem;
    margin-top: 0.75rem;
    overflow-wrap: anywhere;
    color: var(--vpro-ink-secondary);
  }
  @media (max-width: 640px) {
    .flags,
    dl {
      grid-template-columns: minmax(0, 1fr);
    }
  }
</style>
