const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const vm = require('node:vm');
const ts = require('typescript');
const { compile } = require('svelte/compiler');
const { render } = require('svelte/server');
const { componentFunctions, serverComponent, srcPath } = require('./svelteTestHelpers.cjs');

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
  detectSupportDatabaseFailure,
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

test('detectSupportDatabaseFailure and deriveInitialRecoveryDraft diagnose corrupt VUser.db and other support DBs', () => {
  assert.equal(detectSupportDatabaseFailure(makeFailure()), null);

  // 1. Enriched diagnostic from Go StartupService with explicit VUser.db path
  const enrichedFailure = makeFailure({
    message:
      'Shared support database VUser.db (personal species and site unit lists) at /tmp/vpro/data/database-family/VUser.db ' +
      'could not be opened because the file is not a readable VPro database. Your project files and saved settings were kept unchanged.',
  });
  const enrichedDraft = deriveInitialRecoveryDraft(enrichedFailure);
  assert.ok(enrichedDraft.supportDatabaseIssue);
  assert.equal(enrichedDraft.supportDatabaseIssue.role, 'VUser');
  assert.equal(enrichedDraft.supportDatabaseIssue.fileName, 'VUser.db');
  assert.equal(
    enrichedDraft.supportDatabaseIssue.filePath,
    '/tmp/vpro/data/database-family/VUser.db'
  );
  assert.equal(enrichedDraft.supportDatabaseIssue.hasPersonalUserEntries, true);
  assert.equal(enrichedDraft.hasMissingDatabase, false);
  assert.equal(enrichedDraft.clearSu, false);
  assert.equal(enrichedDraft.clearHierarchy, false);
  assert.doesNotMatch(enrichedDraft.formattedMessage, /RuntimeError|YAML|SQLITE_NOTADB/);

  // 2. Raw attach failure infers database-family/VUser.db path from workspace projectPath (POSIX & Windows)
  const rawPosixDraft = deriveInitialRecoveryDraft(
    makeFailure({
      message: 'configured context could not be opened; YAML was retained: attach VUser: file is not a database',
    })
  );
  assert.ok(rawPosixDraft.supportDatabaseIssue);
  assert.equal(rawPosixDraft.supportDatabaseIssue.filePath, '/tmp/vpro/data/database-family/VUser.db');
  assert.match(rawPosixDraft.formattedMessage, /Shared support database VUser\.db/);
  assert.match(rawPosixDraft.formattedMessage, /\/tmp\/vpro\/data\/database-family\/VUser\.db/);
  assert.doesNotMatch(rawPosixDraft.formattedMessage, /YAML|RuntimeError/);

  const rawWinIssue = detectSupportDatabaseFailure(
    makeFailure({
      projectPath: 'C:\\Users\\FieldCrew\\AppData\\Local\\vpro\\projects\\Sample.db',
      message: 'configured context could not be opened; YAML was retained: VUser.USysUserSpp is missing a required physical table',
    })
  );
  assert.ok(rawWinIssue);
  assert.equal(
    rawWinIssue.filePath,
    'C:\\Users\\FieldCrew\\AppData\\Local\\vpro\\database-family\\VUser.db'
  );

  // 3. Multi-support-database corruption
  const multiIssue = detectSupportDatabaseFailure(
    makeFailure({
      message:
        'Shared support databases could not be opened: VLists.db (provincial plant taxonomy and BEC reference lists) ' +
        'at /tmp/vpro/data/database-family/VLists.db (the file is empty (0 bytes)); ' +
        'VUser.db (personal species and site unit lists) at /tmp/vpro/data/database-family/VUser.db (the file is not a readable VPro database).',
    })
  );
  assert.ok(multiIssue);
  assert.deepEqual([...multiIssue.allFileNames], ['VLists.db', 'VUser.db']);
  assert.equal(multiIssue.hasPersonalUserEntries, true);
});

test('StartupRecoveryPanel SSR and recovery actions back up corrupt VUser.db and exit Startup Recovery', async () => {
  const Panel = serverComponent(source, 'StartupRecoveryPanel.svelte', {
    '../../bindings/github.com/boostao/vpro/app': {
      LifecycleService: {
        ResetStartupToSample: async () => ({ ready: true, backupPath: '' }),
        ChooseStartupDatabaseFile: async () => '',
        RecoverStartupWithPaths: async () => ({ ready: true, backupPath: '' }),
      },
    },
  });

  const corruptVUserHtml = render(Panel, {
    props: {
      startupFailure: makeFailure({
        message:
          'Shared support database VUser.db (personal species and site unit lists) at /tmp/vpro/data/database-family/VUser.db ' +
          'could not be opened because the file is not a readable VPro database. Your project files and saved settings were kept unchanged.',
      }),
      busy: false,
      onrecovered: () => {},
    },
  }).body;

  assert.match(corruptVUserHtml, /Shared support database could not be opened/);
  assert.match(corruptVUserHtml, /data-startup-support-db-callout/);
  assert.match(corruptVUserHtml, /\/tmp\/vpro\/data\/database-family\/VUser\.db/);
  assert.match(corruptVUserHtml, /VUser\.corrupt-&lt;timestamp(?:&gt;|>)\.db/);
  assert.match(corruptVUserHtml, /data-startup-repair-support/);
  assert.match(corruptVUserHtml, /Back up &amp; restore VUser\.db &amp; open project/);
  assert.match(corruptVUserHtml, /Restore VUser\.db &amp; Switch to Sample project/);
  assert.doesNotMatch(corruptVUserHtml, /Option 2: Relocate missing database path/);

  // Exercise interactive recovery actions (Option 1: keep project & settings; Option 2: switch to Sample)
  const calls = [];
  const notices = [];
  const supportFailure = makeFailure({
    message:
      'Shared support database VUser.db (personal species and site unit lists) at /tmp/vpro/data/database-family/VUser.db ' +
      'could not be opened because the file is not a readable VPro database.',
  });
  const derivedMeta = deriveInitialRecoveryDraft(supportFailure);

  const ctx = componentFunctions(
    'StartupRecoveryPanel.svelte',
    ['buildRecoveryNotice', 'fallbackStartupToSample', 'recoverStartupPaths', 'repairSupportAndOpenProject'],
    {
      $state: { snapshot: (v) => structuredClone(v) },
      busy: false,
      recoveryWorking: false,
      recoveryError: '',
      recoveryProjectPath: derivedMeta.projectPath,
      recoveryProjectName: derivedMeta.projectName,
      recoverySUPath: derivedMeta.suPath,
      recoveryClearSU: derivedMeta.clearSu,
      recoveryHierarchyPath: derivedMeta.hierarchyPath,
      recoveryClearHierarchy: derivedMeta.clearHierarchy,
      derivedMeta,
      formatStartupError,
      LifecycleService: {
        RecoverStartupWithPaths: async (payload) => {
          calls.push({ rpc: 'RecoverStartupWithPaths', payload });
          return {
            ready: true,
            backupPath: '/tmp/vpro/config/config.backup-20261119-164500.yml',
            message:
              'Unreadable VUser.db was backed up to /tmp/vpro/data/database-family/VUser.corrupt-20261119-164500.db and replaced with a clean VUser.db.',
          };
        },
        ResetStartupToSample: async () => {
          calls.push({ rpc: 'ResetStartupToSample' });
          return {
            ready: true,
            backupPath: '/tmp/vpro/config/config.backup-20261119-164500.yml',
            message:
              'Unreadable VUser.db was backed up to /tmp/vpro/data/database-family/VUser.corrupt-20261119-164500.db and replaced with a clean VUser.db.',
          };
        },
      },
      onrecovered: async (notice) => {
        notices.push(notice);
      },
    }
  );

  await ctx.actions.repairSupportAndOpenProject();
  assert.equal(calls.length, 1);
  assert.equal(calls[0].rpc, 'RecoverStartupWithPaths');
  assert.equal(calls[0].payload.projectPath, '/tmp/vpro/data/projects/Sample.db');
  assert.equal(notices.length, 1);
  assert.match(notices[0], /Support database restored and project opened cleanly\./);
  assert.match(notices[0], /VUser\.corrupt-20261119-164500\.db/);
  assert.match(notices[0], /config\.backup-20261119-164500\.yml/);
  assert.equal(ctx.recoveryError, '');

  await ctx.actions.fallbackStartupToSample();
  assert.equal(calls.length, 2);
  assert.equal(calls[1].rpc, 'ResetStartupToSample');
  assert.equal(notices.length, 2);
  assert.match(notices[1], /Recovered with built-in Sample project\./);
  assert.match(notices[1], /VUser\.corrupt-20261119-164500\.db/);
});
