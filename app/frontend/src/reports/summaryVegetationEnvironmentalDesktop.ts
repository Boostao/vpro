import { VegetationReportService } from '../../bindings/github.com/boostao/vpro/app';
import { summaryEnvironmentalLifeformRegistry, type SummaryEnvironmentalPort } from './summaryVegetationEnvironmental';

const ALWAYS_ON = Boolean(1);
export const summaryEnvironmentalEnabled = ALWAYS_ON;
export const summaryEnvironmentalNumericEnabled = ALWAYS_ON;
export const summaryEnvironmentalLifeformEnabled = ALWAYS_ON;
export const summaryEnvironmentalDesktop = summaryEnvironmentalLifeformRegistry(true);
export const summaryEnvironmentalPort: SummaryEnvironmentalPort = {
  preview: (contextId) => VegetationReportService.PreviewSummaryVegetationEnvironmentalLifeform(contextId, 1, 6, 0),
  validationYield: () => new Promise<void>((resolve) => setTimeout(resolve, 0)),
};
