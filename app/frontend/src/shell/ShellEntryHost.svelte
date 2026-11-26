<script lang="ts">
  import { ContextService, type ProjectPlotProfileFilterRequest } from '../../bindings/github.com/boostao/vpro/app';
  import type { PlotSummary } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
  import { invalidateProjectIdChoices } from '../entry/entryReferenceCache';
  import { bindContextPlots } from '../shared/contextPlots';
  import { formatError, type ReadRequests } from '../shared/readRequests';
  import { projectState, webMeta } from '../shared/state';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import type { CloseDecision, EditorCloseState } from './closeLifecycle';
  import type { PlotProfileSelectionController } from './plotProfileOps';
  import type { DiagnosticsDraftContext, FS882EditorHandle, ShellViewId } from './shellPlotOps';

  let {
    mode,
    busy,
    error = $bindable(''),
    view = $bindable<ShellViewId>('fs882'),
    editorPlotNumber = $bindable<string | undefined>(undefined),
    editorEntryForm = $bindable<'fs882' | 'sivi' | 'fs882-twopage'>('fs882'),
    selected = $bindable<PlotSummary | null>(null),
    standaloneMetadataPlot = $bindable(''),
    standaloneMetadataEditor = $bindable<
      { hasUnsavedChanges?: () => boolean; getCloseState: () => EditorCloseState; undo: () => void } | undefined
    >(undefined),
    localEditorBusy = $bindable(false),
    editor = $bindable<FS882EditorHandle | undefined>(undefined),
    fs882ModuleLoaded = $bindable(false),
    plotFindOpen = $bindable(false),
    plotFindQuery = $bindable(''),
    plotFindError = $bindable(''),
    plotFindResult = $bindable<Awaited<ReturnType<typeof ContextService.LookupScopedPlot>> | null>(null),
    pictureManagerPlot = $bindable(''),
    diagnosticsDraft = $bindable<DiagnosticsDraftContext | null>(null),
    editorLabel,
    editorBusy,
    transitionWorking,
    pendingTransition,
    closeRequest,
    closeWorking,
    closeError,
    transitionError,
    closeState,
    allAvailablePlots,
    canUndoEditorPlot,
    stateReads,
    requestTransition,
    respondToClose,
    respondToTransition,
    navigate,
    findScopedPlot,
    openFoundPlot,
    applyProfileNavigation,
    profileSelection,
    initialProfileReviewOpen = false,
    onConsumedInitialProfileReview,
    reviewProfileSU,
    copyPlotToNewNumber,
    removePlotFromProject,
    refreshCatalogAfterWrite,
  }: {
    mode: 'metadata' | 'fs882';
    busy: boolean;
    error: string;
    view: ShellViewId;
    editorPlotNumber: string | undefined;
    editorEntryForm: 'fs882' | 'sivi' | 'fs882-twopage';
    selected: PlotSummary | null;
    standaloneMetadataPlot: string;
    standaloneMetadataEditor:
      { hasUnsavedChanges?: () => boolean; getCloseState: () => EditorCloseState; undo: () => void } | undefined;
    localEditorBusy: boolean;
    editor: FS882EditorHandle | undefined;
    fs882ModuleLoaded: boolean;
    plotFindOpen: boolean;
    plotFindQuery: string;
    plotFindError: string;
    plotFindResult: Awaited<ReturnType<typeof ContextService.LookupScopedPlot>> | null;
    pictureManagerPlot: string;
    diagnosticsDraft: DiagnosticsDraftContext | null;
    editorLabel: 'FS882' | 'FS882 (2-Page)' | 'SIVI / FS1333';
    editorBusy: boolean;
    transitionWorking: boolean;
    pendingTransition: unknown;
    closeRequest: string;
    closeWorking: boolean;
    closeError: string;
    transitionError: string;
    closeState: EditorCloseState | undefined;
    allAvailablePlots: PlotSummary[];
    canUndoEditorPlot: boolean;
    stateReads: ReadRequests;
    requestTransition: (run: (contextId: string) => Promise<void>, ownedAction?: () => boolean) => Promise<void>;
    respondToClose: (decision: CloseDecision) => Promise<void>;
    respondToTransition: (decision: CloseDecision) => Promise<void>;
    navigate: (next: ShellViewId | 'fs882-twopage') => void;
    findScopedPlot: () => Promise<void>;
    openFoundPlot: () => Promise<void>;
    applyProfileNavigation: (proposal: ProjectPlotProfileFilterRequest, origin: string) => Promise<void>;
    profileSelection?: PlotProfileSelectionController;
    initialProfileReviewOpen?: boolean;
    onConsumedInitialProfileReview?: () => void;
    reviewProfileSU?: (proposal: ProjectPlotProfileFilterRequest, origin: string) => Promise<void>;
    copyPlotToNewNumber: (sourcePlot: string, targetPlot: string) => Promise<void>;
    removePlotFromProject: (sourcePlot: string, cleanProjectName: string) => Promise<void>;
    refreshCatalogAfterWrite: () => Promise<void>;
  } = $props();

  const adjacentEditorPlots = $derived.by<string[]>(() => {
    if (!editorPlotNumber || allAvailablePlots.length === 0) return [];
    const idx = allAvailablePlots.findIndex((p) => p.plotNumber === editorPlotNumber);
    if (idx === -1) return [];
    const neighbors: string[] = [];
    const next = allAvailablePlots[idx + 1]?.plotNumber;
    const prev = allAvailablePlots[idx - 1]?.plotNumber;
    if (next && next !== editorPlotNumber) neighbors.push(next);
    if (prev && prev !== editorPlotNumber) neighbors.push(prev);
    return neighbors;
  });

  async function loadFS882Editor() {
    const module = await import('../entry/FS882Form.svelte');
    fs882ModuleLoaded = true;
    return module;
  }
</script>

{#if mode === 'metadata' && $projectState?.contextId}
  <div class="p-3 space-y-3" data-standalone-metadata-host>
    <div
      class="flex flex-wrap items-center justify-between gap-2 rounded border border-vpro-border bg-vpro-surface-subtle px-3 py-2 text-xs"
    >
      <div class="flex flex-wrap items-center gap-2">
        <span class="font-semibold text-vpro-navy">Project Metadata ({$projectState.activeProject})</span>
        {#if allAvailablePlots.length > 1}
          <label class="inline-flex items-center gap-1.5 text-vpro-ink-secondary" for="standalone-metadata-plot-select">
            <span>Plot scope:</span>
            <select
              id="standalone-metadata-plot-select"
              class="rounded border border-vpro-border bg-white px-2 py-1 font-mono text-xs"
              value={standaloneMetadataPlot}
              disabled={localEditorBusy || Boolean(standaloneMetadataEditor?.hasUnsavedChanges?.())}
              onchange={(e) => {
                standaloneMetadataPlot = e.currentTarget.value;
              }}
            >
              {#each allAvailablePlots as p (p.plotNumber)}
                <option value={p.plotNumber}>{p.plotNumber}</option>
              {/each}
            </select>
          </label>
        {/if}
      </div>
      {#if !IS_WEB_READONLY}
        <button
          type="button"
          class="rounded border border-vpro-navy bg-white px-2.5 py-1 font-semibold text-vpro-navy hover:bg-vpro-navy-tint disabled:opacity-50"
          disabled={localEditorBusy || Boolean(standaloneMetadataEditor?.hasUnsavedChanges?.())}
          onclick={() => {
            standaloneMetadataPlot = '';
            localEditorBusy = false;
            navigate('project-admin');
          }}
        >
          Open Metadata Presets &amp; Project Admin
        </button>
      {/if}
    </div>
    {#key `${$projectState.contextId}:${standaloneMetadataPlot}`}
      {#await import('../admin/ProjectMetadataEditor.svelte')}
        <p role="status" class="p-4 text-sm">Loading Project Metadata {IS_WEB_READONLY ? 'Viewer' : 'Editor'}...</p>
      {:then { default: ProjectMetadataEditor }}
        <ProjectMetadataEditor
          bind:this={standaloneMetadataEditor}
          client={bindContextPlots($projectState.contextId)}
          contextId={$projectState.contextId}
          plot={standaloneMetadataPlot}
          allowCreation={!IS_WEB_READONLY}
          allowTemplateCreation={!IS_WEB_READONLY}
          allowRestoration={!IS_WEB_READONLY}
          onbusy={(b) => {
            localEditorBusy = b;
          }}
          oncommitted={async () => {
            const currentCtx = $projectState?.contextId;
            if (currentCtx) invalidateProjectIdChoices(currentCtx);
            const nextState = await stateReads.track(ContextService.GetState());
            projectState.set(nextState);
          }}
          onclosed={() => {
            standaloneMetadataPlot = '';
            localEditorBusy = false;
          }}
        />
      {:catch loadError}
        <p class="error" role="alert">Project Metadata Editor could not load: {formatError(loadError)}</p>
      {/await}
    {/key}
  </div>
{:else}
  <div class="h-full flex flex-col p-2">
    {#if plotFindOpen}
      <section aria-label="Find scoped plot" class="mb-2 p-3 border rounded">
        <form
          onsubmit={(event) => {
            event.preventDefault();
            void findScopedPlot();
          }}
          class="flex flex-wrap items-end gap-2"
        >
          <label for="find-scoped-plot" class="flex flex-col gap-1 flex-1 min-w-0"
            >Exact plot number
            <input
              id="find-scoped-plot"
              class="px-2 py-1 border rounded min-w-0"
              bind:value={plotFindQuery}
              oninput={() => {
                plotFindResult = null;
                plotFindError = '';
              }}
              disabled={busy || editorBusy || transitionWorking || pendingTransition !== null}
            />
          </label>
          <button
            type="submit"
            class="px-3 py-1 border rounded disabled:opacity-50"
            disabled={busy || editorBusy || transitionWorking || pendingTransition !== null}
            >Find in current scope</button
          >
          <button
            type="button"
            class="px-3 py-1 border rounded disabled:opacity-50"
            disabled={busy || transitionWorking || pendingTransition !== null}
            onclick={() => {
              plotFindOpen = false;
              plotFindResult = null;
              plotFindError = '';
            }}>Dismiss find</button
          >
        </form>
        {#if plotFindError}<p role="alert" class="mt-2 text-vpro-error">{plotFindError}</p>{/if}
        {#if plotFindResult}
          <p role="status" class="mt-2">
            Found plot {JSON.stringify(plotFindResult.plot.plotNumber)} in the current recordset.
          </p>
          <button
            type="button"
            class="mt-2 px-3 py-1 border rounded disabled:opacity-50"
            disabled={busy ||
              editorBusy ||
              transitionWorking ||
              pendingTransition !== null ||
              plotFindResult.contextId !== $projectState?.contextId ||
              plotFindResult.plot.plotNumber === editorPlotNumber}
            onclick={() => void openFoundPlot()}>Open found plot</button
          >
        {/if}
        <p class="mt-2 text-sm">
          Find is read-only. Exact spaces and case are preserved, including historical long identifiers. Current SU and
          reviewed profile filters stay in effect. Open rechecks the target after Save/Discard/Cancel; no record is
          created.
        </p>
      </section>
    {/if}
    <fieldset disabled={busy} class="contents">
      {#key $projectState?.contextId}
        {#key editorEntryForm}
          {#await loadFS882Editor()}
            <p role="status" data-entry-loading="fs882">Loading {editorLabel} editor...</p>
          {:then { default: FS882Form }}
            <FS882Form
              bind:this={editor}
              plotNumber={editorPlotNumber}
              neighborPlots={adjacentEditorPlots}
              contextId={$projectState?.contextId ?? ''}
              entryForm={editorEntryForm}
              availablePlots={allAvailablePlots}
              onSelectPlotForTwoPage={(p) => {
                void requestTransition(async () => {
                  const found = allAvailablePlots.find((item) => item.plotNumber === p) ?? null;
                  if (found) selected = found;
                  editorPlotNumber = p;
                  editorEntryForm = 'fs882-twopage';
                  view = 'fs882';
                  error = '';
                });
              }}
              onSwitchTo6x4NewPlot={() => {
                void requestTransition(async () => {
                  editorPlotNumber = undefined;
                  editorEntryForm = 'fs882';
                  view = 'fs882';
                  error = '';
                });
              }}
              canUndoPlotDelete={IS_WEB_READONLY ? false : canUndoEditorPlot}
              onCopyPlotToNumber={IS_WEB_READONLY ? undefined : copyPlotToNewNumber}
              onRemovePlotAction={IS_WEB_READONLY ? undefined : removePlotFromProject}
              onSaved={async (p) => {
                editorPlotNumber = p;
                await refreshCatalogAfterWrite();
              }}
              onClosed={() => navigate('plots')}
              onBusyChange={(val) => {
                localEditorBusy = val;
              }}
              onProfileNavigation={applyProfileNavigation}
              onProfileSUReview={IS_WEB_READONLY ? undefined : reviewProfileSU}
              {profileSelection}
              {initialProfileReviewOpen}
              {onConsumedInitialProfileReview}
              onFindPlot={() => {
                plotFindOpen = true;
              }}
              onOpenPictureManager={IS_WEB_READONLY && $webMeta?.picturesAvailable === false
                ? undefined
                : (p) => {
                    void requestTransition(async () => {
                      pictureManagerPlot = p || editorPlotNumber || '';
                      view = 'picture-manager';
                      error = '';
                    });
                  }}
              onDiagnosticsContextChange={(ctx) => {
                diagnosticsDraft = ctx;
              }}
            />
          {:catch loadErr}
            <p class="error" role="alert" data-entry-load-error="fs882">
              {editorLabel} {IS_WEB_READONLY ? 'viewer' : 'editor'} could not load: {formatError(loadErr)}
            </p>
          {/await}
        {/key}
      {/key}
    </fieldset>
  </div>
  {#if !IS_WEB_READONLY && (closeRequest || pendingTransition)}
    {#await import('./CloseConfirm.svelte') then { default: CloseConfirm }}
      <CloseConfirm
        requestId={closeRequest || (pendingTransition ? 'context' : '')}
        purpose={closeRequest ? 'close' : 'context'}
        {editorLabel}
        working={closeWorking || transitionWorking}
        canSave={closeState?.canSave ?? false}
        saveReason={closeState?.saveReason ?? `Return to the ${editorLabel} editor before saving.`}
        error={closeRequest ? closeError : transitionError}
        onrespond={closeRequest ? respondToClose : respondToTransition}
      />
    {/await}
  {/if}
  {#if editorPlotNumber && $projectState?.contextId}
    {#await import('../diagnostics/LMH25DiagnosticsBar.svelte') then { default: LMH25DiagnosticsBar }}
      {@const matchingDraft = diagnosticsDraft?.plotNumber === editorPlotNumber ? diagnosticsDraft : null}
      <div class="px-2 pb-2">
        <LMH25DiagnosticsBar
          contextId={$projectState.contextId}
          plotNumber={editorPlotNumber}
          header={matchingDraft?.header ?? null}
          humus={matchingDraft?.humus ?? []}
          mineral={matchingDraft?.mineral ?? []}
          waitForDraft={true}
          onApplyHumusThickness={IS_WEB_READONLY ? undefined : (v) => editor?.applyDiagnosticHumusThickness?.(v)}
          onApplyKeyedSMR={IS_WEB_READONLY ? undefined : (v) => editor?.applyDiagnosticSMR?.(v)}
          onApplyKeyedSNR={IS_WEB_READONLY ? undefined : (v) => editor?.applyDiagnosticSNR?.(v)}
        />
      </div>
    {/await}
  {/if}
{/if}
