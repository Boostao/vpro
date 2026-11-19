package lifecycle

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"slices"
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

const sqliteHeaderMagic = "SQLite format 3\x00"

type supportDatabaseSpec struct {
	Role           string
	Description    string
	RequiredTables []string
	RequiredCols   map[string][]string
}

var supportDatabaseSpecs = []supportDatabaseSpec{
	{
		Role:           "VPro64",
		Description:    "built-in table templates",
		RequiredTables: []string{"USysEnvTable", "USysVegTable", "USysSuTable", "USysHierarchyTable"},
	},
	{
		Role:        "VLists",
		Description: "provincial plant taxonomy and BEC reference lists",
		RequiredTables: []string{
			"USysAllSpecs", "USysTableOfLists", "MasterSiteUnitList", "USysMetadataTemplates",
			"USysZoneList", "USysMasterAudit", "USysSiteSeriesNames", "USysSppAttributes",
			"USysSppAttributeFieldList", "USysSppAttributeDescription",
		},
		RequiredCols: map[string][]string{
			"USysAllSpecs": {"EnglishName", "CombinedEnglishName"},
		},
	},
	{
		Role:           "VUser",
		Description:    "personal species and site unit lists",
		RequiredTables: []string{"USysUserSpp", "UserSiteUnitList", "USysSiteUnitAll", "USysPrefs"},
	},
	{
		Role:           "VMetaData",
		Description:    "project metadata codes",
		RequiredTables: []string{"ProjectMetadata", "ProjectMetaDataCodes"},
	},
	{
		Role:           "VMessageBoard",
		Description:    "workspace message board",
		RequiredTables: []string{"tblMessageBoard", "tblMessageList"},
	},
	{
		Role:           "VPics",
		Description:    "plot picture catalogue",
		RequiredTables: []string{"tblVPics"},
	},
}

func findSupportDatabaseSpec(role string) (supportDatabaseSpec, bool) {
	trimmed := strings.TrimSpace(strings.TrimSuffix(strings.TrimSuffix(role, ".db"), ".DB"))
	for _, spec := range supportDatabaseSpecs {
		if strings.EqualFold(trimmed, spec.Role) {
			return spec, true
		}
	}
	return supportDatabaseSpec{}, false
}

type supportDatabaseIssue struct {
	Spec   supportDatabaseSpec
	Path   string
	Reason string
}

type supportDatabaseBackup struct {
	Role         string
	OriginalPath string
	BackupPath   string
}

func describeSupportDatabaseFailureReason(err error) string {
	if err == nil {
		return ""
	}
	lower := strings.ToLower(err.Error())
	switch {
	case strings.Contains(lower, "empty (0 bytes)"):
		return "the file is empty (0 bytes)"
	case strings.Contains(lower, "not a database"):
		return "the file is not a readable VPro database"
	case strings.Contains(lower, "malformed") || strings.Contains(lower, "corrupt") || strings.Contains(lower, "integrity check"):
		return "the database file is damaged"
	case strings.Contains(lower, "missing a required physical table") ||
		strings.Contains(lower, "missing required column") ||
		strings.Contains(lower, "_table_metadata"):
		return "required VPro support tables are missing or incomplete"
	case strings.Contains(lower, "directory"):
		return "a folder was found instead of a database file"
	case strings.Contains(lower, "no such file") || strings.Contains(lower, "not found") || strings.Contains(lower, "cannot find"):
		return "the file was not found"
	default:
		return "the file could not be read"
	}
}

func inspectSupportDatabaseFile(ctx context.Context, spec supportDatabaseSpec, path string) (absent bool, err error) {
	if ctx == nil {
		ctx = context.Background()
	}
	linfo, lerr := os.Lstat(path)
	if errors.Is(lerr, os.ErrNotExist) {
		return true, nil
	}
	if lerr != nil {
		return false, lerr
	}
	if linfo.IsDir() {
		return false, errors.New("path is a directory instead of a database file")
	}
	info, statErr := os.Stat(path)
	if statErr != nil {
		return false, fmt.Errorf("file cannot be accessed: %w", statErr)
	}
	if !info.Mode().IsRegular() {
		return false, errors.New("path is not a regular file")
	}
	if info.Size() == 0 {
		return false, errors.New("file is empty (0 bytes)")
	}
	f, openErr := os.Open(path)
	if openErr != nil {
		return false, openErr
	}
	var header [16]byte
	_, readErr := io.ReadFull(f, header[:])
	_ = f.Close()
	if readErr != nil || string(header[:]) != sqliteHeaderMagic {
		return false, errors.New("file is not a database")
	}

	db, dbErr := sqlutil.OpenReadOnlyContext(ctx, path)
	if dbErr != nil {
		return false, dbErr
	}
	defer func() { _ = db.Close() }()

	checkRows, qErr := db.QueryContext(ctx, "PRAGMA quick_check(1);")
	if qErr != nil {
		return false, qErr
	}
	defer checkRows.Close()
	var checkResults []string
	for checkRows.Next() {
		var line string
		if sErr := checkRows.Scan(&line); sErr != nil {
			return false, sErr
		}
		checkResults = append(checkResults, strings.TrimSpace(line))
	}
	if rErr := checkRows.Err(); rErr != nil {
		return false, rErr
	}
	if len(checkResults) == 0 {
		return false, errors.New("integrity check returned no result")
	}
	for _, res := range checkResults {
		if !strings.EqualFold(res, "ok") {
			return false, fmt.Errorf("integrity check failed: %s", res)
		}
	}

	var hasMeta bool
	if mErr := db.QueryRowContext(ctx, "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='_table_metadata')").Scan(&hasMeta); mErr != nil {
		return false, mErr
	}
	if hasMeta {
		metaRows, mQueryErr := db.QueryContext(ctx, `SELECT * FROM "_table_metadata"`)
		if mQueryErr != nil {
			return false, mQueryErr
		}
		defer metaRows.Close()
		metaCols, colErr := metaRows.Columns()
		if colErr != nil {
			return false, colErr
		}
		if !slices.Contains(metaCols, "table_name") || !slices.Contains(metaCols, "description") {
			return false, errors.New("_table_metadata must contain table_name and description")
		}
		vals := make([]any, len(metaCols))
		ptrs := make([]any, len(metaCols))
		for i := range vals {
			ptrs[i] = &vals[i]
		}
		for metaRows.Next() {
			if sErr := metaRows.Scan(ptrs...); sErr != nil {
				return false, sErr
			}
		}
		if rErr := metaRows.Err(); rErr != nil {
			return false, rErr
		}
	}

	for _, tbl := range spec.RequiredTables {
		var exists bool
		if tErr := db.QueryRowContext(ctx, "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name=?)", tbl).Scan(&exists); tErr != nil {
			return false, tErr
		}
		if !exists {
			return false, fmt.Errorf("%s.%s is missing a required physical table", spec.Role, tbl)
		}
	}

	for tbl, reqCols := range spec.RequiredCols {
		colRows, cErr := db.QueryContext(ctx, `PRAGMA table_info("`+strings.ReplaceAll(tbl, `"`, `""`)+`")`)
		if cErr != nil {
			return false, cErr
		}
		var haveCols []string
		if rErr := func() error {
			defer colRows.Close()
			for colRows.Next() {
				var cid, notNull, pk int
				var cName, cType string
				var dflt sql.NullString
				if sErr := colRows.Scan(&cid, &cName, &cType, &notNull, &dflt, &pk); sErr != nil {

					return sErr
				}
				haveCols = append(haveCols, cName)
			}
			return colRows.Err()
		}(); rErr != nil {

			return false, rErr
		}
		for _, wantCol := range reqCols {
			if !slices.Contains(haveCols, wantCol) {
				return false, fmt.Errorf("%s.%s is missing required column %s", spec.Role, tbl, wantCol)
			}
		}
	}

	return false, nil
}

func readConfiguredSupportDBPaths(configPath string) map[string]string {
	if strings.TrimSpace(configPath) == "" {
		return nil
	}
	raw, err := os.ReadFile(configPath)
	if err != nil {
		return nil
	}
	values, err := vprocore.DecodeConfig(raw)
	if err != nil {
		return nil
	}
	desktop, ok := values["Desktop"].(map[string]any)
	if !ok {
		return nil
	}
	rawPaths, ok := desktop["DatabasePaths"].(map[string]any)
	if !ok {
		return nil
	}
	out := make(map[string]string, len(rawPaths))
	for role, val := range rawPaths {
		if s, ok := val.(string); ok && strings.TrimSpace(s) != "" {
			out[role] = strings.TrimSpace(s)
		}
	}
	return out
}

func reanchorSupportCandidate(rawPath, dataDir string) (string, bool) {
	if strings.TrimSpace(dataDir) == "" {
		return rawPath, false
	}
	slashed := strings.ReplaceAll(rawPath, `\`, `/`)
	marker := "/" + vprocore.DatabaseFamilySubdir + "/"
	idx := strings.LastIndex(slashed, marker)
	if idx < 0 {
		return rawPath, false
	}
	tail := slashed[idx+len(marker):]
	if tail == "" || strings.Contains(tail, "/") || tail == "." || tail == ".." || !strings.EqualFold(filepath.Ext(tail), ".db") {
		return rawPath, false
	}
	cand := filepath.Join(dataDir, vprocore.DatabaseFamilySubdir, tail)
	if info, err := os.Stat(cand); err == nil && info.Mode().IsRegular() {
		return cand, true
	}
	return rawPath, false
}

func diagnoseSupportDatabases(ctx context.Context, dataDir, configPath string) []supportDatabaseIssue {
	customPaths := readConfiguredSupportDBPaths(configPath)
	var issues []supportDatabaseIssue
	for _, spec := range supportDatabaseSpecs {
		if customPath, hasCustom := customPaths[spec.Role]; hasCustom {
			effective := customPath
			if !filepath.IsAbs(customPath) {
				if anchored, ok := reanchorSupportCandidate(customPath, dataDir); ok {
					effective = anchored
				} else {
					issues = append(issues, supportDatabaseIssue{
						Spec:   spec,
						Path:   customPath,
						Reason: "the file was not found",
					})
					continue
				}
			} else if info, stErr := os.Stat(customPath); stErr != nil || !info.Mode().IsRegular() {
				if anchored, ok := reanchorSupportCandidate(customPath, dataDir); ok {
					effective = anchored
				} else {
					absent, inspErr := inspectSupportDatabaseFile(ctx, spec, customPath)
					if absent {
						issues = append(issues, supportDatabaseIssue{
							Spec:   spec,
							Path:   customPath,
							Reason: "the file was not found",
						})
					} else if inspErr != nil {
						issues = append(issues, supportDatabaseIssue{
							Spec:   spec,
							Path:   customPath,
							Reason: describeSupportDatabaseFailureReason(inspErr),
						})
					}
					continue
				}
			}
			if absent, inspErr := inspectSupportDatabaseFile(ctx, spec, effective); absent {
				issues = append(issues, supportDatabaseIssue{
					Spec:   spec,
					Path:   effective,
					Reason: "the file was not found",
				})
				continue
			} else if inspErr != nil {
				issues = append(issues, supportDatabaseIssue{
					Spec:   spec,
					Path:   effective,
					Reason: describeSupportDatabaseFailureReason(inspErr),
				})
				continue
			}
		}

		if strings.TrimSpace(dataDir) == "" {
			continue
		}
		canonPath := filepath.Join(dataDir, vprocore.DatabaseFamilySubdir, spec.Role+".db")
		absent, inspErr := inspectSupportDatabaseFile(ctx, spec, canonPath)
		if !absent && inspErr != nil {
			issues = append(issues, supportDatabaseIssue{
				Spec:   spec,
				Path:   canonPath,
				Reason: describeSupportDatabaseFailureReason(inspErr),
			})
		}
	}
	return issues
}

func formatSupportDatabaseIssuesDiagnostic(issues []supportDatabaseIssue) string {
	if len(issues) == 0 {
		return ""
	}
	if len(issues) == 1 {
		it := issues[0]
		return fmt.Sprintf(
			"Shared support database %s.db (%s) at %s could not be opened because %s. Your project files and saved settings were kept unchanged.",
			it.Spec.Role, it.Spec.Description, it.Path, it.Reason,
		)
	}
	parts := make([]string, 0, len(issues))
	for _, it := range issues {
		parts = append(parts, fmt.Sprintf("%s.db (%s) at %s (%s)", it.Spec.Role, it.Spec.Description, it.Path, it.Reason))
	}
	return fmt.Sprintf(
		"Shared support databases could not be opened: %s. Your project files and saved settings were kept unchanged.",
		strings.Join(parts, "; "),
	)
}

func mentionsSupportRoleFailure(msg string) bool {
	trimmed := strings.TrimSpace(msg)
	if trimmed == "" || strings.HasPrefix(trimmed, "Shared support database") {
		return true
	}
	for _, spec := range supportDatabaseSpecs {
		if strings.Contains(trimmed, "attach "+spec.Role+":") ||
			strings.Contains(trimmed, "read "+spec.Role+" table descriptions:") ||
			strings.Contains(trimmed, spec.Role+".") ||
			strings.Contains(trimmed, "DatabasePaths."+spec.Role) {
			return true
		}
	}
	return false
}

func copyNonEmptySidecarBackup(srcSidecar, dstSidecar string) error {
	info, err := os.Stat(srcSidecar)
	if errors.Is(err, os.ErrNotExist) || (err == nil && (!info.Mode().IsRegular() || info.Size() == 0)) {
		return nil
	}
	if err != nil {
		return err
	}
	raw, err := os.ReadFile(srcSidecar)
	if err != nil {
		return err
	}
	return os.WriteFile(dstSidecar, raw, 0o600)
}

func backupCorruptSupportDatabase(dbPath, role string, now time.Time) (string, error) {
	linfo, lerr := os.Lstat(dbPath)
	if errors.Is(lerr, os.ErrNotExist) {
		return "", nil
	}
	if lerr != nil {
		return "", lerr
	}
	dir := filepath.Dir(dbPath)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	stamp := now.UTC().Format("20060102-150405")

	if linfo.IsDir() {
		for attempt := 0; attempt < 1000; attempt++ {
			suffix := ""
			if attempt > 0 {
				suffix = fmt.Sprintf("-%d", attempt)
			}
			candidate := filepath.Join(dir, fmt.Sprintf("%s.corrupt-%s%s.dir", role, stamp, suffix))
			if _, stErr := os.Lstat(candidate); errors.Is(stErr, os.ErrNotExist) {
				if rErr := os.Rename(dbPath, candidate); rErr != nil {
					return "", rErr
				}
				return candidate, nil
			}
		}
		return "", fmt.Errorf("could not allocate unique backup folder name for %s.db", role)
	}

	if linfo.Mode()&os.ModeSymlink != 0 {
		if _, stErr := os.Stat(dbPath); stErr != nil {
			target, _ := os.Readlink(dbPath)
			for attempt := 0; attempt < 1000; attempt++ {
				suffix := ""
				if attempt > 0 {
					suffix = fmt.Sprintf("-%d", attempt)
				}
				candidate := filepath.Join(dir, fmt.Sprintf("%s.corrupt-%s%s.symlink.txt", role, stamp, suffix))
				f, cErr := os.OpenFile(candidate, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
				if errors.Is(cErr, os.ErrExist) {
					continue
				}
				if cErr != nil {
					return "", cErr
				}
				_, _ = f.WriteString(target + "\n")
				_ = f.Sync()
				_ = f.Close()
				_ = os.Remove(dbPath)
				return candidate, nil
			}
			return "", fmt.Errorf("could not allocate unique backup symlink note for %s.db", role)
		}
	}

	raw, err := os.ReadFile(dbPath)
	if err != nil {
		return "", fmt.Errorf("read %s.db for backup: %w", role, err)
	}
	stage, err := os.CreateTemp(dir, ".support-corrupt-backup-*.db")
	if err != nil {
		return "", err
	}
	stageName := stage.Name()
	defer os.Remove(stageName)
	if err := stage.Chmod(0o600); err != nil {
		_ = stage.Close()
		return "", err
	}
	if _, err := stage.Write(raw); err != nil {
		_ = stage.Close()
		return "", err
	}
	if err := stage.Sync(); err != nil {
		_ = stage.Close()
		return "", err
	}
	if err := stage.Close(); err != nil {
		return "", err
	}

	for attempt := 0; attempt < 1000; attempt++ {
		suffix := ""
		if attempt > 0 {
			suffix = fmt.Sprintf("-%d", attempt)
		}
		candidate := filepath.Join(dir, fmt.Sprintf("%s.corrupt-%s%s.db", role, stamp, suffix))
		linkErr := sqlutil.LinkOrCreateExclusive(stageName, candidate)
		if linkErr == nil {
			_ = copyNonEmptySidecarBackup(dbPath+"-wal", candidate+"-wal")
			_ = copyNonEmptySidecarBackup(dbPath+"-journal", candidate+"-journal")
			_ = os.Chmod(dbPath, 0o600)
			if rmErr := sqlutil.RemoveSQLiteWithSidecars(dbPath); rmErr != nil {
				return "", fmt.Errorf("remove unreadable %s.db after saving backup %s: %w", role, candidate, rmErr)
			}
			return candidate, nil
		}
		if errors.Is(linkErr, os.ErrExist) {
			continue
		}
		return "", fmt.Errorf("write %s.db backup %q: %w", role, candidate, linkErr)
	}
	return "", fmt.Errorf("could not allocate unique backup filename for %s.db", role)
}

func repairWorkspaceSupportDatabases(ctx context.Context, dataDir string, now time.Time) ([]supportDatabaseBackup, error) {
	if strings.TrimSpace(dataDir) == "" {
		return nil, nil
	}
	absRoot, err := filepath.Abs(dataDir)
	if err != nil {
		return nil, err
	}
	familyDir := filepath.Join(absRoot, vprocore.DatabaseFamilySubdir)
	var backups []supportDatabaseBackup
	for _, spec := range supportDatabaseSpecs {
		dbPath := filepath.Join(familyDir, spec.Role+".db")
		absent, inspErr := inspectSupportDatabaseFile(ctx, spec, dbPath)
		if absent || inspErr == nil {
			continue
		}
		backupPath, bErr := backupCorruptSupportDatabase(dbPath, spec.Role, now)
		if bErr != nil {
			return backups, fmt.Errorf("back up unreadable %s.db: %w", spec.Role, bErr)
		}
		if backupPath != "" {
			backups = append(backups, supportDatabaseBackup{
				Role:         spec.Role,
				OriginalPath: dbPath,
				BackupPath:   backupPath,
			})
		}
	}
	if len(backups) == 0 {
		return nil, nil
	}
	if _, err := vprocore.InstallDatabaseFamily(absRoot); err != nil {
		return backups, fmt.Errorf("restore clean support databases: %w", err)
	}
	for _, item := range backups {
		spec, ok := findSupportDatabaseSpec(item.Role)
		if !ok {
			continue
		}
		if absent, vErr := inspectSupportDatabaseFile(ctx, spec, item.OriginalPath); absent || vErr != nil {
			if absent {
				return backups, fmt.Errorf("restored %s.db was not created at %s", item.Role, item.OriginalPath)
			}
			return backups, fmt.Errorf("verify restored %s.db: %w", item.Role, vErr)
		}
	}
	return backups, nil
}

func formatSupportDatabaseBackupSummary(backups []supportDatabaseBackup) string {
	if len(backups) == 0 {
		return ""
	}
	if len(backups) == 1 {
		b := backups[0]
		return fmt.Sprintf("Unreadable %s.db was backed up to %s and replaced with a clean %s.db.", b.Role, b.BackupPath, b.Role)
	}
	parts := make([]string, 0, len(backups))
	for _, b := range backups {
		parts = append(parts, fmt.Sprintf("%s.db -> %s", b.Role, b.BackupPath))
	}
	return fmt.Sprintf("Unreadable support databases were backed up (%s) and replaced with clean built-in copies.", strings.Join(parts, "; "))
}

func enrichRecoveryDiagnostics(state *StartupState, dataDir string) {
	if state == nil || state.Ready {
		return
	}
	state.Message = HumanizeStartupMessage(state.Message)
	if strings.TrimSpace(dataDir) != "" || strings.TrimSpace(state.ConfigPath) != "" {
		if issues := diagnoseSupportDatabases(context.Background(), dataDir, state.ConfigPath); len(issues) > 0 {
			supportDiag := formatSupportDatabaseIssuesDiagnostic(issues)
			if mentionsSupportRoleFailure(state.Message) {
				state.Message = supportDiag
			} else {
				state.Message = appendDiagnosticSentence(state.Message, supportDiag)
			}
		}
	}
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
	priorBytes, priorReadErr := os.ReadFile(configPath)
	hadPrior := priorReadErr == nil
	opTime := s.now()

	backupPath, err := vprocore.BackupDesktopConfigFile(configPath, opTime)
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

	supportBackups, repErr := repairWorkspaceSupportDatabases(ctx, s.DataDir, opTime)
	if repErr != nil {
		if hadPrior {
			_ = vprocore.WriteDesktopConfigAtomically(configPath, priorBytes)
		}
		return StartupState{}, errors.New(HumanizeStartupMessage(repErr.Error()))
	}
	supportMsg := formatSupportDatabaseBackupSummary(supportBackups)
	if backupPath == "" && len(supportBackups) > 0 {
		backupPath = supportBackups[0].BackupPath
	}

	if s.Activate != nil {
		activated, actErr := s.Activate()
		if actErr != nil {
			if hadPrior {
				_ = vprocore.WriteDesktopConfigAtomically(configPath, priorBytes)
			}
			return StartupState{}, fmt.Errorf("activate Sample project: %s", HumanizeStartupMessage(actErr.Error()))
		}
		activated.BackupPath = backupPath
		if supportMsg != "" {
			activated.Message = supportMsg
		}
		s.State = WithBuildMetadata(activated)
		return s.State, nil
	}

	s.State = WithBuildMetadata(StartupState{
		Ready:          true,
		Message:        supportMsg,
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
		// Drop invalid, unreachable, or corrupt custom DatabasePaths so standard family databases can open cleanly
		if rawDBPaths, hasDBPaths := desktop["DatabasePaths"].(map[string]any); hasDBPaths {
			for role, v := range rawDBPaths {
				pStr, ok := v.(string)
				spec, knownRole := findSupportDatabaseSpec(role)
				if !ok || !filepath.IsAbs(pStr) || !knownRole {
					delete(rawDBPaths, role)
					continue
				}
				if info, stErr := os.Stat(pStr); stErr != nil || !info.Mode().IsRegular() {
					delete(rawDBPaths, role)
					continue
				}
				if absent, inspErr := inspectSupportDatabaseFile(ctx, spec, pStr); absent || inspErr != nil {
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

	opTime := s.now()
	backupPath, err := vprocore.BackupDesktopConfigFile(configPath, opTime)
	if err != nil {
		return StartupState{}, err
	}
	if err := vprocore.WriteDesktopConfigAtomically(configPath, encoded); err != nil {
		return StartupState{}, fmt.Errorf("write recovered config.yml: %w", err)
	}

	supportBackups, repErr := repairWorkspaceSupportDatabases(ctx, s.DataDir, opTime)
	if repErr != nil {
		if hadPrior {
			_ = vprocore.WriteDesktopConfigAtomically(configPath, priorBytes)
		}
		return StartupState{}, errors.New(HumanizeStartupMessage(repErr.Error()))
	}
	supportMsg := formatSupportDatabaseBackupSummary(supportBackups)
	if backupPath == "" && len(supportBackups) > 0 {
		backupPath = supportBackups[0].BackupPath
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
		if supportMsg != "" {
			activated.Message = supportMsg
		}
		s.State = WithBuildMetadata(activated)
		return s.State, nil
	}

	next := StartupState{
		Ready:          true,
		Message:        supportMsg,
		ConfigPath:     configPath,
		ReleaseChannel: vprocore.ReleaseChannelStable,
		BackupPath:     backupPath,
	}
	PopulateRecoveryHints(&next)
	s.State = WithBuildMetadata(next)
	return s.State, nil
}
