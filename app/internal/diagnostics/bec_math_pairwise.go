package diagnostics

import (
	"math"
	"slices"
	"strings"
)

func normalizePairwiseParams(in PairwiseParams) PairwiseParams {
	out := in
	if out.MinConstancy <= 0 {
		out.MinConstancy = 60.0
	}
	if out.NoiseConstancy <= 0 {
		out.NoiseConstancy = 10.0
	}
	if out.MinPlots <= 0 {
		out.MinPlots = 2
	}
	if out.MinDiff <= 0 {
		out.MinDiff = 0.5
	}
	if out.MinDD <= 0 {
		out.MinDD = 0.5
	}
	if out.MinorCover <= 0 {
		out.MinorCover = 1.0
	}
	if out.DominantCover <= 0 {
		out.DominantCover = 7.0
	}
	return out
}

// DiagnosticPotentialScores captures BEC _calc_diagnostic_potential.R components.
type DiagnosticPotentialScores struct {
	DPotential          float64
	DDPotential         float64
	DiagnosticPotential float64
}

// CalcDiagnosticPotential ports _calc_diagnostic_potential.R from MoF BEC_R_working.
func CalcDiagnosticPotential(constancy, meanCov float64, params PairwiseParams) DiagnosticPotentialScores {
	p := normalizePairwiseParams(params)
	const constExp = 0.5
	const coverExp = 0.333
	const maxPotential = 10.0

	dPot := 0.0
	if constancy >= p.MinConstancy && 100.0 > p.MinConstancy {
		dPot = 4.0 * math.Pow((constancy-p.MinConstancy)/(100.0-p.MinConstancy), constExp)
	}
	ddPot := 0.0
	if constancy >= p.MinConstancy && meanCov >= p.DominantCover && 100.0 > p.DominantCover {
		ddPot = 4.0 * math.Pow((meanCov-p.DominantCover)/(100.0-p.DominantCover), coverExp)
	}
	coverWeight := 1.0
	if meanCov < p.MinorCover {
		if meanCov <= 0 {
			coverWeight = 0
		} else {
			coverWeight = math.Sqrt(meanCov / p.MinorCover)
		}
	}
	dPotAdj := dPot * coverWeight
	bonus := 0.0
	if dPotAdj > 0 && meanCov >= p.DominantCover {
		ratio := dPotAdj / 4.0
		bonus = 2.0 * ratio * ratio
	}
	diagPot := math.Min(dPotAdj+ddPot+bonus, maxPotential)
	if diagPot <= p.MinDiff {
		diagPot = 0
	}
	return DiagnosticPotentialScores{
		DPotential:          dPot,
		DDPotential:         ddPot,
		DiagnosticPotential: diagPot,
	}
}

type unitSpeciesStat struct {
	presentPlots int
	totalCover   float64
	meanCoverAll float64
	meanCoverPr  float64
	constancyPct float64
	diagPot      float64
}

type classifiedPlotRecord struct {
	plotNumber     string
	fieldNumber    string
	siteUnit       string
	zone           string
	subZone        string
	siteSeries     string
	userSiteUnit   string
	moistureRegime string
	nutrientRegime string
	speciesCovers  map[string]float64
	totalCover     float64
}

// SorensenSimilarity computes the BEC Diagnostic10.xla / Sorensen / Bray-Curtis quantitative similarity
// 2 * sum(min(u1, u2)) / sum(u1 + u2) in [0, 1].
func SorensenSimilarity(u1, u2 map[string]float64) float64 {
	sumMin := 0.0
	sumTot := 0.0
	for sp, v1 := range u1 {
		if v1 > 0 {
			sumTot += v1
			if v2 := u2[sp]; v2 > 0 {
				if v1 < v2 {
					sumMin += v1
				} else {
					sumMin += v2
				}
			}
		}
	}
	for _, v2 := range u2 {
		if v2 > 0 {
			sumTot += v2
		}
	}
	if sumTot <= 0 {
		return 0
	}
	return (2.0 * sumMin) / sumTot
}

func computePairwiseDPoints(constSelf, constOther, meanSelf float64, p PairwiseParams) float64 {
	constDiff := constSelf - constOther
	if constDiff < 20.0 || constSelf < p.MinConstancy {
		return 0
	}
	constScore := math.Cbrt(constDiff) * (constDiff / 100.0)
	pts := 0.0
	if constSelf >= p.MinConstancy+10.0 {
		pts = constScore
	} else {
		weight := math.Max(0, math.Min(1.0, (constSelf-p.MinConstancy)/10.0))
		pts = constScore * weight
	}
	if meanSelf <= p.MinorCover {
		pts *= meanSelf / p.MinorCover
	}
	if constDiff < 40.0 {
		pts *= (constDiff - 20.0) / 20.0
	}
	if pts < p.MinDiff {
		return 0
	}
	return pts
}

func computePairwiseDDPoints(meanSelf, meanOther float64, p PairwiseParams) float64 {
	if meanSelf <= meanOther || meanSelf <= 5.0 {
		return 0
	}
	ddiff := math.Abs(math.Cbrt(meanSelf) - math.Cbrt(meanOther))
	pts := 0.0
	if meanSelf >= 10.0 {
		pts = ddiff
	} else {
		pts = ddiff * ((meanSelf - 5.0) / 5.0)
	}
	if pts <= p.MinDD {
		return 0
	}
	return pts
}

// ComputePairwiseAnalysis builds both the symmetric U x U Sorensen similarity matrix
// and the BEC _do_pairwise.R differential comparison list.
func ComputePairwiseAnalysis(
	units []string,
	plotCounts map[string]int,
	speciesMeta map[string]SpeciesTaxonMeta,
	unitSpecies map[string]map[string]unitSpeciesStat,
	rawParams PairwiseParams,
) ([]PairwiseMatrixRow, []PairwiseUnitComparison) {
	p := normalizePairwiseParams(rawParams)
	nUnits := len(units)

	// Assign dense species IDs 0..S-1 so pairwise U*(U-1)/2 comparisons run as zero-alloc sorted slice merges.
	spSet := map[string]struct{}{}
	for _, u := range units {
		for sp := range unitSpecies[u] {
			spSet[sp] = struct{}{}
		}
	}
	spNames := make([]string, 0, len(spSet))
	for sp := range spSet {
		spNames = append(spNames, sp)
	}
	slices.Sort(spNames)
	spIDByName := make(map[string]int32, len(spNames))
	spSciByID := make([]string, len(spNames))
	eligibleByID := make([]bool, len(spNames))
	for idx, sp := range spNames {
		spIDByName[sp] = int32(idx)
		spSciByID[idx] = speciesMeta[sp].ScientificName
	}

	for _, u := range units {
		if plotCounts[u] < p.MinPlots {
			continue
		}
		for sp, st := range unitSpecies[u] {
			if st.constancyPct >= p.MinConstancy {
				eligibleByID[spIDByName[sp]] = true
			}
		}
	}

	type indexedUnitSp struct {
		spID         int32
		meanCoverAll float64
		constancyPct float64
		diagPot      float64
	}
	unitVecs := make([][]indexedUnitSp, nUnits)
	unitSumMeans := make([]float64, nUnits)
	unitEligible := make([]bool, nUnits)
	for uIdx, u := range units {
		unitEligible[uIdx] = plotCounts[u] >= p.MinPlots
		m := unitSpecies[u]
		vec := make([]indexedUnitSp, 0, len(m))
		sumMean := 0.0
		for sp, st := range m {
			if st.meanCoverAll > 0 || st.constancyPct > 0 {
				vec = append(vec, indexedUnitSp{
					spID:         spIDByName[sp],
					meanCoverAll: st.meanCoverAll,
					constancyPct: st.constancyPct,
					diagPot:      st.diagPot,
				})
				if st.meanCoverAll > 0 {
					sumMean += st.meanCoverAll
				}
			}
		}
		slices.SortFunc(vec, func(a, b indexedUnitSp) int {
			return int(a.spID - b.spID)
		})
		unitVecs[uIdx] = vec
		unitSumMeans[uIdx] = sumMean
	}

	sorensenMat := make([][]float64, nUnits)
	becSimMat := make([][]float64, nUnits)
	for i := range nUnits {
		sorensenMat[i] = make([]float64, nUnits)
		becSimMat[i] = make([]float64, nUnits)
		sorensenMat[i][i] = 1.0
		becSimMat[i][i] = 1.0
	}

	comparisons := make([]PairwiseUnitComparison, 0, nUnits*(nUnits-1)/2)

	for i := 0; i < nUnits; i++ {
		u1 := units[i]
		v1 := unitVecs[i]
		elig1 := unitEligible[i]
		for j := i + 1; j < nUnits; j++ {
			u2 := units[j]
			v2 := unitVecs[j]
			elig2 := unitEligible[j]

			sumMin := 0.0
			sharedDiag := 0.0
			diffTot1 := 0.0
			diffTot2 := 0.0
			var diffTaxa []PairwiseDifferentialTaxon

			k1, k2 := 0, 0
			for k1 < len(v1) || k2 < len(v2) {
				var spID int32
				var s1, s2 indexedUnitSp
				var has1, has2 bool
				if k2 >= len(v2) || (k1 < len(v1) && v1[k1].spID < v2[k2].spID) {
					s1 = v1[k1]
					spID = s1.spID
					has1 = true
					k1++
				} else if k1 >= len(v1) || v2[k2].spID < v1[k1].spID {
					s2 = v2[k2]
					spID = s2.spID
					has2 = true
					k2++
				} else {
					s1 = v1[k1]
					s2 = v2[k2]
					spID = s1.spID
					has1, has2 = true, true
					k1++
					k2++
					if s1.meanCoverAll > 0 && s2.meanCoverAll > 0 {
						if s1.meanCoverAll < s2.meanCoverAll {
							sumMin += s1.meanCoverAll
						} else {
							sumMin += s2.meanCoverAll
						}
					}
				}

				if !eligibleByID[spID] {
					continue
				}
				var st1, st2 indexedUnitSp
				inUnion := false
				if has1 && elig1 && s1.constancyPct > p.NoiseConstancy {
					st1 = s1
					inUnion = true
				}
				if has2 && elig2 && s2.constancyPct > p.NoiseConstancy {
					st2 = s2
					inUnion = true
				}
				if !inUnion || (st1.diagPot <= 0 && st2.diagPot <= 0) {
					continue
				}
				sharedDiag += math.Min(st1.diagPot, st2.diagPot)

				d1 := computePairwiseDPoints(st1.constancyPct, st2.constancyPct, st1.meanCoverAll, p)
				dd1 := computePairwiseDDPoints(st1.meanCoverAll, st2.meanCoverAll, p)
				pts1 := d1 + dd1
				if d1 > p.MinDiff && dd1 > p.MinDiff {
					pts1 *= 1.25
				}
				pts1 = math.Min(pts1, 10.0)

				d2 := computePairwiseDPoints(st2.constancyPct, st1.constancyPct, st2.meanCoverAll, p)
				dd2 := computePairwiseDDPoints(st2.meanCoverAll, st1.meanCoverAll, p)
				pts2 := d2 + dd2
				if d2 > p.MinDiff && dd2 > p.MinDiff {
					pts2 *= 1.25
				}
				pts2 = math.Min(pts2, 10.0)

				diffTot1 += pts1
				diffTot2 += pts2

				if pts1 > 0 || pts2 > 0 {
					favours := u1
					if pts2 > pts1 {
						favours = u2
					}
					diffTaxa = append(diffTaxa, PairwiseDifferentialTaxon{
						Species:        spNames[spID],
						ScientificName: spSciByID[spID],
						ConstancyUnit1: RoundACE15(st1.constancyPct, 1),
						MeanCoverUnit1: RoundACE15(st1.meanCoverAll, 2),
						ConstancyUnit2: RoundACE15(st2.constancyPct, 1),
						MeanCoverUnit2: RoundACE15(st2.meanCoverAll, 2),
						DiffPtsUnit1:   RoundACE15(pts1, 2),
						DiffPtsUnit2:   RoundACE15(pts2, 2),
						FavoursUnit:    favours,
					})
				}
			}
			if diffTaxa == nil {
				diffTaxa = []PairwiseDifferentialTaxon{}
			}

			sor := 0.0
			if sumTot := unitSumMeans[i] + unitSumMeans[j]; sumTot > 0 {
				sor = (2.0 * sumMin) / sumTot
			}
			sorensenMat[i][j] = sor
			sorensenMat[j][i] = sor

			slices.SortFunc(diffTaxa, func(a, b PairwiseDifferentialTaxon) int {
				maxA := math.Max(a.DiffPtsUnit1, a.DiffPtsUnit2)
				maxB := math.Max(b.DiffPtsUnit1, b.DiffPtsUnit2)
				if maxA > maxB {
					return -1
				}
				if maxA < maxB {
					return 1
				}
				return strings.Compare(a.Species, b.Species)
			})

			diffTot := diffTot1 + diffTot2
			diffRatio := 0.0
			if denom := diffTot + 2.0*sharedDiag; denom > 0 {
				diffRatio = (2.0 * sharedDiag) / denom
			}
			ratio1 := 0.0
			if denom1 := diffTot1 + sharedDiag; denom1 > 0 {
				ratio1 = sharedDiag / denom1
			}
			ratio2 := 0.0
			if denom2 := diffTot2 + sharedDiag; denom2 > 0 {
				ratio2 = sharedDiag / denom2
			}
			becMean := (ratio1 + ratio2) / 2.0
			becMin := math.Min(ratio1, ratio2)
			becMax := math.Max(ratio1, ratio2)

			becSimMat[i][j] = becMean
			becSimMat[j][i] = becMean

			if !elig1 || !elig2 {
				continue
			}

			comparisons = append(comparisons, PairwiseUnitComparison{
				Unit1:               u1,
				Unit2:               u2,
				PlotsUnit1:          plotCounts[u1],
				PlotsUnit2:          plotCounts[u2],
				SorensenSimilarity:  RoundACE15(sor, 4),
				SorensenPct:         RoundACE15(sor*100.0, 1),
				SharedDiagPotential: RoundACE15(sharedDiag, 2),
				DiffTotalUnit1:      RoundACE15(diffTot1, 2),
				DiffTotalUnit2:      RoundACE15(diffTot2, 2),
				DiffRatio:           RoundACE15(diffRatio, 4),
				BECSimMin:           RoundACE15(becMin, 4),
				BECSimMean:          RoundACE15(becMean, 4),
				BECSimMax:           RoundACE15(becMax, 4),
				DifferentialTaxa:    diffTaxa,
			})
		}
	}

	matrixRows := make([]PairwiseMatrixRow, nUnits)
	for i, uRow := range units {
		cells := make([]PairwiseMatrixCell, nUnits)
		for j, uCol := range units {
			sor := sorensenMat[i][j]
			sorPct := sor * 100.0
			bec := becSimMat[i][j]
			cells[j] = PairwiseMatrixCell{
				Unit:              uCol,
				Similarity:        RoundACE15(sor, 4),
				SimilarityPct:     RoundACE15(sorPct, 1),
				SimilarityPctText: FormatACE15(sorPct, 1),
				BECSimMean:        RoundACE15(bec, 4),
				BECSimMeanPct:     RoundACE15(bec*100.0, 1),
			}
		}
		matrixRows[i] = PairwiseMatrixRow{
			Unit:  uRow,
			Cells: cells,
		}
	}

	return matrixRows, comparisons
}
