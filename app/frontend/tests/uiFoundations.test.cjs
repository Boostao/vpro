const assert = require('node:assert/strict');
const { test } = require('node:test');
const { render } = require('svelte/server');
const { serverComponent, loadTypeScript, readSrc } = require('./svelteTestHelpers.cjs');

test('4-tier notification controller deduplicates rapid identical events, pauses/resumes timers, and tracks unread severity', () => {
  let clock = 10_000;
  const scheduled = new Map();
  let timerSeq = 0;

  const mod = loadTypeScript('shell/notificationService.svelte.ts', {
    'svelte/store': require('svelte/store'),
  });

  const ctrl = mod.createNotificationController({
    now: () => clock,
    schedule: (fn, ms) => {
      const id = ++timerSeq;
      scheduled.set(id, { fn, ms });
      return id;
    },
    cancelSchedule: (id) => {
      scheduled.delete(id);
    },
  });

  ctrl.success('Plot 00337 saved', 'Committed to Sample.db');
  clock += 500;
  ctrl.success('Plot 00337 saved', 'Committed to Sample.db');

  let snap = ctrl.getSnapshot();
  assert.equal(snap.entries.length, 1);
  assert.equal(snap.entries[0].repeatCount, 2);
  assert.equal(snap.toasts.length, 1);
  assert.equal(snap.toasts[0].repeatCount, 2);

  // Pause toast after 1000ms elapsed, advance clock, resume, and confirm remaining time
  const toastId = snap.toasts[0].id;
  clock += 1000;
  ctrl.pauseToast(toastId);
  assert.equal(ctrl.getSnapshot().toasts[0].paused, true);
  assert.equal(scheduled.size, 0);

  clock += 20_000; // Hovering for 20s does not dismiss while paused
  assert.equal(ctrl.getSnapshot().toasts.length, 1);

  ctrl.resumeToast(toastId);
  assert.equal(ctrl.getSnapshot().toasts[0].paused, false);
  assert.equal(scheduled.size, 1);
  const [armed] = [...scheduled.values()];
  assert.equal(armed.ms, 3500);
  armed.fn();
  assert.equal(ctrl.getSnapshot().toasts.length, 0);

  // Severity escalation & category filtering
  ctrl.push({ severity: 'warning', category: 'lmh25', title: 'rSMR divergence >= 2', message: 'Keyed 5 vs Field 2' });
  assert.equal(ctrl.getSnapshot().badgeSeverity, 'warning');

  ctrl.push({ severity: 'error', category: 'background', title: 'WMS offline', message: 'Using local PMTiles' });
  snap = ctrl.getSnapshot();
  assert.equal(snap.badgeSeverity, 'error');
  assert.equal(snap.unreadErrorCount, 1);
  assert.equal(snap.unreadWarningCount, 1);
  assert.equal(mod.filterNotificationEntries(snap.entries, 'errors').length, 1);
  assert.equal(mod.filterNotificationEntries(snap.entries, 'lmh25').length, 1);
  assert.equal(mod.filterNotificationEntries(snap.entries, 'background').length, 1);

  ctrl.markAllRead();
  assert.equal(ctrl.getSnapshot().unreadCount, 0);
  assert.equal(ctrl.getSnapshot().badgeSeverity, 'none');

  ctrl.clearHistory();
  assert.equal(ctrl.getSnapshot().entries.length, 0);
});

test('CommandPalette fuzzy search ranks exact leading-zero plot numbers first and SSRs cleanly', () => {
  const cmdMod = loadTypeScript('shell/commandPalette.ts');
  const catalog = cmdMod.buildCommandPaletteCatalog({
    plots: [
      { plotNumber: '00337', siteUnit: '01', zone: 'SBS', subZone: 'dk' },
      { plotNumber: '10442', siteUnit: '05', zone: 'CWH', subZone: 'vm1' },
    ],
    projects: [{ name: 'Sample', file: 'Sample.db', active: true, compatible: true }],
    sus: [{ index: 0, name: 'Sample_SU', active: true, compatible: true }],
    activeSU: 'Sample_SU',
    metadataAvailable: false,
  });

  const exactPlot = cmdMod.searchCommandPalette(catalog, '00337');
  assert.ok(exactPlot.length >= 3);
  assert.equal(exactPlot[0].action.kind, 'open-plot-fs882');
  assert.equal(exactPlot[0].action.plotNumber, '00337');

  const rsmrHits = cmdMod.searchCommandPalette(catalog, 'rsmr');
  assert.ok(rsmrHits.some((item) => item.category === 'help' && item.title.includes('rSMR')));

  const lucideStub = new Proxy({}, { get: () => () => {} });
  const PaletteComp = serverComponent(readSrc('shell/CommandPalette.svelte'), 'CommandPalette.svelte', {
    './commandPalette': cmdMod,
    '@lucide/svelte': lucideStub,
  });
  const html = render(PaletteComp, {
    props: {
      open: true,
      catalogInput: { plots: [{ plotNumber: '00337', siteUnit: '01' }] },
      onselect() {},
      onclose() {},
    },
  }).body;
  assert.match(html, /data-command-palette/);
  assert.match(html, /Plot 00337/);

  const notifMod = loadTypeScript('shell/notificationService.svelte.ts', { 'svelte/store': require('svelte/store') });
  const notifCtrl = notifMod.createNotificationController({ schedule: () => 1, cancelSchedule: () => {} });
  notifCtrl.success('Workbook exported', 'Sample_Summary.xlsx');
  const notifDeps = {
    './notificationService.svelte': notifMod,
    '@lucide/svelte': lucideStub,
  };
  const HostComp = serverComponent(readSrc('shell/NotificationHost.svelte'), 'NotificationHost.svelte', notifDeps);
  assert.match(render(HostComp, { props: { controller: notifCtrl } }).body, /data-notification-toast-host/);
  const DrawerComp = serverComponent(readSrc('shell/NotificationDrawer.svelte'), 'NotificationDrawer.svelte', notifDeps);
  assert.match(render(DrawerComp, { props: { open: true, controller: notifCtrl, onclose() {} } }).body, /data-notification-drawer/);

  const tokensCss = readSrc('tokens.css');
  assert.match(tokensCss, /--vpro-navy:\s*#003366/);
  assert.match(tokensCss, /--vpro-gold:\s*#fcba19/);
  assert.match(tokensCss, /\/fonts\/BCSans-Regular\.woff2/);
});
