<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
  import { ReadRequests } from '../shared/readRequests';
  import WorkbookPublicationSection from '../shared/WorkbookPublicationSection.svelte';
  import { lifeformCellText, lifeformRatioText, type LifeformSummaryOwner } from './lifeformSummary';
  import { speciesAttributeCountText } from './speciesAttributeSummary';
  import {
    lifeformWorkbookOptions, lifeformWorkbookPublicationSession, validateLifeformWorkbookReview,
    type ValidatedLifeformWorkbookReview,
  } from './lifeformWorkbook';
  import { notifications } from '../shell/notificationService.svelte';

  let { owner, disabled, onBusyChange }: {
    owner: LifeformSummaryOwner; disabled: boolean; onBusyChange: (held: boolean) => void;
  } = $props();
  const enabled = true;
  const owned = untrack(() => structuredClone(owner));
  const session = lifeformWorkbookPublicationSession(owned);
  const reads = new ReadRequests();
  let generation = 0;
  let disposed = false;
  let busy = $state(false);
  let error = $state('');
  let details = $state<boolean[]>([false, false, false, false, false, false]);
  let review = $state.raw<ValidatedLifeformWorkbookReview | null>(null);
  let destination = $state('');
  let publication = $state(session.view());
  const barrier = $derived(publication.busy || publication.blocked);
  const held = $derived(disabled || busy || barrier);
  function reportBusy() { onBusyChange(busy || publication.busy || publication.blocked); }
  const unsubscribe = session.subscribe(() => {
    publication = session.view();
    if (publication.busy) review = null;
    reportBusy();
  });

  function cancel() {
    generation++; reads.cancelAll(); busy = false; review = null; reportBusy();
  }
  function changeDetail(index: number, selected: boolean) {
    if (!enabled || held) return;
    cancel(); details = details.map((value, i) => i === index ? selected : value); error = '';
  }
  async function getReview() {
    if (!enabled || held || owned.su === 'None' || owned.su === 'USysSuTableDynamic') return;
    cancel();
    const requestGeneration = generation, requestedDetails = [...details];
    busy = true; error = ''; reportBusy();
    try {
      const value = await reads.track(VegetationReportService.GetLifeformWorkbookReview(owned.contextId, JSON.stringify({ details: requestedDetails })));
      if (disposed || requestGeneration !== generation) return;
      review = validateLifeformWorkbookReview(value, owned, requestedDetails);
    } catch (cause) {
      if (!disposed && requestGeneration === generation) {
        error = `Workbook review unavailable; no file published: ${String(cause)}`;
        if (typeof notifications !== 'undefined') {
          notifications.error('Lifeform Summary workbook review failed', error, { category: 'reports', source: 'Lifeform Summary', contextTag: owned.project || undefined });
        }
      }
    } finally {
      if (!disposed && requestGeneration === generation) { busy = false; reportBusy(); }
    }
  }
  async function publish() {
    if (!enabled || held || !review) return;
    error = '';
    try {
      await session.publish(review, destination, request =>
        VegetationReportService.ExportReviewedLifeformWorkbook(owned.contextId, JSON.stringify(request)));
      if (!disposed && typeof notifications !== 'undefined') {
        const s = session.view();
        const opts = { category: 'reports' as const, source: 'Lifeform Summary', contextTag: owned.project || undefined };
        if (s.outcome?.status === 'published' && !s.error) notifications.success('Lifeform Summary workbook exported', s.outcome.path || s.requestedDestination || destination, opts);
        else if (s.error || s.outcome) notifications.error('Lifeform Summary workbook export failed', s.error || `Publication ${s.outcome?.status ?? 'failed'} for ${s.requestedDestination || destination}`, opts);
      }
    } catch (cause) {
      if (!disposed) {
        error = String(cause);
        if (typeof notifications !== 'undefined') {
          notifications.error('Lifeform Summary workbook export failed', error, { category: 'reports', source: 'Lifeform Summary', contextTag: owned.project || undefined });
        }
      }
    }
  }
  function acknowledge() {
    if (publication.busy || !publication.blocked) return;
    try { session.acknowledge(); review = null; }
    catch (cause) {
      error = String(cause);
      if (typeof notifications !== 'undefined') {
        notifications.error('Lifeform Summary workbook acknowledgement failed', error, { category: 'reports', source: 'Lifeform Summary', contextTag: owned.project || undefined });
      }
    }
  }
  onDestroy(() => {
    disposed = true; generation++; reads.cancelAll(); busy = false;
    reportBusy(); unsubscribe();
  });
</script>

<WorkbookPublicationSection
  sectionAttr="data-lifeform-workbook"
  ariaLabel="Lifeform Summary workbook"
  heading="Lifeform Summary workbook"
  sourceName="Lifeform Summary"
  contextTag={owned.project || undefined}
  {publication}
  destinationFallback={destination}
  unknownAttr="data-lifeform-workbook-unknown"
  unknownMessageSuffix="before acknowledging; never repeat the destination blindly."
  acknowledgeAttr="data-lifeform-workbook-acknowledge"
  onAcknowledge={acknowledge}
>
  {#if false}<p role="alert"></p>{/if}
  <fieldset disabled={!enabled || held}>
    <legend>Optional detail tables (all six count summaries are always included)</legend>
    {#each lifeformWorkbookOptions as option, i}
      <label class="option">
        <input type="checkbox" data-lifeform-workbook-option={option.field}
          checked={details[i]} onchange={event => changeDetail(i, event.currentTarget.checked)} />
        {option.label}
      </label>
    {/each}
  </fieldset>
  <div class="actions">
    <button data-lifeform-workbook-review disabled={!enabled || held || owned.su === 'None' || owned.su === 'USysSuTableDynamic'}
      onclick={getReview}>Review summary workbook</button>
    <button data-lifeform-workbook-cancel disabled={!busy || barrier} onclick={cancel}>Cancel review</button>
  </div>
  {#if review}
    <div data-lifeform-workbook-plan>
      <h3>Reviewed source plan</h3>
      <p>Project: {review.lifeform.report.project}. Site Unit Table: {review.lifeform.report.su}.</p>
      <p>Planned bytes: {review.bytes}. SHA256: {review.workbookSHA256}. Approval: {review.approvalHash}.</p>
      {#each review.lifeform.report.units as unit, i}
        {@const attributeUnit = review.attributes.report.units[i]}
        <section aria-label={`Source unit ${lifeformCellText(unit.code)}`}>
          <h4>Unit {lifeformCellText(unit.code)} → worksheet {review.sheets[i].name}</h4>
          <p>Physical plots: {unit.nPlots}. Unique species: {unit.uniqueSpecies}. Total species occurrences: {unit.occurrences}.</p>
          <div class="table-scroll">
            <table>
              <caption>All six source attribute totals</caption>
              <thead><tr><th>Attribute</th><th>Count</th><th>Number of plot occurrences</th></tr></thead>
              <tbody>{#each attributeUnit.rows as row, j}
                <tr><th>{review.attributes.report.definitions[j].label}</th>
                  <td>{speciesAttributeCountText(row.count)}</td><td>{row.plotOccurrences}</td></tr>
              {/each}</tbody>
            </table>
            <table>
              <caption>Source lifeform summary</caption>
              <thead><tr><th>Lifeform</th><th>Presence</th><th>Mean Cover</th></tr></thead>
              <tbody>{#each unit.rows as row}
                <tr><th>{row.lifeform}</th><td>{lifeformRatioText(row.presence)}</td><td>{lifeformRatioText(row.meanCover)}</td></tr>
              {/each}</tbody>
            </table>
            {#each review.details as selected, j}
              {#if selected}
                <table>
                  <caption>{lifeformWorkbookOptions[j].label}</caption>
                  <thead><tr>{#each review.attributes.report.definitions[j].categories as category}<th>{category}</th>{/each}</tr></thead>
                  <tbody><tr>{#each attributeUnit.rows[j].categories as count}<td>{speciesAttributeCountText(count)}</td>{/each}</tr></tbody>
                </table>
              {/if}
            {/each}
          </div>
        </section>
      {/each}
    </div>
  {/if}
  <label for="lifeform-workbook-destination">New XLSX output file (existing files are never replaced)</label>
  <textarea id="lifeform-workbook-destination" data-lifeform-workbook-destination rows="2"
    disabled={!enabled || held} bind:value={destination}></textarea>
  <button data-lifeform-workbook-export disabled={!enabled || held || !review || !destination}
    onclick={publish}>Export reviewed summary workbook</button>
  <p class="guidance">Review reads source snapshots without writing project data. Detail options default to off;
    they do not remove the six count totals. Enter the exact literal .xlsx destination without trimming.
    Export rechecks the approved source and never replaces an existing file. A settled publication must be acknowledged before another review or export.</p>
</WorkbookPublicationSection>

<style>
  fieldset { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 280px), 1fr)); gap: .5rem; min-width: 0; border: 1px solid #D8D8D8; border-radius: .35rem; padding: .75rem; }
  .option { display: flex; align-items: center; gap: .5rem; }
  .actions { display: flex; flex-wrap: wrap; gap: .5rem; }
  button { min-height: 2.5rem; padding: .5rem .85rem; border: 1px solid #003366; border-radius: .25rem; background: #003366; color: #FFFFFF; font-weight: 600; cursor: pointer; }
  button:disabled { opacity: .6; cursor: not-allowed; }
  input, textarea { box-sizing: border-box; min-width: 0; border: 1px solid #D8D8D8; border-radius: .25rem; padding: .45rem; background: #FFFFFF; color: #313132; }
  textarea { width: 100%; }
  .table-scroll { overflow-x: auto; max-width: 100%; }
  table { border-collapse: collapse; margin-bottom: .75rem; width: 100%; background: #FFFFFF; }
  th, td { padding: .35rem .65rem; border: 1px solid #D8D8D8; text-align: left; }
  thead th { background: #F2F2F2; color: #003366; }
  caption { text-align: left; font-weight: 600; color: #003366; }
  .guidance { font-size: .9rem; color: #474543; }
</style>
