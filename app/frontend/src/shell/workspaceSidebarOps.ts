import type {
  AccessDatabaseInspection,
  AccessProjectImportResult,
  ContextService,
  ImportExportService,
} from '../../bindings/github.com/boostao/vpro/app';
import type { AccessProjectCandidate } from '../../bindings/github.com/boostao/vpro/app/internal/interchange/models';
import type { ProjectInfo } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
import { formatError, type CancellableRead, type ReadRequests } from '../shared/readRequests';
import { notifications } from './notificationService.svelte';

export async function formatSidebarErrorOp(cause: unknown): Promise<string> {
  try {
    const mod = await import('../interchange/interchangeHub');
    if (typeof mod?.formatInterchangeError === 'function') return mod.formatInterchangeError(cause);
  } catch {
    // Fallback in isolated VM tests where dynamic import is unavailable.
  }
  const msg = formatError(cause);
  if (/picture selection|file dialogs not available/i.test(msg)) {
    return 'File selection requires an active desktop window; enter a file path directly when running in a browser.';
  }
  if (/Access source read error|cannot read Access catalog/i.test(msg)) {
    return 'The selected Access file could not be read. It may be incomplete, damaged, or in an unsupported format.';
  }
  if (/\b(?:lstat|stat|open)\b[^:]*:\s*no such file/i.test(msg)) {
    return 'The selected file or folder was not found. Check the path and try again.';
  }
  return msg.replace(/:\s*sql:\s*no rows in result set/gi, '').trim() || 'An unexpected error occurred.';
}

export function isCancelledAccessErrorOp(cause: unknown): boolean {
  if (!cause) return false;
  if (cause instanceof Error && cause.name === 'CancelError') return true;
  const text = String(cause).toLowerCase();
  return text.includes('context canceled') || text.includes('operation cancelled');
}

export function computeAccessProgressPercent(
  accessWorking: boolean,
  accessProgressPhase: string,
  accessProgressRows: number,
  accessProgressExpectedRows: number
): number | null {
  if (!accessWorking) return null;
  if (accessProgressPhase === 'finalizing') return 98;
  if (accessProgressExpectedRows > 0 && accessProgressRows > 0) {
    return Math.min(96, Math.max(1, Math.round((accessProgressRows / accessProgressExpectedRows) * 95)));
  }
  return null;
}

function isCancellableRpc<T>(value: PromiseLike<T>): value is CancellableRead<T> {
  return value !== null && typeof value === 'object' && typeof (value as { cancel?: unknown }).cancel === 'function';
}

function trackSidebarAccessRpc<T>(
  rawRpc: PromiseLike<T>,
  accessRequests: ReadRequests | undefined,
  setActiveRpc: (rpc: { cancel: () => unknown } | null) => void
): PromiseLike<T> {
  if (isCancellableRpc(rawRpc)) {
    if (accessRequests) {
      setActiveRpc(null);
      return accessRequests.track(rawRpc);
    }
    setActiveRpc(rawRpc);
    return rawRpc;
  }
  setActiveRpc(null);
  return rawRpc;
}

export async function browseExternalProjectFileOp(params: {
  contextId: string | undefined;
  contextService: Pick<typeof ContextService, 'ChooseExternalSQLiteFile'>;
  onDiscovered: (selectedPath: string, discovered: ProjectInfo[], firstProjectName: string | null) => void;
  notify?: typeof notifications;
}): Promise<void> {
  const { contextId, contextService, onDiscovered, notify = notifications } = params;
  if (!contextId) return;
  try {
    const inspection = await contextService.ChooseExternalSQLiteFile(contextId);
    if (!inspection.selectedPath) return;
    const projects = inspection.projects ?? [];
    const first = projects.find((p) => p.compatible) ?? projects[0] ?? null;
    onDiscovered(inspection.selectedPath, projects, first?.name ?? null);
    if (first) {
      notify.push({
        severity: 'info',
        category: 'general',
        source: 'Attach Project',
        title: `Found ${projects.length} project(s)`,
        message: first.file,
        toast: true,
      });
    } else {
      notify.push({
        severity: 'warning',
        category: 'general',
        source: 'Attach Project',
        title: 'No project table found',
        message: 'Selected file contains no VPro project tables.',
        toast: true,
      });
    }
  } catch (cause) {
    notify.push({
      severity: 'error',
      category: 'general',
      source: 'Attach Project',
      title: 'Could not inspect project file',
      message: await formatSidebarErrorOp(cause),
      toast: true,
    });
  }
}

export async function runInspectAccessSourceOp(params: {
  contextId: string;
  pathToInspect: string;
  reqGen: number;
  isCurrentGen: () => boolean;
  attachProgress: () => Promise<void>;
  importExportService: Pick<typeof ImportExportService, 'InspectAccessDatabase'>;
  accessRequests: ReadRequests | undefined;
  setActiveRpc: (rpc: { cancel: () => unknown } | null) => void;
  onResolved: (inspection: AccessDatabaseInspection, first: AccessProjectCandidate | null) => void;
  onFailed: (msg: string) => void;
  onSettledCurrent: () => void;
  notify?: typeof notifications;
}): Promise<void> {
  const {
    contextId,
    pathToInspect,
    isCurrentGen,
    attachProgress,
    importExportService,
    accessRequests,
    setActiveRpc,
    onResolved,
    onFailed,
    onSettledCurrent,
    notify = notifications,
  } = params;
  try {
    await attachProgress();
    if (!isCurrentGen()) return;
    const rawRpc = importExportService.InspectAccessDatabase(contextId, pathToInspect);
    const inspection = await trackSidebarAccessRpc(rawRpc, accessRequests, setActiveRpc);
    if (!isCurrentGen()) return;
    const first = (inspection.projects ?? []).find((p) => p.compatible) ?? (inspection.projects ?? [])[0] ?? null;
    onResolved(inspection, first);
  } catch (cause) {
    if (!isCurrentGen() || isCancelledAccessErrorOp(cause)) return;
    const msg = await formatSidebarErrorOp(cause);
    if (!isCurrentGen()) return;
    onFailed(msg);
    notify.push({
      severity: 'error',
      category: 'background',
      source: 'Access Import',
      title: 'Access inspection failed',
      message: msg,
    });
  } finally {
    if (isCurrentGen()) onSettledCurrent();
  }
}

export async function runImportAccessProjectOp(params: {
  contextId: string;
  payload: {
    sourcePath: string;
    sourceProject: string;
    targetProject: string;
    destinationPath: string;
    activateOnSuccess: boolean;
  };
  isCurrentGen: () => boolean;
  attachProgress: () => Promise<void>;
  importExportService: Pick<typeof ImportExportService, 'ImportAccessProject'>;
  accessRequests: ReadRequests | undefined;
  setActiveRpc: (rpc: { cancel: () => unknown } | null) => void;
  onSucceeded: (result: AccessProjectImportResult) => Promise<void>;
  onFailed: (msg: string) => void;
  onSettledCurrent: () => void;
  notify?: typeof notifications;
}): Promise<void> {
  const {
    contextId,
    payload,
    isCurrentGen,
    attachProgress,
    importExportService,
    accessRequests,
    setActiveRpc,
    onSucceeded,
    onFailed,
    onSettledCurrent,
    notify = notifications,
  } = params;
  try {
    await attachProgress();
    if (!isCurrentGen()) return;
    const rawRpc = importExportService.ImportAccessProject(contextId, payload);
    const result = await trackSidebarAccessRpc(rawRpc, accessRequests, setActiveRpc);
    if (!isCurrentGen()) return;
    notify.push({
      severity: 'success',
      category: 'background',
      source: 'Access Import',
      title: `Imported ${result.targetProject} (${result.plotCount} plots)`,
      message: `Saved to ${result.destinationPath}`,
    });
    await onSucceeded(result);
  } catch (cause) {
    if (!isCurrentGen() || isCancelledAccessErrorOp(cause)) return;
    const msg = await formatSidebarErrorOp(cause);
    if (!isCurrentGen()) return;
    onFailed(msg);
    notify.push({
      severity: 'error',
      category: 'background',
      source: 'Access Import',
      title: 'Access project import failed',
      message: msg,
    });
  } finally {
    if (isCurrentGen()) onSettledCurrent();
  }
}
