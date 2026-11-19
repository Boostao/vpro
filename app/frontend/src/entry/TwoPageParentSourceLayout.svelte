<script lang="ts">
  import type { Snippet } from 'svelte';
  import TwoPageEntryLayout from './TwoPageEntryLayout.svelte';
  import type { TwoPageEntryChild } from './twoPageEntryProjection';
  import type { PaperControl } from './paperLayout';
  import type { TwoPageParentForm } from './twoPageParentSession';

  let {
    form,
    plot,
    scope,
    scopeLabel,
    values,
    editor,
    childContent,
  }: {
    form: TwoPageParentForm;
    plot: string;
    scope: 'common' | 'extra';
    scopeLabel: string;
    values: Map<string, string | null>;
    editor: { columns: readonly string[]; input: Snippet<[PaperControl, string]>; labelled: true };
    childContent?: Snippet<[TwoPageEntryChild, PaperControl]>;
  } = $props();
</script>

<p class="text-sm">{scopeLabel} fields are editable in this source layout. Other parent fields and linked records
  remain read-only during this review; finish and close this scope before editing another.</p>
<TwoPageEntryLayout {form} {values} editors={[{ ...editor, scope }]}>
  {#snippet identity(field)}
    <label class="form-field"><span class="field-label">Plot number</span>
      <input data-column={field.column} value={plot} readonly aria-label="Plot number"
        title="Existing plot identities cannot be renamed here" />
    </label>
  {/snippet}
  {#snippet embedded(child, control)}
    {#if childContent}{@render childContent(child, control)}
    {:else}<p>{child.form}: linked records are unavailable in this review.</p>{/if}
  {/snippet}
</TwoPageEntryLayout>
