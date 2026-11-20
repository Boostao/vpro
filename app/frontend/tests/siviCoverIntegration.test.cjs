const { srcPath, loadTypeScript, componentFunctions, readFS882Composite } = require('./svelteTestHelpers.cjs');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync } = require('node:fs');
const { compile } = require('svelte/compiler');

const rawParent = readFileSync(srcPath('FS882Form.svelte'), 'utf8');
const parent = readFS882Composite();

function host(overrides = {}) {
  const names = ['siviCoverOperation', 'stageSIVICoverCell', 'showSIVICoverPanel', 'refreshSIVIChildEditors',
    'siviCombinedOperation', 'stageSIVICombinedCell', 'showSIVICombinedPanel', 'load'];
  const context = componentFunctions('FS882Form.svelte', names, {
    error: null, successMsg: null, siviCoverEnabled: true, busy: false, headerWorkflowBusy: false, pictureMetadataPending: false, siviCreationPending: false,
    siviDeletionPending: false, siviRestorationPending: false, siviCreationUndoPending: false,
    siviUnsaved: false, heightUnsaved: false, otherUnsaved: false, soilUnsaved: false,
    attributeUnsaved: false, collectedUnsaved: false, speciesUnsaved: false,
    siviParentWriteUnsaved: false, siviParentActionUnsaved: false,
    siviProjectAssignmentUnsaved: false, siviParentSharedUnsaved: false,
    siviCoverEditingDisabled: false, siviCoverReading: false, siviCoverUnsaved: false,
    siviCoverPanelOpen: false, siviPanelOpen: true, siviCoverView: { review: [{}] },
    siviCoverSession: null, siviSession: null,
    siviCombinedSession: null, siviCombinedEnabled: true, siviCombinedUnsaved: false,
    siviCombinedEditingDisabled: false, siviCombinedPanelOpen: false, siviCombinedReading: false,
    siviCombinedView: { review: [{}] },
    siviCollectedSession: null, siviCollectedUnsaved: false, siviCollectedPanelOpen: false,
    siviSpeciesSession: null, siviSpeciesUnsaved: false, siviSpeciesPanelOpen: false,
    siviIdentitySession: null, siviIdentityUnsaved: false, siviIdentityPanelOpen: false,
    siviParentSharedSession: null, siviProjectAssignmentSession: null, siviParentActionSession: null,
    siviParentWriteSession: null, siviParentSourceView: null, siviParentSession: null,
    AuditRestoreAction: { AuditRestoreRetain: 'retain', AuditRestorePrune: 'prune' },
    ...loadTypeScript('fs882FormHelpers.ts'),
    loadChildData: async () => {},
    ...overrides,
  });
  context.api = context.actions;
  return context;
}

test('cover facade and source panel are independently gated without widening height saves', () => {
  assert.equal(compile(rawParent, { filename: 'FS882Form.svelte', generate: 'client' }).warnings.length, 0);
  assert.equal(compile(readFileSync(srcPath('FS882VegTab.svelte'), 'utf8'), { filename: 'FS882VegTab.svelte', generate: 'client' }).warnings.length, 0);
  for (const method of ['GetSIVICoverOriginal', 'SaveSIVICoverReviewed', 'RestoreSIVICoverReviewed']) {
    assert.ok(parent.includes(`PlotEntryService.${method}(`));
  }
  assert.match(parent, /coverReads\.track\(PlotEntryService\.GetSIVICoverOriginal/);
  assert.match(parent, /coverReads[\s\S]*?r\.cancelAll\(\)/);
  assert.match(parent, /data-sivi-cover-cancel-read[\s\S]{0,160}cancelCoverRead/);
  assert.match(parent, /coverSession = new SIVICoverSession/);
});

test('source notice flag is forwarded to all owned child writers without granting backend authority', () => {
  for (const Writer of ['Height', 'Cover', 'Combined', 'Collected']) {
    assert.match(parent, new RegExp(`new SIVI${Writer}Session\\([\\s\\S]*?extendedShrubs,\\s*true\\s*\\)`));
  }
});

test('cover owner contributes dirty busy blocked Save Undo Lock and peer-editor barriers', () => {
  assert.match(parent, /\[\(\) => coverUnsaved,\s*\(\) => coverOperation\('save'\)\]/);
  assert.match(parent, /\[\(\) => coverUnsaved,\s*\(\) => void coverOperation\('undo'\)\]/);
  assert.match(parent, /\bcoverClose\b[\s\S]*?\.some\(\(c\)\s*=>\s*c\?\.blocked/);
  assert.match(parent, /coverSession\.closeState\(\)\.unsaved \|\| coverSession\.closeState\(\)\.busy/);
  assert.match(parent, /SIVI covers or unresolved acknowledgements must be saved or explicitly undone before changing the plot lock/);
});

test('cover operations reject every peer draft and never invoke mutation during another operation', async () => {
  for (const guard of ['busy', 'headerWorkflowBusy', 'siviUnsaved', 'siviCombinedUnsaved', 'siviCollectedUnsaved', 'heightUnsaved', 'otherUnsaved',
    'soilUnsaved', 'attributeUnsaved', 'collectedUnsaved', 'speciesUnsaved', 'siviParentWriteUnsaved',
    'siviParentActionUnsaved', 'siviProjectAssignmentUnsaved', 'siviParentSharedUnsaved']) {
    let calls = 0;
    const context = host({ [guard]: true, siviCoverSession: { save: async () => { calls++; return true; } } });
    assert.equal(await context.api.siviCoverOperation('save'), false, guard);
    assert.equal(calls, 0, guard);
    assert.match(context.error, /no conflicting drafts or operation/);
  }
});

test('cover read cancellation state exists only for loading, never for mutation or restoration', async () => {
  for (const operation of ['load', 'save', 'undo', 'retain', 'prune']) {
    let reading;
    let action;
    const session = {
      load: async () => { reading = context.siviCoverReading; return true; },
      save: async () => { reading = context.siviCoverReading; return true; },
      undo: async () => { reading = context.siviCoverReading; return true; },
      restore: async selected => { reading = context.siviCoverReading; action = selected; return true; },
    };
    const context = host({ siviCoverSession: session });
    assert.equal(await context.api.siviCoverOperation(operation), true);
    assert.equal(reading, operation === 'load');
    assert.equal(context.siviCoverReading, false);
    if (operation === 'retain' || operation === 'prune') assert.equal(action, operation);
  }
});

test('invalid cover drafts remain correctable while blocked authority uses explicit Undo recovery', async () => {
  let staged = 0;
  let undone = 0;
  const context = host({
    siviCoverSession: {
      stage: () => { staged++; },
      view: () => ({ error: 'less than 100' }),
      undo: async () => { undone++; return true; },
    },
  });
  context.api.stageSIVICoverCell('1', 'Cover1', '100', false);
  assert.equal(staged, 1);
  assert.match(context.error, /SIVI cover less than 100/);
  context.siviCoverEditingDisabled = true;
  context.api.stageSIVICoverCell('1', 'Cover1', '99', false);
  assert.equal(staged, 1);
  assert.equal(await context.api.siviCoverOperation('undo'), true);
  assert.equal(undone, 1);
});

test('panel switches do not replace or reload the retained cover draft owner', async () => {
  let loads = 0;
  const context = host({
    siviCoverUnsaved: true, siviCoverView: { review: null }, siviCoverEditingDisabled: true,
    siviCoverSession: { load: async () => { loads++; return true; } },
  });
  const owner = context.siviCoverSession;
  await context.api.showSIVICoverPanel();
  assert.equal(context.siviCoverPanelOpen, true);
  assert.equal(context.siviPanelOpen, false);
  await context.api.showSIVICoverPanel();
  assert.equal(context.siviCoverPanelOpen, false);
  assert.equal(context.siviCoverSession, owner);
  assert.equal(loads, 0);
});

test('acknowledged child changes refresh only an already-loaded peer and preserve its session', async () => {
  for (const owner of ['height', 'cover']) {
    const calls = [];
    const peer = { view: () => ({ review: [{}] }), closeState: () => ({ unsaved: false, busy: false }),
      refreshSource: async () => { calls.push('peer'); return true; } };
    const context = host({
      loadChildData: async plot => { calls.push(plot); },
      siviCoverSession: owner === 'height' ? peer : null,
      siviSession: owner === 'cover' ? peer : null,
    });
    await context.api.refreshSIVIChildEditors('P', owner);
    assert.deepEqual(calls, ['P', 'peer']);
    assert.equal(owner === 'height' ? context.siviCoverSession : context.siviSession, peer);
    peer.view = () => ({ review: null });
    calls.length = 0;
    await context.api.refreshSIVIChildEditors('P', owner);
    assert.deepEqual(calls, ['P']);
    peer.view = () => ({ review: [{}] });
    peer.refreshSource = async () => false;
    await assert.rejects(context.api.refreshSIVIChildEditors('P', owner), /failed to refresh/);
  }
});

    test('combined facade is wired through Save Undo Lock close and disposal', () => {
      for (const method of ['GetSIVICombinedOriginal', 'SaveSIVICombinedReviewed', 'RestoreSIVICombinedReviewed']) assert.ok(parent.includes(`PlotEntryService.${method}(`));
      assert.match(parent, /combinedReads[\s\S]*?r\.cancelAll\(\)/);
      assert.match(parent, /\[\(\) => combinedUnsaved,\s*\(\) => combinedOperation\('save'\)\]/);
      assert.match(parent, /\[\(\) => combinedUnsaved,\s*\(\) => void combinedOperation\('undo'\)\]/);
      assert.match(parent, /\bcombinedClose\b[\s\S]*?\.some\(\(c\)\s*=>\s*c\?\.blocked/);
      assert.match(parent, /Combined SIVI drafts or unresolved acknowledgements must be saved or explicitly undone before changing the plot lock/);
    });

    test('combined actions reject conflicting owners including recovery; read cancellation never advertises a mutation', async () => {
      for (const guard of ['busy', 'headerWorkflowBusy', 'siviUnsaved', 'siviCoverUnsaved', 'siviCollectedUnsaved', 'heightUnsaved',
        'otherUnsaved', 'soilUnsaved', 'attributeUnsaved', 'collectedUnsaved', 'speciesUnsaved',
        'siviParentWriteUnsaved', 'siviParentActionUnsaved', 'siviProjectAssignmentUnsaved', 'siviParentSharedUnsaved']) {
        let calls = 0;
        const context = host({ [guard]: true, siviCombinedSession: { save: async () => { calls++; return true; } } });
        assert.equal(await context.api.siviCombinedOperation('save'), false, guard);
        assert.equal(calls, 0, guard);
        assert.match(context.error, /no conflicting drafts or operation/);
      }
      for (const operation of ['load', 'save', 'undo', 'retain', 'prune']) {
        let context;
        const action = async () => {
          assert.equal(context.siviCombinedReading, operation === 'load');
          return true;
        };
        context = host({ siviCombinedSession: { load: action, save: action, undo: action, restore: action } });
        assert.equal(await context.api.siviCombinedOperation(operation), true);
        assert.equal(context.siviCombinedReading, false);
      }
    });

    test('combined peer refresh preflights every owner before resetting any original or parent projection', async () => {
      for (const field of ['unsaved', 'busy']) {
        let calls = 0;
        const clean = { closeState: () => ({ unsaved: false, busy: false }), view: () => ({ review: [{}] }),
          refreshSource: async () => { calls++; return true; } };
        const blocked = { ...clean, closeState: () => ({ [field]: true }) };
        const context = host({ siviSession: clean, siviCoverSession: blocked, loadChildData: async () => { calls++; } });
        await assert.rejects(context.api.refreshSIVIChildEditors('P', 'combined'), /no peer originals were reset/);
        assert.equal(calls, 0);
      }
      const calls = [];
      const peer = name => ({ closeState: () => ({ unsaved: false, busy: false }), view: () => ({ review: [{}] }),
        refreshSource: async () => { calls.push(name); return true; } });
      const context = host({ siviSession: peer('height'), siviCoverSession: peer('cover'),
        siviCombinedSession: peer('owner'), loadChildData: async plot => { calls.push(plot); } });
      await context.api.refreshSIVIChildEditors('P', 'combined');
      assert.deepEqual(calls, ['P', 'height', 'cover']);
    });

    test('combined panel remount preserves drafts and late host receipts cannot overwrite a replacement owner', async () => {
      const context = host({ siviCombinedUnsaved: true, siviCombinedEditingDisabled: true });
      await context.api.showSIVICombinedPanel();
      assert.equal(context.siviCombinedPanelOpen, true);
      assert.equal(context.siviPanelOpen, false);
      assert.equal(context.siviCoverPanelOpen, false);
      await context.api.showSIVICombinedPanel();
      assert.equal(context.siviCombinedPanelOpen, false);
      let resolve;
      context.siviCombinedUnsaved = false;
      context.siviCombinedEditingDisabled = false;
      context.siviCombinedSession = { load: () => new Promise(done => { resolve = done; }) };
      const loading = context.api.siviCombinedOperation('load');
      context.siviCombinedSession = {};
      context.error = 'replacement owner error';
      context.successMsg = 'replacement status';
      context.siviCombinedReading = true;
      resolve(true);
      assert.equal(await loading, false);
      assert.equal(context.error, 'replacement owner error');
      assert.equal(context.successMsg, 'replacement status');
      assert.equal(context.siviCombinedReading, true);
    });

    test('plot-triggered load cannot replace a combined owner with drafts, recovery state or an operation', async () => {
      for (const state of [{ unsaved: true, busy: false }, { unsaved: false, busy: true },
        { unsaved: true, busy: true, blocked: true }]) {
        let disposed = 0;
        const owner = { closeState: () => state, dispose: () => { disposed++; } };
        const context = host({ siviCombinedSession: owner, siviParentSession: { dispose: () => { disposed++; } } });
        await context.api.load('replacement plot');
        assert.equal(context.siviCombinedSession, owner);
        assert.equal(disposed, 0);
        assert.match(context.error, /Combined SIVI drafts or operations.*before replacing their plot owner/);
      }
    });
