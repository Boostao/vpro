package projectops

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"slices"
	"strings"

	"github.com/boostao/vpro/app/internal/vprocore"
)

type vegGroupKey struct {
	plot    string
	species string
}

func buildOptimizeVegPlan(ctx context.Context, db sqliteQueryer, project string, filterPlots []string, custodianAuditOverride bool) (OptimizeVegPreview, []plannedVegConsolidation, []string, error) {
	if err := validateOptimizeVegProjectSchema(ctx, db, project); err != nil {
		return OptimizeVegPreview{}, nil, nil, err
	}

	envTable := project + "_Env"
	vegTable := project + "_Veg"
	auditTable := project + "_Audit"
	quotedEnv := vprocore.QuoteHeaderIdentifier(envTable)
	quotedVeg := vprocore.QuoteHeaderIdentifier(vegTable)
	quotedAudit := vprocore.QuoteHeaderIdentifier(auditTable)

	colRows, err := db.QueryContext(ctx, "SELECT * FROM "+quotedVeg+" LIMIT 0")
	if err != nil {
		return OptimizeVegPreview{}, nil, nil, err
	}
	defer colRows.Close()
	cols, colErr := colRows.Columns()
	if colErr != nil {
		return OptimizeVegPreview{}, nil, nil, colErr
	}

	cntRows, err := db.QueryContext(ctx, "SELECT COUNT(*) FROM "+quotedVeg)
	if err != nil {
		return OptimizeVegPreview{}, nil, nil, err
	}
	var beforeRowCount int
	if scanErr := func() (scanErr error) {
		defer func() { scanErr = errors.Join(scanErr, cntRows.Close()) }()
		if cntRows.Next() {
			if err := cntRows.Scan(&beforeRowCount); err != nil {

				return err
			}
		}
		return cntRows.Err()
	}(); scanErr != nil {
		return OptimizeVegPreview{}, nil, nil, scanErr
	}

	plotFilter := map[string]bool{}
	var sortedFilterPlots []string
	for _, p := range filterPlots {
		if strings.TrimSpace(p) != "" && !plotFilter[p] {
			plotFilter[p] = true
			sortedFilterPlots = append(sortedFilterPlots, p)
		}
	}
	slices.Sort(sortedFilterPlots)

	dupKeys := map[vegGroupKey]bool{}
	dupPlotsSet := map[string]bool{}
	var dupPlots []string
	var groupOrder []vegGroupKey

	dupKeyQuery := `SELECT CAST("PlotNumber" AS BLOB), CAST("Species" AS BLOB) FROM ` + quotedVeg + `
		WHERE typeof("PlotNumber")='text' AND typeof("Species")='text'
		  AND "PlotNumber" <> '' AND "Species" <> ''
		GROUP BY "PlotNumber" COLLATE BINARY, "Species" COLLATE BINARY
		HAVING COUNT(*) > 1`
	dupKeyRows, err := db.QueryContext(ctx, dupKeyQuery)
	if err != nil {
		return OptimizeVegPreview{}, nil, nil, err
	}
	if err := func() (scanErr error) {
		defer func() { scanErr = errors.Join(scanErr, dupKeyRows.Close()) }()
		for dupKeyRows.Next() {
			if err := ctx.Err(); err != nil {

				return err
			}
			var plotBytes, sppBytes []byte
			if err := dupKeyRows.Scan(&plotBytes, &sppBytes); err != nil {

				return err
			}
			plot := string(plotBytes)
			spp := string(sppBytes)
			if len(plotFilter) > 0 && !plotFilter[plot] {
				continue
			}
			gk := vegGroupKey{plot: plot, species: spp}
			if !dupKeys[gk] {
				dupKeys[gk] = true
				groupOrder = append(groupOrder, gk)
			}
			if !dupPlotsSet[plot] {
				dupPlotsSet[plot] = true
				dupPlots = append(dupPlots, plot)
			}
		}
		return dupKeyRows.Err()
	}(); err != nil {
		return OptimizeVegPreview{}, nil, nil, err
	}

	slices.Sort(dupPlots)
	slices.SortFunc(groupOrder, func(a, b vegGroupKey) int {
		if c := strings.Compare(a.plot, b.plot); c != 0 {
			return c
		}
		return strings.Compare(a.species, b.species)
	})

	envFound := map[string]bool{}
	envLocked := map[string]bool{}
	if len(dupPlots) > 0 {
		const batchSize = 400
		for start := 0; start < len(dupPlots); start += batchSize {
			end := min(start+batchSize, len(dupPlots))
			chunk := dupPlots[start:end]
			marks := make([]string, len(chunk))
			args := make([]any, len(chunk))
			for i, p := range chunk {
				marks[i] = "?"
				args[i] = p
			}
			eq := `SELECT CAST("PlotNumber" AS BLOB), COALESCE("Flag", 0) FROM ` + quotedEnv +
				` WHERE typeof("PlotNumber")='text' AND "PlotNumber" IN (` + strings.Join(marks, ",") + `)`
			eRows, eErr := db.QueryContext(ctx, eq, args...)
			if eErr != nil {
				return OptimizeVegPreview{}, nil, nil, eErr
			}
			if err := func() (scanErr error) {
				defer func() { scanErr = errors.Join(scanErr, eRows.Close()) }()
				for eRows.Next() {
					var pb []byte
					var flagVal int64
					if err := eRows.Scan(&pb, &flagVal); err != nil {

						return err
					}
					p := string(pb)
					envFound[p] = true
					if flagVal != 0 {
						envLocked[p] = true
					}
				}
				return eRows.Err()
			}(); err != nil {
				return OptimizeVegPreview{}, nil, nil, err
			}
		}
		for _, p := range dupPlots {
			if !envFound[p] {
				return OptimizeVegPreview{}, nil, nil, fmt.Errorf("OptimizeVeg refused: vegetation plot %q does not exist in %s", p, envTable)
			}
		}
	}

	plotColIdx, sppColIdx := -1, -1
	selectParts := []string{"rowid"}
	for i, c := range cols {
		if c == "PlotNumber" {
			plotColIdx = i
		} else if c == "Species" {
			sppColIdx = i
		}
		q := vprocore.QuoteHeaderIdentifier(c)
		selectParts = append(selectParts,
			"typeof("+q+")",
			"CASE typeof("+q+") WHEN 'integer' THEN CAST("+q+" AS INTEGER) WHEN 'real' THEN CAST("+q+" AS REAL) ELSE CAST("+q+" AS BLOB) END",
		)
	}

	var dupRows []vegRowWithRowID
	if len(dupPlots) > 0 && plotColIdx >= 0 && sppColIdx >= 0 {
		const batchSize = 400
		storages := make([]string, len(cols))
		vals := make([]any, len(cols))
		var rid int64
		dest := make([]any, 0, 1+len(cols)*2)
		dest = append(dest, &rid)
		for i := range cols {
			dest = append(dest, &storages[i], &vals[i])
		}

		for start := 0; start < len(dupPlots); start += batchSize {
			end := min(start+batchSize, len(dupPlots))
			chunk := dupPlots[start:end]
			marks := make([]string, len(chunk))
			args := make([]any, len(chunk))
			for i, p := range chunk {
				marks[i] = "?"
				args[i] = p
			}
			q := "SELECT " + strings.Join(selectParts, ", ") + " FROM " + quotedVeg +
				` WHERE typeof("PlotNumber")='text' AND typeof("Species")='text' AND "PlotNumber" IN (` + strings.Join(marks, ",") + `) ORDER BY rowid`
			rows, qErr := db.QueryContext(ctx, q, args...)
			if qErr != nil {
				return OptimizeVegPreview{}, nil, nil, qErr
			}
			if err := func() (scanErr error) {
				defer func() { scanErr = errors.Join(scanErr, rows.Close()) }()
				for rows.Next() {
					if err := ctx.Err(); err != nil {

						return err
					}
					if err := rows.Scan(dest...); err != nil {

						return err
					}
					if storages[plotColIdx] != "text" || storages[sppColIdx] != "text" {
						continue
					}
					var plot, spp string
					switch b := vals[plotColIdx].(type) {
					case []byte:
						plot = string(b)
					case string:
						plot = b
					}
					switch b := vals[sppColIdx].(type) {
					case []byte:
						spp = string(b)
					case string:
						spp = b
					}
					if !dupKeys[vegGroupKey{plot: plot, species: spp}] {
						continue
					}

					cellMap := make(map[string]rawSQLiteCell, len(cols))
					for i, col := range cols {
						c := rawSQLiteCell{storage: storages[i]}
						switch storages[i] {
						case "integer":
							if v, ok := vals[i].(int64); ok {
								c.intVal = v
							}
						case "real":
							if v, ok := vals[i].(float64); ok {
								c.realVal = v
							}
						case "text", "blob":
							switch b := vals[i].(type) {
							case []byte:
								c.bytes = append([]byte(nil), b...)
							case string:
								c.bytes = []byte(b)
							}
						}
						cellMap[col] = c
					}
					dupRows = append(dupRows, vegRowWithRowID{rowID: rid, cells: cellMap})
				}
				return rows.Err()
			}(); err != nil {
				return OptimizeVegPreview{}, nil, nil, err
			}
		}
	}

	slices.SortFunc(dupRows, func(a, b vegRowWithRowID) int {
		aID, bID := a.cells["ID"].intVal, b.cells["ID"].intVal
		if aID < bID {
			return -1
		}
		if aID > bID {
			return 1
		}
		if a.rowID < b.rowID {
			return -1
		}
		if a.rowID > b.rowID {
			return 1
		}
		return 0
	})

	digestHasher := sha256.New()
	_, _ = fmt.Fprintf(digestHasher, "count:%d|filters:%s|auditOverride:%t|", beforeRowCount, strings.Join(sortedFilterPlots, ","), custodianAuditOverride)
	for _, p := range dupPlots {
		if envLocked[p] {
			_, _ = fmt.Fprintf(digestHasher, "locked:%s|", p)
		}
	}
	grouped := make(map[vegGroupKey][]vegRowWithRowID, len(groupOrder))
	for _, r := range dupRows {
		_, _ = fmt.Fprintf(digestHasher, "row:%d|", r.rowID)
		for _, col := range cols {
			c := r.cells[col]
			switch c.storage {
			case "integer":
				_, _ = fmt.Fprintf(digestHasher, "%s=i:%d;", col, c.intVal)
			case "real":
				_, _ = fmt.Fprintf(digestHasher, "%s=r:%g;", col, c.realVal)
			case "text", "blob":
				_, _ = fmt.Fprintf(digestHasher, "%s=%s:%x;", col, c.storage, c.bytes)
			default:
				_, _ = fmt.Fprintf(digestHasher, "%s=null;", col)
			}
		}
		gk := vegGroupKey{plot: string(r.cells["PlotNumber"].bytes), species: string(r.cells["Species"].bytes)}
		grouped[gk] = append(grouped[gk], r)
	}

	preview := OptimizeVegPreview{
		Project:            project,
		BeforeRowCount:     beforeRowCount,
		AfterRowCount:      beforeRowCount,
		OldToSurvivorIDMap: map[int64]int64{},
		Groups:             []OptimizeVegGroup{},
	}
	var plans []plannedVegConsolidation

	// Precompute all retired IDs to query <P>_Audit in bulk before building final group summaries.
	type auditLookupTarget struct {
		plot       string
		species    string
		survivorID int64
	}
	retiredTargetByID := map[int64]auditLookupTarget{}
	var allRetiredIDs []int64
	for _, gk := range groupOrder {
		members := grouped[gk]
		if len(members) <= 1 {
			continue
		}
		survivorID := members[0].cells["ID"].intVal
		for _, dup := range members[1:] {
			dupID := dup.cells["ID"].intVal
			retiredTargetByID[dupID] = auditLookupTarget{plot: gk.plot, species: gk.species, survivorID: survivorID}
			allRetiredIDs = append(allRetiredIDs, dupID)
		}
	}

	auditRefsByKey := map[vegGroupKey][]OptimizeVegAuditRef{}
	if len(allRetiredIDs) > 0 {
		const batchSize = 400
		for start := 0; start < len(allRetiredIDs); start += batchSize {
			end := min(start+batchSize, len(allRetiredIDs))
			chunk := allRetiredIDs[start:end]
			marks := make([]string, len(chunk))
			args := make([]any, 0, len(chunk)+1)
			for i, id := range chunk {
				marks[i] = "?"
				args = append(args, id)
			}
			args = append(args, vegTable)
			aq := `SELECT COALESCE(CAST("PlotNumber" AS TEXT), ''), COALESCE("Table", ''), COALESCE("EditField", ''), COALESCE("EditWhen", ''), "ID"
				FROM ` + quotedAudit + `
				WHERE typeof("ID") = 'integer' AND "ID" IN (` + strings.Join(marks, ",") + `)
				  AND (LOWER(COALESCE("Table", '')) IN ('_veg', 'veg', LOWER(?)) OR COALESCE("Table", '') = '')
				ORDER BY "EditWhen", rowid`
			aRows, aErr := db.QueryContext(ctx, aq, args...)
			if aErr != nil {
				return OptimizeVegPreview{}, nil, nil, aErr
			}
			if err := func() (scanErr error) {
				defer func() { scanErr = errors.Join(scanErr, aRows.Close()) }()
				for aRows.Next() {
					var aPlot, aTable, aField, aWhen string
					var aID int64
					if err := aRows.Scan(&aPlot, &aTable, &aField, &aWhen, &aID); err != nil {

						return err
					}
					tgt, ok := retiredTargetByID[aID]
					if !ok {
						continue
					}
					_, _ = fmt.Fprintf(digestHasher, "audit:%d:%s:%s:%s|", aID, aTable, aField, aWhen)
					ref := OptimizeVegAuditRef{
						PlotNumber: tgt.plot,
						Species:    tgt.species,
						RetiredID:  aID,
						Table:      aTable,
						EditField:  aField,
						EditWhen:   aWhen,
					}
					gk := vegGroupKey{plot: tgt.plot, species: tgt.species}
					auditRefsByKey[gk] = append(auditRefsByKey[gk], ref)
				}
				return aRows.Err()
			}(); err != nil {
				return OptimizeVegPreview{}, nil, nil, err
			}
		}
	}

	preview.PreviewDigest = hex.EncodeToString(digestHasher.Sum(nil))

	coveredCols := map[string]bool{
		"PlotNumber": true, "Species": true, "ID": true,
		"HeightB": true, "Layer": true, "Collected": true, "Flag": true,
	}
	for _, col := range vegCoverCols {
		coveredCols[col] = true
	}
	for _, col := range vegNumericHeightCols {
		coveredCols[col] = true
	}
	for _, col := range vegFirstIntCols {
		coveredCols[col] = true
	}

	for _, gk := range groupOrder {
		members := grouped[gk]
		if len(members) <= 1 {
			continue
		}
		plans = append(plans, resolveOptimizeVegGroup(
			gk, members, cols, coveredCols, envLocked, auditRefsByKey[gk], custodianAuditOverride, &preview,
		))
	}

	return preview, plans, cols, nil
}
