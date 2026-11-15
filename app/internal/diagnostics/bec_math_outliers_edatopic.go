package diagnostics

import (
	"math"
	"slices"
	"strings"
)

const defaultOutlierThreshold = 0.45

func normalizeOutlierThreshold(threshold float64) float64 {
	if threshold <= 0 {
		return defaultOutlierThreshold
	}
	if threshold > 1 {
		return 1.0
	}
	return threshold
}

// ComputeOutlierQueue evaluates every classified plot against its Leave-One-Out (LOO) assigned SiteUnit
// centroid and its nearest rival SiteUnit centroid, sorting descending by RivalSimilarity - OwnSimilarity.
func ComputeOutlierQueue(
	units []string,
	plots []classifiedPlotRecord,
	unitCoverSums map[string]map[string]float64,
	unitTotalSums map[string]float64,
	unitPlotCounts map[string]int,
) []OutlierPlotCandidate {
	return ComputeOutlierQueueWithThreshold(units, plots, unitCoverSums, unitTotalSums, unitPlotCounts, defaultOutlierThreshold)
}

// ComputeOutlierQueueWithThreshold evaluates classified plots with an explicit own-similarity threshold (default 0.45 matching R vpro_outliers).
func ComputeOutlierQueueWithThreshold(
	units []string,
	plots []classifiedPlotRecord,
	unitCoverSums map[string]map[string]float64,
	unitTotalSums map[string]float64,
	unitPlotCounts map[string]int,
	threshold float64,
) []OutlierPlotCandidate {
	normThreshold := normalizeOutlierThreshold(threshold)
	if len(plots) == 0 {
		return []OutlierPlotCandidate{}
	}

	nUnits := len(units)
	unitIdxByName := make(map[string]int, nUnits)
	spSet := map[string]struct{}{}
	for i, u := range units {
		unitIdxByName[u] = i
		for sp := range unitCoverSums[u] {
			spSet[sp] = struct{}{}
		}
	}
	for i := range plots {
		for sp := range plots[i].speciesCovers {
			spSet[sp] = struct{}{}
		}
	}
	nSp := len(spSet)
	spIDByName := make(map[string]int32, nSp)
	nextSpID := int32(0)
	for sp := range spSet {
		spIDByName[sp] = nextSpID
		nextSpID++
	}

	unitSumsFlat := make([]float64, nUnits*nSp)
	unitCountsArr := make([]int, nUnits)
	unitTotalsArr := make([]float64, nUnits)
	unitInvCounts := make([]float64, nUnits)
	unitMeanTotals := make([]float64, nUnits)
	for uIdx, u := range units {
		cnt := unitPlotCounts[u]
		unitCountsArr[uIdx] = cnt
		tot := unitTotalSums[u]
		unitTotalsArr[uIdx] = tot
		if cnt > 0 {
			inv := 1.0 / float64(cnt)
			unitInvCounts[uIdx] = inv
			unitMeanTotals[uIdx] = tot * inv
		}
		base := uIdx * nSp
		for sp, s := range unitCoverSums[u] {
			unitSumsFlat[base+int(spIDByName[sp])] = s
		}
	}

	type spCovPair struct {
		spID int32
		cov  float64
	}
	var plotVec []spCovPair

	out := make([]OutlierPlotCandidate, 0, len(plots))
	for i := range plots {
		p := &plots[i]
		uAssigned := p.siteUnit
		uAssignedIdx, hasAssigned := unitIdxByName[uAssigned]
		nAssigned := 0
		if hasAssigned {
			nAssigned = unitCountsArr[uAssignedIdx]
		} else {
			nAssigned = unitPlotCounts[uAssigned]
		}
		singleton := nAssigned <= 1

		plotVec = plotVec[:0]
		for sp, cov := range p.speciesCovers {
			if cov > 0 {
				plotVec = append(plotVec, spCovPair{spID: spIDByName[sp], cov: cov})
			}
		}

		ownSim := 0.0
		if !singleton && hasAssigned {
			invLOO := 1.0 / float64(nAssigned-1)
			looTotal := (unitTotalsArr[uAssignedIdx] - p.totalCover) * invLOO
			if looTotal < 0 {
				looTotal = 0
			}
			denom := p.totalCover + looTotal
			if denom > 0 {
				uBase := uAssignedIdx * nSp
				sumMin := 0.0
				for _, pair := range plotVec {
					looMean := (unitSumsFlat[uBase+int(pair.spID)] - pair.cov) * invLOO
					if looMean > 0 {
						if pair.cov < looMean {
							sumMin += pair.cov
						} else {
							sumMin += looMean
						}
					}
				}
				ownSim = (2.0 * sumMin) / denom
			}
		}

		rivalUnit := ""
		rivalSim := 0.0
		for uIdx, candUnit := range units {
			if uIdx == uAssignedIdx && hasAssigned {
				continue
			}
			nCand := unitCountsArr[uIdx]
			if nCand <= 0 {
				continue
			}
			denom := p.totalCover + unitMeanTotals[uIdx]
			sim := 0.0
			if denom > 0 {
				invCand := unitInvCounts[uIdx]
				cBase := uIdx * nSp
				sumMin := 0.0
				for _, pair := range plotVec {
					candMean := unitSumsFlat[cBase+int(pair.spID)] * invCand
					if candMean > 0 {
						if pair.cov < candMean {
							sumMin += pair.cov
						} else {
							sumMin += candMean
						}
					}
				}
				sim = (2.0 * sumMin) / denom
			}
			if rivalUnit == "" || sim > rivalSim || (sim == rivalSim && candUnit < rivalUnit) {
				rivalUnit = candUnit
				rivalSim = sim
			}
		}

		delta := rivalSim - ownSim
		out = append(out, OutlierPlotCandidate{
			PlotNumber:         p.plotNumber,
			FieldNumber:        p.fieldNumber,
			AssignedUnit:       uAssigned,
			AssignedUnitPlots:  nAssigned,
			SingletonUnit:      singleton,
			OwnSimilarity:      RoundACE15(ownSim, 4),
			OwnSimilarityPct:   RoundACE15(ownSim*100.0, 1),
			NearestRivalUnit:   rivalUnit,
			RivalSimilarity:    RoundACE15(rivalSim, 4),
			RivalSimilarityPct: RoundACE15(rivalSim*100.0, 1),
			DeltaSimilarity:    RoundACE15(delta, 4),
			DeltaSimilarityPct: RoundACE15(delta*100.0, 1),
			Misplaced:          rivalUnit != "" && delta > 0,
			BelowThreshold:     !singleton && ownSim < normThreshold,
			MoistureRegime:     p.moistureRegime,
			NutrientRegime:     p.nutrientRegime,
			Zone:               p.zone,
			SubZone:            p.subZone,
			SiteSeries:         p.siteSeries,
		})
	}

	slices.SortFunc(out, func(a, b OutlierPlotCandidate) int {
		if a.DeltaSimilarity > b.DeltaSimilarity {
			return -1
		}
		if a.DeltaSimilarity < b.DeltaSimilarity {
			return 1
		}
		if a.OwnSimilarity < b.OwnSimilarity {
			return -1
		}
		if a.OwnSimilarity > b.OwnSimilarity {
			return 1
		}
		return strings.Compare(a.PlotNumber, b.PlotNumber)
	})

	top5Cutoff := max(1, int(math.Ceil(float64(len(out))*0.05)))
	for i := range out {
		out[i].Rank = i + 1
		out[i].Top5PercentAnomaly = (i + 1) <= top5Cutoff
	}
	return out
}

// ParseRelativeSMR extracts a canonical BEC rSMR class ("0".."8") from an Env MoistureRegime field.
func ParseRelativeSMR(raw string) (string, bool) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return "", false
	}
	ch := trimmed[0]
	if ch >= '0' && ch <= '8' {
		// Reject multi-digit integers like "10" while allowing modifiers like "4w" or "3-4"
		if len(trimmed) > 1 && trimmed[1] >= '0' && trimmed[1] <= '9' {
			return "", false
		}
		return string(ch), true
	}
	return "", false
}

// ParseRelativeSNR extracts a canonical BEC rSNR class ("A".."F") from an Env NutrientRegime field.
func ParseRelativeSNR(raw string) (string, bool) {
	trimmed := strings.ToUpper(strings.TrimSpace(raw))
	if trimmed == "" {
		return "", false
	}
	ch := trimmed[0]
	if ch >= 'A' && ch <= 'F' {
		if len(trimmed) > 1 && trimmed[1] >= 'A' && trimmed[1] <= 'Z' {
			return "", false
		}
		return string(ch), true
	}
	return "", false
}

func buildSingleEdatopicGrid(siteUnit, label string, plots []classifiedPlotRecord) EdatopicUnitGrid {
	type cellBucket struct {
		plots []string
	}
	grid := make([][]cellBucket, len(SMRRows))
	for r := range SMRRows {
		grid[r] = make([]cellBucket, len(SNRCols))
	}

	plotted := 0
	for _, p := range plots {
		smr, okM := ParseRelativeSMR(p.moistureRegime)
		snr, okN := ParseRelativeSNR(p.nutrientRegime)
		if !okM || !okN {
			continue
		}
		rIdx := int(smr[0] - '0')
		cIdx := int(snr[0] - 'A')
		grid[rIdx][cIdx].plots = append(grid[rIdx][cIdx].plots, p.plotNumber)
		plotted++
	}

	total := len(plots)
	cells := make([]EdatopicCell, 0, len(SMRRows)*len(SNRCols))
	maxCount := 0
	maxProm := 0.0

	for rIdx, smr := range SMRRows {
		for cIdx, snr := range SNRCols {
			pList := grid[rIdx][cIdx].plots
			if pList == nil {
				pList = []string{}
			} else {
				slices.Sort(pList)
			}
			cnt := len(pList)
			unitPct := 0.0
			if total > 0 {
				unitPct = RoundACE15((float64(cnt)/float64(total))*100.0, 1)
			}
			prom := 0.0
			if plotted > 0 {
				prom = RoundACE15((float64(cnt)/float64(plotted))*100.0, 1)
			}
			if cnt > maxCount {
				maxCount = cnt
			}
			if prom > maxProm {
				maxProm = prom
			}
			cells = append(cells, EdatopicCell{
				SMR:         smr,
				SNR:         snr,
				PlotCount:   cnt,
				UnitPct:     unitPct,
				Prominence:  prom,
				PlotNumbers: pList,
			})
		}
	}

	return EdatopicUnitGrid{
		SiteUnit:             siteUnit,
		Label:                label,
		TotalPlots:           total,
		PlottedEdatopicCount: plotted,
		MissingEdatopicCount: total - plotted,
		MaxCellCount:         maxCount,
		MaxProminence:        maxProm,
		Cells:                cells,
	}
}

// ComputeEdatopicGrids computes the Overall and per-SiteUnit 9 x 6 (rSMR 0..8 x rSNR A..F) heatmaps.
func ComputeEdatopicGrids(units []string, plots []classifiedPlotRecord) (EdatopicUnitGrid, []EdatopicUnitGrid) {
	overall := buildSingleEdatopicGrid("__OVERALL__", "All Classified Plots", plots)
	byUnit := make(map[string][]classifiedPlotRecord, len(units))
	for _, p := range plots {
		byUnit[p.siteUnit] = append(byUnit[p.siteUnit], p)
	}
	unitGrids := make([]EdatopicUnitGrid, 0, len(units))
	for _, u := range units {
		unitGrids = append(unitGrids, buildSingleEdatopicGrid(u, u, byUnit[u]))
	}
	return overall, unitGrids
}
