package interchange

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"

	"github.com/boostao/vpro/app/internal/vprocore"
)

func populateGeoPackageTx(
	ctx context.Context,
	tx *sql.Tx,
	targetSRSID int32,
	crs string,
	request GeoPackageExportRequest,
	suByPlot map[string]string,
	envCols []gpkgColSpec,
	envRows [][]any,
	adminCols []gpkgColSpec,
	adminRows [][]any,
	vegObs []longVegObservation,
	humusCols []gpkgColSpec,
	humusRows [][]any,
	mineralCols []gpkgColSpec,
	mineralRows [][]any,
) (GeoPackageExportOutcome, error) {
	outcome := GeoPackageExportOutcome{
		CRS:             crs,
		SRSID:           targetSRSID,
		AttributeTables: []string{},
	}

	// 1. OGC GeoPackage 1.3 system metadata tables
	if _, err := tx.ExecContext(ctx, `
		CREATE TABLE gpkg_spatial_ref_sys (
			srs_name TEXT NOT NULL,
			srs_id INTEGER NOT NULL PRIMARY KEY,
			organization TEXT NOT NULL,
			organization_coordsys_id INTEGER NOT NULL,
			definition TEXT NOT NULL,
			description TEXT
		);
		CREATE TABLE gpkg_contents (
			table_name TEXT NOT NULL PRIMARY KEY,
			data_type TEXT NOT NULL,
			identifier TEXT UNIQUE,
			description TEXT DEFAULT '',
			last_change DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
			min_x DOUBLE,
			min_y DOUBLE,
			max_x DOUBLE,
			max_y DOUBLE,
			srs_id INTEGER,
			CONSTRAINT fk_gc_r_srs_id FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys(srs_id)
		);
		CREATE TABLE gpkg_geometry_columns (
			table_name TEXT NOT NULL,
			column_name TEXT NOT NULL,
			geometry_type_name TEXT NOT NULL,
			srs_id INTEGER NOT NULL,
			z TINYINT NOT NULL,
			m TINYINT NOT NULL,
			CONSTRAINT pk_geom_cols PRIMARY KEY (table_name, column_name),
			CONSTRAINT fk_gc_tn FOREIGN KEY (table_name) REFERENCES gpkg_contents(table_name),
			CONSTRAINT fk_gc_srs FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys(srs_id)
		);
	`); err != nil {
		return outcome, fmt.Errorf("create gpkg metadata tables: %w", err)
	}

	srsEntries := []struct {
		name string
		id   int32
		org  string
		code int32
		def  string
		desc string
	}{
		{"Undefined Cartesian SRS", -1, "NONE", -1, "undefined", "undefined cartesian coordinate reference system"},
		{"Undefined Geographic SRS", 0, "NONE", 0, "undefined", "undefined geographic coordinate reference system"},
		{"WGS 84 geodetic", 4326, "EPSG", 4326, wktWGS84, "WGS 84 / NAD83 geographic 2D"},
		{"NAD83", 4269, "EPSG", 4269, wktNAD83, "North American Datum 1983"},
		{"NAD83 / BC Albers", 3005, "EPSG", 3005, wktBCAlbers, "BC Ministry of Forests standard Albers Equal-Area Conic"},
	}
	for _, srs := range srsEntries {
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO gpkg_spatial_ref_sys (srs_name, srs_id, organization, organization_coordsys_id, definition, description)
			VALUES (?, ?, ?, ?, ?, ?)`,
			srs.name, srs.id, srs.org, srs.code, srs.def, srs.desc); err != nil {
			return outcome, err
		}
	}

	// Index Admin rows by Plot
	adminPlotIdx := -1
	for i, c := range adminCols {
		if strings.EqualFold(c.Name, "Plot") {
			adminPlotIdx = i
			break
		}
	}
	adminByPlot := map[string][]any{}
	if adminPlotIdx >= 0 {
		for _, r := range adminRows {
			if p, ok := r[adminPlotIdx].(string); ok {
				adminByPlot[p] = r
			}
		}
	}

	// Build unified plots feature table columns (Env + non-duplicate Admin + SiteUnit)
	seenCol := map[string]bool{"fid": true, "geom": true, "siteunit": true}
	var mergedSpecs []struct {
		name    string
		gType   string
		fromEnv bool
		idx     int
	}
	envPlotIdx, latIdx, lonIdx := -1, -1, -1
	for i, c := range envCols {
		lower := strings.ToLower(c.Name)
		if lower == "plotnumber" {
			envPlotIdx = i
		} else if lower == "latitude" {
			latIdx = i
		} else if lower == "longitude" {
			lonIdx = i
		}
		if seenCol[lower] {
			continue
		}
		seenCol[lower] = true
		mergedSpecs = append(mergedSpecs, struct {
			name    string
			gType   string
			fromEnv bool
			idx     int
		}{name: c.Name, gType: c.GPKGType, fromEnv: true, idx: i})
	}
	for i, c := range adminCols {
		lower := strings.ToLower(c.Name)
		if lower == "plot" || seenCol[lower] {
			continue
		}
		seenCol[lower] = true
		mergedSpecs = append(mergedSpecs, struct {
			name    string
			gType   string
			fromEnv bool
			idx     int
		}{name: c.Name, gType: c.GPKGType, fromEnv: false, idx: i})
	}

	colDefs := []string{`"fid" INTEGER PRIMARY KEY AUTOINCREMENT`, `"geom" POINT`, `"SiteUnit" TEXT`}
	insertCols := []string{`"geom"`, `"SiteUnit"`}
	placeholders := []string{"?", "?"}
	for _, ms := range mergedSpecs {
		q := vprocore.QuoteHeaderIdentifier(ms.name)
		colDefs = append(colDefs, q+" "+ms.gType)
		insertCols = append(insertCols, q)
		placeholders = append(placeholders, "?")
	}

	if _, err := tx.ExecContext(ctx, `CREATE TABLE "plots" (`+strings.Join(colDefs, ", ")+`)`); err != nil {
		return outcome, fmt.Errorf("create plots feature table: %w", err)
	}

	stmt, err := tx.PrepareContext(ctx, `INSERT INTO "plots" (`+strings.Join(insertCols, ", ")+`) VALUES (`+strings.Join(placeholders, ", ")+`)`)
	if err != nil {
		return outcome, err
	}
	defer stmt.Close()

	hasBounds := false
	var minX, minY, maxX, maxY float64
	locatedPlotSet := map[string]bool{}

	for _, eRow := range envRows {
		plotNum := ""
		if envPlotIdx >= 0 && eRow[envPlotIdx] != nil {
			plotNum = fmt.Sprint(eRow[envPlotIdx])
		}
		var geomBlob any
		hasValidCoord := false
		if latIdx >= 0 && lonIdx >= 0 && eRow[latIdx] != nil && eRow[lonIdx] != nil {
			latVal, ok1 := asFloat64Value(eRow[latIdx])
			lonVal, ok2 := asFloat64Value(eRow[lonIdx])
			if ok1 && ok2 {
				nLat, nLon, flipped, valid := NormalizeWesternLongitude(latVal, lonVal)
				if valid {
					hasValidCoord = true
					if flipped {
						outcome.NormalizedWestLongitudes++
					}
					var x, y float64
					if targetSRSID == 3005 {
						x, y = ProjectNAD83ToBCAlbers(nLat, nLon)
					} else {
						x, y = nLon, nLat
					}
					geomBlob = EncodeGeoPackagePoint(targetSRSID, x, y)
					if !hasBounds {
						minX, maxX, minY, maxY = x, x, y, y
						hasBounds = true
					} else {
						if x < minX {
							minX = x
						}
						if x > maxX {
							maxX = x
						}
						if y < minY {
							minY = y
						}
						if y > maxY {
							maxY = y
						}
					}
				}
			}
		}

		if !hasValidCoord {
			outcome.SkippedUnlocatedCount++
			if !request.IncludeUnlocatedPlots {
				continue
			}
		} else {
			outcome.LocatedPlotCount++
		}
		locatedPlotSet[plotNum] = true

		aRow := adminByPlot[plotNum]
		args := make([]any, 0, 2+len(mergedSpecs))
		args = append(args, geomBlob, suByPlot[plotNum])
		for _, ms := range mergedSpecs {
			if ms.fromEnv {
				val := eRow[ms.idx]
				// Normalize exported Longitude attribute when positive West was flipped
				if strings.EqualFold(ms.name, "Longitude") && hasValidCoord && val != nil {
					if fv, ok := asFloat64Value(val); ok && fv >= 100 && fv <= 170 {
						val = -fv
					}
				}
				args = append(args, val)
			} else if aRow != nil && ms.idx < len(aRow) {
				args = append(args, aRow[ms.idx])
			} else {
				args = append(args, nil)
			}
		}
		if _, err := stmt.ExecContext(ctx, args...); err != nil {
			return outcome, fmt.Errorf("insert plot %s into GeoPackage: %w", plotNum, err)
		}
		outcome.FeatureCount++
	}

	nowISO := time.Now().UTC().Format("2006-01-02T15:04:05.000Z")
	var bMinX, bMinY, bMaxX, bMaxY any
	if hasBounds {
		bMinX, bMinY, bMaxX, bMaxY = minX, minY, maxX, maxY
	}
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO gpkg_contents (table_name, data_type, identifier, description, last_change, min_x, min_y, max_x, max_y, srs_id)
		VALUES ('plots', 'features', 'plots', 'VPro BEC Ecological Plots (Env + Admin + SiteUnit)', ?, ?, ?, ?, ?, ?)`,
		nowISO, bMinX, bMinY, bMaxX, bMaxY, targetSRSID); err != nil {
		return outcome, err
	}
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO gpkg_geometry_columns (table_name, column_name, geometry_type_name, srs_id, z, m)
		VALUES ('plots', 'geom', 'POINT', ?, 0, 0)`, targetSRSID); err != nil {
		return outcome, err
	}

	// Optional non-spatial attribute tables (data_type = 'attributes')
	if request.IncludeAttributeTables {
		// 1. veg
		if _, err := tx.ExecContext(ctx, `
			CREATE TABLE "veg" (
				"fid" INTEGER PRIMARY KEY AUTOINCREMENT,
				"PlotNumber" TEXT NOT NULL,
				"SiteUnit" TEXT,
				"Layer" TEXT NOT NULL,
				"Species" TEXT NOT NULL,
				"ScientificName" TEXT,
				"Lifeform" INTEGER,
				"Cover" DOUBLE NOT NULL,
				"Height" DOUBLE,
				"Collected" TEXT
			)`); err != nil {
			return outcome, err
		}
		vegStmt, err := tx.PrepareContext(ctx, `INSERT INTO "veg" ("PlotNumber","SiteUnit","Layer","Species","ScientificName","Lifeform","Cover","Height","Collected") VALUES (?,?,?,?,?,?,?,?,?)`)
		if err != nil {
			return outcome, err
		}
		for _, vo := range vegObs {
			if !request.IncludeUnlocatedPlots && !locatedPlotSet[vo.PlotNumber] {
				continue
			}
			var lfAny, htAny any
			if vo.Lifeform != nil {
				lfAny = *vo.Lifeform
			}
			if vo.Height != nil {
				htAny = *vo.Height
			}
			if _, err := vegStmt.ExecContext(ctx, vo.PlotNumber, vo.SiteUnit, vo.Layer, vo.Species, vo.ScientificName, lfAny, vo.Cover, htAny, vo.Collected); err != nil {
				vegStmt.Close()
				return outcome, err
			}
		}
		vegStmt.Close()
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO gpkg_contents (table_name, data_type, identifier, description, last_change, srs_id)
			VALUES ('veg', 'attributes', 'veg', 'VPro Long Vegetation Observations', ?, 0)`, nowISO); err != nil {
			return outcome, err
		}
		outcome.AttributeTables = append(outcome.AttributeTables, "veg")

		// 2. humus & 3. mineral
		for _, attrTbl := range []struct {
			name string
			desc string
			cols []gpkgColSpec
			rows [][]any
		}{
			{"humus", "VPro Soil Humus Horizons", humusCols, humusRows},
			{"mineral", "VPro Soil Mineral Horizons", mineralCols, mineralRows},
		} {
			if err := writeAttributeTableGPKG(ctx, tx, attrTbl.name, attrTbl.desc, nowISO, attrTbl.cols, attrTbl.rows, locatedPlotSet, request.IncludeUnlocatedPlots); err != nil {
				return outcome, err
			}
			outcome.AttributeTables = append(outcome.AttributeTables, attrTbl.name)
		}
	}

	return outcome, nil
}

func writeAttributeTableGPKG(
	ctx context.Context,
	tx *sql.Tx,
	tableName, desc, nowISO string,
	cols []gpkgColSpec,
	rows [][]any,
	locatedPlots map[string]bool,
	includeUnlocated bool,
) error {
	defs := []string{`"fid" INTEGER PRIMARY KEY AUTOINCREMENT`}
	insCols := make([]string, 0, len(cols))
	marks := make([]string, 0, len(cols))
	plotIdx := -1
	for i, c := range cols {
		if strings.EqualFold(c.Name, "PlotNumber") {
			plotIdx = i
		}
		colOut := c.Name
		if strings.EqualFold(colOut, "fid") {
			colOut = "src_fid"
		}
		q := vprocore.QuoteHeaderIdentifier(colOut)
		defs = append(defs, q+" "+c.GPKGType)
		insCols = append(insCols, q)
		marks = append(marks, "?")
	}
	qTbl := vprocore.QuoteHeaderIdentifier(tableName)
	if _, err := tx.ExecContext(ctx, `CREATE TABLE `+qTbl+` (`+strings.Join(defs, ", ")+`)`); err != nil {
		return err
	}
	stmt, err := tx.PrepareContext(ctx, `INSERT INTO `+qTbl+` (`+strings.Join(insCols, ", ")+`) VALUES (`+strings.Join(marks, ", ")+`)`)
	if err != nil {
		return err
	}
	defer stmt.Close()

	for _, r := range rows {
		if !includeUnlocated && plotIdx >= 0 && r[plotIdx] != nil {
			if !locatedPlots[fmt.Sprint(r[plotIdx])] {
				continue
			}
		}
		if _, err := stmt.ExecContext(ctx, r...); err != nil {
			return err
		}
	}
	_, err = tx.ExecContext(ctx, `
		INSERT INTO gpkg_contents (table_name, data_type, identifier, description, last_change, srs_id)
		VALUES (?, 'attributes', ?, ?, ?, 0)`, tableName, tableName, desc, nowISO)
	return err
}
