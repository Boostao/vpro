import { Dialogs, Events } from '@wailsio/runtime';
import { ImportExportService } from '../../bindings/github.com/boostao/vpro/app';
import { formatError, trackIfCancellable, type ReadRequests } from '../shared/readRequests';

const ACCESS_IMPORT_PROGRESS_EVENT = 'vpro:access-import-progress';

export interface AccessImportProgressPayload {
  contextId?: string;
  operation?: string;
  phase?: string;
  sourceTable?: string;
  targetTable?: string;
  tableIndex?: number;
  tableRowsProcessed?: number;
  tableRowsImported?: number;
  totalRowsProcessed?: number;
  message?: string;
}

export function subscribeWailsAccessImportProgress(
  handler: (progress: AccessImportProgressPayload) => void
): () => void {
  if (typeof Events?.On !== 'function') {
    return () => {};
  }
  return Events.On(ACCESS_IMPORT_PROGRESS_EVENT, (ev: { data?: unknown }) => {
    handler((ev?.data ?? null) as AccessImportProgressPayload);
  });
}

export interface FileDialogFilter {
  DisplayName: string;
  Pattern: string;
}

interface VenusProjectCandidate {
  projectId: string;
  projectName: string;
  suggestedTarget: string;
  suggestedDestPath: string;
  plotCount: number;
  vegObsCount: number;
  humusRowCount: number;
  mineralRowCount: number;
}

export interface VenusSourceInspection {
  sourcePath: string;
  sourceFormat: string;
  venusVersion: string;
  sourceSha256: string;
  projects: VenusProjectCandidate[];
}

interface VenusImportRequest {
  sourcePath: string;
  sourceProject?: string;
  targetProject: string;
  destinationPath?: string;
  activateOnSuccess: boolean;
}

export interface VenusImportResult {
  sourcePath: string;
  sourceFormat: string;
  venusVersion: string;
  sourceProject: string;
  targetProject: string;
  destinationPath: string;
  destinationSha256: string;
  plotCount: number;
  vegRowCount: number;
  humusRowCount: number;
  mineralRowCount: number;
  activated: boolean;
  state?: Record<string, unknown> | null;
}

interface TurboVegExportRequest {
  format: 'xml' | 'sqlite';
  destinationPath: string;
  lumpTable?: string;
  lumpDbPath?: string;
}

export interface TurboVegExportOutcome {
  format: string;
  path: string;
  sha256: string;
  plotCount: number;
  speciesCount: number;
  observationCount: number;
}

interface TurboVegImportRequest {
  sourcePath: string;
  format?: 'xml' | 'sqlite' | '';
  targetProject: string;
  destinationPath?: string;
  activateOnSuccess: boolean;
  resolveVProCodeSynonyms?: boolean;
}

export interface TurboVegImportOutcome {
  sourcePath: string;
  format: string;
  targetProject: string;
  destinationPath: string;
  destinationSha256: string;
  plotCount: number;
  speciesCount: number;
  observationCount: number;
  activated: boolean;
  state?: Record<string, unknown> | null;
}

interface UserSpeciesRecord {
  code: string;
  scientificName: string | null;
  lifeForm: number | null;
  englishName: string | null;
  report?: number | null;
  sppNumber?: number | null;
  codetype?: string | null;
}

interface UserSpeciesExportRequest {
  format: 'json' | 'csv';
  destinationPath?: string;
}

export interface UserSpeciesExportResult {
  format: string;
  rowCount: number;
  path?: string;
  fileSha256: string;
  payloadSha256: string;
  content: string;
  species: UserSpeciesRecord[];
}

export type UserSpeciesCollisionPolicy = 'skip' | 'overwrite';

interface UserSpeciesImportRequest {
  sourcePath?: string;
  format?: 'json' | 'csv' | '';
  content?: string;
  collisionPolicy: UserSpeciesCollisionPolicy;
}

interface UserSpeciesImportItemReview {
  code: string;
  scientificName: string;
  lifeForm?: number | null;
  status: 'new' | 'collision_user' | 'collision_master';
  action: 'insert' | 'overwrite' | 'skip';
  reason?: string;
}

export interface UserSpeciesImportPreview {
  totalRows: number;
  newCount: number;
  userCollisions: number;
  masterCollisions: number;
  payloadSha256: string;
  items: UserSpeciesImportItemReview[];
}

export interface UserSpeciesImportResult {
  preview: UserSpeciesImportPreview;
  insertedCount: number;
  overwrittenCount: number;
  skippedCount: number;
}

interface LongTidyCSVRequest {
  destinationPath?: string;
  lumpTable?: string;
  lumpDbPath?: string;
}

interface WideMatrixCSVRequest {
  destinationPath?: string;
  layerMode: 'rollup_all' | 'strata_4' | 'species_layer';
  zeroFill: boolean;
  includeSiteUnit: boolean;
  lumpTable?: string;
  lumpDbPath?: string;
}

export interface CSVExportOutcome {
  mode: string;
  rowCount: number;
  plotCount: number;
  speciesCount: number;
  columnCount: number;
  path?: string;
  sha256: string;
  previewCsv: string;
}

interface RDSExportRequest {
  destinationPath: string;
  lumpTable?: string;
  lumpDbPath?: string;
}

interface RDSTableSummary {
  name: string;
  rowCount: number;
  columnCount: number;
}

export interface RDSExportOutcome {
  path: string;
  sha256: string;
  byteSize: number;
  plotCount: number;
  tables: RDSTableSummary[];
}

interface GeoPackageExportRequest {
  destinationPath: string;
  crs: 'EPSG:3005' | 'EPSG:4326';
  includeAttributeTables: boolean;
  includeUnlocatedPlots: boolean;
  lumpTable?: string;
  lumpDbPath?: string;
}

export interface GeoPackageExportOutcome {
  path: string;
  sha256: string;
  crs: string;
  srsId: number;
  featureCount: number;
  locatedPlotCount: number;
  skippedUnlocatedCount: number;
  normalizedWestLongitudes: number;
  attributeTables: string[];
}

export interface LumpTableSummary {
  name: string;
  tableName: string;
  databasePath: string;
  isActiveProject: boolean;
  metadataVersion: string;
  rowCount: number;
  activeCount: number;
  distinctLumpCodes: number;
}

export interface InterchangeHubPort {
  inspectVenusSource(contextID: string, sourcePath: string): Promise<VenusSourceInspection>;
  importVenusProject(contextID: string, request: VenusImportRequest): Promise<VenusImportResult>;
  exportTurboVeg(contextID: string, request: TurboVegExportRequest): Promise<TurboVegExportOutcome>;
  importTurboVeg(contextID: string, request: TurboVegImportRequest): Promise<TurboVegImportOutcome>;
  exportUserSpeciesList(contextID: string, request: UserSpeciesExportRequest): Promise<UserSpeciesExportResult>;
  previewUserSpeciesImport(contextID: string, request: UserSpeciesImportRequest): Promise<UserSpeciesImportPreview>;
  importUserSpeciesList(contextID: string, request: UserSpeciesImportRequest): Promise<UserSpeciesImportResult>;
  exportLongTidyCSV(contextID: string, request: LongTidyCSVRequest): Promise<CSVExportOutcome>;
  exportWideMatrixCSV(contextID: string, request: WideMatrixCSVRequest): Promise<CSVExportOutcome>;
  exportProjectRDS(contextID: string, request: RDSExportRequest): Promise<RDSExportOutcome>;
  exportGeoPackage(contextID: string, request: GeoPackageExportRequest): Promise<GeoPackageExportOutcome>;
  discoverLumpTables?(contextID: string, externalPaths?: string[]): Promise<LumpTableSummary[]>;
  chooseOpenFile?(title: string, filters?: FileDialogFilter[]): Promise<string>;
  chooseSaveFile?(title: string, defaultFilename: string, filters?: FileDialogFilter[]): Promise<string>;
}

export const defaultInterchangeHubPort: InterchangeHubPort = {
  inspectVenusSource: (contextID, sourcePath) => ImportExportService.InspectVenusSource(contextID, sourcePath) as never,
  importVenusProject: (contextID, request) => ImportExportService.ImportVenusProject(contextID, request) as never,
  exportTurboVeg: (contextID, request) => ImportExportService.ExportTurboVeg(contextID, request) as never,
  importTurboVeg: (contextID, request) => ImportExportService.ImportTurboVeg(contextID, request) as never,
  exportUserSpeciesList: (contextID, request) => ImportExportService.ExportUserSpeciesList(contextID, request) as never,
  previewUserSpeciesImport: (contextID, request) =>
    ImportExportService.PreviewUserSpeciesImport(contextID, request as never) as never,
  importUserSpeciesList: (contextID, request) =>
    ImportExportService.ImportUserSpeciesList(contextID, request as never) as never,
  exportLongTidyCSV: (contextID, request) => ImportExportService.ExportLongTidyCSV(contextID, request) as never,
  exportWideMatrixCSV: (contextID, request) => ImportExportService.ExportWideMatrixCSV(contextID, request) as never,
  exportProjectRDS: (contextID, request) => ImportExportService.ExportProjectRDS(contextID, request) as never,
  exportGeoPackage: (contextID, request) => ImportExportService.ExportGeoPackage(contextID, request) as never,
  discoverLumpTables: (contextID, externalPaths = []) =>
    ImportExportService.DiscoverLumpTables(contextID, externalPaths) as never,
  chooseOpenFile: async (title, filters) => {
    const selected = await Dialogs.OpenFile({
      Title: title,
      CanChooseFiles: true,
      CanChooseDirectories: false,
      AllowsMultipleSelection: false,
      Filters: filters,
    });
    return Array.isArray(selected) ? (selected[0] ?? '') : (selected ?? '');
  },
  chooseSaveFile: async (title, defaultFilename, filters) => {
    const selected = await Dialogs.SaveFile({
      Title: title,
      Filename: defaultFilename,
      Filters: filters,
    });
    return selected ?? '';
  },
};

const PROJECT_IDENT_RE = /^[A-Za-z][A-Za-z0-9_]{0,30}$/;

export function validateTargetProjectName(raw: string): { valid: boolean; normalized: string; error: string } {
  const trimmed = (raw ?? '').trim();
  if (!trimmed) {
    return { valid: false, normalized: '', error: 'Target project name is required.' };
  }
  if (!PROJECT_IDENT_RE.test(trimmed)) {
    return {
      valid: false,
      normalized: trimmed,
      error:
        'Target project name must start with a letter and use only letters, digits, or underscores (max 31 chars).',
    };
  }
  const lower = trimmed.toLowerCase();
  if (lower === 'none' || lower === 'sample' || lower.includes('master')) {
    return {
      valid: false,
      normalized: trimmed,
      error: 'Target project name cannot be None, Sample, or contain master.',
    };
  }
  return { valid: true, normalized: trimmed, error: '' };
}

export function defaultYieldScheduler(): Promise<void> {
  if (typeof globalThis.setTimeout === 'function') {
    return new Promise((resolve) => globalThis.setTimeout(resolve, 0));
  }
  return Promise.resolve();
}

// Cooperative chunked client-side XML sanity check that yields every chunkSize characters
// so Cancel / remount / close guards can preempt large client-side XML inspection.
export async function validateXMLSnippetChunked(
  xmlText: string,
  chunkSize = 16384,
  yieldFn: () => Promise<void> = defaultYieldScheduler,
  isCancelled: () => boolean = () => false
): Promise<{ valid: boolean; plotTagCount: number; error: string }> {
  if (!xmlText || !xmlText.trim()) {
    return { valid: false, plotTagCount: 0, error: 'XML content is empty.' };
  }
  const step = Math.max(1, chunkSize);
  let plotTagCount = 0;
  let offset = 0;
  while (offset < xmlText.length) {
    if (isCancelled()) {
      throw new Error('XML validation cancelled');
    }
    const end = Math.min(xmlText.length, offset + step);
    let i = offset;
    for (; i < end; i++) {
      const code = xmlText.charCodeAt(i);
      if (code === 0) {
        return { valid: false, plotTagCount: 0, error: 'XML contains NUL byte.' };
      }
      if (code >= 0xd800 && code <= 0xdbff) {
        if (i + 1 < xmlText.length) {
          const low = xmlText.charCodeAt(i + 1);
          if (low < 0xdc00 || low > 0xdfff) {
            return { valid: false, plotTagCount: 0, error: 'XML contains unpaired UTF-16 high surrogate.' };
          }
          i++;
        } else {
          return { valid: false, plotTagCount: 0, error: 'XML ends with unpaired UTF-16 high surrogate.' };
        }
      } else if (code >= 0xdc00 && code <= 0xdfff) {
        return { valid: false, plotTagCount: 0, error: 'XML contains unpaired UTF-16 low surrogate.' };
      }
      if (code === 0x3c) {
        const probe = xmlText.slice(i, Math.min(xmlText.length, i + 8));
        if (/^<Plot(?=[\s/>]|$)/i.test(probe)) {
          plotTagCount++;
        }
      }
    }
    offset = i;
    await yieldFn();
    if (isCancelled()) {
      throw new Error('XML validation cancelled');
    }
  }
  return { valid: true, plotTagCount, error: '' };
}

export function formatInterchangeError(raw: unknown): string {
  let msg = String(raw ?? '').trim();
  if (!msg) return 'An unexpected error occurred.';
  const prefixes = ['RuntimeError:', 'Error:', 'CallError:'];
  let stripped = true;
  while (stripped) {
    stripped = false;
    for (const prefix of prefixes) {
      if (msg.startsWith(prefix)) {
        msg = msg.slice(prefix.length).trim();
        stripped = true;
      }
    }
  }
  if (msg.includes('picture selection') || msg.includes('file dialogs not available in server mode')) {
    return 'File selection requires an active desktop window; enter a file path directly when running in a browser.';
  }
  if (msg.includes('database disk image is malformed') || msg.includes('file is not a database')) {
    return 'The selected database file is damaged, incomplete, or not a valid SQLite file.';
  }
  if (
    msg.includes('Access source read error') ||
    msg.includes('cannot read Access catalog') ||
    msg.includes('cannot reopen Access database')
  ) {
    return 'The selected Access file could not be read. It may be incomplete, damaged, or in an unsupported format.';
  }
  const xmlLine = /XML syntax error on line (\d+)/i.exec(msg);
  if (xmlLine) {
    return `The selected XML file is incomplete or contains invalid XML formatting on line ${xmlLine[1]}.`;
  }
  if (msg.includes('XML syntax error') || msg.includes('unexpected EOF')) {
    return 'The selected file ended unexpectedly or contains invalid formatting.';
  }
  if (
    /\b(?:lstat|stat|open|CreateFile|GetFileAttributesEx)\b[^:]*:\s*(?:no such file or directory|cannot find the file)/i.test(
      msg
    )
  ) {
    return 'The selected file or folder was not found. Check the path and try again.';
  }
  if (
    /\b(?:lstat|stat|open|CreateFile|GetFileAttributesEx)\b[^:]*:\s*(?:permission denied|access is denied)/i.test(msg)
  ) {
    return 'VPro does not have permission to read or write the selected file path.';
  }
  msg = msg.replace(/\b(?:lstat|stat|open|CreateFile|GetFileAttributesEx)\s+[^:]+:\s*/gi, '');
  msg = msg.replace(/:\s*sql:\s*no rows in result set/gi, '');
  msg = msg.replace(/\bsql:\s*no rows in result set\b/gi, 'the requested table or record was not found');
  return msg.trim() || 'An unexpected error occurred.';
}

export const TURBOVEG_LAYER_CROSSWALK: ReadonlyArray<{
  vproLayers: string;
  tvGroup: string;
  description: string;
}> = [
  {
    vproLayers: 'Cover1..Cover3, TotalA',
    tvGroup: '1..3 = t1..t3 (Tree)',
    description: 'Dominant (A1), main canopy (A2), sub-canopy (A3); TotalA via VPRO_LAYER UDF',
  },
  {
    vproLayers: 'Cover4..Cover5c, TotalB',
    tvGroup: '4..5 = s1..s2 (Shrub)',
    description: 'Tall (B1) & low (B2) shrubs; CHARS 5a..5c & TotalB via VPRO_LAYER UDF',
  },
  {
    vproLayers: 'Cover6',
    tvGroup: '6 = hl (Herb)',
    description: 'Herbaceous layer (C); untagged external 7=jl non-woody & 8=sl seedlings',
  },
  {
    vproLayers: 'Cover5 (woody) / Cover6',
    tvGroup: '7..8 = jl, sl (Juvenile)',
    description: 'External Turboveg juvenile woody -> Cover5; non-woody & seedlings -> Cover6',
  },
  {
    vproLayers: 'Cover7..Cover9',
    tvGroup: '9 = ml (Cryptogam)',
    description: 'Terrestrial (D), epixylic (Dw), and epilithic (Dr) bryoids/lichens via VPRO_LAYER UDF',
  },
  { vproLayers: 'Cover10', tvGroup: '10 = ep (Epiphyte)', description: 'Arboreal lichens and epiphytes (Ep)' },
];

export function lumpDbBaseName(dbPath: string): string {
  const normalized = (dbPath ?? '').replaceAll('\\', '/');
  const idx = normalized.lastIndexOf('/');
  return idx >= 0 ? normalized.slice(idx + 1) : normalized;
}

export function computeLumpOptionValue(item: LumpTableSummary, list: readonly LumpTableSummary[]): string {
  const dupes = list.filter((other) => other.tableName.toLowerCase() === item.tableName.toLowerCase()).length;
  return dupes <= 1 || item.isActiveProject ? item.tableName : `${item.tableName}@${item.databasePath}`;
}

export function buildLumpOptionLabel(item: LumpTableSummary): string {
  const rules = `${item.activeCount} active rule${item.activeCount === 1 ? '' : 's'}`;
  return item.isActiveProject
    ? `${item.tableName} (${rules})`
    : `${item.tableName} (${lumpDbBaseName(item.databasePath)} · ${rules})`;
}

export function findSelectedLumpOptionKey(
  discovered: readonly LumpTableSummary[],
  tableName: string,
  dbPath: string
): string {
  const trimmedTable = (tableName ?? '').trim();
  if (!trimmedTable) return '';
  const trimmedDb = (dbPath ?? '').trim();
  const match =
    discovered.find(
      (item) =>
        item.tableName.toLowerCase() === trimmedTable.toLowerCase() &&
        (!trimmedDb ? item.isActiveProject : item.databasePath === trimmedDb)
    ) ?? discovered.find((item) => item.tableName.toLowerCase() === trimmedTable.toLowerCase());
  return match ? computeLumpOptionValue(match, discovered) : trimmedTable;
}

export function resolveLumpOptionChoice(
  discovered: readonly LumpTableSummary[],
  optionValue: string
): { tableName: string; dbPath: string } {
  const raw = (optionValue ?? '').trim();
  const chosen = raw ? (discovered.find((item) => computeLumpOptionValue(item, discovered) === raw) ?? null) : null;
  return {
    tableName: chosen ? chosen.tableName : '',
    dbPath: chosen && !chosen.isActiveProject ? chosen.databasePath : '',
  };
}

function isLumpSelectionStillValid(discovered: readonly LumpTableSummary[], curTable: string, curDb: string): boolean {
  return discovered.some(
    (item) => item.tableName.toLowerCase() === curTable.toLowerCase() && (!curDb || item.databasePath === curDb)
  );
}

export function invalidLumpTargets(
  discovered: readonly LumpTableSummary[],
  tvTable: string,
  tvDb: string,
  csvTable: string,
  csvDb: string,
  gpkgTable: string,
  gpkgDb: string
): Array<'tv' | 'csv' | 'gpkg'> {
  const out: Array<'tv' | 'csv' | 'gpkg'> = [];
  if (tvTable && !isLumpSelectionStillValid(discovered, tvTable, tvDb)) out.push('tv');
  if (csvTable && !isLumpSelectionStillValid(discovered, csvTable, csvDb)) out.push('csv');
  if (gpkgTable && !isLumpSelectionStillValid(discovered, gpkgTable, gpkgDb)) out.push('gpkg');
  return out;
}

export async function refreshDiscoveredLumpTablesOp(
  ownerContextId: string,
  extraPaths: string[],
  port: InterchangeHubPort | undefined,
  reads: ReadRequests | undefined,
  bumpGen: () => number,
  isCurrent: (reqId: number) => boolean,
  onLoaded: (items: LumpTableSummary[]) => void
): Promise<void> {
  if (!ownerContextId) {
    onLoaded([]);
    return;
  }
  const discoverFn =
    typeof port?.discoverLumpTables === 'function'
      ? port.discoverLumpTables.bind(port)
      : port === defaultInterchangeHubPort && typeof defaultInterchangeHubPort.discoverLumpTables === 'function'
        ? defaultInterchangeHubPort.discoverLumpTables
        : null;
  if (!discoverFn) return;
  const reqId = bumpGen();
  try {
    const rawRpc = discoverFn(ownerContextId, [...extraPaths]);
    const tracked = reads ? trackIfCancellable(reads, rawRpc) : rawRpc;
    const items = (await tracked) ?? [];
    if (!isCurrent(reqId)) return;
    onLoaded(Array.isArray(items) ? items : []);
  } catch {
    if (isCurrent(reqId)) onLoaded([]);
  }
}

export async function pickInterchangeFilePath(
  mode: 'open' | 'save',
  title: string,
  defaultFilename: string,
  filters: FileDialogFilter[],
  busyOrHeld: boolean,
  isSameOwner: () => boolean,
  port: InterchangeHubPort,
  clearError: () => void,
  onError: (title: string, msg: string) => void,
  assign: (chosen: string) => void | Promise<void>
): Promise<void> {
  if (busyOrHeld) return;
  clearError();
  try {
    const chosen =
      mode === 'open'
        ? await (port.chooseOpenFile ?? defaultInterchangeHubPort.chooseOpenFile)?.(title, filters)
        : await (port.chooseSaveFile ?? defaultInterchangeHubPort.chooseSaveFile)?.(title, defaultFilename, filters);
    if (isSameOwner() && typeof chosen === 'string' && chosen.trim()) {
      await assign(chosen.trim());
    }
  } catch (cause) {
    onError('File picker failed', formatError(cause));
  }
}

export async function validateInterchangeXmlSnippet(
  xmlText: string,
  busyOrHeld: boolean,
  bumpGen: () => number,
  isCancelled: (reqGen: number) => boolean,
  onDone: (reqGen: number) => void,
  setBusy: (next: boolean) => void,
  clearError: () => void,
  yieldScheduler: () => Promise<void>,
  onError: (title: string, msg: string) => void
): Promise<number | null> {
  if (busyOrHeld) return null;
  const reqGen = bumpGen();
  clearError();
  setBusy(true);
  try {
    const check = await validateXMLSnippetChunked(xmlText, 8192, yieldScheduler, () => isCancelled(reqGen));
    if (isCancelled(reqGen)) return null;
    if (!check.valid) {
      onError('TurboVeg XML validation failed', check.error);
      return null;
    }
    return check.plotTagCount;
  } catch (cause) {
    if (!isCancelled(reqGen) && !(cause instanceof Error && cause.name === 'CancelError')) {
      onError('TurboVeg XML validation failed', formatError(cause));
    }
    return null;
  } finally {
    onDone(reqGen);
  }
}

export function lumpExportFields(
  lumpTable: string | undefined,
  lumpDbPath: string | undefined
): { lumpTable: string; lumpDbPath?: string } {
  const db = typeof lumpDbPath === 'string' ? lumpDbPath.trim() : '';
  return { lumpTable: (lumpTable ?? '').trim(), ...(db ? { lumpDbPath: db } : {}) };
}

export function buildVenusImportPayload(
  sourcePath: string,
  sourceProject: string,
  targetProject: string,
  destinationPath: string,
  activateOnSuccess: boolean
): VenusImportRequest {
  return {
    sourcePath: sourcePath.trim(),
    sourceProject: sourceProject.trim(),
    targetProject,
    destinationPath: destinationPath.trim(),
    activateOnSuccess,
  };
}

export function buildWideCsvPayload(
  destinationPath: string,
  layerMode: 'rollup_all' | 'strata_4' | 'species_layer',
  zeroFill: boolean,
  includeSiteUnit: boolean,
  lumpTable: string | undefined,
  lumpDbPath: string | undefined
): WideMatrixCSVRequest {
  return {
    destinationPath: destinationPath.trim(),
    layerMode,
    zeroFill,
    includeSiteUnit,
    ...lumpExportFields(lumpTable, lumpDbPath),
  };
}

export function buildGeoPackagePayload(
  destinationPath: string,
  crs: 'EPSG:3005' | 'EPSG:4326',
  includeAttributeTables: boolean,
  includeUnlocatedPlots: boolean,
  lumpTable: string | undefined,
  lumpDbPath: string | undefined
): GeoPackageExportRequest {
  return {
    destinationPath: destinationPath.trim(),
    crs,
    includeAttributeTables,
    includeUnlocatedPlots,
    ...lumpExportFields(lumpTable, lumpDbPath),
  };
}

export function trackHubCall<T>(rawRpc: Promise<T>, rpcRequests: ReadRequests | undefined): [Promise<T>, unknown] {
  const tracked = rpcRequests ? trackIfCancellable(rpcRequests, rawRpc) : rawRpc;
  return [tracked, tracked === rawRpc ? rawRpc : null];
}

export async function awaitHubCall<T>(
  tracked: Promise<T>
): Promise<{ res?: T; err: string | null; cancelled: boolean }> {
  try {
    return { res: await tracked, err: null, cancelled: false };
  } catch (cause) {
    if (cause instanceof Error && cause.name === 'CancelError') {
      return { err: null, cancelled: true };
    }
    return { err: formatError(cause), cancelled: false };
  }
}

export function onVenusImported(
  notify: { success: (title: string, msg: string, opts: { category: 'background'; source: string }) => unknown },
  res: VenusImportResult,
  onActivated: (state: Record<string, unknown>) => void
): VenusImportResult {
  notify.success(`Imported ${res.plotCount} plots into ${res.targetProject}`, `Saved to ${res.destinationPath}`, {
    category: 'background',
    source: 'Interchange · VENUS 5.0',
  });
  if (res.activated && res.state) onActivated(res.state);
  return res;
}

export function onTurboVegImported(
  notify: { success: (title: string, msg: string, opts: { category: 'background'; source: string }) => unknown },
  res: TurboVegImportOutcome,
  onActivated: (state: Record<string, unknown>) => void
): TurboVegImportOutcome {
  notify.success(`Imported ${res.plotCount} TurboVeg plot(s) into ${res.targetProject}`, res.destinationPath, {
    category: 'background',
    source: 'Interchange · TurboVeg',
  });
  if (res.activated && res.state) onActivated(res.state);
  return res;
}

export function buildTurboVegImportPayload(
  sourcePath: string,
  format: 'xml' | 'sqlite' | '',
  targetProject: string,
  destinationPath: string,
  activateOnSuccess: boolean,
  opts: { resolveVProCodeSynonyms: boolean }
): TurboVegImportRequest {
  return {
    sourcePath: sourcePath.trim(),
    format,
    targetProject,
    destinationPath: destinationPath.trim(),
    activateOnSuccess,
    resolveVProCodeSynonyms: opts.resolveVProCodeSynonyms,
  };
}

export function onTurboVegExported(
  notify: { success: (title: string, msg: string, opts: { category: 'background'; source: string }) => unknown },
  res: TurboVegExportOutcome
): TurboVegExportOutcome {
  notify.success(`Exported ${res.plotCount} TurboVeg plot(s)`, res.path, {
    category: 'background',
    source: 'Interchange · TurboVeg',
  });
  return res;
}

export function onRdsExported(
  notify: { success: (title: string, msg: string, opts: { category: 'background'; source: string }) => unknown },
  res: RDSExportOutcome
): RDSExportOutcome {
  notify.success(`Exported R .rds (${res.plotCount} plots)`, res.path, {
    category: 'background',
    source: 'Interchange · R .rds',
  });
  return res;
}

export function onGeoPackageExported(
  notify: { success: (title: string, msg: string, opts: { category: 'background'; source: string }) => unknown },
  res: GeoPackageExportOutcome
): GeoPackageExportOutcome {
  notify.success(`Exported ${res.featureCount} GeoPackage plot features (${res.crs})`, res.path, {
    category: 'background',
    source: 'Interchange · GeoPackage',
  });
  return res;
}
