const { srcPath } = require('./svelteTestHelpers.cjs');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const path = require('node:path');
const { compile } = require('svelte/compiler');

const app = readFileSync(srcPath('App.svelte'), 'utf8');
const navigation = readFileSync(srcPath('Navigation.svelte'), 'utf8');

test('standalone lifeform and summary vegetation previews are wired in navigation and app routes', () => {
  const { renderShellDeferredViews } = require('./svelteTestHelpers.cjs');
  assert.equal(compile(navigation, { filename: 'Navigation.svelte', generate: 'client' }).warnings.length, 0);
  assert.match(navigation, /name: '(Lifeform Summary|Lifeform (&|and) Species Attributes?)'.*view: 'lifeform-summary'/);
  assert.match(navigation, /name: 'Summary Vegetation', icon: ChartColumn, view: 'summary-vegetation'/);
  assert.equal(renderShellDeferredViews('lifeform-summary', null), '');
  assert.match(renderShellDeferredViews('lifeform-summary', { contextId: 'c1', activeProject: 'Sample', activeSU: 'S1' }), /Loading Lifeform Summary/);
});

test('lifeform preview borrows the owned context lifetime and reports busy state to navigation and native close', async () => {
  const { componentFunctions } = require('./svelteTestHelpers.cjs');
  const cancelled = [];
  const ctx = componentFunctions('App.svelte', ['handleCloseRequest', 'navigate'], {
    editorBusy: true,
    LifecycleService: { GetPendingCloseRequest: async () => 'req-1', CancelClose: async (id) => cancelled.push(id) },
  });
  await ctx.actions.handleCloseRequest('req-1');
  assert.deepEqual(cancelled, ['req-1']);
  await ctx.actions.navigate('home');
  assert.match(ctx.error, /Wait for the current operation/);
});
