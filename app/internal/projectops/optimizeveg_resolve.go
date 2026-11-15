package projectops

import (
	"encoding/hex"
	"fmt"
	"math"
	"slices"
	"strconv"
	"strings"

	"github.com/boostao/vpro/app/internal/vprocore"
)

func strPtrFromAuditVal(v any) *string {
	if v == nil {
		return nil
	}
	s := fmt.Sprint(v)
	return &s
}

func resolveVegTextConsensus(members []vegRowWithRowID, col, plot, species string) (rawSQLiteCell, *OptimizeVegConflict) {
	seen := map[string]bool{}
	var vals []string
	var ids []int64
	var chosen rawSQLiteCell
	hasVal := false
	for _, m := range members {
		c := m.cells[col]
		if c.storage == "null" {
			continue
		}
		var txt string
		switch c.storage {
		case "text":
			txt = string(c.bytes)
		case "integer":
			txt = strconv.FormatInt(c.intVal, 10)
		case "real":
			txt = vprocore.SourceDoubleDecimalString(c.realVal)
		case "blob":
			txt = hex.EncodeToString(c.bytes)
		default:
			continue
		}
		if strings.TrimSpace(txt) == "" {
			continue
		}
		if !hasVal {
			hasVal = true
			chosen = rawSQLiteCell{storage: c.storage, intVal: c.intVal, realVal: c.realVal, bytes: append([]byte(nil), c.bytes...)}
		}
		if !seen[txt] {
			seen[txt] = true
			vals = append(vals, txt)
		}
		if idCell := m.cells["ID"]; idCell.storage == "integer" {
			ids = append(ids, idCell.intVal)
		}
	}
	if !hasVal {
		return rawSQLiteCell{storage: "null"}, nil
	}
	if len(vals) > 1 {
		return rawSQLiteCell{storage: "null"}, &OptimizeVegConflict{
			PlotNumber: plot,
			Species:    species,
			Field:      col,
			Reason:     fmt.Sprintf("conflicting non-null %s values (%s)", col, strings.Join(vals, " vs ")),
			Values:     vals,
			SourceIDs:  ids,
		}
	}
	return chosen, nil
}

func resolveVegIntConsensus(members []vegRowWithRowID, col, plot, species string) (rawSQLiteCell, *OptimizeVegConflict) {
	seen := map[string]bool{}
	var vals []string
	var ids []int64
	var chosen rawSQLiteCell
	hasVal := false
	for _, m := range members {
		c := m.cells[col]
		if c.storage == "null" {
			continue
		}
		var key, disp string
		switch c.storage {
		case "integer":
			disp = strconv.FormatInt(c.intVal, 10)
			key = "i:" + disp
		case "real":
			disp = vprocore.SourceDoubleDecimalString(c.realVal)
			key = "r:" + disp
		case "text":
			disp = string(c.bytes)
			if strings.TrimSpace(disp) == "" {
				continue
			}
			key = "t:" + disp
		case "blob":
			disp = hex.EncodeToString(c.bytes)
			key = "b:" + disp
		default:
			continue
		}
		if !hasVal {
			hasVal = true
			chosen = rawSQLiteCell{storage: c.storage, intVal: c.intVal, realVal: c.realVal, bytes: append([]byte(nil), c.bytes...)}
		}
		if !seen[key] {
			seen[key] = true
			vals = append(vals, disp)
		}
		if idCell := m.cells["ID"]; idCell.storage == "integer" {
			ids = append(ids, idCell.intVal)
		}
	}
	if !hasVal {
		return rawSQLiteCell{storage: "null"}, nil
	}
	if len(vals) > 1 {
		return rawSQLiteCell{storage: "null"}, &OptimizeVegConflict{
			PlotNumber: plot,
			Species:    species,
			Field:      col,
			Reason:     fmt.Sprintf("conflicting non-null %s values (%s)", col, strings.Join(vals, " vs ")),
			Values:     vals,
			SourceIDs:  ids,
		}
	}
	return chosen, nil
}

func resolveOptimizeVegGroup(
	gk vegGroupKey,
	members []vegRowWithRowID,
	cols []string,
	coveredCols map[string]bool,
	envLocked map[string]bool,
	auditRefs []OptimizeVegAuditRef,
	custodianAuditOverride bool,
	preview *OptimizeVegPreview,
) plannedVegConsolidation {
	survivor := members[0]
	survivorLogicalID := survivor.cells["ID"].intVal

	afterCells := make(map[string]rawSQLiteCell, len(cols))
	for k, v := range survivor.cells {
		afterCells[k] = v
	}

	mergedCovers := map[string]float64{}
	mergedHeights := map[string]float64{}
	var cappedCols []string
	var conflicts []OptimizeVegConflict
	var blockedReasons []string
	overlapping := false

	// Rule 3: Independent non-null MAX on numeric cover columns.
	for _, col := range vegCoverCols {
		if _, hasCol := survivor.cells[col]; !hasCol {
			continue
		}
		countNonNull := 0
		var maxVal float64
		for _, m := range members {
			c := m.cells[col]
			if c.storage == "null" {
				continue
			}
			var val float64
			switch c.storage {
			case "real":
				val = c.realVal
			case "integer":
				val = float64(c.intVal)
			default:
				continue
			}
			if math.IsNaN(val) || math.IsInf(val, 0) {
				continue
			}
			if countNonNull == 0 || val > maxVal {
				maxVal = val
			}
			countNonNull++
		}
		if countNonNull == 0 {
			afterCells[col] = rawSQLiteCell{storage: "null"}
			continue
		}
		if countNonNull > 1 {
			overlapping = true
		}
		finalCover := maxVal
		if finalCover >= 0 {
			if _, ok := NarrowSingleCover(finalCover); !ok {
				finalCover = 99.0
				cappedCols = append(cappedCols, col)
			}
		}
		afterCells[col] = rawSQLiteCell{storage: "real", realVal: finalCover}
		mergedCovers[col] = finalCover
	}

	// Rule 3: Independent non-null MAX on numeric height columns.
	for _, col := range vegNumericHeightCols {
		if _, hasCol := survivor.cells[col]; !hasCol {
			continue
		}
		hasVal := false
		var maxVal float64
		for _, m := range members {
			c := m.cells[col]
			if c.storage == "null" {
				continue
			}
			var val float64
			switch c.storage {
			case "real":
				val = c.realVal
			case "integer":
				val = float64(c.intVal)
			default:
				continue
			}
			if math.IsNaN(val) || math.IsInf(val, 0) {
				continue
			}
			if !hasVal || val > maxVal {
				maxVal = val
				hasVal = true
			}
		}
		if !hasVal {
			afterCells[col] = rawSQLiteCell{storage: "null"}
		} else {
			afterCells[col] = rawSQLiteCell{storage: "real", realVal: maxVal}
			mergedHeights[col] = maxVal
		}
	}

	// Rule 3: HeightB (VARCHAR) uses consensus-or-block on non-null values.
	var mergedHeightBPtr *string
	if _, hasHB := survivor.cells["HeightB"]; hasHB {
		chosenHB, conflict := resolveVegTextConsensus(members, "HeightB", gk.plot, gk.species)
		if conflict != nil {
			conflicts = append(conflicts, *conflict)
			afterCells["HeightB"] = survivor.cells["HeightB"]
		} else {
			afterCells["HeightB"] = chosenHB
			if chosenHB.storage != "null" {
				s := fmt.Sprint(auditTextForRawCell(chosenHB))
				mergedHeightBPtr = &s
			}
		}
	}

	// Rule 4: Layer, Collected, Flag, LL..Other2 (and any extra columns) use consensus-or-block.
	for _, textCol := range []string{"Layer", "Collected"} {
		if _, hasCol := survivor.cells[textCol]; !hasCol {
			continue
		}
		chosen, conflict := resolveVegTextConsensus(members, textCol, gk.plot, gk.species)
		if conflict != nil {
			conflicts = append(conflicts, *conflict)
			afterCells[textCol] = survivor.cells[textCol]
		} else {
			afterCells[textCol] = chosen
		}
	}

	if _, hasFlag := survivor.cells["Flag"]; hasFlag {
		chosen, conflict := resolveVegIntConsensus(members, "Flag", gk.plot, gk.species)
		if conflict != nil {
			conflicts = append(conflicts, *conflict)
			afterCells["Flag"] = survivor.cells["Flag"]
		} else {
			afterCells["Flag"] = chosen
		}
	}

	for _, col := range vegFirstIntCols {
		if _, hasCol := survivor.cells[col]; !hasCol {
			continue
		}
		chosen, conflict := resolveVegIntConsensus(members, col, gk.plot, gk.species)
		if conflict != nil {
			conflicts = append(conflicts, *conflict)
			afterCells[col] = survivor.cells[col]
		} else {
			afterCells[col] = chosen
		}
	}

	for _, col := range cols {
		if coveredCols[col] {
			continue
		}
		chosen, conflict := resolveVegIntConsensus(members, col, gk.plot, gk.species)
		if conflict != nil {
			conflicts = append(conflicts, *conflict)
			afterCells[col] = survivor.cells[col]
		} else {
			afterCells[col] = chosen
		}
	}

	// Rule 5: Locked plot check (Env.Flag != 0) cannot be overridden.
	if envLocked[gk.plot] {
		msg := fmt.Sprintf("plot %q is locked (Env.Flag != 0)", gk.plot)
		blockedReasons = append(blockedReasons, msg)
		conflicts = append(conflicts, OptimizeVegConflict{
			PlotNumber:   gk.plot,
			Species:      gk.species,
			Field:        "Env.Flag",
			Reason:       msg,
			SourceIDs:    []int64{survivorLogicalID},
			Overrideable: false,
		})
	}

	var retiredIDs []int64
	var deletedRowIDs []int64
	var deletedBefore []map[string]rawSQLiteCell
	oldToSurvivor := make(map[int64]int64, len(members)-1)
	for _, dup := range members[1:] {
		deletedRowIDs = append(deletedRowIDs, dup.rowID)
		deletedBefore = append(deletedBefore, dup.cells)
		dupID := dup.cells["ID"].intVal
		retiredIDs = append(retiredIDs, dupID)
		oldToSurvivor[dupID] = survivorLogicalID
		preview.OldToSurvivorIDMap[dupID] = survivorLogicalID
	}

	if len(auditRefs) > 0 && !custodianAuditOverride {
		refIDSet := map[int64]bool{}
		var refIDs []int64
		for _, ref := range auditRefs {
			if !refIDSet[ref.RetiredID] {
				refIDSet[ref.RetiredID] = true
				refIDs = append(refIDs, ref.RetiredID)
			}
		}
		slices.Sort(refIDs)
		msg := fmt.Sprintf("%d _Audit event(s) reference retired vegetation IDs %v; requires CustodianAuditOverride confirmation", len(auditRefs), refIDs)
		blockedReasons = append(blockedReasons, msg)
		conflicts = append(conflicts, OptimizeVegConflict{
			PlotNumber:   gk.plot,
			Species:      gk.species,
			Field:        "Audit.ID",
			Reason:       msg,
			SourceIDs:    refIDs,
			Overrideable: true,
		})
	}

	var fieldDiffs []OptimizeVegFieldDiff
	for _, col := range cols {
		if col == "PlotNumber" || col == "Species" {
			continue
		}
		changed := !rawCellsEqual(survivor.cells[col], afterCells[col])
		differsAcross := false
		for _, dup := range members[1:] {
			if !rawCellsEqual(survivor.cells[col], dup.cells[col]) {
				differsAcross = true
				break
			}
		}
		if !changed && !differsAcross {
			continue
		}
		beforeMap := make(map[int64]*string, len(members))
		for _, m := range members {
			beforeMap[m.cells["ID"].intVal] = strPtrFromAuditVal(auditTextForRawCell(m.cells[col]))
		}
		fieldDiffs = append(fieldDiffs, OptimizeVegFieldDiff{
			Field:    col,
			Proposed: strPtrFromAuditVal(auditTextForRawCell(afterCells[col])),
			Before:   beforeMap,
		})
	}

	blocked := len(conflicts) > 0 || len(blockedReasons) > 0
	if blocked && len(blockedReasons) == 0 && len(conflicts) > 0 {
		for _, c := range conflicts {
			blockedReasons = append(blockedReasons, c.Reason)
		}
	}

	grp := OptimizeVegGroup{
		PlotNumber:                gk.plot,
		Species:                   gk.species,
		SourceRowCount:            len(members),
		SurvivorID:                survivorLogicalID,
		RetiredIDs:                retiredIDs,
		OldToSurvivorIDMap:        oldToSurvivor,
		HasOverlappingLayerCovers: overlapping,
		CappedCoverColumns:        cappedCols,
		MergedCovers:              mergedCovers,
		MergedHeights:             mergedHeights,
		MergedHeightB:             mergedHeightBPtr,
		FieldDiffs:                fieldDiffs,
		Conflicts:                 conflicts,
		AuditReferences:           auditRefs,
		Blocked:                   blocked,
		BlockedReasons:            blockedReasons,
	}
	preview.Groups = append(preview.Groups, grp)
	preview.DuplicateSpeciesCount++
	preview.RowsToConsolidate += len(members) - 1
	preview.AfterRowCount -= len(members) - 1
	if overlapping {
		preview.OverlappingGroupCount++
	}
	preview.CappedCoverCount += len(cappedCols)
	if blocked {
		preview.BlockedGroupCount++
		preview.HasBlockingConflicts = true
		preview.Conflicts = append(preview.Conflicts, conflicts...)
	}
	if len(auditRefs) > 0 {
		preview.AuditReferences = append(preview.AuditReferences, auditRefs...)
	}

	return plannedVegConsolidation{
		group:          grp,
		survivorRowID:  survivor.rowID,
		deletedRowIDs:  deletedRowIDs,
		deletedPhysIDs: retiredIDs,
		survivorBefore: survivor.cells,
		survivorAfter:  afterCells,
		deletedBefore:  deletedBefore,
	}
}
