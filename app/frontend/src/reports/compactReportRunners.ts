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

function webDownloadTarget(prefix: string, project: string): string {
  const stem = `${project || 'vpro'}_${prefix}`;
  return typeof defaultWebExportFilename === 'function' ? defaultWebExportFilename(stem, '.xlsx') : `${stem}.xlsx`;
}

function webReviewedExportSummary(params: {
  reportKind: string;
  title: string;
  project: string;
  su: string;
  destination: string;
  bytes: number;
  unitCount: number;
  plotCount: number;
}): QuickExportSummary {
  return {
    reportKind: params.reportKind,
    title: params.title,
    project: params.project,
    su: params.su,
    scopeLabel: params.su && params.su !== 'None' ? `Active SU: ${params.su}` : 'Reviewed Workbook',
    fallbackNotice: '',
    unitCount: params.unitCount,
    plotCount: params.plotCount,
    path: params.destination,
    bytes: params.bytes,
    preferencesSaved: false,
    openedInSpreadsheet: false,
    spreadsheetNotice: '',
  };
}

export async function exportSummaryVegSpreadsheet(
  contextId: string,
  draft: SummaryVegQuickDraft,
  project: string,
  su: string
): Promise<{ summary: QuickExportSummary | null; error: string }> {
  const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
  if (!webReadOnly) {
    const req = buildSummaryVegQuickRequest(draft, project, true);
    return runQuickSpreadsheetExport({
      source: 'Summary Vegetation',
      project,
      kind: 'veg',
      invoke: () => VegetationReportService.QuickRunSummaryVegetationWorkbook(contextId, req),
    });
  }
  return runReviewedWebDownload({
    source: 'Summary Vegetation',
    project,
    invoke: async () => {
      const review = await VegetationReportService.GetSummaryVegetationWorkbookReviewFromPreferences(contextId);
      if (!review?.approvalHash) throw new Error('Summary Vegetation workbook review returned no approval snapshot.');
      const destination = webDownloadTarget('summary_veg', project);
      const outcome = await VegetationReportService.ExportReviewedSummaryVegetationWorkbook(
        contextId,
        JSON.stringify({
          options: review.options,
          approvalHash: review.approvalHash,
          destination,
          ...(review.ancillary ? { createdAt: review.ancillary.createdAt } : {}),
        })
      );
      if (outcome && outcome.status !== 'published') throw new Error(outcome.errorMessage || 'Download failed.');
      return webReviewedExportSummary({
        reportKind: 'summary_vegetation',
        title: draft.title.trim() || 'Summary Vegetation Report',
        project,
        su,
        destination,
        bytes: Number(review.bytes ?? 0),
        unitCount: review.preview?.units?.length ?? 0,
        plotCount: review.preview?.memberships?.length ?? 0,
      });
    },
  });
}

export async function exportLongVegSpreadsheet(
  contextId: string,
  draft: LongVegQuickDraft,
  project: string,
  su: string
): Promise<{ summary: QuickExportSummary | null; error: string }> {
  const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
  if (!webReadOnly) {
    const req = buildLongVegQuickRequest(draft, project, true);
    return runQuickSpreadsheetExport({
      source: 'Long Vegetation',
      project,
      kind: 'veg',
      invoke: () => VegetationReportService.QuickRunLongVegetationWorkbook(contextId, req),
    });
  }
  return runReviewedWebDownload({
    source: 'Long Vegetation',
    project,
    invoke: async () => {
      const scope = draft.lumpTable.trim() ? `lump:${draft.lumpTable.trim()}` : 'unlumped';
      const review = await VegetationReportService.GetVegetationWorkbookReview(contextId, JSON.stringify({ scope }));
      if (!review?.approvalHash) throw new Error('Long Vegetation workbook review returned no approval snapshot.');
      const destination = webDownloadTarget('long_veg', project);
      const outcome = await VegetationReportService.ExportReviewedVegetationWorkbook(
        contextId,
        JSON.stringify({
          scope: review.scope || scope,
          createdDate: review.createdDate,
          approvalHash: review.approvalHash,
          destination,
        })
      );
      if (outcome && outcome.status !== 'published') throw new Error(outcome.errorMessage || 'Download failed.');
      const units = review.preview?.report?.units ?? [];
      const plotCount = units.reduce((acc, u) => acc + Number(u.numPlots ?? 0), 0);
      return webReviewedExportSummary({
        reportKind: 'long_vegetation',
        title: draft.title.trim() || 'Long Vegetation Report',
        project,
        su,
        destination,
        bytes: Number(review.bytes ?? 0),
        unitCount: units.length,
        plotCount,
      });
    },
  });
}

export async function exportLifeformSpreadsheet(
  contextId: string,
  draft: LifeformQuickDraft,
  project: string,
  su: string
): Promise<{ summary: QuickExportSummary | null; error: string }> {
  const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
  if (!webReadOnly) {
    const req = buildLifeformQuickRequest(draft, project, true);
    return runQuickSpreadsheetExport({
      source: 'Lifeform Summary',
      project,
      kind: 'veg',
      invoke: () => VegetationReportService.QuickRunLifeformWorkbook(contextId, req),
    });
  }
  return runReviewedWebDownload({
    source: 'Lifeform Summary',
    project,
    invoke: async () => {
      const details = buildLifeformQuickRequest(draft, project, false).details ?? [true, true, true, true, true, true];
      const review = await VegetationReportService.GetLifeformWorkbookReview(contextId, JSON.stringify({ details }));
      if (!review?.approvalHash) throw new Error('Lifeform workbook review returned no approval snapshot.');
      const destination = webDownloadTarget('lifeform', project);
      const outcome = await VegetationReportService.ExportReviewedLifeformWorkbook(
        contextId,
        JSON.stringify({ details: review.details ?? details, approvalHash: review.approvalHash, destination })
      );
      if (outcome && outcome.status !== 'published') throw new Error(outcome.errorMessage || 'Download failed.');
      const units = review.lifeform?.report?.units ?? [];
      const plotCount = units.reduce((acc, u) => acc + Number(u.nPlots ?? 0), 0);
      return webReviewedExportSummary({
        reportKind: 'lifeform_summary',
        title: 'Lifeform Summary',
        project,
        su,
        destination,
        bytes: Number(review.bytes ?? 0),
        unitCount: units.length,
        plotCount,
      });
    },
  });
}

export async function exportLongEnvSpreadsheet(
  contextId: string,
  draft: LongEnvQuickDraft,
  project: string,
  su: string
): Promise<{ summary: QuickExportSummary | null; error: string }> {
  const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
  if (!webReadOnly) {
    const req = buildLongEnvQuickRequest(draft, project, true);
    return runQuickSpreadsheetExport({
      source: 'Long Environment',
      project,
      kind: 'env',
      invoke: () => EnvironmentReportService.QuickRunLongEnvironmentWorkbook(contextId, req),
    });
  }
  return runReviewedWebDownload({
    source: 'Long Environment',
    project,
    invoke: async () => {
      const requestedTitle = draft.title.trim() || 'Long Environment Report';
      const review = await EnvironmentReportService.GetEnvironmentWorkbookReview(
        contextId,
        JSON.stringify({ title: requestedTitle })
      );
      if (!review?.approvalHash) throw new Error('Long Environment workbook review returned no approval snapshot.');
      const destination = webDownloadTarget('long_env', project);
      const title = review.preview?.report?.title ?? requestedTitle;
      const outcome = await EnvironmentReportService.ExportReviewedEnvironmentWorkbook(
        contextId,
        JSON.stringify({ title, approvalHash: review.approvalHash, destination })
      );
      if (outcome && outcome.status !== 'published') throw new Error(outcome.errorMessage || 'Download failed.');
      const units = review.preview?.report?.units ?? [];
      const plotCount = units.reduce((acc, u) => acc + (u.plots?.length ?? 0), 0);
      return webReviewedExportSummary({
        reportKind: 'long_environment',
        title,
        project,
        su,
        destination,
        bytes: Number(review.bytes ?? 0),
        unitCount: units.length,
        plotCount,
      });
    },
  });
}

export async function exportSummaryEnvSpreadsheet(
  contextId: string,
  draft: SummaryEnvQuickDraft,
  project: string,
  su: string
): Promise<{ summary: QuickExportSummary | null; error: string }> {
  const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
  if (!webReadOnly) {
    const req = buildSummaryEnvQuickRequest(draft, project, true);
    return runQuickSpreadsheetExport({
      source: 'Summary Environment',
      project,
      kind: 'env',
      invoke: () => EnvironmentReportService.QuickRunSummaryEnvironmentWorkbook(contextId, req),
    });
  }
  return runReviewedWebDownload({
    source: 'Summary Environment',
    project,
    invoke: async () => {
      const method = Number(draft.method) === 2 ? 2 : 1;
      const orderBy = Number(draft.orderBy) === 2 ? 2 : 1;
      const includeSpecies = Boolean(draft.includeSpecies);
      const destination = webDownloadTarget('summary_env', project);
      if (orderBy === 2 || includeSpecies) {
        const extOpts = {
          method,
          orderBy,
          includeSpecies,
          coverCalculation: 1,
          andOr: 1,
          presenceGreaterThan: Number(draft.presenceGreaterThan) || 0,
          coverGreaterThan: Number(draft.coverGreaterThan) || 0,
        };
        const review = await EnvironmentReportService.GetSiteUnitSummaryExtendedWorkbookReview(
          contextId,
          JSON.stringify(extOpts)
        );
        if (!review?.approvalHash) throw new Error('Summary Environment workbook review returned no approval snapshot.');
        const outcome = await EnvironmentReportService.ExportReviewedSiteUnitSummaryExtendedWorkbook(
          contextId,
          JSON.stringify({ ...(review.options ?? extOpts), approvalHash: review.approvalHash, destination })
        );
        if (outcome && outcome.status !== 'published') throw new Error(outcome.errorMessage || 'Download failed.');
        const units = review.environment?.report?.units ?? [];
        const plotCount = units.reduce((acc, u) => acc + (u.plots?.length ?? 0), 0);
        return webReviewedExportSummary({
          reportKind: 'summary_environment',
          title: 'Summary Environment',
          project,
          su,
          destination,
          bytes: Number(review.bytes ?? 0),
          unitCount: units.length,
          plotCount,
        });
      }
      const review = await EnvironmentReportService.GetSiteUnitSummaryWorkbookReview(
        contextId,
        JSON.stringify({ method })
      );
      if (!review?.approvalHash) throw new Error('Summary Environment workbook review returned no approval snapshot.');
      const outcome = await EnvironmentReportService.ExportReviewedSiteUnitSummaryWorkbook(
        contextId,
        JSON.stringify({ method, approvalHash: review.approvalHash, destination })
      );
      if (outcome && outcome.status !== 'published') throw new Error(outcome.errorMessage || 'Download failed.');
      const units = review.preview?.report?.units ?? [];
      const plotCount = units.reduce((acc, u) => acc + (u.plots?.length ?? 0), 0);
      return webReviewedExportSummary({
        reportKind: 'summary_environment',
        title: 'Summary Environment',
        project,
        su,
        destination,
        bytes: Number(review.bytes ?? 0),
        unitCount: units.length,
        plotCount,
      });
    },
  });
}

export async function exportSubzoneMatrixSpreadsheet(
  contextId: string,
  hierarchy: string
): Promise<{ summary: QuickExportSummary | null; error: string }> {
  const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
  if (!webReadOnly) {
    const req = buildSubzoneMatrixQuickRequest(hierarchy);
    return runQuickSpreadsheetExport({
      source: 'Subzone Matrix',
      project: hierarchy,
      kind: 'env',
      invoke: () => EnvironmentReportService.QuickRunSubzoneMatrixWorkbook(contextId, req),
    });
  }
  return runReviewedWebDownload({
    source: 'Subzone Matrix',
    project: hierarchy,
    invoke: async () => {
      const review = await EnvironmentReportService.GetSubzoneMatrixReview(contextId);
      if (!review?.approvalHash) throw new Error('Subzone Matrix workbook review returned no approval snapshot.');
      const destination = webDownloadTarget('subzone_matrix', hierarchy || 'subzone');
      const outcome = await EnvironmentReportService.ExportReviewedSubzoneMatrix(
        contextId,
        JSON.stringify({ approvalHash: review.approvalHash, destination })
      );
      if (outcome && outcome.status !== 'published') throw new Error(outcome.errorMessage || 'Download failed.');
      return webReviewedExportSummary({
        reportKind: 'subzone_matrix',
        title: 'Subzone Matrix of Units',
        project: hierarchy,
        su: hierarchy,
        destination,
        bytes: Number(review.bytes ?? 0),
        unitCount: review.preview?.columns?.length ?? 0,
        plotCount: Number(review.preview?.total ?? 0),
      });
    },
  });
}

async function runReviewedWebDownload(params: {
  source: string;
  project?: string;
  invoke: () => Promise<QuickExportSummary>;
}): Promise<{ summary: QuickExportSummary | null; error: string }> {
  try {
    const summary = await params.invoke();
    notifications.success(
      `${params.source} spreadsheet downloaded`,
      `${summary.unitCount} units · ${summary.plotCount} plots`,
      { category: 'reports', source: params.source, contextTag: params.project || undefined }
    );
    return { summary, error: '' };
  } catch (cause) {
    const error = formatCompactReportError(cause, `${params.source} spreadsheet download`);
    notifications.error(`${params.source} download failed`, error, {
      category: 'reports',
      source: params.source,
      contextTag: params.project || undefined,
    });
    return { summary: null, error };
  }
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
    ...(forExport
      ? { openInSpreadsheet: !webReadOnly, destinationPath: webReadOnly ? webDownloadTarget('summary_veg', project) : undefined }
      : {}),
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
    ...(forExport
      ? { openInSpreadsheet: !webReadOnly, destinationPath: webReadOnly ? webDownloadTarget('long_veg', project) : undefined }
      : {}),
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
    ...(forExport
      ? { openInSpreadsheet: !webReadOnly, destinationPath: webReadOnly ? webDownloadTarget('lifeform', project) : undefined }
      : {}),
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
    ...(forExport
      ? { openInSpreadsheet: !webReadOnly, destinationPath: webReadOnly ? webDownloadTarget('long_env', project) : undefined }
      : {}),
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
    ...(forExport
      ? { openInSpreadsheet: !webReadOnly, destinationPath: webReadOnly ? webDownloadTarget('summary_env', project) : undefined }
      : {}),
  };
}

function buildSubzoneMatrixQuickRequest(hierarchy: string): QuickSubzoneMatrixRequest {
  const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
  return {
    openInSpreadsheet: !webReadOnly,
    destinationPath: webReadOnly ? webDownloadTarget('subzone_matrix', hierarchy || 'subzone') : undefined,
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
