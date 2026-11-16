<script lang="ts">
  import { onDestroy } from 'svelte';
  import { VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
  import { ReadRequests } from '../shared/readRequests';
  import { validateLifeformSummary, lifeformCellText, lifeformRatioText, type LifeformSummaryPreview } from './lifeformSummary';
  import { validateSpeciesAttributeSummary, speciesAttributeCountText, type SpeciesAttributeSummaryPreview } from './speciesAttributeSummary';
  import LifeformWorkbookPanel from './LifeformWorkbookPanel.svelte';
  import { notifications } from '../shell/notificationService.svelte';

  let { contextId, project, projectPath, su, suPath, onBusyChange }: {
    contextId: string; project: string; projectPath: string; su: string; suPath: string;
    onBusyChange: (busy: boolean) => void;
  } = $props();
  const enabled = true;
  const attributesEnabled = true;
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
  const currentAttributes = $derived((attributeKey === ownerKey || (!attributeKey && previewKey === ownerKey)) ? attributePreview : null);
  const scopeBlocked = $derived(unitScope === 'su' ? (su === 'None' || su === 'USysSuTableDynamic') : su === 'None');
  function reportBusy() { onBusyChange(busy || workbookBusy); }
  function cancel() { generation++; reads.cancelAll(); busy = false; reportBusy(); }
  async function show(kind: 'lifeform' | 'attributes') {
    if (!enabled || kind === 'attributes' && !attributesEnabled || busy || workbookBusy || scopeBlocked) return;
    cancel(); const request = generation, key = ownerKey;
    const owner = { contextId, project, projectPath, su, suPath };
    busy = true; error = '';
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
        attributePreview = unitScope === 'hierarchy'
          ? validateSpeciesAttributeSummary(value, owner, true)
          : validateSpeciesAttributeSummary(value, owner);
        attributeKey = key;
      } else {
        preview = unitScope === 'hierarchy'
          ? validateLifeformSummary(value, owner, true)
          : validateLifeformSummary(value, owner);
        previewKey = key;
      }
    } catch (cause) {
      if (request === generation && key === ownerKey) {
        error = `${kind === 'attributes' ? 'Species attribute summary' : 'Lifeform Summary'} unavailable; no data or configuration writes: ${String(cause)}`;
        if (typeof notifications !== 'undefined') {
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
      }
    } finally {
      if (request === generation) { busy = false; reportBusy(); }
    }
  }
  onDestroy(cancel);
</script>

<section class="lifeform-summary" data-lifeform-summary aria-label="Lifeform Summary">
  <header class="sticky top-0 z-20 bg-white/95 backdrop-blur-xs py-2 border-b border-[#D8D8D8] report-sticky-bar" data-report-sticky-bar>
    <h1>Lifeform Summary</h1>
    <div class="actions">
      {#if unitScope === 'su'}
        <button onclick={() => show('lifeform')} disabled={!enabled || busy || workbookBusy || su === 'None' || su === 'USysSuTableDynamic'}>Preview Lifeform Summary</button>
        <button onclick={() => show('attributes')} disabled={!enabled || !attributesEnabled || busy || workbookBusy || su === 'None' || su === 'USysSuTableDynamic'}>Preview species attribute summaries</button>
      {:else}
        <button data-lifeform-hierarchy-preview onclick={() => show('lifeform')} disabled={!enabled || busy || workbookBusy || su === 'None'}>Preview Lifeform (~) Summary</button>
        <button data-attributes-hierarchy-preview onclick={() => show('attributes')} disabled={!enabled || !attributesEnabled || busy || workbookBusy || su === 'None'}>Preview species attribute (~) summaries</button>
      {/if}
      {#if busy}<button onclick={cancel}>Cancel preview</button><p role="status">Reading owned project and SU…</p>{/if}
    </div>
  </header>
  {#if error}<p role="alert" class="error">{error}</p>{/if}
  <p>Project {project}; selected SU {su}. Profile navigation does not filter this report.</p>
  <div class="scope-controls">
    <label>Unit Scope
      <select value={unitScope} onchange={event => { unitScope = (event.currentTarget as HTMLSelectElement).value as 'su' | 'hierarchy'; }} disabled={busy || workbookBusy} data-lifeform-unit-scope>
        <option value="su">Selected Site Unit Table</option>
        <option value="hierarchy">Hierarchy Breakpoints (~)</option>
      </select>
    </label>
    {#if unitScope === 'hierarchy'}
      <label>Breakpoint Policy
        <select value={breakpointPolicy} onchange={event => { breakpointPolicy = (event.currentTarget as HTMLSelectElement).value as 'lowest' | 'highest'; }} disabled={busy || workbookBusy} data-lifeform-breakpoint-policy>
          <option value="lowest">Lowest (~) Breakpoint</option>
          <option value="highest">Highest (~) Breakpoint</option>
        </select>
      </label>
    {/if}
  </div>
  {#if scopeBlocked}<p>{unitScope === 'hierarchy' ? 'An active Site Unit selection or USysSuTableDynamic (not None) is required for hierarchy breakpoint resolution.' : 'A selected normal SU is required. Switch Unit Scope to Hierarchy Breakpoints (~) for breakpoint resolution.'}</p>{/if}
  <LifeformWorkbookPanel owner={{ contextId, project, projectPath, su, suPath }} disabled={busy}
    onBusyChange={(held) => { workbookBusy = held; reportBusy(); }} />
  {#if currentPreview}
    {#each currentPreview.report.units as unit}
      <article>
        <h2>Unit: {lifeformCellText(unit.code)}</h2>
        <dl>
          <div><dt>nPlots (physical non-NULL PlotNumber count)</dt><dd>{unit.nPlots}</dd></div>
          <div><dt>Number of unique species</dt><dd>{unit.uniqueSpecies}</dd></div>
          <div><dt>Total species occurrences</dt><dd>{unit.occurrences}</dd></div>
        </dl>
        <div class="table-scroll">
          <table>
            <caption>Lifeform presence and mean cover for {lifeformCellText(unit.code)}</caption>
            <thead><tr><th scope="col">Lifeform</th><th scope="col">Catalogue label</th><th scope="col">Definition</th><th scope="col">Short name</th><th scope="col">Presence</th><th scope="col">Mean Cover</th></tr></thead>
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
    {#if currentPreview.report.units.length === 0}<p>No physical SU memberships.</p>{/if}
  {/if}
  {#if currentAttributes}
    {#each currentAttributes.report.units as unit}
      <article data-species-attribute-summary>
        <h2>Species attributes — Unit: {lifeformCellText(unit.code)}</h2>
        <p>nPlots (physical non-NULL PlotNumber count): {unit.nPlots}</p>
        <div class="table-scroll">
          <table>
            <caption>Attribute counts for {lifeformCellText(unit.code)}</caption>
            <thead><tr><th scope="col">Attribute</th><th scope="col">Count</th><th scope="col">Number of plot occurrences</th></tr></thead>
            <tbody>{#each unit.rows as row, i}<tr><th scope="row">{currentAttributes.report.definitions[i].label}</th><td>{speciesAttributeCountText(row.count)}</td><td>{row.plotOccurrences}</td></tr>{/each}</tbody>
          </table>
        </div>
        {#each unit.rows as row, i}
          <div class="table-scroll">
            <table>
              <caption>{currentAttributes.report.definitions[i].label} details for {lifeformCellText(unit.code)}</caption>
              <thead><tr>{#each currentAttributes.report.definitions[i].categories as category}<th scope="col">{category}</th>{/each}</tr></thead>
              <tbody><tr>{#each row.categories as count}<td>{speciesAttributeCountText(count)}</td>{/each}</tr></tbody>
            </table>
          </div>
        {/each}
      </article>
    {/each}
    {#if currentAttributes.report.units.length === 0}<p>No physical SU memberships.</p>{/if}
  {/if}
  <p class="guidance">Read-only preview: no database, configuration or Excel writes. Lifeform and Species Attribute previews stay independent without clearing each other. Lifeform global inserted rows rejoin SU by PlotNumber, retaining duplicate and cross-unit weights. Attribute summaries instead join raw physical vegetation/SU/attribute rows; repeated observations and definitions retain their weights. Hierarchy Breakpoints (~) resolves unit memberships at lowest or highest '~' nodes against the active SU/Hierarchy.</p>
</section>

<style>
  .lifeform-summary { display: grid; gap: 1rem; padding: 1rem; background: #F2F2F2; color: #313132; min-width: 0; }
  .report-sticky-bar { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: .75rem; padding-inline: .75rem; border-radius: .35rem; }
  h1, h2 { margin: 0; color: #003366; }
  p { margin: 0; }
  .scope-controls { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 280px), 1fr)); gap: .75rem; background: #FFFFFF; padding: .85rem; border: 1px solid #D8D8D8; border-radius: .5rem; }
  .scope-controls label { display: flex; flex-direction: column; gap: .35rem; min-width: 0; font-weight: 500; color: #313132; }
  .scope-controls select { box-sizing: border-box; width: 100%; min-width: 0; padding: .5rem; border: 1px solid #D8D8D8; border-radius: .25rem; background: #FFFFFF; color: #313132; }
  .actions { display: flex; gap: .75rem; flex-wrap: wrap; align-items: center; }
  .actions button { min-height: 2.5rem; padding: .5rem .85rem; border: 1px solid #003366; border-radius: .25rem; background: #003366; color: #FFFFFF; font-weight: 600; cursor: pointer; }
  .actions button:hover:not(:disabled) { background: #002244; border-color: #002244; }
  .actions button:disabled { opacity: .6; cursor: not-allowed; }
  article { display: grid; gap: .75rem; padding: 1rem; background: #FFFFFF; border: 1px solid #D8D8D8; border-radius: .5rem; min-width: 0; }
  dl { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 280px), 1fr)); gap: .75rem; margin: 0; }
  dt { font-weight: 600; color: #003366; } dd { margin: .25rem 0 0; }
  .table-scroll { overflow-x: auto; max-width: 100%; }
  table { border-collapse: collapse; width: 100%; background: #FFFFFF; }
  th, td { padding: .5rem; border-bottom: 1px solid #D8D8D8; text-align: left; }
  thead th { background: #F2F2F2; color: #003366; }
  caption { text-align: left; padding-bottom: .5rem; font-weight: 600; color: #003366; }
  .error { color: #D8292F; font-weight: 600; } .guidance { font-size: .9rem; color: #474543; }
</style>
