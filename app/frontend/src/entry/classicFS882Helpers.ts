import type { HumusRecord, MineralRecord, VegRecord } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
import type { SoilDrafts } from './fs882FormChildren';

export type ClassicLayoutMode = 'single' | 'side-by-side' | 'top-down' | 'grid';
export type ClassicCardId = 'site' | 'soils' | 'veg' | 'mensuration';

export const CLASSIC_CARD_OPTIONS: readonly { id: ClassicCardId; shortLabel: string; label: string }[] = [
  { id: 'site', shortLabel: 'Card 1: Site', label: 'Card 1 — Site & Environment' },
  { id: 'soils', shortLabel: 'Card 2: Soil', label: 'Card 2 — Soil & Terrain' },
  { id: 'veg', shortLabel: 'Card 3: Vegetation', label: 'Card 3 — Vegetation' },
  { id: 'mensuration', shortLabel: 'Card 4: Mensuration', label: 'Card 4 — Mensuration' },
];

export const CLASSIC_LAYOUT_MODES: readonly { id: ClassicLayoutMode; label: string; title: string }[] = [
  { id: 'single', label: 'Single', title: 'Show one FS882 card at a time' },
  { id: 'side-by-side', label: 'Side-by-Side', title: 'Compare or edit two FS882 cards side by side' },
  { id: 'top-down', label: 'Top-Down', title: 'Stack all 4 FS882 cards vertically for scrolling or printing' },
  { id: 'grid', label: 'Grid', title: 'Show all 4 FS882 cards in a 2x2 grid' },
];

export function resolveVisibleCards(
  mode: ClassicLayoutMode,
  activeTab: string,
  leftCard: ClassicCardId,
  rightCard: ClassicCardId
): Set<ClassicCardId> {
  if (mode === 'top-down' || mode === 'grid') {
    return new Set<ClassicCardId>(['site', 'soils', 'veg', 'mensuration']);
  }
  if (mode === 'side-by-side') {
    return new Set<ClassicCardId>([leftCard, rightCard]);
  }
  if (activeTab === 'site' || activeTab === 'soils' || activeTab === 'veg' || activeTab === 'mensuration') {
    return new Set<ClassicCardId>([activeTab]);
  }
  return new Set<ClassicCardId>();
}

function parseDepthNumber(val: unknown): number | null {
  if (val === null || val === undefined || val === '') return null;
  if (typeof val === 'number') return Number.isFinite(val) ? val : null;
  const parsed = Number(String(val).trim());
  return Number.isFinite(parsed) ? parsed : null;
}

function effectiveHumusDepth(row: HumusRecord, drafts: SoilDrafts, field: 'upperDepth' | 'lowerDepth'): number | null {
  const staged = drafts[`Humus/${row.id}`]?.cells?.[field];
  if (staged !== undefined) {
    return staged.raw.trim() === '' ? null : parseDepthNumber(staged.value ?? staged.raw);
  }
  return parseDepthNumber(row[field]);
}

function effectiveMineralDepth(row: MineralRecord, drafts: SoilDrafts, field: 'upperDepth' | 'lowerDepth'): number | null {
  const staged = drafts[`Mineral/${row.id}`]?.cells?.[field];
  if (staged !== undefined) {
    return staged.raw.trim() === '' ? null : parseDepthNumber(staged.value ?? staged.raw);
  }
  return parseDepthNumber(row[field]);
}

/**
 * Sorts organic soil horizons per LMH25 (2023):
 * - Upland organic (L, F, H; UpperDepth >= LowerDepth): measured upward from 0 cm -> UpperDepth DESC
 * - Wetland organic (Of, Om, Oh; UpperDepth < LowerDepth): measured downward from 0 cm -> UpperDepth ASC
 * - Unset depths placed last.
 */
export function sortHumusHorizonsLMH25(rows: readonly HumusRecord[], drafts: SoilDrafts = {}): HumusRecord[] {
  return rows.slice().sort((a, b) => {
    const aUp = effectiveHumusDepth(a, drafts, 'upperDepth');
    const aLow = effectiveHumusDepth(a, drafts, 'lowerDepth');
    const bUp = effectiveHumusDepth(b, drafts, 'upperDepth');
    const bLow = effectiveHumusDepth(b, drafts, 'lowerDepth');
    if (aUp === null && bUp === null) return a.id - b.id;
    if (aUp === null) return 1;
    if (bUp === null) return -1;
    const aWetland = aLow !== null && aUp < aLow;
    const bWetland = bLow !== null && bUp < bLow;
    if (aWetland !== bWetland) return aWetland ? 1 : -1;
    if (aWetland && bWetland) return aUp - bUp || a.id - b.id;
    return bUp - aUp || a.id - b.id;
  });
}

/**
 * Sorts mineral soil horizons per LMH25 (2023):
 * - Mineral horizons (A, B, C, R, W): measured downward from 0 cm -> UpperDepth ASC
 * - Unset depths placed last.
 */
export function sortMineralHorizonsLMH25(rows: readonly MineralRecord[], drafts: SoilDrafts = {}): MineralRecord[] {
  return rows.slice().sort((a, b) => {
    const aUp = effectiveMineralDepth(a, drafts, 'upperDepth');
    const bUp = effectiveMineralDepth(b, drafts, 'upperDepth');
    if (aUp === null && bUp === null) return a.id - b.id;
    if (aUp === null) return 1;
    if (bUp === null) return -1;
    return aUp - bUp || a.id - b.id;
  });
}

export function classifyVegRowsForClassicCard(rows: readonly VegRecord[]): {
  treeShrub: VegRecord[];
  herb: VegRecord[];
  moss: VegRecord[];
} {
  const treeShrub: VegRecord[] = [];
  const herb: VegRecord[] = [];
  const moss: VegRecord[] = [];
  for (const r of rows) {
    const hasAB =
      [
        r.cover1,
        r.cover2,
        r.cover3,
        r.totalA,
        r.height1,
        r.height2,
        r.height3,
        r.cover4,
        r.cover5,
        r.cover5a,
        r.cover5b,
        r.cover5c,
        r.totalB,
        r.height4,
        r.height5,
      ].some((v) => v != null) ||
      r.layer === 'A' ||
      r.layer === 'B';
    const hasC = r.cover6 != null || r.height6 != null || r.layer === 'C';
    const hasD = [r.cover7, r.cover8, r.cover9].some((v) => v != null) || r.layer === 'D';
    if (hasAB) treeShrub.push(r);
    if (hasC) herb.push(r);
    if (hasD) moss.push(r);
    if (!hasAB && !hasC && !hasD) {
      treeShrub.push(r);
    }
  }
  return { treeShrub, herb, moss };
}

export function computeSubstrateTotal(header: {
  substrateOrganicMatter?: number | null;
  substrateDecWood?: number | null;
  substrateBedRock?: number | null;
  substrateRocks?: number | null;
  substrateMineralSoil?: number | null;
  substrateWater?: number | null;
}): number | null {
  const vals = [
    header.substrateOrganicMatter,
    header.substrateDecWood,
    header.substrateBedRock,
    header.substrateRocks,
    header.substrateMineralSoil,
    header.substrateWater,
  ];
  let sum = 0;
  let count = 0;
  for (const v of vals) {
    if (typeof v === 'number' && Number.isFinite(v)) {
      sum += v;
      count += 1;
    }
  }
  return count > 0 ? Math.round(sum * 100) / 100 : null;
}

export function formatRecordJumpInput(raw: string, totalCount: number): { index: number | null; error: string | null } {
  const trimmed = raw.trim().replace(/,/g, '');
  if (!trimmed) return { index: null, error: 'Enter a record number.' };
  if (!/^\d+$/.test(trimmed)) return { index: null, error: 'Record number must be a whole number.' };
  const parsed = Number(trimmed);
  if (!Number.isSafeInteger(parsed) || parsed < 1 || (totalCount > 0 && parsed > totalCount)) {
    return {
      index: null,
      error: totalCount > 0 ? `Record number must be between 1 and ${totalCount.toLocaleString()}.` : 'No records available.',
    };
  }
  return { index: parsed, error: null };
}
