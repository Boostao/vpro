import {
  ContextService,
  PlotEntryService,
  type FS882Header,
  type HumusRecord,
  type ListItem,
  type MineralRecord,
  type OrdinaryAuditReadEntry,
  type OtherRecord,
  type SoilSuggestion,
  type SpeciesItem,
  type VegRecord,
  type VegetationDeletionReview,
} from '../../bindings/github.com/boostao/vpro/app';
import type { bindContextPlots } from '../shared/contextPlots';
import { formatError, ReadRequests } from '../shared/readRequests';
import {
  aCoverSourceNotice,
  aCoverSourceNotices,
  cancelChildDraftsImpl,
  childOperationImpl,
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
  saveChildDraftsImpl,
  soilDirty,
  soilErrors,
  soilUpdates,
  speciesDirty,
  speciesErrors,
  speciesForms,
  speciesUpdates,
  stageAttributeCellImpl,
  stageCollectedCellImpl,
  stageHeightCellImpl,
  stageOtherCellImpl,
  stageSoilCellImpl,
  stageSpeciesCellImpl,
  vegetationAttributeDirty,
  vegetationAttributeErrors,
  vegetationAttributeUpdates,
  vegetationNumberUpdates,
  type CollectedDrafts,
  type HeightDrafts,
  type OtherDrafts,
  type OtherValue,
  type SoilDrafts,
  type SoilKind,
  type SpeciesChoices,
  type SpeciesDecisionKind,
  type SpeciesDrafts,
  type SpeciesLists,
  type VegetationAttributeDrafts,
} from './fs882FormChildren';
import {
  buildDirectSourceChildWrite,
  firstMatch,
  newVegetationFields,
  projectSourceRows,
  type FS882ChildCapabilities,
} from './fs882FormHelpers';
import { executeChildDataLoad, executeSpeciesReferencesLoad, executeSuggestionLoad } from './fs882FormLoadSave';
import {
  beginCreationPersonalSpecies,
  beginPersonalSpecies,
  chooseVegetationCreationSpecies,
  confirmVegetationDeletionImpl,
  createChildImpl,
  matchesCreationPersonalSpeciesSource,
  matchesPersonalSpeciesSource,
  personalSpeciesErrors,
  reviewCreationSpeciesChoicesImpl,
  reviewSpeciesChoicesImpl,
  reviewVegetationDeletionImpl,
  savePersonalSpeciesImpl,
  saveVegetationCreationImpl,
  stageVegetationCreation,
  stageVegetationCreationSpecies,
  startVegetationCreationImpl,
  vegetationCreationErrors,
  vegetationCreationSpeciesError,
  type PersonalSpeciesDraft,
  type VegetationCreationDraft,
} from './fs882FormVegDrafts';

export interface FS882ChildWorkflowsDeps {
  contextId: string;
  plotService: typeof PlotEntryService & ReturnType<typeof bindContextPlots>;
  reads: ReadRequests;
  getLoadRequest: () => number;
  getDraft: () => FS882Header;
  getOriginal: () => FS882Header | null;
  getBusy: () => boolean;
  setBusy: (b: boolean) => void;
  getDirty: () => boolean;
  getCapabilitiesReady: () => boolean;
  invalidateCapabilities: () => void;
  getHeaderWorkflowBusy: () => boolean;
  getChildParentDisabled: () => boolean;
  getSiviChildUnsaved: () => boolean;
  getChildUnsaved: () => boolean;
  getCurrentError: () => string | null;
  setError: (msg: string | null) => void;
  appendError: (suffix: string) => void;
  setSuccess: (msg: string | null) => void;
}

export function createFS882ChildWorkflows(deps: FS882ChildWorkflowsDeps) {
  const ordinarySoilUnavailable: string | null = null;
  const ordinaryVegetationUnavailable: string | null = null;
  const referenceReads = new ReadRequests();
  const speciesReads = new ReadRequests();
  const speciesReferenceReads = new ReadRequests();
  const speciesChoiceReads = new ReadRequests();
  const deletionReads = new ReadRequests();

  let referenceRequest = 0;
  let speciesRequest = 0;
  let speciesReferenceRequest = 0;
  let speciesChoiceRequest = 0;
  let deletionRequest = 0;

  let deletionBusy = $state(false);
  let deletionReview = $state<VegetationDeletionReview | null>(null);
  let creationDraft = $state<VegetationCreationDraft | null>(null);
  let creationChoices = $state<SpeciesChoices | null>(null);
  let personalDraft = $state<PersonalSpeciesDraft | null>(null);
  let savedPersonalCodes = $state<string[]>([]);
  let speciesDecisionBusy = $state(false);
  let speciesChoices = $state<Record<string, SpeciesChoices>>({});

  let heightDrafts = $state<HeightDrafts>({});
  let otherDrafts = $state<OtherDrafts>({});
  let soilDrafts = $state<SoilDrafts>({});
  let attributeDrafts = $state<VegetationAttributeDrafts>({});
  let collectedDrafts = $state<CollectedDrafts>({});
  let speciesDrafts = $state<SpeciesDrafts>({});

  let vegList = $state<VegRecord[]>([]);
  let humusList = $state<HumusRecord[]>([]);
  let mineralList = $state<MineralRecord[]>([]);
  let otherList = $state<OtherRecord[]>([]);
  let auditList = $state<OrdinaryAuditReadEntry[]>([]);
  let vegetationReadUnavailable = $state<string | null>(null);
  let historicalSoilUnavailable = $state<string | null>(null);
  let childCapabilities = $state<FS882ChildCapabilities>({ Veg: {}, Humus: {}, Mineral: {}, Other: {} });
  let childRevision = $state(0);

  let soilSuggestions = $state<SoilSuggestion[]>([]);
  let soilReferenceReady = $state(false);
  let soilReferenceBusy = $state(false);
  let soilReferenceError = $state<string | null>(null);

  let attributeSuggestions = $state<SoilSuggestion[]>([]);
  let attributeReferenceReady = $state(false);
  let attributeReferenceBusy = $state(false);
  let attributeReferenceError = $state<string | null>(null);

  let speciesLists = $state<SpeciesLists>({});
  let speciesReferenceReady = $state(false);
  let speciesReferenceBusy = $state(false);
  let speciesReferenceError = $state<string | null>(null);

  let moistureList = $state<ListItem[]>([]);
  let nutrientList = $state<ListItem[]>([]);
  let mesoSlopeList = $state<ListItem[]>([]);
  let surfaceShapeList = $state<ListItem[]>([]);

  let showSpeciesModal = $state(false);
  let speciesSearchQuery = $state('');
  let speciesSearchResults = $state<SpeciesItem[]>([]);
  let searchingSpecies = $state(false);
  let newChild = $state<'humus' | 'mineral' | 'other' | null>(null);

  const personalInvalid = $derived(personalDraft ? personalSpeciesErrors(personalDraft) : []);
  const heightUnsaved = $derived(heightDirty(heightDrafts));
  const heightInvalid = $derived(heightErrors(heightDrafts));
  const otherUnsaved = $derived(otherDirty(otherDrafts));
  const otherInvalid = $derived(otherErrors(otherDrafts));
  const soilUnsaved = $derived(soilDirty(soilDrafts));
  const soilInvalid = $derived(soilErrors(soilDrafts, mineralList));
  const attributeUnsaved = $derived(vegetationAttributeDirty(attributeDrafts));
  const attributeInvalid = $derived(vegetationAttributeErrors(attributeDrafts));
  const collectedUnsaved = $derived(collectedDirty(collectedDrafts));
  const speciesUnsaved = $derived(speciesDirty(speciesDrafts));
  const speciesInvalid = $derived(speciesErrors(speciesDrafts));
  const creationInvalid = $derived(
    creationDraft ? vegetationCreationErrors(creationDraft, speciesLists[creationDraft.form] ?? []) : []
  );
  const creationSpeciesInvalid = $derived(
    creationDraft ? vegetationCreationSpeciesError(creationDraft, speciesLists[creationDraft.form] ?? []) : null
  );
  const creationNotice = $derived(
    creationDraft && !Object.values(creationDraft.cells).some((cell) => cell?.error !== null)
      ? aCoverSourceNotice(
          creationDraft.form,
          'new',
          Object.fromEntries(Object.entries(creationDraft.cells).map(([field, cell]) => [field, cell?.value]))
        )
      : null
  );
  const heightNotices = $derived(heightSourceNotices(heightDrafts, vegList));
  const speciesNotices = $derived(
    aCoverSourceNotices(
      Object.entries(speciesDrafts).flatMap(([id, cell]) =>
        cell.error === null && cell.raw !== cell.expected ? [{ id: Number(id), form: cell.form }] : []
      ),
      vegList
    )
  );
  const collectedNotices = $derived(
    aCoverSourceNotices(
      Object.entries(collectedDrafts).flatMap(([id, cell]) =>
        cell.value !== cell.expected && cell.form ? [{ id: Number(id), form: cell.form }] : []
      ),
      vegList
    )
  );

  const totalTreeCover = $derived(
    vegetationReadUnavailable
      ? null
      : Math.min(
          99,
          vegList.reduce(
            (s, r) =>
              s + Math.min(99, r.totalA != null ? r.totalA : (r.cover1 || 0) + (r.cover2 || 0) + (r.cover3 || 0)),
            0
          )
        )
  );
  const totalShrubCover = $derived(
    vegetationReadUnavailable
      ? null
      : Math.min(
          99,
          vegList.reduce(
            (s, r) =>
              s +
              Math.min(
                99,
                r.totalB != null
                  ? r.totalB
                  : (r.cover4 || 0) + (r.cover5 || 0) + (r.cover5a || 0) + (r.cover5b || 0) + (r.cover5c || 0)
              ),
            0
          )
        )
  );
  const totalHerbCover = $derived(
    vegetationReadUnavailable
      ? null
      : Math.min(
          99,
          vegList.reduce((s, r) => s + Math.min(99, r.cover6 || 0), 0)
        )
  );
  const totalMossCover = $derived(
    vegetationReadUnavailable
      ? null
      : Math.min(
          99,
          vegList.reduce((s, r) => s + Math.min(99, r.cover7 || 0), 0)
        )
  );

  const anyOrdinaryUnsaved = $derived(
    heightUnsaved || otherUnsaved || soilUnsaved || attributeUnsaved || collectedUnsaved || speciesUnsaved
  );
  const anyDraftOrReviewUnsaved = $derived(anyOrdinaryUnsaved || deletionReview !== null || creationDraft !== null);
  const anyBusy = $derived(speciesDecisionBusy || deletionBusy);

  function peerDisabled(otherOrdinaryUnsaved: boolean): boolean {
    return deps.getChildParentDisabled() || deps.getSiviChildUnsaved() || otherOrdinaryUnsaved;
  }
  const heightEditingDisabled = $derived(
    peerDisabled(otherUnsaved || soilUnsaved || attributeUnsaved || collectedUnsaved || speciesUnsaved)
  );
  const otherEditingDisabled = $derived(
    peerDisabled(heightUnsaved || soilUnsaved || attributeUnsaved || collectedUnsaved || speciesUnsaved)
  );
  const soilEditingDisabled = $derived(
    Boolean(ordinarySoilUnavailable) ||
      Boolean(historicalSoilUnavailable) ||
      !soilReferenceReady ||
      soilReferenceBusy ||
      peerDisabled(heightUnsaved || otherUnsaved || attributeUnsaved || collectedUnsaved || speciesUnsaved)
  );
  const attributeEditingDisabled = $derived(
    !attributeReferenceReady ||
      attributeReferenceBusy ||
      peerDisabled(heightUnsaved || otherUnsaved || soilUnsaved || collectedUnsaved || speciesUnsaved)
  );
  const collectedEditingDisabled = $derived(
    peerDisabled(heightUnsaved || otherUnsaved || soilUnsaved || attributeUnsaved || speciesUnsaved)
  );
  const speciesEditingDisabled = $derived(
    !speciesReferenceReady ||
      speciesReferenceBusy ||
      peerDisabled(heightUnsaved || otherUnsaved || soilUnsaved || attributeUnsaved || collectedUnsaved)
  );

  function sourceRows(name: string) {
    return projectSourceRows(name, { vegList, humusList, mineralList, otherList, childCapabilities });
  }

  async function loadChildData(p: string) {
    const request = deps.getLoadRequest();
    const outcome = await executeChildDataLoad({
      ordinaryVegetationUnavailable,
      ordinarySoilUnavailable,
      siviIdentityEnabled: true,
      readVegetationAvailability: () =>
        deps.reads.track(ContextService.GetVegetationReadAvailability(deps.contextId, p)),
      listVegRecords: () => deps.reads.track(deps.plotService.ListVegRecords(p)),
      listHumusRecords: () => deps.reads.track(deps.plotService.ListHumusRecords(p)),
      listMineralRecords: () => deps.reads.track(deps.plotService.ListMineralRecords(p)),
      listOtherRecords: () => deps.reads.track(deps.plotService.ListOtherRecords(p)),
      listAuditReadEntries: () => deps.reads.track(deps.plotService.ListAuditReadEntries(p)),
      getVegCaps: () => deps.reads.track(deps.plotService.GetChildCapabilities('Veg')),
      getHumusCaps: () => deps.reads.track(deps.plotService.GetChildCapabilities('Humus')),
      getMineralCaps: () => deps.reads.track(deps.plotService.GetChildCapabilities('Mineral')),
      getOtherCaps: () => deps.reads.track(deps.plotService.GetChildCapabilities('Other')),
    });
    if (request !== deps.getLoadRequest()) return;
    childCapabilities = outcome.childCapabilities;
    vegList = outcome.vegList;
    vegetationReadUnavailable = outcome.vegetationReadUnavailable;
    historicalSoilUnavailable = outcome.historicalSoilUnavailable;
    humusList = outcome.humusList;
    mineralList = outcome.mineralList;
    otherList = outcome.otherList;
    auditList = outcome.auditList;
    childRevision += 1;
  }

  async function loadReferenceLists() {
    referenceRequest += 1;
    const request = referenceRequest;
    referenceReads.cancelAll();
    try {
      const [m, n, ms, ss] = await Promise.all([
        referenceReads.track(PlotEntryService.GetListItems('MoistureRegime')),
        referenceReads.track(PlotEntryService.GetListItems('NutrientRegime')),
        referenceReads.track(PlotEntryService.GetListItems('MesoSlopePosition')),
        referenceReads.track(PlotEntryService.GetListItems('SurfaceShape')),
      ]);
      if (request !== referenceRequest) return;
      moistureList = m ?? [];
      nutrientList = n ?? [];
      mesoSlopeList = ms ?? [];
      surfaceShapeList = ss ?? [];
    } catch (e) {
      if (request === referenceRequest) deps.setError(`Reference lists could not be loaded: ${formatError(e)}`);
    }
  }

  function childOperation(operation: () => Promise<void>) {
    return childOperationImpl(
      {
        busy: deps.getBusy(),
        headerWorkflowBusy: deps.getHeaderWorkflowBusy(),
        capabilitiesReady: deps.getCapabilitiesReady(),
        locked: deps.getDraft().locked,
        hasOriginal: Boolean(deps.getOriginal()),
        plotNumber: deps.getDraft().plotNumber,
        dirty: deps.getDirty(),
        childUnsaved: deps.getChildUnsaved(),
        setBusy: deps.setBusy,
        setError: deps.setError,
        appendError: deps.appendError,
        setSuccess: deps.setSuccess,
        invalidateCapabilities: deps.invalidateCapabilities,
        loadChildData,
      },
      operation
    );
  }

  async function searchSpecies() {
    speciesRequest += 1;
    const request = speciesRequest;
    speciesReads.cancelAll();
    if (!speciesSearchQuery.trim()) {
      speciesSearchResults = [];
      searchingSpecies = false;
      return;
    }
    searchingSpecies = true;
    try {
      const res = await speciesReads.track(PlotEntryService.SearchSpecies(speciesSearchQuery, 15));
      if (request !== speciesRequest) return;
      speciesSearchResults = res ?? [];
    } catch (e) {
      if (request === speciesRequest) deps.setError(`Species search failed: ${formatError(e)}`);
    } finally {
      if (request === speciesRequest) searchingSpecies = false;
    }
  }

  async function selectSpeciesToAdd(sp: SpeciesItem) {
    if (
      await childOperation(() =>
        deps.plotService.SaveVegRecord({
          ...newVegetationFields,
          id: 0,
          plotNumber: deps.getDraft().plotNumber,
          species: sp.code,
          layer: 'A',
          cover1: 0,
          totalA: 0,
        })
      )
    ) {
      showSpeciesModal = false;
      speciesSearchQuery = '';
      speciesSearchResults = [];
    }
  }

  function loadSpeciesReferences() {
    return executeSpeciesReferencesLoad({
      enabled: true,
      busy: speciesReferenceBusy,
      forms: speciesForms,
      currentRequest: () => speciesReferenceRequest,
      fetchFormSpecies: (form) => speciesReferenceReads.track(deps.plotService.ListVegetationSpecies(form)),
      getSpeciesDrafts: () => speciesDrafts,
      setBusy: (b) => {
        speciesReferenceBusy = b;
      },
      setReady: (r) => {
        speciesReferenceReady = r;
      },
      setError: (e) => {
        speciesReferenceError = e;
      },
      setLists: (l) => {
        speciesLists = l;
      },
      setSpeciesDrafts: (d) => {
        speciesDrafts = d;
      },
    });
  }

  function loadSoilSuggestions() {
    if (ordinarySoilUnavailable || soilReferenceBusy) return Promise.resolve();
    return executeSuggestionLoad({
      enabled: true,
      busy: soilReferenceBusy,
      missingMessage: 'Soil reference metadata was not returned.',
      unavailablePrefix: 'Soil reference suggestions unavailable',
      currentRequest: () => referenceRequest,
      fetchRows: () => referenceReads.track(deps.plotService.ListSoilSuggestions()),
      setBusy: (b) => {
        soilReferenceBusy = b;
      },
      setReady: (r) => {
        soilReferenceReady = r;
      },
      setError: (e) => {
        soilReferenceError = e;
      },
      setSuggestions: (r) => {
        soilSuggestions = r;
      },
    });
  }

  function loadAttributeSuggestions() {
    return executeSuggestionLoad({
      enabled: true,
      busy: attributeReferenceBusy,
      missingMessage: 'Vegetation attribute reference metadata was not returned.',
      unavailablePrefix: 'Vegetation attribute references unavailable',
      currentRequest: () => referenceRequest,
      fetchRows: () => referenceReads.track(deps.plotService.ListVegetationAttributeSuggestions()),
      setBusy: (b) => {
        attributeReferenceBusy = b;
      },
      setReady: (r) => {
        attributeReferenceReady = r;
      },
      setError: (e) => {
        attributeReferenceError = e;
      },
      setSuggestions: (r) => {
        attributeSuggestions = r;
      },
    });
  }

  function stageSpeciesCell(form: string, id: number, raw: string) {
    const res = stageSpeciesCellImpl({
      disabled: speciesEditingDisabled,
      childCapabilities,
      vegList,
      humusList,
      mineralList,
      otherList,
      plotNumber: deps.getDraft().plotNumber,
      speciesDrafts,
      speciesChoices,
      speciesLists,
      form,
      id,
      raw,
    });
    speciesDrafts = res.speciesDrafts;
    speciesChoices = res.speciesChoices;
    if (res.error) deps.setError(res.error);
    else {
      deps.setSuccess(null);
      if (res.clearSpeciesError && deps.getCurrentError()?.startsWith('Species ')) deps.setError(null);
    }
    if (res.bumpRevision) childRevision += 1;
  }
  function reviewSpeciesChoices(id: number) {
    return reviewSpeciesChoicesImpl({
      id,
      speciesEditingDisabled,
      getSpeciesDrafts: () => speciesDrafts,
      getSpeciesChoices: () => speciesChoices,
      bumpRequest: () => {
        speciesChoiceRequest += 1;
        return speciesChoiceRequest;
      },
      currentRequest: () => speciesChoiceRequest,
      port: {
        speciesChoiceReads,
        ListVegetationSpeciesAliases: (req) => deps.plotService.ListVegetationSpeciesAliases(req),
        ListVegetationSpeciesUsers: (req) => deps.plotService.ListVegetationSpeciesUsers(req),
      },
      setDecisionBusy: (b) => {
        speciesDecisionBusy = b;
      },
      setSpeciesChoices: (c) => {
        speciesChoices = c;
      },
      setError: deps.setError,
    });
  }
  function chooseSpeciesCode(id: number, kind: SpeciesDecisionKind, selected?: string) {
    try {
      if (speciesEditingDisabled)
        throw new Error('Wait for available, unlocked species editing before selecting a decision.');
      const choices = speciesChoices[String(id)];
      if (!choices) throw new Error('Review the current species entry before selecting a decision.');
      speciesDrafts = chooseSpecies(speciesDrafts, id, choices, kind, selected);
      const next = { ...speciesChoices };
      delete next[String(id)];
      speciesChoices = next;
      deps.setError(null);
      deps.setSuccess(null);
      childRevision += 1;
    } catch (cause) {
      deps.setError(`Species decision failed; draft retained: ${formatError(cause)}`);
    }
  }
  function cancelSpeciesDrafts() {
    return cancelChildDraftsImpl({
      guardBlocked: personalDraft !== null || deps.getBusy() || deps.getHeaderWorkflowBusy(),
      guardMessage:
        personalDraft !== null
          ? 'Cancel personal definition entry before cancelling plot species drafts.'
          : 'Wait for the current operation before cancelling species drafts.',
      clearDrafts: () => {
        speciesDrafts = {};
        speciesChoices = {};
      },
      bumpRevision: () => {
        childRevision += 1;
      },
      plotNumber: deps.getDraft().plotNumber,
      loadChildData,
      successMessage: savedPersonalCodes.length
        ? 'Plot species drafts cancelled. No plot data or project history changed; explicitly saved personal definitions remain available.'
        : 'Species drafts cancelled. Stored data and history were unchanged; current rows reloaded.',
      reloadErrorMessage: 'Species drafts cancelled, but rows could not be reloaded. Reopen the plot',
      setBusy: deps.setBusy,
      setError: deps.setError,
      setSuccess: deps.setSuccess,
      invalidateCapabilities: deps.invalidateCapabilities,
    });
  }
  function startPersonalSpecies(id: number) {
    try {
      if (speciesEditingDisabled)
        throw new Error(
          'Personal definition creation is unavailable while loading, locked or another workflow is active.'
        );
      const cell = speciesDrafts[String(id)];
      const choices = speciesChoices[String(id)];
      if (!cell || !choices)
        throw new Error('Review the current unknown code before creating its personal definition.');
      personalDraft = beginPersonalSpecies(id, cell, choices);
      deps.setError(null);
      deps.setSuccess(null);
    } catch (cause) {
      deps.setError(`Personal definition could not start: ${formatError(cause)}`);
    }
  }
  function cancelPersonalSpecies() {
    if (deps.getBusy() || deps.getHeaderWorkflowBusy()) {
      deps.setError('Wait for the personal definition operation before cancelling entry.');
      return;
    }
    personalDraft = null;
    deps.setError(null);
    deps.setSuccess(
      'Personal definition entry cancelled without writes. The original plot species draft or new-row proposal is retained.'
    );
  }
  function personalSourceMatches(proposed: PersonalSpeciesDraft): boolean {
    return proposed.source.kind === 'existing'
      ? matchesPersonalSpeciesSource(proposed, speciesDrafts[String(proposed.source.id)])
      : proposed.source.kind === 'creation' && matchesCreationPersonalSpeciesSource(proposed, creationDraft);
  }
  function savePersonalSpecies() {
    return savePersonalSpeciesImpl({
      proposed: personalDraft,
      enabled: true,
      busy: deps.getBusy(),
      headerWorkflowBusy: deps.getHeaderWorkflowBusy(),
      dirty: deps.getDirty(),
      locked: deps.getDraft().locked,
      capabilitiesReady: deps.getCapabilitiesReady(),
      personalSourceMatches,
      speciesChoiceReads,
      CreatePersonalSpeciesDefinition: (req) => deps.plotService.CreatePersonalSpeciesDefinition(req),
      ListVegetationSpeciesUsers: (req) => deps.plotService.ListVegetationSpeciesUsers(req),
      ListVegetationSpeciesAliases: (req) => deps.plotService.ListVegetationSpeciesAliases(req),
      getSpeciesDrafts: () => speciesDrafts,
      getSpeciesChoices: () => speciesChoices,
      getCreationDraft: () => creationDraft,
      getSavedPersonalCodes: () => savedPersonalCodes,
      setBusy: deps.setBusy,
      setError: deps.setError,
      setSuccess: deps.setSuccess,
      setPersonalDraft: (d) => {
        personalDraft = d;
      },
      setSavedPersonalCodes: (c) => {
        savedPersonalCodes = c;
      },
      setSpeciesDrafts: (d) => {
        speciesDrafts = d;
      },
      setSpeciesChoices: (c) => {
        speciesChoices = c;
      },
      setCreationDraft: (d) => {
        creationDraft = d;
      },
      setCreationChoices: (c) => {
        creationChoices = c;
      },
      bumpChildRevision: () => {
        childRevision += 1;
      },
      invalidateCapabilities: deps.invalidateCapabilities,
    });
  }
  function saveSpeciesDrafts() {
    const updates = speciesUpdates(speciesDrafts);
    return saveChildDraftsImpl({
      disabled: speciesEditingDisabled,
      guardMessage: 'Save a clean, unlocked header with available species references before saving.',
      hasUpdates: updates.length > 0,
      noChangeMessage: 'No species values changed.',
      clearEmpty: () => {
        speciesDrafts = {};
      },
      commit: () => deps.plotService.UpdateVegetationSpecies(deps.getDraft().plotNumber, updates),
      clearOnCommit: () => {
        speciesDrafts = {};
        speciesChoices = {};
      },
      plotNumber: deps.getDraft().plotNumber,
      loadChildData,
      buildSuccessMessage: () =>
        [`Saved ${updates.length} species row drafts.`, ...aCoverSourceNotices(updates, vegList)].join(' '),
      committedRefreshPrefix: 'Species changes committed, but refresh failed. Reopen the plot before editing',
      failedPrefix: 'Species save failed; drafts retained',
      setBusy: deps.setBusy,
      setError: deps.setError,
      setSuccess: deps.setSuccess,
      invalidateCapabilities: deps.invalidateCapabilities,
    });
  }

  function stageCollectedCell(id: number, form: string) {
    const res = stageCollectedCellImpl({
      disabled: collectedEditingDisabled,
      childCapabilities,
      vegList,
      humusList,
      mineralList,
      otherList,
      plotNumber: deps.getDraft().plotNumber,
      collectedDrafts,
      id,
      form,
    });
    collectedDrafts = res.collectedDrafts;
    if (res.error) deps.setError(res.error);
    else {
      deps.setSuccess(null);
      if (res.clearCollectedError && deps.getCurrentError()?.startsWith('Collected ')) deps.setError(null);
    }
    if (res.bumpRevision) childRevision += 1;
  }
  function cancelCollectedDrafts() {
    return cancelChildDraftsImpl({
      guardBlocked: deps.getBusy() || deps.getHeaderWorkflowBusy(),
      guardMessage: 'Wait for the current operation before cancelling Collected drafts.',
      clearDrafts: () => {
        collectedDrafts = {};
      },
      bumpRevision: () => {
        childRevision += 1;
      },
      plotNumber: deps.getDraft().plotNumber,
      loadChildData,
      successMessage: 'Collected drafts cancelled. Stored data and history were unchanged; current rows reloaded.',
      reloadErrorMessage: 'Collected drafts cancelled, but current rows could not be reloaded. Reopen the plot',
      setBusy: deps.setBusy,
      setError: deps.setError,
      setSuccess: deps.setSuccess,
      invalidateCapabilities: deps.invalidateCapabilities,
    });
  }
  function saveCollectedDrafts() {
    const updates = collectedUpdates(collectedDrafts);
    const sources = updates.map(({ id }) => ({ id, form: collectedDrafts[String(id)].form ?? '' }));
    return saveChildDraftsImpl({
      disabled: collectedEditingDisabled,
      guardMessage: 'Save a clean, unlocked header before saving Collected drafts.',
      hasUpdates: updates.length > 0,
      noChangeMessage: 'No Collected values changed.',
      clearEmpty: () => {
        collectedDrafts = {};
      },
      commit: () => deps.plotService.UpdateCollectedRecords(deps.getDraft().plotNumber, updates),
      clearOnCommit: () => {
        collectedDrafts = {};
      },
      plotNumber: deps.getDraft().plotNumber,
      loadChildData,
      buildSuccessMessage: () =>
        [`Saved ${updates.length} Collected row drafts.`, ...aCoverSourceNotices(sources, vegList)].join(' '),
      committedRefreshPrefix: 'Collected changes committed, but refresh failed. Reopen the plot before editing',
      failedPrefix: 'Collected save failed; drafts retained',
      setBusy: deps.setBusy,
      setError: deps.setError,
      setSuccess: deps.setSuccess,
      invalidateCapabilities: deps.invalidateCapabilities,
    });
  }

  function startVegetationCreation(form: string) {
    startVegetationCreationImpl({
      allowed: Boolean(
        !deps.getChildParentDisabled() && !deps.getChildUnsaved() && speciesReferenceReady && !speciesReferenceBusy
      ),
      form,
      setCreationDraft: (d) => {
        creationDraft = d;
      },
      setCreationChoices: (c) => {
        creationChoices = c;
      },
      setError: deps.setError,
      setSuccess: deps.setSuccess,
    });
  }
  function stageCreationCell(column: string, raw: string) {
    if (!creationDraft || personalDraft !== null || deps.getBusy() || deps.getHeaderWorkflowBusy()) {
      deps.setError('An available creation draft without personal metadata entry is required before editing.');
      return;
    }
    try {
      creationDraft = stageVegetationCreation(creationDraft, column, raw);
      deps.setError(null);
      deps.setSuccess(null);
    } catch (cause) {
      deps.setError(`Vegetation creation input rejected: ${formatError(cause)}`);
    }
  }
  function stageCreationSpecies(raw: string) {
    if (!creationDraft || personalDraft !== null || deps.getBusy() || deps.getHeaderWorkflowBusy()) {
      deps.setError('An available creation draft without personal metadata entry is required before editing species.');
      return;
    }
    creationDraft = stageVegetationCreationSpecies(creationDraft, raw);
    creationChoices = null;
    deps.setError(null);
    deps.setSuccess(null);
  }
  function reviewCreationSpeciesChoices() {
    return reviewCreationSpeciesChoicesImpl({
      enabled: true,
      proposed: creationDraft,
      canReview: Boolean(
        creationDraft &&
        !creationDraft.decision &&
        personalDraft === null &&
        !deps.getBusy() &&
        !deps.getHeaderWorkflowBusy() &&
        !deps.getDraft().locked &&
        deps.getCapabilitiesReady() &&
        speciesReferenceReady &&
        !speciesReferenceBusy &&
        creationSpeciesInvalid
      ),
      bumpRequest: () => {
        speciesChoiceRequest += 1;
        return speciesChoiceRequest;
      },
      currentRequest: () => speciesChoiceRequest,
      getCreationDraft: () => creationDraft,
      port: {
        speciesChoiceReads,
        ListVegetationSpeciesAliases: (req) => deps.plotService.ListVegetationSpeciesAliases(req),
        ListVegetationSpeciesUsers: (req) => deps.plotService.ListVegetationSpeciesUsers(req),
      },
      setDecisionBusy: (b) => {
        speciesDecisionBusy = b;
      },
      setCreationChoices: (c) => {
        creationChoices = c;
      },
      setError: deps.setError,
    });
  }
  function chooseCreationSpecies(kind: SpeciesDecisionKind, selected?: string) {
    try {
      if (
        !creationDraft ||
        !creationChoices ||
        personalDraft !== null ||
        deps.getBusy() ||
        deps.getHeaderWorkflowBusy() ||
        deps.getDraft().locked ||
        !deps.getCapabilitiesReady()
      ) {
        throw new Error('Review the available unlocked creation entry before selecting a decision.');
      }
      creationDraft = chooseVegetationCreationSpecies(creationDraft, creationChoices, kind, selected);
      creationChoices = null;
      deps.setError(null);
      deps.setSuccess(null);
    } catch (cause) {
      deps.setError(`Creation species decision failed; draft retained: ${formatError(cause)}`);
    }
  }
  function startCreationPersonalSpecies() {
    try {
      if (
        !creationDraft ||
        !creationChoices ||
        !creationSpeciesInvalid ||
        personalDraft !== null ||
        deps.getBusy() ||
        deps.getHeaderWorkflowBusy() ||
        deps.getDraft().locked ||
        !deps.getCapabilitiesReady() ||
        !speciesReferenceReady ||
        speciesReferenceBusy
      ) {
        throw new Error('Review the available unlocked unknown creation code before creating its personal definition.');
      }
      personalDraft = beginCreationPersonalSpecies(creationDraft, creationChoices);
      deps.setError(null);
      deps.setSuccess(null);
    } catch (cause) {
      deps.setError(`Creation personal definition could not start: ${formatError(cause)}`);
    }
  }
  function cancelVegetationCreation() {
    return cancelChildDraftsImpl({
      guardBlocked: personalDraft !== null || deps.getBusy() || deps.getHeaderWorkflowBusy(),
      guardMessage:
        personalDraft !== null
          ? 'Cancel personal definition entry before cancelling the new-row proposal.'
          : 'Wait for the current operation before cancelling creation.',
      clearDrafts: () => {
        creationDraft = null;
        creationChoices = null;
      },
      plotNumber: deps.getDraft().plotNumber,
      loadChildData,
      successMessage: savedPersonalCodes.length
        ? 'Vegetation creation cancelled. No project data or history changed; explicitly saved personal definitions remain available.'
        : 'Vegetation creation cancelled. No stored data or history changed; current rows reloaded.',
      reloadErrorMessage: 'Creation cancelled, but rows could not be reloaded. Reopen the plot',
      setBusy: deps.setBusy,
      setError: deps.setError,
      setSuccess: deps.setSuccess,
      invalidateCapabilities: deps.invalidateCapabilities,
    });
  }
  function saveVegetationCreation() {
    return saveVegetationCreationImpl({
      allowed: Boolean(
        creationDraft &&
        personalDraft === null &&
        !deps.getBusy() &&
        !deps.getHeaderWorkflowBusy() &&
        !deps.getDirty() &&
        !deps.getDraft().locked &&
        deps.getCapabilitiesReady() &&
        deps.getOriginal() !== null &&
        speciesReferenceReady &&
        !speciesReferenceBusy
      ),
      proposed: creationDraft,
      plotNumber: deps.getDraft().plotNumber,
      speciesLists,
      CreateSourceVegetation: (p, r) => deps.plotService.CreateSourceVegetation(p, r),
      loadChildData,
      getVegList: () => vegList,
      setBusy: deps.setBusy,
      setError: deps.setError,
      setSuccess: deps.setSuccess,
      clearCreation: () => {
        creationDraft = null;
        creationChoices = null;
      },
      invalidateCapabilities: deps.invalidateCapabilities,
    });
  }

  function reviewVegetationDeletion(form: string, id: number) {
    return reviewVegetationDeletionImpl({
      enabled: true,
      blocked: deps.getChildParentDisabled() || deps.getChildUnsaved(),
      form,
      id,
      plotNumber: deps.getDraft().plotNumber,
      vegList,
      sourceRows,
      deletionReads,
      bumpRequest: () => {
        deletionRequest += 1;
        return deletionRequest;
      },
      currentRequest: () => deletionRequest,
      getPlotNumber: () => deps.getDraft().plotNumber,
      ReviewVegetationDeletion: (p, f, rowId) => deps.plotService.ReviewVegetationDeletion(p, f, rowId),
      setDeletionBusy: (b) => {
        deletionBusy = b;
      },
      setDeletionReview: (r) => {
        deletionReview = r;
      },
      setError: deps.setError,
      setSuccess: deps.setSuccess,
    });
  }
  function cancelVegetationDeletion() {
    return cancelChildDraftsImpl({
      guardBlocked: deps.getBusy() || deps.getHeaderWorkflowBusy(),
      guardMessage: 'Wait for the current operation before cancelling deletion review.',
      clearDrafts: () => {
        deletionReview = null;
      },
      plotNumber: deps.getDraft().plotNumber,
      loadChildData,
      successMessage: 'Vegetation deletion cancelled. No stored data or history changed; current rows reloaded.',
      reloadErrorMessage: 'Deletion review cancelled, but rows could not be reloaded. Reopen the plot',
      setBusy: deps.setBusy,
      setError: deps.setError,
      setSuccess: deps.setSuccess,
      invalidateCapabilities: deps.invalidateCapabilities,
    });
  }
  function confirmVegetationDeletion() {
    return confirmVegetationDeletionImpl({
      allowed: Boolean(
        deletionReview &&
        !deps.getBusy() &&
        !deps.getHeaderWorkflowBusy() &&
        !deps.getDirty() &&
        !deps.getDraft().locked &&
        deps.getCapabilitiesReady() &&
        deps.getOriginal() !== null
      ),
      reviewed: deletionReview,
      plotNumber: deps.getDraft().plotNumber,
      DeleteReviewedVegetation: (p, r) => deps.plotService.DeleteReviewedVegetation(p, r),
      loadChildData,
      setBusy: deps.setBusy,
      setError: deps.setError,
      setSuccess: deps.setSuccess,
      clearReview: () => {
        deletionReview = null;
      },
      invalidateCapabilities: deps.invalidateCapabilities,
    });
  }

  function stageHeightCell(id: number, col: string, raw: string, form: string) {
    const res = stageHeightCellImpl({
      enabled: true,
      disabled: heightEditingDisabled,
      childCapabilities,
      vegList,
      humusList,
      mineralList,
      otherList,
      plotNumber: deps.getDraft().plotNumber,
      heightDrafts,
      id,
      column: col,
      raw,
      form,
    });
    heightDrafts = res.heightDrafts;
    if (res.error) deps.setError(res.error);
    else deps.setSuccess(null);
    if (res.bumpRevision) childRevision += 1;
  }
  function cancelHeightDrafts() {
    return cancelChildDraftsImpl({
      guardBlocked: deps.getBusy() || deps.getHeaderWorkflowBusy(),
      guardMessage: 'Wait for the current operation before cancelling height drafts.',
      clearDrafts: () => {
        heightDrafts = {};
      },
      bumpRevision: () => {
        childRevision += 1;
      },
      plotNumber: deps.getDraft().plotNumber,
      loadChildData,
      successMessage: 'Height drafts cancelled. Stored data and history were unchanged; current rows reloaded.',
      reloadErrorMessage: 'Height drafts cancelled, but current rows could not be reloaded. Reopen the plot',
      setBusy: deps.setBusy,
      setError: deps.setError,
      setSuccess: deps.setSuccess,
      invalidateCapabilities: deps.invalidateCapabilities,
    });
  }
  function saveHeightDrafts() {
    const updates = heightUpdates(heightDrafts);
    const notices = heightSourceNotices(heightDrafts, vegList);
    return saveChildDraftsImpl({
      disabled: heightEditingDisabled,
      guardMessage: 'Save a clean, unlocked header before saving height drafts.',
      hasUpdates: updates.length > 0,
      noChangeMessage: 'No height values changed.',
      clearEmpty: () => {
        heightDrafts = {};
      },
      commit: () =>
        deps.plotService.UpdateVegetationNumbers(deps.getDraft().plotNumber, vegetationNumberUpdates(heightDrafts)),
      clearOnCommit: () => {
        heightDrafts = {};
      },
      plotNumber: deps.getDraft().plotNumber,
      loadChildData,
      buildSuccessMessage: () =>
        `Saved ${updates.length} height/cover row drafts.${notices.length ? ' ' + notices.join(' ') : ''}`,
      committedRefreshPrefix: 'Height changes committed, but refresh failed. Reopen the plot before editing',
      failedPrefix: 'Height save failed; drafts retained',
      setBusy: deps.setBusy,
      setError: deps.setError,
      setSuccess: deps.setSuccess,
      invalidateCapabilities: deps.invalidateCapabilities,
    });
  }

  function stageOtherCell(id: number, col: string, raw: OtherValue) {
    const res = stageOtherCellImpl({
      disabled: otherEditingDisabled,
      childCapabilities,
      otherList,
      plotNumber: deps.getDraft().plotNumber,
      otherDrafts,
      id,
      column: col,
      raw,
    });
    otherDrafts = res.otherDrafts;
    if (res.error) deps.setError(res.error);
    else {
      deps.setSuccess(null);
      if (res.clearOtherError && deps.getCurrentError()?.startsWith('Other ')) deps.setError(null);
    }
    if (res.bumpRevision) childRevision += 1;
  }
  function cancelOtherDrafts() {
    return cancelChildDraftsImpl({
      guardBlocked: deps.getBusy() || deps.getHeaderWorkflowBusy(),
      guardMessage: 'Wait for the current operation before cancelling Other drafts.',
      clearDrafts: () => {
        otherDrafts = {};
      },
      bumpRevision: () => {
        childRevision += 1;
      },
      plotNumber: deps.getDraft().plotNumber,
      loadChildData,
      successMessage: 'Other drafts cancelled. Stored data and history were unchanged; current rows reloaded.',
      reloadErrorMessage: 'Other drafts cancelled, but current rows could not be reloaded. Reopen the plot',
      setBusy: deps.setBusy,
      setError: deps.setError,
      setSuccess: deps.setSuccess,
      invalidateCapabilities: deps.invalidateCapabilities,
    });
  }
  function saveOtherDrafts() {
    const updates = otherUpdates(otherDrafts);
    return saveChildDraftsImpl({
      disabled: otherEditingDisabled,
      guardMessage: 'Save a clean, unlocked header before saving Other drafts.',
      hasUpdates: updates.length > 0,
      noChangeMessage: 'No Other values changed.',
      clearEmpty: () => {
        otherDrafts = {};
      },
      commit: () => deps.plotService.UpdateOtherRecords(deps.getDraft().plotNumber, updates),
      clearOnCommit: () => {
        otherDrafts = {};
      },
      plotNumber: deps.getDraft().plotNumber,
      loadChildData,
      buildSuccessMessage: () => `Saved ${updates.length} Other row drafts.`,
      committedRefreshPrefix: 'Other changes committed, but refresh failed. Reopen the plot before editing',
      failedPrefix: 'Other save failed; drafts retained',
      setBusy: deps.setBusy,
      setError: deps.setError,
      setSuccess: deps.setSuccess,
      invalidateCapabilities: deps.invalidateCapabilities,
    });
  }

  function stageSoilCell(kind: SoilKind, id: number, col: string, raw: string) {
    if (soilEditingDisabled) {
      deps.setError(
        'Soil draft failed: Error: Soil editing is unavailable while loading, locked, busy or another draft is unsaved.'
      );
      childRevision += 1;
      return;
    }
    const res = stageSoilCellImpl({
      disabled: soilEditingDisabled,
      childCapabilities,
      humusList,
      mineralList,
      plotNumber: deps.getDraft().plotNumber,
      soilDrafts,
      kind,
      id,
      column: col,
      raw,
    });
    soilDrafts = res.soilDrafts;
    if (res.error) deps.setError(res.error);
    else {
      deps.setSuccess(null);
      if (res.clearSoilError && deps.getCurrentError()?.startsWith('Soil ')) deps.setError(null);
    }
    if (res.bumpRevision) childRevision += 1;
  }
  function cancelSoilDrafts() {
    return cancelChildDraftsImpl({
      guardBlocked: deps.getBusy() || deps.getHeaderWorkflowBusy(),
      guardMessage: 'Wait for the current operation before cancelling soil drafts.',
      clearDrafts: () => {
        soilDrafts = {};
      },
      bumpRevision: () => {
        childRevision += 1;
      },
      plotNumber: deps.getDraft().plotNumber,
      loadChildData,
      successMessage: 'Soil drafts cancelled. Stored data and history were unchanged; current rows reloaded.',
      reloadErrorMessage: 'Soil drafts cancelled, but current rows could not be reloaded. Reopen the plot',
      setBusy: deps.setBusy,
      setError: deps.setError,
      setSuccess: deps.setSuccess,
      invalidateCapabilities: deps.invalidateCapabilities,
    });
  }
  function saveSoilDrafts() {
    if (soilEditingDisabled) {
      deps.setError('Save a clean, unlocked header with available references before saving soil drafts.');
      return Promise.resolve();
    }
    const updates = soilUpdates(soilDrafts, mineralList);
    return saveChildDraftsImpl({
      disabled: soilEditingDisabled,
      guardMessage: 'Save a clean, unlocked header with available references before saving soil drafts.',
      hasUpdates: updates.length > 0,
      noChangeMessage: 'No soil values changed.',
      clearEmpty: () => {
        soilDrafts = {};
      },
      commit: () => deps.plotService.UpdateSoilRecords(deps.getDraft().plotNumber, updates),
      clearOnCommit: () => {
        soilDrafts = {};
      },
      plotNumber: deps.getDraft().plotNumber,
      loadChildData,
      buildSuccessMessage: () => `Saved ${updates.length} Humus/Mineral row drafts.`,
      committedRefreshPrefix: 'Soil changes committed, but refresh failed. Reopen the plot before editing',
      failedPrefix: 'Soil save failed; drafts retained',
      setBusy: deps.setBusy,
      setError: deps.setError,
      setSuccess: deps.setSuccess,
      invalidateCapabilities: deps.invalidateCapabilities,
    });
  }

  function stageAttributeCell(id: number, col: string, raw: string) {
    const res = stageAttributeCellImpl({
      disabled: attributeEditingDisabled,
      childCapabilities,
      vegList,
      plotNumber: deps.getDraft().plotNumber,
      attributeDrafts,
      id,
      column: col,
      raw,
    });
    attributeDrafts = res.attributeDrafts;
    if (res.error) deps.setError(res.error);
    else {
      deps.setSuccess(null);
      if (res.clearAttrError && deps.getCurrentError()?.startsWith('Vegetation attribute ')) deps.setError(null);
    }
    if (res.bumpRevision) childRevision += 1;
  }
  function cancelAttributeDrafts() {
    return cancelChildDraftsImpl({
      guardBlocked: deps.getBusy() || deps.getHeaderWorkflowBusy(),
      guardMessage: 'Wait for the current operation before cancelling attribute drafts.',
      clearDrafts: () => {
        attributeDrafts = {};
      },
      bumpRevision: () => {
        childRevision += 1;
      },
      plotNumber: deps.getDraft().plotNumber,
      loadChildData,
      successMessage:
        'Vegetation attribute drafts cancelled. Stored data and history were unchanged; current rows reloaded.',
      reloadErrorMessage: 'Vegetation attribute drafts cancelled, but rows could not be reloaded. Reopen the plot',
      setBusy: deps.setBusy,
      setError: deps.setError,
      setSuccess: deps.setSuccess,
      invalidateCapabilities: deps.invalidateCapabilities,
    });
  }
  function saveAttributeDrafts() {
    const updates = vegetationAttributeUpdates(attributeDrafts);
    return saveChildDraftsImpl({
      disabled: attributeEditingDisabled,
      guardMessage: 'Save a clean, unlocked header with available references before saving attribute drafts.',
      hasUpdates: updates.length > 0,
      noChangeMessage: 'No vegetation attribute values changed.',
      clearEmpty: () => {
        attributeDrafts = {};
      },
      commit: () => deps.plotService.UpdateVegetationAttributes(deps.getDraft().plotNumber, updates),
      clearOnCommit: () => {
        attributeDrafts = {};
      },
      plotNumber: deps.getDraft().plotNumber,
      loadChildData,
      buildSuccessMessage: () => `Saved ${updates.length} vegetation attribute row drafts.`,
      committedRefreshPrefix: 'Vegetation attributes committed, but refresh failed. Reopen the plot before editing',
      failedPrefix: 'Vegetation attribute save failed; drafts retained',
      setBusy: deps.setBusy,
      setError: deps.setError,
      setSuccess: deps.setSuccess,
      invalidateCapabilities: deps.invalidateCapabilities,
    });
  }

  async function editSourceChild(name: string, id: number, column: string, raw: string) {
    if (ordinaryVegetationUnavailable && name.startsWith('SubVeg')) {
      deps.setError(ordinaryVegetationUnavailable);
      return;
    }
    const soilUnavailable = ordinarySoilUnavailable ?? historicalSoilUnavailable;
    if (soilUnavailable && (name === 'SoilHumusXL' || name === 'SoilMineralXL')) {
      deps.setError(soilUnavailable);
      return;
    }
    try {
      if (name.startsWith('SubVeg') && column.toLowerCase() === 'species') {
        throw new Error(
          'Species requires the source-list draft workflow; unrestricted source-grid edits are unavailable.'
        );
      }
      await childOperation(
        buildDirectSourceChildWrite(
          name,
          id,
          column,
          raw,
          { vegList, humusList, mineralList, otherList },
          deps.plotService
        )
      );
    } catch (cause) {
      deps.setError(`Child input failed: ${formatError(cause)}`);
    }
  }

  function openNewChild(kind: 'humus' | 'mineral' | 'other') {
    if (kind === 'other' ? otherEditingDisabled || otherUnsaved : soilEditingDisabled || soilUnsaved) {
      deps.setError('Save or cancel drafts and wait for an unlocked, available child workflow before adding a row.');
      return;
    }
    deps.setError(null);
    newChild = kind;
  }

  async function deleteSourceChild(name: string, id: number) {
    const childEditingDisabled = deps.getChildParentDisabled() || deps.getChildUnsaved();
    if (childEditingDisabled || (name.startsWith('Soil') && soilEditingDisabled)) {
      deps.setError('Save or cancel drafts and wait for an unlocked, available child workflow before deleting a row.');
      return;
    }
    if (!window.confirm(`Delete this ${name} record?`)) return;
    const plot = deps.getDraft().plotNumber;
    if (name.startsWith('SubVeg')) await childOperation(() => deps.plotService.DeleteVegRecord(plot, id));
    else if (name === 'SoilHumusXL') await childOperation(() => deps.plotService.DeleteHumusRecord(plot, id));
    else if (name === 'SoilMineralXL') await childOperation(() => deps.plotService.DeleteMineralRecord(plot, id));
    else if (name === 'SubOtherXL') await childOperation(() => deps.plotService.DeleteOtherRecord(plot, id));
    else deps.setError(`Deletion is not migrated for ${name}.`);
  }

  async function createChild(first: string, second: string) {
    const soilUnavailable = ordinarySoilUnavailable ?? historicalSoilUnavailable;
    await createChildImpl({
      kind: newChild,
      first,
      second,
      plotNumber: deps.getDraft().plotNumber,
      soilUnavailable,
      setError: deps.setError,
      clearNewChild: () => {
        newChild = null;
      },
      childOperation,
      SaveHumusRecord: (r) => deps.plotService.SaveHumusRecord(r),
      SaveMineralRecord: (r) => deps.plotService.SaveMineralRecord(r),
      SaveOtherRecord: (r) => deps.plotService.SaveOtherRecord(r),
    });
  }

  function resetForPlot() {
    heightDrafts = {};
    otherDrafts = {};
    soilDrafts = {};
    attributeDrafts = {};
    collectedDrafts = {};
    speciesDrafts = {};
    speciesChoices = {};
    deletionReview = null;
    creationDraft = null;
    creationChoices = null;
    personalDraft = null;
    savedPersonalCodes = [];
    vegList = [];
    vegetationReadUnavailable = null;
    historicalSoilUnavailable = null;
    humusList = [];
    mineralList = [];
    otherList = [];
    auditList = [];
    childCapabilities = { Veg: {}, Humus: {}, Mineral: {}, Other: {} };
  }

  function disposeAll() {
    referenceRequest += 1;
    speciesRequest += 1;
    speciesReferenceRequest += 1;
    speciesChoiceRequest += 1;
    deletionRequest += 1;
    for (const r of [referenceReads, speciesReads, speciesReferenceReads, speciesChoiceReads, deletionReads])
      r.cancelAll();
  }

  function saveDraftHandler(): (() => Promise<void | boolean>) | null {
    return firstMatch<() => Promise<void | boolean>>([
      [() => creationDraft !== null, () => saveVegetationCreation()],
      [() => heightUnsaved, () => saveHeightDrafts()],
      [() => otherUnsaved, () => saveOtherDrafts()],
      [() => soilUnsaved, () => saveSoilDrafts()],
      [() => attributeUnsaved, () => saveAttributeDrafts()],
      [() => collectedUnsaved, () => saveCollectedDrafts()],
      [() => speciesUnsaved, () => saveSpeciesDrafts()],
    ]);
  }

  function undoDraftHandler(): (() => void) | null {
    return firstMatch<() => void>([
      [() => personalDraft !== null, () => cancelPersonalSpecies()],
      [() => deletionReview !== null, () => void cancelVegetationDeletion()],
      [() => creationDraft !== null, () => void cancelVegetationCreation()],
      [() => heightUnsaved, () => void cancelHeightDrafts()],
      [() => otherUnsaved, () => void cancelOtherDrafts()],
      [() => soilUnsaved, () => void cancelSoilDrafts()],
      [() => attributeUnsaved, () => void cancelAttributeDrafts()],
      [() => collectedUnsaved, () => void cancelCollectedDrafts()],
      [() => speciesUnsaved, () => void cancelSpeciesDrafts()],
    ]);
  }

  function lockBlockedReason(): string | null {
    return firstMatch<string>([
      [
        () => personalDraft !== null,
        'Save the personal definition explicitly or Cancel its entry before changing the plot lock.',
      ],
      [() => creationDraft !== null, 'Save or Cancel vegetation creation before changing the plot lock.'],
      [() => deletionReview !== null, 'Confirm or Cancel vegetation deletion review before changing the plot lock.'],
      [() => heightUnsaved, 'Save or Cancel height drafts before changing the plot lock.'],
      [() => otherUnsaved, 'Save or Cancel Other drafts before changing the plot lock.'],
      [() => soilUnsaved, 'Save or Cancel soil drafts before changing the plot lock.'],
      [() => attributeUnsaved, 'Save or Cancel vegetation attribute drafts before changing the plot lock.'],
      [() => collectedUnsaved, 'Save or Cancel Collected drafts before changing the plot lock.'],
      [() => speciesUnsaved, 'Save or Cancel species drafts before changing the plot lock.'],
    ]);
  }

  function hasInvalidDrafts(): boolean {
    return (
      heightInvalid.length > 0 ||
      otherInvalid.length > 0 ||
      soilInvalid.length > 0 ||
      attributeInvalid.length > 0 ||
      speciesInvalid.length > 0 ||
      deletionReview !== null ||
      creationInvalid.length > 0
    );
  }

  function saveReasonFields() {
    return {
      hasPersonalDraft: personalDraft !== null,
      hasDeletionReview: deletionReview !== null,
      creationInvalidCount: creationInvalid.length,
      hasCreationDraft: creationDraft !== null,
      speciesReferenceReady,
      speciesReferenceBusy,
      hasNewChild: newChild !== null,
      otherInvalidCount: otherInvalid.length,
      soilInvalidCount: soilInvalid.length,
      soilUnsaved,
      soilReferenceReady,
      soilReferenceBusy,
      attributeInvalidCount: attributeInvalid.length,
      attributeUnsaved,
      attributeReferenceReady,
      attributeReferenceBusy,
      speciesInvalidCount: speciesInvalid.length,
      speciesUnsaved,
    };
  }

  return {
    ordinarySoilUnavailable,
    ordinaryVegetationUnavailable,
    get vegList() {
      return vegList;
    },
    set vegList(v: VegRecord[]) {
      vegList = v;
    },
    get humusList() {
      return humusList;
    },
    get mineralList() {
      return mineralList;
    },
    get otherList() {
      return otherList;
    },
    get auditList() {
      return auditList;
    },
    get childCapabilities() {
      return childCapabilities;
    },
    get childRevision() {
      return childRevision;
    },
    set childRevision(v: number) {
      childRevision = v;
    },
    get vegetationReadUnavailable() {
      return vegetationReadUnavailable;
    },
    get historicalSoilUnavailable() {
      return historicalSoilUnavailable;
    },
    set historicalSoilUnavailable(v: string | null) {
      historicalSoilUnavailable = v;
    },
    get totalTreeCover() {
      return totalTreeCover;
    },
    get totalShrubCover() {
      return totalShrubCover;
    },
    get totalHerbCover() {
      return totalHerbCover;
    },
    get totalMossCover() {
      return totalMossCover;
    },
    get lists() {
      return {
        moistureRegime: moistureList,
        nutrientRegime: nutrientList,
        mesoSlopePos: mesoSlopeList,
        surfaceShape: surfaceShapeList,
      };
    },
    get showSpeciesModal() {
      return showSpeciesModal;
    },
    set showSpeciesModal(v: boolean) {
      showSpeciesModal = v;
    },
    get speciesSearchQuery() {
      return speciesSearchQuery;
    },
    set speciesSearchQuery(v: string) {
      speciesSearchQuery = v;
    },
    get speciesSearchResults() {
      return speciesSearchResults;
    },
    get searchingSpecies() {
      return searchingSpecies;
    },
    get newChild() {
      return newChild;
    },
    set newChild(v: 'humus' | 'mineral' | 'other' | null) {
      newChild = v;
    },
    get heightDrafts() {
      return heightDrafts;
    },
    set heightDrafts(v: HeightDrafts) {
      heightDrafts = v;
    },
    get heightUnsaved() {
      return heightUnsaved;
    },
    get heightInvalid() {
      return heightInvalid;
    },
    get heightNotices() {
      return heightNotices;
    },
    get heightEditingDisabled() {
      return heightEditingDisabled;
    },
    get otherDrafts() {
      return otherDrafts;
    },
    set otherDrafts(v: OtherDrafts) {
      otherDrafts = v;
    },
    get otherUnsaved() {
      return otherUnsaved;
    },
    get otherInvalid() {
      return otherInvalid;
    },
    get otherEditingDisabled() {
      return otherEditingDisabled;
    },
    get soilDrafts() {
      return soilDrafts;
    },
    set soilDrafts(v: SoilDrafts) {
      soilDrafts = v;
    },
    get soilUnsaved() {
      return soilUnsaved;
    },
    get soilInvalid() {
      return soilInvalid;
    },
    get soilSuggestions() {
      return soilSuggestions;
    },
    get soilReferenceReady() {
      return soilReferenceReady;
    },
    set soilReferenceReady(v: boolean) {
      soilReferenceReady = v;
    },
    get soilReferenceBusy() {
      return soilReferenceBusy;
    },
    set soilReferenceBusy(v: boolean) {
      soilReferenceBusy = v;
    },
    get soilReferenceError() {
      return soilReferenceError;
    },
    get soilEditingDisabled() {
      return soilEditingDisabled;
    },
    get attributeDrafts() {
      return attributeDrafts;
    },
    set attributeDrafts(v: VegetationAttributeDrafts) {
      attributeDrafts = v;
    },
    get attributeUnsaved() {
      return attributeUnsaved;
    },
    get attributeInvalid() {
      return attributeInvalid;
    },
    get attributeSuggestions() {
      return attributeSuggestions;
    },
    get attributeReferenceBusy() {
      return attributeReferenceBusy;
    },
    set attributeReferenceBusy(v: boolean) {
      attributeReferenceBusy = v;
    },
    get attributeReferenceError() {
      return attributeReferenceError;
    },
    get attributeEditingDisabled() {
      return attributeEditingDisabled;
    },
    get collectedDrafts() {
      return collectedDrafts;
    },
    set collectedDrafts(v: CollectedDrafts) {
      collectedDrafts = v;
    },
    get collectedUnsaved() {
      return collectedUnsaved;
    },
    get collectedNotices() {
      return collectedNotices;
    },
    get collectedEditingDisabled() {
      return collectedEditingDisabled;
    },
    get speciesDrafts() {
      return speciesDrafts;
    },
    set speciesDrafts(v: SpeciesDrafts) {
      speciesDrafts = v;
    },
    get speciesChoices() {
      return speciesChoices;
    },
    get speciesLists() {
      return speciesLists;
    },
    get speciesUnsaved() {
      return speciesUnsaved;
    },
    get speciesInvalid() {
      return speciesInvalid;
    },
    get speciesNotices() {
      return speciesNotices;
    },
    get speciesDecisionBusy() {
      return speciesDecisionBusy;
    },
    get speciesReferenceReady() {
      return speciesReferenceReady;
    },
    get speciesReferenceBusy() {
      return speciesReferenceBusy;
    },
    set speciesReferenceBusy(v: boolean) {
      speciesReferenceBusy = v;
    },
    get speciesReferenceError() {
      return speciesReferenceError;
    },
    get speciesEditingDisabled() {
      return speciesEditingDisabled;
    },
    get personalDraft() {
      return personalDraft;
    },
    set personalDraft(v: PersonalSpeciesDraft | null) {
      personalDraft = v;
    },
    get personalInvalid() {
      return personalInvalid;
    },
    get savedPersonalCodes() {
      return savedPersonalCodes;
    },
    get creationDraft() {
      return creationDraft;
    },
    set creationDraft(v: VegetationCreationDraft | null) {
      creationDraft = v;
    },
    get creationChoices() {
      return creationChoices;
    },
    get creationInvalid() {
      return creationInvalid;
    },
    get creationSpeciesInvalid() {
      return creationSpeciesInvalid;
    },
    get creationNotice() {
      return creationNotice;
    },
    get deletionReview() {
      return deletionReview;
    },
    set deletionReview(v: VegetationDeletionReview | null) {
      deletionReview = v;
    },
    get anyOrdinaryUnsaved() {
      return anyOrdinaryUnsaved;
    },
    get anyDraftOrReviewUnsaved() {
      return anyDraftOrReviewUnsaved;
    },
    get anyBusy() {
      return anyBusy;
    },
    sourceRows,
    loadChildData,
    loadReferenceLists,
    loadSpeciesReferences,
    loadSoilSuggestions,
    loadAttributeSuggestions,
    searchSpecies,
    selectSpeciesToAdd,
    stageSpeciesCell,
    reviewSpeciesChoices,
    chooseSpeciesCode,
    cancelSpeciesDrafts,
    startPersonalSpecies,
    cancelPersonalSpecies,
    savePersonalSpecies,
    saveSpeciesDrafts,
    stageCollectedCell,
    cancelCollectedDrafts,
    saveCollectedDrafts,
    startVegetationCreation,
    stageCreationCell,
    stageCreationSpecies,
    reviewCreationSpeciesChoices,
    chooseCreationSpecies,
    startCreationPersonalSpecies,
    cancelVegetationCreation,
    saveVegetationCreation,
    reviewVegetationDeletion,
    cancelVegetationDeletion,
    confirmVegetationDeletion,
    stageHeightCell,
    cancelHeightDrafts,
    saveHeightDrafts,
    stageOtherCell,
    cancelOtherDrafts,
    saveOtherDrafts,
    stageSoilCell,
    cancelSoilDrafts,
    saveSoilDrafts,
    stageAttributeCell,
    cancelAttributeDrafts,
    saveAttributeDrafts,
    editSourceChild,
    openNewChild,
    deleteSourceChild,
    deleteVeg: (id: number) => deleteSourceChild('SubVegAXL_BC', id),
    deleteHumus: (id: number) => deleteSourceChild('SoilHumusXL', id),
    createChild,
    resetForPlot,
    disposeAll,
    saveDraftHandler,
    undoDraftHandler,
    lockBlockedReason,
    hasInvalidDrafts,
    saveReasonFields,
  };
}

export type FS882ChildWorkflowsController = ReturnType<typeof createFS882ChildWorkflows>;
