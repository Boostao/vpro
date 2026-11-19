package vegreport

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"math"
	"math/big"
	"strconv"

	"github.com/boostao/vpro/app/internal/reports/reportcore"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type LifeformSummaryEntry struct {
	PlotNumber    string                       `json:"plotNumber"`
	Species       string                       `json:"species"`
	Lifeform      int                          `json:"lifeform"`
	Cover         float64                      `json:"cover"`
	InsertSURowID string                       `json:"insertSuRowId"`
	SpeciesRowID  string                       `json:"speciesRowId"`
	ProjectID     vprocore.ProjectMetadataCell `json:"projectId"`
}

type LifeformSummaryCatalogueRow struct {
	RowID      string                       `json:"rowId"`
	Lifeform   int                          `json:"lifeform"`
	Label      vprocore.ProjectMetadataCell `json:"label"`
	Definition vprocore.ProjectMetadataCell `json:"definition"`
	ShortName  vprocore.ProjectMetadataCell `json:"shortName"`
}

type LifeformSummaryRow struct {
	CatalogueRowID string   `json:"catalogueRowId"`
	Lifeform       int      `json:"lifeform"`
	PlotGroups     int      `json:"plotGroups"`
	CoverCount     int      `json:"coverCount"`
	Presence       *float64 `json:"presence"`
	MeanCover      *float64 `json:"meanCover"`
}

type LifeformSummaryUnit struct {
	Code          vprocore.ProjectMetadataCell `json:"code"`
	NPlots        int                          `json:"nPlots"`
	SURowIDs      []string                     `json:"suRowIds"`
	UniqueSpecies int                          `json:"uniqueSpecies"`
	Occurrences   int                          `json:"occurrences"`
	Rows          []LifeformSummaryRow         `json:"rows"`
}

type LifeformSummaryReport struct {
	Project     string                                  `json:"project"`
	SU          string                                  `json:"su"`
	QuerySource string                                  `json:"querySource"`
	Ordering    string                                  `json:"ordering"`
	Memberships []reportcore.VegetationReportMembership `json:"memberships"`
	Entries     []LifeformSummaryEntry                  `json:"entries"`
	Catalogue   []LifeformSummaryCatalogueRow           `json:"catalogue"`
	Units       []LifeformSummaryUnit                   `json:"units"`
}

// This preview models the normal-SU SQL, not Excel, attributes or hierarchy
// breaks. Binary identity joins are the shared preparation's explicit policy;
// CodeType uses explicit ASCII S/s exclusion, without asserting locale collation.
func planLifeformSummary(ctx context.Context, project, suName string, veg, su, species, catalogue vprocore.ProjectMetadataTable) (LifeformSummaryReport, error) {
	fail := func(err error) (LifeformSummaryReport, error) { return LifeformSummaryReport{}, err }
	if err := ctx.Err(); err != nil {
		return fail(err)
	}
	if suName == "None" {
		return fail(errors.New("Lifeform Summary requires an SU table or dynamic hierarchy breakpoints"))
	}
	coverNames := []string{"PlotNumber", "Species"}
	for i := 1; i <= 10; i++ {
		coverNames = append(coverNames, fmt.Sprintf("Cover%d", i))
	}
	columns, err := vprocore.SiteUnitTransferColumns(veg, coverNames...)
	if err != nil {
		return fail(fmt.Errorf("Lifeform Summary physical Veg schema: %w", err))
	}
	// The common MAX kernel also supports layer-only fields. Project only this
	// source's ten covers so unused Cover5a/b/c and totals cannot affect it.
	projected := vprocore.ProjectMetadataTable{Columns: []vprocore.ProjectMetadataColumn{{Name: "PlotNumber"}, {Name: "Species"}}}
	for _, name := range longVegetationCoverColumns() {
		projected.Columns = append(projected.Columns, vprocore.ProjectMetadataColumn{Name: name})
	}
	for _, row := range veg.Rows {
		if err := ctx.Err(); err != nil {
			return fail(err)
		}
		cells := []vprocore.ProjectMetadataCell{row.Cells[columns["PlotNumber"]], row.Cells[columns["Species"]]}
		for _, name := range longVegetationCoverColumns() {
			cell := vprocore.ProjectMetadataCell{Storage: "null"}
			for _, included := range coverNames[2:] {
				if name == included {
					cell = row.Cells[columns[name]]
					break
				}
			}
			cells = append(cells, cell)
		}
		projected.Rows = append(projected.Rows, vprocore.ProjectMetadataRow{RowID: row.RowID, Cells: cells})
	}
	prepared, err := prepareLongVegetation(ctx, project, suName, projected, su,
		vprocore.ProjectMetadataTable{Columns: []vprocore.ProjectMetadataColumn{{Name: "LayerText"}}})
	if err != nil {
		return fail(err)
	}
	byRowID := make(map[string]reportcore.VegetationReportMembership, len(prepared.Memberships))
	for _, membership := range prepared.Memberships {
		byRowID[membership.RowID] = membership
	}
	prepared.Memberships = []reportcore.VegetationReportMembership{}
	for _, row := range su.Rows {
		prepared.Memberships = append(prepared.Memberships, byRowID[row.RowID])
	}
	// CreateSmallVeg copies USysVegTable: each reduced cover is assigned to
	// SINGLE before the species join, including rows with no qualifying Code.
	for i := range prepared.ReducedRows {
		for column, name := range prepared.CoverColumns {
			value, err := vprocore.VegetationReportNumber(prepared.ReducedRows[i].Covers[column])
			if err != nil {
				return fail(err)
			}
			if value == nil {
				continue
			}
			maximum, err := reportcore.LifeformSummarySingle(value)
			if err != nil {
				return fail(fmt.Errorf("TempReportVegLF %s: %w", name, err))
			}
			prepared.ReducedRows[i].Covers[column] = vprocore.ProjectMetadataCell{Storage: "real", Real: &maximum}
		}
	}
	result := LifeformSummaryReport{Project: project, SU: suName,
		QuerySource: "normal-su-global-entrydat-plot-rejoin",
		Ordering:    "physical-catalogue-rowid-and-first-membership",
		Memberships: prepared.Memberships, Entries: []LifeformSummaryEntry{},
		Catalogue: []LifeformSummaryCatalogueRow{}, Units: []LifeformSummaryUnit{}}
	specColumns, err := vprocore.SiteUnitTransferColumns(species, "Code", "Lifeform", "Codetype")
	if err != nil {
		return fail(err)
	}
	catColumns, err := vprocore.SiteUnitTransferColumns(catalogue, "Lifeform", "LifeformTXT", "Definition", "ShortName")
	if err != nil {
		return fail(err)
	}
	seen := map[int]bool{}
	for _, row := range catalogue.Rows {
		if err := ctx.Err(); err != nil {
			return fail(err)
		}
		form, err := lifeformSummaryInteger(row.Cells[catColumns["Lifeform"]])
		if err != nil || form == nil || seen[*form] {
			return fail(fmt.Errorf("LifeformCodes row %s violates its unique non-NULL INTEGER key", row.RowID))
		}
		seen[*form] = true
		if *form == 13 {
			continue
		}
		values := []vprocore.ProjectMetadataCell{}
		for _, column := range []string{"LifeformTXT", "Definition", "ShortName"} {
			cell := row.Cells[catColumns[column]]
			if err := reportcore.LifeformSummaryText(cell, 255); err != nil {
				return fail(fmt.Errorf("LifeformCodes row %s %s: %w", row.RowID, column, err))
			}
			values = append(values, vprocore.CloneSiteUnitCell(cell))
		}
		result.Catalogue = append(result.Catalogue, LifeformSummaryCatalogueRow{row.RowID, *form, values[0], values[1], values[2]})
	}
	type definition struct {
		rowID string
		form  int
	}
	definitions := map[string][]definition{}
	for _, row := range species.Rows {
		if err := ctx.Err(); err != nil {
			return fail(err)
		}
		code, codeType := row.Cells[specColumns["Code"]], row.Cells[specColumns["Codetype"]]
		if _, err := vprocore.VegetationReportIdentity(code); err != nil {
			return fail(fmt.Errorf("USysAllSpecs row %s Code: %w", row.RowID, err))
		}
		if _, err := vprocore.VegetationReportIdentity(codeType); err != nil {
			return fail(fmt.Errorf("USysAllSpecs row %s Codetype: %w", row.RowID, err))
		}
		if code.Text == nil || codeType.Text == nil || *codeType.Text == "S" || *codeType.Text == "s" {
			continue
		}
		form, err := lifeformSummaryInteger(row.Cells[specColumns["Lifeform"]])
		if err != nil {
			return fail(fmt.Errorf("USysAllSpecs row %s Lifeform: %w", row.RowID, err))
		}
		if form != nil && *form >= 0 && *form <= 12 {
			// UX-REPORTS-001: one definition per (Code, Lifeform); duplicate
			// catalogue rows (e.g. CodeType U + XX) must not multiply a veg row.
			duplicate := false
			for _, existing := range definitions[*code.Text] {
				duplicate = duplicate || existing.form == *form
			}
			if !duplicate {
				definitions[*code.Text] = append(definitions[*code.Text], definition{row.RowID, *form})
			}
		}
	}
	// EntryDat is global across the selected SU. Each insertion retains every
	// physical SU and Code match; its ProjectID is NOT a later unit predicate.
	for form := 0; form <= 12; form++ {
		for _, reduced := range prepared.ReducedRows {
			if err := ctx.Err(); err != nil {
				return fail(err)
			}
			if reduced.Species.Text == nil {
				continue
			}
			for _, def := range definitions[*reduced.Species.Text] {
				if def.form != form {
					continue
				}
				for _, membership := range prepared.Memberships {
					if membership.PlotNumber.Text == nil || *membership.PlotNumber.Text != reduced.PlotNumber {
						continue
					}
					for _, item := range []struct {
						cell  vprocore.ProjectMetadataCell
						limit int
						name  string
					}{
						{metadataLifeformText(reduced.PlotNumber), 8, "PlotNumber"},
						{reduced.Species, 8, "Species"}, {membership.SiteUnit, 20, "ProjectID"},
					} {
						if err := reportcore.LifeformSummaryText(item.cell, item.limit); err != nil {
							return fail(fmt.Errorf("EntryDatVegLF %s: %w", item.name, err))
						}
					}
					total := new(big.Rat)
					for i, name := range prepared.CoverColumns {
						if name == "Cover5a" || name == "Cover5b" || name == "Cover5c" || name == "TotalA" || name == "TotalB" {
							continue
						}
						value, err := vprocore.VegetationReportNumber(reduced.Covers[i])
						if err != nil {
							return fail(err)
						}
						if value != nil {
							total.Add(total, value)
						}
					}
					// USysV2VegLF.Cover is SINGLE: round once at assignment,
					// before any qryLF1 sums or duplicate-weighted rejoin.
					single, err := reportcore.LifeformSummarySingle(total)
					if err != nil {
						return fail(fmt.Errorf("EntryDatVegLF Cover: %w", err))
					}
					result.Entries = append(result.Entries, LifeformSummaryEntry{reduced.PlotNumber,
						*reduced.Species.Text, form, single, membership.RowID, def.rowID, vprocore.CloneSiteUnitCell(membership.SiteUnit)})
				}
			}
		}
	}
	unitIndexes := map[string]int{}
	for _, membership := range prepared.Memberships {
		if err := ctx.Err(); err != nil {
			return fail(err)
		}
		key := membership.SiteUnit.Storage + "\x00"
		if membership.SiteUnit.Text != nil {
			key += *membership.SiteUnit.Text
		}
		index, found := unitIndexes[key]
		if !found {
			index = len(result.Units)
			unitIndexes[key] = index
			result.Units = append(result.Units, LifeformSummaryUnit{Code: vprocore.CloneSiteUnitCell(membership.SiteUnit),
				SURowIDs: []string{}, Rows: []LifeformSummaryRow{}})
		}
		unit := &result.Units[index]
		unit.SURowIDs = append(unit.SURowIDs, membership.RowID)
		if membership.PlotNumber.Text != nil {
			unit.NPlots++
		}
	}
	for i := range result.Units {
		unit := &result.Units[i]
		type aggregate struct {
			sum   *big.Rat
			count int
		}
		groups := map[int]map[string]*aggregate{}
		unique := map[string]bool{}
		for _, membership := range prepared.Memberships {
			if membership.SiteUnit.Text == nil || unit.Code.Text == nil || *membership.SiteUnit.Text != *unit.Code.Text || membership.PlotNumber.Text == nil {
				continue
			}
			for _, entry := range result.Entries {
				if err := ctx.Err(); err != nil {
					return fail(err)
				}
				if entry.PlotNumber != *membership.PlotNumber.Text {
					continue
				}
				unit.Occurrences++
				unique[entry.Species] = true
				if groups[entry.Lifeform] == nil {
					groups[entry.Lifeform] = map[string]*aggregate{}
				}
				group := groups[entry.Lifeform][entry.PlotNumber]
				if group == nil {
					group = &aggregate{sum: new(big.Rat)}
					groups[entry.Lifeform][entry.PlotNumber] = group
				}
				group.count++
				group.sum.Add(group.sum, new(big.Rat).SetFloat64(entry.Cover))
			}
		}
		unit.UniqueSpecies = len(unique)
		for _, cat := range result.Catalogue {
			row := LifeformSummaryRow{CatalogueRowID: cat.RowID, Lifeform: cat.Lifeform, PlotGroups: len(groups[cat.Lifeform])}
			total := new(big.Rat)
			for _, group := range groups[cat.Lifeform] {
				row.CoverCount += group.count
				total.Add(total, group.sum)
			}
			if unit.NPlots > 0 {
				presence := float64(row.PlotGroups) / float64(unit.NPlots)
				row.Presence = &presence
				if row.PlotGroups > 0 {
					sum, _ := total.Float64()
					mean := sum / float64(unit.NPlots) / 100
					if math.IsNaN(mean) || math.IsInf(mean, 0) {
						return fail(errors.New("Lifeform Summary aggregate is not finite"))
					}
					row.MeanCover = &mean
				}
			}
			unit.Rows = append(unit.Rows, row)
		}
	}
	if err := ctx.Err(); err != nil {
		return fail(err)
	}
	return result, nil
}

func metadataLifeformText(value string) vprocore.ProjectMetadataCell {
	return vprocore.ProjectMetadataCell{Storage: "text", Text: &value}
}

func lifeformSummaryInteger(cell vprocore.ProjectMetadataCell) (*int, error) {
	if cell.Storage == "null" {
		return nil, nil
	}
	number, err := vprocore.VegetationReportNumber(cell)
	if err != nil || number == nil || !number.IsInt() || !number.Num().IsInt64() {
		return nil, errors.New("expected nullable source INTEGER, not repaired/coerced metadata")
	}
	value := number.Num().Int64()
	if value < -32768 || value > 32767 {
		return nil, fmt.Errorf("source INTEGER out of range: %s", strconv.FormatInt(value, 10))
	}
	result := int(value)
	return &result, nil
}

type LifeformSummaryPreview struct {
	ContextID   string                `json:"contextId"`
	ProjectPath string                `json:"projectPath"`
	SUPath      string                `json:"suPath"`
	Report      LifeformSummaryReport `json:"report"`
}

type LifeformSummaryService struct {
	contexts *vprocore.ContextService
	snapshot vprocore.PublicationReadSnapshotHooks
}

func NewLifeformSummaryService(contexts *vprocore.ContextService) (*LifeformSummaryService, error) {
	return &LifeformSummaryService{contexts: contexts}, nil
}

// resolveLifeformAndAttributeSU reads the physical SU table (or Env UserSiteUnit/BECSiteUnit/SiteSeries fallback
// for USysSuTableDynamic) and, when forceHierarchy or USysSuTableDynamic is active, rolls SiteUnit assignments
// up to matching '~' hierarchy breakpoint nodes.
func resolveLifeformAndAttributeSU(ctx context.Context, owner *vprocore.SqliteContext, tx *sql.Tx, label, breakpointPolicy string, forceHierarchy bool) (vprocore.ProjectMetadataTable, error) {
	hasPhysicalTable := func(role, name string) (bool, error) {
		var kind string
		err := tx.QueryRowContext(ctx, `SELECT type FROM `+vprocore.QuoteHeaderIdentifier(role)+
			`.sqlite_master WHERE name COLLATE BINARY=? LIMIT 1`, name).Scan(&kind)
		if errors.Is(err, sql.ErrNoRows) {
			return false, nil
		}
		if err != nil {
			return false, err
		}
		if kind != "table" {
			return false, fmt.Errorf("%s requires original physical table %s.%s", label, role, name)
		}
		return true, nil
	}

	readRequiredTable := func(role, name string) (vprocore.ProjectMetadataTable, error) {
		ok, err := hasPhysicalTable(role, name)
		if err != nil {
			return vprocore.ProjectMetadataTable{}, err
		}
		if !ok {
			return vprocore.ProjectMetadataTable{}, fmt.Errorf("%s requires original physical table %s.%s", label, role, name)
		}
		return vprocore.ReadSQLiteStorageRows(ctx, tx, role, name, "", nil, "")
	}

	useHierarchy := forceHierarchy || owner.Selection.SU == "USysSuTableDynamic"
	var suTable vprocore.ProjectMetadataTable
	var err error
	if owner.Selection.SU == "USysSuTableDynamic" {
		loaded := false
		for _, role := range []string{"su", "project"} {
			if _, attached := owner.Attachments[role]; !attached {
				continue
			}
			ok, tErr := hasPhysicalTable(role, "USysSuTableDynamic_SU")
			if tErr != nil {
				return vprocore.ProjectMetadataTable{}, tErr
			}
			if ok {
				suTable, err = vprocore.ReadSQLiteStorageRows(ctx, tx, role, "USysSuTableDynamic_SU", "", nil, "")
				if err != nil {
					return vprocore.ProjectMetadataTable{}, err
				}
				loaded = true
				break
			}
		}
		if !loaded {
			env, eErr := readRequiredTable("project", owner.Selection.Project+"_Env")
			if eErr != nil {
				return vprocore.ProjectMetadataTable{}, eErr
			}
			suTable, err = buildDynamicHierarchySourceSUTable(ctx, env)
			if err != nil {
				return vprocore.ProjectMetadataTable{}, err
			}
		}
	} else {
		suTable, err = readRequiredTable("su", owner.Selection.SU+"_SU")
		if err != nil {
			return vprocore.ProjectMetadataTable{}, err
		}
	}

	if useHierarchy {
		nodes, hErr := loadHierarchyNodesFromTx(ctx, tx, owner.Selection.Hierarchy)
		if hErr != nil {
			return vprocore.ProjectMetadataTable{}, hErr
		}
		rolled, _, rErr := resolveHierarchyBreakpointsOnSU(suTable, nodes, HierarchyBreakpointOptions{
			BreakpointPolicy: breakpointPolicy,
			StripTildePrefix: true,
		})
		if rErr != nil {
			return vprocore.ProjectMetadataTable{}, rErr
		}
		suTable = rolled
	}
	return suTable, nil
}

func (s *LifeformSummaryService) Preview(ctx context.Context, contextID string) (LifeformSummaryPreview, error) {
	return s.previewConfigured(ctx, contextID, "", false)
}

// PreviewWithHierarchyBreakpoints resolves Lifeform Summary using '~' hierarchy
// breakpoints ('lowest' or 'highest') against the active SU or dynamic source.
func (s *LifeformSummaryService) PreviewWithHierarchyBreakpoints(ctx context.Context, contextID, breakpointPolicy string) (LifeformSummaryPreview, error) {
	return s.previewConfigured(ctx, contextID, breakpointPolicy, true)
}

func (s *LifeformSummaryService) previewConfigured(ctx context.Context, contextID, breakpointPolicy string, forceHierarchy bool) (LifeformSummaryPreview, error) {
	if ctx == nil {
		return LifeformSummaryPreview{}, errors.New("Lifeform Summary requires a context")
	}
	if err := ctx.Err(); err != nil {
		return LifeformSummaryPreview{}, err
	}
	if s == nil || s.contexts == nil || s.contexts.Projects == nil || s.contexts.Projects.Sqlite == nil || s.contexts.Plots == nil {
		return LifeformSummaryPreview{}, errors.New("Lifeform Summary context service is unavailable")
	}
	if err := vprocore.ValidateGoogleEarthReviewStrings(contextID); err != nil {
		return LifeformSummaryPreview{}, err
	}
	return vprocore.WithContextPlotRequest(ctx, s.contexts, contextID, func(plots *vprocore.PlotService) (LifeformSummaryPreview, error) {
		return vprocore.WithOwnedPreferenceSnapshot(ctx, plots, s.snapshot, func(owner *vprocore.SqliteContext, tx *sql.Tx) (LifeformSummaryPreview, error) {
			if owner.Selection.SU == "None" {
				return LifeformSummaryPreview{}, errors.New("Lifeform Summary requires a selected normal SU or USysSuTableDynamic; None scope is unavailable")
			}
			suTable, err := resolveLifeformAndAttributeSU(ctx, owner, tx, "Lifeform Summary", breakpointPolicy, forceHierarchy)
			if err != nil {
				return LifeformSummaryPreview{}, err
			}
			tables := make([]vprocore.ProjectMetadataTable, 3)
			for i, source := range []struct{ role, table string }{
				{"project", owner.Selection.Project + "_Veg"},
				{"VLists", "USysAllSpecs"},
				{"VPro64", "LifeformCodes"},
			} {
				var count int
				if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM `+vprocore.QuoteHeaderIdentifier(source.role)+
					`.sqlite_master WHERE type='table' AND name COLLATE BINARY=?`, source.table).Scan(&count); err != nil {
					return LifeformSummaryPreview{}, err
				}
				if count != 1 {
					return LifeformSummaryPreview{}, fmt.Errorf("Lifeform Summary requires original physical table %s.%s", source.role, source.table)
				}
				tables[i], err = vprocore.ReadSQLiteStorageRows(ctx, tx, source.role, source.table, "", nil, "")
				if err != nil {
					return LifeformSummaryPreview{}, err
				}
			}
			species, err := readLifeformSpeciesSource(ctx, tx, tables[1])
			if err != nil {
				return LifeformSummaryPreview{}, err
			}
			report, err := planLifeformSummary(ctx, owner.Selection.Project, owner.Selection.SU, tables[0], suTable, species, tables[2])
			if err != nil {
				return LifeformSummaryPreview{}, err
			}
			return LifeformSummaryPreview{contextID, owner.Selection.ProjectPath, owner.Selection.SUPath, report}, nil
		})
	})
}

// readLifeformSpeciesSource merges VLists.USysAllSpecs with the optional
// VUser.USysUserSpp so personal species count toward their configured
// LifeForm (UX-REPORTS-001). Shared by the preview and workbook readers.
func readLifeformSpeciesSource(ctx context.Context, tx *sql.Tx, master vprocore.ProjectMetadataTable) (vprocore.ProjectMetadataTable, error) {
	var personal vprocore.ProjectMetadataTable
	var count int
	if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM "VUser".sqlite_master WHERE type='table' AND name COLLATE BINARY='USysUserSpp'`).Scan(&count); err != nil {
		return vprocore.ProjectMetadataTable{}, err
	}
	if count == 1 {
		var err error
		personal, err = vprocore.ReadSQLiteStorageRows(ctx, tx, "VUser", "USysUserSpp", "", nil, "")
		if err != nil {
			return vprocore.ProjectMetadataTable{}, err
		}
	}
	return mergeLifeformSpeciesSources(master, personal)
}

// mergeLifeformSpeciesSources projects VLists.USysAllSpecs and the optional
// VUser.USysUserSpp (LifeForm or Lifeform) onto Code/Lifeform/Codetype. Master
// rows keep their rowids; personal rows use the negated rowid so species row
// identities stay numeric and distinct.
func mergeLifeformSpeciesSources(master, personal vprocore.ProjectMetadataTable) (vprocore.ProjectMetadataTable, error) {
	out := vprocore.ProjectMetadataTable{Columns: []vprocore.ProjectMetadataColumn{{Name: "Code"}, {Name: "Lifeform"}, {Name: "Codetype"}}}
	masterColumns, err := vprocore.SiteUnitTransferColumns(master, "Code", "Lifeform", "Codetype")
	if err != nil {
		return out, err
	}
	for _, row := range master.Rows {
		out.Rows = append(out.Rows, vprocore.ProjectMetadataRow{RowID: row.RowID, Cells: []vprocore.ProjectMetadataCell{
			row.Cells[masterColumns["Code"]], row.Cells[masterColumns["Lifeform"]], row.Cells[masterColumns["Codetype"]]}})
	}
	if len(personal.Columns) == 0 {
		return out, nil
	}
	lifeformColumn := "LifeForm"
	canonical, original := false, false
	for _, column := range personal.Columns {
		canonical = canonical || column.Name == "Lifeform"
		original = original || column.Name == "LifeForm"
	}
	if canonical && original {
		return out, errors.New("USysUserSpp has ambiguous LifeForm/Lifeform columns")
	}
	if canonical {
		lifeformColumn = "Lifeform"
	}
	personalColumns, err := vprocore.SiteUnitTransferColumns(personal, "Code", lifeformColumn, "Codetype")
	if err != nil {
		return out, fmt.Errorf("USysUserSpp: %w", err)
	}
	for _, row := range personal.Rows {
		rowID, err := strconv.ParseInt(row.RowID, 10, 64)
		if err != nil || rowID <= 0 {
			return out, fmt.Errorf("USysUserSpp row %s requires a valid record number", row.RowID)
		}
		out.Rows = append(out.Rows, vprocore.ProjectMetadataRow{RowID: strconv.FormatInt(-rowID, 10), Cells: []vprocore.ProjectMetadataCell{
			row.Cells[personalColumns["Code"]], row.Cells[personalColumns[lifeformColumn]], row.Cells[personalColumns["Codetype"]]}})
	}
	return out, nil
}
