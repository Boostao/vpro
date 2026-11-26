package vegreport

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/boostao/vpro/app/internal/reports/reportcore"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

// QuickVegReportExportResult summarizes a streamlined one-step vegetation workbook export.
type QuickVegReportExportResult struct {
	ReportKind          string `json:"reportKind"`
	Title               string `json:"title"`
	Project             string `json:"project"`
	SU                  string `json:"su"`
	ScopeLabel          string `json:"scopeLabel"`
	FallbackNotice      string `json:"fallbackNotice,omitempty"`
	UnitCount           int    `json:"unitCount"`
	PlotCount           int    `json:"plotCount"`
	RowCount            int    `json:"rowCount"`
	Path                string `json:"path"`
	SHA256              string `json:"sha256"`
	Bytes               int    `json:"bytes"`
	PreferencesSaved    bool   `json:"preferencesSaved"`
	OpenedInSpreadsheet bool   `json:"openedInSpreadsheet"`
	SpreadsheetNotice   string `json:"spreadsheetNotice,omitempty"`
}

// QuickSummaryVegetationRequest configures one-step Summary Vegetation HTML or XLSX generation.
type QuickSummaryVegetationRequest struct {
	Title             *string  `json:"title,omitempty"`
	Average           *int     `json:"average,omitempty"`
	Display           *int     `json:"display,omitempty"`
	ShowClass         *int     `json:"showClass,omitempty"`
	GroupBy           *int     `json:"groupBy,omitempty"`
	UnitScope         string   `json:"unitScope,omitempty"` // "auto" | "su" | "none" | "field" | "hierarchy"
	UnitField         string   `json:"unitField,omitempty"`
	ShowCommon        *bool    `json:"showCommon,omitempty"`
	ShowGuide         *bool    `json:"showGuide,omitempty"`
	IncludeEnv        *bool    `json:"includeEnv,omitempty"`
	CreateSummary     *bool    `json:"createSummary,omitempty"`
	CombineVariants   *bool    `json:"combineVariants,omitempty"`
	Constancy         *bool    `json:"constancy,omitempty"`
	HierarchyHeader   *bool    `json:"hierarchyHeader,omitempty"`
	LumpTable         *string  `json:"lumpTable,omitempty"`
	ValueLimit        *float64 `json:"valueLimit,omitempty"`
	SavePreferences   *bool    `json:"savePreferences,omitempty"`
	DestinationPath   string   `json:"destinationPath,omitempty"`
	OpenInSpreadsheet bool     `json:"openInSpreadsheet,omitempty"`
}

func (r *QuickSummaryVegetationRequest) UnmarshalJSON(data []byte) error {
	type plain QuickSummaryVegetationRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

// QuickLongVegetationRequest configures one-step Long Vegetation HTML or XLSX generation.
type QuickLongVegetationRequest struct {
	Title                *string  `json:"title,omitempty"`
	Grouping             string   `json:"grouping,omitempty"` // "layer" | "strata" | "lifeform" | "none"
	Average              string   `json:"average,omitempty"`  // "all-plots" | "non-zero"
	Order                string   `json:"order,omitempty"`    // "presence" | "mean-cover" | "species"
	ShowEnglishName      *bool    `json:"showEnglishName,omitempty"`
	ShowSpeciesCode      *bool    `json:"showSpeciesCode,omitempty"`
	ConstantSpeciesList  *bool    `json:"constantSpeciesList,omitempty"`
	PresenceGreaterThan  *float64 `json:"presenceGreaterThan,omitempty"`
	MeanCoverGreaterThan *float64 `json:"meanCoverGreaterThan,omitempty"`
	CombineVariants      *bool    `json:"combineVariants,omitempty"`
	LumpTable            *string  `json:"lumpTable,omitempty"`
	ScopeMode            string   `json:"scopeMode,omitempty"` // "auto" | "su" | "zone-subzone" | "all-plots"
	SavePreferences      *bool    `json:"savePreferences,omitempty"`
	DestinationPath      string   `json:"destinationPath,omitempty"`
	OpenInSpreadsheet    bool     `json:"openInSpreadsheet,omitempty"`
}

func (r *QuickLongVegetationRequest) UnmarshalJSON(data []byte) error {
	type plain QuickLongVegetationRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

// QuickLifeformReportRequest configures one-step Lifeform & Species Attribute HTML or XLSX generation.
type QuickLifeformReportRequest struct {
	ScopeMode         string `json:"scopeMode,omitempty"` // "auto" | "su" | "zone-subzone" | "all-plots"
	Details           []bool `json:"details,omitempty"`
	DestinationPath   string `json:"destinationPath,omitempty"`
	OpenInSpreadsheet bool   `json:"openInSpreadsheet,omitempty"`
}

func (r *QuickLifeformReportRequest) UnmarshalJSON(data []byte) error {
	type plain QuickLifeformReportRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

func shouldSaveQuickPreferences(flag *bool) bool {
	return flag == nil || *flag
}

func defaultQuickExportPath(root, project, reportSlug string) string {
	stamp := time.Now().Format("20060102-150405")
	safeProj := strings.TrimSpace(project)
	if safeProj == "" {
		safeProj = "VPro"
	}
	return filepath.Join(root, "exports", fmt.Sprintf("%s_%s_%s.xlsx", safeProj, reportSlug, stamp))
}

func writeQuickWorkbookAtomic(ctx context.Context, requestedPath, root, project, reportSlug string, data []byte) (string, string, error) {
	if err := ctx.Err(); err != nil {
		return "", "", err
	}
	dest := strings.TrimSpace(requestedPath)
	if dest == "" {
		dest = defaultQuickExportPath(root, project, reportSlug)
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
	tmp, err := os.CreateTemp(filepath.Dir(resolved), ".vpro-report-*.xlsx")
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

func maybeOpenInSpreadsheetApp(ctx context.Context, prefs *vprocore.DesktopConfig, xlsxPath string, requested bool) (bool, string) {
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

func buildQuickEnvFallbackSUTable(ctx context.Context, env vprocore.ProjectMetadataTable, scopeMode string) (
	suTable vprocore.ProjectMetadataTable, syntheticSU string, scopeLabel string, notice string, err error,
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
		// Prefer Zone/SubZone/SiteSeries grouping if any plot has Zone or SubZone populated.
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
			{Name: "PlotNumber", DeclaredType: "VARCHAR"},
			{Name: "SiteUnit", DeclaredType: "VARCHAR"},
		},
		Rows: make([]vprocore.ProjectMetadataRow, 0, len(env.Rows)),
	}
	seen := map[string]bool{}
	for _, row := range env.Rows {
		if err := ctx.Err(); err != nil {
			return vprocore.ProjectMetadataTable{}, "", "", "", err
		}
		plotCell := row.Cells[ec["PlotNumber"]]
		plotStr, err := vprocore.VegetationReportIdentity(plotCell)
		if err != nil {
			return vprocore.ProjectMetadataTable{}, "", "", "", err
		}
		if plotStr == nil || strings.TrimSpace(*plotStr) == "" || seen[*plotStr] {
			continue
		}
		seen[*plotStr] = true

		unitCode := "All Plots"
		if mode == "zone-subzone" {
			z := ""
			sz := ""
			ss := ""
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

func activeSUTableRowCount(ctx context.Context, tx *sql.Tx, suName string) (int, error) {
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

func formatEmptySUFallbackNotice(suName, baseNotice string) string {
	prefix := fmt.Sprintf("Site Unit table %q has no assigned plots;", suName)
	if strings.HasPrefix(baseNotice, "No Site Unit table is selected;") {
		return prefix + strings.TrimPrefix(baseNotice, "No Site Unit table is selected;")
	}
	if strings.TrimSpace(baseNotice) != "" {
		return prefix + " " + baseNotice
	}
	return prefix + " automatically included all project plots."
}

// resolveQuickSummaryOptions merges saved preferences, request overrides, and ActiveSU=="None" fallback.
func resolveQuickSummaryOptions(
	ctx context.Context,
	prefs *vprocore.DesktopConfig,
	sel vprocore.DesktopSelection,
	req QuickSummaryVegetationRequest,
) (opts SummaryVegetationWorkbookOptions, valueLimit float64, scopeLabel, fallbackNotice string, prefsToSave map[string]any, err error) {
	saved, err := readSummarySavedPresentationState(ctx, prefs, sel.SU)
	if err != nil {
		saved = SummaryVegetationAppliedPreferences{
			Title:     "Summary Vegetation Report",
			Average:   1,
			Display:   6,
			GroupBy:   1,
			UnitScope: "su",
		}
	}
	if strings.TrimSpace(saved.Title) == "" {
		saved.Title = "Summary Vegetation Report"
	}
	if saved.Average != 1 && saved.Average != 2 {
		saved.Average = 1
	}
	if saved.Display < 1 || saved.Display > 6 {
		saved.Display = 6
	}
	if saved.GroupBy < 1 || saved.GroupBy > 4 {
		saved.GroupBy = 1
	}

	changes := map[string]any{}
	if req.Title != nil {
		saved.Title = strings.TrimSpace(*req.Title)
		if saved.Title == "" {
			saved.Title = "Summary Vegetation Report"
		}
		changes["SVReportTitle"] = saved.Title
	}
	if req.Average != nil && (*req.Average == 1 || *req.Average == 2) {
		saved.Average = *req.Average
		changes["SVAvgType"] = saved.Average
	}
	if req.Display != nil && *req.Display >= 1 && *req.Display <= 6 {
		saved.Display = *req.Display
		changes["SVValue"] = saved.Display
	}
	if req.ShowClass != nil {
		saved.ShowClass = *req.ShowClass
		changes["SVShowClass"] = saved.ShowClass
	}
	if req.GroupBy != nil && *req.GroupBy >= 1 && *req.GroupBy <= 4 {
		saved.GroupBy = *req.GroupBy
		changes["SVGroupBy"] = saved.GroupBy
	}
	if req.ShowCommon != nil {
		saved.ShowCommon = *req.ShowCommon
		changes["SVShowEnglishName"] = boolToAccessInt(*req.ShowCommon)
	}
	if req.ShowGuide != nil {
		saved.ShowGuide = *req.ShowGuide
		changes["SVShowGuideName"] = boolToAccessInt(*req.ShowGuide)
	}
	if req.IncludeEnv != nil {
		saved.IncludeEnv = *req.IncludeEnv
		changes["SVIncludeEnvFields"] = boolToAccessInt(*req.IncludeEnv)
	}
	if req.CreateSummary != nil {
		saved.CreateSummary = *req.CreateSummary
		changes["SVReportSummary"] = boolToAccessInt(*req.CreateSummary)
	}
	if req.CombineVariants != nil {
		saved.CombineVariants = *req.CombineVariants
		changes["SVSubSppAsSpp"] = boolToAccessInt(*req.CombineVariants)
	}
	if req.Constancy != nil {
		saved.Constancy = *req.Constancy
		changes["SVConstancyFormat"] = boolToAccessInt(*req.Constancy)
	}
	if req.HierarchyHeader != nil {
		saved.HierarchyHeader = *req.HierarchyHeader
		changes["SVShowHierarchyHeader"] = boolToAccessInt(*req.HierarchyHeader)
	}
	if req.LumpTable != nil {
		trimmed := strings.TrimSpace(*req.LumpTable)
		if strings.EqualFold(trimmed, "None") || strings.EqualFold(trimmed, "None_Lump") {
			saved.LumpTable = ""
		} else {
			saved.LumpTable = trimmed
		}
	}
	if req.ValueLimit != nil && *req.ValueLimit >= 0 {
		saved.ValueLimit = *req.ValueLimit
		changes["SVShowValOpt"] = int(*req.ValueLimit)
	}

	reqScope := strings.ToLower(strings.TrimSpace(req.UnitScope))
	if reqScope != "" && reqScope != "auto" {
		saved.UnitScope = reqScope
	}
	if strings.TrimSpace(req.UnitField) != "" {
		saved.UnitField = strings.TrimSpace(req.UnitField)
	}

	// Graceful fallback when ActiveSU == "None" or ActiveHierarchy == "None".
	if saved.UnitScope == "" || saved.UnitScope == "auto" {
		if sel.SU != "" && sel.SU != "None" {
			saved.UnitScope = "su"
		} else if saved.UnitField != "" {
			saved.UnitScope = "field"
		} else {
			saved.UnitScope = "none"
		}
	}
	if saved.UnitScope == "su" && (sel.SU == "" || sel.SU == "None") {
		if saved.UnitField != "" {
			saved.UnitScope = "field"
			fallbackNotice = fmt.Sprintf("No Site Unit table is selected; automatically grouped project plots by %s.", saved.UnitField)
		} else {
			saved.UnitScope = "none"
			fallbackNotice = "No Site Unit table is selected; automatically summarized all project plots."
		}
	} else if (sel.SU == "" || sel.SU == "None") && (reqScope == "" || reqScope == "auto" || reqScope == "su") {
		if saved.UnitScope == "field" && saved.UnitField != "" {
			fallbackNotice = fmt.Sprintf("No Site Unit table is selected; automatically grouped project plots by %s.", saved.UnitField)
		} else {
			fallbackNotice = "No Site Unit table is selected; automatically summarized all project plots."
		}
	}
	if saved.UnitScope == "hierarchy" && (sel.Hierarchy == "" || sel.Hierarchy == "None") {
		if sel.SU != "" && sel.SU != "None" {
			saved.UnitScope = "su"
			fallbackNotice = "No Hierarchy is selected; automatically fell back to the active Site Unit table."
		} else {
			saved.UnitScope = "none"
			fallbackNotice = "No Hierarchy or Site Unit table is selected; automatically summarized all project plots."
		}
	}
	if saved.UnitScope == "field" && saved.UnitField == "" {
		saved.UnitField = "Zone"
	}

	switch saved.UnitScope {
	case "su":
		scopeLabel = "Site Unit: " + sel.SU
	case "hierarchy":
		scopeLabel = "Hierarchy: " + sel.Hierarchy
	case "field":
		scopeLabel = "Field-Derived: " + saved.UnitField
	default:
		scopeLabel = "All Project Plots"
	}

	group := summaryGroupByToGroupAndOrder(saved.GroupBy)
	showClass := saved.ShowClass
	if (saved.Display == 4 || saved.Display == 5) && showClass == 0 {
		showClass = 1
	}
	if saved.Display != 4 && saved.Display != 5 {
		showClass = 0
	}

	opts = SummaryVegetationWorkbookOptions{
		Title:      saved.Title,
		Average:    saved.Average,
		Display:    saved.Display,
		ShowClass:  showClass,
		IncludeEnv: saved.IncludeEnv,
		UnitScope:  saved.UnitScope,
		UnitField:  saved.UnitField,
	}
	if saved.CreateSummary {
		opts.Ancillary = &SummaryVegetationWorkbookAncillaryOptions{CreateSummary: true}
	}
	if group != 11 {
		opts.GroupAndOrder = &group
	}
	if saved.Constancy {
		g := 13
		opts.GroupAndOrder = &g
		opts.Display = 1
		opts.ShowClass = 0
		opts.Constancy = true
		opts.References = &SummaryVegetationReferenceOptions{}
	} else if saved.ShowCommon || saved.ShowGuide {
		if group == 11 || group == 12 {
			opts.References = &SummaryVegetationReferenceOptions{
				ShowCommon:    saved.ShowCommon || saved.ShowGuide,
				UseGuideNames: saved.ShowGuide,
			}
		} else if saved.Display == 6 {
			opts.UnanimousCommon = true
			opts.References = &SummaryVegetationReferenceOptions{
				ShowCommon:    saved.ShowCommon || saved.ShowGuide,
				UseGuideNames: saved.ShowGuide,
			}
		}
	}
	if saved.HierarchyHeader && sel.Hierarchy != "" && sel.Hierarchy != "None" {
		hh := true
		opts.HierarchyHeader = &hh
	}
	if saved.CombineVariants {
		cv := true
		opts.CombineVariants = &cv
	}
	if saved.LumpTable != "" {
		opts.LumpTable = saved.LumpTable
	}
	return opts, saved.ValueLimit, scopeLabel, fallbackNotice, changes, nil
}

func boolToAccessInt(v bool) int {
	if v {
		return -1
	}
	return 0
}

// QuickExportSummaryVegetationWorkbook runs Summary Vegetation in a single step:
// loads saved preferences, applies overrides, persists updated preferences, handles ActiveSU=="None",
// writes the .xlsx file atomically, and optionally launches the user's spreadsheet application.
func (s *SummaryVegetationWorkbookService) QuickExportWorkbook(
	ctx context.Context,
	contextID string,
	req QuickSummaryVegetationRequest,
) (*QuickVegReportExportResult, error) {
	if err := s.authorize(ctx); err != nil {
		return nil, err
	}
	contexts := s.source.environment.report.contexts
	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*QuickVegReportExportResult, error) {
		owner := plots.Projects.Sqlite
		opts, _, scopeLabel, fallbackNotice, prefChanges, err := resolveQuickSummaryOptions(ctx, plots.Projects.Preferences, owner.Selection, req)
		if err != nil {
			return nil, err
		}
		prefsSaved := false
		if shouldSaveQuickPreferences(req.SavePreferences) && len(prefChanges) > 0 && plots.Projects.Preferences != nil {
			if err := plots.Projects.Preferences.Update("ReportOptions", prefChanges); err == nil {
				prefsSaved = true
			}
		}

		var (
			workbook summaryVegetationWorkbook
			preview  SummaryVegetationPreview
		)
		err = func() error {
			_, snapErr := vprocore.WithOwnedPreferenceSnapshot(ctx, plots, vprocore.PublicationReadSnapshotHooks{}, func(owner *vprocore.SqliteContext, tx *sql.Tx) (struct{}, error) {
				if opts.UnitScope == "su" && owner.Selection.SU != "" && owner.Selection.SU != "None" {
					suRows, countErr := activeSUTableRowCount(ctx, tx, owner.Selection.SU)
					if countErr == nil && suRows == 0 {
						if strings.EqualFold(strings.TrimSpace(req.UnitScope), "su") {
							return struct{}{}, fmt.Errorf("Site Unit table %q has no assigned plots. Assign plots to this Site Unit table or switch Unit Scope to Auto, Field-Derived, or All Project Plots.", owner.Selection.SU)
						}
						if opts.UnitField != "" {
							opts.UnitScope = "field"
							scopeLabel = "Field-Derived: " + opts.UnitField
							fallbackNotice = fmt.Sprintf("Site Unit table %q has no assigned plots; automatically grouped project plots by %s.", owner.Selection.SU, opts.UnitField)
						} else {
							opts.UnitScope = "none"
							scopeLabel = "All Project Plots"
							fallbackNotice = fmt.Sprintf("Site Unit table %q has no assigned plots; automatically summarized all project plots.", owner.Selection.SU)
						}
					}
				}
				createdAt := ""
				if opts.Ancillary != nil {
					createdAt = time.Now().UTC().Format(time.RFC3339)
				}
				src, rErr := s.readSourceAt(ctx, plots, owner, tx, contextID, opts, createdAt)
				if rErr != nil {
					return struct{}{}, rErr
				}
				wb, wErr := prepareSummaryWorkbookSource(ctx, src, opts)
				if wErr != nil {
					return struct{}{}, wErr
				}
				workbook = wb
				preview = src.Input.Vegetation
				return struct{}{}, nil
			})
			return snapErr
		}()
		if err != nil {
			return nil, err
		}

		outPath, shaHex, err := writeQuickWorkbookAtomic(ctx, req.DestinationPath, plots.Projects.Root, owner.Selection.Project, "SummaryVegetation", workbook.Bytes)
		if err != nil {
			return nil, err
		}
		opened, spreadNotice := maybeOpenInSpreadsheetApp(ctx, plots.Projects.Preferences, outPath, req.OpenInSpreadsheet)

		totalPlots := 0
		for _, u := range preview.Units {
			totalPlots += u.NumPlots
		}
		return &QuickVegReportExportResult{
			ReportKind:          "summary_vegetation",
			Title:               opts.Title,
			Project:             preview.Project,
			SU:                  preview.SU,
			ScopeLabel:          scopeLabel,
			FallbackNotice:      fallbackNotice,
			UnitCount:           len(preview.Units),
			PlotCount:           totalPlots,
			RowCount:            len(preview.Rows),
			Path:                outPath,
			SHA256:              shaHex,
			Bytes:               len(workbook.Bytes),
			PreferencesSaved:    prefsSaved,
			OpenedInSpreadsheet: opened,
			SpreadsheetNotice:   spreadNotice,
		}, nil
	})
}

// RenderSummaryVegetationHTMLReport renders a self-contained Quarto-style HTML Summary Vegetation report.
func (s *SummaryVegetationService) RenderHTMLReport(
	ctx context.Context,
	contextID string,
	req QuickSummaryVegetationRequest,
) (*reportcore.HTMLReportResult, error) {
	if s == nil || s.contexts == nil || ctx == nil {
		return nil, errors.New("Summary Vegetation HTML report requires active context")
	}
	return vprocore.WithContextPlotRequest(ctx, s.contexts, contextID, func(plots *vprocore.PlotService) (*reportcore.HTMLReportResult, error) {
		owner := plots.Projects.Sqlite
		opts, valueLimit, scopeLabel, fallbackNotice, prefChanges, err := resolveQuickSummaryOptions(ctx, plots.Projects.Preferences, owner.Selection, req)
		if err != nil {
			return nil, err
		}
		if shouldSaveQuickPreferences(req.SavePreferences) && len(prefChanges) > 0 && plots.Projects.Preferences != nil {
			_ = plots.Projects.Preferences.Update("ReportOptions", prefChanges)
		}

		groupAndOrder := 11
		if opts.GroupAndOrder != nil {
			groupAndOrder = *opts.GroupAndOrder
		}
		mode := summaryVegetationGroupedOrdinary
		if opts.Constancy {
			mode = summaryVegetationGroupedConstancy
		} else if opts.UnanimousCommon {
			mode = summaryVegetationGroupedUnanimousCommon
		}
		cfgReq := SummaryVegetationConfiguredRequest{
			UnitScope:       opts.UnitScope,
			UnitField:       opts.UnitField,
			HierarchyHeader: opts.HierarchyHeader,
			CombineVariants: opts.CombineVariants,
		}
		if opts.LumpTable != "" {
			lt := opts.LumpTable
			cfgReq.LumpTable = &lt
		}

		preview, err := vprocore.WithOwnedPreferenceSnapshot(ctx, plots, s.snapshot, func(owner *vprocore.SqliteContext, tx *sql.Tx) (SummaryVegetationPreview, error) {
			if cfgReq.UnitScope == "su" && owner.Selection.SU != "" && owner.Selection.SU != "None" {
				suRows, countErr := activeSUTableRowCount(ctx, tx, owner.Selection.SU)
				if countErr == nil && suRows == 0 {
					if strings.EqualFold(strings.TrimSpace(req.UnitScope), "su") {
						return SummaryVegetationPreview{}, fmt.Errorf("Site Unit table %q has no assigned plots. Assign plots to this Site Unit table or switch Unit Scope to Auto, Field-Derived, or All Project Plots.", owner.Selection.SU)
					}
					if cfgReq.UnitField != "" {
						cfgReq.UnitScope = "field"
						scopeLabel = "Field-Derived: " + cfgReq.UnitField
						fallbackNotice = fmt.Sprintf("Site Unit table %q has no assigned plots; automatically grouped project plots by %s.", owner.Selection.SU, cfgReq.UnitField)
					} else {
						cfgReq.UnitScope = "none"
						scopeLabel = "All Project Plots"
						fallbackNotice = fmt.Sprintf("Site Unit table %q has no assigned plots; automatically summarized all project plots.", owner.Selection.SU)
					}
				}
			}
			snap, rErr := s.readSnapshotConfigured(ctx, contextID, plots, owner, tx,
				opts.Average, opts.Display, opts.ShowClass, groupAndOrder, opts.References, mode, cfgReq, nil, valueLimit)
			if rErr != nil {
				return SummaryVegetationPreview{}, rErr
			}
			return snap.Preview, nil
		})
		if err != nil {
			return nil, err
		}

		headers := []string{"Layer", "Species"}
		numericCols := []bool{false, false}
		hasCommon := false
		for _, r := range preview.Rows {
			if r.CommonName != nil && strings.TrimSpace(reportcore.FormatMetadataCellText(*r.CommonName)) != "" {
				hasCommon = true
				break
			}
		}
		if hasCommon {
			headers = append(headers, "Common Name")
			numericCols = append(numericCols, false)
		}
		totalPlots := 0
		for _, u := range preview.Units {
			totalPlots += u.NumPlots
			headers = append(headers, fmt.Sprintf("%s (n=%d)", u.Code, u.NumPlots))
			numericCols = append(numericCols, true)
		}
		rows := make([]reportcore.HTMLReportRow, 0, len(preview.Rows))
		for _, r := range preview.Rows {
			cells := []string{
				reportcore.FormatMetadataCellText(r.Layer),
				reportcore.FormatMetadataCellText(r.Species),
			}
			if hasCommon {
				cn := ""
				if r.CommonName != nil {
					cn = reportcore.FormatMetadataCellText(*r.CommonName)
				}
				cells = append(cells, cn)
			}
			for _, cov := range r.Covers {
				cells = append(cells, reportcore.FormatMetadataCellText(cov))
			}
			rows = append(rows, reportcore.HTMLReportRow{Cells: cells})
		}

		rendered, err := reportcore.RenderQuartoHTMLReport(reportcore.HTMLReportDocument{
			Title:      opts.Title,
			ReportKind: "Summary Vegetation",
			Project:    preview.Project,
			SU:         preview.SU,
			ScopeLabel: scopeLabel,
			UnitCount:  len(preview.Units),
			PlotCount:  totalPlots,
			Notice:     fallbackNotice,
			Badges: []reportcore.HTMLReportBadge{
				{Label: "Species Rows", Value: strconv.Itoa(len(preview.Rows))},
			},
			Tables: []reportcore.HTMLReportTable{
				{
					Title:       "Vegetation Summary Table",
					PlotCount:   totalPlots,
					Headers:     headers,
					NumericCols: numericCols,
					Rows:        rows,
				},
			},
		})
		if err != nil {
			return nil, err
		}
		return &rendered, nil
	})
}

func resolveQuickLongVegOptions(
	ctx context.Context,
	contexts *vprocore.ContextService,
	plots *vprocore.PlotService,
	tx *sql.Tx,
	req QuickLongVegetationRequest,
) (options longVegetationOptions, layout vegetationWorkbookLayout, prefChanges map[string]any, err error) {
	values, err := plots.Projects.Preferences.Snapshot()
	if err != nil {
		return longVegetationOptions{}, vegetationWorkbookLayout{}, nil, err
	}
	options, err = DecodeOwnedLongVegetationOptions(contexts, ctx, plots, tx, values)
	if err != nil {
		// Fall back to clean defaults if legacy/partial preferences fail strict decode.
		options = longVegetationOptions{
			Title:           "Long Vegetation Report",
			Average:         "all-plots",
			Order:           "presence",
			ShowEnglishName: true,
		}
	}
	layout, err = decodeVegetationWorkbookLayout(values)
	if err != nil {
		layout = vegetationWorkbookLayout{QuickReport: true, ReportSummary: true}
	}
	if strings.TrimSpace(options.Title) == "" {
		options.Title = "Long Vegetation Report"
	}

	prefChanges = map[string]any{}
	if req.Title != nil {
		options.Title = strings.TrimSpace(*req.Title)
		if options.Title == "" {
			options.Title = "Long Vegetation Report"
		}
		prefChanges["LVReportTitle"] = options.Title
	}
	if g := strings.ToLower(strings.TrimSpace(req.Grouping)); g != "" {
		options.NoneGrouping, options.LifeformGrouping, options.StrataGrouping = false, false, false
		switch g {
		case "layer":
			prefChanges["LVGroupBy"] = 1
		case "strata":
			options.StrataGrouping = true
			prefChanges["LVGroupBy"] = 2
		case "lifeform":
			options.LifeformGrouping = true
			prefChanges["LVGroupBy"] = 3
		case "none":
			options.NoneGrouping = true
			prefChanges["LVGroupBy"] = 4
		}
	}
	if avg := strings.ToLower(strings.TrimSpace(req.Average)); avg != "" {
		switch avg {
		case "all-plots", "all":
			options.Average = "all-plots"
			prefChanges["LVAvgType"] = 10
		case "non-zero", "nonzero":
			options.Average = "non-zero"
			prefChanges["LVAvgType"] = 20
		}
	}
	if ord := strings.ToLower(strings.TrimSpace(req.Order)); ord != "" {
		switch ord {
		case "presence":
			options.Order = "presence"
			prefChanges["LVOrderBy"] = 10
		case "mean-cover", "cover":
			options.Order = "mean-cover"
			prefChanges["LVOrderBy"] = 20
		case "species":
			options.Order = "species"
			prefChanges["LVOrderBy"] = 30
		}
	}
	if req.ShowEnglishName != nil {
		options.ShowEnglishName = *req.ShowEnglishName
		prefChanges["LVShowEnglishName"] = boolToAccessInt(*req.ShowEnglishName)
	}
	if req.ShowSpeciesCode != nil {
		options.ShowSpeciesCode = *req.ShowSpeciesCode
		prefChanges["LVUseSppCodesOnly"] = boolToAccessInt(*req.ShowSpeciesCode)
	}
	if req.ConstantSpeciesList != nil {
		options.ConstantSpeciesList = *req.ConstantSpeciesList
		prefChanges["LVConstantSppList"] = boolToAccessInt(*req.ConstantSpeciesList)
	}
	if req.PresenceGreaterThan != nil && *req.PresenceGreaterThan >= 0 {
		options.PresenceGreaterThan = *req.PresenceGreaterThan
		prefChanges["LVPresenceGreaterThan"] = int(*req.PresenceGreaterThan)
	}
	if req.MeanCoverGreaterThan != nil && *req.MeanCoverGreaterThan >= 0 {
		options.MeanCoverGreaterThan = *req.MeanCoverGreaterThan
		prefChanges["LVCoverGreaterThan"] = int(*req.MeanCoverGreaterThan)
	}
	if req.CombineVariants != nil {
		options.CombineVariants = *req.CombineVariants
	}
	if req.LumpTable != nil {
		options.LumpTable = strings.TrimSpace(*req.LumpTable)
	}
	return options, layout, prefChanges, nil
}

func buildQuickLongVegetationPreview(
	contexts *vprocore.ContextService,
	ctx context.Context,
	contextID string,
	req QuickLongVegetationRequest,
) (
	preview LongVegetationPreview,
	layout vegetationWorkbookLayout,
	scopeLabel string,
	fallbackNotice string,
	prefsSaved bool,
	root string,
	err error,
) {
	err = func() error {
		_, callErr := vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (struct{}, error) {
			root = plots.Projects.Root
			var prefChanges map[string]any
			_, snapErr := vprocore.WithOwnedPreferenceSnapshot(ctx, plots, vprocore.PublicationReadSnapshotHooks{}, func(owner *vprocore.SqliteContext, tx *sql.Tx) (struct{}, error) {
				options, lay, changes, optErr := resolveQuickLongVegOptions(ctx, contexts, plots, tx, req)
				if optErr != nil {
					return struct{}{}, optErr
				}
				layout = lay
				prefChanges = changes

				scopeMode := strings.ToLower(strings.TrimSpace(req.ScopeMode))
				useActiveSU := owner.Selection.SU != "" && owner.Selection.SU != "None" &&
					(scopeMode == "" || scopeMode == "auto" || scopeMode == "su")
				emptyActiveSUName := ""
				if useActiveSU {
					suRows, countErr := activeSUTableRowCount(ctx, tx, owner.Selection.SU)
					if countErr == nil && suRows == 0 {
						if scopeMode == "su" {
							return struct{}{}, fmt.Errorf("Site Unit table %q has no assigned plots. Assign plots to this Site Unit table or switch Scope to Auto, Zone/SubZone, or All Project Plots.", owner.Selection.SU)
						}
						emptyActiveSUName = owner.Selection.SU
						useActiveSU = false
					}
				}

				if useActiveSU {
					source, rErr := readLongVegetationReportSource(ctx, owner, tx, options)
					if rErr != nil {
						return struct{}{}, rErr
					}
					options.resolvedLumpTable = source.LumpTable
					transport, tErr := longVegetationTransport(ctx, source.Report)
					if tErr != nil {
						return struct{}{}, tErr
					}
					preview = LongVegetationPreview{
						ContextID:   contextID,
						ProjectPath: owner.Selection.ProjectPath,
						SUPath:      owner.Selection.SUPath,
						Settings:    vegetationSettings(options),
						Report:      transport,
					}
					scopeLabel = "Site Unit: " + owner.Selection.SU
					return struct{}{}, nil
				}

				// ActiveSU == "None" (or explicit fallback scope): synthesize SU table from Env!
				veg, rErr := summaryReadRequiredTable(ctx, tx, "project", owner.Selection.Project+"_Veg")
				if rErr != nil {
					return struct{}{}, rErr
				}
				env, rErr := summaryReadRequiredTable(ctx, tx, "project", owner.Selection.Project+"_Env")
				if rErr != nil {
					return struct{}{}, rErr
				}
				species, rErr := summaryReadRequiredTable(ctx, tx, "VLists", "USysAllSpecs")
				if rErr != nil {
					return struct{}{}, rErr
				}
				layers, rErr := summaryReadRequiredTable(ctx, tx, "VPro64", "LayerCode")
				if rErr != nil {
					return struct{}{}, rErr
				}
				master, rErr := summaryReadRequiredTable(ctx, tx, "VLists", "MasterSiteUnitList")
				if rErr != nil {
					return struct{}{}, rErr
				}
				var personal vprocore.ProjectMetadataTable
				if options.LifeformGrouping {
					personal, rErr = summaryReadRequiredTable(ctx, tx, "VUser", "USysUserSpp")
					if rErr != nil {
						return struct{}{}, rErr
					}
				}
				suTable, syntheticSU, sLabel, notice, fErr := buildQuickEnvFallbackSUTable(ctx, env, scopeMode)
				if fErr != nil {
					return struct{}{}, fErr
				}
				scopeLabel = sLabel
				if emptyActiveSUName != "" {
					fallbackNotice = formatEmptySUFallbackNotice(emptyActiveSUName, notice)
				} else {
					fallbackNotice = notice
				}

				prepared, pErr := prepareLongVegetation(ctx, owner.Selection.Project, syntheticSU, veg, suTable, layers)
				if pErr != nil {
					return struct{}{}, pErr
				}
				lumpPlan, lErr := loadLongVegetationLumpPlan(ctx, tx, species, options.LumpTable, options.CombineVariants)
				if lErr != nil {
					return struct{}{}, lErr
				}
				options.resolvedLumpTable = lumpPlan.TableLabel
				options.lumpMap = lumpPlan.ActiveMap
				options.lumpRows = lumpPlan.Rows

				report, planErr := planLongVegetationPreparedSource(ctx, prepared, species, personal, layers, options)
				if planErr != nil {
					return struct{}{}, planErr
				}
				if err := addLongVegetationUnitNames(ctx, &report, master); err != nil {
					return struct{}{}, err
				}
				transport, tErr := longVegetationTransport(ctx, report)
				if tErr != nil {
					return struct{}{}, tErr
				}
				preview = LongVegetationPreview{
					ContextID:   contextID,
					ProjectPath: owner.Selection.ProjectPath,
					SUPath:      owner.Selection.ProjectPath,
					Settings:    vegetationSettings(options),
					Report:      transport,
				}
				return struct{}{}, nil
			})
			if snapErr != nil {
				return struct{}{}, snapErr
			}
			if shouldSaveQuickPreferences(req.SavePreferences) && len(prefChanges) > 0 && plots.Projects.Preferences != nil {
				if plots.Projects.Preferences.Update("ReportOptions", prefChanges) == nil {
					prefsSaved = true
				}
			}
			return struct{}{}, nil
		})
		return callErr
	}()
	return preview, layout, scopeLabel, fallbackNotice, prefsSaved, root, err
}

// QuickExportLongVegetationWorkbook runs Long Vegetation in one step with automatic ActiveSU=="None" fallback.
func QuickExportLongVegetationWorkbook(
	contexts *vprocore.ContextService,
	ctx context.Context,
	contextID string,
	req QuickLongVegetationRequest,
) (*QuickVegReportExportResult, error) {
	if contexts == nil || ctx == nil {
		return nil, errors.New("Long Vegetation quick export requires active context")
	}
	preview, layout, scopeLabel, fallbackNotice, prefsSaved, root, err := buildQuickLongVegetationPreview(contexts, ctx, contextID, req)
	if err != nil {
		return nil, err
	}
	layout.ReportSummary = false
	layout.Summary = nil
	wb, err := prepareLongVegetationWorkbook(ctx, preview, layout)
	if err != nil {
		return nil, err
	}
	outPath, shaHex, err := writeQuickWorkbookAtomic(ctx, req.DestinationPath, root, preview.Report.Project, "LongVegetation", wb.Bytes)
	if err != nil {
		return nil, err
	}
	opened, spreadNotice := maybeOpenInSpreadsheetApp(ctx, contexts.Projects.Preferences, outPath, req.OpenInSpreadsheet)

	totalPlots, totalRows := 0, 0
	for _, u := range preview.Report.Units {
		totalPlots += u.NumPlots
		totalRows += len(u.Rows)
	}
	return &QuickVegReportExportResult{
		ReportKind:          "long_vegetation",
		Title:               preview.Report.Title,
		Project:             preview.Report.Project,
		SU:                  preview.Report.SU,
		ScopeLabel:          scopeLabel,
		FallbackNotice:      fallbackNotice,
		UnitCount:           len(preview.Report.Units),
		PlotCount:           totalPlots,
		RowCount:            totalRows,
		Path:                outPath,
		SHA256:              shaHex,
		Bytes:               len(wb.Bytes),
		PreferencesSaved:    prefsSaved,
		OpenedInSpreadsheet: opened,
		SpreadsheetNotice:   spreadNotice,
	}, nil
}

// RenderLongVegetationHTMLReport renders a self-contained Quarto-style HTML Long Vegetation report.
func RenderLongVegetationHTMLReport(
	contexts *vprocore.ContextService,
	ctx context.Context,
	contextID string,
	req QuickLongVegetationRequest,
) (*reportcore.HTMLReportResult, error) {
	if contexts == nil || ctx == nil {
		return nil, errors.New("Long Vegetation HTML report requires active context")
	}
	preview, _, scopeLabel, fallbackNotice, _, _, err := buildQuickLongVegetationPreview(contexts, ctx, contextID, req)
	if err != nil {
		return nil, err
	}
	tables := make([]reportcore.HTMLReportTable, 0, len(preview.Report.Units))
	totalPlots := 0
	for _, unit := range preview.Report.Units {
		totalPlots += unit.NumPlots
		unitCode := reportcore.FormatMetadataCellText(unit.Code)
		if unitCode == "" {
			unitCode = "Unnamed Unit"
		}
		subtitle := ""
		if unit.LongName != nil && strings.TrimSpace(*unit.LongName) != "" {
			subtitle = *unit.LongName
		}
		plotOrder := []string{}
		if len(unit.Rows) > 0 {
			for _, p := range unit.Rows[0].Plots {
				plotOrder = append(plotOrder, p.PlotNumber)
			}
		}
		headers := []string{"Layer", "Species"}
		numCols := []bool{false, false}
		if preview.Settings.ShowEnglishName {
			headers = append(headers, "English Name")
			numCols = append(numCols, false)
		}
		headers = append(headers, "Pres (%)", "Mean (%)")
		numCols = append(numCols, true, true)
		for _, pNum := range plotOrder {
			headers = append(headers, pNum)
			numCols = append(numCols, true)
		}

		rows := make([]reportcore.HTMLReportRow, 0, len(unit.Rows))
		for _, r := range unit.Rows {
			cells := []string{
				reportcore.FormatMetadataCellText(r.Layer),
				reportcore.FormatMetadataCellText(r.Species),
			}
			if preview.Settings.ShowEnglishName {
				cells = append(cells, reportcore.FormatMetadataCellText(r.EnglishName))
			}
			presStr := ""
			if r.Presence != nil {
				presStr = fmt.Sprintf("%.1f", *r.Presence)
			}
			meanStr := ""
			if r.MeanCover != nil {
				meanStr = fmt.Sprintf("%.2f", *r.MeanCover)
			}
			cells = append(cells, presStr, meanStr)
			for _, p := range r.Plots {
				if p.Cover != nil {
					cells = append(cells, strconv.FormatFloat(*p.Cover, 'f', -1, 64))
				} else {
					cells = append(cells, "")
				}
			}
			rows = append(rows, reportcore.HTMLReportRow{Cells: cells})
		}

		tables = append(tables, reportcore.HTMLReportTable{
			Title:       unitCode,
			Subtitle:    subtitle,
			PlotCount:   unit.NumPlots,
			Headers:     headers,
			NumericCols: numCols,
			Rows:        rows,
		})
	}

	rendered, err := reportcore.RenderQuartoHTMLReport(reportcore.HTMLReportDocument{
		Title:      preview.Report.Title,
		ReportKind: "Long Vegetation",
		Project:    preview.Report.Project,
		SU:         preview.Report.SU,
		ScopeLabel: scopeLabel,
		UnitCount:  len(preview.Report.Units),
		PlotCount:  totalPlots,
		Notice:     fallbackNotice,
		Tables:     tables,
	})
	if err != nil {
		return nil, err
	}
	return &rendered, nil
}

func buildQuickLifeformInput(
	contexts *vprocore.ContextService,
	ctx context.Context,
	contextID string,
	scopeMode string,
) (input lifeformWorkbookInput, scopeLabel, fallbackNotice, root string, err error) {
	_, err = vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (struct{}, error) {
		root = plots.Projects.Root
		return vprocore.WithOwnedPreferenceSnapshot(ctx, plots, vprocore.PublicationReadSnapshotHooks{}, func(owner *vprocore.SqliteContext, tx *sql.Tx) (struct{}, error) {
			mode := strings.ToLower(strings.TrimSpace(scopeMode))
			useActiveSU := owner.Selection.SU != "" && owner.Selection.SU != "None" &&
				(mode == "" || mode == "auto" || mode == "su")
			emptyActiveSUName := ""
			if useActiveSU {
				suRows, countErr := activeSUTableRowCount(ctx, tx, owner.Selection.SU)
				if countErr == nil && suRows == 0 {
					if mode == "su" {
						return struct{}{}, fmt.Errorf("Site Unit table %q has no assigned plots. Assign plots to this Site Unit table or switch Scope to Auto, Zone/SubZone, or All Project Plots.", owner.Selection.SU)
					}
					emptyActiveSUName = owner.Selection.SU
					useActiveSU = false
				}
			}
			if useActiveSU {
				loaded, lErr := readLifeformWorkbookSource(ctx, owner, tx, contextID)
				if lErr != nil {
					return struct{}{}, lErr
				}
				input = loaded
				scopeLabel = "Site Unit: " + owner.Selection.SU
				return struct{}{}, nil
			}
			env, rErr := summaryReadRequiredTable(ctx, tx, "project", owner.Selection.Project+"_Env")
			if rErr != nil {
				return struct{}{}, rErr
			}
			suTable, syntheticSU, sLabel, notice, fErr := buildQuickEnvFallbackSUTable(ctx, env, mode)
			if fErr != nil {
				return struct{}{}, fErr
			}
			if emptyActiveSUName != "" {
				notice = formatEmptySUFallbackNotice(emptyActiveSUName, notice)
			}
			veg, rErr := summaryReadRequiredTable(ctx, tx, "project", owner.Selection.Project+"_Veg")
			if rErr != nil {
				return struct{}{}, rErr
			}
			allSpecs, rErr := summaryReadRequiredTable(ctx, tx, "VLists", "USysAllSpecs")
			if rErr != nil {
				return struct{}{}, rErr
			}
			lfCodes, rErr := summaryReadRequiredTable(ctx, tx, "VPro64", "LifeformCodes")
			if rErr != nil {
				return struct{}{}, rErr
			}
			sppAttrs, rErr := summaryReadRequiredTable(ctx, tx, "VLists", "USysSppAttributes")
			if rErr != nil {
				return struct{}{}, rErr
			}
			species, rErr := readLifeformSpeciesSource(ctx, tx, allSpecs)
			if rErr != nil {
				return struct{}{}, rErr
			}
			lf, lErr := planLifeformSummary(ctx, owner.Selection.Project, syntheticSU, veg, suTable, species, lfCodes)
			if lErr != nil {
				return struct{}{}, lErr
			}
			at, aErr := planSpeciesAttributeSummary(ctx, owner.Selection.Project, syntheticSU, veg, suTable, sppAttrs)
			if aErr != nil {
				return struct{}{}, aErr
			}
			input = lifeformWorkbookInput{
				Lifeform:   LifeformSummaryPreview{contextID, owner.Selection.ProjectPath, owner.Selection.ProjectPath, lf},
				Attributes: SpeciesAttributeSummaryPreview{contextID, owner.Selection.ProjectPath, owner.Selection.ProjectPath, at},
				Tables:     []vprocore.ProjectMetadataTable{veg, suTable, allSpecs, lfCodes, sppAttrs},
			}
			scopeLabel = sLabel
			fallbackNotice = notice
			return struct{}{}, nil
		})
	})
	return input, scopeLabel, fallbackNotice, root, err
}

// QuickExportLifeformWorkbook runs Lifeform & Species Attribute workbook export in one step.
func QuickExportLifeformWorkbook(
	contexts *vprocore.ContextService,
	ctx context.Context,
	contextID string,
	req QuickLifeformReportRequest,
) (*QuickVegReportExportResult, error) {
	if contexts == nil || ctx == nil {
		return nil, errors.New("Lifeform workbook quick export requires active context")
	}
	input, scopeLabel, fallbackNotice, root, err := buildQuickLifeformInput(contexts, ctx, contextID, req.ScopeMode)
	if err != nil {
		return nil, err
	}
	var details [6]bool
	for i := 0; i < len(details) && i < len(req.Details); i++ {
		details[i] = req.Details[i]
	}
	wb, err := prepareLifeformSummaryWorkbook(ctx, input.Lifeform, input.Attributes, lifeformWorkbookLayout{Details: details})
	if err != nil {
		return nil, err
	}
	outPath, shaHex, err := writeQuickWorkbookAtomic(ctx, req.DestinationPath, root, input.Lifeform.Report.Project, "LifeformSummary", wb.Bytes)
	if err != nil {
		return nil, err
	}
	opened, spreadNotice := maybeOpenInSpreadsheetApp(ctx, contexts.Projects.Preferences, outPath, req.OpenInSpreadsheet)

	totalPlots := 0
	for _, u := range input.Lifeform.Report.Units {
		totalPlots += u.NPlots
	}
	return &QuickVegReportExportResult{
		ReportKind:          "lifeform_summary",
		Title:               "Lifeform & Species Attribute Summary",
		Project:             input.Lifeform.Report.Project,
		SU:                  input.Lifeform.Report.SU,
		ScopeLabel:          scopeLabel,
		FallbackNotice:      fallbackNotice,
		UnitCount:           len(input.Lifeform.Report.Units),
		PlotCount:           totalPlots,
		RowCount:            len(input.Lifeform.Report.Catalogue),
		Path:                outPath,
		SHA256:              shaHex,
		Bytes:               len(wb.Bytes),
		PreferencesSaved:    false,
		OpenedInSpreadsheet: opened,
		SpreadsheetNotice:   spreadNotice,
	}, nil
}

// RenderLifeformHTMLReport renders a self-contained Quarto-style HTML Lifeform Summary report.
func RenderLifeformHTMLReport(
	contexts *vprocore.ContextService,
	ctx context.Context,
	contextID string,
	req QuickLifeformReportRequest,
) (*reportcore.HTMLReportResult, error) {
	if contexts == nil || ctx == nil {
		return nil, errors.New("Lifeform HTML report requires active context")
	}
	input, scopeLabel, fallbackNotice, _, err := buildQuickLifeformInput(contexts, ctx, contextID, req.ScopeMode)
	if err != nil {
		return nil, err
	}
	lf := input.Lifeform.Report
	headers := []string{"Lifeform"}
	numCols := []bool{false}
	totalPlots := 0
	for _, u := range lf.Units {
		totalPlots += u.NPlots
		code := reportcore.FormatMetadataCellText(u.Code)
		headers = append(headers, fmt.Sprintf("%s (n=%d)", code, u.NPlots))
		numCols = append(numCols, true)
	}
	rows := make([]reportcore.HTMLReportRow, 0, len(lf.Catalogue))
	for cIdx, cat := range lf.Catalogue {
		label := reportcore.FormatMetadataCellText(cat.Label)
		if label == "" {
			label = reportcore.FormatMetadataCellText(cat.ShortName)
		}
		if label == "" {
			label = fmt.Sprintf("Lifeform %d", cat.Lifeform)
		}
		cells := []string{label}
		for _, u := range lf.Units {
			val := ""
			if cIdx < len(u.Rows) {
				row := u.Rows[cIdx]
				if row.MeanCover != nil && row.Presence != nil {
					val = fmt.Sprintf("%.0f%% / %.2f", *row.Presence, *row.MeanCover)
				} else if row.MeanCover != nil {
					val = fmt.Sprintf("%.2f", *row.MeanCover)
				}
			}
			cells = append(cells, val)
		}
		rows = append(rows, reportcore.HTMLReportRow{Cells: cells})
	}
	rendered, err := reportcore.RenderQuartoHTMLReport(reportcore.HTMLReportDocument{
		Title:      "Lifeform & Species Attribute Summary",
		ReportKind: "Lifeform Summary",
		Project:    lf.Project,
		SU:         lf.SU,
		ScopeLabel: scopeLabel,
		UnitCount:  len(lf.Units),
		PlotCount:  totalPlots,
		Notice:     fallbackNotice,
		Tables: []reportcore.HTMLReportTable{
			{
				Title:       "Mean Cover by Lifeform (%)",
				PlotCount:   totalPlots,
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
