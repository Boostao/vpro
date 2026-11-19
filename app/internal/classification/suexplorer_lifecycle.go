package classification

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"unicode/utf16"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

const (
	suCreationHistoryTable = "__VPRO_SUCreationHistory"
	suCreationHistorySQL   = `CREATE TABLE "__VPRO_SUCreationHistory"(ID INTEGER PRIMARY KEY,Created TEXT NOT NULL,Proposal TEXT NOT NULL)`
)

type CreateSUTableRequest struct {
	Name                    string `json:"name"`
	Destination             string `json:"destination"` // "project" (default) | "new_file"
	FilePath                string `json:"filePath"`
	PopulateAllProjectPlots bool   `json:"populateAllProjectPlots"`
	SeedFromUserSiteUnit    bool   `json:"seedFromUserSiteUnit"`
	Activate                bool   `json:"activate"`
}

func (r *CreateSUTableRequest) UnmarshalJSON(data []byte) error {
	type plain CreateSUTableRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type SaveSUTableAsRequest struct {
	SourceSU    string `json:"sourceSu"` // defaults to active SU when empty
	NewName     string `json:"newName"`
	Destination string `json:"destination"` // "project" (default) | "new_file"
	FilePath    string `json:"filePath"`
	Activate    bool   `json:"activate"`
}

func (r *SaveSUTableAsRequest) UnmarshalJSON(data []byte) error {
	type plain SaveSUTableAsRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type SUTableLifecycleResult struct {
	ContextID string                 `json:"contextId"`
	Name      string                 `json:"name"`
	TableName string                 `json:"tableName"`
	FilePath  string                 `json:"filePath"`
	PlotCount int                    `json:"plotCount"`
	Activated bool                   `json:"activated"`
	NewState  *vprocore.ProjectState `json:"newState,omitempty"`
}

func validateClassificationObjectName(rawName, label string) (string, error) {
	trimmed := strings.TrimSpace(rawName)
	if !utf8.ValidString(trimmed) || !vprocore.ProjectNamePattern.MatchString(trimmed) {
		return "", fmt.Errorf("%s name %q is invalid; use letters, digits, hyphens, or underscores", label, rawName)
	}
	if strings.EqualFold(trimmed, "None") || strings.EqualFold(trimmed, "Sample") || strings.EqualFold(trimmed, "USysSuTableDynamic") {
		return "", fmt.Errorf("%s name %q is reserved and cannot be created or overwritten", label, trimmed)
	}
	return trimmed, nil
}

func createSUTableObjectsInTx(ctx context.Context, tx *sql.Tx, suName string) error {
	tableName := suName + "_SU"
	var collision int
	if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM main.sqlite_master WHERE name = ? COLLATE NOCASE`, tableName).Scan(&collision); err != nil {
		return err
	}
	if collision != 0 {
		return fmt.Errorf("table %s already exists in target database", tableName)
	}
	qTable := vprocore.QuoteHeaderIdentifier(tableName)
	qUniq := vprocore.QuoteHeaderIdentifier("uidx_" + tableName + "_PlotNumber")
	qIdx := vprocore.QuoteHeaderIdentifier("idx_" + tableName + "_SiteUnit")

	if _, err := tx.ExecContext(ctx, `CREATE TABLE main.`+qTable+` ("PlotNumber" VARCHAR, "SiteUnit" VARCHAR)`); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `CREATE UNIQUE INDEX main.`+qUniq+` ON `+qTable+` ("PlotNumber")`); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `CREATE INDEX main.`+qIdx+` ON `+qTable+` ("SiteUnit")`); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS main._table_metadata (table_name TEXT PRIMARY KEY, description TEXT)`); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `INSERT OR REPLACE INTO main._table_metadata (table_name, description) VALUES (?, 'VP04')`, tableName); err != nil {
		return err
	}
	return nil
}

func utf16UnitsWithin(s string, maxUnits int) bool {
	if len(s) <= maxUnits {
		return true
	}
	return len(utf16.Encode([]rune(s))) <= maxUnits
}

func CreateSUTable(ctx context.Context, contexts *vprocore.ContextService, contextID string, request CreateSUTableRequest) (*SUTableLifecycleResult, error) {
	if ctx == nil {
		return nil, errors.New("SU creation requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("classification context service is unavailable")
	}
	suName, err := validateClassificationObjectName(request.Name, "SU")
	if err != nil {
		return nil, err
	}
	dest := strings.ToLower(strings.TrimSpace(request.Destination))
	if dest == "" {
		if strings.TrimSpace(request.FilePath) != "" {
			dest = "new_file"
		} else {
			dest = "project"
		}
	}
	if dest != "project" && dest != "new_file" {
		return nil, fmt.Errorf("unsupported SU destination %q; expected 'project' or 'new_file'", request.Destination)
	}

	var out *SUTableLifecycleResult
	var targetPath string
	var currentSelection vprocore.DesktopSelection

	_, err = vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (struct{}, error) {
		owner := plots.Projects.Sqlite
		currentSelection = owner.Selection
		project := owner.Selection.Project

		var seeds []sqlutil.SURowSeed

		if request.PopulateAllProjectPlots {
			if err := owner.WithReadSnapshot(ctx, func(tx *sql.Tx) error {
				adminUnits := map[string]string{}
				if request.SeedFromUserSiteUnit {
					aRows, aErr := tx.QueryContext(ctx,
						`SELECT CAST("Plot" AS BLOB), CAST("UserSiteUnit" AS TEXT)
						 FROM "project".`+vprocore.QuoteHeaderIdentifier(project+"_Admin")+`
						 WHERE typeof("Plot")='text' AND "UserSiteUnit" IS NOT NULL`)
					if aErr != nil {
						return aErr
					}
					for aRows.Next() {
						var rawPlot []byte
						var u sql.NullString
						if sErr := aRows.Scan(&rawPlot, &u); sErr != nil {
							aRows.Close()
							return sErr
						}
						key := string(rawPlot)
						if _, exists := adminUnits[key]; !exists && u.Valid {
							adminUnits[key] = u.String
						}
					}
					if aErr := errors.Join(aRows.Err(), aRows.Close()); aErr != nil {
						return aErr
					}
				}

				rows, qErr := tx.QueryContext(ctx,
					`SELECT CAST(env."PlotNumber" AS BLOB), CAST(env."PlotNumber" AS TEXT)
					 FROM "project".`+vprocore.QuoteHeaderIdentifier(project+"_Env")+` AS env
					 WHERE typeof(env."PlotNumber")='text' AND TRIM(env."PlotNumber") <> ''
					 ORDER BY env."PlotNumber" COLLATE NOCASE ASC, env.rowid ASC`)
				if qErr != nil {
					return qErr
				}
				seen := map[string]bool{}
				for rows.Next() {
					var rawPlot []byte
					var p string
					if sErr := rows.Scan(&rawPlot, &p); sErr != nil {
						rows.Close()
						return sErr
					}
					rawKey := string(rawPlot)
					if seen[rawKey] || !utf16UnitsWithin(p, 7) {
						continue
					}
					seen[rawKey] = true
					var unitPtr *string
					if request.SeedFromUserSiteUnit {
						if uStr, ok := adminUnits[rawKey]; ok && strings.TrimSpace(uStr) != "" && utf16UnitsWithin(uStr, 255) {
							val := uStr
							unitPtr = &val
						}
					}
					seeds = append(seeds, sqlutil.SURowSeed{PlotNumber: p, SiteUnit: unitPtr})
				}
				return errors.Join(rows.Err(), rows.Close())
			}); err != nil {
				return struct{}{}, err
			}
		}

		tableName := suName + "_SU"
		proposalBytes, err := json.Marshal(request)
		if err != nil {
			return struct{}{}, err
		}

		if dest == "project" {
			targetPath = owner.Selection.ProjectPath
			err = owner.WithMetadataWriter(ctx, func(conn *sql.Conn) (txErr error) {
				tx, bErr := conn.BeginTx(ctx, nil)
				if bErr != nil {
					return bErr
				}
				defer func() {
					if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
						txErr = errors.Join(txErr, rb)
					}
				}()
				if err := createSUTableObjectsInTx(ctx, tx, suName); err != nil {
					return err
				}
				qTable := vprocore.QuoteHeaderIdentifier(tableName)
				if err := sqlutil.InsertSURowsBatched(ctx, tx, qTable, seeds); err != nil {
					return err
				}
				if err := vprocore.AppendTechnicalProvenance(ctx, tx, suCreationHistoryTable, suCreationHistorySQL, string(proposalBytes), "SU table creation"); err != nil {
					return err
				}
				if err := ctx.Err(); err != nil {
					return err
				}
				return tx.Commit()
			})
			if err != nil {
				return struct{}{}, err
			}
		} else {
			freshPath, _, fErr := vprocore.FreshSQLiteDestination(request.FilePath, "SU")
			if fErr != nil {
				return struct{}{}, fErr
			}
			targetPath = freshPath
			committed := false
			db, oErr := sqlutil.OpenWALCreateSQLite(freshPath)
			if oErr != nil {
				return struct{}{}, oErr
			}
			defer func() {
				_ = db.Close()
				if !committed {
					_ = sqlutil.RemoveSQLiteWithSidecars(freshPath)
				}
			}()
			tx, bErr := sqlutil.BeginStagedTx(ctx, db)
			if bErr != nil {
				return struct{}{}, bErr
			}
			if err := createSUTableObjectsInTx(ctx, tx, suName); err != nil {
				_ = tx.Rollback()
				return struct{}{}, err
			}
			qTable := vprocore.QuoteHeaderIdentifier(tableName)
			if err := sqlutil.InsertSURowsBatched(ctx, tx, qTable, seeds); err != nil {
				_ = tx.Rollback()
				return struct{}{}, err
			}
			if err := vprocore.AppendTechnicalProvenance(ctx, tx, suCreationHistoryTable, suCreationHistorySQL, string(proposalBytes), "SU file creation"); err != nil {
				_ = tx.Rollback()
				return struct{}{}, err
			}
			if err := sqlutil.CommitStagedTx(ctx, tx); err != nil {
				return struct{}{}, err
			}
			committed = true
		}

		out = &SUTableLifecycleResult{
			ContextID: contextID,
			Name:      suName,
			TableName: tableName,
			FilePath:  targetPath,
			PlotCount: len(seeds),
		}
		return struct{}{}, nil
	})
	if err != nil {
		return nil, err
	}

	if request.Activate {
		nextState, swErr := contexts.SwitchContext(contextID, vprocore.ContextSelection{
			Project:       currentSelection.Project,
			ProjectPath:   currentSelection.ProjectPath,
			SU:            suName,
			SUPath:        targetPath,
			Hierarchy:     currentSelection.Hierarchy,
			HierarchyPath: currentSelection.HierarchyPath,
		})
		if swErr != nil {
			return nil, swErr
		}
		out.Activated = true
		out.ContextID = nextState.ContextID
		out.NewState = &nextState
	}
	return out, nil
}

func SaveSUTableAs(ctx context.Context, contexts *vprocore.ContextService, contextID string, request SaveSUTableAsRequest) (*SUTableLifecycleResult, error) {
	if ctx == nil {
		return nil, errors.New("SU save-as requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("classification context service is unavailable")
	}
	newName, err := validateClassificationObjectName(request.NewName, "SU")
	if err != nil {
		return nil, err
	}
	dest := strings.ToLower(strings.TrimSpace(request.Destination))
	if dest == "" {
		if strings.TrimSpace(request.FilePath) != "" {
			dest = "new_file"
		} else {
			dest = "project"
		}
	}
	if dest != "project" && dest != "new_file" {
		return nil, fmt.Errorf("unsupported SU save-as destination %q", request.Destination)
	}

	var out *SUTableLifecycleResult
	var targetPath string
	var currentSelection vprocore.DesktopSelection

	_, err = vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (struct{}, error) {
		owner := plots.Projects.Sqlite
		currentSelection = owner.Selection
		srcName := strings.TrimSpace(request.SourceSU)
		if srcName == "" {
			srcName = owner.Selection.SU
		}
		if srcName == "" || srcName == "None" {
			return struct{}{}, errors.New("an active or explicit source SU table is required for Save As")
		}

		var copiedRows []sqlutil.SURowSeed

		if err := owner.WithReadSnapshot(ctx, func(tx *sql.Tx) error {
			role := "su"
			if !strings.EqualFold(srcName, owner.Selection.SU) {
				role = "project"
			}
			srcTable := srcName + "_SU"
			rows, qErr := tx.QueryContext(ctx,
				`SELECT CAST("PlotNumber" AS TEXT), CAST("SiteUnit" AS TEXT) FROM `+
					vprocore.QuoteHeaderIdentifier(role)+`.`+vprocore.QuoteHeaderIdentifier(srcTable)+` ORDER BY rowid ASC`)
			if qErr != nil {
				return fmt.Errorf("read source SU %s: %w", srcTable, qErr)
			}
			for rows.Next() {
				var p, u sql.NullString
				if sErr := rows.Scan(&p, &u); sErr != nil {
					rows.Close()
					return sErr
				}
				seed := sqlutil.SURowSeed{PlotNull: !p.Valid}
				if p.Valid {
					seed.PlotNumber = p.String
				}
				if u.Valid {
					v := u.String
					seed.SiteUnit = &v
				}
				copiedRows = append(copiedRows, seed)
			}
			return errors.Join(rows.Err(), rows.Close())
		}); err != nil {
			return struct{}{}, err
		}

		targetTable := newName + "_SU"
		proposalBytes, err := json.Marshal(request)
		if err != nil {
			return struct{}{}, err
		}

		if dest == "project" {
			targetPath = owner.Selection.ProjectPath
			err = owner.WithMetadataWriter(ctx, func(conn *sql.Conn) (txErr error) {
				wtx, bErr := conn.BeginTx(ctx, nil)
				if bErr != nil {
					return bErr
				}
				defer func() {
					if rb := wtx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
						txErr = errors.Join(txErr, rb)
					}
				}()
				if err := createSUTableObjectsInTx(ctx, wtx, newName); err != nil {
					return err
				}
				qTarget := vprocore.QuoteHeaderIdentifier(targetTable)
				if err := sqlutil.InsertSURowsBatched(ctx, wtx, qTarget, copiedRows); err != nil {
					return err
				}
				if err := vprocore.AppendTechnicalProvenance(ctx, wtx, suCreationHistoryTable, suCreationHistorySQL, string(proposalBytes), "SU save-as"); err != nil {
					return err
				}
				if err := ctx.Err(); err != nil {
					return err
				}
				return wtx.Commit()
			})
			if err != nil {
				return struct{}{}, err
			}
		} else {
			freshPath, _, fErr := vprocore.FreshSQLiteDestination(request.FilePath, "SU")
			if fErr != nil {
				return struct{}{}, fErr
			}
			targetPath = freshPath
			committed := false
			db, oErr := sqlutil.OpenWALCreateSQLite(freshPath)
			if oErr != nil {
				return struct{}{}, oErr
			}
			defer func() {
				_ = db.Close()
				if !committed {
					_ = sqlutil.RemoveSQLiteWithSidecars(freshPath)
				}
			}()
			wtx, bErr := sqlutil.BeginStagedTx(ctx, db)
			if bErr != nil {
				return struct{}{}, bErr
			}
			if err := createSUTableObjectsInTx(ctx, wtx, newName); err != nil {
				_ = wtx.Rollback()
				return struct{}{}, err
			}
			qTarget := vprocore.QuoteHeaderIdentifier(targetTable)
			if err := sqlutil.InsertSURowsBatched(ctx, wtx, qTarget, copiedRows); err != nil {
				_ = wtx.Rollback()
				return struct{}{}, err
			}
			if err := vprocore.AppendTechnicalProvenance(ctx, wtx, suCreationHistoryTable, suCreationHistorySQL, string(proposalBytes), "SU file save-as"); err != nil {
				_ = wtx.Rollback()
				return struct{}{}, err
			}
			if err := sqlutil.CommitStagedTx(ctx, wtx); err != nil {
				return struct{}{}, err
			}
			committed = true
		}

		out = &SUTableLifecycleResult{
			ContextID: contextID,
			Name:      newName,
			TableName: targetTable,
			FilePath:  targetPath,
			PlotCount: len(copiedRows),
		}
		return struct{}{}, nil
	})
	if err != nil {
		return nil, err
	}

	if request.Activate {
		nextState, swErr := contexts.SwitchContext(contextID, vprocore.ContextSelection{
			Project:       currentSelection.Project,
			ProjectPath:   currentSelection.ProjectPath,
			SU:            newName,
			SUPath:        targetPath,
			Hierarchy:     currentSelection.Hierarchy,
			HierarchyPath: currentSelection.HierarchyPath,
		})
		if swErr != nil {
			return nil, swErr
		}
		out.Activated = true
		out.ContextID = nextState.ContextID
		out.NewState = &nextState
	}
	return out, nil
}
