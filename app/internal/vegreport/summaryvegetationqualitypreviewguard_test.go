package vegreport

import (
	"context"
	"reflect"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestSummaryVegetationQualityEnforceFiltersQualifiedPreviewAndRejectsMalformed(t *testing.T) {
	service, state := summaryVegetationServiceFixture(t, false)
	baseline, err := service.Preview(context.Background(), state.ContextID, 1, 6)
	if err != nil {
		t.Fatal(err)
	}
	owner := service.contexts.Projects.Sqlite
	vprotest.MutateContextFixture(t, owner.Attachments["VLists"], `DELETE FROM USysTableOfLists WHERE ListName IN ('DataQuality', 'BEC_Use');
		INSERT INTO USysTableOfLists(ListName, ItemOrder, Item) VALUES
			('DataQuality', 1, 'Poor'),
			('DataQuality', 2, 'Fair'),
			('DataQuality', 3, 'Good'),
			('DataQuality', 4, 'Excellent')`)
	vprotest.MutateContextFixture(t, owner.Attachments["project"], `
		DELETE FROM `+vprocore.QuoteHeaderIdentifier(state.ActiveProject+"_Env")+`;
		DELETE FROM `+vprocore.QuoteHeaderIdentifier(state.ActiveProject+"_Admin")+`;
		INSERT INTO `+vprocore.QuoteHeaderIdentifier(state.ActiveProject+"_Env")+`(PlotNumber) VALUES('P1'),('P2'),('P3');
		INSERT INTO `+vprocore.QuoteHeaderIdentifier(state.ActiveProject+"_Admin")+`(Plot, SitePlotQuality, VegPlotQuality, SoilPlotQuality, BEC_Use) VALUES
			('P1', 'Good', 'Good', 'Good', 'True'),
			('P2', 'Good', 'Good', 'Good', 'True'),
			('P3', 'Poor', 'Good', 'Good', 'True')`)
	if err := service.contexts.Projects.Preferences.Update("ReportOptions", map[string]any{
		"DataQualityFilterEnforce": true,
		"DataQualityFilterSite":    "Good",
	}); err != nil {
		t.Fatal(err)
	}
	got, err := service.Preview(context.Background(), state.ContextID, 1, 6)
	if err != nil || got.Quality == nil || !got.Quality.Enforced || got.Quality.Retained != 3 || len(got.Units) != 1 || got.Units[0].Code != "A" {
		t.Fatalf("expected enforced QC to filter out P3/P5/P9/P6 and keep P1/P2 in unit A, got quality=%+v units=%+v err=%v", got.Quality, got.Units, err)
	}
	if err := service.contexts.Projects.Preferences.Update("ReportOptions", map[string]any{"DataQualityFilterEnforce": "malformed"}); err != nil {
		t.Fatal(err)
	}
	if bad, err := service.Preview(context.Background(), state.ContextID, 1, 6); err == nil || !reflect.DeepEqual(bad, SummaryVegetationPreview{}) {
		t.Fatal("malformed quality preferences silently defaulted", bad, err)
	}
	if err := service.contexts.Projects.Preferences.Update("ReportOptions", map[string]any{"DataQualityFilterEnforce": false}); err != nil {
		t.Fatal(err)
	}
	recovered, err := service.Preview(context.Background(), state.ContextID, 1, 6)
	if err != nil || !reflect.DeepEqual(baseline, recovered) {
		t.Fatal("corrected inactive quality changed original preview", recovered, err)
	}
}
