package classification

import (
	"context"
	"database/sql"
	"encoding/csv"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
	"unicode/utf16"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

const (
	userSiteUnitIdentityTable = "__VPRO_UserSiteUnitIdentity"
	userSiteUnitHistoryTable  = "__VPRO_UserSiteUnitHistory"
	userSiteUnitHistorySQL    = `CREATE TABLE "__VPRO_UserSiteUnitHistory"(ID INTEGER PRIMARY KEY,Created TEXT NOT NULL,Proposal TEXT NOT NULL)`
)

type UserSiteUnitEntry struct {
	ID                       int64  `json:"id"`
	SiteSeries               string `json:"siteSeries"`
	SiteSeriesLongName       string `json:"siteSeriesLongName"`
	SiteSeriesScientificName string `json:"siteSeriesScientificName"`
	Level                    int64  `json:"level"`
}

type UpsertUserSiteUnitRequest struct {
	ID                       *int64 `json:"id,omitempty"`
	SiteSeries               string `json:"siteSeries"`
	SiteSeriesLongName       string `json:"siteSeriesLongName"`
	SiteSeriesScientificName string `json:"siteSeriesScientificName"`
	Level                    *int64 `json:"level,omitempty"`
}

func (r *UpsertUserSiteUnitRequest) UnmarshalJSON(data []byte) error {
	type plain UpsertUserSiteUnitRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type DeleteUserSiteUnitRequest struct {
	ID int64 `json:"id"`
}

func (r *DeleteUserSiteUnitRequest) UnmarshalJSON(data []byte) error {
	type plain DeleteUserSiteUnitRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type UserSiteUnitImportResult struct {
	Inserted int                 `json:"inserted"`
	Updated  int                 `json:"updated"`
	Skipped  int                 `json:"skipped"`
	Total    int                 `json:"total"`
	Entries  []UserSiteUnitEntry `json:"entries"`
}

func validateUserSiteUnitWriter(c *vprocore.SqliteContext) error {
	if !c.IsOpen() {
		return errors.New("classification context is closed")
	}
	vuserPath := strings.TrimSpace(c.Attachments["VUser"])
	vuserInfo := c.AttachmentInfo["VUser"]
	if vuserPath == "" || vuserInfo == nil {
		return errors.New("personal UserSiteUnitList requires an attached VUser database")
	}
	curInfo, err := os.Stat(vuserPath)
	if err != nil {
		return fmt.Errorf("VUser database is unavailable: %w", err)
	}
	if !os.SameFile(vuserInfo, curInfo) {
		return errors.New("VUser database file identity changed; aborting write")
	}
	for _, protected := range []string{"VPro64", "VLists", "VMetaData", "VMessageBoard", "VPics"} {
		if info := c.AttachmentInfo[protected]; info != nil && os.SameFile(vuserInfo, info) {
			return fmt.Errorf("VUser aliases protected support database %s; writes are prohibited", protected)
		}
	}
	return nil
}

func requireUserSiteUnitSchema(ctx context.Context, tx *sql.Tx) error {
	var physical int
	if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM main.sqlite_master WHERE type='table' AND name COLLATE BINARY='UserSiteUnitList'`).Scan(&physical); err != nil {
		return err
	}
	if physical != 1 {
		return errors.New("VUser.UserSiteUnitList physical table is missing")
	}
	cols := map[string]bool{}
	rows, err := tx.QueryContext(ctx, `PRAGMA main.table_info("UserSiteUnitList")`)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var cid, notNull, pk int
		var name, decl string
		var dflt any
		if err := rows.Scan(&cid, &name, &decl, &notNull, &dflt, &pk); err == nil {
			cols[name] = true
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	for _, req := range []string{"ID", "SiteSeries", "SiteSeriesLongName", "SiteSeriesScientificName"} {
		if !cols[req] {
			return fmt.Errorf("VUser.UserSiteUnitList is missing required column %s", req)
		}
	}
	return nil
}

func validateUserSiteUnitText(name, value string, maxUTF16 int, required bool) (string, error) {
	if !utf8.ValidString(value) || strings.ContainsRune(value, 0) {
		return "", fmt.Errorf("%s must be valid UTF-8 text without NUL", name)
	}
	trimmed := strings.TrimSpace(value)
	if required && trimmed == "" {
		return "", fmt.Errorf("%s cannot be blank", name)
	}
	if len(utf16.Encode([]rune(trimmed))) > maxUTF16 {
		return "", fmt.Errorf("%s exceeds %d UTF-16 code units", name, maxUTF16)
	}
	return trimmed, nil
}

func userSiteUnitHasLevelColumn(ctx context.Context, tx *sql.Tx) bool {
	rows, err := tx.QueryContext(ctx, `PRAGMA main.table_info("UserSiteUnitList")`)
	if err != nil {
		return false
	}
	defer rows.Close()
	for rows.Next() {
		var cid, notNull, pk int
		var name, decl string
		var dflt any
		if err := rows.Scan(&cid, &name, &decl, &notNull, &dflt, &pk); err == nil && strings.EqualFold(name, "Level") {
			return true
		}
	}
	return false
}

func allocateUserSiteUnitID(ctx context.Context, tx *sql.Tx) (int64, error) {
	if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS main.`+vprocore.QuoteHeaderIdentifier(userSiteUnitIdentityTable)+` (
		"ID" INTEGER PRIMARY KEY
	)`); err != nil {
		return 0, err
	}
	if _, err := tx.ExecContext(ctx, `INSERT OR IGNORE INTO main.`+vprocore.QuoteHeaderIdentifier(userSiteUnitIdentityTable)+` ("ID")
		SELECT "ID" FROM main."UserSiteUnitList" WHERE "ID" > 0`); err != nil {
		return 0, err
	}
	var maxID int64
	if err := tx.QueryRowContext(ctx, `SELECT COALESCE(MAX("ID"), 0) FROM main.`+vprocore.QuoteHeaderIdentifier(userSiteUnitIdentityTable)).Scan(&maxID); err != nil {
		return 0, err
	}
	nextID := maxID + 1
	if _, err := tx.ExecContext(ctx, `INSERT INTO main.`+vprocore.QuoteHeaderIdentifier(userSiteUnitIdentityTable)+` ("ID") VALUES (?)`, nextID); err != nil {
		return 0, err
	}
	return nextID, nil
}

func readUserSiteUnitEntries(ctx context.Context, q interface {
	QueryContext(context.Context, string, ...any) (*sql.Rows, error)
}, alias string, includeLevel bool) ([]UserSiteUnitEntry, error) {
	levelExpr := "11"
	if includeLevel {
		levelExpr = `COALESCE("Level", 11)`
	}
	rows, err := q.QueryContext(ctx,
		`SELECT COALESCE("ID", 0),
		        COALESCE(CAST("SiteSeries" AS TEXT), ''),
		        COALESCE(CAST("SiteSeriesLongName" AS TEXT), ''),
		        COALESCE(CAST("SiteSeriesScientificName" AS TEXT), ''),
		        `+levelExpr+`
		 FROM `+vprocore.QuoteHeaderIdentifier(alias)+`."UserSiteUnitList"
		 ORDER BY "SiteSeries" COLLATE NOCASE ASC, "ID" ASC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []UserSiteUnitEntry{}
	for rows.Next() {
		var item UserSiteUnitEntry
		if err := rows.Scan(&item.ID, &item.SiteSeries, &item.SiteSeriesLongName, &item.SiteSeriesScientificName, &item.Level); err != nil {
			return nil, err
		}
		out = append(out, item)
	}
	return out, rows.Err()
}

// ListUserSiteUnitList returns all personal site unit entries stored in VUser.UserSiteUnitList.
func ListUserSiteUnitList(ctx context.Context, contexts *vprocore.ContextService, contextID string) ([]UserSiteUnitEntry, error) {
	if ctx == nil {
		return nil, errors.New("UserSiteUnitList query requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("classification context service is unavailable")
	}
	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (_ []UserSiteUnitEntry, resultErr error) {
		owner := plots.Projects.Sqlite
		unlock, err := owner.AcquireMutex(ctx)
		if err != nil {
			return nil, err
		}
		defer unlock()
		tx, err := owner.BeginReadSnapshot(ctx)
		if err != nil {
			return nil, err
		}
		defer func() {
			if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
				resultErr = errors.Join(resultErr, rb)
			}
		}()
		hasLevel := false
		if colRows, cErr := tx.QueryContext(ctx, `PRAGMA "VUser".table_info("UserSiteUnitList")`); cErr == nil {
			for colRows.Next() {
				var cid, notNull, pk int
				var name, decl string
				var dflt any
				if err := colRows.Scan(&cid, &name, &decl, &notNull, &dflt, &pk); err == nil && strings.EqualFold(name, "Level") {
					hasLevel = true
				}
			}
			_ = colRows.Close()
		}
		entries, err := readUserSiteUnitEntries(ctx, tx, "VUser", hasLevel)
		if err != nil {
			return nil, err
		}
		if err := tx.Commit(); err != nil {
			return nil, err
		}
		return entries, nil
	})
}

// SaveUserSiteUnitEntry atomically inserts or updates an entry in VUser.UserSiteUnitList.
func SaveUserSiteUnitEntry(ctx context.Context, contexts *vprocore.ContextService, contextID string, req UpsertUserSiteUnitRequest) (*UserSiteUnitEntry, error) {
	if ctx == nil {
		return nil, errors.New("UserSiteUnitList save requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("classification context service is unavailable")
	}
	siteSeries, err := validateUserSiteUnitText("SiteSeries", req.SiteSeries, 50, true)
	if err != nil {
		return nil, err
	}
	longName, err := validateUserSiteUnitText("SiteSeriesLongName", req.SiteSeriesLongName, 255, false)
	if err != nil {
		return nil, err
	}
	sciName, err := validateUserSiteUnitText("SiteSeriesScientificName", req.SiteSeriesScientificName, 255, false)
	if err != nil {
		return nil, err
	}
	level := int64(11)
	if req.Level != nil {
		if *req.Level < 1 || *req.Level > 11 {
			return nil, fmt.Errorf("UserSiteUnitList Level must be between 1 and 11, got %d", *req.Level)
		}
		level = *req.Level
	}

	var saved *UserSiteUnitEntry
	_, err = vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (struct{}, error) {
		owner := plots.Projects.Sqlite
		err := owner.WithSelectedFileWriter(ctx, "VUser", func() error {
			return validateUserSiteUnitWriter(owner)
		}, func(conn *sql.Conn) (txErr error) {
			tx, bErr := conn.BeginTx(ctx, nil)
			if bErr != nil {
				return bErr
			}
			defer func() {
				if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
					txErr = errors.Join(txErr, rb)
				}
			}()
			if err := requireUserSiteUnitSchema(ctx, tx); err != nil {
				return err
			}
			hasLevel := userSiteUnitHasLevelColumn(ctx, tx)
			var targetID int64
			if req.ID != nil && *req.ID > 0 {
				targetID = *req.ID
				var exists int
				if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM main."UserSiteUnitList" WHERE "ID" = ?`, targetID).Scan(&exists); err != nil {
					return err
				}
				if exists != 1 {
					return fmt.Errorf("UserSiteUnitList row %d does not exist", targetID)
				}
				var dup int
				if err := tx.QueryRowContext(ctx,
					`SELECT COUNT(*) FROM main."UserSiteUnitList" WHERE "SiteSeries" = ? COLLATE NOCASE AND "ID" <> ?`,
					siteSeries, targetID,
				).Scan(&dup); err != nil {
					return err
				}
				if dup > 0 {
					return fmt.Errorf("UserSiteUnitList already defines %q", siteSeries)
				}
				if hasLevel {
					if _, err := tx.ExecContext(ctx,
						`UPDATE main."UserSiteUnitList" SET "SiteSeries"=?, "SiteSeriesLongName"=?, "SiteSeriesScientificName"=?, "Level"=? WHERE "ID"=?`,
						siteSeries, nullStringIfEmpty(longName), nullStringIfEmpty(sciName), level, targetID,
					); err != nil {
						return err
					}
				} else {
					if _, err := tx.ExecContext(ctx,
						`UPDATE main."UserSiteUnitList" SET "SiteSeries"=?, "SiteSeriesLongName"=?, "SiteSeriesScientificName"=? WHERE "ID"=?`,
						siteSeries, nullStringIfEmpty(longName), nullStringIfEmpty(sciName), targetID,
					); err != nil {
						return err
					}
				}
			} else {
				var dup int
				if err := tx.QueryRowContext(ctx,
					`SELECT COUNT(*) FROM main."UserSiteUnitList" WHERE "SiteSeries" = ? COLLATE NOCASE`,
					siteSeries,
				).Scan(&dup); err != nil {
					return err
				}
				if dup > 0 {
					return fmt.Errorf("UserSiteUnitList already defines %q", siteSeries)
				}
				allocID, aErr := allocateUserSiteUnitID(ctx, tx)
				if aErr != nil {
					return aErr
				}
				targetID = allocID
				if hasLevel {
					if _, err := tx.ExecContext(ctx,
						`INSERT INTO main."UserSiteUnitList" ("ID","SiteSeries","SiteSeriesLongName","SiteSeriesScientificName","Level") VALUES (?,?,?,?,?)`,
						targetID, siteSeries, nullStringIfEmpty(longName), nullStringIfEmpty(sciName), level,
					); err != nil {
						return err
					}
				} else {
					if _, err := tx.ExecContext(ctx,
						`INSERT INTO main."UserSiteUnitList" ("ID","SiteSeries","SiteSeriesLongName","SiteSeriesScientificName") VALUES (?,?,?,?)`,
						targetID, siteSeries, nullStringIfEmpty(longName), nullStringIfEmpty(sciName),
					); err != nil {
						return err
					}
				}
			}
			proposal, err := json.Marshal(req)
			if err != nil {
				return err
			}
			if err := vprocore.AppendTechnicalProvenance(ctx, tx, userSiteUnitHistoryTable, userSiteUnitHistorySQL, string(proposal), "VUser.UserSiteUnitList save"); err != nil {
				return err
			}
			if err := validateUserSiteUnitWriter(owner); err != nil {
				return err
			}
			if err := tx.Commit(); err != nil {
				return err
			}
			saved = &UserSiteUnitEntry{
				ID:                       targetID,
				SiteSeries:               siteSeries,
				SiteSeriesLongName:       longName,
				SiteSeriesScientificName: sciName,
				Level:                    level,
			}
			return nil
		})
		return struct{}{}, err
	})
	if err != nil {
		return nil, err
	}
	return saved, nil
}

// DeleteUserSiteUnitEntry atomically deletes an entry from VUser.UserSiteUnitList while
// reserving its deleted ID against future reuse.
func DeleteUserSiteUnitEntry(ctx context.Context, contexts *vprocore.ContextService, contextID string, req DeleteUserSiteUnitRequest) error {
	if ctx == nil {
		return errors.New("UserSiteUnitList delete requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	if contexts == nil {
		return errors.New("classification context service is unavailable")
	}
	if req.ID <= 0 {
		return errors.New("UserSiteUnitList delete requires a positive row ID")
	}
	_, err := vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (struct{}, error) {
		owner := plots.Projects.Sqlite
		err := owner.WithSelectedFileWriter(ctx, "VUser", func() error {
			return validateUserSiteUnitWriter(owner)
		}, func(conn *sql.Conn) (txErr error) {
			tx, bErr := conn.BeginTx(ctx, nil)
			if bErr != nil {
				return bErr
			}
			defer func() {
				if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
					txErr = errors.Join(txErr, rb)
				}
			}()
			if err := requireUserSiteUnitSchema(ctx, tx); err != nil {
				return err
			}
			if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS main.`+vprocore.QuoteHeaderIdentifier(userSiteUnitIdentityTable)+` ("ID" INTEGER PRIMARY KEY)`); err != nil {
				return err
			}
			if _, err := tx.ExecContext(ctx, `INSERT OR IGNORE INTO main.`+vprocore.QuoteHeaderIdentifier(userSiteUnitIdentityTable)+` ("ID") SELECT "ID" FROM main."UserSiteUnitList" WHERE "ID" > 0`); err != nil {
				return err
			}
			if _, err := tx.ExecContext(ctx, `INSERT OR IGNORE INTO main.`+vprocore.QuoteHeaderIdentifier(userSiteUnitIdentityTable)+` ("ID") VALUES (?)`, req.ID); err != nil {
				return err
			}
			res, err := tx.ExecContext(ctx, `DELETE FROM main."UserSiteUnitList" WHERE "ID" = ?`, req.ID)
			if err != nil {
				return err
			}
			if n, _ := res.RowsAffected(); n != 1 {
				return fmt.Errorf("UserSiteUnitList row %d does not exist", req.ID)
			}
			proposal, err := json.Marshal(req)
			if err != nil {
				return err
			}
			if err := vprocore.AppendTechnicalProvenance(ctx, tx, userSiteUnitHistoryTable, userSiteUnitHistorySQL, string(proposal), "VUser.UserSiteUnitList delete"); err != nil {
				return err
			}
			if err := validateUserSiteUnitWriter(owner); err != nil {
				return err
			}
			return tx.Commit()
		})
		return struct{}{}, err
	})
	return err
}

// ExportUserSiteUnitListCSV serializes VUser.UserSiteUnitList as UTF-8 CSV.
func ExportUserSiteUnitListCSV(ctx context.Context, contexts *vprocore.ContextService, contextID string) (string, error) {
	entries, err := ListUserSiteUnitList(ctx, contexts, contextID)
	if err != nil {
		return "", err
	}
	var sb strings.Builder
	w := csv.NewWriter(&sb)
	if err := w.Write([]string{"ID", "SiteSeries", "SiteSeriesLongName", "SiteSeriesScientificName", "Level"}); err != nil {
		return "", err
	}
	for _, item := range entries {
		if err := w.Write([]string{
			strconv.FormatInt(item.ID, 10),
			item.SiteSeries,
			item.SiteSeriesLongName,
			item.SiteSeriesScientificName,
			strconv.FormatInt(item.Level, 10),
		}); err != nil {
			return "", err
		}
	}
	w.Flush()
	if err := w.Error(); err != nil {
		return "", err
	}
	return sb.String(), nil
}

// ImportUserSiteUnitListCSV parses CSV rows (requiring a SiteSeries column and optional
// SiteSeriesLongName, SiteSeriesScientificName, Level columns) and atomically upserts them
// into VUser.UserSiteUnitList.
func ImportUserSiteUnitListCSV(ctx context.Context, contexts *vprocore.ContextService, contextID, csvText string, overwriteExisting bool) (*UserSiteUnitImportResult, error) {
	if ctx == nil {
		return nil, errors.New("UserSiteUnitList import requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("classification context service is unavailable")
	}
	if !utf8.ValidString(csvText) || strings.ContainsRune(csvText, 0) {
		return nil, errors.New("UserSiteUnitList CSV must be valid UTF-8 without NUL")
	}
	r := csv.NewReader(strings.NewReader(strings.TrimPrefix(csvText, "\uFEFF")))
	r.FieldsPerRecord = -1
	header, err := r.Read()
	if err != nil {
		if errors.Is(err, io.EOF) {
			return nil, errors.New("UserSiteUnitList CSV is empty")
		}
		return nil, fmt.Errorf("UserSiteUnitList CSV header: %w", err)
	}
	colIdx := map[string]int{}
	for i, h := range header {
		key := strings.ToLower(strings.TrimSpace(h))
		if key != "" {
			colIdx[key] = i
		}
	}
	ssCol, hasSS := colIdx["siteseries"]
	if !hasSS {
		return nil, errors.New("UserSiteUnitList CSV must include a SiteSeries header column")
	}
	lnCol, hasLN := colIdx["siteserieslongname"]
	sciCol, hasSci := colIdx["siteseriesscientificname"]
	lvlCol, hasLvl := colIdx["level"]

	type parsedRow struct {
		siteSeries string
		longName   string
		sciName    string
		level      int64
	}
	var parsed []parsedRow
	seenCSV := map[string]bool{}
	lineNum := 1
	for {
		rec, rErr := r.Read()
		if errors.Is(rErr, io.EOF) {
			break
		}
		if rErr != nil {
			return nil, fmt.Errorf("UserSiteUnitList CSV row %d: %w", lineNum+1, rErr)
		}
		lineNum++
		cell := func(ok bool, idx int) string {
			if !ok || idx < 0 || idx >= len(rec) {
				return ""
			}
			return rec[idx]
		}
		ss, err := validateUserSiteUnitText("SiteSeries", cell(true, ssCol), 50, true)
		if err != nil {
			return nil, fmt.Errorf("CSV row %d: %w", lineNum, err)
		}
		key := strings.ToLower(ss)
		if seenCSV[key] {
			return nil, fmt.Errorf("CSV row %d: duplicate SiteSeries %q in import", lineNum, ss)
		}
		seenCSV[key] = true
		ln, err := validateUserSiteUnitText("SiteSeriesLongName", cell(hasLN, lnCol), 255, false)
		if err != nil {
			return nil, fmt.Errorf("CSV row %d: %w", lineNum, err)
		}
		sci, err := validateUserSiteUnitText("SiteSeriesScientificName", cell(hasSci, sciCol), 255, false)
		if err != nil {
			return nil, fmt.Errorf("CSV row %d: %w", lineNum, err)
		}
		lvl := int64(11)
		if rawLvl := strings.TrimSpace(cell(hasLvl, lvlCol)); rawLvl != "" {
			v, pErr := strconv.ParseInt(rawLvl, 10, 64)
			if pErr != nil || v < 1 || v > 11 {
				return nil, fmt.Errorf("CSV row %d: invalid Level %q (must be 1..11)", lineNum, rawLvl)
			}
			lvl = v
		}
		parsed = append(parsed, parsedRow{siteSeries: ss, longName: ln, sciName: sci, level: lvl})
	}
	if len(parsed) == 0 {
		return nil, errors.New("UserSiteUnitList CSV has no data rows")
	}

	var result *UserSiteUnitImportResult
	_, err = vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (struct{}, error) {
		owner := plots.Projects.Sqlite
		err := owner.WithSelectedFileWriter(ctx, "VUser", func() error {
			return validateUserSiteUnitWriter(owner)
		}, func(conn *sql.Conn) (txErr error) {
			tx, bErr := conn.BeginTx(ctx, nil)
			if bErr != nil {
				return bErr
			}
			defer func() {
				if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
					txErr = errors.Join(txErr, rb)
				}
			}()
			if err := requireUserSiteUnitSchema(ctx, tx); err != nil {
				return err
			}
			hasLevel := userSiteUnitHasLevelColumn(ctx, tx)
			existing, eErr := readUserSiteUnitEntries(ctx, tx, "main", hasLevel)
			if eErr != nil {
				return eErr
			}
			bySeries := make(map[string]UserSiteUnitEntry, len(existing))
			for _, item := range existing {
				bySeries[strings.ToLower(strings.TrimSpace(item.SiteSeries))] = item
			}
			res := &UserSiteUnitImportResult{}
			for _, row := range parsed {
				if cur, exists := bySeries[strings.ToLower(row.siteSeries)]; exists {
					if !overwriteExisting {
						res.Skipped++
						continue
					}
					if hasLevel {
						if _, err := tx.ExecContext(ctx,
							`UPDATE main."UserSiteUnitList" SET "SiteSeries"=?, "SiteSeriesLongName"=?, "SiteSeriesScientificName"=?, "Level"=? WHERE "ID"=?`,
							row.siteSeries, nullStringIfEmpty(row.longName), nullStringIfEmpty(row.sciName), row.level, cur.ID,
						); err != nil {
							return err
						}
					} else {
						if _, err := tx.ExecContext(ctx,
							`UPDATE main."UserSiteUnitList" SET "SiteSeries"=?, "SiteSeriesLongName"=?, "SiteSeriesScientificName"=? WHERE "ID"=?`,
							row.siteSeries, nullStringIfEmpty(row.longName), nullStringIfEmpty(row.sciName), cur.ID,
						); err != nil {
							return err
						}
					}
					res.Updated++
					continue
				}
				allocID, aErr := allocateUserSiteUnitID(ctx, tx)
				if aErr != nil {
					return aErr
				}
				if hasLevel {
					if _, err := tx.ExecContext(ctx,
						`INSERT INTO main."UserSiteUnitList" ("ID","SiteSeries","SiteSeriesLongName","SiteSeriesScientificName","Level") VALUES (?,?,?,?,?)`,
						allocID, row.siteSeries, nullStringIfEmpty(row.longName), nullStringIfEmpty(row.sciName), row.level,
					); err != nil {
						return err
					}
				} else {
					if _, err := tx.ExecContext(ctx,
						`INSERT INTO main."UserSiteUnitList" ("ID","SiteSeries","SiteSeriesLongName","SiteSeriesScientificName") VALUES (?,?,?,?)`,
						allocID, row.siteSeries, nullStringIfEmpty(row.longName), nullStringIfEmpty(row.sciName),
					); err != nil {
						return err
					}
				}
				res.Inserted++
			}
			proposal, err := json.Marshal(struct {
				OverwriteExisting bool `json:"overwriteExisting"`
				Rows              int  `json:"rows"`
				Inserted          int  `json:"inserted"`
				Updated           int  `json:"updated"`
				Skipped           int  `json:"skipped"`
			}{overwriteExisting, len(parsed), res.Inserted, res.Updated, res.Skipped})
			if err != nil {
				return err
			}
			if err := vprocore.AppendTechnicalProvenance(ctx, tx, userSiteUnitHistoryTable, userSiteUnitHistorySQL, string(proposal), "VUser.UserSiteUnitList import"); err != nil {
				return err
			}
			entries, eErr := readUserSiteUnitEntries(ctx, tx, "main", hasLevel)
			if eErr != nil {
				return eErr
			}
			if err := validateUserSiteUnitWriter(owner); err != nil {
				return err
			}
			if err := tx.Commit(); err != nil {
				return err
			}
			res.Entries = entries
			res.Total = len(entries)
			result = res
			return nil
		})
		return struct{}{}, err
	})
	if err != nil {
		return nil, err
	}
	return result, nil
}
