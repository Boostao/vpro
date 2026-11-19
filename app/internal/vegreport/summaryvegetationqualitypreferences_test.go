package vegreport

import (
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

import (
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func summaryQualityFixture(t *testing.T) *vprocore.DesktopConfig {
	t.Helper()
	data, config := vprotest.ConfigFixture(t)
	store, err := vprocore.OpenDesktopConfig(data, config)
	if err != nil {
		t.Fatal(err)
	}
	fields := map[string]any{
		"DataQualityFilterEnforce": false, "DataQualityFilterSite": "Poor", "DataQualityFilterVeg": "Poor",
		"DataQualityFilterSoil": "Poor", "DataQualityFilterBECUseLV": "True",
		"DataQualityFilterSiteNull": true, "DataQualityFilterVegNull": "True",
		"DataQualityFilterSoilNull": "True", "DataQualityFilterBECUse": 1,
	}
	if err := store.Update("ReportOptions", fields); err != nil {
		t.Fatal(err)
	}
	return store
}

func TestSummaryQualityPrivateDefaultsOmissionSharedCASAndReopen(t *testing.T) {
	store := summaryQualityFixture(t)
	ctx := context.Background()
	expected := summaryVegetationQualityPreferenceValues{
		SiteMinimum: "Poor", VegMinimum: "Poor", SoilMinimum: "Poor", BECMinimum: "",
		SiteIncludeNulls: true, VegIncludeNulls: true, SoilIncludeNulls: true, BECIncludeNulls: true,
	}
	read, err := ReadSummaryVegetationQualityPreferences(store, ctx)
	if err != nil || read != expected {
		t.Fatal(read, err)
	}
	before, err := os.ReadFile(store.Path)
	if err != nil {
		t.Fatal(err)
	}
	if result, err := CompareAndSetSummaryVegetationQualityPreferences(store, ctx, expected, expected); err != nil || result != (vprocore.ReportPreferenceUpdate{}) {
		t.Fatal(result, err)
	}
	after, err := os.ReadFile(store.Path)
	if err != nil || !bytes.Equal(before, after) {
		t.Fatal("no-op rewrote legacy storage", err)
	}
	original, err := store.Snapshot()
	if err != nil {
		t.Fatal(err)
	}
	proposed := expected
	proposed.SiteMinimum = "  literal nonmember longer than 15  "
	proposed.BECMinimum = "3"
	proposed.BECIncludeNulls = false
	result, err := CompareAndSetSummaryVegetationQualityPreferences(store, ctx, expected, proposed)
	if err != nil || !result.Committed || !result.Changed {
		t.Fatal(result, err)
	}
	reopened, err := vprocore.OpenDesktopConfig(filepath.Dir(filepath.Dir(store.Path)), filepath.Dir(store.Path))
	if err != nil {
		t.Fatal(err)
	}
	read, err = ReadSummaryVegetationQualityPreferences(reopened, ctx)
	if err != nil || read != proposed {
		t.Fatal("independent reopen changed literal values", read, err)
	}
	persisted, err := reopened.Snapshot()
	if err != nil {
		t.Fatal(err)
	}
	fields := original["ReportOptions"].(map[string]any)
	fields["DataQualityFilterSite"] = proposed.SiteMinimum
	fields["DataQualityFilterBECUseLV"] = "3"
	fields["DataQualityFilterBECUse"] = false
	if !reflect.DeepEqual(original, persisted) {
		t.Fatal("unrelated/legacy storage changed", original, persisted)
	}
	if result, err := CompareAndSetSummaryVegetationQualityPreferences(store, ctx, expected, proposed); err == nil || result.Committed || !strings.Contains(err.Error(), "changed") {
		t.Fatal("shared expected values authorized stale Save", result, err)
	}
	for _, invalidBEC := range []string{"True", "False", " true ", "false"} {
		bad := proposed
		bad.BECMinimum = invalidBEC
		if res, err := CompareAndSetSummaryVegetationQualityPreferences(store, ctx, proposed, bad); err == nil || res.Committed {
			t.Fatalf("expected boolean BECMinimum placeholder %q to be rejected, got res=%+v err=%v", invalidBEC, res, err)
		}
	}
}

func TestSummaryQualityPrivateBooleanStorageAndInvalidTypes(t *testing.T) {
	for _, key := range []string{"DataQualityFilterEnforce", "DataQualityFilterSiteNull", "DataQualityFilterVegNull", "DataQualityFilterSoilNull", "DataQualityFilterBECUse"} {
		for _, test := range []struct {
			value any
			want  bool
			valid bool
		}{
			{true, true, true}, {false, false, true}, {-1, true, true}, {0, false, true},
			{1, true, key == "DataQualityFilterBECUse"},
			{"True", true, key != "DataQualityFilterEnforce"}, {"False", false, key != "DataQualityFilterEnforce"},
			{"true", false, false}, {" True ", false, false}, {nil, false, false},
			{2, false, false}, {1.0, false, false}, {[]any{1}, false, false}, {map[string]any{"a": 1}, false, false},
		} {
			value, err := summaryVegetationQualityPreferenceOption(vprocore.ConfigValues{"ReportOptions": map[string]any{key: test.value}}, key)
			if (err == nil) != test.valid || test.valid && value != test.want {
				t.Fatal(key, test, value, err)
			}
		}
	}
	if value, err := summaryVegetationQualityPreferenceOption(vprocore.ConfigValues{}, "LVGroupBy"); value != nil || err == nil {
		t.Fatal(value, err)
	}
}

func TestSummaryQualityPrivateRefusalRollbackCancellationAndCommittedReceipt(t *testing.T) {
	store := summaryQualityFixture(t)
	expected, err := ReadSummaryVegetationQualityPreferences(store, context.Background())
	if err != nil {
		t.Fatal(err)
	}
	for _, text := range []string{"bad\x00new", string([]byte{0xff})} {
		proposed := expected
		proposed.VegMinimum = text
		if result, err := CompareAndSetSummaryVegetationQualityPreferences(store, context.Background(), expected, proposed); err == nil || result.Committed {
			t.Fatal(result, err)
		}
	}
	proposed := expected
	proposed.Enforce = true
	resEnforce, err := CompareAndSetSummaryVegetationQualityPreferences(store, context.Background(), expected, proposed)
	if err != nil || !resEnforce.Committed || !resEnforce.Changed {
		t.Fatal("unlock Enforce failed", resEnforce, err)
	}
	resRevert, err := CompareAndSetSummaryVegetationQualityPreferences(store, context.Background(), proposed, expected)
	if err != nil || !resRevert.Committed || !resRevert.Changed {
		t.Fatal("revert Enforce failed", resRevert, err)
	}
	proposed = expected
	proposed.VegIncludeNulls = false
	before, err := os.ReadFile(store.Path)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if result, err := CompareAndSetSummaryVegetationQualityPreferences(store, ctx, expected, proposed); !errors.Is(err, context.Canceled) || result.Committed {
		t.Fatal(result, err)
	}
	replace := store.Replace
	store.Replace = func(string, string) error { return errors.New("replacement collision") }
	if result, err := CompareAndSetSummaryVegetationQualityPreferences(store, context.Background(), expected, proposed); err == nil || result.Committed {
		t.Fatal(result, err)
	}
	after, err := os.ReadFile(store.Path)
	stages, stageErr := filepath.Glob(filepath.Join(filepath.Dir(store.Path), ".config-*.yml"))
	if err != nil || !bytes.Equal(before, after) || stageErr != nil || len(stages) != 0 {
		t.Fatal("refusal changed config or retained stages", err, stageErr)
	}
	ctx, cancel = context.WithCancel(context.Background())
	defer cancel()
	store.Replace = func(from, to string) error {
		if err := replace(from, to); err != nil {
			return err
		}
		cancel()
		return nil
	}
	result, err := CompareAndSetSummaryVegetationQualityPreferences(store, ctx, expected, proposed)
	store.Replace = replace
	if !result.Committed || !result.Changed || err == nil || !strings.Contains(err.Error(), "do not replay") {
		t.Fatal(result, err)
	}
	read, err := ReadSummaryVegetationQualityPreferences(store, context.Background())
	if err != nil || read != proposed {
		t.Fatal(read, err)
	}
}

func TestSummaryQualityPrivateHistoricalNULOmissionAndCorrection(t *testing.T) {
	store := summaryQualityFixture(t)
	if err := store.Update("ReportOptions", map[string]any{"DataQualityFilterSite": "old\x00literal"}); err != nil {
		t.Fatal(err)
	}
	expected, err := ReadSummaryVegetationQualityPreferences(store, context.Background())
	if err != nil {
		t.Fatal(err)
	}
	proposed := expected
	proposed.SoilIncludeNulls = false
	if result, err := CompareAndSetSummaryVegetationQualityPreferences(store, context.Background(), expected, proposed); err != nil || !result.Committed {
		t.Fatal(result, err)
	}
	if read, err := ReadSummaryVegetationQualityPreferences(store, context.Background()); err != nil || read != proposed {
		t.Fatal(read, err)
	}
	corrected := proposed
	corrected.SiteMinimum = "Good"
	if result, err := CompareAndSetSummaryVegetationQualityPreferences(store, context.Background(), proposed, corrected); err != nil || !result.Committed {
		t.Fatal(result, err)
	}
}

func TestDefaultConfigInitYMLQualityEnforceRetainsNumericSampleBECUsePlots(t *testing.T) {
	sampleRaw, err := vprocore.SampleFiles.ReadFile("resources/Sample.db")
	if err != nil {
		t.Fatal(err)
	}
	contexts, state := newClonedContextService(t, sampleRaw, nil)
	sel := vprotest.ContextSelection(state)
	sel.SU = "Sample"
	sel.SUPath = state.ProjectPath
	sampleState, err := contexts.SwitchContext(state.ContextID, sel)
	if err != nil {
		t.Fatalf("SwitchContext to Sample SU failed: %v", err)
	}

	qualSvc := NewSummaryVegetationQualityPreferencesService(contexts)
	review, err := qualSvc.GetSummaryVegetationQualityPreferences(context.Background(), sampleState.ContextID)
	if err != nil {
		t.Fatalf("GetSummaryVegetationQualityPreferences failed: %v", err)
	}
	if review.Values.BECMinimum != "" {
		t.Fatalf("default config.init.yml BECMinimum = %q, want empty string", review.Values.BECMinimum)
	}

	proposed := review.Values
	proposed.Enforce = true
	outcome := qualSvc.SaveSummaryVegetationQualityPreferences(
		context.Background(),
		sampleState.ContextID,
		summaryQualityRequest(t, review.Values, proposed),
	)
	if !outcome.Committed || !outcome.Changed || outcome.ErrorMessage != "" {
		t.Fatalf("enabling Enforce QC failed: %+v", outcome)
	}

	sumSvc, err := NewSummaryVegetationService(contexts)
	if err != nil {
		t.Fatal(err)
	}
	preview, err := sumSvc.PreviewWithPreferences(context.Background(), sampleState.ContextID)
	if err != nil {
		t.Fatalf("PreviewWithPreferences with default Enforce QC failed: %v", err)
	}
	if preview.Quality == nil || !preview.Quality.Enforced ||
		preview.Quality.TotalBefore != 51 || preview.Quality.Retained != 51 || preview.Quality.RemovedCount != 0 ||
		len(preview.Units) != 11 {
		t.Fatalf("default Enforce QC dropped valid Sample BEC_Use plots: quality=%+v units=%d", preview.Quality, len(preview.Units))
	}

	// Exclude NULL BEC_Use while keeping default unset BECMinimum: all 48 numeric BEC_Use (1..5) plots must remain.
	noNullBEC := proposed
	noNullBEC.BECIncludeNulls = false
	outNoNull := qualSvc.SaveSummaryVegetationQualityPreferences(
		context.Background(),
		sampleState.ContextID,
		summaryQualityRequest(t, proposed, noNullBEC),
	)
	if !outNoNull.Committed || outNoNull.ErrorMessage != "" {
		t.Fatalf("disabling BECIncludeNulls failed: %+v", outNoNull)
	}
	previewNoNull, err := sumSvc.PreviewWithPreferences(context.Background(), sampleState.ContextID)
	if err != nil {
		t.Fatalf("PreviewWithPreferences with BECIncludeNulls=false failed: %v", err)
	}
	if previewNoNull.Quality == nil || previewNoNull.Quality.Retained != 48 || previewNoNull.Quality.RemovedCount != 3 {
		t.Fatalf("expected 48 numeric BEC_Use plots retained and 3 NULL plots removed, got %+v", previewNoNull.Quality)
	}

	// Verify Exclusion Filter preview succeeds across all 6 display modes when showClass is normalized.
	for _, display := range []int{1, 2, 3, 4, 5, 6} {
		showClass := normalizeSummaryVegetationShowClass(display, 1)
		exclPrev, err := PreviewSummaryVegetationWithExclusions(context.Background(), contexts, sampleState.ContextID, SummaryVegetationExclusionRequest{
			Average:          1,
			Display:          display,
			ShowClass:        showClass,
			GroupAndOrder:    11,
			UseDefaultPresets: true,
		})
		if err != nil || exclPrev == nil || len(exclPrev.Preview.Rows) == 0 {
			t.Fatalf("PreviewSummaryVegetationWithExclusions(display=%d, showClass=%d) failed: err=%v preview=%+v", display, showClass, err, exclPrev)
		}
	}
}
