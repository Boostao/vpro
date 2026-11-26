import {
  ContextService,
  type HTMLReportResult,
  type QuickEnvReportExportResult,
  type QuickVegReportExportResult,
  type SpreadsheetAppPreference,
} from '../../bindings/github.com/boostao/vpro/app';
import { formatError } from '../shared/readRequests';
import { IS_WEB_READONLY } from '../web/runtimeMode';
import { formatWebDownloadFeedback } from '../web/webMeta';

export type CompactScopeMode = 'su' | 'fallback' | 'hierarchy' | 'missing-hierarchy';

export interface CompactScopeInfo {
  mode: CompactScopeMode;
  badge: string;
  detail: string;
  ready: boolean;
}

export interface QuickExportSummary {
  reportKind: string;
  title: string;
  project: string;
  su: string;
  scopeLabel: string;
  fallbackNotice: string;
  unitCount: number;
  plotCount: number;
  rowCount?: number;
  path: string;
  bytes: number;
  preferencesSaved: boolean;
  openedInSpreadsheet: boolean;
  spreadsheetNotice: string;
}

export interface SpreadsheetAppPort {
  getPreference(contextID: string): Promise<SpreadsheetAppPreference>;
  setPreference(contextID: string, pref: SpreadsheetAppPreference): Promise<SpreadsheetAppPreference>;
  openFile(contextID: string, filePath: string): Promise<void>;
}

export const defaultSpreadsheetAppPort: SpreadsheetAppPort = {
  getPreference: (contextID) => ContextService.GetSpreadsheetAppPreference(contextID),
  setPreference: (contextID, pref) => ContextService.SetSpreadsheetAppPreference(contextID, pref),
  openFile: (contextID, filePath) => ContextService.OpenReportInSpreadsheet(contextID, filePath),
};

export interface SpreadsheetPreset {
  id: 'default' | 'excel' | 'calc';
  label: string;
  programPath: string;
  description: string;
}

export const SPREADSHEET_APP_PRESETS: ReadonlyArray<SpreadsheetPreset> = [
  {
    id: 'default',
    label: 'OS Default',
    programPath: '',
    description: 'Open spreadsheets with your system default program.',
  },
  {
    id: 'excel',
    label: 'Microsoft Excel',
    programPath: 'excel',
    description: 'Launch Microsoft Excel when opening exported workbooks.',
  },
  {
    id: 'calc',
    label: 'LibreOffice Calc',
    programPath: 'soffice',
    description: 'Launch LibreOffice Calc when opening exported workbooks.',
  },
];

export function describeCompactScope(input: {
  project?: string;
  su?: string;
  hierarchy?: string;
  requiresHierarchy?: boolean;
}): CompactScopeInfo {
  const project = (input.project ?? '').trim() || 'Active Project';
  const su = (input.su ?? '').trim();
  const hierarchy = (input.hierarchy ?? '').trim();

  if (input.requiresHierarchy) {
    if (hierarchy && hierarchy !== 'None') {
      return {
        mode: 'hierarchy',
        badge: `Hierarchy: ${hierarchy}`,
        detail: 'Uses the selected hierarchy and standard BEC unit labels.',
        ready: true,
      };
    }
    return {
      mode: 'missing-hierarchy',
      badge: 'No Hierarchy Selected',
      detail: 'Select a hierarchy in the sidebar to build or display the Subzone Matrix.',
      ready: false,
    };
  }

  if (su && su !== 'None') {
    return {
      mode: 'su',
      badge: `Active SU: ${su}`,
      detail: `Project ${project} · running on active Site Unit table ${su}.`,
      ready: true,
    };
  }

  return {
    mode: 'fallback',
    badge: 'Auto Scope: All Plots / Zone+SubZone',
    detail: `Project ${project} · no Site Unit table attached, so VPro groups automatically by Zone + SubZone or All Plots.`,
    ready: true,
  };
}

export function formatSpreadsheetAppLabel(pref: SpreadsheetAppPreference | null | undefined): string {
  const path = (pref?.programPath ?? '').trim();
  if (!path) return 'OS Default';
  const lower = path.toLowerCase();
  if (lower === 'excel' || lower.endsWith('excel.exe') || lower.includes('microsoft excel')) {
    return 'Microsoft Excel';
  }
  if (lower === 'soffice' || lower === 'scalc' || lower.includes('libreoffice')) {
    return 'LibreOffice Calc';
  }
  const normalized = path.replaceAll('\\', '/');
  const idx = normalized.lastIndexOf('/');
  return idx >= 0 ? normalized.slice(idx + 1) : normalized;
}

export function normalizeQuickVegExportResult(
  raw: QuickVegReportExportResult | null | undefined
): QuickExportSummary | null {
  if (!raw) return null;
  return {
    reportKind: raw.reportKind ?? '',
    title: raw.title ?? '',
    project: raw.project ?? '',
    su: raw.su ?? '',
    scopeLabel: raw.scopeLabel ?? '',
    fallbackNotice: raw.fallbackNotice ?? '',
    unitCount: Number(raw.unitCount ?? 0),
    plotCount: Number(raw.plotCount ?? 0),
    rowCount: typeof raw.rowCount === 'number' ? raw.rowCount : undefined,
    path: raw.path ?? '',
    bytes: Number(raw.bytes ?? 0),
    preferencesSaved: Boolean(raw.preferencesSaved),
    openedInSpreadsheet: Boolean(raw.openedInSpreadsheet),
    spreadsheetNotice: raw.spreadsheetNotice ?? '',
  };
}

export function normalizeQuickEnvExportResult(
  raw: QuickEnvReportExportResult | null | undefined
): QuickExportSummary | null {
  if (!raw) return null;
  return {
    reportKind: raw.reportKind ?? '',
    title: raw.title ?? '',
    project: raw.project ?? '',
    su: raw.su ?? '',
    scopeLabel: raw.scopeLabel ?? '',
    fallbackNotice: raw.fallbackNotice ?? '',
    unitCount: Number(raw.unitCount ?? 0),
    plotCount: Number(raw.plotCount ?? 0),
    path: raw.path ?? '',
    bytes: Number(raw.bytes ?? 0),
    preferencesSaved: Boolean(raw.preferencesSaved),
    openedInSpreadsheet: Boolean(raw.openedInSpreadsheet),
    spreadsheetNotice: raw.spreadsheetNotice ?? '',
  };
}

export function slugifyReportFilename(title: string, ext: string): string {
  const base = (title || 'vpro_report')
    .trim()
    .replace(/[^A-Za-z0-9._-]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 64);
  const safeBase = base || 'vpro_report';
  const cleanExt = ext.startsWith('.') ? ext : `.${ext}`;
  return safeBase.toLowerCase().endsWith(cleanExt.toLowerCase()) ? safeBase : `${safeBase}${cleanExt}`;
}

export function triggerBrowserHTMLDownload(report: HTMLReportResult): boolean {
  if (
    typeof globalThis.document === 'undefined' ||
    typeof globalThis.Blob === 'undefined' ||
    typeof globalThis.URL === 'undefined' ||
    typeof globalThis.URL.createObjectURL !== 'function'
  ) {
    return false;
  }
  const blob = new globalThis.Blob([report.html ?? ''], { type: 'text/html;charset=utf-8' });
  const url = globalThis.URL.createObjectURL(blob);
  const link = globalThis.document.createElement('a');
  link.href = url;
  link.download = slugifyReportFilename(report.title || report.reportKind || 'vpro_report', '.html');
  globalThis.document.body?.appendChild(link);
  link.click();
  link.remove();
  globalThis.setTimeout(() => globalThis.URL.revokeObjectURL(url), 1000);
  return true;
}

export function formatCompactReportError(cause: unknown, actionLabel: string): string {
  const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
  if (webReadOnly && typeof formatWebDownloadFeedback === 'function') {
    return formatWebDownloadFeedback(cause, actionLabel);
  }
  return formatError(cause);
}

export function formatBytesCompact(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return '0 B';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

const STORAGE_PREFIX = 'vpro:quick-report:';

export function loadQuickReportPrefs<T extends Record<string, unknown>>(reportKey: string, defaults: T): T {
  try {
    if (typeof globalThis.localStorage === 'undefined') return { ...defaults };
    const raw = globalThis.localStorage.getItem(`${STORAGE_PREFIX}${reportKey}`);
    if (!raw) return { ...defaults };
    const parsed = JSON.parse(raw) as unknown;
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return { ...defaults };
    return { ...defaults, ...(parsed as Partial<T>) };
  } catch {
    return { ...defaults };
  }
}

export function saveQuickReportPrefs<T extends Record<string, unknown>>(reportKey: string, values: T): void {
  if (typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY) return;
  try {
    if (typeof globalThis.localStorage === 'undefined') return;
    globalThis.localStorage.setItem(`${STORAGE_PREFIX}${reportKey}`, JSON.stringify(values));
  } catch {
    // Ignore storage quota or restricted context errors.
  }
}
