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

const MISSING_FILE_REASON_RE = /(not found|no such file|cannot find|unavailable|missing|does not exist)/i;

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

  for (const m of msg.matchAll(/\b(VPro64|VLists|VUser|VMetaData|VMessageBoard|VPics)\.db\b/gi)) {
    addRole(m[1]);
  }
  for (const m of msg.matchAll(/\battach\s+(VPro64|VLists|VUser|VMetaData|VMessageBoard|VPics)\s*:/gi)) {
    addRole(m[1]);
  }
  for (const m of msg.matchAll(
    /\bread\s+(VPro64|VLists|VUser|VMetaData|VMessageBoard|VPics)\s+table descriptions\s*:/gi
  )) {
    addRole(m[1]);
  }
  for (const m of msg.matchAll(
    /\b(VPro64|VLists|VUser|VMetaData|VMessageBoard|VPics)\.[A-Za-z0-9_]+\s+is missing\b/gi
  )) {
    addRole(m[1]);
  }
  for (const m of msg.matchAll(/\bDesktop\.DatabasePaths\.(VPro64|VLists|VUser|VMetaData|VMessageBoard|VPics)\b/gi)) {
    addRole(m[1]);
  }
  for (const m of msg.matchAll(/\b(?:create|validate)\s+temporary\s+([A-Za-z0-9_]+)\s*:/gi)) {
    const mapped = SUPPORT_VIEW_ROLE_MAP[m[1]];
    if (mapped) addRole(mapped);
  }

  if (roles.length === 0) return null;

  const primaryRole = roles[0];
  let filePath = '';

  for (const m of msg.matchAll(/((?:\/|[A-Za-z]:[\\/])[^\s"';()]+?\.db)\b/gi)) {
    const candidatePath = m[1];
    const baseMatch = /([^/\\]+)\.db$/i.exec(candidatePath);
    if (baseMatch && canonicalSupportRole(baseMatch[1])) {
      filePath = candidatePath;
      break;
    }
  }
  if (!filePath) {
    const atPathMatch = /\bat\s+((?:\/|[A-Za-z]:[\\/])[^\s;()]+?\.db)(?=[\s.;,)]|$)/i.exec(msg);
    if (atPathMatch) filePath = atPathMatch[1];
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
  if (/empty \(0 bytes\)/i.test(msg)) return 'the file is empty (0 bytes)';
  if (/file is not a database|not a readable VPro database/i.test(msg)) {
    return 'the file is not a readable VPro database';
  }
  if (/malformed|corrupt|integrity check|damaged/i.test(msg)) return 'the database file is damaged';
  if (/missing (?:a )?required (?:physical )?(?:table|column)|_table_metadata/i.test(msg)) {
    return 'required VPro support tables are missing or incomplete';
  }
  if (/no such file|not found|cannot find/i.test(msg)) return 'the file was not found';
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

  const legacyConflictMatch = /^legacy JSON conflicts with explicit YAML ([^;]+); both files were retained$/i.exec(msg);
  if (legacyConflictMatch) {
    const rawKey = legacyConflictMatch[1].trim();
    const friendly = FRIENDLY_CONFIG_FIELD_LABELS[rawKey] ?? rawKey;
    return `An older VPro selection file conflicts with your saved ${friendly} setting. Both files were kept unchanged.`;
  }

  const legacyChangedMatch =
    /^legacy (.+) changed after migration; YAML and JSON were retained for explicit resolution$/i.exec(msg);
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
    if (msg.includes(rawKey)) msg = msg.replaceAll(rawKey, friendly);
  }

  return msg
    .replaceAll(
      'configured context could not be opened; YAML was retained: ',
      'Your saved project or support databases could not be opened (your settings file was kept unchanged): '
    )
    .replaceAll('; YAML selection was retained', ' (your saved settings were kept unchanged)')
    .replaceAll('; YAML was retained', ' (your saved settings were kept unchanged)');
}

export function isDatabasePathMissing(
  failure: Partial<StartupState> | null | undefined,
  target: 'project' | 'su' | 'hierarchy'
): boolean {
  if (!failure) return false;
  const msg = String(failure.message ?? '');

  if (target === 'su') {
    if (!hasConfiguredContextSelection(failure.configuredSu)) return false;
    const suPath = String(failure.suPath ?? '').trim();
    if (
      /Configured Site Unit database was not found|Site Unit database unavailable|SU database unavailable/i.test(msg)
    ) {
      return true;
    }
    return suPath !== '' && msg.includes(suPath) && MISSING_FILE_REASON_RE.test(msg);
  }

  if (target === 'hierarchy') {
    if (!hasConfiguredContextSelection(failure.configuredHierarchy)) return false;
    const hierPath = String(failure.hierarchyPath ?? '').trim();
    if (
      /Configured Hierarchy database was not found|Hierarchy database unavailable|configured hierarchy .* unavailable/i.test(
        msg
      )
    ) {
      return true;
    }
    return hierPath !== '' && msg.includes(hierPath) && MISSING_FILE_REASON_RE.test(msg);
  }

  const projPath = String(failure.projectPath ?? '').trim();
  const projectMissingRe =
    /Configured project database was not found|configured project .* is unavailable|project database unavailable|external project\/SU path/i;
  if (projPath === '') {
    if (detectSupportDatabaseFailure(failure) !== null) return projectMissingRe.test(msg);
    return true;
  }
  if (projectMissingRe.test(msg)) return true;
  return msg.includes(projPath) && MISSING_FILE_REASON_RE.test(msg);
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

export function deriveInitialRecoveryDraft(failure: Partial<StartupState> | null | undefined): InitialRecoveryDraft {
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
