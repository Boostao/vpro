package lmh25rules

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/boostao/vpro/app/internal/vprocore"
)

type edatopicSiteIndicators struct {
	slope               float64
	aspect              int
	meso                string
	drainage            string
	waterSrc            string
	rzps                string
	rrType              string
	humusForm           string
	humusClass          string
	insolation          bool
	coldSlope           bool
	soilDepth           float64
	hasExplicitDepth    bool
	isFragmental        bool
	isCoarse            bool
	isFine              bool
	wsi                 bool
	wsiDepth            float64
	waterTableAtSurface bool
	activeFluvial       bool
	bedrockPct          float64
	slopeGroup          string
	restrictedFlow      bool
	isSaline            bool
}

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
	ind := computeEdatopicIndicators(
		res, header, soilGroup, hasPeatyHorizons, peatTotalThickness,
		hasGleying, minGleyDepth, lithicDepth, maxMineralLower,
		weightedCF, cfWeight, dominantTexture, hasSalineHorizon,
	)

	res.SMRTrace = append(res.SMRTrace, KeyTraceStep{
		Key:       "9.3",
		Step:      "Site & Soil Indicators",
		Condition: fmt.Sprintf("MesoSlope=%s (%s), Slope=%.1f%%, Aspect=%d, SoilDepth=%.0fcm, Coarse=%t, Fine=%t, WSI=%t (depth=%.0fcm)", ind.meso, ind.slopeGroup, ind.slope, ind.aspect, ind.soilDepth, ind.isCoarse, ind.isFine, ind.wsi, ind.wsiDepth),
		Outcome:   ind.slopeGroup,
	})

	smrClass, smrLabel := inferKey94SMR(res, ind)
	recordSMRDivergence(res, smrClass, smrLabel)

	snrClass, snrLabel := inferKey96SNR(
		res, header, ind, soilGroup,
		peatTotalThickness, peatUpper40Total, peatOfUpper40, peatOmUpper40,
		uplandTotalThickness, uplandHThickness,
		ahDepth, aeDepth, bDark, bLight, hasTurbation,
	)
	recordSNRDivergence(res, snrClass, snrLabel)
}

func computeEdatopicIndicators(
	res *PlotDiagnosticsResult,
	header vprocore.FS882Header,
	soilGroup string,
	hasPeatyHorizons bool,
	peatTotalThickness float64,
	hasGleying bool,
	minGleyDepth, lithicDepth, maxMineralLower, weightedCF, cfWeight float64,
	dominantTexture string,
	hasSalineHorizon bool,
) edatopicSiteIndicators {
	slope := derefFloatOrZero(header.Slope)
	aspect := derefIntOrDefault(header.Aspect, -1)
	meso := trimUpper(header.MesoSlopePos)
	drainage := strings.ToLower(strings.TrimSpace(derefStr(header.SoilDrainage)))
	waterSrc := trimUpper(header.WaterSource)
	rzps := trimUpper(header.RootZoneParticleSize)
	rrType := trimUpper(header.RootRestrictingType)
	humusForm := trimUpper(header.HumusForm)
	floodFreq := trimUpper(header.FloodingRegimeFreq)
	surfMat := trimUpper(header.SurficialMaterialSurf)

	insolation := slope > 35.0 && aspect >= 157 && aspect <= 285
	coldSlope := slope > 35.0 && aspect >= 0 && aspect != 999 && (aspect >= 337 || aspect <= 105)

	soilDepth, hasExplicitDepth := resolveRestrictingSoilDepth(header, rrType, lithicDepth, maxMineralLower)
	isFragmental, isCoarse, isFine := classifyParticleSizeRegime(dominantTexture, rzps, weightedCF, cfWeight)
	wsi, wsiDepth, waterTableAtSurface := evaluateWetSoilIndicators(
		res, header, soilGroup, drainage, waterSrc,
		hasPeatyHorizons, hasGleying, peatTotalThickness, minGleyDepth,
	)

	activeFluvial := waterSrc == "F" || floodFreq == "A" || floodFreq == "F" || strings.HasPrefix(surfMat, "FA")
	bedrockPct := derefFloatOrZero(header.SubstrateBedRock)
	slopeGroup := classifyMesoSlopeGroup(meso, header.Slope != nil, slope)
	restrictedFlow := slope < 5.0 && (isVeryPoorDrainage(drainage) || drainage == "p" || isFine)
	humusClass := classifyHumusFormFamily(humusForm)
	isSaline := waterSrc == "E" || rrType == "X" || hasSalineHorizon

	return edatopicSiteIndicators{
		slope:               slope,
		aspect:              aspect,
		meso:                meso,
		drainage:            drainage,
		waterSrc:            waterSrc,
		rzps:                rzps,
		rrType:              rrType,
		humusForm:           humusForm,
		humusClass:          humusClass,
		insolation:          insolation,
		coldSlope:           coldSlope,
		soilDepth:           soilDepth,
		hasExplicitDepth:    hasExplicitDepth,
		isFragmental:        isFragmental,
		isCoarse:            isCoarse,
		isFine:              isFine,
		wsi:                 wsi,
		wsiDepth:            wsiDepth,
		waterTableAtSurface: waterTableAtSurface,
		activeFluvial:       activeFluvial,
		bedrockPct:          bedrockPct,
		slopeGroup:          slopeGroup,
		restrictedFlow:      restrictedFlow,
		isSaline:            isSaline,
	}
}

func derefFloatOrZero(v *float64) float64 {
	if v != nil {
		return *v
	}
	return 0.0
}

func derefIntOrDefault(v *int, fallback int) int {
	if v != nil {
		return *v
	}
	return fallback
}

func resolveRestrictingSoilDepth(header vprocore.FS882Header, rrType string, lithicDepth, maxMineralLower float64) (float64, bool) {
	soilDepth := 120.0
	hasExplicit := false
	if header.RootRestrictingDepth != nil && rrType != "N" {
		soilDepth = float64(*header.RootRestrictingDepth)
		hasExplicit = true
	}
	if lithicDepth >= 0 && (!hasExplicit || lithicDepth < soilDepth) {
		soilDepth = lithicDepth
		hasExplicit = true
	}
	if !hasExplicit && maxMineralLower > 0 && maxMineralLower < 40 && rrType == "L" {
		soilDepth = maxMineralLower
		hasExplicit = true
	}
	return soilDepth, hasExplicit
}

func classifyParticleSizeRegime(dominantTexture, rzps string, weightedCF, cfWeight float64) (isFragmental, isCoarse, isFine bool) {
	avgCF := 20.0
	if cfWeight > 0 {
		avgCF = weightedCF / cfWeight
	}
	isSandy := isOneOf(dominantTexture, "S", "LS") || isOneOf(rzps, "S", "SS")
	isLoamy := isOneOf(dominantTexture, "SL", "L", "SCL") || isOneOf(rzps, "CL", "L", "FL")
	isSiltyClayey := isOneOf(dominantTexture, "SIL", "SI", "SICL", "CL", "SC", "SIC", "C") || isOneOf(rzps, "CSI", "FSI", "C", "FC")

	isFragmental = rzps == "F" || avgCF > 85.0
	isCoarse = isFragmental || isOneOf(rzps, "S", "SS", "CI", "CLS", "AS") ||
		(isSandy && (cfWeight == 0 || avgCF > 35.0)) ||
		(isLoamy && avgCF > 70.0) || avgCF > 70.0
	isFine = !isCoarse && (isOneOf(rzps, "C", "FC", "CSI", "FSI") ||
		(isSiltyClayey && (cfWeight == 0 || avgCF <= 20.0)))
	return isFragmental, isCoarse, isFine
}

func isOneOf(val string, candidates ...string) bool {
	for _, c := range candidates {
		if val == c {
			return true
		}
	}
	return false
}

func isVeryPoorDrainage(drainage string) bool {
	return drainage == "v" || drainage == "aq" || drainage == "pa"
}

func evaluateWetSoilIndicators(
	res *PlotDiagnosticsResult,
	header vprocore.FS882Header,
	soilGroup, drainage, waterSrc string,
	hasPeatyHorizons, hasGleying bool,
	peatTotalThickness, minGleyDepth float64,
) (wsi bool, wsiDepth float64, waterTableAtSurface bool) {
	wsiDepth = 999.0
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
	if dWsi, dDepth := drainageWSIThreshold(drainage); dWsi {
		wsi = true
		if dDepth.bound < 0 || wsiDepth > dDepth.bound {
			wsiDepth = dDepth.target
		}
	}
	if isOneOf(waterSrc, "G", "S", "M", "T", "E") {
		wsi = true
		if wsiDepth > 50 {
			wsiDepth = 45
		}
	}
	waterTableAtSurface = isVeryPoorDrainage(drainage) ||
		(header.SeepageDepth != nil && *header.SeepageDepth == 0) ||
		(header.SubstrateWater != nil && *header.SubstrateWater >= 25.0)
	return wsi, wsiDepth, waterTableAtSurface
}

type wsiDepthCap struct {
	bound  float64
	target float64
}

func drainageWSIThreshold(drainage string) (bool, wsiDepthCap) {
	switch drainage {
	case "v", "aq", "pa":
		return true, wsiDepthCap{bound: -1, target: 0}
	case "p", "ac":
		return true, wsiDepthCap{bound: 25, target: 20}
	case "i", "sa":
		return true, wsiDepthCap{bound: 45, target: 45}
	default:
		return false, wsiDepthCap{}
	}
}

func classifyMesoSlopeGroup(meso string, hasSlope bool, slope float64) string {
	switch meso {
	case "CR", "UP":
		return "UPPER"
	case "MD":
		return "MID"
	case "LW", "TO", "GU":
		return "LOWER"
	case "LV", "DP":
		return "FLAT"
	default:
		if hasSlope && slope < 5.0 {
			return "FLAT"
		}
		return "MID"
	}
}

func inferKey94SMR(res *PlotDiagnosticsResult, ind edatopicSiteIndicators) (int, string) {
	switch ind.slopeGroup {
	case "UPPER":
		return inferUpperSlopeSMR(res, ind)
	case "LOWER":
		return inferLowerSlopeSMR(res, ind)
	case "FLAT":
		return inferFlatSlopeSMR(res, ind)
	default:
		return inferMidSlopeSMR(res, ind)
	}
}

func inferUpperSlopeSMR(res *PlotDiagnosticsResult, ind edatopicSiteIndicators) (int, string) {
	if ind.wsi {
		if ind.wsiDepth < 30 {
			res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Ridge/Upper + WSI", "WSI < 30 cm from surface", "6"})
			return 6, "6"
		}
		res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Ridge/Upper + WSI", "WSI >= 30 cm from surface", "(4)-5"})
		return 5, "(4)-5"
	}
	if ind.hasExplicitDepth && ind.soilDepth < 40 {
		if ind.bedrockPct > 10 || ind.soilDepth < 20 {
			res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Ridge/Upper shallow (<40 cm)", "Bedrock > 10% or soil depth < 20 cm", "0(-1)"})
			return 0, "0(-1)"
		}
		res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Ridge/Upper shallow (<40 cm)", "Soil depth 20-40 cm, bedrock <= 10%", "1"})
		return 1, "1"
	}
	if ind.isCoarse {
		if ind.insolation {
			res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Ridge/Upper deep coarse", "Insolation slope (>35%, SSE-W)", "1(-2)"})
			return 1, "1(-2)"
		}
		res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Ridge/Upper deep coarse", "Non-insolation slope", "(1-)2"})
		if ind.coldSlope {
			return 3, "2-3 (cold aspect)"
		}
		return 2, "(1-)2"
	}
	if ind.insolation {
		res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Ridge/Upper deep medium/fine", "Insolation slope (>35%, SSE-W)", "2(-3)"})
		return 2, "2(-3)"
	}
	res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Ridge/Upper deep medium/fine", "Non-insolation slope", "(2-)3"})
	if ind.coldSlope {
		return 4, "3-4 (cold aspect)"
	}
	return 3, "(2-)3"
}

func inferMidSlopeSMR(res *PlotDiagnosticsResult, ind edatopicSiteIndicators) (int, string) {
	if ind.wsi {
		if ind.wsiDepth < 30 {
			res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Mid slope + WSI", "WSI < 30 cm from surface", "6"})
			return 6, "6"
		}
		res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Mid slope + WSI", "WSI >= 30 cm from surface", "(4-)5"})
		return 5, "(4-)5"
	}
	shallow := ind.hasExplicitDepth && ind.soilDepth < 50
	if ind.isCoarse {
		if shallow && ind.insolation {
			res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Mid slope coarse", "Both soil depth < 50 cm and insolation", "1-(2)"})
			return 1, "1-(2)"
		}
		if shallow || ind.insolation {
			res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Mid slope coarse", "Either soil depth < 50 cm or insolation", "2"})
			return 2, "2"
		}
		res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Mid slope coarse", "Soil depth >= 50 cm and non-insolation", "3"})
		return 3, "3"
	}
	if shallow && ind.insolation {
		res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Mid slope medium/fine", "Both soil depth < 50 cm and insolation", "2"})
		return 2, "2"
	}
	if shallow || ind.insolation {
		res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Mid slope medium/fine", "Either soil depth < 50 cm or insolation", "3"})
		if ind.coldSlope {
			return 4, "3-4 (cold aspect)"
		}
		return 3, "3"
	}
	res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Mid slope medium/fine", "Deep (>= 50 cm) non-insolation mesic reference", "4"})
	return 4, "4"
}

func inferLowerSlopeSMR(res *PlotDiagnosticsResult, ind edatopicSiteIndicators) (int, string) {
	if ind.wsi {
		if ind.wsiDepth < 30 {
			if ind.waterTableAtSurface {
				res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Lower/Toe/Gully + WSI", "Water table at or above surface", "8"})
				return 8, "8"
			}
			res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Lower/Toe/Gully + WSI", "WSI < 30 cm from surface", "7"})
			return 7, "7"
		}
		res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Lower/Toe/Gully + WSI", "WSI >= 30 cm from surface", "6"})
		return 6, "6"
	}
	if ind.isCoarse {
		res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Lower/Toe/Gully without WSI", "Coarse particle size", "4(-5)"})
		return 4, "4(-5)"
	}
	res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Lower/Toe/Gully without WSI", "Medium/fine particle size", "5(-6)"})
	return 5, "5(-6)"
}

func inferFlatSlopeSMR(res *PlotDiagnosticsResult, ind edatopicSiteIndicators) (int, string) {
	if (ind.wsi && ind.wsiDepth < 60) || ind.activeFluvial {
		if ind.wsi && ind.wsiDepth < 30 {
			if ind.waterTableAtSurface {
				res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Flat/Depression wet", "WSI < 30 cm and water table at/above surface", "8"})
				return 8, "8"
			}
			res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Flat/Depression wet", "WSI < 30 cm, water table below surface", "7"})
			return 7, "7"
		}
		if ind.isFine {
			res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Flat/Depression moist", "WSI 30-60 cm or fluvial + fine particle size", "6"})
			return 6, "6"
		}
		res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Flat/Depression moist", "WSI 30-60 cm or fluvial + non-fine particle size", "5"})
		return 5, "5"
	}
	if ind.isCoarse {
		res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Flat/Depression dry", "No WSI < 60 cm + coarse particle size", "2-3"})
		return 2, "2-3"
	}
	if ind.isFine {
		res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Flat/Depression dry", "No WSI < 60 cm + fine particle size", "5"})
		return 5, "5"
	}
	res.SMRTrace = append(res.SMRTrace, KeyTraceStep{"9.4", "Flat/Depression dry", "No WSI < 60 cm + medium particle size", "4"})
	return 4, "4"
}

func recordSMRDivergence(res *PlotDiagnosticsResult, smrClass int, smrLabel string) {
	res.KeyedSMR = smrLabel
	res.KeyedSMRClass = &smrClass
	fieldClass, ok := parseFieldSMRClass(res.FieldSMR)
	if !ok {
		return
	}
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

func inferKey96SNR(
	res *PlotDiagnosticsResult,
	header vprocore.FS882Header,
	ind edatopicSiteIndicators,
	soilGroup string,
	peatTotalThickness, peatUpper40Total, peatOfUpper40, peatOmUpper40 float64,
	uplandTotalThickness, uplandHThickness float64,
	ahDepth, aeDepth float64,
	bDark, bLight, hasTurbation bool,
) (int, string) {
	var snrClass int
	var snrLabel string

	switch {
	case ind.isSaline:
		snrClass, snrLabel = 5, "F"
		res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Excess Saline / Tidal / Chemical", "Saline water source, chemical restriction, or pH > 8.2", "F"})
	case ind.wsi || ind.activeFluvial:
		snrClass, snrLabel = inferWetOrFluvialSNR(res, ind, soilGroup, peatTotalThickness, peatUpper40Total, peatOfUpper40, peatOmUpper40, ahDepth)
	case (ind.hasExplicitDepth && ind.soilDepth < 30) || ind.isFragmental || soilGroup == "FO":
		snrClass, snrLabel = inferShallowOrFolisolSNR(res, ind, soilGroup, uplandTotalThickness, uplandHThickness, ahDepth, aeDepth, bDark, bLight)
	case ind.isCoarse || (ind.hasExplicitDepth && ind.soilDepth < 50):
		snrClass, snrLabel = inferCoarseOrModeratelyShallowSNR(res, ind, ahDepth, aeDepth, bDark, bLight, hasTurbation)
	default:
		snrClass, snrLabel = inferDeepUplandSNR(res, ind, ahDepth, aeDepth, bDark, bLight, uplandTotalThickness)
	}

	if hasPermafrostIndicator(header, ind) && snrClass > 0 && snrClass < 5 {
		snrClass--
		snrLabel = snrClassLetter(snrClass)
		res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6*", "Permafrost adjustment", "Permafrost / active layer present -> lower SNR by 1 class", snrLabel})
	}
	return snrClass, snrLabel
}

func hasPermafrostIndicator(header vprocore.FS882Header, ind edatopicSiteIndicators) bool {
	return ind.waterSrc == "Z" || ind.rrType == "Z" || (header.ActiveLayerDepth != nil && *header.ActiveLayerDepth > 0)
}

func inferWetOrFluvialSNR(
	res *PlotDiagnosticsResult,
	ind edatopicSiteIndicators,
	soilGroup string,
	peatTotalThickness, peatUpper40Total, peatOfUpper40, peatOmUpper40, ahDepth float64,
) (int, string) {
	if peatTotalThickness > 20 || (res.IsOrganicSoilOrder && soilGroup != "FO") {
		return inferPeatyWetSNR(res, ind, soilGroup, peatUpper40Total, peatOfUpper40, peatOmUpper40)
	}
	richSurface := ahDepth > 5 || ind.humusClass == "MULL"
	if ind.wsi && ind.wsiDepth < 30 {
		if ind.restrictedFlow {
			if richSurface {
				res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "WSI < 30 cm + restricted flow", "Ah > 5 cm or Mull humus", "C"})
				return 2, "C"
			}
			res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "WSI < 30 cm + restricted flow", "Ah <= 5 cm", "B"})
			return 1, "B"
		}
		if richSurface || ind.activeFluvial {
			res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "WSI < 30 cm + moving water", "Ah > 5 cm, Mull, or active fluvial", "D"})
			return 3, "D"
		}
		res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "WSI < 30 cm + moving water", "Ah <= 5 cm, non-fluvial", "C"})
		return 2, "C"
	}
	if ind.restrictedFlow {
		if richSurface {
			res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "WSI >= 30 cm + restricted flow", "Ah > 5 cm or Mull humus", "D"})
			return 3, "D"
		}
		res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "WSI >= 30 cm + restricted flow", "Ah <= 5 cm", "C"})
		return 2, "C"
	}
	if richSurface || ind.activeFluvial {
		res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "WSI >= 30 cm / Active Fluvial", "Ah > 5 cm, Mull, or active fluvial seepage", "E"})
		return 4, "E"
	}
	res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "WSI >= 30 cm + moving water", "Ah <= 5 cm", "D"})
	return 3, "D"
}

func inferPeatyWetSNR(
	res *PlotDiagnosticsResult,
	ind edatopicSiteIndicators,
	soilGroup string,
	peatUpper40Total, peatOfUpper40, peatOmUpper40 float64,
) (int, string) {
	ofDom := (peatUpper40Total > 0 && peatOfUpper40/peatUpper40Total >= 0.5) || soilGroup == "F"
	ofOmDom := (peatUpper40Total > 0 && (peatOfUpper40+peatOmUpper40)/peatUpper40Total >= 0.5) || soilGroup == "M"
	switch {
	case ofDom:
		res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Wet/Peaty > 20 cm", "Of (fibric) dominant in upper 40 cm", "A-B"})
		return 0, "A-B"
	case ofOmDom:
		res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Wet/Peaty > 20 cm", "Of+Om dominant in upper 40 cm", "B-C"})
		return 1, "B-C"
	case ind.restrictedFlow:
		res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Wet/Peaty > 20 cm", "Oh dominant + restricted water flow", "C-D"})
		return 2, "C-D"
	default:
		res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Wet/Peaty > 20 cm", "Oh dominant + moving water", "D-E"})
		return 3, "D-E"
	}
}

func inferShallowOrFolisolSNR(
	res *PlotDiagnosticsResult,
	ind edatopicSiteIndicators,
	soilGroup string,
	uplandTotalThickness, uplandHThickness, ahDepth, aeDepth float64,
	bDark, bLight bool,
) (int, string) {
	if soilGroup == "FO" {
		if (uplandTotalThickness + ind.soilDepth) < 30 {
			res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Folisol", "LFH + Mineral < 30 cm", "A"})
			return 0, "A"
		}
		if uplandTotalThickness > 0 && uplandHThickness/uplandTotalThickness >= 0.5 {
			res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Folisol", "H horizons dominant", "C"})
			return 2, "C"
		}
		res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Folisol", "L/F horizons dominant", "B"})
		return 1, "B"
	}
	if ahDepth > 5 || bDark || ind.humusClass == "MULL" {
		res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Mineral < 30 cm or Fragmental", "Ah > 5 cm, dark B (value <= 3), or Mull", "C"})
		return 2, "C"
	}
	if bLight || aeDepth > 2 || (ind.hasExplicitDepth && ind.soilDepth < 10) || (ind.humusClass == "MOR" && ind.isCoarse) {
		res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Mineral < 30 cm or Fragmental", "Light soil (value >= 7), Ae > 2 cm, depth < 10 cm, or coarse Mor", "A"})
		return 0, "A"
	}
	res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Mineral < 30 cm or Fragmental", "Moderate mineral colour, no thick Ae", "B"})
	return 1, "B"
}

func inferCoarseOrModeratelyShallowSNR(
	res *PlotDiagnosticsResult,
	ind edatopicSiteIndicators,
	ahDepth, aeDepth float64,
	bDark, bLight, hasTurbation bool,
) (int, string) {
	if ahDepth > 2 || bDark || ind.humusClass == "MULL" {
		if hasTurbation || ind.humusClass == "MULL" {
			res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Coarse or depth < 50 cm", "Ah > 2 cm / dark B + Mull or soil turbation", "D"})
			return 3, "D"
		}
		res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Coarse or depth < 50 cm", "Ah > 2 cm or dark B without turbation", "C"})
		return 2, "C"
	}
	if bLight || aeDepth > 2 {
		res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Coarse or depth < 50 cm", "Light B (value >= 7) or Ae > 2 cm", "A"})
		return 0, "A"
	}
	if ind.humusClass == "MODER" {
		res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.7", "Coarse or depth < 50 cm + Moder", "Moder humus form on >= 30 cm soil", "C"})
		return 2, "C"
	}
	res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Coarse or depth < 50 cm", "Mor/unspecified humus without dark B or thick Ae", "B"})
	return 1, "B"
}

func inferDeepUplandSNR(
	res *PlotDiagnosticsResult,
	ind edatopicSiteIndicators,
	ahDepth, aeDepth float64,
	bDark, bLight bool,
	uplandTotalThickness float64,
) (int, string) {
	if ahDepth > 2 || bDark || ind.humusClass == "MULL" {
		if ind.isFine && ahDepth > 5 {
			res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Deep medium/fine upland", "Fine textured + Ah > 5 cm", "E"})
			return 4, "E"
		}
		res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Deep medium/fine upland", "Ah > 2 cm, dark B (value <= 3), or Mull humus", "D"})
		return 3, "D"
	}
	if bLight || aeDepth > 2 || (ind.humusClass == "MOR" && ind.coldSlope && uplandTotalThickness > 10) {
		res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Deep medium/fine upland", "Light B (value >= 7), Ae > 2 cm, or thick Mor on cool aspect", "B"})
		return 1, "B"
	}
	if ind.humusClass == "MODER" && ind.slopeGroup == "LOWER" {
		res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.7", "Deep medium/fine + Moder on lower/toe", "Moder humus on receiving slope", "D"})
		return 3, "D"
	}
	res.SNRTrace = append(res.SNRTrace, KeyTraceStep{"9.6", "Deep medium/fine upland", "Mesotrophic reference soil", "C"})
	return 2, "C"
}

func recordSNRDivergence(res *PlotDiagnosticsResult, snrClass int, snrLabel string) {
	res.KeyedSNR = snrLabel
	res.KeyedSNRClass = &snrClass
	fieldClass, ok := parseFieldSNRClass(res.FieldSNR)
	if !ok {
		return
	}
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
