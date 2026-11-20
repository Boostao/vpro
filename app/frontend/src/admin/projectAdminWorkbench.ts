import { wellFormedUTF16 } from '../entry/qualityEditor';
import { ContextService, ValidationService } from '../../bindings/github.com/boostao/vpro/app';
import { formatError } from '../shared/readRequests';
import { notifications } from '../shell/notificationService.svelte';
import type { ProjectMetadataPreset } from './projectMetadataPresets';

export { formatError, notifications };

const PROJECT_NAME_PATTERN = /^[A-Za-z][A-Za-z0-9_]{0,30}$/;

export type MergeResolutionChoice = 'keep_target' | 'accept_source';
export type { ProjectMetadataPreset };

interface NewProjectRequest {
  projectName: string;
  projectId?: string;
  projectTitle?: string;
  presetId?: string;
  destinationPath?: string;
  activateOnSuccess: boolean;
}

export interface NewProjectResult {
  projectName: string;
  projectId: string;
  destinationPath: string;
  destinationSha256: string;
  activated: boolean;
  state?: unknown;
}

interface SaveProjectAsRequest {
  newProjectName: string;
  destinationPath?: string;
  activateOnSuccess: boolean;
}

export interface SaveProjectAsResult {
  sourceProject: string;
  newProjectName: string;
  destinationPath: string;
  destinationSha256: string;
  copiedTables: string[];
  companionTables: string[];
  activated: boolean;
  state?: unknown;
}

interface ExportSplinterRequest {
  splinterProject: string;
  destinationPath?: string;
  useActiveSu: boolean;
  siteUnits?: string[];
  plotNumbers?: string[];
  activateOnSuccess: boolean;
}

export interface ExportSplinterResult {
  sourceProject: string;
  splinterProject: string;
  destinationPath: string;
  destinationSha256: string;
  sourcePlotCount: number;
  exportedPlotCount: number;
  createdSuTable: boolean;
  activated: boolean;
  state?: unknown;
}

interface CompareProjectsRequest {
  sourcePath?: string;
  sourceProject?: string;
  targetPath: string;
  targetProject?: string;
  caseInsensitiveText?: boolean;
}

export interface FieldDiff {
  table: string;
  plotNumber: string;
  key: string;
  field: string;
  sourceVal: string | null;
  targetVal: string | null;
}

interface PlotDiff {
  plotNumber: string;
  status: 'Added' | 'Removed' | 'Identical' | 'Modified';
  diffCount: number;
  fieldDiffs: FieldDiff[];
}

export interface CompareProjectsResult {
  sourcePath: string;
  sourceProject: string;
  targetPath: string;
  targetProject: string;
  totalPlots: number;
  addedCount: number;
  removedCount: number;
  identicalCount: number;
  modifiedCount: number;
  metadataDiffCount?: number;
  plots: PlotDiff[];
  fieldDiffs: FieldDiff[];
  metadataDiffs?: FieldDiff[] | null;
}

interface ComplianceOptions {
  useActiveSu: boolean;
}

interface ComplianceSummaryCounts {
  envCodeErrors: number;
  boundsErrors: number;
  envAdminMismatches: number;
  orphanChildRows: number;
  duplicateSpeciesSplits: number;
  unlistedSpecies: number;
  synonymSpecies: number;
  userSpecies: number;
  plotsWithoutVeg: number;
}

interface EnvironmentCodeFinding {
  listName: string;
  field: string;
  plotNumber: string;
  value: string;
}

interface BoundsFinding {
  table: string;
  plotNumber: string;
  rowId: number;
  field: string;
  value: string;
  rule: string;
}

interface EnvAdminCompletenessFinding {
  plotNumber: string;
  issue: string;
}

interface OrphanChildFinding {
  table: string;
  plotNumber: string;
  rowCount: number;
}

interface DuplicateVegSpeciesFinding {
  plotNumber: string;
  species: string;
  rowCount: number;
  overlappingLayers: string[];
}

interface TaxonomyComplianceFinding {
  rowId: number;
  id: number;
  plotNumber: string;
  species: string;
  status: string;
  suggestedCode?: string;
}

interface SkippedListDefinition {
  listName: string;
  field: string;
  reason: string;
}

export interface ComplianceValidationReport {
  project: string;
  su: string;
  useActiveSu: boolean;
  passed: boolean;
  summary: ComplianceSummaryCounts;
  envCodeFindings: EnvironmentCodeFinding[];
  skippedDefinitions?: SkippedListDefinition[] | null;
  boundsFindings: BoundsFinding[];
  envAdminFindings: EnvAdminCompletenessFinding[];
  orphanFindings: OrphanChildFinding[];
  plotsWithoutVegetation: string[];
  duplicateVegFindings: DuplicateVegSpeciesFinding[];
  taxonomyFindings: TaxonomyComplianceFinding[];
}

interface QuarantineOrphanRequest {
  tables?: string[];
}

interface QuarantinedTableSummary {
  table: string;
  quarantineTable: string;
  movedRows: number;
  plotNumbers: string[];
}

export interface QuarantineOrphanResult {
  project: string;
  batchId: string;
  totalQuarantined: number;
  reservedDeletedIds: number[];
  auditRowId?: number;
  tables: QuarantinedTableSummary[];
}

interface OptimizeVegOptions {
  plotNumbers?: string[];
  custodianAuditOverride?: boolean;
}

interface OptimizeVegConflict {
  plotNumber: string;
  species: string;
  field: string;
  reason: string;
  values?: string[] | null;
  sourceIds?: number[] | null;
  overrideable?: boolean;
}

interface OptimizeVegAuditRef {
  plotNumber: string;
  species: string;
  retiredId: number;
  table: string;
  editField: string;
  editWhen: string;
}

interface OptimizeVegGroup {
  plotNumber: string;
  species: string;
  sourceRowCount: number;
  survivorId: number;
  retiredIds: number[];
  hasOverlappingLayerCovers: boolean;
  cappedCoverColumns: string[];
  mergedCovers: Record<string, number>;
  mergedHeights: Record<string, number>;
  mergedHeightB?: string;
  blocked?: boolean;
  blockedReasons?: string[] | null;
  conflicts?: OptimizeVegConflict[] | null;
  auditReferences?: OptimizeVegAuditRef[] | null;
}

export interface OptimizeVegPreview {
  project: string;
  beforeRowCount: number;
  afterRowCount: number;
  rowsToConsolidate: number;
  duplicateSpeciesCount: number;
  overlappingGroupCount: number;
  cappedCoverCount: number;
  blockedGroupCount?: number;
  hasBlockingConflicts?: boolean;
  previewDigest: string;
  groups: OptimizeVegGroup[];
  conflicts?: OptimizeVegConflict[] | null;
  auditReferences?: OptimizeVegAuditRef[] | null;
}

interface ApplyOptimizeVegRequest {
  plotNumbers?: string[];
  expectedDigest?: string;
  custodianAuditOverride?: boolean;
}

export interface OptimizeVegResult {
  project: string;
  beforeRowCount: number;
  afterRowCount: number;
  consolidatedGroups: number;
  deletedRows: number;
  reservedDeletedIds: number[];
  auditRowsWritten: number;
  groups: OptimizeVegGroup[];
}

interface ThreeWayMergePreviewRequest {
  sourcePath: string;
  sourceProject?: string;
  targetPath?: string;
  targetProject?: string;
  basePath?: string;
  baseProject?: string;
  caseInsensitiveText?: boolean;
}

interface MergeConflictItem {
  conflictId: string;
  plotNumber: string;
  table: string;
  key: string;
  field: string;
  baseVal?: string | null;
  sourceVal: string | null;
  targetVal: string | null;
  kind: 'FastForward' | 'Conflict' | 'TargetModifiedOnly' | 'SourceDelete';
  defaultResolution: MergeResolutionChoice;
}

interface MergePlotPreview {
  plotNumber: string;
  category: 'Added' | 'Identical' | 'FastForward' | 'Conflict' | 'TargetOnly' | 'SourceDelete';
  items: MergeConflictItem[];
}

export interface ThreeWayMergePreview {
  sourcePath: string;
  sourceProject: string;
  targetPath: string;
  targetProject: string;
  basePath?: string;
  baseProject?: string;
  previewDigest: string;
  addedCount: number;
  identicalCount: number;
  fastForwardCount: number;
  conflictCount: number;
  targetOnlyCount: number;
  sourceDeleteCount?: number;
  metadataConflictCount?: number;
  plots: MergePlotPreview[];
  conflicts: MergeConflictItem[];
  metadataItems?: MergeConflictItem[] | null;
}

interface ThreeWayMergeExecuteRequest {
  sourcePath: string;
  sourceProject?: string;
  targetPath?: string;
  targetProject?: string;
  basePath?: string;
  baseProject?: string;
  expectedPreviewDigest?: string;
  defaultConflictResolution?: MergeResolutionChoice;
  plotResolutions?: Record<string, MergeResolutionChoice>;
  fieldResolutions?: Record<string, MergeResolutionChoice>;
  caseInsensitiveText?: boolean;
}

export interface ThreeWayMergeResult {
  sourceProject: string;
  targetProject: string;
  targetPath: string;
  addedPlots: number;
  updatedPlots: number;
  skippedPlots: number;
  allocatedChildIds: number[];
  reservedDeletedIds: number[];
  auditRowsWritten: number;
}

export interface ProjectAdminPort {
  listProjectMetadataPresets?(): Promise<ProjectMetadataPreset[]>;
  createNewProject(contextId: string, req: NewProjectRequest): Promise<NewProjectResult>;
  saveProjectAs(contextId: string, req: SaveProjectAsRequest): Promise<SaveProjectAsResult>;
  exportSplinterProject(contextId: string, req: ExportSplinterRequest): Promise<ExportSplinterResult>;
  compareProjects(contextId: string, req: CompareProjectsRequest): Promise<CompareProjectsResult>;
  runComplianceValidation(contextId: string, opts: ComplianceOptions): Promise<ComplianceValidationReport>;
  quarantineOrphanRecords(contextId: string, req: QuarantineOrphanRequest): Promise<QuarantineOrphanResult>;
  previewOptimizeVeg(contextId: string, opts: OptimizeVegOptions): Promise<OptimizeVegPreview>;
  applyOptimizeVeg(contextId: string, req: ApplyOptimizeVegRequest): Promise<OptimizeVegResult>;
  previewThreeWayMerge(contextId: string, req: ThreeWayMergePreviewRequest): Promise<ThreeWayMergePreview>;
  executeThreeWayMerge(contextId: string, req: ThreeWayMergeExecuteRequest): Promise<ThreeWayMergeResult>;
}

export const defaultProjectAdminPort: ProjectAdminPort = {
  listProjectMetadataPresets: () => ContextService.ListProjectMetadataPresets() as never,
  createNewProject: (contextId, req) => ContextService.CreateNewProject(contextId, req) as never,
  saveProjectAs: (contextId, req) => ContextService.SaveProjectAs(contextId, req) as never,
  exportSplinterProject: (contextId, req) => ContextService.ExportSplinterProject(contextId, req) as never,
  compareProjects: (contextId, req) => ContextService.CompareProjects(contextId, req) as never,
  runComplianceValidation: (contextId, opts) => ValidationService.RunComplianceValidation(contextId, opts) as never,
  quarantineOrphanRecords: (contextId, req) => ValidationService.QuarantineOrphanRecords(contextId, req) as never,
  previewOptimizeVeg: (contextId, opts) => ValidationService.PreviewOptimizeVeg(contextId, opts) as never,
  applyOptimizeVeg: (contextId, req) => ValidationService.ApplyOptimizeVeg(contextId, req) as never,
  previewThreeWayMerge: (contextId, req) => ValidationService.PreviewThreeWayMerge(contextId, req) as never,
  executeThreeWayMerge: (contextId, req) => ValidationService.ExecuteThreeWayMerge(contextId, req) as never,
};

export function validateProjectNameInput(raw: string): string | null {
  if (typeof raw !== 'string' || !wellFormedUTF16(raw) || raw.includes('\0')) {
    return 'Project name must be well-formed Unicode without NUL characters.';
  }
  if (raw === '' || raw.trim() !== raw) {
    return 'Project name is required and cannot contain leading or trailing spaces.';
  }
  if (!PROJECT_NAME_PATTERN.test(raw)) {
    return 'Project name must start with a letter and use only ASCII letters, digits, or underscores (max 31 characters).';
  }
  const lower = raw.toLowerCase();
  if (lower === 'none' || lower === 'sample' || lower.includes('master')) {
    return `Project name "${raw}" is reserved (None, Sample, and master names are not permitted).`;
  }
  return null;
}

export function validateNewProjectDraft(draft: NewProjectRequest): string | null {
  const nameErr = validateProjectNameInput(draft.projectName);
  if (nameErr) return nameErr;
  if (draft.projectId !== undefined && draft.projectId !== '') {
    if (!wellFormedUTF16(draft.projectId) || draft.projectId.includes('\0')) {
      return 'ProjectID contains invalid Unicode.';
    }
    if (draft.projectId.length > 20) {
      return 'Metadata ProjectID cannot exceed 20 UTF-16 code units.';
    }
  }
  if (draft.projectTitle !== undefined && draft.projectTitle !== '') {
    if (!wellFormedUTF16(draft.projectTitle) || draft.projectTitle.includes('\0')) {
      return 'ProjectTitle contains invalid Unicode.';
    }
    if (draft.projectTitle.length > 255) {
      return 'ProjectTitle cannot exceed 255 UTF-16 code units.';
    }
  }
  return null;
}

export function parseLiteralTokenList(raw: string): string[] {
  if (!raw || !raw.trim()) return [];
  const items: string[] = [];
  for (const part of raw.split(/[\n,]+/)) {
    const trimmed = part.trim();
    if (trimmed !== '' && !items.includes(trimmed)) {
      items.push(trimmed);
    }
  }
  return items;
}

export function validateSplinterDraft(draft: ExportSplinterRequest, activeSu: string): string | null {
  const nameErr = validateProjectNameInput(draft.splinterProject);
  if (nameErr) return nameErr;
  const hasPlots = (draft.plotNumbers?.length ?? 0) > 0;
  const hasUnits = (draft.siteUnits?.length ?? 0) > 0;
  if (draft.useActiveSu && (!activeSu || activeSu === 'None') && !hasPlots && !hasUnits) {
    return 'Select an active Site Unit (SU) table or provide explicit Site Units or Plot Numbers.';
  }
  if (!draft.useActiveSu && !hasPlots && !hasUnits) {
    return 'Enable active SU filtering or specify at least one Site Unit or Plot Number.';
  }
  for (const plot of draft.plotNumbers ?? []) {
    if (!wellFormedUTF16(plot) || plot.includes('\0') || plot.length > 7) {
      return `Plot number "${plot}" exceeds 7 UTF-16 code units or contains invalid characters.`;
    }
  }
  return null;
}

export function buildInitialMergeFieldResolutions(
  preview: ThreeWayMergePreview
): Record<string, MergeResolutionChoice> {
  const map: Record<string, MergeResolutionChoice> = {};
  for (const c of preview.conflicts) {
    map[c.conflictId] = c.defaultResolution;
  }
  for (const c of preview.metadataItems ?? []) {
    map[c.conflictId] = c.defaultResolution;
  }
  return map;
}

export function buildInitialMergePlotResolutions(preview: ThreeWayMergePreview): Record<string, MergeResolutionChoice> {
  const map: Record<string, MergeResolutionChoice> = {};
  for (const plot of preview.plots ?? []) {
    if (plot.category === 'Added' || plot.category === 'FastForward' || plot.category === 'SourceDelete') {
      map[plot.plotNumber] = 'accept_source';
    } else if (plot.category === 'Conflict' || plot.category === 'TargetOnly') {
      map[plot.plotNumber] = 'keep_target';
    }
  }
  return map;
}

function escapeDelimitedCell(raw: string | null | undefined, delimiter: ',' | '\t'): string {
  const text = raw === null || raw === undefined ? 'NULL' : String(raw);
  if (delimiter === '\t') {
    return text.replace(/[\r\n\t]+/g, ' ');
  }
  if (/[",\r\n]/.test(text)) {
    return `"${text.replace(/"/g, '""')}"`;
  }
  return text;
}

export function formatCompareDiffsDelimited(
  result: Pick<CompareProjectsResult, 'fieldDiffs' | 'metadataDiffs'>,
  delimiter: ',' | '\t' = ','
): string {
  const rows = [...(result.fieldDiffs ?? []), ...(result.metadataDiffs ?? [])];
  const header = ['PlotNumber', 'Table', 'Key', 'Field', 'SourceValue', 'TargetValue'].join(delimiter);
  const lines = rows.map((row) =>
    [
      escapeDelimitedCell(row.plotNumber, delimiter),
      escapeDelimitedCell(row.table, delimiter),
      escapeDelimitedCell(row.key, delimiter),
      escapeDelimitedCell(row.field, delimiter),
      escapeDelimitedCell(row.sourceVal, delimiter),
      escapeDelimitedCell(row.targetVal, delimiter),
    ].join(delimiter)
  );
  return [header, ...lines].join('\n');
}

export const FALLBACK_PROJECT_METADATA_PRESETS: ProjectMetadataPreset[] = [
  {
    id: 'LMH25_2023_FS882',
    label: 'LMH25 (2023) Standard FS882',
    description: 'B.C. Ministry of Forests LMH 25 (2nd Ed., 2023) full ecosystem field form (NAD83).',
    ecosysCollectionStandard: 'LMH25',
    vegCoverMethod: 'Percent',
    plotMethod: '20x20',
    datum: 'NAD83',
    coverDescriptions: {},
  },
  {
    id: 'LMH25_FS1333_SIVI',
    label: 'LMH25 FS1333 SIVI Ground',
    description: 'LMH 25 FS1333 Site Inspection and Vegetation Inventory rapid ground protocol (NAD83).',
    ecosysCollectionStandard: 'LMH25',
    vegCoverMethod: 'Percent',
    plotMethod: '20x20',
    datum: 'NAD83',
    coverDescriptions: {},
  },
  {
    id: 'DEIF_1980',
    label: 'DEIF 1980 Historical',
    description: 'Describing Ecosystems in the Field (1980) historical BEC standard normalized to NAD83.',
    ecosysCollectionStandard: 'DEIF 1980',
    vegCoverMethod: 'Percent',
    plotMethod: '20x20',
    datum: 'NAD83',
    coverDescriptions: {},
  },
  {
    id: 'CHARS_Arctic',
    label: 'CHARS Arctic',
    description: 'CHARS tundra/subarctic standard with extended Arctic shrub covers Cover5a..5c (NAD83).',
    ecosysCollectionStandard: 'CHAR',
    vegCoverMethod: 'Percent',
    plotMethod: '20x20',
    datum: 'NAD83',
    coverDescriptions: {},
  },
];

export function triggerCompareDiffDownload(
  result: Pick<CompareProjectsResult, 'sourceProject' | 'targetProject'>,
  format: 'CSV' | 'TSV',
  text: string
): void {
  if (
    typeof document !== 'undefined' &&
    typeof Blob !== 'undefined' &&
    typeof URL !== 'undefined' &&
    typeof URL.createObjectURL === 'function'
  ) {
    const mime = format === 'TSV' ? 'text/tab-separated-values;charset=utf-8' : 'text/csv;charset=utf-8';
    const url = URL.createObjectURL(new Blob([text], { type: mime }));
    const a = document.createElement('a');
    a.href = url;
    a.download = `compare_${result.sourceProject}_vs_${result.targetProject}.${format.toLowerCase()}`;
    a.click();
    URL.revokeObjectURL(url);
  }
}

export function checkOptimizeVegApplyGate(
  preview: OptimizeVegPreview | null,
  unresolvedConflictCount: number,
  confirmReviewed: boolean
): { title: string; message: string } | null {
  if (!preview) {
    return {
      title: 'OptimizeVeg preview required',
      message: 'Run Preview OptimizeVeg before applying consolidation.',
    };
  }
  if (unresolvedConflictCount > 0) {
    return {
      title: 'OptimizeVeg conflicts unresolved',
      message: `Resolve ${unresolvedConflictCount} OptimizeVeg blocking conflict(s) (or re-run preview with Custodian Audit Override if only _Audit references remain) before committing.`,
    };
  }
  if (!confirmReviewed) {
    return {
      title: 'OptimizeVeg confirmation required',
      message: 'Check "I have reviewed conflicts and want to commit OptimizeVeg" before committing.',
    };
  }
  return null;
}

export function buildNewProjectPayload(
  projectName: string,
  projectId: string,
  projectTitle: string,
  presetId: string,
  destinationPath: string,
  activateOnSuccess: boolean
): NewProjectRequest {
  return {
    projectName,
    projectId: projectId || undefined,
    projectTitle: projectTitle || undefined,
    presetId: presetId || undefined,
    destinationPath: destinationPath || undefined,
    activateOnSuccess,
  };
}

export function buildSplinterPayload(
  splinterProject: string,
  destinationPath: string,
  useActiveSu: boolean,
  unitsRaw: string,
  plotsRaw: string,
  activateOnSuccess: boolean
): ExportSplinterRequest {
  return {
    splinterProject,
    destinationPath: destinationPath || undefined,
    useActiveSu,
    siteUnits: parseLiteralTokenList(unitsRaw),
    plotNumbers: parseLiteralTokenList(plotsRaw),
    activateOnSuccess,
  };
}

export function buildThreeWayMergeEndpoints(
  preview: ThreeWayMergePreview | null | undefined,
  fields: {
    sourcePath: string;
    sourceProject: string;
    targetPath: string;
    targetProject: string;
    basePath: string;
    baseProject: string;
    caseInsensitive: boolean;
  }
) {
  return {
    sourcePath: preview ? preview.sourcePath : fields.sourcePath.trim(),
    sourceProject: preview?.sourceProject || fields.sourceProject.trim() || undefined,
    targetPath: (preview ? preview.targetPath : fields.targetPath.trim()) || undefined,
    targetProject: preview?.targetProject || fields.targetProject.trim() || undefined,
    basePath: preview?.basePath || fields.basePath.trim() || undefined,
    baseProject: preview?.baseProject || fields.baseProject.trim() || undefined,
    caseInsensitiveText: fields.caseInsensitive || undefined,
  };
}

export function buildCompareProjectsPayload(
  sourcePath: string,
  sourceProject: string,
  targetPath: string,
  targetProject: string,
  caseInsensitive: boolean
): CompareProjectsRequest {
  return {
    sourcePath: sourcePath.trim() || undefined,
    sourceProject: sourceProject.trim() || undefined,
    targetPath: targetPath.trim(),
    targetProject: targetProject.trim() || undefined,
    caseInsensitiveText: caseInsensitive || undefined,
  };
}

export function summarizeOptimizeVegPreview(preview: OptimizeVegPreview): {
  severity: 'warning' | 'info';
  title: string;
  message: string;
} {
  const blockedCount =
    typeof preview.blockedGroupCount === 'number' && preview.blockedGroupCount > 0
      ? preview.blockedGroupCount
      : preview.hasBlockingConflicts
        ? preview.conflicts?.length || 1
        : 0;
  if (blockedCount > 0) {
    return {
      severity: 'warning',
      title: 'OptimizeVeg preview blocked by conflicts',
      message: `OptimizeVeg preview found ${blockedCount} blocked group(s) with unresolved conflicts.`,
    };
  }
  return {
    severity: 'info',
    title: 'OptimizeVeg preview ready',
    message: `OptimizeVeg preview: ${preview.duplicateSpeciesCount} multi-row species group(s) (${preview.beforeRowCount} -> ${preview.afterRowCount} rows).`,
  };
}

export function buildOptimizeVegOptions(plotNumbersRaw: string, custodianAuditOverride: boolean) {
  const plotNumbers = parseLiteralTokenList(plotNumbersRaw);
  return {
    plotNumbers: plotNumbers.length > 0 ? plotNumbers : undefined,
    custodianAuditOverride: custodianAuditOverride || undefined,
  };
}

export function buildExecuteMergePayload(
  preview: ThreeWayMergePreview,
  endpoints: ReturnType<typeof buildThreeWayMergeEndpoints>,
  defaultConflictResolution: MergeResolutionChoice,
  plotResolutions: Record<string, MergeResolutionChoice>,
  fieldResolutions: Record<string, MergeResolutionChoice>
) {
  return {
    ...endpoints,
    expectedPreviewDigest: preview.previewDigest,
    defaultConflictResolution,
    plotResolutions,
    fieldResolutions,
  };
}

export interface AdminOpOutcome {
  severity: 'success' | 'info' | 'warning';
  title: string;
  message: string;
  lifecycle?: { activated: boolean; state?: unknown };
}

export function computeNewProjIdTruncationWarning(newProjName: string, newProjId: string): string | null {
  return newProjName.trim().length > 20 && newProjId.trim() === ''
    ? `Project name exceeds 20 characters and ProjectID is blank; derived ProjectID will truncate to "${newProjName.trim().slice(0, 20)}".`
    : null;
}

export function pushAdminNotification(
  severity: 'success' | 'info' | 'warning' | 'error',
  title: string,
  message: string,
  activeProject: string,
  toast = true
): void {
  notifications[severity](title, message, {
    category: 'admin',
    source: 'Project Admin',
    contextTag: activeProject || undefined,
    toast,
  });
}

export function validateNewProjectInputs(
  projectName: string,
  projectId: string,
  projectTitle: string,
  presetId: string,
  destinationPath: string,
  activateOnSuccess: boolean
): string | null {
  if (projectName === '') return null;
  return validateNewProjectDraft(
    buildNewProjectPayload(projectName, projectId, projectTitle, presetId, destinationPath, activateOnSuccess)
  );
}

export function validateSplinterInputs(
  splinterProject: string,
  destinationPath: string,
  useActiveSu: boolean,
  unitsRaw: string,
  plotsRaw: string,
  activateOnSuccess: boolean,
  activeSu: string
): string | null {
  if (splinterProject === '') return null;
  return validateSplinterDraft(
    buildSplinterPayload(splinterProject, destinationPath, useActiveSu, unitsRaw, plotsRaw, activateOnSuccess),
    activeSu
  );
}

export function buildSaveProjectAsPayload(
  newProjectName: string,
  destinationPath: string,
  activateOnSuccess: boolean
): SaveProjectAsRequest {
  return {
    newProjectName,
    destinationPath: destinationPath || undefined,
    activateOnSuccess,
  };
}

export function describeNewProjectOutcome(res: NewProjectResult): AdminOpOutcome {
  return {
    severity: 'success',
    title: `Created project "${res.projectName}"`,
    message: `Created VPro project "${res.projectName}" at ${res.destinationPath}.`,
    lifecycle: res,
  };
}

export function describeSaveProjectAsOutcome(res: SaveProjectAsResult): AdminOpOutcome {
  return {
    severity: 'success',
    title: `Saved project as "${res.newProjectName}"`,
    message: `Saved project "${res.sourceProject}" as "${res.newProjectName}" (${res.copiedTables.length} tables).`,
    lifecycle: res,
  };
}

export function describeExportSplinterOutcome(res: ExportSplinterResult): AdminOpOutcome {
  return {
    severity: 'success',
    title: `Exported splinter "${res.splinterProject}"`,
    message: `Exported ${res.exportedPlotCount} of ${res.sourcePlotCount} plots to "${res.splinterProject}".`,
    lifecycle: res,
  };
}

export function describeComplianceOutcome(report: ComplianceValidationReport): AdminOpOutcome {
  return {
    severity: report.passed ? 'success' : 'warning',
    title: report.passed ? `Compliance passed: ${report.project}` : `Compliance issues found: ${report.project}`,
    message: report.passed
      ? `Compliance validation passed for project "${report.project}".`
      : `Compliance validation identified issues requiring review in "${report.project}".`,
  };
}

export function describeQuarantineOutcome(res: QuarantineOrphanResult): AdminOpOutcome {
  return {
    severity: 'success',
    title: 'Orphan child rows quarantined',
    message: `Quarantined ${res.totalQuarantined} orphan child row(s) into quarantine tables (batch ${res.batchId}).`,
  };
}

export function describeApplyOptimizeVegOutcome(res: OptimizeVegResult): AdminOpOutcome {
  return {
    severity: 'success',
    title: 'OptimizeVeg consolidation complete',
    message: `OptimizeVeg consolidated ${res.consolidatedGroups} group(s), removed ${res.deletedRows} duplicate row(s), and wrote ${res.auditRowsWritten} audit row(s).`,
  };
}

export function describeCompareProjectsOutcome(res: CompareProjectsResult): AdminOpOutcome {
  return {
    severity: 'info',
    title: 'Project comparison complete',
    message: `Compared ${res.sourceProject} vs ${res.targetProject}: ${res.addedCount} Added, ${res.removedCount} Removed, ${res.modifiedCount} Modified, ${res.identicalCount} Identical.`,
  };
}

export function describePreviewMergeOutcome(preview: ThreeWayMergePreview): AdminOpOutcome {
  return {
    severity: 'info',
    title: '3-Way merge preview ready',
    message: `Merge preview ready: ${preview.addedCount} Added, ${preview.fastForwardCount} Fast-Forward, ${preview.sourceDeleteCount ?? 0} Source Delete, ${preview.conflictCount} Conflict plot(s).`,
  };
}

export function describeExecuteMergeOutcome(res: ThreeWayMergeResult): AdminOpOutcome {
  return {
    severity: 'success',
    title: '3-Way merge committed',
    message: `3-Way Merge complete: ${res.addedPlots} plot(s) added, ${res.updatedPlots} plot(s) updated, ${res.auditRowsWritten} audit row(s) recorded.`,
  };
}
