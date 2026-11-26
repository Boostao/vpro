import { IS_WEB_READONLY } from '../web/runtimeMode';
import type { WebMetaResponse } from '../web/webMeta';

export const WEB_READONLY_BLOCKED_VIEWS: ReadonlySet<string> = new Set(['project-admin', 'user-log']);
export const WEB_READONLY_BLOCKED_ACTIONS: ReadonlySet<string> = new Set([
  'new-sivi',
  'cloud-sync',
  'user-setup',
  'auth-signin',
]);
export const WEB_READONLY_BLOCKED_HELP_ACTIONS: ReadonlySet<string> = new Set(['reset-sample']);

export interface NavMenuItemShape {
  name: string;
  view?: string;
  action?: string;
  helpAction?: string;
  deferredPhase2?: boolean;
  [key: string]: unknown;
}

export interface NavMenuGroupShape<TItem extends NavMenuItemShape = NavMenuItemShape> {
  label: string;
  items: TItem[];
}

export interface NavMenuShape<TItem extends NavMenuItemShape = NavMenuItemShape> {
  label: string;
  groups: NavMenuGroupShape<TItem>[];
  [key: string]: unknown;
}

const WEB_MENU_LABELS: Readonly<Record<string, string>> = {
  Forms: 'Plot Viewers',
  Interchange: 'Downloads',
};

const WEB_GROUP_LABELS: Readonly<Record<string, string>> = {
  'Data Entry': 'Plot Viewers',
  'Project & Classification': 'Classification',
  'Import & Export': 'Export & Downloads',
  'Release & Workspace': 'Release & Info',
};

const WEB_ITEM_LABELS: Readonly<Record<string, string>> = {
  'FS882 Classic Form': 'FS882 Plot Viewer',
  'FS882 Data Forms (6x4)': 'FS882 Plot Viewer (6x4)',
  'Two-Page Entry (FS882-8x6XL)': 'Two-Page Plot Viewer (FS882-8x6XL)',
  'View/Edit SIVI Data': 'View SIVI Data',
  'Enter/Edit SIVI Data': 'View SIVI Data',
  'Export to VPro64 & Interchange Hub': 'Export & Downloads Hub',
  'Interchange Hub (VPro64, TurboVeg, RDS, GeoPackage)': 'Export & Downloads Hub (TurboVeg, CSV, R .rds, GeoPackage)',
  'Combine Species': 'Combine Species (Read-Only)',
};

export function isViewAllowedInWebReadOnly(view: string, picturesAvailable = true): boolean {
  if (WEB_READONLY_BLOCKED_VIEWS.has(view)) return false;
  if (view === 'picture-manager' && !picturesAvailable) return false;
  return true;
}

export function filterNavigationMenusForMode<TItem extends NavMenuItemShape, TMenu extends NavMenuShape<TItem>>(
  menus: readonly TMenu[],
  webReadOnly: boolean = IS_WEB_READONLY,
  picturesAvailable = true
): TMenu[] {
  if (!webReadOnly) {
    return [...menus];
  }
  const filtered: TMenu[] = [];
  for (const menu of menus) {
    const groups: NavMenuGroupShape<TItem>[] = [];
    for (const group of menu.groups) {
      const items: TItem[] = [];
      for (const item of group.items) {
        if (item.deferredPhase2) continue;
        if (item.action && WEB_READONLY_BLOCKED_ACTIONS.has(item.action)) continue;
        if (item.helpAction && WEB_READONLY_BLOCKED_HELP_ACTIONS.has(item.helpAction)) continue;
        if (item.view && !isViewAllowedInWebReadOnly(item.view, picturesAvailable)) continue;
        const renamed = WEB_ITEM_LABELS[item.name] ?? item.name;
        items.push({ ...item, name: renamed });
      }
      if (items.length > 0) {
        groups.push({
          ...group,
          label: WEB_GROUP_LABELS[group.label] ?? group.label,
          items,
        });
      }
    }
    if (groups.length > 0) {
      filtered.push({
        ...menu,
        label: WEB_MENU_LABELS[menu.label] ?? menu.label,
        groups,
      });
    }
  }
  return filtered;
}

export interface SnapshotProvenanceSummary {
  snapshotId: string;
  publishedDate: string;
  plotCount: number;
  redacted: boolean;
  redactedPlotCount: number;
  notice: string;
  standardsLabel: string;
}

export function formatSnapshotProvenance(
  meta: WebMetaResponse | null,
  activeProject?: string,
  fallbackPlotCount = 0
): SnapshotProvenanceSummary {
  const publishedRaw = meta?.publishedAt?.trim() ?? '';
  const publishedDate = publishedRaw ? publishedRaw.slice(0, 10) : '';
  const activeDs = activeProject
    ? meta?.datasets.find((d) => d.project === activeProject || d.id === activeProject)
    : undefined;
  const plotCount = activeDs?.plotCount ?? meta?.totalPlotCount ?? fallbackPlotCount;
  const redacted = meta?.redacted ?? false;
  const redactedPlotCount = activeDs?.redactedPlotCount ?? meta?.redactedPlotCount ?? 0;
  const notice =
    meta?.redactionNotice ||
    (redacted
      ? 'Sensitive species plot coordinates are generalized to 10 km for rare-plant protection.'
      : '');
  const bec = meta?.standards?.becVersion || 'BECdb v13';
  const tax = meta?.standards?.taxonomyVersion || 'BCPlantTaxonomy v19';
  return {
    snapshotId: meta?.snapshotId || 'BECMaster Snapshot',
    publishedDate,
    plotCount,
    redacted,
    redactedPlotCount,
    notice,
    standardsLabel: `${bec} · ${tax}`,
  };
}

export function defaultWebExportFilename(baseName: string, extension: string): string {
  const safeBase =
    String(baseName || 'vpro_export')
      .trim()
      .replace(/[^A-Za-z0-9._-]+/g, '_')
      .replace(/^_+|_+$/g, '') || 'vpro_export';
  const cleanExt = extension.startsWith('.') ? extension : `.${extension}`;
  return safeBase.toLowerCase().endsWith(cleanExt.toLowerCase()) ? safeBase : `${safeBase}${cleanExt}`;
}
