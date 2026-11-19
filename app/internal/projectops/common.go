package projectops

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

// ValidateProjectName enforces canonical VPro project naming rules:
// ^[A-Za-z][A-Za-z0-9_]{0,30}$ and reserves None, Sample, and any name containing "master".
func ValidateProjectName(raw string) (string, error) {
	if !utf8.ValidString(raw) || strings.ContainsRune(raw, 0) {
		return "", errors.New("project name must be valid UTF-8 without NUL bytes")
	}
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" || trimmed != raw {
		return "", errors.New("project name must not be empty or contain leading/trailing whitespace")
	}
	if !vprocore.ProjectNamePattern.MatchString(trimmed) {
		return "", errors.New("project name must start with a letter and contain only ASCII letters, digits, or underscores (max 31 chars)")
	}
	lower := strings.ToLower(trimmed)
	if lower == "none" || lower == "sample" || strings.Contains(lower, "master") {
		return "", fmt.Errorf("project name %q is reserved (None, Sample, and master names are not permitted)", trimmed)
	}
	return trimmed, nil
}

func resolveNewProjectDestination(projectsRoot, projectName, requestedDest string, label string) (string, os.FileInfo, error) {
	dest := strings.TrimSpace(requestedDest)
	if dest == "" {
		dest = filepath.Join(projectsRoot, projectName+".db")
	} else if !strings.EqualFold(filepath.Ext(dest), ".db") {
		dest += ".db"
	}
	return vprocore.FreshSQLiteDestination(dest, label)
}

type contextSnapshotInfo struct {
	Root          string
	Project       string
	ProjectPath   string
	SU            string
	SUPath        string
	Hierarchy     string
	HierarchyPath string
	VListsPath    string
	VPro64Path    string
	CurrentUser   string
	AuditLevel    int
}

func inspectContextSnapshot(ctx context.Context, s *vprocore.ContextService, contextID string) (contextSnapshotInfo, error) {
	if s == nil {
		return contextSnapshotInfo{}, errors.New("project context service is unavailable")
	}
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (contextSnapshotInfo, error) {
		owner := plots.Projects.Sqlite
		var snap contextSnapshotInfo
		if err := owner.WithLease(ctx, func() error {
			user := strings.TrimSpace(plots.CurrentUser)
			if user == "" {
				user = "VProUser"
			}
			snap = contextSnapshotInfo{
				Root:          plots.Projects.Root,
				Project:       owner.Selection.Project,
				ProjectPath:   owner.Selection.ProjectPath,
				SU:            owner.Selection.SU,
				SUPath:        owner.Selection.SUPath,
				Hierarchy:     owner.Selection.Hierarchy,
				HierarchyPath: owner.Selection.HierarchyPath,
				VListsPath:    owner.Attachments["VLists"],
				VPro64Path:    owner.Attachments["VPro64"],
				CurrentUser:   user,
				AuditLevel:    plots.AuditStrength,
			}
			return nil
		}); err != nil {
			return contextSnapshotInfo{}, err
		}
		return snap, nil
	})
}

func computeFileSHA256(path string) (string, error) {
	h := sha256.New()
	raw, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	_, _ = h.Write(raw)
	if wal, walErr := os.ReadFile(path + "-wal"); walErr == nil && len(wal) > 0 {
		_, _ = h.Write([]byte("|WAL|"))
		_, _ = h.Write(wal)
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// readVListsVersionStamps reads USysAllSpecs and USysTableOfLists version descriptions
// from VLists.db _table_metadata along with the short SHA-256 digest of VLists.db.
func readVListsVersionStamps(ctx context.Context, vlistsPath string) (allSpecsStamp, tableOfListsStamp, shortDigest string, err error) {
	if vlistsPath == "" {
		return "Unknown", "Unknown", "", nil
	}
	fullSHA, shaErr := computeFileSHA256(vlistsPath)
	if shaErr != nil {
		return "", "", "", fmt.Errorf("hash VLists.db: %w", shaErr)
	}
	if len(fullSHA) >= 12 {
		shortDigest = fullSHA[:12]
	} else {
		shortDigest = fullSHA
	}
	db, openErr := sqlutil.OpenReadOnlyContext(ctx, vlistsPath)
	if openErr != nil {
		return "", "", "", fmt.Errorf("open VLists.db: %w", openErr)
	}
	defer db.Close()

	readDesc := func(tableName string) string {
		var desc sql.NullString
		qErr := db.QueryRowContext(ctx, `SELECT description FROM "_table_metadata" WHERE table_name = ?`, tableName).Scan(&desc)
		if qErr != nil || !desc.Valid || strings.TrimSpace(desc.String) == "" {
			return "Unknown"
		}
		return strings.TrimSpace(desc.String)
	}
	allSpecsBase := readDesc("USysAllSpecs")
	listsBase := readDesc("USysTableOfLists")
	if shortDigest != "" {
		allSpecsStamp = fmt.Sprintf("%s [sha256:%s]", allSpecsBase, shortDigest)
		tableOfListsStamp = fmt.Sprintf("%s [sha256:%s]", listsBase, shortDigest)
	} else {
		allSpecsStamp = allSpecsBase
		tableOfListsStamp = listsBase
	}
	if sqlutil.UTF16Len(allSpecsStamp) > 255 {
		allSpecsStamp = allSpecsBase
	}
	if sqlutil.UTF16Len(tableOfListsStamp) > 255 {
		tableOfListsStamp = listsBase
	}
	return allSpecsStamp, tableOfListsStamp, shortDigest, nil
}

type rawSQLiteCell struct {
	storage string
	intVal  int64
	realVal float64
	bytes   []byte
}

func (c rawSQLiteCell) sqlParam() any {
	switch c.storage {
	case "null":
		return nil
	case "integer":
		return c.intVal
	case "real":
		return c.realVal
	case "text":
		return string(c.bytes)
	case "blob":
		return append([]byte(nil), c.bytes...)
	default:
		return nil
	}
}

type sqliteQueryer interface {
	QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error)
}

func readExactTableRows(ctx context.Context, db sqliteQueryer, qualifiedTable string, whereClause string, args ...any) ([]string, [][]rawSQLiteCell, error) {
	colRows, err := db.QueryContext(ctx, "SELECT * FROM "+qualifiedTable+" LIMIT 0")
	if err != nil {
		return nil, nil, err
	}
	defer colRows.Close()
	cols, colErr := colRows.Columns()
	if colErr != nil {
		return nil, nil, colErr
	}
	if len(cols) == 0 {
		return nil, nil, fmt.Errorf("table %s has no columns", qualifiedTable)
	}
	selectExprs := make([]string, 0, len(cols)*2)
	for _, col := range cols {
		q := vprocore.QuoteHeaderIdentifier(col)
		selectExprs = append(selectExprs,
			"typeof("+q+")",
			"CASE typeof("+q+") WHEN 'integer' THEN CAST("+q+" AS INTEGER) WHEN 'real' THEN CAST("+q+" AS REAL) ELSE CAST("+q+" AS BLOB) END",
		)
	}
	query := "SELECT " + strings.Join(selectExprs, ", ") + " FROM " + qualifiedTable
	if whereClause != "" {
		query += " WHERE " + whereClause
	}
	rows, err := db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()

	var out [][]rawSQLiteCell
	for rows.Next() {
		if err := ctx.Err(); err != nil {
			return nil, nil, err
		}
		storages := make([]string, len(cols))
		vals := make([]any, len(cols))
		dest := make([]any, 0, len(cols)*2)
		for i := range cols {
			dest = append(dest, &storages[i], &vals[i])
		}
		if err := rows.Scan(dest...); err != nil {
			return nil, nil, err
		}
		rowCells := make([]rawSQLiteCell, len(cols))
		for i := range cols {
			cell := rawSQLiteCell{storage: storages[i]}
			switch storages[i] {
			case "null":
			case "integer":
				if v, ok := vals[i].(int64); ok {
					cell.intVal = v
				}
			case "real":
				if v, ok := vals[i].(float64); ok {
					cell.realVal = v
				}
			case "text", "blob":
				switch b := vals[i].(type) {
				case []byte:
					if storages[i] == "text" && !utf8.Valid(b) {
						return nil, nil, fmt.Errorf("table %s column %s contains malformed UTF-8", qualifiedTable, cols[i])
					}
					cell.bytes = append([]byte(nil), b...)
				case string:
					if storages[i] == "text" && !utf8.ValidString(b) {
						return nil, nil, fmt.Errorf("table %s column %s contains malformed UTF-8", qualifiedTable, cols[i])
					}
					cell.bytes = []byte(b)
				}
			default:
				return nil, nil, fmt.Errorf("unsupported SQLite storage class %q in %s.%s", storages[i], qualifiedTable, cols[i])
			}
			rowCells[i] = cell
		}
		out = append(out, rowCells)
	}
	if err := rows.Err(); err != nil {
		return nil, nil, err
	}
	return cols, out, nil
}

func insertExactTableRows(ctx context.Context, tx *sql.Tx, targetTable string, cols []string, rows [][]rawSQLiteCell) error {
	if len(rows) == 0 {
		return nil
	}
	quotedCols := make([]string, len(cols))
	marks := make([]string, len(cols))
	for i, c := range cols {
		quotedCols[i] = vprocore.QuoteHeaderIdentifier(c)
		marks[i] = "?"
	}
	stmtSQL := fmt.Sprintf("INSERT INTO %s (%s) VALUES (%s)",
		vprocore.QuoteHeaderIdentifier(targetTable),
		strings.Join(quotedCols, ", "),
		strings.Join(marks, ", "),
	)
	stmt, err := tx.PrepareContext(ctx, stmtSQL)
	if err != nil {
		return err
	}
	defer stmt.Close()
	for _, r := range rows {
		if err := ctx.Err(); err != nil {
			return err
		}
		args := make([]any, len(cols))
		for i := range cols {
			args[i] = r[i].sqlParam()
		}
		if _, err := stmt.ExecContext(ctx, args...); err != nil {
			return err
		}
	}
	return nil
}

func ensureChildIdentityTable(ctx context.Context, tx *sql.Tx) error {
	return vprocore.EnsureChildIdentityTable(ctx, tx)
}

func reserveChildID(ctx context.Context, tx *sql.Tx, childTable string, id int64) error {
	return vprocore.ReserveChildID(ctx, tx, childTable, id)
}

// allocateSafeChildID delegates to vprocore.SeedAndAllocateChildID so deleted IDs are never reused.
func allocateSafeChildID(ctx context.Context, tx *sql.Tx, project, suffix string) (int64, error) {
	return vprocore.SeedAndAllocateChildID(ctx, tx, project, suffix)
}
