package lumping

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"math"
	"slices"
	"strings"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

func resolveActualLumpTable(ctx context.Context, db *sql.DB, requested string) (string, error) {
	_, tableName, err := normalizeLumpBaseName(requested)
	if err != nil {
		return "", err
	}
	var actual string
	if err := db.QueryRowContext(ctx, `SELECT name FROM sqlite_master WHERE type='table' AND name COLLATE NOCASE=?`, tableName).Scan(&actual); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", fmt.Errorf("lump table %s does not exist", tableName)
		}
		return "", err
	}
	return actual, nil
}

func readRawLumpRowsFromDB(ctx context.Context, dbPath, tableName string) ([]LumpRow, string, string, error) {
	resolved, err := vprocore.ExistingDatabasePath(dbPath)
	if err != nil {
		return nil, "", "", err
	}
	db, err := sqlutil.OpenReadOnlyContext(ctx, resolved)
	if err != nil {
		return nil, "", "", err
	}
	defer db.Close()

	actual, err := resolveActualLumpTable(ctx, db, tableName)
	if err != nil {
		return nil, "", "", err
	}
	quoted := vprocore.QuoteHeaderIdentifier(actual)
	rows, err := db.QueryContext(ctx, `SELECT COALESCE(LumpCode,''), COALESCE(SppCode,''), CASE WHEN "Use" IS NULL THEN NULL WHEN typeof("Use")='text' THEN "Use" ELSE CAST("Use" AS INTEGER) END FROM `+quoted+` ORDER BY LumpCode COLLATE NOCASE, SppCode COLLATE NOCASE`)
	if err != nil {
		return nil, "", "", err
	}
	defer rows.Close()

	result := []LumpRow{}
	for rows.Next() {
		var lc, sc string
		var rawUse any
		if err := rows.Scan(&lc, &sc, &rawUse); err != nil {
			return nil, "", "", err
		}
		result = append(result, LumpRow{
			LumpCode: strings.ToUpper(strings.TrimSpace(lc)),
			SppCode:  strings.ToUpper(strings.TrimSpace(sc)),
			Use:      normalizeAccessBool(rawUse),
		})
	}
	return result, actual, resolved, rows.Err()
}

func GetLumpTableRows(s *vprocore.ContextService, ctx context.Context, contextID, tableName, dbPath string) ([]LumpRow, error) {
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) ([]LumpRow, error) {
		owner := plots.Projects.Sqlite
		targetPath := strings.TrimSpace(dbPath)
		if targetPath == "" {
			targetPath = owner.Selection.ProjectPath
		}
		rawRows, _, _, err := readRawLumpRowsFromDB(ctx, targetPath, tableName)
		if err != nil {
			return nil, err
		}

		catalog, err := vprocore.WithReadSnapshotValue(ctx, owner, func(tx *sql.Tx) (map[string]speciesTaxonomyEntry, error) {
			cat, _, err := loadTaxonomyCatalog(ctx, tx)
			return cat, err
		})
		if err != nil {
			return nil, err
		}
		for i := range rawRows {
			rawRows[i] = enrichLumpRow(rawRows[i], catalog)
		}
		return rawRows, nil
	})
}

func resolveConnLumpTable(ctx context.Context, wtx *vprocore.WriteTx, requested string) (string, error) {
	_, tableName, err := normalizeLumpBaseName(requested)
	if err != nil {
		return "", err
	}
	var actual string
	if err := wtx.QueryRowContext(ctx, `SELECT name FROM sqlite_master WHERE type='table' AND name COLLATE NOCASE=?`, tableName).Scan(&actual); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", fmt.Errorf("lump table %s does not exist in the active project", tableName)
		}
		return "", err
	}
	return actual, nil
}

func UpsertLumpRow(s *vprocore.ContextService, ctx context.Context, contextID, tableName string, input LumpRowInput) (LumpRow, error) {
	lumpCode, sppCode, err := ValidateLumpCodes(input.LumpCode, input.SppCode)
	if err != nil {
		return LumpRow{}, err
	}
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (LumpRow, error) {
		owner := plots.Projects.Sqlite
		catalog, _, err := loadCatalogForContext(ctx, owner)
		if err != nil {
			return LumpRow{}, err
		}
		if _, ok := catalog[sppCode]; !ok && !input.AllowUnlisted {
			return LumpRow{}, fmt.Errorf("species code %q was not found in VLists.USysAllSpecs or VUser.USysUserSpp", sppCode)
		}
		if err := withImmediateProjectWriteTx(ctx, owner, func(wtx *vprocore.WriteTx) error {
			actual, tErr := resolveConnLumpTable(ctx, wtx, tableName)
			if tErr != nil {
				return tErr
			}
			quoted := vprocore.QuoteHeaderIdentifier(actual)
			var existingSpp string
			qErr := wtx.QueryRowContext(ctx, `SELECT SppCode FROM `+quoted+` WHERE SppCode COLLATE NOCASE=?`, sppCode).Scan(&existingSpp)
			if qErr == nil {
				_, uErr := wtx.ExecContext(ctx, `UPDATE `+quoted+` SET "LumpCode"=?, "SppCode"=?, "Use"=? WHERE SppCode COLLATE NOCASE=?`,
					lumpCode, sppCode, accessBoolToInt(input.Use), existingSpp)
				return uErr
			}
			if !errors.Is(qErr, sql.ErrNoRows) {
				return qErr
			}
			_, iErr := wtx.ExecContext(ctx, `INSERT INTO `+quoted+` ("LumpCode", "SppCode", "Use") VALUES (?, ?, ?)`,
				lumpCode, sppCode, accessBoolToInt(input.Use))
			return iErr
		}); err != nil {
			return LumpTableRowZero(), err
		}
		return enrichLumpRow(LumpRow{LumpCode: lumpCode, SppCode: sppCode, Use: input.Use}, catalog), nil
	})
}

func LumpTableRowZero() LumpRow { return LumpRow{} }

func UpdateLumpRow(s *vprocore.ContextService, ctx context.Context, contextID, tableName, existingSppCode string, input LumpRowInput) (LumpRow, error) {
	lumpCode, sppCode, err := ValidateLumpCodes(input.LumpCode, input.SppCode)
	if err != nil {
		return LumpRow{}, err
	}
	oldKey := strings.ToUpper(strings.TrimSpace(existingSppCode))
	if oldKey == "" {
		return LumpRow{}, errors.New("existing SppCode is required for update")
	}
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (LumpRow, error) {
		owner := plots.Projects.Sqlite
		catalog, _, err := loadCatalogForContext(ctx, owner)
		if err != nil {
			return LumpRow{}, err
		}
		if _, ok := catalog[sppCode]; !ok && !input.AllowUnlisted {
			return LumpRow{}, fmt.Errorf("species code %q was not found in VLists.USysAllSpecs or VUser.USysUserSpp", sppCode)
		}
		if err := withImmediateProjectWriteTx(ctx, owner, func(wtx *vprocore.WriteTx) error {
			actual, tErr := resolveConnLumpTable(ctx, wtx, tableName)
			if tErr != nil {
				return tErr
			}
			quoted := vprocore.QuoteHeaderIdentifier(actual)
			if !strings.EqualFold(oldKey, sppCode) {
				var conflict bool
				if err := wtx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM `+quoted+` WHERE SppCode COLLATE NOCASE=?)`, sppCode).Scan(&conflict); err != nil {
					return err
				}
				if conflict {
					return fmt.Errorf("species code %q already exists in %s", sppCode, actual)
				}
			}
			res, uErr := wtx.ExecContext(ctx, `UPDATE `+quoted+` SET "LumpCode"=?, "SppCode"=?, "Use"=? WHERE SppCode COLLATE NOCASE=?`,
				lumpCode, sppCode, accessBoolToInt(input.Use), oldKey)
			if uErr != nil {
				return uErr
			}
			affected, aErr := res.RowsAffected()
			if aErr != nil {
				return aErr
			}
			if affected == 0 {
				return fmt.Errorf("species code %q was not found in %s", oldKey, actual)
			}
			return nil
		}); err != nil {
			return LumpRow{}, err
		}
		return enrichLumpRow(LumpRow{LumpCode: lumpCode, SppCode: sppCode, Use: input.Use}, catalog), nil
	})
}

func DeleteLumpRow(s *vprocore.ContextService, ctx context.Context, contextID, tableName, sppCode string) error {
	target := strings.ToUpper(strings.TrimSpace(sppCode))
	if target == "" {
		return errors.New("SppCode is required for delete")
	}
	_, err := vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (struct{}, error) {
		owner := plots.Projects.Sqlite
		return struct{}{}, withImmediateProjectWriteTx(ctx, owner, func(wtx *vprocore.WriteTx) error {
			actual, err := resolveConnLumpTable(ctx, wtx, tableName)
			if err != nil {
				return err
			}
			res, err := wtx.ExecContext(ctx, `DELETE FROM `+vprocore.QuoteHeaderIdentifier(actual)+` WHERE SppCode COLLATE NOCASE=?`, target)
			if err != nil {
				return err
			}
			affected, err := res.RowsAffected()
			if err != nil {
				return err
			}
			if affected == 0 {
				return fmt.Errorf("species code %q was not found in %s", target, actual)
			}
			return nil
		})
	})
	return err
}

func ToggleLumpRow(s *vprocore.ContextService, ctx context.Context, contextID, tableName, sppCode string, use bool) (LumpRow, error) {
	target := strings.ToUpper(strings.TrimSpace(sppCode))
	if target == "" {
		return LumpRow{}, errors.New("SppCode is required for toggle")
	}
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (LumpRow, error) {
		owner := plots.Projects.Sqlite
		var lumpCode, storedSpp string
		if err := withImmediateProjectWriteTx(ctx, owner, func(wtx *vprocore.WriteTx) error {
			actual, err := resolveConnLumpTable(ctx, wtx, tableName)
			if err != nil {
				return err
			}
			quoted := vprocore.QuoteHeaderIdentifier(actual)
			if err := wtx.QueryRowContext(ctx, `SELECT LumpCode, SppCode FROM `+quoted+` WHERE SppCode COLLATE NOCASE=?`, target).Scan(&lumpCode, &storedSpp); err != nil {
				if errors.Is(err, sql.ErrNoRows) {
					return fmt.Errorf("species code %q was not found in %s", target, actual)
				}
				return err
			}
			_, err = wtx.ExecContext(ctx, `UPDATE `+quoted+` SET "Use"=? WHERE SppCode COLLATE NOCASE=?`, accessBoolToInt(use), storedSpp)
			return err
		}); err != nil {
			return LumpRow{}, err
		}
		catalog, _, err := loadCatalogForContext(ctx, owner)
		if err != nil {
			return LumpRow{}, err
		}
		return enrichLumpRow(LumpRow{LumpCode: strings.ToUpper(strings.TrimSpace(lumpCode)), SppCode: strings.ToUpper(strings.TrimSpace(storedSpp)), Use: use}, catalog), nil
	})
}

func SetAllLumpRowsUse(s *vprocore.ContextService, ctx context.Context, contextID, tableName string, use bool) (int, error) {
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (int, error) {
		owner := plots.Projects.Sqlite
		var updated int
		err := withImmediateProjectWriteTx(ctx, owner, func(wtx *vprocore.WriteTx) error {
			actual, err := resolveConnLumpTable(ctx, wtx, tableName)
			if err != nil {
				return err
			}
			res, err := wtx.ExecContext(ctx, `UPDATE `+vprocore.QuoteHeaderIdentifier(actual)+` SET "Use"=?`, accessBoolToInt(use))
			if err != nil {
				return err
			}
			n, err := res.RowsAffected()
			updated = int(n)
			return err
		})
		return updated, err
	})
}

var vegCoverLayerColumns = []string{
	"Cover1", "Cover2", "Cover3", "TotalA",
	"Cover4", "Cover5", "Cover5a", "Cover5b", "Cover5c", "TotalB",
	"Cover6", "Cover7", "Cover8", "Cover9", "Cover10",
}

func computeFoldingImpactFromTx(ctx context.Context, tx *sql.Tx, project string, activeMap map[string]string, tableName, dbPath string) (LumpImpactPreview, error) {
	preview := LumpImpactPreview{
		TableName:    tableName,
		DatabasePath: dbPath,
		CoverCap:     FoldedCoverCap,
		Groups:       []LumpGroupImpact{},
	}

	if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM USysEnv`).Scan(&preview.TotalPlots); err != nil {
		return preview, err
	}

	vegTable := "project." + vprocore.QuoteHeaderIdentifier(project+"_Veg")
	query := `SELECT v.PlotNumber, v.Species, ` + strings.Join(vegCoverLayerColumns, ", ") + `
		FROM ` + vegTable + ` AS v
		WHERE EXISTS (SELECT 1 FROM USysEnv AS e WHERE typeof(e.PlotNumber)=typeof(v.PlotNumber) AND CAST(e.PlotNumber AS BLOB)=CAST(v.PlotNumber AS BLOB))`

	rows, err := tx.QueryContext(ctx, query)
	if err != nil {
		return preview, fmt.Errorf("read project vegetation for impact preview: %w", err)
	}
	defer rows.Close()

	rawSpeciesSet := map[string]struct{}{}
	foldedSpeciesSet := map[string]struct{}{}
	foldedSourceSpp := map[string]struct{}{}

	type cellKey struct {
		plot  string
		layer int
		code  string
	}
	type cellAcc struct {
		sumCover float64
		count    int
		lumped   bool
	}
	cells := map[cellKey]*cellAcc{}

	type groupStat struct {
		sources  map[string]struct{}
		plots    map[string]struct{}
		rawObs   int
		maxCover float64
		capped   int
		folded   int
	}
	groups := map[string]*groupStat{}

	narrowCover := func(cv sql.NullFloat64) (float64, bool) {
		if !cv.Valid {
			return 0, false
		}
		s := float32(cv.Float64)
		if math.IsNaN(float64(s)) || math.IsInf(float64(s), 0) || s < 0 {
			return 0, false
		}
		return float64(s), true
	}

	for rows.Next() {
		var plot, spp string
		var covers [15]sql.NullFloat64
		dest := []any{&plot, &spp}
		for i := range covers {
			dest = append(dest, &covers[i])
		}
		if err := rows.Scan(dest...); err != nil {
			return preview, err
		}
		rawCode := strings.ToUpper(strings.TrimSpace(spp))
		if rawCode == "" {
			continue
		}
		targetCode, isFolded := activeMap[rawCode]
		if !isFolded || targetCode == "" {
			targetCode = rawCode
		} else {
			foldedSourceSpp[rawCode] = struct{}{}
		}

		// Match Synthesis sublayer_sum precedence (Cover1..Cover3 over TotalA;
		// Cover4..Cover5c over TotalB) so populated stratum totals are never
		// double-counted alongside populated sublayers (UX-CLASS-003).
		hasSubA := false
		for i := 0; i <= 2; i++ {
			if _, ok := narrowCover(covers[i]); ok {
				hasSubA = true
				break
			}
		}
		hasSubB := false
		for i := 4; i <= 8; i++ {
			if _, ok := narrowCover(covers[i]); ok {
				hasSubB = true
				break
			}
		}

		hasPositiveLayer := false
		for layerIdx, cv := range covers {
			if (layerIdx == 3 && hasSubA) || (layerIdx == 9 && hasSubB) {
				continue
			}
			narrowed, ok := narrowCover(cv)
			if !ok || narrowed <= 0 {
				continue
			}
			hasPositiveLayer = true
			preview.RawObservations++
			ck := cellKey{plot: plot, layer: layerIdx, code: targetCode}
			acc := cells[ck]
			if acc == nil {
				acc = &cellAcc{}
				cells[ck] = acc
			}
			acc.sumCover += narrowed
			acc.count++
			if isFolded {
				acc.lumped = true
			}

			if isFolded {
				gs := groups[targetCode]
				if gs == nil {
					gs = &groupStat{sources: map[string]struct{}{}, plots: map[string]struct{}{}}
					groups[targetCode] = gs
				}
				gs.sources[rawCode] = struct{}{}
				gs.plots[plot] = struct{}{}
				gs.rawObs++
			}
		}
		if !hasPositiveLayer {
			// Still count presence-only row as one observation in layer -1
			preview.RawObservations++
			ck := cellKey{plot: plot, layer: -1, code: targetCode}
			acc := cells[ck]
			if acc == nil {
				acc = &cellAcc{}
				cells[ck] = acc
			}
			acc.count++
			if isFolded {
				acc.lumped = true
				gs := groups[targetCode]
				if gs == nil {
					gs = &groupStat{sources: map[string]struct{}{}, plots: map[string]struct{}{}}
					groups[targetCode] = gs
				}
				gs.sources[rawCode] = struct{}{}
				gs.plots[plot] = struct{}{}
				gs.rawObs++
			}
		}
		rawSpeciesSet[rawCode] = struct{}{}
		foldedSpeciesSet[targetCode] = struct{}{}
	}
	if err := rows.Err(); err != nil {
		return preview, err
	}

	preview.DistinctRawSpecies = len(rawSpeciesSet)
	preview.DistinctFoldedSpecies = len(foldedSpeciesSet)
	preview.SpeciesFoldedCount = len(foldedSourceSpp)
	preview.FoldedObservations = len(cells)

	for ck, acc := range cells {
		if acc.count > 1 {
			preview.MergedCells++
		}
		cappedVal := acc.sumCover
		wasCapped := false
		isFoldedCell := (len(activeMap) > 0 && acc.lumped) || acc.count > 1
		if isFoldedCell && cappedVal > FoldedCoverCap {
			cappedVal = FoldedCoverCap
			wasCapped = true
			preview.CappedCells++
		}
		if gs, ok := groups[ck.code]; ok {
			gs.folded++
			if cappedVal > gs.maxCover {
				gs.maxCover = cappedVal
			}
			if wasCapped {
				gs.capped++
			}
		}
	}

	for code, gs := range groups {
		srcs := make([]string, 0, len(gs.sources))
		for src := range gs.sources {
			srcs = append(srcs, src)
		}
		slices.Sort(srcs)
		preview.Groups = append(preview.Groups, LumpGroupImpact{
			LumpCode:           code,
			SourceSpecies:      srcs,
			PlotCount:          len(gs.plots),
			RawObservations:    gs.rawObs,
			FoldedObservations: gs.folded,
			MaxFoldedCover:     math.Round(gs.maxCover*100) / 100,
			CappedCells:        gs.capped,
		})
	}
	slices.SortFunc(preview.Groups, func(a, b LumpGroupImpact) int {
		if a.PlotCount != b.PlotCount {
			return b.PlotCount - a.PlotCount
		}
		return strings.Compare(a.LumpCode, b.LumpCode)
	})
	return preview, nil
}

func PreviewLumpImpact(s *vprocore.ContextService, ctx context.Context, contextID, tableName, dbPath string) (LumpImpactPreview, error) {
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (LumpImpactPreview, error) {
		owner := plots.Projects.Sqlite
		targetPath := strings.TrimSpace(dbPath)
		if targetPath == "" {
			targetPath = owner.Selection.ProjectPath
		}
		activeMap := map[string]string{}
		resolvedTable := strings.TrimSpace(tableName)
		resolvedPath := targetPath
		if resolvedTable != "" && !strings.EqualFold(resolvedTable, "None") && !strings.EqualFold(resolvedTable, "None_Lump") {
			rows, actual, rPath, err := readRawLumpRowsFromDB(ctx, targetPath, resolvedTable)
			if err != nil {
				return LumpImpactPreview{}, err
			}
			resolvedTable = actual
			resolvedPath = rPath
			for _, r := range rows {
				if r.Use && r.SppCode != "" && r.LumpCode != "" && !strings.EqualFold(r.SppCode, r.LumpCode) {
					activeMap[r.SppCode] = r.LumpCode
				}
			}
		}

		return vprocore.WithReadSnapshotValue(ctx, owner, func(tx *sql.Tx) (LumpImpactPreview, error) {
			return computeFoldingImpactFromTx(ctx, tx, owner.Selection.Project, activeMap, resolvedTable, resolvedPath)
		})
	})
}
