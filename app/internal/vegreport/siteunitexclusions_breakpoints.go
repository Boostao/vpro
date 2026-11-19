package vegreport

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"slices"
	"strings"
	"unicode/utf16"

	"github.com/boostao/vpro/app/internal/vprocore"
)

type hierarchyBreakNode struct {
	id     int64
	name   string
	parent *int64
	level  int64
}

func cleanBreakNodeName(name string) (string, bool) {
	trimmed := strings.TrimSpace(name)
	if strings.HasPrefix(trimmed, "~") {
		return strings.TrimSpace(strings.TrimPrefix(trimmed, "~")), true
	}
	return trimmed, false
}

func loadHierarchyNodesFromTx(ctx context.Context, tx *sql.Tx, hierName string) ([]hierarchyBreakNode, error) {
	tableName := hierName + "_Hierarchy"
	var count int
	if err := tx.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM "hierarchy".sqlite_master WHERE type='table' AND name COLLATE BINARY=?`,
		tableName,
	).Scan(&count); err != nil {
		return nil, err
	}
	if count != 1 {
		return nil, fmt.Errorf("active hierarchy table %s does not exist in attached hierarchy database", tableName)
	}
	rows, err := tx.QueryContext(ctx,
		`SELECT "ID", COALESCE(CAST("Name" AS TEXT), ''), "Parent", COALESCE("Level", 11)
		 FROM "hierarchy".`+vprocore.QuoteHeaderIdentifier(tableName)+` ORDER BY "ID" ASC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var nodes []hierarchyBreakNode
	for rows.Next() {
		var n hierarchyBreakNode
		var p sql.NullInt64
		if err := rows.Scan(&n.id, &n.name, &p, &n.level); err != nil {
			return nil, err
		}
		if p.Valid {
			pv := p.Int64
			n.parent = &pv
		}
		nodes = append(nodes, n)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	// Verify hierarchy is acyclic before resolving breakpoints
	byID := make(map[int64]hierarchyBreakNode, len(nodes))
	for _, n := range nodes {
		byID[n.id] = n
	}
	for _, n := range nodes {
		visited := map[int64]bool{n.id: true}
		curr := n.parent
		for curr != nil {
			if visited[*curr] {
				return nil, fmt.Errorf("active hierarchy %s contains a parent cycle involving node %d", hierName, *curr)
			}
			next, ok := byID[*curr]
			if !ok {
				break
			}
			visited[*curr] = true
			curr = next.parent
		}
	}
	return nodes, nil
}

func resolveHierarchyBreakpointsOnSU(
	su vprocore.ProjectMetadataTable,
	nodes []hierarchyBreakNode,
	options HierarchyBreakpointOptions,
) (vprocore.ProjectMetadataTable, HierarchyBreakpointResolution, error) {
	sc, err := vprocore.SiteUnitTransferColumns(su, "PlotNumber", "SiteUnit")
	if err != nil {
		return vprocore.ProjectMetadataTable{}, HierarchyBreakpointResolution{}, err
	}

	policy := strings.ToLower(strings.TrimSpace(options.BreakpointPolicy))
	if policy == "" {
		policy = "lowest"
	}
	if policy != "lowest" && policy != "highest" {
		return vprocore.ProjectMetadataTable{}, HierarchyBreakpointResolution{}, fmt.Errorf("unsupported breakpointPolicy %q; expected 'lowest' or 'highest'", options.BreakpointPolicy)
	}
	unbrokenPolicy := strings.ToLower(strings.TrimSpace(options.UnbrokenUnitPolicy))
	if unbrokenPolicy == "" {
		unbrokenPolicy = "keep_original"
	}
	if unbrokenPolicy != "keep_original" && unbrokenPolicy != "exclude_unbroken" {
		return vprocore.ProjectMetadataTable{}, HierarchyBreakpointResolution{}, fmt.Errorf("unsupported unbrokenUnitPolicy %q; expected 'keep_original' or 'exclude_unbroken'", options.UnbrokenUnitPolicy)
	}

	byID := make(map[int64]hierarchyBreakNode, len(nodes))
	byCleanLower := make(map[string]hierarchyBreakNode, len(nodes))
	for _, n := range nodes {
		byID[n.id] = n
		clean, _ := cleanBreakNodeName(n.name)
		if clean != "" {
			byCleanLower[strings.ToLower(clean)] = n
		}
	}

	// Compute unit plot counts & distinct original units
	unitPlotCounts := map[string]int{}
	distinctOriginal := []string{}
	seenOrig := map[string]bool{}
	for _, row := range su.Rows {
		pCell := row.Cells[sc["PlotNumber"]]
		uCell := row.Cells[sc["SiteUnit"]]
		if uCell.Storage != "text" || uCell.Text == nil || strings.TrimSpace(*uCell.Text) == "" {
			continue
		}
		u := *uCell.Text
		if !seenOrig[u] {
			seenOrig[u] = true
			distinctOriginal = append(distinctOriginal, u)
		}
		if pCell.Storage == "text" && pCell.Text != nil && strings.TrimSpace(*pCell.Text) != "" {
			unitPlotCounts[u]++
		}
	}
	slices.Sort(distinctOriginal)

	mappingByUnit := map[string]HierarchyBreakpointUnitMapping{}
	mappings := make([]HierarchyBreakpointUnitMapping, 0, len(distinctOriginal))
	unmapped := []string{}
	bucketSources := map[string]map[string]bool{}
	bucketPlots := map[string]int{}
	afterUnitSet := map[string]bool{}
	rolledUpPlots := 0

	for _, orig := range distinctOriginal {
		cleanOrig, _ := cleanBreakNodeName(orig)
		startNode, matched := byCleanLower[strings.ToLower(cleanOrig)]

		var breaksBottomUp []hierarchyBreakNode
		if matched {
			curr := &startNode
			visited := map[int64]bool{}
			for curr != nil && !visited[curr.id] {
				visited[curr.id] = true
				if _, isBrk := cleanBreakNodeName(curr.name); isBrk {
					breaksBottomUp = append(breaksBottomUp, *curr)
				}
				if curr.parent == nil {
					break
				}
				parentNode, ok := byID[*curr.parent]
				if !ok {
					break
				}
				curr = &parentNode
			}
		} else {
			unmapped = append(unmapped, orig)
		}

		pCount := unitPlotCounts[orig]
		if len(breaksBottomUp) > 0 {
			chosen := breaksBottomUp[0] // lowest '~' ancestor (nearest to leaf)
			if policy == "highest" {
				chosen = breaksBottomUp[len(breaksBottomUp)-1] // highest '~' ancestor (nearest to root)
			}
			effective := strings.TrimSpace(chosen.name)
			if options.StripTildePrefix {
				effective, _ = cleanBreakNodeName(effective)
			}
			if len(utf16.Encode([]rune(effective))) > 255 {
				return vprocore.ProjectMetadataTable{}, HierarchyBreakpointResolution{}, fmt.Errorf("breakpoint unit %q cannot exceed 255 characters", effective)
			}
			m := HierarchyBreakpointUnitMapping{
				OriginalUnit:  orig,
				EffectiveUnit: effective,
				RolledUp:      effective != orig,
				MatchedInTree: true,
				Excluded:      false,
				PlotCount:     pCount,
			}
			mappingByUnit[orig] = m
			mappings = append(mappings, m)
			afterUnitSet[effective] = true
			if m.RolledUp {
				rolledUpPlots += pCount
			}
			if bucketSources[effective] == nil {
				bucketSources[effective] = map[string]bool{}
			}
			bucketSources[effective][orig] = true
			bucketPlots[effective] += pCount
		} else {
			if unbrokenPolicy == "exclude_unbroken" {
				m := HierarchyBreakpointUnitMapping{
					OriginalUnit:  orig,
					EffectiveUnit: "",
					RolledUp:      false,
					MatchedInTree: matched,
					Excluded:      true,
					PlotCount:     pCount,
				}
				mappingByUnit[orig] = m
				mappings = append(mappings, m)
			} else {
				m := HierarchyBreakpointUnitMapping{
					OriginalUnit:  orig,
					EffectiveUnit: orig,
					RolledUp:      false,
					MatchedInTree: matched,
					Excluded:      false,
					PlotCount:     pCount,
				}
				mappingByUnit[orig] = m
				mappings = append(mappings, m)
				afterUnitSet[orig] = true
			}
		}
	}

	rolledSU := vprocore.ProjectMetadataTable{
		Columns: append([]vprocore.ProjectMetadataColumn{}, su.Columns...),
		Rows:    make([]vprocore.ProjectMetadataRow, 0, len(su.Rows)),
	}
	sIdx := sc["SiteUnit"]
	for _, row := range su.Rows {
		uCell := row.Cells[sIdx]
		if uCell.Storage == "text" && uCell.Text != nil && strings.TrimSpace(*uCell.Text) != "" {
			m, ok := mappingByUnit[*uCell.Text]
			if ok && m.Excluded {
				continue
			}
			cloned := make([]vprocore.ProjectMetadataCell, len(row.Cells))
			for i, c := range row.Cells {
				cloned[i] = vprocore.CloneSiteUnitCell(c)
			}
			if ok && m.EffectiveUnit != "" {
				eff := m.EffectiveUnit
				cloned[sIdx] = vprocore.ProjectMetadataCell{Storage: "text", Text: &eff}
			}
			rolledSU.Rows = append(rolledSU.Rows, vprocore.ProjectMetadataRow{
				RowID: row.RowID,
				Cells: cloned,
			})
		} else {
			if unbrokenPolicy == "exclude_unbroken" {
				continue
			}
			cloned := make([]vprocore.ProjectMetadataCell, len(row.Cells))
			for i, c := range row.Cells {
				cloned[i] = vprocore.CloneSiteUnitCell(c)
			}
			rolledSU.Rows = append(rolledSU.Rows, vprocore.ProjectMetadataRow{
				RowID: row.RowID,
				Cells: cloned,
			})
		}
	}

	bucketKeys := make([]string, 0, len(bucketSources))
	for k := range bucketSources {
		bucketKeys = append(bucketKeys, k)
	}
	slices.Sort(bucketKeys)
	buckets := make([]HierarchyBreakpointBucket, 0, len(bucketKeys))
	for _, bk := range bucketKeys {
		srcs := make([]string, 0, len(bucketSources[bk]))
		for s := range bucketSources[bk] {
			srcs = append(srcs, s)
		}
		slices.Sort(srcs)
		buckets = append(buckets, HierarchyBreakpointBucket{
			BreakpointUnit: bk,
			SourceUnits:    srcs,
			PlotCount:      bucketPlots[bk],
		})
	}

	res := HierarchyBreakpointResolution{
		BreakpointPolicy:  policy,
		TotalUnitsBefore:  len(distinctOriginal),
		TotalUnitsAfter:   len(afterUnitSet),
		RolledUpPlotCount: rolledUpPlots,
		UnmappedUnits:     unmapped,
		Mappings:          mappings,
		Buckets:           buckets,
	}
	return rolledSU, res, nil
}

func ResolveHierarchyBreakpointUnits(
	ctx context.Context,
	contexts *vprocore.ContextService,
	contextID string,
	request HierarchyBreakpointRequest,
) (*HierarchyBreakpointResolution, error) {
	if ctx == nil {
		return nil, errors.New("hierarchy breakpoint resolution requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("vegetation report context service is unavailable")
	}
	rules, err := NormalizeExclusionRules(request.Rules, request.UseDefaultPresets)
	if err != nil {
		return nil, err
	}

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*HierarchyBreakpointResolution, error) {
		owner := plots.Projects.Sqlite
		if owner.Selection.SU == "" || owner.Selection.SU == "None" {
			return nil, errors.New("an active Site Unit (SU) table must be selected")
		}
		if owner.Selection.Hierarchy == "" || owner.Selection.Hierarchy == "None" {
			return nil, errors.New("an active Hierarchy table must be selected to resolve '~' breakpoints")
		}
		return vprocore.WithReadSnapshotValue(ctx, owner, func(tx *sql.Tx) (*HierarchyBreakpointResolution, error) {
			if err := vprocore.ProfileOwnedFiles(owner); err != nil {
				return nil, err
			}
			suTable, err := vprocore.ReadSQLiteStorageRows(ctx, tx, "su", owner.Selection.SU+"_SU", "", nil, "")
			if err != nil {
				return nil, err
			}
			filteredSU, _, err := FilterSUTableByExclusions(suTable, rules)
			if err != nil {
				return nil, err
			}
			nodes, err := loadHierarchyNodesFromTx(ctx, tx, owner.Selection.Hierarchy)
			if err != nil {
				return nil, err
			}
			_, res, err := resolveHierarchyBreakpointsOnSU(filteredSU, nodes, request.Options)
			if err != nil {
				return nil, err
			}
			res.ContextID = contextID
			res.Project = owner.Selection.Project
			res.SU = owner.Selection.SU
			res.Hierarchy = owner.Selection.Hierarchy

			if err := vprocore.ProfileOwnedFiles(owner); err != nil {
				return nil, err
			}
			return &res, nil
		})
	})
}
