const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { render } = require('svelte/server');
const { loadTypeScript, serverComponent, srcPath, canonicalLocalSpecifier } = require('./svelteTestHelpers.cjs');

const wailsStub = {
  Call: {
    ByName: () => Promise.resolve(null),
  },
};

const grid = loadTypeScript('universalDatasheetGrid.ts', {
  '@wailsio/runtime': wailsStub,
});
const cls = loadTypeScript('classificationExplorer.ts', {
  '@wailsio/runtime': wailsStub,
});
const plain = value => JSON.parse(JSON.stringify(value));

test('phytosociological wide rank schema exposes all 12 rank columns incl. Superclass and Subclass', () => {
  assert.deepEqual(
    plain(cls.PHYTOSOCIOLOGICAL_RANK_COLUMNS.map(c => c.label)),
    [
      'Superclass',
      'Class',
      'Subclass',
      'Order',
      'SubOrder',
      'Alliance',
      'SubAlliance',
      'Association',
      'SubAssociation',
      'Facies',
      'WorkingUnit',
      'SiteSeries',
    ]
  );
});

test('flattenVisibleSUTree renders unit folders, draggable plot leaves, and Unassigned Plots bucket', () => {
  const tree = {
    contextId: 'ctx-1',
    project: 'Sample',
    projectPath: '/data/Sample.db',
    su: 'Sample',
    suPath: '/data/Sample.db',
    totalProject: 3,
    totalAssigned: 2,
    totalUnassigned: 1,
    orphanPlots: [],
    units: [
      {
        siteUnit: 'CWHvm1/01',
        longName: 'HwBa - Blueberry',
        origin: 'master',
        maskValid: true,
        plotCount: 2,
        plots: [
          { plotNumber: '00337', fieldNumber: 'F1', zone: 'CWH', subZone: 'vm1', siteSeries: '01', userSiteUnit: '', moistureRegime: '4', nutrientRegime: 'C', elevation: 320, siteUnit: 'CWHvm1/01', presentInSu: true, inProjectEnv: true, locked: false },
          { plotNumber: '108050', fieldNumber: 'F2', zone: 'CWH', subZone: 'vm1', siteSeries: '01', userSiteUnit: '', moistureRegime: '5', nutrientRegime: 'D', elevation: 410, siteUnit: 'CWHvm1/01', presentInSu: true, inProjectEnv: true, locked: false },
        ],
      },
    ],
    unassignedPlots: [
      { plotNumber: '202050', fieldNumber: 'F3', zone: 'MH', subZone: 'mm1', siteSeries: '', userSiteUnit: '', moistureRegime: '', nutrientRegime: '', elevation: null, siteUnit: '', presentInSu: false, inProjectEnv: true, locked: false },
    ],
  };

  const collapsed = cls.flattenVisibleSUTree(tree, new Set());
  assert.equal(collapsed.length, 2); // unit::CWHvm1/01 + bucket::__unassigned__

  const expanded = cls.flattenVisibleSUTree(
    tree,
    new Set(['unit::CWHvm1/01', cls.UNASSIGNED_BUCKET_ID])
  );
  assert.equal(expanded.length, 5);
  assert.equal(expanded[1].label, '00337');
  assert.equal(expanded[4].label, '202050');
});

test('WAI-ARIA tree keyboard navigation handles ArrowUp/Down/Left/Right/Home/End/Enter', () => {
  const items = [
    { id: 'unit::A', parentId: null, expandable: true, expanded: false },
    { id: 'unit::B', parentId: null, expandable: true, expanded: true },
    { id: 'plot::B::1', parentId: 'unit::B', expandable: false, expanded: false },
  ];

  // ArrowRight on collapsed folder -> expand
  assert.deepEqual(plain(cls.resolveAriaTreeKeyAction(items, 'unit::A', 'ArrowRight')), {
    type: 'expand',
    targetId: 'unit::A',
  });
  // ArrowRight on expanded folder -> focus first child
  assert.deepEqual(plain(cls.resolveAriaTreeKeyAction(items, 'unit::B', 'ArrowRight')), {
    type: 'focus',
    targetId: 'plot::B::1',
  });
  // ArrowLeft on child leaf -> focus parent folder
  assert.deepEqual(plain(cls.resolveAriaTreeKeyAction(items, 'plot::B::1', 'ArrowLeft')), {
    type: 'focus',
    targetId: 'unit::B',
  });
  // ArrowLeft on expanded folder -> collapse
  assert.deepEqual(plain(cls.resolveAriaTreeKeyAction(items, 'unit::B', 'ArrowLeft')), {
    type: 'collapse',
    targetId: 'unit::B',
  });
  assert.deepEqual(plain(cls.resolveAriaTreeKeyAction(items, 'unit::A', 'End')), {
    type: 'focus',
    targetId: 'plot::B::1',
  });
  assert.deepEqual(plain(cls.resolveAriaTreeKeyAction(items, 'plot::B::1', 'Home')), {
    type: 'focus',
    targetId: 'unit::A',
  });
});

test('hierarchy cycle detection, ~ breakpoint toggle, BEC mask check, and flat row validation', () => {
  const nodes = [
    { id: 1, parent: null },
    { id: 2, parent: 1 },
    { id: 3, parent: 2 },
  ];
  assert.equal(cls.wouldIntroduceHierarchyCycle(nodes, 1, 1), true);
  assert.equal(cls.wouldIntroduceHierarchyCycle(nodes, 1, 3), true);
  assert.equal(cls.wouldIntroduceHierarchyCycle(nodes, 3, 1), false);
  assert.equal(cls.wouldIntroduceHierarchyCycle(nodes, 2, null), false);

  assert.equal(cls.toggleBreakpointName('Tsugion'), '~Tsugion');
  assert.equal(cls.toggleBreakpointName('~Tsugion'), 'Tsugion');

  assert.equal(cls.isValidBECUnitMask('CWHvm1/01'), true);
  assert.equal(cls.isValidBECUnitMask('SBSmk2/05'), true);
  assert.equal(cls.isValidBECUnitMask('MyWorkingUnit'), false);

  const okErr = cls.validateFlatHierarchyRows([
    { ...cls.createEmptyFlatHierarchyRow(), class: 'Vaccinio-Piceetea', order: '~Piceetalia', siteSeries: 'CWHvm1/01' },
    { ...cls.createEmptyFlatHierarchyRow(), class: 'Vaccinio-Piceetea', order: '~Piceetalia', siteSeries: 'CWHvm1/05' },
  ]);
  assert.equal(okErr, '');

  const conflictErr = cls.validateFlatHierarchyRows([
    { ...cls.createEmptyFlatHierarchyRow(), class: 'ClassA', order: 'SharedOrder', siteSeries: 'CWHvm1/01' },
    { ...cls.createEmptyFlatHierarchyRow(), class: 'ClassB', order: 'SharedOrder', siteSeries: 'CWHvm1/05' },
  ]);
  assert.match(conflictErr, /conflicting parents/);
});

test('ClassificationExplorer.svelte compiles with zero warnings, renders all 3 modes, and has zero emojis', () => {
  const svelteSource = readFileSync(srcPath('ClassificationExplorer.svelte'), 'utf8');
  assert.equal(/\p{Extended_Pictographic}/u.test(svelteSource), false, 'must contain zero emojis');

  const exclusionSvc = loadTypeScript('siteUnitExclusionFilter.ts', {
    '@wailsio/runtime': wailsStub,
  });
  const exclusionComponent = serverComponent(
    readFileSync(srcPath('SiteUnitExclusionFilter.svelte'), 'utf8'),
    'SiteUnitExclusionFilter.svelte',
    {
      './siteUnitExclusionFilter': exclusionSvc,
    }
  );
  const Component = serverComponent(svelteSource, 'ClassificationExplorer.svelte', {
    './classificationExplorer': cls,
    './universalDatasheetGrid': grid,
    './SiteUnitExclusionFilter.svelte': { default: exclusionComponent },
  });

  const suRender = render(Component, {
    props: { contextId: 'ctx-1', project: 'Sample', su: 'Sample', hierarchy: 'Sample', initialMode: 'su_tree' },
  });
  assert.match(suRender.body, /data-tour="classification-explorer-root"/);
  assert.match(suRender.body, /role="tree"/);
  assert.match(suRender.body, /BECdb v13 Unit Picker/);
  assert.match(suRender.body, /UserSiteUnitList/);
  assert.match(suRender.body, /Site Unit Exclusion Rules/);

  const flatRender = render(Component, {
    props: { contextId: 'ctx-1', project: 'Sample', su: 'Sample', hierarchy: 'Sample', initialMode: 'hierarchy_flat' },
  });
  assert.match(flatRender.body, /Wide Phytosociological Rank Editor/);
  assert.match(flatRender.body, /Save Hierarchy As/);
  assert.match(flatRender.body, /SubAlliance/);
});

test('ClassificationExplorer avoids duplicate reload races on self-activated SU creation and warns when 0 rows change on assignment', async () => {
  const vm = require('node:vm');
  const ts = require('typescript');
  const { compile } = require('svelte/compiler');
  const client = await import('svelte/internal/client');

  const appSrc = readFileSync(srcPath('shell/ShellDeferredViews.svelte'), 'utf8');
  const clsSectionStart = appSrc.indexOf("{:else if view === 'classification-explorer'");
  const clsSectionEnd = appSrc.indexOf("{:else if view === 'project-admin'");
  assert.ok(clsSectionStart > 0 && clsSectionEnd > clsSectionStart);
  assert.doesNotMatch(
    appSrc.slice(clsSectionStart, clsSectionEnd),
    /\{#key \$projectState\.contextId\}/,
    'classification-explorer must update in place without #key remount'
  );

  let script = readFileSync(srcPath('ClassificationExplorer.svelte'), 'utf8').match(
    /<script lang="ts">([\s\S]*?)<\/script>/
  )[1];
  script = script.replace(
    "onRequestSUSync?: (direction: 'su_to_env' | 'env_to_su') => void;",
    "onRequestSUSync?: (direction: 'su_to_env' | 'env_to_su') => void; inspect?: (v: any) => void;"
  );
  script = script.replace('onRequestSUSync,', 'onRequestSUSync, inspect,');
  script += `\n$effect(() => inspect?.({
    setNewSUName(name) { newSUName = name; },
    submitCreateSU,
    assignPlots,
    getState: () => ({ effectiveContextId, statusBanner, errorMessage }),
  }));`;

  const compiled = compile(`<script lang="ts">${script}</script>`, { generate: 'client' });
  assert.equal(compiled.warnings.length, 0);
  const modObj = { exports: {} };
  vm.runInNewContext(
    ts.transpileModule(compiled.js.code, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    }).outputText,
    {
      module: modObj,
      exports: modObj.exports,
      structuredClone,
      queueMicrotask,
      CSS: { escape: s => s },
      require(name) {
        if (name === 'svelte') {
          return {
            onMount: fn => fn(),
            onDestroy: () => {},
            untrack: client.untrack,
          };
        }
        if (name === 'svelte/internal/client') return client;
        if (name.startsWith('svelte/')) return require(name);
        const canon = canonicalLocalSpecifier(name);
        if (canon === './readRequests') return { ReadRequests: class { track(p) { return p; } cancelAll() {} } };
        if (canon === './universalDatasheetGrid') return grid;
        if (canon === './classificationExplorer') return cls;
        throw new Error(`Unexpected module ${name}`);
      },
    }
  );

  const treeLoads = [];
  const ctxProp = client.state('ctx-1');
  let api;
  const dispose = client.effect_root(() => {
    modObj.exports.default(null, {
      get contextId() {
        return client.get(ctxProp);
      },
      project: 'Sample',
      su: 'Sample',
      hierarchy: 'Sample',
      port: {
        getSUPlotTree: async cid => {
          treeLoads.push(cid);
          return {
            contextId: cid,
            project: 'Sample',
            projectPath: '/Sample.db',
            su: 'Sample',
            suPath: '/Sample.db',
            totalProject: 1,
            totalAssigned: 1,
            totalUnassigned: 0,
            orphanPlots: [],
            units: [],
            unassignedPlots: [],
          };
        },
        searchBECUnitPicker: async () => [],
        createSUTable: async () => ({
          contextId: 'ctx-2',
          name: 'Working2026',
          tableName: 'Working2026_SU',
          filePath: '/Sample.db',
          plotCount: 14,
          activated: true,
          newState: { contextId: 'ctx-2' },
        }),
        assignPlotsToSiteUnit: async cid => ({
          contextId: cid,
          su: 'Sample',
          tableName: 'Sample_SU',
          changedPlots: 0,
          historyId: 0,
        }),
      },
      onContextChanged: nextId => {
        // Simulate asynchronous parent refresh updating contextId prop on a later tick
        setTimeout(() => {
          client.set(ctxProp, nextId);
          client.flush();
        }, 5);
      },
      inspect: v => {
        api = v;
      },
    });
  });

  try {
    client.flush();
    await new Promise(r => setTimeout(r, 10));
    client.flush();
    assert.deepEqual(treeLoads, ['ctx-1']);
    treeLoads.length = 0;

    api.setNewSUName('Working2026');
    client.flush();
    await api.submitCreateSU();
    client.flush();
    // Wait for delayed parent contextId update
    await new Promise(r => setTimeout(r, 20));
    client.flush();

    // Must have loaded 'ctx-2' ONCE without reverting to 'ctx-1' or firing a duplicate 'ctx-2' reload!
    assert.equal(api.getState().effectiveContextId, 'ctx-2');
    assert.deepEqual(treeLoads, ['ctx-2']);
    assert.match(api.getState().statusBanner, /Created and activated Working2026_SU/);

    // 0 changed rows on AssignPlotsToSiteUnit must explain why 0 rows changed
    await api.assignPlots(['00337'], 'CWHvm1/01');
    client.flush();
    assert.match(api.getState().statusBanner, /0 plot\(s\) changed.*already assigned|read-only/i);
  } finally {
    dispose();
  }
});

test('UX-CLASS-001: rows under an existing Superclass validate without false parent conflicts', () => {
  const empty = cls.createEmptyFlatHierarchyRow();
  assert.equal(empty.superclass, '');
  assert.equal(empty.subclass, '');
  const loaded = { ...empty, superclass: 'Conifer Forests', class: 'ClassA', subclass: 'SubclassA', siteSeries: 'SS01' };
  const added = { ...empty, superclass: 'Conifer Forests', class: 'ClassA', siteSeries: 'QA_NEW_SERIES' };
  assert.equal(cls.validateFlatHierarchyRows([loaded, added]), '');
  const hiddenParent = { ...empty, class: 'ClassA', siteSeries: 'QA_NEW_SERIES' };
  assert.match(cls.validateFlatHierarchyRows([loaded, hiddenParent]), /conflicting parents/);
});

test('UX-CLASS-001: Sample_Hierarchy ClassA/ClassB rows validate cleanly and enforce rank/breakpoint/UTF-16 rules', () => {
  const empty = cls.createEmptyFlatHierarchyRow();
  const sampleRows = [
    {
      ...empty,
      leafId: -370059454,
      superclass: 'Conifer Forests',
      class: 'ClassA',
      subclass: 'SubClassA',
      order: 'ORDER Tsugmer',
      subOrder: 'SUBORDER Tsugmer-Coptasp',
      subAlliance: 'SubAllianceA',
      association: '~ASSOC Tsugmer-Phylemp-Cladina',
      subAssociation: 'SUBASS Hm-Phylemp-Cladina(Abieama)',
      facies: 'FaciesA',
      siteSeries: 'MH  whp  /02',
    },
    {
      ...empty,
      leafId: 1212739030,
      superclass: 'Conifer Forests',
      class: 'ClassA',
      subclass: 'SubClassA',
      order: 'ORDER Tsugmer',
      subOrder: 'SUBORDER Tsugmer-Coptasp',
      subAlliance: 'SubAllianceB',
      association: '~ASSOC Tsugmer-Cassste',
      subAssociation: 'SUBASS Hm-Cassste(Veravir)',
      facies: 'Facies - B',
      siteSeries: 'MH  whp  /01',
    },
    {
      ...empty,
      leafId: -1218107202,
      superclass: 'Conifer Forests',
      class: 'ClassB',
      facies: 'ClassLess',
      siteSeries: 'BWBSdk 2 /06',
    },
    {
      ...empty,
      superclass: 'Conifer Forests',
      class: 'ClassA',
      siteSeries: 'QA_NEW_SERIES',
    },
  ];
  assert.equal(cls.validateFlatHierarchyRows(sampleRows), '');

  // Repeated ~ prefixes normalize consistently with Go SplitBreakpointPrefix
  assert.equal(cls.toggleBreakpointName('~~Tsugion'), 'Tsugion');
  assert.match(
    cls.validateFlatHierarchyRows([{ ...empty, class: '~~   ' }]),
    /empty breakpoint node/
  );
  assert.match(
    cls.validateFlatHierarchyRows([
      { ...empty, superclass: 'Conifer Forests', class: 'ClassA', siteSeries: 'SS01' },
      { ...empty, superclass: 'Conifer Forests', order: 'ClassA', siteSeries: 'SS02' },
    ]),
    /conflicting ranks/
  );
  assert.match(
    cls.validateFlatHierarchyRows([{ ...empty, siteSeries: 'A'.repeat(256) }]),
    /255 UTF-16 code units/
  );
});

test('UX-CLASS-005: ClassificationLeftTreePane surfaces cyclic hierarchy nodes with warning banner, Cycle badges, and Root reparent default', async () => {
  const leftPaneSource = readFileSync(srcPath('ClassificationLeftTreePane.svelte'), 'utf8');
  assert.equal(/\p{Extended_Pictographic}/u.test(leftPaneSource), false, 'ClassificationLeftTreePane must contain zero emojis');

  const LeftPane = serverComponent(leftPaneSource, 'ClassificationLeftTreePane.svelte', {
    './classificationExplorer': cls,
  });

  const cycleHierarchyView = {
    contextId: 'ctx-cycle',
    project: 'Sample',
    hierarchy: 'QA_CycleHier',
    hierarchyPath: '/Sample.db',
    tableName: 'QA_CycleHier_Hierarchy',
    roots: [
      {
        id: 1,
        name: 'CycleA',
        cleanName: 'CycleA',
        parent: 2,
        level: 2,
        rankName: 'Class',
        isBreakpoint: false,
        depth: 0,
        children: [
          {
            id: 2,
            name: 'CycleB',
            cleanName: 'CycleB',
            parent: 1,
            level: 4,
            rankName: 'Order',
            isBreakpoint: false,
            depth: 1,
            children: [],
          },
        ],
      },
      {
        id: 3,
        name: 'SelfCycle',
        cleanName: 'SelfCycle',
        parent: 3,
        level: 6,
        rankName: 'Alliance',
        isBreakpoint: false,
        depth: 0,
        children: [],
      },
      {
        id: 4,
        name: 'ValidRoot',
        cleanName: 'ValidRoot',
        parent: null,
        level: 2,
        rankName: 'Class',
        isBreakpoint: false,
        depth: 0,
        children: [
          {
            id: 5,
            name: 'ValidLeaf',
            cleanName: 'ValidLeaf',
            parent: 4,
            level: 11,
            rankName: 'SiteSeries',
            isBreakpoint: false,
            depth: 1,
            children: [],
          },
        ],
      },
    ],
    flatNodes: [
      { id: 1, name: 'CycleA', cleanName: 'CycleA', parent: 2, level: 2, rankName: 'Class', isBreakpoint: false, depth: 0, children: [] },
      { id: 2, name: 'CycleB', cleanName: 'CycleB', parent: 1, level: 4, rankName: 'Order', isBreakpoint: false, depth: 1, children: [] },
      { id: 3, name: 'SelfCycle', cleanName: 'SelfCycle', parent: 3, level: 6, rankName: 'Alliance', isBreakpoint: false, depth: 0, children: [] },
      { id: 4, name: 'ValidRoot', cleanName: 'ValidRoot', parent: null, level: 2, rankName: 'Class', isBreakpoint: false, depth: 0, children: [] },
      { id: 5, name: 'ValidLeaf', cleanName: 'ValidLeaf', parent: 4, level: 11, rankName: 'SiteSeries', isBreakpoint: false, depth: 1, children: [] },
    ],
    flatRankRows: [],
    diagnostics: {
      totalNodes: 5,
      rootNodes: 3,
      breakpointNodes: 0,
      blankNameNodes: 0,
      orphanNodes: [],
      cycleNodeIds: [1, 2, 3],
    },
  };

  const flatItems = cls.flattenVisibleHierarchyTree(cycleHierarchyView.roots, new Set([1, 2, 3, 4]));
  assert.deepEqual(
    plain(flatItems.map(i => i.name)),
    ['CycleA', 'CycleB', 'SelfCycle', 'ValidRoot', 'ValidLeaf']
  );

  const rendered = render(LeftPane, {
    props: {
      mode: 'hierarchy_tree',
      treeRowHeight: 34,
      suFilterText: '',
      suTree: null,
      flatSUItems: [],
      suVirtualSlice: { startIndex: 0, endIndex: 0, topSpacerPx: 0, bottomSpacerPx: 0 },
      visibleSUItems: [],
      selectedPlots: [],
      lastHistoryId: 0,
      hierarchyView: cycleHierarchyView,
      flatHierarchyItems: flatItems,
      hierVirtualSlice: { startIndex: 0, endIndex: flatItems.length, topSpacerPx: 0, bottomSpacerPx: 0 },
      visibleHierarchyItems: flatItems,
      selectedHierarchyNodeId: 1,
      expandedHierarchyIds: [1, 2, 3, 4],
      treeScrollTop: 0,
      treeViewportHeight: 480,
      mutating: false,
      onLoadSUTree: () => {},
      onOpenDialog: () => {},
      onUndoLast: () => {},
      onToggleSUExpand: () => {},
      onPlotClick: () => {},
      onPlotDragStart: () => {},
      onBucketDrop: () => {},
      onAssignPlots: () => {},
      onToggleHierarchyExpand: () => {},
      onSelectHierarchyNode: () => {},
      onToggleBreak: () => {},
    },
  });

  assert.match(rendered.body, /data-hierarchy-cycle-banner/);
  assert.match(rendered.body, /Parent cycle detected \(3 nodes\)/);
  assert.match(rendered.body, /CycleA \(#1\)/);
  assert.match(rendered.body, /CycleB \(#2\)/);
  assert.match(rendered.body, /SelfCycle \(#3\)/);
  assert.equal((rendered.body.match(/data-hierarchy-cycle-badge/g) ?? []).length, 3);

  // Verify client-side auto-expand of cycle nodes and Root-default selection for cyclic nodes
  const vm = require('node:vm');
  const ts = require('typescript');
  const { compile } = require('svelte/compiler');
  const client = await import('svelte/internal/client');

  let paneScript = leftPaneSource.match(/<script lang="ts">([\s\S]*?)<\/script>/)[1];
  paneScript = paneScript.replace(
    'onToggleBreak: (nodeId: number) => void;',
    'onToggleBreak: (nodeId: number) => void; inspect?: (v: any) => void;'
  );
  paneScript = paneScript.replace('onToggleBreak,', 'onToggleBreak, inspect,');
  paneScript += `\n$effect(() => inspect?.({ selectHierarchyTreeNode }));`;

  const compiled = compile(`<script lang="ts">${paneScript}</script>`, { generate: 'client' });
  assert.equal(compiled.warnings.length, 0);
  const modObj = { exports: {} };
  vm.runInNewContext(
    ts.transpileModule(compiled.js.code, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    }).outputText,
    {
      module: modObj,
      exports: modObj.exports,
      queueMicrotask,
      CSS: { escape: s => s },
      require(name) {
        if (name === 'svelte/internal/client') return client;
        if (name.startsWith('svelte/')) return require(name);
        if (canonicalLocalSpecifier(name) === './classificationExplorer') return cls;
        throw new Error(`Unexpected module ${name}`);
      },
    }
  );

  const expandedState = client.state([999999]); // simulate switching from another hierarchy
  const selections = [];
  let paneApi;
  const dispose = client.effect_root(() => {
    modObj.exports.default(null, {
      mode: 'hierarchy_tree',
      treeRowHeight: 34,
      suFilterText: '',
      suTree: null,
      flatSUItems: [],
      suVirtualSlice: { startIndex: 0, endIndex: 0, topSpacerPx: 0, bottomSpacerPx: 0 },
      visibleSUItems: [],
      selectedPlots: [],
      lastHistoryId: 0,
      hierarchyView: cycleHierarchyView,
      flatHierarchyItems: flatItems,
      hierVirtualSlice: { startIndex: 0, endIndex: flatItems.length, topSpacerPx: 0, bottomSpacerPx: 0 },
      visibleHierarchyItems: flatItems,
      selectedHierarchyNodeId: null,
      get expandedHierarchyIds() {
        return client.get(expandedState);
      },
      set expandedHierarchyIds(next) {
        client.set(expandedState, next);
      },
      treeScrollTop: 0,
      treeViewportHeight: 480,
      mutating: false,
      onLoadSUTree: () => {},
      onOpenDialog: () => {},
      onUndoLast: () => {},
      onToggleSUExpand: () => {},
      onPlotClick: () => {},
      onPlotDragStart: () => {},
      onBucketDrop: () => {},
      onAssignPlots: () => {},
      onToggleHierarchyExpand: () => {},
      onSelectHierarchyNode: (id, name, pid) => selections.push([id, name, pid]),
      onToggleBreak: () => {},
      inspect: v => {
        paneApi = v;
      },
    });
  });

  try {
    client.flush();
    assert.deepEqual(plain(client.get(expandedState)), [999999, 1, 2, 3]);

    // Selecting CycleA (whose stored parent is 2, a cycle partner) defaults reparent target to null (Root)
    paneApi.selectHierarchyTreeNode(1, 'CycleA', 2);
    // Selecting ValidLeaf (whose stored parent is 4, acyclic) preserves parent 4
    paneApi.selectHierarchyTreeNode(5, 'ValidLeaf', 4);
    assert.deepEqual(selections, [
      [1, 'CycleA', null],
      [5, 'ValidLeaf', 4],
    ]);
  } finally {
    dispose();
  }
});
