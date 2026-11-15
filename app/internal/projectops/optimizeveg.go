package projectops

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type OptimizeVegOptions struct {
	PlotNumbers            []string `json:"plotNumbers,omitempty"`
	CustodianAuditOverride bool     `json:"custodianAuditOverride,omitempty"`
}

func (r *OptimizeVegOptions) UnmarshalJSON(data []byte) error {
	type plain OptimizeVegOptions
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type OptimizeVegConflict struct {
	PlotNumber   string   `json:"plotNumber"`
	Species      string   `json:"species"`
	Field        string   `json:"field"`
	Reason       string   `json:"reason"`
	Values       []string `json:"values,omitempty"`
	SourceIDs    []int64  `json:"sourceIds,omitempty"`
	Overrideable bool     `json:"overrideable,omitempty"`
}

type OptimizeVegAuditRef struct {
	PlotNumber string `json:"plotNumber"`
	Species    string `json:"species"`
	RetiredID  int64  `json:"retiredId"`
	Table      string `json:"table"`
	EditField  string `json:"editField"`
	EditWhen   string `json:"editWhen"`
}

type OptimizeVegFieldDiff struct {
	Field    string            `json:"field"`
	Proposed *string           `json:"proposed,omitempty"`
	Before   map[int64]*string `json:"before,omitempty"`
}

type OptimizeVegGroup struct {
	PlotNumber                string                 `json:"plotNumber"`
	Species                   string                 `json:"species"`
	SourceRowCount            int                    `json:"sourceRowCount"`
	SurvivorID                int64                  `json:"survivorId"`
	RetiredIDs                []int64                `json:"retiredIds"`
	OldToSurvivorIDMap        map[int64]int64        `json:"oldToSurvivorIdMap,omitempty"`
	HasOverlappingLayerCovers bool                   `json:"hasOverlappingLayerCovers"`
	CappedCoverColumns        []string               `json:"cappedCoverColumns"`
	MergedCovers              map[string]float64     `json:"mergedCovers"`
	MergedHeights             map[string]float64     `json:"mergedHeights"`
	MergedHeightB             *string                `json:"mergedHeightB,omitempty"`
	FieldDiffs                []OptimizeVegFieldDiff `json:"fieldDiffs,omitempty"`
	Conflicts                 []OptimizeVegConflict  `json:"conflicts,omitempty"`
	AuditReferences           []OptimizeVegAuditRef  `json:"auditReferences,omitempty"`
	Blocked                   bool                   `json:"blocked,omitempty"`
	BlockedReasons            []string               `json:"blockedReasons,omitempty"`
}

type OptimizeVegPreview struct {
	Project               string                `json:"project"`
	BeforeRowCount        int                   `json:"beforeRowCount"`
	AfterRowCount         int                   `json:"afterRowCount"`
	RowsToConsolidate     int                   `json:"rowsToConsolidate"`
	DuplicateSpeciesCount int                   `json:"duplicateSpeciesCount"`
	OverlappingGroupCount int                   `json:"overlappingGroupCount"`
	CappedCoverCount      int                   `json:"cappedCoverCount"`
	BlockedGroupCount     int                   `json:"blockedGroupCount"`
	HasBlockingConflicts  bool                  `json:"hasBlockingConflicts"`
	PreviewDigest         string                `json:"previewDigest"`
	OldToSurvivorIDMap    map[int64]int64       `json:"oldToSurvivorIdMap,omitempty"`
	Conflicts             []OptimizeVegConflict `json:"conflicts,omitempty"`
	AuditReferences       []OptimizeVegAuditRef `json:"auditReferences,omitempty"`
	Groups                []OptimizeVegGroup    `json:"groups"`
}

type ApplyOptimizeVegRequest struct {
	PlotNumbers            []string `json:"plotNumbers,omitempty"`
	ExpectedDigest         string   `json:"expectedDigest,omitempty"`
	CustodianAuditOverride bool     `json:"custodianAuditOverride,omitempty"`
}

func (r *ApplyOptimizeVegRequest) UnmarshalJSON(data []byte) error {
	type plain ApplyOptimizeVegRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type OptimizeVegResult struct {
	Project            string             `json:"project"`
	BeforeRowCount     int                `json:"beforeRowCount"`
	AfterRowCount      int                `json:"afterRowCount"`
	ConsolidatedGroups int                `json:"consolidatedGroups"`
	DeletedRows        int                `json:"deletedRows"`
	ReservedDeletedIDs []int64            `json:"reservedDeletedIds"`
	OldToSurvivorIDMap map[int64]int64    `json:"oldToSurvivorIdMap,omitempty"`
	AuditRowsWritten   int                `json:"auditRowsWritten"`
	Groups             []OptimizeVegGroup `json:"groups"`
}

var vegCoverCols = []string{
	"Cover1", "Cover2", "Cover3", "TotalA",
	"Cover4", "Cover5", "Cover5a", "Cover5b", "Cover5c", "TotalB",
	"Cover6", "Cover7", "Cover8", "Cover9", "Cover10",
}

var vegNumericHeightCols = []string{
	"Height1", "Height2", "Height3", "HeightA",
	"Height4", "Height5", "Height5a", "Height5b", "Height5c",
	"Height6",
}

var vegFirstIntCols = []string{
	"LL", "AF", "DC", "UT", "VI", "PV", "PG", "FFA",
	"Cultural1", "Cultural2", "Other1", "Other2",
}

const (
	vegSignedInt32Min = int64(-2147483648)
	vegSignedInt32Max = int64(2147483647)
)

type plannedVegConsolidation struct {
	group          OptimizeVegGroup
	survivorRowID  int64
	deletedRowIDs  []int64
	deletedPhysIDs []int64
	survivorBefore map[string]rawSQLiteCell
	survivorAfter  map[string]rawSQLiteCell
	deletedBefore  []map[string]rawSQLiteCell
}

type vegRowWithRowID struct {
	rowID int64
	cells map[string]rawSQLiteCell
}

func strPtrFromAuditVal(v any) *string {
	if v == nil {
		return nil
	}
	s := fmt.Sprint(v)
	return &s
}

func resolveVegTextConsensus(members []vegRowWithRowID, col, plot, species string) (rawSQLiteCell, *OptimizeVegConflict) {
	seen := map[string]bool{}
	var vals []string
	var ids []int64
	var chosen rawSQLiteCell
	hasVal := false
	for _, m := range members {
		c := m.cells[col]
		if c.storage == "null" {
			continue
		}
		var txt string
		switch c.storage {
		case "text":
			txt = string(c.bytes)
		case "integer":
			txt = strconv.FormatInt(c.intVal, 10)
		case "real":
			txt = vprocore.SourceDoubleDecimalString(c.realVal)
		case "blob":
			txt = hex.EncodeToString(c.bytes)
		default:
			continue
		}
		if strings.TrimSpace(txt) == "" {
			continue
		}
		if !hasVal {
			hasVal = true
			chosen = rawSQLiteCell{storage: c.storage, intVal: c.intVal, realVal: c.realVal, bytes: append([]byte(nil), c.bytes...)}
		}
		if !seen[txt] {
			seen[txt] = true
			vals = append(vals, txt)
		}
		if idCell := m.cells["ID"]; idCell.storage == "integer" {
			ids = append(ids, idCell.intVal)
		}
	}
	if !hasVal {
		return rawSQLiteCell{storage: "null"}, nil
	}
	if len(vals) > 1 {
		return rawSQLiteCell{storage: "null"}, &OptimizeVegConflict{
			PlotNumber: plot,
			Species:    species,
			Field:      col,
			Reason:     fmt.Sprintf("conflicting non-null %s values (%s)", col, strings.Join(vals, " vs ")),
			Values:     vals,
			SourceIDs:  ids,
		}
	}
	return chosen, nil
}

func resolveVegIntConsensus(members []vegRowWithRowID, col, plot, species string) (rawSQLiteCell, *OptimizeVegConflict) {
	seen := map[string]bool{}
	var vals []string
	var ids []int64
	var chosen rawSQLiteCell
	hasVal := false
	for _, m := range members {
		c := m.cells[col]
		if c.storage == "null" {
			continue
		}
		var key, disp string
		switch c.storage {
		case "integer":
			disp = strconv.FormatInt(c.intVal, 10)
			key = "i:" + disp
		case "real":
			disp = vprocore.SourceDoubleDecimalString(c.realVal)
			key = "r:" + disp
		case "text":
			disp = string(c.bytes)
			if strings.TrimSpace(disp) == "" {
				continue
			}
			key = "t:" + disp
		case "blob":
			disp = hex.EncodeToString(c.bytes)
			key = "b:" + disp
		default:
			continue
		}
		if !hasVal {
			hasVal = true
			chosen = rawSQLiteCell{storage: c.storage, intVal: c.intVal, realVal: c.realVal, bytes: append([]byte(nil), c.bytes...)}
		}
		if !seen[key] {
			seen[key] = true
			vals = append(vals, disp)
		}
		if idCell := m.cells["ID"]; idCell.storage == "integer" {
			ids = append(ids, idCell.intVal)
		}
	}
	if !hasVal {
		return rawSQLiteCell{storage: "null"}, nil
	}
	if len(vals) > 1 {
		return rawSQLiteCell{storage: "null"}, &OptimizeVegConflict{
			PlotNumber: plot,
			Species:    species,
			Field:      col,
			Reason:     fmt.Sprintf("conflicting non-null %s values (%s)", col, strings.Join(vals, " vs ")),
			Values:     vals,
			SourceIDs:  ids,
		}
	}
	return chosen, nil
}

func validateOptimizeVegProjectSchema(ctx context.Context, db sqliteQueryer, project string) error {
	envTable := project + "_Env"
	vegTable := project + "_Veg"
	auditTable := project + "_Audit"
	existing := map[string]bool{}
	tRows, err := db.QueryContext(ctx, `SELECT name FROM sqlite_master WHERE type='table' AND name IN (?, ?, ?, '_table_metadata')`,
		envTable, vegTable, auditTable)
	if err != nil {
		return err
	}
	for tRows.Next() {
		var name string
		if err := tRows.Scan(&name); err != nil {
			_ = tRows.Close()
			return err
		}
		existing[name] = true
	}
	if err := errors.Join(tRows.Err(), tRows.Close()); err != nil {
		return err
	}
	for _, req := range []string{envTable, vegTable, auditTable} {
		if !existing[req] {
			return fmt.Errorf("OptimizeVeg refused: required VP08 table %s is missing", req)
		}
	}
	if existing["_table_metadata"] {
		for _, req := range []string{envTable, vegTable, auditTable} {
			mRows, mErr := db.QueryContext(ctx, `SELECT COALESCE(description, '') FROM "_table_metadata" WHERE table_name = ? LIMIT 1`, req)
			if mErr != nil {
				return mErr
			}
			var desc string
			found := mRows.Next()
			if found {
				if err := mRows.Scan(&desc); err != nil {
					_ = mRows.Close()
					return err
				}
			}
			if err := errors.Join(mRows.Err(), mRows.Close()); err != nil {
				return err
			}
			if !found {
				return fmt.Errorf("OptimizeVeg refused: table %s lacks VP08 version stamp in _table_metadata", req)
			}
			if strings.TrimSpace(desc) != "VP08" {
				return fmt.Errorf("OptimizeVeg refused: table %s has version %q in _table_metadata; expected VP08", req, desc)
			}
		}
	}

	quotedVeg := vprocore.QuoteHeaderIdentifier(vegTable)
	badRows, err := db.QueryContext(ctx, `SELECT rowid, typeof("ID"), COALESCE(CAST("ID" AS TEXT), '<null>') FROM `+quotedVeg+`
		WHERE typeof("ID") <> 'integer' OR "ID" < ? OR "ID" > ? LIMIT 1`,
		vegSignedInt32Min, vegSignedInt32Max)
	if err != nil {
		return err
	}
	if badRows.Next() {
		var rid int64
		var typ, raw string
		scanErr := badRows.Scan(&rid, &typ, &raw)
		_ = badRows.Close()
		if scanErr != nil {
			return scanErr
		}
		return fmt.Errorf("OptimizeVeg refused: rowid %d in %s has invalid or non-32-bit ID (%s=%s); all vegetation rows must carry non-null unique signed 32-bit IDs",
			rid, vegTable, typ, raw)
	}
	if err := errors.Join(badRows.Err(), badRows.Close()); err != nil {
		return err
	}

	dupIDRows, err := db.QueryContext(ctx, `SELECT "ID", COUNT(*) FROM `+quotedVeg+` GROUP BY "ID" HAVING COUNT(*) > 1 LIMIT 1`)
	if err != nil {
		return err
	}
	if dupIDRows.Next() {
		var dupID int64
		var cnt int
		scanErr := dupIDRows.Scan(&dupID, &cnt)
		_ = dupIDRows.Close()
		if scanErr != nil {
			return scanErr
		}
		return fmt.Errorf("OptimizeVeg refused: duplicate ID %d appears %d times in %s; every row must have a unique signed 32-bit ID",
			dupID, cnt, vegTable)
	}
	if err := errors.Join(dupIDRows.Err(), dupIDRows.Close()); err != nil {
		return err
	}
	return nil
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
	cols, colErr := colRows.Columns()
	_ = colRows.Close()
	if colErr != nil {
		return OptimizeVegPreview{}, nil, nil, colErr
	}

	cntRows, err := db.QueryContext(ctx, "SELECT COUNT(*) FROM "+quotedVeg)
	if err != nil {
		return OptimizeVegPreview{}, nil, nil, err
	}
	var beforeRowCount int
	if cntRows.Next() {
		if err := cntRows.Scan(&beforeRowCount); err != nil {
			_ = cntRows.Close()
			return OptimizeVegPreview{}, nil, nil, err
		}
	}
	if err := errors.Join(cntRows.Err(), cntRows.Close()); err != nil {
		return OptimizeVegPreview{}, nil, nil, err
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

	type groupKey struct {
		plot    string
		species string
	}
	dupKeys := map[groupKey]bool{}
	dupPlotsSet := map[string]bool{}
	var dupPlots []string
	var groupOrder []groupKey

	dupKeyQuery := `SELECT CAST("PlotNumber" AS BLOB), CAST("Species" AS BLOB) FROM ` + quotedVeg + `
		WHERE typeof("PlotNumber")='text' AND typeof("Species")='text'
		  AND "PlotNumber" <> '' AND "Species" <> ''
		GROUP BY "PlotNumber" COLLATE BINARY, "Species" COLLATE BINARY
		HAVING COUNT(*) > 1`
	dupKeyRows, err := db.QueryContext(ctx, dupKeyQuery)
	if err != nil {
		return OptimizeVegPreview{}, nil, nil, err
	}
	for dupKeyRows.Next() {
		if err := ctx.Err(); err != nil {
			_ = dupKeyRows.Close()
			return OptimizeVegPreview{}, nil, nil, err
		}
		var plotBytes, sppBytes []byte
		if err := dupKeyRows.Scan(&plotBytes, &sppBytes); err != nil {
			_ = dupKeyRows.Close()
			return OptimizeVegPreview{}, nil, nil, err
		}
		plot := string(plotBytes)
		spp := string(sppBytes)
		if len(plotFilter) > 0 && !plotFilter[plot] {
			continue
		}
		gk := groupKey{plot: plot, species: spp}
		if !dupKeys[gk] {
			dupKeys[gk] = true
			groupOrder = append(groupOrder, gk)
		}
		if !dupPlotsSet[plot] {
			dupPlotsSet[plot] = true
			dupPlots = append(dupPlots, plot)
		}
	}
	if err := errors.Join(dupKeyRows.Err(), dupKeyRows.Close()); err != nil {
		return OptimizeVegPreview{}, nil, nil, err
	}

	slices.Sort(dupPlots)
	slices.SortFunc(groupOrder, func(a, b groupKey) int {
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
			for eRows.Next() {
				var pb []byte
				var flagVal int64
				if err := eRows.Scan(&pb, &flagVal); err != nil {
					_ = eRows.Close()
					return OptimizeVegPreview{}, nil, nil, err
				}
				p := string(pb)
				envFound[p] = true
				if flagVal != 0 {
					envLocked[p] = true
				}
			}
			if err := errors.Join(eRows.Err(), eRows.Close()); err != nil {
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
			for rows.Next() {
				if err := ctx.Err(); err != nil {
					_ = rows.Close()
					return OptimizeVegPreview{}, nil, nil, err
				}
				if err := rows.Scan(dest...); err != nil {
					_ = rows.Close()
					return OptimizeVegPreview{}, nil, nil, err
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
				if !dupKeys[groupKey{plot: plot, species: spp}] {
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
			if err := errors.Join(rows.Err(), rows.Close()); err != nil {
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
	grouped := make(map[groupKey][]vegRowWithRowID, len(groupOrder))
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
		gk := groupKey{plot: string(r.cells["PlotNumber"].bytes), species: string(r.cells["Species"].bytes)}
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

	auditRefsByKey := map[groupKey][]OptimizeVegAuditRef{}
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
			for aRows.Next() {
				var aPlot, aTable, aField, aWhen string
				var aID int64
				if err := aRows.Scan(&aPlot, &aTable, &aField, &aWhen, &aID); err != nil {
					_ = aRows.Close()
					return OptimizeVegPreview{}, nil, nil, err
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
				gk := groupKey{plot: tgt.plot, species: tgt.species}
				auditRefsByKey[gk] = append(auditRefsByKey[gk], ref)
			}
			if err := errors.Join(aRows.Err(), aRows.Close()); err != nil {
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
		survivor := members[0]
		survivorLogicalID := survivor.cells["ID"].intVal

		afterCells := make(map[string]rawSQLiteCell, len(cols))
		for k, v := range survivor.cells {
			afterCells[k] = v
		}

		mergedCovers := map[string]float64{}
		mergedHeights := map[string]float64{}
		var cappedCols []string
		var conflicts []OptimizeVegConflict
		var blockedReasons []string
		overlapping := false

		// Rule 3: Independent non-null MAX on numeric cover columns.
		for _, col := range vegCoverCols {
			if _, hasCol := survivor.cells[col]; !hasCol {
				continue
			}
			countNonNull := 0
			var maxVal float64
			for _, m := range members {
				c := m.cells[col]
				if c.storage == "null" {
					continue
				}
				var val float64
				switch c.storage {
				case "real":
					val = c.realVal
				case "integer":
					val = float64(c.intVal)
				default:
					continue
				}
				if math.IsNaN(val) || math.IsInf(val, 0) {
					continue
				}
				if countNonNull == 0 || val > maxVal {
					maxVal = val
				}
				countNonNull++
			}
			if countNonNull == 0 {
				afterCells[col] = rawSQLiteCell{storage: "null"}
				continue
			}
			if countNonNull > 1 {
				overlapping = true
			}
			finalCover := maxVal
			if finalCover >= 0 {
				if _, ok := NarrowSingleCover(finalCover); !ok {
					finalCover = 99.0
					cappedCols = append(cappedCols, col)
				}
			}
			afterCells[col] = rawSQLiteCell{storage: "real", realVal: finalCover}
			mergedCovers[col] = finalCover
		}

		// Rule 3: Independent non-null MAX on numeric height columns.
		for _, col := range vegNumericHeightCols {
			if _, hasCol := survivor.cells[col]; !hasCol {
				continue
			}
			hasVal := false
			var maxVal float64
			for _, m := range members {
				c := m.cells[col]
				if c.storage == "null" {
					continue
				}
				var val float64
				switch c.storage {
				case "real":
					val = c.realVal
				case "integer":
					val = float64(c.intVal)
				default:
					continue
				}
				if math.IsNaN(val) || math.IsInf(val, 0) {
					continue
				}
				if !hasVal || val > maxVal {
					maxVal = val
					hasVal = true
				}
			}
			if !hasVal {
				afterCells[col] = rawSQLiteCell{storage: "null"}
			} else {
				afterCells[col] = rawSQLiteCell{storage: "real", realVal: maxVal}
				mergedHeights[col] = maxVal
			}
		}

		// Rule 3: HeightB (VARCHAR) uses consensus-or-block on non-null values.
		var mergedHeightBPtr *string
		if _, hasHB := survivor.cells["HeightB"]; hasHB {
			chosenHB, conflict := resolveVegTextConsensus(members, "HeightB", gk.plot, gk.species)
			if conflict != nil {
				conflicts = append(conflicts, *conflict)
				afterCells["HeightB"] = survivor.cells["HeightB"]
			} else {
				afterCells["HeightB"] = chosenHB
				if chosenHB.storage != "null" {
					s := fmt.Sprint(auditTextForRawCell(chosenHB))
					mergedHeightBPtr = &s
				}
			}
		}

		// Rule 4: Layer, Collected, Flag, LL..Other2 (and any extra columns) use consensus-or-block.
		for _, textCol := range []string{"Layer", "Collected"} {
			if _, hasCol := survivor.cells[textCol]; !hasCol {
				continue
			}
			chosen, conflict := resolveVegTextConsensus(members, textCol, gk.plot, gk.species)
			if conflict != nil {
				conflicts = append(conflicts, *conflict)
				afterCells[textCol] = survivor.cells[textCol]
			} else {
				afterCells[textCol] = chosen
			}
		}

		if _, hasFlag := survivor.cells["Flag"]; hasFlag {
			chosen, conflict := resolveVegIntConsensus(members, "Flag", gk.plot, gk.species)
			if conflict != nil {
				conflicts = append(conflicts, *conflict)
				afterCells["Flag"] = survivor.cells["Flag"]
			} else {
				afterCells["Flag"] = chosen
			}
		}

		for _, col := range vegFirstIntCols {
			if _, hasCol := survivor.cells[col]; !hasCol {
				continue
			}
			chosen, conflict := resolveVegIntConsensus(members, col, gk.plot, gk.species)
			if conflict != nil {
				conflicts = append(conflicts, *conflict)
				afterCells[col] = survivor.cells[col]
			} else {
				afterCells[col] = chosen
			}
		}

		for _, col := range cols {
			if coveredCols[col] {
				continue
			}
			chosen, conflict := resolveVegIntConsensus(members, col, gk.plot, gk.species)
			if conflict != nil {
				conflicts = append(conflicts, *conflict)
				afterCells[col] = survivor.cells[col]
			} else {
				afterCells[col] = chosen
			}
		}

		// Rule 5: Locked plot check (Env.Flag != 0) cannot be overridden.
		if envLocked[gk.plot] {
			msg := fmt.Sprintf("plot %q is locked (Env.Flag != 0)", gk.plot)
			blockedReasons = append(blockedReasons, msg)
			conflicts = append(conflicts, OptimizeVegConflict{
				PlotNumber:   gk.plot,
				Species:      gk.species,
				Field:        "Env.Flag",
				Reason:       msg,
				SourceIDs:    []int64{survivorLogicalID},
				Overrideable: false,
			})
		}

		var retiredIDs []int64
		var deletedRowIDs []int64
		var deletedBefore []map[string]rawSQLiteCell
		oldToSurvivor := make(map[int64]int64, len(members)-1)
		for _, dup := range members[1:] {
			deletedRowIDs = append(deletedRowIDs, dup.rowID)
			deletedBefore = append(deletedBefore, dup.cells)
			dupID := dup.cells["ID"].intVal
			retiredIDs = append(retiredIDs, dupID)
			oldToSurvivor[dupID] = survivorLogicalID
			preview.OldToSurvivorIDMap[dupID] = survivorLogicalID
		}

		auditRefs := auditRefsByKey[gk]
		if len(auditRefs) > 0 && !custodianAuditOverride {
			refIDSet := map[int64]bool{}
			var refIDs []int64
			for _, ref := range auditRefs {
				if !refIDSet[ref.RetiredID] {
					refIDSet[ref.RetiredID] = true
					refIDs = append(refIDs, ref.RetiredID)
				}
			}
			slices.Sort(refIDs)
			msg := fmt.Sprintf("%d _Audit event(s) reference retired vegetation IDs %v; requires CustodianAuditOverride confirmation", len(auditRefs), refIDs)
			blockedReasons = append(blockedReasons, msg)
			conflicts = append(conflicts, OptimizeVegConflict{
				PlotNumber:   gk.plot,
				Species:      gk.species,
				Field:        "Audit.ID",
				Reason:       msg,
				SourceIDs:    refIDs,
				Overrideable: true,
			})
		}

		var fieldDiffs []OptimizeVegFieldDiff
		for _, col := range cols {
			if col == "PlotNumber" || col == "Species" {
				continue
			}
			changed := !rawCellsEqual(survivor.cells[col], afterCells[col])
			differsAcross := false
			for _, dup := range members[1:] {
				if !rawCellsEqual(survivor.cells[col], dup.cells[col]) {
					differsAcross = true
					break
				}
			}
			if !changed && !differsAcross {
				continue
			}
			beforeMap := make(map[int64]*string, len(members))
			for _, m := range members {
				beforeMap[m.cells["ID"].intVal] = strPtrFromAuditVal(auditTextForRawCell(m.cells[col]))
			}
			fieldDiffs = append(fieldDiffs, OptimizeVegFieldDiff{
				Field:    col,
				Proposed: strPtrFromAuditVal(auditTextForRawCell(afterCells[col])),
				Before:   beforeMap,
			})
		}

		blocked := len(conflicts) > 0 || len(blockedReasons) > 0
		if blocked && len(blockedReasons) == 0 && len(conflicts) > 0 {
			for _, c := range conflicts {
				blockedReasons = append(blockedReasons, c.Reason)
			}
		}

		grp := OptimizeVegGroup{
			PlotNumber:                gk.plot,
			Species:                   gk.species,
			SourceRowCount:            len(members),
			SurvivorID:                survivorLogicalID,
			RetiredIDs:                retiredIDs,
			OldToSurvivorIDMap:        oldToSurvivor,
			HasOverlappingLayerCovers: overlapping,
			CappedCoverColumns:        cappedCols,
			MergedCovers:              mergedCovers,
			MergedHeights:             mergedHeights,
			MergedHeightB:             mergedHeightBPtr,
			FieldDiffs:                fieldDiffs,
			Conflicts:                 conflicts,
			AuditReferences:           auditRefs,
			Blocked:                   blocked,
			BlockedReasons:            blockedReasons,
		}
		preview.Groups = append(preview.Groups, grp)
		preview.DuplicateSpeciesCount++
		preview.RowsToConsolidate += len(members) - 1
		preview.AfterRowCount -= len(members) - 1
		if overlapping {
			preview.OverlappingGroupCount++
		}
		preview.CappedCoverCount += len(cappedCols)
		if blocked {
			preview.BlockedGroupCount++
			preview.HasBlockingConflicts = true
			preview.Conflicts = append(preview.Conflicts, conflicts...)
		}
		if len(auditRefs) > 0 {
			preview.AuditReferences = append(preview.AuditReferences, auditRefs...)
		}

		plans = append(plans, plannedVegConsolidation{
			group:          grp,
			survivorRowID:  survivor.rowID,
			deletedRowIDs:  deletedRowIDs,
			deletedPhysIDs: retiredIDs,
			survivorBefore: survivor.cells,
			survivorAfter:  afterCells,
			deletedBefore:  deletedBefore,
		})
	}

	return preview, plans, cols, nil
}

// PreviewOptimizeVeg computes a non-destructive preview of consolidating split/duplicate
// (PlotNumber, Species) rows in <Project>_Veg.
func PreviewOptimizeVeg(s *vprocore.ContextService, ctx context.Context, contextID string, opts OptimizeVegOptions) (OptimizeVegPreview, error) {
	snap, err := inspectContextSnapshot(ctx, s, contextID)
	if err != nil {
		return OptimizeVegPreview{}, err
	}
	db, err := sqlutil.OpenReadOnlyContext(ctx, snap.ProjectPath)
	if err != nil {
		return OptimizeVegPreview{}, err
	}
	defer db.Close()
	tx, err := db.BeginTx(ctx, &sql.TxOptions{ReadOnly: true})
	if err != nil {
		return OptimizeVegPreview{}, err
	}
	defer func() { _ = tx.Rollback() }()

	preview, _, _, err := buildOptimizeVegPlan(ctx, tx, snap.Project, opts.PlotNumbers, opts.CustodianAuditOverride)
	return preview, err
}

func rawCellsEqual(a, b rawSQLiteCell) bool {
	if a.storage != b.storage {
		return false
	}
	switch a.storage {
	case "null":
		return true
	case "integer":
		return a.intVal == b.intVal
	case "real":
		return math.Float64bits(a.realVal) == math.Float64bits(b.realVal)
	case "text", "blob":
		return string(a.bytes) == string(b.bytes)
	default:
		return false
	}
}

func auditTextForRawCell(c rawSQLiteCell) any {
	switch c.storage {
	case "null":
		return nil
	case "integer":
		return strconv.FormatInt(c.intVal, 10)
	case "real":
		return vprocore.SourceDoubleDecimalString(c.realVal)
	case "text":
		return string(c.bytes)
	case "blob":
		return hex.EncodeToString(c.bytes)
	default:
		return nil
	}
}

// ApplyOptimizeVeg executes multi-row (PlotNumber, Species) consolidation inside a single
// BEGIN IMMEDIATE transaction, reserving all retired child IDs in __VPRO_ChildIdentity
// and writing full <Project>_Audit records.
func ApplyOptimizeVeg(s *vprocore.ContextService, ctx context.Context, contextID string, req ApplyOptimizeVegRequest) (OptimizeVegResult, error) {
	if s == nil {
		return OptimizeVegResult{}, errors.New("project context service is unavailable")
	}
	var out OptimizeVegResult
	err := s.Edit(contextID, func(plots *vprocore.PlotService) error {
		owner := plots.Projects.Sqlite
		user := strings.TrimSpace(plots.CurrentUser)
		if user == "" {
			user = "VProUser"
		}
		return owner.WithMetadataWriter(ctx, func(conn *sql.Conn) (txErr error) {
			tx, err := conn.BeginTx(ctx, nil)
			if err != nil {
				return err
			}
			defer func() {
				if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
					txErr = errors.Join(txErr, rb)
				}
			}()

			project := owner.Selection.Project
			preview, plans, cols, err := buildOptimizeVegPlan(ctx, tx, project, req.PlotNumbers, req.CustodianAuditOverride)
			if err != nil {
				return err
			}
			if expected := strings.TrimSpace(req.ExpectedDigest); expected != "" && expected != preview.PreviewDigest {
				return errors.New("vegetation table changed since preview; re-run PreviewOptimizeVeg before applying")
			}
			if preview.HasBlockingConflicts || len(preview.Conflicts) > 0 {
				return fmt.Errorf("OptimizeVeg refused: %d blocking conflict(s) across %d group(s); first: %s",
					len(preview.Conflicts), preview.BlockedGroupCount, preview.Conflicts[0].Reason)
			}
			if len(plans) == 0 {
				out = OptimizeVegResult{
					Project:            project,
					BeforeRowCount:     preview.BeforeRowCount,
					AfterRowCount:      preview.AfterRowCount,
					ReservedDeletedIDs: []int64{},
					OldToSurvivorIDMap: map[int64]int64{},
					Groups:             []OptimizeVegGroup{},
				}
				return nil
			}

			if err := ensureChildIdentityTable(ctx, tx); err != nil {
				return err
			}

			vegTable := project + "_Veg"
			quotedVeg := vprocore.QuoteHeaderIdentifier(vegTable)
			quotedAudit := vprocore.QuoteHeaderIdentifier(project + "_Audit")
			now := time.Now().Format("2006-01-02 15:04:05")

			auditStmt, err := tx.PrepareContext(ctx, `INSERT INTO `+quotedAudit+` ("Project","User","PlotNumber","Table","EditField","EditWhen","BeforeEdit","AfterEdit","Restore","Flag","ID") VALUES (?,?,?,?,?,?,?,?,0,0,?)`)
			if err != nil {
				return err
			}
			defer auditStmt.Close()

			var allReserved []int64
			oldToSurvivorAll := map[int64]int64{}
			deletedCount := 0
			auditCount := 0

			for i := range plans {
				if err := ctx.Err(); err != nil {
					return err
				}
				plan := &plans[i]
				survivorID := plan.group.SurvivorID
				if err := reserveChildID(ctx, tx, vegTable, survivorID); err != nil {
					return err
				}

				// Update changed columns on survivor row using explicit column names.
				var setParts []string
				var updateArgs []any
				for _, col := range cols {
					if col == "PlotNumber" || col == "Species" || col == "ID" {
						continue
					}
					beforeCell := plan.survivorBefore[col]
					afterCell := plan.survivorAfter[col]
					if rawCellsEqual(beforeCell, afterCell) {
						continue
					}
					setParts = append(setParts, vprocore.QuoteHeaderIdentifier(col)+" = ?")
					updateArgs = append(updateArgs, afterCell.sqlParam())
					if _, err := auditStmt.ExecContext(ctx, project, user, plan.group.PlotNumber, "_Veg", col, now,
						auditTextForRawCell(beforeCell), auditTextForRawCell(afterCell), survivorID); err != nil {
						return err
					}
					auditCount++
				}
				if len(setParts) > 0 {
					updateArgs = append(updateArgs, plan.survivorRowID)
					uRes, uErr := tx.ExecContext(ctx, "UPDATE "+quotedVeg+" SET "+strings.Join(setParts, ", ")+" WHERE rowid = ?", updateArgs...)
					if uErr != nil {
						return uErr
					}
					if n, _ := uRes.RowsAffected(); n != 1 {
						return errors.New("OptimizeVeg survivor row update did not match 1 row")
					}
				}

				// Delete duplicate rows and permanently reserve their IDs in __VPRO_ChildIdentity.
				for dIdx, dupRowID := range plan.deletedRowIDs {
					dupCells := plan.deletedBefore[dIdx]
					dupID := dupCells["ID"].intVal
					if dupID != survivorID {
						if err := reserveChildID(ctx, tx, vegTable, dupID); err != nil {
							return err
						}
						allReserved = append(allReserved, dupID)
						oldToSurvivorAll[dupID] = survivorID
					}
					for _, col := range cols {
						if col == "ID" || col == "PlotNumber" {
							continue
						}
						beforeCell := dupCells[col]
						if beforeCell.storage == "null" || (col == "Flag" && beforeCell.storage == "integer" && beforeCell.intVal == 0) {
							continue
						}
						if _, err := auditStmt.ExecContext(ctx, project, user, plan.group.PlotNumber, "_Veg", col, now,
							auditTextForRawCell(beforeCell), nil, dupID); err != nil {
							return err
						}
						auditCount++
					}
					dRes, dErr := tx.ExecContext(ctx, "DELETE FROM "+quotedVeg+" WHERE rowid = ?", dupRowID)
					if dErr != nil {
						return dErr
					}
					if n, _ := dRes.RowsAffected(); n != 1 {
						return errors.New("OptimizeVeg duplicate row delete did not match 1 row")
					}
					deletedCount++
				}
			}

			// Verify post-mutation row count matches preview plan before commit.
			var actualAfterCount int
			if err := tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM "+quotedVeg).Scan(&actualAfterCount); err != nil {
				return err
			}
			if actualAfterCount != preview.AfterRowCount {
				return fmt.Errorf("OptimizeVeg row count check failed: got %d, expected %d", actualAfterCount, preview.AfterRowCount)
			}

			// Record a project-level OptimizeVeg provenance receipt in Audit (with old-to-survivor ID map).
			summaryJSON, _ := json.Marshal(map[string]any{
				"consolidatedGroups":     len(plans),
				"deletedRows":            deletedCount,
				"oldToSurvivorIdMap":     oldToSurvivorAll,
				"custodianAuditOverride": req.CustodianAuditOverride,
			})
			if _, err := tx.ExecContext(ctx, `INSERT INTO `+quotedAudit+` ("Project","User","Table","EditField","EditWhen","AfterEdit","Restore","Flag") VALUES (?,?,?,?,?,?,0,0)`,
				project, user, "_Veg", "OptimizeVeg", now, string(summaryJSON)); err != nil {
				return err
			}
			auditCount++

			// Verify foreign key integrity on mutated tables inside the transaction.
			for _, tbl := range []string{vegTable, project + "_Audit"} {
				fkRows, fkErr := tx.QueryContext(ctx, "PRAGMA foreign_key_check("+vprocore.QuoteHeaderIdentifier(tbl)+")")
				if fkErr != nil {
					return fkErr
				}
				hasFKViolation := fkRows.Next()
				if err := errors.Join(fkRows.Err(), fkRows.Close()); err != nil {
					return err
				}
				if hasFKViolation {
					return fmt.Errorf("OptimizeVeg foreign_key_check failed for %s", tbl)
				}
			}

			if err := ctx.Err(); err != nil {
				return err
			}
			if err := tx.Commit(); err != nil {
				return err
			}

			groups := make([]OptimizeVegGroup, len(plans))
			for i, p := range plans {
				groups[i] = p.group
			}
			slices.Sort(allReserved)
			allReserved = slices.Compact(allReserved)
			out = OptimizeVegResult{
				Project:            project,
				BeforeRowCount:     preview.BeforeRowCount,
				AfterRowCount:      preview.AfterRowCount,
				ConsolidatedGroups: len(plans),
				DeletedRows:        deletedCount,
				ReservedDeletedIDs: allReserved,
				OldToSurvivorIDMap: oldToSurvivorAll,
				AuditRowsWritten:   auditCount,
				Groups:             groups,
			}
			return nil
		})
	})
	if err != nil {
		return OptimizeVegResult{}, err
	}
	return out, nil
}
