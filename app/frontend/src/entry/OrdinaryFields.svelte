<script lang="ts">
  import { untrack, type Snippet } from 'svelte';
  import type { FS882Header } from '../../bindings/github.com/boostao/vpro/app';
  import type { PaperControl } from './paperLayout';
  import {
    ordinaryFields,
    additionalParentFields,
    nullableParentFlags,
    nullableParentField,
    ordinaryTextError,
    ordinaryNumberValue,
    ordinaryValidation,
    sourceParentBooleanNullError,
    ordinarySession,
    rememberOrdinarySession,
    type OrdinaryScope,
    type OrdinaryNumberField,
    type OrdinaryTextField,
    type OrdinaryDrafts,
  } from './ordinaryEditor';
  let {
    draft = $bindable(),
    original,
    scope,
    capabilities,
    disabled,
    onchange,
    onvalidation,
    onVegNotesTab,
    children,
  }: {
    draft: FS882Header;
    original: FS882Header | null;
    scope: OrdinaryScope;
    capabilities: Record<string, boolean | undefined>;
    disabled: boolean;
    onchange: () => void;
    onvalidation: (key: string, message: string | null) => void;
    onVegNotesTab?: () => void;
    children: Snippet<[{ columns: readonly string[]; input: Snippet<[PaperControl, string]> } | undefined]>;
  } = $props();
  let staged = $state<OrdinaryDrafts>({});
  const fields = $derived(
    [...ordinaryFields, ...additionalParentFields, ...nullableParentFlags].filter((field) => field.scope === scope)
  );
  const validation = $derived(ordinaryValidation(scope, draft, original, staged, fields));
  $effect(() => {
    const identity = draft,
      baseline = original;
    untrack(() => {
      staged = ordinarySession(identity, baseline);
    });
  });
  $effect(() => {
    const message = validation;
    untrack(() => onvalidation(`ordinary-${scope}`, message));
  });
  function setText(field: OrdinaryTextField, raw: string): void {
    const value = raw === '' ? null : raw;
    if (draft[field.key] === value) return;
    draft[field.key] = value;
    onchange();
  }
  function stage(field: OrdinaryNumberField, raw: string): void {
    const previous = staged[field.key];
    const cell = ordinaryNumberValue(field, raw, original?.[field.key] ?? null);
    staged = { ...staged, [field.key]: cell };
    rememberOrdinarySession(draft, original, staged);
    const changed = cell.error !== null || !!previous?.error || cell.value !== draft[field.key];
    if (cell.error === null) draft[field.key] = cell.value;
    if (changed) onchange();
  }
</script>

{#if validation}<p role="alert">{validation}</p>{/if}
{@render children(fields.length ? { columns: fields.map((field) => field.column), input } : undefined)}
{#snippet input(control: PaperControl, position: string)}
  {@const field = nullableParentField(control.column)}
  {#if field?.kind === 'flag' && control.type === 'CheckBox'}
    {@const nullDiagnostic = sourceParentBooleanNullError(field.column, false, true)}
    {@const nullBlocked = nullDiagnostic !== null && original?.[field.key] != null}
    <div class="nullable-flag" style={position}>
      <input
        id={`header-${field.key}`}
        data-column={field.column}
        data-source-control={control.controlName}
        type="checkbox"
        aria-label={field.label}
        checked={draft[field.key] === true}
        indeterminate={draft[field.key] === null}
        disabled={disabled || capabilities[field.key] !== true || !control.enabled || control.locked}
        onchange={(event) => {
          draft[field.key] = event.currentTarget.checked;
          onchange();
        }}
      />
      <span>{draft[field.key] === null ? 'Not recorded (NULL)' : draft[field.key] ? 'Yes' : 'No'}</span>
      <button
        type="button"
        aria-label={`Clear ${field.label} to NULL`}
        disabled={disabled ||
          capabilities[field.key] !== true ||
          !control.enabled ||
          control.locked ||
          draft[field.key] === null ||
          nullBlocked}
        onclick={() => {
          draft[field.key] = null;
          onchange();
        }}>Clear</button
      >
      {#if nullDiagnostic}<p class="text-xs">{nullDiagnostic} Unchanged historical NULL is retained.</p>{/if}
    </div>
  {:else if field && field.kind !== 'flag' && control.type === 'TextBox'}
    {#if field.kind === 'memo'}
      <textarea
        class="ordinary-control"
        id={`header-${field.key}`}
        data-column={field.column}
        data-source-control={control.controlName}
        style={position}
        aria-label={field.label}
        rows="4"
        value={draft[field.key] ?? ''}
        disabled={disabled || capabilities[field.key] !== true || !control.enabled || control.locked}
        aria-invalid={ordinaryTextError(field, draft[field.key], original?.[field.key] ?? null) !== null}
        oninput={(event) => setText(field, event.currentTarget.value)}
        onkeydown={(event) => {
          if (field.key === 'vegNotes' && event.key === 'Tab' && onVegNotesTab) {
            event.preventDefault();
            onVegNotesTab();
          }
        }}></textarea>
    {:else if field.kind === 'text'}
      <input
        class="ordinary-control"
        id={`header-${field.key}`}
        data-column={field.column}
        data-source-control={control.controlName}
        style={position}
        aria-label={field.label}
        value={draft[field.key] ?? ''}
        disabled={disabled || capabilities[field.key] !== true || !control.enabled || control.locked}
        aria-invalid={ordinaryTextError(field, draft[field.key], original?.[field.key] ?? null) !== null}
        oninput={(event) => setText(field, event.currentTarget.value)}
      />
    {:else}
      <input
        class="ordinary-control"
        id={`header-${field.key}`}
        data-column={field.column}
        data-source-control={control.controlName}
        style={position}
        type="text"
        inputmode="decimal"
        aria-label={field.label}
        value={staged[field.key]?.raw ?? String(draft[field.key] ?? '')}
        disabled={disabled || capabilities[field.key] !== true || !control.enabled || control.locked}
        aria-invalid={staged[field.key]?.error ? 'true' : undefined}
        oninput={(event) => stage(field, event.currentTarget.value)}
      />
    {/if}
  {/if}
{/snippet}

<style>
  .ordinary-control {
    width: 100%;
    min-width: 0;
    min-height: 40px;
    border: 1px solid var(--vpro-border);
    border-radius: 4px;
    padding: 0.5rem 0.65rem;
    background: white;
    color: var(--vpro-ink);
    font: inherit;
    line-height: 1.4;
  }
  .ordinary-control:disabled {
    color: var(--vpro-ink-muted);
    background: var(--vpro-canvas);
  }
  .ordinary-control:focus {
    outline: 2px solid var(--vpro-navy);
    outline-offset: 1px;
  }
  .ordinary-control[aria-invalid='true'] {
    border-color: var(--vpro-error);
  }
  .nullable-flag {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 0.5rem;
    min-height: 40px;
  }
  .nullable-flag input {
    width: 1.25rem;
    height: 1.25rem;
    accent-color: var(--vpro-navy);
  }
  .nullable-flag button {
    padding: 0.25rem 0.5rem;
    border: 1px solid var(--vpro-border);
    border-radius: 4px;
    background: white;
    color: var(--vpro-ink);
  }
  .nullable-flag button:disabled {
    color: var(--vpro-ink-muted);
    background: var(--vpro-canvas);
  }
  p {
    color: var(--vpro-error);
    font-size: 0.75rem;
  }
</style>
