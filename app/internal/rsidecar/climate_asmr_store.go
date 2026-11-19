package rsidecar

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"math"
	"strings"
	"time"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type scopedEnvPlot struct {
	PlotNumber string
	Zone       string
	SubZone    string
	BGC        string
	SiteUnit   string
	Latitude   *float64
	Longitude  *float64
	Elevation  *float64
	Slope      *float64
	Aspect     *float64
	RSMR       string
	RSNR       string
}

func readScopedEnvPlots(
	ctx context.Context,
	owner *vprocore.SqliteContext,
	useActiveSU bool,
	bgcFilter string,
	siteUnitFilter string,
	explicitPlots []string,
) ([]scopedEnvPlot, error) {
	unlock, err := owner.AcquireMutex(ctx)
	if err != nil {
		return nil, err
	}
	defer unlock()
	if !owner.IsOpen() {
		return nil, errors.New("project context is closed")
	}

	tx, err := owner.BeginReadSnapshot(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	envTable := vprocore.QuoteHeaderIdentifier(owner.Selection.Project + "_Env")
	suActive := owner.Selection.SU != "" && owner.Selection.SU != "None"

	suMap := make(map[string]string)
	if suActive {
		suSchema := "main"
		if _, ok := owner.Attachments["su"]; ok {
			suSchema = "su"
		} else if owner.Selection.SUPath != "" && !vprocore.SameDesktopPath(owner.Selection.SUPath, owner.Selection.ProjectPath) {
			suSchema = "su"
		}
		suTable := vprocore.QuoteHeaderIdentifier(owner.Selection.SU + "_SU")
		// Check whether SU table exists in suSchema or main
		var suExists int
		_ = tx.QueryRowContext(ctx, fmt.Sprintf(`SELECT COUNT(*) FROM %s.sqlite_master WHERE type='table' AND name = ? COLLATE NOCASE`, suSchema), owner.Selection.SU+"_SU").Scan(&suExists)
		if suExists == 0 && suSchema != "main" {
			_ = tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM main.sqlite_master WHERE type='table' AND name = ? COLLATE NOCASE`, owner.Selection.SU+"_SU").Scan(&suExists)
			if suExists > 0 {
				suSchema = "main"
			}
		}
		if suExists > 0 {
			sRows, qErr := tx.QueryContext(ctx, fmt.Sprintf(
				`SELECT CAST("PlotNumber" AS TEXT), TRIM(COALESCE(CAST("SiteUnit" AS TEXT), '')) FROM %s.%s WHERE typeof("PlotNumber")='text'`,
				suSchema, suTable,
			))
			if qErr == nil {
				func() {
					defer sRows.Close()

					for sRows.Next() {
						var p, u string
						if err := sRows.Scan(&p, &u); err == nil {
							suMap[p] = u
						}
					}

				}()
			}
		}
	}

	// Check whether Admin table has GIS_BGC for plots missing field Zone/SubZone
	gisMap := make(map[string]string)
	adminTableName := owner.Selection.Project + "_Admin"
	var adminExists int
	_ = tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM project.sqlite_master WHERE type='table' AND name = ? COLLATE NOCASE`, adminTableName).Scan(&adminExists)
	envSchema := "project"
	if adminExists == 0 {
		var mainEnvExists int
		_ = tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM main.sqlite_master WHERE type='table' AND name = ? COLLATE NOCASE`, owner.Selection.Project+"_Env").Scan(&mainEnvExists)
		if mainEnvExists > 0 {
			envSchema = "main"
			_ = tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM main.sqlite_master WHERE type='table' AND name = ? COLLATE NOCASE`, adminTableName).Scan(&adminExists)
		}
	}
	if adminExists > 0 {
		aRows, aErr := tx.QueryContext(ctx, fmt.Sprintf(
			`SELECT CAST("Plot" AS TEXT), TRIM(COALESCE(CAST("GIS_BGC" AS TEXT), '')) FROM %s.%s WHERE typeof("Plot")='text'`,
			envSchema, vprocore.QuoteHeaderIdentifier(adminTableName),
		))
		if aErr == nil {
			func() {
				defer aRows.Close()

				for aRows.Next() {
					var p, g string
					if err := aRows.Scan(&p, &g); err == nil && g != "" {
						gisMap[p] = strings.ReplaceAll(g, " ", "")
					}
				}

			}()
		}
	}

	allowedSet := make(map[string]bool, len(explicitPlots))
	for _, p := range explicitPlots {
		if p != "" {
			allowedSet[p] = true
		}
	}
	bgcFilterClean := strings.ToUpper(strings.ReplaceAll(strings.TrimSpace(bgcFilter), " ", ""))
	unitFilterClean := strings.ToUpper(strings.TrimSpace(siteUnitFilter))

	query := fmt.Sprintf(
		`SELECT CAST("PlotNumber" AS TEXT),
		        TRIM(COALESCE(CAST("Zone" AS TEXT), '')),
		        TRIM(COALESCE(CAST("SubZone" AS TEXT), '')),
		        TRIM(COALESCE(CAST("SiteSeries" AS TEXT), '')),
		        CAST("Latitude" AS REAL),
		        CAST("Longitude" AS REAL),
		        CAST("Elevation" AS REAL),
		        CAST("SlopeGradient" AS REAL),
		        CAST("Aspect" AS REAL),
		        TRIM(COALESCE(CAST("MoistureRegime" AS TEXT), '')),
		        TRIM(COALESCE(CAST("NutrientRegime" AS TEXT), ''))
		   FROM %s.%s
		  WHERE typeof("PlotNumber")='text'
		  ORDER BY "PlotNumber" ASC`,
		envSchema, envTable,
	)
	rows, err := tx.QueryContext(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []scopedEnvPlot
	for rows.Next() {
		var plotNum, zone, subZone, siteSeries, rsmr, rsnr string
		var lat, lon, elev, slope, aspect sql.NullFloat64
		if err := rows.Scan(&plotNum, &zone, &subZone, &siteSeries, &lat, &lon, &elev, &slope, &aspect, &rsmr, &rsnr); err != nil {
			return nil, err
		}
		if len(allowedSet) > 0 && !allowedSet[plotNum] {
			continue
		}
		suUnit, inSU := suMap[plotNum]
		if useActiveSU && suActive && !inSU {
			continue
		}

		bgc := strings.ReplaceAll(zone+subZone, " ", "")
		if bgc == "" {
			bgc = gisMap[plotNum]
		}
		effectiveUnit := suUnit
		if effectiveUnit == "" && bgc != "" && siteSeries != "" {
			effectiveUnit = bgc + "/" + siteSeries
		} else if effectiveUnit == "" && bgc != "" {
			effectiveUnit = bgc
		}

		if bgcFilterClean != "" {
			bgcUpper := strings.ToUpper(bgc)
			if bgcUpper != bgcFilterClean && !strings.HasPrefix(bgcUpper, bgcFilterClean) {
				continue
			}
		}
		if unitFilterClean != "" && strings.ToUpper(strings.TrimSpace(effectiveUnit)) != unitFilterClean {
			continue
		}

		item := scopedEnvPlot{
			PlotNumber: plotNum,
			Zone:       zone,
			SubZone:    subZone,
			BGC:        bgc,
			SiteUnit:   effectiveUnit,
			RSMR:       rsmr,
			RSNR:       rsnr,
		}
		if lat.Valid && !math.IsNaN(lat.Float64) && math.Abs(lat.Float64) <= 90.0 && lat.Float64 != 0 {
			v := lat.Float64
			item.Latitude = &v
		}
		if lon.Valid && !math.IsNaN(lon.Float64) && math.Abs(lon.Float64) <= 180.0 && lon.Float64 != 0 {
			v := NormalizeBCWesternLongitude(lon.Float64)
			item.Longitude = &v
		}
		if elev.Valid && !math.IsNaN(elev.Float64) && elev.Float64 >= -100.0 && elev.Float64 <= 6000.0 {
			v := elev.Float64
			item.Elevation = &v
		}
		if slope.Valid && !math.IsNaN(slope.Float64) {
			v := slope.Float64
			item.Slope = &v
		}
		if aspect.Valid && !math.IsNaN(aspect.Float64) {
			v := aspect.Float64
			item.Aspect = &v
		}
		out = append(out, item)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	return out, tx.Commit()
}

type cachedNormalRecord struct {
	PlotNumber    string
	CoordElevHash string
	RefPeriod     string
	Source        string
	MAT           float64
	MWMT          float64
	MCMT          float64
	MAP           float64
	MSP           float64
	PAS           float64
	CMD           float64
	PPT05         float64
	PPT06         float64
	PPT07         float64
	PPT08         float64
	PPT09         float64
	PPTAt         float64
	PPTWt         float64
	DD5           float64
	NFFD          float64
	ComputedAt    string
}

func readExistingPlotClimateCache(ctx context.Context, db *sql.DB) (map[string]cachedNormalRecord, error) {
	out := make(map[string]cachedNormalRecord)
	var exists int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM main.sqlite_master WHERE type='table' AND name = ?`, PlotClimateTableName).Scan(&exists); err != nil {
		return nil, err
	}
	if exists == 0 {
		return out, nil
	}
	rows, err := db.QueryContext(ctx, `
		SELECT CAST("PlotNumber" AS TEXT), "CoordElevHash", "RefPeriod", "Source",
		       COALESCE("MAT",0), COALESCE("MWMT",0), COALESCE("MCMT",0), COALESCE("MAP",0),
		       COALESCE("MSP",0), COALESCE("PAS",0), COALESCE("CMD",0),
		       COALESCE("PPT_05",0), COALESCE("PPT_06",0), COALESCE("PPT_07",0), COALESCE("PPT_08",0), COALESCE("PPT_09",0),
		       COALESCE("PPT_at",0), COALESCE("PPT_wt",0), COALESCE("DD5",0), COALESCE("NFFD",0), "ComputedAt"
		  FROM main."__VPRO_PlotClimate"
		 WHERE typeof("PlotNumber")='text'
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var r cachedNormalRecord
		if err := rows.Scan(
			&r.PlotNumber, &r.CoordElevHash, &r.RefPeriod, &r.Source,
			&r.MAT, &r.MWMT, &r.MCMT, &r.MAP, &r.MSP, &r.PAS, &r.CMD,
			&r.PPT05, &r.PPT06, &r.PPT07, &r.PPT08, &r.PPT09,
			&r.PPTAt, &r.PPTWt, &r.DD5, &r.NFFD, &r.ComputedAt,
		); err != nil {
			return nil, err
		}
		out[r.PlotNumber] = r
	}
	return out, rows.Err()
}

func readExistingPlotClimateCacheReadOnly(ctx context.Context, owner *vprocore.SqliteContext) (map[string]cachedNormalRecord, error) {
	unlock, err := owner.AcquireMutex(ctx)
	if err != nil {
		return nil, err
	}
	projectPath := owner.Selection.ProjectPath
	unlock()

	roDB, err := sqlutil.OpenReadOnlyContext(ctx, projectPath)
	if err != nil {
		return nil, err
	}
	defer roDB.Close()
	return readExistingPlotClimateCache(ctx, roDB)
}

type plotClimateSpec struct {
	ep   scopedEnvPlot
	hash string
	hit  bool
}

func upsertPlotClimateRowsAtomic(
	ctx context.Context,
	db *sql.DB,
	specs []plotClimateSpec,
	normByHash map[string]cachedNormalRecord,
	refPeriod string,
) error {
	conn, err := db.Conn(ctx)
	if err != nil {
		return err
	}
	defer conn.Close()

	if _, err := conn.ExecContext(ctx, "BEGIN IMMEDIATE"); err != nil {
		return fmt.Errorf("begin immediate transaction for __VPRO_PlotClimate: %w", err)
	}
	committed := false
	defer func() {
		if !committed {
			_, _ = conn.ExecContext(context.WithoutCancel(ctx), "ROLLBACK")
		}
	}()

	if _, err := conn.ExecContext(ctx, plotClimateDDL); err != nil {
		return err
	}

	nowISO := time.Now().UTC().Format(time.RFC3339)
	for _, s := range specs {
		if s.hit {
			continue
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		norm, ok := normByHash[s.hash]
		if !ok {
			continue
		}
		compAt := norm.ComputedAt
		if compAt == "" {
			compAt = nowISO
		}

		// Literal PlotNumber check to prevent SQLite numeric affinity coercion on leading-zero plots
		var existing int
		if err := conn.QueryRowContext(
			ctx,
			`SELECT COUNT(*) FROM main."__VPRO_PlotClimate" WHERE typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB)`,
			s.ep.PlotNumber,
		).Scan(&existing); err != nil {
			return err
		}
		if existing > 0 {
			_, err = conn.ExecContext(
				ctx,
				`UPDATE main."__VPRO_PlotClimate"
				    SET "CoordElevHash" = ?, "RefPeriod" = ?, "Source" = ?,
				        "MAT" = ?, "MWMT" = ?, "MCMT" = ?, "MAP" = ?, "MSP" = ?, "PAS" = ?, "CMD" = ?,
				        "PPT_05" = ?, "PPT_06" = ?, "PPT_07" = ?, "PPT_08" = ?, "PPT_09" = ?,
				        "PPT_at" = ?, "PPT_wt" = ?, "DD5" = ?, "NFFD" = ?, "ComputedAt" = ?
				  WHERE typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB)`,
				s.hash, refPeriod, norm.Source,
				norm.MAT, norm.MWMT, norm.MCMT, norm.MAP, norm.MSP, norm.PAS, norm.CMD,
				norm.PPT05, norm.PPT06, norm.PPT07, norm.PPT08, norm.PPT09,
				norm.PPTAt, norm.PPTWt, norm.DD5, norm.NFFD, compAt,
				s.ep.PlotNumber,
			)
		} else {
			_, err = conn.ExecContext(
				ctx,
				`INSERT INTO main."__VPRO_PlotClimate" (
					"PlotNumber", "CoordElevHash", "RefPeriod", "Source",
					"MAT", "MWMT", "MCMT", "MAP", "MSP", "PAS", "CMD",
					"PPT_05", "PPT_06", "PPT_07", "PPT_08", "PPT_09",
					"PPT_at", "PPT_wt", "DD5", "NFFD", "ComputedAt"
				) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
				s.ep.PlotNumber, s.hash, refPeriod, norm.Source,
				norm.MAT, norm.MWMT, norm.MCMT, norm.MAP, norm.MSP, norm.PAS, norm.CMD,
				norm.PPT05, norm.PPT06, norm.PPT07, norm.PPT08, norm.PPT09,
				norm.PPTAt, norm.PPTWt, norm.DD5, norm.NFFD, compAt,
			)
		}
		if err != nil {
			return err
		}
	}

	if err := ctx.Err(); err != nil {
		return err
	}
	if _, err := conn.ExecContext(ctx, "COMMIT"); err != nil {
		return err
	}
	committed = true
	return nil
}
