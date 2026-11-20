<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { formatError } from '../shared/readRequests';
  import {
    defaultProjectMetadataAutomationPort,
    COVER_DESCRIPTION_ORDER,
    formatCollectionCode,
    formatDatumCode,
    validateMetadataAutomationRequest,
    type ProjectMetadataAutomationPort,
    type ProjectMetadataPreset,
    type DerivedProjectMetadata,
    type ApplyProjectMetadataAutomationResult,
  } from './projectMetadataPresets';

  let {
    contextId,
    projectId = '',
    operationHeld = false,
    port = defaultProjectMetadataAutomationPort,
    onBusyChange,
    onapplied,
  }: {
    contextId: string;
    projectId?: string;
    operationHeld?: boolean;
    port?: ProjectMetadataAutomationPort;
    onBusyChange?: (busy: boolean) => void;
    onapplied?: (result: ApplyProjectMetadataAutomationResult) => void;
  } = $props();

  let targetProjectId = $state('');
  let presets = $state<ProjectMetadataPreset[]>([]);
  let selectedPresetId = $state<string>('LMH25_2023_FS882');
  let applyDerived = $state(true);
  let applyPreset = $state(true);
  let derivedPreview = $state<DerivedProjectMetadata | null>(null);
  let lastResult = $state<ApplyProjectMetadataAutomationResult | null>(null);
  let busy = $state(false);
  let error = $state<string | null>(null);
  let status = $state<string | null>(null);
  let generation = 0;
  let trackedContextId = '';

  function setBusy(next: boolean) {
    busy = next;
    onBusyChange?.(next);
  }

  $effect(() => {
    if (projectId && targetProjectId === '') {
      targetProjectId = projectId;
    }
  });

  $effect(() => {
    if (trackedContextId !== '' && trackedContextId !== contextId) {
      targetProjectId = projectId || '';
      lastResult = null;
      trackedContextId = contextId;
      void loadPreviewAndPresets();
      return;
    }
    trackedContextId = contextId;
  });

  const selectedPreset = $derived(presets.find((p) => p.id === selectedPresetId) ?? null);

  onMount(() => {
    void loadPreviewAndPresets();
  });

  onDestroy(() => {
    generation++;
    onBusyChange?.(false);
  });

  async function loadPreviewAndPresets() {
    if (operationHeld) return;
    const gen = ++generation;
    setBusy(true);
    error = null;
    try {
      const pidSnapshot = $state.snapshot(targetProjectId);
      const [loadedPresets, derived] = await Promise.all([
        port.listPresets(),
        port.deriveFromPlots(contextId, pidSnapshot),
      ]);
      if (gen !== generation) return;
      presets = loadedPresets;
      derivedPreview = derived;
      if (!targetProjectId && derived.projectId) {
        targetProjectId = derived.projectId;
      }
      status = `Derived metadata preview computed across ${derived.totalPlotsInScope} plot(s).`;
    } catch (cause) {
      if (gen === generation) error = `Metadata derivation preview unavailable: ${formatError(cause)}`;
    } finally {
      if (gen === generation) setBusy(false);
    }
  }

  async function commitAutomation() {
    if (busy || operationHeld) {
      error = 'Wait for the current operation or decision before applying ProjectMetadata presets.';
      return;
    }
    const req = $state.snapshot({
      projectId: targetProjectId.trim(),
      applyDerived,
      presetId: applyPreset ? selectedPresetId : undefined,
    });
    const vErr = validateMetadataAutomationRequest(req);
    if (vErr) {
      error = vErr;
      return;
    }
    const gen = ++generation;
    setBusy(true);
    error = null;
    status = null;
    try {
      const res = await port.applyAutomation(contextId, req);
      if (gen !== generation) return;
      lastResult = res;
      derivedPreview = res.derived;
      status = `Applied ${res.updatedColumns.length} metadata column(s) to ProjectID "${res.projectId}" (ID ${res.metadataId}, ${res.auditRowCount} audit entries).`;
      if (onapplied) onapplied(res);
    } catch (cause) {
      if (gen === generation) error = `Apply ProjectMetadata automation failed: ${formatError(cause)}`;
    } finally {
      if (gen === generation) setBusy(false);
    }
  }
</script>

<section
  class="min-w-0 space-y-4 rounded border border-vpro-border bg-white shadow-sm"
  aria-label="Auto-Derived ProjectMetadata and Standards Presets"
>
  <header class="border-b-[3px] border-b-vpro-gold bg-vpro-navy px-4 py-3 text-white">
    <p class="text-xs font-semibold uppercase tracking-wider text-vpro-gold">PROJECT METADATA</p>
    <h3 class="m-0 text-base font-semibold text-white">
      Auto-Populate Project Metadata from Plots &amp; LMH25 Presets
    </h3>
  </header>

  <div class="space-y-4 px-4 pb-4">
    {#if error}
      <p role="alert" class="rounded border-l-4 border-red-700 bg-red-50 p-3 text-xs text-red-900">{error}</p>
    {/if}
    {#if status}
      <p role="status" class="rounded border-l-4 border-vpro-navy bg-vpro-surface-subtle p-3 text-xs text-vpro-ink">
        {status}
      </p>
    {/if}

    <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
      <div class="space-y-1">
        <label class="block text-xs font-semibold text-vpro-ink-secondary" for="auto-meta-pid"
          >Target ProjectID (max 20 characters)</label
        >
        <input
          id="auto-meta-pid"
          type="text"
          class="w-full rounded border border-vpro-border p-2 text-sm font-mono"
          bind:value={targetProjectId}
          disabled={busy}
        />
      </div>
      <div class="space-y-1">
        <label class="block text-xs font-semibold text-vpro-ink-secondary" for="auto-meta-preset"
          >Standards Preset Template</label
        >
        <select
          id="auto-meta-preset"
          class="w-full rounded border border-vpro-border p-2 text-sm"
          bind:value={selectedPresetId}
          disabled={busy}
        >
          {#each presets as preset (preset.id)}
            <option value={preset.id}>{preset.label}</option>
          {/each}
        </select>
      </div>
      <div class="flex items-end gap-2">
        <button
          type="button"
          disabled={busy}
          class="rounded border border-vpro-navy bg-white px-3 py-2 text-xs font-semibold text-vpro-navy hover:bg-vpro-surface-subtle disabled:opacity-50"
          onclick={loadPreviewAndPresets}
        >
          Refresh Plot Preview
        </button>
        <button
          type="button"
          disabled={busy || (!applyDerived && !applyPreset)}
          class="rounded border-2 border-vpro-gold bg-vpro-navy px-4 py-2 text-xs font-semibold text-white hover:bg-vpro-navy-dark disabled:opacity-50"
          onclick={commitAutomation}
        >
          Apply to ProjectMetadata
        </button>
      </div>
    </div>

    <div class="flex flex-wrap gap-6 text-xs text-vpro-ink">
      <label class="flex items-center gap-2 font-medium">
        <input type="checkbox" bind:checked={applyDerived} disabled={busy} />
        Apply Auto-Derived Plot Aggregations &amp; 2026 VLists Stamps
      </label>
      <label class="flex items-center gap-2 font-medium">
        <input type="checkbox" bind:checked={applyPreset} disabled={busy} />
        Apply Selected Standards Preset &amp; 15 Cover*Description Fields
      </label>
    </div>

    <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
      {#if derivedPreview}
        <fieldset class="space-y-2 rounded border border-vpro-border border-t-[3px] border-t-vpro-gold p-3">
          <legend class="px-1 text-xs font-semibold text-vpro-navy"
            >Non-Destructive Plot Aggregation Preview ({derivedPreview.totalPlotsInScope} plots)</legend
          >
          <dl class="grid grid-cols-2 gap-x-3 gap-y-1 text-xs">
            <dt class="text-vpro-ink-secondary">Survey Years (StartDate..EndDate)</dt>
            <dd class="font-mono font-semibold">
              {derivedPreview.startDate ?? 'NULL'} .. {derivedPreview.endDate ?? 'NULL'}
            </dd>
            <dt class="text-vpro-ink-secondary">NumberOfFS882Plots</dt>
            <dd class="font-mono font-semibold">{derivedPreview.numberOfFs882Plots}</dd>
            <dt class="text-vpro-ink-secondary">NumberOfSiteVisits (SIVI)</dt>
            <dd class="font-mono font-semibold">{derivedPreview.numberOfSiteVisits}</dd>
            <dt class="text-vpro-ink-secondary">GeographicStudyRegion</dt>
            <dd class="font-mono">{derivedPreview.geographicStudyRegion || '(none)'}</dd>
            <dt class="text-vpro-ink-secondary">CollectedSite</dt>
            <dd>{formatCollectionCode(derivedPreview.collectedSite)}</dd>
            <dt class="text-vpro-ink-secondary">CollectedVeg</dt>
            <dd>{formatCollectionCode(derivedPreview.collectedVeg)}</dd>
            <dt class="text-vpro-ink-secondary">CollectedSoil</dt>
            <dd>{formatCollectionCode(derivedPreview.collectedSoil)}</dd>
            <dt class="text-vpro-ink-secondary">CollectedTerrain</dt>
            <dd>{formatCollectionCode(derivedPreview.collectedTerrain)}</dd>
            <dt class="text-vpro-ink-secondary">AllSpecs Stamp</dt>
            <dd class="break-all font-mono">{derivedPreview.allSpecs}</dd>
            <dt class="text-vpro-ink-secondary">TableOfLists Stamp</dt>
            <dd class="break-all font-mono">{derivedPreview.tableOfLists}</dd>
          </dl>
        </fieldset>
      {/if}

      {#if selectedPreset}
        <fieldset class="space-y-2 rounded border border-vpro-border border-t-[3px] border-t-vpro-gold p-3">
          <legend class="px-1 text-xs font-semibold text-vpro-navy">Preset Preview: {selectedPreset.label}</legend>
          <p class="text-xs text-vpro-ink-secondary">{selectedPreset.description}</p>
          <dl class="grid grid-cols-2 gap-x-3 gap-y-1 text-xs">
            <dt class="text-vpro-ink-secondary">EcosysCollectionStandard</dt>
            <dd class="font-mono font-semibold">{selectedPreset.ecosysCollectionStandard}</dd>
            <dt class="text-vpro-ink-secondary">VegCoverMethod / PlotMethod</dt>
            <dd class="font-mono">{selectedPreset.vegCoverMethod} / {selectedPreset.plotMethod}</dd>
            <dt class="text-vpro-ink-secondary">Datum</dt>
            <dd class="font-mono font-semibold">{formatDatumCode(selectedPreset.datum)}</dd>
          </dl>
          <div class="max-h-40 overflow-y-auto rounded border border-vpro-border p-2">
            <table class="w-full text-left text-xs">
              <tbody>
                {#each COVER_DESCRIPTION_ORDER as col}
                  <tr class="border-b border-vpro-rail last:border-b-0">
                    <td class="py-1 pr-2 font-mono text-vpro-ink-secondary">{col}</td>
                    <td class="py-1 text-vpro-ink">{selectedPreset.coverDescriptions[col] ?? ''}</td>
                  </tr>
                {/each}
              </tbody>
            </table>
          </div>
        </fieldset>
      {/if}
    </div>

    {#if lastResult}
      <p class="text-xs text-vpro-ink-secondary">
        Saved Metadata ID {lastResult.metadataId} ({lastResult.updatedColumns.length} updated field(s)).
      </p>
    {/if}
  </div>
</section>
