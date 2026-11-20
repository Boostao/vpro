<script lang="ts">
  import type { SpeciesCodeCheckOption } from '../../bindings/github.com/boostao/vpro/app';
  import type { SpeciesCodeCheckRow } from '../../bindings/github.com/boostao/vpro/app/internal/validation/models';
  import { suggestedCodeForRow, type CodeCheckDraft } from './speciesCodeCheckEditor';
  import { speciesEventError } from './vegetationSpeciesEditor';

  let {
    row,
    cell,
    target,
    disabled,
    onApplySuggested,
    onStage,
    onReviewTarget,
    onAccept,
    onIgnore,
    onStartPersonal,
  }: {
    row: SpeciesCodeCheckRow;
    cell: CodeCheckDraft['cells'][string] | undefined;
    target: { entered: string; options: SpeciesCodeCheckOption[] } | undefined;
    disabled: boolean;
    onApplySuggested: (row: SpeciesCodeCheckRow) => void;
    onStage: (id: number, raw: string) => void;
    onReviewTarget: (id: number) => void;
    onAccept: (id: number, all: boolean) => void;
    onIgnore: (id: number, all: boolean) => void;
    onStartPersonal: (row: SpeciesCodeCheckRow) => void;
  } = $props();
</script>

<tr data-code-check-id={row.id}>
  <td>{row.plotNumber} / {row.id}</td>
  <td>
    <div class="font-mono">{row.code === null ? 'NULL' : JSON.stringify(row.code)}</div>
    <div class="mt-1 text-xs text-vpro-ink-muted">Status: {row.status}</div>
    {#if row.suggestedCode && suggestedCodeForRow(row)}
      <div class="mt-1 flex flex-wrap items-center gap-1.5" data-suggested-code={row.suggestedCode}>
        <span
          class="rounded bg-vpro-gold-surface px-1.5 py-0.5 text-xs font-medium text-vpro-ink border border-vpro-gold"
          >Suggested: {row.suggestedCode}</span
        >
        <button
          type="button"
          class="text-xs"
          data-use-suggested-id={row.id}
          {disabled}
          onclick={() => onApplySuggested(row)}>Use suggested ({row.suggestedCode})</button
        >
      </div>
    {/if}
  </td>
  <td>
    <label for={`check-replacement-${row.id}`}
      >Replacement, plot {row.plotNumber}, row {row.id}
      <input
        id={`check-replacement-${row.id}`}
        type="text"
        value={cell?.raw ?? ''}
        {disabled}
        aria-invalid={!!cell?.error}
        oninput={(event) => onStage(row.id, event.currentTarget.value)}
      />
    </label>
    {#if cell && cell.reviewed === cell.raw && cell.raw !== row.code}
      <p class="mt-1 text-xs font-medium text-vpro-success">
        Reviewed replacement ready to save: {JSON.stringify(cell.reviewed)}
      </p>
    {/if}
    <button type="button" class="mt-1" disabled={disabled || !cell} onclick={() => onReviewTarget(row.id)}
      >Review literal target</button
    >
    {#if target && target.entered === cell?.raw}
      <div
        class="mt-2 rounded border border-vpro-border bg-vpro-canvas p-2 text-xs"
        aria-label={`Target definitions, row ${row.id}`}
      >
        {#each target.options as option}
          <p>
            {option.source}: {JSON.stringify(option.code)}; scientific {option.scientificName === null
              ? 'NULL'
              : JSON.stringify(option.scientificName)}; English {option.englishName === null
              ? 'NULL'
              : JSON.stringify(option.englishName)}; Lifeform {option.lifeform ?? 'NULL'}; Codetype {option.codeType ===
            null
              ? 'NULL'
              : JSON.stringify(option.codeType)}.
          </p>
        {/each}
        <p class="mt-1 text-vpro-navy">
          Replacing an old code where the target species already exists on the same plot/layer combines covers safely
          (capped at 99%).
        </p>
        <div class="mt-1.5 flex flex-wrap gap-1.5">
          <button type="button" {disabled} onclick={() => onAccept(row.id, false)}>Use for this physical row</button>
          <button type="button" {disabled} onclick={() => onAccept(row.id, true)}
            >Use for matching originals in this scope</button
          >
        </div>
      </div>
    {/if}
  </td>
  <td>
    <div class="flex flex-wrap gap-1.5">
      <button type="button" {disabled} onclick={() => onIgnore(row.id, false)}>Ignore this row</button>
      <button type="button" {disabled} onclick={() => onIgnore(row.id, true)}>Ignore matching codes locally</button>
      {#if row.status === 'unlisted' && row.code !== null && !speciesEventError(row.code)}
        <button type="button" {disabled} onclick={() => onStartPersonal(row)}>Create personal definition</button>
      {/if}
    </div>
  </td>
</tr>
