package classification

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"os"
	"slices"
	"strings"
	"unicode/utf16"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type HierarchyAddNodeRequest struct {
	Name         string `json:"name"`
	ParentID     *int64 `json:"parentId"`
	Level        int64  `json:"level"`
	Tag          string `json:"tag,omitempty"`
	IsBreakpoint bool   `json:"isBreakpoint"`
}

func (r *HierarchyAddNodeRequest) UnmarshalJSON(data []byte) error {
	type plain HierarchyAddNodeRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type HierarchyRenameNodeRequest struct {
	NodeID  int64  `json:"nodeId"`
	NewName string `json:"newName"`
}

func (r *HierarchyRenameNodeRequest) UnmarshalJSON(data []byte) error {
	type plain HierarchyRenameNodeRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type HierarchyReparentNodeRequest struct {
	NodeID      int64  `json:"nodeId"`
	NewParentID *int64 `json:"newParentId"`
	NewLevel    *int64 `json:"newLevel,omitempty"`
}

func (r *HierarchyReparentNodeRequest) UnmarshalJSON(data []byte) error {
	type plain HierarchyReparentNodeRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type HierarchyDeleteNodeRequest struct {
	NodeID          int64 `json:"nodeId"`
	CascadeChildren bool  `json:"cascadeChildren"`
}

func (r *HierarchyDeleteNodeRequest) UnmarshalJSON(data []byte) error {
	type plain HierarchyDeleteNodeRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type HierarchyMutationResult struct {
	ContextID    string `json:"contextId"`
	Hierarchy    string `json:"hierarchy"`
	TableName    string `json:"tableName"`
	NodeID       int64  `json:"nodeId,omitempty"`
	NodeName     string `json:"nodeName,omitempty"`
	AffectedRows int    `json:"affectedRows"`
}

type SaveFlatHierarchyRequest struct {
	Rows []FlatHierarchyRow `json:"rows"`
}

func (r *SaveFlatHierarchyRequest) UnmarshalJSON(data []byte) error {
	type plain SaveFlatHierarchyRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

func allocateHierarchyNodeID(ctx context.Context, tx *sql.Tx, tableName string) (int64, error) {
	if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS main.`+vprocore.QuoteHeaderIdentifier(hierarchyIdentityTable)+` (
		"HierarchyTable" TEXT NOT NULL,
		"ID" INTEGER NOT NULL,
		PRIMARY KEY ("HierarchyTable", "ID")
	)`); err != nil {
		return 0, err
	}
	qTable := vprocore.QuoteHeaderIdentifier(tableName)
	var maxID int64
	if err := tx.QueryRowContext(ctx,
		`SELECT COALESCE(MAX(id_val), 0) FROM (
			SELECT "ID" AS id_val FROM main.`+qTable+` WHERE "ID" > 0
			UNION
			SELECT "ID" AS id_val FROM main.`+vprocore.QuoteHeaderIdentifier(hierarchyIdentityTable)+` WHERE "HierarchyTable" = ? AND "ID" > 0
		)`,
		tableName,
	).Scan(&maxID); err != nil {
		return 0, err
	}
	if maxID >= math.MaxInt32 {
		return 0, errors.New("hierarchy node ID space exhausted")
	}
	nextID := maxID + 1
	if _, err := tx.ExecContext(ctx,
		`INSERT INTO main.`+vprocore.QuoteHeaderIdentifier(hierarchyIdentityTable)+` ("HierarchyTable", "ID") VALUES (?, ?)`,
		tableName, nextID,
	); err != nil {
		return 0, err
	}
	return nextID, nil
}

func validateHierarchyNodeName(rawName string, isBreak bool) (string, error) {
	trimmed := strings.TrimSpace(rawName)
	if !utf8.ValidString(trimmed) || strings.ContainsRune(trimmed, 0) {
		return "", errors.New("hierarchy node name must be valid UTF-8 text without NUL")
	}
	clean, hasBreakPrefix := SplitBreakpointPrefix(trimmed)
	if clean == "" {
		return "", errors.New("hierarchy node name cannot be blank")
	}
	final := clean
	if isBreak || hasBreakPrefix {
		final = "~" + clean
	}
	if len(utf16.Encode([]rune(final))) > 255 {
		return "", errors.New("hierarchy node name exceeds 255 UTF-16 code units")
	}
	return final, nil
}

func withHierarchyWriter(
	ctx context.Context,
	contexts *vprocore.ContextService,
	contextID string,
	opName string,
	mutate func(owner *vprocore.SqliteContext, tx *sql.Tx, hierName, tableName string) (*HierarchyMutationResult, any, error),
) (*HierarchyMutationResult, error) {
	if ctx == nil {
		return nil, fmt.Errorf("%s requires a request context", opName)
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("classification context service is unavailable")
	}
	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*HierarchyMutationResult, error) {
		owner := plots.Projects.Sqlite
		if owner.Selection.Hierarchy == "" || owner.Selection.Hierarchy == "None" {
			return nil, errors.New("an active Hierarchy table must be selected")
		}
		hierName := owner.Selection.Hierarchy
		tableName := hierName + "_Hierarchy"

		validateFiles := func() error {
			if err := owner.ValidateMetadataWriterFiles(); err != nil {
				return err
			}
			hInfo := owner.AttachmentInfo["hierarchy"]
			if hInfo == nil {
				return errors.New("active Hierarchy file is not attached")
			}
			for role, info := range owner.AttachmentInfo {
				if strings.HasPrefix(role, "V") && os.SameFile(hInfo, info) {
					return fmt.Errorf("hierarchy database shares a file with support role %s; writes are prohibited", role)
				}
			}
			return nil
		}

		var out *HierarchyMutationResult
		err := owner.WithSelectedFileWriter(ctx, "hierarchy", validateFiles, func(conn *sql.Conn) (txErr error) {
			tx, bErr := conn.BeginTx(ctx, nil) // BEGIN IMMEDIATE
			if bErr != nil {
				return bErr
			}
			defer func() {
				if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
					txErr = errors.Join(txErr, rb)
				}
			}()

			beforeState, sErr := inspectHierarchyTableState(ctx, tx, tableName)
			if sErr != nil {
				return sErr
			}
			res, proposal, mErr := mutate(owner, tx, hierName, tableName)
			if mErr != nil {
				return mErr
			}
			afterState, aErr := inspectHierarchyTableState(ctx, tx, tableName)
			if aErr != nil {
				return aErr
			}
			if err := validateHierarchyMutationTransition(opName, res, beforeState, afterState); err != nil {
				return err
			}
			rawProp, jErr := json.Marshal(struct {
				Op       string `json:"op"`
				Proposal any    `json:"proposal"`
			}{opName, proposal})
			if jErr != nil {
				return jErr
			}
			if err := vprocore.AppendTechnicalProvenance(ctx, tx, hierarchyHistoryTable, hierarchyHistorySQL, string(rawProp), opName); err != nil {
				return err
			}
			if err := validateFiles(); err != nil {
				return err
			}
			if err := ctx.Err(); err != nil {
				return err
			}
			if err := tx.Commit(); err != nil {
				return err
			}
			res.ContextID = contextID
			res.Hierarchy = hierName
			res.TableName = tableName
			out = res
			return nil
		})
		if err != nil {
			return nil, err
		}
		return out, nil
	})
}

type hierarchyDuplicatePair struct {
	firstID  int64
	secondID int64
	rawName  string
}

type hierarchyTableState struct {
	records   []rawHierarchyRecord
	byID      map[int64]rawHierarchyRecord
	cycleIDs  []int64
	cycleSet  map[int64]bool
	orphanIDs []int64
	orphanSet map[int64]bool
	blankIDs  map[int64]bool
	dupPairs  map[[2]int64]bool
	dups      []hierarchyDuplicatePair
}

func inspectHierarchyTableState(ctx context.Context, tx *sql.Tx, tableName string) (*hierarchyTableState, error) {
	rows, err := tx.QueryContext(ctx,
		`SELECT "ID", COALESCE(CAST("Name" AS TEXT), ''), "Parent", COALESCE("Level", 11)
		 FROM main.`+vprocore.QuoteHeaderIdentifier(tableName)+` ORDER BY "ID" ASC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	state := &hierarchyTableState{
		byID:      map[int64]rawHierarchyRecord{},
		cycleSet:  map[int64]bool{},
		orphanSet: map[int64]bool{},
		blankIDs:  map[int64]bool{},
		dupPairs:  map[[2]int64]bool{},
	}
	idsByClean := map[string][]int64{}
	for rows.Next() {
		var r rawHierarchyRecord
		var parent sql.NullInt64
		if err := rows.Scan(&r.id, &r.name, &parent, &r.level); err != nil {
			return nil, err
		}
		if parent.Valid {
			p := parent.Int64
			r.parent = &p
		}
		state.byID[r.id] = r
		cleanName, _ := SplitBreakpointPrefix(r.name)
		lowerName := strings.ToLower(strings.TrimSpace(cleanName))
		if lowerName == "" {
			state.blankIDs[r.id] = true
		} else {
			for _, prevID := range idsByClean[lowerName] {
				pairKey := [2]int64{min(prevID, r.id), max(prevID, r.id)}
				state.dupPairs[pairKey] = true
				state.dups = append(state.dups, hierarchyDuplicatePair{
					firstID:  prevID,
					secondID: r.id,
					rawName:  r.name,
				})
			}
			idsByClean[lowerName] = append(idsByClean[lowerName], r.id)
		}
		state.records = append(state.records, r)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	cycles, orphans, _ := DetectHierarchyCyclesAndOrphans(state.records)
	state.cycleIDs = cycles
	for _, id := range cycles {
		state.cycleSet[id] = true
	}
	state.orphanIDs = orphans
	for _, id := range orphans {
		state.orphanSet[id] = true
	}
	return state, nil
}

func validateHierarchyMutationTransition(
	opName string,
	res *HierarchyMutationResult,
	before *hierarchyTableState,
	after *hierarchyTableState,
) error {
	if opName == "hierarchy_save_flat_rows" {
		if len(after.dups) > 0 {
			d := after.dups[0]
			return fmt.Errorf("duplicate hierarchy node name %q (nodes %d and %d)", d.rawName, d.firstID, d.secondID)
		}
		if len(after.blankIDs) > 0 {
			return errors.New("hierarchy cannot contain blank node names")
		}
		if len(after.orphanIDs) > 0 {
			return fmt.Errorf("hierarchy contains orphan parent reference on node(s) %v", after.orphanIDs)
		}
		if len(after.cycleIDs) > 0 {
			return fmt.Errorf("hierarchy mutation rejected: cycle detected involving node(s) %v", after.cycleIDs)
		}
		return nil
	}

	var targetID int64
	if res != nil {
		targetID = res.NodeID
	}
	isNameEdit := opName == "hierarchy_add_node" || opName == "hierarchy_rename_node" || opName == "hierarchy_toggle_breakpoint"

	for _, d := range after.dups {
		pairKey := [2]int64{min(d.firstID, d.secondID), max(d.firstID, d.secondID)}
		if !before.dupPairs[pairKey] || (isNameEdit && (d.firstID == targetID || d.secondID == targetID)) {
			return fmt.Errorf("duplicate hierarchy node name %q (nodes %d and %d)", d.rawName, d.firstID, d.secondID)
		}
	}

	for id := range after.blankIDs {
		if !before.blankIDs[id] || (isNameEdit && id == targetID) {
			return errors.New("hierarchy cannot contain blank node names")
		}
	}

	var offendingOrphans []int64
	for _, id := range after.orphanIDs {
		if !before.orphanSet[id] || (opName == "hierarchy_reparent_node" && id == targetID) {
			offendingOrphans = append(offendingOrphans, id)
		}
	}
	if len(offendingOrphans) > 0 {
		return fmt.Errorf("hierarchy contains orphan parent reference on node(s) %v", offendingOrphans)
	}

	var newCycles []int64
	for _, id := range after.cycleIDs {
		if !before.cycleSet[id] {
			newCycles = append(newCycles, id)
		}
	}
	if len(newCycles) > 0 {
		return fmt.Errorf("hierarchy mutation rejected: cycle detected involving node(s) %v", after.cycleIDs)
	}

	if opName == "hierarchy_reparent_node" {
		if after.cycleSet[targetID] {
			return fmt.Errorf("hierarchy mutation rejected: cycle detected involving node(s) %v", after.cycleIDs)
		}
		if rec, ok := after.byID[targetID]; ok {
			visited := map[int64]bool{targetID: true}
			curr := rec.parent
			for curr != nil {
				if visited[*curr] || after.cycleSet[*curr] {
					return fmt.Errorf("hierarchy mutation rejected: cycle detected involving node(s) %v", after.cycleIDs)
				}
				next, exists := after.byID[*curr]
				if !exists {
					break
				}
				visited[*curr] = true
				curr = next.parent
			}
		}
	}
	return nil
}

func resolveSafePromoteParent(ctx context.Context, tx *sql.Tx, tableName string, nodeID int64, parent sql.NullInt64) (*int64, error) {
	if !parent.Valid || parent.Int64 == nodeID {
		return nil, nil
	}
	state, err := inspectHierarchyTableState(ctx, tx, tableName)
	if err != nil {
		return nil, err
	}
	if _, exists := state.byID[parent.Int64]; !exists {
		return nil, nil
	}
	visited := map[int64]bool{nodeID: true}
	curr := &parent.Int64
	for curr != nil {
		if visited[*curr] || state.cycleSet[*curr] {
			return nil, nil
		}
		rec, ok := state.byID[*curr]
		if !ok {
			break
		}
		visited[*curr] = true
		curr = rec.parent
	}
	p := parent.Int64
	return &p, nil
}

func hierarchyTableHasTagColumn(ctx context.Context, tx *sql.Tx, tableName string) bool {
	cols, err := vprocore.ReadSQLiteStorageColumns(ctx, tx, "main", tableName)
	if err != nil {
		return false
	}
	for _, c := range cols {
		if strings.EqualFold(c.Name, "Tag") {
			return true
		}
	}
	return false
}

func AddHierarchyNode(ctx context.Context, contexts *vprocore.ContextService, contextID string, request HierarchyAddNodeRequest) (*HierarchyMutationResult, error) {
	finalName, err := validateHierarchyNodeName(request.Name, request.IsBreakpoint)
	if err != nil {
		return nil, err
	}
	lvl := request.Level
	if lvl == 0 {
		lvl = 11
	}
	if lvl < 1 || lvl > 11 {
		return nil, fmt.Errorf("hierarchy Level must be between 1 and 11, got %d", lvl)
	}

	return withHierarchyWriter(ctx, contexts, contextID, "hierarchy_add_node", func(_ *vprocore.SqliteContext, tx *sql.Tx, _, tableName string) (*HierarchyMutationResult, any, error) {
		qTable := vprocore.QuoteHeaderIdentifier(tableName)
		if request.ParentID != nil {
			var pExists bool
			if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM main.`+qTable+` WHERE "ID" = ?)`, *request.ParentID).Scan(&pExists); err != nil {
				return nil, nil, err
			}
			if !pExists {
				return nil, nil, fmt.Errorf("parent hierarchy node %d does not exist", *request.ParentID)
			}
		}
		newID, err := allocateHierarchyNodeID(ctx, tx, tableName)
		if err != nil {
			return nil, nil, err
		}
		if hierarchyTableHasTagColumn(ctx, tx, tableName) && strings.TrimSpace(request.Tag) != "" {
			if _, err := tx.ExecContext(ctx,
				`INSERT INTO main.`+qTable+` ("ID","Name","Parent","Level","Tag") VALUES (?,?,?,?,?)`,
				newID, finalName, request.ParentID, lvl, strings.TrimSpace(request.Tag),
			); err != nil {
				return nil, nil, err
			}
		} else {
			if _, err := tx.ExecContext(ctx,
				`INSERT INTO main.`+qTable+` ("ID","Name","Parent","Level") VALUES (?,?,?,?)`,
				newID, finalName, request.ParentID, lvl,
			); err != nil {
				return nil, nil, err
			}
		}
		return &HierarchyMutationResult{
			NodeID:       newID,
			NodeName:     finalName,
			AffectedRows: 1,
		}, request, nil
	})
}

func RenameHierarchyNode(ctx context.Context, contexts *vprocore.ContextService, contextID string, request HierarchyRenameNodeRequest) (*HierarchyMutationResult, error) {
	finalName, err := validateHierarchyNodeName(request.NewName, false)
	if err != nil {
		return nil, err
	}
	return withHierarchyWriter(ctx, contexts, contextID, "hierarchy_rename_node", func(_ *vprocore.SqliteContext, tx *sql.Tx, _, tableName string) (*HierarchyMutationResult, any, error) {
		qTable := vprocore.QuoteHeaderIdentifier(tableName)
		res, err := tx.ExecContext(ctx, `UPDATE main.`+qTable+` SET "Name" = ? WHERE "ID" = ?`, finalName, request.NodeID)
		if err != nil {
			return nil, nil, err
		}
		n, err := res.RowsAffected()
		if err != nil || n != 1 {
			return nil, nil, fmt.Errorf("hierarchy node %d does not exist", request.NodeID)
		}
		return &HierarchyMutationResult{
			NodeID:       request.NodeID,
			NodeName:     finalName,
			AffectedRows: 1,
		}, request, nil
	})
}

func ReparentHierarchyNode(ctx context.Context, contexts *vprocore.ContextService, contextID string, request HierarchyReparentNodeRequest) (*HierarchyMutationResult, error) {
	if request.NewParentID != nil && *request.NewParentID == request.NodeID {
		return nil, fmt.Errorf("hierarchy cycle detected: node %d cannot be its own parent", request.NodeID)
	}
	if request.NewLevel != nil && (*request.NewLevel < 1 || *request.NewLevel > 11) {
		return nil, fmt.Errorf("hierarchy Level must be between 1 and 11, got %d", *request.NewLevel)
	}

	return withHierarchyWriter(ctx, contexts, contextID, "hierarchy_reparent_node", func(_ *vprocore.SqliteContext, tx *sql.Tx, _, tableName string) (*HierarchyMutationResult, any, error) {
		qTable := vprocore.QuoteHeaderIdentifier(tableName)
		if request.NewParentID != nil {
			var pExists bool
			if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM main.`+qTable+` WHERE "ID" = ?)`, *request.NewParentID).Scan(&pExists); err != nil {
				return nil, nil, err
			}
			if !pExists {
				return nil, nil, fmt.Errorf("target parent node %d does not exist", *request.NewParentID)
			}
		}

		var res sql.Result
		var err error
		if request.NewLevel != nil {
			res, err = tx.ExecContext(ctx, `UPDATE main.`+qTable+` SET "Parent" = ?, "Level" = ? WHERE "ID" = ?`, request.NewParentID, *request.NewLevel, request.NodeID)
		} else {
			res, err = tx.ExecContext(ctx, `UPDATE main.`+qTable+` SET "Parent" = ? WHERE "ID" = ?`, request.NewParentID, request.NodeID)
		}
		if err != nil {
			return nil, nil, err
		}
		n, err := res.RowsAffected()
		if err != nil || n != 1 {
			return nil, nil, fmt.Errorf("hierarchy node %d does not exist", request.NodeID)
		}
		return &HierarchyMutationResult{
			NodeID:       request.NodeID,
			AffectedRows: 1,
		}, request, nil
	})
}

func ToggleHierarchyBreakpoint(ctx context.Context, contexts *vprocore.ContextService, contextID string, nodeID int64) (*HierarchyMutationResult, error) {
	return withHierarchyWriter(ctx, contexts, contextID, "hierarchy_toggle_breakpoint", func(_ *vprocore.SqliteContext, tx *sql.Tx, _, tableName string) (*HierarchyMutationResult, any, error) {
		qTable := vprocore.QuoteHeaderIdentifier(tableName)
		var currentName string
		if err := tx.QueryRowContext(ctx, `SELECT COALESCE(CAST("Name" AS TEXT), '') FROM main.`+qTable+` WHERE "ID" = ?`, nodeID).Scan(&currentName); err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return nil, nil, fmt.Errorf("hierarchy node %d does not exist", nodeID)
			}
			return nil, nil, err
		}
		clean, isBrk := SplitBreakpointPrefix(currentName)
		nextName, err := validateHierarchyNodeName(clean, !isBrk)
		if err != nil {
			return nil, nil, err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE main.`+qTable+` SET "Name" = ? WHERE "ID" = ?`, nextName, nodeID); err != nil {
			return nil, nil, err
		}
		return &HierarchyMutationResult{
			NodeID:       nodeID,
			NodeName:     nextName,
			AffectedRows: 1,
		}, map[string]any{"nodeId": nodeID, "before": currentName, "after": nextName}, nil
	})
}

func DeleteHierarchyNode(ctx context.Context, contexts *vprocore.ContextService, contextID string, request HierarchyDeleteNodeRequest) (*HierarchyMutationResult, error) {
	return withHierarchyWriter(ctx, contexts, contextID, "hierarchy_delete_node", func(_ *vprocore.SqliteContext, tx *sql.Tx, _, tableName string) (*HierarchyMutationResult, any, error) {
		qTable := vprocore.QuoteHeaderIdentifier(tableName)
		var parent sql.NullInt64
		if err := tx.QueryRowContext(ctx, `SELECT "Parent" FROM main.`+qTable+` WHERE "ID" = ?`, request.NodeID).Scan(&parent); err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return nil, nil, fmt.Errorf("hierarchy node %d does not exist", request.NodeID)
			}
			return nil, nil, err
		}

		// Reserve all existing positive IDs in __VPRO_HierarchyIdentity before deleting so deleted IDs are never reused!
		if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS main.`+vprocore.QuoteHeaderIdentifier(hierarchyIdentityTable)+` (
			"HierarchyTable" TEXT NOT NULL,
			"ID" INTEGER NOT NULL,
			PRIMARY KEY ("HierarchyTable", "ID")
		)`); err != nil {
			return nil, nil, err
		}
		if _, err := tx.ExecContext(ctx,
			`INSERT OR IGNORE INTO main.`+vprocore.QuoteHeaderIdentifier(hierarchyIdentityTable)+` ("HierarchyTable","ID")
			 SELECT ?, "ID" FROM main.`+qTable+` WHERE "ID" > 0`,
			tableName,
		); err != nil {
			return nil, nil, err
		}

		affected := 0
		if request.CascadeChildren {
			// Collect full descendant subtree iteratively
			toDelete := []int64{request.NodeID}
			seen := map[int64]bool{request.NodeID: true}
			for idx := 0; idx < len(toDelete); idx++ {
				curr := toDelete[idx]
				rows, err := tx.QueryContext(ctx, `SELECT "ID" FROM main.`+qTable+` WHERE "Parent" = ?`, curr)
				if err != nil {
					return nil, nil, err
				}
				for rows.Next() {
					var cid int64
					if err := rows.Scan(&cid); err != nil {
						rows.Close()
						return nil, nil, err
					}
					if !seen[cid] {
						seen[cid] = true
						toDelete = append(toDelete, cid)
					}
				}
				rows.Close()
			}
			for i := len(toDelete) - 1; i >= 0; i-- {
				res, err := tx.ExecContext(ctx, `DELETE FROM main.`+qTable+` WHERE "ID" = ?`, toDelete[i])
				if err != nil {
					return nil, nil, err
				}
				n, _ := res.RowsAffected()
				affected += int(n)
			}
		} else {
			parentPtr, pErr := resolveSafePromoteParent(ctx, tx, tableName, request.NodeID, parent)
			if pErr != nil {
				return nil, nil, pErr
			}
			if _, err := tx.ExecContext(ctx, `UPDATE main.`+qTable+` SET "Parent" = ? WHERE "Parent" = ?`, parentPtr, request.NodeID); err != nil {
				return nil, nil, err
			}
			res, err := tx.ExecContext(ctx, `DELETE FROM main.`+qTable+` WHERE "ID" = ?`, request.NodeID)
			if err != nil {
				return nil, nil, err
			}
			n, _ := res.RowsAffected()
			affected = int(n)
		}

		return &HierarchyMutationResult{
			NodeID:       request.NodeID,
			AffectedRows: affected,
		}, request, nil
	})
}

// SaveFlatHierarchyRows synchronizes edited wide phytosociological rank rows
// (Superclass | Class | Subclass | Order | SubOrder | Alliance | SubAlliance | Association | SubAssociation | Facies | WorkingUnit | SiteSeries)
// back into the <Name>_Hierarchy adjacency list inside an atomic BEGIN IMMEDIATE transaction.
func SaveFlatHierarchyRows(ctx context.Context, contexts *vprocore.ContextService, contextID string, request SaveFlatHierarchyRequest) (*HierarchyMutationResult, error) {
	return withHierarchyWriter(ctx, contexts, contextID, "hierarchy_save_flat_rows", func(_ *vprocore.SqliteContext, tx *sql.Tx, _, tableName string) (*HierarchyMutationResult, any, error) {
		qTable := vprocore.QuoteHeaderIdentifier(tableName)
		hasTag := hierarchyTableHasTagColumn(ctx, tx, tableName)

		// Preserve existing node IDs by clean/raw name for stability, and ensure deleted IDs stay reserved.
		if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS main.`+vprocore.QuoteHeaderIdentifier(hierarchyIdentityTable)+` (
			"HierarchyTable" TEXT NOT NULL,
			"ID" INTEGER NOT NULL,
			PRIMARY KEY ("HierarchyTable", "ID")
		)`); err != nil {
			return nil, nil, err
		}
		if _, err := tx.ExecContext(ctx,
			`INSERT OR IGNORE INTO main.`+vprocore.QuoteHeaderIdentifier(hierarchyIdentityTable)+` ("HierarchyTable","ID")
			 SELECT ?, "ID" FROM main.`+qTable+` WHERE "ID" > 0`,
			tableName,
		); err != nil {
			return nil, nil, err
		}

		tagExpr := `''`
		if hasTag {
			tagExpr = `COALESCE(CAST("Tag" AS TEXT), '')`
		}
		rows, err := tx.QueryContext(ctx,
			`SELECT "ID", COALESCE(CAST("Name" AS TEXT), ''), "Parent", COALESCE("Level", 11), `+tagExpr+
				` FROM main.`+qTable+` ORDER BY "ID"`)
		if err != nil {
			return nil, nil, err
		}
		var existingRecords []rawHierarchyRecord
		existingIDs := map[int64]bool{}
		for rows.Next() {
			var rec rawHierarchyRecord
			var parent sql.NullInt64
			if err := rows.Scan(&rec.id, &rec.name, &parent, &rec.level, &rec.tag); err != nil {
				rows.Close()
				return nil, nil, err
			}
			if parent.Valid {
				v := parent.Int64
				rec.parent = &v
			}
			existingRecords = append(existingRecords, rec)
			existingIDs[rec.id] = true
		}
		if err := errors.Join(rows.Err(), rows.Close()); err != nil {
			return nil, nil, err
		}

		finalNodes, preservedUnrepIDs, err := ensureFlatHierarchyRoundTrips(existingRecords, request.Rows, func() (int64, error) {
			return allocateHierarchyNodeID(ctx, tx, tableName)
		})
		if err != nil {
			return nil, nil, err
		}

		// Diffed synchronization inside tx: DELETE removed, UPDATE existing represented nodes
		// (preserving legacy MyOrder, ChildID, StartChild, LastChild, Flag, and non-working Tag),
		// keep untouched non-flat/inverted nodes verbatim, and INSERT added nodes.
		finalByID := make(map[int64]*flatPlannedNode, len(finalNodes))
		for _, n := range finalNodes {
			finalByID[n.id] = n
		}
		var removedIDs []int64
		for id := range existingIDs {
			if finalByID[id] == nil {
				removedIDs = append(removedIDs, id)
			}
		}
		slices.Sort(removedIDs)
		for _, id := range removedIDs {
			if _, err := tx.ExecContext(ctx, `DELETE FROM main.`+qTable+` WHERE "ID" = ?`, id); err != nil {
				return nil, nil, err
			}
		}
		for _, n := range finalNodes {
			if preservedUnrepIDs[n.id] {
				continue
			}
			if existingIDs[n.id] {
				if hasTag {
					if _, err := tx.ExecContext(ctx,
						`UPDATE main.`+qTable+` SET "Name" = ?, "Parent" = ?, "Level" = ?, "Tag" = ? WHERE "ID" = ?`,
						n.name, n.parent, n.level, nullStringIfEmpty(n.tag), n.id,
					); err != nil {
						return nil, nil, err
					}
				} else {
					if _, err := tx.ExecContext(ctx,
						`UPDATE main.`+qTable+` SET "Name" = ?, "Parent" = ?, "Level" = ? WHERE "ID" = ?`,
						n.name, n.parent, n.level, n.id,
					); err != nil {
						return nil, nil, err
					}
				}
				continue
			}
			if hasTag {
				if _, err := tx.ExecContext(ctx,
					`INSERT INTO main.`+qTable+` ("ID","Name","Parent","Level","Tag") VALUES (?,?,?,?,?)`,
					n.id, n.name, n.parent, n.level, nullStringIfEmpty(n.tag),
				); err != nil {
					return nil, nil, err
				}
			} else {
				if _, err := tx.ExecContext(ctx,
					`INSERT INTO main.`+qTable+` ("ID","Name","Parent","Level") VALUES (?,?,?,?)`,
					n.id, n.name, n.parent, n.level,
				); err != nil {
					return nil, nil, err
				}
			}
		}

		return &HierarchyMutationResult{
			AffectedRows: len(finalNodes),
		}, request, nil
	})
}

func nullStringIfEmpty(s string) any {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	return s
}

func sameInt64Ptr(a, b *int64) bool {
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	return *a == *b
}

func copyInt64Ptr(p *int64) *int64 {
	if p == nil {
		return nil
	}
	v := *p
	return &v
}

type flatPlannedNode struct {
	id     int64
	name   string
	parent *int64
	level  int64
	tag    string
}

// planFlatHierarchyNodes turns flat rank rows into the desired node set, keyed
// by lower-case clean name, reusing existing IDs and allocating new ones.
func planFlatHierarchyNodes(rows []FlatHierarchyRow, existingIDByClean map[string]int64, allocate func() (int64, error)) (map[string]*flatPlannedNode, []string, error) {
	desiredByClean := map[string]*flatPlannedNode{}
	desiredOrder := []string{}
	for rowIdx, flat := range rows {
		steps := []struct {
			raw   string
			level int64
			tag   string
		}{
			{flat.Superclass, 1, ""},
			{flat.Class, 2, ""},
			{flat.Subclass, 3, ""},
			{flat.Order, 4, ""},
			{flat.SubOrder, 5, ""},
			{flat.Alliance, 6, ""},
			{flat.SubAlliance, 7, ""},
			{flat.Association, 8, ""},
			{flat.SubAssociation, 9, ""},
			{flat.Facies, 10, ""},
			{flat.WorkingUnit, 10, "working"},
			{flat.SiteSeries, 11, ""},
		}
		var parentID *int64
		for _, step := range steps {
			if strings.TrimSpace(step.raw) == "" {
				continue
			}
			validatedName, vErr := validateHierarchyNodeName(step.raw, false)
			if vErr != nil {
				return nil, nil, fmt.Errorf("flat row %d: %w", rowIdx+1, vErr)
			}
			clean, _ := SplitBreakpointPrefix(validatedName)
			key := strings.ToLower(clean)
			if existing := desiredByClean[key]; existing != nil {
				if !sameInt64Ptr(existing.parent, parentID) {
					return nil, nil, fmt.Errorf("flat row %d places node %q under conflicting parents in the same hierarchy", rowIdx+1, clean)
				}
				if existing.level != step.level || existing.tag != step.tag {
					return nil, nil, fmt.Errorf("flat row %d places node %q at conflicting ranks in the same hierarchy", rowIdx+1, clean)
				}
				if strings.HasPrefix(validatedName, "~") {
					existing.name = validatedName
				}
				idCopy := existing.id
				parentID = &idCopy
				continue
			}
			id, ok := existingIDByClean[key]
			if !ok {
				allocated, aErr := allocate()
				if aErr != nil {
					return nil, nil, aErr
				}
				id = allocated
			}
			desiredByClean[key] = &flatPlannedNode{id: id, name: validatedName, parent: copyInt64Ptr(parentID), level: step.level, tag: step.tag}
			desiredOrder = append(desiredOrder, key)
			idCopy := id
			parentID = &idCopy
		}
	}
	return desiredByClean, desiredOrder, nil
}

// ensureFlatHierarchyRoundTrips reconciles requested flat rows with the stored
// hierarchy: existing non-flat/inverted subtrees (such as a legacy Level-1 node
// nested below Level-5 in Sample_Hierarchy) are preserved intact whenever their
// surrounding parent-child paths remain intact, while genuinely lossy edits
// (clean-name twins, broken links/cycles, or edits that would detach, bypass,
// or delete non-flat nodes) are refused without mutating the database.
func ensureFlatHierarchyRoundTrips(
	existingRecords []rawHierarchyRecord,
	rows []FlatHierarchyRow,
	allocate func() (int64, error),
) ([]*flatPlannedNode, map[int64]bool, error) {
	cycles, orphans, blanks := DetectHierarchyCyclesAndOrphans(existingRecords)
	if blanks > 0 || len(orphans) > 0 || len(cycles) > 0 {
		return nil, nil, errors.New("this hierarchy cannot be edited in the Flat Rank Table because it contains blank names, orphan links, or cycles; use the Hierarchy Tree view")
	}

	existingByID := make(map[int64]rawHierarchyRecord, len(existingRecords))
	existingIDByClean := make(map[string]int64, len(existingRecords))
	childrenCount := make(map[int64]int, len(existingRecords))
	minExistingID := int64(math.MinInt32)
	for _, rec := range existingRecords {
		existingByID[rec.id] = rec
		if rec.id < minExistingID {
			minExistingID = rec.id
		}
		if rec.parent != nil {
			childrenCount[*rec.parent]++
		}
		clean, _ := SplitBreakpointPrefix(rec.name)
		key := strings.ToLower(clean)
		if prevID, dup := existingIDByClean[key]; dup {
			prevClean, _ := SplitBreakpointPrefix(existingByID[prevID].name)
			if prevClean == "" {
				prevClean = fmt.Sprintf("ID %d", prevID)
			}
			return nil, nil, fmt.Errorf(
				"this hierarchy cannot be edited in the Flat Rank Table without losing node %q (duplicate or '~' twin names with %q); use the Hierarchy Tree view",
				prevClean, rec.name,
			)
		}
		existingIDByClean[key] = rec.id
	}

	_, _, baselineFlatRows, _ := buildHierarchyTreeAndFlatRows(existingRecords)
	baseTemp := minExistingID - 1
	baselineByClean, _, bErr := planFlatHierarchyNodes(baselineFlatRows, existingIDByClean, func() (int64, error) {
		baseTemp--
		return baseTemp, nil
	})
	if bErr != nil {
		return nil, nil, fmt.Errorf("this hierarchy cannot be edited in the Flat Rank Table (%v); use the Hierarchy Tree view", bErr)
	}
	baselineByID := make(map[int64]*flatPlannedNode, len(baselineByClean))
	for _, n := range baselineByClean {
		baselineByID[n.id] = n
	}

	unrepresentedIDs := map[int64]bool{}
	for _, rec := range existingRecords {
		baseNode := baselineByID[rec.id]
		if baseNode == nil || (rec.level >= 1 && rec.level <= 11 && baseNode.level != rec.level) {
			unrepresentedIDs[rec.id] = true
		}
	}

	nextTempID := minExistingID - 1
	tempIDs := map[int64]bool{}
	desiredByClean, desiredOrder, err := planFlatHierarchyNodes(rows, existingIDByClean, func() (int64, error) {
		nextTempID--
		tempIDs[nextTempID] = true
		return nextTempID, nil
	})
	if err != nil {
		return nil, nil, err
	}

	finalNodes := make([]*flatPlannedNode, 0, len(desiredOrder)+len(unrepresentedIDs))
	finalByID := make(map[int64]*flatPlannedNode, len(desiredOrder)+len(unrepresentedIDs))
	for _, key := range desiredOrder {
		n := desiredByClean[key]
		if unrepresentedIDs[n.id] {
			orig := existingByID[n.id]
			clean, _ := SplitBreakpointPrefix(orig.name)
			return nil, nil, fmt.Errorf(
				"this hierarchy cannot be edited in the Flat Rank Table without losing node %q (already exists as a non-flat Level %d node); use the Hierarchy Tree view",
				clean, orig.level,
			)
		}
		if orig, existed := existingByID[n.id]; existed {
			if n.tag == "" && !strings.EqualFold(strings.TrimSpace(orig.tag), "working") {
				n.tag = orig.tag
			}
			if orig.parent != nil && unrepresentedIDs[*orig.parent] {
				baseNode := baselineByID[n.id]
				if baseNode == nil || !sameInt64Ptr(n.parent, baseNode.parent) {
					hiddenClean, _ := SplitBreakpointPrefix(existingByID[*orig.parent].name)
					return nil, nil, fmt.Errorf(
						"this hierarchy cannot be edited in the Flat Rank Table without losing node %q (cannot reparent %q across a non-flat rank chain); use the Hierarchy Tree view",
						hiddenClean, orig.name,
					)
				}
				n.parent = copyInt64Ptr(orig.parent)
			}
		}
		finalNodes = append(finalNodes, n)
		finalByID[n.id] = n
	}

	requestLeafIDs := map[int64]bool{}
	for _, r := range rows {
		if r.LeafID != 0 {
			requestLeafIDs[r.LeafID] = true
		}
	}

	for _, rec := range existingRecords {
		if !unrepresentedIDs[rec.id] {
			continue
		}
		preserved := &flatPlannedNode{
			id:     rec.id,
			name:   rec.name,
			parent: copyInt64Ptr(rec.parent),
			level:  rec.level,
			tag:    rec.tag,
		}
		finalNodes = append(finalNodes, preserved)
		finalByID[rec.id] = preserved
	}

	if len(unrepresentedIDs) > 0 {
		survivingKids := make(map[int64]int, len(unrepresentedIDs))
		for _, n := range finalNodes {
			if n.parent != nil {
				survivingKids[*n.parent]++
			}
		}
		for _, rec := range existingRecords {
			if !unrepresentedIDs[rec.id] {
				continue
			}
			clean, _ := SplitBreakpointPrefix(rec.name)
			if clean == "" {
				clean = fmt.Sprintf("ID %d", rec.id)
			}
			if rec.parent != nil && finalByID[*rec.parent] == nil {
				return nil, nil, fmt.Errorf(
					"this hierarchy cannot be edited in the Flat Rank Table without losing node %q (its parent was removed); use the Hierarchy Tree view",
					clean,
				)
			}
			if childrenCount[rec.id] > 0 && survivingKids[rec.id] == 0 {
				return nil, nil, fmt.Errorf(
					"this hierarchy cannot be edited in the Flat Rank Table without losing node %q (same-rank or inverted-level nesting); use the Hierarchy Tree view",
					clean,
				)
			}
			if childrenCount[rec.id] == 0 && !requestLeafIDs[rec.id] {
				return nil, nil, fmt.Errorf(
					"this hierarchy cannot be edited in the Flat Rank Table without losing node %q (non-flat leaf rank); use the Hierarchy Tree view",
					clean,
				)
			}
		}

		collectUnrepAncestors := func(startID int64, parentOf func(int64) *int64) []int64 {
			var chain []int64
			seen := map[int64]bool{startID: true}
			curr := parentOf(startID)
			for curr != nil && !seen[*curr] {
				seen[*curr] = true
				if unrepresentedIDs[*curr] {
					chain = append(chain, *curr)
				}
				curr = parentOf(*curr)
			}
			return chain
		}
		origParentOf := func(id int64) *int64 {
			r, ok := existingByID[id]
			if !ok {
				return nil
			}
			return r.parent
		}
		finalParentOf := func(id int64) *int64 {
			n := finalByID[id]
			if n == nil {
				return nil
			}
			return n.parent
		}
		for _, rec := range existingRecords {
			if finalByID[rec.id] == nil {
				continue
			}
			before := collectUnrepAncestors(rec.id, origParentOf)
			after := collectUnrepAncestors(rec.id, finalParentOf)
			if !slices.Equal(before, after) {
				lostID := rec.id
				if len(before) > 0 {
					lostID = before[0]
				}
				clean, _ := SplitBreakpointPrefix(existingByID[lostID].name)
				return nil, nil, fmt.Errorf(
					"this hierarchy cannot be edited in the Flat Rank Table without losing node %q (same-rank or inverted-level nesting); use the Hierarchy Tree view",
					clean,
				)
			}
		}
	}

	if len(tempIDs) > 0 {
		realByTemp := make(map[int64]int64, len(tempIDs))
		for _, n := range finalNodes {
			if tempIDs[n.id] {
				allocated, aErr := allocate()
				if aErr != nil {
					return nil, nil, aErr
				}
				realByTemp[n.id] = allocated
				n.id = allocated
			}
		}
		for _, n := range finalNodes {
			if n.parent != nil {
				if realID, mapped := realByTemp[*n.parent]; mapped {
					v := realID
					n.parent = &v
				}
			}
		}
	}

	return finalNodes, unrepresentedIDs, nil
}
