//go:build !vpro_headless

package interchange_test

import (
	"context"
	"os"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/interchange"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestVenus50AccessMDBTemplateInspection(t *testing.T) {
	// Test real Jet .mdb VENUS 5.0 template via internal/accessreader when sibling asset is present
	const realVenusMDB = "/home/bruno/Work/VPRO_ACCESS/VPro64/Templates/TemplateVENUS5.mdb"
	if _, statErr := os.Stat(realVenusMDB); statErr != nil {
		t.Skip("sibling TemplateVENUS5.mdb not present")
	}
	service, state := vprotest.ReportServiceFixture(t, false)
	mdbInsp, mdbErr := interchange.InspectVenusSource(service, context.Background(), state.ContextID, realVenusMDB)
	if mdbErr != nil {
		t.Fatalf("InspectVenusSource on real TemplateVENUS5.mdb failed: %v", mdbErr)
	}
	if mdbInsp.SourceFormat != "mdb" || !strings.HasPrefix(mdbInsp.VenusVersion, "5") {
		t.Fatalf("unexpected TemplateVENUS5.mdb inspection metadata: %+v", mdbInsp)
	}
}
