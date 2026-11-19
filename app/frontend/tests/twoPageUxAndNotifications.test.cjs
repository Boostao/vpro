const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const { runInNewContext } = require('node:vm');
const { compile } = require('svelte/compiler');
const { render } = require('svelte/server');
const { componentFunctions, loadTypeScript, serverComponent, srcPath } = require('./svelteTestHelpers.cjs');

const read = name => readFileSync(srcPath(name), 'utf8');

test('FS882Form decouples host onBusyChange from twoPageOpen while keeping internal mutex invariants', () => {
  const formSrc = read('FS882Form.svelte');
  assert.equal(compile(formSrc, { filename: srcPath('FS882Form.svelte'), generate: 'client' }).warnings.length, 0);

  // External host busy uses hostEditorBusy rather than headerWorkflowBusy
  assert.match(formSrc, /\$effect\(\(\) => \{\s*onBusyChange\?\.\(hostEditorBusy\);\s*\}\);/);
  assert.doesNotMatch(formSrc, /onBusyChange\?\.\(busy \|\| headerWorkflowBusy/);

  const hostExpr = formSrc.match(/const hostEditorBusy = \$derived\(([\s\S]*?)\n  \);/)?.[1];
  assert.ok(hostExpr, 'hostEditorBusy derived expression must exist');

  const idleEnv = {
    busy: false, siviSourceAuthorityUnknown: false,
    coordinateBusy: false, workingUnitBusy: false, qualityBusy: false, siteCodeBusy: false, regionCodeBusy: false,
    soilCodeBusy: false, geologyCodeBusy: false, parentCodeBusy: false, drainageBusy: false, speciesDecisionBusy: false,
    deletionBusy: false, codeCheckBusy: false, metadataBusy: false, profileReviewBusy: false,
    externalSUEnvironmentBusy: false, externalSUEnvironmentBlocked: false,
    siviParentBusy: false, siviBusy: false, siviCombinedBusy: false, siviCoverBusy: false, siviCollectedBusy: false,
    siviSpeciesBusy: false, siviIdentityBusy: false, siviCreationBusy: false, siviLifecycleBusy: false,
    twoPageBusy: false, pictureBusy: false, pictureMetadataClose: null,
    twoPageSoilBusy: false, twoPageSoilBlocked: false, twoPageVegetationBusy: false, twoPageVegetationBlocked: false,
    twoPageOpen: true, twoPageEditor: { getCloseState: () => ({}) },
    environmentSUOpen: false, environmentSUEditor: null,
    metadataOpen: false, metadataEditor: null,
    codeCheckOpen: false, codeCheckEditor: null,
  };

  // Mounted idle Two-Page editor must NOT hold global app in Busy
  assert.equal(runInNewContext(hostExpr, idleEnv), false);
  // Lazy-loading Two-Page editor before mount MUST hold Busy
  assert.equal(runInNewContext(hostExpr, { ...idleEnv, twoPageEditor: undefined }), true);
  // Active two-page async operation MUST hold Busy
  assert.equal(runInNewContext(hostExpr, { ...idleEnv, twoPageBusy: true }), true);
  // Active form async operation MUST hold Busy
  assert.equal(runInNewContext(hostExpr, { ...idleEnv, busy: true }), true);

  // Outer 6x4 chrome is hidden only in standalone two-page entry mode when mounted
  assert.match(formSrc, /const standaloneTwoPage = \$derived\(entryForm === 'fs882-twopage'\);/);
  assert.match(formSrc, /<header hidden=\{standaloneTwoPage && twoPageOpen && twoPageScope === 'entry'\}/);
  assert.match(formSrc, /<nav[^>]*hidden=\{standaloneTwoPage && twoPageOpen && twoPageScope === 'entry'\}/);
});

test('standalone TwoPageEntryEditor exposes clean Ready close state, dirty saveForClose, and preserves inline barrier', async () => {
  const twoPageSrc = read('TwoPageEntryEditor.svelte');
  assert.equal(compile(twoPageSrc, { filename: srcPath('TwoPageEntryEditor.svelte'), generate: 'client' }).warnings.length, 0);

  let saves = 0;
  const makeHost = (standalone, overrides = {}) => {
    const clean = { unsaved: false, busy: false, blocked: false, canSave: true, saveReason: '', error: null };
    const session = {
      closeState: () => clean,
      view: () => ({ original: {}, error: null, referenceError: null }),
      save: async () => { saves++; clean.unsaved = false; return true; },
    };
    return componentFunctions('TwoPageEntryEditor.svelte', ['getCloseState', 'getDraftState', 'saveForClose', 'operation'], {
      standalone,
      form: 'FS882-8x6XL',
      owner: { contextId: 'ctx-1', project: 'Sample', plot: '202050' },
      reviewEnabled: true,
      editingEnabled: true,
      childBlocked: false,
      externalOpen: false,
      sourceRefreshing: false,
      auditOpen: false,
      auditBusy: false,
      googleEarthOpen: false,
      googleEarthBusy: false,
      vegetationTableOpen: false,
      vegetationTableBusy: false,
      environmentTableOpen: false,
      environmentTableBusy: false,
      projectMetadataOpen: null,
      projectMetadataBusy: false,
      profilingOpen: false,
      profilingBusy: false,
      AuditRestoreAction: {},
      error: null,
      close: clean,
      view: { original: {}, error: null, referenceError: null },
      sessions: new Map([['FS882-8x6XL', session]]),
      session,
      ...overrides,
    });
  };

  // Standalone clean plot -> Ready (unsaved: false, canSave: true)
  const cleanStandalone = makeHost(true);
  assert.deepEqual({ ...cleanStandalone.actions.getCloseState() }, {
    unsaved: false, busy: false, blocked: false, canSave: true, saveReason: '', error: null,
  });

  // Standalone dirty valid plot -> Unsaved Draft, saveForClose delegates to operation('save')
  const dirtyStandalone = makeHost(true);
  dirtyStandalone.close.unsaved = true;
  const dirtyClose = dirtyStandalone.actions.getCloseState();
  assert.equal(dirtyClose.unsaved, true);
  assert.equal(dirtyClose.canSave, true);
  assert.equal(await dirtyStandalone.actions.saveForClose(), true);
  assert.equal(saves, 1);

  // Default inline sub-review (standalone = false) retains explicit close barrier
  const inlineReview = makeHost(false);
  const inlineClose = inlineReview.actions.getCloseState();
  assert.equal(inlineClose.unsaved, true);
  assert.equal(inlineClose.canSave, false);
  assert.match(inlineClose.saveReason, /close their review/);
});

test('WorkspaceSidebar routes Data on Disk and SQLite picker messages to notifications with zero inline PROJECTS banner', async () => {
  const sidebarSrc = read('shell/WorkspaceSidebar.svelte');
  assert.equal(compile(sidebarSrc, { filename: srcPath('shell/WorkspaceSidebar.svelte'), generate: 'client' }).warnings.length, 0);

  assert.doesNotMatch(sidebarSrc, /revealMessage|revealError|externalPickMessage|externalPickError/);

  const { createNotificationController } = loadTypeScript('shell/notificationService.svelte.ts', {
    'svelte/store': require('svelte/store'),
  });
  const notifications = createNotificationController({
    schedule: () => 0,
    cancelSchedule: () => {},
  });

  const okHost = componentFunctions('WorkspaceSidebar.svelte', ['revealInExplorer'], {
    $projectState: { contextId: 'ctx-1' },
    ContextService: { RevealInFileExplorer: async (_cid, target) => `C:\\vpro\\${target}` },
    notifications,
  });
  await okHost.actions.revealInExplorer('root');

  const errHost = componentFunctions('WorkspaceSidebar.svelte', ['revealInExplorer'], {
    $projectState: { contextId: 'ctx-1' },
    ContextService: { RevealInFileExplorer: async () => { throw new Error('Explorer unavailable'); } },
    notifications,
  });
  await errHost.actions.revealInExplorer('project');

  const snap = notifications.getSnapshot();
  assert.equal(snap.entries.length, 2);
  assert.equal(snap.entries[0].severity, 'error');
  assert.equal(snap.entries[0].title, 'Could not open File Explorer');
  assert.match(snap.entries[0].message, /Explorer unavailable/);
  assert.equal(snap.entries[1].severity, 'info');
  assert.equal(snap.entries[1].title, 'Opened in File Explorer');
  assert.equal(snap.entries[1].message, 'C:\\vpro\\root');
  assert.equal(snap.toasts.length, 2);
});

test('App and shell panels route operational errors and startup recovery notices to notifications with zero duplicate inline error banners', async () => {
  const appSrc = read('App.svelte');
  const cssSrc = read('vpro.css');
  const twoPageSrc = read('TwoPageEntryEditor.svelte');
  const plotsPanelSrc = read('shell/PlotsBrowserPanel.svelte');
  const statusBannersSrc = read('shell/WorkspaceStatusBanners.svelte');

  for (const [rel, src] of [
    ['App.svelte', appSrc],
    ['shell/PlotsBrowserPanel.svelte', plotsPanelSrc],
    ['shell/WorkspaceStatusBanners.svelte', statusBannersSrc],
  ]) {
    assert.equal(compile(src, { filename: srcPath(rel), generate: 'client' }).warnings.length, 0, `${rel} client compile must have 0 warnings`);
    assert.equal(compile(src, { filename: srcPath(rel), generate: 'server' }).warnings.length, 0, `${rel} server compile must have 0 warnings`);
  }

  // Zero inline {#if error}<p class="error" operational banners or redundant green notice banners remain
  assert.equal((appSrc.match(/\{#if error\}<p class="error"/g) ?? []).length, 0);
  assert.equal((plotsPanelSrc.match(/\{#if error\}<p class="error"/g) ?? []).length, 0);
  assert.doesNotMatch(appSrc, /data-startup-backup-notice/);
  assert.doesNotMatch(appSrc, /ondismisserror=/);
  assert.doesNotMatch(statusBannersSrc, /data-reset-sample-notice/);

  // Script state, auto-clear effect, Find Plot inline validation, and lazy-chunk catch fallback remain intact
  assert.match(appSrc, /let offset = \$state\(0\), busy = \$state\(false\), error = \$state\(''\);/);
  assert.match(appSrc, /let resetSampleConfirmOpen = \$state\(false\), resetSampleNotice = \$state\(''\);/);
  assert.match(appSrc, /let startupBackupNotice = \$state\(''\);/);
  assert.match(appSrc, /error === 'Wait for the current operation or decision before changing context\.'/);
  assert.match(appSrc, /data-entry-load-error="fs882"/);
  assert.match(appSrc, /aria-label="Find scoped plot"/);

  // App.svelte routes error (via deduped $effect + requestTransition) and startupBackupNotice (onrecovered) into notifications
  assert.match(appSrc, /let lastPushedError = '';/);
  assert.match(
    appSrc,
    /\$effect\(\(\) => \{\s*const currentError = error;[\s\S]*?lastPushedError = currentError;[\s\S]*?notifications\.push\(\{[\s\S]*?category:\s*'general'[\s\S]*?source:\s*'Workspace'[\s\S]*?message:\s*currentError[\s\S]*?toast:\s*true/
  );
  assert.match(
    appSrc,
    /onrecovered=\{async \(notice\) => \{[\s\S]*?startupBackupNotice = notice;[\s\S]*?notifications\.success\('Startup recovery complete', notice, \{ source: 'Startup Recovery' \}\)/
  );

  // Runtime requestTransition pushes Navigation paused warning once and sets lastPushedError to prevent $effect double-push
  const { createNotificationController } = loadTypeScript('shell/notificationService.svelte.ts', {
    'svelte/store': require('svelte/store'),
  });
  const notifications = createNotificationController({ schedule: () => 0, cancelSchedule: () => {} });
  const transitionCtx = componentFunctions('App.svelte', ['requestTransition'], {
    document: { activeElement: null },
    HTMLElement: class {},
    tick: async () => {},
    closeDisposition: () => 'busy',
    view: 'plots',
    editor: null,
    busy: true,
    editorBusy: false,
    companionPanelBusy: false,
    workbenchDirtyLabel: '',
    transitionWorking: false,
    archivePublicationBusy: false,
    vegetationPublicationBusy: false,
    lifeformPublicationBusy: false,
    summaryPublicationBusy: false,
    pendingTransition: null,
    closeRequest: '',
    editorInitializing: false,
    $projectState: { contextId: 'ctx-1' },
    error: '',
    lastPushedError: '',
    transitionError: '',
    notifications,
  });
  await transitionCtx.actions.requestTransition(async () => {});
  assert.equal(transitionCtx.error, 'Wait for the current operation or decision before changing context.');
  assert.equal(transitionCtx.lastPushedError, transitionCtx.error);
  const snap = notifications.getSnapshot();
  assert.equal(snap.entries.length, 1);
  assert.equal(snap.entries[0].severity, 'warning');
  assert.equal(snap.entries[0].title, 'Navigation paused');
  assert.equal(snap.entries[0].message, transitionCtx.error);
  assert.equal(snap.toasts.length, 1);

  // PlotsBrowserPanel & WorkspaceStatusBanners SSR cleanly without inline operational error or resetSample banners
  const iconsProxy = new Proxy({}, { get: () => () => {} });
  const BrowserSSR = serverComponent(plotsPanelSrc, 'shell/PlotsBrowserPanel.svelte', {
    '@lucide/svelte': iconsProxy,
    '../shared/state': { projectState: { subscribe: (fn) => { fn({ activeProject: 'Sample' }); return () => {}; } } },
  });
  const browserHtml = render(BrowserSSR, {
    props: { region: 'main', view: 'plots', error: 'Transient load failure', page: { total: 0, plots: [] } },
  }).body;
  assert.doesNotMatch(browserHtml, /Transient load failure/);
  assert.doesNotMatch(browserHtml, /class="error"/);

  const BannersSSR = serverComponent(statusBannersSrc, 'shell/WorkspaceStatusBanners.svelte', {});
  const bannersHtml = render(BannersSSR, {
    props: {
      region: 'banners',
      startupFailed: true,
      resetSampleNotice: 'Workspace reset',
      diagnostics: [{ file: 'Sample.db', message: 'Check schema' }],
    },
  }).body;
  assert.match(bannersHtml, /class="project-warning"/);
  assert.match(bannersHtml, /Sample\.db: Check schema/);
  assert.doesNotMatch(bannersHtml, /data-reset-sample-notice/);

  // Global zero-specificity default styling for unclassed buttons
  assert.match(cssSrc, /:where\(button:not\(\[class\]\)/);

  // TwoPageEntryEditor uses plain-language labels and styled toolbar buttons
  assert.doesNotMatch(twoPageSrc, /one owned complete-entry draft|: read-only saved data|Return to complete-entry source/);
  assert.match(twoPageSrc, /FS882 \(2-Page\): Ecosystem Field Form/);
  assert.match(twoPageSrc, /Back to Two-Page Form/);
  assert.match(twoPageSrc, /Close Form/);
});
