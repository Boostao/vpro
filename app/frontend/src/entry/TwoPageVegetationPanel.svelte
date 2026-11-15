<script lang="ts">
  import { tick, untrack } from 'svelte';
  import { twoPageVegetationSession, twoPageVegetationWritingEnabled, twoPageVegetationSpeciesListEnabled } from './twoPageVegetationSessions';
  import { vegetationColumnIndex, vegetationSourceCell, type TwoPageVegetationForm } from './twoPageVegetationWire';
  import { metadataCellText } from '../admin/projectMetadataEditor';
  import { collectedNext } from './collectedEditor';
  import { enterNavigationMode } from './enterNavigation';
  import { twoPageVegetationGroups, twoPageVegetationStoredText, twoPageVegetationRowDiagnostic, twoPageVegetationHasColumn } from './twoPageVegetationPresentation';
  import VegetationSpeciesReferences from './VegetationSpeciesReferences.svelte';
  import { vegetationSpeciesListOptions, vegetationSpeciesListHasCommonCover } from './twoPageVegetationSpeciesList';

  interface VegetationCrudPort {
    createRow(contextId: string, req: {
      requestId: string; plotNumber: string; form: string; species: string;
      layer?: string | null; collected?: string | null; covers: Record<string, number | null>;
    }): Promise<{ requestId: string; rowId: string; id: number; species: string }>;
    deleteRow(contextId: string, req: {
      requestId: string; plotNumber: string; form: string; id: number; rowId?: string;
    }): Promise<{ requestId: string; deletedId: number; species: string }>;
    restoreRow(contextId: string, req: {
      requestId: string; plotNumber: string; form: string; deleteRequestId: string;
    }): Promise<{ requestId: string; restoredId: number; restoredRowId: string; species: string }>;
    listDeletedRows(contextId: string, plot: string, form: string): Promise<Array<{
      deleteRequestId: string; plotNumber: string; form: string; deletedId: number;
      species: string; layer: string; deletedBy: string; deletedAt: string; restored: boolean;
    }> | null>;
  }

  let { vegetationCrudPort, contextId, project, plot, form, parentBlocked }: {
    vegetationCrudPort?: VegetationCrudPort;
    contextId: string; project: string; plot: string; form: TwoPageVegetationForm; parentBlocked: boolean;
  } = $props();
  const session = $derived(twoPageVegetationSession({ contextId, project, plot, form }));
  let revision = $state(0);
  let error = $state<string | null>(null);
  let statusMsg = $state<string | null>(null);
  let panel = $state<HTMLElement>();
  let crudBusy = $state(false);
  let createOpen = $state(false);
  let createSpecies = $state('');
  let createLayer = $state('');
  let createCollected = $state('');
  let deleteConfirmRowId = $state<string | null>(null);
  let deletedHistoryOpen = $state(false);
  let deletedRows = $state<Array<{
    deleteRequestId: string; plotNumber: string; form: string; deletedId: number;
    species: string; layer: string; deletedBy: string; deletedAt: string; restored: boolean;
  }>>([]);
  let crudGeneration = 0;
  $effect(() => session.subscribe(() => untrack(() => revision++)));
  const view = $derived.by(() => { revision; return session.view(); });
  const selected = $derived(view.selectedRowId);
  const close = $derived.by(() => { revision; return session.closeState(); });
  const row = $derived(selected === null
    ? view.original?.records.rows.find(row => row.rowId === view.original?.sourceRowIds[0]) ?? view.original?.records.rows[0]
    : view.original?.records.rows.find(row => row.rowId === selected));
  const diagnostic = $derived(view.original && row ? twoPageVegetationRowDiagnostic(view.original, row.rowId) : null);
  const fieldsDisabled = $derived(parentBlocked || !twoPageVegetationWritingEnabled || view.busy ||
    view.blocked || view.acknowledgementRequired || !!diagnostic);
  const speciesListAvailable = $derived(twoPageVegetationSpeciesListEnabled && (form === 'SubVegAXL_BC' || form === 'SubVegAXL'));
  const speciesOptions = $derived(speciesListAvailable && view.references
    ? vegetationSpeciesListOptions(view.references, { contextId, project, plot, form }) : []);
  const speciesWarningUnavailable = $derived(speciesListAvailable && view.original && row
    ? !vegetationSpeciesListHasCommonCover(view.original, row.rowId) : false);

  function pickSpecies(plannedRow: string, event: Event) {
    try {
      const select = event.currentTarget;
      if (!speciesListAvailable || speciesWarningUnavailable || fieldsDisabled || !row || row.rowId !== plannedRow || !panel ||
        panel.dataset.vegetationCurrentRow !== plannedRow || !(select instanceof HTMLSelectElement) ||
        select.disabled || !select.checkVisibility() || !panel.contains(select) ||
        !speciesOptions.some(option => option.code === select.value)) {
        throw new Error('Observed Species list control, physical row or exact code differs from the planned selection.');
      }
      stage('Species', select.value, false);
    } catch (cause) { error = `Species list selection refused without mutation: ${String(cause)}`; }
  }

  function selectRow(rowId: string) {
    try {
      if (!view.original?.records.rows.some(row => row.rowId === rowId)) throw new Error('Observed physical vegetation row is unavailable.');
      session.select(rowId); error = null;
    } catch (cause) { error = `Vegetation selection refused without mutation: ${String(cause)}`; }
  }
  function stage(column: string, raw: string, nullValue: boolean) {
    try {
      if (fieldsDisabled || !row) throw new Error('Resolve parent/other-owner operations and unlock the plot before linked vegetation staging.');
      session.stage(row.rowId, column, raw, nullValue); error = null;
    } catch (cause) { error = `Linked vegetation draft refused; owned state retained: ${String(cause)}`; }
  }
  function cycleCollected(plannedRow: string, event: MouseEvent) {
    try {
      if (fieldsDisabled || !row || row.rowId !== plannedRow || !view.original || !panel ||
        panel.dataset.twoPageVegetationPanel !== form || panel.dataset.vegetationCurrentRow !== plannedRow) {
        throw new Error('Observed vegetation owner/physical row differs from the planned Collected click.');
      }
      const button = event.currentTarget;
      const input = panel.querySelector<HTMLInputElement>('[data-vegetation-column="Collected"] input[type="text"]');
      if (!(button instanceof HTMLButtonElement) || button.disabled || !panel.contains(button) ||
        !button.checkVisibility() || !input || input.disabled || !input.checkVisibility()) {
        throw new Error('Observed Collected controls are unavailable; no source value was cycled.');
      }
      const draft = view.drafts[JSON.stringify([plannedRow, 'Collected'])];
      const source = draft?.value ?? vegetationSourceCell(view.original, plannedRow, 'Collected');
      if (draft?.error || source.storage !== 'null' && source.storage !== 'text') {
        throw new Error('Correct Collected validation/nontext storage manually before its source click.');
      }
      const raw = draft?.raw ?? metadataCellText(source);
      if (input.value !== (source.storage === 'null' ? '' : raw.replace(/[\r\n]/g, ''))) {
        throw new Error('Observed Collected display differs from its retained draft/original.');
      }
      const next = collectedNext(source.storage === 'null' ? null : source.text);
      stage('Collected', next ?? '', next === null);
    } catch (cause) { error = `Source Collected click refused without mutation: ${String(cause)}`; }
  }
  async function operation(action: 'load' | 'references' | 'save' | 'recover' | 'undo' | 'acknowledge' | 'cancel') {
    const owned = session;
    try {
      if (parentBlocked && (action === 'load' || action === 'references' || action === 'save')) throw new Error('Finish actual parent/other-owner drafts and unlock the plot before loading or saving linked vegetation.');
      error = null;
      if (action === 'undo') session.undo();
      else if (action === 'acknowledge') session.acknowledge();
      else if (action === 'cancel') session.cancel();
      else {
        const ok = action === 'load' ? await owned.load()
          : action === 'references' ? await owned.loadReferences()
          : action === 'save' ? await owned.save(crypto.randomUUID()) : await owned.resolve();
        if (owned !== session) return;
        if (!ok) error = action === 'references' ? owned.view().referenceError : owned.view().error;
      }
    } catch (cause) {
      if (owned === session) error = `Linked vegetation operation refused; owned state retained: ${String(cause)}`;
    }
  }

  async function resolveCrudPort(): Promise<VegetationCrudPort> {
    if (vegetationCrudPort) return vegetationCrudPort;
    const { PlotEntryService } = await import('../../bindings/github.com/boostao/vpro/app');
    return {
      createRow: (cid, req) => PlotEntryService.CreateTwoPageVegetationRow(cid, req as never),
      deleteRow: (cid, req) => PlotEntryService.DeleteTwoPageVegetationRow(cid, req as never),
      restoreRow: (cid, req) => PlotEntryService.RestoreTwoPageVegetationRow(cid, req as never),
      listDeletedRows: (cid, p, f) => PlotEntryService.ListTwoPageVegetationDeletedRows(cid, p, f),
    };
  }

  async function submitCreateRow() {
    if (fieldsDisabled || close.unsaved || close.blocked || crudBusy || !view.original) {
      error = 'Save or Undo pending vegetation drafts before creating a row.';
      return;
    }
    const species = createSpecies.trim();
    if (!species) {
      error = 'Species code is required to create a vegetation row.';
      return;
    }
    const owned = session;
    const gen = ++crudGeneration;
    crudBusy = true;
    error = null;
    statusMsg = null;
    try {
      const port = await resolveCrudPort();
      const created = await port.createRow(contextId, {
        requestId: crypto.randomUUID(),
        plotNumber: plot,
        form,
        species,
        layer: createLayer.trim() || null,
        collected: createCollected.trim() || null,
        covers: {},
      });
      if (gen !== crudGeneration || owned !== session) return;
      createOpen = false;
      createSpecies = '';
      createLayer = '';
      createCollected = '';
      await owned.load();
      if (owned === session && created.rowId) owned.select(created.rowId);
      statusMsg = `Created vegetation row for ${created.species}.`;
    } catch (cause) {
      if (owned === session) error = `Create vegetation row refused: ${String(cause)}`;
    } finally {
      if (gen === crudGeneration) crudBusy = false;
    }
  }

  async function confirmDeleteRow() {
    if (fieldsDisabled || close.unsaved || close.blocked || crudBusy || !view.original || !row || deleteConfirmRowId !== row.rowId) {
      error = 'Resolve drafts and confirm the selected row before deleting.';
      return;
    }
    const idText = twoPageVegetationStoredText(view.original, row.rowId, 'ID');
    const numericId = Number(idText);
    if (!Number.isSafeInteger(numericId)) {
      error = `Cannot delete physical row ${row.rowId}: invalid application ID ${JSON.stringify(idText)}.`;
      return;
    }
    const owned = session;
    const gen = ++crudGeneration;
    crudBusy = true;
    error = null;
    statusMsg = null;
    try {
      const port = await resolveCrudPort();
      const deleted = await port.deleteRow(contextId, {
        requestId: crypto.randomUUID(),
        plotNumber: plot,
        form,
        id: numericId,
        rowId: row.rowId,
      });
      if (gen !== crudGeneration || owned !== session) return;
      deleteConfirmRowId = null;
      await owned.load();
      statusMsg = `Deleted vegetation row ${deleted.deletedId} (${deleted.species}).`;
    } catch (cause) {
      if (owned === session) error = `Delete vegetation row refused: ${String(cause)}`;
    } finally {
      if (gen === crudGeneration) crudBusy = false;
    }
  }

  async function loadDeletedRows() {
    if (parentBlocked || view.busy || crudBusy) return;
    const gen = ++crudGeneration;
    crudBusy = true;
    error = null;
    try {
      const port = await resolveCrudPort();
      const list = await port.listDeletedRows(contextId, plot, form);
      if (gen !== crudGeneration) return;
      deletedRows = list ?? [];
      deletedHistoryOpen = true;
    } catch (cause) {
      error = `Could not load deleted vegetation rows: ${String(cause)}`;
    } finally {
      if (gen === crudGeneration) crudBusy = false;
    }
  }

  async function restoreDeletedRow(deleteRequestId: string) {
    if (fieldsDisabled || close.unsaved || close.blocked || crudBusy) return;
    const owned = session;
    const gen = ++crudGeneration;
    crudBusy = true;
    error = null;
    statusMsg = null;
    try {
      const port = await resolveCrudPort();
      const restored = await port.restoreRow(contextId, {
        requestId: crypto.randomUUID(),
        plotNumber: plot,
        form,
        deleteRequestId,
      });
      if (gen !== crudGeneration || owned !== session) return;
      await owned.load();
      if (owned === session && restored.restoredRowId) owned.select(restored.restoredRowId);
      const list = await port.listDeletedRows(contextId, plot, form);
      if (gen === crudGeneration) deletedRows = list ?? [];
      statusMsg = `Restored vegetation row ${restored.restoredId} (${restored.species}).`;
    } catch (cause) {
      if (owned === session) error = `Restore vegetation row refused: ${String(cause)}`;
    } finally {
      if (gen === crudGeneration) crudBusy = false;
    }
  }

  async function enterRecord(event: KeyboardEvent, column: string) {
    if (event.key !== 'Enter' || event.defaultPrevented || event.isComposing || event.repeat ||
        event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
    event.preventDefault();
    try {
      if (fieldsDisabled || close.blocked || !row || !view.original || !panel || enterNavigationMode(form) !== 'record') {
        throw new Error('Correct retained validation and resolve parent/vegetation operations before source record navigation.');
      }
      const control = event.currentTarget;
      if (!(control instanceof HTMLInputElement) || control !== event.target ||
          document.activeElement !== control || !panel.contains(control) || !control.checkVisibility() || control.disabled ||
          control.closest<HTMLElement>('[data-vegetation-column]')?.dataset.vegetationColumn !== column ||
          panel.dataset.twoPageVegetationPanel !== form || panel.dataset.vegetationCurrentRow !== row.rowId) {
        throw new Error('Observed Enter focus/control/physical owner differs from its planned vegetation field.');
      }
      if (typeof panel.querySelectorAll === 'function') {
        const inputs = Array.from(
          panel.querySelectorAll<HTMLInputElement>('[data-vegetation-column] input[type="text"]'),
        ).filter(el => !el.disabled && el.checkVisibility());
        const idx = inputs.indexOf(control);
        if (idx >= 0 && idx + 1 < inputs.length) {
          error = null;
          inputs[idx + 1].focus();
          return;
        }
      }
      const rows = view.original.records.rows;
      const current = rows.findIndex(candidate => candidate.rowId === row.rowId);
      const next = current >= 0 ? rows[current + 1] : undefined;
      if (!next) throw new Error('No next existing vegetation record. Automatic Save is unavailable.');
      error = null;
      const owned = session;
      session.select(next.rowId);
      await tick();
      if (!panel || owned !== session || panel.dataset.vegetationCurrentRow !== next.rowId) return;
      const firstInput = panel.querySelector<HTMLInputElement>('[data-vegetation-column] input[type="text"]:not(:disabled)');
      if (firstInput && firstInput.checkVisibility()) firstInput.focus();
    } catch (cause) {
      error = `Source vegetation Enter refused without mutation: ${String(cause)}`;
    }
  }
</script>

<section bind:this={panel} class="min-w-0 space-y-3 rounded border border-[#D8D8D8] bg-white p-3" aria-label={`${form} linked vegetation`}
  data-two-page-vegetation-panel={form} data-vegetation-current-row={row?.rowId}>
  <h4 class="font-semibold text-[#003366]">{form === 'SubVegCXL' ? 'Herb' : form === 'SubVegDXL' ? 'Moss/Lichen' : 'Tree/Shrubs'}</h4>
  {#if parentBlocked}<p role="status">Finish actual parent/other-owner drafts and unlock the plot before new vegetation staging.</p>{/if}
  {#if error}<p role="alert" class="break-words text-sm text-[#D8292F]">{error}</p>{/if}
  {#if statusMsg}<p role="status" class="break-words text-sm text-[#2E8540]">{statusMsg}</p>{/if}
  {#if view.error && view.error !== error}<p role="alert" class="break-words text-sm text-[#D8292F]">{view.error}</p>{/if}
  {#if view.referenceError && view.referenceError !== error}<p role="alert" class="break-words text-sm text-[#D8292F]">{view.referenceError}</p>{/if}
  {#if view.blocked}<p role="alert">Save outcome unresolved. Recover the exact retained request; do not repeat Save.</p>{/if}
  {#if view.noCommitCertificate}<p role="status" class="break-words">Server certified no commit for {view.noCommitCertificate.requestId}. Correct or Undo retained drafts; another Save needs a new request.</p>{/if}
  {#if Object.keys(view.drafts).length}<p role="status">{Object.keys(view.drafts).length} retained field draft(s). Save applies all retained edits together, including other physical rows.</p>{/if}
  <div class="flex flex-wrap gap-2">
    <button type="button" class="rounded border border-[#D8D8D8] bg-white px-2.5 py-1 text-xs font-medium text-[#313132] disabled:opacity-50"
      disabled={parentBlocked || close.unsaved || view.busy || close.blocked || crudBusy} onclick={() => operation('load')}>Load vegetation</button>
    <button type="button" class="rounded border border-[#D8D8D8] bg-white px-2.5 py-1 text-xs font-medium text-[#313132] disabled:opacity-50"
      disabled={parentBlocked || view.busy || view.blocked || view.acknowledgementRequired || crudBusy}
      onclick={() => operation('references')}>Review Species definitions (read only)</button>
    <button type="button" class="rounded border border-[#003366] bg-[#003366] px-2.5 py-1 text-xs font-medium text-white disabled:opacity-50"
      disabled={parentBlocked || !close.canSave || crudBusy} onclick={() => operation('save')}>Save vegetation</button>
    <button type="button" class="rounded border border-[#D8D8D8] bg-white px-2.5 py-1 text-xs font-medium text-[#313132] disabled:opacity-50"
      disabled={view.busy || view.blocked || view.acknowledgementRequired || !Object.keys(view.drafts).length || crudBusy} onclick={() => operation('undo')}>Undo vegetation drafts</button>
    <button type="button" data-veg-create-toggle
      class="rounded border border-[#003366] bg-white px-2.5 py-1 text-xs font-medium text-[#003366] disabled:opacity-50"
      disabled={fieldsDisabled || close.unsaved || close.blocked || crudBusy || !view.original}
      onclick={() => { createOpen = !createOpen; error = null; }}>
      {createOpen ? 'Cancel Add Row' : 'Add species row'}
    </button>
    <button type="button" data-veg-delete-btn
      class="rounded border border-[#D8292F] bg-white px-2.5 py-1 text-xs font-medium text-[#D8292F] disabled:opacity-50"
      disabled={fieldsDisabled || close.unsaved || close.blocked || crudBusy || !row}
      onclick={() => { if (row) deleteConfirmRowId = deleteConfirmRowId === row.rowId ? null : row.rowId; }}>
      Delete selected row
    </button>
    <button type="button" data-veg-deleted-list-btn
      class="rounded border border-[#D8D8D8] bg-white px-2.5 py-1 text-xs font-medium text-[#313132] disabled:opacity-50"
      disabled={parentBlocked || view.busy || crudBusy}
      onclick={() => { if (deletedHistoryOpen) deletedHistoryOpen = false; else void loadDeletedRows(); }}>
      {deletedHistoryOpen ? 'Hide deleted rows' : 'Deleted rows'}
    </button>
    {#if view.busy}<button type="button" onclick={() => operation('cancel')}>Cancel vegetation operation</button>{/if}
    {#if view.blocked}<button type="button" disabled={view.busy} onclick={() => operation('recover')}>Recover vegetation outcome (read only)</button>{/if}
    {#if view.acknowledgementRequired}<button type="button" disabled={view.busy} onclick={() => operation('acknowledge')}>Acknowledge committed vegetation receipt</button>{/if}
  </div>
  {#if createOpen}
    <div class="rounded border border-[#003366]/30 bg-[#F2F2F2] p-3 space-y-2" data-veg-create-panel>
      <p class="text-xs font-semibold text-[#003366]">Add Vegetation Row ({form})</p>
      <div class="grid grid-cols-1 gap-2 sm:grid-cols-3">
        <div class="min-w-0">
          <label class="block text-xs font-medium text-[#313132]" for={`${form}-create-species`}>Species Code *</label>
          <input id={`${form}-create-species`} type="text" class="w-full rounded border border-[#D8D8D8] bg-white px-2 py-1.5 text-sm"
            bind:value={createSpecies} disabled={crudBusy} placeholder="e.g. PSEUMEN" />
        </div>
        <div class="min-w-0">
          <label class="block text-xs font-medium text-[#313132]" for={`${form}-create-layer`}>Layer (optional)</label>
          <input id={`${form}-create-layer`} type="text" class="w-full rounded border border-[#D8D8D8] bg-white px-2 py-1.5 text-sm"
            bind:value={createLayer} disabled={crudBusy} placeholder="e.g. A1, B1, C, D" />
        </div>
        <div class="min-w-0">
          <label class="block text-xs font-medium text-[#313132]" for={`${form}-create-collected`}>Collected (optional)</label>
          <input id={`${form}-create-collected`} type="text" class="w-full rounded border border-[#D8D8D8] bg-white px-2 py-1.5 text-sm"
            bind:value={createCollected} disabled={crudBusy} placeholder="C or V" />
        </div>
      </div>
      <div class="flex flex-wrap gap-2">
        <button type="button" data-veg-create-submit
          class="rounded bg-[#003366] px-3 py-1 text-xs font-medium text-white disabled:opacity-50"
          disabled={crudBusy || !createSpecies.trim()} onclick={() => void submitCreateRow()}>
          Create row
        </button>
        <button type="button" class="rounded border border-[#D8D8D8] bg-white px-3 py-1 text-xs text-[#313132]"
          disabled={crudBusy} onclick={() => { createOpen = false; }}>
          Cancel
        </button>
      </div>
    </div>
  {/if}
  {#if view.original && row && deleteConfirmRowId === row.rowId}
    <div class="rounded border border-[#D8292F] bg-[#FCEAEA] p-2.5 flex flex-wrap items-center justify-between gap-2 text-xs text-[#313132]" data-veg-delete-confirm>
      <span>Delete vegetation row {twoPageVegetationStoredText(view.original, row.rowId, 'ID')} ({twoPageVegetationStoredText(view.original, row.rowId, 'Species')})? Can be restored from Deleted rows.</span>
      <div class="flex gap-2">
        <button type="button" data-veg-delete-confirm-btn class="rounded bg-[#D8292F] px-2.5 py-1 text-xs font-medium text-white disabled:opacity-50"
          disabled={crudBusy} onclick={() => void confirmDeleteRow()}>Confirm delete</button>
        <button type="button" class="rounded border border-[#D8D8D8] bg-white px-2.5 py-1 text-xs text-[#313132]"
          disabled={crudBusy} onclick={() => { deleteConfirmRowId = null; }}>Cancel</button>
      </div>
    </div>
  {/if}
  {#if deletedHistoryOpen}
    <div class="rounded border border-[#D8D8D8] bg-[#F2F2F2] p-3 space-y-2" data-veg-deleted-panel>
      <p class="text-xs font-semibold text-[#003366]">Deleted Vegetation Rows ({deletedRows.length})</p>
      {#if deletedRows.length === 0}
        <p class="text-xs text-[#606060]">No deleted rows recorded for this form.</p>
      {:else}
        <div class="space-y-1.5">
          {#each deletedRows as entry (entry.deleteRequestId)}
            <div class="flex flex-wrap items-center justify-between gap-2 rounded border border-[#D8D8D8] bg-white p-2 text-xs">
              <span>ID {entry.deletedId} · <strong>{entry.species}</strong> {entry.layer ? `(${entry.layer})` : ''} · Deleted {entry.deletedAt} by {entry.deletedBy}</span>
              {#if entry.restored}
                <span class="rounded bg-[#EBF5ED] px-2 py-0.5 text-[#1F5C2C]">Restored</span>
              {:else}
                <button type="button" data-veg-restore-btn={entry.deleteRequestId}
                  class="rounded border border-[#003366] bg-[#003366] px-2.5 py-1 text-xs font-medium text-white disabled:opacity-50"
                  disabled={crudBusy || fieldsDisabled || close.unsaved || close.blocked}
                  onclick={() => void restoreDeletedRow(entry.deleteRequestId)}>Restore row</button>
              {/if}
            </div>
          {/each}
        </div>
      {/if}
    </div>
  {/if}
  {#if view.original}
    <div class="flex flex-wrap gap-2" aria-label={`${form} complete physical rows`}>
      {#each view.original.records.rows as physical (physical.rowId)}
        <button type="button" class="min-w-0 break-words rounded border p-2 text-left" aria-pressed={row?.rowId === physical.rowId}
          disabled={view.busy} onclick={() => selectRow(physical.rowId)}>
          Species {twoPageVegetationHasColumn(view.original, 'Species') ? twoPageVegetationStoredText(view.original, physical.rowId, 'Species') : '(source column unavailable)'};
          ID {twoPageVegetationStoredText(view.original, physical.rowId, 'ID')}; physical row {physical.rowId};
          {view.original.sourceRowIds.includes(physical.rowId) ? 'in source query' : 'physical only, read only'}
        </button>
      {:else}<p role="status">No physical vegetation records for this exact parent. Creation is unavailable.</p>{/each}
    </div>
    {#if selected !== null && !row}<p role="alert">Selected physical row {selected} is no longer observed. Choose an existing physical row explicitly.</p>{/if}
    {#if row}
      <p class="break-words text-sm">Application ID {twoPageVegetationStoredText(view.original, row.rowId, 'ID')}; physical row {row.rowId}; parent {plot}</p>
      {#if diagnostic}<p role="alert">{diagnostic}</p>{/if}
      <p class="break-words text-sm">Species (read only): {twoPageVegetationHasColumn(view.original, 'Species') ? twoPageVegetationStoredText(view.original, row.rowId, 'Species') : '(source column unavailable)'}</p>
      {#if speciesListAvailable && twoPageVegetationHasColumn(view.original, 'Species')}
        {@const speciesDraft = view.drafts[JSON.stringify([row.rowId, 'Species'])]}
        {@const speciesId = `${form}-${row.rowId}-Species-list`}
        {@const plannedRow = row.rowId}
        <div class="min-w-0 space-y-1" data-vegetation-column="Species">
          <label class="block text-sm font-medium" for={speciesId}>Species: existing list selection</label>
          <select id={speciesId} class="w-full min-w-0 rounded border p-2" value={speciesDraft?.raw ?? ''}
            disabled={fieldsDisabled || speciesWarningUnavailable || !view.references || !speciesOptions.length} aria-invalid={!!speciesDraft?.error}
            aria-describedby={speciesDraft?.error ? `${speciesId}-error` : undefined} onchange={event => pickSpecies(plannedRow, event)}>
            <option value="">Select an exact existing list code</option>
            {#each speciesOptions as option (`${option.role}:${option.rowId}`)}
              <option value={option.code}>{option.code} | {option.cells[1].storage === 'null' ? 'NULL' : JSON.stringify(option.cells[1].text)} |
                {option.cells[4].text} | {option.cells[2].integer} |
                {option.cells[3].storage === 'null' ? 'NULL' : JSON.stringify(option.cells[3].text)} | {option.role} row {option.rowId}</option>
            {/each}
          </select>
          {#if speciesDraft?.error}<p id={`${speciesId}-error`} role="alert" class="text-sm text-red-700">{speciesDraft.error}</p>{/if}
          {#if speciesWarningUnavailable}<p role="status" class="text-sm">Species selection is unavailable: all seven original common covers are NULL; the source warning/advance route is not qualified.</p>{/if}
          {#if !view.references}<p role="status" class="text-sm">Review physical Species definitions before selecting a list code.</p>
          {:else if !speciesOptions.length}<p role="status" class="text-sm">No qualified exact A/CHARS list codes are available.</p>{/if}
        </div>
      {/if}
      {#each twoPageVegetationGroups(form) as group}
        <fieldset class="min-w-0 rounded border p-3">
          <legend class="text-sm font-semibold">{group.label}</legend>
          <div class="grid min-w-0 grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3">
            {#each group.fields as [column, label]}
              {#if twoPageVegetationHasColumn(view.original, column)}
                {@const source = row.cells[vegetationColumnIndex(view.original, column)]}
                {@const draft = view.drafts[JSON.stringify([row.rowId, column])]}
                {@const raw = draft?.raw ?? (source.storage === 'null' ? '' : metadataCellText(source))}
                {@const nullValue = draft?.nullValue ?? source.storage === 'null'}
                {@const id = `${form}-${row.rowId}-${column}`}
                {@const plannedRow = row.rowId}
                <div class="min-w-0 space-y-1 focus-within:bg-[#FFF9E6]" data-vegetation-column={column}>
                  <label class="block text-sm font-medium" for={id}>{label}</label>
                  <input {id} class="w-full min-w-0 rounded border border-[#D8D8D8] p-2" type="text" value={nullValue ? '' : raw}
                    disabled={fieldsDisabled} placeholder={nullValue ? 'NULL' : undefined}
                    aria-invalid={!!draft?.error} aria-describedby={draft?.error ? `${id}-error` : undefined}
                    onkeydown={event => void enterRecord(event, column)}
                    oninput={event => stage(column, event.currentTarget.value, false)} />
                  <label class="flex items-center gap-2 text-sm">
                    <input type="checkbox" checked={nullValue} disabled={fieldsDisabled} onchange={event => stage(column, raw, event.currentTarget.checked)} />
                    {label}: NULL (not empty text)
                  </label>
                  {#if draft?.error}<p id={`${id}-error`} role="alert" class="text-sm text-[#D8292F]">{draft.error}</p>{/if}
                  {#if !draft}<p class="text-xs text-[#606060]">Stored {source.storage}</p>{/if}
                  {#if column === 'Collected'}
                    <button type="button" disabled={fieldsDisabled || !!draft?.error ||
                      (draft?.value ?? source).storage !== 'null' && (draft?.value ?? source).storage !== 'text'}
                      onclick={event => cycleCollected(plannedRow, event)}>Cycle Collected: NULL / C / V</button>
                    <p class="text-xs text-[#606060]">C = Collected; V = Verified. Manual values remain distinct.</p>
                  {/if}
                </div>
              {:else}<p role="alert">Source field {column} unavailable; row is read only.</p>{/if}
            {/each}
          </div>
        </fieldset>
      {/each}
    {/if}
  {/if}
  {#each Object.values(view.drafts).filter(draft => draft.error && draft.rowId !== row?.rowId) as draft}
    <p role="alert">Physical row {draft.rowId}, {draft.column}: {draft.error}. Select that row to correct it or Undo.</p>
  {/each}
  {#if view.receipts.length}<p role="status">{view.receipts.length} immutable committed vegetation receipt(s) retained across remounts.</p>{/if}
  {#if view.references}<VegetationSpeciesReferences references={view.references} />{/if}
  <p class="text-xs text-[#606060]">LMH25 2-Page vegetation strata &amp; species editor: cover values validate against calibrated single-precision (&lt; 100%) bounds while leaving untouched historical values intact. Save commits species, cover, and voucher changes atomically.</p>
</section>
