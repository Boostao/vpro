import type {
  HumusRecord,
  MineralRecord,
  OtherRecord,
  VegRecord,
} from '../../bindings/github.com/boostao/vpro/app';
import {
  aCoverSourceNotice,
  aCoverSourceNotices,
  heightDirty,
  heightErrors,
  heightField,
  heightSourceNotices,
  heightUpdates,
  stageHeight,
  vegetationNumberUpdates,
  type HeightDrafts,
} from './heightEditor';
import { otherDirty, otherErrors, otherField, otherUpdates, stageOther, type OtherDrafts, type OtherValue } from './otherEditor';
import { soilDirty, soilErrors, soilField, soilUpdates, stageSoil, type SoilDrafts, type SoilKind } from './soilChildEditor';
import {
  stageVegetationAttribute,
  vegetationAttributeDirty,
  vegetationAttributeErrors,
  vegetationAttributeField,
  vegetationAttributeUpdates,
  type VegetationAttributeDrafts,
} from './vegetationAttributeEditor';
import { collectedDirty, collectedUpdates, stageCollected, type CollectedDrafts } from './collectedEditor';
import {
  chooseSpecies,
  speciesDirty,
  speciesErrors,
  speciesForms,
  speciesUpdates,
  stageSpecies,
  type SpeciesChoices,
  type SpeciesDecisionKind,
  type SpeciesDrafts,
  type SpeciesLists,
} from './vegetationSpeciesEditor';
import {
  projectSourceRows,
  type FS882ChildCapabilities,
} from './fs882FormHelpers';

export interface ChildOperationContext {
  busy: boolean;
  headerWorkflowBusy: boolean;
  capabilitiesReady: boolean;
  locked: boolean;
  hasOriginal: boolean;
  plotNumber: string;
  dirty: boolean;
  childUnsaved: boolean;
  setBusy: (busy: boolean) => void;
  setError: (msg: string | null) => void;
  appendError: (suffix: string) => void;
  setSuccess: (msg: string | null) => void;
  invalidateCapabilities: () => void;
  loadChildData: (plot: string) => Promise<void>;
}

/** Merge committed Humus/Mineral rows with valid staged SoilDrafts for live diagnostics snapshots. */
export function mergeSoilDraftRows<T extends { id: number }>(
  kind: 'Humus' | 'Mineral',
  rows: T[],
  drafts: SoilDrafts,
  snapshotRow: (row: T) => Record<string, unknown>,
): Record<string, unknown>[] {
  return rows.map(row => {
    const snap = snapshotRow(row);
    const staged = drafts[`${kind}/${row.id}`];
    if (!staged) return snap;
    const merged: Record<string, unknown> = { ...snap };
    for (const [key, cell] of Object.entries(staged.cells)) {
      if (cell.error === null) merged[key] = cell.value;
    }
    return merged;
  });
}

/** Shared wrapper for cancelling any staged child draft cohort and reloading rows. */
export async function cancelChildDraftsImpl(params: {
  guardBlocked: boolean;
  guardMessage: string;
  clearDrafts: () => void;
  bumpRevision?: () => void;
  plotNumber: string;
  loadChildData: (plot: string) => Promise<void>;
  successMessage: string;
  reloadErrorMessage: string;
  setBusy: (busy: boolean) => void;
  setError: (msg: string | null) => void;
  setSuccess: (msg: string | null) => void;
  invalidateCapabilities: () => void;
}): Promise<void> {
  if (params.guardBlocked) {
    params.setError(params.guardMessage);
    return;
  }
  params.clearDrafts();
  params.bumpRevision?.();
  params.setError(null);
  params.setSuccess(null);
  params.setBusy(true);
  try {
    await params.loadChildData(params.plotNumber);
    params.setSuccess(params.successMessage);
  } catch (cause) {
    params.invalidateCapabilities();
    params.setError(`${params.reloadErrorMessage}: ${String(cause)}`);
  } finally {
    params.setBusy(false);
  }
}

/** Shared atomic commit helper for staged child drafts (height, other, soil, attribute, collected, species). */
export async function saveChildDraftsImpl(params: {
  disabled: boolean;
  guardMessage: string;
  hasUpdates: boolean;
  noChangeMessage: string;
  clearEmpty: () => void;
  commit: () => Promise<void>;
  clearOnCommit: () => void;
  plotNumber: string;
  loadChildData: (plot: string) => Promise<void>;
  buildSuccessMessage: () => string;
  committedRefreshPrefix: string;
  failedPrefix: string;
  setBusy: (busy: boolean) => void;
  setError: (msg: string | null) => void;
  setSuccess: (msg: string | null) => void;
  invalidateCapabilities: () => void;
}): Promise<void> {
  if (params.disabled) {
    params.setError(params.guardMessage);
    return;
  }
  let committed = false;
  params.setBusy(true);
  params.setError(null);
  params.setSuccess(null);
  try {
    if (!params.hasUpdates) {
      params.clearEmpty();
      params.setSuccess(params.noChangeMessage);
      return;
    }
    await params.commit();
    committed = true;
    params.clearOnCommit();
    await params.loadChildData(params.plotNumber);
    params.setSuccess(params.buildSuccessMessage());
  } catch (cause) {
    if (committed) params.invalidateCapabilities();
    params.setError(
      committed
        ? `${params.committedRefreshPrefix}: ${String(cause)}`
        : `${params.failedPrefix}: ${String(cause)}`,
    );
  } finally {
    params.setBusy(false);
  }
}

/** Generic exclusive child write helper for direct source record operations. */
export async function childOperationImpl(
  ctx: ChildOperationContext,
  operation: () => Promise<void>,
): Promise<boolean> {
  if (!ctx.capabilitiesReady || ctx.busy || ctx.headerWorkflowBusy || ctx.locked) {
    ctx.setError('Child editing is unavailable while the plot is loading, busy or locked.');
    return false;
  }
  if (!ctx.hasOriginal || !ctx.plotNumber || ctx.dirty || ctx.childUnsaved) {
    ctx.setError('Save the plot header before editing child records.');
    return false;
  }
  if (ctx.locked || ctx.busy) {
    ctx.setError('Child records cannot be changed while locked or loading.');
    return false;
  }
  ctx.setBusy(true);
  ctx.setError(null);
  ctx.setSuccess(null);
  let committed = false;
  try {
    await operation();
    committed = true;
    await ctx.loadChildData(ctx.plotNumber);
    return true;
  } catch (cause) {
    if (committed) {
      ctx.invalidateCapabilities();
      ctx.setError(`Child changes committed, but refresh failed. Reopen the plot before editing: ${String(cause)}`);
      return true;
    }
    ctx.setError(`Child operation failed: ${String(cause)}`);
    try {
      await ctx.loadChildData(ctx.plotNumber);
    } catch (refreshError) {
      ctx.appendError(`; refresh failed: ${String(refreshError)}`);
    }
    return false;
  } finally {
    ctx.setBusy(false);
  }
}

function sourceRowsFor(
  name: string,
  vegList: VegRecord[],
  humusList: HumusRecord[],
  mineralList: MineralRecord[],
  otherList: OtherRecord[],
  childCapabilities: FS882ChildCapabilities,
) {
  return projectSourceRows(name, { vegList, humusList, mineralList, otherList, childCapabilities });
}

/** Stage an editable vegetation height/cover draft cell with identity and capability guards. */
export function stageHeightCellImpl(params: {
  enabled: boolean;
  disabled: boolean;
  childCapabilities: FS882ChildCapabilities;
  vegList: VegRecord[];
  humusList: HumusRecord[];
  mineralList: MineralRecord[];
  otherList: OtherRecord[];
  plotNumber: string;
  heightDrafts: HeightDrafts;
  id: number;
  column: string;
  raw: string;
  form: string;
}): { heightDrafts: HeightDrafts; error?: string; bumpRevision?: boolean } {
  try {
    if (!params.enabled || params.disabled) {
      throw new Error('Height editing is unavailable while loading, locked, busy or the header is unsaved.');
    }
    const field = heightField(params.column);
    if (!field || params.childCapabilities.Veg[field] !== true) {
      throw new Error(`Height column ${params.column} is unavailable in the active schema.`);
    }
    const rows = params.vegList.filter(row => row.id === params.id && row.plotNumber === params.plotNumber);
    if (rows.length !== 1) throw new Error('Height row identity is missing or ambiguous; reload before editing.');
    if (!sourceRowsFor(params.form, params.vegList, params.humusList, params.mineralList, params.otherList, params.childCapabilities).some(row => row.id === params.id)) {
      throw new Error('Vegetation source row is unavailable; reload before editing.');
    }
    return { heightDrafts: stageHeight(params.heightDrafts, params.id, field, params.raw, rows[0][field] ?? null, params.form) };
  } catch (cause) {
    return { heightDrafts: params.heightDrafts, error: `Height draft failed: ${String(cause)}`, bumpRevision: true };
  }
}

/** Stage an editable SubOtherXL cell draft. */
export function stageOtherCellImpl(params: {
  disabled: boolean;
  childCapabilities: FS882ChildCapabilities;
  otherList: OtherRecord[];
  plotNumber: string;
  otherDrafts: OtherDrafts;
  id: number;
  column: string;
  raw: OtherValue;
}): { otherDrafts: OtherDrafts; clearOtherError: boolean; error?: string; bumpRevision?: boolean } {
  try {
    if (params.disabled) throw new Error('Other editing is unavailable while loading, locked, busy or another draft is unsaved.');
    const field = otherField(params.column);
    if (!field || params.childCapabilities.Other[field.key] !== true) {
      throw new Error(`Other column ${params.column} is unavailable in the active schema.`);
    }
    const rows = params.otherList.filter(row => row.id === params.id && row.plotNumber === params.plotNumber);
    if (rows.length !== 1) throw new Error('Other row identity is missing or ambiguous; reload before editing.');
    return {
      otherDrafts: stageOther(params.otherDrafts, params.id, field, params.raw, rows[0][field.key] ?? null),
      clearOtherError: true,
    };
  } catch (cause) {
    return { otherDrafts: params.otherDrafts, clearOtherError: false, error: `Other draft failed: ${String(cause)}`, bumpRevision: true };
  }
}

/** Stage a SoilHumusXL or SoilMineralXL cell draft. */
export function stageSoilCellImpl(params: {
  disabled: boolean;
  childCapabilities: FS882ChildCapabilities;
  humusList: HumusRecord[];
  mineralList: MineralRecord[];
  plotNumber: string;
  soilDrafts: SoilDrafts;
  kind: SoilKind;
  id: number;
  column: string;
  raw: string;
}): { soilDrafts: SoilDrafts; clearSoilError: boolean; error?: string; bumpRevision?: boolean } {
  try {
    if (params.disabled) throw new Error('Soil editing is unavailable while loading, locked, busy or another draft is unsaved.');
    const field = soilField(params.kind, params.column);
    if (!field || params.childCapabilities[params.kind][field.key] !== true) {
      throw new Error(`Soil column ${params.column} is unavailable in the active schema.`);
    }
    const rows = (params.kind === 'Humus' ? params.humusList : params.mineralList).filter(
      row => row.id === params.id && row.plotNumber === params.plotNumber,
    );
    if (rows.length !== 1) throw new Error('Soil row identity is missing or ambiguous; reload before editing.');
    const stored = new Map(Object.entries(rows[0])).get(field.key);
    if (stored !== null && stored !== undefined && typeof stored !== 'string' && typeof stored !== 'number') {
      throw new Error('Soil cell has an unsupported storage type.');
    }
    return {
      soilDrafts: stageSoil(params.soilDrafts, params.kind, params.id, field, params.raw, stored ?? null),
      clearSoilError: true,
    };
  } catch (cause) {
    return { soilDrafts: params.soilDrafts, clearSoilError: false, error: `Soil draft failed: ${String(cause)}`, bumpRevision: true };
  }
}

/** Stage a USysVegOtherXL numeric vegetation-attribute cell draft. */
export function stageAttributeCellImpl(params: {
  disabled: boolean;
  childCapabilities: FS882ChildCapabilities;
  vegList: VegRecord[];
  plotNumber: string;
  attributeDrafts: VegetationAttributeDrafts;
  id: number;
  column: string;
  raw: string;
}): { attributeDrafts: VegetationAttributeDrafts; clearAttrError: boolean; error?: string; bumpRevision?: boolean } {
  try {
    if (params.disabled) throw new Error('Attribute editing is unavailable while loading, locked, busy or another draft is unsaved.');
    const field = vegetationAttributeField(params.column);
    if (!field || params.childCapabilities.Veg[field.key] !== true) {
      throw new Error(`Attribute column ${params.column} is unavailable in the active schema.`);
    }
    const rows = params.vegList.filter(row => row.id === params.id && row.plotNumber === params.plotNumber);
    if (rows.length !== 1) throw new Error('Vegetation row identity is missing or ambiguous; reload before editing.');
    const stored = new Map(Object.entries(rows[0])).get(field.key);
    if (stored !== null && stored !== undefined && typeof stored !== 'number') {
      throw new Error('Attribute cell has an unsupported storage type.');
    }
    return {
      attributeDrafts: stageVegetationAttribute(params.attributeDrafts, params.id, field, params.raw, stored ?? null),
      clearAttrError: true,
    };
  } catch (cause) {
    return {
      attributeDrafts: params.attributeDrafts,
      clearAttrError: false,
      error: `Vegetation attribute draft failed: ${String(cause)}`,
      bumpRevision: true,
    };
  }
}

/** Cycle Collected draft on an ordinary vegetation source row. */
export function stageCollectedCellImpl(params: {
  disabled: boolean;
  childCapabilities: FS882ChildCapabilities;
  vegList: VegRecord[];
  humusList: HumusRecord[];
  mineralList: MineralRecord[];
  otherList: OtherRecord[];
  plotNumber: string;
  collectedDrafts: CollectedDrafts;
  id: number;
  form: string;
}): { collectedDrafts: CollectedDrafts; clearCollectedError: boolean; error?: string; bumpRevision?: boolean } {
  try {
    if (params.disabled) throw new Error('Collected editing is unavailable while loading, locked, busy or another draft is unsaved.');
    if (params.childCapabilities.Veg.collected !== true) throw new Error('Collected is unavailable in the active schema.');
    const rows = params.vegList.filter(row => row.id === params.id && row.plotNumber === params.plotNumber);
    if (rows.length !== 1) throw new Error('Collected row identity is missing or ambiguous; reload before editing.');
    if (!sourceRowsFor(params.form, params.vegList, params.humusList, params.mineralList, params.otherList, params.childCapabilities).some(row => row.id === params.id)) {
      throw new Error('Collected source row is unavailable; reload before editing.');
    }
    // VegRecord omits nil Collected; the empty string remains a distinct value.
    const stored = rows[0].collected ?? null;
    return {
      collectedDrafts: stageCollected(params.collectedDrafts, params.id, stored, params.form),
      clearCollectedError: true,
    };
  } catch (cause) {
    return { collectedDrafts: params.collectedDrafts, clearCollectedError: false, error: `Collected draft failed: ${String(cause)}`, bumpRevision: true };
  }
}

/** Stage a species code draft on an existing vegetation row and clear prior choice prompts for it. */
export function stageSpeciesCellImpl(params: {
  disabled: boolean;
  childCapabilities: FS882ChildCapabilities;
  vegList: VegRecord[];
  humusList: HumusRecord[];
  mineralList: MineralRecord[];
  otherList: OtherRecord[];
  plotNumber: string;
  speciesDrafts: SpeciesDrafts;
  speciesChoices: Record<string, SpeciesChoices>;
  speciesLists: SpeciesLists;
  form: string;
  id: number;
  raw: string;
}): {
  speciesDrafts: SpeciesDrafts;
  speciesChoices: Record<string, SpeciesChoices>;
  clearSpeciesError: boolean;
  error?: string;
  bumpRevision?: boolean;
} {
  try {
    if (params.disabled) throw new Error('Species editing is unavailable while loading, locked, busy or another draft is unsaved.');
    if (params.childCapabilities.Veg.species !== true) throw new Error('Species is unavailable in the active schema.');
    const rows = params.vegList.filter(row => row.id === params.id && row.plotNumber === params.plotNumber);
    if (rows.length !== 1 || !sourceRowsFor(params.form, params.vegList, params.humusList, params.mineralList, params.otherList, params.childCapabilities).some(row => row.id === params.id)) {
      throw new Error('Species source row is missing or ambiguous; reload before editing.');
    }
    const nextDrafts = stageSpecies(params.speciesDrafts, params.form, params.id, params.raw, rows[0].species, params.speciesLists);
    const choices = { ...params.speciesChoices };
    delete choices[String(params.id)];
    return { speciesDrafts: nextDrafts, speciesChoices: choices, clearSpeciesError: true };
  } catch (cause) {
    return {
      speciesDrafts: params.speciesDrafts,
      speciesChoices: params.speciesChoices,
      clearSpeciesError: false,
      error: `Species draft failed: ${String(cause)}`,
      bumpRevision: true,
    };
  }
}

export {
  aCoverSourceNotice,
  aCoverSourceNotices,
  chooseSpecies,
  collectedDirty,
  collectedUpdates,
  heightDirty,
  heightErrors,
  heightSourceNotices,
  heightUpdates,
  otherDirty,
  otherErrors,
  otherUpdates,
  soilDirty,
  soilErrors,
  soilUpdates,
  speciesDirty,
  speciesErrors,
  speciesForms,
  speciesUpdates,
  vegetationAttributeDirty,
  vegetationAttributeErrors,
  vegetationAttributeUpdates,
  vegetationNumberUpdates,
};
export type {
  CollectedDrafts,
  HeightDrafts,
  OtherDrafts,
  OtherValue,
  SoilDrafts,
  SoilKind,
  SpeciesChoices,
  SpeciesDecisionKind,
  SpeciesDrafts,
  SpeciesLists,
  VegetationAttributeDrafts,
};
