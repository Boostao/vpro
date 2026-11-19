const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');
const { compile } = require('svelte/compiler');
const { render } = require('svelte/server');
const { loadTypeScript, serverComponent, componentFunctions, srcPath } = require('./svelteTestHelpers.cjs');

const read = name => readFileSync(srcPath(name), 'utf8');

const quality = loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });

const wailsCalls = [];
const bindingsStub = new Proxy({}, {
  get: (_t, service) => new Proxy({}, {
    get: (_s, method) => (...args) => {
      wailsCalls.push({ methodName: `main.${String(service)}.${String(method)}`, args });
      return Promise.resolve({ ok: true });
    },
  }),
});

const projectAdmin = loadTypeScript('projectAdminWorkbench.ts', {
  '../../bindings/github.com/boostao/vpro/app': bindingsStub,
  './qualityEditor': quality,
});

const cloudSync = loadTypeScript('cloudSyncWorkbench.ts', {
  '../../bindings/github.com/boostao/vpro/app': bindingsStub,
  './qualityEditor': quality,
  './projectAdminWorkbench': projectAdmin,
});

test('all 20 defaultCloudSyncPort methods call exact main.ContextService.* Wails endpoints', async () => {
  wailsCalls.length = 0;
  const p = cloudSync.defaultCloudSyncPort;

  await p.getCloudSyncConfigStatus();
  await p.configureCloudSyncSession({ roleMode: 'contributor' });
  await p.testCloudConnection();
  await p.bootstrapCloudSchemas();
  await p.publishStandardsToCloud('ctx-1', { becVersion: '13', taxonomyVersion: '19' });
  await p.seedBECMasterBaseline({ sourceDbPath: '/data/BECMaster.db', replaceExisting: false });
  await p.pullCloudStandards('ctx-1');
  await p.previewBECMasterSubset({ zones: ['CWH'], plotNumbers: ['00337'] });
  await p.pullBECMasterSubset('ctx-1', {
    filter: { zones: ['CWH'] },
    targetProject: 'CWH_2026',
    activateOnSuccess: true,
  });
  await p.previewStagingSubmission('ctx-1', false);
  await p.submitProjectToStaging('ctx-1', { submittedBy: 'Ecologist' });
  await p.listStagingSubmissions({ status: 'pending', limit: 25 });
  await p.getStagingSubmissionDetail('sub-001');
  await p.previewStagingToMasterMerge({ submissionId: 'sub-001' });
  await p.executeStagingToMasterMerge({
    submissionId: 'sub-001',
    expectedPreviewDigest: 'sha256-preview-1',
  });
  await p.rejectStagingSubmission({ submissionId: 'sub-001', reviewerNotes: 'Missing horizon depths' });
  await p.createBECMasterSnapshot('ctx-1', { snapshotTag: 'BECMaster_2026_11' });
  await p.listBECMasterSnapshots();
  await p.listBECMasterDownloadLog(50);
  await p.verifyBECMasterAuditChain(250);

  assert.equal(wailsCalls.length, 20);
  assert.deepEqual(
    wailsCalls.map(c => c.methodName),
    [
      'main.ContextService.GetCloudSyncConfigStatus',
      'main.ContextService.ConfigureCloudSyncSession',
      'main.ContextService.TestCloudConnection',
      'main.ContextService.BootstrapCloudSchemas',
      'main.ContextService.PublishStandardsToCloud',
      'main.ContextService.SeedBECMasterBaseline',
      'main.ContextService.PullCloudStandards',
      'main.ContextService.PreviewBECMasterSubset',
      'main.ContextService.PullBECMasterSubset',
      'main.ContextService.PreviewStagingSubmission',
      'main.ContextService.SubmitProjectToStaging',
      'main.ContextService.ListStagingSubmissions',
      'main.ContextService.GetStagingSubmissionDetail',
      'main.ContextService.PreviewStagingToMasterMerge',
      'main.ContextService.ExecuteStagingToMasterMerge',
      'main.ContextService.RejectStagingSubmission',
      'main.ContextService.CreateBECMasterSnapshot',
      'main.ContextService.ListBECMasterSnapshots',
      'main.ContextService.ListBECMasterDownloadLog',
      'main.ContextService.VerifyBECMasterAuditChain',
    ]
  );

  assert.deepEqual(wailsCalls[4].args, ['ctx-1', { becVersion: '13', taxonomyVersion: '19' }]);
  assert.deepEqual(wailsCalls[6].args, ['ctx-1']);
  assert.deepEqual(wailsCalls[7].args, [{ zones: ['CWH'], plotNumbers: ['00337'] }]);
  assert.deepEqual(wailsCalls[9].args, ['ctx-1', false]);
  assert.deepEqual(wailsCalls[12].args, ['sub-001']);
  assert.deepEqual(wailsCalls[18].args, [50]);
  assert.deepEqual(wailsCalls[19].args, [250]);
});

test('subset filter, bbox, compliance gate, custodian-protected field, and snapshot tag helpers enforce VPro invariants', () => {
  // Literal leading-zero PlotNumber preservation
  const built = cloudSync.buildSubsetFilterDraft({
    zonesRaw: ' CWH , ICH ',
    subzonesRaw: 'vm1',
    projectIdsRaw: '',
    plotNumbersRaw: '00337, 108050',
    bboxRaw: '-133.2, 52.1, -131.0, 54.4',
    limitRaw: '250',
    allowFullCheckout: false,
  });
  assert.equal(built.error, null);
  assert.deepEqual(structuredClone(built.filter), {
    zones: ['CWH', 'ICH'],
    subzones: ['vm1'],
    plotNumbers: ['00337', '108050'],
    bbox: [-133.2, 52.1, -131.0, 54.4],
    limit: 250,
  });

  // Empty filter blocked unless allowFullCheckout is true
  const emptyBlocked = cloudSync.buildSubsetFilterDraft({
    zonesRaw: '',
    subzonesRaw: '',
    projectIdsRaw: '',
    plotNumbersRaw: '',
    bboxRaw: '',
  });
  assert.match(emptyBlocked.error, /Specify at least one regional filter/);

  const fullAllowed = cloudSync.buildSubsetFilterDraft({
    zonesRaw: '',
    subzonesRaw: '',
    projectIdsRaw: '',
    plotNumbersRaw: '',
    bboxRaw: '',
    allowFullCheckout: true,
  });
  assert.equal(fullAllowed.error, null);
  assert.deepEqual(structuredClone(fullAllowed.filter), { allowFullCheckout: true });

  // PlotNumber > 7 UTF-16 rejected
  const overlongPlot = cloudSync.buildSubsetFilterDraft({
    zonesRaw: '',
    subzonesRaw: '',
    projectIdsRaw: '',
    plotNumbersRaw: '12345678',
    bboxRaw: '',
  });
  assert.match(overlongPlot.error, /7 UTF-16/);

  // Invalid BBox rejected
  assert.match(cloudSync.parseBboxInput('-120, 55, -125, 56').error, /minLon < maxLon/);
  assert.match(cloudSync.parseBboxInput('-125, 58, -120, 55').error, /minLat < maxLat/);

  // Staging compliance gate
  assert.equal(cloudSync.canUploadStagingSubmission(null, 'custodian', true), false);
  assert.equal(cloudSync.canUploadStagingSubmission({ compliancePassed: false }, 'contributor', true), false);
  assert.equal(cloudSync.canUploadStagingSubmission({ compliancePassed: false }, 'custodian', false), false);
  assert.equal(cloudSync.canUploadStagingSubmission({ compliancePassed: false }, 'custodian', true), true);
  assert.equal(cloudSync.canUploadStagingSubmission({ compliancePassed: true }, 'contributor', false), true);

  // Custodian-protected BEC fields
  for (const field of ['BECSiteUnit', 'BEC_Use', 'GIS_BGC']) {
    assert.equal(cloudSync.isCustodianProtectedConflict({ field, custodianProtected: false }), true);
  }
  assert.equal(cloudSync.isCustodianProtectedConflict({ field: 'SlopeGradient', custodianProtected: false }), false);

  // Snapshot tag validator
  assert.equal(cloudSync.validateSnapshotTagInput('BECMaster_2026.11-rc1'), null);
  assert.match(cloudSync.validateSnapshotTagInput('bad tag/slash'), /ASCII letters/);
});

test('UX-CLOUD-003: numeric input parsers handle number, string, null, undefined, empty, NaN, and negative/out-of-range values without TypeError', () => {
  // 1. buildSubsetFilterDraft limitRaw (Svelte 5 <input type="number"> coerces to number | null)
  for (const [raw, expected] of [
    [5, 5],
    [1, 1],
    ['5', 5],
    ['  250  ', 250],
  ]) {
    const res = cloudSync.buildSubsetFilterDraft({
      zonesRaw: 'CWH',
      subzonesRaw: '',
      projectIdsRaw: '',
      plotNumbersRaw: '',
      bboxRaw: '',
      limitRaw: raw,
    });
    assert.equal(res.error, null);
    assert.deepEqual(structuredClone(res.filter), { zones: ['CWH'], limit: expected });
  }

  for (const emptyVal of [null, undefined, '', '   ']) {
    const withZone = cloudSync.buildSubsetFilterDraft({
      zonesRaw: 'CWH',
      subzonesRaw: '',
      projectIdsRaw: '',
      plotNumbersRaw: '',
      bboxRaw: '',
      limitRaw: emptyVal,
    });
    assert.equal(withZone.error, null);
    assert.deepEqual(structuredClone(withZone.filter), { zones: ['CWH'] });

    const allEmpty = cloudSync.buildSubsetFilterDraft({
      zonesRaw: '',
      subzonesRaw: '',
      projectIdsRaw: '',
      plotNumbersRaw: '',
      bboxRaw: '',
      limitRaw: emptyVal,
    });
    assert.equal(allEmpty.filter, null);
    assert.match(allEmpty.error, /Specify at least one regional filter/);
  }

  for (const badLimit of [0, '0', -1, -5, '-5', 2.5, '2.5', Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY, 1e21, 'abc']) {
    const badRes = cloudSync.buildSubsetFilterDraft({
      zonesRaw: 'CWH',
      subzonesRaw: '',
      projectIdsRaw: '',
      plotNumbersRaw: '',
      bboxRaw: '',
      limitRaw: badLimit,
    });
    assert.equal(badRes.filter, null);
    assert.equal(badRes.error, 'Subset plot limit must be a positive integer.');
  }

  // 2. parseSessionPortInput (Port override 1..65535)
  for (const [raw, expected] of [
    [5433, 5433],
    [1, 1],
    [65535, 65535],
    ['5433', 5433],
    [' 5432 ', 5432],
  ]) {
    assert.deepEqual(structuredClone(cloudSync.parseSessionPortInput(raw)), { port: expected, error: null });
  }

  for (const emptyPort of [null, undefined, '', '   ']) {
    assert.deepEqual(structuredClone(cloudSync.parseSessionPortInput(emptyPort)), { port: undefined, error: null });
  }

  for (const badPort of [0, '0', -1, '-5432', 65536, 70000, '70000', 5432.5, '5432.5', Number.NaN, Number.POSITIVE_INFINITY, 1e21, 'abc']) {
    const res = cloudSync.parseSessionPortInput(badPort);
    assert.equal(res.port, undefined);
    assert.equal(res.error, 'Server port must be an integer between 1 and 65535.');
  }

  // 3. parseAuditChainLimitInput (Audit Limit >= 0, empty -> 0)
  for (const [raw, expected] of [
    [0, 0],
    ['0', 0],
    [100, 100],
    [' 250 ', 250],
    [null, 0],
    [undefined, 0],
    ['', 0],
    ['   ', 0],
  ]) {
    assert.deepEqual(structuredClone(cloudSync.parseAuditChainLimitInput(raw)), { limit: expected, error: null });
  }

  for (const badAudit of [-1, -5, '-5', 1.5, '1.5', Number.NaN, Number.POSITIVE_INFINITY, 1e21, 'abc']) {
    const res = cloudSync.parseAuditChainLimitInput(badAudit);
    assert.equal(res.error, 'Audit limit must be a non-negative integer (0 = all).');
  }
});

test('offline SSR render of CloudSyncWorkbench shows BC Gov bar, Contributor controls, password inputs, and zero leaked secrets', () => {
  const src = read('CloudSyncWorkbench.svelte');
  assert.doesNotMatch(src, /[\u{1F300}-\u{1FAFF}]/u, 'CloudSyncWorkbench must contain zero emojis');
  const compiledClient = compile(src, { filename: 'CloudSyncWorkbench.svelte', generate: 'client' });
  assert.deepEqual(compiledClient.warnings, []);
  const compiledAuth = compile(read('CloudSyncAuthPanel.svelte'), { filename: 'CloudSyncAuthPanel.svelte', generate: 'client' });
  assert.deepEqual(compiledAuth.warnings, []);
  const compiledPull = compile(read('CloudSyncPullPanel.svelte'), { filename: 'CloudSyncPullPanel.svelte', generate: 'client' });
  assert.deepEqual(compiledPull.warnings, []);

  let networkCalledDuringSSR = false;
  const ssrPort = new Proxy(
    {},
    {
      get() {
        return () => {
          networkCalledDuringSSR = true;
          throw new Error('SSR must never invoke CloudSyncPort RPCs');
        };
      },
    }
  );

  const Component = serverComponent(src, 'CloudSyncWorkbench.svelte', {
    './cloudSyncWorkbench': cloudSync,
  });
  const html = render(Component, {
    props: {
      contextId: 'ctx-offline-ssr',
      activeProject: 'HaidaGwaii_2026',
      activeSu: 'HGW_SU',
      port: ssrPort,
    },
  }).body;

  assert.equal(networkCalledDuringSSR, false);
  assert.match(html, /#003366/);
  assert.match(html, /#FCBA19/);
  assert.match(html, /Offline \/ Unprobed/);
  assert.match(html, /Contributor/);
  assert.match(html, /Checkout Regional Subset from BECMaster/);
  assert.match(html, /Submit Active Project to BECMaster Staging/);
  assert.match(html, /HaidaGwaii_2026/);
  assert.doesNotMatch(html, /data-custodian-panel/);

  // Both password inputs must use type="password" and autocomplete="off"
  const passwordInputs = [...html.matchAll(/<input\b[^>]*id="cloud-override-(?:admin-)?password"[^>]*>/g)].map(m => m[0]);
  assert.equal(passwordInputs.length, 2);
  for (const tag of passwordInputs) {
    assert.match(tag, /type="password"/);
    assert.match(tag, /autocomplete="off"/);
  }
  assert.doesNotMatch(html, /postgres:\/\/|postgresql:\/\/|PGPASSWORD/i);
});

test('CloudSyncWorkbench client rune actions are offline-first on mount, detach proxies, clear passwords, enforce compliance, pass merge digest, and honor operationHeld + onDestroy', async () => {
  const client = await import('svelte/internal/client');
  let script = read('CloudSyncWorkbench.svelte').match(/<script lang="ts">([\s\S]*?)<\/script>/)[1];
  script = script.replace(
    'oncontextswitched?: (state: unknown) => void;',
    'oncontextswitched?: (state: unknown) => void; inspect?: (v: any) => void;'
  );
  script = script.replace('oncontextswitched,', 'oncontextswitched, inspect,');
  script += `\n$effect(() => inspect?.({
    getState: () => ({
      busy,
      error,
      statusMessage,
      activeRoleMode,
      overrideHost,
      overridePort,
      overrideDatabase,
      overrideSslMode,
      overrideUser,
      overrideAdminUser,
      overridePassword,
      overrideAdminPassword,
      configStatus,
      connectionReport,
      subsetPreview,
      pullSubsetResult,
      stagingPreflight,
      submitStagingResult,
      submissions,
      selectedSubmissionDetail,
      mergePreview,
      mergeExecuteResult,
      snapshots,
      downloadLog,
      auditChainResult,
    }),
    setSessionInputs(vals) {
      if (vals.roleMode !== undefined) selectedRoleMode = vals.roleMode;
      if (vals.host !== undefined) overrideHost = vals.host;
      if ('port' in vals) overridePort = vals.port;
      if (vals.database !== undefined) overrideDatabase = vals.database;
      if (vals.sslMode !== undefined) overrideSslMode = vals.sslMode;
      if (vals.user !== undefined) overrideUser = vals.user;
      if (vals.password !== undefined) overridePassword = vals.password;
      if (vals.adminUser !== undefined) overrideAdminUser = vals.adminUser;
      if (vals.adminPassword !== undefined) overrideAdminPassword = vals.adminPassword;
    },
    applySessionConfig,
    switchRoleAndConnect,
    syncProvincialStandards,
    setSubsetInputs(vals) {
      if (vals.zones !== undefined) subsetZonesRaw = vals.zones;
      if (vals.plots !== undefined) subsetPlotNumbersRaw = vals.plots;
      if ('limit' in vals) subsetLimitRaw = vals.limit;
      if (vals.targetProject !== undefined) subsetTargetProject = vals.targetProject;
      if (vals.activate !== undefined) subsetActivateOnSuccess = vals.activate;
    },
    runPreviewSubset,
    runPullSubset,
    runStagingPreflight,
    setStagingInputs(vals) {
      if (vals.submittedBy !== undefined) stagingSubmittedBy = vals.submittedBy;
      if (vals.notes !== undefined) stagingSubmitterNotes = vals.notes;
      if (vals.custodianOverride !== undefined) stagingCustodianOverride = vals.custodianOverride;
    },
    runSubmitToStaging,
    refreshSubmissionsList,
    runBootstrapSchemas,
    setAuditChainLimit(v) { auditChainLimit = v; },
    runVerifyAuditChain,
    runPublishStandards,
    setSeedPath(p) { seedSourceDbPath = p; },
    runSeedBaseline,
    inspectSubmission,
    runPreviewStagingMerge,
    setMergePlotResolution,
    setMergeFieldResolution,
    setMergeReviewerNotes(n) { mergeReviewerNotes = n; },
    runExecuteStagingMerge,
    runRejectSubmission,
    setSnapshotTag(t, fmt) { snapshotTag = t; if (fmt !== undefined) snapshotExportFormat = fmt; },
    runCreateSnapshot,
    refreshSnapshotsAndLedger,
  }));`;

  const compiled = compile(`<script lang="ts">${script}</script>`, { generate: 'client' });
  assert.equal(compiled.warnings.length, 0);

  const destroyCallbacks = [];
  const mountCallbacks = [];
  const cjsMod = { exports: {} };
  vm.runInNewContext(
    ts.transpileModule(compiled.js.code, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    }).outputText,
    {
      module: cjsMod,
      exports: cjsMod.exports,
      structuredClone,
      queueMicrotask,
      Promise,
      Set,
      Number,
      String,
      Object,
      require(name) {
        if (name === 'svelte') {
          return {
            onMount: fn => mountCallbacks.push(fn),
            onDestroy: fn => destroyCallbacks.push(fn),
          };
        }
        if (name === 'svelte/internal/client') return client;
        if (name.startsWith('svelte/')) return require(name);
        if (name === './cloudSyncWorkbench') return cloudSync;
        throw new Error(`Unexpected module ${name}`);
      },
    }
  );

  const dispatches = [];
  const busyTransitions = [];
  const switchedStates = [];
  let preflightPasses = false;
  let heldConnectionResolver = null;
  let nextConnectionError = null;
  let nextAuditError = null;

  function assertClonableArgs(method, args) {
    for (const arg of args) {
      assert.doesNotThrow(() => structuredClone(arg), `${method} received un-detached Svelte proxy`);
    }
    dispatches.push([method, ...args]);
  }

  const mockPort = {
    async getCloudSyncConfigStatus() {
      assertClonableArgs('getCloudSyncConfigStatus', []);
      return {
        configured: true,
        configSource: 'becmaster.env',
        envFileDetected: true,
        activeRoleMode: 'contributor',
        hasContributorCreds: true,
        hasCustodianCreds: true,
        sessionOverride: false,
        port: 5432,
        database: 'becmaster',
        sslMode: 'require',
      };
    },
    async configureCloudSyncSession(req) {
      assertClonableArgs('configureCloudSyncSession', [req]);
      return {
        configured: true,
        configSource: req.clearOverrides ? 'becmaster.env' : 'session_override',
        envFileDetected: true,
        activeRoleMode: req.roleMode,
        hasContributorCreds: true,
        hasCustodianCreds: true,
        sessionOverride: !req.clearOverrides,
        port: req.port ?? 5432,
        database: req.database ?? 'becmaster',
        sslMode: req.sslMode ?? 'require',
      };
    },
    async testCloudConnection() {
      assertClonableArgs('testCloudConnection', []);
      if (nextConnectionError) {
        const err = nextConnectionError;
        nextConnectionError = null;
        throw err;
      }
      if (heldConnectionResolver) {
        return new Promise(resolve => {
          heldConnectionResolver = resolve;
        });
      }
      return {
        connected: true,
        activeRoleMode: 'custodian',
        configSource: 'session_override',
        latencyMs: 14,
        serverVersion: 'PostgreSQL 17.2',
        postgisVersion: '3.5',
        database: 'becmaster',
        sslMode: 'require',
        schemasBootstrapped: true,
        canReadMaster: true,
        canSubmitStaging: true,
        canMergeMaster: true,
        canBootstrapSchema: true,
        becmasterPlotCount: 71567,
        becmasterVegCount: 1651842,
        pendingSubmissionCount: 2,
        snapshotCount: 3,
        latestSnapshotTag: 'BECMaster_2026_05',
        activeStandardsRelease: '2026.05',
        activeBecVersion: '13',
        activeTaxonomyVersion: '19',
        checkedAt: '2026-11-14T14:00:00Z',
      };
    },
    async bootstrapCloudSchemas() {
      assertClonableArgs('bootstrapCloudSchemas', []);
      return {
        schemaVersion: 1,
        appliedMigrations: ['001_init'],
        schemasVerified: ['becmaster', 'staging', 'standards', 'governance'],
        postgisEnabled: true,
        pgcryptoEnabled: true,
        roleGrantsApplied: true,
        contributorRoleSet: true,
        bootstrappedAt: '2026-11-14T14:01:00Z',
      };
    },
    async verifyBECMasterAuditChain(limit) {
      assertClonableArgs('verifyBECMasterAuditChain', [limit]);
      if (nextAuditError) {
        const err = nextAuditError;
        nextAuditError = null;
        throw err;
      }
      return {
        verifiedRows: limit > 0 ? limit : 597277,
        totalRows: 597277,
        valid: true,
        partialWindow: limit > 0,
        tailHash: 'abcdef0123456789fedcba9876543210',
      };
    },
    async publishStandardsToCloud(cid, req) {
      assertClonableArgs('publishStandardsToCloud', [cid, req]);
      return {
        releaseId: req.releaseId ?? 'BECv13_2026',
        becVersion: '13',
        taxonomyVersion: '19',
        vlistsSha256: 'aaaa1111bbbb2222cccc3333',
        becDbSha256: 'dddd4444eeee5555ffff6666',
        vmetaDataSha256: '777788889999000011112222',
        tableCounts: { USysAllSpecs: 7450 },
        elapsedMs: 42,
        publishedAt: '2026-11-14T14:02:00Z',
      };
    },
    async seedBECMasterBaseline(req) {
      assertClonableArgs('seedBECMasterBaseline', [req]);
      return {
        sourceProject: 'BECMaster_fixing',
        sourceSha256: '1234567890abcdef',
        snapshotTag: 'baseline_2026',
        plotCount: 71567,
        adminCount: 71567,
        vegCount: 1651842,
        humusCount: 50000,
        mineralCount: 90000,
        otherCount: 1200,
        metadataCount: 45,
        auditCount: 597277,
        childIdentityRows: 1800000,
        tailAuditHash: 'fedcba0987654321',
        elapsedMs: 950,
        seededAt: '2026-11-14T14:03:00Z',
        tableCounts: { Env: 71567 },
      };
    },
    async pullCloudStandards(cid) {
      assertClonableArgs('pullCloudStandards', [cid]);
      return {
        updated: true,
        alreadyCurrent: false,
        releaseId: '2026.05',
        becVersion: '13',
        taxonomyVersion: '19',
        localSha256: 'oldsha',
        cloudSha256: 'newsha',
        state: { contextId: 'ctx-std-updated', activeProject: 'Sample' },
      };
    },
    async previewBECMasterSubset(filter) {
      assertClonableArgs('previewBECMasterSubset', [filter]);
      return {
        matchingPlots: 18,
        matchingVeg: 412,
        samplePlots: ['00337', '108050'],
        zoneBreakdown: { CWH: 18 },
      };
    },
    async pullBECMasterSubset(cid, req) {
      assertClonableArgs('pullBECMasterSubset', [cid, req]);
      return {
        targetProject: req.targetProject,
        destinationPath: `/projects/${req.targetProject}.db`,
        destinationSha256: 'abcdef1234567890abcdef1234567890',
        plotCount: 18,
        vegCount: 412,
        humusCount: 24,
        mineralCount: 39,
        otherCount: 0,
        metadataCount: 1,
        downloadLogId: 7,
        activated: req.activateOnSuccess,
        state: { contextId: 'ctx-subset-activated', activeProject: req.targetProject },
      };
    },
    async previewStagingSubmission(cid, useActiveSu) {
      assertClonableArgs('previewStagingSubmission', [cid, useActiveSu]);
      return {
        project: 'Sample',
        projectId: 'SMP',
        plotCount: 12,
        vegRowCount: 240,
        sourceDbSha256: 'sha-stage-1',
        compliancePassed: preflightPasses,
        blockingErrorCount: preflightPasses ? 0 : 3,
        complianceSummary: { envCodeErrors: preflightPasses ? 0 : 3 },
        complianceReport: {},
        userSpeciesManifest: {
          schemaVersion: '1.0',
          exportedAt: '2026-11-14T14:04:00Z',
          sourceProject: 'Sample',
          rowCount: 1,
          payloadSha256: 'spp-sha',
          species: [{ code: 'CAREX_SP1', scientificName: 'Carex sp. nov.', lifeForm: 6, englishName: 'Sedge' }],
        },
        lumpRowCount: 2,
        suRowCount: 12,
      };
    },
    async submitProjectToStaging(cid, req) {
      assertClonableArgs('submitProjectToStaging', [cid, req]);
      return {
        submissionId: 'sub-900',
        projectName: 'Sample',
        projectId: 'SMP',
        submittedBy: req.submittedBy ?? 'anon',
        dbRole: 'vpro_contributor',
        status: 'pending',
        plotCount: 12,
        vegRowCount: 240,
        userSpeciesCount: 1,
        sourceDbSha256: 'sha-stage-1',
        compliancePassed: preflightPasses,
        submittedAt: '2026-11-14T14:05:00Z',
      };
    },
    async listStagingSubmissions(filter) {
      assertClonableArgs('listStagingSubmissions', [filter]);
      return [
        {
          submissionId: 'sub-900',
          projectName: 'Sample',
          submittedBy: 'Skeena Crew',
          dbRole: 'vpro_contributor',
          submittedAt: '2026-11-14T14:05:00Z',
          status: 'pending',
          plotCount: 12,
          vegRowCount: 240,
          sourceDbSha256: 'sha-stage-1',
          compliancePassed: true,
          userSpeciesCount: 1,
          lumpRowCount: 2,
          suRowCount: 12,
        },
      ];
    },
    async getStagingSubmissionDetail(submissionId) {
      assertClonableArgs('getStagingSubmissionDetail', [submissionId]);
      return {
        summary: {
          submissionId,
          projectName: 'Sample',
          submittedBy: 'Skeena Crew',
          dbRole: 'vpro_contributor',
          submittedAt: '2026-11-14T14:05:00Z',
          status: 'pending',
          plotCount: 12,
          vegRowCount: 240,
          sourceDbSha256: 'sha-stage-1',
          compliancePassed: true,
          userSpeciesCount: 1,
          lumpRowCount: 2,
          suRowCount: 12,
        },
        complianceReport: {},
        userSpeciesManifest: {
          schemaVersion: '1.0',
          exportedAt: '2026-11-14T14:04:00Z',
          sourceProject: 'Sample',
          rowCount: 1,
          payloadSha256: 'spp-sha',
          species: [{ code: 'CAREX_SP1', scientificName: 'Carex sp. nov.', lifeForm: 6, englishName: null }],
        },
        provisionalSpeciesDiffs: [
          { code: 'CAREX_SP1', scientificName: 'Carex sp. nov.', lifeForm: 6, status: 'unlisted' },
        ],
        lumpRows: [{ lumpCode: 'SALIX_SPP', sppCode: 'SALIBEB', use: true }],
        suRows: [{ plotNumber: '00337', siteUnit: 'CWHvm1/01' }],
      };
    },
    async previewStagingToMasterMerge(req) {
      assertClonableArgs('previewStagingToMasterMerge', [req]);
      return {
        submissionId: req.submissionId,
        sourceProject: 'Sample',
        targetProject: 'BECMaster',
        previewDigest: 'digest-3way-xyz',
        addedCount: 2,
        identicalCount: 8,
        fastForwardCount: 1,
        conflictCount: 1,
        targetOnlyCount: 71555,
        elapsedMs: 38,
        plots: [
          {
            plotNumber: '00337',
            category: 'Conflict',
            items: [],
          },
        ],
        conflicts: [
          {
            conflictId: '00337::Env::MoistureRegime',
            plotNumber: '00337',
            table: 'Env',
            key: 'MoistureRegime',
            field: 'MoistureRegime',
            baseVal: '4',
            sourceVal: '5',
            targetVal: '4',
            kind: 'Conflict',
            defaultResolution: 'keep_target',
            custodianProtected: false,
          },
        ],
        custodianProtectedDiffs: [
          {
            conflictId: '00337::Admin::BECSiteUnit',
            plotNumber: '00337',
            table: 'Admin',
            key: 'BECSiteUnit',
            field: 'BECSiteUnit',
            baseVal: 'CWHvm1/01',
            sourceVal: 'CWHvm1/05',
            targetVal: 'CWHvm1/01',
            kind: 'CustodianProtected',
            defaultResolution: 'keep_target',
            custodianProtected: true,
          },
        ],
      };
    },
    async executeStagingToMasterMerge(req) {
      assertClonableArgs('executeStagingToMasterMerge', [req]);
      return {
        mergeTxId: 'tx-merge-42',
        submissionId: req.submissionId,
        sourceProject: 'Sample',
        addedPlots: 2,
        updatedPlots: 2,
        skippedPlots: 8,
        allocatedChildIds: [9001, 9002],
        reservedDeletedIds: [450],
        auditRowsWritten: 17,
        tailAuditHash: '99887766554433221100',
        mergedAt: '2026-11-14T14:10:00Z',
      };
    },
    async rejectStagingSubmission(req) {
      assertClonableArgs('rejectStagingSubmission', [req]);
      return {
        submissionId: req.submissionId,
        projectName: 'Sample',
        submittedBy: 'Skeena Crew',
        dbRole: 'vpro_contributor',
        submittedAt: '2026-11-14T14:05:00Z',
        status: 'rejected',
        plotCount: 12,
        vegRowCount: 240,
        sourceDbSha256: 'sha-stage-1',
        compliancePassed: true,
        userSpeciesCount: 1,
        lumpRowCount: 2,
        suRowCount: 12,
        reviewerNotes: req.reviewerNotes,
      };
    },
    async createBECMasterSnapshot(cid, req) {
      assertClonableArgs('createBECMasterSnapshot', [cid, req]);
      return {
        snapshotTag: req.snapshotTag,
        createdAt: '2026-11-14T14:12:00Z',
        createdBy: 'Custodian',
        plotCount: 71569,
        vegCount: 1652082,
        becVersion: '13',
        taxonomyVersion: '19',
        manifestSha256: 'snapsha256abcdef123456',
        exportedPath: req.exportFormat ? `/exports/${req.snapshotTag}.${req.exportFormat}` : undefined,
      };
    },
    async listBECMasterSnapshots() {
      assertClonableArgs('listBECMasterSnapshots', []);
      return [
        {
          snapshotTag: 'BECMaster_2026_11',
          createdAt: '2026-11-14T14:12:00Z',
          createdBy: 'Custodian',
          plotCount: 71569,
          vegCount: 1652082,
          becVersion: '13',
          taxonomyVersion: '19',
          manifestSha256: 'snapsha256abcdef123456',
        },
      ];
    },
    async listBECMasterDownloadLog(limit) {
      assertClonableArgs('listBECMasterDownloadLog', [limit]);
      return [
        {
          id: 7,
          downloadedAt: '2026-11-14T14:06:00Z',
          actor: 'vpro_contributor',
          roleTier: 'contributor',
          filterJson: { zones: ['CWH'] },
          format: 'sqlite',
          plotCount: 18,
        },
      ];
    },
  };

  let api;
  const props = client.proxy({
    contextId: 'ctx-live',
    activeProject: 'Sample',
    activeSu: 'Sample',
    operationHeld: false,
    port: mockPort,
    onBusyChange: b => busyTransitions.push(b),
    oncontextswitched: st => switchedStates.push(st),
    inspect: v => {
      api = v;
    },
  });

  const dispose = client.effect_root(() => {
    cjsMod.exports.default(null, props);
  });
  for (const fn of mountCallbacks) fn();
  client.flush();
  await Promise.resolve();
  client.flush();

  try {
    // 1. Offline-first mount: ONLY getCloudSyncConfigStatus called on mount!
    assert.deepEqual(
      dispatches.map(d => d[0]),
      ['getCloudSyncConfigStatus'],
      'onMount must call ONLY getCloudSyncConfigStatus and zero live network endpoints'
    );
    assert.equal(api.getState().configStatus.envFileDetected, true);

    // 2. Session credential override clears password fields immediately and never leaks secrets
    const testSecretA = 'TempContribPass#91';
    const testSecretB = 'TempAdminPass#92';
    api.setSessionInputs({
      roleMode: 'contributor',
      host: 'db.internal.example',
      port: '5432',
      user: 'ecologist',
      password: testSecretA,
      adminUser: 'custodian',
      adminPassword: testSecretB,
    });
    client.flush();
    await api.applySessionConfig(false);
    client.flush();
    assert.equal(api.getState().overrideHost, 'db.internal.example', 'UX-CLOUD-005: Server Host override must stay visible after Apply Session Override');
    assert.equal(api.getState().overrideUser, 'ecologist', 'Contributor user override must stay visible');
    assert.equal(api.getState().overrideAdminUser, 'custodian', 'Custodian admin user override must stay visible');
    assert.equal(api.getState().overridePassword, '', 'contributor password must clear immediately');
    assert.equal(api.getState().overrideAdminPassword, '', 'admin password must clear immediately');
    assert.equal(String(api.getState().statusMessage).includes(testSecretA), false);
    assert.equal(String(api.getState().statusMessage).includes(testSecretB), false);

    // 2b. UX-CLOUD-003: numeric/null/undefined/empty/NaN/invalid Port override never throws TypeError
    api.setSessionInputs({ port: 5433 });
    client.flush();
    await api.applySessionConfig(false);
    client.flush();
    assert.equal(api.getState().error, null);
    assert.equal(dispatches.at(-1)[0], 'configureCloudSyncSession');
    assert.equal(dispatches.at(-1)[1].port, 5433);

    for (const emptyPort of [null, undefined, '', '   ']) {
      api.setSessionInputs({ port: emptyPort });
      client.flush();
      await api.applySessionConfig(false);
      client.flush();
      assert.equal(api.getState().error, null);
      assert.equal(dispatches.at(-1)[0], 'configureCloudSyncSession');
      assert.equal(dispatches.at(-1)[1].port, undefined);
    }

    for (const badPort of [70000, 0, -1, Number.NaN, '70000']) {
      const countBeforeBadPort = dispatches.length;
      api.setSessionInputs({ port: badPort });
      client.flush();
      await api.applySessionConfig(false);
      client.flush();
      assert.equal(dispatches.length, countBeforeBadPort, 'invalid port must not invoke configureCloudSyncSession');
      assert.equal(api.getState().error, 'Server port must be an integer between 1 and 65535.');
    }
    api.setSessionInputs({ port: 5432 });
    client.flush();

    // 3. operationHeld guard blocks actions before invoking Wails
    const countBeforeHeld = dispatches.length;
    props.operationHeld = true;
    client.flush();
    await api.syncProvincialStandards();
    client.flush();
    assert.equal(dispatches.length, countBeforeHeld, 'operationHeld must block network RPCs');
    assert.match(api.getState().error, /Wait for the current operation/);
    props.operationHeld = false;
    client.flush();

    // 4. Sync Provincial Standards & Regional Subset Checkout preserve '00337' and trigger oncontextswitched
    await api.syncProvincialStandards();
    client.flush();
    assert.equal(switchedStates.length, 1);
    assert.equal(switchedStates[0].contextId, 'ctx-std-updated');

    api.setSubsetInputs({
      zones: 'CWH',
      plots: '00337, 108050',
      targetProject: 'Skeena_Sub_2026',
      activate: true,
    });
    client.flush();
    await api.runPreviewSubset();
    client.flush();
    const previewSubsetCall = dispatches.find(d => d[0] === 'previewBECMasterSubset');
    assert.deepEqual(previewSubsetCall[1].plotNumbers, ['00337', '108050']);

    await api.runPullSubset();
    client.flush();
    assert.equal(switchedStates.length, 2);
    assert.equal(switchedStates[1].activeProject, 'Skeena_Sub_2026');

    // 4b. UX-CLOUD-003: numeric/null/undefined/empty/NaN/negative Subset Plot Limit in both Preview and Pull
    api.setSubsetInputs({ zones: 'CWH', plots: '', limit: 5, targetProject: 'Skeena_Limit5' });
    client.flush();
    await api.runPreviewSubset();
    client.flush();
    assert.equal(api.getState().error, null);
    assert.equal(dispatches.at(-1)[0], 'previewBECMasterSubset');
    assert.equal(dispatches.at(-1)[1].limit, 5);

    await api.runPullSubset();
    client.flush();
    assert.equal(api.getState().error, null);
    assert.equal(dispatches.at(-1)[0], 'pullBECMasterSubset');
    assert.equal(dispatches.at(-1)[2].filter.limit, 5);

    for (const emptyLimit of [null, undefined, '', '   ']) {
      api.setSubsetInputs({ zones: 'CWH', limit: emptyLimit });
      client.flush();
      await api.runPreviewSubset();
      client.flush();
      assert.equal(api.getState().error, null);
      assert.equal(dispatches.at(-1)[1].limit, undefined);
    }

    for (const badLimit of [-5, 0, Number.NaN, 2.5, '-3']) {
      const countBeforeBadLimit = dispatches.length;
      api.setSubsetInputs({ zones: 'CWH', limit: badLimit, targetProject: 'Skeena_Limit5' });
      client.flush();
      await api.runPreviewSubset();
      client.flush();
      assert.equal(dispatches.length, countBeforeBadLimit);
      assert.equal(api.getState().error, 'Subset plot limit must be a positive integer.');

      await api.runPullSubset();
      client.flush();
      assert.equal(dispatches.length, countBeforeBadLimit);
      assert.equal(api.getState().error, 'Subset plot limit must be a positive integer.');
    }
    api.setSubsetInputs({ limit: '' });
    client.flush();

    // 5. Staging Pre-Flight compliance gate blocks non-compliant Contributor upload
    preflightPasses = false;
    await api.runSubmitToStaging();
    client.flush();
    assert.match(api.getState().error, /Run Pre-Flight Compliance/);
    assert.equal(dispatches.some(d => d[0] === 'submitProjectToStaging'), false);

    await api.runStagingPreflight();
    client.flush();
    assert.equal(api.getState().stagingPreflight.compliancePassed, false);
    await api.runSubmitToStaging();
    client.flush();
    assert.match(api.getState().error, /Upload blocked/);
    assert.equal(dispatches.some(d => d[0] === 'submitProjectToStaging'), false);

    // Compliance passes -> Contributor can upload staging bundle
    preflightPasses = true;
    await api.runStagingPreflight();
    client.flush();
    api.setStagingInputs({ submittedBy: 'Skeena Crew', notes: '2026 plots validated' });
    client.flush();
    await api.runSubmitToStaging();
    client.flush();
    assert.equal(api.getState().submitStagingResult.submissionId, 'sub-900');

    // 6. Switch to Custodian Admin, run maintenance, inspect detail, 3-way merge with digest + resolutions, reject, snapshots
    api.setSessionInputs({ roleMode: 'custodian' });
    client.flush();
    await api.switchRoleAndConnect();
    client.flush();
    assert.equal(api.getState().activeRoleMode, 'custodian');
    assert.equal(api.getState().connectionReport.becmasterPlotCount, 71567);

    await api.runBootstrapSchemas();
    api.setAuditChainLimit(100);
    client.flush();
    await api.runVerifyAuditChain();
    client.flush();
    assert.equal(api.getState().auditChainResult.valid, true);
    assert.equal(api.getState().auditChainResult.verifiedRows, 100);
    assert.equal(api.getState().auditChainResult.totalRows, 597277);
    assert.equal(api.getState().auditChainResult.partialWindow, true);
    assert.match(api.getState().statusMessage, /latest 100 of 597,277 row\(s\) valid \(partial window/);

    for (const emptyOrZeroAudit of [0, '0', null, undefined, '', '   ']) {
      api.setAuditChainLimit(emptyOrZeroAudit);
      client.flush();
      await api.runVerifyAuditChain();
      client.flush();
      assert.equal(api.getState().error, null);
      assert.equal(dispatches.at(-1)[0], 'verifyBECMasterAuditChain');
      assert.equal(dispatches.at(-1)[1], 0);
      assert.equal(api.getState().auditChainResult.verifiedRows, 597277);
      assert.equal(api.getState().auditChainResult.totalRows, 597277);
      assert.equal(api.getState().auditChainResult.partialWindow, false);
      assert.match(api.getState().statusMessage, /verified from genesis: all 597,277 row\(s\) valid/);
    }

    // UX-CLOUD-004: failed/tampered audit check clears previous green auditChainResult
    nextAuditError = new Error('audit row_hash tampered at seq=49');
    api.setAuditChainLimit(0);
    client.flush();
    await api.runVerifyAuditChain();
    client.flush();
    assert.equal(api.getState().auditChainResult, null, 'failed audit verification must clear stale valid auditChainResult');
    assert.match(api.getState().error, /audit row_hash tampered at seq=49/);

    for (const badAudit of [-1, -5, '-5', Number.NaN, 1.5]) {
      const countBeforeBadAudit = dispatches.length;
      api.setAuditChainLimit(badAudit);
      client.flush();
      await api.runVerifyAuditChain();
      client.flush();
      assert.equal(dispatches.length, countBeforeBadAudit);
      assert.equal(api.getState().error, 'Audit limit must be a non-negative integer (0 = all).');
    }

    // 6b. UX-CLOUD-005: Failed Test Connection clears stale Connected state, and Apply/Clear Session Override preserve/reset Server Host
    assert.equal(api.getState().connectionReport.connected, true);
    nextConnectionError = new Error('connect to PostgreSQL: lookup <pg-host>: no such host');
    await api.switchRoleAndConnect();
    client.flush();
    assert.equal(api.getState().connectionReport, null, 'UX-CLOUD-005: failed Test Connection must clear stale Connected report');
    assert.match(api.getState().error, /Cloud connection probe failed/);

    // Reconnect -> green Connected again
    await api.switchRoleAndConnect();
    client.flush();
    assert.equal(api.getState().connectionReport.connected, true);

    // Apply Session Override clears unprobed connectionReport while preserving overrideHost
    api.setSessionInputs({
      roleMode: 'custodian',
      host: '  nonexistent-qa1117.invalid  ',
      sslMode: 'verify-full',
    });
    client.flush();
    await api.applySessionConfig(false);
    client.flush();
    assert.equal(api.getState().overrideHost, 'nonexistent-qa1117.invalid');
    assert.equal(api.getState().overrideSslMode, 'verify-full');
    assert.equal(api.getState().connectionReport, null, 'UX-CLOUD-005: applying new session override clears stale connection status until probed');

    // Editing another field (sslMode -> prefer) without re-typing host still retains and sends overrideHost
    api.setSessionInputs({ sslMode: 'prefer' });
    client.flush();
    await api.applySessionConfig(false);
    client.flush();
    assert.equal(dispatches.at(-1)[0], 'configureCloudSyncSession');
    assert.equal(dispatches.at(-1)[1].host, 'nonexistent-qa1117.invalid');
    assert.equal(api.getState().overrideHost, 'nonexistent-qa1117.invalid');

    // Clear Session Override resets host/users to '' and restores defaults from status
    await api.applySessionConfig(true);
    client.flush();
    assert.equal(api.getState().overrideHost, '');
    assert.equal(api.getState().overrideUser, '');
    assert.equal(api.getState().overrideAdminUser, '');
    assert.equal(api.getState().overrideSslMode, 'require');

    // Reconnect for remaining Custodian tests & onDestroy check
    await api.switchRoleAndConnect();
    client.flush();
    assert.equal(api.getState().connectionReport.connected, true);
    await api.runPublishStandards();
    api.setSeedPath('/data/BECMaster_fixing.db');
    client.flush();
    await api.runSeedBaseline();
    await api.refreshSubmissionsList();
    await api.inspectSubmission('sub-900');
    client.flush();
    assert.equal(api.getState().selectedSubmissionDetail.provisionalSpeciesDiffs[0].code, 'CAREX_SP1');

    await api.runPreviewStagingMerge('sub-900');
    client.flush();
    assert.equal(api.getState().mergePreview.previewDigest, 'digest-3way-xyz');
    // Custodian-protected field defaults to keep_target; override MoistureRegime to accept_source
    api.setMergePlotResolution('00337', 'keep_target');
    api.setMergeFieldResolution('00337::Env::MoistureRegime', 'accept_source');
    api.setMergeReviewerNotes('Approved MoistureRegime update; kept BECSiteUnit');
    client.flush();
    await api.runExecuteStagingMerge();
    client.flush();

    const mergeExecCall = dispatches.find(d => d[0] === 'executeStagingToMasterMerge');
    assert.ok(mergeExecCall);
    assert.equal(mergeExecCall[1].expectedPreviewDigest, 'digest-3way-xyz');
    assert.equal(mergeExecCall[1].plotResolutions['00337'], 'keep_target');
    assert.equal(mergeExecCall[1].fieldResolutions['00337::Env::MoistureRegime'], 'accept_source');
    assert.equal(mergeExecCall[1].fieldResolutions['00337::Admin::BECSiteUnit'], 'keep_target');
    assert.equal(api.getState().mergeExecuteResult.mergeTxId, 'tx-merge-42');

    // Reject requires reviewer notes
    api.setMergeReviewerNotes('');
    client.flush();
    await api.runRejectSubmission('sub-900');
    client.flush();
    assert.match(api.getState().error, /Reviewer notes are required/);
    api.setMergeReviewerNotes('Duplicate plot numbers require field check');
    client.flush();
    await api.runRejectSubmission('sub-900');
    client.flush();
    assert.equal(api.getState().submissions[0].status, 'rejected');

    // Snapshots & Download Activity Log
    api.setSnapshotTag('BECMaster_2026_11', 'gpkg');
    client.flush();
    await api.runCreateSnapshot();
    await api.refreshSnapshotsAndLedger();
    client.flush();
    assert.equal(api.getState().snapshots.length, 1);
    assert.equal(api.getState().downloadLog.length, 1);

    // 7. onDestroy cancels in-flight async work and releases onBusyChange(false)
    heldConnectionResolver = true;
    const inflightPromise = api.switchRoleAndConnect();
    client.flush();
    assert.equal(busyTransitions.at(-1), true);
    for (const fn of destroyCallbacks) fn();
    assert.equal(busyTransitions.at(-1), false, 'onDestroy must release busy barrier immediately');
    const prevPlotCount = api.getState().connectionReport.becmasterPlotCount;
    heldConnectionResolver({
      connected: true,
      activeRoleMode: 'contributor',
      configSource: 'late',
      latencyMs: 999,
      serverVersion: 'late',
      database: 'becmaster',
      sslMode: 'require',
      schemasBootstrapped: true,
      canReadMaster: true,
      canSubmitStaging: true,
      canMergeMaster: false,
      canBootstrapSchema: false,
      becmasterPlotCount: 1,
      becmasterVegCount: 1,
      pendingSubmissionCount: 0,
      snapshotCount: 0,
      checkedAt: 'late',
    });
    await inflightPromise;
    client.flush();
    assert.equal(api.getState().connectionReport.becmasterPlotCount, prevPlotCount, 'post-destroy resolve must not mutate state');
  } finally {
    dispose();
  }
});

test('ProjectAdminWorkbench, Navigation, and App wire Cloud BECMaster Sync cleanly without new static script imports', () => {
  const adminSrc = read('ProjectAdminWorkbench.svelte');
  const scriptBlock = adminSrc.match(/<script lang="ts">([\s\S]*?)<\/script>/)[1];
  const importCount = (scriptBlock.match(/\bimport\s+/g) ?? []).length;
  assert.equal(importCount, 2, 'ProjectAdminWorkbench <script> must keep only its 2 existing imports');
  assert.match(adminSrc, /data-workbench-tab=\{id\}/);
  assert.match(adminSrc, /\['cloudsync',\s*'Cloud BECMaster Sync'\]/);
  assert.match(adminSrc, /#await import\('\.\/CloudSyncWorkbench\.svelte'\)/);

  const navSrc = read('Navigation.svelte');
  const icons = new Proxy({}, { get: () => () => {} });
  const Nav = serverComponent(navSrc, 'Navigation.svelte', { '@lucide/svelte': icons });
  const navHtml = render(Nav, { props: { view: 'home', onnavigate: () => {} } }).body;
  const syncButtons = [...navHtml.matchAll(/<button\b([^>]*)>[\s\S]*?<span>Cloud BECMaster Sync<\/span>\s*<\/button>/g)];
  assert.equal(syncButtons.length, 2, 'Cloud BECMaster Sync must appear in both Forms and Interchange menus');
  for (const btn of syncButtons) {
    assert.equal(/\bdisabled(?:\s|=|$)/.test(btn[1]), false, 'Cloud BECMaster Sync menu buttons must be enabled');
  }

  // Verify callback vs fallback dispatch in Navigation.svelte
  const calls = [];
  const fallbackCtx = componentFunctions('Navigation.svelte', ['itemEnabled', 'activate', 'closeMenu', 'navigate'], {
    openMenu: 'Interchange',
    navigation: { querySelector: () => ({ querySelector: () => ({ focus: () => calls.push('focus') }) }) },
    onnavigate: v => calls.push(`nav:${v}`),
  });
  fallbackCtx.actions.activate({ action: 'cloud-sync' });
  assert.deepEqual(calls, ['focus', 'nav:project-admin']);

  calls.length = 0;
  const cbCtx = componentFunctions('Navigation.svelte', ['itemEnabled', 'activate', 'closeMenu', 'navigate'], {
    openMenu: 'Forms',
    navigation: { querySelector: () => ({ querySelector: () => ({ focus: () => calls.push('focus') }) }) },
    onnavigate: v => calls.push(`nav:${v}`),
    onopencloudsync: () => calls.push('open-cloud-sync'),
  });
  cbCtx.actions.activate({ action: 'cloud-sync' });
  assert.deepEqual(calls, ['focus', 'open-cloud-sync']);

  const appSrc = read('App.svelte');
  assert.match(appSrc, /onopencloudsync=\{\(\)\s*=>\s*\{\s*void requestTransition\(/);
  assert.match(appSrc, /projectAdminTab = 'cloudsync'/);
  assert.match(appSrc, /initialTab=\{projectAdminTab\}/);
});

test('UX-CLOUD-004 & UX-CLOUD-005: Custodian audit banner distinguishes full-chain genesis vs partial tail window and AuthPanel renders offline badge when connectionReport is cleared', () => {
  const stdSrc = read('CloudSyncCustodianStandardsPanel.svelte');
  assert.doesNotMatch(stdSrc, /[\u{1F300}-\u{1FAFF}]/u, 'CloudSyncCustodianStandardsPanel must contain zero emojis');
  const compiledStd = compile(stdSrc, { filename: 'CloudSyncCustodianStandardsPanel.svelte', generate: 'client' });
  assert.deepEqual(compiledStd.warnings, []);

  const StdComponent = serverComponent(stdSrc, 'CloudSyncCustodianStandardsPanel.svelte', {
    './cloudSyncWorkbench': cloudSync,
  });

  const fullChainHtml = render(StdComponent, {
    props: {
      busy: false,
      operationHeld: false,
      auditChainResult: {
        verifiedRows: 597360,
        totalRows: 597360,
        valid: true,
        partialWindow: false,
        tailHash: '4bb62176078f7bb990232fd463e1ecaea79f266d7200ed0202a20f9112d81c93',
      },
      bootstrapResult: null,
      publishStandardsResult: null,
      seedSourceDbPath: '',
      seedBaselineResult: null,
      onPublishStandards: () => {},
      onSeedBaseline: () => {},
    },
  }).body;
  assert.match(fullChainHtml, /data-audit-chain-banner/);
  assert.match(fullChainHtml, /Audit Hash Chain VALID/);
  assert.match(fullChainHtml, /Verified all 597,360 rows from genesis/);
  assert.doesNotMatch(fullChainHtml, /partial window/);

  const partialHtml = render(StdComponent, {
    props: {
      busy: false,
      operationHeld: false,
      auditChainResult: {
        verifiedRows: 1000,
        totalRows: 597360,
        valid: true,
        partialWindow: true,
        tailHash: '4bb62176078f7bb990232fd463e1ecaea79f266d7200ed0202a20f9112d81c93',
      },
      bootstrapResult: null,
      publishStandardsResult: null,
      seedSourceDbPath: '',
      seedBaselineResult: null,
      onPublishStandards: () => {},
      onSeedBaseline: () => {},
    },
  }).body;
  assert.match(partialHtml, /Verified latest 1,000 of 597,360 rows \(partial window\)/);

  const emptyHtml = render(StdComponent, {
    props: {
      busy: false,
      operationHeld: false,
      auditChainResult: {
        verifiedRows: 0,
        totalRows: 0,
        valid: true,
        partialWindow: false,
        tailHash: '0'.repeat(64),
      },
      bootstrapResult: null,
      publishStandardsResult: null,
      seedSourceDbPath: '',
      seedBaselineResult: null,
      onPublishStandards: () => {},
      onSeedBaseline: () => {},
    },
  }).body;
  assert.match(emptyHtml, /Verified 0 rows \(empty ledger anchored to genesis\)/);

  // AuthPanel offline state after failed Test Connection (connectionReport = null) + retained overrideHost
  const AuthComponent = serverComponent(read('CloudSyncAuthPanel.svelte'), 'CloudSyncAuthPanel.svelte', {
    './cloudSyncWorkbench': cloudSync,
  });
  const authOfflineHtml = render(AuthComponent, {
    props: {
      busy: false,
      operationHeld: false,
      activeRoleMode: 'contributor',
      configStatus: {
        configured: true,
        configSource: 'session',
        envFileDetected: true,
        activeRoleMode: 'contributor',
        hasContributorCreds: true,
        hasCustodianCreds: true,
        sessionOverride: true,
        port: 5432,
        database: 'becmaster',
        sslMode: 'verify-full',
      },
      connectionReport: null,
      pullStandardsResult: null,
      selectedRoleMode: 'contributor',
      overrideHost: 'nonexistent-qa1117.invalid',
      overridePort: '5432',
      overrideDatabase: 'becmaster',
      overrideSslMode: 'verify-full',
      overrideUser: 'bec_contributor',
      overridePassword: '',
      overrideAdminUser: '',
      overrideAdminPassword: '',
      onSwitchRoleAndConnect: () => {},
      onSyncProvincialStandards: () => {},
      onApplySessionConfig: () => {},
    },
  }).body;
  assert.match(authOfflineHtml, /data-cloud-status-badge="offline"/);
  assert.match(authOfflineHtml, /Offline \/ Unprobed/);
  assert.doesNotMatch(authOfflineHtml, /data-cloud-status-badge="connected"/);
  assert.match(authOfflineHtml, /nonexistent-qa1117\.invalid/);
});
