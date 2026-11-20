import type {
  HumusRecord,
  MineralRecord,
  OtherRecord,
  PersonalSpeciesDefinitionRequest,
  VegRecord,
  VegetationCreationRequest,
  VegetationDeletionReview,
  VegetationSpeciesOption,
} from '../../bindings/github.com/boostao/vpro/app';
import type { VegetationSpeciesAlias } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
import { aCoverSourceNotice, aCoverSourceNotices } from './heightEditor';
import {
  chooseSpecies,
  speciesEventError,
  type SpeciesChoices,
  type SpeciesDrafts,
  type SpeciesLists,
} from './vegetationSpeciesEditor';
import {
  beginVegetationCreation,
  chooseVegetationCreationSpecies,
  stageVegetationCreation,
  stageVegetationCreationSpecies,
  vegetationCreationErrors,
  vegetationCreationRequest,
  vegetationCreationSpeciesError,
  type VegetationCreationDraft,
} from './vegetationCreationEditor';
import {
  beginCreationPersonalSpecies,
  beginPersonalSpecies,
  matchesCreationPersonalSpeciesSource,
  matchesPersonalSpeciesSource,
  personalSpeciesCommittedError,
  personalSpeciesErrors,
  personalSpeciesMatches,
  personalSpeciesRequest,
  type PersonalSpeciesDraft,
} from './personalSpeciesEditor';
import { validateDeletionReview } from './vegetationDeletionEditor';
import { newHumusFields, newMineralFields, newOtherFields } from './fs882FormHelpers';
import { paperChild } from './paperLayout';
import { formatError, type CancellableRead, type ReadRequests } from '../shared/readRequests';

export interface SpeciesLookupPort {
  speciesChoiceReads: ReadRequests;
  ListVegetationSpeciesAliases: (req: { code: string }) => CancellableRead<VegetationSpeciesAlias[] | null>;
  ListVegetationSpeciesUsers: (req: { code: string }) => CancellableRead<VegetationSpeciesOption[] | null>;
}

/** Lookup aliases and personal definitions for an unresolved staged species draft. */
export async function reviewSpeciesChoicesImpl(params: {
  id: number;
  speciesEditingDisabled: boolean;
  getSpeciesDrafts: () => SpeciesDrafts;
  getSpeciesChoices: () => Record<string, SpeciesChoices>;
  bumpRequest: () => number;
  currentRequest: () => number;
  port: SpeciesLookupPort;
  setDecisionBusy: (busy: boolean) => void;
  setSpeciesChoices: (choices: Record<string, SpeciesChoices>) => void;
  setError: (msg: string | null) => void;
}): Promise<void> {
  if (params.speciesEditingDisabled) {
    params.setError('Wait for available, unlocked species editing before reviewing choices.');
    return;
  }
  const cell = params.getSpeciesDrafts()[String(params.id)];
  if (!cell || !cell.error || cell.raw === '' || cell.raw.length > 8) {
    params.setError('Enter a nonempty species code of at most eight UTF-16 units before reviewing choices.');
    return;
  }
  const request = params.bumpRequest();
  params.setDecisionBusy(true);
  params.setError(null);
  try {
    const aliases = await params.port.speciesChoiceReads.track(
      params.port.ListVegetationSpeciesAliases({ code: cell.raw })
    );
    if (request !== params.currentRequest()) return;
    if (aliases === null) throw new Error('Species alias metadata was not returned.');
    const users = aliases.some((option) => option.code !== null)
      ? []
      : await params.port.speciesChoiceReads.track(params.port.ListVegetationSpeciesUsers({ code: cell.raw }));
    if (request !== params.currentRequest()) return;
    const current = params.getSpeciesDrafts()[String(params.id)];
    if (!current || current.raw !== cell.raw || current.form !== cell.form || current.expected !== cell.expected) {
      throw new Error('The species editor entry changed during lookup; review it again.');
    }
    if (users === null) throw new Error('Species personal-code metadata was not returned.');
    params.setSpeciesChoices({
      ...params.getSpeciesChoices(),
      [String(params.id)]: { form: cell.form, entered: cell.raw, aliases, users },
    });
  } catch (cause) {
    if (request === params.currentRequest()) {
      params.setError(`Species choices unavailable; draft retained: ${formatError(cause)}`);
    }
  } finally {
    if (request === params.currentRequest()) params.setDecisionBusy(false);
  }
}

/** Save a personal species definition to the user database and attach it to its source draft. */
export async function savePersonalSpeciesImpl(params: {
  proposed: PersonalSpeciesDraft | null;
  enabled: boolean;
  busy: boolean;
  headerWorkflowBusy: boolean;
  dirty: boolean;
  locked: boolean;
  capabilitiesReady: boolean;
  personalSourceMatches: (draft: PersonalSpeciesDraft) => boolean;
  speciesChoiceReads: ReadRequests;
  CreatePersonalSpeciesDefinition: (req: PersonalSpeciesDefinitionRequest) => Promise<VegetationSpeciesOption>;
  ListVegetationSpeciesUsers: (req: { code: string }) => CancellableRead<VegetationSpeciesOption[] | null>;
  ListVegetationSpeciesAliases: (req: { code: string }) => CancellableRead<VegetationSpeciesAlias[] | null>;
  getSpeciesDrafts: () => SpeciesDrafts;
  getSpeciesChoices: () => Record<string, SpeciesChoices>;
  getCreationDraft: () => VegetationCreationDraft | null;
  getSavedPersonalCodes: () => string[];
  setBusy: (b: boolean) => void;
  setError: (e: string | null) => void;
  setSuccess: (s: string | null) => void;
  setPersonalDraft: (d: PersonalSpeciesDraft | null) => void;
  setSavedPersonalCodes: (c: string[]) => void;
  setSpeciesDrafts: (d: SpeciesDrafts) => void;
  setSpeciesChoices: (c: Record<string, SpeciesChoices>) => void;
  setCreationDraft: (d: VegetationCreationDraft | null) => void;
  setCreationChoices: (c: SpeciesChoices | null) => void;
  bumpChildRevision: () => void;
  invalidateCapabilities: () => void;
}): Promise<void> {
  const proposed = params.proposed;
  if (
    !params.enabled ||
    !proposed ||
    params.busy ||
    params.headerWorkflowBusy ||
    params.dirty ||
    params.locked ||
    !params.capabilitiesReady ||
    !params.personalSourceMatches(proposed)
  ) {
    params.setError('An available unlocked personal definition and its unchanged source species draft are required.');
    return;
  }
  let committed = false;
  params.setBusy(true);
  params.setError(null);
  params.setSuccess(null);
  try {
    const request = personalSpeciesRequest(proposed);
    const definition = await params.CreatePersonalSpeciesDefinition(request);
    committed = true;
    params.setPersonalDraft(null);
    params.setSavedPersonalCodes([...new Set([...params.getSavedPersonalCodes(), proposed.entered.toUpperCase()])]);
    if (!personalSpeciesMatches(definition, request)) {
      throw new Error('Saved personal definition response differs from planned metadata.');
    }
    const [users, aliases] = await Promise.all([
      params.speciesChoiceReads.track(params.ListVegetationSpeciesUsers({ code: proposed.entered })),
      params.speciesChoiceReads.track(params.ListVegetationSpeciesAliases({ code: proposed.entered })),
    ]);
    if (
      users === null ||
      aliases === null ||
      users.filter((option) => personalSpeciesMatches(option, request)).length !== 1
    ) {
      throw new Error('Saved personal definition differs from independently reloaded metadata.');
    }
    if (!params.personalSourceMatches(proposed)) {
      throw new Error('The original plot species draft or new-row proposal changed during personal definition save.');
    }
    const reloaded = { form: proposed.form, entered: proposed.entered, users, aliases };
    if (proposed.source.kind === 'existing') {
      params.setSpeciesDrafts(
        chooseSpecies(params.getSpeciesDrafts(), proposed.source.id, reloaded, 'user', definition.code ?? undefined)
      );
      const choices = { ...params.getSpeciesChoices() };
      delete choices[String(proposed.source.id)];
      params.setSpeciesChoices(choices);
    } else {
      const cd = params.getCreationDraft();
      if (!cd) throw new Error('The original new-row proposal is unavailable after definition save.');
      params.setCreationDraft(chooseVegetationCreationSpecies(cd, reloaded, 'user', definition.code ?? undefined));
      params.setCreationChoices(null);
    }
    params.bumpChildRevision();
    params.setSuccess(
      `Personal definition ${definition.code} saved in the user database. The plot assignment is still unsaved; ${
        proposed.source.kind === 'existing' ? 'Save species drafts' : 'Save new vegetation record'
      } commits it. Undo never removes this explicitly saved definition.`
    );
  } catch (cause) {
    committed = committed || personalSpeciesCommittedError(cause);
    if (committed) {
      params.setPersonalDraft(null);
      params.invalidateCapabilities();
    }
    params.setError(
      committed
        ? `Personal definition committed, but cleanup, refresh or source verification failed. The plot was not saved; reopen it before editing: ${formatError(cause)}`
        : `Personal definition save failed; metadata and plot drafts retained: ${formatError(cause)}`
    );
  } finally {
    params.setBusy(false);
  }
}

/** Begin a vegetation creation draft from paperChild control columns. */
export function startVegetationCreationImpl(params: {
  allowed: boolean;
  form: string;
  setCreationDraft: (d: VegetationCreationDraft | null) => void;
  setCreationChoices: (c: SpeciesChoices | null) => void;
  setError: (e: string | null) => void;
  setSuccess: (s: string | null) => void;
}): void {
  if (!params.allowed) {
    params.setError(
      'Finish or cancel other drafts and load canonical species references before starting vegetation creation.'
    );
    return;
  }
  const columns = [...paperChild(params.form).controls]
    .sort((a, b) => a.tabOrder - b.tabOrder)
    .flatMap((control) => (control.column ? [control.column] : []));
  try {
    params.setCreationDraft(beginVegetationCreation(params.form, columns));
    params.setCreationChoices(null);
    params.setError(null);
    params.setSuccess(null);
  } catch (cause) {
    params.setError(`Vegetation creation could not start: ${formatError(cause)}`);
  }
}

/** Lookup aliases/users for an unresolved ordinary vegetation creation draft. */
export async function reviewCreationSpeciesChoicesImpl(params: {
  enabled: boolean;
  proposed: VegetationCreationDraft | null;
  canReview: boolean;
  bumpRequest: () => number;
  currentRequest: () => number;
  getCreationDraft: () => VegetationCreationDraft | null;
  port: SpeciesLookupPort;
  setDecisionBusy: (b: boolean) => void;
  setCreationChoices: (c: SpeciesChoices | null) => void;
  setError: (e: string | null) => void;
}): Promise<void> {
  const proposed = params.proposed;
  if (!params.enabled || !proposed || proposed.decision || !params.canReview) {
    params.setError('An available unresolved creation species entry is required before reviewing choices.');
    return;
  }
  const evErr = speciesEventError(proposed.species);
  if (evErr) {
    params.setError(evErr);
    return;
  }
  const request = params.bumpRequest();
  params.setDecisionBusy(true);
  params.setCreationChoices(null);
  params.setError(null);
  try {
    const aliases = await params.port.speciesChoiceReads.track(
      params.port.ListVegetationSpeciesAliases({ code: proposed.species })
    );
    if (request !== params.currentRequest()) return;
    if (aliases === null) throw new Error('Species alias metadata was not returned.');
    const users = aliases.some((option) => option.code !== null)
      ? []
      : await params.port.speciesChoiceReads.track(params.port.ListVegetationSpeciesUsers({ code: proposed.species }));
    if (request !== params.currentRequest()) return;
    const current = params.getCreationDraft();
    if (!current || current.form !== proposed.form || current.species !== proposed.species || current.decision) {
      throw new Error('The original creation species entry changed during lookup; review it again.');
    }
    if (users === null) throw new Error('Species personal-code metadata was not returned.');
    params.setCreationChoices({ form: proposed.form, entered: proposed.species, aliases, users });
  } catch (cause) {
    if (request === params.currentRequest()) {
      params.setError(`Creation species choices unavailable; draft retained: ${formatError(cause)}`);
    }
  } finally {
    if (request === params.currentRequest()) params.setDecisionBusy(false);
  }
}

/** Commit a staged ordinary vegetation creation draft and independently verify the allocated ID. */
export async function saveVegetationCreationImpl(params: {
  allowed: boolean;
  proposed: VegetationCreationDraft | null;
  plotNumber: string;
  speciesLists: SpeciesLists;
  CreateSourceVegetation: (plot: string, req: VegetationCreationRequest) => Promise<number>;
  loadChildData: (plot: string) => Promise<void>;
  getVegList: () => VegRecord[];
  setBusy: (b: boolean) => void;
  setError: (e: string | null) => void;
  setSuccess: (s: string | null) => void;
  clearCreation: () => void;
  invalidateCapabilities: () => void;
}): Promise<void> {
  const proposed = params.proposed;
  if (!params.allowed || !proposed) {
    params.setError('An unlocked available creation draft and canonical references are required before saving.');
    return;
  }
  let committed = false;
  params.setBusy(true);
  params.setError(null);
  params.setSuccess(null);
  try {
    const request = vegetationCreationRequest(proposed, params.speciesLists[proposed.form] ?? []);
    const id = await params.CreateSourceVegetation(params.plotNumber, request);
    committed = true;
    params.clearCreation();
    if (!Number.isInteger(id) || id <= 0 || id > 2147483647) {
      throw new Error('Creation returned an invalid allocated identity.');
    }
    await params.loadChildData(params.plotNumber);
    const observed = params.getVegList().filter((row) => row.id === id && row.plotNumber === params.plotNumber);
    if (observed.length !== 1 || observed[0].species !== request.species) {
      throw new Error('Committed creation differs from independently reloaded identity/species.');
    }
    const notice = aCoverSourceNotice(proposed.form, id, observed[0]);
    params.setSuccess(
      [
        `Vegetation row ${id} created in ${proposed.form}. No Layer or other cover values were inferred.`,
        ...(notice ? [notice] : []),
      ].join(' ')
    );
  } catch (cause) {
    if (committed) params.invalidateCapabilities();
    params.setError(
      committed
        ? `Vegetation creation committed, but refresh or identity verification failed. Reopen the plot before editing: ${formatError(cause)}`
        : `Vegetation creation failed; draft retained: ${formatError(cause)}`
    );
  } finally {
    params.setBusy(false);
  }
}

/** Review an ordinary vegetation deletion before explicit confirmation. */
export async function reviewVegetationDeletionImpl(params: {
  enabled: boolean;
  blocked: boolean;
  form: string;
  id: number;
  plotNumber: string;
  vegList: VegRecord[];
  sourceRows: (form: string) => Array<{ id: number }>;
  deletionReads: ReadRequests;
  bumpRequest: () => number;
  currentRequest: () => number;
  getPlotNumber: () => string;
  ReviewVegetationDeletion: (plot: string, form: string, id: number) => CancellableRead<VegetationDeletionReview>;
  setDeletionBusy: (b: boolean) => void;
  setDeletionReview: (r: VegetationDeletionReview | null) => void;
  setError: (e: string | null) => void;
  setSuccess: (s: string | null) => void;
}): Promise<void> {
  if (!params.enabled || params.blocked) {
    params.setError('Finish or cancel other drafts before reviewing vegetation deletion.');
    return;
  }
  const rows = params.vegList.filter((row) => row.id === params.id && row.plotNumber === params.plotNumber);
  if (rows.length !== 1 || !params.sourceRows(params.form).some((row) => row.id === params.id)) {
    params.setError('Vegetation deletion source row is missing or ambiguous; reload before reviewing.');
    return;
  }
  const species = rows[0].species;
  const plot = params.plotNumber;
  const request = params.bumpRequest();
  params.setDeletionBusy(true);
  params.setError(null);
  params.setSuccess(null);
  try {
    const reviewed = await params.deletionReads.track(params.ReviewVegetationDeletion(plot, params.form, params.id));
    if (request !== params.currentRequest()) return;
    if (params.getPlotNumber() !== plot)
      throw new Error('Vegetation deletion plot changed during lookup; reload before reviewing.');
    params.setDeletionReview(validateDeletionReview(reviewed, params.form, params.id, species));
  } catch (cause) {
    if (request === params.currentRequest()) {
      params.setError(`Vegetation deletion review failed; no data changed: ${formatError(cause)}`);
    }
  } finally {
    if (request === params.currentRequest()) params.setDeletionBusy(false);
  }
}

/** Commit an explicitly reviewed ordinary vegetation deletion. */
export async function confirmVegetationDeletionImpl(params: {
  allowed: boolean;
  reviewed: VegetationDeletionReview | null;
  plotNumber: string;
  DeleteReviewedVegetation: (
    plot: string,
    req: { id: number; form: string; expected: VegetationDeletionReview['expected'] }
  ) => Promise<void>;
  loadChildData: (plot: string) => Promise<void>;
  setBusy: (b: boolean) => void;
  setError: (e: string | null) => void;
  setSuccess: (s: string | null) => void;
  clearReview: () => void;
  invalidateCapabilities: () => void;
}): Promise<void> {
  const reviewed = params.reviewed;
  if (!params.allowed || !reviewed) {
    params.setError('Review an available, unlocked vegetation row before explicitly confirming deletion.');
    return;
  }
  let committed = false;
  params.setBusy(true);
  params.setError(null);
  params.setSuccess(null);
  try {
    await params.DeleteReviewedVegetation(params.plotNumber, {
      id: reviewed.id,
      form: reviewed.form,
      expected: reviewed.expected,
    });
    committed = true;
    params.clearReview();
    await params.loadChildData(params.plotNumber);
    params.setSuccess(`Vegetation row ${reviewed.id} deleted from all views. Its identity remains reserved.`);
  } catch (cause) {
    if (committed) params.invalidateCapabilities();
    params.setError(
      committed
        ? `Vegetation deletion committed, but refresh failed. Reopen the plot before editing: ${formatError(cause)}`
        : `Vegetation deletion failed; review retained: ${formatError(cause)}`
    );
  } finally {
    params.setBusy(false);
  }
}

/** Create a new Humus, Mineral, or Other child record through childOperation. */
export async function createChildImpl(params: {
  kind: 'humus' | 'mineral' | 'other' | null;
  first: string;
  second: string;
  plotNumber: string;
  soilUnavailable: string | null;
  setError: (e: string | null) => void;
  clearNewChild: () => void;
  childOperation: (op: () => Promise<void>) => Promise<boolean>;
  SaveHumusRecord: (rec: HumusRecord) => Promise<unknown>;
  SaveMineralRecord: (rec: MineralRecord) => Promise<unknown>;
  SaveOtherRecord: (rec: OtherRecord) => Promise<unknown>;
}): Promise<void> {
  const kind = params.kind;
  if (params.soilUnavailable && (kind === 'humus' || kind === 'mineral')) {
    params.setError(params.soilUnavailable);
    return;
  }
  let saved = false;
  if (kind === 'humus') {
    saved = await params.childOperation(async () => {
      await params.SaveHumusRecord({
        ...newHumusFields,
        id: 0,
        plotNumber: params.plotNumber,
        horizon: params.first || undefined,
        comment: params.second || undefined,
      });
    });
  } else if (kind === 'mineral') {
    saved = await params.childOperation(async () => {
      await params.SaveMineralRecord({
        ...newMineralFields,
        id: 0,
        plotNumber: params.plotNumber,
        horizon: params.first || undefined,
        comments: params.second || undefined,
      });
    });
  } else if (kind === 'other') {
    saved = await params.childOperation(async () => {
      await params.SaveOtherRecord({
        ...newOtherFields,
        id: 0,
        plotNumber: params.plotNumber,
        dataName: params.first || undefined,
        dataItem: params.second || undefined,
      });
    });
  }
  if (saved) params.clearNewChild();
}

export {
  aCoverSourceNotices,
  beginCreationPersonalSpecies,
  beginPersonalSpecies,
  chooseVegetationCreationSpecies,
  matchesCreationPersonalSpeciesSource,
  matchesPersonalSpeciesSource,
  personalSpeciesErrors,
  stageVegetationCreation,
  stageVegetationCreationSpecies,
  vegetationCreationErrors,
  vegetationCreationSpeciesError,
};
export type { PersonalSpeciesDraft, VegetationCreationDraft };
