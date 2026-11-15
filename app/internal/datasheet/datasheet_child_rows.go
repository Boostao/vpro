package datasheet

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"os"
	"slices"
	"strconv"
	"strings"
	"time"
)

type DatasheetInsertChildRowRequest struct {
	TableKey   string                                  `json:"tableKey"`
	PlotNumber string                                  `json:"plotNumber"`
	Cells      map[string]vprocore.ProjectMetadataCell `json:"cells"`
}

func (r *DatasheetInsertChildRowRequest) UnmarshalJSON(data []byte) error {
	type plain DatasheetInsertChildRowRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type DatasheetInsertChildRowResult struct {
	ContextID  string `json:"contextId"`
	TableKey   string `json:"tableKey"`
	TableName  string `json:"tableName"`
	PlotNumber string `json:"plotNumber"`
	RowID      string `json:"rowId"`
	ID         int64  `json:"id"`
	AuditRows  int    `json:"auditRows"`
}

type DatasheetDeleteChildRowRequest struct {
	TableKey           string `json:"tableKey"`
	RowID              string `json:"rowId"`
	ExpectedPlotNumber string `json:"expectedPlotNumber,omitempty"`
	ExpectedID         *int64 `json:"expectedId,omitempty"`
}

func (r *DatasheetDeleteChildRowRequest) UnmarshalJSON(data []byte) error {
	type plain DatasheetDeleteChildRowRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type DatasheetDeleteChildRowResult struct {
	ContextID  string `json:"contextId"`
	TableKey   string `json:"tableKey"`
	TableName  string `json:"tableName"`
	PlotNumber string `json:"plotNumber"`
	RowID      string `json:"rowId"`
	DeletedID  int64  `json:"deletedId"`
	AuditRows  int    `json:"auditRows"`
}

func isEditableDatasheetChildTable(key string) bool {
	return key == "Veg" || key == "Humus" || key == "Mineral" || key == "Other"
}

func validateDatasheetTargetFiles(owner *vprocore.SqliteContext, target resolvedDatasheetTarget) func() error {
	return func() error {
		if err := owner.ValidateMetadataWriterFiles(); err != nil {
			return err
		}
		roleInfo := owner.AttachmentInfo[target.role]
		if roleInfo == nil {
			return fmt.Errorf("datasheet role %s is not attached", target.role)
		}
		for supportRole, info := range owner.AttachmentInfo {
			if strings.HasPrefix(supportRole, "V") && os.SameFile(roleInfo, info) {
				return fmt.Errorf("datasheet target %s shares a file with support database %s; writes are prohibited", target.tableName, supportRole)
			}
		}
		return nil
	}
}

func requirePlotUnlockedInMainTx(ctx context.Context, tx *sql.Tx, project, plotNumber string) error {
	var lockedCount int
	if err := tx.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM main.`+vprocore.QuoteHeaderIdentifier(project+"_Env")+
			` WHERE typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB) AND "Flag" IS NOT NULL AND CAST("Flag" AS INTEGER) <> 0`,
		plotNumber,
	).Scan(&lockedCount); err != nil {
		return err
	}
	if lockedCount > 0 {
		return fmt.Errorf("plot %q is locked (Flag = -1); unlock the plot before editing its child rows", plotNumber)
	}
	return nil
}

// InsertDatasheetChildRow atomically inserts a row into an editable project child table
// (Veg, Humus, Mineral, or Other), enforcing plot existence and lock, LMH25 depth sign,
// cover bounds, monotonic __VPRO_ChildIdentity reservation, and <Project>_Audit provenance.
func InsertDatasheetChildRow(ctx context.Context, contexts *vprocore.ContextService, contextID string, request DatasheetInsertChildRowRequest) (*DatasheetInsertChildRowResult, error) {
	if ctx == nil {
		return nil, errors.New("datasheet row insert requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("datasheet context service is unavailable")
	}
	if err := vprocore.ValidateChildPhysicalText("PlotNumber", request.PlotNumber, 7); err != nil {
		return nil, err
	}

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*DatasheetInsertChildRowResult, error) {
		owner := plots.Projects.Sqlite
		canEditMaster := plots.CanEditMasterBEC()
		plots.Mu.RLock()
		currentUser := plots.CurrentUser
		plots.Mu.RUnlock()
		if strings.TrimSpace(currentUser) == "" {
			currentUser = "VPro"
		}

		target, err := findDatasheetTarget(owner, request.TableKey)
		if err != nil {
			return nil, err
		}
		if !target.available || target.readOnly || !isEditableDatasheetChildTable(target.key) {
			return nil, fmt.Errorf("datasheet row insert is only supported for editable child tables (Veg, Humus, Mineral, Other), got %q", request.TableKey)
		}

		validateFiles := validateDatasheetTargetFiles(owner, target)
		var out *DatasheetInsertChildRowResult
		wErr := owner.WithSelectedFileWriter(ctx, target.role, validateFiles, func(conn *sql.Conn) (txErr error) {
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
			if err := vprocore.ChildParent(tx, project, request.PlotNumber); err != nil {
				return err
			}
			if err := requirePlotUnlockedInMainTx(ctx, tx, project, request.PlotNumber); err != nil {
				return err
			}

			rawCols, err := vprocore.ReadSQLiteStorageColumns(ctx, tx, "main", target.tableName)
			if err != nil {
				return err
			}
			colMetaByLower := make(map[string]DatasheetColumnMeta, len(rawCols))
			for _, col := range rawCols {
				colMetaByLower[strings.ToLower(col.Name)] = classifyColumnMeta(target.key, col, target.pinnedColumn, canEditMaster)
			}

			if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS "__VPRO_ChildIdentity" (
				"ChildTable" TEXT NOT NULL, "ID" INTEGER NOT NULL, PRIMARY KEY ("ChildTable","ID"))`); err != nil {
				return err
			}
			quotedTable := vprocore.QuoteHeaderIdentifier(target.tableName)
			newID, err := vprocore.AllocateChildID(tx, quotedTable)
			if err != nil {
				return err
			}

			cellKeys := make([]string, 0, len(request.Cells))
			for k := range request.Cells {
				cellKeys = append(cellKeys, k)
			}
			slices.Sort(cellKeys)

			insertCols := []string{`"PlotNumber"`, `"ID"`}
			insertVals := []any{request.PlotNumber, newID}
			hasFlag := false
			var auditCols []string
			var auditAfters []*string
			var effHorizon vprocore.ProjectMetadataCell
			var effUpper vprocore.ProjectMetadataCell
			var effLower vprocore.ProjectMetadataCell
			hasSpecies := false

			for _, key := range cellKeys {
				colMeta, ok := colMetaByLower[strings.ToLower(strings.TrimSpace(key))]
				if !ok {
					return fmt.Errorf("unknown column %q on %s", key, target.tableName)
				}
				if colMeta.Name == "PlotNumber" || colMeta.Name == "ID" {
					continue
				}
				driverVal, auditAfter, normalized, vErr := validateAndNormalizeDatasheetCell(target.key, colMeta, request.Cells[key], canEditMaster)
				if vErr != nil {
					return vErr
				}
				if colMeta.Name == "Flag" {
					hasFlag = true
				}
				if colMeta.Name == "Species" && normalized.Text != nil && strings.TrimSpace(*normalized.Text) != "" {
					hasSpecies = true
				}
				switch colMeta.Name {
				case "Horizon":
					effHorizon = normalized
				case "UpperDepth":
					effUpper = normalized
				case "LowerDepth":
					effLower = normalized
				}
				insertCols = append(insertCols, vprocore.QuoteHeaderIdentifier(colMeta.Name))
				insertVals = append(insertVals, driverVal)
				if normalized.Storage != "null" {
					auditCols = append(auditCols, colMeta.Name)
					auditAfters = append(auditAfters, auditAfter)
				}
			}
			if target.key == "Veg" && !hasSpecies {
				return errors.New("Veg.Species is required when inserting a vegetation row")
			}
			if target.key == "Humus" || target.key == "Mineral" {
				if effHorizon.Text != nil {
					if sErr := validateSoilHorizonDepthSign(target.key, *effHorizon.Text, cellFloat64Ptr(effUpper), cellFloat64Ptr(effLower)); sErr != nil {
						return sErr
					}
				}
			}
			if !hasFlag {
				if _, ok := colMetaByLower["flag"]; ok {
					insertCols = append(insertCols, `"Flag"`)
					insertVals = append(insertVals, int64(0))
				}
			}

			if _, err := tx.ExecContext(ctx, `INSERT INTO "__VPRO_ChildIdentity" ("ChildTable","ID") VALUES (?,?) ON CONFLICT DO NOTHING`,
				quotedTable, newID); err != nil {
				return err
			}
			marks := strings.TrimSuffix(strings.Repeat("?,", len(insertCols)), ",")
			res, err := tx.ExecContext(ctx, `INSERT INTO main.`+quotedTable+` (`+strings.Join(insertCols, ",")+`) VALUES (`+marks+`)`, insertVals...)
			if err != nil {
				return err
			}
			rid, err := res.LastInsertId()
			if err != nil {
				return err
			}

			auditTable := vprocore.QuoteHeaderIdentifier(project + "_Audit")
			tableSuffix := "_" + target.key
			now := time.Now().Format("2006-01-02 15:04:05")
			for i, colName := range auditCols {
				if _, err := tx.ExecContext(ctx,
					`INSERT INTO main.`+auditTable+
						` ("Project","User","PlotNumber","Table","EditField","EditWhen","BeforeEdit","AfterEdit","Restore","Flag","ID") VALUES (?,?,?,?,?,?,?,?,0,0,?)`,
					project, currentUser, request.PlotNumber, tableSuffix, colName, now, nil, auditAfters[i], newID,
				); err != nil {
					return err
				}
			}

			proposalBytes, err := json.Marshal(struct {
				ContextID string                         `json:"contextId"`
				User      string                         `json:"user"`
				Request   DatasheetInsertChildRowRequest `json:"request"`
				ID        int64                          `json:"id"`
			}{contextID, currentUser, request, newID})
			if err != nil {
				return err
			}
			if err := vprocore.AppendTechnicalProvenance(ctx, tx, datasheetHistoryTable, datasheetHistorySQL, string(proposalBytes), "datasheet row insert"); err != nil {
				return err
			}
			if err := validateFiles(); err != nil {
				return err
			}
			if err := tx.Commit(); err != nil {
				return err
			}
			out = &DatasheetInsertChildRowResult{
				ContextID:  contextID,
				TableKey:   target.key,
				TableName:  target.tableName,
				PlotNumber: request.PlotNumber,
				RowID:      strconv.FormatInt(rid, 10),
				ID:         newID,
				AuditRows:  len(auditCols),
			}
			return nil
		})
		if wErr != nil {
			return nil, wErr
		}
		return out, nil
	})
}

// DeleteDatasheetChildRow atomically deletes an existing row from an editable project child table
// (Veg, Humus, Mineral, or Other), permanently reserving its ID in __VPRO_ChildIdentity and
// recording <Project>_Audit provenance.
func DeleteDatasheetChildRow(ctx context.Context, contexts *vprocore.ContextService, contextID string, request DatasheetDeleteChildRowRequest) (*DatasheetDeleteChildRowResult, error) {
	if ctx == nil {
		return nil, errors.New("datasheet row delete requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("datasheet context service is unavailable")
	}
	rid, parseErr := strconv.ParseInt(strings.TrimSpace(request.RowID), 10, 64)
	if parseErr != nil {
		return nil, fmt.Errorf("invalid datasheet rowId %q", request.RowID)
	}

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*DatasheetDeleteChildRowResult, error) {
		owner := plots.Projects.Sqlite
		canEditMaster := plots.CanEditMasterBEC()
		plots.Mu.RLock()
		currentUser := plots.CurrentUser
		plots.Mu.RUnlock()
		if strings.TrimSpace(currentUser) == "" {
			currentUser = "VPro"
		}

		target, err := findDatasheetTarget(owner, request.TableKey)
		if err != nil {
			return nil, err
		}
		if !target.available || target.readOnly || !isEditableDatasheetChildTable(target.key) {
			return nil, fmt.Errorf("datasheet row delete is only supported for editable child tables (Veg, Humus, Mineral, Other), got %q", request.TableKey)
		}

		validateFiles := validateDatasheetTargetFiles(owner, target)
		var out *DatasheetDeleteChildRowResult
		wErr := owner.WithSelectedFileWriter(ctx, target.role, validateFiles, func(conn *sql.Conn) (txErr error) {
			tx, err := conn.BeginTx(ctx, nil)
			if err != nil {
				return err
			}
			defer func() {
				if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
					txErr = errors.Join(txErr, rb)
				}
			}()

			rawCols, err := vprocore.ReadSQLiteStorageColumns(ctx, tx, "main", target.tableName)
			if err != nil {
				return err
			}
			columns := make([]DatasheetColumnMeta, len(rawCols))
			colIdxByLower := make(map[string]int, len(rawCols))
			for i, col := range rawCols {
				columns[i] = classifyColumnMeta(target.key, col, target.pinnedColumn, canEditMaster)
				colIdxByLower[strings.ToLower(col.Name)] = i
			}
			cells, err := readSinglePhysicalRowByRowID(ctx, tx, target.tableName, columns, rid)
			if err != nil {
				return err
			}
			pIdx, okP := colIdxByLower["plotnumber"]
			idIdx, okID := colIdxByLower["id"]
			if !okP || !okID || cells[pIdx].Text == nil || cells[idIdx].Integer == nil {
				return fmt.Errorf("%s row %d is missing PlotNumber or ID identity", target.tableName, rid)
			}
			plotNumber := *cells[pIdx].Text
			childID, err := strconv.ParseInt(*cells[idIdx].Integer, 10, 64)
			if err != nil {
				return fmt.Errorf("%s row %d has non-integer ID %q", target.tableName, rid, *cells[idIdx].Integer)
			}
			if request.ExpectedPlotNumber != "" && request.ExpectedPlotNumber != plotNumber {
				return fmt.Errorf("concurrency conflict on %s row %d: expected PlotNumber %q, stored %q", target.tableName, rid, request.ExpectedPlotNumber, plotNumber)
			}
			if request.ExpectedID != nil && *request.ExpectedID != childID {
				return fmt.Errorf("concurrency conflict on %s row %d: expected ID %d, stored %d", target.tableName, rid, *request.ExpectedID, childID)
			}

			project := owner.Selection.Project
			if err := requirePlotUnlockedInMainTx(ctx, tx, project, plotNumber); err != nil {
				return err
			}

			quotedTable := vprocore.QuoteHeaderIdentifier(target.tableName)
			if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS "__VPRO_ChildIdentity" (
				"ChildTable" TEXT NOT NULL, "ID" INTEGER NOT NULL, PRIMARY KEY ("ChildTable","ID"))`); err != nil {
				return err
			}
			if _, err := tx.ExecContext(ctx, `INSERT INTO "__VPRO_ChildIdentity" ("ChildTable","ID") VALUES (?,?) ON CONFLICT DO NOTHING`,
				quotedTable, childID); err != nil {
				return err
			}

			res, err := tx.ExecContext(ctx, `DELETE FROM main.`+quotedTable+` WHERE rowid = ?`, rid)
			if err != nil {
				return err
			}
			if affected, aErr := res.RowsAffected(); aErr != nil || affected != 1 {
				return errors.Join(aErr, fmt.Errorf("delete %s row %d affected %d rows (expected 1)", target.tableName, rid, affected))
			}

			auditTable := vprocore.QuoteHeaderIdentifier(project + "_Audit")
			tableSuffix := "_" + target.key
			now := time.Now().Format("2006-01-02 15:04:05")
			auditCount := 0
			for i, col := range columns {
				if col.Name == "PlotNumber" || col.Name == "ID" || cells[i].Storage == "null" {
					continue
				}
				beforeText := auditTextForStoredCell(cells[i], col.IsBoolean)
				if _, err := tx.ExecContext(ctx,
					`INSERT INTO main.`+auditTable+
						` ("Project","User","PlotNumber","Table","EditField","EditWhen","BeforeEdit","AfterEdit","Restore","Flag","ID") VALUES (?,?,?,?,?,?,?,?,0,0,?)`,
					project, currentUser, plotNumber, tableSuffix, col.Name, now, beforeText, nil, childID,
				); err != nil {
					return err
				}
				auditCount++
			}
			if auditCount == 0 {
				if _, err := tx.ExecContext(ctx,
					`INSERT INTO main.`+auditTable+
						` ("Project","User","PlotNumber","Table","EditField","EditWhen","BeforeEdit","AfterEdit","Restore","Flag","ID") VALUES (?,?,?,?,?,?,?,?,0,0,?)`,
					project, currentUser, plotNumber, tableSuffix, "ID", now, cells[idIdx].Integer, nil, childID,
				); err != nil {
					return err
				}
				auditCount = 1
			}

			proposalBytes, err := json.Marshal(struct {
				ContextID string                         `json:"contextId"`
				User      string                         `json:"user"`
				Request   DatasheetDeleteChildRowRequest `json:"request"`
				Plot      string                         `json:"plotNumber"`
				DeletedID int64                          `json:"deletedId"`
			}{contextID, currentUser, request, plotNumber, childID})
			if err != nil {
				return err
			}
			if err := vprocore.AppendTechnicalProvenance(ctx, tx, datasheetHistoryTable, datasheetHistorySQL, string(proposalBytes), "datasheet row delete"); err != nil {
				return err
			}
			if err := validateFiles(); err != nil {
				return err
			}
			if err := tx.Commit(); err != nil {
				return err
			}
			out = &DatasheetDeleteChildRowResult{
				ContextID:  contextID,
				TableKey:   target.key,
				TableName:  target.tableName,
				PlotNumber: plotNumber,
				RowID:      strconv.FormatInt(rid, 10),
				DeletedID:  childID,
				AuditRows:  auditCount,
			}
			return nil
		})
		if wErr != nil {
			return nil, wErr
		}
		return out, nil
	})
}
