export type ValidationFormTab = 'site' | 'soils' | 'veg' | 'vegOther' | 'other' | 'siviParent';

export interface FormValidationItem {
  id: string;
  tab: ValidationFormTab;
  tabLabel: string;
  fieldLabel: string;
  message: string;
  targetColumn?: string;
  targetSelector?: string;
}

const HEADER_KEY_TO_COLUMN_AND_TAB: Record<
  string,
  { tab: ValidationFormTab; tabLabel: string; fieldLabel: string; column?: string; selector?: string }
> = {
  plotNumber: { tab: 'site', tabLabel: 'Site', fieldLabel: 'Plot Number', column: 'PlotNumber', selector: '#header-plotNumber' },
  latitude: { tab: 'site', tabLabel: 'Site', fieldLabel: 'Latitude', column: 'Latitude' },
  longitude: { tab: 'site', tabLabel: 'Site', fieldLabel: 'Longitude', column: 'Longitude' },
  coordinate: { tab: 'site', tabLabel: 'Site', fieldLabel: 'Coordinates', column: 'Latitude' },
  zone: { tab: 'site', tabLabel: 'Site', fieldLabel: 'BEC Zone', column: 'Zone' },
  subZone: { tab: 'site', tabLabel: 'Site', fieldLabel: 'BEC Subzone', column: 'SubZone' },
  siteSeries: { tab: 'site', tabLabel: 'Site', fieldLabel: 'Site Series', column: 'SiteSeries' },
  becSiteUnit: { tab: 'site', tabLabel: 'Site', fieldLabel: 'BEC Master Unit', column: 'BECSiteUnit' },
  userSiteUnit: { tab: 'site', tabLabel: 'Site', fieldLabel: 'Working Unit', column: 'UserSiteUnit' },
  sitePlotQuality: { tab: 'site', tabLabel: 'Site', fieldLabel: 'Site Quality', column: 'SitePlotQuality' },
  vegPlotQuality: { tab: 'site', tabLabel: 'Site', fieldLabel: 'Veg Quality', column: 'VegPlotQuality' },
  soilPlotQuality: { tab: 'site', tabLabel: 'Site', fieldLabel: 'Soil Quality', column: 'SoilPlotQuality' },
  substrateOrganicMatter: { tab: 'site', tabLabel: 'Site', fieldLabel: 'Organic Matter (%)', column: 'SubstrateOrganicMatter' },
  substrateDecWood: { tab: 'site', tabLabel: 'Site', fieldLabel: 'Decaying Wood (%)', column: 'SubstrateDecWood' },
  substrateBedRock: { tab: 'site', tabLabel: 'Site', fieldLabel: 'Bedrock (%)', column: 'SubstrateBedRock' },
  substrateRocks: { tab: 'site', tabLabel: 'Site', fieldLabel: 'Rocks (%)', column: 'SubstrateRocks' },
  substrateMineralSoil: { tab: 'site', tabLabel: 'Site', fieldLabel: 'Mineral Soil (%)', column: 'SubstrateMineralSoil' },
  substrateWater: { tab: 'site', tabLabel: 'Site', fieldLabel: 'Water (%)', column: 'SubstrateWater' },
  substrate: { tab: 'site', tabLabel: 'Site', fieldLabel: 'Substrate (%)', selector: '.substrate-control[aria-invalid="true"], [data-column^="Substrate"]' },
  bec: { tab: 'site', tabLabel: 'Site', fieldLabel: 'BEC Classification', selector: '[data-column="Zone"][aria-invalid="true"], [data-column="SubZone"][aria-invalid="true"], [data-column="SiteSeries"][aria-invalid="true"], [data-column="Zone"]' },
  workingUnit: { tab: 'site', tabLabel: 'Site', fieldLabel: 'Working Unit', column: 'UserSiteUnit' },
  quality: { tab: 'site', tabLabel: 'Site', fieldLabel: 'Data Quality', selector: '[data-column$="PlotQuality"][aria-invalid="true"], [data-column="SitePlotQuality"]' },
  siteCodes: { tab: 'site', tabLabel: 'Site', fieldLabel: 'Site Code', selector: '[data-source-page="Site"] [aria-invalid="true"], [data-column="SiteDisturbance1"]' },
  regionCodes: { tab: 'site', tabLabel: 'Site', fieldLabel: 'Region / Ecosection', selector: '[data-column="FSRegionDistrict"][aria-invalid="true"], [data-column="Ecosection"][aria-invalid="true"], [data-column="FSRegionDistrict"]' },
  soilCodes: { tab: 'soils', tabLabel: 'Soil/Terrain', fieldLabel: 'Soil Classification Code', selector: '[data-source-page="Soil/Terrain"] [aria-invalid="true"], [data-column="SoilClassGroup"]' },
  geologyCodes: { tab: 'soils', tabLabel: 'Soil/Terrain', fieldLabel: 'Geology / Lithology Code', selector: '[data-column^="BedrockGeology"][aria-invalid="true"], [data-column^="CoarseFragLith"][aria-invalid="true"], [data-column="BedrockGeology1"]' },
  'ordinary-soils': { tab: 'soils', tabLabel: 'Soil/Terrain', fieldLabel: 'Soil Field', selector: '[data-source-page="Soil/Terrain"] [aria-invalid="true"]' },
  'parentCodes-soils': { tab: 'soils', tabLabel: 'Soil/Terrain', fieldLabel: 'Terrain / Soil Code', selector: '[data-source-page="Soil/Terrain"] [aria-invalid="true"]' },
  'ordinary-veg': { tab: 'veg', tabLabel: 'Vegetation', fieldLabel: 'Vegetation Header', selector: '[data-source-page="Vegetation"] [aria-invalid="true"]' },
  fsRegionDistrict: { tab: 'site', tabLabel: 'Site', fieldLabel: 'Region / District', column: 'FSRegionDistrict' },
  ecosection: { tab: 'site', tabLabel: 'Site', fieldLabel: 'Ecosection', column: 'Ecosection' },
  snowCoverRegime: { tab: 'site', tabLabel: 'Site', fieldLabel: 'Snow Cover Regime', column: 'SnowCoverregime', selector: '#header-snowCoverregime' },
  activeLayerDepth: { tab: 'site', tabLabel: 'Site', fieldLabel: 'Active Layer Depth', column: 'ActiveLayerDepth', selector: '#header-activeLayerDepth' },
  soilClassGroup: { tab: 'soils', tabLabel: 'Soil/Terrain', fieldLabel: 'Soil Great Group', column: 'SoilClassGroup' },
  soilClassSubGroup: { tab: 'soils', tabLabel: 'Soil/Terrain', fieldLabel: 'Soil Subgroup', column: 'SoilClassSubGroup' },
  humusForm: { tab: 'soils', tabLabel: 'Soil/Terrain', fieldLabel: 'Humus Form', column: 'HumusForm' },
  humusFormPhase: { tab: 'soils', tabLabel: 'Soil/Terrain', fieldLabel: 'Humus Phase', column: 'HumusFormPhase' },
  hydroGeoSystem: { tab: 'soils', tabLabel: 'Soil/Terrain', fieldLabel: 'Hydrogeologic System', column: 'HydroGeoSystem' },
  hydroGeoSubSystem: { tab: 'soils', tabLabel: 'Soil/Terrain', fieldLabel: 'Hydrogeologic Subsystem', column: 'HydroGeoSubSystem' },
  waterSource: { tab: 'soils', tabLabel: 'Soil/Terrain', fieldLabel: 'Water Source', column: 'WaterSource' },
  soilDrainage: { tab: 'soils', tabLabel: 'Soil/Terrain', fieldLabel: 'Soil Drainage', column: 'SoilDrainage' },
  floodingRegimeFreq: { tab: 'soils', tabLabel: 'Soil/Terrain', fieldLabel: 'Flooding Frequency', column: 'FloodingRegimeFreq' },
  floodingRegimeDur: { tab: 'soils', tabLabel: 'Soil/Terrain', fieldLabel: 'Flooding Duration', column: 'FloodingRegimeDur' },
  bedrockGeology1: { tab: 'soils', tabLabel: 'Soil/Terrain', fieldLabel: 'Bedrock Type 1', column: 'BedrockGeology1' },
  bedrockGeology2: { tab: 'soils', tabLabel: 'Soil/Terrain', fieldLabel: 'Bedrock Type 2', column: 'BedrockGeology2' },
  bedrockGeology3: { tab: 'soils', tabLabel: 'Soil/Terrain', fieldLabel: 'Bedrock Type 3', column: 'BedrockGeology3' },
  coarseFragLith1: { tab: 'soils', tabLabel: 'Soil/Terrain', fieldLabel: 'Coarse Frag Lithology 1', column: 'CoarseFragLith1' },
  coarseFragLith2: { tab: 'soils', tabLabel: 'Soil/Terrain', fieldLabel: 'Coarse Frag Lithology 2', column: 'CoarseFragLith2' },
  coarseFragLith3: { tab: 'soils', tabLabel: 'Soil/Terrain', fieldLabel: 'Coarse Frag Lithology 3', column: 'CoarseFragLith3' },
  strataCoverTree: { tab: 'veg', tabLabel: 'Vegetation', fieldLabel: 'Tree Cover (%)', column: 'StrataCoverTree' },
  strataCoverShrub: { tab: 'veg', tabLabel: 'Vegetation', fieldLabel: 'Shrub Cover (%)', column: 'StrataCoverShrub' },
  strataCoverHerb: { tab: 'veg', tabLabel: 'Vegetation', fieldLabel: 'Herb Cover (%)', column: 'StrataCoverHerb' },
  strataCoverMoss: { tab: 'veg', tabLabel: 'Vegetation', fieldLabel: 'Moss Cover (%)', column: 'StrataCoverMoss' },
};

function humanizeKey(key: string): string {
  return key
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .replace(/([a-zA-Z])(\d)/g, '$1 $2')
    .replace(/^./, (c) => c.toUpperCase());
}

export interface BuildValidationSummaryInput {
  siviStandalone?: boolean;
  headerValidation?: Record<string, string | undefined>;
  soilInvalid?: readonly string[];
  speciesInvalid?: readonly string[];
  heightInvalid?: readonly string[];
  creationInvalid?: readonly string[];
  personalInvalid?: readonly string[];
  attributeInvalid?: readonly string[];
  otherInvalid?: readonly string[];
}

export function buildFormValidationItems(input: BuildValidationSummaryInput): FormValidationItem[] {
  const items: FormValidationItem[] = [];
  const defaultSiteTab: ValidationFormTab = input.siviStandalone ? 'siviParent' : 'site';
  const defaultSiteLabel = input.siviStandalone ? 'Plot & Site' : 'Site';

  for (const [key, rawMsg] of Object.entries(input.headerValidation ?? {})) {
    const msg = rawMsg?.trim();
    if (!msg) continue;
    const mapped = HEADER_KEY_TO_COLUMN_AND_TAB[key];
    const isSoilField = mapped?.tab === 'soils' || /^(soil|humus|terrain|surficial|surfaceExp|geoMor|hydro|water|seepage|flood|root|bedrock|coarse)/i.test(key);
    const isVegField = mapped?.tab === 'veg' || /^(veg|strata|species)/i.test(key);
    const tab: ValidationFormTab = isSoilField
      ? 'soils'
      : isVegField
      ? 'veg'
      : defaultSiteTab;
    const tabLabel = tab === 'soils' ? 'Soil/Terrain' : tab === 'veg' ? 'Vegetation' : defaultSiteLabel;
    const column = mapped?.column ?? (key.charAt(0).toUpperCase() + key.slice(1));
    items.push({
      id: `hdr-${key}`,
      tab,
      tabLabel,
      fieldLabel: mapped?.fieldLabel ?? humanizeKey(key),
      message: msg,
      targetColumn: column,
      targetSelector: mapped?.selector ?? `[data-column="${column}"], #header-${key}`,
    });
  }

  for (const [idx, msg] of (input.soilInvalid ?? []).entries()) {
    if (!msg?.trim()) continue;
    items.push({
      id: `soil-${idx}`,
      tab: 'soils',
      tabLabel: 'Soil/Terrain',
      fieldLabel: 'Horizon Draft',
      message: msg.trim(),
      targetSelector: '.soil-draft-toolbar, [data-source-control="SoilHumus"] [aria-invalid="true"], [data-source-control="SoilMineral"] [aria-invalid="true"]',
    });
  }

  for (const [idx, msg] of (input.speciesInvalid ?? []).entries()) {
    if (!msg?.trim()) continue;
    items.push({
      id: `spp-${idx}`,
      tab: 'veg',
      tabLabel: 'Vegetation',
      fieldLabel: 'Species Code',
      message: msg.trim(),
      targetSelector: '[data-column="Species"][aria-invalid="true"], .species-draft-toolbar',
    });
  }

  for (const [idx, msg] of (input.heightInvalid ?? []).entries()) {
    if (!msg?.trim()) continue;
    items.push({
      id: `ht-${idx}`,
      tab: 'veg',
      tabLabel: 'Vegetation',
      fieldLabel: 'Strata Cover / Height',
      message: msg.trim(),
      targetSelector: '.source-child [aria-invalid="true"], .height-draft-toolbar',
    });
  }

  for (const [idx, msg] of (input.creationInvalid ?? []).entries()) {
    if (!msg?.trim()) continue;
    items.push({
      id: `create-${idx}`,
      tab: 'veg',
      tabLabel: 'Vegetation',
      fieldLabel: 'New Species Row',
      message: msg.trim(),
      targetSelector: '#creation-species, .vegetation-creation-draft [aria-invalid="true"]',
    });
  }

  for (const [idx, msg] of (input.personalInvalid ?? []).entries()) {
    if (!msg?.trim()) continue;
    items.push({
      id: `pers-${idx}`,
      tab: 'veg',
      tabLabel: 'Vegetation',
      fieldLabel: 'Personal Species',
      message: msg.trim(),
      targetSelector: '.personal-species-draft input',
    });
  }

  for (const [idx, msg] of (input.attributeInvalid ?? []).entries()) {
    if (!msg?.trim()) continue;
    items.push({
      id: `attr-${idx}`,
      tab: 'vegOther',
      tabLabel: 'Veg Other',
      fieldLabel: 'Veg Attribute',
      message: msg.trim(),
      targetSelector: '[data-source-control="USysVegOther"] [aria-invalid="true"], .attribute-draft-toolbar',
    });
  }

  for (const [idx, msg] of (input.otherInvalid ?? []).entries()) {
    if (!msg?.trim()) continue;
    items.push({
      id: `other-${idx}`,
      tab: 'other',
      tabLabel: 'Other',
      fieldLabel: 'Other Data',
      message: msg.trim(),
      targetSelector: '[data-source-control="SubOther"] [aria-invalid="true"], .other-draft-toolbar',
    });
  }

  return items;
}

export function focusValidationTarget(container: ParentNode | null | undefined, item: FormValidationItem): boolean {
  if (!container) return false;
  const rawGroups = [
    item.targetSelector,
    item.targetColumn ? `[data-column="${item.targetColumn}"]` : undefined,
    '[aria-invalid="true"]',
  ].filter((s): s is string => Boolean(s));

  const selectors = rawGroups.flatMap((group) =>
    group
      .split(',')
      .map((part) => part.trim())
      .filter(Boolean),
  );

  for (const sel of selectors) {
    try {
      const el = container.querySelector<HTMLElement>(sel);
      if (el) {
        if (typeof el.scrollIntoView === 'function') {
          el.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }
        if (typeof el.focus === 'function') {
          el.focus({ preventScroll: true });
        }
        return true;
      }
    } catch {
      // Ignore invalid selector edge cases and fall through
    }
  }
  return false;
}
