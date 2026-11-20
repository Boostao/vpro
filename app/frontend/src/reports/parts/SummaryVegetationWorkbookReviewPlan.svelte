<script lang="ts">
  import type { SummaryVegetationWorkbookSession } from '../summaryVegetationWorkbook';

  type ReviewedWorkbookPlan = NonNullable<ReturnType<SummaryVegetationWorkbookSession['view']>['review']>;

  let {
    review,
    currentReview,
    held,
    unitPage = $bindable(0),
    referencePage = $bindable(0),
    unitPageSize = 50,
  }: {
    review: ReviewedWorkbookPlan;
    currentReview: boolean;
    held: boolean;
    unitPage?: number;
    referencePage?: number;
    unitPageSize?: number;
  } = $props();
</script>

<div data-summary-workbook-plan class="plan">
  {#if !currentReview}
    <p role="alert">Calculation options changed; review the current options before publication.</p>
  {/if}
  <p>
    Sheet: {review.sheet}. Group field: {review.preview.groupField?.name ?? 'Layer'}.
    {review.preview.rows.length} vegetation rows;
    {review.environment?.rows.length ?? 0} environmental rows; first vegetation row {review.firstVegetationRow}.
    {review.bytes} bytes.
  </p>
  <p>Approval: {review.approvalHash}<br />Workbook SHA256: {review.workbookSHA256}</p>
  {#if review.preview.references}
    {@const reference = review.preview.references}
    <div data-summary-workbook-reference-plan class="plan">
      <p>
        Effective references: {reference.masterRows} physical master rows;
        {reference.removedMasterRows} old attribute rows excluded; {reference.personalRows} personal rows.
        {reference.derivedRows} attribute rows projected from {reference.descriptionRows} description rows;
        {reference.unionRows} distinct literal reference rows. Common names: {reference.showCommon
          ? 'included'
          : 'not included'}. Guide names: {reference.useGuideNames ? 'master CombinedEnglishName' : 'not selected'}.
      </p>
      <p>
        Derived origins identify physical attribute-description rows, not invented master records. Name groups are shown
        below; cover values are in the workbook.
        {#if review.options.unanimousCommon}
          Source NULL and empty remain distinct for unanimity; a unanimous empty name is projected as NULL by original
          First.
        {:else}
          NULL and empty names remain distinct.
        {/if}
      </p>
      <div class="unit-table">
        <table aria-label="Reviewed effective reference groups">
          <thead>
            <tr>
              <th scope="col">{review.preview.groupField?.name ?? 'Layer'}</th>
              <th scope="col">Scientific name/code</th>
              {#if reference.showCommon}<th scope="col">Common name</th>{/if}
              <th scope="col">Order</th>
            </tr>
          </thead>
          <tbody>
            {#each review.preview.rows.slice(referencePage * unitPageSize, (referencePage + 1) * unitPageSize) as row}
              <tr
                aria-label={row.rawSpecies
                  ? `Raw species ${row.rawSpecies.text === null ? '(NULL)' : row.rawSpecies.text === '' ? '(empty)' : row.rawSpecies.text}`
                  : undefined}
              >
                <td>
                  {row.layer.storage === 'integer'
                    ? row.layer.integer
                    : row.layer.text === null
                      ? '(NULL)'
                      : row.layer.text === ''
                        ? '(empty)'
                        : row.layer.text}
                </td>
                <th scope="row">
                  {row.species.text === null ? '(NULL)' : row.species.text === '' ? '(empty)' : row.species.text}
                </th>
                {#if reference.showCommon}
                  {#if row.commonName}
                    <td>
                      {row.commonName.text === null
                        ? '(NULL)'
                        : row.commonName.text === ''
                          ? '(empty)'
                          : row.commonName.text}
                    </td>
                  {:else}
                    <td><span role="alert">Reviewed common name is missing.</span></td>
                  {/if}
                {/if}
                <td>
                  {row.order.storage === 'real'
                    ? row.order.real
                    : row.order.text === null
                      ? '(NULL)'
                      : row.order.text === ''
                        ? '(empty)'
                        : row.order.text}
                </td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
      <div class="actions">
        <button data-summary-reference-previous disabled={held || referencePage === 0} onclick={() => referencePage--}>
          Previous name groups
        </button>
        <span>
          {review.preview.rows.length} name groups; page {referencePage + 1} of
          {Math.max(1, Math.ceil(review.preview.rows.length / unitPageSize))}.
        </span>
        <button
          data-summary-reference-next
          disabled={held || (referencePage + 1) * unitPageSize >= review.preview.rows.length}
          onclick={() => referencePage++}
        >
          Next name groups
        </button>
      </div>
    </div>
  {/if}
  {#if review.ancillary}
    <div data-summary-workbook-ancillary-plan class="plan">
      <p>
        Source sheets: {review.ancillary.sheets.join(', ')}. Reviewed creation time: {review.ancillary.createdAt}.
        {review.ancillary.membershipRows} physical SU membership rows.
      </p>
      {#if review.ancillary.summary}
        {@const summary = review.ancillary.summary}
        <p>
          Plots in database: {summary.environmentCountAvailable ? summary.environmentRows : 'N/A'}. Non-NULL selected
          plot rows: {summary.selectedPlotRows}. AllSpecs version: {summary.version === ''
            ? '(empty)'
            : summary.version} ({summary.versionStatus}).
        </p>
        <div class="unit-table">
          <table aria-label="Reviewed ReportSummary units">
            <thead>
              <tr>
                <th scope="col">Short name</th>
                <th scope="col">Units</th>
                <th scope="col">Long name</th>
              </tr>
            </thead>
            <tbody>
              {#each summary.units.slice(unitPage * unitPageSize, (unitPage + 1) * unitPageSize) as unit (unit.code)}
                <tr>
                  <th scope="row">{unit.code === '' ? '(empty)' : unit.code}</th>
                  <td>{unit.numPlots}</td>
                  <td>{unit.longName === null ? '(NULL)' : unit.longName === '' ? '(empty)' : unit.longName}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
        <div class="actions">
          <button data-summary-units-previous disabled={held || unitPage === 0} onclick={() => unitPage--}>
            Previous units
          </button>
          <span
            >{`${summary.units.length} units; page ${unitPage + 1} of ${Math.max(1, Math.ceil(summary.units.length / unitPageSize))}.`}</span
          >
          <button
            data-summary-units-next
            disabled={held || (unitPage + 1) * unitPageSize >= summary.units.length}
            onclick={() => unitPage++}
          >
            Next units
          </button>
        </div>
      {/if}
    </div>
  {/if}
  <p>{review.scope}</p>
</div>

<style>
  .plan {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 0.75rem;
    min-width: 0;
    overflow-wrap: anywhere;
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.75rem;
    align-items: center;
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
  .unit-table {
    min-width: 0;
    overflow-x: auto;
  }
  table {
    width: 100%;
    border-collapse: collapse;
    background: var(--vpro-surface);
  }
  th,
  td {
    padding: 0.5rem;
    border: 1px solid var(--vpro-border);
    text-align: left;
    overflow-wrap: anywhere;
  }
  thead th {
    background: var(--vpro-canvas);
    color: var(--vpro-navy);
  }
  [role='alert'] {
    color: var(--vpro-error);
  }
</style>
