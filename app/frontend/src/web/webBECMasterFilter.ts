import type { ExpressionSpecification, LayerSpecification, SourceSpecification, StyleSpecification } from 'maplibre-gl';
import type { PMTilesManifest } from '../../bindings/github.com/boostao/vpro/app';
import { triggerBrowserDownload } from './wailsWebRuntime';
import { isExportQueueBusyError } from './webMeta';

export { triggerBrowserDownload };

// Official BC Ministry of Forests BEC v13 Zone thematic palette
const WEB_BEC_ZONE_PALETTE: Readonly<Record<string, string>> = Object.freeze({
  CDF: '#a3cc51',
  CWH: '#20854e',
  MH: '#5c4d99',
  CMA: '#b8c4d0',
  IMA: '#c9d4df',
  BAFA: '#9eb0c2',
  ESSF: '#7a5299',
  ICH: '#2d9a8c',
  SBS: '#3b82b6',
  SBPS: '#6aaed6',
  MS: '#9e7bb5',
  IDF: '#d99b26',
  PP: '#e07b39',
  BG: '#c94a38',
  BWBS: '#4a90a4',
  SWB: '#6d8fa6',
});

function resolveWebPMTilesArchiveUrl(archiveName: string, pmtilesBaseUrl?: string): string {
  const cleanArchive = archiveName.replace(/^\/+/, '');
  const trimmedBase = (pmtilesBaseUrl ?? '').trim().replace(/\/+$/, '');
  if (!trimmedBase) {
    return `pmtiles:///pmtiles/${cleanArchive}`;
  }
  if (/^pmtiles:\/\//i.test(trimmedBase)) {
    return `${trimmedBase}/${cleanArchive}`;
  }
  if (/^https?:\/\//i.test(trimmedBase)) {
    return `pmtiles://${trimmedBase}/${cleanArchive}`;
  }
  const rooted = trimmedBase.startsWith('/') ? trimmedBase : `/${trimmedBase}`;
  return `pmtiles://${rooted}/${cleanArchive}`;
}

const WEB_SESSION_HEADER = 'X-VPro-Session';
const SESSION_STORAGE_KEY = 'vpro:web-session-id';
let fallbackWebSessionId = '';

function resolveWebSessionId(): string {
  try {
    if (typeof globalThis.sessionStorage !== 'undefined') {
      const existing = globalThis.sessionStorage.getItem(SESSION_STORAGE_KEY);
      if (existing && existing.trim().length > 0) return existing;
      const created =
        typeof globalThis.crypto?.randomUUID === 'function'
          ? globalThis.crypto.randomUUID()
          : `${Date.now().toString(16)}-${Math.random().toString(16).slice(2)}`;
      globalThis.sessionStorage.setItem(SESSION_STORAGE_KEY, created);
      return created;
    }
  } catch {
    // Restricted storage contexts fall back to an in-memory session ID.
  }
  if (!fallbackWebSessionId) {
    fallbackWebSessionId =
      typeof globalThis.crypto?.randomUUID === 'function'
        ? globalThis.crypto.randomUUID()
        : `${Date.now().toString(16)}-${Math.random().toString(16).slice(2)}`;
  }
  return fallbackWebSessionId;
}

export interface BECMasterCodedOption {
  code: string;
  label: string;
}

export interface BECMasterProjectOption {
  projectId: string;
  title?: string;
  plotCount?: number;
}

export interface BECMasterPublicationOption {
  id: string;
  title: string;
}

export interface BECMasterFilterOptions {
  contextId: string;
  project: string;
  totalPlots: number;
  regions: BECMasterCodedOption[];
  projects: BECMasterProjectOption[];
  projectIds: string[];
  publications: BECMasterPublicationOption[];
  hasPublicationLinks: boolean;
  zones: string[];
  subzonesByZone: Record<string, string[]>;
  minYear: number;
  maxYear: number;
  successionalStatuses: BECMasterCodedOption[];
  structuralStages: BECMasterCodedOption[];
  sitePlotQualities: BECMasterCodedOption[];
  vegPlotQualities: BECMasterCodedOption[];
  soilPlotQualities: BECMasterCodedOption[];
  locationAccuracies: BECMasterCodedOption[];
}

export type BECMasterSelectMode = 'all' | 'region' | 'project' | 'bbox';

export interface BECMasterFilterRequest {
  mode: BECMasterSelectMode;
  regions?: string[];
  projectIds?: string[];
  publicationIds?: string[];
  nwLat?: number;
  nwLon?: number;
  seLat?: number;
  seLon?: number;
  zones?: string[];
  subzones?: string[];
  minYear?: number;
  maxYear?: number;
  successionalStatuses?: string[];
  structuralStages?: string[];
  inPublicationsOnly?: boolean;
  sitePlotQualities?: string[];
  vegPlotQualities?: string[];
  soilPlotQualities?: string[];
  locationAccuracy?: string;
}

export interface BECMasterMapPoint {
  plotNumber: string;
  lat: number;
  lon: number;
  zone: string;
  subZone: string;
  siteSeries: string;
  projectId: string;
  region: string;
}

export interface BECMasterFilterResult {
  contextId: string;
  project: string;
  totalPlots: number;
  matchedCount: number;
  plotNumbers: string[];
  points: BECMasterMapPoint[];
}

export type BECMasterDownloadFormat = 'vpro64' | 'csv' | 'gpkg' | 'rds' | 'turboveg' | 'kml';

export interface BECMasterDownloadFormatOption {
  id: BECMasterDownloadFormat;
  label: string;
  extension: string;
  description: string;
}

export const BECMASTER_DOWNLOAD_FORMATS: readonly BECMasterDownloadFormatOption[] = Object.freeze([
  Object.freeze({
    id: 'vpro64',
    label: 'VPro64 SQLite (.db)',
    extension: '.db',
    description: 'Ready-to-open VPro project database containing the selected plots and tables.',
  }),
  Object.freeze({
    id: 'csv',
    label: 'CSVs (.zip)',
    extension: '.zip',
    description: 'Zipped CSV files for Environment, Vegetation, Soil, Admin, and Metadata tables.',
  }),
  Object.freeze({
    id: 'gpkg',
    label: 'GeoPackage (.gpkg)',
    extension: '.gpkg',
    description: 'BC Albers spatial GeoPackage with plot points and ecological attributes for GIS.',
  }),
  Object.freeze({
    id: 'rds',
    label: 'R Bundle (.rds)',
    extension: '.rds',
    description: 'Native R data bundle for direct analysis with the vpro R package.',
  }),
  Object.freeze({
    id: 'turboveg',
    label: 'TurboVeg 3 (.zip)',
    extension: '.zip',
    description: 'TurboVeg 3 interchange export for phytosociological software.',
  }),
  Object.freeze({
    id: 'kml',
    label: 'Google Earth (.kml)',
    extension: '.kml',
    description: 'KML placemarks for viewing selected plots in Google Earth.',
  }),
]);

export interface BECMasterDownloadRequest {
  contextId: string;
  format: BECMasterDownloadFormat;
  plotNumbers?: string[];
  filter?: BECMasterFilterRequest;
  crs?: string;
  includeAttributeTables?: boolean;
  turbovegFormat?: string;
}

export interface BECMasterDownloadResponse {
  downloadUrl: string;
  filename: string;
  format: string;
  plotCount: number;
  bytes: number;
}

export interface BECMasterBoundingBox {
  nwLat: number;
  nwLon: number;
  seLat: number;
  seLon: number;
}

export interface BECMasterFilterState {
  mode: BECMasterSelectMode;
  regions: string[];
  projectIds: string[];
  publicationIds: string[];
  nwLat: string;
  nwLon: string;
  seLat: string;
  seLon: string;
  zones: string[];
  subzones: string[];
  minYear: string;
  maxYear: string;
  successionalStatuses: string[];
  structuralStages: string[];
  inPublicationsOnly: boolean;
  sitePlotQualities: string[];
  vegPlotQualities: string[];
  soilPlotQualities: string[];
  locationAccuracy: string;
}

export type WebExplorerTabId = 'map' | 'datasheet' | 'reports' | 'analysis';

export interface WebExplorerUrlState {
  tab?: WebExplorerTabId;
  dataset?: string;
  su?: string;
  hierarchy?: string;
  plot?: string;
  filter?: Partial<BECMasterFilterState>;
}

const VALID_EXPLORER_TABS: ReadonlySet<WebExplorerTabId> = new Set(['map', 'datasheet', 'reports', 'analysis']);

export class BECMasterHttpError extends Error {
  readonly status: number;
  readonly isBusy: boolean;

  constructor(message: string, status: number, isBusy = false) {
    super(message);
    this.name = 'BECMasterHttpError';
    this.status = status;
    this.isBusy = isBusy;
  }
}

function extractHttpErrorText(bodyText: string, status: number, statusText: string): string {
  const trimmed = bodyText.trim();
  if (trimmed) {
    try {
      const parsed = JSON.parse(trimmed) as unknown;
      if (parsed && typeof parsed === 'object') {
        const obj = parsed as Record<string, unknown>;
        if (typeof obj.error === 'string' && obj.error.trim()) return obj.error.trim();
        if (typeof obj.message === 'string' && obj.message.trim()) return obj.message.trim();
      } else if (typeof parsed === 'string' && parsed.trim()) {
        return parsed.trim();
      }
    } catch {
      return trimmed;
    }
  }
  return statusText ? `HTTP ${status} ${statusText}` : `HTTP ${status}`;
}

function resolveFetch(fetchImpl?: typeof fetch): typeof fetch {
  const fn = fetchImpl ?? (typeof globalThis.fetch === 'function' ? globalThis.fetch.bind(globalThis) : null);
  if (!fn) {
    throw new BECMasterHttpError('Network requests are unavailable in this environment.', 0, false);
  }
  return fn;
}

export async function fetchBECMasterFilterOptions(
  contextId?: string,
  opts?: { fetchImpl?: typeof fetch; signal?: AbortSignal }
): Promise<BECMasterFilterOptions> {
  const fetchFn = resolveFetch(opts?.fetchImpl);
  const query = contextId?.trim() ? `?contextId=${encodeURIComponent(contextId.trim())}` : '';
  const response = await fetchFn(`/api/becmaster/filter-options${query}`, {
    method: 'GET',
    signal: opts?.signal,
    headers: {
      Accept: 'application/json',
      [WEB_SESSION_HEADER]: resolveWebSessionId(),
    },
  });
  const text = await response.text();
  if (!response.ok) {
    const rawMsg = extractHttpErrorText(text, response.status, response.statusText);
    const busy = response.status === 503 || response.status === 429 || isExportQueueBusyError(rawMsg);
    throw new BECMasterHttpError(rawMsg, response.status, busy);
  }
  return JSON.parse(text) as BECMasterFilterOptions;
}

export async function filterBECMasterPlots(
  contextId: string,
  filter: BECMasterFilterRequest,
  opts?: { fetchImpl?: typeof fetch; signal?: AbortSignal }
): Promise<BECMasterFilterResult> {
  const fetchFn = resolveFetch(opts?.fetchImpl);
  const response = await fetchFn('/api/becmaster/filter', {
    method: 'POST',
    signal: opts?.signal,
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      [WEB_SESSION_HEADER]: resolveWebSessionId(),
    },
    body: JSON.stringify({
      contextId: contextId.trim(),
      filter,
    }),
  });
  const text = await response.text();
  if (!response.ok) {
    const rawMsg = extractHttpErrorText(text, response.status, response.statusText);
    const busy = response.status === 503 || response.status === 429 || isExportQueueBusyError(rawMsg);
    throw new BECMasterHttpError(rawMsg, response.status, busy);
  }
  return JSON.parse(text) as BECMasterFilterResult;
}

export async function downloadBECMasterSubset(
  req: BECMasterDownloadRequest,
  opts?: {
    fetchImpl?: typeof fetch;
    signal?: AbortSignal;
    autoDownload?: boolean;
    triggerDownload?: (url: string, filename?: string) => boolean;
  }
): Promise<BECMasterDownloadResponse> {
  const fetchFn = resolveFetch(opts?.fetchImpl);
  const response = await fetchFn('/api/becmaster/download', {
    method: 'POST',
    signal: opts?.signal,
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      [WEB_SESSION_HEADER]: resolveWebSessionId(),
    },
    body: JSON.stringify(req),
  });
  const text = await response.text();
  if (!response.ok) {
    const rawMsg = extractHttpErrorText(text, response.status, response.statusText);
    const busy = response.status === 503 || response.status === 429 || isExportQueueBusyError(rawMsg);
    throw new BECMasterHttpError(rawMsg, response.status, busy);
  }
  const payload = JSON.parse(text) as BECMasterDownloadResponse;
  if (opts?.autoDownload !== false && payload.downloadUrl) {
    const dlFn = opts?.triggerDownload ?? triggerBrowserDownload;
    dlFn(payload.downloadUrl, payload.filename);
  }
  return payload;
}

export function createEmptyBECMasterFilterState(): BECMasterFilterState {
  return {
    mode: 'all',
    regions: [],
    projectIds: [],
    publicationIds: [],
    nwLat: '',
    nwLon: '',
    seLat: '',
    seLon: '',
    zones: [],
    subzones: [],
    minYear: '',
    maxYear: '',
    successionalStatuses: [],
    structuralStages: [],
    inPublicationsOnly: false,
    sitePlotQualities: [],
    vegPlotQualities: [],
    soilPlotQualities: [],
    locationAccuracy: '',
  };
}

function roundCoord(val: number): number {
  return Math.round(val * 100000) / 100000;
}

function normalizeWestLongitude(lon: number): number {
  if (lon > 100 && lon <= 180) {
    return -lon;
  }
  return lon;
}

export function normalizeBoundingBox(a: [number, number], b: [number, number]): BECMasterBoundingBox {
  const lonA = normalizeWestLongitude(a[0]);
  const lonB = normalizeWestLongitude(b[0]);
  const latA = a[1];
  const latB = b[1];
  return {
    nwLat: roundCoord(Math.max(latA, latB)),
    nwLon: roundCoord(Math.min(lonA, lonB)),
    seLat: roundCoord(Math.min(latA, latB)),
    seLon: roundCoord(Math.max(lonA, lonB)),
  };
}

function parseFiniteNumber(raw: string): number | undefined {
  const trimmed = raw.trim();
  if (!trimmed) return undefined;
  const n = Number(trimmed);
  return Number.isFinite(n) ? n : undefined;
}

function parseYearInt(raw: string): number | undefined {
  const n = parseFiniteNumber(raw);
  if (n === undefined) return undefined;
  const intVal = Math.trunc(n);
  return intVal >= 1900 && intVal <= 2100 ? intVal : undefined;
}

export function parseBoundingBoxFromState(state: Pick<BECMasterFilterState, 'nwLat' | 'nwLon' | 'seLat' | 'seLon'>): BECMasterBoundingBox | null {
  const nwLat = parseFiniteNumber(state.nwLat);
  const nwLon = parseFiniteNumber(state.nwLon);
  const seLat = parseFiniteNumber(state.seLat);
  const seLon = parseFiniteNumber(state.seLon);
  if (nwLat === undefined || nwLon === undefined || seLat === undefined || seLon === undefined) {
    return null;
  }
  return normalizeBoundingBox([nwLon, nwLat], [seLon, seLat]);
}

export function buildFilterRequestFromState(state: BECMasterFilterState): BECMasterFilterRequest {
  const req: BECMasterFilterRequest = {
    mode: state.mode,
  };

  if (state.mode === 'region' && state.regions.length > 0) {
    req.regions = [...state.regions];
  } else if (state.mode === 'project') {
    if (state.projectIds.length > 0) req.projectIds = [...state.projectIds];
    if (state.publicationIds.length > 0) req.publicationIds = [...state.publicationIds];
  } else if (state.mode === 'bbox') {
    const bbox = parseBoundingBoxFromState(state);
    if (bbox) {
      req.nwLat = bbox.nwLat;
      req.nwLon = bbox.nwLon;
      req.seLat = bbox.seLat;
      req.seLon = bbox.seLon;
    }
  }

  if (state.zones.length > 0) req.zones = [...state.zones];
  if (state.subzones.length > 0) req.subzones = [...state.subzones];

  const minYear = parseYearInt(state.minYear);
  const maxYear = parseYearInt(state.maxYear);
  if (minYear !== undefined) req.minYear = minYear;
  if (maxYear !== undefined) req.maxYear = maxYear;

  if (state.successionalStatuses.length > 0) req.successionalStatuses = [...state.successionalStatuses];
  if (state.structuralStages.length > 0) req.structuralStages = [...state.structuralStages];
  if (state.inPublicationsOnly) req.inPublicationsOnly = true;
  if (state.sitePlotQualities.length > 0) req.sitePlotQualities = [...state.sitePlotQualities];
  if (state.vegPlotQualities.length > 0) req.vegPlotQualities = [...state.vegPlotQualities];
  if (state.soilPlotQualities.length > 0) req.soilPlotQualities = [...state.soilPlotQualities];
  if (state.locationAccuracy.trim()) req.locationAccuracy = state.locationAccuracy.trim();

  return req;
}

export function computeAvailableSubzones(
  subzonesByZone: Record<string, string[]> | null | undefined,
  selectedZones: readonly string[]
): string[] {
  if (!subzonesByZone) return [];
  const zoneKeys =
    selectedZones.length > 0
      ? selectedZones.filter((z) => Object.hasOwn(subzonesByZone, z))
      : Object.keys(subzonesByZone);
  const set = new Set<string>();
  for (const z of zoneKeys) {
    for (const sz of subzonesByZone[z] ?? []) {
      if (sz) set.add(sz);
    }
  }
  return [...set].sort((a, b) => a.localeCompare(b));
}

export function pruneSelectedSubzones(
  selectedSubzones: readonly string[],
  availableSubzones: readonly string[]
): string[] {
  if (selectedSubzones.length === 0) return [];
  const allowed = new Set(availableSubzones);
  return selectedSubzones.filter((sz) => allowed.has(sz));
}

export function countActiveFilters(state: BECMasterFilterState): number {
  let count = 0;
  if (state.mode === 'region' && state.regions.length > 0) count += 1;
  if (state.mode === 'project' && (state.projectIds.length > 0 || state.publicationIds.length > 0)) count += 1;
  if (state.mode === 'bbox' && parseBoundingBoxFromState(state) !== null) count += 1;
  if (state.zones.length > 0) count += 1;
  if (state.subzones.length > 0) count += 1;
  if (parseYearInt(state.minYear) !== undefined || parseYearInt(state.maxYear) !== undefined) count += 1;
  if (state.successionalStatuses.length > 0) count += 1;
  if (state.structuralStages.length > 0) count += 1;
  if (state.inPublicationsOnly) count += 1;
  if (state.sitePlotQualities.length > 0) count += 1;
  if (state.vegPlotQualities.length > 0) count += 1;
  if (state.soilPlotQualities.length > 0) count += 1;
  if (state.locationAccuracy.trim().length > 0) count += 1;
  return count;
}

export function hasActiveFilterSelections(state: BECMasterFilterState): boolean {
  return countActiveFilters(state) > 0;
}

export function formatByteSize(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes < 0) return '0 B';
  if (bytes < 1024) return `${Math.round(bytes)} B`;
  const kb = bytes / 1024;
  if (kb < 1024) return `${kb.toFixed(1)} KB`;
  const mb = kb / 1024;
  if (mb < 1024) return `${mb.toFixed(2)} MB`;
  return `${(mb / 1024).toFixed(2)} GB`;
}

function splitCsvParam(raw: string | null): string[] {
  if (!raw) return [];
  return raw
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

export function parseExplorerUrlState(search: string): WebExplorerUrlState {
  const params = new URLSearchParams(search.startsWith('?') ? search.slice(1) : search);
  const pick = (key: string): string | undefined => {
    const v = params.get(key)?.trim();
    return v ? v : undefined;
  };
  const rawTab = pick('tab') ?? pick('view');
  let tab: WebExplorerTabId | undefined;
  if (rawTab && VALID_EXPLORER_TABS.has(rawTab as WebExplorerTabId)) {
    tab = rawTab as WebExplorerTabId;
  }

  const filter: Partial<BECMasterFilterState> = {};
  const rawMode = pick('mode');
  if (rawMode === 'all' || rawMode === 'region' || rawMode === 'project' || rawMode === 'bbox') {
    filter.mode = rawMode;
  }

  const regions = splitCsvParam(params.get('regions'));
  if (regions.length > 0) {
    filter.regions = regions;
    if (!filter.mode) filter.mode = 'region';
  }
  const projectIds = splitCsvParam(params.get('projects'));
  if (projectIds.length > 0) {
    filter.projectIds = projectIds;
    if (!filter.mode) filter.mode = 'project';
  }
  const publicationIds = splitCsvParam(params.get('pubs'));
  if (publicationIds.length > 0) {
    filter.publicationIds = publicationIds;
    if (!filter.mode) filter.mode = 'project';
  }
  const rawBBox = pick('bbox');
  if (rawBBox) {
    const parts = rawBBox.split(',').map((p) => Number(p.trim()));
    if (parts.length === 4 && parts.every((n) => Number.isFinite(n))) {
      const norm = normalizeBoundingBox([parts[1], parts[0]], [parts[3], parts[2]]);
      filter.nwLat = String(norm.nwLat);
      filter.nwLon = String(norm.nwLon);
      filter.seLat = String(norm.seLat);
      filter.seLon = String(norm.seLon);
      if (!filter.mode) filter.mode = 'bbox';
    }
  }

  const zones = splitCsvParam(params.get('zones'));
  if (zones.length > 0) filter.zones = zones;
  const subzones = splitCsvParam(params.get('subzones'));
  if (subzones.length > 0) filter.subzones = subzones;
  const minYear = pick('minYear');
  if (minYear && parseYearInt(minYear) !== undefined) filter.minYear = minYear;
  const maxYear = pick('maxYear');
  if (maxYear && parseYearInt(maxYear) !== undefined) filter.maxYear = maxYear;
  const succ = splitCsvParam(params.get('succ'));
  if (succ.length > 0) filter.successionalStatuses = succ;
  const stage = splitCsvParam(params.get('stage'));
  if (stage.length > 0) filter.structuralStages = stage;
  if (params.get('pubOnly') === '1' || params.get('pubOnly') === 'true') {
    filter.inPublicationsOnly = true;
  }
  const siteQ = splitCsvParam(params.get('siteQ'));
  if (siteQ.length > 0) filter.sitePlotQualities = siteQ;
  const vegQ = splitCsvParam(params.get('vegQ'));
  if (vegQ.length > 0) filter.vegPlotQualities = vegQ;
  const soilQ = splitCsvParam(params.get('soilQ'));
  if (soilQ.length > 0) filter.soilPlotQualities = soilQ;
  const acc = pick('acc');
  if (acc) filter.locationAccuracy = acc;

  return {
    tab,
    dataset: pick('dataset'),
    su: pick('su'),
    hierarchy: pick('hierarchy'),
    plot: pick('plot'),
    filter: Object.keys(filter).length > 0 ? filter : undefined,
  };
}

export function formatExplorerUrlQuery(state: WebExplorerUrlState): string {
  const params = new URLSearchParams();
  if (state.dataset?.trim()) params.set('dataset', state.dataset.trim());
  if (state.su?.trim() && state.su.trim() !== 'None') params.set('su', state.su.trim());
  if (state.hierarchy?.trim() && state.hierarchy.trim() !== 'None') params.set('hierarchy', state.hierarchy.trim());
  if (state.tab && state.tab !== 'map') params.set('tab', state.tab);
  if (state.plot?.trim()) params.set('plot', state.plot.trim());

  const f = state.filter;
  if (f) {
    if (f.mode && f.mode !== 'all') params.set('mode', f.mode);
    if (f.mode === 'region' && f.regions && f.regions.length > 0) {
      params.set('regions', f.regions.join(','));
    }
    if (f.mode === 'project' && f.projectIds && f.projectIds.length > 0) {
      params.set('projects', f.projectIds.join(','));
    }
    if (f.mode === 'project' && f.publicationIds && f.publicationIds.length > 0) {
      params.set('pubs', f.publicationIds.join(','));
    }
    if (f.mode === 'bbox' && f.nwLat && f.nwLon && f.seLat && f.seLon) {
      const bbox = parseBoundingBoxFromState({
        nwLat: f.nwLat,
        nwLon: f.nwLon,
        seLat: f.seLat,
        seLon: f.seLon,
      });
      if (bbox) {
        params.set('bbox', `${bbox.nwLat},${bbox.nwLon},${bbox.seLat},${bbox.seLon}`);
      }
    }
    if (f.zones && f.zones.length > 0) params.set('zones', f.zones.join(','));
    if (f.subzones && f.subzones.length > 0) params.set('subzones', f.subzones.join(','));
    if (f.minYear && parseYearInt(f.minYear) !== undefined) params.set('minYear', String(parseYearInt(f.minYear)));
    if (f.maxYear && parseYearInt(f.maxYear) !== undefined) params.set('maxYear', String(parseYearInt(f.maxYear)));
    if (f.successionalStatuses && f.successionalStatuses.length > 0) {
      params.set('succ', f.successionalStatuses.join(','));
    }
    if (f.structuralStages && f.structuralStages.length > 0) {
      params.set('stage', f.structuralStages.join(','));
    }
    if (f.inPublicationsOnly) params.set('pubOnly', '1');
    if (f.sitePlotQualities && f.sitePlotQualities.length > 0) params.set('siteQ', f.sitePlotQualities.join(','));
    if (f.vegPlotQualities && f.vegPlotQualities.length > 0) params.set('vegQ', f.vegPlotQualities.join(','));
    if (f.soilPlotQualities && f.soilPlotQualities.length > 0) params.set('soilQ', f.soilPlotQualities.join(','));
    if (f.locationAccuracy?.trim()) params.set('acc', f.locationAccuracy.trim());
  }

  const encoded = params.toString();
  return encoded ? `?${encoded}` : '';
}

export function syncExplorerUrlState(
  state: WebExplorerUrlState,
  win?: {
    location?: { pathname?: string; search?: string; hash?: string };
    history?: { replaceState?: (data: unknown, unused: string, url?: string | URL | null) => void };
  }
): string {
  const targetWin = win ?? (typeof globalThis.window !== 'undefined' ? globalThis.window : undefined);
  const nextSearch = formatExplorerUrlQuery(state);
  if (!targetWin?.location || typeof targetWin.history?.replaceState !== 'function') {
    return nextSearch;
  }
  const pathname = targetWin.location.pathname || '/';
  const hash = targetWin.location.hash || '';
  const currentSearch = targetWin.location.search || '';
  if (currentSearch === nextSearch) {
    return `${pathname}${nextSearch}${hash}`;
  }
  const nextUrl = `${pathname}${nextSearch}${hash}`;
  try {
    targetWin.history.replaceState(null, '', nextUrl);
  } catch {
    // Ignore history restrictions in sandboxed environments.
  }
  return nextUrl;
}

// --- Web Map Basemaps & Style Builders ---

export type WebMapBasemapId = 'esri-hybrid' | 'satellite' | 'bc-gov-topo' | 'osm' | 'offline-neutral';

export interface WebMapBasemapOption {
  id: WebMapBasemapId;
  label: string;
  online: boolean;
  darkTheme: boolean;
  attribution: string;
  baseTiles?: string[];
  referenceTiles?: string[];
  maxZoom?: number;
}

export const DEFAULT_WEB_MAP_BASEMAP: WebMapBasemapId = 'esri-hybrid';

export const WEB_MAP_BASEMAPS: readonly WebMapBasemapOption[] = Object.freeze([
  Object.freeze({
    id: 'esri-hybrid',
    label: 'Esri Hybrid',
    online: true,
    darkTheme: true,
    attribution: 'Esri, Maxar, Earthstar Geographics, GIS User Community',
    baseTiles: [
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    ],
    referenceTiles: [
      'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
    ],
    maxZoom: 18,
  }),
  Object.freeze({
    id: 'satellite',
    label: 'Satellite',
    online: true,
    darkTheme: true,
    attribution: 'Esri, Maxar, Earthstar Geographics, GIS User Community',
    baseTiles: [
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    ],
    maxZoom: 18,
  }),
  Object.freeze({
    id: 'bc-gov-topo',
    label: 'BC Gov Topo',
    online: true,
    darkTheme: false,
    attribution: 'Government of British Columbia, DataBC',
    baseTiles: ['/maps/bc-proxy/basemap/{z}/{y}/{x}'],
    maxZoom: 17,
  }),
  Object.freeze({
    id: 'osm',
    label: 'OpenStreetMap',
    online: true,
    darkTheme: false,
    attribution: 'OpenStreetMap contributors',
    baseTiles: ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],
    maxZoom: 19,
  }),
  Object.freeze({
    id: 'offline-neutral',
    label: 'Offline Neutral',
    online: false,
    darkTheme: false,
    attribution: 'BC Ministry of Forests BEC v13',
  }),
]);

function getWebMapBasemap(id?: WebMapBasemapId | null): WebMapBasemapOption {
  return WEB_MAP_BASEMAPS.find((b) => b.id === id) ?? WEB_MAP_BASEMAPS[0];
}

function buildBECZoneFillMatch(): ExpressionSpecification {
  const stops: string[] = [];
  for (const [zone, hex] of Object.entries(WEB_BEC_ZONE_PALETTE)) {
    stops.push(zone, hex);
  }
  return ['match', ['get', 'ZONE'], ...stops, '#64748b'] as unknown as ExpressionSpecification;
}

export function buildPlotsGeoJSON(points: readonly BECMasterMapPoint[]): GeoJSON.FeatureCollection<GeoJSON.Point> {
  return {
    type: 'FeatureCollection',
    features: points
      .filter((pt) => Number.isFinite(pt.lon) && Number.isFinite(pt.lat))
      .map((pt) => ({
        type: 'Feature',
        geometry: {
          type: 'Point',
          coordinates: [pt.lon, pt.lat],
        },
        properties: {
          plotNumber: pt.plotNumber,
          zone: pt.zone,
          subZone: pt.subZone,
          siteSeries: pt.siteSeries,
          projectId: pt.projectId,
          region: pt.region,
        },
      })),
  };
}

export function buildBBoxGeoJSON(bbox: BECMasterBoundingBox | null): GeoJSON.FeatureCollection<GeoJSON.Polygon> {
  if (!bbox) {
    return { type: 'FeatureCollection', features: [] };
  }
  const { nwLat, nwLon, seLat, seLon } = bbox;
  return {
    type: 'FeatureCollection',
    features: [
      {
        type: 'Feature',
        geometry: {
          type: 'Polygon',
          coordinates: [
            [
              [nwLon, nwLat],
              [seLon, nwLat],
              [seLon, seLat],
              [nwLon, seLat],
              [nwLon, nwLat],
            ],
          ],
        },
        properties: {},
      },
    ],
  };
}

export const BC_DEFAULT_BOUNDS: [[number, number], [number, number]] = [
  [-139.06, 48.3],
  [-114.03, 60.0],
];

export function computePointsBounds(
  points: readonly BECMasterMapPoint[]
): [[number, number], [number, number]] | null {
  let minLon = Infinity;
  let maxLon = -Infinity;
  let minLat = Infinity;
  let maxLat = -Infinity;
  let valid = 0;

  for (const pt of points) {
    if (!Number.isFinite(pt.lon) || !Number.isFinite(pt.lat)) continue;
    if (pt.lat < 40 || pt.lat > 75 || pt.lon < -160 || pt.lon > -100) continue;
    if (pt.lon < minLon) minLon = pt.lon;
    if (pt.lon > maxLon) maxLon = pt.lon;
    if (pt.lat < minLat) minLat = pt.lat;
    if (pt.lat > maxLat) maxLat = pt.lat;
    valid += 1;
  }

  if (valid === 0) return null;
  if (Math.abs(maxLon - minLon) < 0.01 && Math.abs(maxLat - minLat) < 0.01) {
    return [
      [minLon - 0.15, minLat - 0.1],
      [maxLon + 0.15, maxLat + 0.1],
    ];
  }
  return [
    [minLon, minLat],
    [maxLon, maxLat],
  ];
}

export function buildWebExplorerMapStyle(opts: {
  basemap: WebMapBasemapId;
  showBgcOverlay: boolean;
  bgcOpacity?: number;
  pmtilesBaseUrl?: string;
  manifest?: PMTilesManifest | null;
  forceNoPmtiles?: boolean;
}): StyleSpecification {
  const baseOpt = getWebMapBasemap(opts.basemap);
  const bgcArchive = opts.manifest?.archives?.['bc-bgc-v13.pmtiles'];
  const bgcAvailable = !opts.forceNoPmtiles && bgcArchive?.available !== false;
  const bgcMaxZoom = bgcArchive?.maxZoom && bgcArchive.maxZoom > 0 ? bgcArchive.maxZoom : 8;
  const bgcOpacity = Math.max(0, Math.min(1, opts.bgcOpacity ?? 0.38));

  const sources: Record<string, SourceSpecification> = {};

  if (baseOpt.online && baseOpt.baseTiles && baseOpt.baseTiles.length > 0) {
    sources.web_basemap_base = {
      type: 'raster',
      tiles: baseOpt.baseTiles,
      tileSize: 256,
      ...(baseOpt.maxZoom ? { maxzoom: baseOpt.maxZoom } : {}),
      attribution: baseOpt.attribution,
    };
  }
  if (baseOpt.online && baseOpt.referenceTiles && baseOpt.referenceTiles.length > 0) {
    sources.web_basemap_ref = {
      type: 'raster',
      tiles: baseOpt.referenceTiles,
      tileSize: 256,
      ...(baseOpt.maxZoom ? { maxzoom: baseOpt.maxZoom } : {}),
      attribution: baseOpt.attribution,
    };
  }
  if (bgcAvailable) {
    sources.bc_bgc_pmtiles = {
      type: 'vector',
      url: resolveWebPMTilesArchiveUrl('bc-bgc-v13.pmtiles', opts.pmtilesBaseUrl),
      minzoom: 3,
      maxzoom: bgcMaxZoom,
      attribution: 'BC Ministry of Forests BEC v13',
    };
  }

  const layers: LayerSpecification[] = [
    {
      id: 'web-map-bg',
      type: 'background',
      paint: {
        'background-color': baseOpt.darkTheme ? '#0f2338' : '#edf1f5',
      },
    },
  ];

  if (sources.web_basemap_base) {
    layers.push({
      id: 'web-basemap-base-layer',
      type: 'raster',
      source: 'web_basemap_base',
      paint: { 'raster-opacity': 1 },
    });
  }

  if (bgcAvailable) {
    layers.push(
      {
        id: 'bgc-zones-fill',
        type: 'fill',
        source: 'bc_bgc_pmtiles',
        'source-layer': 'bgc',
        layout: { visibility: opts.showBgcOverlay ? 'visible' : 'none' },
        paint: {
          'fill-color': buildBECZoneFillMatch(),
          'fill-opacity': bgcOpacity,
        },
      },
      {
        id: 'bgc-subzone-outline',
        type: 'line',
        source: 'bc_bgc_pmtiles',
        'source-layer': 'bgc',
        layout: { visibility: opts.showBgcOverlay ? 'visible' : 'none' },
        paint: {
          'line-color': baseOpt.darkTheme ? '#e2e8f0' : '#003366',
          'line-width': ['interpolate', ['linear'], ['zoom'], 4, 0.4, 9, 1.15],
          'line-opacity': Math.min(0.85, bgcOpacity + 0.25),
        },
      }
    );
  }

  if (sources.web_basemap_ref) {
    layers.push({
      id: 'web-basemap-ref-layer',
      type: 'raster',
      source: 'web_basemap_ref',
      paint: { 'raster-opacity': 0.9 },
    });
  }

  return {
    version: 8,
    name: `VPro BECMaster Explorer (${baseOpt.label})`,
    sources,
    layers,
  };
}
