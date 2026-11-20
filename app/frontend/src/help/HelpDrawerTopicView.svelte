<script lang="ts">
  import { FileText } from '@lucide/svelte';
  import type { HelpBundle, HelpGuide, HelpLookupResult } from './helpSystem';

  let {
    groupedFields,
    selectedFieldId,
    lookup,
    onloadtopic,
    onopenkey,
    onopenguide,
  }: {
    groupedFields: Array<[string, HelpBundle['fields']]>;
    selectedFieldId: string;
    lookup: HelpLookupResult | null;
    onloadtopic: (helpId: string) => void;
    onopenkey: (keyId: string) => void;
    onopenguide: (guide: HelpGuide) => void;
  } = $props();
</script>

<div class="space-y-3">
  <div>
    <label
      for="help-field-selector"
      class="block text-[11px] font-semibold uppercase tracking-wide text-vpro-ink-secondary"
    >
      Jump to LMH25 (2023) Field Specification
    </label>
    <select
      id="help-field-selector"
      class="mt-1 w-full rounded border border-vpro-border bg-white px-2.5 py-1.5 text-xs text-vpro-ink"
      value={selectedFieldId}
      onchange={(e) => onloadtopic(e.currentTarget.value)}
    >
      {#each groupedFields as [sectionName, fields] (sectionName)}
        <optgroup label={sectionName}>
          {#each fields as f (f.id)}
            <option value={f.id}>{f.code} — {f.title}</option>
          {/each}
        </optgroup>
      {/each}
    </select>
  </div>

  {#if lookup?.field}
    {@const field = lookup.field}
    <article
      class="space-y-3 rounded border border-vpro-border border-t-[3px] border-t-vpro-navy bg-white p-3.5"
      data-help-active-field={field.id}
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <span class="rounded bg-vpro-navy px-2 py-0.5 font-mono text-[11px] font-semibold text-white">
          {field.code}
        </span>
        <span
          class="rounded border border-vpro-border bg-vpro-canvas px-2 py-0.5 font-mono text-[11px] font-medium text-vpro-ink"
        >
          LMH25 (2023) p. {field.lmh25Page}
        </span>
      </div>

      <div>
        <div class="text-[11px] font-medium text-vpro-ink-muted">{field.section}</div>
        <h3 class="mt-0.5 text-sm font-bold text-vpro-navy">{field.title}</h3>
      </div>

      <dl class="grid grid-cols-1 gap-2 rounded bg-vpro-canvas p-2.5 sm:grid-cols-2">
        <div>
          <dt class="text-[10px] font-semibold uppercase text-vpro-ink-muted">VPro Column(s)</dt>
          <dd class="mt-0.5 font-mono text-[11px] font-medium text-vpro-ink">{field.column}</dd>
        </div>
        <div>
          <dt class="text-[10px] font-semibold uppercase text-vpro-ink-muted">Domain &amp; Units</dt>
          <dd class="mt-0.5 text-[11px] font-medium text-vpro-ink">{field.unit}</dd>
        </div>
      </dl>

      <p class="text-xs text-vpro-ink">{field.summary}</p>

      {#if field.rules.length > 0}
        <section aria-label="Calibration and directional rules" class="space-y-1.5">
          <h4 class="text-[11px] font-bold uppercase tracking-wide text-vpro-navy">
            LMH25 &amp; VPro Calibration Rules
          </h4>
          <ul class="list-disc space-y-1 pl-4 text-xs text-vpro-ink">
            {#each field.rules as rule}
              <li>{rule}</li>
            {/each}
          </ul>
        </section>
      {/if}

      {#if lookup.decisionKey}
        {@const dk = lookup.decisionKey}
        <div class="rounded border border-vpro-gold bg-amber-50/50 p-2.5">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div>
              <div class="font-mono text-[11px] font-semibold text-vpro-navy">{dk.code}</div>
              <div class="text-xs font-medium text-vpro-ink">{dk.title}</div>
            </div>
            <button
              type="button"
              data-help-open-linked-key={dk.id}
              class="rounded bg-vpro-navy px-2.5 py-1.5 text-xs font-semibold text-white hover:bg-vpro-navy-dark"
              onclick={() => onopenkey(dk.id)}
            >
              Open Interactive Key
            </button>
          </div>
        </div>
      {/if}

      {#if field.codes.length > 0}
        <section aria-label="Valid picklist codes" class="space-y-1.5">
          <h4 class="text-[11px] font-bold uppercase tracking-wide text-vpro-navy">
            Standard Picklist Codes (USysTableOfLists)
          </h4>
          <div class="overflow-x-auto rounded border border-vpro-border">
            <table class="w-full min-w-0 border-collapse text-xs">
              <thead>
                <tr class="bg-vpro-canvas text-left text-[11px] font-semibold text-vpro-navy">
                  <th class="border-b border-vpro-border px-2.5 py-1.5">Code</th>
                  <th class="border-b border-vpro-border px-2.5 py-1.5">LMH25 Definition</th>
                </tr>
              </thead>
              <tbody>
                {#each field.codes as opt (opt.code)}
                  <tr class="border-b border-vpro-rail last:border-b-0">
                    <td class="whitespace-nowrap px-2.5 py-1.5 font-mono font-semibold text-vpro-navy">{opt.code}</td>
                    <td class="whitespace-normal px-2.5 py-1.5 text-vpro-ink">{opt.label}</td>
                  </tr>
                {/each}
              </tbody>
            </table>
          </div>
        </section>
      {/if}

      {#if lookup.relatedGuides.length > 0}
        <section aria-label="Related guides" class="space-y-1.5 border-t border-vpro-border pt-2.5">
          <h4 class="text-[11px] font-bold uppercase tracking-wide text-vpro-ink-secondary">Related Workflow Guides</h4>
          <div class="flex flex-wrap gap-1.5">
            {#each lookup.relatedGuides as guide (guide.id)}
              <button
                type="button"
                class="inline-flex items-center gap-1 rounded border border-vpro-border bg-vpro-canvas px-2.5 py-1 text-[11px] font-medium text-vpro-navy hover:bg-vpro-rail"
                onclick={() => onopenguide(guide)}
              >
                <FileText size={12} />
                {guide.title}
              </button>
            {/each}
          </div>
        </section>
      {/if}
    </article>
  {/if}
</div>
