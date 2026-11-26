<script lang="ts">
  import {
    BookOpen,
    ChartColumn,
    ChevronDown,
    ClipboardList,
    Compass,
    FileText,
    FolderKanban,
    Globe,
    HelpCircle,
    History,
    Info,
    KeyRound,
    Keyboard,
    Leaf,
    Link,
    Network,
    Newspaper,
    Palette,
    RotateCcw,
    SlidersHorizontal,
    Table,
    TableProperties,
    Tag,
    Tent,
  } from '@lucide/svelte';
  import { webShellRuntime } from '../shared/state';
  import { IS_WEB_READONLY } from '../web/runtimeMode';

  type View =
    | 'home'
    | 'plots'
    | 'geospatial-map'
    | 'diagnostic-synthesis'
    | 'r-sidecar'
    | 'quarto-unit-report'
    | 'hierarchy'
    | 'fs882'
    | 'fs882-twopage'
    | 'datasheet'
    | 'classification-explorer'
    | 'project-admin'
    | 'lump-editor'
    | 'interchange-hub'
    | 'long-environment'
    | 'summary-environment'
    | 'long-vegetation'
    | 'summary-vegetation'
    | 'lifeform-summary'
    | 'subzone-matrix'
    | 'table-csv'
    | 'user-log'
    | 'plot-locations'
    | 'google-earth-review'
    | 'picture-manager'
    | 'plot-label-preview';
  type HelpMenuAction = 'guide' | 'tours' | 'shortcuts' | 'whats-new' | 'reset-sample' | 'about';
  type Item = {
    name: string;
    icon: typeof ClipboardList;
    view?: View;
    action?: 'sivi' | 'new-sivi' | 'metadata' | 'cloud-sync' | 'auth-signin' | 'user-setup';
    helpAction?: HelpMenuAction;
    deferredPhase2?: boolean;
  };
  type Menu = { label: string; icon: typeof ClipboardList; groups: { label: string; items: Item[] }[] };

  let {
    view,
    onnavigate,
    activeEntryForm = 'fs882',
    siviAvailable = false,
    onopensivi,
    newSiviAvailable = false,
    onopennewsivi,
    metadataAvailable = false,
    onopenmetadata,
    onopencloudsync,
    onopenauthsignin,
    onopenusersetup,
    onhelpaction,
    whatsNewUnreadCount = 0,
    resetSampleAvailable = true,
    releaseChannel = 'stable',
    picturesAvailable = true,
  }: {
    view: View;
    onnavigate: (view: View) => void;
    activeEntryForm?: 'fs882' | 'sivi' | 'fs882-twopage';
    siviAvailable?: boolean;
    onopensivi?: () => void;
    newSiviAvailable?: boolean;
    onopennewsivi?: () => void;
    metadataAvailable?: boolean;
    onopenmetadata?: () => void;
    onopencloudsync?: () => void;
    onopenauthsignin?: () => void;
    onopenusersetup?: () => void;
    onhelpaction?: (action: HelpMenuAction) => void;
    whatsNewUnreadCount?: number;
    resetSampleAvailable?: boolean;
    releaseChannel?: string;
    picturesAvailable?: boolean;
  } = $props();

  let navigation: HTMLElement;
  let openMenu = $state<string | null>(null);

  const showDeferredPhase2 = $derived(releaseChannel === 'experimental');

  const rawMenus: Menu[] = $derived([
    {
      label: 'Forms',
      icon: ClipboardList,
      groups: [
        {
          label: 'Data Entry',
          items: [
            { name: 'FS882 Classic Form', icon: ClipboardList, view: 'fs882' },
            { name: 'Universal Datasheet Grid', icon: TableProperties, view: 'datasheet' },
            { name: 'View/Edit SIVI Data', icon: Tent, action: 'sivi' },
            { name: 'New SIVI Plot', icon: Tent, action: 'new-sivi' },
          ],
        },
        {
          label: 'Others',
          items: [
            { name: 'Project Metadata', icon: Table, action: 'metadata' },
            { name: 'Plot Pictures', icon: FileText, view: 'picture-manager' },
            ...(showDeferredPhase2
              ? [
                  { name: 'Herbarium (Planned)', icon: Leaf, deferredPhase2: true },
                  { name: 'Colour-theme (Planned)', icon: Palette, deferredPhase2: true },
                ]
              : []),
          ],
        },
      ],
    },
    {
      label: 'Reports',
      icon: ChartColumn,
      groups: [
        {
          label: 'Vegetation',
          items: [
            { name: 'Summary Vegetation', icon: ChartColumn, view: 'summary-vegetation' },
            { name: 'Long Vegetation', icon: TableProperties, view: 'long-vegetation' },
            { name: 'Lifeform & Species Attributes', icon: Leaf, view: 'lifeform-summary' },
          ],
        },
        {
          label: 'Environment',
          items: [
            { name: 'Long Environment', icon: TableProperties, view: 'long-environment' },
            { name: 'Summary Environment', icon: ChartColumn, view: 'summary-environment' },
          ],
        },
        {
          label: 'Unit Reports',
          items: [{ name: 'Quarto Unit Report', icon: BookOpen, view: 'quarto-unit-report' }],
        },
        {
          label: 'Others',
          items: [
            { name: 'Subzone Matrix of Units', icon: Table, view: 'subzone-matrix' },
            { name: 'Hierarchy Table', icon: Network, view: 'hierarchy' },
            { name: 'Plot Label PDF', icon: Tag, view: 'plot-label-preview' },
            { name: 'Plot Locations', icon: FileText, view: 'plot-locations' },
            { name: 'Google Earth KML', icon: Globe, view: 'google-earth-review' },
            ...(showDeferredPhase2
              ? [{ name: 'Hierarchy Diagram (Planned)', icon: Network, deferredPhase2: true }]
              : []),
          ],
        },
      ],
    },
    {
      label: 'Analysis',
      icon: SlidersHorizontal,
      groups: [
        {
          label: 'BEC & Multivariate Analysis',
          items: [
            { name: 'BEC Diagnostic & Pairwise Synthesis', icon: ChartColumn, view: 'diagnostic-synthesis' },
            { name: 'R Climate, aSMR & Multivariate Clustering', icon: Network, view: 'r-sidecar' },
          ],
        },
      ],
    },
    {
      label: 'Project Management',
      icon: FolderKanban,
      groups: [
        {
          label: 'Project & Classification',
          items: [
            { name: 'Project Lifecycle, QA & Merge', icon: ClipboardList, view: 'project-admin' },
            { name: 'Cloud BECMaster Sync', icon: Globe, action: 'cloud-sync' },
            { name: 'SU & Hierarchy Explorer', icon: Network, view: 'classification-explorer' },
            { name: 'Combine Species', icon: Link, view: 'lump-editor' },
          ],
        },
        {
          label: 'Access & Audit',
          items: [
            { name: 'Sign In & Access', icon: KeyRound, action: 'auth-signin' },
            { name: 'User Log', icon: History, view: 'user-log' },
          ],
        },
      ],
    },
    {
      label: 'Interchange',
      icon: Table,
      groups: [
        {
          label: 'Import & Export',
          items: [
            { name: 'Export to VPro64 & Interchange Hub', icon: Globe, view: 'interchange-hub' },
            { name: 'Project Table CSV Archive', icon: Table, view: 'table-csv' },
          ],
        },
      ],
    },
    {
      label: 'Help',
      icon: HelpCircle,
      groups: [
        {
          label: 'Documentation & Onboarding',
          items: [
            { name: 'F1 LMH25 Guide', icon: BookOpen, helpAction: 'guide' },
            { name: 'Tours', icon: Compass, helpAction: 'tours' },
            { name: 'Shortcuts', icon: Keyboard, helpAction: 'shortcuts' },
          ],
        },
        {
          label: 'Release & Workspace',
          items: [
            { name: "What's New", icon: Newspaper, helpAction: 'whats-new' },
            { name: 'Reset to Sample', icon: RotateCcw, helpAction: 'reset-sample' },
            { name: 'About', icon: Info, helpAction: 'about' },
          ],
        },
      ],
    },
  ]);

  const menus: Menu[] = $derived(
    IS_WEB_READONLY ? ($webShellRuntime ? $webShellRuntime.filterMenus(rawMenus, true, picturesAvailable) : []) : rawMenus
  );

  const menusBeforeMap = $derived(
    menus.filter((m) => m.label !== 'Interchange' && m.label !== 'Downloads' && m.label !== 'Help')
  );
  const menusAfterMap = $derived(
    menus.filter((m) => m.label === 'Interchange' || m.label === 'Downloads' || m.label === 'Help')
  );

  function closeMenu(restoreFocus = false) {
    if (restoreFocus && openMenu) {
      navigation.querySelector<HTMLDetailsElement>('details[open]')?.querySelector('summary')?.focus();
    }
    openMenu = null;
  }

  function dismissOutside(event: Event) {
    if (event.target instanceof Node && !navigation?.contains(event.target)) closeMenu();
  }

  function dismissOnFocus(event: FocusEvent) {
    const disclosure = navigation?.querySelector('details[open]');
    if (disclosure && event.target instanceof Node && !disclosure.contains(event.target)) closeMenu();
  }

  function escape(event: KeyboardEvent) {
    if (event.key === 'Escape' && openMenu) {
      event.preventDefault();
      closeMenu(true);
    }
  }

  function navigate(next: View) {
    closeMenu(true);
    onnavigate(next);
  }

  function itemEnabled(item: Item) {
    if (item.action === 'sivi') return siviAvailable && !!onopensivi;
    if (item.action === 'new-sivi') return newSiviAvailable && !!onopennewsivi;
    if (item.action === 'metadata') return metadataAvailable && !!onopenmetadata;
    if (item.action === 'cloud-sync') return true;
    if (item.action === 'auth-signin') return true;
    if (item.action === 'user-setup') return true;
    if (item.helpAction === 'reset-sample') return resetSampleAvailable;
    if (item.helpAction) return true;
    return !!item.view;
  }

  function activate(item: Item) {
    if (!itemEnabled(item)) return;
    if (item.action === 'sivi' && onopensivi) {
      closeMenu(true);
      onopensivi();
    } else if (item.action === 'new-sivi' && onopennewsivi) {
      closeMenu(true);
      onopennewsivi();
    } else if (item.action === 'metadata' && onopenmetadata) {
      closeMenu(true);
      onopenmetadata();
    } else if (item.action === 'cloud-sync') {
      if (typeof onopencloudsync === 'function') {
        closeMenu(true);
        onopencloudsync();
      } else {
        navigate('project-admin');
      }
    } else if (item.action === 'auth-signin') {
      closeMenu(true);
      if (typeof onopenauthsignin === 'function') {
        onopenauthsignin();
      }
    } else if (item.action === 'user-setup') {
      closeMenu(true);
      if (typeof onopenusersetup === 'function') {
        onopenusersetup();
      }
    } else if (item.helpAction) {
      closeMenu(true);
      if (typeof onhelpaction === 'function') onhelpaction(item.helpAction);
    } else if (item.view) {
      navigate(item.view);
    }
  }

  function isItemCurrent(item: Item): boolean {
    if (item.view === 'fs882') return view === 'fs882' && activeEntryForm !== 'sivi';
    return item.view === view;
  }
</script>

<svelte:window onpointerdown={dismissOutside} onfocusin={dismissOnFocus} onkeydowncapture={escape} />

{#snippet navMenuBlock(menu: Menu)}
  <details class="nav-menu" data-nav-group={menu.label} open={openMenu === menu.label}>
    <summary
      class:current={menu.groups.some((group) => group.items.some((item) => isItemCurrent(item)))}
      onclick={(event) => {
        event.preventDefault();
        openMenu = openMenu === menu.label ? null : menu.label;
      }}
    >
      <menu.icon size={16} aria-hidden="true" />
      {menu.label}
      {#if menu.label === 'Help' && whatsNewUnreadCount > 0}
        <span
          class="rounded bg-vpro-gold px-1.5 py-0.5 font-mono text-[10px] font-bold text-vpro-navy"
          data-nav-whats-new-badge>{whatsNewUnreadCount}</span
        >
      {/if}
      <ChevronDown size={14} aria-hidden="true" />
    </summary>
    <div class="nav-menu-content">
      {#each menu.groups as group (group.label)}
        <section
          data-nav-group={group.label === 'Project & Classification' ? 'Project' : group.label}
          aria-labelledby={`nav-${menu.label}-${group.label.replaceAll(' ', '-')}`}
        >
          <h2 class="nav-group-label" id={`nav-${menu.label}-${group.label.replaceAll(' ', '-')}`}>{group.label}</h2>
          {#each group.items as item (item.name)}
            <button
              disabled={!itemEnabled(item)}
              class:current={isItemCurrent(item)}
              data-help-menu-item={item.helpAction}
              data-nav-item={item.view ?? item.action ?? item.helpAction}
              aria-current={isItemCurrent(item) ? 'page' : undefined}
              title={item.action === 'sivi'
                ? itemEnabled(item)
                  ? IS_WEB_READONLY
                    ? 'View SIVI / FS1333 record for the selected plot.'
                    : 'SIVI / FS1333 editor for the selected plot. Existing draft and close guards apply.'
                  : IS_WEB_READONLY
                    ? 'Select a plot to view SIVI / FS1333 data.'
                    : 'Select a plot to open SIVI / FS1333 data entry.'
                : item.action === 'metadata'
                  ? itemEnabled(item)
                    ? IS_WEB_READONLY
                      ? 'View project metadata for the active dataset.'
                      : 'Project metadata for the active project (requires a clean, unlocked editor when a plot is open).'
                    : IS_WEB_READONLY
                      ? 'Open a dataset to view project metadata.'
                      : 'Finish or Undo drafts in a clean, unlocked editor before opening Project Metadata.'
                  : item.helpAction === 'reset-sample'
                    ? 'Safe recovery: restores a fresh copy of the Sample project and switches your session without deleting your own projects.'
                    : item.deferredPhase2
                      ? 'Planned for a future release'
                      : item.name}
              onclick={() => activate(item)}
            >
              <item.icon size={16} aria-hidden="true" />
              {#if item.action === 'sivi' && !itemEnabled(item)}
                <span class="nav-item-hint">Select plot</span>
              {:else if item.action === 'metadata' && !itemEnabled(item)}
                <span class="nav-item-hint">Open clean plot</span>
              {/if}
              <span
                >{item.name}{item.helpAction === 'whats-new' && whatsNewUnreadCount > 0
                  ? ` (${whatsNewUnreadCount} new)`
                  : ''}</span
              >
            </button>
          {/each}
        </section>
      {/each}
    </div>
  </details>
{/snippet}

<nav bind:this={navigation} class="main-nav" aria-label="Main navigation">
  {#each menusBeforeMap as menu (menu.label)}
    {@render navMenuBlock(menu)}
  {/each}
  <button
    data-nav-top="Map"
    class:current={view === 'geospatial-map'}
    aria-current={view === 'geospatial-map' ? 'page' : undefined}
    onclick={() => navigate('geospatial-map')}
  >
    <Globe size={16} aria-hidden="true" />Map
  </button>
  {#each menusAfterMap as menu (menu.label)}
    {@render navMenuBlock(menu)}
  {/each}
</nav>
