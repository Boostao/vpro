package spatial_test

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/spatial"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestWave2_WesternLongitudeNeverFlipsPositiveAndUnifiedBounds(t *testing.T) {
	// S6.2: Unified bounds [45.0..85.0] N, [-170.0..-100.0] W across vprocore and spatial.
	lat, lon, flipped, inBounds := spatial.NormalizeBCWesternCoordinates(45.5, 165.0)
	if !flipped || !inBounds || lat != 45.5 || lon != -165.0 {
		t.Fatalf("expected unified western bounds normalization (45.5, 165.0 -> -165.0), got lat=%v lon=%v flipped=%v inBounds=%v",
			lat, lon, flipped, inBounds)
	}
	lat2, lon2, flipped2, inBounds2 := vprocore.NormalizeWesternBCCoordinates(52.3, -125.4)
	if flipped2 || !inBounds2 || lat2 != 52.3 || lon2 != -125.4 {
		t.Fatalf("expected already-negative -125.4 preserved in bounds, got lat=%v lon=%v flipped=%v inBounds=%v",
			lat2, lon2, flipped2, inBounds2)
	}

	// S6.1: Already-negative stored longitude (-125.4) never flips positive across PlotLocation,
	// GoogleEarthReview, and TwoPageGoogleEarthService.
	negCell := vprocore.ProjectMetadataCell{Storage: "real", Real: &lon2}
	dispNeg, err := vprocore.NegateLocationLongitude(negCell)
	if err != nil || dispNeg.Real == nil || *dispNeg.Real != -125.4 {
		t.Fatalf("expected already-negative -125.4 preserved by NegateLocationLongitude, got %+v (%v)", dispNeg, err)
	}
	posLon := 125.4
	posCell := vprocore.ProjectMetadataCell{Storage: "real", Real: &posLon}
	dispPos, err := vprocore.NegateLocationLongitude(posCell)
	if err != nil || dispPos.Real == nil || *dispPos.Real != -125.4 {
		t.Fatalf("expected positive 125.4 negated to -125.4, got %+v (%v)", dispPos, err)
	}

	// TwoPageGoogleEarthService accepts already-negative -125.4 normalized by 3D Geospatial Workbench.
	contexts, state := vprotest.ContextServiceFixture(t)
	vprotest.MutateContextFixture(t, state.ProjectPath, `
		UPDATE Sample_Env SET Latitude = 52.3, Longitude = -125.4 WHERE PlotNumber = '108050';
	`)
	svc, err := spatial.NewTwoPageGoogleEarthService(contexts)
	if err != nil {
		t.Fatal(err)
	}
	reqJSON, _ := json.Marshal(spatial.GoogleEarthKMLRequest{
		DescriptionField: "PlotRepresenting",
		Title:            "Western Negative Lon",
	})
	review, err := svc.GetReview(context.Background(), state.ContextID, "108050", "FS882-8x6XL", string(reqJSON))
	if err != nil {
		t.Fatalf("TwoPageGoogleEarthService rejected already-negative -125.4: %v", err)
	}
	if !strings.Contains(review.KML, "<coordinates>-125.4,52.3,0</coordinates>") {
		t.Fatalf("expected <coordinates>-125.4,52.3,0</coordinates> in KML, got:\n%s", review.KML)
	}
}
