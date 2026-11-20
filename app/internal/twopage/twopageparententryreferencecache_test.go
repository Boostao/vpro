package twopage

import (
	"context"
	"encoding/json"
	"reflect"
	"sync/atomic"
	"testing"

	"github.com/boostao/vpro/app/internal/references"
	"github.com/boostao/vpro/app/internal/sourceform/sftest"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

type countingQualityReader struct {
	inner *references.QualityService
	calls atomic.Int64
}

func (c *countingQualityReader) ListPlotQualityChoices(ctx context.Context) ([]references.PlotQualityChoice, error) {
	c.calls.Add(1)
	return c.inner.ListPlotQualityChoices(ctx)
}

type countingBECReader struct {
	inner        *references.BECService
	zoneCalls    atomic.Int64
	subZoneCalls atomic.Int64
}

func (c *countingBECReader) ListBECZones(ctx context.Context) ([]references.BECZone, error) {
	c.zoneCalls.Add(1)
	return c.inner.ListBECZones(ctx)
}

func (c *countingBECReader) ListBECSubZones(ctx context.Context, zone *string) ([]references.BECSubZone, error) {
	c.subZoneCalls.Add(1)
	return c.inner.ListBECSubZones(ctx, zone)
}

func buildCountingTwoPageReaders(t *testing.T) (TwoPageEntryReferenceReaders, *countingQualityReader, *countingBECReader) {
	t.Helper()
	region, err := references.NewRegionCodeService(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	quality, err := references.NewQualityService(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	soil, err := references.NewSoilCodeService(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	bec, err := references.NewBECService(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	geology, err := references.NewGeologyCodeService(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		for _, closeFn := range []func() error{region.Close, quality.Close, soil.Close, bec.Close, geology.Close} {
			if err := closeFn(); err != nil {
				t.Error(err)
			}
		}
	})
	countingQuality := &countingQualityReader{inner: quality}
	countingBEC := &countingBECReader{inner: bec}
	shared := sftest.TwoPageEntryBorrowedReferenceReaders(t)
	shared.Region = region
	shared.Bec = countingBEC
	shared.Geology = geology
	return TwoPageEntryReferenceReaders{
		Shared:     shared,
		Ecosection: region,
		Quality:    countingQuality,
		Soil:       soil,
		Series:     bec,
	}, countingQuality, countingBEC
}

func TestTwoPageStaticReferenceCacheParityCloningAndEviction(t *testing.T) {
	ctx := context.Background()
	contexts, state := vprotest.ContextServiceFixture(t)
	readers, countingQuality, countingBEC := buildCountingTwoPageReaders(t)

	page, err := contexts.Projects.ListPlots(ctx, 0, 3)
	if err != nil || len(page.Plots) < 2 {
		t.Fatalf("ListPlots failed: %v (len=%d)", err, len(page.Plots))
	}
	plot1, plot2 := page.Plots[0].PlotNumber, page.Plots[1].PlotNumber
	owner := contexts.Projects.Sqlite

	// 1. Cold read populates static cache for (owner, contextID, form).
	snap1, err := ReadTwoPageEntryReferences(contexts, ctx, state.ContextID, plot1, "FS882-8x6XL",
		vprotest.MetadataText("BG"), vprotest.MetadataText("xh1"), readers)
	if err != nil {
		t.Fatalf("cold ReadTwoPageEntryReferences failed: %v", err)
	}
	if len(snap1.Fields) != 56 {
		t.Fatalf("expected 56 fields, got %d", len(snap1.Fields))
	}
	if !twoPageStaticRefCache.hasOwnerForTest(owner) {
		t.Fatal("expected static reference cache entry to be populated for active owner")
	}
	qualityCallsAfterCold := countingQuality.calls.Load()
	zoneCallsAfterCold := countingBEC.zoneCalls.Load()
	subZoneCallsAfterCold := countingBEC.subZoneCalls.Load()
	if qualityCallsAfterCold == 0 || zoneCallsAfterCold != 1 || subZoneCallsAfterCold != 1 {
		t.Fatalf("unexpected cold counts: quality=%d zone=%d subZone=%d",
			qualityCallsAfterCold, zoneCallsAfterCold, subZoneCallsAfterCold)
	}

	// 2. Warm read on a different plot & different (Zone, SubZone) reuses all static fields
	//    while recomputing dynamic SubZone / SiteSeries / ProjectID / UserSiteUnit fields.
	snap2Warm, err := ReadTwoPageEntryReferences(contexts, ctx, state.ContextID, plot2, "FS882-8x6XL",
		vprotest.MetadataText("IDF"), vprotest.MetadataText("dk1"), readers)
	if err != nil {
		t.Fatalf("warm ReadTwoPageEntryReferences failed: %v", err)
	}
	if countingQuality.calls.Load() != qualityCallsAfterCold {
		t.Fatalf("expected 0 quality calls on warm cache hit, got %d", countingQuality.calls.Load()-qualityCallsAfterCold)
	}
	if countingBEC.zoneCalls.Load() != zoneCallsAfterCold {
		t.Fatalf("expected 0 Zone calls on warm cache hit, got %d", countingBEC.zoneCalls.Load()-zoneCallsAfterCold)
	}
	if countingBEC.subZoneCalls.Load() != subZoneCallsAfterCold+1 {
		t.Fatalf("expected SubZone (dynamic) to re-query on warm cache hit, got %d", countingBEC.subZoneCalls.Load()-subZoneCallsAfterCold)
	}

	// Compare warm snapshot byte-for-byte against a completely cold (evicted) read for the same inputs.
	twoPageStaticRefCache.evictOwner(owner)
	snap2Cold, err := ReadTwoPageEntryReferences(contexts, ctx, state.ContextID, plot2, "FS882-8x6XL",
		vprotest.MetadataText("IDF"), vprotest.MetadataText("dk1"), readers)
	if err != nil {
		t.Fatalf("cold parity ReadTwoPageEntryReferences failed: %v", err)
	}
	warmJSON, err := json.Marshal(snap2Warm)
	if err != nil {
		t.Fatal(err)
	}
	coldJSON, err := json.Marshal(snap2Cold)
	if err != nil {
		t.Fatal(err)
	}
	if string(warmJSON) != string(coldJSON) || !reflect.DeepEqual(snap2Warm, snap2Cold) {
		t.Fatal("warm cached TwoPageEntryReferenceSnapshot diverged from cold uncached read")
	}

	// 3. Defensive cloning: mutating returned slices/pointers must not corrupt cached entries.
	mutatedStaticColumn := ""
	originalChoiceCode := ""
	for i := range snap2Cold.Fields {
		field := &snap2Cold.Fields[i]
		if field.Column == "Zone" && len(field.Choices) > 0 && field.Choices[0].Code != nil {
			mutatedStaticColumn = field.Column
			originalChoiceCode = *field.Choices[0].Code
			*field.Choices[0].Code = "MUTATED_BY_CALLER"
			field.Choices = field.Choices[:0]
			break
		}
	}
	if mutatedStaticColumn == "" {
		t.Fatal("failed to locate Zone field for defensive clone check")
	}
	snap3, err := ReadTwoPageEntryReferences(contexts, ctx, state.ContextID, plot2, "FS882-8x6XL",
		vprotest.MetadataText("IDF"), vprotest.MetadataText("dk1"), readers)
	if err != nil {
		t.Fatalf("post-mutation ReadTwoPageEntryReferences failed: %v", err)
	}
	for _, field := range snap3.Fields {
		if field.Column == mutatedStaticColumn {
			if len(field.Choices) == 0 || field.Choices[0].Code == nil || *field.Choices[0].Code != originalChoiceCode {
				t.Fatalf("cache was mutated by caller: got %+v, want %q", field.Choices, originalChoiceCode)
			}
		}
	}

	// 4. ProfileOwnedFiles verification still runs on warm cache hits.
	origInfo := owner.AttachmentInfo["VLists"]
	owner.AttachmentInfo["VLists"] = owner.AttachmentInfo["project"]
	_, tamperErr := ReadTwoPageEntryReferences(contexts, ctx, state.ContextID, plot2, "FS882-8x6XL",
		vprotest.MetadataText("IDF"), vprotest.MetadataText("dk1"), readers)
	owner.AttachmentInfo["VLists"] = origInfo
	if tamperErr == nil {
		t.Fatal("expected ProfileOwnedFiles check to reject changed VLists file identity even on warm cache")
	}

	// 5. Eviction on context switch / SqliteContext.Close().
	nextSel := vprotest.ContextSelection(state)
	nextSel.SU, nextSel.SUPath = "None", ""
	nextState, err := contexts.SwitchContext(state.ContextID, nextSel)
	if err != nil {
		t.Fatalf("SwitchContext failed: %v", err)
	}
	if twoPageStaticRefCache.hasOwnerForTest(owner) {
		t.Fatal("expected static reference cache to evict closed owner on context switch")
	}

	// New context works cleanly and caches independently.
	if _, err := ReadTwoPageEntryReferences(contexts, ctx, nextState.ContextID, plot1, "FS882-8x6XL",
		vprotest.MetadataText("BG"), vprocore.ProjectMetadataCell{Storage: "null"}, readers); err != nil {
		t.Fatalf("ReadTwoPageEntryReferences on new context failed: %v", err)
	}
	if !twoPageStaticRefCache.hasOwnerForTest(contexts.Projects.Sqlite) {
		t.Fatal("expected new context owner to populate static cache")
	}
}
