const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
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

const MODIFIED_REPORT_FILES = [
  'reports/LongVegetationReport.svelte',
  'reports/SummaryVegetationReport.svelte',
  'reports/SiteUnitSummary.svelte',
  'reports/LongEnvironmentReport.svelte',
  'reports/LifeformSummary.svelte',
  'reports/SubzoneMatrixReport.svelte',
  'reports/SiteUnitSummaryWorkbookPanel.svelte',
  'reports/SummaryVegetationWorkbookPanel.svelte',
  'reports/LifeformWorkbookPanel.svelte',
];

const STICKY_HOSTS = [
  {
    file: 'reports/LongVegetationReport.svelte',
    heading: 'Long Vegetation',
    actionPattern: /data-source-control="btnViewReport"/,
    renderComponent() {
      class PubStub {
        view() { return { busy: false, blocked: false, error: '', outcome: null, requestedDestination: '' }; }
        subscribe(fn) { fn(); return () => {}; }
      }
      return serverComponent(readFileSync(srcPath('reports/LongVegetationReport.svelte'), 'utf8'), 'LongVegetationReport.svelte', {
        '../bindings/github.com/boostao/vpro/app': {},
        './longVegetationProjectWorkspaces': { projectReportWorkspace: () => null },
        './longVegetationSelectedUnitSelection': {}, './LongVegetationSelectedUnitSelection.svelte': { default() {} },
        '../shared/state': { projectState: { subscribe(fn) { fn({ activeHierarchy: 'HierA' }); return () => {}; } } },
        '../classification/SiteUnitExclusionFilter.svelte': { default() {} },
        '../classification/siteUnitExclusionFilter': { createDefaultBreakpointOptions: () => ({}) },
        './longVegetationGroupPreferences': {}, './LongVegetationGroupPreferences.svelte': { default() {} },
        './longVegetationNamingPreferences': {}, './LongVegetationNamingPreferences.svelte': { default() {} },
        './longVegetationSelectedFieldPreferences': {}, './LongVegetationSelectedFieldPreferences.svelte': { default() {} },
        './longVegetationEnforcementPreferences': {}, './LongVegetationEnforcementPreferences.svelte': { default() {} },
        './longVegetationQualityNullPreferences': {}, './LongVegetationQualityNullPreferences.svelte': { default() {} },
        './longVegetationQualityMinimumPreferences': {}, './LongVegetationQualityMinimumPreferences.svelte': { default() {} },
        './longVegetationUnitPreferences': {}, './LongVegetationUnitPreferences.svelte': { default() {} },
        './longVegetationPreferences': {}, './longVegetationStatisticsPreferences': {},
        './longVegetationSwitchPreferences': {}, './LongVegetationSwitchPreferences.svelte': { default() {} },
        './longVegetationThresholdPreferences': {}, './LongVegetationThresholdPreferences.svelte': { default() {} },
        './longVegetationReport': {},
        './longEnvironmentReport': { reportCellText: () => '' },
        './vegetationWorkbook': { VegetationWorkbookPublicationSession: PubStub, vegetationWorkbookPublicationSession: () => new PubStub() },
      });
    },
    props: { contextId: 'ctx-lv', project: 'Sample', projectPath: '/tmp/Sample.db', su: 'Working', suPath: '/tmp/Sample.db', onBusyChange() {} },
  },
  {
    file: 'reports/SummaryVegetationReport.svelte',
    heading: 'Summary Vegetation',
    actionPattern: /data-summary-preview/,
    renderComponent() {
      const lifeform = loadTypeScript('lifeformSummary.ts');
      const summary = loadTypeScript('summaryVegetation.ts', { './lifeformSummary': lifeform }, { setTimeout });
      return serverComponent(readFileSync(srcPath('reports/SummaryVegetationReport.svelte'), 'utf8'), 'SummaryVegetationReport.svelte', {
        './summaryVegetation': summary,
        '../bindings/github.com/boostao/vpro/app': {},
        '../shared/state': { projectState: { subscribe(fn) { fn(null); return () => {}; } } },
        '../classification/SiteUnitExclusionFilter.svelte': { default() {} },
        '../classification/siteUnitExclusionFilter': {},
      });
    },
    props: { contextId: 'ctx-sv', project: 'Sample', projectPath: '/tmp/Sample.db', su: 'Working', suPath: '/tmp/Sample.db', onBusyChange() {} },
  },
  {
    file: 'reports/SiteUnitSummary.svelte',
    heading: 'Summary Environment',
    actionPattern: /data-source-control="btnCreateReport"/,
    renderComponent() {
      return serverComponent(readFileSync(srcPath('reports/SiteUnitSummary.svelte'), 'utf8'), 'SiteUnitSummary.svelte', {
        '../bindings/github.com/boostao/vpro/app': {},
        './siteUnitSummary': {},
        './longEnvironmentReport': { reportCellText: () => '' },
        './siteUnitSummaryPreferences': {
          siteUnitSummaryPreferencesSession: () => ({ view: () => ({ draft: null, busy: false, blocked: false, authorityUnknown: false, draftError: '', error: '', receipts: [] }), subscribe(fn) { fn(); return () => {}; }, cancelLoad() {} }),
          siteUnitSummaryFullPreferencesSession: null,
        },
        './SiteUnitSummaryWorkbookPanel.svelte': { default() {} },
        './siteUnitSummarySpecies': { summarySpeciesCriteria: () => ({ view: () => ({ enabled: false, error: '' }), subscribe(fn) { fn(); return () => {}; } }) },
        './siteUnitSummaryExtendedWorkbook': { extendedSummaryWorkbookPublicationSession: () => ({ view: () => ({ busy: false, blocked: false }), requestedOptions: () => null }) },
      });
    },
    props: { contextId: 'ctx-su', project: 'Sample', projectPath: '/tmp/Sample.db', su: 'Working', suPath: '/tmp/Sample.db', onBusyChange() {} },
  },
  {
    file: 'reports/LongEnvironmentReport.svelte',
    heading: 'Long Environment',
    actionPattern: /data-source-control="btnViewReport"/,
    renderComponent() {
      return serverComponent(readFileSync(srcPath('reports/LongEnvironmentReport.svelte'), 'utf8'), 'LongEnvironmentReport.svelte', {
        '../bindings/github.com/boostao/vpro/app': {},
        './longEnvironmentReport': { reportTitleError: () => null, reportCellText: () => '' },
        './longEnvironmentPreferences': {
          longEnvironmentPreferencesSession: () => ({
            view: () => ({ draft: { title: '' }, initialized: true, busy: false, blocked: false, authorityUnknown: false, draftError: '', error: '', receipts: [], saved: true }),
            subscribe(fn) { fn(); return () => {}; },
            cancelLoad() {},
          }),
        },
        './environmentWorkbook': {
          environmentWorkbookPublicationSession: () => ({
            view: () => ({ busy: false, blocked: false, outcome: null, error: '', requestedDestination: '' }),
            subscribe(fn) { fn(); return () => {}; },
          }),
        },
      });
    },
    props: { contextId: 'ctx-le', project: 'Sample', projectPath: '/tmp/Sample.db', su: 'Working', suPath: '/tmp/Sample.db', onBusyChange() {} },
  },
  {
    file: 'reports/LifeformSummary.svelte',
    heading: 'Lifeform Summary',
    actionPattern: /Preview Lifeform Summary/,
    renderComponent() {
      const lifeform = loadTypeScript('lifeformSummary.ts');
      return serverComponent(readFileSync(srcPath('reports/LifeformSummary.svelte'), 'utf8'), 'LifeformSummary.svelte', {
        '../bindings/github.com/boostao/vpro/app': {},
        './lifeformSummary': lifeform,
        './speciesAttributeSummary': loadTypeScript('speciesAttributeSummary.ts', { './lifeformSummary': lifeform }),
        './LifeformWorkbookPanel.svelte': { default() {} },
      });
    },
    props: { contextId: 'ctx-lf', project: 'Sample', projectPath: '/tmp/Sample.db', su: 'Working', suPath: '/tmp/Sample.db', onBusyChange() {} },
  },
  {
    file: 'reports/SubzoneMatrixReport.svelte',
    heading: 'Subzone Matrix of Units',
    actionPattern: /data-matrix-read/,
    renderComponent() {
      return serverComponent(readFileSync(srcPath('reports/SubzoneMatrixReport.svelte'), 'utf8'), 'SubzoneMatrixReport.svelte', {
        '../bindings/github.com/boostao/vpro/app': {},
        './subzoneMatrixReport': {
          matrixPublicationSession: () => ({
            view: () => ({ busy: false, blocked: false, outcome: null, error: '', requestedDestination: '' }),
            subscribe(fn) { fn(); return () => {}; },
          }),
          matrixCellText: (v) => String(v ?? ''),
        },
      });
    },
    props: { contextId: 'ctx-sm', hierarchy: 'SampleHier', hierarchyPath: '/tmp/Hier.db', onBusyChange() {} },
  },
];

function makeController() {
  const { createNotificationController } = loadTypeScript('shell/notificationService.svelte.ts', {
    'svelte/store': require('svelte/store'),
  });
  return createNotificationController({ schedule: () => 0, cancelSchedule: () => {} });
}

test('all modified report and workbook files compile with 0 warnings, zero emojis, zero palette classes, and notification imports', () => {
  const emojiRe = /\p{Extended_Pictographic}/u;
  const tailwindPaletteRegex = /\b(?:bg|text|border)-(?:indigo|emerald|amber|slate|teal|sky|rose|green|blue|gray|zinc|stone|red|yellow)-\d+\b/;

  for (const rel of MODIFIED_REPORT_FILES) {
    const file = srcPath(rel);
    const src = readFileSync(file, 'utf8');
    for (const target of ['client', 'server']) {
      const compiled = compile(src, { filename: file, generate: target });
      assert.deepEqual(compiled.warnings, [], `${rel} (${target}) emitted Svelte compiler warnings`);
    }
    assert.equal(emojiRe.test(src), false, `${rel} must contain zero emojis`);
    assert.equal(tailwindPaletteRegex.test(src), false, `${rel} must not use forbidden Tailwind palette classes`);
    assert.match(
      src,
      /import\s*\{\s*notifications\s*\}\s*from\s*'\.\.\/shell\/notificationService\.svelte'/,
      `${rel} must import notifications from ../shell/notificationService.svelte`,
    );
  }
});

test('all 6 report hosts render sticky command bar with heading and primary actions in SSR HTML', () => {
  for (const host of STICKY_HOSTS) {
    const comp = host.renderComponent();
    const html = render(comp, { props: host.props }).body;
    const match = html.match(/<header\b([^>]*\bdata-report-sticky-bar\b[^>]*)>([\s\S]*?)<\/header>/);
    assert.ok(match, `${host.file} must render <header data-report-sticky-bar>`);
    const attrs = match[1];
    const inner = match[2];
    for (const cls of ['sticky', 'top-0', 'z-20', 'bg-white/95', 'backdrop-blur-xs', 'py-2', 'border-b']) {
      assert.ok(attrs.includes(cls), `${host.file} sticky header missing class "${cls}"`);
    }
    assert.ok(
      attrs.includes('border-vpro-border') || attrs.includes('border-[#D8D8D8]'),
      `${host.file} sticky header missing border-vpro-border token class`,
    );
    assert.match(inner, new RegExp(`<h1[^>]*>${host.heading}<\\/h1>`), `${host.file} sticky header must contain <h1>${host.heading}</h1>`);
    assert.match(inner, host.actionPattern, `${host.file} sticky header must contain primary action control`);
  }
});

test('workbook panels route success and failure notifications with category: reports and contextTag', async () => {
  // 1. SiteUnitSummaryWorkbookPanel.svelte
  {
    const notifications = makeController();
    const dest = 'C:\\out\\su-summary.xlsx';
    let pubStatus = 'published';
    const session = {
      view: () => ({
        busy: false,
        blocked: true,
        requestedDestination: dest,
        outcome: pubStatus === 'published'
          ? { status: 'published', path: dest, sha256: 'a'.repeat(64), errorMessage: '' }
          : { status: 'not-published', path: '', sha256: '', errorMessage: 'Destination already exists' },
        error: pubStatus === 'published' ? '' : 'Destination already exists',
      }),
      publish: async () => {},
    };
    const ctx = componentFunctions('SiteUnitSummaryWorkbookPanel.svelte', ['getReview', 'publish'], {
      enabled: true, held: false, normalOwner: true, validMethod: true, method: 1, extended: false,
      extendedOptions: null, allowConfiguredScope: false,
      owned: { contextId: 'ctx-1', project: 'Sample', projectPath: 'C:\\p.db', su: 'Working', suPath: 'C:\\p.db' },
      generation: 0, disposed: false, busy: false, error: '',
      review: { preview: { report: { method: 1 } } }, currentReview: true, destination: dest,
      session, originalSession: session, extendedSession: null,
      reportBusy() {}, cancel() {},
      reads: { track: (p) => p, cancelAll() {} },
      EnvironmentReportService: {
        GetSiteUnitSummaryWorkbookReview: () => Promise.reject(new Error('SU review failed')),
        ExportReviewedSiteUnitSummaryWorkbook: async () => null,
      },
      notifications,
    });
    await ctx.actions.publish();
    pubStatus = 'not-published';
    await ctx.actions.publish();
    await ctx.actions.getReview();

    const entries = notifications.getSnapshot().entries;
    assert.equal(entries.length, 3);
    assert.equal(entries[0].severity, 'error');
    assert.equal(entries[0].category, 'reports');
    assert.equal(entries[0].source, 'Summary Environment');
    assert.equal(entries[1].severity, 'error');
    assert.equal(entries[1].category, 'reports');
    assert.equal(entries[2].severity, 'success');
    assert.equal(entries[2].category, 'reports');
    assert.equal(entries[2].source, 'Summary Environment');
    assert.equal(entries[2].contextTag, 'Sample');
    assert.match(entries[2].message, /su-summary\.xlsx/);
  }

  // 2. SummaryVegetationWorkbookPanel.svelte
  {
    const notifications = makeController();
    const dest = 'C:\\out\\sum-veg.xlsx';
    let pubStatus = 'published';
    const session = {
      view: () => ({
        destination: dest,
        error: 'Summary workbook review rejected',
        publication: {
          busy: false,
          blocked: true,
          requestedDestination: dest,
          outcome: pubStatus === 'published'
            ? { status: 'published', path: dest, sha256: 'b'.repeat(64), errorMessage: '' }
            : { status: 'not-published', path: '', sha256: '', errorMessage: 'Write collision' },
          error: pubStatus === 'published' ? '' : 'Write collision',
        },
      }),
      review: async () => false,
      publish: async () => {},
    };
    const ctx = componentFunctions('SummaryVegetationWorkbookPanel.svelte', ['review', 'publish'], {
      enabled: true, held: false, modeUnavailable: false, currentReview: true,
      owned: { contextId: 'ctx-2', project: 'Sample', projectPath: 'C:\\p.db', su: 'Working', suPath: 'C:\\p.db' },
      calculation: { average: 1, display: 1, showClass: 1 },
      viewState: { draftError: '', destination: dest },
      unitPage: 0, referencePage: 0, error: '',
      session,
      VegetationReportService: {
        GetSummaryVegetationWorkbookReview: async () => null,
        ExportReviewedSummaryVegetationWorkbook: async () => null,
      },
      notifications,
    });
    await ctx.actions.publish();
    pubStatus = 'not-published';
    await ctx.actions.publish();
    await ctx.actions.review();

    const entries = notifications.getSnapshot().entries;
    assert.equal(entries.length, 3);
    assert.equal(entries[0].severity, 'error');
    assert.equal(entries[0].category, 'reports');
    assert.equal(entries[0].source, 'Summary Vegetation');
    assert.equal(entries[1].severity, 'error');
    assert.equal(entries[2].severity, 'success');
    assert.equal(entries[2].category, 'reports');
    assert.equal(entries[2].source, 'Summary Vegetation');
    assert.equal(entries[2].contextTag, 'Sample');
    assert.match(entries[2].message, /sum-veg\.xlsx/);
  }

  // 3. LifeformWorkbookPanel.svelte
  {
    const notifications = makeController();
    const dest = 'C:\\out\\lifeform.xlsx';
    let pubStatus = 'published';
    const session = {
      view: () => ({
        busy: false,
        blocked: true,
        requestedDestination: dest,
        outcome: pubStatus === 'published'
          ? { status: 'published', path: dest, sha256: 'c'.repeat(64), errorMessage: '' }
          : { status: 'not-published', path: '', sha256: '', errorMessage: 'File exists' },
        error: pubStatus === 'published' ? '' : 'File exists',
      }),
      publish: async () => {},
    };
    const ctx = componentFunctions('LifeformWorkbookPanel.svelte', ['getReview', 'publish'], {
      enabled: true, held: false,
      owned: { contextId: 'ctx-3', project: 'Sample', projectPath: 'C:\\p.db', su: 'Working', suPath: 'C:\\p.db' },
      generation: 0, disposed: false, busy: false, error: '', details: [false, false, false, false, false, false],
      review: { bytes: 10 }, destination: dest,
      session, reportBusy() {}, cancel() {},
      reads: { track: (p) => p, cancelAll() {} },
      VegetationReportService: {
        GetLifeformWorkbookReview: () => Promise.reject(new Error('Lifeform review failed')),
        ExportReviewedLifeformWorkbook: async () => null,
      },
      notifications,
    });
    await ctx.actions.publish();
    pubStatus = 'not-published';
    await ctx.actions.publish();
    await ctx.actions.getReview();

    const entries = notifications.getSnapshot().entries;
    assert.equal(entries.length, 3);
    assert.equal(entries[0].severity, 'error');
    assert.equal(entries[0].category, 'reports');
    assert.equal(entries[0].source, 'Lifeform Summary');
    assert.equal(entries[1].severity, 'error');
    assert.equal(entries[2].severity, 'success');
    assert.equal(entries[2].category, 'reports');
    assert.equal(entries[2].source, 'Lifeform Summary');
    assert.equal(entries[2].contextTag, 'Sample');
    assert.match(entries[2].message, /lifeform\.xlsx/);
  }
});

test('report hosts route success and failure notifications with category: reports and contextTag', async () => {
  // 1. LongVegetationReport.svelte
  {
    const notifications = makeController();
    const dest = 'C:\\out\\long-veg.xlsx';
    let pubStatus = 'published';
    const workbookSession = {
      view: () => ({
        busy: false,
        blocked: true,
        requestedDestination: dest,
        outcome: pubStatus === 'published'
          ? { status: 'published', path: dest, sha256: 'd'.repeat(64), errorMessage: '' }
          : { status: 'not-published', path: '', sha256: '', errorMessage: 'Collision' },
        error: pubStatus === 'published' ? '' : 'Collision',
      }),
      publish: async () => {},
    };
    const ctx = componentFunctions('LongVegetationReport.svelte', ['show', 'publishWorkbook'], {
      contextId: 'ctx-lv', project: 'Sample', hierarchy: 'HierA', effectiveHierarchy: 'HierA', su: 'Working',
      projectActive: false, projectWorkspace: null, projectView: null, sharedPreferenceBarrier: false,
      busy: false, operationHeld: false, workbookBarrier: false, preferenceBarrier: false, workbookEnabled: true,
      settings: {}, workbookReview: {}, destination: dest, selectedWorkbookScope: 'unlumped',
      generation: 0, error: '', preview: null,
      cancel() {}, reportBusy() {},
      reads: { track: (p) => p, cancelAll() {} },
      workbookSession,
      VegetationReportService: {
        PreviewLongVegetation: () => Promise.reject(new Error('Preview denied')),
        ExportReviewedVegetationWorkbook: async () => null,
      },
      notifications,
    });
    await ctx.actions.publishWorkbook();
    pubStatus = 'not-published';
    await ctx.actions.publishWorkbook();
    await ctx.actions.show();

    const entries = notifications.getSnapshot().entries;
    assert.equal(entries.length, 3);
    assert.equal(entries[0].severity, 'error');
    assert.equal(entries[0].category, 'reports');
    assert.equal(entries[0].source, 'Long Vegetation');
    assert.equal(entries[1].severity, 'error');
    assert.equal(entries[2].severity, 'success');
    assert.equal(entries[2].category, 'reports');
    assert.equal(entries[2].source, 'Long Vegetation');
    assert.equal(entries[2].contextTag, 'Sample');
    assert.match(entries[2].message, /long-veg\.xlsx/);
  }

  // 2. LongEnvironmentReport.svelte
  {
    const notifications = makeController();
    const dest = 'C:\\out\\long-env.xlsx';
    let pubStatus = 'published';
    const workbookSession = {
      view: () => ({
        busy: false,
        blocked: true,
        requestedDestination: dest,
        outcome: pubStatus === 'published'
          ? { status: 'published', path: dest, sha256: 'e'.repeat(64), errorMessage: '' }
          : { status: 'not-published', path: '', sha256: '', errorMessage: 'Exists' },
        error: pubStatus === 'published' ? '' : 'Exists',
      }),
      publish: async () => {},
    };
    const ctx = componentFunctions('LongEnvironmentReport.svelte', ['show', 'publishWorkbook'], {
      contextId: 'ctx-le', project: 'Sample', su: 'Working', title: 'Report', titleError: null, ready: true,
      busy: false, preferenceBarrier: false, workbookBarrier: false, workbookEnabled: true,
      workbookReview: {}, destination: dest, generation: 0, error: '', preview: null,
      cancel() {}, reportBusy() {},
      reads: { track: (p) => p, cancelAll() {} },
      workbookSession,
      EnvironmentReportService: {
        PreviewLongEnvironment: () => Promise.reject(new Error('Env read failed')),
        ExportReviewedEnvironmentWorkbook: async () => null,
      },
      notifications,
    });
    await ctx.actions.publishWorkbook();
    pubStatus = 'not-published';
    await ctx.actions.publishWorkbook();
    await ctx.actions.show();

    const entries = notifications.getSnapshot().entries;
    assert.equal(entries.length, 3);
    assert.equal(entries[0].severity, 'error');
    assert.equal(entries[0].category, 'reports');
    assert.equal(entries[0].source, 'Long Environment');
    assert.equal(entries[1].severity, 'error');
    assert.equal(entries[2].severity, 'success');
    assert.equal(entries[2].category, 'reports');
    assert.equal(entries[2].source, 'Long Environment');
    assert.equal(entries[2].contextTag, 'Sample');
    assert.match(entries[2].message, /long-env\.xlsx/);
  }

  // 3. SubzoneMatrixReport.svelte
  {
    const notifications = makeController();
    const dest = 'C:\\out\\matrix.xlsx';
    let pubStatus = 'published';
    const session = {
      view: () => ({
        busy: false,
        blocked: true,
        requestedDestination: dest,
        outcome: pubStatus === 'published'
          ? { status: 'published', path: dest, sha256: 'f'.repeat(64), errorMessage: '' }
          : { status: 'not-published', path: '', sha256: '', errorMessage: 'Write error' },
        error: pubStatus === 'published' ? '' : 'Write error',
      }),
      publish: async () => {},
    };
    const ctx = componentFunctions('SubzoneMatrixReport.svelte', ['show', 'publishWorkbook'], {
      contextId: 'ctx-sm', hierarchy: 'SampleHier', hierarchyPath: 'C:\\h.db',
      busy: false, barrier: false, available: true, preview: null, workbook: {}, destination: dest,
      generation: 0, error: '', limit: 25,
      cancel() {}, reportBusy() {},
      reads: { track: (p) => p, cancelAll() {} },
      session,
      EnvironmentReportService: {
        GetSubzoneMatrixPreview: () => Promise.reject(new Error('Matrix failed')),
        ExportReviewedSubzoneMatrix: async () => null,
      },
      notifications,
    });
    await ctx.actions.publishWorkbook();
    pubStatus = 'not-published';
    await ctx.actions.publishWorkbook();
    await ctx.actions.show();

    const entries = notifications.getSnapshot().entries;
    assert.equal(entries.length, 3);
    assert.equal(entries[0].severity, 'error');
    assert.equal(entries[0].category, 'reports');
    assert.equal(entries[0].source, 'Subzone Matrix');
    assert.equal(entries[1].severity, 'error');
    assert.equal(entries[2].severity, 'success');
    assert.equal(entries[2].category, 'reports');
    assert.equal(entries[2].source, 'Subzone Matrix');
    assert.equal(entries[2].contextTag, 'SampleHier');
    assert.match(entries[2].message, /matrix\.xlsx/);
  }

  // 4. SiteUnitSummary.svelte, SummaryVegetationReport.svelte, and LifeformSummary.svelte load failures
  {
    const notifications = makeController();
    const suCtx = componentFunctions('SiteUnitSummary.svelte', ['show'], {
      contextId: 'ctx-su', project: 'Sample', su: 'Working', siteUnitType: 1, method: 1, mode: 'layer',
      busy: false, workbookBusy: false, preferenceBarrier: false, speciesBarrier: false, ready: true,
      speciesView: null, criteria: null, generation: 0, error: '', preview: null, speciesPreview: null,
      cancel() {}, reportBusy() {},
      reads: { track: (p) => p },
      EnvironmentReportService: { PreviewSiteUnitSummary: () => Promise.reject(new Error('SU load failed')) },
      notifications,
    });
    await suCtx.actions.show();

    const svCtx = componentFunctions('SummaryVegetationReport.svelte', ['previewReport'], {
      project: 'Sample', effectiveHierarchy: 'HierA', unitScope: 'su',
      hierarchyHeaderEnabled: false, effectiveCombineVariants: false, lumpTable: '',
      includeGoldstreamMetadata: false, qualityView: null, exclusionSummaryText: '',
      port: {},
      session: {
        show: async () => {},
        showConfigured: async () => {},
        view: () => ({ error: 'SV preview load failed' }),
      },
      notifications,
    });
    await svCtx.actions.previewReport();

    const lfCtx = componentFunctions('LifeformSummary.svelte', ['show'], {
      contextId: 'ctx-lf', project: 'Sample', projectPath: 'C:\\p.db', su: 'Working', suPath: 'C:\\p.db',
      enabled: true, attributesEnabled: true, busy: false, workbookBusy: false, scopeBlocked: false,
      unitScope: 'su', breakpointPolicy: 'lowest', ownerKey: 'k', generation: 0, error: '',
      preview: null, attributePreview: null,
      cancel() {}, reportBusy() {},
      reads: { track: (p) => p },
      VegetationReportService: { PreviewLifeformSummary: () => Promise.reject(new Error('LF preview failed')) },
      notifications,
    });
    await lfCtx.actions.show('lifeform');

    const entries = notifications.getSnapshot().entries;
    assert.equal(entries.length, 3);
    assert.equal(entries[0].severity, 'error');
    assert.equal(entries[0].category, 'reports');
    assert.equal(entries[0].source, 'Lifeform Summary');
    assert.equal(entries[0].contextTag, 'Sample');
    assert.equal(entries[1].severity, 'error');
    assert.equal(entries[1].category, 'reports');
    assert.equal(entries[1].source, 'Summary Vegetation');
    assert.equal(entries[1].contextTag, 'Sample');
    assert.equal(entries[2].severity, 'error');
    assert.equal(entries[2].category, 'reports');
    assert.equal(entries[2].source, 'Summary Environment');
    assert.equal(entries[2].contextTag, 'Sample');
  }
});

test('all 25 report and workbook Svelte components satisfy Clean Sweep UI and notification invariants', () => {
  const { readdirSync } = require('node:fs');
  const reportDir = srcPath('reports');
  const svelteFiles = readdirSync(reportDir).filter((name) => name.endsWith('.svelte')).sort();
  assert.ok(svelteFiles.length >= 25);
  const emojiRe = /\p{Extended_Pictographic}/u;
  const tailwindPaletteRegex = /\b(?:bg|text|border)-(?:indigo|emerald|amber|slate|teal|sky|rose|green|blue|gray|zinc|stone|red|yellow)-\d+\b/;

  for (const name of svelteFiles) {
    const rel = `reports/${name}`;
    const file = path.join(reportDir, name);
    const src = readFileSync(file, 'utf8');
    for (const target of ['client', 'server']) {
      const compiled = compile(src, { filename: file, generate: target });
      assert.deepEqual(compiled.warnings, [], `${rel} (${target}) emitted Svelte compiler warnings`);
    }
    assert.equal(emojiRe.test(src), false, `${rel} must contain zero emojis`);
    assert.equal(tailwindPaletteRegex.test(src), false, `${rel} must not use forbidden Tailwind palette classes`);
    if (/ReadRequests/.test(src)) {
      assert.match(
        src,
        /import\s*\{\s*notifications\s*\}\s*from\s*'\.\.\/shell\/notificationService\.svelte'/,
        `${rel} must import notifications from ../shell/notificationService.svelte`,
      );
    }
    assert.doesNotMatch(src, /; publication cannot be cancelled\./, `${rel} must not render transient publication busy chatter`);
    assert.doesNotMatch(src, /; Save cannot be cancelled/, `${rel} must not render transient save busy chatter`);
    assert.doesNotMatch(src, /Reading (?:owned|actual saved|complete owned|the source workbook plan)/, `${rel} must not render transient read busy chatter`);
    assert.doesNotMatch(src, /<p[^>]*data-(?:lifeform|environment|vegetation|project|site-unit|summary)-workbook-receipt/, `${rel} must not render known workbook DOM receipts`);
  }
});
