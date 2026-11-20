<script lang="ts">
  import { tick, untrack } from 'svelte';
  import { PlotEntryService, type ProjectMetadataCell } from '../../bindings/github.com/boostao/vpro/app';
  import { formatError } from '../shared/readRequests';
  import TwoPageSoilLifecycleSection, { type DeletedSoilHorizonEntry } from './TwoPageSoilLifecycleSection.svelte';
  import TwoPageSoilRecordFields from './TwoPageSoilRecordFields.svelte';
  import { SoilReferenceLookup, type SoilReferenceView } from './twoPageSoilReferences';
  import { twoPageSoilSession, twoPageSoilWritingEnabled, twoPageSoilCreationEnabled } from './twoPageSoilSessions';
  import { twoPageSoilKind } from './twoPageSoilEditor';
  import { equalCell } from '../admin/projectMetadataEditor';
  import { enterNavigationMode } from './enterNavigation';
  import {
    twoPageSoilStoredText,
    twoPageSoilRowDiagnostic,
    twoPageSoilDepthOrder,
    validateSoilEnterTarget,
    type SoilDeleteRestorePort,
    type SoilPanelProps,
  } from './twoPageSoilPresentation';
  import { notifications } from '../shell/notificationService.svelte';

  let { soilDeleteRestorePort, contextId, project, plot, form, parentBlocked }: SoilPanelProps = $props();
  const session = $derived(twoPageSoilSession({ contextId, project, plot, form }));
  let revision = $state(0);
  let selected = $state<string | null>(
    untrack(() => {
      const original = session.view().original;
      return original ? (twoPageSoilDepthOrder(original).rows[0]?.rowId ?? null) : null;
    })
  );
  let error = $state<string | null>(null),
    panel = $state<HTMLElement>();
  let referenceView = $state.raw<SoilReferenceView>({ busy: false, data: null, error: null });
  let referenceLookup = $state.raw<SoilReferenceLookup | null>(null);
  let deleteConfirmRowId = $state<string | null>(null),
    deleteRestoreBusy = $state(false),
    deletedHistoryOpen = $state(false);
  let deletedHorizons = $state<DeletedSoilHorizonEntry[]>([]);
  let deleteRestoreGeneration = 0;

  async function resolveSoilDeleteRestorePort(): Promise<SoilDeleteRestorePort> {
    if (soilDeleteRestorePort) return soilDeleteRestorePort;
    const { ContextService } = await import('../../bindings/github.com/boostao/vpro/app');
    return {
      deleteHorizon: (cid, req) => ContextService.DeleteTwoPageSoilHorizon(cid, req) as never,
      restoreHorizon: (cid, req) => ContextService.RestoreTwoPageSoilHorizon(cid, req) as never,
      listDeletedHorizons: (cid, p, f) => ContextService.ListTwoPageSoilDeletedHorizons(cid, p, f) as never,
    };
  }

  async function runDeleteRestoreOp(
    prefix: string,
    fn: (port: SoilDeleteRestorePort, isCurrent: () => boolean) => Promise<void>
  ) {
    deleteRestoreGeneration += 1;
    const gen = deleteRestoreGeneration;
    deleteRestoreBusy = true;
    error = null;
    try {
      await fn(await resolveSoilDeleteRestorePort(), () => gen === deleteRestoreGeneration);
    } catch (cause) {
      if (gen === deleteRestoreGeneration) error = `${prefix}: ${formatError(cause)}`;
    } finally {
      if (gen === deleteRestoreGeneration) deleteRestoreBusy = false;
    }
  }

  async function refreshDeletedHorizons() {
    if (parentBlocked || view.busy || deleteRestoreBusy) return;
    await runDeleteRestoreOp('Deleted soil horizon history unavailable', async (port, isCurrent) => {
      const list = await port.listDeletedHorizons(contextId, plot, form);
      if (isCurrent()) {
        deletedHorizons = list ?? [];
        deletedHistoryOpen = true;
      }
    });
  }

  async function confirmDeleteHorizon() {
    if (
      parentBlocked ||
      referenceView.busy ||
      view.busy ||
      close.unsaved ||
      close.blocked ||
      deleteRestoreBusy ||
      !view.original ||
      !row ||
      deleteConfirmRowId !== row.rowId
    ) {
      error = 'Resolve retained drafts and confirm the selected physical row before deleting a horizon.';
      return;
    }
    const parsedId = Number(twoPageSoilStoredText(view.original, row.rowId, 'ID'));
    if (!Number.isInteger(parsedId) || parsedId === 0) {
      error = 'Soil horizon deletion requires a non-zero integer application ID.';
      return;
    }
    const req = $state.snapshot({
      requestId: crypto.randomUUID(),
      plotNumber: plot,
      form,
      id: parsedId,
      rowId: row.rowId,
    });
    const owned = session;
    await runDeleteRestoreOp('Delete soil horizon refused', async (port, isCurrent) => {
      const deleted = await port.deleteHorizon(contextId, req);
      if (!isCurrent() || owned !== session) return;
      deleteConfirmRowId = null;
      await owned.load();
      if (owned === session) selected = depthOrder?.rows[0]?.rowId ?? null;
      if (deletedHistoryOpen) {
        const list = await port.listDeletedHorizons(contextId, plot, form);
        if (isCurrent()) deletedHorizons = list ?? [];
      }
      notifications.success(
        `${twoPageSoilKind(form)} horizon deleted`,
        `Deleted horizon ${deleted?.horizon || '(NULL)'} (ID ${deleted?.deletedId ?? parsedId}).`,
        { category: 'entry', source: 'Two-Page Soil', contextTag: plot ? `Plot ${plot}` : undefined }
      );
    });
  }

  async function restoreDeletedHorizon(deleteRequestId: string) {
    if (parentBlocked || referenceView.busy || view.busy || close.unsaved || close.blocked || deleteRestoreBusy) {
      error = 'Save or Undo retained soil drafts before restoring a deleted horizon.';
      return;
    }
    const req = $state.snapshot({ requestId: crypto.randomUUID(), plotNumber: plot, form, deleteRequestId });
    const owned = session;
    await runDeleteRestoreOp('Restore soil horizon refused', async (port, isCurrent) => {
      const restored = await port.restoreHorizon(contextId, req);
      if (!isCurrent() || owned !== session) return;
      await owned.load();
      if (owned === session && restored.restoredRowId) selected = restored.restoredRowId;
      const list = await port.listDeletedHorizons(contextId, plot, form);
      if (isCurrent()) deletedHorizons = list ?? [];
      notifications.success(
        `${twoPageSoilKind(form)} horizon restored`,
        `Restored horizon ${restored?.horizon || '(NULL)'} (ID ${restored?.restoredId ?? ''}).`,
        { category: 'entry', source: 'Two-Page Soil', contextTag: plot ? `Plot ${plot}` : undefined }
      );
    });
  }

  $effect(() => {
    const lookup = new SoilReferenceLookup(
      { contextId, project, plot, form },
      (target) => PlotEntryService.GetTwoPageSoilReferences(target.contextId, target.plot, target.form) as never,
      (next) => {
        referenceView = next;
      }
    );
    untrack(() => {
      referenceLookup = lookup;
      referenceView = lookup.snapshot();
    });
    return () => lookup.dispose();
  });
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
  const close = $derived.by(() => {
    revision;
    return session.closeState();
  });
  const depthOrder = $derived(view.original ? twoPageSoilDepthOrder(view.original) : null);
  const row = $derived(depthOrder?.rows.find((candidate) => candidate.rowId === selected) ?? depthOrder?.rows[0]);
  const diagnostic = $derived(view.original && row ? twoPageSoilRowDiagnostic(view.original, row.rowId) : null);
  const fieldsDisabled = $derived(
    parentBlocked ||
      !twoPageSoilWritingEnabled ||
      view.busy ||
      referenceView.busy ||
      view.blocked ||
      view.acknowledgementRequired ||
      !!diagnostic ||
      !!view.creation
  );
  const soilCleanIdle = $derived(
    !parentBlocked && !referenceView.busy && !view.busy && !close.unsaved && !close.blocked
  );

  async function focusHorizon(plannedRow = row?.rowId, owned = session): Promise<boolean> {
    await tick();
    if (!panel || owned !== session || plannedRow !== row?.rowId) return false;
    if (panel.dataset.twoPageSoilPanel !== form || panel.dataset.soilCurrentRow !== plannedRow)
      throw new Error('Observed soil panel/physical record changed before Horizon focus.');
    const input = panel?.querySelector<HTMLInputElement>('[data-soil-column="Horizon"] input[type="text"]');
    if (!input || input.disabled || !input.checkVisibility()) return false;
    input.focus();
    if (document.activeElement !== input)
      throw new Error('The observed soil Horizon did not receive focus; no record was saved or created.');
    return true;
  }

  async function selectRow(rowId: string) {
    try {
      if (!depthOrder?.rows.some((candidate) => candidate.rowId === rowId))
        throw new Error('The selected physical soil record is unavailable.');
      selected = rowId;
      await focusHorizon(rowId);
    } catch (cause) {
      error = `Soil selection/focus refused without mutation: ${formatError(cause)}`;
    }
  }

  function beginCreation() {
    try {
      if (parentBlocked || referenceView.busy)
        throw new Error('Resolve parent/source-choice operations before Add Horizon.');
      session.beginCreation();
      error = null;
    } catch (cause) {
      error = `Add Horizon refused without mutation: ${formatError(cause)}`;
    }
  }

  function stageCreation(raw: string) {
    try {
      if (parentBlocked || referenceView.busy)
        throw new Error('Resolve parent/source-choice operations before staging a new Horizon.');
      session.stageCreation(raw);
      error = null;
    } catch (cause) {
      error = `New Horizon draft refused: ${formatError(cause)}`;
    }
  }

  async function createHorizon() {
    const owned = session;
    try {
      if (parentBlocked || referenceView.busy || !panel || panel.dataset.twoPageSoilPanel !== form)
        throw new Error('Observed creation owner is unavailable.');
      const input = panel.querySelector<HTMLInputElement>('[data-soil-new-horizon]');
      if (!input || input.disabled || !input.checkVisibility() || input.value !== view.creation?.raw)
        throw new Error('Observed new Horizon differs from its retained literal draft.');
      error = null;
      const ok = await owned.create(crypto.randomUUID());
      if (owned !== session) return;
      if (!ok) error = owned.view().error;
      else {
        const receipt = owned.view().receipts.at(-1);
        if (receipt?.history.CreatedRowID) selected = receipt.history.CreatedRowID;
        const plotTag = plot ? `Plot ${plot}` : undefined;
        notifications.success(
          `${twoPageSoilKind(form)} horizon created`,
          plotTag ? `Added horizon to ${plotTag}.` : 'Horizon created.',
          { category: 'entry', source: 'Two-Page Soil', contextTag: plotTag }
        );
      }
    } catch (cause) {
      if (owned === session)
        error = `Explicit Horizon creation refused; retained state preserved: ${formatError(cause)}`;
    }
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
      const nextInput = validateSoilEnterTarget({
        fieldsDisabled,
        closeBlocked: close.blocked,
        rowId: row?.rowId,
        original: view.original,
        panel,
        form,
        mode: enterNavigationMode(form),
        event,
        column,
        drafts: view.drafts,
        doc: document,
        InputCtor: HTMLInputElement,
        TextareaCtor: HTMLTextAreaElement,
      });
      if (nextInput) {
        error = null;
        nextInput.focus();
        return;
      }
      const current = depthOrder?.rows.findIndex((candidate) => candidate.rowId === row?.rowId) ?? -1;
      const next = current >= 0 ? depthOrder?.rows[current + 1] : undefined;
      if (!next) throw new Error('No next existing soil record. Creation and automatic Save are unavailable.');
      error = null;
      selected = next.rowId;
      if (!(await focusHorizon(next.rowId)))
        throw new Error(
          'Next physical soil record is selected, but its Horizon is read only or no longer visible; no Save was dispatched.'
        );
    } catch (cause) {
      error = `Source soil Enter refused without mutation: ${formatError(cause)}`;
    }
  }

  async function loadReferences() {
    try {
      if (parentBlocked || view.busy || view.blocked || view.acknowledgementRequired || !referenceLookup)
        throw new Error('Resolve parent/soil ownership before loading source choices.');
      await referenceLookup.refresh();
    } catch (cause) {
      error = `Source soil choice read refused: ${formatError(cause)}`;
    }
  }

  function chooseReference(column: string, plannedRow: string, definitionId: string, value: ProjectMetadataCell) {
    try {
      if (
        !row ||
        row.rowId !== plannedRow ||
        panel?.dataset.soilCurrentRow !== plannedRow ||
        panel.dataset.twoPageSoilPanel !== form ||
        referenceView.data?.contextId !== contextId ||
        referenceView.data.project !== project ||
        referenceView.data.plot !== plot ||
        referenceView.data.form !== form
      ) {
        throw new Error('Observed soil choice owner/physical row differs from its planned field.');
      }
      const observed = referenceView.data.fields
        .find((field) => field.column === column)
        ?.definitions.rows.find((definition) => definition.rowId === definitionId)?.cells[3];
      if (!observed || !equalCell(observed, value))
        throw new Error('Observed source definition identity/value differs from the planned soil choice.');
      if (value.storage !== 'text' && value.storage !== 'null')
        throw new Error('Source choice Item must be explicit TEXT or NULL.');
      stage(column, value.text ?? '', value.storage === 'null');
    } catch (cause) {
      error = `Source soil choice refused without mutation: ${formatError(cause)}`;
    }
  }

  async function operation(action: 'load' | 'save' | 'recover' | 'undo' | 'acknowledge' | 'cancel') {
    try {
      if ((parentBlocked || referenceView.busy) && (action === 'load' || action === 'save'))
        throw new Error(
          'Finish actual parent drafts/operations and unlock the plot before loading or saving linked soil.'
        );
      error = null;
      const owned = session;
      if (action === 'cancel') owned.cancel();
      else if (action === 'undo') owned.undo();
      else if (action === 'acknowledge') owned.acknowledge();
      else {
        const ok =
          action === 'load'
            ? await owned.load()
            : action === 'save'
              ? await owned.save(crypto.randomUUID())
              : await owned.resolve();
        if (!ok) error = owned.view().error;
        else if (action === 'load' && owned === session) {
          selected = row?.rowId ?? null;
          await focusHorizon(selected ?? undefined, owned);
        } else if (action === 'save') {
          const plotTag = plot ? `Plot ${plot}` : undefined;
          notifications.success(
            `${twoPageSoilKind(form)} horizon changes saved`,
            plotTag ? `${plotTag} (${form}) edits committed.` : `${form} edits committed.`,
            { category: 'entry', source: 'Two-Page Soil', contextTag: plotTag }
          );
        }
      }
    } catch (cause) {
      error = `Linked soil operation refused; owned state retained: ${formatError(cause)}`;
    }
  }

  function stage(column: string, raw: string, nullValue: boolean) {
    try {
      if (fieldsDisabled || !row)
        throw new Error(
          'Linked soil staging is unavailable while parent ownership, Lock or the retained soil operation blocks it.'
        );
      session.stage(row.rowId, column, raw, nullValue);
      error = null;
    } catch (cause) {
      error = `Linked soil draft refused; owned state retained: ${formatError(cause)}`;
    }
  }
</script>

<section
  bind:this={panel}
  class="two-page-soil-panel min-w-0 space-y-3 rounded border bg-white p-3"
  aria-label={`${form} linked soil`}
  data-two-page-soil-panel={form}
  data-soil-current-row={row?.rowId}
  data-help-id={form === 'SoilHumusXL' ? 'humus.upper_lower_depth' : 'mineral.horizon'}
>
  <div
    class="vpro-sticky-subbar sticky top-0 z-15 bg-white/95 border-b border-vpro-border pb-2 space-y-2"
    data-soil-sticky-bar
  >
    <h4 class="font-semibold">{form === 'SoilHumusXL' ? 'Humus' : 'Mineral soil'}</h4>
    <div class="flex flex-wrap gap-2">
      <button type="button" disabled={!soilCleanIdle} onclick={() => operation('load')}
        >Load {twoPageSoilKind(form)}</button
      >
      <button
        type="button"
        disabled={parentBlocked || referenceView.busy || !close.canSave}
        onclick={() => operation('save')}>Save {twoPageSoilKind(form)}</button
      >
      <button
        type="button"
        disabled={parentBlocked || view.busy || referenceView.busy || view.blocked || view.acknowledgementRequired}
        onclick={loadReferences}>{referenceView.error ? 'Retry' : 'Load'} source soil choices</button
      >
      {#if referenceView.busy}<button type="button" onclick={() => referenceLookup?.cancel()}
          >Cancel source soil choices</button
        >{/if}
      {#if twoPageSoilCreationEnabled}
        <button type="button" disabled={!soilCleanIdle || !view.original} onclick={beginCreation}
          >New {twoPageSoilKind(form)} horizon</button
        >
      {/if}
      {#if twoPageSoilCreationEnabled || soilDeleteRestorePort}
        <button
          type="button"
          data-soil-delete-trigger
          disabled={!soilCleanIdle || deleteRestoreBusy || !view.original || !row || !!diagnostic}
          onclick={() => {
            deleteConfirmRowId = row?.rowId ?? null;
            error = null;
          }}>Delete selected {twoPageSoilKind(form)} horizon</button
        >
        <button
          type="button"
          data-soil-deleted-history-trigger
          disabled={parentBlocked || view.busy || deleteRestoreBusy || close.unsaved || close.blocked}
          onclick={refreshDeletedHorizons}>Deleted {twoPageSoilKind(form)} horizons</button
        >
      {/if}
      <button
        type="button"
        disabled={view.busy ||
          view.blocked ||
          view.acknowledgementRequired ||
          (!Object.keys(view.drafts).length && !view.creation)}
        onclick={() => operation('undo')}>Undo soil drafts</button
      >
      {#if view.busy}<button type="button" onclick={() => operation('cancel')}>Cancel soil operation</button>{/if}
      {#if view.blocked}<button type="button" disabled={view.busy} onclick={() => operation('recover')}
          >Recover soil outcome (read only)</button
        >{/if}
      {#if view.acknowledgementRequired}<button
          type="button"
          disabled={view.busy}
          onclick={() => operation('acknowledge')}>Acknowledge committed soil receipt</button
        >{/if}
    </div>
  </div>
  <TwoPageSoilLifecycleSection
    state={{
      project,
      plot,
      form,
      parentBlocked,
      error,
      view,
      referenceView,
      unsaved: close.unsaved,
      closeBlocked: Boolean(close.blocked),
      deleteRestoreBusy,
      showDeletedHistory: deletedHistoryOpen && (twoPageSoilCreationEnabled || Boolean(soilDeleteRestorePort)),
      deleteConfirmRowId,
      currentRowId: row?.rowId,
      original: view.original,
      deletedHorizons,
    }}
    handlers={{
      onconfirmdelete: () => void confirmDeleteHorizon(),
      oncanceldelete: () => {
        deleteConfirmRowId = null;
      },
      onrestore: (id) => void restoreDeletedHorizon(id),
      onstagecreation: stageCreation,
      oncreate: () => void createHorizon(),
    }}
  />
  <TwoPageSoilRecordFields
    state={{
      plot,
      form,
      original: view.original,
      depthOrder,
      row,
      diagnostic,
      drafts: view.drafts,
      receiptCount: view.receipts.length,
      fieldsDisabled,
      referenceView,
    }}
    handlers={{
      onselectrow: (id) => void selectRow(id),
      onenterrecord: (event, column) => void enterRecord(event, column),
      onstage: stage,
      onchoosereference: chooseReference,
    }}
  />
</section>

<style>
  .two-page-soil-panel {
    max-width: 100%;
    overflow-x: clip;
    border-color: var(--vpro-border);
    border-top: 3px solid var(--vpro-gold);
    font-variant-numeric: tabular-nums;
  }
  .two-page-soil-panel :global(input[type='text']),
  .two-page-soil-panel :global(textarea) {
    border-color: var(--vpro-forest-border);
    font-variant-numeric: tabular-nums;
  }
  .two-page-soil-panel :global(input[type='text']:focus),
  .two-page-soil-panel :global(textarea:focus) {
    outline: 2px solid var(--vpro-focus-ring);
    outline-offset: 1px;
  }
</style>
