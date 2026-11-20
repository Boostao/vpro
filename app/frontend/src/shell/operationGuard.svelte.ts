import type { ProjectState } from '../../bindings/github.com/boostao/vpro/app';
import { subscribeExternalSUEnvironmentActivity } from '../classification/externalSUEnvironment';
import { subscribeTwoPageSoilActivity } from '../entry/twoPageSoilActivity';
import { subscribeTwoPageVegetationActivity } from '../entry/twoPageVegetationActivity';
import { tableCSVArchivePublicationSession } from '../interchange/tableCSVArchiveExport';
import { subscribePictureCreationActivity } from '../pictures/pictureCreationActivity';
import { subscribePictureLifecycleActivity } from '../pictures/pictureLifecycleActivity';
import { lifeformWorkbookPublicationSession } from '../reports/lifeformWorkbook';
import { projectReportWorkspace } from '../reports/longVegetationProjectWorkspaces';
import { extendedSummaryWorkbookPublicationSession } from '../reports/siteUnitSummaryExtendedWorkbook';
import { siteUnitSummaryWorkbookPublicationSession } from '../reports/siteUnitSummaryWorkbook';
import { matrixPublicationSession } from '../reports/subzoneMatrixReport';
import {
  summaryEnvironmentalDesktop,
  summaryEnvironmentalEnabled,
} from '../reports/summaryVegetationEnvironmentalDesktop';
import { summaryVegetationFieldListDesktop } from '../reports/summaryVegetationFieldListDesktop';
import { summaryVegetationPreferenceSession } from '../reports/summaryVegetationPreferences';
import { summaryVegetationPresentationPreferenceSession } from '../reports/summaryVegetationPresentationPreferences';
import { summaryVegetationQualityPreferenceSession } from '../reports/summaryVegetationQualityPreferences';
import { summaryVegetationWorkbookSession } from '../reports/summaryVegetationWorkbook';
import { vegetationWorkbookPublicationSession } from '../reports/vegetationWorkbook';

export const TRANSITION_HOLD_NOTICE = 'Wait for the current operation or decision before changing context.';
export const CLOSE_HOLD_NOTICE = 'Wait for the current operation to finish before closing VPRO.';
export const PAGING_HOLD_NOTICE = 'Wait for the current operation to finish before refreshing or paging plots.';

export interface OperationEntryStatus {
  busy?: boolean;
  blocked?: boolean;
  dirty?: boolean;
}

export interface OperationRegistrationOptions {
  /** True for the active editor or companion panel (ignored for in-place owned editor actions). */
  ownedEditor?: boolean;
  /** True for companion panels (tracked separately from editorBusy). */
  companionPanel?: boolean;
  /** True for the shell's own read/switch busy flag. */
  shellBusy?: boolean;
  /** True for the pending-transition confirmation dialog state. */
  transitionDialog?: boolean;
  /** True for the window-close confirmation dialog state. */
  closeDialog?: boolean;
  /** True for background publication sessions (kept out of editorBusy while still blocking all guards). */
  publicationOnly?: boolean;
}

export interface OperationBusyCheckOptions {
  ignoreOwnedEditor?: boolean;
  ignoreTransitionDialog?: boolean;
  ignoreCloseDialog?: boolean;
  ignoreShellBusy?: boolean;
}

interface RegisteredOperation {
  read: () => OperationEntryStatus;
  options: OperationRegistrationOptions;
}

export interface ShellOperationGuard {
  register(name: string, read: () => OperationEntryStatus, options?: OperationRegistrationOptions): () => void;
  notify(): void;
  isBusy(options?: OperationBusyCheckOptions): boolean;
  hasDirtyWorkbench(options?: { ignoreOwnedEditor?: boolean }): boolean;
  readonly editorBusy: boolean;
}

export function createOperationGuard(): ShellOperationGuard {
  const entries = new Map<string, RegisteredOperation>();
  let seq = 0;
  let pulse = $state(0);

  function notify(): void {
    pulse = ++seq;
  }

  function register(
    name: string,
    read: () => OperationEntryStatus,
    options: OperationRegistrationOptions = {}
  ): () => void {
    entries.set(name, { read, options });
    pulse = ++seq;
    return () => {
      if (entries.get(name)?.read === read) {
        entries.delete(name);
        pulse = ++seq;
      }
    };
  }

  function isBusy(options: OperationBusyCheckOptions = {}): boolean {
    void pulse;
    for (const { read, options: reg } of entries.values()) {
      if (options.ignoreOwnedEditor && reg.ownedEditor) continue;
      if (options.ignoreTransitionDialog && reg.transitionDialog) continue;
      if (options.ignoreCloseDialog && reg.closeDialog) continue;
      if (options.ignoreShellBusy && reg.shellBusy) continue;
      const status = read();
      if (status.busy || status.blocked) return true;
    }
    return false;
  }

  function hasDirtyWorkbench(options: { ignoreOwnedEditor?: boolean } = {}): boolean {
    void pulse;
    for (const { read, options: reg } of entries.values()) {
      if (options.ignoreOwnedEditor && reg.ownedEditor) continue;
      if (read().dirty) return true;
    }
    return false;
  }

  return {
    register,
    notify,
    isBusy,
    hasDirtyWorkbench,
    get editorBusy(): boolean {
      void pulse;
      for (const { read, options: reg } of entries.values()) {
        if (reg.shellBusy || reg.companionPanel || reg.transitionDialog || reg.closeDialog || reg.publicationOnly) {
          continue;
        }
        const status = read();
        if (status.busy || status.blocked) return true;
      }
      return false;
    },
  };
}

export type BlockedHomeRedirectTarget =
  | {
      view:
        | 'subzone-matrix'
        | 'summary-vegetation'
        | 'long-vegetation'
        | 'lifeform-summary'
        | 'table-csv'
        | 'summary-environment';
    }
  | { view: 'picture-manager'; plotNumber: string };

export function bindShellActivitySubscriptions(
  guard: ShellOperationGuard,
  getState: () => ProjectState | null,
  onBlockedFromHome: (target: BlockedHomeRedirectTarget) => void
): void {
  const flags: Record<string, boolean> = {};
  const setFlag = (key: string, next: boolean, options: OperationRegistrationOptions = {}) => {
    if (!flags[key] && !next && key in flags) return;
    flags[key] = next;
    guard.register(key, () => ({ busy: flags[key] }), options);
  };

  $effect(() => {
    const state = getState();
    if (!state?.contextId || state.activeHierarchy === 'None' || !state.hierarchyPath) {
      setFlag('matrix-publication', false);
      return;
    }
    const session = matrixPublicationSession({
      contextId: state.contextId,
      hierarchy: state.activeHierarchy,
      hierarchyPath: state.hierarchyPath,
    });
    return session.subscribe(() => {
      const pub = session.view();
      setFlag('matrix-publication', pub.busy || pub.blocked);
      if (pub.blocked) onBlockedFromHome({ view: 'subzone-matrix' });
    });
  });

  $effect(() => {
    if (!summaryEnvironmentalEnabled) return;
    return summaryEnvironmentalDesktop.subscribe(() => {
      const active = summaryEnvironmentalDesktop.activity().busy;
      setFlag('summary-environmental', active);
      if (active) onBlockedFromHome({ view: 'summary-vegetation' });
    });
  });

  $effect(() => {
    if (!summaryVegetationFieldListDesktop.enabled) return;
    return summaryVegetationFieldListDesktop.subscribe(() => {
      const activity = summaryVegetationFieldListDesktop.activity();
      const active = activity.busy || activity.blocked;
      setFlag('summary-field-list', active);
      if (active) onBlockedFromHome({ view: 'summary-vegetation' });
    });
  });

  $effect(() => {
    const state = getState();
    if (
      (!summaryVegetationPreferenceSession &&
        !summaryVegetationQualityPreferenceSession &&
        !summaryVegetationPresentationPreferenceSession) ||
      !state?.contextId ||
      !state.projectPath ||
      !state.suPath
    ) {
      setFlag('summary-preferences', false);
      return;
    }
    const owner = {
      contextId: state.contextId,
      project: state.activeProject,
      projectPath: state.projectPath,
      su: state.activeSU,
      suPath: state.suPath,
    };
    const preferences = summaryVegetationPreferenceSession?.(owner);
    const quality = summaryVegetationQualityPreferenceSession?.(owner);
    const presentation = summaryVegetationPresentationPreferenceSession?.(owner);
    const changed = () => {
      const views = [preferences?.view(), quality?.view(), presentation?.view()];
      const active = views.some((current) => !!current && (current.busy || current.blocked || !!current.draftError));
      setFlag('summary-preferences', active);
      if (active) onBlockedFromHome({ view: 'summary-vegetation' });
    };
    const r1 = preferences?.subscribe(changed);
    const r2 = quality?.subscribe(changed);
    const r3 = presentation?.subscribe(changed);
    return () => {
      r1?.();
      r2?.();
      r3?.();
    };
  });

  $effect(() => {
    const state = getState();
    if (
      !projectReportWorkspace ||
      !state?.contextId ||
      !state.projectPath ||
      (state.activeSU !== 'None' && !state.suPath)
    ) {
      setFlag('project-report-workspace', false);
      return;
    }
    const workspace = projectReportWorkspace({
      contextId: state.contextId,
      project: state.activeProject,
      projectPath: state.projectPath,
      su: state.activeSU,
      suPath: state.suPath ?? '',
    });
    return workspace.subscribe(() => {
      const active = workspace.view().closeBlocked;
      setFlag('project-report-workspace', active);
      if (active) onBlockedFromHome({ view: 'long-vegetation' });
    });
  });

  $effect(() => subscribeTwoPageSoilActivity((a) => setFlag('two-page-soil', a.busy || a.blocked)));
  $effect(() => subscribeTwoPageVegetationActivity((a) => setFlag('two-page-vegetation', a.busy || a.blocked)));
  $effect(() => subscribeExternalSUEnvironmentActivity((a) => setFlag('external-su-environment', a.busy || a.blocked)));

  $effect(() => {
    const state = getState();
    return subscribePictureLifecycleActivity((activity) => {
      setFlag('picture-lifecycle', activity.busy || activity.blocked);
      if (
        activity.owner &&
        activity.owner.contextId === state?.contextId &&
        activity.owner.project === state.activeProject
      ) {
        onBlockedFromHome({ view: 'picture-manager', plotNumber: activity.owner.plotNumber });
      }
    });
  });

  $effect(() => {
    const state = getState();
    return subscribePictureCreationActivity((activity) => {
      setFlag('picture-creation', activity.busy || activity.blocked);
      if (
        activity.owner &&
        activity.owner.contextId === state?.contextId &&
        activity.owner.project === state.activeProject
      ) {
        onBlockedFromHome({ view: 'picture-manager', plotNumber: activity.owner.plotNumber });
      }
    });
  });

  $effect(() => {
    const state = getState();
    if (!state?.contextId || state.activeSU === 'None' || !state.suPath) {
      setFlag('vegetation-publication', false, { publicationOnly: true });
      return;
    }
    const session = vegetationWorkbookPublicationSession(
      {
        contextId: state.contextId,
        project: state.activeProject,
        projectPath: state.projectPath ?? '',
        su: state.activeSU,
        suPath: state.suPath,
      },
      true
    );
    return session.subscribe(() => {
      const pub = session.view();
      setFlag('vegetation-publication', pub.busy || pub.blocked, { publicationOnly: true });
      if (pub.blocked) onBlockedFromHome({ view: 'long-vegetation' });
    });
  });

  $effect(() => {
    const state = getState();
    if (!state?.contextId || state.activeSU === 'None' || !state.suPath) {
      setFlag('lifeform-publication', false, { publicationOnly: true });
      return;
    }
    const session = lifeformWorkbookPublicationSession({
      contextId: state.contextId,
      project: state.activeProject,
      projectPath: state.projectPath ?? '',
      su: state.activeSU,
      suPath: state.suPath,
    });
    return session.subscribe(() => {
      const pub = session.view();
      setFlag('lifeform-publication', pub.busy || pub.blocked, { publicationOnly: true });
      if (pub.blocked) onBlockedFromHome({ view: 'lifeform-summary' });
    });
  });

  $effect(() => {
    const state = getState();
    if (!state?.contextId) {
      setFlag('archive-publication', false, { publicationOnly: true });
      return;
    }
    const session = tableCSVArchivePublicationSession({
      contextId: state.contextId,
      project: state.activeProject,
      projectPath: state.projectPath ?? '',
    });
    return session.subscribe(() => {
      const pub = session.view();
      setFlag('archive-publication', pub.busy || pub.blocked, { publicationOnly: true });
      if (pub.blocked) onBlockedFromHome({ view: 'table-csv' });
    });
  });

  $effect(() => {
    const state = getState();
    if (!state?.contextId || state.activeSU === 'None' || !state.suPath) {
      setFlag('summary-environment-publication', false, { publicationOnly: true });
      return;
    }
    const owner = {
      contextId: state.contextId,
      project: state.activeProject,
      projectPath: state.projectPath ?? '',
      su: state.activeSU,
      suPath: state.suPath,
    };
    const sessions = [
      siteUnitSummaryWorkbookPublicationSession(owner),
      extendedSummaryWorkbookPublicationSession(owner),
    ];
    const update = () => {
      const states = sessions.map((s) => s.view());
      const busy = states.some((s) => s.busy);
      const blocked = states.some((s) => s.blocked);
      setFlag('summary-environment-publication', busy || blocked, { publicationOnly: true });
      if (blocked) onBlockedFromHome({ view: 'summary-environment' });
    };
    const stops = sessions.map((s) => s.subscribe(update));
    return () => {
      for (const stop of stops) stop();
    };
  });

  $effect(() => {
    const state = getState();
    if (!state?.contextId || state.activeSU === 'None' || !state.suPath) {
      setFlag('summary-vegetation-publication', false, { publicationOnly: true });
      return;
    }
    const session = summaryVegetationWorkbookSession({
      contextId: state.contextId,
      project: state.activeProject,
      projectPath: state.projectPath ?? '',
      su: state.activeSU,
      suPath: state.suPath,
    });
    return session.subscribe(() => {
      const held = session.held();
      setFlag('summary-vegetation-publication', held, { publicationOnly: true });
      if (held) onBlockedFromHome({ view: 'summary-vegetation' });
    });
  });
}
