package projectops

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type SaveProjectAsRequest struct {
	NewProjectName    string `json:"newProjectName"`
	DestinationPath   string `json:"destinationPath,omitempty"`
	ActivateOnSuccess bool   `json:"activateOnSuccess"`
}

func (r *SaveProjectAsRequest) UnmarshalJSON(data []byte) error {
	type plain SaveProjectAsRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type SaveProjectAsResult struct {
	SourceProject   string                 `json:"sourceProject"`
	NewProjectName  string                 `json:"newProjectName"`
	DestinationPath string                 `json:"destinationPath"`
	DestinationSHA  string                 `json:"destinationSha256"`
	CopiedTables    []string               `json:"copiedTables"`
	CompanionTables []string               `json:"companionTables"`
	Activated       bool                   `json:"activated"`
	State           *vprocore.ProjectState `json:"state,omitempty"`
}

// SaveProjectAs performs a lossless atomic copy of the active <Project>.db renaming
// <OldPrefix>_* tables, indexes, foreign keys, and _table_metadata to <NewPrefix>_*
// while preserving companion _SU, _Hierarchy, _Lump, _Profile tables and VP08 tags.
func SaveProjectAs(s *vprocore.ContextService, ctx context.Context, contextID string, req SaveProjectAsRequest) (_ SaveProjectAsResult, resultErr error) {
	newName, err := ValidateProjectName(req.NewProjectName)
	if err != nil {
		return SaveProjectAsResult{}, err
	}
	snap, err := inspectContextSnapshot(ctx, s, contextID)
	if err != nil {
		return SaveProjectAsResult{}, err
	}
	oldName := snap.Project
	resolvedDest, parentInfo, err := resolveNewProjectDestination(filepath.Join(snap.Root, "projects"), newName, req.DestinationPath, "Save project as")
	if err != nil {
		return SaveProjectAsResult{}, err
	}
	if vprocore.SameDesktopPath(resolvedDest, snap.ProjectPath) {
		return SaveProjectAsResult{}, errors.New("destination database path must differ from the active project database")
	}

	srcDB, err := sqlutil.OpenReadOnlyContext(ctx, snap.ProjectPath)
	if err != nil {
		return SaveProjectAsResult{}, err
	}
	defer srcDB.Close()
	srcTx, err := srcDB.BeginTx(ctx, &sql.TxOptions{ReadOnly: true})
	if err != nil {
		return SaveProjectAsResult{}, err
	}
	defer func() { _ = srcTx.Rollback() }()

	type tableCopySpec struct {
		suffix     string
		companion  bool
		oldTable   string
		newTable   string
		createSQL  string
		indexSQLs  []string
		columns    []string
		rows       [][]rawSQLiteCell
		metaTag    string
		hasMetaTag bool
	}

	existingTables := map[string]string{}
	masterRows, err := srcTx.QueryContext(ctx, `SELECT name, sql FROM sqlite_master WHERE type='table' AND sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY name`)
	if err != nil {
		return SaveProjectAsResult{}, err
	}
	for masterRows.Next() {
		var name, ddl string
		if err := masterRows.Scan(&name, &ddl); err != nil {
			masterRows.Close()
			return SaveProjectAsResult{}, err
		}
		existingTables[name] = ddl
	}
	if err := errors.Join(masterRows.Err(), masterRows.Close()); err != nil {
		return SaveProjectAsResult{}, err
	}

	metaTags := map[string]string{}
	if _, hasMeta := existingTables["_table_metadata"]; hasMeta {
		mRows, mErr := srcTx.QueryContext(ctx, `SELECT table_name, COALESCE(description, '') FROM "_table_metadata"`)
		if mErr != nil {
			return SaveProjectAsResult{}, mErr
		}
		for mRows.Next() {
			var tName, desc string
			if err := mRows.Scan(&tName, &desc); err != nil {
				mRows.Close()
				return SaveProjectAsResult{}, err
			}
			metaTags[tName] = desc
		}
		if err := errors.Join(mRows.Err(), mRows.Close()); err != nil {
			return SaveProjectAsResult{}, err
		}
	}

	// Order Env first so FK references from Admin/Veg/Humus/Mineral/Other/Audit resolve cleanly!
	orderedSuffixes := []struct {
		suffix    string
		companion bool
	}{
		{"Env", false},
		{"Admin", false},
		{"Veg", false},
		{"Humus", false},
		{"Mineral", false},
		{"Other", false},
		{"Audit", false},
		{"Metadata", false},
	}
	for _, comp := range companionProjectSuffixes {
		orderedSuffixes = append(orderedSuffixes, struct {
			suffix    string
			companion bool
		}{comp, true})
	}

	var specs []tableCopySpec
	var copiedTables, companionTables []string
	hasCompanionSU := false
	hasCompanionHierarchy := false

	for _, item := range orderedSuffixes {
		oldTbl := oldName + "_" + item.suffix
		ddl, present := existingTables[oldTbl]
		if !present {
			if !item.companion {
				return SaveProjectAsResult{}, fmt.Errorf("active project %s is missing core table %s", oldName, oldTbl)
			}
			continue
		}
		newTbl := newName + "_" + item.suffix
		rewrittenTableSQL := rewriteProjectObjectSQL(ddl, oldName, newName, oldTbl, newTbl)

		idxRows, idxErr := srcTx.QueryContext(ctx, `SELECT name, sql FROM sqlite_master WHERE type='index' AND tbl_name=? AND sql IS NOT NULL ORDER BY name`, oldTbl)
		if idxErr != nil {
			return SaveProjectAsResult{}, idxErr
		}
		var idxSQLs []string
		for idxRows.Next() {
			var idxName, idxSQL string
			if err := idxRows.Scan(&idxName, &idxSQL); err != nil {
				idxRows.Close()
				return SaveProjectAsResult{}, err
			}
			rewrittenIdx := rewriteProjectIndexSQL(idxSQL, idxName, oldName, newName, oldTbl, newTbl)
			idxSQLs = append(idxSQLs, rewrittenIdx)
		}
		if err := errors.Join(idxRows.Err(), idxRows.Close()); err != nil {
			return SaveProjectAsResult{}, err
		}

		cols, tableRows, readErr := readExactTableRows(ctx, srcTx, vprocore.QuoteHeaderIdentifier(oldTbl), "")
		if readErr != nil {
			return SaveProjectAsResult{}, readErr
		}
		if item.suffix == "Audit" {
			rewriteAuditProjectCells(cols, tableRows, newName)
		}
		tag, hasTag := metaTags[oldTbl]
		if !item.companion && (tag == "" || item.suffix == "Env") {
			tag = "VP08"
			hasTag = true
		}

		specs = append(specs, tableCopySpec{
			suffix:     item.suffix,
			companion:  item.companion,
			oldTable:   oldTbl,
			newTable:   newTbl,
			createSQL:  rewrittenTableSQL,
			indexSQLs:  idxSQLs,
			columns:    cols,
			rows:       tableRows,
			metaTag:    tag,
			hasMetaTag: hasTag,
		})
		copiedTables = append(copiedTables, newTbl)
		if item.companion {
			companionTables = append(companionTables, newTbl)
			if item.suffix == "SU" {
				hasCompanionSU = true
			} else if item.suffix == "Hierarchy" {
				hasCompanionHierarchy = true
			}
		}
	}

	// Capture __VPRO_ChildIdentity reservations if present.
	type childIdEntry struct {
		childTable string
		id         int64
	}
	var childIds []childIdEntry
	if _, ok := existingTables["__VPRO_ChildIdentity"]; ok {
		cRows, cErr := srcTx.QueryContext(ctx, `SELECT "ChildTable", "ID" FROM "__VPRO_ChildIdentity"`)
		if cErr != nil {
			return SaveProjectAsResult{}, cErr
		}
		for cRows.Next() {
			var ct string
			var cid int64
			if err := cRows.Scan(&ct, &cid); err != nil {
				cRows.Close()
				return SaveProjectAsResult{}, err
			}
			unquoted := strings.Trim(ct, `"`)
			if after, matched := strings.CutPrefix(unquoted, oldName+"_"); matched {
				ct = vprocore.QuoteHeaderIdentifier(newName + "_" + after)
			}
			childIds = append(childIds, childIdEntry{ct, cid})
		}
		if err := errors.Join(cRows.Err(), cRows.Close()); err != nil {
			return SaveProjectAsResult{}, err
		}
	}

	// Capture _vpro_su_policy for <Old>_SU if present.
	var suPolicyKind string
	if _, ok := existingTables["_vpro_su_policy"]; ok && hasCompanionSU {
		_ = srcTx.QueryRowContext(ctx, `SELECT kind FROM "_vpro_su_policy" WHERE table_name = ?`, oldName+"_SU").Scan(&suPolicyKind)
	}

	tmpFile, err := os.CreateTemp(filepath.Dir(resolvedDest), ".vpro-saveas-*.db")
	if err != nil {
		return SaveProjectAsResult{}, err
	}
	tmpPath := tmpFile.Name()
	published := false
	defer func() {
		if !published {
			_ = os.Remove(tmpPath)
		}
	}()
	if err := tmpFile.Chmod(0600); err != nil {
		_ = tmpFile.Close()
		return SaveProjectAsResult{}, err
	}
	if err := tmpFile.Close(); err != nil {
		return SaveProjectAsResult{}, err
	}

	dstDB, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(tmpPath, "rw")+"&_journal_mode=DELETE&_synchronous=FULL&_txlock=immediate")
	if err != nil {
		return SaveProjectAsResult{}, err
	}
	dstDB.SetMaxOpenConns(1)
	dstTx, err := dstDB.BeginTx(ctx, nil)
	if err != nil {
		_ = dstDB.Close()
		return SaveProjectAsResult{}, err
	}

	writeErr := func() error {
		// Temporarily defer FK enforcement during bulk row load, then verify foreign_key_check.
		for _, spec := range specs {
			if _, err := dstTx.ExecContext(ctx, spec.createSQL); err != nil {
				return fmt.Errorf("create table %s: %w", spec.newTable, err)
			}
			if err := insertExactTableRows(ctx, dstTx, spec.newTable, spec.columns, spec.rows); err != nil {
				return fmt.Errorf("copy rows into %s: %w", spec.newTable, err)
			}
			for _, idxSQL := range spec.indexSQLs {
				if _, err := dstTx.ExecContext(ctx, idxSQL); err != nil {
					return fmt.Errorf("create index on %s: %w", spec.newTable, err)
				}
			}
		}

		if _, err := dstTx.ExecContext(ctx, `CREATE TABLE "_table_metadata" ("table_name" TEXT PRIMARY KEY, "description" TEXT)`); err != nil {
			return err
		}
		for _, spec := range specs {
			if spec.hasMetaTag {
				if _, err := dstTx.ExecContext(ctx, `INSERT INTO "_table_metadata" ("table_name", "description") VALUES (?, ?)`, spec.newTable, spec.metaTag); err != nil {
					return err
				}
			}
		}
		if len(childIds) > 0 {
			if err := ensureChildIdentityTable(ctx, dstTx); err != nil {
				return err
			}
			for _, entry := range childIds {
				if _, err := dstTx.ExecContext(ctx, `INSERT INTO "__VPRO_ChildIdentity" ("ChildTable", "ID") VALUES (?, ?) ON CONFLICT DO NOTHING`, entry.childTable, entry.id); err != nil {
					return err
				}
			}
		}
		if suPolicyKind != "" {
			if _, err := dstTx.ExecContext(ctx, `CREATE TABLE "_vpro_su_policy" ("table_name" TEXT PRIMARY KEY, "kind" TEXT NOT NULL)`); err != nil {
				return err
			}
			if _, err := dstTx.ExecContext(ctx, `INSERT INTO "_vpro_su_policy" ("table_name", "kind") VALUES (?, ?)`, newName+"_SU", suPolicyKind); err != nil {
				return err
			}
		}
		return ctx.Err()
	}()
	if writeErr != nil {
		_ = dstTx.Rollback()
		_ = dstDB.Close()
		return SaveProjectAsResult{}, writeErr
	}
	if err := dstTx.Commit(); err != nil {
		_ = dstDB.Close()
		return SaveProjectAsResult{}, err
	}
	if err := dstDB.Close(); err != nil {
		return SaveProjectAsResult{}, err
	}

	if err := verifyStagedVP08Project(ctx, tmpPath, newName); err != nil {
		return SaveProjectAsResult{}, err
	}
	if err := publishStagedDatabase(tmpPath, resolvedDest, parentInfo); err != nil {
		return SaveProjectAsResult{}, err
	}
	published = true
	_ = os.Remove(tmpPath)

	shaHex, err := computeFileSHA256(resolvedDest)
	if err != nil {
		return SaveProjectAsResult{}, err
	}
	res := SaveProjectAsResult{
		SourceProject:   oldName,
		NewProjectName:  newName,
		DestinationPath: resolvedDest,
		DestinationSHA:  shaHex,
		CopiedTables:    copiedTables,
		CompanionTables: companionTables,
	}
	if req.ActivateOnSuccess {
		nextSU := "None"
		nextSUPath := ""
		if hasCompanionSU && snap.SU == oldName && vprocore.SameDesktopPath(snap.SUPath, snap.ProjectPath) {
			nextSU = newName
			nextSUPath = resolvedDest
		}
		nextHierarchy := "None"
		nextHierarchyPath := ""
		if hasCompanionHierarchy && snap.Hierarchy == oldName && (snap.HierarchyPath == "" || vprocore.SameDesktopPath(snap.HierarchyPath, snap.ProjectPath)) {
			nextHierarchy = newName
			nextHierarchyPath = resolvedDest
		}
		state, swErr := s.SwitchContext(contextID, vprocore.ContextSelection{
			Project:       newName,
			ProjectPath:   resolvedDest,
			SU:            nextSU,
			SUPath:        nextSUPath,
			Hierarchy:     nextHierarchy,
			HierarchyPath: nextHierarchyPath,
		})
		if swErr != nil {
			return res, fmt.Errorf("project saved as %s, but context switch failed: %w", resolvedDest, swErr)
		}
		res.Activated = true
		res.State = &state
	}
	return res, nil
}
