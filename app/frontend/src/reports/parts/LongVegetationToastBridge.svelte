<script lang="ts">
  import { untrack } from 'svelte';
  import { notifications } from '../../shell/notificationService.svelte';

  type PubLike = {
    outcome?: { status: string; path: string; sha256: string } | null;
    error?: string;
    requestedDestination: string;
  };
  type ReceiptViewLike = {
    receipts?: Array<{
      kind: string;
      outcome?: { committed: boolean; changed: boolean; errorMessage: string };
      errorMessage?: string;
    }>;
    error?: string;
  } | null;

  let {
    publication,
    projectView,
    preferenceView,
    statisticsView,
    destination,
    resolveContextTag,
    onSyncApi,
  }: {
    publication: PubLike | null | undefined;
    projectView: { error?: string; publication?: PubLike | null } | null | undefined;
    preferenceView: ReceiptViewLike;
    statisticsView: ReceiptViewLike;
    destination: string;
    resolveContextTag: () => string | undefined;
    onSyncApi?: (api: {
      syncWorkbook: () => void;
      syncProject: () => void;
      syncPreference: () => void;
      syncStatistics: () => void;
    }) => void;
  } = $props();

  let prefCount = 0;
  let lastPrefErr = '';
  let statCount = 0;
  let lastStatErr = '';
  let lastPubKey = '';
  let lastProjErr = '';
  let lastProjPubKey = '';

  const pubKeyOf = (p: PubLike | null | undefined) =>
    !p
      ? ''
      : p.outcome
        ? `outcome:${p.outcome.status}:${p.requestedDestination}:${p.outcome.path}:${p.outcome.sha256}:${p.error ?? ''}`
        : p.error
          ? `error:${p.error}:${p.requestedDestination}`
          : '';

  function emitWorkbookToast(p: PubLike | null | undefined, ctxTag: string | undefined) {
    if (!p) return;
    const opts = { category: 'reports' as const, source: 'Long Vegetation', contextTag: ctxTag };
    if (p.outcome?.status === 'published' && !p.error) {
      notifications.success(
        'Long Vegetation workbook exported',
        p.outcome.path || p.requestedDestination || destination,
        opts
      );
    } else if (p.error || p.outcome) {
      notifications.error(
        'Long Vegetation workbook export failed',
        p.error || `Publication ${p.outcome?.status ?? 'failed'} for ${p.requestedDestination || destination}`,
        opts
      );
    }
  }

  function syncWorkbook() {
    const pub = publication;
    const key = pubKeyOf(pub);
    if (!key) {
      lastPubKey = '';
      return;
    }
    if (key === lastPubKey) return;
    lastPubKey = key;
    emitWorkbookToast(pub, resolveContextTag());
  }

  function syncProject() {
    const pv = projectView;
    if (!pv) {
      lastProjErr = '';
      lastProjPubKey = '';
      return;
    }
    const ctxTag = resolveContextTag();
    const err = pv.error ?? '';
    if (err && err !== lastProjErr) {
      notifications.error('Long Vegetation project report failed', err, {
        category: 'reports',
        source: 'Long Vegetation',
        contextTag: ctxTag,
      });
    }
    lastProjErr = err;
    const key = pubKeyOf(pv.publication);
    if (!key) {
      lastProjPubKey = '';
      return;
    }
    if (key === lastProjPubKey) return;
    lastProjPubKey = key;
    emitWorkbookToast(pv.publication, ctxTag);
  }

  function syncReceipts(
    v: ReceiptViewLike,
    cnt: number,
    prevErr: string,
    labels: [string, string, string, string, string, string, string, string]
  ): [number, string] {
    if (!v) return [cnt, prevErr];
    const list = v.receipts ?? [];
    const start = list.length < cnt ? 0 : cnt;
    const opts = { category: 'reports' as const, source: 'Long Vegetation', contextTag: resolveContextTag() };
    let nextErr = prevErr;
    for (let i = start; i < list.length; i++) {
      const r = list[i];
      if (r.kind === 'known' && r.outcome) {
        if (r.outcome.committed && !r.outcome.errorMessage) {
          notifications.success(labels[0], r.outcome.changed ? labels[1] : labels[2], opts);
        } else if (r.outcome.committed) {
          notifications.warning(labels[3], r.outcome.errorMessage, opts);
          nextErr = r.outcome.errorMessage;
        } else if (r.outcome.errorMessage) {
          notifications.error(labels[4], r.outcome.errorMessage, opts);
          nextErr = r.outcome.errorMessage;
        } else {
          notifications.info(labels[5], labels[6], opts);
        }
      }
    }
    const curErr = v.error ?? '';
    if (curErr && curErr !== nextErr) notifications.error(labels[7], curErr, opts);
    return [list.length, curErr];
  }

  function syncPreference() {
    [prefCount, lastPrefErr] = syncReceipts(preferenceView, prefCount, lastPrefErr, [
      'Long Vegetation title saved',
      'Saved report title preference.',
      'No title changes.',
      'Long Vegetation title saved with warning',
      'Long Vegetation title save failed',
      'Long Vegetation title unchanged',
      'No title preference changes were needed.',
      'Long Vegetation title preference failed',
    ]);
  }

  function syncStatistics() {
    [statCount, lastStatErr] = syncReceipts(statisticsView, statCount, lastStatErr, [
      'Long Vegetation Average/Order saved',
      'Saved Average/Order preferences.',
      'No Average/Order changes.',
      'Long Vegetation Average/Order saved with warning',
      'Long Vegetation Average/Order save failed',
      'Long Vegetation Average/Order unchanged',
      'No Average/Order changes were needed.',
      'Long Vegetation Average/Order preference failed',
    ]);
  }

  untrack(() => {
    syncWorkbook();
    syncPreference();
    syncStatistics();
    syncProject();
    onSyncApi?.({ syncWorkbook, syncProject, syncPreference, syncStatistics });
  });

  $effect(() => {
    void publication;
    untrack(syncWorkbook);
  });
  $effect(() => {
    void projectView;
    untrack(syncProject);
  });
  $effect(() => {
    void preferenceView;
    untrack(syncPreference);
  });
  $effect(() => {
    void statisticsView;
    untrack(syncStatistics);
  });
</script>
