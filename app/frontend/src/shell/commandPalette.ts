export type CommandPaletteCategory = 'plots' | 'context' | 'views' | 'help';

export interface CommandPalettePlotCandidate {
  plotNumber: string;
  siteUnit?: string | null;
  zone?: string | null;
  subZone?: string | null;
  location?: string | null;
}

export interface CommandPaletteProjectCandidate {
  name: string;
  path?: string;
  file?: string;
  version?: string;
  compatible?: boolean;
  active?: boolean;
}

export interface CommandPaletteSUCandidate {
  index: number;
  name: string;
  path?: string;
  kind?: string;
  compatible?: boolean;
  active?: boolean;
}

export interface CommandPaletteHelpCandidate {
  id: string;
  title: string;
  subtitle: string;
  keywords?: string;
}

export type CommandPaletteAction =
  | { kind: 'open-plot-fs882'; plotNumber: string }
  | { kind: 'open-plot-twopage'; plotNumber: string }
  | { kind: 'open-plot-sivi'; plotNumber: string }
  | { kind: 'switch-project'; projectIndex: number; name: string }
  | { kind: 'switch-su'; suIndex: number; name: string }
  | { kind: 'navigate-view'; view: string }
  | { kind: 'new-sivi' }
  | { kind: 'open-metadata' }
  | { kind: 'help-topic'; topicId: string; tab?: 'inspector' | 'keys' | 'guides' }
  | { kind: 'help-action'; action: 'guide' | 'tours' | 'shortcuts' | 'whats-new' | 'reset-sample' | 'about' };

export interface CommandPaletteItem {
  id: string;
  category: CommandPaletteCategory;
  categoryLabel: string;
  title: string;
  subtitle: string;
  badge?: string;
  shortcut?: string;
  disabled?: boolean;
  disabledReason?: string;
  searchText: string;
  action: CommandPaletteAction;
}

export interface BuildCommandPaletteInput {
  plots?: readonly CommandPalettePlotCandidate[];
  projects?: readonly CommandPaletteProjectCandidate[];
  sus?: readonly CommandPaletteSUCandidate[];
  selectedPlotNumber?: string | null;
  activeSU?: string | null;
  metadataAvailable?: boolean;
  siviAvailable?: boolean;
  newSiviAvailable?: boolean;
  helpTopics?: readonly CommandPaletteHelpCandidate[];
}

const DEFAULT_HELP_TOPICS: readonly CommandPaletteHelpCandidate[] = [
  { id: 'site.plot_number', title: 'LMH25 SITE 1 — Plot Number & Identity', subtitle: 'Field manual rules & 7-character plot identifier rules', keywords: 'plot number identity f1 site' },
  { id: 'site.moisture_regime', title: 'LMH25 Key 9.3 / 9.4 — Relative Soil Moisture Regime (rSMR)', subtitle: 'Upland & wetland moisture key (0 Very Xeric to 8 Hydric)', keywords: 'rsmr moisture regime edatopic key' },
  { id: 'site.nutrient_regime', title: 'LMH25 Key 9.6 — Soil Nutrient Regime (rSNR)', subtitle: 'Nutrient key (A Very Poor to F Saline)', keywords: 'rsnr nutrient regime edatopic key' },
  { id: 'humus.upper_lower_depth', title: 'LMH25 SOIL — Humus & Mineral Horizon Depth Signs', subtitle: 'Upland L/F/H upward (Upper > Lower) vs. mineral/peat downward', keywords: 'humus mineral horizon depth sign lfh' },
  { id: 'veg.covers', title: 'LMH25 VEG — Strata & Species % Cover Visual Chart', subtitle: 'Tree A, Shrub B, Herb C, Moss D & cover bounds under 100%', keywords: 'vegetation cover strata shrub chars' },
  { id: 'sivi.plot_type', title: 'FS1333 SIVI — Site Visit Ground Inspection & Visual Calls', subtitle: 'TEM/SIBEC PlotType G / V / N / O conventions', keywords: 'sivi fs1333 site visit tem sibec' },
];

export function buildCommandPaletteCatalog(input: BuildCommandPaletteInput): CommandPaletteItem[] {
  const items: CommandPaletteItem[] = [];

  for (const plot of input.plots ?? []) {
    const plotNo = String(plot.plotNumber ?? '').trim();
    if (!plotNo) continue;
    const bec = [plot.zone, plot.subZone].filter(Boolean).join('');
    const metaParts = [
      plot.siteUnit ? `SU ${plot.siteUnit}` : null,
      bec ? `BGC ${bec}` : null,
      plot.location || null,
    ].filter(Boolean);
    const metaSubtitle = metaParts.length > 0 ? metaParts.join(' · ') : 'Active context plot';
    const baseSearch = `${plotNo} ${plot.siteUnit ?? ''} ${bec} ${plot.location ?? ''}`.toLowerCase();

    items.push({
      id: `plot-fs882-${plotNo}`,
      category: 'plots',
      categoryLabel: 'Plots in Active Context',
      title: `Plot ${plotNo} — Open in FS882 (6×4)`,
      subtitle: metaSubtitle,
      badge: 'FS882',
      searchText: `${baseSearch} fs882 6x4 open plot card`,
      action: { kind: 'open-plot-fs882', plotNumber: plotNo },
    });
    items.push({
      id: `plot-2page-${plotNo}`,
      category: 'plots',
      categoryLabel: 'Plots in Active Context',
      title: `Plot ${plotNo} — Open in FS882 Two-Page`,
      subtitle: metaSubtitle,
      badge: '2-Page',
      searchText: `${baseSearch} two page 2-page 8x6 open plot`,
      action: { kind: 'open-plot-twopage', plotNumber: plotNo },
    });
    items.push({
      id: `plot-sivi-${plotNo}`,
      category: 'plots',
      categoryLabel: 'Plots in Active Context',
      title: `Plot ${plotNo} — Open in SIVI / FS1333`,
      subtitle: metaSubtitle,
      badge: 'SIVI',
      searchText: `${baseSearch} sivi fs1333 site visit open plot`,
      action: { kind: 'open-plot-sivi', plotNumber: plotNo },
    });
  }

  for (const [index, proj] of (input.projects ?? []).entries()) {
    items.push({
      id: `project-${index}-${proj.name}`,
      category: 'context',
      categoryLabel: 'Projects & Site Units (SUs)',
      title: `Project: ${proj.name}`,
      subtitle: proj.active ? `Active project · ${proj.file ?? proj.path ?? ''}` : `Switch active project · ${proj.file ?? proj.path ?? ''}`,
      badge: proj.active ? 'Active' : (proj.version ?? 'VP08'),
      disabled: proj.compatible === false,
      disabledReason: proj.compatible === false ? 'Incompatible project schema' : undefined,
      searchText: `project switch ${proj.name} ${proj.file ?? ''} ${proj.path ?? ''}`.toLowerCase(),
      action: { kind: 'switch-project', projectIndex: index, name: proj.name },
    });
  }

  items.push({
    id: 'su-none',
    category: 'context',
    categoryLabel: 'Projects & Site Units (SUs)',
    title: 'Site Unit Filter: None (All Project Plots)',
    subtitle: !input.activeSU || input.activeSU === 'None' ? 'Currently showing all plots in project' : 'Clear active Site Unit filter',
    badge: !input.activeSU || input.activeSU === 'None' ? 'Active' : 'SU',
    searchText: 'site unit su none clear filter all plots',
    action: { kind: 'switch-su', suIndex: -1, name: 'None' },
  });

  for (const su of input.sus ?? []) {
    items.push({
      id: `su-${su.index}-${su.name}`,
      category: 'context',
      categoryLabel: 'Projects & Site Units (SUs)',
      title: `Site Unit Table: ${su.name}`,
      subtitle: su.active ? 'Active Site Unit filter' : `Activate ${su.name} Site Unit table`,
      badge: su.active ? 'Active' : (su.kind === 'master' ? 'Master SU' : 'SU'),
      disabled: su.compatible === false,
      disabledReason: su.compatible === false ? 'Incompatible SU table' : undefined,
      searchText: `site unit su table ${su.name} ${su.path ?? ''}`.toLowerCase(),
      action: { kind: 'switch-su', suIndex: su.index, name: su.name },
    });
  }

  const views: Array<{
    id: string;
    title: string;
    subtitle: string;
    badge: string;
    shortcut?: string;
    keywords: string;
    action: CommandPaletteAction;
    disabled?: boolean;
    disabledReason?: string;
  }> = [
    { id: 'view-home', title: 'Workspace Home & Readiness Overview', subtitle: 'Session summary, active libraries & quick entry', badge: 'View', keywords: 'home dashboard overview', action: { kind: 'navigate-view', view: 'home' } },
    { id: 'view-plots', title: 'Plot Register & Scoped Plot Lookup', subtitle: 'Browse, filter, and open plots in active context', badge: 'Plots', keywords: 'plots list table lookup register', action: { kind: 'navigate-view', view: 'plots' } },
    { id: 'view-fs882', title: 'FS882 Ecosystem Field Form (6×4)', subtitle: 'Site, Soil/Terrain, Vegetation, Veg Other & Audit editor', badge: 'Form', keywords: 'fs882 6x4 form entry site soil veg', action: { kind: 'navigate-view', view: 'fs882' } },
    { id: 'action-new-sivi', title: 'New SIVI / FS1333 Plot', subtitle: 'Create a new Site Visit plot in active project', badge: 'Form', keywords: 'new create sivi fs1333 plot', action: { kind: 'new-sivi' }, disabled: input.newSiviAvailable === false, disabledReason: 'Finish current busy workflow first' },
    { id: 'view-datasheet', title: 'Universal Datasheet Grid', subtitle: 'Direct spreadsheet editing across Env, Veg, Humus, Mineral & SU', badge: 'Grid', keywords: 'datasheet spreadsheet table grid bulk edit', action: { kind: 'navigate-view', view: 'datasheet' } },
    { id: 'view-map', title: '3D Map (BGC, Coordinate Check & Site Units)', subtitle: 'Provincial BGC v13 overlay, coordinate check & polygon AOI -> SU', badge: 'GIS', keywords: 'map 3d geospatial gis bgc pmtiles aoi coordinates', action: { kind: 'navigate-view', view: 'geospatial-map' } },
    { id: 'view-synthesis', title: 'BEC Diagnostic & Pairwise Synthesis', subtitle: 'Differential species matrix, Sorensen similarity, outliers & edatopic grid', badge: 'BEC', keywords: 'diagnostic synthesis differential edatopic matrix similarity', action: { kind: 'navigate-view', view: 'diagnostic-synthesis' } },
    { id: 'view-rsidecar', title: 'R Companion: Climate, Clustering & Quarto Guides', subtitle: 'Clustering, downscaled climate normals & publication HTML guides', badge: 'R / Quarto', keywords: 'r sidecar climr asmr quarto guide clustering', action: { kind: 'navigate-view', view: 'r-sidecar' } },
    { id: 'view-classification', title: 'SU & Hierarchy Classification Explorer', subtitle: 'Dual-pane Site Unit assignment & flat hierarchy tree', badge: 'SU', keywords: 'classification explorer su hierarchy tree', action: { kind: 'navigate-view', view: 'classification-explorer' } },
    { id: 'view-project-admin', title: 'Project Admin, Compliance QA, Splinter & Merge', subtitle: 'Create, Save As, Splinter, Compare, Merge & LMH25 batch QA', badge: 'Admin', keywords: 'project admin new save as splinter merge compare qa', action: { kind: 'navigate-view', view: 'project-admin' } },
    { id: 'view-lump', title: 'Combine Species (Lump Table Editor)', subtitle: 'Non-destructive query/report taxonomic species lumping', badge: 'Taxonomy', keywords: 'combine species lump taxonomy synonym', action: { kind: 'navigate-view', view: 'lump-editor' } },
    { id: 'view-interchange', title: 'Interchange Hub (VENUS 5, TurboVeg, RDS, GeoPackage)', subtitle: 'External ecological & GIS format import/export', badge: 'Export', keywords: 'interchange import export venus turboveg rds geopackage gpkg csv', action: { kind: 'navigate-view', view: 'interchange-hub' } },
    { id: 'view-summary-veg', title: 'Summary Vegetation Report (.xlsx)', subtitle: 'Constancy, prominence & grouped phytosociological workbooks', badge: 'Report', keywords: 'summary vegetation report xlsx excel constancy', action: { kind: 'navigate-view', view: 'summary-vegetation' } },
    { id: 'view-long-veg', title: 'Long Vegetation Report (.xlsx)', subtitle: 'Full plot-by-species layer/strata/lifeform workbooks', badge: 'Report', keywords: 'long vegetation report xlsx excel', action: { kind: 'navigate-view', view: 'long-vegetation' } },
    { id: 'view-lifeform', title: 'Lifeform & Species Attribute Summary (.xlsx)', subtitle: 'Lifeform breakdown & provincial species attributes', badge: 'Report', keywords: 'lifeform summary species attributes report', action: { kind: 'navigate-view', view: 'lifeform-summary' } },
    { id: 'view-long-env', title: 'Long Environment Report (.xlsx)', subtitle: 'Plot-level site, soil & terrain workbooks', badge: 'Report', keywords: 'long environment report xlsx site soil', action: { kind: 'navigate-view', view: 'long-environment' } },
    { id: 'view-summary-env', title: 'Summary Environment Report (.xlsx)', subtitle: 'Site Unit quantitative IQR & qualitative frequency summaries', badge: 'Report', keywords: 'summary environment site unit report xlsx', action: { kind: 'navigate-view', view: 'summary-environment' } },
    { id: 'view-subzone-matrix', title: 'Subzone Matrix of Units (.xlsx)', subtitle: 'Cross-subzone unit comparison matrix', badge: 'Report', keywords: 'subzone matrix units report xlsx', action: { kind: 'navigate-view', view: 'subzone-matrix' } },
    { id: 'view-plot-labels', title: 'Saved Plot Label Preview & PDF', subtitle: 'Calibrated herbarium & field plot labels', badge: 'PDF', keywords: 'plot label pdf print preview', action: { kind: 'navigate-view', view: 'plot-label-preview' } },
    { id: 'view-plot-locations', title: 'Plot Location & Coordinate Review', subtitle: 'NAD83 geodetic & UTM coordinate verification', badge: 'QA', keywords: 'plot location review coordinates utm lat lon', action: { kind: 'navigate-view', view: 'plot-locations' } },
    { id: 'view-google-earth', title: 'Google Earth KML Location Preparation', subtitle: 'Secondary KML 2.1 export preparation', badge: 'KML', keywords: 'google earth kml export locations', action: { kind: 'navigate-view', view: 'google-earth-review' } },
    { id: 'view-table-csv', title: 'Project Table CSV Archive Review', subtitle: 'Deterministic 8-table VP08 CSV bundle export', badge: 'CSV', keywords: 'table csv archive zip export', action: { kind: 'navigate-view', view: 'table-csv' } },
    { id: 'view-pictures', title: 'Plot Picture Manager', subtitle: 'Inspect and manage linked VPics plot photographs', badge: 'Photos', keywords: 'pictures photos vpics manager', action: { kind: 'navigate-view', view: 'picture-manager' } },
    { id: 'view-hierarchy', title: 'Hierarchy Table View', subtitle: 'Inspect active flat classification hierarchy nodes', badge: 'Hierarchy', keywords: 'hierarchy table nodes units', action: { kind: 'navigate-view', view: 'hierarchy' } },
    { id: 'view-user-log', title: 'User Activity Log Review', subtitle: 'Paginated audit review of USysUserLog', badge: 'Audit', keywords: 'user log audit history', action: { kind: 'navigate-view', view: 'user-log' } },
    { id: 'action-metadata', title: 'Project Metadata Editor', subtitle: 'Edit <Project>_Metadata for the open clean plot', badge: 'Metadata', keywords: 'project metadata editor standards', action: { kind: 'open-metadata' }, disabled: !input.metadataAvailable, disabledReason: 'Requires clean, unlocked open plot in FS882' },
  ];

  for (const v of views) {
    items.push({
      id: v.id,
      category: 'views',
      categoryLabel: 'Views, Forms, Reports & Tools',
      title: v.title,
      subtitle: v.subtitle,
      badge: v.badge,
      shortcut: v.shortcut,
      disabled: v.disabled,
      disabledReason: v.disabledReason,
      searchText: `${v.title} ${v.subtitle} ${v.keywords}`.toLowerCase(),
      action: v.action,
    });
  }

  const helpActions: Array<{
    id: string;
    title: string;
    subtitle: string;
    shortcut?: string;
    keywords: string;
    action: CommandPaletteAction;
  }> = [
    { id: 'help-guide', title: 'Open LMH25 (2023) Contextual Reference Drawer', subtitle: 'Offline field definitions, code lists & rSMR/rSNR keys', shortcut: 'F1', keywords: 'help f1 lmh25 manual reference drawer', action: { kind: 'help-action', action: 'guide' } },
    { id: 'help-tours', title: 'Interactive Guided Walkthroughs (4 Tours)', subtitle: '90-second spotlight tours for migrating VPro 64 ecologists', keywords: 'tours walkthroughs onboarding tutorial vpro 64', action: { kind: 'help-action', action: 'tours' } },
    { id: 'help-shortcuts', title: 'Keyboard Shortcuts Cheat-Sheet', subtitle: 'Enter/Tab grid navigation, View Field Card, F1 & Ctrl+K', shortcut: '?', keywords: 'keyboard shortcuts hotkeys accelerators', action: { kind: 'help-action', action: 'shortcuts' } },
    { id: 'help-whats-new', title: "What's New & Release Changelog", subtitle: 'Version highlights & bundled BECdb/Taxonomy updates', keywords: 'whats new release notes changelog', action: { kind: 'help-action', action: 'whats-new' } },
    { id: 'help-reset-sample', title: 'Reset Workspace to Sample Project', subtitle: 'Safe non-destructive Sample workspace recovery', keywords: 'reset sample recovery restore', action: { kind: 'help-action', action: 'reset-sample' } },
    { id: 'help-about', title: 'About VPro & 2026 Master Standards Provenance', subtitle: 'Build stamps, BECdb v13, BCPlantTaxonomy v19 & Data Use Agreement', keywords: 'about vpro version standards sha256 license', action: { kind: 'help-action', action: 'about' } },
  ];

  for (const h of helpActions) {
    items.push({
      id: h.id,
      category: 'help',
      categoryLabel: 'LMH25 Help, Shortcuts & Tours',
      title: h.title,
      subtitle: h.subtitle,
      badge: 'Help',
      shortcut: h.shortcut,
      searchText: `${h.title} ${h.subtitle} ${h.keywords}`.toLowerCase(),
      action: h.action,
    });
  }

  for (const topic of input.helpTopics ?? DEFAULT_HELP_TOPICS) {
    items.push({
      id: `topic-${topic.id}`,
      category: 'help',
      categoryLabel: 'LMH25 Help, Shortcuts & Tours',
      title: topic.title,
      subtitle: topic.subtitle,
      badge: 'LMH25',
      searchText: `${topic.id} ${topic.title} ${topic.subtitle} ${topic.keywords ?? ''}`.toLowerCase(),
      action: { kind: 'help-topic', topicId: topic.id, tab: topic.id.includes('regime') ? 'keys' : 'inspector' },
    });
  }

  return items;
}

export function scoreCommandItem(item: CommandPaletteItem, rawQuery: string): number {
  const q = rawQuery.trim().toLowerCase();
  if (!q) {
    if (item.category === 'views') return 50;
    if (item.category === 'plots') return item.badge === 'FS882' ? 45 : 20;
    if (item.category === 'context') return 35;
    return 30;
  }

  const tokens = q.split(/\s+/).filter(Boolean);
  const titleLower = item.title.toLowerCase();
  const hay = item.searchText;
  let score = 0;

  for (const tok of tokens) {
    if (
      item.action.kind.startsWith('open-plot-') &&
      'plotNumber' in item.action &&
      item.action.plotNumber.toLowerCase() === tok
    ) {
      score += item.badge === 'FS882' ? 240 : 210;
      continue;
    }
    if (
      item.action.kind.startsWith('open-plot-') &&
      'plotNumber' in item.action &&
      item.action.plotNumber.toLowerCase().startsWith(tok)
    ) {
      score += item.badge === 'FS882' ? 140 : 120;
      continue;
    }
    if (titleLower.startsWith(tok)) {
      score += 90;
    } else if (titleLower.includes(tok)) {
      score += 60;
    } else if (hay.includes(tok)) {
      score += 35;
    } else {
      // Subsequence fuzzy fallback (e.g. "sumveg" -> "Summary Vegetation")
      let qi = 0;
      for (let i = 0; i < titleLower.length && qi < tok.length; i++) {
        if (titleLower[i] === tok[qi]) qi++;
      }
      if (qi === tok.length && tok.length >= 2) {
        score += 18;
      } else {
        return 0;
      }
    }
  }

  if (item.disabled) score -= 5;
  return Math.max(1, score);
}

export function searchCommandPalette(
  catalog: readonly CommandPaletteItem[],
  query: string,
  limit = 28,
): CommandPaletteItem[] {
  const trimmed = query.trim();
  if (!trimmed) {
    // Curated default quick-jump view: first 6 plots (FS882) + top views + active context + help
    const plots = catalog.filter((i) => i.category === 'plots' && i.badge === 'FS882').slice(0, 6);
    const views = catalog.filter((i) => i.category === 'views' && !i.disabled).slice(0, 10);
    const ctx = catalog.filter((i) => i.category === 'context' && !i.disabled).slice(0, 5);
    const help = catalog.filter((i) => i.category === 'help').slice(0, 4);
    return [...plots, ...views, ...ctx, ...help].slice(0, limit);
  }

  const scored: Array<{ item: CommandPaletteItem; score: number }> = [];
  for (const item of catalog) {
    const score = scoreCommandItem(item, trimmed);
    if (score > 0) scored.push({ item, score });
  }
  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, limit).map((entry) => entry.item);
}
