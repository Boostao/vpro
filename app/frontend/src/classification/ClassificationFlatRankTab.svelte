<script lang="ts">
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

<section class="vpro-cls-flat-pane" aria-label="Editable Flat Phytosociological Hierarchy Table">
  <div class="vpro-cls-subtoolbar">
    <div>
      <strong>Wide Phytosociological Rank Editor</strong>
      <span class="vpro-cls-muted">
        Prefix any branch/unit name with <code>~</code> to mark a Summary Vegetation breakpoint.
      </span>
    </div>
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
          <th>Action</th>
        </tr>
      </thead>
      <tbody>
        {#each flatDraftRows as row, idx (idx)}
          <tr>
            <td class="mono">{idx + 1}</td>
            {#each PHYTOSOCIOLOGICAL_RANK_COLUMNS as col (col.key)}
              {@const cellVal = row[col.key]}
              <td class:breakpoint-cell={cellVal.trim().startsWith('~')}>
                <input
                  type="text"
                  value={cellVal}
                  placeholder={col.label}
                  oninput={e => {
                    flatDraftRows[idx] = {
                      ...flatDraftRows[idx],
                      [col.key]: e.currentTarget.value,
                    };
                    flatDirty = true;
                  }}
                />
              </td>
            {/each}
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
          </tr>
        {/each}
        {#if flatDraftRows.length === 0}
          <tr>
            <td colspan={PHYTOSOCIOLOGICAL_RANK_COLUMNS.length + 2} class="vpro-cls-empty">
              No hierarchy rows defined yet. Click "+ Add Rank Row" or "New Hierarchy" to begin.
            </td>
          </tr>
        {/if}
      </tbody>
    </table>
  </div>
</section>
