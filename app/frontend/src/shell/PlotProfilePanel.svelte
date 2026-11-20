<script lang="ts">
  import { tick } from 'svelte';
  import {
    ContextService,
    type PlotPage,
    type PlotProfileSource,
    type PlotProfileSourceInfo,
    type ProjectPlotProfileFilterRequest,
  } from '../../bindings/github.com/boostao/vpro/app';
  import type { PlotSummary } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
  import { validateProfileFileReview, type ReviewedProfileFile } from '../classification/profileFile';
  import { validateProfileSUReview, type ReviewedProfileSU } from '../classification/profileSU';
  import { validateProjectSUReview, type ReviewedProjectSU } from '../classification/profileSUProject';
  import { validateProfileTableReview, type ReviewedProfileTable } from '../classification/profileTable';
  import {
    validatePlotProfileSource,
    validateProjectPlotProfileReview,
    type ProfileNavigation,
    type ValidatedProjectPlotProfileReview,
  } from '../classification/projectPlotProfileReview';
  import { formatError, type ReadRequests } from '../shared/readRequests';
  import { projectState } from '../shared/state';
  import {
    choosePlotProfileOp,
    createBlankProfileFileOp,
    createBlankProfileTableOp,
    publishProfileWriteOwnershipOp,
    saveProfileSUOp,
    saveProfileSUProjectOp,
  } from './plotProfileOps';
  import PlotProfileSelectionSection from './PlotProfileSelectionSection.svelte';
  import PlotProfileSUSection from './PlotProfileSUSection.svelte';

  let {
    view = $bindable(),
    busy = $bindable(false),
    error = $bindable(''),
    editorPlotNumber = $bindable(undefined),
    profileNavigation = $bindable(null),
    selected = $bindable(null),
    page = $bindable(null),
    operationHeld = false,
    editorBusy = false,
    vegetationPublicationBusy = false,
    lifeformPublicationBusy = false,
    summaryPublicationBusy = false,
    transitionWorking = false,
    pendingTransition = null,
    closeRequest = '',
    profileIndex,
    stateReads,
    requestTransition,
    loadPlots,
    navigateProfilePlot,
    clearProfileNavigation,
    cancelAllReads,
  }: {
    view: string;
    busy: boolean;
    error: string;
    editorPlotNumber: string | undefined;
    profileNavigation: ProfileNavigation | null;
    selected: PlotSummary | null;
    page: PlotPage | null;
    operationHeld?: boolean;
    editorBusy?: boolean;
    vegetationPublicationBusy?: boolean;
    lifeformPublicationBusy?: boolean;
    summaryPublicationBusy?: boolean;
    transitionWorking?: boolean;
    pendingTransition?: unknown;
    closeRequest?: string;
    profileIndex: number;
    stateReads: ReadRequests;
    requestTransition: (run: (contextId: string) => Promise<void>) => Promise<void>;
    loadPlots: (nextOffset: number) => Promise<void>;
    navigateProfilePlot: (delta: number) => Promise<void>;
    clearProfileNavigation: () => Promise<void>;
    cancelAllReads: () => void;
  } = $props();

  let profileTableReview = $state<ReviewedProfileTable | null>(null),
    profileTableContext = $state(''),
    profileTableName = $state('');
  let profileTableError = $state(''),
    profileTableSuccess = $state(''),
    profileTableCommitted = $state(false);
  let profileFileReview = $state<ReviewedProfileFile | null>(null),
    profileFileContext = $state(''),
    profileFileName = $state(''),
    profileFilePath = $state('');
  let profileFileError = $state(''),
    profileFileSuccess = $state(''),
    profileFileCommitted = $state(false);
  let profileWriteReview = $state<ValidatedProjectPlotProfileReview | null>(null),
    profileWriteContext = $state(''),
    profileWriteError = $state('');
  let profilePath = $state(''),
    profileSources = $state<PlotProfileSourceInfo[]>([]),
    profileSourceContext = $state(''),
    profileSourceError = $state('');
  let suReview = $state<ReviewedProfileSU | null>(null),
    suReviewContext = $state(''),
    suName = $state(''),
    suPath = $state('');
  let suError = $state(''),
    suSuccess = $state(''),
    suCommitted = $state(false);
  let suProjectReview = $state<ReviewedProjectSU | null>(null),
    suProjectContext = $state(''),
    suProjectName = $state('');
  let suProjectError = $state(''),
    suProjectSuccess = $state(''),
    suProjectCommitted = $state(false);

  const mutationHost = {
    setBusy: (b: boolean) => {
      busy = b;
    },
    getError: () => error,
    setError: (msg: string) => {
      error = msg;
    },
    resetToPlotsView: () => {
      view = 'plots';
      editorPlotNumber = undefined;
    },
    resetContextAfterProfileSwitch: (state: Awaited<ReturnType<typeof ContextService.GetState>>) => {
      projectState.set(state);
      profileNavigation = null;
      profileSources = [];
      profileSourceContext = '';
      selected = null;
      page = null;
      editorPlotNumber = undefined;
      view = 'plots';
      error = '';
    },
    loadPlotsZero: () => loadPlots(0),
    cancelAllReads: () => cancelAllReads(),
    get stateReads() {
      return stateReads;
    },
    getCurrentContextId: () => $projectState?.contextId,
    requestTransition: (run: (contextId: string) => Promise<void>) => requestTransition(run),
  };

  export function clearCachedSources() {
    profileSources = [];
    profileSourceContext = '';
  }

  export function resetAllReviews() {
    profileSources = [];
    profileSourceContext = '';
    profileWriteReview = null;
    profileWriteContext = '';
    profileWriteError = '';
    suReview = null;
    suReviewContext = '';
    suError = '';
    suSuccess = '';
    suCommitted = false;
    suProjectReview = null;
    suProjectContext = '';
    suProjectError = '';
    suProjectSuccess = '';
    suProjectCommitted = false;
  }

  async function inspectProfileSources() {
    const contextId = $projectState?.contextId;
    if (
      !contextId ||
      operationHeld ||
      busy ||
      editorBusy ||
      vegetationPublicationBusy ||
      lifeformPublicationBusy ||
      summaryPublicationBusy ||
      transitionWorking ||
      pendingTransition !== null ||
      closeRequest
    ) {
      profileSourceError = 'Wait for the current operation or decision before inspecting profile sources.';
      return;
    }
    busy = true;
    profileSourceError = '';
    try {
      await tick();
      const sources = await stateReads.track(ContextService.ListPlotProfileSources(contextId, profilePath));
      if ($projectState?.contextId !== contextId)
        throw new Error('Profile inspection belongs to an old context; inspect again.');
      if (!Array.isArray(sources)) throw new Error('Profile source inspection returned an incomplete collection.');
      const next = sources.map(validatePlotProfileSource);
      profileSources = next;
      profileSourceContext = contextId;
      if (next.length === 0)
        profileSourceError = 'No saved plot profile tables were found; selection remains unchanged.';
    } catch (cause) {
      profileSourceError = `Profile sources were not replaced: ${formatError(cause)}`;
    } finally {
      busy = false;
    }
  }

  export async function reviewProfileSU(proposal: ProjectPlotProfileFilterRequest, origin: string) {
    if (
      operationHeld ||
      busy ||
      editorBusy ||
      vegetationPublicationBusy ||
      lifeformPublicationBusy ||
      summaryPublicationBusy ||
      transitionWorking ||
      pendingTransition !== null ||
      closeRequest ||
      $projectState?.contextId !== origin
    ) {
      throw new Error('Wait for the current owned operation before reviewing Save as SU.');
    }
    busy = true;
    suError = '';
    try {
      await tick();
      const source = await stateReads.track(ContextService.ReviewProjectPlotProfileSU(origin, proposal));
      if ($projectState?.contextId !== origin) throw new Error('Save as SU review belongs to an old context.');
      suReview = validateProfileSUReview(source, proposal);
      suReviewContext = origin;
      suCommitted = false;
      suSuccess = '';
    } finally {
      busy = false;
    }
  }

  async function reviewProfileSUProject() {
    const state = $projectState;
    if (
      !state?.contextId ||
      !suReview ||
      suReviewContext !== state.contextId ||
      operationHeld ||
      busy ||
      editorBusy ||
      vegetationPublicationBusy ||
      lifeformPublicationBusy ||
      summaryPublicationBusy ||
      transitionWorking ||
      pendingTransition !== null ||
      closeRequest
    ) {
      suProjectError =
        'Wait for the current operation and review the current profile before reviewing a project-file SU.';
      return;
    }
    if (!state.projectPath) {
      suProjectError = 'Current project has no owned physical destination; no SU table can be created.';
      return;
    }
    const proposal = $state.snapshot(suReview.filter);
    busy = true;
    suProjectError = '';
    try {
      await tick();
      const source = await stateReads.track(
        ContextService.ReviewProjectPlotProfileSUInProject(state.contextId, proposal)
      );
      if ($projectState?.contextId !== state.contextId)
        throw new Error('Project-file SU review belongs to an old context.');
      suProjectReview = validateProjectSUReview(source, proposal, state.activeProject, state.projectPath);
      suProjectContext = state.contextId;
      suProjectCommitted = false;
      suProjectSuccess = '';
    } catch (cause) {
      suProjectError = `No SU table created; review failed: ${formatError(cause)}`;
    } finally {
      busy = false;
    }
  }

  async function reviewProfileWriteOwnership() {
    const contextId = $projectState?.contextId;
    if (
      !contextId ||
      operationHeld ||
      busy ||
      editorBusy ||
      vegetationPublicationBusy ||
      lifeformPublicationBusy ||
      summaryPublicationBusy ||
      transitionWorking ||
      pendingTransition !== null ||
      closeRequest
    )
      return;
    busy = true;
    profileWriteError = '';
    try {
      await tick();
      const review = await stateReads.track(ContextService.ReviewProjectPlotProfile(contextId));
      if ($projectState?.contextId !== contextId)
        throw new Error('Profile ownership review belongs to an old context.');
      profileWriteReview = validateProjectPlotProfileReview(review);
      profileWriteContext = contextId;
    } catch (cause) {
      profileWriteError = `Profile editing authorization unchanged: ${formatError(cause)}`;
    } finally {
      busy = false;
    }
  }

  async function reviewBlankProfileFile() {
    const contextId = $projectState?.contextId;
    if (
      !contextId ||
      operationHeld ||
      busy ||
      editorBusy ||
      vegetationPublicationBusy ||
      lifeformPublicationBusy ||
      summaryPublicationBusy ||
      transitionWorking ||
      pendingTransition !== null ||
      closeRequest
    ) {
      profileFileError = 'Wait for the current operation or decision before reviewing a new profile file.';
      return;
    }
    busy = true;
    profileFileError = '';
    try {
      await tick();
      const response = await stateReads.track(ContextService.ReviewPlotProfileFileCreation(contextId));
      if ($projectState?.contextId !== contextId) throw new Error('Blank profile review belongs to an old context.');
      profileFileReview = validateProfileFileReview(response);
      profileFileContext = contextId;
      profileFileCommitted = false;
      profileFileSuccess = '';
    } catch (cause) {
      profileFileError = `No profile file created; review failed: ${formatError(cause)}`;
    } finally {
      busy = false;
    }
  }

  async function reviewBlankProfileTable() {
    const contextId = $projectState?.contextId;
    if (
      !contextId ||
      operationHeld ||
      busy ||
      editorBusy ||
      vegetationPublicationBusy ||
      lifeformPublicationBusy ||
      summaryPublicationBusy ||
      transitionWorking ||
      pendingTransition !== null ||
      closeRequest
    ) {
      profileTableError = 'Wait for the current operation or decision before reviewing an existing-file profile.';
      return;
    }
    busy = true;
    profileTableError = '';
    try {
      await tick();
      const response = await stateReads.track(ContextService.ReviewPlotProfileTableCreation(contextId));
      if ($projectState?.contextId !== contextId)
        throw new Error('Existing-file profile review belongs to an old context.');
      profileTableReview = validateProfileTableReview(response);
      profileTableContext = contextId;
      profileTableCommitted = false;
      profileTableSuccess = '';
    } catch (cause) {
      profileTableError = `No profile table created; review failed: ${formatError(cause)}`;
    } finally {
      busy = false;
    }
  }

  function choosePlotProfile(source: PlotProfileSource, origin: string) {
    return choosePlotProfileOp(mutationHost, source, origin);
  }
</script>

{#if suReview}
  <PlotProfileSUSection
    {suReview}
    {suReviewContext}
    bind:suName
    bind:suPath
    {suError}
    {suSuccess}
    {suCommitted}
    {suProjectReview}
    {suProjectContext}
    bind:suProjectName
    {suProjectError}
    {suProjectSuccess}
    {suProjectCommitted}
    {busy}
    {editorBusy}
    {transitionWorking}
    {pendingTransition}
    onSaveSU={() =>
      void saveProfileSUOp(mutationHost, {
        suReview: $state.snapshot(suReview),
        suCommitted,
        suReviewContext,
        suName,
        suPath,
        setSuCommitted: (v) => {
          suCommitted = v;
        },
        setSuError: (m) => {
          suError = m;
        },
        setSuSuccess: (m) => {
          suSuccess = m;
        },
      })}
    onDismissSU={() => {
      suReview = null;
      suError = '';
      suSuccess = '';
    }}
    onReviewSUProject={() => void reviewProfileSUProject()}
    onSaveSUProject={() =>
      void saveProfileSUProjectOp(mutationHost, {
        suProjectReview: $state.snapshot(suProjectReview),
        suProjectCommitted,
        suProjectContext,
        suProjectName,
        setSuProjectCommitted: (v) => {
          suProjectCommitted = v;
        },
        setSuProjectError: (m) => {
          suProjectError = m;
        },
        setSuProjectSuccess: (m) => {
          suProjectSuccess = m;
        },
      })}
    onDismissSUProject={() => {
      suProjectReview = null;
      suProjectError = '';
      suProjectSuccess = '';
    }}
  />
{/if}

<PlotProfileSelectionSection
  bind:profilePath
  {profileSources}
  {profileSourceContext}
  {profileSourceError}
  {profileWriteReview}
  {profileWriteContext}
  {profileWriteError}
  {profileFileReview}
  {profileFileContext}
  bind:profileFileName
  bind:profileFilePath
  {profileFileError}
  {profileFileSuccess}
  {profileFileCommitted}
  {profileTableReview}
  {profileTableContext}
  bind:profileTableName
  {profileTableError}
  {profileTableSuccess}
  {profileTableCommitted}
  {busy}
  {editorBusy}
  {transitionWorking}
  {pendingTransition}
  onInspectSources={() => void inspectProfileSources()}
  onChooseProfile={(source, origin) => void choosePlotProfile(source, origin)}
  onReviewWriteOwnership={() => void reviewProfileWriteOwnership()}
  onPublishWriteOwnership={() =>
    void publishProfileWriteOwnershipOp(mutationHost, {
      profileWriteReview: $state.snapshot(profileWriteReview),
      profileWriteContext,
      clearWriteReview: () => {
        profileWriteReview = null;
        profileWriteContext = '';
      },
      setProfileWriteError: (m) => {
        profileWriteError = m;
      },
    })}
  onDismissWriteOwnership={() => {
    profileWriteReview = null;
    profileWriteError = '';
  }}
  onReviewBlankFile={() => void reviewBlankProfileFile()}
  onCreateBlankFile={() =>
    void createBlankProfileFileOp(mutationHost, {
      profileFileReview: $state.snapshot(profileFileReview),
      profileFileCommitted,
      profileFileContext,
      profileFileName,
      profileFilePath,
      setProfileFileCommitted: (v) => {
        profileFileCommitted = v;
      },
      setProfileFileError: (m) => {
        profileFileError = m;
      },
      setProfileFileSuccess: (m) => {
        profileFileSuccess = m;
      },
      setProfilePath: (p) => {
        profilePath = p;
      },
    })}
  onDismissBlankFile={() => {
    profileFileReview = null;
    profileFileError = '';
    profileFileSuccess = '';
  }}
  onReviewBlankTable={() => void reviewBlankProfileTable()}
  onCreateBlankTable={() =>
    void createBlankProfileTableOp(mutationHost, {
      profileTableReview: $state.snapshot(profileTableReview),
      profileTableCommitted,
      profileTableContext,
      profileTableName,
      setProfileTableCommitted: (v) => {
        profileTableCommitted = v;
      },
      setProfileTableError: (m) => {
        profileTableError = m;
      },
      setProfileTableSuccess: (m) => {
        profileTableSuccess = m;
      },
      setProfilePath: (p) => {
        profilePath = p;
      },
    })}
  onDismissBlankTable={() => {
    profileTableReview = null;
    profileTableError = '';
    profileTableSuccess = '';
  }}
/>

{#if profileNavigation}
  <section class="m-2 p-2 border rounded flex flex-wrap items-center gap-3" aria-label="Active profile navigation">
    <span
      >{profileNavigation.plots.length} of {profileNavigation.result.totalPlots} stored plots in reviewed profile navigation.</span
    >
    {#if view === 'fs882'}
      <span>Record {profileIndex + 1} of {profileNavigation.plots.length}</span>
      <button
        type="button"
        class="px-3 py-1 border rounded disabled:opacity-50"
        disabled={busy || editorBusy || transitionWorking || pendingTransition !== null || profileIndex <= 0}
        onclick={() => void navigateProfilePlot(-1)}>Previous profile plot</button
      >
      <button
        type="button"
        class="px-3 py-1 border rounded disabled:opacity-50"
        disabled={busy ||
          editorBusy ||
          transitionWorking ||
          pendingTransition !== null ||
          profileIndex < 0 ||
          profileIndex >= profileNavigation.plots.length - 1}
        onclick={() => void navigateProfilePlot(1)}>Next profile plot</button
      >
    {/if}
    <button
      type="button"
      class="px-3 py-1 border rounded disabled:opacity-50"
      disabled={busy || editorBusy || transitionWorking || pendingTransition !== null}
      onclick={() => void clearProfileNavigation()}>Clear profile navigation</button
    >
  </section>
{/if}
