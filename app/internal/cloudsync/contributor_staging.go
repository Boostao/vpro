package cloudsync

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"os"
	"slices"
	"strings"
	"time"
)

func extractActiveProjectSubmissionArtifacts(
	ctx context.Context,
	s *vprocore.ContextService,
	contextID string,
	useActiveSU bool,
) (projName, projPath, projID, actor, activeSU, activeSUPath string, suScopePlots map[string]struct{}, plotCount, vegCount int, userManifest CloudUserSpeciesManifest, lumpRows []StagingLumpRow, suRows []StagingSURow, err error) {
	_, err = vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (struct{}, error) {
		owner := plots.Projects.Sqlite
		if lErr := sqlutil.AcquireMutexLease(ctx, &owner.Mu); lErr != nil {
			return struct{}{}, lErr
		}
		defer owner.Mu.Unlock()
		if owner.Conn == nil {
			return struct{}{}, errors.New("project context is closed")
		}
		projName = owner.Selection.Project
		projPath = owner.Selection.ProjectPath
		activeSU = owner.Selection.SU
		activeSUPath = owner.Selection.SUPath
		actor = strings.TrimSpace(plots.CurrentUser)
		if actor == "" {
			actor = "VProUser"
		}
		if useActiveSU && (activeSU == "" || activeSU == "None") {
			return struct{}{}, errors.New("useActiveSu is enabled, but no active Site Unit (*_SU) table is selected")
		}

		tx, bErr := owner.BeginReadSnapshot(ctx)
		if bErr != nil {
			return struct{}{}, bErr
		}
		defer func() { _ = tx.Rollback() }()

		if useActiveSU {
			suScopePlots = map[string]struct{}{}
			suFilterRows, sfErr := tx.QueryContext(ctx, fmt.Sprintf(`SELECT CAST("PlotNumber" AS BLOB) FROM "su".%s WHERE typeof("PlotNumber") = 'text'`, quotePGIdent(activeSU+"_SU")))
			if sfErr != nil {
				return struct{}{}, fmt.Errorf("read active SU %s: %w", activeSU, sfErr)
			}
			for suFilterRows.Next() {
				var raw []byte
				if suFilterRows.Scan(&raw) == nil && len(raw) > 0 {
					suScopePlots[string(raw)] = struct{}{}
				}
			}
			suFilterRows.Close()
			if len(suScopePlots) == 0 {
				return struct{}{}, fmt.Errorf("active Site Unit table %q contains 0 text-keyed plots", activeSU)
			}
		}

		// Count plots & veg rows (strictly honoring suScopePlots when useActiveSU is enabled!)
		referencedSpeciesUpper := map[string]struct{}{}
		eRows, eErr := tx.QueryContext(ctx, fmt.Sprintf(`SELECT CAST("PlotNumber" AS BLOB) FROM "project".%s WHERE typeof("PlotNumber") = 'text'`, quotePGIdent(projName+"_Env")))
		if eErr != nil {
			return struct{}{}, eErr
		}
		validEnvPlots := map[string]struct{}{}
		for eRows.Next() {
			var raw []byte
			if eRows.Scan(&raw) == nil {
				p := string(raw)
				if suScopePlots != nil {
					if _, ok := suScopePlots[p]; !ok {
						continue
					}
				}
				validEnvPlots[p] = struct{}{}
				plotCount++
			}
		}
		eRows.Close()

		vRows, vErr := tx.QueryContext(ctx, fmt.Sprintf(`SELECT CAST("PlotNumber" AS BLOB), COALESCE(CAST("Species" AS TEXT), '') FROM "project".%s WHERE typeof("PlotNumber") = 'text'`, quotePGIdent(projName+"_Veg")))
		if vErr == nil {
			for vRows.Next() {
				var raw []byte
				var spp string
				if vRows.Scan(&raw, &spp) == nil {
					p := string(raw)
					if _, ok := validEnvPlots[p]; !ok {
						continue
					}
					vegCount++
					if trimmedSpp := strings.TrimSpace(spp); trimmedSpp != "" {
						referencedSpeciesUpper[strings.ToUpper(trimmedSpp)] = struct{}{}
					}
				}
			}
			vRows.Close()
		}

		_ = tx.QueryRowContext(ctx, fmt.Sprintf(`SELECT COALESCE(CAST("ProjectID" AS TEXT), '') FROM "project".%s LIMIT 1`, quotePGIdent(projName+"_Metadata"))).Scan(&projID)
		if strings.TrimSpace(projID) == "" {
			_ = tx.QueryRowContext(ctx, fmt.Sprintf(`SELECT COALESCE(CAST("ProjectID" AS TEXT), '') FROM "project".%s WHERE "ProjectID" IS NOT NULL AND "ProjectID" <> '' LIMIT 1`, quotePGIdent(projName+"_Env"))).Scan(&projID)
		}

		// Extract personal species from VUser.USysUserSpp referenced by the scoped <Project>_Veg rows
		uRows, uErr := tx.QueryContext(ctx, `
			SELECT u."Code", u."ScientificName", u."LifeForm", u."EnglishName", u."Report", u."SppNumber", u."Codetype"
			FROM "VUser"."USysUserSpp" u
			ORDER BY u."Code" COLLATE NOCASE, u."Code"
		`)
		var species []CloudUserSpeciesRecord
		if uErr == nil {
			for uRows.Next() {
				var code string
				var sci, eng, ctype sql.NullString
				var lf, sppNum sql.NullInt64
				var rep sql.NullFloat64
				if sErr := uRows.Scan(&code, &sci, &lf, &eng, &rep, &sppNum, &ctype); sErr == nil {
					if _, used := referencedSpeciesUpper[strings.ToUpper(strings.TrimSpace(code))]; !used {
						continue
					}
					rec := CloudUserSpeciesRecord{Code: code}
					if sci.Valid {
						v := sci.String
						rec.ScientificName = &v
					}
					if lf.Valid {
						v := int(lf.Int64)
						rec.LifeForm = &v
					}
					if eng.Valid {
						v := eng.String
						rec.EnglishName = &v
					}
					if rep.Valid {
						v := rep.Float64
						rec.Report = &v
					}
					if sppNum.Valid {
						v := int(sppNum.Int64)
						rec.SppNumber = &v
					}
					if ctype.Valid {
						v := ctype.String
						rec.Codetype = &v
					}
					species = append(species, rec)
				}
			}
			uRows.Close()
		}
		if species == nil {
			species = []CloudUserSpeciesRecord{}
		}
		canonicalBytes, _ := json.Marshal(species)
		pSum := sha256.Sum256(canonicalBytes)
		userManifest = CloudUserSpeciesManifest{
			SchemaVersion: "vpro.userspecies.v1",
			ExportedAt:    time.Now().UTC().Format(time.RFC3339),
			SourceProject: projName,
			RowCount:      len(species),
			PayloadSHA256: hex.EncodeToString(pSum[:]),
			Species:       species,
		}

		// Extract <Project>_Lump rows if present
		lumpRows = []StagingLumpRow{}
		var hasLump bool
		_ = tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM "project".sqlite_master WHERE type='table' AND name=?)`, projName+"_Lump").Scan(&hasLump)
		if hasLump {
			lRows, lErr := tx.QueryContext(ctx, fmt.Sprintf(`SELECT COALESCE(CAST("LumpCode" AS TEXT),''), COALESCE(CAST("SppCode" AS TEXT),''), COALESCE("Use", 0) FROM "project".%s ORDER BY "LumpCode", "SppCode"`, quotePGIdent(projName+"_Lump")))
			if lErr == nil {
				for lRows.Next() {
					var lc, sc string
					var useInt int64
					if lRows.Scan(&lc, &sc, &useInt) == nil && lc != "" && sc != "" {
						lumpRows = append(lumpRows, StagingLumpRow{LumpCode: lc, SppCode: sc, Use: useInt != 0})
					}
				}
				lRows.Close()
			}
		}

		// Extract active *_SU or <Project>_SU rows if present
		suRows = []StagingSURow{}
		if activeSU != "" && activeSU != "None" {
			sRows, sErr := tx.QueryContext(ctx, fmt.Sprintf(`SELECT CAST("PlotNumber" AS TEXT), "SiteUnit" FROM "su".%s WHERE typeof("PlotNumber") = 'text' ORDER BY CAST("PlotNumber" AS BLOB)`, quotePGIdent(activeSU+"_SU")))
			if sErr == nil {
				for sRows.Next() {
					var p string
					var su sql.NullString
					if sRows.Scan(&p, &su) == nil {
						var ptr *string
						if su.Valid {
							v := su.String
							ptr = &v
						}
						suRows = append(suRows, StagingSURow{PlotNumber: p, SiteUnit: ptr})
					}
				}
				sRows.Close()
			}
		} else {
			var hasProjSU bool
			_ = tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM "project".sqlite_master WHERE type='table' AND name=?)`, projName+"_SU").Scan(&hasProjSU)
			if hasProjSU {
				sRows, sErr := tx.QueryContext(ctx, fmt.Sprintf(`SELECT CAST("PlotNumber" AS TEXT), "SiteUnit" FROM "project".%s WHERE typeof("PlotNumber") = 'text' ORDER BY CAST("PlotNumber" AS BLOB)`, quotePGIdent(projName+"_SU")))
				if sErr == nil {
					for sRows.Next() {
						var p string
						var su sql.NullString
						if sRows.Scan(&p, &su) == nil {
							var ptr *string
							if su.Valid {
								v := su.String
								ptr = &v
							}
							suRows = append(suRows, StagingSURow{PlotNumber: p, SiteUnit: ptr})
						}
					}
					sRows.Close()
				}
			}
		}
		return struct{}{}, ctx.Err()
	})
	return
}

// runLayer1ComplianceFallback executes critical compliance checks directly against SQLiteContext
// when no external Layer-2 ComplianceValidatorFunc is injected (such as direct internal/cloudsync tests).
func runLayer1ComplianceFallback(ctx context.Context, s *vprocore.ContextService, contextID string) (ComplianceGateResult, error) {
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (ComplianceGateResult, error) {
		owner := plots.Projects.Sqlite
		if err := sqlutil.AcquireMutexLease(ctx, &owner.Mu); err != nil {
			return ComplianceGateResult{}, err
		}
		defer owner.Mu.Unlock()
		tx, err := owner.BeginReadSnapshot(ctx)
		if err != nil {
			return ComplianceGateResult{}, err
		}
		defer func() { _ = tx.Rollback() }()

		proj := owner.Selection.Project
		var envAdminMismatch, orphans, boundsErrs, unlistedSpp int

		// 1. Env <-> Admin 1:1 completeness
		_ = tx.QueryRowContext(ctx, fmt.Sprintf(`
			SELECT (
				SELECT COUNT(*) FROM "project".%s e
				WHERE typeof(e."PlotNumber")='text' AND NOT EXISTS (
					SELECT 1 FROM "project".%s a WHERE typeof(a."Plot")='text' AND CAST(a."Plot" AS BLOB)=CAST(e."PlotNumber" AS BLOB)
				)
			) + (
				SELECT COUNT(*) FROM "project".%s a
				WHERE typeof(a."Plot")='text' AND NOT EXISTS (
					SELECT 1 FROM "project".%s e WHERE typeof(e."PlotNumber")='text' AND CAST(e."PlotNumber" AS BLOB)=CAST(a."Plot" AS BLOB)
				)
			)
		`, quotePGIdent(proj+"_Env"), quotePGIdent(proj+"_Admin"), quotePGIdent(proj+"_Admin"), quotePGIdent(proj+"_Env"))).Scan(&envAdminMismatch)

		// 2. Orphan child rows
		for _, suffix := range []string{"Veg", "Humus", "Mineral", "Other"} {
			var cnt int
			_ = tx.QueryRowContext(ctx, fmt.Sprintf(`
				SELECT COUNT(*) FROM "project".%s c
				WHERE typeof(c."PlotNumber")<>'text' OR NOT EXISTS (
					SELECT 1 FROM "project".%s e WHERE typeof(e."PlotNumber")='text' AND CAST(e."PlotNumber" AS BLOB)=CAST(c."PlotNumber" AS BLOB)
				)
			`, quotePGIdent(proj+"_"+suffix), quotePGIdent(proj+"_Env"))).Scan(&cnt)
			orphans += cnt
		}

		// 3. PlotNumber UTF-16 <= 7 & Veg Species UTF-16 <= 8 & float32 cover < 100
		pRows, pErr := tx.QueryContext(ctx, fmt.Sprintf(`SELECT CAST("PlotNumber" AS TEXT) FROM "project".%s WHERE typeof("PlotNumber")='text'`, quotePGIdent(proj+"_Env")))
		if pErr == nil {
			for pRows.Next() {
				var p string
				if pRows.Scan(&p) == nil && ValidateUTF16Bound("PlotNumber", p, 7) != nil {
					boundsErrs++
				}
			}
			pRows.Close()
		}

		vRows, vErr := tx.QueryContext(ctx, fmt.Sprintf(`SELECT COALESCE(CAST("Species" AS TEXT),''), "Cover1", "Cover2", "Cover3", "TotalA", "Cover4", "Cover5", "TotalB", "Cover6", "Cover7" FROM "project".%s`, quotePGIdent(proj+"_Veg")))
		if vErr == nil {
			for vRows.Next() {
				var spp string
				var c1, c2, c3, ta, c4, c5, tb, c6, c7 sql.NullFloat64
				if vRows.Scan(&spp, &c1, &c2, &c3, &ta, &c4, &c5, &tb, &c6, &c7) == nil {
					if ValidateUTF16Bound("Species", spp, 8) != nil {
						boundsErrs++
					}
					for _, cv := range []sql.NullFloat64{c1, c2, c3, ta, c4, c5, tb, c6, c7} {
						if cv.Valid {
							if _, ok := NarrowSingleCover(cv.Float64); !ok {
								boundsErrs++
							}
						}
					}
				}
			}
			vRows.Close()
		}

		// 4. Unlisted species check against VLists.USysAllSpecs + VUser.USysUserSpp
		_ = tx.QueryRowContext(ctx, fmt.Sprintf(`
			SELECT COUNT(*) FROM "project".%s v
			WHERE v."Species" IS NOT NULL AND v."Species" <> ''
			  AND NOT EXISTS (SELECT 1 FROM "VLists"."USysAllSpecs" s WHERE UPPER(s."Code") = UPPER(CAST(v."Species" AS TEXT)))
			  AND NOT EXISTS (SELECT 1 FROM "VUser"."USysUserSpp" u WHERE UPPER(u."Code") = UPPER(CAST(v."Species" AS TEXT)))
		`, quotePGIdent(proj+"_Veg"))).Scan(&unlistedSpp)

		blocking := envAdminMismatch + orphans + boundsErrs + unlistedSpp
		summary := map[string]int{
			"envAdminMismatches": envAdminMismatch,
			"orphanChildRows":    orphans,
			"boundsErrors":       boundsErrs,
			"unlistedSpecies":    unlistedSpp,
		}
		passed := blocking == 0
		repJSON, _ := json.Marshal(map[string]any{
			"project": proj,
			"passed":  passed,
			"summary": summary,
		})
		return ComplianceGateResult{
			Passed:        passed,
			BlockingCount: blocking,
			Summary:       summary,
			ReportJSON:    repJSON,
		}, nil
	})
}

func computeDBWithWALSHA256(path string) (string, error) {
	h := sha256.New()
	raw, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	_, _ = h.Write(raw)
	if wal, wErr := os.ReadFile(path + "-wal"); wErr == nil && len(wal) > 0 {
		_, _ = h.Write([]byte("|WAL|"))
		_, _ = h.Write(wal)
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// PreviewStagingSubmission runs mandatory compliance validation and packages UserSpeciesManifest for UI review.
func (m *Manager) PreviewStagingSubmission(
	ctx context.Context,
	s *vprocore.ContextService,
	contextID string,
	useActiveSU bool,
	validator ComplianceValidatorFunc,
) (StagingPreflightPreview, error) {
	if s == nil {
		return StagingPreflightPreview{}, errors.New("project context service is unavailable")
	}
	if validator == nil {
		validator = func(ctx context.Context, s *vprocore.ContextService, cid string, _ bool) (ComplianceGateResult, error) {
			return runLayer1ComplianceFallback(ctx, s, cid)
		}
	}
	comp, err := validator(ctx, s, contextID, useActiveSU)
	if err != nil {
		return StagingPreflightPreview{}, err
	}
	projName, projPath, projID, _, _, _, _, plotCount, vegCount, userManifest, lumpRows, suRows, err := extractActiveProjectSubmissionArtifacts(ctx, s, contextID, useActiveSU)
	if err != nil {
		return StagingPreflightPreview{}, err
	}
	dbSHA, err := computeDBWithWALSHA256(projPath)
	if err != nil {
		return StagingPreflightPreview{}, err
	}
	return StagingPreflightPreview{
		Project:             projName,
		ProjectID:           projID,
		PlotCount:           plotCount,
		VegRowCount:         vegCount,
		SourceDBSHA256:      dbSHA,
		CompliancePassed:    comp.Passed,
		BlockingErrorCount:  comp.BlockingCount,
		ComplianceSummary:   comp.Summary,
		ComplianceReport:    comp.ReportJSON,
		UserSpeciesManifest: userManifest,
		LumpRowCount:        len(lumpRows),
		SURowCount:          len(suRows),
	}, nil
}

// SubmitProjectToStaging enforces compliance validation, packages personal species from VUser.USysUserSpp,
// and streams all 8 VP08 tables into staging.* inside a single atomic PostgreSQL transaction.
func (m *Manager) SubmitProjectToStaging(
	ctx context.Context,
	s *vprocore.ContextService,
	contextID string,
	req SubmitStagingRequest,
	validator ComplianceValidatorFunc,
) (SubmitStagingResult, error) {
	if s == nil {
		return SubmitStagingResult{}, errors.New("project context service is unavailable")
	}
	if validator == nil {
		validator = func(ctx context.Context, s *vprocore.ContextService, cid string, _ bool) (ComplianceGateResult, error) {
			return runLayer1ComplianceFallback(ctx, s, cid)
		}
	}
	comp, err := validator(ctx, s, contextID, req.UseActiveSU)
	if err != nil {
		return SubmitStagingResult{}, err
	}

	creds, err := m.ResolveCredentials()
	if err != nil {
		return SubmitStagingResult{}, err
	}
	activeRole := creds.ActiveRoleMode
	if activeRole == "" {
		activeRole = RoleModeContributor
	}

	if !comp.Passed {
		if !(req.CustodianOverride && activeRole == RoleModeCustodian) {
			return SubmitStagingResult{}, fmt.Errorf(
				"staging upload blocked by pre-flight compliance gate (%d blocking violation(s)); fix errors in Compliance Validator before submitting",
				comp.BlockingCount,
			)
		}
	}

	projName, projPath, projID, actor, _, _, suScopePlots, prePlotCount, preVegCount, userManifest, lumpRows, suRows, err := extractActiveProjectSubmissionArtifacts(ctx, s, contextID, req.UseActiveSU)
	if err != nil {
		return SubmitStagingResult{}, err
	}
	if strings.EqualFold(projName, "Sample") {
		return SubmitStagingResult{}, errors.New("built-in Sample project cannot be submitted to provincial BECMaster staging")
	}
	if subBy := strings.TrimSpace(req.SubmittedBy); subBy != "" {
		actor = subBy
	}

	// Capture an atomic WAL-merged standalone SQLite snapshot so source_db_sha256 and streamed rows are 100% snapshot-consistent!
	snapPath, cleanSnap, err := createConsistentSQLiteSnapshot(ctx, projPath)
	if err != nil {
		return SubmitStagingResult{}, fmt.Errorf("snapshot project SQLite database for staging upload: %w", err)
	}
	defer cleanSnap()

	dbSHA, err := streamFileSHA256Hex(snapPath)
	if err != nil {
		return SubmitStagingResult{}, err
	}

	sqliteDB, err := sqlutil.OpenReadOnlyContext(ctx, snapPath)
	if err != nil {
		return SubmitStagingResult{}, fmt.Errorf("open project SQLite snapshot for staging upload: %w", err)
	}
	defer sqliteDB.Close()

	conn, _, err := m.OpenDedicatedConn(ctx, activeRole)
	if err != nil {
		return SubmitStagingResult{}, err
	}
	defer conn.Close(ctx)

	tx, err := conn.Begin(ctx)
	if err != nil {
		return SubmitStagingResult{}, wrapRedactedError("begin staging upload transaction", err, creds)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var currentDBRole string
	if err := tx.QueryRow(ctx, `SELECT current_user`).Scan(&currentDBRole); err != nil {
		return SubmitStagingResult{}, wrapRedactedError("read current PostgreSQL role", err, creds)
	}

	subID := uuid.NewString()
	nowUTC := time.Now().UTC()
	manifestJSON, _ := json.Marshal(userManifest)
	lumpJSON, _ := json.Marshal(lumpRows)
	suJSON, _ := json.Marshal(suRows)

	var notesPtr, baseSnapPtr, projIDPtr *string
	if n := strings.TrimSpace(req.SubmitterNotes); n != "" {
		notesPtr = &n
	}
	if b := strings.TrimSpace(req.BaseSnapshotTag); b != "" {
		baseSnapPtr = &b
	}
	if p := strings.TrimSpace(projID); p != "" {
		projIDPtr = &p
	}

	if _, err := tx.Exec(ctx, `
		INSERT INTO staging.submissions (
			submission_id, project_name, project_id, submitted_by, db_role, submitted_at,
			status, plot_count, veg_row_count, source_db_sha256, compliance_passed,
			compliance_report, user_species_manifest, lump_rows, su_rows,
			submitter_notes, base_snapshot_tag
		) VALUES (
			$1, $2, $3, $4, $5, $6,
			'pending', $7, $8, $9, $10,
			$11::jsonb, $12::jsonb, $13::jsonb, $14::jsonb,
			$15, $16
		)
	`, subID, projName, projIDPtr, actor, currentDBRole, nowUTC,
		prePlotCount, preVegCount, dbSHA, comp.Passed,
		string(comp.ReportJSON), string(manifestJSON), string(lumpJSON), string(suJSON),
		notesPtr, baseSnapPtr,
	); err != nil {
		return SubmitStagingResult{}, wrapRedactedError("insert staging.submissions header", err, creds)
	}

	plotSet := map[string]struct{}{}
	envCopied, err := streamKeyedParentToPG(ctx, tx, sqliteDB, projName+"_Env", "staging", "env", VP08EnvColumns, "PlotNumber", plotSet, suScopePlots, subID)
	if err != nil {
		return SubmitStagingResult{}, wrapRedactedError("stream staging.env", err, creds)
	}
	if envCopied == 0 {
		return SubmitStagingResult{}, errors.New("project contains 0 valid text-keyed plots to submit")
	}

	seenAdmin := map[string]struct{}{}
	if _, err := streamKeyedParentToPG(ctx, tx, sqliteDB, projName+"_Admin", "staging", "admin", VP08AdminColumns, "Plot", seenAdmin, plotSet, subID); err != nil {
		return SubmitStagingResult{}, wrapRedactedError("stream staging.admin", err, creds)
	}

	vegCopied, err := streamChildTableToPG(ctx, tx, sqliteDB, projName+"_Veg", "staging", "veg", VP08VegColumns, plotSet, &subID)
	if err != nil {
		return SubmitStagingResult{}, wrapRedactedError("stream staging.veg", err, creds)
	}
	if _, err := streamChildTableToPG(ctx, tx, sqliteDB, projName+"_Humus", "staging", "humus", VP08HumusColumns, plotSet, &subID); err != nil {
		return SubmitStagingResult{}, wrapRedactedError("stream staging.humus", err, creds)
	}
	if _, err := streamChildTableToPG(ctx, tx, sqliteDB, projName+"_Mineral", "staging", "mineral", VP08MineralColumns, plotSet, &subID); err != nil {
		return SubmitStagingResult{}, wrapRedactedError("stream staging.mineral", err, creds)
	}
	if _, err := streamChildTableToPG(ctx, tx, sqliteDB, projName+"_Other", "staging", "other", VP08OtherColumns, plotSet, &subID); err != nil {
		return SubmitStagingResult{}, wrapRedactedError("stream staging.other", err, creds)
	}

	seenMeta := map[string]struct{}{}
	if _, err := streamKeyedParentToPG(ctx, tx, sqliteDB, projName+"_Metadata", "staging", "metadata", VP08MetadataColumns, "ProjectID", seenMeta, nil, subID); err != nil {
		return SubmitStagingResult{}, wrapRedactedError("stream staging.metadata", err, creds)
	}

	if err := streamStagingAuditToPG(ctx, tx, sqliteDB, projName+"_Audit", subID, plotSet); err != nil {
		return SubmitStagingResult{}, wrapRedactedError("stream staging.audit", err, creds)
	}

	// Update plot_count and veg_row_count if custodian/table owner; for contributors without UPDATE privilege, inspect before insert!
	// Wait: contributors do NOT have UPDATE on staging.submissions! Let's check: we ALREADY know plotCount & vegCount before INSERT!
	// Wait — let's make sure the initial INSERT into staging.submissions ALREADY sets exact plotCount and vegCount!
	_ = slices.Compact([]string{}) // keep slices used if needed

	if err := tx.Commit(ctx); err != nil {
		return SubmitStagingResult{}, wrapRedactedError("commit staging upload", err, creds)
	}

	return SubmitStagingResult{
		SubmissionID:     subID,
		ProjectName:      projName,
		ProjectID:        projID,
		SubmittedBy:      actor,
		DBRole:           currentDBRole,
		Status:           "pending",
		PlotCount:        int(envCopied),
		VegRowCount:      int(vegCopied),
		UserSpeciesCount: userManifest.RowCount,
		SourceDBSHA256:   dbSHA,
		CompliancePassed: comp.Passed,
		SubmittedAt:      nowUTC.Format(time.RFC3339),
	}, nil
}

func streamStagingAuditToPG(ctx context.Context, tx pgx.Tx, sqliteDB *sql.DB, sqliteAuditTable, subID string, allowedPlots map[string]struct{}) error {
	var hasAudit bool
	if err := sqliteDB.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name=?)`, sqliteAuditTable).Scan(&hasAudit); err != nil || !hasAudit {
		return nil
	}
	query := fmt.Sprintf("SELECT %s FROM %s ORDER BY rowid", sqliteSelectColumnsCSV(VP08AuditColumns), quotePGIdent(sqliteAuditTable))
	rows, err := sqliteDB.QueryContext(ctx, query)
	if err != nil {
		return err
	}
	defer rows.Close()

	copyCols := append([]string{"submission_id"}, columnNames(VP08AuditColumns)...)
	rawVals := make([]any, len(VP08AuditColumns))
	scanDest := make([]any, len(VP08AuditColumns))
	for i := range rawVals {
		scanDest[i] = &rawVals[i]
	}

	_, copyErr := tx.CopyFrom(
		ctx,
		pgx.Identifier{"staging", "audit"},
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
				out := make([]any, len(copyCols))
				out[0] = subID
				for i, col := range VP08AuditColumns {
					conv, cErr := CanonicalizeSQLiteToPG(col, rawVals[i])
					if cErr != nil {
						return nil, cErr
					}
					out[1+i] = conv
				}
				if pStr, ok := out[3].(string); ok && pStr != "" && allowedPlots != nil {
					if _, exists := allowedPlots[pStr]; !exists {
						continue
					}
				}
				return out, nil
			}
		}),
	)
	if copyErr != nil {
		return copyErr
	}
	return rows.Close()
}
