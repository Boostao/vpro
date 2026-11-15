export type FieldCardFormKind = 'fs882' | 'two-page' | 'sivi';
export type FieldCardSide = 'front' | 'back' | 'both';
export type FieldCardTheme = 'bw' | 'classic';

export interface FieldCardCell {
  key: string;
  label: string;
  value: string;
  span?: number;
  mono?: boolean;
  checkbox?: boolean | null;
  isDraft?: boolean;
}

export interface FieldCardOrganicHorizonRow {
  id: string;
  horizon: string;
  upperDepth: number | null;
  lowerDepth: number | null;
  depthRange: string;
  fabricStructure: string;
  mycelFecal: string;
  roots: string;
  vonPost: string;
  ph: string;
  comment: string;
  isDraft: boolean;
}

export interface FieldCardMineralHorizonRow {
  id: string;
  horizon: string;
  upperDepth: number | null;
  lowerDepth: number | null;
  depthRange: string;
  texture: string;
  colour: string;
  coarseFrags: string;
  roots: string;
  structure: string;
  ph: string;
  comments: string;
  isDraft: boolean;
}

export interface FieldCardTreeShrubRow {
  id: string;
  species: string;
  collected: string;
  cover1: string;
  height1: string;
  cover2: string;
  height2: string;
  cover3: string;
  height3: string;
  totalA: string;
  cover4: string;
  height4: string;
  cover5: string;
  height5: string;
  cover5a: string;
  cover5b: string;
  cover5c: string;
  totalB: string;
  isDraft: boolean;
}

export interface FieldCardHerbRow {
  id: string;
  species: string;
  collected: string;
  cover6: string;
  height6: string;
  isDraft: boolean;
}

export interface FieldCardMossRow {
  id: string;
  species: string;
  collected: string;
  cover7: string;
  cover8: string;
  cover9: string;
  isDraft: boolean;
}

export interface TypedMetadataCellLike {
  storage: string;
  text?: string | null;
  integer?: string | null;
  real?: number | null;
  blobHex?: string | null;
}

export interface SIVIParentOriginalLike {
  Plot?: string;
  Project?: string;
  EnvTable?: string;
  EnvColumns?: readonly { name: string }[];
  AdminColumns?: readonly { name: string }[];
  Bindings?: readonly { ControlID: string; Binding: string; Table: string; Column: number }[];
  Rows?: readonly {
    Env: { rowId: string; cells: readonly TypedMetadataCellLike[] };
    Admin: { rowId: string; cells: readonly TypedMetadataCellLike[] };
  }[];
}

export interface StagedParentCellDraftLike {
  input?: { kind: string; raw?: string; value?: boolean; option?: number | null };
  value?: TypedMetadataCellLike;
  raw?: string;
  nullValue?: boolean;
  error?: string | null;
}

export interface SoilDraftsLike {
  [identity: string]: {
    kind: 'Humus' | 'Mineral';
    id: number;
    cells: Record<string, { raw: string; expected: string | number | null; value: string | number | null; error: string | null }>;
  };
}

export interface HeightDraftsLike {
  [rowId: string]: Record<string, { raw: string; expected: number | null; value: number | null; error: string | null } | undefined>;
}

export interface SpeciesDraftsLike {
  [rowId: string]: { form?: string; raw: string; expected?: string | null; error?: string | null };
}

export interface CollectedDraftsLike {
  [rowId: string]: { value: string | null; expected?: string | null; form?: string };
}

export interface CreationDraftLike {
  form: string;
  species: string;
  cells: Record<string, { raw?: string; value?: number | null; error?: string | null } | undefined>;
}

export interface BuildFieldCardInput {
  formKind?: FieldCardFormKind;
  committedHeader?: Record<string, unknown> | null;
  draftHeader?: Record<string, unknown> | null;
  siviParentOriginal?: SIVIParentOriginalLike | null;
  siviSharedDrafts?: Record<string, StagedParentCellDraftLike | undefined>;
  siviDirectDrafts?: Record<string, StagedParentCellDraftLike | undefined>;
  siviActionDrafts?: Record<string, StagedParentCellDraftLike | undefined>;
  siviProjectText?: string | null;
  twoPageOriginal?: SIVIParentOriginalLike | null;
  twoPageDrafts?: Record<string, StagedParentCellDraftLike | undefined>;
  twoPageProjectText?: string | null;
  humusRows?: readonly Record<string, unknown>[];
  mineralRows?: readonly Record<string, unknown>[];
  soilDrafts?: SoilDraftsLike;
  vegRows?: readonly Record<string, unknown>[];
  heightDrafts?: HeightDraftsLike;
  speciesDrafts?: SpeciesDraftsLike;
  collectedDrafts?: CollectedDraftsLike;
  creationDraft?: CreationDraftLike | null;
  extendedShrubs?: boolean;
  snowCoverRegimeRaw?: string | null;
  activeLayerDepthRaw?: string | null;
  isDirty?: boolean;
}

export interface FieldCardViewModel {
  formKind: FieldCardFormKind;
  formCode: string;
  ministryHeader: string;
  cardTitle: string;
  plotNumber: string;
  becUnitMask: string;
  formattedCoordinates: string;
  substrateTotal: number | null;
  substrateTotalDisplay: string;
  extendedShrubs: boolean;
  isDirty: boolean;
  front: {
    identityCells: FieldCardCell[];
    locationCells: FieldCardCell[];
    becEdatopicCells: FieldCardCell[];
    topographyQualityCells: FieldCardCell[];
    substrateCells: FieldCardCell[];
    surfaceTerrainCells: FieldCardCell[];
    subsurfaceTerrainCells: FieldCardCell[];
    geologyCells: FieldCardCell[];
    soilSummaryCells: FieldCardCell[];
    organicHorizons: FieldCardOrganicHorizonRow[];
    mineralHorizons: FieldCardMineralHorizonRow[];
    notes: {
      siteNotes: string;
      officeNotes: string;
      soilNotes: string;
    };
  };
  back: {
    vegSurveyCells: FieldCardCell[];
    strataCoverCells: FieldCardCell[];
    showExtendedShrubColumns: boolean;
    treeShrubRows: FieldCardTreeShrubRow[];
    herbRows: FieldCardHerbRow[];
    mossRows: FieldCardMossRow[];
    vegNotes: string;
  };
}

const COLUMN_ALIASES: Record<string, readonly string[]> = {
  PlotNumber: ['plotNumber', 'PlotNumber'],
  FieldNumber: ['fieldNo', 'FieldNumber'],
  Date: ['date', 'Date'],
  ProjectID: ['projectId', 'ProjectID'],
  StartDate: ['startDate', 'StartDate'],
  SiteSurveyor: ['surveyor', 'SiteSurveyor'],
  PlotType: ['plotType', 'PlotType'],
  PlotSize: ['plotSize', 'PlotSize'],
  SV_PolygonNumber: ['svPolygonNumber', 'SV_PolygonNumber'],
  Location: ['generalLocation', 'Location'],
  FSRegionDistrict: ['fsRegionDistrict', 'FSRegionDistrict'],
  Ecosection: ['ecosection', 'Ecosection'],
  NtsMapSheet: ['mapSheet', 'NtsMapSheet'],
  UTMZone: ['utmZone', 'UTMZone'],
  UTMEasting: ['easting', 'UTMEasting'],
  UTMNorthing: ['northing', 'UTMNorthing'],
  LocationAccuracy: ['accuracy', 'LocationAccuracy'],
  AirPhotoNum: ['airPhotoNum', 'AirPhotoNum'],
  XCoord: ['xCoord', 'XCoord'],
  YCoord: ['yCoord', 'YCoord'],
  Latitude: ['latitude', 'Latitude'],
  Longitude: ['longitude', 'Longitude'],
  ProvinceStateTerritory: ['provinceStateTerritory', 'ProvinceStateTerritory'],
  BECSiteUnit: ['becSiteUnit', 'BECSiteUnit'],
  UserSiteUnit: ['userSiteUnit', 'UserSiteUnit'],
  Zone: ['zone', 'Zone'],
  SubZone: ['subZone', 'SubZone'],
  SiteSeries: ['siteSeries', 'SiteSeries'],
  PlotRepresenting: ['plotRepresenting', 'PlotRepresenting'],
  RealmClass: ['realmClass', 'RealmClass'],
  TransDistrib: ['transition', 'TransDistrib'],
  MapUnit: ['mapUnit', 'MapUnit'],
  GIS_BGC: ['gisBgc', 'GIS_BGC'],
  GIS_BGC_VER: ['gisBgcVer', 'GIS_BGC_VER'],
  BEC_Use: ['becUse', 'BEC_Use'],
  SiteUnitLongName: ['siteUnitLongName', 'SiteUnitLongName'],
  MoistureRegime: ['moistureRegime', 'MoistureRegime'],
  NutrientRegime: ['nutrientRegime', 'NutrientRegime'],
  SuccessionalStatus: ['successional', 'SuccessionalStatus'],
  StructuralStage: ['structuralStage', 'StructuralStage'],
  StandAge: ['standAge', 'StandAge'],
  SV_StandAgeEstMeas: ['svStandAgeEstMeas', 'SV_StandAgeEstMeas'],
  SV_StandHeight: ['svStandHeight', 'SV_StandHeight'],
  SV_StandHeightEstMeas: ['svStandHeightEstMeas', 'SV_StandHeightEstMeas'],
  SV_CanopyComposition: ['svCanopyComposition', 'SV_CanopyComposition'],
  Elevation: ['elevation', 'Elevation'],
  SlopeGradient: ['slope', 'SlopeGradient'],
  Aspect: ['aspect', 'Aspect'],
  MesoSlopePosition: ['mesoSlopePos', 'MesoSlopePosition'],
  SurfaceShape: ['surfaceShape', 'SurfaceShape'],
  SurfaceTopographyType: ['microtopType', 'SurfaceTopographyType'],
  SurfaceTopographySize: ['microtopSize', 'SurfaceTopographySize'],
  Exposure1: ['exposure1', 'Exposure1'],
  Exposure2: ['exposure2', 'Exposure2'],
  SiteDisturbance1: ['siteDisturbance1', 'SiteDisturbance1'],
  SiteDisturbance2: ['siteDisturbance2', 'SiteDisturbance2'],
  SiteDisturbance3: ['siteDisturbance3', 'SiteDisturbance3'],
  SitePlotQuality: ['sitePlotQuality', 'SitePlotQuality'],
  VegPlotQuality: ['vegPlotQuality', 'VegPlotQuality'],
  SoilPlotQuality: ['soilPlotQuality', 'SoilPlotQuality'],
  SnowCoverregime: ['snowCoverRegime', 'SnowCoverregime'],
  ActiveLayerDepth: ['activeLayerDepth', 'ActiveLayerDepth'],
  SubstrateOrganicMatter: ['substrateOrganicMatter', 'SubstrateOrganicMatter'],
  SubstrateDecWood: ['substrateDecWood', 'SubstrateDecWood'],
  SubstrateBedRock: ['substrateBedRock', 'SubstrateBedRock'],
  SubstrateRocks: ['substrateRocks', 'SubstrateRocks'],
  SubstrateMineralSoil: ['substrateMineralSoil', 'SubstrateMineralSoil'],
  SubstrateWater: ['substrateWater', 'SubstrateWater'],
  TerrainTextureSurf: ['terrainTextureSurf', 'TerrainTextureSurf'],
  SurficialMaterialSurf: ['surficialMaterialSurf', 'SurficialMaterialSurf'],
  SurfaceExpSurf: ['surfaceExpSurf', 'SurfaceExpSurf'],
  GeoMorProSurf: ['geoMorProSurf', 'GeoMorProSurf'],
  TerrainTextureSubSurf: ['terrainTextureSubSurf', 'TerrainTextureSubSurf'],
  SurficialMaterialSubSurf: ['surficialMaterialSubSurf', 'SurficialMaterialSubSurf'],
  SurfaceExpSubSurf: ['surfaceExpSubSurf', 'SurfaceExpSubSurf'],
  GeoMorProSubSurf: ['geoMorProSubSurf', 'GeoMorProSubSurf'],
  BedrockGeology1: ['bedrockGeology1', 'BedrockGeology1'],
  BedrockGeology2: ['bedrockGeology2', 'BedrockGeology2'],
  BedrockGeology3: ['bedrockGeology3', 'BedrockGeology3'],
  CoarseFragLith1: ['coarseFragLith1', 'CoarseFragLith1'],
  CoarseFragLith2: ['coarseFragLith2', 'CoarseFragLith2'],
  CoarseFragLith3: ['coarseFragLith3', 'CoarseFragLith3'],
  MensPlotNumber: ['mensPlotNumber', 'MensPlotNumber'],
  SoilSurveyor: ['soilSurveyor', 'SoilSurveyor'],
  SoilClassSubGroup: ['soilClassSubGroup', 'SoilClassSubGroup'],
  SoilClassGroup: ['soilClassGroup', 'SoilClassGroup'],
  SV_AhorizonType: ['svAhorizonType', 'SV_AhorizonType'],
  SV_AhorizonDepth: ['svAhorizonDepth', 'SV_AhorizonDepth'],
  HumusForm: ['humusForm', 'HumusForm'],
  HumusFormPhase: ['humusFormPhase', 'HumusFormPhase'],
  HumusThickness: ['humusThickness', 'HumusThickness'],
  HydroGeoSystem: ['hydroGeoSystem', 'HydroGeoSystem'],
  HydroGeoSubSystem: ['hydroGeoSubSystem', 'HydroGeoSubSystem'],
  RootingDepth: ['rootingDepth', 'RootingDepth'],
  RootZoneParticleSize: ['rootZoneParticleSize', 'RootZoneParticleSize'],
  RootRestrictingType: ['rootRestrictingType', 'RootRestrictingType'],
  RootRestrictingDepth: ['rootRestrictingDepth', 'RootRestrictingDepth'],
  SV_RootZoneTexture: ['svRootZoneTexture', 'SV_RootZoneTexture'],
  SV_SoilDepth: ['svSoilDepth', 'SV_SoilDepth'],
  SV_PercentCoarseFrags: ['svPercentCoarseFrags', 'SV_PercentCoarseFrags'],
  WaterSource: ['waterSource', 'WaterSource'],
  SoilDrainage: ['soilDrainage', 'SoilDrainage'],
  SeepageDepth: ['seepageDepth', 'SeepageDepth'],
  FloodingRegimeFreq: ['floodingRegimeFreq', 'FloodingRegimeFreq'],
  FloodingRegimeDur: ['floodingRegimeDur', 'FloodingRegimeDur'],
  SV_GleyingMottlingCM: ['svGleyingMottlingCm', 'SV_GleyingMottlingCM'],
  SV_FloodPlain: ['svFloodPlain', 'SV_FloodPlain'],
  SV_WaterTableCM: ['svWaterTableCm', 'SV_WaterTableCM'],
  SiteNotes: ['fieldNotes', 'siteNotes', 'SiteNotes'],
  OfficeNotes: ['officeNotes', 'OfficeNotes'],
  SoilNotes: ['soilNotes', 'SoilNotes'],
  VegPlotNumber: ['vegPlotNumber', 'VegPlotNumber'],
  VegSurveyor: ['vegSurveyor', 'VegSurveyor'],
  SpeciesListComplete: ['speciesListComplete', 'SpeciesListComplete'],
  SV_FullCruiseCard: ['svFullCruiseCard', 'SV_FullCruiseCard'],
  StrataCoverTree: ['strataCoverTree', 'StrataCoverTree'],
  StrataCoverShrub: ['strataCoverShrub', 'StrataCoverShrub'],
  StrataCoverHerb: ['strataCoverHerb', 'StrataCoverHerb'],
  StrataCoverMoss: ['strataCoverMoss', 'StrataCoverMoss'],
  StrataCoverTotal: ['strataCoverTotal', 'StrataCoverTotal'],
  VegNotes: ['vegNotes', 'VegNotes'],
};

function typedCellToUnknown(cell: TypedMetadataCellLike | undefined): unknown {
  if (!cell || cell.storage === 'null') return null;
  if (cell.storage === 'real') return cell.real ?? null;
  if (cell.storage === 'integer') return cell.integer ?? null;
  if (cell.storage === 'text') return cell.text ?? '';
  if (cell.storage === 'blob') return cell.blobHex ? `[BLOB ${cell.blobHex}]` : '[BLOB]';
  return null;
}

function extractParentOriginalMap(original: SIVIParentOriginalLike | null | undefined): Map<string, unknown> {
  const result = new Map<string, unknown>();
  if (!original) return result;
  if (original.Plot !== undefined) result.set('plotnumber', original.Plot);
  const row = original.Rows?.[0];
  if (!row) return result;
  if (original.Bindings?.length) {
    for (const binding of original.Bindings) {
      const side = binding.Table === original.EnvTable ? row.Env : row.Admin;
      const cell = side?.cells?.[binding.Column];
      if (cell !== undefined) {
        result.set(binding.Binding.toLowerCase(), typedCellToUnknown(cell));
      }
    }
  }
  if (original.EnvColumns && row.Env?.cells) {
    original.EnvColumns.forEach((col, idx) => {
      const key = col.name.toLowerCase();
      if (!result.has(key)) result.set(key, typedCellToUnknown(row.Env.cells[idx]));
    });
  }
  if (original.AdminColumns && row.Admin?.cells) {
    original.AdminColumns.forEach((col, idx) => {
      const key = col.name.toLowerCase();
      if (!result.has(key)) result.set(key, typedCellToUnknown(row.Admin.cells[idx]));
    });
  }
  return result;
}

function resolveStagedParentDraft(draft: StagedParentCellDraftLike | undefined): { hasOverride: boolean; value: unknown } {
  if (!draft) return { hasOverride: false, value: undefined };
  if (draft.nullValue === true) return { hasOverride: true, value: null };
  if (draft.input) {
    if (draft.input.kind === 'clear') return { hasOverride: true, value: null };
    if (draft.input.kind === 'original') return { hasOverride: false, value: undefined };
    if (draft.input.kind === 'boolean') return { hasOverride: true, value: draft.input.value ?? null };
    if (draft.input.kind === 'option') {
      return { hasOverride: true, value: draft.input.option == null ? null : String(draft.input.option) };
    }
    if (draft.input.kind === 'text') return { hasOverride: true, value: draft.input.raw ?? '' };
  }
  if (typeof draft.raw === 'string') return { hasOverride: true, value: draft.raw };
  if (draft.value !== undefined) return { hasOverride: true, value: typedCellToUnknown(draft.value) };
  return { hasOverride: false, value: undefined };
}

function formatScalar(val: unknown): string {
  if (val === null || val === undefined || val === '') return '—';
  if (typeof val === 'boolean') return val ? 'Yes' : 'No';
  if (typeof val === 'number') {
    if (!Number.isFinite(val)) return String(val);
    return Number.isInteger(val) ? String(val) : String(Math.round(val * 1e6) / 1e6);
  }
  const str = String(val);
  return str.trim() === '' ? (str.length > 0 ? '(blank)' : '—') : str;
}

function parseOptionalNumber(val: unknown): number | null {
  if (val === null || val === undefined || val === '') return null;
  if (typeof val === 'number') return Number.isFinite(val) ? val : null;
  const trimmed = String(val).trim();
  if (!trimmed) return null;
  const parsed = Number(trimmed);
  return Number.isFinite(parsed) ? parsed : null;
}

function parseOptionalBoolean(val: unknown): boolean | null {
  if (val === true || val === -1 || val === '-1') return true;
  if (val === false || val === 0 || val === '0') return false;
  if (typeof val === 'string') {
    const lower = val.trim().toLowerCase();
    if (lower === 'true' || lower === 'yes') return true;
    if (lower === 'false' || lower === 'no') return false;
  }
  return null;
}

function lookupRecordField(row: Record<string, unknown>, candidates: readonly string[]): unknown {
  for (const key of candidates) {
    if (key in row && row[key] !== undefined) return row[key];
  }
  const lowerMap = new Map(Object.entries(row).map(([k, v]) => [k.toLowerCase(), v]));
  for (const key of candidates) {
    const found = lowerMap.get(key.toLowerCase());
    if (found !== undefined) return found;
  }
  return undefined;
}

function formatDepthRange(upper: number | null, lower: number | null, upperRaw: string, lowerRaw: string): string {
  const up = upper !== null ? formatScalar(upper) : upperRaw !== '—' ? upperRaw : '';
  const low = lower !== null ? formatScalar(lower) : lowerRaw !== '—' ? lowerRaw : '';
  if (!up && !low) return '—';
  return `${up || '?'}–${low || '?'} cm`;
}

export function buildFieldCardViewModel(input: BuildFieldCardInput): FieldCardViewModel {
  const formKind: FieldCardFormKind = input.formKind ?? 'fs882';
  const committedMap = new Map<string, unknown>();
  const mergedMap = new Map<string, unknown>();
  const fieldDraftFlags = new Set<string>();

  for (const [k, v] of extractParentOriginalMap(input.siviParentOriginal)) {
    committedMap.set(k, v);
    mergedMap.set(k, v);
  }
  for (const [k, v] of extractParentOriginalMap(input.twoPageOriginal)) {
    committedMap.set(k, v);
    mergedMap.set(k, v);
  }
  if (input.committedHeader) {
    for (const [k, v] of Object.entries(input.committedHeader)) {
      committedMap.set(k.toLowerCase(), v);
      mergedMap.set(k.toLowerCase(), v);
    }
  }
  if (input.draftHeader) {
    for (const [k, v] of Object.entries(input.draftHeader)) {
      const lower = k.toLowerCase();
      const prev = committedMap.get(lower);
      mergedMap.set(lower, v);
      if (input.committedHeader && v !== prev && !(v == null && prev == null)) {
        fieldDraftFlags.add(lower);
      }
    }
  }

  for (const draftBag of [input.siviDirectDrafts, input.siviActionDrafts, input.siviSharedDrafts, input.twoPageDrafts]) {
    if (!draftBag) continue;
    for (const [col, cellDraft] of Object.entries(draftBag)) {
      const resolved = resolveStagedParentDraft(cellDraft);
      if (resolved.hasOverride) {
        const lower = col.toLowerCase();
        mergedMap.set(lower, resolved.value);
        fieldDraftFlags.add(lower);
      }
    }
  }

  if (input.siviProjectText) {
    mergedMap.set('projectid', input.siviProjectText);
    fieldDraftFlags.add('projectid');
  }
  if (input.twoPageProjectText) {
    mergedMap.set('projectid', input.twoPageProjectText);
    fieldDraftFlags.add('projectid');
  }
  if (input.snowCoverRegimeRaw !== undefined && input.snowCoverRegimeRaw !== null) {
    const val = input.snowCoverRegimeRaw === '' ? null : input.snowCoverRegimeRaw;
    const prev = committedMap.get('snowcoverregime') ?? null;
    mergedMap.set('snowcoverregime', val);
    if (val !== prev) fieldDraftFlags.add('snowcoverregime');
  }
  if (input.activeLayerDepthRaw !== undefined && input.activeLayerDepthRaw !== null) {
    const val = input.activeLayerDepthRaw === '' ? null : input.activeLayerDepthRaw;
    const prev = committedMap.get('activelayerdepth');
    mergedMap.set('activelayerdepth', val);
    if (String(val ?? '') !== String(prev ?? '')) fieldDraftFlags.add('activelayerdepth');
  }

  function rawCol(column: string): unknown {
    const aliases = COLUMN_ALIASES[column] ?? [column];
    for (const alias of aliases) {
      const lower = alias.toLowerCase();
      if (mergedMap.has(lower)) return mergedMap.get(lower);
    }
    return undefined;
  }

  function isColDraft(column: string): boolean {
    const aliases = COLUMN_ALIASES[column] ?? [column];
    return aliases.some((alias) => fieldDraftFlags.has(alias.toLowerCase()));
  }

  function cell(
    column: string,
    label: string,
    opts: { span?: number; mono?: boolean; checkbox?: boolean } = {},
  ): FieldCardCell {
    const raw = rawCol(column);
    const cb = opts.checkbox ? parseOptionalBoolean(raw) : undefined;
    let display = formatScalar(raw);
    if (column === 'SV_StandAgeEstMeas' || column === 'SV_StandHeightEstMeas') {
      if (raw === '1' || raw === 1) display = 'Est.';
      else if (raw === '2' || raw === 2) display = 'Meas.';
    }
    return {
      key: column,
      label,
      value: opts.checkbox ? (cb === true ? '\u2611 Yes' : cb === false ? '☐ No' : '☐ —') : display,
      span: opts.span,
      mono: opts.mono,
      checkbox: opts.checkbox ? cb : undefined,
      isDraft: isColDraft(column),
    };
  }

  // Substrate 6-cell strip & sum
  const substrateSpecs: readonly [string, string][] = [
    ['SubstrateOrganicMatter', 'Organic Matter'],
    ['SubstrateDecWood', 'Decaying Wood'],
    ['SubstrateBedRock', 'Bedrock'],
    ['SubstrateRocks', 'Rocks'],
    ['SubstrateMineralSoil', 'Mineral Soil'],
    ['SubstrateWater', 'Water'],
  ];
  let subSum = 0;
  let subCount = 0;
  const substrateCells: FieldCardCell[] = substrateSpecs.map(([col, label]) => {
    const raw = rawCol(col);
    const num = parseOptionalNumber(raw);
    if (num !== null) {
      subSum += num;
      subCount++;
    }
    return {
      key: col,
      label,
      value: num !== null ? `${formatScalar(num)}%` : formatScalar(raw),
      span: 2,
      mono: true,
      isDraft: isColDraft(col),
    };
  });
  const substrateTotal = subCount > 0 ? Math.round(subSum * 100) / 100 : null;
  const substrateTotalDisplay = substrateTotal !== null ? `${substrateTotal}% / 100%` : '— / 100%';

  // Coordinates string
  const lat = parseOptionalNumber(rawCol('Latitude'));
  const lon = parseOptionalNumber(rawCol('Longitude'));
  const utmZ = formatScalar(rawCol('UTMZone'));
  const utmE = formatScalar(rawCol('UTMEasting'));
  const utmN = formatScalar(rawCol('UTMNorthing'));
  const coordParts: string[] = [];
  if (lat !== null || lon !== null) {
    coordParts.push(`${lat !== null ? lat.toFixed(6) + '°' : '?'}, ${lon !== null ? lon.toFixed(6) + '°' : '?'}`);
  }
  if (utmZ !== '—' || utmE !== '—' || utmN !== '—') {
    coordParts.push(`NAD83 UTM ${utmZ !== '—' ? utmZ : '?'} ${utmE !== '—' ? utmE + 'E' : '?'} ${utmN !== '—' ? utmN + 'N' : '?'}`);
  }
  const formattedCoordinates = coordParts.length > 0 ? coordParts.join(' · ') : '—';

  // BEC Unit mask
  const zone = formatScalar(rawCol('Zone'));
  const subZone = formatScalar(rawCol('SubZone'));
  const siteSeries = formatScalar(rawCol('SiteSeries'));
  const becMaster = formatScalar(rawCol('BECSiteUnit'));
  const workingUnit = formatScalar(rawCol('UserSiteUnit'));
  const bgcPrefix = [zone !== '—' ? zone : '', subZone !== '—' ? subZone : ''].filter(Boolean).join(' ');
  const becUnitMask =
    bgcPrefix && siteSeries !== '—'
      ? `${bgcPrefix} / ${siteSeries}`
      : bgcPrefix || (becMaster !== '—' ? becMaster : workingUnit !== '—' ? workingUnit : 'Unclassified');

  const plotNumberRaw = formatScalar(rawCol('PlotNumber'));
  const plotNumber = plotNumberRaw === '—' ? '(New Plot)' : plotNumberRaw;

  const snowVal = rawCol('SnowCoverregime');
  const activeDepthVal = rawCol('ActiveLayerDepth');
  const extendedShrubs = Boolean(
    input.extendedShrubs ||
      (snowVal !== null && snowVal !== undefined && snowVal !== '') ||
      (activeDepthVal !== null && activeDepthVal !== undefined && activeDepthVal !== ''),
  );

  // Organic Horizons (LMH25: upland L/F/H UpperDepth >= LowerDepth sorted UpperDepth DESC; wetland Of/Om/Oh UpperDepth < LowerDepth sorted UpperDepth ASC; NULL last)
  const organicUnsorted: FieldCardOrganicHorizonRow[] = (input.humusRows ?? []).map((row, idx) => {
    const idNum = lookupRecordField(row, ['id', 'ID']);
    const idKey = idNum !== undefined && idNum !== null ? String(idNum) : `h-${idx}`;
    const staged = idNum !== undefined ? input.soilDrafts?.[`Humus/${idNum}`]?.cells : undefined;
    const isDraft = Boolean(staged && Object.values(staged).some((c) => c.error !== null || c.value !== c.expected));

    const getH = (key: string, cols: readonly string[]) => {
      if (staged && key in staged) return staged[key].raw === '' ? null : staged[key].value ?? staged[key].raw;
      return lookupRecordField(row, cols);
    };
    const upRawVal = getH('upperDepth', ['upperDepth', 'UpperDepth']);
    const lowRawVal = getH('lowerDepth', ['lowerDepth', 'LowerDepth']);
    const upNum = parseOptionalNumber(upRawVal);
    const lowNum = parseOptionalNumber(lowRawVal);
    const deg = formatScalar(getH('humusStructureDegree', ['humusStructureDegree', 'HumusStructureDegree']));
    const kind = formatScalar(getH('humusStructureKind', ['humusStructureKind', 'HumusStructureKind']));
    const mycel = formatScalar(getH('mycelAbundance', ['mycelAbundance', 'MycelAbundance']));
    const fecal = formatScalar(getH('fecalAbundance', ['fecalAbundance', 'FecalAbundance']));
    const rAb = formatScalar(getH('rootsAbundance', ['rootsAbundance', 'RootsAbundance']));
    const rSz = formatScalar(getH('rootsSize', ['rootsSize', 'RootsSize']));

    return {
      id: idKey,
      horizon: formatScalar(getH('horizon', ['horizon', 'Horizon'])),
      upperDepth: upNum,
      lowerDepth: lowNum,
      depthRange: formatDepthRange(upNum, lowNum, formatScalar(upRawVal), formatScalar(lowRawVal)),
      fabricStructure: [deg !== '—' ? deg : '', kind !== '—' ? kind : ''].filter(Boolean).join(' ') || '—',
      mycelFecal: [mycel !== '—' ? `M:${mycel}` : '', fecal !== '—' ? `F:${fecal}` : ''].filter(Boolean).join(' ') || '—',
      roots: [rAb !== '—' ? rAb : '', rSz !== '—' ? rSz : ''].filter(Boolean).join('/') || '—',
      vonPost: formatScalar(getH('vonPost', ['vonPost', 'VonPost'])),
      ph: formatScalar(getH('ph', ['ph', 'HumusFormpH', 'humusformph'])),
      comment: formatScalar(getH('comment', ['comment', 'Comment'])),
      isDraft,
    };
  });

  const organicHorizons = organicUnsorted.slice().sort((a, b) => {
    if (a.upperDepth === null && b.upperDepth === null) return 0;
    if (a.upperDepth === null) return 1;
    if (b.upperDepth === null) return -1;
    const aWetland = a.lowerDepth !== null && a.upperDepth < a.lowerDepth;
    const bWetland = b.lowerDepth !== null && b.upperDepth < b.lowerDepth;
    if (aWetland !== bWetland) return aWetland ? 1 : -1;
    if (aWetland && bWetland) return a.upperDepth - b.upperDepth;
    return b.upperDepth - a.upperDepth;
  });

  // Mineral Horizons (LMH25: downward from 0 cm, UpperDepth ASC, NULL last)
  const mineralUnsorted: FieldCardMineralHorizonRow[] = (input.mineralRows ?? []).map((row, idx) => {
    const idNum = lookupRecordField(row, ['id', 'ID']);
    const idKey = idNum !== undefined && idNum !== null ? String(idNum) : `m-${idx}`;
    const staged = idNum !== undefined ? input.soilDrafts?.[`Mineral/${idNum}`]?.cells : undefined;
    const isDraft = Boolean(staged && Object.values(staged).some((c) => c.error !== null || c.value !== c.expected));

    const getM = (key: string, cols: readonly string[]) => {
      if (staged && key in staged) return staged[key].raw === '' ? null : staged[key].value ?? staged[key].raw;
      return lookupRecordField(row, cols);
    };
    const upRawVal = getM('upperDepth', ['upperDepth', 'UpperDepth']);
    const lowRawVal = getM('lowerDepth', ['lowerDepth', 'LowerDepth']);
    const upNum = parseOptionalNumber(upRawVal);
    const lowNum = parseOptionalNumber(lowRawVal);
    const limit = formatScalar(getM('pitDepthLimit', ['pitDepthLimit', 'PitDepthLimit']));
    const baseRange = formatDepthRange(upNum, lowNum, formatScalar(upRawVal), formatScalar(lowRawVal));
    const g = formatScalar(getM('percentCoarseFragsGravel', ['percentCoarseFragsGravel', 'PercentCoarseFragsGravel']));
    const c = formatScalar(getM('percentCoarseFragsCobbles', ['percentCoarseFragsCobbles', 'PercentCoarseFragsCobbles']));
    const s = formatScalar(getM('percentCoarseFragsStones', ['percentCoarseFragsStones', 'PercentCoarseFragsStones']));
    const tot = formatScalar(getM('percentCoarseFragsTotal', ['percentCoarseFragsTotal', 'PercentCoarseFragsTotal']));
    const shp = formatScalar(getM('percentCoarseFragsShape', ['percentCoarseFragsShape', 'PercentCoarseFragsShape']));
    const rAb = formatScalar(getM('rootsAbundance', ['rootsAbundance', 'RootsAbundance']));
    const rSz = formatScalar(getM('rootsSize', ['rootsSize', 'RootsSize']));
    const sCls = formatScalar(getM('mineralStructureClass', ['mineralStructureClass', 'MineralStructureClass']));
    const sKnd = formatScalar(getM('mineralStructureKind', ['mineralStructureKind', 'MineralStructureKind']));

    const cfParts = [
      g !== '—' ? `G:${g}` : '',
      c !== '—' ? `C:${c}` : '',
      s !== '—' ? `S:${s}` : '',
      tot !== '—' ? `T:${tot}%` : '',
      shp !== '—' ? shp : '',
    ].filter(Boolean);

    return {
      id: idKey,
      horizon: formatScalar(getM('horizon', ['horizon', 'Horizon'])),
      upperDepth: upNum,
      lowerDepth: lowNum,
      depthRange: limit !== '—' ? `${baseRange} (${limit})` : baseRange,
      texture: formatScalar(getM('texture', ['texture', 'Texture'])),
      colour: formatScalar(getM('colour', ['colour', 'Colour'])),
      coarseFrags: cfParts.join(' ') || '—',
      roots: [rAb !== '—' ? rAb : '', rSz !== '—' ? rSz : ''].filter(Boolean).join('/') || '—',
      structure: [sCls !== '—' ? sCls : '', sKnd !== '—' ? sKnd : ''].filter(Boolean).join(' ') || '—',
      ph: formatScalar(getM('mineralFormpH', ['mineralFormpH', 'MineralFormpH'])),
      comments: formatScalar(getM('comments', ['comments', 'Comments'])),
      isDraft,
    };
  });

  const mineralHorizons = mineralUnsorted.slice().sort((a, b) => {
    if (a.upperDepth === null && b.upperDepth === null) return 0;
    if (a.upperDepth === null) return 1;
    if (b.upperDepth === null) return -1;
    return a.upperDepth - b.upperDepth;
  });

  // Vegetation rows (A/B, C, D) merging heightDrafts, speciesDrafts, collectedDrafts, creationDraft
  const treeShrubRows: FieldCardTreeShrubRow[] = [];
  const herbRows: FieldCardHerbRow[] = [];
  const mossRows: FieldCardMossRow[] = [];
  let anyExtendedShrubData = extendedShrubs;

  for (const [idx, row] of (input.vegRows ?? []).entries()) {
    const idVal = lookupRecordField(row, ['id', 'ID', 'rowId']);
    const rowKey = idVal !== undefined && idVal !== null ? String(idVal) : `v-${idx}`;
    const htRow = input.heightDrafts?.[rowKey];
    const spDraft = input.speciesDrafts?.[rowKey];
    const colDraft = input.collectedDrafts?.[rowKey];

    const hasHtDraft = Boolean(htRow && Object.values(htRow).some((c) => c && (c.error !== null || c.value !== c.expected)));
    const hasSpDraft = Boolean(spDraft && (spDraft.error != null || spDraft.raw !== spDraft.expected));
    const hasColDraft = Boolean(colDraft && colDraft.value !== colDraft.expected);
    const rowIsDraft = hasHtDraft || hasSpDraft || hasColDraft;

    const species = spDraft ? formatScalar(spDraft.raw) : formatScalar(lookupRecordField(row, ['species', 'Species']));
    const collected = colDraft !== undefined ? formatScalar(colDraft.value) : formatScalar(lookupRecordField(row, ['collected', 'Collected']));

    const getVNum = (field: string, cols: readonly string[]): unknown => {
      const staged = htRow?.[field];
      if (staged !== undefined) return staged.raw === '' ? null : staged.value ?? staged.raw;
      return lookupRecordField(row, cols);
    };

    const c1 = getVNum('cover1', ['cover1', 'Cover1']);
    const h1 = getVNum('height1', ['height1', 'Height1']);
    const c2 = getVNum('cover2', ['cover2', 'Cover2']);
    const h2 = getVNum('height2', ['height2', 'Height2']);
    const c3 = getVNum('cover3', ['cover3', 'Cover3']);
    const h3 = getVNum('height3', ['height3', 'Height3']);
    const totA = getVNum('totalA', ['totalA', 'TotalA']);
    const c4 = getVNum('cover4', ['cover4', 'Cover4']);
    const h4 = getVNum('height4', ['height4', 'Height4']);
    const c5 = getVNum('cover5', ['cover5', 'Cover5']);
    const h5 = getVNum('height5', ['height5', 'Height5']);
    const c5a = getVNum('cover5a', ['cover5a', 'Cover5a']);
    const c5b = getVNum('cover5b', ['cover5b', 'Cover5b']);
    const c5c = getVNum('cover5c', ['cover5c', 'Cover5c']);
    const totB = getVNum('totalB', ['totalB', 'TotalB']);
    const c6 = getVNum('cover6', ['cover6', 'Cover6']);
    const h6 = getVNum('height6', ['height6', 'Height6']);
    const c7 = getVNum('cover7', ['cover7', 'Cover7']);
    const c8 = getVNum('cover8', ['cover8', 'Cover8']);
    const c9 = getVNum('cover9', ['cover9', 'Cover9']);

    if (c5a != null || c5b != null || c5c != null) anyExtendedShrubData = true;

    const inAB = [c1, h1, c2, h2, c3, h3, totA, c4, h4, c5, h5, c5a, c5b, c5c, totB].some((v) => v != null && v !== '');
    const inC = c6 != null && c6 !== '' || h6 != null && h6 !== '';
    const inD = [c7, c8, c9].some((v) => v != null && v !== '');

    if (inAB) {
      treeShrubRows.push({
        id: rowKey,
        species,
        collected,
        cover1: formatScalar(c1),
        height1: formatScalar(h1),
        cover2: formatScalar(c2),
        height2: formatScalar(h2),
        cover3: formatScalar(c3),
        height3: formatScalar(h3),
        totalA: formatScalar(totA),
        cover4: formatScalar(c4),
        height4: formatScalar(h4),
        cover5: formatScalar(c5),
        height5: formatScalar(h5),
        cover5a: formatScalar(c5a),
        cover5b: formatScalar(c5b),
        cover5c: formatScalar(c5c),
        totalB: formatScalar(totB),
        isDraft: rowIsDraft,
      });
    }
    if (inC) {
      herbRows.push({
        id: rowKey,
        species,
        collected,
        cover6: formatScalar(c6),
        height6: formatScalar(h6),
        isDraft: rowIsDraft,
      });
    }
    if (inD) {
      mossRows.push({
        id: rowKey,
        species,
        collected,
        cover7: formatScalar(c7),
        cover8: formatScalar(c8),
        cover9: formatScalar(c9),
        isDraft: rowIsDraft,
      });
    }
  }

  if (input.creationDraft) {
    const cd = input.creationDraft;
    const getCD = (col: string) => {
      const entry = Object.entries(cd.cells).find(([k]) => k.toLowerCase() === col.toLowerCase())?.[1];
      return formatScalar(entry?.raw || entry?.value);
    };
    const sp = formatScalar(cd.species);
    if (cd.form.includes('SubVegA')) {
      if (getCD('Cover5a') !== '—' || getCD('Cover5b') !== '—' || getCD('Cover5c') !== '—') anyExtendedShrubData = true;
      treeShrubRows.push({
        id: 'new',
        species: sp,
        collected: getCD('Collected'),
        cover1: getCD('Cover1'),
        height1: getCD('Height1'),
        cover2: getCD('Cover2'),
        height2: getCD('Height2'),
        cover3: getCD('Cover3'),
        height3: getCD('Height3'),
        totalA: getCD('TotalA'),
        cover4: getCD('Cover4'),
        height4: getCD('Height4'),
        cover5: getCD('Cover5'),
        height5: getCD('Height5'),
        cover5a: getCD('Cover5a'),
        cover5b: getCD('Cover5b'),
        cover5c: getCD('Cover5c'),
        totalB: getCD('TotalB'),
        isDraft: true,
      });
    } else if (cd.form.includes('SubVegC')) {
      herbRows.push({
        id: 'new',
        species: sp,
        collected: getCD('Collected'),
        cover6: getCD('Cover6'),
        height6: getCD('Height6'),
        isDraft: true,
      });
    } else if (cd.form.includes('SubVegD')) {
      mossRows.push({
        id: 'new',
        species: sp,
        collected: getCD('Collected'),
        cover7: getCD('Cover7'),
        cover8: getCD('Cover8'),
        cover9: getCD('Cover9'),
        isDraft: true,
      });
    }
  }

  const anyChildDraft =
    organicHorizons.some((r) => r.isDraft) ||
    mineralHorizons.some((r) => r.isDraft) ||
    treeShrubRows.some((r) => r.isDraft) ||
    herbRows.some((r) => r.isDraft) ||
    mossRows.some((r) => r.isDraft) ||
    Boolean(input.creationDraft);

  const isDirty = input.isDirty !== undefined ? input.isDirty : fieldDraftFlags.size > 0 || anyChildDraft;

  const isTwoPageOrSivi = formKind === 'two-page' || formKind === 'sivi';

  const identityCells: FieldCardCell[] = [
    cell('PlotNumber', 'Plot No.', { span: 3, mono: true }),
    cell('FieldNumber', 'Field No.', { span: 3, mono: true }),
    cell('Date', 'Date', { span: 3, mono: true }),
    cell('ProjectID', 'Project ID', { span: 3, mono: true }),
    cell('SiteSurveyor', 'Site Surveyor', { span: 4 }),
    cell('StartDate', 'Start Year', { span: 2, mono: true }),
    ...(isTwoPageOrSivi
      ? [
          cell('PlotType', 'Plot Type', { span: 2, mono: true }),
          cell('PlotSize', 'Plot Size', { span: 2, mono: true }),
          cell('SV_PolygonNumber', 'Polygon No.', { span: 2, mono: true }),
        ]
      : []),
  ];

  const locationCells: FieldCardCell[] = [
    cell('Location', 'General Location', { span: 12 }),
    cell('FSRegionDistrict', 'FS Region / District', { span: 4, mono: true }),
    cell('Ecosection', 'Ecosection', { span: 4, mono: true }),
    cell('NtsMapSheet', 'NTS Map Sheet', { span: 4, mono: true }),
    cell('Latitude', 'Latitude (DD)', { span: 3, mono: true }),
    cell('Longitude', 'Longitude (DD)', { span: 3, mono: true }),
    cell('UTMZone', 'UTM Zone', { span: 2, mono: true }),
    cell('UTMEasting', 'UTM Easting', { span: 2, mono: true }),
    cell('UTMNorthing', 'UTM Northing', { span: 2, mono: true }),
    cell('LocationAccuracy', 'Accuracy (m)', { span: 3, mono: true }),
    cell('AirPhotoNum', 'Air Photo', { span: 3, mono: true }),
    ...(isTwoPageOrSivi ? [cell('ProvinceStateTerritory', 'Prov / Terr', { span: 3, mono: true })] : []),
  ];

  const becEdatopicCells: FieldCardCell[] = [
    cell('Zone', 'BGC Zone', { span: 3, mono: true }),
    cell('SubZone', 'Subzone / Var', { span: 3, mono: true }),
    cell('SiteSeries', 'Site Series', { span: 3, mono: true }),
    cell('RealmClass', 'Realm / Class', { span: 3, mono: true }),
    cell('BECSiteUnit', 'BEC Master Unit', { span: 6, mono: true }),
    cell('UserSiteUnit', 'Working Unit', { span: 6, mono: true }),
    cell('MoistureRegime', 'Moisture Regime (rSMR)', { span: 4, mono: true }),
    cell('NutrientRegime', 'Nutrient Regime (SNR)', { span: 4, mono: true }),
    cell('TransDistrib', 'Trans. / Distrib.', { span: 4, mono: true }),
    cell('SuccessionalStatus', 'Successional Status', { span: 3, mono: true }),
    cell('StructuralStage', 'Structural Stage', { span: 3, mono: true }),
    cell('StandAge', 'Stand Age (yr)', { span: 3, mono: true }),
    cell('MapUnit', 'Map Unit', { span: 3, mono: true }),
    cell('PlotRepresenting', 'Plot Representing', { span: 12 }),
    ...(isTwoPageOrSivi
      ? [
          cell('SV_StandAgeEstMeas', 'Age Est/Meas', { span: 3 }),
          cell('SV_StandHeight', 'Stand Ht (m)', { span: 3, mono: true }),
          cell('GIS_BGC', 'GIS BGC', { span: 3, mono: true }),
          cell('BEC_Use', 'BEC Use', { span: 3, mono: true }),
          cell('SiteUnitLongName', 'Site Unit Name', { span: 6 }),
          cell('SV_CanopyComposition', 'Canopy Composition', { span: 6 }),
        ]
      : []),
  ];

  const topographyQualityCells: FieldCardCell[] = [
    cell('Elevation', 'Elevation (m)', { span: 2, mono: true }),
    cell('SlopeGradient', 'Slope (%)', { span: 2, mono: true }),
    cell('Aspect', 'Aspect (°)', { span: 2, mono: true }),
    cell('MesoSlopePosition', 'Meso Slope', { span: 2, mono: true }),
    cell('SurfaceShape', 'Surface Shape', { span: 2, mono: true }),
    cell('SurfaceTopographyType', 'Microtop. Type', { span: 1, mono: true }),
    cell('SurfaceTopographySize', 'Microtop. Size', { span: 1, mono: true }),
    cell('SiteDisturbance1', 'Disturb. 1', { span: 2, mono: true }),
    cell('SiteDisturbance2', 'Disturb. 2', { span: 2, mono: true }),
    cell('SiteDisturbance3', 'Disturb. 3', { span: 2, mono: true }),
    cell('Exposure1', 'Exposure 1', { span: 3, mono: true }),
    cell('Exposure2', 'Exposure 2', { span: 3, mono: true }),
    cell('SitePlotQuality', 'Site Quality', { span: 4, mono: true }),
    cell('VegPlotQuality', 'Veg Quality', { span: 4, mono: true }),
    cell('SoilPlotQuality', 'Soil Quality', { span: 4, mono: true }),
    ...(extendedShrubs
      ? [
          cell('SnowCoverregime', 'Snow Cover Regime', { span: 6, mono: true }),
          cell('ActiveLayerDepth', 'Active Layer Depth (cm)', { span: 6, mono: true }),
        ]
      : []),
  ];

  const surfaceTerrainCells: FieldCardCell[] = [
    cell('TerrainTextureSurf', 'Surface Texture', { span: 3, mono: true }),
    cell('SurficialMaterialSurf', 'Surficial Material', { span: 3, mono: true }),
    cell('SurfaceExpSurf', 'Surface Expression', { span: 3, mono: true }),
    cell('GeoMorProSurf', 'Geomorphic Process', { span: 3, mono: true }),
  ];

  const subsurfaceTerrainCells: FieldCardCell[] = [
    cell('TerrainTextureSubSurf', 'Subsurface Texture', { span: 3, mono: true }),
    cell('SurficialMaterialSubSurf', 'Subsurface Material', { span: 3, mono: true }),
    cell('SurfaceExpSubSurf', 'Subsurface Expression', { span: 3, mono: true }),
    cell('GeoMorProSubSurf', 'Subsurface Process', { span: 3, mono: true }),
  ];

  const geologyCells: FieldCardCell[] = [
    cell('BedrockGeology1', 'Bedrock 1', { span: 4, mono: true }),
    cell('BedrockGeology2', 'Bedrock 2', { span: 4, mono: true }),
    cell('BedrockGeology3', 'Bedrock 3', { span: 4, mono: true }),
    cell('CoarseFragLith1', 'Coarse Frag Lith 1', { span: 4, mono: true }),
    cell('CoarseFragLith2', 'Coarse Frag Lith 2', { span: 4, mono: true }),
    cell('CoarseFragLith3', 'Coarse Frag Lith 3', { span: 4, mono: true }),
  ];

  const soilSummaryCells: FieldCardCell[] = [
    cell('SoilSurveyor', 'Soil Surveyor', { span: 3 }),
    cell('MensPlotNumber', 'Mens Plot No.', { span: 3, mono: true }),
    cell('SoilClassSubGroup', 'Soil Subgroup', { span: 3, mono: true }),
    cell('SoilClassGroup', 'Soil Great Group', { span: 3, mono: true }),
    cell('HumusForm', 'Humus Form', { span: 4, mono: true }),
    cell('HumusFormPhase', 'Humus Phase', { span: 4, mono: true }),
    cell('HumusThickness', 'Humus Thick. (cm)', { span: 4, mono: true }),
    cell('HydroGeoSystem', 'Hydrogeo. System', { span: 3, mono: true }),
    cell('HydroGeoSubSystem', 'Hydrogeo. Subsys.', { span: 3, mono: true }),
    cell('WaterSource', 'Water Source', { span: 3, mono: true }),
    cell('SoilDrainage', 'Soil Drainage', { span: 3, mono: true }),
    cell('RootingDepth', 'Rooting Depth (cm)', { span: 3, mono: true }),
    cell('RootZoneParticleSize', 'Root Zone Particle', { span: 3, mono: true }),
    cell('RootRestrictingType', 'Restricting Type', { span: 3, mono: true }),
    cell('RootRestrictingDepth', 'Restricting Depth (cm)', { span: 3, mono: true }),
    cell('SeepageDepth', 'Seepage Depth (cm)', { span: 4, mono: true }),
    cell('FloodingRegimeFreq', 'Flooding Freq.', { span: 4, mono: true }),
    cell('FloodingRegimeDur', 'Flooding Dur.', { span: 4, mono: true }),
    ...(isTwoPageOrSivi
      ? [
          cell('SV_AhorizonType', 'A Horizon Type', { span: 3, mono: true }),
          cell('SV_AhorizonDepth', 'A Horizon Depth (cm)', { span: 3, mono: true }),
          cell('SV_SoilDepth', 'Soil Depth (cm)', { span: 3, mono: true }),
          cell('SV_PercentCoarseFrags', 'Coarse Frags (%)', { span: 3, mono: true }),
          cell('SV_GleyingMottlingCM', 'Gleying/Mottling (cm)', { span: 4, mono: true }),
          cell('SV_WaterTableCM', 'Water Table (cm)', { span: 4, mono: true }),
          cell('SV_FloodPlain', 'Flood Plain', { span: 4, checkbox: true }),
        ]
      : []),
  ];

  const vegSurveyCells: FieldCardCell[] = [
    cell('VegPlotNumber', 'Veg Plot No.', { span: 4, mono: true }),
    cell('VegSurveyor', 'Veg Surveyor', { span: 4 }),
    cell('SpeciesListComplete', 'Spp. List Complete', { span: 4, checkbox: true }),
    ...(formKind === 'two-page' ? [cell('SV_FullCruiseCard', 'Full Cruise Card', { span: 4, checkbox: true })] : []),
  ];

  const strataCoverCells: FieldCardCell[] = [
    cell('StrataCoverTree', 'Tree (A) %', { span: formKind === 'two-page' ? 2 : 3, mono: true }),
    cell('StrataCoverShrub', 'Shrub (B) %', { span: formKind === 'two-page' ? 2 : 3, mono: true }),
    cell('StrataCoverHerb', 'Herb (C) %', { span: formKind === 'two-page' ? 2 : 3, mono: true }),
    cell('StrataCoverMoss', 'Moss/Lichen (D) %', { span: formKind === 'two-page' ? 2 : 3, mono: true }),
    ...(formKind === 'two-page' ? [cell('StrataCoverTotal', 'Total %', { span: 4, mono: true })] : []),
  ];

  const formCode =
    formKind === 'sivi'
      ? 'FS 1333 / SIVI'
      : formKind === 'two-page'
      ? extendedShrubs
        ? 'FS 882 (2-Page · CHARS)'
        : 'FS 882 (2-Page)'
      : 'FS 882 (6×4)';

  const cardTitle =
    formKind === 'sivi'
      ? 'SITE VISIT FIELD CARD (SIVI / FS 1333)'
      : 'ECOSYSTEM FIELD FORM (LMH 25 / FS 882)';

  return {
    formKind,
    formCode,
    ministryHeader: 'B.C. Ministry of Forests — Research Branch · BEC Program',
    cardTitle,
    plotNumber,
    becUnitMask,
    formattedCoordinates,
    substrateTotal,
    substrateTotalDisplay,
    extendedShrubs,
    isDirty,
    front: {
      identityCells,
      locationCells,
      becEdatopicCells,
      topographyQualityCells,
      substrateCells,
      surfaceTerrainCells,
      subsurfaceTerrainCells,
      geologyCells,
      soilSummaryCells,
      organicHorizons,
      mineralHorizons,
      notes: {
        siteNotes: formatScalar(rawCol('SiteNotes')),
        officeNotes: formatScalar(rawCol('OfficeNotes')),
        soilNotes: formatScalar(rawCol('SoilNotes')),
      },
    },
    back: {
      vegSurveyCells,
      strataCoverCells,
      showExtendedShrubColumns: anyExtendedShrubData,
      treeShrubRows,
      herbRows,
      mossRows,
      vegNotes: formatScalar(rawCol('VegNotes')),
    },
  };
}
