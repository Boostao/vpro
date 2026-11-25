<script lang="ts">
  import type { LongVegetationSettings } from '../../../bindings/github.com/boostao/vpro/app/internal/vegreport/models';
  import SiteUnitExclusionFilter from '../../classification/SiteUnitExclusionFilter.svelte';
  import type {
    HierarchyBreakpointOptions,
    SiteUnitExclusionRule,
    SiteUnitExclusionSummary,
  } from '../../classification/siteUnitExclusionFilter';
  import { reportCellText } from '../longEnvironmentReport';
  import { IS_WEB_READONLY } from '../../web/runtimeMode';
  import type { ValidatedProjectWorkbookReview } from '../longVegetationProjectWorkbook.svelte';
  import type { ValidatedVegetationWorkbookReview } from '../vegetationWorkbook';

  export interface LongVegControlsScope {
    contextId: string;
    project: string;
    projectPath: string;
    su: string;
    suPath: string;
    effectiveHierarchy: string;
  }

  export interface LongVegControlsState {
    projectActive: boolean;
    settings: LongVegetationSettings | null;
    groupLabel: string;
    busy: boolean;
    operationHeld: boolean;
    workbookBarrier: boolean;
    preferenceBarrier: boolean;
    selectedWorkbookScope: string;
    lumpTables: string[];
    useSppCodesOnly: boolean;
    applyExclusionsToReport: boolean;
    exclusionSummary: SiteUnitExclusionSummary | null;
    activeWorkbookReview: ValidatedVegetationWorkbookReview | ValidatedProjectWorkbookReview | null;
  }

  export interface LongVegControlsActions {
    onSelectWorkbookScope: (scope: string) => void;
    onRefreshLumpTables: () => void;
    onToggleUseSppCodesOnly: (checked: boolean) => void;
    onToggleApplyExclusions: (checked: boolean) => void;
    onRulesChange: (
      nextRules: SiteUnitExclusionRule[],
      nextUseBP: boolean,
      nextBPOpts: HierarchyBreakpointOptions
    ) => void;
    onLongPreview: (res: { preview?: unknown; exclusions?: SiteUnitExclusionSummary } | null | undefined) => void;
    onPublishWorkbook: () => void;
  }

  let {
    owner,
    state: ctrl,
    destination = $bindable(''),
    actions,
  }: {
    owner: LongVegControlsScope;
    state: LongVegControlsState;
    destination?: string;
    actions: LongVegControlsActions;
  } = $props();
</script>

<p>
  Project {owner.project}; selected SU {owner.su}.
  {ctrl.projectActive
    ? 'Explicit original whole-project scope; current SU is retained only for original quality authority when requested.'
    : 'Whole selected-SU scope; the current plot and profile navigation do not filter this report.'}
</p>
{#if !IS_WEB_READONLY}
  <dl class="scope">
    <div>
      <dt>Project database</dt>
      <dd>{owner.projectPath}</dd>
    </div>
    <div>
      <dt>Selected SU database</dt>
      <dd>{owner.suPath || 'No selected SU'}</dd>
    </div>
  </dl>
{/if}
{#if ctrl.settings}
  {@const settings = ctrl.settings}
  <dl class="settings" aria-label="Read-only report options">
    <div>
      <dt>Report Title</dt>
      <dd data-source-control="rptLvTitle">{settings.title === '' ? '"" (empty title)' : settings.title}</dd>
    </div>
    <div>
      <dt>Group by</dt>
      <dd>{settings.grouping === 'none' ? 'None (source layer observations retained)' : ctrl.groupLabel}</dd>
    </div>
    <div>
      <dt>Average</dt>
      <dd>
        {settings.average === 'all-plots'
          ? ctrl.projectActive
            ? 'By n Plots — original project tuple denominator; quality filters by plot existence'
            : settings.unitGrouping === 'all-plots'
              ? 'By n Plots — joined sum / derived Env/current-list denominator'
              : settings.unitGrouping === 'selected-fields'
                ? 'By n Plots — joined sum / derived selected-field denominator'
                : settings.quality
                  ? 'By n Plots — joined sum / qualified SU denominator'
                  : 'By n Plots — joined sum / physical SU denominator'
          : 'Characteristic — mean of joined non-NULL observations'}
      </dd>
    </div>
    <div>
      <dt>Report units</dt>
      <dd data-source-control="rptLvUnitGroups">
        {settings.unitGrouping === 'all-plots'
          ? ctrl.projectActive
            ? 'None — All plots from original Env rows'
            : 'None — All plots from Env/current selected list joins'
          : settings.unitGrouping === 'selected-fields'
            ? `Selected fields — ${settings.unitFields!.join(' & ')} (no separator)`
            : 'Site unit table — selected SU'}
      </dd>
    </div>
    <div>
      <dt>Constant species list</dt>
      <dd>
        {settings.constantSpeciesList
          ? ctrl.projectActive
            ? 'On — same original project list; thresholds bypassed'
            : 'On — same selected-SU list; thresholds bypassed'
          : 'Off — strict presence and mean-cover thresholds apply'}
      </dd>
    </div>
    <div>
      <dt>Show species with presence &gt; than</dt>
      <dd>{settings.presenceGreaterThan}%{settings.constantSpeciesList ? ' (not applied)' : ''}</dd>
    </div>
    <div>
      <dt>Show species with mean cover &gt; than</dt>
      <dd>{settings.meanCoverGreaterThan}%{settings.constantSpeciesList ? ' (not applied)' : ''}</dd>
    </div>
    <div>
      <dt>Order by</dt>
      <dd>
        {settings.constantSpeciesList
          ? `${ctrl.groupLabel}, then species (constant-list source order)`
          : settings.grouping === 'none'
            ? settings.order === 'presence'
              ? 'Descending presence, then species'
              : 'Species'
            : settings.order === 'presence'
              ? `${ctrl.groupLabel}, then descending presence`
              : `${ctrl.groupLabel}, then species`}
      </dd>
    </div>
    <div>
      <dt>
        {settings.selectedField !== undefined
          ? 'Show selected field'
          : settings.showSpeciesCode
            ? 'Show 8 char. code'
            : 'English names'}
      </dt>
      <dd>
        {settings.selectedField !== undefined
          ? `${JSON.stringify(settings.selectedField)} — typed list and matched report scalars shown separately`
          : settings.showSpeciesCode
            ? 'List and matched master codes shown separately; literal values are not truncated'
            : settings.showEnglishName
              ? 'List and matched report names shown separately'
              : 'Not shown'}
      </dd>
    </div>
    <div>
      <dt>Plot-quality filter</dt>
      <dd data-source-control="optEnforceQC">
        {settings.quality
          ? ctrl.projectActive
            ? 'On — original-SU qualification; original project tuples retained by plot existence'
            : 'On — selected-SU qualification'
          : ctrl.projectActive
            ? 'Off — original project tuples'
            : 'Off — all physical selected-SU memberships'}
      </dd>
    </div>
    {#if settings.quality}
      {#each [{ label: 'Site', field: 'SitePlotQuality', value: settings.quality.site }, { label: 'Vegetation', field: 'VegPlotQuality', value: settings.quality.veg }, { label: 'Soil', field: 'SoilPlotQuality', value: settings.quality.soil }] as criterion}
        <div>
          <dt>{criterion.label} quality minimum</dt>
          <dd data-source-control={criterion.field}>
            {JSON.stringify(criterion.value.minimum)}; include NULL/missing rank:
            {criterion.value.includeNull ? 'Yes' : 'No'}
          </dd>
        </div>
      {/each}
    {/if}
  </dl>
{/if}

<div class="lump-and-variant-controls" aria-label="Lump table and species variant controls">
  <div class="control-field">
    <label for="long-vegetation-lump-scope">Species Lump Table (report and workbook scope)</label>
    <div class="lump-picker-row">
      <select
        id="long-vegetation-lump-scope"
        data-source-control="rptLvLumpTable"
        disabled={ctrl.busy ||
          ctrl.operationHeld ||
          ctrl.workbookBarrier ||
          ctrl.preferenceBarrier ||
          ctrl.projectActive}
        value={ctrl.selectedWorkbookScope}
        onchange={(e) => actions.onSelectWorkbookScope(e.currentTarget.value)}
      >
        <option value="unlumped">None (unlumped)</option>
        {#each ctrl.lumpTables as table}
          <option value={`lump:${table}`}>{table}</option>
        {/each}
      </select>
      <button
        type="button"
        disabled={ctrl.busy || ctrl.operationHeld || ctrl.projectActive}
        onclick={actions.onRefreshLumpTables}
      >
        Refresh Lump Tables
      </button>
    </div>
  </div>
  <label class="toggle-field">
    <input
      id="long-vegetation-combine-variants"
      data-source-control="LVUseSppCodesOnly"
      type="checkbox"
      checked={ctrl.useSppCodesOnly}
      disabled={ctrl.busy || ctrl.operationHeld || ctrl.workbookBarrier || ctrl.preferenceBarrier}
      onchange={(e) => actions.onToggleUseSppCodesOnly(e.currentTarget.checked)}
    />
    <span>
      Combine species variants / subspecies{ctrl.settings?.combineVariants ? ' — active in saved options' : ''}
    </span>
  </label>
  <label class="toggle-field">
    <input
      id="long-vegetation-apply-exclusions"
      type="checkbox"
      checked={ctrl.applyExclusionsToReport}
      disabled={ctrl.busy || ctrl.operationHeld || ctrl.workbookBarrier || ctrl.preferenceBarrier || ctrl.projectActive}
      onchange={(e) => actions.onToggleApplyExclusions(e.currentTarget.checked)}
    />
    <span>Apply active unit exclusions / hierarchy breakpoints (<code>~</code>) on View Report</span>
  </label>
</div>

<details class="exclusion-panel">
  <summary>Site Unit Exclusions &amp; Hierarchy Breakpoints (~)</summary>
  <SiteUnitExclusionFilter
    contextId={owner.contextId}
    su={owner.su}
    hierarchy={owner.effectiveHierarchy}
    reportMode="long"
    onRulesChange={actions.onRulesChange}
    onLongPreview={actions.onLongPreview}
  />
</details>

{#if ctrl.exclusionSummary && ctrl.exclusionSummary.excludedUnits?.length}
  <p class="notice" role="status">
    Exclusion filter active: {ctrl.exclusionSummary.excludedUnits.length} site units excluded ({ctrl.exclusionSummary
      .excludedPlots}
    plots), {ctrl.exclusionSummary.retainedPlots} plots retained.
  </p>
{/if}

{#if ctrl.activeWorkbookReview}
  {@const reviewed = ctrl.activeWorkbookReview}
  <section class="workbook" aria-label="Reviewed workbook">
    <h2>Reviewed workbook — explicit {'scope' in reviewed && reviewed.scope ? reviewed.scope : 'unlumped'} scope</h2>
    <dl class="settings">
      <div>
        <dt>Reviewed creation date</dt>
        <dd>{reviewed.createdDate} (reused at publication)</dd>
      </div>
      <div>
        <dt>Quick report</dt>
        <dd>{reviewed.options.quickReport ? 'On' : 'Off — source print layout retained'}</dd>
      </div>
      <div>
        <dt>Space between groups</dt>
        <dd>{reviewed.options.spaceBetweenGroups ? 'On' : 'Off'}</dd>
      </div>
      <div>
        <dt>Report summary</dt>
        <dd>{reviewed.options.reportSummary ? 'On' : 'Off'}</dd>
      </div>
      <div>
        <dt>Reviewed bytes</dt>
        <dd>{reviewed.bytes}; SHA256 {reviewed.workbookSHA256}</dd>
      </div>
      <div>
        <dt>Source approval</dt>
        <dd>{reviewed.approvalHash}</dd>
      </div>
    </dl>
    <ul>
      {#each reviewed.sheets as sheet}
        <li>Unit {reportCellText(sheet.unit)} → worksheet “{sheet.name}”</li>
      {/each}
    </ul>
    {#each reviewed.skippedUnits as skipped}
      <p>Skipped unit {reportCellText(skipped.unit)}: {skipped.reason}.</p>
    {/each}
    {#if reviewed.summary}
      <p>
        ReportSummary: original Env rows {reviewed.summary.environmentRows};
        {#if 'sourcePlotRows' in reviewed.summary}
          original project non-NULL plot tuples {reviewed.summary.sourcePlotRows}. D:E original project tuples are an
          explicit desktop adaptation of the source's separate current-SU summary.
        {:else}
          {reviewed.preview.settings.unitGrouping === 'selected-fields'
            ? 'derived selected-field join rows (quality filters by plot existence)'
            : reviewed.preview.settings.unitGrouping === 'all-plots'
              ? 'derived Env/current-list join rows'
              : reviewed.preview.report.quality
                ? 'qualified weighted join occurrences'
                : 'non-NULL selected-SU PlotNumber rows'}
          {reviewed.summary.selectedPlotRows}.
        {/if}
        AllSpecs version {reportCellText(reviewed.summary.speciesVersion)}; metadata status
        {reviewed.summary.versionStatus}.
      </p>
      <details>
        <summary>Original AllSpecs Description definitions</summary>
        {#each reviewed.summary.versionDefinitions.rows ?? [] as row}
          <p>Physical row {row.rowId}: {row.cells?.map(reportCellText).join('; ')}</p>
        {:else}
          <p>No Description definitions; absence remains distinct from NULL or empty text.</p>
        {/each}
      </details>
    {/if}
    {#if !IS_WEB_READONLY}
      <label for="vegetation-workbook-destination">New XLSX output file (existing files are never replaced)</label>
      <textarea
        id="vegetation-workbook-destination"
        rows="2"
        disabled={ctrl.busy || ctrl.operationHeld || ctrl.workbookBarrier || ctrl.preferenceBarrier}
        bind:value={destination}></textarea>
    {/if}
    <button
      disabled={ctrl.busy ||
        ctrl.operationHeld ||
        ctrl.workbookBarrier ||
        ctrl.preferenceBarrier ||
        (!IS_WEB_READONLY && (!destination || !/\.xlsx$/i.test(destination)))}
      onclick={actions.onPublishWorkbook}
    >
      {#if IS_WEB_READONLY}
        {'scope' in reviewed && typeof reviewed.scope === 'string' && reviewed.scope !== 'unlumped'
          ? `Download reviewed ${reviewed.scope.replace(/^lump:/, '')} XLSX workbook`
          : 'Download reviewed unlumped XLSX workbook'}
      {:else}
        {'scope' in reviewed && typeof reviewed.scope === 'string' && reviewed.scope !== 'unlumped'
          ? `Publish reviewed ${reviewed.scope.replace(/^lump:/, '')} XLSX workbook`
          : 'Publish reviewed unlumped XLSX workbook'}
      {/if}
    </button>
    <p class="guidance">
      Report settings and layout remain read-only during export. Exporting writes a new .xlsx file and never overwrites
      an existing file. If an export is interrupted, inspect the destination file, acknowledge the notice, and review
      again before retrying.
    </p>
  </section>
{/if}

<style>
  .workbook,
  .lump-and-variant-controls,
  .exclusion-panel {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 0.75rem;
    min-width: 0;
  }
  .lump-and-variant-controls,
  .exclusion-panel {
    background: var(--vpro-canvas);
    border: 1px solid var(--vpro-border);
    border-radius: 0.4rem;
    padding: 0.75rem;
  }
  .control-field {
    display: grid;
    gap: 0.35rem;
    min-width: 0;
  }
  .lump-picker-row {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    align-items: center;
  }
  .lump-picker-row select {
    flex: 1 1 16rem;
  }
  .toggle-field {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-weight: 500;
    cursor: pointer;
  }
  .exclusion-panel summary {
    cursor: pointer;
    font-weight: 600;
    color: var(--vpro-navy);
  }
  textarea,
  select {
    box-sizing: border-box;
    min-width: 0;
    border: 1px solid var(--vpro-border);
    border-radius: 0.4rem;
    padding: 0.6rem;
    width: 100%;
    background: var(--vpro-surface);
    color: var(--vpro-ink);
  }
  h2 {
    color: var(--vpro-navy);
    font-size: 1.25rem;
  }
  dt {
    font-weight: 600;
    color: var(--vpro-navy);
  }
  .scope,
  .settings {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 19rem), 1fr));
    gap: 0.75rem 1.5rem;
  }
  .scope > div,
  .settings > div {
    min-width: 0;
    display: grid;
    gap: 0.25rem;
    align-content: start;
  }
  dd {
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  button {
    border: 1px solid var(--vpro-navy);
    border-radius: 0.4rem;
    padding: 0.5rem 0.75rem;
    background: var(--vpro-surface);
    color: var(--vpro-navy);
    font-weight: 600;
    cursor: pointer;
  }
  button:hover:not(:disabled) {
    background: var(--vpro-canvas);
  }
  button:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
  .notice {
    color: var(--vpro-info);
  }
  .guidance {
    color: var(--vpro-ink-secondary);
    font-size: 0.875rem;
  }
</style>
