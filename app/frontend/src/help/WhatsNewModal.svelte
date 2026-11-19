<script lang="ts">
  import { untrack } from 'svelte';
  import { CheckCircle2, Newspaper, X } from '@lucide/svelte';
  import ModalDialogTrap from '../shared/ModalDialogTrap.svelte';
  import { defaultHelpPort, type HelpBackendPort, type WhatsNewStatus } from './helpSystem';

  let {
    open = false,
    initialStatus = null,
    helpPort = defaultHelpPort,
    onstatuschange,
    onclose,
  }: {
    open?: boolean;
    initialStatus?: WhatsNewStatus | null;
    helpPort?: HelpBackendPort;
    onstatuschange?: (status: WhatsNewStatus) => void;
    onclose: () => void;
  } = $props();

  let status = $state.raw<WhatsNewStatus | null>(untrack(() => initialStatus));
  let loading = $state(false);
  let acknowledging = $state(false);
  let error = $state('');
  let loadGen = 0;

  $effect(() => {
    const incoming = initialStatus;
    untrack(() => {
      if (incoming) status = incoming;
    });
  });

  $effect(() => {
    if (!open) return;
    untrack(() => {
      void refreshStatus();
    });
  });

  async function refreshStatus() {
    const gen = ++loadGen;
    loading = true;
    error = '';
    try {
      const fresh = await helpPort.getWhatsNewStatus();
      if (gen !== loadGen) return;
      status = fresh;
      onstatuschange?.(fresh);
    } catch (cause) {
      if (gen === loadGen) {
        error = `Release notes status could not be loaded: ${String(cause)}`;
      }
    } finally {
      if (gen === loadGen) {
        loading = false;
      }
    }
  }

  async function markLatestAsRead() {
    if (!status?.latestVersion || acknowledging) return;
    acknowledging = true;
    error = '';
    try {
      const updated = await helpPort.acknowledgeWhatsNew(status.latestVersion);
      status = updated;
      onstatuschange?.(updated);
    } catch (cause) {
      error = `Could not persist What's New acknowledgement: ${String(cause)}`;
    } finally {
      acknowledging = false;
    }
  }

  function isEntryUnread(index: number): boolean {
    if (!status) return false;
    return index < status.unreadCount;
  }

</script>

{#if open}
  <div class="fixed inset-0 z-50 flex items-center justify-center bg-vpro-ink/50 p-4" data-whats-new-modal>
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="whats-new-modal-title"
      class="flex max-h-[86vh] w-full max-w-2xl flex-col overflow-hidden rounded border border-vpro-border bg-white text-vpro-ink shadow-2xl"
    >
      <ModalDialogTrap onEscape={onclose} escapeDisabled={acknowledging} initialFocusSelector="[data-whats-new-close]" />
      <header class="flex items-center justify-between gap-3 border-b-[3px] border-b-vpro-gold bg-vpro-navy px-5 py-3.5 text-white">
        <div class="flex items-center gap-2.5">
          <Newspaper size={18} class="text-vpro-gold" />
          <div>
            <div class="font-mono text-[11px] uppercase tracking-wider text-vpro-gold">
              Release &amp; Standards Changelog
            </div>
            <h2 id="whats-new-modal-title" class="text-base font-semibold text-white">
              What's New in VPro
            </h2>
          </div>
        </div>
        <button
          type="button"
          aria-label="Close What's New"
          data-whats-new-close
          class="rounded border border-white/30 bg-white/10 p-1.5 text-white hover:bg-white/20"
          onclick={onclose}
        >
          <X size={16} />
        </button>
      </header>

      <div class="space-y-4 overflow-y-auto p-5 text-xs">
        {#if error}
          <p role="alert" class="rounded border border-vpro-error bg-red-50 p-2.5 text-vpro-error">{error}</p>
        {/if}

        {#if status}
          <div class="flex flex-wrap items-center justify-between gap-2 rounded border border-vpro-border bg-vpro-canvas p-3">
            <div>
              {#if status.hasUnread}
                <span class="font-semibold text-vpro-navy" data-whats-new-unread-banner>
                  {status.unreadCount} unread release update{status.unreadCount === 1 ? '' : 's'}
                  {status.lastSeenVersion ? ` since v${status.lastSeenVersion}` : ''}.
                </span>
              {:else}
                <span class="inline-flex items-center gap-1.5 font-medium text-vpro-success" data-whats-new-all-read>
                  <CheckCircle2 size={14} /> Up to date — acknowledged through v{status.latestVersion}.
                </span>
              {/if}
            </div>
            {#if status.hasUnread}
              <button
                type="button"
                data-whats-new-acknowledge
                disabled={acknowledging}
                class="inline-flex items-center gap-1.5 rounded bg-vpro-navy px-3 py-1.5 text-xs font-semibold text-white hover:bg-vpro-navy-dark disabled:opacity-50"
                onclick={() => void markLatestAsRead()}
              >
                <CheckCircle2 size={13} />
                {acknowledging ? 'Saving...' : `Mark v${status.latestVersion} as Read`}
              </button>
            {/if}
          </div>

          <div class="space-y-3">
            {#each status.entries as entry, index (entry.version)}
              <article
                data-whats-new-version={entry.version}
                class="space-y-2 rounded border p-3.5 {isEntryUnread(index) ? 'border-vpro-navy border-l-[4px] border-l-vpro-gold bg-vpro-warning-bg' : 'border-vpro-border bg-white'}"
              >
                <div class="flex flex-wrap items-center justify-between gap-2">
                  <div class="flex items-center gap-2">
                    <h3 class="font-mono text-sm font-bold text-vpro-navy">Version {entry.version}</h3>
                    <span class="rounded border border-vpro-border bg-vpro-canvas px-2 py-0.5 font-mono text-[10px] uppercase text-vpro-ink-secondary">
                      {entry.channel}
                    </span>
                    {#if isEntryUnread(index)}
                      <span class="rounded bg-vpro-gold px-2 py-0.5 font-mono text-[10px] font-bold uppercase text-vpro-navy">
                        Unread
                      </span>
                    {/if}
                  </div>
                  <span class="font-mono text-[11px] text-vpro-ink-secondary">{entry.date}</span>
                </div>

                <ul class="list-disc space-y-1.5 pl-4 text-xs leading-relaxed text-vpro-ink">
                  {#each entry.highlights as item}
                    <li>{item}</li>
                  {/each}
                </ul>
              </article>
            {/each}
          </div>
        {:else if loading}
          <p role="status" class="text-vpro-ink-secondary">Loading release changelog...</p>
        {/if}
      </div>
    </div>
  </div>
{/if}
