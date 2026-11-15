package lmh25rules

import (
	"fmt"
	"github.com/boostao/vpro/app/internal/vprocore"
	"strconv"
	"strings"
)

func inferSMRAndSNR(
	res *PlotDiagnosticsResult,
	header vprocore.FS882Header,
	soilGroup string,
	hasPeatyHorizons bool,
	peatTotalThickness, peatUpper40Total, peatOfUpper40, peatOmUpper40 float64,
	uplandTotalThickness, uplandHThickness float64,
	ahDepth, aeDepth float64,
	bDark, bLight, hasGleying bool,
	minGleyDepth, lithicDepth, maxMineralLower, weightedCF, cfWeight float64,
	dominantTexture string,
	hasTurbation, hasSalineHorizon bool,
) {
	slope := 0.0
	if header.Slope != nil {
		slope = *header.Slope
	}
	aspect := -1
	if header.Aspect != nil {
		aspect = *header.Aspect
	}
	meso := trimUpper(header.MesoSlopePos)
	drainage := strings.ToLower(strings.TrimSpace(derefStr(header.SoilDrainage)))
	waterSrc := trimUpper(header.WaterSource)
	rzps := trimUpper(header.RootZoneParticleSize)
	rrType := trimUpper(header.RootRestrictingType)
	humusForm := trimUpper(header.HumusForm)
	floodFreq := trimUpper(header.FloodingRegimeFreq)
	surfMat := trimUpper(header.SurficialMaterialSurf)

	// Insolation vs Cold slope (Key 9.3 & Key 9.4 note c)
	insolation := slope > 35.0 && aspect >= 157 && aspect <= 285
	coldSlope := slope > 35.0 && aspect >= 0 && aspect != 999 && (aspect >= 337 || aspect <= 105)

	// Soil depth (cm) to restricting layer
	soilDepth := 120.0
	hasExplicitSoilDepth := false
	if header.RootRestrictingDepth != nil && rrType != "N" {
		soilDepth = float64(*header.RootRestrictingDepth)
		hasExplicitSoilDepth = true
	}
	if lithicDepth >= 0 && (!hasExplicitSoilDepth || lithicDepth < soilDepth) {
		soilDepth = lithicDepth
		hasExplicitSoilDepth = true
	}
	if !hasExplicitSoilDepth && maxMineralLower > 0 && maxMineralLower < 40 && rrType == "L" {
		soilDepth = maxMineralLower
		hasExplicitSoilDepth = true
	}

	avgCF := 20.0
	if cfWeight > 0 {
		avgCF = weightedCF / cfWeight
	}

	// Particle size Coarse vs Fine (Key 9.3 definitions)
	isSandy := dominantTexture == "S" || dominantTexture == "LS" || rzps == "S" || rzps == "SS"
	isLoamy := dominantTexture == "SL" || dominantTexture == "L" || dominantTexture == "SCL" || rzps == "CL" || rzps == "L" || rzps == "FL"
	isSilty := dominantTexture == "SIL" || dominantTexture == "SI" || rzps == "CSI" || rzps == "FSI"
	isClayey := dominantTexture == "SICL" || dominantTexture == "CL" || dominantTexture == "SC" || dominantTexture == "SIC" || dominantTexture == "C" || rzps == "C" || rzps == "FC"

	isFragmental := rzps == "F" || avgCF > 85.0
	isCoarse := isFragmental || rzps == "S" || rzps == "SS" || rzps == "CI" || rzps == "CLS" || rzps == "AS" ||
		(isSandy && (cfWeight == 0 || avgCF > 35.0)) ||
		(isLoamy && avgCF > 70.0) || avgCF > 70.0
	isFine := !isCoarse && (rzps == "C" || rzps == "FC" || rzps == "CSI" || rzps == "FSI" ||
		((isSilty || isClayey) && (cfWeight == 0 || avgCF <= 20.0)))

	// Wet Soil Indicators (WSI - Key 9.3)
	wsi := false
	wsiDepth := 999.0
	if header.SeepageDepth != nil && *header.SeepageDepth >= 0 {
		wsi = true
		if float64(*header.SeepageDepth) < wsiDepth {
			wsiDepth = float64(*header.SeepageDepth)
		}
	}
	if hasGleying {
		wsi = true
		if minGleyDepth >= 0 && minGleyDepth < wsiDepth {
			wsiDepth = minGleyDepth
		}
	}
	if hasPeatyHorizons || (res.IsOrganicSoilOrder && soilGroup != "FO") {
		wsi = true
		if peatTotalThickness >= 20 && wsiDepth > 15 {
			wsiDepth = 10
		}
	}
	switch drainage {
	case "v", "aq", "pa":
		wsi = true
		wsiDepth = 0
	case "p", "ac":
		wsi = true
		if wsiDepth > 25 {
			wsiDepth = 20
		}
	case "i", "sa":
		wsi = true
		if wsiDepth > 45 {
			wsiDepth = 45
		}
	}
	if waterSrc == "G" || waterSrc == "S" || waterSrc == "M" || waterSrc == "T" || waterSrc == "E" {
		wsi = true
		if wsiDepth > 50 {
			wsiDepth = 45
		}
	}
	waterTableAtSurface := drainage == "v" || drainage == "aq" || drainage == "pa" ||
		(header.SeepageDepth != nil && *header.SeepageDepth == 0) ||
		(header.SubstrateWater != nil && *header.SubstrateWater >= 25.0)

	activeFluvial := waterSrc == "F" || floodFreq == "A" || floodFreq == "F" || strings.HasPrefix(surfMat, "FA")
	bedrockPct := 0.0
	if header.SubstrateBedRock != nil {
		bedrockPct = *header.SubstrateBedRock
	}

	// Slope group
	slopeGroup := "MID"
	switch meso {
	case "CR", "UP":
		slopeGroup = "UPPER"
	case "MD":
		slopeGroup = "MID"
	case "LW", "TO", "GU":
		slopeGroup = "LOWER"
	case "LV", "DP":
		slopeGroup = "FLAT"
	default:
		if header.Slope != nil && slope < 5.0 {
			slopeGroup = "FLAT"
		}
	}

	res.SMRTrace = append(res.SMRTrace, KeyTraceStep{
		Key:       "9.3",
		Step:      "Site & Soil Indicators",
		Condition: fmt.Sprintf("MesoSlope=%s (%s), Slope=%.1f%%, Aspect=%d, SoilDepth=%.0fcm, Coarse=%t, Fine=%t, WSI=%t (depth=%.0fcm)", meso, slopeGroup, slope, aspect, soilDepth, isCoarse, isFine, wsi, wsiDepth),
		Outcome:   slopeGroup,
	})

	// Key 9.4 Decision Tree
	var smrClass int
	var smrLabel string

	switch slopeGroup {
	case "UPPER":
		if wsi {
			if wsiDepth < 30 {
				smrClass, smrLabel = 6, "6"
				res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Ridge/Upper + WSI", "WSI < 30 cm from surface", "6"})
			} else {
				smrClass, smrLabel = 5, "(4)-5"
				res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Ridge/Upper + WSI", "WSI >= 30 cm from surface", "(4)-5"})
			}
		} else if hasExplicitSoilDepth && soilDepth < 40 {
			if bedrockPct > 10 || soilDepth < 20 {
				smrClass, smrLabel = 0, "0(-1)"
				res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Ridge/Upper shallow (<40 cm)", "Bedrock > 10% or soil depth < 20 cm", "0(-1)"})
			} else {
				smrClass, smrLabel = 1, "1"
				res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Ridge/Upper shallow (<40 cm)", "Soil depth 20-40 cm, bedrock <= 10%", "1"})
			}
		} else if isCoarse {
			if insolation {
				smrClass, smrLabel = 1, "1(-2)"
				res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Ridge/Upper deep coarse", "Insolation slope (>35%, SSE-W)", "1(-2)"})
			} else {
				smrClass, smrLabel = 2, "(1-)2"
				res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Ridge/Upper deep coarse", "Non-insolation slope", "(1-)2"})
				if coldSlope {
					smrClass, smrLabel = 3, "2-3 (cold aspect)"
				}
			}
		} else {
			if insolation {
				smrClass, smrLabel = 2, "2(-3)"
				res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Ridge/Upper deep medium/fine", "Insolation slope (>35%, SSE-W)", "2(-3)"})
			} else {
				smrClass, smrLabel = 3, "(2-)3"
				res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Ridge/Upper deep medium/fine", "Non-insolation slope", "(2-)3"})
				if coldSlope {
					smrClass, smrLabel = 4, "3-4 (cold aspect)"
				}
			}
		}

	case "MID":
		if wsi {
			if wsiDepth < 30 {
				smrClass, smrLabel = 6, "6"
				res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Mid slope + WSI", "WSI < 30 cm from surface", "6"})
			} else {
				smrClass, smrLabel = 5, "(4-)5"
				res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Mid slope + WSI", "WSI >= 30 cm from surface", "(4-)5"})
			}
		} else {
			shallow := hasExplicitSoilDepth && soilDepth < 50
			if isCoarse {
				if shallow || insolation {
					if shallow && insolation {
						smrClass, smrLabel = 1, "1-(2)"
						res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Mid slope coarse", "Both soil depth < 50 cm and insolation", "1-(2)"})
					} else {
						smrClass, smrLabel = 2, "2"
						res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Mid slope coarse", "Either soil depth < 50 cm or insolation", "2"})
					}
				} else {
					smrClass, smrLabel = 3, "3"
					res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Mid slope coarse", "Soil depth >= 50 cm and non-insolation", "3"})
				}
			} else {
				if shallow || insolation {
					if shallow && insolation {
						smrClass, smrLabel = 2, "2"
						res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Mid slope medium/fine", "Both soil depth < 50 cm and insolation", "2"})
					} else {
						smrClass, smrLabel = 3, "3"
						res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Mid slope medium/fine", "Either soil depth < 50 cm or insolation", "3"})
						if coldSlope {
							smrClass, smrLabel = 4, "3-4 (cold aspect)"
						}
					}
				} else {
					smrClass, smrLabel = 4, "4"
					res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Mid slope medium/fine", "Deep (>= 50 cm) non-insolation mesic reference", "4"})
				}
			}
		}

	case "LOWER":
		if wsi {
			if wsiDepth < 30 {
				if waterTableAtSurface {
					smrClass, smrLabel = 8, "8"
					res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Lower/Toe/Gully + WSI", "Water table at or above surface", "8"})
				} else {
					smrClass, smrLabel = 7, "7"
					res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Lower/Toe/Gully + WSI", "WSI < 30 cm from surface", "7"})
				}
			} else {
				smrClass, smrLabel = 6, "6"
				res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Lower/Toe/Gully + WSI", "WSI >= 30 cm from surface", "6"})
			}
		} else {
			if isCoarse {
				smrClass, smrLabel = 4, "4(-5)"
				res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Lower/Toe/Gully without WSI", "Coarse particle size", "4(-5)"})
			} else {
				smrClass, smrLabel = 5, "5(-6)"
				res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Lower/Toe/Gully without WSI", "Medium/fine particle size", "5(-6)"})
			}
		}

	case "FLAT":
		if (wsi && wsiDepth < 60) || activeFluvial {
			if wsi && wsiDepth < 30 {
				if waterTableAtSurface {
					smrClass, smrLabel = 8, "8"
					res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Flat/Depression wet", "WSI < 30 cm and water table at/above surface", "8"})
				} else {
					smrClass, smrLabel = 7, "7"
					res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Flat/Depression wet", "WSI < 30 cm, water table below surface", "7"})
				}
			} else if isFine {
				smrClass, smrLabel = 6, "6"
				res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Flat/Depression moist", "WSI 30-60 cm or fluvial + fine particle size", "6"})
			} else {
				smrClass, smrLabel = 5, "5"
				res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Flat/Depression moist", "WSI 30-60 cm or fluvial + non-fine particle size", "5"})
			}
		} else if isCoarse {
			smrClass, smrLabel = 2, "2-3"
			res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Flat/Depression dry", "No WSI < 60 cm + coarse particle size", "2-3"})
		} else if isFine {
			smrClass, smrLabel = 5, "5"
			res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Flat/Depression dry", "No WSI < 60 cm + fine particle size", "5"})
		} else {
			smrClass, smrLabel = 4, "4"
			res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Flat/Depression dry", "No WSI < 60 cm + medium particle size", "4"})
		}
	}

	res.KeyedSMR = smrLabel
	res.KeyedSMRClass = &smrClass
	if fieldClass, ok := parseFieldSMRClass(res.FieldSMR); ok {
		res.FieldSMRClass = fieldClass
		diff := *fieldClass - smrClass
		if diff < 0 {
			diff = -diff
		}
		res.SMRDivergence = &diff
		if diff >= 2 {
			res.SMRDivergent = true
			res.Issues = append(res.Issues, DiagnosticIssue{
				Code:      "SMR_KEY_DIVERGENCE",
				Severity:  SeverityWarning,
				Category:  "edatopic_smr",
				Field:     "MoistureRegime",
				Message:   fmt.Sprintf("Field MoistureRegime (%s) diverges by %d classes from LMH25 Key 9.4 inference (%s).", res.FieldSMR, diff, smrLabel),
				Suggested: strconv.Itoa(smrClass),
				LMH25Ref:  "LMH25 (2023) Key 9.4 p. 226",
			})
		}
	}

	// Key 9.6 & 9.7 Decision Tree for rSNR (A..F -> 0..5)
	restrictedFlow := slope < 5.0 && (drainage == "p" || drainage == "v" || drainage == "aq" || drainage == "pa" || isFine)
	humusClass := classifyHumusFormFamily(humusForm)
	isSaline := waterSrc == "E" || rrType == "X" || hasSalineHorizon

	var snrClass int
	var snrLabel string

	if isSaline {
		snrClass, snrLabel = 5, "F"
		res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Excess Saline / Tidal / Chemical", "Saline water source, chemical restriction, or pH > 8.2", "F"})
	} else if wsi || activeFluvial {
		if peatTotalThickness > 20 || (res.IsOrganicSoilOrder && soilGroup != "FO") {
			ofDom := (peatUpper40Total > 0 && peatOfUpper40/peatUpper40Total >= 0.5) || soilGroup == "F"
			ofOmDom := (peatUpper40Total > 0 && (peatOfUpper40+peatOmUpper40)/peatUpper40Total >= 0.5) || soilGroup == "M"
			if ofDom {
				snrClass, snrLabel = 0, "A-B"
				res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Wet/Peaty > 20 cm", "Of (fibric) dominant in upper 40 cm", "A-B"})
			} else if ofOmDom {
				snrClass, snrLabel = 1, "B-C"
				res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Wet/Peaty > 20 cm", "Of+Om dominant in upper 40 cm", "B-C"})
			} else if restrictedFlow {
				snrClass, snrLabel = 2, "C-D"
				res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Wet/Peaty > 20 cm", "Oh dominant + restricted water flow", "C-D"})
			} else {
				snrClass, snrLabel = 3, "D-E"
				res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Wet/Peaty > 20 cm", "Oh dominant + moving water", "D-E"})
			}
		} else if wsi && wsiDepth < 30 {
			if restrictedFlow {
				if ahDepth > 5 || humusClass == "MULL" {
					snrClass, snrLabel = 2, "C"
					res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "WSI < 30 cm + restricted flow", "Ah > 5 cm or Mull humus", "C"})
				} else {
					snrClass, snrLabel = 1, "B"
					res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "WSI < 30 cm + restricted flow", "Ah <= 5 cm", "B"})
				}
			} else {
				if ahDepth > 5 || activeFluvial || humusClass == "MULL" {
					snrClass, snrLabel = 3, "D"
					res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "WSI < 30 cm + moving water", "Ah > 5 cm, Mull, or active fluvial", "D"})
				} else {
					snrClass, snrLabel = 2, "C"
					res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "WSI < 30 cm + moving water", "Ah <= 5 cm, non-fluvial", "C"})
				}
			}
		} else {
			if restrictedFlow {
				if ahDepth > 5 || humusClass == "MULL" {
					snrClass, snrLabel = 3, "D"
					res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "WSI >= 30 cm + restricted flow", "Ah > 5 cm or Mull humus", "D"})
				} else {
					snrClass, snrLabel = 2, "C"
					res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "WSI >= 30 cm + restricted flow", "Ah <= 5 cm", "C"})
				}
			} else {
				if ahDepth > 5 || activeFluvial || humusClass == "MULL" {
					snrClass, snrLabel = 4, "E"
					res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "WSI >= 30 cm / Active Fluvial", "Ah > 5 cm, Mull, or active fluvial seepage", "E"})
				} else {
					snrClass, snrLabel = 3, "D"
					res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "WSI >= 30 cm + moving water", "Ah <= 5 cm", "D"})
				}
			}
		}
	} else if (hasExplicitSoilDepth && soilDepth < 30) || isFragmental || soilGroup == "FO" {
		if soilGroup == "FO" {
			if (uplandTotalThickness + soilDepth) < 30 {
				snrClass, snrLabel = 0, "A"
				res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Folisol", "LFH + Mineral < 30 cm", "A"})
			} else if uplandTotalThickness > 0 && uplandHThickness/uplandTotalThickness >= 0.5 {
				snrClass, snrLabel = 2, "C"
				res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Folisol", "H horizons dominant", "C"})
			} else {
				snrClass, snrLabel = 1, "B"
				res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Folisol", "L/F horizons dominant", "B"})
			}
		} else if ahDepth > 5 || bDark || humusClass == "MULL" {
			snrClass, snrLabel = 2, "C"
			res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Mineral < 30 cm or Fragmental", "Ah > 5 cm, dark B (value <= 3), or Mull", "C"})
		} else if bLight || aeDepth > 2 || (hasExplicitSoilDepth && soilDepth < 10) || (humusClass == "MOR" && isCoarse) {
			snrClass, snrLabel = 0, "A"
			res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Mineral < 30 cm or Fragmental", "Light soil (value >= 7), Ae > 2 cm, depth < 10 cm, or coarse Mor", "A"})
		} else {
			snrClass, snrLabel = 1, "B"
			res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Mineral < 30 cm or Fragmental", "Moderate mineral colour, no thick Ae", "B"})
		}
	} else if isCoarse || (hasExplicitSoilDepth && soilDepth < 50) {
		if ahDepth > 2 || bDark || humusClass == "MULL" {
			if hasTurbation || humusClass == "MULL" {
				snrClass, snrLabel = 3, "D"
				res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Coarse or depth < 50 cm", "Ah > 2 cm / dark B + Mull or soil turbation", "D"})
			} else {
				snrClass, snrLabel = 2, "C"
				res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Coarse or depth < 50 cm", "Ah > 2 cm or dark B without turbation", "C"})
			}
		} else if bLight || aeDepth > 2 {
			snrClass, snrLabel = 0, "A"
			res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Coarse or depth < 50 cm", "Light B (value >= 7) or Ae > 2 cm", "A"})
		} else if humusClass == "MODER" {
			snrClass, snrLabel = 2, "C"
			res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.7", "Coarse or depth < 50 cm + Moder", "Moder humus form on >= 30 cm soil", "C"})
		} else {
			snrClass, snrLabel = 1, "B"
			res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Coarse or depth < 50 cm", "Mor/unspecified humus without dark B or thick Ae", "B"})
		}
	} else {
		// Deep medium/fine upland soil
		if ahDepth > 2 || bDark || humusClass == "MULL" {
			if isFine && ahDepth > 5 {
				snrClass, snrLabel = 4, "E"
				res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Deep medium/fine upland", "Fine textured + Ah > 5 cm", "E"})
			} else {
				snrClass, snrLabel = 3, "D"
				res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Deep medium/fine upland", "Ah > 2 cm, dark B (value <= 3), or Mull humus", "D"})
			}
		} else if bLight || aeDepth > 2 || (humusClass == "MOR" && coldSlope && uplandTotalThickness > 10) {
			snrClass, snrLabel = 1, "B"
			res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Deep medium/fine upland", "Light B (value >= 7), Ae > 2 cm, or thick Mor on cool aspect", "B"})
		} else if humusClass == "MODER" && slopeGroup == "LOWER" {
			snrClass, snrLabel = 3, "D"
			res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.7", "Deep medium/fine + Moder on lower/toe", "Moder humus on receiving slope", "D"})
		} else {
			snrClass, snrLabel = 2, "C"
			res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Deep medium/fine upland", "Mesotrophic reference soil", "C"})
		}
	}

	// Permafrost adjustment (* footnote in Key 9.6: lower SNR by 1 class when permafrost present)
	if (waterSrc == "Z" || rrType == "Z" || (header.ActiveLayerDepth != nil && *header.ActiveLayerDepth > 0)) && snrClass > 0 && snrClass < 5 {
		snrClass--
		snrLabel = snrClassLetter(snrClass)
		res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6*", "Permafrost adjustment", "Permafrost / active layer present -> lower SNR by 1 class", snrLabel})
	}

	res.KeyedSNR = snrLabel
	res.KeyedSNRClass = &snrClass
	if fieldClass, ok := parseFieldSNRClass(res.FieldSNR); ok {
		res.FieldSNRClass = fieldClass
		diff := *fieldClass - snrClass
		if diff < 0 {
			diff = -diff
		}
		res.SNRDivergence = &diff
		if diff >= 2 {
			res.SNRDivergent = true
			res.Issues = append(res.Issues, DiagnosticIssue{
				Code:      "SNR_KEY_DIVERGENCE",
				Severity:  SeverityWarning,
				Category:  "edatopic_snr",
				Field:     "NutrientRegime",
				Message:   fmt.Sprintf("Field NutrientRegime (%s) diverges by %d classes from LMH25 Key 9.6 inference (%s).", res.FieldSNR, diff, snrLabel),
				Suggested: snrClassLetter(snrClass),
				LMH25Ref:  "LMH25 (2023) Key 9.6 p. 228",
			})
		}
	}
}

func classifyHumusFormFamily(code string) string {
	switch strings.ToUpper(strings.TrimSpace(code)) {
	case "L", "VL", "YL":
		return "MULL"
	case "D", "LD", "MD", "RD", "SD", "TD", "YD":
		return "MODER"
	case "R", "FR", "HR", "LR", "MR", "RR", "UR", "YR":
		return "MOR"
	default:
		return ""
	}
}
