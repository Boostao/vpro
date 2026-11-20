import { tick } from 'svelte';
import {
  ContextService,
  type PlotProfileSource,
  type PlotProfileSourceInfo,
} from '../../bindings/github.com/boostao/vpro/app';
import { validateProfileFileCreated, type ReviewedProfileFile } from '../classification/profileFile';
import { validateProfileSUCreated, type ReviewedProfileSU } from '../classification/profileSU';
import { validateProjectSUCreated, type ReviewedProjectSU } from '../classification/profileSUProject';
import { validateProfileTableCreated, type ReviewedProfileTable } from '../classification/profileTable';
import type { ValidatedProjectPlotProfileReview } from '../classification/projectPlotProfileReview';
import { formatError, type ReadRequests } from '../shared/readRequests';
import { projectState } from '../shared/state';

export interface PlotProfileSelectionController {
  readonly profilePath: string;
  setProfilePath: (value: string) => void;
  readonly profileSources: PlotProfileSourceInfo[];
  readonly profileSourceContext: string;
  readonly profileSourceError: string;
  readonly profileWriteReview: ValidatedProjectPlotProfileReview | null;
  readonly profileWriteContext: string;
  readonly profileWriteError: string;
  readonly profileFileReview: ReviewedProfileFile | null;
  readonly profileFileContext: string;
  readonly profileFileName: string;
  setProfileFileName: (value: string) => void;
  readonly profileFilePath: string;
  setProfileFilePath: (value: string) => void;
  readonly profileFileError: string;
  readonly profileFileSuccess: string;
  readonly profileFileCommitted: boolean;
  readonly profileTableReview: ReviewedProfileTable | null;
  readonly profileTableContext: string;
  readonly profileTableName: string;
  setProfileTableName: (value: string) => void;
  readonly profileTableError: string;
  readonly profileTableSuccess: string;
  readonly profileTableCommitted: boolean;
  readonly busy: boolean;
  readonly editorBusy: boolean;
  readonly transitionWorking: boolean;
  readonly pendingTransition: unknown;
  inspectSources: () => void;
  chooseProfile: (source: PlotProfileSource, origin: string) => void;
  reviewWriteOwnership: () => void;
  publishWriteOwnership: () => void;
  dismissWriteOwnership: () => void;
  reviewBlankFile: () => void;
  createBlankFile: () => void;
  dismissBlankFile: () => void;
  reviewBlankTable: () => void;
  createBlankTable: () => void;
  dismissBlankTable: () => void;
}

export interface PlotProfileMutationHost {
  setBusy: (b: boolean) => void;
  getError: () => string;
  setError: (msg: string) => void;
  resetToPlotsView: () => void;
  afterBlankProfileCreated?: () => void;
  resetContextAfterProfileSwitch: (state: Awaited<ReturnType<typeof ContextService.GetState>>) => void;
  loadPlotsZero: () => Promise<void>;
  cancelAllReads: () => void;
  stateReads: ReadRequests;
  getCurrentContextId: () => string | undefined;
  requestTransition: (run: (contextId: string) => Promise<void>) => Promise<void>;
}

export async function saveProfileSUOp(
  host: PlotProfileMutationHost,
  params: {
    suReview: ReviewedProfileSU | null;
    suCommitted: boolean;
    suReviewContext: string;
    suName: string;
    suPath: string;
    setSuCommitted: (v: boolean) => void;
    setSuError: (msg: string) => void;
    setSuSuccess: (msg: string) => void;
  }
) {
  const { suReview, suCommitted, suReviewContext, suName, suPath, setSuCommitted, setSuError, setSuSuccess } = params;
  if (!suReview || suCommitted || suReviewContext !== host.getCurrentContextId()) {
    setSuError('Review the current stored profile before creating one new SU file.');
    return;
  }
  const proposal = { review: suReview, name: suName, path: suPath, confirmed: true };
  await host.requestTransition(async (contextId) => {
    if (contextId !== suReviewContext) throw new Error('Save as SU proposal belongs to an old context.');
    host.setBusy(true);
    setSuError('');
    let committed = false;
    try {
      await tick();
      const response = await ContextService.SaveProjectPlotProfileSU(contextId, proposal);
      committed = true;
      setSuCommitted(true);
      const created = validateProfileSUCreated(response, proposal.name, proposal.review.plots.length);
      setSuSuccess(
        `Created ${created.name} with ${created.plotCount} stored plots in ${created.path}. Current project/SU selection is unchanged.`
      );
      host.resetToPlotsView();
      await host.loadPlotsZero();
      if (host.getError())
        host.setError(`SU file published, but navigation refresh failed; do not replay creation: ${host.getError()}`);
    } catch (cause) {
      const msg = formatError(cause);
      if (committed || String(cause).includes('Profile SU file published, but')) {
        setSuCommitted(true);
        setSuError(`SU file published; do not replay creation: ${msg}`);
      } else {
        setSuError(`No SU file published; proposal retained for correction or retry: ${msg}`);
      }
      throw cause;
    } finally {
      host.setBusy(false);
    }
  });
}

export async function saveProfileSUProjectOp(
  host: PlotProfileMutationHost,
  params: {
    suProjectReview: ReviewedProjectSU | null;
    suProjectCommitted: boolean;
    suProjectContext: string;
    suProjectName: string;
    setSuProjectCommitted: (v: boolean) => void;
    setSuProjectError: (msg: string) => void;
    setSuProjectSuccess: (msg: string) => void;
  }
) {
  const {
    suProjectReview,
    suProjectCommitted,
    suProjectContext,
    suProjectName,
    setSuProjectCommitted,
    setSuProjectError,
    setSuProjectSuccess,
  } = params;
  if (!suProjectReview || suProjectCommitted || suProjectContext !== host.getCurrentContextId()) {
    setSuProjectError('Review the current project destination before creating one SU table.');
    return;
  }
  const proposal = { review: suProjectReview, name: suProjectName, confirmed: true };
  await host.requestTransition(async (contextId) => {
    if (contextId !== suProjectContext) throw new Error('Project-file SU proposal belongs to an old context.');
    host.setBusy(true);
    setSuProjectError('');
    let committed = false;
    try {
      await tick();
      const response = await ContextService.SaveProjectPlotProfileSUInProject(contextId, proposal);
      committed = true;
      setSuProjectCommitted(true);
      const created = validateProjectSUCreated(
        response,
        proposal.name,
        proposal.review.su.plots.length,
        proposal.review.path
      );
      setSuProjectSuccess(
        `Created ${created.name} with ${created.plotCount} stored plots in ${created.path}. Existing data/descriptions and project/SU selection are unchanged; select it separately.`
      );
      host.resetToPlotsView();
      const state = await host.stateReads.track(ContextService.GetState());
      if (state.contextId !== contextId || host.getCurrentContextId() !== contextId) {
        throw new Error(
          'SU table committed, but context changed before destination discovery refresh; do not replay creation.'
        );
      }
      projectState.set(state);
      await host.loadPlotsZero();
      if (host.getError())
        host.setError(`SU table committed, but navigation refresh failed; do not replay creation: ${host.getError()}`);
    } catch (cause) {
      const msg = formatError(cause);
      if (committed || String(cause).includes('Profile SU table committed, but')) {
        setSuProjectCommitted(true);
        setSuProjectError(`SU table committed; do not replay creation: ${msg}`);
      } else {
        setSuProjectError(`No SU table created; proposal retained for correction or retry: ${msg}`);
      }
      throw cause;
    } finally {
      host.setBusy(false);
    }
  });
}

export async function choosePlotProfileOp(host: PlotProfileMutationHost, source: PlotProfileSource, origin: string) {
  const proposal = { name: source.name, path: source.path };
  await host.requestTransition(async (contextId) => {
    if (contextId !== origin) throw new Error('Profile source belongs to an old context; inspect again.');
    host.setBusy(true);
    try {
      await tick();
      const state = await ContextService.SelectPlotProfile(contextId, proposal);
      host.cancelAllReads();
      host.resetContextAfterProfileSwitch(state);
      await host.loadPlotsZero();
      if (host.getError())
        host.setError(`Profile selection committed, but refresh failed; do not replay selection: ${host.getError()}`);
    } finally {
      host.setBusy(false);
    }
  });
}

export async function publishProfileWriteOwnershipOp(
  host: PlotProfileMutationHost,
  params: {
    profileWriteReview: ValidatedProjectPlotProfileReview | null;
    profileWriteContext: string;
    clearWriteReview: () => void;
    setProfileWriteError: (msg: string) => void;
  }
) {
  const { profileWriteReview, profileWriteContext, clearWriteReview, setProfileWriteError } = params;
  if (!profileWriteReview || profileWriteContext !== host.getCurrentContextId()) {
    setProfileWriteError('Review the current selected profile before changing write authorization.');
    return;
  }
  const proposal = { review: profileWriteReview, enabled: !profileWriteReview.source.writable, confirmed: true };
  await host.requestTransition(async (contextId) => {
    if (contextId !== profileWriteContext) throw new Error('Profile ownership review belongs to an old context.');
    host.setBusy(true);
    setProfileWriteError('');
    let published = false;
    try {
      await tick();
      const state = await ContextService.SetPlotProfileEditing(contextId, proposal);
      published = true;
      host.cancelAllReads();
      clearWriteReview();
      host.resetContextAfterProfileSwitch(state);
      await host.loadPlotsZero();
      if (host.getError())
        host.setError(
          `Profile authorization committed, but refresh failed; do not replay authorization: ${host.getError()}`
        );
    } catch (cause) {
      const msg = formatError(cause);
      setProfileWriteError(
        published
          ? `Profile authorization committed; do not replay: ${msg}`
          : `Profile authorization unchanged; review retained for retry: ${msg}`
      );
      throw cause;
    } finally {
      host.setBusy(false);
    }
  });
}

export async function createBlankProfileFileOp(
  host: PlotProfileMutationHost,
  params: {
    profileFileReview: ReviewedProfileFile | null;
    profileFileCommitted: boolean;
    profileFileContext: string;
    profileFileName: string;
    profileFilePath: string;
    setProfileFileCommitted: (v: boolean) => void;
    setProfileFileError: (msg: string) => void;
    setProfileFileSuccess: (msg: string) => void;
    setProfilePath: (p: string) => void;
  }
) {
  const {
    profileFileReview,
    profileFileCommitted,
    profileFileContext,
    profileFileName,
    profileFilePath,
    setProfileFileCommitted,
    setProfileFileError,
    setProfileFileSuccess,
    setProfilePath,
  } = params;
  if (!profileFileReview || profileFileCommitted || profileFileContext !== host.getCurrentContextId()) {
    setProfileFileError('Review the current original empty template before creating one new profile file.');
    return;
  }
  const proposal = { review: profileFileReview, name: profileFileName, path: profileFilePath, confirmed: true };
  await host.requestTransition(async (contextId) => {
    if (contextId !== profileFileContext) throw new Error('Blank profile proposal belongs to an old context.');
    host.setBusy(true);
    setProfileFileError('');
    let committed = false;
    try {
      await tick();
      const response = await ContextService.CreatePlotProfileFile(contextId, proposal);
      committed = true;
      setProfileFileCommitted(true);
      const created = validateProfileFileCreated(response, proposal.name);
      setProfileFileSuccess(
        `Created ${created.table} with zero rules in ${created.source.path}. Inspect, select and authorize it explicitly to begin editing; current context selection is unchanged.`
      );
      setProfilePath(created.source.path);
      if (host.afterBlankProfileCreated) host.afterBlankProfileCreated();
      else host.resetToPlotsView();
      await host.loadPlotsZero();
      if (host.getError())
        host.setError(
          `Profile file published, but navigation refresh failed; do not replay creation: ${host.getError()}`
        );
    } catch (cause) {
      const msg = formatError(cause);
      if (committed || String(cause).includes('Profile file published, but')) {
        setProfileFileCommitted(true);
        setProfileFileError(`Profile file published; do not replay creation: ${msg}`);
      } else {
        setProfileFileError(`No profile file published; proposal retained for correction or retry: ${msg}`);
      }
      throw cause;
    } finally {
      host.setBusy(false);
    }
  });
}

export async function createBlankProfileTableOp(
  host: PlotProfileMutationHost,
  params: {
    profileTableReview: ReviewedProfileTable | null;
    profileTableCommitted: boolean;
    profileTableContext: string;
    profileTableName: string;
    setProfileTableCommitted: (v: boolean) => void;
    setProfileTableError: (msg: string) => void;
    setProfileTableSuccess: (msg: string) => void;
    setProfilePath: (p: string) => void;
  }
) {
  const {
    profileTableReview,
    profileTableCommitted,
    profileTableContext,
    profileTableName,
    setProfileTableCommitted,
    setProfileTableError,
    setProfileTableSuccess,
    setProfilePath,
  } = params;
  if (!profileTableReview || profileTableCommitted || profileTableContext !== host.getCurrentContextId()) {
    setProfileTableError(
      'Review current selected-profile ownership and the original template before creating one table.'
    );
    return;
  }
  const proposal = { review: profileTableReview, name: profileTableName, confirmed: true };
  await host.requestTransition(async (contextId) => {
    if (contextId !== profileTableContext) throw new Error('Existing-file profile proposal belongs to an old context.');
    host.setBusy(true);
    setProfileTableError('');
    let committed = false;
    try {
      await tick();
      const response = await ContextService.CreatePlotProfileTable(contextId, proposal);
      committed = true;
      setProfileTableCommitted(true);
      const created = validateProfileTableCreated(response, proposal.name, proposal.review.profile.source.source.path);
      setProfileTableSuccess(
        `Created ${created.table} with zero rules in ${created.source.path}. Existing data/descriptions and current selection are unchanged. Inspect and select it explicitly; selection clears external session grants.`
      );
      setProfilePath(created.source.path);
      if (host.afterBlankProfileCreated) host.afterBlankProfileCreated();
      else host.resetToPlotsView();
      await host.loadPlotsZero();
      if (host.getError())
        host.setError(
          `Profile table committed, but navigation refresh failed; do not replay creation: ${host.getError()}`
        );
    } catch (cause) {
      const msg = formatError(cause);
      if (committed || String(cause).includes('Profile table committed, but')) {
        setProfileTableCommitted(true);
        setProfileTableError(`Profile table committed; do not replay creation: ${msg}`);
      } else {
        setProfileTableError(`No profile table created; proposal retained for correction or retry: ${msg}`);
      }
      throw cause;
    } finally {
      host.setBusy(false);
    }
  });
}
