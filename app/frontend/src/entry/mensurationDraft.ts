import type { FS882Header, TreePlotRecord, TreeRowRecord } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';

const TREE_PLOT_TEXT_MAX: Readonly<Record<string, number>> = {
  plotNumber: 7,
  subPlot: 30,
  mensurationId: 255,
  zone: 10,
  subZone: 15,
  fiz: 2,
  treeSurveyor: 30,
  date: 0,
  seralStage: 255,
  fsRegionDistrict: 7,
  location: 255,
  becSiteUnit: 100,
  siteSeries: 5,
  comment: 0,
  dataSource: 255,
};

const TREES_TEXT_MAX: Readonly<Record<string, number>> = {
  plotNumber: 7,
  subPlot: 30,
  treeSpp: 3,
  ageNote: 255,
  treeOrigin: 1,
  damageType: 3,
  damageSeverity: 1,
  crownClass: 1,
  wildLifeUse: 17,
  treeNotes: 0,
  liveDead: 255,
};

const TREES_BYTE_FIELDS = [
  'treeHealth',
  'conks',
  'blindConks',
  'scars',
  'forkOrCrook',
  'frostCrack',
  'mistletoe',
  'rottenBranch',
  'deadOrBrokenTop',
  'appearance',
  'crownCondition',
  'barkRetention',
  'woodCondition',
  'lichenLoading',
  'mossLoading',
] as const;

const TREES_DOUBLE_FIELDS = ['cuVolume', 'sph', 'basalArea', 'siteIndex24', 'si50'] as const;

const MAX_FLOAT32 = 3.4028234663852886e38;
const MIN_INT32 = -2147483648;
const MAX_INT32 = 2147483647;

function utf16Length(value: string): number {
  return value.length;
}

export function treePlotKey(rec: Pick<TreePlotRecord, 'subPlot' | 'measurementId'>): string {
  return `${rec.subPlot}::${rec.measurementId}`;
}

export function treeRowKey(
  row: Pick<TreeRowRecord, 'rowId' | 'subPlot' | 'measurementId' | 'treeNum'>,
  fallbackIndex = 0
): string {
  if (typeof row.rowId === 'number' && row.rowId > 0) return `rid:${row.rowId}`;
  return `new:${row.subPlot ?? ''}::${row.measurementId ?? ''}::${row.treeNum ?? ''}::${fallbackIndex}`;
}

export function nextMeasurementId(treePlots: readonly TreePlotRecord[], subPlot: string): number {
  const normalized = subPlot.trim();
  let maxId = 0;
  for (const tp of treePlots) {
    if (tp.subPlot === normalized && typeof tp.measurementId === 'number' && tp.measurementId > maxId) {
      maxId = tp.measurementId;
    }
  }
  return maxId + 1;
}

export function nextTreeNumber(
  trees: readonly TreeRowRecord[],
  subPlot?: string | null,
  measurementId?: number | null
): number {
  let maxNum = 0;
  for (const row of trees) {
    if (subPlot !== undefined && row.subPlot !== subPlot) continue;
    if (measurementId !== undefined && row.measurementId !== measurementId) continue;
    if (typeof row.treeNum === 'number' && Number.isFinite(row.treeNum) && row.treeNum > maxNum) {
      maxNum = Math.trunc(row.treeNum);
    }
  }
  return maxNum + 1;
}

export function newEmptyTreePlotRecord(
  plotNumber: string,
  header?: Partial<FS882Header> | null,
  existing: readonly TreePlotRecord[] = []
): TreePlotRecord {
  const defaultSubPlot = 'A';
  const measurementId = existing.length === 0 ? 1 : nextMeasurementId(existing, defaultSubPlot);
  return {
    plotNumber,
    subPlot: defaultSubPlot,
    measurementId,
    mensurationId: null,
    zone: header?.zone ?? null,
    subZone: header?.subZone ?? null,
    fiz: null,
    treeSurveyor: header?.surveyor ?? null,
    date: header?.date ?? null,
    cruisePlot: false,
    cwdPlot: false,
    wildlifePlot: false,
    informalPlot: false,
    siteIndexPlot: false,
    baf: null,
    dbhLimit: null,
    standAge: header?.standAge ?? null,
    plotSize: null,
    seralStage: header?.structuralStage ?? null,
    fsRegionDistrict: header?.fsRegionDistrict ?? null,
    location: header?.generalLocation ?? null,
    becSiteUnit: header?.becSiteUnit ?? null,
    standAgeVPro: header?.standAge ?? null,
    siteSeries: header?.siteSeries ?? null,
    comment: null,
    dataSource: null,
  };
}

export function newEmptyTreeRowRecord(
  plotNumber: string,
  subPlot: string | null,
  measurementId: number | null,
  treeNum: number
): TreeRowRecord {
  return {
    plotNumber,
    subPlot,
    measurementId,
    treeNum,
    treeSpp: null,
    dbh: null,
    dbhClass: null,
    totalHtCalc: null,
    heightClass: null,
    countAge: null,
    countHt: null,
    totalAge: null,
    ageNote: null,
    treeHealth: null,
    treeOrigin: null,
    conks: null,
    blindConks: null,
    scars: null,
    forkOrCrook: null,
    frostCrack: null,
    mistletoe: null,
    rottenBranch: null,
    deadOrBrokenTop: null,
    damageType: null,
    damageSeverity: null,
    crownClass: null,
    ht2LiveCrown: null,
    appearance: null,
    crownCondition: null,
    barkRetention: null,
    woodCondition: null,
    lichenLoading: null,
    mossLoading: null,
    wildLifeUse: null,
    treeNotes: null,
    liveDead: null,
    cuVolume: null,
    sph: null,
    basalArea: null,
    siteIndexId: null,
    siteIndex: null,
    siteIndex24: null,
    si50: null,
  };
}

export function sortTreePlots(plots: readonly TreePlotRecord[]): TreePlotRecord[] {
  return plots.slice().sort((a, b) => {
    const subCmp = a.subPlot.localeCompare(b.subPlot);
    if (subCmp !== 0) return subCmp;
    return a.measurementId - b.measurementId;
  });
}

export function sortTreeRows(rows: readonly TreeRowRecord[]): TreeRowRecord[] {
  return rows.slice().sort((a, b) => {
    const subA = a.subPlot ?? '';
    const subB = b.subPlot ?? '';
    const subCmp = subA.localeCompare(subB);
    if (subCmp !== 0) return subCmp;
    const measA = a.measurementId ?? Number.MAX_SAFE_INTEGER;
    const measB = b.measurementId ?? Number.MAX_SAFE_INTEGER;
    if (measA !== measB) return measA - measB;
    const numA = a.treeNum ?? Number.MAX_SAFE_INTEGER;
    const numB = b.treeNum ?? Number.MAX_SAFE_INTEGER;
    if (numA !== numB) return numA - numB;
    return (a.rowId ?? Number.MAX_SAFE_INTEGER) - (b.rowId ?? Number.MAX_SAFE_INTEGER);
  });
}

export function parseOptionalInt(
  raw: string,
  label: string,
  bounds: { min?: number; max?: number } = {}
): { value: number | null; error: string | null } {
  const trimmed = raw.trim();
  if (trimmed === '') return { value: null, error: null };
  if (!/^[+-]?\d+$/.test(trimmed)) {
    return { value: null, error: `${label} must be a whole number.` };
  }
  const parsed = Number(trimmed);
  const min = bounds.min ?? MIN_INT32;
  const max = bounds.max ?? MAX_INT32;
  if (!Number.isSafeInteger(parsed) || parsed < min || parsed > max) {
    return { value: null, error: `${label} must be between ${min} and ${max}.` };
  }
  return { value: parsed, error: null };
}

export function parseOptionalFloat(
  raw: string,
  label: string,
  single = true
): { value: number | null; error: string | null } {
  const trimmed = raw.trim();
  if (trimmed === '') return { value: null, error: null };
  const parsed = Number(trimmed);
  if (!Number.isFinite(parsed)) {
    return { value: null, error: `${label} must be a valid number.` };
  }
  if (single && Math.abs(parsed) > MAX_FLOAT32) {
    return { value: null, error: `${label} is outside the supported numeric range.` };
  }
  return { value: parsed === 0 ? 0 : parsed, error: null };
}

function checkTextField(
  errors: string[],
  label: string,
  value: string | null | undefined,
  maxLen: number
): void {
  if (value === null || value === undefined) return;
  if (value.includes('\u0000')) {
    errors.push(`${label} cannot contain NUL characters.`);
    return;
  }
  if (maxLen > 0 && utf16Length(value) > maxLen) {
    errors.push(`${label} must be at most ${maxLen} characters.`);
  }
}

export function validateTreePlotDraft(rec: TreePlotRecord): string[] {
  const errors: string[] = [];
  if (!rec.plotNumber || !rec.plotNumber.trim()) {
    errors.push('PlotNumber is required.');
  } else if (rec.plotNumber !== rec.plotNumber.trim()) {
    errors.push('PlotNumber cannot start or end with spaces.');
  } else {
    checkTextField(errors, 'PlotNumber', rec.plotNumber, TREE_PLOT_TEXT_MAX.plotNumber);
  }
  if (!rec.subPlot || !rec.subPlot.trim()) {
    errors.push('SubPlot is required.');
  } else {
    checkTextField(errors, 'SubPlot', rec.subPlot, TREE_PLOT_TEXT_MAX.subPlot);
  }
  if (!Number.isInteger(rec.measurementId) || rec.measurementId < MIN_INT32 || rec.measurementId > MAX_INT32) {
    errors.push('MeasurementID must be a whole number.');
  }
  const textFields: readonly [keyof TreePlotRecord, string][] = [
    ['mensurationId', 'MensurationID'],
    ['zone', 'Zone'],
    ['subZone', 'SubZone'],
    ['fiz', 'FIZ'],
    ['treeSurveyor', 'TreeSurveyor'],
    ['date', 'Date'],
    ['seralStage', 'SeralStage'],
    ['fsRegionDistrict', 'FSRegionDistrict'],
    ['location', 'Location'],
    ['becSiteUnit', 'BECSiteUnit'],
    ['siteSeries', 'SiteSeries'],
    ['comment', 'Comment'],
    ['dataSource', 'DataSource'],
  ];
  for (const [key, label] of textFields) {
    checkTextField(errors, label, rec[key] as string | null, TREE_PLOT_TEXT_MAX[key] ?? 0);
  }
  for (const [key, label] of [
    ['baf', 'BAF'],
    ['dbhLimit', 'DBHLimit'],
    ['plotSize', 'PlotSize'],
  ] as const) {
    const val = rec[key];
    if (val !== null && val !== undefined && (!Number.isFinite(val) || Math.abs(val) > MAX_FLOAT32)) {
      errors.push(`${label} must be a valid number.`);
    }
  }
  for (const [key, label] of [
    ['standAge', 'StandAge'],
    ['standAgeVPro', 'StandAgeVPro'],
  ] as const) {
    const val = rec[key];
    if (val !== null && val !== undefined && (!Number.isInteger(val) || val < MIN_INT32 || val > MAX_INT32)) {
      errors.push(`${label} must be a whole number.`);
    }
  }
  return errors;
}

export function validateTreeRowDraft(rec: TreeRowRecord): string[] {
  const errors: string[] = [];
  if (!rec.plotNumber || !rec.plotNumber.trim()) {
    errors.push('PlotNumber is required.');
  } else {
    checkTextField(errors, 'PlotNumber', rec.plotNumber, TREES_TEXT_MAX.plotNumber);
  }
  const textFields: readonly [keyof TreeRowRecord, string][] = [
    ['subPlot', 'SubPlot'],
    ['treeSpp', 'TreeSpp'],
    ['ageNote', 'AgeNote'],
    ['treeOrigin', 'TreeOrigin'],
    ['damageType', 'DamageType'],
    ['damageSeverity', 'DamageSeverity'],
    ['crownClass', 'CrownClass'],
    ['wildLifeUse', 'WildLifeUse'],
    ['treeNotes', 'TreeNotes'],
    ['liveDead', 'LiveDead'],
  ];
  for (const [key, label] of textFields) {
    checkTextField(errors, label, rec[key] as string | null, TREES_TEXT_MAX[key] ?? 0);
  }
  for (const [key, label] of [
    ['measurementId', 'MeasurementID'],
    ['treeNum', 'TreeNum'],
    ['countAge', 'CountAge'],
    ['totalAge', 'TotalAge'],
  ] as const) {
    const val = rec[key];
    if (val !== null && val !== undefined && (!Number.isInteger(val) || val < MIN_INT32 || val > MAX_INT32)) {
      errors.push(`${label} must be a whole number.`);
    }
  }
  for (const field of TREES_BYTE_FIELDS) {
    const val = rec[field];
    if (val !== null && val !== undefined && (!Number.isInteger(val) || val < 0 || val > 255)) {
      errors.push(`${field} must be a whole number from 0 to 255.`);
    }
  }
  for (const [key, label] of [
    ['dbh', 'DBH'],
    ['dbhClass', 'DBHClass'],
    ['totalHtCalc', 'TotalHtCalc'],
    ['heightClass', 'HeightClass'],
    ['countHt', 'CountHT'],
    ['ht2LiveCrown', 'Ht2LiveCrown'],
    ['siteIndex', 'SiteIndex'],
  ] as const) {
    const val = rec[key];
    if (val !== null && val !== undefined && (!Number.isFinite(val) || Math.abs(val) > MAX_FLOAT32)) {
      errors.push(`${label} must be a valid number.`);
    }
  }
  for (const key of TREES_DOUBLE_FIELDS) {
    const val = rec[key];
    if (val !== null && val !== undefined && !Number.isFinite(val)) {
      errors.push(`${key} must be a finite number.`);
    }
  }
  return errors;
}

export function formatPathologySummary(row: TreeRowRecord): string {
  const parts: string[] = [];
  if (row.conks != null) parts.push(`Ck:${row.conks}`);
  if (row.blindConks != null) parts.push(`BC:${row.blindConks}`);
  if (row.scars != null) parts.push(`Sc:${row.scars}`);
  if (row.forkOrCrook != null) parts.push(`Fk:${row.forkOrCrook}`);
  if (row.frostCrack != null) parts.push(`Fr:${row.frostCrack}`);
  if (row.mistletoe != null) parts.push(`Ms:${row.mistletoe}`);
  if (row.rottenBranch != null) parts.push(`RB:${row.rottenBranch}`);
  if (row.deadOrBrokenTop != null) parts.push(`DT:${row.deadOrBrokenTop}`);
  if (row.damageType) parts.push(`Dmg:${row.damageType}${row.damageSeverity ? '/' + row.damageSeverity : ''}`);
  if (row.wildLifeUse) parts.push(`WL:${row.wildLifeUse}`);
  if (row.appearance != null || row.crownCondition != null || row.barkRetention != null || row.woodCondition != null) {
    parts.push('WLT');
  }
  return parts.length > 0 ? parts.join(' ') : 'None';
}
