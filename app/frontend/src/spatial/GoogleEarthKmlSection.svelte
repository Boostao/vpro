<script lang="ts">
  import type { GoogleEarthKMLReview } from '../../bindings/github.com/boostao/vpro/app';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import type { GoogleEarthKMLPublicationSession } from './googleEarthKMLExport';
  import type { ValidatedGoogleEarthFields } from './googleEarthReview';

  type PublicationView = ReturnType<GoogleEarthKMLPublicationSession['view']>;

  let {
    project,
    projectPath,
    su,
    suPath,
    locked = false,
    fields = null,
    selectedField = $bindable(''),
    title = $bindable(''),
    destination = $bindable(''),
    kml = null,
    publication,
    onChangeTitle,
    onChangeField,
    onAcknowledgePublication,
  }: {
    project: string;
    projectPath: string;
    su: string;
    suPath: string;
    locked?: boolean;
    fields?: ValidatedGoogleEarthFields | null;
    selectedField?: string;
    title?: string;
    destination?: string;
    kml?: GoogleEarthKMLReview | null;
    publication: PublicationView;
    onChangeTitle: (event: Event) => void;
    onChangeField: (event: Event) => void;
    onAcknowledgePublication: () => void;
  } = $props();
</script>

{#if publication.requestedDestination && publication.blocked && !publication.busy}
  <section data-google-earth-kml-outcome aria-label="KML file publication outcome">
    {#if !publication.outcome}
      <p role="alert">
        KML publication outcome is unknown. Do not repeat {publication.requestedDestination}; inspect it before
        acknowledging.
      </p>
    {:else}
      <p>Requested destination: {publication.requestedDestination} ({publication.outcome.status}).</p>
    {/if}
    <button type="button" data-google-earth-kml-acknowledge onclick={onAcknowledgePublication}>
      Acknowledge outcome before a new review
    </button>
  </section>
{/if}

<p>
  Project <strong>{project}</strong> · Site Unit <strong>{su}</strong>. Includes all plots with coordinates in the
  current project{su !== 'None' ? ' and Site Unit table' : ''}.
</p>
{#if !IS_WEB_READONLY}
  <dl>
    <div>
      <dt>Project file</dt>
      <dd>{projectPath}</dd>
    </div>
    {#if su !== 'None'}
      <div>
        <dt>Site Unit file</dt>
        <dd>{suPath}</dd>
      </div>
    {/if}
  </dl>
{/if}

<div class="options">
  {#if !IS_WEB_READONLY}
    <div class="field">
      <label for="google-earth-kml-destination">New output file:</label>
      <input
        id="google-earth-kml-destination"
        type="text"
        placeholder="/path/to/plots.kml"
        disabled={locked}
        bind:value={destination}
      />
    </div>
  {/if}
  <div class="field" data-google-earth-kml-controls>
    <label for="google-earth-place-name">Place Name:</label>
    <input id="google-earth-place-name" type="text" disabled={locked} bind:value={title} oninput={onChangeTitle} />
  </div>
  <div class="field">
    <label for="google-earth-description">Description field:</label>
    <select
      id="google-earth-description"
      disabled={locked || !fields}
      bind:value={selectedField}
      onchange={onChangeField}
    >
      <option value="">Choose a plot description field</option>
      {#if selectedField && !fields?.fields.some((field) => field.name === selectedField)}
        <option value={selectedField}>{selectedField} (saved preference — load fields to verify)</option>
      {/if}
      {#each fields?.fields ?? [] as field (field.name)}
        <option value={field.name}>{field.name}</option>
      {/each}
    </select>
  </div>
</div>

<p class="notice">
  Load description fields, choose a text field for placemark descriptions, and enter a full output path for a new
  <code>.kml</code> file (existing files are never overwritten). Edits to Place Name and Description field apply to the
  current preview; use Load saved preferences or Save reviewed preferences to reuse or update your defaults.
  {#if selectedField && !fields?.fields.some((field) => field.name === selectedField)}
    Selected field "{selectedField}" has not been verified in this project yet — click Load description fields before
    exporting.
  {/if}
</p>

{#if kml}
  <p role="status" data-google-earth-kml-summary>
    {kml.placemarkCount} placemarks ({kml.byteCount} bytes) ready to export. Previewing KML does not write a file, change
    saved preferences, or open Google Earth.
  </p>
  <label for="google-earth-kml-text">Prepared KML text:</label>
  <textarea id="google-earth-kml-text" readonly rows="10" value={kml.kml}></textarea>
{/if}

<style>
  .field {
    display: grid;
    grid-template-columns: minmax(10rem, auto) minmax(0, 30rem);
    align-items: center;
    gap: 0.5rem;
  }
  .options {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 280px), 1fr));
    gap: 1rem;
  }
  label,
  dt {
    font-weight: 600;
    color: var(--vpro-navy);
  }
  input,
  select,
  textarea,
  button {
    border: 1px solid var(--vpro-border);
    border-radius: 0.25rem;
    padding: 0.4rem 0.6rem;
    min-width: 0;
    background: var(--vpro-surface);
    color: var(--vpro-ink);
  }
  button {
    border-color: var(--vpro-navy);
    color: var(--vpro-navy);
    font-weight: 600;
  }
  input,
  select,
  textarea {
    width: 100%;
  }
  input:disabled,
  select:disabled,
  textarea:disabled,
  button:disabled {
    opacity: 0.5;
  }
  dl > div {
    margin: 0.6rem 0;
  }
  dd,
  p {
    overflow-wrap: anywhere;
  }
  .notice {
    color: var(--vpro-ink-secondary);
  }
  @media (max-width: 960px) {
    .field {
      grid-template-columns: minmax(0, 1fr);
    }
  }
</style>
