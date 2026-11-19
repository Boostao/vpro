package sourceform

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"reflect"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/boostao/vpro/app/internal/vprocore"
)

const siviIdentityHistoryTable = "__VPRO_SIVIIdentityHistory"
const SiviIdentityHistorySQL = `CREATE TABLE "__VPRO_SIVIIdentityHistory"(ID INTEGER PRIMARY KEY,Created TEXT NOT NULL,Proposal TEXT NOT NULL,Restored TEXT)`
const SourceIdentityLedger = "__VPRO_ChildIdentity"

type SiviIdentityHistory struct {
	Project, Plot   string
	Extended        bool
	Before          vprocore.ProjectMetadataTable
	Edits           []SiviHeightEdit
	Committed       vprocore.ProjectMetadataTable
	ReturnOccupants []siviIdentityOccupant
	Audits          []vprocore.AuditEntry
}

func WithSIVIIdentityWriter[T any](ctx context.Context, service *vprocore.ContextService, contextID, plot, operation string,
	apply func(*vprocore.PlotService, *vprocore.SqliteContext, *sql.Tx) (*T, bool, error)) (*T, error) {
	return vprocore.WithContextPlotRequest(ctx, service, contextID, func(plots *vprocore.PlotService) (*T, error) {
		if err := plots.RequireContextEdit(); err != nil {
			return nil, err
		}
		owner := plots.Projects.Sqlite
		var result *T
		committed := false
		err := owner.WithMetadataWriter(ctx, func(conn *sql.Conn) (resultErr error) {
			if err := SiviHeightContextParent(ctx, owner, plot); err != nil {
				return err
			}
			tx, err := conn.BeginTx(ctx, nil)
			if err != nil {
				return err
			}
			defer func() {
				if err := tx.Rollback(); err != nil && !errors.Is(err, sql.ErrTxDone) {
					resultErr = errors.Join(resultErr, err)
				}
			}()
			if err := siviHeightParents(ctx, tx, owner.Selection.Project, plot); err != nil {
				return err
			}
			var changed bool
			result, changed, err = apply(plots, owner, tx)
			if err != nil {
				return err
			}
			if !changed {
				return ctx.Err()
			}
			if err := owner.ValidateMetadataWriterFiles(); err != nil {
				return err
			}
			if err := SiviHeightContextParent(ctx, owner, plot); err != nil {
				return err
			}
			if err := ctx.Err(); err != nil {
				return err
			}
			if err := tx.Commit(); err != nil {
				return err
			}
			committed = true
			return nil
		})
		if err != nil {
			if committed {
				return nil, fmt.Errorf("SIVI identity %s committed but cleanup failed; reload before retrying: %w", operation, err)
			}
			return nil, errors.Join(err, ctx.Err())
		}
		return result, nil
	})
}

func WriteSIVIIdentities(s *vprocore.ContextService, ctx context.Context, contextID, plot string, extended bool, original []SiviVegetationProjection, edits []SiviHeightEdit) (*siviHeightWriteResult, error) {
	return WithSIVIIdentityWriter(ctx, s, contextID, plot, "edit",
		func(plots *vprocore.PlotService, owner *vprocore.SqliteContext, tx *sql.Tx) (*siviHeightWriteResult, bool, error) {
			before, err := vprocore.EnvironmentSiteUnitTables(ctx, tx)
			if err != nil {
				return nil, false, err
			}
			project := owner.Selection.Project
			veg := before[project+"_Veg"]
			observed, err := ProjectSIVIVegetation(ctx, plot, extended, veg)
			if err != nil {
				return nil, false, err
			}
			if !reflect.DeepEqual(original, observed) {
				return nil, false, errors.New("SIVI original source rows changed; cancel and reload")
			}
			reserved, err := siviIdentityReservedIDs(project, before)
			if err != nil {
				return nil, false, err
			}
			assignments, err := planSIVIIdentityEdits(ctx, plot, extended, veg, edits, reserved)
			if err != nil {
				return nil, false, err
			}
			result := &siviHeightWriteResult{}
			if len(assignments) == 0 {
				return result, false, nil
			}
			if err := vprocore.ValidateChildPhysicalText("SIVI audit user", plots.CurrentUser, 100); err != nil {
				return nil, false, err
			}
			planned, err := applySIVIIdentityPlan(veg, assignments)
			if err != nil {
				return nil, false, err
			}
			event := SiviIdentityHistory{Project: project, Plot: plot, Extended: extended,
				Before:    vprocore.ProjectMetadataTable{Columns: veg.Columns, Rows: []vprocore.ProjectMetadataRow{}},
				Committed: vprocore.ProjectMetadataTable{Columns: veg.Columns, Rows: []vprocore.ProjectMetadataRow{}},
				Edits:     []SiviHeightEdit{},
				Audits:    []vprocore.AuditEntry{}}
			event.ReturnOccupants, err = siviIdentityReturnOccupants(veg, assignments)
			if err != nil {
				return nil, false, err
			}
			owned := map[string]bool{}
			for _, assignment := range assignments {
				owned[assignment.RowID] = true
				for _, edit := range edits {
					if edit.RowID == assignment.RowID {
						event.Edits = append(event.Edits, edit)
					}
				}
			}
			for i, row := range veg.Rows {
				if owned[row.RowID] {
					event.Before.Rows = append(event.Before.Rows, row)
					event.Committed.Rows = append(event.Committed.Rows, planned.Rows[i])
				}
			}
			baseline, ledger, err := reserveSIVIIdentityPlan(ctx, tx, project, before, assignments)
			if err != nil {
				return nil, false, err
			}
			if err := writeSIVIIdentityAssignments(ctx, tx, project, plot, assignments); err != nil {
				return nil, false, err
			}
			when := time.Now().UTC().Format("2006-01-02 15:04:05")
			var auditRecords []vprocore.AuditEntry
			for _, assignment := range assignments {
				beforeVal, err := vprocore.MetadataCellValue(assignment.Before)
				if err != nil {
					return nil, false, err
				}
				afterVal, err := vprocore.MetadataCellValue(assignment.After)
				if err != nil {
					return nil, false, err
				}
				if !vprocore.AuditHeaderChange(beforeVal, afterVal, plots.AuditStrength) {
					continue
				}
				_, expectedID, err := siviIdentityAuditID(assignment.Before, assignment.After)
				if err != nil {
					return nil, false, err
				}
				plotCopy := plot
				colCopy := assignment.Column
				auditRowID, err := vprocore.RecordAudit(ctx, tx, vprocore.AuditWriteEntry{
					Project:    project,
					User:       plots.CurrentUser,
					PlotNumber: &plotCopy,
					Table:      "_Veg",
					EditField:  &colCopy,
					EditWhen:   when,
					BeforeEdit: vprocore.HeaderAuditValue(beforeVal),
					AfterEdit:  vprocore.HeaderAuditValue(afterVal),
					ID:         expectedID,
				})
				if err != nil {
					return nil, false, err
				}
				actual, err := vprocore.SelectedAuditEntries(tx, project, plot, []int64{auditRowID})
				if err != nil || len(actual) != 1 {
					return nil, false, errors.Join(err, errors.New("SIVI identity audit row was not recorded"))
				}
				record := actual[0]
				if record.Table != "_Veg" || record.EditField != assignment.Column ||
					!reflect.DeepEqual(record.ID, expectedID) || record.User != plots.CurrentUser || record.EditWhen != when ||
					record.Restore || record.Flag || !vprocore.MetadataAuditTextEqual(record.BeforeEdit, beforeVal) ||
					!vprocore.MetadataAuditTextEqual(record.AfterEdit, afterVal) {
					return nil, false, errors.New("SIVI identity inserted audit differs from its typed assignment")
				}
				auditRecords = append(auditRecords, record)
			}
			event.Audits = append(event.Audits, auditRecords...)
			plannedAudit, err := AppendSourcePlannedAudits(baseline[project+"_Audit"], auditRecords)
			if err != nil {
				return nil, false, err
			}
			expected := map[string]vprocore.ProjectMetadataTable{
				project + "_Veg":     planned,
				project + "_Audit":   plannedAudit,
				SourceIdentityLedger: ledger,
			}
			after, err := vprocore.EnvironmentSiteUnitTables(ctx, tx)
			if err != nil {
				return nil, false, err
			}
			if err := vprocore.VerifySiteUnitTransferTables(baseline, after, expected, ""); err != nil {
				return nil, false, fmt.Errorf("SIVI identity transaction differs from its complete plan: %w", err)
			}
			proposal, err := json.Marshal(event)
			if err != nil {
				return nil, false, err
			}
			if err := vprocore.AppendTechnicalProvenance(ctx, tx, siviIdentityHistoryTable, SiviIdentityHistorySQL, string(proposal), "SIVI identity"); err != nil {
				return nil, false, err
			}
			var id int64
			if err := tx.QueryRowContext(ctx, `SELECT MAX(ID) FROM "`+siviIdentityHistoryTable+`"`).Scan(&id); err != nil {
				return nil, false, err
			}
			after, err = vprocore.EnvironmentSiteUnitTables(ctx, tx)
			if err != nil {
				return nil, false, err
			}
			if err := vprocore.VerifySiteUnitTransferTables(baseline, after, expected, siviIdentityHistoryTable); err != nil {
				return nil, false, err
			}
			result.ChangedCells, result.HistoryID = len(assignments), strconv.FormatInt(id, 10)
			return result, true, nil
		})
}

func writeSIVIIdentityAssignments(ctx context.Context, tx *sql.Tx, project, plot string, assignments []SiviHeightAssignment) error {
	table := vprocore.QuoteHeaderIdentifier(project + "_Veg")
	for _, assignment := range assignments {
		if assignment.After.Storage == "integer" {
			var collision bool
			if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM `+table+` WHERE ID=? AND rowid<>?)`,
				assignment.Value, assignment.RowID).Scan(&collision); err != nil {
				return err
			}
			if collision {
				return errors.New("SIVI new ID collides with physical SQLite identity storage")
			}
		}
		if err := updateSIVIPhysicalIdentity(ctx, tx, project, plot, assignment); err != nil {
			return err
		}
	}
	return nil
}

func updateSIVIPhysicalIdentity(ctx context.Context, tx *sql.Tx, project, plot string, assignment SiviHeightAssignment) error {
	old, err := vprocore.MetadataCellValue(assignment.Before)
	if err != nil {
		return err
	}
	updated, err := tx.ExecContext(ctx, `UPDATE `+vprocore.QuoteHeaderIdentifier(project+"_Veg")+
		` SET ID=? WHERE rowid=? AND typeof(PlotNumber)='text' AND PlotNumber COLLATE BINARY IS ? AND typeof(ID)=? AND ID IS ?`,
		assignment.Value, assignment.RowID, plot, assignment.Before.Storage, old)
	if err != nil {
		return err
	}
	if count, err := updated.RowsAffected(); err != nil || count != 1 {
		return errors.Join(err, errors.New("SIVI ID assignment did not affect exactly one original physical row"))
	}
	return nil
}

func reserveSIVIIdentityPlan(ctx context.Context, tx *sql.Tx, project string, before map[string]vprocore.ProjectMetadataTable, assignments []SiviHeightAssignment) (map[string]vprocore.ProjectMetadataTable, vprocore.ProjectMetadataTable, error) {
	cells := make([]vprocore.ProjectMetadataCell, 0, len(assignments)*2)
	for _, assignment := range assignments {
		cells = append(cells, assignment.Before, assignment.After)
	}
	return ReserveSourceChildIdentityPlan(ctx, tx, project, "Veg", "SIVI identity", before, cells)
}

func ReserveSourceChildIdentityPlan(ctx context.Context, tx *sql.Tx, project, kind, operation string, before map[string]vprocore.ProjectMetadataTable, cells []vprocore.ProjectMetadataCell) (map[string]vprocore.ProjectMetadataTable, vprocore.ProjectMetadataTable, error) {
	baseline := before
	ledger, present := before[SourceIdentityLedger]
	if !present {
		if err := vprocore.EnsureChildIdentityTable(ctx, tx); err != nil {
			return nil, vprocore.ProjectMetadataTable{}, err
		}
		created, err := vprocore.EnvironmentSiteUnitTables(ctx, tx)
		if err != nil {
			return nil, vprocore.ProjectMetadataTable{}, err
		}
		if err := vprocore.VerifySiteUnitTransferTables(before, created, nil, SourceIdentityLedger); err != nil {
			return nil, vprocore.ProjectMetadataTable{}, err
		}
		ledger, baseline = created[SourceIdentityLedger], created
		if len(ledger.Rows) != 0 {
			return nil, vprocore.ProjectMetadataTable{}, fmt.Errorf("new %s reservation ledger is not empty", operation)
		}
	}
	if !reflect.DeepEqual(ledger.Columns, []vprocore.ProjectMetadataColumn{{Name: "ChildTable", DeclaredType: "TEXT"}, {Name: "ID", DeclaredType: "INTEGER"}}) {
		return nil, vprocore.ProjectMetadataTable{}, fmt.Errorf("%s reservation schema differs from the existing child ledger", operation)
	}
	expected := vprocore.ProjectMetadataTable{Columns: ledger.Columns, Rows: append([]vprocore.ProjectMetadataRow{}, ledger.Rows...)}
	table := vprocore.QuoteHeaderIdentifier(project + "_" + kind)
	ids := map[string]bool{}
	for _, cell := range cells {
		if cell.Storage == "integer" && cell.Integer != nil {
			ids[*cell.Integer] = true
		}
	}
	for _, row := range ledger.Rows {
		if row.Cells[0].Text != nil && *row.Cells[0].Text == table && row.Cells[1].Integer != nil {
			delete(ids, *row.Cells[1].Integer)
		}
	}
	ordered := make([]string, 0, len(ids))
	for id := range ids {
		ordered = append(ordered, id)
	}
	sort.Strings(ordered)
	for _, id := range ordered {
		rowID, err := vprocore.InsertStrictChildIDReservation(ctx, tx, table, id)
		if err != nil {
			return nil, vprocore.ProjectMetadataTable{}, err
		}
		owner, number := table, id
		expected.Rows = append(expected.Rows, vprocore.ProjectMetadataRow{RowID: strconv.FormatInt(rowID, 10), Cells: []vprocore.ProjectMetadataCell{
			{Storage: "text", Text: &owner}, {Storage: "integer", Integer: &number},
		}})
	}
	sort.Slice(expected.Rows, func(i, j int) bool {
		a, _ := strconv.ParseInt(expected.Rows[i].RowID, 10, 64)
		b, _ := strconv.ParseInt(expected.Rows[j].RowID, 10, 64)
		return a < b
	})
	return baseline, expected, nil
}

func siviIdentityAuditID(before, after vprocore.ProjectMetadataCell) (any, *int64, error) {
	for _, cell := range []vprocore.ProjectMetadataCell{before, after} {
		if cell.Storage == "integer" && cell.Integer != nil {
			parsed, err := strconv.ParseInt(*cell.Integer, 10, 32)
			if err != nil {
				return nil, nil, err
			}
			return parsed, &parsed, nil
		}
	}
	return nil, nil, nil
}

func RestoreSIVIIdentities(s *vprocore.ContextService, ctx context.Context, contextID, plot, historyID string, action vprocore.AuditRestoreAction) (*vprocore.AuditRestoreResult, error) {
	if action != vprocore.AuditRestoreCancel && action != vprocore.AuditRestoreRetain && action != vprocore.AuditRestorePrune {
		return nil, errors.New("SIVI identity restoration requires cancel, retain or prune")
	}
	if action == vprocore.AuditRestoreCancel {
		return &vprocore.AuditRestoreResult{Cancelled: true}, nil
	}
	ids, err := vprocore.AuditRowIDs([]string{historyID})
	if err != nil {
		return nil, err
	}
	return WithSIVIIdentityWriter(ctx, s, contextID, plot, "restoration",
		func(_ *vprocore.PlotService, owner *vprocore.SqliteContext, tx *sql.Tx) (*vprocore.AuditRestoreResult, bool, error) {
			if err := vprocore.VerifyTechnicalProvenance(ctx, tx, siviIdentityHistoryTable, SiviIdentityHistorySQL, "SIVI identity"); err != nil {
				return nil, false, err
			}
			var proposal string
			var restored *string
			if err := tx.QueryRowContext(ctx, `SELECT Proposal,Restored FROM "`+siviIdentityHistoryTable+`" WHERE ID=?`, ids[0]).Scan(&proposal, &restored); err != nil {
				return nil, false, err
			}
			if restored != nil {
				return nil, false, errors.New("SIVI identity history was already restored; do not replay")
			}
			var event SiviIdentityHistory
			if err := vprocore.DecodeProfileLifecycleJSON([]byte(proposal), &event, "Project", "Plot", "Extended", "Before", "Edits", "Committed", "ReturnOccupants", "Audits"); err != nil {
				return nil, false, err
			}
			project := owner.Selection.Project
			before, err := vprocore.EnvironmentSiteUnitTables(ctx, tx)
			if err != nil {
				return nil, false, err
			}
			veg := before[project+"_Veg"]
			assignments, err := planSIVIIdentityRestoration(ctx, project, plot, veg, event)
			if err != nil {
				return nil, false, err
			}
			if len(event.Audits) > len(assignments) {
				return nil, false, errors.New("SIVI identity history has excess audit entries")
			}
			planned, err := applySIVIIdentityPlan(veg, assignments)
			if err != nil {
				return nil, false, err
			}
			audit := before[project+"_Audit"]
			auditColumns, err := vprocore.SiteUnitTransferColumns(audit, "Restore")
			if err != nil {
				return nil, false, err
			}
			audit.Rows = append([]vprocore.ProjectMetadataRow{}, audit.Rows...)
			prunedAuditRows := 0
			seenAudits := map[string]bool{}
			matched := make([]bool, len(assignments))
			for _, record := range event.Audits {
				if err := ctx.Err(); err != nil {
					return nil, false, err
				}
				if seenAudits[record.RowID] || record.EditField != "ID" ||
					record.Restore || record.Flag || record.Project != project || record.PlotNumber != plot {
					return nil, false, errors.New("SIVI identity audit differs from its physical identity/value")
				}
				claimIdx := -1
				for idx, rev := range assignments {
					if matched[idx] {
						continue
					}
					origBeforeVal, err := vprocore.MetadataCellValue(rev.After)
					if err != nil {
						return nil, false, err
					}
					origAfterVal, err := vprocore.MetadataCellValue(rev.Before)
					if err != nil {
						return nil, false, err
					}
					_, expectedID, err := siviIdentityAuditID(rev.After, rev.Before)
					if err != nil {
						return nil, false, err
					}
					if reflect.DeepEqual(record.ID, expectedID) &&
						vprocore.MetadataAuditTextEqual(record.BeforeEdit, origBeforeVal) &&
						vprocore.MetadataAuditTextEqual(record.AfterEdit, origAfterVal) {
						claimIdx = idx
						break
					}
				}
				if claimIdx < 0 {
					return nil, false, errors.New("SIVI identity history audit does not match any planned assignment")
				}
				matched[claimIdx] = true
				seenAudits[record.RowID] = true
				auditIDs, err := vprocore.AuditRowIDs([]string{record.RowID})
				if err != nil {
					return nil, false, err
				}
				actual, err := vprocore.SelectedAuditEntries(tx, project, plot, auditIDs)
				if err != nil {
					return nil, false, err
				}
				normalize := func(entry vprocore.AuditEntry) (vprocore.AuditEntry, error) {
					if !strings.EqualFold(entry.Table, "_Veg") && !strings.EqualFold(entry.Table, project+"_Veg") {
						return vprocore.AuditEntry{}, errors.New("SIVI identity audit has an unavailable restoration table alias")
					}
					entry.Table = "_Veg"
					return entry, nil
				}
				observed, err := normalize(actual[0])
				if err != nil {
					return nil, false, err
				}
				expectedRecord, err := normalize(record)
				if err != nil || !reflect.DeepEqual(observed, expectedRecord) {
					return nil, false, errors.Join(err, errors.New("SIVI identity audit changed; no restoration or pruning"))
				}
				if err := VerifySIVIPhysicalAudit(before[project+"_Audit"], expectedRecord, project); err != nil {
					return nil, false, err
				}
				query := `UPDATE ` + vprocore.QuoteHeaderIdentifier(project+"_Audit") + ` SET Restore=-1 WHERE rowid=?`
				if action == vprocore.AuditRestorePrune {
					query = `DELETE FROM ` + vprocore.QuoteHeaderIdentifier(project+"_Audit") + ` WHERE rowid=?`
				}
				changed, err := tx.ExecContext(ctx, query, auditIDs[0])
				if err != nil {
					return nil, false, err
				}
				if count, err := changed.RowsAffected(); err != nil || count != 1 {
					return nil, false, errors.Join(err, errors.New("SIVI identity audit restoration did not affect exactly one row"))
				}
				for j, row := range audit.Rows {
					if row.RowID != record.RowID {
						continue
					}
					if action == vprocore.AuditRestorePrune {
						audit.Rows = append(audit.Rows[:j], audit.Rows[j+1:]...)
						prunedAuditRows++
					} else {
						truth := "-1"
						audit.Rows[j].Cells = append([]vprocore.ProjectMetadataCell{}, row.Cells...)
						audit.Rows[j].Cells[auditColumns["Restore"]] = vprocore.ProjectMetadataCell{Storage: "integer", Integer: &truth}
					}
					break
				}
			}
			for _, assignment := range assignments {
				if err := updateSIVIPhysicalIdentity(ctx, tx, project, plot, assignment); err != nil {
					return nil, false, err
				}
			}
			when := time.Now().UTC().Format(time.RFC3339Nano)
			updated, err := tx.ExecContext(ctx, `UPDATE "`+siviIdentityHistoryTable+`" SET Restored=? WHERE ID=? AND Restored IS NULL`, when, ids[0])
			if err != nil {
				return nil, false, err
			}
			if count, err := updated.RowsAffected(); err != nil || count != 1 {
				return nil, false, errors.Join(err, errors.New("SIVI identity restoration did not mark exactly one history event"))
			}
			history := before[siviIdentityHistoryTable]
			historyColumns, err := vprocore.SiteUnitTransferColumns(history, "ID", "Restored")
			if err != nil {
				return nil, false, err
			}
			history.Rows = append([]vprocore.ProjectMetadataRow{}, history.Rows...)
			for i, row := range history.Rows {
				if row.Cells[historyColumns["ID"]].Integer != nil && *row.Cells[historyColumns["ID"]].Integer == strconv.FormatInt(ids[0], 10) {
					history.Rows[i].Cells = append([]vprocore.ProjectMetadataCell{}, row.Cells...)
					history.Rows[i].Cells[historyColumns["Restored"]] = vprocore.ProjectMetadataCell{Storage: "text", Text: &when}
				}
			}
			after, err := vprocore.EnvironmentSiteUnitTables(ctx, tx)
			if err != nil {
				return nil, false, err
			}
			if err := vprocore.VerifySiteUnitTransferTables(before, after, map[string]vprocore.ProjectMetadataTable{
				project + "_Veg":         planned,
				project + "_Audit":       audit,
				siviIdentityHistoryTable: history,
			}, ""); err != nil {
				return nil, false, err
			}
			return &vprocore.AuditRestoreResult{
				RestoredRows:    len(assignments),
				PrunedAuditRows: prunedAuditRows,
			}, true, nil
		})
}

func planSIVIIdentityRestoration(ctx context.Context, project, plot string, veg vprocore.ProjectMetadataTable, event SiviIdentityHistory) ([]SiviHeightAssignment, error) {
	if event.Project != project || event.Plot != plot || len(event.Before.Rows) == 0 ||
		!reflect.DeepEqual(event.Before.Columns, veg.Columns) {
		return nil, errors.New("SIVI identity history belongs to another owner or changed schema")
	}
	assignments, err := planSIVIIdentityEdits(ctx, plot, event.Extended, event.Before, event.Edits, nil)
	if err != nil || len(assignments) != len(event.Before.Rows) {
		return nil, errors.Join(err, errors.New("SIVI identity history has incomplete or repeated original assignments"))
	}
	committed, err := applySIVIIdentityPlan(event.Before, assignments)
	if err != nil || !reflect.DeepEqual(committed, event.Committed) {
		return nil, errors.Join(err, errors.New("SIVI identity history changed non-ID fields or committed values"))
	}
	if _, err := vprocore.SiteUnitTransferColumns(veg, "ID"); err != nil {
		return nil, err
	}
	for _, row := range committed.Rows {
		matches := false
		for _, current := range veg.Rows {
			if current.RowID == row.RowID {
				matches = reflect.DeepEqual(row, current)
				break
			}
		}
		if !matches {
			return nil, errors.New("SIVI physical row changed since the identity edit; no restoration or pruning")
		}
	}
	occupants, err := siviIdentityReturnOccupants(veg, assignments)
	if err != nil || !reflect.DeepEqual(occupants, event.ReturnOccupants) {
		return nil, errors.Join(err, errors.New("SIVI original ID occupancy changed; historical duplicates cannot be safely restored"))
	}
	reversed := make([]SiviHeightAssignment, 0, len(assignments))
	for _, assignment := range assignments {
		value, err := vprocore.MetadataCellValue(assignment.Before)
		if err != nil {
			return nil, err
		}
		reversed = append(reversed, SiviHeightAssignment{
			assignment.RowID, "ID", vprocore.CloneSiteUnitCell(assignment.After), vprocore.CloneSiteUnitCell(assignment.Before), value,
		})
	}
	return reversed, ctx.Err()
}
