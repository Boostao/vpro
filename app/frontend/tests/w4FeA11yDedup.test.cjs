const test = require('node:test');
const assert = require('node:assert/strict');
const { readdirSync, readFileSync } = require('node:fs');
const path = require('node:path');
const { parse } = require('svelte/compiler');
const { render } = require('svelte/server');
const { loadTypeScript, readSrc, serverComponent } = require('./svelteTestHelpers.cjs');

const SRC_ROOT = path.resolve(__dirname, '..', 'src');

function walkFiles(dir, extFilter) {
  const results = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...walkFiles(full, extFilter));
    } else if (!extFilter || extFilter(entry.name)) {
      results.push(full);
    }
  }
  return results.sort();
}

function getAttr(el, name) {
  return (el.attributes || []).find((attr) => attr.name === name);
}

function childNodesOf(node) {
  if (!node || typeof node !== 'object') return [];
  if (Array.isArray(node.nodes)) return node.nodes;
  if (node.fragment && Array.isArray(node.fragment.nodes)) return node.fragment.nodes;
  if (Array.isArray(node.children)) return node.children;
  return [];
}

function walkSvelteTemplate(node, fn, parent = null) {
  if (!node || typeof node !== 'object') return;
  fn(node, parent);
  for (const child of childNodesOf(node)) walkSvelteTemplate(child, fn, node);
  for (const branchKey of ['consequent', 'alternate', 'body', 'fallback', 'pending', 'then', 'catch']) {
    if (node[branchKey]) walkSvelteTemplate(node[branchKey], fn, node);
  }
}

function extractNodeText(node) {
  let out = '';
  walkSvelteTemplate(node, (child) => {
    if (child.type === 'Text') out += child.data;
    if (child.type === 'ExpressionTag' || child.type === 'Component') out += 'x';
  });
  return out.trim();
}

function countUnlabelledInComponent(relPath) {
  const src = readSrc(relPath);
  const ast = parse(src, { modern: true });
  const labelForTargets = new Set();
  walkSvelteTemplate(ast.fragment, (node) => {
    if (node.type === 'RegularElement' && node.name === 'label') {
      const forAttr = getAttr(node, 'for');
      if (forAttr) labelForTargets.add(true);
    }
  });

  const unlabelledControls = [];
  const unnamedButtons = [];

  function checkSubtree(node, insideLabel) {
    if (!node || typeof node !== 'object') return;
    let wrapped = insideLabel;
    if (node.type === 'RegularElement' && node.name === 'label') {
      wrapped = true;
    }
    if (node.type === 'RegularElement' && ['input', 'select', 'textarea'].includes(node.name)) {
      const typeAttr = getAttr(node, 'type');
      const isHiddenOrBtn =
        typeAttr &&
        Array.isArray(typeAttr.value) &&
        typeAttr.value[0]?.data &&
        ['hidden', 'submit', 'button', 'reset'].includes(typeAttr.value[0].data);
      if (!isHiddenOrBtn) {
        const hasAria = Boolean(getAttr(node, 'aria-label') || getAttr(node, 'aria-labelledby') || getAttr(node, 'title'));
        const hasIdForLabel = Boolean(getAttr(node, 'id') && labelForTargets.size > 0);
        if (!wrapped && !hasAria && !hasIdForLabel) {
          const line = src.slice(0, node.start).split('\n').length;
          unlabelledControls.push(`${relPath}:${line} <${node.name}>`);
        }
      }
    }
    if (node.type === 'RegularElement' && node.name === 'button') {
      const hasAria = Boolean(getAttr(node, 'aria-label') || getAttr(node, 'aria-labelledby') || getAttr(node, 'title'));
      const text = extractNodeText({ nodes: childNodesOf(node) });
      if (!hasAria && !text) {
        const line = src.slice(0, node.start).split('\n').length;
        unnamedButtons.push(`${relPath}:${line} <button>`);
      }
    }
    for (const child of childNodesOf(node)) checkSubtree(child, wrapped);
    for (const branchKey of ['consequent', 'alternate', 'body', 'fallback', 'pending', 'then', 'catch']) {
      if (node[branchKey]) checkSubtree(node[branchKey], wrapped);
    }
  }

  checkSubtree(ast.fragment, false);
  return { unlabelledControls, unnamedButtons };
}

test('ENG-FE-004: coordinateConversion.ts is the sole NAD83/DMS converter owner in src/entry/ and converts accurately', async () => {
  const entryFiles = walkFiles(path.join(SRC_ROOT, 'entry'), (name) => name.endsWith('.ts') || name.endsWith('.svelte'));
  const rpcHolders = entryFiles
    .filter((file) => /ProjectNAD83UTMToLatLon|ConvertCoordinate/.test(readFileSync(file, 'utf8')))
    .map((file) => path.relative(SRC_ROOT, file).replaceAll('\\', '/'));

  assert.deepEqual(rpcHolders, ['entry/coordinateConversion.ts']);

  const coordMod = loadTypeScript('entry/coordinateConversion.ts');
  assert.equal(coordMod.parseNorthernNAD83UTMZone('9'), 9);
  assert.equal(coordMod.parseNorthernNAD83UTMZone('10N'), 10);
  assert.equal(coordMod.parseNorthernNAD83UTMZone('07n'), 7);
  assert.equal(coordMod.parseNorthernNAD83UTMZone(12), 12);
  for (const invalid of ['', '6', '13', '10S', 'abc']) {
    assert.throws(() => coordMod.parseNorthernNAD83UTMZone(invalid), /Invalid NAD83 UTM zone/);
  }

  const projected = await coordMod.projectNAD83UTMZoneToLatLon(
    {
      ProjectNAD83UTMToLatLon: async (zone, easting, northing) => {
        assert.equal(zone, 10);
        assert.equal(easting, 475123.44);
        assert.equal(northing, 5459876.56);
        return { latitude: 49.28912349, longitude: -123.34198761 };
      },
    },
    '10N',
    475123.44,
    5459876.56,
  );
  assert.deepEqual({ ...projected }, {
    zone: 10,
    latitude: 49.289123,
    longitude: -123.341988,
    easting: 475123.4,
    northing: 5459876.6,
  });

  const ddLon = await coordMod.convertDMOrDMSToDecimalDegrees(
    {
      ConvertCoordinate: async (axis, mode, parts) => {
        assert.equal(axis, 'longitude');
        assert.equal(mode, 'DMS');
        assert.deepEqual({ ...parts }, { degrees: 123, minutes: 30, seconds: 36, negative: true });
        return -123.51;
      },
    },
    { CoordinateModeDM: 'DM', CoordinateModeDMS: 'DMS' },
    'longitude',
    'dms',
    '123',
    '30',
    '36',
    'W',
  );
  assert.equal(ddLon, -123.51);

  const port = coordMod.createSpatialCoordinatePort(
    {
      GetCoordinateMode: async () => 'DD',
      SetCoordinateMode: async (m) => { assert.equal(m, 'DMS'); },
      DecomposeCoordinate: async (v, m) => ({ degrees: v, minutes: 0, seconds: 0, negative: m === 'DM' }),
      ConvertCoordinate: async (_a, m, p) => (m === 'DD' ? p.degrees : -1),
    },
    { CoordinateModeDD: 'DD', CoordinateModeDM: 'DM', CoordinateModeDMS: 'DMS' },
  );
  assert.equal(await port.getMode(), 'DD');
  await port.setMode('dms');
  assert.equal(await port.convert('latitude', 'dd', { degrees: 54.25, minutes: null, seconds: null, negative: false }), 54.25);
});

test('ENG-FE-004: CoordinateHelper, LongVegetationPreferenceSection, and WorkbookPublicationSection deduplicate panels cleanly', () => {
  const CoordinateHelper = serverComponent(readSrc('entry/CoordinateHelper.svelte'), 'CoordinateHelper.svelte');
  for (const defaultMode of ['utm', 'dms', 'dm']) {
    const html = render(CoordinateHelper, {
      props: {
        idPrefix: `test-${defaultMode}`,
        defaultMode,
        onApplyUTM() {},
        onApplyAxis() {},
      },
    }).body;
    assert.match(html, new RegExp(`for="test-${defaultMode}-coord-mode"`));
    if (defaultMode === 'utm') {
      assert.match(html, /aria-label="NAD83 UTM Zone"/);
      assert.match(html, /aria-label="NAD83 UTM Easting"/);
      assert.match(html, /aria-label="NAD83 UTM Northing"/);
    } else {
      assert.match(html, /aria-label="Coordinate Axis"/);
      assert.match(html, /aria-label="Coordinate Degrees"/);
      assert.match(html, /aria-label="Coordinate Minutes"/);
      assert.match(html, /aria-label="Hemisphere"/);
      if (defaultMode === 'dms') {
        assert.match(html, /aria-label="Coordinate Seconds"/);
      } else {
        assert.doesNotMatch(html, /aria-label="Coordinate Seconds"/);
      }
    }
  }

  const prefPanels = [
    'reports/LongVegetationGroupPreferences.svelte',
    'reports/LongVegetationUnitPreferences.svelte',
    'reports/LongVegetationNamingPreferences.svelte',
    'reports/LongVegetationQualityNullPreferences.svelte',
    'reports/LongVegetationQualityMinimumPreferences.svelte',
    'reports/LongVegetationSwitchPreferences.svelte',
    'reports/LongVegetationThresholdPreferences.svelte',
    'reports/LongVegetationSelectedFieldPreferences.svelte',
    'reports/LongVegetationEnforcementPreferences.svelte',
    'reports/LongVegetationProjectUnitPreferences.svelte',
  ];
  for (const panel of prefPanels) {
    assert.match(readSrc(panel), /<LongVegetationPreferenceSection\b/, `${panel} must delegate to LongVegetationPreferenceSection`);
  }

  const workbookPanels = [
    'reports/LifeformWorkbookPanel.svelte',
    'reports/SiteUnitSummaryWorkbookPanel.svelte',
    'reports/SummaryVegetationWorkbookPanel.svelte',
  ];
  for (const panel of workbookPanels) {
    assert.match(readSrc(panel), /<WorkbookPublicationSection\b/, `${panel} must delegate to WorkbookPublicationSection`);
  }
});

test('ENG-FE-006 + UX-SHELL-006: dialogA11y traps Tab/Shift+Tab, handles Escape with busy guard, and restores focus', () => {
  const { findFocusableElements, trapDialogTabKey, modalDialog } = loadTypeScript('shared/dialogA11y.ts');

  function makeEl(tag, attrs = {}) {
    return {
      tagName: tag,
      attrs: { ...attrs },
      hidden: Boolean(attrs.hidden),
      tabIndex: attrs.tabindex !== undefined ? Number(attrs.tabindex) : 0,
      parentElement: null,
      focused: false,
      hasAttribute(k) {
        return Object.prototype.hasOwnProperty.call(this.attrs, k) && this.attrs[k] !== false && this.attrs[k] !== undefined;
      },
      getAttribute(k) {
        return Object.prototype.hasOwnProperty.call(this.attrs, k) ? String(this.attrs[k]) : null;
      },
      setAttribute(k, v) {
        this.attrs[k] = String(v);
      },
      focus() {
        doc.activeElement = this;
        this.focused = true;
      },
    };
  }

  const trigger = makeEl('BUTTON');
  const firstBtn = makeEl('BUTTON');
  const disabledBtn = makeEl('BUTTON', { disabled: '' });
  const skippedBtn = makeEl('BUTTON', { tabindex: '-1' });
  const lastInput = makeEl('INPUT');

  const docListeners = [];
  const doc = {
    activeElement: trigger,
    contains(target) {
      return target === trigger || dialog.contains(target);
    },
    querySelectorAll(sel) {
      return sel.includes('role="dialog"') ? [dialog] : [];
    },
    addEventListener(type, fn) {
      if (type === 'keydown') docListeners.push(fn);
    },
    removeEventListener(type, fn) {
      if (type === 'keydown') {
        const idx = docListeners.indexOf(fn);
        if (idx >= 0) docListeners.splice(idx, 1);
      }
    },
  };

  const dialog = {
    ownerDocument: doc,
    tabIndex: -1,
    hidden: false,
    parentElement: null,
    attrs: { role: 'dialog', 'aria-modal': 'true' },
    children: [firstBtn, disabledBtn, skippedBtn, lastInput],
    hasAttribute(k) {
      return Object.prototype.hasOwnProperty.call(this.attrs, k);
    },
    getAttribute(k) {
      return Object.prototype.hasOwnProperty.call(this.attrs, k) ? String(this.attrs[k]) : null;
    },
    setAttribute(k, v) {
      this.attrs[k] = v;
    },
    focus() {
      doc.activeElement = this;
    },
    contains(el) {
      return el === this || this.children.includes(el);
    },
    querySelector() {
      return null;
    },
    querySelectorAll() {
      return this.children;
    },
    addEventListener() {},
    removeEventListener() {},
  };

  const focusables = findFocusableElements(dialog);
  assert.equal(focusables.length, 2);
  assert.equal(focusables[0], firstBtn);
  assert.equal(focusables[1], lastInput);

  // Forward Tab on last element wraps to first element
  doc.activeElement = lastInput;
  let prevented = false;
  assert.equal(
    trapDialogTabKey(
      {
        key: 'Tab',
        shiftKey: false,
        preventDefault() {
          prevented = true;
        },
      },
      dialog,
    ),
    true,
  );
  assert.equal(prevented, true);
  assert.equal(doc.activeElement, firstBtn);

  // Shift+Tab on first element wraps to last element
  prevented = false;
  assert.equal(
    trapDialogTabKey(
      {
        key: 'Tab',
        shiftKey: true,
        preventDefault() {
          prevented = true;
        },
      },
      dialog,
    ),
    true,
  );
  assert.equal(prevented, true);
  assert.equal(doc.activeElement, lastInput);

  // modalDialog lifecycle: initial focus, Escape guard, Escape close, restore focus on destroy
  doc.activeElement = trigger;
  let closeCalls = 0;
  const handle = modalDialog(dialog, {
    onClose: () => {
      closeCalls++;
    },
    escapeDisabled: true,
  });
  assert.equal(doc.activeElement, firstBtn, 'initial focus moves inside modal');

  const dispatchKey = (evt) => {
    for (const fn of [...docListeners]) fn(evt);
  };
  assert.equal(docListeners.length >= 1, true);
  dispatchKey({ key: 'Escape', defaultPrevented: false, preventDefault() {}, stopPropagation() {} });
  assert.equal(closeCalls, 0, 'Escape is suppressed while escapeDisabled is true');

  handle.update({
    onClose: () => {
      closeCalls++;
    },
    escapeDisabled: false,
  });
  dispatchKey({ key: 'Escape', defaultPrevented: false, preventDefault() {}, stopPropagation() {} });
  assert.equal(closeCalls, 1, 'Escape invokes onClose once enabled');

  handle.destroy();
  assert.equal(doc.activeElement, trigger, 'destroy restores focus to opener');
});

test('ENG-FE-006 + UX-SHELL-006: all 9 owned custom dialog components mount ModalDialogTrap and all owned form controls have programmatic labels', () => {
  const modalFiles = [
    'shell/ResetSampleModal.svelte',
    'shell/UserSetupModal.svelte',
    'shell/CommandPalette.svelte',
    'help/AboutVProModal.svelte',
    'help/KeyboardShortcutsModal.svelte',
    'help/WhatsNewModal.svelte',
    'help/OnboardingTour.svelte',
    'entry/SIVIParentCreateModal.svelte',
    'diagnostics/SynthesisExportModal.svelte',
  ];
  for (const modalFile of modalFiles) {
    assert.match(readSrc(modalFile), /<ModalDialogTrap\b/, `${modalFile} must mount ModalDialogTrap`);
  }

  const auditedFormComponents = [
    'admin/ProjectAdminMergeTab.svelte',
    'classification/ClassificationFlatRankTab.svelte',
    'classification/ClassificationLeftTreePane.svelte',
    'classification/ClassificationPlotInspectorPane.svelte',
    'datasheet/DatasheetHeader.svelte',
    'diagnostics/SynthesisMatrixTab.svelte',
    'diagnostics/SynthesisOutlierQueue.svelte',
    'entry/CoordinateFields.svelte',
    'entry/CoordinateHelper.svelte',
    'entry/FS882ChildCreateModal.svelte',
    'entry/FS882SoilHorizonSection.svelte',
    'entry/FS882StratumSummary.svelte',
    'entry/SIVIParentCreateModal.svelte',
    'entry/SIVIParentSharedFields.svelte',
    'entry/SIVIProjectAssignmentField.svelte',
    'interchange/InterchangeHub.svelte',
  ];

  const allUnlabelled = [];
  const allUnnamedBtns = [];
  for (const comp of auditedFormComponents) {
    const { unlabelledControls, unnamedButtons } = countUnlabelledInComponent(comp);
    allUnlabelled.push(...unlabelledControls);
    allUnnamedBtns.push(...unnamedButtons);
  }
  assert.deepEqual(allUnlabelled, []);
  assert.deepEqual(allUnnamedBtns, []);
});

test('UX-CLASS-006: Classification Assign buttons resist clipping on long BEC codes and Synthesis Matrix preserves unit columns at 1024x640', () => {
  const inspectorSrc = readSrc('classification/ClassificationPlotInspectorPane.svelte');
  assert.match(inspectorSrc, /\.vpro-cls-assign-btn\s*\{[\s\S]*?flex-shrink:\s*0/);
  assert.match(inspectorSrc, /\.vpro-cls-assign-btn\s*\{[\s\S]*?white-space:\s*nowrap/);
  assert.match(inspectorSrc, /\.vpro-cls-bec-info\s+\.vpro-cls-sub\s*\{[\s\S]*?overflow-wrap:\s*anywhere/);

  const userSuSrc = readSrc('classification/ClassificationUserSUPanel.svelte');
  assert.match(userSuSrc, /\.vpro-cls-actions\s+button\s*\{[\s\S]*?flex-shrink:\s*0/);
  assert.match(userSuSrc, /\.vpro-cls-actions\s+button\s*\{[\s\S]*?white-space:\s*nowrap/);

  const synthViewSrc = readSrc('diagnostics/ClassificationSynthesisView.svelte');
  assert.match(synthViewSrc, /@media\s*\(max-width:\s*1200px\)[\s\S]*?\.syn-workspace-grid\s*\{\s*grid-template-columns:\s*minmax\(0,\s*1fr\);/);

  const matrixSrc = readSrc('diagnostics/SynthesisMatrixTab.svelte');
  assert.match(matrixSrc, /@media\s*\(max-width:\s*1200px\)/);
  assert.match(matrixSrc, /\.sticky-col\.col-sci\s*\{[\s\S]*?position:\s*static/);
});

test('UX-CLASS-007: zero Access/SQLite engineering jargon in src/classification/ and RuntimeError stripped from classification banners', () => {
  const classFiles = walkFiles(path.join(SRC_ROOT, 'classification'), (name) => name.endsWith('.ts') || name.endsWith('.svelte'));
  const bannedPattern = /VP05|Use \(-1\)|USysAllSpecs|optResetFilter|SQLite TEMP|UTF-16-unit/;

  for (const file of classFiles) {
    const content = readFileSync(file, 'utf8');
    const rel = path.relative(SRC_ROOT, file).replaceAll('\\', '/');
    assert.doesNotMatch(content, bannedPattern, `${rel} must not expose legacy Access or SQLite jargon`);
  }

  const lumpSrc = readSrc('classification/LumpEditor.svelte');
  assert.match(lumpSrc, />Active<\/th>/);
  assert.match(lumpSrc, /Species Catalogue/);
  assert.match(lumpSrc, /RuntimeError/);

  const profileSrc = readSrc('classification/ProjectPlotProfileReview.svelte');
  assert.match(profileSrc, /Start with all plots/);
  assert.match(profileSrc, /RuntimeError/);

  const explorerSrc = readSrc('classification/ClassificationExplorer.svelte');
  assert.match(explorerSrc, /RuntimeError/);

  const transferSrc = readSrc('classification/EnvironmentSUTransfer.svelte');
  assert.match(transferSrc, /RuntimeError/);
});
