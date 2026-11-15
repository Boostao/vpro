package vprocore

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/boostao/vpro/app/internal/sqlutil"
)

func (service *ProjectService) discover() ([]ProjectInfo, []ProjectDiagnostic, error) {
	return service.DiscoverContext(context.Background())
}

func (service *ProjectService) DiscoverContext(ctx context.Context) ([]ProjectInfo, []ProjectDiagnostic, error) {
	if err := ctx.Err(); err != nil {
		return nil, nil, err
	}
	files, err := os.ReadDir(filepath.Join(service.Root, "projects"))
	if err != nil {
		return nil, nil, err
	}
	projects := []ProjectInfo{}
	diagnostics := []ProjectDiagnostic{}
	for _, file := range files {
		if err := ctx.Err(); err != nil {
			return nil, nil, err
		}
		if !file.Type().IsRegular() || !strings.EqualFold(filepath.Ext(file.Name()), ".db") {
			continue
		}
		found, err := InspectFileContext(ctx, filepath.Join(service.Root, "projects", file.Name()))
		if err != nil {
			if ctx.Err() != nil && errors.Is(err, ctx.Err()) {
				return nil, nil, ctx.Err()
			}
			if file.Name() == "Sample.db" {
				return nil, nil, sqlutil.LabelledReadError("inspect "+file.Name(), err)
			}
			diagnostics = append(diagnostics, ProjectDiagnostic{File: file.Name(), Message: err.Error()})
			continue
		}
		projects = append(projects, found...)
	}
	slices.SortFunc(projects, func(left, right ProjectInfo) int { return strings.Compare(left.Name, right.Name) })
	for index := 1; index < len(projects); index++ {
		if projects[index].Name == projects[index-1].Name {
			return nil, nil, fmt.Errorf("duplicate project family %q", projects[index].Name)
		}
	}
	if err := ctx.Err(); err != nil {
		return nil, nil, err
	}
	return projects, diagnostics, nil
}

func (service *ProjectService) GetState(ctx context.Context) (ProjectState, error) {
	if err := sqlutil.AcquireReadLease(ctx, &service.Mu); err != nil {
		return ProjectState{}, err
	}
	defer service.Mu.RUnlock()
	if service.Sqlite != nil {
		return service.SqliteStateContextLocked(ctx)
	}
	projects, diagnostics, err := service.DiscoverContext(ctx)
	if err != nil {
		return ProjectState{}, err
	}
	active := service.Active
	activeSU := service.ActiveSU
	activeHierarchy := service.activeHierarchy
	hierarchyFile := service.hierarchyFile
	selected := CompatibleProject(projects, active)
	if selected.Name == "" {
		return ProjectState{}, errors.New("no compatible project is active")
	}
	sus, err := service.DiscoverSUsContext(ctx, selected)
	if err != nil {
		return ProjectState{}, err
	}
	hierarchies, err := DiscoverHierarchiesContext(ctx, filepath.Join(service.Root, "projects"))
	if err != nil {
		return ProjectState{}, err
	}
	return ProjectState{ActiveProject: active, ActiveSU: activeSU, ActiveHierarchy: activeHierarchy, HierarchyFile: hierarchyFile, Projects: projects, SUs: sus, Hierarchies: hierarchies, Diagnostics: diagnostics}, nil
}

func (service *ProjectService) SelectProject(name string) (ProjectState, error) {
	service.Mu.Lock()
	if service.Sqlite != nil {
		defer service.Mu.Unlock()
		return ProjectState{}, errors.New("use an identity-bound context switch for the active SQLite application")
	}
	service.Mu.Unlock()
	if !ProjectNamePattern.MatchString(name) {
		return ProjectState{}, errors.New("invalid VPRO project name")
	}
	projects, diagnostics, err := service.discover()
	if err != nil {
		return ProjectState{}, err
	}
	if !hasCompatible(projects, name) {
		return ProjectState{}, fmt.Errorf("project %q is not a complete VP08 family", name)
	}
	sus, err := service.discoverSUs(CompatibleProject(projects, name))
	if err != nil {
		return ProjectState{}, err
	}
	hierarchies, err := discoverHierarchies(filepath.Join(service.Root, "projects"))
	if err != nil {
		return ProjectState{}, err
	}
	service.Mu.Lock()
	defer service.Mu.Unlock()
	if err := service.saveSelection(name, "None"); err != nil {
		return ProjectState{}, err
	}
	service.Active = name
	service.ActiveSU = "None"
	return ProjectState{ActiveProject: name, ActiveSU: "None", ActiveHierarchy: service.activeHierarchy, HierarchyFile: service.hierarchyFile, Projects: projects, SUs: sus, Hierarchies: hierarchies, Diagnostics: diagnostics}, nil
}

func (service *ProjectService) SelectSU(name string) (ProjectState, error) {
	service.Mu.Lock()
	if service.Sqlite != nil {
		defer service.Mu.Unlock()
		return ProjectState{}, errors.New("use an identity-bound context switch for the active SQLite application")
	}
	service.Mu.Unlock()
	if name != "None" && !ProjectNamePattern.MatchString(name) {
		return ProjectState{}, errors.New("invalid VPRO SU name")
	}
	projects, diagnostics, err := service.discover()
	if err != nil {
		return ProjectState{}, err
	}
	service.Mu.Lock()
	defer service.Mu.Unlock()
	selected := CompatibleProject(projects, service.Active)
	if selected.Name == "" {
		return ProjectState{}, errors.New("no compatible project is active")
	}
	sus, err := service.discoverSUs(selected)
	if err != nil {
		return ProjectState{}, err
	}
	hierarchies, err := discoverHierarchies(filepath.Join(service.Root, "projects"))
	if err != nil {
		return ProjectState{}, err
	}
	if name != "None" && !hasCompatibleSU(sus, name) {
		return ProjectState{}, fmt.Errorf("SU %q is not an available, authorized site unit in this project file", name)
	}
	if err := service.saveSelection(service.Active, name); err != nil {
		return ProjectState{}, err
	}
	service.ActiveSU = name
	return ProjectState{ActiveProject: service.Active, ActiveSU: name, ActiveHierarchy: service.activeHierarchy, HierarchyFile: service.hierarchyFile, Projects: projects, SUs: sus, Hierarchies: hierarchies, Diagnostics: diagnostics}, nil
}

func (service *ProjectService) SelectHierarchy(name, file string) (ProjectState, error) {
	service.Mu.Lock()
	if service.Sqlite != nil {
		defer service.Mu.Unlock()
		return ProjectState{}, errors.New("use an identity-bound context switch for the active SQLite application")
	}
	service.Mu.Unlock()
	if name != "None" && !ProjectNamePattern.MatchString(name) {
		return ProjectState{}, errors.New("invalid VPRO hierarchy name")
	}
	projects, diagnostics, err := service.discover()
	if err != nil {
		return ProjectState{}, err
	}
	hierarchies, err := discoverHierarchies(filepath.Join(service.Root, "projects"))
	if err != nil {
		return ProjectState{}, err
	}
	if name == "None" {
		if file != "" {
			return ProjectState{}, errors.New("None hierarchy cannot have a source file")
		}
	} else if !hasCompatibleHierarchy(hierarchies, name, file) {
		return ProjectState{}, fmt.Errorf("hierarchy %q in %q is not an available hierarchy", name, file)
	}
	service.Mu.Lock()
	defer service.Mu.Unlock()
	selected := CompatibleProject(projects, service.Active)
	if selected.Name == "" {
		return ProjectState{}, errors.New("no compatible project is active")
	}
	sus, err := service.discoverSUs(selected)
	if err != nil {
		return ProjectState{}, err
	}
	if err := service.saveSelectionWithHierarchy(service.Active, service.ActiveSU, name, file); err != nil {
		return ProjectState{}, err
	}
	service.activeHierarchy = name
	service.hierarchyFile = file
	return ProjectState{ActiveProject: service.Active, ActiveSU: service.ActiveSU, ActiveHierarchy: name, HierarchyFile: file, Projects: projects, SUs: sus, Hierarchies: hierarchies, Diagnostics: diagnostics}, nil
}

func (service *ProjectService) GetHierarchyNodes(ctx context.Context) ([]HierarchyNode, error) {
	if err := sqlutil.AcquireReadLease(ctx, &service.Mu); err != nil {
		return nil, err
	}
	if service.Sqlite != nil {
		defer service.Mu.RUnlock()
		return service.sqliteHierarchyLocked(ctx)
	}
	service.Mu.RUnlock()
	service.Mu.RLock()
	name, file := service.activeHierarchy, service.hierarchyFile
	service.Mu.RUnlock()
	if name == "None" {
		return []HierarchyNode{}, nil
	}
	hierarchies, err := discoverHierarchies(filepath.Join(service.Root, "projects"))
	if err != nil {
		return nil, err
	}
	if !hasCompatibleHierarchy(hierarchies, name, file) {
		return nil, errors.New("active hierarchy is no longer available")
	}
	return listHierarchyNodesContext(ctx, filepath.Join(service.Root, "projects", file), name)
}

func (service *ProjectService) saveSelection(name, su string) error {
	return service.saveSelectionWithHierarchy(name, su, service.activeHierarchy, service.hierarchyFile)
}

func (service *ProjectService) saveSelectionWithHierarchy(name, su, hierarchy, file string) error {
	if service.Preferences != nil {
		projects, _, err := service.discover()
		if err != nil {
			return err
		}
		selected := CompatibleProject(projects, name)
		if selected.Name == "" {
			return errors.New("cannot persist an unavailable project")
		}
		path, err := filepath.Abs(filepath.Join(service.Root, "projects", selected.File))
		if err != nil {
			return err
		}
		suPath, hierarchyPath := "", ""
		if su != "None" {
			suPath = path
		}
		if hierarchy != "None" {
			hierarchyPath, err = filepath.Abs(filepath.Join(service.Root, "projects", file))
			if err != nil {
				return err
			}
		}
		return service.Preferences.Update("Current", map[string]any{
			"CurrProject": name, "ProjectPath": path, "CurrPlotlist": su, "SUPath": suPath,
			"CurrHierarchy": hierarchy, "HierarchyPath": hierarchyPath,
		})
	}
	if su == "None" {
		su = ""
	}
	if hierarchy == "None" {
		hierarchy = ""
		file = ""
	}
	settings, err := json.Marshal(struct {
		ActiveProject   string `json:"activeProject"`
		ActiveSU        string `json:"activeSU,omitempty"`
		ActiveHierarchy string `json:"activeHierarchy,omitempty"`
		HierarchyFile   string `json:"hierarchyFile,omitempty"`
	}{name, su, hierarchy, file})
	if err != nil {
		return err
	}
	if err := os.MkdirAll(service.Config, 0700); err != nil {
		return err
	}
	temporary, err := os.CreateTemp(service.Config, ".selection-*.json")
	if err != nil {
		return err
	}
	defer os.Remove(temporary.Name())
	if err := temporary.Chmod(0600); err != nil {
		temporary.Close()
		return err
	}
	if _, err := temporary.Write(settings); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	if err := os.Rename(temporary.Name(), filepath.Join(service.Config, "desktop-selection.json")); err != nil {
		return err
	}
	return nil
}

func (service *ProjectService) ListPlots(ctx context.Context, offset, limit int) (PlotPage, error) {
	if err := ctx.Err(); err != nil {
		return PlotPage{}, err
	}
	if offset < 0 || limit < 1 || limit > 200 {
		return PlotPage{}, errors.New("plot page requires a nonnegative offset and a limit from 1 to 200")
	}
	if err := sqlutil.AcquireReadLease(ctx, &service.Mu); err != nil {
		return PlotPage{}, err
	}
	if service.Sqlite != nil {
		defer service.Mu.RUnlock()
		return service.sqlitePlotsLocked(ctx, offset, limit)
	}
	service.Mu.RUnlock()
	service.Mu.RLock()
	active := service.Active
	activeSU := service.ActiveSU
	service.Mu.RUnlock()
	projects, _, err := service.discover()
	if err != nil {
		return PlotPage{}, err
	}
	selected := CompatibleProject(projects, active)
	if selected.Name == "" {
		return PlotPage{}, errors.New("no compatible project is active")
	}
	database, err := sqlutil.OpenReadOnly(filepath.Join(service.Root, "projects", selected.File))
	if err != nil {
		return PlotPage{}, err
	}
	defer database.Close()
	table := `"` + active + `_Env"`
	from := " FROM " + table + ` AS env WHERE EXISTS (SELECT 1 FROM "` + active + `_Admin" AS admin WHERE admin.Plot = env.PlotNumber)`
	if activeSU != "None" {
		sus, err := service.discoverSUs(selected)
		if err != nil {
			return PlotPage{}, err
		}
		if !hasCompatibleSU(sus, activeSU) {
			return PlotPage{}, errors.New("active SU is no longer available")
		}
		from += ` AND EXISTS (SELECT 1 FROM "` + activeSU + `_SU" AS su WHERE su.PlotNumber = env.PlotNumber)`
	}
	page := PlotPage{Plots: []PlotSummary{}}
	if err := database.QueryRowContext(ctx, "SELECT COUNT(*)"+from).Scan(&page.Total); err != nil {
		return PlotPage{}, err
	}
	rows, err := database.QueryContext(ctx, "SELECT env.PlotNumber, env.FieldNumber, env.PlotRepresenting, env.Zone, env.SubZone, env.SiteSeries"+from+" ORDER BY env.PlotNumber LIMIT ? OFFSET ?", limit, offset)
	if err != nil {
		return PlotPage{}, err
	}
	defer rows.Close()
	for rows.Next() {
		var plot PlotSummary
		if err := rows.Scan(&plot.PlotNumber, &plot.FieldNumber, &plot.PlotRepresenting, &plot.Zone, &plot.SubZone, &plot.SiteSeries); err != nil {
			return PlotPage{}, err
		}
		page.Plots = append(page.Plots, plot)
	}
	return page, rows.Err()
}
