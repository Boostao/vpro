package rsidecar

import (
	"context"
	"database/sql"
	"errors"
	"math"
	"sort"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/vprocore"
)

type rClimatePointInput struct {
	CoordElevHash string  `json:"coordElevHash"`
	Lat           float64 `json:"lat"`
	Lon           float64 `json:"lon"`
	Elev          float64 `json:"elev"`
	BGC           string  `json:"bgc"`
	Zone          string  `json:"zone"`
}

type rClimateNormalOutput struct {
	CoordElevHash string  `json:"coordElevHash"`
	Source        string  `json:"source"`
	MAT           float64 `json:"mat"`
	MWMT          float64 `json:"mwmt"`
	MCMT          float64 `json:"mcmt"`
	MAP           float64 `json:"map"`
	MSP           float64 `json:"msp"`
	PAS           float64 `json:"pas"`
	CMD           float64 `json:"cmd"`
	PPT05         float64 `json:"ppt05"`
	PPT06         float64 `json:"ppt06"`
	PPT07         float64 `json:"ppt07"`
	PPT08         float64 `json:"ppt08"`
	PPT09         float64 `json:"ppt09"`
	PPTAt         float64 `json:"pptAt"`
	PPTWt         float64 `json:"pptWt"`
	DD5           float64 `json:"dd5"`
	NFFD          float64 `json:"nffd"`
}

type rClimateScriptResponse struct {
	OK              bool                   `json:"ok"`
	RefPeriod       string                 `json:"refPeriod"`
	VProCompatible  bool                   `json:"vproCompatible"`
	ClimrUsed       bool                   `json:"climrUsed"`
	ComputedNormals []rClimateNormalOutput `json:"computedNormals"`
}

// GetCachedPlotClimate reads the currently cached __VPRO_PlotClimate rows enriched with plot site/edatopic metadata.
func GetCachedPlotClimate(
	ctx context.Context,
	contexts *vprocore.ContextService,
	contextID string,
	refPeriod string,
) ([]PlotClimateRow, error) {
	if ctx == nil {
		return nil, errors.New("GetCachedPlotClimate requires a non-nil context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("context service is unavailable")
	}
	period, err := NormalizeRefPeriod(refPeriod)
	if err != nil {
		return nil, err
	}

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) ([]PlotClimateRow, error) {
		owner := plots.Projects.Sqlite
		envPlots, err := readScopedEnvPlots(ctx, owner, false, "", "", nil)
		if err != nil {
			return nil, err
		}
		cacheMap, err := readExistingPlotClimateCacheReadOnly(ctx, owner)
		if err != nil {
			return nil, err
		}

		out := make([]PlotClimateRow, 0, len(cacheMap))
		for _, ep := range envPlots {
			c, ok := cacheMap[ep.PlotNumber]
			if !ok || c.RefPeriod != period {
				continue
			}
			lat, lon, elev := 0.0, 0.0, 0.0
			if ep.Latitude != nil {
				lat = *ep.Latitude
			}
			if ep.Longitude != nil {
				lon = *ep.Longitude
			}
			if ep.Elevation != nil {
				elev = *ep.Elevation
			}
			tr, err := EvaluateMinistryASMR(c.CMD, c.PPT05, c.PPT06, c.PPT07, c.PPT08, c.PPT09, c.PPTAt, c.PPTWt, ep.Slope, ep.Aspect, ep.RSMR)
			if err != nil {
				return nil, err
			}
			out = append(out, PlotClimateRow{
				PlotNumber:     ep.PlotNumber,
				CoordElevHash:  c.CoordElevHash,
				RefPeriod:      c.RefPeriod,
				Source:         c.Source,
				Latitude:       lat,
				Longitude:      lon,
				Elevation:      elev,
				BGC:            ep.BGC,
				SiteUnit:       ep.SiteUnit,
				SlopeGradient:  ep.Slope,
				Aspect:         ep.Aspect,
				RSMR:           ep.RSMR,
				RSNR:           ep.RSNR,
				MAT:            c.MAT,
				MWMT:           c.MWMT,
				MCMT:           c.MCMT,
				MAP:            c.MAP,
				MSP:            c.MSP,
				PAS:            c.PAS,
				CMD:            c.CMD,
				PPT05:          c.PPT05,
				PPT06:          c.PPT06,
				PPT07:          c.PPT07,
				PPT08:          c.PPT08,
				PPT09:          c.PPT09,
				PPTAt:          c.PPTAt,
				PPTWt:          c.PPTWt,
				DD5:            c.DD5,
				NFFD:           c.NFFD,
				MoistMonths:    tr.MoistMonths,
				DormantDeficit: tr.DormantDeficit,
				AspectFactor:   tr.AspectFactor,
				CMDTopo:        tr.CMDTopo,
				CMDSite:        tr.CMDSite,
				ASMR:           tr.ASMR,
				ComputedAt:     c.ComputedAt,
			})
		}
		return out, nil
	})
}

// ComputePlotClimateAndDualEdatopic maintains __VPRO_PlotClimate keyed by (Round(Lat,5), Round(Lon,5), Elev, RefPeriod)
// and computes side-by-side Relative (rSMR x rSNR) and Actual (aSMR x rSNR) edatopic grid matrices.
func ComputePlotClimateAndDualEdatopic(
	ctx context.Context,
	contexts *vprocore.ContextService,
	contextID string,
	req ClimateEdatopicRequest,
	opts ...RuntimeOptions,
) (*ClimateEdatopicResult, error) {
	if ctx == nil {
		return nil, errors.New("ComputePlotClimateAndDualEdatopic requires a non-nil context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("context service is unavailable")
	}
	if !utf8.ValidString(req.BGCFilter) || !utf8.ValidString(req.SiteUnitFilter) {
		return nil, errors.New("filter inputs must be valid UTF-8")
	}
	refPeriod, err := NormalizeRefPeriod(req.RefPeriod)
	if err != nil {
		return nil, err
	}
	cfg := effectiveOptions(opts...)

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*ClimateEdatopicResult, error) {
		owner := plots.Projects.Sqlite
		envPlots, err := readScopedEnvPlots(ctx, owner, req.UseActiveSU, req.BGCFilter, req.SiteUnitFilter, req.PlotNumbers)
		if err != nil {
			return nil, err
		}

		cacheByPlot, err := readExistingPlotClimateCacheReadOnly(ctx, owner)
		if err != nil {
			return nil, err
		}

		// Also index already-cached normals by CoordElevHash so a new plot at identical coordinates reuses cached normals
		normByHash := make(map[string]cachedNormalRecord, len(cacheByPlot))
		if !req.ForceRefresh {
			for _, rec := range cacheByPlot {
				if rec.RefPeriod == refPeriod {
					normByHash[rec.CoordElevHash] = rec
				}
			}
		}

		uncachedByHash := make(map[string]rClimatePointInput)
		var uncachedList []rClimatePointInput
		cacheHits := 0
		cacheMisses := 0
		coordinatized := 0
		skippedNoCoords := 0

		evaluatedSpecs := make([]plotClimateSpec, 0, len(envPlots))

		for _, ep := range envPlots {
			if ep.Latitude == nil || ep.Longitude == nil || ep.Elevation == nil {
				skippedNoCoords++
				continue
			}
			coordinatized++
			h := ComputeCoordElevHash(*ep.Latitude, *ep.Longitude, *ep.Elevation, refPeriod)
			existingPlot, plotMatched := cacheByPlot[ep.PlotNumber]
			if !req.ForceRefresh && plotMatched && existingPlot.CoordElevHash == h && existingPlot.RefPeriod == refPeriod {
				cacheHits++
				evaluatedSpecs = append(evaluatedSpecs, plotClimateSpec{ep: ep, hash: h, hit: true})
				continue
			}
			cacheMisses++
			evaluatedSpecs = append(evaluatedSpecs, plotClimateSpec{ep: ep, hash: h, hit: false})
			if _, ok := normByHash[h]; !ok {
				if _, queued := uncachedByHash[h]; !queued {
					normLon := NormalizeBCWesternLongitude(*ep.Longitude)
					pt := rClimatePointInput{
						CoordElevHash: h,
						Lat:           math.Round((*ep.Latitude)*1e5) / 1e5,
						Lon:           math.Round(normLon*1e5) / 1e5,
						Elev:          math.Round((*ep.Elevation)*10.0) / 10.0,
						BGC:           ep.BGC,
						Zone:          ep.Zone,
					}
					uncachedByHash[h] = pt
					uncachedList = append(uncachedList, pt)
				}
			}
		}

		canWriteCache := !owner.ReadOnly && owner.CheckEditLock() == nil
		var projDB *sql.DB
		if canWriteCache && (len(uncachedList) > 0 || cacheMisses > 0) {
			projDB, err = owner.ProjectDatabase(ctx)
			if err != nil {
				return nil, err
			}
		}

		// Invoke out-of-process R sidecar only when there are uncached coordinate hashes to compute
		if len(uncachedList) > 0 {
			if canWriteCache && projDB != nil {
				if err := CheckpointProjectWAL(ctx, projDB); err != nil {
					return nil, err
				}
			}
			var rResp rClimateScriptResponse
			rReq := map[string]any{
				"assetsDir":         ".",
				"projectPath":       owner.Selection.ProjectPath,
				"projectName":       owner.Selection.Project,
				"refPeriod":         refPeriod,
				"forceOfflineModel": req.ForceOfflineModel,
				"uncachedPoints":    uncachedList,
			}
			err := executeRScriptJSON(
				ctx,
				cfg,
				"",
				"compute_climate_asmr.R",
				[]string{"aSMR_Rules_HalfStep.csv", "CMD_adjustments.csv", "bgc_climate_normals.csv"},
				rReq,
				&rResp,
			)
			if err != nil {
				return nil, err
			}
			nowISO := time.Now().UTC().Format(time.RFC3339)
			for _, cn := range rResp.ComputedNormals {
				normByHash[cn.CoordElevHash] = cachedNormalRecord{
					CoordElevHash: cn.CoordElevHash,
					RefPeriod:     refPeriod,
					Source:        cn.Source,
					MAT:           cn.MAT,
					MWMT:          cn.MWMT,
					MCMT:          cn.MCMT,
					MAP:           cn.MAP,
					MSP:           cn.MSP,
					PAS:           cn.PAS,
					CMD:           cn.CMD,
					PPT05:         cn.PPT05,
					PPT06:         cn.PPT06,
					PPT07:         cn.PPT07,
					PPT08:         cn.PPT08,
					PPT09:         cn.PPT09,
					PPTAt:         cn.PPTAt,
					PPTWt:         cn.PPTWt,
					DD5:           cn.DD5,
					NFFD:          cn.NFFD,
					ComputedAt:    nowISO,
				}
			}
		}

		// Persist any missed plot rows atomically inside BEGIN IMMEDIATE (skipped on read-only or edit-locked contexts)
		if canWriteCache && projDB != nil && cacheMisses > 0 {
			if err := upsertPlotClimateRowsAtomic(ctx, projDB, evaluatedSpecs, normByHash, refPeriod); err != nil {
				return nil, err
			}
		}

		// Assemble PlotClimateRow list & dual edatopic grids
		sourceSummary := make(map[string]int)
		plotRows := make([]PlotClimateRow, 0, len(evaluatedSpecs))
		for _, spec := range evaluatedSpecs {
			var norm cachedNormalRecord
			var ok bool
			if spec.hit {
				norm, ok = cacheByPlot[spec.ep.PlotNumber]
			} else {
				norm, ok = normByHash[spec.hash]
			}
			if !ok {
				continue
			}
			sourceSummary[norm.Source]++
			tr, err := EvaluateMinistryASMR(
				norm.CMD,
				norm.PPT05, norm.PPT06, norm.PPT07, norm.PPT08, norm.PPT09,
				norm.PPTAt, norm.PPTWt,
				spec.ep.Slope, spec.ep.Aspect,
				spec.ep.RSMR,
			)
			if err != nil {
				return nil, err
			}
			plotRows = append(plotRows, PlotClimateRow{
				PlotNumber:     spec.ep.PlotNumber,
				CoordElevHash:  spec.hash,
				RefPeriod:      refPeriod,
				Source:         norm.Source,
				Latitude:       *spec.ep.Latitude,
				Longitude:      *spec.ep.Longitude,
				Elevation:      *spec.ep.Elevation,
				BGC:            spec.ep.BGC,
				SiteUnit:       spec.ep.SiteUnit,
				SlopeGradient:  spec.ep.Slope,
				Aspect:         spec.ep.Aspect,
				RSMR:           spec.ep.RSMR,
				RSNR:           spec.ep.RSNR,
				MAT:            norm.MAT,
				MWMT:           norm.MWMT,
				MCMT:           norm.MCMT,
				MAP:            norm.MAP,
				MSP:            norm.MSP,
				PAS:            norm.PAS,
				CMD:            norm.CMD,
				PPT05:          norm.PPT05,
				PPT06:          norm.PPT06,
				PPT07:          norm.PPT07,
				PPT08:          norm.PPT08,
				PPT09:          norm.PPT09,
				PPTAt:          norm.PPTAt,
				PPTWt:          norm.PPTWt,
				DD5:            norm.DD5,
				NFFD:           norm.NFFD,
				MoistMonths:    tr.MoistMonths,
				DormantDeficit: tr.DormantDeficit,
				AspectFactor:   tr.AspectFactor,
				CMDTopo:        tr.CMDTopo,
				CMDSite:        tr.CMDSite,
				ASMR:           tr.ASMR,
				ComputedAt:     norm.ComputedAt,
			})
		}

		overallRel, overallAct := buildEdatopicMatrices(plotRows)

		groupMode := strings.ToLower(strings.TrimSpace(req.GroupBy))
		if groupMode == "" {
			if owner.Selection.SU != "" && owner.Selection.SU != "None" {
				groupMode = "site_unit"
			} else {
				groupMode = "bgc"
			}
		}

		grouped := make(map[string][]PlotClimateRow)
		for _, pr := range plotRows {
			key := pr.SiteUnit
			if groupMode == "bgc" {
				key = pr.BGC
			}
			if strings.TrimSpace(key) == "" {
				key = "Unassigned"
			}
			grouped[key] = append(grouped[key], pr)
		}

		keys := make([]string, 0, len(grouped))
		for k := range grouped {
			keys = append(keys, k)
		}
		sort.Strings(keys)

		unitSummaries := make([]DualUnitEdatopicSummary, 0, len(keys))
		for _, k := range keys {
			sub := grouped[k]
			relG, actG := buildEdatopicMatrices(sub)
			var matSum, mapSum, cmdSum float64
			var asmrSum, shiftSum float64
			asmrCnt, shiftCnt := 0, 0
			bgcSample, suSample := "", ""
			for _, r := range sub {
				matSum += r.MAT
				mapSum += r.MAP
				cmdSum += r.CMD
				if bgcSample == "" && r.BGC != "" {
					bgcSample = r.BGC
				}
				if suSample == "" && r.SiteUnit != "" {
					suSample = r.SiteUnit
				}
				if r.ASMR != nil {
					asmrSum += *r.ASMR
					asmrCnt++
					if rDig, ok := parseRSMRDigit(r.RSMR); ok {
						shiftSum += (*r.ASMR - float64(rDig))
						shiftCnt++
					}
				}
			}
			n := float64(len(sub))
			var meanAsmr, meanShift *float64
			if asmrCnt > 0 {
				v := math.Round((asmrSum/float64(asmrCnt))*100.0) / 100.0
				meanAsmr = &v
			}
			if shiftCnt > 0 {
				v := math.Round((shiftSum/float64(shiftCnt))*100.0) / 100.0
				meanShift = &v
			}
			unitSummaries = append(unitSummaries, DualUnitEdatopicSummary{
				GroupKey:     k,
				BGC:          bgcSample,
				SiteUnit:     suSample,
				PlotCount:    len(sub),
				MeanMAT:      math.Round((matSum/n)*100.0) / 100.0,
				MeanMAP:      math.Round((mapSum/n)*10.0) / 10.0,
				MeanCMD:      math.Round((cmdSum/n)*10.0) / 10.0,
				MeanASMR:     meanAsmr,
				MeanShift:    meanShift,
				RelativeGrid: relG,
				ActualGrid:   actG,
			})
		}

		return &ClimateEdatopicResult{
			ContextID:          contextID,
			Project:            owner.Selection.Project,
			ActiveSU:           owner.Selection.SU,
			RefPeriod:          refPeriod,
			TotalScopedPlots:   len(envPlots),
			CoordinatizedPlots: coordinatized,
			SkippedNoCoords:    skippedNoCoords,
			CacheHits:          cacheHits,
			CacheMisses:        cacheMisses,
			SourceSummary:      sourceSummary,
			OverallRelative:    overallRel,
			OverallActual:      overallAct,
			UnitSummaries:      unitSummaries,
			Plots:              plotRows,
		}, nil
	})
}
