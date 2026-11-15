package rsidecar

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

func constancyRomanClass(pct float64) string {
	switch {
	case pct > 80.0:
		return "V"
	case pct > 60.0:
		return "IV"
	case pct > 40.0:
		return "III"
	case pct > 20.0:
		return "II"
	default:
		return "I"
	}
}

func computeFiveNumberSummary(vals []float64) *FiveNumberBoxSummary {
	clean := make([]float64, 0, len(vals))
	for _, v := range vals {
		if !math.IsNaN(v) && !math.IsInf(v, 0) {
			clean = append(clean, v)
		}
	}
	if len(clean) == 0 {
		return &FiveNumberBoxSummary{N: 0}
	}
	sort.Float64s(clean)
	quantile := func(p float64) float64 {
		if len(clean) == 1 {
			return clean[0]
		}
		pos := p * float64(len(clean)-1)
		lo := int(math.Floor(pos))
		hi := int(math.Ceil(pos))
		if lo == hi {
			return clean[lo]
		}
		frac := pos - float64(lo)
		return clean[lo]*(1.0-frac) + clean[hi]*frac
	}
	round1 := func(x float64) float64 { return math.Round(x*10.0) / 10.0 }
	return &FiveNumberBoxSummary{
		N:      len(clean),
		Min:    round1(clean[0]),
		Q1:     round1(quantile(0.25)),
		Median: round1(quantile(0.50)),
		Q3:     round1(quantile(0.75)),
		Max:    round1(clean[len(clean)-1]),
	}
}

func computeAspectRose(aspects []float64) []AspectRoseSector {
	labels := []string{"N", "NE", "E", "SE", "S", "SW", "W", "NW"}
	counts := make([]int, 8)
	for _, a := range aspects {
		if math.IsNaN(a) || math.IsInf(a, 0) || a < 0 || a > 360 || a == 999 {
			continue
		}
		norm := math.Mod(a+360.0, 360.0)
		idx := int(math.Floor((norm+22.5)/45.0)) % 8
		counts[idx]++
	}
	out := make([]AspectRoseSector, 8)
	for i, lbl := range labels {
		out[i] = AspectRoseSector{Sector: lbl, Count: counts[i]}
	}
	return out
}

func combineStratumCovers(vals ...float64) float64 {
	prod := 1.0
	anyPos := false
	for _, v := range vals {
		if math.IsNaN(v) || v <= 0 {
			continue
		}
		clamped := math.Min(99.0, v)
		prod *= (1.0 - clamped/100.0)
		anyPos = true
	}
	if !anyPos {
		return 0.0
	}
	return 100.0 * (1.0 - prod)
}

func buildQuartoVegSummary(
	ctx context.Context,
	owner *vprocore.SqliteContext,
	plotNumbers []string,
	applyLump bool,
	minConstancyPct float64,
) ([]QuartoVegSummaryRow, error) {
	if len(plotNumbers) == 0 {
		return []QuartoVegSummaryRow{}, nil
	}
	if err := sqlutil.AcquireMutexLease(ctx, &owner.Mu); err != nil {
		return nil, err
	}
	defer owner.Mu.Unlock()
	if owner.Conn == nil {
		return nil, errors.New("project context is closed")
	}

	tx, err := owner.BeginReadSnapshot(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	vegSchema := "project"
	var projVegExists int
	_ = tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM project.sqlite_master WHERE type='table' AND name = ? COLLATE NOCASE`, owner.Selection.Project+"_Veg").Scan(&projVegExists)
	if projVegExists == 0 {
		vegSchema = "main"
	}

	// Optional lump map
	lumpMap := make(map[string]string)
	if applyLump {
		lumpTableName := owner.Selection.Project + "_Lump"
		var lumpExists int
		_ = tx.QueryRowContext(ctx, fmt.Sprintf(`SELECT COUNT(*) FROM %s.sqlite_master WHERE type='table' AND name = ? COLLATE NOCASE`, vegSchema), lumpTableName).Scan(&lumpExists)
		if lumpExists > 0 {
			lRows, lErr := tx.QueryContext(ctx, fmt.Sprintf(
				`SELECT UPPER(TRIM(CAST("SppCode" AS TEXT))), UPPER(TRIM(CAST("LumpCode" AS TEXT))), COALESCE("Use", 0) FROM %s.%s`,
				vegSchema, vprocore.QuoteHeaderIdentifier(lumpTableName),
			))
			if lErr == nil {
				for lRows.Next() {
					var spp, lump string
					var useFlag int
					if err := lRows.Scan(&spp, &lump, &useFlag); err == nil && useFlag != 0 && spp != "" && lump != "" {
						lumpMap[spp] = lump
					}
				}
				lRows.Close()
			}
		}
	}

	// Load VLists species names
	type sppNames struct {
		sci string
		eng string
	}
	nameMap := make(map[string]sppNames)
	sRows, sErr := tx.QueryContext(ctx, `
		SELECT UPPER(TRIM(CAST("Code" AS TEXT))),
		       COALESCE(CAST("ScientificName" AS TEXT), ''),
		       COALESCE(CAST("EnglishName" AS TEXT), '')
		  FROM VLists."USysAllSpecs"
		 WHERE COALESCE("Codetype", 'U') IN ('U', 'D')
	`)
	if sErr == nil {
		for sRows.Next() {
			var c, sci, eng string
			if err := sRows.Scan(&c, &sci, &eng); err == nil && c != "" {
				if _, exists := nameMap[c]; !exists {
					nameMap[c] = sppNames{sci: sci, eng: eng}
				}
			}
		}
		sRows.Close()
	}

	allowed := make(map[string]bool, len(plotNumbers))
	for _, p := range plotNumbers {
		allowed[p] = true
	}

	vegQuery := fmt.Sprintf(
		`SELECT CAST("PlotNumber" AS TEXT), UPPER(TRIM(CAST("Species" AS TEXT))),
		        COALESCE("Cover1",0), COALESCE("Cover2",0), COALESCE("Cover3",0), COALESCE("TotalA",0),
		        COALESCE("Cover4",0), COALESCE("Cover5",0), COALESCE("Cover5a",0), COALESCE("Cover5b",0), COALESCE("Cover5c",0), COALESCE("TotalB",0),
		        COALESCE("Cover6",0), COALESCE("Cover7",0), COALESCE("Cover8",0), COALESCE("Cover9",0), COALESCE("Cover10",0)
		   FROM %s.%s
		  WHERE typeof("PlotNumber")='text' AND TRIM(COALESCE("Species",'')) <> ''`,
		vegSchema, vprocore.QuoteHeaderIdentifier(owner.Selection.Project+"_Veg"),
	)
	vRows, err := tx.QueryContext(ctx, vegQuery)
	if err != nil {
		return nil, err
	}
	defer vRows.Close()

	// Aggregate cover per (LayerGroup, Species, PlotNumber)
	type cellKey struct {
		layerOrder int
		layerLabel string
		species    string
	}
	plotLayerCover := make(map[cellKey]map[string]float64)
	addCover := func(ord int, label, spp, plot string, cov float64) {
		if cov <= 0 {
			return
		}
		k := cellKey{layerOrder: ord, layerLabel: label, species: spp}
		mp := plotLayerCover[k]
		if mp == nil {
			mp = make(map[string]float64)
			plotLayerCover[k] = mp
		}
		mp[plot] = combineStratumCovers(mp[plot], cov)
	}

	for vRows.Next() {
		var plot, spp string
		var c1, c2, c3, ta, c4, c5, c5a, c5b, c5c, tb, c6, c7, c8, c9, c10 sql.NullFloat64
		if err := vRows.Scan(&plot, &spp, &c1, &c2, &c3, &ta, &c4, &c5, &c5a, &c5b, &c5c, &tb, &c6, &c7, &c8, &c9, &c10); err != nil {
			return nil, err
		}
		if !allowed[plot] || spp == "" {
			continue
		}
		if folded, ok := lumpMap[spp]; ok {
			spp = folded
		}
		treeCov := ta.Float64
		if treeCov <= 0 {
			treeCov = combineStratumCovers(c1.Float64, c2.Float64, c3.Float64)
		}
		shrubCov := tb.Float64
		if shrubCov <= 0 {
			shrubCov = combineStratumCovers(c4.Float64, c5.Float64, c5a.Float64, c5b.Float64, c5c.Float64)
		}
		herbCov := c6.Float64
		mossCov := combineStratumCovers(c7.Float64, c8.Float64, c9.Float64, c10.Float64)

		addCover(1, "Tree (A)", spp, plot, treeCov)
		addCover(2, "Shrub (B)", spp, plot, shrubCov)
		addCover(3, "Herb (C)", spp, plot, herbCov)
		addCover(4, "Moss/Lichen (D)", spp, plot, mossCov)
	}
	if err := vRows.Err(); err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}

	nTotal := float64(len(plotNumbers))
	type sortableRow struct {
		order int
		row   QuartoVegSummaryRow
	}
	var collected []sortableRow
	for k, mp := range plotLayerCover {
		presCnt := len(mp)
		constancy := (float64(presCnt) / nTotal) * 100.0
		if constancy < minConstancyPct {
			continue
		}
		covSum := 0.0
		for _, cv := range mp {
			covSum += cv
		}
		meanCov := covSum / float64(presCnt)
		nm := nameMap[k.species]
		sci := nm.sci
		if sci == "" {
			sci = k.species
		}
		collected = append(collected, sortableRow{
			order: k.layerOrder,
			row: QuartoVegSummaryRow{
				Layer:          k.layerLabel,
				Species:        k.species,
				ScientificName: sci,
				EnglishName:    nm.eng,
				ConstancyPct:   vprocore.RoundCalibratedDecimal(constancy, 1),
				ConstancyClass: constancyRomanClass(constancy),
				MeanCover:      vprocore.RoundCalibratedDecimal(meanCov, 2),
			},
		})
	}

	sort.Slice(collected, func(i, j int) bool {
		if collected[i].order != collected[j].order {
			return collected[i].order < collected[j].order
		}
		if collected[i].row.ConstancyPct != collected[j].row.ConstancyPct {
			return collected[i].row.ConstancyPct > collected[j].row.ConstancyPct
		}
		if collected[i].row.MeanCover != collected[j].row.MeanCover {
			return collected[i].row.MeanCover > collected[j].row.MeanCover
		}
		return collected[i].row.Species < collected[j].row.Species
	})

	out := make([]QuartoVegSummaryRow, len(collected))
	for i, item := range collected {
		out[i] = item.row
	}
	return out, nil
}

func sanitizeSlug(raw string) string {
	var b strings.Builder
	for _, r := range strings.TrimSpace(raw) {
		switch {
		case (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9'):
			b.WriteRune(r)
		case r == '-' || r == '_':
			b.WriteRune(r)
		default:
			b.WriteRune('_')
		}
	}
	res := strings.Trim(b.String(), "_")
	if res == "" {
		return "bec_guide"
	}
	return res
}

func canWriteExportDirectory(dir string) bool {
	if strings.TrimSpace(dir) == "" {
		return false
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return false
	}
	probe, err := os.CreateTemp(dir, ".vpro-export-probe-*")
	if err != nil {
		return false
	}
	name := probe.Name()
	_ = probe.Close()
	_ = os.Remove(name)
	return true
}

func resolveDefaultGuideExportPath(projectDir, configuredDataDir, filename string) string {
	projectExports := filepath.Join(projectDir, "exports")
	if canWriteExportDirectory(projectExports) {
		return filepath.Join(projectExports, filename)
	}
	if trimmed := strings.TrimSpace(configuredDataDir); trimmed != "" {
		return filepath.Join(trimmed, "exports", filename)
	}
	if resolvedDataDir, err := sqlutil.UserDataDir(); err == nil && strings.TrimSpace(resolvedDataDir) != "" {
		return filepath.Join(resolvedDataDir, "exports", filename)
	}
	return filepath.Join(projectExports, filename)
}

func publishBytesAtomically(destPath string, content []byte) (int64, string, error) {
	absDest, err := filepath.Abs(destPath)
	if err != nil {
		return 0, "", fmt.Errorf("resolve destination path %q: %w", destPath, err)
	}
	parentDir := filepath.Dir(absDest)
	if err := os.MkdirAll(parentDir, 0755); err != nil {
		return 0, "", fmt.Errorf("create destination directory %q: %w", parentDir, err)
	}

	var randTok [6]byte
	_, _ = rand.Read(randTok[:])
	stageFile := filepath.Join(parentDir, fmt.Sprintf(".%s.stage-%s", filepath.Base(absDest), hex.EncodeToString(randTok[:])))
	f, err := os.OpenFile(stageFile, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0644)
	if err != nil {
		return 0, "", fmt.Errorf("open atomic staging file %q: %w", stageFile, err)
	}
	cleanupStage := true
	defer func() {
		if cleanupStage {
			_ = os.Remove(stageFile)
		}
	}()

	if _, err := f.Write(content); err != nil {
		_ = f.Close()
		return 0, "", err
	}
	if err := f.Sync(); err != nil {
		_ = f.Close()
		return 0, "", err
	}
	if err := f.Close(); err != nil {
		return 0, "", err
	}
	if err := os.Rename(stageFile, absDest); err != nil {
		return 0, "", fmt.Errorf("atomic rename to %q: %w", absDest, err)
	}
	cleanupStage = false

	sum := sha256.Sum256(content)
	return int64(len(content)), hex.EncodeToString(sum[:]), nil
}
