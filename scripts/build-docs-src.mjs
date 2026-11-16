#!/usr/bin/env node
/**
 * Single-source help & documentation compiler (Option 1).
 *
 * Source of truth: `docs-src/*.json`
 *   - docs-src/lmh25_fields.json
 *   - docs-src/guides.json
 *   - docs-src/tours.json
 *   - docs-src/shortcuts.json
 *   - docs-src/whats_new.json
 *   - docs-src/data_use_agreement.json
 *
 * `whatsNew` Release Notes Condenser Rules (see CONTRIBUTING.md §6–7):
 *   1. Edit `docs-src/whats_new.json` (newest release at index 0) BEFORE tagging `vX.Y.Z`.
 *   2. Condense commits/PRs into 4–7 workflow-themed bullets led by user outcomes.
 *   3. Use plain CBC-level language focused on feature shape; avoid libraries, SQL locks,
 *      internal `__VPRO_*` tables, contract codes, and millisecond micro-benchmarks.
 *   4. Run `node scripts/build-docs-src.mjs` to compile `app/resources/help_bundle.json`.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..');
const docsSrcDir = path.join(repoRoot, 'docs-src');
const outBundlePath = path.join(repoRoot, 'app', 'resources', 'help_bundle.json');

const EMOJI_RE = /\p{Extended_Pictographic}/u;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(`docs-src validation failed: ${message}`);
  }
}

function assertNoEmoji(value, contextPath) {
  if (typeof value === 'string') {
    assert(!EMOJI_RE.test(value), `emoji not allowed at ${contextPath}`);
    return;
  }
  if (Array.isArray(value)) {
    value.forEach((item, idx) => assertNoEmoji(item, `${contextPath}[${idx}]`));
    return;
  }
  if (value && typeof value === 'object') {
    for (const [k, v] of Object.entries(value)) {
      assertNoEmoji(v, `${contextPath}.${k}`);
    }
  }
}

const provenance = readJson(path.join(repoRoot, 'app', 'resources', 'standards-2026-provenance.json'));
const lmh25Doc = readJson(path.join(docsSrcDir, 'lmh25_fields.json'));
const guides = readJson(path.join(docsSrcDir, 'guides.json'));
const tours = readJson(path.join(docsSrcDir, 'tours.json'));
const shortcuts = readJson(path.join(docsSrcDir, 'shortcuts.json'));
const whatsNew = readJson(path.join(docsSrcDir, 'whats_new.json'));
const dataUseAgreement = readJson(path.join(docsSrcDir, 'data_use_agreement.json'));

const fields = lmh25Doc?.fields;
const decisionKeys = lmh25Doc?.decisionKeys;

assert(Array.isArray(fields) && fields.length >= 15, `expected >= 15 LMH25 fields, got ${fields?.length}`);
assert(Array.isArray(decisionKeys) && decisionKeys.length === 3, `expected 3 decisionKeys, got ${decisionKeys?.length}`);
assert(Array.isArray(guides) && guides.length === 6, `expected 6 guides, got ${guides?.length}`);
assert(Array.isArray(tours) && tours.length === 4, `expected 4 tours, got ${tours?.length}`);
assert(Array.isArray(shortcuts) && shortcuts.length >= 7, `expected >= 7 shortcuts, got ${shortcuts?.length}`);
assert(Array.isArray(whatsNew) && whatsNew.length >= 1, 'whats_new.json must contain at least 1 entry');

whatsNew.forEach((entry, idx) => {
  assert(entry && typeof entry === 'object', `whatsNew[${idx}] must be an object`);
  assert(typeof entry.version === 'string' && entry.version.trim().length > 0, `whatsNew[${idx}].version is required`);
  assert(typeof entry.date === 'string' && DATE_RE.test(entry.date), `whatsNew[${idx}].date must match YYYY-MM-DD`);
  assert(entry.channel === 'stable' || entry.channel === 'preview', `whatsNew[${idx}].channel must be 'stable' or 'preview'`);
  assert(
    Array.isArray(entry.highlights) &&
      entry.highlights.length > 0 &&
      entry.highlights.every((h) => typeof h === 'string' && h.trim().length > 0),
    `whatsNew[${idx}].highlights must be a non-empty array of strings`
  );
});

assert(
  dataUseAgreement &&
    typeof dataUseAgreement === 'object' &&
    Array.isArray(dataUseAgreement.clauses) &&
    dataUseAgreement.clauses.length === 9,
  `data_use_agreement.json must contain 9 clauses, got ${dataUseAgreement?.clauses?.length}`
);

const bundle = {
  schemaVersion: 1,
  productName: 'VPro',
  fullName: 'VENUS — Vegetation and Environment NexUS — Professional',
  organization: 'B.C. Ministry of Forests, Research Branch — Biogeoclimatic Ecosystem Classification (BEC) Program',
  lmh25Edition: 'LMH25 (2023)',
  provenance,
  fields,
  decisionKeys,
  guides,
  tours,
  shortcuts,
  whatsNew,
  dataUseAgreement,
};

assertNoEmoji(bundle, 'help_bundle');

fs.writeFileSync(outBundlePath, JSON.stringify(bundle, null, 2) + '\n');
console.log(
  `Compiled docs-src/ (${fields.length} LMH25 fields, ${decisionKeys.length} keys, ${guides.length} guides, ${tours.length} tours) -> app/resources/help_bundle.json`
);
