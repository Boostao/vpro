const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const ts = require('typescript');
const { compile } = require('svelte/compiler');
const { render } = require('svelte/server');
const { componentFunctions, loadTypeScript, serverComponent, srcPath } = require('./svelteTestHelpers.cjs');

const read = name => readFileSync(srcPath(name), 'utf8');

function makeNotifController() {
  const notifMod = loadTypeScript('shell/notificationService.svelte.ts', {
    'svelte/store': require('svelte/store'),
  });
  return notifMod.createNotificationController({
    schedule: () => 1,
    cancelSchedule: () => {},
  });
}

const mockBindings = new Proxy({}, {
  get: (_t, service) => new Proxy({}, {
    get: (_s, method) => () => Promise.resolve(
      String(method).startsWith('List') || String(method).startsWith('Get') ? [] : null
    ),
  }),
});

test('all 5 admin/datasheet/rsidecar workbenches compile with 0 warnings, pass theme lint, expose data-workbench-sticky-bar in SSR, and drop duplicate status banners', () => {
  const svelteFiles = [
    'admin/ProjectAdminWorkbench.svelte',
    'admin/CloudSyncWorkbench.svelte',
    'admin/ProjectMetadataEditor.svelte',
    'admin/ProjectMetadataRestore.svelte',
    'datasheet/UniversalDatasheetGrid.svelte',
    'rsidecar/RSidecarWorkbench.svelte',
  ];
  const emojiRe = /\p{Extended_Pictographic}/u;
  const legacyGreenUtil = /\b(?:bg|text|border|ring|outline)-(?:emerald|teal|green)-\d{2,3}\b/i;

  for (const rel of svelteFiles) {
    const src = read(rel);
    assert.equal(emojiRe.test(src), false, `${rel} must contain zero emojis`);
    assert.equal(legacyGreenUtil.test(src), false, `${rel} must contain zero green/emerald/teal utilities`);
    const clientCompiled = compile(src, { filename: srcPath(rel), generate: 'client' });
    assert.deepEqual(clientCompiled.warnings, [], `${rel} emitted client compiler warnings`);
    const serverCompiled = compile(src, { filename: srcPath(rel), generate: 'server' });
    assert.deepEqual(serverCompiled.warnings, [], `${rel} emitted server compiler warnings`);
  }

  // Verify duplicate layout-shifting inline status banners are removed while script state stays intact
  const adminSrc = read('admin/ProjectAdminWorkbench.svelte');
  assert.match(adminSrc, /let statusMessage = \$state<string \| null>\(null\);/);
  assert.doesNotMatch(adminSrc, /\{#if statusMessage\}/);

  const cloudSrc = read('admin/CloudSyncWorkbench.svelte');
  assert.match(cloudSrc, /let statusMessage = \$state<string \| null>\(null\);/);
  assert.doesNotMatch(cloudSrc, /\{#if statusMessage\}/);

  const dsSrc = read('datasheet/UniversalDatasheetGrid.svelte');
  assert.match(dsSrc, /let statusBanner = \$state\(''\);/);
  assert.doesNotMatch(dsSrc, /\{#if statusBanner\}/);

  const rSrc = read('rsidecar/RSidecarWorkbench.svelte');
  assert.match(rSrc, /let statusMessage = \$state<string \| null>\(null\);/);
  assert.doesNotMatch(rSrc, /\{#if statusMessage\}/);

  // Verify SSR output renders data-workbench-sticky-bar and sticky utility classes on all 5 workbenches
  const quality = loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });
  const presetsStub = loadTypeScript('projectMetadataPresets.ts', {
    '../../bindings/github.com/boostao/vpro/app': mockBindings,
    './qualityEditor': quality,
  });
  const adminMod = loadTypeScript('projectAdminWorkbench.ts', {
    '../../bindings/github.com/boostao/vpro/app': mockBindings,
    './projectMetadataPresets': presetsStub,
    './qualityEditor': quality,
  });
  const cloudMod = loadTypeScript('cloudSyncWorkbench.ts', {
    '../../bindings/github.com/boostao/vpro/app': mockBindings,
    './qualityEditor': quality,
    './projectAdminWorkbench': adminMod,
  });
  const gridMod = loadTypeScript('universalDatasheetGrid.ts', {
    '@wailsio/runtime': { Call: { ByName: () => Promise.resolve(null) } },
  });
  const rMod = loadTypeScript('rSidecarWorkbench.ts', {
    '../../bindings/github.com/boostao/vpro/app': mockBindings,
    './qualityEditor': quality,
  });
  const defaults = JSON.parse(readFileSync(srcPath('../../resources/project-metadata-standard.json'), 'utf8'));
  const mapping = JSON.parse(readFileSync(srcPath('../../resources/project-metadata-template.json'), 'utf8'));
  const layout = JSON.parse(readFileSync(srcPath('../../resources/project-metadata-layout.json'), 'utf8'));
  const metaMod = loadTypeScript('projectMetadataEditor.ts', {
    './qualityEditor': quality,
    '../../resources/project-metadata-standard.json': defaults,
    '../../resources/project-metadata-template.json': mapping,
  });
  const metaPresMod = loadTypeScript('projectMetadataPresentation.ts', {
    '../../resources/project-metadata-layout.json': layout,
  });
  const restoreMod = loadTypeScript('projectMetadataRestore.ts', {
    './qualityEditor': quality,
    './projectMetadataEditor': metaMod,
  });

  const ssrCases = [
    {
      name: 'ProjectAdminWorkbench.svelte',
      comp: serverComponent(adminSrc, 'admin/ProjectAdminWorkbench.svelte', { './projectAdminWorkbench': adminMod }),
      props: { contextId: 'ctx-1', activeProject: 'Sample', activeSu: 'Sample' },
      borderRe: /border-(?:vpro-border|stone-200)/,
    },
    {
      name: 'CloudSyncWorkbench.svelte',
      comp: serverComponent(cloudSrc, 'admin/CloudSyncWorkbench.svelte', { './cloudSyncWorkbench': cloudMod }),
      props: { contextId: 'ctx-1', activeProject: 'Sample', activeSu: 'Sample', port: {} },
      borderRe: /border-(?:vpro-border|stone-200)/,
    },
    {
      name: 'ProjectMetadataEditor.svelte',
      comp: serverComponent(read('admin/ProjectMetadataEditor.svelte'), 'admin/ProjectMetadataEditor.svelte', {
        './projectMetadataEditor': metaMod,
        './projectMetadataPresentation': metaPresMod,
        './projectMetadataRestore': restoreMod,
        '../../bindings/github.com/boostao/vpro/app': {
          AuditRestoreAction: { AuditRestoreRetain: 'retain', AuditRestorePrune: 'prune' },
        },
      }),
      props: { client: {}, contextId: 'ctx-1', plot: '00337', onclosed() {}, onbusy() {}, oncommitted: async () => {} },
      borderRe: /border-(?:vpro-border|stone-200)/,
    },
    {
      name: 'UniversalDatasheetGrid.svelte',
      comp: serverComponent(dsSrc, 'datasheet/UniversalDatasheetGrid.svelte', { './universalDatasheetGrid': gridMod }),
      props: { contextId: 'ctx-1', project: 'Sample', su: 'Sample', hierarchy: 'Sample' },
      borderRe: /border-(?:vpro-border|stone-200)/,
    },
    {
      name: 'RSidecarWorkbench.svelte',
      comp: serverComponent(rSrc, 'rsidecar/RSidecarWorkbench.svelte', { './rSidecarWorkbench': rMod }),
      props: { contextId: 'ctx-1', activeProject: 'Sample', activeSu: 'Sample' },
      borderRe: /border-(?:vpro-border|\[#D8D8D8\])/,
    },
  ];

  for (const item of ssrCases) {
    const html = render(item.comp, { props: item.props }).body;
    const barTag = html.match(/<[^>]+\bdata-workbench-sticky-bar(?:="")?[^>]*>/)?.[0];
    assert.ok(barTag, `${item.name} SSR output must include data-workbench-sticky-bar`);
    assert.match(barTag, /\bsticky\b/);
    assert.match(barTag, /\btop-0\b/);
    assert.match(barTag, /\bz-20\b/);
    assert.match(barTag, /\bbg-white\/95\b/);
    assert.match(barTag, /\bbackdrop-blur-xs\b/);
    assert.match(barTag, /\bpy-2\b/);
    assert.match(barTag, /\bborder-b\b/);
    assert.match(barTag, item.borderRe);
  }
});

test('UniversalDatasheetGrid binds Ctrl+S / Cmd+S to trigger Save only when valid staged edits exist and Save is enabled', () => {
  const dsSrc = read('datasheet/UniversalDatasheetGrid.svelte');
  assert.match(dsSrc, /<svelte:window[^>]*onkeydown=\{handleWindowKeydown\}/);

  let saves = 0;
  const makeCtx = overrides => componentFunctions('UniversalDatasheetGrid.svelte', ['handleWindowKeydown'], {
    page: { tableKey: 'Veg' },
    saving: false,
    activeTableReadOnly: false,
    validEditCount: 2,
    invalidDraftCount: 0,
    saveDrafts: async () => { saves++; },
    ...overrides,
  });

  // Ctrl+S and Cmd+S prevent default and trigger saveDrafts when ready
  for (const mod of [{ ctrlKey: true, metaKey: false, key: 's' }, { ctrlKey: false, metaKey: true, key: 'S' }]) {
    let prevented = 0;
    const before = saves;
    makeCtx().actions.handleWindowKeydown({
      ...mod,
      altKey: false,
      shiftKey: false,
      preventDefault: () => { prevented++; },
    });
    assert.equal(prevented, 1);
    assert.equal(saves, before + 1);
  }

  // Shift+Ctrl+S or Alt+Ctrl+S should not intercept or save
  for (const mod of [{ shiftKey: true, altKey: false }, { shiftKey: false, altKey: true }]) {
    let prevented = 0;
    const before = saves;
    makeCtx().actions.handleWindowKeydown({
      ctrlKey: true,
      metaKey: false,
      key: 's',
      ...mod,
      preventDefault: () => { prevented++; },
    });
    assert.equal(prevented, 0);
    assert.equal(saves, before);
  }

  // Disabled conditions: preventDefault still runs, saveDrafts must NOT fire
  for (const disabled of [
    { validEditCount: 0 },
    { invalidDraftCount: 1 },
    { saving: true },
    { activeTableReadOnly: true },
    { page: null },
  ]) {
    let prevented = 0;
    const before = saves;
    makeCtx(disabled).actions.handleWindowKeydown({
      ctrlKey: true,
      metaKey: false,
      altKey: false,
      shiftKey: false,
      key: 's',
      preventDefault: () => { prevented++; },
    });
    assert.equal(prevented, 1);
    assert.equal(saves, before);
  }
});

test('ProjectAdminWorkbench routes lifecycle/compliance/optimizeveg outcomes to admin notifications', async () => {
  const client = await import('svelte/internal/client');
  const notifCtrl = makeNotifController();
  const quality = loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });
  const presetsStub = loadTypeScript('projectMetadataPresets.ts', {
    '../../bindings/github.com/boostao/vpro/app': mockBindings,
    './qualityEditor': quality,
  });
  const adminMod = loadTypeScript('projectAdminWorkbench.ts', {
    '../../bindings/github.com/boostao/vpro/app': mockBindings,
    './projectMetadataPresets': presetsStub,
    './qualityEditor': quality,
    '../shell/notificationService.svelte': { notifications: notifCtrl },
  });

  let script = read('admin/ProjectAdminWorkbench.svelte').match(/<script lang="ts">([\s\S]*?)<\/script>/)[1];
  script = script.replace('oncontextswitched,', 'oncontextswitched, inspect,');
  script += `\n$effect(() => inspect({
    setNewProj(name) { newProjName = name; },
    submitCreateNewProject,
    runCompliance,
    runApplyOptimizeVeg,
  }));`;

  const compiled = compile(`<script lang="ts">${script}</script>`, { generate: 'client' });
  assert.equal(compiled.warnings.length, 0);

  const modObj = { exports: {} };
  vm.runInNewContext(
    ts.transpileModule(compiled.js.code, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    }).outputText,
    {
      module: modObj,
      exports: modObj.exports,
      structuredClone,
      require(name) {
        if (name === 'svelte') return { onDestroy: () => {} };
        if (name === 'svelte/internal/client') return client;
        if (name.startsWith('svelte/')) return require(name);
        if (name === './projectAdminWorkbench') return adminMod;
        throw new Error(`Unexpected module ${name}`);
      },
    }
  );

  let api;
  const dispose = client.effect_root(() => {
    modObj.exports.default(null, {
      contextId: 'ctx-admin',
      activeProject: 'Bulkley2026',
      activeSu: 'Bulkley_SU',
      port: {
        async listProjectMetadataPresets() { return []; },
        async createNewProject(_cid, req) {
          return {
            projectName: req.projectName,
            projectId: req.projectName,
            destinationPath: `/projects/${req.projectName}.db`,
            destinationSha256: 'abc123',
            activated: false,
          };
        },
        async runComplianceValidation() {
          return {
            project: 'Bulkley2026',
            su: 'None',
            useActiveSu: false,
            passed: false,
            summary: { envCodeErrors: 1, boundsErrors: 0, envAdminMismatches: 0, orphanChildRows: 0, duplicateSpeciesSplits: 0, unlistedSpecies: 0, synonymSpecies: 0, userSpecies: 0, plotsWithoutVeg: 0 },
            envCodeFindings: [],
            boundsFindings: [],
            envAdminFindings: [],
            orphanFindings: [],
            plotsWithoutVegetation: [],
            duplicateVegFindings: [],
            taxonomyFindings: [],
          };
        },
      },
      inspect: v => { api = v; },
    });
  });

  try {
    client.flush();
    api.setNewProj('Kootenay_2026');
    client.flush();
    await api.submitCreateNewProject();
    await api.runCompliance();
    await api.runApplyOptimizeVeg();
    client.flush();

    const entries = notifCtrl.getSnapshot().entries;
    assert.equal(entries.length, 3);
    assert.ok(entries.every(e => e.category === 'admin' && e.source === 'Project Admin' && e.contextTag === 'Bulkley2026'));
    assert.equal(entries[0].severity, 'error');
    assert.equal(entries[1].severity, 'warning');
    assert.equal(entries[2].severity, 'success');
    assert.match(entries[2].message, /Kootenay_2026/);
  } finally {
    dispose();
  }
});

test('CloudSyncWorkbench routes background notifications and scrubs DSNs, PGPASSWORD, tokens, and session passwords BEFORE pushing', async () => {
  const client = await import('svelte/internal/client');
  const notifCtrl = makeNotifController();
  const quality = loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });
  const adminMod = loadTypeScript('projectAdminWorkbench.ts', {
    '../../bindings/github.com/boostao/vpro/app': mockBindings,
    './qualityEditor': quality,
  });
  const cloudMod = loadTypeScript('cloudSyncWorkbench.ts', {
    '../../bindings/github.com/boostao/vpro/app': mockBindings,
    './qualityEditor': quality,
    './projectAdminWorkbench': adminMod,
    '../shell/notificationService.svelte': { notifications: notifCtrl },
  });

  // Direct redaction unit verification
  const redacted = cloudMod.redactCloudSecrets(
    'dial postgresql://ecologist:SecretPass99@10.0.0.5:5432/becmaster PGPASSWORD=TopSecret token=BearerTok123 customSecret#1',
    ['customSecret#1']
  );
  assert.doesNotMatch(redacted, /SecretPass99|TopSecret|BearerTok123|customSecret#1|postgresql:\/\//);
  assert.match(redacted, /postgres:\/\/<redacted>/);

  let script = read('admin/CloudSyncWorkbench.svelte').match(/<script lang="ts">([\s\S]*?)<\/script>/)[1];
  script = script.replace(
    'oncontextswitched?: (state: unknown) => void;',
    'oncontextswitched?: (state: unknown) => void; inspect?: (v: any) => void;'
  );
  script = script.replace('oncontextswitched,', 'oncontextswitched, inspect,');
  script += `\n$effect(() => inspect?.({
    setPasswords(pw, adminPw) { overridePassword = pw; overrideAdminPassword = adminPw; },
    applySessionConfig,
    syncProvincialStandards,
    getState: () => ({ error, statusMessage, overridePassword, overrideAdminPassword }),
  }));`;

  const compiled = compile(`<script lang="ts">${script}</script>`, { generate: 'client' });
  assert.equal(compiled.warnings.length, 0);

  const modObj = { exports: {} };
  vm.runInNewContext(
    ts.transpileModule(compiled.js.code, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    }).outputText,
    {
      module: modObj,
      exports: modObj.exports,
      structuredClone,
      queueMicrotask,
      Promise,
      Set,
      Number,
      String,
      Object,
      require(name) {
        if (name === 'svelte') return { onMount: fn => fn(), onDestroy: () => {} };
        if (name === 'svelte/internal/client') return client;
        if (name.startsWith('svelte/')) return require(name);
        if (name === './cloudSyncWorkbench') return cloudMod;
        throw new Error(`Unexpected module ${name}`);
      },
    }
  );

  const secretA = 'ContribSecret#77!';
  const secretB = 'CustodianSecret#88!';
  let api;
  const dispose = client.effect_root(() => {
    modObj.exports.default(null, {
      contextId: 'ctx-cloud',
      activeProject: 'HaidaGwaii_2026',
      port: {
        async getCloudSyncConfigStatus() {
          return {
            configured: true,
            configSource: 'becmaster.env',
            envFileDetected: true,
            activeRoleMode: 'contributor',
            hasContributorCreds: true,
            hasCustodianCreds: false,
            sessionOverride: false,
            port: 5432,
            database: 'becmaster',
            sslMode: 'require',
          };
        },
        async configureCloudSyncSession() {
          throw new Error(
            `connect postgres://ecologist:${secretA}@192.168.10.20:5432/becmaster failed: PGPASSWORD=${secretA} token=tok_live_999 ${secretB}`
          );
        },
        async pullCloudStandards() {
          return {
            updated: true,
            alreadyCurrent: false,
            releaseId: '2026.11',
            becVersion: '13',
            taxonomyVersion: '19',
            localSha256: 'a',
            cloudSha256: 'b',
          };
        },
      },
      inspect: v => { api = v; },
    });
  });

  try {
    client.flush();
    await Promise.resolve();
    client.flush();

    api.setPasswords(secretA, secretB);
    client.flush();
    await api.applySessionConfig(false);
    await api.syncProvincialStandards();
    client.flush();

    const snap = notifCtrl.getSnapshot();
    assert.equal(snap.entries.length, 2);
    assert.ok(snap.entries.every(e => e.category === 'background' && e.source === 'BECMaster Cloud Sync' && e.contextTag === 'HaidaGwaii_2026'));

    const errEntry = snap.entries.find(e => e.severity === 'error');
    assert.ok(errEntry, 'error notification must be pushed on failed cloud session config');
    for (const forbidden of [secretA, secretB, 'postgres://ecologist', 'tok_live_999']) {
      assert.equal(errEntry.message.includes(forbidden), false, `notification leaked secret: ${forbidden}`);
      assert.equal(String(api.getState().error).includes(forbidden), false, `inline error leaked secret: ${forbidden}`);
    }
    assert.match(errEntry.message, /postgres:\/\/<redacted>/);
    assert.match(errEntry.message, /PGPASSWORD=<redacted>/);
    assert.match(errEntry.message, /token=<redacted>/);
  } finally {
    dispose();
  }
});

test('ProjectMetadataEditor and ProjectMetadataRestore route save/create/restore notifications under admin category', async () => {
  const client = await import('svelte/internal/client');
  const notifCtrl = makeNotifController();
  const quality = loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });
  const defaults = JSON.parse(readFileSync(srcPath('../../resources/project-metadata-standard.json'), 'utf8'));
  const mapping = JSON.parse(readFileSync(srcPath('../../resources/project-metadata-template.json'), 'utf8'));
  const layout = JSON.parse(readFileSync(srcPath('../../resources/project-metadata-layout.json'), 'utf8'));
  const metaMod = loadTypeScript('projectMetadataEditor.ts', {
    './qualityEditor': quality,
    '../../resources/project-metadata-standard.json': defaults,
    '../../resources/project-metadata-template.json': mapping,
  });
  const metaPresMod = loadTypeScript('projectMetadataPresentation.ts', {
    '../../resources/project-metadata-layout.json': layout,
  });
  const restoreMod = loadTypeScript('projectMetadataRestore.ts', {
    './qualityEditor': quality,
    './projectMetadataEditor': metaMod,
  });

  const cell = (storage, value) => ({ storage, text: storage === 'text' ? value : null, integer: storage === 'integer' ? value : null, real: null, blobHex: null });
  const cols = ['ID', 'ProjectID', 'ProjectTitle', 'Notes'].map(name => ({ name, declaredType: 'TEXT' }));
  const row = { rowId: '-200', cells: [cell('integer', '-200'), cell('text', 'Proj1'), cell('text', 'Title1'), cell('null')] };
  const reviewObj = {
    project: 'SampleMeta',
    plotNumber: '00337',
    projectId: 'Proj1',
    projectRecords: { columns: cols, rows: [row] },
    masterTemplates: { columns: [], rows: [] },
  };
  const fieldDefs = [
    { name: 'ProjectTitle', kind: 'text', maximum: 255, collection: false, referenceList: '', referenceColumn: '', limitToList: false, options: [] },
    { name: 'Notes', kind: 'text', maximum: 0, collection: false, referenceList: '', referenceColumn: '', limitToList: false, options: [] },
  ];

  // 1. ProjectMetadataEditor save & error
  let script = read('admin/ProjectMetadataEditor.svelte').match(/<script lang="ts">([\s\S]*?)<\/script>/)[1];
  script = script.replace('allowRestoration = false', 'allowRestoration = false, inspect');
  script += `\n$effect(() => inspect({ select, stage, save, getState: () => ({ ready, error, success }) }));`;
  const compiled = compile(`<script lang="ts">${script}</script>`, { generate: 'client' });
  assert.equal(compiled.warnings.length, 0);

  const editorMod = { exports: {} };
  vm.runInNewContext(
    ts.transpileModule(compiled.js.code, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    }).outputText,
    {
      module: editorMod,
      exports: editorMod.exports,
      structuredClone,
      require(name) {
        if (name === 'svelte') return { onMount: fn => fn(), onDestroy: () => {} };
        if (name === 'svelte/internal/client') return client;
        if (name.startsWith('svelte/')) return require(name);
        if (name === '../shared/readRequests') return { ReadRequests: class { track(p) { return p; } cancelAll() {} } };
        if (name === './projectMetadataEditor') return metaMod;
        if (name === './projectMetadataPresentation') return metaPresMod;
        if (name === '../shell/notificationService.svelte') return { notifications: notifCtrl };
        if (name === './ProjectMetadataRestore.svelte') return {};
        throw new Error(`Unexpected module ${name}`);
      },
    }
  );

  let failSave = false;
  let editorApi;
  const disposeEditor = client.effect_root(() => {
    editorMod.exports.default(null, {
      client: {
        ReviewProjectMetadata: async () => structuredClone(reviewObj),
        ListProjectMetadataFields: async () => structuredClone(fieldDefs),
        SaveProjectMetadata: async () => { if (failSave) throw new Error('disk locked'); },
      },
      contextId: 'ctx-meta',
      plot: '00337',
      onclosed() {},
      onbusy() {},
      oncommitted: async () => {},
      inspect: v => { editorApi = v; },
    });
  });

  try {
    client.flush();
    await new Promise(r => setTimeout(r, 10));
    client.flush();

    editorApi.select('-200');
    editorApi.stage(fieldDefs[0], 'Updated Title', false);
    client.flush();
    await editorApi.save();
    client.flush();

    failSave = true;
    editorApi.stage(fieldDefs[0], 'Another Edit', false);
    client.flush();
    await editorApi.save();
    client.flush();
  } finally {
    disposeEditor();
  }

  // 2. ProjectMetadataRestore success notification
  let restoreScript = read('admin/ProjectMetadataRestore.svelte').match(/<script lang="ts">([\s\S]*?)<\/script>/)[1];
  restoreScript = restoreScript.replace('oncommitted }:', 'oncommitted, inspect }:');
  restoreScript = restoreScript.replace('oncommitted: (rowId: string) => Promise<void>;', 'oncommitted: (rowId: string) => Promise<void>; inspect?: (v: any) => void;');
  restoreScript += `\n$effect(() => inspect?.({ review, restore }));`;
  const compiledRestore = compile(`<script lang="ts">${restoreScript}</script>`, { generate: 'client' });
  assert.equal(compiledRestore.warnings.length, 0);

  const restoreObj = { exports: {} };
  vm.runInNewContext(
    ts.transpileModule(compiledRestore.js.code, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    }).outputText,
    {
      module: restoreObj,
      exports: restoreObj.exports,
      structuredClone,
      require(name) {
        if (name === 'svelte') return { onMount: fn => fn(), onDestroy: () => {} };
        if (name === 'svelte/internal/client') return client;
        if (name.startsWith('svelte/')) return require(name);
        if (name === '../../bindings/github.com/boostao/vpro/app') return { AuditRestoreAction: { AuditRestoreRetain: 'retain', AuditRestorePrune: 'prune' } };
        if (name === '../shared/readRequests') return { ReadRequests: class { track(p) { return p; } cancelAll() {} } };
        if (name === './projectMetadataEditor') return metaMod;
        if (name === './projectMetadataPresentation') return metaPresMod;
        if (name === './projectMetadataRestore') return restoreMod;
        if (name === '../shell/notificationService.svelte') return { notifications: notifCtrl };
        throw new Error(`Unexpected module ${name}`);
      },
    }
  );

  const currentRow = structuredClone(row);
  currentRow.cells[2] = cell('text', '');
  const restoredRow = structuredClone(row);
  let restoreApi;
  const disposeRestore = client.effect_root(() => {
    restoreObj.exports.default(null, {
      client: {
        ListProjectMetadataRestoreHistory: async () => ({
          historyPresent: true,
          events: [{ historyId: '9007199254740994', created: '2026-10-02T01:02:03Z', rowId: '-200', id: -200, fields: ['ProjectTitle'], restored: false }],
        }),
        ReviewProjectMetadataRestoration: async () => ({
          contextId: 'ctx-meta',
          historyId: '9007199254740994',
          project: 'SampleMeta',
          plotNumber: '00337',
          projectId: 'Proj1',
          id: -200,
          columns: cols,
          current: currentRow,
          restored: restoredRow,
          audits: [{
            rowId: '9007199254740993', project: 'SampleMeta', user: 'Tester', plotNumber: '00337',
            table: '_Metadata', editField: 'ProjectTitle', editWhen: '2026-10-02 01:02:03',
            beforeEdit: 'Title1', afterEdit: '', restore: false, flag: false, id: -200,
          }],
        }),
        RestoreProjectMetadata: async () => ({ cancelled: false, restoredRows: 1, prunedAuditRows: 0, cleanedVegRows: 0 }),
      },
      contextId: 'ctx-meta',
      plot: '00337',
      onclosed() {},
      onbusy() {},
      oncommitted: async () => {},
      inspect: v => { restoreApi = v; },
    });
  });

  try {
    client.flush();
    await new Promise(r => setTimeout(r, 10));
    client.flush();
    await restoreApi.review('9007199254740994');
    client.flush();
    await restoreApi.restore('retain');
    client.flush();
  } finally {
    disposeRestore();
  }

  const entries = notifCtrl.getSnapshot().entries;
  assert.equal(entries.length, 3);
  assert.ok(entries.every(e => e.category === 'admin' && e.source === 'Project Metadata'));
  assert.equal(entries[0].severity, 'success');
  assert.match(entries[0].title, /restored/i);
  assert.equal(entries[1].severity, 'error');
  assert.equal(entries[2].severity, 'success');
  assert.match(entries[2].title, /saved/i);
});

test('UniversalDatasheetGrid routes save, find/replace, delete, and Ctrl+S actions to entry notifications', async () => {
  const client = await import('svelte/internal/client');
  const notifCtrl = makeNotifController();
  const gridMod = loadTypeScript('universalDatasheetGrid.ts', {
    '@wailsio/runtime': { Call: { ByName: () => Promise.resolve(null) } },
    '../shell/notificationService.svelte': { notifications: notifCtrl },
  });

  let dsScript = read('datasheet/UniversalDatasheetGrid.svelte').match(/<script lang="ts">([\s\S]*?)<\/script>/)[1];
  dsScript = dsScript.replace(
    'onOpenPlot?: (plotNumber: string) => void;',
    'onOpenPlot?: (plotNumber: string) => void; inspect?: (v: any) => void;'
  );
  dsScript = dsScript.replace('onOpenPlot,', 'onOpenPlot, inspect,');
  dsScript += `\n$effect(() => inspect?.({
    setCellDraft,
    handleWindowKeydown,
    setFindArgs(col, f, r) { findColumn = col; findText = f; replaceText = r; },
    runFindPreview,
    applyFindReplaceValid,
    selectFirstRow() { activeCell = { row: 0, col: 0 }; },
    requestDeleteSelectedRow,
    confirmDeleteSelectedRow,
  }));`;

  const compiled = compile(`<script lang="ts">${dsScript}</script>`, { generate: 'client' });
  assert.equal(compiled.warnings.length, 0);

  const dsMod = { exports: {} };
  vm.runInNewContext(
    ts.transpileModule(compiled.js.code, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    }).outputText,
    {
      module: dsMod,
      exports: dsMod.exports,
      structuredClone,
      queueMicrotask,
      require(name) {
        if (name === 'svelte') return { onMount: fn => fn(), onDestroy: () => {}, untrack: client.untrack };
        if (name === 'svelte/internal/client') return client;
        if (name.startsWith('svelte/')) return require(name);
        if (name.endsWith('/readRequests')) return { ReadRequests: class { track(p) { return p; } cancelAll() {} } };
        if (name.endsWith('/universalDatasheetGrid')) return gridMod;
        throw new Error(`Unexpected module ${name}`);
      },
    }
  );

  let api;
  const dispose = client.effect_root(() => {
    dsMod.exports.default(null, {
      contextId: 'ctx-ds-notif',
      project: 'Skeena2026',
      initialTableKey: 'Veg',
      port: {
        listTables: async () => [{ key: 'Veg', tableName: 'Skeena2026_Veg', available: true, rowCount: 1 }],
        getPage: async () => ({
          tableKey: 'Veg',
          tableName: 'Skeena2026_Veg',
          totalRows: 1,
          offset: 0,
          limit: 250,
          canEditMaster: false,
          columns: [
            { name: 'PlotNumber', declaredType: 'TEXT', kind: 'text', pinned: true, editable: false, protected: false, maxUtf16: 7, isCoverSingle: false, isBoolean: false },
            { name: 'Species', declaredType: 'TEXT', kind: 'text', pinned: false, editable: true, protected: false, maxUtf16: 8, isCoverSingle: false, isBoolean: false },
          ],
          rows: [{ rowId: '1', cells: [{ storage: 'text', text: '00337' }, { storage: 'text', text: 'PSEUMEN' }] }],
        }),
        applyEdits: async () => ({ updatedCells: 1, updatedRows: 1, auditRows: 1 }),
        previewFindReplace: async () => ({
          tableKey: 'Veg',
          tableName: 'Skeena2026_Veg',
          column: 'Species',
          matchedRows: 1,
          validCount: 1,
          invalidCount: 0,
          truncated: false,
          items: [{
            rowId: '1',
            plotNumber: '00337',
            validationError: '',
            edit: { rowId: '1', column: 'Species', before: { storage: 'text', text: 'PSEUMEN' }, after: { storage: 'text', text: 'TSUGHET' } },
          }],
        }),
        deleteChildRow: async () => ({ tableName: 'Skeena2026_Veg', deletedId: 1, plotNumber: '00337', auditRows: 1 }),
      },
      inspect: v => { api = v; },
    });
  });

  try {
    client.flush();
    await new Promise(r => setTimeout(r, 10));
    client.flush();

    // Stage edit and trigger Ctrl+S
    api.setCellDraft(0, 1, 'TSUGHET');
    client.flush();
    api.handleWindowKeydown({ ctrlKey: true, metaKey: false, altKey: false, shiftKey: false, key: 's', preventDefault() {} });
    await new Promise(r => setTimeout(r, 10));
    client.flush();

    api.setFindArgs('Species', 'PSEUMEN', 'TSUGHET');
    client.flush();
    await api.runFindPreview();
    await api.applyFindReplaceValid();
    client.flush();

    api.selectFirstRow();
    api.requestDeleteSelectedRow();
    client.flush();
    await api.confirmDeleteSelectedRow();
    client.flush();

    const entries = notifCtrl.getSnapshot().entries;
    assert.equal(entries.length, 3);
    assert.ok(entries.every(e => e.category === 'entry' && e.source === 'Datasheet Grid' && e.contextTag === 'Skeena2026' && e.severity === 'success'));
    assert.match(entries[0].message, /Deleted row ID 1/);
    assert.match(entries[1].message, /Applied 1 replacement/);
    assert.match(entries[2].message, /Saved 1 cell\(s\)/);
  } finally {
    dispose();
  }
});

test('RSidecarWorkbench routes runtime check, climate/aSMR, clustering, candidate promotion, and Quarto render to background notifications', async () => {
  const client = await import('svelte/internal/client');
  const notifCtrl = makeNotifController();
  const quality = loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });
  const rMod = loadTypeScript('rSidecarWorkbench.ts', {
    '../../bindings/github.com/boostao/vpro/app': mockBindings,
    './qualityEditor': quality,
    '../shell/notificationService.svelte': { notifications: notifCtrl },
  });

  let script = read('rsidecar/RSidecarWorkbench.svelte').match(/<script lang="ts">([\s\S]*?)<\/script>/)[1];
  script = script.replace('oncontextswitched,', 'oncontextswitched, inspect,');
  script += `\n$effect(() => inspect({
    refreshRRuntime,
    runClimateAndDualEdatopic,
    submitClustering,
    setPromoteTarget(t) { promoteTargetSuName = t; promoteConfirmOverwrite = true; },
    submitPromoteCandidate,
    submitRenderQuartoGuide,
  }));`;

  const compiled = compile(`<script lang="ts">${script}</script>`, { generate: 'client' });
  assert.equal(compiled.warnings.length, 0);

  const modObj = { exports: {} };
  vm.runInNewContext(
    ts.transpileModule(compiled.js.code, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    }).outputText,
    {
      module: modObj,
      exports: modObj.exports,
      structuredClone,
      require(name) {
        if (name === 'svelte') return { onDestroy: () => {} };
        if (name === 'svelte/internal/client') return client;
        if (name.startsWith('svelte/')) return require(name);
        if (name === './rSidecarWorkbench') return rMod;
        throw new Error(`Unexpected module ${name}`);
      },
    }
  );

  let failQuarto = false;
  let api;
  const dispose = client.effect_root(() => {
    modObj.exports.default(null, {
      contextId: 'ctx-r',
      activeProject: 'Babine_2026',
      activeSu: 'Babine_SU',
      port: {
        async detectRRuntime() {
          return {
            available: true, rscriptPath: '/usr/bin/Rscript', rVersion: '4.6.2', rVersionFull: 'R 4.6.2',
            platform: 'linux', quartoAvailable: true, quartoPath: '/usr/bin/quarto', quartoVersion: '1.9.38',
            climrCachePath: '', climrRastersCached: false, readyForClimate: true, readyForClustering: true,
            readyForQuarto: true, missingRequired: [], packages: [], setupInstructions: [],
          };
        },
        async computePlotClimateAndDualEdatopic() {
          return {
            contextId: 'ctx-r', project: 'Babine_2026', activeSu: 'Babine_SU', refPeriod: '1961_1990',
            totalScopedPlots: 10, coordinatizedPlots: 10, skippedNoCoords: 0, cacheHits: 2, cacheMisses: 8,
            sourceSummary: {}, overallRelative: { kind: 'relative', moistureAxis: [], nutrientAxis: [], totalPlots: 0, modalCell: '', cells: [] },
            overallActual: { kind: 'actual', moistureAxis: [], nutrientAxis: [], totalPlots: 0, modalCell: '', cells: [] },
            unitSummaries: [], plots: [],
          };
        },
        async runMultivariateClustering() {
          return {
            contextId: 'ctx-r', project: 'Babine_2026', activeSu: 'Babine_SU', method: 'NC', distance: 'bray',
            linkage: 'ward.D2', transform: 'sqrt', k: 3, plotCount: 10, speciesCount: 20, lumpAppliedRows: 0,
            copheneticCorrelation: 0.85, meanSilhouette: 0.42, noiseCount: 0,
            candidateSuName: 'Babine_ClusterCandidate', candidateTableName: 'Babine_ClusterCandidate_SU',
            materializedRows: 10, clusters: [{ clusterUnit: 'BEC_01' }], memberships: [],
            dendrogram: { maxHeight: 1, cutHeight: 0.5, newick: '(A:0.5,B:0.5);', segments: [], leaves: [] },
          };
        },
        async promoteClusterCandidateToSU() {
          return {
            contextId: 'ctx-r', candidateTableName: 'Babine_ClusterCandidate_SU', targetSuName: 'Babine_Final',
            targetTableName: 'Babine_Final_SU', overwroteExisting: false, promotedRows: 10, skippedNoiseRows: 0, activated: false,
          };
        },
        async renderQuartoGuide() {
          if (failQuarto) throw new Error('Quarto template missing');
          return {
            contextId: 'ctx-r', guideType: 'single_unit', title: 'Guide', targetUnit: 'SBSmc2/01',
            bgcLabel: 'SBSmc2', plotCount: 10, speciesRowCount: 5, rendererUsed: 'quarto',
            htmlPath: '/exports/guide.html', htmlSizeBytes: 2048, htmlSha256: 'a'.repeat(64), htmlPreview: '<html></html>', vegetationTable: [],
          };
        },
      },
      inspect: v => { api = v; },
    });
  });

  try {
    client.flush();
    await api.refreshRRuntime();
    await api.runClimateAndDualEdatopic();
    await api.submitClustering();
    api.setPromoteTarget('Babine_Final');
    client.flush();
    await api.submitPromoteCandidate();
    await api.submitRenderQuartoGuide();
    failQuarto = true;
    await api.submitRenderQuartoGuide();
    client.flush();

    const entries = notifCtrl.getSnapshot().entries;
    assert.equal(entries.length, 6);
    assert.ok(entries.every(e => e.category === 'background' && e.source === 'R Companion' && e.contextTag === 'Babine_2026'));
    assert.equal(entries[0].severity, 'error');
    assert.match(entries[0].message, /Quarto template missing/);
    assert.equal(entries[1].severity, 'success');
    assert.equal(entries[2].severity, 'success');
    assert.equal(entries[3].severity, 'success');
    assert.equal(entries[4].severity, 'success');
    assert.equal(entries[5].severity, 'success');
  } finally {
    dispose();
  }
});
