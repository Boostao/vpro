<script lang="ts">
  import { VegetationReportService } from '../../../bindings/github.com/boostao/vpro/app';
  import { formatError, type ReadRequests } from '../../shared/readRequests';
  import type { longVegetationPreferencesSession } from '../longVegetationPreferences';
  import type { longVegetationStatisticsPreferencesSession } from '../longVegetationStatisticsPreferences';

  type TitleSession = NonNullable<ReturnType<typeof longVegetationPreferencesSession>>;
  type StatsSession = NonNullable<ReturnType<typeof longVegetationStatisticsPreferencesSession>>;

  export interface TitleStatsHolds {
    busy: boolean;
    operationHeld: boolean;
    workbookBarrier: boolean;
    preferenceBarrier: boolean;
    unitBarrier: boolean;
    unitMutationHeld: boolean;
    titleBarrier: boolean;
    statisticsBarrier: boolean;
    peerPreferenceBarriers: boolean;
    peerMutationHeld: boolean;
    acknowledgePeerHeld: boolean;
  }

  export interface TitleStatsCallbacks {
    reads: ReadRequests;
    onBeginRead: () => number;
    onEndRead: (req: number) => void;
    onCancelParent: () => number;
    onSyncPreferenceToast: () => void;
    onSyncStatisticsToast: () => void;
    onError: (toastTitle: string, message: string) => void;
  }

  let {
    contextId,
    preferences,
    preferenceView,
    statistics,
    statisticsView,
    holds,
    callbacks: cb,
  }: {
    contextId: string;
    preferences: TitleSession | null;
    preferenceView: ReturnType<TitleSession['view']> | null;
    statistics: StatsSession | null;
    statisticsView: ReturnType<StatsSession['view']> | null;
    holds: TitleStatsHolds;
    callbacks: TitleStatsCallbacks;
  } = $props();

  let latestReq = 0;

  async function loadSavedTitle() {
    const peerHeld =
      holds.unitBarrier ||
      holds.busy ||
      holds.operationHeld ||
      holds.workbookBarrier ||
      holds.statisticsBarrier ||
      holds.peerPreferenceBarriers;
    if (!preferences || peerHeld || preferenceView?.busy || preferenceView?.blocked) return;
    const req = cb.onBeginRead();
    latestReq = req;
    const token = preferences.beginLoad();
    try {
      const val = await cb.reads.track(VegetationReportService.GetLongVegetationPreferences(contextId));
      if (req === latestReq) preferences.applyLoaded(val, token);
    } catch (c) {
      if (req === latestReq) {
        cb.onError(
          'Long Vegetation title load failed',
          `Saved title unavailable; no defaults applied: ${formatError(c)}`
        );
      }
    } finally {
      cb.onEndRead(req);
    }
  }

  async function saveTitle() {
    if (!preferences || holds.busy || holds.operationHeld || holds.workbookBarrier || holds.preferenceBarrier) return;
    const req = cb.onCancelParent();
    latestReq = req;
    try {
      await preferences.save((v) =>
        VegetationReportService.SaveLongVegetationPreferences(contextId, JSON.stringify(v))
      );
      cb.onSyncPreferenceToast();
    } catch (c) {
      if (req === latestReq) cb.onError('Long Vegetation title save failed', formatError(c));
    }
  }

  function editTitle(value: string) {
    if (!preferences || holds.unitMutationHeld) return;
    latestReq = cb.onCancelParent();
    preferences.edit(value);
  }

  async function loadSavedStatistics() {
    const peerHeld =
      holds.unitBarrier ||
      holds.busy ||
      holds.operationHeld ||
      holds.workbookBarrier ||
      holds.titleBarrier ||
      holds.peerPreferenceBarriers;
    if (!statistics || peerHeld || statisticsView?.busy || statisticsView?.blocked) return;
    const req = cb.onBeginRead();
    latestReq = req;
    const token = statistics.beginLoad();
    try {
      const val = await cb.reads.track(VegetationReportService.GetLongVegetationStatisticsPreferences(contextId));
      if (req === latestReq) statistics.applyLoaded(val, token);
    } catch (c) {
      if (req === latestReq) {
        cb.onError(
          'Long Vegetation statistics load failed',
          `Saved Average/Order choices unavailable; no defaults applied: ${formatError(c)}`
        );
      }
    } finally {
      cb.onEndRead(req);
    }
  }

  async function saveStatistics() {
    if (!statistics || holds.busy || holds.operationHeld || holds.workbookBarrier || holds.preferenceBarrier) return;
    const req = cb.onCancelParent();
    latestReq = req;
    try {
      await statistics.save((v) =>
        VegetationReportService.SaveLongVegetationStatisticsPreferences(contextId, JSON.stringify(v))
      );
      cb.onSyncStatisticsToast();
    } catch (c) {
      if (req === latestReq) cb.onError('Long Vegetation statistics save failed', formatError(c));
    }
  }

  function editAverage(value: string) {
    if (!statistics || holds.unitMutationHeld) return;
    latestReq = cb.onCancelParent();
    statistics.editAverage(value);
  }

  function editOrder(value: string) {
    if (!statistics || holds.unitMutationHeld) return;
    latestReq = cb.onCancelParent();
    statistics.editOrder(value);
  }
</script>

{#if preferences && preferenceView}
  <section class="preferences" aria-label="Saved Long Vegetation title">
    <label for="long-vegetation-title">Report Title</label>
    <textarea
      id="long-vegetation-title"
      data-source-control="rptLvTitle"
      rows="2"
      value={preferenceView.draft.title}
      aria-invalid={!!preferenceView.draftError}
      disabled={holds.unitMutationHeld ||
        holds.busy ||
        holds.operationHeld ||
        holds.workbookBarrier ||
        holds.peerMutationHeld ||
        !!statisticsView?.busy ||
        !!statisticsView?.blocked ||
        preferenceView.busy ||
        preferenceView.blocked ||
        !preferenceView.initialized}
      oninput={(event) => editTitle(event.currentTarget.value)}></textarea>
    <div class="actions">
      <button
        data-long-vegetation-preferences-load
        disabled={holds.unitBarrier ||
          holds.busy ||
          holds.operationHeld ||
          holds.workbookBarrier ||
          holds.statisticsBarrier ||
          holds.peerPreferenceBarriers ||
          preferenceView.busy ||
          preferenceView.blocked}
        onclick={loadSavedTitle}
      >
        Load saved title
      </button>
      <button
        data-long-vegetation-preferences-save
        disabled={holds.busy ||
          holds.operationHeld ||
          holds.workbookBarrier ||
          holds.preferenceBarrier ||
          !preferenceView.saved}
        onclick={saveTitle}
      >
        Save title preferences
      </button>
      <button
        data-long-vegetation-preferences-undo
        disabled={holds.unitMutationHeld ||
          holds.busy ||
          holds.operationHeld ||
          holds.workbookBarrier ||
          holds.peerMutationHeld ||
          !!statisticsView?.busy ||
          !!statisticsView?.blocked ||
          preferenceView.busy ||
          preferenceView.blocked ||
          !preferenceView.saved}
        onclick={() => {
          latestReq = cb.onCancelParent();
          preferences.undo();
        }}
      >
        Undo title draft
      </button>
      {#if preferenceView.blocked && !preferenceView.busy}
        <button
          data-long-vegetation-preferences-acknowledge
          disabled={holds.unitMutationHeld ||
            holds.busy ||
            holds.operationHeld ||
            holds.workbookBarrier ||
            holds.acknowledgePeerHeld}
          onclick={() => preferences.acknowledge()}
        >
          Acknowledge title preference outcome
        </button>
      {/if}
    </div>
    {#each preferenceView.receipts as receipt}
      {#if receipt.kind !== 'known'}
        <p data-long-vegetation-preferences-receipt role="alert">
          Preference receipt: outcome unknown; changed unknown; committed unknown. {receipt.errorMessage}
        </p>
      {/if}
    {/each}
    <p class="guidance">
      Unsaved edits do not change report output. Save your title, then reload report options to apply changes. If a save
      is interrupted, reload the saved title before saving again. Project data and audit history are untouched.
    </p>
  </section>
{/if}

{#if statistics && statisticsView}
  <section class="preferences" aria-label="Saved Long Vegetation Average and Order">
    <label for="long-vegetation-average">Calculate</label>
    <select
      id="long-vegetation-average"
      data-source-control="rptLvAvgType"
      value={statisticsView.draft.avgType}
      aria-invalid={!!statisticsView.draftError}
      disabled={holds.unitMutationHeld ||
        holds.busy ||
        holds.operationHeld ||
        holds.workbookBarrier ||
        holds.peerMutationHeld ||
        !!preferenceView?.busy ||
        !!preferenceView?.blocked ||
        statisticsView.busy ||
        statisticsView.blocked ||
        !statisticsView.initialized}
      onchange={(event) => editAverage(event.currentTarget.value)}
    >
      <option value="" disabled>Load saved Average</option>
      <option value="10">By n Plots</option>
      <option value="20">Characteristic</option>
    </select>
    <label for="long-vegetation-order">Order by</label>
    <select
      id="long-vegetation-order"
      data-source-control="rptLvOrderBy"
      value={statisticsView.draft.orderBy}
      aria-invalid={!!statisticsView.draftError}
      disabled={holds.unitMutationHeld ||
        holds.busy ||
        holds.operationHeld ||
        holds.workbookBarrier ||
        holds.peerMutationHeld ||
        !!preferenceView?.busy ||
        !!preferenceView?.blocked ||
        statisticsView.busy ||
        statisticsView.blocked ||
        !statisticsView.initialized}
      onchange={(event) => editOrder(event.currentTarget.value)}
    >
      <option value="" disabled>Load saved Order by</option>
      <option value="10">Species</option>
      <option value="20">Presence</option>
    </select>
    <div class="actions">
      <button
        data-long-vegetation-statistics-load
        disabled={holds.unitBarrier ||
          holds.busy ||
          holds.operationHeld ||
          holds.workbookBarrier ||
          holds.titleBarrier ||
          holds.peerPreferenceBarriers ||
          statisticsView.busy ||
          statisticsView.blocked}
        onclick={loadSavedStatistics}
      >
        Load saved Average/Order
      </button>
      <button
        data-long-vegetation-statistics-save
        disabled={holds.busy ||
          holds.operationHeld ||
          holds.workbookBarrier ||
          holds.preferenceBarrier ||
          !statisticsView.saved}
        onclick={saveStatistics}
      >
        Save Average/Order preferences
      </button>
      <button
        data-long-vegetation-statistics-undo
        disabled={holds.unitMutationHeld ||
          holds.busy ||
          holds.operationHeld ||
          holds.workbookBarrier ||
          holds.peerMutationHeld ||
          !!preferenceView?.busy ||
          !!preferenceView?.blocked ||
          statisticsView.busy ||
          statisticsView.blocked ||
          !statisticsView.saved}
        onclick={() => {
          latestReq = cb.onCancelParent();
          statistics.undo();
        }}
      >
        Undo Average/Order draft
      </button>
      {#if statisticsView.blocked && !statisticsView.busy}
        <button
          data-long-vegetation-statistics-acknowledge
          disabled={holds.unitMutationHeld ||
            holds.busy ||
            holds.operationHeld ||
            holds.workbookBarrier ||
            holds.acknowledgePeerHeld}
          onclick={() => statistics?.acknowledge()}
        >
          Acknowledge Average/Order outcome
        </button>
      {/if}
    </div>
    {#each statisticsView.receipts as receipt}
      {#if receipt.kind !== 'known'}
        <p data-long-vegetation-statistics-receipt role="alert">
          Preference receipt: outcome unknown; changed unknown; committed unknown. {receipt.errorMessage}
        </p>
      {/if}
    {/each}
    <p class="guidance">
      Unsaved edits do not change report output. Save your selections, then reload report options to apply changes.
      Saving updates only Calculate and Order species by; project data and audit history are untouched.
    </p>
  </section>
{/if}

<style>
  .preferences {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 0.75rem;
    min-width: 0;
  }
  textarea,
  select {
    box-sizing: border-box;
    min-width: 0;
    border: 1px solid var(--vpro-border);
    border-radius: 0.4rem;
    padding: 0.6rem;
    width: 100%;
    background: var(--vpro-surface);
    color: var(--vpro-ink);
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    align-items: center;
  }
  button {
    border: 1px solid var(--vpro-navy);
    border-radius: 0.4rem;
    padding: 0.5rem 0.75rem;
    background: var(--vpro-surface);
    color: var(--vpro-navy);
    font-weight: 600;
    cursor: pointer;
  }
  button:hover:not(:disabled) {
    background: var(--vpro-canvas);
  }
  button:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
  .guidance {
    color: var(--vpro-ink-secondary);
    font-size: 0.875rem;
  }
</style>
