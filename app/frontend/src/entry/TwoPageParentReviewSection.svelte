<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { TwoPageParentForm } from './twoPageParentSession';

  let {
    ariaLabel,
    error,
    form,
    locked,
    closeLabel,
    onchooseform,
    onclose,
    children,
  }: {
    ariaLabel: string;
    error: string | null;
    form: TwoPageParentForm;
    locked?: boolean;
    closeLabel: string;
    onchooseform: (next: TwoPageParentForm) => void;
    onclose: () => void;
    children: Snippet;
  } = $props();
</script>

<section class="space-y-3" aria-label={ariaLabel}>
  {#if error}<p role="alert" class="text-sm text-red-700">{error}</p>{/if}
  <div class="flex flex-wrap gap-2">
    <label class="inline-flex items-center gap-2 rounded border px-2 py-1 text-sm">
      <input
        type="checkbox"
        data-extended-shrubs
        checked={form === 'FS882-8x6XL-CHARS'}
        disabled={locked}
        onchange={(event) => onchooseform(event.currentTarget.checked ? 'FS882-8x6XL-CHARS' : 'FS882-8x6XL')}
      />
      Show extended shrub layers
    </label>
    <button type="button" disabled={locked} onclick={onclose}>{closeLabel}</button>
  </div>
  {@render children()}
</section>
