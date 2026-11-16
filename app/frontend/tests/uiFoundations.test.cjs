const assert = require('node:assert/strict');
const { test } = require('node:test');
const { compile } = require('svelte/compiler');
const { render } = require('svelte/server');
const { serverComponent, loadTypeScript, readSrc, srcPath } = require('./svelteTestHelpers.cjs');

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

test('notificationService filters entry/reports/background/admin/lmh25, preserves contextTag & action on dedupe, and triggers actions', () => {
  let clock = 50_000;
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

  let triggeredCount = 0;
  const action = {
    label: 'Open Plot 00337',
    onTrigger: () => {
      triggeredCount++;
    },
  };

  // New push + dedupe while toast is active preserves contextTag & action
  const first = ctrl.push({
    severity: 'warning',
    category: 'entry',
    title: 'Plot saved with warning',
    message: 'Check stratum cover',
    source: 'FS882',
    contextTag: 'Plot 00337',
    action,
    toast: true,
  });
  assert.equal(first.contextTag, 'Plot 00337');
  assert.equal(first.action?.label, 'Open Plot 00337');

  clock += 400;
  const deduped = ctrl.push({
    severity: 'warning',
    category: 'entry',
    title: 'Plot saved with warning',
    message: 'Check stratum cover',
    toast: true,
  });
  assert.equal(deduped.id, first.id);
  assert.equal(deduped.repeatCount, 2);
  assert.equal(deduped.contextTag, 'Plot 00337');
  assert.equal(deduped.action?.label, 'Open Plot 00337');

  let snap = ctrl.getSnapshot();
  assert.equal(snap.toasts.length, 1);
  assert.equal(snap.toasts[0].contextTag, 'Plot 00337');
  assert.equal(snap.toasts[0].action?.label, 'Open Plot 00337');

  // Dismiss toast, then dedupe again within window -> recreated toast must still preserve contextTag & action
  ctrl.dismissToast(snap.toasts[0].id);
  assert.equal(ctrl.getSnapshot().toasts.length, 0);
  clock += 400;
  ctrl.push({
    severity: 'warning',
    category: 'entry',
    title: 'Plot saved with warning',
    message: 'Check stratum cover',
    toast: true,
  });
  snap = ctrl.getSnapshot();
  assert.equal(snap.entries[0].repeatCount, 3);
  assert.equal(snap.toasts.length, 1);
  assert.equal(snap.toasts[0].contextTag, 'Plot 00337');
  assert.equal(snap.toasts[0].action?.label, 'Open Plot 00337');

  // triggerAction marks entry read, dismisses matching toast & timer, invokes callback, emits, returns true
  let emittedLatest = null;
  const unsub = ctrl.subscribe((s) => {
    emittedLatest = s;
  });
  const ok = ctrl.triggerAction(first.id);
  assert.equal(ok, true);
  assert.equal(triggeredCount, 1);
  assert.equal(emittedLatest.entries[0].read, true);
  assert.equal(emittedLatest.toasts.length, 0);
  assert.equal(scheduled.size, 0);
  assert.equal(ctrl.triggerAction('nonexistent'), false);
  unsub();

  // Push entries across all categories to verify filterNotificationEntries
  const generalWarn = ctrl.push({ severity: 'warning', category: 'general', title: 'General advisory' });
  const lmhEntry = ctrl.push({ severity: 'warning', category: 'lmh25', title: 'Soil depth sign', contextTag: 'Horizon H' });
  const reportEntry = ctrl.push({ severity: 'info', category: 'reports', title: 'Summary exported', contextTag: 'Sample_SU', toast: false });
  const adminEntry = ctrl.push({ severity: 'info', category: 'admin', title: 'User list updated', toast: false });
  const bgEntry = ctrl.push({ severity: 'error', category: 'background', title: 'Sync failed', toast: false });

  assert.equal(ctrl.triggerAction(reportEntry.id), false);

  const allEntries = ctrl.getSnapshot().entries;
  assert.equal(mod.filterNotificationEntries(allEntries, 'all').length, 6);
  assert.deepEqual(Array.from(mod.filterNotificationEntries(allEntries, 'errors'), (e) => e.id), [bgEntry.id]);
  assert.deepEqual(Array.from(mod.filterNotificationEntries(allEntries, 'entry'), (e) => e.id), [first.id]);
  assert.deepEqual(Array.from(mod.filterNotificationEntries(allEntries, 'lmh25'), (e) => e.id), [lmhEntry.id, generalWarn.id]);
  assert.deepEqual(Array.from(mod.filterNotificationEntries(allEntries, 'reports'), (e) => e.id), [reportEntry.id]);
  assert.deepEqual(Array.from(mod.filterNotificationEntries(allEntries, 'background'), (e) => e.id), [bgEntry.id, adminEntry.id]);
});

test('NotificationDrawer and NotificationHost compile with 0 client/server warnings and SSR contextTag and actions', () => {
  const drawerSrc = readSrc('shell/NotificationDrawer.svelte');
  const hostSrc = readSrc('shell/NotificationHost.svelte');

  assert.equal(compile(drawerSrc, { filename: srcPath('shell/NotificationDrawer.svelte'), generate: 'client' }).warnings.length, 0);
  assert.equal(compile(hostSrc, { filename: srcPath('shell/NotificationHost.svelte'), generate: 'client' }).warnings.length, 0);

  const notifMod = loadTypeScript('shell/notificationService.svelte.ts', { 'svelte/store': require('svelte/store') });
  const ctrl = notifMod.createNotificationController({ schedule: () => 1, cancelSchedule: () => {} });
  const entry = ctrl.push({
    severity: 'warning',
    category: 'entry',
    title: 'Unsaved plot change',
    message: 'Cover exceeds 99% cap in lump preview.',
    source: 'FS882',
    contextTag: 'Plot 00337',
    action: { label: 'Open Plot 00337', onTrigger() {} },
    toast: true,
  });
  ctrl.push({
    severity: 'info',
    category: 'reports',
    title: 'Report ready',
    message: 'Summary workbook written.',
    toast: false,
  });

  const lucideStub = new Proxy({}, { get: () => () => {} });
  const deps = {
    './notificationService.svelte': notifMod,
    '@lucide/svelte': lucideStub,
  };

  const DrawerComp = serverComponent(drawerSrc, 'shell/NotificationDrawer.svelte', deps);
  const drawerHtml = render(DrawerComp, { props: { open: true, controller: ctrl, onclose() {} } }).body;
  assert.match(drawerHtml, /data-notification-filter="all"[^>]*>All</);
  assert.match(drawerHtml, /data-notification-filter="errors"[^>]*>Errors</);
  assert.match(drawerHtml, /data-notification-filter="entry"[^>]*>Data Entry</);
  assert.match(drawerHtml, /data-notification-filter="lmh25"[^>]*>LMH25 &amp; QC</);
  assert.match(drawerHtml, /data-notification-filter="reports"[^>]*>Reports &amp; Exports</);
  assert.match(drawerHtml, /data-notification-filter="background"[^>]*>System &amp; Sync</);
  assert.match(drawerHtml, /role="listitem"[^>]*class="vpro-notif-item/);
  assert.match(drawerHtml, /class="vpro-notif-context tabular-nums[^"]*"[^>]*>Plot 00337</);
  assert.match(drawerHtml, new RegExp(`data-notification-action="${entry.id}"[^>]*>\\s*Open Plot 00337\\s*<`));

  const HostComp = serverComponent(hostSrc, 'shell/NotificationHost.svelte', deps);
  const hostHtml = render(HostComp, { props: { controller: ctrl } }).body;
  assert.match(hostHtml, /class="vpro-toast-context tabular-nums[^"]*"[^>]*>Plot 00337</);
  assert.match(hostHtml, new RegExp(`data-toast-action="${entry.id}"[^>]*>\\s*Open Plot 00337\\s*<`));
});
