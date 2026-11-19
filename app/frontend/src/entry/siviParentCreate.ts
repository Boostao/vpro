import { wellFormedUTF16 } from './qualityEditor';
import { ContextService } from '../../bindings/github.com/boostao/vpro/app';

export const SIVI_PLOT_TYPES = ['Ground', 'Visual', 'Note', 'Other', 'FS882'] as const;
export type SIVIPlotType = (typeof SIVI_PLOT_TYPES)[number];

export interface CreateSIVIPlotRequest {
  requestId?: string;
  plotNumber: string;
  plotType: SIVIPlotType;
  projectId?: string;
  fieldNumber?: string;
  date?: string;
  siteSurveyor?: string;
  svPolygonNumber?: string;
  zone?: string;
  subZone?: string;
  siteSeries?: string;
  userSiteUnit?: string;
  addToActiveSu?: boolean;
}

export interface CreateSIVIPlotResult {
  requestId: string;
  contextId: string;
  project: string;
  plotNumber: string;
  plotType: SIVIPlotType;
  addedToSu: boolean;
  auditRowCount: number;
  createdAt: string;
  actor: string;
  replayed: boolean;
}

export interface UndoCreateSIVIPlotRequest {
  requestId?: string;
  creationRequestId: string;
  plotNumber: string;
}

export interface UndoCreateSIVIPlotResult {
  requestId: string;
  creationRequestId: string;
  contextId: string;
  project: string;
  plotNumber: string;
  removedFromSu: boolean;
  undoneAt: string;
  actor: string;
  replayed: boolean;
}

export interface SIVICreatedPlotEntry {
  requestId: string;
  plotNumber: string;
  plotType: SIVIPlotType;
  projectId?: string;
  svPolygonNumber?: string;
  createdAt: string;
  actor: string;
  undone: boolean;
  undoneAt?: string;
  canUndo: boolean;
}

export interface SIVIParentCreatePort {
  createPlot(contextId: string, req: CreateSIVIPlotRequest): Promise<CreateSIVIPlotResult>;
  undoCreatePlot(contextId: string, req: UndoCreateSIVIPlotRequest): Promise<UndoCreateSIVIPlotResult>;
  listCreatedPlots(contextId: string): Promise<SIVICreatedPlotEntry[]>;
}

export const defaultSIVIParentCreatePort: SIVIParentCreatePort = {
  createPlot: (contextId, req) => (ContextService.CreateSIVIPlot(contextId, req) as never),
  undoCreatePlot: (contextId, req) => (ContextService.UndoCreateSIVIPlot(contextId, req) as never),
  listCreatedPlots: contextId => (ContextService.ListCreatedSIVIPlots(contextId) as never),
};

function validateSIVIFieldUTF16(label: string, value: string | undefined, maxUnits: number, required = false): string | null {
  const text = value ?? '';
  if (!wellFormedUTF16(text) || text.includes('\0')) {
    return `${label} contains malformed Unicode or NUL bytes.`;
  }
  if (required && text.trim() === '') {
    return `${label} is required.`;
  }
  if (text.length > maxUnits) {
    return `${label} exceeds ${maxUnits} UTF-16 code units (entered ${text.length}).`;
  }
  return null;
}

function isValidISOCalendarDate(raw: string): boolean {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw);
  if (!m) return false;
  const year = Number.parseInt(m[1], 10);
  const month = Number.parseInt(m[2], 10);
  const day = Number.parseInt(m[3], 10);
  if (year < 100 || year > 9999 || month < 1 || month > 12 || day < 1 || day > 31) return false;
  const dt = new Date(Date.UTC(year, month - 1, day));
  return dt.getUTCFullYear() === year && dt.getUTCMonth() === month - 1 && dt.getUTCDate() === day;
}

export function validateCreateSIVIPlotDraft(draft: CreateSIVIPlotRequest): Record<string, string> {
  const errors: Record<string, string> = {};
  const plotErr = validateSIVIFieldUTF16('PlotNumber', draft.plotNumber, 7, true);
  if (plotErr) errors.plotNumber = plotErr;
  else if (draft.plotNumber !== draft.plotNumber.trim()) {
    errors.plotNumber = 'PlotNumber must not contain leading or trailing spaces.';
  }

  if (!SIVI_PLOT_TYPES.includes(draft.plotType)) {
    errors.plotType = 'PlotType must be Ground, Visual, Note, Other, or FS882.';
  }
  for (const [key, label, max] of [
    ['projectId', 'ProjectID', 30],
    ['fieldNumber', 'FieldNumber', 50],
    ['date', 'Date', 32],
    ['siteSurveyor', 'SiteSurveyor', 30],
    ['svPolygonNumber', 'SV_PolygonNumber', 25],
    ['zone', 'Zone', 4],
    ['subZone', 'SubZone', 8],
    ['siteSeries', 'SiteSeries', 5],
    ['userSiteUnit', 'UserSiteUnit', 100],
  ] as const) {
    const err = validateSIVIFieldUTF16(label, draft[key], max, false);
    if (err) errors[key] = err;
  }
  if (draft.date && draft.date.trim() !== '') {
    if (draft.date !== draft.date.trim() || !/^\d{4}-\d{2}-\d{2}$/.test(draft.date)) {
      errors.date = 'Date must use ISO format YYYY-MM-DD.';
    } else if (!isValidISOCalendarDate(draft.date)) {
      errors.date = 'Date must be a valid calendar date in YYYY-MM-DD format.';
    }
  }
  return errors;
}
