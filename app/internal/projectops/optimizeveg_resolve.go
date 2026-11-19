package projectops

import (
	"encoding/hex"
	"fmt"
	"math"
	"slices"
	"strconv"
	"strings"

	"github.com/boostao/vpro/app/internal/sqlutil"

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

type invalidVegNumericCell struct {
	sourceID  int64
	hasID     bool
	display   string
	violation string
}

func memberSourceID(m vegRowWithRowID) (int64, bool) {
	if idCell, ok := m.cells["ID"]; ok && idCell.storage == "integer" {
		return idCell.intVal, true
	}
	if m.rowID != 0 {
		return m.rowID, true
	}
	return 0, false
}

func isNonFiniteTextToken(raw string) bool {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "nan", "+nan", "-nan", "inf", "+inf", "-inf", "infinity", "+infinity", "-infinity":
		return true
	default:
		return false
	}
}

func groupHasVegColumn(members []vegRowWithRowID, col string) bool {
	for _, m := range members {
		if _, ok := m.cells[col]; ok {
			return true
		}
	}
	return false
}

func formatMemberIDTag(id int64, hasID bool) string {
	if !hasID {
		return ""
	}
	return fmt.Sprintf(" (ID %d)", id)
}

func validateMemberCoverCell(col string, m vegRowWithRowID) (float64, bool, *invalidVegNumericCell) {
	c, exists := m.cells[col]
	if !exists || c.storage == "" || c.storage == "null" {
		return 0, false, nil
	}
	srcID, hasID := memberSourceID(m)
	idTag := formatMemberIDTag(srcID, hasID)

	switch c.storage {
	case "real", "integer":
		var val float64
		var disp string
		if c.storage == "real" {
			val = c.realVal
			disp = strconv.FormatFloat(val, 'g', -1, 64)
		} else {
			val = float64(c.intVal)
			disp = strconv.FormatInt(c.intVal, 10)
		}
		if math.IsNaN(val) || math.IsInf(val, 0) {
			return 0, true, &invalidVegNumericCell{
				sourceID:  srcID,
				hasID:     hasID,
				display:   disp,
				violation: fmt.Sprintf("non-finite %s cover %s%s", col, disp, idTag),
			}
		}
		if val < 0 {
			return 0, true, &invalidVegNumericCell{
				sourceID:  srcID,
				hasID:     hasID,
				display:   disp,
				violation: fmt.Sprintf("negative %s cover %s%s", col, disp, idTag),
			}
		}
		if math.Abs(val) > math.MaxFloat32 {
			return 0, true, &invalidVegNumericCell{
				sourceID:  srcID,
				hasID:     hasID,
				display:   disp,
				violation: fmt.Sprintf("out-of-bounds %s cover %s (outside supported numeric range)%s", col, disp, idTag),
			}
		}
		narrowed, ok := sqlutil.NarrowSingleCover(val)
		if !ok {
			narrowedDisp := strconv.FormatFloat(float64(narrowed), 'g', -1, 32)
			return 0, true, &invalidVegNumericCell{
				sourceID:  srcID,
				hasID:     hasID,
				display:   disp,
				violation: fmt.Sprintf("out-of-bounds %s cover %s (rounded cover %s%% reaches 100%%)%s", col, disp, narrowedDisp, idTag),
			}
		}
		if narrowed == 0 {
			narrowed = 0
		}
		return float64(narrowed), true, nil

	case "text":
		rawText := string(c.bytes)
		disp := fmt.Sprintf("%q", rawText)
		kind := "non-numeric"
		if isNonFiniteTextToken(rawText) {
			kind = "non-numeric/non-finite"
		}
		return 0, true, &invalidVegNumericCell{
			sourceID:  srcID,
			hasID:     hasID,
			display:   disp,
			violation: fmt.Sprintf("%s %s cover %s%s", kind, col, disp, idTag),
		}

	case "blob":
		disp := "0x" + hex.EncodeToString(c.bytes)
		return 0, true, &invalidVegNumericCell{
			sourceID:  srcID,
			hasID:     hasID,
			display:   disp,
			violation: fmt.Sprintf("non-numeric %s cover blob %s%s", col, disp, idTag),
		}

	default:
		disp := fmt.Sprintf("<%s>", c.storage)
		return 0, true, &invalidVegNumericCell{
			sourceID:  srcID,
			hasID:     hasID,
			display:   disp,
			violation: fmt.Sprintf("non-numeric %s cover %s%s", col, disp, idTag),
		}
	}
}

func validateMemberHeightCell(col string, m vegRowWithRowID) (float64, bool, *invalidVegNumericCell) {
	c, exists := m.cells[col]
	if !exists || c.storage == "" || c.storage == "null" {
		return 0, false, nil
	}
	srcID, hasID := memberSourceID(m)
	idTag := formatMemberIDTag(srcID, hasID)

	switch c.storage {
	case "real", "integer":
		var val float64
		var disp string
		if c.storage == "real" {
			val = c.realVal
			disp = strconv.FormatFloat(val, 'g', -1, 64)
		} else {
			val = float64(c.intVal)
			disp = strconv.FormatInt(c.intVal, 10)
		}
		if math.IsNaN(val) || math.IsInf(val, 0) {
			return 0, true, &invalidVegNumericCell{
				sourceID:  srcID,
				hasID:     hasID,
				display:   disp,
				violation: fmt.Sprintf("non-finite %s height %s%s", col, disp, idTag),
			}
		}
		if val < 0 {
			return 0, true, &invalidVegNumericCell{
				sourceID:  srcID,
				hasID:     hasID,
				display:   disp,
				violation: fmt.Sprintf("negative %s height %s%s", col, disp, idTag),
			}
		}
		if math.Abs(val) > math.MaxFloat32 || math.IsInf(float64(float32(val)), 0) {
			return 0, true, &invalidVegNumericCell{
				sourceID:  srcID,
				hasID:     hasID,
				display:   disp,
				violation: fmt.Sprintf("out-of-bounds %s height %s (outside supported numeric range)%s", col, disp, idTag),
			}
		}
		if val == 0 {
			val = 0
		}
		return val, true, nil

	case "text":
		rawText := string(c.bytes)
		disp := fmt.Sprintf("%q", rawText)
		kind := "non-numeric"
		if isNonFiniteTextToken(rawText) {
			kind = "non-numeric/non-finite"
		}
		return 0, true, &invalidVegNumericCell{
			sourceID:  srcID,
			hasID:     hasID,
			display:   disp,
			violation: fmt.Sprintf("%s %s height %s%s", kind, col, disp, idTag),
		}

	case "blob":
		disp := "0x" + hex.EncodeToString(c.bytes)
		return 0, true, &invalidVegNumericCell{
			sourceID:  srcID,
			hasID:     hasID,
			display:   disp,
			violation: fmt.Sprintf("non-numeric %s height blob %s%s", col, disp, idTag),
		}

	default:
		disp := fmt.Sprintf("<%s>", c.storage)
		return 0, true, &invalidVegNumericCell{
			sourceID:  srcID,
			hasID:     hasID,
			display:   disp,
			violation: fmt.Sprintf("non-numeric %s height %s%s", col, disp, idTag),
		}
	}
}

func buildInvalidNumericConflict(
	gk vegGroupKey,
	col string,
	invalids []invalidVegNumericCell,
) OptimizeVegConflict {
	reasons := make([]string, 0, len(invalids))
	var badVals []string
	seenVals := map[string]bool{}
	var badIDs []int64
	seenIDs := map[int64]bool{}
	for _, inv := range invalids {
		reasons = append(reasons, inv.violation)
		if !seenVals[inv.display] {
			seenVals[inv.display] = true
			badVals = append(badVals, inv.display)
		}
		if inv.hasID && !seenIDs[inv.sourceID] {
			seenIDs[inv.sourceID] = true
			badIDs = append(badIDs, inv.sourceID)
		}
	}
	msg := fmt.Sprintf("%s cannot be consolidated", strings.Join(reasons, "; "))
	return OptimizeVegConflict{
		PlotNumber:   gk.plot,
		Species:      gk.species,
		Field:        col,
		Reason:       msg,
		Values:       badVals,
		SourceIDs:    badIDs,
		Overrideable: false,
	}
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
	if len(members) == 0 {
		return plannedVegConsolidation{}
	}
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

	// Rule 3: Validate EVERY source row's numeric cover cell BEFORE computing non-null MAX.
	for _, col := range vegCoverCols {
		if !groupHasVegColumn(members, col) {
			continue
		}
		countNonNull := 0
		validCount := 0
		var maxVal float64
		var invalidCells []invalidVegNumericCell
		for _, m := range members {
			narrowed, present, invalid := validateMemberCoverCell(col, m)
			if !present {
				continue
			}
			countNonNull++
			if invalid != nil {
				invalidCells = append(invalidCells, *invalid)
				continue
			}
			if validCount == 0 || narrowed > maxVal {
				maxVal = narrowed
			}
			validCount++
		}
		if countNonNull > 1 {
			overlapping = true
		}
		if len(invalidCells) > 0 {
			conflict := buildInvalidNumericConflict(gk, col, invalidCells)
			blockedReasons = append(blockedReasons, conflict.Reason)
			conflicts = append(conflicts, conflict)
			if survCell, ok := survivor.cells[col]; ok {
				afterCells[col] = survCell
			} else {
				afterCells[col] = rawSQLiteCell{storage: "null"}
			}
			continue
		}
		if validCount == 0 {
			afterCells[col] = rawSQLiteCell{storage: "null"}
			continue
		}
		afterCells[col] = rawSQLiteCell{storage: "real", realVal: maxVal}
		mergedCovers[col] = maxVal
	}

	// Rule 3: Validate EVERY source row's numeric height cell BEFORE computing non-null MAX.
	for _, col := range vegNumericHeightCols {
		if !groupHasVegColumn(members, col) {
			continue
		}
		hasVal := false
		var maxVal float64
		var invalidCells []invalidVegNumericCell
		for _, m := range members {
			val, present, invalid := validateMemberHeightCell(col, m)
			if !present {
				continue
			}
			if invalid != nil {
				invalidCells = append(invalidCells, *invalid)
				continue
			}
			if !hasVal || val > maxVal {
				maxVal = val
				hasVal = true
			}
		}
		if len(invalidCells) > 0 {
			conflict := buildInvalidNumericConflict(gk, col, invalidCells)
			blockedReasons = append(blockedReasons, conflict.Reason)
			conflicts = append(conflicts, conflict)
			if survCell, ok := survivor.cells[col]; ok {
				afterCells[col] = survCell
			} else {
				afterCells[col] = rawSQLiteCell{storage: "null"}
			}
			continue
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
	if blocked {
		for _, c := range conflicts {
			if !slices.Contains(blockedReasons, c.Reason) {
				blockedReasons = append(blockedReasons, c.Reason)
			}
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
