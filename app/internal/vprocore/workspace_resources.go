package vprocore

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"
)

const (
	WorkspaceResourceProject   = "project"
	WorkspaceResourceSU        = "su"
	WorkspaceResourceHierarchy = "hierarchy"
)

type workspaceStoredResource struct {
	Kind string
	Name string
	Path string
}

// WorkspaceResourceEntry describes a project, SU, or hierarchy visible in the unified Work Space.
type WorkspaceResourceEntry struct {
	Kind       string `json:"kind"`
	Name       string `json:"name"`
	Path       string `json:"path"`
	File       string `json:"file"`
	Managed    bool   `json:"managed"`
	Attached   bool   `json:"attached"`
	Compatible bool   `json:"compatible"`
	Active     bool   `json:"active"`
	Available  bool   `json:"available"`
}

// WorkspaceSQLiteInspection describes all Projects, SUs, and Hierarchies discovered inside one SQLite file.
type WorkspaceSQLiteInspection struct {
	SelectedPath string          `json:"selectedPath"`
	Projects     []ProjectInfo   `json:"projects"`
	SUs          []SUInfo        `json:"sus"`
	Hierarchies  []HierarchyInfo `json:"hierarchies"`
}

type AttachWorkspaceResourceRequest struct {
	Kind     string `json:"kind"`
	Path     string `json:"path"`
	Name     string `json:"name,omitempty"`
	Activate bool   `json:"activate,omitempty"`
}

func (r *AttachWorkspaceResourceRequest) UnmarshalJSON(data []byte) error {
	type plain AttachWorkspaceResourceRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type AttachWorkspaceResourceResult struct {
	Kind      string                   `json:"kind"`
	Attached  []WorkspaceResourceEntry `json:"attached"`
	Activated bool                     `json:"activated"`
	Converted bool                     `json:"converted,omitempty"`
	State     ProjectState             `json:"state"`
}

type UnattachWorkspaceResourceRequest struct {
	Kind string `json:"kind"`
	Name string `json:"name"`
	Path string `json:"path,omitempty"`
}

func (r *UnattachWorkspaceResourceRequest) UnmarshalJSON(data []byte) error {
	type plain UnattachWorkspaceResourceRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type UnattachWorkspaceResourceResult struct {
	Kind         string       `json:"kind"`
	Name         string       `json:"name"`
	Path         string       `json:"path"`
	FileRetained bool         `json:"fileRetained"`
	State        ProjectState `json:"state"`
}

type CreateWorkspaceResourceRequest struct {
	Kind            string `json:"kind"`
	Name            string `json:"name"`
	DestinationMode string `json:"destinationMode,omitempty"` // "managed_new_file" | "custom_new_file" | "existing_db" | "active_project"
	FilePath        string `json:"filePath,omitempty"`
	ProjectTitle    string `json:"projectTitle,omitempty"`
	PopulatePlots   bool   `json:"populatePlots,omitempty"`
	SeedFromUserSU  bool   `json:"seedFromUserSu,omitempty"`
	Activate        bool   `json:"activate,omitempty"`
}

func (r *CreateWorkspaceResourceRequest) UnmarshalJSON(data []byte) error {
	type plain CreateWorkspaceResourceRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type CreateWorkspaceResourceResult struct {
	Kind      string       `json:"kind"`
	Name      string       `json:"name"`
	TableName string       `json:"tableName"`
	Path      string       `json:"path"`
	RowCount  int          `json:"rowCount"`
	Activated bool         `json:"activated"`
	State     ProjectState `json:"state"`
}

// ChooseNativeAttachableDatabaseFile opens a native OS file picker accepting both VPro SQLite and Access databases.
func ChooseNativeAttachableDatabaseFile(ctx context.Context, title string) (string, error) {
	if strings.TrimSpace(title) == "" {
		title = "Attach VPro SQLite or Access Database"
	}
	return chooseNativeOpenFileWithFilters(ctx, title, []nativeFileFilter{
		{DisplayName: "VPro & Access Databases (*.db;*.sqlite;*.sqlite3;*.accdb;*.mdb)", Pattern: "*.db;*.sqlite;*.sqlite3;*.accdb;*.mdb"},
		{DisplayName: "VPro SQLite Databases (*.db;*.sqlite;*.sqlite3)", Pattern: "*.db;*.sqlite;*.sqlite3"},
		{DisplayName: "Microsoft Access Databases (*.accdb;*.mdb)", Pattern: "*.accdb;*.mdb"},
	})
}

func normalizeWorkspaceResourceKind(raw string) (string, error) {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case WorkspaceResourceProject:
		return WorkspaceResourceProject, nil
	case WorkspaceResourceSU, "siteunit", "site_unit", "plotlist":
		return WorkspaceResourceSU, nil
	case WorkspaceResourceHierarchy:
		return WorkspaceResourceHierarchy, nil
	default:
		return "", fmt.Errorf("workspace resource kind %q must be \"project\", \"su\", or \"hierarchy\"", raw)
	}
}

func decodeWorkspaceResourceList(raw any) []workspaceStoredResource {
	list, ok := raw.([]any)
	if !ok {
		return nil
	}
	out := make([]workspaceStoredResource, 0, len(list))
	for _, item := range list {
		m, ok := item.(map[string]any)
		if !ok {
			continue
		}
		kindRaw, _ := m["kind"].(string)
		name, _ := m["name"].(string)
		path, _ := m["path"].(string)
		kind, err := normalizeWorkspaceResourceKind(kindRaw)
		if err != nil || strings.TrimSpace(name) == "" || strings.TrimSpace(path) == "" {
			continue
		}
		out = append(out, workspaceStoredResource{
			Kind: kind,
			Name: strings.TrimSpace(name),
			Path: filepath.Clean(strings.TrimSpace(path)),
		})
	}
	return out
}

func encodeWorkspaceResourceList(items []workspaceStoredResource) []any {
	out := make([]any, 0, len(items))
	for _, item := range items {
		out = append(out, map[string]any{
			"kind": item.Kind,
			"name": item.Name,
			"path": item.Path,
		})
	}
	return out
}

func readWorkspaceResourceLists(prefs *DesktopConfig) (attached, detached []workspaceStoredResource, err error) {
	if prefs == nil {
		return nil, nil, nil
	}
	values, err := prefs.Snapshot()
	if err != nil {
		return nil, nil, err
	}
	ws, ok := values["Workspace"].(map[string]any)
	if !ok {
		return nil, nil, nil
	}
	return decodeWorkspaceResourceList(ws["AttachedResources"]),
		decodeWorkspaceResourceList(ws["DetachedResources"]),
		nil
}

func saveWorkspaceResourceLists(prefs *DesktopConfig, attached, detached []workspaceStoredResource) error {
	if prefs == nil {
		return errors.New("desktop configuration is unavailable")
	}
	return prefs.Update("Workspace", map[string]any{
		"AttachedResources": encodeWorkspaceResourceList(attached),
		"DetachedResources": encodeWorkspaceResourceList(detached),
	})
}

func sameWorkspaceStoredResource(a, b workspaceStoredResource) bool {
	return a.Kind == b.Kind && a.Name == b.Name && SameDesktopPath(a.Path, b.Path)
}

func upsertWorkspaceResource(list []workspaceStoredResource, item workspaceStoredResource) []workspaceStoredResource {
	for i := range list {
		if sameWorkspaceStoredResource(list[i], item) {
			list[i] = item
			return list
		}
	}
	return append(list, item)
}

func removeWorkspaceResource(list []workspaceStoredResource, target workspaceStoredResource) []workspaceStoredResource {
	out := make([]workspaceStoredResource, 0, len(list))
	for _, item := range list {
		if sameWorkspaceStoredResource(item, target) {
			continue
		}
		out = append(out, item)
	}
	return out
}

func isManagedWorkspacePath(root, path string) bool {
	if root == "" || path == "" {
		return false
	}
	projectsDir := filepath.Join(root, "projects")
	return SameDesktopPath(filepath.Dir(path), projectsDir)
}

// InspectWorkspaceSQLiteFile inspects a single SQLite file for VP08 Projects, SUs, and Hierarchies.
func InspectWorkspaceSQLiteFile(ctx context.Context, path string) (WorkspaceSQLiteInspection, error) {
	if ctx == nil {
		return WorkspaceSQLiteInspection{}, errors.New("inspecting workspace SQLite file requires a context")
	}
	if err := ctx.Err(); err != nil {
		return WorkspaceSQLiteInspection{}, err
	}
	resolved, err := ExistingDatabasePath(path)
	if err != nil {
		return WorkspaceSQLiteInspection{}, err
	}
	projects, err := InspectFileContext(ctx, resolved)
	if err != nil {
		return WorkspaceSQLiteInspection{}, err
	}
	for i := range projects {
		projects[i].Path = resolved
	}
	sus, err := discoverSUsInFileContext(ctx, resolved)
	if err != nil {
		return WorkspaceSQLiteInspection{}, err
	}
	for i := range sus {
		sus[i].Path = resolved
	}
	hierarchies, err := inspectHierarchiesInFileContext(ctx, resolved)
	if err != nil {
		return WorkspaceSQLiteInspection{}, err
	}
	for i := range hierarchies {
		hierarchies[i].Path = resolved
	}
	return WorkspaceSQLiteInspection{
		SelectedPath: resolved,
		Projects:     projects,
		SUs:          sus,
		Hierarchies:  hierarchies,
	}, nil
}

func discoverSUsInFileContext(ctx context.Context, path string) ([]SUInfo, error) {
	tmpSvc := &ProjectService{}
	return tmpSvc.DiscoverSUsContext(ctx, ProjectInfo{Path: path})
}

func inspectHierarchiesInFileContext(ctx context.Context, path string) ([]HierarchyInfo, error) {
	db, err := sqlutil.OpenReadOnlyContext(ctx, path)
	if err != nil {
		return nil, err
	}
	found, inspectErr := inspectHierarchies(sqlutil.ContextPlotDB{DB: db, Ctx: ctx}, filepath.Base(path))
	closeErr := db.Close()
	if err := errors.Join(inspectErr, closeErr); err != nil {
		return nil, err
	}
	return found, nil
}

// mergeWorkspaceResourcesLocked merges persisted Workspace.AttachedResources into the
// live ProjectState lists and filters out any non-active Workspace.DetachedResources.
func (service *ProjectService) mergeWorkspaceResourcesLocked(
	ctx context.Context,
	selection DesktopSelection,
	projects *[]ProjectInfo,
	sus *[]SUInfo,
	hierarchies *[]HierarchyInfo,
) {
	if service == nil || service.Preferences == nil {
		return
	}
	attached, detached, err := readWorkspaceResourceLists(service.Preferences)
	if err != nil {
		return
	}
	isDetached := func(kind, name, path string) bool {
		if kind == WorkspaceResourceProject && name == selection.Project && SameDesktopPath(path, selection.ProjectPath) {
			return false
		}
		if kind == WorkspaceResourceSU && name == selection.SU && SameDesktopPath(path, selection.SUPath) {
			return false
		}
		if kind == WorkspaceResourceHierarchy && name == selection.Hierarchy && SameDesktopPath(path, selection.HierarchyPath) {
			return false
		}
		target := workspaceStoredResource{Kind: kind, Name: name, Path: path}
		for _, item := range detached {
			if sameWorkspaceStoredResource(item, target) {
				return true
			}
		}
		return false
	}

	if len(detached) > 0 {
		filteredProjects := make([]ProjectInfo, 0, len(*projects))
		for _, p := range *projects {
			if !isDetached(WorkspaceResourceProject, p.Name, p.Path) {
				filteredProjects = append(filteredProjects, p)
			}
		}
		*projects = filteredProjects

		filteredSUs := make([]SUInfo, 0, len(*sus))
		for _, su := range *sus {
			if !isDetached(WorkspaceResourceSU, su.Name, su.Path) {
				filteredSUs = append(filteredSUs, su)
			}
		}
		*sus = filteredSUs

		filteredHierarchies := make([]HierarchyInfo, 0, len(*hierarchies))
		for _, h := range *hierarchies {
			if !isDetached(WorkspaceResourceHierarchy, h.Name, h.Path) {
				filteredHierarchies = append(filteredHierarchies, h)
			}
		}
		*hierarchies = filteredHierarchies
	}

	// Merge attached external resources (gracefully skip missing files without breaking GetState).
	inspected := map[string]WorkspaceSQLiteInspection{}
	for _, entry := range attached {
		if ctx.Err() != nil {
			return
		}
		resolved, pathErr := ExistingDatabasePath(entry.Path)
		if pathErr != nil {
			continue
		}
		info, cached := inspected[resolved]
		if !cached {
			var inspectErr error
			info, inspectErr = InspectWorkspaceSQLiteFile(ctx, resolved)
			if inspectErr != nil {
				continue
			}
			inspected[resolved] = info
		}
		switch entry.Kind {
		case WorkspaceResourceProject:
			for _, p := range info.Projects {
				if p.Name != entry.Name || isDetached(WorkspaceResourceProject, p.Name, p.Path) {
					continue
				}
				if !slices.ContainsFunc(*projects, func(existing ProjectInfo) bool {
					return existing.Name == p.Name && SameDesktopPath(existing.Path, p.Path)
				}) {
					*projects = append(*projects, p)
				}
			}
		case WorkspaceResourceSU:
			for _, su := range info.SUs {
				if su.Name != entry.Name || isDetached(WorkspaceResourceSU, su.Name, su.Path) {
					continue
				}
				if !slices.ContainsFunc(*sus, func(existing SUInfo) bool {
					return existing.Name == su.Name && SameDesktopPath(existing.Path, su.Path)
				}) {
					*sus = append(*sus, su)
				}
			}
		case WorkspaceResourceHierarchy:
			for _, h := range info.Hierarchies {
				if h.Name != entry.Name || isDetached(WorkspaceResourceHierarchy, h.Name, h.Path) {
					continue
				}
				if !slices.ContainsFunc(*hierarchies, func(existing HierarchyInfo) bool {
					return existing.Name == h.Name && SameDesktopPath(existing.Path, h.Path)
				}) {
					*hierarchies = append(*hierarchies, h)
				}
			}
		}
	}

	slices.SortFunc(*projects, func(left, right ProjectInfo) int {
		if order := strings.Compare(left.Name, right.Name); order != 0 {
			return order
		}
		return strings.Compare(left.Path, right.Path)
	})
	slices.SortFunc(*sus, func(left, right SUInfo) int {
		if order := strings.Compare(left.Name, right.Name); order != 0 {
			return order
		}
		return strings.Compare(left.Path, right.Path)
	})
	slices.SortFunc(*hierarchies, func(left, right HierarchyInfo) int {
		if order := strings.Compare(left.Name, right.Name); order != 0 {
			return order
		}
		return strings.Compare(left.Path, right.Path)
	})
}

// ListWorkspaceResources returns all projects, SUs, and hierarchies currently visible in the unified Work Space.
func (s *ContextService) ListWorkspaceResources(ctx context.Context, contextID string) ([]WorkspaceResourceEntry, error) {
	return WithContextPlotRequest(ctx, s, contextID, func(plots *PlotService) ([]WorkspaceResourceEntry, error) {
		state, err := plots.Projects.GetState(ctx)
		if err != nil {
			return nil, err
		}
		attached, _, err := readWorkspaceResourceLists(plots.Projects.Preferences)
		if err != nil {
			return nil, err
		}
		isAttached := func(kind, name, path string) bool {
			target := workspaceStoredResource{Kind: kind, Name: name, Path: path}
			for _, item := range attached {
				if sameWorkspaceStoredResource(item, target) {
					return true
				}
			}
			return false
		}
		entries := make([]WorkspaceResourceEntry, 0, len(state.Projects)+len(state.SUs)+len(state.Hierarchies))
		for _, p := range state.Projects {
			entries = append(entries, WorkspaceResourceEntry{
				Kind:       WorkspaceResourceProject,
				Name:       p.Name,
				Path:       p.Path,
				File:       p.File,
				Managed:    isManagedWorkspacePath(plots.Projects.Root, p.Path),
				Attached:   isAttached(WorkspaceResourceProject, p.Name, p.Path),
				Compatible: p.Compatible,
				Active:     p.Name == state.ActiveProject && SameDesktopPath(p.Path, state.ProjectPath),
				Available:  true,
			})
		}
		for _, su := range state.SUs {
			entries = append(entries, WorkspaceResourceEntry{
				Kind:       WorkspaceResourceSU,
				Name:       su.Name,
				Path:       su.Path,
				File:       filepath.Base(su.Path),
				Managed:    isManagedWorkspacePath(plots.Projects.Root, su.Path),
				Attached:   isAttached(WorkspaceResourceSU, su.Name, su.Path),
				Compatible: su.Compatible,
				Active:     su.Name == state.ActiveSU && SameDesktopPath(su.Path, state.SUPath),
				Available:  true,
			})
		}
		for _, h := range state.Hierarchies {
			entries = append(entries, WorkspaceResourceEntry{
				Kind:       WorkspaceResourceHierarchy,
				Name:       h.Name,
				Path:       h.Path,
				File:       h.File,
				Managed:    isManagedWorkspacePath(plots.Projects.Root, h.Path),
				Attached:   isAttached(WorkspaceResourceHierarchy, h.Name, h.Path),
				Compatible: h.Compatible,
				Active:     h.Name == state.ActiveHierarchy && SameDesktopPath(h.Path, state.HierarchyPath),
				Available:  true,
			})
		}
		// Include any attached external entries whose disk file is currently unreachable so the user can unattach them.
		for _, item := range attached {
			found := slices.ContainsFunc(entries, func(e WorkspaceResourceEntry) bool {
				return e.Kind == item.Kind && e.Name == item.Name && SameDesktopPath(e.Path, item.Path)
			})
			if !found {
				entries = append(entries, WorkspaceResourceEntry{
					Kind:       item.Kind,
					Name:       item.Name,
					Path:       item.Path,
					File:       filepath.Base(item.Path),
					Managed:    isManagedWorkspacePath(plots.Projects.Root, item.Path),
					Attached:   true,
					Compatible: false,
					Active:     false,
					Available:  false,
				})
			}
		}
		return entries, nil
	})
}

// AttachWorkspaceResource attaches one or more compatible Projects, SUs, or Hierarchies from a SQLite file
// into config.yml without moving or copying the disk file, and optionally switches the active context.
func (s *ContextService) AttachWorkspaceResource(ctx context.Context, contextID string, req AttachWorkspaceResourceRequest) (AttachWorkspaceResourceResult, error) {
	kind, err := normalizeWorkspaceResourceKind(req.Kind)
	if err != nil {
		return AttachWorkspaceResourceResult{}, err
	}
	if strings.TrimSpace(req.Path) == "" {
		return AttachWorkspaceResourceResult{}, errors.New("attaching a workspace resource requires a database file path")
	}

	var (
		root      string
		prefs     *DesktopConfig
		curSel    DesktopSelection
		attached  []WorkspaceResourceEntry
		firstName string
		resolved  string
	)
	if _, err := WithContextPlotRequest(ctx, s, contextID, func(plots *PlotService) (struct{}, error) {
		root = plots.Projects.Root
		prefs = plots.Projects.Preferences
		curSel = plots.Projects.Sqlite.Selection
		return struct{}{}, nil
	}); err != nil {
		return AttachWorkspaceResourceResult{}, err
	}

	inspect, err := InspectWorkspaceSQLiteFile(ctx, req.Path)
	if err != nil {
		return AttachWorkspaceResourceResult{}, err
	}
	resolved = inspect.SelectedPath
	requestedName := strings.TrimSpace(req.Name)

	switch kind {
	case WorkspaceResourceProject:
		for _, p := range inspect.Projects {
			if !p.Compatible {
				continue
			}
			if requestedName != "" && p.Name != requestedName {
				continue
			}
			attached = append(attached, WorkspaceResourceEntry{
				Kind:       kind,
				Name:       p.Name,
				Path:       resolved,
				File:       filepath.Base(resolved),
				Managed:    isManagedWorkspacePath(root, resolved),
				Attached:   true,
				Compatible: true,
				Available:  true,
			})
		}
	case WorkspaceResourceSU:
		for _, su := range inspect.SUs {
			if !su.Compatible {
				continue
			}
			if requestedName != "" && su.Name != requestedName {
				continue
			}
			attached = append(attached, WorkspaceResourceEntry{
				Kind:       kind,
				Name:       su.Name,
				Path:       resolved,
				File:       filepath.Base(resolved),
				Managed:    isManagedWorkspacePath(root, resolved),
				Attached:   true,
				Compatible: true,
				Available:  true,
			})
		}
	case WorkspaceResourceHierarchy:
		for _, h := range inspect.Hierarchies {
			if !h.Compatible {
				continue
			}
			if requestedName != "" && h.Name != requestedName {
				continue
			}
			attached = append(attached, WorkspaceResourceEntry{
				Kind:       kind,
				Name:       h.Name,
				Path:       resolved,
				File:       filepath.Base(resolved),
				Managed:    isManagedWorkspacePath(root, resolved),
				Attached:   true,
				Compatible: true,
				Available:  true,
			})
		}
	}

	if len(attached) == 0 {
		if requestedName != "" {
			return AttachWorkspaceResourceResult{}, fmt.Errorf("compatible %s %q was not found in %s", kind, requestedName, filepath.Base(resolved))
		}
		return AttachWorkspaceResourceResult{}, fmt.Errorf("no compatible %s tables were found in %s", kind, filepath.Base(resolved))
	}
	firstName = attached[0].Name

	storedAttached, storedDetached, err := readWorkspaceResourceLists(prefs)
	if err != nil {
		return AttachWorkspaceResourceResult{}, err
	}
	managed := isManagedWorkspacePath(root, resolved)
	for _, entry := range attached {
		item := workspaceStoredResource{Kind: entry.Kind, Name: entry.Name, Path: entry.Path}
		storedDetached = removeWorkspaceResource(storedDetached, item)
		if !managed || entry.Kind == WorkspaceResourceSU {
			// Record external files and standalone SU DBs so they remain visible across projects.
			storedAttached = upsertWorkspaceResource(storedAttached, item)
		}
	}
	if err := saveWorkspaceResourceLists(prefs, storedAttached, storedDetached); err != nil {
		return AttachWorkspaceResourceResult{}, err
	}

	activated := false
	var state ProjectState
	if req.Activate {
		next := ContextSelection{
			Project:       curSel.Project,
			ProjectPath:   curSel.ProjectPath,
			SU:            curSel.SU,
			SUPath:        curSel.SUPath,
			Hierarchy:     curSel.Hierarchy,
			HierarchyPath: curSel.HierarchyPath,
		}
		switch kind {
		case WorkspaceResourceProject:
			next.Project = firstName
			next.ProjectPath = resolved
			next.SU = "None"
			next.SUPath = ""
		case WorkspaceResourceSU:
			next.SU = firstName
			next.SUPath = resolved
		case WorkspaceResourceHierarchy:
			next.Hierarchy = firstName
			next.HierarchyPath = resolved
		}
		state, err = s.SwitchContext(contextID, next)
		if err != nil {
			return AttachWorkspaceResourceResult{}, err
		}
		activated = true
		for i := range attached {
			if attached[i].Name == firstName {
				attached[i].Active = true
			}
		}
	} else {
		state, err = s.Projects.GetState(ctx)
		if err != nil {
			return AttachWorkspaceResourceResult{}, err
		}
	}

	return AttachWorkspaceResourceResult{
		Kind:      kind,
		Attached:  attached,
		Activated: activated,
		State:     state,
	}, nil
}

// UnattachWorkspaceResource removes a Project, SU, or Hierarchy from the workspace list
// WITHOUT deleting or modifying any database file on disk.
func (s *ContextService) UnattachWorkspaceResource(ctx context.Context, contextID string, req UnattachWorkspaceResourceRequest) (UnattachWorkspaceResourceResult, error) {
	kind, err := normalizeWorkspaceResourceKind(req.Kind)
	if err != nil {
		return UnattachWorkspaceResourceResult{}, err
	}
	name := strings.TrimSpace(req.Name)
	if name == "" || strings.EqualFold(name, "None") {
		return UnattachWorkspaceResourceResult{}, errors.New("unattaching a workspace resource requires a valid resource name")
	}

	var (
		root   string
		prefs  *DesktopConfig
		curSel DesktopSelection
		state  ProjectState
	)
	if _, err := WithContextPlotRequest(ctx, s, contextID, func(plots *PlotService) (struct{}, error) {
		root = plots.Projects.Root
		prefs = plots.Projects.Preferences
		curSel = plots.Projects.Sqlite.Selection
		var stateErr error
		state, stateErr = plots.Projects.GetState(ctx)
		return struct{}{}, stateErr
	}); err != nil {
		return UnattachWorkspaceResourceResult{}, err
	}

	targetPath := strings.TrimSpace(req.Path)
	if targetPath == "" {
		switch kind {
		case WorkspaceResourceProject:
			for _, p := range state.Projects {
				if p.Name == name {
					targetPath = p.Path
					break
				}
			}
		case WorkspaceResourceSU:
			for _, su := range state.SUs {
				if su.Name == name {
					targetPath = su.Path
					break
				}
			}
		case WorkspaceResourceHierarchy:
			for _, h := range state.Hierarchies {
				if h.Name == name {
					targetPath = h.Path
					break
				}
			}
		}
	}
	if targetPath == "" {
		storedAttached, _, err := readWorkspaceResourceLists(prefs)
		if err == nil {
			for _, item := range storedAttached {
				if item.Kind == kind && item.Name == name {
					targetPath = item.Path
					break
				}
			}
		}
	}
	if targetPath == "" {
		return UnattachWorkspaceResourceResult{}, fmt.Errorf("%s %q is not currently attached in the workspace", kind, name)
	}
	if abs, absErr := filepath.Abs(targetPath); absErr == nil {
		targetPath = abs
	}

	// If the unattached resource is currently active, switch cleanly away first.
	nextContextID := contextID
	needSwitch := false
	next := ContextSelection{
		Project:       curSel.Project,
		ProjectPath:   curSel.ProjectPath,
		SU:            curSel.SU,
		SUPath:        curSel.SUPath,
		Hierarchy:     curSel.Hierarchy,
		HierarchyPath: curSel.HierarchyPath,
	}
	switch kind {
	case WorkspaceResourceProject:
		if curSel.Project == name && SameDesktopPath(curSel.ProjectPath, targetPath) {
			var fallback ProjectInfo
			for _, p := range state.Projects {
				if !p.Compatible || (p.Name == name && SameDesktopPath(p.Path, targetPath)) {
					continue
				}
				if p.Name == "Sample" {
					fallback = p
					break
				}
				if fallback.Name == "" {
					fallback = p
				}
			}
			if fallback.Name == "" {
				return UnattachWorkspaceResourceResult{}, errors.New("cannot unattach the only remaining active project; attach or create another project first")
			}
			next.Project = fallback.Name
			next.ProjectPath = fallback.Path
			next.SU = "None"
			next.SUPath = ""
			needSwitch = true
		}
	case WorkspaceResourceSU:
		if curSel.SU == name && SameDesktopPath(curSel.SUPath, targetPath) {
			next.SU = "None"
			next.SUPath = ""
			needSwitch = true
		}
	case WorkspaceResourceHierarchy:
		if curSel.Hierarchy == name && SameDesktopPath(curSel.HierarchyPath, targetPath) {
			next.Hierarchy = "None"
			next.HierarchyPath = ""
			needSwitch = true
		}
	}

	storedAttached, storedDetached, err := readWorkspaceResourceLists(prefs)
	if err != nil {
		return UnattachWorkspaceResourceResult{}, err
	}
	item := workspaceStoredResource{Kind: kind, Name: name, Path: targetPath}
	storedAttached = removeWorkspaceResource(storedAttached, item)

	// If this resource is auto-discovered (in <root>/projects or active project DB), mark it detached
	// in config.yml so it is hidden from the workspace list while preserving the file on disk.
	autoDiscovered := isManagedWorkspacePath(root, targetPath) ||
		(kind == WorkspaceResourceSU && SameDesktopPath(targetPath, next.ProjectPath))
	if autoDiscovered {
		storedDetached = upsertWorkspaceResource(storedDetached, item)
	}
	if err := saveWorkspaceResourceLists(prefs, storedAttached, storedDetached); err != nil {
		return UnattachWorkspaceResourceResult{}, err
	}

	if needSwitch {
		state, err = s.SwitchContext(nextContextID, next)
		if err != nil {
			return UnattachWorkspaceResourceResult{}, err
		}
	} else {
		state, err = s.Projects.GetState(ctx)
		if err != nil {
			return UnattachWorkspaceResourceResult{}, err
		}
	}

	return UnattachWorkspaceResourceResult{
		Kind:         kind,
		Name:         name,
		Path:         targetPath,
		FileRetained: true,
		State:        state,
	}, nil
}

func validateNewWorkspaceResourceName(kind, raw string) (string, error) {
	name := strings.TrimSpace(raw)
	if !utf8.ValidString(name) || !ProjectNamePattern.MatchString(name) {
		return "", fmt.Errorf("%s name %q must start with a letter and use only letters, digits, or underscores (max 31 characters)", kind, raw)
	}
	if strings.EqualFold(name, "None") || strings.EqualFold(name, "Sample") || strings.EqualFold(name, "USysSuTableDynamic") {
		return "", fmt.Errorf("%s name %q is reserved and cannot be created", kind, name)
	}
	if kind == WorkspaceResourceProject && strings.Contains(strings.ToLower(name), "master") {
		return "", fmt.Errorf("project name %q cannot contain the reserved word \"master\"", name)
	}
	return name, nil
}

func resolveCreateDestinationMode(kind, mode, filePath string) (string, error) {
	m := strings.ToLower(strings.TrimSpace(mode))
	hasPath := strings.TrimSpace(filePath) != ""
	if m == "" {
		if !hasPath {
			return "managed_new_file", nil
		}
		if info, err := os.Stat(filePath); err == nil && info.Mode().IsRegular() {
			return "existing_db", nil
		}
		return "custom_new_file", nil
	}
	switch m {
	case "managed_new_file", "new_file":
		if hasPath {
			return "custom_new_file", nil
		}
		return "managed_new_file", nil
	case "custom_new_file":
		if !hasPath {
			return "", errors.New("custom_new_file destination mode requires a filePath")
		}
		return "custom_new_file", nil
	case "existing_db":
		if !hasPath {
			return "", errors.New("existing_db destination mode requires a filePath")
		}
		return "existing_db", nil
	case "active_project", "project":
		if kind == WorkspaceResourceProject {
			return "", errors.New("active_project destination mode applies to SUs and hierarchies; use managed_new_file, custom_new_file, or existing_db for projects")
		}
		return "active_project", nil
	default:
		return "", fmt.Errorf("unsupported destinationMode %q", mode)
	}
}

// CreateWorkspaceResource creates a new standalone Project / SU / Hierarchy .db file,
// adds a new table inside an existing multi-SU/multi-hierarchy SQLite database, or creates
// an SU/Hierarchy table inside the currently active project database.
func (s *ContextService) CreateWorkspaceResource(ctx context.Context, contextID string, req CreateWorkspaceResourceRequest) (CreateWorkspaceResourceResult, error) {
	kind, err := normalizeWorkspaceResourceKind(req.Kind)
	if err != nil {
		return CreateWorkspaceResourceResult{}, err
	}
	name, err := validateNewWorkspaceResourceName(kind, req.Name)
	if err != nil {
		return CreateWorkspaceResourceResult{}, err
	}
	mode, err := resolveCreateDestinationMode(kind, req.DestinationMode, req.FilePath)
	if err != nil {
		return CreateWorkspaceResourceResult{}, err
	}
	if err := sqlutil.ValidateUTF16Bound("ProjectTitle", req.ProjectTitle, 255); err != nil {
		return CreateWorkspaceResourceResult{}, err
	}

	var (
		root   string
		prefs  *DesktopConfig
		curSel DesktopSelection
	)
	if _, err := WithContextPlotRequest(ctx, s, contextID, func(plots *PlotService) (struct{}, error) {
		root = plots.Projects.Root
		prefs = plots.Projects.Preferences
		curSel = plots.Projects.Sqlite.Selection
		return struct{}{}, nil
	}); err != nil {
		return CreateWorkspaceResourceResult{}, err
	}

	var (
		destPath  string
		tableName string
		rowCount  int
	)

	switch kind {
	case WorkspaceResourceProject:
		tableName = name + "_Env"
		review, err := s.ReadNewProjectTemplates(ctx, contextID)
		if err != nil {
			return CreateWorkspaceResourceResult{}, err
		}
		ddlPlan, err := PlanNewProjectDDL(ctx, name, review)
		if err != nil {
			return CreateWorkspaceResourceResult{}, err
		}
		destPath, err = createProjectResource(ctx, root, mode, req.FilePath, name, req.ProjectTitle, ddlPlan)
		if err != nil {
			return CreateWorkspaceResourceResult{}, err
		}

	case WorkspaceResourceSU:
		tableName = name + "_SU"
		var seedRows [][2]string
		if req.PopulatePlots {
			seedRows, err = readActiveProjectSUSeedRows(ctx, s, contextID, req.SeedFromUserSU)
			if err != nil {
				return CreateWorkspaceResourceResult{}, err
			}
		}
		destPath, rowCount, err = createSUResource(ctx, root, curSel.ProjectPath, mode, req.FilePath, name, seedRows)
		if err != nil {
			return CreateWorkspaceResourceResult{}, err
		}

	case WorkspaceResourceHierarchy:
		tableName = name + "_Hierarchy"
		destPath, err = createHierarchyResource(ctx, root, curSel.ProjectPath, mode, req.FilePath, name)
		if err != nil {
			return CreateWorkspaceResourceResult{}, err
		}
	}

	// Register in config.yml if external or standalone SU so it stays visible across projects.
	storedAttached, storedDetached, err := readWorkspaceResourceLists(prefs)
	if err != nil {
		return CreateWorkspaceResourceResult{}, err
	}
	item := workspaceStoredResource{Kind: kind, Name: name, Path: destPath}
	storedDetached = removeWorkspaceResource(storedDetached, item)
	if !isManagedWorkspacePath(root, destPath) || (kind == WorkspaceResourceSU && !SameDesktopPath(destPath, curSel.ProjectPath)) {
		storedAttached = upsertWorkspaceResource(storedAttached, item)
	}
	if err := saveWorkspaceResourceLists(prefs, storedAttached, storedDetached); err != nil {
		return CreateWorkspaceResourceResult{}, err
	}

	activated := false
	var state ProjectState
	if req.Activate {
		next := ContextSelection{
			Project:       curSel.Project,
			ProjectPath:   curSel.ProjectPath,
			SU:            curSel.SU,
			SUPath:        curSel.SUPath,
			Hierarchy:     curSel.Hierarchy,
			HierarchyPath: curSel.HierarchyPath,
		}
		switch kind {
		case WorkspaceResourceProject:
			next.Project = name
			next.ProjectPath = destPath
			next.SU = "None"
			next.SUPath = ""
		case WorkspaceResourceSU:
			next.SU = name
			next.SUPath = destPath
		case WorkspaceResourceHierarchy:
			next.Hierarchy = name
			next.HierarchyPath = destPath
		}
		state, err = s.SwitchContext(contextID, next)
		if err != nil {
			return CreateWorkspaceResourceResult{}, err
		}
		activated = true
	} else {
		state, err = s.Projects.GetState(ctx)
		if err != nil {
			return CreateWorkspaceResourceResult{}, err
		}
	}

	return CreateWorkspaceResourceResult{
		Kind:      kind,
		Name:      name,
		TableName: tableName,
		Path:      destPath,
		RowCount:  rowCount,
		Activated: activated,
		State:     state,
	}, nil
}

func ensureDBExtension(path string) string {
	trimmed := strings.TrimSpace(path)
	if trimmed == "" {
		return ""
	}
	if !strings.EqualFold(filepath.Ext(trimmed), ".db") {
		return trimmed + ".db"
	}
	return trimmed
}

func writeNewSQLiteFileAtomically(ctx context.Context, destPath, label string, populate func(tx *sql.Tx) error) (string, error) {
	resolvedDest, _, err := FreshSQLiteDestination(destPath, label)
	if err != nil {
		return "", err
	}
	tmpFile, err := os.CreateTemp(filepath.Dir(resolvedDest), ".vpro-create-*.db")
	if err != nil {
		return "", err
	}
	tmpPath := tmpFile.Name()
	published := false
	defer func() {
		if !published {
			_ = sqlutil.RemoveSQLiteWithSidecars(tmpPath)
		}
	}()
	if err := tmpFile.Chmod(0o600); err != nil {
		_ = tmpFile.Close()
		return "", err
	}
	if err := tmpFile.Close(); err != nil {
		return "", err
	}
	db, err := sqlutil.OpenStagedSQLite(tmpPath, sqlutil.StagedSQLiteOptions{ImmediateTxLock: true})
	if err != nil {
		return "", err
	}
	tx, err := sqlutil.BeginStagedTx(ctx, db)
	if err != nil {
		_ = db.Close()
		return "", err
	}
	if err := populate(tx); err != nil {
		_ = tx.Rollback()
		_ = db.Close()
		return "", err
	}
	if err := tx.Commit(); err != nil {
		_ = db.Close()
		return "", err
	}
	if err := db.Close(); err != nil {
		return "", err
	}
	if err := sqlutil.LinkOrCreateExclusive(tmpPath, resolvedDest); err != nil {
		return "", fmt.Errorf("publish %s database %q: %w", label, resolvedDest, err)
	}
	published = true
	_ = sqlutil.RemoveSQLiteWithSidecars(tmpPath)
	if err := InitializeSQLiteWAL(ctx, resolvedDest); err != nil {
		return "", err
	}
	return resolvedDest, nil
}

func execInExistingSQLiteTx(ctx context.Context, path string, mutate func(tx *sql.Tx) error) (string, error) {
	resolved, err := ExistingDatabasePath(path)
	if err != nil {
		return "", err
	}
	db, err := sqlutil.OpenImmediateWriteSQLite(resolved)
	if err != nil {
		return "", err
	}
	defer db.Close()
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return "", err
	}
	if err := mutate(tx); err != nil {
		_ = tx.Rollback()
		return "", err
	}
	if err := tx.Commit(); err != nil {
		return "", err
	}
	return resolved, nil
}

func createProjectResource(ctx context.Context, root, mode, filePath, projectName, projectTitle string, ddlPlan *newProjectDDLPlan) (string, error) {
	populate := func(tx *sql.Tx) error {
		for _, tblPlan := range ddlPlan.Tables {
			var collision int
			if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM sqlite_master WHERE name = ? COLLATE NOCASE`, tblPlan.TargetTable).Scan(&collision); err != nil {
				return err
			}
			if collision != 0 {
				return fmt.Errorf("table %s already exists in target database", tblPlan.TargetTable)
			}
			for _, mapping := range tblPlan.Schema {
				if mapping.SQL != nil {
					if _, err := tx.ExecContext(ctx, *mapping.SQL); err != nil {
						return fmt.Errorf("create %s: %w", tblPlan.TargetTable, err)
					}
				}
			}
		}
		if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS "_table_metadata" ("table_name" TEXT PRIMARY KEY, "description" TEXT)`); err != nil {
			return err
		}
		for _, suffix := range CoreTables {
			if _, err := tx.ExecContext(ctx, `INSERT OR REPLACE INTO "_table_metadata" ("table_name", "description") VALUES (?, 'VP08')`, projectName+"_"+suffix); err != nil {
				return err
			}
		}
		if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS "__VPRO_ChildIdentity" ("TableName" TEXT PRIMARY KEY, "LastID" INTEGER NOT NULL)`); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO "__VPRO_ChildIdentity" ("TableName", "LastID") VALUES (?, 1) ON CONFLICT("TableName") DO UPDATE SET "LastID" = MAX("LastID", 1)`, projectName+"_Metadata"); err != nil {
			return err
		}
		projectID := sqlutil.TruncateUTF16(projectName, 20)
		now := time.Now().Format("2006-01-02 15:04:05")
		metaTable := QuoteHeaderIdentifier(projectName + "_Metadata")
		if strings.TrimSpace(projectTitle) != "" {
			if _, err := tx.ExecContext(ctx, `INSERT INTO `+metaTable+` ("ID", "ProjectID", "ProjectTitle", "DateLastEdited") VALUES (1, ?, ?, ?)`, projectID, strings.TrimSpace(projectTitle), now); err != nil {
				return err
			}
		} else {
			if _, err := tx.ExecContext(ctx, `INSERT INTO `+metaTable+` ("ID", "ProjectID", "DateLastEdited") VALUES (1, ?, ?)`, projectID, now); err != nil {
				return err
			}
		}
		return nil
	}

	switch mode {
	case "managed_new_file":
		return writeNewSQLiteFileAtomically(ctx, filepath.Join(root, "projects", projectName+".db"), "Project", populate)
	case "custom_new_file":
		return writeNewSQLiteFileAtomically(ctx, ensureDBExtension(filePath), "Project", populate)
	case "existing_db":
		return execInExistingSQLiteTx(ctx, filePath, populate)
	default:
		return "", fmt.Errorf("unsupported project creation mode %q", mode)
	}
}

func readActiveProjectSUSeedRows(ctx context.Context, s *ContextService, contextID string, seedFromUserSU bool) ([][2]string, error) {
	return WithContextPlotRequest(ctx, s, contextID, func(plots *PlotService) ([][2]string, error) {
		owner := plots.Projects.Sqlite
		unlock, err := owner.AcquireMutex(ctx)
		if err != nil {
			return nil, err
		}
		defer unlock()
		tx, err := owner.BeginReadSnapshot(ctx)
		if err != nil {
			return nil, err
		}
		defer tx.Rollback()

		envTable := QuoteHeaderIdentifier(owner.Selection.Project + "_Env")
		adminTable := QuoteHeaderIdentifier(owner.Selection.Project + "_Admin")
		var query string
		if seedFromUserSU {
			query = `SELECT e.PlotNumber, COALESCE(NULLIF(TRIM(a.UserSiteUnit), ''), NULLIF(TRIM(e.SiteSeries), ''), '') ` +
				`FROM "project".` + envTable + ` e ` +
				`LEFT JOIN "project".` + adminTable + ` a ON typeof(a.Plot)='text' AND typeof(e.PlotNumber)='text' AND CAST(a.Plot AS BLOB)=CAST(e.PlotNumber AS BLOB) ` +
				`WHERE typeof(e.PlotNumber)='text' AND TRIM(e.PlotNumber) <> '' ORDER BY e.PlotNumber`
		} else {
			query = `SELECT PlotNumber, '' FROM "project".` + envTable + ` WHERE typeof(PlotNumber)='text' AND TRIM(PlotNumber) <> '' ORDER BY PlotNumber`
		}
		rows, err := tx.QueryContext(ctx, query)
		if err != nil {
			return nil, err
		}
		defer rows.Close()
		out := make([][2]string, 0)
		seen := map[string]bool{}
		for rows.Next() {
			var plot, unit string
			if err := rows.Scan(&plot, &unit); err != nil {
				return nil, err
			}
			if seen[plot] {
				continue
			}
			seen[plot] = true
			out = append(out, [2]string{plot, unit})
		}
		if err := rows.Err(); err != nil {
			return nil, err
		}
		return out, tx.Commit()
	})
}

func createSUResource(ctx context.Context, root, activeProjectPath, mode, filePath, suName string, seedRows [][2]string) (string, int, error) {
	tableName := suName + "_SU"
	inserted := 0
	populate := func(tx *sql.Tx) error {
		var collision int
		if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM sqlite_master WHERE name = ? COLLATE NOCASE`, tableName).Scan(&collision); err != nil {
			return err
		}
		if collision != 0 {
			return fmt.Errorf("SU table %s already exists in target database", tableName)
		}
		qTable := QuoteHeaderIdentifier(tableName)
		qUniq := QuoteHeaderIdentifier("uidx_" + tableName + "_PlotNumber")
		qIdx := QuoteHeaderIdentifier("idx_" + tableName + "_SiteUnit")
		if _, err := tx.ExecContext(ctx, `CREATE TABLE `+qTable+` ("PlotNumber" VARCHAR, "SiteUnit" VARCHAR)`); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `CREATE UNIQUE INDEX `+qUniq+` ON `+qTable+` ("PlotNumber")`); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `CREATE INDEX `+qIdx+` ON `+qTable+` ("SiteUnit")`); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS "_table_metadata" ("table_name" TEXT PRIMARY KEY, "description" TEXT)`); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `INSERT OR REPLACE INTO "_table_metadata" ("table_name", "description") VALUES (?, 'VP04')`, tableName); err != nil {
			return err
		}
		for _, pair := range seedRows {
			var suVal any
			if strings.TrimSpace(pair[1]) != "" {
				suVal = pair[1]
			}
			if _, err := tx.ExecContext(ctx, `INSERT INTO `+qTable+` ("PlotNumber", "SiteUnit") VALUES (?, ?)`, pair[0], suVal); err != nil {
				return err
			}
			inserted++
		}
		return nil
	}

	var dest string
	var err error
	switch mode {
	case "managed_new_file":
		dest, err = writeNewSQLiteFileAtomically(ctx, filepath.Join(root, "projects", suName+"_SU.db"), "Site Unit", populate)
	case "custom_new_file":
		dest, err = writeNewSQLiteFileAtomically(ctx, ensureDBExtension(filePath), "Site Unit", populate)
	case "existing_db":
		dest, err = execInExistingSQLiteTx(ctx, filePath, populate)
	case "active_project":
		dest, err = execInExistingSQLiteTx(ctx, activeProjectPath, populate)
	default:
		return "", 0, fmt.Errorf("unsupported SU creation mode %q", mode)
	}
	return dest, inserted, err
}

func createHierarchyResource(ctx context.Context, root, activeProjectPath, mode, filePath, hierName string) (string, error) {
	tableName := hierName + "_Hierarchy"
	populate := func(tx *sql.Tx) error {
		var collision int
		if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM sqlite_master WHERE name = ? COLLATE NOCASE`, tableName).Scan(&collision); err != nil {
			return err
		}
		if collision != 0 {
			return fmt.Errorf("hierarchy table %s already exists in target database", tableName)
		}
		qTable := QuoteHeaderIdentifier(tableName)
		if _, err := tx.ExecContext(ctx, `CREATE TABLE `+qTable+` (
			"ID" INTEGER PRIMARY KEY,
			"Name" VARCHAR NOT NULL,
			"Parent" INTEGER,
			"Level" SMALLINT,
			"Tag" VARCHAR,
			"MyOrder" VARCHAR,
			"ChildID" SMALLINT,
			"StartChild" SMALLINT,
			"LastChild" SMALLINT,
			"Flag" BOOLEAN
		)`); err != nil {
			return err
		}
		for _, idx := range []struct {
			unique bool
			name   string
			col    string
		}{
			{true, "uidx_" + tableName + "_Name", "Name"},
			{false, "idx_" + tableName + "_Parent", "Parent"},
			{false, "idx_" + tableName + "_Level", "Level"},
			{false, "idx_" + tableName + "_ChildID", "ChildID"},
		} {
			kw := "CREATE INDEX "
			if idx.unique {
				kw = "CREATE UNIQUE INDEX "
			}
			if _, err := tx.ExecContext(ctx, kw+QuoteHeaderIdentifier(idx.name)+" ON "+qTable+" ("+QuoteHeaderIdentifier(idx.col)+")"); err != nil {
				return err
			}
		}
		if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS "_table_metadata" ("table_name" TEXT PRIMARY KEY, "description" TEXT)`); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `INSERT OR REPLACE INTO "_table_metadata" ("table_name", "description") VALUES (?, 'VP04')`, tableName); err != nil {
			return err
		}
		return nil
	}

	switch mode {
	case "managed_new_file":
		return writeNewSQLiteFileAtomically(ctx, filepath.Join(root, "projects", hierName+"_Hierarchy.db"), "Hierarchy", populate)
	case "custom_new_file":
		return writeNewSQLiteFileAtomically(ctx, ensureDBExtension(filePath), "Hierarchy", populate)
	case "existing_db":
		return execInExistingSQLiteTx(ctx, filePath, populate)
	case "active_project":
		return execInExistingSQLiteTx(ctx, activeProjectPath, populate)
	default:
		return "", fmt.Errorf("unsupported hierarchy creation mode %q", mode)
	}
}
