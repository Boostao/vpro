import type { CoordinateParts } from '../../bindings/github.com/boostao/vpro/app';
import { trackIfCancellable, type ReadRequests } from '../shared/readRequests';
import type { CoordinateAPI, CoordinateAxis, CoordinateDisplayMode } from './coordinateEditor';

export type CoordinateHelperMode = 'dm' | 'dms' | 'utm';
export type CoordinateHemisphere = 'N' | 'S' | 'E' | 'W';

export interface SpatialCoordinateRuntimeService {
  GetCoordinateMode(): Promise<string>;
  SetCoordinateMode(mode: string): Promise<void>;
  DecomposeCoordinate(value: number | null, mode: string): Promise<CoordinateParts>;
  ConvertCoordinate(axis: string, mode: string, parts: CoordinateParts): Promise<number | null>;
  ProjectNAD83UTMToLatLon(
    zone: number,
    easting: number,
    northing: number
  ): Promise<{ latitude: number; longitude: number }>;
}

export interface SpatialCoordinateModeMap {
  CoordinateModeDD: string;
  CoordinateModeDM: string;
  CoordinateModeDMS: string;
}

function runRead<T>(reads: ReadRequests | undefined, request: PromiseLike<T>): Promise<T> {
  return reads ? trackIfCancellable(reads, request) : Promise.resolve(request);
}

export function createSpatialCoordinatePort(
  service: Pick<
    SpatialCoordinateRuntimeService,
    'GetCoordinateMode' | 'SetCoordinateMode' | 'DecomposeCoordinate' | 'ConvertCoordinate'
  >,
  modes: SpatialCoordinateModeMap,
  reads?: ReadRequests
): CoordinateAPI {
  const serviceModes: Record<CoordinateDisplayMode, string> = {
    dd: modes.CoordinateModeDD,
    dm: modes.CoordinateModeDM,
    dms: modes.CoordinateModeDMS,
  };
  return {
    getMode: () => runRead(reads, service.GetCoordinateMode()),
    setMode: (value) => service.SetCoordinateMode(serviceModes[value]),
    decompose: (value, valueMode) => runRead(reads, service.DecomposeCoordinate(value, serviceModes[valueMode])),
    convert: (axis, valueMode, parts) =>
      runRead(reads, service.ConvertCoordinate(axis, serviceModes[valueMode], parts)),
  };
}

export function parseNorthernNAD83UTMZone(rawZone: string | number): number {
  const trimmed = String(rawZone ?? '').trim();
  const zoneMatch = /^0*([0-9]{1,2})[Nn]?$/.exec(trimmed);
  const zoneNum = zoneMatch ? Number.parseInt(zoneMatch[1], 10) : Number.NaN;
  if (!Number.isInteger(zoneNum) || zoneNum < 7 || zoneNum > 12) {
    throw new Error(`Invalid NAD83 UTM zone "${trimmed}" (expected Northern Hemisphere zone 7–12, such as 9 or 10N).`);
  }
  return zoneNum;
}

export async function projectNAD83UTMZoneToLatLon(
  service: Pick<SpatialCoordinateRuntimeService, 'ProjectNAD83UTMToLatLon'>,
  rawZone: string | number,
  easting: number,
  northing: number,
  strictNorthernZone = true,
  reads?: ReadRequests
): Promise<{ zone: number; latitude: number; longitude: number; easting: number; northing: number }> {
  const zone = strictNorthernZone
    ? parseNorthernNAD83UTMZone(rawZone)
    : Number.parseInt(String(rawZone ?? '').trim(), 10);
  if (!Number.isFinite(zone) || !Number.isFinite(easting) || !Number.isFinite(northing)) {
    throw new Error('Enter valid NAD83 UTM Zone, Easting, and Northing.');
  }
  const projected = await runRead(reads, service.ProjectNAD83UTMToLatLon(zone, easting, northing));
  return {
    zone,
    latitude: Math.round(projected.latitude * 1e6) / 1e6,
    longitude: Math.round(projected.longitude * 1e6) / 1e6,
    easting: Math.round(easting * 10) / 10,
    northing: Math.round(northing * 10) / 10,
  };
}

export async function convertDMOrDMSToDecimalDegrees(
  service: Pick<SpatialCoordinateRuntimeService, 'ConvertCoordinate'>,
  modes: Pick<SpatialCoordinateModeMap, 'CoordinateModeDM' | 'CoordinateModeDMS'>,
  axis: CoordinateAxis,
  helperMode: 'dm' | 'dms',
  rawDeg: string,
  rawMin: string,
  rawSec: string,
  hemisphere: CoordinateHemisphere,
  reads?: ReadRequests
): Promise<number> {
  const degrees = rawDeg.trim() === '' ? null : Number(rawDeg);
  const minutes = rawMin.trim() === '' ? null : Number(rawMin);
  const seconds = helperMode === 'dms' ? (rawSec.trim() === '' ? null : Number(rawSec)) : null;
  const negative = hemisphere === 'S' || hemisphere === 'W';
  const mode = helperMode === 'dms' ? modes.CoordinateModeDMS : modes.CoordinateModeDM;
  const dd = await runRead(reads, service.ConvertCoordinate(axis, mode, { degrees, minutes, seconds, negative }));
  if (dd === null || !Number.isFinite(dd)) {
    throw new Error('Coordinate conversion returned empty result.');
  }
  return dd;
}
