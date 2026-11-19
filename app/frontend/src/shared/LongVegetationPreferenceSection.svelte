<script lang="ts">
  import { untrack, type Snippet } from 'svelte';
  import { notifications } from '../shell/notificationService.svelte';

  interface KnownOutcome {
    committed: boolean;
    changed: boolean;
    errorMessage: string;
  }

  interface ProjectReceiptRequestShape {
    revision: string;
    approvalHash: string;
    expected: { unitGroups: number };
    proposed: { unitGroups: number };
  }

  interface PreferenceReceiptItem {
    kind: string;
    errorMessage?: string;
    outcome?: KnownOutcome | { outcome: KnownOutcome };
    request?: unknown;
  }

  function extractKnownOutcome(raw: KnownOutcome | { outcome: KnownOutcome }): KnownOutcome {
    return 'outcome' in raw ? raw.outcome : raw;
  }

  function asProjectReceiptRequest(req: unknown): ProjectReceiptRequestShape | null {
    if (!req || typeof req !== 'object') return null;
    const candidate = req as Record<string, unknown>;
    if (typeof candidate.revision !== 'string' || typeof candidate.approvalHash !== 'string') return null;
    const expected = candidate.expected as { unitGroups?: unknown } | undefined;
    const proposed = candidate.proposed as { unitGroups?: unknown } | undefined;
    if (typeof expected?.unitGroups !== 'number' || typeof proposed?.unitGroups !== 'number') return null;
    return {
      revision: candidate.revision,
      approvalHash: candidate.approvalHash,
      expected: { unitGroups: expected.unitGroups },
      proposed: { unitGroups: proposed.unitGroups },
    };
  }

  interface StandardPrefView {
    busy: boolean;
    blocked: boolean;
    authorityUnknown?: boolean;
    draftError?: string;
    error?: string;
    saved?: unknown;
    receipts?: readonly PreferenceReceiptItem[];
  }

  interface StandardPrefSession {
    undo(): void;
    acknowledge(): void;
  }

  let {
    ariaLabel,
    sectionAttr,
    receiptAttr,
    actionPrefix,
    contextTag,
    titleBase,
    savedChangedMsg,
    savedNoChangeMsg,
    unchangedMsg,
    view = null,
    preferences = null,
    busy = false,
    operationHeld = false,
    mutationHeld = false,
    draftError,
    viewError,
    readError = '',
    extraError = '',
    extraErrorTitle = '',
    authorityUnknown,
    unknownOutcomeBanner = '',
    saveDisabled,
    undoDisabled,
    loadDisabled,
    acknowledgeVisible,
    acknowledgeDisabled,
    cancelVisible,
    cancelAttr = false,
    loadLabel,
    saveLabel,
    undoLabel,
    acknowledgeLabel,
    cancelLabel,
    guidance = '',
    receipts,
    formatSavedMessage,
    onload,
    onsave,
    onundo,
    onacknowledge,
    oncancel,
    children,
    afterActions,
  }: {
    ariaLabel: string;
    sectionAttr: string;
    receiptAttr: string;
    actionPrefix: string;
    contextTag?: string;
    titleBase: string;
    savedChangedMsg: string;
    savedNoChangeMsg: string;
    unchangedMsg: string;
    view?: StandardPrefView | null;
    preferences?: StandardPrefSession | null;
    busy?: boolean;
    operationHeld?: boolean;
    mutationHeld?: boolean;
    draftError?: string;
    viewError?: string;
    readError?: string;
    extraError?: string;
    extraErrorTitle?: string;
    authorityUnknown?: boolean;
    unknownOutcomeBanner?: string;
    saveDisabled?: boolean;
    undoDisabled?: boolean;
    loadDisabled?: boolean;
    acknowledgeVisible?: boolean;
    acknowledgeDisabled?: boolean;
    cancelVisible?: boolean;
    cancelAttr?: boolean;
    loadLabel: string;
    saveLabel: string;
    undoLabel: string;
    acknowledgeLabel: string;
    cancelLabel: string;
    guidance?: string;
    receipts?: readonly PreferenceReceiptItem[];
    formatSavedMessage?: (request: ProjectReceiptRequestShape | null, changed: boolean) => string;
    onload: () => void;
    onsave: () => void;
    onundo?: () => void;
    onacknowledge?: () => void;
    oncancel: () => void;
    children: Snippet;
    afterActions?: Snippet;
  } = $props();

  const resolvedDraftError = $derived(draftError ?? view?.draftError ?? '');
  const resolvedViewError = $derived(viewError ?? view?.error ?? '');
  const resolvedReceipts = $derived(receipts ?? view?.receipts ?? []);
  const resolvedAuthorityUnknown = $derived(authorityUnknown ?? Boolean(view?.authorityUnknown));
  const resolvedLoadDisabled = $derived(loadDisabled ?? Boolean(busy || operationHeld || view?.busy || view?.blocked));
  const resolvedSaveDisabled = $derived(
    saveDisabled ?? Boolean(busy || operationHeld || view?.busy || view?.blocked || view?.authorityUnknown || view?.draftError || !view?.saved)
  );
  const resolvedUndoDisabled = $derived(undoDisabled ?? Boolean(busy || mutationHeld || view?.busy || view?.blocked || !view?.saved));
  const resolvedAckVisible = $derived(acknowledgeVisible ?? Boolean(view?.blocked && !view?.busy));
  const resolvedAckDisabled = $derived(acknowledgeDisabled ?? Boolean(busy || mutationHeld));
  const resolvedCancelVisible = $derived(cancelVisible ?? busy);

  let notifiedReceipts = 0;
  let lastViewError = '';
  let lastReadError = '';
  let lastExtraError = '';

  function syncNotifications(
    nextReceipts: readonly PreferenceReceiptItem[],
    nextViewErr: string,
    nextReadErr: string,
    nextExtraErr: string,
    ctx: string | undefined,
  ) {
    if (typeof notifications === 'undefined') return;
    if (nextReceipts.length < notifiedReceipts) notifiedReceipts = 0;
    const tag = ctx || undefined;
    for (let i = notifiedReceipts; i < nextReceipts.length; i++) {
      const receipt = nextReceipts[i];
      if (receipt.kind === 'known' && receipt.outcome) {
        const outcome = extractKnownOutcome(receipt.outcome);
        if (outcome.committed && !outcome.errorMessage) {
          const msg = formatSavedMessage
            ? formatSavedMessage(asProjectReceiptRequest(receipt.request), outcome.changed)
            : outcome.changed
              ? savedChangedMsg
              : savedNoChangeMsg;
          notifications.success(`${titleBase} saved`, msg, {
            category: 'reports',
            source: 'Long Vegetation',
            contextTag: tag,
          });
        } else if (outcome.committed) {
          notifications.warning(`${titleBase} saved with warning`, outcome.errorMessage, {
            category: 'reports',
            source: 'Long Vegetation',
            contextTag: tag,
          });
          lastViewError = outcome.errorMessage;
        } else if (outcome.errorMessage) {
          notifications.error(`${titleBase} save failed`, outcome.errorMessage, {
            category: 'reports',
            source: 'Long Vegetation',
            contextTag: tag,
          });
          lastViewError = outcome.errorMessage;
        } else {
          notifications.info(`${titleBase} unchanged`, unchangedMsg, {
            category: 'reports',
            source: 'Long Vegetation',
            contextTag: tag,
          });
        }
      }
    }
    notifiedReceipts = nextReceipts.length;

    if (nextReadErr && nextReadErr !== lastReadError) {
      notifications.error(`${titleBase} load failed`, nextReadErr, {
        category: 'reports',
        source: 'Long Vegetation',
        contextTag: tag,
      });
    }
    lastReadError = nextReadErr;

    if (nextViewErr && nextViewErr !== lastViewError) {
      notifications.error(`${titleBase} preference failed`, nextViewErr, {
        category: 'reports',
        source: 'Long Vegetation',
        contextTag: tag,
      });
    }
    lastViewError = nextViewErr;

    if (nextExtraErr && nextExtraErr !== lastExtraError && extraErrorTitle) {
      notifications.error(extraErrorTitle, nextExtraErr, {
        category: 'reports',
        source: 'Long Vegetation',
        contextTag: tag,
      });
    }
    lastExtraError = nextExtraErr;
  }

  untrack(() => syncNotifications(resolvedReceipts, resolvedViewError, readError, extraError, contextTag));

  $effect(() => {
    const r = resolvedReceipts;
    const ve = resolvedViewError;
    const re = readError;
    const ee = extraError;
    const ct = contextTag;
    untrack(() => syncNotifications(r, ve, re, ee, ct));
  });

  function handleUndo() {
    if (onundo) onundo();
    else {
      oncancel();
      preferences?.undo();
    }
  }

  function handleAcknowledge() {
    if (onacknowledge) onacknowledge();
    else preferences?.acknowledge();
  }
</script>

<section class="lv-pref-section" aria-label={ariaLabel} {...{ [sectionAttr]: '' }}>
  {#if resolvedDraftError}
    <p class="error" role="alert">{resolvedDraftError}</p>
  {/if}
  {#if resolvedAuthorityUnknown && unknownOutcomeBanner}
    <p role="alert">{unknownOutcomeBanner}</p>
  {/if}
  {#each resolvedReceipts as receipt}
    {#if receipt.kind !== 'known'}
      {@const projReq = asProjectReceiptRequest(receipt.request)}
      {#if projReq}
        <div class="receipt" {...{ [receiptAttr]: '' }} role="alert">
          <p>
            Preference receipt for revision {projReq.revision}:
            expected {projReq.expected.unitGroups}; proposed {projReq.proposed.unitGroups}.
            Changed unknown; committed unknown. {receipt.errorMessage ?? ''}
          </p>
          <p>Approval: <code>{projReq.approvalHash}</code></p>
        </div>
      {:else}
        <p {...{ [receiptAttr]: '' }} role="alert">
          Preference receipt: outcome unknown; changed unknown; committed unknown. {receipt.errorMessage ?? ''}
        </p>
      {/if}
    {/if}
  {/each}

  {@render children()}

  <div class="actions">
    <button {...{ [`${actionPrefix}-load`]: '' }} disabled={resolvedLoadDisabled} onclick={onload}>
      {loadLabel}
    </button>
    <button {...{ [`${actionPrefix}-save`]: '' }} disabled={resolvedSaveDisabled} onclick={onsave}>
      {saveLabel}
    </button>
    <button {...{ [`${actionPrefix}-undo`]: '' }} disabled={resolvedUndoDisabled} onclick={handleUndo}>
      {undoLabel}
    </button>
    {#if resolvedAckVisible}
      <button {...{ [`${actionPrefix}-acknowledge`]: '' }} disabled={resolvedAckDisabled} onclick={handleAcknowledge}>
        {acknowledgeLabel}
      </button>
    {/if}
    {#if resolvedCancelVisible}
      <button {...(cancelAttr ? { [`${actionPrefix}-cancel`]: '' } : {})} onclick={oncancel}>
        {cancelLabel}
      </button>
    {/if}
  </div>

  {#if afterActions}
    {@render afterActions()}
  {/if}

  {#if guidance}
    <p class="guidance">{guidance}</p>
  {/if}
</section>

<style>
  .lv-pref-section {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 0.75rem;
    min-width: 0;
  }
  .receipt {
    min-width: 0;
  }
  p,
  code {
    overflow-wrap: anywhere;
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    align-items: center;
  }
  button {
    border: 1px solid var(--vpro-border);
    border-radius: 0.4rem;
    padding: 0.5rem 0.75rem;
    background: var(--vpro-surface);
  }
  button:disabled {
    opacity: 0.5;
  }
  .error {
    color: var(--vpro-error);
  }
  .guidance {
    color: var(--vpro-ink-secondary);
    font-size: 0.875rem;
  }
</style>
