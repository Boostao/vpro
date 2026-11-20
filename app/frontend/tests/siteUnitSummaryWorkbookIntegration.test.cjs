const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { componentFunctions, loadTypeScript, srcPath } = require('./svelteTestHelpers.cjs');

function loadOperationGuardWithSummaryStubs(stubs, onEffect) {
  const noopSub = () => () => {};
  const noopSession = () => ({ view: () => ({ busy: false, blocked: false, closeBlocked: false }), held: () => false, subscribe: noopSub });
  return loadTypeScript(
    'shell/operationGuard.svelte.ts',
    {
      './externalSUEnvironment': { subscribeExternalSUEnvironmentActivity: noopSub },
      './twoPageSoilActivity': { subscribeTwoPageSoilActivity: noopSub },
      './twoPageVegetationActivity': { subscribeTwoPageVegetationActivity: noopSub },
      './tableCSVArchiveExport': { tableCSVArchivePublicationSession: noopSession },
      './pictureCreationActivity': { subscribePictureCreationActivity: noopSub },
      './pictureLifecycleActivity': { subscribePictureLifecycleActivity: noopSub },
      './lifeformWorkbook': { lifeformWorkbookPublicationSession: noopSession },
      './longVegetationProjectWorkspaces': { projectReportWorkspace: noopSession },
      './subzoneMatrixReport': { matrixPublicationSession: noopSession },
      './summaryVegetationEnvironmentalDesktop': { summaryEnvironmentalEnabled: false, summaryEnvironmentalDesktop: {} },
      './summaryVegetationFieldListDesktop': { summaryVegetationFieldListDesktop: { enabled: false } },
      './summaryVegetationPreferences': { summaryVegetationPreferenceSession: null },
      './summaryVegetationPresentationPreferences': { summaryVegetationPresentationPreferenceSession: null },
      './summaryVegetationQualityPreferences': { summaryVegetationQualityPreferenceSession: null },
      './summaryVegetationWorkbook': { summaryVegetationWorkbookSession: noopSession },
      './vegetationWorkbook': { vegetationWorkbookPublicationSession: noopSession },
      ...stubs,
    },
    {
      $effect: (run) => onEffect(run),
    }
  );
}

test('actual top-level Summary authority effect subscribes and reopens a retained receipt without the panel', () => {
  for (const blocked of [true, false]) {
    let subscribed = 0, unsubscribed = 0, owner, redirectedView = 'home';
    const cleanups = [];
    const mod = loadOperationGuardWithSummaryStubs(
      {
        './siteUnitSummaryWorkbook': {
          siteUnitSummaryWorkbookPublicationSession(value) {
            owner = value;
            return {
              view: () => ({ busy: !blocked, blocked }),
              subscribe(listener) {
                subscribed++;
                listener();
                return () => { unsubscribed++; };
              },
            };
          },
        },
        './siteUnitSummaryExtendedWorkbook': {
          extendedSummaryWorkbookPublicationSession() {
            return {
              view: () => ({ busy: false, blocked: false }),
              subscribe(listener) {
                listener();
                return () => {};
              },
            };
          },
        },
      },
      (run) => {
        const stop = run();
        if (typeof stop === 'function') cleanups.push(stop);
      }
    );
    const guard = mod.createOperationGuard();
    mod.bindShellActivitySubscriptions(
      guard,
      () => ({
        contextId: 'owned',
        activeProject: 'Sample',
        projectPath: 'C:\\Sample.db',
        activeSU: 'Summary',
        suPath: 'C:\\external.db',
      }),
      (target) => {
        if (redirectedView === 'home') redirectedView = target.view;
      }
    );
    assert.equal(subscribed, 1);
    assert.equal(guard.isBusy(), true);
    assert.equal(redirectedView, blocked ? 'summary-environment' : 'home');
    assert.equal(owner.contextId, 'owned');
    assert.equal(owner.suPath, 'C:\\external.db');
    for (const stop of cleanups) stop();
    assert.equal(unsubscribed, 1);
  }
});

test('actual Summary root guards refuse native close and context changes with an unmounted retained publication', async () => {
  let cancelled = 0, confirmed = 0, navigated = 0;
  const context = componentFunctions('App.svelte', ['handleCloseRequest', 'respondToClose', 'requestTransition'], {
    closeWorking: false, closeRequest: '', closeError: '', error: '', view: 'home', editor: undefined,
    busy: false, editorBusy: false, transitionWorking: false, archivePublicationBusy: false,
    vegetationPublicationBusy: false, lifeformPublicationBusy: false, summaryPublicationBusy: true,
    pendingTransition: null, transitionError: '', $projectState: { contextId: 'owned' },
    document: { activeElement: null }, HTMLElement: class {}, tick: async () => {},
    closeDisposition: (state, busy) => busy ? 'busy' : 'clean',
    LifecycleService: { GetPendingCloseRequest: async () => 'request',
      CancelClose: async () => { cancelled++; }, ConfirmClose: async () => { confirmed++; } },
  });
  await context.actions.handleCloseRequest('request');
  assert.equal(cancelled, 1); assert.equal(confirmed, 0);
  context.closeRequest = 'request';
  await context.actions.respondToClose('discard');
  assert.equal(confirmed, 0); assert.match(context.closeError, /Wait/);
  context.closeRequest = '';
  await context.actions.requestTransition(async () => { navigated++; });
  assert.equal(navigated, 0); assert.match(context.error, /Wait/);
  context.summaryPublicationBusy = false;
  await context.actions.requestTransition(async () => { navigated++; });
  assert.equal(navigated, 1);
});

test('actual Summary publication blocks background plot, hierarchy, state and profile reads', async () => {
  const baseState = {
    summaryPublicationBusy: true, lifeformPublicationBusy: false, vegetationPublicationBusy: false, pictureCreationBusy: false, pictureLifecycleBusy: false, twoPageSoilBusy: false,
    view: 'home', editorBusy: false, busy: false, transitionWorking: false, pendingTransition: null,
    closeRequest: '', request: 0, stateRequest: 0, hierarchyRequest: 0, plotFindEnabled: true,
    $projectState: { contextId: 'owned' }, profileSourceError: '', profileFileError: '', profileTableError: '',
  };
  const context = componentFunctions('App.svelte', ['loadPlots', 'refresh', 'loadHierarchy', 'findScopedPlot'], baseState);
  const profileContext = componentFunctions('PlotProfilePanel.svelte', ['inspectProfileSources',
    'reviewProfileSU', 'reviewProfileWriteOwnership', 'reviewBlankProfileFile', 'reviewBlankProfileTable'], baseState);
  for (const name of ['loadPlots', 'refresh', 'loadHierarchy', 'findScopedPlot']) {
    await context.actions[name](0);
  }
  for (const name of ['inspectProfileSources', 'reviewProfileWriteOwnership', 'reviewBlankProfileFile', 'reviewBlankProfileTable']) {
    await profileContext.actions[name](0);
  }
  await assert.rejects(profileContext.actions.reviewProfileSU({}, 'owned'), /Wait/);
  assert.equal(context.request, 0); assert.equal(context.stateRequest, 0); assert.equal(context.hierarchyRequest, 0);
  assert.equal(context.busy, false);
  assert.equal(profileContext.busy, false);
  for (const name of ['profileSourceError', 'profileFileError', 'profileTableError']) assert.match(profileContext[name], /Wait/);
});

test('actual Summary parent prevents method, preview and preference changes while publication is held', async () => {
  const held = [];
  const context = componentFunctions('SiteUnitSummary.svelte',
    ['reportBusy', 'cancel', 'options', 'show', 'loadPreferences', 'savePreferences', 'editMethod'], {
      workbookBusy: true, busy: false, preferenceBarrier: false, speciesBarrier: false, method: 1,
      generation: 0, onBusyChange: value => held.push(value),
      reads: { cancelAll() {} }, preferences: { cancelLoad() {} },
    });
  await context.actions.options(); await context.actions.show();
  await context.actions.loadPreferences(); await context.actions.savePreferences(); context.actions.editMethod(2);
  assert.equal(context.method, 1); assert.equal(context.generation, 0);
  context.actions.cancel();
  assert.equal(context.generation, 1); assert.deepEqual(held, [true]);
  context.workbookBusy = false; context.preferenceBarrier = true;
  context.actions.reportBusy();
  assert.deepEqual(held, [true, true]);
  context.preferenceBarrier = false;
  context.actions.reportBusy();
  assert.deepEqual(held, [true, true, false]);
});

test('Summary root and parent wire persistent publication authority', () => {
  const parent =
    readFileSync(srcPath('SiteUnitSummary.svelte'), 'utf8') +
    '\n' +
    readFileSync(srcPath('SiteUnitSummaryActionBar.svelte'), 'utf8');
  let redirected = '';
  const mod = loadOperationGuardWithSummaryStubs(
    {
      './siteUnitSummaryWorkbook': {
        siteUnitSummaryWorkbookPublicationSession: () => ({
          view: () => ({ busy: false, blocked: true }),
          subscribe: (fn) => { fn(); return () => {}; },
        }),
      },
      './siteUnitSummaryExtendedWorkbook': {
        extendedSummaryWorkbookPublicationSession: () => ({
          view: () => ({ busy: false, blocked: false }),
          subscribe: (fn) => { fn(); return () => {}; },
        }),
      },
    },
    (run) => run()
  );
  const guard = mod.createOperationGuard();
  mod.bindShellActivitySubscriptions(
    guard,
    () => ({ contextId: 'owned', activeProject: 'Sample', projectPath: '/Sample.db', activeSU: 'Summary', suPath: '/ext.db' }),
    (target) => { redirected = target.view; }
  );
  assert.equal(guard.isBusy(), true);
  assert.equal(redirected, 'summary-environment');
  assert.match(parent, /<SiteUnitSummaryWorkbookPanel[\s\S]*owner=\{\{ contextId, project, projectPath, su, suPath \}\}[\s\S]*\{method\}/);
  assert.match(parent, /onBusyChange=\{\(held\) => \{\s*workbookBusy = held;\s*reportBusy\(\);\s*\}\}/);
  for (const selector of ['undo', 'normal', 'acknowledge']) {
    assert.match(parent, new RegExp(`data-summary-preferences-${selector}[\\s\\S]*?disabled=\\{(?:model\\.)?workbookBusy`));
  }
});
