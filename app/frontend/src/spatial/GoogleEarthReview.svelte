<script lang="ts">
  import { onDestroy } from 'svelte';
  import { SpatialService, type GoogleEarthKMLReview, type GoogleEarthKMLExportReview } from '../../bindings/github.com/boostao/vpro/app';
  import { ReadRequests } from '../shared/readRequests';
  import { reportCellText } from '../reports/longEnvironmentReport';
  import { validateGoogleEarthFields, validateGoogleEarthReview, type ValidatedGoogleEarthFields, type ValidatedGoogleEarthReview } from './googleEarthReview';
  import { googleEarthXMLText, validateGoogleEarthKMLReview } from './googleEarthKMLReview';
  import { validateGoogleEarthKMLExportReview, googleEarthKMLPublicationSession } from './googleEarthKMLExport';
  import { wellFormedUTF16 } from '../entry/qualityEditor';
  import { googleEarthPreferencesSession } from './googleEarthPreferences';
  import { notifications } from '../shell/notificationService.svelte';

  let { contextId, project, projectPath, su, suPath, onBusyChange }: {
    contextId: string; project: string; projectPath: string; su: string; suPath: string; onBusyChange: (busy: boolean) => void;
  } = $props();
  let fields = $state<ValidatedGoogleEarthFields | null>(null);
  let selectedField = $state('');
  let review = $state<ValidatedGoogleEarthReview | null>(null);
  let busy = $state(false);
  let error = $state('');
  const kmlEnabled = true;
  const kmlExportEnabled = true;
  const preferencesEnabled = true;
  let title = $state('VPro Plot Locations');
  let kml = $state<GoogleEarthKMLReview | null>(null);
  let approval = $state<GoogleEarthKMLExportReview | null>(null);
  let destination = $state('');
  const publicationSession = googleEarthKMLPublicationSession(scope());
  let publication = $state(publicationSession.view());
  const preferenceSession = preferencesEnabled ? googleEarthPreferencesSession(scope()) : null;
  const initialPreferences = preferenceSession?.view() ?? null;
  let preferences = $state(initialPreferences);
  if (initialPreferences) { title = initialPreferences.draft.title; selectedField = initialPreferences.draft.descriptionField; }
  const preferenceLocked = $derived(!!preferences && (preferences.busy || preferences.blocked));
  const locked = $derived(busy || publication.busy || publication.blocked || preferenceLocked);
  function updateBusy() { onBusyChange(busy || publication.busy || publication.blocked || !!preferences && (preferences.busy || preferences.blocked || !!preferences.draftError)); }
  let lastNotifiedKmlKey = '';
  let lastNotifiedPrefKey = '';
  const unsubscribe = publicationSession.subscribe(() => {
    publication = publicationSession.view();
    updateBusy();
    if (!publication.busy && typeof notifications !== 'undefined') {
      const key = publication.outcome
        ? `outcome:${publication.requestedDestination}:${publication.outcome.status}:${publication.outcome.path}:${publication.outcome.errorMessage}`
        : publication.error
          ? `error:${publication.requestedDestination}:${publication.error}`
          : '';
      if (key && key !== lastNotifiedKmlKey) {
        lastNotifiedKmlKey = key;
        if (publication.outcome?.status === 'published') {
          notifications.success(
            'Google Earth KML exported',
            `Exported KML to ${publication.outcome.path || publication.requestedDestination}.`,
            { category: 'reports', source: 'Google Earth KML', contextTag: project || undefined },
          );
        } else {
          notifications.error(
            'Google Earth KML export failed',
            publication.outcome?.errorMessage || publication.error || 'KML publication reported errors.',
            { category: 'reports', source: 'Google Earth KML', contextTag: project || undefined },
          );
        }
      }
    }
  });
  const unsubscribePreferences = preferenceSession?.subscribe(() => {
    preferences = preferenceSession.view();
    updateBusy();
    if (preferences && preferences.attempted && !preferences.busy && typeof notifications !== 'undefined') {
      const key = preferences.outcome
        ? `outcome:${preferences.outcome.committed}:${preferences.outcome.changed}:${preferences.error}`
        : preferences.error
          ? `error:${preferences.error}`
          : '';
      if (key && key !== lastNotifiedPrefKey) {
        lastNotifiedPrefKey = key;
        if (preferences.error) {
          notifications.error(
            preferences.outcome?.committed ? 'Google Earth preference notice' : 'Google Earth preference save failed',
            preferences.error,
            { category: 'reports', source: 'Google Earth KML', contextTag: project || undefined },
          );
        } else if (preferences.outcome?.committed) {
          notifications.success(
            'Google Earth preferences saved',
            `Saved Google Earth title "${preferences.draft.title}" and description field "${preferences.draft.descriptionField}".`,
            { category: 'reports', source: 'Google Earth KML', contextTag: project || undefined },
          );
        } else if (preferences.outcome) {
          notifications.info(
            'Google Earth preferences unchanged',
            'Saved preferences already matched the current draft.',
            { category: 'reports', source: 'Google Earth KML', contextTag: project || undefined },
          );
        }
      }
    }
  });
  const pageSize = 50;
  const reads = new ReadRequests();
  let generation = 0;
  const previousOffset = $derived(review ? Math.max(0, review.offset - pageSize) : 0);
  const nextOffset = $derived(review ? review.offset + pageSize : 0);
  function scope() { return { contextId, project, projectPath, su, suPath }; }
  function cancel() { generation++; preferenceSession?.cancelLoad(); reads.cancelAll(); busy = false; updateBusy(); }
  function rememberDraft() { preferenceSession?.edit({ title, descriptionField: selectedField }); }
  function changeField(event: Event) {
    selectedField = (event.currentTarget as HTMLSelectElement).value;
    cancel(); rememberDraft(); review = null; kml = null; approval = null; error = '';
  }
  function changeTitle(event: Event) {
    title = (event.currentTarget as HTMLInputElement).value;
    cancel(); rememberDraft(); kml = null; approval = null;
    error = preferencesEnabled || googleEarthXMLText(title) ? '' : 'Place Name contains unsupported control characters; remove them before preparing KML.';
  }
  function undoPreferences() {
    if (locked || !preferenceSession) return;
    cancel(); preferenceSession.undo();
    const restored = preferenceSession.view().draft;
    title = restored.title; selectedField = restored.descriptionField;
    review = null; kml = null; approval = null; error = '';
  }
  async function loadPreferences() {
    if (locked || !preferenceSession) return;
    cancel(); const request = generation, preferenceRequest = preferenceSession.beginLoad();
    error = ''; busy = true; updateBusy();
    try {
      const value = await reads.track(SpatialService.GetGoogleEarthPreferences(contextId));
      if (request !== generation) return;
      if (!preferenceSession.applyLoaded(value, preferenceRequest)) return;
      const applied = preferenceSession.view().draft;
      title = applied.title; selectedField = applied.descriptionField;
      review = null; kml = null; approval = null;
      if (!googleEarthXMLText(title)) {
        error = 'Saved Place Name contains unsupported control characters; update Place Name before preparing KML.';
        notifications.error('Saved Place Name invalid for KML', error, { category: 'reports', source: 'Google Earth KML', contextTag: project || undefined });
      }
    } catch (cause) {
      if (request === generation) {
        error = `Saved preferences unavailable; no defaults applied: ${String(cause)}`;
        notifications.error('Saved preferences unavailable', error, { category: 'reports', source: 'Google Earth KML', contextTag: project || undefined });
      }
    } finally {
      if (request === generation) { busy = false; updateBusy(); }
    }
  }
  async function savePreferences() {
    if (locked || !preferenceSession) return;
    error = '';
    try {
      await preferenceSession.save(fields?.fields.map(field => field.name) ?? [], request =>
        SpatialService.SaveGoogleEarthPreferences(contextId, JSON.stringify(request)));
      const current = preferenceSession.view();
      const key = current.outcome
        ? `outcome:${current.outcome.committed}:${current.outcome.changed}:${current.error}`
        : current.error
          ? `error:${current.error}`
          : '';
      if (typeof lastNotifiedPrefKey === 'undefined' || (key && lastNotifiedPrefKey !== key)) {
        if (typeof lastNotifiedPrefKey !== 'undefined' && key) lastNotifiedPrefKey = key;
        if (current.error) {
          notifications.error(
            current.outcome?.committed ? 'Google Earth preference notice' : 'Google Earth preference save failed',
            current.error,
            { category: 'reports', source: 'Google Earth KML', contextTag: project || undefined },
          );
        } else if (current.outcome?.committed) {
          notifications.success(
            'Google Earth preferences saved',
            `Saved Google Earth title "${current.draft.title}" and description field "${current.draft.descriptionField}".`,
            { category: 'reports', source: 'Google Earth KML', contextTag: project || undefined },
          );
        } else if (current.outcome) {
          notifications.info(
            'Google Earth preferences unchanged',
            'Saved preferences already matched the current draft.',
            { category: 'reports', source: 'Google Earth KML', contextTag: project || undefined },
          );
        }
      }
    } catch (cause) {
      error = String(cause);
      notifications.error('Google Earth preference save failed', error, { category: 'reports', source: 'Google Earth KML', contextTag: project || undefined });
    }
  }
  async function loadFields() {
    if (locked) {
      error = 'Finish or acknowledge the current operation before reloading fields.';
      notifications.error('Google Earth fields blocked', error, { category: 'reports', source: 'Google Earth KML', contextTag: project || undefined });
      return;
    }
    cancel(); const request = generation, expected = scope();
    fields = null; if (!preferencesEnabled) selectedField = ''; review = null; kml = null; approval = null; error = ''; busy = true; onBusyChange(true);
    try {
      const value = await reads.track(SpatialService.GetGoogleEarthDescriptionFields(contextId));
      if (request !== generation) return;
      fields = validateGoogleEarthFields(value, expected);
      preferenceSession?.setPhysicalFields(fields.fields.map(field => field.name));
    } catch (cause) {
      if (request === generation) {
        error = `Description fields unavailable; no data, audits, preferences or files written: ${String(cause)}`;
        notifications.error('Google Earth fields unavailable', error, { category: 'reports', source: 'Google Earth KML', contextTag: project || undefined });
      }
    } finally {
      if (request === generation) { busy = false; updateBusy(); }
    }
  }
  async function prepareKML() {
    if (locked) {
      error = 'Finish or acknowledge the current operation before preparing KML.';
      notifications.error('KML preview blocked', error, { category: 'reports', source: 'Google Earth KML', contextTag: project || undefined });
      return;
    }
    if (!fields || !fields.fields.some(field => field.name === selectedField) || !googleEarthXMLText(title)) {
      error = 'Load description fields, choose a field, and enter a valid Place Name before preparing KML.';
      notifications.error('KML preview blocked', error, { category: 'reports', source: 'Google Earth KML', contextTag: project || undefined });
      return;
    }
    cancel(); const request = generation, expected = scope(), descriptionField = selectedField, placeName = title;
    kml = null; approval = null; error = ''; busy = true; onBusyChange(true);
    try {
      const payload = JSON.stringify({ descriptionField, title: placeName });
      if (kmlExportEnabled) {
        const value = await reads.track(SpatialService.GetGoogleEarthKMLExportReview(contextId, payload));
        if (request !== generation) return;
        const validated = await validateGoogleEarthKMLExportReview(value, expected, descriptionField, placeName);
        if (request !== generation) return;
        approval = validated; kml = validated.review;
      } else {
        const value = await reads.track(SpatialService.GetGoogleEarthKMLReview(contextId, payload));
        if (request !== generation) return;
        const validated = await validateGoogleEarthKMLReview(value, expected, descriptionField, placeName);
        if (request !== generation) return;
        kml = validated;
      }
    } catch (cause) {
      if (request === generation) {
        error = `KML preview unavailable; no data, audits, preferences or files written: ${String(cause)}`;
        notifications.error('KML preview unavailable', error, { category: 'reports', source: 'Google Earth KML', contextTag: project || undefined });
      }
    } finally {
      if (request === generation) { busy = false; updateBusy(); }
    }
  }
  async function show(offset = 0) {
    if (locked) {
      error = 'Finish or acknowledge the current operation before another review.';
      notifications.error('Google Earth location review blocked', error, { category: 'reports', source: 'Google Earth KML', contextTag: project || undefined });
      return;
    }
    if (!fields || !fields.fields.some(field => field.name === selectedField)) {
      error = 'Load description fields and choose a field before reviewing plot locations.';
      notifications.error('Google Earth location review blocked', error, { category: 'reports', source: 'Google Earth KML', contextTag: project || undefined });
      return;
    }
    cancel(); const request = generation, expected = scope(), descriptionField = selectedField;
    review = null; error = ''; busy = true; onBusyChange(true);
    try {
      const value = await reads.track(SpatialService.GetGoogleEarthReview(contextId,
        JSON.stringify({ descriptionField, offset, limit: pageSize })));
      if (request !== generation) return;
      const validated = await validateGoogleEarthReview(value, expected, descriptionField, offset, pageSize);
      if (request !== generation) return;
      review = validated;
    } catch (cause) {
      if (request === generation) {
        error = `Google Earth preparation unavailable; no data, audits, preferences or files written: ${String(cause)}`;
        notifications.error('Google Earth review unavailable', error, { category: 'reports', source: 'Google Earth KML', contextTag: project || undefined });
      }
    } finally {
      if (request === generation) { busy = false; updateBusy(); }
    }
  }
  async function publishKML() {
    if (locked || !approval) {
      error = 'Prepare an owned KML file review and acknowledge any prior outcome first.';
      notifications.error('KML export blocked', error, { category: 'reports', source: 'Google Earth KML', contextTag: project || undefined });
      return;
    }
    error = '';
    try {
      await publicationSession.publish(approval, destination, request =>
        SpatialService.ExportReviewedGoogleEarthKML(contextId, JSON.stringify(request)));
      const current = publicationSession.view();
      const key = current.outcome
        ? `outcome:${current.requestedDestination}:${current.outcome.status}:${current.outcome.path}:${current.outcome.errorMessage}`
        : current.error
          ? `error:${current.requestedDestination}:${current.error}`
          : '';
      if (typeof lastNotifiedKmlKey === 'undefined' || (key && lastNotifiedKmlKey !== key)) {
        if (typeof lastNotifiedKmlKey !== 'undefined' && key) lastNotifiedKmlKey = key;
        if (current.outcome?.status === 'published') {
          notifications.success(
            'Google Earth KML exported',
            `Exported KML to ${current.outcome.path || destination}.`,
            { category: 'reports', source: 'Google Earth KML', contextTag: project || undefined },
          );
        } else {
          notifications.error(
            'Google Earth KML export failed',
            current.outcome?.errorMessage || current.error || 'KML publication reported errors.',
            { category: 'reports', source: 'Google Earth KML', contextTag: project || undefined },
          );
        }
      }
    } catch (cause) {
      error = `KML publication request unavailable: ${String(cause)}`;
      notifications.error('Google Earth KML export failed', error, { category: 'reports', source: 'Google Earth KML', contextTag: project || undefined });
    }
  }
  function acknowledgePublication() {
    publicationSession.acknowledge(); approval = null; kml = null;
  }
  onDestroy(cancel);
  onDestroy(unsubscribe);
  onDestroy(() => unsubscribePreferences?.());
</script>

<section class="earth-review" data-google-earth-review aria-label="Google Earth location preparation">
  <header class="sticky top-0 z-20 bg-white/95 backdrop-blur-xs py-2 border-b border-vpro-border" data-workbench-sticky-bar>
    <h1>Google Earth location preparation</h1>
    <div class="actions">
      <button type="button" data-google-earth-fields disabled={locked} onclick={loadFields}>Load description fields</button>
      <button type="button" data-google-earth-read disabled={locked || !selectedField || !fields} onclick={() => show()}>Review Google Earth locations</button>
      {#if kmlEnabled || kmlExportEnabled}
        <button type="button" data-google-earth-kml-prepare disabled={locked || !selectedField || !fields || !googleEarthXMLText(title)}
          onclick={prepareKML}>{kmlExportEnabled ? 'Review KML file export (no file yet)' : 'Prepare KML text (no file)'}</button>
        {#if kmlExportEnabled}
          <button type="button" data-google-earth-kml-publish
            disabled={locked || !approval || !destination || !wellFormedUTF16(destination) || destination.includes('\0')}
            onclick={publishKML}>Build reviewed KML file (never replace)</button>
        {/if}
      {/if}
      {#if busy}<button type="button" data-google-earth-cancel onclick={cancel}>Cancel preparation read</button>{/if}
    </div>
  </header>
  {#if preferences?.draftError}<p class="error" role="alert" data-google-earth-preferences-draft-error>{preferences.draftError}</p>{/if}
  {#if preferencesEnabled && preferences}
    <section data-google-earth-preferences aria-label="Reviewed Google Earth preferences">
      <button type="button" data-google-earth-preferences-load disabled={locked} onclick={loadPreferences}>Load saved preferences (apply to live fields)</button>
      <button type="button" data-google-earth-preferences-save disabled={locked || !preferences.saved || !!preferences.draftError} onclick={savePreferences}>Save reviewed preferences</button>
      <button type="button" data-google-earth-preferences-undo disabled={locked || !preferences.saved} onclick={undoPreferences}>Undo preference draft</button>
      {#if preferences.blocked && !preferences.busy}
        <div data-google-earth-preferences-outcome>
          {#if !preferences.outcome}
            <p role="alert">Preference save outcome is unknown. Do not replay; acknowledge and explicitly reload saved preferences before another save.</p>
          {:else}
            <p role="status">Preference save attempt requires acknowledgement before continuing.</p>
          {/if}
          <button type="button" data-google-earth-preferences-acknowledge disabled={preferences.busy || !preferences.blocked}
            onclick={() => preferenceSession?.acknowledge()}>Acknowledge preference outcome</button>
        </div>
      {/if}
    </section>
  {/if}
  {#if publication.requestedDestination && publication.blocked && !publication.busy}
    <section data-google-earth-kml-outcome aria-label="KML file publication outcome">
      {#if !publication.outcome}
        <p role="alert">KML publication outcome is unknown. Do not repeat {publication.requestedDestination}; inspect it before acknowledging.</p>
      {:else}
        <p>Requested destination: {publication.requestedDestination} ({publication.outcome.status}).</p>
      {/if}
      <button type="button" data-google-earth-kml-acknowledge onclick={acknowledgePublication}>Acknowledge outcome before a new review</button>
    </section>
  {/if}
  <p>Project <strong>{project}</strong> · Site Unit <strong>{su}</strong>. Includes all plots with coordinates in the current project{su !== 'None' ? ' and Site Unit table' : ''}.</p>
  <dl><div><dt>Project file</dt><dd>{projectPath}</dd></div>
    {#if su !== 'None'}<div><dt>Site Unit file</dt><dd>{suPath}</dd></div>{/if}</dl>
  <div class="options">
  {#if kmlExportEnabled}
    <div class="field">
      <label for="google-earth-kml-destination">New output file:</label>
      <input id="google-earth-kml-destination" type="text" placeholder="/path/to/plots.kml" disabled={locked} bind:value={destination} />
    </div>
  {/if}
  {#if kmlEnabled || kmlExportEnabled || preferencesEnabled}
    <div class="field" data-google-earth-kml-controls>
      <label for="google-earth-place-name">Place Name:</label>
      <input id="google-earth-place-name" type="text" disabled={locked} bind:value={title} oninput={changeTitle} />
    </div>
  {/if}
  <div class="field">
    <label for="google-earth-description">Description field:</label>
    <select id="google-earth-description" disabled={locked || !fields} bind:value={selectedField} onchange={changeField}>
      <option value="">Choose a plot description field</option>
      {#if preferencesEnabled && selectedField && !fields?.fields.some(field => field.name === selectedField)}
        <option value={selectedField}>{selectedField} (saved preference — load fields to verify)</option>
      {/if}
      {#each fields?.fields ?? [] as field (field.name)}<option value={field.name}>{field.name}</option>{/each}
    </select>
  </div>
  </div>
  <p class="notice">
    Load description fields, choose a text field for placemark descriptions, and enter a full output path for a new <code>.kml</code> file (existing files are never overwritten).
    {#if preferencesEnabled}
      Edits to Place Name and Description field apply to the current preview; use Load saved preferences or Save reviewed preferences to reuse or update your defaults.
      {#if selectedField && !fields?.fields.some(field => field.name === selectedField)}
        Selected field "{selectedField}" has not been verified in this project yet — click Load description fields before exporting.
      {/if}
    {/if}
    {#if !kmlExportEnabled}KML file export is currently unavailable.{/if}
  </p>
  {#if kmlEnabled || kmlExportEnabled}
    {#if kml}
      <p role="status" data-google-earth-kml-summary>{kml.placemarkCount} placemarks ({kml.byteCount} bytes) ready to export.
        {#if preferencesEnabled}Previewing KML does not write a file, change saved preferences, or open Google Earth.
        {:else if !publication.requestedDestination}No file created, preference saved or viewer launched.
        {:else}Previewing KML does not write a file; see the export status above.{/if}</p>
      <label for="google-earth-kml-text">Prepared KML text:</label>
      <textarea id="google-earth-kml-text" readonly rows="10" value={kml.kml}></textarea>
    {/if}
  {/if}
  {#if review}
    <p role="status" data-google-earth-summary>{review.totalRows} plot locations with latitude and longitude ready for export.
      {#if preferencesEnabled}Previewing plot locations does not modify project data, saved preferences, or files on disk.
      {:else}No data, audits, preferences or files written.{/if}</p>
    <div class="table-scroll">
      <table>
        <caption>Plot coordinates for Google Earth export (signed decimal longitude and latitude)</caption>
        <thead><tr>{#each review.fields as field, i}<th id={`earth-field-${i}`} scope="col">{field.label}</th>{/each}</tr></thead>
        <tbody>{#each review.rows as row (`${row.envRowId}:${row.membershipRowId}`)}
          <tr data-google-earth-row={`${row.envRowId}:${row.membershipRowId}`}>
            {#each [row.plotNumber, row.longitude, row.latitude, row.description] as cell, i}
              <td headers={`earth-field-${i}`} aria-label={`${review.fields[i].label} for plot record ${row.envRowId}, Site Unit record ${row.membershipRowId || 'not selected'}`}>{reportCellText(cell)}</td>
            {/each}
          </tr>
        {:else}<tr><td colspan="4">No plot coordinates found on this page.</td></tr>{/each}</tbody>
      </table>
    </div>
    <div class="actions" aria-label="Google Earth preparation pages">
      <button type="button" disabled={locked || review.offset === 0} onclick={() => show(previousOffset)}>Previous pairs</button>
      <span>{review.rows.length ? review.offset + 1 : 0}-{review.rows.length ? review.offset + review.rows.length : 0} of {review.totalRows}</span>
      <button type="button" disabled={locked || review.offset + review.rows.length >= review.totalRows} onclick={() => show(nextOffset)}>Next pairs</button>
    </div>
    <details><summary>Plot record details for this page</summary>
      {#each review.rows as row (`${row.envRowId}:${row.membershipRowId}`)}
        <p>Plot record {row.envRowId}; Site Unit record {row.membershipRowId || 'not selected'};
          stored longitude {reportCellText(row.storedLongitude)}.</p>
      {/each}
    </details>
  {/if}
</section>

<style>
  .earth-review { padding: 1rem; min-width: 0; max-width: 100%; color: var(--vpro-ink); background: var(--vpro-surface); }
  h1 { font-size: 1.5rem; margin-bottom: .75rem; color: var(--vpro-navy); }
  .actions { display: flex; flex-wrap: wrap; align-items: center; gap: .75rem; margin: 1rem 0; }
  .field { display: grid; grid-template-columns: minmax(10rem, auto) minmax(0, 30rem); align-items: center; gap: .5rem; }
  .options { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 280px), 1fr)); gap: 1rem; }
  label, dt { font-weight: 600; color: var(--vpro-navy); }
  input, select, textarea, button { border: 1px solid var(--vpro-border); border-radius: .25rem; padding: .4rem .6rem; min-width: 0; background: var(--vpro-surface); color: var(--vpro-ink); }
  button { border-color: var(--vpro-navy); color: var(--vpro-navy); font-weight: 600; }
  input, select, textarea { width: 100%; }
  input:disabled, select:disabled, textarea:disabled, button:disabled { opacity: .5; }
  dl > div { margin: .6rem 0; }
  dd, p { overflow-wrap: anywhere; }
  .table-scroll { overflow-x: auto; max-width: 100%; }
  table { border-collapse: collapse; width: 100%; }
  th, td { border: 1px solid var(--vpro-border); padding: .4rem .6rem; text-align: left; vertical-align: top; white-space: pre-wrap; }
  th { background: var(--vpro-canvas); color: var(--vpro-navy); }
  caption { text-align: left; margin-bottom: .5rem; color: var(--vpro-ink-secondary); }
  .notice { color: var(--vpro-ink-secondary); }
  .error { color: var(--vpro-error); }
  @media (max-width: 960px) { .field { grid-template-columns: minmax(0, 1fr); } }
</style>
