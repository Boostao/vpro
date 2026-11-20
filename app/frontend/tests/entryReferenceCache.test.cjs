const assert = require('node:assert/strict');
const { test } = require('node:test');
const { loadTypeScript } = require('./svelteTestHelpers.cjs');

function createHarness() {
  const evalCache = new Map();
  const registry = loadTypeScript('shared/contextSessionRegistry.ts', {}, {}, evalCache);
  const cache = loadTypeScript('entry/entryReferenceCache.ts', {}, {}, evalCache);
  const bec = loadTypeScript('entry/becEditor.ts', {}, {}, evalCache);
  const quality = loadTypeScript('entry/qualityEditor.ts', {}, {}, evalCache);
  const catalogueLookup = loadTypeScript('entry/catalogueLookup.ts', {}, {}, evalCache);
  const workingUnit = loadTypeScript('entry/workingUnitEditor.ts', {}, {}, evalCache);
  const coordEditor = loadTypeScript('entry/coordinateEditor.ts', {}, {}, evalCache);
  const coordConv = loadTypeScript('entry/coordinateConversion.ts', {}, {}, evalCache);
  cache.resetEntryReferenceCachesForTest();
  return { evalCache, registry, cache, bec, quality, catalogueLookup, workingUnit, coordEditor, coordConv };
}

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
}

test('global catalogues: freeze arrays, deduplicate in-flight fetches, never cache rejections, and support force/invalidate', async () => {
  const { cache } = createHarness();
  let calls = 0;
  const gate = deferred();

  const p1 = cache.getCachedGlobalCatalogue('plotQuality', () => {
    calls += 1;
    return gate.promise;
  });
  const p2 = cache.getCachedGlobalCatalogue('plotQuality', () => {
    calls += 1;
    return Promise.resolve([{ code: 'SHOULD_NOT_RUN' }]);
  });
  assert.equal(calls, 1);
  assert.equal(cache.peekGlobalCatalogue('plotQuality'), undefined);

  gate.resolve([{ code: 'Good' }, { code: 'Fair' }]);
  const [r1, r2] = await Promise.all([p1, p2]);
  assert.equal(r1, r2);
  assert.equal(Object.isFrozen(r1), true);
  assert.equal(cache.peekGlobalCatalogue('plotQuality'), r1);

  // Warm hit does not call fetcher
  const r3 = await cache.getCachedGlobalCatalogue('plotQuality', async () => {
    calls += 1;
    return [];
  });
  assert.equal(calls, 1);
  assert.equal(r3, r1);

  // Rejected promise is never cached; retry succeeds
  let failOnce = true;
  await assert.rejects(
    cache.getCachedGlobalCatalogue('failingList', async () => {
      if (failOnce) {
        failOnce = false;
        throw new Error('catalogue unavailable');
      }
      return [{ code: 'OK' }];
    }),
    /catalogue unavailable/
  );
  assert.equal(cache.peekGlobalCatalogue('failingList'), undefined);
  const recovered = await cache.getCachedGlobalCatalogue('failingList', async () => [{ code: 'OK' }]);
  assert.equal(recovered.length, 1);
  assert.equal(cache.peekGlobalCatalogue('failingList'), recovered);

  // Force refresh bypasses & replaces cache
  const forced = await cache.getCachedGlobalCatalogue('plotQuality', async () => [{ code: 'Updated' }], true);
  assert.deepEqual([...forced], [{ code: 'Updated' }]);
  assert.equal(cache.peekGlobalCatalogue('plotQuality'), forced);

  // Invalidating while in-flight prevents late stale resolution from polluting cache
  const staleGate = deferred();
  const stalePromise = cache.getCachedGlobalCatalogue('staleKey', () => staleGate.promise);
  cache.invalidateGlobalCatalogue('staleKey');
  staleGate.resolve([{ code: 'STALE' }]);
  await stalePromise;
  assert.equal(cache.peekGlobalCatalogue('staleKey'), undefined);

  // Clear all global catalogues
  cache.invalidateGlobalCatalogue();
  assert.equal(cache.peekGlobalCatalogue('plotQuality'), undefined);
  assert.equal(cache.peekGlobalCatalogue('failingList'), undefined);
});

test('BEC LRU caches zones globally, distinguishes null vs "null", evicts least-recently-used beyond 64 keys, and avoids busy flash in BECLookup', async () => {
  const { cache, bec } = createHarness();
  let zoneCalls = 0;
  let subCalls = 0;
  let seriesCalls = 0;

  const zones = await cache.getCachedBECZones(async () => {
    zoneCalls += 1;
    return [{ zone: 'CWH', description: 'Coastal Western Hemlock' }];
  });
  assert.equal(Object.isFrozen(zones), true);
  assert.equal(cache.peekBECZones(), zones);

  // Distinguish null vs literal "null"
  const nullSub = await cache.getCachedBECSubZones(null, async () => [{ zone: null, subZone: null, description: null }]);
  const literalNullSub = await cache.getCachedBECSubZones('null', async () => [
    { zone: 'null', subZone: 'x', description: 'literal' },
  ]);
  assert.notEqual(nullSub, literalNullSub);
  assert.equal(cache.peekBECSubZones(null), nullSub);
  assert.equal(cache.peekBECSubZones('null'), literalNullSub);

  // Fill 64 siteSeries keys: k0..k63
  for (let i = 0; i < 64; i += 1) {
    await cache.getCachedBECSiteSeries('CWH', `s${i}`, async () => [{ rowId: String(i), siteSeries: '01' }]);
  }
  assert.ok(cache.peekBECSiteSeries('CWH', 's0')); // Touch s0 so s1 becomes LRU!
  await cache.getCachedBECSiteSeries('CWH', 's64', async () => [{ rowId: '64', siteSeries: '01' }]);
  assert.ok(cache.peekBECSiteSeries('CWH', 's0'), 'touched s0 must survive LRU eviction');
  assert.equal(cache.peekBECSiteSeries('CWH', 's1'), undefined, 'least-recently-used s1 must be evicted');
  assert.ok(cache.peekBECSiteSeries('CWH', 's64'));

  // BECLookup sync cache hit: 0 RPCs and 0 busy:true publications
  cache.invalidateBECCache();
  assert.equal(cache.peekBECZones(), undefined);
  assert.equal(cache.peekBECSubZones(null), undefined);
  assert.equal(cache.peekBECSiteSeries('CWH', 's0'), undefined);

  const states = [];
  const api = {
    zones: () =>
      cache.getCachedBECZones(async () => {
        zoneCalls += 1;
        return [{ zone: 'BG', description: 'Bunchgrass' }];
      }),
    subZones: (z) =>
      cache.getCachedBECSubZones(z, async () => {
        subCalls += 1;
        return [{ zone: z, subZone: 'xh1', description: null }];
      }),
    siteSeries: (z, sz) =>
      cache.getCachedBECSiteSeries(z, sz, async () => {
        seriesCalls += 1;
        return [{ rowId: '1', sourceId: null, zone: z, subZone: sz, siteSeries: '01', description: null, region: null, variant: null, phase: null }];
      }),
  };
  const lookupCache = {
    peekZones: () => cache.peekBECZones(),
    peekSubZones: (z) => cache.peekBECSubZones(z),
    peekSiteSeries: (z, sz) => cache.peekBECSiteSeries(z, sz),
    invalidate: () => cache.invalidateBECCache(),
  };

  const first = new bec.BECLookup(api, (v) => states.push(v), undefined, lookupCache);
  await first.refresh('BG', 'xh1');
  assert.equal(first.snapshot().ready, true);
  const countsAfterCold = { zoneCalls, subCalls, seriesCalls };

  // Second BECLookup instance for same (zone, subZone): 0 RPCs, 0 busy flash!
  const warmStates = [];
  const second = new bec.BECLookup(api, (v) => warmStates.push(v), undefined, lookupCache);
  await second.refresh('BG', 'xh1');
  assert.deepEqual({ zoneCalls, subCalls, seriesCalls }, countsAfterCold);
  assert.equal(warmStates.some((s) => s.busy), false);
  assert.equal(second.snapshot().ready, true);
  assert.equal(second.snapshot().siteSeries.length, 1);

  // Explicit force refresh invalidates & re-fetches
  await second.refresh('BG', 'xh1', true);
  assert.equal(zoneCalls, countsAfterCold.zoneCalls + 1);
  assert.equal(subCalls, countsAfterCold.subCalls + 1);
  assert.equal(seriesCalls, countsAfterCold.seriesCalls + 1);
});

test('preferences, working unit caches, and WorkingUnitLookup sync warm start', async () => {
  const { cache, workingUnit } = createHarness();

  // Coordinate mode preference cache + error non-caching
  let coordReads = 0;
  await assert.rejects(
    cache.getCachedCoordinateMode(async () => {
      throw new Error('coord mode fail');
    }),
    /coord mode fail/
  );
  assert.equal(cache.peekCoordinateMode(), undefined);
  assert.equal(
    await cache.getCachedCoordinateMode(async () => {
      coordReads += 1;
      return 'dd';
    }),
    'dd'
  );
  assert.equal(await cache.getCachedCoordinateMode(async () => { coordReads += 1; return 'dm'; }), 'dd');
  assert.equal(coordReads, 1);
  cache.setCachedCoordinateMode('dms');
  assert.equal(cache.peekCoordinateMode(), 'dms');

  // Working unit mode + master + context-scoped env/su choices
  const masterRows = await cache.getCachedMasterWorkingUnitChoices(async () => [{ rowId: '1', code: 'M1', origin: 'master', sourceId: null, description: null, scientificName: null, level: 1, selectable: true, diagnostic: '' }]);
  assert.equal(Object.isFrozen(masterRows), true);
  assert.equal(cache.peekMasterWorkingUnitChoices(), masterRows);

  const envRows = await cache.getCachedWorkingUnitChoices('ctx-a', 'env', async () => [
    { rowId: '2', code: 'E1', origin: 'env', sourceId: null, description: null, scientificName: null, level: null, selectable: true, diagnostic: '' },
  ]);
  const suRows = await cache.getCachedWorkingUnitChoices('ctx-a', 'su', async () => [
    { rowId: '3', code: 'S1', origin: 'su', sourceId: null, description: null, scientificName: null, level: null, selectable: true, diagnostic: '' },
  ]);
  assert.equal(cache.peekWorkingUnitChoices('ctx-a', 'env'), envRows);
  assert.equal(cache.peekWorkingUnitChoices('ctx-a', 'su'), suRows);

  // Empty contextId does not cache env/su
  let emptyEnvCalls = 0;
  await cache.getCachedWorkingUnitChoices('', 'env', async () => { emptyEnvCalls += 1; return []; });
  await cache.getCachedWorkingUnitChoices('', 'env', async () => { emptyEnvCalls += 1; return []; });
  assert.equal(emptyEnvCalls, 2);
  assert.equal(cache.peekWorkingUnitChoices('', 'env'), undefined);

  // Mode-specific invalidation keeps sibling mode intact
  cache.invalidateWorkingUnitChoices('ctx-a', 'env');
  assert.equal(cache.peekWorkingUnitChoices('ctx-a', 'env'), undefined);
  assert.equal(cache.peekWorkingUnitChoices('ctx-a', 'su'), suRows);

  // WorkingUnitLookup warms synchronously from cache with 0 RPCs and 0 busy flash
  cache.setCachedWorkingUnitMode({ mode: 'su', warning: null });
  let apiCalls = 0;
  const wuEvents = [];
  const wuLookup = new workingUnit.WorkingUnitLookup(
    {
      getMode: async () => { apiCalls += 1; return { mode: 'su', warning: null }; },
      setMode: async (m) => { apiCalls += 1; return { mode: m, warning: null }; },
      choices: async () => { apiCalls += 1; return suRows; },
      master: async () => { apiCalls += 1; return masterRows; },
    },
    (v) => wuEvents.push(v),
    { mode: null },
    undefined,
    {
      peekMode: () => cache.peekWorkingUnitMode(),
      peekChoices: (m) => cache.peekWorkingUnitChoices('ctx-a', m),
      peekMaster: () => cache.peekMasterWorkingUnitChoices(),
    }
  );
  assert.equal(wuLookup.snapshot().ready, true);
  assert.equal(wuLookup.snapshot().masterReady, true);
  assert.equal(wuLookup.snapshot().busy, false);
  assert.equal(wuLookup.snapshot().choices, suRows);
  assert.equal(wuLookup.snapshot().master, masterRows);
  await wuLookup.refresh();
  assert.equal(apiCalls, 0);
  assert.equal(wuEvents.some((e) => e.busy), false);
});

test('deduplicated species lists make only 3 canonical RPCs for all 6 form keys and never cache failures', async () => {
  const { cache } = createHarness();
  const fetchedForms = [];
  const gate = deferred();

  const fetchForm = async (form) => {
    fetchedForms.push(form);
    await gate.promise;
    return [{ code: `CODE_${form}`, scientificName: null, lifeform: 1, englishName: null, codeType: 'U' }];
  };

  // Concurrent calls deduplicate to 3 total fetches (never 6 or 12)
  const p1 = cache.getCachedSpeciesLists('ctx-spp', fetchForm);
  const p2 = cache.getCachedSpeciesLists('ctx-spp', fetchForm);
  gate.resolve();
  const [lists1, lists2] = await Promise.all([p1, p2]);

  assert.equal(lists1, lists2);
  assert.deepEqual(fetchedForms, ['SubVegAXL_BC', 'SubVegCXL', 'SubVegDXL']);
  assert.equal(Object.isFrozen(lists1), true);
  assert.equal(Object.isFrozen(lists1.SubVegAXL_BC), true);
  assert.equal(lists1.SubVegAXL, lists1.SubVegAXL_BC);
  assert.equal(lists1.SubVegAhtXL, lists1.SubVegAXL_BC);
  assert.equal(lists1.SubVegChtXL, lists1.SubVegCXL);
  assert.equal(lists1.SubVegDXL[0].code, 'CODE_SubVegDXL');
  assert.equal(cache.peekSpeciesLists('ctx-spp'), lists1);

  // Failure on one of the 3 forms rejects and does not cache
  cache.invalidateSpeciesLists('ctx-spp');
  assert.equal(cache.peekSpeciesLists('ctx-spp'), undefined);
  await assert.rejects(
    cache.getCachedSpeciesLists('ctx-spp', async (form) => {
      if (form === 'SubVegCXL') throw new Error('boom');
      return [];
    }),
    /boom/
  );
  assert.equal(cache.peekSpeciesLists('ctx-spp'), undefined);

  // Null return rejects and does not cache
  await assert.rejects(
    cache.getCachedSpeciesLists('ctx-spp', async (form) => (form === 'SubVegDXL' ? null : [])),
    /Species metadata for SubVegDXL was not returned/
  );
  assert.equal(cache.peekSpeciesLists('ctx-spp'), undefined);

  // Global invalidateSpeciesLists() with no argument clears all contexts
  await cache.getCachedSpeciesLists('ctx-1', async () => []);
  await cache.getCachedSpeciesLists('ctx-2', async () => []);
  cache.invalidateSpeciesLists();
  assert.equal(cache.peekSpeciesLists('ctx-1'), undefined);
  assert.equal(cache.peekSpeciesLists('ctx-2'), undefined);
});

test('plot bundle prefetch LRU (max 6 per contextId), in-flight dedup, error non-caching, and invalidation', async () => {
  const { cache } = createHarness();

  // In-flight dedup between prefetchPlotBundle and getCachedPlotBundle
  let fetchCount = 0;
  const gate = deferred();
  const prefetchPromise = cache.prefetchPlotBundle('ctx-1', '00337', () => {
    fetchCount += 1;
    return gate.promise;
  });
  const loadPromise = cache.getCachedPlotBundle('ctx-1', '00337', () => {
    fetchCount += 1;
    return Promise.resolve({ header: { plotNumber: 'SHOULD_NOT_RUN' } });
  });
  assert.equal(fetchCount, 1);

  const bundle337 = { header: { plotNumber: '00337' } };
  gate.resolve(bundle337);
  const [prefetched, loaded] = await Promise.all([prefetchPromise, loadPromise]);
  assert.equal(prefetched, bundle337);
  assert.equal(loaded, bundle337);
  assert.equal(cache.peekPlotBundle('ctx-1', '00337'), bundle337);

  // Prefetch failure does not throw unhandled rejection and does not cache
  const failedPrefetch = await cache.prefetchPlotBundle('ctx-1', 'BAD1', async () => {
    throw new Error('transient read error');
  });
  assert.equal(failedPrefetch, undefined);
  assert.equal(cache.peekPlotBundle('ctx-1', 'BAD1'), undefined);

  // LRU eviction beyond 6 plots per contextId (00337 is #1, add P2..P6 -> 6 total)
  for (let i = 2; i <= 6; i += 1) {
    await cache.getCachedPlotBundle('ctx-1', `P${i}`, async () => ({ plot: `P${i}` }));
  }
  // Touch 00337 so P2 becomes least-recently-used
  assert.equal(cache.peekPlotBundle('ctx-1', '00337'), bundle337);
  await cache.getCachedPlotBundle('ctx-1', 'P7', async () => ({ plot: 'P7' }));
  assert.equal(cache.peekPlotBundle('ctx-1', '00337'), bundle337, 'recently peeked 00337 stays cached');
  assert.equal(cache.peekPlotBundle('ctx-1', 'P2'), undefined, 'oldest untouched plot P2 is evicted');
  assert.ok(cache.peekPlotBundle('ctx-1', 'P7'));

  // Other context has independent 6-plot budget
  await cache.getCachedPlotBundle('ctx-2', 'OTHER1', async () => ({ plot: 'OTHER1' }));
  assert.ok(cache.peekPlotBundle('ctx-2', 'OTHER1'));

  // Invalidate single plot vs whole context
  cache.invalidatePlotBundle('ctx-1', 'P7');
  assert.equal(cache.peekPlotBundle('ctx-1', 'P7'), undefined);
  assert.equal(cache.peekPlotBundle('ctx-1', '00337'), bundle337);

  // Invalidating in-flight plot prevents stale resolution from landing in cache
  const staleGate = deferred();
  const staleLoad = cache.getCachedPlotBundle('ctx-1', 'P9', () => staleGate.promise);
  cache.invalidatePlotBundle('ctx-1', 'P9');
  staleGate.resolve({ plot: 'STALE_P9' });
  await staleLoad;
  assert.equal(cache.peekPlotBundle('ctx-1', 'P9'), undefined);

  cache.invalidatePlotBundle('ctx-1');
  assert.equal(cache.peekPlotBundle('ctx-1', '00337'), undefined);
  assert.ok(cache.peekPlotBundle('ctx-2', 'OTHER1'));
});

test('onContextDisposed evicts all context-scoped entries for disposed context while keeping sibling contexts and global caches', async () => {
  const { registry, cache } = createHarness();

  await cache.getCachedGlobalCatalogue('globalCat', async () => [{ code: 'G1' }]);
  await cache.getCachedBECZones(async () => [{ zone: 'ICH', description: null }]);
  cache.setCachedCoordinateMode('dm');
  cache.setCachedWorkingUnitMode({ mode: 'env', warning: null });
  await cache.getCachedMasterWorkingUnitChoices(async () => []);

  for (const ctx of ['ctx-old', 'ctx-keep']) {
    await cache.getCachedWorkingUnitChoices(ctx, 'env', async () => []);
    cache.setCachedContextCapabilities(ctx, {
      headerCapabilities: { plotNumber: true },
      childCapabilities: { Veg: {}, Humus: {}, Mineral: {}, Other: {} },
      masterAllowed: true,
    });
    await cache.getCachedContextValue(ctx, 'soilSuggestions', async () => [{ code: 'S1' }]);
    await cache.getCachedSpeciesLists(ctx, async () => []);
    await cache.getCachedPlotBundle(ctx, 'P1', async () => ({ plot: 'P1' }));
  }

  registry.onContextDisposed('ctx-old');

  // ctx-old completely evicted
  assert.equal(cache.peekWorkingUnitChoices('ctx-old', 'env'), undefined);
  assert.equal(cache.getCachedContextCapabilities('ctx-old'), undefined);
  assert.equal(cache.peekContextValue('ctx-old', 'soilSuggestions'), undefined);
  assert.equal(cache.peekSpeciesLists('ctx-old'), undefined);
  assert.equal(cache.peekPlotBundle('ctx-old', 'P1'), undefined);

  // ctx-keep untouched
  assert.ok(cache.peekWorkingUnitChoices('ctx-keep', 'env'));
  assert.ok(cache.getCachedContextCapabilities('ctx-keep'));
  assert.ok(cache.peekContextValue('ctx-keep', 'soilSuggestions'));
  assert.ok(cache.peekSpeciesLists('ctx-keep'));
  assert.ok(cache.peekPlotBundle('ctx-keep', 'P1'));

  // Global caches untouched
  assert.ok(cache.peekGlobalCatalogue('globalCat'));
  assert.ok(cache.peekBECZones());
  assert.equal(cache.peekCoordinateMode(), 'dm');
  assert.equal(cache.peekWorkingUnitMode().mode, 'env');
  assert.ok(cache.peekMasterWorkingUnitChoices());

  // invalidateMasterBECPolicy clears context capabilities
  cache.invalidateMasterBECPolicy();
  assert.equal(cache.getCachedContextCapabilities('ctx-keep'), undefined);

  // Generic context-scoped values: key-specific & projectIdChoices invalidation
  await cache.getCachedContextValue('ctx-keep', 'projectIdChoices', async () => ['P1', 'P2']);
  await cache.getCachedContextValue('ctx-keep', 'attributeSuggestions', async () => [{ code: 'A1' }]);
  assert.equal(Object.isFrozen(cache.peekContextValue('ctx-keep', 'projectIdChoices')), true);
  cache.invalidateProjectIdChoices('ctx-keep');
  assert.equal(cache.peekContextValue('ctx-keep', 'projectIdChoices'), undefined);
  assert.ok(cache.peekContextValue('ctx-keep', 'attributeSuggestions'));
  cache.invalidateContextValue('ctx-keep', 'attributeSuggestions');
  assert.equal(cache.peekContextValue('ctx-keep', 'attributeSuggestions'), undefined);
  await cache.getCachedContextValue('ctx-keep', 'k1', async () => 1);
  await cache.getCachedContextValue('ctx-keep', 'k2', async () => 2);
  cache.invalidateContextValue('ctx-keep');
  assert.equal(cache.peekContextValue('ctx-keep', 'k1'), undefined);
  assert.equal(cache.peekContextValue('ctx-keep', 'k2'), undefined);
});

test('CatalogueLookup with cacheKey hits cache synchronously on remount and bypasses on force=true', async () => {
  const { cache, catalogueLookup } = createHarness();
  let calls = 0;
  const fetchRows = async (force) => {
    calls += 1;
    return [{ rowId: String(calls), code: force ? 'FORCED' : 'CACHED', listName: 'PlotQualitySite', listFilter: null, itemOrder: 1, description: null, fieldUsedIn: null, validateLoops: null, validate: null, note: null, flag: null, selectable: true, diagnostic: '' }];
  };

  const first = new catalogueLookup.CatalogueLookup(fetchRows, () => {}, 'Quality', 'plotQuality');
  assert.equal(first.snapshot().ready, false);
  await first.refresh();
  assert.equal(calls, 1);
  assert.equal(first.snapshot().ready, true);
  assert.equal(first.snapshot().choices[0].code, 'CACHED');

  // Second instance mounts with warm cache: ready immediately, 0 RPCs, 0 busy flash
  const secondEvents = [];
  const second = new catalogueLookup.CatalogueLookup(fetchRows, (v) => secondEvents.push(v), 'Quality', 'plotQuality');
  assert.equal(second.snapshot().ready, true);
  assert.equal(second.snapshot().busy, false);
  await second.refresh();
  assert.equal(calls, 1);
  assert.equal(secondEvents.some((e) => e.busy), false);

  // Explicit force=true invalidates cache and re-fetches
  await second.refresh(true);
  assert.equal(calls, 2);
  assert.equal(second.snapshot().choices[0].code, 'FORCED');
  assert.equal(cache.peekGlobalCatalogue('plotQuality')[0].code, 'FORCED');
});

test('createSpatialCoordinatePort caches coordinate mode and applies exact Go-parity DD fast path', async () => {
  const { coordConv, coordEditor } = createHarness();
  let getModeCalls = 0;
  let setModeCalls = 0;
  const decomposeCalls = [];

  const mockService = {
    async GetCoordinateMode() {
      getModeCalls += 1;
      return 'dd';
    },
    async SetCoordinateMode() {
      setModeCalls += 1;
    },
    async DecomposeCoordinate(value, mode) {
      decomposeCalls.push({ value, mode });
      if (value !== null && (!Number.isFinite(value) || Math.abs(value) > 180)) {
        throw new Error('coordinate must be finite with magnitude no greater than 180');
      }
      return { degrees: value === null ? null : Math.trunc(Math.abs(value)), minutes: 30, seconds: null, negative: (value ?? 0) < 0 };
    },
    async ConvertCoordinate() {
      return 0;
    },
  };
  const modes = { CoordinateModeDD: 'dd', CoordinateModeDM: 'dm', CoordinateModeDMS: 'dms' };

  const port1 = coordConv.createSpatialCoordinatePort(mockService, modes);
  const port2 = coordConv.createSpatialCoordinatePort(mockService, modes);

  assert.equal(await port1.getMode(), 'dd');
  assert.equal(await port2.getMode(), 'dd');
  assert.equal(getModeCalls, 1, 'second port reuses cached coordinate mode');

  // DD fast path: null, -0, valid numbers <= 180 resolve without DecomposeCoordinate RPC
  assert.deepEqual({ ...(await port1.decompose(null, 'dd')) }, { degrees: null, minutes: null, seconds: null, negative: false });
  const negZero = await port1.decompose(-0, 'dd');
  assert.equal(Object.is(negZero.degrees, -0), true);
  assert.equal(negZero.negative, false);
  assert.deepEqual({ ...(await port1.decompose(-180, 'dd')) }, { degrees: -180, minutes: null, seconds: null, negative: false });
  assert.deepEqual({ ...(await port1.decompose(54.25, 'dd')) }, { degrees: 54.25, minutes: null, seconds: null, negative: false });
  assert.equal(decomposeCalls.length, 0);

  // Out-of-range DD and DM/DMS delegate to SpatialService.DecomposeCoordinate
  await assert.rejects(port1.decompose(180.001, 'dd'), /magnitude no greater than 180/);
  await assert.rejects(port1.decompose(Number.NaN, 'dd'), /magnitude no greater than 180/);
  await port1.decompose(54.5, 'dm');
  assert.equal(decomposeCalls.length, 3);

  // CoordinateEditor with cached DD mode + DD fast path: 0 busy flash on syncDraft
  const busyEvents = [];
  const editor = new coordEditor.CoordinateEditor(port1, {
    state() {},
    busy: (b) => busyEvents.push(b),
    dirty() {},
    value() {},
    validation() {},
    error() {},
  });
  editor.syncDraft(49.25, -123.1, {});
  await editor.initialize();
  assert.equal(busyEvents.includes(true), false);
  assert.equal(editor.snapshot().axes.latitude.buffers.degrees, '49.25');
  assert.equal(editor.snapshot().axes.longitude.buffers.degrees, '-123.1');

  // setMode persists and updates cache
  await port1.setMode('dm');
  assert.equal(setModeCalls, 1);
  assert.equal(await port2.getMode(), 'dm');
  assert.equal(getModeCalls, 1);
});

test('userSetupModal invalidates cached Master BEC policy after SetUserName / SetCurrentUser', async () => {
  const { evalCache, cache } = createHarness();
  const sampleStatus = { userName: 'alice', accredited: true, masterBecAllowed: true, inUserRestrictions: false, canEditBecSiteUnit: true };
  const userSetup = loadTypeScript(
    'shell/userSetupModal.ts',
    {
      '../../bindings/github.com/boostao/vpro/app': {
        ContextService: {
          GetUserSetup: async () => sampleStatus,
          SetUserName: async () => sampleStatus,
        },
        PlotEntryService: {
          SetCurrentUser: async () => {},
          UserAccreditationStatus: async () => sampleStatus,
        },
      },
    },
    {},
    evalCache
  );

  const caps = {
    headerCapabilities: { plotNumber: true },
    childCapabilities: { Veg: {}, Humus: {}, Mineral: {}, Other: {} },
    masterAllowed: false,
  };
  cache.setCachedContextCapabilities('ctx-u1', caps);
  await userSetup.defaultUserSetupPort.setUserName('ctx-u1', 'alice');
  assert.equal(cache.getCachedContextCapabilities('ctx-u1'), undefined);

  cache.setCachedContextCapabilities('ctx-u2', caps);
  await userSetup.defaultUserSetupPort.setUserName('', 'bob');
  assert.equal(cache.getCachedContextCapabilities('ctx-u2'), undefined);
});
