import type {
  AttachableFileInspection,
  ContextService,
  ImportExportService,
} from '../../bindings/github.com/boostao/vpro/app';
import type {
  AttachWorkspaceResourceResult,
  CreateWorkspaceResourceRequest,
  CreateWorkspaceResourceResult,
  UnattachWorkspaceResourceResult,
} from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
import type { VPro64ExportOutcome } from '../../bindings/github.com/boostao/vpro/app/internal/interchange/models';
import { formatError } from '../shared/readRequests';
import { notifications } from './notificationService.svelte';

export type WorkspaceResourceKind = 'project' | 'su' | 'hierarchy';

export interface AttachCandidateItem {
  name: string;
  label: string;
  compatible: boolean;
}

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

export function workspaceKindLabel(kind: WorkspaceResourceKind): string {
  if (kind === 'project') return 'Project';
  if (kind === 'su') return 'Site Unit';
  return 'Hierarchy';
}

export function extractAttachCandidates(
  kind: WorkspaceResourceKind,
  inspection: AttachableFileInspection
): AttachCandidateItem[] {
  if (kind === 'project') {
    return (inspection.projects ?? []).map((p) => ({
      name: p.name,
      label: p.compatible ? p.name : `${p.name} (${p.version || 'incompatible'})`,
      compatible: Boolean(p.compatible),
    }));
  }
  if (kind === 'su') {
    return (inspection.sus ?? []).map((s) => ({
      name: s.name,
      label: s.kind === 'master' ? `${s.name} (master)` : s.name,
      compatible: Boolean(s.compatible),
    }));
  }
  return (inspection.hierarchies ?? []).map((h) => ({
    name: h.name,
    label: h.name,
    compatible: Boolean(h.compatible),
  }));
}

export function requiresAccessConversion(inspection: AttachableFileInspection | null | undefined): boolean {
  if (!inspection) return false;
  return Boolean(inspection.requiresConvert || inspection.fileKind === 'access');
}

export async function runAttachWorkspaceResourceOp(params: {
  contextId: string;
  kind: WorkspaceResourceKind;
  path: string;
  name?: string;
  activate?: boolean;
  contextService: Pick<typeof ContextService, 'AttachWorkspaceResource'>;
  notify?: typeof notifications;
}): Promise<AttachWorkspaceResourceResult> {
  const { contextId, kind, path, name = '', activate = true, contextService, notify = notifications } = params;
  const result = await contextService.AttachWorkspaceResource(contextId, {
    kind,
    path,
    name,
    activate,
  });
  const label = workspaceKindLabel(kind);
  const attachedName = name || result.attached?.[0]?.name || label;
  notify.push({
    severity: 'success',
    category: 'general',
    source: 'Work Space',
    title: result.converted ? `Converted and attached ${attachedName}` : `Attached ${label}: ${attachedName}`,
    message: result.converted
      ? 'Converted from Microsoft Access into a VPro database (.db) and added to your Work Space.'
      : `Added to your Work Space.`,
    toast: true,
  });
  return result;
}

export async function runUnattachWorkspaceResourceOp(params: {
  contextId: string;
  kind: WorkspaceResourceKind;
  name: string;
  path?: string;
  contextService: Pick<typeof ContextService, 'UnattachWorkspaceResource'>;
  notify?: typeof notifications;
}): Promise<UnattachWorkspaceResourceResult> {
  const { contextId, kind, name, path = '', contextService, notify = notifications } = params;
  const result = await contextService.UnattachWorkspaceResource(contextId, { kind, name, path });
  notify.push({
    severity: 'info',
    category: 'general',
    source: 'Work Space',
    title: `Removed ${workspaceKindLabel(kind)}: ${name}`,
    message: 'Unattached from your Work Space. The database file on disk was not deleted.',
    toast: true,
  });
  return result;
}

export async function runCreateWorkspaceResourceOp(params: {
  contextId: string;
  request: CreateWorkspaceResourceRequest;
  contextService: Pick<typeof ContextService, 'CreateWorkspaceResource'>;
  notify?: typeof notifications;
}): Promise<CreateWorkspaceResourceResult> {
  const { contextId, request, contextService, notify = notifications } = params;
  const result = await contextService.CreateWorkspaceResource(contextId, request);
  const kind = (request.kind as WorkspaceResourceKind) || 'project';
  notify.push({
    severity: 'success',
    category: 'general',
    source: 'Work Space',
    title: `Created ${workspaceKindLabel(kind)}: ${result.name}`,
    message: result.path ? `Saved in ${result.path}` : 'Added to your Work Space.',
    toast: true,
  });
  return result;
}

export async function runExportVPro64Op(params: {
  contextId: string;
  includeActiveSU: boolean;
  includeHierarchy: boolean;
  importExportService: Pick<typeof ImportExportService, 'ChooseVPro64ExportFile' | 'ExportVPro64Database'>;
  notify?: typeof notifications;
}): Promise<VPro64ExportOutcome | null> {
  const { contextId, includeActiveSU, includeHierarchy, importExportService, notify = notifications } = params;
  const destinationPath = await importExportService.ChooseVPro64ExportFile();
  if (!destinationPath) return null;
  const outcome = await importExportService.ExportVPro64Database(contextId, {
    destinationPath,
    includeActiveSU,
    includeHierarchy,
    includeMensuration: true,
    includeCompanions: true,
  });
  notify.push({
    severity: 'success',
    category: 'background',
    source: 'Export to VPro64',
    title: `Exported ${outcome.targetProject} (${outcome.plotCount} plots)`,
    message: `Saved VPro64 package to ${outcome.destinationPath}`,
    toast: true,
  });
  return outcome;
}
