package sourceform

import (
	"context"
	"fmt"

	"github.com/boostao/vpro/app/internal/vprocore"
)

const SiviCoverHistoryTable = "__VPRO_SIVICoverHistory"
const siviCoverHistorySQL = `CREATE TABLE "__VPRO_SIVICoverHistory"(ID INTEGER PRIMARY KEY,Created TEXT NOT NULL,Proposal TEXT NOT NULL,Restored TEXT)`

func SiviCoverWritePolicy() SiviVegetationWritePolicy {
	return SiviVegetationWritePolicy{"cover", SiviCoverHistoryTable, siviCoverHistorySQL,
		[]string{"Cover1", "Cover2", "Cover3", "TotalA", "Cover4", "Cover5", "Cover5a", "Cover5b", "Cover5c", "TotalB",
			"Cover6", "Cover7", "Cover8", "Cover9"}, PlanSIVICoverEdits}
}

func WriteSIVICovers(s *vprocore.ContextService, ctx context.Context, contextID, plot string, extended bool, original []SiviVegetationProjection, edits []SiviHeightEdit) (*siviHeightWriteResult, error) {
	return WriteSIVIVegetationCells(s, ctx, contextID, plot, extended, original, edits, SiviCoverWritePolicy())
}

func RestoreSIVICovers(s *vprocore.ContextService, ctx context.Context, contextID, plot, historyID string, action vprocore.AuditRestoreAction) (*vprocore.AuditRestoreResult, error) {
	return RestoreSIVIVegetationCells(s, ctx, contextID, plot, historyID, action, SiviCoverWritePolicy())
}

// This private plan does not authorize writes or widen the height service.
func PlanSIVICoverEdits(ctx context.Context, plot string, extended bool, veg vprocore.ProjectMetadataTable, edits []SiviHeightEdit) ([]SiviHeightAssignment, error) {
	return PlanSIVIChildEdits(ctx, plot, extended, veg, edits, "cover",
		func(group int, column string) bool {
			switch group {
			case 0:
				switch column {
				case "Cover1", "Cover2", "Cover3", "TotalA", "Cover4", "Cover5", "TotalB":
					return true
				case "Cover5a", "Cover5b", "Cover5c":
					return extended
				}
			case 1:
				return column == "Cover6"
			case 2:
				return column == "Cover7" || column == "Cover8" || column == "Cover9"
			}
			return false
		}, validateSIVICoverCell)
}

func validateSIVICoverCell(column string, cell vprocore.ProjectMetadataCell) error {
	if err := ValidateSIVIChildSingle(column, cell); err != nil {
		return err
	}
	// Covers are Access SINGLE: narrow to float32 BEFORE the [0, 100) check (AGENTS.md §3.3), so
	// 99.999996 is accepted while 99.999999 (which narrows to 100) is rejected (ENG-GO-002).
	// ValidateSIVIChildSingle above already restricts covers to NULL or real storage.
	if err := vprocore.ValidateSingleCoverChange("Veg."+column, nil, cell.Real); err != nil {
		return fmt.Errorf("Veg.%s requires a value >= 0 and less than 100 or NULL, matching the SIVI source control", column)
	}
	return nil
}
