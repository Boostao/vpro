<script lang="ts">
  import type { ProjectMetadataCell } from '../../../bindings/github.com/boostao/vpro/app';
  import type { LongVegetationSettings } from '../../../bindings/github.com/boostao/vpro/app/internal/vegreport/models';
  import { reportCellText } from '../longEnvironmentReport';
  import type { ValidatedLongVegetationPreview } from '../longVegetationReport';

  let {
    settings,
    preview,
    groupLabel,
    useSppCodesOnly,
  }: {
    settings: LongVegetationSettings | null;
    preview: ValidatedLongVegetationPreview | null;
    groupLabel: string;
    useSppCodesOnly: boolean;
  } = $props();

  function baseVariantCode(code: string): string {
    if (code.length <= 1) return code;
    const last = code.charAt(code.length - 1);
    return last >= '0' && last < '9' ? code.slice(0, -1) : code;
  }

  function rollupUnitRows(
    unit: ValidatedLongVegetationPreview['report']['units'][number],
    activeSettings: LongVegetationSettings
  ) {
    if (!useSppCodesOnly || activeSettings.combineVariants) return unit.rows;
    const merged = new Map<string, (typeof unit.rows)[number]>();
    for (const row of unit.rows) {
      const rawSpecies = row.species.storage === 'text' ? (row.species.text ?? '') : '';
      const rolledSpecies = rawSpecies ? baseVariantCode(rawSpecies) : rawSpecies;
      const layerKey = `${row.layer.storage}:${row.layer.text ?? row.layer.integer ?? ''}`;
      const key = `${layerKey}|${rolledSpecies.toUpperCase()}`;
      const existing = merged.get(key);
      if (!existing) {
        merged.set(key, {
          ...row,
          species: row.species.storage === 'text' ? { ...row.species, text: rolledSpecies } : row.species,
          plots: row.plots.map((plot) => ({ ...plot })),
        });
      } else {
        let nonNullPlots = 0;
        let coverSum = 0;
        const combinedPlots = existing.plots.map((plot, index) => {
          const incoming = row.plots[index]?.cover ?? null;
          let nextCover = plot.cover;
          if (incoming !== null) nextCover = nextCover === null ? incoming : Math.min(99, nextCover + incoming);
          if (nextCover !== null) {
            nonNullPlots += 1;
            coverSum += nextCover;
          }
          return { ...plot, cover: nextCover };
        });
        const denom = activeSettings.average === 'observations' ? nonNullPlots : unit.numPlots;
        existing.plots = combinedPlots;
        existing.presence = unit.numPlots > 0 ? nonNullPlots / unit.numPlots : null;
        existing.meanCover = denom > 0 ? coverSum / denom : null;
      }
    }
    return [...merged.values()];
  }

  const numberText = (value: number | null) => (value === null ? 'NULL' : String(value));
  const presenceText = (value: number | null) => (value === null ? 'NULL' : `${value * 100}%`);
  const supplementaryText = (cell: ProjectMetadataCell) =>
    preview?.report.selectedFieldType === 'boolean' && cell.storage !== 'null'
      ? cell.integer === '-1'
        ? 'TRUE'
        : 'FALSE'
      : reportCellText(cell);
</script>

{#if settings?.constantSpeciesList}
  <p class="notice">
    Constant species list is enabled in retained YAML. Presence and mean-cover thresholds are bypassed, as in the source
    report; missing combinations have NULL statistics, not zero.
  </p>
{/if}
{#if settings?.grouping === 'none'}
  <p class="notice">
    The source's None mode changes row ordering, not cover aggregation. Layer observations remain separate and labelled;
    equal source sort keys use a deterministic layer/name tie-break. A constant species list retains its source
    layer-first order.
  </p>
{/if}
{#if settings?.grouping === 'lifeform'}
  <p class="notice">
    Lifeform conversion uses the original master/personal UNION, extended covers and the source's 99.9 cap before
    grouped insertion. Cover10 is not part of this conversion. Later master definitions and physical memberships retain
    their separate join weights; this is not the standalone Lifeform Summary.
  </p>
{/if}
{#if settings?.grouping === 'strata'}
  <p class="notice">
    Strata A/B use retained TotalA/TotalB when present; otherwise source cover sums are capped at 99. Extended B covers
    participate. Only positive A/B results are inserted; C/D retain every non-NULL cover, including zero or negative
    values. Physical Strata definitions retain their original join weights; Cover8/9/10 do not enter this conversion.
  </p>
{/if}

{#if preview}
  <h2>{preview.report.title === '' ? '"" (empty title)' : preview.report.title}</h2>
  <p role="status">{preview.report.units.length} units. No data, audits or configuration written.</p>
  {#if preview.report.quality}
    <p class="notice">
      Quality ranks use original DataQuality definitions, not the editor dropdown ordering. NULL flags apply to
      missing/NULL joined ranks; matches only in another list are excluded.
      {preview.report.sourceKind
        ? 'Original project tuples are retained by qualified plot existence; reference fanout does not multiply their denominator or cover.'
        : preview.settings.unitGrouping === 'selected-fields'
          ? 'For selected-field units, quality keeps derived rows by qualified plot existence; reference fanout does not multiply their denominator or cover.'
          : 'Reference fanout weights the denominator and joined cover without inventing physical SU row IDs.'}
    </p>
    <details class="quality-provenance">
      <summary>Quality qualification provenance ({preview.report.quality.occurrences.length} occurrences)</summary>
      <p>
        Threshold reference row IDs — Site: {preview.report.quality.thresholdRowIds[0].join(', ')}; Vegetation:
        {preview.report.quality.thresholdRowIds[1].join(', ')}; Soil:
        {preview.report.quality.thresholdRowIds[2].join(', ')}.
      </p>
      <p>
        Excluded physical membership IDs:
        {preview.report.quality.excludedMembershipIds.length
          ? preview.report.quality.excludedMembershipIds.join(', ')
          : 'None'}.
      </p>
      {#each preview.report.quality.references as reference}
        <p class="quality-occurrence">
          Reference row {reference.rowId}: item {reportCellText(reference.item)}; list
          {reportCellText(reference.listName)}; rank {reportCellText(reference.itemOrder)}.
        </p>
      {/each}
      {#each preview.report.quality.occurrences as occurrence}
        <p class="quality-occurrence">
          SU row {occurrence.membershipId}; plot {JSON.stringify(occurrence.plotNumber.text)}; unit
          {reportCellText(occurrence.siteUnit)}; ENV row {occurrence.envRowId}; Admin row {occurrence.adminRowId};
          quality values (Site, Vegetation, Soil): {occurrence.values.map(reportCellText).join(', ')}; reference rows
          (Site, Vegetation, Soil): {occurrence.listRowIds.map((id) => (id === null ? 'NULL join' : id)).join(', ')}.
        </p>
      {/each}
    </details>
  {/if}
  {#if preview.report.sourceKind && preview.report.projectUnits}
    <p class="notice">
      Original project scope: {preview.report.sourceKind}. Complete original Build remains separate from emitted tuples.
      No synthetic SU row IDs or memberships are created.
    </p>
    <details class="quality-provenance">
      <summary>Original project tuple provenance ({preview.report.projectUnits.length} tuples)</summary>
      {#each preview.report.projectUnits as tuple}
        <p class="quality-occurrence">
          Original ENV row {tuple.envRowId}; Admin row {tuple.adminRowId ?? 'not used by All plots'}; plot
          {reportCellText(tuple.plotNumber)}; derived unit {reportCellText(tuple.siteUnit)}.
        </p>
      {/each}
    </details>
  {/if}
  {#if preview.settings.unitGrouping === 'all-plots' && preview.report.noneUnits}
    <p class="notice">
      None report units join physical Env rows to the current selected list. Quality qualification runs first when
      enabled. The derived All plots unit does not replace original SU identities or expand to all-project scope.
    </p>
    <details class="quality-provenance">
      <summary>None unit join provenance ({preview.report.noneUnits.length} occurrences)</summary>
      {#each preview.report.noneUnits as occurrence}
        <p class="quality-occurrence">
          Outer ENV row {occurrence.envRowId}; original SU row {occurrence.membershipId}; plot
          {JSON.stringify(occurrence.plotNumber.text)}; derived unit {reportCellText(occurrence.siteUnit)};
          {occurrence.qualityOccurrence === null
            ? 'unfiltered current list'
            : `quality occurrence index ${occurrence.qualityOccurrence}`}.
        </p>
      {/each}
    </details>
  {/if}
  {#if preview.settings.unitGrouping === 'selected-fields' && preview.report.selectedUnits}
    <p class="notice">
      Selected report units concatenate the ordered fields with no separator. Original selected-SU/Env/Admin joins
      define the derived denominator and cover weights. Quality, when enabled, filters by qualified plot existence
      rather than multiplying those joins. This is not all-project scope and original physical identities remain
      unchanged.
    </p>
    <details class="quality-provenance">
      <summary>Selected field unit join provenance ({preview.report.selectedUnits.length} occurrences)</summary>
      {#each preview.report.selectedUnits as occurrence}
        <p class="quality-occurrence">
          Original SU row {occurrence.membershipId}; ENV row
          {occurrence.envRowId === null ? 'NULL join' : occurrence.envRowId}; Admin row
          {occurrence.adminRowId === null ? 'NULL join' : occurrence.adminRowId}; plot
          {reportCellText(occurrence.plotNumber)}; derived unit {reportCellText(occurrence.siteUnit)}.
        </p>
      {/each}
    </details>
  {/if}
  {#each preview.report.diagnostics as diagnostic}
    <p class="diagnostic">{diagnostic.code}: {JSON.stringify(diagnostic.identity)}; count {diagnostic.count}.</p>
  {/each}
  {#each preview.report.units as unit}
    {@const renderedRows = rollupUnitRows(unit, preview.settings)}
    <section class="unit">
      <h3>Site Unit — {unit.code.storage === 'null' ? 'Unassigned (NULL)' : reportCellText(unit.code)}</h3>
      <p class="unit-name">
        Long name: {unit.longName === null
          ? unit.nameStatus
          : unit.longName === ''
            ? '"" (empty name)'
            : unit.longName}; reference status: {unit.nameStatus}.
      </p>
      <details>
        <summary>Reference name candidates ({unit.nameCandidates.length})</summary>
        {#each unit.nameCandidates as candidate}
          <p class="name-candidate">Reference row {candidate.rowId}: {reportCellText(candidate.value)}</p>
        {/each}
      </details>
      {#if preview.report.sourceKind}
        <p>
          Original project tuple denominator: {unit.numPlots}; emitted tuple indexes:
          {unit.projectUnitIndexes?.length ?? 0}.
        </p>
        <details>
          <summary>Original project tuple indexes</summary>
          <p>{unit.projectUnitIndexes?.join(', ')}</p>
        </details>
      {:else}
        <p>
          {preview.settings.unitGrouping === 'all-plots'
            ? 'Derived Env/current-list denominator'
            : preview.settings.unitGrouping === 'selected-fields'
              ? 'Derived selected-field denominator'
              : preview.settings.quality
                ? 'Qualified denominator'
                : 'Physical denominator'}: {unit.numPlots}; retained physical membership rows:
          {unit.membershipIds.length}.
        </p>
        <details>
          <summary>Physical membership row IDs ({unit.membershipIds.length})</summary>
          <p>{unit.membershipIds.join(', ')}</p>
        </details>
      {/if}
      {#if renderedRows.length === 0}
        <p>No {groupLabel.toLowerCase()}/species rows satisfy the current report settings.</p>
      {:else}
        <div class="table-scroll" role="region" aria-label={`Vegetation table for unit ${reportCellText(unit.code)}`}>
          <table>
            <caption>Vegetation Table — Site Unit {reportCellText(unit.code)}</caption>
            <thead>
              <tr>
                <th scope="col">{groupLabel}</th>
                <th scope="col">Species</th>
                {#if preview.settings.showSpeciesCode}
                  <th scope="col">List Code</th>
                  <th scope="col">Matched report Code</th>
                {:else if preview.settings.showEnglishName}
                  <th scope="col">List English name</th>
                  <th scope="col">Matched report English name</th>
                {:else if preview.settings.selectedField !== undefined}
                  <th scope="col">List {preview.settings.selectedField}</th>
                  <th scope="col">Matched report {preview.settings.selectedField}</th>
                {/if}
                <th scope="col">Presence (%)</th>
                <th scope="col">Mean cover (%)</th>
                {#each renderedRows[0].plots as plot}
                  <th scope="col">Plot {JSON.stringify(plot.plotNumber)}</th>
                {/each}
              </tr>
            </thead>
            <tbody>
              {#each renderedRows as row}
                <tr>
                  <td>{reportCellText(row.layer)}</td>
                  <th scope="row">{reportCellText(row.species)}</th>
                  {#if preview.settings.showEnglishName || preview.settings.showSpeciesCode || preview.settings.selectedField !== undefined}
                    <td>{supplementaryText(row.englishName)}</td>
                    <td>{supplementaryText(row.matchedName)}</td>
                  {/if}
                  <td>{presenceText(row.presence)}</td>
                  <td>{numberText(row.meanCover)}</td>
                  {#each row.plots as plot}
                    <td>{numberText(plot.cover)}</td>
                  {/each}
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {/if}
    </section>
  {/each}
{/if}

<style>
  h2 {
    color: var(--vpro-navy);
    font-size: 1.25rem;
  }
  h3 {
    font-weight: 600;
    color: var(--vpro-navy);
  }
  .unit {
    min-width: 0;
    display: grid;
    gap: 0.5rem;
  }
  .unit-name,
  .name-candidate,
  .quality-occurrence {
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  .table-scroll {
    overflow-x: auto;
    max-width: 100%;
    border: 1px solid var(--vpro-border);
    background: var(--vpro-surface);
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
    min-width: 8rem;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  thead th {
    background: var(--vpro-navy);
    color: var(--vpro-surface);
  }
  .diagnostic,
  .notice {
    color: var(--vpro-info);
  }
</style>
