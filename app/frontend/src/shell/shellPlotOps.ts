import type {
  ContextService,
  DatasheetService,
  PlotPage,
  ProjectState,
} from '../../bindings/github.com/boostao/vpro/app';
import type { PlotSummary } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
import type { ProfileNavigation } from '../classification/projectPlotProfileReview';
import type { ReadRequests } from '../shared/readRequests';
import type { EditorCloseState } from './closeLifecycle';
import type { BuildCommandPaletteInput } from './commandPalette';
import { notifications } from './notificationService.svelte';

export type ShellViewId =
  | 'home'
  | 'plots'
  | 'geospatial-map'
  | 'diagnostic-synthesis'
  | 'r-sidecar'
  | 'hierarchy'
  | 'fs882'
  | 'datasheet'
  | 'classification-explorer'
  | 'project-admin'
  | 'lump-editor'
  | 'interchange-hub'
  | 'long-environment'
  | 'summary-environment'
  | 'long-vegetation'
  | 'summary-vegetation'
  | 'lifeform-summary'
  | 'subzone-matrix'
  | 'table-csv'
  | 'user-log'
  | 'plot-locations'
  | 'google-earth-review'
  | 'picture-manager'
  | 'plot-label-preview';

export interface DiagnosticsDraftContext {
  plotNumber: string;
  header: Record<string, unknown> | null;
  humus: Record<string, unknown>[];
  mineral: Record<string, unknown>[];
}

export interface FS882EditorHandle {
  getCloseState: () => EditorCloseState;
  saveForClose: () => Promise<boolean>;
  canOpenProjectMetadata: () => boolean;
  openProjectMetadata: () => void;
  canOpenMetadataInPlace?: () => boolean;
  applyDiagnosticHumusThickness?: (value: number) => void;
  applyDiagnosticSMR?: (smrCode: string) => void;
  applyDiagnosticSNR?: (snrCode: string) => void;
}

export interface CreatedSiviPlotEntry {
  requestId: string;
  plotNumber: string;
  canUndo: boolean;
}

export function extractDatasheetPlotSummaries(
  dsPage: Awaited<ReturnType<typeof DatasheetService.GetDatasheetPage>>
): PlotSummary[] {
  if (!dsPage?.columns || !dsPage?.rows) return [];
  const colIdx = new Map<string, number>();
  dsPage.columns.forEach((col, idx) => colIdx.set(col.name.toLowerCase(), idx));
  const cellStr = (
    cells: Array<{ text: string | null; integer: string | null; real: number | null }> | null | undefined,
    name: string
  ): string | null => {
    const idx = colIdx.get(name.toLowerCase());
    if (idx === undefined || !cells || !cells[idx]) return null;
    const c = cells[idx];
    if (c.text !== null && c.text !== undefined) return c.text;
    if (c.integer !== null && c.integer !== undefined) return String(c.integer);
    if (c.real !== null && c.real !== undefined) return String(c.real);
    return null;
  };
  const out: PlotSummary[] = [];
  for (const row of dsPage.rows) {
    const pn = cellStr(row.cells, 'plotnumber');
    if (!pn) continue;
    out.push({
      plotNumber: pn,
      fieldNumber: cellStr(row.cells, 'fieldnumber'),
      plotRepresenting: cellStr(row.cells, 'plotrepresenting'),
      zone: cellStr(row.cells, 'zone'),
      subZone: cellStr(row.cells, 'subzone'),
      siteSeries: cellStr(row.cells, 'siteseries'),
    });
  }
  return out;
}

export async function collectAllProjectPlotNumbers(
  contextId: string,
  datasheetService: Pick<typeof DatasheetService, 'GetDatasheetPage'> | undefined,
  fallbackPlots: PlotSummary[]
): Promise<string[]> {
  if (typeof datasheetService?.GetDatasheetPage === 'function') {
    const plotNums: string[] = [];
    for (let nextOff = 0; ; nextOff += 1000) {
      const dsPage = await datasheetService.GetDatasheetPage(contextId, {
        tableKey: 'Env',
        offset: nextOff,
        limit: 1000,
        sort: null,
        filters: null,
        globalSearch: '',
        scopeToActiveSU: false,
      });
      const summaries = extractDatasheetPlotSummaries(dsPage);
      if (summaries.length === 0) break;
      for (const s of summaries) plotNums.push(s.plotNumber);
      if (summaries.length < 1000 || plotNums.length >= (dsPage?.totalRows ?? 0)) break;
    }
    if (plotNums.length > 0) return plotNums;
  }
  return fallbackPlots.map((p) => p.plotNumber);
}

export function mergeAvailablePlots(
  profileNavigation: ProfileNavigation | null,
  scopedRows: PlotSummary[],
  pageRows: PlotSummary[],
  dynamicRows: PlotSummary[]
): PlotSummary[] {
  if (profileNavigation) return profileNavigation.plots;
  const merged = new Map<string, PlotSummary>();
  for (const row of scopedRows) {
    if (row?.plotNumber) merged.set(row.plotNumber, row);
  }
  for (const row of pageRows) {
    if (row?.plotNumber && !merged.has(row.plotNumber)) merged.set(row.plotNumber, row);
  }
  for (const row of dynamicRows) {
    if (row?.plotNumber && !merged.has(row.plotNumber)) merged.set(row.plotNumber, row);
  }
  return merged.size > 0 ? Array.from(merged.values()) : pageRows;
}

export function buildShellCommandCatalogInput(params: {
  allAvailablePlots: PlotSummary[];
  state: ProjectState | null;
  selectedPlotNumber: string | null;
  metadataAvailable: boolean;
  newSiviAvailable: boolean;
}): BuildCommandPaletteInput {
  const { allAvailablePlots, state, selectedPlotNumber, metadataAvailable, newSiviAvailable } = params;
  return {
    plots: allAvailablePlots.map((p) => ({
      plotNumber: p.plotNumber,
      siteUnit: p.siteSeries,
      zone: p.zone,
      subZone: p.subZone,
      location: p.plotRepresenting,
    })),
    projects: (state?.projects ?? []).map((p) => ({
      name: p.name,
      path: p.path,
      file: p.file,
      version: p.version,
      compatible: p.compatible,
      active: p.name === state?.activeProject && p.path === state?.projectPath,
    })),
    sus: (state?.sus ?? []).map((s, index) => ({
      index,
      name: s.name,
      path: s.path,
      kind: s.kind,
      compatible: s.compatible,
      active: s.name === state?.activeSU && s.path === state?.suPath,
    })),
    selectedPlotNumber,
    activeSU: state?.activeSU ?? 'None',
    metadataAvailable,
    siviAvailable: true,
    newSiviAvailable,
  };
}

export async function runScopedPlotCatalogRefresh(params: {
  expectedContextId: string;
  currentPage: PlotPage | null;
  offset: number;
  force: boolean;
  scopedCatalogKey: string;
  hasCatalogRows: boolean;
  profileNavigation: ProfileNavigation | null;
  getState: () => ProjectState | null;
  nextRequestId: () => number;
  isCurrentRequest: (reqId: number) => boolean;
  catalogPlotReads: ReadRequests;
  contextService: Pick<typeof ContextService, 'ListPlots' | 'ListCreatedSIVIPlots'>;
  onCreatedSiviPlots: (rows: CreatedSiviPlotEntry[]) => void;
  onCatalogResolved: (rows: PlotSummary[], key: string) => void;
}): Promise<void> {
  const SCOPED_PLOT_CATALOG_CAP = 2000;
  const SCOPED_PLOT_CHUNK_SIZE = 200;
  const {
    expectedContextId,
    currentPage,
    offset,
    force,
    scopedCatalogKey,
    hasCatalogRows,
    profileNavigation,
    getState,
    nextRequestId,
    isCurrentRequest,
    catalogPlotReads,
    contextService,
    onCreatedSiviPlots,
    onCatalogResolved,
  } = params;
  if (
    !expectedContextId ||
    !currentPage ||
    typeof currentPage.total !== 'number' ||
    !Array.isArray(currentPage.plots)
  ) {
    return;
  }
  if (typeof contextService?.ListPlots !== 'function') return;
  const state = getState();
  const navKey = profileNavigation
    ? `profile:${profileNavigation.contextId}:${profileNavigation.plots.length}`
    : 'default';
  const nextKey = `${expectedContextId}|${state?.activeProject ?? ''}|${state?.activeSU ?? ''}|${currentPage.total}|${navKey}`;
  if (!force && nextKey === scopedCatalogKey && hasCatalogRows) return;
  const current = nextRequestId();
  catalogPlotReads.cancelAll();
  try {
    if (typeof contextService.ListCreatedSIVIPlots === 'function') {
      try {
        const created = await catalogPlotReads.track(contextService.ListCreatedSIVIPlots(expectedContextId));
        if (!isCurrentRequest(current) || getState()?.contextId !== expectedContextId) return;
        onCreatedSiviPlots(
          (created ?? []).map((entry) => ({
            requestId: entry.requestId,
            plotNumber: entry.plotNumber,
            canUndo: Boolean(entry.canUndo && !entry.undone),
          }))
        );
      } catch {
        if (isCurrentRequest(current)) onCreatedSiviPlots([]);
      }
    }
    if (profileNavigation && profileNavigation.contextId === expectedContextId) {
      onCatalogResolved(profileNavigation.plots, nextKey);
      return;
    }
    const total = currentPage.total;
    if (total <= currentPage.plots.length && offset === 0) {
      onCatalogResolved(currentPage.plots, nextKey);
      return;
    }
    const targetCount = Math.min(total, SCOPED_PLOT_CATALOG_CAP);
    const collected: PlotSummary[] = [];
    for (let nextOff = 0; nextOff < targetCount; nextOff += SCOPED_PLOT_CHUNK_SIZE) {
      const limit = Math.min(SCOPED_PLOT_CHUNK_SIZE, targetCount - nextOff);
      const chunk = await catalogPlotReads.track(contextService.ListPlots(nextOff, limit));
      if (!isCurrentRequest(current) || getState()?.contextId !== expectedContextId) return;
      if (!chunk || !Array.isArray(chunk.plots) || chunk.plots.length === 0) break;
      collected.push(...chunk.plots);
      if (chunk.plots.length < limit) break;
    }
    if (isCurrentRequest(current) && getState()?.contextId === expectedContextId) {
      onCatalogResolved(collected, nextKey);
    }
  } catch {
    // Keep current page rows available if background catalog pagination cancels
  }
}

export async function runCopyPlotToNewNumber(params: {
  sourcePlot: string;
  rawTargetPlot: string;
  isBusy: boolean;
  hasUnsavedEdits: boolean;
  contextId: string | undefined;
  allAvailablePlots: PlotSummary[];
  contextService: Pick<
    typeof ContextService,
    | 'GetPlot'
    | 'ListVegRecords'
    | 'ListHumusRecords'
    | 'ListMineralRecords'
    | 'ListOtherRecords'
    | 'CreatePlot'
    | 'SaveVegRecord'
    | 'SaveHumusRecord'
    | 'SaveMineralRecord'
    | 'SaveOtherRecord'
  >;
  reloadAndSelect: (targetPlot: string, fallbackSummary: PlotSummary) => Promise<void>;
  notify?: typeof notifications;
}): Promise<void> {
  const {
    sourcePlot,
    rawTargetPlot,
    isBusy,
    hasUnsavedEdits,
    contextId,
    allAvailablePlots,
    contextService,
    reloadAndSelect,
    notify = notifications,
  } = params;
  if (isBusy) throw new Error('Wait for the current operation to finish first.');
  if (hasUnsavedEdits) throw new Error('Save or undo unsaved edits before copying a plot.');
  if (!contextId) throw new Error('Open a project before copying a plot.');
  const targetPlot = rawTargetPlot.trim();
  if (!targetPlot || targetPlot.length > 7 || targetPlot.includes('\u0000')) {
    throw new Error('Plot Number must be 1 to 7 characters.');
  }
  if (targetPlot === sourcePlot) {
    throw new Error('Enter a Plot Number different from the current plot.');
  }
  if (allAvailablePlots.some((p) => p.plotNumber === targetPlot)) {
    throw new Error(`Plot ${targetPlot} already exists in this project.`);
  }
  const header = await contextService.GetPlot(contextId, sourcePlot);
  if (!header) throw new Error(`Plot ${sourcePlot} could not be read.`);
  const [vegRows, humusRows, mineralRows, otherRows] = await Promise.all([
    contextService.ListVegRecords(contextId, sourcePlot),
    contextService.ListHumusRecords(contextId, sourcePlot),
    contextService.ListMineralRecords(contextId, sourcePlot),
    contextService.ListOtherRecords(contextId, sourcePlot),
  ]);
  await contextService.CreatePlot(contextId, { ...header, plotNumber: targetPlot, locked: false });
  for (const row of vegRows ?? []) {
    await contextService.SaveVegRecord(contextId, { ...row, id: 0, plotNumber: targetPlot });
  }
  for (const row of humusRows ?? []) {
    await contextService.SaveHumusRecord(contextId, { ...row, id: 0, plotNumber: targetPlot });
  }
  for (const row of mineralRows ?? []) {
    await contextService.SaveMineralRecord(contextId, { ...row, id: 0, plotNumber: targetPlot });
  }
  for (const row of otherRows ?? []) {
    await contextService.SaveOtherRecord(contextId, { ...row, id: 0, plotNumber: targetPlot });
  }
  const copiedSummary: PlotSummary = {
    plotNumber: targetPlot,
    fieldNumber: header.fieldNo ?? null,
    plotRepresenting: header.plotRepresenting ?? null,
    zone: header.zone ?? null,
    subZone: header.subZone ?? null,
    siteSeries: header.siteSeries ?? null,
  };
  await reloadAndSelect(targetPlot, copiedSummary);
  notify.success?.(
    `Copied plot ${sourcePlot} to ${targetPlot}`,
    'Site, vegetation, soil, and auxiliary rows were copied to the new Plot Number.',
    { category: 'entry', source: 'Plots', contextTag: `Plot ${targetPlot}` }
  );
}

export async function runRemovePlotFromProject(params: {
  sourcePlot: string;
  rawCleanProjectName: string;
  isBusy: boolean;
  hasUnsavedEdits: boolean;
  contextId: string | undefined;
  createdSiviPlots: CreatedSiviPlotEntry[];
  allAvailablePlots: PlotSummary[];
  contextService: Pick<typeof ContextService, 'UndoCreateSIVIPlot' | 'ExportSplinterProject'>;
  datasheetService: Pick<typeof DatasheetService, 'GetDatasheetPage'> | undefined;
  onUndoneSivi: (sourcePlot: string) => Promise<void>;
  onSplinterSwitched: (result: Awaited<ReturnType<typeof ContextService.ExportSplinterProject>>) => Promise<void>;
  notify?: typeof notifications;
}): Promise<void> {
  const {
    sourcePlot,
    rawCleanProjectName,
    isBusy,
    hasUnsavedEdits,
    contextId,
    createdSiviPlots,
    allAvailablePlots,
    contextService,
    datasheetService,
    onUndoneSivi,
    onSplinterSwitched,
    notify = notifications,
  } = params;
  if (isBusy) throw new Error('Wait for the current operation to finish first.');
  if (hasUnsavedEdits) throw new Error('Save or undo unsaved edits before removing a plot.');
  if (!contextId) throw new Error('Open a project before removing a plot.');
  const undoable = createdSiviPlots.find((entry) => entry.plotNumber === sourcePlot && entry.canUndo);
  if (undoable) {
    await contextService.UndoCreateSIVIPlot(contextId, {
      creationRequestId: undoable.requestId,
      plotNumber: sourcePlot,
    });
    await onUndoneSivi(sourcePlot);
    notify.success?.(`Deleted plot ${sourcePlot}`, 'Removed the newly created SIVI plot.', {
      category: 'entry',
      source: 'Plots',
    });
    return;
  }
  const cleanProject = rawCleanProjectName.trim();
  if (!cleanProject || !/^[A-Za-z][A-Za-z0-9_]{0,29}$/.test(cleanProject)) {
    throw new Error(
      'Clean project name must start with a letter and use only letters, numbers, or underscores (up to 30 characters).'
    );
  }
  const allPlotNumbers = await collectAllProjectPlotNumbers(contextId, datasheetService, allAvailablePlots);
  const remainingPlots = allPlotNumbers.filter((pn) => pn !== sourcePlot);
  if (remainingPlots.length === 0) {
    throw new Error(
      'Cannot save a clean project copy when this is the only plot in the project. Create a blank project in Project Admin instead.'
    );
  }
  const result = await contextService.ExportSplinterProject(contextId, {
    splinterProject: cleanProject,
    useActiveSu: false,
    plotNumbers: remainingPlots,
    activateOnSuccess: true,
  });
  await onSplinterSwitched(result);
  notify.success?.(
    `Switched to ${result.splinterProject}`,
    `Saved ${result.exportedPlotCount} plots without plot ${sourcePlot}. Original project file was preserved.`,
    { category: 'general', source: 'Plots' }
  );
}
