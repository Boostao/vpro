const assert = require('node:assert/strict');
const { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('typescript');
const { compile } = require('svelte/compiler');
const { render } = require('svelte/server');
const {
  SRC_ROOT,
  buildSrcIndex,
  componentFunctions,
  loadTypeScript,
  readSrc,
  serverComponent,
  srcFiles,
  srcPath,
} = require('./svelteTestHelpers.cjs');

// All sibling files formatted and verified on post-merge main:
const SIBLING_OWNED_FILES = new Set([]);

function createMiniDomEnvironment() {
  class MiniNode extends EventTarget {
    constructor(nodeType, nodeName = '') {
      super();
      this.nodeType = nodeType;
      this.nodeName = nodeName.toUpperCase();
      this.parentNode = null;
      this.childNodes = [];
      this._text = '';
      this.ownerDocument = null;
    }
    get parentElement() {
      return this.parentNode && this.parentNode.nodeType === 1 ? this.parentNode : null;
    }
    get firstChild() {
      return this.childNodes[0] ?? null;
    }
    get lastChild() {
      return this.childNodes[this.childNodes.length - 1] ?? null;
    }
    get nextSibling() {
      if (!this.parentNode) return null;
      const idx = this.parentNode.childNodes.indexOf(this);
      return idx >= 0 ? (this.parentNode.childNodes[idx + 1] ?? null) : null;
    }
    get previousSibling() {
      if (!this.parentNode) return null;
      const idx = this.parentNode.childNodes.indexOf(this);
      return idx > 0 ? this.parentNode.childNodes[idx - 1] : null;
    }
    appendChild(child) {
      if (child.nodeType === 11) {
        for (const c of [...child.childNodes]) this.appendChild(c);
        return child;
      }
      if (child.parentNode) child.parentNode.removeChild(child);
      child.parentNode = this;
      this.childNodes.push(child);
      return child;
    }
    insertBefore(child, ref) {
      if (!ref) return this.appendChild(child);
      if (child.nodeType === 11) {
        for (const c of [...child.childNodes]) this.insertBefore(c, ref);
        return child;
      }
      if (child.parentNode) child.parentNode.removeChild(child);
      const idx = this.childNodes.indexOf(ref);
      child.parentNode = this;
      if (idx === -1) this.childNodes.push(child);
      else this.childNodes.splice(idx, 0, child);
      return child;
    }
    removeChild(child) {
      const idx = this.childNodes.indexOf(child);
      if (idx >= 0) {
        this.childNodes.splice(idx, 1);
        child.parentNode = null;
      }
      return child;
    }
    before(...nodes) {
      if (!this.parentNode) return;
      for (const n of nodes) this.parentNode.insertBefore(n, this);
    }
    after(...nodes) {
      if (!this.parentNode) return;
      const ref = this.nextSibling;
      for (const n of nodes) this.parentNode.insertBefore(n, ref);
    }
    remove() {
      if (this.parentNode) this.parentNode.removeChild(this);
    }
    get textContent() {
      if (this.nodeType === 3 || this.nodeType === 8) return this._text;
      return this.childNodes.map((c) => c.textContent).join('');
    }
    set textContent(v) {
      if (this.nodeType === 3 || this.nodeType === 8) {
        this._text = String(v);
        return;
      }
      this.childNodes = [];
      if (v !== '' && v !== null && v !== undefined) {
        const t = new MiniNode(3, '#text');
        t._text = String(v);
        t.parentNode = this;
        t.ownerDocument = this.ownerDocument;
        this.childNodes.push(t);
      }
    }
    get data() {
      return this._text;
    }
    set data(v) {
      this._text = String(v);
    }
    cloneNode(deep = false) {
      const copy =
        this.nodeType === 1 ? new MiniElement(this.tagName) : new MiniNode(this.nodeType, this.nodeName);
      copy._text = this._text;
      copy.ownerDocument = this.ownerDocument;
      if (this.attributes) {
        copy.attributes = new Map(this.attributes);
        if (copy.attributes.has('id')) copy.id = copy.attributes.get('id');
        if (copy.attributes.has('class')) copy.className = copy.attributes.get('class');
        if (copy.attributes.has('value')) copy.value = copy.attributes.get('value');
      }
      if (deep) {
        for (const c of this.childNodes) copy.appendChild(c.cloneNode(true));
      }
      return copy;
    }
    dispatch(event) {
      const path = [];
      for (let n = this; n; n = n.parentNode) path.push(n);
      if (this.ownerDocument && path[path.length - 1] !== this.ownerDocument) {
        path.push(this.ownerDocument);
      }
      event.composedPath = () => path;
      Object.defineProperty(event, 'target', { configurable: true, value: this });
      for (const cur of path) {
        Object.defineProperty(event, 'currentTarget', { configurable: true, value: cur });
        const handler = cur[`__${event.type}`];
        if (typeof handler === 'function') handler.call(cur, event);
        cur.dispatchEvent(event);
        if (!event.bubbles || event.cancelBubble) break;
      }
    }
  }

  class MiniElement extends MiniNode {
    constructor(tag) {
      super(1, tag);
      this.tagName = tag.toUpperCase();
      this.attributes = new Map();
      this.style = {};
      this.id = '';
      this.value = '';
      this.checked = false;
      this.disabled = false;
      this.className = '';
    }
    setAttribute(k, v) {
      this.attributes.set(k, String(v));
      if (k === 'id') this.id = String(v);
      if (k === 'class') this.className = String(v);
      if (k === 'value') this.value = String(v);
      if (k === 'disabled') this.disabled = true;
    }
    getAttribute(k) {
      return this.attributes.has(k) ? this.attributes.get(k) : null;
    }
    removeAttribute(k) {
      this.attributes.delete(k);
      if (k === 'disabled') this.disabled = false;
    }
    hasAttribute(k) {
      return this.attributes.has(k);
    }
    focus() {}
    blur() {}
    scrollIntoView() {}
    get options() {
      return this.childNodes.filter((c) => c.nodeType === 1 && c.tagName === 'OPTION');
    }
    querySelectorAll(pred) {
      const out = [];
      const matchFn =
        typeof pred === 'function'
          ? pred
          : (el) => {
              if (pred.startsWith('#')) return el.getAttribute('id') === pred.slice(1);
              if (pred.startsWith('[') && pred.endsWith(']')) {
                const [k, rawV] = pred.slice(1, -1).split('=');
                return rawV !== undefined
                  ? el.getAttribute(k) === rawV.replace(/^['"]|['"]$/g, '')
                  : el.hasAttribute(k);
              }
              return el.tagName === pred.toUpperCase();
            };
      function walk(node) {
        for (const c of node.childNodes) {
          if (c.nodeType === 1) {
            if (matchFn(c)) out.push(c);
            walk(c);
          }
        }
      }
      walk(this);
      return out;
    }
    querySelector(pred) {
      return this.querySelectorAll(pred)[0] ?? null;
    }
  }

  function parseMiniHtml(html, doc) {
    const frag = new MiniNode(11, '#document-fragment');
    frag.ownerDocument = doc;
    const stack = [frag];
    const voidTags = new Set(['INPUT', 'BR', 'HR', 'IMG', 'META', 'LINK', 'SOURCE', 'COL']);
    const tokenRe =
      /<!--([\s\S]*?)-->|<\/([a-zA-Z0-9:-]+)\s*>|<([a-zA-Z0-9:-]+)((?:\s+[^\s/>=]+(?:=(?:"[^"]*"|'[^']*'|[^\s"'>]+))?)*)\s*(\/?)>|([^<]+)/g;
    let m;
    while ((m = tokenRe.exec(html)) !== null) {
      const top = stack[stack.length - 1];
      if (m[1] !== undefined) {
        const c = new MiniNode(8, '#comment');
        c._text = m[1];
        c.ownerDocument = doc;
        top.appendChild(c);
      } else if (m[2] !== undefined) {
        if (stack.length > 1) stack.pop();
      } else if (m[3] !== undefined) {
        const el = new MiniElement(m[3]);
        el.ownerDocument = doc;
        const attrRe = /([^\s/>=]+)(?:=(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?/g;
        let am;
        while ((am = attrRe.exec(m[4] || '')) !== null) {
          el.setAttribute(am[1], am[2] ?? am[3] ?? am[4] ?? '');
        }
        top.appendChild(el);
        if (!m[5] && !voidTags.has(el.tagName)) stack.push(el);
      } else if (m[6] !== undefined) {
        const t = new MiniNode(3, '#text');
        t._text = m[6];
        t.ownerDocument = doc;
        top.appendChild(t);
      }
    }
    return frag;
  }

  class MiniTemplate extends MiniElement {
    constructor(doc) {
      super('template');
      this.ownerDocument = doc;
      this.content = new MiniNode(11, '#document-fragment');
    }
    set innerHTML(html) {
      this.content = parseMiniHtml(html, this.ownerDocument);
    }
  }

  const doc = new MiniNode(9, '#document');
  doc.ownerDocument = doc;
  doc.createElement = (tag) => {
    if (String(tag).toLowerCase() === 'template') return new MiniTemplate(doc);
    const el = new MiniElement(tag);
    el.ownerDocument = doc;
    return el;
  };
  doc.createElementNS = (_ns, tag) => doc.createElement(tag);
  doc.createTextNode = (txt) => {
    const n = new MiniNode(3, '#text');
    n._text = String(txt);
    n.ownerDocument = doc;
    return n;
  };
  doc.createComment = (txt) => {
    const n = new MiniNode(8, '#comment');
    n._text = String(txt);
    n.ownerDocument = doc;
    return n;
  };
  doc.importNode = (node, deep) => node.cloneNode(deep);
  doc.activeElement = null;
  const win = new EventTarget();
  win.document = doc;

  return { win, doc, MiniElement, MiniNode };
}

test('ENG-FE-001: App.svelte <= 500 lines, zero typeof declared-var guards, and behavioural operationGuard refuses close/transition/paging visibly', async () => {
  const appSrc = readSrc('App.svelte');
  const appLines = appSrc.trimEnd().split('\n').length;
  assert.ok(appLines <= 500, `Expected App.svelte <= 500 lines, got ${appLines}`);
  assert.equal((appSrc.match(/PublicationBusy \|\|/g) || []).length, 0);
  assert.equal((appSrc.match(/as unknown as/g) || []).length, 0);
  assert.doesNotMatch(appSrc, /typeof\s+(?:companionPanelBusy|workbenchDirtyLabel|notifications)\s*!==\s*'undefined'/);
  assert.match(appSrc, /export const operationGuard = createOperationGuard\(\)/);

  const opGuardMod = loadTypeScript('shell/operationGuard.svelte.ts', {
    './externalSUEnvironment': { subscribeExternalSUEnvironmentActivity: () => () => {} },
    './twoPageSoilActivity': { subscribeTwoPageSoilActivity: () => () => {} },
    './twoPageVegetationActivity': { subscribeTwoPageVegetationActivity: () => () => {} },
    './tableCSVArchiveExport': { tableCSVArchivePublicationSession: () => ({ view: () => ({}), subscribe: () => () => {} }) },
    './pictureCreationActivity': { subscribePictureCreationActivity: () => () => {} },
    './pictureLifecycleActivity': { subscribePictureLifecycleActivity: () => () => {} },
    './lifeformWorkbook': { lifeformWorkbookPublicationSession: () => ({ view: () => ({}), subscribe: () => () => {} }) },
    './longVegetationProjectWorkspaces': { projectReportWorkspace: () => ({ view: () => ({}), subscribe: () => () => {} }) },
    './siteUnitSummaryExtendedWorkbook': { extendedSummaryWorkbookPublicationSession: () => ({ view: () => ({}), subscribe: () => () => {} }) },
    './siteUnitSummaryWorkbook': { siteUnitSummaryWorkbookPublicationSession: () => ({ view: () => ({}), subscribe: () => () => {} }) },
    './subzoneMatrixReport': { matrixPublicationSession: () => ({ view: () => ({}), subscribe: () => () => {} }) },
    './summaryVegetationEnvironmentalDesktop': { summaryEnvironmentalEnabled: false, summaryEnvironmentalDesktop: {} },
    './summaryVegetationFieldListDesktop': { summaryVegetationFieldListDesktop: { enabled: false } },
    './summaryVegetationPreferences': { summaryVegetationPreferenceSession: null },
    './summaryVegetationPresentationPreferences': { summaryVegetationPresentationPreferenceSession: null },
    './summaryVegetationQualityPreferences': { summaryVegetationQualityPreferenceSession: null },
    './summaryVegetationWorkbook': { summaryVegetationWorkbookSession: () => ({ held: () => false, subscribe: () => () => {} }) },
    './vegetationWorkbook': { vegetationWorkbookPublicationSession: () => ({ view: () => ({}), subscribe: () => () => {} }) },
  });

  let registeredBusy = true;
  const guard = opGuardMod.createOperationGuard();
  guard.register('test-background-publication', () => ({ busy: registeredBusy }), { publicationOnly: true });

  const warnings = [];
  let cancelCloseCalls = 0;
  let confirmCloseCalls = 0;
  let listPlotsCalls = 0;
  let transitionRuns = 0;

  const ctx = componentFunctions(
    'App.svelte',
    [
      'handleCloseRequest',
      'respondToClose',
      'requestTransition',
      'respondToTransition',
      'loadPlots',
      'refresh',
      'loadHierarchy',
    ],
    {
      operationGuard: guard,
      view: 'fs882',
      $projectState: { contextId: 'ctx-guard' },
      editor: {
        getCloseState: () => ({ unsaved: true, busy: false, error: '' }),
        saveForClose: async () => true,
        canOpenProjectMetadata: () => true,
        openProjectMetadata() {},
      },
      pendingTransition: { contextId: 'ctx-guard', run: async () => { transitionRuns++; } },
      LifecycleService: {
        GetPendingCloseRequest: async () => 'req-1',
        CancelClose: async () => { cancelCloseCalls++; },
        ConfirmClose: async () => { confirmCloseCalls++; },
        GetStartupState: async () => ({ ready: true }),
      },
      ContextService: {
        ListPlots: async () => {
          listPlotsCalls++;
          return { plots: [{ plotNumber: '00337' }], total: 1 };
        },
        GetState: async () => ({ contextId: 'ctx-guard' }),
        GetHierarchyNodes: async () => [],
      },
      notifications: {
        push() {},
        info() {},
        success() {},
        error() {},
        warning: (title, msg) => warnings.push({ title, msg }),
      },
    }
  );

  // 1. requestTransition refuses and surfaces notice + warning toast
  ctx.error = '';
  await ctx.actions.requestTransition(async () => { transitionRuns++; });
  assert.equal(transitionRuns, 0);
  assert.match(ctx.error, /Wait for the current operation/);
  assert.equal(warnings.length, 1);

  // 2. loadPlots, refresh, loadHierarchy all refuse AND surface refusal notice (not silent!)
  for (const action of ['loadPlots', 'refresh', 'loadHierarchy']) {
    ctx.error = '';
    ctx.pausedByGuard = false;
    await ctx.actions[action](0);
    assert.equal(ctx.pausedByGuard, true, `${action} must mark pausedByGuard`);
    assert.match(ctx.error, /Wait for the current operation/, `${action} must surface visible refusal notice`);
  }
  assert.equal(listPlotsCalls, 0);

  // 3. respondToTransition refuses with visible transitionError
  ctx.transitionError = '';
  await ctx.actions.respondToTransition('discard');
  assert.equal(transitionRuns, 0);
  assert.match(ctx.transitionError, /Wait for the current editor operation/);

  // 4. handleCloseRequest cancels close and surfaces visible error
  ctx.error = '';
  ctx.closeRequest = '';
  await ctx.actions.handleCloseRequest('req-1');
  assert.equal(cancelCloseCalls, 1);
  assert.equal(confirmCloseCalls, 0);
  assert.match(ctx.error, /Wait for the current operation/);

  // 5. respondToClose refuses save/discard while busy
  ctx.closeRequest = 'req-1';
  ctx.closeError = '';
  await ctx.actions.respondToClose('discard');
  assert.equal(confirmCloseCalls, 0);
  assert.match(ctx.closeError, /Wait for the current operation/);

  // 6. Clearing registered operation unblocks navigation and paging
  registeredBusy = false;
  ctx.closeRequest = '';
  ctx.pendingTransition = null;
  ctx.view = 'plots';
  await ctx.actions.loadPlots(0);
  assert.equal(listPlotsCalls, 1);
  await ctx.actions.requestTransition(async () => { transitionRuns++; });
  assert.equal(transitionRuns, 1);
});

test('ENG-FE-003: onContextDisposed evicts prior contextId entries across session registries on switchContext and sample reset', async () => {
  const reg = loadTypeScript('shared/contextSessionRegistry.ts');
  const testMap = new Map([
    ['ctx-alpha:Sample', { id: 1 }],
    ['ctx-alpha\u0000Plot1', { id: 2 }],
    [JSON.stringify(['ctx-alpha', 'Sample']), { id: 3 }],
    ['ctx-beta:Sample', { id: 4 }],
  ]);
  const unregister = reg.registerContextDisposer((oldId) => reg.evictMapEntriesByContext(testMap, oldId));

  try {
    const switchCtx = componentFunctions('App.svelte', ['switchContext'], {
      ContextService: {
        SwitchContext: async () => ({
          contextId: 'ctx-beta',
          activeProject: 'Sample',
          activeSU: 'None',
          activeHierarchy: 'None',
        }),
      },
      loadPlots: async () => {},
      loadHierarchy: async () => {},
    });
    await switchCtx.actions.switchContext('ctx-alpha', { project: 'Sample' }, 'plots');
    assert.equal(testMap.has('ctx-alpha:Sample'), false);
    assert.equal(testMap.has('ctx-alpha\u0000Plot1'), false);
    assert.equal(testMap.has(JSON.stringify(['ctx-alpha', 'Sample'])), false);
    assert.equal(testMap.has('ctx-beta:Sample'), true);

    // Also verify direct onContextDisposed invocation for sample reset path
    testMap.set('ctx-reset:Sample', { id: 5 });
    reg.onContextDisposed('ctx-reset');
    assert.equal(testMap.has('ctx-reset:Sample'), false);
    assert.equal(testMap.has('ctx-beta:Sample'), true);
  } finally {
    unregister();
  }
});

test('ENG-FE-005 & ENG-FE-012: svelteTestHelpers has zero canon === branches, throws on duplicate basenames, and scope.ts owns ProjectSUScope/ownedScope', () => {
  const helperSrc = readFileSync(path.join(__dirname, 'svelteTestHelpers.cjs'), 'utf8');
  assert.equal((helperSrc.match(/canon === '\.\/longVegetation/g) || []).length, 0);

  const tmp = mkdtempSync(path.join(os.tmpdir(), 'vpro-dup-idx-'));
  try {
    mkdirSync(path.join(tmp, 'a'));
    mkdirSync(path.join(tmp, 'b'));
    writeFileSync(path.join(tmp, 'a', 'Collision.svelte'), '<div>a</div>');
    writeFileSync(path.join(tmp, 'b', 'Collision.svelte'), '<div>b</div>');
    assert.throws(() => buildSrcIndex(tmp), /Duplicate src basename "Collision\.svelte"/);
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }

  const scopeMod = loadTypeScript('shared/scope.ts');
  const expectedScope = {
    contextId: 'ctx-1',
    project: 'Sample',
    projectPath: '/Sample.db',
    su: 'Working',
    suPath: '/Working.db',
  };
  assert.equal(scopeMod.ownedScope({ ...expectedScope }, expectedScope), true);
  assert.equal(scopeMod.ownedScope({ ...expectedScope, su: 'Other' }, expectedScope), false);
  assert.equal(scopeMod.ownedScope({ ...expectedScope, contextId: '' }, { ...expectedScope, contextId: '' }), false);

  for (const rel of srcFiles()) {
    if (rel.startsWith('spatial/') || SIBLING_OWNED_FILES.has(rel)) continue;
    const content = readSrc(rel);
    assert.doesNotMatch(content, /from\s+['"][^'"]*googleEarthReview['"]/, `${rel} must import scope from shared/scope.ts`);
  }
});

test('ENG-FE-005: dedicated behavioural tests for formValidationSummary.ts, DatasheetVirtualTable, ProjectAdminMergeTab, CloudSyncCustodianMergePanel, and ClassificationDialogs', () => {
  // 1. entry/formValidationSummary.ts
  const fv = loadTypeScript('entry/formValidationSummary.ts');
  const items = fv.buildFormValidationItems({
    headerValidation: {
      plotNumber: 'Plot number is required.',
      soilDrainage: 'Invalid drainage code.',
      strataCoverTree: 'Must be < 100.',
    },
    soilInvalid: ['Upper depth must exceed lower depth for upland humus.'],
    speciesInvalid: ['Unknown species code "ZZZZ".'],
    attributeInvalid: ['Invalid distribution code.'],
    otherInvalid: ['Missing note category.'],
  });
  assert.equal(items.length, 7);
  assert.equal(items.find((i) => i.id === 'hdr-plotNumber').tab, 'site');
  assert.equal(items.find((i) => i.id === 'hdr-soilDrainage').tab, 'soils');
  assert.equal(items.find((i) => i.id === 'hdr-strataCoverTree').tab, 'veg');
  assert.equal(items.find((i) => i.id === 'attr-0').tab, 'vegOther');
  assert.equal(items.find((i) => i.id === 'other-0').tab, 'other');

  let focusedSelector = '';
  let scrolled = false;
  const fakeContainer = {
    querySelector(sel) {
      if (sel === '#header-plotNumber') {
        return {
          scrollIntoView() { scrolled = true; },
          focus() { focusedSelector = sel; },
        };
      }
      return null;
    },
  };
  assert.equal(fv.focusValidationTarget(fakeContainer, items[0]), true);
  assert.equal(scrolled, true);
  assert.equal(focusedSelector, '#header-plotNumber');
  assert.equal(fv.focusValidationTarget(null, items[0]), false);

  // 2. DatasheetVirtualTable.svelte
  const VirtualTable = serverComponent(readSrc('datasheet/DatasheetVirtualTable.svelte'), 'datasheet/DatasheetVirtualTable.svelte');
  const cols = [
    { name: 'PlotNumber', kind: 'text', editable: false, nullable: false, maxChars: 7 },
    { name: 'Elevation', kind: 'integer', editable: true, nullable: true, maxChars: 0 },
  ];
  const dsHtml = render(VirtualTable, {
    props: {
      page: {
        tableKey: 'Env',
        tableName: 'Sample_Env',
        pinnedColumn: 'PlotNumber',
        columns: cols,
        rows: [
          {
            rowId: '00337',
            plotNumber: '00337',
            cells: [
              { storage: 'text', text: '00337' },
              { storage: 'integer', integer: '1240' },
            ],
          },
        ],
        totalRows: 1,
        offset: 0,
        limit: 250,
      },
      orderedColumns: cols.map((meta, originalIndex) => ({ meta, originalIndex })),
      drafts: { '00337:Elevation': { rawText: '99999', error: 'Out of elevation bounds' } },
      draftCount: 1,
      invalidDraftCount: 1,
      onHeaderSort() {},
      onLoadPage() {},
      onSetCellDraft() {},
      onClearCellDraft() {},
      onBannerInfo() {},
    },
  }).body;
  assert.match(dsHtml, /00337/);
  assert.match(dsHtml, /Elevation/);

  // 3. ProjectAdminMergeTab.svelte
  const MergeTab = serverComponent(readSrc('admin/ProjectAdminMergeTab.svelte'), 'admin/ProjectAdminMergeTab.svelte');
  const mergeHtml = render(MergeTab, {
    props: {
      busy: false,
      cmpResult: {
        targetProject: 'Skeena2026',
        sourceProject: 'SkeenaField',
        onlyInTarget: ['00100'],
        onlyInSource: ['00200'],
        modifiedPlots: [
          {
            plotNumber: '00337',
            diffs: [{ plotNumber: '00337', table: 'Env', key: '00337', field: 'Elevation', targetVal: '1200', sourceVal: '1240' }],
          },
        ],
        identicalPlotCount: 12,
      },
      cmpAllDiffs: [
        { plotNumber: '00337', table: 'Env', key: '00337', field: 'Elevation', targetVal: '1200', sourceVal: '1240' },
      ],
      cmpExportPreview: null,
      mergePreview: null,
      mergePlotResolutions: {},
      mergeFieldResolutions: {},
      mergeResult: null,
      onRunCompare() {},
      onExportCompareDiffs() {},
      onPreviewMerge() {},
      onExecuteMerge() {},
      onSetPlotResolution() {},
      onSetFieldResolution() {},
    },
  }).body;
  assert.match(mergeHtml, /00337/);
  assert.match(mergeHtml, /Elevation/);

  // 4. CloudSyncCustodianMergePanel.svelte
  const CustodianPanel = serverComponent(
    readSrc('admin/CloudSyncCustodianMergePanel.svelte'),
    'admin/CloudSyncCustodianMergePanel.svelte'
  );
  const custHtml = render(CustodianPanel, {
    props: {
      busy: false,
      operationHeld: false,
      submissions: [
        {
          submissionId: 'sub-2026-01',
          projectName: 'HaidaGwaii',
          submittedBy: 'ecologist@gov.bc.ca',
          submittedAt: '2026-11-19T12:00:00Z',
          status: 'pending',
          plotCount: 14,
          rarePlantTruncatedCount: 1,
        },
      ],
      selectedSubmissionDetail: null,
      mergePreview: null,
      combinedMergeItems: [],
      mergePlotResolutions: {},
      mergeFieldResolutions: {},
      mergeReviewerNotes: '',
      mergeExecuteResult: null,
      onRefreshSubmissions() {},
      onInspectSubmission() {},
      onPreviewMerge() {},
      onSetPlotResolution() {},
      onSetFieldResolution() {},
      onExecuteMerge() {},
      onRejectSubmission() {},
    },
  }).body;
  assert.match(custHtml, /sub-2026-01/);
  assert.match(custHtml, /HaidaGwaii/);

  // 5. ClassificationDialogs.svelte
  const ClassDialogs = serverComponent(
    readSrc('classification/ClassificationDialogs.svelte'),
    'classification/ClassificationDialogs.svelte'
  );
  const dlgHtml = render(ClassDialogs, {
    props: {
      activeDialog: 'new_su',
      effectiveContextId: 'ctx-cls',
      activeHierarchy: 'BEC13',
      port: {},
      mutating: false,
      newSUName: 'CWHvm1_Working',
      newSUDestination: 'project',
      newSUFilePath: '',
      populateAllPlots: true,
      seedFromUserSU: false,
      onClose() {},
      onSubmitCreateSU() {},
      onMutatingChange() {},
      onError() {},
      onStatus() {},
      onActivated() {},
      onReloadSU: async () => {},
      onReloadHierarchy: async () => {},
    },
  }).body;
  assert.match(dlgHtml, /CWHvm1_Working/);
});

test('ENG-FE-005: real mounted Svelte 5 component dispatches DOM click, input, and keydown user events', async () => {
  const { win, doc, MiniElement, MiniNode } = createMiniDomEnvironment();
  const prev = {
    window: globalThis.window,
    document: globalThis.document,
    Element: globalThis.Element,
    HTMLElement: globalThis.HTMLElement,
    Node: globalThis.Node,
    Text: globalThis.Text,
    MutationObserver: globalThis.MutationObserver,
  };
  globalThis.window = win;
  globalThis.document = doc;
  globalThis.Element = MiniElement;
  globalThis.HTMLElement = MiniElement;
  globalThis.Node = MiniNode;
  globalThis.Text = MiniNode;
  globalThis.MutationObserver = class {
    observe() {}
    disconnect() {}
  };

  try {
    const svelteClient = await import('svelte/internal/client');
    const svelteIndexHref = pathToFileURL(
      path.join(path.dirname(require.resolve('svelte/package.json')), 'src', 'index-client.js')
    ).href;
    const { mount, unmount, flushSync } = await import(svelteIndexHref);

    // Mount real DatasheetFindReplaceDrawer.svelte and dispatch input + click events
    const drawerSrc = readSrc('datasheet/DatasheetFindReplaceDrawer.svelte');
    const compiled = compile(drawerSrc, { filename: 'DatasheetFindReplaceDrawer.svelte', generate: 'client' });
    const mod = { exports: {} };
    vm.runInNewContext(
      ts.transpileModule(compiled.js.code, {
        compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
      }).outputText,
      {
        module: mod,
        exports: mod.exports,
        window: win,
        document: doc,
        Element: MiniElement,
        HTMLElement: MiniElement,
        Node: MiniNode,
        Text: MiniNode,
        require(name) {
          if (name === 'svelte/internal/client') return svelteClient;
          if (name === 'svelte') return { untrack: svelteClient.untrack };
          if (name.startsWith('svelte/')) return require(name);
          throw new Error(`Unexpected module ${name}`);
        },
      }
    );

    let previewClicks = 0;
    let applyClicks = 0;
    const target = doc.createElement('div');
    doc.appendChild(target);
    const instance = mount(mod.exports.default, {
      target,
      props: {
        page: {
          tableKey: 'Env',
          tableName: 'Sample_Env',
          pinnedColumn: 'PlotNumber',
          columns: [],
          rows: [],
          totalRows: 0,
          offset: 0,
          limit: 50,
        },
        editableColumns: [{ name: 'SiteNotes', kind: 'text', editable: true, nullable: true, maxChars: 255 }],
        findColumn: 'SiteNotes',
        findText: 'old',
        replaceText: 'new',
        findPreview: {
          tableName: 'Sample_Env',
          column: 'SiteNotes',
          matchedRows: 2,
          validCount: 2,
          invalidCount: 0,
          items: [],
        },
        onRunPreview: () => { previewClicks++; },
        onApplyValid: () => { applyClicks++; },
      },
    });

    const inputs = target.querySelectorAll('input');
    assert.ok(inputs.length >= 2);
    inputs[0].value = 'Tsuga';
    inputs[0].dispatch(new Event('input', { bubbles: true }));
    const kd = new Event('keydown', { bubbles: true });
    kd.key = 'Enter';
    inputs[0].dispatch(kd);
    flushSync();

    const buttons = target.querySelectorAll('button');
    assert.equal(buttons.length, 2);
    buttons[0].dispatch(new Event('click', { bubbles: true }));
    buttons[1].dispatch(new Event('click', { bubbles: true }));
    flushSync();

    assert.equal(previewClicks, 1);
    assert.equal(applyClicks, 1);
    await unmount(instance);
  } finally {
    globalThis.window = prev.window;
    globalThis.document = prev.document;
    globalThis.Element = prev.Element;
    globalThis.HTMLElement = prev.HTMLElement;
    globalThis.Node = prev.Node;
    globalThis.Text = prev.Text;
    globalThis.MutationObserver = prev.MutationObserver;
  }
});

test('ENG-FE-007 & UX-ENV-008: formatError strips RuntimeError prefixes, translates plot jargon into plain language, and WorkspaceSidebar cancels inspectAccessSource reads', async () => {
  class FakeRuntimeError extends Error {
    constructor(msg) {
      super(msg);
      this.name = 'RuntimeError';
    }
  }
  const readsMod = loadTypeScript('shared/readRequests.ts', {
    '@wailsio/runtime': {
      Call: { RuntimeError: FakeRuntimeError },
      CancelledRejectionError: class CancelledRejectionError extends Error {},
    },
  });

  assert.equal(readsMod.formatError(new FakeRuntimeError('plot 00337 exists')), 'plot 00337 exists');
  assert.equal(
    readsMod.formatError(new Error('RuntimeError: plot "00337" already exists in Sample_Env')),
    'plot "00337" already exists in Sample_Env'
  );

  const literalTranslated = readsMod.formatError(
    new Error('RuntimeError: literal plot requires 1 to 7 non-whitespace characters')
  );
  assert.doesNotMatch(literalTranslated, /RuntimeError|literal plot requires/i);
  assert.match(literalTranslated, /Plot number/i);

  const membershipTranslated = readsMod.formatError(
    new Error('CallError: certified physical source membership check failed for plot 00337')
  );
  assert.doesNotMatch(membershipTranslated, /CallError|certified physical source membership/i);

  // Verify WorkspaceSidebar inspectAccessSource cancels prior in-flight ReadRequests on re-invocation
  let cancelledCount = 0;
  let resolveFirst;
  let markFirstStarted;
  const firstStarted = new Promise((r) => { markFirstStarted = r; });
  const firstPromise = Object.assign(
    new Promise((r) => { resolveFirst = r; }),
    { cancel() { cancelledCount++; } }
  );
  const secondPromise = Object.assign(
    Promise.resolve({ sourcePath: '/tmp/Legacy.mdb', format: 'MDB', projects: [] }),
    { cancel() {} }
  );
  let callNum = 0;
  const realReads = new readsMod.ReadRequests();
  const sidebarCtx = componentFunctions('WorkspaceSidebar.svelte', ['inspectAccessSource'], {
    accessSourcePath: '/tmp/Legacy.mdb',
    accessRequests: realReads,
    subscribeAccessProgress: () => () => {},
    $projectState: { contextId: 'ctx-sb' },
    ImportExportService: {
      InspectAccessDatabase: () => {
        if (++callNum === 1) {
          queueMicrotask(markFirstStarted);
          return firstPromise;
        }
        return secondPromise;
      },
    },
  });

  const p1 = sidebarCtx.actions.inspectAccessSource('/tmp/Old.mdb');
  await firstStarted;
  const p2 = sidebarCtx.actions.inspectAccessSource('/tmp/Legacy.mdb');
  resolveFirst({ sourcePath: '/tmp/Old.mdb', format: 'MDB', projects: [] });
  await Promise.all([p1, p2]);
  assert.equal(cancelledCount >= 1, true, 'Re-invoking inspectAccessSource must cancel in-flight request');
  assert.equal(sidebarCtx.accessInspection.sourcePath, '/tmp/Legacy.mdb');
});

test('UX-SHELL-008: shell modals/hubs/guides eliminate internal DB/schema/route tokens and deduplicate switchContext error toast', async () => {
  // 1. WhatsNewModal "2 unread release updates." without space before period
  const WhatsNewModal = serverComponent(readSrc('help/WhatsNewModal.svelte'), 'help/WhatsNewModal.svelte');
  const wnHtml = render(WhatsNewModal, {
    props: {
      open: true,
      initialStatus: {
        latestVersion: '2.0.0',
        lastSeenVersion: '',
        hasUnread: true,
        unreadCount: 2,
        entries: [
          {
            version: '2.0.0',
            date: '2026-11-19',
            title: 'Wave 5',
            unread: true,
            highlights: ['Plain-language workspace navigation.'],
          },
        ],
      },
      onclose() {},
    },
  }).body;
  assert.match(wnHtml, /2 unread release updates\./);
  assert.doesNotMatch(wnHtml, /updates\s+\./);

  // 2. HomeWorkspaceHub, WorkspaceSidebar, UserSetupModal, AboutVProModal, LumpEditor copy checks
  for (const [file, forbidden] of [
    ['shell/HomeWorkspaceHub.svelte', /\bSQLite\b|\*_SU\b/],
    ['shell/WorkspaceSidebar.svelte', /\bSQLite\b|~NodeName/],
    ['shell/UserSetupModal.svelte', /USysAccreditation|USysUserRestrictions/],
    ['help/AboutVProModal.svelte', /BCPlantTaxonomy\.db/],
    ['classification/LumpEditor.svelte', /\*_Lump/],
  ]) {
    const src = readSrc(file);
    assert.doesNotMatch(src, forbidden, `${file} must not expose ${forbidden}`);
  }

  // 3. docs-src/guides.json uses "Projects & context" instead of "Session Context bar"
  const guidesJson = readFileSync(path.resolve(__dirname, '../../../docs-src/guides.json'), 'utf8');
  assert.doesNotMatch(guidesJson, /Session Context bar/i);
  assert.match(guidesJson, /Projects & context/i);

  // 4. switchContext failure emits a single error notification (setting lastPushedError so $effect does not duplicate)
  const pushed = [];
  const appCtx = componentFunctions('App.svelte', ['switchContext'], {
    ContextService: {
      SwitchContext: async () => {
        throw new Error('RuntimeError: file is not a database');
      },
    },
    notifications: {
      push: (entry) => pushed.push(entry),
      error() {},
      warning() {},
      info() {},
      success() {},
    },
  });
  await assert.rejects(() => appCtx.actions.switchContext('ctx-1', { project: 'Bad' }, 'plots'));
  assert.equal(pushed.length, 1, 'Expected exactly one toast notification on switchContext failure');
  assert.equal(appCtx.lastPushedError, appCtx.error, 'lastPushedError must match error to suppress duplicate banner toast');
  assert.doesNotMatch(pushed[0].message, /RuntimeError|file is not a database/i);
});
