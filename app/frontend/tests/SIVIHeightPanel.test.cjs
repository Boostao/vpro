const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { render } = require('svelte/server');
const { serverComponent, srcPath } = require('./svelteTestHelpers.cjs');
const { review } = require('./siviSourceFixture.cjs');
const source = readFileSync(srcPath('SIVIHeightPanel.svelte'), 'utf8');
const Panel = serverComponent(source, 'SIVIHeightPanel.svelte', {
  '../bindings/github.com/boostao/vpro/app': {
    AuditRestoreAction: { AuditRestoreRetain: 'retain', AuditRestorePrune: 'prune' },
  },
  './projectMetadataEditor': { metadataCellText: cell =>
    cell.storage === 'text' ? cell.text : cell.storage === 'real' ? String(cell.real) :
      cell.storage === 'integer' ? cell.integer : cell.storage === 'blob' ? `hex:${cell.blobHex}` : '' },
  './siviHeightEditor': { siviHeightDirty: drafts => Object.keys(drafts).length > 0 },
});
function html(view = {}) {
  return render(Panel, { props: {
    view: { review: review(), drafts: {}, extended: false, busy: false, blocked: false, error: null, historyId: null, ...view },
    disabled: false, canSave: true, onstage() {}, onsave() {}, onundo() {}, onreload() {}, onrestore() {},
  } }).body;
}
test('SIVI responsive source panel has one visibly labelled control per height and read-only A/C/D context', () => {
  const markup = html();
  for (const [column, label] of [['HeightA', 'Ht A'], ['HeightB', 'Ht B'], ['Height6', 'Ht']]) {
    assert.equal((markup.match(new RegExp(`data-sivi-column="${column}"`, 'g')) || []).length, 1);
    assert.match(markup, new RegExp(`<label[^>]*for="sivi-9007199254740993-${column}"[^>]*>${label}`));
  }
  assert.match(markup, /Tree\/Shrubs/);
  assert.match(markup, /Moss\/Lichen/);
  assert.match(markup, /Dr\/Dw/);
  assert.match(markup, /NULL \(distinct from empty text\)/);
  assert.doesNotMatch(markup, /<dt[^>]*>B3</);
  assert.doesNotMatch(markup, /data-sivi-extended-guidance/);
  assert.doesNotMatch(markup, /data-sivi-column="(?:Species|Cover\d|Collected)"/);
  assert.match(source, /grid-cols-1 gap-3 sm:grid-cols-2/);
  assert.match(source, /w-full min-w-0/);
});
test('SIVI extended presentation exposes source B3/B4/B5 without resetting or hiding height errors', () => {
  const markup = html({ review: review({ extended: true }), extended: true,
    drafts: { '9007199254740993': { HeightB: { raw: 'bad literal', nullValue: false, error: 'overlength retained' } } } });
  for (const label of ['B3', 'B4', 'B5']) assert.match(markup, new RegExp(`<dt[^>]*>${label}</`));
  assert.match(markup, /data-sivi-group="SubVegA-SIVI"/);
  assert.match(markup, />bad literal<\/textarea>/);
  assert.match(markup, /aria-invalid="true"/);
  assert.match(markup, /overlength retained/);
  assert.match(markup, /aria-describedby="sivi-9007199254740993-HeightB-error"/);
  assert.match(markup, /aggregate height editing remains available/);
  assert.ok(markup.indexOf('data-sivi-extended-guidance') > markup.lastIndexOf('data-sivi-column='));
});
test('SIVI safety feedback stays above fields and ordinary guidance below all fields', () => {
  const markup = html({ blocked: true, error: 'Do not replay the committed operation.' });
  assert.ok(markup.indexOf('Do not replay the committed operation.') < markup.indexOf('data-sivi-row='));
  assert.ok(markup.indexOf('Numeric heights may be cleared') > markup.lastIndexOf('data-sivi-column='));
  assert.match(markup, /data-sivi-save[^>]*disabled/);
  assert.match(markup, /data-sivi-column="HeightA"[^>]*disabled/);
});
test('SIVI parent keeps the owner outside tabs and wires busy/dirty/safety gates before native acceptance', () => {
  const { createFS882TestController, readFS882Composite } = require('./svelteTestHelpers.cjs');
  const parent = readFS882Composite();
  const h = createFS882TestController();
  try {
    assert.equal(h.ctrl.headerWorkflowBusy, false);
    h.ctrl.twoPageOpen = true;
    h.flush();
    assert.equal(h.ctrl.otherHeaderWorkflowBusy, true);
    assert.equal(h.ctrl.headerWorkflowBusy, true);
  } finally {
    h.dispose();
  }
  assert.match(parent, /\[\(\) => heightUnsaved,\s*\(\) => heightOperation\('save'\)\]/);
  assert.match(parent, /\[\(\) => heightUnsaved,\s*\(\) => void heightOperation\('undo'\)\]/);
  assert.match(parent, /\[heightReads,[\s\S]*?r\.cancelAll\(\)/);
  assert.match(parent, /<SIVIHeightPanel[\s\S]*?<SourcePage/);
  assert.match(parent, /extendedShrubsNotice/);
  assert.match(parent, /Extended shrubs use cover mode/);
});
