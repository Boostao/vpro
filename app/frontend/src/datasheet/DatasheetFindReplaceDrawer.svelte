<script lang="ts">
  import type { DatasheetColumnMeta, DatasheetFindReplacePreview, DatasheetPage } from './universalDatasheetGrid';

  let {
    page,
    editableColumns = [],
    findColumn = $bindable(''),
    findText = $bindable(''),
    replaceText = $bindable(''),
    findMatchCase = $bindable(false),
    findExactCell = $bindable(false),
    findPreview = null,
    findBusy = false,
    saving = false,
    onRunPreview,
    onApplyValid,
  }: {
    page: DatasheetPage;
    editableColumns?: DatasheetColumnMeta[];
    findColumn?: string;
    findText?: string;
    replaceText?: string;
    findMatchCase?: boolean;
    findExactCell?: boolean;
    findPreview?: DatasheetFindReplacePreview | null;
    findBusy?: boolean;
    saving?: boolean;
    onRunPreview: () => Promise<void> | void;
    onApplyValid: () => Promise<void> | void;
  } = $props();
</script>

<section class="vpro-ds-find-drawer" aria-label="Column Find and Replace">
  <div class="vpro-ds-find-controls">
    <label>
      <span>Column</span>
      <select bind:value={findColumn}>
        {#each editableColumns as col (col.name)}
          <option value={col.name}>{col.name} ({col.kind})</option>
        {/each}
      </select>
    </label>
    <label>
      <span>Find</span>
      <input type="text" bind:value={findText} placeholder="Text to find..." />
    </label>
    <label>
      <span>Replace With</span>
      <input type="text" bind:value={replaceText} placeholder="Replacement (blank = NULL)" />
    </label>
    <label class="vpro-ds-inline-check">
      <input type="checkbox" bind:checked={findMatchCase} />
      <span>Match case</span>
    </label>
    <label class="vpro-ds-inline-check">
      <input type="checkbox" bind:checked={findExactCell} />
      <span>Whole cell</span>
    </label>
    <button type="button" class="vpro-btn-secondary" disabled={findBusy} onclick={onRunPreview}>
      {findBusy ? 'Previewing...' : 'Preview Matches'}
    </button>
    {#if findPreview && findPreview.validCount > 0}
      <button type="button" class="vpro-btn-primary" disabled={saving} onclick={onApplyValid}>
        Apply {findPreview.validCount} Valid Replacement(s)
      </button>
    {/if}
  </div>

  {#if findPreview}
    <div class="vpro-ds-find-summary">
      <p>
        Matched <strong>{findPreview.matchedRows}</strong> row(s) in
        <code>{findPreview.tableName}.{findPreview.column}</code> —
        <strong>{findPreview.validCount}</strong> valid,
        <strong>{findPreview.invalidCount}</strong> blocked by validation.
      </p>
      {#if findPreview.items.length > 0}
        <div class="vpro-ds-find-preview-scroll">
          <table>
            <thead>
              <tr>
                <th>{page.pinnedColumn}</th>
                <th>Before</th>
                <th>After</th>
                <th>Validation</th>
              </tr>
            </thead>
            <tbody>
              {#each findPreview.items.slice(0, 50) as item (item.rowId)}
                <tr>
                  <td class="mono">{item.pinnedIdentity}</td>
                  <td class="mono">{item.beforeText || '(NULL)'}</td>
                  <td class="mono">{item.afterText || '(NULL)'}</td>
                  <td class:text-err={!!item.validationError}>
                    {item.validationError || 'Ready'}
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {/if}
    </div>
  {/if}
</section>
