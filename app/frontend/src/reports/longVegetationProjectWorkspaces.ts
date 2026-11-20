import { VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
import { ReadRequests } from '../shared/readRequests';
import {
  createProjectReportWorkspaceRegistry,
  type ProjectWorkspacePort,
} from './longVegetationProjectWorkspace.svelte';
import type { ProjectReportOwner } from './longVegetationProjectReport';

const capabilities = Object.freeze({
  enabled: true,
  workbook: true,
  lifeform: true,
  strata: true,
  code: true,
  selectedField: true,
});

function ownedPorts(owner: ProjectReportOwner): ProjectWorkspacePort {
  const scopeReads = new ReadRequests(),
    unitReads = new ReadRequests(),
    reportReads = new ReadRequests();
  const context = owner.contextId;
  const nonnull = <T>(value: T | null, operation: string): T => {
    if (value === null) throw new Error(`No owned project ${operation} acknowledgement returned.`);
    return value;
  };
  return {
    scope: {
      scope: async () =>
        nonnull(await scopeReads.track(VegetationReportService.GetLongVegetationReportScope(context)), 'scope'),
      catalogue: async () =>
        nonnull(
          await scopeReads.track(VegetationReportService.GetLongVegetationProjectFieldDefinitions(context)),
          'field catalogue'
        ),
      switchScope: async (request) =>
        nonnull(await VegetationReportService.SetLongVegetationReportScope(context, request), 'scope switch'),
      fields: async (request) =>
        nonnull(await VegetationReportService.SetLongVegetationProjectFields(context, request), 'field draft'),
      build: async (revision) =>
        nonnull(await VegetationReportService.BuildLongVegetationProjectScope(context, revision), 'Build'),
    },
    options: (request) => reportReads.track(VegetationReportService.GetLongVegetationProjectOptions(context, request)),
    preview: (request) => reportReads.track(VegetationReportService.PreviewLongVegetationProject(context, request)),
    unitPreferences: (request) =>
      unitReads.track(VegetationReportService.GetLongVegetationProjectUnitPreferences(context, request)),
    saveUnits: (request) => VegetationReportService.SaveLongVegetationProjectUnits(context, request),
    workbookReview: (request) =>
      reportReads.track(VegetationReportService.GetLongVegetationProjectWorkbookReview(context, request)),
    publishWorkbook: (request) => VegetationReportService.ExportReviewedLongVegetationProjectWorkbook(context, request),
    cancelScopeReads: () => scopeReads.cancelAll(),
    cancelUnitReads: () => unitReads.cancelAll(),
    cancelReportReads: () => reportReads.cancelAll(),
  };
}

export const projectReportWorkspace = createProjectReportWorkspaceRegistry(ownedPorts, capabilities);
