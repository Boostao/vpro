import type { ProjectState } from '../../bindings/github.com/boostao/vpro/app';
import { HelpService } from '../../bindings/github.com/boostao/vpro/app';

export type HelpDrawerTab = 'inspector' | 'keys' | 'guides';
export type HelpMenuAction = 'guide' | 'tours' | 'shortcuts' | 'whats-new' | 'reset-sample' | 'about';

interface HelpCodeOption {
  code: string;
  label: string;
}

interface HelpFieldTopic {
  id: string;
  code: string;
  section: string;
  title: string;
  column: string;
  unit: string;
  lmh25Page: number;
  keyRef?: string;
  summary: string;
  rules: string[];
  codes: HelpCodeOption[];
}

interface HelpDecisionStep {
  step: number;
  prompt: string;
  yes?: string;
  no?: string;
}

export interface HelpDecisionKey {
  id: string;
  code: string;
  title: string;
  lmh25Page: number;
  steps: HelpDecisionStep[];
}

interface HelpGuideSection {
  heading: string;
  body: string;
}

export interface HelpGuide {
  id: string;
  slug: string;
  category: string;
  title: string;
  summary: string;
  sections: HelpGuideSection[];
}

interface HelpTourStep {
  target: string;
  view: string;
  title: string;
  body: string;
}

export interface HelpTour {
  id: string;
  title: string;
  duration: string;
  description: string;
  steps: HelpTourStep[];
}

export interface HelpShortcut {
  keys: string;
  scope: string;
  action: string;
}

interface HelpWhatsNewEntry {
  version: string;
  date: string;
  channel: string;
  highlights: string[];
}

export interface HelpDataUseAgreement {
  title: string;
  authority: string;
  sourceUrl: string;
  citation: string;
  clauses: string[];
}

interface StandardsSourceStamp {
  archiveName: string;
  archiveSha256: string;
  extractedName: string;
  extractedSha256: string;
  version: string;
}

interface StandardsArtifactStamp {
  path: string;
  sha256: string;
  counts: Record<string, number>;
}

interface HelpLibraryStamps {
  schemaVersion: number;
  generator: string;
  becVersion: string;
  becArchiveSha256: string;
  becExtractedSha256: string;
  taxonomyVersion: string;
  taxonomyArchiveSha256: string;
  taxonomyExtractedSha256: string;
  lmh25Edition: string;
  lmh25Pdf2023Sha256: string;
  sources: StandardsSourceStamp[];
  artifacts: StandardsArtifactStamp[];
}

export type BuildMode = 'dev' | 'alpha' | 'release' | string;

export interface AboutInfo {
  productName: string;
  fullName: string;
  organization: string;
  appVersion: string;
  buildMode: BuildMode;
  gitCommit: string;
  buildDate: string;
  isPrerelease: boolean;
  unsignedNotice: boolean;
  schemaVersion: string;
  releaseChannel: string;
  configPath: string;
  dataDir: string;
  libraryStamps: HelpLibraryStamps;
}

export function formatShortCommit(sha?: string | null): string {
  const trimmed = (sha ?? '').trim();
  if (!trimmed) return '';
  if (/^[0-9a-f]{8,40}$/i.test(trimmed)) {
    return trimmed.slice(0, 7);
  }
  return trimmed;
}

export interface HelpBundle {
  schemaVersion: number;
  productName: string;
  fullName: string;
  organization: string;
  lmh25Edition: string;
  libraryStamps: HelpLibraryStamps;
  fields: HelpFieldTopic[];
  decisionKeys: HelpDecisionKey[];
  guides: HelpGuide[];
  tours: HelpTour[];
  shortcuts: HelpShortcut[];
  whatsNew: HelpWhatsNewEntry[];
  dataUseAgreement: HelpDataUseAgreement;
}

export interface HelpLookupResult {
  requestedId: string;
  resolvedId: string;
  matchKind: string;
  field?: HelpFieldTopic;
  decisionKey?: HelpDecisionKey;
  relatedGuides: HelpGuide[];
}

export interface HelpSearchHit {
  kind: 'field' | 'key' | 'guide' | 'shortcut' | 'tour' | string;
  id: string;
  code?: string;
  title: string;
  section?: string;
  snippet: string;
  lmh25Page?: number;
  score: number;
}

export interface WhatsNewStatus {
  latestVersion: string;
  lastSeenVersion: string;
  hasUnread: boolean;
  unreadCount: number;
  entries: HelpWhatsNewEntry[];
}

export interface HelpBackendPort {
  getHelpBundle(): Promise<HelpBundle>;
  lookupHelpTopic(helpId: string): Promise<HelpLookupResult>;
  searchHelp(query: string): Promise<HelpSearchHit[]>;
  getWhatsNewStatus(): Promise<WhatsNewStatus>;
  acknowledgeWhatsNew(version: string): Promise<WhatsNewStatus>;
  getAboutInfo(): Promise<AboutInfo>;
  resetWorkspaceToSample(contextId: string): Promise<ProjectState>;
}

export const defaultHelpPort: HelpBackendPort = {
  getHelpBundle() {
    return HelpService.GetHelpBundle() as never;
  },
  lookupHelpTopic(helpId: string) {
    return HelpService.LookupHelpTopic(helpId) as never;
  },
  searchHelp(query: string) {
    return HelpService.SearchHelp(query) as never;
  },
  getWhatsNewStatus() {
    return HelpService.GetWhatsNewStatus() as never;
  },
  acknowledgeWhatsNew(version: string) {
    return HelpService.AcknowledgeWhatsNew(version) as never;
  },
  getAboutInfo() {
    return HelpService.GetAboutInfo() as never;
  },
  resetWorkspaceToSample(contextId: string) {
    return HelpService.ResetWorkspaceToSample(contextId) as never;
  },
};

const COLUMN_TO_HELP_ID: Record<string, string> = {
  plotnumber: 'site.plot_number',
  plot: 'site.plot_number',
  fieldnumber: 'site.field_number',
  projectid: 'site.field_number',
  date: 'site.date',
  startdate: 'site.date',
  sitesurveyor: 'site.date',
  vegsurveyor: 'site.date',
  soilsurveyor: 'site.date',
  zone: 'site.bgc_zone',
  subzone: 'site.bgc_zone',
  siteseries: 'site.bgc_zone',
  becsiteunit: 'site.bgc_zone',
  usersiteunit: 'site.bgc_zone',
  mapunit: 'site.bgc_zone',
  plotrepresenting: 'site.bgc_zone',
  representing: 'site.bgc_zone',
  transdistrib: 'site.bgc_zone',
  ecosection: 'site.ecosection',
  fsregiondistrict: 'site.ecosection',
  forestregiondistrict: 'site.ecosection',
  latitude: 'site.coordinates',
  longitude: 'site.coordinates',
  utmzone: 'site.coordinates',
  utmeasting: 'site.coordinates',
  utmnorthing: 'site.coordinates',
  locationaccuracy: 'site.coordinates',
  ntsmapsheet: 'site.coordinates',
  location: 'site.coordinates',
  elevation: 'site.elevation',
  slopegradient: 'site.elevation',
  aspect: 'site.elevation',
  exposure1: 'site.elevation',
  exposure2: 'site.elevation',
  mesoslopeposition: 'site.meso_slope',
  surfaceshape: 'site.meso_slope',
  surfacetopographytype: 'site.meso_slope',
  surfacetopographysize: 'site.meso_slope',
  moistureregime: 'site.moisture_regime',
  nutrientregime: 'site.nutrient_regime',
  substratedecwood: 'site.substrate_cover',
  substratebedrock: 'site.substrate_cover',
  substraterocks: 'site.substrate_cover',
  substratemineralsoil: 'site.substrate_cover',
  substrateorganicmatter: 'site.substrate_cover',
  substratewater: 'site.substrate_cover',
  structuralstage: 'site.successional_structural',
  successionalstatus: 'site.successional_structural',
  standage: 'site.successional_structural',
  sitedisturbance1: 'site.successional_structural',
  sitedisturbance2: 'site.successional_structural',
  sitedisturbance3: 'site.successional_structural',
  floodingregimedur: 'soil.rooting_seepage',
  floodingregimefreq: 'soil.rooting_seepage',
  realmclass: 'site.realm_class',
  snowcoverregime: 'site.realm_class',
  activelayerdepth: 'site.realm_class',
  humusform: 'humus.humus_form',
  humusformphase: 'humus.humus_form',
  humusformph: 'humus.humus_form',
  humusstructuredegree: 'humus.humus_form',
  humusstructurekind: 'humus.humus_form',
  mycelabundance: 'humus.humus_form',
  fecalabundance: 'humus.humus_form',
  consistence: 'humus.humus_form',
  character: 'humus.humus_form',
  fauna: 'humus.humus_form',
  humusthickness: 'humus.upper_lower_depth',
  vonpost: 'humus.von_post',
  pitdepthlimit: 'mineral.horizon',
  texture: 'mineral.texture_cf',
  colour: 'mineral.texture_cf',
  mineralformph: 'mineral.texture_cf',
  percentcoarsefragstotal: 'mineral.texture_cf',
  percentcoarsefragsgravel: 'mineral.texture_cf',
  percentcoarsefragscobbles: 'mineral.texture_cf',
  percentcoarsefragsstones: 'mineral.texture_cf',
  percentcoarsefragsshape: 'mineral.texture_cf',
  mineralstructureclass: 'mineral.texture_cf',
  mineralstructurekind: 'mineral.texture_cf',
  mottlesabundance: 'mineral.texture_cf',
  mottlessize: 'mineral.texture_cf',
  mottlescontrast: 'mineral.texture_cf',
  clayfilmsfreq: 'mineral.texture_cf',
  clayfilmthickness: 'mineral.texture_cf',
  effervescence: 'mineral.texture_cf',
  porosity: 'mineral.texture_cf',
  gravel: 'mineral.texture_cf',
  cobbles: 'mineral.texture_cf',
  stones: 'mineral.texture_cf',
  rootingdepth: 'soil.rooting_seepage',
  rootrestrictingtype: 'soil.rooting_seepage',
  rootrestrictingdepth: 'soil.rooting_seepage',
  rootzoneparticlesize: 'soil.rooting_seepage',
  rootsabundance: 'soil.rooting_seepage',
  rootssize: 'soil.rooting_seepage',
  seepagedepth: 'soil.rooting_seepage',
  soildrainage: 'soil.rooting_seepage',
  soilclassgroup: 'soil.rooting_seepage',
  soilclasssubgroup: 'soil.rooting_seepage',
  watersource: 'soil.rooting_seepage',
  hydrogeosystem: 'soil.rooting_seepage',
  hydrogeosubsystem: 'soil.rooting_seepage',
  sitemodifier1: 'site.bgc_zone',
  sitemodifier2: 'site.bgc_zone',
  gis_bgc: 'site.bgc_zone',
  bec_use: 'site.bgc_zone',
  species: 'veg.species',
  layer: 'veg.species',
  collected: 'veg.species',
  af: 'veg.species',
  dc: 'veg.species',
  ut: 'veg.species',
  vi: 'veg.species',
  pv: 'veg.species',
  pg: 'veg.species',
  ffa: 'veg.species',
  cultural1: 'veg.species',
  cultural2: 'veg.species',
  other1: 'veg.species',
  other2: 'veg.species',
  ll: 'veg.species',
  plottype: 'sivi.plot_type',
};

function mapColumnToHelpId(
  column: string | null | undefined,
  domain?: 'site' | 'humus' | 'mineral' | 'veg' | 'sivi'
): string | null {
  if (!column) return null;
  const normalized = column.trim().toLowerCase();
  if (!normalized) return null;

  if (normalized === 'horizon') {
    return domain === 'mineral' ? 'mineral.horizon' : 'humus.horizon';
  }
  if (normalized === 'upperdepth' || normalized === 'lowerdepth') {
    return domain === 'mineral' ? 'mineral.horizon' : 'humus.upper_lower_depth';
  }
  if (
    normalized.startsWith('cover') ||
    normalized.startsWith('height') ||
    normalized === 'totala' ||
    normalized === 'totalb'
  ) {
    return 'veg.covers';
  }
  if (normalized.startsWith('substrate')) {
    return 'site.substrate_cover';
  }
  if (normalized in COLUMN_TO_HELP_ID) {
    return COLUMN_TO_HELP_ID[normalized];
  }
  if (domain === 'sivi') {
    return 'sivi.plot_type';
  }
  return null;
}

function defaultHelpTopicForView(view: string, entryForm: 'fs882' | 'sivi' | 'fs882-twopage' = 'fs882'): string {
  if ((view === 'fs882' || view === 'fs882-twopage') && entryForm === 'sivi') return 'sivi.plot_type';
  switch (view) {
    case 'fs882':
    case 'fs882-twopage':
      return 'site.moisture_regime';
    case 'datasheet':
      return 'veg.covers';
    case 'geospatial-map':
    case 'plot-locations':
    case 'google-earth-review':
      return 'site.coordinates';
    case 'diagnostic-synthesis':
    case 'classification-explorer':
    case 'hierarchy':
    case 'subzone-matrix':
      return 'site.bgc_zone';
    case 'lump-editor':
    case 'long-vegetation':
    case 'summary-vegetation':
    case 'lifeform-summary':
      return 'veg.species';
    case 'r-sidecar':
    case 'long-environment':
    case 'summary-environment':
      return 'site.moisture_regime';
    default:
      return 'site.plot_number';
  }
}

interface HelpInspectableElement {
  parentElement?: HelpInspectableElement | null;
  getAttribute?(name: string): string | null;
  closest?(selector: string): HelpInspectableElement | null;
}

const CONTEXTUAL_FIELD_ATTRIBUTES = [
  ['data-two-page-entry-field', 'site'],
  ['data-two-page-common-field', 'site'],
  ['data-two-page-field', 'site'],
  ['data-sivi-shared-field', 'sivi'],
  ['data-sivi-parent-field', 'sivi'],
  ['data-chars-field', 'sivi'],
] as const;

function inferContextualDomain(
  origin: HelpInspectableElement | null | undefined,
  entryForm: 'fs882' | 'sivi' | 'fs882-twopage',
  fallbackDomain: 'site' | 'humus' | 'mineral' | 'veg' | 'sivi'
): 'site' | 'humus' | 'mineral' | 'veg' | 'sivi' {
  const twoPageSoil = origin?.closest?.('[data-two-page-soil-panel]')?.getAttribute?.('data-two-page-soil-panel') ?? '';
  if (twoPageSoil === 'SoilMineralXL') return 'mineral';
  if (twoPageSoil === 'SoilHumusXL') return 'humus';

  const sourceForm = origin?.closest?.('[data-source-form]')?.getAttribute?.('data-source-form') ?? '';
  if (sourceForm === 'SoilMineralXL') return 'mineral';
  if (sourceForm === 'SoilHumusXL') return 'humus';
  if (sourceForm.startsWith('SubVeg') || sourceForm.startsWith('USysVeg')) return 'veg';

  const dsTable = origin?.closest?.('[data-datasheet-table]')?.getAttribute?.('data-datasheet-table') ?? '';
  if (dsTable === 'Mineral') return 'mineral';
  if (dsTable === 'Humus') return 'humus';
  if (dsTable === 'Veg') return 'veg';

  if (fallbackDomain === 'site' && entryForm === 'sivi') return 'sivi';
  return fallbackDomain;
}

function resolveAttributesOnNode(
  node: HelpInspectableElement,
  origin: HelpInspectableElement,
  entryForm: 'fs882' | 'sivi' | 'fs882-twopage'
): string | null {
  if (typeof node.getAttribute !== 'function') return null;

  const soilCol = node.getAttribute('data-soil-column');
  if (soilCol) {
    const soilDomain = inferContextualDomain(origin, entryForm, 'humus') === 'mineral' ? 'mineral' : 'humus';
    const mapped = mapColumnToHelpId(soilCol, soilDomain);
    if (mapped) return mapped;
  }

  for (const [attr, domain] of CONTEXTUAL_FIELD_ATTRIBUTES) {
    const col = node.getAttribute(attr);
    if (col) {
      const mapped = mapColumnToHelpId(col, domain);
      if (mapped) return mapped;
    }
  }

  const colAttr = node.getAttribute('data-column');
  if (colAttr) {
    const colDomain = inferContextualDomain(origin, entryForm, 'site');
    const mapped = mapColumnToHelpId(colAttr, colDomain);
    if (mapped) return mapped;
  }

  const directId = node.getAttribute('data-help-id')?.trim();
  if (directId) {
    return directId;
  }

  return null;
}

export function resolveContextualHelpTarget(
  activeElement: HelpInspectableElement | null | undefined,
  view: string,
  entryForm: 'fs882' | 'sivi' | 'fs882-twopage' = 'fs882'
): string {
  if (activeElement) {
    // Walk from the focused control upward so closer field/column attributes always beat outer container data-help-id wrappers.
    let current: HelpInspectableElement | null | undefined = activeElement;
    let walkedParentChain = false;
    while (current) {
      const resolved = resolveAttributesOnNode(current, activeElement, entryForm);
      if (resolved) return resolved;
      if (current.parentElement !== undefined) {
        walkedParentChain = true;
      }
      current = current.parentElement ?? null;
    }

    // Fallback for lightweight closest()-only test doubles without parentElement chains:
    // evaluate field-specific attributes before container-level [data-help-id].
    if (!walkedParentChain && typeof activeElement.closest === 'function') {
      const soilColHolder = activeElement.closest('[data-soil-column]');
      const soilCol = soilColHolder?.getAttribute?.('data-soil-column');
      if (soilCol) {
        const soilDomain = inferContextualDomain(activeElement, entryForm, 'humus') === 'mineral' ? 'mineral' : 'humus';
        const mapped = mapColumnToHelpId(soilCol, soilDomain);
        if (mapped) return mapped;
      }

      for (const [attr, domain] of CONTEXTUAL_FIELD_ATTRIBUTES) {
        const holder = activeElement.closest(`[${attr}]`);
        const col = holder?.getAttribute?.(attr);
        if (col) {
          const mapped = mapColumnToHelpId(col, domain);
          if (mapped) return mapped;
        }
      }

      const colHolder = activeElement.closest('[data-column]');
      const colAttr = colHolder?.getAttribute?.('data-column');
      if (colAttr) {
        const colDomain = inferContextualDomain(activeElement, entryForm, 'site');
        const mapped = mapColumnToHelpId(colAttr, colDomain);
        if (mapped) return mapped;
      }

      const directHolder = activeElement.closest('[data-help-id]');
      const directId = directHolder?.getAttribute?.('data-help-id')?.trim();
      if (directId) {
        return directId;
      }
    }
  }

  return defaultHelpTopicForView(view, entryForm);
}

function isEditableTarget(
  target:
    { tagName?: string; isContentEditable?: boolean; getAttribute?: (name: string) => string | null } | null | undefined
): boolean {
  if (!target) return false;
  if (target.isContentEditable) return true;
  const tag = (target.tagName ?? '').toUpperCase();
  if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return true;
  const role = target.getAttribute?.('role');
  return role === 'textbox' || role === 'combobox' || role === 'searchbox';
}

export function classifyGlobalHelpShortcut(
  event: {
    key: string;
    ctrlKey?: boolean;
    metaKey?: boolean;
    altKey?: boolean;
    shiftKey?: boolean;
    defaultPrevented?: boolean;
  },
  activeElement:
    { tagName?: string; isContentEditable?: boolean; getAttribute?: (name: string) => string | null } | null | undefined
): 'f1' | 'shortcuts' | null {
  if (event.defaultPrevented) return null;
  if (event.key === 'F1') {
    return 'f1';
  }
  if ((event.ctrlKey || event.metaKey) && !event.altKey && (event.key === '/' || event.key === '?')) {
    return 'shortcuts';
  }
  if (event.key === '?' && !event.ctrlKey && !event.metaKey && !event.altKey) {
    if (!isEditableTarget(activeElement)) {
      return 'shortcuts';
    }
  }
  return null;
}

interface DecisionKeyHistoryItem {
  step: number;
  prompt: string;
  choice: 'yes' | 'no';
  outcome: string;
}

export interface DecisionKeyEvalState {
  keyId: string;
  currentStep: number;
  completed: boolean;
  conclusion: string | null;
  history: DecisionKeyHistoryItem[];
}

export function isDichotomousDecisionKey(key: HelpDecisionKey | null | undefined): boolean {
  if (!key || !Array.isArray(key.steps) || key.steps.length === 0) return false;
  return key.steps.some((step) => Boolean(step.yes || step.no));
}

export function createDecisionKeyState(key: HelpDecisionKey): DecisionKeyEvalState {
  const firstStep = key.steps[0]?.step ?? 1;
  return {
    keyId: key.id,
    currentStep: firstStep,
    completed: false,
    conclusion: null,
    history: [],
  };
}

export function answerDecisionKeyStep(
  key: HelpDecisionKey,
  state: DecisionKeyEvalState,
  choice: 'yes' | 'no'
): DecisionKeyEvalState {
  if (state.completed) return state;
  const stepObj = key.steps.find((s) => s.step === state.currentStep);
  if (!stepObj) return state;
  const outcome = (choice === 'yes' ? stepObj.yes : stepObj.no) ?? '';
  const nextHistory: DecisionKeyHistoryItem[] = [
    ...state.history,
    {
      step: stepObj.step,
      prompt: stepObj.prompt,
      choice,
      outcome,
    },
  ];
  const gotoMatch = outcome.match(/^Go to Step\s+(\d+)/i);
  if (gotoMatch) {
    const nextStepNum = Number.parseInt(gotoMatch[1], 10);
    if (key.steps.some((s) => s.step === nextStepNum)) {
      return {
        keyId: key.id,
        currentStep: nextStepNum,
        completed: false,
        conclusion: null,
        history: nextHistory,
      };
    }
  }
  return {
    keyId: key.id,
    currentStep: stepObj.step,
    completed: true,
    conclusion: outcome || 'Completed',
    history: nextHistory,
  };
}

interface CoverPatchRect {
  x: number;
  y: number;
  w: number;
  h: number;
}

interface CoverComparisonBlock {
  percent: number;
  label: string;
  areaM2: string;
  equivalentSquare: string;
  patches: CoverPatchRect[];
}

function generateDeterministicPatches(percent: number): CoverPatchRect[] {
  // 100 x 100 coordinate frame = 100 m2 (10 m x 10 m plot; 10,000 SVG units^2 total).
  // Every plate uses pairwise-disjoint rectangles whose exact union area equals percent * 100.
  switch (percent) {
    case 0.1:
      return [{ x: 48.4, y: 48.4, w: 3.2, h: 3.125 }];
    case 1:
      return [
        { x: 14, y: 18, w: 4, h: 4 },
        { x: 68, y: 20, w: 4, h: 3 },
        { x: 38, y: 44, w: 5, h: 4 },
        { x: 74, y: 62, w: 4.5, h: 4 },
        { x: 20, y: 72, w: 4, h: 4 },
        { x: 52, y: 80, w: 4.5, h: 4 },
      ];
    case 5:
      return [
        { x: 10, y: 12, w: 10, h: 10 },
        { x: 58, y: 14, w: 9, h: 9 },
        { x: 34, y: 38, w: 11, h: 10 },
        { x: 72, y: 52, w: 9, h: 9 },
        { x: 16, y: 68, w: 9, h: 8 },
        { x: 50, y: 76, w: 8, h: 7 },
      ];
    case 10:
      return [
        { x: 8, y: 8, w: 13, h: 13 },
        { x: 46, y: 10, w: 12, h: 11 },
        { x: 76, y: 16, w: 12, h: 11 },
        { x: 24, y: 38, w: 14, h: 13 },
        { x: 62, y: 44, w: 13, h: 12 },
        { x: 12, y: 68, w: 11, h: 11 },
        { x: 48, y: 74, w: 12, h: 9 },
      ];
    case 25:
      return [
        { x: 6, y: 6, w: 22, h: 20 },
        { x: 42, y: 8, w: 18, h: 16 },
        { x: 70, y: 12, w: 20, h: 18 },
        { x: 16, y: 36, w: 24, h: 20 },
        { x: 54, y: 42, w: 22, h: 18 },
        { x: 8, y: 68, w: 20, h: 16 },
        { x: 46, y: 70, w: 18, h: 12 },
      ];
    case 50:
      return [
        { x: 4, y: 4, w: 30, h: 28 },
        { x: 42, y: 6, w: 24, h: 24 },
        { x: 72, y: 8, w: 23, h: 28 },
        { x: 8, y: 38, w: 28, h: 26 },
        { x: 44, y: 38, w: 28, h: 25 },
        { x: 6, y: 69, w: 34, h: 21 },
        { x: 48, y: 68, w: 38, h: 21 },
      ];
    case 75:
      return [
        { x: 2, y: 2, w: 45, h: 42 },
        { x: 52, y: 2, w: 46, h: 36 },
        { x: 2, y: 48, w: 40, h: 48 },
        { x: 49, y: 42, w: 48, h: 28 },
        { x: 49, y: 74, w: 46, h: 15 },
      ];
    default:
      return [];
  }
}

export const COVER_COMPARISON_BLOCKS: readonly CoverComparisonBlock[] = [
  {
    percent: 0.1,
    label: '0.1%',
    areaM2: '0.1 m² / 100 m²',
    equivalentSquare: '0.32 m × 0.32 m',
    patches: generateDeterministicPatches(0.1),
  },
  {
    percent: 1,
    label: '1%',
    areaM2: '1 m² / 100 m²',
    equivalentSquare: '1.00 m × 1.00 m',
    patches: generateDeterministicPatches(1),
  },
  {
    percent: 5,
    label: '5%',
    areaM2: '5 m² / 100 m²',
    equivalentSquare: '2.24 m × 2.24 m',
    patches: generateDeterministicPatches(5),
  },
  {
    percent: 10,
    label: '10%',
    areaM2: '10 m² / 100 m²',
    equivalentSquare: '3.16 m × 3.16 m',
    patches: generateDeterministicPatches(10),
  },
  {
    percent: 25,
    label: '25%',
    areaM2: '25 m² / 100 m²',
    equivalentSquare: '5.00 m × 5.00 m (1 quadrant)',
    patches: generateDeterministicPatches(25),
  },
  {
    percent: 50,
    label: '50%',
    areaM2: '50 m² / 100 m²',
    equivalentSquare: '7.07 m × 7.07 m (half plot)',
    patches: generateDeterministicPatches(50),
  },
  {
    percent: 75,
    label: '75%',
    areaM2: '75 m² / 100 m²',
    equivalentSquare: '8.66 m × 8.66 m (3 quadrants)',
    patches: generateDeterministicPatches(75),
  },
];

const TOUR_VIEW_LABELS: Record<string, string> = {
  home: 'Home',
  plots: 'Plots',
  fs882: 'FS882 Plot Entry',
  'fs882-twopage': 'Two-Page Entry',
  datasheet: 'Datasheet',
  'classification-explorer': 'SU & Hierarchy Explorer',
  'geospatial-map': '3D Map',
  'diagnostic-synthesis': 'BEC Diagnostics',
  'r-sidecar': 'R Companion',
  'interchange-hub': 'Interchange Hub',
  'project-admin': 'Project Admin',
  'lump-editor': 'Combine Species',
  'cloud-sync': 'Cloud Sync',
  pictures: 'Plot Pictures',
  'picture-manager': 'Plot Pictures',
  'long-veg': 'Long Vegetation Report',
  'long-vegetation': 'Long Vegetation Report',
  'summary-veg': 'Summary Vegetation Report',
  'summary-vegetation': 'Summary Vegetation Report',
  'long-environment': 'Long Environment Report',
  'summary-environment': 'Summary Environment Report',
  'lifeform-summary': 'Lifeform Summary Report',
  'subzone-matrix': 'Subzone Matrix Report',
  hierarchy: 'Hierarchy Table',
  'table-csv': 'Table CSV Archive',
  'user-log': 'User Log',
  'plot-locations': 'Plot Locations',
  'google-earth-review': 'Google Earth (KML)',
  'plot-label-preview': 'Plot Label PDF',
};

export function formatTourViewLabel(view: string | null | undefined): string {
  const key = (view ?? '').trim();
  if (!key) return 'Workspace';
  if (key in TOUR_VIEW_LABELS) return TOUR_VIEW_LABELS[key];
  return key
    .split(/[-_\s]+/)
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
}

export interface TourBoxRect {
  top: number;
  left: number;
  width: number;
  height: number;
}

export function computeTourDialogLayout(
  viewportWidth: number,
  viewportHeight: number,
  targetRect: TourBoxRect | null,
  overlaps: (a: TourBoxRect, b: TourBoxRect, pad?: number) => boolean
): { placement: string; style: string } {
  const margin = viewportWidth < 640 ? 12 : 20;
  const cardHeightEst = 270;
  if (viewportWidth < 640) {
    const targetBottom = targetRect ? targetRect.top + targetRect.height : 0;
    const topFlip =
      !!targetRect && targetRect.top > viewportHeight * 0.45 && targetBottom > viewportHeight - cardHeightEst;
    return {
      placement: topFlip ? 'mobile-top' : 'mobile-bottom',
      style: topFlip
        ? `top:${margin}px;bottom:auto;left:${margin}px;right:${margin}px;width:auto;max-width:calc(100vw - ${margin * 2}px);`
        : `bottom:${margin}px;top:auto;left:${margin}px;right:${margin}px;width:auto;max-width:calc(100vw - ${margin * 2}px);`,
    };
  }

  const cardW = Math.min(448, Math.max(280, viewportWidth - margin * 2));
  const candidates: Array<{ name: string; box: TourBoxRect; style: string }> = [
    {
      name: 'bottom-right',
      box: {
        top: viewportHeight - margin - cardHeightEst,
        left: viewportWidth - margin - cardW,
        width: cardW,
        height: cardHeightEst,
      },
      style: `right:${margin}px;bottom:${margin}px;left:auto;top:auto;width:${cardW}px;max-width:calc(100vw - ${margin * 2}px);`,
    },
    {
      name: 'top-right',
      box: { top: margin + 56, left: viewportWidth - margin - cardW, width: cardW, height: cardHeightEst },
      style: `right:${margin}px;top:${margin + 56}px;left:auto;bottom:auto;width:${cardW}px;max-width:calc(100vw - ${margin * 2}px);`,
    },
    {
      name: 'bottom-left',
      box: { top: viewportHeight - margin - cardHeightEst, left: margin, width: cardW, height: cardHeightEst },
      style: `left:${margin}px;bottom:${margin}px;right:auto;top:auto;width:${cardW}px;max-width:calc(100vw - ${margin * 2}px);`,
    },
    {
      name: 'top-left',
      box: { top: margin + 56, left: margin, width: cardW, height: cardHeightEst },
      style: `left:${margin}px;top:${margin + 56}px;right:auto;bottom:auto;width:${cardW}px;max-width:calc(100vw - ${margin * 2}px);`,
    },
  ];

  if (targetRect) {
    const clear = candidates.find((c) => !overlaps(c.box, targetRect));
    if (clear) {
      return { placement: clear.name, style: clear.style };
    }
  }
  return { placement: candidates[0].name, style: candidates[0].style };
}
