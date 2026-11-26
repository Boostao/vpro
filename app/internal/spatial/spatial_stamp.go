package spatial

import (
	"context"
	"fmt"
	"math"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"

	"github.com/boostao/vpro/app/internal/vprocore"
)

func formatAuditBeforeAfter(val any) any {
	if val == nil {
		return nil
	}
	switch v := val.(type) {
	case string:
		return v
	case *string:
		if v == nil {
			return nil
		}
		return *v
	case int:
		return strconv.Itoa(v)
	case *int:
		if v == nil {
			return nil
		}
		return strconv.Itoa(*v)
	case float64:
		return strconv.FormatFloat(v, 'g', -1, 64)
	case *float64:
		if v == nil {
			return nil
		}
		return strconv.FormatFloat(*v, 'g', -1, 64)
	default:
		return fmt.Sprint(v)
	}
}

type spatialCellMutation struct {
	tableSuffix string // "Env" | "Admin"
	column      string
	beforeVal   any
	afterVal    any
}

type spatialPlotPlan struct {
	plotNumber string
	mutations  []spatialCellMutation
}

func planCoordinateMutations(r rawSpatialPlotRow, geod PlotGeodesyEvaluation, req ApplySpatialAttributesRequest) ([]spatialCellMutation, error) {
	var muts []spatialCellMutation
	if req.NormalizeLongitudeSign && geod.LongitudeSignFlipped && geod.NormalizedLon != nil && r.longitude != nil {
		muts = append(muts, spatialCellMutation{
			tableSuffix: "Env",
			column:      "Longitude",
			beforeVal:   *r.longitude,
			afterVal:    *geod.NormalizedLon,
		})
	}
	if req.SyncUTMFromLatLon && geod.ComputedUTMZone != nil && geod.ComputedUTMEasting != nil && geod.ComputedUTMNorthing != nil {
		zStr := strconv.Itoa(*geod.ComputedUTMZone)
		if err := sqlutil.ValidateUTF16Bound("UTMZone", zStr, 2); err != nil {
			return nil, err
		}
		eastRounded := math.Round(*geod.ComputedUTMEasting*10.0) / 10.0
		northRounded := math.Round(*geod.ComputedUTMNorthing*10.0) / 10.0
		allUTMBlank := (r.utmZone == nil || strings.TrimSpace(*r.utmZone) == "") && r.utmEasting == nil && r.utmNorthing == nil
		if !req.OnlyWhenBlank || allUTMBlank {
			var beforeZ, beforeE, beforeN any
			if r.utmZone != nil {
				beforeZ = *r.utmZone
			}
			if r.utmEasting != nil {
				beforeE = *r.utmEasting
			}
			if r.utmNorthing != nil {
				beforeN = *r.utmNorthing
			}
			if beforeZ != zStr {
				muts = append(muts, spatialCellMutation{"Env", "UTMZone", beforeZ, zStr})
			}
			if r.utmEasting == nil || math.Abs(*r.utmEasting-eastRounded) > 0.05 {
				muts = append(muts, spatialCellMutation{"Env", "UTMEasting", beforeE, eastRounded})
			}
			if r.utmNorthing == nil || math.Abs(*r.utmNorthing-northRounded) > 0.05 {
				muts = append(muts, spatialCellMutation{"Env", "UTMNorthing", beforeN, northRounded})
			}
		}
	}
	if req.SyncLatLonFromUTM && geod.UTMDerivedLat != nil && geod.UTMDerivedLon != nil {
		latRounded := math.Round(*geod.UTMDerivedLat*1e6) / 1e6
		lonRounded := math.Round(*geod.UTMDerivedLon*1e6) / 1e6
		bothDDBlank := r.latitude == nil && r.longitude == nil
		if !req.OnlyWhenBlank || bothDDBlank {
			var beforeLat, beforeLon any
			if r.latitude != nil {
				beforeLat = *r.latitude
			}
			if r.longitude != nil {
				beforeLon = *r.longitude
			}
			if r.latitude == nil || math.Abs(*r.latitude-latRounded) > 1e-6 {
				muts = append(muts, spatialCellMutation{"Env", "Latitude", beforeLat, latRounded})
			}
			if r.longitude == nil || math.Abs(*r.longitude-lonRounded) > 1e-6 {
				muts = append(muts, spatialCellMutation{"Env", "Longitude", beforeLon, lonRounded})
			}
		}
	}
	return muts, nil
}

func appendSuggestedTextMutation(
	muts *[]spatialCellMutation,
	tableSuffix, column, currentVal, suggestedVal string,
	maxUTF16 int,
	onlyWhenBlank bool,
) error {
	if suggestedVal == "" {
		return nil
	}
	if err := sqlutil.ValidateUTF16Bound(column, suggestedVal, maxUTF16); err != nil {
		return err
	}
	if onlyWhenBlank && strings.TrimSpace(currentVal) != "" {
		return nil
	}
	if currentVal == suggestedVal {
		return nil
	}
	var before any
	if currentVal != "" {
		before = currentVal
	}
	*muts = append(*muts, spatialCellMutation{tableSuffix, column, before, suggestedVal})
	return nil
}

func planSuggestedAttributeMutations(r rawSpatialPlotRow, sug *SpatialAttributeSuggestion, req ApplySpatialAttributesRequest) ([]spatialCellMutation, error) {
	if sug == nil {
		return nil, nil
	}
	var muts []spatialCellMutation
	if req.StampGISBGC && sug.GISBGC != "" {
		if err := sqlutil.ValidateUTF16Bound("GIS_BGC", sug.GISBGC, 255); err != nil {
			return nil, err
		}
		if !req.OnlyWhenBlank || strings.TrimSpace(r.gisBGC) == "" {
			var beforeGIS any
			if r.gisBGC != "" {
				beforeGIS = r.gisBGC
			}
			if r.gisBGC != sug.GISBGC {
				muts = append(muts, spatialCellMutation{"Admin", "GIS_BGC", beforeGIS, sug.GISBGC})
			}
			var beforeVer any
			if r.gisBGCVer != nil {
				beforeVer = *r.gisBGCVer
			}
			if r.gisBGCVer == nil || *r.gisBGCVer != CurrentBECGISVersion {
				muts = append(muts, spatialCellMutation{"Admin", "GIS_BGC_VER", beforeVer, CurrentBECGISVersion})
			}
		}
	}
	if req.StampAdminFields {
		for _, field := range []struct {
			suffix  string
			col     string
			current string
			sugVal  string
			maxU16  int
		}{
			{"Env", "Ecosection", r.ecosection, sug.Ecosection, 3},
			{"Env", "FSRegionDistrict", r.fsRegionDistrict, sug.FSRegionDistrict, 7},
			{"Env", "NtsMapSheet", r.ntsMapSheet, sug.NtsMapSheet, 8},
			{"Admin", "ProvinceStateTerritory", r.province, sug.ProvinceStateTerritory, 255},
		} {
			if err := appendSuggestedTextMutation(&muts, field.suffix, field.col, field.current, field.sugVal, field.maxU16, req.OnlyWhenBlank); err != nil {
				return nil, err
			}
		}
	}
	return muts, nil
}

func buildSpatialPlotPlans(ctx context.Context, targets []rawSpatialPlotRow, req ApplySpatialAttributesRequest, attr *PMTilesAttributor) ([]spatialPlotPlan, error) {
	var plans []spatialPlotPlan
	for _, r := range targets {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		geod := EvaluatePlotGeodesy(PlotGeodesyInput{
			Latitude:         r.latitude,
			Longitude:        r.longitude,
			UTMZone:          r.utmZone,
			UTMEasting:       r.utmEasting,
			UTMNorthing:      r.utmNorthing,
			LocationAccuracy: r.locationAccuracy,
		})
		var sug *SpatialAttributeSuggestion
		if geod.NormalizedLat != nil && geod.NormalizedLon != nil {
			sug, _ = attr.SuggestSpatialAttributes(*geod.NormalizedLat, *geod.NormalizedLon)
		} else if geod.UTMDerivedLat != nil && geod.UTMDerivedLon != nil {
			sug, _ = attr.SuggestSpatialAttributes(*geod.UTMDerivedLat, *geod.UTMDerivedLon)
		}
		coordMuts, err := planCoordinateMutations(r, geod, req)
		if err != nil {
			return nil, err
		}
		attrMuts, err := planSuggestedAttributeMutations(r, sug, req)
		if err != nil {
			return nil, err
		}
		muts := append(coordMuts, attrMuts...)
		if len(muts) > 0 {
			plans = append(plans, spatialPlotPlan{plotNumber: r.plotNumber, mutations: muts})
		}
	}
	return plans, nil
}

func ensureSingleAdminRowForSpatialStamp(ctx context.Context, wtx *vprocore.WriteTx, qAdmin, plotNumber string) error {
	var adminCnt int
	if err := wtx.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM main.`+qAdmin+` WHERE typeof("Plot")='text' AND CAST("Plot" AS BLOB)=CAST(? AS BLOB)`,
		plotNumber).Scan(&adminCnt); err != nil {
		return err
	}
	if adminCnt == 0 {
		_, err := wtx.ExecContext(ctx, `INSERT INTO main.`+qAdmin+` ("Plot") VALUES (?)`, plotNumber)
		return err
	}
	if adminCnt > 1 {
		return fmt.Errorf("plot %q has duplicate Admin rows", plotNumber)
	}
	return nil
}

func executeSpatialPlotPlans(
	ctx context.Context,
	wtx *vprocore.WriteTx,
	currentUser string,
	plans []spatialPlotPlan,
	res *ApplySpatialAttributesResult,
) error {
	project := wtx.Project
	qEnv := vprocore.QuoteHeaderIdentifier(project + "_Env")
	qAdmin := vprocore.QuoteHeaderIdentifier(project + "_Admin")
	now := time.Now().Format("2006-01-02 15:04:05")

	auditStmt, err := vprocore.PrepareProjectAuditStmt(ctx, wtx, "main", project)
	if err != nil {
		return err
	}
	defer auditStmt.Close()

	for _, plan := range plans {
		if err := ctx.Err(); err != nil {
			return err
		}
		for _, m := range plan.mutations {
			if m.tableSuffix == "Admin" {
				if err := ensureSingleAdminRowForSpatialStamp(ctx, wtx, qAdmin, plan.plotNumber); err != nil {
					return err
				}
				break
			}
		}
		plotCopy := plan.plotNumber
		for _, m := range plan.mutations {
			qTarget, pkCol := qEnv, `"PlotNumber"`
			if m.tableSuffix == "Admin" {
				qTarget, pkCol = qAdmin, `"Plot"`
			}
			qCol := vprocore.QuoteHeaderIdentifier(m.column)
			execRes, err := wtx.ExecContext(ctx,
				`UPDATE main.`+qTarget+` SET `+qCol+` = ? WHERE typeof(`+pkCol+`)='text' AND CAST(`+pkCol+` AS BLOB)=CAST(? AS BLOB)`,
				m.afterVal, plan.plotNumber)
			if err != nil {
				return fmt.Errorf("update %s.%s for plot %s: %w", m.tableSuffix, m.column, plan.plotNumber, err)
			}
			affected, _ := execRes.RowsAffected()
			if affected != 1 {
				return fmt.Errorf("expected 1 updated row in %s for plot %q, got %d", m.tableSuffix, plan.plotNumber, affected)
			}
			colCopy := m.column
			if _, err := vprocore.ExecPreparedAudit(ctx, auditStmt, vprocore.AuditWriteEntry{
				Project:    project,
				User:       currentUser,
				PlotNumber: &plotCopy,
				Table:      "_" + m.tableSuffix,
				EditField:  &colCopy,
				EditWhen:   now,
				BeforeEdit: formatAuditBeforeAfter(m.beforeVal),
				AfterEdit:  formatAuditBeforeAfter(m.afterVal),
			}); err != nil {
				return fmt.Errorf("insert audit row for plot %s: %w", plan.plotNumber, err)
			}
			res.UpdatedCells++
			res.AuditRows++
		}
		res.UpdatedPlots++
	}
	return nil
}

// ApplySpatialAttributes transactionally stamps GIS_BGC (v13), Ecosection, FSRegionDistrict, NtsMapSheet,
// and/or NAD83 UTM <-> LatLon coordinates inside BEGIN IMMEDIATE with mandatory <Project>_Audit rows.
func ApplySpatialAttributes(ctx context.Context, contexts *vprocore.ContextService, contextID string, req ApplySpatialAttributesRequest, attributors ...*PMTilesAttributor) (*ApplySpatialAttributesResult, error) {
	if ctx == nil {
		return nil, fmt.Errorf("spatial stamp requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, fmt.Errorf("spatial context service is unavailable")
	}
	if !req.StampGISBGC && !req.StampAdminFields && !req.NormalizeLongitudeSign && !req.SyncUTMFromLatLon && !req.SyncLatLonFromUTM {
		return nil, fmt.Errorf("at least one spatial attribution action must be enabled")
	}
	attr := getDefaultPMTilesAttributor()
	if len(attributors) > 0 && attributors[0] != nil {
		attr = attributors[0]
	}

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*ApplySpatialAttributesResult, error) {
		if err := plots.CheckEditLock(); err != nil {
			return nil, err
		}
		owner := plots.Projects.Sqlite
		project := owner.Selection.Project
		plots.Mu.RLock()
		currentUser := strings.TrimSpace(plots.CurrentUser)
		plots.Mu.RUnlock()
		if currentUser == "" {
			currentUser = "VProUser"
		}

		rawRows, err := queryScopedSpatialPlotRows(ctx, owner)
		if err != nil {
			return nil, err
		}
		selectedSet := make(map[string]bool, len(req.PlotNumbers))
		for _, p := range req.PlotNumbers {
			if p == "" || !utf8.ValidString(p) || strings.ContainsRune(p, 0) {
				return nil, fmt.Errorf("invalid plot number %q", p)
			}
			selectedSet[p] = true
		}
		if len(selectedSet) == 0 && !req.AllScopedPlots {
			return nil, fmt.Errorf("specify plotNumbers or set allScopedPlots=true")
		}

		var targets []rawSpatialPlotRow
		for _, r := range rawRows {
			if req.AllScopedPlots || selectedSet[r.plotNumber] {
				targets = append(targets, r)
			}
		}
		if len(targets) == 0 {
			return &ApplySpatialAttributesResult{ContextID: contextID, Project: project}, nil
		}

		plans, err := buildSpatialPlotPlans(ctx, targets, req, attr)
		if err != nil {
			return nil, err
		}
		if len(plans) == 0 {
			return &ApplySpatialAttributesResult{ContextID: contextID, Project: project}, nil
		}

		res := &ApplySpatialAttributesResult{ContextID: contextID, Project: project}
		if err := owner.WithImmediateRoleWriteTx(ctx, "project", owner.ValidateMetadataWriterFiles, func(wtx *vprocore.WriteTx) error {
			return executeSpatialPlotPlans(ctx, wtx, currentUser, plans, res)
		}); err != nil {
			return nil, err
		}
		return res, nil
	})
}
