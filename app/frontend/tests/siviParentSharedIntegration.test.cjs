const { srcPath, readFS882Composite } = require('./svelteTestHelpers.cjs');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync } = require('node:fs');
const { compile } = require('svelte/compiler');
const rawParent = readFileSync(srcPath('FS882Form.svelte'), 'utf8');
const parent = readFS882Composite();
test('shared SIVI scope is independently gated and uses its owned facade rather than whole-header saves', () => {
  assert.equal(compile(rawParent, { filename: 'FS882Form.svelte', generate: 'client' }).warnings.length, 0);
  assert.equal(compile(readFileSync(srcPath('FS882Modals.svelte'), 'utf8'), { filename: 'FS882Modals.svelte', generate: 'client' }).warnings.length, 0);
  for (const method of ['GetSIVIParentSharedOriginal', 'SaveSIVIParentShared', 'RestoreSIVIParentShared']) assert.ok(parent.includes(`PlotEntryService.${method}(`));
  assert.match(parent, /parentSharedReads\.track/);
  assert.match(parent, /parentSharedReads\.cancelAll/);
});
test('shared SIVI state joins Save Undo Lock close ownership and sibling refresh without duplicate source fields', () => {
  assert.match(parent, /\[\(\) => parentSharedUnsaved,\s*\(\) => parentSharedOperation\('save'\)\]/);
  assert.match(parent, /\[\(\) => parentSharedUnsaved,\s*\(\) => void parentSharedOperation\('undo'\)\]/);
  assert.match(parent, /Undo shared SIVI drafts\/recovery before changing the plot lock/);
  assert.match(parent, /parentSharedSession\.closeState\(\)\.unsaved/);
  assert.match(parent, /\bparentSharedClose\b[\s\S]*?\.some\(\(c\)\s*=>\s*c\?\.blocked/);
  assert.match(parent, /liveColumns:\s*sivi\.parentSharedView\.original\s*\?\s*sivi\.sharedColumns\s*:\s*\[\]/);
  assert.match(parent, /unsaved:\s*sivi\.parentSharedUnsaved\s*\|\|\s*\(sivi\.parentSharedClose\?\.blocked\s*\?\?\s*false\)/);
  assert.match(parent, /refreshParent\(plot,\s*\[parentWriteSession,\s*parentActionSession,\s*projectAssignmentSession\]\)/);
  assert.match(parent, /siviParentSharedSession\?\.dispose\(\)/);
});
test('reference editing owned reads share cancellation and persistent session lifetime', () => {
  assert.match(parent, /readReferences:\s*\(?zone\)?\s*=>\s*parentSharedReads\.track\(PlotEntryService\.GetSIVIParentSharedReferences\(/);
  assert.match(parent, /cancelRead:\s*\(\)\s*=>\s*parentSharedReads\.cancelAll\(\)/);
  assert.match(parent, /siviParentSharedFieldsFor\(true\)\.map\(/);
  assert.match(parent, /onreferences=\{\(\) => \{\s*void sivi\.parentSharedSession\?\.refreshReferences\(\);\s*\}\}/);
});
