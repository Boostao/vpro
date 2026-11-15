package classification

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"unicode/utf16"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/references"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

const (
	suAssignmentHistoryTable = "__VPRO_SUEnvironmentHistory"
	suAssignmentHistorySQL   = `CREATE TABLE "__VPRO_SUEnvironmentHistory"(ID INTEGER PRIMARY KEY,Created TEXT NOT NULL,Proposal TEXT NOT NULL)`
)

type BECUnitPickerRequest struct {
	Query   string `json:"query"`
	Zone    string `json:"zone"`
	SubZone string `json:"subZone"`
	Limit   int    `json:"limit"`
}

func (r *BECUnitPickerRequest) UnmarshalJSON(data []byte) error {
	type plain BECUnitPickerRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type BECUnitPickerChoice struct {
	SiteSeries     string `json:"siteSeries"`
	LongName       string `json:"longName"`
	ScientificName string `json:"scientificName"`
	Zone           string `json:"zone"`
	SubZone        string `json:"subZone"`
	Alliance       string `json:"alliance,omitempty"`
	Suballiance    string `json:"suballiance,omitempty"`
	Source         string `json:"source"` // "master" | "user" | "becdb_v13"
	MaskValid      bool   `json:"maskValid"`
}

type AssignPlotsToSiteUnitRequest struct {
	PlotNumbers                []string `json:"plotNumbers"`
	TargetSiteUnit             *string  `json:"targetSiteUnit"` // nil or "" means Unassigned
	RemoveFromSUWhenUnassigned bool     `json:"removeFromSuWhenUnassigned"`
}

func (r *AssignPlotsToSiteUnitRequest) UnmarshalJSON(data []byte) error {
	type plain AssignPlotsToSiteUnitRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type suPlotAssignmentDelta struct {
	PlotNumber     string  `json:"plotNumber"`
	ExistedBefore  bool    `json:"existedBefore"`
	BeforeSiteUnit *string `json:"beforeSiteUnit"`
	ExistedAfter   bool    `json:"existedAfter"`
	AfterSiteUnit  *string `json:"afterSiteUnit"`
}

type suPlotAssignmentReceipt struct {
	Kind      string                  `json:"kind"`
	ContextID string                  `json:"contextId"`
	Project   string                  `json:"project"`
	SU        string                  `json:"su"`
	Deltas    []suPlotAssignmentDelta `json:"deltas"`
}

type AssignPlotsToSiteUnitResult struct {
	ContextID    string `json:"contextId"`
	SU           string `json:"su"`
	TableName    string `json:"tableName"`
	ChangedPlots int    `json:"changedPlots"`
	HistoryID    int64  `json:"historyId"`
}

func splitZoneSubZoneFromUnitCode(code string) (string, string) {
	compact := compactBECUnitCode(code)
	slashIdx := strings.IndexByte(compact, '/')
	prefix := compact
	if slashIdx >= 0 {
		prefix = compact[:slashIdx]
	}
	i := 0
	for i < len(prefix) && prefix[i] >= 'A' && prefix[i] <= 'Z' {
		i++
	}
	return prefix[:i], prefix[i:]
}

func SearchBECUnitPicker(
	ctx context.Context,
	contexts *vprocore.ContextService,
	bec *references.BECService,
	contextID string,
	request BECUnitPickerRequest,
) ([]BECUnitPickerChoice, error) {
	if ctx == nil {
		return nil, errors.New("BEC unit picker requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	limit := request.Limit
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	q := strings.ToLower(strings.TrimSpace(request.Query))
	qCompact := strings.ToLower(compactBECUnitCode(request.Query))
	zFilter := strings.ToUpper(strings.TrimSpace(request.Zone))
	szFilter := strings.ToLower(compactBECUnitCode(request.SubZone))

	seen := map[string]bool{}
	choices := []BECUnitPickerChoice{}

	// 1. Include active BECdb v13 units from BECService when available
	if bec != nil {
		var zPtr, szPtr *string
		if zFilter != "" {
			zCopy := zFilter
			zPtr = &zCopy
		}
		if szFilter != "" {
			szCopy := szFilter
			szPtr = &szCopy
		}
		if seriesList, bErr := bec.ListBECSiteSeries(ctx, zPtr, szPtr); bErr == nil {
			for _, item := range seriesList {
				if err := ctx.Err(); err != nil {
					return nil, err
				}
				if item.ExpiredDate != nil && strings.TrimSpace(*item.ExpiredDate) != "" {
					continue
				}
				rawCode := ""
				if item.MergedBGC != nil && strings.TrimSpace(*item.MergedBGC) != "" {
					rawCode = strings.TrimSpace(*item.MergedBGC)
				} else if item.Zone != nil && item.SubZone != nil && item.SSCode != nil &&
					strings.TrimSpace(*item.Zone) != "" && strings.TrimSpace(*item.SSCode) != "" {
					rawCode = strings.TrimSpace(*item.Zone) + strings.TrimSpace(*item.SubZone) + "/" + strings.TrimSpace(*item.SSCode)
				} else if item.SSCode != nil {
					rawCode = strings.TrimSpace(*item.SSCode)
				}
				code := compactBECUnitCode(rawCode)
				if code == "" {
					continue
				}
				lname := ""
				if item.Description != nil && strings.TrimSpace(*item.Description) != "" {
					lname = strings.TrimSpace(*item.Description)
				} else if item.Name != nil {
					lname = strings.TrimSpace(*item.Name)
				}
				sci := ""
				if item.PlantAssociation != nil {
					sci = *item.PlantAssociation
				}
				zoneVal := ""
				if item.Zone != nil {
					zoneVal = *item.Zone
				}
				subVal := ""
				if item.SubZone != nil {
					subVal = *item.SubZone
				}
				alliance := ""
				if item.Alliance != nil {
					alliance = *item.Alliance
				}
				suballiance := ""
				if item.Suballiance != nil {
					suballiance = *item.Suballiance
				}
				if q != "" {
					hay := strings.ToLower(code + " " + rawCode + " " + lname + " " + sci + " " + alliance)
					if !strings.Contains(hay, q) && (qCompact == "" || !strings.Contains(hay, qCompact)) {
						continue
					}
				}
				upper := strings.ToUpper(code)
				if seen[upper] {
					continue
				}
				seen[upper] = true
				choices = append(choices, BECUnitPickerChoice{
					SiteSeries:     code,
					LongName:       lname,
					ScientificName: sci,
					Zone:           zoneVal,
					SubZone:        subVal,
					Alliance:       alliance,
					Suballiance:    suballiance,
					Source:         "becdb_v13",
					MaskValid:      BECUnitMaskValid(code),
				})
				if len(choices) >= limit {
					return choices, nil
				}
			}
		}
	}

	// 2. Supplement with VUser.UserSiteUnitList and VLists.MasterSiteUnitList from active context
	if contexts != nil && contextID != "" {
		extra, err := vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (_ []BECUnitPickerChoice, resultErr error) {
			owner := plots.Projects.Sqlite
			if err := sqlutil.AcquireMutexLease(ctx, &owner.Mu); err != nil {
				return nil, err
			}
			defer owner.Mu.Unlock()
			tx, sErr := owner.BeginReadSnapshot(ctx)
			if sErr != nil {
				return nil, sErr
			}
			defer func() {
				if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
					resultErr = errors.Join(resultErr, rb)
				}
			}()

			var found []BECUnitPickerChoice
			for _, src := range []struct {
				role, table, tag string
			}{
				{"VUser", "UserSiteUnitList", "user"},
				{"VLists", "MasterSiteUnitList", "master"},
			} {
				rows, qErr := tx.QueryContext(ctx,
					`SELECT COALESCE(CAST("SiteSeries" AS TEXT),''),
					        COALESCE(CAST("SiteSeriesLongName" AS TEXT),''),
					        COALESCE(CAST("SiteSeriesScientificName" AS TEXT),'')
					 FROM `+vprocore.QuoteHeaderIdentifier(src.role)+`.`+vprocore.QuoteHeaderIdentifier(src.table)+
						` ORDER BY "SiteSeries" COLLATE NOCASE ASC`)
				if qErr != nil {
					continue
				}
				for rows.Next() {
					var code, lname, sci string
					if err := rows.Scan(&code, &lname, &sci); err != nil {
						continue
					}
					code = strings.TrimSpace(code)
					if code == "" {
						continue
					}
					compact := compactBECUnitCode(code)
					z, sz := splitZoneSubZoneFromUnitCode(code)
					if zFilter != "" && !strings.EqualFold(z, zFilter) {
						continue
					}
					if szFilter != "" && !strings.HasPrefix(strings.ToLower(sz), szFilter) {
						continue
					}
					if q != "" {
						hay := strings.ToLower(code + " " + compact + " " + lname + " " + sci)
						if !strings.Contains(hay, q) && (qCompact == "" || !strings.Contains(hay, qCompact)) {
							continue
						}
					}
					upper := strings.ToUpper(compact)
					if seen[upper] {
						continue
					}
					seen[upper] = true
					found = append(found, BECUnitPickerChoice{
						SiteSeries:     code,
						LongName:       lname,
						ScientificName: sci,
						Zone:           z,
						SubZone:        sz,
						Source:         src.tag,
						MaskValid:      BECUnitMaskValid(code),
					})
					if len(choices)+len(found) >= limit {
						rows.Close()
						_ = tx.Commit()
						return found, nil
					}
				}
				rows.Close()
			}
			_ = tx.Commit()
			return found, nil
		})
		if err == nil {
			choices = append(choices, extra...)
		}
	}

	return choices, nil
}

func AssignPlotsToSiteUnit(ctx context.Context, contexts *vprocore.ContextService, contextID string, request AssignPlotsToSiteUnitRequest) (*AssignPlotsToSiteUnitResult, error) {
	if ctx == nil {
		return nil, errors.New("SU plot assignment requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("classification context service is unavailable")
	}
	if len(request.PlotNumbers) == 0 {
		return nil, errors.New("select at least one plot to assign")
	}

	var normalizedUnit *string
	if request.TargetSiteUnit != nil {
		trimmed := strings.TrimSpace(*request.TargetSiteUnit)
		if !utf8.ValidString(trimmed) || strings.ContainsRune(trimmed, 0) {
			return nil, errors.New("SiteUnit must be valid UTF-8 text without NUL")
		}
		if len(utf16.Encode([]rune(trimmed))) > 255 {
			return nil, errors.New("SiteUnit exceeds 255 UTF-16 code units")
		}
		if trimmed != "" {
			normalizedUnit = &trimmed
		}
	}

	uniquePlots := make([]string, 0, len(request.PlotNumbers))
	seenPlot := map[string]bool{}
	for _, p := range request.PlotNumbers {
		if p == "" || !utf8.ValidString(p) || strings.ContainsRune(p, 0) {
			return nil, fmt.Errorf("invalid plot number %q", p)
		}
		if len(utf16.Encode([]rune(p))) > 7 {
			return nil, fmt.Errorf("plot number %q exceeds 7 UTF-16 code units", p)
		}
		if !seenPlot[p] {
			seenPlot[p] = true
			uniquePlots = append(uniquePlots, p)
		}
	}

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*AssignPlotsToSiteUnitResult, error) {
		owner := plots.Projects.Sqlite
		if owner.Selection.SU == "" || owner.Selection.SU == "None" {
			return nil, errors.New("an active Site Unit (SU) table must be selected before assigning plots")
		}
		suName := owner.Selection.SU
		suTable := suName + "_SU"
		qTable := vprocore.QuoteHeaderIdentifier(suTable)

		validateFiles := func() error {
			if err := owner.ValidateMetadataWriterFiles(); err != nil {
				return err
			}
			suInfo := owner.AttachmentInfo["su"]
			if suInfo == nil {
				return errors.New("active SU file is not attached")
			}
			for role, info := range owner.AttachmentInfo {
				if strings.HasPrefix(role, "V") && os.SameFile(suInfo, info) {
					return fmt.Errorf("SU database shares a file with support role %s; writes are prohibited", role)
				}
			}
			return nil
		}

		res := &AssignPlotsToSiteUnitResult{
			ContextID: contextID,
			SU:        suName,
			TableName: suTable,
		}

		err := owner.WithSelectedFileWriter(ctx, "su", validateFiles, func(conn *sql.Conn) (txErr error) {
			tx, bErr := conn.BeginTx(ctx, nil) // BEGIN IMMEDIATE
			if bErr != nil {
				return bErr
			}
			defer func() {
				if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
					txErr = errors.Join(txErr, rb)
				}
			}()

			deltas := make([]suPlotAssignmentDelta, 0, len(uniquePlots))
			for _, plotNum := range uniquePlots {
				if err := ctx.Err(); err != nil {
					return err
				}
				var rowID int64
				var existing sql.NullString
				qErr := tx.QueryRowContext(ctx,
					`SELECT rowid, CAST("SiteUnit" AS TEXT) FROM main.`+qTable+
						` WHERE "PlotNumber" = ? AND typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB)`,
					plotNum, plotNum,
				).Scan(&rowID, &existing)

				existedBefore := qErr == nil
				if qErr != nil && !errors.Is(qErr, sql.ErrNoRows) {
					return qErr
				}
				var beforePtr *string
				if existedBefore && existing.Valid {
					v := existing.String
					beforePtr = &v
				}

				if normalizedUnit == nil {
					// Moving to Unassigned
					if !existedBefore {
						continue
					}
					if request.RemoveFromSUWhenUnassigned {
						if _, err := tx.ExecContext(ctx, `DELETE FROM main.`+qTable+` WHERE rowid = ?`, rowID); err != nil {
							return err
						}
						deltas = append(deltas, suPlotAssignmentDelta{
							PlotNumber:     plotNum,
							ExistedBefore:  true,
							BeforeSiteUnit: beforePtr,
							ExistedAfter:   false,
							AfterSiteUnit:  nil,
						})
						res.ChangedPlots++
					} else {
						if beforePtr == nil || *beforePtr == "" {
							continue
						}
						if _, err := tx.ExecContext(ctx, `UPDATE main.`+qTable+` SET "SiteUnit" = NULL WHERE rowid = ?`, rowID); err != nil {
							return err
						}
						deltas = append(deltas, suPlotAssignmentDelta{
							PlotNumber:     plotNum,
							ExistedBefore:  true,
							BeforeSiteUnit: beforePtr,
							ExistedAfter:   true,
							AfterSiteUnit:  nil,
						})
						res.ChangedPlots++
					}
				} else {
					// Moving to TargetSiteUnit
					afterCopy := *normalizedUnit
					if existedBefore {
						if beforePtr != nil && *beforePtr == afterCopy {
							continue
						}
						if _, err := tx.ExecContext(ctx, `UPDATE main.`+qTable+` SET "SiteUnit" = ? WHERE rowid = ?`, afterCopy, rowID); err != nil {
							return err
						}
						deltas = append(deltas, suPlotAssignmentDelta{
							PlotNumber:     plotNum,
							ExistedBefore:  true,
							BeforeSiteUnit: beforePtr,
							ExistedAfter:   true,
							AfterSiteUnit:  &afterCopy,
						})
						res.ChangedPlots++
					} else {
						if _, err := tx.ExecContext(ctx, `INSERT INTO main.`+qTable+` ("PlotNumber","SiteUnit") VALUES (?,?)`, plotNum, afterCopy); err != nil {
							return err
						}
						deltas = append(deltas, suPlotAssignmentDelta{
							PlotNumber:     plotNum,
							ExistedBefore:  false,
							BeforeSiteUnit: nil,
							ExistedAfter:   true,
							AfterSiteUnit:  &afterCopy,
						})
						res.ChangedPlots++
					}
				}
			}

			if len(deltas) > 0 {
				receipt := suPlotAssignmentReceipt{
					Kind:      "su_plot_assignment",
					ContextID: contextID,
					Project:   owner.Selection.Project,
					SU:        suName,
					Deltas:    deltas,
				}
				rawReceipt, mErr := json.Marshal(receipt)
				if mErr != nil {
					return mErr
				}
				if err := vprocore.AppendTechnicalProvenance(ctx, tx, suAssignmentHistoryTable, suAssignmentHistorySQL, string(rawReceipt), "SU plot assignment"); err != nil {
					return err
				}
				_ = tx.QueryRowContext(ctx, `SELECT MAX(ID) FROM main.`+vprocore.QuoteHeaderIdentifier(suAssignmentHistoryTable)).Scan(&res.HistoryID)
			}

			if err := validateFiles(); err != nil {
				return err
			}
			if err := ctx.Err(); err != nil {
				return err
			}
			return tx.Commit()
		})
		if err != nil {
			return nil, err
		}
		return res, nil
	})
}

func UndoSUAssignment(ctx context.Context, contexts *vprocore.ContextService, contextID string, historyID int64) (*AssignPlotsToSiteUnitResult, error) {
	if ctx == nil {
		return nil, errors.New("SU undo requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("classification context service is unavailable")
	}

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*AssignPlotsToSiteUnitResult, error) {
		owner := plots.Projects.Sqlite
		if owner.Selection.SU == "" || owner.Selection.SU == "None" {
			return nil, errors.New("an active Site Unit (SU) table must be selected before undoing an assignment")
		}
		suName := owner.Selection.SU
		suTable := suName + "_SU"
		qTable := vprocore.QuoteHeaderIdentifier(suTable)

		validateFiles := func() error {
			return owner.ValidateMetadataWriterFiles()
		}

		res := &AssignPlotsToSiteUnitResult{
			ContextID: contextID,
			SU:        suName,
			TableName: suTable,
		}

		err := owner.WithSelectedFileWriter(ctx, "su", validateFiles, func(conn *sql.Conn) (txErr error) {
			tx, bErr := conn.BeginTx(ctx, nil)
			if bErr != nil {
				return bErr
			}
			defer func() {
				if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
					txErr = errors.Join(txErr, rb)
				}
			}()

			var targetID int64
			var proposal string
			if historyID > 0 {
				err := tx.QueryRowContext(ctx,
					`SELECT ID, Proposal FROM main.`+vprocore.QuoteHeaderIdentifier(suAssignmentHistoryTable)+` WHERE ID = ?`,
					historyID,
				).Scan(&targetID, &proposal)
				if err != nil {
					return fmt.Errorf("SU assignment history #%d not found: %w", historyID, err)
				}
			} else {
				err := tx.QueryRowContext(ctx,
					`SELECT ID, Proposal FROM main.`+vprocore.QuoteHeaderIdentifier(suAssignmentHistoryTable)+
						` WHERE Proposal LIKE '%"kind":"su_plot_assignment"%' ORDER BY ID DESC LIMIT 1`,
				).Scan(&targetID, &proposal)
				if err != nil {
					return fmt.Errorf("no reversible SU plot assignment found: %w", err)
				}
			}

			var receipt suPlotAssignmentReceipt
			if err := json.Unmarshal([]byte(proposal), &receipt); err != nil || receipt.Kind != "su_plot_assignment" || receipt.SU != suName {
				return errors.New("selected history entry is not a reversible assignment for the active SU")
			}

			reverseDeltas := make([]suPlotAssignmentDelta, 0, len(receipt.Deltas))
			for i := len(receipt.Deltas) - 1; i >= 0; i-- {
				d := receipt.Deltas[i]
				if !d.ExistedBefore {
					if _, err := tx.ExecContext(ctx,
						`DELETE FROM main.`+qTable+` WHERE "PlotNumber" = ? AND typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB)`,
						d.PlotNumber, d.PlotNumber,
					); err != nil {
						return err
					}
				} else {
					var existingRowID int64
					rErr := tx.QueryRowContext(ctx,
						`SELECT rowid FROM main.`+qTable+` WHERE "PlotNumber" = ? AND typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB)`,
						d.PlotNumber, d.PlotNumber,
					).Scan(&existingRowID)
					if errors.Is(rErr, sql.ErrNoRows) {
						if _, err := tx.ExecContext(ctx, `INSERT INTO main.`+qTable+` ("PlotNumber","SiteUnit") VALUES (?,?)`, d.PlotNumber, d.BeforeSiteUnit); err != nil {
							return err
						}
					} else if rErr != nil {
						return rErr
					} else {
						if _, err := tx.ExecContext(ctx, `UPDATE main.`+qTable+` SET "SiteUnit" = ? WHERE rowid = ?`, d.BeforeSiteUnit, existingRowID); err != nil {
							return err
						}
					}
				}
				reverseDeltas = append(reverseDeltas, suPlotAssignmentDelta{
					PlotNumber:     d.PlotNumber,
					ExistedBefore:  d.ExistedAfter,
					BeforeSiteUnit: d.AfterSiteUnit,
					ExistedAfter:   d.ExistedBefore,
					AfterSiteUnit:  d.BeforeSiteUnit,
				})
				res.ChangedPlots++
			}

			undoReceipt, err := json.Marshal(struct {
				Kind     string                  `json:"kind"`
				UndoneID string                  `json:"undoneId"`
				SU       string                  `json:"su"`
				Deltas   []suPlotAssignmentDelta `json:"deltas"`
			}{"su_plot_assignment_undo", strconv.FormatInt(targetID, 10), suName, reverseDeltas})
			if err != nil {
				return err
			}
			if err := vprocore.AppendTechnicalProvenance(ctx, tx, suAssignmentHistoryTable, suAssignmentHistorySQL, string(undoReceipt), "SU assignment undo"); err != nil {
				return err
			}
			_ = tx.QueryRowContext(ctx, `SELECT MAX(ID) FROM main.`+vprocore.QuoteHeaderIdentifier(suAssignmentHistoryTable)).Scan(&res.HistoryID)
			return tx.Commit()
		})
		if err != nil {
			return nil, err
		}
		return res, nil
	})
}
