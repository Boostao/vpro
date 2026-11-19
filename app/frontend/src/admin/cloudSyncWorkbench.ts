import { wellFormedUTF16 } from '../entry/qualityEditor';
import { validateProjectNameInput, parseLiteralTokenList } from './projectAdminWorkbench';
import { ContextService } from '../../bindings/github.com/boostao/vpro/app';
import { notifications } from '../shell/notificationService.svelte';

export { validateProjectNameInput, parseLiteralTokenList, notifications };

/**
 * Redacts PostgreSQL DSNs, password/token key-value pairs, Bearer credentials,
 * and literal session password values before messages are shown or routed to notifications.
 */
export function redactCloudSecrets(message: string, secrets: readonly string[] = []): string {
  let out = String(message ?? '');
  if (!out) return '';
  out = out.replace(/postgres(?:ql)?:\/\/[^\s'"`<>]+/gi, 'postgres://<redacted>');
  out = out.replace(
    /\b(PGPASSWORD|password|passwd|pwd|secret|token|api[_-]?key)\s*([:=])\s*(?:'[^']*'|"[^"]*"|[^\s;,&'"`]+)/gi,
    '$1$2<redacted>'
  );
  out = out.replace(/\bBearer\s+\S+/gi, 'Bearer <redacted>');
  for (const raw of secrets) {
    if (typeof raw !== 'string') continue;
    const candidates = [raw, raw.trim()].filter((val, idx, arr) => val.length >= 2 && arr.indexOf(val) === idx);
    for (const candidate of candidates) {
      out = out.split(candidate).join('<redacted>');
      try {
        const encoded = encodeURIComponent(candidate);
        if (encoded && encoded !== candidate) {
          out = out.split(encoded).join('<redacted>');
        }
      } catch {
        // Ignore malformed surrogate sequences during redaction.
      }
    }
  }
  return out;
}

function isSafeCloudIdentifier(token: string | undefined): token is string {
  if (!token) return false;
  if (token.includes('<redacted>') || token.includes('<pg-host>') || token.includes('<redacted-ip>')) {
    return false;
  }
  return /^[A-Za-z0-9_.-]{1,80}$/.test(token);
}

/**
 * Formats cloud sync, PostgreSQL/pgx, TLS, and local file errors into CBC-level
 * plain language while strictly preserving secret/DSN redaction and stripping
 * raw RuntimeError/SQLSTATE/syscall noise.
 */
export function formatCloudSyncError(cause: unknown, secrets: readonly string[] = []): string {
  let rawText = '';
  if (typeof cause === 'string') {
    rawText = cause;
  } else if (
    cause &&
    typeof cause === 'object' &&
    'message' in cause &&
    typeof (cause as { message: unknown }).message === 'string'
  ) {
    rawText = (cause as { message: string }).message;
  } else {
    rawText = String(cause ?? '');
  }

  let msg = redactCloudSecrets(rawText, secrets).trim();
  if (!msg) {
    return 'An unexpected cloud sync error occurred.';
  }

  const prefixRe = /^(?:RuntimeError|Error|CallError):\s*/i;
  while (prefixRe.test(msg)) {
    msg = msg.replace(prefixRe, '').trim();
  }
  if (!msg) {
    return 'An unexpected cloud sync error occurred.';
  }

  // 1. Unconfigured credentials / empty host
  if (/contributor credentials are not configured/i.test(msg)) {
    return 'Contributor cloud credentials are not configured. Enter your server and account details under Session Credential Override, or add them to becmaster.env.';
  }
  if (/custodian admin credentials are not configured/i.test(msg)) {
    return 'Custodian Admin cloud credentials are not configured. Enter custodian credentials under Session Credential Override, or add them to becmaster.env.';
  }
  if (/PostgreSQL credentials are not configured|PostgreSQL host is empty/i.test(msg)) {
    return 'Cloud server settings are incomplete. Enter the Server Host and account credentials under Session Credential Override.';
  }

  // 2. Remote plaintext TLS guard & SSL / X.509 handshake failures
  if (/TLS is required for remote PostgreSQL hosts/i.test(msg)) {
    return 'Encrypted connections are required for remote cloud servers. Set SSL Mode to require, verify-ca, or verify-full.';
  }
  if (/server does not support SSL/i.test(msg)) {
    return 'The cloud server does not accept encrypted SSL connections on this port. Check the Port and SSL Mode settings.';
  }
  if (
    /\bx509:|tls:|TLS handshake|certificate signed by unknown authority|certificate is valid for|certificate has expired|unable to verify the first certificate/i.test(
      msg
    )
  ) {
    return 'Secure connection failed because the server security certificate could not be verified. Check the Server Host and SSL Mode settings.';
  }

  // 3. PostgreSQL authentication / sign-in failures (SQLSTATE 28P01, 28000, pg_hba, SASL, password auth)
  if (/\bSQLSTATE\s+28P01\b|password authentication failed|SASL authentication failed/i.test(msg)) {
    const userMatch = /authentication failed for user\s+"([^"]+)"/i.exec(msg);
    const safeUser = isSafeCloudIdentifier(userMatch?.[1]) ? userMatch[1] : null;
    return safeUser
      ? redactCloudSecrets(`Could not sign in as "${safeUser}" — check your username and password.`, secrets)
      : 'Could not sign in to the cloud database — check your username and password.';
  }
  if (/no pg_hba\.conf entry/i.test(msg)) {
    return 'Could not sign in — the cloud server rejected connections for this account or network address. Check your username, SSL Mode, and server access rules.';
  }
  if (/\bSQLSTATE\s+28000\b|is not permitted to log in|role\s+"[^"]+"\s+does not exist|authentication failed/i.test(msg)) {
    return 'Could not sign in to the cloud database — check your username, role selection, and password.';
  }

  // 4. Missing cloud database (SQLSTATE 3D000)
  if (/\bSQLSTATE\s+3D000\b|database\s+"[^"]+"\s+does not exist/i.test(msg)) {
    const dbMatch = /database\s+"([^"]+)"\s+does not exist/i.exec(msg);
    const safeDb = isSafeCloudIdentifier(dbMatch?.[1]) ? dbMatch[1] : null;
    return safeDb
      ? redactCloudSecrets(
          `Cloud database "${safeDb}" was not found on the server. Check the Database name in Session Credential Override.`,
          secrets
        )
      : 'The configured cloud database was not found on the server. Check the Database name and try again.';
  }

  // 5. Insufficient database privileges (SQLSTATE 42501)
  if (/\bSQLSTATE\s+42501\b|permission denied for (?:schema|table|relation|sequence|database|function)|must be owner of/i.test(msg)) {
    return 'Your current cloud role does not have permission for this action. Switch to Custodian Admin if you are bootstrapping schemas, publishing standards, merging submissions, or cutting snapshots.';
  }

  // 6. Unbootstrapped BECMaster schemas/tables (SQLSTATE 42P01 / 3F000)
  if (
    /\bSQLSTATE\s+(?:42P01|3F000)\b|(?:relation|schema)\s+"(?:becmaster|staging|standards)(?:\.[^"]+)?"\s+does not exist/i.test(
      msg
    )
  ) {
    return 'Required BECMaster cloud tables are not set up on this server yet. Ask a Custodian Admin to run Bootstrap / Verify Schemas first.';
  }

  // 7. Concurrent custodian merge conflict (SQLSTATE 40001)
  if (/\bSQLSTATE\s+40001\b|could not serialize access/i.test(msg)) {
    return 'Another custodian updated BECMaster at the same time. Re-run Review & 3-Way Diff vs BECMaster and try again.';
  }

  // 8. DNS lookup / network reachability / connection refused / timeouts
  if (
    /\bno such host\b|Temporary failure in name resolution|Name or service not known|nodename nor servname provided|\bserver misbehaving\b|\bgetaddrinfo\b/i.test(
      msg
    )
  ) {
    return 'Server address could not be found. Check the Server Host setting and your network connection.';
  }
  if (/\bconnection refused\b|actively refused it/i.test(msg)) {
    return 'Could not connect to the cloud server — the server refused the connection. Check the Server Host, Port, and that the server is running.';
  }
  if (/\bi\/o timeout\b|context deadline exceeded|\bconnection timed out\b|\bdial\s+tcp\b.*\btimed out\b|\btimeout\b.*connect/i.test(msg)) {
    return 'Connection to the cloud server timed out. Check the Server Host, Port, and your network or VPN connection.';
  }
  if (/\bnetwork is unreachable\b|\bno route to host\b|\bconnection reset by peer\b/i.test(msg)) {
    return 'Could not reach the cloud server. Check your network or VPN connection and server settings.';
  }

  // 9. Local file system & SQLite file errors (Publish Standards, Seed Baseline, Subset / Snapshot export)
  if (/picture selection|file dialogs not available in server mode|requires an active desktop window/i.test(msg)) {
    return 'File selection requires an active desktop window; enter a file path directly when running in a browser.';
  }
  if (/database disk image is malformed|file is not a database/i.test(msg)) {
    return 'The selected local file is damaged, incomplete, or is not a valid VPro database file (.db).';
  }
  if (
    /\b(?:lstat|stat|open|CreateFile|GetFileAttributesEx)\b[^:]*:\s*(?:no such file or directory|cannot find the file|cannot find the path)|resolve database\s+"[^"]+":.*(?:no such file or directory|cannot find)/i.test(
      msg
    )
  ) {
    const pathMatch =
      /resolve database\s+"([^"]+)"/i.exec(msg) ?? /"([^"]+\.(?:db|sqlite|sqlite3|rds|gpkg))"/i.exec(msg);
    const safePath = pathMatch?.[1] && !pathMatch[1].includes('<redacted>') ? pathMatch[1] : null;
    return safePath
      ? redactCloudSecrets(`Local database file "${safePath}" was not found. Check the file path and try again.`, secrets)
      : 'The specified local database file or folder was not found. Check the file path and try again.';
  }
  if (/\b(?:lstat|stat|open|CreateFile|GetFileAttributesEx|mkdir)\b[^:]*:\s*(?:permission denied|access is denied)/i.test(msg)) {
    return 'VPro does not have permission to read or write the specified local file path.';
  }
  if (/\bis a directory\b|must be a regular file/i.test(msg)) {
    return 'The specified path points to a folder instead of a database file (.db).';
  }

  // 10. Context cancellation
  if (/^context canceled$/i.test(msg)) {
    return 'The cloud operation was cancelled.';
  }

  // 11. General fallback: strip pgx dial prefixes, FATAL/ERROR headers, SQLSTATE codes, and OS syscall prefixes
  msg = msg.replace(
    /^(?:connect to PostgreSQL|configure PostgreSQL pool|initialize PostgreSQL pool|parse PostgreSQL connection config|parse PostgreSQL host):\s*/i,
    ''
  );
  msg = msg.replace(/failed to connect to `[^`]*`:\s*(?:[^\s:]+(?:\s+\([^)]*\))?:\s*)*/gi, '');
  msg = msg.replace(/\b(?:server error:\s*)?(?:FATAL|ERROR|PANIC):\s*/gi, '');
  msg = msg.replace(/\s*\(SQLSTATE\s+[0-9A-Z]{5}\)/gi, '');
  msg = msg.replace(/\bSQLSTATE\s+[0-9A-Z]{5}\b:?\s*/gi, '');
  msg = msg.replace(/\b(?:lstat|stat|open|CreateFile|GetFileAttributesEx)\s+[^:]+:\s*/gi, '');
  msg = msg.replace(/\s{2,}/g, ' ').trim();

  return redactCloudSecrets(msg || 'An unexpected cloud sync error occurred.', secrets);
}

export type CloudRoleMode = 'contributor' | 'custodian';
export type CloudMergeResolution = 'keep_target' | 'accept_source';

export const CUSTODIAN_PROTECTED_FIELDS = ['BECSiteUnit', 'BEC_Use', 'GIS_BGC'] as const;

export interface CloudConfigStatus {
  configured: boolean;
  configSource: string;
  envFileDetected: boolean;
  activeRoleMode: CloudRoleMode;
  hasContributorCreds: boolean;
  hasCustodianCreds: boolean;
  sessionOverride: boolean;
  port: number;
  database: string;
  sslMode: string;
}

export interface SessionConfigRequest {
  roleMode: CloudRoleMode;
  clearOverrides?: boolean;
  host?: string;
  port?: number;
  database?: string;
  sslMode?: string;
  user?: string;
  password?: string;
  adminUser?: string;
  adminPassword?: string;
}

export interface CloudConnectionReport {
  connected: boolean;
  activeRoleMode: CloudRoleMode;
  configSource: string;
  latencyMs: number;
  serverVersion: string;
  postgisVersion?: string;
  database: string;
  sslMode: string;
  schemasBootstrapped: boolean;
  canReadMaster: boolean;
  canSubmitStaging: boolean;
  canMergeMaster: boolean;
  canBootstrapSchema: boolean;
  becmasterPlotCount: number;
  becmasterVegCount: number;
  pendingSubmissionCount: number;
  snapshotCount: number;
  latestSnapshotTag?: string;
  activeStandardsRelease?: string;
  activeBecVersion?: string;
  activeTaxonomyVersion?: string;
  activeVListsSha256?: string;
  checkedAt: string;
}

export interface SchemaBootstrapResult {
  schemaVersion: number;
  appliedMigrations: string[];
  schemasVerified: string[];
  postgisEnabled: boolean;
  pgcryptoEnabled: boolean;
  roleGrantsApplied: boolean;
  contributorRoleSet: boolean;
  bootstrappedAt: string;
}

export interface PublishStandardsRequest {
  releaseId?: string;
  becVersion?: string;
  taxonomyVersion?: string;
  vlistsPath?: string;
  becDbPath?: string;
  vmetaDataPath?: string;
  notes?: string;
}

export interface PublishStandardsResult {
  releaseId: string;
  becVersion: string;
  taxonomyVersion: string;
  vlistsSha256: string;
  becDbSha256: string;
  vmetaDataSha256: string;
  tableCounts: Record<string, number>;
  elapsedMs: number;
  publishedAt: string;
}

export interface SeedBaselineRequest {
  sourceDbPath: string;
  sourceProject?: string;
  snapshotTag?: string;
  replaceExisting: boolean;
  skipAudit?: boolean;
  notes?: string;
}

export interface SeedBaselineResult {
  sourceProject: string;
  sourceSha256: string;
  snapshotTag: string;
  plotCount: number;
  adminCount: number;
  vegCount: number;
  humusCount: number;
  mineralCount: number;
  otherCount: number;
  metadataCount: number;
  auditCount: number;
  childIdentityRows: number;
  tailAuditHash: string;
  elapsedMs: number;
  seededAt: string;
  tableCounts: Record<string, number>;
}

export interface PullStandardsResult {
  updated: boolean;
  alreadyCurrent: boolean;
  releaseId: string;
  becVersion: string;
  taxonomyVersion: string;
  localSha256: string;
  cloudSha256: string;
  publishedAt?: string;
  state?: unknown;
}

export interface SubsetFilter {
  zones?: string[];
  subzones?: string[];
  projectIds?: string[];
  plotNumbers?: string[];
  bbox?: number[];
  limit?: number;
  allowFullCheckout?: boolean;
}

export interface SubsetPreview {
  matchingPlots: number;
  matchingVeg: number;
  samplePlots: string[];
  zoneBreakdown: Record<string, number>;
}

export interface PullSubsetRequest {
  filter: SubsetFilter;
  targetProject: string;
  destinationPath?: string;
  activateOnSuccess: boolean;
}

export interface PullSubsetResult {
  targetProject: string;
  destinationPath: string;
  destinationSha256: string;
  plotCount: number;
  vegCount: number;
  humusCount: number;
  mineralCount: number;
  otherCount: number;
  metadataCount: number;
  downloadLogId: number;
  activated: boolean;
  state?: unknown;
}

export interface CloudUserSpeciesRecord {
  code: string;
  scientificName: string | null;
  lifeForm: number | null;
  englishName: string | null;
  report?: number;
  sppNumber?: number;
  codetype?: string;
}

export interface CloudUserSpeciesManifest {
  schemaVersion: string;
  exportedAt: string;
  sourceProject: string;
  rowCount: number;
  payloadSha256: string;
  species: CloudUserSpeciesRecord[];
}

export interface StagingPreflightPreview {
  project: string;
  projectId: string;
  plotCount: number;
  vegRowCount: number;
  sourceDbSha256: string;
  compliancePassed: boolean;
  blockingErrorCount: number;
  complianceSummary: Record<string, number>;
  complianceReport: unknown;
  userSpeciesManifest: CloudUserSpeciesManifest;
  lumpRowCount: number;
  suRowCount: number;
}

export interface SubmitStagingRequest {
  useActiveSu?: boolean;
  submitterNotes?: string;
  submittedBy?: string;
  baseSnapshotTag?: string;
  custodianOverride?: boolean;
}

export interface SubmitStagingResult {
  submissionId: string;
  projectName: string;
  projectId: string;
  submittedBy: string;
  dbRole: string;
  status: string;
  plotCount: number;
  vegRowCount: number;
  userSpeciesCount: number;
  sourceDbSha256: string;
  compliancePassed: boolean;
  submittedAt: string;
}

export interface ListSubmissionsFilter {
  status?: string;
  submittedBy?: string;
  limit?: number;
}

export interface StagingSubmissionSummary {
  submissionId: string;
  projectName: string;
  projectId?: string;
  submittedBy: string;
  dbRole: string;
  submittedAt: string;
  status: string;
  plotCount: number;
  vegRowCount: number;
  sourceDbSha256: string;
  compliancePassed: boolean;
  userSpeciesCount: number;
  lumpRowCount: number;
  suRowCount: number;
  submitterNotes?: string;
  baseSnapshotTag?: string;
  reviewerNotes?: string;
  reviewedBy?: string;
  reviewedAt?: string;
  mergedTxId?: string;
}

export interface ProvisionalSpeciesDiff {
  code: string;
  scientificName?: string;
  lifeForm?: number;
  status: string;
  officialCode?: string;
  officialScientific?: string;
}

export interface StagingSubmissionDetail {
  summary: StagingSubmissionSummary;
  complianceReport: unknown;
  userSpeciesManifest: CloudUserSpeciesManifest;
  provisionalSpeciesDiffs: ProvisionalSpeciesDiff[];
  lumpRows: { lumpCode: string; sppCode: string; use: boolean }[];
  suRows: { plotNumber: string; siteUnit: string | null }[];
}

export interface CloudMergeConflictItem {
  conflictId: string;
  plotNumber: string;
  table: string;
  key: string;
  field: string;
  baseVal?: string | null;
  sourceVal: string | null;
  targetVal: string | null;
  kind: string;
  defaultResolution: CloudMergeResolution;
  custodianProtected: boolean;
}

export interface CloudMergePlotPreview {
  plotNumber: string;
  category: string;
  items: CloudMergeConflictItem[];
}

export interface StagingMergePreviewRequest {
  submissionId: string;
  baseDbPath?: string;
  baseProject?: string;
}

export interface StagingMergePreview {
  submissionId: string;
  sourceProject: string;
  targetProject: string;
  baseDbPath?: string;
  baseProject?: string;
  previewDigest: string;
  addedCount: number;
  identicalCount: number;
  fastForwardCount: number;
  conflictCount: number;
  targetOnlyCount: number;
  elapsedMs: number;
  plots: CloudMergePlotPreview[];
  conflicts: CloudMergeConflictItem[];
  custodianProtectedDiffs: CloudMergeConflictItem[];
}

export interface StagingMergeExecuteRequest {
  submissionId: string;
  baseDbPath?: string;
  baseProject?: string;
  expectedPreviewDigest: string;
  defaultConflictResolution?: CloudMergeResolution;
  plotResolutions?: Record<string, CloudMergeResolution>;
  fieldResolutions?: Record<string, CloudMergeResolution>;
  reviewerNotes?: string;
  actor?: string;
}

export interface StagingMergeResult {
  mergeTxId: string;
  submissionId: string;
  sourceProject: string;
  addedPlots: number;
  updatedPlots: number;
  skippedPlots: number;
  allocatedChildIds: number[];
  reservedDeletedIds: number[];
  auditRowsWritten: number;
  tailAuditHash: string;
  mergedAt: string;
}

export interface RejectSubmissionRequest {
  submissionId: string;
  reviewerNotes: string;
  actor?: string;
}

export interface CreateSnapshotRequest {
  snapshotTag: string;
  notes?: string;
  exportFormat?: string;
  destinationPath?: string;
  zoneFilter?: string;
}

export interface SnapshotRecord {
  snapshotTag: string;
  createdAt: string;
  createdBy: string;
  plotCount: number;
  vegCount: number;
  becVersion: string;
  taxonomyVersion: string;
  manifestSha256: string;
  notes?: string;
  exportedPath?: string;
}

export interface DownloadLogEntry {
  id: number;
  downloadedAt: string;
  actor: string;
  roleTier: string;
  filterJson: unknown;
  format: string;
  plotCount: number;
}

export interface AuditChainVerification {
  verifiedRows: number;
  totalRows?: number;
  valid: boolean;
  partialWindow: boolean;
  tailHash: string;
}

export interface RememberedSessionOverrides {
  host: string;
  port: string;
  database: string;
  sslMode: string;
  user: string;
  adminUser: string;
}

let rememberedSessionOverrides: RememberedSessionOverrides | null = null;

export function getRememberedSessionOverrides(): RememberedSessionOverrides | null {
  return rememberedSessionOverrides ? { ...rememberedSessionOverrides } : null;
}

export function setRememberedSessionOverrides(next: RememberedSessionOverrides): void {
  rememberedSessionOverrides = {
    host: next.host,
    port: next.port,
    database: next.database,
    sslMode: next.sslMode,
    user: next.user,
    adminUser: next.adminUser,
  };
}

export function clearRememberedSessionOverrides(): void {
  rememberedSessionOverrides = null;
}

export function formatAuditChainBannerSummary(res: AuditChainVerification): string {
  const verified = Math.max(0, Math.trunc(Number(res.verifiedRows) || 0));
  const total =
    typeof res.totalRows === 'number' && Number.isFinite(res.totalRows) && res.totalRows >= verified
      ? Math.trunc(res.totalRows)
      : null;
  if (res.valid) {
    if (res.partialWindow) {
      if (total !== null && total > 0) {
        return `Verified latest ${verified.toLocaleString('en-US')} of ${total.toLocaleString('en-US')} rows (partial window)`;
      }
      return `Verified latest ${verified.toLocaleString('en-US')} rows (partial window)`;
    }
    if (verified === 0) {
      return 'Verified 0 rows (empty ledger anchored to genesis)';
    }
    return `Verified all ${verified.toLocaleString('en-US')} rows from genesis`;
  }
  const totalPart = total !== null && total > 0 ? ` of ${total.toLocaleString('en-US')}` : '';
  return `Verification failed after ${verified.toLocaleString('en-US')}${totalPart} rows (${res.partialWindow ? 'partial window' : 'full chain'})`;
}

export function formatAuditChainStatusMessage(res: AuditChainVerification): string {
  const verified = Math.max(0, Math.trunc(Number(res.verifiedRows) || 0));
  const total =
    typeof res.totalRows === 'number' && Number.isFinite(res.totalRows) && res.totalRows >= verified
      ? Math.trunc(res.totalRows)
      : null;
  const tailShort = res.tailHash ? res.tailHash.slice(0, 16) : 'empty';
  if (!res.valid) {
    return `BECMaster audit chain verification FAILED across ${verified.toLocaleString('en-US')} row(s).`;
  }
  if (res.partialWindow) {
    if (total !== null && total > 0) {
      return `BECMaster audit chain verified: latest ${verified.toLocaleString('en-US')} of ${total.toLocaleString('en-US')} row(s) valid (partial window, tail ${tailShort}).`;
    }
    return `BECMaster audit chain verified: latest ${verified.toLocaleString('en-US')} row(s) valid (partial window, tail ${tailShort}).`;
  }
  if (verified === 0) {
    return `BECMaster audit chain verified: 0 rows in ledger (anchored to genesis, tail ${tailShort}).`;
  }
  return `BECMaster audit chain verified from genesis: all ${verified.toLocaleString('en-US')} row(s) valid (tail ${tailShort}).`;
}

export interface CloudSyncPort {
  getCloudSyncConfigStatus(): Promise<CloudConfigStatus>;
  configureCloudSyncSession(req: SessionConfigRequest): Promise<CloudConfigStatus>;
  testCloudConnection(): Promise<CloudConnectionReport>;
  bootstrapCloudSchemas(): Promise<SchemaBootstrapResult>;
  verifyBECMasterAuditChain(limit?: number): Promise<AuditChainVerification>;
  publishStandardsToCloud(contextId: string, req: PublishStandardsRequest): Promise<PublishStandardsResult>;
  seedBECMasterBaseline(req: SeedBaselineRequest): Promise<SeedBaselineResult>;
  pullCloudStandards(contextId: string): Promise<PullStandardsResult>;
  previewBECMasterSubset(filter: SubsetFilter): Promise<SubsetPreview>;
  pullBECMasterSubset(contextId: string, req: PullSubsetRequest): Promise<PullSubsetResult>;
  previewStagingSubmission(contextId: string, useActiveSu: boolean): Promise<StagingPreflightPreview>;
  submitProjectToStaging(contextId: string, req: SubmitStagingRequest): Promise<SubmitStagingResult>;
  listStagingSubmissions(filter: ListSubmissionsFilter): Promise<StagingSubmissionSummary[]>;
  getStagingSubmissionDetail(submissionId: string): Promise<StagingSubmissionDetail>;
  previewStagingToMasterMerge(req: StagingMergePreviewRequest): Promise<StagingMergePreview>;
  executeStagingToMasterMerge(req: StagingMergeExecuteRequest): Promise<StagingMergeResult>;
  rejectStagingSubmission(req: RejectSubmissionRequest): Promise<StagingSubmissionSummary>;
  createBECMasterSnapshot(contextId: string, req: CreateSnapshotRequest): Promise<SnapshotRecord>;
  listBECMasterSnapshots(): Promise<SnapshotRecord[]>;
  listBECMasterDownloadLog(limit: number): Promise<DownloadLogEntry[]>;
}

export const defaultCloudSyncPort: CloudSyncPort = {
  getCloudSyncConfigStatus: () => (ContextService.GetCloudSyncConfigStatus() as never),
  configureCloudSyncSession: req => (ContextService.ConfigureCloudSyncSession(req) as never),
  testCloudConnection: () => (ContextService.TestCloudConnection() as never),
  bootstrapCloudSchemas: () => (ContextService.BootstrapCloudSchemas() as never),
  verifyBECMasterAuditChain: (limit = 0) => (ContextService.VerifyBECMasterAuditChain(limit) as never),
  publishStandardsToCloud: (contextId, req) => (ContextService.PublishStandardsToCloud(contextId, req) as never),
  seedBECMasterBaseline: req => (ContextService.SeedBECMasterBaseline(req) as never),
  pullCloudStandards: contextId => (ContextService.PullCloudStandards(contextId) as never),
  previewBECMasterSubset: filter => (ContextService.PreviewBECMasterSubset(filter) as never),
  pullBECMasterSubset: (contextId, req) => (ContextService.PullBECMasterSubset(contextId, req) as never),
  previewStagingSubmission: (contextId, useActiveSu) => (ContextService.PreviewStagingSubmission(contextId, useActiveSu) as never),
  submitProjectToStaging: (contextId, req) => (ContextService.SubmitProjectToStaging(contextId, req) as never),
  listStagingSubmissions: filter => (ContextService.ListStagingSubmissions(filter) as never),
  getStagingSubmissionDetail: submissionId => (ContextService.GetStagingSubmissionDetail(submissionId) as never),
  previewStagingToMasterMerge: req => (ContextService.PreviewStagingToMasterMerge(req) as never),
  executeStagingToMasterMerge: req => (ContextService.ExecuteStagingToMasterMerge(req) as never),
  rejectStagingSubmission: req => (ContextService.RejectStagingSubmission(req) as never),
  createBECMasterSnapshot: (contextId, req) => (ContextService.CreateBECMasterSnapshot(contextId, req) as never),
  listBECMasterSnapshots: () => (ContextService.ListBECMasterSnapshots() as never),
  listBECMasterDownloadLog: limit => (ContextService.ListBECMasterDownloadLog(limit) as never),
};

export interface SubsetFilterDraftInput {
  zonesRaw: string;
  subzonesRaw: string;
  projectIdsRaw: string;
  plotNumbersRaw: string;
  bboxRaw: string;
  limitRaw?: string | number | null | undefined;
  allowFullCheckout?: boolean;
}

export function parseSessionPortInput(raw: string | number | null | undefined): {
  port?: number;
  error: string | null;
} {
  const trimmed = String(raw ?? '').trim();
  if (trimmed === '') {
    return { port: undefined, error: null };
  }
  const parsed = Number(trimmed);
  if (!Number.isSafeInteger(parsed) || parsed < 1 || parsed > 65535) {
    return { error: 'Server port must be an integer between 1 and 65535.' };
  }
  return { port: parsed, error: null };
}

export function parseAuditChainLimitInput(raw: string | number | null | undefined): {
  limit: number;
  error: string | null;
} {
  const trimmed = String(raw ?? '').trim();
  if (trimmed === '') {
    return { limit: 0, error: null };
  }
  const parsed = Number(trimmed);
  if (!Number.isSafeInteger(parsed) || parsed < 0) {
    return { limit: 0, error: 'Audit limit must be a non-negative integer (0 = all).' };
  }
  return { limit: parsed, error: null };
}

export function parseBboxInput(raw: string | null | undefined): { bbox?: number[]; error: string | null } {
  const trimmed = String(raw ?? '').trim();
  if (trimmed === '') {
    return { bbox: undefined, error: null };
  }
  const parts = trimmed.split(/[\s,]+/).filter(Boolean);
  if (parts.length !== 4) {
    return { error: 'Bounding box requires 4 numbers: minLon, minLat, maxLon, maxLat.' };
  }
  const nums = parts.map(Number);
  if (nums.some(n => !Number.isFinite(n))) {
    return { error: 'Bounding box values must be finite decimal degrees.' };
  }
  const [minLon, minLat, maxLon, maxLat] = nums;
  if (minLon < -180 || maxLon > 180 || minLon >= maxLon) {
    return { error: 'Bounding box longitudes must satisfy -180 <= minLon < maxLon <= 180.' };
  }
  if (minLat < -90 || maxLat > 90 || minLat >= maxLat) {
    return { error: 'Bounding box latitudes must satisfy -90 <= minLat < maxLat <= 90.' };
  }
  return { bbox: [minLon, minLat, maxLon, maxLat], error: null };
}

export function buildSubsetFilterDraft(input: SubsetFilterDraftInput): { filter: SubsetFilter | null; error: string | null } {
  const zones = parseLiteralTokenList(input.zonesRaw);
  const subzones = parseLiteralTokenList(input.subzonesRaw);
  const projectIds = parseLiteralTokenList(input.projectIdsRaw);
  const plotNumbers = parseLiteralTokenList(input.plotNumbersRaw);

  for (const plot of plotNumbers) {
    if (!wellFormedUTF16(plot) || plot.includes('\0') || plot.length > 7) {
      return { filter: null, error: `Plot number "${plot}" exceeds 7 UTF-16 code units or contains invalid characters.` };
    }
  }

  const bboxParsed = parseBboxInput(input.bboxRaw);
  if (bboxParsed.error) {
    return { filter: null, error: bboxParsed.error };
  }

  let limit: number | undefined;
  const limitTrimmed = String(input.limitRaw ?? '').trim();
  if (limitTrimmed !== '') {
    const parsed = Number(limitTrimmed);
    if (!Number.isSafeInteger(parsed) || parsed <= 0) {
      return { filter: null, error: 'Subset plot limit must be a positive integer.' };
    }
    limit = parsed;
  }

  const allowFullCheckout = !!input.allowFullCheckout;
  const hasRegionalFilter =
    zones.length > 0 ||
    subzones.length > 0 ||
    projectIds.length > 0 ||
    plotNumbers.length > 0 ||
    !!bboxParsed.bbox;

  if (!hasRegionalFilter && !allowFullCheckout) {
    return {
      filter: null,
      error:
        'Specify at least one regional filter (Zone, Subzone, Project ID, Plot Number, or Bounding Box), or enable full checkout.',
    };
  }

  const filter: SubsetFilter = {};
  if (zones.length > 0) filter.zones = zones;
  if (subzones.length > 0) filter.subzones = subzones;
  if (projectIds.length > 0) filter.projectIds = projectIds;
  if (plotNumbers.length > 0) filter.plotNumbers = plotNumbers;
  if (bboxParsed.bbox) filter.bbox = bboxParsed.bbox;
  if (limit !== undefined) filter.limit = limit;
  if (allowFullCheckout) filter.allowFullCheckout = true;

  return { filter, error: null };
}

export function canUploadStagingSubmission(
  preflight: StagingPreflightPreview | null,
  activeRoleMode: CloudRoleMode,
  custodianOverride: boolean
): boolean {
  if (!preflight) return false;
  if (preflight.compliancePassed) return true;
  return activeRoleMode === 'custodian' && custodianOverride;
}

export function isCustodianProtectedConflict(item: Pick<CloudMergeConflictItem, 'field' | 'custodianProtected'>): boolean {
  if (item.custodianProtected) return true;
  const lower = item.field.toLowerCase();
  return CUSTODIAN_PROTECTED_FIELDS.some(f => f.toLowerCase() === lower);
}

export function buildInitialCloudMergeFieldResolutions(preview: StagingMergePreview): Record<string, CloudMergeResolution> {
  const map: Record<string, CloudMergeResolution> = {};
  for (const item of preview.custodianProtectedDiffs ?? []) {
    map[item.conflictId] = 'keep_target';
  }
  return map;
}

export const MAX_SNAPSHOT_TAG_LENGTH = 80;

export function validateSnapshotTagInput(raw: string): string | null {
  if (typeof raw !== 'string' || !wellFormedUTF16(raw) || raw.includes('\0')) {
    return 'Snapshot tag must be well-formed Unicode without NUL characters.';
  }
  const trimmed = raw.trim();
  if (trimmed === '' || trimmed !== raw) {
    return 'Snapshot tag is required and cannot contain leading or trailing spaces.';
  }
  if (!/^[A-Za-z0-9._-]{1,80}$/.test(trimmed)) {
    return 'Snapshot tag may use only ASCII letters, digits, dots, underscores, or hyphens (max 80 characters).';
  }
  return null;
}
