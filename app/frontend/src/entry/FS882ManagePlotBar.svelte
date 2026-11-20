<script lang="ts">
  import { formatError } from '../shared/readRequests';

  let {
    open = $bindable(),
    originalPlotNumber,
    activeProject,
    busy,
    canUndoPlotDelete,
    onCopyPlotToNumber,
    onRemovePlotAction,
    onError,
  }: {
    open: boolean;
    originalPlotNumber: string | undefined;
    activeProject: string | undefined;
    busy: boolean;
    canUndoPlotDelete: boolean;
    onCopyPlotToNumber?: (sourcePlot: string, targetPlot: string) => Promise<void>;
    onRemovePlotAction?: (sourcePlot: string, cleanProjectName: string) => Promise<void>;
    onError: (msg: string | null) => void;
  } = $props();

  let copyPlotTarget = $state('');
  let removeCleanProject = $state('');
  let managePlotBusy = $state(false);
  let lastManagedOrigin = '';

  $effect(() => {
    const origPlot = originalPlotNumber ?? '';
    if (origPlot !== lastManagedOrigin) {
      lastManagedOrigin = origPlot;
      open = false;
      copyPlotTarget = origPlot.trim().slice(0, 7);
      const baseProj = (activeProject ?? 'Project').replace(/[^A-Za-z0-9_]/g, '');
      removeCleanProject = `${(baseProj || 'Project').slice(0, 22)}_Clean`;
    }
  });

  async function runCopyPlot() {
    if (!originalPlotNumber || !onCopyPlotToNumber || managePlotBusy) return;
    managePlotBusy = true;
    onError(null);
    try {
      await onCopyPlotToNumber(originalPlotNumber, copyPlotTarget);
      open = false;
    } catch (cause) {
      onError(formatError(cause));
    } finally {
      managePlotBusy = false;
    }
  }

  async function runRemovePlot() {
    if (!originalPlotNumber || !onRemovePlotAction || managePlotBusy) return;
    managePlotBusy = true;
    onError(null);
    try {
      await onRemovePlotAction(originalPlotNumber, canUndoPlotDelete ? '' : removeCleanProject);
      open = false;
    } catch (cause) {
      onError(formatError(cause));
    } finally {
      managePlotBusy = false;
    }
  }
</script>

{#if open && originalPlotNumber}
  <section
    aria-label="Manage plot number"
    data-manage-plot-panel
    class="border-b border-vpro-border bg-vpro-surface-subtle px-4 py-2.5 text-xs flex flex-wrap items-end gap-4"
  >
    {#if onCopyPlotToNumber}
      <label class="flex flex-col gap-1">
        <span class="font-semibold text-vpro-navy">Copy Plot {originalPlotNumber} to New Plot Number</span>
        <span class="flex items-center gap-1.5">
          <input
            type="text"
            maxlength="7"
            data-fs882-copy-plot-input
            class="rounded border border-vpro-border bg-white px-2 py-1 font-mono text-xs w-28"
            placeholder="New plot #"
            bind:value={copyPlotTarget}
            disabled={managePlotBusy || busy}
          />
          <button
            type="button"
            data-fs882-copy-plot-btn
            class="rounded bg-vpro-navy px-2.5 py-1 font-semibold text-white hover:bg-vpro-navy-dark disabled:opacity-50"
            disabled={managePlotBusy || busy || !copyPlotTarget.trim()}
            onclick={() => void runCopyPlot()}>Copy Plot</button
          >
        </span>
      </label>
    {/if}
    {#if onRemovePlotAction}
      <div class="flex flex-col gap-1">
        <span class="font-semibold text-vpro-error-ink">
          {canUndoPlotDelete
            ? 'Delete Newly Created Plot'
            : `Remove Plot ${originalPlotNumber} into Clean Project Copy`}
        </span>
        <div class="flex items-center gap-1.5">
          {#if !canUndoPlotDelete}
            <input
              type="text"
              maxlength="30"
              aria-label="Clean project copy name"
              data-fs882-clean-project-input
              class="rounded border border-vpro-border bg-white px-2 py-1 font-mono text-xs w-44"
              placeholder="Clean project name"
              bind:value={removeCleanProject}
              disabled={managePlotBusy || busy}
            />
          {/if}
          <button
            type="button"
            data-fs882-remove-plot-btn
            class="rounded border border-vpro-error bg-white px-2.5 py-1 font-semibold text-vpro-error hover:bg-vpro-error-bg disabled:opacity-50"
            disabled={managePlotBusy || busy || (!canUndoPlotDelete && !removeCleanProject.trim())}
            onclick={() => void runRemovePlot()}
          >
            {canUndoPlotDelete ? 'Delete Plot' : 'Save & Switch Without Plot'}
          </button>
        </div>
      </div>
    {/if}
    <button
      type="button"
      class="ml-auto rounded border border-vpro-border bg-white px-2.5 py-1 text-vpro-ink-secondary hover:bg-vpro-canvas"
      onclick={() => {
        open = false;
      }}>Close</button
    >
  </section>
{/if}
