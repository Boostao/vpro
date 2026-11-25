import type { Component } from 'svelte';
import { writable } from 'svelte/store';
import type { ProjectState } from '../../bindings/github.com/boostao/vpro/app';
import type { filterNavigationMenusForMode } from '../shell/webReadOnlyShell';
import type { WebMetaResponse, WebUrlContextInput, WebUrlResolutionPlan, WebUrlState } from '../web/webMeta';

export interface WebShellRuntimeBundle {
  filterMenus: typeof filterNavigationMenusForMode;
  isViewAllowed: (view: string, picturesAvailable?: boolean) => boolean;
  hubOverrides: Readonly<Record<string, { title: string; subtitle: string; description: string; cta: string }>>;
  planInitialUrl: (search: string, state: WebUrlContextInput, picturesAvailable: boolean) => WebUrlResolutionPlan;
  syncUrl: (state: WebUrlState) => string;
  ProvenanceBadge: Component<{ variant: 'header' | 'sidebar' | 'home'; activeProject?: string; plotCount?: number }>;
}

export const projectState = writable<ProjectState | null>(null);
export const webMeta = writable<WebMetaResponse | null>(null);
export const webShellRuntime = writable<WebShellRuntimeBundle | null>(null);
