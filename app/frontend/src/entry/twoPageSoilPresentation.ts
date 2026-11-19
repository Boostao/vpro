import { metadataCellText } from '../admin/projectMetadataEditor';
import { twoPageSoilEditableID, twoPageSoilKind, type TwoPageSoilOriginal } from './twoPageSoilEditor';
import { soilFields } from './soilChildEditor';

export const twoPageSoilGroups = {
  Humus: [
    { label: 'Horizon and depth', fields: [['Horizon', 'Horizon'], ['UpperDepth', 'Depth Up'], ['LowerDepth', 'Depth Low']] },
    { label: 'Structure', fields: [['HumusStructureDegree', 'Structure AB'], ['HumusStructureKind', 'Fabric'], ['vonPost', 'Von Post']] },
    { label: 'Organisms and roots', fields: [['MycelAbundance', 'Mycel AB'], ['FecalAbundance', 'Fecal AB'], ['RootsAbundance', 'Roots AB'], ['RootsSize', 'Roots Size']] },
    { label: 'pH and comments', fields: [['HumusFormpH', 'pH'], ['Comment', 'Comments (consistency, character, fauna, etc.)']] },
  ],
  Mineral: [
    { label: 'Horizon and depth', fields: [['Horizon', 'Horizon'], ['UpperDepth', 'Depth Up'], ['LowerDepth', 'Depth Low'], ['PitDepthLimit', '+ (Pit depth limit)']] },
    { label: 'Texture and aspect', fields: [['Texture', 'Texture'], ['Colour', 'Colour'], ['ASP', 'ASP']] },
    { label: '% Coarse fragments', fields: [['PercentCoarseFragsGravel', 'G'], ['PercentCoarseFragsCobbles', 'C'], ['PercentCoarseFragsStones', 'S'], ['PercentCoarseFragsTotal', 'Tot.'], ['PercentCoarseFragsShape', 'Shape']] },
    { label: 'Roots and structure', fields: [['RootsAbundance', 'Roots AB'], ['RootsSize', 'Roots Size'], ['MineralStructureClass', 'Structure Class'], ['MineralStructureKind', 'Structure Kind']] },
    { label: 'pH and comments', fields: [['MineralFormpH', 'pH'], ['Comments', 'Comments (mottles, clay films, effervesc., etc.)']] },
  ],
} as const;

export function twoPageSoilCell(original: TwoPageSoilOriginal, rowId: string, column: string) {
  const row = original.records.rows.find(row => row.rowId === rowId);
  const index = original.records.columns.findIndex(field => field.name === column);
  if (!row || index < 0) throw new Error(`Soil physical row ${rowId} / source column ${column} is unavailable.`);
  return row.cells[index];
}

export function twoPageSoilStoredText(original: TwoPageSoilOriginal, rowId: string, column: string) {
  const cell = twoPageSoilCell(original, rowId, column);
  return cell.storage === 'null' ? 'NULL' : cell.storage === 'text' && cell.text === '' ? '(empty text)' : metadataCellText(cell);
}

export function twoPageSoilRowDiagnostic(original: TwoPageSoilOriginal, rowId: string): string | null {
  try { twoPageSoilEditableID(original, rowId); }
  catch (cause) { return `Read-only physical row: ${String(cause)}`; }
  const missing = soilFields[twoPageSoilKind(original.form)].filter(field =>
    !original.records.columns.some(column => column.name === field.column));
  return missing.length ? `Read-only physical row: source columns unavailable: ${missing.map(field => field.column).join(', ')}.` : null;
}

export function twoPageSoilDepthOrder(original: TwoPageSoilOriginal) {
  const rows = original.records.rows.slice();
  const index = original.records.columns.findIndex(column => column.name === 'UpperDepth');
  const fallback = (reason: string) => ({
    rows,
    diagnostic: `${reason} Physical reader order is shown without coercion.`,
    status: null as string | null,
  });
  if (index < 0) return fallback('Depth order unavailable: UpperDepth is missing.');
  const values = new Map<string, bigint | number | null>();
  for (const row of rows) {
    const cell = row.cells[index];
    if (cell.storage === 'null') values.set(row.rowId, null);
    else if (cell.storage === 'integer' && cell.integer !== null) values.set(row.rowId, BigInt(cell.integer));
    else if (cell.storage === 'real' && cell.real !== null && Number.isFinite(cell.real)) values.set(row.rowId, cell.real);
    else return fallback(`Depth order unavailable: physical row ${row.rowId} has historical ${cell.storage} UpperDepth.`);
  }
  const humus = original.form === 'SoilHumusXL';
  // LMH25 (AGENTS.md §3.4): upland L/F/H read top-down by UpperDepth DESC, then wetland
  // O*/Hydric/Limno/Cumulo by UpperDepth ASC (mirrors Go vprocore.HumusOrderBySQL).
  const horizonIndex = original.records.columns.findIndex(column => column.name === 'Horizon');
  const wetland = new Map<string, boolean>();
  let hasWetland = false;
  let hasUpland = false;
  for (const row of rows) {
    const cell = horizonIndex < 0 ? null : row.cells[horizonIndex];
    const code = cell && cell.storage === 'text' && cell.text !== null
      ? cell.text.trim().toUpperCase().replace(/^[0-9IVX ]+/, '') : '';
    const isWet = humus && /^(O|HYDRIC|LIMNO|CUMULO)/.test(code);
    wetland.set(row.rowId, isWet);
    if (humus) {
      if (isWet) hasWetland = true;
      else hasUpland = true;
    }
  }
  rows.sort((left, right) => {
    const a = values.get(left.rowId), b = values.get(right.rowId);
    if (a === undefined || b === undefined) throw new Error('Soil depth order lost its validated physical row.');
    const wa = wetland.get(left.rowId) === true, wb = wetland.get(right.rowId) === true;
    if (!humus) return a === null ? b === null ? 0 : -1 : b === null ? 1 : a < b ? -1 : a > b ? 1 : 0;
    if (wa !== wb) return wa ? 1 : -1;
    if (a === null || b === null) return a === null ? (b === null ? 0 : 1) : -1; // NULL depths last
    const comparison = a < b ? -1 : a > b ? 1 : 0;
    return wa ? comparison : -comparison;
  });
  const status = !humus
    ? 'Depth Up ascending (NULL first). Ties retain physical reader order.'
    : hasWetland && hasUpland
      ? 'Upland descending, then wetland ascending (NULL last). Ties retain physical reader order.'
      : hasWetland
        ? 'Depth Down ascending (NULL last). Ties retain physical reader order.'
        : 'Depth Up descending (NULL last). Ties retain physical reader order.';
  return { rows, diagnostic: null as string | null, status };
}
