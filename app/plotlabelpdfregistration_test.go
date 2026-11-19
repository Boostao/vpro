package main

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestPlotLabelPDFRegistrationIsUnconditionallyRegisteredOnImportExportService(t *testing.T) {
	services, _, _, _ := openTestDesktopServices(t)
	contextSvc := findRegisteredService[ContextService](t, services)
	importExportSvc := findRegisteredService[ImportExportService](t, services)

	ctx := context.Background()
	state, err := contextSvc.GetState(ctx)
	if err != nil {
		t.Fatalf("ContextService.GetState: %v", err)
	}

	review, err := importExportSvc.GetPlotLabelPDFReview(ctx, state.ContextID, `{"plotNumber":"108050"}`)
	if err != nil || review == nil {
		t.Fatalf("GetPlotLabelPDFReview failed on default-ON ImportExportService: review=%+v err=%v", review, err)
	}
	if review.Project != "Sample" || len(review.ApprovalHash) != 64 || len(review.PDFSHA256) != 64 || review.SessionID == "" {
		t.Fatalf("unexpected PlotLabelPDFExportReview: %+v", review)
	}

	destPDF := filepath.Join(t.TempDir(), "plot-108050-label.pdf")
	exportReq, err := json.Marshal(map[string]string{
		"plotNumber":   "108050",
		"approvalHash": review.ApprovalHash,
		"destination":  destPDF,
		"requestId":    "11111111-2222-4333-8444-555555555555",
		"sessionId":    review.SessionID,
	})
	if err != nil {
		t.Fatal(err)
	}
	outcome, err := importExportSvc.ExportReviewedPlotLabelPDF(ctx, state.ContextID, string(exportReq))
	if err != nil || outcome == nil || outcome.Status != "published" || outcome.SHA256 != review.PDFSHA256 {
		t.Fatalf("ExportReviewedPlotLabelPDF failed: outcome=%+v err=%v", outcome, err)
	}
	pdfBytes, err := os.ReadFile(destPDF)
	if err != nil || !bytes.HasPrefix(pdfBytes, []byte("%PDF-")) {
		t.Fatalf("expected published PDF file at %s, err=%v", destPDF, err)
	}

	recovered, err := importExportSvc.RecoverPlotLabelPDFOutcome(ctx, state.ContextID, string(exportReq))
	if err != nil || recovered == nil || recovered.Outcome == nil || recovered.Outcome.SHA256 != review.PDFSHA256 {
		t.Fatalf("RecoverPlotLabelPDFOutcome failed: recovered=%+v err=%v", recovered, err)
	}

	if _, err := importExportSvc.GetPlotLabelPDFReview(ctx, "stale-context-id", `{"plotNumber":"108050"}`); err == nil {
		t.Fatal("expected stale context ID to be rejected by GetPlotLabelPDFReview")
	}
}
