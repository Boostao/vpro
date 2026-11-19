package lifecycle

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"go.yaml.in/yaml/v3"
)

type StartupState struct {
	Ready               bool   `json:"ready"`
	Message             string `json:"message"`
	ConfigPath          string `json:"configPath"`
	ReleaseChannel      string `json:"releaseChannel"`
	AppVersion          string `json:"appVersion"`
	BuildMode           string `json:"buildMode"`
	GitCommit           string `json:"gitCommit"`
	BuildDate           string `json:"buildDate"`
	IsPrerelease        bool   `json:"isPrerelease"`
	UnsignedNotice      bool   `json:"unsignedNotice"`
	BackupPath          string `json:"backupPath"`
	ConfiguredProject   string `json:"configuredProject"`
	ProjectPath         string `json:"projectPath"`
	ConfiguredSU        string `json:"configuredSu"`
	SUPath              string `json:"suPath"`
	ConfiguredHierarchy string `json:"configuredHierarchy"`
	HierarchyPath       string `json:"hierarchyPath"`
}

func WithBuildMetadata(state StartupState) StartupState {
	build := CurrentBuildInfo()
	state.AppVersion = build.AppVersion
	state.BuildMode = build.BuildMode
	state.GitCommit = build.GitCommit
	state.BuildDate = build.BuildDate
	state.IsPrerelease = build.IsPrerelease
	state.UnsignedNotice = build.UnsignedNotice
	if strings.TrimSpace(state.ReleaseChannel) == "" {
		state.ReleaseChannel = vprocore.ReleaseChannelStable
	}
	return state
}

type StartupRecoveryRequest struct {
	ProjectPath    string `json:"projectPath"`
	ProjectName    string `json:"projectName"`
	SUPath         string `json:"suPath"`
	ClearSU        bool   `json:"clearSu"`
	HierarchyPath  string `json:"hierarchyPath"`
	ClearHierarchy bool   `json:"clearHierarchy"`
}

func (r *StartupRecoveryRequest) UnmarshalJSON(data []byte) error {
	type plain StartupRecoveryRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type StartupService struct {
	mu       sync.RWMutex
	State    StartupState                          `json:"-" yaml:"-"`
	DataDir  string                                `json:"-" yaml:"-"`
	Now      func() time.Time                      `json:"-" yaml:"-"`
	Chooser  func(context.Context) (string, error) `json:"-" yaml:"-"`
	Activate func() (StartupState, error)          `json:"-" yaml:"-"`
}

func (s *StartupService) now() time.Time {
	if s != nil && s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

func (s *StartupService) GetState() StartupState {
	if s == nil {
		return WithBuildMetadata(StartupState{ReleaseChannel: vprocore.ReleaseChannelStable})
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	return WithBuildMetadata(s.State)
}

func (s *StartupService) SetState(next StartupState) {
	if s == nil {
		return
	}
	s.mu.Lock()
	enrichRecoveryDiagnostics(&next, s.DataDir)
	s.State = WithBuildMetadata(next)
	s.mu.Unlock()
}

var friendlyConfigFieldLabels = map[string]string{
	"Current.CoordMethod":      "Coordinate display format",
	"Current.AssignedSuSource": "Working Unit source",
	"Current.ProjectIdSource":  "Project ID source",
	"Current.CurrProject":      "Active Project",
	"Current.CurrPlotlist":     "Active Site Unit list",
	"Current.CurrHierarchy":    "Active Hierarchy",
	"Current.ProjectPath":      "Project file path",
	"Current.SUPath":           "Site Unit file path",
	"Current.HierarchyPath":    "Hierarchy file path",
	"Current.User":             "User name",
	"Audit.AuditStrength":      "Audit tracking level",
	"Desktop.SchemaVersion":    "Settings version",
}

// HumanizeStartupMessage translates internal YAML/JSON preference key errors into plain language
// while preserving file paths and concrete database diagnostics.
func HumanizeStartupMessage(raw string) string {
	msg := strings.TrimSpace(raw)
	if msg == "" {
		return ""
	}
	for _, prefix := range []string{"RuntimeError: ", "Error: ", "validate recovered configuration: "} {
		for strings.HasPrefix(msg, prefix) {
			msg = strings.TrimSpace(strings.TrimPrefix(msg, prefix))
		}
	}
	if strings.HasPrefix(msg, "legacy JSON conflicts with explicit YAML ") && strings.HasSuffix(msg, "; both files were retained") {
		field := strings.TrimSuffix(strings.TrimPrefix(msg, "legacy JSON conflicts with explicit YAML "), "; both files were retained")
		label := friendlyConfigFieldLabels[field]
		if label == "" {
			label = field
		}
		return fmt.Sprintf("An older VPro selection file conflicts with your saved %s setting. Both files were kept unchanged.", label)
	}
	if strings.HasPrefix(msg, "legacy ") && strings.HasSuffix(msg, " changed after migration; YAML and JSON were retained for explicit resolution") {
		path := strings.TrimSuffix(strings.TrimPrefix(msg, "legacy "), " changed after migration; YAML and JSON were retained for explicit resolution")
		return fmt.Sprintf("An older VPro settings file (%s) changed after your preferences were upgraded. Both files were kept unchanged so you can confirm which project to open.", path)
	}
	switch msg {
	case "Current.CoordMethod must be an integer from 1 to 3":
		return "Saved Coordinate display format setting could not be read (expected Decimal Degrees, Degrees-Minutes, or Degrees-Minutes-Seconds)."
	case "Current.AssignedSuSource must be an integer from 1 to 3":
		return "Saved Working Unit source setting could not be read."
	case "Audit.AuditStrength must be an integer from 0 to 3":
		return "Saved Audit tracking level setting could not be read."
	case "Desktop.SchemaVersion must be an integer from 1 to 1":
		return "Saved settings version is not supported by this release of VPro."
	case "Current.User must not be empty":
		return "Saved User name must not be empty."
	}
	for rawKey, friendly := range friendlyConfigFieldLabels {
		if strings.Contains(msg, rawKey) {
			msg = strings.ReplaceAll(msg, rawKey, friendly)
		}
	}
	msg = strings.ReplaceAll(msg, "configured context could not be opened; YAML was retained: ", "Your saved project or support databases could not be opened (your settings file was kept unchanged): ")
	msg = strings.ReplaceAll(msg, "; YAML selection was retained", " (your saved settings were kept unchanged)")
	msg = strings.ReplaceAll(msg, "; YAML was retained", " (your saved settings were kept unchanged)")
	return msg
}

func appendDiagnosticSentence(base, sentence string) string {
	sentence = strings.TrimSpace(sentence)
	if sentence == "" || strings.Contains(base, sentence) {
		return base
	}
	base = strings.TrimSpace(base)
	if base == "" {
		return sentence
	}
	if !strings.HasSuffix(base, ".") && !strings.HasSuffix(base, "!") && !strings.HasSuffix(base, "?") {
		base += "."
	}
	return base + " " + sentence
}

func enrichRecoveryDiagnostics(state *StartupState, dataDir string) {
	if state == nil || state.Ready {
		return
	}
	state.Message = HumanizeStartupMessage(state.Message)
	if strings.TrimSpace(state.ProjectPath) == "" &&
		strings.TrimSpace(state.ConfiguredProject) != "" &&
		state.ConfiguredProject != "None" &&
		strings.TrimSpace(dataDir) != "" {
		candidate := filepath.Join(dataDir, "projects", state.ConfiguredProject+".db")
		if resolved, err := vprocore.ExistingDatabasePath(candidate); err == nil {
			state.ProjectPath = resolved
		}
	}
	if p := strings.TrimSpace(state.ProjectPath); p != "" {
		if _, err := vprocore.ExistingDatabasePath(p); err != nil && !strings.Contains(state.Message, p) {
			state.Message = appendDiagnosticSentence(state.Message, fmt.Sprintf("Configured project database was not found at %s.", p))
		}
	}
	if su := strings.TrimSpace(state.ConfiguredSU); su != "" && su != "None" {
		if sp := strings.TrimSpace(state.SUPath); sp != "" {
			if _, err := vprocore.ExistingDatabasePath(sp); err != nil {
				state.Message = appendDiagnosticSentence(state.Message, fmt.Sprintf("Configured Site Unit database was not found at %s.", sp))
			}
		}
	}
	if hier := strings.TrimSpace(state.ConfiguredHierarchy); hier != "" && hier != "None" {
		if hp := strings.TrimSpace(state.HierarchyPath); hp != "" {
			if _, err := vprocore.ExistingDatabasePath(hp); err != nil {
				state.Message = appendDiagnosticSentence(state.Message, fmt.Sprintf("Configured Hierarchy database was not found at %s.", hp))
			}
		}
	}
}

// PopulateRecoveryHints extracts best-effort selection hints from an existing config.yml
// without mutating any files on disk.
func PopulateRecoveryHints(state *StartupState) {
	if state == nil || strings.TrimSpace(state.ConfigPath) == "" {
		return
	}
	raw, err := os.ReadFile(state.ConfigPath)
	if err != nil {
		enrichRecoveryDiagnostics(state, "")
		return
	}
	values, err := vprocore.DecodeConfig(raw)
	if err != nil {
		enrichRecoveryDiagnostics(state, "")
		return
	}
	if ch, ok := values["release_channel"].(string); ok && (ch == vprocore.ReleaseChannelStable || ch == vprocore.ReleaseChannelExperimental) {
		state.ReleaseChannel = ch
	}
	current, err := vprocore.ConfigSection(values, "Current")
	if err != nil {
		enrichRecoveryDiagnostics(state, "")
		return
	}
	str := func(k string) string {
		v, _ := current[k].(string)
		return v
	}
	state.ConfiguredProject = str("CurrProject")
	state.ProjectPath = str("ProjectPath")
	state.ConfiguredSU = str("CurrPlotlist")
	state.SUPath = str("SUPath")
	state.ConfiguredHierarchy = str("CurrHierarchy")
	state.HierarchyPath = str("HierarchyPath")
	enrichRecoveryDiagnostics(state, "")
}

// ChooseDatabaseFile opens a native file chooser for relocating a missing .db file.
func (s *StartupService) ChooseDatabaseFile(ctx context.Context) (string, error) {
	if ctx != nil {
		if err := ctx.Err(); err != nil {
			return "", err
		}
	}
	if s != nil && s.Chooser != nil {
		return s.Chooser(ctx)
	}
	path, err := vprocore.ChooseNativeSQLiteDatabaseFile(ctx, "Locate VPro SQLite Project Database")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(path), nil
}

// ResetToSample backs up the existing config.yml to config.backup-<timestamp>.yml,
// writes canonical Sample defaults, and activates the live application runtime.
func (s *StartupService) ResetToSample(ctx context.Context) (StartupState, error) {
	if ctx != nil {
		if err := ctx.Err(); err != nil {
			return StartupState{}, err
		}
	}
	if s == nil {
		return StartupState{}, errors.New("startup service is unavailable")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.State.Ready {
		return s.State, nil
	}
	configPath := strings.TrimSpace(s.State.ConfigPath)
	if configPath == "" {
		return StartupState{}, errors.New("startup configuration path is unavailable")
	}
	priorBytes, priorReadErr := os.ReadFile(configPath)
	hadPrior := priorReadErr == nil

	backupPath, err := vprocore.BackupDesktopConfigFile(configPath, s.now())
	if err != nil {
		return StartupState{}, err
	}

	defaults, err := vprocore.DecodeConfig(vprocore.DesktopDefaults)
	if err != nil {
		return StartupState{}, err
	}
	defaults["Desktop"] = map[string]any{
		"SchemaVersion": 1,
		"LegacyImports": vprocore.StampLegacyImportHashes(s.DataDir, filepath.Dir(configPath)),
	}
	if err := vprocore.ValidateDesktopConfig(defaults); err != nil {
		return StartupState{}, err
	}
	encoded, err := yaml.Marshal(defaults)
	if err != nil {
		return StartupState{}, err
	}
	if err := vprocore.WriteDesktopConfigAtomically(configPath, encoded); err != nil {
		return StartupState{}, fmt.Errorf("write Sample recovery config.yml: %w", err)
	}

	if s.Activate != nil {
		activated, actErr := s.Activate()
		if actErr != nil {
			if hadPrior {
				_ = vprocore.WriteDesktopConfigAtomically(configPath, priorBytes)
			}
			return StartupState{}, fmt.Errorf("activate Sample project: %w", actErr)
		}
		activated.BackupPath = backupPath
		s.State = WithBuildMetadata(activated)
		return s.State, nil
	}

	s.State = WithBuildMetadata(StartupState{
		Ready:          true,
		ConfigPath:     configPath,
		ReleaseChannel: vprocore.ReleaseChannelStable,
		BackupPath:     backupPath,
	})
	return s.State, nil
}

// RecoverWithPaths validates the relocated SQLite project path, backs up config.yml
// to config.backup-<timestamp>.yml, updates missing paths cleanly, and activates the runtime.
func (s *StartupService) RecoverWithPaths(ctx context.Context, req StartupRecoveryRequest) (StartupState, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return StartupState{}, err
	}
	if s == nil {
		return StartupState{}, errors.New("startup service is unavailable")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.State.Ready {
		return s.State, nil
	}
	configPath := strings.TrimSpace(s.State.ConfigPath)
	if configPath == "" {
		return StartupState{}, errors.New("startup configuration path is unavailable")
	}

	rawProjPath := strings.TrimSpace(req.ProjectPath)
	if rawProjPath == "" {
		return StartupState{}, errors.New("select or enter an existing SQLite project database (.db) path")
	}
	absProjPath, err := filepath.Abs(rawProjPath)
	if err != nil {
		return StartupState{}, fmt.Errorf("resolve project database path: %w", err)
	}
	resolvedProjPath, err := vprocore.ExistingDatabasePath(absProjPath)
	if err != nil {
		return StartupState{}, fmt.Errorf("project database unavailable: %w", err)
	}
	inspected, err := vprocore.InspectFileContext(ctx, resolvedProjPath)
	if err != nil {
		return StartupState{}, fmt.Errorf("inspect project database: %w", err)
	}
	var compatible []vprocore.ProjectInfo
	for _, p := range inspected {
		if p.Compatible {
			compatible = append(compatible, p)
		}
	}
	if len(compatible) == 0 {
		return StartupState{}, fmt.Errorf("no compatible VPro project tables were found in %s", resolvedProjPath)
	}

	priorBytes, priorReadErr := os.ReadFile(configPath)
	hadPrior := priorReadErr == nil

	var values vprocore.ConfigValues
	if hadPrior {
		if decoded, decErr := vprocore.DecodeConfig(priorBytes); decErr == nil {
			values = decoded
		}
	}
	if values == nil {
		defaults, defErr := vprocore.DecodeConfig(vprocore.DesktopDefaults)
		if defErr != nil {
			return StartupState{}, defErr
		}
		values = defaults
	}
	vprocore.NormalizeLegacyConfigScalars(values)

	stampedImports := vprocore.StampLegacyImportHashes(s.DataDir, filepath.Dir(configPath))
	if _, ok := values["Desktop"].(map[string]any); !ok {
		values["Desktop"] = map[string]any{
			"SchemaVersion": 1,
			"LegacyImports": stampedImports,
		}
	} else {
		desktop := values["Desktop"].(map[string]any)
		desktop["SchemaVersion"] = 1
		desktop["LegacyImports"] = stampedImports
		// Drop invalid/unreachable custom DatabasePaths so standard family databases can open cleanly
		if rawDBPaths, hasDBPaths := desktop["DatabasePaths"].(map[string]any); hasDBPaths {
			for role, v := range rawDBPaths {
				pStr, ok := v.(string)
				if !ok || !filepath.IsAbs(pStr) {
					delete(rawDBPaths, role)
					continue
				}
				if info, stErr := os.Stat(pStr); stErr != nil || !info.Mode().IsRegular() {
					delete(rawDBPaths, role)
				}
			}
			if len(rawDBPaths) == 0 {
				delete(desktop, "DatabasePaths")
			}
		}
	}

	defaults, err := vprocore.DecodeConfig(vprocore.DesktopDefaults)
	if err != nil {
		return StartupState{}, err
	}
	for sec, defVal := range defaults {
		if _, exists := values[sec]; !exists {
			values[sec] = defVal
			continue
		}
		if defMap, isMap := defVal.(map[string]any); isMap {
			if curMap, ok := values[sec].(map[string]any); ok {
				for k, v := range defMap {
					if _, exists := curMap[k]; !exists {
						curMap[k] = v
					}
				}
			} else {
				values[sec] = defMap
			}
		}
	}

	current := values["Current"].(map[string]any)
	previousProject, _ := current["CurrProject"].(string)
	requestedName := strings.TrimSpace(req.ProjectName)
	chosenProject := ""
	if requestedName != "" {
		for _, p := range compatible {
			if p.Name == requestedName {
				chosenProject = p.Name
				break
			}
		}
		if chosenProject == "" {
			return StartupState{}, fmt.Errorf("project %q was not found as a compatible VPro project in %s", requestedName, resolvedProjPath)
		}
	} else {
		for _, p := range compatible {
			if p.Name == previousProject {
				chosenProject = p.Name
				break
			}
		}
		if chosenProject == "" {
			if len(compatible) == 1 {
				chosenProject = compatible[0].Name
			} else {
				names := make([]string, 0, len(compatible))
				for _, p := range compatible {
					names = append(names, p.Name)
				}
				return StartupState{}, fmt.Errorf("database contains multiple VPro projects (%s); enter the target project name", strings.Join(names, ", "))
			}
		}
	}

	current["CurrProject"] = chosenProject
	current["ProjectPath"] = resolvedProjPath

	currSU, okSU := current["CurrPlotlist"].(string)
	if !okSU || strings.TrimSpace(currSU) == "" || !vprocore.ProjectNamePattern.MatchString(currSU) {
		currSU = "None"
		current["CurrPlotlist"] = "None"
	}
	if req.ClearSU || currSU == "None" {
		current["CurrPlotlist"] = "None"
		current["SUPath"] = ""
	} else if suTrimmed := strings.TrimSpace(req.SUPath); suTrimmed != "" {
		absSU, absErr := filepath.Abs(suTrimmed)
		if absErr != nil {
			return StartupState{}, fmt.Errorf("resolve Site Unit database path: %w", absErr)
		}
		resolvedSU, exErr := vprocore.ExistingDatabasePath(absSU)
		if exErr != nil {
			return StartupState{}, fmt.Errorf("Site Unit database unavailable at %s: %w", absSU, exErr)
		}
		current["SUPath"] = resolvedSU
	} else {
		current["SUPath"] = ""
	}

	currHier, okHier := current["CurrHierarchy"].(string)
	if !okHier || strings.TrimSpace(currHier) == "" || !vprocore.ProjectNamePattern.MatchString(currHier) {
		currHier = "None"
		current["CurrHierarchy"] = "None"
	}
	if req.ClearHierarchy || currHier == "None" {
		current["CurrHierarchy"] = "None"
		current["HierarchyPath"] = ""
	} else if hierTrimmed := strings.TrimSpace(req.HierarchyPath); hierTrimmed != "" {
		absHier, absErr := filepath.Abs(hierTrimmed)
		if absErr != nil {
			return StartupState{}, fmt.Errorf("resolve Hierarchy database path: %w", absErr)
		}
		resolvedHier, exErr := vprocore.ExistingDatabasePath(absHier)
		if exErr != nil {
			return StartupState{}, fmt.Errorf("Hierarchy database unavailable at %s: %w", absHier, exErr)
		}
		current["HierarchyPath"] = resolvedHier
	} else {
		current["HierarchyPath"] = ""
	}

	// Clear unreachable explicit ProfilePath so a missing external profile does not block recovery
	if rawProfPath, hasProfPath := current["ProfilePath"]; hasProfPath {
		if profPath, ok := rawProfPath.(string); !ok {
			delete(current, "ProfilePath")
		} else if strings.TrimSpace(profPath) != "" {
			if info, stErr := os.Stat(profPath); stErr != nil || !info.Mode().IsRegular() {
				delete(current, "ProfilePath")
				current["CurrVegProfile"] = chosenProject
			}
		}
	}
	if currProf, ok := current["CurrVegProfile"].(string); !ok || strings.TrimSpace(currProf) == "" || !utf8.ValidString(currProf) {
		current["CurrVegProfile"] = chosenProject
	} else if previousProject != "" && currProf == previousProject && chosenProject != previousProject {
		if profPath, _ := current["ProfilePath"].(string); strings.TrimSpace(profPath) == "" {
			current["CurrVegProfile"] = chosenProject
		}
	}

	// Repair any remaining out-of-range/corrupt required scalars after backing up priorBytes
	if _, err := vprocore.ConfigInt(values, "Current", "CoordMethod", 1, 3); err != nil {
		current["CoordMethod"] = 1
	}
	if _, err := vprocore.ConfigInt(values, "Current", "AssignedSuSource", 1, 3); err != nil {
		current["AssignedSuSource"] = 1
	}
	if auditMap, ok := values["Audit"].(map[string]any); !ok {
		values["Audit"] = map[string]any{"AuditStrength": 3}
	} else if _, err := vprocore.ConfigInt(values, "Audit", "AuditStrength", 0, 3); err != nil {
		auditMap["AuditStrength"] = 3
	}

	if user, ok := current["User"].(string); !ok || strings.TrimSpace(user) == "" || !utf8.ValidString(user) {
		current["User"] = "Admin"
	}
	if ch, hasCh := values["release_channel"]; hasCh {
		if chStr, ok := ch.(string); !ok || (chStr != vprocore.ReleaseChannelStable && chStr != vprocore.ReleaseChannelExperimental) {
			values["release_channel"] = vprocore.ReleaseChannelStable
		}
	}

	if err := vprocore.ValidateDesktopConfig(values); err != nil {
		return StartupState{}, errors.New(HumanizeStartupMessage(err.Error()))
	}
	encoded, err := yaml.Marshal(values)
	if err != nil {
		return StartupState{}, err
	}

	backupPath, err := vprocore.BackupDesktopConfigFile(configPath, s.now())
	if err != nil {
		return StartupState{}, err
	}
	if err := vprocore.WriteDesktopConfigAtomically(configPath, encoded); err != nil {
		return StartupState{}, fmt.Errorf("write recovered config.yml: %w", err)
	}

	if s.Activate != nil {
		activated, actErr := s.Activate()
		if actErr != nil {
			if hadPrior {
				_ = vprocore.WriteDesktopConfigAtomically(configPath, priorBytes)
			}
			return StartupState{}, errors.New(HumanizeStartupMessage(actErr.Error()))
		}
		activated.BackupPath = backupPath
		s.State = WithBuildMetadata(activated)
		return s.State, nil
	}

	next := StartupState{
		Ready:          true,
		ConfigPath:     configPath,
		ReleaseChannel: vprocore.ReleaseChannelStable,
		BackupPath:     backupPath,
	}
	PopulateRecoveryHints(&next)
	s.State = WithBuildMetadata(next)
	return s.State, nil
}
