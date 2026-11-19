const { readJsonFixture } = require('./fixtureLoader.cjs');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');
const { render } = require('svelte/server');
const {
  componentFunctions,
  loadTypeScript,
  serverComponent,
  srcPath,
} = require('./svelteTestHelpers.cjs');

const { createNotificationController } = loadTypeScript('shell/notificationService.svelte.ts', {
  'svelte/store': require('svelte/store'),
});

const lifeform = loadTypeScript('lifeformSummary.ts');
const summary = loadTypeScript('summaryVegetation.ts', { './lifeformSummary': lifeform }, { setTimeout });
const qualityEditor = loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });
const cells = loadTypeScript('projectMetadataRestore.ts', { './qualityEditor': qualityEditor, './projectMetadataEditor': {} });
const locations = loadTypeScript('plotLocationReview.ts', { './projectMetadataRestore': cells });
const earth = loadTypeScript('googleEarthReview.ts', {
  './projectMetadataRestore': cells,
  './qualityEditor': qualityEditor,
  './plotLocationReview': locations,
});
const shared = loadTypeScript('reportTitlePreferences.ts', {
  './qualityEditor': qualityEditor,
  './googleEarthReview': earth,
});
const transport = loadTypeScript('siviParentTransport.ts', {
  './projectMetadataRestore': cells,
  './siviParentEditor': {},
  './siviParentSession': {},
});
const references = loadTypeScript('reports/qualityMinimumReference.ts', {
  './lifeformSummary': lifeform,
  './projectMetadataRestore': cells,
  './siviParentTransport': transport,
});
const qualityPrefs = loadTypeScript('reports/summaryVegetationQualityPreferences.ts', {
  './googleEarthReview': earth,
  './lifeformSummary': lifeform,
  './qualityEditor': qualityEditor,
  './qualityMinimumReference': references,
  './reportTitlePreferences': shared,
});

const summaryWire = readJsonFixture('summaryVegetationWire.json');
const qualityWire = readJsonFixture('summaryVegetationQualityPreferencesWire.json');
const scopeWire = readJsonFixture('longVegetationProjectScopeWire.json');

test('UX-REPORTS-004: Preview with Saved Preferences renders table immediately without requiring Load saved quality options', async () => {
  const rawPreview = structuredClone(summaryWire[1]);
  rawPreview.appliedPreferences = {
    title: 'Short veg report title',
    average: 1,
    display: 1,
    showClass: 0,
    groupBy: 1,
    unitScope: 'su',
  };
  const owner = {
    contextId: rawPreview.contextId,
    project: rawPreview.project,
    projectPath: rawPreview.projectPath,
    su: rawPreview.su,
    suPath: rawPreview.suPath,
  };
  const session = new summary.SummaryVegetationSession(owner);
  await session.showWithPreferences({
    preview: async () => rawPreview,
    previewWithPreferences: async () => rawPreview,
    cancel() {},
  });

  // Unloaded quality session (qualityView.saved === null -> qualityUnavailable === true, qualityInvalid === false)
  const unloadedQuality = new qualityPrefs.SummaryVegetationQualityPreferencesSession(owner);
  assert.equal(unloadedQuality.view().saved, null);

  const Panel = serverComponent(
    readFileSync(srcPath('SummaryVegetationReport.svelte'), 'utf8'),
    'SummaryVegetationReport.svelte',
    {
      './summaryVegetation': { ...summary, summaryVegetationSession: () => session },
      './summaryVegetationQualityPreferences': {
        ...qualityPrefs,
        summaryVegetationQualityPreferenceSession: () => unloadedQuality,
      },
      '../bindings/github.com/boostao/vpro/app': {},
      '../shared/state': { projectState: { subscribe(fn) { fn(null); return () => {}; } } },
      '../classification/SiteUnitExclusionFilter.svelte': { default: () => {} },
      '../classification/siteUnitExclusionFilter': {},
    }
  );

  const html = render(Panel, { props: { ...owner, onBusyChange() {} } }).body;
  assert.match(html, /<article[^>]*data-summary-result[^>]*>/, 'Preview result article must render immediately');
  const rowCount = (html.match(/<tbody>[\s\S]*?<\/tbody>/)?.[0].match(/<tr>/g) ?? []).length;
  assert.ok(rowCount > 0, `Expected visible tbody rows in Preview with Saved Preferences, got ${rowCount}`);
  assert.match(html, /Synced saved preferences:/);

  // If quality reload fails (qualityInvalid === true), stale preview is suppressed safely.
  unloadedQuality.rejectRead(new Error('quality read failed'));
  const htmlInvalid = render(Panel, { props: { ...owner, onBusyChange() {} } }).body;
  assert.doesNotMatch(htmlInvalid, /<article[^>]*data-summary-result[^>]*>/);
});

test('UX-REPORTS-004: SummaryVegetationReport normalizes showClass=0 for display 1..3/6 and normalizes Exclusion Filter preview sources', async () => {
  const rawPreview = structuredClone(summaryWire[1]);
  const owner = {
    contextId: rawPreview.contextId,
    project: rawPreview.project,
    projectPath: rawPreview.projectPath,
    su: rawPreview.su,
    suPath: rawPreview.suPath,
  };

  const ProbeExclusionFilter = serverComponent(
    '<script lang="ts">let p = $props();</script><span data-probe-show-class={String(p.showClass)} data-probe-display={String(p.display)}></span>',
    'SiteUnitExclusionFilter.svelte'
  );

  for (const [display, expectedShowClass] of [
    [1, 0],
    [2, 0],
    [3, 0],
    [4, 1],
    [5, 20],
    [6, 0],
  ]) {
    const session = new summary.SummaryVegetationSession(owner);
    session.edit(1, display, display === 5 ? 20 : 1, 11);
    const Panel = serverComponent(
      readFileSync(srcPath('SummaryVegetationReport.svelte'), 'utf8'),
      'SummaryVegetationReport.svelte',
      {
        './summaryVegetation': { ...summary, summaryVegetationSession: () => session },
        '../bindings/github.com/boostao/vpro/app': {},
        '../shared/state': { projectState: { subscribe(fn) { fn(null); return () => {}; } } },
        '../classification/SiteUnitExclusionFilter.svelte': { default: ProbeExclusionFilter },
        '../classification/siteUnitExclusionFilter': {},
      }
    );
    const html = render(Panel, { props: { ...owner, onBusyChange() {} } }).body;
    assert.match(
      html,
      new RegExp(`data-probe-show-class="${expectedShowClass}"`),
      `display=${display} must forward showClass=${expectedShowClass} to SiteUnitExclusionFilter`
    );
    assert.match(html, new RegExp(`data-probe-display="${display}"`));
  }

  // Verify normalizeExclusionSummaryPreview handles filtered/breakpoint source tags and optional references cleanly.
  const ctx = componentFunctions('SummaryVegetationReport.svelte', ['normalizeExclusionSummaryPreview'], {});
  const filteredPreview = {
    ...structuredClone(summaryWire[1]),
    source: 'literal-filtered-su-layer',
  };
  const normalized = ctx.actions.normalizeExclusionSummaryPreview(filteredPreview);
  assert.equal(normalized.source, 'literal-normal-su-layer');
  const session = new summary.SummaryVegetationSession(owner);
  await session.applyExternalPreview(normalized, { preview: async () => null, cancel() {} });
  assert.equal(session.view().error, '');
  assert.ok(session.view().preview && session.view().preview.rows.length > 0);
});

test('UX-REPORTS-005: Default Summary quality preferences have empty BECMinimum (never literal "True")', () => {
  assert.equal(qualityWire.review.values.becMinimum, '');
  const owner = {
    contextId: qualityWire.review.contextId,
    project: qualityWire.review.project,
    projectPath: qualityWire.review.projectPath,
    su: 'Sample',
    suPath: qualityWire.review.projectPath,
  };
  const session = new qualityPrefs.SummaryVegetationQualityPreferencesSession(owner);
  session.apply({ ...structuredClone(qualityWire.review), ...owner });

  const QualityPanel = serverComponent(
    readFileSync(srcPath('SummaryVegetationQualityPreferences.svelte'), 'utf8'),
    'SummaryVegetationQualityPreferences.svelte',
    { './summaryVegetationQualityPreferences': qualityPrefs }
  );
  const html = render(QualityPanel, {
    props: {
      contextId: owner.contextId,
      preferences: session,
      port: { read: () => { throw new Error('unexpected read'); }, save: () => { throw new Error('unexpected save'); } },
      onReadBusyChange() {},
    },
  }).body;
  const becInput = html.match(/<input[^>]*data-source-control="BEC_Use"[^>]*>/)?.[0] ?? '';
  assert.ok(becInput, 'BEC_Use input must render');
  assert.doesNotMatch(becInput, /value="True"/i, 'BEC_Use input must never default to literal "True"');
  assert.match(becInput, /value=""/, 'BEC_Use input must default to empty string');
});

test('UX-REPORTS-007: Opening Summary Vegetation with SU=None fires zero error toasts and zero red alerts', () => {
  const notifications = createNotificationController({ schedule: () => 0, cancelSchedule: () => {} });
  const fieldList = loadTypeScript('summaryVegetationFieldList.ts');
  const numericEnv = loadTypeScript('summaryVegetationEnvironmentalNumeric.ts', {
    './lifeformSummary': lifeform,
    './summaryVegetationFieldList': fieldList,
  });
  const envMod = loadTypeScript('summaryVegetationEnvironmental.ts', {
    './lifeformSummary': lifeform,
    './summaryVegetationFieldList': fieldList,
    './summaryVegetation': summary,
    './summaryVegetationEnvironmentalNumeric': numericEnv,
  });
  const desktopEnv = envMod.summaryEnvironmentalLifeformRegistry(true);

  const Panel = serverComponent(
    readFileSync(srcPath('SummaryVegetationReport.svelte'), 'utf8'),
    'SummaryVegetationReport.svelte',
    {
      './summaryVegetation': summary,
      './summaryVegetationEnvironmentalDesktop': {
        summaryEnvironmentalEnabled: true,
        summaryEnvironmentalNumericEnabled: true,
        summaryEnvironmentalLifeformEnabled: true,
        summaryEnvironmentalDesktop: desktopEnv,
        summaryEnvironmentalPort: { preview: () => Promise.reject(new Error('must not preview on mount')) },
      },
      '../shell/notificationService.svelte': { notifications },
      '../bindings/github.com/boostao/vpro/app': {},
      '../shared/state': { projectState: { subscribe(fn) { fn(null); return () => {}; } } },
      '../classification/SiteUnitExclusionFilter.svelte': { default: () => {} },
      '../classification/siteUnitExclusionFilter': {},
    }
  );

  const html = render(Panel, {
    props: {
      contextId: 'ctx-none',
      project: 'Sample',
      projectPath: '/tmp/Sample.db',
      su: 'None',
      suPath: '',
      onBusyChange() {},
    },
  }).body;

  assert.equal(notifications.getSnapshot().entries.length, 0, 'Summary Vegetation mount with SU=None must emit zero toasts');
  assert.doesNotMatch(html, /role="alert"/, 'Summary Vegetation mount with SU=None must render zero role="alert" elements');
  assert.match(html, /class="scope-guidance[^"]*"[^>]*role="status"/);
  assert.match(html.match(/<button[^>]*data-summary-preview-preferences[^>]*>/)[0], /\bdisabled\b/);
});

test('UX-REPORTS-007: Opening Long Vegetation with SU=None and SU=Sample renders zero pre-action alerts and skips GetLongVegetationOptions when SU=None', async () => {
  const notifications = createNotificationController({ schedule: () => 0, cancelSchedule: () => {} });
  const scopePanelSrc = readFileSync(srcPath('LongVegetationProjectScopeSelection.svelte'), 'utf8');
  const RealScopePanel = serverComponent(scopePanelSrc, 'LongVegetationProjectScopeSelection.svelte', {
    '../shell/notificationService.svelte': { notifications },
  });

  class PubStub {
    view() { return { busy: false, blocked: false, error: '', outcome: null, requestedDestination: '' }; }
    subscribe(fn) { fn(); return () => {}; }
  }

  for (const suValue of ['None', 'Sample']) {
    const scopeState = {
      scope: {
        contextId: `ctx-${suValue}`,
        project: 'Sample',
        projectPath: '/tmp/Sample.db',
        su: suValue,
        suPath: suValue === 'None' ? '' : '/tmp/Sample.db',
        sourceKind: 'selected-list',
        revision: '0',
        fields: [],
        build: null,
        buildCurrent: false,
      },
      definitions: scopeWire[0].catalogue.definitions,
      fields: [],
      dirty: false,
      draftError: 'Select at least one physical field before Build, or Undo the field draft.',
      error: '',
      busy: false,
      authorityUnknown: false,
      outputReady: false,
      closeBlocked: false,
    };
    const workspaceView = {
      scope: scopeState,
      units: { closeBlocked: false, readBusy: false, busy: false, blocked: false },
      publication: { busy: false, blocked: false, error: '', outcome: null, requestedDestination: '' },
      readBusy: false,
      error: '',
      settings: null,
      preview: null,
      workbookReview: null,
      projectActive: false,
      outputReady: false,
      scopeOperationHeld: false,
      scopeMutationHeld: false,
      unitOperationHeld: false,
      unitMutationHeld: false,
      closeBlocked: false,
    };
    const workspace = {
      view: () => structuredClone(workspaceView),
      subscribe(fn) { fn(); return () => {}; },
      selection: {
        view: () => structuredClone(scopeState),
        subscribe(fn) { fn(); return () => {}; },
        cancel() {},
        load: async () => {},
      },
      units: { cancelRead() {} },
      cancelScopeReads() {},
      cancelUnitReads() {},
      cancelReportRead() {},
      invalidate() {},
    };

    const LongVeg = serverComponent(
      readFileSync(srcPath('LongVegetationReport.svelte'), 'utf8'),
      'LongVegetationReport.svelte',
      {
        '../bindings/github.com/boostao/vpro/app': {},
        '../shell/notificationService.svelte': { notifications },
        './longVegetationProjectWorkspaces': { projectReportWorkspace: () => workspace },
        './LongVegetationProjectScopeSelection.svelte': { default: RealScopePanel },
        './LongVegetationProjectUnitPreferences.svelte': { default() {} },
        './longVegetationSelectedUnitSelection': {},
        './LongVegetationSelectedUnitSelection.svelte': { default() {} },
        '../shared/state': { projectState: { subscribe(fn) { fn(null); return () => {}; } } },
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
      }
    );

    const html = render(LongVeg, {
      props: {
        contextId: `ctx-${suValue}`,
        project: 'Sample',
        projectPath: '/tmp/Sample.db',
        su: suValue,
        suPath: suValue === 'None' ? '' : '/tmp/Sample.db',
        onBusyChange() {},
      },
    }).body;

    assert.equal(notifications.getSnapshot().entries.length, 0, `Long Vegetation mount (${suValue}) must emit zero toasts`);
    assert.doesNotMatch(html, /role="alert"/, `Long Vegetation mount (${suValue}) must render zero role="alert" banners`);
    assert.doesNotMatch(html, /Select at least one physical field before Build/);
    if (suValue === 'None') {
      assert.match(html, /Select an SU in Projects &amp; context/);
    }
  }

  // Verify onMount logic skips options() when SU=None and calls options() when SU=Sample.
  const lvSrc = readFileSync(srcPath('LongVegetationReport.svelte'), 'utf8');
  const mountSlice = lvSrc.slice(lvSrc.indexOf('  onMount(() => {'), lvSrc.indexOf('  onDestroy(() => {'));
  for (const [suValue, expectedCalls] of [['None', 0], ['Sample', 1]]) {
    let optionsCalls = 0;
    let mountedPromise;
    const context = vm.createContext({
      su: suValue,
      disposed: false,
      error: '',
      project: 'Sample',
      effectiveHierarchy: 'None',
      hierarchy: 'None',
      notifications,
      loadLumpTables: async () => {},
      options: async () => { optionsCalls++; },
      projectWorkspace: {
        selection: {
          load: () => {
            mountedPromise = Promise.resolve();
            return mountedPromise;
          },
        },
        view: () => ({ scope: { scope: { sourceKind: 'selected-list' } } }),
      },
      onMount(fn) { fn(); },
    });
    vm.runInContext(ts.transpileModule(mountSlice, { compilerOptions: { target: ts.ScriptTarget.ES2022 } }).outputText, context);
    await mountedPromise;
    assert.equal(optionsCalls, expectedCalls, `onMount with su=${suValue} must invoke options() ${expectedCalls} time(s)`);
  }
});
