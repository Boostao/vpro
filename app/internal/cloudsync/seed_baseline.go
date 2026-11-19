package cloudsync

import (
	"context"
	"database/sql"
	"fmt"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/jackc/pgx/v5"
	"strings"
	"time"
)

// SeedBECMasterBaseline streams a VP08 SQLite project (e.g. 71,567-plot BECMaster_fixing.db)
// into becmaster.* via pgx.CopyFrom without OOM, seeding child_identity, hash-chained audit, and baseline snapshot.
func (m *Manager) SeedBECMasterBaseline(ctx context.Context, req SeedBaselineRequest) (SeedBaselineResult, error) {
	t0 := time.Now()
	resolvedPath, project, err := resolveProjectInSQLiteFile(ctx, req.SourceDBPath, req.SourceProject)
	if err != nil {
		return SeedBaselineResult{}, err
	}
	srcSHA, err := streamFileSHA256Hex(resolvedPath)
	if err != nil {
		return SeedBaselineResult{}, fmt.Errorf("hash source SQLite database: %w", err)
	}

	snapshotTag := strings.TrimSpace(req.SnapshotTag)
	if snapshotTag == "" {
		snapshotTag = "BECMaster_v13_Baseline"
	}

	sqliteDB, err := sqlutil.OpenReadOnlyContext(ctx, resolvedPath)
	if err != nil {
		return SeedBaselineResult{}, fmt.Errorf("open source SQLite database: %w", err)
	}
	defer sqliteDB.Close()

	conn, creds, err := m.OpenDedicatedConn(ctx, RoleModeCustodian)
	if err != nil {
		return SeedBaselineResult{}, err
	}
	defer conn.Close(ctx)

	tx, err := conn.Begin(ctx)
	if err != nil {
		return SeedBaselineResult{}, wrapRedactedError("begin BECMaster seed transaction", err, creds)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if req.ReplaceExisting {
		// Preserve becmaster.child_identity and child_identity_watermark so previously retired child IDs are never reused!
		if _, err := tx.Exec(ctx, `
			TRUNCATE TABLE
				becmaster.env,
				becmaster.admin,
				becmaster.veg,
				becmaster.humus,
				becmaster.mineral,
				becmaster.other,
				becmaster.metadata,
				becmaster.audit
			RESTART IDENTITY CASCADE
		`); err != nil {
			return SeedBaselineResult{}, wrapRedactedError("truncate existing becmaster baseline", err, creds)
		}
	}

	// 1. Stream <Project>_Env ("PlotNumber" byte-exact text identity)
	plotSet := make(map[string]struct{}, 72000)
	envCount, err := streamKeyedParentToPG(ctx, tx, sqliteDB, project+"_Env", "becmaster", "env", VP08EnvColumns, "PlotNumber", plotSet, nil)
	if err != nil {
		return SeedBaselineResult{}, wrapRedactedError("seed becmaster.env", err, creds)
	}

	// 2. Stream <Project>_Admin (filtered to valid plots in becmaster.env)
	seenAdmin := make(map[string]struct{}, len(plotSet))
	adminCount, err := streamKeyedParentToPG(ctx, tx, sqliteDB, project+"_Admin", "becmaster", "admin", VP08AdminColumns, "Plot", seenAdmin, plotSet)
	if err != nil {
		return SeedBaselineResult{}, wrapRedactedError("seed becmaster.admin", err, creds)
	}

	// 3. Stream child tables (<Project>_Veg, _Humus, _Mineral, _Other) row-by-row with zero full-table slice in RAM
	vegCount, err := streamChildTableToPG(ctx, tx, sqliteDB, project+"_Veg", "becmaster", "veg", VP08VegColumns, plotSet, nil)
	if err != nil {
		return SeedBaselineResult{}, wrapRedactedError("seed becmaster.veg", err, creds)
	}
	humusCount, err := streamChildTableToPG(ctx, tx, sqliteDB, project+"_Humus", "becmaster", "humus", VP08HumusColumns, plotSet, nil)
	if err != nil {
		return SeedBaselineResult{}, wrapRedactedError("seed becmaster.humus", err, creds)
	}
	mineralCount, err := streamChildTableToPG(ctx, tx, sqliteDB, project+"_Mineral", "becmaster", "mineral", VP08MineralColumns, plotSet, nil)
	if err != nil {
		return SeedBaselineResult{}, wrapRedactedError("seed becmaster.mineral", err, creds)
	}
	otherCount, err := streamChildTableToPG(ctx, tx, sqliteDB, project+"_Other", "becmaster", "other", VP08OtherColumns, plotSet, nil)
	if err != nil {
		return SeedBaselineResult{}, wrapRedactedError("seed becmaster.other", err, creds)
	}

	// 4. Populate becmaster.child_identity and O(1) child_identity_watermark server-side
	cmdTag, err := tx.Exec(ctx, `
		INSERT INTO becmaster.child_identity (child_table, id)
		SELECT 'veg', "ID" FROM becmaster.veg WHERE "ID" IS NOT NULL
		UNION ALL
		SELECT 'humus', "ID" FROM becmaster.humus WHERE "ID" IS NOT NULL
		UNION ALL
		SELECT 'mineral', "ID" FROM becmaster.mineral WHERE "ID" IS NOT NULL
		UNION ALL
		SELECT 'other', "ID" FROM becmaster.other WHERE "ID" IS NOT NULL
		ON CONFLICT (child_table, id) DO NOTHING
	`)
	if err != nil {
		return SeedBaselineResult{}, wrapRedactedError("seed becmaster.child_identity", err, creds)
	}
	childIdentityRows := cmdTag.RowsAffected()

	// Also merge any __VPRO_ChildIdentity retired reservations from the source SQLite database
	if err := copySQLiteRetiredChildIdentities(ctx, tx, sqliteDB, project); err != nil {
		return SeedBaselineResult{}, wrapRedactedError("seed retired child identities", err, creds)
	}

	for _, childTbl := range []string{"veg", "humus", "mineral", "other"} {
		if _, err := tx.Exec(ctx, `
			INSERT INTO becmaster.child_identity_watermark (child_table, max_id)
			VALUES ($1, COALESCE((SELECT GREATEST(MAX(id), 0) FROM becmaster.child_identity WHERE child_table = $1), 0))
			ON CONFLICT (child_table) DO UPDATE SET
				max_id = GREATEST(becmaster.child_identity_watermark.max_id, EXCLUDED.max_id)
		`, childTbl); err != nil {
			return SeedBaselineResult{}, wrapRedactedError("seed child_identity_watermark", err, creds)
		}
	}

	// 5. Stream <Project>_Metadata
	seenMeta := make(map[string]struct{}, 128)
	metaCount, err := streamKeyedParentToPG(ctx, tx, sqliteDB, project+"_Metadata", "becmaster", "metadata", VP08MetadataColumns, "ProjectID", seenMeta, nil)
	if err != nil {
		return SeedBaselineResult{}, wrapRedactedError("seed becmaster.metadata", err, creds)
	}

	// 6. Stream <Project>_Audit with SHA-256 tamper-evident hash chain
	tailHash := GenesisAuditHash
	_ = tx.QueryRow(ctx, `SELECT row_hash FROM becmaster.audit ORDER BY audit_seq DESC LIMIT 1`).Scan(&tailHash)
	var auditCount int64
	if !req.SkipAudit {
		auditCount, tailHash, err = streamMasterAuditToPG(ctx, tx, sqliteDB, project+"_Audit", tailHash)
		if err != nil {
			return SeedBaselineResult{}, wrapRedactedError("seed becmaster.audit", err, creds)
		}
	}

	// 7. Record baseline snapshot in becmaster.snapshots
	becVer, taxVer := readBundledStandardsVersions()
	_ = tx.QueryRow(ctx, `
		SELECT bec_version, taxonomy_version FROM standards.library_releases
		WHERE is_current = TRUE ORDER BY published_at DESC LIMIT 1
	`).Scan(&becVer, &taxVer)

	nowUTC := time.Now().UTC()
	var notesPtr *string
	if n := strings.TrimSpace(req.Notes); n != "" {
		notesPtr = &n
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO becmaster.snapshots (
			snapshot_tag, created_at, created_by, plot_count, veg_count,
			bec_version, taxonomy_version, manifest_sha256, notes
		) VALUES ($1, $2, current_user, $3, $4, $5, $6, $7, $8)
		ON CONFLICT (snapshot_tag) DO UPDATE SET
			created_at = EXCLUDED.created_at,
			created_by = EXCLUDED.created_by,
			plot_count = EXCLUDED.plot_count,
			veg_count = EXCLUDED.veg_count,
			bec_version = EXCLUDED.bec_version,
			taxonomy_version = EXCLUDED.taxonomy_version,
			manifest_sha256 = EXCLUDED.manifest_sha256,
			notes = EXCLUDED.notes
	`, snapshotTag, nowUTC, int(envCount), vegCount, becVer, taxVer, srcSHA, notesPtr); err != nil {
		return SeedBaselineResult{}, wrapRedactedError("record baseline snapshot", err, creds)
	}

	if err := tx.Commit(ctx); err != nil {
		return SeedBaselineResult{}, wrapRedactedError("commit BECMaster baseline", err, creds)
	}

	// Refresh planner statistics outside transaction for < 500ms merge previews & subset queries
	_, _ = conn.Exec(ctx, `ANALYZE becmaster.env, becmaster.admin, becmaster.veg, becmaster.humus, becmaster.mineral, becmaster.other`)

	return SeedBaselineResult{
		SourceProject:     project,
		SourceSHA256:      srcSHA,
		SnapshotTag:       snapshotTag,
		PlotCount:         int(envCount),
		AdminCount:        int(adminCount),
		VegCount:          vegCount,
		HumusCount:        humusCount,
		MineralCount:      mineralCount,
		OtherCount:        otherCount,
		MetadataCount:     int(metaCount),
		AuditCount:        auditCount,
		ChildIdentityRows: childIdentityRows,
		TailAuditHash:     tailHash,
		ElapsedMs:         time.Since(t0).Milliseconds(),
		SeededAt:          nowUTC.Format(time.RFC3339),
		TableCounts: map[string]int64{
			"env":      envCount,
			"admin":    adminCount,
			"veg":      vegCount,
			"humus":    humusCount,
			"mineral":  mineralCount,
			"other":    otherCount,
			"metadata": metaCount,
			"audit":    auditCount,
		},
	}, nil
}

// streamKeyedParentToPG streams Env, Admin, or Metadata rows into becmaster.<tbl> or staging.<tbl>.
// If submissionID != nil, prepends submission_id as column 0 for staging tables.
func streamKeyedParentToPG(
	ctx context.Context,
	tx pgx.Tx,
	sqliteDB *sql.DB,
	sqliteTable string,
	pgSchema string,
	pgTable string,
	cols []ColumnSpec,
	keyCol string,
	seenKeys map[string]struct{},
	allowedKeys map[string]struct{},
	submissionID ...string,
) (int64, error) {
	qKey := quotePGIdent(keyCol)
	// Enforce literal text key extraction via CAST(col AS BLOB) when typeof='text', falling back to CAST AS TEXT for Metadata if numeric
	whereClause := fmt.Sprintf("WHERE %s IS NOT NULL", qKey)
	if keyCol == "PlotNumber" || keyCol == "Plot" {
		whereClause = fmt.Sprintf("WHERE typeof(%s) = 'text'", qKey)
	}
	query := fmt.Sprintf("SELECT %s FROM %s %s", sqliteSelectColumnsCSV(cols), quotePGIdent(sqliteTable), whereClause)
	rows, err := sqliteDB.QueryContext(ctx, query)
	if err != nil {
		return 0, fmt.Errorf("query %s: %w", sqliteTable, err)
	}
	defer rows.Close()

	keyIdx := -1
	for i, c := range cols {
		if c.Name == keyCol {
			keyIdx = i
			break
		}
	}
	if keyIdx < 0 {
		return 0, fmt.Errorf("key column %s missing in %s spec", keyCol, pgTable)
	}

	hasSubID := len(submissionID) > 0 && submissionID[0] != ""
	copyCols := columnNames(cols)
	if hasSubID {
		copyCols = append([]string{"submission_id"}, copyCols...)
	}

	rawVals := make([]any, len(cols))
	scanDest := make([]any, len(cols))
	for i := range rawVals {
		scanDest[i] = &rawVals[i]
	}

	var streamErr error
	copied, copyErr := tx.CopyFrom(
		ctx,
		pgx.Identifier{pgSchema, pgTable},
		copyCols,
		pgx.CopyFromFunc(func() ([]any, error) {
			for {
				if err := ctx.Err(); err != nil {
					return nil, err
				}
				if !rows.Next() {
					return nil, rows.Err()
				}
				if err := rows.Scan(scanDest...); err != nil {
					return nil, err
				}
				keyVal, kErr := CanonicalizeSQLiteToPG(cols[keyIdx], rawVals[keyIdx])
				if kErr != nil || keyVal == nil {
					continue
				}
				keyStr, ok := keyVal.(string)
				if !ok || keyStr == "" {
					continue
				}
				if allowedKeys != nil {
					if _, exists := allowedKeys[keyStr]; !exists {
						continue
					}
				}
				if seenKeys != nil {
					if _, dup := seenKeys[keyStr]; dup {
						continue
					}
					seenKeys[keyStr] = struct{}{}
				}

				offset := 0
				out := make([]any, len(copyCols))
				if hasSubID {
					out[0] = submissionID[0]
					offset = 1
				}
				skipRow := false
				for i, col := range cols {
					conv, cErr := CanonicalizeSQLiteToPG(col, rawVals[i])
					if cErr != nil {
						streamErr = fmt.Errorf("%s.%s (key=%q): %w", sqliteTable, col.Name, keyStr, cErr)
						return nil, streamErr
					}
					out[offset+i] = conv
				}
				if skipRow {
					continue
				}
				return out, nil
			}
		}),
	)
	if streamErr != nil {
		return 0, streamErr
	}
	if copyErr != nil {
		return 0, copyErr
	}
	return copied, rows.Close()
}

// streamChildTableToPG streams Veg, Humus, Mineral, or Other ordered by PlotNumber so
// per-plot duplicate/NULL ID repair uses O(1) memory across 1.65M+ rows.
func streamChildTableToPG(
	ctx context.Context,
	tx pgx.Tx,
	sqliteDB *sql.DB,
	sqliteTable string,
	pgSchema string,
	pgTable string,
	cols []ColumnSpec,
	allowedPlots map[string]struct{},
	submissionID *string,
) (int64, error) {
	var maxExistingID sql.NullInt64
	_ = sqliteDB.QueryRowContext(ctx, fmt.Sprintf(`SELECT MAX("ID") FROM %s WHERE typeof("ID") = 'integer'`, quotePGIdent(sqliteTable))).Scan(&maxExistingID)
	nextSyntheticID := int64(100000000)
	if maxExistingID.Valid && maxExistingID.Int64 >= nextSyntheticID {
		nextSyntheticID = maxExistingID.Int64 + 1
	}

	query := fmt.Sprintf(`SELECT %s FROM %s WHERE typeof("PlotNumber") = 'text' ORDER BY CAST("PlotNumber" AS BLOB)`,
		sqliteSelectColumnsCSV(cols), quotePGIdent(sqliteTable))
	rows, err := sqliteDB.QueryContext(ctx, query)
	if err != nil {
		return 0, fmt.Errorf("query %s: %w", sqliteTable, err)
	}
	defer rows.Close()

	plotIdx, idIdx := -1, -1
	for i, c := range cols {
		if c.Name == "PlotNumber" {
			plotIdx = i
		} else if c.Name == "ID" {
			idIdx = i
		}
	}

	hasSubID := submissionID != nil && *submissionID != ""
	copyCols := columnNames(cols)
	if hasSubID {
		copyCols = append([]string{"submission_id"}, copyCols...)
	}

	rawVals := make([]any, len(cols))
	scanDest := make([]any, len(cols))
	for i := range rawVals {
		scanDest[i] = &rawVals[i]
	}

	seenIDsTableWide := map[int64]struct{}{}
	var streamErr error

	copied, copyErr := tx.CopyFrom(
		ctx,
		pgx.Identifier{pgSchema, pgTable},
		copyCols,
		pgx.CopyFromFunc(func() ([]any, error) {
			for {
				if err := ctx.Err(); err != nil {
					return nil, err
				}
				if !rows.Next() {
					return nil, rows.Err()
				}
				if err := rows.Scan(scanDest...); err != nil {
					return nil, err
				}
				pVal, pErr := CanonicalizeSQLiteToPG(cols[plotIdx], rawVals[plotIdx])
				if pErr != nil || pVal == nil {
					continue
				}
				plotStr, ok := pVal.(string)
				if !ok || plotStr == "" {
					continue
				}
				if allowedPlots != nil {
					if _, exists := allowedPlots[plotStr]; !exists {
						continue
					}
				}

				offset := 0
				out := make([]any, len(copyCols))
				if hasSubID {
					out[0] = *submissionID
					offset = 1
				}
				for i, col := range cols {
					conv, cErr := CanonicalizeSQLiteToPG(col, rawVals[i])
					if cErr != nil {
						streamErr = fmt.Errorf("%s.%s (plot=%q): %w", sqliteTable, col.Name, plotStr, cErr)
						return nil, streamErr
					}
					out[offset+i] = conv
				}

				var rowID int64
				if out[offset+idIdx] == nil {
					rowID = nextSyntheticID
					nextSyntheticID++
				} else {
					rowID = out[offset+idIdx].(int64)
					if _, dup := seenIDsTableWide[rowID]; dup {
						rowID = nextSyntheticID
						nextSyntheticID++
					}
				}
				for {
					if _, dup := seenIDsTableWide[rowID]; !dup {
						break
					}
					rowID = nextSyntheticID
					nextSyntheticID++
				}
				seenIDsTableWide[rowID] = struct{}{}
				out[offset+idIdx] = rowID
				return out, nil
			}
		}),
	)
	if streamErr != nil {
		return 0, streamErr
	}
	if copyErr != nil {
		return 0, copyErr
	}
	return copied, rows.Close()
}

func copySQLiteRetiredChildIdentities(ctx context.Context, tx pgx.Tx, sqliteDB *sql.DB, project string) error {
	var hasTable bool
	if err := sqliteDB.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='__VPRO_ChildIdentity')`).Scan(&hasTable); err != nil || !hasTable {
		return nil
	}

	// Select only retired/deleted IDs not already present in the live child tables, then bulk-stream via CopyFrom.
	type suffixSpec struct {
		suffix string
		pgName string
	}
	var pairs [][2]any
	for _, sp := range []suffixSpec{
		{"Veg", "veg"},
		{"Humus", "humus"},
		{"Mineral", "mineral"},
		{"Other", "other"},
	} {
		rawName := project + "_" + sp.suffix
		quotedName := quotePGIdent(rawName)
		q := fmt.Sprintf(`
			SELECT "ID" FROM "__VPRO_ChildIdentity"
			WHERE typeof("ID") = 'integer' AND ("ChildTable" = ? OR "ChildTable" = ?)
			EXCEPT
			SELECT "ID" FROM %s WHERE typeof("ID") = 'integer'
		`, quotedName)
		rows, err := sqliteDB.QueryContext(ctx, q, rawName, quotedName)
		if err != nil {
			continue
		}
		for rows.Next() {
			var id int64
			if rows.Scan(&id) == nil {
				pairs = append(pairs, [2]any{sp.pgName, id})
			}
		}
		rows.Close()
	}
	if len(pairs) == 0 {
		return nil
	}

	if _, err := tx.Exec(ctx, `CREATE TEMP TABLE IF NOT EXISTS _vpro_retired_ids (child_table TEXT NOT NULL, id BIGINT NOT NULL) ON COMMIT DROP`); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `TRUNCATE TABLE _vpro_retired_ids`); err != nil {
		return err
	}
	idx := 0
	if _, err := tx.CopyFrom(
		ctx,
		pgx.Identifier{"_vpro_retired_ids"},
		[]string{"child_table", "id"},
		pgx.CopyFromFunc(func() ([]any, error) {
			if idx >= len(pairs) {
				return nil, nil
			}
			p := pairs[idx]
			idx++
			return []any{p[0], p[1]}, nil
		}),
	); err != nil {
		return err
	}
	_, err := tx.Exec(ctx, `
		INSERT INTO becmaster.child_identity (child_table, id)
		SELECT child_table, id FROM _vpro_retired_ids
		ON CONFLICT (child_table, id) DO NOTHING
	`)
	return err
}

func streamMasterAuditToPG(ctx context.Context, tx pgx.Tx, sqliteDB *sql.DB, sqliteAuditTable, initialPrevHash string) (int64, string, error) {
	var hasAudit bool
	if err := sqliteDB.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name=?)`, sqliteAuditTable).Scan(&hasAudit); err != nil || !hasAudit {
		return 0, initialPrevHash, err
	}
	query := fmt.Sprintf("SELECT %s FROM %s ORDER BY rowid", sqliteSelectColumnsCSV(VP08AuditColumns), quotePGIdent(sqliteAuditTable))
	rows, err := sqliteDB.QueryContext(ctx, query)
	if err != nil {
		return 0, initialPrevHash, err
	}
	defer rows.Close()

	copyCols := append(columnNames(VP08AuditColumns), "merge_tx_id", "prev_hash", "row_hash")
	rawVals := make([]any, len(VP08AuditColumns))
	scanDest := make([]any, len(VP08AuditColumns))
	for i := range rawVals {
		scanDest[i] = &rawVals[i]
	}

	prevHash := initialPrevHash
	var streamErr error
	copied, copyErr := tx.CopyFrom(
		ctx,
		pgx.Identifier{"becmaster", "audit"},
		copyCols,
		pgx.CopyFromFunc(func() ([]any, error) {
			if err := ctx.Err(); err != nil {
				return nil, err
			}
			if !rows.Next() {
				return nil, rows.Err()
			}
			if err := rows.Scan(scanDest...); err != nil {
				return nil, err
			}
			vp08Vals := make([]any, len(VP08AuditColumns))
			for i, col := range VP08AuditColumns {
				conv, cErr := CanonicalizeSQLiteToPG(col, rawVals[i])
				if cErr != nil {
					// Tolerate historical malformed text in legacy 2008 Audit memos by sanitizing invalid UTF-8 only on baseline audit import
					if col.PGType == "TEXT" && !col.IsAccessBool {
						if s, ok := rawVals[i].(string); ok {
							conv = strings.ToValidUTF8(strings.ReplaceAll(s, "\x00", ""), "\uFFFD")
						} else if b, ok := rawVals[i].([]byte); ok {
							conv = strings.ToValidUTF8(strings.ReplaceAll(string(b), "\x00", ""), "\uFFFD")
						} else {
							streamErr = cErr
							return nil, streamErr
						}
					} else {
						streamErr = cErr
						return nil, streamErr
					}
				}
				vp08Vals[i] = conv
			}
			rowHash := ComputeAuditRowHash(prevHash, "", vp08Vals)
			out := make([]any, len(copyCols))
			copy(out, vp08Vals)
			out[len(VP08AuditColumns)] = nil // merge_tx_id
			out[len(VP08AuditColumns)+1] = prevHash
			out[len(VP08AuditColumns)+2] = rowHash
			prevHash = rowHash
			return out, nil
		}),
	)
	if streamErr != nil {
		return 0, prevHash, streamErr
	}
	if copyErr != nil {
		return 0, prevHash, copyErr
	}
	return copied, prevHash, rows.Close()
}
