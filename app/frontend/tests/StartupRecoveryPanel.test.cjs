const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const vm = require('node:vm');
const ts = require('typescript');
const { compile } = require('svelte/compiler');
const { render } = require('svelte/server');
const { serverComponent, srcPath } = require('./svelteTestHelpers.cjs');

const source = readFileSync(srcPath('StartupRecoveryPanel.svelte'), 'utf8');
const moduleBlock = source.match(/<script lang="ts" module>([\s\S]*?)<\/script>/)[1];
const moduleExports = {};
vm.runInNewContext(
  ts.transpileModule(moduleBlock, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  }).outputText,
  { exports: moduleExports }
);

const {
  hasConfiguredContextSelection,
  formatStartupError,
  isDatabasePathMissing,
  deriveInitialRecoveryDraft,
} = moduleExports;

function makeFailure(overrides = {}) {
  return {
    ready: false,
    message: 'Current.CoordMethod must be an integer from 1 to 3',
    configPath: '/tmp/vpro/config/config.yml',
    releaseChannel: 'stable',
    appVersion: '2.0.0-dev',
    buildMode: 'dev',
    gitCommit: '35e8e7cb',
    buildDate: '2026-11-19',
    isPrerelease: true,
    unsignedNotice: false,
    backupPath: '',
    configuredProject: 'Sample',
    projectPath: '/tmp/vpro/data/projects/Sample.db',
    configuredSu: 'None',
    suPath: '',
    configuredHierarchy: 'Sample',
    hierarchyPath: '/tmp/vpro/data/projects/Sample.db',
    ...overrides,
  };
}

test('StartupRecoveryPanel compiles cleanly with zero warnings, zero emojis, and plain-language labels', () => {
  assert.doesNotMatch(source, /[\u{1F300}-\u{1FAFF}]/u, 'must contain zero emojis');
  const compiled = compile(source, { filename: 'StartupRecoveryPanel.svelte', generate: 'client' });
  assert.deepEqual(compiled.warnings, []);
});

test('formatStartupError strips RuntimeError prefixes and translates raw YAML keys into plain language', () => {
  assert.equal(
    formatStartupError(
      'RuntimeError: validate recovered configuration: Current.CoordMethod must be an integer from 1 to 3'
    ),
    'Saved Coordinate display format setting could not be read (expected Decimal Degrees, Degrees-Minutes, or Degrees-Minutes-Seconds).'
  );
  assert.equal(
    formatStartupError(
      'legacy JSON conflicts with explicit YAML Current.CurrHierarchy; both files were retained'
    ),
    'An older VPro selection file conflicts with your saved Active Hierarchy setting. Both files were kept unchanged.'
  );
  const supportErr = formatStartupError(
    'RuntimeError: configured context could not be opened; YAML was retained: attach VUser: file is not a database'
  );
  assert.doesNotMatch(supportErr, /RuntimeError:|YAML/);
  assert.match(supportErr, /attach VUser: file is not a database/);
});

test('deriveInitialRecoveryDraft never pre-checks reset for None or valid existing Sample.db paths', () => {
  assert.equal(hasConfiguredContextSelection('None'), false);
  assert.equal(hasConfiguredContextSelection(''), false);
  assert.equal(hasConfiguredContextSelection('Sample'), true);

  const realStateDraft = deriveInitialRecoveryDraft(makeFailure());
  assert.equal(realStateDraft.clearSu, false);
  assert.equal(realStateDraft.clearHierarchy, false);
  assert.equal(realStateDraft.hasMissingDatabase, false);
  assert.equal(realStateDraft.projectPath, '/tmp/vpro/data/projects/Sample.db');
  assert.equal(realStateDraft.hierarchyPath, '/tmp/vpro/data/projects/Sample.db');
  assert.doesNotMatch(realStateDraft.formattedMessage, /Current\.CoordMethod|RuntimeError/);

  // Managed empty suPath / hierarchyPath without missing-file error must NOT pre-check reset
  const managedPathsDraft = deriveInitialRecoveryDraft(
    makeFailure({
      configuredSu: 'Sample',
      suPath: '',
      configuredHierarchy: 'Sample',
      hierarchyPath: '',
      message: 'Saved Audit tracking level setting could not be read.',
    })
  );
  assert.equal(managedPathsDraft.clearSu, false);
  assert.equal(managedPathsDraft.clearHierarchy, false);
  assert.equal(managedPathsDraft.hasMissingDatabase, false);
});

test('deriveInitialRecoveryDraft pre-checks reset only when SU or Hierarchy paths are reported missing', () => {
  const missingBoth = deriveInitialRecoveryDraft(
    makeFailure({
      configuredProject: 'Field2026',
      projectPath: '/gone/usb/Field2026.db',
      configuredSu: 'Field2026_SU',
      suPath: '/gone/usb/MissingSU.db',
      configuredHierarchy: 'Field2026_Hier',
      hierarchyPath: '/gone/usb/MissingHier.db',
      message:
        'Configured project database was not found at /gone/usb/Field2026.db. ' +
        'Configured Site Unit database was not found at /gone/usb/MissingSU.db. ' +
        'Configured Hierarchy database was not found at /gone/usb/MissingHier.db.',
    })
  );
  assert.equal(missingBoth.clearSu, true);
  assert.equal(missingBoth.clearHierarchy, true);
  assert.equal(missingBoth.hasMissingDatabase, true);
  assert.equal(isDatabasePathMissing(makeFailure({ configuredSu: 'None', suPath: '' }), 'su'), false);

  // Missing project DB, None SU, valid local Hierarchy DB -> only project is missing
  const missingProjectOnly = deriveInitialRecoveryDraft(
    makeFailure({
      projectPath: '/gone/usb/Field2026.db',
      configuredSu: 'None',
      suPath: '',
      configuredHierarchy: 'LocalHier',
      hierarchyPath: '/local/projects/LocalHier.db',
      message: 'Configured project database was not found at /gone/usb/Field2026.db.',
    })
  );
  assert.equal(missingProjectOnly.clearSu, false);
  assert.equal(missingProjectOnly.clearHierarchy, false);
  assert.equal(missingProjectOnly.hasMissingDatabase, true);
});

test('StartupRecoveryPanel SSR renders repair vs relocate headings and accurate checkbox states', () => {
  const Panel = serverComponent(source, 'StartupRecoveryPanel.svelte', {
    '../../bindings/github.com/boostao/vpro/app': {
      LifecycleService: {
        ResetStartupToSample: async () => ({ ready: true, backupPath: '' }),
        ChooseStartupDatabaseFile: async () => '',
        RecoverStartupWithPaths: async () => ({ ready: true, backupPath: '' }),
      },
    },
  });

  // 1. Settings conflict / legacy scalar failure with valid Sample.db -> Repair heading, 0 checked boxes
  const settingsHtml = render(Panel, {
    props: {
      startupFailure: makeFailure({
        message: 'legacy JSON conflicts with explicit YAML Current.CurrHierarchy; both files were retained',
      }),
      busy: false,
      onrecovered: () => {},
    },
  }).body;
  assert.match(settingsHtml, /Option 2: Repair settings &amp; open project/);
  assert.doesNotMatch(settingsHtml, /Current\.CurrHierarchy/);
  assert.match(settingsHtml, /Active Hierarchy/);
  assert.equal((settingsHtml.match(/type="checkbox"[^>]*checked/g) ?? []).length, 0);
  assert.match(settingsHtml, /id="recovery-hierarchy-path"/);

  // 2. Missing external Hierarchy path -> Relocate heading, only Hierarchy checkbox checked
  const missingHierHtml = render(Panel, {
    props: {
      startupFailure: makeFailure({
        configuredSu: 'None',
        suPath: '',
        configuredHierarchy: 'MissingHier',
        hierarchyPath: '/gone/drive/MissingHier.db',
        message: 'Configured Hierarchy database was not found at /gone/drive/MissingHier.db.',
      }),
      busy: false,
      onrecovered: () => {},
    },
  }).body;
  assert.match(missingHierHtml, /Option 2: Relocate missing database path/);
  assert.equal((missingHierHtml.match(/type="checkbox"[^>]*checked/g) ?? []).length, 1);
  assert.doesNotMatch(missingHierHtml, /id="recovery-hierarchy-path"/);
});
