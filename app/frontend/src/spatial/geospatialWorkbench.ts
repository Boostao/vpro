import type {
  PMTilesManifest,
  SpatialWorkbenchPayload,
} from '../../bindings/github.com/boostao/vpro/app';

export type SpatialGeoArrowColumns = SpatialWorkbenchPayload['geoArrow'];


export {
  buildWGSLSpatialFilterShader,
  detectSpatialComputeBackend,
  executeCPUSpatialFilterKernel,
  executeSpatialFilterKernel,
} from './spatialCompute';
export type {
  SpatialComputeBackendKind,
  SpatialComputeBackendInfo,
  SpatialFilterKernelResult,
} from './spatialCompute';
export {
  FLATGEOBUF_MAGIC_V3,
  decodeFlatGeobufPoints,
  pointInPolygonRing,
} from './spatialFlatGeobuf';
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

export const DEFAULT_BC_VIEW_STATE = {
  longitude: -124.8,
  latitude: 54.2,
  zoom: 4.8,
  pitch: 0,
  bearing: 0,
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

export function buildBECZoneMatchExpression(): any[] {
  const expr: any[] = ['match', ['get', 'ZONE']];
  for (const [zone, hex] of Object.entries(BEC_ZONE_PALETTE)) {
    expr.push(zone, hex);
  }
  expr.push('#474543');
  return expr;
}

/**
 * Builds the offline-first MapLibre GL JS v6 style specification backed by local PMTiles
 * byte-range sources and optional BC OpenMaps WMS orthoimagery.
 */
export function buildMapLibreGeospatialStyle(
  manifest: PMTilesManifest | null | undefined,
  visibility: MapLayerVisibility
): Record<string, any> {
  const bgcArchive = manifest?.archives?.['bc-bgc-v13.pmtiles'];
  const adminArchive = manifest?.archives?.['bc-admin-ecosections-districts.pmtiles'];
  const bgcMaxZoom = bgcArchive?.maxZoom && bgcArchive.maxZoom > 0 ? bgcArchive.maxZoom : 6;
  const adminMaxZoom = adminArchive?.maxZoom && adminArchive.maxZoom > 0 ? adminArchive.maxZoom : 6;

  const sources: Record<string, any> = {
    bc_bgc_pmtiles: {
      type: 'vector',
      url: 'pmtiles:///maps/bc-bgc-v13.pmtiles',
      minzoom: 3,
      maxzoom: bgcMaxZoom,
      attribution: 'BC Ministry of Forests BEC v13',
    },
    bc_admin_pmtiles: {
      type: 'vector',
      url: 'pmtiles:///maps/bc-admin-ecosections-districts.pmtiles',
      minzoom: 3,
      maxzoom: adminMaxZoom,
      attribution: 'GeoBC Ecosections & NR Districts',
    },
  };

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

  const layers: Record<string, any>[] = [
    {
      id: 'vpro-ocean-background',
      type: 'background',
      paint: {
        'background-color': visibility.hillshade3D ? '#002244' : '#F2F2F2',
      },
    },
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
    },
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
    },
  ];

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

export function summarizeArchiveResolution(payload: SpatialWorkbenchPayload | null): string {
  if (!payload?.manifest?.archives) return 'Resolving local PMTiles archives...';
  const bgc = payload.manifest.archives['bc-bgc-v13.pmtiles'];
  if (!bgc) return 'Embedded Overview PMTiles (z3..6)';
  if (bgc.fullResolution) {
    return `Full-Res Provincial PMTiles (z${bgc.minZoom}..${bgc.maxZoom})`;
  }
  return `Embedded Overview Fallback (z${bgc.minZoom}..${bgc.maxZoom})`;
}

export function classifyWMSMapError(
  event: unknown,
  wmsEnabled: boolean,
  online?: boolean
): string | null {
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
    return 'BC OpenMaps WMS tile request failed (offline or remote service unreachable). Offline PMTiles vector layers remain active.';
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

export function buildAOIGeoJSONFeatureCollection(aoiVertices: Array<[number, number]>) {
  const features: any[] = [];
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
    if (
      r.bgcMismatch ||
      r.divergenceFlagged ||
      r.longitudeSignFlipped ||
      (!r.storedGisBgc && !!r.suggestedGisBgc)
    ) {
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
  },
>(rows: T[], onlyIssues: boolean): T[] {
  if (!onlyIssues) return rows;
  return rows.filter(
    (r) =>
      r.bgcMismatch ||
      r.divergenceFlagged ||
      r.longitudeSignFlipped ||
      r.elevationFlagged ||
      (!r.storedGisBgc && !!r.suggestedGisBgc)
  );
}

export function syncMapAOIOverlay(
  mapInstance: any,
  aoiVertices: Array<[number, number]>
): void {
  if (!mapInstance) return;
  const fc = buildAOIGeoJSONFeatureCollection(aoiVertices);
  const src = mapInstance.getSource('vpro-aoi-overlay');
  if (src) {
    src.setData(fc);
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

export function fitMapToPayloadBounds(
  mapInstance: any,
  payload: SpatialWorkbenchPayload | null
): void {
  if (!mapInstance || !payload || payload.plottableCount === 0) return;
  const [minLon, minLat, maxLon, maxLat] = payload.boundingBox;
  if (!Number.isFinite(minLon) || !Number.isFinite(maxLon)) return;
  if (Math.abs(maxLon - minLon) < 0.005 && Math.abs(maxLat - minLat) < 0.005) {
    mapInstance.jumpTo({ center: [minLon, minLat], zoom: 9.5 });
    return;
  }
  mapInstance.fitBounds(
    [
      [minLon, minLat],
      [maxLon, maxLat],
    ],
    { padding: 48, maxZoom: 10, duration: 500 }
  );
}

export function buildSpatialDeckLayers(params: {
  LineLayerCtor: any;
  ScatterplotLayerCtor: any;
  pts: WorkbenchPlotPoint[];
  matched: Set<string>;
  selPlotNum: string;
  showVectors: boolean;
  discrepancySegments: DiscrepancyVectorSegment[];
  aoiPreviewTrigger: unknown;
  onPinClick: (pt: WorkbenchPlotPoint) => void;
}): any[] {
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
  const layers: any[] = [];
  if (showVectors && discrepancySegments.length > 0) {
    layers.push(
      new LineLayerCtor({
        id: 'vpro-utm-dd-vectors',
        data: discrepancySegments,
        getSourcePosition: (d: DiscrepancyVectorSegment) => d.sourcePosition,
        getTargetPosition: (d: DiscrepancyVectorSegment) => d.targetPosition,
        getColor: (d: DiscrepancyVectorSegment) =>
          d.flagged ? [216, 41, 47, 220] : [252, 186, 25, 200],
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
      getRadius: (d: WorkbenchPlotPoint) =>
        d.plotNumber === selPlotNum ? 9 : matched.has(d.plotNumber) ? 7.5 : 5.5,
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
