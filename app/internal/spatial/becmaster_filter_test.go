package spatial

import (
	"context"
	"encoding/json"
	"slices"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestBECMasterFilterOptionsParity(t *testing.T) {
	contexts, state := vprotest.ContextServiceFixture(t)
	ctx := context.Background()

	opts, err := GetBECMasterFilterOptions(ctx, contexts, state.ContextID)
	if err != nil {
		t.Fatalf("GetBECMasterFilterOptions: %v", err)
	}
	if opts.ContextID != state.ContextID || opts.Project != state.ActiveProject || opts.TotalPlots <= 0 {
		t.Fatalf("unexpected header metadata: %+v", opts)
	}

	// 1. Exact 8 BC Forest Regions
	wantRegions := []string{"RCB", "RKB", "RNO", "ROM", "RSC", "RSK", "RTO", "RWC"}
	gotRegions := make([]string, len(opts.Regions))
	for i, r := range opts.Regions {
		gotRegions[i] = r.Code
		if r.Label == "" {
			t.Fatalf("region %q missing label", r.Code)
		}
	}
	if !slices.Equal(gotRegions, wantRegions) {
		t.Fatalf("regions = %v, want %v", gotRegions, wantRegions)
	}

	// 2. Distinct ProjectIDs from Metadata/Env, Publications gracefully empty
	if len(opts.ProjectIDs) == 0 || len(opts.Projects) != len(opts.ProjectIDs) {
		t.Fatalf("expected non-empty distinct ProjectIDs, got ids=%v projects=%v", opts.ProjectIDs, opts.Projects)
	}
	if opts.HasPublicationLinks || opts.Publications == nil || len(opts.Publications) != 0 {
		t.Fatalf("expected graceful empty publications when no link table exists: has=%v pubs=%v", opts.HasPublicationLinks, opts.Publications)
	}

	// 3. Zones & SubzonesByZone (UPPER(Zone || SubZone))
	if len(opts.Zones) == 0 {
		t.Fatal("expected non-empty Zones")
	}
	for _, z := range opts.Zones {
		if _, ok := opts.SubzonesByZone[z]; !ok {
			t.Fatalf("zone %q missing key in SubzonesByZone", z)
		}
	}

	// 4. MinYear / MaxYear must ignore OLE sentinel 1899-12-30
	if opts.MinYear <= 1900 || opts.MaxYear < opts.MinYear {
		t.Fatalf("invalid MinYear..MaxYear (%d..%d); must exclude 1899 sentinel", opts.MinYear, opts.MaxYear)
	}

	// 5. Exact 8 SuccessionalStatuses
	wantSucc := []string{"OC", "MC", "DC", "YC", "OS", "MS", "YS", "PS"}
	gotSucc := make([]string, len(opts.SuccessionalStatuses))
	for i, s := range opts.SuccessionalStatuses {
		gotSucc[i] = s.Code
	}
	if !slices.Equal(gotSucc, wantSucc) {
		t.Fatalf("successionalStatuses = %v, want %v", gotSucc, wantSucc)
	}

	// 6. StructuralStages from VLists.USysTableOfLists (<=2 char items)
	if len(opts.StructuralStages) < 15 {
		t.Fatalf("expected >=15 structural stages from VLists, got %d: %+v", len(opts.StructuralStages), opts.StructuralStages)
	}
	for _, st := range opts.StructuralStages {
		if len([]rune(st.Code)) > 2 || st.Code == "" {
			t.Fatalf("unexpected structural stage code %q", st.Code)
		}
	}

	// 7. Site/Veg/Soil PlotQualities from VLists PlotQualitySite excluding 'NA'
	wantQuals := []string{"Excellent", "Good", "Fair", "Poor"}
	for label, list := range map[string][]BECMasterCodedOption{
		"site": opts.SitePlotQualities,
		"veg":  opts.VegPlotQualities,
		"soil": opts.SoilPlotQualities,
	} {
		got := make([]string, len(list))
		for i, q := range list {
			got[i] = q.Code
			if q.Code == "NA" {
				t.Fatalf("%s qualities must exclude NA", label)
			}
		}
		if !slices.Equal(got, wantQuals) {
			t.Fatalf("%s qualities = %v, want %v", label, got, wantQuals)
		}
	}

	// 8. Exact 7 LocationAccuracies
	wantAcc := []string{"<=1", "<=5", "<=10", "<=30", "<=100", "<=1000", ">1000"}
	gotAcc := make([]string, len(opts.LocationAccuracies))
	for i, a := range opts.LocationAccuracies {
		gotAcc[i] = a.Code
	}
	if !slices.Equal(gotAcc, wantAcc) {
		t.Fatalf("locationAccuracies = %v, want %v", gotAcc, wantAcc)
	}
}

func TestBECMasterFilterModesAndComposableAttributes(t *testing.T) {
	contexts, state := vprotest.ContextServiceFixture(t)
	ctx := context.Background()

	// Seed deterministic plots covering signed & unsigned BC western longitudes, regions, projects,
	// zones/subzones, years, successional statuses, structural stages, qualities, BECSiteUnit, and accuracies.
	vprotest.MutateContextFixture(t, state.ProjectPath, `
		UPDATE Sample_Env SET
			ProjectID = 'SKEENA2024',
			FSRegionDistrict = 'RSK.DSS',
			Date = '2024-07-15',
			Zone = 'SBS',
			SubZone = 'mc2',
			SiteSeries = '01',
			SuccessionalStatus = 'MC',
			StructuralStage = '6m',
			Latitude = 54.7804,
			Longitude = 127.1743,
			LocationAccuracy = 5
		WHERE PlotNumber = '00337';
		UPDATE Sample_Admin SET
			SitePlotQuality = 'Excellent',
			VegPlotQuality = 'Excellent',
			SoilPlotQuality = 'Good',
			BECSiteUnit = 'SBSmc2/01'
		WHERE Plot = '00337';

		UPDATE Sample_Env SET
			ProjectID = 'OMINECA2018',
			FSRegionDistrict = 'ROM.DPG',
			Date = '2018-08-20',
			Zone = 'SBS',
			SubZone = 'mk1',
			SiteSeries = '05',
			SuccessionalStatus = 'YS',
			StructuralStage = '3b',
			Latitude = 53.9171,
			Longitude = -122.7497,
			LocationAccuracy = 25
		WHERE PlotNumber = '108050';
		UPDATE Sample_Admin SET
			SitePlotQuality = 'Good',
			VegPlotQuality = 'Fair',
			SoilPlotQuality = 'Poor',
			BECSiteUnit = ''
		WHERE Plot = '108050';
	`)

	// 1. Mode: region -> RSK matches 00337 (FSRegionDistrict='RSK.DSS') and not 108050
	regRes, err := FilterBECMasterPlots(ctx, contexts, state.ContextID, BECMasterFilterRequest{
		Mode:    "region",
		Regions: []string{"rsk"},
	})
	if err != nil {
		t.Fatalf("region filter: %v", err)
	}
	if !slices.Contains(regRes.PlotNumbers, "00337") || slices.Contains(regRes.PlotNumbers, "108050") {
		t.Fatalf("unexpected RSK region filter result: %v", regRes.PlotNumbers)
	}
	if len(regRes.Points) != 1 || regRes.Points[0].PlotNumber != "00337" || regRes.Points[0].Lon > 0 || regRes.Points[0].Region != "RSK" {
		t.Fatalf("expected normalized negative West lon & RSK region on point 00337, got %+v", regRes.Points)
	}

	// 2. Mode: project -> SKEENA2024
	projRes, err := FilterBECMasterPlots(ctx, contexts, state.ContextID, BECMasterFilterRequest{
		Mode:       "project",
		ProjectIDs: []string{"SKEENA2024"},
	})
	if err != nil {
		t.Fatalf("project filter: %v", err)
	}
	if !slices.Equal(projRes.PlotNumbers, []string{"00337"}) {
		t.Fatalf("project SKEENA2024 = %v, want [00337]", projRes.PlotNumbers)
	}

	// 3. Mode: bbox with BOTH signed negative longitudes AND legacy positive West longitudes
	nwLat, seLat := 55.2, 54.3
	signedNWLon, signedSELon := -128.0, -126.5
	posNWLon, posSELon := 128.0, 126.5

	bboxSigned, err := FilterBECMasterPlots(ctx, contexts, state.ContextID, BECMasterFilterRequest{
		Mode:  "bbox",
		NWLat: &nwLat, NWLon: &signedNWLon,
		SELat: &seLat, SELon: &signedSELon,
	})
	if err != nil {
		t.Fatalf("signed bbox filter: %v", err)
	}
	bboxPos, err := FilterBECMasterPlots(ctx, contexts, state.ContextID, BECMasterFilterRequest{
		Mode:  "bbox",
		NWLat: &nwLat, NWLon: &posNWLon,
		SELat: &seLat, SELon: &posSELon,
	})
	if err != nil {
		t.Fatalf("positive West bbox filter: %v", err)
	}
	if !slices.Contains(bboxSigned.PlotNumbers, "00337") || slices.Contains(bboxSigned.PlotNumbers, "108050") {
		t.Fatalf("signed bbox mismatch: %v", bboxSigned.PlotNumbers)
	}
	if !slices.Equal(bboxSigned.PlotNumbers, bboxPos.PlotNumbers) {
		t.Fatalf("positive West bbox (%v) diverged from signed bbox (%v)", bboxPos.PlotNumbers, bboxSigned.PlotNumbers)
	}

	// 4. Composable AND attribute & quality filters
	minYr, maxYr := 2020, 2025
	andRes, err := FilterBECMasterPlots(ctx, contexts, state.ContextID, BECMasterFilterRequest{
		Mode:                 "all",
		Zones:                []string{"SBS"},
		Subzones:             []string{"SBSMC2"},
		MinYear:              &minYr,
		MaxYear:              &maxYr,
		SuccessionalStatuses: []string{"MC"},
		StructuralStages:     []string{"6m"}, // LOWER(SUBSTR('6m', 1, 2)) == '6m'
		InPublicationsOnly:   true,           // BECSiteUnit non-empty fallback
		SitePlotQualities:    []string{"Excellent"},
		VegPlotQualities:     []string{"Excellent"},
		SoilPlotQualities:    []string{"Good"},
		LocationAccuracy:     "<=5",
	})
	if err != nil {
		t.Fatalf("composable AND filter: %v", err)
	}
	if !slices.Equal(andRes.PlotNumbers, []string{"00337"}) {
		t.Fatalf("composable AND filter = %v, want [00337]", andRes.PlotNumbers)
	}

	// Check <=30 matches 108050 (acc=25) while <=10 excludes it
	acc30, err := FilterBECMasterPlots(ctx, contexts, state.ContextID, BECMasterFilterRequest{
		Mode:             "project",
		ProjectIDs:       []string{"OMINECA2018"},
		StructuralStages: []string{"3B"},
		LocationAccuracy: "<=30",
	})
	if err != nil || !slices.Equal(acc30.PlotNumbers, []string{"108050"}) {
		t.Fatalf("expected 108050 for acc<=30 & stage 3b, got %v (err=%v)", acc30, err)
	}
	acc10, err := FilterBECMasterPlots(ctx, contexts, state.ContextID, BECMasterFilterRequest{
		Mode:             "project",
		ProjectIDs:       []string{"OMINECA2018"},
		LocationAccuracy: "<=10",
	})
	if err != nil || len(acc10.PlotNumbers) != 0 {
		t.Fatalf("expected 0 plots for acc<=10 on OMINECA2018, got %v (err=%v)", acc10, err)
	}

	// 5. Optional publication link table discovery & filtering
	vprotest.MutateContextFixture(t, state.ProjectPath, `
		CREATE TABLE ProjectPublications (
			PublicationID TEXT,
			Title TEXT,
			ProjectID TEXT
		);
		INSERT INTO ProjectPublications (PublicationID, Title, ProjectID) VALUES
			('LMH77', 'Field Guide to Site Identification — Skeena', 'SKEENA2024');
	`)
	optsWithPub, err := GetBECMasterFilterOptions(ctx, contexts, state.ContextID)
	if err != nil {
		t.Fatalf("GetBECMasterFilterOptions with publications: %v", err)
	}
	if !optsWithPub.HasPublicationLinks || len(optsWithPub.Publications) != 1 || optsWithPub.Publications[0].ID != "LMH77" {
		t.Fatalf("expected publication LMH77, got has=%v pubs=%+v", optsWithPub.HasPublicationLinks, optsWithPub.Publications)
	}
	pubRes, err := FilterBECMasterPlots(ctx, contexts, state.ContextID, BECMasterFilterRequest{
		Mode:           "project",
		PublicationIDs: []string{"LMH77"},
	})
	if err != nil || !slices.Equal(pubRes.PlotNumbers, []string{"00337"}) {
		t.Fatalf("publication filter = %v (err=%v), want [00337]", pubRes, err)
	}

	// 6. Strict JSON & validation error checks
	var strictReq BECMasterFilterRequest
	if err := json.Unmarshal([]byte(`{"mode":"all","unknownField":1}`), &strictReq); err == nil {
		t.Fatal("expected strict JSON decode error on unknown field")
	}
	if _, err := FilterBECMasterPlots(ctx, contexts, state.ContextID, BECMasterFilterRequest{Mode: "bogus"}); err == nil {
		t.Fatal("expected error for invalid mode")
	}
	if _, err := FilterBECMasterPlots(ctx, contexts, state.ContextID, BECMasterFilterRequest{Mode: "bbox"}); err == nil {
		t.Fatal("expected error for bbox without coordinates")
	}
	if _, err := FilterBECMasterPlots(ctx, contexts, state.ContextID, BECMasterFilterRequest{LocationAccuracy: "<=999"}); err == nil {
		t.Fatal("expected error for invalid locationAccuracy")
	}
	badMin, badMax := 2025, 2020
	if _, err := FilterBECMasterPlots(ctx, contexts, state.ContextID, BECMasterFilterRequest{MinYear: &badMin, MaxYear: &badMax}); err == nil {
		t.Fatal("expected error when minYear > maxYear")
	}
}
