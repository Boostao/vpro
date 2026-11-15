package rsidecar

import (
	"bytes"
	"crypto/sha256"
	"encoding/csv"
	"encoding/hex"
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"
	"sync"

	"github.com/boostao/vpro/app/internal/sqlutil"
)

const (
	PlotClimateTableName = "__VPRO_PlotClimate"
	plotClimateDDL       = `CREATE TABLE IF NOT EXISTS main."__VPRO_PlotClimate" (
		"PlotNumber" TEXT PRIMARY KEY,
		"CoordElevHash" TEXT NOT NULL,
		"RefPeriod" TEXT NOT NULL,
		"Source" TEXT NOT NULL,
		"MAT" REAL,
		"MWMT" REAL,
		"MCMT" REAL,
		"MAP" REAL,
		"MSP" REAL,
		"PAS" REAL,
		"CMD" REAL,
		"PPT_05" REAL,
		"PPT_06" REAL,
		"PPT_07" REAL,
		"PPT_08" REAL,
		"PPT_09" REAL,
		"PPT_at" REAL,
		"PPT_wt" REAL,
		"DD5" REAL,
		"NFFD" REAL,
		"ComputedAt" TEXT NOT NULL
	)`
)

// PlotClimateRow represents one cached plot climate normal record in __VPRO_PlotClimate
// enriched with the plot's site/edatopic attributes and computed Ministry CMD -> aSMR output.
type PlotClimateRow struct {
	PlotNumber     string   `json:"plotNumber"`
	CoordElevHash  string   `json:"coordElevHash"`
	RefPeriod      string   `json:"refPeriod"`
	Source         string   `json:"source"`
	Latitude       float64  `json:"latitude"`
	Longitude      float64  `json:"longitude"`
	Elevation      float64  `json:"elevation"`
	BGC            string   `json:"bgc"`
	SiteUnit       string   `json:"siteUnit"`
	SlopeGradient  *float64 `json:"slopeGradient,omitempty"`
	Aspect         *float64 `json:"aspect,omitempty"`
	RSMR           string   `json:"rsmr"`
	RSNR           string   `json:"rsnr"`
	MAT            float64  `json:"mat"`
	MWMT           float64  `json:"mwmt"`
	MCMT           float64  `json:"mcmt"`
	MAP            float64  `json:"map"`
	MSP            float64  `json:"msp"`
	PAS            float64  `json:"pas"`
	CMD            float64  `json:"cmd"`
	PPT05          float64  `json:"ppt05"`
	PPT06          float64  `json:"ppt06"`
	PPT07          float64  `json:"ppt07"`
	PPT08          float64  `json:"ppt08"`
	PPT09          float64  `json:"ppt09"`
	PPTAt          float64  `json:"pptAt"`
	PPTWt          float64  `json:"pptWt"`
	DD5            float64  `json:"dd5"`
	NFFD           float64  `json:"nffd"`
	MoistMonths    int      `json:"moistMonths"`
	DormantDeficit float64  `json:"dormantDeficit"`
	AspectFactor   float64  `json:"aspectFactor"`
	CMDTopo        float64  `json:"cmdTopo"`
	CMDSite        *float64 `json:"cmdSite,omitempty"`
	ASMR           *float64 `json:"asmr,omitempty"`
	ComputedAt     string   `json:"computedAt"`
}

// EdatopicGridCell represents one (moisture x nutrient) cell in either a Relative (rSMR) or Actual (aSMR) edatopic grid.
type EdatopicGridCell struct {
	Moisture    string   `json:"moisture"`
	Nutrient    string   `json:"nutrient"`
	Count       int      `json:"count"`
	Frequency   float64  `json:"frequency"`
	MeanCMD     *float64 `json:"meanCmd,omitempty"`
	MeanCMDSite *float64 `json:"meanCmdSite,omitempty"`
	PlotNumbers []string `json:"plotNumbers"`
}

// EdatopicGridMatrix holds a full 2D edatopic grid summary (rSMR x rSNR or aSMR x rSNR).
type EdatopicGridMatrix struct {
	Kind         string             `json:"kind"` // "relative" | "actual"
	MoistureAxis []string           `json:"moistureAxis"`
	NutrientAxis []string           `json:"nutrientAxis"`
	TotalPlots   int                `json:"totalPlots"`
	ModalCell    string             `json:"modalCell"`
	Cells        []EdatopicGridCell `json:"cells"`
}

// DualUnitEdatopicSummary pairs Relative (rSMR x rSNR) and Actual (aSMR x rSNR) grids for a BGC or SiteUnit.
type DualUnitEdatopicSummary struct {
	GroupKey     string             `json:"groupKey"`
	BGC          string             `json:"bgc"`
	SiteUnit     string             `json:"siteUnit"`
	PlotCount    int                `json:"plotCount"`
	MeanMAT      float64            `json:"meanMat"`
	MeanMAP      float64            `json:"meanMap"`
	MeanCMD      float64            `json:"meanCmd"`
	MeanASMR     *float64           `json:"meanAsmr,omitempty"`
	MeanShift    *float64           `json:"meanShift,omitempty"` // mean(aSMR - rSMR)
	RelativeGrid EdatopicGridMatrix `json:"relativeGrid"`
	ActualGrid   EdatopicGridMatrix `json:"actualGrid"`
}

// ClimateEdatopicRequest configures batch __VPRO_PlotClimate caching and CMD -> aSMR dual edatopic computation.
type ClimateEdatopicRequest struct {
	RefPeriod         string   `json:"refPeriod"` // "1961_1990" (default) | "1991_2020"
	GroupBy           string   `json:"groupBy"`   // "bgc" | "site_unit" (default "site_unit" when SU active else "bgc")
	BGCFilter         string   `json:"bgcFilter"` // Optional BGC filter
	SiteUnitFilter    string   `json:"siteUnitFilter"`
	UseActiveSU       bool     `json:"useActiveSu"`
	PlotNumbers       []string `json:"plotNumbers,omitempty"`
	ForceRefresh      bool     `json:"forceRefresh"`
	ForceOfflineModel bool     `json:"forceOfflineModel"`
}

func (r *ClimateEdatopicRequest) UnmarshalJSON(data []byte) error {
	type plain ClimateEdatopicRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

// ClimateEdatopicResult returns cached/newly-computed plot climate rows and side-by-side Relative vs Actual edatopic grids.
type ClimateEdatopicResult struct {
	ContextID          string                    `json:"contextId"`
	Project            string                    `json:"project"`
	ActiveSU           string                    `json:"activeSu"`
	RefPeriod          string                    `json:"refPeriod"`
	TotalScopedPlots   int                       `json:"totalScopedPlots"`
	CoordinatizedPlots int                       `json:"coordinatizedPlots"`
	SkippedNoCoords    int                       `json:"skippedNoCoords"`
	CacheHits          int                       `json:"cacheHits"`
	CacheMisses        int                       `json:"cacheMisses"`
	SourceSummary      map[string]int            `json:"sourceSummary"`
	OverallRelative    EdatopicGridMatrix        `json:"overallRelative"`
	OverallActual      EdatopicGridMatrix        `json:"overallActual"`
	UnitSummaries      []DualUnitEdatopicSummary `json:"unitSummaries"`
	Plots              []PlotClimateRow          `json:"plots"`
}

type asmrRuleRow struct {
	SMRLevel int
	CMDMax   float64
	ASMR     float64
}

var (
	asmrRulesOnce sync.Once
	asmrRulesData []asmrRuleRow
	asmrRulesErr  error
)

func loadEmbeddedASMRRules() ([]asmrRuleRow, error) {
	asmrRulesOnce.Do(func() {
		raw, err := embeddedAssets.ReadFile("assets/aSMR_Rules_HalfStep.csv")
		if err != nil {
			asmrRulesErr = err
			return
		}
		raw = bytes.TrimPrefix(raw, []byte{0xEF, 0xBB, 0xBF})
		reader := csv.NewReader(bytes.NewReader(raw))
		records, err := reader.ReadAll()
		if err != nil {
			asmrRulesErr = err
			return
		}
		for i, rec := range records {
			if i == 0 || len(rec) < 3 {
				continue
			}
			lvl, err1 := strconv.Atoi(strings.TrimSpace(rec[0]))
			cmdMax, err2 := strconv.ParseFloat(strings.TrimSpace(rec[1]), 64)
			asmrVal, err3 := strconv.ParseFloat(strings.TrimSpace(rec[2]), 64)
			if err1 != nil || err2 != nil || err3 != nil {
				continue
			}
			asmrRulesData = append(asmrRulesData, asmrRuleRow{
				SMRLevel: lvl,
				CMDMax:   cmdMax,
				ASMR:     asmrVal,
			})
		}
	})
	return asmrRulesData, asmrRulesErr
}

// NormalizeBCWesternLongitude converts legacy positive BC western longitudes (e.g. 123.629 -> -123.629)
// while leaving already-negative longitudes intact.
func NormalizeBCWesternLongitude(lon float64) float64 {
	if lon > 0 && lon >= 110.0 && lon <= 145.0 {
		return -lon
	}
	return lon
}

// NormalizeRefPeriod normalizes climate reference period identifiers.
func NormalizeRefPeriod(raw string) (string, error) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return "1961_1990", nil
	}
	normalized := strings.ReplaceAll(trimmed, "-", "_")
	switch normalized {
	case "1961_1990", "1991_2020":
		return normalized, nil
	default:
		return "", fmt.Errorf("unsupported climate reference period %q (expected 1961_1990 or 1991_2020)", raw)
	}
}

// ComputeCoordElevHash computes a deterministic 128-bit hex key over (Round(Lat,5), Round(Lon,5), Round(Elev,1), RefPeriod).
func ComputeCoordElevHash(lat, lon, elev float64, refPeriod string) string {
	normLon := NormalizeBCWesternLongitude(lon)
	lat5 := math.Round(lat*1e5) / 1e5
	lon5 := math.Round(normLon*1e5) / 1e5
	elev1 := math.Round(elev*10.0) / 10.0
	canonical := fmt.Sprintf("%.5f|%.5f|%.1f|%s", lat5, lon5, elev1, refPeriod)
	sum := sha256.Sum256([]byte(canonical))
	return hex.EncodeToString(sum[:16])
}

func parseRSMRDigit(raw string) (int, bool) {
	s := strings.TrimSpace(raw)
	for _, ch := range s {
		if ch >= '0' && ch <= '8' {
			return int(ch - '0'), true
		}
	}
	return 0, false
}

func normalizeRSNRCode(raw string) string {
	s := strings.ToUpper(strings.TrimSpace(raw))
	for _, ch := range s {
		if ch >= 'A' && ch <= 'F' {
			if ch == 'F' {
				// Map hyper-eutrophic F into E+ / E column when displaying standard 5-column A..E BEC grid, or preserve A..E
				return "E"
			}
			return string(ch)
		}
	}
	return ""
}

// ASMRTransferOutput holds intermediate and final outputs of the Ministry CMD -> aSMR transfer function.
type ASMRTransferOutput struct {
	MoistMonths    int
	DormantPrecip  float64
	DormantDeficit float64
	AspectFactor   float64
	CMDTopo        float64
	CMDSite        *float64
	ASMR           *float64
}

// EvaluateMinistryASMR implements the exact Ministry CMD -> aSMR transfer function from
// BEC_R_working/_functions/_calculate_aSMR.R + aSMR_Rules_HalfStep.csv.
func EvaluateMinistryASMR(
	cmdAnnual float64,
	ppt05, ppt06, ppt07, ppt08, ppt09 float64,
	pptAt, pptWt float64,
	slope, aspect *float64,
	rsmrRaw string,
) (ASMRTransferOutput, error) {
	rules, err := loadEmbeddedASMRRules()
	if err != nil {
		return ASMRTransferOutput{}, err
	}

	moistCnt := 0
	for _, p := range []float64{ppt05, ppt06, ppt07, ppt08, ppt09} {
		if !math.IsNaN(p) && p >= 90.0 {
			moistCnt++
		}
	}
	moistFlag := 0.0
	if moistCnt > 4 {
		moistFlag = 1.0
	}
	multiplier := 1.0 + (moistFlag / 5.0)
	cmdGS := cmdAnnual / multiplier

	pptDorm := pptAt + pptWt
	defVal := math.Max(0.0, 350.0-pptDorm)
	cmdTotal := cmdGS + defVal

	aspectFactor := 1.0
	if slope != nil && aspect != nil && !math.IsNaN(*slope) && !math.IsNaN(*aspect) && *slope > 35.0 {
		if *aspect > 180.0 && *aspect < 270.0 {
			aspectFactor = 1.25
		} else if *aspect > 315.0 || (*aspect >= 0.0 && *aspect < 45.0) {
			aspectFactor = 0.85
		}
	}
	cmdTopo := math.Round(cmdTotal*aspectFactor*10.0) / 10.0

	out := ASMRTransferOutput{
		MoistMonths:    moistCnt,
		DormantPrecip:  math.Round(pptDorm*10.0) / 10.0,
		DormantDeficit: math.Round(defVal*10.0) / 10.0,
		AspectFactor:   aspectFactor,
		CMDTopo:        cmdTopo,
	}

	rInt, ok := parseRSMRDigit(rsmrRaw)
	if !ok {
		return out, nil
	}
	if rInt == 8 {
		zero := 0.0
		eight := 8.0
		out.CMDSite = &zero
		out.ASMR = &eight
		return out, nil
	}

	var cmdSite float64
	switch {
	case rInt < 4:
		cmdSite = cmdTopo + float64(4-rInt)*125.0
	case rInt == 4:
		cmdSite = cmdTopo
	case rInt == 5:
		cmdSite = cmdTopo / 2.0
	case rInt == 6:
		cmdSite = cmdTopo / 4.0
	default: // rInt == 7
		cmdSite = cmdTopo / 8.0
	}
	cmdSite = math.Round(math.Max(0.0, cmdSite)*10.0) / 10.0
	out.CMDSite = &cmdSite

	smrLevel := 0
	if rInt >= 5 {
		smrLevel = rInt
	}
	bestASMR := 0.0
	matched := false
	for _, r := range rules {
		if r.SMRLevel == smrLevel && cmdSite <= r.CMDMax {
			if !matched || r.ASMR > bestASMR {
				bestASMR = r.ASMR
				matched = true
			}
		}
	}
	out.ASMR = &bestASMR
	return out, nil
}

func formatASMRLabel(v float64) string {
	rounded := math.Round(v*2.0) / 2.0
	if math.Abs(rounded-math.Round(rounded)) < 1e-6 {
		return strconv.Itoa(int(math.Round(rounded)))
	}
	return fmt.Sprintf("%.1f", rounded)
}

func buildEdatopicMatrices(rows []PlotClimateRow) (EdatopicGridMatrix, EdatopicGridMatrix) {
	nutrients := []string{"A", "B", "C", "D", "E"}
	relRows := []string{"0", "1", "2", "3", "4", "5", "6", "7", "8"}
	actRows := []string{"0", "0.5", "1", "1.5", "2", "2.5", "3", "3.5", "4", "4.5", "5", "5.5", "6", "6.5", "7", "7.5", "8"}

	type accum struct {
		plots      []string
		cmdSum     float64
		cmdCnt     int
		cmdSiteSum float64
		cmdSiteCnt int
	}
	relMap := make(map[string]*accum)
	actMap := make(map[string]*accum)
	relTotal := 0
	actTotal := 0

	for _, r := range rows {
		snr := normalizeRSNRCode(r.RSNR)
		if snr == "" {
			continue
		}
		if rDigit, ok := parseRSMRDigit(r.RSMR); ok {
			key := fmt.Sprintf("%d|%s", rDigit, snr)
			a := relMap[key]
			if a == nil {
				a = &accum{}
				relMap[key] = a
			}
			a.plots = append(a.plots, r.PlotNumber)
			a.cmdSum += r.CMD
			a.cmdCnt++
			if r.CMDSite != nil {
				a.cmdSiteSum += *r.CMDSite
				a.cmdSiteCnt++
			}
			relTotal++
		}
		if r.ASMR != nil {
			aLbl := formatASMRLabel(*r.ASMR)
			key := fmt.Sprintf("%s|%s", aLbl, snr)
			a := actMap[key]
			if a == nil {
				a = &accum{}
				actMap[key] = a
			}
			a.plots = append(a.plots, r.PlotNumber)
			a.cmdSum += r.CMD
			a.cmdCnt++
			if r.CMDSite != nil {
				a.cmdSiteSum += *r.CMDSite
				a.cmdSiteCnt++
			}
			actTotal++
		}
	}

	materialize := func(kind string, mAxis []string, total int, mp map[string]*accum) EdatopicGridMatrix {
		cells := make([]EdatopicGridCell, 0, len(mAxis)*len(nutrients))
		modal := ""
		modalCnt := 0
		for _, m := range mAxis {
			for _, n := range nutrients {
				a := mp[m+"|"+n]
				if a == nil || len(a.plots) == 0 {
					continue
				}
				cnt := len(a.plots)
				if cnt > modalCnt {
					modalCnt = cnt
					modal = m + "/" + n
				}
				var meanCmd, meanCmdSite *float64
				if a.cmdCnt > 0 {
					v := math.Round((a.cmdSum/float64(a.cmdCnt))*10.0) / 10.0
					meanCmd = &v
				}
				if a.cmdSiteCnt > 0 {
					v := math.Round((a.cmdSiteSum/float64(a.cmdSiteCnt))*10.0) / 10.0
					meanCmdSite = &v
				}
				freq := 0.0
				if total > 0 {
					freq = math.Round((float64(cnt)/float64(total))*1000.0) / 10.0
				}
				plotsCopy := make([]string, len(a.plots))
				copy(plotsCopy, a.plots)
				sort.Strings(plotsCopy)
				cells = append(cells, EdatopicGridCell{
					Moisture:    m,
					Nutrient:    n,
					Count:       cnt,
					Frequency:   freq,
					MeanCMD:     meanCmd,
					MeanCMDSite: meanCmdSite,
					PlotNumbers: plotsCopy,
				})
			}
		}
		return EdatopicGridMatrix{
			Kind:         kind,
			MoistureAxis: mAxis,
			NutrientAxis: nutrients,
			TotalPlots:   total,
			ModalCell:    modal,
			Cells:        cells,
		}
	}

	return materialize("relative", relRows, relTotal, relMap), materialize("actual", actRows, actTotal, actMap)
}
