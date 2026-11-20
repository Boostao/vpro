import type {
  AuditRestoreAction,
  FS882Header,
  HumusRecord,
  MineralRecord,
  OtherRecord,
  VegRecord,
} from '../../bindings/github.com/boostao/vpro/app';
import { formatError } from '../shared/readRequests';
import type { SIVIHeightSession } from './siviHeightSession';
import type { SIVICoverSession } from './siviCoverSession';
import type { SIVICombinedSession } from './siviCombinedSession';
import type { SIVICollectedSession } from './siviCollectedSession';
import type { SIVISpeciesSession } from './siviSpeciesSession';
import type { SIVIIdentitySession } from './siviIdentitySession';

export type FS882ChildKind = 'Veg' | 'Humus' | 'Mineral' | 'Other';

export type FS882ChildCapabilities = Record<FS882ChildKind, Record<string, boolean | undefined>>;

export function toRecord(value: object): Record<string, unknown> {
  return { ...value };
}

export const newHumusFields = {
  humusStructureDegree: null,
  humusStructureKind: null,
  mycelAbundance: null,
  fecalAbundance: null,
  rootsAbundance: null,
  rootsSize: null,
  vonPost: null,
};

export const newMineralFields = {
  pitDepthLimit: null,
  asp: null,
  percentCoarseFragsGravel: null,
  percentCoarseFragsCobbles: null,
  percentCoarseFragsStones: null,
  percentCoarseFragsTotal: null,
  percentCoarseFragsShape: null,
  rootsAbundance: null,
  rootsSize: null,
  mineralStructureClass: null,
  mineralStructureKind: null,
  mineralFormpH: null,
};

export const newOtherFields = {
  userItem1: null,
  userItem2: null,
  userItem3: null,
  userFlag1: null,
  userFlag2: null,
  userFlag3: null,
};

export const newVegetationFields = {
  height1: null,
  height2: null,
  height3: null,
  height4: null,
  height5: null,
  height6: null,
  ll: null,
  af: null,
  dc: null,
  ut: null,
  vi: null,
  pv: null,
  pg: null,
  ffa: null,
  cultural1: null,
  cultural2: null,
  other1: null,
  other2: null,
};

export function newEmptyFS882Draft(): FS882Header {
  return {
    plotNumber: '',
    projectId: null,
    surveyor: null,
    date: null,
    fieldNo: null,
    generalLocation: null,
    mapSheet: null,
    utmZone: null,
    easting: null,
    northing: null,
    accuracy: null,
    plotRepresenting: null,
    siteSeries: null,
    transition: null,
    mapUnit: null,
    moistureRegime: null,
    nutrientRegime: null,
    successional: null,
    structuralStage: null,
    standAge: null,
    elevation: null,
    slope: null,
    aspect: null,
    mesoSlopePos: null,
    surfaceShape: null,
    microtopType: null,
    microtopSize: null,
    fieldNotes: null,
    officeNotes: null,
    startDate: null,
    activeLayerDepth: null,
    airPhotoNum: null,
    becSiteUnit: null,
    bedrockGeology1: null,
    bedrockGeology2: null,
    bedrockGeology3: null,
    coarseFragLith1: null,
    coarseFragLith2: null,
    coarseFragLith3: null,
    ecosection: null,
    enteredBy: null,
    exposure1: null,
    exposure2: null,
    fsRegionDistrict: null,
    floodingRegimeDur: null,
    floodingRegimeFreq: null,
    geoMorProSubSurf: null,
    geoMorProSurf: null,
    humusForm: null,
    humusFormPhase: null,
    humusThickness: null,
    hydroGeoSubSystem: null,
    hydroGeoSystem: null,
    latitude: null,
    longitude: null,
    photo: null,
    realmClass: null,
    rootRestrictingDepth: null,
    rootRestrictingType: null,
    rootZoneParticleSize: null,
    rootingDepth: null,
    seepageDepth: null,
    siteDisturbance1: null,
    siteDisturbance2: null,
    siteDisturbance3: null,
    sitePlotQuality: null,
    snowCoverRegime: null,
    soilClassGroup: null,
    soilClassSubGroup: null,
    soilDrainage: null,
    soilNotes: null,
    soilPlotQuality: null,
    soilSurveyor: null,
    speciesListComplete: null,
    strataCoverHerb: null,
    strataCoverMoss: null,
    strataCoverShrub: null,
    strataCoverTree: null,
    subZone: null,
    substrateBedRock: null,
    substrateDecWood: null,
    substrateMineralSoil: null,
    substrateOrganicMatter: null,
    substrateRocks: null,
    substrateWater: null,
    surfaceExpSubSurf: null,
    surfaceExpSurf: null,
    surficialMaterialSubSurf: null,
    surficialMaterialSurf: null,
    terrainTextureSubSurf: null,
    terrainTextureSurf: null,
    updatedFromCards: null,
    userSiteUnit: null,
    vegNotes: null,
    vegPlotQuality: null,
    vegSurveyor: null,
    waterSource: null,
    xCoord: null,
    yCoord: null,
    zone: null,
    locked: false,
  };
}

const treeColumns = [
  'cover1',
  'cover2',
  'cover3',
  'totalA',
  'cover4',
  'cover5',
  'cover5a',
  'cover5b',
  'cover5c',
  'totalB',
] as const;
const heightTreeColumns = [
  'cover1',
  'height1',
  'cover2',
  'height2',
  'cover3',
  'height3',
  'totalA',
  'cover4',
  'height4',
  'cover5',
  'height5',
  'totalB',
] as const;

function projectChildValues(
  record: object,
  kind: FS882ChildKind,
  childCapabilities: FS882ChildCapabilities
): Record<string, string | number | boolean | null | undefined> {
  const values: Record<string, string | number | boolean | null | undefined> = {};
  const stored = new Map(Object.entries(record));
  for (const [key, supported] of Object.entries(childCapabilities[kind] ?? {})) {
    if (supported) {
      const value = stored.get(key);
      if (value == null || typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
        values[key.toLowerCase()] = value ?? null;
      }
    }
  }
  return values;
}

export function projectSourceRows(
  name: string,
  lists: {
    vegList: VegRecord[];
    humusList: HumusRecord[];
    mineralList: MineralRecord[];
    otherList: OtherRecord[];
    childCapabilities: FS882ChildCapabilities;
  }
): Array<{ id: number; values: Record<string, string | number | boolean | null | undefined> }> {
  const { vegList, humusList, mineralList, otherList, childCapabilities } = lists;
  if (['SubVegAXL_BC', 'SubVegAXL', 'SubVegCXL', 'SubVegDXL', 'SubVegAhtXL', 'SubVegChtXL'].includes(name)) {
    const records = vegList.filter((row) =>
      name === 'SubVegAXL_BC' || name === 'SubVegAXL'
        ? treeColumns.some((key) => row[key] != null)
        : name === 'SubVegAhtXL'
          ? heightTreeColumns.some((key) => row[key] != null)
          : name === 'SubVegCXL' || name === 'SubVegChtXL'
            ? row.cover6 != null
            : row.cover7 != null || row.cover8 != null || row.cover9 != null
    );
    return records.map((row) => ({
      id: row.id,
      values: projectChildValues(row, 'Veg', childCapabilities),
    }));
  }
  if (name === 'USysVegOtherXL') {
    return vegList.map((row) => ({
      id: row.id,
      values: projectChildValues(row, 'Veg', childCapabilities),
    }));
  }
  if (name === 'SoilHumusXL') {
    return humusList.map((row) => ({
      id: row.id,
      values: {
        ...projectChildValues(row, 'Humus', childCapabilities),
        ...(childCapabilities.Humus?.ph ? { humusformph: row.ph ?? null } : {}),
      },
    }));
  }
  if (name === 'SoilMineralXL') {
    return mineralList.map((row) => ({
      id: row.id,
      values: projectChildValues(row, 'Mineral', childCapabilities),
    }));
  }
  if (name === 'SubOtherXL') {
    return otherList.map((row) => ({
      id: row.id,
      values: projectChildValues(row, 'Other', childCapabilities),
    }));
  }
  throw new Error(`Child data binding is not migrated for ${name}`);
}

export function historicalSoilReadError(kind: 'Humus' | 'Mineral', cause: unknown): string | null {
  const detail = cause instanceof Error ? cause.message : String(cause);
  if (
    /(?:Humus|Mineral) row for plot .* has unsupported NULL ID/i.test(detail) ||
    /sql:\s*Scan error on column index \d+,\s*name\b/i.test(detail)
  ) {
    return `Ordinary ID-keyed ${kind.toLowerCase()} rows are unavailable for this historical plot: ${detail}. Use Two-page complete entry linked soil review to inspect or edit physical rows.`;
  }
  return null;
}

export function validateOrdinarySoilRecordIds<T extends { id: number }>(
  kind: 'Humus' | 'Mineral',
  rows: T[]
): { records: T[]; reason: string | null } {
  const seen = new Set<number>();
  for (const row of rows) {
    if (!row || !Number.isInteger(row.id) || row.id < -2147483648 || row.id > 2147483647) {
      return {
        records: [],
        reason: `Ordinary ID-keyed ${kind.toLowerCase()} rows are unavailable for this historical plot: ${kind} row ID exceeds exact signed32 ordinary identity. Use Two-page complete entry linked soil review to inspect or edit physical rows.`,
      };
    }
    if (seen.has(row.id)) {
      return {
        records: [],
        reason: `Ordinary ID-keyed ${kind.toLowerCase()} rows are unavailable for this historical plot: ${kind} row ID ${row.id} is duplicated. Use Two-page complete entry linked soil review to inspect or edit physical rows.`,
      };
    }
    seen.add(row.id);
  }
  return { records: rows, reason: null };
}

async function executeReviewedSIVISessionOperation(
  owner: {
    load: () => Promise<boolean>;
    save: () => Promise<boolean>;
    undo: () => Promise<boolean>;
    restore: (action: AuditRestoreAction) => Promise<boolean>;
  },
  operation: 'load' | 'save' | 'undo' | 'retain' | 'prune',
  retainAction: AuditRestoreAction,
  pruneAction: AuditRestoreAction
): Promise<boolean> {
  if (operation === 'load') return owner.load();
  if (operation === 'save') return owner.save();
  if (operation === 'undo') return owner.undo();
  return owner.restore(operation === 'retain' ? retainAction : pruneAction);
}

/** Return the first value whose predicate evaluates true (lazy short-circuiting). */
export function firstMatch<T>(guards: Array<[() => boolean, T]>): T | null {
  for (const [cond, value] of guards) {
    if (cond()) return value;
  }
  return null;
}

type ReviewedSiviKind =
  | 'parentWrite'
  | 'parentAction'
  | 'projectAssignment'
  | 'parentShared'
  | 'height'
  | 'cover'
  | 'combined'
  | 'collected'
  | 'species'
  | 'identity';

export type ReviewedSiviOperation = 'load' | 'save' | 'undo' | 'retain' | 'prune';

type SiviChildOwner =
  | 'height'
  | 'cover'
  | 'combined'
  | 'collected'
  | 'species'
  | 'identity'
  | 'creation'
  | 'deletion'
  | 'restoration'
  | 'creationUndo';

interface ReviewedSiviDescriptor {
  guardMsg: string;
  saveMsg: string;
  restoreMsg: string;
  reloadMsg: string;
  failMsg: string;
}

const REVIEWED_SIVI_DESCRIPTORS: Record<ReviewedSiviKind, ReviewedSiviDescriptor> = {
  parentWrite: {
    guardMsg:
      'SIVI parent edits require a clean unlocked parent and no conflicting operation; resolve acknowledgements explicitly.',
    saveMsg: 'SIVI directly bound parent fields saved and independently reloaded.',
    restoreMsg: 'SIVI typed parent restoration completed and reloaded.',
    reloadMsg: 'SIVI parent originals reloaded; no mutation was replayed.',
    failMsg: 'SIVI parent operation failed; owner state retained',
  },
  parentAction: {
    guardMsg:
      'SIVI source actions require a clean unlocked parent and no conflicting drafts or operation; resolve acknowledgements explicitly.',
    saveMsg: 'SIVI source actions saved; callback directive verified and owned parent reloaded.',
    restoreMsg: 'SIVI typed source-action restoration completed and reloaded.',
    reloadMsg: 'SIVI action originals reloaded; no mutation was replayed.',
    failMsg: 'SIVI source-action operation failed; owner state retained',
  },
  projectAssignment: {
    guardMsg:
      'ProjectID assignment requires a clean unlocked parent and no conflicting drafts or operation; resolve acknowledgements explicitly.',
    saveMsg: 'Existing physical ProjectID definition assigned; owned parent and choices reloaded.',
    restoreMsg: 'Typed ProjectID restoration completed and reloaded; metadata was not changed.',
    reloadMsg: 'Owned ProjectID parent and choices reloaded; no mutation was replayed.',
    failMsg: 'ProjectID assignment operation failed; owner state retained',
  },
  parentShared: {
    guardMsg:
      'Shared SIVI edits require a clean unlocked parent and no conflicting operation; recover uncertain writes explicitly.',
    saveMsg: 'Shared SIVI operation completed and owned originals reloaded; no mutation was replayed.',
    restoreMsg: 'Shared SIVI operation completed and owned originals reloaded; no mutation was replayed.',
    reloadMsg: 'Shared SIVI operation completed and owned originals reloaded; no mutation was replayed.',
    failMsg: 'Shared SIVI operation failed; owner state retained',
  },
  height: {
    guardMsg:
      'SIVI requires an available clean, unlocked parent and no conflicting operation or unresolved acknowledgement.',
    saveMsg: 'SIVI aggregate heights saved; current rows and audits reloaded.',
    restoreMsg: 'SIVI typed height restoration completed; current rows and audits reloaded.',
    reloadMsg: 'SIVI source rows reloaded. No height mutation was replayed.',
    failMsg: 'SIVI operation failed; owner state retained',
  },
  cover: {
    guardMsg: 'SIVI covers require a clean, unlocked available parent and no conflicting drafts or operation.',
    saveMsg: 'SIVI source covers saved; current rows and audits reloaded.',
    restoreMsg: 'SIVI typed cover restoration completed; current rows and audits reloaded.',
    reloadMsg: 'SIVI source cover rows reloaded. No mutation was replayed.',
    failMsg: 'SIVI cover operation failed; owner state retained',
  },
  combined: {
    guardMsg:
      'SIVI combined editing requires a clean, unlocked available parent and no conflicting drafts or operation.',
    saveMsg: 'SIVI covers and heights saved atomically; current rows and audits reloaded.',
    restoreMsg: 'SIVI typed combined restoration completed; current rows and audits reloaded.',
    reloadMsg: 'SIVI combined source rows reloaded. No mutation was replayed.',
    failMsg: 'SIVI combined operation failed; owner state retained',
  },
  collected: {
    guardMsg:
      'SIVI Collected editing requires a clean, unlocked available parent and no conflicting drafts or operation.',
    saveMsg: 'SIVI Collected cycle intent saved; current rows and audits reloaded.',
    restoreMsg: 'SIVI typed Collected restoration completed; current rows and audits reloaded.',
    reloadMsg: 'SIVI Collected source rows reloaded. No mutation was replayed.',
    failMsg: 'SIVI Collected operation failed; owner state retained',
  },
  species: {
    guardMsg:
      'SIVI Species editing requires a clean, unlocked available parent and no conflicting drafts or operation.',
    saveMsg: 'SIVI Species source decisions saved; current rows, definitions and audits reloaded.',
    restoreMsg: 'SIVI typed Species restoration completed; current rows, definitions and audits reloaded.',
    reloadMsg: 'SIVI Species rows and definitions reloaded. No mutation was replayed.',
    failMsg: 'SIVI Species operation failed; owner state retained',
  },
  identity: {
    guardMsg: 'SIVI ID editing requires a clean, unlocked available parent and no conflicting drafts or operation.',
    saveMsg: 'SIVI IDs saved with technical restoration history; no source field audits were created.',
    restoreMsg: 'Original IDs restored without source audit pruning or vegetation deletion.',
    reloadMsg: 'Owned SIVI ID source rows reloaded. No mutation was replayed.',
    failMsg: 'SIVI ID operation failed; owner state retained',
  },
};

interface ReviewedSiviOwner {
  load: () => Promise<boolean>;
  save: () => Promise<boolean>;
  undo: () => Promise<boolean>;
  restore: (action: AuditRestoreAction) => Promise<boolean>;
  view: () => { error: string | null };
}

/** Run any reviewed SIVI parent or child session operation with owner-swap protection. */
export async function runReviewedSiviOp(params: {
  kind: ReviewedSiviKind;
  operation: ReviewedSiviOperation;
  allowed: boolean;
  getOwner: () => ReviewedSiviOwner | null;
  retainAction: AuditRestoreAction;
  pruneAction: AuditRestoreAction;
  trackOwner?: boolean;
  onReading?: (reading: boolean) => void;
  setError: (msg: string | null) => void;
  setSuccess: (msg: string | null) => void;
}): Promise<boolean> {
  const desc = REVIEWED_SIVI_DESCRIPTORS[params.kind];
  const owner = params.getOwner();
  if (!owner || !params.allowed) {
    params.setError(desc.guardMsg);
    return false;
  }
  params.setError(null);
  params.setSuccess(null);
  params.onReading?.(params.operation === 'load');
  try {
    const ok = await executeReviewedSIVISessionOperation(
      owner,
      params.operation,
      params.retainAction,
      params.pruneAction
    );
    if (params.trackOwner && owner !== params.getOwner()) return false;
    if (!ok) {
      params.setError(owner.view().error);
      return false;
    }
    params.setSuccess(
      params.operation === 'save'
        ? desc.saveMsg
        : params.operation === 'retain' || params.operation === 'prune'
          ? desc.restoreMsg
          : desc.reloadMsg
    );
    return true;
  } catch (cause) {
    if (params.trackOwner && owner !== params.getOwner()) return false;
    params.setError(`${desc.failMsg}: ${formatError(cause)}`);
    return false;
  } finally {
    if (!params.trackOwner || owner === params.getOwner()) {
      params.onReading?.(false);
    }
  }
}

/** Execute a synchronous SIVI cell staging callback with normalized error handling. */
export function runStageSivi(params: {
  allowed: boolean;
  guardMessage: string;
  errorPrefix: string;
  failPrefix: string;
  action: () => void;
  readError: () => string | null;
  currentError: string | null;
  setError: (msg: string | null) => void;
  setSuccess: (msg: string | null) => void;
}): void {
  try {
    if (!params.allowed) throw new Error(params.guardMessage);
    params.action();
    const message = params.readError();
    if (message) params.setError(`${params.errorPrefix}${message}`);
    else if (params.errorPrefix && params.currentError?.startsWith(params.errorPrefix)) params.setError(null);
    else if (!params.errorPrefix) params.setError(null);
    params.setSuccess(null);
  } catch (cause) {
    params.setError(`${params.failPrefix}: ${formatError(cause)}`);
  }
}

/** Refresh ordinary child lists and untouched SIVI child editors after an exclusive child mutation. */
export async function refreshSiviChildEditorsImpl(params: {
  plot: string;
  owner: SiviChildOwner;
  siviCreationPending: boolean;
  siviDeletionPending: boolean;
  siviRestorationPending: boolean;
  siviCreationUndoPending: boolean;
  sessions: {
    height: SIVIHeightSession | null;
    cover: SIVICoverSession | null;
    combined: SIVICombinedSession | null;
    collected: SIVICollectedSession | null;
    species: SIVISpeciesSession | null;
    identity: SIVIIdentitySession | null;
  };
  loadChildData: (plot: string) => Promise<void>;
}): Promise<void> {
  if (
    (params.owner !== 'creation' && params.siviCreationPending) ||
    (params.owner !== 'deletion' && params.siviDeletionPending) ||
    (params.owner !== 'restoration' && params.siviRestorationPending) ||
    (params.owner !== 'creationUndo' && params.siviCreationUndoPending)
  ) {
    throw new Error('SIVI lifecycle peer owns an unresolved review; no peer originals were reset.');
  }
  const peers = [
    params.owner !== 'height' ? params.sessions.height : null,
    params.owner !== 'cover' ? params.sessions.cover : null,
    params.owner !== 'combined' ? params.sessions.combined : null,
    params.owner !== 'collected' ? params.sessions.collected : null,
    params.owner !== 'species' ? params.sessions.species : null,
    params.owner !== 'identity' ? params.sessions.identity : null,
  ];
  for (const peer of peers) {
    if (peer?.closeState().unsaved || peer?.closeState().busy || peer?.closeState().blocked) {
      throw new Error('SIVI peer owns unresolved drafts or an operation; no peer originals were reset.');
    }
  }
  await params.loadChildData(params.plot);
  for (const peer of peers) {
    if (peer?.view().review && !(await peer.refreshSource())) {
      throw new Error('SIVI peer originals failed to refresh; reload explicitly before continuing.');
    }
  }
}

export function buildDirectSourceChildWrite(
  name: string,
  id: number,
  column: string,
  raw: string,
  lists: {
    vegList: VegRecord[];
    humusList: HumusRecord[];
    mineralList: MineralRecord[];
    otherList: OtherRecord[];
  },
  port: {
    UpdateVegRecord: (record: VegRecord) => Promise<unknown>;
    UpdateHumusRecord: (record: HumusRecord) => Promise<unknown>;
    UpdateMineralRecord: (record: MineralRecord) => Promise<unknown>;
    UpdateOtherRecord: (record: OtherRecord) => Promise<unknown>;
  }
): () => Promise<void> {
  const key = column.toLowerCase();
  const numeric = () => {
    if (raw === '') return undefined;
    const value = Number(raw);
    if (!Number.isFinite(value)) throw new Error(`Enter a finite number for ${column}.`);
    return value;
  };
  if (name.startsWith('SubVeg')) {
    const row = lists.vegList.find((record) => record.id === id);
    if (!row) throw new Error('Vegetation row disappeared; reload before editing.');
    const numbers: Record<
      string,
      | 'cover1'
      | 'cover2'
      | 'cover3'
      | 'totalA'
      | 'cover4'
      | 'cover5'
      | 'totalB'
      | 'cover6'
      | 'cover7'
      | 'cover8'
      | 'cover9'
    > = {
      cover1: 'cover1',
      cover2: 'cover2',
      cover3: 'cover3',
      totala: 'totalA',
      cover4: 'cover4',
      cover5: 'cover5',
      totalb: 'totalB',
      cover6: 'cover6',
      cover7: 'cover7',
      cover8: 'cover8',
      cover9: 'cover9',
    };
    const numberKey = numbers[key];
    if (numberKey)
      return async () => {
        await port.UpdateVegRecord({ ...row, [numberKey]: numeric() });
      };
    if (key === 'collected')
      return async () => {
        await port.UpdateVegRecord({ ...row, collected: raw || undefined });
      };
    throw new Error(`Vegetation column ${column} is not migrated.`);
  }
  if (name === 'SoilHumusXL') {
    const row = lists.humusList.find((record) => record.id === id);
    if (!row) throw new Error('Humus row disappeared; reload before editing.');
    const numbers: Record<string, 'upperDepth' | 'lowerDepth' | 'ph'> = {
      upperdepth: 'upperDepth',
      lowerdepth: 'lowerDepth',
      humusformph: 'ph',
    };
    if (numbers[key])
      return async () => {
        await port.UpdateHumusRecord({ ...row, [numbers[key]]: numeric() });
      };
    if (key === 'horizon' || key === 'comment')
      return async () => {
        await port.UpdateHumusRecord({ ...row, [key]: raw || undefined });
      };
    throw new Error(`Humus column ${column} is not migrated.`);
  }
  if (name === 'SoilMineralXL') {
    const row = lists.mineralList.find((record) => record.id === id);
    if (!row) throw new Error('Mineral row disappeared; reload before editing.');
    const numbers: Record<string, 'upperDepth' | 'lowerDepth'> = { upperdepth: 'upperDepth', lowerdepth: 'lowerDepth' };
    if (numbers[key])
      return async () => {
        await port.UpdateMineralRecord({ ...row, [numbers[key]]: numeric() });
      };
    if (key === 'horizon' || key === 'texture' || key === 'colour' || key === 'comments') {
      return async () => {
        await port.UpdateMineralRecord({ ...row, [key]: raw || undefined });
      };
    }
    throw new Error(`Mineral column ${column} is not migrated.`);
  }
  if (name === 'SubOtherXL') {
    const row = lists.otherList.find((record) => record.id === id);
    if (!row) throw new Error('Other row disappeared; reload before editing.');
    const fields: Record<string, 'dataName' | 'dataItem'> = { dataname: 'dataName', dataitem: 'dataItem' };
    if (!fields[key]) throw new Error(`Other column ${column} is not migrated.`);
    return async () => {
      await port.UpdateOtherRecord({ ...row, [fields[key]]: raw || undefined });
    };
  }
  throw new Error(`Child form ${name} is not migrated.`);
}
