const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');

const FE_ROOT = path.resolve(__dirname, '..');
const SRC_ROOT = path.join(FE_ROOT, 'src');
const TESTS_ROOT = path.join(FE_ROOT, 'tests');

function walkFiles(dir, pred) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) return walkFiles(full, pred);
    return pred(entry.name) ? [full] : [];
  });
}

test('ENG-BASELINE-007: .npmrc uses npm 11 native min-release-age without deprecated minimum-release-age', () => {
  const npmrc = fs.readFileSync(path.join(FE_ROOT, '.npmrc'), 'utf8');
  assert.doesNotMatch(npmrc, /\bminimum-release-age\b/);
  assert.match(npmrc, /^min-release-age=7$/m);
});

test('ENG-FE-010: package.json has zero unreferenced direct dependencies and zero truly-dead value exports', () => {
  const pkg = JSON.parse(fs.readFileSync(path.join(FE_ROOT, 'package.json'), 'utf8'));
  const deps = Object.keys(pkg.dependencies || {});
  for (const unreferenced of [
    '@fontsource/ibm-plex-mono',
    '@fontsource/ibm-plex-sans',
    '@luma.gl/core',
    '@luma.gl/webgpu',
    '@deck.gl/core',
  ]) {
    assert.equal(deps.includes(unreferenced), false, `Unreferenced dependency ${unreferenced} must not remain in package.json`);
  }

  const srcFiles = walkFiles(SRC_ROOT, (n) => /\.(svelte|ts)$/.test(n));
  const testFiles = walkFiles(TESTS_ROOT, (n) => /\.(cjs|js)$/.test(n));
  const identRe = /[A-Za-z0-9_$]+/g;

  const fileTokens = new Map();
  const totalSrcCounts = new Map();
  for (const f of srcFiles) {
    const text = fs.readFileSync(f, 'utf8');
    const local = new Map();
    for (const m of text.matchAll(identRe)) {
      const k = m[0];
      local.set(k, (local.get(k) || 0) + 1);
      totalSrcCounts.set(k, (totalSrcCounts.get(k) || 0) + 1);
    }
    fileTokens.set(f, { text, local });
  }

  const testTokens = new Set();
  for (const tf of testFiles) {
    if (path.basename(tf) === 'designTokensAndDeadCode.test.cjs') continue;
    for (const m of fs.readFileSync(tf, 'utf8').matchAll(identRe)) {
      testTokens.add(m[0]);
    }
  }

  const expRe = /export\s+(?:async\s+)?(function\*?|const|let|class|enum)\s+([A-Za-z0-9_$]+)/g;
  const deadValueExports = [];
  for (const [f, { text, local }] of fileTokens.entries()) {
    for (const m of text.matchAll(expRe)) {
      const name = m[2];
      const outside = (totalSrcCounts.get(name) || 0) - (local.get(name) || 0);
      if (outside === 0 && !testTokens.has(name)) {
        deadValueExports.push(`${path.relative(FE_ROOT, f)}: ${name}`);
      }
    }
  }
  assert.deepEqual(deadValueExports, [], `Found unreferenced value exports:\n${deadValueExports.join('\n')}`);
});

test('ENG-FE-010 & ENG-FE-011: tokens.css, vpro.css @theme, and workbenches.css enforce semantic vpro-* tokens with zero dead selectors', () => {
  const tokensCss = fs.readFileSync(path.join(SRC_ROOT, 'tokens.css'), 'utf8');
  const vproCss = fs.readFileSync(path.join(SRC_ROOT, 'vpro.css'), 'utf8');
  const wbCss = fs.readFileSync(path.join(SRC_ROOT, 'styles', 'workbenches.css'), 'utf8');

  assert.doesNotMatch(tokensCss, /--bcgov-/);
  assert.doesNotMatch(vproCss, /--bcgov-/);

  const colorTokens = [...tokensCss.matchAll(/^\s*(--vpro-(?!font-|radius-|shadow-)[a-z0-9-]+)\s*:/gm)].map((m) => m[1]);
  assert.ok(colorTokens.length >= 29, `Expected >= 29 color tokens in tokens.css, found ${colorTokens.length}`);
  for (const tok of colorTokens) {
    const themeKey = tok.replace(/^--vpro-/, '--color-vpro-');
    assert.ok(
      vproCss.includes(`${themeKey}: var(${tok})`),
      `vpro.css @theme must map ${themeKey}: var(${tok})`,
    );
  }

  for (const deadSelector of [
    '.notif-badge-error',
    '.notif-badge-warning',
    '.notif-badge-info',
    '.ctx-status-ready',
    '.ctx-status-dirty',
    '.ctx-status-busy',
    '.home-summary',
    '.home-count',
    '.home-overview-wrap',
    '.error-dismiss',
    '.form-status',
    '.fs882-editor-host',
    '.wb-alert-error',
    '.wb-alert-info',
  ]) {
    assert.equal(vproCss.includes(deadSelector), false, `Dead selector ${deadSelector} still in vpro.css`);
    assert.equal(wbCss.includes(deadSelector), false, `Dead selector ${deadSelector} still in workbenches.css`);
  }

  assert.doesNotMatch(vproCss, /#[0-9a-fA-F]{3,8}\b/, 'vpro.css must use var(--vpro-*) rather than raw hex literals');
  assert.doesNotMatch(wbCss, /#[0-9a-fA-F]{3,8}\b/, 'workbenches.css must use var(--vpro-*) rather than raw hex literals');
});
