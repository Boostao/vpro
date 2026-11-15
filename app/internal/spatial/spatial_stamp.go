package spatial

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"github.com/boostao/vpro/app/internal/vprocore"
	"math"
	"strconv"
	"strings"
	"time"
	"unicode/utf16"
	"unicode/utf8"
)

func validateUTF16FieldWidth(field, val string, maxUnits int) error {
	if !utf8.ValidString(val) || strings.ContainsRune(val, 0) {
		return fmt.Errorf("%s contains invalid UTF-8 or NUL bytes", field)
	}
	if maxUnits > 0 && len(utf16.Encode([]rune(val))) > maxUnits {
		return fmt.Errorf("%s value %q exceeds %d UTF-16 code units", field, val, maxUnits)
	}
	return nil
}

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

// ApplySpatialAttributes transactionally stamps GIS_BGC (v13), Ecosection, FSRegionDistrict, NtsMapSheet,
// and/or NAD83 UTM <-> LatLon coordinates inside BEGIN IMMEDIATE with mandatory <Project>_Audit rows.
func ApplySpatialAttributes(ctx context.Context, contexts *vprocore.ContextService, contextID string, req ApplySpatialAttributesRequest, attributors ...*PMTilesAttributor) (*ApplySpatialAttributesResult, error) {
	if ctx == nil {
		return nil, errors.New("spatial stamp requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("spatial context service is unavailable")
	}
	if !req.StampGISBGC && !req.StampAdminFields && !req.NormalizeLongitudeSign && !req.SyncUTMFromLatLon && !req.SyncLatLonFromUTM {
		return nil, errors.New("at least one spatial attribution action must be enabled")
	}
	attr := getDefaultPMTilesAttributor()
	if len(attributors) > 0 && attributors[0] != nil {
		attr = attributors[0]
	}

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*ApplySpatialAttributesResult, error) {
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
			return nil, errors.New("specify plotNumbers or set allScopedPlots=true")
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

		type cellMutation struct {
			tableSuffix string // "Env" | "Admin"
			column      string
			beforeVal   any
			afterVal    any
		}
		type plotPlan struct {
			plotNumber string
			mutations  []cellMutation
		}
		var plans []plotPlan

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

			var muts []cellMutation

			if req.NormalizeLongitudeSign && geod.LongitudeSignFlipped && geod.NormalizedLon != nil && r.longitude != nil {
				muts = append(muts, cellMutation{
					tableSuffix: "Env",
					column:      "Longitude",
					beforeVal:   *r.longitude,
					afterVal:    *geod.NormalizedLon,
				})
			}

			if req.SyncUTMFromLatLon && geod.ComputedUTMZone != nil && geod.ComputedUTMEasting != nil && geod.ComputedUTMNorthing != nil {
				zStr := strconv.Itoa(*geod.ComputedUTMZone)
				if err := validateUTF16FieldWidth("UTMZone", zStr, 2); err != nil {
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
						muts = append(muts, cellMutation{"Env", "UTMZone", beforeZ, zStr})
					}
					if r.utmEasting == nil || math.Abs(*r.utmEasting-eastRounded) > 0.05 {
						muts = append(muts, cellMutation{"Env", "UTMEasting", beforeE, eastRounded})
					}
					if r.utmNorthing == nil || math.Abs(*r.utmNorthing-northRounded) > 0.05 {
						muts = append(muts, cellMutation{"Env", "UTMNorthing", beforeN, northRounded})
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
						muts = append(muts, cellMutation{"Env", "Latitude", beforeLat, latRounded})
					}
					if r.longitude == nil || math.Abs(*r.longitude-lonRounded) > 1e-6 {
						muts = append(muts, cellMutation{"Env", "Longitude", beforeLon, lonRounded})
					}
				}
			}

			if req.StampGISBGC && sug != nil && sug.GISBGC != "" {
				if err := validateUTF16FieldWidth("GIS_BGC", sug.GISBGC, 255); err != nil {
					return nil, err
				}
				if !req.OnlyWhenBlank || strings.TrimSpace(r.gisBGC) == "" {
					var beforeGIS any
					if r.gisBGC != "" {
						beforeGIS = r.gisBGC
					}
					if r.gisBGC != sug.GISBGC {
						muts = append(muts, cellMutation{"Admin", "GIS_BGC", beforeGIS, sug.GISBGC})
					}
					var beforeVer any
					if r.gisBGCVer != nil {
						beforeVer = *r.gisBGCVer
					}
					if r.gisBGCVer == nil || *r.gisBGCVer != CurrentBECGISVersion {
						muts = append(muts, cellMutation{"Admin", "GIS_BGC_VER", beforeVer, CurrentBECGISVersion})
					}
				}
			}

			if req.StampAdminFields && sug != nil {
				if sug.Ecosection != "" {
					if err := validateUTF16FieldWidth("Ecosection", sug.Ecosection, 3); err != nil {
						return nil, err
					}
					if !req.OnlyWhenBlank || strings.TrimSpace(r.ecosection) == "" {
						var before any
						if r.ecosection != "" {
							before = r.ecosection
						}
						if r.ecosection != sug.Ecosection {
							muts = append(muts, cellMutation{"Env", "Ecosection", before, sug.Ecosection})
						}
					}
				}
				if sug.FSRegionDistrict != "" {
					if err := validateUTF16FieldWidth("FSRegionDistrict", sug.FSRegionDistrict, 7); err != nil {
						return nil, err
					}
					if !req.OnlyWhenBlank || strings.TrimSpace(r.fsRegionDistrict) == "" {
						var before any
						if r.fsRegionDistrict != "" {
							before = r.fsRegionDistrict
						}
						if r.fsRegionDistrict != sug.FSRegionDistrict {
							muts = append(muts, cellMutation{"Env", "FSRegionDistrict", before, sug.FSRegionDistrict})
						}
					}
				}
				if sug.NtsMapSheet != "" {
					if err := validateUTF16FieldWidth("NtsMapSheet", sug.NtsMapSheet, 8); err != nil {
						return nil, err
					}
					if !req.OnlyWhenBlank || strings.TrimSpace(r.ntsMapSheet) == "" {
						var before any
						if r.ntsMapSheet != "" {
							before = r.ntsMapSheet
						}
						if r.ntsMapSheet != sug.NtsMapSheet {
							muts = append(muts, cellMutation{"Env", "NtsMapSheet", before, sug.NtsMapSheet})
						}
					}
				}
				if sug.ProvinceStateTerritory != "" {
					if err := validateUTF16FieldWidth("ProvinceStateTerritory", sug.ProvinceStateTerritory, 255); err != nil {
						return nil, err
					}
					if !req.OnlyWhenBlank || strings.TrimSpace(r.province) == "" {
						var before any
						if r.province != "" {
							before = r.province
						}
						if r.province != sug.ProvinceStateTerritory {
							muts = append(muts, cellMutation{"Admin", "ProvinceStateTerritory", before, sug.ProvinceStateTerritory})
						}
					}
				}
			}

			if len(muts) > 0 {
				plans = append(plans, plotPlan{plotNumber: r.plotNumber, mutations: muts})
			}
		}

		if len(plans) == 0 {
			return &ApplySpatialAttributesResult{ContextID: contextID, Project: project}, nil
		}

		res := &ApplySpatialAttributesResult{ContextID: contextID, Project: project}
		err = owner.WithMetadataWriter(ctx, func(conn *sql.Conn) (txErr error) {
			tx, bErr := conn.BeginTx(ctx, nil)
			if bErr != nil {
				return bErr
			}
			defer func() {
				if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
					txErr = errors.Join(txErr, rb)
				}
			}()

			qEnv := vprocore.QuoteHeaderIdentifier(project + "_Env")
			qAdmin := vprocore.QuoteHeaderIdentifier(project + "_Admin")
			qAudit := vprocore.QuoteHeaderIdentifier(project + "_Audit")
			now := time.Now().Format("2006-01-02 15:04:05")

			auditStmt, aErr := tx.PrepareContext(ctx,
				`INSERT INTO main.`+qAudit+` ("Project","User","PlotNumber","Table","EditField","EditWhen","BeforeEdit","AfterEdit","Restore","Flag") VALUES (?,?,?,?,?,?,?,?,0,0)`)
			if aErr != nil {
				return aErr
			}
			defer auditStmt.Close()

			for _, plan := range plans {
				if err := ctx.Err(); err != nil {
					return err
				}
				// Ensure 1:1 Admin row exists for this literal plot before updating Admin columns
				var hasAdminMuts bool
				for _, m := range plan.mutations {
					if m.tableSuffix == "Admin" {
						hasAdminMuts = true
						break
					}
				}
				if hasAdminMuts {
					var adminCnt int
					if err := tx.QueryRowContext(ctx,
						`SELECT COUNT(*) FROM main.`+qAdmin+` WHERE typeof("Plot")='text' AND CAST("Plot" AS BLOB)=CAST(? AS BLOB)`,
						plan.plotNumber).Scan(&adminCnt); err != nil {
						return err
					}
					if adminCnt == 0 {
						if _, err := tx.ExecContext(ctx, `INSERT INTO main.`+qAdmin+` ("Plot") VALUES (?)`, plan.plotNumber); err != nil {
							return err
						}
					} else if adminCnt > 1 {
						return fmt.Errorf("plot %q has duplicate Admin rows", plan.plotNumber)
					}
				}

				for _, m := range plan.mutations {
					qTarget := qEnv
					pkCol := `"PlotNumber"`
					if m.tableSuffix == "Admin" {
						qTarget = qAdmin
						pkCol = `"Plot"`
					}
					qCol := vprocore.QuoteHeaderIdentifier(m.column)
					execRes, err := tx.ExecContext(ctx,
						`UPDATE main.`+qTarget+` SET `+qCol+` = ? WHERE typeof(`+pkCol+`)='text' AND CAST(`+pkCol+` AS BLOB)=CAST(? AS BLOB)`,
						m.afterVal, plan.plotNumber)
					if err != nil {
						return fmt.Errorf("update %s.%s for plot %s: %w", m.tableSuffix, m.column, plan.plotNumber, err)
					}
					affected, _ := execRes.RowsAffected()
					if affected != 1 {
						return fmt.Errorf("expected 1 updated row in %s for plot %q, got %d", m.tableSuffix, plan.plotNumber, affected)
					}
					if _, err := auditStmt.ExecContext(ctx,
						project,
						currentUser,
						plan.plotNumber,
						"_"+m.tableSuffix,
						m.column,
						now,
						formatAuditBeforeAfter(m.beforeVal),
						formatAuditBeforeAfter(m.afterVal),
					); err != nil {
						return fmt.Errorf("insert audit row for plot %s: %w", plan.plotNumber, err)
					}
					res.UpdatedCells++
					res.AuditRows++
				}
				res.UpdatedPlots++
			}

			if err := ctx.Err(); err != nil {
				return err
			}
			return tx.Commit()
		})
		if err != nil {
			return nil, err
		}
		return res, nil
	})
}
