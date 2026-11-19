package references

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/resources"
)

func TestReferenceService_SpeciesAndLists(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "vpro-ref-test-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tempDir)

	svc, err := NewReferenceService(tempDir)
	if err != nil {
		t.Fatalf("NewReferenceService failed: %v", err)
	}
	defer svc.Close()

	// Test 1: Species search
	matches, err := svc.SearchSpecies(context.Background(), "ABIELAS", 10)
	if err != nil {
		t.Fatalf("SearchSpecies failed: %v", err)
	}
	if len(matches) == 0 {
		t.Fatalf("expected species matches for 'ABIELAS', got none")
	}

	foundAbielas := false
	for _, m := range matches {
		if m.Code == "ABIELAS" {
			foundAbielas = true
			if m.ScientificName == "" {
				t.Errorf("expected ScientificName for ABIELAS, got empty")
			}
		}
	}
	if !foundAbielas {
		t.Errorf("expected ABIELAS in search results")
	}

	// Test 2: Get single species
	sp, err := svc.GetSpecies(context.Background(), "ABIELAS")
	if err != nil {
		t.Fatalf("GetSpecies failed: %v", err)
	}
	if sp == nil || sp.Code != "ABIELAS" {
		t.Fatalf("expected ABIELAS, got %v", sp)
	}

	// Test 3: List items (MoistureRegime)
	items, err := svc.GetListItems(context.Background(), "MoistureRegime")
	if err != nil {
		t.Fatalf("GetListItems failed: %v", err)
	}
	if len(items) == 0 {
		t.Fatalf("expected MoistureRegime list items, got none")
	}

	// Test 4: GetAllLists
	all, err := svc.GetAllLists(context.Background())
	if err != nil {
		t.Fatalf("GetAllLists failed: %v", err)
	}
	if len(all) == 0 {
		t.Fatalf("expected non-empty lists map")
	}
	if _, ok := all["MoistureRegime"]; !ok {
		t.Errorf("expected MoistureRegime in GetAllLists")
	}

	// Test 5: 2025/2026 Taxonomy & LMH25 (2023) vocabulary extensions
	for _, code := range []string{"CALLNOO", "PINUALB", "PINUCON1", "POPUHAS", "CORNNUT", "BREWBRE", "ACAUTRI"} {
		sp2026, err := svc.GetSpecies(context.Background(), code)
		if err != nil || sp2026 == nil || sp2026.Code != code {
			t.Fatalf("expected 2025/2026 taxon %s in vlists.db, got %+v (%v)", code, sp2026, err)
		}
	}
	for _, expected := range []struct{ list, item string }{
		{"StructuralStage", "3c"},
		{"StructuralStage", "3d"},
		{"SiviStructuralStage", "3c"},
		{"SiviStructuralStage", "3d"},
		{"StructuralStageMod", "v"},
		{"StructuralStageMod", "k"},
		{"SiteDisturbance", "A.w.th"},
		{"SiteDisturbance", "A.w.br"},
		{"Exposure", "CO"},
		{"FloodingRegimeDur", "S"},
		{"FloodingRegimeFreq", "S"},
	} {
		listItems := all[expected.list]
		found := false
		for _, it := range listItems {
			if it.Item == expected.item {
				found = true
				break
			}
		}
		if !found {
			t.Fatalf("expected LMH25 2023 item %s in list %s", expected.item, expected.list)
		}
	}

	// Test 6: Truncated/corrupt lookup read-model is atomically repaired on open,
	// and top-level <tempDir>/vlists.db is never created.
	_ = svc.Close()
	if _, statErr := os.Lstat(filepath.Join(tempDir, "vlists.db")); !os.IsNotExist(statErr) {
		t.Fatalf("ReferenceService must not create top-level vlists.db, got stat err=%v", statErr)
	}
	readModelPath := ReferenceReadModelPath(tempDir)
	if err := os.WriteFile(readModelPath, []byte("truncated"), 0o644); err != nil {
		t.Fatal(err)
	}
	repaired, err := NewReferenceService(tempDir)
	if err != nil {
		t.Fatalf("NewReferenceService failed to repair truncated %s: %v", readModelPath, err)
	}
	defer repaired.Close()
	spRepaired, err := repaired.GetSpecies(context.Background(), "ABIELAS")
	if err != nil || spRepaired == nil || spRepaired.Code != "ABIELAS" {
		t.Fatalf("repaired lookup read-model failed species lookup: %+v (%v)", spRepaired, err)
	}
}

func TestReferenceService_NeverClobbersCaseInsensitiveOrTopLevelVListsDB(t *testing.T) {
	canonicalVLists, err := resources.DatabaseFamilyFS.ReadFile("resources/database-family/VLists.db")
	if err != nil {
		t.Fatalf("read canonical database-family/VLists.db: %v", err)
	}
	wantHash := sqlutil.BecHash(canonicalVLists)
	if wantHash != "81e259244106b14d6dd3c65f0a7e7e87bdb06f60e6c54947c0506e2039379441" {
		t.Fatalf("unexpected canonical VLists.db hash: %s", wantHash)
	}

	// 1. Simulate a case-insensitive NTFS/APFS <dataDir> where <dataDir>/vlists.db
	// and <dataDir>/VLists.db share the exact same underlying inode.
	ciDir := t.TempDir()
	lowerPath := filepath.Join(ciDir, "vlists.db")
	pascalPath := filepath.Join(ciDir, "VLists.db")
	if err := os.WriteFile(lowerPath, canonicalVLists, 0o644); err != nil {
		t.Fatal(err)
	}
	if _, statErr := os.Stat(pascalPath); os.IsNotExist(statErr) {
		if err := os.Symlink(lowerPath, pascalPath); err != nil {
			t.Fatalf("symlink VLists.db -> vlists.db: %v", err)
		}
	}
	infoLower, err := os.Stat(lowerPath)
	if err != nil {
		t.Fatal(err)
	}
	infoPascal, err := os.Stat(pascalPath)
	if err != nil {
		t.Fatal(err)
	}
	if !os.SameFile(infoLower, infoPascal) {
		t.Fatalf("expected case-insensitive simulation to alias %s and %s to the same file", lowerPath, pascalPath)
	}

	t.Setenv("VPRO_DATA_DIR", ciDir)
	svc, err := NewReferenceService("")
	if err != nil {
		t.Fatalf("NewReferenceService with VPRO_DATA_DIR=%s failed: %v", ciDir, err)
	}
	defer svc.Close()

	sp, err := svc.GetSpecies(context.Background(), "ABIELAS")
	if err != nil || sp == nil || sp.Code != "ABIELAS" {
		t.Fatalf("GetSpecies after case-insensitive coexist boot failed: %+v (%v)", sp, err)
	}
	items, err := svc.GetListItems(context.Background(), "MoistureRegime")
	if err != nil || len(items) == 0 {
		t.Fatalf("GetListItems after case-insensitive coexist boot failed: len=%d err=%v", len(items), err)
	}

	afterBytes, err := os.ReadFile(pascalPath)
	if err != nil {
		t.Fatalf("read VLists.db after NewReferenceService: %v", err)
	}
	if !bytes.Equal(afterBytes, canonicalVLists) {
		t.Fatalf("VLists.db was modified by NewReferenceService: got %d bytes (sha256=%s), want %d bytes (sha256=%s)",
			len(afterBytes), sqlutil.BecHash(afterBytes), len(canonicalVLists), wantHash)
	}

	vdb, err := sqlutil.OpenReadOnly(pascalPath)
	if err != nil {
		t.Fatalf("open preserved VLists.db: %v", err)
	}
	defer vdb.Close()
	for _, tbl := range []string{"USysAllSpecs", "USysSiteSeriesNames", "MasterSiteUnitList", "USysTableOfLists", "USysZoneList"} {
		var exists int
		if err := vdb.QueryRow(`SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?`, tbl).Scan(&exists); err != nil || exists != 1 {
			t.Fatalf("preserved VLists.db missing canonical table %s (exists=%d err=%v)", tbl, exists, err)
		}
	}

	// 2. Placing canonical VLists.db at <csDir>/VLists.db without any pre-existing lowercase entry
	// preserves VLists.db intact and provisions only ReferenceReadModelPath(csDir).
	csDir := t.TempDir()
	topVLists := filepath.Join(csDir, "VLists.db")
	if err := os.WriteFile(topVLists, canonicalVLists, 0o644); err != nil {
		t.Fatal(err)
	}
	svc2, err := NewReferenceService(csDir)
	if err != nil {
		t.Fatalf("NewReferenceService(csDir) failed: %v", err)
	}
	defer svc2.Close()

	if _, err := os.Stat(ReferenceReadModelPath(csDir)); err != nil {
		t.Fatalf("expected isolated read-model at %s: %v", ReferenceReadModelPath(csDir), err)
	}
	csAfter, err := os.ReadFile(topVLists)
	if err != nil || !bytes.Equal(csAfter, canonicalVLists) {
		t.Fatalf("top-level VLists.db altered: err=%v", err)
	}
}
