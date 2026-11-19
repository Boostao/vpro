package cloudsync

import (
	"context"
	"errors"
	"fmt"
	"math"
	"strings"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/jackc/pgx/v5"
)

// IsSensitiveRedBlueList returns true when a USysSppAttributes.RedBlueList code
// designates a sensitive provincial conservation rank (Red/Blue list).
// Blank, NULL, and 'Z' ("No definition or data") are treated as non-sensitive.
func IsSensitiveRedBlueList(raw string) bool {
	switch strings.ToUpper(strings.TrimSpace(raw)) {
	case "R", "B", "RED", "BLUE":
		return true
	default:
		return false
	}
}

// TruncateSensitiveLatLon truncates geographic decimal degrees to a 0.1-degree (~10 km) grid cell.
func TruncateSensitiveLatLon(deg float64) float64 {
	if math.IsNaN(deg) || math.IsInf(deg, 0) {
		return deg
	}
	return math.Trunc(deg*10.0) / 10.0
}

// TruncateSensitiveUTM truncates projected coordinates (meters) to a 10 km (10,000 m) grid cell.
func TruncateSensitiveUTM(meters float64) float64 {
	if math.IsNaN(meters) || math.IsInf(meters, 0) {
		return meters
	}
	return math.Trunc(meters/10000.0) * 10000.0
}

func toFloat64Value(raw any) (float64, bool) {
	switch v := raw.(type) {
	case float64:
		if math.IsNaN(v) || math.IsInf(v, 0) {
			return 0, false
		}
		return v, true
	case float32:
		f := float64(v)
		if math.IsNaN(f) || math.IsInf(f, 0) {
			return 0, false
		}
		return f, true
	case int64:
		return float64(v), true
	case int32:
		return float64(v), true
	case int:
		return float64(v), true
	default:
		return 0, false
	}
}

// MaskSensitiveEnvRow truncates coordinate columns in a streamed VP08EnvColumns row slice.
func MaskSensitiveEnvRow(cols []ColumnSpec, rowArgs []any) {
	var xIdx, yIdx int = -1, -1
	for i, col := range cols {
		if i >= len(rowArgs) || rowArgs[i] == nil {
			continue
		}
		switch col.Name {
		case "Longitude", "Latitude":
			if f, ok := toFloat64Value(rowArgs[i]); ok {
				rowArgs[i] = TruncateSensitiveLatLon(f)
			}
		case "UTMEasting", "UTMNorthing":
			if f, ok := toFloat64Value(rowArgs[i]); ok {
				rowArgs[i] = TruncateSensitiveUTM(f)
			}
		case "XCoord":
			xIdx = i
		case "YCoord":
			yIdx = i
		}
	}
	if xIdx >= 0 || yIdx >= 0 {
		var xv, yv float64
		hasX, hasY := false, false
		if xIdx >= 0 {
			xv, hasX = toFloat64Value(rowArgs[xIdx])
		}
		if yIdx >= 0 {
			yv, hasY = toFloat64Value(rowArgs[yIdx])
		}
		// Treat bounded XCoord/YCoord within +/-180/90 as geographic degrees; larger magnitudes as projected meters.
		isDeg := (!hasX || math.Abs(xv) <= 180.0) && (!hasY || math.Abs(yv) <= 90.0)
		if hasX {
			if isDeg {
				rowArgs[xIdx] = TruncateSensitiveLatLon(xv)
			} else {
				rowArgs[xIdx] = TruncateSensitiveUTM(xv)
			}
		}
		if hasY {
			if isDeg {
				rowArgs[yIdx] = TruncateSensitiveLatLon(yv)
			} else {
				rowArgs[yIdx] = TruncateSensitiveUTM(yv)
			}
		}
	}
}

func readSensitiveSpeciesFromSQLiteVLists(ctx context.Context, vlistsPath string) (map[string]struct{}, bool, error) {
	out := map[string]struct{}{}
	trimmed := strings.TrimSpace(vlistsPath)
	if trimmed == "" {
		return out, false, nil
	}
	db, err := sqlutil.OpenReadOnlyContext(ctx, trimmed)
	if err != nil {
		return out, false, err
	}
	defer db.Close()

	var hasTbl int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='USysSppAttributes'`).Scan(&hasTbl); err != nil {
		return out, false, err
	}
	if hasTbl == 0 {
		return out, false, nil
	}
	rows, err := db.QueryContext(ctx, `
		SELECT UPPER(TRIM(CAST("Code" AS TEXT))), COALESCE(CAST("RedBlueList" AS TEXT), ''), COALESCE(CAST("Codetype" AS TEXT), '')
		FROM "USysSppAttributes"
		WHERE "Code" IS NOT NULL AND TRIM(CAST("Code" AS TEXT)) <> ''
		  AND "RedBlueList" IS NOT NULL AND TRIM(CAST("RedBlueList" AS TEXT)) <> ''
	`)
	if err != nil {
		return out, true, err
	}
	defer rows.Close()
	for rows.Next() {
		var code, rbl, ct string
		if err := rows.Scan(&code, &rbl, &ct); err != nil {
			return out, true, err
		}
		if strings.EqualFold(strings.TrimSpace(ct), "S") {
			continue
		}
		if IsSensitiveRedBlueList(rbl) {
			out[code] = struct{}{}
		}
	}
	return out, true, rows.Err()
}

func readSensitiveSpeciesFromPG(ctx context.Context, q pgxQueryRowOrQuery) (map[string]struct{}, bool, error) {
	out := map[string]struct{}{}
	if q == nil {
		return out, false, errors.New("PostgreSQL query handle is nil")
	}
	var hasTbl bool
	if err := q.QueryRow(ctx, `SELECT to_regclass('standards.usys_spp_attributes') IS NOT NULL`).Scan(&hasTbl); err != nil {
		return out, false, err
	}
	if !hasTbl {
		return out, false, nil
	}
	rows, err := q.Query(ctx, `
		SELECT DISTINCT UPPER(TRIM("Code"))
		FROM standards.usys_spp_attributes
		WHERE "Code" IS NOT NULL AND TRIM("Code") <> ''
		  AND COALESCE(UPPER(TRIM("Codetype")), '') <> 'S'
		  AND UPPER(TRIM(COALESCE("RedBlueList", ''))) IN ('R', 'B', 'RED', 'BLUE')
	`)
	if err != nil {
		return out, true, err
	}
	defer rows.Close()
	for rows.Next() {
		var code string
		if err := rows.Scan(&code); err != nil {
			return out, true, err
		}
		if code != "" {
			out[code] = struct{}{}
		}
	}
	return out, true, rows.Err()
}

type pgxQueryRowOrQuery interface {
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

func findSensitivePlotsForSubsetPG(ctx context.Context, q pgxQueryRowOrQuery, plotList []string, vlistsPath string) (map[string]struct{}, error) {
	sensitivePlots := map[string]struct{}{}

	speciesSet, pgHasTbl, err := readSensitiveSpeciesFromPG(ctx, q)
	if err != nil {
		return nil, err
	}
	localSet, localHasTbl, lErr := readSensitiveSpeciesFromSQLiteVLists(ctx, vlistsPath)
	if lErr != nil && len(speciesSet) == 0 {
		return nil, fmt.Errorf("read local VLists conservation status metadata: %w", lErr)
	}
	for code := range localSet {
		speciesSet[code] = struct{}{}
	}
	if len(speciesSet) == 0 {
		if !pgHasTbl && !localHasTbl {
			return nil, errors.New("conservation status table standards.usys_spp_attributes / USysSppAttributes is missing; refusing to export unredacted plot coordinates without BC CDC Red/Blue status metadata")
		}
		return nil, errors.New("conservation status metadata (standards.usys_spp_attributes / USysSppAttributes.RedBlueList) contains 0 Red/Blue-listed species rows; refusing to export unredacted plot coordinates when sensitive-species redaction is required (populate BC CDC Red/Blue status codes first)")
	}
	if len(plotList) == 0 {
		return sensitivePlots, nil
	}

	speciesList := make([]string, 0, len(speciesSet))
	for code := range speciesSet {
		speciesList = append(speciesList, code)
	}
	rows, err := q.Query(ctx, `
		SELECT DISTINCT "PlotNumber"
		FROM becmaster.veg
		WHERE "PlotNumber" = ANY($1)
		  AND "Species" IS NOT NULL
		  AND UPPER(TRIM("Species")) = ANY($2)
	`, plotList, speciesList)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var plot string
		if err := rows.Scan(&plot); err != nil {
			return nil, err
		}
		if plot != "" {
			sensitivePlots[plot] = struct{}{}
		}
	}
	return sensitivePlots, rows.Err()
}
