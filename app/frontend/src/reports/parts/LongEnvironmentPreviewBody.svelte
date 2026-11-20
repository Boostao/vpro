<script lang="ts">
  import type { LongEnvironmentPreview } from '../../../bindings/github.com/boostao/vpro/app';
  import { reportCellText } from '../longEnvironmentReport';

  let { preview }: { preview: LongEnvironmentPreview } = $props();
</script>

<h2>{preview.report.title}</h2>
<p role="status">
  {preview.report.units?.length} units; 72 ordered rows. This report preparation made no data/configuration writes.
</p>
{#each preview.report.diagnostics ?? [] as diagnostic}
  <p class="diagnostic">
    {diagnostic.code}: unit {diagnostic.unit === null ? 'not applicable' : JSON.stringify(diagnostic.unit)}; plot
    {diagnostic.plotNumber === null ? 'not applicable' : JSON.stringify(diagnostic.plotNumber)}; count
    {diagnostic.count}.
  </p>
{/each}
{#each preview.report.units ?? [] as unit (unit.code)}
  <section class="unit">
    <h3>Site Unit — {unit.code === '' ? '"" (empty code)' : unit.code}</h3>
    <p>
      Long name: {unit.longName === null ? unit.nameStatus : unit.longName === '' ? '"" (empty name)' : unit.longName}
    </p>
    <details>
      <summary>Reference name candidates ({unit.nameCandidates?.length})</summary>
      {#each unit.nameCandidates ?? [] as candidate}
        <p>Reference row {candidate.rowId}: {reportCellText(candidate.value)}</p>
      {/each}
    </details>
    <div class="table-scroll" role="region" aria-label={`Environmental table for unit ${unit.code}`}>
      <table>
        <caption>Environment Table — Site Unit {JSON.stringify(unit.code)}</caption>
        <thead>
          <tr>
            <th scope="col">Field</th>
            {#each unit.plots ?? [] as plot}
              <th scope="col">{JSON.stringify(plot.plotNumber)}<br />{plot.status}</th>
            {/each}
          </tr>
        </thead>
        <tbody>
          {#each preview.report.fields ?? [] as field, i}
            <tr class:heading={field.heading}>
              <th scope="row">{field.label}</th>
              {#each unit.plots ?? [] as plot}
                <td>{field.heading ? '' : reportCellText(plot.values![i])}</td>
              {/each}
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  </section>
{/each}

<style>
  h2 {
    font-size: 1.25rem;
  }
  h3 {
    font-weight: 600;
  }
  .unit {
    min-width: 0;
    display: grid;
    gap: 0.5rem;
  }
  .table-scroll {
    overflow-x: auto;
    max-width: 100%;
    border: 1px solid var(--vpro-border);
  }
  table {
    border-collapse: collapse;
    width: 100%;
  }
  th,
  td {
    border: 1px solid var(--vpro-border);
    padding: 0.5rem;
    text-align: left;
    min-width: 9rem;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  th[scope='row'] {
    min-width: 16rem;
  }
  .heading {
    background: var(--vpro-canvas);
  }
  .diagnostic {
    color: var(--vpro-info);
  }
</style>
