<script lang="ts">
  import type { OtherRecord, SoilSuggestion } from '../../bindings/github.com/boostao/vpro/app';
  import SourceChild from './SourceChild.svelte';
  import SourcePage from './SourcePage.svelte';
  import { embeddedForm } from './paperLayout';
  import type { OtherDrafts, OtherValue } from './otherEditor';
  import type { VegetationAttributeDrafts } from './vegetationAttributeEditor';

  let {
    mode,
    sourceHeaderValues,
    childRevision,
    busy,
    headerWorkflowBusy,
    sourceRows,
    vegetationReadUnavailable = null,
    attributeReferenceBusy = false,
    attributeReferenceError = null,
    attributeEditingDisabled = false,
    attributeDrafts = {},
    attributeSuggestions = [],
    loadAttributeSuggestions = async () => {},
    stageAttributeCell = () => {},
    otherEditingDisabled = false,
    otherUnsaved = false,
    otherDrafts = {},
    otherList = [],
    openNewChild = () => {},
    stageOtherCell = () => {},
    deleteSourceChild = async () => {},
  }: {
    mode: 'vegOther' | 'other';
    sourceHeaderValues: Map<string, unknown>;
    childRevision: number;
    busy: boolean;
    headerWorkflowBusy: boolean;
    sourceRows: (
      name: string
    ) => Array<{ id: number; values: Record<string, string | number | boolean | null | undefined> }>;
    vegetationReadUnavailable?: string | null;
    attributeReferenceBusy?: boolean;
    attributeReferenceError?: string | null;
    attributeEditingDisabled?: boolean;
    attributeDrafts?: VegetationAttributeDrafts;
    attributeSuggestions?: SoilSuggestion[];
    loadAttributeSuggestions?: () => Promise<void>;
    stageAttributeCell?: (id: number, column: string, raw: string) => void;
    otherEditingDisabled?: boolean;
    otherUnsaved?: boolean;
    otherDrafts?: OtherDrafts;
    otherList?: OtherRecord[];
    openNewChild?: (kind: 'humus' | 'mineral' | 'other') => void;
    stageOtherCell?: (id: number, column: string, raw: OtherValue) => void;
    deleteSourceChild?: (name: string, id: number) => Promise<void>;
  } = $props();
</script>

{#if mode === 'vegOther'}
  {#if vegetationReadUnavailable}
    <p role="alert">
      Vegetation attribute editing requires exact unique ordinary IDs. Use the physical-row source views; historical
      NULL/duplicates are preserved.
    </p>
  {:else}
    {#if attributeReferenceBusy}<p role="status">Loading vegetation attribute references...</p>{/if}
    {#if attributeReferenceError}
      <p role="alert">{attributeReferenceError}</p>
      <button
        type="button"
        disabled={busy || attributeReferenceBusy || headerWorkflowBusy}
        onclick={() => void loadAttributeSuggestions()}>Retry attribute references</button
      >
    {/if}
    <SourcePage name="Veg Other" values={sourceHeaderValues}>
      {#snippet embedded(control)}
        {@const child = embeddedForm(control.controlId)}
        <SourceChild
          name={child.form}
          rows={sourceRows(child.form)}
          revision={childRevision}
          disabled={attributeEditingDisabled}
          onattributestage={stageAttributeCell}
          {attributeDrafts}
          {attributeSuggestions}
        />
      {/snippet}
    </SourcePage>
    <div class="mt-3 text-xs text-vpro-ink-secondary">
      <p>
        Suggestions retain source definitions, including duplicates. AF is free numeric entry; species and row creation
        remain unavailable here.
      </p>
      <button
        type="button"
        class="mt-2 px-2 py-1 border rounded"
        disabled={busy || attributeReferenceBusy || headerWorkflowBusy}
        onclick={() => void loadAttributeSuggestions()}>Reload attribute references</button
      >
    </div>
  {/if}
{:else}
  <button class="mb-3 text-xs" disabled={otherEditingDisabled || otherUnsaved} onclick={() => openNewChild('other')}
    >Add Other Data</button
  >
  <SourcePage name="Other" values={sourceHeaderValues}>
    {#snippet embedded(control)}
      {@const child = embeddedForm(control.controlId)}
      <SourceChild
        name={child.form}
        rows={sourceRows(child.form)}
        revision={childRevision}
        disabled={otherEditingDisabled}
        deleteDisabled={otherUnsaved}
        onotherstage={stageOtherCell}
        {otherDrafts}
        ondelete={deleteSourceChild}
      />
    {/snippet}
  </SourcePage>
  <div class="space-y-3">
    <h3 class="font-bold text-xs uppercase tracking-wider text-vpro-ink-secondary">
      Auxiliary Data ({otherList.length})
    </h3>
    <div class="border border-vpro-border rounded overflow-x-auto bg-white">
      <table class="w-full text-left text-xs">
        <thead class="bg-vpro-canvas border-b border-vpro-border text-vpro-ink-secondary font-semibold">
          <tr>
            <th class="p-2">Data Name</th>
            <th class="p-2">Value</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-vpro-rail">
          {#each otherList as o (o.id)}
            <tr class="hover:bg-vpro-surface-subtle">
              <td class="p-2 font-medium">{o.dataName ?? '—'}</td>
              <td class="p-2">{o.dataItem ?? '—'}</td>
            </tr>
          {:else}
            <tr>
              <td colspan="2" class="p-4 text-center text-vpro-ink-muted">No auxiliary data items.</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  </div>
{/if}
