package vegreport

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"

	"github.com/boostao/vpro/app/internal/reports/reportcore"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type SummaryVegetationReferenceOrigin struct {
	Table string `json:"table"`
	RowID string `json:"rowId"`
}

type SummaryVegetationWitness struct {
	StageRowID        string                             `json:"stageRowId"`
	ConversionLayerID string                             `json:"conversionLayerId"`
	MembershipID      string                             `json:"membershipId"`
	Unit              string                             `json:"unit"`
	LayerMapID        string                             `json:"layerMapId"`
	ReferenceOrigins  []SummaryVegetationReferenceOrigin `json:"referenceOrigins"`
	RawVegRowIDs      []string                           `json:"rawVegRowIds"`
	Cover             vprocore.ProjectMetadataCell       `json:"cover"`
}

type SummaryVegetationRow struct {
	Layer      vprocore.ProjectMetadataCell   `json:"layer"`
	Species    vprocore.ProjectMetadataCell   `json:"species"`
	CommonName *vprocore.ProjectMetadataCell  `json:"commonName,omitempty"`
	RawSpecies *vprocore.ProjectMetadataCell  `json:"rawSpecies,omitempty"`
	Order      vprocore.ProjectMetadataCell   `json:"order"`
	Covers     []vprocore.ProjectMetadataCell `json:"covers"`
	Witnesses  []SummaryVegetationWitness     `json:"witnesses"`
}

type SummaryVegetationUnit struct {
	Code            string   `json:"code"`
	HierarchyHeader *string  `json:"hierarchyHeader,omitempty"`
	NumPlots        int      `json:"numPlots"`
	MembershipIDs   []string `json:"membershipIds"`
	RawVegRowIDs    []string `json:"rawVegRowIds"`
}

type SummaryVegetationField struct {
	Name    string `json:"name"`
	DAOType int    `json:"daoType"`
	Size    int    `json:"size"`
}

type SummaryVegetationPreview struct {
	ContextID              string                                  `json:"contextId"`
	Project                string                                  `json:"project"`
	ProjectPath            string                                  `json:"projectPath"`
	SU                     string                                  `json:"su"`
	SUPath                 string                                  `json:"suPath"`
	Average                int                                     `json:"average"`
	Display                int                                     `json:"display"`
	ShowClass              int                                     `json:"showClass,omitempty"`
	GroupAndOrder          int                                     `json:"groupAndOrder,omitempty"`
	GroupField             *SummaryVegetationField                 `json:"groupField,omitempty"`
	OrderField             *SummaryVegetationField                 `json:"orderField,omitempty"`
	Source                 string                                  `json:"source"`
	Ordering               string                                  `json:"ordering"`
	Memberships            []reportcore.VegetationReportMembership `json:"memberships"`
	Units                  []SummaryVegetationUnit                 `json:"units"`
	Columns                []string                                `json:"columns"`
	Rows                   []SummaryVegetationRow                  `json:"rows"`
	References             *SummaryVegetationReferenceReview       `json:"references,omitempty"`
	Quality                *SummaryVegetationQualityFilterResult   `json:"quality,omitempty"`
	UnitScope              string                                  `json:"unitScope,omitempty"`
	UnitField              string                                  `json:"unitField,omitempty"`
	HierarchyHeaderEnabled bool                                    `json:"hierarchyHeaderEnabled,omitempty"`
	CombineVariants        bool                                    `json:"combineVariants,omitempty"`
	LumpTable              string                                  `json:"lumpTable,omitempty"`
	ValueLimit             float64                                 `json:"valueLimit,omitempty"`
	Goldstream             *SummaryVegetationGoldstreamMetadata    `json:"goldstream,omitempty"`
	AppliedPreferences     *SummaryVegetationAppliedPreferences    `json:"appliedPreferences,omitempty"`
}

type SummaryVegetationService struct {
	contexts *vprocore.ContextService
	snapshot vprocore.PublicationReadSnapshotHooks
}

func NewSummaryVegetationService(contexts *vprocore.ContextService) (*SummaryVegetationService, error) {
	return &SummaryVegetationService{contexts: contexts}, nil
}

// Preview — Explicit read-only draft options do not invoke the mutating Access Form_Load
// or its saved setters, and never borrow Long Vegetation quality/preferences.
func (s *SummaryVegetationService) Preview(ctx context.Context, contextID string, average, display int) (SummaryVegetationPreview, error) {
	return s.preview(ctx, contextID, average, display, 0, 11)
}

func (s *SummaryVegetationService) PreviewClass(ctx context.Context, contextID string, average, display, showClass int) (SummaryVegetationPreview, error) {
	if showClass == 0 {
		return SummaryVegetationPreview{}, errors.New("Summary Vegetation class preview requires explicit ShowClass1,10 or20")
	}
	return s.preview(ctx, contextID, average, display, showClass, 11)
}

func (s *SummaryVegetationService) PreviewGrouped(ctx context.Context, contextID string, average, groupAndOrder int) (SummaryVegetationPreview, error) {
	if groupAndOrder != 12 && groupAndOrder != 13 && groupAndOrder != 14 {
		return SummaryVegetationPreview{}, errors.New("Summary Vegetation grouped preview requires GroupAndOrder12,13 or14")
	}
	return s.preview(ctx, contextID, average, 6, 0, groupAndOrder)
}

func (s *SummaryVegetationService) PreviewGroupedDisplay(ctx context.Context, contextID string, average, groupAndOrder, display, showClass int) (SummaryVegetationPreview, error) {
	if err := validateSummaryVegetationGroupedOptions(ctx, average, groupAndOrder, display, showClass); err != nil {
		return SummaryVegetationPreview{}, err
	}
	return s.preview(ctx, contextID, average, display, showClass, groupAndOrder)
}

func (s *SummaryVegetationService) preview(ctx context.Context, contextID string, average, display, showClass, groupAndOrder int) (SummaryVegetationPreview, error) {
	fail := func(err error) (SummaryVegetationPreview, error) { return SummaryVegetationPreview{}, err }
	if ctx == nil {
		return fail(errors.New("Summary Vegetation requires a context"))
	}
	if err := ctx.Err(); err != nil {
		return fail(err)
	}
	if s == nil || s.contexts == nil || s.contexts.Projects == nil || s.contexts.Projects.Sqlite == nil || s.contexts.Plots == nil {
		return fail(errors.New("Summary Vegetation context service is unavailable"))
	}
	if err := vprocore.ValidateGoogleEarthReviewStrings(contextID); err != nil {
		return fail(err)
	}
	if err := validateSummaryVegetationDisplayOptions(ctx, average, display, showClass); err != nil {
		return fail(err)
	}
	return vprocore.WithContextPlotRequest(ctx, s.contexts, contextID, func(plots *vprocore.PlotService) (SummaryVegetationPreview, error) {
		return vprocore.WithOwnedPreferenceSnapshot(ctx, plots, s.snapshot, func(owner *vprocore.SqliteContext, tx *sql.Tx) (SummaryVegetationPreview, error) {
			source, err := s.readSnapshot(ctx, contextID, plots, owner, tx, average, display, showClass, groupAndOrder)
			if err != nil {
				return fail(err)
			}
			return source.Preview, nil
		})
	})
}

type summaryVegetationSnapshotPreview struct {
	Preview      SummaryVegetationPreview
	SU           vprocore.ProjectMetadataTable
	Veg          vprocore.ProjectMetadataTable
	Master       vprocore.ProjectMetadataTable
	Personal     vprocore.ProjectMetadataTable
	Layers       vprocore.ProjectMetadataTable
	Descriptions *vprocore.ProjectMetadataTable `json:"Descriptions,omitempty"`
}

func (s *SummaryVegetationService) readSnapshot(ctx context.Context, contextID string, plots *vprocore.PlotService,
	owner *vprocore.SqliteContext, tx *sql.Tx, average, display, showClass, groupAndOrder int) (summaryVegetationSnapshotPreview, error) {
	return s.readSnapshotWithReferences(ctx, contextID, plots, owner, tx, average, display, showClass, groupAndOrder, nil)
}

func (s *SummaryVegetationService) readSnapshotWithReferences(ctx context.Context, contextID string, plots *vprocore.PlotService,
	owner *vprocore.SqliteContext, tx *sql.Tx, average, display, showClass, groupAndOrder int,
	options *SummaryVegetationReferenceOptions) (summaryVegetationSnapshotPreview, error) {
	return s.readSnapshotWithReferenceMode(ctx, contextID, plots, owner, tx,
		average, display, showClass, groupAndOrder, options, summaryVegetationGroupedOrdinary)
}

const summaryVegetationConstancySource = "literal-normal-su-constancy"
const summaryVegetationConstancyOrdering = "literal-null-first-numeric-lifeform-species-raw-code"
const summaryVegetationUnanimousCommonSource = "literal-normal-su-unanimous-common"
const summaryVegetationUnanimousCommonOrdering = "literal-null-first-group-species-unanimous-common"

func (s *SummaryVegetationService) readSnapshotWithReferenceMode(ctx context.Context, contextID string, plots *vprocore.PlotService,
	owner *vprocore.SqliteContext, tx *sql.Tx, average, display, showClass, groupAndOrder int,
	options *SummaryVegetationReferenceOptions, mode summaryVegetationGroupedMode) (summaryVegetationSnapshotPreview, error) {
	return s.readSnapshotConfigured(ctx, contextID, plots, owner, tx,
		average, display, showClass, groupAndOrder, options, mode, SummaryVegetationConfiguredRequest{}, nil, 0)
}

type summaryEffectivePresentation struct {
	scope           string
	unitField       string
	combineVariants bool
	lumpTable       string
	hierarchyHeader bool
}

func validateSummarySnapshotMode(mode summaryVegetationGroupedMode, groupAndOrder, display, showClass int, options *SummaryVegetationReferenceOptions) error {
	if mode != summaryVegetationGroupedOrdinary && mode != summaryVegetationGroupedConstancy &&
		mode != summaryVegetationGroupedUnanimousCommon {
		return errors.New("Summary snapshot requires a supported explicit grouping mode")
	}
	constancy := mode == summaryVegetationGroupedConstancy
	unanimousCommon := mode == summaryVegetationGroupedUnanimousCommon
	if constancy && (groupAndOrder != 13 || display != 1 || showClass != 0 || options == nil ||
		options.ShowCommon || options.UseGuideNames) {
		return errors.New("Summary Constancy snapshot requires Group13/Display1 and effective references without common/guide names")
	}
	if unanimousCommon && (showClass != 0 || options == nil ||
		!summaryVegetationUnanimousCommonAvailable(groupAndOrder, display, options.ShowCommon || options.UseGuideNames)) {
		return errors.New("Summary unanimous common-name snapshot requires Group13/14 Display6 and effective common/guide references")
	}
	if !unanimousCommon && options != nil && !summaryVegetationReferenceGroupingAvailable(groupAndOrder, options.ShowCommon || options.UseGuideNames) {
		return errors.New("Summary effective common/guide references require Layer11 or Strata12 inspection; First(common name) for13/14 remains unavailable")
	}
	return nil
}

func resolveSummaryEffectivePresentation(ctx context.Context, prefs *vprocore.DesktopConfig, sel vprocore.DesktopSelection, req SummaryVegetationConfiguredRequest) (summaryEffectivePresentation, error) {
	effectiveScope, err := resolveEffectiveSummaryScope(req.UnitScope, sel.SU)
	if err != nil {
		return summaryEffectivePresentation{}, err
	}
	basePrefs, _ := readSummarySavedPresentationState(ctx, prefs, sel.SU)
	out := summaryEffectivePresentation{
		scope:           effectiveScope,
		unitField:       strings.TrimSpace(req.UnitField),
		combineVariants: basePrefs.CombineVariants,
		lumpTable:       basePrefs.LumpTable,
		hierarchyHeader: basePrefs.HierarchyHeader,
	}
	if out.unitField == "" {
		out.unitField = basePrefs.UnitField
	}
	if req.CombineVariants != nil {
		out.combineVariants = *req.CombineVariants
	}
	if req.LumpTable != nil {
		trimmed := strings.TrimSpace(*req.LumpTable)
		if strings.EqualFold(trimmed, "None") || strings.EqualFold(trimmed, "None_Lump") {
			out.lumpTable = ""
		} else {
			out.lumpTable = trimmed
		}
	}
	if req.HierarchyHeader != nil {
		out.hierarchyHeader = *req.HierarchyHeader
	}
	if out.scope == "hierarchy" && (sel.Hierarchy == "" || sel.Hierarchy == "None") {
		return summaryEffectivePresentation{}, errors.New("Summary Vegetation requires an active Hierarchy table for hierarchy/dynamic-break scope")
	}
	return out, nil
}

func summaryHasPhysicalTable(ctx context.Context, tx *sql.Tx, role, table string) (bool, error) {
	var count int
	if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM `+vprocore.QuoteHeaderIdentifier(role)+
		`.sqlite_master WHERE type='table' AND name COLLATE BINARY=?`, table).Scan(&count); err != nil {
		return false, err
	}
	return count == 1, nil
}

func summaryReadRequiredTable(ctx context.Context, tx *sql.Tx, role, table string) (vprocore.ProjectMetadataTable, error) {
	ok, err := summaryHasPhysicalTable(ctx, tx, role, table)
	if err != nil {
		return vprocore.ProjectMetadataTable{}, err
	}
	if !ok {
		return vprocore.ProjectMetadataTable{}, fmt.Errorf("Summary Vegetation requires original physical table %s.%s", role, table)
	}
	return vprocore.ReadSQLiteStorageRows(ctx, tx, role, table, "", nil, "")
}

func loadSummaryScopeSUTable(ctx context.Context, tx *sql.Tx, owner *vprocore.SqliteContext, pres summaryEffectivePresentation, quality summaryVegetationQualityPreferenceValues, breakpointPolicy string) (vprocore.ProjectMetadataTable, *SummaryVegetationQualityFilterResult, error) {
	var cachedEnv *vprocore.ProjectMetadataTable
	loadEnv := func() (vprocore.ProjectMetadataTable, error) {
		if cachedEnv != nil {
			return *cachedEnv, nil
		}
		env, err := summaryReadRequiredTable(ctx, tx, "project", owner.Selection.Project+"_Env")
		if err != nil {
			return vprocore.ProjectMetadataTable{}, err
		}
		cachedEnv = &env
		return env, nil
	}

	var suTable vprocore.ProjectMetadataTable
	var err error
	switch pres.scope {
	case "none":
		env, eErr := loadEnv()
		if eErr != nil {
			return vprocore.ProjectMetadataTable{}, nil, eErr
		}
		suTable, err = buildWholeProjectSUTable(ctx, env)
	case "field":
		env, eErr := loadEnv()
		if eErr != nil {
			return vprocore.ProjectMetadataTable{}, nil, eErr
		}
		suTable, err = buildFieldDerivedSUTable(ctx, env, pres.unitField)
	case "hierarchy":
		if owner.Selection.SU == "" || owner.Selection.SU == "None" || owner.Selection.SU == "USysSuTableDynamic" {
			dynExists := false
			if owner.Selection.SU == "USysSuTableDynamic" {
				if _, ok := owner.Attachments["su"]; ok {
					dynExists, err = summaryHasPhysicalTable(ctx, tx, "su", "USysSuTableDynamic_SU")
					if err != nil {
						return vprocore.ProjectMetadataTable{}, nil, err
					}
				}
			}
			if dynExists {
				suTable, err = summaryReadRequiredTable(ctx, tx, "su", "USysSuTableDynamic_SU")
			} else {
				env, eErr := loadEnv()
				if eErr != nil {
					return vprocore.ProjectMetadataTable{}, nil, eErr
				}
				suTable, err = buildDynamicHierarchySourceSUTable(ctx, env)
			}
		} else {
			suTable, err = summaryReadRequiredTable(ctx, tx, "su", owner.Selection.SU+"_SU")
		}
	default:
		suTable, err = summaryReadRequiredTable(ctx, tx, "su", owner.Selection.SU+"_SU")
	}
	if err != nil {
		return vprocore.ProjectMetadataTable{}, nil, err
	}

	var qualityResult *SummaryVegetationQualityFilterResult
	if quality.Enforce {
		env, eErr := loadEnv()
		if eErr != nil {
			return vprocore.ProjectMetadataTable{}, nil, eErr
		}
		admin, aErr := summaryReadRequiredTable(ctx, tx, "project", owner.Selection.Project+"_Admin")
		if aErr != nil {
			return vprocore.ProjectMetadataTable{}, nil, aErr
		}
		lists, lErr := summaryReadRequiredTable(ctx, tx, "VLists", "USysTableOfLists")
		if lErr != nil {
			return vprocore.ProjectMetadataTable{}, nil, lErr
		}
		suTable, qualityResult, err = filterSummaryVegetationQuality(ctx, suTable, env, admin, lists, quality)
		if err != nil {
			return vprocore.ProjectMetadataTable{}, nil, err
		}
	}

	if pres.scope == "hierarchy" {
		nodes, nErr := loadHierarchyNodesFromTx(ctx, tx, owner.Selection.Hierarchy)
		if nErr != nil {
			return vprocore.ProjectMetadataTable{}, nil, nErr
		}
		suTable, _, err = resolveHierarchyBreakpointsOnSU(suTable, nodes, HierarchyBreakpointOptions{
			BreakpointPolicy: breakpointPolicy,
			StripTildePrefix: true,
		})
		if err != nil {
			return vprocore.ProjectMetadataTable{}, nil, err
		}
	}
	return suTable, qualityResult, nil
}

func extractDistinctTextSUPlots(suTable vprocore.ProjectMetadataTable) []string {
	if len(suTable.Rows) == 0 || len(suTable.Rows) > 900 {
		return nil
	}
	plotColIdx := -1
	for cIdx, col := range suTable.Columns {
		if strings.EqualFold(col.Name, "PlotNumber") {
			plotColIdx = cIdx
			break
		}
	}
	if plotColIdx < 0 {
		return nil
	}
	seen := make(map[string]struct{}, len(suTable.Rows))
	out := make([]string, 0, len(suTable.Rows))
	for _, r := range suTable.Rows {
		cell := r.Cells[plotColIdx]
		if cell.Storage != "text" || cell.Text == nil {
			return nil
		}
		if _, ok := seen[*cell.Text]; !ok {
			seen[*cell.Text] = struct{}{}
			out = append(out, *cell.Text)
		}
	}
	return out
}

func loadSummaryFilteredVegTable(ctx context.Context, tx *sql.Tx, project string, suTable, masterSpecs vprocore.ProjectMetadataTable, lumpTable string, combineVariants bool) (vprocore.ProjectMetadataTable, string, error) {
	vegTableName := project + "_Veg"
	vegOK, err := summaryHasPhysicalTable(ctx, tx, "project", vegTableName)
	if err != nil {
		return vprocore.ProjectMetadataTable{}, "", err
	}
	if !vegOK {
		return vprocore.ProjectMetadataTable{}, "", fmt.Errorf("Summary Vegetation requires original physical table %s.%s", "project", vegTableName)
	}
	var totalVegRows int
	_ = tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM "project".`+vprocore.QuoteHeaderIdentifier(vegTableName)).Scan(&totalVegRows)
	var rawVeg vprocore.ProjectMetadataTable
	if totalVegRows > 50000 {
		if suPlotFilter := extractDistinctTextSUPlots(suTable); len(suPlotFilter) > 0 {
			rawVeg, err = vprocore.ReadSQLiteStorageRowsIn(ctx, tx, "project", vegTableName, "PlotNumber", suPlotFilter, "")
		} else {
			rawVeg, err = vprocore.ReadSQLiteStorageRows(ctx, tx, "project", vegTableName, "", nil, "")
		}
	} else {
		rawVeg, err = vprocore.ReadSQLiteStorageRows(ctx, tx, "project", vegTableName, "", nil, "")
	}
	if err != nil {
		return vprocore.ProjectMetadataTable{}, "", err
	}
	effectiveVeg, appliedLumpLabel, _, err := applySummaryVegetationLumpAndVariants(ctx, tx, rawVeg, masterSpecs, lumpTable, combineVariants)
	return effectiveVeg, appliedLumpLabel, err
}

func buildSummaryPreviewTransport(ctx context.Context, contextID string, owner *vprocore.SqliteContext, average, display, showClass, groupAndOrder int, mode summaryVegetationGroupedMode, report summaryVegetationLayerReport, grouped summaryVegetationGroupedReport, references *summaryVegetationReferencePlan, suTable vprocore.ProjectMetadataTable) (SummaryVegetationPreview, error) {
	result := SummaryVegetationPreview{
		ContextID: contextID, Project: owner.Selection.Project, ProjectPath: owner.Selection.ProjectPath,
		SU: owner.Selection.SU, SUPath: owner.Selection.SUPath, Average: average, Display: display, ShowClass: showClass,
		Source: "literal-normal-su-layer", Ordering: "literal-null-first-layer-species",
		Memberships: []reportcore.VegetationReportMembership{}, Units: []SummaryVegetationUnit{},
		Columns: append([]string{}, report.Columns...), Rows: []SummaryVegetationRow{},
	}
	if references != nil {
		result.Source = "literal-normal-su-effective-references"
		result.References = &references.Review
		if references.Review.ShowCommon {
			result.Ordering = "literal-null-first-layer-species-common"
		}
	}
	if groupAndOrder != 11 {
		result.GroupAndOrder = groupAndOrder
		result.GroupField = &SummaryVegetationField{grouped.GroupField.Name, grouped.GroupField.DAOType, grouped.GroupField.Size}
		result.OrderField = &SummaryVegetationField{grouped.OrderField.Name, grouped.OrderField.DAOType, grouped.OrderField.Size}
		result.Source = "literal-normal-su-grouped"
		result.Ordering = "literal-null-first-group-species"
		if references != nil {
			result.Source = "literal-normal-su-effective-references"
			if references.Review.ShowCommon {
				result.Ordering = "literal-null-first-layer-species-common"
			}
		}
	}
	if mode == summaryVegetationGroupedConstancy {
		result.Source, result.Ordering = summaryVegetationConstancySource, summaryVegetationConstancyOrdering
	}
	if mode == summaryVegetationGroupedUnanimousCommon {
		result.Source, result.Ordering = summaryVegetationUnanimousCommonSource, summaryVegetationUnanimousCommonOrdering
	}
	uc, err := vprocore.SiteUnitTransferColumns(suTable, "PlotNumber", "SiteUnit")
	if err != nil {
		return SummaryVegetationPreview{}, err
	}
	for _, row := range suTable.Rows {
		if err := ctx.Err(); err != nil {
			return SummaryVegetationPreview{}, err
		}
		result.Memberships = append(result.Memberships, reportcore.VegetationReportMembership{
			RowID: row.RowID, PlotNumber: vprocore.CloneSiteUnitCell(row.Cells[uc["PlotNumber"]]),
			SiteUnit: vprocore.CloneSiteUnitCell(row.Cells[uc["SiteUnit"]]),
		})
	}
	for _, unit := range report.Units {
		if err := ctx.Err(); err != nil {
			return SummaryVegetationPreview{}, err
		}
		result.Units = append(result.Units, SummaryVegetationUnit{Code: unit.Code, NumPlots: unit.NumPlots,
			MembershipIDs: append([]string{}, unit.MembershipIDs...), RawVegRowIDs: append([]string{}, unit.RawVegRowIDs...)})
	}
	for _, row := range report.Rows {
		if err := ctx.Err(); err != nil {
			return SummaryVegetationPreview{}, err
		}
		transport, err := cloneSummaryVegetationRowTransport(ctx, row)
		if err != nil {
			return SummaryVegetationPreview{}, err
		}
		result.Rows = append(result.Rows, transport)
	}
	return result, nil
}

func cloneSummaryVegetationRowTransport(ctx context.Context, row summaryVegetationLayerRow) (SummaryVegetationRow, error) {
	transport := SummaryVegetationRow{
		Layer: vprocore.CloneSiteUnitCell(row.Layer), Species: vprocore.CloneSiteUnitCell(row.Species),
		Order: vprocore.CloneSiteUnitCell(row.Order), Covers: []vprocore.ProjectMetadataCell{}, Witnesses: []SummaryVegetationWitness{},
	}
	if row.CommonName != nil {
		value := vprocore.CloneSiteUnitCell(*row.CommonName)
		transport.CommonName = &value
	}
	if row.RawSpecies != nil {
		value := vprocore.CloneSiteUnitCell(*row.RawSpecies)
		transport.RawSpecies = &value
	}
	for _, cell := range row.Covers {
		if err := ctx.Err(); err != nil {
			return SummaryVegetationRow{}, err
		}
		transport.Covers = append(transport.Covers, vprocore.CloneSiteUnitCell(cell))
	}
	for _, witness := range row.Witnesses {
		if err := ctx.Err(); err != nil {
			return SummaryVegetationRow{}, err
		}
		origins := make([]SummaryVegetationReferenceOrigin, 0, len(witness.ReferenceOrigins))
		for _, origin := range witness.ReferenceOrigins {
			origins = append(origins, SummaryVegetationReferenceOrigin{Table: origin.Table, RowID: origin.RowID})
		}
		transport.Witnesses = append(transport.Witnesses, SummaryVegetationWitness{
			StageRowID: witness.StageRowID, ConversionLayerID: witness.ConversionLayerID,
			MembershipID: witness.MembershipID, Unit: witness.Unit, LayerMapID: witness.LayerMapID,
			ReferenceOrigins: origins, RawVegRowIDs: append([]string{}, witness.RawVegRowIDs...),
			Cover: vprocore.CloneSiteUnitCell(witness.Cover),
		})
	}
	return transport, nil
}

func (s *SummaryVegetationService) readSnapshotConfigured(ctx context.Context, contextID string, plots *vprocore.PlotService,
	owner *vprocore.SqliteContext, tx *sql.Tx, average, display, showClass, groupAndOrder int,
	options *SummaryVegetationReferenceOptions, mode summaryVegetationGroupedMode,
	req SummaryVegetationConfiguredRequest, saved *SummaryVegetationAppliedPreferences, valueLimit float64) (summaryVegetationSnapshotPreview, error) {
	fail := func(err error) (summaryVegetationSnapshotPreview, error) {
		return summaryVegetationSnapshotPreview{}, err
	}
	if err := validateSummarySnapshotMode(mode, groupAndOrder, display, showClass, options); err != nil {
		return fail(err)
	}
	quality, err := ReadSummaryVegetationQualityPreferences(plots.Projects.Preferences, ctx)
	if err != nil {
		return fail(err)
	}
	pres, err := resolveSummaryEffectivePresentation(ctx, plots.Projects.Preferences, owner.Selection, req)
	if err != nil {
		return fail(err)
	}

	tables := make([]vprocore.ProjectMetadataTable, 5)
	for _, item := range []struct {
		idx         int
		role, table string
	}{
		{2, "VLists", "USysAllSpecs"},
		{3, "VUser", "USysUserSpp"},
		{4, "VPro64", "LayerCode"},
	} {
		tbl, rErr := summaryReadRequiredTable(ctx, tx, item.role, item.table)
		if rErr != nil {
			return fail(rErr)
		}
		tables[item.idx] = tbl
	}

	var qualityResult *SummaryVegetationQualityFilterResult
	tables[1], qualityResult, err = loadSummaryScopeSUTable(ctx, tx, owner, pres, quality, req.BreakpointPolicy)
	if err != nil {
		return fail(err)
	}

	var appliedLumpLabel string
	tables[0], appliedLumpLabel, err = loadSummaryFilteredVegTable(ctx, tx, owner.Selection.Project, tables[1], tables[2], pres.lumpTable, pres.combineVariants)
	if err != nil {
		return fail(err)
	}

	var descriptions *vprocore.ProjectMetadataTable
	var references *summaryVegetationReferencePlan
	if options != nil {
		ok, dErr := summaryHasPhysicalTable(ctx, tx, "VLists", "USysSppAttributeDescription")
		if dErr != nil {
			return fail(dErr)
		}
		if !ok {
			return fail(errors.New("Summary effective references require original physical VLists.USysSppAttributeDescription"))
		}
		table, rErr := vprocore.ReadSQLiteStorageRows(ctx, tx, "VLists", "USysSppAttributeDescription", "", nil, "")
		if rErr != nil {
			return fail(rErr)
		}
		plan, pErr := prepareSummaryVegetationReferences(ctx, tables[2], tables[3], table, *options)
		if pErr != nil {
			return fail(pErr)
		}
		descriptions, references = &table, &plan
	}

	effectiveSUName := owner.Selection.SU
	if (effectiveSUName == "" || effectiveSUName == "None") && pres.scope != "su" {
		switch pres.scope {
		case "hierarchy":
			effectiveSUName = "USysSuTableDynamic"
		case "field":
			effectiveSUName = "Field_" + pres.unitField
		default:
			effectiveSUName = "All_Plots"
		}
	}

	var report summaryVegetationLayerReport
	var grouped summaryVegetationGroupedReport
	switch {
	case groupAndOrder == 11:
		report, err = prepareSummaryVegetationLayerReferences(ctx, owner.Selection.Project, effectiveSUName,
			tables[0], tables[1], tables[2], tables[3], tables[4], average, display, showClass, references)
	case mode == summaryVegetationGroupedConstancy:
		grouped, err = prepareSummaryVegetationConstancyReferences(ctx, owner.Selection.Project, effectiveSUName,
			tables[0], tables[1], tables[2], tables[3], tables[4], average, references)
		report = grouped.Report
	case mode == summaryVegetationGroupedUnanimousCommon:
		grouped, err = prepareSummaryVegetationUnanimousCommonReferences(ctx, owner.Selection.Project, effectiveSUName,
			tables[0], tables[1], tables[2], tables[3], tables[4], average, groupAndOrder, references)
		report = grouped.Report
	default:
		grouped, err = prepareSummaryVegetationGroupedReferences(ctx, owner.Selection.Project, effectiveSUName,
			tables[0], tables[1], tables[2], tables[3], tables[4], average, groupAndOrder, display, showClass, references)
		report = grouped.Report
	}
	if err != nil {
		return fail(err)
	}

	result, err := buildSummaryPreviewTransport(ctx, contextID, owner, average, display, showClass, groupAndOrder, mode, report, grouped, references, tables[1])
	if err != nil {
		return fail(err)
	}
	if pres.scope != "su" && (result.SU == "" || result.SU == "None") {
		result.SU = effectiveSUName
		if result.SUPath == "" {
			result.SUPath = owner.Selection.ProjectPath
		}
	}
	if valueLimit > 0 {
		result.Rows = filterSummaryRowsByValueLimit(result.Rows, valueLimit)
		result.ValueLimit = valueLimit
	}
	if qualityResult != nil {
		result.Quality = qualityResult
	}
	if pres.combineVariants {
		result.CombineVariants = true
	}
	if appliedLumpLabel != "" {
		result.LumpTable = appliedLumpLabel
	}
	if pres.scope != "su" {
		result.UnitScope = pres.scope
		if pres.scope == "field" {
			result.UnitField = pres.unitField
		}
	}
	if pres.hierarchyHeader {
		if err := populateSummaryHierarchyHeaders(ctx, tx, owner.Selection.Hierarchy, &result); err != nil {
			return fail(err)
		}
	}
	if req.IncludeGoldstreamMetadata && display == 5 {
		result.Goldstream = buildSummaryGoldstreamMetadata(result)
	}
	if saved != nil {
		copied := *saved
		if appliedLumpLabel != "" {
			copied.LumpTable = appliedLumpLabel
		}
		result.AppliedPreferences = &copied
	}
	if err := ctx.Err(); err != nil {
		return fail(err)
	}
	return summaryVegetationSnapshotPreview{Preview: result, SU: tables[1], Veg: tables[0], Master: tables[2],
		Personal: tables[3], Layers: tables[4], Descriptions: descriptions}, nil
}
