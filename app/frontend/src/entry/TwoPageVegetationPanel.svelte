<script lang="ts">
  import { tick, untrack } from 'svelte';
  import { formatError } from '../shared/readRequests';
  import TwoPageVegCrudSection, { type DeletedVegetationRowEntry } from './TwoPageVegCrudSection.svelte';
  import TwoPageVegRecordFields from './TwoPageVegRecordFields.svelte';
  import {
    twoPageVegetationSession,
    twoPageVegetationWritingEnabled,
    twoPageVegetationSpeciesListEnabled,
  } from './twoPageVegetationSessions';
  import { enterNavigationMode } from './enterNavigation';
  import {
    twoPageVegetationStoredText,
    twoPageVegetationRowDiagnostic,
    validateVegSpeciesPick,
    validateVegEnterTarget,
    computeVegCollectedCycle,
    type VegetationCrudPort,
    type VegPanelProps,
  } from './twoPageVegetationPresentation';
  import { vegetationSpeciesListOptions, vegetationSpeciesListHasCommonCover } from './twoPageVegetationSpeciesList';
  import { notifications } from '../shell/notificationService.svelte';

  let { vegetationCrudPort, contextId, project, plot, form, parentBlocked }: VegPanelProps = $props();
  const session = $derived(twoPageVegetationSession({ contextId, project, plot, form }));
  let revision = $state(0),
    error = $state<string | null>(null);
  let statusMsg = $state<string | null>(null);
  let panel = $state<HTMLElement>(),
    crudBusy = $state(false),
    createOpen = $state(false);
  let createSpecies = $state(''),
    createLayer = $state(''),
    createCollected = $state('');
  let deleteConfirmRowId = $state<string | null>(null),
    deletedHistoryOpen = $state(false);
  let deletedRows = $state<DeletedVegetationRowEntry[]>([]);
  let crudGeneration = 0;

  $effect(() =>
    session.subscribe(() =>
      untrack(() => {
        revision += 1;
      })
    )
  );
  const view = $derived.by(() => {
    revision;
    return session.view();
  });
  const selected = $derived(view.selectedRowId);
  const close = $derived.by(() => {
    revision;
    return session.closeState();
  });
  const row = $derived(
    selected === null
      ? (view.original?.records.rows.find((candidate) => candidate.rowId === view.original?.sourceRowIds[0]) ??
          view.original?.records.rows[0])
      : view.original?.records.rows.find((candidate) => candidate.rowId === selected)
  );
  const diagnostic = $derived(view.original && row ? twoPageVegetationRowDiagnostic(view.original, row.rowId) : null);
  const fieldsDisabled = $derived(
    parentBlocked ||
      !twoPageVegetationWritingEnabled ||
      view.busy ||
      view.blocked ||
      view.acknowledgementRequired ||
      !!diagnostic
  );
  const speciesListAvailable = $derived(
    twoPageVegetationSpeciesListEnabled && (form === 'SubVegAXL_BC' || form === 'SubVegAXL')
  );
  const speciesOptions = $derived(
    speciesListAvailable && view.references
      ? vegetationSpeciesListOptions(view.references, { contextId, project, plot, form })
      : []
  );
  const speciesWarningUnavailable = $derived(
    speciesListAvailable && view.original && row
      ? !vegetationSpeciesListHasCommonCover(view.original, row.rowId)
      : false
  );

  function pickSpecies(plannedRow: string, event: Event) {
    try {
      stage(
        'Species',
        validateVegSpeciesPick({
          available: speciesListAvailable,
          warningUnavailable: speciesWarningUnavailable,
          fieldsDisabled,
          currentRowId: row?.rowId,
          plannedRow,
          panel,
          event,
          options: speciesOptions,
        }),
        false
      );
    } catch (cause) {
      error = `Species list selection refused without mutation: ${formatError(cause)}`;
    }
  }

  function selectRow(rowId: string) {
    try {
      if (!view.original?.records.rows.some((candidate) => candidate.rowId === rowId))
        throw new Error('Observed physical vegetation row is unavailable.');
      session.select(rowId);
      error = null;
    } catch (cause) {
      error = `Vegetation selection refused without mutation: ${formatError(cause)}`;
    }
  }

  function stage(column: string, raw: string, nullValue: boolean) {
    try {
      if (fieldsDisabled || !row)
        throw new Error('Resolve parent/other-owner operations and unlock the plot before linked vegetation staging.');
      session.stage(row.rowId, column, raw, nullValue);
      error = null;
    } catch (cause) {
      error = `Linked vegetation draft refused; owned state retained: ${formatError(cause)}`;
    }
  }

  function cycleCollected(plannedRow: string, event: MouseEvent) {
    try {
      const next = computeVegCollectedCycle({
        fieldsDisabled,
        currentRowId: row?.rowId,
        plannedRow,
        original: view.original,
        panel,
        form,
        event,
        draft: view.drafts[JSON.stringify([plannedRow, 'Collected'])],
        ButtonCtor: HTMLButtonElement,
      });
      stage('Collected', next ?? '', next === null);
    } catch (cause) {
      error = `Source Collected click refused without mutation: ${formatError(cause)}`;
    }
  }

  async function operation(action: 'load' | 'references' | 'save' | 'recover' | 'undo' | 'acknowledge' | 'cancel') {
    const owned = session;
    try {
      if (parentBlocked && (action === 'load' || action === 'references' || action === 'save'))
        throw new Error(
          'Finish actual parent/other-owner drafts and unlock the plot before loading or saving linked vegetation.'
        );
      error = null;
      if (action === 'undo') session.undo();
      else if (action === 'acknowledge') session.acknowledge();
      else if (action === 'cancel') session.cancel();
      else {
        const ok =
          action === 'load'
            ? await owned.load()
            : action === 'references'
              ? await owned.loadReferences()
              : action === 'save'
                ? await owned.save(crypto.randomUUID())
                : await owned.resolve();
        if (owned !== session) return;
        if (!ok) error = action === 'references' ? owned.view().referenceError : owned.view().error;
        else if (action === 'save') {
          const plotTag = plot ? `Plot ${plot}` : undefined;
          notifications.success(
            'Vegetation changes saved',
            plotTag ? `${plotTag} (${form}) edits committed.` : `${form} edits committed.`,
            { category: 'entry', source: 'Two-Page Vegetation', contextTag: plotTag }
          );
        }
      }
    } catch (cause) {
      if (owned === session) error = `Linked vegetation operation refused; owned state retained: ${formatError(cause)}`;
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

  async function runVegCrudOp(
    prefix: string,
    clearStatus: boolean,
    fn: (port: VegetationCrudPort, owned: typeof session, isCurrent: () => boolean) => Promise<void>
  ) {
    const owned = session;
    crudGeneration += 1;
    const gen = crudGeneration;
    crudBusy = true;
    error = null;
    if (clearStatus) statusMsg = null;
    try {
      await fn(await resolveCrudPort(), owned, () => gen === crudGeneration);
    } catch (cause) {
      if (owned === session) error = `${prefix}: ${formatError(cause)}`;
    } finally {
      if (gen === crudGeneration) crudBusy = false;
    }
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
    await runVegCrudOp('Create vegetation row refused', true, async (port, owned, isCurrent) => {
      const created = await port.createRow(contextId, {
        requestId: crypto.randomUUID(),
        plotNumber: plot,
        form,
        species,
        layer: createLayer.trim() || null,
        collected: createCollected.trim() || null,
        covers: {},
      });
      if (!isCurrent() || owned !== session) return;
      createOpen = false;
      createSpecies = '';
      createLayer = '';
      createCollected = '';
      await owned.load();
      if (owned === session && created.rowId) owned.select(created.rowId);
      statusMsg = `Created vegetation row for ${created.species}.`;
      notifications.success(
        `Created vegetation row (${created.species})`,
        plot ? `Added to Plot ${plot} (${form}).` : `Added to ${form}.`,
        { category: 'entry', source: 'Two-Page Vegetation', contextTag: plot ? `Plot ${plot}` : undefined }
      );
    });
  }

  async function confirmDeleteRow() {
    if (
      fieldsDisabled ||
      close.unsaved ||
      close.blocked ||
      crudBusy ||
      !view.original ||
      !row ||
      deleteConfirmRowId !== row.rowId
    ) {
      error = 'Resolve drafts and confirm the selected row before deleting.';
      return;
    }
    const idText = twoPageVegetationStoredText(view.original, row.rowId, 'ID'),
      numericId = Number(idText);
    if (!Number.isSafeInteger(numericId)) {
      error = `Cannot delete physical row ${row.rowId}: invalid application ID ${JSON.stringify(idText)}.`;
      return;
    }
    await runVegCrudOp('Delete vegetation row refused', true, async (port, owned, isCurrent) => {
      const deleted = await port.deleteRow(contextId, {
        requestId: crypto.randomUUID(),
        plotNumber: plot,
        form,
        id: numericId,
        rowId: row.rowId,
      });
      if (!isCurrent() || owned !== session) return;
      deleteConfirmRowId = null;
      await owned.load();
      statusMsg = `Deleted vegetation row ${deleted.deletedId} (${deleted.species}).`;
      notifications.success(
        `Deleted vegetation row (${deleted.species})`,
        `Row ID ${deleted.deletedId} deleted (recoverable via Deleted rows).`,
        { category: 'entry', source: 'Two-Page Vegetation', contextTag: plot ? `Plot ${plot}` : undefined }
      );
    });
  }

  async function loadDeletedRows() {
    if (parentBlocked || view.busy || crudBusy) return;
    await runVegCrudOp('Could not load deleted vegetation rows', false, async (port, _owned, isCurrent) => {
      const list = await port.listDeletedRows(contextId, plot, form);
      if (isCurrent()) {
        deletedRows = list ?? [];
        deletedHistoryOpen = true;
      }
    });
  }

  async function restoreDeletedRow(deleteRequestId: string) {
    if (fieldsDisabled || close.unsaved || close.blocked || crudBusy) return;
    await runVegCrudOp('Restore vegetation row refused', true, async (port, owned, isCurrent) => {
      const restored = await port.restoreRow(contextId, {
        requestId: crypto.randomUUID(),
        plotNumber: plot,
        form,
        deleteRequestId,
      });
      if (!isCurrent() || owned !== session) return;
      await owned.load();
      if (owned === session && restored.restoredRowId) owned.select(restored.restoredRowId);
      const list = await port.listDeletedRows(contextId, plot, form);
      if (isCurrent()) deletedRows = list ?? [];
      statusMsg = `Restored vegetation row ${restored.restoredId} (${restored.species}).`;
      notifications.success(
        `Restored vegetation row (${restored.species})`,
        `Row ID ${restored.restoredId} restored to ${form}.`,
        { category: 'entry', source: 'Two-Page Vegetation', contextTag: plot ? `Plot ${plot}` : undefined }
      );
    });
  }

  async function enterRecord(event: KeyboardEvent, column: string) {
    if (
      event.key !== 'Enter' ||
      event.defaultPrevented ||
      event.isComposing ||
      event.repeat ||
      event.altKey ||
      event.ctrlKey ||
      event.metaKey ||
      event.shiftKey
    )
      return;
    event.preventDefault();
    try {
      const { nextInput, nextRowId } = validateVegEnterTarget({
        fieldsDisabled,
        closeBlocked: close.blocked,
        rowId: row?.rowId,
        original: view.original,
        panel,
        form,
        mode: enterNavigationMode(form),
        event,
        column,
        doc: document,
        InputCtor: HTMLInputElement,
      });
      if (nextInput) {
        error = null;
        nextInput.focus();
        return;
      }
      if (!nextRowId) return;
      error = null;
      const owned = session;
      session.select(nextRowId);
      await tick();
      if (!panel || owned !== session || panel.dataset.vegetationCurrentRow !== nextRowId) return;
      const firstInput = panel.querySelector<HTMLInputElement>(
        '[data-vegetation-column] input[type="text"]:not(:disabled)'
      );
      if (firstInput && firstInput.checkVisibility()) firstInput.focus();
    } catch (cause) {
      error = `Source vegetation Enter refused without mutation: ${formatError(cause)}`;
    }
  }
</script>

<section
  bind:this={panel}
  class="two-page-veg-panel min-w-0 space-y-3 rounded border border-vpro-border bg-white p-3"
  aria-label={`${form} linked vegetation`}
  data-two-page-vegetation-panel={form}
  data-vegetation-current-row={row?.rowId}
>
  <div
    class="vpro-sticky-subbar sticky top-0 z-15 bg-white/95 border-b border-vpro-border pb-2 pt-1 space-y-2"
    data-veg-sticky-bar
  >
    <h4 class="font-semibold text-vpro-navy">
      {form === 'SubVegCXL' ? 'Herb' : form === 'SubVegDXL' ? 'Moss/Lichen' : 'Tree/Shrubs'}
    </h4>
    <div class="flex flex-wrap gap-2">
      <button
        type="button"
        class="rounded border border-vpro-border bg-white px-2.5 py-1 text-xs font-medium text-vpro-ink disabled:opacity-50"
        disabled={parentBlocked || close.unsaved || view.busy || close.blocked || crudBusy}
        onclick={() => operation('load')}>Load vegetation</button
      >
      <button
        type="button"
        class="rounded border border-vpro-border bg-white px-2.5 py-1 text-xs font-medium text-vpro-ink disabled:opacity-50"
        disabled={parentBlocked || view.busy || view.blocked || view.acknowledgementRequired || crudBusy}
        onclick={() => operation('references')}>Review Species definitions (read only)</button
      >
      <button
        type="button"
        class="rounded border border-vpro-navy bg-vpro-navy px-2.5 py-1 text-xs font-medium text-white disabled:opacity-50"
        disabled={parentBlocked || !close.canSave || crudBusy}
        onclick={() => operation('save')}>Save vegetation</button
      >
      <button
        type="button"
        class="rounded border border-vpro-border bg-white px-2.5 py-1 text-xs font-medium text-vpro-ink disabled:opacity-50"
        disabled={view.busy ||
          view.blocked ||
          view.acknowledgementRequired ||
          !Object.keys(view.drafts).length ||
          crudBusy}
        onclick={() => operation('undo')}>Undo vegetation drafts</button
      >
      <button
        type="button"
        data-veg-create-toggle
        class="rounded border border-vpro-navy bg-white px-2.5 py-1 text-xs font-medium text-vpro-navy disabled:opacity-50"
        disabled={fieldsDisabled || close.unsaved || close.blocked || crudBusy || !view.original}
        onclick={() => {
          createOpen = !createOpen;
          error = null;
        }}>{createOpen ? 'Cancel Add Row' : 'Add species row'}</button
      >
      <button
        type="button"
        data-veg-delete-btn
        class="rounded border border-vpro-error bg-white px-2.5 py-1 text-xs font-medium text-vpro-error disabled:opacity-50"
        disabled={fieldsDisabled || close.unsaved || close.blocked || crudBusy || !row}
        onclick={() => {
          if (row) deleteConfirmRowId = deleteConfirmRowId === row.rowId ? null : row.rowId;
        }}>Delete selected row</button
      >
      <button
        type="button"
        data-veg-deleted-list-btn
        class="rounded border border-vpro-border bg-white px-2.5 py-1 text-xs font-medium text-vpro-ink disabled:opacity-50"
        disabled={parentBlocked || view.busy || crudBusy}
        onclick={() => {
          if (deletedHistoryOpen) deletedHistoryOpen = false;
          else void loadDeletedRows();
        }}>{deletedHistoryOpen ? 'Hide deleted rows' : 'Deleted rows'}</button
      >
      {#if view.busy}<button type="button" onclick={() => operation('cancel')}>Cancel vegetation operation</button>{/if}
      {#if view.blocked}<button type="button" disabled={view.busy} onclick={() => operation('recover')}
          >Recover vegetation outcome (read only)</button
        >{/if}
      {#if view.acknowledgementRequired}<button
          type="button"
          disabled={view.busy}
          onclick={() => operation('acknowledge')}>Acknowledge committed vegetation receipt</button
        >{/if}
    </div>
  </div>
  <TwoPageVegCrudSection
    bind:createSpecies
    bind:createLayer
    bind:createCollected
    state={{
      form,
      parentBlocked,
      error,
      view,
      createOpen,
      crudBusy,
      fieldsDisabled,
      unsaved: close.unsaved,
      closeBlocked: Boolean(close.blocked),
      original: view.original,
      currentRowId: row?.rowId,
      deleteConfirmRowId,
      deletedHistoryOpen,
      deletedRows,
    }}
    handlers={{
      onsubmitcreate: () => void submitCreateRow(),
      oncancelcreate: () => {
        createOpen = false;
      },
      onconfirmdelete: () => void confirmDeleteRow(),
      oncanceldelete: () => {
        deleteConfirmRowId = null;
      },
      onrestore: (id) => void restoreDeletedRow(id),
    }}
  />
  <TwoPageVegRecordFields
    state={{
      plot,
      form,
      original: view.original,
      selected,
      row,
      diagnostic,
      busy: view.busy,
      fieldsDisabled,
      drafts: view.drafts,
      receiptCount: view.receipts.length,
      references: view.references,
      speciesListAvailable,
      speciesOptions,
      speciesWarningUnavailable,
    }}
    handlers={{
      onselectrow: selectRow,
      onpickspecies: pickSpecies,
      onenterrecord: (event, column) => void enterRecord(event, column),
      onstage: stage,
      oncyclecollected: cycleCollected,
    }}
  />
</section>

<style>
  .two-page-veg-panel {
    max-width: 100%;
    overflow-x: clip;
    border-color: var(--vpro-border);
    border-top: 3px solid var(--vpro-gold);
    font-variant-numeric: tabular-nums;
  }
  .two-page-veg-panel :global(input[type='text']),
  .two-page-veg-panel :global(select) {
    border-color: var(--vpro-forest-border);
    font-variant-numeric: tabular-nums;
  }
  .two-page-veg-panel :global(input[type='text']:focus),
  .two-page-veg-panel :global(select:focus) {
    outline: 2px solid var(--vpro-focus-ring);
    outline-offset: 1px;
  }
</style>
