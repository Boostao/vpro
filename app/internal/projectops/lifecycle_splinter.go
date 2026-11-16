package projectops

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type ExportSplinterRequest struct {
	SplinterProject   string   `json:"splinterProject"`
	DestinationPath   string   `json:"destinationPath,omitempty"`
	UseActiveSU       bool     `json:"useActiveSu"`
	SiteUnits         []string `json:"siteUnits,omitempty"`
	PlotNumbers       []string `json:"plotNumbers,omitempty"`
	ActivateOnSuccess bool     `json:"activateOnSuccess"`
}

func (r *ExportSplinterRequest) UnmarshalJSON(data []byte) error {
	type plain ExportSplinterRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type ExportSplinterResult struct {
	SourceProject     string                 `json:"sourceProject"`
	SplinterProject   string                 `json:"splinterProject"`
	DestinationPath   string                 `json:"destinationPath"`
	DestinationSHA    string                 `json:"destinationSha256"`
	SourcePlotCount   int                    `json:"sourcePlotCount"`
	ExportedPlotCount int                    `json:"exportedPlotCount"`
	CreatedSUTable    bool                   `json:"createdSuTable"`
	Activated         bool                   `json:"activated"`
	State             *vprocore.ProjectState `json:"state,omitempty"`
}

// ExportSplinterProject extracts plots matching the active *_SU, explicit SiteUnits filter,
// and/or explicit PlotNumbers subset into a standalone VP08 <Splinter>.db carrying all matching
// _Env, _Admin, _Veg, _Humus, _Mineral, _Other, _Audit, matching _Metadata rows, and filtered <Splinter>_SU.
func ExportSplinterProject(s *vprocore.ContextService, ctx context.Context, contextID string, req ExportSplinterRequest) (_ ExportSplinterResult, resultErr error) {
	splinterName, err := ValidateProjectName(req.SplinterProject)
	if err != nil {
		return ExportSplinterResult{}, err
	}
	for _, p := range req.PlotNumbers {
		if p == "" || !utf8.ValidString(p) || strings.ContainsRune(p, 0) {
			return ExportSplinterResult{}, errors.New("explicit plot numbers must be non-empty valid UTF-8")
		}
	}
	for _, u := range req.SiteUnits {
		if !utf8.ValidString(u) || strings.ContainsRune(u, 0) {
			return ExportSplinterResult{}, errors.New("site unit filters must be valid UTF-8")
		}
	}

	snap, err := inspectContextSnapshot(ctx, s, contextID)
	if err != nil {
		return ExportSplinterResult{}, err
	}
	useSU := req.UseActiveSU || (len(req.PlotNumbers) == 0 && len(req.SiteUnits) == 0 && snap.SU != "None")
	if useSU && snap.SU == "None" {
		return ExportSplinterResult{}, errors.New("splinter export requires an active SU table, site unit filter, or explicit plot subset")
	}
	if !useSU && len(req.PlotNumbers) == 0 && len(req.SiteUnits) == 0 {
		return ExportSplinterResult{}, errors.New("splinter export requires an active SU table, site unit filter, or explicit plot subset")
	}

	resolvedDest, parentInfo, err := resolveNewProjectDestination(filepath.Join(snap.Root, "projects"), splinterName, req.DestinationPath, "Splinter project")
	if err != nil {
		return ExportSplinterResult{}, err
	}

	review, err := s.ReadNewProjectTemplates(ctx, contextID)
	if err != nil {
		return ExportSplinterResult{}, err
	}
	ddlPlan, err := vprocore.PlanNewProjectDDL(ctx, splinterName, review)
	if err != nil {
		return ExportSplinterResult{}, err
	}

	srcDB, err := sqlutil.OpenReadOnlyContext(ctx, snap.ProjectPath)
	if err != nil {
		return ExportSplinterResult{}, err
	}
	defer srcDB.Close()

	// Load SU map if active SU is available.
	suMap := map[string]*string{}
	hasSUSource := snap.SU != "None" && snap.SUPath != ""
	if hasSUSource {
		suDB := srcDB
		if !vprocore.SameDesktopPath(snap.SUPath, snap.ProjectPath) {
			extDB, oErr := sqlutil.OpenReadOnlyContext(ctx, snap.SUPath)
			if oErr != nil {
				return ExportSplinterResult{}, oErr
			}
			defer extDB.Close()
			suDB = extDB
		}
		suTbl := vprocore.QuoteHeaderIdentifier(snap.SU + "_SU")
		sRows, sErr := suDB.QueryContext(ctx, `SELECT CAST("PlotNumber" AS BLOB), typeof("PlotNumber"), CAST("SiteUnit" AS BLOB), typeof("SiteUnit") FROM `+suTbl)
		if sErr != nil {
			return ExportSplinterResult{}, sErr
		}
		for sRows.Next() {
			var pBytes, uBytes []byte
			var pType, uType string
			if err := sRows.Scan(&pBytes, &pType, &uBytes, &uType); err != nil {
				sRows.Close()
				return ExportSplinterResult{}, err
			}
			if pType != "text" {
				continue
			}
			pKey := string(pBytes)
			if uType == "text" {
				uStr := string(uBytes)
				suMap[pKey] = &uStr
			} else {
				suMap[pKey] = nil
			}
		}
		if err := errors.Join(sRows.Err(), sRows.Close()); err != nil {
			return ExportSplinterResult{}, err
		}
	}

	srcTx, err := srcDB.BeginTx(ctx, &sql.TxOptions{ReadOnly: true})
	if err != nil {
		return ExportSplinterResult{}, err
	}
	defer func() { _ = srcTx.Rollback() }()

	envTbl := vprocore.QuoteHeaderIdentifier(snap.Project + "_Env")
	adminTbl := vprocore.QuoteHeaderIdentifier(snap.Project + "_Admin")

	// Determine total source plot count and matching plot set using exact literal PlotNumber bytes.
	plotFilter := map[string]bool{}
	for _, p := range req.PlotNumbers {
		plotFilter[p] = true
	}
	unitFilter := map[string]bool{}
	for _, u := range req.SiteUnits {
		unitFilter[u] = true
	}

	pRows, err := srcTx.QueryContext(ctx, `SELECT CAST(e."PlotNumber" AS BLOB), typeof(e."PlotNumber"),
		COALESCE(CAST(e."ProjectID" AS TEXT), ''),
		COALESCE(CAST(a."UserSiteUnit" AS TEXT), ''),
		COALESCE(CAST(e."SiteSeries" AS TEXT), '')
		FROM `+envTbl+` e
		LEFT JOIN `+adminTbl+` a ON typeof(a."Plot")='text' AND CAST(a."Plot" AS BLOB)=CAST(e."PlotNumber" AS BLOB)
		ORDER BY e."PlotNumber"`)
	if err != nil {
		return ExportSplinterResult{}, err
	}
	totalSourcePlots := 0
	selectedPlots := map[string]bool{}
	var orderedSelectedPlots []string
	selectedProjectIDs := map[string]bool{}
	fallbackSUMap := map[string]*string{}

	for pRows.Next() {
		var pBytes []byte
		var pType, pid, userSU, siteSeries string
		if err := pRows.Scan(&pBytes, &pType, &pid, &userSU, &siteSeries); err != nil {
			pRows.Close()
			return ExportSplinterResult{}, err
		}
		if pType != "text" {
			continue
		}
		totalSourcePlots++
		plot := string(pBytes)

		if useSU {
			if _, inSU := suMap[plot]; !inSU {
				continue
			}
		}
		if len(plotFilter) > 0 && !plotFilter[plot] {
			continue
		}
		if len(unitFilter) > 0 {
			if hasSUSource {
				uPtr, inSU := suMap[plot]
				uVal := ""
				if uPtr != nil {
					uVal = *uPtr
				}
				if !inSU || !unitFilter[uVal] {
					continue
				}
			} else {
				candidateUnit := strings.TrimSpace(userSU)
				if candidateUnit == "" {
					candidateUnit = strings.TrimSpace(siteSeries)
				}
				if !unitFilter[candidateUnit] {
					continue
				}
				uCopy := candidateUnit
				fallbackSUMap[plot] = &uCopy
			}
		}

		if !selectedPlots[plot] {
			selectedPlots[plot] = true
			orderedSelectedPlots = append(orderedSelectedPlots, plot)
			if pid != "" {
				selectedProjectIDs[strings.ToLower(pid)] = true
			}
		}
	}
	if err := errors.Join(pRows.Err(), pRows.Close()); err != nil {
		return ExportSplinterResult{}, err
	}

	filterRowsByColumn := func(cols []string, allRows [][]rawSQLiteCell, colName string, allowed map[string]bool, caseInsensitive bool) [][]rawSQLiteCell {
		colIdx := -1
		for i, c := range cols {
			if strings.EqualFold(c, colName) {
				colIdx = i
				break
			}
		}
		if colIdx < 0 {
			return nil
		}
		var filtered [][]rawSQLiteCell
		for _, r := range allRows {
			cell := r[colIdx]
			if cell.storage != "text" {
				continue
			}
			key := string(cell.bytes)
			if caseInsensitive {
				key = strings.ToLower(key)
			}
			if allowed[key] {
				filtered = append(filtered, r)
			}
		}
		return filtered
	}

	type tableData struct {
		cols []string
		rows [][]rawSQLiteCell
	}
	extracted := map[string]tableData{}
	for _, spec := range []struct {
		suffix string
		keyCol string
	}{
		{"Env", "PlotNumber"},
		{"Admin", "Plot"},
		{"Veg", "PlotNumber"},
		{"Humus", "PlotNumber"},
		{"Mineral", "PlotNumber"},
		{"Other", "PlotNumber"},
		{"Audit", "PlotNumber"},
	} {
		cols, allRows, rErr := readExactTableRows(ctx, srcTx, vprocore.QuoteHeaderIdentifier(snap.Project+"_"+spec.suffix), "")
		if rErr != nil {
			return ExportSplinterResult{}, rErr
		}
		filteredRows := filterRowsByColumn(cols, allRows, spec.keyCol, selectedPlots, false)
		if spec.suffix == "Audit" {
			rewriteAuditProjectCells(cols, filteredRows, splinterName)
		}
		extracted[spec.suffix] = tableData{
			cols: cols,
			rows: filteredRows,
		}
	}

	metaCols, metaAllRows, err := readExactTableRows(ctx, srcTx, vprocore.QuoteHeaderIdentifier(snap.Project+"_Metadata"), "")
	if err != nil {
		return ExportSplinterResult{}, err
	}
	extracted["Metadata"] = tableData{
		cols: metaCols,
		rows: filterRowsByColumn(metaCols, metaAllRows, "ProjectID", selectedProjectIDs, true),
	}

	var sourceIdentityReservations []struct {
		suffix string
		id     int64
	}
	var hasSourceIdentity bool
	if err := srcTx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='__VPRO_ChildIdentity')`).Scan(&hasSourceIdentity); err != nil {
		return ExportSplinterResult{}, err
	}
	if hasSourceIdentity {
		idRows, qErr := srcTx.QueryContext(ctx, `SELECT ChildTable, ID FROM "__VPRO_ChildIdentity"`)
		if qErr != nil {
			return ExportSplinterResult{}, qErr
		}
		srcPrefix := strings.Trim(vprocore.QuoteHeaderIdentifier(snap.Project+"_"), `"`)
		for idRows.Next() {
			var childTbl string
			var reservedID int64
			if sErr := idRows.Scan(&childTbl, &reservedID); sErr != nil {
				_ = idRows.Close()
				return ExportSplinterResult{}, sErr
			}
			unquoted := strings.Trim(childTbl, `"`)
			if strings.HasPrefix(unquoted, srcPrefix) {
				sourceIdentityReservations = append(sourceIdentityReservations, struct {
					suffix string
					id     int64
				}{suffix: strings.TrimPrefix(unquoted, srcPrefix), id: reservedID})
			}
		}
		if err := errors.Join(idRows.Err(), idRows.Close()); err != nil {
			return ExportSplinterResult{}, err
		}
	}

	tmpFile, err := os.CreateTemp(filepath.Dir(resolvedDest), ".vpro-splinter-*.db")
	if err != nil {
		return ExportSplinterResult{}, err
	}
	tmpPath := tmpFile.Name()
	published := false
	defer func() {
		if !published {
			_ = sqlutil.RemoveSQLiteWithSidecars(tmpPath)
		}
	}()
	if err := tmpFile.Chmod(0600); err != nil {
		_ = tmpFile.Close()
		return ExportSplinterResult{}, err
	}
	if err := tmpFile.Close(); err != nil {
		return ExportSplinterResult{}, err
	}

	dstDB, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(tmpPath, "rw")+"&_journal_mode=DELETE&_synchronous=FULL&_txlock=immediate")
	if err != nil {
		return ExportSplinterResult{}, err
	}
	dstDB.SetMaxOpenConns(1)
	dstTx, err := sqlutil.BeginStagedTx(ctx, dstDB)
	if err != nil {
		_ = dstDB.Close()
		return ExportSplinterResult{}, err
	}

	createdSU := hasSUSource || len(fallbackSUMap) > 0
	writeErr := func() error {
		for _, tblPlan := range ddlPlan.Tables {
			for _, mapping := range tblPlan.Schema {
				if mapping.SQL != nil {
					if _, err := dstTx.ExecContext(ctx, *mapping.SQL); err != nil {
						return err
					}
				}
			}
		}
		if _, err := dstTx.ExecContext(ctx, `CREATE TABLE "_table_metadata" ("table_name" TEXT PRIMARY KEY, "description" TEXT)`); err != nil {
			return err
		}
		for _, suffix := range vprocore.CoreTables {
			if _, err := dstTx.ExecContext(ctx, `INSERT INTO "_table_metadata" ("table_name", "description") VALUES (?, 'VP08')`, splinterName+"_"+suffix); err != nil {
				return err
			}
		}
		if err := ensureChildIdentityTable(ctx, dstTx); err != nil {
			return err
		}
		for _, res := range sourceIdentityReservations {
			if err := reserveChildID(ctx, dstTx, splinterName+"_"+res.suffix, res.id); err != nil {
				return err
			}
		}

		for _, suffix := range []string{"Env", "Admin", "Veg", "Humus", "Mineral", "Other", "Audit", "Metadata"} {
			td := extracted[suffix]
			targetTbl := splinterName + "_" + suffix
			if err := insertExactTableRows(ctx, dstTx, targetTbl, td.cols, td.rows); err != nil {
				return fmt.Errorf("insert splinter %s: %w", targetTbl, err)
			}
			// Reserve copied positive child IDs so monotonic child ID allocation never collides.
			if suffix == "Veg" || suffix == "Humus" || suffix == "Mineral" || suffix == "Other" || suffix == "Metadata" {
				idIdx := -1
				for i, c := range td.cols {
					if c == "ID" {
						idIdx = i
						break
					}
				}
				if idIdx >= 0 {
					for _, r := range td.rows {
						if r[idIdx].storage == "integer" && r[idIdx].intVal > 0 {
							if err := reserveChildID(ctx, dstTx, targetTbl, r[idIdx].intVal); err != nil {
								return err
							}
						}
					}
				}
			}
		}

		if createdSU {
			suTableName := splinterName + "_SU"
			quotedSU := vprocore.QuoteHeaderIdentifier(suTableName)
			if _, err := dstTx.ExecContext(ctx, `CREATE TABLE `+quotedSU+` ("PlotNumber" VARCHAR, "SiteUnit" VARCHAR);
				CREATE UNIQUE INDEX `+vprocore.QuoteHeaderIdentifier("uidx_"+suTableName+"_PlotNumber")+` ON `+quotedSU+` ("PlotNumber");
				CREATE INDEX `+vprocore.QuoteHeaderIdentifier("idx_"+suTableName+"_SiteUnit")+` ON `+quotedSU+` ("SiteUnit");`); err != nil {
				return err
			}
			stmt, err := dstTx.PrepareContext(ctx, `INSERT INTO `+quotedSU+` ("PlotNumber", "SiteUnit") VALUES (?, ?)`)
			if err != nil {
				return err
			}
			defer stmt.Close()
			for _, plot := range orderedSelectedPlots {
				var unitVal any
				if hasSUSource {
					if uPtr := suMap[plot]; uPtr != nil {
						unitVal = *uPtr
					}
				} else if uPtr := fallbackSUMap[plot]; uPtr != nil {
					unitVal = *uPtr
				}
				if _, err := stmt.ExecContext(ctx, plot, unitVal); err != nil {
					return err
				}
			}
			if _, err := dstTx.ExecContext(ctx, `INSERT INTO "_table_metadata" ("table_name", "description") VALUES (?, 'VP04')`, suTableName); err != nil {
				return err
			}
		}
		return ctx.Err()
	}()
	if writeErr != nil {
		_ = dstTx.Rollback()
		_ = dstDB.Close()
		return ExportSplinterResult{}, writeErr
	}
	if err := sqlutil.CommitStagedTx(ctx, dstTx); err != nil {
		_ = dstDB.Close()
		return ExportSplinterResult{}, err
	}
	if err := dstDB.Close(); err != nil {
		return ExportSplinterResult{}, err
	}

	if err := verifyStagedVP08Project(ctx, tmpPath, splinterName); err != nil {
		return ExportSplinterResult{}, err
	}
	if err := publishStagedDatabase(tmpPath, resolvedDest, parentInfo); err != nil {
		return ExportSplinterResult{}, err
	}
	published = true
	_ = sqlutil.RemoveSQLiteWithSidecars(tmpPath)

	shaHex, err := computeFileSHA256(resolvedDest)
	if err != nil {
		return ExportSplinterResult{}, err
	}

	res := ExportSplinterResult{
		SourceProject:     snap.Project,
		SplinterProject:   splinterName,
		DestinationPath:   resolvedDest,
		DestinationSHA:    shaHex,
		SourcePlotCount:   totalSourcePlots,
		ExportedPlotCount: len(orderedSelectedPlots),
		CreatedSUTable:    createdSU,
	}
	if req.ActivateOnSuccess {
		nextSU := "None"
		nextSUPath := ""
		if createdSU {
			nextSU = splinterName
			nextSUPath = resolvedDest
		}
		state, swErr := s.SwitchContext(contextID, vprocore.ContextSelection{
			Project:     splinterName,
			ProjectPath: resolvedDest,
			SU:          nextSU,
			SUPath:      nextSUPath,
			Hierarchy:   "None",
		})
		if swErr != nil {
			return res, fmt.Errorf("splinter project exported to %s, but context switch failed: %w", resolvedDest, swErr)
		}
		res.Activated = true
		res.State = &state
	}
	return res, nil
}
