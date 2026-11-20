<script lang="ts">
  import { untrack, type Snippet } from 'svelte';
  import type { FS882Header } from '../../bindings/github.com/boostao/vpro/app';
  import type { PaperControl } from './paperLayout';
  import FieldGuidance from './FieldGuidance.svelte';
  import {
    substrateKey,
    substrateLabels,
    stageSubstrate,
    substrateErrors,
    substrateValidation,
    substrateSession,
    rememberSubstrateSession,
    type SubstrateValues,
    type SubstrateDrafts,
    type SubstrateKey,
  } from './substrateEditor';

  let {
    draft = $bindable(),
    original,
    controls,
    position,
    capabilities,
    disabled,
    onchange,
    onvalidation,
    children,
  }: {
    draft: FS882Header;
    original: SubstrateValues | null;
    controls: PaperControl[];
    position: (control: PaperControl) => string;
    capabilities: Record<string, boolean | undefined>;
    disabled: boolean;
    onchange: () => void;
    onvalidation: (key: 'substrate', message: string | null) => void;
    children: Snippet<[Snippet<[PaperControl?]>]>;
  } = $props();
  let staged = $state<SubstrateDrafts>({});
  const errors = $derived(substrateErrors(staged));
  $effect(() => {
    const identity = draft;
    const baseline = original;
    untrack(() => {
      staged = substrateSession(identity, baseline);
    });
  });
  $effect(() => {
    const message = substrateValidation(staged, draft, original);
    untrack(() => onvalidation('substrate', message));
  });
  function stage(key: SubstrateKey, raw: string): void {
    const previous = staged[key];
    staged = stageSubstrate(staged, key, raw, original?.[key] ?? null);
    rememberSubstrateSession(draft, staged, original);
    const cell = staged[key];
    if (!cell) return;
    const changed =
      cell.error !== null || (previous?.error !== null && previous?.error !== undefined) || cell.value !== draft[key];
    if (cell.error === null) draft[key] = cell.value;
    if (changed) onchange();
  }
</script>

{#if errors.length > 0}
  <div class="substrate-toolbar" aria-label="Substrate draft safety controls">
    {#each errors as message}<span role="alert">{message}</span>{/each}
  </div>
{/if}
{@render children(substrateInputs)}
<FieldGuidance title="Substrate entry guidance">
  <p>
    Substrate values are nullable numbers. Negative values, 100, 101 and totals above 100 are permitted; nothing is
    balanced or changed automatically.
  </p>
  <p>
    Save is explicit. Desktop values retain float64 precision within the finite Access Single range instead of rounding
    to Single.
  </p>
</FieldGuidance>
{#snippet substrateInputs(only?: PaperControl)}
  {#each (only ? [only] : controls).filter((control) => substrateKey(control.column) && control.type === 'TextBox') as control (control.controlId)}
    {@const key = substrateKey(control.column)}
    {#if key}
      <input
        class="substrate-control"
        id={`header-${key}`}
        data-column={control.column}
        data-source-control={control.controlName}
        style={position(control)}
        type="text"
        inputmode="decimal"
        aria-label={substrateLabels[key]}
        value={staged[key]?.raw ?? String(draft[key] ?? '')}
        aria-invalid={staged[key]?.error ? 'true' : undefined}
        disabled={disabled || capabilities[key] !== true || !control.enabled || control.locked}
        placeholder={capabilities[key] === true ? '' : 'Pending'}
        oninput={(event) => stage(key, event.currentTarget.value)}
      />
    {/if}
  {/each}
{/snippet}

<style>
  .substrate-toolbar {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.45rem;
    padding: 0.35rem 0.5rem;
    margin-bottom: 0.5rem;
    border: 1px solid var(--vpro-error-border);
    background: var(--vpro-error-bg);
    color: var(--vpro-error-ink);
    border-radius: 4px;
    font-size: 0.75rem;
  }
  .substrate-control {
    box-sizing: border-box;
    width: 100%;
    min-width: 0;
    min-height: 40px;
    border: 1px solid var(--vpro-forest-border);
    border-radius: 4px;
    padding: 0.5rem 0.65rem;
    background: var(--vpro-surface, white);
    color: var(--vpro-ink);
    font: inherit;
    font-family: var(--vpro-font-mono, monospace);
    font-variant-numeric: tabular-nums;
    line-height: 1.4;
  }
  .substrate-control:disabled {
    color: var(--vpro-ink-muted);
    background: var(--vpro-surface-subtle);
  }
  .substrate-control:focus {
    outline: 2px solid var(--vpro-focus-ring);
    outline-offset: 1px;
  }
  .substrate-control[aria-invalid='true'] {
    border-color: var(--vpro-error);
  }
</style>
