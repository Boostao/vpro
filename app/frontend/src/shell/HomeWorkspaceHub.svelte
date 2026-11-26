<script lang="ts">
  import { untrack } from 'svelte';
  import { CheckCircle2, Newspaper, ShieldCheck } from '@lucide/svelte';
  import {
    defaultHelpPort,
    formatShortCommit,
    type BuildMode,
    type HelpBackendPort,
    type WhatsNewStatus,
  } from '../help/helpSystem';
  import { IS_WEB_READONLY } from '../web/runtimeMode';

  let {
    whatsNewStatus = null,
    buildMode = '' as BuildMode,
    appVersion = '',
    gitCommit = '',
    releaseChannel = 'stable',
    helpPort = defaultHelpPort,
    onacknowledgewhatsnew,
    onhelpaction,
  }: {
    whatsNewStatus?: WhatsNewStatus | null;
    buildMode?: BuildMode;
    appVersion?: string;
    gitCommit?: string;
    releaseChannel?: string;
    helpPort?: HelpBackendPort;
    onacknowledgewhatsnew?: () => void | Promise<void>;
    onhelpaction?: (action: 'guide' | 'tours' | 'about') => void;
  } = $props();

  let loadedStatus = $state.raw<WhatsNewStatus | null>(null);
  let loading = $state(false);
  let acknowledging = $state(false);

  const shortCommit = $derived(formatShortCommit(gitCommit));
  const status = $derived(whatsNewStatus ?? loadedStatus);

  $effect(() => {
    if (whatsNewStatus || typeof helpPort?.getWhatsNewStatus !== 'function') return;
    untrack(() => {
      if (loadedStatus || loading) return;
      loading = true;
      void helpPort
        .getWhatsNewStatus()
        .then((fresh) => {
          loadedStatus = fresh;
        })
        .catch(() => {})
        .finally(() => {
          loading = false;
        });
    });
  });

  async function markLatestAsRead() {
    if (!status?.latestVersion || acknowledging) return;
    acknowledging = true;
    try {
      if (onacknowledgewhatsnew) {
        await onacknowledgewhatsnew();
      } else if (typeof helpPort?.acknowledgeWhatsNew === 'function') {
        loadedStatus = await helpPort.acknowledgeWhatsNew(status.latestVersion);
      }
    } finally {
      acknowledging = false;
    }
  }

  function isEntryUnread(index: number): boolean {
    if (!status) return false;
    return index < status.unreadCount;
  }
</script>

<div class="mx-auto max-w-3xl space-y-4 py-2" data-home-workspace-hub data-opening-whats-new>
  {#if !IS_WEB_READONLY && buildMode === 'alpha'}
    <section
      data-home-tier-banner="alpha"
      aria-label="Alpha Preview Evaluation Notice"
      class="rounded border border-vpro-navy border-l-[4px] border-l-vpro-gold bg-vpro-warning-bg p-3.5 text-xs text-vpro-ink"
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <div class="flex items-center gap-2 font-bold text-vpro-navy">
          <ShieldCheck size={16} class="text-vpro-navy" aria-hidden="true" />
          <span
            >VPro Alpha Preview{appVersion ? ` (v${appVersion})` : ''} — B.C. Ministry of Forests BEC Evaluation</span
          >
        </div>
        <a
          href="https://github.com/Boostao/vpro/issues"
          target="_blank"
          rel="noreferrer"
          class="rounded border border-vpro-navy bg-white px-2.5 py-1 font-semibold text-vpro-info hover:bg-vpro-navy-tint"
        >
          Report Feedback / Issue
        </a>
      </div>
      <p class="mt-1.5 leading-relaxed text-vpro-ink">
        Keep backup copies of archival databases before running bulk Access conversions or multi-project merges. Preview
        packages are unsigned — verify installer checksums against <code class="font-mono text-vpro-navy"
          >SHA256SUMS.txt</code
        >.
      </p>
    </section>
  {:else if buildMode === 'dev'}
    <section
      data-home-tier-banner="dev"
      aria-label="Local Developer Build Notice"
      class="flex flex-wrap items-center justify-between gap-2 rounded border border-vpro-border border-l-[4px] border-l-vpro-navy bg-vpro-surface-subtle px-3.5 py-2 font-mono text-[11px] text-vpro-ink-secondary"
    >
      <span>
        DEV BUILD · v{appVersion || '2.0.0-dev'}{shortCommit ? ` · ${shortCommit}` : ''} · channel={releaseChannel}
      </span>
      {#if onhelpaction}
        <button
          type="button"
          class="rounded border border-vpro-border bg-white px-2 py-0.5 font-sans text-[11px] font-semibold text-vpro-navy hover:bg-vpro-canvas"
          onclick={() => onhelpaction('about')}
        >
          Inspect Build &amp; Paths
        </button>
      {/if}
    </section>
  {/if}

  <section
    aria-labelledby="opening-whats-new-title"
    data-whats-new-opening
    class="overflow-hidden rounded border border-vpro-border bg-white shadow-xs"
  >
    <header
      class="flex flex-wrap items-center justify-between gap-3 border-b-[3px] border-b-vpro-gold bg-vpro-navy px-5 py-3.5 text-white"
    >
      <div class="flex items-center gap-2.5">
        <Newspaper size={18} class="text-vpro-gold" aria-hidden="true" />
        <div>
          <div class="font-mono text-[11px] uppercase tracking-wider text-vpro-gold">
            B.C. Biogeoclimatic Ecosystem Classification
          </div>
          <h1 id="opening-whats-new-title" class="text-base font-semibold text-white">What's New in VPro</h1>
        </div>
      </div>

      {#if status?.hasUnread}
        <button
          type="button"
          data-whats-new-acknowledge
          disabled={acknowledging}
          class="inline-flex items-center gap-1.5 rounded bg-vpro-gold px-3 py-1.5 text-xs font-bold text-vpro-navy hover:brightness-95 disabled:opacity-50"
          onclick={() => void markLatestAsRead()}
        >
          <CheckCircle2 size={14} aria-hidden="true" />
          <span>{acknowledging ? 'Saving…' : `Mark v${status.latestVersion} as Read`}</span>
        </button>
      {:else if status?.latestVersion}
        <span class="inline-flex items-center gap-1.5 font-mono text-[11px] text-white/90">
          <CheckCircle2 size={14} class="text-vpro-gold" aria-hidden="true" />
          <span>v{status.latestVersion}</span>
        </span>
      {/if}
    </header>

    <div class="space-y-3 p-5 text-xs">
      {#if status && status.entries.length > 0}
        {#if status.hasUnread}
          <p
            data-whats-new-banner
            class="rounded border border-vpro-navy/25 border-l-[4px] border-l-vpro-gold bg-vpro-warning-bg px-3.5 py-2 text-xs text-vpro-ink"
          >
            <strong class="font-semibold text-vpro-navy">What's New in VPro v{status.latestVersion}:</strong>
            <span>
              {status.unreadCount} unread release update{status.unreadCount === 1 ? '' : 's'} available.
            </span>
          </p>
        {/if}

        {#each status.entries as entry, index (entry.version)}
          <article
            data-whats-new-version={entry.version}
            class="space-y-2 rounded border p-3.5 {isEntryUnread(index)
              ? 'border-vpro-navy border-l-[4px] border-l-vpro-gold bg-vpro-warning-bg/60'
              : 'border-vpro-border bg-white'}"
          >
            <div class="flex flex-wrap items-center justify-between gap-2">
              <div class="flex items-center gap-2">
                <h2 class="font-mono text-sm font-bold text-vpro-navy">Version {entry.version}</h2>
                <span
                  class="rounded border border-vpro-border bg-vpro-canvas px-2 py-0.5 font-mono text-[10px] uppercase text-vpro-ink-secondary"
                >
                  {entry.channel}
                </span>
                {#if isEntryUnread(index)}
                  <span class="rounded bg-vpro-gold px-2 py-0.5 font-mono text-[10px] font-bold uppercase text-vpro-navy">
                    New
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
      {:else if loading}
        <p role="status" class="text-vpro-ink-secondary">Loading VPro release notes…</p>
      {:else}
        <p class="leading-relaxed text-vpro-ink-secondary">
          Select a Project, Site Unit, or Hierarchy in the <strong>Work Space</strong> panel on the left, then choose a
          workflow from <strong>Forms</strong>, <strong>Reports</strong>, <strong>Analysis</strong>,
          <strong>Project Management</strong>, <strong>Map</strong>, or <strong>Interchange</strong> above.
        </p>
      {/if}
    </div>
  </section>
</div>
