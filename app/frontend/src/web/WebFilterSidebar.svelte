<script lang="ts">
  import { ChevronLeft, ChevronRight, Crosshair, Filter, RotateCcw, Search, SquareDashedMousePointer } from '@lucide/svelte';
  import {
    computeAvailableSubzones,
    countActiveFilters,
    pruneSelectedSubzones,
    type BECMasterFilterOptions,
    type BECMasterFilterState,
    type BECMasterSelectMode,
  } from './webBECMasterFilter';

  let {
    options,
    filter = $bindable(),
    collapsed = $bindable(false),
    drawBBoxMode = $bindable(false),
    loadingOptions = false,
    applying = false,
    onApply,
    onClear,
  }: {
    options: BECMasterFilterOptions | null;
    filter: BECMasterFilterState;
    collapsed?: boolean;
    drawBBoxMode?: boolean;
    loadingOptions?: boolean;
    applying?: boolean;
    onApply: () => void;
    onClear: () => void;
  } = $props();

  let projectSearch = $state('');
  let subzoneSearch = $state('');
  let qualityExpanded = $state(true);

  const activeCount = $derived(countActiveFilters(filter));

  const availableSubzones = $derived(computeAvailableSubzones(options?.subzonesByZone, filter.zones));

  const filteredSubzones = $derived.by(() => {
    const q = subzoneSearch.trim().toLowerCase();
    if (!q) return availableSubzones;
    return availableSubzones.filter((sz) => sz.toLowerCase().includes(q));
  });

  const filteredProjects = $derived.by(() => {
    const list = options?.projects ?? [];
    const q = projectSearch.trim().toLowerCase();
    if (!q) return list;
    return list.filter(
      (p) => p.projectId.toLowerCase().includes(q) || (p.title ?? '').toLowerCase().includes(q)
    );
  });

  function toggleValue(list: readonly string[], value: string): string[] {
    if (list.includes(value)) {
      return list.filter((item) => item !== value);
    }
    return [...list, value];
  }

  function setSelectMode(nextMode: BECMasterSelectMode) {
    filter = { ...filter, mode: nextMode };
    if (nextMode !== 'bbox' && drawBBoxMode) {
      drawBBoxMode = false;
    }
  }

  function toggleZone(zone: string) {
    const nextZones = toggleValue(filter.zones, zone);
    const nextAvail = computeAvailableSubzones(options?.subzonesByZone, nextZones);
    const nextSubzones = pruneSelectedSubzones(filter.subzones, nextAvail);
    filter = { ...filter, zones: nextZones, subzones: nextSubzones };
  }

  function toggleDrawBBox() {
    if (filter.mode !== 'bbox') {
      filter = { ...filter, mode: 'bbox' };
    }
    drawBBoxMode = !drawBBoxMode;
  }

  function clearBBoxInputs() {
    filter = { ...filter, nwLat: '', nwLon: '', seLat: '', seLon: '' };
    drawBBoxMode = false;
  }
</script>

<aside
  class="web-filter-sidebar"
  class:collapsed
  aria-label="Select and Filter Plots"
  data-web-filter-sidebar
>
  <div class="web-filter-header">
    {#if !collapsed}
      <div class="web-filter-title-row">
        <Filter size={15} class="text-vpro-navy shrink-0" aria-hidden="true" />
        <h2 class="web-filter-heading">Select &amp; Filter Plots</h2>
        {#if activeCount > 0}
          <span class="web-filter-badge tabular-nums" data-active-filter-count>{activeCount}</span>
        {/if}
      </div>
    {/if}
    <button
      type="button"
      class="web-collapse-btn"
      aria-label={collapsed ? 'Expand filter panel' : 'Collapse filter panel'}
      aria-expanded={!collapsed}
      title={collapsed ? 'Expand filter panel' : 'Collapse filter panel'}
      onclick={() => (collapsed = !collapsed)}
      data-filter-collapse-btn
    >
      {#if collapsed}
        <ChevronRight size={16} aria-hidden="true" />
      {:else}
        <ChevronLeft size={16} aria-hidden="true" />
      {/if}
    </button>
  </div>

  {#if collapsed}
    <div class="web-collapsed-rail">
      <button
        type="button"
        class="web-collapsed-expand-pill"
        onclick={() => (collapsed = false)}
        title="Open Select & Filter Plots"
      >
        <Filter size={15} aria-hidden="true" />
        <span class="web-collapsed-label">Filters</span>
        {#if activeCount > 0}
          <span class="web-filter-badge tabular-nums">{activeCount}</span>
        {/if}
      </button>
    </div>
  {:else}
    <div class="web-filter-scroll">
      {#if loadingOptions && !options}
        <p class="web-filter-status" role="status">Loading filter choices...</p>
      {/if}

      <!-- 1. Select Plots Primary Mode -->
      <fieldset class="web-filter-section" data-filter-section="select-plots">
        <legend class="web-section-legend">1. Select Plots</legend>
        <div class="web-mode-radios" role="radiogroup" aria-label="Plot selection method">
          {#each [
            { id: 'all', label: 'All' },
            { id: 'region', label: 'Region' },
            { id: 'project', label: 'Project' },
            { id: 'bbox', label: 'Bounding Box' },
          ] as modeOpt (modeOpt.id)}
            <label class="web-mode-radio" class:active={filter.mode === modeOpt.id}>
              <input
                type="radio"
                name="becmaster-select-mode"
                value={modeOpt.id}
                checked={filter.mode === modeOpt.id}
                onchange={() => setSelectMode(modeOpt.id as BECMasterSelectMode)}
                data-select-mode={modeOpt.id}
              />
              <span>{modeOpt.label}</span>
            </label>
          {/each}
        </div>

        {#if filter.mode === 'region'}
          <div class="web-mode-body" data-mode-panel="region">
            <div class="web-field-label">BC Forest Regions ({filter.regions.length} selected)</div>
            <div class="web-check-list web-check-list-compact">
              {#each options?.regions ?? [] as reg (reg.code)}
                <label class="web-check-item">
                  <input
                    type="checkbox"
                    checked={filter.regions.includes(reg.code)}
                    onchange={() => (filter = { ...filter, regions: toggleValue(filter.regions, reg.code) })}
                    data-region-checkbox={reg.code}
                  />
                  <span class="web-code-pill">{reg.code}</span>
                  <span class="truncate">{reg.label}</span>
                </label>
              {/each}
            </div>
          </div>
        {:else if filter.mode === 'project'}
          <div class="web-mode-body" data-mode-panel="project">
            <div class="web-field-label">
              Project IDs ({filter.projectIds.length} selected)
            </div>
            <div class="web-search-box">
              <Search size={13} aria-hidden="true" />
              <input
                type="search"
                bind:value={projectSearch}
                placeholder="Search projects..."
                aria-label="Search Project IDs"
              />
            </div>
            <div class="web-check-list">
              {#if filteredProjects.length === 0}
                <div class="web-empty-note">No matching projects.</div>
              {:else}
                {#each filteredProjects as proj (proj.projectId)}
                  <label class="web-check-item" title={proj.title || proj.projectId}>
                    <input
                      type="checkbox"
                      checked={filter.projectIds.includes(proj.projectId)}
                      onchange={() =>
                        (filter = { ...filter, projectIds: toggleValue(filter.projectIds, proj.projectId) })}
                      data-project-checkbox={proj.projectId}
                    />
                    <span class="font-mono text-[11px] font-semibold">{proj.projectId}</span>
                    {#if proj.plotCount}
                      <span class="web-item-count tabular-nums">{proj.plotCount.toLocaleString()}</span>
                    {/if}
                  </label>
                {/each}
              {/if}
            </div>

            {#if options?.hasPublicationLinks && (options.publications?.length ?? 0) > 0}
              <div class="mt-2.5" data-publications-filter>
                <div class="web-field-label">
                  Publications ({filter.publicationIds.length} selected)
                </div>
                <div class="web-check-list web-check-list-compact">
                  {#each options.publications as pub (pub.id)}
                    <label class="web-check-item" title={pub.title}>
                      <input
                        type="checkbox"
                        checked={filter.publicationIds.includes(pub.id)}
                        onchange={() =>
                          (filter = {
                            ...filter,
                            publicationIds: toggleValue(filter.publicationIds, pub.id),
                          })}
                        data-publication-checkbox={pub.id}
                      />
                      <span class="truncate">{pub.title}</span>
                    </label>
                  {/each}
                </div>
              </div>
            {/if}
          </div>
        {:else if filter.mode === 'bbox'}
          <div class="web-mode-body" data-mode-panel="bbox">
            <div class="flex items-center gap-1.5">
              <button
                type="button"
                class="web-draw-bbox-btn"
                class:active={drawBBoxMode}
                aria-pressed={drawBBoxMode}
                onclick={toggleDrawBBox}
                data-draw-bbox-toggle
              >
                <SquareDashedMousePointer size={14} aria-hidden="true" />
                <span>{drawBBoxMode ? 'Drawing on Map (Click & Drag)...' : 'Draw Bounding Box on Map'}</span>
              </button>
              {#if filter.nwLat || filter.nwLon || filter.seLat || filter.seLon}
                <button
                  type="button"
                  class="web-mini-clear-btn"
                  onclick={clearBBoxInputs}
                  title="Clear bounding box coordinates"
                >
                  Clear
                </button>
              {/if}
            </div>
            {#if drawBBoxMode}
              <p class="web-bbox-hint" role="status">
                Click and drag on the map to draw a selection rectangle, or press Escape to cancel.
              </p>
            {/if}

            <div class="web-coord-group">
              <div class="web-coord-group-title">
                <Crosshair size={12} aria-hidden="true" />
                <span>Northwest Corner (Decimal Degrees)</span>
              </div>
              <div class="web-coord-pair">
                <label class="web-num-field">
                  <span>NW Lat</span>
                  <input
                    type="number"
                    step="0.0001"
                    min="45"
                    max="65"
                    placeholder="56.5000"
                    bind:value={filter.nwLat}
                    data-bbox-nw-lat
                  />
                </label>
                <label class="web-num-field">
                  <span>NW Lon</span>
                  <input
                    type="number"
                    step="0.0001"
                    min="-145"
                    max="-110"
                    placeholder="-129.0000"
                    bind:value={filter.nwLon}
                    data-bbox-nw-lon
                  />
                </label>
              </div>
            </div>

            <div class="web-coord-group">
              <div class="web-coord-group-title">
                <Crosshair size={12} aria-hidden="true" />
                <span>Southeast Corner (Decimal Degrees)</span>
              </div>
              <div class="web-coord-pair">
                <label class="web-num-field">
                  <span>SE Lat</span>
                  <input
                    type="number"
                    step="0.0001"
                    min="45"
                    max="65"
                    placeholder="52.0000"
                    bind:value={filter.seLat}
                    data-bbox-se-lat
                  />
                </label>
                <label class="web-num-field">
                  <span>SE Lon</span>
                  <input
                    type="number"
                    step="0.0001"
                    min="-145"
                    max="-110"
                    placeholder="-121.0000"
                    bind:value={filter.seLon}
                    data-bbox-se-lon
                  />
                </label>
              </div>
            </div>
          </div>
        {:else}
          <p class="web-all-hint">Showing all plots in the active dataset. Narrow results using attributes below or choose Region, Project, or Bounding Box.</p>
        {/if}
      </fieldset>

      <!-- 2. Attribute Filters -->
      <fieldset class="web-filter-section" data-filter-section="attributes">
        <legend class="web-section-legend">2. Attribute Filters</legend>

        <div class="web-field-group">
          <div class="web-field-label">BGC Zone ({filter.zones.length} selected)</div>
          <div class="web-chip-grid">
            {#each options?.zones ?? [] as zone (zone)}
              <button
                type="button"
                class="web-toggle-chip"
                class:selected={filter.zones.includes(zone)}
                aria-pressed={filter.zones.includes(zone)}
                onclick={() => toggleZone(zone)}
                data-zone-chip={zone}
              >
                {zone}
              </button>
            {/each}
          </div>
        </div>

        <div class="web-field-group">
          <div class="web-field-label">
            Subzone / BGC ({filter.subzones.length} selected)
            {#if filter.zones.length > 0}
              <span class="web-field-subnote">in {filter.zones.join(', ')}</span>
            {/if}
          </div>
          <div class="web-search-box">
            <Search size={13} aria-hidden="true" />
            <input
              type="search"
              bind:value={subzoneSearch}
              placeholder="Filter subzones (e.g. CWHvm1)..."
              aria-label="Filter BGC subzones"
            />
          </div>
          <div class="web-check-list web-check-list-compact">
            {#if filteredSubzones.length === 0}
              <div class="web-empty-note">No matching subzones.</div>
            {:else}
              {#each filteredSubzones as sz (sz)}
                <label class="web-check-item">
                  <input
                    type="checkbox"
                    checked={filter.subzones.includes(sz)}
                    onchange={() => (filter = { ...filter, subzones: toggleValue(filter.subzones, sz) })}
                    data-subzone-checkbox={sz}
                  />
                  <span class="font-mono text-[11px]">{sz}</span>
                </label>
              {/each}
            {/if}
          </div>
        </div>

        <div class="web-field-group">
          <div class="web-field-label">Survey Year Range</div>
          <div class="web-coord-pair">
            <label class="web-num-field">
              <span>Start Year</span>
              <input
                type="number"
                min={options?.minYear || 1950}
                max={options?.maxYear || 2030}
                placeholder={options?.minYear ? String(options.minYear) : '1965'}
                bind:value={filter.minYear}
                data-filter-min-year
              />
            </label>
            <label class="web-num-field">
              <span>End Year</span>
              <input
                type="number"
                min={options?.minYear || 1950}
                max={options?.maxYear || 2030}
                placeholder={options?.maxYear ? String(options.maxYear) : '2026'}
                bind:value={filter.maxYear}
                data-filter-max-year
              />
            </label>
          </div>
        </div>

        <div class="web-field-group">
          <div class="web-field-label">Successional Status ({filter.successionalStatuses.length})</div>
          <div class="web-check-list web-check-list-compact">
            {#each options?.successionalStatuses ?? [] as st (st.code)}
              <label class="web-check-item">
                <input
                  type="checkbox"
                  checked={filter.successionalStatuses.includes(st.code)}
                  onchange={() =>
                    (filter = {
                      ...filter,
                      successionalStatuses: toggleValue(filter.successionalStatuses, st.code),
                    })}
                  data-succ-checkbox={st.code}
                />
                <span class="web-code-pill">{st.code}</span>
                <span class="truncate">{st.label}</span>
              </label>
            {/each}
          </div>
        </div>

        <div class="web-field-group">
          <div class="web-field-label">Structural Stage ({filter.structuralStages.length})</div>
          <div class="web-check-list web-check-list-compact">
            {#each options?.structuralStages ?? [] as sg (sg.code)}
              <label class="web-check-item">
                <input
                  type="checkbox"
                  checked={filter.structuralStages.includes(sg.code)}
                  onchange={() =>
                    (filter = {
                      ...filter,
                      structuralStages: toggleValue(filter.structuralStages, sg.code),
                    })}
                  data-stage-checkbox={sg.code}
                />
                <span class="web-code-pill">{sg.code}</span>
                <span class="truncate">{sg.label}</span>
              </label>
            {/each}
          </div>
        </div>

        <label class="web-pub-only-check">
          <input
            type="checkbox"
            bind:checked={filter.inPublicationsOnly}
            data-filter-published-only
          />
          <span>Plots used in published classification only</span>
        </label>
      </fieldset>

      <!-- 3. Quality Filters -->
      <fieldset class="web-filter-section" data-filter-section="quality">
        <legend class="web-section-legend">
          <button
            type="button"
            class="web-legend-toggle"
            aria-expanded={qualityExpanded}
            onclick={() => (qualityExpanded = !qualityExpanded)}
          >
            <span>3. Quality &amp; Location Accuracy</span>
            <span class="text-[11px] font-normal text-vpro-ink-muted">{qualityExpanded ? 'Hide' : 'Show'}</span>
          </button>
        </legend>

        {#if qualityExpanded}
          <div class="web-field-group">
            <div class="web-field-label">Site Plot Quality</div>
            <div class="web-chip-grid">
              {#each options?.sitePlotQualities ?? [] as q (q.code)}
                <button
                  type="button"
                  class="web-toggle-chip"
                  class:selected={filter.sitePlotQualities.includes(q.code)}
                  aria-pressed={filter.sitePlotQualities.includes(q.code)}
                  title={q.label}
                  onclick={() =>
                    (filter = {
                      ...filter,
                      sitePlotQualities: toggleValue(filter.sitePlotQualities, q.code),
                    })}
                  data-site-quality-chip={q.code}
                >
                  {q.code}
                </button>
              {/each}
            </div>
          </div>

          <div class="web-field-group">
            <div class="web-field-label">Veg Plot Quality</div>
            <div class="web-chip-grid">
              {#each options?.vegPlotQualities ?? [] as q (q.code)}
                <button
                  type="button"
                  class="web-toggle-chip"
                  class:selected={filter.vegPlotQualities.includes(q.code)}
                  aria-pressed={filter.vegPlotQualities.includes(q.code)}
                  title={q.label}
                  onclick={() =>
                    (filter = {
                      ...filter,
                      vegPlotQualities: toggleValue(filter.vegPlotQualities, q.code),
                    })}
                  data-veg-quality-chip={q.code}
                >
                  {q.code}
                </button>
              {/each}
            </div>
          </div>

          <div class="web-field-group">
            <div class="web-field-label">Soil Plot Quality</div>
            <div class="web-chip-grid">
              {#each options?.soilPlotQualities ?? [] as q (q.code)}
                <button
                  type="button"
                  class="web-toggle-chip"
                  class:selected={filter.soilPlotQualities.includes(q.code)}
                  aria-pressed={filter.soilPlotQualities.includes(q.code)}
                  title={q.label}
                  onclick={() =>
                    (filter = {
                      ...filter,
                      soilPlotQualities: toggleValue(filter.soilPlotQualities, q.code),
                    })}
                  data-soil-quality-chip={q.code}
                >
                  {q.code}
                </button>
              {/each}
            </div>
          </div>

          <div class="web-field-group">
            <label class="web-field-label" for="becmaster-loc-accuracy">Location Accuracy</label>
            <select
              id="becmaster-loc-accuracy"
              class="web-select"
              bind:value={filter.locationAccuracy}
              data-filter-location-accuracy
            >
              <option value="">Any accuracy</option>
              {#each options?.locationAccuracies ?? [] as acc (acc.code)}
                <option value={acc.code}>{acc.label}</option>
              {/each}
            </select>
          </div>
        {/if}
      </fieldset>
    </div>

    <div class="web-filter-footer">
      <button
        type="button"
        class="web-apply-btn"
        disabled={applying}
        onclick={onApply}
        data-filter-apply-btn
      >
        {applying ? 'Applying...' : 'Apply'}
      </button>
      <button
        type="button"
        class="web-clear-btn"
        disabled={applying}
        onclick={onClear}
        data-filter-clear-btn
      >
        <RotateCcw size={13} aria-hidden="true" />
        <span>Clear Selections</span>
      </button>
    </div>
  {/if}
</aside>

<style>
  .web-filter-sidebar {
    width: 340px;
    min-width: 320px;
    max-width: 380px;
    display: flex;
    flex-direction: column;
    background: var(--vpro-surface, #ffffff);
    border-right: 1px solid var(--vpro-border, #d1d5db);
    overflow: hidden;
    flex-shrink: 0;
  }

  .web-filter-sidebar.collapsed {
    width: 48px;
    min-width: 48px;
    max-width: 48px;
  }

  .web-filter-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    padding: 10px 12px;
    background: var(--vpro-surface-subtle, #f8fafb);
    border-bottom: 1px solid var(--vpro-border, #d1d5db);
  }

  .web-filter-title-row {
    display: flex;
    align-items: center;
    gap: 6px;
    min-width: 0;
  }

  .web-filter-heading {
    margin: 0;
    font-size: 13px;
    font-weight: 700;
    color: var(--vpro-navy, #003366);
    white-space: nowrap;
  }

  .web-filter-badge {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 20px;
    height: 18px;
    padding: 0 5px;
    border-radius: 999px;
    background: var(--vpro-gold, #fcba19);
    color: #002244;
    font-size: 11px;
    font-weight: 700;
  }

  .web-collapse-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 26px;
    height: 26px;
    border-radius: 4px;
    border: 1px solid var(--vpro-border, #d1d5db);
    background: #ffffff;
    color: var(--vpro-navy, #003366);
    cursor: pointer;
  }

  .web-collapse-btn:hover {
    background: var(--vpro-navy-tint, #ebf1f8);
  }

  .web-collapsed-rail {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    padding-top: 12px;
  }

  .web-collapsed-expand-pill {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
    padding: 8px 4px;
    border: 1px solid var(--vpro-border, #d1d5db);
    border-radius: 6px;
    background: var(--vpro-surface-subtle, #f8fafb);
    color: var(--vpro-navy, #003366);
    cursor: pointer;
    font-size: 10px;
    font-weight: 700;
  }

  .web-collapsed-label {
    writing-mode: vertical-rl;
    transform: rotate(180deg);
    letter-spacing: 0.04em;
  }

  .web-filter-scroll {
    flex: 1;
    overflow-y: auto;
    padding: 10px 12px 14px;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .web-filter-status {
    margin: 0;
    font-size: 12px;
    color: var(--vpro-ink-secondary, #4b5563);
  }

  .web-filter-section {
    margin: 0;
    padding: 10px;
    border: 1px solid var(--vpro-border, #d1d5db);
    border-radius: 6px;
    background: var(--vpro-surface-subtle, #f8fafb);
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .web-section-legend {
    padding: 0 4px;
    font-size: 11px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--vpro-navy, #003366);
    width: 100%;
  }

  .web-legend-toggle {
    display: flex;
    align-items: center;
    justify-content: space-between;
    width: 100%;
    border: none;
    background: transparent;
    padding: 0;
    font: inherit;
    color: inherit;
    text-transform: inherit;
    letter-spacing: inherit;
    cursor: pointer;
  }

  .web-mode-radios {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 5px;
  }

  .web-mode-radio {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 5px 8px;
    border-radius: 4px;
    border: 1px solid var(--vpro-border, #d1d5db);
    background: #ffffff;
    font-size: 12px;
    font-weight: 600;
    color: var(--vpro-ink, #313132);
    cursor: pointer;
  }

  .web-mode-radio.active {
    border-color: var(--vpro-navy, #003366);
    background: var(--vpro-navy-tint, #ebf1f8);
    color: var(--vpro-navy, #003366);
  }

  .web-mode-radio input {
    accent-color: var(--vpro-navy, #003366);
    margin: 0;
  }

  .web-mode-body {
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding-top: 2px;
  }

  .web-all-hint {
    margin: 0;
    font-size: 11.5px;
    line-height: 1.4;
    color: var(--vpro-ink-secondary, #4b5563);
  }

  .web-field-group {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .web-field-label {
    font-size: 11.5px;
    font-weight: 600;
    color: var(--vpro-ink, #313132);
  }

  .web-field-subnote {
    font-weight: 400;
    color: var(--vpro-ink-muted, #5f6b7a);
  }

  .web-search-box {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 4px 8px;
    border: 1px solid var(--vpro-border, #d1d5db);
    border-radius: 4px;
    background: #ffffff;
    color: var(--vpro-ink-muted, #5f6b7a);
  }

  .web-search-box input {
    border: none;
    outline: none;
    width: 100%;
    font-size: 12px;
    color: var(--vpro-ink, #313132);
    background: transparent;
  }

  .web-check-list {
    max-height: 148px;
    overflow-y: auto;
    border: 1px solid var(--vpro-border, #d1d5db);
    border-radius: 4px;
    background: #ffffff;
    padding: 4px;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .web-check-list-compact {
    max-height: 118px;
  }

  .web-check-item {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 3px 5px;
    border-radius: 3px;
    font-size: 12px;
    color: var(--vpro-ink, #313132);
    cursor: pointer;
  }

  .web-check-item:hover {
    background: var(--vpro-navy-tint, #ebf1f8);
  }

  .web-check-item input {
    accent-color: var(--vpro-navy, #003366);
    margin: 0;
    flex-shrink: 0;
  }

  .web-code-pill {
    font-family: var(--vpro-font-mono, monospace);
    font-size: 10.5px;
    font-weight: 700;
    padding: 0 4px;
    border-radius: 3px;
    background: var(--vpro-canvas, #f2f4f6);
    color: var(--vpro-navy, #003366);
    flex-shrink: 0;
  }

  .web-item-count {
    margin-left: auto;
    font-size: 10.5px;
    color: var(--vpro-ink-muted, #5f6b7a);
  }

  .web-empty-note {
    padding: 6px;
    font-size: 11.5px;
    color: var(--vpro-ink-muted, #5f6b7a);
  }

  .web-chip-grid {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
  }

  .web-toggle-chip {
    padding: 3px 8px;
    border-radius: 4px;
    border: 1px solid var(--vpro-border, #d1d5db);
    background: #ffffff;
    font-size: 11.5px;
    font-weight: 600;
    color: var(--vpro-ink, #313132);
    cursor: pointer;
  }

  .web-toggle-chip:hover {
    border-color: var(--vpro-navy, #003366);
  }

  .web-toggle-chip.selected {
    background: var(--vpro-navy, #003366);
    border-color: var(--vpro-navy, #003366);
    color: #ffffff;
  }

  .web-draw-bbox-btn {
    flex: 1;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    padding: 6px 10px;
    border-radius: 4px;
    border: 1px solid var(--vpro-navy, #003366);
    background: #ffffff;
    color: var(--vpro-navy, #003366);
    font-size: 12px;
    font-weight: 700;
    cursor: pointer;
  }

  .web-draw-bbox-btn:hover {
    background: var(--vpro-navy-tint, #ebf1f8);
  }

  .web-draw-bbox-btn.active {
    background: var(--vpro-gold, #fcba19);
    border-color: #b7791f;
    color: #002244;
  }

  .web-mini-clear-btn {
    padding: 6px 8px;
    border-radius: 4px;
    border: 1px solid var(--vpro-border, #d1d5db);
    background: #ffffff;
    color: var(--vpro-ink-secondary, #4b5563);
    font-size: 11.5px;
    font-weight: 600;
    cursor: pointer;
  }

  .web-bbox-hint {
    margin: 0;
    padding: 5px 7px;
    border-radius: 4px;
    background: var(--vpro-gold-surface, #fef7e3);
    border: 1px solid var(--vpro-warning-border, #d99b26);
    font-size: 11px;
    color: var(--vpro-warning-ink, #704b00);
  }

  .web-coord-group {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .web-coord-group-title {
    display: flex;
    align-items: center;
    gap: 4px;
    font-size: 11px;
    font-weight: 600;
    color: var(--vpro-navy, #003366);
  }

  .web-coord-pair {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 6px;
  }

  .web-num-field {
    display: flex;
    flex-direction: column;
    gap: 2px;
    font-size: 11px;
    color: var(--vpro-ink-secondary, #4b5563);
  }

  .web-num-field input {
    width: 100%;
    padding: 4px 6px;
    border: 1px solid var(--vpro-border, #d1d5db);
    border-radius: 4px;
    background: #ffffff;
    font-family: var(--vpro-font-mono, monospace);
    font-size: 12px;
    color: var(--vpro-ink, #313132);
  }

  .web-pub-only-check {
    display: flex;
    align-items: flex-start;
    gap: 7px;
    padding-top: 2px;
    font-size: 12px;
    font-weight: 600;
    color: var(--vpro-ink, #313132);
    cursor: pointer;
  }

  .web-pub-only-check input {
    margin-top: 2px;
    accent-color: var(--vpro-navy, #003366);
  }

  .web-select {
    width: 100%;
    padding: 5px 8px;
    border: 1px solid var(--vpro-border, #d1d5db);
    border-radius: 4px;
    background: #ffffff;
    font-size: 12px;
    color: var(--vpro-ink, #313132);
  }

  .web-filter-footer {
    display: flex;
    gap: 8px;
    padding: 10px 12px;
    background: var(--vpro-surface, #ffffff);
    border-top: 1px solid var(--vpro-border, #d1d5db);
  }

  .web-apply-btn {
    flex: 1;
    padding: 8px 12px;
    border-radius: 4px;
    border: 1px solid var(--vpro-navy, #003366);
    background: var(--vpro-navy, #003366);
    color: #ffffff;
    font-size: 13px;
    font-weight: 700;
    cursor: pointer;
  }

  .web-apply-btn:hover:not(:disabled) {
    background: var(--vpro-navy-hover, #0a4480);
  }

  .web-apply-btn:disabled,
  .web-clear-btn:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .web-clear-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 5px;
    padding: 8px 10px;
    border-radius: 4px;
    border: 1px solid var(--vpro-border-strong, #9ca3af);
    background: #ffffff;
    color: var(--vpro-ink, #313132);
    font-size: 12px;
    font-weight: 600;
    cursor: pointer;
  }

  .web-clear-btn:hover:not(:disabled) {
    background: var(--vpro-canvas, #f2f4f6);
  }

  @media (max-width: 960px) {
    .web-filter-sidebar {
      width: 100%;
      min-width: 0;
      max-width: none;
      border-right: none;
      border-bottom: 1px solid var(--vpro-border, #d1d5db);
      max-height: 46vh;
    }

    .web-filter-sidebar.collapsed {
      width: 100%;
      min-width: 0;
      max-width: none;
      max-height: none;
    }

    .web-collapsed-rail {
      display: none;
    }
  }
</style>
