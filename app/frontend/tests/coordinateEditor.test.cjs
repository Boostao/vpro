const { srcPath } = require('./svelteTestHelpers.cjs');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const vm = require('node:vm');
const ts = require('typescript');
const { compile } = require('svelte/compiler');
const source = readFileSync(srcPath('coordinateEditor.ts'), 'utf8');
const moduleExports = {};
vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText,
  { exports: moduleExports, structuredClone });
const { CoordinateEditor, coordinateParts, coordinateDecimalValue, isCoordinateControl, coordinateSession, rememberCoordinateSession, coordinateBusy } = moduleExports;
const buffers = (degrees = '', minutes = '', seconds = '', negative = false) => ({ degrees, minutes, seconds, negative });
const tick = () => new Promise(resolve => setImmediate(resolve));
function deferred() { let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; }
function setup(overrides = {}, session) {
  const events = { states: [], busy: [], dirty: 0, values: [], validation: [], errors: [], conversions: [], preferences: [] };
  const api = {
    getMode: async () => 'dd',
    setMode: async mode => { events.preferences.push(mode); },
    decompose: async (value, mode) => mode === 'dd'
      ? { degrees: value, minutes: null, seconds: null, negative: false }
      : value === null ? { degrees: null, minutes: null, seconds: null, negative: false }
      : { degrees: Math.trunc(Math.abs(value)), minutes: mode === 'dms' ? 30 : 30.25, seconds: mode === 'dms' ? 1.25 : null, negative: value < 0 },
    convert: async (axis, mode, parts) => {
      events.conversions.push({ axis, mode, parts });
      if (parts.degrees === null) return null;
      return mode === 'dd' ? parts.degrees : (parts.degrees + parts.minutes / 60 + (parts.seconds ?? 0) / 3600) * (parts.negative ? -1 : 1);
    }, ...overrides
  };
  const editor = new CoordinateEditor(api, {
    state: state => events.states.push(state), busy: busy => events.busy.push(busy),
    dirty: () => events.dirty++, value: (axis, value) => events.values.push({ axis, value }),
    validation: (axis, message) => events.validation.push({ axis, message }),
    error: message => events.errors.push(message)
  }, session);
  return { editor, events, api };
}

test('typed parts preserve signed DD, NULL and whole-magnitude sign', () => {
  const dd = coordinateParts('latitude', 'dd', buffers('-49.123456789'));
  assert.equal(dd.degrees, -49.123456789);
  assert.equal(dd.negative, false);
  assert.equal(dd.minutes, null);
  const dm = coordinateParts('longitude', 'dm', buffers('123', '30.25', '', true));
  assert.equal(dm.negative, true);
  assert.equal(dm.minutes, 30.25);
  assert.equal(coordinateParts('latitude', 'dms', buffers()).degrees, null);
  for (const input of [buffers('49', ''), buffers('49', '60'), buffers('49', '-1'), buffers('-49', '30'), buffers('-0', '30'), buffers('49.5', '1'), buffers('90', '1')]) {
    assert.throws(() => coordinateParts('latitude', 'dm', input));
  }
  for (const input of [buffers('49', '1.5', '0'), buffers('49', '1', '60'), buffers('49', '1', '-1'), buffers('49', '1', ''), buffers('49', '1', 'NaN')]) {
    assert.throws(() => coordinateParts('latitude', 'dms', input));
  }
  for (const text of [' ', '1e', 'Infinity', '91', 'not-number']) assert.throws(() => coordinateParts('latitude', 'dd', buffers(text)));
  assert.equal(coordinateParts('longitude', 'dd', buffers('-180')).degrees, -180);
});
test('scoped DD parsing preserves raw precision and unchanged historical values without a preference lifecycle', () => {
  for (const [axis, limit] of [['latitude', 90], ['longitude', 180]]) {
    for (const raw of ['', String(limit), String(-limit), '-0', '+1.1234567890123', '1e1']) {
      const parsed = coordinateDecimalValue(axis, raw, null);
      assert.equal(parsed.raw, raw);
      assert.equal(parsed.error, null);
      assert.equal(parsed.value, raw === '' ? null : Number(raw));
    }
    assert.equal(Object.is(coordinateDecimalValue(axis, '-0', null).value, -0), true);
    assert.equal(coordinateDecimalValue(axis, '4e2', 400).value, 400);
    for (const raw of [' ', '0x10', '1e', 'NaN', 'Infinity', '1e309', String(limit + .000001)]) {
      const parsed = coordinateDecimalValue(axis, raw, null);
      assert.equal(parsed.raw, raw);
      assert.equal(parsed.value, null);
      assert.ok(parsed.error);
    }
    assert.equal(coordinateDecimalValue(axis, '0x10', 16).error, `Enter a finite ${axis} degrees.`);
    assert.equal(coordinateDecimalValue(axis, '1e', null).error, `Enter a finite ${axis} degrees.`);
  }
});
test('preference and decomposition never change draft values or mark dirty', async () => {
  const { editor, events } = setup();
  editor.syncDraft(-49.123456789, null);
  await editor.initialize();
  await editor.changeMode('dm');
  assert.equal(events.dirty, 0);
  assert.equal(events.values.length, 0);
  assert.equal(events.preferences[0], 'dm');
  assert.equal(editor.snapshot().axes.latitude.buffers.negative, true);
  assert.equal(editor.snapshot().axes.longitude.buffers.degrees, '');
  assert.equal(events.busy[0], true);
  assert.equal(events.busy.at(-1), false);
});
test('conversions affect only edited axis and preserve lexical buffer on draft echo', async () => {
  const { editor, events } = setup();
  editor.syncDraft(-49.123456789, -123.987654321);
  await editor.initialize();
  editor.edit('latitude', 'degrees', '-50.1200');
  await tick();
  editor.syncDraft(-50.12, -123.987654321);
  assert.equal(events.values.length, 1);
  assert.equal(events.values[0].axis, 'latitude');
  assert.equal(editor.snapshot().axes.latitude.buffers.degrees, '-50.1200');
  assert.equal(editor.snapshot().axes.longitude.value, -123.987654321);
  assert.equal(events.validation.at(-1).message, null);
});
test('partial/invalid parts mark dirty, preserve coordinate and prevent mode switch', async () => {
  const { editor, events } = setup({ getMode: async () => 'dm' });
  editor.syncDraft(-49.5, null);
  await editor.initialize();
  editor.edit('latitude', 'minutes', '');
  await editor.changeMode('dms');
  assert.equal(events.dirty, 1);
  assert.equal(events.conversions.length, 0);
  assert.equal(events.preferences.length, 0);
  assert.equal(editor.snapshot().axes.latitude.value, -49.5);
  assert.equal(editor.snapshot().axes.latitude.buffers.minutes, '');
  assert.match(editor.snapshot().axes.latitude.error, /Complete all/);
  editor.edit('latitude', 'degrees', '');
  await tick();
  assert.equal(events.values.at(-1).value, null);
  assert.equal(editor.snapshot().axes.longitude.value, null);
});
test('out-of-order converter replies and replies after disposal are ignored', async () => {
  const requests = [];
  const { editor, events } = setup({ convert: () => { const request = deferred(); requests.push(request); return request.promise; } });
  editor.syncDraft(49, -123.25);
  await editor.initialize();
  editor.edit('latitude', 'degrees', '50');
  editor.edit('latitude', 'degrees', '51');
  requests[1].resolve(51); await tick();
  requests[0].resolve(50); await tick();
  assert.equal(events.values.length, 1);
  assert.equal(events.values[0].value, 51);
  assert.equal(events.busy.at(-1), false);
  editor.edit('latitude', 'degrees', '52');
  editor.dispose();
  assert.equal(events.busy.at(-1), true);
  requests[2].resolve(52); await tick();
  assert.equal(events.values.length, 1);
  assert.equal(events.busy.at(-1), false);
});
test('invalid newer text invalidates an older successful converter reply', async () => {
  const request = deferred();
  const { editor, events } = setup({ convert: () => request.promise });
  editor.syncDraft(49, null); await editor.initialize();
  editor.edit('latitude', 'degrees', '50');
  editor.edit('latitude', 'degrees', '1e');
  request.resolve(50); await tick();
  assert.equal(events.values.length, 0);
  assert.equal(editor.snapshot().axes.latitude.value, 49);
  assert.equal(editor.snapshot().axes.latitude.buffers.degrees, '1e');
});
test('external reload invalidates pending conversion and decomposes new raw values', async () => {
  const request = deferred();
  const { editor, events } = setup({ convert: () => request.promise });
  editor.syncDraft(49, null); await editor.initialize();
  editor.edit('latitude', 'degrees', '50');
  editor.syncDraft(-48.123456789, null);
  await tick();
  request.resolve(50); await tick();
  assert.equal(events.values.length, 0);
  assert.equal(editor.snapshot().axes.latitude.buffers.degrees, '-48.123456789');
});
test('cached invalid input survives tab remount but a new draft identity has no cache', async () => {
  const identity = {};
  const first = setup({ getMode: async () => 'dm' });
  first.editor.syncDraft(49.5, null); await first.editor.initialize();
  first.editor.edit('latitude', 'minutes', '1e');
  rememberCoordinateSession(identity, first.editor.snapshot());
  first.editor.dispose();
  const second = setup({ getMode: async () => 'dm' }, coordinateSession(identity));
  second.editor.syncDraft(49.5, null); await second.editor.initialize();
  assert.equal(second.editor.snapshot().axes.latitude.buffers.minutes, '1e');
  assert.match(second.editor.snapshot().axes.latitude.error, /finite/);
  await second.editor.changeMode('dd');
  assert.equal(second.events.preferences.length, 0);
  assert.equal(coordinateSession({}), undefined);
});
test('binding failures and invalid service results expose validation without draft writes', async () => {
  const { editor, events } = setup({ convert: async () => { throw new Error('conversion rejected'); } });
  editor.syncDraft(49, null); await editor.initialize();
  editor.edit('latitude', 'degrees', '50'); await tick();
  assert.equal(events.values.length, 0);
  assert.match(events.validation.at(-1).message, /conversion rejected/);
  assert.equal(events.busy.at(-1), false);
  const invalid = setup({ getMode: async () => '' });
  await invalid.editor.initialize();
  assert.equal(invalid.editor.snapshot().ready, false);
  assert.match(invalid.events.errors.at(-1), /unsupported display mode/);
});
test('pending busy ownership remains accurate across same-draft component remounts', () => {
  const identity = {}, oldOwner = {}, newOwner = {};
  assert.equal(coordinateBusy(identity, oldOwner, true), true);
  assert.equal(coordinateBusy(identity, newOwner, true), true);
  assert.equal(coordinateBusy(identity, oldOwner, false), true);
  assert.equal(coordinateBusy(identity, newOwner, false), false);
});
test('decomposition failures are retryable without draft writes and preserve negative zero', async () => {
  let fail = true;
  const { editor, events } = setup({
    decompose: async value => {
      if (fail) throw new Error('display failure');
      return { degrees: value, minutes: null, seconds: null, negative: false };
    }
  });
  editor.syncDraft(-0, null); await editor.initialize();
  assert.equal(editor.snapshot().axes.latitude.ready, false);
  assert.match(editor.snapshot().axes.latitude.error, /display failure/);
  fail = false; await editor.initialize();
  assert.equal(editor.snapshot().axes.latitude.ready, true);
  assert.equal(editor.snapshot().axes.latitude.buffers.degrees, '-0');
  assert.equal(events.validation.at(-1).message, null);
  assert.equal(events.dirty, 0);
  assert.equal(events.values.length, 0);
});
test('preference failure preserves display mode/buffers and invalid server numeric results never write', async () => {
  const { editor, events } = setup({ setMode: async () => { throw new Error('preference failure'); }, convert: async () => undefined });
  editor.syncDraft(-49.123456789, null); await editor.initialize();
  await editor.changeMode('dm');
  assert.equal(editor.snapshot().mode, 'dd');
  assert.equal(editor.snapshot().axes.latitude.buffers.degrees, '-49.123456789');
  assert.match(events.errors.at(-1), /preference failure/);
  editor.edit('latitude', 'degrees', '-50.1200'); await tick();
  assert.equal(events.values.length, 0);
  assert.match(events.validation.at(-1).message, /invalid coordinate/);
});
test('syncDraft before and during getMode decomposes latest plot coordinates once per axis without duplicate RPCs', async () => {
  const beforeCalls = [];
  const before = setup({
    decompose: async (value, mode) => {
      beforeCalls.push({ value, mode });
      return { degrees: value, minutes: null, seconds: null, negative: false };
    }
  });
  before.editor.syncDraft(58.1234550476074, 123.629028320313, {});
  assert.equal(beforeCalls.length, 0);
  await before.editor.initialize();
  assert.deepEqual(beforeCalls, [
    { value: 58.1234550476074, mode: 'dd' },
    { value: 123.629028320313, mode: 'dd' }
  ]);
  assert.equal(before.editor.snapshot().ready, true);
  assert.equal(before.editor.snapshot().busy, false);
  assert.equal(before.editor.snapshot().axes.latitude.ready, true);
  assert.equal(before.editor.snapshot().axes.longitude.ready, true);
  assert.equal(before.editor.snapshot().axes.latitude.buffers.degrees, '58.1234550476074');
  assert.equal(before.editor.snapshot().axes.longitude.buffers.degrees, '123.629028320313');

  const modeGate = deferred();
  const duringCalls = [];
  const during = setup({
    getMode: () => modeGate.promise,
    decompose: async (value, mode) => {
      duringCalls.push({ value, mode });
      return mode === 'dm' && value !== null
        ? { degrees: Math.trunc(Math.abs(value)), minutes: 15.5, seconds: null, negative: value < 0 }
        : { degrees: value, minutes: null, seconds: null, negative: false };
    }
  });
  const initPromise = during.editor.initialize();
  during.editor.syncDraft(50.5, 120.5, {});
  during.editor.syncDraft(58.1234550476074, 123.629028320313, {});
  assert.equal(duringCalls.length, 0);
  modeGate.resolve('dm');
  await initPromise;
  assert.deepEqual(duringCalls, [
    { value: 58.1234550476074, mode: 'dm' },
    { value: 123.629028320313, mode: 'dm' }
  ]);
  assert.equal(during.editor.snapshot().ready, true);
  assert.equal(during.editor.snapshot().busy, false);
  assert.equal(during.editor.snapshot().axes.latitude.ready, true);
  assert.equal(during.editor.snapshot().axes.longitude.ready, true);
  assert.equal(during.editor.snapshot().axes.latitude.buffers.degrees, '58');
  assert.equal(during.editor.snapshot().axes.longitude.buffers.degrees, '123');
});
test('syncDraft arriving while initialize is awaiting initial decompose populates and enables both axes (UX-ENV-003)', async () => {
  const decomposeRequests = [];
  const { editor, events } = setup({
    decompose: (value, mode) => {
      const req = deferred();
      decomposeRequests.push({ value, mode, ...req });
      return req.promise;
    }
  });
  const draft0 = {}, draft337 = {};
  editor.syncDraft(null, null, draft0);
  const init = editor.initialize();
  await tick();
  assert.equal(decomposeRequests.length, 2);
  assert.deepEqual(decomposeRequests.map(r => r.value), [null, null]);

  // Plot 00337 loads while initial (null, null) decomposition is still in flight
  editor.syncDraft(58.1234550476074, 123.629028320313, draft337);
  assert.equal(decomposeRequests.length, 4);
  assert.deepEqual(decomposeRequests.slice(2).map(r => r.value), [58.1234550476074, 123.629028320313]);

  // Resolve initial (null) latitude first, and resolve plot 00337 longitude BEFORE initial (null) longitude (out-of-order)
  decomposeRequests[0].resolve({ degrees: null, minutes: null, seconds: null, negative: false });
  decomposeRequests[3].resolve({ degrees: 123.629028320313, minutes: null, seconds: null, negative: false });
  await tick();
  assert.equal(editor.snapshot().busy, true);

  decomposeRequests[1].resolve({ degrees: null, minutes: null, seconds: null, negative: false });
  decomposeRequests[2].resolve({ degrees: 58.1234550476074, minutes: null, seconds: null, negative: false });
  await init;

  const snap = editor.snapshot();
  assert.equal(snap.ready, true);
  assert.equal(snap.busy, false);
  assert.equal(snap.axes.latitude.ready, true);
  assert.equal(snap.axes.longitude.ready, true);
  assert.equal(snap.axes.latitude.buffers.degrees, '58.1234550476074');
  assert.equal(snap.axes.longitude.buffers.degrees, '123.629028320313');
  assert.equal(events.dirty, 0);
  assert.equal(events.errors.length, 0);
});
test('syncDraft after getMode and changeMode invoke decompose once per axis and handle syncDraft during setMode', async () => {
  const calls = [];
  let setModeGate = null;
  const { editor, events } = setup({
    setMode: mode => {
      events.preferences.push(mode);
      return setModeGate ? setModeGate.promise : Promise.resolve();
    },
    decompose: async (value, mode) => {
      calls.push({ value, mode });
      return mode === 'dd'
        ? { degrees: value, minutes: null, seconds: null, negative: false }
        : value === null
        ? { degrees: null, minutes: null, seconds: null, negative: false }
        : { degrees: Math.trunc(Math.abs(value)), minutes: 30, seconds: mode === 'dms' ? 15 : null, negative: value < 0 };
    }
  });
  const plotA = {}, plotB = {}, plotC = {}, plotD = {};
  editor.syncDraft(58.1234550476074, 123.629028320313, plotA);
  await editor.initialize();
  assert.equal(calls.length, 2);

  calls.length = 0;
  editor.syncDraft(54.25, 125.75, plotB);
  await tick();
  assert.deepEqual(calls, [
    { value: 54.25, mode: 'dd' },
    { value: 125.75, mode: 'dd' }
  ]);

  // Repeated syncDraft with identical clean coordinates fires zero duplicate RPCs
  calls.length = 0;
  editor.syncDraft(54.25, 125.75, plotB);
  await tick();
  assert.equal(calls.length, 0);

  // Mode switch invokes decompose exactly once per axis
  await editor.changeMode('dms');
  assert.deepEqual(calls, [
    { value: 54.25, mode: 'dms' },
    { value: 125.75, mode: 'dms' }
  ]);

  // syncDraft arriving while setMode is pending decomposes once in the new mode after setMode resolves
  calls.length = 0;
  setModeGate = deferred();
  const modePromise = editor.changeMode('dm');
  editor.syncDraft(51.5, 119.5, plotC);
  assert.equal(calls.length, 0);
  setModeGate.resolve();
  await modePromise;
  assert.deepEqual(calls, [
    { value: 51.5, mode: 'dm' },
    { value: 119.5, mode: 'dm' }
  ]);
  assert.equal(editor.snapshot().axes.latitude.ready, true);
  assert.equal(editor.snapshot().axes.longitude.ready, true);

  // If setMode fails after syncDraft updated coordinates while pending, new coordinates still decompose in retained mode
  calls.length = 0;
  setModeGate = deferred();
  const failedModePromise = editor.changeMode('dd');
  editor.syncDraft(49.5, 121.5, plotD);
  assert.equal(calls.length, 0);
  setModeGate.reject(new Error('save rejected'));
  await failedModePromise;
  assert.deepEqual(calls, [
    { value: 49.5, mode: 'dm' },
    { value: 121.5, mode: 'dm' }
  ]);
  assert.equal(editor.snapshot().mode, 'dm');
  assert.equal(editor.snapshot().axes.latitude.ready, true);
  assert.equal(editor.snapshot().axes.longitude.ready, true);
});
test('rapid plot switching ignores stale out-of-order decompose and convert replies across draft identities', async () => {
  const decomposeRequests = [];
  const convertRequests = [];
  const { editor, events } = setup({
    decompose: (value, mode) => {
      const req = deferred();
      decomposeRequests.push({ value, mode, ...req });
      return req.promise;
    },
    convert: (axis, mode, parts) => {
      const req = deferred();
      convertRequests.push({ axis, mode, parts, ...req });
      return req.promise;
    }
  });
  const plot1 = {}, plot2 = {}, plot3 = {}, plot4 = {};
  editor.syncDraft(58.12, 123.62, plot1);
  const init = editor.initialize();
  await tick();
  decomposeRequests[0].resolve({ degrees: 58.12, minutes: null, seconds: null, negative: false });
  decomposeRequests[1].resolve({ degrees: 123.62, minutes: null, seconds: null, negative: false });
  await init;

  // Rapidly switch Plot 1 -> Plot 2 -> Plot 3 while decompositions remain in flight
  editor.syncDraft(54.0, 125.0, plot2);
  editor.syncDraft(51.5, 120.5, plot3);
  assert.equal(decomposeRequests.length, 6);

  // Plot 3 resolves FIRST, then Plot 2 resolves/rejects out of order
  decomposeRequests[4].resolve({ degrees: 51.5, minutes: null, seconds: null, negative: false });
  decomposeRequests[5].resolve({ degrees: 120.5, minutes: null, seconds: null, negative: false });
  await tick();
  decomposeRequests[2].resolve({ degrees: 54.0, minutes: null, seconds: null, negative: false });
  decomposeRequests[3].reject(new Error('stale plot 2 failure'));
  await tick();

  assert.equal(editor.snapshot().busy, false);
  assert.equal(editor.snapshot().axes.latitude.ready, true);
  assert.equal(editor.snapshot().axes.longitude.ready, true);
  assert.equal(editor.snapshot().axes.latitude.buffers.degrees, '51.5');
  assert.equal(editor.snapshot().axes.longitude.buffers.degrees, '120.5');
  assert.equal(editor.snapshot().axes.longitude.error, null);
  assert.equal(events.errors.length, 0);

  // User starts typing on Plot 3 (whose latitude is 51.5), then switches to Plot 4 which ALSO has latitude 51.5
  editor.edit('latitude', 'degrees', '52.0');
  assert.equal(convertRequests.length, 1);
  editor.syncDraft(51.5, 122.0, plot4);
  decomposeRequests[6].resolve({ degrees: 51.5, minutes: null, seconds: null, negative: false });
  decomposeRequests[7].resolve({ degrees: 122.0, minutes: null, seconds: null, negative: false });
  convertRequests[0].resolve(52.0);
  await tick();

  assert.equal(events.values.length, 0);
  assert.equal(editor.snapshot().axes.latitude.value, 51.5);
  assert.equal(editor.snapshot().axes.latitude.buffers.degrees, '51.5');
  assert.equal(editor.snapshot().axes.longitude.buffers.degrees, '122');
});
test('getMode failure never invokes decompose and recovers cleanly on retry', async () => {
  let failMode = true;
  const decomposeCalls = [];
  const modeGate = deferred();
  const { editor, events } = setup({
    getMode: () => failMode ? modeGate.promise : Promise.resolve('dd'),
    decompose: async (value, mode) => {
      decomposeCalls.push({ value, mode });
      return { degrees: value, minutes: null, seconds: null, negative: false };
    }
  });
  const firstAttempt = editor.initialize();
  editor.syncDraft(58.1234550476074, 123.629028320313, {});
  modeGate.reject(new Error('config unavailable'));
  await firstAttempt;

  assert.equal(decomposeCalls.length, 0);
  assert.equal(editor.snapshot().ready, false);
  assert.equal(editor.snapshot().busy, false);
  assert.equal(editor.snapshot().axes.latitude.ready, false);
  assert.equal(editor.snapshot().axes.longitude.ready, false);
  assert.match(events.errors.at(-1), /config unavailable/);

  failMode = false;
  await editor.initialize();
  assert.deepEqual(decomposeCalls, [
    { value: 58.1234550476074, mode: 'dd' },
    { value: 123.629028320313, mode: 'dd' }
  ]);
  assert.equal(editor.snapshot().ready, true);
  assert.equal(editor.snapshot().busy, false);
  assert.equal(editor.snapshot().axes.latitude.ready, true);
  assert.equal(editor.snapshot().axes.longitude.ready, true);
  assert.equal(editor.snapshot().axes.latitude.buffers.degrees, '58.1234550476074');
  assert.equal(editor.snapshot().axes.longitude.buffers.degrees, '123.629028320313');
});
test('coordinate inputs retain labelled relationships and configuration/schema/lock gates', () => {
  const component = readFileSync(srcPath('CoordinateFields.svelte'), 'utf8');
  const header = readFileSync(srcPath('HeaderEditor.svelte'), 'utf8');
  for (const [filename, text] of [['CoordinateFields.svelte', component], ['HeaderEditor.svelte', header]]) {
    const compiled = compile(text, { filename, generate: 'client' });
    assert.equal(compiled.warnings.filter(w => w.code.startsWith('a11y')).length, 0);
  }
  assert.match(component, /placeholder=\{capabilities\[mapping\.axis\] !== true \? 'Pending' : ''\}/);
  assert.match(component, /capabilities\[axis\] !== true/);
  assert.match(component, /style=\{position\(control\)\}/);
  assert.match(component, /Safety addition: explicit numeric signs/);
  assert.match(component, /role=\{only \? undefined : 'radiogroup'\}/);
  assert.match(component, /identity = draft;[\s\S]*editor\.syncDraft/);
  assert.match(component, /coordinateBusy\(busyIdentity, busyOwner, value\)/);
  assert.match(header, /paperPage\('Site', 'initial', coordinateMode\)/);
  assert.match(header, /onCoordinateBusyChange\?:/);
  assert.match(header, /isCoordinateControl\(control.controlName\)/);
  const { createFS882TestController } = require('./svelteTestHelpers.cjs');
  const h = createFS882TestController();
  try {
    h.ctrl.validateHeader('coordinates', 'Latitude invalid');
    h.ctrl.error = 'Latitude invalid';
    h.ctrl.validateHeader('coordinates', null);
    assert.equal(h.ctrl.error, null);
  } finally {
    h.dispose();
  }
  for (const name of ['Latitude', 'Longitude', 'LatD', 'LatM', 'LatS', 'LatD2', 'LatMD', 'LonD', 'LonM', 'LonS', 'LonD2', 'LonMD', 'Check369', 'Check371', 'Check373', 'optCoordMethod2']) assert.equal(isCoordinateControl(name), true);
  for (const name of ['lblLatitude', 'lblLatD', 'lblLonM', 'OfficeNotes']) assert.equal(isCoordinateControl(name), false);
});
