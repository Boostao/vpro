<script lang="ts">
  import LongVegetationProjectScopeSelection from '../LongVegetationProjectScopeSelection.svelte';
  import LongVegetationProjectUnitPreferences from '../LongVegetationProjectUnitPreferences.svelte';
  import type { ProjectScopeSelectionSession } from '../longVegetationProjectScopeSession';
  import type { projectReportWorkspace } from '../longVegetationProjectWorkspaces';
  import type { VegetationWorkbookPublicationSession } from '../vegetationWorkbook';

  type Workspace = NonNullable<ReturnType<typeof projectReportWorkspace>>;

  export interface LongVegHeaderState {
    su: string;
    settingsReady: boolean;
    selectedWorkbookScope: string;
    busy: boolean;
    operationHeld: boolean;
    workbookBarrier: boolean;
    preferenceBarrier: boolean;
    sharedPreferenceBarrier: boolean;
    sharedMutationHeld: boolean;
    projectActive: boolean;
    projectWorkspace: Workspace | null;
    projectView: ReturnType<Workspace['view']> | null;
    projectScopeSelection: ProjectScopeSelectionSession | null;
    publication: ReturnType<VegetationWorkbookPublicationSession['view']>;
    preferenceDraftError: string;
    statisticsDraftError: string;
  }

  export interface LongVegHeaderActions {
    onShow: () => void;
    onOptions: () => void;
    onReviewWorkbook: () => void;
    onCancel: () => void;
    onAcknowledgeWorkbook: () => void;
    onProjectChanged: () => void;
  }

  let { state: hs, actions }: { state: LongVegHeaderState; actions: LongVegHeaderActions } = $props();
</script>

<div class="legacy-report-bar">
  <h2>Detailed Long Vegetation Controls</h2>
  <div class="actions">
    <button
      disabled={hs.busy ||
        hs.operationHeld ||
        hs.workbookBarrier ||
        hs.preferenceBarrier ||
        (hs.projectActive ? !hs.projectView?.outputReady : !hs.settingsReady || hs.su === 'None')}
      onclick={actions.onShow}
    >
      View Inline Preview
    </button>
    <button
      disabled={hs.busy ||
        hs.operationHeld ||
        hs.workbookBarrier ||
        hs.preferenceBarrier ||
        (hs.projectActive ? !hs.projectView?.outputReady : !hs.su || hs.su === 'None')}
      onclick={actions.onOptions}
    >
      Reload report options
    </button>
    <button
      disabled={hs.busy ||
        hs.operationHeld ||
        hs.workbookBarrier ||
        hs.preferenceBarrier ||
        (hs.projectActive
          ? !hs.projectView?.outputReady
          : !hs.settingsReady || hs.su === 'None' || hs.su === 'USysSuTableDynamic')}
      onclick={actions.onReviewWorkbook}
    >
      {hs.selectedWorkbookScope === 'unlumped'
        ? 'Review unlumped XLSX workbook (no file yet)'
        : `Review ${hs.selectedWorkbookScope.replace(/^lump:/, '')} XLSX workbook (no file yet)`}
    </button>
    {#if hs.busy || hs.projectView?.readBusy}<button onclick={actions.onCancel}>Cancel report read</button>{/if}
    {#if hs.projectView?.readBusy}
      <button data-project-report-cancel onclick={() => hs.projectWorkspace?.cancelReportRead()}>
        Cancel original project report read
      </button>
    {/if}
  </div>
</div>

{#if hs.su === 'None' && !hs.projectActive}
  <p class="scope-guidance" role="status">
    {hs.projectWorkspace
      ? 'Select an SU in Projects & context, or choose an explicit available whole-project scope before viewing the report.'
      : 'Select an SU in Projects & context before viewing the report.'}
  </p>
{/if}
{#if hs.preferenceDraftError}<p class="error" role="alert">{hs.preferenceDraftError}</p>{/if}
{#if hs.statisticsDraftError}<p class="error" role="alert">{hs.statisticsDraftError}</p>{/if}
{#if !hs.publication.outcome && hs.publication.requestedDestination && !hs.publication.busy}
  <p data-vegetation-workbook-unknown role="alert">
    Workbook outcome unknown. Retain and inspect {hs.publication.requestedDestination}; never replay blindly.
  </p>
{/if}
{#if hs.publication.blocked && !hs.publication.busy}
  <button onclick={actions.onAcknowledgeWorkbook}>Acknowledge workbook outcome</button>
{/if}
{#if hs.projectWorkspace && hs.projectView && hs.projectScopeSelection}
  {@const pw = hs.projectWorkspace}
  {@const pv = hs.projectView}
  {#if !pv.publication?.outcome && pv.publication?.requestedDestination && !pv.publication.busy}
    <p data-project-workbook-unknown role="alert">
      Original project workbook outcome unknown. Retain and inspect {pv.publication.requestedDestination}; never replay
      blindly.
    </p>
  {/if}
  {#if pv.publication?.blocked && !pv.publication.busy}
    <button
      data-project-workbook-acknowledge
      disabled={hs.busy || hs.operationHeld || hs.sharedMutationHeld || hs.publication.busy || hs.publication.blocked}
      onclick={() => pw.workbook?.acknowledge()}
    >
      Acknowledge original project workbook outcome
    </button>
  {/if}
  <LongVegetationProjectScopeSelection
    selection={hs.projectScopeSelection}
    allPlotsAvailable={hs.su === 'None'}
    cancelReads={() => pw.cancelScopeReads()}
    onChange={actions.onProjectChanged}
    operationHeld={hs.busy ||
      hs.operationHeld ||
      hs.workbookBarrier ||
      hs.sharedPreferenceBarrier ||
      pv.scopeOperationHeld}
    mutationHeld={hs.busy || hs.operationHeld || hs.workbookBarrier || hs.sharedMutationHeld || pv.scopeMutationHeld}
  />
  {#if hs.projectActive}
    <LongVegetationProjectUnitPreferences
      preferences={pw.units}
      fetchPreferences={pw.fetchUnitPreferences}
      savePreferences={pw.saveUnitPreferences}
      cancelReads={() => pw.cancelUnitReads()}
      onChange={actions.onProjectChanged}
      operationHeld={hs.busy ||
        hs.operationHeld ||
        hs.workbookBarrier ||
        hs.sharedPreferenceBarrier ||
        pv.unitOperationHeld}
      mutationHeld={hs.busy || hs.operationHeld || hs.workbookBarrier || hs.sharedMutationHeld || pv.unitMutationHeld}
    />
  {/if}
{/if}

<style>
  .legacy-report-bar {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 0.75rem;
  }
  .legacy-report-bar h2 {
    margin: 0;
    font-size: 1.05rem;
    color: var(--vpro-navy);
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    align-items: center;
  }
  button {
    border: 1px solid var(--vpro-navy);
    border-radius: 0.4rem;
    padding: 0.5rem 0.75rem;
    background: var(--vpro-surface);
    color: var(--vpro-navy);
    font-weight: 600;
    cursor: pointer;
  }
  button:hover:not(:disabled) {
    background: var(--vpro-canvas);
  }
  button:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
  .error {
    color: var(--vpro-error);
    font-weight: 600;
  }
  .scope-guidance {
    margin: 0;
    padding: 0.6rem 0.85rem;
    border-left: 4px solid var(--vpro-navy);
    background: var(--vpro-canvas);
    color: var(--vpro-ink);
    border-radius: 0.3rem;
  }
</style>
