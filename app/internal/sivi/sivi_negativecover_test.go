package sivi

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/sourceform"
	"github.com/boostao/vpro/app/internal/sourceform/sftest"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestSIVICoverAndCombinedAndCreationRejectNegativeCoverWrites(t *testing.T) {
	contexts, state, db, original, heights := sftest.SiviWriteFixture(t, false, 3)

	coverSvc, err := NewSIVICoverService(contexts)
	if err != nil {
		t.Fatal(err)
	}
	negEdit := sourceform.SiviHeightEdit{
		RowID:    heights[0].RowID,
		Form:     "SubVegA-SIVI_BC",
		Column:   "Cover1",
		Expected: vprotest.SiviReal(0),
		Value:    vprotest.SiviReal(-0.5),
	}
	if _, err := coverSvc.SaveReviewed(context.Background(), state.ContextID, "108050", false, siviCoverRequestJSON(t, original, negEdit)); err == nil || !strings.Contains(err.Error(), ">= 0") {
		t.Fatalf("expected SIVICoverService to reject negative cover write, got %v", err)
	}

	combinedSvc, err := NewSIVICombinedService(contexts)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := combinedSvc.SaveReviewed(context.Background(), state.ContextID, "108050", false, siviCoverRequestJSON(t, original, negEdit)); err == nil || !strings.Contains(err.Error(), ">= 0") {
		t.Fatalf("expected SIVICombinedService to reject negative cover write, got %v", err)
	}

	// Verify unchanged historical negative cover is still tolerated inside SIVICombinedService.SaveReviewed.
	if _, err := db.Exec(`UPDATE Sample_Veg SET Cover2 = -1 WHERE rowid = ?`, heights[0].RowID); err != nil {
		t.Fatal(err)
	}
	origHist, err := combinedSvc.GetOriginal(context.Background(), state.ContextID, "108050", false)
	if err != nil {
		t.Fatal(err)
	}
	histPayload, err := json.Marshal(SIVICombinedWrite{
		Original: origHist,
		Edits: []SIVICoverEdit{
			{RowID: heights[0].RowID, Form: "SubVegA-SIVI_BC", Column: "Cover2", Expected: vprotest.SiviReal(-1), Value: vprotest.SiviReal(-1)},
			{RowID: heights[0].RowID, Form: "SubVegA-SIVI_BC", Column: "Cover1", Expected: vprotest.SiviReal(0), Value: vprotest.SiviReal(2)},
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := combinedSvc.SaveReviewed(context.Background(), state.ContextID, "108050", false, string(histPayload)); err != nil {
		t.Fatalf("expected unchanged historical negative cover to remain tolerated, got %v", err)
	}

	// Creation service rejects negative cover writes.
	_, crCtx, crState, _, _ := siviSpeciesServiceFixture(t, false, 3)
	createSvc, err := NewSIVICreationService(crCtx)
	if err != nil {
		t.Fatal(err)
	}
	negVal := -2.0
	createRaw, err := json.Marshal(sourceform.SiviCreationRequest{
		RequestID: "00000000-0000-4000-8000-000000000098",
		ContextID: crState.ContextID,
		Project:   "Sample",
		Plot:      "108050",
		Form:      "SubVegA-SIVI_BC",
		Species:   "A",
		Covers:    []sourceform.SiviCreationCover{{Column: "Cover1", Value: vprocore.ProjectMetadataCell{Storage: "real", Real: &negVal}}},
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := createSvc.Create(context.Background(), crState.ContextID, string(createRaw)); err == nil || !strings.Contains(err.Error(), ">= 0") {
		t.Fatalf("expected SIVICreationService.Create to reject negative cover, got %v", err)
	}
}
