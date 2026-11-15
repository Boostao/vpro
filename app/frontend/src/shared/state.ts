import { writable } from 'svelte/store';
import type { ProjectState } from '../../bindings/github.com/boostao/vpro/app';

export const projectState = writable<ProjectState | null>(null);