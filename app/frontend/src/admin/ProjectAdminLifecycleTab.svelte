<script lang="ts">
  import type {
    ExportSplinterResult,
    NewProjectResult,
    ProjectMetadataPreset,
    SaveProjectAsResult,
  } from './projectAdminWorkbench';

  export interface LifecycleViewMeta {
    busy: boolean;
    activeProject: string;
    activeSu: string;
    availablePresets: ProjectMetadataPreset[];
    selectedNewProjPreset: ProjectMetadataPreset | null;
    newProjIdTruncationWarning: string | null;
    newProjValidationError: string | null;
    saveAsValidationError: string | null;
    splinterValidationError: string | null;
    newProjResult: NewProjectResult | null;
    saveAsResult: SaveProjectAsResult | null;
    splinterResult: ExportSplinterResult | null;
  }

  let {
    meta,
    newProjName = $bindable(''),
    newProjId = $bindable(''),
    newProjTitle = $bindable(''),
    newProjPreset = $bindable('LMH25_2023_FS882'),
    newProjDest = $bindable(''),
    newProjActivate = $bindable(false),
    saveAsName = $bindable(''),
    saveAsDest = $bindable(''),
    saveAsActivate = $bindable(false),
    splinterName = $bindable(''),
    splinterDest = $bindable(''),
    splinterUseSu = $bindable(true),
    splinterUnitsRaw = $bindable(''),
    splinterPlotsRaw = $bindable(''),
    splinterActivate = $bindable(false),
    onsubmitnewproject,
    onsubmitsaveas,
    onsubmitsplinter,
  }: {
    meta: LifecycleViewMeta;
    newProjName?: string;
    newProjId?: string;
    newProjTitle?: string;
    newProjPreset?: string;
    newProjDest?: string;
    newProjActivate?: boolean;
    saveAsName?: string;
    saveAsDest?: string;
    saveAsActivate?: boolean;
    splinterName?: string;
    splinterDest?: string;
    splinterUseSu?: boolean;
    splinterUnitsRaw?: string;
    splinterPlotsRaw?: string;
    splinterActivate?: boolean;
    onsubmitnewproject: () => void;
    onsubmitsaveas: () => void;
    onsubmitsplinter: () => void;
  } = $props();
</script>

<div class="grid grid-cols-1 gap-4 lg:grid-cols-3">
  <fieldset class="space-y-3 rounded border border-vpro-border border-t-[3px] border-t-vpro-gold p-4">
    <legend class="px-1 text-sm font-semibold text-vpro-navy">Create New VPro Project</legend>
    <div class="space-y-1">
      <label class="block text-xs font-semibold text-vpro-ink-secondary" for="new-project-name">
        Project Name (A-Z, 0-9, _, max 31)
      </label>
      <input
        id="new-project-name"
        type="text"
        class="w-full rounded border border-vpro-border p-2 text-sm"
        bind:value={newProjName}
        disabled={meta.busy}
        aria-invalid={!!meta.newProjValidationError}
      />
    </div>
    <div class="space-y-1">
      <label class="block text-xs font-semibold text-vpro-ink-secondary" for="new-project-id">
        Metadata ProjectID (optional, max 20)
      </label>
      <input
        id="new-project-id"
        type="text"
        class="w-full rounded border border-vpro-border p-2 text-sm"
        bind:value={newProjId}
        disabled={meta.busy}
      />
    </div>
    <div class="space-y-1">
      <label class="block text-xs font-semibold text-vpro-ink-secondary" for="new-project-title">
        Project Title (optional)
      </label>
      <input
        id="new-project-title"
        type="text"
        class="w-full rounded border border-vpro-border p-2 text-sm"
        bind:value={newProjTitle}
        disabled={meta.busy}
      />
    </div>
    <div class="space-y-1">
      <label class="block text-xs font-semibold text-vpro-ink" for="new-project-preset">Standards Preset</label>
      <select
        id="new-project-preset"
        class="w-full rounded border border-vpro-border-strong p-2 text-sm"
        bind:value={newProjPreset}
        disabled={meta.busy}
      >
        {#each meta.availablePresets as preset (preset.id)}
          <option value={preset.id}>{preset.label}</option>
        {/each}
        <option value="">None (Blank Metadata)</option>
      </select>
      {#if meta.selectedNewProjPreset}
        <p class="text-[11px] text-vpro-ink-secondary">
          Standard: <span class="font-mono font-semibold">{meta.selectedNewProjPreset.ecosysCollectionStandard}</span>
          &middot; Datum: <span class="font-mono font-semibold">{meta.selectedNewProjPreset.datum}</span> ({meta
            .selectedNewProjPreset.plotMethod})
        </p>
      {/if}
    </div>
    {#if meta.newProjIdTruncationWarning}
      <p
        role="status"
        data-projectid-truncation-warning
        class="rounded border-l-4 border-vpro-gold bg-vpro-warning-bg p-2 text-xs text-vpro-ink"
      >
        {meta.newProjIdTruncationWarning}
      </p>
    {/if}
    <div class="space-y-1">
      <label class="block text-xs font-semibold text-vpro-ink-secondary" for="new-project-dest">
        Destination .db Path (optional)
      </label>
      <input
        id="new-project-dest"
        type="text"
        class="w-full rounded border border-vpro-border p-2 font-mono text-sm"
        bind:value={newProjDest}
        disabled={meta.busy}
        placeholder="Defaults to projects/<Name>.db"
      />
    </div>
    <label class="flex items-center gap-2 text-xs text-vpro-ink">
      <input type="checkbox" bind:checked={newProjActivate} disabled={meta.busy} />
      Switch active context to new project immediately
    </label>
    {#if meta.newProjValidationError}<p role="alert" class="text-xs text-vpro-error">
        {meta.newProjValidationError}
      </p>{/if}
    <button
      type="button"
      disabled={meta.busy || !newProjName || !!meta.newProjValidationError}
      class="w-full rounded bg-vpro-navy px-3 py-2 text-sm font-semibold text-white hover:bg-vpro-navy-dark disabled:opacity-50"
      onclick={onsubmitnewproject}
    >
      Create VPro Project
    </button>
    {#if meta.newProjResult}
      <p class="break-all text-xs text-vpro-ink-secondary">
        ProjectID: <span class="font-mono font-semibold text-vpro-navy">{meta.newProjResult.projectId}</span> &middot;
        SHA-256: <span class="font-mono">{meta.newProjResult.destinationSha256.slice(0, 16)}</span>
      </p>
    {/if}
  </fieldset>

  <fieldset class="space-y-3 rounded border border-vpro-border border-t-[3px] border-t-vpro-gold p-4">
    <legend class="px-1 text-sm font-semibold text-vpro-navy">Save Active Project As</legend>
    <p class="text-xs text-vpro-ink-secondary">
      Lossless copy of <span class="font-mono font-semibold">{meta.activeProject}</span> renaming prefix across core and companion
      (_SU, _Hierarchy, _Lump, _Profile) tables.
    </p>
    <div class="space-y-1">
      <label class="block text-xs font-semibold text-vpro-ink-secondary" for="saveas-name">New Project Prefix</label>
      <input
        id="saveas-name"
        type="text"
        class="w-full rounded border border-vpro-border p-2 text-sm"
        bind:value={saveAsName}
        disabled={meta.busy}
        aria-invalid={!!meta.saveAsValidationError}
      />
    </div>
    <div class="space-y-1">
      <label class="block text-xs font-semibold text-vpro-ink-secondary" for="saveas-dest">
        Destination .db Path (optional)
      </label>
      <input
        id="saveas-dest"
        type="text"
        class="w-full rounded border border-vpro-border p-2 font-mono text-sm"
        bind:value={saveAsDest}
        disabled={meta.busy}
        placeholder="Defaults to projects/<NewPrefix>.db"
      />
    </div>
    <label class="flex items-center gap-2 text-xs text-vpro-ink">
      <input type="checkbox" bind:checked={saveAsActivate} disabled={meta.busy} />
      Switch active context to saved copy
    </label>
    {#if meta.saveAsValidationError}<p role="alert" class="text-xs text-red-700">{meta.saveAsValidationError}</p>{/if}
    <button
      type="button"
      disabled={meta.busy || !saveAsName || !!meta.saveAsValidationError}
      class="w-full rounded bg-vpro-navy px-3 py-2 text-sm font-semibold text-white hover:bg-vpro-navy-dark disabled:opacity-50"
      onclick={onsubmitsaveas}
    >
      Save Project As
    </button>
    {#if meta.saveAsResult && meta.saveAsResult.companionTables.length > 0}
      <p class="text-xs text-vpro-ink-secondary">
        Preserved companions: <span class="font-mono">{meta.saveAsResult.companionTables.join(', ')}</span>
      </p>
    {/if}
  </fieldset>

  <fieldset class="space-y-3 rounded border border-vpro-border border-t-[3px] border-t-vpro-gold p-4">
    <legend class="px-1 text-sm font-semibold text-vpro-navy">Export Splinter Project</legend>
    <div class="space-y-1">
      <label class="block text-xs font-semibold text-vpro-ink-secondary" for="splinter-name"
        >Splinter Project Name</label
      >
      <input
        id="splinter-name"
        type="text"
        class="w-full rounded border border-vpro-border p-2 text-sm"
        bind:value={splinterName}
        disabled={meta.busy}
        aria-invalid={!!meta.splinterValidationError}
      />
    </div>
    <label class="flex items-center gap-2 text-xs text-vpro-ink">
      <input type="checkbox" bind:checked={splinterUseSu} disabled={meta.busy} />
      Filter by active Site Unit table ({meta.activeSu})
    </label>
    <div class="space-y-1">
      <label class="block text-xs font-semibold text-vpro-ink-secondary" for="splinter-units">
        Site Unit Filter (comma-separated, optional)
      </label>
      <input
        id="splinter-units"
        type="text"
        class="w-full rounded border border-vpro-border p-2 font-mono text-sm"
        bind:value={splinterUnitsRaw}
        disabled={meta.busy}
        placeholder="e.g. CWHvm1/01, CWHvm1/05"
      />
    </div>
    <div class="space-y-1">
      <label class="block text-xs font-semibold text-vpro-ink-secondary" for="splinter-plots">
        Explicit Plot Subset (comma-separated, optional)
      </label>
      <input
        id="splinter-plots"
        type="text"
        class="w-full rounded border border-vpro-border p-2 font-mono text-sm"
        bind:value={splinterPlotsRaw}
        disabled={meta.busy}
        placeholder="e.g. 00337, 108050"
      />
    </div>
    <div class="space-y-1">
      <label class="block text-xs font-semibold text-vpro-ink-secondary" for="splinter-dest">
        Destination .db Path (optional)
      </label>
      <input
        id="splinter-dest"
        type="text"
        class="w-full rounded border border-vpro-border p-2 font-mono text-sm"
        bind:value={splinterDest}
        disabled={meta.busy}
      />
    </div>
    <label class="flex items-center gap-2 text-xs text-vpro-ink">
      <input type="checkbox" bind:checked={splinterActivate} disabled={meta.busy} />
      Switch active context to splinter project
    </label>
    {#if meta.splinterValidationError}<p role="alert" class="text-xs text-red-700">
        {meta.splinterValidationError}
      </p>{/if}
    <button
      type="button"
      disabled={meta.busy || !splinterName || !!meta.splinterValidationError}
      class="w-full rounded bg-vpro-navy px-3 py-2 text-sm font-semibold text-white hover:bg-vpro-navy-dark disabled:opacity-50"
      onclick={onsubmitsplinter}
    >
      Export Splinter Project
    </button>
    {#if meta.splinterResult}
      <p class="text-xs text-vpro-ink-secondary">
        Exported {meta.splinterResult.exportedPlotCount} / {meta.splinterResult.sourcePlotCount} plots.
      </p>
    {/if}
  </fieldset>
</div>
