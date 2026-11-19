package validation

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"slices"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type ComplianceOptions struct {
	UseActiveSU bool `json:"useActiveSu"`
}

func (r *ComplianceOptions) UnmarshalJSON(data []byte) error {
	type plain ComplianceOptions
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type EnvironmentCodeFinding struct {
	ListName   string `json:"listName"`
	Field      string `json:"field"`
	PlotNumber string `json:"plotNumber"`
	Value      string `json:"value"`
}

type SkippedListDefinition struct {
	ListName string `json:"listName"`
	Field    string `json:"field"`
	Reason   string `json:"reason"`
}

type BoundsFinding struct {
	Table      string `json:"table"`
	PlotNumber string `json:"plotNumber"`
	RowID      int64  `json:"rowId"`
	Field      string `json:"field"`
	Value      string `json:"value"`
	Rule       string `json:"rule"`
}

type EnvAdminCompletenessFinding struct {
	PlotNumber string `json:"plotNumber"`
	Issue      string `json:"issue"` // "missing_admin" | "orphan_admin"
}

type OrphanChildFinding struct {
	Table      string `json:"table"` // "Veg" | "Humus" | "Mineral" | "Other" | "Audit" | "SU"
	PlotNumber string `json:"plotNumber"`
	RowCount   int    `json:"rowCount"`
}

type DuplicateVegSpeciesFinding struct {
	PlotNumber        string   `json:"plotNumber"`
	Species           string   `json:"species"`
	RowCount          int      `json:"rowCount"`
	OverlappingLayers []string `json:"overlappingLayers"`
}

type TaxonomyComplianceFinding struct {
	RowID         int64   `json:"rowId"`
	ID            int64   `json:"id"`
	PlotNumber    string  `json:"plotNumber"`
	Species       string  `json:"species"`
	Status        string  `json:"status"` // "missing" | "synonym" | "user" | "unlisted"
	SuggestedCode *string `json:"suggestedCode,omitempty"`
}

type ComplianceSummaryCounts struct {
	EnvCodeErrors          int `json:"envCodeErrors"`
	BoundsErrors           int `json:"boundsErrors"`
	EnvAdminMismatches     int `json:"envAdminMismatches"`
	OrphanChildRows        int `json:"orphanChildRows"`
	DuplicateSpeciesSplits int `json:"duplicateSpeciesSplits"`
	UnlistedSpecies        int `json:"unlistedSpecies"`
	SynonymSpecies         int `json:"synonymSpecies"`
	UserSpecies            int `json:"userSpecies"`
	PlotsWithoutVeg        int `json:"plotsWithoutVeg"`
}

type ComplianceValidationReport struct {
	Project                string                        `json:"project"`
	SU                     string                        `json:"su"`
	UseActiveSU            bool                          `json:"useActiveSu"`
	Passed                 bool                          `json:"passed"`
	Summary                ComplianceSummaryCounts       `json:"summary"`
	EnvCodeFindings        []EnvironmentCodeFinding      `json:"envCodeFindings"`
	SkippedDefinitions     []SkippedListDefinition       `json:"skippedDefinitions"`
	BoundsFindings         []BoundsFinding               `json:"boundsFindings"`
	EnvAdminFindings       []EnvAdminCompletenessFinding `json:"envAdminFindings"`
	OrphanFindings         []OrphanChildFinding          `json:"orphanFindings"`
	PlotsWithoutVegetation []string                      `json:"plotsWithoutVegetation"`
	DuplicateVegFindings   []DuplicateVegSpeciesFinding  `json:"duplicateVegFindings"`
	TaxonomyFindings       []TaxonomyComplianceFinding   `json:"taxonomyFindings"`
}

func asciiLower(s string) string {
	for i := 0; i < len(s); i++ {
		if s[i] >= 'A' && s[i] <= 'Z' {
			b := []byte(s)
			for j := i; j < len(b); j++ {
				if b[j] >= 'A' && b[j] <= 'Z' {
					b[j] += 'a' - 'A'
				}
			}
			return string(b)
		}
	}
	return s
}

func isTextOrNoneAffinityType(declType string) bool {
	u := strings.ToUpper(strings.TrimSpace(declType))
	if u == "" {
		return true
	}
	if strings.Contains(u, "INT") {
		return false
	}
	if strings.Contains(u, "CHAR") || strings.Contains(u, "CLOB") || strings.Contains(u, "TEXT") || strings.Contains(u, "BLOB") {
		return true
	}
	return false
}

func readTableColumnTypes(ctx context.Context, tx *sql.Tx, alias, table string) (map[string]string, map[string]string, error) {
	rows, err := tx.QueryContext(ctx, "PRAGMA "+vprocore.QuoteHeaderIdentifier(alias)+".table_info("+vprocore.QuoteHeaderIdentifier(table)+")")
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()
	names := map[string]string{}
	types := map[string]string{}
	for rows.Next() {
		var cid, notNull, pk int
		var name, typ string
		var def sql.NullString
		if err := rows.Scan(&cid, &name, &typ, &notNull, &def, &pk); err != nil {
			return nil, nil, err
		}
		lower := strings.ToLower(name)
		names[lower] = name
		types[lower] = typ
	}
	return names, types, rows.Err()
}

func buildSUPlotInPreFilter(colExpr string, declType string, suPlots []string) (string, []any) {
	if len(suPlots) == 0 || len(suPlots) > 900 || !isTextOrNoneAffinityType(declType) {
		return "", nil
	}
	placeholders := make([]string, len(suPlots))
	args := make([]any, len(suPlots))
	for i, p := range suPlots {
		if !utf8.ValidString(p) || strings.ContainsRune(p, 0) {
			return "", nil
		}
		placeholders[i] = "?"
		args[i] = p
	}
	return colExpr + " IN (" + strings.Join(placeholders, ",") + ")", args
}

func isValidSingleCover(val float64) bool {
	if math.IsNaN(val) || math.IsInf(val, 0) || val < 0 || math.Abs(val) > math.MaxFloat32 {
		return false
	}
	f32 := float32(val)
	return f32 >= 0 && f32 < 100
}

type QuarantineOrphanRequest struct {
	Tables []string `json:"tables,omitempty"` // Optional subset of ["Veg", "Humus", "Mineral", "Other"]; defaults to all 4
}

func (r *QuarantineOrphanRequest) UnmarshalJSON(data []byte) error {
	type plain QuarantineOrphanRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type QuarantinedTableSummary struct {
	Table           string   `json:"table"`
	QuarantineTable string   `json:"quarantineTable"`
	MovedRows       int      `json:"movedRows"`
	PlotNumbers     []string `json:"plotNumbers"`
}

type QuarantineOrphanResult struct {
	Project            string                    `json:"project"`
	BatchID            string                    `json:"batchId"`
	TotalQuarantined   int                       `json:"totalQuarantined"`
	ReservedDeletedIDs []int64                   `json:"reservedDeletedIds"`
	AuditRowID         int64                     `json:"auditRowId,omitempty"`
	Tables             []QuarantinedTableSummary `json:"tables"`
}

var allowedQuarantineTables = []string{"Veg", "Humus", "Mineral", "Other"}

// QuarantineOrphanRecords transactionally moves orphan child rows (whose PlotNumber is missing
// from <Project>_Env) into __VPRO_Quarantine_<Table>, preserving all original columns and values,
// reserving positive child IDs in __VPRO_ChildIdentity, and writing an atomic <Project>_Audit receipt.
func QuarantineOrphanRecords(s *vprocore.ContextService, ctx context.Context, contextID string, req QuarantineOrphanRequest) (QuarantineOrphanResult, error) {
	if s == nil {
		return QuarantineOrphanResult{}, errors.New("validation context service is unavailable")
	}
	targetSuffixes := req.Tables
	if len(targetSuffixes) == 0 {
		targetSuffixes = append([]string(nil), allowedQuarantineTables...)
	} else {
		for _, t := range targetSuffixes {
			if !slices.Contains(allowedQuarantineTables, t) {
				return QuarantineOrphanResult{}, fmt.Errorf("unsupported quarantine table suffix %q (allowed: Veg, Humus, Mineral, Other)", t)
			}
		}
	}

	var entropy [8]byte
	if _, err := rand.Read(entropy[:]); err != nil {
		return QuarantineOrphanResult{}, err
	}
	batchID := hex.EncodeToString(entropy[:])

	var out QuarantineOrphanResult
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
			envTbl := vprocore.QuoteHeaderIdentifier(project + "_Env")
			now := time.Now().Format("2006-01-02 15:04:05")

			if err := vprocore.EnsureChildIdentityTable(ctx, tx); err != nil {
				return err
			}

			envTextPlots := map[string]struct{}{}
			eRows, eErr := tx.QueryContext(ctx, `SELECT CAST("PlotNumber" AS BLOB) FROM `+envTbl+` WHERE typeof("PlotNumber")='text'`)
			if eErr != nil {
				return eErr
			}
			if err := func() (scanErr error) {
				defer func() { scanErr = errors.Join(scanErr, eRows.Close()) }()
				for eRows.Next() {
					var raw []byte
					if err := eRows.Scan(&raw); err != nil {

						return err
					}
					envTextPlots[string(raw)] = struct{}{}
				}
				return eRows.Err()
			}(); err != nil {
				return err
			}

			var summaries []QuarantinedTableSummary
			var reservedIDs []int64
			totalMoved := 0

			for _, suffix := range targetSuffixes {
				if err := ctx.Err(); err != nil {
					return err
				}
				srcTableName := project + "_" + suffix
				quotedSrc := vprocore.QuoteHeaderIdentifier(srcTableName)
				quarantineTableName := "__VPRO_Quarantine_" + suffix
				quotedQuarantine := vprocore.QuoteHeaderIdentifier(quarantineTableName)

				// Inspect source columns & types so __VPRO_Quarantine_<Suffix> preserves full schema.
				pRows, pErr := tx.QueryContext(ctx, "PRAGMA table_info("+quotedSrc+")")
				if pErr != nil {
					return pErr
				}
				var colNames []string
				var colDefs []string
				hasID := false
				if err := func() (scanErr error) {
					defer func() { scanErr = errors.Join(scanErr, pRows.Close()) }()
					for pRows.Next() {
						var cid, notNull, pk int
						var cName, cType string
						var defVal sql.NullString
						if err := pRows.Scan(&cid, &cName, &cType, &notNull, &defVal, &pk); err != nil {

							return err
						}
						if cName == "ID" {
							hasID = true
						}
						colNames = append(colNames, cName)
						decl := cType
						if strings.TrimSpace(decl) == "" {
							decl = "BLOB"
						}
						colDefs = append(colDefs, vprocore.QuoteHeaderIdentifier(cName)+" "+decl)
					}
					return pRows.Err()
				}(); err != nil {
					return err
				}

				// Single O(N) pass collecting orphan rowids, distinct orphan plot numbers, & positive IDs.
				var plotSet []string
				seenPlots := map[string]bool{}
				idExpr := "0"
				if hasID {
					idExpr = `CASE WHEN typeof("ID")='integer' THEN "ID" ELSE 0 END`
				}
				scanRows, sErr := tx.QueryContext(ctx,
					`SELECT rowid, typeof("PlotNumber"), CAST("PlotNumber" AS BLOB), COALESCE(CAST("PlotNumber" AS TEXT), '<NULL>'), `+idExpr+
						` FROM `+quotedSrc+` ORDER BY rowid`)
				if sErr != nil {
					return sErr
				}
				var orphanRowIDs []int64
				var tableIDs []int64
				if err := func() (scanErr error) {
					defer func() { scanErr = errors.Join(scanErr, scanRows.Close()) }()
					for scanRows.Next() {
						var rowID, id int64
						var plotType, p string
						var rawPlot []byte
						if err := scanRows.Scan(&rowID, &plotType, &rawPlot, &p, &id); err != nil {

							return err
						}
						if plotType == "text" {
							if _, inEnv := envTextPlots[string(rawPlot)]; inEnv {
								continue
							}
						}
						orphanRowIDs = append(orphanRowIDs, rowID)
						if !seenPlots[p] {
							seenPlots[p] = true
							plotSet = append(plotSet, p)
						}
						if id > 0 {
							tableIDs = append(tableIDs, id)
						}
					}
					return scanRows.Err()
				}(); err != nil {
					return err
				}

				rowCount := len(orphanRowIDs)
				if rowCount == 0 {
					summaries = append(summaries, QuarantinedTableSummary{
						Table:           suffix,
						QuarantineTable: quarantineTableName,
						MovedRows:       0,
						PlotNumbers:     []string{},
					})
					continue
				}

				metaDefs := []string{
					`"__QuarantineBatchID" TEXT NOT NULL`,
					`"__QuarantinedAt" TEXT NOT NULL`,
					`"__QuarantinedBy" TEXT NOT NULL`,
					`"__SourceRowID" INTEGER NOT NULL`,
				}
				createQuarantineSQL := `CREATE TABLE IF NOT EXISTS ` + quotedQuarantine + ` (` +
					strings.Join(append(metaDefs, colDefs...), ", ") + `)`
				if _, err := tx.ExecContext(ctx, createQuarantineSQL); err != nil {
					return err
				}

				quotedCols := make([]string, len(colNames))
				for i, c := range colNames {
					quotedCols[i] = vprocore.QuoteHeaderIdentifier(c)
				}
				joinedCols := strings.Join(quotedCols, ", ")

				const batchSize = 500
				movedTotal := 0
				deletedTotal := 0
				for start := 0; start < len(orphanRowIDs); start += batchSize {
					end := start + batchSize
					if end > len(orphanRowIDs) {
						end = len(orphanRowIDs)
					}
					chunk := orphanRowIDs[start:end]
					ph := make([]string, len(chunk))
					insArgs := make([]any, 0, 3+len(chunk))
					insArgs = append(insArgs, batchID, now, user)
					delArgs := make([]any, len(chunk))
					for i, rid := range chunk {
						ph[i] = "?"
						insArgs = append(insArgs, rid)
						delArgs[i] = rid
					}
					inList := strings.Join(ph, ",")
					insertQuarantineSQL := `INSERT INTO ` + quotedQuarantine +
						` ("__QuarantineBatchID", "__QuarantinedAt", "__QuarantinedBy", "__SourceRowID", ` + joinedCols + `)
						SELECT ?, ?, ?, rowid, ` + joinedCols + `
						FROM ` + quotedSrc + ` WHERE rowid IN (` + inList + `) ORDER BY rowid`
					insRes, insErr := tx.ExecContext(ctx, insertQuarantineSQL, insArgs...)
					if insErr != nil {
						return insErr
					}
					moved, _ := insRes.RowsAffected()
					movedTotal += int(moved)

					delRes, delErr := tx.ExecContext(ctx, `DELETE FROM `+quotedSrc+` WHERE rowid IN (`+inList+`)`, delArgs...)
					if delErr != nil {
						return delErr
					}
					deleted, _ := delRes.RowsAffected()
					deletedTotal += int(deleted)
				}
				if movedTotal != rowCount {
					return errors.New("quarantine insert row count mismatch; transaction aborted")
				}
				if deletedTotal != rowCount {
					return errors.New("quarantine delete row count mismatch; transaction aborted")
				}

				for _, id := range tableIDs {
					if err := vprocore.ReserveChildID(ctx, tx, quotedSrc, id); err != nil {
						return err
					}
					reservedIDs = append(reservedIDs, id)
				}

				totalMoved += rowCount
				slices.Sort(plotSet)
				summaries = append(summaries, QuarantinedTableSummary{
					Table:           suffix,
					QuarantineTable: quarantineTableName,
					MovedRows:       rowCount,
					PlotNumbers:     plotSet,
				})
			}

			var auditID int64
			if totalMoved > 0 {
				receiptBytes, _ := json.Marshal(map[string]any{
					"batchId":          batchID,
					"totalQuarantined": totalMoved,
					"tables":           summaries,
				})
				// Note: PlotNumber is kept NULL because <Project>_Audit has a foreign key to <Project>_Env(PlotNumber).
				aID, aErr := vprocore.RecordAudit(ctx, tx, vprocore.AuditWriteEntry{
					Project:   project,
					User:      user,
					Table:     "__VPRO_Quarantine",
					EditField: vprocore.AuditString("QuarantineOrphanRecords"),
					EditWhen:  now,
					AfterEdit: string(receiptBytes),
				})
				if aErr != nil {
					return aErr
				}
				auditID = aID
			}

			if err := ctx.Err(); err != nil {
				return err
			}
			if err := tx.Commit(); err != nil {
				return err
			}
			slices.Sort(reservedIDs)
			reservedIDs = slices.Compact(reservedIDs)
			out = QuarantineOrphanResult{
				Project:            project,
				BatchID:            batchID,
				TotalQuarantined:   totalMoved,
				ReservedDeletedIDs: reservedIDs,
				AuditRowID:         auditID,
				Tables:             summaries,
			}
			return nil
		})
	})
	if err != nil {
		return QuarantineOrphanResult{}, err
	}
	return out, nil
}
