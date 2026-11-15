const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readdirSync, readFileSync, statSync } = require('node:fs');
const path = require('node:path');
const { compile } = require('svelte/compiler');
const { srcPath } = require('./svelteTestHelpers.cjs');

const FRONTEND_ROOT = path.resolve(__dirname, '..');
const SRC_ROOT = path.join(FRONTEND_ROOT, 'src');
const OWNED_DIRS = ['entry', 'datasheet', 'admin', 'interchange', 'pictures'];

function walkOwnedFiles(dirs) {
  const out = [];
  for (const dir of dirs) {
    const absDir = path.join(SRC_ROOT, dir);
    const visit = current => {
      for (const entry of readdirSync(current)) {
        const full = path.join(current, entry);
        if (statSync(full).isDirectory()) visit(full);
        else if (full.endsWith('.svelte') || full.endsWith('.ts')) out.push(full);
      }
    };
    visit(absDir);
  }
  return out.sort();
}

test('Wave 3 theme invariant: zero Forest Green hexes, emerald/teal utilities, or emojis remain across entry, datasheet, admin, interchange, pictures', () => {
  const legacyGreenHex = /#(173f38|2c5b4a|d7ad51|b7cfc0|365c48|d1dcd4|176149|174f38|268453|e9efeb|e6f0e8|d2e4d7|dbe8dd|eaf0e9|f0f6ee|e4eee9|526e62|456050|20322d|bd9b48|b7493c|0f766e|ccfbf1|065f46|047857|ecfdf5|d1fae5|a7f3d0|6ee7b7|34d399|10b981|059669|064e3b)\b/i;
  const legacyGreenUtil = /\b(?:bg|text|border|ring|outline)-(?:emerald|teal|green)-\d{2,3}\b/i;
  const emojiRe = /\p{Extended_Pictographic}/u;

  const files = walkOwnedFiles(OWNED_DIRS);
  assert.ok(files.length >= 60, `Expected >= 60 owned source files, saw ${files.length}`);
  for (const file of files) {
    const rel = path.relative(FRONTEND_ROOT, file);
    const text = readFileSync(file, 'utf8');
    assert.equal(legacyGreenHex.test(text), false, `${rel} contains legacy forest-green/emerald hex`);
    assert.equal(legacyGreenUtil.test(text), false, `${rel} contains legacy emerald/teal/green utility class`);
    assert.equal(emojiRe.test(text), false, `${rel} contains raw emoji character`);
    if (file.endsWith('.svelte')) {
      const compiled = compile(text, { filename: file, generate: 'client' });
      assert.equal(compiled.warnings.length, 0, `${rel} emitted Svelte warnings: ${JSON.stringify(compiled.warnings)}`);
    }
  }
});

test('Wave 3 Guided Tour data-tour roots exist on outermost containers in all four root workbenches', () => {
  const expectedTours = [
    ['admin/ProjectAdminWorkbench.svelte', 'project-admin-root'],
    ['interchange/InterchangeHub.svelte', 'interchange-hub-root'],
    ['entry/FS882Form.svelte', 'fs882-form-root'],
    ['datasheet/UniversalDatasheetGrid.svelte', 'datasheet-grid-root'],
  ];
  for (const [rel, tourId] of expectedTours) {
    const src = readFileSync(path.join(SRC_ROOT, rel), 'utf8');
    assert.ok(src.includes(`data-tour="${tourId}"`), `${rel} must define data-tour="${tourId}"`);
  }
});

test('S1.1 / S1.4 / S1.6 / S1.7 / S1.10 / S4.3 FS882Form & HeaderEditor parity', () => {
  const fs882 = readFileSync(srcPath('FS882Form.svelte'), 'utf8');
  const header = readFileSync(srcPath('HeaderEditor.svelte'), 'utf8');
  const shared = readFileSync(srcPath('SIVIParentSharedFields.svelte'), 'utf8');
  const createTs = readFileSync(srcPath('siviParentCreate.ts'), 'utf8');

  // S1.1 & S4.3 props and exported methods
  assert.match(fs882, /entryForm\?:\s*'fs882'\s*\|\s*'sivi'\s*\|\s*'fs882-twopage'/);
  assert.match(fs882, /autoOpenedTwoPageKey/);
  assert.match(fs882, /onOpenPictureManager\?:\s*\(plotNumber:\s*string\)\s*=>\s*void/);
  assert.match(fs882, /onDiagnosticsContextChange\?:/);
  assert.match(fs882, /export function applyDiagnosticHumusThickness\(/);
  assert.match(fs882, /export function applyDiagnosticSMR\(/);
  assert.match(fs882, /export function applyDiagnosticSNR\(/);

  // S1.4 picture manager, ProjectID datalist, right-click SU copy, FS882StratumSummary retained
  assert.match(header, /control\.controlName === 'btnManagePictures' && onOpenPictureManager/);
  assert.match(header, /attachSuContextMenu/);
  assert.match(header, /header-projectId-options/);
  assert.doesNotMatch(header, /Deferred Phase 2/);

  // S1.6 accurate CHARS cover-only copy
  assert.match(fs882, /Cover5a–Cover5c only; Height5a–Height5c height fields are disabled/);
  assert.match(shared, /Cover5a–Cover5c only; height fields remain disabled/);

  // S1.7 FS882 allowed in SIVI create & uncoupled Arctic state
  assert.match(createTs, /'FS882'/);
  assert.match(fs882, /nonArcticHeaderDirty/);
});

test('S1.2 / S1.8 / S1.12 / S4.4 TwoPage CRUD, Enter navigation, Coordinate helper, and SpeciesCodeCheck suggestions', () => {
  const twoPage = readFileSync(srcPath('TwoPageEntryEditor.svelte'), 'utf8');
  const vegPanel = readFileSync(srcPath('TwoPageVegetationPanel.svelte'), 'utf8');
  const auditPanel = readFileSync(srcPath('TwoPageAuditPanel.svelte'), 'utf8');
  const metaPanel = readFileSync(srcPath('TwoPageProjectMetadataPanel.svelte'), 'utf8');
  const enterNav = readFileSync(srcPath('enterNavigation.ts'), 'utf8');
  const codeCheck = readFileSync(srcPath('SpeciesCodeCheck.svelte'), 'utf8');

  for (const method of ['CreateTwoPageVegetationRow', 'DeleteTwoPageVegetationRow', 'RestoreTwoPageVegetationRow', 'ListTwoPageVegetationDeletedRows']) {
    assert.ok(vegPanel.includes(method), `TwoPageVegetationPanel must wire ${method}`);
  }
  assert.ok(auditPanel.includes('SetTwoPageSourceAuditRestoreSelection'));
  assert.ok(auditPanel.includes('RestoreSelectedTwoPageSourceAudit'));
  assert.ok(metaPanel.includes('onEditMetadata'));
  assert.ok(twoPage.includes('onOpenProfileSU'));
  assert.ok(twoPage.includes('ConvertCoordinate'));

  for (const form of ['SubVegAhtXL', 'SubVegChtXL', 'SubOtherXL', 'SubOther']) {
    assert.ok(enterNav.includes(`'${form}'`), `enterNavigation.ts must include ${form}`);
  }
  assert.ok(codeCheck.includes('applySuggested'));
  assert.ok(codeCheck.includes('row.suggestedCode'));
});

test('S2.1 / S2.7 / S2.8 / S2.9 UniversalDatasheetGrid parity', () => {
  const dsTs = readFileSync(srcPath('universalDatasheetGrid.ts'), 'utf8');
  const dsSvelte = readFileSync(srcPath('UniversalDatasheetGrid.svelte'), 'utf8');
  assert.match(dsTs, /col\.protected/);
  assert.match(dsTs, /DatasheetService\.ListDatasheetAllTables/);
  assert.match(dsTs, /DatasheetService\.InsertDatasheetChildRow/);
  assert.match(dsTs, /DatasheetService\.DeleteDatasheetChildRow/);
  assert.match(dsTs, /ArrowUp/);
  assert.match(dsSvelte, /event\.shiftKey/);
});

test('S2.2 / S2.6 / S2.11 / S2.14 / S2.15 / S2.17 / S2.18 / S4.1 / S6.7 ProjectAdmin & CloudSync parity', () => {
  const admin = readFileSync(srcPath('ProjectAdminWorkbench.svelte'), 'utf8');
  const cloudTs = readFileSync(srcPath('cloudSyncWorkbench.ts'), 'utf8');
  const cloudSvelte = readFileSync(srcPath('CloudSyncWorkbench.svelte'), 'utf8');
  assert.match(admin, /mergePlotResolutions/);
  assert.match(admin, /optPreview\.conflicts/);
  assert.match(admin, /complianceReport\.envAdminFindings/);
  assert.match(admin, /complianceReport\.orphanFindings/);
  assert.match(admin, /complianceReport\.taxonomyFindings/);
  assert.match(cloudTs, /VerifyBECMasterAuditChain/);
  assert.match(cloudSvelte, /Verify Audit Chain/);
});

test('S4.8 / S4.9 / S4.10 InterchangeHub & PlotLabelPreview parity', () => {
  const hub = readFileSync(srcPath('InterchangeHub.svelte'), 'utf8');
  const labelPreview = readFileSync(srcPath('plotLabelPreview.ts'), 'utf8');
  assert.match(hub, /resolveVProCodeSynonyms:\s*tvResolveSynonyms/);
  assert.match(hub, /\[45\.\.85 N,\s*-170\.\.-100 W\]/);
  assert.match(labelPreview, /const zone = labelText\(value\.zone, 'Zone', 4\) \?\? ''/);
});
