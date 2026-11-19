package main

import (
	"context"
	"path/filepath"
	"testing"
)

func TestExternalSUEnvironmentRegistrationUnconditionalDefaultOn(t *testing.T) {
	services, _, _, _ := openTestDesktopServices(t)
	contextSvc := findRegisteredService[ContextService](t, services)
	classificationSvc := findRegisteredService[ClassificationService](t, services)

	ctx := context.Background()
	state, err := contextSvc.GetState(ctx)
	if err != nil {
		t.Fatalf("ContextService.GetState: %v", err)
	}

	extSUFile := filepath.Join(t.TempDir(), "ExtUnits.db")
	created, err := classificationSvc.CreateSUTable(ctx, state.ContextID, CreateSUTableRequest{
		Name:                    "ExtUnits",
		Destination:             "new_file",
		FilePath:                extSUFile,
		PopulateAllProjectPlots: true,
		SeedFromUserSiteUnit:    true,
		Activate:                true,
	})
	if err != nil || created == nil || !created.Activated || created.NewState == nil {
		t.Fatalf("CreateSUTable(new_file) failed: created=%+v err=%v", created, err)
	}

	review, err := classificationSvc.GetExternalSUEnvironmentReview(ctx, created.NewState.ContextID)
	if err != nil || review == nil {
		t.Fatalf("GetExternalSUEnvironmentReview failed on default-ON ClassificationService: review=%+v err=%v", review, err)
	}
	if len(review.ApprovalHash) != 64 || len(review.SourceHash) != 64 || review.SessionID == "" || review.SUPath == "" {
		t.Fatalf("unexpected ExternalSUEnvironmentReview: %+v", review)
	}

	if _, err := classificationSvc.GetExternalSUEnvironmentReview(ctx, "stale-context-id"); err == nil {
		t.Fatal("expected stale context ID to be rejected by GetExternalSUEnvironmentReview")
	}
}
