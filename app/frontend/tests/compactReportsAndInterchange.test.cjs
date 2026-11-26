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

test('all 6 primary reports wire QuickRun*Workbook and Render*HTMLReport RPCs and build valid desktop vs web requests', () => {
  const expectedWiring = [
    ['reports/SummaryVegetationReport.svelte', /QuickRunSummaryVegetationWorkbook/, /RenderSummaryVegetationHTMLReport/],
    ['reports/LongVegetationReport.svelte', /QuickRunLongVegetationWorkbook/, /RenderLongVegetationHTMLReport/],
    ['reports/LifeformSummary.svelte', /QuickRunLifeformWorkbook/, /RenderLifeformHTMLReport/],
    ['reports/LongEnvironmentReport.svelte', /QuickRunLongEnvironmentWorkbook/, /RenderLongEnvironmentHTMLReport/],
    ['reports/SiteUnitSummary.svelte', /QuickRunSummaryEnvironmentWorkbook/, /RenderSummaryEnvironmentHTMLReport/],
    ['reports/SubzoneMatrixReport.svelte', /QuickRunSubzoneMatrixWorkbook/, /RenderSubzoneMatrixHTMLReport/],
  ];
  for (const [rel, exportRe, htmlRe] of expectedWiring) {
    const src = readFileSync(srcPath(rel), 'utf8');
    assert.match(src, /CompactReportShell/, `${rel} must use CompactReportShell`);
    assert.match(src, exportRe, `${rel} must call ${exportRe}`);
    assert.match(src, htmlRe, `${rel} must call ${htmlRe}`);
  }

  const desktopCompact = loadTypeScript('reports/compactReport.ts', {
    '../../bindings/github.com/boostao/vpro/app': { ContextService: {} },
    '../web/runtimeMode': { IS_WEB_READONLY: false },
    '../web/webMeta': { formatWebDownloadFeedback: (e) => String(e) },
  });
  const desktopRunners = loadTypeScript('reports/compactReportRunners.ts', {
    '../../bindings/github.com/boostao/vpro/app': { EnvironmentReportService: {}, VegetationReportService: {} },
    '../shell/notificationService.svelte': { notifications: { success() {}, error() {} } },
    '../shell/webReadOnlyShell': { defaultWebExportFilename: (s, ext) => `${s}${ext}` },
    '../web/runtimeMode': { IS_WEB_READONLY: false },
    './compactReport': desktopCompact,
  });

  const svDesktop = desktopRunners.buildSummaryVegQuickRequest(desktopRunners.DEFAULT_SUMMARY_VEG_QUICK, 'Sample', true);
  assert.equal(svDesktop.savePreferences, true);
  assert.equal(svDesktop.openInSpreadsheet, true);
  assert.equal(svDesktop.unitScope, 'auto');

  const lvDesktop = desktopRunners.buildLongVegQuickRequest(desktopRunners.DEFAULT_LONG_VEG_QUICK, 'Sample', true);
  assert.equal(lvDesktop.savePreferences, true);
  assert.equal(lvDesktop.openInSpreadsheet, true);
  assert.equal(lvDesktop.scopeMode, 'auto');

  const webCompact = loadTypeScript('reports/compactReport.ts', {
    '../../bindings/github.com/boostao/vpro/app': { ContextService: {} },
    '../web/runtimeMode': { IS_WEB_READONLY: true },
    '../web/webMeta': { formatWebDownloadFeedback: (e) => String(e) },
  });
  const webRunners = loadTypeScript('reports/compactReportRunners.ts', {
    '../../bindings/github.com/boostao/vpro/app': { EnvironmentReportService: {}, VegetationReportService: {} },
    '../shell/notificationService.svelte': { notifications: { success() {}, error() {} } },
    '../shell/webReadOnlyShell': { defaultWebExportFilename: (s, ext) => `${s}${ext}` },
    '../web/runtimeMode': { IS_WEB_READONLY: true },
    './compactReport': webCompact,
  });

  const svWeb = webRunners.buildSummaryVegQuickRequest(webRunners.DEFAULT_SUMMARY_VEG_QUICK, 'BECMaster', true);
  assert.equal(svWeb.savePreferences, false);
  assert.equal(svWeb.openInSpreadsheet, false);
  assert.equal(svWeb.destinationPath, 'BECMaster_summary_veg.xlsx');
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
