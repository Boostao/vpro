<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
  import { ReadRequests, formatError, trackIfCancellable } from '../shared/readRequests';
  import { notifications } from '../shell/notificationService.svelte';
  import WorkbookPublicationSection from '../shared/WorkbookPublicationSection.svelte';
  import SummaryVegetationWorkbookReviewPlan from './parts/SummaryVegetationWorkbookReviewPlan.svelte';
  import {
    summaryVegetationReferenceGroupingAvailable,
    summaryVegetationUnanimousCommonAvailable,
    type SummaryVegetationOwner,
  } from './summaryVegetation';
  import { summaryEnvironmentalLifeformEnabled } from './summaryVegetationEnvironmentalDesktop';
  import {
    summaryVegetationWorkbookSession,
    sameSummaryWorkbookOptions,
    summaryWorkbookScopeOptions,
    type SummaryWorkbookCalculation,
  } from './summaryVegetationWorkbook';

  let {
    owner,
    calculation,
    disabled,
    savedPresentation = null,
    onPreferencesLoaded,
    onBusyChange,
  }: {
    owner: SummaryVegetationOwner;
    calculation: SummaryWorkbookCalculation;
    disabled: boolean;
    savedPresentation?: {
      title: string;
      includeEnv: boolean;
      createSummary: boolean;
      showCommon: boolean;
      showGuide: boolean;
      constancy?: boolean;
    } | null;
    onPreferencesLoaded?: (options: ReturnType<ReturnType<typeof summaryVegetationWorkbookSession>['options']>) => void;
    onBusyChange: (held: boolean) => void;
  } = $props();

  const owned = untrack(() => structuredClone(owner));
  const session = summaryVegetationWorkbookSession(owned);
  const workbookReads = new ReadRequests();
  const environmentEnabled = summaryEnvironmentalLifeformEnabled;
  let viewState = $state.raw(session.view());
  let error = $state('');
  let unitPage = $state(0);
  let referencePage = $state(0);
  const unitPageSize = 50;
  const barrier = $derived(viewState.publication.busy || viewState.publication.blocked);
  const held = $derived(disabled || viewState.reviewing || barrier);
  const grouped = $derived(calculation.groupAndOrder !== undefined);
  const constancy = $derived(calculation.constancy === true);
  const effectiveReferences = $derived(constancy || viewState.includeReferences);
  const effectiveCommon = $derived(!constancy && viewState.showCommon);
  const effectiveGuide = $derived(!constancy && viewState.useGuideNames);
  const unanimousCommon = $derived(
    effectiveReferences &&
      summaryVegetationUnanimousCommonAvailable(
        calculation.groupAndOrder ?? 11,
        calculation.display,
        effectiveCommon || effectiveGuide
      )
  );
  const groupingUnavailable = $derived(
    grouped &&
      effectiveReferences &&
      !unanimousCommon &&
      !summaryVegetationReferenceGroupingAvailable(calculation.groupAndOrder ?? 11, effectiveCommon || effectiveGuide)
  );
  const modeUnavailable = $derived(groupingUnavailable || (viewState.includeEnv && !environmentEnabled));
  const groupLabel = $derived(
    !grouped
      ? 'Layer'
      : calculation.groupAndOrder === 12
        ? 'Strata'
        : calculation.groupAndOrder === 13
          ? 'Lifeform'
          : calculation.groupAndOrder === 14
            ? 'None'
            : 'Unsupported'
  );
  const currentReview = $derived(
    !!viewState.review &&
      sameSummaryWorkbookOptions(viewState.review.options, {
        average: calculation.average,
        display: calculation.display,
        showClass: calculation.showClass,
        title: viewState.title,
        includeEnv: viewState.includeEnv,
        ...(grouped ? { groupAndOrder: calculation.groupAndOrder } : {}),
        ...(constancy ? { constancy: true } : {}),
        ...(unanimousCommon ? { unanimousCommon: true } : {}),
        ...summaryWorkbookScopeOptions(calculation),
        ...(viewState.includeAncillary ? { ancillary: { createSummary: viewState.createSummary } } : {}),
        ...(effectiveReferences ? { references: { showCommon: effectiveCommon, useGuideNames: effectiveGuide } } : {}),
      })
  );
  const unsubscribe = session.subscribe(() => {
    viewState = session.view();
    onBusyChange(session.held());
  });

  function edit(field: 'title' | 'destination', raw: string) {
    if (held) return;
    error = '';
    try {
      session.edit(field, raw);
    } catch (cause) {
      error = formatError(cause);
    }
  }
  function includeEnvironment(event: Event) {
    if (held || !environmentEnabled) return;
    error = '';
    try {
      session.includeEnvironment((event.currentTarget as HTMLInputElement).checked);
    } catch (cause) {
      error = formatError(cause);
    }
  }
  function selectAncillary(field: 'sheets' | 'summary', event: Event) {
    if (held) return;
    const checked = (event.currentTarget as HTMLInputElement).checked;
    error = '';
    try {
      if (field === 'sheets') session.includeAncillary(checked);
      else session.includeSummary(checked);
    } catch (cause) {
      error = formatError(cause);
    }
  }
  function undo() {
    if (held) return;
    error = '';
    try {
      session.undoDraft();
    } catch (cause) {
      error = formatError(cause);
    }
  }
  function selectReferences(field: 'include' | 'common' | 'guide', event: Event) {
    if (held || constancy) return;
    const checked = (event.currentTarget as HTMLInputElement).checked;
    error = '';
    try {
      session.selectReferences(field, checked);
    } catch (cause) {
      error = formatError(cause);
    }
  }
  async function review() {
    if (held || modeUnavailable || viewState.draftError) return;
    error = '';
    unitPage = 0;
    referencePage = 0;
    try {
      const ok = await session.review(calculation, {
        review: (contextId, options) =>
          trackIfCancellable(
            workbookReads,
            VegetationReportService.GetSummaryVegetationWorkbookReview(contextId, JSON.stringify(options))
          ),
        validationYield: () => new Promise((resolve) => setTimeout(resolve, 0)),
      });
      if (!ok) {
        const curErr = session.view().error;
        if (curErr) {
          notifications.error('Summary Vegetation workbook review failed', curErr, {
            category: 'reports',
            source: 'Summary Vegetation',
            contextTag: owned.project || undefined,
          });
        }
      }
    } catch (cause) {
      error = formatError(cause);
      notifications.error('Summary Vegetation workbook review failed', error, {
        category: 'reports',
        source: 'Summary Vegetation',
        contextTag: owned.project || undefined,
      });
    }
  }
  function syncSavedPresentation() {
    if (held || !savedPresentation) return;
    error = '';
    try {
      session.syncPresentation({
        title: savedPresentation.title,
        includeEnv: savedPresentation.includeEnv,
        includeAncillary: savedPresentation.createSummary,
        createSummary: savedPresentation.createSummary,
        includeReferences: savedPresentation.showCommon || savedPresentation.showGuide,
        showCommon: savedPresentation.showCommon,
        useGuideNames: savedPresentation.showGuide,
      });
    } catch (cause) {
      error = formatError(cause);
    }
  }
  async function reviewFromPreferences() {
    if (held || viewState.draftError) return;
    error = '';
    unitPage = 0;
    referencePage = 0;
    try {
      const loaded = await session.reviewFromPreferences({
        review: (contextId, options) =>
          trackIfCancellable(
            workbookReads,
            VegetationReportService.GetSummaryVegetationWorkbookReview(contextId, JSON.stringify(options))
          ),
        reviewFromPreferences: (contextId) =>
          trackIfCancellable(
            workbookReads,
            VegetationReportService.GetSummaryVegetationWorkbookReviewFromPreferences(contextId)
          ),
        validationYield: () => new Promise((resolve) => setTimeout(resolve, 0)),
      });
      if (loaded) {
        onPreferencesLoaded?.(loaded.options);
      } else {
        const curErr = session.view().error;
        if (curErr) {
          notifications.error('Summary Vegetation workbook review failed', curErr, {
            category: 'reports',
            source: 'Summary Vegetation',
            contextTag: owned.project || undefined,
          });
        }
      }
    } catch (cause) {
      error = formatError(cause);
      notifications.error('Summary Vegetation workbook review failed', error, {
        category: 'reports',
        source: 'Summary Vegetation',
        contextTag: owned.project || undefined,
      });
    }
  }
  async function publish() {
    if (held || modeUnavailable || viewState.draftError || !currentReview) return;
    error = '';
    try {
      await session.publish(calculation, (request) =>
        VegetationReportService.ExportReviewedSummaryVegetationWorkbook(owned.contextId, JSON.stringify(request))
      );
      const s = session.view().publication;
      const opts = {
        category: 'reports' as const,
        source: 'Summary Vegetation',
        contextTag: owned.project || undefined,
      };
      if (s.outcome?.status === 'published' && !s.error) {
        notifications.success(
          'Summary Vegetation workbook exported',
          s.outcome.path || s.requestedDestination || viewState.destination,
          opts
        );
      } else if (s.error || s.outcome) {
        notifications.error(
          'Summary Vegetation workbook export failed',
          s.error ||
            `Publication ${s.outcome?.status ?? 'failed'} for ${s.requestedDestination || viewState.destination}`,
          opts
        );
      }
    } catch (cause) {
      error = formatError(cause);
      notifications.error('Summary Vegetation workbook export failed', error, {
        category: 'reports',
        source: 'Summary Vegetation',
        contextTag: owned.project || undefined,
      });
    }
  }
  function acknowledge() {
    if (viewState.publication.busy || !viewState.publication.blocked) return;
    error = '';
    try {
      session.acknowledge();
    } catch (cause) {
      error = formatError(cause);
      notifications.error('Summary Vegetation workbook acknowledgement failed', error, {
        category: 'reports',
        source: 'Summary Vegetation',
        contextTag: owned.project || undefined,
      });
    }
  }
  function cancelReview() {
    workbookReads.cancelAll();
    session.cancel();
  }
  onDestroy(() => {
    session.cancel();
    unsubscribe();
    workbookReads.cancelAll();
  });
</script>

<WorkbookPublicationSection
  sectionAttr="data-summary-vegetation-workbook"
  ariaLabel="Summary inspection workbook"
  heading="Summary inspection workbook (draft)"
  sourceName="Summary Vegetation"
  contextTag={owned.project || undefined}
  publication={viewState.publication}
  destinationFallback={viewState.destination}
  reviewError={viewState.error ?? ''}
  draftError={viewState.draftError}
  unknownAttr="data-summary-workbook-unknown"
  unknownMessageSuffix="; never repeat the destination blindly."
  acknowledgeAttr="data-summary-workbook-acknowledge"
  onAcknowledge={acknowledge}
>
  <p data-summary-workbook-group>
    Workbook grouping: {groupLabel}.
    {#if constancy}
      Uses the loaded presentation Constancy draft: Lifeform grouping, Display Values1 and effective references without
      common/guide names.
    {:else}
      Uses the Summary Group by selection.
    {/if}
  </p>
  {#if constancy}
    <p data-summary-workbook-constancy>
      Constancy inspection retains numeric lifeform and separate raw-species groups, including visibly identical rows.
      Equal visible keys use an adapted raw-code tie order. Independent workbook name/reference drafts are retained for
      deselection; no preferences were saved.
    </p>
  {/if}
  {#if groupingUnavailable}
    <p role="alert">
      Grouped publication requires its independent build flag and compatible reference options. Common/guide names
      support Layer, Strata, or Lifeform/None Display Values6 with unanimous names. Other Lifeform/None displays support
      attribute references with both names off. Clear incompatible modes or choose a supported grouping. {'No options were changed automatically.'}
    </p>
  {/if}
  <div class="fields">
    <label>
      Workbook title
      <input
        data-summary-workbook-title
        value={viewState.title}
        disabled={held}
        oninput={(event) => edit('title', event.currentTarget.value)}
      />
    </label>
    <label class="checkbox">
      <input
        type="checkbox"
        data-summary-workbook-environment
        checked={viewState.includeEnv}
        disabled={held || !environmentEnabled}
        onchange={includeEnvironment}
      />
      Include selected environmental rows
    </label>
    <label class="checkbox">
      <input
        type="checkbox"
        data-summary-workbook-ancillary
        checked={viewState.includeAncillary}
        disabled={held}
        onchange={(event) => selectAncillary('sheets', event)}
      />
      Include source worksheets (SU Table)
    </label>
    <label class="checkbox">
      <input
        type="checkbox"
        data-summary-workbook-summary
        checked={viewState.createSummary}
        disabled={held || !viewState.includeAncillary}
        onchange={(event) => selectAncillary('summary', event)}
      />
      Include ReportSummary counts, unit names and version
    </label>
    <label class="checkbox">
      <input
        type="checkbox"
        data-summary-workbook-references
        checked={effectiveReferences}
        disabled={held || constancy}
        onchange={(event) => selectReferences('include', event)}
      />
      Project effective source references and attribute descriptions
    </label>
    <label class="checkbox">
      <input
        type="checkbox"
        data-summary-workbook-common
        checked={effectiveCommon}
        disabled={held || !viewState.includeReferences || viewState.useGuideNames || constancy}
        onchange={(event) => selectReferences('common', event)}
      />
      {#if unanimousCommon}
        Include unanimous common names in the workbook
      {:else}
        Include common names in grouping and the workbook
      {/if}
    </label>
    <label class="checkbox">
      <input
        type="checkbox"
        data-summary-workbook-guide
        checked={effectiveGuide}
        disabled={held || !viewState.includeReferences || constancy}
        onchange={(event) => selectReferences('guide', event)}
      />
      Use master CombinedEnglishName (also includes common names)
    </label>
    <label>
      New workbook destination (.xlsx)
      <input
        data-summary-workbook-destination
        value={viewState.destination}
        disabled={held}
        oninput={(event) => edit('destination', event.currentTarget.value)}
      />
    </label>
  </div>
  {#if unanimousCommon}
    <p data-summary-workbook-unanimous-common>
      Lifeform/None Display Values6 retains the original group and species key. Every contributing source name across
      all units must agree exactly; differing names stop review rather than split groups or choose an arbitrary name.
      Original First projects a unanimous empty name as NULL. Guide-name selection is an effective reference projection,
      not the original saved callback.
    </p>
  {/if}
  <div class="actions">
    <button data-summary-workbook-review disabled={held || modeUnavailable || !!viewState.draftError} onclick={review}>
      Review inspection workbook
    </button>
    <button
      type="button"
      data-summary-workbook-review-preferences
      disabled={held || !!viewState.draftError}
      onclick={reviewFromPreferences}
    >
      Review from Saved Preferences
    </button>
    {#if savedPresentation}
      <button type="button" data-summary-workbook-sync disabled={held} onclick={syncSavedPresentation}>
        Sync from Saved Presentation
      </button>
    {/if}
    <button data-summary-workbook-cancel disabled={!viewState.reviewing || barrier} onclick={cancelReview}>
      Cancel review
    </button>
    <button data-summary-workbook-undo disabled={held} onclick={undo}>Undo export options</button>
    <button
      data-summary-workbook-publish
      disabled={held || modeUnavailable || !!viewState.draftError || !currentReview || !viewState.destination}
      onclick={publish}
    >
      Publish reviewed workbook
    </button>
  </div>
  {#if viewState.review}
    <SummaryVegetationWorkbookReviewPlan
      review={viewState.review}
      {currentReview}
      {held}
      bind:unitPage
      bind:referencePage
      {unitPageSize}
    />
  {/if}
  <p>
    Explicit inspection export using the grouping, Calculate, Display Values and Show above, plus these
    title/environment options. Saved presentation callbacks are not applied. Source data, preferences and audit history
    are not changed. This is not the original Access Report action: quality/lumping callbacks, original formatting,
    Excel coercion, printing and macros remain unavailable. Optional attribute/common/guide projection is read-only and
    uses literal comparison, not Access collation or physical preflight mutations. Source worksheets are a separate
    inspection option. Existing destinations are never replaced.
  </p>
</WorkbookPublicationSection>

<style>
  .fields {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 280px), 1fr));
    gap: 1rem;
  }
  label {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
    min-width: 0;
    color: var(--vpro-ink);
    font-weight: 500;
  }
  input:not([type='checkbox']) {
    width: 100%;
    box-sizing: border-box;
    min-width: 0;
    padding: 0.5rem;
    border: 1px solid var(--vpro-border);
    border-radius: 0.25rem;
    background: var(--vpro-surface);
    color: var(--vpro-ink);
  }
  .checkbox {
    flex-direction: row;
    align-items: center;
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.75rem;
  }
  button {
    min-height: 2.5rem;
    padding: 0.5rem 0.85rem;
    border: 1px solid var(--vpro-navy);
    border-radius: 0.25rem;
    background: var(--vpro-navy);
    color: var(--vpro-surface);
    cursor: pointer;
    font-weight: 600;
  }
  button:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }
  [role='alert'] {
    color: var(--vpro-error);
  }
</style>
