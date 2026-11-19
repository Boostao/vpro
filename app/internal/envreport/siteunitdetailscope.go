package envreport

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type siteUnitDetailQuerySource string

const (
	siteUnitDetailProjectJoin          siteUnitDetailQuerySource = "project-env-admin"
	siteUnitDetailSelectedSU           siteUnitDetailQuerySource = "selected-su-filtered-env-admin"
	siteUnitDetailDynamicSU            siteUnitDetailQuerySource = "dynamic-su-env-admin"
	siteUnitDetailHierarchyBreakpoints siteUnitDetailQuerySource = "hierarchy-breakpoints-env-admin"
	siteUnitDetailFieldDerived         siteUnitDetailQuerySource = "field-derived-env-admin"
)

func isKnownSiteUnitDetailQuerySource(source siteUnitDetailQuerySource) bool {
	switch source {
	case siteUnitDetailProjectJoin,
		siteUnitDetailSelectedSU,
		siteUnitDetailDynamicSU,
		siteUnitDetailHierarchyBreakpoints,
		siteUnitDetailFieldDerived:
		return true
	default:
		return false
	}
}

func siteUnitDetailAllowsUnselectedSU(source siteUnitDetailQuerySource) bool {
	return source == siteUnitDetailHierarchyBreakpoints || source == siteUnitDetailFieldDerived
}

type siteUnitDetailJoinedPlot struct {
	PlotNumber string
	SURowID    string
	EnvRowID   string
	AdminRowID string
}

type siteUnitDetailScopeUnit struct {
	Code  string
	Plots []siteUnitDetailJoinedPlot
}

type siteUnitDetailScopeMembership struct {
	RowID      string
	PlotNumber vprocore.ProjectMetadataCell
	SiteUnit   vprocore.ProjectMetadataCell
	JoinedRows int
	Status     string
}

type siteUnitDetailScope struct {
	Project     string
	SU          string
	QuerySource siteUnitDetailQuerySource
	Units       []siteUnitDetailScopeUnit
	Memberships []siteUnitDetailScopeMembership
}

// This prepares physical normal-SU join weights, not source collation, numeric
// summaries, reference names, hierarchy/field-derived units or report output.
func prepareSiteUnitDetailScope(ctx context.Context, project, suName string, source siteUnitDetailQuerySource,
	maxJoinedRows int, env, admin, su vprocore.ProjectMetadataTable) (siteUnitDetailScope, error) {
	fail := func(err error) (siteUnitDetailScope, error) { return siteUnitDetailScope{}, err }
	if err := ctx.Err(); err != nil {
		return fail(err)
	}
	if !isKnownSiteUnitDetailQuerySource(source) {
		return fail(errors.New("site unit detail scope requires known project or resolved SU query provenance"))
	}
	if project == "" || suName == "" || (suName == "None" && !siteUnitDetailAllowsUnselectedSU(source)) ||
		!utf8.ValidString(project) || !utf8.ValidString(suName) || strings.ContainsRune(project+suName, 0) {
		return fail(errors.New("site unit detail scope requires explicit valid project/SU identities"))
	}
	if maxJoinedRows <= 0 {
		return fail(errors.New("site unit detail scope requires a positive joined-row budget"))
	}
	envColumns, err := vprocore.SiteUnitTransferColumns(env, "PlotNumber")
	if err != nil {
		return fail(fmt.Errorf("site unit detail Env schema: %w", err))
	}
	adminColumns, err := vprocore.SiteUnitTransferColumns(admin, "Plot")
	if err != nil {
		return fail(fmt.Errorf("site unit detail Admin schema: %w", err))
	}
	suColumns, err := vprocore.SiteUnitTransferColumns(su, "PlotNumber", "SiteUnit")
	if err != nil {
		return fail(fmt.Errorf("site unit detail selected SU schema: %w", err))
	}
	if err := ctx.Err(); err != nil {
		return fail(err)
	}
	envRows, err := vprocore.SiteUnitTransferIndex(env, envColumns["PlotNumber"])
	if err != nil {
		return fail(fmt.Errorf("site unit detail Env identity: %w", err))
	}
	adminRows, err := vprocore.SiteUnitTransferIndex(admin, adminColumns["Plot"])
	if err != nil {
		return fail(fmt.Errorf("site unit detail Admin identity: %w", err))
	}
	result := siteUnitDetailScope{Project: project, SU: suName, QuerySource: source,
		Units: []siteUnitDetailScopeUnit{}, Memberships: []siteUnitDetailScopeMembership{}}
	units := map[string][]siteUnitDetailJoinedPlot{}
	joined := 0
	for _, row := range su.Rows {
		if err := ctx.Err(); err != nil {
			return fail(err)
		}
		plotCell, unitCell := row.Cells[suColumns["PlotNumber"]], row.Cells[suColumns["SiteUnit"]]
		plot, err := vprocore.VegetationReportIdentity(plotCell)
		if err != nil {
			return fail(fmt.Errorf("site unit detail SU row %s plot identity: %w", row.RowID, err))
		}
		unit, err := vprocore.VegetationReportIdentity(unitCell)
		if err != nil {
			return fail(fmt.Errorf("site unit detail SU row %s unit identity: %w", row.RowID, err))
		}
		membership := siteUnitDetailScopeMembership{RowID: row.RowID, PlotNumber: vprocore.CloneSiteUnitCell(plotCell),
			SiteUnit: vprocore.CloneSiteUnitCell(unitCell)}
		switch {
		case unit == nil:
			membership.Status = "null-unit"
		case plot == nil:
			membership.Status = "null-plot"
		case len(envRows[*plot]) == 0:
			membership.Status = "missing-env"
		case len(adminRows[*plot]) == 0:
			membership.Status = "missing-admin"
		default:
			membership.Status = "joined"
			// Filtered_Env DISTINCTROW projects Env/Admin, not SU: its
			// selected-SU filter does not multiply this final SU join again.
			for _, environment := range envRows[*plot] {
				for _, administration := range adminRows[*plot] {
					if err := ctx.Err(); err != nil {
						return fail(err)
					}
					if joined == maxJoinedRows {
						return fail(fmt.Errorf("site unit detail scope exceeds joined-row budget %d", maxJoinedRows))
					}
					units[*unit] = append(units[*unit], siteUnitDetailJoinedPlot{
						*plot, row.RowID, environment.RowID, administration.RowID})
					joined++
					membership.JoinedRows++
				}
			}
		}
		result.Memberships = append(result.Memberships, membership)
	}
	for unit, plots := range units {
		if err := ctx.Err(); err != nil {
			return fail(err)
		}
		sort.Slice(plots, func(i, j int) bool {
			a, b := plots[i], plots[j]
			if a.PlotNumber != b.PlotNumber {
				return a.PlotNumber < b.PlotNumber
			}
			if a.SURowID != b.SURowID {
				return a.SURowID < b.SURowID
			}
			if a.EnvRowID != b.EnvRowID {
				return a.EnvRowID < b.EnvRowID
			}
			return a.AdminRowID < b.AdminRowID
		})
		result.Units = append(result.Units, siteUnitDetailScopeUnit{unit, plots})
	}
	sort.Slice(result.Units, func(i, j int) bool { return result.Units[i].Code > result.Units[j].Code })
	sort.Slice(result.Memberships, func(i, j int) bool { return result.Memberships[i].RowID < result.Memberships[j].RowID })
	if err := ctx.Err(); err != nil {
		return fail(err)
	}
	return result, nil
}

type siteUnitDetailOwnedScope struct {
	ContextID   string
	ProjectPath string
	SUPath      string
	Scope       siteUnitDetailScope
}

type SiteUnitSummaryRequest struct {
	Method int `json:"method"`
}

func (request *SiteUnitSummaryRequest) UnmarshalJSON(data []byte) error {
	type plain SiteUnitSummaryRequest
	var value plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &value, "Summary Environment preview", "method"); err != nil {
		return err
	}
	*request = SiteUnitSummaryRequest(value)
	return nil
}

type SiteUnitSummaryPreview struct {
	ContextID   string                `json:"contextId"`
	ProjectPath string                `json:"projectPath"`
	SUPath      string                `json:"suPath"`
	Report      SiteUnitSummaryReport `json:"report"`
}

type SiteUnitSummaryOptions struct {
	ContextID    string `json:"contextId"`
	Project      string `json:"project"`
	ProjectPath  string `json:"projectPath"`
	SU           string `json:"su"`
	SUPath       string `json:"suPath"`
	Method       int    `json:"method"`
	SiteUnitType int    `json:"siteUnitType"`
}

func GetSiteUnitSummaryOptions(s *vprocore.ContextService, ctx context.Context, contextID string) (SiteUnitSummaryOptions, error) {
	if ctx == nil {
		return SiteUnitSummaryOptions{}, errors.New("Summary Environment options require a context")
	}
	if err := ctx.Err(); err != nil {
		return SiteUnitSummaryOptions{}, err
	}
	if s == nil {
		return SiteUnitSummaryOptions{}, errors.New("Summary Environment options require owned contexts")
	}
	return ReadSiteUnitSummaryOptions(s, ctx, contextID, vprocore.PublicationReadSnapshotHooks{})
}

func ReadSiteUnitSummaryOptions(s *vprocore.ContextService, ctx context.Context, contextID string,
	hooks vprocore.PublicationReadSnapshotHooks) (SiteUnitSummaryOptions, error) {
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (SiteUnitSummaryOptions, error) {
		return vprocore.WithOwnedPreferenceSnapshot(ctx, plots, hooks, func(owner *vprocore.SqliteContext, tx *sql.Tx) (SiteUnitSummaryOptions, error) {
			config := plots.Projects.Preferences
			if config == nil {
				return SiteUnitSummaryOptions{}, errors.New("Summary Environment option configuration is unavailable")
			}
			if err := sqlutil.AcquireMutexLease(ctx, &config.Mu); err != nil {
				return SiteUnitSummaryOptions{}, err
			}
			defer config.Mu.Unlock()
			values, err := config.ReadLocked()
			if err != nil {
				return SiteUnitSummaryOptions{}, err
			}
			method, err := vprocore.ConfigInt(values, "ReportOptions", "SEOptValueMethod", 1, 2)
			if err != nil {
				return SiteUnitSummaryOptions{}, err
			}
			unitType, err := vprocore.ConfigInt(values, "ReportOptions", "SESuType", 1, 3)
			if err != nil {
				return SiteUnitSummaryOptions{}, err
			}
			if unitType == 1 && (owner.Selection.SU == "" || owner.Selection.SU == "None") {
				return SiteUnitSummaryOptions{}, errors.New("Summary Environment requires an explicitly selected normal SU")
			}
			if unitType == 2 && (owner.Selection.Hierarchy == "" || owner.Selection.Hierarchy == "None") {
				return SiteUnitSummaryOptions{}, errors.New("Summary Environment hierarchy breakpoints require an active hierarchy")
			}
			if err := ctx.Err(); err != nil {
				return SiteUnitSummaryOptions{}, err
			}
			return SiteUnitSummaryOptions{contextID, owner.Selection.Project, owner.Selection.ProjectPath,
				owner.Selection.SU, owner.Selection.SUPath, method, unitType}, nil
		})
	})
}

func ReadSiteUnitSummaryFullPreferences(s *vprocore.ContextService, ctx context.Context, contextID string,
	hooks vprocore.PublicationReadSnapshotHooks) (SiteUnitSummaryFullPreferences, error) {
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (SiteUnitSummaryFullPreferences, error) {
		return vprocore.WithOwnedPreferenceSnapshot(ctx, plots, hooks, func(owner *vprocore.SqliteContext, tx *sql.Tx) (SiteUnitSummaryFullPreferences, error) {
			values, err := readSiteUnitSummaryFullPreferenceValues(ctx, plots.Projects.Preferences)
			if err != nil {
				return SiteUnitSummaryFullPreferences{}, err
			}
			if values.SiteUnitType == 1 && (owner.Selection.SU == "" || owner.Selection.SU == "None") {
				return SiteUnitSummaryFullPreferences{}, errors.New("Summary Environment requires an explicitly selected normal SU")
			}
			if values.SiteUnitType == 2 && (owner.Selection.Hierarchy == "" || owner.Selection.Hierarchy == "None") {
				return SiteUnitSummaryFullPreferences{}, errors.New("Summary Environment hierarchy breakpoints require an active hierarchy")
			}
			return SiteUnitSummaryFullPreferences{
				ContextID:   contextID,
				Project:     owner.Selection.Project,
				ProjectPath: owner.Selection.ProjectPath,
				SU:          owner.Selection.SU,
				SUPath:      owner.Selection.SUPath,
				Values:      values,
			}, nil
		})
	})
}

func readSiteUnitSummaryUnitType(ctx context.Context, config *vprocore.DesktopConfig) (int, error) {
	if config == nil {
		return 1, nil
	}
	if err := sqlutil.AcquireMutexLease(ctx, &config.Mu); err != nil {
		return 0, err
	}
	defer config.Mu.Unlock()
	values, err := config.ReadLocked()
	if err != nil {
		return 0, err
	}
	return vprocore.ConfigInt(values, "ReportOptions", "SESuType", 1, 3)
}

var defaultSiteUnitSummaryGroupFields = []string{"Zone", "SubZone", "SiteSeries"}

func resolveSiteUnitSummaryScopeTables(ctx context.Context, owner *vprocore.SqliteContext, tx *sql.Tx, unitType int, groupFields []string) (
	env, admin, su, master vprocore.ProjectMetadataTable, source siteUnitDetailQuerySource, err error) {
	baseSources := []struct{ role, table string }{
		{"project", owner.Selection.Project + "_Env"},
		{"project", owner.Selection.Project + "_Admin"},
		{"VLists", "MasterSiteUnitList"},
	}
	baseTables := make([]vprocore.ProjectMetadataTable, 3)
	for i, src := range baseSources {
		table, readErr := vprocore.ReadPhysicalLocationTable(ctx, tx, src.role, src.table)
		if readErr != nil {
			return env, admin, su, master, "", readErr
		}
		baseTables[i] = table
	}
	env, admin, master = baseTables[0], baseTables[1], baseTables[2]
	switch unitType {
	case 1:
		if owner.Selection.SU == "" || owner.Selection.SU == "None" {
			return env, admin, su, master, "", errors.New("Summary Environment requires an explicitly selected normal SU")
		}
		su, err = vprocore.ReadPhysicalLocationTable(ctx, tx, "su", owner.Selection.SU+"_SU")
		if err != nil {
			return env, admin, su, master, "", err
		}
		source = siteUnitDetailSelectedSU
		if owner.Selection.SU == "USysSuTableDynamic" {
			source = siteUnitDetailDynamicSU
		}
		return env, admin, su, master, source, nil
	case 2:
		if owner.Selection.Hierarchy == "" || owner.Selection.Hierarchy == "None" {
			return env, admin, su, master, "", errors.New("Summary Environment hierarchy breakpoints require an active hierarchy")
		}
		hier, readErr := vprocore.ReadPhysicalLocationTable(ctx, tx, "hierarchy", owner.Selection.Hierarchy+"_Hierarchy")
		if readErr != nil {
			return env, admin, su, master, "", readErr
		}
		var hasBaseSU bool
		var baseSU vprocore.ProjectMetadataTable
		if owner.Selection.SU != "" && owner.Selection.SU != "None" {
			baseSU, readErr = vprocore.ReadPhysicalLocationTable(ctx, tx, "su", owner.Selection.SU+"_SU")
			if readErr != nil {
				return env, admin, su, master, "", readErr
			}
			hasBaseSU = true
		}
		su, err = buildHierarchyBreakpointSUTable(ctx, hier, baseSU, hasBaseSU, env)
		if err != nil {
			return env, admin, su, master, "", err
		}
		return env, admin, su, master, siteUnitDetailHierarchyBreakpoints, nil
	case 3:
		var hasBaseSU bool
		var baseSU vprocore.ProjectMetadataTable
		if owner.Selection.SU != "" && owner.Selection.SU != "None" {
			var readErr error
			baseSU, readErr = vprocore.ReadPhysicalLocationTable(ctx, tx, "su", owner.Selection.SU+"_SU")
			if readErr != nil {
				return env, admin, su, master, "", readErr
			}
			hasBaseSU = true
		}
		su, err = buildFieldDerivedSUTable(ctx, env, baseSU, hasBaseSU, groupFields)
		if err != nil {
			return env, admin, su, master, "", err
		}
		return env, admin, su, master, siteUnitDetailFieldDerived, nil
	default:
		return env, admin, su, master, "", errors.New("Summary Environment requires Normal SU (1), Hierarchy Breakpoints (2), or Field-Derived (3)")
	}
}

func metadataCellText(cell vprocore.ProjectMetadataCell) (string, bool) {
	switch cell.Storage {
	case "text":
		if cell.Text == nil {
			return "", false
		}
		trimmed := strings.TrimSpace(*cell.Text)
		return trimmed, trimmed != ""
	case "integer":
		if cell.Integer == nil {
			return "", false
		}
		trimmed := strings.TrimSpace(*cell.Integer)
		return trimmed, trimmed != ""
	case "real":
		if cell.Real == nil {
			return "", false
		}
		return strconv.FormatFloat(*cell.Real, 'g', -1, 64), true
	default:
		return "", false
	}
}

func buildHierarchyBreakpointSUTable(ctx context.Context, hier, baseSU vprocore.ProjectMetadataTable, hasBaseSU bool,
	env vprocore.ProjectMetadataTable) (vprocore.ProjectMetadataTable, error) {
	if err := ctx.Err(); err != nil {
		return vprocore.ProjectMetadataTable{}, err
	}
	hCols, err := vprocore.SiteUnitTransferColumns(hier, "ID", "Name", "Parent")
	if err != nil {
		return vprocore.ProjectMetadataTable{}, fmt.Errorf("Summary Environment hierarchy schema: %w", err)
	}
	type hierNode struct {
		id     string
		name   string
		parent string
		isBP   bool
		bpName string
	}
	nodesByID := make(map[string]hierNode, len(hier.Rows))
	exactMatches := make(map[string][]string)
	foldMatches := make(map[string][]string)
	breakpointCount := 0
	for _, row := range hier.Rows {
		id, okID := metadataCellText(row.Cells[hCols["ID"]])
		if !okID {
			continue
		}
		rawName := ""
		if t, ok := metadataCellText(row.Cells[hCols["Name"]]); ok {
			rawName = t
		}
		parent, _ := metadataCellText(row.Cells[hCols["Parent"]])
		isBP := strings.HasPrefix(rawName, "~")
		bpName := ""
		if isBP {
			breakpointCount++
			bpName = strings.TrimSpace(strings.TrimPrefix(rawName, "~"))
		}
		nodesByID[id] = hierNode{id: id, name: rawName, parent: parent, isBP: isBP, bpName: bpName}
		if rawName != "" {
			exactMatches[rawName] = append(exactMatches[rawName], id)
			foldMatches[strings.ToLower(rawName)] = append(foldMatches[strings.ToLower(rawName)], id)
			if isBP && bpName != "" {
				exactMatches[bpName] = append(exactMatches[bpName], id)
				foldMatches[strings.ToLower(bpName)] = append(foldMatches[strings.ToLower(bpName)], id)
			}
		}
	}
	if breakpointCount == 0 {
		return vprocore.ProjectMetadataTable{}, errors.New("Summary Environment hierarchy breakpoints found no '~' breakpoint nodes in active hierarchy")
	}
	resolveBP := func(unitName string) (string, bool) {
		unitName = strings.TrimSpace(unitName)
		if unitName == "" {
			return "", false
		}
		candidates := exactMatches[unitName]
		if len(candidates) == 0 {
			candidates = foldMatches[strings.ToLower(unitName)]
		}
		for _, startID := range candidates {
			visited := make(map[string]bool)
			curID := startID
			for curID != "" {
				if visited[curID] {
					break
				}
				visited[curID] = true
				node, ok := nodesByID[curID]
				if !ok {
					break
				}
				if node.isBP && node.bpName != "" {
					return node.bpName, true
				}
				if node.parent == "" || node.parent == curID {
					break
				}
				curID = node.parent
			}
		}
		return "", false
	}
	out := vprocore.ProjectMetadataTable{
		Columns: []vprocore.ProjectMetadataColumn{
			{Name: "PlotNumber", DeclaredType: "TEXT"},
			{Name: "SiteUnit", DeclaredType: "TEXT"},
		},
		Rows: []vprocore.ProjectMetadataRow{},
	}
	if hasBaseSU {
		suCols, err := vprocore.SiteUnitTransferColumns(baseSU, "PlotNumber", "SiteUnit")
		if err != nil {
			return vprocore.ProjectMetadataTable{}, err
		}
		for _, row := range baseSU.Rows {
			plotCell := vprocore.CloneSiteUnitCell(row.Cells[suCols["PlotNumber"]])
			unitCell := vprocore.ProjectMetadataCell{Storage: "null"}
			if unitName, ok := metadataCellText(row.Cells[suCols["SiteUnit"]]); ok {
				if bp, matched := resolveBP(unitName); matched {
					bpCopy := bp
					unitCell = vprocore.ProjectMetadataCell{Storage: "text", Text: &bpCopy}
				}
			}
			out.Rows = append(out.Rows, vprocore.ProjectMetadataRow{
				RowID: row.RowID,
				Cells: []vprocore.ProjectMetadataCell{plotCell, unitCell},
			})
		}
		return out, nil
	}
	envCols, err := vprocore.SiteUnitTransferColumns(env, "PlotNumber")
	if err != nil {
		return vprocore.ProjectMetadataTable{}, err
	}
	candidateUnitCols := make([]int, 0, 3)
	for _, name := range []string{"UserSiteUnit", "BECSiteUnit", "SiteSeries"} {
		for idx, col := range env.Columns {
			if col.Name == name {
				candidateUnitCols = append(candidateUnitCols, idx)
				break
			}
		}
	}
	for _, row := range env.Rows {
		plotCell := vprocore.CloneSiteUnitCell(row.Cells[envCols["PlotNumber"]])
		unitCell := vprocore.ProjectMetadataCell{Storage: "null"}
		for _, colIdx := range candidateUnitCols {
			if unitName, ok := metadataCellText(row.Cells[colIdx]); ok {
				if bp, matched := resolveBP(unitName); matched {
					bpCopy := bp
					unitCell = vprocore.ProjectMetadataCell{Storage: "text", Text: &bpCopy}
					break
				}
			}
		}
		out.Rows = append(out.Rows, vprocore.ProjectMetadataRow{
			RowID: row.RowID,
			Cells: []vprocore.ProjectMetadataCell{plotCell, unitCell},
		})
	}
	return out, nil
}

func buildFieldDerivedSUTable(ctx context.Context, env, baseSU vprocore.ProjectMetadataTable, hasBaseSU bool,
	groupFields []string) (vprocore.ProjectMetadataTable, error) {
	if err := ctx.Err(); err != nil {
		return vprocore.ProjectMetadataTable{}, err
	}
	if len(groupFields) == 0 {
		groupFields = defaultSiteUnitSummaryGroupFields
	}
	required := append([]string{"PlotNumber"}, groupFields...)
	envCols, err := vprocore.SiteUnitTransferColumns(env, required...)
	if err != nil {
		return vprocore.ProjectMetadataTable{}, fmt.Errorf("Summary Environment field-derived schema: %w", err)
	}
	deriveRowUnit := func(row vprocore.ProjectMetadataRow) vprocore.ProjectMetadataCell {
		var b strings.Builder
		for _, field := range groupFields {
			if text, ok := metadataCellText(row.Cells[envCols[field]]); ok {
				b.WriteString(text)
			}
		}
		code := strings.TrimSpace(b.String())
		if code == "" {
			return vprocore.ProjectMetadataCell{Storage: "null"}
		}
		return vprocore.ProjectMetadataCell{Storage: "text", Text: &code}
	}
	out := vprocore.ProjectMetadataTable{
		Columns: []vprocore.ProjectMetadataColumn{
			{Name: "PlotNumber", DeclaredType: "TEXT"},
			{Name: "SiteUnit", DeclaredType: "TEXT"},
		},
		Rows: []vprocore.ProjectMetadataRow{},
	}
	if hasBaseSU {
		suCols, err := vprocore.SiteUnitTransferColumns(baseSU, "PlotNumber")
		if err != nil {
			return vprocore.ProjectMetadataTable{}, err
		}
		derivedByPlot := make(map[string]vprocore.ProjectMetadataCell, len(env.Rows))
		for _, row := range env.Rows {
			plotText, ok := metadataCellText(row.Cells[envCols["PlotNumber"]])
			if !ok {
				continue
			}
			if _, exists := derivedByPlot[plotText]; !exists {
				derivedByPlot[plotText] = deriveRowUnit(row)
			}
		}
		for _, row := range baseSU.Rows {
			plotCell := vprocore.CloneSiteUnitCell(row.Cells[suCols["PlotNumber"]])
			unitCell := vprocore.ProjectMetadataCell{Storage: "null"}
			if plotText, ok := metadataCellText(plotCell); ok {
				if derived, exists := derivedByPlot[plotText]; exists {
					unitCell = vprocore.CloneSiteUnitCell(derived)
				}
			}
			out.Rows = append(out.Rows, vprocore.ProjectMetadataRow{
				RowID: row.RowID,
				Cells: []vprocore.ProjectMetadataCell{plotCell, unitCell},
			})
		}
		return out, nil
	}
	for _, row := range env.Rows {
		out.Rows = append(out.Rows, vprocore.ProjectMetadataRow{
			RowID: row.RowID,
			Cells: []vprocore.ProjectMetadataCell{
				vprocore.CloneSiteUnitCell(row.Cells[envCols["PlotNumber"]]),
				deriveRowUnit(row),
			},
		})
	}
	return out, nil
}

func PreviewSiteUnitSummary(s *vprocore.ContextService, ctx context.Context, contextID string, request SiteUnitSummaryRequest) (SiteUnitSummaryPreview, error) {
	if ctx == nil {
		return SiteUnitSummaryPreview{}, errors.New("Summary Environment preview requires a context")
	}
	if err := ctx.Err(); err != nil {
		return SiteUnitSummaryPreview{}, err
	}
	if s == nil {
		return SiteUnitSummaryPreview{}, errors.New("Summary Environment preview requires owned contexts")
	}
	return ReadSiteUnitSummary(s, ctx, contextID, request, vprocore.PublicationReadSnapshotHooks{})
}

func ReadSiteUnitSummary(s *vprocore.ContextService, ctx context.Context, contextID string, request SiteUnitSummaryRequest,
	hooks vprocore.PublicationReadSnapshotHooks) (SiteUnitSummaryPreview, error) {
	if request.Method != 1 && request.Method != 2 {
		return SiteUnitSummaryPreview{}, errors.New("Summary Environment requires Mean (1) or Interquartile (2)")
	}
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (SiteUnitSummaryPreview, error) {
		return vprocore.WithOwnedPreferenceSnapshot(ctx, plots, hooks, func(owner *vprocore.SqliteContext, tx *sql.Tx) (SiteUnitSummaryPreview, error) {
			unitType, err := readSiteUnitSummaryUnitType(ctx, plots.Projects.Preferences)
			if err != nil {
				return SiteUnitSummaryPreview{}, err
			}
			input, err := readSiteUnitSummaryWorkbookSourceWithScope(ctx, owner, tx, contextID, request.Method, unitType)
			if err != nil {
				return SiteUnitSummaryPreview{}, err
			}
			return input.Preview, nil
		})
	})
}
