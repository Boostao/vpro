<script lang="ts">
  import type { PlotLabelPreview } from './plotLabelPreview';
  import type { PlotLabelRegionalEvidence } from './plotLabelRegional';

  let {
    preview,
    regionalEvidence,
  }: {
    preview: PlotLabelPreview;
    regionalEvidence: PlotLabelRegionalEvidence | null;
  } = $props();
</script>

<details class="field-details">
  <summary>Label field values</summary>
  <dl>
    <div>
      <dt>PlotNumber1</dt>
      <dd>{preview.plotNumber1}</dd>
    </div>
    <div>
      <dt>Zone1</dt>
      <dd>{preview.zone1}</dd>
    </div>
    <div>
      <dt>Representing1</dt>
      <dd>
        {preview.representing1 === null
          ? '(NULL)'
          : preview.representing1 === ''
            ? '(empty text)'
            : preview.representing1}
      </dd>
    </div>
    <div>
      <dt>ProjectID1</dt>
      <dd>
        {preview.projectId1 === null ? '(NULL)' : preview.projectId1 === '' ? '(empty text)' : preview.projectId1}
      </dd>
    </div>
  </dl>
  <p>
    Leading and trailing spaces are trimmed on the card for Plot Number and Representing, while exact stored text and
    blank values are listed above.
  </p>
  {#if regionalEvidence}
    <p data-plot-label-regional-date>
      Formatted date ({regionalEvidence.locale}, {regionalEvidence.pattern}): {regionalEvidence.isoDate}.
    </p>
  {/if}
</details>

<style>
  .field-details {
    margin-top: 1rem;
  }
  dl {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 10rem), 1fr));
    gap: 0.75rem;
    min-width: 0;
  }
  dt {
    font-weight: 600;
  }
  dd {
    margin: 0.15rem 0 0;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
</style>
