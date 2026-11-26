package vprocore

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"testing"
)

func openWorkspaceTestContext(t *testing.T) (*ContextService, ProjectState) {
	t.Helper()
	dataDir := t.TempDir()
	configDir := t.TempDir()
	prefs, err := OpenDesktopConfig(dataDir, configDir)
	if err != nil {
		t.Fatalf("OpenDesktopConfig: %v", err)
	}
	projects, err := NewSQLiteProjectService(dataDir, configDir, prefs)
	if err != nil {
		t.Fatalf("NewSQLiteProjectService: %v", err)
	}
	t.Cleanup(func() { _ = projects.CloseSQLiteContext() })
	plots, err := NewPlotServiceWithPreferences(projects)
	if err != nil {
		t.Fatalf("NewPlotServiceWithPreferences: %v", err)
	}
	ctxSvc, err := NewContextService(projects, plots)
	if err != nil {
		t.Fatalf("NewContextService: %v", err)
	}
	state, err := projects.GetState(context.Background())
	if err != nil {
		t.Fatalf("GetState: %v", err)
	}
	return ctxSvc, state
}

func TestWorkspaceResourcesCreateAttachUnattachPreservesDiskFiles(t *testing.T) {
	ctx := context.Background()
	svc, state := openWorkspaceTestContext(t)
	extDir := t.TempDir()

	// 1. Create a standalone external project .db and activate it.
	extProjPath := filepath.Join(extDir, "FieldStudy2026.db")
	createdProj, err := svc.CreateWorkspaceResource(ctx, state.ContextID, CreateWorkspaceResourceRequest{
		Kind:            WorkspaceResourceProject,
		Name:            "FieldStudy2026",
		DestinationMode: "custom_new_file",
		FilePath:        extProjPath,
		ProjectTitle:    "BC Field Study 2026",
		Activate:        true,
	})
	if err != nil {
		t.Fatalf("CreateWorkspaceResource(project): %v", err)
	}
	if !createdProj.Activated || createdProj.State.ActiveProject != "FieldStudy2026" {
		t.Fatalf("expected FieldStudy2026 active, got %+v", createdProj)
	}
	if _, err := os.Stat(extProjPath); err != nil {
		t.Fatalf("external project file missing: %v", err)
	}
	state = createdProj.State

	// Switch back to Sample and confirm FieldStudy2026 stays attached in GetState().
	sampleProj := CompatibleProject(state.Projects, "Sample")
	state, err = svc.SwitchContext(state.ContextID, ContextSelection{
		Project:       "Sample",
		ProjectPath:   sampleProj.Path,
		SU:            "None",
		Hierarchy:     state.ActiveHierarchy,
		HierarchyPath: state.HierarchyPath,
	})
	if err != nil {
		t.Fatalf("SwitchContext back to Sample: %v", err)
	}
	if !slices.ContainsFunc(state.Projects, func(p ProjectInfo) bool {
		return p.Name == "FieldStudy2026" && SameDesktopPath(p.Path, extProjPath)
	}) {
		t.Fatalf("expected attached external project FieldStudy2026 in GetState().Projects, got %+v", state.Projects)
	}

	// 2. Create a multi-SU external database with TWO SU tables (first via custom_new_file, second via existing_db).
	multiSUPath := filepath.Join(extDir, "SharedSUs.db")
	su1, err := svc.CreateWorkspaceResource(ctx, state.ContextID, CreateWorkspaceResourceRequest{
		Kind:            WorkspaceResourceSU,
		Name:            "CoastalUnits",
		DestinationMode: "custom_new_file",
		FilePath:        multiSUPath,
		PopulatePlots:   true,
		SeedFromUserSU:  true,
		Activate:        true,
	})
	if err != nil {
		t.Fatalf("CreateWorkspaceResource(su1): %v", err)
	}
	if su1.RowCount == 0 || su1.State.ActiveSU != "CoastalUnits" {
		t.Fatalf("expected populated & active SU CoastalUnits, got %+v", su1)
	}
	state = su1.State

	su2, err := svc.CreateWorkspaceResource(ctx, state.ContextID, CreateWorkspaceResourceRequest{
		Kind:            WorkspaceResourceSU,
		Name:            "InteriorUnits",
		DestinationMode: "existing_db",
		FilePath:        multiSUPath,
		PopulatePlots:   false,
		Activate:        false,
	})
	if err != nil {
		t.Fatalf("CreateWorkspaceResource(su2 in existing_db): %v", err)
	}
	state = su2.State
	if !slices.ContainsFunc(state.SUs, func(u SUInfo) bool { return u.Name == "CoastalUnits" }) ||
		!slices.ContainsFunc(state.SUs, func(u SUInfo) bool { return u.Name == "InteriorUnits" }) {
		t.Fatalf("expected both multi-SU tables visible in GetState().SUs, got %+v", state.SUs)
	}

	// 3. Create a standalone external Hierarchy .db and activate it.
	extHierPath := filepath.Join(extDir, "RegionalHier.db")
	hierRes, err := svc.CreateWorkspaceResource(ctx, state.ContextID, CreateWorkspaceResourceRequest{
		Kind:            WorkspaceResourceHierarchy,
		Name:            "RegionalHier",
		DestinationMode: "custom_new_file",
		FilePath:        extHierPath,
		Activate:        true,
	})
	if err != nil {
		t.Fatalf("CreateWorkspaceResource(hierarchy): %v", err)
	}
	if !hierRes.Activated || hierRes.State.ActiveHierarchy != "RegionalHier" {
		t.Fatalf("expected RegionalHier active, got %+v", hierRes)
	}
	state = hierRes.State

	// 4. Unattach active SU -> resets ActiveSU to None, removes CoastalUnits from list, retains disk file!
	unSU, err := svc.UnattachWorkspaceResource(ctx, state.ContextID, UnattachWorkspaceResourceRequest{
		Kind: WorkspaceResourceSU,
		Name: "CoastalUnits",
		Path: multiSUPath,
	})
	if err != nil {
		t.Fatalf("UnattachWorkspaceResource(su): %v", err)
	}
	if !unSU.FileRetained {
		t.Fatal("expected FileRetained=true")
	}
	if unSU.State.ActiveSU != "None" {
		t.Fatalf("expected ActiveSU reset to None after unattaching active SU, got %q", unSU.State.ActiveSU)
	}
	if slices.ContainsFunc(unSU.State.SUs, func(u SUInfo) bool { return u.Name == "CoastalUnits" }) {
		t.Fatalf("expected CoastalUnits removed from SUs list, got %+v", unSU.State.SUs)
	}
	if _, err := os.Stat(multiSUPath); err != nil {
		t.Fatalf("disk file must NOT be deleted on unattach: %v", err)
	}
	state = unSU.State

	// 5. Re-attach CoastalUnits from disk file without activating -> appears in SUs list again!
	reAttach, err := svc.AttachWorkspaceResource(ctx, state.ContextID, AttachWorkspaceResourceRequest{
		Kind:     WorkspaceResourceSU,
		Path:     multiSUPath,
		Name:     "CoastalUnits",
		Activate: false,
	})
	if err != nil {
		t.Fatalf("AttachWorkspaceResource(re-attach): %v", err)
	}
	if len(reAttach.Attached) != 1 || reAttach.Attached[0].Name != "CoastalUnits" {
		t.Fatalf("unexpected re-attach result: %+v", reAttach)
	}
	if !slices.ContainsFunc(reAttach.State.SUs, func(u SUInfo) bool { return u.Name == "CoastalUnits" }) {
		t.Fatalf("expected CoastalUnits back in SUs list after re-attach, got %+v", reAttach.State.SUs)
	}
	state = reAttach.State

	// 6. Unattach active Hierarchy -> resets ActiveHierarchy to None, retains disk file!
	unHier, err := svc.UnattachWorkspaceResource(ctx, state.ContextID, UnattachWorkspaceResourceRequest{
		Kind: WorkspaceResourceHierarchy,
		Name: "RegionalHier",
		Path: extHierPath,
	})
	if err != nil {
		t.Fatalf("UnattachWorkspaceResource(hierarchy): %v", err)
	}
	if unHier.State.ActiveHierarchy != "None" {
		t.Fatalf("expected ActiveHierarchy=None, got %q", unHier.State.ActiveHierarchy)
	}
	if _, err := os.Stat(extHierPath); err != nil {
		t.Fatalf("hierarchy disk file must NOT be deleted on unattach: %v", err)
	}
	state = unHier.State

	// 7. Unattach FieldStudy2026 project -> removed from list, disk file preserved.
	unProj, err := svc.UnattachWorkspaceResource(ctx, state.ContextID, UnattachWorkspaceResourceRequest{
		Kind: WorkspaceResourceProject,
		Name: "FieldStudy2026",
		Path: extProjPath,
	})
	if err != nil {
		t.Fatalf("UnattachWorkspaceResource(project): %v", err)
	}
	if slices.ContainsFunc(unProj.State.Projects, func(p ProjectInfo) bool { return p.Name == "FieldStudy2026" }) {
		t.Fatalf("expected FieldStudy2026 removed from Projects list")
	}
	if _, err := os.Stat(extProjPath); err != nil {
		t.Fatalf("project disk file must NOT be deleted on unattach: %v", err)
	}

	// 8. ListWorkspaceResources returns unified list including Sample.
	entries, err := svc.ListWorkspaceResources(ctx, unProj.State.ContextID)
	if err != nil {
		t.Fatalf("ListWorkspaceResources: %v", err)
	}
	if !slices.ContainsFunc(entries, func(e WorkspaceResourceEntry) bool {
		return e.Kind == WorkspaceResourceProject && e.Name == "Sample" && e.Active && e.Managed
	}) {
		t.Fatalf("expected active managed Sample project in ListWorkspaceResources, got %+v", entries)
	}
}

func TestWorkspaceResourcesFailClosedWhenReadOnly(t *testing.T) {
	ctx := context.Background()
	svc, state := openWorkspaceTestContext(t)
	svc.Projects.Sqlite.ReadOnly = true

	if _, err := svc.AttachWorkspaceResource(ctx, state.ContextID, AttachWorkspaceResourceRequest{
		Kind: WorkspaceResourceProject,
		Path: state.ProjectPath,
	}); !errors.Is(err, ErrReadOnlyContext) {
		t.Fatalf("expected AttachWorkspaceResource to fail with ErrReadOnlyContext, got %v", err)
	}
	if _, err := svc.UnattachWorkspaceResource(ctx, state.ContextID, UnattachWorkspaceResourceRequest{
		Kind: WorkspaceResourceProject,
		Name: "Sample",
		Path: state.ProjectPath,
	}); !errors.Is(err, ErrReadOnlyContext) {
		t.Fatalf("expected UnattachWorkspaceResource to fail with ErrReadOnlyContext, got %v", err)
	}
	if _, err := svc.CreateWorkspaceResource(ctx, state.ContextID, CreateWorkspaceResourceRequest{
		Kind: WorkspaceResourceSU,
		Name: "ReadOnlySU",
	}); !errors.Is(err, ErrReadOnlyContext) {
		t.Fatalf("expected CreateWorkspaceResource to fail with ErrReadOnlyContext, got %v", err)
	}
}
