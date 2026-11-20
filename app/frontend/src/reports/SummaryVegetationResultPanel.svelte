<script lang="ts">
  import type { SummaryVegetationPreview } from './summaryVegetation';

  let {
    project,
    su,
    preview,
  }: {
    project: string;
    su: string;
    preview: SummaryVegetationPreview;
  } = $props();
</script>

<article data-summary-result>
  <h2>
    {preview.unitScope && preview.unitScope !== 'su'
      ? `Summary Units (${preview.unitScope})`
      : 'Current Site Unit Table'} — {preview.groupAndOrder === 12
      ? 'Strata'
      : preview.groupAndOrder === 13
        ? 'Lifeform'
        : preview.groupAndOrder === 14
          ? 'None'
          : 'Layer'}
  </h2>
  <p>
    Calculate: {preview.average === 1 ? 'By n Plots' : 'Characteristic'}. Display Values: {preview.display === 1
      ? '% Presence and % Cover'
      : preview.display === 2
        ? 'Presence Class and Significance Class'
        : preview.display === 3
          ? 'Presence Class and % Cover'
          : preview.display === 4
            ? 'Prominence Class'
            : preview.display === 5
              ? 'Goldstream Class'
              : '% Cover'}.
    {#if preview.showClass}
      Show: {preview.showClass === 20 ? 'Value' : preview.showClass === 1 ? 'Class (historical default 1)' : 'Class'}.
      Calculate is retained but ignored for class formulas.
    {/if}
    {#if preview.lumpTable}Lump table: {preview.lumpTable}.
    {/if}
    {#if preview.combineVariants}Variants combined.
    {/if}
    {#if preview.hierarchyHeaderEnabled}Hierarchy headers included.
    {/if}
  </p>
  {#if preview.quality}
    <p class="qc-summary" data-summary-qc-summary role="status">
      QC filter: {preview.quality.enforced ? 'Enforced' : 'Inactive'} — retained {preview.quality.retained} of {preview
        .quality.totalBefore} plots ({preview.quality.removedCount} removed).
    </p>
  {/if}
  {#if preview.goldstream}
    <p class="qc-summary" data-summary-goldstream-summary>
      Goldstream metadata: {preview.goldstream.formula} (ShowClass {preview.goldstream.showClass}, labels: {(
        preview.goldstream.classLabels ?? []
      ).join(', ') || 'none'}).
    </p>
  {/if}
  {#if preview.appliedPreferences}
    <p class="scope-meta" data-summary-applied-preferences>
      Synced saved preferences: “{preview.appliedPreferences.title || '(untitled)'}”, scope={preview.appliedPreferences
        .unitScope || 'su'}{#if preview.appliedPreferences.lumpTable}, lump={preview.appliedPreferences.lumpTable}{/if}.
    </p>
  {/if}
  <div class="table-scroll">
    <table>
      <caption>Summary Vegetation — {project}, {su}</caption>
      <thead>
        <tr>
          <th scope="col">{preview.groupField?.name ?? 'Layer'}</th>
          <th scope="col">Spp</th>
          <th scope="col">Order</th>
          {#each preview.columns as unit}
            <th scope="col">{unit || '(empty unit)'}</th>
          {/each}
        </tr>
        {#if preview.units.some((u) => !!u.hierarchyHeader)}
          <tr>
            <th scope="row" colspan="3">Hierarchy</th>
            {#each preview.columns as code}
              <td>{preview.units.find((u) => u.code === code)?.hierarchyHeader ?? ''}</td>
            {/each}
          </tr>
        {/if}
        <tr>
          <th scope="row" colspan="3">n Plots</th>
          {#each preview.columns as code}
            <td>{preview.units.find((unit) => unit.code === code)?.numPlots}</td>
          {/each}
        </tr>
      </thead>
      <tbody>
        {#each preview.rows as row}
          <tr>
            <td>{row.layer.text ?? `(NULL ${preview.groupField?.name ?? 'Layer'})`}</td>
            <th scope="row">{row.species.text ?? '(NULL Spp)'}</th>
            <td>{row.order.storage === 'real' ? row.order.real : (row.order.text ?? '')}</td>
            {#each row.covers as cover, i}
              <td aria-label={`${row.species.text ?? 'NULL Spp'} — ${preview.columns[i] || 'empty unit'}`}
                >{cover.text ?? ''}</td
              >
            {/each}
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
  {#if preview.rows.length === 0}
    <p>No species rows matched the selected report options.</p>
  {/if}
  <details>
    <summary>Physical admission and calculation provenance</summary>
    {#each preview.units as unit}
      <p>
        Unit {unit.code || '(empty)'}: {unit.numPlots} plots ({unit.membershipIds.length} unit assignments; {unit
          .rawVegRowIds.length} vegetation records).
      </p>
    {/each}
    {#each preview.rows as row}
      <p>
        {row.layer.text ?? 'NULL Layer'} — {row.species.text ?? 'NULL Spp'}: {row.witnesses.length}
        species observations.
      </p>
    {/each}
  </details>
</article>

<style>
  article,
  details {
    min-width: 0;
  }
  h2 {
    margin: 0;
    color: var(--vpro-navy);
  }
  .scope-meta {
    overflow-wrap: anywhere;
    color: var(--vpro-ink-secondary);
  }
  .qc-summary {
    padding: 0.5rem 0.75rem;
    border-left: 4px solid var(--vpro-gold);
    background: var(--vpro-surface);
    color: var(--vpro-navy);
    font-weight: 600;
  }
  summary {
    min-height: 2.5rem;
    padding: 0.5rem 0.85rem;
    border: 1px solid var(--vpro-navy);
    border-radius: 0.25rem;
    background: var(--vpro-navy);
    color: var(--vpro-surface);
    font-weight: 600;
    cursor: pointer;
  }
  summary:hover {
    background: var(--vpro-navy-dark);
    border-color: var(--vpro-navy-dark);
  }
  .table-scroll {
    overflow-x: auto;
    max-width: 100%;
  }
  table {
    border-collapse: collapse;
    width: 100%;
    background: var(--vpro-surface);
  }
  th,
  td {
    padding: 0.5rem;
    border: 1px solid var(--vpro-border);
    text-align: left;
    vertical-align: top;
  }
  thead th {
    background: var(--vpro-canvas);
    color: var(--vpro-navy);
  }
</style>
