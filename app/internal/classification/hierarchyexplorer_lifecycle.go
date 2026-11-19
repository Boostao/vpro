package classification

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

const (
	hierarchyIdentityTable = "__VPRO_HierarchyIdentity"
	hierarchyHistoryTable  = "__VPRO_HierarchyEditHistory"
	hierarchyHistorySQL    = `CREATE TABLE "__VPRO_HierarchyEditHistory"(ID INTEGER PRIMARY KEY,Created TEXT NOT NULL,Proposal TEXT NOT NULL)`
)

type CreateHierarchyTableRequest struct {
	Name        string `json:"name"`
	Destination string `json:"destination"` // "project" (default) | "new_file"
	FilePath    string `json:"filePath"`
	Activate    bool   `json:"activate"`
}

func (r *CreateHierarchyTableRequest) UnmarshalJSON(data []byte) error {
	type plain CreateHierarchyTableRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type SaveHierarchyTableAsRequest struct {
	SourceHierarchy string `json:"sourceHierarchy"` // defaults to active Hierarchy when empty
	NewName         string `json:"newName"`
	Destination     string `json:"destination"` // "project" (default) | "new_file"
	FilePath        string `json:"filePath"`
	Activate        bool   `json:"activate"`
}

func (r *SaveHierarchyTableAsRequest) UnmarshalJSON(data []byte) error {
	type plain SaveHierarchyTableAsRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type HierarchyTableLifecycleResult struct {
	ContextID string                 `json:"contextId"`
	Name      string                 `json:"name"`
	TableName string                 `json:"tableName"`
	FilePath  string                 `json:"filePath"`
	Activated bool                   `json:"activated"`
	NewState  *vprocore.ProjectState `json:"newState,omitempty"`
}

func createHierarchyTableObjectsInTx(ctx context.Context, tx *sql.Tx, hierName string) error {
	tableName := hierName + "_Hierarchy"
	var collision int
	if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM main.sqlite_master WHERE name = ? COLLATE NOCASE`, tableName).Scan(&collision); err != nil {
		return err
	}
	if collision != 0 {
		return fmt.Errorf("hierarchy table %s already exists in target database", tableName)
	}
	qTable := vprocore.QuoteHeaderIdentifier(tableName)
	if _, err := tx.ExecContext(ctx, `CREATE TABLE main.`+qTable+` (
		"ID" INTEGER PRIMARY KEY,
		"Name" VARCHAR NOT NULL,
		"Parent" INTEGER,
		"Level" SMALLINT,
		"Tag" VARCHAR,
		"MyOrder" VARCHAR,
		"ChildID" SMALLINT,
		"StartChild" SMALLINT,
		"LastChild" SMALLINT,
		"Flag" BOOLEAN
	)`); err != nil {
		return err
	}
	for _, idx := range []struct {
		unique bool
		name   string
		col    string
	}{
		{true, "uidx_" + tableName + "_Name", "Name"},
		{false, "idx_" + tableName + "_Parent", "Parent"},
		{false, "idx_" + tableName + "_Level", "Level"},
		{false, "idx_" + tableName + "_ChildID", "ChildID"},
	} {
		kw := "CREATE INDEX "
		if idx.unique {
			kw = "CREATE UNIQUE INDEX "
		}
		if _, err := tx.ExecContext(ctx, kw+"main."+vprocore.QuoteHeaderIdentifier(idx.name)+" ON "+qTable+" ("+vprocore.QuoteHeaderIdentifier(idx.col)+")"); err != nil {
			return err
		}
	}
	if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS main._table_metadata (table_name TEXT PRIMARY KEY, description TEXT)`); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `INSERT OR REPLACE INTO main._table_metadata (table_name, description) VALUES (?, 'VP04')`, tableName); err != nil {
		return err
	}
	return nil
}

func CreateHierarchyTable(ctx context.Context, contexts *vprocore.ContextService, contextID string, request CreateHierarchyTableRequest) (*HierarchyTableLifecycleResult, error) {
	if ctx == nil {
		return nil, errors.New("hierarchy creation requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("classification context service is unavailable")
	}
	hierName, err := validateClassificationObjectName(request.Name, "Hierarchy")
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
		return nil, fmt.Errorf("unsupported hierarchy destination %q", request.Destination)
	}

	var out *HierarchyTableLifecycleResult
	var targetPath string
	var currentSelection vprocore.DesktopSelection

	_, err = vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (struct{}, error) {
		owner := plots.Projects.Sqlite
		currentSelection = owner.Selection
		tableName := hierName + "_Hierarchy"
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
				if err := createHierarchyTableObjectsInTx(ctx, tx, hierName); err != nil {
					return err
				}
				if err := vprocore.AppendTechnicalProvenance(ctx, tx, hierarchyHistoryTable, hierarchyHistorySQL, string(proposalBytes), "hierarchy creation"); err != nil {
					return err
				}
				return tx.Commit()
			})
			if err != nil {
				return struct{}{}, err
			}
		} else {
			freshPath, _, fErr := vprocore.FreshSQLiteDestination(request.FilePath, "Hierarchy")
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
					_ = os.Remove(freshPath)
				}
			}()
			tx, bErr := db.BeginTx(ctx, nil)
			if bErr != nil {
				return struct{}{}, bErr
			}
			if err := createHierarchyTableObjectsInTx(ctx, tx, hierName); err != nil {
				_ = tx.Rollback()
				return struct{}{}, err
			}
			if err := vprocore.AppendTechnicalProvenance(ctx, tx, hierarchyHistoryTable, hierarchyHistorySQL, string(proposalBytes), "hierarchy file creation"); err != nil {
				_ = tx.Rollback()
				return struct{}{}, err
			}
			if err := tx.Commit(); err != nil {
				return struct{}{}, err
			}
			committed = true
		}

		out = &HierarchyTableLifecycleResult{
			ContextID: contextID,
			Name:      hierName,
			TableName: tableName,
			FilePath:  targetPath,
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
			SU:            currentSelection.SU,
			SUPath:        currentSelection.SUPath,
			Hierarchy:     hierName,
			HierarchyPath: filepath.Clean(targetPath),
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

// SaveHierarchyTableAs clones an existing hierarchy table (preserving IDs and legacy columns
// MyOrder, ChildID, StartChild, LastChild, Flag) into the project DB or a fresh external .db file.
func SaveHierarchyTableAs(ctx context.Context, contexts *vprocore.ContextService, contextID string, request SaveHierarchyTableAsRequest) (*HierarchyTableLifecycleResult, error) {
	if ctx == nil {
		return nil, errors.New("hierarchy save-as requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("classification context service is unavailable")
	}
	newName, err := validateClassificationObjectName(request.NewName, "Hierarchy")
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
		return nil, fmt.Errorf("unsupported hierarchy save-as destination %q", request.Destination)
	}

	var out *HierarchyTableLifecycleResult
	var targetPath string
	var currentSelection vprocore.DesktopSelection

	_, err = vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (struct{}, error) {
		owner := plots.Projects.Sqlite
		currentSelection = owner.Selection
		srcName := strings.TrimSpace(request.SourceHierarchy)
		if srcName == "" {
			srcName = owner.Selection.Hierarchy
		}
		if srcName == "" || strings.EqualFold(srcName, "None") {
			return struct{}{}, errors.New("an active or explicit source hierarchy table is required for Save As")
		}
		srcRole := "hierarchy"
		if !strings.EqualFold(srcName, owner.Selection.Hierarchy) {
			srcRole = "project"
		}
		srcTable := srcName + "_Hierarchy"
		destTable := newName + "_Hierarchy"

		type copiedHierRow struct {
			id         int64
			name       string
			parent     any
			level      any
			tag        any
			myOrder    any
			childID    any
			startChild any
			lastChild  any
			flag       any
		}
		var copied []copiedHierRow

		snapErr := owner.WithReadSnapshot(ctx, func(tx *sql.Tx) error {

			var physical int
			if qErr := tx.QueryRowContext(ctx,
				`SELECT COUNT(*) FROM `+vprocore.QuoteHeaderIdentifier(srcRole)+`.sqlite_master WHERE type='table' AND name COLLATE BINARY=?`,
				srcTable,
			).Scan(&physical); qErr != nil {
				return qErr
			}
			if physical != 1 {
				return fmt.Errorf("source hierarchy table %s does not exist in %s database", srcTable, srcRole)
			}

			colSet := map[string]bool{}
			colRows, pErr := tx.QueryContext(ctx, `PRAGMA `+vprocore.QuoteHeaderIdentifier(srcRole)+`.table_info(`+vprocore.QuoteHeaderIdentifier(srcTable)+`)`)
			if pErr != nil {
				return pErr
			}
			for colRows.Next() {
				var cid, notNull, pk int
				var name, decl string
				var dflt any
				if sErr := colRows.Scan(&cid, &name, &decl, &notNull, &dflt, &pk); sErr != nil {
					colRows.Close()
					return sErr
				}
				colSet[name] = true
			}
			if cErr := errors.Join(colRows.Err(), colRows.Close()); cErr != nil {
				return cErr
			}
			optExpr := func(col string) string {
				if colSet[col] {
					return vprocore.QuoteHeaderIdentifier(col)
				}
				return "NULL"
			}
			q := fmt.Sprintf(
				`SELECT "ID", COALESCE(CAST("Name" AS TEXT), ''), "Parent", "Level", %s, %s, %s, %s, %s, %s FROM %s.%s ORDER BY "ID" ASC`,
				optExpr("Tag"), optExpr("MyOrder"), optExpr("ChildID"), optExpr("StartChild"), optExpr("LastChild"), optExpr("Flag"),
				vprocore.QuoteHeaderIdentifier(srcRole), vprocore.QuoteHeaderIdentifier(srcTable),
			)
			rows, rErr := tx.QueryContext(ctx, q)
			if rErr != nil {
				return rErr
			}
			for rows.Next() {
				var item copiedHierRow
				if sErr := rows.Scan(&item.id, &item.name, &item.parent, &item.level, &item.tag, &item.myOrder, &item.childID, &item.startChild, &item.lastChild, &item.flag); sErr != nil {
					rows.Close()
					return sErr
				}
				copied = append(copied, item)
			}
			return errors.Join(rows.Err(), rows.Close())
		})
		if snapErr != nil {
			return struct{}{}, snapErr
		}

		proposalBytes, err := json.Marshal(request)
		if err != nil {
			return struct{}{}, err
		}
		writeRows := func(tx *sql.Tx) error {
			if err := createHierarchyTableObjectsInTx(ctx, tx, newName); err != nil {
				return err
			}
			qDest := vprocore.QuoteHeaderIdentifier(destTable)
			for _, item := range copied {
				if _, err := tx.ExecContext(ctx,
					`INSERT INTO main.`+qDest+` ("ID","Name","Parent","Level","Tag","MyOrder","ChildID","StartChild","LastChild","Flag") VALUES (?,?,?,?,?,?,?,?,?,?)`,
					item.id, item.name, item.parent, item.level, item.tag, item.myOrder, item.childID, item.startChild, item.lastChild, item.flag,
				); err != nil {
					return err
				}
			}
			if err := vprocore.SeedHierarchyNodeIDs(ctx, tx, hierarchyIdentityTable, destTable); err != nil {
				return err
			}
			return vprocore.AppendTechnicalProvenance(ctx, tx, hierarchyHistoryTable, hierarchyHistorySQL, string(proposalBytes), "hierarchy save-as")
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
				if err := writeRows(tx); err != nil {
					return err
				}
				return tx.Commit()
			})
			if err != nil {
				return struct{}{}, err
			}
		} else {
			freshPath, _, fErr := vprocore.FreshSQLiteDestination(request.FilePath, "Hierarchy")
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
					_ = os.Remove(freshPath)
				}
			}()
			tx, bErr := db.BeginTx(ctx, nil)
			if bErr != nil {
				return struct{}{}, bErr
			}
			if err := writeRows(tx); err != nil {
				_ = tx.Rollback()
				return struct{}{}, err
			}
			if err := tx.Commit(); err != nil {
				return struct{}{}, err
			}
			committed = true
		}

		out = &HierarchyTableLifecycleResult{
			ContextID: contextID,
			Name:      newName,
			TableName: destTable,
			FilePath:  targetPath,
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
			SU:            currentSelection.SU,
			SUPath:        currentSelection.SUPath,
			Hierarchy:     newName,
			HierarchyPath: filepath.Clean(targetPath),
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
