<script lang="ts">
  import { Bell, Database, Search } from '@lucide/svelte';
  import type { StartupState } from '../../bindings/github.com/boostao/vpro/app';
  import { projectState, webMeta } from '../shared/state';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import Navigation from './Navigation.svelte';
  import type { ShellViewId } from './shellPlotOps';
  import type { ShellUiController } from './shellUiController.svelte';
  import WorkspaceStatusBanners from './WorkspaceStatusBanners.svelte';

  let {
    ui,
    view,
    editorEntryForm,
    startupFailure,
    siviAvailable,
    onNavigate,
    onOpenSivi,
    onOpenMetadata,
    onOpenCloudSync,
    onOpenAuthSignIn,
  }: {
    ui: ShellUiController;
    view: ShellViewId;
    editorEntryForm: 'fs882' | 'sivi' | 'fs882-twopage';
    startupFailure: StartupState | null;
    siviAvailable: boolean;
    onNavigate: (next: ShellViewId | 'fs882-twopage') => void;
    onOpenSivi: () => void;
    onOpenMetadata: () => void;
    onOpenCloudSync: () => void;
    onOpenAuthSignIn?: () => void;
  } = $props();

  const picturesAvailable = $derived(!IS_WEB_READONLY || ($webMeta?.picturesAvailable ?? true));
</script>

<header class="topbar">
  <div class="brand">
    <span class="brand-symbol" aria-hidden="true">
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="36 36 952 952" width="28" height="28" focusable="false">
        <defs>
          <linearGradient id="vpro-topbar-navy" x1="16%" y1="6%" x2="84%" y2="96%">
            <stop offset="0%" stop-color="#0B437A" />
            <stop offset="52%" stop-color="#003366" />
            <stop offset="100%" stop-color="#001D3A" />
          </linearGradient>
          <linearGradient id="vpro-topbar-shield" x1="50%" y1="0%" x2="50%" y2="100%">
            <stop offset="0%" stop-color="#2E8540" />
            <stop offset="56%" stop-color="#1E5128" />
            <stop offset="100%" stop-color="#13381B" />
          </linearGradient>
        </defs>
        <rect
          x="64"
          y="64"
          width="896"
          height="896"
          rx="196"
          ry="196"
          fill="url(#vpro-topbar-navy)"
          stroke="#38598A"
          stroke-width="16"
        />
        <path
          d="M512 162L216 286V512C216 681 342 827 512 864C682 827 808 681 808 512V286Z"
          fill="url(#vpro-topbar-shield)"
          stroke="#FCBA19"
          stroke-width="28"
          stroke-linejoin="round"
        />
        <path d="M488 614H536L542 754Q512 764 482 754Z" fill="#FCBA19" />
        <path d="M512 454L698 654Q512 618 326 654Z" fill="#FFFFFF" />
        <path d="M512 344L656 518Q512 488 368 518Z" fill="#FFFFFF" />
        <path d="M512 244L614 396Q512 372 410 396Z" fill="#FFFFFF" />
      </svg>
    </span>
    <span>VPro</span>
    <WorkspaceStatusBanners
      region="badge"
      buildMode={ui.buildMode}
      appVersion={ui.appVersion}
      shortBuildCommit={ui.shortBuildCommit}
      releaseChannel={ui.releaseChannel}
      startupFailed={startupFailure !== null}
      onopenabout={() => {
        ui.aboutModalOpen = true;
      }}
    />
  </div>
  <button
    class="context-toggle"
    type="button"
    data-workspace-toggle
    disabled={startupFailure !== null}
    aria-expanded={ui.contextExpanded}
    aria-controls="project-context"
    onclick={() => ui.toggleContextSidebar()}
  >
    {IS_WEB_READONLY ? 'Datasets' : 'Work Space'}
  </button>
  {#if !startupFailure}
    <Navigation
      {view}
      activeEntryForm={editorEntryForm}
      onnavigate={onNavigate}
      {siviAvailable}
      onopensivi={onOpenSivi}
      newSiviAvailable={IS_WEB_READONLY ? false : ui.newSiviAvailable}
      onopennewsivi={() => {
        if (!IS_WEB_READONLY) ui.newSiviModalOpen = true;
      }}
      metadataAvailable={ui.metadataAvailable}
      onopenmetadata={onOpenMetadata}
      onopencloudsync={IS_WEB_READONLY ? undefined : onOpenCloudSync}
      onopenauthsignin={IS_WEB_READONLY
        ? undefined
        : () => {
            if (onOpenAuthSignIn) onOpenAuthSignIn();
            else ui.authSignInOpen = true;
          }}
      onopenusersetup={IS_WEB_READONLY
        ? undefined
        : () => {
            ui.userSetupOpen = true;
          }}
      whatsNewUnreadCount={ui.whatsNewStatus?.unreadCount ?? 0}
      resetSampleAvailable={IS_WEB_READONLY ? false : ui.newSiviAvailable}
      releaseChannel={ui.releaseChannel}
      {picturesAvailable}
      onhelpaction={(action) => ui.handleHelpMenuAction(action)}
    />
  {/if}
  <div class="topbar-actions">
    <button
      type="button"
      class="cmd-trigger"
      disabled={startupFailure !== null}
      aria-label="Open Quick-Jump Command Palette (Ctrl+K)"
      title="Quick-Jump Command Palette (Ctrl+K)"
      data-command-palette-trigger
      onclick={() => {
        ui.commandPaletteOpen = true;
      }}
    >
      <Search size={14} aria-hidden="true" />
      <span class="cmd-trigger-label">Quick Jump</span>
      <kbd>Ctrl+K</kbd>
    </button>

    <button
      type="button"
      class="notif-bell"
      disabled={startupFailure !== null}
      aria-label={`Notification Center${ui.notifSnapshot.unreadCount > 0 ? ` (${ui.notifSnapshot.unreadCount} unread)` : ''}`}
      title="Open Notification Center"
      data-notification-bell
      onclick={() => {
        ui.notificationDrawerOpen = !ui.notificationDrawerOpen;
      }}
    >
      <Bell size={16} aria-hidden="true" />
      {#if ui.notifSnapshot.unreadCount > 0}
        <span
          class="notif-badge tabular-nums notif-badge-{ui.notifSnapshot.badgeSeverity === 'none'
            ? 'info'
            : ui.notifSnapshot.badgeSeverity}"
          data-notification-badge={ui.notifSnapshot.badgeSeverity}
        >
          {ui.notifSnapshot.unreadCount > 99 ? '99+' : ui.notifSnapshot.unreadCount}
        </span>
      {/if}
    </button>

    <div class="topbar-context">
      <Database size={15} strokeWidth={1.8} aria-hidden="true" />
      <span>{$projectState?.activeProject ?? 'No project'}</span>
    </div>
  </div>
</header>
