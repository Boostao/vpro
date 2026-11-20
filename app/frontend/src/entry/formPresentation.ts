import { accessCaption, type PaperControl } from './paperLayout';

type Group = { title: string; fields: readonly string[] };
const groups: Record<string, readonly Group[]> = {
  Site: [
    { title: 'Identity and survey', fields: ['PlotNumber', 'Date', 'SiteSurveyor', 'FieldNumber'] },
    { title: 'Project', fields: ['ProjectID', 'StartDate', 'Option477', 'Option479', 'btnLoadMetadata'] },
    {
      title: 'BEC Master and Working Unit',
      fields: ['BECSiteUnit', 'UserSiteUnit', 'Option455', 'Option457', 'Option459', 'btnCoptToWorkingUnit'],
    },
    {
      title: 'Location',
      fields: [
        'Location',
        'FSRegionDistrict',
        'NtsMapSheet',
        'UTMZone',
        'UTMEasting',
        'UTMNorthing',
        'Combo467',
        'AirPhotoNum',
        'XCoord',
        'YCoord',
        'Ecosection',
      ],
    },
    {
      title: 'Coordinate display',
      fields: [
        'Check369',
        'Check371',
        'Check373',
        'Latitude',
        'Longitude',
        'LatD2',
        'LatMD',
        'LonD2',
        'LonMD',
        'LatD',
        'LatM',
        'LatS',
        'LonD',
        'LonM',
        'LonS',
      ],
    },
    {
      title: 'Site classification',
      fields: ['PlotRepresenting', 'Zone', 'SubZone', 'SiteSeries', 'RealmClass', 'TransDistrib', 'MapUnit'],
    },
    {
      title: 'Site conditions and stand',
      fields: ['MoistureRegime', 'NutrientRegime', 'SuccessionalStatus', 'StructuralStage', 'StandAge'],
    },
    {
      title: 'Topography',
      fields: [
        'Elevation',
        'SlopeGradient',
        'Aspect',
        'MesoSlopePosition',
        'SurfaceShape',
        'SurfaceTopographyType',
        'SurfaceTopographySize',
      ],
    },
    { title: 'Data quality', fields: ['SitePlotQuality', 'VegPlotQuality', 'SoilPlotQuality'] },
    {
      title: 'Substrate (%)',
      fields: [
        'SubstrateOrganicMatter',
        'SubstrateDecWood',
        'SubstrateBedRock',
        'SubstrateRocks',
        'SubstrateMineralSoil',
        'SubstrateWater',
      ],
    },
    {
      title: 'Disturbance and exposure',
      fields: ['SiteDisturbance1', 'SiteDisturbance2', 'SiteDisturbance3', 'Exposure1', 'Exposure2'],
    },
    { title: 'Site diagram and pictures', fields: ['frmVPics', 'btnManagePictures', 'Photo'] },
    { title: 'Entry and source actions', fields: ['EnteredBy', 'UpdatedFromCards', 'Toggle408', 'Toggle409'] },
    { title: 'Field and office notes', fields: ['SiteNotes', 'OfficeNotes'] },
  ],
  'Soil/Terrain': [
    { title: 'Survey', fields: ['MensPlotNumber', 'SoilSurveyor'] },
    {
      title: 'Geology',
      fields: [
        'BedrockGeology1',
        'BedrockGeology2',
        'BedrockGeology3',
        'CoarseFragLith1',
        'CoarseFragLith2',
        'CoarseFragLith3',
      ],
    },
    {
      title: 'Surface terrain',
      fields: ['TerrainTextureSurf', 'SurficialMaterialSurf', 'SurfaceExpSurf', 'GeoMorProSurf'],
    },
    {
      title: 'Subsurface terrain',
      fields: ['TerrainTextureSubSurf', 'SurficialMaterialSubSurf', 'SurfaceExpSubSurf', 'GeoMorProSubSurf'],
    },
    { title: 'Soil classification', fields: ['SoilClassSubGroup', 'SoilClassGroup'] },
    { title: 'Humus form', fields: ['HumusForm', 'HumusFormPhase', 'HumusThickness'] },
    { title: 'Hydrogeology', fields: ['HydroGeoSystem', 'HydroGeoSubSystem'] },
    {
      title: 'Rooting and restricting layer',
      fields: ['RootingDepth', 'RootZoneParticleSize', 'RootRestrictingType', 'RootRestrictingDepth'],
    },
    {
      title: 'Water and drainage',
      fields: ['WaterSource', 'SoilDrainage', 'SeepageDepth', 'FloodingRegimeFreq', 'FloodingRegimeDur'],
    },
    { title: 'Organic horizons / layers', fields: ['SoilHumus'] },
    { title: 'Mineral horizons / layers', fields: ['SoilMineral'] },
    { title: 'Soil notes', fields: ['SoilNotes'] },
  ],
  Vegetation: [
    { title: 'Vegetation survey', fields: ['VegPlotNumber', 'VegSurveyor', 'SpeciesListComplete'] },
    {
      title: 'Stratum cover (%)',
      fields: ['StrataCoverTree', 'StrataCoverShrub', 'StrataCoverHerb', 'StrataCoverMoss'],
    },
    {
      title: 'Vegetation actions',
      fields: ['btnCoverAndHeight', 'btnCheckSppCodes', 'AddSpp', 'btnAllowSmallEntry', 'btnFindPlot'],
    },
    { title: 'Tree and shrub strata (A / B)', fields: ['SubVegA', 'SubVegAht'] },
    { title: 'Herb stratum (C)', fields: ['SubVegC', 'SubVegCht'] },
    { title: 'Moss and lichen stratum (D)', fields: ['SubVegD'] },
    { title: 'Vegetation notes', fields: ['VegNotes'] },
  ],
  'Veg Other': [
    { title: 'Plot', fields: ['Text445'] },
    { title: 'Vegetation characteristics', fields: ['USysVegOther'] },
  ],
  Other: [
    { title: 'Plot', fields: ['Text287'] },
    { title: 'User defined data', fields: ['SubOther'] },
  ],
};
const twoPageSiteFields: Record<string, readonly string[]> = {
  'Identity and survey': ['PlotType', 'PlotSize', 'SV_PolygonNumber'],
  Project: ['Option304', 'Option306', 'Option290', 'Option292'],
  'BEC Master and Working Unit': [
    'Option217',
    'Option213',
    'Option215',
    'btnCopyToUserSU',
    'GIS_BGC',
    'GIS_BGC_VER',
    'BEC_Use',
    'SiteUnitLongName',
  ],
  Location: ['LocationAccuracy', 'ProvinceStateTerritory'],
  'Site conditions and stand': [
    'SV_StandAgeEstMeas',
    'SV_StandHeight',
    'SV_StandHeightEstMeas',
    'SV_CanopyComposition',
  ],
  'Entry and source actions': ['Toggle196', 'Toggle197', 'PlotList'],
};
groups['Site/Veg'] = [
  ...groups.Site.map((group) => ({ ...group, fields: [...group.fields, ...(twoPageSiteFields[group.title] ?? [])] })),
  ...groups.Vegetation.map((group) => ({
    ...group,
    fields: [
      ...group.fields,
      ...(group.title === 'Stratum cover (%)'
        ? ['StrataCoverTotal']
        : group.title === 'Vegetation actions'
          ? ['SV_FullCruiseCard']
          : []),
    ],
  })),
];
groups['Soil/Terrain'] = groups['Soil/Terrain'].map((group) => ({
  ...group,
  fields: [
    ...group.fields,
    ...(group.title === 'Soil classification'
      ? ['SV_AhorizonType', 'SV_AhorizonDepth']
      : group.title === 'Rooting and restricting layer'
        ? ['SV_RootZoneTexture', 'SV_SoilDepth', 'SV_PercentCoarseFrags', 'ActiveLayerDepth']
        : group.title === 'Water and drainage'
          ? ['SV_GleyingMottlingCM', 'SV_FloodPlain', 'SV_WaterTableCM']
          : []),
  ],
}));
const labels: Record<string, string> = {
  BECSiteUnit: 'BEC Master',
  UserSiteUnit: 'Working Unit',
  Zone: 'BEC zone',
  SubZone: 'BEC subzone',
  TransDistrib: 'Transition / distribution',
  MoistureRegime: 'Moisture regime',
  NutrientRegime: 'Nutrient regime',
  MesoSlopePosition: 'Meso slope position',
  SurfaceShape: 'Surface shape',
  SitePlotQuality: 'Site data quality',
  VegPlotQuality: 'Vegetation data quality',
  SoilPlotQuality: 'Soil data quality',
  SubstrateOrganicMatter: 'Organic matter (%)',
  SubstrateRocks: 'Rocks (%)',
  SubstrateDecWood: 'Decaying wood (%)',
  SubstrateMineralSoil: 'Mineral soil (%)',
  SubstrateBedRock: 'Bedrock (%)',
  SubstrateWater: 'Water (%)',
  SiteDisturbance1: 'Site disturbance 1',
  SiteDisturbance2: 'Site disturbance 2',
  SiteDisturbance3: 'Site disturbance 3',
  Exposure1: 'Exposure 1',
  Exposure2: 'Exposure 2',
  SiteNotes: 'Field notes',
  OfficeNotes: 'Office notes',
  SoilClassGroup: 'Soil great group',
  SoilClassSubGroup: 'Soil subgroup',
  BedrockGeology1: 'Bedrock type 1',
  BedrockGeology2: 'Bedrock type 2',
  BedrockGeology3: 'Bedrock type 3',
  CoarseFragLith1: 'Coarse fragment lithology 1',
  CoarseFragLith2: 'Coarse fragment lithology 2',
  CoarseFragLith3: 'Coarse fragment lithology 3',
  TerrainTextureSurf: 'Surface texture',
  SurficialMaterialSurf: 'Surface material',
  SurfaceExpSurf: 'Surface expression',
  GeoMorProSurf: 'Surface geomorphic process',
  TerrainTextureSubSurf: 'Subsurface texture',
  SurficialMaterialSubSurf: 'Subsurface material',
  SurfaceExpSubSurf: 'Subsurface expression',
  GeoMorProSubSurf: 'Subsurface geomorphic process',
  HumusFormPhase: 'Humus phase',
  HumusThickness: 'Humus thickness (cm)',
  HydroGeoSystem: 'Hydrogeologic system',
  HydroGeoSubSystem: 'Hydrogeologic subsystem',
  WaterSource: 'Water source',
  FloodingRegimeFreq: 'Flooding frequency',
  FloodingRegimeDur: 'Flooding duration',
  VegNotes: 'Vegetation notes',
  SoilNotes: 'Soil notes',
  Photo: 'Photo',
  SpeciesListComplete: 'Species list complete?',
  Check369: 'Decimal degrees',
  Check371: 'Degrees and decimal minutes',
  Check373: 'Degrees, minutes and seconds',
  Option455: 'Env choices',
  Option457: 'Master choices',
  Option459: 'SU table choices',
  Option477: 'Project from Env (unavailable)',
  Option479: 'Project from Master (unavailable)',
  LatD: 'Latitude degrees',
  LatM: 'Latitude minutes',
  LatS: 'Latitude seconds',
  LonD: 'Longitude degrees',
  LonM: 'Longitude minutes',
  LonS: 'Longitude seconds',
  LatD2: 'Latitude degrees',
  LatMD: 'Latitude decimal minutes',
  LonD2: 'Longitude degrees',
  LonMD: 'Longitude decimal minutes',
  Cover1: 'A1 cover (%)',
  Cover2: 'A2 cover (%)',
  Cover3: 'A3 cover (%)',
  TotalA: 'Total A cover (%)',
  Cover4: 'B1 cover (%)',
  Cover5: 'B2 cover (%)',
  TotalB: 'Total B cover (%)',
  Height1: 'A1 height',
  Height2: 'A2 height',
  Height3: 'A3 height',
  Height4: 'B1 height',
  Height5: 'B2 height',
  UpperDepth: 'Upper depth',
  LowerDepth: 'Lower depth',
  HumusFormpH: 'Humus pH',
  MineralFormpH: 'Mineral pH',
  HumusStructureKind: 'Humus structure kind',
  HumusStructureDegree: 'Humus structure degree',
  MineralStructureKind: 'Mineral structure kind',
  MineralStructureClass: 'Mineral structure class',
  PercentCoarseFragsGravel: 'Coarse fragments: gravel (%)',
  PercentCoarseFragsCobbles: 'Coarse fragments: cobbles (%)',
  PercentCoarseFragsStones: 'Coarse fragments: stones (%)',
  PercentCoarseFragsTotal: 'Coarse fragments: total (%)',
  PercentCoarseFragsShape: 'Coarse fragments: shape',
  RootsAbundance: 'Roots abundance',
  RootsSize: 'Roots size',
};
export function controlLabel(control: PaperControl, preferSourceCaption = false): string {
  const token = control.controlName ?? control.column ?? '';
  const caption = accessCaption(control.caption).replace(/\s+/g, ' ').trim();
  return (
    (preferSourceCaption && caption ? caption : undefined) ??
    (preferSourceCaption
      ? (labels[control.column ?? ''] ?? labels[token])
      : (labels[token] ?? labels[control.column ?? ''])) ??
    (caption ||
      (control.column ?? token).replace(/([a-z])([A-Z])/g, '$1 $2').replace(/([a-zA-Z])(\d)/g, '$1 $2') ||
      'Source field')
  );
}
export function presentationGroups(name: string, controls: PaperControl[]) {
  const remaining = new Set(
    controls.filter(
      (control) =>
        !['Label', 'Rectangle', 'Line'].includes(control.type) &&
        (control.type !== 'OptionGroup' || Boolean(control.column))
    )
  );
  const result = (groups[name] ?? [])
    .map((group) => {
      const members = group.fields.flatMap((token) =>
        [...remaining].filter((control) => control.controlName === token || control.column === token)
      );
      const unique = [...new Set(members)];
      unique.forEach((control) => remaining.delete(control));
      return { title: group.title, controls: unique };
    })
    .filter((group) => group.controls.length);
  if (remaining.size)
    result.push({
      title: 'Additional source fields and actions',
      controls: [...remaining].sort((a, b) => a.tabOrder - b.tabOrder),
    });
  return result;
}
export type CardZone = 'top-band' | 'quad-left' | 'quad-right' | 'full';

const unmigratedControlNames = new Set([
  'Option477',
  'Option479',
  'Option304',
  'Option306',
  'Option290',
  'Option292',
  'Toggle408',
  'Toggle409',
  'Toggle196',
  'Toggle197',
  'AddSpp',
  'btnAllowSmallEntry',
]);

const migratedButtonNames = new Set([
  'btnCoverAndHeight',
  'btnCheckSppCodes',
  'btnFindPlot',
  'btnLoadMetadata',
  'btnCoptToWorkingUnit',
  'btnCopyToUserSU',
]);

export function isUnmigratedStubControl(control: PaperControl): boolean {
  const name = control.controlName ?? '';
  if (unmigratedControlNames.has(name)) return true;
  if (control.type === 'CommandButton' || control.type === 'ToggleButton') {
    return !migratedButtonNames.has(name);
  }
  return false;
}

export function groupCardZone(pageName: string, groupTitle: string): CardZone {
  if (pageName === 'Site' || pageName === 'Site/Veg') {
    if (groupTitle === 'Identity and survey' || groupTitle === 'Project') return 'top-band';
    if (groupTitle === 'Location' || groupTitle === 'Coordinate display' || groupTitle === 'Vegetation survey')
      return 'quad-left';
    if (
      groupTitle === 'BEC Master and Working Unit' ||
      groupTitle === 'Site classification' ||
      groupTitle === 'Site conditions and stand' ||
      groupTitle === 'Stratum cover (%)'
    ) {
      return 'quad-right';
    }
    return 'full';
  }
  if (pageName === 'Soil/Terrain') {
    if (groupTitle === 'Survey' || groupTitle === 'Geology') return 'top-band';
    if (groupTitle === 'Surface terrain' || groupTitle === 'Subsurface terrain') return 'full';
    if (groupTitle === 'Soil classification' || groupTitle === 'Humus form') return 'quad-left';
    if (
      groupTitle === 'Hydrogeology' ||
      groupTitle === 'Rooting and restricting layer' ||
      groupTitle === 'Water and drainage'
    ) {
      return 'quad-right';
    }
    return 'full';
  }
  if (pageName === 'Vegetation') {
    if (groupTitle === 'Vegetation survey') return 'quad-left';
    if (groupTitle === 'Stratum cover (%)') return 'quad-right';
    return 'full';
  }
  return 'full';
}

export function controlColumnSpan(pageName: string, groupTitle: string, control: PaperControl): number {
  if (control.type === 'Subform') return 12;
  const col = control.column ?? '';
  const name = control.controlName ?? '';

  if (groupTitle === 'Substrate (%)') return 2;
  if (groupTitle === 'Surface terrain' || groupTitle === 'Subsurface terrain') return 3;
  if (groupTitle === 'Field and office notes') return 6;
  if (col === 'SoilNotes' || col === 'VegNotes') return 12;
  if (groupTitle === 'Geology') return 4;
  if (groupTitle === 'Topography') return 2;
  if (groupTitle === 'Data quality') return 4;

  if (groupTitle === 'Identity and survey') {
    if (col === 'PlotNumber' || col === 'Date' || col === 'SiteSurveyor' || col === 'FieldNumber') return 3;
    return 4;
  }
  if (groupTitle === 'Project') {
    if (name === 'btnLoadMetadata') return 12;
    return 6;
  }
  if (groupTitle === 'Location') {
    if (col === 'Location') return 12;
    if (col === 'FSRegionDistrict' || col === 'Ecosection') return 6;
    return 4;
  }
  if (groupTitle === 'Coordinate display') {
    if (name === 'Check369' || name === 'Check371' || name === 'Check373') return 4;
    if (col === 'Latitude' || col === 'Longitude' || name === 'Latitude' || name === 'Longitude') return 6;
    if (name === 'LatD2' || name === 'LatMD' || name === 'LonD2' || name === 'LonMD') return 3;
    if (name === 'LatD' || name === 'LatM' || name === 'LatS' || name === 'LonD' || name === 'LonM' || name === 'LonS')
      return 4;
    return 4;
  }
  if (groupTitle === 'BEC Master and Working Unit') {
    if (col === 'BECSiteUnit' || col === 'UserSiteUnit') return 6;
    if (col === 'SiteUnitLongName') return 12;
    if (name === 'btnCoptToWorkingUnit' || name === 'btnCopyToUserSU') return 6;
    return 4;
  }
  if (groupTitle === 'Site classification') {
    if (col === 'PlotRepresenting') return 12;
    return 4;
  }
  if (groupTitle === 'Site conditions and stand') {
    if (col === 'MoistureRegime' || col === 'NutrientRegime') return 6;
    if (col === 'SV_CanopyComposition') return 12;
    return 4;
  }
  if (groupTitle === 'Disturbance and exposure') {
    if (col === 'Exposure1' || col === 'Exposure2') return 3;
    return 2;
  }
  if (groupTitle === 'Survey') return 6;
  if (groupTitle === 'Soil classification') return 6;
  if (groupTitle === 'Humus form') return 4;
  if (groupTitle === 'Hydrogeology') return 6;
  if (groupTitle === 'Rooting and restricting layer') return 6;
  if (groupTitle === 'Water and drainage') return 4;
  if (groupTitle === 'Vegetation survey') return 4;
  if (groupTitle === 'Stratum cover (%)') {
    if (pageName === 'Site/Veg') return col === 'StrataCoverTotal' ? 4 : 2;
    return 3;
  }
  if (groupTitle === 'Vegetation actions') return 4;

  return wideControl(control) ? 12 : 3;
}

export function wideControl(control: PaperControl): boolean {
  return (
    control.type === 'Subform' ||
    ['Location', 'PlotRepresenting', 'SiteNotes', 'OfficeNotes', 'SoilNotes', 'VegNotes'].includes(control.column ?? '')
  );
}

export interface HeaderStandardFieldSpec {
  key: string;
  label: string;
  kind: 'text' | 'notes' | 'number';
  list?: boolean;
  step?: string;
}

export const headerFieldSpecs: readonly [string, HeaderStandardFieldSpec][] = [
  ['ProjectID', { key: 'projectId', label: 'Project ID', kind: 'text' }],
  ['FieldNumber', { key: 'fieldNo', label: 'Field number', kind: 'text' }],
  ['SiteSurveyor', { key: 'surveyor', label: 'Site surveyor', kind: 'text' }],
  ['Date', { key: 'date', label: 'Survey date', kind: 'text' }],
  ['StartDate', { key: 'startDate', label: 'Start year', kind: 'number' }],
  ['Location', { key: 'generalLocation', label: 'Location', kind: 'text' }],
  ['NtsMapSheet', { key: 'mapSheet', label: 'NTS map sheet', kind: 'text' }],
  ['UTMZone', { key: 'utmZone', label: 'UTM zone', kind: 'text' }],
  ['UTMEasting', { key: 'easting', label: 'UTM easting', kind: 'number', step: 'any' }],
  ['UTMNorthing', { key: 'northing', label: 'UTM northing', kind: 'number', step: 'any' }],
  ['LocationAccuracy', { key: 'accuracy', label: 'Location accuracy', kind: 'number' }],
  ['PlotRepresenting', { key: 'plotRepresenting', label: 'Plot representing', kind: 'text' }],
  ['TransDistrib', { key: 'transition', label: 'Transition distribution', kind: 'text' }],
  ['MapUnit', { key: 'mapUnit', label: 'Map unit', kind: 'text' }],
  ['MoistureRegime', { key: 'moistureRegime', label: 'Moisture regime', kind: 'text', list: true }],
  ['NutrientRegime', { key: 'nutrientRegime', label: 'Nutrient regime', kind: 'text', list: true }],
  ['SuccessionalStatus', { key: 'successional', label: 'Successional status', kind: 'text' }],
  ['StructuralStage', { key: 'structuralStage', label: 'Structural stage', kind: 'text' }],
  ['StandAge', { key: 'standAge', label: 'Stand age', kind: 'number' }],
  ['Elevation', { key: 'elevation', label: 'Elevation (m)', kind: 'number' }],
  ['SlopeGradient', { key: 'slope', label: 'Slope gradient (%)', kind: 'number', step: 'any' }],
  ['Aspect', { key: 'aspect', label: 'Aspect (degrees)', kind: 'number' }],
  ['MesoSlopePosition', { key: 'mesoSlopePos', label: 'Meso slope position', kind: 'text', list: true }],
  ['SurfaceShape', { key: 'surfaceShape', label: 'Surface shape', kind: 'text', list: true }],
  ['SurfaceTopographyType', { key: 'microtopType', label: 'Surface topography type', kind: 'text' }],
  ['SurfaceTopographySize', { key: 'microtopSize', label: 'Surface topography size', kind: 'text' }],
  ['SiteNotes', { key: 'fieldNotes', label: 'Site notes', kind: 'notes' }],
  ['OfficeNotes', { key: 'officeNotes', label: 'Office notes', kind: 'notes' }],
];

import type { Snippet } from 'svelte';
import type { FS882Header, ListItem } from '../../bindings/github.com/boostao/vpro/app';
import type { BECCodes } from './becEditor';
import type { CoordinateDisplayMode } from './coordinateEditor';
import type { QualityCodes } from './qualityEditor';
import type { RegionCodes } from './regionCodeEditor';
import type { SiteCodes } from './siteCodeEditor';
import type { SubstrateValues } from './substrateEditor';
import type { WorkingUnitCodes, WorkingUnitSession } from './workingUnitEditor';

export type HeaderTextKey = {
  [K in keyof FS882Header]: FS882Header[K] extends string | null ? K : never;
}[keyof FS882Header];
export type HeaderNullableTextKey = Exclude<HeaderTextKey, 'plotNumber'>;
export type HeaderNumberKey = {
  [K in keyof FS882Header]: FS882Header[K] extends number | null ? K : never;
}[keyof FS882Header];
export type HeaderValidationKey =
  | HeaderNumberKey
  | 'plotNumber'
  | 'date'
  | 'utmZone'
  | 'standCodes'
  | 'substrateBounds'
  | 'bec'
  | 'workingUnit'
  | 'masterBEC'
  | 'quality'
  | 'substrate'
  | 'siteCodes'
  | 'regionCodes';
export type HeaderSlot = {
  columns: readonly string[];
  controls: readonly string[];
  input: Snippet<[PaperControl, string]>;
  labelled: true;
};
export type HeaderOriginal =
  | (BECCodes & WorkingUnitCodes & QualityCodes & SubstrateValues & SiteCodes & RegionCodes & Partial<FS882Header>)
  | null;
export type HeaderColumnEditor = { columns: readonly string[]; input: Snippet<[PaperControl, string]> };

export interface HeaderEditorBaseProps {
  draft: FS882Header;
  original: HeaderOriginal;
  capabilities: Record<string, boolean | undefined>;
  disabled: boolean;
  existing: boolean;
  lists: Partial<Record<HeaderNullableTextKey, ListItem[]>>;
  onchange: () => void;
  onerror: (message: string) => void;
  onvalidation: (key: HeaderValidationKey, message: string | null) => void;
  masterAllowed?: boolean;
  extendedShrubs?: boolean;
  snowCoverRegime?: string;
  activeLayerDepth?: string;
  snowCoverRegimeDisabled?: boolean;
  activeLayerDepthDisabled?: boolean;
  snowCoverRegimeError?: string | null;
  activeLayerDepthError?: string | null;
  onSnowCoverRegimeChange?: (value: string) => void;
  onActiveLayerDepthChange?: (value: string) => void;
  onWorkingUnitBusyChange?: (busy: boolean) => void;
  onQualityBusyChange?: (busy: boolean) => void;
  onSiteCodeBusyChange?: (busy: boolean) => void;
  onRegionCodeBusyChange?: (busy: boolean) => void;
  workingUnitSession: WorkingUnitSession;
  editor?: HeaderColumnEditor;
  additionalEditor?: HeaderColumnEditor;
  onMetadata?: () => void;
  metadataDisabled?: boolean;
  onOpenPictureManager?: (plotNumber: string) => void;
  projectIds?: readonly string[];
  pictureEditor?: Snippet;
  sourcePage?: ReturnType<typeof import('./paperLayout').paperPage>;
  coordinateMode?: CoordinateDisplayMode;
  children?: Snippet<[HeaderSlot, CoordinateDisplayMode]>;
}
