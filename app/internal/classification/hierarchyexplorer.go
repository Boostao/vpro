package classification

import (
	"context"
	"database/sql"
	"errors"
	"slices"
	"strings"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

// Canonical wide phytosociological rank columns (1..11 VPro levels + WorkingUnit).
var PhytosociologicalRanks = []struct {
	Key   string `json:"key"`
	Label string `json:"label"`
	Level int64  `json:"level"`
}{
	{Key: "Superclass", Label: "Superclass", Level: 1},
	{Key: "Class", Label: "Class", Level: 2},
	{Key: "Subclass", Label: "Subclass", Level: 3},
	{Key: "Order", Label: "Order", Level: 4},
	{Key: "SubOrder", Label: "SubOrder", Level: 5},
	{Key: "Alliance", Label: "Alliance", Level: 6},
	{Key: "SubAlliance", Label: "SubAlliance", Level: 7},
	{Key: "Association", Label: "Association", Level: 8},
	{Key: "SubAssociation", Label: "SubAssociation", Level: 9},
	{Key: "Facies", Label: "Facies", Level: 10},
	{Key: "WorkingUnit", Label: "WorkingUnit", Level: 10},
	{Key: "SiteSeries", Label: "SiteSeries", Level: 11},
}

type HierarchyExplorerNode struct {
	ID           int64                   `json:"id"`
	Name         string                  `json:"name"`
	CleanName    string                  `json:"cleanName"`
	Parent       *int64                  `json:"parent"`
	Level        int64                   `json:"level"`
	RankName     string                  `json:"rankName"`
	Tag          string                  `json:"tag,omitempty"`
	IsBreakpoint bool                    `json:"isBreakpoint"`
	Depth        int                     `json:"depth"`
	Children     []HierarchyExplorerNode `json:"children"`
}

// FlatHierarchyRow represents one root-to-leaf classification chain in the editable wide rank table:
// Class | Order | SubOrder | Alliance | SubAlliance | Association | SubAssociation | Facies | WorkingUnit | SiteSeries
type FlatHierarchyRow struct {
	LeafID         int64  `json:"leafId"`
	Superclass     string `json:"superclass,omitempty"`
	Class          string `json:"class"`
	Subclass       string `json:"subclass,omitempty"`
	Order          string `json:"order"`
	SubOrder       string `json:"subOrder"`
	Alliance       string `json:"alliance"`
	SubAlliance    string `json:"subAlliance"`
	Association    string `json:"association"`
	SubAssociation string `json:"subAssociation"`
	Facies         string `json:"facies"`
	WorkingUnit    string `json:"workingUnit"`
	SiteSeries     string `json:"siteSeries"`
	BreakpointRank string `json:"breakpointRank,omitempty"`
}

func (r *FlatHierarchyRow) UnmarshalJSON(data []byte) error {
	type plain FlatHierarchyRow
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type HierarchyDiagnostics struct {
	TotalNodes      int     `json:"totalNodes"`
	RootNodes       int     `json:"rootNodes"`
	BreakpointNodes int     `json:"breakpointNodes"`
	BlankNameNodes  int     `json:"blankNameNodes"`
	OrphanNodes     []int64 `json:"orphanNodes"`
	CycleNodeIDs    []int64 `json:"cycleNodeIds"`
}

type HierarchyExplorerView struct {
	ContextID     string                  `json:"contextId"`
	Project       string                  `json:"project"`
	Hierarchy     string                  `json:"hierarchy"`
	HierarchyPath string                  `json:"hierarchyPath"`
	TableName     string                  `json:"tableName"`
	Roots         []HierarchyExplorerNode `json:"roots"`
	FlatNodes     []HierarchyExplorerNode `json:"flatNodes"`
	FlatRankRows  []FlatHierarchyRow      `json:"flatRankRows"`
	Diagnostics   HierarchyDiagnostics    `json:"diagnostics"`
}

func levelToRankName(level int64, tag string) string {
	switch level {
	case 1:
		return "Superclass"
	case 2:
		return "Class"
	case 3:
		return "Subclass"
	case 4:
		return "Order"
	case 5:
		return "SubOrder"
	case 6:
		return "Alliance"
	case 7:
		return "SubAlliance"
	case 8:
		return "Association"
	case 9:
		return "SubAssociation"
	case 10:
		if strings.EqualFold(strings.TrimSpace(tag), "working") {
			return "WorkingUnit"
		}
		return "Facies"
	case 11:
		return "SiteSeries"
	default:
		return "SiteSeries"
	}
}

func SplitBreakpointPrefix(name string) (clean string, isBreak bool) {
	trimmed := strings.TrimSpace(name)
	for strings.HasPrefix(trimmed, "~") {
		isBreak = true
		trimmed = strings.TrimSpace(strings.TrimLeft(trimmed, "~"))
	}
	return trimmed, isBreak
}

type rawHierarchyRecord struct {
	id     int64
	name   string
	parent *int64
	level  int64
	tag    string
}

func DetectHierarchyCyclesAndOrphans(records []rawHierarchyRecord) (cycleIDs []int64, orphanIDs []int64, blankCount int) {
	byID := make(map[int64]rawHierarchyRecord, len(records))
	for _, r := range records {
		byID[r.id] = r
		clean, _ := SplitBreakpointPrefix(r.name)
		if strings.TrimSpace(clean) == "" {
			blankCount++
		}
	}
	cycleSet := map[int64]bool{}
	orphanSet := map[int64]bool{}

	for _, r := range records {
		if r.parent != nil {
			if _, ok := byID[*r.parent]; !ok {
				orphanSet[r.id] = true
			}
		}
		visited := []int64{r.id}
		visitedSet := map[int64]int{r.id: 0}
		curr := r.parent
		for curr != nil {
			if idx, seen := visitedSet[*curr]; seen {
				for _, cid := range visited[idx:] {
					cycleSet[cid] = true
				}
				break
			}
			nextNode, exists := byID[*curr]
			if !exists {
				break
			}
			visitedSet[*curr] = len(visited)
			visited = append(visited, *curr)
			curr = nextNode.parent
		}
	}

	for id := range cycleSet {
		cycleIDs = append(cycleIDs, id)
	}
	slices.Sort(cycleIDs)
	for id := range orphanSet {
		orphanIDs = append(orphanIDs, id)
	}
	slices.Sort(orphanIDs)
	return cycleIDs, orphanIDs, blankCount
}

func effectiveCycleEntryRank(level int64) int64 {
	if level >= 1 && level <= 11 {
		return level
	}
	return 12
}

func compareCycleEntryCandidate(a, b rawHierarchyRecord) int {
	la, lb := effectiveCycleEntryRank(a.level), effectiveCycleEntryRank(b.level)
	if la != lb {
		if la < lb {
			return -1
		}
		return 1
	}
	ca, _ := SplitBreakpointPrefix(a.name)
	cb, _ := SplitBreakpointPrefix(b.name)
	if cmp := strings.Compare(strings.ToLower(ca), strings.ToLower(cb)); cmp != 0 {
		return cmp
	}
	if a.id < b.id {
		return -1
	}
	if a.id > b.id {
		return 1
	}
	return 0
}

func buildHierarchyTreeAndFlatRows(records []rawHierarchyRecord) ([]HierarchyExplorerNode, []HierarchyExplorerNode, []FlatHierarchyRow, HierarchyDiagnostics) {
	cycles, orphans, blanks := DetectHierarchyCyclesAndOrphans(records)
	cycleSet := map[int64]bool{}
	for _, id := range cycles {
		cycleSet[id] = true
	}
	byID := make(map[int64]rawHierarchyRecord, len(records))
	childrenByParent := map[int64][]rawHierarchyRecord{}
	var rootsRaw []rawHierarchyRecord
	breakCount := 0

	for _, r := range records {
		byID[r.id] = r
		if _, isBrk := SplitBreakpointPrefix(r.name); isBrk {
			breakCount++
		}
	}

	sortedRecords := slices.Clone(records)
	slices.SortFunc(sortedRecords, func(a, b rawHierarchyRecord) int {
		ca, _ := SplitBreakpointPrefix(a.name)
		cb, _ := SplitBreakpointPrefix(b.name)
		if cmp := strings.Compare(strings.ToLower(ca), strings.ToLower(cb)); cmp != 0 {
			return cmp
		}
		if a.id < b.id {
			return -1
		}
		if a.id > b.id {
			return 1
		}
		return 0
	})

	// Partition existing parent cycles into disjoint directed cycles and promote one
	// deterministic entry node per cycle to root so cyclic nodes remain visible and repairable.
	cycleRootSet := map[int64]bool{}
	visitedCycleNodes := map[int64]bool{}
	for _, r := range sortedRecords {
		if !cycleSet[r.id] || visitedCycleNodes[r.id] {
			continue
		}
		var members []rawHierarchyRecord
		currID := r.id
		for !visitedCycleNodes[currID] {
			visitedCycleNodes[currID] = true
			rec, ok := byID[currID]
			if !ok {
				break
			}
			members = append(members, rec)
			if rec.parent == nil || !cycleSet[*rec.parent] {
				break
			}
			currID = *rec.parent
		}
		if len(members) > 0 {
			best := members[0]
			for _, cand := range members[1:] {
				if compareCycleEntryCandidate(cand, best) < 0 {
					best = cand
				}
			}
			cycleRootSet[best.id] = true
		}
	}

	for _, r := range sortedRecords {
		if cycleRootSet[r.id] {
			rootsRaw = append(rootsRaw, r) // surface broken-cycle entry at root so cyclic branches remain inspectable/repairable
		} else if r.parent == nil {
			rootsRaw = append(rootsRaw, r)
		} else if _, exists := byID[*r.parent]; !exists {
			rootsRaw = append(rootsRaw, r) // surface orphan at root so it remains inspectable/repairable
		} else {
			childrenByParent[*r.parent] = append(childrenByParent[*r.parent], r)
		}
	}

	flatNodes := []HierarchyExplorerNode{}
	flatRows := []FlatHierarchyRow{}

	var buildSubtree func(rec rawHierarchyRecord, depth int, chain []rawHierarchyRecord) HierarchyExplorerNode
	buildSubtree = func(rec rawHierarchyRecord, depth int, chain []rawHierarchyRecord) HierarchyExplorerNode {
		clean, isBrk := SplitBreakpointPrefix(rec.name)
		lvl := rec.level
		if lvl < 1 || lvl > 11 {
			lvl = min(11, int64(depth+2))
		}
		rank := levelToRankName(lvl, rec.tag)
		nextChain := append(slices.Clone(chain), rec)

		var kidsRaw []rawHierarchyRecord
		for _, child := range childrenByParent[rec.id] {
			if slices.ContainsFunc(nextChain, func(prev rawHierarchyRecord) bool { return prev.id == child.id }) {
				continue
			}
			kidsRaw = append(kidsRaw, child)
		}
		node := HierarchyExplorerNode{
			ID:           rec.id,
			Name:         rec.name,
			CleanName:    clean,
			Parent:       rec.parent,
			Level:        lvl,
			RankName:     rank,
			Tag:          rec.tag,
			IsBreakpoint: isBrk,
			Depth:        depth,
			Children:     make([]HierarchyExplorerNode, 0, len(kidsRaw)),
		}
		flatNodes = append(flatNodes, HierarchyExplorerNode{
			ID:           node.ID,
			Name:         node.Name,
			CleanName:    node.CleanName,
			Parent:       node.Parent,
			Level:        node.Level,
			RankName:     node.RankName,
			Tag:          node.Tag,
			IsBreakpoint: node.IsBreakpoint,
			Depth:        node.Depth,
			Children:     []HierarchyExplorerNode{},
		})

		if len(kidsRaw) == 0 {
			flatRows = append(flatRows, chainToFlatHierarchyRow(nextChain))
		} else {
			for _, child := range kidsRaw {
				node.Children = append(node.Children, buildSubtree(child, depth+1, nextChain))
			}
		}
		return node
	}

	roots := make([]HierarchyExplorerNode, 0, len(rootsRaw))
	for _, r := range rootsRaw {
		roots = append(roots, buildSubtree(r, 0, nil))
	}

	diag := HierarchyDiagnostics{
		TotalNodes:      len(records),
		RootNodes:       len(rootsRaw),
		BreakpointNodes: breakCount,
		BlankNameNodes:  blanks,
		OrphanNodes:     orphans,
		CycleNodeIDs:    cycles,
	}
	if diag.OrphanNodes == nil {
		diag.OrphanNodes = []int64{}
	}
	if diag.CycleNodeIDs == nil {
		diag.CycleNodeIDs = []int64{}
	}
	return roots, flatNodes, flatRows, diag
}

type flatSubseqCandidate struct {
	indices     []int
	includeLeaf bool
}

func betterFlatSubseq(a, b flatSubseqCandidate) bool {
	if len(a.indices) != len(b.indices) {
		return len(a.indices) > len(b.indices)
	}
	if a.includeLeaf != b.includeLeaf {
		return a.includeLeaf
	}
	for i := range a.indices {
		if a.indices[i] != b.indices[i] {
			return a.indices[i] < b.indices[i]
		}
	}
	return false
}

func effectiveChainRank(rec rawHierarchyRecord, idx, chainLen int) (string, int) {
	lvl := rec.level
	if lvl < 1 || lvl > 11 {
		if idx == chainLen-1 {
			lvl = 11
		} else {
			lvl = min(10, int64(idx+2))
		}
	}
	rank := levelToRankName(lvl, rec.tag)
	switch rank {
	case "Superclass":
		return rank, 0
	case "Class":
		return rank, 1
	case "Subclass":
		return rank, 2
	case "Order":
		return rank, 3
	case "SubOrder":
		return rank, 4
	case "Alliance":
		return rank, 5
	case "SubAlliance":
		return rank, 6
	case "Association":
		return rank, 7
	case "SubAssociation":
		return rank, 8
	case "Facies":
		return rank, 9
	case "WorkingUnit":
		return rank, 10
	default:
		return "SiteSeries", 11
	}
}

// selectFlatChainIndices chooses the longest strictly increasing rank-slot
// subsequence along a root-to-leaf chain, preferring inclusion of the leaf on
// equal length and otherwise the earliest (uppermost) ancestor at each rank so
// a descendant with an inverted or duplicate Level never overwrites an ancestor
// rank slot or inverts parent-child order across rows.
func selectFlatChainIndices(slots []int) []int {
	if len(slots) == 0 {
		return nil
	}
	var bestBySlot [12]flatSubseqCandidate
	for idx, slot := range slots {
		isLeaf := idx == len(slots)-1
		cand := flatSubseqCandidate{indices: []int{idx}, includeLeaf: isLeaf}
		for prevSlot := 0; prevSlot < slot; prevSlot++ {
			prev := bestBySlot[prevSlot]
			if len(prev.indices) == 0 {
				continue
			}
			ext := flatSubseqCandidate{
				indices:     append(slices.Clone(prev.indices), idx),
				includeLeaf: isLeaf,
			}
			if betterFlatSubseq(ext, cand) {
				cand = ext
			}
		}
		if len(bestBySlot[slot].indices) == 0 || betterFlatSubseq(cand, bestBySlot[slot]) {
			bestBySlot[slot] = cand
		}
	}
	var winner flatSubseqCandidate
	for _, cand := range bestBySlot {
		if len(cand.indices) == 0 {
			continue
		}
		if len(winner.indices) == 0 || betterFlatSubseq(cand, winner) {
			winner = cand
		}
	}
	return winner.indices
}

func chainToFlatHierarchyRow(chain []rawHierarchyRecord) FlatHierarchyRow {
	var row FlatHierarchyRow
	if len(chain) == 0 {
		return row
	}
	row.LeafID = chain[len(chain)-1].id
	ranks := make([]string, len(chain))
	slots := make([]int, len(chain))
	for idx, rec := range chain {
		ranks[idx], slots[idx] = effectiveChainRank(rec, idx, len(chain))
	}
	for _, idx := range selectFlatChainIndices(slots) {
		rec := chain[idx]
		rank := ranks[idx]
		if _, isBrk := SplitBreakpointPrefix(rec.name); isBrk {
			row.BreakpointRank = rank
		}
		// Keep full Name (including '~' prefix when marked as breakpoint) so flat table displays & round-trips breakpoints losslessly.
		switch rank {
		case "Superclass":
			row.Superclass = rec.name
		case "Class":
			row.Class = rec.name
		case "Subclass":
			row.Subclass = rec.name
		case "Order":
			row.Order = rec.name
		case "SubOrder":
			row.SubOrder = rec.name
		case "Alliance":
			row.Alliance = rec.name
		case "SubAlliance":
			row.SubAlliance = rec.name
		case "Association":
			row.Association = rec.name
		case "SubAssociation":
			row.SubAssociation = rec.name
		case "Facies":
			row.Facies = rec.name
		case "WorkingUnit":
			row.WorkingUnit = rec.name
		default:
			row.SiteSeries = rec.name
		}
	}
	return row
}

func GetHierarchyExplorer(ctx context.Context, contexts *vprocore.ContextService, contextID string) (*HierarchyExplorerView, error) {
	if ctx == nil {
		return nil, errors.New("hierarchy explorer requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("classification context service is unavailable")
	}

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (_ *HierarchyExplorerView, resultErr error) {
		owner := plots.Projects.Sqlite
		if owner.Selection.Hierarchy == "" || owner.Selection.Hierarchy == "None" {
			return &HierarchyExplorerView{
				ContextID:    contextID,
				Project:      owner.Selection.Project,
				Hierarchy:    "None",
				Roots:        []HierarchyExplorerNode{},
				FlatNodes:    []HierarchyExplorerNode{},
				FlatRankRows: []FlatHierarchyRow{},
				Diagnostics:  HierarchyDiagnostics{OrphanNodes: []int64{}, CycleNodeIDs: []int64{}},
			}, nil
		}

		unlock, err := owner.AcquireMutex(ctx)
		if err != nil {
			return nil, err
		}
		defer unlock()
		if err := vprocore.ProfileOwnedFiles(owner); err != nil {
			return nil, err
		}
		tx, err := owner.BeginReadSnapshot(ctx)
		if err != nil {
			return nil, err
		}
		defer func() {
			if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
				resultErr = errors.Join(resultErr, rb)
			}
		}()

		tableName := owner.Selection.Hierarchy + "_Hierarchy"
		hasTag := false
		cols, err := vprocore.ReadSQLiteStorageColumns(ctx, tx, "hierarchy", tableName)
		if err != nil {
			return nil, err
		}
		for _, c := range cols {
			if strings.EqualFold(c.Name, "Tag") {
				hasTag = true
			}
		}

		tagExpr := `''`
		if hasTag {
			tagExpr = `COALESCE(CAST("Tag" AS TEXT), '')`
		}
		rows, err := tx.QueryContext(ctx,
			`SELECT "ID", COALESCE(CAST("Name" AS TEXT), ''), "Parent", COALESCE("Level", 11), `+tagExpr+
				` FROM "hierarchy".`+vprocore.QuoteHeaderIdentifier(tableName)+` ORDER BY "ID" ASC`)
		if err != nil {
			return nil, err
		}
		var records []rawHierarchyRecord
		for rows.Next() {
			var r rawHierarchyRecord
			var parent sql.NullInt64
			if err := rows.Scan(&r.id, &r.name, &parent, &r.level, &r.tag); err != nil {
				rows.Close()
				return nil, err
			}
			if parent.Valid {
				p := parent.Int64
				r.parent = &p
			}
			records = append(records, r)
		}
		if err := errors.Join(rows.Err(), rows.Close()); err != nil {
			return nil, err
		}

		roots, flatNodes, flatRows, diag := buildHierarchyTreeAndFlatRows(records)

		if err := vprocore.ProfileOwnedFiles(owner); err != nil {
			return nil, err
		}
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		if err := tx.Commit(); err != nil {
			return nil, err
		}
		return &HierarchyExplorerView{
			ContextID:     contextID,
			Project:       owner.Selection.Project,
			Hierarchy:     owner.Selection.Hierarchy,
			HierarchyPath: owner.Selection.HierarchyPath,
			TableName:     tableName,
			Roots:         roots,
			FlatNodes:     flatNodes,
			FlatRankRows:  flatRows,
			Diagnostics:   diag,
		}, nil
	})
}
