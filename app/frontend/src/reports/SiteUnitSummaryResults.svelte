<script lang="ts">
  import { reportCellText } from './longEnvironmentReport';
  import type { ValidatedSiteUnitSummary } from './siteUnitSummary';
  import type { ValidatedSummarySpecies } from './siteUnitSummarySpecies';

  let {
    preview,
    speciesPreview,
  }: {
    preview: ValidatedSiteUnitSummary;
    speciesPreview: ValidatedSummarySpecies | null;
  } = $props();
</script>

<p role="status" data-summary-count>
  {preview.report.units.length} units; {preview.report.memberships.length} plot assignments.
  {preview.report.method === 1 ? 'Min---Mean---Max' : 'Interquartile 25% - 50% - 75%'}
</p>
{#if preview.report.units.length === 0}
  <p>No matching plots found in the selected Site Units.</p>
{/if}
{#each preview.report.units as unit, unitIndex (unit.code)}
  <article data-summary-unit>
    <h2>{unit.code === '' ? '"" (empty unit)' : unit.code}</h2>
    <p>{unit.longName === '' ? '"" (empty name)' : unit.longName ?? `Name ${unit.nameStatus}`}</p>
    <p>Plots in unit: {unit.plots.length}</p>
    {#if speciesPreview}
      {@const speciesUnit = speciesPreview.units[unitIndex]}
      <section data-summary-species-unit aria-label={`Vegetation species for ${unit.code}`}>
        <h3>Vegetation species</h3>
        {#each speciesUnit.groups as group}
          <h4>{group.caption}</h4>
          {#if group.rows.some(row => row.included)}
            <div class="species-table">
              <table>
                <thead>
                  <tr>
                    <th scope="col">Scientific Name</th>
                    <th scope="col">Common Name</th>
                    <th scope="col">%Cover</th>
                    <th scope="col">%Presence</th>
                  </tr>
                </thead>
                <tbody>
                  {#each group.rows.filter(row => row.included) as row}
                    <tr>
                      <th
                        scope="row"
                        aria-label={`${reportCellText(row.scientificName)} (${row.species})`}
                      >
                        {reportCellText(row.scientificName)}
                      </th>
                      <td>{reportCellText(row.englishName)}</td>
                      <td>{row.cover}</td>
                      <td>{row.presence}</td>
                    </tr>
                  {/each}
                </tbody>
              </table>
            </div>
          {:else}
            <p>No species meet the selected presence and cover thresholds.</p>
          {/if}
          <details>
            <summary>Species cover, presence, and filter details</summary>
            <ul>
              {#each group.rows as row}
                <li>
                  {row.species}: {row.cover}% cover; {row.presence}% presence ({row.physicalValues}
                  observations); {row.included ? 'included' : 'excluded'}.
                </li>
              {/each}
            </ul>
          </details>
        {:else}
          <p>No species recorded in reportable vegetation groups.</p>
        {/each}
      </section>
    {/if}
    {#each ['SITE', 'VEGETATION', 'SOILS'] as section}
      <section aria-labelledby={`summary-${unitIndex}-${section}`}>
        <h3 id={`summary-${unitIndex}-${section}`}>{section}</h3>
        <dl>
          {#each preview.report.fields as field, index}
            {#if field.section === section}
              <div>
                <dt>{field.label}</dt>
                <dd data-summary-value>
                  {unit.values[index] === '' ? '"" (empty summary)' : unit.values[index]}
                </dd>
              </div>
            {/if}
          {/each}
        </dl>
      </section>
    {/each}
    <details>
      <summary>Included plots and unit name matches</summary>
      <ul>
        {#each unit.plots as plot}
          <li>Plot {plot.plotNumber}</li>
        {/each}
      </ul>
      {#if unit.nameCandidates.length > 0}
        <ul>
          {#each unit.nameCandidates as candidate}
            <li>Unit name match: {reportCellText(candidate.value)}</li>
          {/each}
        </ul>
      {/if}
    </details>
  </article>
{/each}
<details>
  <summary>Site Unit assignments and plot status</summary>
  <ul>
    {#each preview.report.memberships as membership}
      <li>
        Plot {reportCellText(membership.plotNumber)} — unit {reportCellText(membership.siteUnit)}:
        {membership.status} ({membership.joinedRows} matching plot record{membership.joinedRows === 1 ? '' : 's'})
      </li>
    {/each}
  </ul>
</details>

<style>
  h2,
  h3 {
    font-weight: 600;
    margin: 0.8rem 0;
    color: var(--vpro-navy);
  }
  h2 {
    font-size: 1.2rem;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  article {
    border: 1px solid var(--vpro-border);
    border-radius: 0.5rem;
    padding: 1rem;
    margin-top: 1rem;
    background: var(--vpro-surface);
    min-width: 0;
  }
  dl {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 280px), 1fr));
    gap: 0.5rem 1rem;
  }
  dl > div {
    display: grid;
    grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
    gap: 0.5rem;
    padding: 0.45rem 0.6rem;
    background: var(--vpro-canvas);
    border-radius: 0.25rem;
  }
  dt {
    font-weight: 600;
    color: var(--vpro-navy);
  }
  dd,
  li {
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  details {
    margin-top: 0.8rem;
  }
  summary {
    min-height: 2.5rem;
    border: 1px solid var(--vpro-navy);
    border-radius: 0.25rem;
    padding: 0.5rem 0.85rem;
    background: var(--vpro-navy);
    color: var(--vpro-surface);
    font-weight: 600;
    cursor: pointer;
  }
  summary:hover {
    background: var(--vpro-navy-dark);
    border-color: var(--vpro-navy-dark);
  }
  .species-table {
    overflow-x: auto;
    max-width: 100%;
  }
  table {
    width: 100%;
    border-collapse: collapse;
    margin: 0.5rem 0;
    background: var(--vpro-surface);
  }
  th,
  td {
    padding: 0.5rem;
    border-bottom: 1px solid var(--vpro-border);
    text-align: left;
    overflow-wrap: anywhere;
  }
  thead th {
    background: var(--vpro-canvas);
    color: var(--vpro-navy);
  }
  @media (max-width: 640px) {
    dl > div {
      grid-template-columns: minmax(0, 1fr);
    }
  }
</style>
