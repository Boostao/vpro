const { existsSync, readFileSync } = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');

const FIXTURES_DIR = path.join(__dirname, 'fixtures');

function resolveFixturePath(relOrAbsPath) {
  const raw = String(relOrAbsPath);
  const candidateBase = path.isAbsolute(raw)
    ? raw
    : path.join(FIXTURES_DIR, raw.replaceAll('\\', '/').replace(/^\.\//, '').replace(/^fixtures\//, ''));
  if (candidateBase.endsWith('.gz')) {
    if (existsSync(candidateBase)) return { filePath: candidateBase, gzipped: true };
    const plainPath = candidateBase.slice(0, -3);
    if (existsSync(plainPath)) return { filePath: plainPath, gzipped: false };
    throw new Error(`Fixture not found: ${candidateBase} (or ${plainPath})`);
  }
  const gzPath = `${candidateBase}.gz`;
  if (existsSync(gzPath)) return { filePath: gzPath, gzipped: true };
  if (existsSync(candidateBase)) return { filePath: candidateBase, gzipped: false };
  throw new Error(`Fixture not found: ${candidateBase} (or ${gzPath})`);
}

function readFixtureText(relOrAbsPath) {
  const { filePath, gzipped } = resolveFixturePath(relOrAbsPath);
  const bytes = readFileSync(filePath);
  return gzipped ? zlib.gunzipSync(bytes).toString('utf8') : bytes.toString('utf8');
}

function readJsonFixture(relOrAbsPath) {
  return JSON.parse(readFixtureText(relOrAbsPath));
}

module.exports = { readFixtureText, readJsonFixture, resolveFixturePath };
