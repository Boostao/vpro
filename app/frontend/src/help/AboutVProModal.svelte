<script lang="ts">
  import { untrack } from 'svelte';
  import { CheckCircle2, Copy, FileCheck2, ShieldCheck, X } from '@lucide/svelte';
  import ModalDialogTrap from '../shared/ModalDialogTrap.svelte';
  import { formatError } from '../shared/readRequests';
  import {
    defaultHelpPort,
    formatShortCommit,
    type AboutInfo,
    type HelpBackendPort,
    type HelpDataUseAgreement,
  } from './helpSystem';

  let {
    open = false,
    helpPort = defaultHelpPort,
    onclose,
  }: {
    open?: boolean;
    helpPort?: HelpBackendPort;
    onclose: () => void;
  } = $props();

  let about = $state.raw<AboutInfo | null>(null);
  let agreement = $state.raw<HelpDataUseAgreement | null>(null);
  let loading = $state(false);
  let error = $state('');
  let copiedDigest = $state('');
  let loadGen = 0;

  $effect(() => {
    if (!open) return;
    untrack(() => {
      void loadAboutAndAgreement();
    });
  });

  async function loadAboutAndAgreement() {
    const gen = ++loadGen;
    loading = true;
    error = '';
    try {
      const [aboutRes, bundleRes] = await Promise.all([helpPort.getAboutInfo(), helpPort.getHelpBundle()]);
      if (gen !== loadGen) return;
      about = aboutRes;
      agreement = bundleRes.dataUseAgreement ?? null;
    } catch (cause) {
      if (gen === loadGen) {
        error = `About & provenance metadata failed to load: ${formatError(cause)}`;
      }
    } finally {
      if (gen === loadGen) {
        loading = false;
      }
    }
  }

  async function copyDigest(sha: string) {
    try {
      if (typeof navigator !== 'undefined' && navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(sha);
      }
      copiedDigest = sha;
    } catch {
      copiedDigest = '';
    }
  }
</script>

{#if open}
  <div class="fixed inset-0 z-50 flex items-center justify-center bg-vpro-ink/50 p-4" data-about-vpro-modal>
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="about-vpro-modal-title"
      class="flex max-h-[88vh] w-full max-w-2xl flex-col overflow-hidden rounded border border-vpro-border bg-white text-vpro-ink shadow-2xl"
    >
      <ModalDialogTrap onEscape={onclose} initialFocusSelector="[data-about-vpro-close]" />
      <header
        class="flex items-center justify-between gap-3 border-b-[3px] border-b-vpro-gold bg-vpro-navy px-5 py-3.5 text-white"
      >
        <div class="flex items-center gap-2.5">
          <ShieldCheck size={18} class="text-vpro-gold" />
          <div>
            <div class="font-mono text-[11px] uppercase tracking-wider text-vpro-gold">
              Institutional Identity &amp; Standards Provenance
            </div>
            <h2 id="about-vpro-modal-title" class="text-base font-semibold text-white">
              About VPro &amp; 2026 Master Standards Libraries
            </h2>
          </div>
        </div>
        <button
          type="button"
          aria-label="Close About VPro"
          data-about-vpro-close
          class="rounded border border-white/30 bg-white/10 p-1.5 text-white hover:bg-white/20"
          onclick={onclose}
        >
          <X size={16} />
        </button>
      </header>

      <div class="space-y-4 overflow-y-auto p-5 text-xs">
        {#if error}
          <p role="alert" class="rounded border border-vpro-error bg-red-50 p-2.5 text-vpro-error">{error}</p>
        {/if}

        {#if loading && !about}
          <p role="status" class="text-vpro-ink-secondary">Loading standards provenance stamps...</p>
        {:else if about}
          <section class="rounded border border-vpro-border border-l-[4px] border-l-vpro-navy bg-vpro-canvas p-3.5">
            <div class="flex flex-wrap items-baseline justify-between gap-2">
              <h3 class="text-base font-bold text-vpro-navy">{about.productName}</h3>
              <div class="flex flex-wrap items-center gap-2 font-mono text-[11px]">
                <span class="rounded bg-vpro-navy px-2 py-0.5 font-semibold text-white">v{about.appVersion}</span>
                {#if about.buildMode === 'dev'}
                  <span
                    data-about-build-tier="dev"
                    class="rounded border border-vpro-gold bg-vpro-navy px-2 py-0.5 font-semibold uppercase text-vpro-gold"
                  >
                    DEV BUILD{about.gitCommit ? ` · ${formatShortCommit(about.gitCommit)}` : ''}
                  </span>
                {:else if about.buildMode === 'alpha'}
                  <span
                    data-about-build-tier="alpha"
                    class="rounded border border-vpro-navy bg-vpro-gold px-2 py-0.5 font-semibold uppercase text-vpro-navy"
                  >
                    ALPHA PREVIEW
                  </span>
                {/if}
                <span class="rounded border border-vpro-border bg-white px-2 py-0.5 font-semibold text-vpro-navy">
                  Schema {about.schemaVersion}
                </span>
                {#if about.buildMode === 'dev' || about.releaseChannel === 'experimental'}
                  <span
                    class="rounded border border-vpro-border bg-white px-2 py-0.5 uppercase text-vpro-ink-secondary"
                  >
                    Channel: {about.releaseChannel}
                  </span>
                {/if}
              </div>
            </div>
            <div class="mt-1 text-xs font-semibold text-vpro-ink">{about.fullName}</div>
            <div class="mt-0.5 text-xs text-vpro-ink-secondary">{about.organization}</div>
          </section>

          {#if about.buildMode === 'alpha'}
            <section
              data-about-alpha-callout
              class="space-y-1.5 rounded border border-vpro-navy border-l-[4px] border-l-vpro-gold bg-vpro-warning-bg p-3 text-xs text-vpro-ink"
            >
              <div class="font-bold text-vpro-navy">Alpha Preview — Client Evaluation Build (v{about.appVersion})</div>
              <p class="leading-relaxed">
                This preview build is provided for B.C. Ministry of Forests BEC Program evaluation and domain
                verification. Keep backup copies of archival project files before running bulk imports or merges, and
                report classification or workflow issues via
                <a
                  href="https://github.com/Boostao/vpro/issues"
                  target="_blank"
                  rel="noreferrer"
                  class="font-semibold text-vpro-info underline">github.com/Boostao/vpro/issues</a
                >.
              </p>
            </section>
          {/if}

          {#if about.unsignedNotice && about.buildMode !== 'dev'}
            <section
              data-about-unsigned-notice
              class="rounded border border-vpro-border bg-vpro-canvas p-3 text-[11px] leading-relaxed text-vpro-ink"
            >
              <strong class="font-semibold text-vpro-navy">Preview Package Integrity (SHA-256 Verified):</strong>
              Preview desktop installers and portable archives are unsigned. Verify downloaded files against the published
              <code class="font-mono text-vpro-navy">SHA256SUMS.txt</code> checksums on the release portal.
            </section>
          {/if}

          {#if about.buildMode === 'dev'}
            <section
              data-about-dev-diagnostics
              aria-label="Developer Build Diagnostics"
              class="space-y-1 rounded border border-vpro-border bg-vpro-surface-subtle p-3 font-mono text-[11px] text-vpro-ink-secondary"
            >
              <div class="font-sans text-xs font-bold uppercase tracking-wide text-vpro-navy">
                Developer Diagnostics (Local Dev Build Only)
              </div>
              <div>
                Build Mode: {about.buildMode} · Commit: {about.gitCommit || 'local'}{about.buildDate
                  ? ` · Built: ${about.buildDate}`
                  : ''}
              </div>
              <div>Runtime Channel: {about.releaseChannel}</div>
              {#if about.configPath}<div class="break-all">Config YAML: {about.configPath}</div>{/if}
              {#if about.dataDir}<div class="break-all">Workspace Data Folder: {about.dataDir}</div>{/if}
            </section>
          {/if}

          <section class="space-y-2.5" aria-label="2026 Provincial Standards SHA-256 Stamps">
            <h4 class="flex items-center gap-1.5 text-xs font-bold uppercase tracking-wide text-vpro-navy">
              <FileCheck2 size={14} /> Embedded 2026 Master Standards (SHA-256 Verified)
            </h4>

            <div class="grid grid-cols-1 gap-2.5">
              <div class="rounded border border-vpro-border bg-white p-3">
                <div class="flex items-center justify-between gap-2">
                  <span class="font-semibold text-vpro-navy">BECdb Master Classification</span>
                  <span
                    class="rounded bg-vpro-success-bg px-2 py-0.5 font-mono text-[11px] font-semibold text-vpro-success"
                  >
                    {about.libraryStamps.becVersion}
                  </span>
                </div>
                <div class="mt-1.5 space-y-1 font-mono text-[11px] text-vpro-ink-secondary">
                  <div class="break-all">Archive SHA-256: {about.libraryStamps.becArchiveSha256}</div>
                  <div class="break-all">ACCDB SHA-256: {about.libraryStamps.becExtractedSha256}</div>
                </div>
              </div>

              <div class="rounded border border-vpro-border bg-white p-3">
                <div class="flex items-center justify-between gap-2">
                  <span class="font-semibold text-vpro-navy">B.C. Master Plant Taxonomy</span>
                  <span
                    class="rounded bg-vpro-success-bg px-2 py-0.5 font-mono text-[11px] font-semibold text-vpro-success"
                  >
                    {about.libraryStamps.taxonomyVersion}
                  </span>
                </div>
                <div class="mt-1.5 space-y-1 font-mono text-[11px] text-vpro-ink-secondary">
                  <div class="break-all">Archive SHA-256: {about.libraryStamps.taxonomyArchiveSha256}</div>
                  <div class="break-all">ACCDB SHA-256: {about.libraryStamps.taxonomyExtractedSha256}</div>
                </div>
              </div>

              <div class="rounded border border-vpro-border bg-white p-3">
                <div class="flex items-center justify-between gap-2">
                  <span class="font-semibold text-vpro-navy">Field Manual Specification</span>
                  <span
                    class="rounded bg-vpro-success-bg px-2 py-0.5 font-mono text-[11px] font-semibold text-vpro-success"
                  >
                    {about.libraryStamps.lmh25Edition}
                  </span>
                </div>
                <div class="mt-1.5 break-all font-mono text-[11px] text-vpro-ink-secondary">
                  PDF SHA-256: {about.libraryStamps.lmh25Pdf2023Sha256}
                </div>
              </div>
            </div>
          </section>

          <details class="rounded border border-vpro-border bg-white p-3">
            <summary class="cursor-pointer text-xs font-bold text-vpro-navy">
              Built-in Reference Databases ({about.libraryStamps.artifacts.length})
            </summary>
            <div class="mt-2 overflow-x-auto">
              <table class="w-full min-w-0 border-collapse text-[11px]">
                <thead>
                  <tr class="bg-vpro-canvas text-left font-semibold text-vpro-navy">
                    <th class="border-b border-vpro-border px-2 py-1.5">Artifact</th>
                    <th class="border-b border-vpro-border px-2 py-1.5">Row Counts</th>
                    <th class="border-b border-vpro-border px-2 py-1.5">SHA-256</th>
                  </tr>
                </thead>
                <tbody>
                  {#each about.libraryStamps.artifacts as art (art.path)}
                    <tr class="border-b border-vpro-rail last:border-b-0">
                      <td class="whitespace-nowrap px-2 py-1.5 font-mono text-vpro-navy">{art.path}</td>
                      <td class="whitespace-normal px-2 py-1.5 font-mono text-vpro-ink-secondary">
                        {Object.entries(art.counts)
                          .map(([k, v]) => `${k}: ${v}`)
                          .join(', ')}
                      </td>
                      <td class="whitespace-nowrap px-2 py-1.5 font-mono text-vpro-ink-secondary">
                        <button
                          type="button"
                          class="inline-flex items-center gap-1 rounded border border-vpro-border px-1.5 py-0.5 hover:bg-vpro-canvas"
                          title={art.sha256}
                          onclick={() => void copyDigest(art.sha256)}
                        >
                          {#if copiedDigest === art.sha256}
                            <CheckCircle2 size={11} class="text-vpro-success" /> Copied
                          {:else}
                            <Copy size={11} /> {art.sha256.slice(0, 12)}…
                          {/if}
                        </button>
                      </td>
                    </tr>
                  {/each}
                </tbody>
              </table>
            </div>
          </details>

          {#if agreement}
            <details class="rounded border border-vpro-border bg-vpro-canvas p-3" data-bec-data-use-agreement>
              <summary class="cursor-pointer text-xs font-bold text-vpro-navy">
                {agreement.title} ({agreement.clauses.length} Clauses &amp; Official Citation)
              </summary>
              <div class="mt-2.5 space-y-2.5 border-t border-vpro-border pt-2.5 text-xs">
                <div class="rounded border border-vpro-border bg-white p-2.5">
                  <div class="text-[10px] font-bold uppercase text-vpro-ink-muted">Recommended Citation</div>
                  <p class="mt-1 font-mono text-[11px] text-vpro-ink">{agreement.citation}</p>
                </div>
                <ol class="space-y-1.5 text-[11px] leading-relaxed text-vpro-ink">
                  {#each agreement.clauses as clause}
                    <li class="rounded bg-white p-2">{clause}</li>
                  {/each}
                </ol>
              </div>
            </details>
          {/if}
        {/if}
      </div>
    </div>
  </div>
{/if}
