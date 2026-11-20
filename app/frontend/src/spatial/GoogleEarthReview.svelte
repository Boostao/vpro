<script lang="ts">
  import { onDestroy } from 'svelte';
  import {
    SpatialService,
    type GoogleEarthKMLExportReview,
    type GoogleEarthKMLReview,
  } from '../../bindings/github.com/boostao/vpro/app';
  import { wellFormedUTF16 } from '../entry/qualityEditor';
  import { reportCellText } from '../reports/longEnvironmentReport';
  import { ReadRequests, formatError } from '../shared/readRequests';
  import { notifications } from '../shell/notificationService.svelte';
  import GoogleEarthKmlSection from './GoogleEarthKmlSection.svelte';
  import GoogleEarthLocationsTable from './GoogleEarthLocationsTable.svelte';
  import { googleEarthKMLPublicationSession, validateGoogleEarthKMLExportReview } from './googleEarthKMLExport';
  import { googleEarthXMLText } from './googleEarthKMLReview';
  import { googleEarthPreferencesSession } from './googleEarthPreferences';
  import GoogleEarthPreferencesSection from './GoogleEarthPreferencesSection.svelte';
  import {
    validateGoogleEarthFields,
    validateGoogleEarthReview,
    type ValidatedGoogleEarthFields,
    type ValidatedGoogleEarthReview,
  } from './googleEarthReview';

  let {
    contextId,
    project,
    projectPath,
    su,
    suPath,
    onBusyChange,
  }: {
    contextId: string;
    project: string;
    projectPath: string;
    su: string;
    suPath: string;
    onBusyChange: (busy: boolean) => void;
  } = $props();

  let fields = $state<ValidatedGoogleEarthFields | null>(null);
  let selectedField = $state('');
  let review = $state<ValidatedGoogleEarthReview | null>(null);
  let busy = $state(false);
  let error = $state('');
  let title = $state('VPro Plot Locations');
  let kml = $state<GoogleEarthKMLReview | null>(null);
  let approval = $state<GoogleEarthKMLExportReview | null>(null);
  let destination = $state('');

  function scope() {
    return { contextId, project, projectPath, su, suPath };
  }

  const publicationSession = googleEarthKMLPublicationSession(scope());
  let publication = $state(publicationSession.view());
  const preferenceSession = googleEarthPreferencesSession(scope());
  const initialPreferences = preferenceSession.view();
  let preferences = $state(initialPreferences);
  title = initialPreferences.draft.title;
  selectedField = initialPreferences.draft.descriptionField;

  const preferenceLocked = $derived(!!preferences && (preferences.busy || preferences.blocked));
  const locked = $derived(busy || publication.busy || publication.blocked || preferenceLocked);

  function updateBusy() {
    onBusyChange(
      busy ||
        publication.busy ||
        publication.blocked ||
        (!!preferences && (preferences.busy || preferences.blocked || !!preferences.draftError))
    );
  }

  let lastNotifiedKmlKey = '';
  let lastNotifiedPrefKey = '';

  const unsubscribe = publicationSession.subscribe(() => {
    publication = publicationSession.view();
    updateBusy();
    if (publication.busy) return;
    const key = publication.outcome
      ? `outcome:${publication.requestedDestination}:${publication.outcome.status}:${publication.outcome.path}:${publication.outcome.errorMessage}`
      : publication.error
        ? `error:${publication.requestedDestination}:${publication.error}`
        : '';
    if (!key || key === lastNotifiedKmlKey) return;
    lastNotifiedKmlKey = key;
    const meta = { category: 'reports' as const, source: 'Google Earth KML', contextTag: project || undefined };
    if (publication.outcome?.status === 'published') {
      notifications.success(
        'Google Earth KML exported',
        `Exported KML to ${publication.outcome.path || publication.requestedDestination}.`,
        meta
      );
    } else {
      notifications.error(
        'Google Earth KML export failed',
        publication.outcome?.errorMessage || publication.error || 'KML publication reported errors.',
        meta
      );
    }
  });

  const unsubscribePreferences = preferenceSession.subscribe(() => {
    preferences = preferenceSession.view();
    updateBusy();
    if (!preferences || !preferences.attempted || preferences.busy) return;
    const key = preferences.outcome
      ? `outcome:${preferences.outcome.committed}:${preferences.outcome.changed}:${preferences.error}`
      : preferences.error
        ? `error:${preferences.error}`
        : '';
    if (!key || key === lastNotifiedPrefKey) return;
    lastNotifiedPrefKey = key;
    const meta = { category: 'reports' as const, source: 'Google Earth KML', contextTag: project || undefined };
    if (preferences.error) {
      notifications.error(
        preferences.outcome?.committed ? 'Google Earth preference notice' : 'Google Earth preference save failed',
        preferences.error,
        meta
      );
    } else if (preferences.outcome?.committed) {
      notifications.success(
        'Google Earth preferences saved',
        `Saved Google Earth title "${preferences.draft.title}" and description field "${preferences.draft.descriptionField}".`,
        meta
      );
    } else if (preferences.outcome) {
      notifications.info(
        'Google Earth preferences unchanged',
        'Saved preferences already matched the current draft.',
        meta
      );
    }
  });

  const pageSize = 50;
  const reads = new ReadRequests();
  let generation = 0;
  const previousOffset = $derived(review ? Math.max(0, review.offset - pageSize) : 0);
  const nextOffset = $derived(review ? review.offset + pageSize : 0);

  function cancel() {
    generation++;
    preferenceSession.cancelLoad();
    reads.cancelAll();
    busy = false;
    updateBusy();
  }

  function rememberDraft() {
    preferenceSession.edit({ title, descriptionField: selectedField });
  }

  function changeField(event: Event) {
    selectedField = (event.currentTarget as HTMLSelectElement).value;
    cancel();
    rememberDraft();
    [review, kml, approval, error] = [null, null, null, ''];
  }

  function changeTitle(event: Event) {
    title = (event.currentTarget as HTMLInputElement).value;
    cancel();
    rememberDraft();
    [kml, approval, error] = [null, null, ''];
  }

  function undoPreferences() {
    if (locked) return;
    cancel();
    preferenceSession.undo();
    const restored = preferenceSession.view().draft;
    [title, selectedField] = [restored.title, restored.descriptionField];
    review = null;
    kml = null;
    approval = null;
    error = '';
  }

  async function loadPreferences() {
    if (locked) return;
    cancel();
    const request = generation;
    const preferenceRequest = preferenceSession.beginLoad();
    const meta = { category: 'reports' as const, source: 'Google Earth KML', contextTag: project || undefined };
    [error, busy] = ['', true];
    updateBusy();
    try {
      const value = await reads.track(SpatialService.GetGoogleEarthPreferences(contextId));
      if (request !== generation) return;
      if (!preferenceSession.applyLoaded(value, preferenceRequest)) return;
      const applied = preferenceSession.view().draft;
      [title, selectedField] = [applied.title, applied.descriptionField];
      review = null;
      kml = null;
      approval = null;
      if (!googleEarthXMLText(title)) {
        error = 'Saved Place Name contains unsupported control characters; update Place Name before preparing KML.';
        notifications.error('Saved Place Name invalid for KML', error, meta);
      }
    } catch (cause) {
      if (request === generation) {
        error = `Saved preferences unavailable; no defaults applied: ${formatError(cause)}`;
        notifications.error('Saved preferences unavailable', error, meta);
      }
    } finally {
      if (request === generation) {
        busy = false;
        updateBusy();
      }
    }
  }

  async function savePreferences() {
    if (locked || !preferenceSession) return;
    const meta = { category: 'reports' as const, source: 'Google Earth KML', contextTag: project || undefined };
    error = '';
    try {
      await preferenceSession.save(fields?.fields.map((field) => field.name) ?? [], (request) =>
        SpatialService.SaveGoogleEarthPreferences(contextId, JSON.stringify(request))
      );
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
            meta
          );
        } else if (current.outcome?.committed) {
          notifications.success(
            'Google Earth preferences saved',
            `Saved Google Earth title "${current.draft.title}" and description field "${current.draft.descriptionField}".`,
            meta
          );
        } else if (current.outcome) {
          notifications.info(
            'Google Earth preferences unchanged',
            'Saved preferences already matched the current draft.',
            meta
          );
        }
      }
    } catch (cause) {
      error = formatError(cause);
      notifications.error('Google Earth preference save failed', error, meta);
    }
  }

  async function loadFields() {
    const meta = { category: 'reports' as const, source: 'Google Earth KML', contextTag: project || undefined };
    if (locked) {
      error = 'Finish or acknowledge the current operation before reloading fields.';
      notifications.error('Google Earth fields blocked', error, meta);
      return;
    }
    cancel();
    const [request, expected] = [generation, scope()];
    [fields, review, kml, approval, error, busy] = [null, null, null, null, '', true];
    onBusyChange(true);
    try {
      const value = await reads.track(SpatialService.GetGoogleEarthDescriptionFields(contextId));
      if (request !== generation) return;
      fields = validateGoogleEarthFields(value, expected);
      preferenceSession.setPhysicalFields(fields.fields.map((field) => field.name));
    } catch (cause) {
      if (request === generation) {
        error = `Description fields unavailable; no data, audits, preferences or files written: ${formatError(cause)}`;
        notifications.error('Google Earth fields unavailable', error, meta);
      }
    } finally {
      if (request === generation) {
        busy = false;
        updateBusy();
      }
    }
  }

  async function prepareKML() {
    const meta = { category: 'reports' as const, source: 'Google Earth KML', contextTag: project || undefined };
    if (locked) {
      error = 'Finish or acknowledge the current operation before preparing KML.';
      notifications.error('KML preview blocked', error, meta);
      return;
    }
    if (!fields || !fields.fields.some((field) => field.name === selectedField) || !googleEarthXMLText(title)) {
      error = 'Load description fields, choose a field, and enter a valid Place Name before preparing KML.';
      notifications.error('KML preview blocked', error, meta);
      return;
    }
    cancel();
    const [request, expected, descriptionField, placeName] = [generation, scope(), selectedField, title];
    [kml, approval, error, busy] = [null, null, '', true];
    onBusyChange(true);
    try {
      const payload = JSON.stringify({ descriptionField, title: placeName });
      const value = await reads.track(SpatialService.GetGoogleEarthKMLExportReview(contextId, payload));
      if (request !== generation) return;
      const validated = await validateGoogleEarthKMLExportReview(value, expected, descriptionField, placeName);
      if (request !== generation) return;
      [approval, kml] = [validated, validated.review];
    } catch (cause) {
      if (request === generation) {
        error = `KML preview unavailable; no data, audits, preferences or files written: ${formatError(cause)}`;
        notifications.error('KML preview unavailable', error, meta);
      }
    } finally {
      if (request === generation) {
        busy = false;
        updateBusy();
      }
    }
  }

  async function show(offset = 0) {
    const meta = { category: 'reports' as const, source: 'Google Earth KML', contextTag: project || undefined };
    if (locked) {
      error = 'Finish or acknowledge the current operation before another review.';
      notifications.error('Google Earth location review blocked', error, meta);
      return;
    }
    if (!fields || !fields.fields.some((field) => field.name === selectedField)) {
      error = 'Load description fields and choose a field before reviewing plot locations.';
      notifications.error('Google Earth location review blocked', error, meta);
      return;
    }
    cancel();
    const [request, expected, descriptionField] = [generation, scope(), selectedField];
    [review, error, busy] = [null, '', true];
    onBusyChange(true);
    try {
      const value = await reads.track(
        SpatialService.GetGoogleEarthReview(contextId, JSON.stringify({ descriptionField, offset, limit: pageSize }))
      );
      if (request !== generation) return;
      const validated = await validateGoogleEarthReview(value, expected, descriptionField, offset, pageSize);
      if (request !== generation) return;
      review = validated;
    } catch (cause) {
      if (request === generation) {
        error = `Google Earth preparation unavailable; no data, audits, preferences or files written: ${formatError(cause)}`;
        notifications.error('Google Earth review unavailable', error, meta);
      }
    } finally {
      if (request === generation) {
        busy = false;
        updateBusy();
      }
    }
  }

  async function publishKML() {
    const meta = { category: 'reports' as const, source: 'Google Earth KML', contextTag: project || undefined };
    if (locked || !approval) {
      error = 'Prepare an owned KML file review and acknowledge any prior outcome first.';
      notifications.error('KML export blocked', error, meta);
      return;
    }
    error = '';
    try {
      await publicationSession.publish(approval, destination, (request) =>
        SpatialService.ExportReviewedGoogleEarthKML(contextId, JSON.stringify(request))
      );
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
            meta
          );
        } else {
          notifications.error(
            'Google Earth KML export failed',
            current.outcome?.errorMessage || current.error || 'KML publication reported errors.',
            meta
          );
        }
      }
    } catch (cause) {
      error = `KML publication request unavailable: ${formatError(cause)}`;
      notifications.error('Google Earth KML export failed', error, meta);
    }
  }

  function acknowledgePublication() {
    publicationSession.acknowledge();
    [approval, kml] = [null, null];
  }

  onDestroy(cancel);
  onDestroy(unsubscribe);
  onDestroy(() => unsubscribePreferences?.());
</script>

<section class="earth-review" data-google-earth-review aria-label="Google Earth location preparation">
  <header
    class="sticky top-0 z-20 bg-white/95 backdrop-blur-xs py-2 border-b border-vpro-border"
    data-workbench-sticky-bar
  >
    <h1>Google Earth location preparation</h1>
    <div class="actions">
      <button type="button" data-google-earth-fields disabled={locked} onclick={loadFields}
        >Load description fields</button
      >
      <button
        type="button"
        data-google-earth-read
        disabled={locked || !selectedField || !fields}
        onclick={() => show()}
      >
        Review Google Earth locations
      </button>
      <button
        type="button"
        data-google-earth-kml-prepare
        disabled={locked || !selectedField || !fields || !googleEarthXMLText(title)}
        onclick={prepareKML}
      >
        Review KML file export (no file yet)
      </button>
      <button
        type="button"
        data-google-earth-kml-publish
        disabled={locked || !approval || !destination || !wellFormedUTF16(destination) || destination.includes('\0')}
        onclick={publishKML}
      >
        Build reviewed KML file (never replace)
      </button>
      {#if busy}<button type="button" data-google-earth-cancel onclick={cancel}>Cancel preparation read</button>{/if}
    </div>
  </header>

  <GoogleEarthPreferencesSection
    {preferences}
    {locked}
    onLoadPreferences={loadPreferences}
    onSavePreferences={savePreferences}
    onUndoPreferences={undoPreferences}
    onAcknowledgePreferences={() => preferenceSession.acknowledge()}
  />

  <GoogleEarthKmlSection
    {project}
    {projectPath}
    {su}
    {suPath}
    {locked}
    {fields}
    bind:selectedField
    bind:title
    bind:destination
    {kml}
    {publication}
    onChangeTitle={changeTitle}
    onChangeField={changeField}
    onAcknowledgePublication={acknowledgePublication}
  />

  {#if review}
    <GoogleEarthLocationsTable
      {review}
      {locked}
      {previousOffset}
      {nextOffset}
      formatCell={reportCellText}
      onShowPage={(offset) => show(offset)}
    />
  {/if}
</section>

<style>
  .earth-review {
    padding: 1rem;
    min-width: 0;
    max-width: 100%;
    color: var(--vpro-ink);
    background: var(--vpro-surface);
  }
  h1 {
    font-size: 1.5rem;
    margin-bottom: 0.75rem;
    color: var(--vpro-navy);
  }
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
</style>
