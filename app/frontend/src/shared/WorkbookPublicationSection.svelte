<script lang="ts">
  import { untrack, type Snippet } from 'svelte';
  import { notifications } from '../shell/notificationService.svelte';

  interface WorkbookPublicationSnapshot {
    busy: boolean;
    blocked: boolean;
    requestedDestination: string;
    error?: string;
    outcome?: {
      status: string;
      path: string;
      sha256: string;
      errorMessage?: string;
    } | null;
  }

  let {
    sectionAttr,
    ariaLabel,
    heading,
    sourceName,
    contextTag,
    publication,
    destinationFallback = '',
    reviewError = '',
    draftError = '',
    unknownAttr,
    unknownMessageSuffix = 'before acknowledging; never repeat the destination blindly.',
    acknowledgeAttr,
    onAcknowledge,
    guidance = '',
    children,
    footer,
  }: {
    sectionAttr: string;
    ariaLabel: string;
    heading: string;
    sourceName: string;
    contextTag?: string;
    publication: WorkbookPublicationSnapshot;
    destinationFallback?: string;
    reviewError?: string;
    draftError?: string;
    unknownAttr: string;
    unknownMessageSuffix?: string;
    acknowledgeAttr: string;
    onAcknowledge: () => void;
    guidance?: string;
    children: Snippet;
    footer?: Snippet;
  } = $props();

  let lastPubKey = '';
  let lastReviewError = '';

  function syncNotifications(
    settled: WorkbookPublicationSnapshot,
    revErr: string,
    destFallback: string,
    ctx: string | undefined,
  ) {
    if (typeof notifications === 'undefined') return;
    const tag = ctx || undefined;
    if (revErr && revErr !== lastReviewError) {
      notifications.error(`${sourceName} workbook review failed`, revErr, {
        category: 'reports',
        source: sourceName,
        contextTag: tag,
      });
    }
    lastReviewError = revErr;

    if (settled.busy) {
      lastPubKey = '';
      return;
    }
    if (!settled.outcome && !settled.error) return;
    const key = JSON.stringify([
      settled.outcome?.status ?? '',
      settled.outcome?.path ?? '',
      settled.outcome?.sha256 ?? '',
      settled.error ?? '',
      settled.requestedDestination ?? '',
    ]);
    if (key === lastPubKey) return;
    lastPubKey = key;
    if (settled.outcome?.status === 'published' && !settled.error) {
      const exportedPath = settled.outcome.path || settled.requestedDestination || destFallback;
      notifications.success(`${sourceName} workbook exported`, exportedPath, {
        category: 'reports',
        source: sourceName,
        contextTag: tag,
      });
    } else if (settled.error || settled.outcome) {
      notifications.error(
        `${sourceName} workbook export failed`,
        settled.error || `Publication ${settled.outcome?.status ?? 'failed'} for ${settled.requestedDestination || destFallback}`,
        {
          category: 'reports',
          source: sourceName,
          contextTag: tag,
        },
      );
    }
  }

  untrack(() => syncNotifications(publication, reviewError, destinationFallback, contextTag));

  $effect(() => {
    const pub = publication;
    const revErr = reviewError;
    const dest = destinationFallback;
    const ctx = contextTag;
    untrack(() => syncNotifications(pub, revErr, dest, ctx));
  });
</script>

<section class="workbook-shell" {...{ [sectionAttr]: '' }} aria-label={ariaLabel}>
  <h2>{heading}</h2>
  {#if draftError}
    <p role="alert" class="alert-text">{draftError}</p>
  {/if}
  {#if !publication.outcome && publication.requestedDestination && !publication.busy}
    <p {...{ [unknownAttr]: '' }} role="alert" class="alert-text">
      Workbook outcome unknown. Retain and inspect {publication.requestedDestination} {unknownMessageSuffix}
    </p>
  {/if}
  {#if publication.blocked && !publication.busy}
    <button {...{ [acknowledgeAttr]: '' }} onclick={onAcknowledge}>Acknowledge workbook outcome</button>
  {/if}

  {@render children()}

  {#if guidance}
    <p class="guidance">{guidance}</p>
  {/if}
  {#if footer}
    {@render footer()}
  {/if}
</section>

<style>
  .workbook-shell {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 0.75rem;
    min-width: 0;
    overflow-wrap: anywhere;
    padding: 1rem;
    background: var(--vpro-surface);
    border: 1px solid var(--vpro-border);
    border-radius: 0.5rem;
    color: var(--vpro-ink);
  }
  h2 {
    margin: 0;
    color: var(--vpro-navy);
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
  .alert-text {
    color: var(--vpro-error);
  }
  .guidance {
    margin: 0;
    font-size: 0.875rem;
    color: var(--vpro-ink-secondary);
  }
</style>
