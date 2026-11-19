package sourceform

import (
	"context"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore"
)

func TestW4PlanSIVICreationMissingCanonicalColumnsMessageSpacing(t *testing.T) {
	incompleteVeg := vprocore.ProjectMetadataTable{
		Columns: []vprocore.ProjectMetadataColumn{
			{Name: "PlotNumber", DeclaredType: "TEXT"},
			{Name: "Species", DeclaredType: "TEXT"},
		},
	}
	req := SiviCreationRequest{
		RequestID: "r1",
		ContextID: "c1",
		Project:   "Sample",
		Plot:      "00337",
		Form:      "SubVegC-SIVI",
		Species:   "ABIEAMA",
	}
	_, _, err := PlanSIVICreation(context.Background(), req, incompleteVeg, 1)
	if err == nil {
		t.Fatal("expected error when canonical _Veg columns are missing")
	}
	if !strings.Contains(err.Error(), "all 44 canonical fields") {
		t.Fatalf("expected spaced 'all 44 canonical fields' message (UX-VEG-006), got: %v", err)
	}
	if strings.Contains(err.Error(), "all44") {
		t.Fatalf("unexpected unspaced 'all44' typo in error: %v", err)
	}
}
