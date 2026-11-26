package main

import (
	"context"
	"errors"
	"testing"

	authpkg "github.com/boostao/vpro/app/internal/auth"
	vprocorepkg "github.com/boostao/vpro/app/internal/vprocore"
)

func TestContextServiceAuthRPCsEditLockAndActivityLifecycle(t *testing.T) {
	t.Setenv("VPRO_OIDC_CLIENT_ID", "")
	t.Setenv("VPRO_BUILD_MODE", "")
	t.Setenv("VPRO_TELEMETRY_URL", "")
	t.Setenv("VPRO_TELEMETRY_PG_URL", "")
	t.Setenv("VPRO_PG_URL", "")

	services, _, _, _ := openTestDesktopServices(t)
	if len(services) != 12 {
		t.Fatalf("expected strictly 12 services, got %d", len(services))
	}
	ctxSvc := findRegisteredService[ContextService](t, services)
	ctx := context.Background()

	state, err := ctxSvc.GetState(ctx)
	if err != nil {
		t.Fatalf("GetState: %v", err)
	}

	// 1. Initial auth session is unsigned and edit lock is active once auth RPC initializes.
	sess, err := ctxSvc.GetAuthSession(ctx)
	if err != nil {
		t.Fatalf("GetAuthSession: %v", err)
	}
	if sess.SignedIn || sess.MachineID == "" || !sess.DevFallbackAvailable {
		t.Fatalf("unexpected initial session: %+v", sess)
	}

	lockState, err := ctxSvc.GetEditLockStatus(ctx, state.ContextID)
	if err != nil {
		t.Fatalf("GetEditLockStatus: %v", err)
	}
	if !lockState.Locked || lockState.CanEditCurrentProject || lockState.SignedIn || lockState.IsBECMasterProject {
		t.Fatalf("expected locked initial EditLockState on Sample, got %+v", lockState)
	}

	// Unsigned mutation fails closed with ErrEditingLockedSignInRequired.
	if err := ctxSvc.CreatePlot(ctx, state.ContextID, vprocorepkg.FS882Header{PlotNumber: "AUTH01"}); !errors.Is(err, vprocorepkg.ErrEditingLockedSignInRequired) {
		t.Fatalf("unsigned CreatePlot = %v, want ErrEditingLockedSignInRequired", err)
	}

	// 2. BeginOIDCSignIn without VPRO_OIDC_CLIENT_ID fails cleanly with ErrOIDCNotConfigured.
	if _, err := ctxSvc.BeginOIDCSignIn(ctx, "idir"); !errors.Is(err, authpkg.ErrOIDCNotConfigured) {
		t.Fatalf("BeginOIDCSignIn without client ID = %v, want ErrOIDCNotConfigured", err)
	}

	// 3. Dev evaluation sign-in as contributor unlocks working project edits.
	signedIn, err := ctxSvc.CompleteDevEvaluationSignIn(ctx, "dev.contrib", "Dev Contributor", authpkg.RoleContributor)
	if err != nil {
		t.Fatalf("CompleteDevEvaluationSignIn: %v", err)
	}
	if !signedIn.SignedIn || signedIn.Role != authpkg.RoleContributor || !signedIn.CanEditWorkingProjects || signedIn.CanEditBECMaster {
		t.Fatalf("unexpected dev signed-in summary: %+v", signedIn)
	}

	unlocked, err := ctxSvc.GetEditLockStatus(ctx, state.ContextID)
	if err != nil || unlocked.Locked || !unlocked.CanEditCurrentProject || unlocked.DisplayName != "Dev Contributor" {
		t.Fatalf("expected unlocked contributor state, got %+v err=%v", unlocked, err)
	}
	if err := ctxSvc.CreatePlot(ctx, state.ContextID, vprocorepkg.FS882Header{PlotNumber: "AUTH01"}); err != nil {
		t.Fatalf("contributor CreatePlot failed: %v", err)
	}

	// 4. Activity telemetry queues offline cleanly.
	act, err := ctxSvc.RecordAppActivity(ctx, authpkg.EventKindDatasetUpload, "Sample", 12)
	if err != nil || !act.Queued || act.EventID == "" || act.PendingCount < 1 {
		t.Fatalf("RecordAppActivity failed: %+v err=%v", act, err)
	}

	// 5. SignOut re-locks data editing immediately.
	out, err := ctxSvc.SignOut(ctx)
	if err != nil || out.SignedIn {
		t.Fatalf("SignOut failed: %+v err=%v", out, err)
	}
	if err := ctxSvc.CreatePlot(ctx, state.ContextID, vprocorepkg.FS882Header{PlotNumber: "AUTH02"}); !errors.Is(err, vprocorepkg.ErrEditingLockedSignInRequired) {
		t.Fatalf("post-signout CreatePlot = %v, want ErrEditingLockedSignInRequired", err)
	}
}
