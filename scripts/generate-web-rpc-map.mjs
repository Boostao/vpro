#!/usr/bin/env node
/**
 * Build-time generator & validator for the VPro Web Read-Only RPC map.
 *
 * Reads:
 *   - app/resources/web_rpc_allowlist.json
 *   - app/frontend/bindings/github.com/boostao/vpro/app/{index,*service}.ts
 *
 * Emits:
 *   - app/frontend/src/web/generatedRpcMap.ts
 *
 * Usage:
 *   node scripts/generate-web-rpc-map.mjs          # generate/update TS map
 *   node scripts/generate-web-rpc-map.mjs --check  # verify up-to-date & valid (CI)
 */

import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
export const REPO_ROOT = path.resolve(__dirname, '..');
export const ALLOWLIST_PATH = path.join(REPO_ROOT, 'app', 'resources', 'web_rpc_allowlist.json');
export const BINDINGS_DIR = path.join(
  REPO_ROOT,
  'app',
  'frontend',
  'bindings',
  'github.com',
  'boostao',
  'vpro',
  'app'
);
export const OUTPUT_PATH = path.join(REPO_ROOT, 'app', 'frontend', 'src', 'web', 'generatedRpcMap.ts');

export const ALLOWED_KINDS = new Set(['rpc', 'prefs', 'download']);

/**
 * Fail-closed denylist patterns checked against EVERY allowlisted Service.Method.
 * Any match fails code generation immediately unless explicitly narrowed to a verified
 * in-memory preference or read-only query exception.
 */
export const FORBIDDEN_METHOD_PREFIX_RE =
  /^(?:Add|Apply|Assign|Attach|Begin|Bootstrap|Cancel|Choose|Close|Compare|Complete|Confirm|Configure|Create|Delete|Ensure|Execute|Import|Insert|Inspect|Materialize|Merge|Open|Promote|Publish|Pull|Quarantine|QuickRun|Reassign|Record|Recover|Reject|Release|Reload|Rename|Reparent|Reset|Restore|Reveal|Seed|SignOut|Splinter|Submit|Sync|TestCloud|Toggle|Transfer|Unattach|Undo|Update|Upsert|VerifyBECMaster)/;

export const FORBIDDEN_METHOD_SUBSTRING_RE =
  /(?:UserLog|UserSetup|UserAccreditation|Cloud|Staging|BECMaster|DeletionHistory|DeletedRow|DeletedHorizon|UndoHistory|Receipt|Splinter|ThreeWayMerge|PendingClose|CreationImage|CreationSelection|PictureOptions$|MetadataRestore|PlotProfileFileCreation|PlotProfileTableCreation|SpeciesCodeCheck|VegetationDeletion)/i;

const AUDIT_SUBSTRING_RE = /Audit/i;
const ALLOWED_AUDIT_EXCEPTIONS = new Set(['SpatialService.BatchAuditSpatialQA']);

const ALLOWED_BECMASTER_READ_EXCEPTIONS = new Set([
  'SpatialService.GetBECMasterFilterOptions',
  'SpatialService.FilterBECMasterPlots',
]);

const ALLOWED_SAVE_PREFS_RE =
  /^Save(?:LongVegetation(?:[A-Za-z]*Preferences|ProjectUnits)|SummaryVegetation(?:Presentation|Quality)?Preferences|FullSiteUnitSummaryPreferences|SiteUnitSummaryPreferences|LongEnvironmentPreferences|GoogleEarthPreferences)$/;

const ALLOWED_SET_PREFS_RE =
  /^Set(?:CoordinateMode|WorkingUnitMode|LongVegetation(?:ProjectFields|ReportScope|SelectedUnitFields))$/;

const ALLOWED_SELECT_READ_EXCEPTIONS = new Set(['SpatialService.SelectPlotsInPolygonAOI']);

const ALLOWED_GET_PICTURE_OPTIONS_EXCEPTION = 'PictureService.GetPictureOptions';

const ALLOWED_QUICKRUN_DOWNLOAD_EXCEPTIONS = new Set([
  'VegetationReportService.QuickRunSummaryVegetationWorkbook',
  'VegetationReportService.QuickRunLongVegetationWorkbook',
  'VegetationReportService.QuickRunLifeformWorkbook',
  'EnvironmentReportService.QuickRunLongEnvironmentWorkbook',
  'EnvironmentReportService.QuickRunSummaryEnvironmentWorkbook',
  'EnvironmentReportService.QuickRunSubzoneMatrixWorkbook',
]);

/**
 * Returns a non-empty denial reason string if (service, method, kind) violates
 * the fail-closed read-only policy, or null if permitted.
 */
export function checkDenylist(service, method, kind) {
  const qualified = `${service}.${method}`;

  if (!ALLOWED_KINDS.has(kind)) {
    return `${qualified}: invalid kind "${kind}" (must be rpc | prefs | download)`;
  }

  const isAllowedQuickRunDownload =
    kind === 'download' && ALLOWED_QUICKRUN_DOWNLOAD_EXCEPTIONS.has(qualified);

  if (!isAllowedQuickRunDownload && FORBIDDEN_METHOD_PREFIX_RE.test(method)) {
    return `${qualified}: matches forbidden mutating/admin/cloud/dialog prefix`;
  }

  if (
    qualified !== ALLOWED_GET_PICTURE_OPTIONS_EXCEPTION &&
    !ALLOWED_BECMASTER_READ_EXCEPTIONS.has(qualified) &&
    FORBIDDEN_METHOD_SUBSTRING_RE.test(method)
  ) {
    return `${qualified}: matches forbidden audit/cloud/user-setup/receipt/recovery substring`;
  }

  if (AUDIT_SUBSTRING_RE.test(method) && !ALLOWED_AUDIT_EXCEPTIONS.has(qualified)) {
    return `${qualified}: audit methods are forbidden in web read-only mode`;
  }

  if (method.startsWith('Save')) {
    if (kind !== 'prefs' || !ALLOWED_SAVE_PREFS_RE.test(method)) {
      return `${qualified}: Save* method is not an approved ephemeral in-memory DesktopConfig preference`;
    }
  }

  if (method.startsWith('Set')) {
    if (kind !== 'prefs' || !ALLOWED_SET_PREFS_RE.test(method)) {
      return `${qualified}: Set* method is not an approved ephemeral in-memory preference/scope setter`;
    }
  }

  if (method.startsWith('Select') && !ALLOWED_SELECT_READ_EXCEPTIONS.has(qualified)) {
    return `${qualified}: Select* disk/context switching is forbidden (use stateless SwitchContext)`;
  }

  if (method.startsWith('Acknowledge') && qualified !== 'HelpService.AcknowledgeWhatsNew') {
    return `${qualified}: Acknowledge* is forbidden except ephemeral HelpService.AcknowledgeWhatsNew`;
  }

  if (
    kind === 'download' &&
    !method.startsWith('Export') &&
    method !== 'RenderQuartoGuide' &&
    !isAllowedQuickRunDownload
  ) {
    return `${qualified}: download kind is restricted to read-only Export* / RenderQuartoGuide / approved QuickRun*Workbook methods`;
  }

  return null;
}

/**
 * Parses Wails v3 generated TypeScript service bindings in BINDINGS_DIR.
 * Returns Map<serviceName, Map<methodName, numericID>>.
 */
export function parseBindings(bindingsDir = BINDINGS_DIR) {
  const indexPath = path.join(bindingsDir, 'index.ts');
  const indexSrc = readFileSync(indexPath, 'utf8');
  const serviceFiles = new Map();

  const importRe = /^import\s+\*\s+as\s+([A-Za-z0-9_]+)\s+from\s+"\.\/([a-z0-9_]+)\.js";/gm;
  for (const match of indexSrc.matchAll(importRe)) {
    const [, serviceName, baseName] = match;
    serviceFiles.set(serviceName, path.join(bindingsDir, `${baseName}.ts`));
  }

  if (serviceFiles.size === 0) {
    throw new Error(`No service bindings found in ${indexPath}`);
  }

  const services = new Map();
  const fnBlockRe =
    /^export\s+function\s+([A-Za-z0-9_]+)\s*\([^\n]*\)\s*:\s*\$CancellablePromise<[^\n]+>\s*\{\r?\n\s*return\s+\$Call\.ByID\((\d+)\b/gm;

  for (const [serviceName, filePath] of serviceFiles.entries()) {
    const src = readFileSync(filePath, 'utf8');
    const methods = new Map();
    const expectedCount = (src.match(/^export\s+function\s+/gm) || []).length;
    for (const match of src.matchAll(fnBlockRe)) {
      const [, methodName, rawId] = match;
      const id = Number(rawId);
      if (!Number.isSafeInteger(id)) {
        throw new Error(`Unsafe RPC ID ${rawId} for ${serviceName}.${methodName}`);
      }
      if (methods.has(methodName)) {
        throw new Error(`Duplicate method ${serviceName}.${methodName} in ${filePath}`);
      }
      methods.set(methodName, id);
    }
    if (methods.size !== expectedCount) {
      throw new Error(
        `Parsed ${methods.size} of ${expectedCount} exported functions in ${filePath}; check binding parser`
      );
    }
    services.set(serviceName, methods);
  }

  return services;
}

/**
 * Validates allowlist against parsed bindings & denylist and builds deterministic TS output.
 */
export function buildRpcMap(allowlist, bindings) {
  if (!allowlist || typeof allowlist !== 'object' || !allowlist.services || typeof allowlist.services !== 'object') {
    throw new Error('Allowlist JSON must contain a top-level "services" object');
  }

  const entries = [];
  const seenIds = new Map();
  const errors = [];
  const counts = { rpc: 0, prefs: 0, download: 0, total: 0 };

  const serviceNames = Object.keys(allowlist.services).sort();
  for (const serviceName of serviceNames) {
    const bindingMethods = bindings.get(serviceName);
    if (!bindingMethods) {
      errors.push(`Allowlisted service "${serviceName}" does not exist in Wails bindings`);
      continue;
    }

    const methodMap = allowlist.services[serviceName];
    if (!methodMap || typeof methodMap !== 'object' || Array.isArray(methodMap)) {
      errors.push(`Allowlisted service "${serviceName}" must map method names to kinds`);
      continue;
    }

    const methodNames = Object.keys(methodMap).sort();
    for (const methodName of methodNames) {
      const kind = methodMap[methodName];
      const denial = checkDenylist(serviceName, methodName, kind);
      if (denial) {
        errors.push(`DENYLIST VIOLATION: ${denial}`);
        continue;
      }

      if (!bindingMethods.has(methodName)) {
        errors.push(`Allowlisted method "${serviceName}.${methodName}" not found in Wails bindings`);
        continue;
      }

      const id = bindingMethods.get(methodName);
      if (seenIds.has(id)) {
        errors.push(`Duplicate Wails ByID ${id} between ${seenIds.get(id)} and ${serviceName}.${methodName}`);
        continue;
      }
      seenIds.set(id, `${serviceName}.${methodName}`);

      entries.push({ id, service: serviceName, method: methodName, kind });
      counts[kind] += 1;
      counts.total += 1;
    }
  }

  if (errors.length > 0) {
    throw new Error(`Web RPC allowlist validation failed:\n  - ${errors.join('\n  - ')}`);
  }

  entries.sort((a, b) => a.id - b.id);
  const byNameEntries = [...entries].sort((a, b) =>
    `${a.service}.${a.method}`.localeCompare(`${b.service}.${b.method}`)
  );

  const lines = [
    '// Code generated by scripts/generate-web-rpc-map.mjs from app/resources/web_rpc_allowlist.json. DO NOT EDIT.',
    '',
    "export type WebRpcKind = 'rpc' | 'prefs' | 'download';",
    '',
    'export interface WebRpcEntry {',
    '  readonly id: number;',
    '  readonly service: string;',
    '  readonly method: string;',
    '  readonly kind: WebRpcKind;',
    '}',
    '',
    'export const WEB_RPC_BY_ID: Readonly<Record<number, WebRpcEntry>> = Object.freeze({',
  ];

  const quote = (value) => `'${value.replaceAll('\\', '\\\\').replaceAll("'", "\\'")}'`;

  for (const entry of entries) {
    const singleLine = `  ${entry.id}: Object.freeze({ id: ${entry.id}, service: ${quote(entry.service)}, method: ${quote(entry.method)}, kind: ${quote(entry.kind)} }),`;
    if (singleLine.length <= 120) {
      lines.push(singleLine);
    } else {
      lines.push(
        `  ${entry.id}: Object.freeze({`,
        `    id: ${entry.id},`,
        `    service: ${quote(entry.service)},`,
        `    method: ${quote(entry.method)},`,
        `    kind: ${quote(entry.kind)},`,
        '  }),'
      );
    }
  }

  lines.push('});', '', 'export const WEB_RPC_BY_NAME: Readonly<Record<string, WebRpcEntry>> = Object.freeze({');

  for (const entry of byNameEntries) {
    lines.push(`  ${quote(`${entry.service}.${entry.method}`)}: WEB_RPC_BY_ID[${entry.id}],`);
  }

  lines.push('});', '');

  return {
    source: lines.join('\n'),
    entries,
    counts,
  };
}

function main() {
  const checkMode = process.argv.includes('--check');
  const allowlist = JSON.parse(readFileSync(ALLOWLIST_PATH, 'utf8'));
  const bindings = parseBindings(BINDINGS_DIR);
  const { source, counts } = buildRpcMap(allowlist, bindings);

  if (checkMode) {
    if (!existsSync(OUTPUT_PATH)) {
      console.error(
        `[generate-web-rpc-map] Missing generated file: ${path.relative(REPO_ROOT, OUTPUT_PATH)}. Run: node scripts/generate-web-rpc-map.mjs`
      );
      process.exit(1);
    }
    const existing = readFileSync(OUTPUT_PATH, 'utf8');
    if (existing !== source) {
      console.error(
        `[generate-web-rpc-map] ${path.relative(REPO_ROOT, OUTPUT_PATH)} is out of date with app/resources/web_rpc_allowlist.json or bindings. Run: node scripts/generate-web-rpc-map.mjs`
      );
      process.exit(1);
    }
    console.log(
      `[generate-web-rpc-map] OK (${counts.total} allowlisted RPCs: ${counts.rpc} rpc, ${counts.prefs} prefs, ${counts.download} download)`
    );
    return;
  }

  mkdirSync(path.dirname(OUTPUT_PATH), { recursive: true });
  writeFileSync(OUTPUT_PATH, source, 'utf8');
  console.log(
    `[generate-web-rpc-map] Wrote ${path.relative(REPO_ROOT, OUTPUT_PATH)} (${counts.total} allowlisted RPCs: ${counts.rpc} rpc, ${counts.prefs} prefs, ${counts.download} download)`
  );
}

if (process.argv[1] && path.resolve(process.argv[1]) === __filename) {
  main();
}
