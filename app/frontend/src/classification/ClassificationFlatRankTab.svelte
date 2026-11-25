<script lang="ts">
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import {
    createEmptyFlatHierarchyRow,
    PHYTOSOCIOLOGICAL_RANK_COLUMNS,
    type FlatHierarchyRow,
  } from './classificationExplorer';

  interface Props {
    flatDraftRows: FlatHierarchyRow[];
    flatDirty: boolean;
    flatValidationError: string;
    mutating: boolean;
    onOpenDialog: (dialog: 'new_hierarchy' | 'save_hierarchy_as') => void;
    onSaveFlatRows: () => void;
  }

  let {
    flatDraftRows = $bindable(),
    flatDirty = $bindable(),
    flatValidationError,
    mutating,
    onOpenDialog,
    onSaveFlatRows,
  }: Props = $props();
</script>

<section
  class="vpro-cls-flat-pane"
  aria-label={IS_WEB_READONLY
    ? 'Read-Only Flat Phytosociological Hierarchy Table'
    : 'Editable Flat Phytosociological Hierarchy Table'}
>
  <div class="vpro-cls-subtoolbar">
    <div>
      <strong>{IS_WEB_READONLY ? 'Wide Phytosociological Rank Viewer' : 'Wide Phytosociological Rank Editor'}</strong>
      <span class="vpro-cls-muted">
        {IS_WEB_READONLY
          ? "Rows prefixed with '~' mark Summary Vegetation report breakpoints."
          : "Prefix any branch/unit name with ~ to mark a Summary Vegetation breakpoint."}
      </span>
    </div>
    {#if !IS_WEB_READONLY}
      <div class="vpro-cls-actions">
        <button type="button" class="vpro-btn-secondary" onclick={() => onOpenDialog('new_hierarchy')}>
          New Hierarchy
        </button>
        <button type="button" class="vpro-btn-secondary" onclick={() => onOpenDialog('save_hierarchy_as')}>
          Save Hierarchy As
        </button>
        <button
          type="button"
          class="vpro-btn-secondary"
          onclick={() => {
            flatDraftRows = [...flatDraftRows, createEmptyFlatHierarchyRow()];
            flatDirty = true;
          }}
        >
          + Add Rank Row
        </button>
        <button
          type="button"
          class="vpro-btn-primary"
          disabled={!flatDirty || !!flatValidationError || mutating}
          onclick={onSaveFlatRows}
        >
          {mutating ? 'Saving...' : 'Save Flat Hierarchy'}
        </button>
      </div>
    {/if}
  </div>

  {#if flatValidationError}
    <p role="alert" class="vpro-cls-alert">{flatValidationError}</p>
  {/if}

  <div class="vpro-cls-flat-scroll">
    <table class="vpro-cls-flat-table">
      <thead>
        <tr>
          <th>#</th>
          {#each PHYTOSOCIOLOGICAL_RANK_COLUMNS as col (col.key)}
            <th>{col.label}</th>
          {/each}
          {#if !IS_WEB_READONLY}<th>Action</th>{/if}
        </tr>
      </thead>
      <tbody>
        {#each flatDraftRows as row, idx (idx)}
          <tr>
            <td class="mono">{idx + 1}</td>
            {#each PHYTOSOCIOLOGICAL_RANK_COLUMNS as col (col.key)}
              {@const cellVal = row[col.key] ?? ''}
              <td class:breakpoint-cell={cellVal.trim().startsWith('~')}>
                <input
                  type="text"
                  aria-label={`${col.label} for row ${idx + 1}`}
                  value={cellVal}
                  placeholder={col.label}
                  readonly={IS_WEB_READONLY}
                  oninput={(e) => {
                    if (IS_WEB_READONLY) return;
                    flatDraftRows[idx] = {
                      ...flatDraftRows[idx],
                      [col.key]: e.currentTarget.value,
                    };
                    flatDirty = true;
                  }}
                />
              </td>
            {/each}
            {#if !IS_WEB_READONLY}
              <td>
                <button
                  type="button"
                  class="vpro-btn-mini"
                  onclick={() => {
                    flatDraftRows = flatDraftRows.filter((_, i) => i !== idx);
                    flatDirty = true;
                  }}
                >
                  Remove
                </button>
              </td>
            {/if}
          </tr>
        {/each}
        {#if flatDraftRows.length === 0}
          <tr>
            <td colspan={PHYTOSOCIOLOGICAL_RANK_COLUMNS.length + (IS_WEB_READONLY ? 1 : 2)} class="vpro-cls-empty">
              {IS_WEB_READONLY
                ? 'No hierarchy rows are defined in this snapshot.'
                : 'No hierarchy rows defined yet. Click "+ Add Rank Row" or "New Hierarchy" to begin.'}
            </td>
          </tr>
        {/if}
      </tbody>
    </table>
  </div>
</section>
