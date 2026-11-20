import type { ExpressionSpecification, LayerSpecification, SourceSpecification, StyleSpecification } from 'maplibre-gl';
import type { PMTilesManifest, SpatialWorkbenchPayload } from '../../bindings/github.com/boostao/vpro/app';
import type { SpatialComputeBackendInfo } from './spatialCompute';
import { pointInPolygonRing } from './spatialFlatGeobuf';

type SpatialGeoArrowColumns = SpatialWorkbenchPayload['geoArrow'];

export {
  buildWGSLSpatialFilterShader,
  detectSpatialComputeBackend,
  executeCPUSpatialFilterKernel,
  executeSpatialFilterKernel,
} from './spatialCompute';
export type { SpatialComputeBackendKind, SpatialComputeBackendInfo, SpatialFilterKernelResult } from './spatialCompute';
export { FLATGEOBUF_MAGIC_V3, decodeFlatGeobufPoints, pointInPolygonRing } from './spatialFlatGeobuf';
export type { DecodedFlatGeobufPlot } from './spatialFlatGeobuf';

export interface WorkbenchPlotPoint {
  index: number;
  plotNumber: string;
  lon: number;
  lat: number;
  hasUtm: boolean;
  utmDerivedLon: number | null;
  utmDerivedLat: number | null;
  divergenceMeters: number;
  divergenceFlagged: boolean;
  longitudeFlipped: boolean;
  elevation: number | null;
  slope: number | null;
  aspect: number | null;
  zone: string;
  subZone: string;
  fieldBgc: string;
  gisBgc: string;
  bgcMismatch: boolean;
  siteUnit: string;
  ecosection: string;
  fsRegionDistrict: string;
}

export interface DiscrepancyVectorSegment {
  plotNumber: string;
  sourcePosition: [number, number];
  targetPosition: [number, number];
  divergenceMeters: number;
  flagged: boolean;
}

export interface MapLayerVisibility {
  bgcFill: boolean;
  bgcLabels: boolean;
  ecosections: boolean;
  nrDistricts: boolean;
  hillshade3D: boolean;
  bcOpenMapsWMS: boolean;
  discrepancyVectors: boolean;
}

// Official BC Ministry of Forests BEC v13 Zone thematic palette
export const BEC_ZONE_PALETTE: Record<string, string> = {
  CDF: '#a3cc51',
  CWH: '#20854e',
  MH: '#5c4d99',
  CMA: '#b8c4d0',
  IMA: '#c9d4df',
  BAFA: '#9eb0c2',
  ESSF: '#7a5299',
  ICH: '#2d9a8c',
  SBS: '#3b82b6',
  SBPS: '#6aaed6',
  MS: '#9e7bb5',
  IDF: '#d99b26',
  PP: '#e07b39',
  BG: '#c94a38',
  BWBS: '#4a90a4',
  SWB: '#6d8fa6',
};

const DEFAULT_BC_VIEW_STATE = {
  longitude: -124.8,
  latitude: 54.2,
  zoom: 4.8,
  pitch: 0,
  bearing: 0,
};

export const INITIAL_COMPUTE_INFO: SpatialComputeBackendInfo = {
  backend: 'webgl2-cpu',
  available: false,
  adapterLabel: 'Probing GPU compute...',
  maxComputeWorkgroupSizeX: 0,
  fallbackReason: null,
};

export const INITIAL_LAYER_VISIBILITY: MapLayerVisibility = {
  bgcFill: true,
  bgcLabels: true,
  ecosections: false,
  nrDistricts: false,
  hillshade3D: false,
  bcOpenMapsWMS: false,
  discrepancyVectors: true,
};

export function materializeWorkbenchPlots(cols: SpatialGeoArrowColumns | null | undefined): {
  points: WorkbenchPlotPoint[];
  coordsFloat32: Float32Array;
  discrepancyVectors: DiscrepancyVectorSegment[];
} {
  if (!cols || !cols.count) {
    return { points: [], coordsFloat32: new Float32Array(0), discrepancyVectors: [] };
  }
  const n = cols.count;
  const points: WorkbenchPlotPoint[] = new Array(n);
  const coordsFloat32 = new Float32Array(n * 2);
  const discrepancyVectors: DiscrepancyVectorSegment[] = [];

  for (let i = 0; i < n; i++) {
    const lon = cols.lon?.[i] ?? 0;
    const lat = cols.lat?.[i] ?? 0;
    const hasUtm = cols.hasUtm?.[i] ?? false;
    const utmLon = hasUtm ? (cols.utmDerivedLon?.[i] ?? null) : null;
    const utmLat = hasUtm ? (cols.utmDerivedLat?.[i] ?? null) : null;
    const divM = cols.divergenceMeters?.[i] ?? 0;
    const divFlag = cols.divergenceFlagged?.[i] ?? false;

    coordsFloat32[i * 2] = lon;
    coordsFloat32[i * 2 + 1] = lat;

    const pt: WorkbenchPlotPoint = {
      index: i,
      plotNumber: cols.plotNumber?.[i] ?? '',
      lon,
      lat,
      hasUtm,
      utmDerivedLon: utmLon,
      utmDerivedLat: utmLat,
      divergenceMeters: divM,
      divergenceFlagged: divFlag,
      longitudeFlipped: cols.longitudeFlipped?.[i] ?? false,
      elevation: cols.hasElevation?.[i] ? (cols.elevation?.[i] ?? null) : null,
      slope: cols.hasSlope?.[i] ? (cols.slope?.[i] ?? null) : null,
      aspect: cols.hasAspect?.[i] ? (cols.aspect?.[i] ?? null) : null,
      zone: cols.zone?.[i] ?? '',
      subZone: cols.subZone?.[i] ?? '',
      fieldBgc: cols.fieldBgc?.[i] ?? '',
      gisBgc: cols.gisBgc?.[i] ?? '',
      bgcMismatch: cols.bgcMismatch?.[i] ?? false,
      siteUnit: cols.siteUnit?.[i] ?? '',
      ecosection: cols.ecosection?.[i] ?? '',
      fsRegionDistrict: cols.fsRegionDistrict?.[i] ?? '',
    };
    points[i] = pt;

    if (hasUtm && utmLon !== null && utmLat !== null && divM >= 5.0) {
      discrepancyVectors.push({
        plotNumber: pt.plotNumber,
        sourcePosition: [lon, lat],
        targetPosition: [utmLon, utmLat],
        divergenceMeters: divM,
        flagged: divFlag,
      });
    }
  }

  return { points, coordsFloat32, discrepancyVectors };
}

function buildBECZoneMatchExpression(): ExpressionSpecification {
  const stops: string[] = [];
  for (const [zone, hex] of Object.entries(BEC_ZONE_PALETTE)) {
    stops.push(zone, hex);
  }
  return ['match', ['get', 'ZONE'], ...stops, '#474543'] as unknown as ExpressionSpecification;
}

type PMTilesArchiveStatusExt = NonNullable<PMTilesManifest['archives']>[string] & {
  warning?: string;
};

function buildOfflineGraticuleGeoJSON(): {
  type: 'FeatureCollection';
  features: Array<{
    type: 'Feature';
    properties: { label: string };
    geometry: { type: 'LineString'; coordinates: Array<[number, number]> };
  }>;
} {
  const features: Array<{
    type: 'Feature';
    properties: { label: string };
    geometry: { type: 'LineString'; coordinates: Array<[number, number]> };
  }> = [];
  for (let lon = -140; lon <= -110; lon += 5) {
    features.push({
      type: 'Feature',
      properties: { label: `${Math.abs(lon)}W` },
      geometry: {
        type: 'LineString',
        coordinates: [
          [lon, 45],
          [lon, 65],
        ],
      },
    });
  }
  for (let lat = 48; lat <= 62; lat += 2) {
    features.push({
      type: 'Feature',
      properties: { label: `${lat}N` },
      geometry: {
        type: 'LineString',
        coordinates: [
          [-142, lat],
          [-110, lat],
        ],
      },
    });
  }
  return { type: 'FeatureCollection', features };
}

/**
 * Builds the offline-first MapLibre GL JS v6 style specification backed by local PMTiles
 * byte-range sources and optional BC OpenMaps WMS orthoimagery.
 */
export function buildMapLibreGeospatialStyle(
  manifest: PMTilesManifest | null | undefined,
  visibility: MapLayerVisibility,
  options?: { forceGraticuleFallback?: boolean }
): StyleSpecification {
  const bgcArchive = manifest?.archives?.['bc-bgc-v13.pmtiles'] as PMTilesArchiveStatusExt | undefined;
  const adminArchive = manifest?.archives?.['bc-admin-ecosections-districts.pmtiles'] as
    PMTilesArchiveStatusExt | undefined;
  const bgcAvailable = !options?.forceGraticuleFallback && bgcArchive?.available !== false;
  const adminAvailable = !options?.forceGraticuleFallback && adminArchive?.available !== false;
  const bgcMaxZoom = bgcArchive?.maxZoom && bgcArchive.maxZoom > 0 ? bgcArchive.maxZoom : 6;
  const adminMaxZoom = adminArchive?.maxZoom && adminArchive.maxZoom > 0 ? adminArchive.maxZoom : 6;

  const sources: Record<string, SourceSpecification> = {
    vpro_offline_graticule: {
      type: 'geojson',
      data: buildOfflineGraticuleGeoJSON(),
    },
  };

  if (bgcAvailable) {
    sources.bc_bgc_pmtiles = {
      type: 'vector',
      url: 'pmtiles:///maps/bc-bgc-v13.pmtiles',
      minzoom: 3,
      maxzoom: bgcMaxZoom,
      attribution: 'BC Ministry of Forests BEC v13',
    };
  }
  if (adminAvailable) {
    sources.bc_admin_pmtiles = {
      type: 'vector',
      url: 'pmtiles:///maps/bc-admin-ecosections-districts.pmtiles',
      minzoom: 3,
      maxzoom: adminMaxZoom,
      attribution: 'GeoBC Ecosections & NR Districts',
    };
  }

  if (visibility.bcOpenMapsWMS) {
    sources.bc_openmaps_wms = {
      type: 'raster',
      tiles: [
        'https://openmaps.gov.bc.ca/geo/pub/ows?service=WMS&version=1.3.0&request=GetMap&layers=pub:WHSE_BASEMAPPING.DRA_DGTL_ROAD_ATLAS_MPAR_SP&styles=&crs=EPSG:3857&bbox={bbox-epsg-3857}&width=256&height=256&format=image/png&transparent=true',
      ],
      tileSize: 256,
      attribution: 'BC Data Catalogue OpenMaps WMS',
    };
  }

  const layers: LayerSpecification[] = [
    {
      id: 'vpro-ocean-background',
      type: 'background',
      paint: {
        'background-color': visibility.hillshade3D ? '#002244' : '#F2F2F2',
      },
    },
    {
      id: 'vpro-offline-graticule-lines',
      type: 'line',
      source: 'vpro_offline_graticule',
      paint: {
        'line-color': visibility.hillshade3D ? '#1A5A96' : '#D8D8D8',
        'line-width': 0.8,
        'line-dasharray': [2, 3],
        'line-opacity': 0.65,
      },
    },
  ];

  if (bgcAvailable) {
    layers.push(
      {
        id: 'bgc-zones-fill',
        type: 'fill',
        source: 'bc_bgc_pmtiles',
        'source-layer': 'bgc',
        layout: {
          visibility: visibility.bgcFill ? 'visible' : 'none',
        },
        paint: {
          'fill-color': buildBECZoneMatchExpression(),
          'fill-opacity': visibility.hillshade3D ? 0.62 : 0.48,
        },
      },
      {
        id: 'bgc-subzone-outline',
        type: 'line',
        source: 'bc_bgc_pmtiles',
        'source-layer': 'bgc',
        layout: {
          visibility: visibility.bgcFill ? 'visible' : 'none',
        },
        paint: {
          'line-color': '#003366',
          'line-width': ['interpolate', ['linear'], ['zoom'], 4, 0.35, 9, 1.1],
          'line-opacity': 0.55,
        },
      }
    );
  }

  if (adminAvailable) {
    layers.push(
      {
        id: 'ecosections-outline',
        type: 'line',
        source: 'bc_admin_pmtiles',
        'source-layer': 'ecosections',
        layout: {
          visibility: visibility.ecosections ? 'visible' : 'none',
        },
        paint: {
          'line-color': '#1A5A96',
          'line-width': 1.4,
          'line-dasharray': [3, 2],
          'line-opacity': 0.85,
        },
      },
      {
        id: 'nr-districts-outline',
        type: 'line',
        source: 'bc_admin_pmtiles',
        'source-layer': 'nr_districts',
        layout: {
          visibility: visibility.nrDistricts ? 'visible' : 'none',
        },
        paint: {
          'line-color': '#FCBA19',
          'line-width': 1.8,
          'line-opacity': 0.9,
        },
      }
    );
  }

  if (visibility.bcOpenMapsWMS) {
    layers.push({
      id: 'bc-openmaps-wms-layer',
      type: 'raster',
      source: 'bc_openmaps_wms',
      paint: { 'raster-opacity': 0.72 },
    });
  }

  return {
    version: 8,
    name: 'VPro Offline BGC v13 Geospatial Style',
    sources,
    layers,
  };
}

export function summarizePMTilesManifestWarnings(manifest: PMTilesManifest | null | undefined): string | null {
  if (!manifest?.archives) return null;
  const warnings: string[] = [];
  for (const raw of Object.values(manifest.archives)) {
    const item = raw as PMTilesArchiveStatusExt | undefined;
    const warn = typeof item?.warning === 'string' ? item.warning.trim() : '';
    if (warn && !warnings.includes(warn)) {
      warnings.push(warn);
    }
  }
  return warnings.length > 0 ? warnings.join(' ') : null;
}

export function summarizeArchiveResolution(payload: SpatialWorkbenchPayload | null): string {
  if (!payload?.manifest?.archives) return 'Resolving local map layers...';
  const bgc = payload.manifest.archives['bc-bgc-v13.pmtiles'] as PMTilesArchiveStatusExt | undefined;
  if (!bgc) return 'Built-in Overview Map (z3..6)';
  const minZ = bgc.minZoom > 0 ? bgc.minZoom : 3;
  const maxZ = bgc.maxZoom > 0 ? bgc.maxZoom : 6;
  if (bgc.fullResolution) {
    return `Full-Resolution Provincial Map (z${minZ}..${maxZ})`;
  }
  if (bgc.warning) {
    return `Built-in Overview Fallback (z${minZ}..${maxZ}, local archive unreadable)`;
  }
  return `Built-in Overview Fallback (z${minZ}..${maxZ})`;
}

export function classifyPMTilesMapError(event: unknown): string | null {
  if (!event || typeof event !== 'object') return null;
  const rec = event as Record<string, any>;
  const sourceId = typeof rec.sourceId === 'string' ? rec.sourceId : '';
  const errObj = rec.error;
  const errMsg =
    errObj instanceof Error
      ? errObj.message
      : typeof errObj?.message === 'string'
        ? errObj.message
        : typeof rec.message === 'string'
          ? rec.message
          : '';
  const errUrl = typeof errObj?.url === 'string' ? errObj.url : typeof rec.url === 'string' ? rec.url : '';
  const lowerMsg = errMsg.toLowerCase();
  const lowerUrl = errUrl.toLowerCase();
  const isPMTilesSource =
    sourceId === 'bc_bgc_pmtiles' ||
    sourceId === 'bc_admin_pmtiles' ||
    lowerUrl.includes('.pmtiles') ||
    lowerMsg.includes('pmtiles') ||
    lowerMsg.includes('bad header') ||
    lowerMsg.includes('wrong magic');
  if (!isPMTilesSource) return null;
  if (
    lowerMsg.includes('pmtiles') ||
    lowerMsg.includes('header') ||
    lowerMsg.includes('magic') ||
    lowerMsg.includes('corrupt') ||
    lowerMsg.includes('decompress') ||
    lowerMsg.includes('range') ||
    lowerMsg.includes('fetch') ||
    lowerMsg.includes('404') ||
    lowerMsg.includes('status')
  ) {
    return 'A local PMTiles map archive could not be decoded. Switched to the built-in offline map fallback.';
  }
  return null;
}

export function classifyWMSMapError(event: unknown, wmsEnabled: boolean, online?: boolean): string | null {
  if (!wmsEnabled) return null;
  if (online === false) {
    return 'BC OpenMaps WMS imagery is unreachable while offline. Offline BGC v13, Ecosections, NR Districts, and plot layers remain active.';
  }
  if (!event || typeof event !== 'object') return null;
  const rec = event as Record<string, any>;
  const sourceId = typeof rec.sourceId === 'string' ? rec.sourceId : '';
  const errObj = rec.error;
  const errMsg =
    errObj instanceof Error
      ? errObj.message
      : typeof errObj?.message === 'string'
        ? errObj.message
        : typeof rec.message === 'string'
          ? rec.message
          : '';
  const errUrl =
    typeof errObj?.url === 'string'
      ? errObj.url
      : typeof rec.tile?.tileID === 'object' || typeof rec.url === 'string'
        ? String(rec.url ?? '')
        : '';
  if (
    sourceId === 'bc_openmaps_wms' ||
    errUrl.includes('openmaps.gov.bc.ca') ||
    errMsg.toLowerCase().includes('openmaps.gov.bc.ca') ||
    errMsg.toLowerCase().includes('failed to fetch') ||
    errMsg.toLowerCase().includes('networkerror') ||
    errMsg.toLowerCase().includes('load tile')
  ) {
    return 'BC OpenMaps WMS tile request failed (offline or remote service unreachable). Offline map vector layers remain active.';
  }
  return null;
}

export interface SpatialStampOptions {
  allScoped: boolean;
  plotNumbers: string[];
  stampGisBgc: boolean;
  stampAdminFields: boolean;
  onlyWhenBlank: boolean;
  normalizeLongitudeSign: boolean;
  syncUtmFromLatLon: boolean;
  syncLatLonFromUTM: boolean;
}

export interface SpatialAOICommitInput {
  mode: 'update_active' | 'create_project_su' | 'create_su_file';
  suName: string;
  filePath: string;
  siteUnit: string;
  includeNonAoiPlotsAsUnassigned: boolean;
  activate: boolean;
}

export interface SpatialGpkgExportInput {
  destinationPath: string;
  crs: 'EPSG:3005' | 'EPSG:4326';
  includeAttributeTables: boolean;
  includeUnlocatedPlots: boolean;
}

export function filterWorkbenchPlots(
  plotPoints: WorkbenchPlotPoint[],
  zoneFilter: string,
  plotSearch: string
): WorkbenchPlotPoint[] {
  const zf = zoneFilter.trim().toUpperCase();
  const sq = plotSearch.trim().toLowerCase();
  return plotPoints.filter((pt) => {
    if (zf && pt.zone.toUpperCase() !== zf && !pt.gisBgc.toUpperCase().startsWith(zf)) {
      return false;
    }
    if (sq && !pt.plotNumber.toLowerCase().includes(sq) && !pt.siteUnit.toLowerCase().includes(sq)) {
      return false;
    }
    return true;
  });
}

export function extractDistinctZones(plotPoints: WorkbenchPlotPoint[]): string[] {
  const set = new Set<string>();
  for (const p of plotPoints) {
    if (p.zone) set.add(p.zone);
  }
  return [...set].sort();
}

type AOIGeoJSONFeature = {
  type: 'Feature';
  properties: Record<string, never>;
  geometry:
    | { type: 'Polygon'; coordinates: Array<Array<[number, number]>> }
    | { type: 'LineString'; coordinates: Array<[number, number]> }
    | { type: 'Point'; coordinates: [number, number] };
};

function buildAOIGeoJSONFeatureCollection(aoiVertices: Array<[number, number]>) {
  const features: AOIGeoJSONFeature[] = [];
  if (aoiVertices.length >= 3) {
    const closed = [...aoiVertices, aoiVertices[0]];
    features.push({
      type: 'Feature',
      properties: {},
      geometry: { type: 'Polygon', coordinates: [closed] },
    });
  } else if (aoiVertices.length === 2) {
    features.push({
      type: 'Feature',
      properties: {},
      geometry: { type: 'LineString', coordinates: aoiVertices },
    });
  }
  for (const v of aoiVertices) {
    features.push({
      type: 'Feature',
      properties: {},
      geometry: { type: 'Point', coordinates: v },
    });
  }
  return { type: 'FeatureCollection' as const, features };
}

export function computeViewportAOIRectangle(
  mapBounds: { getWest(): number; getSouth(): number; getEast(): number; getNorth(): number } | null,
  payloadBBox?: readonly number[] | null
): Array<[number, number]> {
  let minLon = -124.5;
  let minLat = 53.2;
  let maxLon = -121.5;
  let maxLat = 54.6;
  if (mapBounds) {
    const padLon = (mapBounds.getEast() - mapBounds.getWest()) * 0.15;
    const padLat = (mapBounds.getNorth() - mapBounds.getSouth()) * 0.15;
    minLon = Math.round((mapBounds.getWest() + padLon) * 1e5) / 1e5;
    maxLon = Math.round((mapBounds.getEast() - padLon) * 1e5) / 1e5;
    minLat = Math.round((mapBounds.getSouth() + padLat) * 1e5) / 1e5;
    maxLat = Math.round((mapBounds.getNorth() - padLat) * 1e5) / 1e5;
  } else if (payloadBBox && payloadBBox.length >= 4) {
    [minLon, minLat, maxLon, maxLat] = payloadBBox;
  }
  return [
    [minLon, minLat],
    [maxLon, minLat],
    [maxLon, maxLat],
    [minLon, maxLat],
  ];
}

export function isAbsoluteFilesystemPath(rawPath: string): boolean {
  const trimmed = rawPath.trim();
  if (!trimmed) return false;
  return trimmed.startsWith('/') || /^[A-Za-z]:[\\/]/.test(trimmed) || trimmed.startsWith('\\\\');
}

function resolveProjectExportsDir(projectPath?: string | null): { dir: string; sep: '/' | '\\' } | null {
  const raw = typeof projectPath === 'string' ? projectPath.trim() : '';
  if (!raw || !isAbsoluteFilesystemPath(raw)) return null;
  const sep: '/' | '\\' = raw.includes('\\') && !raw.includes('/') ? '\\' : '/';
  const cleaned = raw.replace(/[\\/]+$/, '');
  const lastSep = Math.max(cleaned.lastIndexOf('/'), cleaned.lastIndexOf('\\'));
  if (lastSep <= 0) return null;
  const parentDir = cleaned.slice(0, lastSep);
  if (!isAbsoluteFilesystemPath(parentDir)) return null;
  const parentSep = Math.max(parentDir.lastIndexOf('/'), parentDir.lastIndexOf('\\'));
  const parentBase = parentSep >= 0 ? parentDir.slice(parentSep + 1) : parentDir;
  if (parentBase.toLowerCase() === 'projects' && parentSep > 0) {
    const dataDir = parentDir.slice(0, parentSep);
    if (isAbsoluteFilesystemPath(dataDir)) {
      return { dir: `${dataDir}${sep}exports`, sep };
    }
  }
  return { dir: `${parentDir}${sep}exports`, sep };
}

export function buildDefaultGeoPackageExportPath(project: string, projectPath?: string | null): string {
  const safeProj = (project || 'vpro').replace(/[^A-Za-z0-9_-]+/g, '_') || 'vpro';
  const fileName = `${safeProj}_plots.gpkg`;
  const exportsDir = resolveProjectExportsDir(projectPath);
  if (!exportsDir) return '';
  return `${exportsDir.dir}${exportsDir.sep}${fileName}`;
}

export function resolveGeoPackageDestinationPath(
  rawDest: string,
  project: string,
  projectPath?: string | null
): string | null {
  const trimmed = rawDest.trim();
  if (!trimmed) return null;
  const withExt = trimmed.toLowerCase().endsWith('.gpkg') ? trimmed : `${trimmed}.gpkg`;
  if (isAbsoluteFilesystemPath(withExt)) {
    return withExt;
  }
  const segments = withExt.split(/[\\/]+/).filter(Boolean);
  if (segments.length === 0 || segments.some((s) => s === '.' || s === '..')) {
    return null;
  }
  const exportsDir = resolveProjectExportsDir(projectPath);
  if (!exportsDir) {
    return null;
  }
  return `${exportsDir.dir}${exportsDir.sep}${segments.join(exportsDir.sep)}`;
}

function hasInvalidOrDiagnosticQACoordinates(row: {
  diagnostics?: string[] | null;
  latitude?: number | null;
  longitude?: number | null;
}): boolean {
  if (Array.isArray(row.diagnostics) && row.diagnostics.length > 0) {
    return true;
  }
  const lat = row.latitude;
  const lon = row.longitude;
  if (lat != null && lon != null) {
    if (
      !Number.isFinite(lat) ||
      !Number.isFinite(lon) ||
      (lat === 0 && lon === 0) ||
      lat < -90 ||
      lat > 90 ||
      lon < -180 ||
      lon > 180
    ) {
      return true;
    }
  } else if ((lat != null) !== (lon != null)) {
    return true;
  }
  return false;
}

export function initQASelectedPlots(
  rows: Array<{
    plotNumber: string;
    bgcMismatch?: boolean;
    divergenceFlagged?: boolean;
    longitudeSignFlipped?: boolean;
    storedGisBgc?: string;
    suggestedGisBgc?: string;
  }>
): Record<string, boolean> {
  const nextSelected: Record<string, boolean> = {};
  for (const r of rows) {
    if (r.bgcMismatch || r.divergenceFlagged || r.longitudeSignFlipped || (!r.storedGisBgc && !!r.suggestedGisBgc)) {
      nextSelected[r.plotNumber] = true;
    }
  }
  return nextSelected;
}

export function filterSpatialQARows<
  T extends {
    bgcMismatch?: boolean;
    divergenceFlagged?: boolean;
    longitudeSignFlipped?: boolean;
    elevationFlagged?: boolean;
    storedGisBgc?: string;
    suggestedGisBgc?: string;
    diagnostics?: string[] | null;
    latitude?: number | null;
    longitude?: number | null;
  },
>(rows: T[], onlyIssues: boolean): T[] {
  if (!onlyIssues) return rows;
  return rows.filter(
    (r) =>
      r.bgcMismatch ||
      r.divergenceFlagged ||
      r.longitudeSignFlipped ||
      r.elevationFlagged ||
      (!r.storedGisBgc && !!r.suggestedGisBgc) ||
      hasInvalidOrDiagnosticQACoordinates(r)
  );
}

export interface MapAOIHost {
  getSource(id: string): object | undefined;
  isStyleLoaded(): boolean | void;
  addSource(id: string, source: SourceSpecification): unknown;
  addLayer(layer: LayerSpecification): unknown;
}

export function syncMapAOIOverlay(
  mapInstance: MapAOIHost | null | undefined,
  aoiVertices: Array<[number, number]>
): void {
  if (!mapInstance) return;
  const fc = buildAOIGeoJSONFeatureCollection(aoiVertices);
  const src = mapInstance.getSource('vpro-aoi-overlay') as { setData?: (data: unknown) => void } | undefined;
  if (src) {
    src.setData?.(fc);
    return;
  }
  if (!mapInstance.isStyleLoaded()) return;
  mapInstance.addSource('vpro-aoi-overlay', { type: 'geojson', data: fc });
  mapInstance.addLayer({
    id: 'vpro-aoi-fill',
    type: 'fill',
    source: 'vpro-aoi-overlay',
    filter: ['==', '$type', 'Polygon'],
    paint: { 'fill-color': '#FCBA19', 'fill-opacity': 0.22 },
  });
  mapInstance.addLayer({
    id: 'vpro-aoi-stroke',
    type: 'line',
    source: 'vpro-aoi-overlay',
    paint: { 'line-color': '#FCBA19', 'line-width': 2.5 },
  });
  mapInstance.addLayer({
    id: 'vpro-aoi-vertices',
    type: 'circle',
    source: 'vpro-aoi-overlay',
    filter: ['==', '$type', 'Point'],
    paint: {
      'circle-radius': 5,
      'circle-color': '#003366',
      'circle-stroke-color': '#FCBA19',
      'circle-stroke-width': 2,
    },
  });
}

const DEFAULT_BC_BOUNDS: [[number, number], [number, number]] = [
  [-139.06, 48.2],
  [-114.05, 60.0],
];

function computeShortestLongitudeArc(lons: number[]): [number, number] {
  const sorted = [...lons].sort((a, b) => a - b);
  if (sorted.length === 1) return [sorted[0], sorted[0]];
  let maxGap = -1;
  let gapAfterIdx = sorted.length - 1;
  for (let i = 0; i < sorted.length - 1; i++) {
    const gap = sorted[i + 1] - sorted[i];
    if (gap > maxGap) {
      maxGap = gap;
      gapAfterIdx = i;
    }
  }
  const wrapGap = sorted[0] + 360 - sorted[sorted.length - 1];
  if (wrapGap >= maxGap) {
    return [sorted[0], sorted[sorted.length - 1]];
  }
  const west = sorted[gapAfterIdx + 1];
  const east = sorted[gapAfterIdx] + 360;
  return [west, east];
}

export function computeMapFitBounds(
  payload: SpatialWorkbenchPayload | null
):
  | { kind: 'jump'; center: [number, number]; zoom: number }
  | { kind: 'bounds'; bounds: [[number, number], [number, number]] }
  | null {
  if (!payload || payload.plottableCount === 0) return null;

  const lons = payload.geoArrow?.lon;
  const lats = payload.geoArrow?.lat;
  const n = payload.geoArrow?.count ?? 0;

  if (n > 0 && Array.isArray(lons) && Array.isArray(lats) && lons.length >= n && lats.length >= n) {
    const regionalLons: number[] = [];
    const regionalLats: number[] = [];
    const allLons: number[] = [];
    const allLats: number[] = [];
    for (let i = 0; i < n; i++) {
      const lon = lons[i];
      const lat = lats[i];
      if (!Number.isFinite(lon) || !Number.isFinite(lat)) continue;
      allLons.push(lon);
      allLats.push(lat);
      if (lat >= 45.0 && lat <= 85.0 && lon >= -170.0 && lon <= -100.0) {
        regionalLons.push(lon);
        regionalLats.push(lat);
      }
    }
    const useLons = regionalLons.length > 0 ? regionalLons : allLons;
    const useLats = regionalLats.length > 0 ? regionalLats : allLats;
    if (useLons.length > 0) {
      const [westLon, eastLon] = computeShortestLongitudeArc(useLons);
      let minLat = Infinity;
      let maxLat = -Infinity;
      for (const lat of useLats) {
        if (lat < minLat) minLat = lat;
        if (lat > maxLat) maxLat = lat;
      }
      const lonSpan = eastLon - westLon;
      const latSpan = maxLat - minLat;
      if (lonSpan < 0.005 && latSpan < 0.005) {
        const normCenterLon = westLon > 180 ? westLon - 360 : westLon;
        return { kind: 'jump', center: [normCenterLon, minLat], zoom: 9.5 };
      }
      if (lonSpan > 70 || latSpan > 50) {
        return { kind: 'bounds', bounds: DEFAULT_BC_BOUNDS };
      }
      return {
        kind: 'bounds',
        bounds: [
          [westLon, minLat],
          [eastLon, maxLat],
        ],
      };
    }
  }

  if (!Array.isArray(payload.boundingBox) || payload.boundingBox.length < 4) return null;
  let [minLon, minLat, maxLon, maxLat] = payload.boundingBox;
  if (!Number.isFinite(minLon) || !Number.isFinite(maxLon) || !Number.isFinite(minLat) || !Number.isFinite(maxLat)) {
    return null;
  }
  const directSpan = Math.abs(maxLon - minLon);
  const antimeridianSpan = minLon + 360 - maxLon;
  if (directSpan > 180 && antimeridianSpan > 0 && antimeridianSpan <= 60) {
    const west = maxLon;
    const east = minLon + 360;
    if (antimeridianSpan < 0.005 && Math.abs(maxLat - minLat) < 0.005) {
      return { kind: 'jump', center: [west > 180 ? west - 360 : west, minLat], zoom: 9.5 };
    }
    return {
      kind: 'bounds',
      bounds: [
        [west, minLat],
        [east, maxLat],
      ],
    };
  }
  if (directSpan > 70 || Math.abs(maxLat - minLat) > 50) {
    return { kind: 'bounds', bounds: DEFAULT_BC_BOUNDS };
  }
  if (directSpan < 0.005 && Math.abs(maxLat - minLat) < 0.005) {
    return { kind: 'jump', center: [minLon, minLat], zoom: 9.5 };
  }
  return {
    kind: 'bounds',
    bounds: [
      [minLon, minLat],
      [maxLon, maxLat],
    ],
  };
}

export interface MapViewportHost {
  jumpTo(options: { center: [number, number]; zoom: number }): unknown;
  fitBounds(
    bounds: [[number, number], [number, number]],
    options?: { padding?: number; maxZoom?: number; duration?: number }
  ): unknown;
}

export function fitMapToPayloadBounds(
  mapInstance: MapViewportHost | null | undefined,
  payload: SpatialWorkbenchPayload | null
): void {
  if (!mapInstance) return;
  const target = computeMapFitBounds(payload);
  if (!target) return;
  if (target.kind === 'jump') {
    mapInstance.jumpTo({ center: target.center, zoom: target.zoom });
    return;
  }
  mapInstance.fitBounds(target.bounds, { padding: 48, maxZoom: 10, duration: 500 });
}

function buildSpatialDeckLayers<TLineLayer, TScatterLayer>(params: {
  LineLayerCtor: new (props: Record<string, unknown>) => TLineLayer;
  ScatterplotLayerCtor: new (props: Record<string, unknown>) => TScatterLayer;
  pts: WorkbenchPlotPoint[];
  matched: Set<string>;
  selPlotNum: string;
  showVectors: boolean;
  discrepancySegments: DiscrepancyVectorSegment[];
  aoiPreviewTrigger: unknown;
  onPinClick: (pt: WorkbenchPlotPoint) => void;
}): Array<TLineLayer | TScatterLayer> {
  const {
    LineLayerCtor,
    ScatterplotLayerCtor,
    pts,
    matched,
    selPlotNum,
    showVectors,
    discrepancySegments,
    aoiPreviewTrigger,
    onPinClick,
  } = params;
  const layers: Array<TLineLayer | TScatterLayer> = [];
  if (showVectors && discrepancySegments.length > 0) {
    layers.push(
      new LineLayerCtor({
        id: 'vpro-utm-dd-vectors',
        data: discrepancySegments,
        getSourcePosition: (d: DiscrepancyVectorSegment) => d.sourcePosition,
        getTargetPosition: (d: DiscrepancyVectorSegment) => d.targetPosition,
        getColor: (d: DiscrepancyVectorSegment) => (d.flagged ? [216, 41, 47, 220] : [252, 186, 25, 200]),
        getWidth: 2.5,
        widthUnits: 'pixels',
      }),
      new ScatterplotLayerCtor({
        id: 'vpro-utm-derived-pins',
        data: discrepancySegments,
        getPosition: (d: DiscrepancyVectorSegment) => d.targetPosition,
        getFillColor: [252, 186, 25, 220],
        getLineColor: [0, 51, 102, 255],
        stroked: true,
        lineWidthMinPixels: 1.5,
        getRadius: 4.5,
        radiusUnits: 'pixels',
      })
    );
  }
  layers.push(
    new ScatterplotLayerCtor({
      id: 'vpro-plot-pins',
      data: pts,
      pickable: true,
      getPosition: (d: WorkbenchPlotPoint) => [d.lon, d.lat],
      getRadius: (d: WorkbenchPlotPoint) => (d.plotNumber === selPlotNum ? 9 : matched.has(d.plotNumber) ? 7.5 : 5.5),
      radiusUnits: 'pixels',
      stroked: true,
      lineWidthMinPixels: 1.5,
      getLineColor: (d: WorkbenchPlotPoint) =>
        d.plotNumber === selPlotNum ? [252, 186, 25, 255] : [255, 255, 255, 235],
      getFillColor: (d: WorkbenchPlotPoint) => {
        if (matched.has(d.plotNumber)) return [252, 186, 25, 245];
        if (d.divergenceFlagged || d.bgcMismatch) return [216, 41, 47, 235];
        return [46, 133, 64, 230];
      },
      updateTriggers: {
        getRadius: [selPlotNum, aoiPreviewTrigger],
        getLineColor: [selPlotNum],
        getFillColor: [aoiPreviewTrigger],
      },
      onClick: (info: { object?: WorkbenchPlotPoint }) => {
        if (info.object) onPinClick(info.object);
      },
    })
  );
  return layers;
}

export function filterCoordinateDiagnosticRows<
  TRow extends {
    plotNumber: string;
    bgcMismatch?: boolean;
    diagnostics?: string[] | null;
    latitude?: number | null;
    longitude?: number | null;
    divergenceFlagged?: boolean;
    longitudeSignFlipped?: boolean;
  },
>(rows: readonly TRow[] | null | undefined): TRow[] {
  return (rows ?? []).filter(
    (r) =>
      hasInvalidOrDiagnosticQACoordinates(r) &&
      !(r.bgcMismatch && (r.diagnostics?.length ?? 0) === 1 && (r.diagnostics?.[0] ?? '').startsWith('Field BGC'))
  );
}

export function computeViewportFilterBounds(
  mapInstance: {
    getBounds(): { getWest(): number; getSouth(): number; getEast(): number; getNorth(): number };
  } | null,
  boundingBox: readonly number[] | null | undefined
): [number, number, number, number] {
  if (mapInstance) {
    const b = mapInstance.getBounds();
    return [b.getWest(), b.getSouth(), b.getEast(), b.getNorth()];
  }
  if (boundingBox && boundingBox.length >= 4) {
    return [boundingBox[0], boundingBox[1], boundingBox[2], boundingBox[3]];
  }
  return [-140, 47, -113, 61];
}

function bindGeospatialMapListeners(opts: {
  map: {
    on(event: string, listener: (evt?: unknown) => void): unknown;
    setStyle(style: StyleSpecification): unknown;
  };
  isAlive: () => boolean;
  onMapLoad: () => void;
  onMoveEnd: () => void;
  onMapError: (evt: unknown) => void;
  onMapClick: (lngLat: { lng: number; lat: number }) => void;
}): void {
  opts.map.on('load', () => {
    if (opts.isAlive()) opts.onMapLoad();
  });
  opts.map.on('moveend', () => {
    if (opts.isAlive()) opts.onMoveEnd();
  });
  opts.map.on('error', (evt) => {
    if (opts.isAlive()) opts.onMapError(evt);
  });
  opts.map.on('click', (evt) => {
    if (!opts.isAlive()) return;
    const rec = evt as { lngLat?: { lng: number; lat: number } } | undefined;
    if (rec?.lngLat) opts.onMapClick(rec.lngLat);
  });
}

let maplibreWorkerInitialized = false;
let pmtilesProtocolInitialized = false;

export function ensureMapLibrePMTilesProtocol<THandler>(
  setWorkerUrlFn: ((url: string) => void) | undefined,
  workerUrl: string,
  addProtocolFn: (scheme: string, handler: THandler) => void,
  ProtocolCtor: new () => { tile: THandler }
): void {
  if (!maplibreWorkerInitialized) {
    if (typeof setWorkerUrlFn === 'function' && workerUrl) setWorkerUrlFn(workerUrl);
    maplibreWorkerInitialized = true;
  }
  if (pmtilesProtocolInitialized) return;
  try {
    const protocol = new ProtocolCtor();
    addProtocolFn('pmtiles', protocol.tile);
  } catch {
    // Ignore duplicate protocol registration
  }
  pmtilesProtocolInitialized = true;
}

function handleGeospatialMapError(opts: {
  evt: unknown;
  bcOpenMapsWMS: boolean;
  wmsOfflineWarning: string;
  pmtilesArchiveWarning: string;
  pmtilesGraticuleFallback: boolean;
  project: string;
  manifest: PMTilesManifest | null | undefined;
  visibility: MapLayerVisibility;
  setWmsWarn: (warn: string) => void;
  setPmWarn: (warn: string) => void;
  enableGraticuleFallback: (style: StyleSpecification) => void;
  warnToast: (title: string, msg: string) => void;
}): void {
  const online = typeof navigator !== 'undefined' ? navigator.onLine : undefined;
  const wmsWarn = classifyWMSMapError(opts.evt, opts.bcOpenMapsWMS, online);
  if (wmsWarn) {
    if (wmsWarn !== opts.wmsOfflineWarning) opts.warnToast('BC OpenMaps WMS unavailable', wmsWarn);
    opts.setWmsWarn(wmsWarn);
    return;
  }
  const pmWarn = classifyPMTilesMapError(opts.evt);
  if (!pmWarn) return;
  if (pmWarn !== opts.pmtilesArchiveWarning) opts.warnToast('Local map archive unreadable', pmWarn);
  opts.setPmWarn(pmWarn);
  if (!opts.pmtilesGraticuleFallback) {
    opts.enableGraticuleFallback(
      buildMapLibreGeospatialStyle(opts.manifest, opts.visibility, { forceGraticuleFallback: true })
    );
  }
}

export function createGeospatialMapInstance<TMap, TOverlay>(
  ctors: [
    new (opts: Record<string, unknown>) => TMap & {
      addControl(ctrl: unknown, pos?: string): unknown;
      on(event: string, cb: (evt?: unknown) => void): unknown;
      setStyle(style: StyleSpecification): unknown;
    },
    new (opts: { visualizePitch: boolean }) => unknown,
    new (opts: { maxWidth: number; unit: 'metric' }) => unknown,
    new (opts: { interleaved: boolean; layers: never[] }) => TOverlay,
  ],
  target: [HTMLElement, StyleSpecification],
  hooks: {
    isAlive: () => boolean;
    onLoad: () => void;
    onMoveEnd: () => void;
    onError: (map: { setStyle(s: StyleSpecification): unknown }, evt: unknown) => void;
    onClick: (pt: [number, number]) => void;
  }
): { map: TMap; overlay: TOverlay } {
  const [MapCtor, NavCtrlCtor, ScaleCtrlCtor, OverlayCtor] = ctors;
  const [container, style] = target;
  const { longitude, latitude, zoom } = DEFAULT_BC_VIEW_STATE;
  const map = new MapCtor({ container, style, center: [longitude, latitude], zoom, pitch: 0, bearing: 0 });
  map.addControl(new NavCtrlCtor({ visualizePitch: true }), 'top-right');
  map.addControl(new ScaleCtrlCtor({ maxWidth: 140, unit: 'metric' }), 'bottom-left');
  const overlay = new OverlayCtor({ interleaved: false, layers: [] });
  map.addControl(overlay);
  bindGeospatialMapListeners({
    map,
    isAlive: hooks.isAlive,
    onMapLoad: hooks.onLoad,
    onMoveEnd: hooks.onMoveEnd,
    onMapError: (evt) => hooks.onError(map, evt),
    onMapClick: (ll) => hooks.onClick([Math.round(ll.lng * 1e6) / 1e6, Math.round(ll.lat * 1e6) / 1e6]),
  });
  return { map, overlay };
}

export function routeGeospatialMapError(
  evt: unknown,
  state: [boolean, string, string, boolean],
  manifest: PMTilesManifest | null | undefined,
  visibility: MapLayerVisibility,
  apply: (wmsWarn: string | null, pmWarn: string | null, fallbackStyle: StyleSpecification | null) => void,
  warnToast: (title: string, msg: string) => void
): void {
  const [bcOpenMapsWMS, wmsOfflineWarning, pmtilesArchiveWarning, pmtilesGraticuleFallback] = state;
  handleGeospatialMapError({
    evt,
    bcOpenMapsWMS,
    wmsOfflineWarning,
    pmtilesArchiveWarning,
    pmtilesGraticuleFallback,
    project: '',
    manifest,
    visibility,
    setWmsWarn: (w) => apply(w, null, null),
    setPmWarn: (w) => apply(null, w, null),
    enableGraticuleFallback: (s) => apply(null, null, s),
    warnToast,
  });
}

export function makeWorkbenchDeckLayers<TLineLayer, TScatterLayer>(
  LineLayerCtor: new (props: Record<string, unknown>) => TLineLayer,
  ScatterplotLayerCtor: new (props: Record<string, unknown>) => TScatterLayer,
  pts: WorkbenchPlotPoint[],
  matched: Set<string>,
  selPlotNum: string,
  showVectors: boolean,
  discrepancySegments: DiscrepancyVectorSegment[],
  aoiPreviewTrigger: unknown,
  onPinClick: (pt: WorkbenchPlotPoint) => void
): Array<TLineLayer | TScatterLayer> {
  return buildSpatialDeckLayers({
    LineLayerCtor,
    ScatterplotLayerCtor,
    pts,
    matched,
    selPlotNum,
    showVectors,
    discrepancySegments,
    aoiPreviewTrigger,
    onPinClick,
  });
}

export async function fetchAOIPolygonPreview<TResult>(
  contextId: string,
  ringSnapshot: Array<[number, number]>,
  plotPoints: readonly WorkbenchPlotPoint[],
  zoneFilter: string,
  selectRpc: (
    ctxId: string,
    req: { polygon: Array<[number, number]>; rings: number[][][]; zone: string }
  ) => Promise<TResult>
): Promise<{ res?: TResult; suggested: string; cause: unknown }> {
  const localMatches = plotPoints.filter((p) => pointInPolygonRing(p.lon, p.lat, ringSnapshot));
  const suggested = localMatches[0]?.gisBgc ? `${localMatches[0].gisBgc}/01` : '';
  try {
    const res = await selectRpc(contextId, { polygon: ringSnapshot, rings: [], zone: zoneFilter.trim() });
    return { res, suggested, cause: null };
  } catch (cause) {
    return { suggested: '', cause };
  }
}

export function disposeGeospatialMap(
  mapInstance: { removeControl(ctrl: never): void; remove(): void } | null,
  deckOverlay: unknown
): void {
  if (deckOverlay && mapInstance) {
    try {
      mapInstance.removeControl(deckOverlay as never);
    } catch {
      // Ignore already-detached control
    }
  }
  if (mapInstance) mapInstance.remove();
}

export function bindWindowConnectivityListeners(onOffline: () => void, onOnline: () => void): () => void {
  if (typeof window === 'undefined') return () => {};
  window.addEventListener('offline', onOffline);
  window.addEventListener('online', onOnline);
  return () => {
    window.removeEventListener('offline', onOffline);
    window.removeEventListener('online', onOnline);
  };
}
