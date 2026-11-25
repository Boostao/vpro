<script lang="ts">
  import { Plus, Trash2 } from '@lucide/svelte';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import DrainageFields from './DrainageFields.svelte';
  import GeologyCodeFields from './GeologyCodeFields.svelte';
  import OrdinaryFields from './OrdinaryFields.svelte';
  import ParentCodeFields from './ParentCodeFields.svelte';
  import SoilCodeFields from './SoilCodeFields.svelte';
  import SoilCodeReference from './SoilCodeReference.svelte';
  import SourceChild from './SourceChild.svelte';
  import SourcePage from './SourcePage.svelte';
  import type { FS882SoilHorizonSectionProps } from './fs882SoilTypes';
  import { embeddedForm } from './paperLayout';

  let {
    draft = $bindable(),
    original,
    capabilities,
    headerRevision = 0,
    sourceHeaderValues,
    ordinarySoilUnavailable,
    historicalSoilUnavailable,
    showSoilCodeReference = false,
    soilReferenceBusy,
    soilReferenceError,
    soilEditingDisabled,
    soilUnsaved,
    headerInputsDisabled,
    busy,
    headerWorkflowBusy,
    coordinateBusy,
    workingUnitBusy,
    qualityBusy,
    siteCodeBusy,
    regionCodeBusy,
    soilCodeBusy = $bindable(false),
    geologyCodeBusy = $bindable(false),
    parentCodeBusy = $bindable(false),
    drainageBusy = $bindable(false),
    childRevision,
    soilDrafts,
    soilSuggestions,
    humusList,
    mineralList,
    sourceRows,
    markDirty,
    validateHeader,
    loadSoilSuggestions,
    openNewChild,
    stageSoilCell,
    deleteSourceChild,
    deleteHumus,
  }: FS882SoilHorizonSectionProps & { headerRevision?: number } = $props();
</script>

{#if ordinarySoilUnavailable}<p role="status" data-soil-ordinary-unavailable>{ordinarySoilUnavailable}</p>{/if}
{#if historicalSoilUnavailable}<p role="status" data-soil-historical-unavailable>{historicalSoilUnavailable}</p>{/if}
{#if !ordinarySoilUnavailable}
  {#if soilReferenceBusy}<p role="status">Loading soil reference suggestions...</p>{/if}
  {#if soilReferenceError}
    <p role="alert">{soilReferenceError}</p>
    <button
      type="button"
      disabled={busy || soilReferenceBusy || headerWorkflowBusy}
      onclick={() => void loadSoilSuggestions()}>Retry soil references</button
    >
  {/if}
{/if}
{#if showSoilCodeReference}<SoilCodeReference disabled={busy || headerWorkflowBusy} />{/if}
{#if !IS_WEB_READONLY}
  <div class="flex gap-2 mb-3 text-xs">
    <button disabled={soilEditingDisabled || soilUnsaved} onclick={() => openNewChild('humus')}>Add Humus Layer</button>
    <button disabled={soilEditingDisabled || soilUnsaved} onclick={() => openNewChild('mineral')}
      >Add Mineral Layer</button
    >
  </div>
{/if}
<OrdinaryFields
  bind:draft
  {original}
  {capabilities}
  scope="soils"
  disabled={headerInputsDisabled}
  onchange={markDirty}
  onvalidation={validateHeader}
>
  {#snippet children(ordinaryEditor)}
    <DrainageFields
      bind:draft
      {original}
      {capabilities}
      disabled={headerInputsDisabled}
      onchange={markDirty}
      onvalidation={validateHeader}
      onbusy={(pending) => {
        drainageBusy = pending;
      }}
    >
      {#snippet children(drainageEditor)}
        <SoilCodeFields
          bind:draft
          {original}
          {capabilities}
          disabled={headerInputsDisabled ||
            coordinateBusy ||
            workingUnitBusy ||
            qualityBusy ||
            siteCodeBusy ||
            regionCodeBusy ||
            geologyCodeBusy}
          onchange={markDirty}
          onvalidation={validateHeader}
          onbusy={(pending) => {
            soilCodeBusy = pending;
          }}
        >
          {#snippet children(editor)}
            <GeologyCodeFields
              bind:draft
              {original}
              {capabilities}
              disabled={headerInputsDisabled ||
                coordinateBusy ||
                workingUnitBusy ||
                qualityBusy ||
                siteCodeBusy ||
                regionCodeBusy ||
                soilCodeBusy}
              onchange={markDirty}
              onvalidation={validateHeader}
              onbusy={(pending) => {
                geologyCodeBusy = pending;
              }}
            >
              {#snippet children(geologyEditor)}
                <ParentCodeFields
                  bind:draft
                  {original}
                  {capabilities}
                  scope="soils"
                  disabled={headerInputsDisabled}
                  onchange={markDirty}
                  onvalidation={validateHeader}
                  onbusy={(pending) => {
                    parentCodeBusy = pending;
                  }}
                >
                  {#snippet children(parentEditor)}
                    {#key headerRevision}
                      <SourcePage
                        name="Soil/Terrain"
                        values={sourceHeaderValues}
                        {editor}
                        editors={[
                          ...(geologyEditor ? [geologyEditor] : []),
                          ...(parentEditor ? [parentEditor] : []),
                          ...(ordinaryEditor ? [ordinaryEditor] : []),
                          ...(drainageEditor ? [drainageEditor] : []),
                        ]}
                      >
                        {#snippet embedded(control)}
                          {@const child = embeddedForm(control.controlId)}
                          {#if ordinarySoilUnavailable}
                            <p role="status" data-soil-ordinary-unavailable={child.form}>{ordinarySoilUnavailable}</p>
                          {:else if historicalSoilUnavailable}
                            <p role="status" data-soil-historical-unavailable={child.form}>{historicalSoilUnavailable}</p>
                          {:else}
                            <SourceChild
                              name={child.form}
                              rows={sourceRows(child.form)}
                              revision={childRevision}
                              disabled={soilEditingDisabled}
                              deleteDisabled={soilUnsaved}
                              onsoilstage={stageSoilCell}
                              {soilDrafts}
                              {soilSuggestions}
                              ondelete={IS_WEB_READONLY ? undefined : deleteSourceChild}
                            />
                          {/if}
                        {/snippet}
                      </SourcePage>
                    {/key}
                  {/snippet}
                </ParentCodeFields>
              {/snippet}
            </GeologyCodeFields>
          {/snippet}
        </SoilCodeFields>
      {/snippet}
    </DrainageFields>
  {/snippet}
</OrdinaryFields>
{#if !ordinarySoilUnavailable}
  <div class="mt-3 text-xs text-vpro-ink-secondary">
    <p>
      Suggestions are optional. Raw text is never completed or case-changed automatically; no soil totals are guessed.
    </p>
    <button
      type="button"
      class="mt-2 px-2 py-1 border rounded"
      disabled={busy || soilReferenceBusy || headerWorkflowBusy}
      onclick={() => void loadSoilSuggestions()}>Reload soil references</button
    >
  </div>
  <details class="mt-4 border border-vpro-border rounded p-3">
    <summary class="text-xs font-semibold cursor-pointer">Humus &amp; mineral horizon records</summary>
    <div class="space-y-6">
      <div class="space-y-3" data-help-id="humus.upper_lower_depth">
        <div class="flex justify-between items-center">
          <h3 class="font-bold text-xs uppercase tracking-wider text-vpro-ink-secondary">
            Humus Layers ({humusList.length})
          </h3>
          <button
            type="button"
            onclick={() => openNewChild('humus')}
            disabled={soilEditingDisabled || soilUnsaved}
            class="px-2.5 py-1 bg-stone-700 hover:bg-vpro-ink text-white rounded text-xs flex items-center gap-1"
          >
            <Plus size={14} /> Add Humus Layer
          </button>
        </div>
        <div class="border border-vpro-border rounded overflow-x-auto bg-white">
          <table class="w-full text-left text-xs">
            <thead class="bg-vpro-canvas border-b border-vpro-border text-vpro-ink-secondary font-semibold">
              <tr>
                <th class="p-2">Horizon</th>
                <th class="p-2">Upper Depth</th>
                <th class="p-2">Lower Depth</th>
                <th class="p-2">pH</th>
                <th class="p-2">Comment</th>
                <th class="p-2">Action</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-vpro-rail">
              {#each humusList as h (h.id)}
                <tr class="hover:bg-vpro-surface-subtle" data-source-form="SoilHumusXL">
                  <td class="p-2 font-semibold" data-column="Horizon">{h.horizon ?? '—'}</td>
                  <td class="p-2" data-column="UpperDepth">{h.upperDepth ?? '—'}</td>
                  <td class="p-2" data-column="LowerDepth">{h.lowerDepth ?? '—'}</td>
                  <td class="p-2" data-column="HumusFormpH">{h.ph ?? '—'}</td>
                  <td class="p-2">{h.comment ?? '—'}</td>
                  <td class="p-2">
                    <button
                      type="button"
                      onclick={() => void deleteHumus(h.id)}
                      disabled={soilEditingDisabled || soilUnsaved}
                      class="text-red-600 hover:text-red-800 p-1"
                      title="Delete humus row"
                      aria-label="Delete humus row"
                    >
                      <Trash2 size={14} />
                    </button>
                  </td>
                </tr>
              {:else}
                <tr
                  ><td colspan="6" class="p-4 text-center text-vpro-ink-muted"
                    >{historicalSoilUnavailable ?? 'No humus layers recorded.'}</td
                  ></tr
                >
              {/each}
            </tbody>
          </table>
        </div>
      </div>

      <div class="space-y-3" data-help-id="mineral.texture_cf">
        <h3 class="font-bold text-xs uppercase tracking-wider text-vpro-ink-secondary">
          Mineral Layers ({mineralList.length})
        </h3>
        <div class="border border-vpro-border rounded overflow-x-auto bg-white">
          <table class="w-full text-left text-xs">
            <thead class="bg-vpro-canvas border-b border-vpro-border text-vpro-ink-secondary font-semibold">
              <tr>
                <th class="p-2">Horizon</th>
                <th class="p-2">Upper Depth</th>
                <th class="p-2">Lower Depth</th>
                <th class="p-2">Texture</th>
                <th class="p-2">Colour</th>
                <th class="p-2">Comments</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-vpro-rail">
              {#each mineralList as m (m.id)}
                <tr class="hover:bg-vpro-surface-subtle" data-source-form="SoilMineralXL">
                  <td class="p-2 font-semibold" data-column="Horizon">{m.horizon ?? '—'}</td>
                  <td class="p-2" data-column="UpperDepth">{m.upperDepth ?? '—'}</td>
                  <td class="p-2" data-column="LowerDepth">{m.lowerDepth ?? '—'}</td>
                  <td class="p-2" data-column="Texture">{m.texture ?? '—'}</td>
                  <td class="p-2" data-column="Colour">{m.colour ?? '—'}</td>
                  <td class="p-2">{m.comments ?? '—'}</td>
                </tr>
              {:else}
                <tr
                  ><td colspan="6" class="p-4 text-center text-vpro-ink-muted"
                    >{historicalSoilUnavailable ?? 'No mineral layers recorded.'}</td
                  ></tr
                >
              {/each}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </details>
{/if}
