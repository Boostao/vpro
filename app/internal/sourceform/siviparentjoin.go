package sourceform

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf16"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/vprocore"
)

type SIVIParentJoinReview struct {
	ContextID, Project, Plot, Scope, Diagnostic string
	Verified                                    bool
	EnvRowIDs, AdminRowIDs                      []string
}

func SiviASCIIPlotKey(value string) (string, bool) {
	if len(value) == 0 || len(value) > 7 {
		return "", false
	}
	key := strings.TrimRight(value, " ")
	if key == "" {
		return "", false
	}
	for _, char := range key {
		if !(char >= 'A' && char <= 'Z' || char >= 'a' && char <= 'z' || char >= '0' && char <= '9') {
			return "", false
		}
	}
	return strings.ToUpper(key), true
}

// ValidateSIVIPlotIdentity enforces the VP08 literal Text-7 PlotNumber contract
// (AGENTS.md §3.2, §3.5): valid UTF-8, non-empty and not whitespace-only, no NUL
// or control runes (allowing ASCII spaces, hyphens, underscores, punctuation, and
// Unicode characters), and at most 7 UTF-16 code units.
func ValidateSIVIPlotIdentity(value string) error {
	if value == "" || strings.TrimSpace(value) == "" {
		return errors.New("plot identity must not be empty or whitespace-only")
	}
	if !utf8.ValidString(value) {
		return errors.New("plot identity contains malformed UTF-8")
	}
	for _, r := range value {
		if r == 0 || unicode.IsControl(r) {
			return errors.New("plot identity contains NUL or control characters")
		}
	}
	if len(utf16.Encode([]rune(value))) > 7 {
		return errors.New("plot identity cannot exceed 7 characters")
	}
	return nil
}

func ReadOwnedSIVIParentWriteJoin(ctx context.Context, plots *vprocore.PlotService, contextID, plot string) (*SIVIParentJoinReview, error) {
	return vprocore.WithOwnedSIVISnapshot(ctx, plots, func(owner *vprocore.SqliteContext, tx *sql.Tx) (*SIVIParentJoinReview, error) {
		return readSIVIParentWriteJoin(ctx, tx, "project", contextID, owner.Selection.Project, plot)
	})
}

func readSIVIParentWriteJoin(ctx context.Context, tx *sql.Tx, alias, contextID, project, plot string) (*SIVIParentJoinReview, error) {
	result := &SIVIParentJoinReview{
		ContextID: contextID, Project: project, Plot: plot,
		Scope: "VP08-literal-TEXT7-BLOB", EnvRowIDs: []string{}, AdminRowIDs: []string{},
	}
	if err := ValidateSIVIPlotIdentity(plot); err != nil {
		result.Diagnostic = fmt.Sprintf("Plot identity is outside the literal TEXT7 join domain: %s.", err.Error())
		return result, nil
	}
	trimmed := strings.TrimRight(plot, " ")
	unavailable := false
	literal := [2]int{}
	for i, suffix := range []string{"_Env", "_Admin"} {
		table, column := project+suffix, "PlotNumber"
		if i == 1 {
			column = "Plot"
		}
		if err := vprocore.ValidateSIVIPhysicalSchema(ctx, tx, alias, table, "join review"); err != nil {
			return nil, err
		}
		keyColumn := vprocore.QuoteHeaderIdentifier(column)
		relation := vprocore.QuoteHeaderIdentifier(alias) + "." + vprocore.QuoteHeaderIdentifier(table)
		query := "SELECT rowid,typeof(" + keyColumn + "),CAST(" + keyColumn + " AS BLOB) FROM " + relation +
			" WHERE (typeof(" + keyColumn + ")='text' AND (" +
			"CAST(" + keyColumn + " AS BLOB)=CAST(? AS BLOB) OR " +
			"CAST(rtrim(" + keyColumn + ",' ') AS BLOB)=CAST(? AS BLOB)" +
			")) OR (typeof(" + keyColumn + ") NOT IN ('text','null') AND (" +
			"CAST(" + keyColumn + " AS TEXT)=? OR rtrim(CAST(" + keyColumn + " AS TEXT),' ')=?" +
			")) ORDER BY rowid"
		rows, err := tx.QueryContext(ctx, query, plot, trimmed, plot, trimmed)
		if err != nil {
			return nil, err
		}
		if err := func() (scanErr error) {
			defer func() { scanErr = errors.Join(scanErr, rows.Close()) }()
			for rows.Next() {
				var id int64
				var storage string
				var raw []byte
				if err := rows.Scan(&id, &storage, &raw); err != nil {
					return err
				}
				if storage != "text" {
					unavailable = true
					continue
				}
				cell, err := vprocore.ProjectMetadataCellInternal(storage, raw)
				if err != nil {
					return err
				}
				if _, err := vprocore.MetadataCellValue(cell); err != nil {
					return err
				}
				if ValidateSIVIPlotIdentity(*cell.Text) != nil {
					unavailable = true
					continue
				}
				idText := strconv.FormatInt(id, 10)
				if i == 0 {
					result.EnvRowIDs = append(result.EnvRowIDs, idText)
				} else {
					result.AdminRowIDs = append(result.AdminRowIDs, idText)
				}
				if *cell.Text == plot {
					literal[i]++
				}
			}
			return rows.Err()
		}(); err != nil {
			return nil, err
		}
	}
	result.Verified = !unavailable && literal[0] == 1 && literal[1] == 1 &&
		len(result.EnvRowIDs) == 1 && len(result.AdminRowIDs) == 1
	switch {
	case unavailable:
		result.Diagnostic = "Target plot join identity has unsupported non-text storage or invalid TEXT7 bytes; source membership is not certified."
	case !result.Verified:
		result.Diagnostic = fmt.Sprintf("Source comparison finds %d Env and %d Admin rows; one exact unambiguous physical pair is required.", len(result.EnvRowIDs), len(result.AdminRowIDs))
	default:
		result.Diagnostic = "One exact literal TEXT7 physical pair verified."
	}
	return result, nil
}

func ReadOwnedSIVIParentJoin(ctx context.Context, plots *vprocore.PlotService, contextID, plot string) (*SIVIParentJoinReview, error) {
	return vprocore.WithOwnedSIVISnapshot(ctx, plots, func(owner *vprocore.SqliteContext, tx *sql.Tx) (*SIVIParentJoinReview, error) {
		return readSIVIParentJoin(ctx, tx, "project", contextID, owner.Selection.Project, plot)
	})
}

func readSIVIParentJoin(ctx context.Context, tx *sql.Tx, alias, contextID, project, plot string) (*SIVIParentJoinReview, error) {
	result := &SIVIParentJoinReview{ContextID: contextID, Project: project, Plot: plot,
		Scope: "DAO-General1033-ASCII-alphanumeric-TEXT7", EnvRowIDs: []string{}, AdminRowIDs: []string{}}
	requested, supported := SiviASCIIPlotKey(plot)
	if !supported {
		result.Diagnostic = "Plot identity is outside the independently probed ASCII TEXT7 join domain."
		return result, nil
	}
	unavailable := false
	literal := []int{0, 0}
	for i, suffix := range []string{"_Env", "_Admin"} {
		table, column := project+suffix, "PlotNumber"
		if i == 1 {
			column = "Plot"
		}
		if err := vprocore.ValidateSIVIPhysicalSchema(ctx, tx, alias, table, "join review"); err != nil {
			return nil, err
		}
		keyColumn := vprocore.QuoteHeaderIdentifier(column)
		query := "SELECT rowid,typeof(" + keyColumn + "),CAST(" + keyColumn + " AS BLOB) FROM " + vprocore.QuoteHeaderIdentifier(alias) + "." +
			vprocore.QuoteHeaderIdentifier(table) + " ORDER BY rowid"
		rows, err := tx.QueryContext(ctx, query)
		if err != nil {
			return nil, err
		}
		if err := func() (scanErr error) {
			defer func() { scanErr = errors.Join(scanErr, rows.Close()) }()
			for rows.Next() {
				var id int64
				var storage string
				var raw []byte
				if err := rows.Scan(&id, &storage, &raw); err != nil {
					return err
				}
				if storage == "null" {
					continue
				}
				if storage != "text" {
					unavailable = true
					continue
				}
				cell, err := vprocore.ProjectMetadataCellInternal(storage, raw)
				if err != nil {
					return err
				}
				if _, err := vprocore.MetadataCellValue(cell); err != nil {
					return err
				}
				key, valid := SiviASCIIPlotKey(*cell.Text)
				if !valid {
					unavailable = true
					continue
				}
				if key != requested {
					continue
				}
				idText := strconv.FormatInt(id, 10)
				if i == 0 {
					result.EnvRowIDs = append(result.EnvRowIDs, idText)
				} else {
					result.AdminRowIDs = append(result.AdminRowIDs, idText)
				}
				if *cell.Text == plot {
					literal[i]++
				}
			}
			return rows.Err()
		}(); err != nil {
			return nil, err
		}
	}
	result.Verified = !unavailable && literal[0] == 1 && literal[1] == 1 &&
		len(result.EnvRowIDs) == 1 && len(result.AdminRowIDs) == 1
	switch {
	case unavailable:
		result.Diagnostic = "A physical join identity has unsupported storage, Unicode, punctuation, empty text or length; source membership is not certified."
	case !result.Verified:
		result.Diagnostic = fmt.Sprintf("Source comparison finds %d Env and %d Admin rows; one exact unambiguous physical pair is required.", len(result.EnvRowIDs), len(result.AdminRowIDs))
	default:
		result.Diagnostic = "One exact physical pair; case/trailing-space aliases are absent in the independently probed ASCII domain. This is not write authorization."
	}
	return result, nil
}
