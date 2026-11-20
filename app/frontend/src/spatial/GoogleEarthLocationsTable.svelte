<script lang="ts">
  import type { ValidatedGoogleEarthReview } from './googleEarthReview';

  let {
    review,
    locked,
    previousOffset,
    nextOffset,
    formatCell,
    onShowPage,
  }: {
    review: ValidatedGoogleEarthReview;
    locked: boolean;
    previousOffset: number;
    nextOffset: number;
    formatCell: (cell: ValidatedGoogleEarthReview['rows'][number]['plotNumber']) => string;
    onShowPage: (offset: number) => void;
  } = $props();
</script>

<p role="status" data-google-earth-summary>
  {review.totalRows} plot locations with latitude and longitude ready for export. Previewing plot locations does not modify
  project data, saved preferences, or files on disk.
</p>
<div class="table-scroll">
  <table>
    <caption>Plot coordinates for Google Earth export (signed decimal longitude and latitude)</caption>
    <thead>
      <tr>
        {#each review.fields as field, i}
          <th id={`earth-field-${i}`} scope="col">{field.label}</th>
        {/each}
      </tr>
    </thead>
    <tbody>
      {#each review.rows as row (`${row.envRowId}:${row.membershipRowId}`)}
        <tr data-google-earth-row={`${row.envRowId}:${row.membershipRowId}`}>
          {#each [row.plotNumber, row.longitude, row.latitude, row.description] as cell, i}
            <td
              headers={`earth-field-${i}`}
              aria-label={`${review.fields[i].label} for plot record ${row.envRowId}, Site Unit record ${row.membershipRowId || 'not selected'}`}
              >{formatCell(cell)}</td
            >
          {/each}
        </tr>
      {:else}
        <tr><td colspan="4">No plot coordinates found on this page.</td></tr>
      {/each}
    </tbody>
  </table>
</div>
<div class="actions" aria-label="Google Earth preparation pages">
  <button type="button" disabled={locked || review.offset === 0} onclick={() => onShowPage(previousOffset)}
    >Previous pairs</button
  >
  <span
    >{review.rows.length ? review.offset + 1 : 0}-{review.rows.length ? review.offset + review.rows.length : 0} of {review.totalRows}</span
  >
  <button
    type="button"
    disabled={locked || review.offset + review.rows.length >= review.totalRows}
    onclick={() => onShowPage(nextOffset)}>Next pairs</button
  >
</div>
<details>
  <summary>Plot record details for this page</summary>
  {#each review.rows as row (`${row.envRowId}:${row.membershipRowId}`)}
    <p>
      Plot record {row.envRowId}; Site Unit record {row.membershipRowId || 'not selected'}; stored longitude {formatCell(
        row.storedLongitude
      )}.
    </p>
  {/each}
</details>

<style>
  .actions {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.75rem;
    margin: 1rem 0;
  }
  button {
    border: 1px solid var(--vpro-navy);
    border-radius: 0.25rem;
    padding: 0.4rem 0.6rem;
    min-width: 0;
    background: var(--vpro-surface);
    color: var(--vpro-navy);
    font-weight: 600;
  }
  button:disabled {
    opacity: 0.5;
  }
  p {
    overflow-wrap: anywhere;
  }
  .table-scroll {
    overflow-x: auto;
    max-width: 100%;
  }
  table {
    border-collapse: collapse;
    width: 100%;
  }
  th,
  td {
    border: 1px solid var(--vpro-border);
    padding: 0.4rem 0.6rem;
    text-align: left;
    vertical-align: top;
    white-space: pre-wrap;
  }
  th {
    background: var(--vpro-canvas);
    color: var(--vpro-navy);
  }
  caption {
    text-align: left;
    margin-bottom: 0.5rem;
    color: var(--vpro-ink-secondary);
  }
</style>
