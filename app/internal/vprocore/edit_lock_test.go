package vprocore_test

import (
	"context"
	"database/sql"
	"errors"
	"sync"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestEvaluateEditLockAndBECMasterProjectDetection(t *testing.T) {
	for _, masterName := range []string{"BECMaster", "becmaster", "BECMaster_2026", "BECMaster-prod", "BECMaster fixing"} {
		if !vprocore.IsBECMasterProjectName(masterName) {
			t.Fatalf("expected IsBECMasterProjectName(%q) = true", masterName)
		}
	}
	for _, localName := range []string{"", "Sample", "Haida_Gwaii_2019", "MyBECMasterCopy"} {
		if vprocore.IsBECMasterProjectName(localName) {
			t.Fatalf("expected IsBECMasterProjectName(%q) = false", localName)
		}
	}

	unsigned := vprocore.EvaluateEditLock("Sample", vprocore.EditLockSnapshot{
		OIDCConfigured:       true,
		DevFallbackAvailable: false,
	})
	if !unsigned.Locked || unsigned.CanEditCurrentProject || unsigned.SignedIn || !unsigned.OIDCConfigured || unsigned.DevFallbackAvailable || unsigned.Reason == "" {
		t.Fatalf("unexpected unsigned EditLockState: %+v", unsigned)
	}

	viewer := vprocore.EvaluateEditLock("Sample", vprocore.EditLockSnapshot{
		SignedIn: true, UserID: "VIEWER1", DisplayName: "Viewer User", Role: vprocore.AuthRoleViewer, IdentityProvider: "bceid",
	})
	if !viewer.Locked || viewer.CanEditCurrentProject || viewer.Role != vprocore.AuthRoleViewer {
		t.Fatalf("viewer must remain locked: %+v", viewer)
	}

	contribSample := vprocore.EvaluateEditLock("Sample", vprocore.EditLockSnapshot{
		SignedIn: true, UserID: "CONTRIB1", DisplayName: "Field Contrib", Role: vprocore.AuthRoleContributor, IdentityProvider: "idir",
	})
	if contribSample.Locked || !contribSample.CanEditCurrentProject || contribSample.IsBECMasterProject {
		t.Fatalf("contributor should edit working project: %+v", contribSample)
	}

	contribMaster := vprocore.EvaluateEditLock("BECMaster_2026", vprocore.EditLockSnapshot{
		SignedIn: true, UserID: "CONTRIB1", DisplayName: "Field Contrib", Role: vprocore.AuthRoleContributor, IdentityProvider: "idir",
	})
	if !contribMaster.Locked || contribMaster.CanEditCurrentProject || !contribMaster.IsBECMasterProject {
		t.Fatalf("contributor must be locked on BECMaster: %+v", contribMaster)
	}

	regMaster := vprocore.EvaluateEditLock("BECMaster", vprocore.EditLockSnapshot{
		SignedIn: true, UserID: "REG1", DisplayName: "Regional Eco", Role: vprocore.AuthRoleRegionalEcologist, IdentityProvider: "idir",
	})
	if !regMaster.Locked || regMaster.CanEditCurrentProject || !regMaster.IsBECMasterProject {
		t.Fatalf("regional_ecologist must be locked on BECMaster direct edits: %+v", regMaster)
	}

	custMaster := vprocore.EvaluateEditLock("BECMaster", vprocore.EditLockSnapshot{
		SignedIn: true, UserID: "CUST1", DisplayName: "BEC Custodian", Role: vprocore.AuthRoleCustodian, IdentityProvider: "idir",
	})
	if custMaster.Locked || !custMaster.CanEditCurrentProject || !custMaster.IsBECMasterProject {
		t.Fatalf("custodian must be unlocked on BECMaster: %+v", custMaster)
	}
}

func TestContextServiceAuthEditLockEnforcementAndRoleTransitions(t *testing.T) {
	ctx := context.Background()
	svc, state := vprotest.ContextServiceFixture(t)

	// 1. Default un-enforced mode preserves backwards compatibility for existing unit tests.
	if err := svc.CreatePlot(state.ContextID, vprocore.FS882Header{PlotNumber: "UNENF1"}); err != nil {
		t.Fatalf("default un-enforced CreatePlot failed: %v", err)
	}

	var mu sync.Mutex
	currentSnap := vprocore.EditLockSnapshot{
		SignedIn:             false,
		OIDCConfigured:       false,
		DevFallbackAvailable: true,
	}
	setSnap := func(next vprocore.EditLockSnapshot) {
		mu.Lock()
		currentSnap = next
		mu.Unlock()
	}
	vprocore.SetContextEditLockProvider(svc, true, func() vprocore.EditLockSnapshot {
		mu.Lock()
		defer mu.Unlock()
		return currentSnap
	})

	// 2. Enforced & unsigned: all plot mutations fail closed with ErrEditingLockedSignInRequired.
	lockStatus, err := vprocore.GetContextEditLockStatus(svc, ctx, state.ContextID)
	if err != nil {
		t.Fatalf("GetContextEditLockStatus: %v", err)
	}
	if !lockStatus.Locked || lockStatus.CanEditCurrentProject || lockStatus.SignedIn || !lockStatus.DevFallbackAvailable {
		t.Fatalf("expected locked unsigned status, got %+v", lockStatus)
	}
	if err := svc.CreatePlot(state.ContextID, vprocore.FS882Header{PlotNumber: "LOCK01"}); !errors.Is(err, vprocore.ErrEditingLockedSignInRequired) {
		t.Fatalf("unsigned CreatePlot = %v, want ErrEditingLockedSignInRequired", err)
	}
	hdr, err := svc.GetPlot(ctx, state.ContextID, "108050")
	if err != nil {
		t.Fatalf("reads must remain allowed while locked: %v", err)
	}
	if err := svc.UpdatePlot(state.ContextID, *hdr); !errors.Is(err, vprocore.ErrEditingLockedSignInRequired) {
		t.Fatalf("unsigned UpdatePlot = %v, want ErrEditingLockedSignInRequired", err)
	}
	if err := svc.SaveVegRecord(state.ContextID, vprocore.VegRecord{PlotNumber: "108050", Species: "ABIEAMA"}); !errors.Is(err, vprocore.ErrEditingLockedSignInRequired) {
		t.Fatalf("unsigned SaveVegRecord = %v, want ErrEditingLockedSignInRequired", err)
	}
	if err := svc.SaveHumusRecord(state.ContextID, vprocore.HumusRecord{PlotNumber: "108050"}); !errors.Is(err, vprocore.ErrEditingLockedSignInRequired) {
		t.Fatalf("unsigned SaveHumusRecord = %v, want ErrEditingLockedSignInRequired", err)
	}
	if err := svc.SaveMineralRecord(state.ContextID, vprocore.MineralRecord{PlotNumber: "108050"}); !errors.Is(err, vprocore.ErrEditingLockedSignInRequired) {
		t.Fatalf("unsigned SaveMineralRecord = %v, want ErrEditingLockedSignInRequired", err)
	}
	if err := svc.SaveOtherRecord(state.ContextID, vprocore.OtherRecord{PlotNumber: "108050"}); !errors.Is(err, vprocore.ErrEditingLockedSignInRequired) {
		t.Fatalf("unsigned SaveOtherRecord = %v, want ErrEditingLockedSignInRequired", err)
	}
	if err := svc.SetAuditRestoreSelection(state.ContextID, "108050", nil); !errors.Is(err, vprocore.ErrEditingLockedSignInRequired) {
		t.Fatalf("unsigned SetAuditRestoreSelection = %v, want ErrEditingLockedSignInRequired", err)
	}
	if canMaster, err := svc.CanEditMasterBEC(ctx, state.ContextID); err != nil || canMaster {
		t.Fatalf("unsigned CanEditMasterBEC = (%v, %v), want (false, nil)", canMaster, err)
	}

	// 3. Viewer role stays locked with ErrBECMasterPermissionRequired.
	setSnap(vprocore.EditLockSnapshot{
		SignedIn: true, UserID: "VIEW1", DisplayName: "Read Only", Role: vprocore.AuthRoleViewer, IdentityProvider: "bceid",
	})
	if err := svc.CreatePlot(state.ContextID, vprocore.FS882Header{PlotNumber: "LOCK02"}); !errors.Is(err, vprocore.ErrBECMasterPermissionRequired) {
		t.Fatalf("viewer CreatePlot = %v, want ErrBECMasterPermissionRequired", err)
	}

	// 4. Contributor unlocks working project editing but not Master BEC.
	setSnap(vprocore.EditLockSnapshot{
		SignedIn: true, UserID: "CONT1", DisplayName: "Field Ecologist", Role: vprocore.AuthRoleContributor, IdentityProvider: "idir",
	})
	if err := svc.CreatePlot(state.ContextID, vprocore.FS882Header{PlotNumber: "CONT01"}); err != nil {
		t.Fatalf("contributor CreatePlot on Sample failed: %v", err)
	}
	if canMaster, err := svc.CanEditMasterBEC(ctx, state.ContextID); err != nil || canMaster {
		t.Fatalf("contributor CanEditMasterBEC = (%v, %v), want (false, nil)", canMaster, err)
	}

	// 5. Custodian unlocks Master BEC even when user name is not legacy "Will MacKenzie".
	setSnap(vprocore.EditLockSnapshot{
		SignedIn: true, UserID: "CUST1", DisplayName: "Provincial Custodian", Role: vprocore.AuthRoleCustodian, IdentityProvider: "idir",
	})
	if canMaster, err := svc.CanEditMasterBEC(ctx, state.ContextID); err != nil || !canMaster {
		t.Fatalf("custodian CanEditMasterBEC = (%v, %v), want (true, nil)", canMaster, err)
	}
	acc, err := svc.GetUserSetup(ctx, state.ContextID)
	if err != nil || !acc.MasterBECAllowed || !acc.CanEditBECSiteUnit || !acc.Accredited {
		t.Fatalf("custodian GetUserSetup = %+v err=%v, want MasterBECAllowed+CanEditBECSiteUnit", acc, err)
	}

	// 6. Direct PlotService CheckEditLock on BECMaster project rejects contributor and allows custodian.
	directPlots := vprocore.NewPlotService(&vprocore.ProjectService{Active: "BECMaster_2026"})
	directPlots.SetEditLockProvider(true, func() vprocore.EditLockSnapshot {
		mu.Lock()
		defer mu.Unlock()
		return currentSnap
	})
	setSnap(vprocore.EditLockSnapshot{
		SignedIn: true, UserID: "CONT1", DisplayName: "Field Ecologist", Role: vprocore.AuthRoleContributor, IdentityProvider: "idir",
	})
	if err := directPlots.CheckEditLock(); !errors.Is(err, vprocore.ErrBECMasterPermissionRequired) {
		t.Fatalf("contributor CheckEditLock on BECMaster_2026 = %v, want ErrBECMasterPermissionRequired", err)
	}
	scopedDirect, err := directPlots.WithRequestContext(ctx)
	if err != nil {
		t.Fatalf("WithRequestContext: %v", err)
	}
	if err := scopedDirect.CheckEditLock(); !errors.Is(err, vprocore.ErrBECMasterPermissionRequired) {
		t.Fatalf("WithRequestContext must preserve edit lock policy, got %v", err)
	}
	setSnap(vprocore.EditLockSnapshot{
		SignedIn: true, UserID: "CUST1", DisplayName: "Provincial Custodian", Role: vprocore.AuthRoleCustodian, IdentityProvider: "idir",
	})
	if err := directPlots.CheckEditLock(); err != nil {
		t.Fatalf("custodian CheckEditLock on BECMaster_2026 failed: %v", err)
	}

	// 7. Sign-out re-locks immediately.
	setSnap(vprocore.EditLockSnapshot{SignedIn: false})
	if err := svc.CreatePlot(state.ContextID, vprocore.FS882Header{PlotNumber: "LOCK03"}); !errors.Is(err, vprocore.ErrEditingLockedSignInRequired) {
		t.Fatalf("post-signout CreatePlot = %v, want ErrEditingLockedSignInRequired", err)
	}

	// 8. Central SQLite write gates fail closed even after SwitchContext creates a new SqliteContext.
	switched, err := svc.SwitchContext(state.ContextID, vprocore.ContextSelection{
		Project:       state.ActiveProject,
		ProjectPath:   state.ProjectPath,
		SU:            "None",
		Hierarchy:     "None",
	})
	if err != nil {
		t.Fatalf("SwitchContext while locked must remain allowed for reading: %v", err)
	}
	owner := svc.Projects.Sqlite
	if _, err := owner.ProjectDatabase(ctx); !errors.Is(err, vprocore.ErrEditingLockedSignInRequired) {
		t.Fatalf("post-switch ProjectDatabase = %v, want ErrEditingLockedSignInRequired", err)
	}
	if err := owner.WithImmediateWriteTx(ctx, func(_ *vprocore.WriteTx) error { return nil }); !errors.Is(err, vprocore.ErrEditingLockedSignInRequired) {
		t.Fatalf("post-switch WithImmediateWriteTx = %v, want ErrEditingLockedSignInRequired", err)
	}
	if err := owner.WithSelectedFileWriter(ctx, "project", func() error { return nil }, func(_ *sql.Conn) error { return nil }); !errors.Is(err, vprocore.ErrEditingLockedSignInRequired) {
		t.Fatalf("post-switch WithSelectedFileWriter = %v, want ErrEditingLockedSignInRequired", err)
	}
	if err := svc.Edit(switched.ContextID, func(_ *vprocore.PlotService) error { return nil }); !errors.Is(err, vprocore.ErrEditingLockedSignInRequired) {
		t.Fatalf("post-switch ContextService.Edit = %v, want ErrEditingLockedSignInRequired", err)
	}
	if err := vprocore.EditContext(ctx, svc, switched.ContextID, func(_ *vprocore.PlotService) error { return nil }); !errors.Is(err, vprocore.ErrEditingLockedSignInRequired) {
		t.Fatalf("post-switch EditContext = %v, want ErrEditingLockedSignInRequired", err)
	}
	if _, err := svc.CreateWorkspaceResource(ctx, switched.ContextID, vprocore.CreateWorkspaceResourceRequest{
		Kind:            vprocore.WorkspaceResourceSU,
		Name:            "BlockedSU",
		DestinationMode: "active_project",
	}); !errors.Is(err, vprocore.ErrEditingLockedSignInRequired) {
		t.Fatalf("post-switch CreateWorkspaceResource = %v, want ErrEditingLockedSignInRequired", err)
	}
}
