<script lang="ts" module>
  import type { StartupState } from '../../bindings/github.com/boostao/vpro/app';

  const FRIENDLY_CONFIG_FIELD_LABELS: Record<string, string> = {
    'Current.CoordMethod': 'Coordinate display format',
    'Current.AssignedSuSource': 'Working Unit source',
    'Current.ProjectIdSource': 'Project ID source',
    'Current.CurrProject': 'Active Project',
    'Current.CurrPlotlist': 'Active Site Unit list',
    'Current.CurrHierarchy': 'Active Hierarchy',
    'Current.ProjectPath': 'Project file path',
    'Current.SUPath': 'Site Unit file path',
    'Current.HierarchyPath': 'Hierarchy file path',
    'Current.User': 'User name',
    'Audit.AuditStrength': 'Audit tracking level',
    'Desktop.SchemaVersion': 'Settings version',
  };

  const SUPPORT_DATABASE_DESCRIPTIONS: Record<string, string> = {
    VPro64: 'built-in table templates',
    VLists: 'provincial plant taxonomy and BEC reference lists',
    VUser: 'personal species and site unit lists',
    VMetaData: 'project metadata codes',
    VMessageBoard: 'workspace message board',
    VPics: 'plot picture catalogue',
  };

  const SUPPORT_VIEW_ROLE_MAP: Record<string, string> = {
    USysUserSpp: 'VUser',
    USysUserSiteUnitList: 'VUser',
    UserSiteUnitList: 'VUser',
    USysSiteUnitAll: 'VUser',
    USysPrefs: 'VUser',
    USysAllSpecs: 'VLists',
    USysTableOfLists: 'VLists',
    USysMasterSiteUnitList: 'VLists',
    MasterSiteUnitList: 'VLists',
    USysMetadataTemplates: 'VLists',
    USysZoneList: 'VLists',
    USysMasterAudit: 'VLists',
    USysSiteSeriesNames: 'VLists',
    USysSppAttributes: 'VLists',
    USysSppAttributeFieldList: 'VLists',
    USysSppAttributeDescription: 'VLists',
    ProjectMetadata: 'VMetaData',
    ProjectMetaDataCodes: 'VMetaData',
    tblMessageBoard: 'VMessageBoard',
    tblMessageList: 'VMessageBoard',
    tblVPics: 'VPics',
  };

  const MISSING_FILE_REASON_RE =
    /(not found|no such file|cannot find|unavailable|missing|does not exist)/i;

  function canonicalSupportRole(raw: string | null | undefined): string | null {
    const cleaned = String(raw ?? '')
      .trim()
      .replace(/\.db$/i, '');
    for (const role of Object.keys(SUPPORT_DATABASE_DESCRIPTIONS)) {
      if (role.toLowerCase() === cleaned.toLowerCase()) {
        return role;
      }
    }
    return null;
  }

  export interface SupportDatabaseIssue {
    role: string;
    fileName: string;
    allFileNames: string[];
    roleDescription: string;
    filePath: string;
    hasPersonalUserEntries: boolean;
  }

  export function detectSupportDatabaseFailure(
    failure: Partial<StartupState> | null | undefined
  ): SupportDatabaseIssue | null {
    if (!failure) return null;
    const msg = String(failure.message ?? '').trim();
    if (!msg) return null;

    const roles: string[] = [];
    const addRole = (candidate: string | null | undefined) => {
      const canon = canonicalSupportRole(candidate);
      if (canon && !roles.includes(canon)) {
        roles.push(canon);
      }
    };

    const dbNameRe = /\b(VPro64|VLists|VUser|VMetaData|VMessageBoard|VPics)\.db\b/gi;
    for (const m of msg.matchAll(dbNameRe)) {
      addRole(m[1]);
    }
    const attachRe = /\battach\s+(VPro64|VLists|VUser|VMetaData|VMessageBoard|VPics)\s*:/gi;
    for (const m of msg.matchAll(attachRe)) {
      addRole(m[1]);
    }
    const descRe =
      /\bread\s+(VPro64|VLists|VUser|VMetaData|VMessageBoard|VPics)\s+table descriptions\s*:/gi;
    for (const m of msg.matchAll(descRe)) {
      addRole(m[1]);
    }
    const missingTblRe =
      /\b(VPro64|VLists|VUser|VMetaData|VMessageBoard|VPics)\.[A-Za-z0-9_]+\s+is missing\b/gi;
    for (const m of msg.matchAll(missingTblRe)) {
      addRole(m[1]);
    }
    const dbPathsRe =
      /\bDesktop\.DatabasePaths\.(VPro64|VLists|VUser|VMetaData|VMessageBoard|VPics)\b/gi;
    for (const m of msg.matchAll(dbPathsRe)) {
      addRole(m[1]);
    }
    const tempViewRe = /\b(?:create|validate)\s+temporary\s+([A-Za-z0-9_]+)\s*:/gi;
    for (const m of msg.matchAll(tempViewRe)) {
      const mapped = SUPPORT_VIEW_ROLE_MAP[m[1]];
      if (mapped) addRole(mapped);
    }

    if (roles.length === 0) {
      return null;
    }

    const primaryRole = roles[0];
    let filePath = '';

    const pathCandidateRe = /((?:\/|[A-Za-z]:[\\/])[^\s"';()]+?\.db)\b/gi;
    for (const m of msg.matchAll(pathCandidateRe)) {
      const candidatePath = m[1];
      const baseMatch = /([^/\\]+)\.db$/i.exec(candidatePath);
      if (baseMatch && canonicalSupportRole(baseMatch[1])) {
        filePath = candidatePath;
        break;
      }
    }
    if (!filePath) {
      const atPathMatch = /\bat\s+((?:\/|[A-Za-z]:[\\/])[^\s;()]+?\.db)(?=[\s.;,)]|$)/i.exec(msg);
      if (atPathMatch) {
        filePath = atPathMatch[1];
      }
    }
    if (!filePath) {
      const projPath = String(failure.projectPath ?? '').trim();
      const workspaceMatch = /^(.*?)([/\\])projects\2[^/\\]+\.db$/i.exec(projPath);
      if (workspaceMatch) {
        const [, rootDir, sep] = workspaceMatch;
        filePath = `${rootDir}${sep}database-family${sep}${primaryRole}.db`;
      }
    }

    const allFileNames = roles.map((r) => `${r}.db`);
    return {
      role: primaryRole,
      fileName: allFileNames.length === 1 ? allFileNames[0] : allFileNames.join(', '),
      allFileNames,
      roleDescription: SUPPORT_DATABASE_DESCRIPTIONS[primaryRole] ?? 'shared support database',
      filePath,
      hasPersonalUserEntries: roles.includes('VUser'),
    };
  }

  function describeRawSupportFailureReason(msg: string): string {
    if (/empty \(0 bytes\)/i.test(msg)) {
      return 'the file is empty (0 bytes)';
    }
    if (/file is not a database|not a readable VPro database/i.test(msg)) {
      return 'the file is not a readable VPro database';
    }
    if (/malformed|corrupt|integrity check|damaged/i.test(msg)) {
      return 'the database file is damaged';
    }
    if (/missing (?:a )?required (?:physical )?(?:table|column)|_table_metadata/i.test(msg)) {
      return 'required VPro support tables are missing or incomplete';
    }
    if (/no such file|not found|cannot find/i.test(msg)) {
      return 'the file was not found';
    }
    return 'the file could not be read';
  }

  export function hasConfiguredContextSelection(name: string | null | undefined): boolean {
    const trimmed = String(name ?? '').trim();
    return trimmed !== '' && trimmed !== 'None';
  }

  export function formatStartupError(raw: unknown): string {
    let msg = String(raw ?? '').trim();
    if (!msg) return '';

    const prefixes = ['RuntimeError:', 'Error:', 'validate recovered configuration:'];
    let stripped = true;
    while (stripped) {
      stripped = false;
      for (const prefix of prefixes) {
        if (msg.startsWith(prefix)) {
          msg = msg.slice(prefix.length).trim();
          stripped = true;
        }
      }
    }

    const legacyConflictMatch =
      /^legacy JSON conflicts with explicit YAML ([^;]+); both files were retained$/i.exec(msg);
    if (legacyConflictMatch) {
      const rawKey = legacyConflictMatch[1].trim();
      const friendly = FRIENDLY_CONFIG_FIELD_LABELS[rawKey] ?? rawKey;
      return `An older VPro selection file conflicts with your saved ${friendly} setting. Both files were kept unchanged.`;
    }

    const legacyChangedMatch =
      /^legacy (.+) changed after migration; YAML and JSON were retained for explicit resolution$/i.exec(
        msg
      );
    if (legacyChangedMatch) {
      return `An older VPro settings file (${legacyChangedMatch[1].trim()}) changed after your preferences were upgraded. Both files were kept unchanged so you can confirm which project to open.`;
    }

    if (msg === 'Current.CoordMethod must be an integer from 1 to 3') {
      return 'Saved Coordinate display format setting could not be read (expected Decimal Degrees, Degrees-Minutes, or Degrees-Minutes-Seconds).';
    }
    if (msg === 'Current.AssignedSuSource must be an integer from 1 to 3') {
      return 'Saved Working Unit source setting could not be read.';
    }
    if (msg === 'Audit.AuditStrength must be an integer from 0 to 3') {
      return 'Saved Audit tracking level setting could not be read.';
    }
    if (msg === 'Desktop.SchemaVersion must be an integer from 1 to 1') {
      return 'Saved settings version is not supported by this release of VPro.';
    }
    if (msg === 'Current.User must not be empty') {
      return 'Saved User name must not be empty.';
    }

    for (const [rawKey, friendly] of Object.entries(FRIENDLY_CONFIG_FIELD_LABELS)) {
      if (msg.includes(rawKey)) {
        msg = msg.replaceAll(rawKey, friendly);
      }
    }

    msg = msg
      .replaceAll(
        'configured context could not be opened; YAML was retained: ',
        'Your saved project or support databases could not be opened (your settings file was kept unchanged): '
      )
      .replaceAll('; YAML selection was retained', ' (your saved settings were kept unchanged)')
      .replaceAll('; YAML was retained', ' (your saved settings were kept unchanged)');

    return msg;
  }

  export function isDatabasePathMissing(
    failure: Partial<StartupState> | null | undefined,
    target: 'project' | 'su' | 'hierarchy'
  ): boolean {
    if (!failure) return false;
    const msg = String(failure.message ?? '');

    if (target === 'su') {
      if (!hasConfiguredContextSelection(failure.configuredSu)) {
        return false;
      }
      const suPath = String(failure.suPath ?? '').trim();
      if (
        /Configured Site Unit database was not found|Site Unit database unavailable|SU database unavailable/i.test(
          msg
        )
      ) {
        return true;
      }
      if (suPath !== '' && msg.includes(suPath) && MISSING_FILE_REASON_RE.test(msg)) {
        return true;
      }
      return false;
    }

    if (target === 'hierarchy') {
      if (!hasConfiguredContextSelection(failure.configuredHierarchy)) {
        return false;
      }
      const hierPath = String(failure.hierarchyPath ?? '').trim();
      if (
        /Configured Hierarchy database was not found|Hierarchy database unavailable|configured hierarchy .* unavailable/i.test(
          msg
        )
      ) {
        return true;
      }
      if (hierPath !== '' && msg.includes(hierPath) && MISSING_FILE_REASON_RE.test(msg)) {
        return true;
      }
      return false;
    }

    const projPath = String(failure.projectPath ?? '').trim();
    if (projPath === '') {
      if (detectSupportDatabaseFailure(failure) !== null) {
        return /Configured project database was not found|configured project .* is unavailable|project database unavailable|external project\/SU path/i.test(
          msg
        );
      }
      return true;
    }
    if (
      /Configured project database was not found|configured project .* is unavailable|project database unavailable|external project\/SU path/i.test(
        msg
      )
    ) {
      return true;
    }
    if (msg.includes(projPath) && MISSING_FILE_REASON_RE.test(msg)) {
      return true;
    }
    return false;
  }

  export interface InitialRecoveryDraft {
    projectPath: string;
    projectName: string;
    suPath: string;
    clearSu: boolean;
    hierarchyPath: string;
    clearHierarchy: boolean;
    hasMissingDatabase: boolean;
    supportDatabaseIssue: SupportDatabaseIssue | null;
    formattedMessage: string;
  }

  export function deriveInitialRecoveryDraft(
    failure: Partial<StartupState> | null | undefined
  ): InitialRecoveryDraft {
    const supportDatabaseIssue = detectSupportDatabaseFailure(failure);
    const clearSu = isDatabasePathMissing(failure, 'su');
    const clearHierarchy = isDatabasePathMissing(failure, 'hierarchy');
    const projectMissing = isDatabasePathMissing(failure, 'project');

    let formattedMessage = formatStartupError(failure?.message ?? '');
    if (
      supportDatabaseIssue &&
      !/^Shared support database/i.test(formattedMessage) &&
      /^Your saved project or support databases could not be opened/i.test(formattedMessage)
    ) {
      const reason = describeRawSupportFailureReason(formattedMessage);
      const atClause = supportDatabaseIssue.filePath ? ` at ${supportDatabaseIssue.filePath}` : '';
      formattedMessage =
        `Shared support database ${supportDatabaseIssue.role}.db (${supportDatabaseIssue.roleDescription})${atClause} ` +
        `could not be opened because ${reason}. Your project files and saved settings were kept unchanged.`;
    }

    return {
      projectPath: String(failure?.projectPath ?? ''),
      projectName: String(failure?.configuredProject ?? ''),
      suPath: String(failure?.suPath ?? ''),
      clearSu,
      hierarchyPath: String(failure?.hierarchyPath ?? ''),
      clearHierarchy,
      hasMissingDatabase: projectMissing || clearSu || clearHierarchy,
      supportDatabaseIssue,
      formattedMessage,
    };
  }
</script>

<script lang="ts">
  import { untrack } from 'svelte';
  import {
    LifecycleService,
    type StartupRecoveryRequest,
  } from '../../bindings/github.com/boostao/vpro/app';

  let {
    startupFailure,
    busy,
    onrecovered,
  }: {
    startupFailure: StartupState;
    busy: boolean;
    onrecovered: (backupNotice: string) => Promise<void> | void;
  } = $props();

  function failureSignature(state: StartupState): string {
    return JSON.stringify([
      state.configPath ?? '',
      state.message ?? '',
      state.configuredProject ?? '',
      state.projectPath ?? '',
      state.configuredSu ?? '',
      state.suPath ?? '',
      state.configuredHierarchy ?? '',
      state.hierarchyPath ?? '',
    ]);
  }

  const initialSeed = untrack(() => deriveInitialRecoveryDraft(startupFailure));
  let appliedSignature = untrack(() => failureSignature(startupFailure));

  let recoveryWorking = $state(false);
  let recoveryError = $state('');
  let recoveryProjectPath = $state(initialSeed.projectPath);
  let recoveryProjectName = $state(initialSeed.projectName);
  let recoverySUPath = $state(initialSeed.suPath);
  let recoveryClearSU = $state(initialSeed.clearSu);
  let recoveryHierarchyPath = $state(initialSeed.hierarchyPath);
  let recoveryClearHierarchy = $state(initialSeed.clearHierarchy);

  let derivedMeta = $derived(deriveInitialRecoveryDraft(startupFailure));

  $effect(() => {
    const nextSignature = failureSignature(startupFailure);
    if (nextSignature === appliedSignature) return;
    appliedSignature = nextSignature;
    const nextDraft = deriveInitialRecoveryDraft(startupFailure);
    recoveryProjectPath = nextDraft.projectPath;
    recoveryProjectName = nextDraft.projectName;
    recoverySUPath = nextDraft.suPath;
    recoveryClearSU = nextDraft.clearSu;
    recoveryHierarchyPath = nextDraft.hierarchyPath;
    recoveryClearHierarchy = nextDraft.clearHierarchy;
  });

  function buildRecoveryNotice(baseNotice: string, recovered: Partial<StartupState>): string {
    const parts = [baseNotice];
    const extraMsg = String(recovered.message ?? '').trim();
    if (extraMsg) {
      parts.push(extraMsg);
    }
    const backup = String(recovered.backupPath ?? '').trim();
    if (backup && !extraMsg.includes(backup)) {
      parts.push(`Previous configuration was backed up to ${backup}.`);
    }
    return parts.join(' ');
  }

  async function fallbackStartupToSample() {
    if (recoveryWorking || busy) return;
    recoveryWorking = true;
    recoveryError = '';
    try {
      const recovered = await LifecycleService.ResetStartupToSample();
      const notice = buildRecoveryNotice('Recovered with built-in Sample project.', recovered);
      await onrecovered(notice);
    } catch (cause) {
      recoveryError = `Could not fall back to Sample project: ${formatStartupError(cause)}`;
    } finally {
      recoveryWorking = false;
    }
  }

  async function browseStartupDatabase(target: 'project' | 'su' | 'hierarchy') {
    if (recoveryWorking || busy) return;
    recoveryWorking = true;
    recoveryError = '';
    try {
      const picked = await LifecycleService.ChooseStartupDatabaseFile();
      if (!picked) return;
      if (target === 'project') {
        recoveryProjectPath = picked;
      } else if (target === 'su') {
        recoverySUPath = picked;
        recoveryClearSU = false;
      } else {
        recoveryHierarchyPath = picked;
        recoveryClearHierarchy = false;
      }
    } catch (cause) {
      recoveryError = `File picker unavailable: ${formatStartupError(cause)}`;
    } finally {
      recoveryWorking = false;
    }
  }

  async function recoverStartupPaths() {
    if (recoveryWorking || busy) return;
    recoveryWorking = true;
    recoveryError = '';
    try {
      const payload: StartupRecoveryRequest = $state.snapshot({
        projectPath: recoveryProjectPath.trim(),
        projectName: recoveryProjectName.trim(),
        suPath: recoverySUPath.trim(),
        clearSu: recoveryClearSU,
        hierarchyPath: recoveryHierarchyPath.trim(),
        clearHierarchy: recoveryClearHierarchy,
      });
      const recovered = await LifecycleService.RecoverStartupWithPaths(payload);
      const baseNotice = derivedMeta.supportDatabaseIssue
        ? 'Support database restored and project opened cleanly.'
        : derivedMeta.hasMissingDatabase
          ? 'Relocated project opened cleanly.'
          : 'Saved settings repaired and project opened cleanly.';
      const notice = buildRecoveryNotice(baseNotice, recovered);
      await onrecovered(notice);
    } catch (cause) {
      const prefix = derivedMeta.supportDatabaseIssue
        ? 'Could not restore support database'
        : derivedMeta.hasMissingDatabase
          ? 'Could not open relocated database'
          : 'Could not open project';
      recoveryError = `${prefix}: ${formatStartupError(cause)}`;
    } finally {
      recoveryWorking = false;
    }
  }

  async function repairSupportAndOpenProject() {
    if (recoveryWorking || busy) return;
    if (!recoveryProjectPath.trim() || derivedMeta.hasMissingDatabase) {
      await fallbackStartupToSample();
      return;
    }
    await recoverStartupPaths();
  }
</script>

{#snippet projectSelectionFormFields(submitLabel: string)}
  <div class="grid grid-cols-1 sm:grid-cols-3 gap-2 items-end">
    <label for="recovery-project-path" class="sm:col-span-2 flex flex-col gap-1 text-xs font-medium">
      Project database (.db) path
      <input
        id="recovery-project-path"
        class="px-2.5 py-1.5 border rounded text-xs font-mono"
        bind:value={recoveryProjectPath}
        placeholder="/path/to/Project.db"
        disabled={recoveryWorking || busy}
      />
    </label>
    <button
      type="button"
      data-startup-browse-project
      disabled={recoveryWorking || busy}
      class="px-3 py-1.5 border rounded text-xs font-medium hover:bg-slate-50 disabled:opacity-50"
      onclick={() => void browseStartupDatabase('project')}
    >
      Browse .db...
    </button>
  </div>
  <label for="recovery-project-name" class="flex flex-col gap-1 text-xs font-medium max-w-xs">
    Project name inside file (optional when single-project .db)
    <input
      id="recovery-project-name"
      class="px-2.5 py-1.5 border rounded text-xs"
      bind:value={recoveryProjectName}
      placeholder={startupFailure.configuredProject || 'Auto-detect'}
      disabled={recoveryWorking || busy}
    />
  </label>

  <div class="flex flex-wrap gap-4 text-xs">
    <label class="inline-flex items-center gap-1.5">
      <input type="checkbox" bind:checked={recoveryClearSU} disabled={recoveryWorking || busy} />
      <span>Reset missing Site Unit (SU) selection to None</span>
    </label>
    <label class="inline-flex items-center gap-1.5">
      <input type="checkbox" bind:checked={recoveryClearHierarchy} disabled={recoveryWorking || busy} />
      <span>Reset missing Hierarchy selection to None</span>
    </label>
  </div>

  {#if !recoveryClearSU && hasConfiguredContextSelection(startupFailure.configuredSu)}
    <div class="grid grid-cols-1 sm:grid-cols-3 gap-2 items-end">
      <label for="recovery-su-path" class="sm:col-span-2 flex flex-col gap-1 text-xs font-medium">
        Site Unit database (.db) path ({startupFailure.configuredSu})
        <input
          id="recovery-su-path"
          class="px-2.5 py-1.5 border rounded text-xs font-mono"
          bind:value={recoverySUPath}
          disabled={recoveryWorking || busy}
        />
      </label>
      <button
        type="button"
        disabled={recoveryWorking || busy}
        class="px-3 py-1.5 border rounded text-xs font-medium hover:bg-slate-50 disabled:opacity-50"
        onclick={() => void browseStartupDatabase('su')}
      >
        Browse SU .db...
      </button>
    </div>
  {/if}

  {#if !recoveryClearHierarchy && hasConfiguredContextSelection(startupFailure.configuredHierarchy)}
    <div class="grid grid-cols-1 sm:grid-cols-3 gap-2 items-end">
      <label for="recovery-hierarchy-path" class="sm:col-span-2 flex flex-col gap-1 text-xs font-medium">
        Hierarchy database (.db) path ({startupFailure.configuredHierarchy})
        <input
          id="recovery-hierarchy-path"
          class="px-2.5 py-1.5 border rounded text-xs font-mono"
          bind:value={recoveryHierarchyPath}
          disabled={recoveryWorking || busy}
        />
      </label>
      <button
        type="button"
        disabled={recoveryWorking || busy}
        class="px-3 py-1.5 border rounded text-xs font-medium hover:bg-slate-50 disabled:opacity-50"
        onclick={() => void browseStartupDatabase('hierarchy')}
      >
        Browse Hierarchy .db...
      </button>
    </div>
  {/if}

  <div>
    <button
      type="submit"
      data-startup-relocate-open
      disabled={recoveryWorking || busy || !recoveryProjectPath.trim()}
      class="px-3.5 py-1.5 rounded border border-[#003366] text-[#003366] text-xs font-semibold hover:bg-slate-50 disabled:opacity-50"
    >
      {recoveryWorking ? 'Opening...' : submitLabel}
    </button>
  </div>
{/snippet}

<section class="startup-recovery space-y-4 p-5 border rounded bg-white max-w-3xl" role="alert" data-startup-recovery>
  <div>
    <div class="eyebrow">Startup Recovery</div>
    <h1 class="text-xl font-semibold">
      {derivedMeta.supportDatabaseIssue
        ? 'Shared support database could not be opened'
        : 'Saved context could not be opened'}
    </h1>
  </div>
  <p class="text-sm">{derivedMeta.formattedMessage}</p>

  {#if derivedMeta.supportDatabaseIssue}
    {@const issue = derivedMeta.supportDatabaseIssue}
    {@const targetLabel = issue.allFileNames.length > 1 ? 'support databases' : issue.fileName}
    <div
      class="p-3.5 border border-amber-300 rounded bg-amber-50/70 space-y-1.5 text-xs text-slate-800"
      data-startup-support-db-callout
    >
      <div class="font-semibold">
        Affected support database: <code>{issue.fileName}</code> ({issue.roleDescription})
      </div>
      {#if issue.filePath}
        <div>
          File location: <code class="break-all">{issue.filePath}</code>
        </div>
      {/if}
      {#if issue.hasPersonalUserEntries}
        <p class="text-slate-700">
          <code>VUser.db</code> stores custom user species codes and personal site unit lists. Before
          restoring a clean built-in copy, VPro saves your existing file untouched as
          <code>VUser.corrupt-&lt;timestamp&gt;.db</code> in the same folder so no custom entries are
          silently lost.
        </p>
      {:else}
        <p class="text-slate-700">
          Before restoring a clean built-in copy, VPro saves the unreadable file untouched as
          <code>{issue.role}.corrupt-&lt;timestamp&gt;.db</code> in the same folder.
        </p>
      {/if}
    </div>
  {/if}

  <p class="text-xs text-slate-600">
    Your saved preferences in <code>{startupFailure.configPath}</code> and existing project files have not been modified yet.
    Choose an option below — VPro will automatically save a backup copy before making any changes.
  </p>
  {#if recoveryError}
    <p role="alert" class="error text-xs" data-startup-recovery-error>{recoveryError}</p>
  {/if}

  {#if derivedMeta.supportDatabaseIssue}
    {@const issue = derivedMeta.supportDatabaseIssue}
    {@const targetLabel = issue.allFileNames.length > 1 ? 'support databases' : issue.fileName}
    <div class="p-3.5 border rounded bg-slate-50 space-y-2" data-startup-repair-support-panel>
      <h2 class="text-sm font-semibold">Option 1: Back up &amp; restore {targetLabel}</h2>
      <p class="text-xs text-slate-700">
        Saves a timestamped backup copy of the unreadable support database, installs a clean built-in
        copy, and opens
        {#if recoveryProjectPath.trim() && !derivedMeta.hasMissingDatabase}
          your saved <strong>{startupFailure.configuredProject || 'Sample'}</strong> project with your
          preferences intact.
        {:else}
          VPro with the built-in <strong>Sample</strong> project.
        {/if}
        None of your existing <code>.db</code> project files are deleted or altered.
      </p>
      <button
        type="button"
        data-startup-repair-support
        disabled={recoveryWorking || busy}
        class="px-3.5 py-1.5 rounded bg-[#003366] text-white text-xs font-semibold hover:bg-[#002244] disabled:opacity-50"
        onclick={() => void repairSupportAndOpenProject()}
      >
        {recoveryWorking
          ? 'Restoring support database...'
          : `Back up & restore ${targetLabel} & open project`}
      </button>
    </div>

    <div class="p-3.5 border rounded space-y-2">
      <h2 class="text-sm font-semibold">
        Option 2: Restore {targetLabel} &amp; switch to Sample project
      </h2>
      <p class="text-xs text-slate-700">
        Backs up both the unreadable support database and your current settings, installs a clean
        built-in copy, and opens VPro with the built-in <strong>Sample</strong> project.
      </p>
      <button
        type="button"
        data-startup-fallback-sample
        disabled={recoveryWorking || busy}
        class="px-3.5 py-1.5 rounded border border-[#003366] text-[#003366] text-xs font-semibold hover:bg-slate-50 disabled:opacity-50"
        onclick={() => void fallbackStartupToSample()}
      >
        {recoveryWorking
          ? 'Recovering...'
          : `Restore ${targetLabel} & Switch to Sample project`}
      </button>
    </div>

    <details class="p-3.5 border rounded" open={derivedMeta.hasMissingDatabase}>
      <summary class="text-xs font-semibold cursor-pointer select-none">
        {derivedMeta.hasMissingDatabase
          ? `Option 3: Relocate missing project database (.db) & restore ${targetLabel}`
          : 'Open a different project database (.db) file instead'}
      </summary>
      <form
        class="mt-3 space-y-3"
        onsubmit={(event) => {
          event.preventDefault();
          void recoverStartupPaths();
        }}
      >
        {@render projectSelectionFormFields(`Restore ${targetLabel} & open selected project`)}
      </form>
    </details>
  {:else}
    <div class="p-3.5 border rounded bg-slate-50 space-y-2">
      <h2 class="text-sm font-semibold">Option 1: Open built-in Sample project</h2>
      <p class="text-xs text-slate-700">
        Backs up your current settings and opens VPro immediately with the built-in <strong>Sample</strong> project.
        None of your existing <code>.db</code> project files are deleted or altered.
      </p>
      <button
        type="button"
        data-startup-fallback-sample
        disabled={recoveryWorking || busy}
        class="px-3.5 py-1.5 rounded bg-[#003366] text-white text-xs font-semibold hover:bg-[#002244] disabled:opacity-50"
        onclick={() => void fallbackStartupToSample()}
      >
        {recoveryWorking ? 'Recovering...' : 'Switch to Sample project (back up settings)'}
      </button>
    </div>

    <form
      class="p-3.5 border rounded space-y-3"
      onsubmit={(event) => { event.preventDefault(); void recoverStartupPaths(); }}
    >
      <h2 class="text-sm font-semibold">
        {derivedMeta.hasMissingDatabase
          ? 'Option 2: Relocate missing database path'
          : 'Option 2: Repair settings & open project'}
      </h2>
      {#if !derivedMeta.hasMissingDatabase}
        <p class="text-xs text-slate-700">
          Updates your saved preferences while keeping your valid settings and opening the selected project.
        </p>
      {/if}
      {@render projectSelectionFormFields('Update paths & open project')}
    </form>
  {/if}
</section>
