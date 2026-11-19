package diagnostics

import (
	"context"
	"database/sql"
	"errors"
	"math"
	"slices"
	"strings"

	"github.com/boostao/vpro/app/internal/vprocore"
)

const foldedLumpCoverCap = 99.0

type plotSpeciesAcc struct {
	cover  float64
	lumped bool
}

type vegFoldResult struct {
	plotSpeciesTotals   []map[string]*plotSpeciesAcc
	allSpeciesSet       map[string]bool
	lumpSourcesByTarget map[string]map[string]bool
	foldedSourceTaxa    map[string]bool
	lumpCappedCells     int
}

func loadAndFoldProjectVeg(
	ctx context.Context,
	tx *sql.Tx,
	project string,
	coverPrec string,
	lumpMap map[string]string,
	classifiedPlots []classifiedPlotRecord,
	classifiedIndexByPlot map[string]int,
) (vegFoldResult, error) {
	// 6. Read <Project>_Veg for classified plots, applying float32 narrowing and optional *_Lump 99% cap
	type plotLayerKey struct {
		plotIdx int
		layerID int
		species string
	}
	type layerAccumulator struct {
		cover  float64
		lumped bool
		count  int
	}
	layerCells := map[plotLayerKey]*layerAccumulator{}
	lumpSourcesByTarget := map[string]map[string]bool{}
	foldedSourceTaxa := map[string]bool{}

	if len(classifiedPlots) > 0 {
		narrowNullable := func(nf sql.NullFloat64) (float64, bool) {
			if !nf.Valid {
				return 0, false
			}
			s := float32(nf.Float64)
			if math.IsNaN(float64(s)) || math.IsInf(float64(s), 0) || s < 0 {
				return 0, false
			}
			return float64(s), true
		}

		addLayerCover := func(pIdx, layerID int, effSpecies string, val float64, mapped bool) {
			key := plotLayerKey{plotIdx: pIdx, layerID: layerID, species: effSpecies}
			acc := layerCells[key]
			if acc == nil {
				acc = &layerAccumulator{}
				layerCells[key] = acc
			}
			acc.cover += val
			acc.count++
			if mapped {
				acc.lumped = true
			}
		}

		consumeVegQuery := func(vegWhere string, vegArgs []any, batchSet map[string]struct{}) error {
			vegRows, err := tx.QueryContext(ctx,
				`SELECT CAST(v."PlotNumber" AS TEXT),
				        COALESCE(CAST(v."Species" AS TEXT), ''),
				        v."Cover1", v."Cover2", v."Cover3", v."TotalA",
				        v."Cover4", v."Cover5", v."Cover5a", v."Cover5b", v."Cover5c", v."TotalB",
				        v."Cover6", v."Cover7", v."Cover8", v."Cover9", v."Cover10"
				 FROM "project".`+vprocore.QuoteHeaderIdentifier(project+"_Veg")+` AS v
				 `+vegWhere, vegArgs...)
			if err != nil {
				return err
			}
			for vegRows.Next() {
				var plotNum, rawSpp string
				var c1, c2, c3, totA, c4, c5, c5a, c5b, c5c, totB, c6, c7, c8, c9, c10 sql.NullFloat64
				if err := vegRows.Scan(
					&plotNum, &rawSpp,
					&c1, &c2, &c3, &totA,
					&c4, &c5, &c5a, &c5b, &c5c, &totB,
					&c6, &c7, &c8, &c9, &c10,
				); err != nil {
					vegRows.Close()
					return err
				}
				if batchSet != nil {
					if _, inBatch := batchSet[plotNum]; !inBatch {
						continue
					}
				}
				pIdx, ok := classifiedIndexByPlot[plotNum]
				if !ok {
					continue
				}
				rawCode := strings.ToUpper(strings.TrimSpace(rawSpp))
				if rawCode == "" {
					continue
				}
				effCode := rawCode
				wasMapped := false
				if lumpMap != nil {
					if mapped, found := lumpMap[rawCode]; found && mapped != "" {
						effCode = mapped
						wasMapped = true
						foldedSourceTaxa[rawCode] = true
						if lumpSourcesByTarget[effCode] == nil {
							lumpSourcesByTarget[effCode] = map[string]bool{}
						}
						lumpSourcesByTarget[effCode][rawCode] = true
					}
				}

				if coverPrec == "strata_totals" {
					// Stratum A (BuildStrataTable): TotalA when populated (>0 emits uncapped; 0 suppresses A),
					// otherwise sum Cover1..Cover3 with nulls as zero and cap fallback sum at 99.
					if v, valid := narrowNullable(totA); valid {
						if v > 0 {
							addLayerCover(pIdx, 101, effCode, v, wasMapped)
						}
					} else {
						var sumA float64
						for _, nf := range []sql.NullFloat64{c1, c2, c3} {
							if v, valid := narrowNullable(nf); valid {
								sumA += v
							}
						}
						if sumA > 0 {
							if sumA > 99 {
								sumA = 99
							}
							addLayerCover(pIdx, 101, effCode, sumA, wasMapped)
						}
					}

					// Stratum B (BuildStrataTable): TotalB when populated (>0 emits uncapped; 0 suppresses B),
					// otherwise sum Cover4..Cover5c with nulls as zero and cap fallback sum at 99.
					if v, valid := narrowNullable(totB); valid {
						if v > 0 {
							addLayerCover(pIdx, 102, effCode, v, wasMapped)
						}
					} else {
						var sumB float64
						for _, nf := range []sql.NullFloat64{c4, c5, c5a, c5b, c5c} {
							if v, valid := narrowNullable(nf); valid {
								sumB += v
							}
						}
						if sumB > 0 {
							if sumB > 99 {
								sumB = 99
							}
							addLayerCover(pIdx, 102, effCode, sumB, wasMapped)
						}
					}
				} else {
					// Stratum A (sublayer_sum / Access MakeDiagnosticData): use Cover1..Cover3 when any sublayer is populated, else TotalA
					hasSubA := false
					for idx, nf := range []sql.NullFloat64{c1, c2, c3} {
						if v, valid := narrowNullable(nf); valid {
							hasSubA = true
							addLayerCover(pIdx, 1+idx, effCode, v, wasMapped)
						}
					}
					if !hasSubA {
						if v, valid := narrowNullable(totA); valid {
							addLayerCover(pIdx, 101, effCode, v, wasMapped)
						}
					}

					// Stratum B (sublayer_sum / Access MakeDiagnosticData): use Cover4..Cover5c when any sublayer is populated, else TotalB
					hasSubB := false
					for idx, nf := range []sql.NullFloat64{c4, c5, c5a, c5b, c5c} {
						if v, valid := narrowNullable(nf); valid {
							hasSubB = true
							addLayerCover(pIdx, 4+idx, effCode, v, wasMapped)
						}
					}
					if !hasSubB {
						if v, valid := narrowNullable(totB); valid {
							addLayerCover(pIdx, 102, effCode, v, wasMapped)
						}
					}
				}

				// Strata C & D (Cover6..Cover10)
				for idx, nf := range []sql.NullFloat64{c6, c7, c8, c9, c10} {
					if v, valid := narrowNullable(nf); valid {
						addLayerCover(pIdx, 20+idx, effCode, v, wasMapped)
					}
				}
			}
			return errors.Join(vegRows.Err(), vegRows.Close())
		}

		if len(classifiedPlots) <= 10000 {
			const vegBatch = 800
			for start := 0; start < len(classifiedPlots); start += vegBatch {
				end := min(start+vegBatch, len(classifiedPlots))
				chunk := classifiedPlots[start:end]
				placeholders := make([]string, len(chunk))
				vegArgs := make([]any, len(chunk))
				batchSet := make(map[string]struct{}, len(chunk))
				for i := range chunk {
					placeholders[i] = "?"
					vegArgs[i] = chunk[i].plotNumber
					batchSet[chunk[i].plotNumber] = struct{}{}
				}
				vegWhere := `WHERE v."PlotNumber" COLLATE BINARY IN (` + strings.Join(placeholders, ",") + `) AND typeof(v."PlotNumber")='text' AND v."Species" IS NOT NULL`
				if err := consumeVegQuery(vegWhere, vegArgs, batchSet); err != nil {
					return vegFoldResult{}, err
				}
			}
		} else {
			if err := consumeVegQuery(`WHERE typeof(v."PlotNumber")='text' AND v."Species" IS NOT NULL`, nil, nil); err != nil {
				return vegFoldResult{}, err
			}
		}
	}

	// Fold layers into per-(plot, species) cover with 99% cap on lumped observations
	lumpCappedCells := 0
	plotSpeciesTotals := make([]map[string]*plotSpeciesAcc, len(classifiedPlots))
	allSpeciesSet := map[string]bool{}

	for key, acc := range layerCells {
		cov := acc.cover
		isLumpedCell := lumpMap != nil && (acc.lumped || acc.count > 1)
		isFoldedCell := isLumpedCell || acc.count > 1
		if isFoldedCell && cov > foldedLumpCoverCap {
			cov = foldedLumpCoverCap
			if isLumpedCell {
				lumpCappedCells++
			}
		}
		m := plotSpeciesTotals[key.plotIdx]
		if m == nil {
			m = map[string]*plotSpeciesAcc{}
			plotSpeciesTotals[key.plotIdx] = m
		}
		ps := m[key.species]
		if ps == nil {
			ps = &plotSpeciesAcc{}
			m[key.species] = ps
		}
		ps.cover += cov
		if isLumpedCell {
			ps.lumped = true
		}
		allSpeciesSet[key.species] = true
	}

	return vegFoldResult{
		plotSpeciesTotals:   plotSpeciesTotals,
		allSpeciesSet:       allSpeciesSet,
		lumpSourcesByTarget: lumpSourcesByTarget,
		foldedSourceTaxa:    foldedSourceTaxa,
		lumpCappedCells:     lumpCappedCells,
	}, nil
}

type unitCoverAccumulation struct {
	unitPlotCounts    map[string]int
	unitPlotsMap      map[string][]SynthesisUnitPlot
	unitCoverSums     map[string]map[string]float64
	unitPresentCounts map[string]map[string]int
	unitTotalSums     map[string]float64
}

func accumulateUnitPlotsAndCovers(
	orderedUnits []string,
	classifiedPlots []classifiedPlotRecord,
	plotSpeciesTotals []map[string]*plotSpeciesAcc,
) unitCoverAccumulation {
	unitPlotCounts := make(map[string]int, len(orderedUnits))
	unitPlotsMap := make(map[string][]SynthesisUnitPlot, len(orderedUnits))
	unitCoverSums := make(map[string]map[string]float64, len(orderedUnits))
	unitPresentCounts := make(map[string]map[string]int, len(orderedUnits))
	unitTotalSums := make(map[string]float64, len(orderedUnits))

	for _, u := range orderedUnits {
		unitCoverSums[u] = map[string]float64{}
		unitPresentCounts[u] = map[string]int{}
	}

	for i := range classifiedPlots {
		p := &classifiedPlots[i]
		u := p.siteUnit
		unitPlotCounts[u]++
		unitPlotsMap[u] = append(unitPlotsMap[u], SynthesisUnitPlot{
			PlotNumber:     p.plotNumber,
			FieldNumber:    p.fieldNumber,
			SiteUnit:       u,
			Zone:           p.zone,
			SubZone:        p.subZone,
			SiteSeries:     p.siteSeries,
			UserSiteUnit:   p.userSiteUnit,
			MoistureRegime: p.moistureRegime,
			NutrientRegime: p.nutrientRegime,
		})

		psMap := plotSpeciesTotals[i]
		for sp, ps := range psMap {
			cov := ps.cover
			if cov < 0 {
				continue
			}
			p.speciesCovers[sp] = cov
			p.totalCover += cov
			unitCoverSums[u][sp] += cov
			unitPresentCounts[u][sp]++
			unitTotalSums[u] += cov
		}
	}

	return unitCoverAccumulation{
		unitPlotCounts:    unitPlotCounts,
		unitPlotsMap:      unitPlotsMap,
		unitCoverSums:     unitCoverSums,
		unitPresentCounts: unitPresentCounts,
		unitTotalSums:     unitTotalSums,
	}
}

type synthesisMatrixBuildResult struct {
	speciesMeta      map[string]SpeciesTaxonMeta
	unitSpeciesStats map[string]map[string]unitSpeciesStat
	unitsOut         []SynthesisUnitSummary
	speciesRows      []SynthesisSpeciesRow
}

func buildSynthesisSpeciesAndUnits(
	ctx context.Context,
	tx *sql.Tx,
	owner *vprocore.SqliteContext,
	opts SynthesisOptions,
	sigBasis string,
	orderedUnits []string,
	unitLongNames map[string]string,
	acc unitCoverAccumulation,
	allSpeciesSet map[string]bool,
	lumpSourcesByTarget map[string]map[string]bool,
) (synthesisMatrixBuildResult, error) {
	// 7. Batch-load taxonomy metadata for all observed species
	allSpeciesCodes := make([]string, 0, len(allSpeciesSet))
	for sp := range allSpeciesSet {
		allSpeciesCodes = append(allSpeciesCodes, sp)
	}
	slices.Sort(allSpeciesCodes)
	speciesMeta, err := loadSpeciesTaxonomyBatchForOwner(ctx, tx, owner, allSpeciesCodes)
	if err != nil {
		return synthesisMatrixBuildResult{}, err
	}

	// 8. Build per-unit & per-species constancy, mean cover, Domin-Krajina significance, and V7mdlDiagnostic codes
	unitSpeciesStats := make(map[string]map[string]unitSpeciesStat, len(orderedUnits))
	for _, u := range orderedUnits {
		unitSpeciesStats[u] = map[string]unitSpeciesStat{}
	}

	unitSummaryByCode := make(map[string]*SynthesisUnitSummary, len(orderedUnits))
	for _, u := range orderedUnits {
		plotsSlice := acc.unitPlotsMap[u]
		if plotsSlice == nil {
			plotsSlice = []SynthesisUnitPlot{}
		}
		unitSummaryByCode[u] = &SynthesisUnitSummary{
			SiteUnit:  u,
			LongName:  unitLongNames[u],
			PlotCount: acc.unitPlotCounts[u],
			Plots:     plotsSlice,
		}
	}

	speciesRows := make([]SynthesisSpeciesRow, 0, len(allSpeciesCodes))
	for _, sp := range allSpeciesCodes {
		meta := speciesMeta[sp]
		cells := make([]SynthesisUnitSpeciesCell, len(orderedUnits))
		orderedCodes := make([]OrderedUnitCode, len(orderedUnits))
		maxPresPct := 0.0
		maxMeanCov := 0.0

		for uIdx, u := range orderedUnits {
			nPlots := acc.unitPlotCounts[u]
			nPres := acc.unitPresentCounts[u][sp]
			totCov := acc.unitCoverSums[u][sp]

			cell := SynthesisUnitSpeciesCell{
				SiteUnit:             u,
				PresentPlots:         nPres,
				PlotCount:            nPlots,
				PresencePctText:      "",
				MeanCoverAllText:     "",
				MeanCoverPresentText: "",
				CellDiagnosticCodes:  []string{},
			}

			if nPlots > 0 && nPres > 0 {
				presRatio := float64(nPres) / float64(nPlots)
				presPct := presRatio * 100.0
				presClass, presRoman := DiagnosticPresenceClass(presRatio)

				meanAll := totCov / float64(nPlots)
				meanPres := totCov / float64(nPres)

				sigInput := meanAll
				if sigBasis == "present_plots" {
					sigInput = meanPres
				}
				sigClass, sigNum := DominKrajinaSignifClass(sigInput)
				ctCode := FormatUnitCrosstabCode(presClass, sigClass)

				diagPot := CalcDiagnosticPotential(presPct, meanAll, opts.Pairwise).DiagnosticPotential

				cell.PresencePct = RoundACE15(presPct, 1)
				cell.PresencePctText = FormatACE15(presPct, 0)
				cell.PresenceClass = presClass
				cell.PresenceRoman = presRoman
				cell.MeanCoverAll = RoundACE15(meanAll, 2)
				cell.MeanCoverAllText = FormatACE15(meanAll, 1)
				cell.MeanCoverPresent = RoundACE15(meanPres, 2)
				cell.MeanCoverPresentText = FormatACE15(meanPres, 1)
				cell.SignifClass = sigClass
				cell.SignifNumeric = sigNum
				cell.CrosstabCode = ctCode
				cell.DiagnosticPotential = RoundACE15(diagPot, 2)

				codeCopy := ctCode
				orderedCodes[uIdx] = OrderedUnitCode{Unit: u, Code: &codeCopy}

				unitSpeciesStats[u][sp] = unitSpeciesStat{
					presentPlots: nPres,
					totalCover:   totCov,
					meanCoverAll: meanAll,
					meanCoverPr:  meanPres,
					constancyPct: presPct,
					diagPot:      diagPot,
				}
				unitSummaryByCode[u].SpeciesRichness++
				unitSummaryByCode[u].DiagPotentialSum += diagPot
				if presClass == 5 {
					unitSummaryByCode[u].ConstantCount++
				}
				if presPct > maxPresPct {
					maxPresPct = presPct
				}
				if meanAll > maxMeanCov {
					maxMeanCov = meanAll
				}
			} else {
				orderedCodes[uIdx] = OrderedUnitCode{Unit: u, Code: nil}
			}
			cells[uIdx] = cell
		}

		if opts.MinMaxPresencePct > 0 && maxPresPct < opts.MinMaxPresencePct {
			continue
		}

		var diagRes DiagnosticClassification
		if len(orderedCodes) > 0 {
			var cErr error
			diagRes, cErr = ClassifySpeciesDiagnostic(orderedCodes)
			if cErr != nil {
				return synthesisMatrixBuildResult{}, cErr
			}
		}

		for uIdx := range cells {
			c := &cells[uIdx]
			if c.PresentPlots == 0 {
				continue
			}
			if diagRes.Unit != "" && c.SiteUnit == diagRes.Unit {
				c.IsPrimaryDiagnosticUnit = true
				c.CellDiagnosticCodes = append(c.CellDiagnosticCodes, diagRes.Codes...)
				unitSummaryByCode[c.SiteUnit].DiagnosticCount++
			} else if c.PresenceClass == 5 {
				// Secondary unit constancy indicator for multi-unit constant/dominant taxa
				if c.SignifNumeric >= 5 {
					c.CellDiagnosticCodes = append(c.CellDiagnosticCodes, "cd")
				} else {
					c.CellDiagnosticCodes = append(c.CellDiagnosticCodes, "c")
				}
			}
		}

		var srcSpp []string
		if set := lumpSourcesByTarget[sp]; len(set) > 0 {
			srcSpp = make([]string, 0, len(set))
			for k := range set {
				srcSpp = append(srcSpp, k)
			}
			slices.Sort(srcSpp)
		}

		diagCodes := diagRes.Codes
		if diagCodes == nil {
			diagCodes = []string{}
		}

		speciesRows = append(speciesRows, SynthesisSpeciesRow{
			Species:         sp,
			ScientificName:  meta.ScientificName,
			EnglishName:     meta.EnglishName,
			Lifeform:        meta.Lifeform,
			LifeformName:    meta.LifeformName,
			StratumGroup:    meta.StratumGroup,
			SourceSpecies:   srcSpp,
			DiagnosticUnit:  diagRes.Unit,
			Diagnosis:       diagRes.Diagnosis,
			DiagnosticCodes: diagCodes,
			MaxPresencePct:  RoundACE15(maxPresPct, 1),
			MaxMeanCover:    RoundACE15(maxMeanCov, 2),
			Cells:           cells,
		})
	}

	// Order species: diagnostic units first (in orderedUnits order), then Non-Diagnostic, by stratum -> lifeform -> presence -> cover
	unitOrderIndex := make(map[string]int, len(orderedUnits))
	for i, u := range orderedUnits {
		unitOrderIndex[u] = i
	}
	slices.SortFunc(speciesRows, func(a, b SynthesisSpeciesRow) int {
		aDiag := a.DiagnosticUnit != ""
		bDiag := b.DiagnosticUnit != ""
		if aDiag != bDiag {
			if aDiag {
				return -1
			}
			return 1
		}
		if aDiag && bDiag && a.DiagnosticUnit != b.DiagnosticUnit {
			return unitOrderIndex[a.DiagnosticUnit] - unitOrderIndex[b.DiagnosticUnit]
		}
		if srA, srB := stratumSortRank(a.StratumGroup), stratumSortRank(b.StratumGroup); srA != srB {
			return srA - srB
		}
		lfA, lfB := 999, 999
		if a.Lifeform != nil {
			lfA = *a.Lifeform
		}
		if b.Lifeform != nil {
			lfB = *b.Lifeform
		}
		if lfA != lfB {
			return lfA - lfB
		}
		if a.MaxPresencePct != b.MaxPresencePct {
			if a.MaxPresencePct > b.MaxPresencePct {
				return -1
			}
			return 1
		}
		if a.MaxMeanCover != b.MaxMeanCover {
			if a.MaxMeanCover > b.MaxMeanCover {
				return -1
			}
			return 1
		}
		return strings.Compare(a.ScientificName, b.ScientificName)
	})

	unitsOut := make([]SynthesisUnitSummary, 0, len(orderedUnits))
	for _, u := range orderedUnits {
		sum := unitSummaryByCode[u]
		sum.DiagPotentialSum = RoundACE15(sum.DiagPotentialSum, 2)
		unitsOut = append(unitsOut, *sum)
	}

	return synthesisMatrixBuildResult{
		speciesMeta:      speciesMeta,
		unitSpeciesStats: unitSpeciesStats,
		unitsOut:         unitsOut,
		speciesRows:      speciesRows,
	}, nil
}
