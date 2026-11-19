package vprocore_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func realStateSeedYAML(dataDir string) string {
	sampleDB := filepath.Join(dataDir, "projects", "Sample.db")
	return strings.Join([]string{
		"Audit:",
		"  AuditStrength: 1",
		"CHARS:",
		"  ShowCHARStreeVersion: 0",
		"Current:",
		"  AssignedSuSource: 1",
		"  CoordMethod: '1'",
		"  CurrPlotlist: None",
		"  CurrProject: Sample",
		"  CurrHierarchy: Sample",
		"  HierarchyPath: " + sampleDB,
		"  CurrVegProfile: Sample",
		"  DataFormName: frmSIVIsite",
		"  DataFormNumber: '1'",
		"  ProjectIdSource: '2'",
		"  ProjectPath: " + sampleDB,
		"  SUPath: ''",
		"  User: Admin",
		"Diagnostic:",
		"  Name: Diagnostic10",
		"Export:",
		"  rExportUnits: 1",
		"  rVegBy: 1",
		"Hierarchy:",
		"  HierarchyBreaksOnRoots: 0",
		"Message:",
		"  DontShowDataQualityMessage: no",
		"  ShowWhatsNew: yes",
		"PictureOptions:",
		"  PictureLibrary: 0",
		"Program:",
		"  Name: VPro64",
		"ReportOptions:",
		"  DataQualityFilterBECUse: 1",
		"  DataQualityFilterBECUseLV: 'True'",
		"  DataQualityFilterEnforce: no",
		"  DataQualityFilterEnforceLV: no",
		"  DataQualityFilterSite: Poor",
		"  DataQualityFilterSiteLV: Poor",
		"  DataQualityFilterSiteNull: yes",
		"  DataQualityFilterSiteNullLV: yes",
		"  DataQualityFilterSoil: Poor",
		"  DataQualityFilterSoilLV: Poor",
		"  DataQualityFilterSoilNull: 'True'",
		"  DataQualityFilterSoilNullLV: 'True'",
		"  DataQualityFilterVeg: Poor",
		"  DataQualityFilterVegLV: Poor",
		"  DataQualityFilterVegNull: 'True'",
		"  DataQualityFilterVegNullLV: 'True'",
		"  LVAvgType: '10'",
		"  LVOrderBy: '20'",
		"  PcOrdGroup: '1'",
		"System:",
		"  RunOnce: yes",
		"  Version: '3'",
		"UpdateOptions:",
		"  DoUpdateCheck: 0",
		"  DoUpdateCheckInterval: '15'",
		"User:",
		"  ShowReadOnce: 0",
		"",
	}, "\n")
}

func TestOpenDesktopConfigRealStateUpgradeWithAndWithoutLegacySelection(t *testing.T) {
	for _, withSelectionJSON := range []bool{true, false} {
		name := "without-desktop-selection-json"
		if withSelectionJSON {
			name = "with-partial-desktop-selection-json"
		}
		t.Run(name, func(t *testing.T) {
			dataDir, configDir := vprotest.ConfigFixture(t)
			if err := os.WriteFile(filepath.Join(configDir, "config.yml"), []byte(realStateSeedYAML(dataDir)), 0o600); err != nil {
				t.Fatal(err)
			}
			if withSelectionJSON {
				if err := os.WriteFile(filepath.Join(configDir, "desktop-selection.json"), []byte(`{"activeProject":"Sample"}`), 0o600); err != nil {
					t.Fatal(err)
				}
			}

			store, err := vprocore.OpenDesktopConfig(dataDir, configDir)
			if err != nil {
				t.Fatalf("OpenDesktopConfig failed on real-state config.yml (%s): %v", name, err)
			}

			mode, err := store.CoordinateMode()
			if err != nil || mode != vprocore.CoordinateModeDD {
				t.Fatalf("CoordinateMode = %q (%v), want %q", mode, err, vprocore.CoordinateModeDD)
			}
			sel, err := store.Selection()
			if err != nil {
				t.Fatal(err)
			}
			wantPath := filepath.Join(dataDir, "projects", "Sample.db")
			if sel.Project != "Sample" || sel.SU != "None" || sel.Hierarchy != "Sample" || sel.HierarchyPath != wantPath || sel.ProjectPath != wantPath {
				t.Fatalf("unexpected upgraded selection: %+v", sel)
			}

			snap, err := store.Snapshot()
			if err != nil {
				t.Fatal(err)
			}
			if projSrc, err := vprocore.ConfigInt(snap, "Current", "ProjectIdSource", 1, 2); err != nil || projSrc != 2 {
				t.Fatalf("ProjectIdSource = %d (%v), want 2", projSrc, err)
			}
			if formNum, err := vprocore.ConfigString(snap, "Current", "DataFormNumber"); err != nil || formNum != "1" {
				t.Fatalf("DataFormNumber = %q (%v), want \"1\"", formNum, err)
			}
			if formName, err := vprocore.ConfigString(snap, "Current", "DataFormName"); err != nil || formName != "frmSIVIsite" {
				t.Fatalf("DataFormName = %q (%v), want \"frmSIVIsite\"", formName, err)
			}
			if user, err := vprocore.ConfigString(snap, "Current", "User"); err != nil || user != "Admin" {
				t.Fatalf("User = %q (%v), want \"Admin\"", user, err)
			}
			if avgType, err := vprocore.ConfigInt(snap, "ReportOptions", "LVAvgType", 10, 20); err != nil || avgType != 10 {
				t.Fatalf("LVAvgType = %d (%v), want 10", avgType, err)
			}
			if pcOrd, err := vprocore.ConfigInt(snap, "ReportOptions", "PcOrdGroup", 0, 5); err != nil || pcOrd != 1 {
				t.Fatalf("PcOrdGroup = %d (%v), want 1", pcOrd, err)
			}
			msgSec, err := vprocore.ConfigSection(snap, "Message")
			if err != nil || msgSec["DontShowDataQualityMessage"] != false || msgSec["ShowWhatsNew"] != true {
				t.Fatalf("Message booleans not normalized: %#v (%v)", msgSec, err)
			}
			repSec, err := vprocore.ConfigSection(snap, "ReportOptions")
			if err != nil || repSec["DataQualityFilterEnforce"] != false || repSec["DataQualityFilterEnforceLV"] != false ||
				repSec["DataQualityFilterSiteNull"] != true || repSec["DataQualityFilterSiteNullLV"] != true {
				t.Fatalf("ReportOptions YAML 1.1 yes/no booleans not normalized: %#v (%v)", repSec, err)
			}
		})
	}
}

func TestNormalizeLegacyConfigScalarsCoordMethodAndStrictRejection(t *testing.T) {
	validCases := []struct {
		name string
		yaml string
		want vprocore.CoordinateMode
	}{
		{"string-1", "Current:\n  CoordMethod: '1'\n", vprocore.CoordinateModeDD},
		{"string-2", "Current:\n  CoordMethod: \"2\"\n", vprocore.CoordinateModeDM},
		{"string-3", "Current:\n  CoordMethod: '3'\n", vprocore.CoordinateModeDMS},
		{"string-0-unset", "Current:\n  CoordMethod: '0'\n", vprocore.CoordinateModeDD},
		{"int-0-unset", "Current:\n  CoordMethod: 0\n", vprocore.CoordinateModeDD},
		{"string-UTM", "Current:\n  CoordMethod: 'UTM'\n", vprocore.CoordinateModeDD},
		{"string-DD", "Current:\n  CoordMethod: 'DD'\n", vprocore.CoordinateModeDD},
		{"string-DM", "Current:\n  CoordMethod: 'dm'\n", vprocore.CoordinateModeDM},
		{"string-DMS", "Current:\n  CoordMethod: 'DMS'\n", vprocore.CoordinateModeDMS},
		{"string-SchemaVersion-and-DataFormNumber-int", "Desktop:\n  SchemaVersion: '1'\nCurrent:\n  CoordMethod: '1'\n  AssignedSuSource: 'master'\n  ProjectIdSource: 'env'\n  DataFormNumber: 1\nAudit:\n  AuditStrength: '2'\n", vprocore.CoordinateModeDD},
	}

	for _, tc := range validCases {
		t.Run(tc.name, func(t *testing.T) {
			dataDir, configDir := vprotest.ConfigFixture(t)
			if err := os.WriteFile(filepath.Join(configDir, "config.yml"), []byte(tc.yaml), 0o600); err != nil {
				t.Fatal(err)
			}
			store, err := vprocore.OpenDesktopConfig(dataDir, configDir)
			if err != nil {
				t.Fatalf("OpenDesktopConfig(%s) failed: %v", tc.name, err)
			}
			got, err := store.CoordinateMode()
			if err != nil || got != tc.want {
				t.Fatalf("CoordinateMode(%s) = %q (%v), want %q", tc.name, got, err, tc.want)
			}
		})
	}

	invalidCases := []string{
		"Current:\n  CoordMethod: '1abc'\n",
		"Current:\n  CoordMethod: '01'\n",
		"Current:\n  CoordMethod: '-0'\n",
		"Current:\n  CoordMethod: '4'\n",
		"Current:\n  CoordMethod: 'invalid'\n",
		"Audit:\n  AuditStrength: '9'\n",
	}
	for _, bad := range invalidCases {
		t.Run(bad, func(t *testing.T) {
			dataDir, configDir := vprotest.ConfigFixture(t)
			if err := os.WriteFile(filepath.Join(configDir, "config.yml"), []byte(bad), 0o600); err != nil {
				t.Fatal(err)
			}
			if _, err := vprocore.OpenDesktopConfig(dataDir, configDir); err == nil {
				t.Fatalf("expected invalid scalar %q to fail OpenDesktopConfig", bad)
			}
		})
	}
}

func TestPartialDesktopSelectionExplicitConflictsStillDetected(t *testing.T) {
	dataDir, configDir := vprotest.ConfigFixture(t)
	if err := os.WriteFile(filepath.Join(configDir, "config.yml"), []byte(realStateSeedYAML(dataDir)), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(configDir, "desktop-selection.json"), []byte(`{"activeProject":"Sample","activeHierarchy":"None"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := vprocore.OpenDesktopConfig(dataDir, configDir); err == nil || !strings.Contains(err.Error(), "CurrHierarchy") {
		t.Fatalf("expected explicit activeHierarchy=None conflict against CurrHierarchy=Sample, got %v", err)
	}
}
