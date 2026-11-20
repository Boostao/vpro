<script lang="ts">
  import type { ProjectInfo } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';

  let {
    externalProject = $bindable(''),
    externalPath = $bindable(''),
    externalDiscoveredProjects,
    busy,
    editorBusy,
    companionPanelBusy,
    transitionWorking,
    contextReady,
    onBrowseExternal,
    onAttachSubmit,
    onReveal,
  }: {
    externalProject: string;
    externalPath: string;
    externalDiscoveredProjects: ProjectInfo[];
    busy: boolean;
    editorBusy: boolean;
    companionPanelBusy: boolean;
    transitionWorking: boolean;
    contextReady: boolean;
    onBrowseExternal: () => void;
    onAttachSubmit: (event: SubmitEvent) => void;
    onReveal: (target: 'project' | 'root') => void;
  } = $props();

  const attachHeld = $derived(busy || editorBusy || companionPanelBusy || transitionWorking);
</script>

<details class="su-picker">
  <summary>Attach external VPro project (.db)</summary>
  <form onsubmit={onAttachSubmit}>
    <button type="button" id="browse-external-sqlite" disabled={attachHeld || !contextReady} onclick={onBrowseExternal}>
      Browse VPro project file (.db)…
    </button>
    {#if externalDiscoveredProjects.length > 1}
      <label for="external-project-select">DISCOVERED PROJECTS IN FILE</label>
      <select
        id="external-project-select"
        value={externalProject}
        onchange={(e) => {
          externalProject = (e.currentTarget as HTMLSelectElement).value;
        }}
        disabled={attachHeld}
      >
        {#each externalDiscoveredProjects as p (p.name)}
          <option value={p.name} disabled={!p.compatible}>{p.name}{!p.compatible ? ` (${p.version})` : ''}</option>
        {/each}
      </select>
    {/if}
    <label for="external-project">PROJECT PREFIX</label>
    <input id="external-project" bind:value={externalProject} required disabled={attachHeld} />
    <label for="external-path">FULL PROJECT FILE PATH (.DB)</label>
    <input id="external-path" bind:value={externalPath} required disabled={attachHeld} />
    <p>Attaching opens the VPro project file in place without copying it; edits write directly to the attached file.</p>
    <button type="submit" disabled={attachHeld}>Attach project</button>
  </form>
</details>

<div class="su-picker">
  <label for="reveal-explorer-btn">DATA ON DISK</label>
  <div class="grid gap-1.5">
    <button
      type="button"
      id="reveal-explorer-btn"
      class="px-2 py-1.5 border rounded bg-white text-xs text-left"
      disabled={busy || transitionWorking || !contextReady}
      onclick={() => onReveal('project')}
    >
      Reveal active project .db in File Explorer
    </button>
    <button
      type="button"
      id="reveal-root-explorer-btn"
      class="px-2 py-1.5 border rounded bg-white text-xs text-left"
      disabled={busy || transitionWorking || !contextReady}
      onclick={() => onReveal('root')}
    >
      Open VPRO DBs root folder in File Explorer
    </button>
  </div>
</div>
