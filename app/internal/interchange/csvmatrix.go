package interchange

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/csv"
	"encoding/hex"
	"errors"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type vegSublayerSpec struct {
	LayerCode   string
	TVGroup     string
	StrataGroup string
	CoverCol    string
	HeightCol   string
	IsTextHt    bool
}

var canonicalVegSublayers = []vegSublayerSpec{
	{LayerCode: "A1", TVGroup: "Tree", StrataGroup: "A", CoverCol: "Cover1", HeightCol: "Height1"},
	{LayerCode: "A2", TVGroup: "Tree", StrataGroup: "A", CoverCol: "Cover2", HeightCol: "Height2"},
	{LayerCode: "A3", TVGroup: "Tree", StrataGroup: "A", CoverCol: "Cover3", HeightCol: "Height3"},
	{LayerCode: "A", TVGroup: "Tree", StrataGroup: "A", CoverCol: "TotalA", HeightCol: "HeightA"},
	{LayerCode: "B1", TVGroup: "Shrub", StrataGroup: "B", CoverCol: "Cover4", HeightCol: "Height4"},
	{LayerCode: "B2", TVGroup: "Shrub", StrataGroup: "B", CoverCol: "Cover5", HeightCol: "Height5"},
	{LayerCode: "B2a", TVGroup: "Shrub", StrataGroup: "B", CoverCol: "Cover5a", HeightCol: "Height5a"},
	{LayerCode: "B2b", TVGroup: "Shrub", StrataGroup: "B", CoverCol: "Cover5b", HeightCol: "Height5b"},
	{LayerCode: "B2c", TVGroup: "Shrub", StrataGroup: "B", CoverCol: "Cover5c", HeightCol: "Height5c"},
	{LayerCode: "B", TVGroup: "Shrub", StrataGroup: "B", CoverCol: "TotalB", HeightCol: "HeightB", IsTextHt: true},
	{LayerCode: "C", TVGroup: "Herb", StrataGroup: "C", CoverCol: "Cover6", HeightCol: "Height6"},
	{LayerCode: "D", TVGroup: "Moss", StrataGroup: "D", CoverCol: "Cover7", HeightCol: ""},
	{LayerCode: "Dw", TVGroup: "Moss", StrataGroup: "D", CoverCol: "Cover8", HeightCol: ""},
	{LayerCode: "Dr", TVGroup: "Moss", StrataGroup: "D", CoverCol: "Cover9", HeightCol: ""},
	{LayerCode: "Ep", TVGroup: "Epiphyte", StrataGroup: "Ep", CoverCol: "Cover10", HeightCol: ""},
}

type longVegObservation struct {
	PlotNumber     string
	SiteUnit       string
	ID             int64
	LayerIndex     int
	Layer          string
	TVGroup        string
	StrataGroup    string
	Species        string
	ScientificName string
	Lifeform       *int
	Cover          float64
	Height         *float64
	Collected      string
}

type LongTidyCSVRequest struct {
	DestinationPath string `json:"destinationPath,omitempty"`
	LumpTable       string `json:"lumpTable,omitempty"`
	LumpDBPath      string `json:"lumpDbPath,omitempty"`
}

func (r *LongTidyCSVRequest) UnmarshalJSON(data []byte) error {
	type plain LongTidyCSVRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type WideMatrixCSVRequest struct {
	DestinationPath string `json:"destinationPath,omitempty"`
	LayerMode       string `json:"layerMode"` // "rollup_all" | "strata_4" | "species_layer"
	ZeroFill        bool   `json:"zeroFill"`
	IncludeSiteUnit bool   `json:"includeSiteUnit"`
	LumpTable       string `json:"lumpTable,omitempty"`
	LumpDBPath      string `json:"lumpDbPath,omitempty"`
}

func (r *WideMatrixCSVRequest) UnmarshalJSON(data []byte) error {
	type plain WideMatrixCSVRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type CSVExportOutcome struct {
	Mode         string `json:"mode"`
	RowCount     int    `json:"rowCount"`
	PlotCount    int    `json:"plotCount"`
	SpeciesCount int    `json:"speciesCount"`
	ColumnCount  int    `json:"columnCount"`
	Path         string `json:"path,omitempty"`
	SHA256       string `json:"sha256"`
	PreviewCSV   string `json:"previewCsv"`
}

type speciesLookupMeta struct {
	ScientificName string
	EnglishName    string
	Authority      string
	Lifeform       *int
}

func loadSpeciesLookupMeta(ctx context.Context, tx *sql.Tx) (map[string]speciesLookupMeta, error) {
	meta := make(map[string]speciesLookupMeta, 16500)
	rows, err := tx.QueryContext(ctx, `
		SELECT Code, COALESCE(ScientificName,''), COALESCE(EnglishName,''), COALESCE(Authority,''), Lifeform, COALESCE(Codetype,'')
		FROM VLists.USysAllSpecs
		WHERE Code IS NOT NULL AND TRIM(Code) <> ''
		ORDER BY CASE WHEN UPPER(COALESCE(Codetype,''))='U' THEN 0 ELSE 1 END, rowid`)
	if err != nil {
		return nil, err
	}
	rowIdx := 0
	for rows.Next() {
		if rowIdx&511 == 0 {
			if err := ctx.Err(); err != nil {
				rows.Close()
				return nil, err
			}
		}
		rowIdx++
		var code, sci, eng, auth, ctype string
		var lf sql.NullInt64
		if err := rows.Scan(&code, &sci, &eng, &auth, &lf, &ctype); err != nil {
			rows.Close()
			return nil, err
		}
		u := strings.ToUpper(strings.TrimSpace(code))
		if _, exists := meta[u]; exists {
			continue
		}
		var lfPtr *int
		if lf.Valid {
			v := int(lf.Int64)
			lfPtr = &v
		}
		meta[u] = speciesLookupMeta{
			ScientificName: strings.TrimSpace(sci),
			EnglishName:    strings.TrimSpace(eng),
			Authority:      strings.TrimSpace(auth),
			Lifeform:       lfPtr,
		}
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return nil, err
	}
	if err := rows.Close(); err != nil {
		return nil, err
	}

	uRows, err := tx.QueryContext(ctx, `
		SELECT Code, COALESCE(ScientificName,''), COALESCE(EnglishName,''), LifeForm
		FROM VUser.USysUserSpp
		WHERE Code IS NOT NULL AND TRIM(Code) <> ''`)
	if err != nil {
		return nil, err
	}
	uIdx := 0
	for uRows.Next() {
		if uIdx&511 == 0 {
			if err := ctx.Err(); err != nil {
				uRows.Close()
				return nil, err
			}
		}
		uIdx++
		var code, sci, eng string
		var lf sql.NullInt64
		if err := uRows.Scan(&code, &sci, &eng, &lf); err != nil {
			uRows.Close()
			return nil, err
		}
		u := strings.ToUpper(strings.TrimSpace(code))
		if _, exists := meta[u]; exists {
			continue
		}
		var lfPtr *int
		if lf.Valid {
			v := int(lf.Int64)
			lfPtr = &v
		}
		meta[u] = speciesLookupMeta{
			ScientificName: strings.TrimSpace(sci),
			EnglishName:    strings.TrimSpace(eng),
			Lifeform:       lfPtr,
		}
	}
	if err := uRows.Err(); err != nil {
		uRows.Close()
		return nil, err
	}
	if err := uRows.Close(); err != nil {
		return nil, err
	}
	return meta, ctx.Err()
}

func loadOptionalLumpMap(ctx context.Context, defaultProjectPath, lumpTable, lumpDBPath string) (map[string]string, error) {
	tbl := strings.TrimSpace(lumpTable)
	if tbl == "" || strings.EqualFold(tbl, "None") || strings.EqualFold(tbl, "None_Lump") {
		return nil, nil
	}
	if !strings.HasSuffix(strings.ToLower(tbl), "_lump") {
		tbl += "_Lump"
	}
	targetDB := strings.TrimSpace(lumpDBPath)
	if targetDB == "" {
		targetDB = defaultProjectPath
	}
	dbLabel := filepath.Base(targetDB)
	if dbLabel == "" || dbLabel == "." {
		dbLabel = "project database"
	}
	resolved, err := vprocore.ExistingDatabasePath(targetDB)
	if err != nil {
		if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
			return nil, err
		}
		if errors.Is(err, os.ErrNotExist) {
			return nil, fmt.Errorf("species lumping file %q was not found", dbLabel)
		}
		if errors.Is(err, os.ErrPermission) {
			return nil, fmt.Errorf("species lumping file %q could not be opened due to file permissions", dbLabel)
		}
		return nil, fmt.Errorf("species lumping file %q could not be opened", dbLabel)
	}
	resolvedLabel := filepath.Base(resolved)
	db, err := sqlutil.OpenReadOnlyContext(ctx, resolved)
	if err != nil {
		if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
			return nil, err
		}
		return nil, fmt.Errorf("species lumping file %q could not be read", resolvedLabel)
	}
	defer db.Close()

	var actual string
	if err := db.QueryRowContext(ctx, `SELECT name FROM sqlite_master WHERE type='table' AND name COLLATE NOCASE=?`, tbl).Scan(&actual); err != nil {
		if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
			return nil, err
		}
		if errors.Is(err, sql.ErrNoRows) {
			return nil, fmt.Errorf("species lumping table %q was not found in %s", tbl, resolvedLabel)
		}
		return nil, fmt.Errorf("species lumping file %q could not be read as a valid VPro database", resolvedLabel)
	}
	rows, err := db.QueryContext(ctx, `
		SELECT COALESCE(LumpCode,''), COALESCE(SppCode,''),
		       CASE WHEN "Use" IS NULL THEN 0 WHEN typeof("Use")='text' THEN "Use" ELSE CAST("Use" AS INTEGER) END
		FROM `+vprocore.QuoteHeaderIdentifier(actual))
	if err != nil {
		if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
			return nil, err
		}
		return nil, fmt.Errorf("species lumping table %q in %s is missing required LumpCode, SppCode, or Use columns", actual, resolvedLabel)
	}
	defer rows.Close()

	m := map[string]string{}
	for rows.Next() {
		var lc, sc string
		var rawUse any
		if err := rows.Scan(&lc, &sc, &rawUse); err != nil {
			return nil, err
		}
		if isAccessTruthy(rawUse) {
			uSpp := strings.ToUpper(strings.TrimSpace(sc))
			uLump := strings.ToUpper(strings.TrimSpace(lc))
			if uSpp != "" && uLump != "" {
				m[uSpp] = uLump
			}
		}
	}
	return m, rows.Err()
}

func isAccessTruthy(raw any) bool {
	switch v := raw.(type) {
	case nil:
		return false
	case bool:
		return v
	case int64:
		return v != 0
	case int:
		return v != 0
	case float64:
		return v != 0
	case []byte:
		return isAccessTruthy(string(v))
	case string:
		t := strings.TrimSpace(strings.ToLower(v))
		return t == "-1" || t == "1" || t == "true" || t == "yes"
	default:
		return false
	}
}

func scopedPlotsCTEAndPredicate(owner *vprocore.SqliteContext, outerExpr string) (string, string) {
	project := owner.Selection.Project
	envTbl := "project." + vprocore.QuoteHeaderIdentifier(project+"_Env")
	adminTbl := "project." + vprocore.QuoteHeaderIdentifier(project+"_Admin")

	suWhere := ""
	if owner.Selection.SU != "None" {
		suTbl := "su." + vprocore.QuoteHeaderIdentifier(owner.Selection.SU+"_SU")
		suWhere = `
		WHERE EXISTS (
			SELECT 1 FROM ` + suTbl + ` AS s
			WHERE s."PlotNumber" = e."PlotNumber"
			  AND typeof(s."PlotNumber") = 'text'
			  AND CAST(s."PlotNumber" AS BLOB) = CAST(e."PlotNumber" AS BLOB)
		)`
	}

	cte := `WITH "__vpro_scoped_plots"("PlotNumber") AS MATERIALIZED (
		SELECT DISTINCT e."PlotNumber" COLLATE BINARY
		FROM ` + envTbl + ` AS e
		INNER JOIN ` + adminTbl + ` AS a
		  ON a."Plot" = e."PlotNumber"
		 AND typeof(e."PlotNumber") = 'text'
		 AND typeof(a."Plot") = 'text'
		 AND CAST(a."Plot" AS BLOB) = CAST(e."PlotNumber" AS BLOB)` + suWhere + `
	) `

	pred := outerExpr + ` IN (SELECT "PlotNumber" FROM "__vpro_scoped_plots")
		AND typeof(` + outerExpr + `) = 'text'
		AND EXISTS (
			SELECT 1 FROM "__vpro_scoped_plots" AS __sp
			WHERE __sp."PlotNumber" = ` + outerExpr + `
			  AND CAST(__sp."PlotNumber" AS BLOB) = CAST(` + outerExpr + ` AS BLOB)
		)`
	return cte, pred
}

func withScopedReadSnapshot(ctx context.Context, owner *vprocore.SqliteContext, fn func(tx *sql.Tx) error) error {
	if err := sqlutil.AcquireMutexLease(ctx, &owner.Mu); err != nil {
		return err
	}
	defer owner.Mu.Unlock()

	tx, err := owner.BeginReadSnapshot(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	if err := fn(tx); err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	return tx.Commit()
}

func writeAtomicExportFileContext(ctx context.Context, destinationPath string, data []byte) (string, string, error) {
	if err := ctx.Err(); err != nil {
		return "", "", err
	}
	if strings.TrimSpace(destinationPath) == "" {
		sum := sha256.Sum256(data)
		return "", hex.EncodeToString(sum[:]), ctx.Err()
	}
	if !utf8.ValidString(destinationPath) || strings.ContainsRune(destinationPath, 0) {
		return "", "", errors.New("destination path must be valid UTF-8 without NUL")
	}
	abs, err := filepath.Abs(filepath.Clean(destinationPath))
	if err != nil {
		return "", "", err
	}
	dir := filepath.Dir(abs)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", "", fmt.Errorf("create destination directory %s: %w", dir, err)
	}
	tmp, err := os.CreateTemp(dir, ".vpro-export-*")
	if err != nil {
		return "", "", err
	}
	tmpName := tmp.Name()
	committed := false
	defer func() {
		if !committed {
			_ = os.Remove(tmpName)
		}
	}()

	const chunkBytes = 1 << 20
	for offset := 0; offset < len(data); offset += chunkBytes {
		if err := ctx.Err(); err != nil {
			_ = tmp.Close()
			return "", "", err
		}
		end := offset + chunkBytes
		if end > len(data) {
			end = len(data)
		}
		if _, err := tmp.Write(data[offset:end]); err != nil {
			_ = tmp.Close()
			return "", "", err
		}
	}
	if err := ctx.Err(); err != nil {
		_ = tmp.Close()
		return "", "", err
	}
	if err := tmp.Sync(); err != nil {
		_ = tmp.Close()
		return "", "", err
	}
	if err := tmp.Close(); err != nil {
		return "", "", err
	}
	if err := ctx.Err(); err != nil {
		return "", "", err
	}
	if err := os.Rename(tmpName, abs); err != nil {
		return "", "", err
	}
	committed = true
	sum := sha256.Sum256(data)
	return abs, hex.EncodeToString(sum[:]), nil
}

func loadScopedPlotSiteUnits(ctx context.Context, tx *sql.Tx, owner *vprocore.SqliteContext) ([]string, map[string]string, error) {
	if err := ctx.Err(); err != nil {
		return nil, nil, err
	}
	project := owner.Selection.Project
	envTbl := "project." + vprocore.QuoteHeaderIdentifier(project+"_Env")
	adminTbl := "project." + vprocore.QuoteHeaderIdentifier(project+"_Admin")

	plotOrder := []string{}
	suByPlot := map[string]string{}

	var query string
	if owner.Selection.SU != "None" {
		suTbl := "su." + vprocore.QuoteHeaderIdentifier(owner.Selection.SU+"_SU")
		query = `
			SELECT e."PlotNumber", COALESCE(s."SiteUnit", COALESCE(a."UserSiteUnit", ''))
			FROM ` + envTbl + ` AS e
			INNER JOIN ` + adminTbl + ` AS a
			  ON a."Plot" = e."PlotNumber"
			 AND typeof(e."PlotNumber") = 'text'
			 AND typeof(a."Plot") = 'text'
			 AND CAST(a."Plot" AS BLOB) = CAST(e."PlotNumber" AS BLOB)
			INNER JOIN ` + suTbl + ` AS s
			  ON s."PlotNumber" = e."PlotNumber"
			 AND typeof(s."PlotNumber") = 'text'
			 AND CAST(s."PlotNumber" AS BLOB) = CAST(e."PlotNumber" AS BLOB)
			ORDER BY e."PlotNumber" COLLATE BINARY`
	} else {
		query = `
			SELECT e."PlotNumber", COALESCE(a."UserSiteUnit", COALESCE(a."BECSiteUnit", ''))
			FROM ` + envTbl + ` AS e
			INNER JOIN ` + adminTbl + ` AS a
			  ON a."Plot" = e."PlotNumber"
			 AND typeof(e."PlotNumber") = 'text'
			 AND typeof(a."Plot") = 'text'
			 AND CAST(a."Plot" AS BLOB) = CAST(e."PlotNumber" AS BLOB)
			ORDER BY e."PlotNumber" COLLATE BINARY`
	}

	rows, err := tx.QueryContext(ctx, query)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()

	rowIdx := 0
	for rows.Next() {
		if rowIdx&511 == 0 {
			if err := ctx.Err(); err != nil {
				return nil, nil, err
			}
		}
		rowIdx++
		var plot, su string
		if err := rows.Scan(&plot, &su); err != nil {
			return nil, nil, err
		}
		if _, exists := suByPlot[plot]; !exists {
			plotOrder = append(plotOrder, plot)
		}
		suByPlot[plot] = strings.TrimSpace(su)
	}
	if err := rows.Err(); err != nil {
		return nil, nil, err
	}
	return plotOrder, suByPlot, ctx.Err()
}

func extractLongVegObservations(
	ctx context.Context,
	tx *sql.Tx,
	owner *vprocore.SqliteContext,
	suByPlot map[string]string,
	sppMeta map[string]speciesLookupMeta,
	lumpMap map[string]string,
) ([]longVegObservation, error) {
	project := owner.Selection.Project
	vegTbl := "project." + vprocore.QuoteHeaderIdentifier(project+"_Veg")

	vegCols, err := readTxColumnSet(ctx, tx, "project", project+"_Veg")
	if err != nil {
		return nil, err
	}

	selectParts := []string{
		`v."PlotNumber"`,
		`COALESCE(v."ID", 0)`,
		`COALESCE(v."Species", '')`,
		`COALESCE(v."Collected", '')`,
	}
	for _, sl := range canonicalVegSublayers {
		if vegCols[strings.ToLower(sl.CoverCol)] {
			selectParts = append(selectParts, `v.`+vprocore.QuoteHeaderIdentifier(sl.CoverCol))
		} else {
			selectParts = append(selectParts, `NULL`)
		}
		if sl.HeightCol != "" && vegCols[strings.ToLower(sl.HeightCol)] {
			if sl.IsTextHt {
				selectParts = append(selectParts, `CAST(NULLIF(TRIM(CAST(v.`+vprocore.QuoteHeaderIdentifier(sl.HeightCol)+` AS TEXT)), '') AS REAL)`)
			} else {
				selectParts = append(selectParts, `v.`+vprocore.QuoteHeaderIdentifier(sl.HeightCol))
			}
		} else {
			selectParts = append(selectParts, `NULL`)
		}
	}

	cteSQL, scopePred := scopedPlotsCTEAndPredicate(owner, `v."PlotNumber"`)
	query := cteSQL + `SELECT ` + strings.Join(selectParts, ", ") + `
		FROM ` + vegTbl + ` AS v
		WHERE ` + scopePred + `
		ORDER BY v."PlotNumber", v."Species" COLLATE NOCASE, COALESCE(v."ID", 0)`

	rows, err := tx.QueryContext(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("query project vegetation: %w", err)
	}
	defer rows.Close()

	var rawObs []longVegObservation
	scannedRows := 0
	for rows.Next() {
		if scannedRows&511 == 0 {
			if err := ctx.Err(); err != nil {
				return nil, err
			}
		}
		scannedRows++
		var plot, species, collected string
		var id int64
		var covers [15]sql.NullFloat64
		var heights [15]sql.NullFloat64
		dest := make([]any, 0, 4+30)
		dest = append(dest, &plot, &id, &species, &collected)
		for i := range canonicalVegSublayers {
			dest = append(dest, &covers[i], &heights[i])
		}
		if err := rows.Scan(dest...); err != nil {
			return nil, err
		}
		code := strings.ToUpper(strings.TrimSpace(species))
		if code == "" {
			continue
		}
		if lumpMap != nil {
			if target, ok := lumpMap[code]; ok && target != "" {
				code = target
			}
		}
		meta := sppMeta[code]
		su := suByPlot[plot]
		coll := strings.TrimSpace(collected)

		emittedAny := false
		for idx, sl := range canonicalVegSublayers {
			if !covers[idx].Valid {
				continue
			}
			cov32 := float32(covers[idx].Float64)
			cov := float64(cov32)
			if cov < 0 {
				continue
			}
			emittedAny = true
			// Clean float32 decimal artifacts to 4 decimals without rounding valid < 100
			// float32 covers (such as 99.999996) up to 100.0 (used by rdsexport.go / veg_long).
			rounded := math.Round(cov*10000) / 10000
			if cov32 < 100 && rounded >= 100 {
				rounded = 99.9999
			}
			cov = rounded
			var htPtr *float64
			if heights[idx].Valid {
				hv := math.Round(float64(float32(heights[idx].Float64))*100) / 100
				htPtr = &hv
			}
			rawObs = append(rawObs, longVegObservation{
				PlotNumber:     plot,
				SiteUnit:       su,
				ID:             id,
				LayerIndex:     idx,
				Layer:          sl.LayerCode,
				TVGroup:        sl.TVGroup,
				StrataGroup:    sl.StrataGroup,
				Species:        code,
				ScientificName: meta.ScientificName,
				Lifeform:       meta.Lifeform,
				Cover:          cov,
				Height:         htPtr,
				Collected:      coll,
			})
		}
		if !emittedAny {
			// Preserve presence-only / voucher species rows whose sublayer covers are all NULL.
			rawObs = append(rawObs, longVegObservation{
				PlotNumber:     plot,
				SiteUnit:       su,
				ID:             id,
				LayerIndex:     9, // Herb/presence default slot
				Layer:          "C",
				TVGroup:        "Herb",
				StrataGroup:    "C",
				Species:        code,
				ScientificName: meta.ScientificName,
				Lifeform:       meta.Lifeform,
				Cover:          0,
				Height:         nil,
				Collected:      coll,
			})
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}

	// If lumping folded multiple species into the same (PlotNumber, LayerIndex, Species), combine covers capped at 99% and max(Height)
	if len(lumpMap) > 0 {
		type foldKey struct {
			plot  string
			layer int
			spp   string
		}
		folded := make(map[foldKey]*longVegObservation, len(rawObs))
		order := make([]foldKey, 0, len(rawObs))
		for i, obs := range rawObs {
			if i&1023 == 0 {
				if err := ctx.Err(); err != nil {
					return nil, err
				}
			}
			fk := foldKey{plot: obs.PlotNumber, layer: obs.LayerIndex, spp: obs.Species}
			if existing, ok := folded[fk]; ok {
				existing.Cover += obs.Cover
				if existing.Cover > 99.0 {
					existing.Cover = 99.0
				}
				existing.Cover = math.Round(existing.Cover*10000) / 10000
				if obs.Height != nil && (existing.Height == nil || *obs.Height > *existing.Height) {
					v := *obs.Height
					existing.Height = &v
				}
				if existing.Collected == "" && obs.Collected != "" {
					existing.Collected = obs.Collected
				}
			} else {
				cp := obs
				folded[fk] = &cp
				order = append(order, fk)
			}
		}
		rawObs = make([]longVegObservation, 0, len(order))
		for _, fk := range order {
			rawObs = append(rawObs, *folded[fk])
		}
	}

	if err := ctx.Err(); err != nil {
		return nil, err
	}
	slices.SortFunc(rawObs, func(a, b longVegObservation) int {
		if c := strings.Compare(a.PlotNumber, b.PlotNumber); c != 0 {
			return c
		}
		if a.LayerIndex != b.LayerIndex {
			return a.LayerIndex - b.LayerIndex
		}
		return strings.Compare(a.Species, b.Species)
	})
	return rawObs, ctx.Err()
}

func readTxColumnSet(ctx context.Context, tx *sql.Tx, alias, table string) (map[string]bool, error) {
	rows, err := tx.QueryContext(ctx, `PRAGMA `+vprocore.QuoteHeaderIdentifier(alias)+`.table_info(`+vprocore.QuoteHeaderIdentifier(table)+`)`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	cols := map[string]bool{}
	for rows.Next() {
		var cid, notNull, pk int
		var name, ctype string
		var dflt any
		if err := rows.Scan(&cid, &name, &ctype, &notNull, &dflt, &pk); err != nil {
			return nil, err
		}
		cols[strings.ToLower(name)] = true
	}
	return cols, rows.Err()
}

func truncateCSVPreview(data []byte, maxLines int) string {
	lines := strings.SplitAfter(string(data), "\n")
	if len(lines) <= maxLines {
		return string(data)
	}
	return strings.Join(lines[:maxLines], "")
}

func ExportLongTidyCSV(s *vprocore.ContextService, ctx context.Context, contextID string, request LongTidyCSVRequest) (CSVExportOutcome, error) {
	if err := ctx.Err(); err != nil {
		return CSVExportOutcome{}, err
	}
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (CSVExportOutcome, error) {
		owner := plots.Projects.Sqlite
		lumpMap, err := loadOptionalLumpMap(ctx, owner.Selection.ProjectPath, request.LumpTable, request.LumpDBPath)
		if err != nil {
			return CSVExportOutcome{}, err
		}

		var (
			plotOrder []string
			suByPlot  map[string]string
			obs       []longVegObservation
		)
		if err := withScopedReadSnapshot(ctx, owner, func(tx *sql.Tx) error {
			var rErr error
			plotOrder, suByPlot, rErr = loadScopedPlotSiteUnits(ctx, tx, owner)
			if rErr != nil {
				return rErr
			}
			sppMeta, rErr := loadSpeciesLookupMeta(ctx, tx)
			if rErr != nil {
				return rErr
			}
			obs, rErr = extractLongVegObservations(ctx, tx, owner, suByPlot, sppMeta, lumpMap)
			return rErr
		}); err != nil {
			return CSVExportOutcome{}, err
		}

		var buf bytes.Buffer
		w := csv.NewWriter(&buf)
		header := []string{"PlotNumber", "SiteUnit", "Layer", "Species", "ScientificName", "Lifeform", "Cover", "Height", "Collected"}
		if err := w.Write(header); err != nil {
			return CSVExportOutcome{}, err
		}
		sppSet := map[string]struct{}{}
		for i, o := range obs {
			if i&1023 == 0 {
				if err := ctx.Err(); err != nil {
					return CSVExportOutcome{}, err
				}
			}
			sppSet[o.Species] = struct{}{}
			row := []string{
				o.PlotNumber,
				o.SiteUnit,
				o.Layer,
				o.Species,
				o.ScientificName,
				optInt(o.Lifeform),
				strconv.FormatFloat(o.Cover, 'f', -1, 64),
				optFloat(o.Height),
				o.Collected,
			}
			if err := w.Write(row); err != nil {
				return CSVExportOutcome{}, err
			}
		}
		w.Flush()
		if err := w.Error(); err != nil {
			return CSVExportOutcome{}, err
		}

		data := buf.Bytes()
		writtenPath, shaHex, err := writeAtomicExportFileContext(ctx, request.DestinationPath, data)
		if err != nil {
			return CSVExportOutcome{}, err
		}
		return CSVExportOutcome{
			Mode:         "long_tidy",
			RowCount:     len(obs),
			PlotCount:    len(plotOrder),
			SpeciesCount: len(sppSet),
			ColumnCount:  len(header),
			Path:         writtenPath,
			SHA256:       shaHex,
			PreviewCSV:   truncateCSVPreview(data, 25),
		}, nil
	})
}

func ExportWideMatrixCSV(s *vprocore.ContextService, ctx context.Context, contextID string, request WideMatrixCSVRequest) (CSVExportOutcome, error) {
	mode := strings.ToLower(strings.TrimSpace(request.LayerMode))
	if mode == "" {
		mode = "rollup_all"
	}
	if mode != "rollup_all" && mode != "strata_4" && mode != "species_layer" {
		return CSVExportOutcome{}, fmt.Errorf("unsupported Wide Matrix CSV layerMode %q (expected rollup_all, strata_4, or species_layer)", request.LayerMode)
	}
	if err := ctx.Err(); err != nil {
		return CSVExportOutcome{}, err
	}

	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (CSVExportOutcome, error) {
		owner := plots.Projects.Sqlite
		lumpMap, err := loadOptionalLumpMap(ctx, owner.Selection.ProjectPath, request.LumpTable, request.LumpDBPath)
		if err != nil {
			return CSVExportOutcome{}, err
		}

		var (
			plotOrder []string
			suByPlot  map[string]string
			obs       []longVegObservation
		)
		if err := withScopedReadSnapshot(ctx, owner, func(tx *sql.Tx) error {
			var rErr error
			plotOrder, suByPlot, rErr = loadScopedPlotSiteUnits(ctx, tx, owner)
			if rErr != nil {
				return rErr
			}
			sppMeta, rErr := loadSpeciesLookupMeta(ctx, tx)
			if rErr != nil {
				return rErr
			}
			obs, rErr = extractLongVegObservations(ctx, tx, owner, suByPlot, sppMeta, lumpMap)
			return rErr
		}); err != nil {
			return CSVExportOutcome{}, err
		}

		// Notice TotalA / TotalB overlap with A1..A3 / B1..B2c if both populated on a row:
		// To avoid double-counting TotalA alongside Cover1..3 in rollup_all / strata_4, check per (plot, species, strataGroup)
		type plotSppStrata struct {
			plot   string
			spp    string
			strata string
		}
		hasSublayerCover := map[plotSppStrata]bool{}
		for i, o := range obs {
			if i&1023 == 0 {
				if err := ctx.Err(); err != nil {
					return CSVExportOutcome{}, err
				}
			}
			if o.Layer != "A" && o.Layer != "B" {
				hasSublayerCover[plotSppStrata{o.PlotNumber, o.Species, o.StrataGroup}] = true
			}
		}

		colSet := map[string]struct{}{}
		sppSet := map[string]struct{}{}
		type matKey struct {
			plot string
			col  string
		}
		values := map[matKey]float64{}

		for i, o := range obs {
			if i&1023 == 0 {
				if err := ctx.Err(); err != nil {
					return CSVExportOutcome{}, err
				}
			}
			sppSet[o.Species] = struct{}{}
			if (mode == "rollup_all" || mode == "strata_4") && (o.Layer == "A" || o.Layer == "B") {
				if hasSublayerCover[plotSppStrata{o.PlotNumber, o.Species, o.StrataGroup}] {
					continue
				}
			}
			var colName string
			switch mode {
			case "rollup_all":
				colName = o.Species
			case "strata_4":
				colName = o.Species + "_" + o.StrataGroup
			case "species_layer":
				colName = o.Species + "_" + o.Layer
			}
			colSet[colName] = struct{}{}
			mk := matKey{plot: o.PlotNumber, col: colName}
			next := values[mk] + o.Cover
			if next > 99.0 {
				next = 99.0
			}
			values[mk] = math.Round(next*10000) / 10000
		}

		matrixCols := make([]string, 0, len(colSet))
		for c := range colSet {
			matrixCols = append(matrixCols, c)
		}
		slices.Sort(matrixCols)

		header := []string{"PlotNumber"}
		if request.IncludeSiteUnit {
			header = append(header, "SiteUnit")
		}
		header = append(header, matrixCols...)

		var buf bytes.Buffer
		w := csv.NewWriter(&buf)
		if err := w.Write(header); err != nil {
			return CSVExportOutcome{}, err
		}
		absentCell := ""
		if request.ZeroFill {
			absentCell = "0"
		}
		for pIdx, plot := range plotOrder {
			if pIdx&31 == 0 {
				if err := ctx.Err(); err != nil {
					return CSVExportOutcome{}, err
				}
			}
			row := make([]string, 0, len(header))
			row = append(row, plot)
			if request.IncludeSiteUnit {
				row = append(row, suByPlot[plot])
			}
			for _, col := range matrixCols {
				if v, ok := values[matKey{plot: plot, col: col}]; ok && v > 0 {
					row = append(row, strconv.FormatFloat(v, 'f', -1, 64))
				} else {
					row = append(row, absentCell)
				}
			}
			if err := w.Write(row); err != nil {
				return CSVExportOutcome{}, err
			}
		}
		w.Flush()
		if err := w.Error(); err != nil {
			return CSVExportOutcome{}, err
		}

		data := buf.Bytes()
		writtenPath, shaHex, err := writeAtomicExportFileContext(ctx, request.DestinationPath, data)
		if err != nil {
			return CSVExportOutcome{}, err
		}
		return CSVExportOutcome{
			Mode:         "wide_matrix_" + mode,
			RowCount:     len(plotOrder),
			PlotCount:    len(plotOrder),
			SpeciesCount: len(sppSet),
			ColumnCount:  len(header),
			Path:         writtenPath,
			SHA256:       shaHex,
			PreviewCSV:   truncateCSVPreview(data, 20),
		}, nil
	})
}
