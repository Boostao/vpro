const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync } = require('node:fs');
const { compile } = require('svelte/compiler');
const { render } = require('svelte/server');
const { serverComponent, loadTypeScript, srcPath } = require('./svelteTestHelpers.cjs');

const iconsProxy = new Proxy({}, { get: () => () => {} });
const help = loadTypeScript('helpSystem.ts', {
  '@wailsio/runtime': { Call: { ByName: () => Promise.resolve({}) } },
});

const sampleWhatsNew = {
  latestVersion: '2.1.0',
  lastSeenVersion: '2.0.0',
  hasUnread: true,
  unreadCount: 1,
  entries: [
    {
      version: '2.1.0',
      date: '2026-11-26',
      channel: 'stable',
      highlights: ['Unified Work Space sidebar with dropdowns for Project, Site Unit, and Hierarchy.'],
    },
  ],
};

test('HomeWorkspaceHub compiles cleanly with BC Gov styling, zero emojis, minimal What\'s New opening screen, and buildMode tier gating', () => {
  const source = readFileSync(srcPath('HomeWorkspaceHub.svelte'), 'utf8');
  assert.doesNotMatch(source, /[\u{1F300}-\u{1FAFF}]/u, 'must contain zero emojis');
  assert.doesNotMatch(source, /disposable|during migration|Not yet a complete Access replacement/i);
  assert.match(source, /#003366|vpro-navy/);
  assert.match(source, /#FCBA19|vpro-gold/i);

  const compiled = compile(source, { filename: 'HomeWorkspaceHub.svelte', generate: 'client' });
  assert.deepEqual(compiled.warnings, []);

  const Hub = serverComponent(source, 'HomeWorkspaceHub.svelte', {
    '@lucide/svelte': iconsProxy,
    '../help/helpSystem': help,
    '../web/runtimeMode': { IS_WEB_READONLY: false },
  });

  // 1. Release mode: minimal opening screen showing only What's New, zero dev/alpha tier banner, zero cluttered workflow cards
  const releaseHtml = render(Hub, {
    props: {
      whatsNewStatus: sampleWhatsNew,
      buildMode: 'release',
      appVersion: '2.1.0',
      onhelpaction: () => {},
    },
  }).body;
  assert.doesNotMatch(releaseHtml, /data-home-tier-banner/);
  assert.doesNotMatch(releaseHtml, /data-home-workflow=/);
  assert.match(releaseHtml, /data-opening-whats-new/);
  assert.match(releaseHtml, /What's New in VPro/);
  assert.match(releaseHtml, /Version 2\.1\.0/);
  assert.match(releaseHtml, /Mark v2\.1\.0 as Read/);

  // 2. Alpha mode: client evaluation banner + SHA256SUMS notice, zero dev path clutter
  const alphaHtml = render(Hub, {
    props: {
      whatsNewStatus: sampleWhatsNew,
      buildMode: 'alpha',
      appVersion: '2.1.0-alpha.1',
    },
  }).body;
  assert.match(alphaHtml, /data-home-tier-banner="alpha"/);
  assert.match(alphaHtml, /VPro Alpha Preview \(v2\.1\.0-alpha\.1\)/);
  assert.match(alphaHtml, /SHA256SUMS\.txt/);
  assert.doesNotMatch(alphaHtml, /DEV BUILD/);

  // 3. Dev mode: compact dev banner with version and short commit
  const devHtml = render(Hub, {
    props: {
      whatsNewStatus: sampleWhatsNew,
      buildMode: 'dev',
      appVersion: '2.0.0-dev',
      gitCommit: '30e86f6abcdef',
      releaseChannel: 'stable',
      onhelpaction: () => {},
    },
  }).body;
  assert.match(devHtml, /data-home-tier-banner="dev"/);
  assert.match(devHtml, /DEV BUILD · v2\.0\.0-dev · 30e86f6/);
});

test('App and Navigation embed minimal opening HomeWorkspaceHub and clean BEC workflow terminology', () => {
  const { readShellComposite } = require('./svelteTestHelpers.cjs');
  const app = readShellComposite();
  const navigation = readFileSync(srcPath('Navigation.svelte'), 'utf8');
  assert.match(app, /HomeWorkspaceHub/);
  assert.doesNotMatch(app, /DemoReadiness/);
  assert.doesNotMatch(navigation, /Unavailable workflows are disabled/);
  assert.doesNotMatch(navigation, /only verified workflows are writable/);
});
