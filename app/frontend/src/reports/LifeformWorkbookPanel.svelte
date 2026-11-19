<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
  import { ReadRequests } from '../shared/readRequests';
  import WorkbookPublicationSection from '../shared/WorkbookPublicationSection.svelte';
  import { lifeformCellText, lifeformRatioText, type LifeformSummaryOwner } from './lifeformSummary';
  import { speciesAttributeCountText } from './speciesAttributeSummary';
  import {
    lifeformWorkbookOptions,
    lifeformWorkbookPublicationSession,
    validateLifeformWorkbookReview,
    type ValidatedLifeformWorkbookReview,
  } from './lifeformWorkbook';
  import { notifications } from '../shell/notificationService.svelte';

  let {
    owner,
    disabled,
    onBusyChange,
  }: {
    owner: LifeformSummaryOwner;
    disabled: boolean;
    onBusyChange: (held: boolean) => void;
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

  function reportBusy() {
    onBusyChange(busy || publication.busy || publication.blocked);
  }

  const unsubscribe = session.subscribe(() => {
    publication = session.view();
    if (publication.busy) review = null;
    reportBusy();
  });

  function cancel() {
    generation++;
    reads.cancelAll();
    busy = false;
    review = null;
    reportBusy();
  }

  function changeDetail(index: number, selected: boolean) {
    if (!enabled || held) return;
    cancel();
    details = details.map((value, i) => (i === index ? selected : value));
    error = '';
  }

  async function getReview() {
    if (!enabled || held || owned.su === 'None' || owned.su === 'USysSuTableDynamic') return;
    cancel();
    const requestGeneration = generation;
    const requestedDetails = [...details];
    busy = true;
    error = '';
    reportBusy();
    try {
      const value = await reads.track(VegetationReportService.GetLifeformWorkbookReview(owned.contextId, JSON.stringify({ details: requestedDetails })));
      if (disposed || requestGeneration !== generation) return;
      review = validateLifeformWorkbookReview(value, owned, requestedDetails);
    } catch (cause) {
      if (!disposed && requestGeneration === generation) {
        error = `Workbook review unavailable; no file exported: ${String(cause)}`;
        notifications.error('Lifeform Summary workbook review failed', error, {
          category: 'reports',
          source: 'Lifeform Summary',
          contextTag: owned.project || undefined,
        });
      }
    } finally {
      if (!disposed && requestGeneration === generation) {
        busy = false;
        reportBusy();
      }
    }
  }

  async function publish() {
    if (!enabled || held || !review) return;
    error = '';
    try {
      await session.publish(review, destination, request =>
        VegetationReportService.ExportReviewedLifeformWorkbook(
          owned.contextId,
          JSON.stringify(request),
        ),
      );
      if (!disposed) {
        const s = session.view();
        const opts = {
          category: 'reports' as const,
          source: 'Lifeform Summary',
          contextTag: owned.project || undefined,
        };
        if (s.outcome?.status === 'published' && !s.error) {
          notifications.success(
            'Lifeform Summary workbook exported',
            s.outcome.path || s.requestedDestination || destination,
            opts,
          );
        } else if (s.error || s.outcome) {
          notifications.error(
            'Lifeform Summary workbook export failed',
            s.error ||
              `Export ${s.outcome?.status ?? 'failed'} for ${s.requestedDestination || destination}`,
            opts,
          );
        }
      }
    } catch (cause) {
      if (!disposed) {
        error = String(cause);
        notifications.error('Lifeform Summary workbook export failed', error, {
          category: 'reports',
          source: 'Lifeform Summary',
          contextTag: owned.project || undefined,
        });
      }
    }
  }

  function acknowledge() {
    if (publication.busy || !publication.blocked) return;
    try { session.acknowledge(); review = null; } catch (cause) {
      error = String(cause);
      notifications.error('Lifeform Summary workbook acknowledgement failed', error, {
        category: 'reports',
        source: 'Lifeform Summary',
        contextTag: owned.project || undefined,
      });
    }
  }

  onDestroy(() => {
    disposed = true;
    generation++;
    reads.cancelAll();
    busy = false;
    reportBusy();
    unsubscribe();
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
        <input
          type="checkbox"
          data-lifeform-workbook-option={option.field}
          checked={details[i]}
          onchange={event => changeDetail(i, event.currentTarget.checked)}
        />
        {option.label}
      </label>
    {/each}
  </fieldset>
  <div class="actions">
    <button
      data-lifeform-workbook-review
      disabled={!enabled || held || owned.su === 'None' || owned.su === 'USysSuTableDynamic'}
      onclick={getReview}
    >
      Review summary workbook
    </button>
    <button data-lifeform-workbook-cancel disabled={!busy || barrier} onclick={cancel}>
      Cancel review
    </button>
  </div>
  {#if review}
    <div data-lifeform-workbook-plan>
      <h3>Workbook preview</h3>
      <p>Project: {review.lifeform.report.project}. Site Unit Table: {review.lifeform.report.su}.</p>
      <p>Estimated size: {review.bytes} bytes. Checksum (SHA-256): {review.workbookSHA256}.</p>
      {#each review.lifeform.report.units as unit, i}
        {@const attributeUnit = review.attributes.report.units[i]}
        <section aria-label={`Source unit ${lifeformCellText(unit.code)}`}>
          <h4>Unit {lifeformCellText(unit.code)} → worksheet {review.sheets[i].name}</h4>
          <p>
            Plots: {unit.nPlots}. Unique species: {unit.uniqueSpecies}. Total species occurrences: {unit.occurrences}.
          </p>
          <div class="table-scroll">
            <table>
              <caption>All six attribute totals</caption>
              <thead>
                <tr><th>Attribute</th><th>Count</th><th>Number of plot occurrences</th></tr>
              </thead>
              <tbody>
                {#each attributeUnit.rows as row, j}
                  <tr>
                    <th>{review.attributes.report.definitions[j].label}</th>
                    <td>{speciesAttributeCountText(row.count)}</td>
                    <td>{row.plotOccurrences}</td>
                  </tr>
                {/each}
              </tbody>
            </table>
            <table>
              <caption>Lifeform summary</caption>
              <thead><tr><th>Lifeform</th><th>Presence</th><th>Mean Cover</th></tr></thead>
              <tbody>
                {#each unit.rows as row}
                  <tr>
                    <th>{row.lifeform}</th>
                    <td>{lifeformRatioText(row.presence)}</td>
                    <td>{lifeformRatioText(row.meanCover)}</td>
                  </tr>
                {/each}
              </tbody>
            </table>
            {#each review.details as selected, j}
              {#if selected}
                <table>
                  <caption>{lifeformWorkbookOptions[j].label}</caption>
                  <thead>
                    <tr>
                      {#each review.attributes.report.definitions[j].categories as category}
                        <th>{category}</th>
                      {/each}
                    </tr>
                  </thead>
                  <tbody>
                    <tr>
                      {#each attributeUnit.rows[j].categories as count}
                        <td>{speciesAttributeCountText(count)}</td>
                      {/each}
                    </tr>
                  </tbody>
                </table>
              {/if}
            {/each}
          </div>
        </section>
      {/each}
    </div>
  {/if}
  <label for="lifeform-workbook-destination">
    New XLSX output file (existing files are never replaced)
  </label>
  <textarea
    id="lifeform-workbook-destination"
    data-lifeform-workbook-destination
    rows="2"
    disabled={!enabled || held}
    bind:value={destination}
  ></textarea>
  <button
    data-lifeform-workbook-export
    disabled={!enabled || held || !review || !destination}
    onclick={publish}
  >
    Export reviewed summary workbook
  </button>
  <p class="guidance">
    Review prepares the workbook from your current Site Unit table without changing project data.
    All six attribute count totals are always included; check any optional detail tables to append them.
    Enter a new .xlsx file path — export never replaces an existing file, and failed or interrupted exports pause until acknowledged.
  </p>
</WorkbookPublicationSection>

<style>
  fieldset {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 280px), 1fr));
    gap: 0.5rem;
    min-width: 0;
    border: 1px solid var(--vpro-border);
    border-radius: 0.35rem;
    padding: 0.75rem;
  }
  .option {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
  }
  button {
    min-height: 2.5rem;
    padding: 0.5rem 0.85rem;
    border: 1px solid var(--vpro-navy);
    border-radius: 0.25rem;
    background: var(--vpro-navy);
    color: var(--vpro-surface);
    font-weight: 600;
    cursor: pointer;
  }
  button:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }
  input,
  textarea {
    box-sizing: border-box;
    min-width: 0;
    border: 1px solid var(--vpro-border);
    border-radius: 0.25rem;
    padding: 0.45rem;
    background: var(--vpro-surface);
    color: var(--vpro-ink);
  }
  textarea {
    width: 100%;
  }
  .table-scroll {
    overflow-x: auto;
    max-width: 100%;
  }
  table {
    border-collapse: collapse;
    margin-bottom: 0.75rem;
    width: 100%;
    background: var(--vpro-surface);
  }
  th,
  td {
    padding: 0.35rem 0.65rem;
    border: 1px solid var(--vpro-border);
    text-align: left;
  }
  thead th {
    background: var(--vpro-canvas);
    color: var(--vpro-navy);
  }
  caption {
    text-align: left;
    font-weight: 600;
    color: var(--vpro-navy);
  }
  .guidance {
    font-size: 0.9rem;
    color: var(--vpro-ink-secondary);
  }
</style>
