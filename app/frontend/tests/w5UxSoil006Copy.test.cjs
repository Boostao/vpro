const assert = require('node:assert/strict');
const { test } = require('node:test');
const { loadTypeScript } = require('./svelteTestHelpers.cjs');

const grid = loadTypeScript('universalDatasheetGrid.ts', {
  '@wailsio/runtime': { Call: { ByName: () => Promise.resolve(null) } },
});
const children = loadTypeScript('fs882FormChildren.ts');

test('UX-SOIL-006: datasheet text rules distinguish character count vs astral UTF-16 symbol width', () => {
  const textureCol = { name: 'Texture', kind: 'text', maxUtf16: 4, editable: true, isBoolean: false };

  // 5 ASCII characters exceed the 4-character limit and report character count accurately.
  const fiveAscii = grid.parseAndValidateCellInput('Mineral', textureCol, '12345');
  assert.ok(fiveAscii.error);
  assert.match(fiveAscii.error, /Texture must be 4 characters or fewer \(entered 5 characters\)\./);

  // 4 Unicode characters including one astral symbol ('Si\u{1F600}L' = 4 chars, 5 UTF-16 units)
  // never falsely claim "exceeds 4 characters (got 5)".
  const astralFourChars = grid.parseAndValidateCellInput('Mineral', textureCol, 'Si\u{1F600}L');
  assert.ok(astralFourChars.error);
  assert.doesNotMatch(astralFourChars.error, /exceeds 4 characters \(got 5\)/);
  assert.match(astralFourChars.error, /4 characters, 5 UTF-16 units for symbols/);
});

test('UX-SOIL-006: child save error alerts strip RuntimeError prefixes, identity tuples, and dotted table prefixes', async () => {
  let capturedError = null;
  await children.saveChildDraftsImpl({
    disabled: false,
    guardMessage: 'blocked',
    hasUpdates: true,
    noChangeMessage: 'none',
    clearEmpty: () => {},
    commit: async () => {
      throw new Error(
        'RuntimeError: Humus identity ("00337", 1): upland organic horizon "L" requires UpperDepth > LowerDepth (got 0 to 5 cm); Humus.Comment exceeds 255 characters',
      );
    },
    clearOnCommit: () => {},
    plotNumber: '00337',
    loadChildData: async () => {},
    buildSuccessMessage: () => 'ok',
    committedRefreshPrefix: 'Saved; reload failed',
    failedPrefix: 'Failed to save soil changes',
    setBusy: () => {},
    setError: msg => {
      capturedError = msg;
    },
    setSuccess: () => {},
    invalidateCapabilities: () => {},
  });

  assert.ok(capturedError);
  assert.doesNotMatch(capturedError, /RuntimeError:/);
  assert.doesNotMatch(capturedError, /identity \("00337", 1\)/);
  assert.doesNotMatch(capturedError, /Humus\.Comment/);
  assert.match(capturedError, /Humus layer \(Plot 00337\): upland organic horizon "L"/);
  assert.match(capturedError, /Humus Comment exceeds 255 characters/);
});
