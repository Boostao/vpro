import {
  EnvironmentReportService,
  VegetationReportService,
  type HTMLReportResult,
  type QuickLifeformReportRequest,
  type QuickLongEnvironmentRequest,
  type QuickLongVegetationRequest,
  type QuickSubzoneMatrixRequest,
  type QuickSummaryEnvironmentRequest,
  type QuickSummaryVegetationRequest,
} from '../../bindings/github.com/boostao/vpro/app';
import { notifications } from '../shell/notificationService.svelte';
import { defaultWebExportFilename } from '../shell/webReadOnlyShell';
import { IS_WEB_READONLY } from '../web/runtimeMode';
import {
  formatCompactReportError,
  loadQuickReportPrefs,
  normalizeQuickEnvExportResult,
  normalizeQuickVegExportResult,
  saveQuickReportPrefs,
  type QuickExportSummary,
} from './compactReport';

export interface SummaryVegQuickDraft extends Record<string, unknown> {
  title: string;
  unitScope: 'auto' | 'su' | 'none' | 'field' | 'hierarchy';
  unitField: string;
  groupBy: number;
  display: number;
  showClass: number;
  average: number;
  showCommon: boolean;
  includeEnv: boolean;
  combineVariants: boolean;
  lumpTable: string;
}

export const DEFAULT_SUMMARY_VEG_QUICK: SummaryVegQuickDraft = {
  title: 'Summary Vegetation Report',
  unitScope: 'auto',
  unitField: '',
  groupBy: 1,
  display: 1,
  showClass: 10,
  average: 1,
  showCommon: false,
  includeEnv: false,
  combineVariants: false,
  lumpTable: '',
};

export interface LongVegQuickDraft extends Record<string, unknown> {
  title: string;
  grouping: 'layer' | 'strata' | 'lifeform' | 'none';
  average: 'all-plots' | 'non-zero';
  order: 'presence' | 'mean-cover' | 'species';
  scopeMode: 'auto' | 'su' | 'zone-subzone' | 'all-plots';
  showEnglishName: boolean;
  showSpeciesCode: boolean;
  constantSpeciesList: boolean;
  combineVariants: boolean;
  lumpTable: string;
}

export const DEFAULT_LONG_VEG_QUICK: LongVegQuickDraft = {
  title: 'Long Vegetation Report',
  grouping: 'layer',
  average: 'all-plots',
  order: 'presence',
  scopeMode: 'auto',
  showEnglishName: false,
  showSpeciesCode: true,
  constantSpeciesList: false,
  combineVariants: false,
  lumpTable: '',
};

export interface LifeformQuickDraft extends Record<string, unknown> {
  scopeMode: 'auto' | 'su' | 'zone-subzone' | 'all-plots';
  includeLifeformDetails: boolean;
  includeAttributeDetails: boolean;
}

export const DEFAULT_LIFEFORM_QUICK: LifeformQuickDraft = {
  scopeMode: 'auto',
  includeLifeformDetails: true,
  includeAttributeDetails: true,
};

export interface LongEnvQuickDraft extends Record<string, unknown> {
  title: string;
  scopeMode: 'auto' | 'su' | 'zone-subzone' | 'all-plots';
}

export const DEFAULT_LONG_ENV_QUICK: LongEnvQuickDraft = {
  title: 'Long Environment Report',
  scopeMode: 'auto',
};

export interface SummaryEnvQuickDraft extends Record<string, unknown> {
  method: number;
  siteUnitType: number;
  orderBy: number;
  includeSpecies: number;
  presenceGreaterThan: number;
  coverGreaterThan: number;
}

export const DEFAULT_SUMMARY_ENV_QUICK: SummaryEnvQuickDraft = {
  method: 1,
  siteUnitType: 1,
  orderBy: 1,
  includeSpecies: 0,
  presenceGreaterThan: 20,
  coverGreaterThan: 0,
};

function webDownloadTarget(prefix: string, project: string): string | undefined {
  if (typeof IS_WEB_READONLY === 'undefined' || !IS_WEB_READONLY) return undefined;
  const stem = `${project || 'vpro'}_${prefix}`;
  return typeof defaultWebExportFilename === 'function' ? defaultWebExportFilename(stem, '.xlsx') : `${stem}.xlsx`;
}

export function buildSummaryVegQuickRequest(
  draft: SummaryVegQuickDraft,
  project: string,
  forExport: boolean
): QuickSummaryVegetationRequest {
  const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
  return {
    title: draft.title.trim() || 'Summary Vegetation Report',
    unitScope: draft.unitScope,
    unitField: draft.unitScope === 'field' ? draft.unitField.trim() : '',
    groupBy: Number(draft.groupBy) || 1,
    display: Number(draft.display) || 1,
    showClass: Number(draft.showClass) || 10,
    average: Number(draft.average) || 1,
    showCommon: Boolean(draft.showCommon),
    includeEnv: Boolean(draft.includeEnv),
    combineVariants: Boolean(draft.combineVariants),
    lumpTable: draft.lumpTable.trim(),
    savePreferences: !webReadOnly,
    ...(forExport ? { openInSpreadsheet: !webReadOnly, destinationPath: webDownloadTarget('summary_veg', project) } : {}),
  };
}

export function buildLongVegQuickRequest(
  draft: LongVegQuickDraft,
  project: string,
  forExport: boolean
): QuickLongVegetationRequest {
  const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
  return {
    title: draft.title.trim() || 'Long Vegetation Report',
    grouping: draft.grouping,
    average: draft.average,
    order: draft.order,
    scopeMode: draft.scopeMode,
    showEnglishName: Boolean(draft.showEnglishName),
    showSpeciesCode: Boolean(draft.showSpeciesCode),
    constantSpeciesList: Boolean(draft.constantSpeciesList),
    combineVariants: Boolean(draft.combineVariants),
    lumpTable: draft.lumpTable.trim(),
    savePreferences: !webReadOnly,
    ...(forExport ? { openInSpreadsheet: !webReadOnly, destinationPath: webDownloadTarget('long_veg', project) } : {}),
  };
}

export function buildLifeformQuickRequest(
  draft: LifeformQuickDraft,
  project: string,
  forExport: boolean
): QuickLifeformReportRequest {
  const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
  const details = [
    Boolean(draft.includeLifeformDetails),
    Boolean(draft.includeAttributeDetails),
    Boolean(draft.includeAttributeDetails),
    Boolean(draft.includeAttributeDetails),
    Boolean(draft.includeAttributeDetails),
    Boolean(draft.includeAttributeDetails),
  ];
  return {
    scopeMode: draft.scopeMode,
    details,
    ...(forExport ? { openInSpreadsheet: !webReadOnly, destinationPath: webDownloadTarget('lifeform', project) } : {}),
  };
}

export function buildLongEnvQuickRequest(
  draft: LongEnvQuickDraft,
  project: string,
  forExport: boolean
): QuickLongEnvironmentRequest {
  const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
  return {
    title: draft.title.trim() || 'Long Environment Report',
    scopeMode: draft.scopeMode,
    savePreferences: !webReadOnly,
    ...(forExport ? { openInSpreadsheet: !webReadOnly, destinationPath: webDownloadTarget('long_env', project) } : {}),
  };
}

export function buildSummaryEnvQuickRequest(
  draft: SummaryEnvQuickDraft,
  project: string,
  forExport: boolean
): QuickSummaryEnvironmentRequest {
  const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
  return {
    method: Number(draft.method) || 1,
    siteUnitType: Number(draft.siteUnitType) || 1,
    orderBy: Number(draft.orderBy) || 1,
    includeSpecies: Number(draft.includeSpecies) ? 1 : 0,
    presenceGreaterThan: Number(draft.presenceGreaterThan) || 0,
    coverGreaterThan: Number(draft.coverGreaterThan) || 0,
    savePreferences: !webReadOnly,
    ...(forExport ? { openInSpreadsheet: !webReadOnly, destinationPath: webDownloadTarget('summary_env', project) } : {}),
  };
}

export function buildSubzoneMatrixQuickRequest(hierarchy: string): QuickSubzoneMatrixRequest {
  const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
  return {
    openInSpreadsheet: !webReadOnly,
    destinationPath: webDownloadTarget('subzone_matrix', hierarchy || 'subzone'),
  };
}

export function loadInitialQuickDraft<T extends Record<string, unknown>>(key: string, defaults: T): T {
  return loadQuickReportPrefs(key, defaults);
}

export function persistQuickDraft<T extends Record<string, unknown>>(key: string, draft: T): void {
  saveQuickReportPrefs(key, draft);
}

export async function runQuickSpreadsheetExport(params: {
  source: string;
  project?: string;
  kind: 'veg' | 'env';
  invoke: () => Promise<unknown>;
}): Promise<{ summary: QuickExportSummary | null; error: string }> {
  const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
  try {
    const raw = await params.invoke();
    const summary =
      params.kind === 'veg'
        ? normalizeQuickVegExportResult(raw as never)
        : normalizeQuickEnvExportResult(raw as never);
    if (summary) {
      notifications.success(
        webReadOnly ? `${params.source} spreadsheet downloaded` : `${params.source} exported to spreadsheet`,
        webReadOnly ? `${summary.unitCount} units · ${summary.plotCount} plots` : summary.path || summary.scopeLabel,
        { category: 'reports', source: params.source, contextTag: params.project || undefined }
      );
    }
    return { summary, error: '' };
  } catch (cause) {
    const error = formatCompactReportError(cause, `${params.source} spreadsheet export`);
    notifications.error(`${params.source} export failed`, error, {
      category: 'reports',
      source: params.source,
      contextTag: params.project || undefined,
    });
    return { summary: null, error };
  }
}

export async function runQuickHTMLDisplay(params: {
  source: string;
  project?: string;
  invoke: () => Promise<HTMLReportResult | null>;
}): Promise<{ report: HTMLReportResult | null; error: string }> {
  try {
    const report = await params.invoke();
    if (!report || !report.html) {
      throw new Error('The report renderer returned an empty document.');
    }
    return { report, error: '' };
  } catch (cause) {
    const error = formatCompactReportError(cause, `${params.source} display report`);
    notifications.error(`${params.source} display failed`, error, {
      category: 'reports',
      source: params.source,
      contextTag: params.project || undefined,
    });
    return { report: null, error };
  }
}

export async function hydrateSummaryVegQuickDraft(
  contextId: string,
  current: SummaryVegQuickDraft
): Promise<SummaryVegQuickDraft> {
  if (!contextId || typeof VegetationReportService?.GetSummaryVegetationPreferences !== 'function') return current;
  try {
    const review = await VegetationReportService.GetSummaryVegetationPreferences(contextId);
    const saved = review?.values;
    if (!saved) return current;
    return {
      ...current,
      groupBy: typeof saved.groupBy === 'number' && saved.groupBy >= 1 && saved.groupBy <= 4 ? saved.groupBy : current.groupBy,
      average: typeof saved.average === 'number' && (saved.average === 1 || saved.average === 2) ? saved.average : current.average,
      display: typeof saved.display === 'number' && saved.display >= 1 && saved.display <= 6 ? saved.display : current.display,
      showClass: typeof saved.showClass === 'number' && saved.showClass > 0 ? saved.showClass : current.showClass,
    };
  } catch {
    return current;
  }
}

export async function hydrateLongEnvQuickDraft(
  contextId: string,
  current: LongEnvQuickDraft
): Promise<LongEnvQuickDraft> {
  if (!contextId || typeof EnvironmentReportService?.GetLongEnvironmentPreferences !== 'function') return current;
  try {
    const review = await EnvironmentReportService.GetLongEnvironmentPreferences(contextId);
    const savedTitle = review?.values?.title;
    if (typeof savedTitle === 'string' && savedTitle.trim()) {
      return { ...current, title: savedTitle.trim() };
    }
    return current;
  } catch {
    return current;
  }
}

export async function hydrateSummaryEnvQuickDraft(
  contextId: string,
  current: SummaryEnvQuickDraft
): Promise<SummaryEnvQuickDraft> {
  if (!contextId) return current;
  try {
    if (typeof EnvironmentReportService?.GetFullSiteUnitSummaryPreferences === 'function') {
      const full = await EnvironmentReportService.GetFullSiteUnitSummaryPreferences(contextId);
      const vals = full?.values;
      if (vals) {
        return {
          ...current,
          method: vals.method === 1 || vals.method === 2 ? vals.method : current.method,
          siteUnitType: vals.siteUnitType >= 1 && vals.siteUnitType <= 3 ? vals.siteUnitType : current.siteUnitType,
          orderBy: vals.orderBy === 1 || vals.orderBy === 2 ? vals.orderBy : current.orderBy,
          includeSpecies: vals.includeSpecies ? 1 : 0,
          presenceGreaterThan: typeof vals.presenceGreaterThan === 'number' ? vals.presenceGreaterThan : current.presenceGreaterThan,
          coverGreaterThan: typeof vals.coverGreaterThan === 'number' ? vals.coverGreaterThan : current.coverGreaterThan,
        };
      }
    }
  } catch {
    // Fall back to cached or default summary environment settings.
  }
  return current;
}
