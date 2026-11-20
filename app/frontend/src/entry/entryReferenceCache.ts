import type { VegetationSpeciesOption } from '../../bindings/github.com/boostao/vpro/app';
import { evictMapEntriesByContext, registerContextDisposer } from '../shared/contextSessionRegistry';
import type { BECSiteSeries, BECSubZone, BECZone } from './becEditor';
import type { FS882ChildCapabilities } from './fs882FormHelpers';
import type { SpeciesLists } from './vegetationSpeciesEditor';
import type { WorkingUnitChoice, WorkingUnitMode, WorkingUnitModeState } from './workingUnitEditor';

const BEC_LRU_LIMIT = 64;
const PLOT_BUNDLE_LRU_LIMIT = 6;
const MASTER_WORKING_UNIT_CATALOGUE_KEY = 'masterWorkingUnit';

const SPECIES_CANONICAL_FORM_GROUPS: ReadonlyArray<{
  canonicalForm: string;
  aliases: readonly string[];
}> = [
  { canonicalForm: 'SubVegAXL_BC', aliases: ['SubVegAXL_BC', 'SubVegAXL', 'SubVegAhtXL'] },
  { canonicalForm: 'SubVegCXL', aliases: ['SubVegCXL', 'SubVegChtXL'] },
  { canonicalForm: 'SubVegDXL', aliases: ['SubVegDXL'] },
];

export interface CachedContextCapabilities {
  headerCapabilities: Record<string, boolean | undefined>;
  childCapabilities: FS882ChildCapabilities;
  masterAllowed: boolean;
}

const globalCatalogues = new Map<string, unknown[]>();
const globalCataloguePending = new Map<string, Promise<unknown[]>>();

let becZonesCache: BECZone[] | undefined;
let becZonesPending: Promise<BECZone[]> | null = null;
const becSubZonesCache = new Map<string, BECSubZone[]>();
const becSubZonesPending = new Map<string, Promise<BECSubZone[]>>();
const becSiteSeriesCache = new Map<string, BECSiteSeries[]>();
const becSiteSeriesPending = new Map<string, Promise<BECSiteSeries[]>>();

let coordinateModeCache: string | undefined;
let coordinateModePending: Promise<string> | null = null;

let workingUnitModeCache: WorkingUnitModeState | undefined;
let workingUnitModePending: Promise<WorkingUnitModeState> | null = null;

const workingUnitChoicesCache = new Map<string, WorkingUnitChoice[]>();
const workingUnitChoicesPending = new Map<string, Promise<WorkingUnitChoice[]>>();

const contextCapabilitiesCache = new Map<string, CachedContextCapabilities>();

const contextValuesCache = new Map<string, unknown>();
const contextValuesPending = new Map<string, Promise<unknown>>();

const speciesListsCache = new Map<string, SpeciesLists>();
const speciesListsPending = new Map<string, Promise<SpeciesLists>>();

const plotBundlesCache = new Map<string, Map<string, unknown>>();
const plotBundlesPending = new Map<string, Promise<unknown>>();

function contextKey(contextId: string, subKey: string): string {
  return `${contextId}\u0000${subKey}`;
}

function invokeFetcher<T>(fetcher: () => Promise<T>): Promise<T> {
  try {
    return Promise.resolve(fetcher());
  } catch (cause) {
    return Promise.reject(cause);
  }
}

function freezeArray<T>(rows: T[]): T[] {
  return (Object.isFrozen(rows) ? rows : Object.freeze(rows.slice())) as T[];
}

function freezeIfArray<T>(value: T): T {
  return Array.isArray(value) ? (freezeArray(value) as unknown as T) : value;
}

function lruGet<K, V>(map: Map<K, V>, key: K): V | undefined {
  if (!map.has(key)) return undefined;
  const value = map.get(key) as V;
  map.delete(key);
  map.set(key, value);
  return value;
}

function lruSet<K, V>(map: Map<K, V>, key: K, value: V, maxEntries: number): void {
  if (map.has(key)) map.delete(key);
  map.set(key, value);
  while (map.size > maxEntries) {
    const oldest = map.keys().next();
    if (oldest.done) break;
    map.delete(oldest.value);
  }
}

function becSubZoneKey(zone: string | null): string {
  return JSON.stringify(zone);
}

function becSiteSeriesKey(zone: string | null, subZone: string | null): string {
  return JSON.stringify([zone, subZone]);
}

function disposeContextEntries(oldContextId: string): void {
  if (!oldContextId) return;
  evictMapEntriesByContext(workingUnitChoicesCache, oldContextId);
  evictMapEntriesByContext(workingUnitChoicesPending, oldContextId);
  contextCapabilitiesCache.delete(oldContextId);
  evictMapEntriesByContext(contextValuesCache, oldContextId);
  evictMapEntriesByContext(contextValuesPending, oldContextId);
  speciesListsCache.delete(oldContextId);
  speciesListsPending.delete(oldContextId);
  plotBundlesCache.delete(oldContextId);
  evictMapEntriesByContext(plotBundlesPending, oldContextId);
}

registerContextDisposer(disposeContextEntries);

// ---------------------------------------------------------------------------
// Global static catalogues
// ---------------------------------------------------------------------------

export function peekGlobalCatalogue<T>(key: string): T[] | undefined {
  return globalCatalogues.get(key) as T[] | undefined;
}

export function invalidateGlobalCatalogue(key?: string): void {
  if (key === undefined) {
    globalCatalogues.clear();
    globalCataloguePending.clear();
    return;
  }
  globalCatalogues.delete(key);
  globalCataloguePending.delete(key);
}

export function getCachedGlobalCatalogue<T>(
  key: string,
  fetcher: () => Promise<T[]>,
  force = false
): Promise<T[]> {
  if (!force) {
    const cached = globalCatalogues.get(key);
    if (cached !== undefined) return Promise.resolve(cached as T[]);
    const pending = globalCataloguePending.get(key);
    if (pending !== undefined) return pending as Promise<T[]>;
  } else {
    globalCatalogues.delete(key);
    globalCataloguePending.delete(key);
  }
  const request: Promise<T[]> = invokeFetcher(fetcher).then(
      (rows) => {
        if (!Array.isArray(rows)) {
          if (globalCataloguePending.get(key) === request) globalCataloguePending.delete(key);
          return rows;
        }
        const frozen = freezeArray(rows);
        if (globalCataloguePending.get(key) === request) {
          globalCataloguePending.delete(key);
          globalCatalogues.set(key, frozen);
        }
        return frozen;
      },
      (cause) => {
        if (globalCataloguePending.get(key) === request) globalCataloguePending.delete(key);
        throw cause;
      }
    );
  globalCataloguePending.set(key, request);
  return request;
}

// ---------------------------------------------------------------------------
// BEC hierarchy (global zones + LRU of 64 subZone / (zone, subZone) keys)
// ---------------------------------------------------------------------------

export function peekBECZones(): BECZone[] | undefined {
  return becZonesCache;
}

export function getCachedBECZones(fetcher: () => Promise<BECZone[]>, force = false): Promise<BECZone[]> {
  if (!force) {
    if (becZonesCache !== undefined) return Promise.resolve(becZonesCache);
    if (becZonesPending !== null) return becZonesPending;
  } else {
    becZonesCache = undefined;
    becZonesPending = null;
  }
  const request: Promise<BECZone[]> = invokeFetcher(fetcher).then(
      (rows) => {
        if (!Array.isArray(rows)) {
          if (becZonesPending === request) becZonesPending = null;
          return rows;
        }
        const frozen = freezeArray(rows);
        if (becZonesPending === request) {
          becZonesPending = null;
          becZonesCache = frozen;
        }
        return frozen;
      },
      (cause) => {
        if (becZonesPending === request) becZonesPending = null;
        throw cause;
      }
    );
  becZonesPending = request;
  return request;
}

export function peekBECSubZones(zone: string | null): BECSubZone[] | undefined {
  return lruGet(becSubZonesCache, becSubZoneKey(zone));
}

export function getCachedBECSubZones(
  zone: string | null,
  fetcher: () => Promise<BECSubZone[]>,
  force = false
): Promise<BECSubZone[]> {
  const key = becSubZoneKey(zone);
  if (!force) {
    const cached = lruGet(becSubZonesCache, key);
    if (cached !== undefined) return Promise.resolve(cached);
    const pending = becSubZonesPending.get(key);
    if (pending !== undefined) return pending;
  } else {
    becSubZonesCache.delete(key);
    becSubZonesPending.delete(key);
  }
  const request: Promise<BECSubZone[]> = invokeFetcher(fetcher).then(
      (rows) => {
        if (!Array.isArray(rows)) {
          if (becSubZonesPending.get(key) === request) becSubZonesPending.delete(key);
          return rows;
        }
        const frozen = freezeArray(rows);
        if (becSubZonesPending.get(key) === request) {
          becSubZonesPending.delete(key);
          lruSet(becSubZonesCache, key, frozen, BEC_LRU_LIMIT);
        }
        return frozen;
      },
      (cause) => {
        if (becSubZonesPending.get(key) === request) becSubZonesPending.delete(key);
        throw cause;
      }
    );
  becSubZonesPending.set(key, request);
  return request;
}

export function peekBECSiteSeries(zone: string | null, subZone: string | null): BECSiteSeries[] | undefined {
  return lruGet(becSiteSeriesCache, becSiteSeriesKey(zone, subZone));
}

export function getCachedBECSiteSeries(
  zone: string | null,
  subZone: string | null,
  fetcher: () => Promise<BECSiteSeries[]>,
  force = false
): Promise<BECSiteSeries[]> {
  const key = becSiteSeriesKey(zone, subZone);
  if (!force) {
    const cached = lruGet(becSiteSeriesCache, key);
    if (cached !== undefined) return Promise.resolve(cached);
    const pending = becSiteSeriesPending.get(key);
    if (pending !== undefined) return pending;
  } else {
    becSiteSeriesCache.delete(key);
    becSiteSeriesPending.delete(key);
  }
  const request: Promise<BECSiteSeries[]> = invokeFetcher(fetcher).then(
      (rows) => {
        if (!Array.isArray(rows)) {
          if (becSiteSeriesPending.get(key) === request) becSiteSeriesPending.delete(key);
          return rows;
        }
        const frozen = freezeArray(rows);
        if (becSiteSeriesPending.get(key) === request) {
          becSiteSeriesPending.delete(key);
          lruSet(becSiteSeriesCache, key, frozen, BEC_LRU_LIMIT);
        }
        return frozen;
      },
      (cause) => {
        if (becSiteSeriesPending.get(key) === request) becSiteSeriesPending.delete(key);
        throw cause;
      }
    );
  becSiteSeriesPending.set(key, request);
  return request;
}

export function invalidateBECCache(): void {
  becZonesCache = undefined;
  becZonesPending = null;
  becSubZonesCache.clear();
  becSubZonesPending.clear();
  becSiteSeriesCache.clear();
  becSiteSeriesPending.clear();
}

// ---------------------------------------------------------------------------
// User preferences (global)
// ---------------------------------------------------------------------------

export function peekCoordinateMode(): string | undefined {
  return coordinateModeCache;
}

export function setCachedCoordinateMode(mode: string): void {
  coordinateModeCache = mode;
  coordinateModePending = null;
}

export function getCachedCoordinateMode(fetcher: () => Promise<string>, force = false): Promise<string> {
  if (!force) {
    if (coordinateModeCache !== undefined) return Promise.resolve(coordinateModeCache);
    if (coordinateModePending !== null) return coordinateModePending;
  } else {
    coordinateModeCache = undefined;
    coordinateModePending = null;
  }
  const request: Promise<string> = invokeFetcher(fetcher).then(
      (mode) => {
        if (coordinateModePending === request) {
          coordinateModePending = null;
          coordinateModeCache = mode;
        }
        return mode;
      },
      (cause) => {
        if (coordinateModePending === request) coordinateModePending = null;
        throw cause;
      }
    );
  coordinateModePending = request;
  return request;
}

export function peekWorkingUnitMode(): WorkingUnitModeState | undefined {
  return workingUnitModeCache;
}

export function setCachedWorkingUnitMode(state: WorkingUnitModeState): void {
  workingUnitModeCache = Object.freeze({ mode: state.mode, warning: state.warning });
  workingUnitModePending = null;
}

export function getCachedWorkingUnitMode(
  fetcher: () => Promise<WorkingUnitModeState>,
  force = false
): Promise<WorkingUnitModeState> {
  if (!force) {
    if (workingUnitModeCache !== undefined) return Promise.resolve(workingUnitModeCache);
    if (workingUnitModePending !== null) return workingUnitModePending;
  } else {
    workingUnitModeCache = undefined;
    workingUnitModePending = null;
  }
  const request: Promise<WorkingUnitModeState> = invokeFetcher(fetcher).then(
      (state) => {
        const frozen = Object.freeze({ mode: state.mode, warning: state.warning });
        if (workingUnitModePending === request) {
          workingUnitModePending = null;
          workingUnitModeCache = frozen;
        }
        return frozen;
      },
      (cause) => {
        if (workingUnitModePending === request) workingUnitModePending = null;
        throw cause;
      }
    );
  workingUnitModePending = request;
  return request;
}

// ---------------------------------------------------------------------------
// Working units (global master + context-scoped env/su/mode choices)
// ---------------------------------------------------------------------------

export function peekMasterWorkingUnitChoices(): WorkingUnitChoice[] | undefined {
  return peekGlobalCatalogue<WorkingUnitChoice>(MASTER_WORKING_UNIT_CATALOGUE_KEY);
}

export function getCachedMasterWorkingUnitChoices(
  fetcher: () => Promise<WorkingUnitChoice[]>,
  force = false
): Promise<WorkingUnitChoice[]> {
  return getCachedGlobalCatalogue<WorkingUnitChoice>(MASTER_WORKING_UNIT_CATALOGUE_KEY, fetcher, force);
}

export function peekWorkingUnitChoices(contextId: string, mode: WorkingUnitMode): WorkingUnitChoice[] | undefined {
  if (!contextId) return mode === 'master' ? peekMasterWorkingUnitChoices() : undefined;
  return workingUnitChoicesCache.get(contextKey(contextId, mode));
}

export function invalidateWorkingUnitChoices(contextId: string, mode?: WorkingUnitMode): void {
  if (!contextId) return;
  if (mode !== undefined) {
    const key = contextKey(contextId, mode);
    workingUnitChoicesCache.delete(key);
    workingUnitChoicesPending.delete(key);
    return;
  }
  evictMapEntriesByContext(workingUnitChoicesCache, contextId);
  evictMapEntriesByContext(workingUnitChoicesPending, contextId);
}

export function getCachedWorkingUnitChoices(
  contextId: string,
  mode: WorkingUnitMode,
  fetcher: () => Promise<WorkingUnitChoice[]>,
  force = false
): Promise<WorkingUnitChoice[]> {
  if (!contextId) {
    if (mode === 'master') return getCachedMasterWorkingUnitChoices(fetcher, force);
    return invokeFetcher(fetcher);
  }
  const key = contextKey(contextId, mode);
  if (!force) {
    const cached = workingUnitChoicesCache.get(key);
    if (cached !== undefined) return Promise.resolve(cached);
    const pending = workingUnitChoicesPending.get(key);
    if (pending !== undefined) return pending;
  } else {
    workingUnitChoicesCache.delete(key);
    workingUnitChoicesPending.delete(key);
  }
  const request: Promise<WorkingUnitChoice[]> = invokeFetcher(fetcher).then(
      (rows) => {
        if (!Array.isArray(rows)) {
          if (workingUnitChoicesPending.get(key) === request) workingUnitChoicesPending.delete(key);
          return rows;
        }
        const frozen = freezeArray(rows);
        if (workingUnitChoicesPending.get(key) === request) {
          workingUnitChoicesPending.delete(key);
          workingUnitChoicesCache.set(key, frozen);
        }
        return frozen;
      },
      (cause) => {
        if (workingUnitChoicesPending.get(key) === request) workingUnitChoicesPending.delete(key);
        throw cause;
      }
    );
  workingUnitChoicesPending.set(key, request);
  return request;
}

// ---------------------------------------------------------------------------
// Context capabilities & Master BEC policy
// ---------------------------------------------------------------------------

export function getCachedContextCapabilities(contextId: string): CachedContextCapabilities | undefined {
  if (!contextId) return undefined;
  return contextCapabilitiesCache.get(contextId);
}

export function setCachedContextCapabilities(contextId: string, caps: CachedContextCapabilities): void {
  if (!contextId) return;
  contextCapabilitiesCache.set(contextId, caps);
}

export function invalidateMasterBECPolicy(): void {
  contextCapabilitiesCache.clear();
}

// ---------------------------------------------------------------------------
// Generic context-scoped values (soilSuggestions, attributeSuggestions, etc.)
// ---------------------------------------------------------------------------

export function peekContextValue<T>(contextId: string, key: string): T | undefined {
  if (!contextId) return undefined;
  return contextValuesCache.get(contextKey(contextId, key)) as T | undefined;
}

export function invalidateContextValue(contextId: string, key?: string): void {
  if (!contextId) return;
  if (key !== undefined) {
    const composite = contextKey(contextId, key);
    contextValuesCache.delete(composite);
    contextValuesPending.delete(composite);
    return;
  }
  evictMapEntriesByContext(contextValuesCache, contextId);
  evictMapEntriesByContext(contextValuesPending, contextId);
}

export function invalidateProjectIdChoices(contextId: string): void {
  invalidateContextValue(contextId, 'projectIdChoices');
}

export function getCachedContextValue<T>(
  contextId: string,
  key: string,
  fetcher: () => Promise<T>,
  force = false
): Promise<T> {
  if (!contextId) {
    return invokeFetcher(fetcher).then((value) => freezeIfArray(value));
  }
  const composite = contextKey(contextId, key);
  if (!force) {
    if (contextValuesCache.has(composite)) {
      return Promise.resolve(contextValuesCache.get(composite) as T);
    }
    const pending = contextValuesPending.get(composite);
    if (pending !== undefined) return pending as Promise<T>;
  } else {
    contextValuesCache.delete(composite);
    contextValuesPending.delete(composite);
  }
  const request: Promise<T> = invokeFetcher(fetcher).then(
      (value) => {
        const stored = freezeIfArray(value);
        if (contextValuesPending.get(composite) === request) {
          contextValuesPending.delete(composite);
          contextValuesCache.set(composite, stored);
        }
        return stored;
      },
      (cause) => {
        if (contextValuesPending.get(composite) === request) contextValuesPending.delete(composite);
        throw cause;
      }
    );
  contextValuesPending.set(composite, request);
  return request;
}

// ---------------------------------------------------------------------------
// Deduplicated species lists per contextId (3 canonical lifeform groups -> 6 forms)
// ---------------------------------------------------------------------------

export function peekSpeciesLists(contextId: string): SpeciesLists | undefined {
  if (!contextId) return undefined;
  return speciesListsCache.get(contextId);
}

export function invalidateSpeciesLists(contextId?: string): void {
  if (!contextId) {
    speciesListsCache.clear();
    speciesListsPending.clear();
    return;
  }
  speciesListsCache.delete(contextId);
  speciesListsPending.delete(contextId);
}

async function fetchCanonicalSpeciesLists(
  fetchForm: (form: string) => Promise<VegetationSpeciesOption[] | null>
): Promise<SpeciesLists> {
  const results = await Promise.all(
    SPECIES_CANONICAL_FORM_GROUPS.map(({ canonicalForm }) => fetchForm(canonicalForm))
  );
  const lists: SpeciesLists = {};
  SPECIES_CANONICAL_FORM_GROUPS.forEach((group, index) => {
    const options = results[index];
    if (options === null || !Array.isArray(options)) {
      throw new Error(`Species metadata for ${group.canonicalForm} was not returned.`);
    }
    const frozen = freezeArray(options);
    for (const formName of group.aliases) {
      lists[formName] = frozen;
    }
  });
  return Object.freeze(lists);
}

export function getCachedSpeciesLists(
  contextId: string,
  fetchForm: (form: string) => Promise<VegetationSpeciesOption[] | null>,
  force = false
): Promise<SpeciesLists> {
  if (!contextId) {
    return fetchCanonicalSpeciesLists(fetchForm);
  }
  if (!force) {
    const cached = speciesListsCache.get(contextId);
    if (cached !== undefined) return Promise.resolve(cached);
    const pending = speciesListsPending.get(contextId);
    if (pending !== undefined) return pending;
  } else {
    speciesListsCache.delete(contextId);
    speciesListsPending.delete(contextId);
  }
  const request: Promise<SpeciesLists> = fetchCanonicalSpeciesLists(fetchForm).then(
    (lists) => {
      if (speciesListsPending.get(contextId) === request) {
        speciesListsPending.delete(contextId);
        speciesListsCache.set(contextId, lists);
      }
      return lists;
    },
    (cause) => {
      if (speciesListsPending.get(contextId) === request) speciesListsPending.delete(contextId);
      throw cause;
    }
  );
  speciesListsPending.set(contextId, request);
  return request;
}

// ---------------------------------------------------------------------------
// Plot bundle prefetch LRU (max 6 plots per contextId, in-flight dedup)
// ---------------------------------------------------------------------------

export function peekPlotBundle<T>(contextId: string, plotNumber: string): T | undefined {
  if (!contextId || !plotNumber) return undefined;
  const ctxMap = plotBundlesCache.get(contextId);
  if (!ctxMap) return undefined;
  return lruGet(ctxMap, plotNumber) as T | undefined;
}

export function invalidatePlotBundle(contextId: string, plotNumber?: string): void {
  if (!contextId) return;
  if (plotNumber !== undefined) {
    const ctxMap = plotBundlesCache.get(contextId);
    if (ctxMap) {
      ctxMap.delete(plotNumber);
      if (ctxMap.size === 0) plotBundlesCache.delete(contextId);
    }
    plotBundlesPending.delete(contextKey(contextId, plotNumber));
    return;
  }
  plotBundlesCache.delete(contextId);
  evictMapEntriesByContext(plotBundlesPending, contextId);
}

export function getCachedPlotBundle<T>(
  contextId: string,
  plotNumber: string,
  fetcher: () => Promise<T>
): Promise<T> {
  if (!contextId || !plotNumber) {
    return invokeFetcher(fetcher);
  }
  const cached = peekPlotBundle<T>(contextId, plotNumber);
  if (cached !== undefined) return Promise.resolve(cached);
  const pendingKey = contextKey(contextId, plotNumber);
  const pending = plotBundlesPending.get(pendingKey);
  if (pending !== undefined) return pending as Promise<T>;
  const request: Promise<T> = invokeFetcher(fetcher).then(
      (bundle) => {
        if (plotBundlesPending.get(pendingKey) === request) {
          plotBundlesPending.delete(pendingKey);
          let ctxMap = plotBundlesCache.get(contextId);
          if (!ctxMap) {
            ctxMap = new Map<string, unknown>();
            plotBundlesCache.set(contextId, ctxMap);
          }
          lruSet(ctxMap, plotNumber, bundle, PLOT_BUNDLE_LRU_LIMIT);
        }
        return bundle;
      },
      (cause) => {
        if (plotBundlesPending.get(pendingKey) === request) plotBundlesPending.delete(pendingKey);
        throw cause;
      }
    );
  plotBundlesPending.set(pendingKey, request);
  return request;
}

export function prefetchPlotBundle<T>(
  contextId: string,
  plotNumber: string,
  fetcher: () => Promise<T>
): Promise<T | undefined> {
  if (!contextId || !plotNumber) return Promise.resolve(undefined);
  const cached = peekPlotBundle<T>(contextId, plotNumber);
  if (cached !== undefined) return Promise.resolve(cached);
  return getCachedPlotBundle(contextId, plotNumber, fetcher).catch(() => undefined);
}

// ---------------------------------------------------------------------------
// Test reset helper
// ---------------------------------------------------------------------------

export function resetEntryReferenceCachesForTest(): void {
  globalCatalogues.clear();
  globalCataloguePending.clear();
  invalidateBECCache();
  coordinateModeCache = undefined;
  coordinateModePending = null;
  workingUnitModeCache = undefined;
  workingUnitModePending = null;
  workingUnitChoicesCache.clear();
  workingUnitChoicesPending.clear();
  contextCapabilitiesCache.clear();
  contextValuesCache.clear();
  contextValuesPending.clear();
  speciesListsCache.clear();
  speciesListsPending.clear();
  plotBundlesCache.clear();
  plotBundlesPending.clear();
}
