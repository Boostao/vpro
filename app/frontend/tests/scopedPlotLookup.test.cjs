const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { loadTypeScript, srcPath } = require('./svelteTestHelpers.cjs');
const quality = loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });
const find = loadTypeScript('scopedPlotLookup.ts', { './qualityEditor': quality });
const result = (plotNumber = " A' # ") => ({ contextId: 'owned', plot: {
  plotNumber, fieldNumber: null, plotRepresenting: null, zone: null, subZone: null, siteSeries: null
}});

test('Find preserves exact spaces, quotes, case, Unicode and historical long identifiers', () => {
  for (const number of [" A' # ", '108050x', 'É😀', 'historical long plot identifier']) {
    assert.equal(find.plotLookupInputError(number), null);
    assert.equal(find.validateScopedPlotLookup(result(number), number, 'owned').plot.plotNumber, number);
  }
  for (const number of ['', '\ud800', '\udc00', '\0']) assert.notEqual(find.plotLookupInputError(number), null);
});

test('Find rejects incomplete, normalized or foreign responses rather than opening another record', () => {
  for (const alter of [value => value.contextId = 'stale', value => value.plot.plotNumber = "A' #",
    value => value.plot = null, value => delete value.plot.fieldNumber, value => value.plot.zone = 5]) {
    const invalid = result(); alter(invalid);
    assert.throws(() => find.validateScopedPlotLookup(invalid, " A' # ", 'owned'));
  }
});

test('Read-only Find and explicit Open retain SU/profile scope, immutable identity and shared transition ownership', () => {
  const { readShellComposite, readFS882Composite } = require('./svelteTestHelpers.cjs');
  const app = readShellComposite();
  const form = readFS882Composite();
  assert.match(app, /aria-label="Find scoped plot"/);
  assert.match(app, /<label for="find-scoped-plot"/);
  assert.match(form, /\{#if onFindPlot\}/);
  assert.match(form, /\{onFindPlot\}[\s\S]{0,120}findPlotDisabled=\{(?:ctrl\.)?busy \|\| (?:ctrl\.)?headerWorkflowBusy \|\| !(?:ctrl\.)?capabilitiesReady\}/);
  for (const [label, fnHeader] of [
    ['lookupScopedPlotOp', 'export async function lookupScopedPlotOp'],
    ['runFindScopedPlotOp', 'export async function runFindScopedPlotOp'],
    ['openFoundPlot', 'async function openFoundPlot'],
  ]) {
    const start = app.indexOf(fnHeader);
    assert.ok(start >= 0, label);
    const action = app.slice(start, start + 1500);
    assert.doesNotMatch(action, /SwitchContext|profileNavigation = null|CreatePlot|\.trim\(|\.toUpperCase\(/);
    if (label === 'lookupScopedPlotOp') {
      assert.match(
        action,
        /ResolveProjectPlotProfileNavigation\(contextId,\s*profileNavigation\.proposal\)[\s\S]*?validateProfileNavigation\(rawNav,\s*profileNavigation\.proposal,\s*contextId\)/
      );
      assert.match(action, /next\.plots\.some/);
      assert.match(action, /LookupScopedPlot/);
    }
    if (label === 'runFindScopedPlotOp') assert.doesNotMatch(action, /requestTransition|editorPlotNumber:/);
    if (label === 'openFoundPlot') {
      assert.match(action, /\$state\.snapshot\(plotFindResult\)/);
      assert.match(action, /proposal\.plot\.plotNumber === snap\.editorPlotNumber/);
      assert.match(action, /await bridge\.requestTransition/);
      assert.match(action, /await lookupScopedPlotOp\(\{\s*number:\s*proposal\.plot\.plotNumber/);
      assert.match(action, /JSON\.stringify\(current\) !== JSON\.stringify\(proposal\)/);
    }
  }
});
