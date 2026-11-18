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
	clean := strings.TrimPrefix(trimmed, "~")
	clean = strings.TrimSpace(clean)
	if clean == "" {
		return "", errors.New("hierarchy node name cannot be blank")
	}
	final := clean
	if isBreak || strings.HasPrefix(trimmed, "~") {
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

			res, proposal, mErr := mutate(owner, tx, hierName, tableName)
			if mErr != nil {
				return mErr
			}
			if err := ensureHierarchyTableAcyclicAndValid(ctx, tx, tableName); err != nil {
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

func ensureHierarchyTableAcyclicAndValid(ctx context.Context, tx *sql.Tx, tableName string) error {
	rows, err := tx.QueryContext(ctx,
		`SELECT "ID", COALESCE(CAST("Name" AS TEXT), ''), "Parent", COALESCE("Level", 11)
		 FROM main.`+vprocore.QuoteHeaderIdentifier(tableName))
	if err != nil {
		return err
	}
	defer rows.Close()

	var records []rawHierarchyRecord
	seenNames := map[string]int64{}
	for rows.Next() {
		var r rawHierarchyRecord
		var parent sql.NullInt64
		if err := rows.Scan(&r.id, &r.name, &parent, &r.level); err != nil {
			return err
		}
		if parent.Valid {
			p := parent.Int64
			r.parent = &p
		}
		lowerName := strings.ToLower(strings.TrimSpace(r.name))
		if existingID, dup := seenNames[lowerName]; dup {
			return fmt.Errorf("duplicate hierarchy node name %q (nodes %d and %d)", r.name, existingID, r.id)
		}
		seenNames[lowerName] = r.id
		records = append(records, r)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	cycles, orphans, blanks := DetectHierarchyCyclesAndOrphans(records)
	if blanks > 0 {
		return errors.New("hierarchy cannot contain blank node names")
	}
	if len(orphans) > 0 {
		return fmt.Errorf("hierarchy contains orphan parent reference on node(s) %v", orphans)
	}
	if len(cycles) > 0 {
		return fmt.Errorf("hierarchy mutation rejected: cycle detected involving node(s) %v", cycles)
	}
	return nil
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
			var parentPtr *int64
			if parent.Valid {
				p := parent.Int64
				parentPtr = &p
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
// (Class | Order | SubOrder | Alliance | SubAlliance | Association | SubAssociation | Facies | WorkingUnit | SiteSeries)
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

		existingIDByClean := map[string]int64{}
		existingIDs := map[int64]bool{}
		rows, err := tx.QueryContext(ctx, `SELECT "ID", COALESCE(CAST("Name" AS TEXT), '') FROM main.`+qTable)
		if err != nil {
			return nil, nil, err
		}
		for rows.Next() {
			var id int64
			var nm string
			if err := rows.Scan(&id, &nm); err != nil {
				rows.Close()
				return nil, nil, err
			}
			existingIDs[id] = true
			clean, _ := SplitBreakpointPrefix(nm)
			if clean != "" {
				existingIDByClean[strings.ToLower(clean)] = id
			}
		}
		if err := errors.Join(rows.Err(), rows.Close()); err != nil {
			return nil, nil, err
		}

		// UX-CLASS-001: refuse instead of silently deleting nodes when the current
		// hierarchy cannot round-trip through the flat rank table (same-rank chains,
		// "~X"/"X" clean-name twins, blank names, cycles or orphans).
		if err := ensureFlatHierarchyRoundTrips(ctx, tx, qTable, hasTag, existingIDByClean); err != nil {
			return nil, nil, err
		}

		desiredByClean, desiredOrder, err := planFlatHierarchyNodes(request.Rows, existingIDByClean, func() (int64, error) {
			return allocateHierarchyNodeID(ctx, tx, tableName)
		})
		if err != nil {
			return nil, nil, err
		}

		// Diffed synchronization inside tx: DELETE removed, UPDATE existing (preserving legacy
		// MyOrder, ChildID, StartChild, LastChild, Flag columns), and INSERT added nodes.
		desiredByID := make(map[int64]*flatPlannedNode, len(desiredOrder))
		for _, key := range desiredOrder {
			n := desiredByClean[key]
			desiredByID[n.id] = n
		}
		var removedIDs []int64
		for id := range existingIDs {
			if desiredByID[id] == nil {
				removedIDs = append(removedIDs, id)
			}
		}
		slices.Sort(removedIDs)
		for _, id := range removedIDs {
			if _, err := tx.ExecContext(ctx, `DELETE FROM main.`+qTable+` WHERE "ID" = ?`, id); err != nil {
				return nil, nil, err
			}
		}
		for _, key := range desiredOrder {
			n := desiredByClean[key]
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
			AffectedRows: len(desiredOrder),
		}, request, nil
	})
}

func nullStringIfEmpty(s string) any {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	return s
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
				sameParent := (existing.parent == nil && parentID == nil) ||
					(existing.parent != nil && parentID != nil && *existing.parent == *parentID)
				if !sameParent {
					return nil, nil, fmt.Errorf("flat row %d places node %q under conflicting parents in the same hierarchy", rowIdx+1, clean)
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
			var pCopy *int64
			if parentID != nil {
				v := *parentID
				pCopy = &v
			}
			desiredByClean[key] = &flatPlannedNode{id: id, name: validatedName, parent: pCopy, level: step.level, tag: step.tag}
			desiredOrder = append(desiredOrder, key)
			idCopy := id
			parentID = &idCopy
		}
	}
	return desiredByClean, desiredOrder, nil
}

// ensureFlatHierarchyRoundTrips re-plans the stored hierarchy from its own flat
// rows and requires every stored node to survive with the same ID, parent and
// (valid) level; otherwise a flat save would silently delete or reparent nodes.
func ensureFlatHierarchyRoundTrips(ctx context.Context, tx *sql.Tx, qTable string, hasTag bool, existingIDByClean map[string]int64) error {
	tagExpr := `''`
	if hasTag {
		tagExpr = `COALESCE(CAST("Tag" AS TEXT), '')`
	}
	rows, err := tx.QueryContext(ctx, `SELECT "ID", COALESCE(CAST("Name" AS TEXT), ''), "Parent", COALESCE("Level", 11), `+tagExpr+` FROM main.`+qTable+` ORDER BY "ID"`)
	if err != nil {
		return err
	}
	var records []rawHierarchyRecord
	for rows.Next() {
		var rec rawHierarchyRecord
		var parent sql.NullInt64
		if err := rows.Scan(&rec.id, &rec.name, &parent, &rec.level, &rec.tag); err != nil {
			rows.Close()
			return err
		}
		if parent.Valid {
			v := parent.Int64
			rec.parent = &v
		}
		records = append(records, rec)
	}
	if err := errors.Join(rows.Err(), rows.Close()); err != nil {
		return err
	}
	_, _, flatRows, _ := buildHierarchyTreeAndFlatRows(records)
	next := int64(-1)
	planned, _, err := planFlatHierarchyNodes(flatRows, existingIDByClean, func() (int64, error) {
		next--
		return next, nil
	})
	if err != nil {
		return fmt.Errorf("this hierarchy cannot be edited in the Flat Rank Table (%v); use the Hierarchy Tree view", err)
	}
	byID := make(map[int64]*flatPlannedNode, len(planned))
	for _, node := range planned {
		byID[node.id] = node
	}
	for _, rec := range records {
		node := byID[rec.id]
		clean, _ := SplitBreakpointPrefix(rec.name)
		lost := node == nil
		if !lost {
			sameParent := (node.parent == nil && rec.parent == nil) ||
				(node.parent != nil && rec.parent != nil && *node.parent == *rec.parent)
			lost = !sameParent || (rec.level >= 1 && rec.level <= 11 && node.level != rec.level)
		}
		if lost {
			if clean == "" {
				clean = fmt.Sprintf("ID %d", rec.id)
			}
			return fmt.Errorf("this hierarchy cannot be edited in the Flat Rank Table without losing node %q (same-rank nesting, duplicate or '~' twin names, or broken links); use the Hierarchy Tree view", clean)
		}
	}
	return nil
}
