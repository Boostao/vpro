package vegreport

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"math/big"
	"sort"
	"strings"

	"github.com/boostao/vpro/app/internal/reports/reportcore"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type longVegetationLumpRow struct {
	LumpCode string `json:"lumpCode"`
	SppCode  string `json:"sppCode"`
	Use      int    `json:"use"`
}

type longVegetationLumpPlan struct {
	TableLabel string
	ActiveMap  map[string]string
	Rows       []longVegetationLumpRow
}

func resolveLongVegetationWorkbookScope(scope string) (string, error) {
	if scope == "unlumped" {
		return "", nil
	}
	candidate := scope
	if strings.HasPrefix(scope, "lump:") {
		candidate = strings.TrimSpace(strings.TrimPrefix(scope, "lump:"))
		if candidate == "" || strings.ContainsRune(candidate, 0) {
			return "", errors.New("Long Vegetation workbook lump scope requires a non-empty *_Lump table name")
		}
		if len(candidate) <= 5 || !strings.EqualFold(candidate[len(candidate)-5:], "_Lump") {
			candidate += "_Lump"
		}
	}
	if len(candidate) <= 5 || !strings.HasSuffix(candidate, "_Lump") ||
		strings.EqualFold(candidate, "None_Lump") || strings.EqualFold(candidate, "CombinedSpp_Lump") {
		return "", errors.New("Long Vegetation workbook requires explicit 'unlumped' or valid '<Name>_Lump' scope")
	}
	return candidate, nil
}

func decodeLongVegetationLumpOptions(values vprocore.ConfigValues, options *longVegetationOptions, scope string) error {
	if options == nil {
		return nil
	}
	if section, err := vprocore.ConfigSection(values, "ReportOptions"); err == nil {
		if _, hasCombine := section["LVUseSppCodesOnly"]; hasCombine {
			combine, cErr := longVegetationConfigBool(values, "LVUseSppCodesOnly")
			if cErr != nil {
				return cErr
			}
			options.CombineVariants = combine
		}
		if rawTable, hasTable := section["LVLumpTable"]; hasTable && rawTable != nil {
			table, tErr := vprocore.ConfigString(values, "ReportOptions", "LVLumpTable")
			if tErr != nil {
				return tErr
			}
			trimmed := strings.TrimSpace(table)
			if trimmed != "" && !strings.EqualFold(trimmed, "None") && !strings.EqualFold(trimmed, "None_Lump") {
				options.LumpTable = trimmed
			}
		}
	}
	if options.LumpTable == "" {
		if current, err := vprocore.ConfigSection(values, "Current"); err == nil {
			if raw, ok := current["CurrLump"]; ok {
				if text, ok := raw.(string); ok {
					trimmed := strings.TrimSpace(text)
					if trimmed != "" && !strings.EqualFold(trimmed, "None") && !strings.EqualFold(trimmed, "None_Lump") {
						options.LumpTable = trimmed
					}
				}
			}
		}
	}
	if scope != "" {
		resolved, err := resolveLongVegetationWorkbookScope(scope)
		if err != nil {
			return err
		}
		if resolved != "" {
			options.LumpTable = resolved
		}
	}
	return nil
}

func loadLongVegetationLumpPlan(ctx context.Context, tx *sql.Tx, species vprocore.ProjectMetadataTable,
	rawLumpTable string, combineVariants bool) (longVegetationLumpPlan, error) {
	fail := func(err error) (longVegetationLumpPlan, error) { return longVegetationLumpPlan{}, err }
	if err := ctx.Err(); err != nil {
		return fail(err)
	}
	var plan longVegetationLumpPlan
	activeMap := map[string]string{}
	explicitSpp := map[string]bool{}

	trimmed := strings.TrimSpace(rawLumpTable)
	actualTable := ""
	if trimmed != "" && !strings.EqualFold(trimmed, "None") && !strings.EqualFold(trimmed, "None_Lump") {
		if strings.EqualFold(trimmed, "CombinedSpp_Lump") {
			return fail(errors.New("CombinedSpp_Lump is computed via LVUseSppCodesOnly, not as a stored *_Lump table"))
		}
		target := trimmed
		if len(target) <= 5 || !strings.EqualFold(target[len(target)-5:], "_Lump") {
			target += "_Lump"
		}
		err := tx.QueryRowContext(ctx,
			`SELECT name FROM project.sqlite_master WHERE type='table' AND name COLLATE NOCASE=? LIMIT 1`,
			target).Scan(&actualTable)
		if errors.Is(err, sql.ErrNoRows) {
			return fail(fmt.Errorf("Long Vegetation lump table project.%s does not exist", target))
		}
		if err != nil {
			return fail(err)
		}
		table, err := vprocore.ReadSQLiteStorageRows(ctx, tx, "project", actualTable, "", nil, "")
		if err != nil {
			return fail(err)
		}
		cols, err := vprocore.SiteUnitTransferColumns(table, "LumpCode", "SppCode", "Use")
		if err != nil {
			return fail(fmt.Errorf("Long Vegetation lump table %s: %w", actualTable, err))
		}
		for _, row := range table.Rows {
			if err := ctx.Err(); err != nil {
				return fail(err)
			}
			lumpCell := row.Cells[cols["LumpCode"]]
			sppCell := row.Cells[cols["SppCode"]]
			useCell := row.Cells[cols["Use"]]
			useVal, err := vprocore.MetadataCellValue(useCell)
			if err != nil {
				return fail(err)
			}
			useActive := false
			useInt := 0
			switch v := useVal.(type) {
			case int64:
				useActive = v != 0
				if useActive {
					useInt = -1
				}
			case bool:
				useActive = v
				if useActive {
					useInt = -1
				}
			case string:
				clean := strings.TrimSpace(v)
				useActive = strings.EqualFold(clean, "true") || strings.EqualFold(clean, "yes") || clean == "-1" || clean == "1"
				if useActive {
					useInt = -1
				}
			}
			lumpStr, err := vprocore.VegetationReportIdentity(lumpCell)
			if err != nil {
				return fail(err)
			}
			sppStr, err := vprocore.VegetationReportIdentity(sppCell)
			if err != nil {
				return fail(err)
			}
			if lumpStr != nil && sppStr != nil {
				cleanLump := strings.TrimSpace(*lumpStr)
				cleanSpp := strings.TrimSpace(*sppStr)
				if cleanLump != "" && cleanSpp != "" {
					plan.Rows = append(plan.Rows, longVegetationLumpRow{LumpCode: cleanLump, SppCode: cleanSpp, Use: useInt})
					if useActive {
						key := strings.ToUpper(cleanSpp)
						activeMap[key] = cleanLump
						explicitSpp[key] = true
					}
				}
			}
		}
	}

	if combineVariants {
		sc, err := vprocore.SiteUnitTransferColumns(species, "Code")
		if err != nil {
			return fail(fmt.Errorf("Long Vegetation LVUseSppCodesOnly species schema: %w", err))
		}
		for _, row := range species.Rows {
			if err := ctx.Err(); err != nil {
				return fail(err)
			}
			codeCell, err := vprocore.VegetationReportIdentity(row.Cells[sc["Code"]])
			if err != nil || codeCell == nil {
				continue
			}
			code := strings.TrimSpace(*codeCell)
			if len(code) <= 1 {
				continue
			}
			last := code[len(code)-1]
			// V7mdlLumping.CombineSpp: Right([Code], 1) < '9' (ASCII digits 0..8 denote variants/subspecies).
			if last >= '0' && last < '9' {
				key := strings.ToUpper(code)
				if !explicitSpp[key] {
					activeMap[key] = code[:len(code)-1]
				}
			}
		}
	}

	if combineVariants {
		plan.TableLabel = "CombinedSpp_Lump"
	} else if actualTable != "" {
		plan.TableLabel = actualTable
	}
	if len(activeMap) > 0 {
		plan.ActiveMap = activeMap
	}
	return plan, nil
}

func applyLumpToObservations(ctx context.Context, obs []VegetationReportObservation, activeMap map[string]string) ([]VegetationReportObservation, error) {
	if len(activeMap) == 0 || len(obs) == 0 {
		return obs, nil
	}
	type lumpGroupKey struct {
		plot, layer, speciesKey string
	}
	type aggregate struct {
		sample  VegetationReportObservation
		sum     *big.Rat
		count   int
		first   vprocore.ProjectMetadataCell
		touched bool
	}
	groups := map[lumpGroupKey]*aggregate{}
	for _, item := range obs {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		speciesCell := vprocore.CloneSiteUnitCell(item.Species)
		mapped := false
		if speciesCell.Text != nil {
			key := strings.ToUpper(strings.TrimSpace(*speciesCell.Text))
			if replacement, ok := activeMap[key]; ok {
				copyVal := replacement
				speciesCell = vprocore.ProjectMetadataCell{Storage: "text", Text: &copyVal}
				mapped = true
			}
		}
		gk := lumpGroupKey{plot: item.PlotNumber, layer: item.Layer, speciesKey: reportcore.VegetationTextKey(speciesCell)}
		num, err := vprocore.VegetationReportNumber(item.Cover)
		if err != nil {
			return nil, err
		}
		if num == nil {
			continue
		}
		agg := groups[gk]
		if agg == nil {
			agg = &aggregate{
				sample: VegetationReportObservation{
					PlotNumber: item.PlotNumber,
					Species:    speciesCell,
					LayerRowID: item.LayerRowID,
					Layer:      item.Layer,
				},
				sum:     new(big.Rat),
				first:   vprocore.CloneSiteUnitCell(item.Cover),
				touched: mapped,
			}
			groups[gk] = agg
		} else {
			agg.touched = true
		}
		agg.sum.Add(agg.sum, num)
		agg.count++
	}
	keys := make([]lumpGroupKey, 0, len(groups))
	for k := range groups {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		a, b := keys[i], keys[j]
		if a.plot != b.plot {
			return a.plot < b.plot
		}
		if a.layer != b.layer {
			return a.layer < b.layer
		}
		return a.speciesKey < b.speciesKey
	})
	out := make([]VegetationReportObservation, 0, len(keys))
	for _, k := range keys {
		agg := groups[k]
		if agg.count == 1 && !agg.touched {
			agg.sample.Cover = agg.first
		} else {
			value, _ := agg.sum.Float64()
			if value > 99 {
				value = 99
			}
			agg.sample.Cover = vprocore.ProjectMetadataCell{Storage: "real", Real: &value}
		}
		out = append(out, agg.sample)
	}
	return out, nil
}

func applyLumpToLifeformObservations(ctx context.Context, obs []vegetationLifeformObservation, activeMap map[string]string) ([]vegetationLifeformObservation, error) {
	if len(activeMap) == 0 || len(obs) == 0 {
		return obs, nil
	}
	converted := make([]VegetationReportObservation, len(obs))
	layerCells := map[string]vprocore.ProjectMetadataCell{}
	for i, item := range obs {
		layerKey := reportcore.VegetationTextKey(item.Layer)
		layerCells[layerKey] = item.Layer
		converted[i] = VegetationReportObservation{
			PlotNumber: item.PlotNumber,
			Species:    item.Species,
			Layer:      layerKey,
			Cover:      item.Cover,
		}
	}
	lumped, err := applyLumpToObservations(ctx, converted, activeMap)
	if err != nil {
		return nil, err
	}
	out := make([]vegetationLifeformObservation, len(lumped))
	for i, item := range lumped {
		out[i] = vegetationLifeformObservation{
			PlotNumber: item.PlotNumber,
			Species:    item.Species,
			Layer:      vprocore.CloneSiteUnitCell(layerCells[item.Layer]),
			Cover:      item.Cover,
		}
	}
	return out, nil
}
