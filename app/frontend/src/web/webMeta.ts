import { writable, type Writable } from 'svelte/store';
import { webMeta, webShellRuntime, type WebShellRuntimeBundle } from '../shared/state';
import { IS_WEB_READONLY } from './runtimeMode';

export interface WebMetaSUEntry {
  name: string;
  kind?: string;
  file?: string;
  compatible?: boolean;
}

export interface WebMetaHierarchyEntry {
  name: string;
  file?: string;
  version?: string;
  compatible?: boolean;
}

export interface WebMetaDataset {
  id: string;
  label: string;
  project: string;
  plotCount: number;
  redactedPlotCount: number;
  sus: WebMetaSUEntry[];
  hierarchies: WebMetaHierarchyEntry[];
}

export interface WebMetaStandards {
  becVersion: string;
  taxonomyVersion: string;
  vlistsSha256: string;
  redBlueSpeciesCount: number;
}

export interface WebMetaResponse {
  mode: string;
  snapshotId: string;
  publishedAt: string;
  redacted: boolean;
  redactedPlotCount: number;
  totalPlotCount: number;
  redactionNotice: string;
  picturesAvailable: boolean;
  pmtilesBaseUrl: string;
  standards: WebMetaStandards;
  datasets: WebMetaDataset[];
}

export interface WebUrlState {
  dataset?: string;
  su?: string;
  hierarchy?: string;
  view?: string;
  plot?: string;
}

const DEFAULT_REDACTION_NOTICE =
  'Coordinates for plots with conservation-listed species are generalized to 10 km for rare-plant protection.';

export { webMeta };
export const webMetaError: Writable<string> = writable('');

let cachedMeta: WebMetaResponse | null = null;
let inflightLoad: Promise<WebMetaResponse | null> | null = null;

function asString(value: unknown, fallback = ''): string {
  return typeof value === 'string' ? value.trim() : fallback;
}

function asNonNegInt(value: unknown, fallback = 0): number {
  const n = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(n) && n >= 0 ? Math.floor(n) : fallback;
}

function normalizeDataset(raw: unknown): WebMetaDataset | null {
  if (!raw || typeof raw !== 'object') return null;
  const obj = raw as Record<string, unknown>;
  const id = asString(obj.id || obj.project);
  const project = asString(obj.project || obj.id);
  if (!id && !project) return null;
  const label = asString(obj.label) || project || id;
  const susRaw = Array.isArray(obj.sus) ? obj.sus : [];
  const hierarchiesRaw = Array.isArray(obj.hierarchies) ? obj.hierarchies : [];
  return {
    id: id || project,
    label,
    project: project || id,
    plotCount: asNonNegInt(obj.plotCount ?? obj.plot_count, 0),
    redactedPlotCount: asNonNegInt(obj.redactedPlotCount ?? obj.redacted_plot_count, 0),
    sus: susRaw
      .filter((s): s is Record<string, unknown> => Boolean(s && typeof s === 'object'))
      .map((s) => ({
        name: asString(s.name),
        kind: asString(s.kind) || undefined,
        file: asString(s.file) || undefined,
        compatible: s.compatible === false ? false : true,
      }))
      .filter((s) => s.name.length > 0),
    hierarchies: hierarchiesRaw
      .filter((h): h is Record<string, unknown> => Boolean(h && typeof h === 'object'))
      .map((h) => ({
        name: asString(h.name),
        file: asString(h.file) || undefined,
        version: asString(h.version) || undefined,
        compatible: h.compatible === false ? false : true,
      }))
      .filter((h) => h.name.length > 0),
  };
}

export function normalizeWebMeta(raw: unknown): WebMetaResponse {
  const obj = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  const datasetsRaw = Array.isArray(obj.datasets) ? obj.datasets : [];
  const datasets = datasetsRaw.map(normalizeDataset).filter((d): d is WebMetaDataset => d !== null);
  const computedTotal = datasets.reduce((sum, ds) => sum + ds.plotCount, 0);
  const computedRedacted = datasets.reduce((sum, ds) => sum + ds.redactedPlotCount, 0);
  const redacted = Boolean(obj.redacted ?? obj.coordinatesRedacted ?? computedRedacted > 0);
  const redactedPlotCount = asNonNegInt(obj.redactedPlotCount ?? obj.redacted_plot_count, computedRedacted);
  const totalPlotCount = asNonNegInt(obj.totalPlotCount ?? obj.total_plot_count ?? obj.plotCount, computedTotal);
  const explicitNotice = asString(obj.redactionNotice ?? obj.redaction_notice);
  const redactionNotice = explicitNotice || (redacted ? DEFAULT_REDACTION_NOTICE : '');
  const picturesAvailableRaw = obj.picturesAvailable ?? obj.pictures_available;
  const picturesAvailable = picturesAvailableRaw === false ? false : true;
  const rawBaseUrl = asString(obj.pmtilesBaseUrl ?? obj.pmtiles_base_url, '/pmtiles');
  const pmtilesBaseUrl = rawBaseUrl ? rawBaseUrl.replace(/\/+$/, '') : '/pmtiles';
  const stdRaw =
    obj.standards && typeof obj.standards === 'object' ? (obj.standards as Record<string, unknown>) : {};

  return {
    mode: asString(obj.mode, 'readonly') || 'readonly',
    snapshotId: asString(obj.snapshotId ?? obj.snapshot_id),
    publishedAt: asString(obj.publishedAt ?? obj.published_at),
    redacted,
    redactedPlotCount,
    totalPlotCount,
    redactionNotice,
    picturesAvailable,
    pmtilesBaseUrl,
    standards: {
      becVersion: asString(stdRaw.becVersion ?? stdRaw.bec_version, 'BECdb v13'),
      taxonomyVersion: asString(stdRaw.taxonomyVersion ?? stdRaw.taxonomy_version, 'BCPlantTaxonomy v19'),
      vlistsSha256: asString(stdRaw.vlistsSha256 ?? stdRaw.vlists_sha256),
      redBlueSpeciesCount: asNonNegInt(stdRaw.redBlueSpeciesCount ?? stdRaw.red_blue_species_count, 0),
    },
    datasets,
  };
}

export function getCachedWebMeta(): WebMetaResponse | null {
  return cachedMeta;
}

export function setWebMetaCache(meta: WebMetaResponse | null): void {
  cachedMeta = meta;
  webMeta.set(meta);
  if (meta) webMetaError.set('');
}

export function resetWebMetaCache(): void {
  cachedMeta = null;
  inflightLoad = null;
  webMeta.set(null);
  webMetaError.set('');
}

export async function loadWebMeta(options?: {
  force?: boolean;
  fetchImpl?: typeof fetch;
  ignoreMode?: boolean;
}): Promise<WebMetaResponse | null> {
  if (!options?.ignoreMode && !IS_WEB_READONLY) {
    return null;
  }
  if (!options?.force && cachedMeta) {
    return cachedMeta;
  }
  if (!options?.force && inflightLoad) {
    return inflightLoad;
  }
  const fetchFn = options?.fetchImpl ?? (typeof globalThis.fetch === 'function' ? globalThis.fetch.bind(globalThis) : null);
  if (!fetchFn) {
    return null;
  }

  const run = (async () => {
    try {
      const response = await fetchFn('/api/meta', {
        method: 'GET',
        headers: { Accept: 'application/json' },
      });
      if (!response.ok) {
        webMetaError.set(`Could not load snapshot information (HTTP ${response.status}).`);
        return null;
      }
      const raw = (await response.json()) as unknown;
      const normalized = normalizeWebMeta(raw);
      cachedMeta = normalized;
      webMeta.set(normalized);
      webMetaError.set('');
      return normalized;
    } catch (cause) {
      const msg = cause instanceof Error ? cause.message : String(cause ?? 'Network error');
      webMetaError.set(`Could not load snapshot information: ${msg}`);
      return null;
    } finally {
      inflightLoad = null;
    }
  })();

  inflightLoad = run;
  return run;
}

export function resolveWebPMTilesBaseUrl(meta: WebMetaResponse | null = cachedMeta): string {
  const base = meta?.pmtilesBaseUrl?.trim() || '/pmtiles';
  return base.replace(/\/+$/, '');
}

export function parseWebUrlState(search: string): WebUrlState {
  const params = new URLSearchParams(search.startsWith('?') ? search.slice(1) : search);
  const pick = (key: string): string | undefined => {
    const val = params.get(key)?.trim();
    return val ? val : undefined;
  };
  return {
    dataset: pick('dataset'),
    su: pick('su'),
    hierarchy: pick('hierarchy'),
    view: pick('view'),
    plot: pick('plot'),
  };
}

export function formatWebUrlQuery(state: WebUrlState): string {
  const params = new URLSearchParams();
  const dataset = state.dataset?.trim();
  if (dataset) params.set('dataset', dataset);
  const su = state.su?.trim();
  if (su && su !== 'None') params.set('su', su);
  const hierarchy = state.hierarchy?.trim();
  if (hierarchy && hierarchy !== 'None') params.set('hierarchy', hierarchy);
  const view = state.view?.trim();
  if (view) params.set('view', view);
  const plot = state.plot?.trim();
  if (plot) params.set('plot', plot);
  const encoded = params.toString();
  return encoded ? `?${encoded}` : '';
}

export function syncWebUrlState(
  state: WebUrlState,
  win?: {
    location?: { pathname?: string; search?: string; hash?: string };
    history?: { replaceState?: (data: unknown, unused: string, url?: string | URL | null) => void };
  }
): string {
  const targetWin = win ?? (typeof globalThis.window !== 'undefined' ? globalThis.window : undefined);
  const nextSearch = formatWebUrlQuery(state);
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
    // Ignore history API restrictions in sandboxed iframes/tests.
  }
  return nextUrl;
}

export function isExportQueueBusyError(cause: unknown): boolean {
  const text = (cause instanceof Error ? cause.message : String(cause ?? '')).toLowerCase();
  return (
    text.includes('429') ||
    text.includes('503') ||
    text.includes('too many') ||
    text.includes('semaphore') ||
    text.includes('export queue') ||
    text.includes('server busy') ||
    text.includes('export busy') ||
    text.includes('worker pool is busy') ||
    text.includes('pool is busy') ||
    text.includes('retry shortly') ||
    text.includes('capacity')
  );
}

export function formatWebDownloadFeedback(cause: unknown, fallbackMessage: string): string {
  if (isExportQueueBusyError(cause)) {
    return 'Another download is currently being prepared on the server. Please wait a few seconds and try again.';
  }
  return fallbackMessage;
}

export const VALID_WEB_URL_VIEWS: ReadonlySet<string> = new Set([
  'home',
  'plots',
  'geospatial-map',
  'diagnostic-synthesis',
  'r-sidecar',
  'hierarchy',
  'fs882',
  'fs882-twopage',
  'datasheet',
  'classification-explorer',
  'lump-editor',
  'interchange-hub',
  'long-environment',
  'summary-environment',
  'long-vegetation',
  'summary-vegetation',
  'lifeform-summary',
  'subzone-matrix',
  'table-csv',
  'plot-locations',
  'google-earth-review',
  'picture-manager',
  'plot-label-preview',
]);

export const WEB_HUB_WORKFLOW_OVERRIDES: Readonly<
  Record<string, { title: string; subtitle: string; description: string; cta: string }>
> = {
  entry: {
    title: 'Plots & FS882 / SIVI Viewer',
    subtitle: 'LMH25 (2023) Read-Only Field Cards',
    description:
      'Browse published plots and inspect FS882 (6x4), 2-Page, and FS1333 SIVI records with soil horizons, vegetation strata, and live LMH25 diagnostic checks.',
    cta: 'Browse Plots',
  },
  datasheet: {
    title: 'Universal Datasheet Grid',
    subtitle: 'Multi-Plot Table Browser',
    description:
      'Filter, sort, and search across Environment, Vegetation, Humus, Mineral, and Site Unit tables, and jump directly to any plot card.',
    cta: 'Open Datasheet',
  },
  classification: {
    title: 'SU & Hierarchy Explorer',
    subtitle: 'BEC Classification Browser',
    description:
      'Explore published Site Unit assignments, browse tilde (~) hierarchy trees, and inspect species lumping rules and folding impacts.',
    cta: 'Open Explorer',
  },
  spatial: {
    title: '3D Map & Spatial QA',
    subtitle: 'BGC v13 Overlay & Polygon Filter',
    description:
      'Inspect plot coordinates over BGC v13, Ecosections, and Natural Resource Districts, run coordinate checks, filter plots by polygon, and download KML.',
    cta: 'Open 3D Map',
  },
  synthesis: {
    title: 'BEC Diagnostic Synthesis & R Guides',
    subtitle: 'Presence, Fidelity, climr aSMR & Quarto',
    description:
      'Compute Presence (I–V), Domin-Krajina Significance, differential species classes (d, dd, cd, c, ic), climr aSMR edatopic grids, and downloadable guides.',
    cta: 'Open Diagnostics',
  },
  interchange: {
    title: 'Export & Downloads Hub',
    subtitle: 'Excel, TurboVeg 3, CSV, R .rds, GeoPackage',
    description:
      'Download BEC diagnostic workbooks, vegetation and environment reports, TurboVeg 3 exports, CSV tables, native R .rds files, and GeoPackages.',
    cta: 'Open Downloads Hub',
  },
};

export interface WebUrlContextInput {
  contextId?: string;
  activeProject?: string;
  projectPath?: string;
  activeSU?: string;
  suPath?: string;
  activeHierarchy?: string;
  hierarchyPath?: string;
  projects?: readonly { name: string; file?: string; path?: string }[] | null;
  sus?: readonly { name: string; path?: string }[] | null;
  hierarchies?: readonly { name: string; path?: string }[] | null;
}

export interface WebUrlResolutionPlan {
  parsed: WebUrlState;
  switchSelection: {
    project: string;
    projectPath: string;
    su: string;
    suPath: string;
    hierarchy: string;
    hierarchyPath: string;
  } | null;
  view?: string;
  editorEntryForm?: 'fs882-twopage';
  plotNumber?: string;
}

export function planInitialWebUrlNavigation(
  search: string,
  state: WebUrlContextInput,
  picturesAvailable: boolean,
  isAllowedView: (view: string, picturesAvailable: boolean) => boolean
): WebUrlResolutionPlan {
  const parsed = parseWebUrlState(search);
  const wantsSwitch = Boolean(
    state.contextId &&
      ((parsed.dataset && parsed.dataset !== state.activeProject) ||
        (parsed.su && parsed.su !== state.activeSU) ||
        (parsed.hierarchy && parsed.hierarchy !== state.activeHierarchy))
  );
  let switchSelection: WebUrlResolutionPlan['switchSelection'] = null;
  if (wantsSwitch) {
    const targetProject = parsed.dataset
      ? state.projects?.find((p) => p.name === parsed.dataset || p.file === parsed.dataset)
      : state.projects?.find((p) => p.name === state.activeProject && p.path === state.projectPath);
    const targetSU = parsed.su ? state.sus?.find((s) => s.name === parsed.su) : undefined;
    const targetHier = parsed.hierarchy ? state.hierarchies?.find((h) => h.name === parsed.hierarchy) : undefined;
    switchSelection = {
      project: targetProject?.name ?? state.activeProject ?? '',
      projectPath: targetProject?.path ?? state.projectPath ?? '',
      su: parsed.su ? (targetSU?.name ?? parsed.su) : (state.activeSU ?? ''),
      suPath: parsed.su ? (targetSU?.path ?? '') : (state.suPath ?? ''),
      hierarchy: parsed.hierarchy ? (targetHier?.name ?? parsed.hierarchy) : (state.activeHierarchy ?? ''),
      hierarchyPath: parsed.hierarchy ? (targetHier?.path ?? '') : (state.hierarchyPath ?? ''),
    };
  }
  const plan: WebUrlResolutionPlan = { parsed, switchSelection };
  if (parsed.plot) {
    plan.plotNumber = parsed.plot;
  }
  if (parsed.view && VALID_WEB_URL_VIEWS.has(parsed.view) && isAllowedView(parsed.view, picturesAvailable)) {
    if (parsed.view === 'fs882-twopage') {
      plan.view = 'fs882';
      plan.editorEntryForm = 'fs882-twopage';
    } else {
      plan.view = parsed.view;
    }
  } else if (parsed.plot) {
    plan.view = 'fs882';
  }
  return plan;
}

let webShellBootstrapPromise: Promise<WebShellRuntimeBundle> | null = null;

export function bootstrapWebShellRuntime(): Promise<WebShellRuntimeBundle> {
  if (!webShellBootstrapPromise) {
    webShellBootstrapPromise = Promise.all([
      import('../shell/webReadOnlyShell'),
      import('../shell/WebSnapshotProvenance.svelte'),
    ]).then(([shellMod, provenanceMod]) => {
      const bundle: WebShellRuntimeBundle = {
        filterMenus: shellMod.filterNavigationMenusForMode,
        isViewAllowed: shellMod.isViewAllowedInWebReadOnly,
        hubOverrides: WEB_HUB_WORKFLOW_OVERRIDES,
        planInitialUrl: (search, state, picturesAvailable) =>
          planInitialWebUrlNavigation(search, state, picturesAvailable, shellMod.isViewAllowedInWebReadOnly),
        syncUrl: (urlState) => syncWebUrlState(urlState),
        ProvenanceBadge: provenanceMod.default,
      };
      webShellRuntime.set(bundle);
      return bundle;
    });
  }
  return webShellBootstrapPromise;
}
