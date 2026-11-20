const assert = require('node:assert/strict');
const { readdirSync, readFileSync } = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const { compile } = require('svelte/compiler');
const { render } = require('svelte/server');
const {
  componentFunctions,
  loadTypeScript,
  serverComponent,
  srcPath,
} = require('./svelteTestHelpers.cjs');

const REPO_ROOT = path.resolve(__dirname, '..', '..', '..');
const SRC_DIR = path.resolve(__dirname, '..', 'src');
const iconsProxy = new Proxy({}, { get: () => () => {} });

function listFilesRecursive(dir, extFilter) {
  const results = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...listFilesRecursive(full, extFilter));
    } else if (!extFilter || extFilter(entry.name)) {
      results.push(full);
    }
  }
  return results;
}

test('Unified BC Gov tokens, offline fonts, Surface background, and zero Forest Green hexes across owned files', () => {
  const mainGo = readFileSync(path.join(REPO_ROOT, 'app', 'main.go'), 'utf8');
  assert.match(mainGo, /BackgroundColour:\s*application\.NewRGB\(242,\s*242,\s*242\)/);

  const mainTs = readFileSync(path.join(SRC_DIR, 'main.ts'), 'utf8');
  assert.doesNotMatch(mainTs, /@fontsource\//);

  const tokensCss = readFileSync(path.join(SRC_DIR, 'tokens.css'), 'utf8');
  const vproCss = readFileSync(path.join(SRC_DIR, 'vpro.css'), 'utf8');
  const css = `${tokensCss}\n${vproCss}`;
  assert.match(css, /font-family:\s*"BC Sans"/);
  assert.match(css, /url\("\/fonts\/BCSans-Regular\.woff2"\)/);
  assert.match(css, /url\("\/fonts\/BCSans-Bold\.woff2"\)/);
  assert.match(css, /url\("\/fonts\/BCSans-Italic\.woff2"\)/);
  assert.match(css, /url\("\/fonts\/BCSans-BoldItalic\.woff2"\)/);
  assert.match(css, /font-family:\s*"IBM Plex Mono"/);
  assert.match(css, /url\("\/fonts\/ibm-plex-mono-latin-400-normal\.woff2"\)/);
  assert.match(css, /url\("\/fonts\/ibm-plex-mono-latin-500-normal\.woff2"\)/);
  assert.match(css, /url\("\/fonts\/ibm-plex-mono-latin-600-normal\.woff2"\)/);
  assert.match(css, /--font-sans:\s*"BC Sans"/);
  assert.match(css, /--font-mono:\s*"IBM Plex Mono"/);

  for (const token of [
    '--vpro-navy: #003366',
    '--vpro-navy-dark: #002244',
    '--vpro-gold: #fcba19',
    '--vpro-surface: #ffffff',
    '--vpro-canvas: #f2f4f6',
    '--vpro-border: #d1d5db',
    '--vpro-ink: #313132',
    '--vpro-info: #1a5a96',
    '--vpro-success: #2e8540',
    '--vpro-error: #d8292f',
    '--vpro-forest: #1e5128',
    '--color-vpro-navy: var(--vpro-navy)',
    '--color-vpro-gold: var(--vpro-gold)',
  ]) {
    assert.ok(css.includes(token), `tokens.css/vpro.css must declare canonical BC Gov token "${token}"`);
  }

  // Responsive table & dropdown positioning fixes (1C)
  assert.doesNotMatch(css, /(?:^|\n)\s*table\s*\{[^}]*min-width:\s*630px/);
  assert.match(css, /\.table-scroll\s*>\s*table\s*\{[^}]*min-width:\s*630px/);
  assert.match(css, /\.table-scroll\s*\{[^}]*max-width:\s*100%[^}]*overflow-x:\s*auto/);
  assert.doesNotMatch(css, /top:\s*125px/);
  assert.match(css, /\.nav-menu-content[^{]*\{[^}]*max-width:\s*calc\(100vw\s*-\s*24px\)/);

  // Scan ALL owned files under shell/, help/, App.svelte, vpro.css, index.html for Forest Green / stale URLs / emojis
  const legacyHexPattern = /#(?:173f38|2c5b4a|d7ad51|f5f7f4|f7f9f7|183831|204a40|365c48|d1dcd4|b7cfc0|047857|bd9b48|0b2d26|e8eeea|20322d|e8bf64|e6f0e8|174f38|e9efeb|dbe8dd|d2e4d7|268453|456050|f0f6ee|176149)\b/i;
  const emojiPattern = /[\u{1F300}-\u{1FAFF}]/u;
  const ownedFiles = [
    path.join(REPO_ROOT, 'app', 'frontend', 'index.html'),
    path.join(SRC_DIR, 'vpro.css'),
    path.join(SRC_DIR, 'App.svelte'),
    ...listFilesRecursive(path.join(SRC_DIR, 'shell'), (n) => /\.(svelte|ts)$/.test(n)),
    ...listFilesRecursive(path.join(SRC_DIR, 'help'), (n) => /\.(svelte|ts)$/.test(n)),
  ];

  for (const file of ownedFiles) {
    const content = readFileSync(file, 'utf8');
    const rel = path.relative(REPO_ROOT, file);
    assert.doesNotMatch(content, legacyHexPattern, `${rel} contains legacy Forest Green hex`);
    assert.doesNotMatch(content, /\bemerald-\d+/, `${rel} contains legacy emerald utility class`);
    assert.doesNotMatch(content, /vpro_wails/i, `${rel} contains stale vpro_wails repository URL`);
    assert.doesNotMatch(content, emojiPattern, `${rel} contains emoji character`);
  }
});

test('Unified VPro Shield+Conifer SVG crest replaces placeholder V badge in App.svelte and index.html', () => {
  const indexHtml = readFileSync(path.join(REPO_ROOT, 'app', 'frontend', 'index.html'), 'utf8');
  assert.match(indexHtml, /<link\s+rel="icon"\s+type="image\/svg\+xml"\s+href="data:image\/svg\+xml,/);
  assert.match(indexHtml, /<link\s+rel="icon"\s+href="\/favicon\.ico"\s*\/>/);
  assert.doesNotMatch(indexHtml, /M8\.5 7h4\.2/);
  assert.match(indexHtml, /%231E5128/);
  assert.match(indexHtml, /%23FCBA19/);

  const { readShellComposite } = require('./svelteTestHelpers.cjs');
  const appSrc = readShellComposite();
  assert.doesNotMatch(appSrc, /<span class="brand-symbol"[^>]*>V<\/span>/);
  assert.match(appSrc, /<span class="brand-symbol" aria-hidden="true">\s*<svg\b[^>]*viewBox="36 36 952 952"/);
  assert.match(appSrc, /#FCBA19/);
  assert.match(appSrc, /#1E5128/);
});

test('docs-src/tours.json and compiled app/resources/help_bundle.json contain exact Wave 3 tour selectors', () => {
  const toursSrc = JSON.parse(readFileSync(path.join(REPO_ROOT, 'docs-src', 'tours.json'), 'utf8'));
  const helpBundle = JSON.parse(readFileSync(path.join(REPO_ROOT, 'app', 'resources', 'help_bundle.json'), 'utf8'));
  assert.deepEqual(helpBundle.tours, toursSrc);

  const expectedTargets = {
    'tour-session-import': [
      { view: 'home', target: '#project-context' },
      { view: 'project-admin', target: '[data-tour="project-admin-root"]' },
      { view: 'interchange-hub', target: '[data-tour="interchange-hub-root"]' },
    ],
    'tour-card-datasheet': [
      { view: 'fs882', target: '[data-tour="fs882-form-root"]' },
      { view: 'datasheet', target: '[data-tour="datasheet-grid-root"]' },
    ],
    'tour-classification-profiling': [
      { view: 'classification-explorer', target: '[data-tour="classification-explorer-root"]' },
      { view: 'lump-editor', target: '[data-tour="lump-editor-root"]' },
    ],
    'tour-map-diagnostics-reports': [
      { view: 'geospatial-map', target: '[data-tour="geospatial-workbench-root"]' },
      { view: 'diagnostic-synthesis', target: '[data-tour="diagnostic-synthesis-root"]' },
      { view: 'r-sidecar', target: '[data-tour="r-sidecar-root"]' },
    ],
  };

  assert.equal(toursSrc.length, 4);
  for (const tour of toursSrc) {
    assert.deepEqual(
      tour.steps.map((s) => ({ view: s.view, target: s.target })),
      expectedTargets[tour.id],
      `Tour ${tour.id} step targets mismatch`
    );
    for (const step of tour.steps) {
      assert.notEqual(step.target, 'main');
      assert.doesNotMatch(step.target, /data-nav-group/);
    }
  }
});

test('OnboardingTour waits for lazy targets, expands #project-context & ancestor details, scrolls into view, and tracks without mobile overflow', async () => {
  const tourSrc = readFileSync(srcPath('help/OnboardingTour.svelte'), 'utf8');
  assert.deepEqual(compile(tourSrc, { filename: 'OnboardingTour.svelte', generate: 'client' }).warnings, []);

  const mockTours = JSON.parse(readFileSync(path.join(REPO_ROOT, 'docs-src', 'tours.json'), 'utf8'));
  const helpModule = loadTypeScript('help/helpSystem.ts', {
    '../../bindings/github.com/boostao/vpro/app': {},
  });

  // 1. SSR renders cleanly when open
  const TourSSR = serverComponent(tourSrc, 'OnboardingTour.svelte', {
    '@lucide/svelte': iconsProxy,
    './helpSystem': helpModule,
  });
  const catalogHtml = render(TourSSR, {
    props: {
      open: true,
      activeProject: 'Sample',
      helpPort: { getHelpBundle: async () => ({ tours: mockTours }) },
      onnavigateview: () => {},
      onclose: () => {},
    },
  }).body;
  assert.match(catalogHtml, /data-onboarding-tour-catalog/);

  const activeHtml = render(TourSSR, {
    props: {
      open: true,
      initialTourId: 'tour-session-import',
      initialTours: mockTours,
      activeProject: 'Sample',
      helpPort: { getHelpBundle: async () => ({ tours: mockTours }) },
      onnavigateview: () => {},
      onclose: () => {},
    },
  }).body;
  assert.match(activeHtml, /data-onboarding-tour-active="tour-session-import"/);
  assert.match(activeHtml, /data-tour-placement="bottom-right"/);
  assert.match(activeHtml, /max-sm:inset-x-3/);

  // 2. Unit-test DOM observation & ancestor details/context expansion helpers via componentFunctions
  assert.match(tourSrc, /data-tour-overlay/);
  const outerDetails = { tagName: 'DETAILS', open: false, parentElement: null };
  const innerDetails = { tagName: 'DETAILS', open: false, parentElement: outerDetails };
  const scrolledCalls = [];
  const contextOpened = [];
  const observedTargets = [];
  let mutationDisconnectCalls = 0;
  const targetElement = {
    tagName: 'DIV',
    parentElement: innerDetails,
    closest(selector) {
      return selector === '#project-context' ? { id: 'project-context' } : null;
    },
    scrollIntoView(opts) {
      scrolledCalls.push(opts);
    },
    getBoundingClientRect() {
      return { top: 120, left: 40, right: 340, bottom: 280, width: 300, height: 160 };
    },
  };

  let queryReady = false;
  let capturedMutationCb = null;
  let listenerCount = 0;

  const mockDocument = {
    body: {},
    querySelector(sel) {
      return sel === '[data-tour="project-admin-root"]' && queryReady ? targetElement : null;
    },
  };
  const mockWindow = {
    innerWidth: 390,
    innerHeight: 844,
    addEventListener() { listenerCount++; },
    removeEventListener() { listenerCount = Math.max(0, listenerCount - 1); },
  };
  class MockMutationObserver {
    constructor(cb) { capturedMutationCb = cb; }
    observe() {}
    disconnect() { mutationDisconnectCalls++; }
  }
  class MockResizeObserver {
    observe(el) { observedTargets.push(el); }
    disconnect() {}
  }

  const ctx = componentFunctions(
    'help/OnboardingTour.svelte',
    ['openAncestorDetails', 'rectsAlmostEqual', 'isSelfTourMutation', 'disconnectMutationObserver', 'measureResolvedElement', 'beginTargetObservation', 'stopTargetTracking', 'boxesOverlap'],
    {
      document: mockDocument,
      window: mockWindow,
      MutationObserver: MockMutationObserver,
      ResizeObserver: MockResizeObserver,
      setTimeout,
      clearTimeout,
      requestAnimationFrame: () => 0,
      cancelAnimationFrame: () => {},
      open: true,
      targetRect: null,
      targetWaiting: false,
      viewportWidth: 390,
      viewportHeight: 844,
      observedEl: null,
      mutationObserver: null,
      resizeObserver: null,
      retryTimer: null,
      rafId: 0,
      trackingActive: false,
      trackGen: 1,
      onensurecontextopen: () => contextOpened.push(true),
      handleViewportMutation: () => {},
    },
    {
      imports: {
        './helpSystem': helpModule,
      },
    }
  );

  ctx.actions.beginTargetObservation('[data-tour="project-admin-root"]', 1);
  assert.equal(ctx.targetRect, null);
  assert.equal(ctx.targetWaiting, true);
  assert.ok(capturedMutationCb, 'MutationObserver must subscribe to lazy mount changes');

  // Self-mutations from OnboardingTour overlay must be ignored without resolving or looping
  const selfNode = {
    nodeType: 1,
    closest(sel) { return sel.includes('data-tour-spotlight-ring') ? {} : null; },
  };
  assert.equal(ctx.actions.isSelfTourMutation([{ target: selfNode }]), true);

  // Simulate async lazy view finish mounting
  queryReady = true;
  capturedMutationCb([{ target: { nodeType: 1, closest: () => null } }]);

  assert.equal(outerDetails.open, true);
  assert.equal(innerDetails.open, true);
  assert.equal(contextOpened.length, 1);
  assert.deepEqual({ ...scrolledCalls[0] }, { behavior: 'smooth', block: 'nearest', inline: 'nearest' });
  assert.equal(observedTargets[0], targetElement);
  assert.equal(ctx.targetWaiting, false);
  assert.ok(ctx.targetRect && ctx.targetRect.width > 0);
  assert.ok(mutationDisconnectCalls >= 1, 'MutationObserver must disconnect once lazy target resolves');
  const prevRectRef = ctx.targetRect;
  ctx.actions.measureResolvedElement('[data-tour="project-admin-root"]', false);
  assert.equal(ctx.targetRect, prevRectRef, 'Unchanged bounding box must not churn targetRect state');
  assert.ok(ctx.targetRect.left >= 4 && ctx.targetRect.left + ctx.targetRect.width <= 386);
  assert.equal(ctx.actions.boxesOverlap(ctx.targetRect, { top: 200, left: 200, width: 100, height: 100 }), true);
  assert.equal(ctx.actions.boxesOverlap(ctx.targetRect, { top: 600, left: 200, width: 100, height: 100 }), false);

  ctx.actions.stopTargetTracking();
  assert.equal(listenerCount, 0);
});

test('UserSetupModal (S6.12), Navigation graduation, PlotsBrowserPanel (S1.1/S3.9), WorkspaceSidebar quarantine, and App wiring', async () => {
  // 1. userSetupModal.ts validation + RPC port routing
  const rpcLog = [];
  const sampleStatus = {
    userName: 'jdoe',
    accredited: true,
    masterBecAllowed: false,
    inUserRestrictions: false,
    canEditBecSiteUnit: true,
  };
  const userSetup = loadTypeScript('shell/userSetupModal.ts', {
    '../../bindings/github.com/boostao/vpro/app': {
      ContextService: {
        GetUserSetup: async (ctx) => { rpcLog.push(['ContextService.GetUserSetup', ctx]); return sampleStatus; },
        SetUserName: async (ctx, u) => { rpcLog.push(['ContextService.SetUserName', ctx, u]); return { ...sampleStatus, userName: u }; },
      },
      PlotEntryService: {
        UserAccreditationStatus: async () => { rpcLog.push(['PlotEntryService.UserAccreditationStatus']); return sampleStatus; },
        SetCurrentUser: async (u) => { rpcLog.push(['PlotEntryService.SetCurrentUser', u]); },
      },
    },
  });

  assert.equal(userSetup.validateUserSetupName('   ').valid, false);
  assert.equal(userSetup.validateUserSetupName('a\0b').valid, false);
  assert.deepEqual(
    { ...userSetup.validateUserSetupName('  mof-user  ') },
    { valid: true, value: 'mof-user', error: '' }
  );

  await userSetup.defaultUserSetupPort.getUserSetup('ctx-1');
  await userSetup.defaultUserSetupPort.setUserName('ctx-1', 'mof-user');
  await userSetup.defaultUserSetupPort.getUserSetup('');
  await userSetup.defaultUserSetupPort.setUserName('', 'mof-fallback');

  assert.deepEqual(rpcLog, [
    ['ContextService.GetUserSetup', 'ctx-1'],
    ['ContextService.SetUserName', 'ctx-1', 'mof-user'],
    ['PlotEntryService.UserAccreditationStatus'],
    ['PlotEntryService.SetCurrentUser', 'mof-fallback'],
    ['PlotEntryService.UserAccreditationStatus'],
  ]);

  // 2. UserSetupModal.svelte compiles cleanly & renders under SSR
  const modalSrc = readFileSync(srcPath('shell/UserSetupModal.svelte'), 'utf8');
  assert.deepEqual(compile(modalSrc, { filename: 'UserSetupModal.svelte', generate: 'client' }).warnings, []);
  const ModalSSR = serverComponent(modalSrc, 'UserSetupModal.svelte', {
    '@lucide/svelte': iconsProxy,
    './userSetupModal': userSetup,
  });
  const modalHtml = render(ModalSSR, {
    props: { open: true, contextId: 'ctx-1', activeProject: 'Sample', onclose: () => {} },
  }).body;
  assert.match(modalHtml, /data-user-setup-modal/);
  assert.match(modalHtml, /VPro User Setup/);
  assert.match(modalHtml, /data-user-setup-save/);

  // 3. Navigation.svelte compiles cleanly, graduates User setup in stable+experimental, exposes Two-Page & S5.11 label
  const navSrc = readFileSync(srcPath('shell/Navigation.svelte'), 'utf8');
  assert.deepEqual(compile(navSrc, { filename: 'Navigation.svelte', generate: 'client' }).warnings, []);
  assert.doesNotMatch(navSrc, /User setup \(Phase 2 Deferred\)/);
  assert.match(navSrc, /Lifeform & Species Attribute Summaries/);

  const NavSSR = serverComponent(navSrc, 'Navigation.svelte', { '@lucide/svelte': iconsProxy });
  for (const channel of ['stable', 'experimental']) {
    const html = render(NavSSR, {
      props: { view: 'home', releaseChannel: channel, onnavigate: () => {} },
    }).body;
    const setupMatch = html.match(/<button\b([^>]*)>[\s\S]*?<span>User setup<\/span>\s*<\/button>/);
    assert.ok(setupMatch, `Navigation (${channel}) must expose active User setup menu item`);
    assert.equal(/\bdisabled(?:\s|=|$)/.test(setupMatch[1]), false, `User setup must be enabled in ${channel}`);

    const twoPageMatch = html.match(/<button\b([^>]*)>[\s\S]*?<span>Two-Page Entry \(FS882-8x6XL\)<\/span>\s*<\/button>/);
    assert.ok(twoPageMatch, `Navigation (${channel}) must expose Two-Page Entry (FS882-8x6XL)`);
    assert.equal(/\bdisabled(?:\s|=|$)/.test(twoPageMatch[1]), false);
  }

  let setupClicked = 0;
  let navigatedView = '';
  const navCtx = componentFunctions('shell/Navigation.svelte', ['itemEnabled', 'activate', 'closeMenu', 'navigate'], {
    openMenu: 'Forms',
    navigation: { querySelector: () => ({ querySelector: () => ({ focus: () => {} }) }) },
    onopenusersetup: () => { setupClicked++; },
    onnavigate: (v) => { navigatedView = v; },
  });
  navCtx.actions.activate({ action: 'user-setup' });
  assert.equal(setupClicked, 1);
  navCtx.actions.activate({ view: 'fs882-twopage' });
  assert.equal(navigatedView, 'fs882-twopage');

  // 4. PlotsBrowserPanel.svelte S1.1 + S3.9 controls
  const browserSrc = readFileSync(srcPath('shell/PlotsBrowserPanel.svelte'), 'utf8');
  assert.deepEqual(compile(browserSrc, { filename: 'PlotsBrowserPanel.svelte', generate: 'client' }).warnings, []);
  const BrowserSSR = serverComponent(browserSrc, 'PlotsBrowserPanel.svelte', {
    '@lucide/svelte': iconsProxy,
    '../shared/state': { projectState: { subscribe: (fn) => { fn({ activeProject: 'Sample', hierarchyFile: 'Sample', activeHierarchy: 'Sample' }); return () => {}; } } },
  });
  const detailHtml = render(BrowserSSR, {
    props: {
      region: 'detail',
      view: 'plots',
      selected: { plotNumber: '00337', fieldNumber: 'F1', plotRepresenting: '', zone: 'CWH', subZone: 'xm', siteSeries: '01' },
    },
  }).body;
  assert.match(detailHtml, /data-twopage-open/);
  assert.match(detailHtml, /Open Two-Page \(FS882-8x6XL\)/);

  const hierHtml = render(BrowserSSR, {
    props: { region: 'main', view: 'hierarchy', hierarchyNodes: [] },
  }).body;
  assert.match(hierHtml, /data-open-classification-explorer/);
  assert.match(hierHtml, /Open SU &amp; Hierarchy Explorer/);

  // 5. WorkspaceSidebar.svelte quarantine alert details
  const { readSidebarComposite, readShellComposite } = require('./svelteTestHelpers.cjs');
  const sidebarSrc = readFileSync(srcPath('shell/WorkspaceSidebar.svelte'), 'utf8');
  const sidebarComposite = readSidebarComposite();
  assert.deepEqual(compile(sidebarSrc, { filename: 'WorkspaceSidebar.svelte', generate: 'client' }).warnings, []);
  const sidebarHtml = render(
    serverComponent(sidebarSrc, 'WorkspaceSidebar.svelte', {
      '@lucide/svelte': iconsProxy,
      './notificationService.svelte': loadTypeScript('shell/notificationService.svelte.ts', {
        'svelte/store': require('svelte/store'),
      }),
      '../shared/state': {
        projectState: {
          subscribe: (fn) => {
            fn({ contextId: 'ctx-1', activeProject: 'Sample', projectPath: '/tmp/Sample.db', projects: [], sus: [], hierarchies: [] });
            return () => {};
          },
        },
      },
      '../../bindings/github.com/boostao/vpro/app': {
        ContextService: {},
        FilePickerService: {},
        InterchangeService: {},
      },
    }),
    {
      props: {
        accessResult: {
          targetProject: 'LegacyProj',
          plotCount: 14,
          conversionMode: 'VP07->VP08',
          destinationPath: '/tmp/LegacyProj.db',
          quarantinedMalformedRows: 3,
          quarantinedOrphanRows: 2,
          quarantinedOverflowRows: 1,
        },
      },
    }
  );
  assert.match(sidebarComposite, /data-access-quarantine-summary/);
  assert.match(sidebarComposite, /quarantinedMalformedRows/);
  assert.match(sidebarComposite, /quarantinedOrphanRows/);
  assert.match(sidebarComposite, /quarantinedOverflowRows/);
  assert.ok(sidebarHtml.body.includes('PROJECTS'));

  // 6. App.svelte compiles cleanly with 0 warnings and integrates S1.1, S1.10, S4.3, S5.9, S6.12
  const rawAppSrc = readFileSync(srcPath('App.svelte'), 'utf8');
  const appSrc = readShellComposite();
  assert.deepEqual(compile(rawAppSrc, { filename: 'App.svelte', generate: 'client' }).warnings, []);
  assert.match(appSrc, /'fs882-twopage'/);
  assert.match(appSrc, /onOpenPictureManager=/);
  assert.match(appSrc, /onDiagnosticsContextChange=/);
  assert.match(appSrc, /onApplyHumusThickness=\{/);
  assert.match(appSrc, /onApplyKeyedSMR=\{/);
  assert.match(appSrc, /onApplyKeyedSNR=\{/);
  assert.doesNotMatch(appSrc, /<SiteUnitExclusionFilter/);
  assert.doesNotMatch(appSrc, /vpro:site-unit-exclusion-update/);
  assert.match(
    appSrc,
    /<SummaryVegetationReport[\s\S]*hierarchy=\{\$projectState\.activeHierarchy \?\? 'None'\}[\s\S]*onExclusionBusyChange=\{\(value\)\s*=>\s*\{\s*secondaryPanelBusy = value;\s*\}\}/
  );
  assert.match(
    appSrc,
    /<LongVegetationReport[\s\S]*hierarchy=\{\$projectState\.activeHierarchy \?\? 'None'\}/
  );
  assert.match(appSrc, /import\('\.\.?\/shell\/UserSetupModal\.svelte'\)|import\('\.\/UserSetupModal\.svelte'\)/);
});
