const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { compile } = require('svelte/compiler');
const { render } = require('svelte/server');
const { componentFunctions, loadTypeScript, serverComponent, srcPath } = require('./svelteTestHelpers.cjs');

const EMOJI_RE = /\p{Extended_Pictographic}/u;

const TRACK_2C_SVELTE_FILES = [
  'reports/CompactReportShell.svelte',
  'reports/HTMLReportPreviewModal.svelte',
  'reports/SummaryVegetationQuickOptions.svelte',
  'reports/LongVegetationQuickOptions.svelte',
  'reports/SiteUnitSummaryQuickOptions.svelte',
  'interchange/InterchangeVPro64Tab.svelte',
  'interchange/InterchangeHubHeader.svelte',
  'interchange/InterchangeHub.svelte',
  'rsidecar/RSidecarWorkbench.svelte',
  'rsidecar/RSidecarWorkbenchHeader.svelte',
  'rsidecar/RSidecarQuartoTab.svelte',
  'rsidecar/RSidecarEdatopicTab.svelte',
  'diagnostics/ClassificationSynthesisView.svelte',
  'diagnostics/SynthesisTopChrome.svelte',
];

test('Track 2C Svelte components compile cleanly with 0 warnings and contain zero emojis', () => {
  for (const rel of TRACK_2C_SVELTE_FILES) {
    const file = srcPath(rel);
    const src = readFileSync(file, 'utf8');
    assert.equal(EMOJI_RE.test(src), false, `${rel} must contain zero emojis`);
    for (const target of ['client', 'server']) {
      const compiled = compile(src, { filename: file, generate: target });
      assert.deepEqual(compiled.warnings, [], `${rel} (${target}) emitted Svelte compiler warnings`);
    }
  }
});

test('compactReport helpers compute scope badges, spreadsheet labels, filenames, and local preference retention', () => {
  const calls = [];
  const compact = loadTypeScript('reports/compactReport.ts', {
    '../../bindings/github.com/boostao/vpro/app': {
      ContextService: {
        GetSpreadsheetAppPreference: async (cid) => {
          calls.push(['get', cid]);
          return { programPath: 'excel', autoOpenExports: true };
        },
        SetSpreadsheetAppPreference: async (cid, pref) => {
          calls.push(['set', cid, pref]);
          return pref;
        },
        OpenReportInSpreadsheet: async (cid, filePath) => {
          calls.push(['open', cid, filePath]);
        },
      },
    },
    '../web/runtimeMode': { IS_WEB_READONLY: false },
    '../web/webMeta': { formatWebDownloadFeedback: (e) => String(e) },
  });

  const activeScope = compact.describeCompactScope({ project: 'Haida', su: 'WorkingSU' });
  assert.equal(activeScope.mode, 'su');
  assert.equal(activeScope.ready, true);
  assert.match(activeScope.badge, /Active SU: WorkingSU/);

  const fallbackScope = compact.describeCompactScope({ project: 'Haida', su: 'None' });
  assert.equal(fallbackScope.mode, 'fallback');
  assert.equal(fallbackScope.ready, true);
  assert.match(fallbackScope.badge, /All Plots \/ Zone\+SubZone/);

  const missingHier = compact.describeCompactScope({ hierarchy: 'None', requiresHierarchy: true });
  assert.equal(missingHier.mode, 'missing-hierarchy');
  assert.equal(missingHier.ready, false);

  const validHier = compact.describeCompactScope({ hierarchy: 'CoastHier', requiresHierarchy: true });
  assert.equal(validHier.mode, 'hierarchy');
  assert.equal(validHier.ready, true);

  assert.equal(compact.formatSpreadsheetAppLabel({ programPath: '', autoOpenExports: true }), 'OS Default');
  assert.equal(compact.formatSpreadsheetAppLabel({ programPath: 'excel', autoOpenExports: true }), 'Microsoft Excel');
  assert.equal(compact.formatSpreadsheetAppLabel({ programPath: 'soffice', autoOpenExports: false }), 'LibreOffice Calc');
  assert.equal(
    compact.formatSpreadsheetAppLabel({ programPath: '/usr/bin/gnumeric', autoOpenExports: true }),
    'gnumeric'
  );
  assert.equal(compact.slugifyReportFilename('Summary Veg 2026!', '.html'), 'Summary_Veg_2026.html');
});

test('CompactReportShell renders primary Export/Display actions, Auto Scope fallback when SU is None, Spreadsheet App settings, and closed Advanced drawer', () => {
  const compact = loadTypeScript('reports/compactReport.ts', {
    '../../bindings/github.com/boostao/vpro/app': { ContextService: {} },
    '../web/runtimeMode': { IS_WEB_READONLY: false },
    '../web/webMeta': { formatWebDownloadFeedback: (e) => String(e) },
  });
  const Modal = serverComponent(readFileSync(srcPath('reports/HTMLReportPreviewModal.svelte'), 'utf8'), 'HTMLReportPreviewModal.svelte', {
    './compactReport': compact,
  });
  const Shell = serverComponent(readFileSync(srcPath('reports/CompactReportShell.svelte'), 'utf8'), 'CompactReportShell.svelte', {
    './compactReport': compact,
    './HTMLReportPreviewModal.svelte': { default: Modal },
    '../web/runtimeMode': { IS_WEB_READONLY: false },
    '../shell/notificationService.svelte': { notifications: { success() {}, error() {}, info() {}, warning() {} } },
  });

  // Desktop with ActiveSU === "None": buttons are NOT disabled, fallback badge shown, Spreadsheet App button shown
  const html = render(Shell, {
    props: {
      title: 'Summary Vegetation',
      contextId: 'ctx-1',
      project: 'Skeena',
      su: 'None',
      onExportSpreadsheet: () => {},
      onDisplayReport: () => {},
      onCloseHtmlReport: () => {},
      htmlReport: {
        title: 'Summary Vegetation Report',
        reportKind: 'summary_vegetation',
        project: 'Skeena',
        su: 'None',
        scopeLabel: 'All Project Plots',
        unitCount: 1,
        plotCount: 12,
        tableCount: 1,
        html: '<!doctype html><html><body><h1>Summary</h1></body></html>',
      },
    },
  }).body;

  assert.match(html, /data-compact-export-spreadsheet/);
  assert.match(html, /Export to Spreadsheet/);
  assert.match(html, /data-compact-display-report/);
  assert.match(html, /Display Report/);
  assert.doesNotMatch(html, /data-compact-export-spreadsheet[^>]*\sdisabled/);
  assert.doesNotMatch(html, /data-compact-display-report[^>]*\sdisabled/);
  assert.match(html, /Auto Scope: All Plots \/ Zone\+SubZone/);
  assert.match(html, /data-spreadsheet-app-toggle/);
  assert.match(html, /data-html-report-modal/);
  assert.match(html, /sandbox="allow-same-origin allow-modals"/);
  assert.doesNotMatch(html, /allow-scripts/);
  assert.match(html, /data-html-report-print/);
  assert.match(html, /data-html-report-save/);

  // Web read-only mode hides Spreadsheet App toggle
  const ShellWeb = serverComponent(readFileSync(srcPath('reports/CompactReportShell.svelte'), 'utf8'), 'CompactReportShell.svelte', {
    './compactReport': compact,
    './HTMLReportPreviewModal.svelte': { default: Modal },
    '../web/runtimeMode': { IS_WEB_READONLY: true },
    '../shell/notificationService.svelte': { notifications: { success() {}, error() {}, info() {}, warning() {} } },
  });
  const webHtml = render(ShellWeb, {
    props: {
      title: 'Summary Vegetation',
      contextId: 'ctx-web',
      project: 'BECMaster',
      su: 'None',
      onExportSpreadsheet: () => {},
      onDisplayReport: () => {},
      onCloseHtmlReport: () => {},
    },
  }).body;
  assert.doesNotMatch(webHtml, /data-spreadsheet-app-toggle/);
  assert.match(webHtml, /Export to Spreadsheet/);
  assert.match(webHtml, /Display Report/);
});

test('all 6 primary reports wire QuickRun*Workbook on desktop, allowlisted ExportReviewed* downloads in IS_WEB_READONLY, and Render*HTMLReport', async () => {
  const path = require('node:path');
  const expectedWiring = [
    ['reports/SummaryVegetationReport.svelte', /exportSummaryVegSpreadsheet/, /RenderSummaryVegetationHTMLReport/],
    ['reports/LongVegetationReport.svelte', /exportLongVegSpreadsheet/, /RenderLongVegetationHTMLReport/],
    ['reports/LifeformSummary.svelte', /exportLifeformSpreadsheet/, /RenderLifeformHTMLReport/],
    ['reports/LongEnvironmentReport.svelte', /exportLongEnvSpreadsheet/, /RenderLongEnvironmentHTMLReport/],
    ['reports/SiteUnitSummary.svelte', /exportSummaryEnvSpreadsheet/, /RenderSummaryEnvironmentHTMLReport/],
    ['reports/SubzoneMatrixReport.svelte', /exportSubzoneMatrixSpreadsheet/, /RenderSubzoneMatrixHTMLReport/],
  ];
  for (const [rel, exportRe, htmlRe] of expectedWiring) {
    const src = readFileSync(srcPath(rel), 'utf8');
    assert.match(src, /CompactReportShell/, `${rel} must use CompactReportShell`);
    assert.match(src, exportRe, `${rel} must call ${exportRe}`);
    assert.match(src, htmlRe, `${rel} must call ${htmlRe}`);
  }

  // 1. Desktop mode (!IS_WEB_READONLY) invokes all 6 QuickRun*Workbook RPCs
  const desktopCalls = [];
  const quickVegResult = {
    reportKind: 'veg', title: 'Veg', project: 'Sample', su: 'None', scopeLabel: 'All Plots',
    unitCount: 1, plotCount: 4, rowCount: 8, path: '/tmp/out.xlsx', sha256: 'a'.repeat(64), bytes: 1024,
    preferencesSaved: true, openedInSpreadsheet: true,
  };
  const quickEnvResult = {
    reportKind: 'env', title: 'Env', project: 'Sample', su: 'None', scopeLabel: 'All Plots',
    unitCount: 1, plotCount: 4, path: '/tmp/out.xlsx', sha256: 'b'.repeat(64), bytes: 1024,
    preferencesSaved: true, openedInSpreadsheet: true,
  };
  const desktopCompact = loadTypeScript('reports/compactReport.ts', {
    '../../bindings/github.com/boostao/vpro/app': { ContextService: {} },
    '../web/runtimeMode': { IS_WEB_READONLY: false },
    '../web/webMeta': { formatWebDownloadFeedback: (e) => String(e) },
  });
  const desktopRunners = loadTypeScript('reports/compactReportRunners.ts', {
    '../../bindings/github.com/boostao/vpro/app': {
      VegetationReportService: new Proxy({}, {
        get: (_, m) => async (...args) => { desktopCalls.push(`VegetationReportService.${String(m)}`); return quickVegResult; },
      }),
      EnvironmentReportService: new Proxy({}, {
        get: (_, m) => async (...args) => { desktopCalls.push(`EnvironmentReportService.${String(m)}`); return quickEnvResult; },
      }),
    },
    '../shell/notificationService.svelte': { notifications: { success() {}, error() {} } },
    '../shell/webReadOnlyShell': { defaultWebExportFilename: (s, ext) => `${s}${ext}` },
    '../web/runtimeMode': { IS_WEB_READONLY: false },
    './compactReport': desktopCompact,
  });

  await desktopRunners.exportSummaryVegSpreadsheet('ctx-d', desktopRunners.DEFAULT_SUMMARY_VEG_QUICK, 'Sample', 'None');
  await desktopRunners.exportLongVegSpreadsheet('ctx-d', desktopRunners.DEFAULT_LONG_VEG_QUICK, 'Sample', 'None');
  await desktopRunners.exportLifeformSpreadsheet('ctx-d', desktopRunners.DEFAULT_LIFEFORM_QUICK, 'Sample', 'None');
  await desktopRunners.exportLongEnvSpreadsheet('ctx-d', desktopRunners.DEFAULT_LONG_ENV_QUICK, 'Sample', 'None');
  await desktopRunners.exportSummaryEnvSpreadsheet('ctx-d', desktopRunners.DEFAULT_SUMMARY_ENV_QUICK, 'Sample', 'None');
  await desktopRunners.exportSubzoneMatrixSpreadsheet('ctx-d', 'CoastHier');

  assert.deepEqual(desktopCalls, [
    'VegetationReportService.QuickRunSummaryVegetationWorkbook',
    'VegetationReportService.QuickRunLongVegetationWorkbook',
    'VegetationReportService.QuickRunLifeformWorkbook',
    'EnvironmentReportService.QuickRunLongEnvironmentWorkbook',
    'EnvironmentReportService.QuickRunSummaryEnvironmentWorkbook',
    'EnvironmentReportService.QuickRunSubzoneMatrixWorkbook',
  ]);

  // 2. Web read-only mode (IS_WEB_READONLY) NEVER invokes QuickRun*Workbook and strictly calls allowlisted RPCs
  const allowlist = JSON.parse(
    readFileSync(path.resolve(__dirname, '..', '..', 'resources', 'web_rpc_allowlist.json'), 'utf8')
  );
  const webCalls = [];
  const fakeHash = 'c'.repeat(64);
  const webCompact = loadTypeScript('reports/compactReport.ts', {
    '../../bindings/github.com/boostao/vpro/app': { ContextService: {} },
    '../web/runtimeMode': { IS_WEB_READONLY: true },
    '../web/webMeta': { formatWebDownloadFeedback: (e) => String(e) },
  });
  const webRunners = loadTypeScript('reports/compactReportRunners.ts', {
    '../../bindings/github.com/boostao/vpro/app': {
      VegetationReportService: new Proxy({}, {
        get: (_, m) => async () => {
          const name = String(m);
          webCalls.push(['VegetationReportService', name]);
          if (name.startsWith('QuickRun')) throw new Error(`HTTP 403 forbidden on vpro-web: ${name}`);
          if (name.startsWith('ExportReviewed')) return { status: 'published', path: 'dl.xlsx', errorMessage: '' };
          return {
            approvalHash: fakeHash,
            bytes: 2048,
            scope: 'unlumped',
            createdDate: '2026-11-26',
            options: { title: 'SumVeg' },
            details: [true, true, true, true, true, true],
            preview: { units: [{}], memberships: [{}, {}], report: { units: [{ plots: [{}] }] } },
            lifeform: { report: { units: [{ nPlots: 3 }] } },
          };
        },
      }),
      EnvironmentReportService: new Proxy({}, {
        get: (_, m) => async () => {
          const name = String(m);
          webCalls.push(['EnvironmentReportService', name]);
          if (name.startsWith('QuickRun')) throw new Error(`HTTP 403 forbidden on vpro-web: ${name}`);
          if (name.startsWith('ExportReviewed')) return { status: 'published', path: 'dl.xlsx', errorMessage: '' };
          return {
            approvalHash: fakeHash,
            bytes: 2048,
            options: { method: 1, orderBy: 2, includeSpecies: true, coverCalculation: 1, andOr: 1, presenceGreaterThan: 20, coverGreaterThan: 0 },
            preview: { columns: ['CWH'], total: 4, report: { title: 'Long Env', units: [{ nPlots: 2, plots: [{}, {}] }] } },
            environment: { report: { units: [{ nPlots: 2 }] } },
          };
        },
      }),
    },
    '../shell/notificationService.svelte': { notifications: { success() {}, error() {} } },
    '../shell/webReadOnlyShell': { defaultWebExportFilename: (s, ext) => `${s}${ext}` },
    '../web/runtimeMode': { IS_WEB_READONLY: true },
    './compactReport': webCompact,
  });

  const webResults = [
    await webRunners.exportSummaryVegSpreadsheet('ctx-w', webRunners.DEFAULT_SUMMARY_VEG_QUICK, 'BECMaster', 'Working'),
    await webRunners.exportLongVegSpreadsheet('ctx-w', webRunners.DEFAULT_LONG_VEG_QUICK, 'BECMaster', 'Working'),
    await webRunners.exportLifeformSpreadsheet('ctx-w', webRunners.DEFAULT_LIFEFORM_QUICK, 'BECMaster', 'Working'),
    await webRunners.exportLongEnvSpreadsheet('ctx-w', webRunners.DEFAULT_LONG_ENV_QUICK, 'BECMaster', 'Working'),
    await webRunners.exportSummaryEnvSpreadsheet('ctx-w', webRunners.DEFAULT_SUMMARY_ENV_QUICK, 'BECMaster', 'Working'),
    await webRunners.exportSummaryEnvSpreadsheet('ctx-w', { ...webRunners.DEFAULT_SUMMARY_ENV_QUICK, orderBy: 2, includeSpecies: 1 }, 'BECMaster', 'Working'),
    await webRunners.exportSubzoneMatrixSpreadsheet('ctx-w', 'CoastHier'),
  ];

  for (const out of webResults) {
    assert.equal(out.error, '');
    assert.ok(out.summary, 'web export should produce summary');
  }
  assert.equal(webCalls.some(([, m]) => m.startsWith('QuickRun')), false, 'web mode must never call QuickRun*Workbook');
  for (const [svc, method] of webCalls) {
    assert.ok(
      allowlist.services[svc] && allowlist.services[svc][method],
      `${svc}.${method} must be present in web_rpc_allowlist.json`
    );
  }
  const calledMethods = webCalls.map(([svc, m]) => `${svc}.${m}`);
  for (const expectedDownload of [
    'VegetationReportService.ExportReviewedSummaryVegetationWorkbook',
    'VegetationReportService.ExportReviewedVegetationWorkbook',
    'VegetationReportService.ExportReviewedLifeformWorkbook',
    'EnvironmentReportService.ExportReviewedEnvironmentWorkbook',
    'EnvironmentReportService.ExportReviewedSiteUnitSummaryWorkbook',
    'EnvironmentReportService.ExportReviewedSiteUnitSummaryExtendedWorkbook',
    'EnvironmentReportService.ExportReviewedSubzoneMatrix',
  ]) {
    assert.ok(calledMethods.includes(expectedDownload), `expected web download call ${expectedDownload}`);
  }
});

test('RSidecarWorkbench supports initialTab="quarto" and standaloneQuartoMode with instant HTML fallback', async () => {
  const vegCalls = [];
  const quality = loadTypeScript('entry/qualityEditor.ts', {
    './becEditor': loadTypeScript('entry/becEditor.ts'),
  });
  const rMod = loadTypeScript('rsidecar/rSidecarWorkbench.ts', {
    '../../bindings/github.com/boostao/vpro/app': {
      EnvironmentReportService: {},
      VegetationReportService: {
        RenderSummaryVegetationHTMLReport: async (cid, req) => {
          vegCalls.push([cid, req]);
          return {
            title: req.title,
            reportKind: 'summary_vegetation',
            project: 'Sample',
            su: 'None',
            scopeLabel: 'All Plots',
            unitCount: 1,
            plotCount: 5,
            tableCount: 1,
            html: '<html><body>Report</body></html>',
          };
        },
      },
    },
    '../entry/qualityEditor': quality,
    '../shell/notificationService.svelte': { notifications: { success() {}, error() {}, info() {}, warning() {} } },
  });

  const fallbackRes = await rMod.defaultRSidecarPort.renderInstantHTMLReport('ctx-q', 'My Unit Guide');
  assert.equal(vegCalls.length, 1);
  assert.equal(vegCalls[0][1].title, 'My Unit Guide');
  assert.equal(vegCalls[0][1].unitScope, 'auto');
  assert.equal(fallbackRes.plotCount, 5);

  const Workbench = serverComponent(readFileSync(srcPath('rsidecar/RSidecarWorkbench.svelte'), 'utf8'), 'RSidecarWorkbench.svelte', {
    './rSidecarWorkbench': rMod,
  });
  const html = render(Workbench, {
    props: {
      contextId: 'ctx-q',
      activeProject: 'Sample',
      activeSu: 'None',
      initialTab: 'quarto',
      standaloneQuartoMode: true,
    },
  }).body;

  assert.match(html, /data-quarto-standalone-heading/);
  assert.match(html, /data-quarto-unit-report-panel/);
  assert.match(html, /data-quarto-readiness-strip/);
  assert.match(html, /data-quarto-instant-html-fallback/);
  assert.match(html, /Display Instant HTML Report \(No R Required\)/);
});

test('ClassificationSynthesisView renders one-click scope guidance when ActiveSU is None and no units are present', () => {
  const syn = loadTypeScript('diagnostics/classificationSynthesis.ts', {
    '../../bindings/github.com/boostao/vpro/app': {
      ClassificationService: {},
      ContextService: {},
      ImportExportService: {},
      VegetationReportService: {},
    },
  });
  const Comp = serverComponent(
    readFileSync(srcPath('diagnostics/ClassificationSynthesisView.svelte'), 'utf8'),
    'ClassificationSynthesisView.svelte',
    {
      './classificationSynthesis': syn,
      '../shell/notificationService.svelte': { notifications: { push() {}, success() {}, error() {}, info() {}, warning() {} } },
    }
  );
  const html = render(Comp, {
    props: {
      contextId: 'ctx-syn',
      project: 'Haida',
      su: 'None',
      initialSnapshot: null,
    },
  }).body;

  assert.match(html, /data-synthesis-scope-guidance/);
  assert.match(html, /data-synthesis-use-working-units/);
  assert.match(html, /Use Working Units/);
  assert.match(html, /data-synthesis-retry-analysis/);
});

test('InterchangeVPro64Tab replaces VENUS 5 with VPro64 Export checkboxes, ODBC note, and desktop/web export flows', async () => {
  const calls = [];
  const hub = loadTypeScript('interchange/interchangeHub.ts', {
    '../../bindings/github.com/boostao/vpro/app': {
      ImportExportService: {
        ChooseVPro64ExportFile: async () => '/tmp/Haida_VPro64.db',
        ExportVPro64Database: async (cid, req) => {
          calls.push([cid, req]);
          return {
            sourceProject: 'Haida',
            targetProject: req.targetProjectName || 'Haida',
            destinationPath: req.destinationPath,
            sha256: 'a'.repeat(64),
            bytes: 4096,
            journalMode: 'delete',
            plotCount: 14,
            includedSU: req.includeActiveSU ? 'Haida_SU' : '',
            includedHierarchy: req.includeHierarchy ? 'Coast_Hierarchy' : '',
            includedMensuration: req.includeMensuration,
            tables: [{ sourceTable: 'Haida_Env', targetTable: 'Haida_Env', rowCount: 14 }],
          };
        },
      },
    },
    '@wailsio/runtime': { Dialogs: {}, Events: {} },
  });

  const payload = hub.buildVPro64ExportPayload('/tmp/out.db', 'Haida64', true, true, false, true);
  assert.deepEqual(JSON.parse(JSON.stringify(payload)), {
    destinationPath: '/tmp/out.db',
    targetProjectName: 'Haida64',
    includeActiveSU: true,
    includeHierarchy: true,
    includeMensuration: false,
    includeCompanions: true,
  });

  const TabDesktop = serverComponent(
    readFileSync(srcPath('interchange/InterchangeVPro64Tab.svelte'), 'utf8'),
    'InterchangeVPro64Tab.svelte',
    { '../web/runtimeMode': { IS_WEB_READONLY: false } }
  );
  const desktopHtml = render(TabDesktop, {
    props: {
      contextId: 'ctx-v64',
      busy: false,
      operationHeld: false,
      vpro64Outcome: null,
      onChooseVPro64Dest: async () => {},
      onRunVPro64Export: async () => {},
    },
  }).body;

  assert.match(desktopHtml, /data-interchange-vpro64-tab/);
  assert.match(desktopHtml, /data-vpro64-include-su/);
  assert.match(desktopHtml, /data-vpro64-include-hierarchy/);
  assert.match(desktopHtml, /data-vpro64-include-mensuration/);
  assert.match(desktopHtml, /data-vpro64-include-companions/);
  assert.match(desktopHtml, /SQLite ODBC module/i);
  assert.match(desktopHtml, /data-browse-vpro64-dest/);
  assert.match(desktopHtml, /Export VPro64 Database \(\.db\)/);

  const TabWeb = serverComponent(
    readFileSync(srcPath('interchange/InterchangeVPro64Tab.svelte'), 'utf8'),
    'InterchangeVPro64Tab.svelte',
    { '../web/runtimeMode': { IS_WEB_READONLY: true } }
  );
  const webHtml = render(TabWeb, {
    props: {
      contextId: 'ctx-v64',
      busy: false,
      operationHeld: false,
      vpro64Outcome: null,
      onChooseVPro64Dest: async () => {},
      onRunVPro64Export: async () => {},
    },
  }).body;
  assert.doesNotMatch(webHtml, /data-browse-vpro64-dest/);
  assert.match(webHtml, /Download VPro64 Database \(\.db\)/);

  // Verify Intercom choose + export flow on InterchangeHub
  const host = componentFunctions('InterchangeHub.svelte', ['chooseVPro64Dest', 'runVPro64Export', 'pushHubError', 'setBusy'], {
    $state: { snapshot: (v) => structuredClone(v) },
    contextId: 'ctx-v64',
    busy: false,
    operationHeld: false,
    error: '',
    generation: 0,
    vpro64DestPath: '',
    vpro64TargetProject: 'Haida64',
    vpro64IncludeActiveSU: true,
    vpro64IncludeHierarchy: true,
    vpro64IncludeMensuration: true,
    vpro64IncludeCompanions: true,
    vpro64Outcome: null,
    validateTargetProjectName: hub.validateTargetProjectName,
    defaultInterchangeHubPort: hub.defaultInterchangeHubPort,
    onBusyChange() {},
    notifications: { success() {}, error() {} },
    port: hub.defaultInterchangeHubPort,
  });

  await host.actions.chooseVPro64Dest();
  assert.equal(host.vpro64DestPath, '/tmp/Haida_VPro64.db');
  await host.actions.runVPro64Export();
  assert.equal(calls.length, 1);
  assert.equal(calls[0][1].includeMensuration, true);
  assert.equal(host.vpro64Outcome.plotCount, 14);
});
