<script lang="ts">
  import { untrack } from 'svelte';
  import { AlertCircle, AlertTriangle, CheckCircle2, Info, X } from '@lucide/svelte';
  import { notifications, type NotificationStateSnapshot } from './notificationService.svelte';

  let { controller = notifications }: { controller?: typeof notifications } = $props();
  let notifState = $state<NotificationStateSnapshot>(untrack(() => controller.getSnapshot()));

  $effect(() => {
    const unsub = controller.subscribe((next) => {
      notifState = next;
    });
    return unsub;
  });
</script>

{#if notifState.toasts.length > 0}
  <section
    class="vpro-toast-region"
    aria-label="Workspace notifications"
    aria-live="polite"
    aria-relevant="additions text"
    data-notification-toast-host
  >
    {#each notifState.toasts as toast (toast.id)}
      <article
        class="vpro-toast vpro-toast-{toast.severity}"
        role={toast.severity === 'error' ? 'alert' : 'status'}
        data-toast-id={toast.id}
        data-toast-severity={toast.severity}
        onmouseenter={() => controller.pauseToast(toast.id)}
        onmouseleave={() => controller.resumeToast(toast.id)}
        onfocusin={() => controller.pauseToast(toast.id)}
        onfocusout={() => controller.resumeToast(toast.id)}
      >
        <div class="vpro-toast-icon" aria-hidden="true">
          {#if toast.severity === 'success'}
            <CheckCircle2 size={17} />
          {:else if toast.severity === 'error'}
            <AlertCircle size={17} />
          {:else if toast.severity === 'warning'}
            <AlertTriangle size={17} />
          {:else}
            <Info size={17} />
          {/if}
        </div>
        <div class="vpro-toast-body">
          <div class="vpro-toast-title-row">
            <strong class="vpro-toast-title">{toast.title}</strong>
            {#if toast.repeatCount > 1}
              <span class="vpro-toast-repeat tabular-nums">×{toast.repeatCount}</span>
            {/if}
          </div>
          {#if toast.message}
            <p class="vpro-toast-message">{toast.message}</p>
          {/if}
        </div>
        <button
          type="button"
          class="vpro-toast-close"
          aria-label={`Dismiss ${toast.title}`}
          onclick={() => controller.dismissToast(toast.id)}
        >
          <X size={14} />
        </button>
      </article>
    {/each}
  </section>
{/if}

<style>
  .vpro-toast-region {
    position: fixed;
    right: 1rem;
    bottom: 1rem;
    z-index: 70;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    width: min(24rem, calc(100vw - 1.5rem));
    pointer-events: none;
  }
  .vpro-toast {
    pointer-events: auto;
    display: grid;
    grid-template-columns: auto minmax(0, 1fr) auto;
    align-items: start;
    gap: 0.65rem;
    padding: 0.7rem 0.8rem;
    border-radius: var(--vpro-radius-md, 6px);
    background: var(--vpro-surface, #ffffff);
    border: 1px solid var(--vpro-border, #d1d5db);
    border-left-width: 4px;
    box-shadow: var(--vpro-shadow-md, 0 6px 18px rgba(0, 34, 68, 0.14));
    color: var(--vpro-ink, #313132);
    font-size: 0.8125rem;
    line-height: 1.4;
  }
  .vpro-toast-success {
    border-left-color: var(--vpro-success, #2e8540);
  }
  .vpro-toast-success .vpro-toast-icon {
    color: var(--vpro-success, #2e8540);
  }
  .vpro-toast-info {
    border-left-color: var(--vpro-info, #1a5a96);
  }
  .vpro-toast-info .vpro-toast-icon {
    color: var(--vpro-info, #1a5a96);
  }
  .vpro-toast-warning {
    border-left-color: var(--vpro-warning-border, #d99b26);
    background: var(--vpro-warning-bg, #fef6e0);
  }
  .vpro-toast-warning .vpro-toast-icon {
    color: var(--vpro-warning, #9a6700);
  }
  .vpro-toast-error {
    border-left-color: var(--vpro-error, #d8292f);
    background: var(--vpro-error-bg, #fbeaea);
  }
  .vpro-toast-error .vpro-toast-icon {
    color: var(--vpro-error, #d8292f);
  }
  .vpro-toast-icon {
    margin-top: 0.1rem;
  }
  .vpro-toast-body {
    min-width: 0;
  }
  .vpro-toast-title-row {
    display: flex;
    align-items: center;
    gap: 0.4rem;
  }
  .vpro-toast-title {
    font-weight: 700;
    color: var(--vpro-ink, #313132);
    overflow-wrap: anywhere;
  }
  .vpro-toast-repeat {
    font-family: var(--vpro-font-mono, monospace);
    font-size: 0.6875rem;
    font-weight: 600;
    padding: 0.05rem 0.35rem;
    border-radius: 999px;
    background: var(--vpro-navy-tint, #ebf1f8);
    color: var(--vpro-navy, #003366);
  }
  .vpro-toast-message {
    margin: 0.2rem 0 0;
    color: var(--vpro-ink-secondary, #4b5563);
    font-size: 0.75rem;
    overflow-wrap: anywhere;
  }
  .vpro-toast-close {
    display: inline-grid;
    place-items: center;
    width: 1.75rem;
    height: 1.75rem;
    border: 1px solid transparent;
    border-radius: var(--vpro-radius-sm, 4px);
    background: transparent;
    color: var(--vpro-ink-secondary, #4b5563);
  }
  .vpro-toast-close:hover {
    background: rgba(0, 51, 102, 0.08);
    color: var(--vpro-ink, #313132);
  }
  @media (pointer: coarse) {
    .vpro-toast-close {
      min-width: 44px;
      min-height: 44px;
    }
  }
  @media print {
    .vpro-toast-region {
      display: none !important;
    }
  }
</style>
