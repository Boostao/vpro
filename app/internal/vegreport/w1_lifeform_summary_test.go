package vegreport

import (
	"context"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

// UX-REPORTS-001: duplicate (Code, Lifeform) catalogue rows count once and
// VUser.USysUserSpp species contribute their configured LifeForm.
func TestW1LifeformSummaryDedupesDefinitionsAndIncludesPersonalSpecies(t *testing.T) {
	veg, su, _, catalogue := lifeformFixture()
	veg.Rows = append(veg.Rows, vprocore.ProjectMetadataRow{RowID: "4", Cells: append([]vprocore.ProjectMetadataCell{
		vprotest.MetadataText("P"), vprotest.MetadataText("ABIE_RK"), vprotest.MetadataInteger("5")},
		make([]vprocore.ProjectMetadataCell, len(veg.Columns)-3)...)})
	for i := 3; i < len(veg.Columns); i++ {
		veg.Rows[3].Cells[i] = vprocore.ProjectMetadataCell{Storage: "null"}
	}
	master := lifeformTable([]string{"Code", "Lifeform", "Codetype"},
		[]vprocore.ProjectMetadataCell{vprotest.MetadataText("A"), vprotest.MetadataInteger("1"), vprotest.MetadataText("U")},
		[]vprocore.ProjectMetadataCell{vprotest.MetadataText("A"), vprotest.MetadataInteger("1"), vprotest.MetadataText("XX")},
		[]vprocore.ProjectMetadataCell{vprotest.MetadataText("B"), vprotest.MetadataInteger("2"), vprotest.MetadataText("U")})
	personal := lifeformTable([]string{"Code", "LifeForm", "Codetype"},
		[]vprocore.ProjectMetadataCell{vprotest.MetadataText("ABIE_RK"), vprotest.MetadataInteger("1"), vprotest.MetadataText("U")})
	species, err := mergeLifeformSpeciesSources(master, personal)
	if err != nil {
		t.Fatal(err)
	}
	if len(species.Rows) != 4 || species.Rows[3].RowID != "-1" {
		t.Fatalf("personal species not merged with a distinct numeric row id: %+v", species.Rows)
	}
	report, err := planLifeformSummary(context.Background(), "P", "S", veg, su, species, catalogue)
	if err != nil {
		t.Fatal(err)
	}
	counts := map[string]int{}
	for _, entry := range report.Entries {
		if entry.Lifeform == 1 {
			counts[entry.Species]++
		}
	}
	// Plot P has 4 SU memberships; each species row appears once per membership.
	if counts["A"] != 4 || counts["ABIE_RK"] != 4 {
		t.Fatalf("lifeform 1 entries per species = %v, want A:4 ABIE_RK:4", counts)
	}
	if _, err := mergeLifeformSpeciesSources(master, vprocore.ProjectMetadataTable{}); err != nil {
		t.Fatalf("missing VUser table must be optional: %v", err)
	}
}
