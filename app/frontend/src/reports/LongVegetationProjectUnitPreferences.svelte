<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { formatError } from '../shared/readRequests';
  import { notifications } from '../shell/notificationService.svelte';
  import LongVegetationPreferenceSection from '../shared/LongVegetationPreferenceSection.svelte';
  import type {
    LongVegetationProjectUnitOutcome,
    LongVegetationProjectUnitPreferences,
  } from '../../bindings/github.com/boostao/vpro/app';
  import type { ProjectUnitPreferencesSession, ProjectUnitSaveRequest } from './longVegetationProjectUnitSession';

  let {
    preferences,
    fetchPreferences,
    savePreferences,
    cancelReads,
    onChange,
    operationHeld = false,
    mutationHeld = false,
  }: {
    preferences: ProjectUnitPreferencesSession;
    fetchPreferences: (request: {
      revision: string;
      approvalHash: string;
    }) => PromiseLike<LongVegetationProjectUnitPreferences>;
    savePreferences: (request: ProjectUnitSaveRequest) => PromiseLike<LongVegetationProjectUnitOutcome>;
    cancelReads: () => void;
    onChange: () => void;
    operationHeld?: boolean;
    mutationHeld?: boolean;
  } = $props();
  let view = $state.raw(untrack(() => preferences.projectView()));
  let error = $state('');
  let generation = 0;
  const unsubscribe = untrack(() =>
    preferences.subscribe(() => {
      view = preferences.projectView();
      onChange();
    })
  );
  function cancel() {
    generation++;
    cancelReads();
    preferences.cancelRead();
  }
  async function load() {
    if (operationHeld || view.readBusy || view.busy || view.blocked || !view.scope) return;
    const request = ++generation;
    error = '';
    try {
      await preferences.load(fetchPreferences);
    } catch (cause) {
      if (request === generation) {
        error = formatError(cause);
        notifications.error('Long Vegetation project Unit Groups load failed', error, {
          category: 'reports',
          source: 'Long Vegetation',
          contextTag: view.scope?.project || undefined,
        });
      }
    }
  }
  async function save() {
    if (operationHeld || mutationHeld || !view.saveReady) return;
    const request = ++generation;
    error = '';
    try {
      await preferences.saveProject(savePreferences);
    } catch (cause) {
      if (request === generation) {
        error = formatError(cause);
        notifications.error('Long Vegetation project Unit Groups save failed', error, {
          category: 'reports',
          source: 'Long Vegetation',
          contextTag: view.scope?.project || undefined,
        });
      }
    }
  }
  function edit(raw: string) {
    if (mutationHeld || view.readBusy || view.busy || view.blocked || !view.saved) return;
    error = '';
    try {
      preferences.editUnitGroups(raw);
    } catch (cause) {
      error = formatError(cause);
      notifications.error('Long Vegetation project Unit Groups edit failed', error, {
        category: 'reports',
        source: 'Long Vegetation',
        contextTag: view.scope?.project || undefined,
      });
    }
  }
  function undo() {
    if (mutationHeld || view.readBusy || view.busy || view.blocked || !view.saved) return;
    error = '';
    try {
      preferences.undo();
    } catch (cause) {
      error = formatError(cause);
      notifications.error('Long Vegetation project Unit Groups undo failed', error, {
        category: 'reports',
        source: 'Long Vegetation',
        contextTag: view.scope?.project || undefined,
      });
    }
  }
  onDestroy(() => {
    unsubscribe();
    cancel();
  });
</script>

<LongVegetationPreferenceSection
  ariaLabel="Actual saved project Unit Groups"
  sectionAttr="data-project-unit-preferences"
  receiptAttr="data-project-unit-receipt"
  actionPrefix="data-project-unit"
  contextTag={view.scope?.project || undefined}
  titleBase="Long Vegetation project Unit Groups"
  savedChangedMsg="Saved project Unit Groups."
  savedNoChangeMsg="No Unit Groups changes."
  unchangedMsg="No Unit Groups changes were needed."
  draftError={view.draftError}
  viewError={view.error ?? ''}
  readError={view.readError ?? ''}
  authorityUnknown={view.authorityUnknown}
  unknownOutcomeBanner="Unit Groups outcome is unknown. Acknowledge the receipt, then Load actual saved values. The retained draft is not replayed automatically."
  receipts={view.projectReceipts}
  formatSavedMessage={(req, changed) =>
    changed
      ? `Revision ${req?.revision}: Unit Groups set to ${req?.proposed.unitGroups}.`
      : `Revision ${req?.revision}: No Unit Groups changes.`}
  loadDisabled={operationHeld || view.readBusy || view.busy || view.blocked || !view.scope}
  saveDisabled={operationHeld || mutationHeld || !view.saveReady}
  undoDisabled={mutationHeld || view.readBusy || view.busy || view.blocked || !view.saved}
  acknowledgeVisible={view.blocked && !view.busy}
  acknowledgeDisabled={mutationHeld || view.readBusy}
  cancelVisible={view.readBusy}
  cancelAttr={true}
  loadLabel="Load actual saved Unit Groups"
  saveLabel="Save Unit Groups"
  undoLabel="Undo Unit Groups draft"
  acknowledgeLabel="Acknowledge Unit Groups outcome"
  cancelLabel="Cancel Unit Groups read"
  guidance={'Build the explicit project source before Load. Actual saved values are never normalized into ' +
    'the planned source choice. Save only the choice matching that source; changing source requires ' +
    'an explicit scope switch. Drafts do not change report output. Receipts remain after ' +
    'acknowledgement and tab remounts. Only LVUnitGroups changes in YAML; no project data, audits, ' +
    'registry or printing.'}
  onload={load}
  onsave={save}
  onundo={undo}
  onacknowledge={() => preferences.acknowledge()}
  oncancel={cancel}
>
  <label for="project-unit-groups">
    <span>Unit Groups</span>
    <select
      id="project-unit-groups"
      data-source-control="rptLvUnitGroups"
      value={view.draft.unitGroups}
      aria-invalid={!!view.draftError}
      disabled={mutationHeld || view.readBusy || view.busy || view.blocked || !view.saved}
      onchange={(event) => {
        const raw = event.currentTarget.value;
        edit(raw);
      }}
    >
      <option value="" disabled>Load actual saved Unit Groups</option>
      <option value="1" disabled={view.saved?.unitGroups !== 1}>Site unit table (saved value only)</option>
      <option value="2" disabled={view.scope?.sourceKind !== 'project-selected-fields' && view.saved?.unitGroups !== 2}
        >Selected fields</option
      >
      <option value="3" disabled={view.scope?.sourceKind !== 'project-all-plots' && view.saved?.unitGroups !== 3}
        >None (All plots)</option
      >
    </select>
  </label>
  {#if view.saved}<p data-project-unit-actual>
      Actual saved Unit Groups: {view.saved.unitGroups}. Draft: {view.draft.unitGroups}.
    </p>{/if}
</LongVegetationPreferenceSection>

<style>
  label {
    display: grid;
    gap: 0.35rem;
    min-width: 0;
  }
  select {
    width: 100%;
    box-sizing: border-box;
    min-width: 0;
    border: 1px solid var(--vpro-border);
    border-radius: 0.4rem;
    padding: 0.5rem;
  }
  p,
  span {
    overflow-wrap: anywhere;
  }
</style>
