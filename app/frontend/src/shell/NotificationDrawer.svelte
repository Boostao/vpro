<script lang="ts">
  import { untrack } from 'svelte';
  import { AlertCircle, AlertTriangle, Bell, CheckCheck, CheckCircle2, Info, Trash2, X } from '@lucide/svelte';
  import {
    filterNotificationEntries,
    notifications,
    type NotificationCategory,
    type NotificationFilter,
    type NotificationStateSnapshot,
  } from './notificationService.svelte';

  let {
    open = false,
    controller = notifications,
    onclose,
  }: {
    open?: boolean;
    controller?: typeof notifications;
    onclose: () => void;
  } = $props();

  let notifState = $state<NotificationStateSnapshot>(untrack(() => controller.getSnapshot()));
  let activeFilter = $state<NotificationFilter>('all');
  let closeBtn: HTMLButtonElement | undefined = $state();

  $effect(() => {
    const unsub = controller.subscribe((next) => {
      notifState = next;
    });
    return unsub;
  });

  $effect(() => {
    if (open && closeBtn) {
      closeBtn.focus();
    }
  });

  const filtered = $derived(filterNotificationEntries(notifState.entries, activeFilter));

  const filterTabs: { id: NotificationFilter; label: string }[] = [
    { id: 'all', label: 'All' },
    { id: 'errors', label: 'Errors' },
    { id: 'entry', label: 'Data Entry' },
    { id: 'lmh25', label: 'LMH25 & QC' },
    { id: 'reports', label: 'Reports & Exports' },
    { id: 'background', label: 'System & Sync' },
  ];

  function defaultCategorySource(category: NotificationCategory): string {
    switch (category) {
      case 'entry':
        return 'Data Entry';
      case 'lmh25':
        return 'LMH25 Rule';
      case 'reports':
        return 'Reports & Exports';
      case 'admin':
        return 'System & Admin';
      case 'background':
        return 'Background';
      default:
        return 'Workspace';
    }
  }

  function formatTimestamp(iso: string) {
    try {
      const d = new Date(iso);
      if (Number.isNaN(d.getTime())) return iso;
      return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    } catch {
      return iso;
    }
  }

  function handleWindowKeydown(event: KeyboardEvent) {
    if (!open) return;
    if (event.key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      onclose();
    }
  }
</script>

<svelte:window onkeydowncapture={handleWindowKeydown} />

{#if open}
  <div
    class="vpro-notif-backdrop"
    role="presentation"
    data-notification-drawer-backdrop
    onclick={(e) => {
      if (e.target === e.currentTarget) onclose();
    }}
  >
    <div
      class="vpro-notif-drawer"
      role="dialog"
      aria-modal="true"
      aria-labelledby="vpro-notif-drawer-title"
      data-notification-drawer
    >
      <header class="vpro-notif-header">
        <div class="vpro-notif-header-title">
          <Bell size={17} class="text-vpro-gold" />
          <div>
            <div class="vpro-notif-eyebrow">Session Activity &amp; Advisories</div>
            <h2 id="vpro-notif-drawer-title">Notification Center</h2>
          </div>
        </div>
        <button
          bind:this={closeBtn}
          type="button"
          class="vpro-notif-close"
          aria-label="Close Notification Center"
          data-notification-drawer-close
          onclick={onclose}
        >
          <X size={16} />
        </button>
      </header>

      <div class="vpro-notif-toolbar">
        <div class="vpro-notif-filters" role="tablist" aria-label="Filter notifications">
          {#each filterTabs as tab (tab.id)}
            <button
              type="button"
              role="tab"
              aria-selected={activeFilter === tab.id}
              class:active={activeFilter === tab.id}
              data-notification-filter={tab.id}
              onclick={() => (activeFilter = tab.id)}
            >
              {tab.label}
            </button>
          {/each}
        </div>
        <div class="vpro-notif-actions">
          <button
            type="button"
            disabled={notifState.unreadCount === 0}
            data-notification-mark-read
            onclick={() => controller.markAllRead()}
          >
            <CheckCheck size={13} /> Mark all read
          </button>
          <button
            type="button"
            disabled={notifState.entries.length === 0}
            data-notification-clear
            onclick={() => controller.clearHistory()}
          >
            <Trash2 size={13} /> Clear
          </button>
        </div>
      </div>

      <div class="vpro-notif-list" role={filtered.length > 0 ? 'list' : undefined}>
        {#if filtered.length === 0}
          <div class="vpro-notif-empty">
            <p class="font-semibold text-vpro-ink">No notifications in this view</p>
            <p class="mt-1 text-xs text-vpro-ink-secondary">
              Completed saves, exports, LMH25 pedon/edatopic advisories, R/Quarto jobs, and Access import logs appear
              here.
            </p>
          </div>
        {:else}
          {#each filtered as item (item.id)}
            <div
              role="listitem"
              class="vpro-notif-item vpro-notif-{item.severity}"
              class:unread={!item.read}
              data-notification-entry={item.id}
            >
              <button type="button" class="vpro-notif-item-main" onclick={() => controller.markRead(item.id)}>
                <div class="vpro-notif-item-icon" aria-hidden="true">
                  {#if item.severity === 'error'}
                    <AlertCircle size={16} />
                  {:else if item.severity === 'warning'}
                    <AlertTriangle size={16} />
                  {:else if item.severity === 'success'}
                    <CheckCircle2 size={16} />
                  {:else}
                    <Info size={16} />
                  {/if}
                </div>
                <div class="vpro-notif-item-content">
                  <div class="vpro-notif-item-meta">
                    <span class="vpro-notif-source-group">
                      <span class="vpro-notif-source">{item.source ?? defaultCategorySource(item.category)}</span>
                      {#if item.contextTag}
                        <span class="vpro-notif-context tabular-nums" data-notification-context>{item.contextTag}</span>
                      {/if}
                    </span>
                    <time class="vpro-notif-time tabular-nums" datetime={item.timestampIso}
                      >{formatTimestamp(item.timestampIso)}</time
                    >
                  </div>
                  <div class="vpro-notif-item-heading">
                    <strong>{item.title}</strong>
                    {#if item.repeatCount > 1}
                      <span class="vpro-notif-count tabular-nums">×{item.repeatCount}</span>
                    {/if}
                    {#if !item.read}
                      <span class="vpro-notif-unread-dot" aria-label="Unread"></span>
                    {/if}
                  </div>
                  {#if item.message}
                    <p>{item.message}</p>
                  {/if}
                </div>
              </button>
              {#if item.action}
                <div class="vpro-notif-item-footer">
                  <button
                    type="button"
                    class="vpro-notif-action-btn"
                    data-notification-action={item.id}
                    onclick={() => controller.triggerAction(item.id)}
                  >
                    {item.action.label}
                  </button>
                </div>
              {/if}
            </div>
          {/each}
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .vpro-notif-backdrop {
    position: fixed;
    inset: 0;
    z-index: 65;
    background: rgba(0, 22, 46, 0.36);
    display: flex;
    justify-content: flex-end;
  }
  .vpro-notif-drawer {
    width: min(27rem, 100vw);
    height: 100dvh;
    max-height: 100vh;
    background: var(--vpro-surface);
    border-left: 1px solid var(--vpro-border);
    box-shadow: var(--vpro-shadow-lg, 0 14px 34px rgba(0, 34, 68, 0.24));
    display: flex;
    flex-direction: column;
    min-height: 0;
  }
  .vpro-notif-header {
    background: var(--vpro-navy);
    color: var(--vpro-surface);
    border-bottom: 3px solid var(--vpro-gold);
    padding: 0.8rem 1rem;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.75rem;
  }
  .vpro-notif-header-title {
    display: flex;
    align-items: center;
    gap: 0.65rem;
  }
  .vpro-notif-eyebrow {
    font-family: var(--vpro-font-mono, monospace);
    font-size: 0.65rem;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--vpro-gold);
  }
  .vpro-notif-header h2 {
    margin: 0;
    font-size: 0.95rem;
    font-weight: 700;
    color: var(--vpro-surface);
  }
  .vpro-notif-close {
    display: inline-grid;
    place-items: center;
    width: 2rem;
    height: 2rem;
    border-radius: 4px;
    border: 1px solid rgba(255, 255, 255, 0.3);
    background: rgba(255, 255, 255, 0.1);
    color: var(--vpro-surface);
  }
  .vpro-notif-close:hover {
    background: rgba(255, 255, 255, 0.2);
  }
  .vpro-notif-toolbar {
    padding: 0.65rem 0.85rem;
    border-bottom: 1px solid var(--vpro-border);
    background: var(--vpro-surface-subtle);
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }
  .vpro-notif-filters {
    display: flex;
    flex-wrap: wrap;
    gap: 0.3rem;
  }
  .vpro-notif-filters button {
    padding: 0.3rem 0.55rem;
    border-radius: 4px;
    border: 1px solid var(--vpro-border);
    background: var(--vpro-surface);
    color: var(--vpro-ink-secondary);
    font-size: 0.72rem;
    font-weight: 600;
  }
  .vpro-notif-filters button.active {
    background: var(--vpro-navy);
    border-color: var(--vpro-navy);
    color: var(--vpro-surface);
  }
  .vpro-notif-actions {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: 0.5rem;
  }
  .vpro-notif-actions button {
    display: inline-flex;
    align-items: center;
    gap: 0.3rem;
    padding: 0.28rem 0.55rem;
    border-radius: 4px;
    border: 1px solid var(--vpro-border);
    background: var(--vpro-surface);
    color: var(--vpro-ink);
    font-size: 0.72rem;
  }
  .vpro-notif-actions button:disabled {
    opacity: 0.45;
  }
  .vpro-notif-list {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    padding: 0.75rem;
    display: flex;
    flex-direction: column;
    gap: 0.55rem;
  }
  .vpro-notif-empty {
    padding: 2.25rem 1.25rem;
    text-align: center;
    border: 1px dashed var(--vpro-border);
    border-radius: 6px;
    background: var(--vpro-surface-subtle);
  }
  .vpro-notif-item {
    width: 100%;
    display: flex;
    flex-direction: column;
    gap: 0.45rem;
    padding: 0.65rem 0.75rem;
    border-radius: 5px;
    border: 1px solid var(--vpro-border);
    border-left-width: 3px;
    background: var(--vpro-surface);
    font-size: 0.78rem;
  }
  .vpro-notif-item-main {
    width: 100%;
    text-align: left;
    display: grid;
    grid-template-columns: auto minmax(0, 1fr);
    gap: 0.6rem;
    padding: 0;
    border: 0;
    background: transparent;
    font: inherit;
    color: inherit;
    cursor: pointer;
  }
  .vpro-notif-item-main:focus-visible {
    outline: 2px solid var(--vpro-focus-ring);
    outline-offset: 2px;
    border-radius: 3px;
  }
  .vpro-notif-item.unread {
    background: var(--vpro-navy-tint);
  }
  .vpro-notif-error {
    border-left-color: var(--vpro-error);
  }
  .vpro-notif-error .vpro-notif-item-icon {
    color: var(--vpro-error);
  }
  .vpro-notif-warning {
    border-left-color: var(--vpro-warning-border);
  }
  .vpro-notif-warning .vpro-notif-item-icon {
    color: var(--vpro-warning);
  }
  .vpro-notif-success {
    border-left-color: var(--vpro-success);
  }
  .vpro-notif-success .vpro-notif-item-icon {
    color: var(--vpro-success);
  }
  .vpro-notif-info {
    border-left-color: var(--vpro-info);
  }
  .vpro-notif-info .vpro-notif-item-icon {
    color: var(--vpro-info);
  }
  .vpro-notif-item-meta {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.68rem;
    color: var(--vpro-ink-muted);
  }
  .vpro-notif-source-group {
    display: inline-flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 0.35rem;
    min-width: 0;
  }
  .vpro-notif-source {
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }
  .vpro-notif-context {
    font-family: var(--vpro-font-mono, monospace);
    font-size: 0.65rem;
    font-weight: 600;
    line-height: 1.3;
    padding: 0.05rem 0.35rem;
    border-radius: 999px;
    background: var(--vpro-navy-tint);
    border: 1px solid var(--vpro-info-border);
    color: var(--vpro-navy);
    text-transform: none;
    max-width: 100%;
    overflow-wrap: anywhere;
  }
  .vpro-notif-time {
    font-family: var(--vpro-font-mono, monospace);
    flex: none;
  }
  .vpro-notif-item-heading {
    display: flex;
    align-items: center;
    gap: 0.4rem;
    margin-top: 0.15rem;
    color: var(--vpro-ink);
  }
  .vpro-notif-count {
    font-family: var(--vpro-font-mono, monospace);
    font-size: 0.68rem;
    padding: 0.05rem 0.35rem;
    border-radius: 999px;
    background: var(--vpro-surface);
    border: 1px solid var(--vpro-border);
  }
  .vpro-notif-unread-dot {
    width: 7px;
    height: 7px;
    border-radius: 999px;
    background: var(--vpro-navy);
    flex: none;
  }
  .vpro-notif-item-content p {
    margin: 0.25rem 0 0;
    color: var(--vpro-ink-secondary);
    line-height: 1.4;
    overflow-wrap: anywhere;
  }
  .vpro-notif-item-footer {
    display: flex;
    justify-content: flex-start;
    padding-left: calc(16px + 0.6rem);
  }
  .vpro-notif-action-btn {
    display: inline-flex;
    align-items: center;
    gap: 0.25rem;
    padding: 0.22rem 0.55rem;
    border-radius: var(--vpro-radius-sm, 4px);
    border: 1px solid var(--vpro-navy);
    background: var(--vpro-surface);
    color: var(--vpro-navy);
    font-size: 0.72rem;
    font-weight: 600;
    cursor: pointer;
  }
  .vpro-notif-action-btn:hover {
    background: var(--vpro-navy);
    color: var(--vpro-surface);
  }
  .vpro-notif-action-btn:focus-visible {
    outline: 2px solid var(--vpro-focus-ring);
    outline-offset: 2px;
  }
  @media (pointer: coarse) {
    .vpro-notif-close,
    .vpro-notif-filters button,
    .vpro-notif-actions button,
    .vpro-notif-action-btn {
      min-height: 44px;
      padding: 0.5rem 0.75rem;
    }
  }
  @media print {
    .vpro-notif-backdrop {
      display: none !important;
    }
  }
</style>
