package vegreport

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"strconv"

	"github.com/boostao/vpro/app/internal/reports/reportcore"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type summaryVegetationLayerWitness struct {
	StageRowID        string
	ConversionLayerID string
	MembershipID      string
	Unit              string
	LayerMapID        string
	ReferenceOrigins  []reportcore.VegetationLifeformReferenceOrigin
	RawVegRowIDs      []string
	Cover             vprocore.ProjectMetadataCell
}

type summaryVegetationLayerRow struct {
	Layer        vprocore.ProjectMetadataCell
	Species      vprocore.ProjectMetadataCell
	CommonName   *vprocore.ProjectMetadataCell `json:"CommonName,omitempty"`
	RawSpecies   *vprocore.ProjectMetadataCell `json:"RawSpecies,omitempty"`
	Order        vprocore.ProjectMetadataCell
	Covers       []vprocore.ProjectMetadataCell
	Witnesses    []summaryVegetationLayerWitness
	numericGroup *int
}

type summaryVegetationLayerReport struct {
	Units   []summaryVegetationUnit
	Columns []string
	Rows    []summaryVegetationLayerRow
}

type summaryStageLayerMapping struct {
	id    string
	label vprocore.ProjectMetadataCell
}

type summaryStageGroupKey struct {
	layer, species, common, rawSpecies string
}

type summaryStageGroup struct {
	row          summaryVegetationLayerRow
	covers       map[string][]vprocore.ProjectMetadataCell
	sourceCommon string
}

type summaryStageContext struct {
	ctx           context.Context
	projection    summaryVegetationStageProjection
	showCommon    bool
	stageCols     map[string]int
	refCols       map[string]int
	suCols        map[string]int
	mappings      map[string]summaryStageLayerMapping
	references    reportcore.VegetationLifeformReferences
	refRows       map[string][]vprocore.ProjectMetadataRow
	numericGroups map[string]*int
	members       map[string][]vprocore.ProjectMetadataRow
	denominators  map[string]int64
}

func prepareSummaryVegetationLayerReferences(ctx context.Context, project, suName string,
	veg, su, master, personal, layers vprocore.ProjectMetadataTable, average, display, showClass int,
	references *summaryVegetationReferencePlan) (summaryVegetationLayerReport, error) {
	if err := validateSummaryVegetationDisplayOptions(ctx, average, display, showClass); err != nil {
		return summaryVegetationLayerReport{}, err
	}
	prepared, err := prepareLongVegetation(ctx, project, suName, veg, su, layers)
	if err != nil {
		return summaryVegetationLayerReport{}, fmt.Errorf("summary vegetation layer source preparation: %w", err)
	}
	if err := reportcore.LifeformSummaryText(vprocore.ProjectMetadataCell{Storage: "text", Text: &project}, 20); err != nil {
		return summaryVegetationLayerReport{}, fmt.Errorf("summary vegetation staged ProjectID: %w", err)
	}
	stage, origins, conversionLayers, err := buildSummaryStageTableFromPrepared(ctx, prepared)
	if err != nil {
		return summaryVegetationLayerReport{}, err
	}
	result, err := planSummaryVegetationStage(ctx, veg, su, stage, master, personal, layers, average, display, showClass,
		summaryVegetationStageProjection{joinField: "Layer1234567", joinLimit: 2, labelField: "Layer", labelLimit: 3, references: references})
	if err != nil {
		return summaryVegetationLayerReport{}, err
	}
	if err := attachSummaryStageWitnessProvenance(ctx, &result, origins, conversionLayers); err != nil {
		return summaryVegetationLayerReport{}, err
	}
	return result, nil
}

type summaryPreparedSourceKey struct{ plot, species string }

func buildSummaryStageTableFromPrepared(
	ctx context.Context,
	prepared VegetationReportPreparation,
) (vprocore.ProjectMetadataTable, map[string][]string, map[string]string, error) {
	sourceIDs, err := indexReducedRowSourceIDs(ctx, prepared.ReducedRows)
	if err != nil {
		return vprocore.ProjectMetadataTable{}, nil, nil, err
	}
	stage := vprocore.ProjectMetadataTable{
		Columns: []vprocore.ProjectMetadataColumn{{Name: "Plotnumber"}, {Name: "Layer"}, {Name: "Species"}, {Name: "Cover"}},
		Rows:    []vprocore.ProjectMetadataRow{},
	}
	origins := map[string][]string{}
	conversionLayers := map[string]string{}
	for i, observation := range prepared.Observations {
		if err := ctx.Err(); err != nil {
			return vprocore.ProjectMetadataTable{}, nil, nil, err
		}
		number, err := vprocore.VegetationReportNumber(observation.Cover)
		if err != nil {
			return vprocore.ProjectMetadataTable{}, nil, nil, err
		}
		value, err := reportcore.LifeformSummarySingle(number)
		if err != nil {
			return vprocore.ProjectMetadataTable{}, nil, nil, fmt.Errorf("summary vegetation layer staged SINGLE: %w", err)
		}
		if observation.Cover.Real != nil && *observation.Cover.Real == 0 {
			value = *observation.Cover.Real
		}
		id := strconv.Itoa(i + 1)
		stage.Rows = append(stage.Rows, vprocore.ProjectMetadataRow{
			RowID: id,
			Cells: []vprocore.ProjectMetadataCell{
				{Storage: "text", Text: &observation.PlotNumber},
				{Storage: "text", Text: &observation.Layer},
				vprocore.CloneSiteUnitCell(observation.Species),
				{Storage: "real", Real: &value},
			},
		})
		origins[id] = sourceIDs[summaryPreparedSourceKey{observation.PlotNumber, reportcore.VegetationTextKey(observation.Species)}]
		conversionLayers[id] = observation.LayerRowID
	}
	return stage, origins, conversionLayers, nil
}

func indexReducedRowSourceIDs(ctx context.Context, rows []VegetationReportReducedRow) (map[summaryPreparedSourceKey][]string, error) {
	sourceIDs := map[summaryPreparedSourceKey][]string{}
	for _, row := range rows {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		if row.PlotNumber == "" || row.Species.Text == nil || *row.Species.Text == "" {
			return nil, errors.New("summary vegetation TempReportVeg requires nonempty PlotNumber/Species; no source omission")
		}
		if err := reportcore.LifeformSummaryText(vprocore.ProjectMetadataCell{Storage: "text", Text: &row.PlotNumber}, 7); err != nil {
			return nil, fmt.Errorf("summary vegetation TempReportVeg PlotNumber: %w", err)
		}
		if err := reportcore.LifeformSummaryText(row.Species, 8); err != nil {
			return nil, fmt.Errorf("summary vegetation TempReportVeg Species: %w", err)
		}
		for _, cover := range row.Covers {
			if err := ctx.Err(); err != nil {
				return nil, err
			}
			number, err := vprocore.VegetationReportNumber(cover)
			if err != nil {
				return nil, err
			}
			if number != nil {
				if _, err := reportcore.LifeformSummarySingle(number); err != nil {
					return nil, fmt.Errorf("summary vegetation TempReportVeg SINGLE: %w", err)
				}
			}
		}
		sourceIDs[summaryPreparedSourceKey{row.PlotNumber, reportcore.VegetationTextKey(row.Species)}] = row.SourceRowIDs
	}
	return sourceIDs, nil
}

func attachSummaryStageWitnessProvenance(
	ctx context.Context,
	result *summaryVegetationLayerReport,
	origins map[string][]string,
	conversionLayers map[string]string,
) error {
	for i := range result.Rows {
		for j := range result.Rows[i].Witnesses {
			if err := ctx.Err(); err != nil {
				return err
			}
			witness := &result.Rows[i].Witnesses[j]
			witness.RawVegRowIDs = append([]string{}, origins[witness.StageRowID]...)
			witness.ConversionLayerID = conversionLayers[witness.StageRowID]
		}
	}
	return nil
}

type summaryVegetationStageProjection struct {
	joinField       string
	joinLimit       int
	labelField      string
	labelLimit      int
	nullGroup       bool
	numericOrder    bool
	references      *summaryVegetationReferencePlan
	constancy       bool
	unanimousCommon bool
}

func planSummaryVegetationStage(ctx context.Context,
	raw, su, stage, master, personal, layers vprocore.ProjectMetadataTable, average, display, showClass int,
	projection summaryVegetationStageProjection) (summaryVegetationLayerReport, error) {
	if err := validateSummaryStageOptions(ctx, average, display, showClass, projection); err != nil {
		return summaryVegetationLayerReport{}, err
	}
	units, sctx, err := buildSummaryStageContext(ctx, raw, su, stage, master, personal, layers, projection)
	if err != nil {
		return summaryVegetationLayerReport{}, err
	}
	groups, columns, err := sctx.collectStageGroups(stage)
	if err != nil {
		return summaryVegetationLayerReport{}, err
	}
	result := summaryVegetationLayerReport{Units: units, Columns: columns, Rows: []summaryVegetationLayerRow{}}
	if err := sctx.calculateStageGroupRows(groups, average, display, showClass, &result); err != nil {
		return summaryVegetationLayerReport{}, err
	}
	sortSummaryStageRows(result.Rows, projection.constancy, sctx.showCommon)
	if err := ctx.Err(); err != nil {
		return summaryVegetationLayerReport{}, err
	}
	return result, nil
}

func validateSummaryStageOptions(ctx context.Context, average, display, showClass int, projection summaryVegetationStageProjection) error {
	if err := validateSummaryVegetationDisplayOptions(ctx, average, display, showClass); err != nil {
		return err
	}
	if projection.unanimousCommon && (projection.constancy || projection.references == nil ||
		!projection.references.Review.ShowCommon || !projection.numericOrder || display != 6 || showClass != 0) {
		return errors.New("summary vegetation unanimous First(common name) requires a non-Constancy effective common Display6 projection")
	}
	return nil
}

func buildSummaryStageContext(
	ctx context.Context,
	raw, su, stage, master, personal, layers vprocore.ProjectMetadataTable,
	projection summaryVegetationStageProjection,
) ([]summaryVegetationUnit, *summaryStageContext, error) {
	units, err := prepareSummaryVegetationUnits(ctx, raw, su)
	if err != nil {
		return nil, nil, err
	}
	references, showCommon, err := resolveSummaryStageReferences(ctx, master, personal, projection)
	if err != nil {
		return nil, nil, err
	}
	sc, err := vprocore.SiteUnitTransferColumns(stage, "Plotnumber", "Layer", "Species", "Cover")
	if err != nil {
		return nil, nil, fmt.Errorf("summary vegetation staged schema: %w", err)
	}
	mappings, err := buildSummaryLayerMappings(ctx, layers, projection)
	if err != nil {
		return nil, nil, err
	}
	rc, refRows, numericGroups, err := indexSummaryStageReferenceRows(ctx, references, projection)
	if err != nil {
		return nil, nil, err
	}
	denominators := map[string]int64{}
	for _, unit := range units {
		denominators[unit.Code] = int64(unit.NumPlots)
	}
	uc, members, err := indexSummaryStageSUMembers(ctx, su, denominators)
	if err != nil {
		return nil, nil, err
	}
	return units, &summaryStageContext{
		ctx:           ctx,
		projection:    projection,
		showCommon:    showCommon,
		stageCols:     sc,
		refCols:       rc,
		suCols:        uc,
		mappings:      mappings,
		references:    references,
		refRows:       refRows,
		numericGroups: numericGroups,
		members:       members,
		denominators:  denominators,
	}, nil
}

func resolveSummaryStageReferences(
	ctx context.Context,
	master, personal vprocore.ProjectMetadataTable,
	projection summaryVegetationStageProjection,
) (reportcore.VegetationLifeformReferences, bool, error) {
	if projection.references != nil {
		return projection.references.References, projection.references.Review.ShowCommon, nil
	}
	refs, err := reportcore.PrepareVegetationLifeformReferences(ctx, master, personal)
	if err != nil {
		return reportcore.VegetationLifeformReferences{}, false, fmt.Errorf("summary vegetation layer references: %w", err)
	}
	return refs, false, nil
}

func buildSummaryLayerMappings(
	ctx context.Context,
	layers vprocore.ProjectMetadataTable,
	projection summaryVegetationStageProjection,
) (map[string]summaryStageLayerMapping, error) {
	lc, err := vprocore.SiteUnitTransferColumns(layers, projection.joinField, projection.labelField)
	if err != nil {
		return nil, fmt.Errorf("summary vegetation layer mapping schema: %w", err)
	}
	mappings := map[string]summaryStageLayerMapping{}
	for _, row := range layers.Rows {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		code, err := vprocore.VegetationReportIdentity(row.Cells[lc[projection.joinField]])
		if err != nil {
			return nil, fmt.Errorf("summary vegetation layer mapping row %s: %w", row.RowID, err)
		}
		for name, limit := range map[string]int{projection.joinField: projection.joinLimit, projection.labelField: projection.labelLimit} {
			if err := reportcore.LifeformSummaryText(row.Cells[lc[name]], limit); err != nil {
				return nil, fmt.Errorf("summary vegetation layer mapping row %s %s: %w", row.RowID, name, err)
			}
		}
		if code != nil {
			if _, exists := mappings[*code]; exists {
				return nil, fmt.Errorf("summary vegetation layer mapping has duplicate literal %s; original unique index is unavailable", projection.joinField)
			}
			label := vprocore.ProjectMetadataCell{Storage: "null"}
			if !projection.nullGroup {
				label = vprocore.CloneSiteUnitCell(row.Cells[lc[projection.labelField]])
			}
			mappings[*code] = summaryStageLayerMapping{row.RowID, label}
		}
	}
	return mappings, nil
}

func indexSummaryStageReferenceRows(
	ctx context.Context,
	references reportcore.VegetationLifeformReferences,
	projection summaryVegetationStageProjection,
) (map[string]int, map[string][]vprocore.ProjectMetadataRow, map[string]*int, error) {
	rc, err := vprocore.SiteUnitTransferColumns(references.Table, reportcore.VegetationLifeformReferenceColumns...)
	if err != nil {
		return nil, nil, nil, err
	}
	refRows := map[string][]vprocore.ProjectMetadataRow{}
	numericGroups := map[string]*int{}
	for _, row := range references.Table.Rows {
		if err := ctx.Err(); err != nil {
			return nil, nil, nil, err
		}
		if err := validateSummaryReferenceRowText(row, rc, references.Origins[row.RowID], projection.references == nil); err != nil {
			return nil, nil, nil, err
		}
		if projection.constancy {
			if err := recordConstancyNumericGroup(row, rc, numericGroups); err != nil {
				return nil, nil, nil, err
			}
		}
		if code := row.Cells[rc["Code"]].Text; code != nil {
			refRows[*code] = append(refRows[*code], row)
		}
	}
	return rc, refRows, numericGroups, nil
}

func validateSummaryReferenceRowText(
	row vprocore.ProjectMetadataRow,
	rc map[string]int,
	origins []reportcore.VegetationLifeformReferenceOrigin,
	checkOriginLimits bool,
) error {
	codeLimit, typeLimit := 255, 255
	if checkOriginLimits {
		for _, origin := range origins {
			if origin.Table == "USysUserSpp" {
				codeLimit, typeLimit = 8, 50
				break
			}
		}
	}
	for name, limit := range map[string]int{"Code": codeLimit, "ScientificName": 255, "EnglishName": 255, "Codetype": typeLimit} {
		if err := reportcore.LifeformSummaryText(row.Cells[rc[name]], limit); err != nil {
			return fmt.Errorf("summary vegetation layer reference row %s %s: %w", row.RowID, name, err)
		}
	}
	return nil
}

func recordConstancyNumericGroup(row vprocore.ProjectMetadataRow, rc map[string]int, numericGroups map[string]*int) error {
	if row.RowID == "" {
		return errors.New("summary vegetation Constancy reference requires a physical projection identity")
	}
	if _, exists := numericGroups[row.RowID]; exists {
		return errors.New("summary vegetation Constancy has duplicate reference projection identities")
	}
	number, err := summaryVegetationMasterLongInteger(row.Cells[rc["Lifeform"]])
	if err != nil {
		return fmt.Errorf("summary vegetation Constancy reference row %s: %w", row.RowID, err)
	}
	numericGroups[row.RowID] = number
	return nil
}

func indexSummaryStageSUMembers(
	ctx context.Context,
	su vprocore.ProjectMetadataTable,
	denominators map[string]int64,
) (map[string]int, map[string][]vprocore.ProjectMetadataRow, error) {
	uc, err := vprocore.SiteUnitTransferColumns(su, "PlotNumber", "SiteUnit")
	if err != nil {
		return nil, nil, err
	}
	members := map[string][]vprocore.ProjectMetadataRow{}
	for _, row := range su.Rows {
		if err := ctx.Err(); err != nil {
			return nil, nil, err
		}
		plot, unit := row.Cells[uc["PlotNumber"]].Text, row.Cells[uc["SiteUnit"]].Text
		if plot != nil && unit != nil && denominators[*unit] > 0 {
			members[*plot] = append(members[*plot], row)
		}
	}
	return uc, members, nil
}

func (s *summaryStageContext) collectStageGroups(stage vprocore.ProjectMetadataTable) (map[summaryStageGroupKey]*summaryStageGroup, []string, error) {
	groups := map[summaryStageGroupKey]*summaryStageGroup{}
	pivot := map[string]bool{}
	for _, row := range stage.Rows {
		if err := s.ctx.Err(); err != nil {
			return nil, nil, err
		}
		if err := s.processStageRow(row, groups, pivot); err != nil {
			return nil, nil, err
		}
	}
	columns := make([]string, 0, len(pivot))
	for code := range pivot {
		columns = append(columns, code)
	}
	sort.Strings(columns)
	return groups, columns, nil
}

func (s *summaryStageContext) processStageRow(
	row vprocore.ProjectMetadataRow,
	groups map[summaryStageGroupKey]*summaryStageGroup,
	pivot map[string]bool,
) error {
	for name, limit := range map[string]int{"Plotnumber": 8, "Layer": 3, "Species": 8} {
		if err := reportcore.LifeformSummaryText(row.Cells[s.stageCols[name]], limit); err != nil {
			return fmt.Errorf("summary vegetation stage row %s %s: %w", row.RowID, name, err)
		}
	}
	plot := row.Cells[s.stageCols["Plotnumber"]].Text
	species := row.Cells[s.stageCols["Species"]]
	if plot == nil || *plot == "" || species.Text != nil && *species.Text == "" {
		return fmt.Errorf("summary vegetation stage row %s requires nonempty Plotnumber and nonempty-or-NULL Species; no source omission or truncation", row.RowID)
	}
	cover := row.Cells[s.stageCols["Cover"]]
	if _, err := aggregateSummaryVegetationCovers(s.ctx, []vprocore.ProjectMetadataCell{cover}, 1); err != nil {
		return fmt.Errorf("summary vegetation stage row %s: %w", row.RowID, err)
	}
	mapping := summaryStageLayerMapping{label: vprocore.ProjectMetadataCell{Storage: "null"}}
	if code := row.Cells[s.stageCols["Layer"]].Text; code != nil {
		if found, exists := s.mappings[*code]; exists {
			mapping = found
		}
	}
	matches := []vprocore.ProjectMetadataRow{}
	if species.Text != nil {
		matches = s.refRows[*species.Text]
	}
	if len(matches) == 0 {
		matches = []vprocore.ProjectMetadataRow{{}}
	}
	for _, member := range s.members[*plot] {
		if err := s.ctx.Err(); err != nil {
			return err
		}
		unit := *member.Cells[s.suCols["SiteUnit"]].Text
		for _, ref := range matches {
			if err := s.ctx.Err(); err != nil {
				return err
			}
			if err := s.recordMemberRefObservation(row.RowID, member.RowID, unit, species, cover, mapping, ref, groups, pivot); err != nil {
				return err
			}
		}
	}
	return nil
}

func (s *summaryStageContext) recordMemberRefObservation(
	stageRowID, memberRowID, unit string,
	species, cover vprocore.ProjectMetadataCell,
	mapping summaryStageLayerMapping,
	ref vprocore.ProjectMetadataRow,
	groups map[summaryStageGroupKey]*summaryStageGroup,
	pivot map[string]bool,
) error {
	name := species
	common := vprocore.ProjectMetadataCell{Storage: "null"}
	var origins []reportcore.VegetationLifeformReferenceOrigin
	if ref.RowID != "" {
		if scientific := ref.Cells[s.refCols["ScientificName"]]; scientific.Storage != "null" {
			name = scientific
		}
		origins = append(origins, s.references.Origins[ref.RowID]...)
		common = ref.Cells[s.refCols["EnglishName"]]
	}
	label, key, number := s.buildGroupKeyAndLabel(mapping.label, name, species, common, ref.RowID)
	g := groups[key]
	if g != nil && s.projection.unanimousCommon && g.sourceCommon != reportcore.VegetationTextKey(common) {
		return fmt.Errorf("summary vegetation First(common name) is ambiguous for literal group %q species %q; all contributing common names must match, including NULL/empty", key.layer, key.species)
	}
	if g == nil {
		g = s.newSummaryStageGroup(label, name, species, common, number)
		groups[key] = g
	}
	pivot[unit] = true
	g.covers[unit] = append(g.covers[unit], vprocore.CloneSiteUnitCell(cover))
	g.row.Witnesses = append(g.row.Witnesses, summaryVegetationLayerWitness{
		StageRowID: stageRowID, MembershipID: memberRowID, Unit: unit,
		LayerMapID: mapping.id, ReferenceOrigins: origins, RawVegRowIDs: []string{},
		Cover: vprocore.CloneSiteUnitCell(cover),
	})
	return nil
}

func (s *summaryStageContext) buildGroupKeyAndLabel(
	mappingLabel, name, species, common vprocore.ProjectMetadataCell,
	refRowID string,
) (vprocore.ProjectMetadataCell, summaryStageGroupKey, *int) {
	label := mappingLabel
	key := summaryStageGroupKey{layer: reportcore.VegetationTextKey(label), species: reportcore.VegetationTextKey(name)}
	var number *int
	if s.projection.constancy {
		label = vprocore.ProjectMetadataCell{Storage: "null"}
		number = s.numericGroups[refRowID]
		key.layer, key.rawSpecies = "null", reportcore.VegetationTextKey(species)
		if number != nil {
			value := strconv.Itoa(*number)
			label = vprocore.ProjectMetadataCell{Storage: "integer", Integer: &value}
			key.layer = "integer:" + value
		}
	}
	if s.showCommon && !s.projection.unanimousCommon {
		key.common = reportcore.VegetationTextKey(common)
	}
	return label, key, number
}

func (s *summaryStageContext) newSummaryStageGroup(
	label, name, species, common vprocore.ProjectMetadataCell,
	number *int,
) *summaryStageGroup {
	g := &summaryStageGroup{
		row: summaryVegetationLayerRow{
			Layer:        vprocore.CloneSiteUnitCell(label),
			Species:      vprocore.CloneSiteUnitCell(name),
			Witnesses:    []summaryVegetationLayerWitness{},
			numericGroup: number,
		},
		covers: map[string][]vprocore.ProjectMetadataCell{},
	}
	if s.projection.constancy {
		raw := vprocore.CloneSiteUnitCell(species)
		g.row.RawSpecies = &raw
	}
	if s.showCommon {
		value := vprocore.CloneSiteUnitCell(common)
		if s.projection.unanimousCommon {
			g.sourceCommon = reportcore.VegetationTextKey(common)
			if value.Text != nil && *value.Text == "" {
				value = vprocore.ProjectMetadataCell{Storage: "null"}
			}
		}
		g.row.CommonName = &value
	}
	return g
}

func (s *summaryStageContext) calculateStageGroupRows(
	groups map[summaryStageGroupKey]*summaryStageGroup,
	average, display, showClass int,
	result *summaryVegetationLayerReport,
) error {
	for _, g := range groups {
		if err := s.ctx.Err(); err != nil {
			return err
		}
		g.row.Covers = []vprocore.ProjectMetadataCell{}
		g.row.Order = vprocore.ProjectMetadataCell{Storage: "null"}
		for _, unit := range result.Columns {
			if err := s.appendUnitGroupCell(g, unit, average, display, showClass); err != nil {
				return err
			}
		}
		if display == 1 || display == 3 || g.row.Order.Storage != "null" {
			result.Rows = append(result.Rows, g.row)
		}
	}
	return nil
}

func (s *summaryStageContext) appendUnitGroupCell(
	g *summaryStageGroup,
	unit string,
	average, display, showClass int,
) error {
	if len(g.covers[unit]) == 0 {
		g.row.Covers = append(g.row.Covers, vprocore.ProjectMetadataCell{Storage: "null"})
		return nil
	}
	input, err := aggregateSummaryVegetationCovers(s.ctx, g.covers[unit], s.denominators[unit])
	if err != nil {
		return fmt.Errorf("summary vegetation unit %q aggregate: %w", unit, err)
	}
	var cell summaryVegetationDisplayCell
	if showClass == 0 {
		cell, err = calculateSummaryVegetationDisplay(s.ctx, input, average, display)
	} else {
		cell, err = calculateSummaryVegetationClassDisplay(s.ctx, input, average, display, showClass)
	}
	if err != nil {
		return fmt.Errorf("summary vegetation unit %q cell: %w", unit, err)
	}
	g.row.Covers = append(g.row.Covers, vprocore.CloneSiteUnitCell(cell.Value))
	return updateSummaryGroupOrder(&g.row.Order, cell.Order, s.projection.numericOrder)
}

func updateSummaryGroupOrder(current *vprocore.ProjectMetadataCell, candidate vprocore.ProjectMetadataCell, numericOrder bool) error {
	if candidate.Text == nil {
		return nil
	}
	if numericOrder {
		value, err := strconv.ParseFloat(*candidate.Text, 64)
		if err != nil {
			return fmt.Errorf("summary vegetation numeric Order: %w", err)
		}
		if current.Real == nil || value > *current.Real {
			*current = vprocore.ProjectMetadataCell{Storage: "real", Real: &value}
		}
		return nil
	}
	if current.Text == nil || *candidate.Text > *current.Text {
		*current = vprocore.CloneSiteUnitCell(candidate)
	}
	return nil
}

func sortSummaryStageRows(rows []summaryVegetationLayerRow, constancy, showCommon bool) {
	sort.Slice(rows, func(i, j int) bool {
		return compareSummaryStageRows(rows[i], rows[j], constancy, showCommon)
	})
}

func compareSummaryStageRows(a, b summaryVegetationLayerRow, constancy, showCommon bool) bool {
	if constancy {
		if a.numericGroup == nil || b.numericGroup == nil {
			if a.numericGroup != nil || b.numericGroup != nil {
				return a.numericGroup == nil
			}
		} else if *a.numericGroup != *b.numericGroup {
			return *a.numericGroup < *b.numericGroup
		}
	} else if reportcore.VegetationTextKey(a.Layer) != reportcore.VegetationTextKey(b.Layer) {
		return compareNullableTextPtrs(a.Layer.Text, b.Layer.Text)
	}
	if reportcore.VegetationTextKey(a.Species) != reportcore.VegetationTextKey(b.Species) {
		return compareNullableTextPtrs(a.Species.Text, b.Species.Text)
	}
	if constancy && reportcore.VegetationTextKey(*a.RawSpecies) != reportcore.VegetationTextKey(*b.RawSpecies) {
		return compareNullableTextPtrs(a.RawSpecies.Text, b.RawSpecies.Text)
	}
	if showCommon {
		if a.CommonName.Text == nil || b.CommonName.Text == nil {
			return a.CommonName.Text == nil && b.CommonName.Text != nil
		}
		return *a.CommonName.Text < *b.CommonName.Text
	}
	return false
}

func compareNullableTextPtrs(left, right *string) bool {
	if left == nil || right == nil {
		return left == nil
	}
	return *left < *right
}
