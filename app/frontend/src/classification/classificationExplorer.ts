import type { CancellableRead } from '../shared/readRequests';
import {
  ClassificationService,
  ContextService,
  type BECSiteSeries,
  type DeleteUserSiteUnitRequest,
  type SaveHierarchyTableAsRequest,
  type UpsertUserSiteUnitRequest,
  type UserSiteUnitEntry,
  type UserSiteUnitImportResult,
} from '../../bindings/github.com/boostao/vpro/app';

export type ExplorerMode = 'su_tree' | 'hierarchy_tree' | 'hierarchy_flat';

export const PHYTOSOCIOLOGICAL_RANK_COLUMNS = [
  { key: 'superclass', label: 'Superclass', level: 1 },
  { key: 'class', label: 'Class', level: 2 },
  { key: 'subclass', label: 'Subclass', level: 3 },
  { key: 'order', label: 'Order', level: 4 },
  { key: 'subOrder', label: 'SubOrder', level: 5 },
  { key: 'alliance', label: 'Alliance', level: 6 },
  { key: 'subAlliance', label: 'SubAlliance', level: 7 },
  { key: 'association', label: 'Association', level: 8 },
  { key: 'subAssociation', label: 'SubAssociation', level: 9 },
  { key: 'facies', label: 'Facies', level: 10 },
  { key: 'workingUnit', label: 'WorkingUnit', level: 10 },
  { key: 'siteSeries', label: 'SiteSeries', level: 11 },
] as const;

export type PhytosociologicalRankKey = (typeof PHYTOSOCIOLOGICAL_RANK_COLUMNS)[number]['key'];

interface SUPlotLeaf {
  plotNumber: string;
  fieldNumber: string;
  zone: string;
  subZone: string;
  siteSeries: string;
  userSiteUnit: string;
  moistureRegime: string;
  nutrientRegime: string;
  elevation: number | null;
  siteUnit: string;
  presentInSu: boolean;
  inProjectEnv: boolean;
  locked: boolean;
}

interface SUUnitBucket {
  siteUnit: string;
  longName: string;
  origin: string;
  maskValid: boolean;
  plotCount: number;
  plots: SUPlotLeaf[];
}

export interface SUPlotTree {
  contextId: string;
  project: string;
  projectPath: string;
  su: string;
  suPath: string;
  units: SUUnitBucket[];
  unassignedPlots: SUPlotLeaf[];
  orphanPlots: SUPlotLeaf[];
  totalProject: number;
  totalAssigned: number;
  totalUnassigned: number;
}

interface PlotInspectorSpecies {
  species: string;
  scientificName: string;
  englishName: string;
  coverA: string;
  coverB: string;
  coverC: string;
  coverD: string;
  totalCover: number;
  totalFormatted: string;
}

export interface PlotInspectorSummary {
  contextId: string;
  plotNumber: string;
  fieldNumber: string;
  projectId: string;
  zone: string;
  subZone: string;
  siteSeries: string;
  userSiteUnit: string;
  becSiteUnit: string;
  currentSuUnit: string;
  moistureRegime: string;
  nutrientRegime: string;
  elevation: number | null;
  slope: string;
  aspect: number | null;
  latitude: number | null;
  longitude: number | null;
  topSpecies: PlotInspectorSpecies[];
}

interface BECUnitPickerRequest {
  query: string;
  zone: string;
  subZone: string;
  limit: number;
}

export interface BECUnitPickerChoice {
  siteSeries: string;
  longName: string;
  scientificName: string;
  zone: string;
  subZone: string;
  alliance?: string;
  suballiance?: string;
  source: 'master' | 'user' | 'becdb_v13';
  maskValid: boolean;
}

interface CreateSUTableRequest {
  name: string;
  destination: 'project' | 'new_file';
  filePath: string;
  populateAllProjectPlots: boolean;
  seedFromUserSiteUnit: boolean;
  activate: boolean;
}

interface SaveSUTableAsRequest {
  sourceSu: string;
  newName: string;
  destination: 'project' | 'new_file';
  filePath: string;
  activate: boolean;
}

interface SUTableLifecycleResult {
  contextId: string;
  name: string;
  tableName: string;
  filePath: string;
  plotCount: number;
  activated: boolean;
  newState?: unknown;
}

interface AssignPlotsToSiteUnitRequest {
  plotNumbers: string[];
  targetSiteUnit: string | null;
  removeFromSuWhenUnassigned: boolean;
}

interface AssignPlotsToSiteUnitResult {
  contextId: string;
  su: string;
  tableName: string;
  changedPlots: number;
  historyId: number;
}

export type SUFromEnvMode = 'overwrite' | 'fill_unassigned_only' | 'new_table';

interface CreateSUFromEnvFieldsRequest {
  fields: string[];
  separator: string;
  fieldSeparators?: string[];
  useBecSlashFormat: boolean;
  mode: SUFromEnvMode;
  targetSuName?: string;
  destination?: 'project' | 'new_file';
  filePath?: string;
  scopeToExistingSuRowsOnly: boolean;
  skipIncompleteRows: boolean;
  previewOnly: boolean;
  activate: boolean;
}

interface SUFromEnvPlotPreview {
  plotNumber: string;
  beforeSiteUnit: string;
  afterSiteUnit: string;
  action: 'insert' | 'update' | 'preserve_existing' | 'skip_blank' | 'unchanged';
}

export interface CreateSUFromEnvFieldsResult {
  contextId: string;
  mode: SUFromEnvMode;
  targetSu: string;
  tableName: string;
  filePath: string;
  previewOnly: boolean;
  insertedCount: number;
  updatedCount: number;
  preservedCount: number;
  skippedCount: number;
  unchangedCount: number;
  items: SUFromEnvPlotPreview[];
  activated: boolean;
  newState?: unknown;
}

export interface HierarchyExplorerNode {
  id: number;
  name: string;
  cleanName: string;
  parent: number | null;
  level: number;
  rankName: string;
  tag?: string;
  isBreakpoint: boolean;
  depth: number;
  children: HierarchyExplorerNode[];
}

export interface FlatHierarchyRow {
  leafId: number;
  superclass?: string;
  class: string;
  subclass?: string;
  order: string;
  subOrder: string;
  alliance: string;
  subAlliance: string;
  association: string;
  subAssociation: string;
  facies: string;
  workingUnit: string;
  siteSeries: string;
  breakpointRank?: string;
}

interface HierarchyDiagnostics {
  totalNodes: number;
  rootNodes: number;
  breakpointNodes: number;
  blankNameNodes: number;
  orphanNodes: number[];
  cycleNodeIds: number[];
}

export interface HierarchyExplorerView {
  contextId: string;
  project: string;
  hierarchy: string;
  hierarchyPath: string;
  tableName: string;
  roots: HierarchyExplorerNode[];
  flatNodes: HierarchyExplorerNode[];
  flatRankRows: FlatHierarchyRow[];
  diagnostics: HierarchyDiagnostics;
}

interface CreateHierarchyTableRequest {
  name: string;
  destination: 'project' | 'new_file';
  filePath: string;
  activate: boolean;
}

interface HierarchyTableLifecycleResult {
  contextId: string;
  name: string;
  tableName: string;
  filePath: string;
  activated: boolean;
  newState?: unknown;
}

interface HierarchyAddNodeRequest {
  name: string;
  parentId: number | null;
  level: number;
  tag?: string;
  isBreakpoint: boolean;
}

interface HierarchyRenameNodeRequest {
  nodeId: number;
  newName: string;
}

interface HierarchyReparentNodeRequest {
  nodeId: number;
  newParentId: number | null;
  newLevel?: number | null;
}

interface HierarchyDeleteNodeRequest {
  nodeId: number;
  cascadeChildren: boolean;
}

interface HierarchyMutationResult {
  contextId: string;
  hierarchy: string;
  tableName: string;
  nodeId?: number;
  nodeName?: string;
  affectedRows: number;
}

interface SaveFlatHierarchyRequest {
  rows: FlatHierarchyRow[];
}

export type {
  BECSiteSeries,
  DeleteUserSiteUnitRequest,
  SaveHierarchyTableAsRequest,
  UpsertUserSiteUnitRequest,
  UserSiteUnitEntry,
  UserSiteUnitImportResult,
};

export interface BECZoneSummary {
  zone: string;
  description: string;
}

export interface ClassificationBackendPort {
  createSUTable(contextId: string, req: CreateSUTableRequest): Promise<SUTableLifecycleResult>;
  saveSUTableAs(contextId: string, req: SaveSUTableAsRequest): Promise<SUTableLifecycleResult>;
  getSUPlotTree(contextId: string, filterText: string): CancellableRead<SUPlotTree>;
  getPlotInspectorSummary(contextId: string, plotNumber: string): CancellableRead<PlotInspectorSummary>;
  searchBECUnitPicker(contextId: string, req: BECUnitPickerRequest): CancellableRead<BECUnitPickerChoice[]>;
  searchBECSiteSeries?: (
    zone: string | null,
    subZone: string | null,
    query: string,
    limit: number
  ) => CancellableRead<BECUnitPickerChoice[]>;
  listBECZones?: () => CancellableRead<BECZoneSummary[]>;
  listUserSiteUnitList?: (contextId: string) => CancellableRead<UserSiteUnitEntry[]>;
  saveUserSiteUnitEntry?: (contextId: string, req: UpsertUserSiteUnitRequest) => Promise<UserSiteUnitEntry | null>;
  deleteUserSiteUnitEntry?: (contextId: string, req: DeleteUserSiteUnitRequest) => Promise<void>;
  exportUserSiteUnitListCSV?: (contextId: string) => Promise<string>;
  importUserSiteUnitListCSV?: (
    contextId: string,
    csvText: string,
    overwriteExisting: boolean
  ) => Promise<UserSiteUnitImportResult | null>;
  chooseNewSQLiteProjectFile?: (contextId: string, suggestedProject: string) => Promise<string>;
  assignPlotsToSiteUnit(contextId: string, req: AssignPlotsToSiteUnitRequest): Promise<AssignPlotsToSiteUnitResult>;
  undoSUAssignment(contextId: string, historyId: number): Promise<AssignPlotsToSiteUnitResult>;
  createSUFromEnvFields(contextId: string, req: CreateSUFromEnvFieldsRequest): Promise<CreateSUFromEnvFieldsResult>;
  getHierarchyExplorer(contextId: string): CancellableRead<HierarchyExplorerView>;
  createHierarchyTable(contextId: string, req: CreateHierarchyTableRequest): Promise<HierarchyTableLifecycleResult>;
  saveHierarchyTableAs?: (
    contextId: string,
    req: SaveHierarchyTableAsRequest
  ) => Promise<HierarchyTableLifecycleResult | null>;
  addHierarchyNode(contextId: string, req: HierarchyAddNodeRequest): Promise<HierarchyMutationResult>;
  renameHierarchyNode(contextId: string, req: HierarchyRenameNodeRequest): Promise<HierarchyMutationResult>;
  reparentHierarchyNode(contextId: string, req: HierarchyReparentNodeRequest): Promise<HierarchyMutationResult>;
  toggleHierarchyBreakpoint(contextId: string, nodeId: number): Promise<HierarchyMutationResult>;
  deleteHierarchyNode(contextId: string, req: HierarchyDeleteNodeRequest): Promise<HierarchyMutationResult>;
  saveFlatHierarchyRows(contextId: string, req: SaveFlatHierarchyRequest): Promise<HierarchyMutationResult>;
}

function becSiteSeriesToPickerChoice(row: BECSiteSeries): BECUnitPickerChoice {
  const code = (
    row.mergedBGC ||
    row.ssCode ||
    `${row.zone ?? ''}${row.subZone ?? ''}${row.siteSeries ? `/${row.siteSeries}` : ''}`
  ).trim();
  return {
    siteSeries: code,
    longName: (row.name || row.description || '').trim(),
    scientificName: (row.plantAssociation || '').trim(),
    zone: (row.zone || '').trim(),
    subZone: (row.subZone || '').trim(),
    alliance: row.alliance ?? undefined,
    suballiance: row.suballiance ?? undefined,
    source: 'becdb_v13',
    maskValid: isValidBECUnitMask(code),
  };
}

export const defaultClassificationBackendPort: ClassificationBackendPort = {
  createSUTable: (contextId, req) => ClassificationService.CreateSUTable(contextId, req) as never,
  saveSUTableAs: (contextId, req) => ClassificationService.SaveSUTableAs(contextId, req) as never,
  getSUPlotTree: (contextId, filterText) => ClassificationService.GetSUPlotTree(contextId, filterText) as never,
  getPlotInspectorSummary: (contextId, plotNumber) =>
    ClassificationService.GetPlotInspectorSummary(contextId, plotNumber) as never,
  searchBECUnitPicker: (contextId, req) => ClassificationService.SearchBECUnitPicker(contextId, req) as never,
  searchBECSiteSeries: (zone, subZone, query, limit) => {
    const raw = ClassificationService.SearchBECSiteSeries(zone, subZone, query, limit);
    const mapped = raw.then((rows) => (rows ?? []).map(becSiteSeriesToPickerChoice)) as CancellableRead<
      BECUnitPickerChoice[]
    >;
    mapped.cancel = () => raw.cancel();
    return mapped;
  },
  listBECZones: () => {
    const raw = ClassificationService.ListBECZones();
    const mapped = raw.then((rows) =>
      (rows ?? [])
        .map((row) => ({
          zone: (row.zone ?? '').trim(),
          description: (row.description ?? '').trim(),
        }))
        .filter((row) => row.zone !== '')
    ) as CancellableRead<BECZoneSummary[]>;
    mapped.cancel = () => raw.cancel();
    return mapped;
  },
  listUserSiteUnitList: (contextId) => ClassificationService.ListUserSiteUnitList(contextId) as never,
  saveUserSiteUnitEntry: (contextId, req) => ClassificationService.SaveUserSiteUnitEntry(contextId, req) as never,
  deleteUserSiteUnitEntry: (contextId, req) => ClassificationService.DeleteUserSiteUnitEntry(contextId, req) as never,
  exportUserSiteUnitListCSV: (contextId) => ClassificationService.ExportUserSiteUnitListCSV(contextId) as never,
  importUserSiteUnitListCSV: (contextId, csvText, overwriteExisting) =>
    ClassificationService.ImportUserSiteUnitListCSV(contextId, csvText, overwriteExisting) as never,
  chooseNewSQLiteProjectFile: (contextId, suggestedProject) =>
    ContextService.ChooseNewSQLiteProjectFile(contextId, suggestedProject) as never,
  assignPlotsToSiteUnit: (contextId, req) => ClassificationService.AssignPlotsToSiteUnit(contextId, req) as never,
  undoSUAssignment: (contextId, historyId) => ClassificationService.UndoSUAssignment(contextId, historyId) as never,
  createSUFromEnvFields: (contextId, req) => ClassificationService.CreateSUFromEnvFields(contextId, req) as never,
  getHierarchyExplorer: (contextId) => ClassificationService.GetHierarchyExplorer(contextId) as never,
  createHierarchyTable: (contextId, req) => ClassificationService.CreateHierarchyTable(contextId, req) as never,
  saveHierarchyTableAs: (contextId, req) => ClassificationService.SaveHierarchyTableAs(contextId, req) as never,
  addHierarchyNode: (contextId, req) => ClassificationService.AddHierarchyNode(contextId, req) as never,
  renameHierarchyNode: (contextId, req) => ClassificationService.RenameHierarchyNode(contextId, req) as never,
  reparentHierarchyNode: (contextId, req) => ClassificationService.ReparentHierarchyNode(contextId, req) as never,
  toggleHierarchyBreakpoint: (contextId, nodeId) =>
    ClassificationService.ToggleHierarchyBreakpoint(contextId, nodeId) as never,
  deleteHierarchyNode: (contextId, req) => ClassificationService.DeleteHierarchyNode(contextId, req) as never,
  saveFlatHierarchyRows: (contextId, req) => ClassificationService.SaveFlatHierarchyRows(contextId, req) as never,
};

const BEC_UNIT_MASK_REGEX = /^[A-Z]{2,4}[a-z]{1,3}[0-9a-z]{0,3}\/[A-Za-z0-9.\-]{1,12}$/;

export function isValidBECUnitMask(code: string): boolean {
  return BEC_UNIT_MASK_REGEX.test(code.trim());
}

export interface FlattenedSUTreeItem {
  id: string;
  kind: 'unit_folder' | 'unassigned_folder' | 'plot_leaf';
  label: string;
  subtitle: string;
  level: 1 | 2;
  parentId: string | null;
  expandable: boolean;
  expanded: boolean;
  unitCode: string | null; // null represents Unassigned bucket
  plot?: SUPlotLeaf;
  count?: number;
  maskValid?: boolean;
}

export const UNASSIGNED_BUCKET_ID = 'bucket::__unassigned__';

export function flattenVisibleSUTree(tree: SUPlotTree | null, expandedIds: ReadonlySet<string>): FlattenedSUTreeItem[] {
  if (!tree) return [];
  const items: FlattenedSUTreeItem[] = [];

  for (const bucket of tree.units) {
    const folderId = `unit::${bucket.siteUnit}`;
    const expanded = expandedIds.has(folderId);
    items.push({
      id: folderId,
      kind: 'unit_folder',
      label: bucket.siteUnit,
      subtitle: bucket.longName,
      level: 1,
      parentId: null,
      expandable: bucket.plots.length > 0,
      expanded,
      unitCode: bucket.siteUnit,
      count: bucket.plotCount,
      maskValid: bucket.maskValid,
    });
    if (expanded) {
      for (const p of bucket.plots) {
        items.push({
          id: `plot::${bucket.siteUnit}::${p.plotNumber}`,
          kind: 'plot_leaf',
          label: p.plotNumber,
          subtitle: [
            p.zone + p.subZone + (p.siteSeries ? `/${p.siteSeries}` : ''),
            p.moistureRegime ? `SMR ${p.moistureRegime}` : '',
          ]
            .filter(Boolean)
            .join(' · '),
          level: 2,
          parentId: folderId,
          expandable: false,
          expanded: false,
          unitCode: bucket.siteUnit,
          plot: p,
        });
      }
    }
  }

  const unExpanded = expandedIds.has(UNASSIGNED_BUCKET_ID);
  items.push({
    id: UNASSIGNED_BUCKET_ID,
    kind: 'unassigned_folder',
    label: 'Unassigned Plots',
    subtitle: 'Absent from SU or blank SiteUnit',
    level: 1,
    parentId: null,
    expandable: tree.unassignedPlots.length > 0,
    expanded: unExpanded,
    unitCode: null,
    count: tree.unassignedPlots.length,
  });
  if (unExpanded) {
    for (const p of tree.unassignedPlots) {
      items.push({
        id: `plot::__unassigned__::${p.plotNumber}`,
        kind: 'plot_leaf',
        label: p.plotNumber,
        subtitle: [p.zone + p.subZone + (p.siteSeries ? `/${p.siteSeries}` : ''), p.userSiteUnit]
          .filter(Boolean)
          .join(' · '),
        level: 2,
        parentId: UNASSIGNED_BUCKET_ID,
        expandable: false,
        expanded: false,
        unitCode: null,
        plot: p,
      });
    }
  }

  return items;
}

export interface FlattenedHierarchyTreeItem {
  id: string;
  nodeId: number;
  name: string;
  cleanName: string;
  parentNodeId: number | null;
  parentItemId: string | null;
  level: number;
  rankName: string;
  depth: number;
  isBreakpoint: boolean;
  expandable: boolean;
  expanded: boolean;
  childCount: number;
}

export function flattenVisibleHierarchyTree(
  roots: readonly HierarchyExplorerNode[],
  expandedNodeIds: ReadonlySet<number>
): FlattenedHierarchyTreeItem[] {
  const out: FlattenedHierarchyTreeItem[] = [];

  function walk(node: HierarchyExplorerNode, depth: number, parentItemId: string | null) {
    const itemId = `hnode::${node.id}`;
    const expandable = node.children.length > 0;
    const expanded = expandable && expandedNodeIds.has(node.id);
    out.push({
      id: itemId,
      nodeId: node.id,
      name: node.name,
      cleanName: node.cleanName,
      parentNodeId: node.parent,
      parentItemId,
      level: node.level,
      rankName: node.rankName,
      depth,
      isBreakpoint: node.isBreakpoint,
      expandable,
      expanded,
      childCount: node.children.length,
    });
    if (expanded) {
      for (const child of node.children) {
        walk(child, depth + 1, itemId);
      }
    }
  }

  for (const r of roots) {
    walk(r, 1, null);
  }
  return out;
}

interface AriaTreeAction {
  type: 'focus' | 'expand' | 'collapse' | 'select';
  targetId: string;
}

export function resolveAriaTreeKeyAction(
  items: ReadonlyArray<{
    id: string;
    parentId: string | null;
    expandable: boolean;
    expanded: boolean;
  }>,
  focusedId: string,
  key: string
): AriaTreeAction | null {
  if (items.length === 0) return null;
  const idx = items.findIndex((i) => i.id === focusedId);
  const currentIdx = idx >= 0 ? idx : 0;
  const current = items[currentIdx];

  switch (key) {
    case 'ArrowDown':
      if (currentIdx + 1 < items.length) {
        return { type: 'focus', targetId: items[currentIdx + 1].id };
      }
      return null;
    case 'ArrowUp':
      if (currentIdx - 1 >= 0) {
        return { type: 'focus', targetId: items[currentIdx - 1].id };
      }
      return null;
    case 'Home':
      return { type: 'focus', targetId: items[0].id };
    case 'End':
      return { type: 'focus', targetId: items[items.length - 1].id };
    case 'ArrowRight':
      if (current.expandable && !current.expanded) {
        return { type: 'expand', targetId: current.id };
      }
      if (current.expandable && current.expanded && currentIdx + 1 < items.length) {
        return { type: 'focus', targetId: items[currentIdx + 1].id };
      }
      return null;
    case 'ArrowLeft':
      if (current.expandable && current.expanded) {
        return { type: 'collapse', targetId: current.id };
      }
      if (current.parentId) {
        return { type: 'focus', targetId: current.parentId };
      }
      return null;
    case 'Enter':
    case ' ':
      return { type: 'select', targetId: current.id };
    default:
      return null;
  }
}

export function wouldIntroduceHierarchyCycle(
  flatNodes: ReadonlyArray<{ id: number; parent: number | null }>,
  nodeId: number,
  candidateParentId: number | null
): boolean {
  if (candidateParentId === null) return false;
  if (candidateParentId === nodeId) return true;
  const parentById = new Map<number, number | null>();
  for (const n of flatNodes) {
    parentById.set(n.id, n.parent);
  }
  const visited = new Set<number>([nodeId]);
  let curr: number | null | undefined = candidateParentId;
  while (curr !== null && curr !== undefined) {
    if (visited.has(curr)) return true;
    visited.add(curr);
    curr = parentById.get(curr) ?? null;
  }
  return false;
}

export function toggleBreakpointName(rawName: string): string {
  const trimmed = rawName.trim();
  if (trimmed.startsWith('~')) {
    return trimmed.replace(/^~+/, '').trim();
  }
  return `~${trimmed}`;
}

export function validateFlatHierarchyRows(rows: readonly FlatHierarchyRow[]): string {
  const parentByNode = new Map<string, string>();
  const rankByNode = new Map<string, string>();
  const fmtParent = (p: string) => (p === '__root__' ? 'root' : `"${p}"`);

  for (let i = 0; i < rows.length; i++) {
    const r = rows[i];
    let prev = '__root__';
    const seenInRow = new Set<string>();

    for (const col of PHYTOSOCIOLOGICAL_RANK_COLUMNS) {
      const rawName = (r[col.key] ?? '').trim();
      if (!rawName) continue;
      if (rawName.includes('\0')) {
        return `Row ${i + 1} (${col.label}) contains an invalid NUL character.`;
      }
      const hasBreak = rawName.startsWith('~');
      const cleanOrig = rawName.replace(/^~+/, '').trim();
      if (!cleanOrig) {
        return `Row ${i + 1} has an empty breakpoint node ('~').`;
      }
      const normalizedStored = hasBreak ? `~${cleanOrig}` : cleanOrig;
      if (normalizedStored.length > 255) {
        return `Row ${i + 1} (${col.label}) exceeds 255 UTF-16 code units.`;
      }
      const clean = cleanOrig.toLowerCase();
      if (seenInRow.has(clean)) {
        return `Row ${i + 1} repeats "${clean}" at multiple ranks (cycle).`;
      }
      seenInRow.add(clean);

      const existingParent = parentByNode.get(clean);
      if (existingParent !== undefined && existingParent !== prev) {
        return `Row ${i + 1} places "${clean}" under conflicting parents (${fmtParent(prev)} vs ${fmtParent(existingParent)}).`;
      }
      const existingRank = rankByNode.get(clean);
      if (existingRank !== undefined && existingRank !== col.key) {
        return `Row ${i + 1} places "${clean}" at conflicting ranks (${col.label} vs ${existingRank}).`;
      }

      parentByNode.set(clean, prev);
      rankByNode.set(clean, col.key);
      prev = clean;
    }
  }
  return '';
}

export function createEmptyFlatHierarchyRow(): FlatHierarchyRow {
  return {
    leafId: 0,
    superclass: '',
    class: '',
    subclass: '',
    order: '',
    subOrder: '',
    alliance: '',
    subAlliance: '',
    association: '',
    subAssociation: '',
    facies: '',
    workingUnit: '',
    siteSeries: '',
  };
}
