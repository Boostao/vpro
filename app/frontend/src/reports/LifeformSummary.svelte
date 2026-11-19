<script lang="ts">
  import { onDestroy } from 'svelte';
  import { VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
  import { ReadRequests } from '../shared/readRequests';
  import {
    validateLifeformSummary,
    lifeformCellText,
    lifeformRatioText,
    type LifeformSummaryPreview,
  } from './lifeformSummary';
  import {
    validateSpeciesAttributeSummary,
    speciesAttributeCountText,
    type SpeciesAttributeSummaryPreview,
  } from './speciesAttributeSummary';
  import LifeformWorkbookPanel from './LifeformWorkbookPanel.svelte';
  import { notifications } from '../shell/notificationService.svelte';

  let {
    contextId,
    project,
    projectPath,
    su,
    suPath,
    onBusyChange,
  }: {
    contextId: string;
    project: string;
    projectPath: string;
    su: string;
    suPath: string;
    onBusyChange: (busy: boolean) => void;
  } = $props();

  const enabled = true;
  const reads = new ReadRequests();
  let generation = 0;
  let busy = $state(false);
  let workbookBusy = $state(false);
  let error = $state('');
  let unitScope = $state<'su' | 'hierarchy'>('su');
  let breakpointPolicy = $state<'lowest' | 'highest'>('lowest');
  let preview = $state<LifeformSummaryPreview | null>(null);
  let attributePreview = $state<SpeciesAttributeSummaryPreview | null>(null);
  const ownerKey = $derived(JSON.stringify([contextId, project, projectPath, su, suPath]));
  let previewKey = $state('');
  let attributeKey = $state('');
  const currentPreview = $derived(previewKey === ownerKey ? preview : null);
  const currentAttributes = $derived(
    attributeKey === ownerKey || (!attributeKey && previewKey === ownerKey) ? attributePreview : null,
  );
  const scopeBlocked = $derived(
    unitScope === 'su' ? su === 'None' || su === 'USysSuTableDynamic' : su === 'None',
  );

  function reportBusy() {
    onBusyChange(busy || workbookBusy);
  }

  function cancel() {
    generation++;
    reads.cancelAll();
    busy = false;
    reportBusy();
  }

  async function show(kind: 'lifeform' | 'attributes') {
    if (!enabled || busy || workbookBusy || scopeBlocked) return;
    cancel();
    const request = generation;
    const key = ownerKey;
    const owner = { contextId, project, projectPath, su, suPath };
    busy = true;
    error = '';
    if (kind === 'attributes') attributePreview = null;
    else preview = null;
    reportBusy();
    try {
      const value = await reads.track<unknown>(kind === 'attributes'
        ? (unitScope === 'hierarchy'
            ? VegetationReportService.PreviewSpeciesAttributeSummaryWithHierarchyBreakpoints(contextId, breakpointPolicy)
            : VegetationReportService.PreviewSpeciesAttributeSummary(contextId))
        : (unitScope === 'hierarchy'
            ? VegetationReportService.PreviewLifeformSummaryWithHierarchyBreakpoints(contextId, breakpointPolicy)
            : VegetationReportService.PreviewLifeformSummary(contextId)));
      if (request !== generation || key !== ownerKey) return;
      if (kind === 'attributes') {
        attributePreview =
          unitScope === 'hierarchy'
            ? validateSpeciesAttributeSummary(value, owner, true)
            : validateSpeciesAttributeSummary(value, owner);
        attributeKey = key;
      } else {
        preview =
          unitScope === 'hierarchy'
            ? validateLifeformSummary(value, owner, true)
            : validateLifeformSummary(value, owner);
        previewKey = key;
      }
    } catch (cause) {
      if (request === generation && key === ownerKey) {
        error = `${kind === 'attributes' ? 'Species attribute summary' : 'Lifeform Summary'} unavailable: ${String(cause)}`;
        notifications.error(
          kind === 'attributes' ? 'Species attribute summary failed' : 'Lifeform Summary failed',
          error,
          {
            category: 'reports',
            source: 'Lifeform Summary',
            contextTag: (typeof project === 'string' && project) || undefined,
          },
        );
      }
    } finally {
      if (request === generation) {
        busy = false;
        reportBusy();
      }
    }
  }

  onDestroy(cancel);
</script>

<section class="lifeform-summary" data-lifeform-summary aria-label="Lifeform Summary">
  <header
    class="sticky top-0 z-20 bg-white/95 backdrop-blur-xs py-2 border-b border-vpro-border report-sticky-bar"
    data-report-sticky-bar
  >
    <h1>Lifeform Summary</h1>
    <div class="actions">
      {#if unitScope === 'su'}
        <button onclick={() => show('lifeform')} disabled={!enabled || busy || workbookBusy || su === 'None' || su === 'USysSuTableDynamic'}>
          Preview Lifeform Summary
        </button>
        <button onclick={() => show('attributes')} disabled={!enabled || busy || workbookBusy || su === 'None' || su === 'USysSuTableDynamic'}>
          Preview species attribute summaries
        </button>
      {:else}
        <button data-lifeform-hierarchy-preview onclick={() => show('lifeform')} disabled={!enabled || busy || workbookBusy || su === 'None'}>
          Preview Lifeform (~) Summary
        </button>
        <button data-attributes-hierarchy-preview onclick={() => show('attributes')} disabled={!enabled || busy || workbookBusy || su === 'None'}>
          Preview species attribute (~) summaries
        </button>
      {/if}
      {#if busy}<button onclick={cancel}>Cancel preview</button>{/if}
    </div>
  </header>
  <p>Project {project}; active Site Unit table: {su}.</p>
  <div class="scope-controls">
    <label>
      Unit Scope
      <select
        value={unitScope}
        onchange={event => {
          unitScope = (event.currentTarget as HTMLSelectElement).value as 'su' | 'hierarchy';
        }}
        disabled={busy || workbookBusy}
        data-lifeform-unit-scope
      >
        <option value="su">Selected Site Unit Table</option>
        <option value="hierarchy">Hierarchy Breakpoints (~)</option>
      </select>
    </label>
    {#if unitScope === 'hierarchy'}
      <label>
        Breakpoint Policy
        <select
          value={breakpointPolicy}
          onchange={event => {
            breakpointPolicy = (event.currentTarget as HTMLSelectElement).value as 'lowest' | 'highest';
          }}
          disabled={busy || workbookBusy}
          data-lifeform-breakpoint-policy
        >
          <option value="lowest">Lowest (~) Breakpoint</option>
          <option value="highest">Highest (~) Breakpoint</option>
        </select>
      </label>
    {/if}
  </div>
  {#if scopeBlocked}
    <p>
      {unitScope === 'hierarchy'
        ? 'Select a Site Unit table in the sidebar to group units by hierarchy (~) breakpoints.'
        : 'Select a Site Unit table in the sidebar, or switch Unit Scope to Hierarchy Breakpoints (~).'}
    </p>
  {/if}
  <LifeformWorkbookPanel owner={{ contextId, project, projectPath, su, suPath }} disabled={busy}
    onBusyChange={(held) => { workbookBusy = held; reportBusy(); }} />
  {#if currentPreview}
    {#each currentPreview.report.units as unit}
      <article>
        <h2>Unit: {lifeformCellText(unit.code)}</h2>
        <dl>
          <div><dt>Plots (nPlots)</dt><dd>{unit.nPlots}</dd></div>
          <div><dt>Number of unique species</dt><dd>{unit.uniqueSpecies}</dd></div>
          <div><dt>Total species occurrences</dt><dd>{unit.occurrences}</dd></div>
        </dl>
        <div class="table-scroll">
          <table>
            <caption>Lifeform presence and mean cover for {lifeformCellText(unit.code)}</caption>
            <thead>
              <tr>
                <th scope="col">Lifeform</th>
                <th scope="col">Catalogue label</th>
                <th scope="col">Definition</th>
                <th scope="col">Short name</th>
                <th scope="col">Presence</th>
                <th scope="col">Mean Cover</th>
              </tr>
            </thead>
            <tbody>
              {#each unit.rows as row, i}
                <tr><th scope="row">{row.lifeform}</th><td>{lifeformCellText(currentPreview.report.catalogue[i].label)}</td>
                  <td>{lifeformCellText(currentPreview.report.catalogue[i].definition)}</td><td>{lifeformCellText(currentPreview.report.catalogue[i].shortName)}</td>
                  <td>{lifeformRatioText(row.presence)}</td><td>{lifeformRatioText(row.meanCover)}</td></tr>
              {/each}
            </tbody>
          </table>
        </div>
      </article>
    {/each}
    {#if currentPreview.report.units.length === 0}
      <p>No plots are assigned to units in the active Site Unit table.</p>
    {/if}
  {/if}
  {#if currentAttributes}
    {#each currentAttributes.report.units as unit}
      <article data-species-attribute-summary>
        <h2>Species attributes — Unit: {lifeformCellText(unit.code)}</h2>
        <p>Plots (nPlots): {unit.nPlots}</p>
        <div class="table-scroll">
          <table>
            <caption>Attribute counts for {lifeformCellText(unit.code)}</caption>
            <thead>
              <tr>
                <th scope="col">Attribute</th>
                <th scope="col">Count</th>
                <th scope="col">Number of plot occurrences</th>
              </tr>
            </thead>
            <tbody>
              {#each unit.rows as row, i}
                <tr><th scope="row">{currentAttributes.report.definitions[i].label}</th><td>{speciesAttributeCountText(row.count)}</td><td>{row.plotOccurrences}</td></tr>
              {/each}
            </tbody>
          </table>
        </div>
        {#each unit.rows as row, i}
          <div class="table-scroll">
            <table>
              <caption>{currentAttributes.report.definitions[i].label} details for {lifeformCellText(unit.code)}</caption>
              <thead>
                <tr>
                  {#each currentAttributes.report.definitions[i].categories as category}
                    <th scope="col">{category}</th>
                  {/each}
                </tr>
              </thead>
              <tbody>
                <tr>
                  {#each row.categories as count}<td>{speciesAttributeCountText(count)}</td>{/each}
                </tr>
              </tbody>
            </table>
          </div>
        {/each}
      </article>
    {/each}
    {#if currentAttributes.report.units.length === 0}
      <p>No plots are assigned to units in the active Site Unit table.</p>
    {/if}
  {/if}
  <p class="guidance">
    Previews lifeform presence, mean cover, and species attribute counts by Site Unit without changing project data or settings.
    Lifeform and Species Attribute tables can be viewed side by side.
    Choose Hierarchy Breakpoints (~) to roll plots up to the lowest or highest (~) group in the active hierarchy.
  </p>
</section>

<style>
  .lifeform-summary { display: grid; gap: 1rem; padding: 1rem; background: var(--vpro-canvas); color: var(--vpro-ink); min-width: 0; }
  .report-sticky-bar { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: .75rem; padding-inline: .75rem; border-radius: .35rem; }
  h1, h2 { margin: 0; color: var(--vpro-navy); }
  p { margin: 0; }
  .scope-controls { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 280px), 1fr)); gap: .75rem; background: var(--vpro-surface); padding: .85rem; border: 1px solid var(--vpro-border); border-radius: .5rem; }
  .scope-controls label { display: flex; flex-direction: column; gap: .35rem; min-width: 0; font-weight: 500; color: var(--vpro-ink); }
  .scope-controls select { box-sizing: border-box; width: 100%; min-width: 0; padding: .5rem; border: 1px solid var(--vpro-border); border-radius: .25rem; background: var(--vpro-surface); color: var(--vpro-ink); }
  .actions { display: flex; gap: .75rem; flex-wrap: wrap; align-items: center; }
  .actions button { min-height: 2.5rem; padding: .5rem .85rem; border: 1px solid var(--vpro-navy); border-radius: .25rem; background: var(--vpro-navy); color: var(--vpro-surface); font-weight: 600; cursor: pointer; }
  .actions button:hover:not(:disabled) { background: var(--vpro-navy-dark); border-color: var(--vpro-navy-dark); }
  .actions button:disabled { opacity: .6; cursor: not-allowed; }
  article { display: grid; gap: .75rem; padding: 1rem; background: var(--vpro-surface); border: 1px solid var(--vpro-border); border-radius: .5rem; min-width: 0; }
  dl { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 280px), 1fr)); gap: .75rem; margin: 0; }
  dt { font-weight: 600; color: var(--vpro-navy); }
  dd { margin: .25rem 0 0; }
  .table-scroll { overflow-x: auto; max-width: 100%; }
  table { border-collapse: collapse; width: 100%; background: var(--vpro-surface); }
  th, td { padding: .5rem; border-bottom: 1px solid var(--vpro-border); text-align: left; }
  thead th { background: var(--vpro-canvas); color: var(--vpro-navy); }
  caption { text-align: left; padding-bottom: .5rem; font-weight: 600; color: var(--vpro-navy); }
  .guidance { font-size: .9rem; color: var(--vpro-ink-secondary); }
</style>
