package main

import (
	"context"
	"encoding/json"
	"testing"

	vegreportpkg "github.com/boostao/vpro/app/internal/vegreport"
	vprocorepkg "github.com/boostao/vpro/app/internal/vprocore"
)

func TestProjectRegistrationUnconditionalDefaultOn(t *testing.T) {
	ctx := context.Background()
	scope := vegreportpkg.NewLongVegetationReportScopeService(nil)
	if value, err := scope.GetLongVegetationReportScope(ctx, "owned"); err == nil || value != nil {
		t.Fatal("unconfigured scope service authorized scope", value, err)
	}
	workbook := vegreportpkg.NewLongVegetationProjectWorkbookService(nil)
	if value, err := workbook.GetReview(ctx, "owned", `{}`); err == nil || value != nil {
		t.Fatal("unconfigured workbook service authorized review", value, err)
	}

	services, _, _, _ := openTestDesktopServices(t)
	contextSvc := findRegisteredService[ContextService](t, services)
	vegReportSvc := findRegisteredService[VegetationReportService](t, services)

	initState, err := contextSvc.GetState(ctx)
	if err != nil {
		t.Fatalf("ContextService.GetState: %v", err)
	}
	noneState, err := contextSvc.SwitchContext(initState.ContextID, vprocorepkg.ContextSelection{
		Project:       initState.ActiveProject,
		ProjectPath:   initState.ProjectPath,
		SU:            "None",
		SUPath:        "",
		Hierarchy:     initState.ActiveHierarchy,
		HierarchyPath: initState.HierarchyPath,
	})
	if err != nil {
		t.Fatalf("ContextService.SelectSU(None): %v", err)
	}

	initialScope, err := vegReportSvc.GetLongVegetationReportScope(ctx, noneState.ContextID)
	if err != nil || initialScope == nil || initialScope.Project != "Sample" || initialScope.SU != "None" {
		t.Fatalf("GetLongVegetationReportScope failed on default-ON VegetationReportService: scope=%+v err=%v", initialScope, err)
	}

	unitReview, err := vegReportSvc.GetLongVegetationUnitPreferences(ctx, noneState.ContextID)
	if err != nil || unitReview == nil {
		t.Fatalf("GetLongVegetationUnitPreferences failed: review=%+v err=%v", unitReview, err)
	}
	unitSaveJSON, err := json.Marshal(vegreportpkg.LongVegetationUnitPreferencesRequest{
		Expected: unitReview.Values,
		Proposed: vegreportpkg.LongVegetationUnitPreferenceValues{UnitGroups: 3},
	})
	if err != nil {
		t.Fatal(err)
	}
	unitSaved := vegReportSvc.SaveLongVegetationUnitPreferences(ctx, noneState.ContextID, string(unitSaveJSON))
	if !unitSaved.Committed || unitSaved.ErrorMessage != "" {
		t.Fatalf("SaveLongVegetationUnitPreferences(3) failed: %+v", unitSaved)
	}

	scopeAfterUnit, err := vegReportSvc.GetLongVegetationReportScope(ctx, noneState.ContextID)
	if err != nil || scopeAfterUnit == nil {
		t.Fatalf("GetLongVegetationReportScope after unit preference save failed: scope=%+v err=%v", scopeAfterUnit, err)
	}
	setReq, err := json.Marshal(map[string]string{
		"revision":   scopeAfterUnit.Revision,
		"sourceKind": vprocorepkg.VegetationProjectAllScope,
	})
	if err != nil {
		t.Fatal(err)
	}
	updatedScope, err := vegReportSvc.SetLongVegetationReportScope(ctx, noneState.ContextID, string(setReq))
	if err != nil || updatedScope == nil || updatedScope.SourceKind != vprocorepkg.VegetationProjectAllScope {
		t.Fatalf("SetLongVegetationReportScope(all-plots) failed: scope=%+v err=%v", updatedScope, err)
	}

	builtScope, err := vegReportSvc.BuildLongVegetationProjectScope(ctx, noneState.ContextID, updatedScope.Revision)
	if err != nil || builtScope == nil || !builtScope.BuildCurrent || builtScope.Build == nil {
		t.Fatalf("BuildLongVegetationProjectScope failed: scope=%+v err=%v", builtScope, err)
	}

	reviewReq, err := json.Marshal(map[string]string{
		"revision":          builtScope.Revision,
		"buildApprovalHash": builtScope.Build.ApprovalHash,
		"scope":             "unlumped",
	})
	if err != nil {
		t.Fatal(err)
	}
	wbReview, err := vegReportSvc.GetLongVegetationProjectWorkbookReview(ctx, noneState.ContextID, string(reviewReq))
	if err != nil || wbReview == nil || wbReview.Bytes == 0 || len(wbReview.ApprovalHash) != 64 || len(wbReview.WorkbookSHA256) != 64 {
		t.Fatalf("GetLongVegetationProjectWorkbookReview failed: review=%+v err=%v", wbReview, err)
	}
}
