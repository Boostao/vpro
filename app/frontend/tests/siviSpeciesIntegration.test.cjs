const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { compile } = require('svelte/compiler');
const { componentFunctions, readFS882Composite, srcPath } = require('./svelteTestHelpers.cjs');
const rawParent = readFileSync(srcPath('FS882Form.svelte'), 'utf8');
const parent = readFS882Composite();
const main = readFileSync(path.join(__dirname, '..', '..', 'main.go'), 'utf8') + '\n' +
  readFileSync(path.join(__dirname, '..', '..', 'domainservices_plotentry.go'), 'utf8');
const guards = ['busy', 'headerWorkflowBusy', 'siviUnsaved', 'siviCoverUnsaved', 'siviCombinedUnsaved',
  'siviCollectedUnsaved', 'siviIdentityUnsaved', 'heightUnsaved', 'otherUnsaved', 'soilUnsaved', 'attributeUnsaved',
  'collectedUnsaved', 'speciesUnsaved', 'siviParentWriteUnsaved', 'siviParentActionUnsaved',
  'siviProjectAssignmentUnsaved', 'siviParentSharedUnsaved'];
function host(overrides = {}) {
  return componentFunctions('FS882Form.svelte', [
    'siviSpeciesOperation', 'stageSIVISpecies', 'showSIVISpeciesPanel', 'load',
  ], {
    ...Object.fromEntries(guards.map(name => [name, false])), pictureMetadataPending: false, siviCreationPending: false,
    siviDeletionPending: false, siviRestorationPending: false, siviCreationUndoPending: false,
    siviSpeciesSession: null, siviSpeciesEnabled: true, siviSpeciesEditingDisabled: false,
    siviSpeciesUnsaved: false, siviSpeciesReading: false, siviSpeciesPanelOpen: false,
    siviSpeciesView: { review: [{}] }, error: null, successMsg: null,
    siviPanelOpen: true, siviCoverPanelOpen: true, siviCombinedPanelOpen: true, siviCollectedPanelOpen: true,
    siviParentSharedSession: null, siviProjectAssignmentSession: null, siviParentActionSession: null,
    siviParentWriteSession: null, siviParentSourceView: null, siviSession: null, siviCoverSession: null,
    siviCombinedSession: null, siviCollectedSession: null,
    siviIdentitySession: null, siviIdentityPanelOpen: false,
    AuditRestoreAction: { AuditRestoreRetain: 'retain', AuditRestorePrune: 'prune' },
    ...overrides,
  });
}
test('Species has unconditional actual main registration and coordinates both tracked source/reference reads', () => {
  assert.equal(compile(rawParent, { filename: 'FS882Form.svelte', generate: 'client' }).warnings.length, 0);
  assert.equal(compile(readFileSync(srcPath('FS882VegTab.svelte'), 'utf8'), { filename: 'FS882VegTab.svelte', generate: 'client' }).warnings.length, 0);
  assert.match(main, /NewSIVISpeciesService\((?:contextService|core)\)/);
  assert.match(main, /siviSpecies:\s*siviSpecies/);
  assert.match(main, /application\.NewService\((?:plotEntryService|wailsGraph\.plotEntry)\)/);
  for (const method of ['GetSIVISpeciesOriginal', 'GetSIVISpeciesReferences', 'SaveSIVISpeciesReviewed', 'RestoreSIVISpeciesReviewed']) {
    assert.ok(parent.includes(`PlotEntryService.${method}(`));
  }
  for (const method of ['GetSIVISpeciesOriginal', 'GetSIVISpeciesReferences']) {
    assert.match(parent, new RegExp(`speciesReads\\.track\\(PlotEntryService\\.${method}`));
  }
  assert.match(parent, /speciesReads[\s\S]*?r\.cancelAll\(\)/);
  assert.match(parent, /data-sivi-species-cancel-read[\s\S]{0,160}cancelSpeciesRead/);
  assert.match(parent, /\[[\s\S]*?heightSession,[\s\S]*?speciesSession[\s\S]*?\]\)\s*\{\s*s\?\.presentation\(/);
});
test('Species participates in root Save Undo Lock close and all peer/parent barriers', () => {
  assert.match(parent, /\[\(\) => speciesUnsaved,\s*\(\) => speciesOperation\('save'\)\]/);
  assert.match(parent, /\[\(\) => speciesUnsaved,\s*\(\) => void speciesOperation\('undo'\)\]/);
  assert.match(parent, /\bspeciesClose\b[\s\S]*?\.some\(\(c\)\s*=>\s*c\?\.blocked/);
  assert.match(parent, /siviSpeciesClose\?\.saveReason \?\? 'Correct or Undo unresolved SIVI Species drafts\.'/);
  assert.match(parent, /SIVI Species or unresolved acknowledgements must be saved or explicitly undone before changing the plot lock/);
});
test('actual Species root refuses every conflicting owner without invoking a backend operation', async () => {
  for (const guard of [...guards, 'siviSpeciesEditingDisabled']) {
    let calls = 0;
    const current = host({ [guard]: true, siviSpeciesSession: { save: async () => { calls++; return true; } } });
    assert.equal(await current.actions.siviSpeciesOperation('save'), false, guard);
    assert.equal(calls, 0);
    assert.match(current.error, /no conflicting drafts or operation/);
  }
  for (const operation of ['load', 'save', 'undo', 'retain', 'prune']) {
    let calls = 0;
    const action = async selected => {
      calls++;
      assert.equal(current.siviSpeciesReading, operation === 'load');
      if (operation === 'retain' || operation === 'prune') assert.equal(selected, operation);
      return true;
    };
    const current = host({ siviSpeciesSession: { load: action, save: action, undo: action, restore: action } });
    assert.equal(await current.actions.siviSpeciesOperation(operation), true);
    assert.equal(calls, 1);
    assert.equal(current.siviSpeciesReading, false);
  }
});
test('Species remount retains raw errors/context/decisions and guarded root commands surface failures', async () => {
  const calls = [];
  const owner = { stage: (...args) => calls.push(args), view: () => ({ error: 'retained invalid entry' }) };
  const current = host({ siviSpeciesSession: owner, siviSpeciesUnsaved: true, siviSpeciesView: { review: null } });
  for (const [command, raw] of [['Species', 'raw'], ['context', '2'], ['keep', ''], ['replace', 'TREE'], ['user', 'MINE']]) {
    current.actions.stageSIVISpecies('9007199254740993', command, raw);
  }
  assert.equal(calls.length, 5);
  assert.ok(calls.every(args => args[0] === '9007199254740993' && args[3] === false));
  assert.match(current.error, /SIVI Species retained invalid entry/);
  await current.actions.showSIVISpeciesPanel();
  assert.equal(current.siviSpeciesPanelOpen, true);
  assert.equal(current.siviPanelOpen || current.siviCoverPanelOpen || current.siviCombinedPanelOpen || current.siviCollectedPanelOpen, false);
  await current.actions.showSIVISpeciesPanel();
  assert.equal(current.siviSpeciesSession, owner);
  current.siviSpeciesEditingDisabled = true;
  current.actions.stageSIVISpecies('9007199254740993', 'Species', 'another');
  assert.equal(calls.length, 5);
  assert.match(current.error, /draft failed.*Unlock/);
});
test('busy/unknown Species owners cannot be replaced and late host receipts cannot overwrite a replacement', async () => {
  for (const state of [{ unsaved: true }, { busy: true }, { unsaved: true, blocked: true }]) {
    let disposed = 0;
    const owner = { closeState: () => state };
    const current = host({ siviSpeciesSession: owner, siviParentSession: { dispose: () => { disposed++; } } });
    await current.actions.load('another');
    assert.equal(current.siviSpeciesSession, owner);
    assert.equal(disposed, 0);
    assert.match(current.error, /before replacing their plot owner/);
  }
  let deliver;
  const current = host({ siviSpeciesSession: { load: () => new Promise(resolve => { deliver = resolve; }) } });
  const pending = current.actions.siviSpeciesOperation('load');
  current.siviSpeciesSession = {};
  current.error = 'replacement error';
  deliver(true);
  assert.equal(await pending, false);
  assert.equal(current.error, 'replacement error');
});
