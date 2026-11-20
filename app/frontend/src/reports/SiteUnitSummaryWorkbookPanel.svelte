<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { EnvironmentReportService } from '../../bindings/github.com/boostao/vpro/app';
  import type { ProjectSUScope as GoogleEarthScope } from '../shared/scope';
  import { ReadRequests, formatError } from '../shared/readRequests';
  import WorkbookPublicationSection from '../shared/WorkbookPublicationSection.svelte';
  import {
    siteUnitSummaryWorkbookPublicationSession,
    validateSiteUnitSummaryWorkbookReview,
    type ValidatedSiteUnitSummaryWorkbookReview,
  } from './siteUnitSummaryWorkbook';
  import {
    extendedSummaryWorkbookPublicationSession,
    validateExtendedSummaryWorkbookReview,
    sameExtendedSummaryWorkbookOptions,
    type ExtendedSummaryWorkbookOptions,
    type ValidatedExtendedSummaryWorkbookReview,
  } from './siteUnitSummaryExtendedWorkbook';
  import { reportCellText } from './longEnvironmentReport';
  import { notifications } from '../shell/notificationService.svelte';

  let {
    owner,
    method,
    disabled,
    onBusyChange,
    extendedOptions,
    siteUnitType = 1,
    allowConfiguredScope = false,
  }: {
    owner: GoogleEarthScope;
    method: number | null;
    disabled: boolean;
    onBusyChange: (held: boolean) => void;
    extendedOptions?: ExtendedSummaryWorkbookOptions | null;
    siteUnitType?: number | null;
    allowConfiguredScope?: boolean;
  } = $props();
  const extended = untrack(() => extendedOptions !== undefined);
  const owned = untrack(() => structuredClone(owner));
  const originalSession = siteUnitSummaryWorkbookPublicationSession(owned);
  const extendedSession = extended ? extendedSummaryWorkbookPublicationSession(owned) : null;
  const session = extendedSession ?? originalSession;
  const reads = new ReadRequests();
  let generation = 0;
  let disposed = false;
  let busy = $state(false);
  let error = $state('');
  let review = $state.raw<ValidatedSiteUnitSummaryWorkbookReview | ValidatedExtendedSummaryWorkbookReview | null>(null);
  let destination = $state('');
  let publication = $state(session.view());
  const validMethod = $derived(method === 1 || method === 2);
  const currentReview = $derived(
    review !== null &&
      ('environment' in review
        ? sameExtendedSummaryWorkbookOptions(review.options, extendedOptions ?? null)
        : review.preview.report.method === method)
  );
  const reviewedPreview = $derived(
    review === null ? null : 'environment' in review ? review.environment : review.preview
  );
  const reviewedSpecies = $derived(review !== null && 'species' in review ? review.species : null);
  const barrier = $derived(publication.busy || publication.blocked);
  const held = $derived(disabled || busy || barrier);
  const normalOwner = $derived(
    allowConfiguredScope
      ? siteUnitType === 3 || (owned.su !== 'None' && (siteUnitType === 2 || owned.su !== 'USysSuTableDynamic'))
      : owned.su !== 'None' && owned.su !== 'USysSuTableDynamic'
  );
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
  async function getReview() {
    if (held || !normalOwner || !validMethod || method === null || (extended && !extendedOptions)) return;
    cancel();
    const requestGeneration = generation,
      requestedMethod = method;
    const requestedOptions = extendedOptions ? structuredClone(extendedOptions) : null;
    const configuredScope = typeof allowConfiguredScope === 'boolean' && allowConfiguredScope;
    busy = true;
    error = '';
    reportBusy();
    try {
      if (extended && requestedOptions) {
        const value = await reads.track(
          EnvironmentReportService.GetSiteUnitSummaryExtendedWorkbookReview(
            owned.contextId,
            JSON.stringify(requestedOptions)
          )
        );
        if (
          disposed ||
          requestGeneration !== generation ||
          method !== requestedMethod ||
          !sameExtendedSummaryWorkbookOptions(requestedOptions, extendedOptions ?? null)
        )
          return;
        review = configuredScope
          ? validateExtendedSummaryWorkbookReview(value, owned, requestedOptions, true)
          : validateExtendedSummaryWorkbookReview(value, owned, requestedOptions);
      } else {
        const value = await reads.track(
          EnvironmentReportService.GetSiteUnitSummaryWorkbookReview(
            owned.contextId,
            JSON.stringify({ method: requestedMethod })
          )
        );
        if (disposed || requestGeneration !== generation || method !== requestedMethod) return;
        review = configuredScope
          ? validateSiteUnitSummaryWorkbookReview(value, owned, requestedMethod, true)
          : validateSiteUnitSummaryWorkbookReview(value, owned, requestedMethod);
      }
    } catch (cause) {
      if (!disposed && requestGeneration === generation && method === requestedMethod) {
        error = `Workbook review unavailable; no file published: ${formatError(cause)}`;
        notifications.error('Summary Environment workbook review failed', error, {
          category: 'reports',
          source: 'Summary Environment',
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
    if (held || !review || !currentReview || !validMethod || method === null) return;
    const configuredScope = typeof allowConfiguredScope === 'boolean' && allowConfiguredScope;
    const activeSession =
      'environment' in review && extendedSession && extendedOptions ? extendedSession : originalSession;
    error = '';
    try {
      if ('environment' in review && extendedSession && extendedOptions) {
        await extendedSession.publish(
          review,
          destination,
          (request) =>
            EnvironmentReportService.ExportReviewedSiteUnitSummaryExtendedWorkbook(
              owned.contextId,
              JSON.stringify(request)
            ),
          extendedOptions,
          configuredScope
        );
      } else if ('preview' in review && originalSession) {
        await originalSession.publish(
          review,
          destination,
          (request) =>
            EnvironmentReportService.ExportReviewedSiteUnitSummaryWorkbook(owned.contextId, JSON.stringify(request)),
          method,
          configuredScope
        );
      }
      if (!disposed) {
        const s = (activeSession ?? session).view();
        const opts = {
          category: 'reports' as const,
          source: 'Summary Environment',
          contextTag: owned.project || undefined,
        };
        if (s.outcome?.status === 'published' && !s.error)
          notifications.success(
            'Summary Environment workbook exported',
            s.outcome.path || s.requestedDestination || destination,
            opts
          );
        else if (s.error || s.outcome)
          notifications.error(
            'Summary Environment workbook export failed',
            s.error || `Publication ${s.outcome?.status ?? 'failed'} for ${s.requestedDestination || destination}`,
            opts
          );
      }
    } catch (cause) {
      if (!disposed) {
        error = formatError(cause);
        notifications.error('Summary Environment workbook export failed', error, {
          category: 'reports',
          source: 'Summary Environment',
          contextTag: owned.project || undefined,
        });
      }
    }
  }
  function acknowledge() {
    if (publication.busy || !publication.blocked) return;
    try {
      session.acknowledge();
      review = null;
    } catch (cause) {
      error = formatError(cause);
      notifications.error('Summary Environment workbook acknowledgement failed', error, {
        category: 'reports',
        source: 'Summary Environment',
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
  sectionAttr="data-site-unit-workbook"
  ariaLabel="Summary Environment workbook"
  heading="Summary Environment workbook"
  sourceName="Summary Environment"
  contextTag={owned.project || undefined}
  {publication}
  destinationFallback={destination}
  unknownAttr="data-site-unit-workbook-unknown"
  unknownMessageSuffix="before acknowledging; never repeat the destination blindly."
  acknowledgeAttr="data-site-unit-workbook-acknowledge"
  onAcknowledge={acknowledge}
>
  {#if review && !currentReview}
    <p role="alert" class="error">
      The selected method or criteria changed. Review the current options before publishing; the prior review cannot be
      used.
    </p>
  {/if}
  <p>Requested method: {method === 1 ? 'Mean (1)' : method === 2 ? 'Interquartile (2)' : 'Unavailable'}.</p>
  <div class="actions">
    <button
      data-site-unit-workbook-review
      disabled={held || !normalOwner || !validMethod || (extended && !extendedOptions)}
      onclick={getReview}>Review summary workbook</button
    >
    <button data-site-unit-workbook-cancel disabled={!busy || barrier} onclick={cancel}>Cancel review</button>
  </div>
  {#if review && currentReview && reviewedPreview}
    <div class="plan">
      <h3>Reviewed source plan</h3>
      <p>
        Project: {reviewedPreview.report.project}. Site Unit Table: {reviewedPreview.report.su}. Method: {reviewedPreview
          .report.method === 1
          ? 'Mean (1)'
          : 'Interquartile (2)'}. Saved method: {review.scope.savedMethod}. Normal Site Unit scope: {review.scope
          .siteUnitType}. Saved order: {review.scope.orderBy}. Saved species included: {review.scope.includeSpecies}.
      </p>
      {#if 'options' in review}
        <p>
          Requested grouping: {review.options.orderBy === 1
            ? 'Layers'
            : review.options.orderBy === 2
              ? 'Lifeforms'
              : 'Strata A-D'}. Species included: {review.options.includeSpecies}.
          {#if review.options.includeSpecies === 1}Cover calculation: {review.options.coverCalculation === 1
              ? 'All plots'
              : 'Present values'}. Criteria: {review.options.andOr === 1 ? 'AND' : 'OR'}; presence &gt; {review.options
              .presenceGreaterThan}; cover &gt; {review.options.coverGreaterThan}.{/if}
        </p>
      {/if}
      <p>
        Original memberships: {reviewedPreview.report.memberships.length}. Joined rows: {reviewedPreview.report.units.reduce(
          (sum, unit) => sum + unit.plots.length,
          0
        )}. Worksheets: {review.sheets.length}. Planned bytes: {review.bytes}.
      </p>
      {#each reviewedPreview.report.units as unit, unitIndex}
        <section class="unit" aria-label={`Site Unit ${unit.code || '(empty)'}`}>
          <h4>Site Unit: {unit.code === '' ? '(empty)' : unit.code}</h4>
          <p>
            Source long name: {unit.longName === null
              ? '(NULL / missing)'
              : unit.longName === ''
                ? '(empty)'
                : unit.longName}. Name status: {unit.nameStatus}. Name candidates: {unit.nameCandidates.length}. Joined
            rows: {unit.plots.length}. Worksheet: {review.sheets[review.sheets.length - 1 - unitIndex].name}.
          </p>
          {#if reviewedSpecies}
            {#each reviewedSpecies.units[unitIndex].groups as group}
              <h5>{group.caption}</h5>
              {#if group.rows.some((row) => row.included)}
                <div class="species-table">
                  <table>
                    <thead
                      ><tr
                        ><th scope="col">Scientific Name</th><th scope="col">Common Name</th><th scope="col">%Cover</th
                        ><th scope="col">%Presence</th></tr
                      ></thead
                    >
                    <tbody
                      >{#each group.rows.filter((row) => row.included) as row}
                        <tr
                          ><th scope="row" aria-label={`${reportCellText(row.scientificName)} (${row.species})`}
                            >{reportCellText(row.scientificName)}</th
                          >
                          <td>{reportCellText(row.englishName)}</td><td>{row.cover}</td><td>{row.presence}</td></tr
                        >
                      {/each}</tbody
                    >
                  </table>
                </div>
              {:else}<p>No species pass the strict formatted criteria.</p>{/if}
            {/each}
          {/if}
          <div class="summaries">
            {#each ['SITE', 'VEGETATION', 'SOILS'] as section}
              <table>
                <caption>{section} — {unit.code === '' ? '(empty unit)' : unit.code}</caption>
                <thead><tr><th scope="col">Summary field</th><th scope="col">Source value</th></tr></thead>
                <tbody>
                  {#each reviewedPreview.report.fields as field, index}
                    {#if field.section === section}
                      <tr
                        ><th scope="row">{field.label}</th><td
                          >{unit.values[index] === '' ? '(empty)' : unit.values[index]}</td
                        ></tr
                      >
                    {/if}
                  {/each}
                </tbody>
              </table>
            {/each}
          </div>
        </section>
      {/each}
    </div>
  {/if}
  <label class="destination"
    >Workbook destination (.xlsx, literal path)
    <input
      data-site-unit-workbook-destination
      type="text"
      bind:value={destination}
      disabled={held}
      autocomplete="off"
      spellcheck="false"
    />
  </label>
  <button
    data-site-unit-workbook-export
    disabled={held || !currentReview || !validMethod || !destination}
    onclick={publish}>Publish reviewed workbook</button
  >
  <p class="guidance">
    Review is read-only and cancellable. The selected method is an explicit override, not a saved-option change.
    {#if extended}Normal Site Unit summaries use the explicit grouping, inclusion and species criteria above.
    {:else}Only normal Site Unit layer-cover summaries without species are available.{/if} Enter an explicit .xlsx path; it
    is never trimmed or replaced automatically. Publication is irreversible; acknowledge every returned or unknown outcome
    before navigation, close or another publication. Unavailable workflows remain disabled.
  </p>
</WorkbookPublicationSection>

<style>
  h3,
  h4,
  p {
    margin: 0;
  }
  h3,
  h4 {
    color: var(--vpro-navy);
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
  }
  .plan,
  .unit {
    display: grid;
    gap: 0.75rem;
    min-width: 0;
  }
  .summaries {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 280px), 1fr));
    gap: 1rem;
    align-items: start;
  }
  .species-table {
    overflow-x: auto;
    max-width: 100%;
  }
  table {
    width: 100%;
    border-collapse: collapse;
    table-layout: fixed;
    background: var(--vpro-surface);
  }
  caption {
    text-align: left;
    font-weight: bold;
    padding: 0.5rem;
    color: var(--vpro-navy);
  }
  th,
  td {
    text-align: left;
    vertical-align: top;
    padding: 0.5rem;
    border-bottom: 1px solid var(--vpro-border);
    overflow-wrap: anywhere;
    white-space: pre-wrap;
  }
  thead th {
    background: var(--vpro-canvas);
    color: var(--vpro-navy);
  }
  .destination {
    display: grid;
    gap: 0.25rem;
  }
  input {
    box-sizing: border-box;
    width: 100%;
    min-width: 0;
    padding: 0.45rem;
    border: 1px solid var(--vpro-border);
    border-radius: 0.25rem;
    background: var(--vpro-surface);
    color: var(--vpro-ink);
  }
  button {
    min-height: 2.5rem;
    padding: 0.45rem 0.85rem;
    border: 1px solid var(--vpro-navy);
    border-radius: 0.25rem;
    background: var(--vpro-navy);
    color: var(--vpro-surface);
    font-weight: 600;
    cursor: pointer;
  }
  button:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
  .error {
    color: var(--vpro-error);
    overflow-wrap: anywhere;
    font-weight: 600;
  }
  .guidance {
    font-size: 0.875rem;
    color: var(--vpro-ink-secondary);
  }
</style>
