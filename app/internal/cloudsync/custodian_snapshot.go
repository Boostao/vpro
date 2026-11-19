package cloudsync

import (
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"
	"hash"
	"math"
	"slices"
	"strconv"
	"strings"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/jackc/pgx/v5"
)

// cloudCell holds a typed value for byte-exact 3-way diffing and PostgreSQL parameterized writes.
type cloudCell struct {
	kind    string // "null" | "int" | "float" | "text"
	intVal  int64
	fltVal  float64
	textVal string
}

func pgValueToCloudCell(col ColumnSpec, raw any) cloudCell {
	if raw == nil {
		return cloudCell{kind: "null"}
	}
	if col.IsAccessBool {
		switch v := raw.(type) {
		case int16:
			if v != 0 {
				return cloudCell{kind: "int", intVal: -1}
			}
			return cloudCell{kind: "int", intVal: 0}
		case int32:
			if v != 0 {
				return cloudCell{kind: "int", intVal: -1}
			}
			return cloudCell{kind: "int", intVal: 0}
		case int64:
			if v != 0 {
				return cloudCell{kind: "int", intVal: -1}
			}
			return cloudCell{kind: "int", intVal: 0}
		case int:
			if v != 0 {
				return cloudCell{kind: "int", intVal: -1}
			}
			return cloudCell{kind: "int", intVal: 0}
		case float64:
			if math.IsNaN(v) || math.IsInf(v, 0) {
				return cloudCell{kind: "null"}
			}
			if v != 0 {
				return cloudCell{kind: "int", intVal: -1}
			}
			return cloudCell{kind: "int", intVal: 0}
		case bool:
			if v {
				return cloudCell{kind: "int", intVal: -1}
			}
			return cloudCell{kind: "int", intVal: 0}
		case string:
			if parsed, err := parseBoolBytes(v); err == nil {
				if parsed == nil {
					return cloudCell{kind: "null"}
				}
				return cloudCell{kind: "int", intVal: int64(parsed.(int16))}
			}
		case []byte:
			if parsed, err := parseBoolBytes(string(v)); err == nil {
				if parsed == nil {
					return cloudCell{kind: "null"}
				}
				return cloudCell{kind: "int", intVal: int64(parsed.(int16))}
			}
		}
	}
	switch v := raw.(type) {
	case int16:
		return cloudCell{kind: "int", intVal: int64(v)}
	case int32:
		return cloudCell{kind: "int", intVal: int64(v)}
	case int64:
		return cloudCell{kind: "int", intVal: v}
	case float32:
		return cloudCell{kind: "float", fltVal: float64(v)}
	case float64:
		return cloudCell{kind: "float", fltVal: v}
	case string:
		return cloudCell{kind: "text", textVal: v}
	case []byte:
		return cloudCell{kind: "text", textVal: string(v)}
	default:
		return cloudCell{kind: "text", textVal: fmt.Sprint(v)}
	}
}

func (c cloudCell) comparableString() *string {
	switch c.kind {
	case "null":
		return nil
	case "int":
		s := strconv.FormatInt(c.intVal, 10)
		return &s
	case "float":
		s := vprocore.SourceDoubleDecimalString(c.fltVal)
		return &s
	case "text":
		s := c.textVal
		return &s
	default:
		return nil
	}
}

func (c cloudCell) pgParam(col ColumnSpec) any {
	switch c.kind {
	case "null":
		return nil
	case "int":
		if col.IsAccessBool {
			if c.intVal != 0 {
				return int16(-1)
			}
			return int16(0)
		}
		if col.PGType == "SMALLINT" {
			return int16(c.intVal)
		}
		return c.intVal
	case "float":
		return c.fltVal
	case "text":
		return c.textVal
	default:
		return nil
	}
}

type cloudSnapshot struct {
	label string
	plots map[string]bool
	// suffix -> plotNumber -> rowKey -> colName -> *string
	cells map[string]map[string]map[string]*string
	// suffix -> plotNumber -> rowKey -> colName -> cloudCell
	rawCells map[string]map[string]map[string]cloudCell
}

func newCloudSnapshot(label string) *cloudSnapshot {
	s := &cloudSnapshot{
		label:    label,
		plots:    map[string]bool{},
		cells:    map[string]map[string]map[string]*string{},
		rawCells: map[string]map[string]map[string]cloudCell{},
	}
	for _, suffix := range mergeTableSuffixes {
		s.cells[suffix] = map[string]map[string]*string{}
		s.rawCells[suffix] = map[string]map[string]cloudCell{}
	}
	return s
}

type childRowRecord struct {
	cells map[string]cloudCell
	comps map[string]*string
}

func buildLogicalRowsForPlot(suffix string, cols []ColumnSpec, rows []childRowRecord) (map[string]map[string]*string, map[string]map[string]cloudCell) {
	compOut := map[string]map[string]*string{}
	rawOut := map[string]map[string]cloudCell{}

	baseKey := func(r childRowRecord) string {
		switch suffix {
		case "Env", "Admin":
			return suffix
		case "Veg":
			spp := ""
			if r.cells["Species"].kind == "text" {
				spp = r.cells["Species"].textVal
			}
			layer := ""
			if r.cells["Layer"].kind == "text" {
				layer = r.cells["Layer"].textVal
			}
			if layer != "" {
				return fmt.Sprintf("Species=%s|Layer=%s", spp, layer)
			}
			return fmt.Sprintf("Species=%s", spp)
		case "Humus", "Mineral":
			hz := ""
			if r.cells["Horizon"].kind == "text" {
				hz = r.cells["Horizon"].textVal
			}
			return fmt.Sprintf("Horizon=%s", hz)
		case "Other":
			dn := ""
			if r.cells["DataName"].kind == "text" {
				dn = r.cells["DataName"].textVal
			}
			return fmt.Sprintf("DataName=%s", dn)
		default:
			return suffix
		}
	}

	rowSig := func(r childRowRecord) string {
		var b strings.Builder
		b.WriteString(baseKey(r))
		for _, c := range cols {
			if c.Name == "ID" || c.Name == "PlotNumber" || c.Name == "Plot" {
				continue
			}
			b.WriteByte('|')
			if v := r.comps[c.Name]; v != nil {
				b.WriteString(*v)
			} else {
				b.WriteString("<NULL>")
			}
		}
		return b.String()
	}

	sorted := make([]childRowRecord, len(rows))
	copy(sorted, rows)
	slices.SortFunc(sorted, func(a, b childRowRecord) int {
		return strings.Compare(rowSig(a), rowSig(b))
	})

	counts := map[string]int{}
	for _, r := range sorted {
		bk := baseKey(r)
		counts[bk]++
		key := bk
		if counts[bk] > 1 {
			key = fmt.Sprintf("%s#%d", bk, counts[bk])
		}
		compOut[key] = r.comps
		rawOut[key] = r.cells
	}
	return compOut, rawOut
}

func scanSnapshotTableRows(snap *cloudSnapshot, suffix string, cols []ColumnSpec, rows pgx.Rows) error {
	plotCol := "PlotNumber"
	if suffix == "Admin" {
		plotCol = "Plot"
	}
	byPlot := map[string][]childRowRecord{}
	if err := func() error {
		defer rows.Close()
		for rows.Next() {
			vals, vErr := rows.Values()
			if vErr != nil {

				return vErr
			}
			rec := childRowRecord{
				cells: make(map[string]cloudCell, len(cols)),
				comps: make(map[string]*string, len(cols)),
			}
			plotStr := ""
			for i, col := range cols {
				cc := pgValueToCloudCell(col, vals[i])
				rec.cells[col.Name] = cc
				rec.comps[col.Name] = cc.comparableString()
				if col.Name == plotCol && cc.kind == "text" {
					plotStr = cc.textVal
				}
			}
			if plotStr == "" {
				continue
			}
			snap.plots[plotStr] = true
			byPlot[plotStr] = append(byPlot[plotStr], rec)
		}
		return rows.Err()
	}(); err != nil {
		return err
	}
	for plot, list := range byPlot {
		cMap, rMap := buildLogicalRowsForPlot(suffix, cols, list)
		for rk, cm := range cMap {
			snap.cells[suffix][plot+"\x00"+rk] = cm
			snap.rawCells[suffix][plot+"\x00"+rk] = rMap[rk]
		}
	}
	return nil
}

func loadPGSubsetSnapshot(ctx context.Context, q pgQueryer, schema, label string, submissionID string, plotFilter []string) (*cloudSnapshot, error) {
	snap := newCloudSnapshot(label)
	if schema == "becmaster" && submissionID == "" && len(plotFilter) == 0 {
		return snap, nil
	}

	pgTables := map[string]string{
		"Env": "env", "Admin": "admin", "Veg": "veg",
		"Humus": "humus", "Mineral": "mineral", "Other": "other",
	}

	batch := &pgx.Batch{}
	for _, suffix := range mergeTableSuffixes {
		cols := VP08ColumnsBySuffix(suffix)
		plotCol := "PlotNumber"
		if suffix == "Admin" {
			plotCol = "Plot"
		}
		if schema == "staging" {
			batch.Queue(fmt.Sprintf(`SELECT %s FROM staging.%s WHERE submission_id = $1`, quotedColumnCSV(cols), quotePGIdent(pgTables[suffix])), submissionID)
		} else if submissionID != "" && len(plotFilter) == 0 {
			batch.Queue(fmt.Sprintf(`SELECT %s FROM becmaster.%s WHERE %s IN (SELECT "PlotNumber" FROM staging.env WHERE submission_id = $1)`, quotedColumnCSV(cols), quotePGIdent(pgTables[suffix]), quotePGIdent(plotCol)), submissionID)
		} else {
			batch.Queue(fmt.Sprintf(`SELECT %s FROM becmaster.%s WHERE %s = ANY($1)`, quotedColumnCSV(cols), quotePGIdent(pgTables[suffix]), quotePGIdent(plotCol)), plotFilter)
		}
	}

	br := q.SendBatch(ctx, batch)
	defer br.Close()

	for _, suffix := range mergeTableSuffixes {
		cols := VP08ColumnsBySuffix(suffix)
		rows, err := br.Query()
		if err != nil {
			return nil, fmt.Errorf("load %s.%s: %w", schema, pgTables[suffix], err)
		}
		if err := scanSnapshotTableRows(snap, suffix, cols, rows); err != nil {
			return nil, fmt.Errorf("scan %s.%s: %w", schema, pgTables[suffix], err)
		}
	}
	return snap, br.Close()
}

func loadSQLiteBaseSubsetSnapshot(ctx context.Context, dbPath, reqProject string, plotFilter []string) (*cloudSnapshot, string, error) {
	resolved, proj, err := resolveProjectInSQLiteFile(ctx, dbPath, reqProject)
	if err != nil {
		return nil, "", err
	}
	snap := newCloudSnapshot(proj)
	if len(plotFilter) == 0 {
		return snap, proj, nil
	}
	allowed := make(map[string]bool, len(plotFilter))
	for _, p := range plotFilter {
		allowed[p] = true
	}

	db, err := sqlutil.OpenReadOnlyContext(ctx, resolved)
	if err != nil {
		return nil, "", err
	}
	defer db.Close()

	for _, suffix := range mergeTableSuffixes {
		cols := VP08ColumnsBySuffix(suffix)
		plotCol := "PlotNumber"
		if suffix == "Admin" {
			plotCol = "Plot"
		}
		rows, qErr := db.QueryContext(ctx, fmt.Sprintf(`SELECT %s FROM %s WHERE typeof(%s) = 'text'`,
			sqliteSelectColumnsCSV(cols), quotePGIdent(proj+"_"+suffix), quotePGIdent(plotCol)))
		if qErr != nil {
			return nil, "", qErr
		}
		rawVals := make([]any, len(cols))
		dest := make([]any, len(cols))
		for i := range rawVals {
			dest[i] = &rawVals[i]
		}
		byPlot := map[string][]childRowRecord{}
		if err := func() (scanErr error) {
			defer func() { scanErr = errors.Join(scanErr, rows.Close()) }()
			for rows.Next() {
				if sErr := rows.Scan(dest...); sErr != nil {

					return sErr
				}
				rec := childRowRecord{
					cells: make(map[string]cloudCell, len(cols)),
					comps: make(map[string]*string, len(cols)),
				}
				plotStr := ""
				for i, col := range cols {
					pgVal, cErr := CanonicalizeSQLiteToPG(col, rawVals[i])
					if cErr != nil {

						return fmt.Errorf("canonicalize %s.%s for snapshot: %w", suffix, col.Name, cErr) // ENG-GO-004
					}
					cc := pgValueToCloudCell(col, pgVal)
					rec.cells[col.Name] = cc
					rec.comps[col.Name] = cc.comparableString()
					if col.Name == plotCol && cc.kind == "text" {
						plotStr = cc.textVal
					}
				}
				if plotStr == "" || !allowed[plotStr] {
					continue
				}
				snap.plots[plotStr] = true
				byPlot[plotStr] = append(byPlot[plotStr], rec)
			}
			return rows.Err()
		}(); err != nil {
			return nil, "", err
		}
		for plot, list := range byPlot {
			cMap, rMap := buildLogicalRowsForPlot(suffix, cols, list)
			for rk, cm := range cMap {
				snap.cells[suffix][plot+"\x00"+rk] = cm
				snap.rawCells[suffix][plot+"\x00"+rk] = rMap[rk]
			}
		}
	}
	return snap, proj, nil
}

func plotRowsFromSnap(snap *cloudSnapshot, suffix, plot string) map[string]map[string]*string {
	out := map[string]map[string]*string{}
	if snap == nil {
		return out
	}
	prefix := plot + "\x00"
	for k, v := range snap.cells[suffix] {
		if strings.HasPrefix(k, prefix) {
			out[strings.TrimPrefix(k, prefix)] = v
		}
	}
	return out
}

func plotRawRowsFromSnap(snap *cloudSnapshot, suffix, plot string) map[string]map[string]cloudCell {
	out := map[string]map[string]cloudCell{}
	if snap == nil {
		return out
	}
	prefix := plot + "\x00"
	for k, v := range snap.rawCells[suffix] {
		if strings.HasPrefix(k, prefix) {
			out[strings.TrimPrefix(k, prefix)] = v
		}
	}
	return out
}

func writeDigestItem(h hash.Hash, s string) {
	var b [8]byte
	binary.BigEndian.PutUint64(b[:], uint64(len(s)))
	_, _ = h.Write(b[:])
	_, _ = h.Write([]byte(s))
}

func hashCloudSnapshot(snap *cloudSnapshot) string {
	if snap == nil {
		return ""
	}
	h := sha256.New()
	writeDigestItem(h, snap.label)
	for _, suffix := range mergeTableSuffixes {
		writeDigestItem(h, suffix)
		cols := VP08ColumnsBySuffix(suffix)
		keys := make([]string, 0, len(snap.rawCells[suffix]))
		for k := range snap.rawCells[suffix] {
			keys = append(keys, k)
		}
		slices.Sort(keys)
		writeDigestItem(h, strconv.Itoa(len(keys)))
		for _, k := range keys {
			writeDigestItem(h, k)
			rm := snap.rawCells[suffix][k]
			for _, col := range cols {
				c := rm[col.Name]
				writeDigestItem(h, c.kind)
				switch c.kind {
				case "int":
					writeDigestItem(h, strconv.FormatInt(c.intVal, 10))
				case "float":
					writeDigestItem(h, strconv.FormatUint(math.Float64bits(c.fltVal), 16))
				case "text":
					writeDigestItem(h, c.textVal)
				}
			}
		}
	}
	return hex.EncodeToString(h.Sum(nil))
}

func summarizeCloudRow(cols []ColumnSpec, row map[string]*string) string {
	var parts []string
	for _, col := range cols {
		if col.Name == "ID" || col.Name == "PlotNumber" || col.Name == "Plot" {
			continue
		}
		if v := row[col.Name]; v != nil && *v != "" && !(col.Name == "Flag" && *v == "0") {
			parts = append(parts, fmt.Sprintf("%s=%s", col.Name, *v))
		}
	}
	return strings.Join(parts, ", ")
}

func sameNullableStr(a, b *string) bool {
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	return *a == *b
}

func makeCloudConflictID(plot, table, key string) string {
	return plot + "::" + table + "::" + key
}
