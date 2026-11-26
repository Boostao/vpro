package main

import (
	"context"
	"errors"
	"path/filepath"
	"testing"

	authpkg "github.com/boostao/vpro/app/internal/auth"
	classificationpkg "github.com/boostao/vpro/app/internal/classification"
	datasheetpkg "github.com/boostao/vpro/app/internal/datasheet"
	diagnosticspkg "github.com/boostao/vpro/app/internal/diagnostics"
	interchangepkg "github.com/boostao/vpro/app/internal/interchange"
	lifecyclepkg "github.com/boostao/vpro/app/internal/lifecycle"
	projectopspkg "github.com/boostao/vpro/app/internal/projectops"
	rsidecarpkg "github.com/boostao/vpro/app/internal/rsidecar"
	spatialpkg "github.com/boostao/vpro/app/internal/spatial"
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

	// 5. SignOut re-locks data editing immediately and clears stale CurrentUser (P2 #8).
	out, err := ctxSvc.SignOut(ctx)
	if err != nil || out.SignedIn {
		t.Fatalf("SignOut failed: %+v err=%v", out, err)
	}
	live, release := ctxSvc.acquire()
	live.core.Plots.Mu.RLock()
	afterSignOutUser := live.core.Plots.CurrentUser
	live.core.Plots.Mu.RUnlock()
	release()
	if afterSignOutUser != "" {
		t.Fatalf("expected SignOut to clear core.Plots.CurrentUser, got %q", afterSignOutUser)
	}
	if err := ctxSvc.CreatePlot(ctx, state.ContextID, vprocorepkg.FS882Header{PlotNumber: "AUTH02"}); !errors.Is(err, vprocorepkg.ErrEditingLockedSignInRequired) {
		t.Fatalf("post-signout CreatePlot = %v, want ErrEditingLockedSignInRequired", err)
	}
}

func TestDesktopEditLockEnforcedAcrossAllMutatingServicesAndBECMaster(t *testing.T) {
	t.Setenv("VPRO_OIDC_CLIENT_ID", "")
	t.Setenv("VPRO_BUILD_MODE", "")
	t.Setenv("VPRO_TELEMETRY_URL", "")
	t.Setenv("VPRO_TELEMETRY_PG_URL", "")
	t.Setenv("VPRO_PG_URL", "")

	dataDir := t.TempDir()
	configDir := t.TempDir()
	refs := openReferenceCatalogBundle(dataDir)
	cloud := NewCloudSyncManager(configDir)
	closeSvc, err := lifecyclepkg.NewCloseService(func(string) bool { return false }, func() {})
	if err != nil {
		refs.Close()
		cloud.Close()
		t.Fatalf("NewCloseService: %v", err)
	}
	emptyEnv := func(string) (string, bool) { return "", false }
	services, graph := buildDesktopServicesWithAuthLock(dataDir, configDir, refs, cloud, closeSvc, emptyEnv, true)
	t.Cleanup(func() {
		graph.tracker.shutdown(refs, cloud)
	})

	ctx := context.Background()
	ctxSvc := findRegisteredService[ContextService](t, services)
	plotEntrySvc := findRegisteredService[PlotEntryService](t, services)
	datasheetSvc := findRegisteredService[DatasheetService](t, services)
	classSvc := findRegisteredService[ClassificationService](t, services)
	valSvc := findRegisteredService[ValidationService](t, services)
	ieSvc := findRegisteredService[ImportExportService](t, services)
	envRepSvc := findRegisteredService[EnvironmentReportService](t, services)
	spatialSvc := findRegisteredService[SpatialService](t, services)

	// Switch to Sample with Sample SU and Sample Hierarchy active so SU/Hierarchy/Synthesis mutations
	// exercise the real write path rather than failing early on "None".
	state, err := ctxSvc.GetState(ctx)
	if err != nil {
		t.Fatalf("GetState: %v", err)
	}
	var suPath, hierPath string
	for _, su := range state.SUs {
		if su.Name == "Sample" {
			suPath = su.Path
			break
		}
	}
	for _, h := range state.Hierarchies {
		if h.Name == "Sample" {
			hierPath = h.Path
			break
		}
	}
	state, err = ctxSvc.SwitchContext(ctx, state.ContextID, ContextSelection{
		Project:       state.ActiveProject,
		ProjectPath:   state.ProjectPath,
		SU:            "Sample",
		SUPath:        suPath,
		Hierarchy:     "Sample",
		HierarchyPath: hierPath,
	})
	if err != nil {
		t.Fatalf("SwitchContext while unsigned must remain allowed: %v", err)
	}

	// Read first plot & env rowID for realistic datasheet/spatial/SU mutation payloads.
	envPage, err := datasheetSvc.GetDatasheetPage(ctx, state.ContextID, datasheetpkg.DatasheetPageRequest{
		TableKey: "env",
		Offset:   0,
		Limit:    1,
	})
	if err != nil || len(envPage.Rows) == 0 {
		t.Fatalf("GetDatasheetPage(env): err=%v rows=%d", err, len(envPage.Rows))
	}
	firstRowID := envPage.Rows[0].RowID
	plotColIdx := -1
	locColIdx := -1
	for i, col := range envPage.Columns {
		if col.Name == "PlotNumber" {
			plotColIdx = i
		}
		if col.Name == "Location" {
			locColIdx = i
		}
	}
	if plotColIdx < 0 || locColIdx < 0 {
		t.Fatalf("expected PlotNumber and Location columns in env page")
	}
	firstPlot := *envPage.Rows[0].Cells[plotColIdx].Text
	beforeLoc := envPage.Rows[0].Cells[locColIdx]
	afterLocText := "LOCK_BYPASS_TEST"
	targetUnit := "CWHxm1/01"
	otherData := "lock-test"

	probeAllMutatingServices := func(t *testing.T, contextID string, wantErr error) {
		t.Helper()
		checks := []struct {
			name string
			run  func() error
		}{
			{
				name: "ContextService.CreatePlot",
				run:  func() error { return ctxSvc.CreatePlot(ctx, contextID, vprocorepkg.FS882Header{PlotNumber: "LCK999"}) },
			},
			{
				name: "PlotEntryService.EnsureMensurationTables",
				run: func() error {
					_, err := plotEntrySvc.EnsureMensurationTables(ctx, contextID)
					return err
				},
			},
			{
				name: "DatasheetService.ApplyDatasheetEdits",
				run: func() error {
					_, err := datasheetSvc.ApplyDatasheetEdits(ctx, contextID, datasheetpkg.DatasheetEditRequest{
						TableKey: "env",
						Edits: []datasheetpkg.DatasheetCellEdit{
							{
								RowID:  firstRowID,
								Column: "Location",
								Before: beforeLoc,
								After:  vprocorepkg.ProjectMetadataCell{Storage: "text", Text: &afterLocText},
							},
						},
					})
					return err
				},
			},
			{
				name: "DatasheetService.InsertDatasheetChildRow",
				run: func() error {
					_, err := datasheetSvc.InsertDatasheetChildRow(ctx, contextID, datasheetpkg.DatasheetInsertChildRowRequest{
						TableKey:   "other",
						PlotNumber: firstPlot,
						Cells: map[string]vprocorepkg.ProjectMetadataCell{
							"DataName": {Storage: "text", Text: &otherData},
						},
					})
					return err
				},
			},
			{
				name: "ClassificationService.AssignPlotsToSiteUnit",
				run: func() error {
					_, err := classSvc.AssignPlotsToSiteUnit(ctx, contextID, classificationpkg.AssignPlotsToSiteUnitRequest{
						PlotNumbers:    []string{firstPlot},
						TargetSiteUnit: &targetUnit,
					})
					return err
				},
			},
			{
				name: "ClassificationService.AddHierarchyNode",
				run: func() error {
					_, err := classSvc.AddHierarchyNode(ctx, contextID, classificationpkg.HierarchyAddNodeRequest{
						Name:  "LockBypassNode",
						Level: 1,
					})
					return err
				},
			},
			{
				name: "ClassificationService.SaveUserSiteUnitEntry",
				run: func() error {
					_, err := classSvc.SaveUserSiteUnitEntry(ctx, contextID, classificationpkg.UpsertUserSiteUnitRequest{
						SiteSeries:         "LOCK/01",
						SiteSeriesLongName: "Lock Bypass Test",
					})
					return err
				},
			},
			{
				name: "ImportExportService.CreateLumpTable",
				run: func() error {
					_, err := ieSvc.CreateLumpTable(ctx, contextID, "LockBypassLump")
					return err
				},
			},
			{
				name: "ImportExportService.ImportUserSpeciesList",
				run: func() error {
					_, err := ieSvc.ImportUserSpeciesList(ctx, contextID, interchangepkg.UserSpeciesImportRequest{
						Format:          "csv",
						Content:         "Code,ScientificName,EnglishName,Lifeform\nTESTSP1,Test species,Test,1\n",
						CollisionPolicy: interchangepkg.CollisionSkip,
					})
					return err
				},
			},
			{
				name: "SpatialService.ApplySpatialAttributes",
				run: func() error {
					_, err := spatialSvc.ApplySpatialAttributes(ctx, contextID, spatialpkg.ApplySpatialAttributesRequest{
						PlotNumbers:            []string{firstPlot},
						NormalizeLongitudeSign: true,
					})
					return err
				},
			},
			{
				name: "ValidationService.ApplyOptimizeVeg",
				run: func() error {
					_, err := valSvc.ApplyOptimizeVeg(ctx, contextID, projectopspkg.ApplyOptimizeVegRequest{})
					return err
				},
			},
			{
				name: "ContextService.CreateWorkspaceResource",
				run: func() error {
					_, err := ctxSvc.CreateWorkspaceResource(ctx, contextID, CreateWorkspaceResourceRequest{
						Kind:            vprocorepkg.WorkspaceResourceSU,
						Name:            "LockBypassSU",
						DestinationMode: "active_project",
					})
					return err
				},
			},
			{
				name: "EnvironmentReportService.PromoteClusterCandidateToSU",
				run: func() error {
					_, err := envRepSvc.PromoteClusterCandidateToSU(ctx, contextID, rsidecarpkg.PromoteCandidateSURequest{
						CandidateSUName: "Sample_ClusterCandidate",
						TargetSUName:    "LockBypassPromoted",
					})
					return err
				},
			},
			{
				name: "ClassificationService.ReassignSynthesisPlotUnit",
				run: func() error {
					_, err := classSvc.ReassignSynthesisPlotUnit(ctx, contextID, diagnosticspkg.ReassignSynthesisPlotRequest{
						PlotNumber:     firstPlot,
						TargetSiteUnit: targetUnit,
					})
					return err
				},
			},
		}

		for _, chk := range checks {
			err := chk.run()
			if !errors.Is(err, wantErr) {
				t.Errorf("%s: got err=%v, want %v", chk.name, err, wantErr)
			}
		}
	}

	// 1. Unsigned: ALL 14 mutating RPCs fail closed with ErrEditingLockedSignInRequired.
	t.Run("unsigned_locked", func(t *testing.T) {
		probeAllMutatingServices(t, state.ContextID, vprocorepkg.ErrEditingLockedSignInRequired)
	})

	// 2. Viewer role: ALL 14 mutating RPCs fail closed with ErrBECMasterPermissionRequired.
	if _, err := ctxSvc.CompleteDevEvaluationSignIn(ctx, "qa.viewer", "QA Viewer", authpkg.RoleViewer); err != nil {
		t.Fatalf("sign in viewer: %v", err)
	}
	t.Run("viewer_locked", func(t *testing.T) {
		probeAllMutatingServices(t, state.ContextID, vprocorepkg.ErrBECMasterPermissionRequired)
	})

	// 3. Export a real BECMaster.db (with Sample_SU and Sample_Hierarchy renamed/copied), attach & activate it,
	// and verify Custodian can edit BECMaster while lock propagation across SwitchContext blocks Contributor & Regional Ecologist!
	if _, err := ctxSvc.CompleteDevEvaluationSignIn(ctx, "qa.custodian", "QA Custodian", authpkg.RoleCustodian); err != nil {
		t.Fatalf("sign in custodian: %v", err)
	}
	masterDBPath := filepath.Join(t.TempDir(), "BECMaster.db")
	if _, err := ieSvc.ExportVPro64Database(ctx, state.ContextID, interchangepkg.VPro64ExportRequest{
		DestinationPath:   masterDBPath,
		TargetProjectName: "BECMaster",
		IncludeActiveSU:   true,
		IncludeHierarchy:  true,
	}); err != nil {
		t.Fatalf("ExportVPro64Database(BECMaster): %v", err)
	}
	attachedMaster, err := ctxSvc.AttachWorkspaceResource(ctx, state.ContextID, AttachWorkspaceResourceRequest{
		Kind:     vprocorepkg.WorkspaceResourceProject,
		Path:     masterDBPath,
		Name:     "BECMaster",
		Activate: true,
	})
	if err != nil {
		t.Fatalf("AttachWorkspaceResource(BECMaster): %v", err)
	}
	masterState := attachedMaster.State
	// Activate BECMaster's SU and Hierarchy (exported into BECMaster.db as BECMaster_SU / Sample_SU and Sample_Hierarchy).
	var bmSU, bmSUPath, bmHier, bmHierPath string
	for _, su := range masterState.SUs {
		if vprocorepkg.SameDesktopPath(su.Path, masterDBPath) {
			bmSU, bmSUPath = su.Name, su.Path
			break
		}
	}
	for _, h := range masterState.Hierarchies {
		if vprocorepkg.SameDesktopPath(h.Path, masterDBPath) {
			bmHier, bmHierPath = h.Name, h.Path
			break
		}
	}
	if bmSU == "" {
		bmSU = "None"
	}
	if bmHier == "" {
		bmHier, bmHierPath = "Sample", hierPath
	}
	masterState, err = ctxSvc.SwitchContext(ctx, masterState.ContextID, ContextSelection{
		Project:       "BECMaster",
		ProjectPath:   masterState.ProjectPath,
		SU:            bmSU,
		SUPath:        bmSUPath,
		Hierarchy:     bmHier,
		HierarchyPath: bmHierPath,
	})
	if err != nil {
		t.Fatalf("SwitchContext(BECMaster): %v", err)
	}
	if err := ctxSvc.CreatePlot(ctx, masterState.ContextID, vprocorepkg.FS882Header{PlotNumber: "BM0001"}); err != nil {
		t.Fatalf("custodian CreatePlot on BECMaster failed: %v", err)
	}

	// Read first plot rowID on BECMaster for datasheet edit probe.
	bmEnvPage, err := datasheetSvc.GetDatasheetPage(ctx, masterState.ContextID, datasheetpkg.DatasheetPageRequest{
		TableKey: "env",
		Offset:   0,
		Limit:    1,
	})
	if err != nil || len(bmEnvPage.Rows) == 0 {
		t.Fatalf("GetDatasheetPage(BECMaster env): err=%v rows=%d", err, len(bmEnvPage.Rows))
	}
	firstRowID = bmEnvPage.Rows[0].RowID
	for i, col := range bmEnvPage.Columns {
		if col.Name == "PlotNumber" && bmEnvPage.Rows[0].Cells[i].Text != nil {
			firstPlot = *bmEnvPage.Rows[0].Cells[i].Text
		}
		if col.Name == "Location" {
			beforeLoc = bmEnvPage.Rows[0].Cells[i]
		}
	}

	// 4. Contributor on BECMaster: ALL 14 mutating RPCs fail closed with ErrBECMasterPermissionRequired!
	if _, err := ctxSvc.CompleteDevEvaluationSignIn(ctx, "qa.contrib", "QA Contributor", authpkg.RoleContributor); err != nil {
		t.Fatalf("sign in contributor: %v", err)
	}
	t.Run("contributor_blocked_on_becmaster", func(t *testing.T) {
		probeAllMutatingServices(t, masterState.ContextID, vprocorepkg.ErrBECMasterPermissionRequired)
	})

	// 5. Regional Ecologist on BECMaster: ALL 14 mutating RPCs fail closed with ErrBECMasterPermissionRequired!
	if _, err := ctxSvc.CompleteDevEvaluationSignIn(ctx, "qa.regional", "QA Regional", authpkg.RoleRegionalEcologist); err != nil {
		t.Fatalf("sign in regional ecologist: %v", err)
	}
	t.Run("regional_ecologist_blocked_on_becmaster", func(t *testing.T) {
		probeAllMutatingServices(t, masterState.ContextID, vprocorepkg.ErrBECMasterPermissionRequired)
	})

	// 6. SignOut clears CurrentUser and re-locks immediately.
	if _, err := ctxSvc.SignOut(ctx); err != nil {
		t.Fatalf("SignOut: %v", err)
	}
	live, release := ctxSvc.acquire()
	live.core.Plots.Mu.RLock()
	userAfterSignOut := live.core.Plots.CurrentUser
	live.core.Plots.Mu.RUnlock()
	release()
	if userAfterSignOut != "" {
		t.Fatalf("expected CurrentUser cleared after SignOut, got %q", userAfterSignOut)
	}
	t.Run("post_signout_locked_on_becmaster", func(t *testing.T) {
		probeAllMutatingServices(t, masterState.ContextID, vprocorepkg.ErrEditingLockedSignInRequired)
	})
}
