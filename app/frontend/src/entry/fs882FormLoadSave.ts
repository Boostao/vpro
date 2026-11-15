import type {
  FS882Header,
  HumusRecord,
  MineralRecord,
  OrdinaryAuditReadEntry,
  OtherRecord,
  SoilSuggestion,
  VegRecord,
  VegetationSpeciesOption,
} from '../../bindings/github.com/boostao/vpro/app';
import type { VegetationReadAvailability } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
import {
  historicalSoilReadError,
  validateOrdinarySoilRecordIds,
  type FS882ChildCapabilities,
} from './fs882FormHelpers';
import { ordinaryNumberValue, ordinarySession, rememberOrdinarySession } from './ordinaryEditor';
import { stageSpecies, type SpeciesDrafts, type SpeciesLists } from './vegetationSpeciesEditor';
import { vegetationReadAvailability } from './vegetationReadAvailability';
import type { SIVIDeletionRestorationView } from './siviDeletionRestorationSession';
import type { EditorCloseState } from '../shell/closeLifecycle';

export interface SaveReasonInputs {
  busy: boolean;
  headerWorkflowBusy: boolean;
  capabilitiesReady: boolean;
  locked: boolean;
  siviParentActionUnsaved: boolean;
  siviParentActionClose: EditorCloseState | null;
  siviParentWriteUnsaved: boolean;
  siviParentWriteClose: EditorCloseState | null;
  siviParentSharedUnsaved: boolean;
  siviParentSharedClose: EditorCloseState | null;
  siviProjectAssignmentUnsaved: boolean;
  siviProjectAssignmentClose: EditorCloseState | null;
  siviUnsaved: boolean;
  siviClose: EditorCloseState | null;
  siviCoverUnsaved: boolean;
  siviCoverClose: EditorCloseState | null;
  siviCombinedUnsaved: boolean;
  siviCombinedClose: EditorCloseState | null;
  siviCollectedUnsaved: boolean;
  siviCollectedClose: EditorCloseState | null;
  siviSpeciesUnsaved: boolean;
  siviSpeciesClose: EditorCloseState | null;
  siviIdentityUnsaved: boolean;
  siviIdentityClose: EditorCloseState | null;
  hasPersonalDraft: boolean;
  hasDeletionReview: boolean;
  creationInvalidCount: number;
  hasCreationDraft: boolean;
  speciesReferenceReady: boolean;
  speciesReferenceBusy: boolean;
  hasNewChild: boolean;
  invalidChild: boolean;
  otherInvalidCount: number;
  soilInvalidCount: number;
  soilUnsaved: boolean;
  soilReferenceReady: boolean;
  soilReferenceBusy: boolean;
  attributeInvalidCount: number;
  attributeUnsaved: boolean;
  attributeReferenceReady: boolean;
  attributeReferenceBusy: boolean;
  speciesInvalidCount: number;
  speciesUnsaved: boolean;
  invalid: boolean;
  plotNumber: string;
}

/** Compute human-readable saveReason string for EditorCloseState. */
export function computeSaveReason(i: SaveReasonInputs): string {
  const checks: Array<[boolean, string]> = [
    [i.busy || i.headerWorkflowBusy || !i.capabilitiesReady, 'Wait for the plot to finish loading or header workflow.'],
    [i.locked, 'Unlock the plot before saving.'],
    [i.siviParentActionUnsaved && !(i.siviParentActionClose?.canSave ?? false), i.siviParentActionClose?.saveReason ?? 'Correct or Undo unresolved SIVI source actions.'],
    [i.siviParentWriteUnsaved && !(i.siviParentWriteClose?.canSave ?? false), i.siviParentWriteClose?.saveReason ?? 'Correct or Undo unresolved SIVI parent drafts.'],
    [i.siviParentSharedUnsaved && !(i.siviParentSharedClose?.canSave ?? false), i.siviParentSharedClose?.saveReason ?? 'Correct or Undo unresolved shared SIVI drafts.'],
    [i.siviProjectAssignmentUnsaved && !(i.siviProjectAssignmentClose?.canSave ?? false), i.siviProjectAssignmentClose?.saveReason ?? 'Correct or Undo unresolved ProjectID selections.'],
    [i.siviUnsaved && !(i.siviClose?.canSave ?? false), i.siviClose?.saveReason ?? 'Correct or Undo unresolved SIVI heights.'],
    [i.siviCoverUnsaved && !(i.siviCoverClose?.canSave ?? false), i.siviCoverClose?.saveReason ?? 'Correct or Undo unresolved SIVI covers.'],
    [i.siviCombinedUnsaved && !(i.siviCombinedClose?.canSave ?? false), i.siviCombinedClose?.saveReason ?? 'Correct or Undo unresolved combined SIVI drafts.'],
    [i.siviCollectedUnsaved && !(i.siviCollectedClose?.canSave ?? false), i.siviCollectedClose?.saveReason ?? 'Correct or Undo unresolved SIVI Collected cycles.'],
    [i.siviSpeciesUnsaved && !(i.siviSpeciesClose?.canSave ?? false), i.siviSpeciesClose?.saveReason ?? 'Correct or Undo unresolved SIVI Species drafts.'],
    [i.siviIdentityUnsaved && !(i.siviIdentityClose?.canSave ?? false), i.siviIdentityClose?.saveReason ?? 'Correct or Undo unresolved SIVI ID drafts.'],
    [i.hasPersonalDraft, 'Save the personal definition explicitly or Cancel its entry before saving the plot or closing.'],
    [i.hasDeletionReview, 'Confirm reviewed vegetation deletion explicitly or Cancel deletion review before saving and closing.'],
    [i.creationInvalidCount > 0, 'Correct invalid vegetation creation or Cancel creation before saving.'],
    [i.hasCreationDraft && (!i.speciesReferenceReady || i.speciesReferenceBusy), 'Restore canonical species references before saving vegetation creation.'],
    [i.hasNewChild || i.invalidChild, 'Finish or cancel child entry before saving and closing.'],
    [i.otherInvalidCount > 0, 'Correct invalid Other drafts or Cancel Other drafts before saving.'],
    [i.soilInvalidCount > 0, 'Correct invalid soil drafts or Cancel soil drafts before saving.'],
    [i.soilUnsaved && (!i.soilReferenceReady || i.soilReferenceBusy), 'Restore available soil references before saving drafts.'],
    [i.attributeInvalidCount > 0, 'Correct invalid vegetation attributes or Cancel attribute drafts before saving.'],
    [i.attributeUnsaved && (!i.attributeReferenceReady || i.attributeReferenceBusy), 'Restore available attribute references before saving drafts.'],
    [i.speciesInvalidCount > 0, 'Correct invalid species drafts or Cancel species drafts before saving.'],
    [i.speciesUnsaved && (!i.speciesReferenceReady || i.speciesReferenceBusy), 'Restore available species references before saving drafts.'],
    [i.invalid, 'Correct invalid header inputs or Undo before saving.'],
    [!i.plotNumber.trim(), 'Plot Number is required before saving.'],
  ];
  for (const [cond, msg] of checks) {
    if (cond) return msg;
  }
  return '';
}

/** Map a header validation error to the tab-specific banner prompt. */
export function computeHeaderValidationError(message: string, headerValidation: Record<string, string>): string {
  if (message === headerValidation['ordinary-veg']) return `Correct the invalid header input on Vegetation or Undo changes before saving. ${message}`;
  if (message === headerValidation['ordinary-soils']) return `Correct the invalid header input on Soils or Undo changes before saving. ${message}`;
  if (message === headerValidation['parentCodes-soils']) return `Correct the invalid header input on Soils or Undo changes before saving. ${message}`;
  if (message === headerValidation.soilDrainage) return `Correct the invalid header input on Soils or Undo changes before saving. ${message}`;
  if (message === headerValidation.soilCodes || message === headerValidation.geologyCodes) return `Correct the invalid header input on Soils or Undo changes before saving. ${message}`;
  return `Correct the invalid header input on Site or Undo changes before saving. ${message}`;
}

/** Format deletion restoration targets from SIVIDeletionRestorationView history events. */
export function formatSiviRestorationTargets(view: SIVIDeletionRestorationView | null | undefined) {
  return (view?.history?.events ?? []).map(event => ({
    historyId: event.historyId,
    restored: event.consumed,
    label: `${event.form}; Species ${event.species === null ? 'NULL' : event.species === '' ? '(empty text)' : event.species}; application ID ${event.id}; physical row ${event.rowId}; ${event.editWhen}`,
  }));
}

export interface ChildDataLoadResult {
  childCapabilities: FS882ChildCapabilities;
  vegList: VegRecord[];
  vegetationReadUnavailable: string | null;
  historicalSoilUnavailable: string | null;
  humusList: HumusRecord[];
  mineralList: MineralRecord[];
  otherList: OtherRecord[];
  auditList: OrdinaryAuditReadEntry[];
}

/** Execute parallel child reads + capability checks and normalize soil/veg unavailability states. */
export async function executeChildDataLoad(ports: {
  ordinaryVegetationUnavailable: string | null;
  ordinarySoilUnavailable: string | null;
  siviIdentityEnabled: boolean;
  readVegetationAvailability: () => Promise<VegetationReadAvailability | null>;
  listVegRecords: () => Promise<VegRecord[] | null>;
  listHumusRecords: () => Promise<HumusRecord[] | null>;
  listMineralRecords: () => Promise<MineralRecord[] | null>;
  listOtherRecords: () => Promise<OtherRecord[] | null>;
  listAuditReadEntries: () => Promise<OrdinaryAuditReadEntry[] | null>;
  getVegCaps: () => Promise<Record<string, boolean | undefined> | null>;
  getHumusCaps: () => Promise<Record<string, boolean | undefined> | null>;
  getMineralCaps: () => Promise<Record<string, boolean | undefined> | null>;
  getOtherCaps: () => Promise<Record<string, boolean | undefined> | null>;
}): Promise<ChildDataLoadResult> {
  try {
    const [v, hOutcome, mOutcome, o, a, vc, hc, mc, oc] = await Promise.all([
      ports.ordinaryVegetationUnavailable
        ? { records: [] as VegRecord[], reason: ports.ordinaryVegetationUnavailable }
        : ports.siviIdentityEnabled
          ? ports.readVegetationAvailability().then(vegetationReadAvailability)
          : ports.listVegRecords().then(records => ({ records: records ?? [], reason: null as string | null })),
      ports.ordinarySoilUnavailable
        ? { records: [] as HumusRecord[], reason: null as string | null }
        : ports.listHumusRecords().then(
            records => validateOrdinarySoilRecordIds('Humus', records ?? []),
            cause => {
              const reason = historicalSoilReadError('Humus', cause);
              if (reason) return { records: [] as HumusRecord[], reason };
              throw cause;
            },
          ),
      ports.ordinarySoilUnavailable
        ? { records: [] as MineralRecord[], reason: null as string | null }
        : ports.listMineralRecords().then(
            records => validateOrdinarySoilRecordIds('Mineral', records ?? []),
            cause => {
              const reason = historicalSoilReadError('Mineral', cause);
              if (reason) return { records: [] as MineralRecord[], reason };
              throw cause;
            },
          ),
      ports.listOtherRecords(),
      ports.listAuditReadEntries(),
      ports.getVegCaps(),
      ports.getHumusCaps(),
      ports.getMineralCaps(),
      ports.getOtherCaps(),
    ]);
    if (vc === null || hc === null || mc === null || oc === null) {
      throw new Error('Child capabilities were not returned.');
    }
    const soilHistoryReason = [hOutcome.reason, mOutcome.reason].filter(Boolean).join(' ') || null;
    return {
      childCapabilities: { Veg: vc, Humus: hc, Mineral: mc, Other: oc },
      vegList: v.records,
      vegetationReadUnavailable: v.reason,
      historicalSoilUnavailable: soilHistoryReason,
      humusList: soilHistoryReason ? [] : hOutcome.records,
      mineralList: soilHistoryReason ? [] : mOutcome.records,
      otherList: o ?? [],
      auditList: a ?? [],
    };
  } catch (e) {
    throw new Error(`Child records could not be loaded: ${String(e)}`);
  }
}

/** Shared loader for soil and vegetation-attribute suggestion metadata. */
export async function executeSuggestionLoad(params: {
  enabled: boolean;
  busy: boolean;
  missingMessage: string;
  unavailablePrefix: string;
  currentRequest: () => number;
  fetchRows: () => Promise<SoilSuggestion[] | null>;
  setBusy: (b: boolean) => void;
  setReady: (r: boolean) => void;
  setError: (e: string | null) => void;
  setSuggestions: (rows: SoilSuggestion[]) => void;
}): Promise<void> {
  if (!params.enabled || params.busy) return;
  const request = params.currentRequest();
  params.setBusy(true);
  params.setReady(false);
  params.setError(null);
  try {
    const rows = await params.fetchRows();
    if (request !== params.currentRequest()) return;
    if (rows === null) throw new Error(params.missingMessage);
    params.setSuggestions(rows);
    params.setReady(true);
  } catch (cause) {
    if (request === params.currentRequest()) params.setError(`${params.unavailablePrefix}: ${String(cause)}`);
  } finally {
    if (request === params.currentRequest()) params.setBusy(false);
  }
}

/** Load canonical per-form vegetation species lists and revalidate existing drafts. */
export async function executeSpeciesReferencesLoad(params: {
  enabled: boolean;
  busy: boolean;
  forms: readonly string[];
  currentRequest: () => number;
  fetchFormSpecies: (form: string) => Promise<VegetationSpeciesOption[] | null>;
  getSpeciesDrafts: () => SpeciesDrafts;
  setBusy: (b: boolean) => void;
  setReady: (r: boolean) => void;
  setError: (e: string | null) => void;
  setLists: (lists: SpeciesLists) => void;
  setSpeciesDrafts: (drafts: SpeciesDrafts) => void;
}): Promise<void> {
  if (!params.enabled || params.busy) return;
  const request = params.currentRequest();
  params.setBusy(true);
  params.setReady(false);
  params.setError(null);
  try {
    const rows = await Promise.all(params.forms.map(form => params.fetchFormSpecies(form)));
    if (request !== params.currentRequest()) return;
    const lists: SpeciesLists = {};
    params.forms.forEach((form, index) => {
      const options = rows[index];
      if (options === null) throw new Error(`Species metadata for ${form} was not returned.`);
      lists[form] = options;
    });
    params.setLists(lists);
    let drafts = params.getSpeciesDrafts();
    for (const [id, cell] of Object.entries(drafts)) {
      if (!cell.decision) drafts = stageSpecies(drafts, cell.form, Number(id), cell.raw, cell.expected, lists);
    }
    params.setSpeciesDrafts(drafts);
    params.setReady(true);
  } catch (cause) {
    if (request === params.currentRequest()) params.setError(`Species references unavailable: ${String(cause)}`);
  } finally {
    if (request === params.currentRequest()) params.setBusy(false);
  }
}

/** Resolve any retained external-SU prompt action when opening an FS882 host. */
export function resolveRetainedExternalSU(retained: { view: () => { blocked: boolean }; requestSourceForm: () => 'FS882-8x6XL' | 'FS882-8x6XL-CHARS' | null }, twoPageEntryReviewEnabled: boolean): { mode: 'twoPage'; sourceForm: 'FS882-8x6XL' | 'FS882-8x6XL-CHARS' } | { mode: 'external-reverse' } | null {
  if (!retained.view().blocked) return null;
  const sourceForm = retained.requestSourceForm();
  return sourceForm && twoPageEntryReviewEnabled ? { mode: 'twoPage', sourceForm } : { mode: 'external-reverse' };
}

/** Apply diagnostic humus thickness to header draft and clear ordinary string session override. */
export function applyDiagnosticHumusThicknessImpl(params: {
  disabled: boolean;
  supported: boolean;
  value: number;
  draft: FS882Header;
  original: FS882Header | null;
  setError: (e: string | null) => void;
  validateHeader: (key: string, msg: string | null) => void;
  markDirty: () => void;
  bumpRevision: () => void;
}): void {
  if (params.disabled || !params.supported || !Number.isFinite(params.value)) return;
  const field = { key: 'humusThickness' as const, column: 'HumusThickness', label: 'Humus thickness', scope: 'soils' as const, kind: 'single' as const };
  const cell = ordinaryNumberValue(field, String(params.value), params.original?.humusThickness ?? null);
  if (cell.error !== null) {
    params.setError(cell.error);
    return;
  }
  params.draft.humusThickness = cell.value;
  if (params.original) {
    const existing = ordinarySession(params.draft, params.original);
    if ('humusThickness' in existing) {
      const next = { ...existing };
      delete next.humusThickness;
      rememberOrdinarySession(params.draft, params.original, next);
    }
  }
  params.validateHeader('ordinary-soils', null);
  params.markDirty();
  params.bumpRevision();
}

/** Check whether non-arctic header fields differ between draft and original. */
export function isNonArcticHeaderDirty(dirty: boolean, draft: FS882Header, original: FS882Header | null): boolean {
  if (!dirty || !original) return dirty;
  const { snowCoverRegime: _ds, activeLayerDepth: _da, ...restDraft } = draft;
  const { snowCoverRegime: _os, activeLayerDepth: _oa, ...restOrig } = original;
  return JSON.stringify(restDraft) !== JSON.stringify(restOrig);
}
