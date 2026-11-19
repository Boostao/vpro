package vegreport

import (
	"context"
	"errors"
	"fmt"
	"math"
	"sort"

	"github.com/boostao/vpro/app/internal/reports/reportcore"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type vegetationLayerRow struct {
	Layer       vprocore.ProjectMetadataCell
	Species     vprocore.ProjectMetadataCell
	EnglishName vprocore.ProjectMetadataCell
	MatchedName vprocore.ProjectMetadataCell
	Presence    *float64
	MeanCover   *float64
	Plots       []vegetationCrosstabPlot
}

type vegetationLayerUnit struct {
	Code               vprocore.ProjectMetadataCell
	LongName           *string
	NameStatus         string
	NameCandidates     []vprocore.EnvironmentReportName
	NumPlots           int
	MembershipIDs      []string
	ProjectUnitIndexes []int
	Rows               []vegetationLayerRow
}

type vegetationLayerDiagnostic struct {
	Code, Identity string
	Count          int
}

type vegetationLayerReport struct {
	Project, SU, Title string
	SelectedFieldType  string
	Units              []vegetationLayerUnit
	Diagnostics        []vegetationLayerDiagnostic
	Quality            *vegetationQualitySelection
	NoneUnits          []vegetationNoneUnitOccurrence
	SelectedUnits      []vegetationSelectedUnitOccurrence
	ProjectUnits       []vegetationProjectUnitInput
}

type layerDisplayKey struct {
	layer, species, english string
}

type layerJoinedObs struct {
	key   vegetationCrosstabKey
	name  vprocore.ProjectMetadataCell
	plot  string
	cover vprocore.ProjectMetadataCell
}

type layerUnitState struct {
	unit   vegetationLayerUnit
	inputs []layerJoinedObs
}

type layerPlannerRefs struct {
	speciesCols  map[string]int
	layerCols    map[string]int
	speciesIndex map[string][]vprocore.ProjectMetadataRow
	layerIndex   map[string][]vprocore.ProjectMetadataRow
}

type layerPlannerAccumulator struct {
	units          map[string]*layerUnitState
	memberships    map[string][]string
	physicalCounts map[string]int
	active         map[string]bool
	constants      map[layerDisplayKey]layerJoinedObs
	diagnostics    map[string]vegetationLayerDiagnostic
}

func (a *layerPlannerAccumulator) diagnose(code, identity string, count int) {
	a.diagnostics[code+"\x00"+identity] = vegetationLayerDiagnostic{code, identity, count}
}

func planLongVegetationLayers(ctx context.Context, prepared VegetationReportPreparation,
	species, layers vprocore.ProjectMetadataTable, options longVegetationOptions) (vegetationLayerReport, error) {
	if err := validateLayerPlannerInputs(ctx, prepared, options); err != nil {
		return vegetationLayerReport{}, err
	}
	refs, err := buildLayerPlannerReferenceIndex(ctx, species, layers)
	if err != nil {
		return vegetationLayerReport{}, err
	}
	report := vegetationLayerReport{
		Project:     prepared.Project,
		SU:          prepared.SU,
		Title:       options.Title,
		Units:       []vegetationLayerUnit{},
		Diagnostics: []vegetationLayerDiagnostic{},
	}
	acc, err := buildLayerPlannerMemberships(ctx, prepared, &report)
	if err != nil {
		return vegetationLayerReport{}, err
	}
	if err := acc.joinObservations(ctx, prepared.Observations, refs, options); err != nil {
		return vegetationLayerReport{}, err
	}
	if err := acc.populateReportUnits(ctx, prepared, options, &report); err != nil {
		return vegetationLayerReport{}, err
	}
	for _, key := range vprocore.SortedEnvironmentReportKeys(acc.diagnostics) {
		report.Diagnostics = append(report.Diagnostics, acc.diagnostics[key])
	}
	if err := ctx.Err(); err != nil {
		return vegetationLayerReport{}, err
	}
	return report, nil
}

func validateLayerPlannerInputs(ctx context.Context, prepared VegetationReportPreparation, options longVegetationOptions) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	if prepared.projectUnitInputs != nil && (len(prepared.Memberships) != 0 ||
		prepared.selectedUnitOccurrences != nil || prepared.noneUnitMembershipCounts != nil || prepared.qualityMembershipCounts != nil) {
		return errors.New("project report units cannot carry selected-SU memberships or occurrence weights")
	}
	if prepared.Project == "" || prepared.SU == "" || options.Average != "all-plots" && options.Average != "observations" ||
		options.Order != "species" && options.Order != "presence" {
		return errors.New("layer planner requires owned preparation and supported explicit options")
	}
	for _, value := range []float64{options.PresenceGreaterThan, options.MeanCoverGreaterThan} {
		if math.IsNaN(value) || math.IsInf(value, 0) {
			return errors.New("layer planner thresholds must be finite")
		}
	}
	return nil
}

func buildLayerPlannerReferenceIndex(ctx context.Context, species, layers vprocore.ProjectMetadataTable) (layerPlannerRefs, error) {
	sc, err := vprocore.SiteUnitTransferColumns(species, "Code", "ScientificName", "EnglishName", "Codetype")
	if err != nil {
		return layerPlannerRefs{}, err
	}
	lc, err := vprocore.SiteUnitTransferColumns(layers, "Layer1234567", "Layer")
	if err != nil {
		return layerPlannerRefs{}, err
	}
	if err := verifyReferenceTableCells(ctx, species, sc, []string{"Code", "ScientificName", "EnglishName", "Codetype"}); err != nil {
		return layerPlannerRefs{}, err
	}
	if err := verifyReferenceTableCells(ctx, layers, lc, []string{"Layer1234567", "Layer"}); err != nil {
		return layerPlannerRefs{}, err
	}
	si, err := vprocore.SiteUnitTransferIndex(species, sc["Code"])
	if err != nil {
		return layerPlannerRefs{}, err
	}
	li, err := vprocore.SiteUnitTransferIndex(layers, lc["Layer1234567"])
	if err != nil {
		return layerPlannerRefs{}, err
	}
	return layerPlannerRefs{speciesCols: sc, layerCols: lc, speciesIndex: si, layerIndex: li}, nil
}

func verifyReferenceTableCells(ctx context.Context, table vprocore.ProjectMetadataTable, columns map[string]int, required []string) error {
	for _, row := range table.Rows {
		if err := ctx.Err(); err != nil {
			return err
		}
		for _, name := range required {
			if _, err := vprocore.VegetationReportIdentity(row.Cells[columns[name]]); err != nil {
				return fmt.Errorf("layer report reference row %s %s: %w", row.RowID, name, err)
			}
		}
	}
	return nil
}

func buildLayerPlannerMemberships(
	ctx context.Context,
	prepared VegetationReportPreparation,
	report *vegetationLayerReport,
) (*layerPlannerAccumulator, error) {
	acc := &layerPlannerAccumulator{
		units:          map[string]*layerUnitState{},
		memberships:    map[string][]string{},
		physicalCounts: map[string]int{},
		active:         map[string]bool{},
		constants:      map[layerDisplayKey]layerJoinedObs{},
		diagnostics:    map[string]vegetationLayerDiagnostic{},
	}
	if err := acc.collectSelectedMemberships(ctx, prepared); err != nil {
		return nil, err
	}
	if prepared.projectUnitInputs != nil {
		if err := acc.collectProjectUnitMemberships(ctx, prepared.projectUnitInputs, report); err != nil {
			return nil, err
		}
	}
	for _, row := range prepared.ReducedRows {
		for _, id := range acc.memberships[row.PlotNumber] {
			acc.active[id] = true
		}
	}
	for plot, count := range acc.physicalCounts {
		if count > 1 {
			code := "physical_membership_multiplicity"
			if prepared.projectUnitInputs != nil {
				code = "project_unit_join_multiplicity"
			}
			acc.diagnose(code, plot, count)
		}
	}
	return acc, nil
}

func (a *layerPlannerAccumulator) collectSelectedMemberships(ctx context.Context, prepared VegetationReportPreparation) error {
	reportMemberships, err := selectedUnitReportMemberships(ctx, prepared)
	if err != nil {
		return err
	}
	selectedIDs := map[string]map[string]bool{}
	selectedCounts := map[string]int{}
	var selectedOrder []string
	var qualityDiagnostics []vegetationLayerDiagnostic

	for _, member := range reportMemberships {
		if err := ctx.Err(); err != nil {
			return err
		}
		if err := validateMembershipIdentityCells(member); err != nil {
			return err
		}
		id := reportcore.VegetationTextKey(member.SiteUnit)
		state := a.ensureUnitState(id, member.SiteUnit, false)
		recordSelectedMembershipRow(prepared, id, member.RowID, state, selectedIDs, selectedCounts, &selectedOrder)

		weight, diag, err := resolveMembershipWeight(prepared, member.RowID)
		if err != nil {
			return err
		}
		if diag != nil {
			qualityDiagnostics = append(qualityDiagnostics, *diag)
		}
		// Named PlotCount counts SiteUnit; unassigned DCount counts PlotNumber.
		if member.SiteUnit.Text != nil || member.PlotNumber.Text != nil {
			state.unit.NumPlots += weight
		}
		if err := a.recordPlotMembershipWeight(ctx, prepared, member, id, weight, selectedCounts); err != nil {
			return err
		}
	}
	for _, id := range selectedOrder {
		if err := ctx.Err(); err != nil {
			return err
		}
		if selectedCounts[id] > 1 {
			qualityDiagnostics = append(qualityDiagnostics, vegetationLayerDiagnostic{"selected_unit_join_multiplicity", id, selectedCounts[id]})
		}
	}
	for _, diagnostic := range qualityDiagnostics {
		a.diagnose(diagnostic.Code, diagnostic.Identity, diagnostic.Count)
	}
	return nil
}

func validateMembershipIdentityCells(member reportcore.VegetationReportMembership) error {
	for _, cell := range []vprocore.ProjectMetadataCell{member.PlotNumber, member.SiteUnit} {
		if _, err := vprocore.VegetationReportIdentity(cell); err != nil {
			return err
		}
	}
	return nil
}

func (a *layerPlannerAccumulator) ensureUnitState(id string, code vprocore.ProjectMetadataCell, withProjectIndexes bool) *layerUnitState {
	if a.units[id] == nil {
		unit := vegetationLayerUnit{
			Code:          vprocore.CloneSiteUnitCell(code),
			MembershipIDs: []string{},
			Rows:          []vegetationLayerRow{},
		}
		if withProjectIndexes {
			unit.ProjectUnitIndexes = []int{}
		}
		a.units[id] = &layerUnitState{unit: unit, inputs: []layerJoinedObs{}}
	}
	return a.units[id]
}

func recordSelectedMembershipRow(
	prepared VegetationReportPreparation,
	unitID, rowID string,
	state *layerUnitState,
	selectedIDs map[string]map[string]bool,
	selectedCounts map[string]int,
	selectedOrder *[]string,
) {
	if prepared.selectedUnitOccurrences == nil {
		state.unit.MembershipIDs = append(state.unit.MembershipIDs, rowID)
		return
	}
	if selectedCounts[rowID] == 0 {
		*selectedOrder = append(*selectedOrder, rowID)
	}
	selectedCounts[rowID]++
	if selectedIDs[unitID] == nil {
		selectedIDs[unitID] = map[string]bool{}
	}
	if !selectedIDs[unitID][rowID] {
		state.unit.MembershipIDs = append(state.unit.MembershipIDs, rowID)
		selectedIDs[unitID][rowID] = true
	}
}

func resolveMembershipWeight(prepared VegetationReportPreparation, rowID string) (int, *vegetationLayerDiagnostic, error) {
	if prepared.noneUnitMembershipCounts != nil {
		if prepared.qualityMembershipCounts != nil {
			return 0, nil, errors.New("None report unit preparation must not apply quality weights twice")
		}
		weight := prepared.noneUnitMembershipCounts[rowID]
		if weight <= 0 {
			return 0, nil, errors.New("None report unit preparation lost its derived Env/current-list join count")
		}
		if weight > 1 {
			return weight, &vegetationLayerDiagnostic{"none_unit_join_multiplicity", rowID, weight}, nil
		}
		return weight, nil, nil
	}
	if prepared.qualityMembershipCounts != nil {
		weight := prepared.qualityMembershipCounts[rowID]
		if weight <= 0 {
			return 0, nil, errors.New("quality-qualified preparation lost a physical membership weight")
		}
		if weight > 1 {
			return weight, &vegetationLayerDiagnostic{"quality_reference_multiplicity", rowID, weight}, nil
		}
		return weight, nil, nil
	}
	return 1, nil, nil
}

func (a *layerPlannerAccumulator) recordPlotMembershipWeight(
	ctx context.Context,
	prepared VegetationReportPreparation,
	member reportcore.VegetationReportMembership,
	unitID string,
	weight int,
	selectedCounts map[string]int,
) error {
	if member.PlotNumber.Text == nil {
		return nil
	}
	plot := *member.PlotNumber.Text
	if prepared.selectedUnitOccurrences == nil || selectedCounts[member.RowID] == 1 {
		a.physicalCounts[plot]++
	}
	for i := 0; i < weight; i++ {
		if err := ctx.Err(); err != nil {
			return err
		}
		a.memberships[plot] = append(a.memberships[plot], unitID)
	}
	return nil
}

func (a *layerPlannerAccumulator) collectProjectUnitMemberships(
	ctx context.Context,
	inputs []vegetationProjectUnitInput,
	report *vegetationLayerReport,
) error {
	validated, err := validateProjectUnitInputs(ctx, inputs)
	if err != nil {
		return err
	}
	report.ProjectUnits = validated
	for i, row := range report.ProjectUnits {
		if err := ctx.Err(); err != nil {
			return err
		}
		id := reportcore.VegetationTextKey(row.SiteUnit)
		state := a.ensureUnitState(id, row.SiteUnit, true)
		state.unit.ProjectUnitIndexes = append(state.unit.ProjectUnitIndexes, i)
		if row.SiteUnit.Text != nil || row.PlotNumber.Text != nil {
			state.unit.NumPlots++
		}
		if row.PlotNumber.Text != nil {
			a.physicalCounts[*row.PlotNumber.Text]++
			a.memberships[*row.PlotNumber.Text] = append(a.memberships[*row.PlotNumber.Text], id)
		}
	}
	return nil
}

func (a *layerPlannerAccumulator) joinObservations(
	ctx context.Context,
	observations []VegetationReportObservation,
	refs layerPlannerRefs,
	options longVegetationOptions,
) error {
	if len(options.lumpMap) > 0 {
		lumped, err := applyLumpToObservations(ctx, observations, options.lumpMap)
		if err != nil {
			return err
		}
		observations = lumped
	}
	for _, observation := range observations {
		if err := ctx.Err(); err != nil {
			return err
		}
		if err := validateLayerObservation(observation); err != nil {
			return err
		}
		speciesRefs := a.lookupSpeciesRefs(observation.Species, refs.speciesIndex)
		layerRefs := a.lookupLayerRefs(observation.Layer, refs.layerIndex)
		if err := a.appendProjectedObservation(ctx, observation, speciesRefs, layerRefs, refs, options); err != nil {
			return err
		}
	}
	return nil
}

func validateLayerObservation(observation VegetationReportObservation) error {
	if _, err := vprocore.VegetationReportIdentity(observation.Species); err != nil {
		return err
	}
	number, err := vprocore.VegetationReportNumber(observation.Cover)
	if err != nil {
		return err
	}
	if number == nil {
		return errors.New("layer preparation observations must contain non-NULL cover")
	}
	return nil
}

func (a *layerPlannerAccumulator) lookupSpeciesRefs(
	species vprocore.ProjectMetadataCell,
	speciesIndex map[string][]vprocore.ProjectMetadataRow,
) []vprocore.ProjectMetadataRow {
	var refs []vprocore.ProjectMetadataRow
	if species.Text != nil {
		refs = speciesIndex[*species.Text]
	}
	if len(refs) == 0 {
		a.diagnose("missing_master_species", reportcore.VegetationTextKey(species), 1)
		return []vprocore.ProjectMetadataRow{{}}
	}
	if len(refs) > 1 {
		a.diagnose("master_species_multiplicity", *species.Text, len(refs))
	}
	return refs
}

func (a *layerPlannerAccumulator) lookupLayerRefs(
	layer string,
	layerIndex map[string][]vprocore.ProjectMetadataRow,
) []vprocore.ProjectMetadataRow {
	layerRefs := layerIndex[layer]
	if len(layerRefs) == 0 {
		a.diagnose("missing_layer_label", layer, 1)
		return []vprocore.ProjectMetadataRow{{}}
	}
	if len(layerRefs) > 1 {
		a.diagnose("layer_label_multiplicity", layer, len(layerRefs))
	}
	return layerRefs
}

func (a *layerPlannerAccumulator) appendProjectedObservation(
	ctx context.Context,
	observation VegetationReportObservation,
	speciesRefs, layerRefs []vprocore.ProjectMetadataRow,
	refs layerPlannerRefs,
	options longVegetationOptions,
) error {
	plotUnits := a.memberships[observation.PlotNumber]
	for _, ref := range speciesRefs {
		name, english, skip := projectSpeciesReference(observation.Species, ref, refs.speciesCols, options.ShowEnglishName)
		if skip {
			continue
		}
		if options.selectedFieldGrouping != nil && len(plotUnits) != 0 {
			if err := options.selectedFieldGrouping.observeProjected(ctx, name, english); err != nil {
				return err
			}
		}
		for _, layerRef := range layerRefs {
			layer := vprocore.ProjectMetadataCell{Storage: "null"}
			if len(layerRef.Cells) > 0 {
				layer = layerRef.Cells[refs.layerCols["Layer"]]
			}
			value := layerJoinedObs{
				key:   vegetationCrosstabKey{vprocore.CloneSiteUnitCell(layer), vprocore.CloneSiteUnitCell(name)},
				name:  vprocore.CloneSiteUnitCell(english),
				plot:  observation.PlotNumber,
				cover: observation.Cover,
			}
			key := layerDisplayKey{reportcore.VegetationTextKey(layer), reportcore.VegetationTextKey(name), reportcore.VegetationTextKey(english)}
			for _, id := range plotUnits {
				a.units[id].inputs = append(a.units[id].inputs, value)
				a.constants[key] = value
			}
		}
	}
	return nil
}

func projectSpeciesReference(
	fallback vprocore.ProjectMetadataCell,
	ref vprocore.ProjectMetadataRow,
	sc map[string]int,
	showEnglish bool,
) (name, english vprocore.ProjectMetadataCell, skip bool) {
	name = fallback
	english = vprocore.ProjectMetadataCell{Storage: "null"}
	if len(ref.Cells) == 0 {
		return name, english, false
	}
	codeType := ref.Cells[sc["Codetype"]]
	if codeType.Text != nil && (*codeType.Text == "S" || *codeType.Text == "s") {
		return name, english, true
	}
	if scientific := ref.Cells[sc["ScientificName"]]; scientific.Text != nil {
		name = scientific
	}
	if showEnglish {
		english = ref.Cells[sc["EnglishName"]]
	}
	return name, english, false
}

func (a *layerPlannerAccumulator) populateReportUnits(
	ctx context.Context,
	prepared VegetationReportPreparation,
	options longVegetationOptions,
	report *vegetationLayerReport,
) error {
	for _, id := range vprocore.SortedEnvironmentReportKeys(a.units) {
		if err := ctx.Err(); err != nil {
			return err
		}
		state := a.units[id]
		// Orphan-only named units are absent from SnRecords' inner Veg join.
		if state.unit.NumPlots == 0 || state.unit.Code.Text != nil && !a.active[id] {
			count := len(state.unit.MembershipIDs)
			if prepared.projectUnitInputs != nil {
				count = len(state.unit.ProjectUnitIndexes)
			}
			a.diagnose("excluded_unit_without_vegetation", id, count)
			continue
		}
		calculated, pivotNames, err := calculateUnitLayerCrosstabs(ctx, state, options.Average)
		if err != nil {
			return err
		}
		state.unit.Rows = a.selectUnitRows(calculated, pivotNames, options)
		sortLayerUnitRows(state.unit.Rows, options)
		sort.Strings(state.unit.MembershipIDs)
		report.Units = append(report.Units, state.unit)
	}
	return nil
}

func calculateUnitLayerCrosstabs(
	ctx context.Context,
	state *layerUnitState,
	averageMode string,
) ([]vegetationLayerRow, []string, error) {
	buckets := map[string][]vegetationCrosstabInput{}
	names := map[string]vprocore.ProjectMetadataCell{}
	pivots := map[string]bool{}
	for _, input := range state.inputs {
		key := reportcore.VegetationTextKey(input.name)
		buckets[key] = append(buckets[key], vegetationCrosstabInput{input.key, input.plot, input.cover})
		names[key] = input.name
		pivots[input.plot] = true
	}
	pivotNames := vprocore.SortedEnvironmentReportKeys(pivots)
	var calculated []vegetationLayerRow
	for _, key := range vprocore.SortedEnvironmentReportKeys(buckets) {
		rows, err := calculateVegetationCrosstab(ctx, buckets[key], state.unit.NumPlots,
			vegetationCrosstabOptions{Average: averageMode, Unfiltered: true}, nil)
		if err != nil {
			return nil, nil, err
		}
		for _, row := range rows {
			plots := populateBlankPivotPlots(pivotNames, row.Plots)
			calculated = append(calculated, vegetationLayerRow{
				row.Key.Group,
				row.Key.Species,
				vprocore.CloneSiteUnitCell(names[key]),
				vprocore.CloneSiteUnitCell(names[key]),
				row.Presence,
				row.MeanCover,
				plots,
			})
		}
	}
	return calculated, pivotNames, nil
}

func populateBlankPivotPlots(pivotNames []string, rowPlots []vegetationCrosstabPlot) []vegetationCrosstabPlot {
	plots := makeBlankLayerPlots(pivotNames)
	for i := range plots {
		for _, cell := range rowPlots {
			if plots[i].PlotNumber == cell.PlotNumber {
				plots[i].Cover = cell.Cover
			}
		}
	}
	return plots
}

func makeBlankLayerPlots(names []string) []vegetationCrosstabPlot {
	result := make([]vegetationCrosstabPlot, 0, len(names))
	for _, name := range names {
		result = append(result, vegetationCrosstabPlot{PlotNumber: name})
	}
	return result
}

func (a *layerPlannerAccumulator) selectUnitRows(
	calculated []vegetationLayerRow,
	pivotNames []string,
	options longVegetationOptions,
) []vegetationLayerRow {
	rows := []vegetationLayerRow{}
	if !options.ConstantSpeciesList {
		for _, row := range calculated {
			if row.MeanCover != nil && row.Presence != nil && *row.MeanCover > options.MeanCoverGreaterThan &&
				*row.Presence > options.PresenceGreaterThan/100 {
				rows = append(rows, row)
			}
		}
		return rows
	}
	for key, constant := range a.constants {
		matched := 0
		for _, row := range calculated {
			// EnglishName participates in grouping but NOT the final join.
			if constant.key.Group.Text != nil && constant.key.Species.Text != nil &&
				key.layer == reportcore.VegetationTextKey(row.Layer) && key.species == reportcore.VegetationTextKey(row.Species) {
				row.EnglishName = vprocore.CloneSiteUnitCell(constant.name)
				rows = append(rows, cloneVegetationLayerRow(row))
				matched++
			}
		}
		if matched == 0 {
			rows = append(rows, vegetationLayerRow{
				Layer:       vprocore.CloneSiteUnitCell(constant.key.Group),
				Species:     vprocore.CloneSiteUnitCell(constant.key.Species),
				EnglishName: vprocore.CloneSiteUnitCell(constant.name),
				MatchedName: vprocore.ProjectMetadataCell{Storage: "null"},
				Plots:       makeBlankLayerPlots(pivotNames),
			})
		} else if matched > 1 {
			a.diagnose("constant_list_name_fanout", key.layer+"/"+key.species, matched)
		}
	}
	return rows
}

func cloneVegetationLayerRow(row vegetationLayerRow) vegetationLayerRow {
	row.Layer, row.Species = vprocore.CloneSiteUnitCell(row.Layer), vprocore.CloneSiteUnitCell(row.Species)
	row.EnglishName, row.MatchedName = vprocore.CloneSiteUnitCell(row.EnglishName), vprocore.CloneSiteUnitCell(row.MatchedName)
	if row.Presence != nil {
		value := *row.Presence
		row.Presence = &value
	}
	if row.MeanCover != nil {
		value := *row.MeanCover
		row.MeanCover = &value
	}
	row.Plots = append([]vegetationCrosstabPlot{}, row.Plots...)
	for i := range row.Plots {
		if row.Plots[i].Cover != nil {
			value := *row.Plots[i].Cover
			row.Plots[i].Cover = &value
		}
	}
	return row
}

func sortLayerUnitRows(rows []vegetationLayerRow, options longVegetationOptions) {
	sort.Slice(rows, func(i, j int) bool {
		return compareLayerUnitRows(rows[i], rows[j], options)
	})
}

func compareLayerUnitRows(a, b vegetationLayerRow, options longVegetationOptions) bool {
	if (!options.NoneGrouping || options.ConstantSpeciesList) && reportcore.VegetationTextKey(a.Layer) != reportcore.VegetationTextKey(b.Layer) {
		return reportcore.VegetationTextKey(a.Layer) < reportcore.VegetationTextKey(b.Layer)
	}
	if !options.ConstantSpeciesList && options.Order == "presence" && *a.Presence != *b.Presence {
		return *a.Presence > *b.Presence
	}
	for _, pair := range [][2]vprocore.ProjectMetadataCell{{a.Species, b.Species}, {a.EnglishName, b.EnglishName}, {a.MatchedName, b.MatchedName}} {
		if reportcore.VegetationTextKey(pair[0]) != reportcore.VegetationTextKey(pair[1]) {
			return reportcore.VegetationTextKey(pair[0]) < reportcore.VegetationTextKey(pair[1])
		}
	}
	if options.NoneGrouping {
		return reportcore.VegetationTextKey(a.Layer) < reportcore.VegetationTextKey(b.Layer)
	}
	return false
}
