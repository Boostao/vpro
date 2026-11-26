<script lang="ts">
  import { ContextService, type StartupState } from '../../bindings/github.com/boostao/vpro/app';
  import type { ReadRequests } from '../shared/readRequests';
  import { projectState } from '../shared/state';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import NotificationHost from './NotificationHost.svelte';
  import { notifications } from './notificationService.svelte';
  import type { ShellViewId } from './shellPlotOps';
  import type { ShellUiController } from './shellUiController.svelte';

  let {
    ui,
    startupFailure,
    busy,
    editorBusy,
    companionPanelBusy,
    transitionWorking,
    workbenchDirty,
    plotCount = 0,
    stateReads,
    onNavigate,
    onRefresh,
  }: {
    ui: ShellUiController;
    startupFailure: StartupState | null;
    busy: boolean;
    editorBusy: boolean;
    companionPanelBusy: boolean;
    transitionWorking: boolean;
    workbenchDirty: boolean;
    plotCount?: number;
    stateReads: ReadRequests;
    onNavigate: (next: ShellViewId) => void;
    onRefresh: () => Promise<void>;
  } = $props();

  let tourAutoOpenedContext = $state(false);
</script>

{#if !IS_WEB_READONLY && ui.resetSampleConfirmOpen && !startupFailure}
  {#await import('./ResetSampleModal.svelte') then { default: ResetSampleModal }}
    <ResetSampleModal
      open={ui.resetSampleConfirmOpen && !startupFailure}
      {busy}
      {editorBusy}
      {companionPanelBusy}
      {transitionWorking}
      contextAvailable={!!$projectState?.contextId}
      onconfirm={() => void ui.confirmResetWorkspaceToSample()}
      onclose={() => {
        ui.resetSampleConfirmOpen = false;
      }}
    />
  {/await}
{/if}

{#if ui.helpDrawerOpen && !startupFailure}
  {#await import('../help/HelpDrawer.svelte') then { default: HelpDrawer }}
    <HelpDrawer
      open={ui.helpDrawerOpen}
      topicId={ui.helpDrawerTopicId}
      initialTab={ui.helpDrawerTab}
      onclose={() => {
        ui.helpDrawerOpen = false;
      }}
      onstarttour={(tid) => {
        ui.helpDrawerOpen = false;
        ui.tourInitialId = tid ?? null;
        ui.tourOpen = true;
      }}
    />
  {/await}
{/if}

{#if ui.tourOpen && !startupFailure}
  {#await import('../help/OnboardingTour.svelte') then { default: OnboardingTour }}
    <OnboardingTour
      open={ui.tourOpen}
      initialTourId={ui.tourInitialId}
      activeProject={$projectState?.activeProject ?? 'Sample'}
      onensurecontextopen={() => {
        if (!ui.contextExpanded) tourAutoOpenedContext = true;
        ui.contextExpanded = true;
      }}
      onrestorecontext={() => {
        if (tourAutoOpenedContext || ui.isNarrowViewport) {
          tourAutoOpenedContext = false;
          ui.contextExpanded = false;
        }
      }}
      onnavigateview={(nextView) => onNavigate(nextView as ShellViewId)}
      onresetsample={async () => {
        if (tourAutoOpenedContext || ui.isNarrowViewport) {
          tourAutoOpenedContext = false;
          ui.contextExpanded = false;
        }
        ui.tourOpen = false;
        ui.resetSampleConfirmOpen = true;
      }}
      onclose={() => {
        if (tourAutoOpenedContext || ui.isNarrowViewport) {
          tourAutoOpenedContext = false;
          ui.contextExpanded = false;
        }
        ui.tourOpen = false;
        ui.tourInitialId = null;
      }}
    />
  {/await}
{/if}

{#if ui.shortcutsModalOpen && !startupFailure}
  {#await import('../help/KeyboardShortcutsModal.svelte') then { default: KeyboardShortcutsModal }}
    <KeyboardShortcutsModal
      open={ui.shortcutsModalOpen}
      onclose={() => {
        ui.shortcutsModalOpen = false;
      }}
    />
  {/await}
{/if}

{#if ui.whatsNewModalOpen && !startupFailure}
  {#await import('../help/WhatsNewModal.svelte') then { default: WhatsNewModal }}
    <WhatsNewModal
      open={ui.whatsNewModalOpen}
      initialStatus={ui.whatsNewStatus}
      onstatuschange={(updated) => {
        ui.whatsNewStatus = updated;
      }}
      onclose={() => {
        ui.whatsNewModalOpen = false;
      }}
    />
  {/await}
{/if}

{#if ui.aboutModalOpen && !startupFailure}
  {#await import('../help/AboutVProModal.svelte') then { default: AboutVProModal }}
    <AboutVProModal
      open={ui.aboutModalOpen}
      onclose={() => {
        ui.aboutModalOpen = false;
      }}
    />
  {/await}
{/if}

{#if !IS_WEB_READONLY && ui.authSignInOpen && !startupFailure}
  {#await import('./AuthSignInModal.svelte') then { default: AuthSignInModal }}
    <AuthSignInModal
      open={ui.authSignInOpen}
      contextId={$projectState?.contextId ?? ''}
      activeProject={$projectState?.activeProject ?? ''}
      {plotCount}
      onclose={() => {
        ui.authSignInOpen = false;
      }}
    />
  {/await}
{/if}

{#if !IS_WEB_READONLY && ui.userSetupOpen && !startupFailure}
  {#await import('./UserSetupModal.svelte') then { default: UserSetupModal }}
    <UserSetupModal
      open={ui.userSetupOpen}
      contextId={$projectState?.contextId ?? ''}
      activeProject={$projectState?.activeProject ?? 'None'}
      onSaved={async () => {
        if (!editorBusy && !companionPanelBusy && !workbenchDirty) {
          await onRefresh();
        } else {
          const nextState = await stateReads.track(ContextService.GetState());
          projectState.set(nextState);
        }
      }}
      onclose={() => {
        ui.userSetupOpen = false;
      }}
    />
  {/await}
{/if}

{#if !startupFailure}
  {#if ui.commandPaletteOpen}
    {#await import('./CommandPalette.svelte') then { default: CommandPalette }}
      <CommandPalette
        open={ui.commandPaletteOpen}
        catalogInput={ui.commandCatalogInput}
        onselect={(action) => ui.handleCommandPaletteSelect(action)}
        onclose={() => {
          ui.commandPaletteOpen = false;
        }}
      />
    {/await}
  {/if}
  {#if ui.notificationDrawerOpen}
    {#await import('./NotificationDrawer.svelte') then { default: NotificationDrawer }}
      <NotificationDrawer
        open={ui.notificationDrawerOpen}
        controller={notifications}
        onclose={() => {
          ui.notificationDrawerOpen = false;
        }}
      />
    {/await}
  {/if}
{/if}

<NotificationHost controller={notifications} />
