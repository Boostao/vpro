const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { compile } = require('svelte/compiler');
const { render } = require('svelte/server');
const { writable } = require('svelte/store');
const { componentFunctions, loadTypeScript, serverComponent, srcPath } = require('./svelteTestHelpers.cjs');

const iconsProxy = new Proxy({}, { get: () => () => {} });

test('Desktop shell cleanup removes context-strip, right-hand inspector rail, PlotProfilePanel, and non-opening What\'s New banners', () => {
  const headerSrc = readFileSync(srcPath('shell/ShellChromeHeader.svelte'), 'utf8');
  const frameSrc = readFileSync(srcPath('shell/ShellFrame.svelte'), 'utf8');
  const routerSrc = readFileSync(srcPath('shell/ShellWorkspaceRouter.svelte'), 'utf8');
  const uiCtrlSrc = readFileSync(srcPath('shell/shellUiController.svelte.ts'), 'utf8');
  const homeSrc = readFileSync(srcPath('shell/HomeWorkspaceHub.svelte'), 'utf8');

  // 1. Top context-strip removed
  assert.doesNotMatch(headerSrc, /data-context-strip/);
  assert.doesNotMatch(headerSrc, /class="context-strip"/);

  // 2. Right-hand Workspace Inspector rail completely removed
  assert.doesNotMatch(headerSrc, /data-inspector-toggle/);
  assert.doesNotMatch(headerSrc, /showInspectorToggle/);
  assert.doesNotMatch(frameSrc, /showInspectorRail/);
  assert.doesNotMatch(routerSrc, /showInspectorRail/);
  assert.doesNotMatch(routerSrc, /region="detail"/);
  assert.doesNotMatch(uiCtrlSrc, /showInspectorRail|showInspectorToggle/);

  // 3. PlotProfilePanel removed from shell router
  assert.doesNotMatch(routerSrc, /PlotProfilePanel/);

  // 4. What's New banner only appears on the minimal opening screen (view === 'home')
  assert.doesNotMatch(routerSrc, /whatsNewPromptDismissed/);
  assert.match(routerSrc, /view === 'home'[\s\S]*<HomeWorkspaceHub[\s\S]*whatsNewStatus=\{ui\.whatsNewStatus\}/);
  assert.match(homeSrc, /data-opening-whats-new/);
  assert.doesNotMatch(homeSrc, /data-home-workflow-grid/);
});

test('Exact 8-menu architecture: Work Space toggle + Forms, Reports, Analysis, Project Management, Map, Interchange, Help in exact order', () => {
  const headerSrc = readFileSync(srcPath('shell/ShellChromeHeader.svelte'), 'utf8');
  const navSrc = readFileSync(srcPath('shell/Navigation.svelte'), 'utf8');
  const deferredSrc = readFileSync(srcPath('shell/ShellDeferredViews.svelte'), 'utf8');

  assert.deepEqual(compile(headerSrc, { filename: 'ShellChromeHeader.svelte', generate: 'client' }).warnings, []);
  assert.deepEqual(compile(navSrc, { filename: 'Navigation.svelte', generate: 'client' }).warnings, []);
  assert.deepEqual(compile(deferredSrc, { filename: 'ShellDeferredViews.svelte', generate: 'client' }).warnings, []);

  // Sidebar toggle renamed from "Projects & context" -> "Work Space"
  assert.match(headerSrc, /Work Space/);
  assert.doesNotMatch(headerSrc, /Projects & context/);

  const Nav = serverComponent(navSrc, 'Navigation.svelte', {
    '@lucide/svelte': iconsProxy,
    '../shared/state': { webShellRuntime: writable(null) },
    '../web/runtimeMode': { IS_WEB_READONLY: false },
  });
  const html = render(Nav, {
    props: {
      view: 'home',
      onnavigate: () => {},
      siviAvailable: true,
      onopensivi: () => {},
      newSiviAvailable: true,
      onopennewsivi: () => {},
      metadataAvailable: true,
      onopenmetadata: () => {},
      onopencloudsync: () => {},
      onopenauthsignin: () => {},
      onhelpaction: () => {},
      releaseChannel: 'stable',
    },
  }).body;

  // Verify exact top-level order in <nav>
  const topTokens = [];
  for (const match of html.matchAll(/data-nav-group="([^"]+)"|data-nav-top="([^"]+)"/g)) {
    const token = match[1] || match[2];
    if (['Forms', 'Reports', 'Analysis', 'Project Management', 'Map', 'Interchange', 'Help'].includes(token)) {
      if (topTokens[topTokens.length - 1] !== token) topTokens.push(token);
    }
  }
  assert.deepEqual(topTokens, [
    'Forms',
    'Reports',
    'Analysis',
    'Project Management',
    'Map',
    'Interchange',
    'Help',
  ]);

  // Home, Plots, Two-Page Entry, and "3D Map" removed from top navigation
  assert.doesNotMatch(html, />Home<\/button>/);
  assert.doesNotMatch(html, />Plots<\/button>/);
  assert.doesNotMatch(html, /Two-Page Entry/);
  assert.doesNotMatch(html, /3D Map/);

  // Extract Reports dropdown HTML to verify Map / Diagnostics / R Analytics were removed and Quarto Unit Report added
  const reportsBlock = html.match(/data-nav-group="Reports"[\s\S]*?<\/details>/)?.[0] ?? '';
  assert.ok(reportsBlock, 'Reports menu must render');
  assert.match(reportsBlock, /Summary Vegetation/);
  assert.match(reportsBlock, /Long Vegetation/);
  assert.match(reportsBlock, /Lifeform &amp; Species Attributes/);
  assert.match(reportsBlock, /Long Environment/);
  assert.match(reportsBlock, /Summary Environment/);
  assert.match(reportsBlock, /Quarto Unit Report/);
  assert.match(reportsBlock, /Subzone Matrix of Units/);
  assert.match(reportsBlock, /Hierarchy Table/);
  assert.match(reportsBlock, /Plot Label PDF/);
  assert.match(reportsBlock, /Plot Locations/);
  assert.match(reportsBlock, /Google Earth KML/);
  assert.doesNotMatch(reportsBlock, /geospatial-map|diagnostic-synthesis|r-sidecar/);

  // Analysis menu has BEC Diagnostic & Pairwise Synthesis and R Climate, aSMR & Multivariate Clustering
  const analysisBlock = html.match(/data-nav-group="Analysis"[\s\S]*?<\/details>/)?.[0] ?? '';
  assert.match(analysisBlock, /BEC Diagnostic &amp; Pairwise Synthesis/);
  assert.match(analysisBlock, /R Climate, aSMR &amp; Multivariate Clustering/);

  // Project Management menu has Lifecycle/QA/Merge, Cloud BECMaster Sync, SU & Hierarchy Explorer, Combine Species, Sign In & Access, User Log
  const pmBlock = html.match(/data-nav-group="Project Management"[\s\S]*?<\/details>/)?.[0] ?? '';
  assert.match(pmBlock, /Project Lifecycle, QA &amp; Merge/);
  assert.match(pmBlock, /Cloud BECMaster Sync/);
  assert.match(pmBlock, /SU &amp; Hierarchy Explorer/);
  assert.match(pmBlock, /Combine Species/);
  assert.match(pmBlock, /Sign In &amp; Access/);
  assert.match(pmBlock, /User Log/);

  // ShellDeferredViews routes 'quarto-unit-report' to RSidecarWorkbench with initialTab="quarto"
  assert.match(deferredSrc, /view === 'quarto-unit-report'/);
  assert.match(deferredSrc, /import\('\.\.\/rsidecar\/RSidecarWorkbench\.svelte'\)/);
  assert.match(deferredSrc, /initialTab="quarto"/);
});

test('Work Space sidebar renders identical Project/SU/Hierarchy dropdown boxes with Attach/Remove/New, Access auto-convert confirmation, VPro64 export, and Auth status card', async () => {
  const sidebarSrc = readFileSync(srcPath('shell/WorkspaceSidebar.svelte'), 'utf8');
  assert.deepEqual(compile(sidebarSrc, { filename: 'WorkspaceSidebar.svelte', generate: 'client' }).warnings, []);
  assert.doesNotMatch(sidebarSrc, /\bSQLite\b/, 'User-facing copy must follow CBC plain-language standard');
  assert.doesNotMatch(sidebarSrc, /id="access-import-wizard"/, 'Legacy separate Access import wizard must be removed');

  const sampleState = {
    contextId: 'ctx-ws-1',
    activeProject: 'Sample',
    projectPath: '/data/Sample.db',
    activeSU: 'Sample_SU',
    suPath: '/data/Sample.db',
    activeHierarchy: 'Sample_Hier',
    hierarchyPath: '/data/Sample.db',
    projects: [{ name: 'Sample', file: 'Sample.db', path: '/data/Sample.db', version: 'VP08', compatible: true }],
    sus: [{ name: 'Sample_SU', kind: 'ordinary', path: '/data/Sample.db', compatible: true }],
    hierarchies: [{ name: 'Sample_Hier', file: 'Sample.db', path: '/data/Sample.db', compatible: true }],
  };

  const Sidebar = serverComponent(sidebarSrc, 'WorkspaceSidebar.svelte', {
    '@lucide/svelte': iconsProxy,
    '../shared/state': { projectState: writable(sampleState), webShellRuntime: writable(null) },
    '../web/runtimeMode': { IS_WEB_READONLY: false },
    '../../bindings/github.com/boostao/vpro/app': {
      ContextService: {},
      ImportExportService: {},
    },
  });

  const html = render(Sidebar, {
    props: {
      busy: false,
      editorBusy: false,
      companionPanelBusy: false,
      transitionWorking: false,
      requestTransition: async () => {},
      switchContext: async () => {},
      onAccessActivated: async () => {},
      onOpenAuthSignIn: () => {},
    },
  }).body;

  for (const kind of ['project', 'su', 'hierarchy']) {
    assert.match(html, new RegExp(`data-ws-section="${kind}"`));
    assert.match(html, new RegExp(`data-ws-attach="${kind}"`));
    assert.match(html, new RegExp(`data-ws-remove="${kind}"`));
    assert.match(html, new RegExp(`data-ws-new="${kind}"`));
    assert.match(html, new RegExp(`data-ws-select="${kind}"`));
  }
  assert.match(html, /data-ws-export-vpro64/);
  assert.match(html, /Export to VPro64/);
  assert.match(html, /data-ws-auth-card/);
  assert.match(html, /Data locked/);

  // Test unified Attach, Access auto-convert prompt, Unattach, Create, and Export to VPro64 operations
  const readRequestsMod = loadTypeScript('shared/readRequests.ts', {
    '@wailsio/runtime': {
      Call: { RuntimeError: class extends Error {} },
      CancelledRejectionError: class extends Error {},
    },
  });
  const notifMod = loadTypeScript('shell/notificationService.svelte.ts', {
    'svelte/store': require('svelte/store'),
  });
  const notify = notifMod.createNotificationController({ schedule: () => 0, cancelSchedule: () => {} });
  const ops = loadTypeScript('shell/workspaceSidebarOps.ts', {
    '../shared/readRequests': readRequestsMod,
    './notificationService.svelte': { notifications: notify },
  });

  // 1. Access inspection sets requiresConvert = true and triggers confirmation
  const accessInspection = {
    selectedPath: '/legacy/Field2024.accdb',
    fileKind: 'access',
    requiresConvert: true,
    projects: [{ name: 'Field2024', file: 'Field2024.accdb', version: 'VP07', compatible: true, path: '/legacy/Field2024.accdb' }],
    sus: [],
    hierarchies: [],
  };
  assert.equal(ops.requiresAccessConversion(accessInspection), true);
  assert.deepEqual(JSON.parse(JSON.stringify(ops.extractAttachCandidates('project', accessInspection))), [
    { name: 'Field2024', label: 'Field2024', compatible: true },
  ]);

  const rpcCalls = [];
  const attachRes = await ops.runAttachWorkspaceResourceOp({
    contextId: 'ctx-ws-1',
    kind: 'project',
    path: '/legacy/Field2024.accdb',
    name: 'Field2024',
    activate: true,
    contextService: {
      AttachWorkspaceResource: async (ctxId, req) => {
        rpcCalls.push(['attach', ctxId, req]);
        return { kind: 'project', attached: [{ name: 'Field2024' }], activated: true, converted: true, state: sampleState };
      },
    },
    notify,
  });
  assert.equal(attachRes.converted, true);
  assert.equal(rpcCalls[0][2].kind, 'project');

  // 2. Unattach keeps disk file intact
  const unattachRes = await ops.runUnattachWorkspaceResourceOp({
    contextId: 'ctx-ws-1',
    kind: 'su',
    name: 'Sample_SU',
    path: '/data/Sample.db',
    contextService: {
      UnattachWorkspaceResource: async (ctxId, req) => {
        rpcCalls.push(['unattach', ctxId, req]);
        return { kind: 'su', name: 'Sample_SU', path: '/data/Sample.db', fileRetained: true, state: sampleState };
      },
    },
    notify,
  });
  assert.equal(unattachRes.fileRetained, true);

  // 3. Create standalone multi-SU database
  const createRes = await ops.runCreateWorkspaceResourceOp({
    contextId: 'ctx-ws-1',
    request: {
      kind: 'su',
      name: 'CoastalUnits',
      destinationMode: 'existing_db',
      filePath: '/data/MultiSU.db',
      populatePlots: true,
      seedFromUserSu: true,
      activate: true,
    },
    contextService: {
      CreateWorkspaceResource: async (ctxId, req) => {
        rpcCalls.push(['create', ctxId, req]);
        return { kind: 'su', name: 'CoastalUnits', tableName: 'CoastalUnits_SU', path: '/data/MultiSU.db', rowCount: 12, activated: true, state: sampleState };
      },
    },
    notify,
  });
  assert.equal(createRes.tableName, 'CoastalUnits_SU');

  // 4. Export to VPro64
  const exportRes = await ops.runExportVPro64Op({
    contextId: 'ctx-ws-1',
    includeActiveSU: true,
    includeHierarchy: true,
    importExportService: {
      ChooseVPro64ExportFile: async () => '/exports/Sample_VPro64.db',
      ExportVPro64Database: async (ctxId, req) => {
        rpcCalls.push(['exportVPro64', ctxId, req]);
        return {
          sourceProject: 'Sample',
          targetProject: 'Sample',
          destinationPath: req.destinationPath,
          sha256: 'abc',
          bytes: 4096,
          journalMode: 'delete',
          plotCount: 42,
          includedMensuration: true,
          tables: [],
        };
      },
    },
    notify,
  });
  assert.equal(exportRes.plotCount, 42);
  assert.equal(exportRes.destinationPath, '/exports/Sample_VPro64.db');
});

test('AuthSignInModal renders locked/signed-in states, BC Gov OIDC sign-in, gated Dev Evaluation sign-in, and dispatches vpro:auth-changed', async () => {
  const modalSrc = readFileSync(srcPath('shell/AuthSignInModal.svelte'), 'utf8');
  assert.deepEqual(compile(modalSrc, { filename: 'AuthSignInModal.svelte', generate: 'client' }).warnings, []);
  assert.doesNotMatch(modalSrc, /[\u{1F300}-\u{1FAFF}]/u, 'must contain zero emojis');
  assert.doesNotMatch(modalSrc, /emerald-/, 'must use semantic BC Gov vpro-* tokens');
  assert.match(modalSrc, /Data locked — Sign in to edit/);
  assert.match(modalSrc, /Sign in with BC Gov ID \(IDIR \/ BCeID\)/);
  assert.match(modalSrc, /Dev Evaluation Sign-In/);
  assert.match(modalSrc, /vpro:auth-changed/);

  // SSR smoke test of AuthSignInModal
  const Modal = serverComponent(modalSrc, 'AuthSignInModal.svelte', {
    '@lucide/svelte': iconsProxy,
    '../../bindings/github.com/boostao/vpro/app': { ContextService: {} },
    '../shared/ModalDialogTrap.svelte': { default: () => '' },
  });
  const html = render(Modal, {
    props: {
      open: true,
      contextId: 'ctx-1',
      activeProject: 'Sample',
      plotCount: 15,
      onclose: () => {},
    },
  }).body;
  assert.match(html, /data-auth-signin-modal/);
  assert.match(html, /Sign In &amp; Access/);
  assert.match(html, /data-auth-oidc-signin/);
  assert.match(html, /Data locked — Sign in to edit/);

  // Exercise OIDC Sign-In, Dev Evaluation Sign-In, and Sign-Out actions + vpro:auth-changed dispatch
  const eventsDispatched = [];
  const activityCalls = [];
  const statusUpdates = [];
  const fakeWindow = {
    dispatchEvent(ev) {
      eventsDispatched.push(ev.type);
    },
  };
  class FakeCustomEvent {
    constructor(type) {
      this.type = type;
    }
  }
  const signedInSession = {
    signedIn: true,
    machineId: 'm-1',
    userId: 'dev-ecologist',
    displayName: 'Jane Botanist',
    email: '',
    role: 'contributor',
    rawRoles: ['contributor'],
    identityProvider: 'dev',
    issuer: '',
    signedInAt: '2026-11-26T12:00:00Z',
    verifiedAt: '2026-11-26T12:00:00Z',
    tokenExpiresAt: '',
    offlineMode: false,
    oidcConfigured: false,
    devFallbackAvailable: true,
    isDevEvaluation: true,
    canEditWorkingProjects: true,
    canEditBecMaster: false,
  };
  const unlockedLock = {
    locked: false,
    reason: '',
    signedIn: true,
    userId: 'dev-ecologist',
    displayName: 'Jane Botanist',
    role: 'contributor',
    identityProvider: 'dev',
    canEditCurrentProject: true,
    isBecMasterProject: false,
    oidcConfigured: false,
    devFallbackAvailable: true,
  };
  const signedOutSession = { ...signedInSession, signedIn: false, userId: '', displayName: '', role: '' };
  const lockedLock = { ...unlockedLock, locked: true, signedIn: false, reason: 'Sign in required' };

  const port = {
    GetAuthSession: async () => signedOutSession,
    GetEditLockStatus: async () => (ctx.session?.signedIn ? unlockedLock : lockedLock),
    BeginOIDCSignIn: async (hint) => ({
      authUrl: '',
      completed: true,
      browserOpened: true,
      session: { ...signedInSession, identityProvider: hint || 'idir', isDevEvaluation: false },
    }),
    CompleteDevEvaluationSignIn: async (uid, name, role) => ({
      ...signedInSession,
      userId: uid,
      displayName: name,
      role,
    }),
    SignOut: async () => signedOutSession,
    RecordAppActivity: async (kind, ds, count) => {
      activityCalls.push([kind, ds, count]);
      return { eventId: 'ev-1', eventKind: kind, queued: false, pendingCount: 0, recordedAt: '2026-11-26T12:00:00Z' };
    },
  };

  const ctx = componentFunctions(
    'AuthSignInModal.svelte',
    ['dispatchAuthChanged', 'formatRoleLabel', 'handleOIDCSignIn', 'handleDevSignIn', 'handleSignOut'],
    {
      window: fakeWindow,
      CustomEvent: FakeCustomEvent,
      port,
      contextId: 'ctx-1',
      activeProject: 'Sample',
      plotCount: 15,
      session: signedOutSession,
      lockStatus: lockedLock,
      working: false,
      error: '',
      notice: '',
      pendingAuthUrl: '',
      providerHint: 'idir',
      devDisplayName: 'Jane Botanist',
      devRole: 'regional_ecologist',
      onstatuschange: (payload) => statusUpdates.push(payload),
      notifications: { success() {}, info() {} },
    }
  );

  // 1. OIDC sign-in unlocks and dispatches vpro:auth-changed
  await ctx.actions.handleOIDCSignIn();
  assert.equal(ctx.session.signedIn, true);
  assert.equal(ctx.lockStatus.locked, false);
  assert.deepEqual(eventsDispatched, ['vpro:auth-changed']);
  assert.deepEqual(activityCalls, [['signin', 'Sample', 15]]);

  // 2. Dev evaluation sign-in sets selected role and dispatches vpro:auth-changed
  await ctx.actions.handleDevSignIn({ preventDefault() {} });
  assert.equal(ctx.session.role, 'regional_ecologist');
  assert.equal(ctx.session.displayName, 'Jane Botanist');
  assert.equal(eventsDispatched.length, 2);

  // 3. Sign out re-locks and dispatches vpro:auth-changed
  await ctx.actions.handleSignOut();
  assert.equal(ctx.session.signedIn, false);
  assert.equal(ctx.lockStatus.locked, true);
  assert.equal(eventsDispatched.length, 3);
  assert.equal(statusUpdates.length, 3);
});
