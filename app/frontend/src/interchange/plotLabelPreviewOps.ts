import type {
  ContextService,
  ImportExportService,
  PlotLabelPDFExportOutcome,
  PlotLabelPDFExportReview,
} from '../../bindings/github.com/boostao/vpro/app';
import type { CancellableRead, ReadRequests } from '../shared/readRequests';
import type { PublicationView } from '../shared/publicationSession';
import type { plotLabelFromHeader, PlotLabelPreview } from './plotLabelPreview';
import type { validatePlotLabelRegionalPreview, PlotLabelRegionalEvidence } from './plotLabelRegional';
import type { validatePlotLabelPDFReview } from './plotLabelPDFExport';

export interface PlotLabelToastSink {
  success: (title: string, message: string, opts?: Record<string, unknown>) => void;
  warning: (title: string, message: string, opts?: Record<string, unknown>) => void;
  error: (title: string, message: string, opts?: Record<string, unknown>) => void;
}

export function buildPdfNotificationKey(view: PublicationView<PlotLabelPDFExportOutcome>): string {
  if (view.outcome) {
    return `outcome:${view.requestedDestination}:${view.outcome.status}:${view.outcome.path}:${view.outcome.errorMessage}`;
  }
  if (view.error) {
    return `error:${view.requestedDestination}:${view.error}`;
  }
  return '';
}

export function emitPlotLabelPdfExportToast(
  sink: PlotLabelToastSink,
  view: PublicationView<PlotLabelPDFExportOutcome>,
  plotNumber: string | undefined,
  fallbackDest: string,
  project: string
): void {
  const opts = { category: 'reports' as const, source: 'Plot Labels', contextTag: project || undefined };
  if (view.outcome?.status === 'published') {
    const plotPrefix = plotNumber ? `plot ${plotNumber} ` : '';
    sink.success(
      'Label PDF exported',
      `Exported ${plotPrefix}label PDF to ${view.outcome.path || fallbackDest}.`,
      opts
    );
  } else {
    sink.error(
      'Label PDF export failed',
      view.error || view.outcome?.errorMessage || 'Label PDF export did not complete.',
      opts
    );
  }
}

export function emitPlotLabelPdfRecoveryToast(
  sink: PlotLabelToastSink,
  view: PublicationView<PlotLabelPDFExportOutcome>,
  project: string
): void {
  const opts = { category: 'reports' as const, source: 'Plot Labels', contextTag: project || undefined };
  if (view.outcome?.status === 'published') {
    sink.success('Label PDF receipt recovered', `Verified exported PDF at ${view.outcome.path}.`, opts);
  } else if (view.error) {
    sink.error('Label PDF recovery notice', view.error, opts);
  }
}

export interface PlotLabelLoadResult {
  cancelled?: boolean;
  pdfReview: PlotLabelPDFExportReview | null;
  preview: PlotLabelPreview;
  labelDate: string;
  regionalEvidence: PlotLabelRegionalEvidence | null;
  warningMessage?: string;
}

export async function fetchPlotLabelPreviewBundle(input: {
  reads: ReadRequests;
  owner: { contextId: string; project: string; projectPath: string; su: string; suPath: string };
  requestedPlot: string;
  isCurrent: () => boolean;
  importExportSvc:
    | {
        GetPlotLabelPDFReview?: typeof ImportExportService.GetPlotLabelPDFReview;
        GetPlotLabelRegionalPreview?: typeof ImportExportService.GetPlotLabelRegionalPreview;
      }
    | undefined;
  contextSvc: {
    GetPlot: typeof ContextService.GetPlot;
  };
  validators: {
    validatePlotLabelPDFReview?: typeof validatePlotLabelPDFReview;
    validatePlotLabelRegionalPreview?: typeof validatePlotLabelRegionalPreview;
    plotLabelFromHeader?: typeof plotLabelFromHeader;
    makeDate: () => Date;
  };
}): Promise<PlotLabelLoadResult> {
  const { reads, owner, requestedPlot, isCurrent, importExportSvc, contextSvc, validators } = input;
  const { contextId } = owner;
  const cancelledResult = (): PlotLabelLoadResult => ({
    cancelled: true,
    pdfReview: null,
    preview: {} as PlotLabelPreview,
    labelDate: '',
    regionalEvidence: null,
  });
  const hasPdfReview = typeof importExportSvc?.GetPlotLabelPDFReview === 'function';
  const hasRegionalPreview = typeof importExportSvc?.GetPlotLabelRegionalPreview === 'function';

  if (hasPdfReview && importExportSvc?.GetPlotLabelPDFReview) {
    let value: PlotLabelPDFExportReview | null = null;
    let pdfPrepCause: unknown = null;
    try {
      value = await reads.track(
        importExportSvc.GetPlotLabelPDFReview(contextId, JSON.stringify({ plotNumber: requestedPlot }))
      );
    } catch (pdfCause) {
      const canFallbackRegional =
        hasRegionalPreview &&
        /label PDF font|runtime label font|label PDF encoding|clipping\/wrapping/i.test(String(pdfCause));
      if (!canFallbackRegional) throw pdfCause;
      pdfPrepCause = pdfCause;
    }
    if (!isCurrent()) return cancelledResult();
    if (pdfPrepCause !== null && importExportSvc.GetPlotLabelRegionalPreview) {
      let fallbackValue: unknown;
      try {
        fallbackValue = await reads.track(importExportSvc.GetPlotLabelRegionalPreview(contextId, requestedPlot));
      } catch {
        throw pdfPrepCause;
      }
      if (!isCurrent()) return cancelledResult();
      const native = validators.validatePlotLabelRegionalPreview!(fallbackValue, contextId, requestedPlot);
      if (!isCurrent()) return cancelledResult();
      return {
        pdfReview: null,
        preview: native.label,
        labelDate: native.labelDate,
        regionalEvidence: native.evidence,
        warningMessage: `On-screen plot label preview is ready, but portable PDF export is unavailable: ${String(pdfPrepCause)}`,
      };
    }
    const candidate = validators.validatePlotLabelPDFReview!(value, owner, requestedPlot);
    const native = validators.validatePlotLabelRegionalPreview!(candidate.preview, contextId, requestedPlot);
    if (!isCurrent()) return cancelledResult();
    return {
      pdfReview: candidate,
      preview: native.label,
      labelDate: native.labelDate,
      regionalEvidence: native.evidence,
    };
  }

  if (hasRegionalPreview && importExportSvc?.GetPlotLabelRegionalPreview) {
    const value = await reads.track(importExportSvc.GetPlotLabelRegionalPreview(contextId, requestedPlot));
    if (!isCurrent()) return cancelledResult();
    const candidate = validators.validatePlotLabelRegionalPreview!(value, contextId, requestedPlot);
    if (!isCurrent()) return cancelledResult();
    return {
      pdfReview: null,
      preview: candidate.label,
      labelDate: candidate.labelDate,
      regionalEvidence: candidate.evidence,
    };
  }

  const value = await reads.track(contextSvc.GetPlot(contextId, requestedPlot));
  if (!isCurrent()) return cancelledResult();
  const candidate = validators.plotLabelFromHeader!(value, requestedPlot);
  const date = validators.makeDate().toLocaleDateString(undefined, {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });
  return { pdfReview: null, preview: candidate, labelDate: date, regionalEvidence: null };
}
