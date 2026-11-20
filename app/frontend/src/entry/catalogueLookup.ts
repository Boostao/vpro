import { QualityLookup, type PlotQualityChoice, type QualityView } from './qualityEditor';
import { ReadRequests } from '../shared/readRequests';
import {
  getCachedGlobalCatalogue,
  invalidateGlobalCatalogue,
  peekGlobalCatalogue,
} from './entryReferenceCache';

export class CatalogueLookup extends QualityLookup {
  constructor(
    fetch: (force: boolean, requests: ReadRequests) => Promise<PlotQualityChoice[]>,
    state: (view: QualityView) => void,
    label: string,
    cacheKey?: string
  ) {
    const requests = new ReadRequests();
    super(
      (force) =>
        cacheKey
          ? getCachedGlobalCatalogue(cacheKey, () => fetch(force, requests), force)
          : fetch(force, requests),
      state,
      label,
      cacheKey ? undefined : () => requests.cancelAll(),
      cacheKey
        ? {
            peek: () => peekGlobalCatalogue<PlotQualityChoice>(cacheKey),
            invalidate: () => {
              requests.cancelAll();
              invalidateGlobalCatalogue(cacheKey);
            },
          }
        : undefined
    );
  }
}
