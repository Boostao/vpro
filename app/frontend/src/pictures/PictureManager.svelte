<script module lang="ts">
  import { notifications } from '../shell/notificationService.svelte';
</script>

<script lang="ts">
  import { untrack } from 'svelte';
  import PicturePanel from './PicturePanel.svelte';
  import { plotLookupInputError } from '../shared/scopedPlotLookup';
  import { pictureMetadataSession } from './pictureMetadataSessions';
  import { pictureCreationSession } from './pictureCreationSessions';
  import PictureCreationPanel from './PictureCreationPanel.svelte';
  import { pictureLifecycleSession } from './pictureLifecycleSessions';
  import PictureLifecyclePanel from './PictureLifecyclePanel.svelte';

  let { contextId, project, initialPlot = '', onBusyChange }: {
    contextId: string; project: string; initialPlot?: string; onBusyChange: (busy: boolean) => void;
  } = $props();
  const startingPlot = untrack(() => initialPlot);
  let plot = $state(startingPlot);
  let selected = $state(startingPlot);
  let error = $state('');
  let busy = $state(false);
  const metadataWritingEnabled = true;
  const creationEnabled = true;
  const lifecycleEnabled = true;
  const lifecycleSession = $derived(lifecycleEnabled && selected && contextId && project
    ? pictureLifecycleSession({ contextId, project, plotNumber: selected }) : undefined);
  let lifecycleRevision = $state(0);
  $effect(() => lifecycleSession?.subscribe(() => untrack(() => lifecycleRevision++)));
  const lifecycleBlocked = $derived.by(() => {
    lifecycleRevision;
    const close = lifecycleSession?.closeState();
    return !!close && (close.busy || close.blocked || close.unsaved);
  });
  const creationSession = $derived(creationEnabled && selected && contextId && project
    ? pictureCreationSession({ contextId, project, plotNumber: selected }) : undefined);
  let creationRevision = $state(0);
  $effect(() => creationSession?.subscribe(() => untrack(() => creationRevision++)));
  const creationBlocked = $derived.by(() => {
    creationRevision;
    const close = creationSession?.closeState();
    return !!close && (close.busy || close.blocked || close.unsaved);
  });
  const metadataSession = $derived(metadataWritingEnabled && selected && contextId && project
    ? pictureMetadataSession({ contextId, project, plotNumber: selected }) : undefined);
  let metadataRevision = $state(0);
  const metadataBlocked = $derived.by(() => {
    metadataRevision;
    const close = metadataSession?.closeState();
    return !!close && (close.unsaved || close.busy || close.blocked === true);
  });
  $effect(() => metadataSession?.subscribe(() => untrack(() => metadataRevision++)));
  $effect(() => { onBusyChange(busy || metadataBlocked || creationBlocked || lifecycleBlocked); });

  function selectPlot() {
    const contextTag = selected ? `Plot ${selected}` : project || undefined;
    if (busy) {
      error = 'Wait for or cancel the current picture read before selecting another plot.';
      if (typeof notifications !== 'undefined') notifications.error('Plot selection blocked', error, { category: 'entry', source: 'Plot Pictures', contextTag });
      return;
    }
    if (metadataBlocked) {
      error = 'Finish or discard the retained picture metadata draft before selecting another plot.';
      if (typeof notifications !== 'undefined') notifications.error('Plot selection blocked', error, { category: 'entry', source: 'Plot Pictures', contextTag });
      return;
    }
    if (creationBlocked) {
      error = 'Resolve the retained picture selection or creation receipt before selecting another plot.';
      if (typeof notifications !== 'undefined') notifications.error('Plot selection blocked', error, { category: 'entry', source: 'Plot Pictures', contextTag });
      return;
    }
    if (lifecycleBlocked) {
      error = 'Finish the retained picture lifecycle review or acknowledge its receipt before selecting another plot.';
      if (typeof notifications !== 'undefined') notifications.error('Plot selection blocked', error, { category: 'entry', source: 'Plot Pictures', contextTag });
      return;
    }
    const invalid = plotLookupInputError(plot);
    if (invalid) {
      error = invalid;
      if (typeof notifications !== 'undefined') notifications.error('Invalid plot number', error, { category: 'entry', source: 'Plot Pictures', contextTag });
      return;
    }
    error = '';
    selected = plot;
    if (typeof notifications !== 'undefined') {
      notifications.info('Plot selected for pictures', `Selected plot ${plot}.`, { category: 'entry', source: 'Plot Pictures', contextTag: `Plot ${plot}` });
    }
  }
  function reading(value: boolean) {
    busy = value;
    onBusyChange(value || metadataBlocked || creationBlocked || lifecycleBlocked);
  }

  let optionsLoaded = $state(false);
  let optionsBusy = $state(false);
  let libraryPathDraft = $state('');
  let childDirDraft = $state('');
  let managerDirDraft = $state('');
  let activeLibraryPath = $state('');
  let activeManagerDir = $state('');
  let defaultLibraryHint = $state('');
  let defaultDirHint = $state('');

  async function loadPictureOptions() {
    if (optionsBusy) return;
    optionsBusy = true;
    try {
      const { Call } = await import('@wailsio/runtime');
      const current = await Call.ByName('main.PictureService.GetPictureOptions');
      if (current && typeof current === 'object') {
        libraryPathDraft = String(current.pictureLibraryPath ?? '');
        childDirDraft = String(current.childDirectory ?? '');
        managerDirDraft = String(current.managerDirectory ?? '');
        activeLibraryPath = String(current.effectiveLibraryPath ?? '');
        activeManagerDir = String(current.effectiveManagerDirectory ?? '');
        defaultLibraryHint = String(current.defaultLibraryPath ?? '');
        defaultDirHint = String(current.defaultImagesDirectory ?? '');
        optionsLoaded = true;
      }
    } catch (cause) {
      if (typeof notifications !== 'undefined') {
        notifications.error('Picture settings unavailable', String(cause), { category: 'entry', source: 'Plot Pictures' });
      }
    } finally {
      optionsBusy = false;
    }
  }

  async function savePictureOptionsFromManager(resetDefaults = false) {
    if (optionsBusy || busy || metadataBlocked || creationBlocked || lifecycleBlocked) return;
    optionsBusy = true;
    try {
      const payload = resetDefaults
        ? { pictureLibraryPath: '', childDirectory: '', managerDirectory: '' }
        : { pictureLibraryPath: libraryPathDraft, childDirectory: childDirDraft, managerDirectory: managerDirDraft };
      const { Call } = await import('@wailsio/runtime');
      const updated = await Call.ByName('main.PictureService.SavePictureOptions', payload);
      if (updated && typeof updated === 'object') {
        libraryPathDraft = String(updated.pictureLibraryPath ?? '');
        childDirDraft = String(updated.childDirectory ?? '');
        managerDirDraft = String(updated.managerDirectory ?? '');
        activeLibraryPath = String(updated.effectiveLibraryPath ?? '');
        activeManagerDir = String(updated.effectiveManagerDirectory ?? '');
        defaultLibraryHint = String(updated.defaultLibraryPath ?? '');
        defaultDirHint = String(updated.defaultImagesDirectory ?? '');
        optionsLoaded = true;
      }
      if (typeof notifications !== 'undefined') {
        notifications.success(
          'Picture library settings saved',
          resetDefaults ? 'Restored default workspace picture paths.' : 'Updated picture library and folder paths.',
          { category: 'entry', source: 'Plot Pictures' },
        );
      }
    } catch (cause) {
      if (typeof notifications !== 'undefined') {
        notifications.error('Picture library settings failed', String(cause), { category: 'entry', source: 'Plot Pictures' });
      }
    } finally {
      optionsBusy = false;
    }
  }
</script>

<section class="manager" data-picture-manager aria-label="Plot Pictures">
  <header class="sticky top-0 z-20 bg-white/95 backdrop-blur-xs py-2 border-b border-stone-200" data-workbench-sticky-bar>
    <h1>Plot Pictures</h1>
    <p>Project <strong>{project}</strong>. Enter an exact plot number to view, attach, edit, or manage linked plot photos.</p>
    <form onsubmit={event => { event.preventDefault(); selectPlot(); }}>
      <label for="picture-manager-plot">Plot number
        <input id="picture-manager-plot" bind:value={plot} disabled={busy || metadataBlocked || creationBlocked || lifecycleBlocked} />
      </label>
      <button type="submit" disabled={busy || metadataBlocked || creationBlocked || lifecycleBlocked}>Select exact plot</button>
    </form>
  </header>
  <details
    class="library-options"
    data-picture-manager-options
    ontoggle={event => {
      if (event.currentTarget.open && !optionsLoaded) void loadPictureOptions();
    }}
  >
    <summary>Picture library &amp; folder settings</summary>
    <form
      class="options-form"
      onsubmit={event => {
        event.preventDefault();
        void savePictureOptionsFromManager(false);
      }}
    >
      <label for="picture-manager-library-path">Picture Library File (VPics.db)
        <input
          id="picture-manager-library-path"
          bind:value={libraryPathDraft}
          placeholder={defaultLibraryHint || 'Default workspace pics/VPics.db'}
          disabled={optionsBusy || busy || metadataBlocked || creationBlocked || lifecycleBlocked}
        />
      </label>
      <label for="picture-manager-child-dir">Plot Entry Image Folder
        <input
          id="picture-manager-child-dir"
          bind:value={childDirDraft}
          placeholder={defaultDirHint || 'Default workspace pics/images'}
          disabled={optionsBusy || busy || metadataBlocked || creationBlocked || lifecycleBlocked}
        />
      </label>
      <label for="picture-manager-dir">Plot Pictures Manager Folder
        <input
          id="picture-manager-dir"
          bind:value={managerDirDraft}
          placeholder={defaultDirHint || 'Default workspace pics/images'}
          disabled={optionsBusy || busy || metadataBlocked || creationBlocked || lifecycleBlocked}
        />
      </label>
      <div class="options-actions">
        <button
          type="button"
          disabled={optionsBusy || busy || metadataBlocked || creationBlocked || lifecycleBlocked}
          onclick={() => void savePictureOptionsFromManager(true)}
        >Use Workspace Defaults</button>
        <button
          type="submit"
          disabled={optionsBusy || busy || metadataBlocked || creationBlocked || lifecycleBlocked}
        >{optionsBusy ? 'Saving…' : 'Save Picture Paths'}</button>
      </div>
    </form>
    {#if activeLibraryPath}
      <p class="guidance">Active library: {activeLibraryPath}{activeManagerDir ? ` — Active folder: ${activeManagerDir}` : ''}</p>
    {/if}
  </details>
  {#if selected}
    <p data-picture-manager-parent>Selected plot: {JSON.stringify(selected)}</p>
    {#key selected}
      {#if creationSession}<PictureCreationPanel session={creationSession} disabled={busy || metadataBlocked || lifecycleBlocked} />{/if}
      {#if lifecycleSession}<PictureLifecyclePanel session={lifecycleSession} disabled={busy || metadataBlocked || creationBlocked} />{/if}
      <PicturePanel {contextId} {project} plotNumber={selected} view="manager" onBusyChange={reading} {metadataSession}
        disabled={creationBlocked} />
    {/key}
  {/if}
  <p class="guidance">Plot photos are linked by PlotNumber across the whole project without Site Unit or profile filtering.
    Selecting a plot or loading previews never modifies plot records or image files on disk.
    {#if !creationEnabled}Adding pictures is unavailable in this session.{/if}
    {#if !metadataWritingEnabled}Editing picture metadata is unavailable in this session.{/if}
    {#if !lifecycleEnabled}Deleting or restoring picture links is unavailable in this session.{/if}</p>
</section>

<style>
  .manager { padding: 1rem; min-width: 0; max-width: 100%; }
  h1 { font-size: 1.5rem; font-weight: 600; color: #003366; margin-bottom: .75rem; }
  form { display: flex; flex-wrap: wrap; align-items: end; gap: .75rem; margin: .75rem 0; }
  label { display: grid; gap: .3rem; min-width: 0; flex: 1 1 14rem; }
  input, button { border: 1px solid #9F9F9F; border-radius: .25rem; padding: .4rem .6rem; min-width: 0; color: #313132; background: #FFFFFF; }
  button:disabled, input:disabled { opacity: .5; }
  p { overflow-wrap: anywhere; }
  .guidance { font-size: .8rem; color: #474543; margin-top: 1rem; }
  .library-options { margin: .75rem 0; padding: .65rem .75rem; border: 1px solid #D8D8D8; border-radius: .25rem; background: #FFFFFF; }
  .library-options summary { cursor: pointer; font-weight: 600; color: #003366; }
  .options-form { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(16rem, 100%), 1fr)); gap: .75rem; margin-top: .75rem; }
  .options-actions { display: flex; flex-wrap: wrap; align-items: end; gap: .5rem; }
</style>
