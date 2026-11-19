package lifecycle

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/boostao/vpro/app/internal/vprocore"
)

func TestStartupRecoverySampleFallbackRelocationAndPortableReanchor(t *testing.T) {
	// 1. Portable dataDir re-anchoring across moved profiles/OSes
	dataA := filepath.Join(t.TempDir(), "machine-a", "vpro")
	configDir := filepath.Join(t.TempDir(), "config")
	prefs, err := vprocore.OpenDesktopConfig(dataA, configDir)
	if err != nil {
		t.Fatal(err)
	}
	svcA, err := vprocore.NewSQLiteProjectService(dataA, configDir, prefs)
	if err != nil {
		t.Fatal(err)
	}
	_ = svcA.CloseSQLiteContext()

	// Simulate copying config.yml with Windows/Machine-A managed paths onto Machine-B dataDir
	dataB := filepath.Join(t.TempDir(), "machine-b", "vpro")
	if err := prefs.Update("Current", map[string]any{
		"ProjectPath":   `C:\Users\FieldCrew\AppData\Local\vpro\projects\Sample.db`,
		"HierarchyPath": `C:\Users\FieldCrew\AppData\Local\vpro\projects\Sample.db`,
	}); err != nil {
		t.Fatal(err)
	}
	if err := prefs.Update("Desktop", map[string]any{
		"DatabasePaths": map[string]any{
			"VUser": `C:\Users\FieldCrew\AppData\Local\vpro\database-family\VUser.db`,
		},
	}); err != nil {
		t.Fatal(err)
	}
	// Remove Machine-A folder completely so old paths cannot exist anywhere
	_ = os.RemoveAll(dataA)

	svcB, err := vprocore.NewSQLiteProjectService(dataB, configDir, prefs)
	if err != nil {
		t.Fatalf("expected portable dataDir re-anchoring to succeed, got %v", err)
	}
	stateB, err := svcB.GetState(context.Background())
	_ = svcB.CloseSQLiteContext()
	if err != nil || stateB.ProjectPath != filepath.Join(dataB, "projects", "Sample.db") {
		t.Fatalf("unexpected re-anchored project path: %+v (%v)", stateB, err)
	}

	// 2. StartupService ResetToSample backs up broken config.yml to config.backup-<ts>.yml and activates Sample
	recData := t.TempDir()
	recConfig := t.TempDir()
	configFile := filepath.Join(recConfig, "config.yml")
	// Seed retained legacy JSON files (from an earlier VPro migration) to verify ResetToSample
	// stamps Desktop.LegacyImports and never triggers a legacy JSON conflict on activation.
	if err := os.WriteFile(filepath.Join(recConfig, "coordinate-settings.json"), []byte(`{"mode":"dms"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	brokenYAML := []byte("Current:\n  CurrProject: \"MissingUSB\"\n  ProjectPath: \"/unplugged/usb/MissingUSB.db\"\n  User: \"FieldLead\"\n")
	if err := os.WriteFile(configFile, brokenYAML, 0o600); err != nil {
		t.Fatal(err)
	}

	fixedClock := time.Date(2026, 11, 12, 18, 30, 45, 0, time.UTC)
	activateRuntime := func() (StartupState, error) {
		p, err := vprocore.OpenDesktopConfig(recData, recConfig)
		if err != nil {
			return StartupState{}, err
		}
		ps, err := vprocore.NewSQLiteProjectService(recData, recConfig, p)
		if err != nil {
			return StartupState{}, err
		}
		defer ps.CloseSQLiteContext()
		st := StartupState{Ready: true, ConfigPath: p.Path, ReleaseChannel: vprocore.ReleaseChannelStable}
		PopulateRecoveryHints(&st)
		return st, nil
	}

	startup := &StartupService{
		DataDir: recData,
		Now:     func() time.Time { return fixedClock },
		State: StartupState{
			Ready:      false,
			Message:    "missing USB project",
			ConfigPath: configFile,
		},
		Activate: activateRuntime,
	}
	PopulateRecoveryHints(&startup.State)
	if startup.State.ConfiguredProject != "MissingUSB" || startup.State.ProjectPath != "/unplugged/usb/MissingUSB.db" {
		t.Fatalf("PopulateRecoveryHints missed fields: %+v", startup.State)
	}

	recovered, err := startup.ResetToSample(context.Background())
	if err != nil || !recovered.Ready {
		t.Fatalf("ResetToSample failed: %+v (%v)", recovered, err)
	}
	wantBackup := filepath.Join(recConfig, "config.backup-20261112-183045.yml")
	if recovered.BackupPath != wantBackup {
		t.Fatalf("BackupPath = %q, want %q", recovered.BackupPath, wantBackup)
	}
	backupBytes, err := os.ReadFile(wantBackup)
	if err != nil || !bytes.Equal(backupBytes, brokenYAML) {
		t.Fatalf("backup did not preserve exact prior config.yml bytes: %v", err)
	}

	// 3. StartupService RecoverWithPaths relocates missing external .db, preserves User, and backs up without colliding
	relocatedDir := t.TempDir()
	relocatedDB := filepath.Join(relocatedDir, "RelocatedSample.db")
	sampleRaw, err := os.ReadFile(filepath.Join(recData, "projects", "Sample.db"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(relocatedDB, sampleRaw, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(configFile, []byte(
		"Desktop:\n  SchemaVersion: 1\nAudit:\n  AuditStrength: 2\nCurrent:\n  CoordMethod: 1\n  AssignedSuSource: 1\n  CurrProject: \"Sample\"\n  ProjectPath: \"/gone/drive/Sample.db\"\n  CurrPlotlist: \"MissingSU\"\n  SUPath: \"/gone/drive/MissingSU.db\"\n  CurrHierarchy: \"MissingHier\"\n  HierarchyPath: \"/gone/drive/MissingHier.db\"\n  User: \"EcologistJane\"\n",
	), 0o600); err != nil {
		t.Fatal(err)
	}

	startup2 := &StartupService{
		DataDir:  recData,
		Now:      func() time.Time { return fixedClock }, // same timestamp tests -1 collision suffix!
		Chooser:  func(context.Context) (string, error) { return relocatedDB, nil },
		State:    StartupState{Ready: false, Message: "missing drive", ConfigPath: configFile},
		Activate: activateRuntime,
	}
	chosen, err := startup2.ChooseDatabaseFile(context.Background())
	if err != nil || chosen != relocatedDB {
		t.Fatalf("ChooseDatabaseFile = %q (%v), want %q", chosen, err, relocatedDB)
	}
	relocState, err := startup2.RecoverWithPaths(context.Background(), StartupRecoveryRequest{
		ProjectPath:    chosen,
		ClearSU:        true,
		ClearHierarchy: true,
	})
	if err != nil || !relocState.Ready {
		t.Fatalf("RecoverWithPaths failed: %+v (%v)", relocState, err)
	}
	if !strings.HasSuffix(relocState.BackupPath, "config.backup-20261112-183045-1.yml") {
		t.Fatalf("expected non-overwriting -1 backup suffix, got %q", relocState.BackupPath)
	}
	reopenedPrefs, err := vprocore.OpenDesktopConfig(recData, recConfig)
	if err != nil {
		t.Fatal(err)
	}
	snap, err := reopenedPrefs.Snapshot()
	if err != nil {
		t.Fatal(err)
	}
	if u, _ := vprocore.ConfigString(snap, "Current", "User"); u != "EcologistJane" {
		t.Fatalf("RecoverWithPaths lost custom Current.User: got %q", u)
	}
}

func TestStartupRecoveryRealStateUpgradeOption2AndDiagnostics(t *testing.T) {
	// Seed a workspace with Sample.db and family databases first
	dataDir := t.TempDir()
	seedCfg := t.TempDir()
	initPrefs, err := vprocore.OpenDesktopConfig(dataDir, seedCfg)
	if err != nil {
		t.Fatal(err)
	}
	initSvc, err := vprocore.NewSQLiteProjectService(dataDir, seedCfg, initPrefs)
	if err != nil {
		t.Fatal(err)
	}
	_ = initSvc.CloseSQLiteContext()
	sampleDB := filepath.Join(dataDir, "projects", "Sample.db")

	// 1. Direct boot on real-state config.yml + partial desktop-selection.json {"activeProject":"Sample"}
	realCfg := t.TempDir()
	realYAML := strings.Join([]string{
		"Audit:",
		"  AuditStrength: 1",
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
		"Message:",
		"  DontShowDataQualityMessage: no",
		"  ShowWhatsNew: yes",
		"ReportOptions:",
		"  DataQualityFilterEnforce: no",
		"  DataQualityFilterEnforceLV: no",
		"  DataQualityFilterSiteNull: yes",
		"  DataQualityFilterSiteNullLV: yes",
		"System:",
		"  RunOnce: yes",
		"",
	}, "\n")
	if err := os.WriteFile(filepath.Join(realCfg, "config.yml"), []byte(realYAML), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(realCfg, "desktop-selection.json"), []byte(`{"activeProject":"Sample"}`), 0o600); err != nil {
		t.Fatal(err)
	}

	upgradedPrefs, err := vprocore.OpenDesktopConfig(dataDir, realCfg)
	if err != nil {
		t.Fatalf("expected real-state config.yml + partial desktop-selection.json to boot without recovery, got %v", err)
	}
	upgradedSvc, err := vprocore.NewSQLiteProjectService(dataDir, realCfg, upgradedPrefs)
	if err != nil {
		t.Fatalf("NewSQLiteProjectService after real-state upgrade failed: %v", err)
	}
	liveState, err := upgradedSvc.GetState(context.Background())
	_ = upgradedSvc.CloseSQLiteContext()
	if err != nil || liveState.ActiveProject != "Sample" || liveState.ActiveHierarchy != "Sample" {
		t.Fatalf("unexpected active state after real-state upgrade: %+v (%v)", liveState, err)
	}

	// 2. Option 2 (RecoverWithPaths) with string CoordMethod: '1', ProjectIdSource: '2', and valid HierarchyPath (ClearHierarchy: false)
	opt2Cfg := t.TempDir()
	opt2ConfigFile := filepath.Join(opt2Cfg, "config.yml")
	if err := os.WriteFile(opt2ConfigFile, []byte(realYAML), 0o600); err != nil {
		t.Fatal(err)
	}
	// Trigger an explicit conflict via desktop-selection.json so Startup Recovery is entered
	if err := os.WriteFile(filepath.Join(opt2Cfg, "desktop-selection.json"), []byte(`{"activeProject":"Sample","activeHierarchy":"None"}`), 0o600); err != nil {
		t.Fatal(err)
	}

	fixedClock := time.Date(2026, 11, 19, 14, 0, 0, 0, time.UTC)
	activateOpt2 := func() (StartupState, error) {
		p, oErr := vprocore.OpenDesktopConfig(dataDir, opt2Cfg)
		if oErr != nil {
			return StartupState{}, oErr
		}
		ps, sErr := vprocore.NewSQLiteProjectService(dataDir, opt2Cfg, p)
		if sErr != nil {
			return StartupState{}, sErr
		}
		defer ps.CloseSQLiteContext()
		st := StartupState{Ready: true, ConfigPath: p.Path, ReleaseChannel: vprocore.ReleaseChannelStable}
		PopulateRecoveryHints(&st)
		return st, nil
	}

	startupOpt2 := &StartupService{
		DataDir:  dataDir,
		Now:      func() time.Time { return fixedClock },
		Activate: activateOpt2,
	}
	initialRecovery := StartupState{
		Ready:      false,
		Message:    "legacy JSON conflicts with explicit YAML Current.CurrHierarchy; both files were retained",
		ConfigPath: opt2ConfigFile,
	}
	PopulateRecoveryHints(&initialRecovery)
	startupOpt2.SetState(initialRecovery)

	gotFailure := startupOpt2.GetState()
	if strings.Contains(gotFailure.Message, "Current.CurrHierarchy") || strings.Contains(gotFailure.Message, "RuntimeError") {
		t.Fatalf("expected plain-language failure message, got %q", gotFailure.Message)
	}
	if strings.Contains(gotFailure.Message, "Configured Hierarchy database was not found") {
		t.Fatalf("valid HierarchyPath %q was falsely flagged as missing: %q", sampleDB, gotFailure.Message)
	}

	recovered, err := startupOpt2.RecoverWithPaths(context.Background(), StartupRecoveryRequest{
		ProjectPath:    sampleDB,
		ProjectName:    "Sample",
		SUPath:         "",
		ClearSU:        false,
		HierarchyPath:  sampleDB,
		ClearHierarchy: false,
	})
	if err != nil || !recovered.Ready {
		t.Fatalf("Option 2 RecoverWithPaths failed on string CoordMethod: %+v (%v)", recovered, err)
	}
	if recovered.BackupPath == "" {
		t.Fatal("expected Option 2 to create config.backup-<timestamp>.yml")
	}
	afterPrefs, err := vprocore.OpenDesktopConfig(dataDir, opt2Cfg)
	if err != nil {
		t.Fatal(err)
	}
	afterSel, err := afterPrefs.Selection()
	if err != nil || afterSel.Hierarchy != "Sample" || afterSel.HierarchyPath != sampleDB {
		t.Fatalf("Option 2 failed to preserve valid Hierarchy selection: %+v (%v)", afterSel, err)
	}
	afterSnap, err := afterPrefs.Snapshot()
	if err != nil {
		t.Fatal(err)
	}
	if coord, cErr := vprocore.ConfigInt(afterSnap, "Current", "CoordMethod", 1, 3); cErr != nil || coord != 1 {
		t.Fatalf("CoordMethod after Option 2 = %d (%v), want 1", coord, cErr)
	}
	if projSrc, pErr := vprocore.ConfigInt(afterSnap, "Current", "ProjectIdSource", 1, 2); pErr != nil || projSrc != 2 {
		t.Fatalf("ProjectIdSource after Option 2 = %d (%v), want 2", projSrc, pErr)
	}
	if strength, aErr := vprocore.ConfigInt(afterSnap, "Audit", "AuditStrength", 0, 3); aErr != nil || strength != 1 {
		t.Fatalf("AuditStrength after Option 2 = %d (%v), want 1", strength, aErr)
	}

	// 3. Option 2 repairs genuinely corrupt CoordMethod/AuditStrength while pre-filling managed ProjectPath via SetState
	corruptCfg := t.TempDir()
	corruptFile := filepath.Join(corruptCfg, "config.yml")
	corruptYAML := "Audit:\n  AuditStrength: 99\nCurrent:\n  CoordMethod: 'corrupt'\n  CurrProject: Sample\n  ProjectPath: ''\n  CurrPlotlist: MissingSU\n  SUPath: '/nonexistent/MissingSU.db'\n  CurrHierarchy: MissingHier\n  HierarchyPath: '/nonexistent/MissingHier.db'\n  User: BotanistSam\n"
	if err := os.WriteFile(corruptFile, []byte(corruptYAML), 0o600); err != nil {
		t.Fatal(err)
	}
	startupCorrupt := &StartupService{
		DataDir: dataDir,
		Now:     func() time.Time { return fixedClock },
		Activate: func() (StartupState, error) {
			p, oErr := vprocore.OpenDesktopConfig(dataDir, corruptCfg)
			if oErr != nil {
				return StartupState{}, oErr
			}
			ps, sErr := vprocore.NewSQLiteProjectService(dataDir, corruptCfg, p)
			if sErr != nil {
				return StartupState{}, sErr
			}
			defer ps.CloseSQLiteContext()
			st := StartupState{Ready: true, ConfigPath: p.Path, ReleaseChannel: vprocore.ReleaseChannelStable}
			PopulateRecoveryHints(&st)
			return st, nil
		},
	}
	corruptRecovery := StartupState{
		Ready:      false,
		Message:    "Current.CoordMethod must be an integer from 1 to 3",
		ConfigPath: corruptFile,
	}
	PopulateRecoveryHints(&corruptRecovery)
	startupCorrupt.SetState(corruptRecovery)

	corruptState := startupCorrupt.GetState()
	if corruptState.ProjectPath != sampleDB {
		t.Fatalf("expected SetState to prefill managed Sample.db path %q when ProjectPath=='', got %q", sampleDB, corruptState.ProjectPath)
	}
	if !strings.Contains(corruptState.Message, "Configured Site Unit database was not found at /nonexistent/MissingSU.db.") ||
		!strings.Contains(corruptState.Message, "Configured Hierarchy database was not found at /nonexistent/MissingHier.db.") {
		t.Fatalf("expected missing SU/Hierarchy diagnostics in message, got %q", corruptState.Message)
	}

	repaired, err := startupCorrupt.RecoverWithPaths(context.Background(), StartupRecoveryRequest{
		ProjectPath:    corruptState.ProjectPath,
		ClearSU:        true,
		ClearHierarchy: true,
	})
	if err != nil || !repaired.Ready {
		t.Fatalf("RecoverWithPaths failed to repair corrupt scalars: %+v (%v)", repaired, err)
	}
	repairedPrefs, err := vprocore.OpenDesktopConfig(dataDir, corruptCfg)
	if err != nil {
		t.Fatal(err)
	}
	repairedSnap, err := repairedPrefs.Snapshot()
	if err != nil {
		t.Fatal(err)
	}
	if u, _ := vprocore.ConfigString(repairedSnap, "Current", "User"); u != "BotanistSam" {
		t.Fatalf("expected User BotanistSam preserved after repair, got %q", u)
	}
}
