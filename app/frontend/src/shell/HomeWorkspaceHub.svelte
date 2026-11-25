<script lang="ts">
  import {
    ArrowRight,
    BookOpen,
    ChartColumn,
    ClipboardList,
    Compass,
    Database,
    Globe,
    Network,
    ShieldCheck,
    TableProperties,
  } from '@lucide/svelte';
  import { formatShortCommit, type BuildMode } from '../help/helpSystem';
  import { webShellRuntime } from '../shared/state';
  import { IS_WEB_READONLY } from '../web/runtimeMode';

  type HubView =
    | 'plots'
    | 'fs882'
    | 'datasheet'
    | 'classification-explorer'
    | 'geospatial-map'
    | 'diagnostic-synthesis'
    | 'r-sidecar'
    | 'interchange-hub'
    | 'project-admin';

  let {
    activeProject = 'None',
    projectPath = '',
    activeSU = 'None',
    activeHierarchy = 'None',
    plotCount = 0,
    buildMode = '' as BuildMode,
    appVersion = '',
    gitCommit = '',
    releaseChannel = 'stable',
    onnavigate,
    onhelpaction,
  }: {
    activeProject?: string;
    projectPath?: string;
    activeSU?: string;
    activeHierarchy?: string;
    plotCount?: number;
    buildMode?: BuildMode;
    appVersion?: string;
    gitCommit?: string;
    releaseChannel?: string;
    onnavigate: (view: HubView) => void;
    onhelpaction?: (action: 'guide' | 'tours' | 'about') => void;
  } = $props();

  const shortCommit = $derived(formatShortCommit(gitCommit));

  const baseWorkflows: {
    id: string;
    title: string;
    subtitle: string;
    description: string;
    icon: typeof ClipboardList;
    cta: string;
    view?: HubView;
    helpAction?: 'guide' | 'tours';
  }[] = [
    {
      id: 'entry',
      title: 'Plots & FS882 / SIVI Entry',
      subtitle: 'LMH25 (2023) Field Cards',
      description:
        'Browse project plots and edit FS882 (6x4), 2-Page, and FS1333 SIVI records with inline CHARS extended-shrub layers and live pedon/rSMR/rSNR rules.',
      icon: ClipboardList,
      cta: 'Open Plots',
      view: 'plots',
    },
    {
      id: 'datasheet',
      title: 'Universal Datasheet Grid',
      subtitle: 'Multi-Plot Tabular Editing',
      description:
        'Filter, sort, and batch-edit Environment and Vegetation columns across scoped plots with automatic audit history.',
      icon: TableProperties,
      cta: 'Open Datasheet',
      view: 'datasheet',
    },
    {
      id: 'classification',
      title: 'SU & Hierarchy Explorer',
      subtitle: 'BEC Classification Hypothesis',
      description:
        'Organize working Site Unit assignments, manage tilde (~) hierarchy breakpoints, and refine candidate units.',
      icon: Network,
      cta: 'Open Explorer',
      view: 'classification-explorer',
    },
    {
      id: 'spatial',
      title: '3D Geospatial Workbench',
      subtitle: 'Offline 3D Map & Coordinate Check',
      description:
        'Inspect plot coordinates over BGC v13, Ecosections, and Natural Resource Districts with spatial attribute verification and AOI filtering.',
      icon: Globe,
      cta: 'Open 3D Map',
      view: 'geospatial-map',
    },
    {
      id: 'synthesis',
      title: 'BEC Diagnostic Synthesis',
      subtitle: 'Presence, Fidelity & R Companion',
      description:
        'Compute Presence (I–V), Domin-Krajina Significance, and differential species classes (d, dd, cd, c, ic) alongside climr aSMR & Quarto guides.',
      icon: ChartColumn,
      cta: 'Open Diagnostics',
      view: 'diagnostic-synthesis',
    },
    {
      id: 'interchange',
      title: 'Interchange Hub & Admin',
      subtitle: 'Access, VENUS 5, TurboVeg 3, GeoPackage',
      description:
        'Promote Access (.accdb/.mdb) projects, run 3-way merges & QA checks, and exchange VENUS 5.0 XML, TurboVeg 3 databases/XML, .gpkg, and R .rds archives.',
      icon: Database,
      cta: 'Open Interchange Hub',
      view: 'interchange-hub',
    },
  ];

  const workflows = $derived(
    IS_WEB_READONLY && $webShellRuntime?.hubOverrides
      ? baseWorkflows.map((item) => {
          const ov = $webShellRuntime?.hubOverrides[item.id];
          return ov ? { ...item, ...ov } : item;
        })
      : baseWorkflows
  );
</script>

<div class="space-y-4" data-home-workspace-hub>
  {#if !IS_WEB_READONLY && buildMode === 'alpha'}
    <section
      data-home-tier-banner="alpha"
      aria-label="Alpha Preview Evaluation Notice"
      class="rounded border border-vpro-navy border-l-[4px] border-l-vpro-gold bg-vpro-warning-bg p-3.5 text-xs text-vpro-ink"
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <div class="flex items-center gap-2 font-bold text-vpro-navy">
          <ShieldCheck size={16} class="text-vpro-navy" aria-hidden="true" />
          <span
            >VPro Alpha Preview{appVersion ? ` (v${appVersion})` : ''} — B.C. Ministry of Forests BEC Evaluation</span
          >
        </div>
        <a
          href="https://github.com/Boostao/vpro/issues"
          target="_blank"
          rel="noreferrer"
          class="rounded border border-vpro-navy bg-white px-2.5 py-1 font-semibold text-vpro-info hover:bg-vpro-navy-tint"
        >
          Report Feedback / Issue
        </a>
      </div>
      <p class="mt-1.5 leading-relaxed text-vpro-ink">
        Keep backup copies of archival databases before running bulk Access imports or multi-project merges. Preview
        packages are unsigned — verify installer checksums against <code class="font-mono text-vpro-navy"
          >SHA256SUMS.txt</code
        >.
      </p>
    </section>
  {:else if buildMode === 'dev'}
    <section
      data-home-tier-banner="dev"
      aria-label="Local Developer Build Notice"
      class="flex flex-wrap items-center justify-between gap-2 rounded border border-vpro-border border-l-[4px] border-l-vpro-navy bg-vpro-surface-subtle px-3.5 py-2 font-mono text-[11px] text-vpro-ink-secondary"
    >
      <span>
        DEV BUILD · v{appVersion || '2.0.0-dev'}{shortCommit ? ` · ${shortCommit}` : ''} · channel={releaseChannel}
      </span>
      {#if onhelpaction}
        <button
          type="button"
          class="rounded border border-vpro-border bg-white px-2 py-0.5 font-sans text-[11px] font-semibold text-vpro-navy hover:bg-vpro-canvas"
          onclick={() => onhelpaction('about')}
        >
          Inspect Build &amp; Paths
        </button>
      {/if}
    </section>
  {/if}

  <section
    data-home-context-card
    aria-label="Active BEC Session Context"
    class="rounded border border-vpro-border border-t-[3px] border-t-vpro-navy bg-white p-4 shadow-xs"
  >
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <div class="font-mono text-[11px] font-semibold uppercase tracking-wider text-vpro-navy">
          {IS_WEB_READONLY ? 'Active Read-Only BEC Dataset' : 'Active BEC Workspace Context'}
        </div>
        <h2 class="mt-0.5 text-lg font-bold text-vpro-ink">
          {activeProject || (IS_WEB_READONLY ? 'No dataset selected' : 'No project selected')}
        </h2>
        {#if projectPath && !IS_WEB_READONLY}
          <div class="mt-0.5 break-all font-mono text-[11px] text-vpro-ink-muted">{projectPath}</div>
        {/if}
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <button
          type="button"
          data-home-open-plots
          class="inline-flex items-center gap-1.5 rounded bg-vpro-navy px-3.5 py-1.5 text-xs font-semibold text-white hover:bg-vpro-navy-dark"
          onclick={() => onnavigate('plots')}
        >
          <span>View Plots ({plotCount})</span>
          <ArrowRight size={14} aria-hidden="true" />
        </button>
        <button
          type="button"
          data-home-open-fs882
          class="inline-flex items-center gap-1.5 rounded border border-vpro-navy bg-white px-3 py-1.5 text-xs font-semibold text-vpro-navy hover:bg-vpro-surface-subtle"
          onclick={() => onnavigate('fs882')}
        >
          <span>{IS_WEB_READONLY ? 'FS882 Viewer' : 'FS882 Editor'}</span>
        </button>
      </div>
    </div>

    <dl class="mt-3.5 grid grid-cols-2 gap-2.5 border-t border-vpro-border pt-3 text-xs sm:grid-cols-4">
      <div class="rounded bg-vpro-canvas px-2.5 py-2">
        <dt class="font-mono text-[10px] uppercase text-vpro-ink-secondary">Plots in Scope</dt>
        <dd class="mt-0.5 text-sm font-bold text-vpro-navy">{plotCount}</dd>
      </div>
      <div class="rounded bg-vpro-canvas px-2.5 py-2">
        <dt class="font-mono text-[10px] uppercase text-vpro-ink-secondary">Site Unit</dt>
        <dd class="mt-0.5 truncate font-semibold text-vpro-ink" title={activeSU}>{activeSU || 'None'}</dd>
      </div>
      <div class="rounded bg-vpro-canvas px-2.5 py-2">
        <dt class="font-mono text-[10px] uppercase text-vpro-ink-secondary">Hierarchy</dt>
        <dd class="mt-0.5 truncate font-semibold text-vpro-ink" title={activeHierarchy}>{activeHierarchy || 'None'}</dd>
      </div>
      <div class="rounded bg-vpro-canvas px-2.5 py-2">
        <dt class="font-mono text-[10px] uppercase text-vpro-ink-secondary">2026 Master Standards</dt>
        <dd class="mt-0.5 font-mono text-[11px] font-semibold text-vpro-success">BECdb v13 · Taxa v19 · LMH25</dd>
      </div>
    </dl>
  </section>

  <section aria-label="Core BEC Workflows" data-home-workflow-grid>
    <div class="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3">
      {#each workflows as item (item.id)}
        <article
          data-home-workflow={item.id}
          class="flex flex-col justify-between rounded border border-vpro-border bg-white p-3.5 transition-colors hover:border-vpro-navy"
        >
          <div>
            <div class="flex items-center gap-2 text-vpro-navy">
              <item.icon size={16} aria-hidden="true" />
              <span class="font-mono text-[10px] font-semibold uppercase tracking-wider text-vpro-ink-secondary">
                {item.subtitle}
              </span>
            </div>
            <h3 class="mt-1 text-sm font-bold text-vpro-navy">{item.title}</h3>
            <p class="mt-1 text-xs leading-relaxed text-vpro-ink">{item.description}</p>
          </div>
          <div class="mt-3 pt-2 border-t border-vpro-rail">
            <button
              type="button"
              class="inline-flex items-center gap-1 text-xs font-semibold text-vpro-navy hover:underline"
              onclick={() => {
                if (item.view) onnavigate(item.view);
              }}
            >
              <span>{item.cta}</span>
              <ArrowRight size={13} aria-hidden="true" />
            </button>
          </div>
        </article>
      {/each}
    </div>
  </section>

  {#if onhelpaction}
    <section
      data-home-help-bar
      class="flex flex-wrap items-center justify-between gap-2 rounded border border-vpro-border bg-vpro-canvas px-3.5 py-2.5 text-xs text-vpro-ink"
    >
      <div class="flex items-center gap-2">
        <BookOpen size={15} class="text-vpro-navy" aria-hidden="true" />
        <span>
          <strong>Offline Field Manual &amp; Guided Onboarding:</strong> Press
          <kbd class="rounded border border-vpro-border bg-white px-1.5 py-0.5 font-mono text-[11px]">F1</kbd> on any field
          for LMH25 (2023) rules, rSMR/rSNR keys, and visual % cover plates.
        </span>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <button
          type="button"
          class="inline-flex items-center gap-1 rounded border border-vpro-navy bg-white px-2.5 py-1 font-semibold text-vpro-navy hover:bg-vpro-surface-subtle"
          onclick={() => onhelpaction('guide')}
        >
          <BookOpen size={13} aria-hidden="true" />
          <span>LMH25 Reference (F1)</span>
        </button>
        <button
          type="button"
          class="inline-flex items-center gap-1 rounded bg-vpro-navy px-2.5 py-1 font-semibold text-white hover:bg-vpro-navy-dark"
          onclick={() => onhelpaction('tours')}
        >
          <Compass size={13} aria-hidden="true" />
          <span>Guided Tours</span>
        </button>
      </div>
    </section>
  {/if}
</div>
