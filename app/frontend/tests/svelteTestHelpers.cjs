const assert = require('node:assert/strict');
const vm = require('node:vm');
const { existsSync, readdirSync, readFileSync } = require('node:fs');
const path = require('node:path');
const ts = require('typescript');
const { compile } = require('svelte/compiler');
const { readFixtureText, resolveFixturePath } = require('./fixtureLoader.cjs');

const SRC_ROOT = path.resolve(__dirname, '..', 'src');
let cachedByBasename = null;

function buildSrcIndex() {
  const byBase = new Map();
  function walk(dir) {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (!byBase.has(entry.name)) byBase.set(entry.name, full);
    }
  }
  walk(SRC_ROOT);
  cachedByBasename = byBase;
  return byBase;
}

function srcPath(name) {
  const raw = String(name);
  if (path.isAbsolute(raw) && existsSync(raw)) return raw;
  const clean = raw.replaceAll('\\', '/').replace(/^\.\//, '');
  if (clean.startsWith('fixtures/')) {
    try { return resolveFixturePath(clean.slice('fixtures/'.length)).filePath; } catch {}
  }
  const testRelative = path.join(__dirname, clean);
  if (clean.startsWith('fixtures/') && existsSync(testRelative)) return testRelative;
  const direct = path.join(SRC_ROOT, clean);
  if (existsSync(direct)) return direct;
  const base = path.posix.basename(clean);
  const index = cachedByBasename ?? buildSrcIndex();
  if (index.has(base) && existsSync(index.get(base))) return index.get(base);
  const refreshed = buildSrcIndex();
  if (refreshed.has(base) && existsSync(refreshed.get(base))) return refreshed.get(base);
  return direct;
}

function readSrc(name) {
  const clean = String(name).replaceAll('\\', '/').replace(/^\.\//, '');
  if (clean.startsWith('fixtures/')) {
    return readFixtureText(clean.slice('fixtures/'.length));
  }
  return readFileSync(srcPath(name), 'utf8');
}

function srcFiles() {
  const out = [];
  function walk(dir) {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name.endsWith('.svelte') || entry.name.endsWith('.ts')) {
        out.push(path.relative(SRC_ROOT, full).replaceAll('\\', '/'));
      }
    }
  }
  walk(SRC_ROOT);
  return out.sort();
}

function canonicalLocalSpecifier(name) {
  const norm = String(name).replaceAll('\\', '/');
  if ((norm.startsWith('./') || norm.startsWith('../')) && !norm.includes('bindings/') && !norm.includes('resources/')) {
    return './' + path.posix.basename(norm);
  }
  return norm;
}

function resolveDependency(name, dependencies = {}) {
  if (!dependencies || typeof dependencies !== 'object') return { found: false, key: '', value: undefined };
  if (name in dependencies) return { found: true, key: name, value: dependencies[name] };
  const norm = String(name).replaceAll('\\', '/');
  for (const marker of ['bindings/', 'resources/']) {
    const idx = norm.indexOf(marker);
    if (idx !== -1) {
      const suffix = norm.slice(idx);
      for (const key of Object.keys(dependencies)) {
        const kNorm = key.replaceAll('\\', '/');
        const kIdx = kNorm.indexOf(marker);
        if (kIdx !== -1 && kNorm.slice(kIdx) === suffix) {
          return { found: true, key, value: dependencies[key] };
        }
      }
      return { found: false, key: '', value: undefined };
    }
  }
  if (norm.startsWith('./') || norm.startsWith('../')) {
    const base = path.posix.basename(norm);
    const dotBase = './' + base;
    if (dotBase in dependencies) return { found: true, key: dotBase, value: dependencies[dotBase] };
    for (const key of Object.keys(dependencies)) {
      const kNorm = key.replaceAll('\\', '/');
      if ((kNorm.startsWith('./') || kNorm.startsWith('../')) &&
          !kNorm.includes('bindings/') && !kNorm.includes('resources/') &&
          path.posix.basename(kNorm) === base) {
        return { found: true, key, value: dependencies[key] };
      }
    }
  }
  return { found: false, key: '', value: undefined };
}

const serverReads = { ReadRequests: class {
  track(request) { return request; }
  cancelAll() {}
} };

const noopNotificationsStub = {
  notifications: {
    push: () => ({ id: 'stub' }),
    success: () => ({ id: 'stub' }),
    info: () => ({ id: 'stub' }),
    warning: () => ({ id: 'stub' }),
    error: () => ({ id: 'stub' }),
    triggerAction: () => false,
    markRead() {},
    markAllRead() {},
    clearHistory() {},
    dismissToast() {},
    pauseToast() {},
    resumeToast() {},
    subscribe: (fn) => {
      fn({ entries: [], toasts: [], unreadCount: 0, unreadErrorCount: 0, unreadWarningCount: 0, badgeSeverity: 'none' });
      return () => {};
    },
    getSnapshot: () => ({ entries: [], toasts: [], unreadCount: 0, unreadErrorCount: 0, unreadWarningCount: 0, badgeSeverity: 'none' }),
  },
};

function serverComponent(source, filename, dependencies = {}, _environment = {}) {
  const resolvedFilename = srcPath(filename);
  const compiled = compile(source, { filename: resolvedFilename, generate: 'server' });
  assert.equal(compiled.warnings.length, 0);
  const module = { exports: {} };
  const code = ts.transpileModule(compiled.js.code, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, esModuleInterop: false }
  }).outputText;
  vm.runInNewContext(code, {
    module, exports: module.exports, structuredClone,
    require(rawName) {
      const canon = canonicalLocalSpecifier(rawName);
      const matched = resolveDependency(rawName, dependencies);
      if (matched.found) {
        const provided = matched.value;
        if (provided && typeof provided === 'object' && Object.keys(provided).length === 0) {
          if (canon === './longVegetationSelectedUnitSelection') return { createSelectedUnitSelectionRegistry: () => null };
          if (canon === './longVegetationGroupPreferences') return { createLongVegetationGroupPreferencesRegistry: () => null };
          if (canon === './longVegetationNamingPreferences') return { createLongVegetationNamingPreferencesRegistry: () => null };
          if (canon === './longVegetationSelectedFieldPreferences') return { createLongVegetationSelectedFieldPreferencesRegistry: () => null };
          if (canon === './longVegetationEnforcementPreferences') return { createLongVegetationEnforcementPreferencesRegistry: () => null };
          if (canon === './longVegetationUnitPreferences') return { createLongVegetationUnitPreferencesRegistry: () => null };
          if (canon === './longVegetationPreferences') return { longVegetationPreferencesSession: () => null };
          if (canon === './longVegetationStatisticsPreferences') return { longVegetationStatisticsPreferencesSession: () => null };
          if (canon === './longVegetationSwitchPreferences') return { longVegetationSwitchPreferencesSession: () => null };
          if (canon === './longVegetationThresholdPreferences') return { longVegetationThresholdPreferencesSession: () => null };
          if (canon === './longVegetationQualityNullPreferences') return { longVegetationQualityNullPreferencesSession: () => null };
          if (canon === './longVegetationQualityMinimumPreferences') return { longVegetationQualityMinimumPreferencesSession: () => null };
          if (canon === './plotLabelPDFExport') return { plotLabelPDFPublicationSession: () => ({ view: () => ({ busy: false, blocked: false, outcome: null, error: '', requestedDestination: '' }), subscribe: () => () => {} }) };
        }
        return provided;
      }
      if (canon === './notificationService.svelte') return noopNotificationsStub;
      if (canon === './readRequests') return serverReads;
      if (canon === './coordinateConversion') return loadTypeScript('coordinateConversion.ts');
      const qualityDep = resolveDependency('./qualityEditor', dependencies);
      if (canon === './ordinaryEditor') return loadTypeScript('ordinaryEditor.ts', {
        './qualityEditor': qualityDep.found ? qualityDep.value : loadTypeScript('qualityEditor.ts', {
          './becEditor': loadTypeScript('becEditor.ts')
        }),
        './numericEditor': loadTypeScript('numericEditor.ts')
      });
      if (canon === './otherEditor') return loadTypeScript('otherEditor.ts', {
        './qualityEditor': qualityDep.found ? qualityDep.value : loadTypeScript('qualityEditor.ts', {
          './becEditor': loadTypeScript('becEditor.ts')
        })
      });
      if (canon === './soilChildEditor') return loadTypeScript('soilChildEditor.ts', {
        './qualityEditor': qualityDep.found ? qualityDep.value : loadTypeScript('qualityEditor.ts', {
          './becEditor': loadTypeScript('becEditor.ts')
        }),
        './numericEditor': loadTypeScript('numericEditor.ts')
      });
      if (canon === './vegetationAttributeEditor') return loadTypeScript('vegetationAttributeEditor.ts', {
        './numericEditor': loadTypeScript('numericEditor.ts')
      });
      if (canon === './catalogueLookup' && qualityDep.found) {
        return loadTypeScript('catalogueLookup.ts', {
          './qualityEditor': qualityDep.value,
          './readRequests': serverReads
        });
      }
      if (rawName === 'svelte' || rawName.startsWith('svelte/')) return require(rawName);
      if (canon === './ProjectMetadataEditor.svelte') {
        return { default: () => {} };
      }
      if (canon === './summaryVegetationPreferences') {
        return { summaryVegetationPreferenceSession: null };
      }
      if (canon === './summaryVegetationQualityPreferences') {
        return { ...qualityPreferenceHelpers().preferences, summaryVegetationQualityPreferenceSession: null };
      }
      if (canon === './summaryVegetationPresentationPreferences') {
        return { summaryVegetationPresentationPreferenceSession: null };
      }
      if (canon === './summaryVegetationFieldListDesktop') {
        return { summaryVegetationFieldListDesktop: { enabled: false, contextAvailable: () => false } };
      }
      if (canon === './summaryVegetationEnvironmentalDesktop') {
        return { summaryEnvironmentalEnabled: false, summaryEnvironmentalDesktop: {}, summaryEnvironmentalPort: {} };
      }
      if (canon === './SummaryVegetationWorkbookPanel.svelte') {
        return { default: () => {} };
      }
      if (canon === './SummaryVegetationEnvironmental.svelte') return { default: serverComponent(
        readSrc('SummaryVegetationEnvironmental.svelte'),
        'SummaryVegetationEnvironmental.svelte', dependencies) };
      if (canon === './SummaryVegetationFieldList.svelte') return { default: serverComponent(
        readSrc('SummaryVegetationFieldList.svelte'),
        'SummaryVegetationFieldList.svelte', dependencies) };
      if (canon === './summaryVegetationFieldList') return loadTypeScript('summaryVegetationFieldList.ts');
      if (canon === './SummaryVegetationPresentationPreferences.svelte') return { default: serverComponent(
        readSrc('SummaryVegetationPresentationPreferences.svelte'),
        'SummaryVegetationPresentationPreferences.svelte', dependencies) };
      if (canon === './SummaryVegetationQualityPreferences.svelte') return { default: serverComponent(
        readSrc('SummaryVegetationQualityPreferences.svelte'),
        'SummaryVegetationQualityPreferences.svelte', {
          ...dependencies, './summaryVegetationQualityPreferences': qualityPreferenceHelpers().preferences,
        }) };
      if (canon === './longVegetationProjectWorkspaces') {
        return { projectReportWorkspace: null };
      }
      if (canon === './LongVegetationProjectScopeSelection.svelte' || canon === './LongVegetationProjectUnitPreferences.svelte') {
        const compFile = canon.slice(2);
        return { default: serverComponent(readSrc(compFile), compFile, dependencies) };
      }
      if (canon === './FieldGuidance.svelte') return { default: serverComponent(
        readSrc('FieldGuidance.svelte'), 'FieldGuidance.svelte', {}) };
      if (canon === './SIVIChildSourceNotices.svelte') return { default: serverComponent(
        readSrc('SIVIChildSourceNotices.svelte'), 'SIVIChildSourceNotices.svelte', {}) };
      if (canon.startsWith('./') && canon.endsWith('.svelte')) {
        const childBase = canon.slice(2);
        const siblingPath = path.join(path.dirname(resolvedFilename), childBase);
        const targetPath = existsSync(siblingPath) ? siblingPath : srcPath(childBase);
        if (existsSync(targetPath)) {
          return {
            default: serverComponent(readFileSync(targetPath, 'utf8'), targetPath, dependencies),
          };
        }
      }
      throw new Error(`Unexpected renderer dependency ${rawName}`);
    }
  });
  return module.exports.default;
}

function loadTypeScript(filename, dependencies = {}, globals = {}) {
  const module = { exports: {} };
  vm.runInNewContext(ts.transpileModule(readSrc(filename), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, esModuleInterop: true }
  }).outputText, { ...globals, module, exports: module.exports, structuredClone, require(rawName) {
    const canon = canonicalLocalSpecifier(rawName);
    const matched = resolveDependency(rawName, dependencies);
    if (matched.found) return matched.value;
    if (canon === './notificationService.svelte') return noopNotificationsStub;
    const qualityDep = resolveDependency('./qualityEditor', dependencies);
    const restoreDep = resolveDependency('./projectMetadataRestore', dependencies);
    const transportDep = resolveDependency('./siviParentTransport', dependencies);
    const metadataDep = resolveDependency('./projectMetadataEditor', dependencies);
    if (canon === './siviMetadataWire') {
      if (transportDep.found) return transportDep.value;
      const quality = qualityDep.found ? qualityDep.value : loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });
      return loadTypeScript('siviMetadataWire.ts', {
        './projectMetadataRestore': restoreDep.found ? restoreDep.value : loadTypeScript('projectMetadataRestore.ts', {
          './qualityEditor': quality, './projectMetadataEditor': {},
        }),
      });
    }
    if (canon === './pictureCreationActivity') return loadTypeScript('pictureCreationActivity.ts');
    if (canon === './pictureLifecycleActivity') return loadTypeScript('pictureLifecycleActivity.ts');
    if (canon === './twoPageSoilActivity') {
      const quality = qualityDep.found ? qualityDep.value : loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });
      return loadTypeScript('twoPageSoilActivity.ts', { './qualityEditor': quality });
    }
    if (canon === './twoPageVegetationActivity') {
      const quality = qualityDep.found ? qualityDep.value : loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });
      return loadTypeScript('twoPageVegetationActivity.ts', { './qualityEditor': quality });
    }
    if (canon === './qualityMinimumReference') return qualityPreferenceHelpers().reference;
    if (canon === './siviChildSourceNotices') {
      const quality = qualityDep.found ? qualityDep.value : loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });
      const metadata = metadataDep.found ? metadataDep.value : loadTypeScript('projectMetadataEditor.ts', {
        './qualityEditor': quality, '../../resources/project-metadata-standard.json': [], '../../resources/project-metadata-template.json': [],
      });
      return loadTypeScript('siviChildSourceNotices.ts', {
        './heightEditor': loadTypeScript('heightEditor.ts', { './numericEditor': loadTypeScript('numericEditor.ts') }),
        './projectMetadataEditor': metadata,
        './projectMetadataRestore': restoreDep.found ? restoreDep.value : loadTypeScript('projectMetadataRestore.ts', {
          './qualityEditor': quality, './projectMetadataEditor': metadata,
        }),
      });
    }
    if (canon === './spatialCompute') return loadTypeScript('spatial/spatialCompute.ts', dependencies, globals);
    if (canon === './spatialFlatGeobuf') return loadTypeScript('spatial/spatialFlatGeobuf.ts', dependencies, globals);
    if (rawName.endsWith('/fs882-xl-layout.json') || rawName.endsWith('/fs882-extended-shrub-layout.json')) {
      return JSON.parse(readFileSync(path.resolve(__dirname, '../../resources', path.basename(rawName)), 'utf8'));
    }
    if (/^\.\/(fs882Form|ordinaryEditor|qualityEditor|numericEditor|becEditor|heightEditor|otherEditor|soilChildEditor|vegetationAttributeEditor|collectedEditor|vegetationSpeciesEditor|vegetationCreationEditor|personalSpeciesEditor|vegetationDeletionEditor|vegetationReadAvailability|paperLayout)/.test(canon)) {
      return loadTypeScript(`${canon.slice(2)}.ts`, dependencies, globals);
    }
    if (canon.endsWith('bindings/github.com/boostao/vpro/app')) {
      return new Proxy({}, { get: () => new Proxy({}, { get: () => async () => null }) });
    }
    if (canon.endsWith('bindings/events')) {
      return { VproCloseRequest: 'vpro:close-request' };
    }
    throw new Error(`Unexpected TypeScript dependency ${rawName}`);
  } });
  return module.exports;
}
function componentFunctions(filename, names, values) {
  const source = readSrc(filename);
  const baseName = path.basename(String(filename));
  const script = source.match(/<script lang="ts">([\s\S]*?)<\/script>/)[1];
  const ast = ts.createSourceFile(baseName + '.ts', script, ts.ScriptTarget.Latest, true);
  const selected = ast.statements.filter(node => ts.isFunctionDeclaration(node) && names.includes(node.name.text));
  assert.equal(selected.length, names.length);
  const fs882Helpers = baseName === 'FS882Form.svelte'
    ? {
        ...loadTypeScript('fs882FormHelpers.ts'),
        ...loadTypeScript('fs882FormSivi.ts'),
        ...loadTypeScript('fs882FormSiviOps.ts'),
        ...loadTypeScript('fs882FormChildren.ts'),
        ...loadTypeScript('fs882FormVegDrafts.ts'),
        ...loadTypeScript('fs882FormLoadSave.ts'),
      }
    : {};
  const defaultSoilReviewProfile = baseName === 'App.svelte' || baseName === 'FS882Form.svelte'
    ? { ...fs882Helpers, twoPageSoilBusy: false, twoPageSoilBlocked: false, ordinarySoilUnavailable: null, historicalSoilUnavailable: null,
      twoPageVegetationBusy: false, twoPageVegetationBlocked: false, ordinaryVegetationUnavailable: null } : {};
  const context = vm.createContext({ exports: {},
    notifications: noopNotificationsStub.notifications,
    ...(baseName === 'TwoPageEntryEditor.svelte' ? { vegetationTableOpen: false, vegetationTableBusy: false, environmentTableOpen: false, environmentTableBusy: false, projectMetadataOpen: false, projectMetadataBusy: false, profilingOpen: false, profilingBusy: false } : {}),
    ...(baseName === 'SummaryVegetationReport.svelte' ? {
      preferences: null, quality: null, qualityView: null, qualityReadBusy: false,
      qualityMutationHeld: false, qualityInvalid: false, qualityUnavailable: false,
      presentation: null, presentationView: null, presentationReadBusy: false,
      presentationMutationHeld: false, presentationInvalid: false,
      fieldListHeld: false, fieldListBusy: false, environmentalHeld: false,
    } : {}),
    ...(baseName === 'App.svelte' ? { projectReportBusy: false, summaryPreferenceBusy: false, summaryFieldListBusy: false, summaryEnvironmentalBusy: false, externalSUEnvironmentBusy: false, editorInitializing: false, companionPanelBusy: false, workbenchDirtyLabel: '' } : {}), ...defaultSoilReviewProfile, ...values });
  const code = selected.map(node => node.getText(ast)).join('\n') +
    `\nthis.actions = {${names.join(',')}};`;
  vm.runInContext(ts.transpileModule(code, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, alwaysStrict: false
  } }).outputText, context);
  return context;
}
function presentationHelpers() {
  const paper = loadTypeScript('paperLayout.ts', {
    '../../resources/fs882-xl-layout.json': JSON.parse(readFileSync(path.join(__dirname, '..', '..', 'resources', 'fs882-xl-layout.json'), 'utf8')),
    '../../resources/fs882-extended-shrub-layout.json': JSON.parse(readFileSync(path.join(__dirname, '..', '..', 'resources', 'fs882-extended-shrub-layout.json'), 'utf8'))
  });
  return { paper, presentation: loadTypeScript('formPresentation.ts', { './paperLayout': paper }) };
}

function qualityPreferenceHelpers() {
  const quality = loadTypeScript('qualityEditor.ts', { './becEditor': loadTypeScript('becEditor.ts') });
  const cells = loadTypeScript('projectMetadataRestore.ts', { './qualityEditor': quality, './projectMetadataEditor': {} });
  const locations = loadTypeScript('plotLocationReview.ts', { './projectMetadataRestore': cells });
  const earth = loadTypeScript('googleEarthReview.ts', {
    './projectMetadataRestore': cells, './qualityEditor': quality, './plotLocationReview': locations,
  });
  const shared = loadTypeScript('reportTitlePreferences.ts', { './qualityEditor': quality, './googleEarthReview': earth });
  const lifeform = loadTypeScript('lifeformSummary.ts');
  const transport = loadTypeScript('siviParentTransport.ts', {
    './projectMetadataRestore': cells, './siviParentEditor': {}, './siviParentSession': {},
  });
  const reference = loadTypeScript('qualityMinimumReference.ts', {
    './lifeformSummary': lifeform, './projectMetadataRestore': cells, './siviParentTransport': transport,
  });
  return { reference, preferences: loadTypeScript('summaryVegetationQualityPreferences.ts', {
    './googleEarthReview': earth, './lifeformSummary': lifeform, './qualityEditor': quality,
    './qualityMinimumReference': reference, './reportTitlePreferences': shared,
  }) };
}

module.exports = {
  SRC_ROOT,
  srcPath,
  readSrc,
  srcFiles,
  resolveDependency,
  canonicalLocalSpecifier,
  noopNotificationsStub,
  serverComponent,
  loadTypeScript,
  componentFunctions,
  presentationHelpers,
};
