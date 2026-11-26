package envreport

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/boostao/vpro/app/internal/reports/reportcore"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

// QuickEnvReportExportResult summarizes a streamlined one-step environment workbook export.
type QuickEnvReportExportResult struct {
	ReportKind          string `json:"reportKind"`
	Title               string `json:"title"`
	Project             string `json:"project"`
	SU                  string `json:"su"`
	ScopeLabel          string `json:"scopeLabel"`
	FallbackNotice      string `json:"fallbackNotice,omitempty"`
	UnitCount           int    `json:"unitCount"`
	PlotCount           int    `json:"plotCount"`
	Path                string `json:"path"`
	SHA256              string `json:"sha256"`
	Bytes               int    `json:"bytes"`
	PreferencesSaved    bool   `json:"preferencesSaved"`
	OpenedInSpreadsheet bool   `json:"openedInSpreadsheet"`
	SpreadsheetNotice   string `json:"spreadsheetNotice,omitempty"`
}

// QuickLongEnvironmentRequest configures one-step Long Environment HTML or XLSX generation.
type QuickLongEnvironmentRequest struct {
	Title             *string `json:"title,omitempty"`
	ScopeMode         string  `json:"scopeMode,omitempty"` // "auto" | "su" | "zone-subzone" | "all-plots"
	SavePreferences   *bool   `json:"savePreferences,omitempty"`
	DestinationPath   string  `json:"destinationPath,omitempty"`
	OpenInSpreadsheet bool    `json:"openInSpreadsheet,omitempty"`
}

func (r *QuickLongEnvironmentRequest) UnmarshalJSON(data []byte) error {
	type plain QuickLongEnvironmentRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

// QuickSummaryEnvironmentRequest configures one-step Summary Environment (Site Unit Summary) generation.
type QuickSummaryEnvironmentRequest struct {
	Method              *int   `json:"method,omitempty"`       // 1 = Mean, 2 = Interquartile
	SiteUnitType        *int   `json:"siteUnitType,omitempty"` // 1 = Normal SU, 2 = Hierarchy Breakpoints, 3 = Field-Derived
	OrderBy             *int   `json:"orderBy,omitempty"`      // 1 = Layer, 2 = Lifeform
	IncludeSpecies      *int   `json:"includeSpecies,omitempty"`
	CoverCalculation    *int   `json:"coverCalculation,omitempty"`
	AndOr               *int   `json:"andOr,omitempty"`
	PresenceGreaterThan *int   `json:"presenceGreaterThan,omitempty"`
	CoverGreaterThan    *int   `json:"coverGreaterThan,omitempty"`
	SavePreferences     *bool  `json:"savePreferences,omitempty"`
	DestinationPath     string `json:"destinationPath,omitempty"`
	OpenInSpreadsheet   bool   `json:"openInSpreadsheet,omitempty"`
}

func (r *QuickSummaryEnvironmentRequest) UnmarshalJSON(data []byte) error {
	type plain QuickSummaryEnvironmentRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

// QuickSubzoneMatrixRequest configures one-step Subzone Matrix XLSX generation.
type QuickSubzoneMatrixRequest struct {
	DestinationPath   string `json:"destinationPath,omitempty"`
	OpenInSpreadsheet bool   `json:"openInSpreadsheet,omitempty"`
}

func (r *QuickSubzoneMatrixRequest) UnmarshalJSON(data []byte) error {
	type plain QuickSubzoneMatrixRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

func shouldSaveQuickEnvPreferences(flag *bool) bool {
	return flag == nil || *flag
}

func writeQuickEnvWorkbookAtomic(ctx context.Context, requestedPath, root, project, reportSlug string, data []byte) (string, string, error) {
	if err := ctx.Err(); err != nil {
		return "", "", err
	}
	dest := strings.TrimSpace(requestedPath)
	if dest == "" {
		safeProj := strings.TrimSpace(project)
		if safeProj == "" {
			safeProj = "VPro"
		}
		dest = filepath.Join(root, "exports", fmt.Sprintf("%s_%s_%s.xlsx", safeProj, reportSlug, time.Now().Format("20060102-150405")))
	} else if !strings.EqualFold(filepath.Ext(dest), ".xlsx") {
		dest += ".xlsx"
	}
	resolved, err := filepath.Abs(dest)
	if err != nil {
		return "", "", fmt.Errorf("resolve export path: %w", err)
	}
	if err := os.MkdirAll(filepath.Dir(resolved), 0o700); err != nil {
		return "", "", fmt.Errorf("create export folder: %w", err)
	}
	tmp, err := os.CreateTemp(filepath.Dir(resolved), ".vpro-env-report-*.xlsx")
	if err != nil {
		return "", "", fmt.Errorf("stage workbook: %w", err)
	}
	tmpPath := tmp.Name()
	committed := false
	defer func() {
		if !committed {
			_ = os.Remove(tmpPath)
		}
	}()
	if err := tmp.Chmod(0o600); err != nil {
		_ = tmp.Close()
		return "", "", err
	}
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		return "", "", err
	}
	if err := tmp.Sync(); err != nil {
		_ = tmp.Close()
		return "", "", err
	}
	if err := tmp.Close(); err != nil {
		return "", "", err
	}
	if err := os.Rename(tmpPath, resolved); err != nil {
		return "", "", fmt.Errorf("save workbook %q: %w", resolved, err)
	}
	committed = true
	sum := sha256.Sum256(data)
	return resolved, hex.EncodeToString(sum[:]), nil
}

func maybeOpenQuickEnvSpreadsheet(ctx context.Context, prefs *vprocore.DesktopConfig, xlsxPath string, requested bool) (bool, string) {
	if !requested {
		return false, ""
	}
	program := ""
	if prefs != nil {
		if pref, err := vprocore.GetSpreadsheetAppPreference(prefs, ctx); err == nil {
			program = pref.ProgramPath
		}
	}
	if err := vprocore.OpenFileInSpreadsheetApp(ctx, xlsxPath, program); err != nil {
		return false, err.Error()
	}
	return true, ""
}

func buildQuickEnvFallbackSU(ctx context.Context, env vprocore.ProjectMetadataTable, scopeMode string) (
	suTable vprocore.ProjectMetadataTable, syntheticSU, scopeLabel, notice string, err error,
) {
	ec, err := vprocore.SiteUnitTransferColumns(env, "PlotNumber")
	if err != nil {
		return vprocore.ProjectMetadataTable{}, "", "", "", fmt.Errorf("Env schema for fallback scope: %w", err)
	}
	colIdx := func(name string) int {
		for i, c := range env.Columns {
			if strings.EqualFold(c.Name, name) {
				return i
			}
		}
		return -1
	}
	zoneIdx := colIdx("Zone")
	subZoneIdx := colIdx("SubZone")
	seriesIdx := colIdx("SiteSeries")

	mode := strings.ToLower(strings.TrimSpace(scopeMode))
	if mode == "" || mode == "auto" || mode == "su" {
		hasBGC := false
		for _, row := range env.Rows {
			if zoneIdx >= 0 && strings.TrimSpace(reportcore.FormatMetadataCellText(row.Cells[zoneIdx])) != "" {
				hasBGC = true
				break
			}
			if subZoneIdx >= 0 && strings.TrimSpace(reportcore.FormatMetadataCellText(row.Cells[subZoneIdx])) != "" {
				hasBGC = true
				break
			}
		}
		if hasBGC {
			mode = "zone-subzone"
		} else {
			mode = "all-plots"
		}
	}

	out := vprocore.ProjectMetadataTable{
		Columns: []vprocore.ProjectMetadataColumn{
			{Name: "PlotNumber", DeclaredType: "TEXT"},
			{Name: "SiteUnit", DeclaredType: "TEXT"},
		},
		Rows: make([]vprocore.ProjectMetadataRow, 0, len(env.Rows)),
	}
	seen := map[string]bool{}
	for _, row := range env.Rows {
		if err := ctx.Err(); err != nil {
			return vprocore.ProjectMetadataTable{}, "", "", "", err
		}
		plotCell := row.Cells[ec["PlotNumber"]]
		plotStr, err := reportcore.EnvironmentReportIdentity(plotCell)
		if err != nil {
			return vprocore.ProjectMetadataTable{}, "", "", "", err
		}
		if plotStr == nil || strings.TrimSpace(*plotStr) == "" || seen[*plotStr] {
			continue
		}
		seen[*plotStr] = true

		unitCode := "All Plots"
		if mode == "zone-subzone" {
			z, sz, ss := "", "", ""
			if zoneIdx >= 0 {
				z = strings.TrimSpace(reportcore.FormatMetadataCellText(row.Cells[zoneIdx]))
			}
			if subZoneIdx >= 0 {
				sz = strings.TrimSpace(reportcore.FormatMetadataCellText(row.Cells[subZoneIdx]))
			}
			if seriesIdx >= 0 {
				ss = strings.TrimSpace(reportcore.FormatMetadataCellText(row.Cells[seriesIdx]))
			}
			bgc := strings.TrimSpace(z + sz)
			switch {
			case bgc != "" && ss != "":
				unitCode = bgc + "/" + ss
			case bgc != "":
				unitCode = bgc
			case ss != "":
				unitCode = ss
			default:
				unitCode = "Unassigned"
			}
		}
		uCopy := unitCode
		out.Rows = append(out.Rows, vprocore.ProjectMetadataRow{
			RowID: row.RowID,
			Cells: []vprocore.ProjectMetadataCell{
				vprocore.CloneSiteUnitCell(plotCell),
				{Storage: "text", Text: &uCopy},
			},
		})
	}
	if len(out.Rows) == 0 {
		return vprocore.ProjectMetadataTable{}, "", "", "", errors.New("no plots were found in the active project")
	}
	if mode == "zone-subzone" {
		return out, "Field_ZoneSubZone", "Field-Derived (Zone / SubZone / SiteSeries)",
			"No Site Unit table is selected; automatically grouped all project plots by Zone, SubZone, and SiteSeries.", nil
	}
	return out, "All_Plots", "All Project Plots",
		"No Site Unit table is selected; automatically included all project plots as one group.", nil
}

func buildQuickLongEnvironmentReport(
	contexts *vprocore.ContextService,
	ctx context.Context,
	contextID string,
	req QuickLongEnvironmentRequest,
) (report reportcore.EnvironmentReport, scopeLabel, fallbackNotice string, prefsSaved bool, root string, err error) {
	_, err = vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (struct{}, error) {
		root = plots.Projects.Root
		title := "Long Environment Report"
		if plots.Projects.Preferences != nil {
			if savedTitle, tErr := ReadLongEnvironmentPreference(plots.Projects.Preferences, ctx); tErr == nil && strings.TrimSpace(savedTitle) != "" {
				title = savedTitle
			}
		}
		if req.Title != nil {
			title = strings.TrimSpace(*req.Title)
			if title == "" {
				title = "Long Environment Report"
			}
			if shouldSaveQuickEnvPreferences(req.SavePreferences) && plots.Projects.Preferences != nil {
				if plots.Projects.Preferences.Update("ReportOptions", map[string]any{"LEReportTitle": title}) == nil {
					prefsSaved = true
				}
			}
		}
		if err := validateLongEnvironmentTitle(title); err != nil {
			return struct{}{}, err
		}

		return vprocore.WithOwnedPreferenceSnapshot(ctx, plots, vprocore.PublicationReadSnapshotHooks{}, func(owner *vprocore.SqliteContext, tx *sql.Tx) (struct{}, error) {
			env, rErr := vprocore.ReadPhysicalLocationTable(ctx, tx, "project", owner.Selection.Project+"_Env")
			if rErr != nil {
				return struct{}{}, rErr
			}
			admin, rErr := vprocore.ReadPhysicalLocationTable(ctx, tx, "project", owner.Selection.Project+"_Admin")
			if rErr != nil {
				return struct{}{}, rErr
			}
			master, rErr := vprocore.ReadPhysicalLocationTable(ctx, tx, "VLists", "MasterSiteUnitList")
			if rErr != nil {
				return struct{}{}, rErr
			}

			mode := strings.ToLower(strings.TrimSpace(req.ScopeMode))
			useActiveSU := owner.Selection.SU != "" && owner.Selection.SU != "None" && owner.Selection.SU != "USysSuTableDynamic" &&
				(mode == "" || mode == "auto" || mode == "su")

			var (
				suTable     vprocore.ProjectMetadataTable
				effectiveSU string
			)
			if useActiveSU {
				suTable, rErr = vprocore.ReadPhysicalLocationTable(ctx, tx, "su", owner.Selection.SU+"_SU")
				if rErr != nil {
					return struct{}{}, rErr
				}
				if len(suTable.Rows) == 0 {
					if mode == "su" {
						return struct{}{}, fmt.Errorf("Site Unit table %q has no assigned plots. Assign plots to this Site Unit table or switch Scope to Auto, Zone/SubZone, or All Project Plots.", owner.Selection.SU)
					}
					var fErr error
					suTable, effectiveSU, scopeLabel, fallbackNotice, fErr = buildQuickEnvFallbackSU(ctx, env, mode)
					if fErr != nil {
						return struct{}{}, fErr
					}
					fallbackNotice = formatEnvEmptySUFallbackNotice(owner.Selection.SU, fallbackNotice)
				} else {
					effectiveSU = owner.Selection.SU
					scopeLabel = "Site Unit: " + owner.Selection.SU
				}
			} else {
				var fErr error
				suTable, effectiveSU, scopeLabel, fallbackNotice, fErr = buildQuickEnvFallbackSU(ctx, env, mode)
				if fErr != nil {
					return struct{}{}, fErr
				}
			}

			planned, pErr := reportcore.PlanLongEnvironment(ctx, owner.Selection.Project, effectiveSU, title, env, admin, suTable, master)
			if pErr != nil {
				return struct{}{}, pErr
			}
			report = planned
			return struct{}{}, nil
		})
	})
	return report, scopeLabel, fallbackNotice, prefsSaved, root, err
}

// QuickExportLongEnvironmentWorkbook runs Long Environment in one step with automatic ActiveSU=="None" fallback.
func QuickExportLongEnvironmentWorkbook(
	contexts *vprocore.ContextService,
	ctx context.Context,
	contextID string,
	req QuickLongEnvironmentRequest,
) (*QuickEnvReportExportResult, error) {
	if contexts == nil || ctx == nil {
		return nil, errors.New("Long Environment quick export requires active context")
	}
	report, scopeLabel, fallbackNotice, prefsSaved, root, err := buildQuickLongEnvironmentReport(contexts, ctx, contextID, req)
	if err != nil {
		return nil, err
	}
	wb, err := prepareLongEnvironmentWorkbook(ctx, report)
	if err != nil {
		return nil, err
	}
	outPath, shaHex, err := writeQuickEnvWorkbookAtomic(ctx, req.DestinationPath, root, report.Project, "LongEnvironment", wb.Bytes)
	if err != nil {
		return nil, err
	}
	opened, spreadNotice := maybeOpenQuickEnvSpreadsheet(ctx, contexts.Projects.Preferences, outPath, req.OpenInSpreadsheet)

	totalPlots := 0
	for _, u := range report.Units {
		totalPlots += len(u.Plots)
	}
	return &QuickEnvReportExportResult{
		ReportKind:          "long_environment",
		Title:               report.Title,
		Project:             report.Project,
		SU:                  report.SU,
		ScopeLabel:          scopeLabel,
		FallbackNotice:      fallbackNotice,
		UnitCount:           len(report.Units),
		PlotCount:           totalPlots,
		Path:                outPath,
		SHA256:              shaHex,
		Bytes:               len(wb.Bytes),
		PreferencesSaved:    prefsSaved,
		OpenedInSpreadsheet: opened,
		SpreadsheetNotice:   spreadNotice,
	}, nil
}

// RenderLongEnvironmentHTMLReport renders a self-contained Quarto-style HTML Long Environment report.
func RenderLongEnvironmentHTMLReport(
	contexts *vprocore.ContextService,
	ctx context.Context,
	contextID string,
	req QuickLongEnvironmentRequest,
) (*reportcore.HTMLReportResult, error) {
	if contexts == nil || ctx == nil {
		return nil, errors.New("Long Environment HTML report requires active context")
	}
	report, scopeLabel, fallbackNotice, _, _, err := buildQuickLongEnvironmentReport(contexts, ctx, contextID, req)
	if err != nil {
		return nil, err
	}
	tables := make([]reportcore.HTMLReportTable, 0, len(report.Units))
	totalPlots := 0
	for _, unit := range report.Units {
		totalPlots += len(unit.Plots)
		headers := make([]string, 0, len(unit.Plots)+1)
		numCols := make([]bool, 0, len(unit.Plots)+1)
		headers = append(headers, "Attribute")
		numCols = append(numCols, false)
		for _, p := range unit.Plots {
			headers = append(headers, p.PlotNumber)
			numCols = append(numCols, false)
		}
		rows := make([]reportcore.HTMLReportRow, 0, len(report.Fields))
		for fIdx, field := range report.Fields {
			if field.Heading {
				rows = append(rows, reportcore.HTMLReportRow{
					Cells:     []string{field.Label},
					IsHeading: true,
				})
				continue
			}
			cells := make([]string, 0, len(unit.Plots)+1)
			cells = append(cells, field.Label)
			for _, p := range unit.Plots {
				val := ""
				if fIdx < len(p.Values) {
					val = reportcore.FormatMetadataCellText(p.Values[fIdx])
				}
				cells = append(cells, val)
			}
			rows = append(rows, reportcore.HTMLReportRow{Cells: cells})
		}
		subtitle := ""
		if unit.LongName != nil {
			subtitle = strings.TrimSpace(*unit.LongName)
		}
		tables = append(tables, reportcore.HTMLReportTable{
			Title:       unit.Code,
			Subtitle:    subtitle,
			PlotCount:   len(unit.Plots),
			Headers:     headers,
			NumericCols: numCols,
			Rows:        rows,
		})
	}
	rendered, err := reportcore.RenderQuartoHTMLReport(reportcore.HTMLReportDocument{
		Title:      report.Title,
		ReportKind: "Long Environment",
		Project:    report.Project,
		SU:         report.SU,
		ScopeLabel: scopeLabel,
		UnitCount:  len(report.Units),
		PlotCount:  totalPlots,
		Notice:     fallbackNotice,
		Tables:     tables,
	})
	if err != nil {
		return nil, err
	}
	return &rendered, nil
}

func activeEnvSUTableRowCount(ctx context.Context, tx *sql.Tx, suName string) (int, error) {
	if suName == "" || suName == "None" || suName == "USysSuTableDynamic" {
		return 0, nil
	}
	var count int
	err := tx.QueryRowContext(
		ctx,
		`SELECT COUNT(*) FROM su.`+vprocore.QuoteHeaderIdentifier(suName+"_SU"),
	).Scan(&count)
	return count, err
}

func formatEnvEmptySUFallbackNotice(suName, baseNotice string) string {
	prefix := fmt.Sprintf("Site Unit table %q has no assigned plots;", suName)
	if strings.HasPrefix(baseNotice, "No Site Unit table is selected;") {
		return prefix + strings.TrimPrefix(baseNotice, "No Site Unit table is selected;")
	}
	if strings.TrimSpace(baseNotice) != "" {
		return prefix + " " + baseNotice
	}
	return prefix + " automatically included all project plots."
}

func resolveQuickSummaryEnvPrefs(
	ctx context.Context,
	prefs *vprocore.DesktopConfig,
	sel vprocore.DesktopSelection,
	req QuickSummaryEnvironmentRequest,
) (vals SiteUnitSummaryFullPreferenceValues, effectiveUnitType int, scopeLabel, fallbackNotice string, changes map[string]any) {
	vals = SiteUnitSummaryFullPreferenceValues{
		Method:           1,
		SiteUnitType:     1,
		OrderBy:          1,
		IncludeSpecies:   0,
		CoverCalculation: 1,
		AndOr:            1,
	}
	if prefs != nil {
		if loaded, err := readSiteUnitSummaryFullPreferenceValues(ctx, prefs); err == nil {
			vals = loaded
		}
	}
	changes = map[string]any{}
	if req.Method != nil && (*req.Method == 1 || *req.Method == 2) {
		vals.Method = *req.Method
		changes["SEOptValueMethod"] = vals.Method
	}
	if req.SiteUnitType != nil && (*req.SiteUnitType >= 1 && *req.SiteUnitType <= 3) {
		vals.SiteUnitType = *req.SiteUnitType
		changes["SESuType"] = vals.SiteUnitType
	}
	if req.OrderBy != nil && (*req.OrderBy == 1 || *req.OrderBy == 2) {
		vals.OrderBy = *req.OrderBy
		changes["SEOrderBy"] = vals.OrderBy
	}
	if req.IncludeSpecies != nil && (*req.IncludeSpecies == 0 || *req.IncludeSpecies == 1) {
		vals.IncludeSpecies = *req.IncludeSpecies
		changes["SEIncludeSppSummary"] = vals.IncludeSpecies
	}
	if req.CoverCalculation != nil && (*req.CoverCalculation >= 1 && *req.CoverCalculation <= 2) {
		vals.CoverCalculation = *req.CoverCalculation
		changes["SECoverCalc"] = vals.CoverCalculation
	}
	if req.AndOr != nil && (*req.AndOr >= 1 && *req.AndOr <= 2) {
		vals.AndOr = *req.AndOr
		changes["SEOptAndOr"] = vals.AndOr
	}
	if req.PresenceGreaterThan != nil && *req.PresenceGreaterThan >= 0 && *req.PresenceGreaterThan <= 100 {
		vals.PresenceGreaterThan = *req.PresenceGreaterThan
		changes["SESelectSppPresent"] = vals.PresenceGreaterThan
	}
	if req.CoverGreaterThan != nil && *req.CoverGreaterThan >= 0 && *req.CoverGreaterThan <= 100 {
		vals.CoverGreaterThan = *req.CoverGreaterThan
		changes["SESelectSppCover"] = vals.CoverGreaterThan
	}

	effectiveUnitType = vals.SiteUnitType
	if effectiveUnitType == 1 && (sel.SU == "" || sel.SU == "None") {
		effectiveUnitType = 3
		fallbackNotice = "No Site Unit table is selected; automatically grouped project plots by Zone, SubZone, and SiteSeries."
	}
	if effectiveUnitType == 2 && (sel.Hierarchy == "" || sel.Hierarchy == "None") {
		if sel.SU != "" && sel.SU != "None" {
			effectiveUnitType = 1
			fallbackNotice = "No Hierarchy is selected; automatically fell back to the active Site Unit table."
		} else {
			effectiveUnitType = 3
			fallbackNotice = "No Hierarchy or Site Unit table is selected; automatically grouped project plots by Zone, SubZone, and SiteSeries."
		}
	}

	switch effectiveUnitType {
	case 1:
		scopeLabel = "Site Unit: " + sel.SU
	case 2:
		scopeLabel = "Hierarchy Breakpoints: " + sel.Hierarchy
	default:
		scopeLabel = "Field-Derived (Zone / SubZone / SiteSeries)"
	}
	return vals, effectiveUnitType, scopeLabel, fallbackNotice, changes
}

// QuickExportSummaryEnvironmentWorkbook runs Summary Environment in one step:
// handles ActiveSU=="None" via field-derived fallback, automatically chooses standard vs extended
// workbook (eliminating the "requires extended summary workbook" error!), writes .xlsx, and optionally opens it.
func QuickExportSummaryEnvironmentWorkbook(
	contexts *vprocore.ContextService,
	ctx context.Context,
	contextID string,
	req QuickSummaryEnvironmentRequest,
) (*QuickEnvReportExportResult, error) {
	if contexts == nil || ctx == nil {
		return nil, errors.New("Summary Environment quick export requires active context")
	}
	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*QuickEnvReportExportResult, error) {
		owner := plots.Projects.Sqlite
		vals, effectiveUnitType, scopeLabel, fallbackNotice, changes := resolveQuickSummaryEnvPrefs(ctx, plots.Projects.Preferences, owner.Selection, req)
		prefsSaved := false
		if shouldSaveQuickEnvPreferences(req.SavePreferences) && len(changes) > 0 && plots.Projects.Preferences != nil {
			if plots.Projects.Preferences.Update("ReportOptions", changes) == nil {
				prefsSaved = true
			}
		}

		var (
			wb      siteUnitSummaryWorkbook
			preview SiteUnitSummaryPreview
		)
		_, err := vprocore.WithOwnedPreferenceSnapshot(ctx, plots, vprocore.PublicationReadSnapshotHooks{}, func(owner *vprocore.SqliteContext, tx *sql.Tx) (struct{}, error) {
			if effectiveUnitType == 1 && owner.Selection.SU != "" && owner.Selection.SU != "None" && owner.Selection.SU != "USysSuTableDynamic" {
				suRows, countErr := activeEnvSUTableRowCount(ctx, tx, owner.Selection.SU)
				if countErr == nil && suRows == 0 {
					if req.SiteUnitType != nil && *req.SiteUnitType == 1 {
						return struct{}{}, fmt.Errorf("Site Unit table %q has no assigned plots. Assign plots to this Site Unit table or switch Site Unit Type to Field-Derived (Zone / SubZone / SiteSeries).", owner.Selection.SU)
					}
					effectiveUnitType = 3
					scopeLabel = "Field-Derived (Zone / SubZone / SiteSeries)"
					fallbackNotice = fmt.Sprintf("Site Unit table %q has no assigned plots; automatically grouped project plots by Zone, SubZone, and SiteSeries.", owner.Selection.SU)
				}
			}
			extended := vals.OrderBy == 2 || vals.IncludeSpecies == 1
			if extended {
				input, rErr := readSiteUnitQuickVegetationSourceWithScope(ctx, owner, tx, contextID, vals.Method, effectiveUnitType)
				if rErr != nil {
					return struct{}{}, rErr
				}
				extOpts := SiteUnitSummaryExtendedWorkbookOptions{
					Method:              vals.Method,
					OrderBy:             vals.OrderBy,
					IncludeSpecies:      vals.IncludeSpecies,
					CoverCalculation:    vals.CoverCalculation,
					AndOr:               vals.AndOr,
					PresenceGreaterThan: vals.PresenceGreaterThan,
					CoverGreaterThan:    vals.CoverGreaterThan,
				}
				if extOpts.IncludeSpecies == 0 {
					extOpts.OrderBy = 2
					extOpts.CoverCalculation = 1
					extOpts.AndOr = 1
					extOpts.PresenceGreaterThan = 0
					extOpts.CoverGreaterThan = 0
				}
				src := siteUnitSummaryExtendedSource{
					Input:   input,
					Options: extOpts,
				}
				w, envPrev, _, pErr := prepareSiteUnitSummaryExtendedSource(ctx, src)
				if pErr != nil {
					return struct{}{}, pErr
				}
				wb = w
				preview = envPrev
				return struct{}{}, nil
			}

			input, rErr := readSiteUnitSummaryWorkbookSourceWithScope(ctx, owner, tx, contextID, vals.Method, effectiveUnitType)
			if rErr != nil {
				return struct{}{}, rErr
			}
			w, wErr := prepareSiteUnitSummaryWorkbook(ctx, input.Preview)
			if wErr != nil {
				return struct{}{}, wErr
			}
			wb = w
			preview = input.Preview
			return struct{}{}, nil
		})
		if err != nil {
			return nil, err
		}

		outPath, shaHex, err := writeQuickEnvWorkbookAtomic(ctx, req.DestinationPath, plots.Projects.Root, owner.Selection.Project, "SummaryEnvironment", wb.Bytes)
		if err != nil {
			return nil, err
		}
		opened, spreadNotice := maybeOpenQuickEnvSpreadsheet(ctx, plots.Projects.Preferences, outPath, req.OpenInSpreadsheet)

		totalPlots := 0
		for _, u := range preview.Report.Units {
			totalPlots += len(u.Plots)
		}
		methodLabel := "Mean"
		if vals.Method == 2 {
			methodLabel = "Interquartile"
		}
		return &QuickEnvReportExportResult{
			ReportKind:          "summary_environment",
			Title:               "Summary Environment (" + methodLabel + ")",
			Project:             preview.Report.Project,
			SU:                  preview.Report.SU,
			ScopeLabel:          scopeLabel,
			FallbackNotice:      fallbackNotice,
			UnitCount:           len(preview.Report.Units),
			PlotCount:           totalPlots,
			Path:                outPath,
			SHA256:              shaHex,
			Bytes:               len(wb.Bytes),
			PreferencesSaved:    prefsSaved,
			OpenedInSpreadsheet: opened,
			SpreadsheetNotice:   spreadNotice,
		}, nil
	})
}

// RenderSummaryEnvironmentHTMLReport renders a self-contained Quarto-style HTML Summary Environment report.
func RenderSummaryEnvironmentHTMLReport(
	contexts *vprocore.ContextService,
	ctx context.Context,
	contextID string,
	req QuickSummaryEnvironmentRequest,
) (*reportcore.HTMLReportResult, error) {
	if contexts == nil || ctx == nil {
		return nil, errors.New("Summary Environment HTML report requires active context")
	}
	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*reportcore.HTMLReportResult, error) {
		owner := plots.Projects.Sqlite
		vals, effectiveUnitType, scopeLabel, fallbackNotice, changes := resolveQuickSummaryEnvPrefs(ctx, plots.Projects.Preferences, owner.Selection, req)
		if shouldSaveQuickEnvPreferences(req.SavePreferences) && len(changes) > 0 && plots.Projects.Preferences != nil {
			_ = plots.Projects.Preferences.Update("ReportOptions", changes)
		}

		var speciesPreview *SiteUnitSpeciesListPreview
		preview, err := vprocore.WithOwnedPreferenceSnapshot(ctx, plots, vprocore.PublicationReadSnapshotHooks{}, func(owner *vprocore.SqliteContext, tx *sql.Tx) (SiteUnitSummaryPreview, error) {
			if effectiveUnitType == 1 && owner.Selection.SU != "" && owner.Selection.SU != "None" && owner.Selection.SU != "USysSuTableDynamic" {
				suRows, countErr := activeEnvSUTableRowCount(ctx, tx, owner.Selection.SU)
				if countErr == nil && suRows == 0 {
					if req.SiteUnitType != nil && *req.SiteUnitType == 1 {
						return SiteUnitSummaryPreview{}, fmt.Errorf("Site Unit table %q has no assigned plots. Assign plots to this Site Unit table or switch Site Unit Type to Field-Derived (Zone / SubZone / SiteSeries).", owner.Selection.SU)
					}
					effectiveUnitType = 3
					scopeLabel = "Field-Derived (Zone / SubZone / SiteSeries)"
					fallbackNotice = fmt.Sprintf("Site Unit table %q has no assigned plots; automatically grouped project plots by Zone, SubZone, and SiteSeries.", owner.Selection.SU)
				}
			}
			if vals.IncludeSpecies == 1 {
				input, rErr := readSiteUnitQuickVegetationSourceWithScope(ctx, owner, tx, contextID, vals.Method, effectiveUnitType)
				if rErr != nil {
					return SiteUnitSummaryPreview{}, rErr
				}
				spPrev, sErr := siteUnitSummarySpeciesPreview(ctx, input, SiteUnitSpeciesListRequest{
					Method:              vals.Method,
					OrderBy:             vals.OrderBy,
					CoverCalculation:    vals.CoverCalculation,
					AndOr:               vals.AndOr,
					PresenceGreaterThan: vals.PresenceGreaterThan,
					CoverGreaterThan:    vals.CoverGreaterThan,
				})
				if sErr != nil {
					return SiteUnitSummaryPreview{}, sErr
				}
				speciesPreview = &spPrev
				return spPrev.Environment, nil
			}
			input, rErr := readSiteUnitSummaryWorkbookSourceWithScope(ctx, owner, tx, contextID, vals.Method, effectiveUnitType)
			if rErr != nil {
				return SiteUnitSummaryPreview{}, rErr
			}
			return input.Preview, nil
		})
		if err != nil {
			return nil, err
		}

		rep := preview.Report
		headers := make([]string, 0, len(rep.Units)+1)
		numCols := make([]bool, 0, len(rep.Units)+1)
		headers = append(headers, "Environmental Attribute")
		numCols = append(numCols, false)
		totalPlots := 0
		for _, u := range rep.Units {
			totalPlots += len(u.Plots)
			headers = append(headers, fmt.Sprintf("%s (n=%d)", u.Code, len(u.Plots)))
			numCols = append(numCols, false)
		}

		rows := make([]reportcore.HTMLReportRow, 0, len(rep.Fields)+4)
		lastSection := ""
		for fIdx, field := range rep.Fields {
			if field.Section != "" && field.Section != lastSection {
				rows = append(rows, reportcore.HTMLReportRow{
					Cells:     []string{field.Section},
					IsHeading: true,
				})
				lastSection = field.Section
			}
			cells := make([]string, 0, len(rep.Units)+1)
			cells = append(cells, field.Label)
			for _, u := range rep.Units {
				val := ""
				if fIdx < len(u.Values) {
					val = u.Values[fIdx]
				}
				cells = append(cells, val)
			}
			rows = append(rows, reportcore.HTMLReportRow{Cells: cells})
		}

		tables := []reportcore.HTMLReportTable{
			{
				Title:       "Site Unit Environmental Summary",
				PlotCount:   totalPlots,
				Headers:     headers,
				NumericCols: numCols,
				Rows:        rows,
			},
		}
		if speciesPreview != nil {
			for _, spUnit := range speciesPreview.Units {
				spRows := make([]reportcore.HTMLReportRow, 0)
				for _, grp := range spUnit.Groups {
					includedRows := make([]SiteUnitSpeciesListRow, 0, len(grp.Rows))
					for _, r := range grp.Rows {
						if r.Included {
							includedRows = append(includedRows, r)
						}
					}
					if len(includedRows) == 0 {
						continue
					}
					if strings.TrimSpace(grp.Caption) != "" {
						spRows = append(spRows, reportcore.HTMLReportRow{
							Cells:     []string{grp.Caption},
							IsHeading: true,
						})
					}
					for _, r := range includedRows {
						spRows = append(spRows, reportcore.HTMLReportRow{
							Cells: []string{
								r.Species,
								reportcore.FormatMetadataCellText(r.ScientificName),
								reportcore.FormatMetadataCellText(r.EnglishName),
								r.Presence,
								r.Cover,
							},
						})
					}
				}
				tables = append(tables, reportcore.HTMLReportTable{
					Title:       "Species Summary — " + spUnit.Code,
					PlotCount:   spUnit.NPlots,
					Headers:     []string{"Species", "Scientific Name", "English Name", "Presence (%)", "Cover (%)"},
					NumericCols: []bool{false, false, false, true, true},
					Rows:        spRows,
				})
			}
		}

		methodLabel := "Mean"
		if vals.Method == 2 {
			methodLabel = "Interquartile"
		}
		rendered, err := reportcore.RenderQuartoHTMLReport(reportcore.HTMLReportDocument{
			Title:      "Summary Environment Report",
			Subtitle:   "Summary method: " + methodLabel,
			ReportKind: "Summary Environment",
			Project:    rep.Project,
			SU:         rep.SU,
			ScopeLabel: scopeLabel,
			UnitCount:  len(rep.Units),
			PlotCount:  totalPlots,
			Notice:     fallbackNotice,
			Tables:     tables,
		})
		if err != nil {
			return nil, err
		}
		return &rendered, nil
	})
}

// QuickExportSubzoneMatrixWorkbook exports the active Hierarchy Subzone Matrix in one step.
func QuickExportSubzoneMatrixWorkbook(
	contexts *vprocore.ContextService,
	ctx context.Context,
	contextID string,
	req QuickSubzoneMatrixRequest,
) (*QuickEnvReportExportResult, error) {
	if contexts == nil || ctx == nil {
		return nil, errors.New("Subzone Matrix quick export requires active context")
	}
	source, err := ReadSubzoneMatrix(contexts, ctx, contextID)
	if err != nil {
		return nil, err
	}
	wb, err := prepareSubzoneMatrixWorkbook(ctx, source)
	if err != nil {
		return nil, err
	}
	var root, project string
	if _, err := vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (struct{}, error) {
		root = plots.Projects.Root
		project = plots.Projects.Sqlite.Selection.Project
		return struct{}{}, nil
	}); err != nil {
		return nil, err
	}
	outPath, shaHex, err := writeQuickEnvWorkbookAtomic(ctx, req.DestinationPath, root, project, "SubzoneMatrix", wb.Bytes)
	if err != nil {
		return nil, err
	}
	opened, spreadNotice := maybeOpenQuickEnvSpreadsheet(ctx, contexts.Projects.Preferences, outPath, req.OpenInSpreadsheet)
	return &QuickEnvReportExportResult{
		ReportKind:          "subzone_matrix",
		Title:               "Subzone Matrix — " + source.Hierarchy,
		Project:             project,
		SU:                  source.Hierarchy,
		ScopeLabel:          "Hierarchy: " + source.Hierarchy,
		UnitCount:           len(source.Matrix.Rows),
		PlotCount:           len(source.Matrix.Columns),
		Path:                outPath,
		SHA256:              shaHex,
		Bytes:               len(wb.Bytes),
		PreferencesSaved:    false,
		OpenedInSpreadsheet: opened,
		SpreadsheetNotice:   spreadNotice,
	}, nil
}

// RenderSubzoneMatrixHTMLReport renders the active Hierarchy Subzone Matrix as a self-contained Quarto HTML table.
func RenderSubzoneMatrixHTMLReport(
	contexts *vprocore.ContextService,
	ctx context.Context,
	contextID string,
) (*reportcore.HTMLReportResult, error) {
	if contexts == nil || ctx == nil {
		return nil, errors.New("Subzone Matrix HTML report requires active context")
	}
	source, err := ReadSubzoneMatrix(contexts, ctx, contextID)
	if err != nil {
		return nil, err
	}
	var project string
	_, _ = vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (struct{}, error) {
		project = plots.Projects.Sqlite.Selection.Project
		return struct{}{}, nil
	})
	headers := make([]string, 0, len(source.Matrix.Columns)+1)
	numCols := make([]bool, 0, len(source.Matrix.Columns)+1)
	headers = append(headers, "Hierarchy Unit")
	numCols = append(numCols, false)
	for _, col := range source.Matrix.Columns {
		headers = append(headers, col)
		numCols = append(numCols, false)
	}
	rows := make([]reportcore.HTMLReportRow, 0, len(source.Matrix.Rows))
	for _, row := range source.Matrix.Rows {
		cells := make([]string, 0, len(source.Matrix.Columns)+1)
		name := ""
		if row.Name != nil {
			name = *row.Name
		}
		cells = append(cells, name)
		for _, v := range row.Values {
			if v != nil {
				cells = append(cells, *v)
			} else {
				cells = append(cells, "")
			}
		}
		rows = append(rows, reportcore.HTMLReportRow{Cells: cells})
	}
	rendered, err := reportcore.RenderQuartoHTMLReport(reportcore.HTMLReportDocument{
		Title:      "Subzone Matrix — " + source.Hierarchy,
		ReportKind: "Subzone Matrix",
		Project:    project,
		SU:         source.Hierarchy,
		ScopeLabel: "Hierarchy: " + source.Hierarchy,
		UnitCount:  len(source.Matrix.Rows),
		PlotCount:  len(source.Matrix.Columns),
		Tables: []reportcore.HTMLReportTable{
			{
				Title:       "Biogeoclimatic Subzone Matrix",
				Headers:     headers,
				NumericCols: numCols,
				Rows:        rows,
			},
		},
	})
	if err != nil {
		return nil, err
	}
	return &rendered, nil
}
