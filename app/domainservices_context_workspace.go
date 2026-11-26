package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/boostao/vpro/app/internal/interchange"
	vprocorepkg "github.com/boostao/vpro/app/internal/vprocore"
)

type WorkspaceResourceEntry = vprocorepkg.WorkspaceResourceEntry
type AttachWorkspaceResourceRequest = vprocorepkg.AttachWorkspaceResourceRequest
type AttachWorkspaceResourceResult = vprocorepkg.AttachWorkspaceResourceResult
type UnattachWorkspaceResourceRequest = vprocorepkg.UnattachWorkspaceResourceRequest
type UnattachWorkspaceResourceResult = vprocorepkg.UnattachWorkspaceResourceResult
type CreateWorkspaceResourceRequest = vprocorepkg.CreateWorkspaceResourceRequest
type CreateWorkspaceResourceResult = vprocorepkg.CreateWorkspaceResourceResult

// AttachableFileInspection unifies SQLite (.db/.sqlite/.sqlite3) and Microsoft Access
// (.accdb/.mdb) inspection for the unified Work Space Attach dialog.
type AttachableFileInspection struct {
	SelectedPath     string                                `json:"selectedPath"`
	FileKind         string                                `json:"fileKind"` // "sqlite" | "access"
	RequiresConvert  bool                                  `json:"requiresConvert"`
	Projects         []vprocorepkg.ProjectInfo             `json:"projects"`
	SUs              []vprocorepkg.SUInfo                  `json:"sus"`
	Hierarchies      []vprocorepkg.HierarchyInfo           `json:"hierarchies"`
	AccessInspection *interchange.AccessDatabaseInspection `json:"accessInspection,omitempty"`
}

func isAccessDatabaseFile(path string) bool {
	ext := strings.ToLower(strings.TrimSpace(filepath.Ext(path)))
	return ext == ".accdb" || ext == ".mdb"
}

// ChooseAttachableFile opens a native OS file picker accepting VPro SQLite and Access databases.
func (s *ContextService) ChooseAttachableFile(ctx context.Context, contextID, kind string) (string, error) {
	if err := requireContextArg(ctx); err != nil {
		return "", err
	}
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return "", errors.New("project context is unavailable")
	}
	if _, err := vprocorepkg.WithContextPlotRequest(ctx, s.core, contextID, func(*vprocorepkg.PlotService) (struct{}, error) {
		return struct{}{}, nil
	}); err != nil {
		return "", err
	}
	title := "Attach VPro SQLite or Access Database"
	switch strings.ToLower(strings.TrimSpace(kind)) {
	case vprocorepkg.WorkspaceResourceProject:
		title = "Attach Project Database (.db, .accdb, .mdb)"
	case vprocorepkg.WorkspaceResourceSU:
		title = "Attach Site Unit Database (.db, .accdb, .mdb)"
	case vprocorepkg.WorkspaceResourceHierarchy:
		title = "Attach Hierarchy Database (.db, .accdb, .mdb)"
	}
	return vprocorepkg.ChooseNativeAttachableDatabaseFile(ctx, title)
}

// InspectAttachableFile inspects a SQLite (.db/.sqlite/.sqlite3) or Microsoft Access
// (.accdb/.mdb) file to list attachable Projects, SUs, and Hierarchies without mutating disk files.
func (s *ContextService) InspectAttachableFile(ctx context.Context, contextID, path string) (AttachableFileInspection, error) {
	if err := requireContextArg(ctx); err != nil {
		return AttachableFileInspection{}, err
	}
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return AttachableFileInspection{}, errors.New("project context is unavailable")
	}
	trimmed := strings.TrimSpace(path)
	if trimmed == "" {
		return AttachableFileInspection{}, errors.New("inspecting an attachable file requires a file path")
	}
	if isAccessDatabaseFile(trimmed) {
		insp, err := interchange.InspectAccessDatabase(s.core, withWailsAccessImportProgress(ctx, contextID, "inspect"), contextID, trimmed)
		if err != nil {
			return AttachableFileInspection{}, sanitizeImportExportError(err)
		}
		projects := make([]vprocorepkg.ProjectInfo, 0, len(insp.Projects))
		sus := make([]vprocorepkg.SUInfo, 0)
		for _, cand := range insp.Projects {
			projects = append(projects, vprocorepkg.ProjectInfo{
				Name:       cand.SourceProject,
				File:       filepath.Base(insp.SourcePath),
				Version:    cand.SourceVersion,
				Compatible: cand.Compatible,
				Path:       insp.SourcePath,
			})
			for _, suName := range cand.OptionalSUs {
				sus = append(sus, vprocorepkg.SUInfo{
					Name:       suName,
					Kind:       "ordinary",
					Compatible: true,
					Path:       insp.SourcePath,
				})
			}
		}
		return AttachableFileInspection{
			SelectedPath:     insp.SourcePath,
			FileKind:         "access",
			RequiresConvert:  true,
			Projects:         projects,
			SUs:              sus,
			Hierarchies:      []vprocorepkg.HierarchyInfo{},
			AccessInspection: &insp,
		}, nil
	}

	if _, err := vprocorepkg.WithContextPlotRequest(ctx, s.core, contextID, func(*vprocorepkg.PlotService) (struct{}, error) {
		return struct{}{}, nil
	}); err != nil {
		return AttachableFileInspection{}, err
	}
	sqlInsp, err := vprocorepkg.InspectWorkspaceSQLiteFile(ctx, trimmed)
	if err != nil {
		return AttachableFileInspection{}, sanitizeImportExportError(err)
	}
	return AttachableFileInspection{
		SelectedPath:    sqlInsp.SelectedPath,
		FileKind:        "sqlite",
		RequiresConvert: false,
		Projects:        sqlInsp.Projects,
		SUs:             sqlInsp.SUs,
		Hierarchies:     sqlInsp.Hierarchies,
	}, nil
}

// ListWorkspaceResources returns all managed and attached Projects, SUs, and Hierarchies.
func (s *ContextService) ListWorkspaceResources(ctx context.Context, contextID string) ([]WorkspaceResourceEntry, error) {
	if err := requireContextArg(ctx); err != nil {
		return nil, err
	}
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("project context is unavailable")
	}
	return s.core.ListWorkspaceResources(ctx, contextID)
}

// AttachWorkspaceResource attaches a SQLite Project, SU, or Hierarchy into the workspace.
// When given a Microsoft Access (.accdb/.mdb) database, it automatically converts the
// Access database to a clean VP08 SQLite .db file via interchange before attaching.
func (s *ContextService) AttachWorkspaceResource(ctx context.Context, contextID string, req AttachWorkspaceResourceRequest) (AttachWorkspaceResourceResult, error) {
	if err := requireContextArg(ctx); err != nil {
		return AttachWorkspaceResourceResult{}, err
	}
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return AttachWorkspaceResourceResult{}, errors.New("project context is unavailable")
	}
	if !isAccessDatabaseFile(req.Path) {
		return s.core.AttachWorkspaceResource(ctx, contextID, req)
	}

	// Auto-convert Access .accdb/.mdb -> SQLite VP08 .db via Layer-2 interchange.
	insp, err := interchange.InspectAccessDatabase(s.core, withWailsAccessImportProgress(ctx, contextID, "inspect"), contextID, req.Path)
	if err != nil {
		return AttachWorkspaceResourceResult{}, sanitizeImportExportError(err)
	}
	var chosen *interchange.AccessProjectCandidate
	requestedName := strings.TrimSpace(req.Name)
	for i := range insp.Projects {
		cand := &insp.Projects[i]
		if !cand.Compatible {
			continue
		}
		if requestedName == "" || cand.SourceProject == requestedName || cand.SuggestedTarget == requestedName {
			chosen = cand
			break
		}
	}
	if chosen == nil {
		return AttachWorkspaceResourceResult{}, errors.New("no compatible VPro project was found inside the selected Access database")
	}

	targetName := chosen.SuggestedTarget
	if targetName == "" {
		targetName = chosen.SourceProject
	}
	destPath := chosen.SuggestedDestPath
	if destPath != "" {
		if _, statErr := os.Stat(destPath); statErr == nil {
			// Avoid colliding with an already-converted database by appending a numeric suffix.
			base := strings.TrimSuffix(destPath, filepath.Ext(destPath))
			for suffix := 2; suffix < 100; suffix++ {
				candName := fmt.Sprintf("%s_%d", targetName, suffix)
				if len(candName) > 31 {
					candName = fmt.Sprintf("%s_%d", targetName[:28], suffix)
				}
				candDest := fmt.Sprintf("%s_%d.db", base, suffix)
				if _, err := os.Stat(candDest); errors.Is(err, os.ErrNotExist) {
					targetName = candName
					destPath = candDest
					break
				}
			}
		}
	}

	importRes, err := interchange.ImportAccessProject(s.core, withWailsAccessImportProgress(ctx, contextID, "import"), contextID, interchange.AccessProjectImportRequest{
		SourcePath:        insp.SourcePath,
		SourceProject:     chosen.SourceProject,
		TargetProject:     targetName,
		DestinationPath:   destPath,
		ActivateOnSuccess: false,
	})
	if err != nil {
		return AttachWorkspaceResourceResult{}, sanitizeImportExportError(err)
	}

	attachName := importRes.TargetProject
	attachKind := strings.ToLower(strings.TrimSpace(req.Kind))
	if attachKind == "" {
		attachKind = vprocorepkg.WorkspaceResourceProject
	}
	if attachKind == vprocorepkg.WorkspaceResourceSU {
		if requestedName != "" {
			attachName = requestedName
		} else if len(importRes.ImportedSUs) > 0 {
			attachName = importRes.ImportedSUs[0]
		} else {
			attachName = ""
		}
	}
	res, err := s.core.AttachWorkspaceResource(ctx, contextID, AttachWorkspaceResourceRequest{
		Kind:     attachKind,
		Path:     importRes.DestinationPath,
		Name:     attachName,
		Activate: req.Activate,
	})
	if err != nil {
		return AttachWorkspaceResourceResult{}, err
	}
	res.Converted = true
	return res, nil
}

// UnattachWorkspaceResource removes a Project, SU, or Hierarchy from the workspace list
// without deleting its SQLite file on disk.
func (s *ContextService) UnattachWorkspaceResource(ctx context.Context, contextID string, req UnattachWorkspaceResourceRequest) (UnattachWorkspaceResourceResult, error) {
	if err := requireContextArg(ctx); err != nil {
		return UnattachWorkspaceResourceResult{}, err
	}
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return UnattachWorkspaceResourceResult{}, errors.New("project context is unavailable")
	}
	return s.core.UnattachWorkspaceResource(ctx, contextID, req)
}

// CreateWorkspaceResource creates a new standalone Project / SU / Hierarchy .db file
// or adds a new SU / Hierarchy table inside an existing multi-SU SQLite database.
func (s *ContextService) CreateWorkspaceResource(ctx context.Context, contextID string, req CreateWorkspaceResourceRequest) (CreateWorkspaceResourceResult, error) {
	if err := requireContextArg(ctx); err != nil {
		return CreateWorkspaceResourceResult{}, err
	}
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return CreateWorkspaceResourceResult{}, errors.New("project context is unavailable")
	}
	return s.core.CreateWorkspaceResource(ctx, contextID, req)
}

func (s *ContextService) GetSpreadsheetAppPreference(ctx context.Context, contextID string) (SpreadsheetAppPreference, error) {
	if err := requireContextArg(ctx); err != nil {
		return SpreadsheetAppPreference{}, err
	}
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return SpreadsheetAppPreference{}, errors.New("project context is unavailable")
	}
	return s.core.GetSpreadsheetAppPreference(ctx, contextID)
}

func (s *ContextService) SetSpreadsheetAppPreference(ctx context.Context, contextID string, pref SpreadsheetAppPreference) (SpreadsheetAppPreference, error) {
	if err := requireContextArg(ctx); err != nil {
		return SpreadsheetAppPreference{}, err
	}
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return SpreadsheetAppPreference{}, errors.New("project context is unavailable")
	}
	return s.core.SetSpreadsheetAppPreference(ctx, contextID, pref)
}

func (s *ContextService) OpenReportInSpreadsheet(ctx context.Context, contextID, filePath string) error {
	if err := requireContextArg(ctx); err != nil {
		return err
	}
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return errors.New("project context is unavailable")
	}
	return s.core.OpenReportInSpreadsheet(ctx, contextID, filePath)
}
